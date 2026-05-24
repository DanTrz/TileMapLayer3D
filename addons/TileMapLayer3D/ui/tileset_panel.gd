@tool
class_name TilesetPanel
extends PanelContainer

## UI panel for tileset loading and tile selection


#Grid and tile settings
@onready var texture_path_label: Label = %TexturePathLabel
@onready var tile_picker_size_label: Label = %TilePickerSizeLabel
@onready var tile_picker_size_x: SpinBox = %TilePickerSizeX
@onready var tile_picker_size_y: SpinBox = %TilePickerSizeY

@onready var tile_set_size_label: Label = %TileSetSizeLabel
@onready var tile_set_size_x: SpinBox = %TileSetSizeX
@onready var tile_set_size_y: SpinBox = %TileSetSizeY


@onready var tileset_display: TextureRect = %TilesetDisplay
@onready var load_texture_dialog: FileDialog = %LoadTextureDialog
@onready var selection_highlight: ColorRect = %SelectionHighlight
@onready var scroll_container: ScrollContainer = %TileSetScrollContainer
@onready var tile_set_zoom_hslider: HSlider = %TileSetZoomHSlider
@onready var enabled_arched_tiles_checkbox: CheckBox = %EnabledArchedTilesCheckbox

#Box/Prism mesh texture repeat
# @onready var box_texture_repeat_checkbox: CheckBox = %BoxTextureRepeatCheckbox
#Box/Prism mesh depth growth direction
# @onready var box_depth_inward_checkbox: CheckBox = %BoxDepthInwardCheckbox
#Box/Prism Z-fighting auto-resolve
@onready var box_z_fighting_checkbox: CheckBox = %BoxZFightingCheckbox
#SpriteMesh

@onready var manual_tiling_tab: HBoxContainer = %Manual_Tiling
@onready var auto_tile_tab: VBoxContainer = %"Auto_Tiling"
@onready var show_plane_grids_checkbox: CheckBox = %ShowPlaneGridsCheckbox
@onready var cursor_step_dropdown: OptionButton = %CursorStepDropdown
@onready var grid_snap_dropdown: OptionButton = %GridSnapDropdown
@onready var grid_size_spinbox: SpinBox = %GridSizeSpinBox
@onready var grid_size_confirm_dialog: ConfirmationDialog = %GridSizeConfirmDialog
@onready var _texture_change_warning_dialog: ConfirmationDialog = %TextureChangeWarningDialog
@onready var texture_filter_dropdown: OptionButton = %TextureFilterDropdown
@onready var pixel_inset_slider: HSlider = %PixelInsetSlider

@onready var create_collision_button: Button = %CreateCollisionBtn 
@onready var clear_collisions_button: Button = %ClearCollisionsButton 
@onready var collision_alpha_check_box: CheckBox = %CollisionAlphaCheckBox
@onready var backface_collision_check_box: CheckBox = %BackfaceCollisionCheckBox
@onready var save_collision_external_check_box: CheckBox = %SaveCollisionExternally

@onready var bake_alpha_check_box: CheckBox = %BakeAlphaCheckBox
@onready var bake_mesh_button: Button = %BakeMeshButton
@onready var clear_all_tiles_button: Button = %ClearAllTilesButton
@onready var show_debug_button: Button = %ShowDebugInfo
# @onready var autotile_mesh_dropdown: OptionButton = %AutoTileModeDropdown
@onready var _tab_container: TabContainer = $TabContainer

#UV MOde Tile Select
@onready var tile_uvmode_dropdown: OptionButton = %TileUVModeDropdown
@onready var tile_set_section_label: Label = %TileSetSectionLabel
@onready var tile_set_path_label: Label = %TileSetPathLabel


@onready var manual_mode_ui: VBoxContainer = %ManualModeUI
@onready var manual_tab_common_ui: VBoxContainer = %ManualTabCommonUI
@onready var animated_tile_manager: AnimatedTileManager = %AnimatedTileManager


#Manual Tile TIleSet Button
@onready var load_texture_button: Button = %LoadTextureButton
#AutoTile UI Buttons
@onready var load_tile_set_button: Button = %LoadTileSetButton
@onready var save_tileset_button: Button = %SaveTileSetButton
@onready var open_editor_button: Button = %OpenEditorButton
@onready var add_terrain_button: Button = %AddTerrainButton
@onready var remove_terrain_button: Button = %RemoveTerrainButton
@onready var terrain_name_input: LineEdit = %TerrainNameInput


# Emitted when user selects a single tile
signal tile_selected(uv_rect: Rect2)
# Emitted when user selects multiple tiles
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
# Emitted when BOX/PRISM texture repeat mode changes (DEFAULT or REPEAT)
# signal texture_repeat_mode_changed(mode: int)
# Emitted when BOX/PRISM depth growth direction changes (OUTWARD or INWARD)
# signal depth_growth_mode_changed(mode: int)
# Emitted when BOX/PRISM Z-fighting auto-resolve toggle changes
signal box_z_fighting_changed(enabled: bool)
# Emitted when grid size changes (requires rebuild)
signal grid_size_changed(new_size: float)
# Emitted when texture filter mode changes
signal texture_filter_changed(filter_mode: int)
# Emitted when pixel inset value changes (shader UV clamping)
signal pixel_inset_changed(value: float)
# Emitted when Simple Collision button is pressed (No alpha awareness)
signal create_collision_requested(bake_mode: GlobalConstants.BakeMode, backface_collision: bool, save_external_collision: bool)
# Emitted when Clear Collisions button is pressed
signal clear_collisions_requested()
# Emitted when Merge and Bake to Scene button is pressed
signal _bake_mesh_requested(bake_mode: GlobalConstants.BakeMode)
# Emitted when Clear all Tiles button is pressed
signal clear_tiles_requested()
# Emitted when Show Debug button is pressed
signal show_debug_info_requested()
# --- Autotile Signals ---
# Emitted when autotile TileSet is loaded or changed
signal autotile_tileset_changed(tileset: TileSet)
# Emitted when user selects a terrain for autotile painting
signal autotile_terrain_selected(terrain_id: int)
# Emitted when TileSet content changes (terrains, peering bits) - triggers engine rebuild
signal autotile_data_changed()
# Emitted when user confirms texture change that requires clearing the TileSet
# (both manual + autotile, since they now share one TileSet under settings.tileset).
signal clear_tileset_requested()


# State
var current_tilemap3d_node: TileMapLayer3D = null  # Reference to currently edited node
var _is_loading_from_node: bool = false  # Prevents signal loops during UI updates
var current_texture: Texture2D = null
# SelectionManager reference - UI subscribes to this for selection state
var _selection_manager: SelectionManager = null
var _tile_size: Vector2i = GlobalConstants.DEFAULT_TILE_SIZE
var selected_tile_coords: Vector2i = Vector2i(0, 0)
var has_selection: bool = false
var _pending_grid_size: float = 0.0  # Store pending grid size change during confirmation
# Zoom state
var _current_zoom: float = GlobalConstants.TILESET_DEFAULT_ZOOM
var _is_updating_zoom: bool = false  # Prevents slider ↔ zoom feedback loop
var _previous_texture: Texture2D = null  # For detecting texture changes


var _current_tiling_mode: GlobalConstants.MainAppMode = GlobalConstants.MainAppMode.MANUAL  # Default to MANUAL, can be changed by UI or node settings

# Multiple UV rects for multi-selection (managed by TilesetDisplay)
var _selected_tiles: Array[Rect2] = []

func _ready() -> void:
	
	_connect_signals()
	manual_tiling_tab.show()
	set_tiling_mode_from_external(GlobalConstants.MainAppMode.MANUAL)
	set_ui_theme_scale()
	initialize_animated_tile_manager()

func set_ui_theme_scale() -> void:
	var ui_scale: float = GlobalUtil.get_editor_ui_scale()
	tile_picker_size_x.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	tile_picker_size_y.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	terrain_name_input.add_theme_font_size_override("font_size", int(10 * ui_scale))

	texture_path_label.label_settings.font_size = int(10 * ui_scale)
	tile_picker_size_label.label_settings.font_size = int(10 * ui_scale)
	tile_set_path_label.label_settings.font_size = int(10 * ui_scale)
	tile_set_section_label.label_settings.font_size = int(10 * ui_scale)
	tile_set_size_x.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	tile_set_size_y.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	tile_set_size_label.label_settings.font_size = int(10 * ui_scale)


	GlobalUtil.apply_button_theme(load_tile_set_button, "Load", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)
	GlobalUtil.apply_button_theme(load_texture_button, "New", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)
	GlobalUtil.apply_button_theme(save_tileset_button, "Save", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)
	GlobalUtil.apply_button_theme(open_editor_button, "TileSet", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)
	GlobalUtil.apply_button_theme(auto_tile_tab.open_tileset_editor_button, "TileSet", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)
	
	GlobalUtil.apply_button_theme(add_terrain_button, "Add", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE) 
	GlobalUtil.apply_button_theme(remove_terrain_button, "Remove", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE) 


	
func _connect_signals() -> void:
	#print("TilesetPanel: Connecting signals...")
	if load_texture_button and not load_texture_button.pressed.is_connected(_on_load_texture_pressed):
		load_texture_button.pressed.connect(_on_load_texture_pressed)
		#print("   Load button connected")
	if load_texture_dialog and not load_texture_dialog.file_selected.is_connected(_on_texture_selected):
		load_texture_dialog.file_selected.connect(_on_texture_selected)
		#print("   File dialog connected")
	# Picker grid spinboxes — drive `settings.picker_tile_size` only.
	if tile_picker_size_x and not tile_picker_size_x.value_changed.is_connected(_on_tile_picker_size_changed):
		tile_picker_size_x.value_changed.connect(_on_tile_picker_size_changed)
	if tile_picker_size_y and not tile_picker_size_y.value_changed.is_connected(_on_tile_picker_size_changed):
		tile_picker_size_y.value_changed.connect(_on_tile_picker_size_changed)

	# TileSet authoritative tile-size spinboxes — drive `settings.tileset.tile_size`
	# and rebuild the active atlas grid around the requested region size.
	if tile_set_size_x and not tile_set_size_x.value_changed.is_connected(_on_tile_set_size_changed):
		tile_set_size_x.value_changed.connect(_on_tile_set_size_changed)
	if tile_set_size_y and not tile_set_size_y.value_changed.is_connected(_on_tile_set_size_changed):
		tile_set_size_y.value_changed.connect(_on_tile_set_size_changed)

	if tile_uvmode_dropdown:
		if not tile_uvmode_dropdown.item_selected.is_connected(_on_tile_uvmode_selected):
			tile_uvmode_dropdown.item_selected.connect(_on_tile_uvmode_selected)

	# Selection handled internally, but connect to corner editing signal for POINTS mode
	if tileset_display:
		if not tileset_display.select_vertices_data_changed.is_connected(_on_select_vertices_data_changed):
			tileset_display.select_vertices_data_changed.connect(_on_select_vertices_data_changed)

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

	# Connect pixel inset slider
	if pixel_inset_slider and not pixel_inset_slider.value_changed.is_connected(_on_pixel_inset_changed):
		pixel_inset_slider.value_changed.connect(_on_pixel_inset_changed)

	if box_z_fighting_checkbox and not box_z_fighting_checkbox.toggled.is_connected(_on_box_z_fighting_checkbox_toggled):
		box_z_fighting_checkbox.toggled.connect(_on_box_z_fighting_checkbox_toggled)
	# Initialize state based on default value
	box_z_fighting_checkbox.button_pressed = true
	_on_box_z_fighting_checkbox_toggled(true)  


	if create_collision_button and not create_collision_button.pressed.is_connected(_on_create_collision_button_pressed):
		create_collision_button.pressed.connect(_on_create_collision_button_pressed)
		#print("   Generate collision button connected")

	if clear_collisions_button:
		clear_collisions_button.pressed.connect(func(): clear_collisions_requested.emit() )

	if bake_mesh_button and not bake_mesh_button.pressed.is_connected(_on_bake_mesh_button_pressed):
		bake_mesh_button.pressed.connect(_on_bake_mesh_button_pressed)
		#print("   Bake Mesh to Scene button connected")

	if clear_all_tiles_button:
		clear_all_tiles_button.pressed.connect(func(): clear_tiles_requested.emit() )
		#print("   Clear tiles button connected")

	if show_debug_button:
		show_debug_button.pressed.connect(func(): show_debug_info_requested.emit() )
		#print("   Show Debug button connected")

	# Connect AutotileTab signals
	if auto_tile_tab:
		# if not auto_tile_tab.tileset_changed.is_connected(_on_autotile_tileset_changed):
		# 	auto_tile_tab.tileset_changed.connect(_on_autotile_tileset_changed)
			#print("   AutotileTab tileset_changed connected")
		if not auto_tile_tab.terrain_selected.is_connected(_on_autotile_terrain_selected):
			auto_tile_tab.terrain_selected.connect(_on_autotile_terrain_selected)
		# 	#print("   AutotileTab terrain_selected connected")
		# if not auto_tile_tab.tileset_data_changed.is_connected(_on_autotile_data_changed):
		# 	auto_tile_tab.tileset_data_changed.connect(_on_autotile_data_changed)
			#print("   AutotileTab tileset_data_changed connected")

		if not auto_tile_tab.open_tileset_editor_button.pressed.is_connected(_on_open_tileset_editor_pressed):
			auto_tile_tab.open_tileset_editor_button.pressed.connect(_on_open_tileset_editor_pressed)


	if tileset_display:
		if not tileset_display.zoom_requested.is_connected(_on_zoom_requested):
			tileset_display.zoom_requested.connect(_on_zoom_requested)

	if tile_set_zoom_hslider and not tile_set_zoom_hslider.value_changed.is_connected(_on_zoom_slider_changed):
		tile_set_zoom_hslider.value_changed.connect(_on_zoom_slider_changed)

	if enabled_arched_tiles_checkbox and not enabled_arched_tiles_checkbox.toggled.is_connected(_on_enabled_arched_tiles_toggled):
		enabled_arched_tiles_checkbox.toggled.connect(_on_enabled_arched_tiles_toggled)
	# Default to disabled
	enabled_arched_tiles_checkbox.button_pressed = false
	_on_enabled_arched_tiles_toggled(false)

	if not open_editor_button.pressed.is_connected(_on_open_tileset_editor_pressed):
		open_editor_button.pressed.connect(_on_open_tileset_editor_pressed)


	if not save_tileset_button.pressed.is_connected(_on_save_tileset_pressed):
		save_tileset_button.pressed.connect(_on_save_tileset_pressed)
	
	if load_tile_set_button and not load_tile_set_button.pressed.is_connected(_on_load_tileset_file_pressed):
		load_tile_set_button.pressed.connect(_on_load_tileset_file_pressed)


## Returns current TileSet tile size (used by AutotileTab for TileSet creation).
## The picker grid uses `_tile_size` directly and is intentionally separate.
func get_tile_size() -> Vector2i:
	if current_tilemap3d_node and current_tilemap3d_node.settings:
		return TileAtlasResolver.get_tile_size(current_tilemap3d_node.settings)
	if tile_set_size_x and tile_set_size_y:
		return Vector2i(int(tile_set_size_x.value), int(tile_set_size_y.value))
	return GlobalConstants.DEFAULT_TILE_SIZE


## Sets the SelectionManager reference and connects to its signals
## This makes TilesetPanel a subscriber to SelectionManager state changes
func set_selection_manager(manager: SelectionManager) -> void:
	# Disconnect from old manager
	if _selection_manager:
		if _selection_manager.selection_changed.is_connected(_on_selection_manager_changed):
			_selection_manager.selection_changed.disconnect(_on_selection_manager_changed)
		if _selection_manager.selection_cleared.is_connected(_on_selection_manager_cleared):
			_selection_manager.selection_cleared.disconnect(_on_selection_manager_cleared)

	_selection_manager = manager

	# Connect to new manager
	if _selection_manager:
		_selection_manager.selection_changed.connect(_on_selection_manager_changed)
		_selection_manager.selection_cleared.connect(_on_selection_manager_cleared)


## Called when SelectionManager's selection changes
## Updates UI to reflect the authoritative selection state
func _on_selection_manager_changed(tiles: Array[Rect2], anchor: int) -> void:
	# Update local state from SelectionManager (derived, not authoritative)
	_selected_tiles = tiles.duplicate()
	has_selection = tiles.size() > 0

	# Update visual highlight
	if has_selection:
		# Update selected_tile_coords for highlight positioning
		if _selected_tiles.size() > 0 and _tile_size.x > 0 and _tile_size.y > 0:
			selected_tile_coords = Vector2i(
				int(_selected_tiles[0].position.x / _tile_size.x),
				int(_selected_tiles[0].position.y / _tile_size.y)
			)
		tileset_display._update_tile_selection_preview()
	else:
		if selection_highlight:
			selection_highlight.visible = false


## Called when SelectionManager's selection is cleared
## Hides the highlight and clears local derived state
func _on_selection_manager_cleared() -> void:
	_selected_tiles.clear()
	has_selection = false
	selected_tile_coords = Vector2i(-1, -1)
	if selection_highlight:
		selection_highlight.visible = false


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
			_apply_zoom(GlobalConstants.TILESET_DEFAULT_ZOOM)


	# Reset selection when texture changes
	tileset_display.clear_selection()




## Sets the active node and loads its settings into the UI
## This is called by the plugin when a TileMapLayer3D node is selected
func set_active_node(node: TileMapLayer3D) -> void:
	# Disconnect from old node's settings
	if current_tilemap3d_node and current_tilemap3d_node.settings:
		if current_tilemap3d_node.settings.changed.is_connected(_on_node_settings_changed):
			current_tilemap3d_node.settings.changed.disconnect(_on_node_settings_changed)

	current_tilemap3d_node = node

	# Load settings FIRST so current_texture and _tile_size are available
	# before animated tile manager emits frame 0 selection signals
	if current_tilemap3d_node and current_tilemap3d_node.settings:
		if not current_tilemap3d_node.settings.changed.is_connected(_on_node_settings_changed):
			current_tilemap3d_node.settings.changed.connect(_on_node_settings_changed)
		_load_settings_to_ui(current_tilemap3d_node.settings)
	else:
		_clear_ui()

	# Initialize animated tiles AFTER settings are loaded (texture + tile_size ready)
	initialize_animated_tile_manager()

	#print("TilesetPanel: Active node set to ", node.name if node else "null")

## Called when node's settings Resource changes externally (e.g., via Inspector)
## IMPORTANT: Skip reload if WE triggered the change (prevents circular reload)
func _on_node_settings_changed() -> void:
	# Skip if we're currently saving TO settings (our own change)
	# This prevents the circular: UI change → save → settings.changed → reload → breaks UI
	if _is_loading_from_node:
		return
	if current_tilemap3d_node and current_tilemap3d_node.settings:
		_load_settings_to_ui(current_tilemap3d_node.settings)

## Loads settings from Resource to UI controls
func _load_settings_to_ui(settings: TileMapLayerSettings) -> void:
	_is_loading_from_node = true  # Prevent signal loops

	# Load tileset configuration via the unified resolver (prefers settings.tileset,
	# falls back to legacy tileset_texture during migration grace period).
	var active_texture: Texture2D = TileAtlasResolver.get_active_texture(settings)
	if active_texture:
		current_texture = active_texture
		if tileset_display:
			tileset_display.texture = current_texture
			var texture_changed: bool = (_previous_texture != current_texture)
			if texture_changed:
				_reset_zoom_and_pan()
				_previous_texture = current_texture
			else:
				_apply_zoom(settings.tileset_zoom)

		if texture_path_label:
			var path_source: Resource = settings.tileset if settings.tileset != null else active_texture
			texture_path_label.text = path_source.resource_path.get_file() if path_source.resource_path else ""
	else:
		_clear_texture_ui()

	# Picker grid size — independent of the TileSet's `tile_size`. Only drives the
	# selection grid overlay and freeform-drag snap step.
	_tile_size = settings.picker_tile_size
	if tile_picker_size_x:
		tile_picker_size_x.value = _tile_size.x
	if tile_picker_size_y:
		tile_picker_size_y.value = _tile_size.y

	# TileSet authoritative tile-size — sourced from the unified TileSet (or the
	# settings-level `tile_size` mirror while the unified resource isn't set up yet).
	_sync_tile_set_size_spinboxes(TileAtlasResolver.get_tile_size(settings))

	# Selection state is managed by SelectionManager (single source of truth)
	# UI updates via _on_selection_manager_changed/_on_selection_manager_cleared signals
	# Don't restore selection here - it causes UI/system desync on node switch
	_selected_tiles.clear()
	has_selection = false
	selected_tile_coords = Vector2i(-1, -1)
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

	# Load pixel inset
	if pixel_inset_slider:
		pixel_inset_slider.value = settings.pixel_inset_value

	# Load autotile configuration. The unified `settings.tileset` is the source of
	# truth; `autotile_tileset` is the legacy fallback during the migration grace period.
	if auto_tile_tab:
		var unified_tileset: TileSet = settings.tileset
		if unified_tileset == null:
			unified_tileset = settings.autotile_tileset  # legacy fallback
		# Populate AutotileTab's terrain list from the persisted TileSet.
		auto_tile_tab._current_tileset = unified_tileset
		auto_tile_tab.refresh_terrains()
		# Select the saved terrain if any (prefer new field)
		var restored_terrain: int = settings.active_terrain
		if restored_terrain < 0:
			restored_terrain = settings.autotile_active_terrain
		if unified_tileset and restored_terrain >= 0:
			auto_tile_tab.select_terrain(restored_terrain)


	# Load tiling mode (restore correct tab visibility)
	# Reuses set_tiling_mode_from_external() to properly show/hide tabs
	set_tiling_mode_from_external(settings.main_app_mode as GlobalConstants.MainAppMode)

	#Sync UV Tile selection mode
	if tile_uvmode_dropdown:
		tile_uvmode_dropdown.selected = settings.uv_selection_mode

	# Sync BOX/PRISM Z-fighting checkbox
	if box_z_fighting_checkbox:
		box_z_fighting_checkbox.button_pressed = settings.auto_resolve_box_z_fighting


	if settings.tileset:
		update_tileset_buttons_ui(true)
	else:
		update_tileset_buttons_ui(false)

	# Emit signals to update cursor/placement manager with loaded values from settings
	cursor_step_size_changed.emit(settings.cursor_step_size)
	grid_snap_size_changed.emit(settings.grid_snap_size)
	grid_size_changed.emit(settings.grid_size)

	#Arch tiles	enabled state
	enabled_arched_tiles_checkbox.button_pressed = settings.enable_arched_tiles if _on_enabled_arched_tiles_toggled else false 

	_is_loading_from_node = false



func initialize_animated_tile_manager() -> void:
	if animated_tile_manager:
		# Always sync current_tilemap3d_node first to prevent stale reference from previous node
		animated_tile_manager.current_node = current_tilemap3d_node

		if current_tilemap3d_node:
			# Restore the previously active animated tile selection (persisted in settings)
			var target_index: int = 0
			if current_tilemap3d_node.settings:
				var active_id: int = current_tilemap3d_node.settings.active_animated_tile
				if active_id >= 0:
					var found: int = current_tilemap3d_node.settings.animate_tiles_list.keys().find(active_id)
					if found >= 0:
						target_index = found

			animated_tile_manager.load_animated_tile_settings(current_texture, target_index)
		else:
			# No active node — clear UI to prevent showing stale data from previous node
			animated_tile_manager.deselect_all()
			animated_tile_manager._load_default_ui_values()

		# Connect frame 0 auto-selection signal (Signal Up: child emits, parent listens)
		if not animated_tile_manager.anim_tile_frame0_selected.is_connected(select_tiles_programmatically):
			animated_tile_manager.anim_tile_frame0_selected.connect(select_tiles_programmatically)
		

	# print("TilesetPanel: Loaded settings from node and updated cursor/placement")

## Saves UI changes back to node's settings Resource
func _save_ui_to_settings() -> void:
	if not current_tilemap3d_node or not current_tilemap3d_node.settings or _is_loading_from_node:
		return

	# Set flag to prevent settings.changed from triggering a reload
	# This prevents circular: save → settings.changed → reload → breaks UI state
	_is_loading_from_node = true

	# Save tileset configuration. Tile sizes are NOT touched here:
	#   • `settings.picker_tile_size` is written by `_on_tile_picker_size_changed`.
	#   • `settings.tile_size` is written by `_on_tile_set_size_changed`.
	# Both UI controls own their respective settings field directly.
	current_tilemap3d_node.settings.tileset_texture = current_texture
	if texture_filter_dropdown:
		current_tilemap3d_node.settings.texture_filter_mode = texture_filter_dropdown.selected
	if pixel_inset_slider:
		current_tilemap3d_node.settings.pixel_inset_value = pixel_inset_slider.value

	# Save tile selection (for restoration when switching nodes)
	if _selected_tiles.size() > 1:
		# Multi-tile selection
		current_tilemap3d_node.settings.selected_tiles = _selected_tiles.duplicate()
		current_tilemap3d_node.settings.selected_tile_uv = Rect2()  # Clear single selection
	elif _selected_tiles.size() == 1:
		# Single tile selection
		current_tilemap3d_node.settings.selected_tile_uv = _selected_tiles[0]
		current_tilemap3d_node.settings.selected_tiles = []  # Clear multi selection
	else:
		# No selection
		current_tilemap3d_node.settings.selected_tile_uv = Rect2()
		current_tilemap3d_node.settings.selected_tiles = []

	# Save grid configuration
	if grid_size_spinbox:
		current_tilemap3d_node.settings.grid_size = grid_size_spinbox.value

	# Save cursor step size (per-node persistence)
	if cursor_step_dropdown and cursor_step_dropdown.selected >= 0:
		current_tilemap3d_node.settings.cursor_step_size = GlobalConstants.CURSOR_STEP_OPTIONS[cursor_step_dropdown.selected]

	# Save grid snap size (per-node persistence)
	if grid_snap_dropdown and grid_snap_dropdown.selected >= 0:
		current_tilemap3d_node.settings.grid_snap_size = GlobalConstants.GRID_SNAP_OPTIONS[grid_snap_dropdown.selected]
	
	# Save UV Tile Selection Mode
	if tile_uvmode_dropdown:
		current_tilemap3d_node.settings.uv_selection_mode = tile_uvmode_dropdown.selected
	# Reset flag - saving complete
	_is_loading_from_node = false

	if _on_enabled_arched_tiles_toggled:
		current_tilemap3d_node.settings.enable_arched_tiles = enabled_arched_tiles_checkbox.button_pressed


## Clears UI when no node is selected
func _clear_ui() -> void:
	_clear_texture_ui()
	if tile_picker_size_x:
		tile_picker_size_x.value = GlobalConstants.DEFAULT_TILE_SIZE.x
	if tile_picker_size_y:
		tile_picker_size_y.value = GlobalConstants.DEFAULT_TILE_SIZE.y
	_sync_tile_set_size_spinboxes(GlobalConstants.DEFAULT_TILE_SIZE)
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

	if pixel_inset_slider:
		pixel_inset_slider.value = GlobalConstants.DEFAULT_PIXEL_INSET

	# Clear autotile tab
	#if auto_tile_tab:
		#auto_tile_tab.set_tileset(null)

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

# --- Texture Loading ---
func _on_load_texture_pressed() -> void:
	# Warn only if the existing TileSet has user-configured terrain data — loading
	# a new texture rebuilds `settings.tileset` from scratch and would discard it.
	# A blank/Quick-Setup TileSet (no terrain sets) doesn't need the prompt.
	if _existing_tileset_has_terrains() and _texture_change_warning_dialog:
		_texture_change_warning_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_CONFIRM))
		return

	# No terrain config to lose — proceed directly to file dialog
	if load_texture_dialog:
		load_texture_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_DEFAULT))


## Returns true if the unified `settings.tileset` has any terrain set configured.
## Used to gate the destructive-overwrite warning so users only see it when they
## actually have terrain data to lose, not on every Quick-Setup-loaded TileSet.
func _existing_tileset_has_terrains() -> bool:
	if current_tilemap3d_node == null or current_tilemap3d_node.settings == null:
		return false
	var ts: TileSet = current_tilemap3d_node.settings.tileset
	if ts == null:
		return false
	return ts.get_terrain_sets_count() > 0


## Called when user confirms texture change warning (clears TileSet)
func _on_texture_change_confirmed() -> void:
	# Emit signal to clear all TileSet state in plugin (manual + autotile share one TileSet)
	clear_tileset_requested.emit()

	# Now show the texture file dialog
	if load_texture_dialog:
		load_texture_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_DEFAULT))

func _on_texture_selected(path: String) -> void:
	var texture: Texture2D = load(path)
	if texture == null:
		push_error("TilesetPanel: Failed to load texture: " + path)
		return

	# Compressed textures fail in Godot's TileSet editor with "Cannot blit_rect".
	# Decompress in-place before we wrap them into a TileSet.
	if _is_texture_compressed(texture):
		var fixed: bool = await _auto_fix_texture_compression(texture)
		if fixed:
			texture = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)

	current_texture = texture
	if tileset_display:
		tileset_display.texture = texture
		_apply_zoom(GlobalConstants.TILESET_DEFAULT_ZOOM)
	if texture_path_label:
		texture_path_label.text = path.get_file()

	# Build a unified TileSet wrapping this texture so the Manual-tab Load
	# Texture flow now produces the same `settings.tileset` shape as Autotile mode.
	# Quick Setup parity with Godot 2D — user only sees a PNG picker, but they
	# get a real TileSet behind the scenes with default custom data initialized once.
	if current_tilemap3d_node and current_tilemap3d_node.settings:
		var tileset: TileSet = TileAtlasResolver.build_tileset_from_texture(texture, _tile_size)
		_apply_loaded_tileset(tileset)

	# Save to node's settings Resource (also writes legacy tileset_texture for now)
	_save_ui_to_settings()

	# Emit signal for plugin (backward compatibility)
	tileset_loaded.emit(texture)


## Unified end-state for both load paths (Manual texture-load and Autotile .tres-load).
## Connects the TileSet's changed signal, persists into settings, toggles button state,
## and emits autotile_tileset_changed so the plugin can rebuild the AutotileEngine.
func _apply_loaded_tileset(tileset: TileSet) -> void:
	if tileset == null:
		update_tileset_buttons_ui(false)
		return

	if not tileset.changed.is_connected(_on_tileset_resource_changed):
		tileset.changed.connect(_on_tileset_resource_changed)

	save_tileset_to_settings(tileset)
	# Push the TileSet into AutotileTab so its terrain list populates.
	# refresh_terrains() reads from AutotileTab._current_tileset, which is otherwise
	# only assigned via the (now-commented) set_tileset() setter.
	if auto_tile_tab:
		auto_tile_tab._current_tileset = tileset
		auto_tile_tab.refresh_terrains()
	update_tileset_buttons_ui(true)
	autotile_tileset_changed.emit(tileset)


func save_tileset_to_settings(new_tileset:TileSet) -> void:
	if not (current_tilemap3d_node and new_tileset):
		return
	var settings: TileMapLayerSettings = current_tilemap3d_node.settings
	settings.tileset = null
	settings.tileset = new_tileset
	settings.active_source_id = 0
	settings._settings_format_version = 1
	# Legacy mirror — older scenes (and any code path that still falls back to
	# `autotile_tileset` during the migration grace period) need to see the same
	# resource here. Keep mirrored until the grace period ends.
	settings.autotile_tileset = new_tileset
	settings.autotile_source_id = 0

func _on_open_tileset_editor_pressed() -> void:
	if current_tilemap3d_node.settings.tileset:
		# This opens Godot's native TileSet editor in the bottom panel
		var ei: Object = Engine.get_singleton("EditorInterface")
		if ei:
			ei.edit_resource(current_tilemap3d_node.settings.tileset)

func _on_load_tileset_file_pressed() -> void:
	var dialog := FileDialog.new()
	add_child(dialog)

	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.filters = ["*.tres,*.res ; TileSet Resources"]
	dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_DEFAULT))

	var path: String = await dialog.file_selected
	dialog.queue_free()

	var tileset := load(path) as TileSet
	if tileset == null:
		push_error("TilesetPanel: Failed to load TileSet from: " + path)
		update_tileset_buttons_ui(false)
		return

	TileAtlasResolver.initialize_custom_data_for_tileset(tileset)

	# Scan each atlas source for compressed textures and fix in-place. Same
	# rationale as _on_texture_selected — Godot's TileSet editor refuses to
	# paint peering bits on compressed atlases.
	for i: int in range(tileset.get_source_count()):
		var src_id: int = tileset.get_source_id(i)
		var source: TileSetSource = tileset.get_source(src_id)
		if source is TileSetAtlasSource:
			var atlas: TileSetAtlasSource = source as TileSetAtlasSource
			if atlas.texture and _is_texture_compressed(atlas.texture):
				var tex_path: String = atlas.texture.resource_path
				var fixed: bool = await _auto_fix_texture_compression(atlas.texture)
				if fixed and not tex_path.is_empty():
					atlas.texture = ResourceLoader.load(tex_path, "", ResourceLoader.CACHE_MODE_IGNORE)

	_apply_loaded_tileset(tileset)

func _on_save_tileset_pressed() -> void:
	if not current_tilemap3d_node.settings.tileset:
		push_warning("No TileSet Resource Loaded")
		return

	var dialog := FileDialog.new()
	add_child(dialog)

	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	# dialog.filters = ["*.tres,*.res ; TileSet Resources"]
	dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_DEFAULT))

	var save_file_path: String = await dialog.file_selected
	dialog.queue_free()

	if not save_file_path.ends_with(".tres") and not save_file_path.ends_with(".res"):
		save_file_path = save_file_path + ".res"

	var error: Error = ResourceSaver.save(current_tilemap3d_node.settings.tileset, save_file_path)
	if error != OK:
		push_error("TilesetPanel: Failed to save TileSet to '%s' (error %d)" % [save_file_path, error])
	

	var local_tileset: TileSet = load(save_file_path) as TileSet
	if local_tileset:
		_apply_loaded_tileset(local_tileset)

func update_tileset_buttons_ui(enabled: bool) -> void:
	if open_editor_button and save_tileset_button:
		open_editor_button.disabled = !enabled
		save_tileset_button.disabled = !enabled
	else:
		open_editor_button.disabled = !enabled
		save_tileset_button.disabled = !enabled

## Returns true if the texture uses a compressed format incompatible with
## Godot's TileSet editor peering-bit painting (DXT/BPTC/ETC/ASTC).
func _is_texture_compressed(texture: Texture2D) -> bool:
	if texture == null:
		return false
	var image: Image = texture.get_image()
	if image == null:
		return false
	var format: Image.Format = image.get_format()
	if format == Image.FORMAT_DXT1 or format == Image.FORMAT_DXT3 or format == Image.FORMAT_DXT5:
		return true
	if format == Image.FORMAT_ETC or format == Image.FORMAT_ETC2_R11 or format == Image.FORMAT_ETC2_R11S:
		return true
	if format == Image.FORMAT_ETC2_RG11 or format == Image.FORMAT_ETC2_RG11S:
		return true
	if format == Image.FORMAT_ETC2_RGB8 or format == Image.FORMAT_ETC2_RGBA8 or format == Image.FORMAT_ETC2_RGB8A1:
		return true
	if format == Image.FORMAT_ASTC_4x4 or format == Image.FORMAT_ASTC_4x4_HDR:
		return true
	if format == Image.FORMAT_ASTC_8x8 or format == Image.FORMAT_ASTC_8x8_HDR:
		return true
	if format == Image.FORMAT_BPTC_RGBA or format == Image.FORMAT_BPTC_RGBF or format == Image.FORMAT_BPTC_RGBFU:
		return true
	return false


## Forces a compressed texture's import compress/mode to Lossless and triggers a
## reimport. Returns true once the reimport completes. Caller should reload the
## texture via ResourceLoader.load(path, "", CACHE_MODE_IGNORE) to pick up the new format.
func _auto_fix_texture_compression(texture: Texture2D) -> bool:
	if not texture or texture.resource_path.is_empty():
		return false
	var texture_path: String = texture.resource_path
	var import_path: String = texture_path + ".import"

	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		push_warning("TilesetPanel: Cannot access .import file for texture: " + texture_path)
		return false
	config.set_value("params", "compress/mode", 0)  # 0 = Lossless
	if config.save(import_path) != OK:
		push_warning("TilesetPanel: Cannot save .import file for texture: " + texture_path)
		return false

	var ei: Object = Engine.get_singleton("EditorInterface")
	if not ei:
		push_warning("TilesetPanel: EditorInterface not available - cannot trigger reimport")
		return false
	var editor_fs: Object = ei.get_resource_filesystem()
	editor_fs.reimport_files([texture_path])
	await editor_fs.filesystem_changed
	return true


## Called when the TileSet resource changes externally (e.g., in Godot's TileSet Editor)
func _on_tileset_resource_changed() -> void:
	# Refresh terrain list to reflect external changes
	auto_tile_tab.refresh_terrains()
	# Refresh label in case resource_path changed (e.g., after scene save embeds the resource)
	if current_tilemap3d_node.settings.tileset  and texture_path_label:
		texture_path_label.text = current_tilemap3d_node.settings.tileset.resource_path if current_tilemap3d_node.settings.tileset.resource_path else "Unsaved TileSet"

	# Notify that the Terrain data has changed. 
	_on_autotile_data_changed()


## Picker grid spinbox handler — drives `settings.picker_tile_size` only.
## Does NOT touch `TileSet.tile_size` / `atlas.texture_region_size` (those are
## owned by the TileSet resource — edit via the TileSet spinbox below or via
## Godot's TileSet editor).
func _on_tile_picker_size_changed(_value: float) -> void:
	# Skip when the spinbox value was set programmatically by _load_settings_to_ui —
	# otherwise a settings.changed cascade ping-pongs UI ↔ Resource until stack overflow.
	if _is_loading_from_node:
		return
	if not (tile_picker_size_x and tile_picker_size_y):
		push_warning("TilesetPanel: tile_picker_size_x or tile_picker_size_y is null")
		return

	_tile_size = Vector2i(
		int(tile_picker_size_x.value),
		int(tile_picker_size_y.value)
	)
	# Refresh the selection preview (it reads _tile_size for the snap grid).
	if has_selection and tileset_display:
		tileset_display._update_tile_selection_preview()

	if current_tilemap3d_node and current_tilemap3d_node.settings:
		current_tilemap3d_node.settings.picker_tile_size = _tile_size


## TileSet tile-size spinbox handler. Writes three independent storages:
##   • `settings.tile_size` — the settings-level field (always written; persisted
##     on the node even when no TileSet is loaded yet).
##   • `tileset.tile_size` — the live TileSet's own field (only when a TileSet exists).
##   • `atlas.texture_region_size` — the active atlas source's region size.
## Existing atlas cells are preserved so terrain bits, custom data, collision,
## animation, and other per-tile data survive the resize like in Godot's editor.
func _on_tile_set_size_changed(_value: float) -> void:
	if _is_loading_from_node:
		return
	if not (tile_set_size_x and tile_set_size_y):
		push_warning("TilesetPanel: tile_set_size_x or tile_set_size_y is null")
		return
	if current_tilemap3d_node == null or current_tilemap3d_node.settings == null:
		return

	var requested_size: Vector2i = Vector2i(
		int(tile_set_size_x.value),
		int(tile_set_size_y.value)
	)
	var ts: TileSet = current_tilemap3d_node.settings.tileset
	var atlas: TileSetAtlasSource = TileAtlasResolver.get_active_atlas(current_tilemap3d_node.settings)

	# Keep settings.changed and TileSet.changed from reloading this panel midway
	# through the update. Otherwise _load_settings_to_ui can read the old
	# TileSet.tile_size and snap the spinboxes back one edit behind.
	var prev_loading: bool = _is_loading_from_node
	_is_loading_from_node = true

	# Propagate to the live TileSet + atlas when present.
	if ts != null and ts.tile_size != requested_size:
		ts.tile_size = requested_size
	if atlas != null:
		TileAtlasResolver.set_atlas_region_size_preserving_tiles(atlas, requested_size)

	# Mirror to settings (always present, even with no loaded TileSet).
	current_tilemap3d_node.settings.tile_size = requested_size
	_is_loading_from_node = prev_loading
	_sync_tile_set_size_spinboxes(requested_size)


## Helper: writes a Vector2i into the TileSet spinboxes without re-triggering
## the value_changed handler. Used during initial load and external settings sync.
func _sync_tile_set_size_spinboxes(size: Vector2i) -> void:
	var prev_loading: bool = _is_loading_from_node
	_is_loading_from_node = true
	if tile_set_size_x:
		tile_set_size_x.value = size.x
	if tile_set_size_y:
		tile_set_size_y.value = size.y
	_is_loading_from_node = prev_loading


# --- Tile Selection Signal Routing ---

## Called by TilesetDisplay after selection finalized
## Emits appropriate signals for SelectionManager and downstream systems
##@param programmatically: If true, this selection change was triggered by code (e.g., AnimatedTileManager) rather than direct user interaction. This can be used to adjust signal emission if needed (currently not differentiated).
func _emit_tileset_selection_signals(programmatically: bool = false) -> void:
	if _selected_tiles.size() == 0:
		return
	elif _selected_tiles.size() == 1:
		# Single tile selection
		tile_selected.emit(_selected_tiles[0])
	else:
		# Multi-tile selection (anchor_index = 0 for top-left)
		multi_tile_selected.emit(_selected_tiles, 0)
	
	if animated_tile_manager:
		#Always update the AnimatedTileManager to sync selection
		animated_tile_manager.on_tileset_selection_changed(_selected_tiles, _tile_size,programmatically)


## Programmatically set tile selection 
## Updates local state + visual display, then emits signals to SelectionManager → PlacementManager.
func select_tiles_programmatically(tiles: Array[Rect2]) -> void:
	_selected_tiles = tiles.duplicate()
	has_selection = tiles.size() > 0

	if has_selection and _tile_size.x > 0 and _tile_size.y > 0:
		selected_tile_coords = Vector2i(
			int(_selected_tiles[0].position.x / _tile_size.x),
			int(_selected_tiles[0].position.y / _tile_size.y)
		)

	# Visual feedback — highlight selected tiles in tileset display
	if tileset_display:
		tileset_display.queue_redraw()

	# Propagate through normal signal chain → SelectionManager → PlacementManager
	_emit_tileset_selection_signals(true)


func _on_tile_uvmode_selected(index: int) -> void:
	# When switching to POINTS mode, initialize corners for selected tile
	if index == GlobalConstants.Tile_UV_Select_Mode.POINTS:
		if not _selected_tiles.is_empty() and tileset_display:
			var first_tile_uv: Rect2 = _selected_tiles[0]
			var tile_coord := Vector2i(
				int(first_tile_uv.position.x / _tile_size.x),
				int(first_tile_uv.position.y / _tile_size.y)
			)
			tileset_display.initialize_tile_vertices(tile_coord, _tile_size)

	# Save to node's settings Resource
	_save_ui_to_settings()


## Called when corner data is edited in POINTS mode
func _on_select_vertices_data_changed(tile: Vector2i, corners: Array) -> void:
	print("TilesetPanel: Vertices data received for tile ", tile, ": ", corners)
	# TODO: Store corner data for this tile
	# For now, corners are managed by TilesetDisplay
	# Future: Emit signal or store in settings if needed for 3D tile placement

# --- General Settings and Ui Event Handlers ---
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


##24 Handler for enabling/disabling arched tiles (affects tile placement and sculpt mode generation)
func _on_enabled_arched_tiles_toggled(enabled: bool) -> void:
	# Ignore if we're loading from node
	if _is_loading_from_node:
		return

	# Save to node's settings Resource
	_save_ui_to_settings()

	#TODO: Check if we need a signal for it.. for now just updating settings seems enoug. N=
	# arched_tiles_enabled_changed.emit(enabled)









## Handler for BOX/PRISM Z-fighting auto-resolve checkbox toggle
func _on_box_z_fighting_checkbox_toggled(button_pressed: bool) -> void:
	if _is_loading_from_node:
		return

	if current_tilemap3d_node and current_tilemap3d_node.settings:
		current_tilemap3d_node.settings.auto_resolve_box_z_fighting = button_pressed

	box_z_fighting_changed.emit(button_pressed)


func _on_grid_size_value_changed(new_value: float) -> void:
	#print("DEBUG: _on_grid_size_value_changed called: new_value=", new_value, ", _is_loading_from_node=", _is_loading_from_node, ", current_tilemap3d_node=", current_tilemap3d_node != null)

	#   Ignore if no node is selected yet (prevents dialog on initialization)
	if not current_tilemap3d_node:
		#print("DEBUG: Ignoring grid size change - no node selected yet")
		return

	# Ignore if we're loading from node (prevents warning on node switch)
	if _is_loading_from_node:
		#print("DEBUG: Ignoring grid size change - loading from node")
		return

	# Only show warning if value actually changed from current node's setting
	if current_tilemap3d_node.settings:
		var current_grid_size: float = current_tilemap3d_node.settings.grid_size
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
		if current_tilemap3d_node and current_tilemap3d_node.settings:
			grid_size_spinbox.value = current_tilemap3d_node.settings.grid_size
		else:
			grid_size_spinbox.value = GlobalConstants.DEFAULT_GRID_SIZE
		grid_size_spinbox.editable = true

func _on_texture_filter_selected(index: int) -> void:
	# Save to node's settings Resource
	_save_ui_to_settings()

	# Emit signal for plugin (backward compatibility)
	texture_filter_changed.emit(index)
	#print("Texture filter changed to: ", GlobalConstants.TEXTURE_FILTER_OPTIONS[index])

func _on_pixel_inset_changed(value: float) -> void:
	if _is_loading_from_node:
		return
	_save_ui_to_settings()
	pixel_inset_changed.emit(value)

func _on_bake_mesh_button_pressed() -> void:
	var bake_mode: GlobalConstants.BakeMode = GlobalConstants.BakeMode.ALPHA_AWARE if bake_alpha_check_box.button_pressed else GlobalConstants.BakeMode.NORMAL
	_bake_mesh_requested.emit(bake_mode)
	#print("Bake to scene requested with mode: ", bake_mode)


func _on_create_collision_button_pressed() -> void:
	var bake_mode: GlobalConstants.BakeMode = GlobalConstants.BakeMode.ALPHA_AWARE if collision_alpha_check_box.button_pressed else GlobalConstants.BakeMode.NORMAL
	
	var backface_collision: bool = backface_collision_check_box.button_pressed if backface_collision_check_box else false

	var save_external_collision: bool = save_collision_external_check_box.button_pressed if save_collision_external_check_box else false

	#TODO: Add / BackFace collision?
	create_collision_requested.emit(bake_mode, backface_collision, save_external_collision)



## Set tiling mode from external source and select the correct TileSet Tab to show
func set_tiling_mode_from_external(new_mode: GlobalConstants.MainAppMode) -> void:
	_current_tiling_mode = new_mode

	if not _tab_container:
		return

	# Determine target tab index
	var target_tab: int = GlobalConstants.TilSetTab.MANUAL
	match new_mode:
		GlobalConstants.TilSetTab.MANUAL:
			target_tab = GlobalConstants.TilSetTab.MANUAL
			manual_mode_ui.visible = true
			animated_tile_manager.visible = false
			animated_tile_manager.set_anim_tile_selection(false)
		GlobalConstants.MainAppMode.AUTOTILE:
			target_tab = GlobalConstants.TilSetTab.AUTOTILE
			animated_tile_manager.set_anim_tile_selection(false)
		GlobalConstants.MainAppMode.SETTINGS:
			target_tab = GlobalConstants.TilSetTab.SETTINGS
			animated_tile_manager.set_anim_tile_selection(false)
		GlobalConstants.MainAppMode.SMART_OPERATIONS:
			target_tab = GlobalConstants.TilSetTab.MANUAL
			animated_tile_manager.visible = false
			animated_tile_manager.set_anim_tile_selection(false)
		GlobalConstants.MainAppMode.SCULPT:
			target_tab = GlobalConstants.TilSetTab.MANUAL
			manual_mode_ui.visible = false
			animated_tile_manager.visible = false
		GlobalConstants.MainAppMode.ANIMATED_TILES:
			target_tab = GlobalConstants.TilSetTab.MANUAL
			manual_mode_ui.visible = false
			animated_tile_manager.visible = true
		GlobalConstants.MainAppMode.VERTEX_EDIT:
			target_tab = GlobalConstants.TilSetTab.MANUAL
			manual_mode_ui.visible = false
			animated_tile_manager.visible = false

	# Unhide target FIRST to avoid "Cannot deselect tabs" error,
	# then set current, then hide the rest
	_tab_container.set_tab_hidden(target_tab, false)
	_tab_container.current_tab = target_tab
	for i: int in range(_tab_container.get_tab_count()):
		if i != target_tab:
			_tab_container.set_tab_hidden(i, true)


## Handle terrain selection from AutotileTab
func _on_autotile_terrain_selected(terrain_id: int) -> void:
	autotile_terrain_selected.emit(terrain_id)
	#print("TilesetPanel: Autotile terrain selected: ", terrain_id)


# ## Handle TileSet data changes (terrains added/removed, peering bits painted)
func _on_autotile_data_changed() -> void:
	autotile_data_changed.emit()
	print("TilesetPanel: Autotile data changed - forwarding signal")


#==============================================================================
# TILESET ZOOM AND SCROLL FUNCTIONALITY 
#==============================================================================
func _on_zoom_requested(direction: int, focal_point: Vector2) -> void:
	if direction > 0:
		_handle_zoom_in(focal_point)
	else:
		_handle_zoom_out(focal_point)

## Called when zoom slider value changes
func _on_zoom_slider_changed(value: float) -> void:
	if _is_updating_zoom:
		return
	_apply_zoom(value)

## All zoom changes (slider, scroll wheel, load settings, reset) flow through here
func _apply_zoom(new_zoom: float, focal_point: Vector2 = Vector2.ZERO) -> void:
	if not Engine.is_editor_hint():
		return
	if not tileset_display or not current_texture or not scroll_container:
		return

	# Clamp zoom to valid range
	new_zoom = clamp(new_zoom, GlobalConstants.TILESET_MIN_ZOOM, GlobalConstants.TILESET_MAX_ZOOM)

	# Calculate zoom ratio for scroll adjustment
	var zoom_ratio: float = new_zoom / _current_zoom if _current_zoom > 0.0 else 1.0

	# Store old scroll position BEFORE zoom
	var old_scroll: Vector2 = Vector2(
		scroll_container.scroll_horizontal,
		scroll_container.scroll_vertical
	)

	# Update display size — this is what makes zoom work
	var zoomed_size: Vector2 = Vector2(current_texture.get_size()) * new_zoom
	tileset_display.custom_minimum_size = zoomed_size
	tileset_display.size = zoomed_size

	_current_zoom = new_zoom

	# Sync slider without re-triggering _on_zoom_slider_changed
	_is_updating_zoom = true
	if tile_set_zoom_hslider:
		tile_set_zoom_hslider.value = _current_zoom
	_is_updating_zoom = false

	# Adjust scroll to keep focal_point stationary (zoom-to-cursor)
	var new_scroll: Vector2 = (old_scroll + focal_point) * zoom_ratio - focal_point
	call_deferred("_set_scroll_position", new_scroll)

	# Save to settings for persistence
	_save_zoom_to_settings()

	# Redraw selection highlights
	tileset_display.queue_redraw()


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
func _reset_zoom_and_pan() -> void:
	_apply_zoom(GlobalConstants.TILESET_DEFAULT_ZOOM)

## Saves current zoom level to node settings
## Called whenever zoom changes
func _save_zoom_to_settings() -> void:
	if not current_tilemap3d_node or not current_tilemap3d_node.settings:
		return

	# Prevent signal loop
	var was_loading: bool = _is_loading_from_node
	_is_loading_from_node = true

	current_tilemap3d_node.settings.tileset_zoom = _current_zoom

	_is_loading_from_node = was_loading

## Sets scroll position in ScrollContainer
## Called deferred after zoom to let ScrollContainer update size first
func _set_scroll_position(scroll_pos: Vector2) -> void:
	if not scroll_container:
		return

	scroll_container.scroll_horizontal = int(scroll_pos.x)
	scroll_container.scroll_vertical = int(scroll_pos.y)
