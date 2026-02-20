@tool
class_name TilesetPanel
extends PanelContainer

## UI panel for tileset loading and tile selection
## Responsibility: Texture display, tile selection, file loading


# Node references (using unique names %)
@onready var load_texture_button: Button = %LoadTextureButton
@onready var texture_path_label: Label = %TexturePathLabel
@onready var tile_size_label: Label = %TileSizeLabel
@onready var tile_size_x: SpinBox = %TileSizeX
@onready var tile_size_y: SpinBox = %TileSizeY
@onready var tileset_display: TextureRect = %TilesetDisplay
@onready var load_texture_dialog: FileDialog = %LoadTextureDialog
@onready var selection_highlight: ColorRect = %SelectionHighlight
@onready var scroll_container: ScrollContainer = %TileSetScrollContainer
#Box/Prism mesh texture repeat
@onready var box_texture_repeat_checkbox: CheckBox = %BoxTextureRepeatCheckbox
#SpriteMesh
@onready var generate_sprite_mesh_btn: Button = %GenerateSpriteMeshButton
@onready var sprite_mesh_depth_spin_box: SpinBox = %SpriteMeshDepthSpinBox

@onready var manual_tiling_tab: HBoxContainer = %Manual_Tiling
@onready var auto_tile_tab: VBoxContainer = %"Auto_Tiling"
@onready var show_plane_grids_checkbox: CheckBox = %ShowPlaneGridsCheckbox
@onready var cursor_step_dropdown: OptionButton = %CursorStepDropdown
@onready var grid_snap_dropdown: OptionButton = %GridSnapDropdown
@onready var grid_size_spinbox: SpinBox = %GridSizeSpinBox
@onready var grid_size_confirm_dialog: ConfirmationDialog = %GridSizeConfirmDialog
@onready var _texture_change_warning_dialog: ConfirmationDialog = %TextureChangeWarningDialog
@onready var texture_filter_dropdown: OptionButton = %TextureFilterDropdown
@onready var create_collision_button: Button = %CreateCollisionBtn 
@onready var clear_collisions_button: Button = %ClearCollisionsButton #TODO: Add logic for this button //DEBUG 
@onready var collision_alpha_check_box: CheckBox = %CollisionAlphaCheckBox
@onready var backface_collision_check_box: CheckBox = %BackfaceCollisionCheckBox
@onready var save_collision_external_check_box: CheckBox = %SaveCollisionExternally

@onready var bake_alpha_check_box: CheckBox = %BakeAlphaCheckBox
@onready var bake_mesh_button: Button = %BakeMeshButton
@onready var clear_all_tiles_button: Button = %ClearAllTilesButton
@onready var show_debug_button: Button = %ShowDebugInfo
# @onready var autotile_mesh_dropdown: OptionButton = %AutoTileModeDropdown
@onready var _tab_container: TabContainer = $TabContainer

#UV MOde Tile Select #TODO New Logic //DEBUG 
@onready var tile_uvmode_dropdown: OptionButton = %TileUVModeDropdown
@onready var tile_set_section_label: Label = %TileSetSectionLabel
@onready var tile_set_path_label: Label = %TileSetPathLabel
@onready var load_tile_set_button: Button = %LoadTileSetButton
@onready var create_tile_set_button: Button = %CreateTileSetButton
@onready var save_tile_set_button: Button = %SaveTileSetButton
@onready var open_editor_button: Button = %OpenEditorButton
@onready var add_terrain_button: Button = %AddTerrainButton
@onready var remove_terrain_button: Button = %RemoveTerrainButton
@onready var terrain_name_input: LineEdit = %TerrainNameInput




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
# Emitted when BOX/PRISM texture repeat mode changes (DEFAULT or REPEAT)
signal texture_repeat_mode_changed(mode: int)
# Emitted when grid size changes (requires rebuild)
signal grid_size_changed(new_size: float)
# Emitted when texture filter mode changes
signal texture_filter_changed(filter_mode: int)
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
# === AUTOTILE SIGNALS ===
# Emitted when autotile TileSet is loaded or changed
signal autotile_tileset_changed(tileset: TileSet)
# Emitted when user selects a terrain for autotile painting
signal autotile_terrain_selected(terrain_id: int)
# Emitted when TileSet content changes (terrains, peering bits) - triggers engine rebuild
signal autotile_data_changed()
# Emitted when user confirms texture change that requires clearing the TileSet
signal clear_autotile_requested()
# Emitted when user requests Sprite Mesh creation from UI (Clicking the button)
signal request_sprite_mesh_creation(current_texture: Texture2D, selected_tiles: Array[Rect2], tile_size: Vector2i, grid_size: float)

# Maps AutoTile dropdown indices to actual MeshMode values
# AutoTile only supports FLAT_SQUARE (0) and BOX_MESH (2) - NO triangles
const AUTOTILE_MESH_MODE_MAP: Array[int] = [
	GlobalConstants.MeshMode.FLAT_SQUARE,  # Index 0 → value 0
	GlobalConstants.MeshMode.BOX_MESH,     # Index 1 → value 2
]

# State
var current_node: TileMapLayer3D = null  # Reference to currently edited node
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
var _original_texture_size: Vector2 = Vector2.ZERO
var _previous_texture: Texture2D = null  # For detecting texture changes


var _current_tiling_mode: GlobalConstants.MainAppMode = GlobalConstants.MainAppMode.MANUAL  # Default to MANUAL, can be changed by UI or node settings

# Tile selection state
var _selected_tiles: Array[Rect2] = []  # Multiple UV rects for multi-selection (managed by TilesetDisplay)

func _ready() -> void:
	_connect_signals()
	manual_tiling_tab.show()
	set_tiling_mode_from_external(GlobalConstants.MainAppMode.MANUAL)
	set_ui_theme_scale()

func set_ui_theme_scale() -> void:
	var ui_scale: float = GlobalUtil.get_editor_ui_scale()
	tile_size_x.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	tile_size_y.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	terrain_name_input.add_theme_font_size_override("font_size", int(10 * ui_scale))

	texture_path_label.label_settings.font_size = int(10 * ui_scale)
	tile_size_label.label_settings.font_size = int(10 * ui_scale)
	tile_set_path_label.label_settings.font_size = int(10 * ui_scale)
	tile_set_section_label.label_settings.font_size = int(10 * ui_scale)

	GlobalUtil.apply_button_theme(load_tile_set_button, "Load", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE) 
	GlobalUtil.apply_button_theme(load_texture_button, "Load", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE) 
	GlobalUtil.apply_button_theme(create_tile_set_button, "New", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE) 
	GlobalUtil.apply_button_theme(save_tile_set_button, "Save", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE) 
	GlobalUtil.apply_button_theme(open_editor_button, "TileSet", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)
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
	if tile_size_x and not tile_size_x.value_changed.is_connected(_on_tile_size_changed):
		tile_size_x.value_changed.connect(_on_tile_size_changed)
		#print("   TileSizeX connected")
	if tile_size_y and not tile_size_y.value_changed.is_connected(_on_tile_size_changed):
		tile_size_y.value_changed.connect(_on_tile_size_changed)
		#print("   TileSizeY connected")

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
		#print("   Texture filter dropdown connected (default: Nearest)")


	# Connect BOX/PRISM texture repeat checkbox
	if box_texture_repeat_checkbox and not box_texture_repeat_checkbox.toggled.is_connected(_on_texture_repeat_checkbox_toggled):
		box_texture_repeat_checkbox.toggled.connect(_on_texture_repeat_checkbox_toggled)

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
		if not auto_tile_tab.tileset_changed.is_connected(_on_autotile_tileset_changed):
			auto_tile_tab.tileset_changed.connect(_on_autotile_tileset_changed)
			#print("   AutotileTab tileset_changed connected")
		if not auto_tile_tab.terrain_selected.is_connected(_on_autotile_terrain_selected):
			auto_tile_tab.terrain_selected.connect(_on_autotile_terrain_selected)
			#print("   AutotileTab terrain_selected connected")
		if not auto_tile_tab.tileset_data_changed.is_connected(_on_autotile_data_changed):
			auto_tile_tab.tileset_data_changed.connect(_on_autotile_data_changed)
			#print("   AutotileTab tileset_data_changed connected")
		# if not auto_tile_tab.autotile_depth_changed.is_connected(_on_autotile_depth_changed):
		# 	auto_tile_tab.autotile_depth_changed.connect(_on_autotile_depth_changed)
			#print("   AutotileTab autotile_depth_changed connected")

	#Connect Sprite Mesh signals and nodes
	generate_sprite_mesh_btn.pressed.connect(_on_generate_sprite_mesh_btn_pressed)
		#print("   Generate SpriteMesh button connected")


## Returns current tile size (used by AutotileTab for TileSet creation)
func get_tile_size() -> Vector2i:
	return _tile_size


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
			# Set TextureRect to actual texture size for pixel-perfect display
			tileset_display.custom_minimum_size = texture.get_size()
			tileset_display.size = texture.get_size()

	# Reset selection when texture changes
	tileset_display.clear_selection()




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

	# Load autotile configuration
	if auto_tile_tab:
		# Load the TileSet for this specific node (may be null for new nodes)
		auto_tile_tab.set_tileset(settings.autotile_tileset)
		# Select the saved terrain if any
		if settings.autotile_tileset and settings.autotile_active_terrain >= 0:
			auto_tile_tab.select_terrain(settings.autotile_active_terrain)

	# # Load autotile mesh mode (reverse map MeshMode value to dropdown index)
	# if autotile_mesh_dropdown:
	# 	var saved_mode: int = settings.autotile_mesh_mode
	# 	var dropdown_index: int = AUTOTILE_MESH_MODE_MAP.find(saved_mode)
	# 	if dropdown_index == -1:
	# 		dropdown_index = 0  # Default to FLAT_SQUARE
	# 	autotile_mesh_dropdown.selected = dropdown_index

	# Load tiling mode (restore correct tab visibility)
	# Reuses set_tiling_mode_from_external() to properly show/hide tabs
	set_tiling_mode_from_external(settings.main_app_mode as GlobalConstants.MainAppMode)

	# # Load mesh mode
	# if mesh_mode_dropdown:
	# 	mesh_mode_dropdown.selected = settings.mesh_mode

	# # Load collision configuration

	# # Sync Manual depth (follows rotation/flip pattern for explicit UI sync)
	# if mesh_mode_depth_spin_box:
	# 	mesh_mode_depth_spin_box.value = settings.current_depth_scale

	#Sync UV Tile selection mode
	if tile_uvmode_dropdown:
		tile_uvmode_dropdown.selected = settings.uv_selection_mode

	# Sync BOX/PRISM texture repeat mode checkbox
	if box_texture_repeat_checkbox:
		box_texture_repeat_checkbox.button_pressed = (settings.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT)

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
	
	# Save UV Tile Selection Mode
	if tile_uvmode_dropdown:
		current_node.settings.uv_selection_mode = tile_uvmode_dropdown.selected
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
			tileset_display._update_tile_selection_preview()

		# Save to node's settings Resource
		_save_ui_to_settings()
	else:
		push_warning("TilesetPanel: tile_size_x or tile_size_y is null")


# ==============================================================================
# TilesetDisplay / Tile Selection SIGNAL ROUTING
# ==============================================================================

## Called by TilesetDisplay after selection finalized
## Emits appropriate signals for SelectionManager and downstream systems
func _emit_selection_signals() -> void:
	if _selected_tiles.size() == 0:
		return
	elif _selected_tiles.size() == 1:
		# Single tile selection
		tile_selected.emit(_selected_tiles[0])
	else:
		# Multi-tile selection (anchor_index = 0 for top-left)
		multi_tile_selected.emit(_selected_tiles, 0)


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


# ==============================================================================
# Sprite Mesh Generation and Integration section
# ==============================================================================

func _on_generate_sprite_mesh_btn_pressed() -> void: 	
	# Emit event to generate sprite mesh from current selection
	if not has_selection or _selected_tiles.size() == 0:
		push_warning("TilesetPanel: No tile selected for SpriteMesh generation")
		return

	if current_texture == null:
		push_warning("TilesetPanel: No texture loaded for SpriteMesh generation")
		return

	var grid_size := grid_size_spinbox.value if grid_size_spinbox else GlobalConstants.DEFAULT_GRID_SIZE
	var filter_mode: int = texture_filter_dropdown.selected if texture_filter_dropdown else GlobalConstants.DEFAULT_TEXTURE_FILTER
	GlobalTileMapEvents.emit_request_sprite_mesh_creation(current_texture, _selected_tiles, _tile_size, grid_size, filter_mode)
	# print("TilesetPanel: Requested SpriteMesh generation for ", _selected_tiles.size(), " tiles")



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


## Handler for BOX/PRISM texture repeat checkbox toggle
## Emits signal for plugin to update settings (DEFAULT = stripes, REPEAT = uniform)
func _on_texture_repeat_checkbox_toggled(button_pressed: bool) -> void:
	#print("[TEXTURE_REPEAT] UI: Checkbox toggled → button_pressed=%s" % button_pressed)

	# Ignore if we're loading from node (prevents signal loops)
	if _is_loading_from_node:
		#print("[TEXTURE_REPEAT] UI: SKIPPED (loading from node)")
		return

	var mode: int = GlobalConstants.TextureRepeatMode.REPEAT if button_pressed else GlobalConstants.TextureRepeatMode.DEFAULT
	#print("[TEXTURE_REPEAT] UI: Calculated mode=%d (0=DEFAULT, 1=REPEAT)" % mode)

	# Save to per-node settings (single source of truth)
	if current_node and current_node.settings:
		current_node.settings.texture_repeat_mode = mode
		#print("[TEXTURE_REPEAT] UI: Saved to settings.texture_repeat_mode=%d" % mode)
	else:
		pass  #print("[TEXTURE_REPEAT] UI: WARNING - current_node or settings is null!")

	# Emit signal for plugin to update tile placement manager
	#print("[TEXTURE_REPEAT] UI: Emitting texture_repeat_mode_changed(%d)" % mode)
	texture_repeat_mode_changed.emit(mode)



## Get current texture repeat mode from UI checkbox
## Returns GlobalConstants.TextureRepeatMode value
func get_texture_repeat_mode() -> int:
	if box_texture_repeat_checkbox:
		return GlobalConstants.TextureRepeatMode.REPEAT if box_texture_repeat_checkbox.button_pressed else GlobalConstants.TextureRepeatMode.DEFAULT
	return GlobalConstants.TextureRepeatMode.DEFAULT


## Set texture repeat mode in UI checkbox (used when switching nodes)
func set_texture_repeat_mode(mode: int) -> void:
	if box_texture_repeat_checkbox:
		_is_loading_from_node = true
		box_texture_repeat_checkbox.button_pressed = (mode == GlobalConstants.TextureRepeatMode.REPEAT)
		_is_loading_from_node = false


# ## Handler for AutoTile mesh mode dropdown
# ## Maps dropdown index to correct MeshMode value (index 1 → BOX_MESH value 2)
# func _on_autotile_mesh_mode_selected(index: int) -> void:
# 	# Ignore if we're loading from node
# 	if _is_loading_from_node:
# 		return

# 	# Map dropdown index to actual MeshMode value
# 	var mesh_mode: int = AUTOTILE_MESH_MODE_MAP[index] if index < AUTOTILE_MESH_MODE_MAP.size() else GlobalConstants.MeshMode.FLAT_SQUARE

# 	# Save to node settings (single source of truth)
# 	if current_node and current_node.settings:
# 		current_node.settings.autotile_mesh_mode = mesh_mode

# 	# Emit signal with correct MeshMode value
# 	autotile_mesh_mode_changed.emit(mesh_mode)

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
		GlobalConstants.MainAppMode.AUTOTILE:
			target_tab = GlobalConstants.TilSetTab.AUTOTILE
		GlobalConstants.MainAppMode.SETTINGS:
			target_tab = GlobalConstants.TilSetTab.SETTINGS
		GlobalConstants.MainAppMode.MANUAL_SMART_SELECT:
			target_tab = GlobalConstants.TilSetTab.MANUAL

	# Unhide target FIRST to avoid "Cannot deselect tabs" error,
	# then set current, then hide the rest
	_tab_container.set_tab_hidden(target_tab, false)
	_tab_container.current_tab = target_tab
	for i: int in range(_tab_container.get_tab_count()):
		if i != target_tab:
			_tab_container.set_tab_hidden(i, true)

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
