@tool
class_name TilesetPanel
extends PanelContainer

## UI panel for tileset loading and tile selection
## Responsibility: Texture display, tile selection, file loading

## Tiling mode enum - determines whether manual or auto tiling is active
enum TilingMode {
	MANUAL = 0,
	AUTOTILE = 1,
}

# Emitted when user selects a single tile
signal tile_selected(uv_rect: Rect2)

# Emitted when user selects multiple tiles (Phase 2)
signal multi_tile_selected(uv_rects: Array[Rect2], anchor_index: int)

# Emitted when tileset texture is loaded
signal tileset_loaded(texture: Texture2D)

# Emitted when orientation changes
signal orientation_changed(orientation: int)

# Emitted when placement mode changes
signal placement_mode_changed(mode: int)

# Emitted when show plane grids checkbox is toggled
signal show_plane_grids_changed(enabled: bool)

# Emitted when cursor step size changes
signal cursor_step_size_changed(step_size: float)

# Emitted when grid snap size changes
signal grid_snap_size_changed(snap_size: float)

# Emitted when grid snap size changes
signal mesh_mode_selection_changed(mesh_mode: GlobalConstants.MeshMode)

# Emitted when grid size changes (requires rebuild)
signal grid_size_changed(new_size: float)

# Emitted when texture filter mode changes
signal texture_filter_changed(filter_mode: int)

# Emitted when alpha threshold slider changes
signal alpha_threshold_changed(threshold: float)

# Emitted when Simple Collision button is pressed (No alpha awareness)
signal create_collision_requested(bake_mode: MeshBakeManager.BakeMode)

# Emitted when Bake to Scene button is pressed
# signal simple_bake_mesh_requested()

# Emitted when Merge and Bake to Scene button is pressed
signal _bake_mesh_requested(bake_mode: MeshBakeManager.BakeMode)

# Emitted when Clear all Tiles button is pressed
signal clear_tiles_requested()

# Emitted when Show Debug button is pressed
signal show_debug_info_requested()

# === AUTOTILE SIGNALS ===

# Emitted when tiling mode changes (MANUAL or AUTOTILE)
signal tiling_mode_changed(mode: TilingMode)

# Emitted when autotile TileSet is loaded or changed
signal autotile_tileset_changed(tileset: TileSet)

# Emitted when user selects a terrain for autotile painting
signal autotile_terrain_selected(terrain_id: int)

# Emitted when TileSet content changes (terrains, peering bits) - triggers engine rebuild
signal autotile_data_changed()

# Emitted when user confirms texture change that requires clearing the TileSet
signal clear_autotile_requested()

# Node references (using unique names %)
@onready var load_texture_button: Button = %LoadTextureButton
@onready var texture_path_label: Label = %TexturePathLabel
@onready var tile_size_x: SpinBox = %TileSizeX
@onready var tile_size_y: SpinBox = %TileSizeY
@onready var tileset_display: TextureRect = %TilesetDisplay
@onready var load_texture_dialog: FileDialog = %LoadTextureDialog
@onready var selection_highlight: ColorRect = %SelectionHighlight
@onready var scroll_container: ScrollContainer = %TileSetScrollContainer
@onready var mesh_mode_dropdown: OptionButton = %MeshModeDropdown
@onready var export_and_collision_tab: VBoxContainer = %Export_Collision
@onready var manual_tiling_tab: VBoxContainer = %Manual_Tiling
@onready var auto_tile_tab: VBoxContainer = %"Auto_Tiling"
@onready var cursor_position_label: Label = %CursorPositionLabel
@onready var show_plane_grids_checkbox: CheckBox = %ShowPlaneGridsCheckbox
@onready var cursor_step_dropdown: OptionButton = %CursorStepDropdown
@onready var grid_snap_dropdown: OptionButton = %GridSnapDropdown
@onready var grid_size_spinbox: SpinBox = %GridSizeSpinBox
@onready var grid_size_confirm_dialog: ConfirmationDialog = %GridSizeConfirmDialog
@onready var _texture_change_warning_dialog: ConfirmationDialog = %TextureChangeWarningDialog
@onready var texture_filter_dropdown: OptionButton = %TextureFilterDropdown

@onready var create_collision_button: Button = %CreateCollisionBtn 
@onready var collision_check_box: CheckBox = %CollisionCheckBox

@onready var bake_alpha_check_box: CheckBox = %BakeAlphaCheckBox
@onready var bake_mesh_button: Button = %BakeMeshButton
@onready var clear_all_tiles_button: Button = %ClearAllTilesButton
@onready var show_debug_button: Button = %ShowDebugInfo

# Autotile tab reference


# TabContainer reference for detecting tab changes
@onready var _tab_container: TabContainer = $TabContainer

# State
var current_node: TileMapLayer3D = null  # Reference to currently edited node
var _is_loading_from_node: bool = false  # Prevents signal loops during UI updates
var current_texture: Texture2D = null
var _tile_size: Vector2i = GlobalConstants.DEFAULT_TILE_SIZE
var selected_tile_coords: Vector2i = Vector2i(0, 0)
var has_selection: bool = false
var _pending_grid_size: float = 0.0  # Store pending grid size change during confirmation

# Zoom state
var _current_zoom: float = GlobalConstants.TILESET_DEFAULT_ZOOM
var _original_texture_size: Vector2 = Vector2.ZERO
var _previous_texture: Texture2D = null  # For detecting texture changes

# Tiling mode state (MANUAL or AUTOTILE)
var _current_tiling_mode: TilingMode = TilingMode.MANUAL

# Multi-tile selection state (Phase 2)
var _is_dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _selected_tiles: Array[Rect2] = []  # Multiple UV rects for multi-selection
# MAX_SELECTION_SIZE now uses GlobalConstants.PREVIEW_POOL_SIZE


## Returns current tile size (used by AutotileTab for TileSet creation)
func get_tile_size() -> Vector2i:
	return _tile_size


## Returns the currently loaded tileset texture (or null if none)
## Used by AutotileTab to auto-populate new TileSets with atlas source
func get_tileset_texture() -> Texture2D:
	return current_texture


## Updates the tileset texture and refreshes the Manual tab UI
## Called when Auto-Tiling loads a TileSet with atlas texture
func set_tileset_texture(texture: Texture2D) -> void:
	if texture == current_texture:
		return  # No change needed

	current_texture = texture
	if tileset_display:
		tileset_display.texture = texture
		if texture:
			# Set TextureRect to actual texture size for pixel-perfect display
			tileset_display.custom_minimum_size = texture.get_size()
			tileset_display.size = texture.get_size()

	# Reset selection when texture changes
	clear_selection()


func _ready() -> void:
	#if not Engine.is_editor_hint(): return
	# Connect signals immediately - @onready vars are already assigned
	# Deferring caused tile selection to fail on first node load
	_connect_signals()
	_load_default_ui_values()
	export_and_collision_tab.hide()
	manual_tiling_tab.show()
	mesh_mode_dropdown.selected = 0

func _load_default_ui_values() -> void:
	#MeshMode items
	mesh_mode_dropdown.clear()
	for mesh_mode in GlobalConstants.MeshMode:
		mesh_mode_dropdown.add_item(mesh_mode)

func _connect_signals() -> void:
	#print("TilesetPanel: Connecting signals...")
	if load_texture_button and not load_texture_button.pressed.is_connected(_on_load_texture_pressed):
		load_texture_button.pressed.connect(_on_load_texture_pressed)
		#print("   Load button connected")
	if load_texture_dialog and not load_texture_dialog.file_selected.is_connected(_on_texture_selected):
		load_texture_dialog.file_selected.connect(_on_texture_selected)
		#print("   File dialog connected")
	if tile_size_x and not tile_size_x.value_changed.is_connected(_on_tile_size_changed):
		tile_size_x.value_changed.connect(_on_tile_size_changed)
		#print("   TileSizeX connected")
	if tile_size_y and not tile_size_y.value_changed.is_connected(_on_tile_size_changed):
		tile_size_y.value_changed.connect(_on_tile_size_changed)
		#print("   TileSizeY connected")

	# Connect tileset display signals
	if tileset_display:
		if not tileset_display.tile_drag_started.is_connected(_on_tile_drag_started):
			tileset_display.tile_drag_started.connect(_on_tile_drag_started)
			#print("   TilesetDisplay drag_started connected")
		if not tileset_display.tile_drag_updated.is_connected(_on_tile_drag_updated):
			tileset_display.tile_drag_updated.connect(_on_tile_drag_updated)
			#print("   TilesetDisplay drag_updated connected")
		if not tileset_display.tile_drag_ended.is_connected(_on_tile_drag_ended):
			tileset_display.tile_drag_ended.connect(_on_tile_drag_ended)
			#print("   TilesetDisplay drag_ended connected")
		if not tileset_display.zoom_requested.is_connected(_on_zoom_requested):
			tileset_display.zoom_requested.connect(_on_zoom_requested)
			#print("   TilesetDisplay zoom_requested connected")

	# Connect show plane grids checkbox
	if show_plane_grids_checkbox and not show_plane_grids_checkbox.toggled.is_connected(_on_show_plane_grids_toggled):
		show_plane_grids_checkbox.toggled.connect(_on_show_plane_grids_toggled)
		#print("   Show plane grids checkbox connected")

	# Connect cursor step dropdown
	if cursor_step_dropdown and not cursor_step_dropdown.item_selected.is_connected(_on_cursor_step_selected):
		cursor_step_dropdown.item_selected.connect(_on_cursor_step_selected)
		#print("   Cursor step dropdown connected")

	# Connect grid snap dropdown
	if grid_snap_dropdown and not grid_snap_dropdown.item_selected.is_connected(_on_grid_snap_selected):
		grid_snap_dropdown.item_selected.connect(_on_grid_snap_selected)
		#print("   Grid snap dropdown connected")

	# Connect grid size spinbox
	if grid_size_spinbox and not grid_size_spinbox.value_changed.is_connected(_on_grid_size_value_changed):
		grid_size_spinbox.value_changed.connect(_on_grid_size_value_changed)
		#print("   Grid size spinbox connected")

	# Connect grid size confirmation dialog
	if grid_size_confirm_dialog:
		if not grid_size_confirm_dialog.confirmed.is_connected(_on_grid_size_confirmed):
			grid_size_confirm_dialog.confirmed.connect(_on_grid_size_confirmed)
		if not grid_size_confirm_dialog.canceled.is_connected(_on_grid_size_canceled):
			grid_size_confirm_dialog.canceled.connect(_on_grid_size_canceled)
		#print("   Grid size confirmation dialog connected")

	# Connect texture change warning dialog (for clearing TileSet when loading new texture)
	if _texture_change_warning_dialog:
		if not _texture_change_warning_dialog.confirmed.is_connected(_on_texture_change_confirmed):
			_texture_change_warning_dialog.confirmed.connect(_on_texture_change_confirmed)

	# Connect texture filter dropdown
	if texture_filter_dropdown and not texture_filter_dropdown.item_selected.is_connected(_on_texture_filter_selected):
		texture_filter_dropdown.item_selected.connect(_on_texture_filter_selected)
		# Set default to Nearest (index 0)
		texture_filter_dropdown.selected = GlobalConstants.DEFAULT_TEXTURE_FILTER
		#print("   Texture filter dropdown connected (default: Nearest)")


	# Connect mesh_mode_dropdownGenerateCollisionButton
	if mesh_mode_dropdown and not mesh_mode_dropdown.item_selected.is_connected(_on_mesh_mode_selected):
		mesh_mode_dropdown.item_selected.connect(_on_mesh_mode_selected)
		#print("   Mesh Mode dropdown connected")

	if create_collision_button and not create_collision_button.pressed.is_connected(_on_create_collision_button_pressed):
		create_collision_button.pressed.connect(_on_create_collision_button_pressed)
		#print("   Generate collision button connected")

	if bake_mesh_button and not bake_mesh_button.pressed.is_connected(_on_bake_mesh_button_pressed):
		bake_mesh_button.pressed.connect(_on_bake_mesh_button_pressed)
		#print("   Bake Mesh to Scene button connected")

	if clear_all_tiles_button:
		clear_all_tiles_button.pressed.connect(func(): clear_tiles_requested.emit() )
		#print("   Clear tiles button connected")

	if show_debug_button:
		show_debug_button.pressed.connect(func(): show_debug_info_requested.emit() )
		#print("   Show Debug button connected")

	# Connect tab container for tiling mode changes
	if _tab_container and not _tab_container.tab_changed.is_connected(_on_tab_changed):
		_tab_container.tab_changed.connect(_on_tab_changed)
		#print("   Tab container tab_changed connected")

	# Connect AutotileTab signals
	if auto_tile_tab:
		if not auto_tile_tab.tileset_changed.is_connected(_on_autotile_tileset_changed):
			auto_tile_tab.tileset_changed.connect(_on_autotile_tileset_changed)
			#print("   AutotileTab tileset_changed connected")
		if not auto_tile_tab.terrain_selected.is_connected(_on_autotile_terrain_selected):
			auto_tile_tab.terrain_selected.connect(_on_autotile_terrain_selected)
			#print("   AutotileTab terrain_selected connected")
		if not auto_tile_tab.tileset_data_changed.is_connected(_on_autotile_data_changed):
			auto_tile_tab.tileset_data_changed.connect(_on_autotile_data_changed)
			#print("   AutotileTab tileset_data_changed connected")

	#print("TilesetPanel: Signal connections complete")


## Sets the active node and loads its settings into the UI
## This is called by the plugin when a TileMapLayer3D node is selected
func set_active_node(node: TileMapLayer3D) -> void:
	# Disconnect from old node's settings
	if current_node and current_node.settings:
		if current_node.settings.changed.is_connected(_on_node_settings_changed):
			current_node.settings.changed.disconnect(_on_node_settings_changed)

	current_node = node

	# Connect to new node's settings and load them
	if current_node and current_node.settings:
		if not current_node.settings.changed.is_connected(_on_node_settings_changed):
			current_node.settings.changed.connect(_on_node_settings_changed)
		_load_settings_to_ui(current_node.settings)
	else:
		_clear_ui()

	#print("TilesetPanel: Active node set to ", node.name if node else "null")

## Called when node's settings Resource changes externally (e.g., via Inspector)
## IMPORTANT: Skip reload if WE triggered the change (prevents circular reload)
func _on_node_settings_changed() -> void:
	# Skip if we're currently saving TO settings (our own change)
	# This prevents the circular: UI change → save → settings.changed → reload → breaks UI
	if _is_loading_from_node:
		return
	if current_node and current_node.settings:
		_load_settings_to_ui(current_node.settings)

## Loads settings from Resource to UI controls
func _load_settings_to_ui(settings: TileMapLayerSettings) -> void:
	_is_loading_from_node = true  # Prevent signal loops

	# Load tileset configuration
	if settings.tileset_texture:
		current_texture = settings.tileset_texture
		if tileset_display:
			tileset_display.texture = current_texture
			# Cache original texture size for zoom calculations
			_original_texture_size = current_texture.get_size()

			# Only reset zoom if texture actually changed
			# Preserves view when switching between nodes with same texture
			var texture_changed: bool = (_previous_texture != current_texture)
			if texture_changed:
				_reset_zoom_and_pan()
				_previous_texture = current_texture
			else:
				# Restore saved zoom with manual scaling
				if not Engine.is_editor_hint(): return
				_current_zoom = settings.tileset_zoom
				var zoomed_size: Vector2 = _original_texture_size * _current_zoom
				tileset_display.custom_minimum_size = zoomed_size
				tileset_display.size = zoomed_size
				#print("Restored zoom: %.0f%%" % [_current_zoom * 100.0])
		if texture_path_label:
			texture_path_label.text = settings.tileset_texture.resource_path.get_file()
	else:
		_clear_texture_ui()

	# Load tile size
	_tile_size = settings.tile_size
	if tile_size_x:
		tile_size_x.value = settings.tile_size.x
	if tile_size_y:
		tile_size_y.value = settings.tile_size.y

	# Load tile selection (restore previously selected tile)
	# IMPORTANT: Recalculate UV rects based on CURRENT tile size
	# Tile size may have changed since selection was saved
	if settings.selected_tiles.size() > 0:
		# Multi-tile selection - recalculate each UV rect with current tile size
		_selected_tiles.clear()
		for old_uv in settings.selected_tiles:
			# Get tile coordinates from old UV (using old tile size from settings)
			var tile_coords: Vector2i = Vector2i(
				int(old_uv.position.x / settings.tile_size.x),
				int(old_uv.position.y / settings.tile_size.y)
			)
			# Recalculate UV rect with CURRENT tile size
			var new_uv: Rect2 = Rect2(
				Vector2(tile_coords) * Vector2(_tile_size),
				Vector2(_tile_size)
			)
			_selected_tiles.append(new_uv)
		has_selection = true
		_update_selection_highlight()
	elif settings.selected_tile_uv.size != Vector2.ZERO:
		# Single tile selection - recalculate UV rect with current tile size
		_selected_tiles.clear()
		# Get tile coordinates from saved UV (using old tile size from settings)
		if settings.tile_size.x > 0 and settings.tile_size.y > 0:
			selected_tile_coords = Vector2i(
				int(settings.selected_tile_uv.position.x / settings.tile_size.x),
				int(settings.selected_tile_uv.position.y / settings.tile_size.y)
			)
			# Recalculate UV rect with CURRENT tile size
			var new_uv: Rect2 = Rect2(
				Vector2(selected_tile_coords) * Vector2(_tile_size),
				Vector2(_tile_size)
			)
			_selected_tiles.append(new_uv)
			has_selection = true
			_update_selection_highlight()
		else:
			# Can't restore without valid tile size
			has_selection = false
	else:
		# No selection
		_selected_tiles.clear()
		has_selection = false
		if selection_highlight:
			selection_highlight.visible = false

	# Load grid configuration
	if grid_size_spinbox:
		grid_size_spinbox.value = settings.grid_size

	# Load cursor step size from settings (per-node persistence)
	if cursor_step_dropdown:
		var step_index: int = GlobalConstants.CURSOR_STEP_OPTIONS.find(settings.cursor_step_size)
		if step_index >= 0:
			cursor_step_dropdown.selected = step_index
		else:
			# Fallback if saved value not in dropdown options
			var default_index: int = GlobalConstants.CURSOR_STEP_OPTIONS.find(GlobalConstants.DEFAULT_CURSOR_STEP_SIZE)
			cursor_step_dropdown.selected = default_index if default_index >= 0 else 0

	# Load grid snap size from settings (per-node persistence)
	if grid_snap_dropdown:
		var snap_index: int = GlobalConstants.GRID_SNAP_OPTIONS.find(settings.grid_snap_size)
		if snap_index >= 0:
			grid_snap_dropdown.selected = snap_index
		else:
			# Fallback if saved value not in dropdown options
			var default_index: int = GlobalConstants.GRID_SNAP_OPTIONS.find(1.0)
			grid_snap_dropdown.selected = default_index if default_index >= 0 else 0

	# Load texture filter
	if texture_filter_dropdown:
		texture_filter_dropdown.selected = settings.texture_filter_mode

	# Load autotile configuration
	if auto_tile_tab:
		# Load the TileSet for this specific node (may be null for new nodes)
		auto_tile_tab.set_tileset(settings.autotile_tileset)
		# Select the saved terrain if any
		if settings.autotile_tileset and settings.autotile_active_terrain >= 0:
			auto_tile_tab.select_terrain(settings.autotile_active_terrain)

	# Load tiling mode (restore correct tab)
	_current_tiling_mode = settings.tiling_mode as TilingMode
	if _tab_container:
		# Find the correct tab index based on tiling mode
		var target_tab_index: int = 0  # Default to Manual tab
		if _current_tiling_mode == TilingMode.AUTOTILE:
			# Find Auto_Tiling tab index
			for i in range(_tab_container.get_tab_count()):
				if _tab_container.get_tab_title(i) == auto_tile_tab.name:
					target_tab_index = i
					break
		_tab_container.current_tab = target_tab_index

	# Load mesh mode
	if mesh_mode_dropdown:
		mesh_mode_dropdown.selected = settings.mesh_mode

	# Load collision configuration

	_is_loading_from_node = false

	# Emit signals to update cursor/placement manager with loaded values from settings
	cursor_step_size_changed.emit(settings.cursor_step_size)
	grid_snap_size_changed.emit(settings.grid_snap_size)
	grid_size_changed.emit(settings.grid_size)



	# print("TilesetPanel: Loaded settings from node and updated cursor/placement")

## Saves UI changes back to node's settings Resource
func _save_ui_to_settings() -> void:
	if not current_node or not current_node.settings or _is_loading_from_node:
		return

	# Set flag to prevent settings.changed from triggering a reload
	# This prevents circular: save → settings.changed → reload → breaks UI state
	_is_loading_from_node = true

	# Save tileset configuration
	current_node.settings.tileset_texture = current_texture
	current_node.settings.tile_size = _tile_size
	if texture_filter_dropdown:
		current_node.settings.texture_filter_mode = texture_filter_dropdown.selected

	# Save tile selection (for restoration when switching nodes)
	if _selected_tiles.size() > 1:
		# Multi-tile selection
		current_node.settings.selected_tiles = _selected_tiles.duplicate()
		current_node.settings.selected_tile_uv = Rect2()  # Clear single selection
	elif _selected_tiles.size() == 1:
		# Single tile selection
		current_node.settings.selected_tile_uv = _selected_tiles[0]
		current_node.settings.selected_tiles = []  # Clear multi selection
	else:
		# No selection
		current_node.settings.selected_tile_uv = Rect2()
		current_node.settings.selected_tiles = []

	# Save grid configuration
	if grid_size_spinbox:
		current_node.settings.grid_size = grid_size_spinbox.value

	# Save cursor step size (per-node persistence)
	if cursor_step_dropdown and cursor_step_dropdown.selected >= 0:
		current_node.settings.cursor_step_size = GlobalConstants.CURSOR_STEP_OPTIONS[cursor_step_dropdown.selected]

	# Save grid snap size (per-node persistence)
	if grid_snap_dropdown and grid_snap_dropdown.selected >= 0:
		current_node.settings.grid_snap_size = GlobalConstants.GRID_SNAP_OPTIONS[grid_snap_dropdown.selected]

	# Reset flag - saving complete
	_is_loading_from_node = false


## Clears UI when no node is selected
func _clear_ui() -> void:
	_clear_texture_ui()
	if tile_size_x:
		tile_size_x.value = GlobalConstants.DEFAULT_TILE_SIZE.x
	if tile_size_y:
		tile_size_y.value = GlobalConstants.DEFAULT_TILE_SIZE.y
	if grid_size_spinbox:
		grid_size_spinbox.value = GlobalConstants.DEFAULT_GRID_SIZE

	# Reset cursor step and grid snap to 1.0
	if cursor_step_dropdown:
		var step_index: int = GlobalConstants.CURSOR_STEP_OPTIONS.find(1.0)
		if step_index >= 0:
			cursor_step_dropdown.selected = step_index
	if grid_snap_dropdown:
		var snap_index: int = GlobalConstants.GRID_SNAP_OPTIONS.find(1.0)
		if snap_index >= 0:
			grid_snap_dropdown.selected = snap_index

	if texture_filter_dropdown:
		texture_filter_dropdown.selected = GlobalConstants.DEFAULT_TEXTURE_FILTER

	# Clear autotile tab
	if auto_tile_tab:
		auto_tile_tab.set_tileset(null)

	#print("TilesetPanel: UI cleared")

## Clears texture-related UI elements
func _clear_texture_ui() -> void:
	current_texture = null
	if tileset_display:
		tileset_display.texture = null
	if texture_path_label:
		texture_path_label.text = "No texture loaded"
	if selection_highlight:
		selection_highlight.visible = false

# ==============================================================================
# TEXTURE LOADING
# ==============================================================================
func _on_load_texture_pressed() -> void:
	# Check if Auto-Tile TileSet exists - warn user it will be cleared
	var autotile_tab_node: AutotileTab = auto_tile_tab as AutotileTab
	if autotile_tab_node and autotile_tab_node.get_tileset() != null:
		# Show warning dialog - TileSet will be cleared
		if _texture_change_warning_dialog:
			_texture_change_warning_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_CONFIRM))
		return

	# No TileSet exists, proceed directly to file dialog
	if load_texture_dialog:
		load_texture_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_DEFAULT))


## Called when user confirms texture change warning (clears TileSet)
func _on_texture_change_confirmed() -> void:
	# Emit signal to clear all autotile state in plugin
	clear_autotile_requested.emit()

	# Now show the texture file dialog
	if load_texture_dialog:
		load_texture_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_DEFAULT))

func _on_texture_selected(path: String) -> void:
	var texture: Texture2D = load(path)
	if texture:
		current_texture = texture
		if tileset_display:
			tileset_display.texture = texture
			# Set TextureRect to actual texture size for pixel-perfect display
			var texture_size: Vector2 = texture.get_size()
			tileset_display.custom_minimum_size = texture_size
			tileset_display.size = texture_size

			# DON'T set container size - it needs to stay smaller than content for scrolling!
			# The container has custom_minimum_size = Vector2(200, 200) in the scene
			# If texture is larger than 200x200, ScrollContainer will show scrollbars

			#print("Texture size set to: ", texture_size)
		if texture_path_label:
			texture_path_label.text = path.get_file()

		# Save to node's settings Resource
		_save_ui_to_settings()

		# Emit signal for plugin (backward compatibility)
		tileset_loaded.emit(texture)
		#print("Tileset loaded: ", path)
	else:
		push_error("Failed to load texture: " + path)

func _on_tile_size_changed(value: float) -> void:
	#print("_on_tile_size_changed called with value: ", value)
	if tile_size_x and tile_size_y:
		_tile_size = Vector2i(
			int(tile_size_x.value),
			int(tile_size_y.value)
		)
		#print("Tile size changed: ", _tile_size)
		# Update selection highlight if we have a selection
		if has_selection:
			_update_selection_highlight()

		# Save to node's settings Resource
		_save_ui_to_settings()
	else:
		push_warning("TilesetPanel: tile_size_x or tile_size_y is null")


# ==============================================================================
# TilesetDisplay / Tile Selection INPUT EVENTS
# ==============================================================================

## Signal handlers for TilesetDisplay input events
func _on_zoom_requested(direction: int, focal_point: Vector2) -> void:
	# print("Zoom requested: direction=", direction, " focal=", focal_point)
	if direction > 0:
		_handle_zoom_in(focal_point)
	else:
		_handle_zoom_out(focal_point)

func _on_tile_drag_started(position: Vector2) -> void:
	# print("Drag started at event pos: ", position)
	_is_dragging = true
	# Convert to texture coordinates (scroll + zoom aware)
	_drag_start_pos = _screen_to_texture_coords(position)
	# print("  → Texture coords: ", _drag_start_pos)

func _on_tile_drag_updated(position: Vector2) -> void:
	if _is_dragging:
		# Convert to texture coordinates before updating selection
		var texture_pos: Vector2 = _screen_to_texture_coords(position)
		_update_drag_selection(texture_pos)

func _on_tile_drag_ended(position: Vector2) -> void:
	# print("Drag ended at event pos: ", position)
	if _is_dragging:
		_is_dragging = false
		# Convert to texture coordinates before finalizing
		var texture_pos: Vector2 = _screen_to_texture_coords(position)
		# print("  → Texture coords: ", texture_pos)
		_finalize_selection(texture_pos)

func _handle_tile_click(mouse_pos: Vector2) -> void:
	if not current_texture:
		return

	# Calculate which tile was clicked
	var tile_coords: Vector2i = Vector2i(
		int(mouse_pos.x / _tile_size.x),
		int(mouse_pos.y / _tile_size.y)
	)

	# Calculate UV rect in pixel coordinates
	var uv_rect: Rect2 = Rect2(
		Vector2(tile_coords) * Vector2(_tile_size),
		Vector2(_tile_size)
	)

	# Validate bounds
	var texture_size: Vector2 = current_texture.get_size()
	if uv_rect.position.x >= texture_size.x or uv_rect.position.y >= texture_size.y:
		return

	selected_tile_coords = tile_coords
	has_selection = true
	tile_selected.emit(uv_rect)

	#   Release UI focus so WASD input returns to 3D viewport
	# Without this, keyboard input stays trapped in the UI panel
	if tileset_display and tileset_display.has_focus():
		tileset_display.release_focus()

	# print("Tile selected at coords: ", tile_coords, " UV rect: ", uv_rect)

	# Update visual highlight
	_update_selection_highlight()

func _update_selection_highlight() -> void:
	if not has_selection or not selection_highlight:
		return

	# Show and position the highlight rectangle
	selection_highlight.visible = true

	# Multi-tile selection: expand highlight to cover all selected tiles
	if _selected_tiles.size() > 1:
		var min_pos: Vector2 = Vector2(INF, INF)
		var max_pos: Vector2 = Vector2(-INF, -INF)

		for uv_rect in _selected_tiles:
			min_pos.x = min(min_pos.x, uv_rect.position.x)
			min_pos.y = min(min_pos.y, uv_rect.position.y)
			max_pos.x = max(max_pos.x, uv_rect.position.x + uv_rect.size.x)
			max_pos.y = max(max_pos.y, uv_rect.position.y + uv_rect.size.y)

		# Position relative to TilesetDisplay parent (child coordinate system)
		selection_highlight.position = min_pos * _current_zoom
		selection_highlight.size = (max_pos - min_pos) * _current_zoom
		# print("Multi-tile selection highlight: ", _selected_tiles.size(), " tiles")
	else:
		# Single tile selection - scale by zoom
		var tile_pixel_pos: Vector2 = Vector2(selected_tile_coords) * Vector2(_tile_size)
		selection_highlight.position = tile_pixel_pos * _current_zoom
		selection_highlight.size = Vector2(_tile_size) * _current_zoom

	# print("Selection highlight updated: pos=", selection_highlight.position, " size=", selection_highlight.size)

## Clears tile selection (used when entering box erase mode)
func clear_selection() -> void:
	has_selection = false
	_selected_tiles.clear()
	selected_tile_coords = Vector2i(-1, -1)

	# Hide selection highlight
	if selection_highlight:
		selection_highlight.visible = false

## Snaps a pixel position to the tile grid (top-left corner of containing tile)
func _snap_to_tile_grid(pixel_pos: Vector2) -> Vector2:
	var tile_coords: Vector2i = Vector2i(
		int(pixel_pos.x / _tile_size.x),
		int(pixel_pos.y / _tile_size.y)
	)
	return Vector2(tile_coords) * Vector2(_tile_size)

## Updates drag selection visual during mouse motion
func _update_drag_selection(current_pos: Vector2) -> void:
	if not selection_highlight:
		return

	# Snap both positions to tile grid for aligned selection
	var grid_start: Vector2 = _snap_to_tile_grid(_drag_start_pos)
	var grid_current: Vector2 = _snap_to_tile_grid(current_pos)

	# Calculate selection rectangle from snapped positions
	var rect_min: Vector2 = Vector2(
		min(grid_start.x, grid_current.x),
		min(grid_start.y, grid_current.y)
	)
	var rect_max: Vector2 = Vector2(
		max(grid_start.x, grid_current.x) + _tile_size.x,  # Include full tile
		max(grid_start.y, grid_current.y) + _tile_size.y
	)

	# Show preview of selection area (grid-aligned, scaled by zoom)
	selection_highlight.visible = true
	selection_highlight.position = rect_min * _current_zoom
	selection_highlight.size = (rect_max - rect_min) * _current_zoom

## Finalizes selection when mouse is released
func _finalize_selection(end_pos: Vector2) -> void:
	if not current_texture:
		return

	# Snap both positions to tile grid first
	var grid_start: Vector2 = _snap_to_tile_grid(_drag_start_pos)
	var grid_end: Vector2 = _snap_to_tile_grid(end_pos)

	# Calculate selection rectangle from snapped positions
	var rect_min: Vector2 = Vector2(
		min(grid_start.x, grid_end.x),
		min(grid_start.y, grid_end.y)
	)
	var rect_max: Vector2 = Vector2(
		max(grid_start.x, grid_end.x),
		max(grid_start.y, grid_end.y)
	)

	# Convert to tile coordinates (already grid-snapped, so simple division)
	var tile_min: Vector2i = Vector2i(
		int(rect_min.x / _tile_size.x),
		int(rect_min.y / _tile_size.y)
	)
	var tile_max: Vector2i = Vector2i(
		int(rect_max.x / _tile_size.x),
		int(rect_max.y / _tile_size.y)
	)

	# Calculate number of tiles in selection
	var tile_count_x: int = tile_max.x - tile_min.x + 1
	var tile_count_y: int = tile_max.y - tile_min.y + 1
	var total_tiles: int = tile_count_x * tile_count_y

	# print("Selection: ", tile_min, " to ", tile_max, " = ", total_tiles, " tiles")

	# Single tile selection (click without drag or 1x1 area)
	if total_tiles == 1:
		_handle_single_tile_selection(tile_min)
		return

	# Multi-tile selection
	_handle_multi_tile_selection(tile_min, tile_max, total_tiles)

## Handles single tile selection (original behavior)
func _handle_single_tile_selection(tile_coords: Vector2i) -> void:
	# Calculate UV rect
	var uv_rect: Rect2 = Rect2(
		Vector2(tile_coords) * Vector2(_tile_size),
		Vector2(_tile_size)
	)

	# Validate bounds
	var texture_size: Vector2 = current_texture.get_size()
	if uv_rect.position.x >= texture_size.x or uv_rect.position.y >= texture_size.y:
		return

	selected_tile_coords = tile_coords
	has_selection = true
	_selected_tiles.clear()
	_selected_tiles.append(uv_rect)

	# Save tile selection to node's settings
	_save_ui_to_settings()

	tile_selected.emit(uv_rect)

	#   Release UI focus so WASD input returns to 3D viewport
	# Without this, keyboard input stays trapped in the UI panel
	if tileset_display and tileset_display.has_focus():
		tileset_display.release_focus()

	_update_selection_highlight()

	# print("Single tile selected: ", tile_coords)

## Handles multi-tile selection (new Phase 2 functionality)
func _handle_multi_tile_selection(tile_min: Vector2i, tile_max: Vector2i, total_tiles: int) -> void:
	# Build array of UV rects for all selected tiles
	_selected_tiles.clear()
	var texture_size: Vector2 = current_texture.get_size()
	var tiles_added: int = 0

	for y in range(tile_min.y, tile_max.y + 1):
		for x in range(tile_min.x, tile_max.x + 1):
			# Enforce selection limit - stop adding tiles once we hit the cap
			if tiles_added >= GlobalConstants.PREVIEW_POOL_SIZE:
				push_warning("TilesetPanel: Selection capped at %d tiles (tried to select %d)" % [GlobalConstants.PREVIEW_POOL_SIZE, total_tiles])
				break

			var tile_coords: Vector2i = Vector2i(x, y)
			var uv_rect: Rect2 = Rect2(
				Vector2(tile_coords) * Vector2(_tile_size),
				Vector2(_tile_size)
			)

			# Skip tiles outside texture bounds
			if uv_rect.position.x >= texture_size.x or uv_rect.position.y >= texture_size.y:
				continue

			_selected_tiles.append(uv_rect)
			tiles_added += 1

		# Break outer loop too if we hit the cap
		if tiles_added >= GlobalConstants.PREVIEW_POOL_SIZE:
			break

	if _selected_tiles.size() == 0:
		return

	selected_tile_coords = tile_min  # Store top-left for reference
	has_selection = true

	# Save tile selection to node's settings
	_save_ui_to_settings()

	# Emit multi-tile selection signal (anchor_index = 0 for top-left)
	multi_tile_selected.emit(_selected_tiles, 0)

	#   Release UI focus so WASD input returns to 3D viewport
	# Without this, keyboard input stays trapped in the UI panel
	if tileset_display and tileset_display.has_focus():
		tileset_display.release_focus()

	_update_selection_highlight()

	# print("Multi-tile selection: ", _selected_tiles.size(), " tiles selected")


# ==============================================================================
# General settings and UI event handlers
# ==============================================================================

func _on_show_plane_grids_toggled(enabled: bool) -> void:
	show_plane_grids_changed.emit(enabled)
	# print("Show plane grids: ", enabled)

func _on_cursor_step_selected(index: int) -> void:
	# Ignore if we're loading from node
	if _is_loading_from_node:
		return

	# Save to node's settings Resource
	_save_ui_to_settings()

	# Map dropdown indices to actual step values from GlobalConstants
	var step_size: float = GlobalConstants.CURSOR_STEP_OPTIONS[index]
	cursor_step_size_changed.emit(step_size)

func _on_grid_snap_selected(index: int) -> void:
	# Ignore if we're loading from node
	if _is_loading_from_node:
		return

	# Save to node's settings Resource
	_save_ui_to_settings()

	# Map dropdown indices to actual snap values from GlobalConstants
	var snap_size: float = GlobalConstants.GRID_SNAP_OPTIONS[index]
	grid_snap_size_changed.emit(snap_size)

func _on_mesh_mode_selected(index: int) -> void:
	# Ignore if we're loading from node
	if _is_loading_from_node:
		return

	# Save to node settings (single source of truth)
	if current_node and current_node.settings:
		current_node.settings.mesh_mode = index

	var mesh_mode_selected: GlobalConstants.MeshMode = index
	mesh_mode_selection_changed.emit(mesh_mode_selected)

func _on_grid_size_value_changed(new_value: float) -> void:
	#print("DEBUG: _on_grid_size_value_changed called: new_value=", new_value, ", _is_loading_from_node=", _is_loading_from_node, ", current_node=", current_node != null)

	#   Ignore if no node is selected yet (prevents dialog on initialization)
	if not current_node:
		#print("DEBUG: Ignoring grid size change - no node selected yet")
		return

	# Ignore if we're loading from node (prevents warning on node switch)
	if _is_loading_from_node:
		#print("DEBUG: Ignoring grid size change - loading from node")
		return

	# Only show warning if value actually changed from current node's setting
	if current_node.settings:
		var current_grid_size: float = current_node.settings.grid_size
		#print("DEBUG: Comparing new_value (", new_value, ") with current (", current_grid_size, ")")
		if abs(new_value - current_grid_size) < 0.001:
			#print("DEBUG: Same value, no warning needed")
			return  # Same value, no warning needed

	#print("DEBUG: Showing grid size confirmation dialog")
	# Store pending value and show confirmation dialog
	_pending_grid_size = new_value
	if grid_size_confirm_dialog:
		grid_size_confirm_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_CONFIRM))

	# Temporarily disable spinbox to prevent rapid changes during rebuild
	if grid_size_spinbox:
		grid_size_spinbox.editable = false

func _on_grid_size_confirmed() -> void:
	# User confirmed - emit the signal to change grid size
	#print("Grid size change confirmed: ", _pending_grid_size)

	# Save to node's settings Resource (this triggers rebuild in TileMapLayer3D)
	_save_ui_to_settings()

	# Emit signal for plugin (backward compatibility)
	grid_size_changed.emit(_pending_grid_size)

	# Re-enable spinbox after a short delay (rebuild should complete)
	if grid_size_spinbox:
		await get_tree().create_timer(0.5).timeout
		grid_size_spinbox.editable = true

func _on_grid_size_canceled() -> void:
	# User canceled - revert spinbox to current node's value
	#print("Grid size change canceled")
	if grid_size_spinbox:
		# Revert to current node's grid size
		if current_node and current_node.settings:
			grid_size_spinbox.value = current_node.settings.grid_size
		else:
			grid_size_spinbox.value = GlobalConstants.DEFAULT_GRID_SIZE
		grid_size_spinbox.editable = true

func _on_texture_filter_selected(index: int) -> void:
	# Save to node's settings Resource
	_save_ui_to_settings()

	# Emit signal for plugin (backward compatibility)
	texture_filter_changed.emit(index)
	#print("Texture filter changed to: ", GlobalConstants.TEXTURE_FILTER_OPTIONS[index])

func _on_bake_mesh_button_pressed() -> void:
	var bake_mode: MeshBakeManager.BakeMode = MeshBakeManager.BakeMode.ALPHA_AWARE if bake_alpha_check_box.button_pressed else MeshBakeManager.BakeMode.NORMAL
	_bake_mesh_requested.emit(bake_mode)
	#print("Bake to scene requested with mode: ", bake_mode)


func _on_create_collision_button_pressed() -> void:
	var bake_mode: MeshBakeManager.BakeMode = MeshBakeManager.BakeMode.ALPHA_AWARE if collision_check_box.button_pressed else MeshBakeManager.BakeMode.NORMAL
	create_collision_requested.emit(bake_mode)
	#print("Generate collision requested")


## Handles tab container tab changes to detect tiling mode switches
func _on_tab_changed(tab_index: int) -> void:
	if not Engine.is_editor_hint():
		return

	# Get tab name dynamically instead of hardcoded index
	var tab_name: String = _tab_container.get_tab_title(tab_index)

	var new_mode: TilingMode
	if tab_name == auto_tile_tab.name:
		new_mode = TilingMode.AUTOTILE
		# Refresh AutotileTab UI when switching to it (updates resource_path label after TileSet save)
		var autotile_tab_node: AutotileTab = auto_tile_tab as AutotileTab
		if autotile_tab_node:
			autotile_tab_node.refresh_path_label()
	else:
		new_mode = TilingMode.MANUAL

	if new_mode != _current_tiling_mode:
		_current_tiling_mode = new_mode

		# DON'T save to settings here - let the plugin's signal handler do it
		# This prevents the settings.changed cascade that causes flickering
		# The plugin's _on_tiling_mode_changed() will call _set_tiling_mode()

		tiling_mode_changed.emit(new_mode)
		#print("TilesetPanel: Tiling mode changed to ", "AUTOTILE" if new_mode == TilingMode.AUTOTILE else "MANUAL")


## Get the current tiling mode
func get_tiling_mode() -> TilingMode:
	return _current_tiling_mode


## Handle TileSet changes from AutotileTab
func _on_autotile_tileset_changed(tileset: TileSet) -> void:
	autotile_tileset_changed.emit(tileset)
	#print("TilesetPanel: Autotile TileSet changed")


## Handle terrain selection from AutotileTab
func _on_autotile_terrain_selected(terrain_id: int) -> void:
	autotile_terrain_selected.emit(terrain_id)
	#print("TilesetPanel: Autotile terrain selected: ", terrain_id)


## Handle TileSet data changes (terrains added/removed, peering bits painted)
func _on_autotile_data_changed() -> void:
	autotile_data_changed.emit()
	#print("TilesetPanel: Autotile data changed - forwarding signal")


## Updates cursor position display (supports fractional positions)
func update_cursor_position(grid_pos: Vector3) -> void:
	if cursor_position_label:
		cursor_position_label.text = "Cursor: (%.2f, %.2f, %.2f)" % [grid_pos.x, grid_pos.y, grid_pos.z]

# ==============================================================================
# TILESET ZOOM AND SCROLL FUNCTIONALITY 
# ==============================================================================

func _apply_zoom(new_zoom: float, focal_point: Vector2 = Vector2.ZERO) -> void:
	if not Engine.is_editor_hint(): return  # Editor-only guard
	if not tileset_display or not current_texture or not scroll_container:
		return

	# Clamp zoom to valid range using GlobalConstants
	new_zoom = clamp(new_zoom,
		GlobalConstants.TILESET_MIN_ZOOM,
		GlobalConstants.TILESET_MAX_ZOOM)

	# Calculate zoom ratio for scroll adjustment
	var zoom_ratio: float = new_zoom / _current_zoom

	# Store old scroll position BEFORE zoom
	var old_scroll: Vector2 = Vector2(
		scroll_container.scroll_horizontal,
		scroll_container.scroll_vertical
	)

	# Manual zoom: Scale TextureRect size directly
	var zoomed_size: Vector2 = _original_texture_size * new_zoom
	tileset_display.custom_minimum_size = zoomed_size
	tileset_display.size = zoomed_size

	_current_zoom = new_zoom

	# Adjust scroll position to keep focal_point stationary (zoom-to-cursor)
	# Formula: new_scroll = (old_scroll + focal_point) * zoom_ratio - focal_point
	var new_scroll: Vector2 = (old_scroll + focal_point) * zoom_ratio - focal_point

	# Apply new scroll position (deferred to let ScrollContainer update size)
	call_deferred("_set_scroll_position", new_scroll)

	# Save to settings for persistence
	_save_zoom_to_settings()

	# print("Zoom to cursor: %.0f%% at focal_point=%v" % [_current_zoom * 100.0, focal_point])

## Handles zoom in request (Ctrl+Wheel Up)
func _handle_zoom_in(focal_point: Vector2) -> void:
	if not Engine.is_editor_hint(): return
	var new_zoom: float = _current_zoom * GlobalConstants.TILESET_ZOOM_STEP
	_apply_zoom(new_zoom, focal_point)

## Handles zoom out request (Ctrl+Wheel Down)
func _handle_zoom_out(focal_point: Vector2) -> void:
	if not Engine.is_editor_hint(): return
	var new_zoom: float = _current_zoom / GlobalConstants.TILESET_ZOOM_STEP
	_apply_zoom(new_zoom, focal_point)

## Resets zoom to default (100%)
## Called when loading new texture or clicking Reset View button
func _reset_zoom_and_pan() -> void:
	if not Engine.is_editor_hint(): return

	_current_zoom = GlobalConstants.TILESET_DEFAULT_ZOOM

	if tileset_display and current_texture:
		var zoomed_size: Vector2 = _original_texture_size * _current_zoom
		tileset_display.custom_minimum_size = zoomed_size
		tileset_display.size = zoomed_size

	#print("Zoom reset to default (100%)")

## Saves current zoom level to node settings
## Called whenever zoom changes
func _save_zoom_to_settings() -> void:
	if not current_node or not current_node.settings:
		return

	# Prevent signal loop
	var was_loading: bool = _is_loading_from_node
	_is_loading_from_node = true

	current_node.settings.tileset_zoom = _current_zoom

	_is_loading_from_node = was_loading

## Sets scroll position in ScrollContainer
## Called deferred after zoom to let ScrollContainer update size first
func _set_scroll_position(scroll_pos: Vector2) -> void:
	if not scroll_container:
		return

	scroll_container.scroll_horizontal = int(scroll_pos.x)
	scroll_container.scroll_vertical = int(scroll_pos.y)

## Converts local mouse position to texture pixel coordinates
## Accounts for zoom level
## @param local_pos: Mouse position from InputEvent.position (TilesetDisplay local space)
## @return Texture coordinates, or Vector2(-1, -1) if out of bounds
func _screen_to_texture_coords(local_pos: Vector2) -> Vector2:
	if not tileset_display or not current_texture:
		return Vector2(-1, -1)

	# Convert from TilesetDisplay local space to texture pixel coordinates
	# Note: local_pos is already in TilesetDisplay's coordinate space (scroll-aware)
	# We only need to un-zoom to get texture coordinates
	var texture_coords: Vector2 = local_pos / _current_zoom

	# Validate bounds
	if texture_coords.x < 0 or texture_coords.y < 0 or \
	   texture_coords.x >= _original_texture_size.x or \
	   texture_coords.y >= _original_texture_size.y:
		return Vector2(-1, -1)

	return texture_coords

# ==============================================================================
# BOX ERASE SIGNAL HANDLERS
# ==============================================================================
# COMMENTED OUT HANDLERS (kept for reference)
# ==============================================================================

# func _on_generate_collision_pressed() -> void:
# 	create_collision_requested.emit()
# 	print("Generate collision requested")

# func _on_bake_to_scene_button_pressed() -> void:
# 	simple_bake_mesh_requested.emit()
# 	print("Bake to scene requested")

# func _on_clear_all_tiles_button_pressed() -> void:
# 	clear_tiles_requested.emit()
# 	print("Clear tiles requested")
