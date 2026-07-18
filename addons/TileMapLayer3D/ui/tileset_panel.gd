@tool
class_name TilesetPanel
extends PanelContainer



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

@onready var box_z_fighting_checkbox: CheckBox = %BoxZFightingCheckbox

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
@onready var _tab_container: TabContainer = $TabContainer

@onready var tile_uvmode_dropdown: OptionButton = %TileUVModeDropdown
@onready var tile_set_section_label: Label = %TileSetSectionLabel
@onready var tile_set_path_label: Label = %TileSetPathLabel


@onready var manual_mode_ui: VBoxContainer = %ManualModeUI
@onready var manual_tab_common_ui: VBoxContainer = %ManualTabCommonUI
@onready var animated_tile_manager: AnimatedTileManager = %AnimatedTileManager


@onready var load_texture_button: Button = %LoadTextureButton
@onready var load_tile_set_button: Button = %LoadTileSetButton
@onready var save_tileset_button: Button = %SaveTileSetButton
@onready var open_editor_button: Button = %OpenEditorButton
@onready var add_terrain_button: Button = %AddTerrainButton
@onready var remove_terrain_button: Button = %RemoveTerrainButton
@onready var terrain_name_input: LineEdit = %TerrainNameInput


signal tile_selected(uv_rect: Rect2)
signal multi_tile_selected(uv_rects: Array[Rect2], anchor_index: int)
signal tileset_loaded(texture: Texture2D)
signal orientation_changed(orientation: int)
signal placement_mode_changed(mode: int)
signal show_plane_grids_changed(enabled: bool)
signal cursor_step_size_changed(step_size: float)
signal grid_snap_size_changed(snap_size: float)
signal box_z_fighting_changed(enabled: bool)
signal grid_size_changed(new_size: float)
signal texture_filter_changed(filter_mode: int)
signal pixel_inset_changed(value: float)
signal create_collision_requested(bake_mode: GlobalConstants.BakeMode, backface_collision: bool, save_external_collision: bool)
signal clear_collisions_requested()
signal _bake_mesh_requested(bake_mode: GlobalConstants.BakeMode)
signal clear_tiles_requested()
signal show_debug_info_requested()
signal autotile_tileset_changed(tileset: TileSet)
signal autotile_terrain_selected(terrain_id: int)
signal autotile_data_changed()
signal clear_tileset_requested()


var current_tilemap3d_node: TileMapLayer3D = null
var _is_loading_from_node: bool = false
var current_texture: Texture2D = null
var _selection_manager: SelectionManager = null
var _tile_size: Vector2i = GlobalConstants.DEFAULT_TILE_SIZE
var selected_tile_coords: Vector2i = Vector2i(0, 0)
var has_selection: bool = false
var _pending_grid_size: float = 0.0
var _current_zoom: float = GlobalConstants.TILESET_DEFAULT_ZOOM
var _is_updating_zoom: bool = false
var _previous_texture: Texture2D = null


var _current_tiling_mode: GlobalConstants.MainAppMode = GlobalConstants.MainAppMode.MANUAL

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
	if load_texture_button and not load_texture_button.pressed.is_connected(_on_load_texture_pressed):
		load_texture_button.pressed.connect(_on_load_texture_pressed)
	if load_texture_dialog and not load_texture_dialog.file_selected.is_connected(_on_texture_selected):
		load_texture_dialog.file_selected.connect(_on_texture_selected)
	if tile_picker_size_x and not tile_picker_size_x.value_changed.is_connected(_on_tile_picker_size_changed):
		tile_picker_size_x.value_changed.connect(_on_tile_picker_size_changed)
	if tile_picker_size_y and not tile_picker_size_y.value_changed.is_connected(_on_tile_picker_size_changed):
		tile_picker_size_y.value_changed.connect(_on_tile_picker_size_changed)

	if tile_set_size_x and not tile_set_size_x.value_changed.is_connected(_on_tile_set_size_changed):
		tile_set_size_x.value_changed.connect(_on_tile_set_size_changed)
	if tile_set_size_y and not tile_set_size_y.value_changed.is_connected(_on_tile_set_size_changed):
		tile_set_size_y.value_changed.connect(_on_tile_set_size_changed)

	if tile_uvmode_dropdown:
		if not tile_uvmode_dropdown.item_selected.is_connected(_on_tile_uvmode_selected):
			tile_uvmode_dropdown.item_selected.connect(_on_tile_uvmode_selected)

	if tileset_display:
		if not tileset_display.select_vertices_data_changed.is_connected(_on_select_vertices_data_changed):
			tileset_display.select_vertices_data_changed.connect(_on_select_vertices_data_changed)

	if show_plane_grids_checkbox and not show_plane_grids_checkbox.toggled.is_connected(_on_show_plane_grids_toggled):
		show_plane_grids_checkbox.toggled.connect(_on_show_plane_grids_toggled)

	if cursor_step_dropdown and not cursor_step_dropdown.item_selected.is_connected(_on_cursor_step_selected):
		cursor_step_dropdown.item_selected.connect(_on_cursor_step_selected)

	if grid_snap_dropdown and not grid_snap_dropdown.item_selected.is_connected(_on_grid_snap_selected):
		grid_snap_dropdown.item_selected.connect(_on_grid_snap_selected)

	if grid_size_spinbox and not grid_size_spinbox.value_changed.is_connected(_on_grid_size_value_changed):
		grid_size_spinbox.value_changed.connect(_on_grid_size_value_changed)

	if grid_size_confirm_dialog:
		if not grid_size_confirm_dialog.confirmed.is_connected(_on_grid_size_confirmed):
			grid_size_confirm_dialog.confirmed.connect(_on_grid_size_confirmed)
		if not grid_size_confirm_dialog.canceled.is_connected(_on_grid_size_canceled):
			grid_size_confirm_dialog.canceled.connect(_on_grid_size_canceled)

	if _texture_change_warning_dialog:
		if not _texture_change_warning_dialog.confirmed.is_connected(_on_texture_change_confirmed):
			_texture_change_warning_dialog.confirmed.connect(_on_texture_change_confirmed)

	if texture_filter_dropdown and not texture_filter_dropdown.item_selected.is_connected(_on_texture_filter_selected):
		texture_filter_dropdown.item_selected.connect(_on_texture_filter_selected)
		texture_filter_dropdown.selected = GlobalConstants.DEFAULT_TEXTURE_FILTER

	if pixel_inset_slider and not pixel_inset_slider.value_changed.is_connected(_on_pixel_inset_changed):
		pixel_inset_slider.value_changed.connect(_on_pixel_inset_changed)

	if box_z_fighting_checkbox and not box_z_fighting_checkbox.toggled.is_connected(_on_box_z_fighting_checkbox_toggled):
		box_z_fighting_checkbox.toggled.connect(_on_box_z_fighting_checkbox_toggled)
	box_z_fighting_checkbox.button_pressed = true
	_on_box_z_fighting_checkbox_toggled(true)  


	if create_collision_button and not create_collision_button.pressed.is_connected(_on_create_collision_button_pressed):
		create_collision_button.pressed.connect(_on_create_collision_button_pressed)

	if clear_collisions_button:
		clear_collisions_button.pressed.connect(func(): clear_collisions_requested.emit() )

	if bake_mesh_button and not bake_mesh_button.pressed.is_connected(_on_bake_mesh_button_pressed):
		bake_mesh_button.pressed.connect(_on_bake_mesh_button_pressed)

	if clear_all_tiles_button:
		clear_all_tiles_button.pressed.connect(func(): clear_tiles_requested.emit() )

	if show_debug_button:
		show_debug_button.pressed.connect(func(): show_debug_info_requested.emit() )

	if auto_tile_tab:
		if not auto_tile_tab.terrain_selected.is_connected(_on_autotile_terrain_selected):
			auto_tile_tab.terrain_selected.connect(_on_autotile_terrain_selected)

		if not auto_tile_tab.open_tileset_editor_button.pressed.is_connected(_on_open_tileset_editor_pressed):
			auto_tile_tab.open_tileset_editor_button.pressed.connect(_on_open_tileset_editor_pressed)


	if tileset_display:
		if not tileset_display.zoom_requested.is_connected(_on_zoom_requested):
			tileset_display.zoom_requested.connect(_on_zoom_requested)

	if tile_set_zoom_hslider and not tile_set_zoom_hslider.value_changed.is_connected(_on_zoom_slider_changed):
		tile_set_zoom_hslider.value_changed.connect(_on_zoom_slider_changed)

	if enabled_arched_tiles_checkbox and not enabled_arched_tiles_checkbox.toggled.is_connected(_on_enabled_arched_tiles_toggled):
		enabled_arched_tiles_checkbox.toggled.connect(_on_enabled_arched_tiles_toggled)
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
		return TileAtlasResolver.get_tile_size(current_tilemap3d_node)
	if tile_set_size_x and tile_set_size_y:
		return Vector2i(int(tile_set_size_x.value), int(tile_set_size_y.value))
	return GlobalConstants.DEFAULT_TILE_SIZE


func set_selection_manager(manager: SelectionManager) -> void:
	if _selection_manager:
		if _selection_manager.selection_changed.is_connected(_on_selection_manager_changed):
			_selection_manager.selection_changed.disconnect(_on_selection_manager_changed)
		if _selection_manager.selection_cleared.is_connected(_on_selection_manager_cleared):
			_selection_manager.selection_cleared.disconnect(_on_selection_manager_cleared)

	_selection_manager = manager

	if _selection_manager:
		_selection_manager.selection_changed.connect(_on_selection_manager_changed)
		_selection_manager.selection_cleared.connect(_on_selection_manager_cleared)


func _on_selection_manager_changed(tiles: Array[Rect2], anchor: int) -> void:
	_selected_tiles = tiles.duplicate()
	has_selection = tiles.size() > 0

	if has_selection:
		if _selected_tiles.size() > 0 and _tile_size.x > 0 and _tile_size.y > 0:
			selected_tile_coords = Vector2i(
				int(_selected_tiles[0].position.x / _tile_size.x),
				int(_selected_tiles[0].position.y / _tile_size.y)
			)
		tileset_display._update_tile_selection_preview()
	else:
		if selection_highlight:
			selection_highlight.visible = false


func _on_selection_manager_cleared() -> void:
	_selected_tiles.clear()
	has_selection = false
	selected_tile_coords = Vector2i(-1, -1)
	if selection_highlight:
		selection_highlight.visible = false


func get_tileset_texture() -> Texture2D:
	return current_texture


func set_tileset_texture(texture: Texture2D) -> void:
	if texture == current_texture:
		return

	current_texture = texture
	if tileset_display:
		tileset_display.texture = texture
		if texture:
			_apply_zoom(GlobalConstants.TILESET_DEFAULT_ZOOM)


	tileset_display.clear_selection()

	initialize_animated_tile_manager()




func set_active_node(node: TileMapLayer3D) -> void:
	if current_tilemap3d_node and current_tilemap3d_node.settings:
		if current_tilemap3d_node.settings.changed.is_connected(_on_node_settings_changed):
			current_tilemap3d_node.settings.changed.disconnect(_on_node_settings_changed)

	# Disconnect from old node's TileSet.changed so the handler never fires against
	# a stale node (it dereferences current_tilemap3d_node / auto_tile_tab).
	if current_tilemap3d_node:
		var old_tileset: TileSet = current_tilemap3d_node.get_tileset()
		if old_tileset and old_tileset.changed.is_connected(_on_tileset_resource_changed):
			old_tileset.changed.disconnect(_on_tileset_resource_changed)

	current_tilemap3d_node = node

	if current_tilemap3d_node and current_tilemap3d_node.settings:
		if not current_tilemap3d_node.settings.changed.is_connected(_on_node_settings_changed):
			current_tilemap3d_node.settings.changed.connect(_on_node_settings_changed)
		_load_settings_to_ui(current_tilemap3d_node.settings)
	else:
		_clear_ui()

	if current_tilemap3d_node:
		var new_tileset: TileSet = current_tilemap3d_node.get_tileset()
		if new_tileset and not new_tileset.changed.is_connected(_on_tileset_resource_changed):
			new_tileset.changed.connect(_on_tileset_resource_changed)

	initialize_animated_tile_manager()


func _on_node_settings_changed() -> void:
	# Ignore self-triggered changes to prevent a reload loop.
	if _is_loading_from_node:
		return
	if current_tilemap3d_node and current_tilemap3d_node.settings:
		_load_settings_to_ui(current_tilemap3d_node.settings)

func _load_settings_to_ui(settings: TileMapLayerSettings) -> void:
	_is_loading_from_node = true

	var active_texture: Texture2D = TileAtlasResolver.get_active_texture(current_tilemap3d_node)
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
			var path_source: Resource = current_tilemap3d_node.get_tileset() if current_tilemap3d_node and current_tilemap3d_node.get_tileset() != null else active_texture
			texture_path_label.text = path_source.resource_path.get_file() if path_source.resource_path else ""
	else:
		_clear_texture_ui()

	_tile_size = settings.picker_tile_size
	if tile_picker_size_x:
		tile_picker_size_x.value = _tile_size.x
	if tile_picker_size_y:
		tile_picker_size_y.value = _tile_size.y

	_sync_tile_set_size_spinboxes(TileAtlasResolver.get_tile_size(current_tilemap3d_node))

	# Selection state is managed by SelectionManager (single source of truth)
	# UI updates via _on_selection_manager_changed/_on_selection_manager_cleared signals
	# Don't restore selection here - it causes UI/system desync on node switch
	_selected_tiles.clear()
	has_selection = false
	selected_tile_coords = Vector2i(-1, -1)
	if selection_highlight:
		selection_highlight.visible = false

	if grid_size_spinbox:
		grid_size_spinbox.value = settings.grid_size

	if cursor_step_dropdown:
		var step_index: int = GlobalConstants.CURSOR_STEP_OPTIONS.find(settings.cursor_step_size)
		if step_index >= 0:
			cursor_step_dropdown.selected = step_index
		else:
			var default_index: int = GlobalConstants.CURSOR_STEP_OPTIONS.find(GlobalConstants.DEFAULT_CURSOR_STEP_SIZE)
			cursor_step_dropdown.selected = default_index if default_index >= 0 else 0

	if grid_snap_dropdown:
		var snap_index: int = GlobalConstants.GRID_SNAP_OPTIONS.find(settings.grid_snap_size)
		if snap_index >= 0:
			grid_snap_dropdown.selected = snap_index
		else:
			var default_index: int = GlobalConstants.GRID_SNAP_OPTIONS.find(1.0)
			grid_snap_dropdown.selected = default_index if default_index >= 0 else 0

	if texture_filter_dropdown:
		texture_filter_dropdown.selected = settings.texture_filter_mode

	if pixel_inset_slider:
		pixel_inset_slider.value = settings.pixel_inset_value

	if auto_tile_tab:
		var unified_tileset: TileSet = current_tilemap3d_node.get_tileset() if current_tilemap3d_node else null
		if unified_tileset == null:
			unified_tileset = settings.autotile_tileset
		auto_tile_tab._current_tileset = unified_tileset
		auto_tile_tab.refresh_terrains()
		var restored_terrain: int = settings.active_terrain
		if restored_terrain < 0:
			restored_terrain = settings.autotile_active_terrain
		if unified_tileset and restored_terrain >= 0:
			auto_tile_tab.select_terrain(restored_terrain)


	set_tiling_mode_from_external(settings.main_app_mode as GlobalConstants.MainAppMode)

	if tile_uvmode_dropdown:
		tile_uvmode_dropdown.selected = settings.uv_selection_mode

	if box_z_fighting_checkbox:
		box_z_fighting_checkbox.button_pressed = settings.auto_resolve_box_z_fighting


	if current_tilemap3d_node and current_tilemap3d_node.get_tileset():
		update_tileset_buttons_ui(true)
	else:
		update_tileset_buttons_ui(false)

	cursor_step_size_changed.emit(settings.cursor_step_size)
	grid_snap_size_changed.emit(settings.grid_snap_size)
	grid_size_changed.emit(settings.grid_size)

	enabled_arched_tiles_checkbox.button_pressed = settings.enable_arched_tiles if _on_enabled_arched_tiles_toggled else false 

	_is_loading_from_node = false



func initialize_animated_tile_manager() -> void:
	if animated_tile_manager:
		animated_tile_manager.current_node = current_tilemap3d_node

		if current_tilemap3d_node:
			var target_index: int = 0
			if current_tilemap3d_node.settings:
				var active_id: int = current_tilemap3d_node.settings.active_animated_tile
				if active_id >= 0:
					var found: int = current_tilemap3d_node.settings.animate_tiles_list.keys().find(active_id)
					if found >= 0:
						target_index = found

			animated_tile_manager.load_animated_tile_settings(current_texture, target_index)
		else:
			animated_tile_manager.deselect_all()
			animated_tile_manager._load_default_ui_values()

		if not animated_tile_manager.anim_tile_frame0_selected.is_connected(select_tiles_programmatically):
			animated_tile_manager.anim_tile_frame0_selected.connect(select_tiles_programmatically)
		


func _save_ui_to_settings() -> void:
	if not current_tilemap3d_node or not current_tilemap3d_node.settings or _is_loading_from_node:
		return

	# Set flag to prevent settings.changed from triggering a reload
	# This prevents circular: save → settings.changed → reload → breaks UI state
	_is_loading_from_node = true

	current_tilemap3d_node.settings.tileset_texture = current_texture
	if texture_filter_dropdown:
		current_tilemap3d_node.settings.texture_filter_mode = texture_filter_dropdown.selected
	if pixel_inset_slider:
		current_tilemap3d_node.settings.pixel_inset_value = pixel_inset_slider.value

	if _selected_tiles.size() > 1:
		current_tilemap3d_node.settings.selected_tiles = _selected_tiles.duplicate()
		current_tilemap3d_node.settings.selected_tile_uv = Rect2()
	elif _selected_tiles.size() == 1:
		current_tilemap3d_node.settings.selected_tile_uv = _selected_tiles[0]
		current_tilemap3d_node.settings.selected_tiles = []
	else:
		current_tilemap3d_node.settings.selected_tile_uv = Rect2()
		current_tilemap3d_node.settings.selected_tiles = []

	if grid_size_spinbox:
		current_tilemap3d_node.settings.grid_size = grid_size_spinbox.value

	if cursor_step_dropdown and cursor_step_dropdown.selected >= 0:
		current_tilemap3d_node.settings.cursor_step_size = GlobalConstants.CURSOR_STEP_OPTIONS[cursor_step_dropdown.selected]

	if grid_snap_dropdown and grid_snap_dropdown.selected >= 0:
		current_tilemap3d_node.settings.grid_snap_size = GlobalConstants.GRID_SNAP_OPTIONS[grid_snap_dropdown.selected]
	
	if tile_uvmode_dropdown:
		current_tilemap3d_node.settings.uv_selection_mode = tile_uvmode_dropdown.selected
	_is_loading_from_node = false

	if _on_enabled_arched_tiles_toggled:
		current_tilemap3d_node.settings.enable_arched_tiles = enabled_arched_tiles_checkbox.button_pressed


func _clear_ui() -> void:
	_clear_texture_ui()
	if tile_picker_size_x:
		tile_picker_size_x.value = GlobalConstants.DEFAULT_TILE_SIZE.x
	if tile_picker_size_y:
		tile_picker_size_y.value = GlobalConstants.DEFAULT_TILE_SIZE.y
	_sync_tile_set_size_spinboxes(GlobalConstants.DEFAULT_TILE_SIZE)
	if grid_size_spinbox:
		grid_size_spinbox.value = GlobalConstants.DEFAULT_GRID_SIZE

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



func _clear_texture_ui() -> void:
	current_texture = null
	if tileset_display:
		tileset_display.texture = null
	if texture_path_label:
		texture_path_label.text = "No texture loaded"
	if selection_highlight:
		selection_highlight.visible = false

func _on_load_texture_pressed() -> void:
	if _existing_tileset_has_terrains() and _texture_change_warning_dialog:
		_texture_change_warning_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_CONFIRM))
		return

	if load_texture_dialog:
		load_texture_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_DEFAULT))


func _existing_tileset_has_terrains() -> bool:
	if current_tilemap3d_node == null or current_tilemap3d_node.settings == null:
		return false
	var ts: TileSet = current_tilemap3d_node.get_tileset()
	if ts == null:
		return false
	return ts.get_terrain_sets_count() > 0


func _on_texture_change_confirmed() -> void:
	clear_tileset_requested.emit()

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

	if current_tilemap3d_node and current_tilemap3d_node.settings:
		var tileset: TileSet = TileAtlasResolver.build_tileset_from_texture(texture, _tile_size)
		_apply_loaded_tileset(tileset)

	_save_ui_to_settings()

	initialize_animated_tile_manager()

	tileset_loaded.emit(texture)


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
	current_tilemap3d_node.set_tileset(new_tileset)
	settings.active_source_id = 0
	settings._settings_format_version = 1
	settings.autotile_tileset = new_tileset
	settings.autotile_source_id = 0

func _on_open_tileset_editor_pressed() -> void:
	var tileset: TileSet = current_tilemap3d_node.get_tileset() if current_tilemap3d_node else null
	if tileset:
		var ei: Object = Engine.get_singleton("EditorInterface")
		if ei:
			ei.edit_resource(tileset)

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
	var tileset: TileSet = current_tilemap3d_node.get_tileset() if current_tilemap3d_node else null
	if not tileset:
		push_warning("No TileSet Resource Loaded")
		return

	var dialog := FileDialog.new()
	add_child(dialog)

	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_DEFAULT))

	var save_file_path: String = await dialog.file_selected
	dialog.queue_free()

	if not save_file_path.ends_with(".tres") and not save_file_path.ends_with(".res"):
		save_file_path = save_file_path + ".res"

	var error: Error = ResourceSaver.save(tileset, save_file_path)
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


func _auto_fix_texture_compression(texture: Texture2D) -> bool:
	if not texture or texture.resource_path.is_empty():
		return false
	var texture_path: String = texture.resource_path
	var import_path: String = texture_path + ".import"

	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		push_warning("TilesetPanel: Cannot access .import file for texture: " + texture_path)
		return false
	config.set_value("params", "compress/mode", 0)
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


func _on_tileset_resource_changed() -> void:
	# Guard: this can be connected per-node (see set_active_node); bail if the node
	# or tab went away so we never deref a stale reference.
	if current_tilemap3d_node == null or auto_tile_tab == null:
		return
	auto_tile_tab.refresh_terrains()
	var tileset: TileSet = current_tilemap3d_node.get_tileset() if current_tilemap3d_node else null
	if tileset and texture_path_label:
		texture_path_label.text = tileset.resource_path if tileset.resource_path else "Unsaved TileSet"

	_on_autotile_data_changed()


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
	if has_selection and tileset_display:
		tileset_display._update_tile_selection_preview()

	if current_tilemap3d_node and current_tilemap3d_node.settings:
		current_tilemap3d_node.settings.picker_tile_size = _tile_size


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
	var ts: TileSet = current_tilemap3d_node.get_tileset()
	var atlas: TileSetAtlasSource = TileAtlasResolver.get_active_atlas(current_tilemap3d_node)

	# Keep settings.changed and TileSet.changed from reloading this panel midway
	# through the update. Otherwise _load_settings_to_ui can read the old
	# TileSet.tile_size and snap the spinboxes back one edit behind.
	var prev_loading: bool = _is_loading_from_node
	_is_loading_from_node = true

	if ts != null and ts.tile_size != requested_size:
		ts.tile_size = requested_size
	if atlas != null:
		TileAtlasResolver.set_atlas_region_size_preserving_tiles(atlas, requested_size)

	current_tilemap3d_node.settings.tile_size = requested_size
	_is_loading_from_node = prev_loading
	_sync_tile_set_size_spinboxes(requested_size)


func _sync_tile_set_size_spinboxes(size: Vector2i) -> void:
	var prev_loading: bool = _is_loading_from_node
	_is_loading_from_node = true
	if tile_set_size_x:
		tile_set_size_x.value = size.x
	if tile_set_size_y:
		tile_set_size_y.value = size.y
	_is_loading_from_node = prev_loading



func _emit_tileset_selection_signals(programmatically: bool = false) -> void:
	if _selected_tiles.size() == 0:
		return
	elif _selected_tiles.size() == 1:
		tile_selected.emit(_selected_tiles[0])
	else:
		multi_tile_selected.emit(_selected_tiles, 0)
	
	if animated_tile_manager:
		animated_tile_manager.on_tileset_selection_changed(_selected_tiles, _tile_size,programmatically)


func select_tiles_programmatically(tiles: Array[Rect2]) -> void:
	_selected_tiles = tiles.duplicate()
	has_selection = tiles.size() > 0

	if has_selection and _tile_size.x > 0 and _tile_size.y > 0:
		selected_tile_coords = Vector2i(
			int(_selected_tiles[0].position.x / _tile_size.x),
			int(_selected_tiles[0].position.y / _tile_size.y)
		)

	if tileset_display:
		tileset_display.queue_redraw()

	_emit_tileset_selection_signals(true)


func _on_tile_uvmode_selected(index: int) -> void:
	if index == GlobalConstants.Tile_UV_Select_Mode.POINTS:
		if not _selected_tiles.is_empty() and tileset_display:
			var first_tile_uv: Rect2 = _selected_tiles[0]
			var tile_coord := Vector2i(
				int(first_tile_uv.position.x / _tile_size.x),
				int(first_tile_uv.position.y / _tile_size.y)
			)
			tileset_display.initialize_tile_vertices(tile_coord, _tile_size)

	_save_ui_to_settings()


func _on_select_vertices_data_changed(tile: Vector2i, corners: Array) -> void:
	print("TilesetPanel: Vertices data received for tile ", tile, ": ", corners)

func _on_show_plane_grids_toggled(enabled: bool) -> void:
	show_plane_grids_changed.emit(enabled)

func _on_cursor_step_selected(index: int) -> void:
	if _is_loading_from_node:
		return

	_save_ui_to_settings()

	var step_size: float = GlobalConstants.CURSOR_STEP_OPTIONS[index]
	cursor_step_size_changed.emit(step_size)

func _on_grid_snap_selected(index: int) -> void:
	if _is_loading_from_node:
		return

	_save_ui_to_settings()

	var snap_size: float = GlobalConstants.GRID_SNAP_OPTIONS[index]
	grid_snap_size_changed.emit(snap_size)


func _on_enabled_arched_tiles_toggled(enabled: bool) -> void:
	if _is_loading_from_node:
		return

	_save_ui_to_settings()










func _on_box_z_fighting_checkbox_toggled(button_pressed: bool) -> void:
	if _is_loading_from_node:
		return

	if current_tilemap3d_node and current_tilemap3d_node.settings:
		current_tilemap3d_node.settings.auto_resolve_box_z_fighting = button_pressed

	box_z_fighting_changed.emit(button_pressed)


func _on_grid_size_value_changed(new_value: float) -> void:

	if not current_tilemap3d_node:
		return

	if _is_loading_from_node:
		return

	if current_tilemap3d_node.settings:
		var current_grid_size: float = current_tilemap3d_node.settings.grid_size
		if abs(new_value - current_grid_size) < 0.001:
			return

	_pending_grid_size = new_value
	if grid_size_confirm_dialog:
		grid_size_confirm_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_CONFIRM))

	if grid_size_spinbox:
		grid_size_spinbox.editable = false

func _on_grid_size_confirmed() -> void:

	_save_ui_to_settings()

	grid_size_changed.emit(_pending_grid_size)

	if grid_size_spinbox:
		await get_tree().create_timer(0.5).timeout
		grid_size_spinbox.editable = true

func _on_grid_size_canceled() -> void:
	if grid_size_spinbox:
		if current_tilemap3d_node and current_tilemap3d_node.settings:
			grid_size_spinbox.value = current_tilemap3d_node.settings.grid_size
		else:
			grid_size_spinbox.value = GlobalConstants.DEFAULT_GRID_SIZE
		grid_size_spinbox.editable = true

func _on_texture_filter_selected(index: int) -> void:
	_save_ui_to_settings()

	texture_filter_changed.emit(index)

func _on_pixel_inset_changed(value: float) -> void:
	if _is_loading_from_node:
		return
	_save_ui_to_settings()
	pixel_inset_changed.emit(value)

func _on_bake_mesh_button_pressed() -> void:
	var bake_mode: GlobalConstants.BakeMode = GlobalConstants.BakeMode.ALPHA_AWARE if bake_alpha_check_box.button_pressed else GlobalConstants.BakeMode.NORMAL
	_bake_mesh_requested.emit(bake_mode)


func _on_create_collision_button_pressed() -> void:
	var bake_mode: GlobalConstants.BakeMode = GlobalConstants.BakeMode.ALPHA_AWARE if collision_alpha_check_box.button_pressed else GlobalConstants.BakeMode.NORMAL
	
	var backface_collision: bool = backface_collision_check_box.button_pressed if backface_collision_check_box else false

	var save_external_collision: bool = save_collision_external_check_box.button_pressed if save_collision_external_check_box else false

	create_collision_requested.emit(bake_mode, backface_collision, save_external_collision)



func set_tiling_mode_from_external(new_mode: GlobalConstants.MainAppMode) -> void:
	_current_tiling_mode = new_mode

	if not _tab_container:
		return

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


func _on_autotile_terrain_selected(terrain_id: int) -> void:
	autotile_terrain_selected.emit(terrain_id)


func _on_autotile_data_changed() -> void:
	autotile_data_changed.emit()
	print("TilesetPanel: Autotile data changed - forwarding signal")


func _on_zoom_requested(direction: int, focal_point: Vector2) -> void:
	if direction > 0:
		_handle_zoom_in(focal_point)
	else:
		_handle_zoom_out(focal_point)

func _on_zoom_slider_changed(value: float) -> void:
	if _is_updating_zoom:
		return
	_apply_zoom(value)

func _apply_zoom(new_zoom: float, focal_point: Vector2 = Vector2.ZERO) -> void:
	if not Engine.is_editor_hint():
		return
	if not tileset_display or not current_texture or not scroll_container:
		return

	new_zoom = clamp(new_zoom, GlobalConstants.TILESET_MIN_ZOOM, GlobalConstants.TILESET_MAX_ZOOM)

	var zoom_ratio: float = new_zoom / _current_zoom if _current_zoom > 0.0 else 1.0

	var old_scroll: Vector2 = Vector2(
		scroll_container.scroll_horizontal,
		scroll_container.scroll_vertical
	)

	var zoomed_size: Vector2 = Vector2(current_texture.get_size()) * new_zoom
	tileset_display.custom_minimum_size = zoomed_size
	tileset_display.size = zoomed_size

	_current_zoom = new_zoom

	_is_updating_zoom = true
	if tile_set_zoom_hslider:
		tile_set_zoom_hslider.value = _current_zoom
	_is_updating_zoom = false

	var new_scroll: Vector2 = (old_scroll + focal_point) * zoom_ratio - focal_point
	call_deferred("_set_scroll_position", new_scroll)

	_save_zoom_to_settings()

	tileset_display.queue_redraw()


func _handle_zoom_in(focal_point: Vector2) -> void:
	if not Engine.is_editor_hint(): return
	var new_zoom: float = _current_zoom * GlobalConstants.TILESET_ZOOM_STEP
	_apply_zoom(new_zoom, focal_point)

func _handle_zoom_out(focal_point: Vector2) -> void:
	if not Engine.is_editor_hint(): return
	var new_zoom: float = _current_zoom / GlobalConstants.TILESET_ZOOM_STEP
	_apply_zoom(new_zoom, focal_point)

func _reset_zoom_and_pan() -> void:
	_apply_zoom(GlobalConstants.TILESET_DEFAULT_ZOOM)

func _save_zoom_to_settings() -> void:
	if not current_tilemap3d_node or not current_tilemap3d_node.settings:
		return

	var was_loading: bool = _is_loading_from_node
	_is_loading_from_node = true

	current_tilemap3d_node.settings.tileset_zoom = _current_zoom

	_is_loading_from_node = was_loading

func _set_scroll_position(scroll_pos: Vector2) -> void:
	if not scroll_container:
		return

	scroll_container.scroll_horizontal = int(scroll_pos.x)
	scroll_container.scroll_vertical = int(scroll_pos.y)
