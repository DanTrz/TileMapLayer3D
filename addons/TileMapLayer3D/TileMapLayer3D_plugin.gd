# =============================================================================
# PURPOSE: Main plugin entry point for TileMapLayer3D editor plugin
# =============================================================================
# This is the central coordinator for the TileMapLayer3D plugin.
# It handles:
#   - Editor integration (dock panel, toolbar, input forwarding)
#   - Cursor and preview management
#   - Input event routing (mouse, keyboard, area selection)
#   - Signal connections between all subsystems
#   - Manual and Auto-tile mode coordination
#
# ARCHITECTURE:
#   - Delegates placement logic to TilePlacementManager
#   - Delegates autotile logic to AutotilePlacementExtension
#   - Uses TilesetPanel for UI (dock panel)
#   - Uses TileCursor3D and TilePreview3D for visual feedback
#
# INPUT FLOW:
#   _forward_3d_gui_input() → _handle_*() methods → placement_manager
# =============================================================================

@tool
class_name TileMapLayer3DPlugin
extends EditorPlugin

## Main plugin entry point for TileMapLayer3D

# =============================================================================
# SECTION: MEMBER VARIABLES
# =============================================================================

var tileset_panel: TilesetPanel = null
var tool_button: Button = null
var menu_button: MenuButton = null
var placement_manager: TilePlacementManager = null
var current_tile_map3d: TileMapLayer3D = null
var tile_cursor: TileCursor3D = null
var tile_preview: TilePreview3D = null
var is_active: bool = false

# Selection Manager - Single source of truth for tile selection state
var selection_manager: SelectionManager = null

# Autotile system (V5)
var _autotile_engine: AutotileEngine = null
var _autotile_extension: AutotilePlacementExtension = null
# NOTE: _autotile_mode_enabled REMOVED - now read from settings.tiling_mode via _is_autotile_mode()

# Global plugin settings (persists across editor sessions)
var plugin_settings: TilePlacerPluginSettings = null

# Auto-flip signal (emitted by GlobalPlaneDetector via update_from_camera)
signal auto_flip_requested(flip_state: bool)

# NOTE: Multi-tile selection state REMOVED - now read from settings.selected_tiles via _get_selected_tiles()
# The PlacementManager still maintains a runtime cache for fast painting

#  Input throttling to prevent excessive preview updates
var _last_preview_update_time: float = 0.0

var _last_preview_screen_pos: Vector2 = Vector2.INF  # Last screen position that triggered update
var _last_preview_grid_pos: Vector3 = Vector3.INF  # Last grid position that triggered update

#Variable to store local mouse position for key events
var _cached_local_mouse_pos: Vector2 = Vector2.ZERO

# Painting mode state (Phase 5)
var _is_painting: bool = false  # True when LMB held  and dragging
var _is_erasing: bool = false  # True when RMB held and dragging
var _last_painted_position: Vector3 = Vector3.INF  # Last painted grid position (INF = no paint yet)
var _last_paint_update_time: float = 0.0  # Time throttling for paint operations

# Area fill selection state (Shift+Drag fill/erase)
var area_fill_selector: AreaFillSelector3D = null  # Visual selection box
var _area_fill_operator: AreaFillOperator = null  # Handles area fill logic and state

# Tile count warning tracking
var _tile_count_warning_shown: bool = false  # True if 95% warning was already shown
var _last_tile_count: int = 0  # Track previous count to detect threshold crossings

# =============================================================================
# SECTION: HELPER GETTERS - Read from Settings (Single Source of Truth)
# =============================================================================
# These helpers ensure the plugin always reads state from the current node's
# TileMapLayerSettings resource, rather than maintaining duplicate state.
# This prevents bugs where plugin-level state corrupts all nodes.
# =============================================================================

## Returns true if autotile mode is active for current node
func _is_autotile_mode() -> bool:
	if current_tile_map3d and current_tile_map3d.settings:
		return current_tile_map3d.settings.tiling_mode == GlobalConstants.TILING_MODE_AUTOTILE
	return false

## Returns the selected tiles array (from SelectionManager)
func _get_selected_tiles() -> Array[Rect2]:
	if selection_manager:
		return selection_manager.get_tiles_readonly()
	return []

## Returns true if multi-tile selection is active (more than 1 tile selected)
func _has_multi_tile_selection() -> bool:
	if selection_manager:
		return selection_manager.has_multi_selection()
	return false

## Returns the anchor index for multi-tile selection
func _get_selection_anchor_index() -> int:
	if selection_manager:
		return selection_manager.get_anchor()
	return 0

## Sets tiling mode for current node (0=Manual, 1=Autotile)
func _set_tiling_mode(mode: int) -> void:
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.tiling_mode = mode

## Clears tile selection for current node
## Routes through SelectionManager which handles syncing to all locations
func _clear_selection() -> void:
	if selection_manager:
		selection_manager.clear()

## Invalidates preview to force refresh
func _invalidate_preview() -> void:
	if tile_preview:
		tile_preview.hide_preview()
		tile_preview._hide_all_preview_instances()
	_last_preview_grid_pos = Vector3.INF
	_last_preview_screen_pos = Vector2.INF

## Called when current node's settings change (from any source)
## Syncs plugin state from Settings (for changes made outside the plugin, like Inspector)
func _on_current_node_settings_changed() -> void:
	if not current_tile_map3d or not current_tile_map3d.settings:
		return

	var settings = current_tile_map3d.settings

	# Sync autotile extension enabled state
	if _autotile_extension:
		_autotile_extension.set_enabled(settings.tiling_mode == GlobalConstants.TILING_MODE_AUTOTILE)

	# If settings.selected_tiles changed externally (e.g., Inspector), sync to SelectionManager
	# This handles the case where user modifies selection via Inspector
	if selection_manager:
		var current_selection = selection_manager.get_tiles_readonly()
		if current_selection != settings.selected_tiles:
			# emit_signals: true triggers _on_selection_manager_changed() which syncs PlacementManager
			selection_manager.restore_from_settings(settings.selected_tiles, settings.selected_anchor_index, true)

# =============================================================================
# SECTION: LIFECYCLE
# =============================================================================
# Plugin initialization and cleanup methods.
# Called by Godot when the plugin is enabled/disabled.
# =============================================================================

func _enter_tree() -> void:
	print("TileMapLayer3D: Plugin enabled")

	# Load global plugin settings from EditorSettings
	plugin_settings = TilePlacerPluginSettings.new()
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	plugin_settings.load_from_editor_settings(editor_settings)
	#print("Plugin: Global settings loaded")

	# Load and instantiate tileset panel
	var panel_scene: PackedScene = load("uid://bvxqm8r7yjwqr")
	tileset_panel = panel_scene.instantiate() as TilesetPanel

	# Add to dock
	add_control_to_dock(DOCK_SLOT_LEFT_UL, tileset_panel)

	# Connect signals
	tileset_panel.tile_selected.connect(_on_tile_selected)
	tileset_panel.multi_tile_selected.connect(_on_multi_tile_selected)  # Phase 3
	tileset_panel.tileset_loaded.connect(_on_tileset_loaded)
	tileset_panel.orientation_changed.connect(_on_orientation_changed)
	tileset_panel.placement_mode_changed.connect(_on_placement_mode_changed)
	tileset_panel.show_plane_grids_changed.connect(_on_show_plane_grids_changed)
	tileset_panel.cursor_step_size_changed.connect(_on_cursor_step_size_changed)
	auto_flip_requested.connect(_on_auto_flip_requested)  # Auto-flip feature
	tileset_panel.grid_snap_size_changed.connect(_on_grid_snap_size_changed)
	tileset_panel.mesh_mode_selection_changed.connect(_on_mesh_mode_selection_changed)
	tileset_panel.grid_size_changed.connect(_on_grid_size_changed)
	tileset_panel.texture_filter_changed.connect(_on_texture_filter_changed)
	tileset_panel.create_collision_requested.connect(_on_create_collision_requested)
	tileset_panel._bake_mesh_requested.connect(_on_bake_mesh_requested)

	tileset_panel.clear_tiles_requested.connect(_clear_all_tiles)
	tileset_panel.show_debug_info_requested.connect(_on_show_debug_info_requested)

	# Autotile signals
	tileset_panel.tiling_mode_changed.connect(_on_tiling_mode_changed)
	tileset_panel.autotile_tileset_changed.connect(_on_autotile_tileset_changed)
	tileset_panel.autotile_terrain_selected.connect(_on_autotile_terrain_selected)
	tileset_panel.autotile_data_changed.connect(_on_autotile_data_changed)
	tileset_panel.clear_autotile_requested.connect(_on_clear_autotile_requested)

	# Create tool toggle button
	tool_button = Button.new()
	tool_button.text = "Enable Tiling"
	tool_button.tooltip_text = "Toggle 2.5D tile placement tool (select a TileMapLayer3D node first)"
	tool_button.toggle_mode = true
	tool_button.toggled.connect(_on_tool_toggled)

	# Add to 3D editor toolbar
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, tool_button)

	# Create placement manager
	placement_manager = TilePlacementManager.new()

	# Create selection manager (single source of truth for tile selection)
	selection_manager = SelectionManager.new()
	selection_manager.selection_changed.connect(_on_selection_manager_changed)
	selection_manager.selection_cleared.connect(_on_selection_manager_cleared)

	#print("TileMapLayer3D: Dock panel added")

func _exit_tree() -> void:
	# Save global plugin settings to EditorSettings
	if plugin_settings:
		var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
		plugin_settings.save_to_editor_settings(editor_settings)
		#print("Plugin: Global settings saved")

	if tileset_panel:
		remove_control_from_docks(tileset_panel)
		tileset_panel.queue_free()

	if tool_button:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, tool_button)
		tool_button.queue_free()

	if placement_manager:
		placement_manager = null

	# Clean up autotile resources
	_autotile_engine = null
	_autotile_extension = null

	print("TileMapLayer3D: Plugin disabled")

# =============================================================================
# SECTION: EDITOR INTEGRATION
# =============================================================================
# Methods called by Godot's editor to determine which nodes this plugin handles
# and to set up editing context when a node is selected.
# =============================================================================

func _handles(object: Object) -> bool:
	# Check if object is a TileMapLayer3D by checking the script
	if object is Node3D:
		var script: Script = object.get_script()
		if script:
			# Check if it's our TileMapLayer3D script
			var script_path: String = script.resource_path
			if script_path.ends_with("tile_model_3d.gd"):
				return true
		# Also check metadata for runtime-created nodes
		if object.has_meta("_godot25d_tile_model"):
			return true
	return false

##Called when a TileMapLayer3D is selected
func _edit(object: Object) -> void:
	# CRITICAL FIX: Clear multi-tile selection when ANY node selection changes
	# This prevents plugin-wide corruption where multi-selection from Node A
	# blocks autotile on Node B (and all other nodes until restart)
	_clear_selection()

	# Defensive state reset when switching nodes
	# Ensures painting/erasing/area-selection states don't persist across node switches
	_is_painting = false
	_is_erasing = false
	if _area_fill_operator:
		_area_fill_operator.reset_state()
	_invalidate_preview()

	# Disconnect from old node's settings BEFORE switching nodes
	if current_tile_map3d and current_tile_map3d.settings:
		GlobalUtil.safe_disconnect(current_tile_map3d.settings.changed, _on_current_node_settings_changed)

	if object is TileMapLayer3D:
		current_tile_map3d = object as TileMapLayer3D
		#print("DEBUG Plugin._edit: Node selected: ", current_tile_map3d.name)
		#print("DEBUG Plugin._edit: Has settings? ", current_tile_map3d.settings != null)

		# Ensure node has settings Resource
		if not current_tile_map3d.settings:
			# This is a NEW node (no settings saved to scene yet)
			# Create settings and apply global defaults
			#print("DEBUG Plugin._edit: Creating NEW settings with global defaults")
			current_tile_map3d.settings = TileMapLayerSettings.new()

			# Apply global plugin defaults for new nodes ONLY
			if plugin_settings:
				current_tile_map3d.settings.tile_size = plugin_settings.default_tile_size
				current_tile_map3d.settings.grid_size = plugin_settings.default_grid_size
				current_tile_map3d.settings.texture_filter_mode = plugin_settings.default_texture_filter
				current_tile_map3d.settings.enable_collision = plugin_settings.default_enable_collision
				current_tile_map3d.settings.alpha_threshold = plugin_settings.default_alpha_threshold

			#print("Plugin: Created default settings Resource for ", current_tile_map3d.name, " with global defaults (grid_size: ", current_tile_map3d.settings.grid_size, ")")
		else:
			# This is an EXISTING node (settings already saved to scene)
			# DO NOT apply global defaults - respect the saved settings!
			#print("DEBUG Plugin._edit: Using EXISTING settings (grid_size: ", current_tile_map3d.settings.grid_size, ")")
			#print("Plugin: Loaded existing settings for ", current_tile_map3d.name, " (grid_size: ", current_tile_map3d.settings.grid_size, ")")
			pass

		# Update TilesetPanel to show this node's settings
		tileset_panel.set_active_node(current_tile_map3d)

		# Connect to node's settings.changed for sync (single source of truth)
		GlobalUtil.safe_connect(current_tile_map3d.settings.changed, _on_current_node_settings_changed)

		# Update placement manager with node reference and settings
		placement_manager.tile_map_layer3d_root = current_tile_map3d
		placement_manager.grid_size = current_tile_map3d.settings.grid_size

		# Sync tileset texture from settings to placement manager
		if current_tile_map3d.settings.tileset_texture:
			placement_manager.tileset_texture = current_tile_map3d.settings.tileset_texture
			placement_manager.texture_filter_mode = current_tile_map3d.settings.texture_filter_mode

		# Restore rotation and flip state from settings
		placement_manager.current_mesh_rotation = current_tile_map3d.settings.current_mesh_rotation
		placement_manager.is_current_face_flipped = current_tile_map3d.settings.is_face_flipped

		# Restore selection from settings to SelectionManager
		# emit_signals: true triggers _on_selection_manager_changed() which syncs PlacementManager
		if selection_manager and current_tile_map3d.settings.selected_tiles.size() > 0:
			selection_manager.restore_from_settings(
				current_tile_map3d.settings.selected_tiles,
				current_tile_map3d.settings.selected_anchor_index,
				true  # Emit signal to sync PlacementManager via signal handler
			)

		# Sync placement manager with existing tiles
		placement_manager.sync_from_tile_model()

		# Create or update cursor
		call_deferred("_setup_cursor")

		# Set up autotile extension with current node
		call_deferred("_setup_autotile_extension")

		#print("TileMapLayer3D selected: ", current_tile_map3d.name)
	else:
		current_tile_map3d = null
		tileset_panel.set_active_node(null)
		_cleanup_cursor()

# =============================================================================
# SECTION: CURSOR AND PREVIEW SETUP
# =============================================================================
# Methods for creating, configuring, and cleaning up the 3D cursor,
# tile preview, area fill selector, and autotile extension.
# =============================================================================

## Sets up the 3D cursor for the current tile model
func _setup_cursor() -> void:
	# Remove existing cursor if any
	_cleanup_cursor()

	# Also remove any cursors that were accidentally saved to the scene
	_remove_saved_cursors()

	# Create new cursor
	tile_cursor = TileCursor3D.new()
	tile_cursor.grid_size = current_tile_map3d.grid_size
	tile_cursor.name = "TileCursor3D"

	# Apply global settings to cursor
	if plugin_settings:
		tile_cursor.show_plane_grids = plugin_settings.show_plane_grids

	# Add to tile model (runtime-only, never set owner so it won't be saved)
	current_tile_map3d.add_child(tile_cursor)
	# DO NOT set owner - cursor should not persist in scene file

	# Create tile preview
	tile_preview = TilePreview3D.new()
	tile_preview.grid_size = current_tile_map3d.grid_size
	tile_preview.texture_filter_mode = placement_manager.texture_filter_mode
	tile_preview.tile_model = current_tile_map3d
	tile_preview.current_mesh_mode = current_tile_map3d.current_mesh_mode  # NEW: Set mesh mode
	tile_preview.name = "TilePreview3D"
	current_tile_map3d.add_child(tile_preview)
	tile_preview.hide_preview()

	# Create area fill selector (Shift+Drag selection box)
	area_fill_selector = AreaFillSelector3D.new()
	area_fill_selector.grid_size = current_tile_map3d.grid_size
	area_fill_selector.name = "AreaFillSelector3D"
	current_tile_map3d.add_child(area_fill_selector)
	# DO NOT set owner - selector should not persist in scene file

	# Create area fill operator (handles state and workflow)
	_area_fill_operator = AreaFillOperator.new()
	_area_fill_operator.setup(area_fill_selector, placement_manager, current_tile_map3d)
	_area_fill_operator.highlight_requested.connect(_on_area_fill_highlight_requested)
	_area_fill_operator.clear_highlights_requested.connect(_on_area_fill_clear_highlights)
	_area_fill_operator.out_of_bounds_warning.connect(_on_area_fill_out_of_bounds)

	# Connect to placement manager
	placement_manager.cursor_3d = tile_cursor

	#print("3D Cursor created at grid position: ", tile_cursor.grid_position)

## Removes any cursors that were accidentally saved to the scene
func _remove_saved_cursors() -> void:
	if not current_tile_map3d:
		return

	# Find and remove all TileCursor3D children
	for child in current_tile_map3d.get_children():
		if child is TileCursor3D:
			#print("Removing saved cursor: ", child.name)
			child.queue_free()

## Sets up the autotile extension for the current tile model
func _setup_autotile_extension() -> void:
	if not current_tile_map3d or not placement_manager:
		return

	# Create extension if not exists
	if not _autotile_extension:
		_autotile_extension = AutotilePlacementExtension.new()

	# Restore autotile settings from node settings
	if current_tile_map3d.settings:
		var settings: TileMapLayerSettings = current_tile_map3d.settings

		# Restore TileSet if saved
		if settings.autotile_tileset:
			_autotile_engine = AutotileEngine.new(settings.autotile_tileset)
			_autotile_extension.setup(_autotile_engine, placement_manager, current_tile_map3d)
			_autotile_extension.set_engine(_autotile_engine)

			# Restore terrain selection
			if settings.autotile_active_terrain >= 0:
				_autotile_extension.set_terrain(settings.autotile_active_terrain)

			# Update UI with restored TileSet
			if tileset_panel and tileset_panel.auto_tile_tab:
				tileset_panel.auto_tile_tab.set_tileset(settings.autotile_tileset)
				if settings.autotile_active_terrain >= 0:
					tileset_panel.auto_tile_tab.select_terrain(settings.autotile_active_terrain)

			# CRITICAL: Rebuild bitmask cache from loaded tiles for proper neighbor detection
			# Without this, loaded autotiles won't recognize new neighbors after scene reload
			var placement_data: Dictionary = placement_manager.get_placement_data()
			_autotile_engine.rebuild_bitmask_cache(placement_data)

			#print("Autotile: Restored TileSet and terrain from settings")
		else:
			# No saved TileSet, just set up empty extension
			_autotile_extension.setup(null, placement_manager, current_tile_map3d)

	_autotile_extension.set_enabled(_is_autotile_mode())


## Cleans up the cursor when deselecting
func _cleanup_cursor() -> void:
	if tile_cursor:
		if is_instance_valid(tile_cursor):
			tile_cursor.queue_free()
		tile_cursor = null
		placement_manager.cursor_3d = null

	if tile_preview:
		if is_instance_valid(tile_preview):
			tile_preview.queue_free()
		tile_preview = null

	if area_fill_selector:
		if is_instance_valid(area_fill_selector):
			area_fill_selector.queue_free()
		area_fill_selector = null

	if _area_fill_operator:
		_area_fill_operator = null

# =============================================================================
# SECTION: INPUT HANDLING
# =============================================================================
# Methods for processing editor input events (keyboard, mouse, drag).
# Routes input to appropriate handlers based on event type and current mode.
# =============================================================================

# Handle GUI Inputs in the editor
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_active or not current_tile_map3d:
		return AFTER_GUI_INPUT_PASS

	# 1. CAPTURE THE COORDINATES (Fixes Preview Disappearing)
	if event is InputEventMouse:
		_cached_local_mouse_pos = event.position

	# 2. HANDLE KEYS
	if event is InputEventKey and event.pressed:
		# First, try Mesh Rotations (Q, E, R, F, T)
		var result = _handle_mesh_rotations(event, camera)
		
		# If rotation logic handled it (STOP), return immediately.
		if result == AFTER_GUI_INPUT_STOP:
			return result
			
		# If rotation logic didn't handle it (PASS), CONTINUE to check WASD below.
		# (Do not return yet!)

		# Second, try Cursor Movement (W, A, S, D)
		var cursor_based_mode: bool = (placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR_PLANE or placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR)
		if cursor_based_mode and tile_cursor:
			return _handle_cursor3d_movement(event, camera)

	# 3. Handle Mouse Motion (Painting/Preview)
	if event is InputEventMouseMotion:
		_handle_mouse_painting_movement(event, camera)

	# 4. Handle Mouse Buttons (Clicking)
	if event is InputEventMouseButton:
		return _handle_mouse_button_press(event, camera)

	return AFTER_GUI_INPUT_PASS

##Handle all inputs for mesh rotation
func _handle_mesh_rotations(event: InputEvent, camera: Camera3D) -> int:
	if is_active:
		var needs_update: bool = false

		# Handle ESC first - always allow (for area selection cancel)
		if event.keycode == KEY_ESCAPE:
			if _area_fill_operator and _area_fill_operator.is_selecting:
				_area_fill_operator.cancel()
				#print("Area selection cancelled")
				return AFTER_GUI_INPUT_STOP
			return AFTER_GUI_INPUT_PASS

		# AUTOTILE MODE: Block rotation/tilt/flip keys (Q, E, R, T, F)
		# Autotile tiles are automatically oriented based on neighbors
		if _is_autotile_mode():
			return AFTER_GUI_INPUT_PASS

		# MANUAL MODE: Process rotation keys
		match event.keycode:
			KEY_Q:
				placement_manager.current_mesh_rotation = (placement_manager.current_mesh_rotation - 1) % 4
				if placement_manager.current_mesh_rotation < 0:
					placement_manager.current_mesh_rotation += 4
				#print("Rotation: ", placement_manager.current_mesh_rotation * 90)
				needs_update = true

			KEY_E:
				placement_manager.current_mesh_rotation = (placement_manager.current_mesh_rotation + 1) % 4
				#print("Rotation: ", placement_manager.current_mesh_rotation * 90)
				needs_update = true

			KEY_F:
				placement_manager.is_current_face_flipped = not placement_manager.is_current_face_flipped
				needs_update = true
				#var flip_state: String = "FLIPPED" if placement_manager.is_current_face_flipped else "NORMAL"
				#print("Face flip: ", flip_state)

			KEY_R:
				if event.shift_pressed:
					GlobalPlaneDetector.cycle_tilt_backward()
				else:
					GlobalPlaneDetector.cycle_tilt_forward()
				needs_update = true
				
				var should_be_flipped: bool = GlobalPlaneDetector.determine_rotation_flip_for_plane(GlobalPlaneDetector.current_plane_6d)

				placement_manager.is_current_face_flipped = should_be_flipped


			KEY_T:
				GlobalPlaneDetector.reset_to_flat()
				placement_manager.current_mesh_rotation = 0
				needs_update = true
				var default_flip: bool = GlobalPlaneDetector.determine_auto_flip_for_plane(GlobalPlaneDetector.current_plane_6d)
				placement_manager.is_current_face_flipped = default_flip

				#var flip_text: String = "flipped" if default_flip else "normal"
				#print("Reset: Orientation flat, rotation 0°, flip ", flip_text, " (default for current plane)")

		if needs_update:
			# Save rotation/flip state to settings for persistence
			if current_tile_map3d and current_tile_map3d.settings:
				
				current_tile_map3d.settings.current_mesh_rotation = placement_manager.current_mesh_rotation

				current_tile_map3d.settings.is_face_flipped = placement_manager.is_current_face_flipped

			#  Use the Cached Local Position so the Raycast hits the Grid
			# Passing 'true' as 3rd arg bypasses the movement optimization check
			if tile_preview:
				_update_preview(camera, _cached_local_mouse_pos, true)

			# Force Godot Editor to Redraw immediately
			update_overlays()

			return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS

##Handle keyboard input for cursor movement
func _handle_cursor3d_movement(event: InputEvent, camera: Camera3D) -> int:
	#Don't process WASD if a UI control has focus
	var focused_control: Control = get_editor_interface().get_base_control().get_viewport().gui_get_focus_owner()
	if focused_control and (focused_control is LineEdit or focused_control is SpinBox or focused_control is TextEdit):
		return AFTER_GUI_INPUT_PASS

	var shift_pressed: bool = event.shift_pressed
	var handled: bool = false
	var move_vector: Vector3 = Vector3.ZERO
	var basis: Basis = camera.global_transform.basis

	match event.keycode:
		KEY_W:
			if shift_pressed:
				move_vector = GlobalUtil._get_snapped_cardinal_vector(basis.y)
			else:
				move_vector = GlobalUtil._get_snapped_cardinal_vector(-basis.z)
			handled = true
		KEY_S:
			if shift_pressed:
				move_vector = GlobalUtil._get_snapped_cardinal_vector(-basis.y)
			else:
				move_vector = GlobalUtil._get_snapped_cardinal_vector(basis.z)
			handled = true
		KEY_A:
			move_vector = GlobalUtil._get_snapped_cardinal_vector(-basis.x)
			handled = true
		KEY_D:
			move_vector = GlobalUtil._get_snapped_cardinal_vector(basis.x)
			handled = true

	if handled:
		if move_vector.length_squared() > 0.0:
			tile_cursor.move_by(Vector3i(move_vector))
		
		tileset_panel.update_cursor_position(tile_cursor.grid_position)
		return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS

##Handle mouse motion for preview update and painting
func _handle_mouse_painting_movement(event: InputEvent, camera: Camera3D) -> void:
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var is_area_selecting: bool = _area_fill_operator and _area_fill_operator.is_selecting

	# AREA SELECTION: Update selection box during Shift+Drag
	if is_area_selecting:
		_area_fill_operator.update(camera, event.position)

	# PREVIEW: Optimized update with movement threshold + time throttling
	if not is_area_selecting:
		var quick_result: Dictionary = placement_manager.calculate_cursor_plane_placement(camera, event.position)

		if not quick_result.is_empty():
			var grid_pos: Vector3 = quick_result.grid_pos

			#  Check movement threshold before updating
			# This uses the optimization for mouse movement
			if _should_update_preview(event.position, grid_pos):
				if current_time - _last_preview_update_time >= GlobalConstants.PREVIEW_UPDATE_INTERVAL:
					_update_preview(camera, event.position, false) # False = Respect thresholds
					_last_preview_update_time = current_time
					_last_preview_screen_pos = event.position
					_last_preview_grid_pos = grid_pos

	# PAINTING: Continue painting while dragging (Phase 5)
	if (_is_painting or _is_erasing) and current_time - _last_paint_update_time >= GlobalConstants.PAINT_UPDATE_INTERVAL:
		_paint_tile_at_mouse(camera, event.position, _is_erasing)
		_last_paint_update_time = current_time

func _handle_mouse_button_press(event: InputEvent, camera: Camera3D) -> int:
	var is_area_selecting: bool = _area_fill_operator and _area_fill_operator.is_selecting

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.shift_pressed:
				if _area_fill_operator:
					_area_fill_operator.start(camera, event.position, false)
				return AFTER_GUI_INPUT_STOP

			_is_painting = true
			_is_erasing = false
			_last_painted_position = Vector3.INF
			_last_paint_update_time = 0.0

			if _has_multi_tile_selection():
				placement_manager.start_paint_stroke(get_undo_redo(), "Paint Multi-Tiles")
			else:
				placement_manager.start_paint_stroke(get_undo_redo(), "Paint Tiles")

			_paint_tile_at_mouse(camera, event.position, false)
			return AFTER_GUI_INPUT_STOP
		else:
			if is_area_selecting:
				_complete_area_fill()
				return AFTER_GUI_INPUT_STOP

			if _is_painting:
				placement_manager.end_paint_stroke()
				_is_painting = false
				return AFTER_GUI_INPUT_STOP

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if event.shift_pressed:
				if _area_fill_operator:
					_area_fill_operator.start(camera, event.position, true)
				return AFTER_GUI_INPUT_STOP

			_is_erasing = true
			_is_painting = false
			_last_painted_position = Vector3.INF
			_last_paint_update_time = 0.0

			placement_manager.start_paint_stroke(get_undo_redo(), "Erase Tiles")

			_paint_tile_at_mouse(camera, event.position, true)
			return AFTER_GUI_INPUT_STOP
		else:
			if is_area_selecting:
				_complete_area_fill()
				return AFTER_GUI_INPUT_STOP

			if _is_erasing:
				placement_manager.end_paint_stroke()
				_is_erasing = false
				return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS

# =============================================================================
# SECTION: PREVIEW AND HIGHLIGHTING
# =============================================================================
# Methods for updating the tile preview, cursor position, and tile highlighting.
# Includes optimization logic to reduce unnecessary updates.
# =============================================================================

##  Check if preview should update based on movement thresholds
## Reduces preview updates by 5-10x by ignoring micro-movements
func _should_update_preview(screen_pos: Vector2, grid_pos: Vector3 = Vector3.INF) -> bool:
	# RESTORED OPTIMIZATION: Check screen space movement
	if _last_preview_screen_pos != Vector2.INF:
		var screen_delta: float = screen_pos.distance_to(_last_preview_screen_pos)
		if screen_delta < GlobalConstants.PREVIEW_MIN_MOVEMENT:
			return false  # Not enough screen movement

	# Check grid space movement
	if grid_pos != Vector3.INF and _last_preview_grid_pos != Vector3.INF:
		var grid_delta: float = grid_pos.distance_to(_last_preview_grid_pos)
		if grid_delta < GlobalConstants.PREVIEW_MIN_GRID_MOVEMENT:
			return false  # Not enough grid movement

	return true

## Updates the tile preview based on mouse position and camera angle
## Added force_update to bypass optimization on Keyboard events
func _update_preview(camera: Camera3D, screen_pos: Vector2, force_update: bool = false) -> void:
	if not tile_preview or not tile_cursor or not placement_manager.tileset_texture:
		return
	
	# OPTIMIZATION LOGIC
	if not force_update:
		if not _should_update_preview(screen_pos):
			return

	# Update "Last Known" for next frame
	_last_preview_screen_pos = screen_pos

	# Update GlobalPlaneDetector state from camera
	GlobalPlaneDetector.update_from_camera(camera, self)

	var has_multi_selection: bool = _has_multi_tile_selection()
	var has_autotile_ready: bool = _is_autotile_mode() and _autotile_extension and _autotile_extension.is_ready()

	# Only return early if no valid selection in ANY mode
	if not has_multi_selection and not placement_manager.current_tile_uv.has_area() and not has_autotile_ready:
		tile_preview.hide_preview()
		if current_tile_map3d:
			current_tile_map3d.clear_highlights()
		return

	var preview_grid_pos: Vector3
	var preview_orientation: int = GlobalPlaneDetector.current_tile_orientation_18d

	if placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR_PLANE:
		var result: Dictionary = placement_manager.calculate_cursor_plane_placement(camera, screen_pos)
		if result.is_empty():
			tile_preview.hide_preview()
			if current_tile_map3d:
				current_tile_map3d.clear_highlights()
			return
		preview_grid_pos = result.grid_pos
		preview_orientation = result.orientation

		if tile_cursor:
			tile_cursor.set_active_plane(result.active_plane)

	elif placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR:
		var raw_pos = tile_cursor.grid_position
		preview_grid_pos = placement_manager.snap_to_grid(raw_pos)

	else: # RAYCAST mode
		var ray_result: Dictionary = placement_manager._raycast_to_geometry(camera, screen_pos)
		if ray_result.is_empty():
			tile_preview.hide_preview()
			if current_tile_map3d:
				current_tile_map3d.clear_highlights()
			return
		var grid_coords: Vector3 = GlobalUtil.world_to_grid(ray_result.position, placement_manager.grid_size)
		preview_grid_pos = placement_manager.snap_to_grid(grid_coords)

	# POSITION VALIDATION: Check if preview position is within valid coordinate range
	if not TileKeySystem.is_position_valid(preview_grid_pos):
		# Show blocked highlight (bright red) instead of normal preview
		if current_tile_map3d:
			current_tile_map3d.show_blocked_highlight(preview_grid_pos, preview_orientation)
		tile_preview.hide_preview()
		return

	# Clear blocked highlight if position is valid
	if current_tile_map3d:
		current_tile_map3d.clear_blocked_highlight()

	# Update preview (single, multi, or autotile)
	if has_multi_selection:
		# Multi-tile stamp preview (manual mode)
		tile_preview.update_multi_preview(
			preview_grid_pos,
			_get_selected_tiles(),
			preview_orientation,
			placement_manager.current_mesh_rotation,
			placement_manager.tileset_texture,
			placement_manager.is_current_face_flipped,
			true
		)
	elif has_autotile_ready:
		# AUTOTILE MODE: Show solid color preview using terrain color
		var terrain_color: Color = _autotile_engine.get_terrain_color(_autotile_extension.current_terrain_id)
		# Add transparency for better visibility
		terrain_color.a = 0.7
		tile_preview.update_color_preview(
			preview_grid_pos,
			preview_orientation,
			terrain_color,
			placement_manager.current_mesh_rotation,
			placement_manager.is_current_face_flipped,
			true
		)
	else:
		# Single tile preview (manual mode)
		tile_preview.update_preview(
			preview_grid_pos,
			preview_orientation,
			placement_manager.current_tile_uv,
			placement_manager.tileset_texture,
			placement_manager.current_mesh_rotation,
			placement_manager.is_current_face_flipped,
			true
		)

	_highlight_tiles_at_preview_position(preview_grid_pos, preview_orientation, has_multi_selection)


## Highlights tiles at the preview position (shows what will be replaced)
func _highlight_tiles_at_preview_position(grid_pos: Vector3, orientation: int, is_multi: bool) -> void:
	if not current_tile_map3d or not placement_manager:
		return

	var tiles_to_highlight: Array[int] = []

	if is_multi:
		# Multi-tile check: Calculate tile keys for each stamp position
		var selected_tiles: Array[Rect2] = _get_selected_tiles()
		for tile_uv_rect in selected_tiles:
			# Calculate offset for this tile in the multi-selection
			var anchor_uv_rect: Rect2 = selected_tiles[0]
			var pixel_offset: Vector2 = tile_uv_rect.position - anchor_uv_rect.position
			var tile_pixel_size: Vector2 = tile_uv_rect.size
			var grid_offset_2d: Vector2 = pixel_offset / tile_pixel_size

			# Transform offset to 3D based on orientation
			var local_offset: Vector3 = Vector3(grid_offset_2d.x, 0, grid_offset_2d.y)
			var world_offset: Vector3 = placement_manager._transform_local_offset_to_world(
				local_offset,
				orientation,
				placement_manager.current_mesh_rotation
			)

			var tile_grid_pos: Vector3 = grid_pos + world_offset
			var multi_tile_key: int = GlobalUtil.make_tile_key(tile_grid_pos, orientation)

			if placement_manager._placement_data.has(multi_tile_key):
				tiles_to_highlight.append(multi_tile_key)
	else:
		# Single-tile check
		var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
		if placement_manager._placement_data.has(tile_key):
			tiles_to_highlight.append(tile_key)

	# Apply highlights or clear if none found
	if tiles_to_highlight.is_empty():
		current_tile_map3d.clear_highlights()
	else:
		current_tile_map3d.highlight_tiles(tiles_to_highlight)

## Paints tile(s) at mouse position during painting mode (Phase 5)
## Handles duplicate prevention and calls appropriate placement manager method
func _paint_tile_at_mouse(camera: Camera3D, screen_pos: Vector2, is_erase: bool) -> void:
	if not placement_manager:
		return

	# Calculate grid position based on placement mode (same logic as single-tile placement)
	var grid_pos: Vector3
	var orientation: int = GlobalPlaneDetector.current_tile_orientation_18d

	if placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR_PLANE:
		var result: Dictionary = placement_manager.calculate_cursor_plane_placement(camera, screen_pos)
		if result.is_empty():
			return
		grid_pos = result.grid_pos
		orientation = result.orientation

	elif placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR:
		var raw_pos: Vector3 = tile_cursor.grid_position if tile_cursor else Vector3.ZERO
		grid_pos = placement_manager.snap_to_grid(raw_pos)

	else: # RAYCAST mode
		var ray_result: Dictionary = placement_manager._raycast_to_geometry(camera, screen_pos)
		if ray_result.is_empty():
			return
		var grid_coords: Vector3 = GlobalUtil.world_to_grid(ray_result.position, placement_manager.grid_size)
		grid_pos = placement_manager.snap_to_grid(grid_coords)

	# POSITION VALIDATION: Check if position is within valid coordinate range (±3,276.7)
	if not TileKeySystem.is_position_valid(grid_pos):
		# Show blocked highlight (bright red) and warn user
		if current_tile_map3d:
			current_tile_map3d.show_blocked_highlight(grid_pos, orientation)
		push_warning("TileMapLayer3D: Cannot place tile at position %s - outside valid range (±%.1f)" % [grid_pos, GlobalConstants.MAX_GRID_RANGE])
		return  # Block placement

	# Clear blocked highlight if position is valid
	if current_tile_map3d:
		current_tile_map3d.clear_blocked_highlight()

	# DUPLICATE PREVENTION: Check if we've already painted at this position
	# Use distance check instead of direct comparison to handle floating point precision
	if _last_painted_position.distance_to(grid_pos) < GlobalConstants.MIN_PAINT_GRID_DISTANCE:
		return  # Skip - too close to last painted position

	# Paint or erase tile(s) at this position
	if is_erase:
		# ERASE MODE: Remove tile at this position
		# Get terrain_id before erasing for autotile neighbor updates
		var terrain_id: int = GlobalConstants.AUTOTILE_NO_TERRAIN
		if _autotile_extension:
			var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
			var placement_data: Dictionary = placement_manager.get_placement_data()
			if placement_data.has(tile_key):
				var tile_data: TilePlacerData = placement_data[tile_key]
				terrain_id = tile_data.terrain_id

		placement_manager.erase_tile_at(grid_pos, orientation)

		# Update autotile neighbors after erasing
		if _autotile_extension and terrain_id >= 0:
			_autotile_extension.on_tile_erased(grid_pos, orientation, terrain_id)
	else:
		# PAINT MODE: Place tile(s)
		if _has_multi_tile_selection():
			# Multi-tile stamp painting (manual mode only)
			placement_manager.paint_multi_tiles_at(grid_pos, orientation)
		elif _is_autotile_mode() and _autotile_extension and _autotile_extension.is_ready():
			# AUTOTILE MODE: Get UV from autotile system
			var autotile_uv: Rect2 = _autotile_extension.get_autotile_uv(grid_pos, orientation)
			if autotile_uv.has_area():
				# Temporarily set the UV for placement
				var original_uv: Rect2 = placement_manager.current_tile_uv
				placement_manager.current_tile_uv = autotile_uv
				placement_manager.paint_tile_at(grid_pos, orientation)
				placement_manager.current_tile_uv = original_uv

				# Update neighbors and set terrain_id on placed tile
				_autotile_extension.on_tile_placed(grid_pos, orientation)
		else:
			# Single tile painting (manual mode)
			placement_manager.paint_tile_at(grid_pos, orientation)

	# Update last painted position
	_last_painted_position = grid_pos

	# Check tile count warning (for both paint and erase - resets flag when tiles cleared)
	_check_tile_count_warning()

## Checks if tile count is approaching recommended maximum and shows warning
## Called after successful tile placement operations
## Only updates configuration warnings when tile count crosses threshold boundaries
## (avoids O(n) scan on every single tile operation for performance)
func _check_tile_count_warning() -> void:
	if not current_tile_map3d or not placement_manager:
		return

	var total_tiles: int = placement_manager._placement_data.size()
	var threshold: int = int(GlobalConstants.MAX_RECOMMENDED_TILES * GlobalConstants.TILE_COUNT_WARNING_THRESHOLD)
	var limit: int = GlobalConstants.MAX_RECOMMENDED_TILES

	# Detect threshold crossings (entering or exiting warning/limit zones)
	var was_over_limit: bool = _last_tile_count > limit
	var is_over_limit: bool = total_tiles > limit
	var was_over_threshold: bool = _last_tile_count >= threshold
	var is_over_threshold: bool = total_tiles >= threshold

	# Only update configuration warnings when state changes (avoids O(n) scan every operation)
	# This triggers the yellow warning triangle to appear/disappear in the Scene tree
	if was_over_limit != is_over_limit or was_over_threshold != is_over_threshold:
		current_tile_map3d.update_configuration_warnings()

	# Track current count for next comparison
	_last_tile_count = total_tiles

	# Reset warning flag if tile count dropped below threshold (user cleared tiles)
	if total_tiles < threshold:
		_tile_count_warning_shown = false
		return

	# Print warning when reaching threshold (only once until tiles are cleared)
	if not _tile_count_warning_shown:
		push_warning("TileMapLayer3D: Tile count (%d) is at %.0f%% of recommended maximum (%d). Consider splitting into multiple TileMapLayer3D nodes for better performance." % [
			total_tiles,
			GlobalConstants.TILE_COUNT_WARNING_THRESHOLD * 100,
			GlobalConstants.MAX_RECOMMENDED_TILES
		])
		_tile_count_warning_shown = true

# =============================================================================
# SECTION: SIGNAL HANDLERS - UI EVENTS
# =============================================================================
# Callbacks connected to signals from TilesetPanel and other UI components.
# Handle tile selection, mode changes, orientation changes, etc.
# =============================================================================

func _on_tool_toggled(pressed: bool) -> void:
	is_active = pressed
	#print("Tool active: ", is_active)

func _on_tile_selected(uv_rect: Rect2) -> void:
	# Single tile selected - route through SelectionManager
	if selection_manager:
		selection_manager.select([uv_rect], 0)

	# Reset rotation when selecting new tile and save to settings
	if placement_manager:
		placement_manager.current_mesh_rotation = 0
		if current_tile_map3d and current_tile_map3d.settings:
			current_tile_map3d.settings.current_mesh_rotation = 0

	# Hide multi-tile preview instances (single tile doesn't need them)
	if tile_preview:
		tile_preview._hide_all_preview_instances()

## Handles multi-tile selection from UI
## Routes through SelectionManager (single source of truth)
func _on_multi_tile_selected(uv_rects: Array[Rect2], anchor_index: int) -> void:
	# Guard: Ignore if in autotile mode (multi-tile not supported)
	if _is_autotile_mode():
		return

	#print("Multi-tile selected: ", uv_rects.size(), " tiles (anchor: ", anchor_index, ")")

	# Route through SelectionManager (single source of truth)
	if selection_manager:
		selection_manager.select(uv_rects, anchor_index)

	# Reset rotation when selecting new tiles and save to settings
	if placement_manager:
		placement_manager.current_mesh_rotation = 0
		if current_tile_map3d and current_tile_map3d.settings:
			current_tile_map3d.settings.current_mesh_rotation = 0

	# Note: Preview will be updated in _update_preview() during mouse motion

func _on_tileset_loaded(texture: Texture2D) -> void:
	placement_manager.tileset_texture = texture
	if current_tile_map3d:
		current_tile_map3d.tileset_texture = texture
		current_tile_map3d.update_configuration_warnings()
	#print("Tileset texture updated: ", texture.get_path() if texture else "null")

func _on_orientation_changed(orientation: int) -> void:
	GlobalPlaneDetector.current_tile_orientation_18d = orientation
	#print("Orientation updated: ", orientation)

func _on_placement_mode_changed(mode: int) -> void:
	placement_manager.placement_mode = mode as TilePlacementManager.PlacementMode

	#print("Placement mode updated: ", GlobalConstants.PLACEMENT_MODE_NAMES[mode])

	# Update cursor visibility (show cursor for CURSOR_PLANE and CURSOR modes)
	if tile_cursor:
		tile_cursor.visible = (mode == 0 or mode == 1)  # Show cursor for plane and point modes

## Handler for auto-flip feature
## Called when GlobalPlaneDetector detects a plane change and auto-flip is enabled
func _on_auto_flip_requested(flip_state: bool) -> void:
	# Only apply auto-flip if enabled in settings
	if not plugin_settings or not plugin_settings.enable_auto_flip:
		return

	# Update flip state in placement manager
	if placement_manager:
		placement_manager.is_current_face_flipped = flip_state
		#print("Auto-flip: Face flipped = ", flip_state)

		# Also reset mesh rotation to 0 (like T key behavior)
		placement_manager.current_mesh_rotation = 0

		# Save to settings for persistence
		if current_tile_map3d and current_tile_map3d.settings:
			current_tile_map3d.settings.current_mesh_rotation = 0
			current_tile_map3d.settings.is_face_flipped = flip_state


# =============================================================================
# SECTION: SELECTION MANAGER HANDLERS
# =============================================================================
# Handlers for SelectionManager signals. The SelectionManager is the single
# source of truth for selection state. These handlers sync the selection to:
# - Settings (for persistence)
# - PlacementManager (for fast painting)
# =============================================================================

## Called when selection changes in SelectionManager
## Syncs selection to settings (persistence) and placement_manager (runtime)
func _on_selection_manager_changed(tiles: Array[Rect2], anchor: int) -> void:
	# Sync to settings for persistence (only if we have a current node)
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.selected_tiles = tiles.duplicate()
		current_tile_map3d.settings.selected_anchor_index = anchor

	# Sync to placement_manager for fast painting
	if placement_manager:
		if tiles.size() == 1:
			# Single tile selection
			placement_manager.current_tile_uv = tiles[0]
			placement_manager.multi_tile_selection.clear()
			placement_manager.multi_tile_anchor_index = 0
		else:
			# Multi-tile selection
			placement_manager.multi_tile_selection = tiles.duplicate()
			placement_manager.multi_tile_anchor_index = anchor


## Called when selection is cleared in SelectionManager
## Clears selection from all synced locations
func _on_selection_manager_cleared() -> void:
	# Clear from settings
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.selected_tiles.clear()
		current_tile_map3d.settings.selected_anchor_index = 0

	# Clear from placement_manager
	if placement_manager:
		placement_manager.current_tile_uv = Rect2()
		placement_manager.multi_tile_selection.clear()
		placement_manager.multi_tile_anchor_index = 0

	# Clear UI highlight
	if tileset_panel:
		tileset_panel.clear_selection()

	# Hide preview
	if tile_preview:
		tile_preview.hide_preview()
		tile_preview._hide_all_preview_instances()


## Handler for Generate SIMPLE Collision button
func _on_create_collision_requested(bake_mode: MeshBakeManager.BakeMode) -> void:
	if not current_tile_map3d:
		push_warning("No TileMapLayer3D selected")
		return

	#print("Generating collision for ", current_tile_map3d.name, " MODE: ", str(bake_mode))

	var parent: Node = current_tile_map3d.get_parent()
	if not parent:
		push_error("TileMapLayer3D has no parent node")
		return

	#print("Bake Started! MODE: ", str(bake_mode))

	var bake_result: Dictionary = MeshBakeManager.bake_to_static_mesh(
		current_tile_map3d,
		bake_mode,
		get_undo_redo(),
		parent,
		false
	)

	# Create collision from the baked mesh
	bake_result.mesh_instance.create_trimesh_collision()
	var new_collision_shape: ConcavePolygonShape3D = null

	# Find and extract the auto-generated collision shape
	for child in bake_result.mesh_instance.get_children():
		if child is StaticBody3D:
			for collision_child in child.get_children():
				if collision_child is CollisionShape3D:
					# Extract and duplicate the shape resource
					new_collision_shape = collision_child.shape as ConcavePolygonShape3D
					if new_collision_shape:
						new_collision_shape = new_collision_shape.duplicate()  # duplicate so we own it
						new_collision_shape.backface_collision = true
					break
			break

	# Clean up temporary mesh
	bake_result.mesh_instance.queue_free()

	if not new_collision_shape:
		push_error("Failed to generate collision new_collision_shape")
		return

	# Clear existing collision bodies
	current_tile_map3d.clear_collision_shapes()

	# Create new collision structure
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.shape = new_collision_shape
	
	var static_body: StaticCollisionBody3D = StaticCollisionBody3D.new()
	static_body.add_child(collision_shape)
	
	# Add to scene and set owners (requied for editor)
	current_tile_map3d.add_child(static_body)
	var scene_root: Node = current_tile_map3d.get_tree().edited_scene_root
	static_body.owner = scene_root
	collision_shape.owner = scene_root

	#print("Collision generation complete!")

## Merge and Bakes the TileMapLayer3D to a new ArrayMesh creating a unified merged object
## This creates a single optimized mesh from all tiles with perfect UV preservation
## NOW USES MeshBakeManager for centralized baking logic
func _on_bake_mesh_requested(bake_mode: MeshBakeManager.BakeMode) -> void:
	if not Engine.is_editor_hint(): return

	# Validation
	if not current_tile_map3d:
		push_error("No TileMapLayer3D selected for merge bake")
		return

	if current_tile_map3d.saved_tiles.is_empty():
		push_error("TileMapLayer3D has no tiles to merge")
		return

	# Execute bake using MeshBakeManager
	var parent: Node = current_tile_map3d.get_parent()
	if not parent:
		push_error("TileMapLayer3D has no parent node")
		return
	
	#print("Bake Started! MODE: " , str(bake_mode))

	var bake_result: Dictionary = MeshBakeManager.bake_to_static_mesh(
		current_tile_map3d,
		bake_mode,
		get_undo_redo(),
		parent,
		true
	)

	# Check result
	if not bake_result.success:
		push_error("Bake failed: %s" % bake_result.get("error", "Unknown error"))
		return

	# Print success with stats
	#var stats: Dictionary = bake_result.get("merge_result", {})
	#print("Bake complete! Created: %s" % bake_result.mesh_instance.name)
	#if stats.has("tile_count"):
	#	print("   Stats: %d tiles → %d vertices" % [
	#		stats.get("tile_count", 0),
	#		stats.get("vertex_count", 0)
	#	])

# =============================================================================
# SECTION: CLEAR AND DEBUG OPERATIONS
# =============================================================================
# Methods for clearing all tiles and displaying debug information.
# Includes diagnostic tools for troubleshooting placement issues.
# =============================================================================

## Cleans up an array of chunk nodes (removes from tree, clears data, frees)
## Extracted helper to avoid code duplication between square and triangle chunk cleanup
##
## @param chunks: Array of TileChunk nodes to clean up
func _cleanup_chunk_array(chunks: Array) -> void:
	for chunk in chunks:
		if is_instance_valid(chunk):
			if chunk.get_parent():
				chunk.get_parent().remove_child(chunk)
			chunk.owner = null
			chunk.queue_free()
		chunk.tile_refs.clear()
		chunk.instance_to_key.clear()
	chunks.clear()


## Clears all tiles from the current TileMapLayer3D
func _clear_all_tiles() -> void:
	if not current_tile_map3d:
		push_warning("No TileMapLayer3D selected")
		return

	# Confirm with user
	var confirm_dialog: ConfirmationDialog = ConfirmationDialog.new()
	confirm_dialog.dialog_text = "Clear all tiles from '%s'?\n\nThis action cannot be undone." % current_tile_map3d.name
	confirm_dialog.title = "Clear All Tiles"
	confirm_dialog.confirmed.connect(_do_clear_all_tiles)

	# Add to editor interface
	EditorInterface.get_base_control().add_child(confirm_dialog)
	confirm_dialog.popup_centered()

	# Clean up dialog after use
	confirm_dialog.visibility_changed.connect(func():
		if not confirm_dialog.visible:
			confirm_dialog.queue_free()
	)

## Actually performs the clear operation
func _do_clear_all_tiles() -> void:
	if not current_tile_map3d:
		#print("First Select a TileMap3d node")
		return

	#print("Clearing all tiles from ", current_tile_map3d.name)

	# Clear saved tiles
	var tile_count: int = current_tile_map3d.saved_tiles.size()
	current_tile_map3d.saved_tiles.clear()
	current_tile_map3d._saved_tiles_lookup.clear()  #Clear lookup dictionary

	# Clear runtime chunks for BOTH square and triangle chunks
	_cleanup_chunk_array(current_tile_map3d._quad_chunks)
	_cleanup_chunk_array(current_tile_map3d._triangle_chunks)

	# Clear tile lookup
	current_tile_map3d._tile_lookup.clear()

	# Clear collision shapes
	current_tile_map3d.clear_collision_shapes()

	# Clear placement manager data
	placement_manager._placement_data.clear()

	#print("Cleared %d tiles and all collision shapes" % tile_count)

## Shows debug information about the current TileMapLayer3D
## Prints to console (Output panel) for easy copying
func _on_show_debug_info_requested() -> void:
	DebugInfoGenerator.print_report(current_tile_map3d, placement_manager)

# =============================================================================
# SECTION: SETTINGS HANDLERS
# =============================================================================
# Handlers for plugin settings changes (grid size, snap, filter mode, etc.).
# Updates both the current session and persistent plugin settings.
# =============================================================================

## Handler for show plane grids toggle
func _on_show_plane_grids_changed(enabled: bool) -> void:
	if tile_cursor:
		tile_cursor.show_plane_grids = enabled
		#print("Plane grids visibility: ", enabled)

	# Save to global plugin settings
	if plugin_settings:
		plugin_settings.show_plane_grids = enabled

## Handler for cursor step size change
func _on_cursor_step_size_changed(step_size: float) -> void:
	if tile_cursor:
		tile_cursor.cursor_step_size = step_size
		#print("Cursor step size changed to: ", step_size)

## Handler for grid snap size change
func _on_grid_snap_size_changed(snap_size: float) -> void:
	if placement_manager:
		placement_manager.grid_snap_size = snap_size
		#print("Grid snap size changed to: ", snap_size)

func _on_mesh_mode_selection_changed(mesh_mode: GlobalConstants.MeshMode) -> void:
	if current_tile_map3d:
		current_tile_map3d.current_mesh_mode = mesh_mode
		#var mesh_mode_name: String = GlobalConstants.MeshMode.keys()[mesh_mode]
		#print("Mesh Mode Selection changed to: ", mesh_mode, " - ", mesh_mode_name)
	
	# NEW: Update preview mesh mode
	if tile_preview:
		tile_preview.current_mesh_mode = mesh_mode
		# Force preview refresh
		var camera = get_viewport().get_camera_3d()
		if camera:
			_update_preview(camera, get_viewport().get_mouse_position())

## Handler for grid size change (requires rebuild)
func _on_grid_size_changed(new_size: float) -> void:
	#print("Grid size change requested: ", new_size)

	# EARLY EXIT: Skip if grid size hasn't actually changed
	# This prevents collision clearing when just re-selecting a node
	# (TilesetPanel emits grid_size_changed during _load_settings_to_ui even if value unchanged)
	if current_tile_map3d and is_equal_approx(current_tile_map3d.grid_size, new_size):
		return

	# Update all components with new grid_size
	if current_tile_map3d:
		current_tile_map3d.grid_size = new_size

	if placement_manager:
		placement_manager.grid_size = new_size

	if tile_cursor:
		tile_cursor.grid_size = new_size

	if tile_preview:
		tile_preview.grid_size = new_size

	# Clear all collision shapes (user must regenerate manually)
	if current_tile_map3d:
		#print("Clearing collision shapes due to grid size change...")
		current_tile_map3d.clear_collision_shapes()


	# Defer rebuild to next frame to avoid freezing during setter chain
	if current_tile_map3d:
		#print("Rebuilding tiles with new grid_size: ", new_size)
		# Use call_deferred to avoid blocking the main thread
		current_tile_map3d.call_deferred("_rebuild_chunks_from_saved_data", true)  # force_mesh_rebuild=true

	#print("Grid size update initiated - rebuild in progress...")

func _on_texture_filter_changed(filter_mode: int) -> void:
	if placement_manager:
		placement_manager.set_texture_filter(filter_mode)

	# Update preview to use new filter mode
	if tile_preview:
		tile_preview.texture_filter_mode = filter_mode
		tile_preview._update_material()



# =============================================================================
# SECTION: AREA FILL OPERATIONS
# =============================================================================
# Methods for Shift+Drag area fill and erase operations.
# Uses AreaFillOperator for state management and workflow coordination.
# =============================================================================

## Completes area fill/erase operation using the AreaFillOperator
## The operator handles selection state, validation, and emits completion signals
func _complete_area_fill() -> void:
	if not _area_fill_operator:
		return

	# Complete via operator with callbacks for fill and erase
	var result: int = _area_fill_operator.complete(
		get_undo_redo(),
		_do_area_fill,  # Fill callback
		_do_area_erase  # Erase callback
	)

	# Check tile count warning after fill/erase operations
	if result > 0:
		_check_tile_count_warning()


## Callback for area fill operations (called by AreaFillOperator)
## @param min_pos: Minimum corner of area
## @param max_pos: Maximum corner of area
## @param orientation: Active plane orientation (0-5)
## @returns: Number of tiles placed
func _do_area_fill(min_pos: Vector3, max_pos: Vector3, orientation: int) -> int:
	if not placement_manager:
		return -1

	# Branch for autotile vs manual mode
	if _is_autotile_mode() and _autotile_extension and _autotile_extension.is_ready():
		# AUTOTILE AREA FILL: Use autotile system to determine tile UVs
		return _fill_area_autotile(min_pos, max_pos, orientation)
	else:
		# MANUAL AREA FILL: Use selected tile UV for all tiles
		return placement_manager.fill_area_with_undo_compressed(min_pos, max_pos, orientation, get_undo_redo())


## Callback for area erase operations (called by AreaFillOperator)
## @param min_pos: Minimum corner of area
## @param max_pos: Maximum corner of area
## @param orientation: Active plane orientation (0-5)
## @param undo_redo: The EditorUndoRedoManager
## @returns: Number of tiles erased
func _do_area_erase(min_pos: Vector3, max_pos: Vector3, orientation: int, undo_redo: EditorUndoRedoManager) -> int:
	if not placement_manager:
		return -1
	return placement_manager.erase_area_with_undo(min_pos, max_pos, orientation, undo_redo)


## Signal handler: Highlight tiles during area selection
func _on_area_fill_highlight_requested(start_pos: Vector3, end_pos: Vector3, orientation: int, is_erase: bool) -> void:
	_highlight_tiles_in_area(start_pos, end_pos, orientation, is_erase)


## Signal handler: Clear highlights when selection ends
func _on_area_fill_clear_highlights() -> void:
	if current_tile_map3d:
		current_tile_map3d.clear_highlights()


## Signal handler: Show blocked highlight when out of bounds
func _on_area_fill_out_of_bounds(position: Vector3, orientation: int) -> void:
	if current_tile_map3d:
		current_tile_map3d.show_blocked_highlight(position, orientation)


## Fills an area with autotiled tiles
## Uses a four-phase approach to ensure all tiles get correct UVs:
##   Phase 1: Place all tiles with placeholder UV
##   Phase 2: Set terrain_id on ALL tiles (no neighbor updates)
##   Phase 3: Recalculate and apply correct UVs for ALL tiles
##   Phase 4: Update external neighbors (tiles outside fill area)
## @param min_pos: Minimum corner of area
## @param max_pos: Maximum corner of area
## @param orientation: Active plane orientation (0-5)
## @returns: Number of tiles placed, or -1 if operation fails
func _fill_area_autotile(min_pos: Vector3, max_pos: Vector3, orientation: int) -> int:
	if not _autotile_extension or not _autotile_extension.is_ready():
		push_error("Autotile area fill: Extension not ready")
		return -1

	if not placement_manager or not current_tile_map3d:
		push_error("Autotile area fill: Missing placement manager or tile map")
		return -1

	# Get all grid positions in the area
	var positions: Array[Vector3] = GlobalUtil.get_grid_positions_in_area(min_pos, max_pos, orientation)

	if positions.is_empty():
		return 0

	# Safety check: prevent massive fills
	if positions.size() > GlobalConstants.MAX_AREA_FILL_TILES:
		push_error("Autotile area fill: Area too large (%d tiles, max %d)" % [positions.size(), GlobalConstants.MAX_AREA_FILL_TILES])
		return -1

	# Start paint stroke for undo support (all tiles become one undo operation)
	placement_manager.start_paint_stroke(get_undo_redo(), "Autotile Area Fill (%d tiles)" % positions.size())

	# Batch updates for GPU efficiency
	placement_manager.begin_batch_update()

	# Store original UV to restore after
	var original_uv: Rect2 = placement_manager.current_tile_uv

	# Get first valid placeholder UV (will be recalculated in Phase 3)
	var placeholder_uv: Rect2 = _autotile_extension.get_autotile_uv(positions[0], orientation)
	if not placeholder_uv.has_area():
		placement_manager.end_batch_update()
		placement_manager.end_paint_stroke()
		return 0

	# Track placed tiles and their keys
	var placed_positions: Array[Vector3] = []
	var tile_keys: Array[int] = []

	# PHASE 1: Place all tiles with placeholder UV
	# We use the same UV for all - it will be corrected in Phase 3
	for grid_pos: Vector3 in positions:
		placement_manager.current_tile_uv = placeholder_uv
		if placement_manager.paint_tile_at(grid_pos, orientation):
			placed_positions.append(grid_pos)
			tile_keys.append(GlobalUtil.make_tile_key(grid_pos, orientation))

	# Restore original UV
	placement_manager.current_tile_uv = original_uv

	if placed_positions.is_empty():
		placement_manager.end_batch_update()
		placement_manager.end_paint_stroke()
		return 0

	# PHASE 2: Set terrain_id on ALL tiles without triggering neighbor updates
	# This ensures all tiles in the area recognize each other
	var placement_data: Dictionary = placement_manager.get_placement_data()
	var terrain_id: int = _autotile_extension.current_terrain_id

	for tile_key: int in tile_keys:
		if placement_data.has(tile_key):
			var tile_data: TilePlacerData = placement_data[tile_key]
			tile_data.terrain_id = terrain_id
			# Update saved_tiles for persistence
			current_tile_map3d.update_saved_tile_terrain(tile_key, terrain_id)

	# PHASE 3: Recalculate and apply correct UVs for ALL tiles
	# Now that all tiles have terrain_ids, bitmask calculation will be correct
	for i in range(placed_positions.size()):
		var grid_pos: Vector3 = placed_positions[i]
		var tile_key: int = tile_keys[i]

		# Calculate correct UV based on actual neighbors
		var correct_uv: Rect2 = _autotile_extension.get_autotile_uv(grid_pos, orientation)

		if placement_data.has(tile_key) and correct_uv.has_area():
			var tile_data: TilePlacerData = placement_data[tile_key]
			if tile_data.uv_rect != correct_uv:
				tile_data.uv_rect = correct_uv
				current_tile_map3d.update_tile_uv(tile_key, correct_uv)

	# PHASE 4: Update external neighbors (tiles OUTSIDE the filled area)
	# Create a set of filled positions for fast lookup
	var filled_set: Dictionary = {}
	for grid_pos: Vector3 in placed_positions:
		var key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
		filled_set[key] = true

	# Find all external neighbors that need updating
	var external_neighbors: Dictionary = {}  # tile_key -> grid_pos
	for grid_pos: Vector3 in placed_positions:
		var neighbors: Array[Vector3] = PlaneCoordinateMapper.get_neighbor_positions_3d(grid_pos, orientation)
		for neighbor_pos: Vector3 in neighbors:
			var neighbor_key: int = GlobalUtil.make_tile_key(neighbor_pos, orientation)
			# Only include if NOT in filled area AND exists in placement data
			if not filled_set.has(neighbor_key) and placement_data.has(neighbor_key):
				external_neighbors[neighbor_key] = neighbor_pos

	# Update each external neighbor's UV
	for neighbor_key: int in external_neighbors.keys():
		var neighbor_pos: Vector3 = external_neighbors[neighbor_key]
		var neighbor_data: TilePlacerData = placement_data[neighbor_key]

		# Skip non-autotiled tiles
		if neighbor_data.terrain_id < 0:
			continue

		# Recalculate UV for this neighbor
		var engine: AutotileEngine = _autotile_extension.get_engine()
		if engine:
			var new_bitmask: int = engine.calculate_bitmask(
				neighbor_pos, orientation, neighbor_data.terrain_id, placement_data
			)
			var new_uv: Rect2 = engine.get_uv_for_bitmask(neighbor_data.terrain_id, new_bitmask)

			if new_uv.has_area() and neighbor_data.uv_rect != new_uv:
				neighbor_data.uv_rect = new_uv
				current_tile_map3d.update_tile_uv(neighbor_key, new_uv)

	placement_manager.end_batch_update()

	# End paint stroke (commits the undo action)
	placement_manager.end_paint_stroke()

	return placed_positions.size()


## Highlights tiles within the selection area (shows what will be affected)
## IMPORTANT: Detects ALL tiles within bounds, including half-grid positions (0.5 snap)
## @param is_erase: True for erase mode, false for paint mode
func _highlight_tiles_in_area(start_pos: Vector3, end_pos: Vector3, orientation: int, is_erase: bool = false) -> void:
	if not current_tile_map3d or not placement_manager:
		return

	# Calculate actual min/max bounds (user may have dragged in any direction)
	var min_pos: Vector3 = Vector3(
		min(start_pos.x, end_pos.x),
		min(start_pos.y, end_pos.y),
		min(start_pos.z, end_pos.z)
	)
	var max_pos: Vector3 = Vector3(
		max(start_pos.x, end_pos.x),
		max(start_pos.y, end_pos.y),
		max(start_pos.z, end_pos.z)
	)

	# Apply orientation-aware tolerance to match erase_area_with_undo() behavior
	# This ensures highlighted tiles exactly match tiles that will be deleted
	# Tolerance is applied ONLY on plane axes, NOT depth axis (prevents misleading preview)
	if is_erase:
		var tolerance: float = GlobalConstants.AREA_ERASE_SURFACE_TOLERANCE
		var tolerance_vector: Vector3 = GlobalUtil.get_orientation_tolerance(orientation, tolerance)
		min_pos -= tolerance_vector
		max_pos += tolerance_vector

	# Build list of existing tiles to highlight
	var tiles_to_highlight: Array[int] = []

	if is_erase:
		# ERASE MODE: Iterate through ALL existing tiles and check if they fall within bounds
		# This detects tiles at half-grid positions (0.5 snap) that would be missed
		# by the old integer grid iteration approach

		# Early exit: Skip real-time highlighting for massive tile counts (performance optimization)
		# Area erase will still work correctly - this only disables the orange preview
		const MAX_HIGHLIGHT_CHECK: int = 20000
		var total_tiles: int = placement_manager._placement_data.size()
		if total_tiles > MAX_HIGHLIGHT_CHECK:
			current_tile_map3d.clear_highlights()
			return

		var total_in_bounds: int = 0
		for tile_key in placement_manager._placement_data.keys():
			var tile_data: TilePlacerData = placement_manager._placement_data[tile_key]
			var tile_pos: Vector3 = tile_data.grid_position

			# Check if tile position falls within selection bounds (inclusive)
			var is_within_bounds: bool = (
				tile_pos.x >= min_pos.x and tile_pos.x <= max_pos.x and
				tile_pos.y >= min_pos.y and tile_pos.y <= max_pos.y and
				tile_pos.z >= min_pos.z and tile_pos.z <= max_pos.z
			)

			if is_within_bounds:
				total_in_bounds += 1

				#  Cap highlight count to prevent performance issues
				# Area erase will still work on ALL tiles in bounds
				if tiles_to_highlight.size() < GlobalConstants.MAX_HIGHLIGHTED_TILES:
					tiles_to_highlight.append(tile_key)

		# Warn user if selection exceeds highlight cap
		if total_in_bounds > GlobalConstants.MAX_HIGHLIGHTED_TILES:
			push_warning("TileMapLayer3D: Area selection showing %d/%d tiles (erase will still affect all %d tiles)" % [
				GlobalConstants.MAX_HIGHLIGHTED_TILES,
				total_in_bounds,
				total_in_bounds
			])
	else:
		# PAINT MODE: Only highlight tiles matching current orientation at integer grid positions
		# (Paint fill only affects integer positions)
		var positions: Array[Vector3] = GlobalUtil.get_grid_positions_in_area(min_pos, max_pos, orientation)

		var total_in_bounds: int = 0
		for grid_pos in positions:
			var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
			if placement_manager._placement_data.has(tile_key):
				total_in_bounds += 1

				#  Cap highlight count to prevent performance issues
				# Area fill will still work on ALL tiles in bounds
				if tiles_to_highlight.size() < GlobalConstants.MAX_HIGHLIGHTED_TILES:
					tiles_to_highlight.append(tile_key)

		# Warn user if selection exceeds highlight cap
		if total_in_bounds > GlobalConstants.MAX_HIGHLIGHTED_TILES:
			push_warning("TileMapLayer3D: Area selection showing %d/%d tiles (fill will still affect all %d tiles)" % [
				GlobalConstants.MAX_HIGHLIGHTED_TILES,
				total_in_bounds,
				total_in_bounds
			])

	# Apply highlights or clear if none
	if tiles_to_highlight.is_empty():
		current_tile_map3d.clear_highlights()
	else:
		current_tile_map3d.highlight_tiles(tiles_to_highlight)

# =============================================================================
# SECTION: AUTOTILE MODE HANDLERS
# =============================================================================
# Handlers for autotile mode operations (V5).
# Manages mode switching, tileset changes, terrain selection, and data updates.
# =============================================================================

## Resets mesh transforms to default state (same effect as T key)
## Autotile placement requires default orientation - no user rotations
## Used when entering autotile mode or selecting a terrain
func _reset_autotile_transforms() -> void:
	if not placement_manager:
		return
	GlobalPlaneDetector.reset_to_flat()
	placement_manager.current_mesh_rotation = 0
	var default_flip: bool = GlobalPlaneDetector.determine_auto_flip_for_plane(GlobalPlaneDetector.current_plane_6d)
	placement_manager.is_current_face_flipped = default_flip

	# Save rotation/flip state to settings for persistence
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.current_mesh_rotation = 0
		current_tile_map3d.settings.is_face_flipped = default_flip

	# Reset mesh mode to SQUARE for autotile (autotile only supports square meshes)
	if current_tile_map3d:
		current_tile_map3d.current_mesh_mode = GlobalConstants.MeshMode.MESH_SQUARE
		# Update settings (single source of truth)
		if current_tile_map3d.settings:
			current_tile_map3d.settings.mesh_mode = GlobalConstants.MeshMode.MESH_SQUARE
	if tile_preview:
		tile_preview.current_mesh_mode = GlobalConstants.MeshMode.MESH_SQUARE

	# Update UI dropdown WITHOUT triggering signals (prevents cascade!)
	# Signal cascade from dropdown can cause settings reload which resurrects old selection
	if tileset_panel and tileset_panel.mesh_mode_dropdown:
		tileset_panel.mesh_mode_dropdown.set_block_signals(true)
		tileset_panel.mesh_mode_dropdown.selected = 0  # 0 = MESH_SQUARE
		tileset_panel.mesh_mode_dropdown.set_block_signals(false)


## Handler for tiling mode change (Manual vs Autotile)
## Writes to settings (single source of truth), then syncs to extension
func _on_tiling_mode_changed(mode: TilesetPanel.TilingMode) -> void:
	# Write to settings (single source of truth)
	_set_tiling_mode(mode)

	# Only clear selection when ENTERING autotile mode
	# When switching to Manual mode, preserve selection so user can continue painting
	if mode == TilesetPanel.TilingMode.AUTOTILE:
		_clear_selection()
		_reset_autotile_transforms()

	# Enable/disable autotile extension
	if _autotile_extension:
		_autotile_extension.set_enabled(mode == TilesetPanel.TilingMode.AUTOTILE)

	# Force preview refresh
	_invalidate_preview()


## Syncs tileset texture from AutotileEngine to all components
## Extracted helper to avoid code duplication (DRY principle)
## Called when TileSet is loaded or when TileSet data changes
func _sync_autotile_texture() -> void:
	if not _autotile_engine:
		return

	var autotile_texture: Texture2D = _autotile_engine.get_texture()
	if autotile_texture:
		placement_manager.tileset_texture = autotile_texture
		if current_tile_map3d:
			current_tile_map3d.tileset_texture = autotile_texture
			if current_tile_map3d.settings:
				current_tile_map3d.settings.tileset_texture = autotile_texture
			current_tile_map3d.update_configuration_warnings()

		# Update Manual tab UI to reflect the texture
		if tileset_panel:
			tileset_panel.set_tileset_texture(autotile_texture)
	else:
		push_warning("Autotile: TileSet has no atlas texture - neighbor updates will fail!")


## Handler for autotile TileSet change
func _on_autotile_tileset_changed(tileset: TileSet) -> void:
	# Clean up old engine
	if _autotile_engine:
		_autotile_engine = null

	if not tileset:
		if _autotile_extension:
			_autotile_extension.set_engine(null)
		#print("Autotile: TileSet cleared")
		return

	# Create new engine with the TileSet
	_autotile_engine = AutotileEngine.new(tileset)

	# Sync tileset_texture from TileSet atlas to all components
	_sync_autotile_texture()

	# Set up extension if not already created
	if not _autotile_extension:
		_autotile_extension = AutotilePlacementExtension.new()

	# Connect extension to engine and managers
	if placement_manager and current_tile_map3d:
		_autotile_extension.setup(_autotile_engine, placement_manager, current_tile_map3d)

	_autotile_extension.set_engine(_autotile_engine)
	_autotile_extension.set_enabled(_is_autotile_mode())

	# Save TileSet to node settings for persistence
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.autotile_tileset = tileset

	#print("Autotile: TileSet loaded with ", _autotile_engine.get_terrain_count(), " terrains")


## Handler for autotile terrain selection
func _on_autotile_terrain_selected(terrain_id: int) -> void:
	# Just set the terrain - mode should already be enabled from tab switch
	# No defensive mode enabling here - that caused side effects
	if _autotile_extension:
		_autotile_extension.set_terrain(terrain_id)

	# Reset mesh transforms (uses signal-blocked dropdown update)
	_reset_autotile_transforms()

	# Save to settings
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.autotile_active_terrain = terrain_id


## Handler for autotile data changes (terrains added/removed, peering bits painted)
## Rebuilds the AutotileEngine lookup tables when TileSet content changes
func _on_autotile_data_changed() -> void:
	if _autotile_engine:
		_autotile_engine.rebuild_lookup()

		# Re-sync texture in case atlas source was added/changed in TileSet Editor
		_sync_autotile_texture()


## Handler for clearing autotile state when user loads a new texture
## This is called when user confirms texture change warning dialog
func _on_clear_autotile_requested() -> void:
	# Clear the AutotileTab's TileSet (triggers tileset_changed signal cascade)
	if tileset_panel and tileset_panel.auto_tile_tab:
		var autotile_tab_node: AutotileTab = tileset_panel.auto_tile_tab as AutotileTab
		if autotile_tab_node:
			autotile_tab_node.set_tileset(null)

	# Clear autotile engine
	if _autotile_engine:
		_autotile_engine = null

	# Clear extension engine reference
	if _autotile_extension:
		_autotile_extension.set_engine(null)

	# Clear all autotile settings on the current node
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.autotile_tileset = null
		current_tile_map3d.settings.autotile_source_id = GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID
		current_tile_map3d.settings.autotile_terrain_set = GlobalConstants.AUTOTILE_DEFAULT_TERRAIN_SET
		current_tile_map3d.settings.autotile_active_terrain = GlobalConstants.AUTOTILE_NO_TERRAIN

	#print("Autotile: Cleared all autotile state for new texture loading")
