@tool
class_name TileContextToolbar
extends HBoxContainer


signal rotate_btn_pressed(direction: int)

signal tilt_btn_pressed(reverse: bool)

signal reset_btn_pressed()

signal flip_btn_pressed()

signal smart_select_dropdown_changed(smart_mode: GlobalConstants.SmartSelectionMode)

signal smart_select_operation_btn_pressed(smart_mode_operation: GlobalConstants.SmartSelectionOperation)
signal mesh_mode_selection_changed(mesh_mode: GlobalConstants.MeshMode)
signal mesh_mode_depth_changed(depth: float)
signal arch_radius_ratio_changed(ratio: float)

signal sculp_brush_changed(brush_type: GlobalConstants.SculptBrushType, brush_size: float)

signal sculp_mode_options_changed(draw_top: bool, draw_bottom: bool, flip_sides: bool, flip_top: bool, flip_bottom: bool)

signal smart_operations_mode_changed(smart_mode: GlobalConstants.SmartOperationsMainMode)

signal smart_fill_changed(fill_mode: int, width: float, fill_direction: int, flip_face: bool, ramp_sides: bool)

signal vertex_convert_pressed()

signal vertex_delete_pressed()

signal freeze_uv_changed(enabled: bool)

signal texture_repeat_mode_changed(mode: int)

signal depth_growth_mode_changed(mode: int)

@onready var main_tiling_group: FlowContainer = %MainTilingGroup
@onready var manual_mode_group: HBoxContainer = %ManualModeGroup
@onready var box_prism_group: HBoxContainer = %BoxPrismGroup

@onready var sculp_mode_group: HBoxContainer = %SculpModeGroup

@onready var smart_operations_group: HBoxContainer = %SmartOperationtGroup
@onready var smart_select_group: HBoxContainer = %SmartSelectGroup
@onready var smart_fill_group: HBoxContainer = %SmartFillGroup

@onready var vertex_edit_group: HBoxContainer = %VertexEditGroup
@onready var vertex_convert_btn: Button = %VertexConvertBtn
@onready var vertex_delete_btn: Button = %VertexDeleteBtn

@onready var _rotate_right_btn: Button = %RotateRightBtn
@onready var _rotate_left_btn: Button = %RotateLeftBtn
@onready var _cycle_tilt_btn: Button = %CycleTiltBtn
@onready var _reset_orientation_btn: Button = %ResetOrientationBtn
@onready var _flip_face_btn: Button = %FlipFaceBtn
@onready var _freeze_uv_btn: Button = %FreezeUVBtn
@onready var _status_label: Label = %StatusLabel



@onready var smart_operation_opt_btn: OptionButton = %SmartOperationOptBtn
@onready var smart_select_mode_option_btn: OptionButton = %SmartSelectionModeOptBtn
@onready var smart_select_replaceUV_btn: Button = %SmartSelectReplaceUVBtn
@onready var smart_select_delete_btn: Button = %SmartSelectDeleteBtn
@onready var smart_select_clear_btn: Button = %SmartSelectClearBtn
@onready var smart_select_replace_mesh_btn: Button = %SmartSelectReplaceMeshTypeBtn
@onready var smart_select_target_mesh_opt: SquareOptionButton = %SmartSelectTargetMeshTypeOpt
@onready var smart_fill_mode_opt_btn: OptionButton = %SmartFillModeOptBtn
@onready var smart_fill_width_spin_box: SpinBox = %SmartFillWidthSpinBox
@onready var smart_fill_direction_opt_btn: OptionButton = %SmartFillDirectionOptBtn
@onready var smart_fill_face_flip_check_box: CheckBox = %SmartFillFaceFlipCheckBox
@onready var smart_fill_ramp_sides_check_box: CheckBox = %SmartFillRampSidesCheckBox

@onready var mesh_mode_dropdown: SquareOptionButton = %MeshModeDropdown
@onready var mesh_mode_depth_spin_box: SpinBox = %MeshModeDepthSpinBox
@onready var arch_radius_lbl: Label = %ArchRadiusLbl
@onready var arch_radius_spin_box: SpinBox = %ArchRadiusSpinBox


@onready var mesh_mode_label: Label = %MeshModeLabel
@onready var mesh_mode_depth_lbl: Label = %MeshModeDepthLbl
@onready var tile_world_pos_label: Label = %TileWorldPosLabel
@onready var tile_grid_pos_label: Label = %TileGridPosLabel


@onready var sculp_brush_dropdown: OptionButton = %SculpBrushDropdown
@onready var sculpt_brush_size_hslider: HSlider = %SculptBrushSizeHSlider

@onready var sculp_draw_top_check_box: CheckBox = $SculpModeGroup/DrawTilesHBoxContainer/VBoxContainer/SculpDrawTopCheckBox
@onready var sculp_draw_bottom_check_box: CheckBox = $SculpModeGroup/DrawTilesHBoxContainer/VBoxContainer2/SculpDrawBottomCheckBox
@onready var sculp_flip_sides_check_box: CheckBox = $SculpModeGroup/FlipTilesHBoxContainer/VBoxContainer5/SculpFlipSidesCheckBox
@onready var sculp_flip_top_check_box: CheckBox = $SculpModeGroup/FlipTilesHBoxContainer/VBoxContainer3/SculpFlipTopCheckBox
@onready var sculp_flip_bottom_check_box: CheckBox = $SculpModeGroup/FlipTilesHBoxContainer/VBoxContainer4/SculpFlipBottomCheckBox

@onready var box_texture_repeat_checkbox: CheckBox = %BoxTextureRepeatCheckbox
@onready var box_depth_inward_checkbox: CheckBox = %BoxDepthInwardCheckbox

@onready var create_sprite_mesh_btn: Button = %CreateSpriteMeshBtn

var _current_settings: TileMapLayerSettings= null

var _updating_ui: bool = false


func _init() -> void:
	name = "TileContextToolbar"


func _ready() -> void:
	prepare_ui_components()


func prepare_ui_components() -> void:

	var ui_scale: float = GlobalUtil.get_editor_ui_scale()

	_rotate_right_btn.pressed.connect(_on_rotate_right_pressed)
	GlobalUtil.apply_button_theme(_rotate_right_btn, "RotateRight", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	_rotate_left_btn.pressed.connect(_on_rotate_left_pressed)
	GlobalUtil.apply_button_theme(_rotate_left_btn, "RotateLeft", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	_cycle_tilt_btn.pressed.connect(_on_tilt_pressed)
	GlobalUtil.apply_button_theme(_cycle_tilt_btn, "FadeCross", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	_reset_orientation_btn.pressed.connect(_on_reset_pressed)
	GlobalUtil.apply_button_theme(_reset_orientation_btn, "EditorPositionUnselected", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	_flip_face_btn.toggled.connect(_on_flip_toggled)
	GlobalUtil.apply_button_theme(_flip_face_btn, "ExpandTree", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	_freeze_uv_btn.toggled.connect(_on_freeze_uv_toggled)
	GlobalUtil.apply_button_theme(_freeze_uv_btn, "Pin", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	create_sprite_mesh_btn.pressed.connect(_on_create_sprite_mesh_btn_pressed)
	GlobalUtil.apply_button_theme(create_sprite_mesh_btn, "SpriteFrames", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	smart_select_replaceUV_btn.pressed.connect(_on_smart_select_replaceUV_pressed)
	GlobalUtil.apply_button_theme(smart_select_replaceUV_btn, "Loop", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	smart_select_delete_btn.pressed.connect(_on_smart_select_delete_pressed)
	GlobalUtil.apply_button_theme(smart_select_delete_btn, "Remove", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	smart_select_clear_btn.pressed.connect(_on_smart_select_clear_pressed)
	GlobalUtil.apply_button_theme(smart_select_clear_btn, "Clear", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	smart_select_replace_mesh_btn.pressed.connect(_on_smart_select_replace_mesh_pressed)
	GlobalUtil.apply_button_theme(smart_select_replace_mesh_btn, "MeshItem", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)


	smart_operation_opt_btn.item_selected.connect(on_smart_operations_dropdown_changed)
	smart_operation_opt_btn.add_theme_font_size_override("font_size", int(10 * ui_scale))
	smart_operation_opt_btn.custom_minimum_size.x = GlobalConstants.BUTTOM_CONTEXT_UI_SIZE * ui_scale

	smart_select_mode_option_btn.item_selected.connect(_on_smart_select_mode_changed)
	smart_select_mode_option_btn.add_theme_font_size_override("font_size", int(10 * ui_scale))
	smart_select_mode_option_btn.custom_minimum_size.x = GlobalConstants.BUTTOM_CONTEXT_UI_SIZE * ui_scale

	_status_label.text = "0°"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_label.label_settings.font_size = int(10 * ui_scale)

	tile_world_pos_label.label_settings.font_size = int(8 * ui_scale)
	tile_grid_pos_label.label_settings.font_size = int(8  * ui_scale)
	mesh_mode_label.label_settings.font_size = int(10 * ui_scale)
	mesh_mode_depth_lbl.label_settings.font_size = int(10 * ui_scale)

	mesh_mode_depth_spin_box.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	arch_radius_spin_box.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))

	mesh_mode_dropdown.item_selected.connect(_on_mesh_mode_selected)
	mesh_mode_depth_spin_box.value_changed.connect(_on_mesh_mode_depth_changed)
	arch_radius_spin_box.value_changed.connect(_on_arch_radius_ratio_changed)

	sculp_brush_dropdown.item_selected.connect(_on_sculp_brush_selected)
	sculpt_brush_size_hslider.value_changed.connect(_on_sculpt_brush_size_changed)


	vertex_convert_btn.pressed.connect(_on_vertex_convert_pressed)
	GlobalUtil.apply_button_theme(vertex_convert_btn, "MeshItem", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)
	vertex_delete_btn.pressed.connect(_on_vertex_delete_pressed)
	GlobalUtil.apply_button_theme(vertex_delete_btn, "Remove", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	smart_fill_mode_opt_btn.item_selected.connect(
		func (index: int): _emit_smart_fill_changed())

	smart_fill_width_spin_box.value_changed.connect(
		func (value: float): _emit_smart_fill_changed())

	smart_fill_direction_opt_btn.item_selected.connect(
		func (index: int): _emit_smart_fill_changed())

	smart_fill_face_flip_check_box.pressed.connect(
		func (): _emit_smart_fill_changed())

	smart_fill_ramp_sides_check_box.pressed.connect(
		func (): _emit_smart_fill_changed())

	sculp_draw_top_check_box.pressed.connect(_on_sculpt_mode_ui_changed)
	sculp_draw_bottom_check_box.pressed.connect(_on_sculpt_mode_ui_changed)
	sculp_flip_sides_check_box.pressed.connect(_on_sculpt_mode_ui_changed)
	sculp_flip_top_check_box.pressed.connect(_on_sculpt_mode_ui_changed)
	sculp_flip_bottom_check_box.pressed.connect(_on_sculpt_mode_ui_changed)

	
	box_texture_repeat_checkbox.toggled.connect(_on_texture_repeat_checkbox_toggled)
	box_texture_repeat_checkbox.add_theme_font_size_override("font_size", int(10 * ui_scale))
	box_texture_repeat_checkbox.button_pressed = true
	_on_texture_repeat_checkbox_toggled(true)

	box_depth_inward_checkbox.toggled.connect(_on_depth_inward_checkbox_toggled)
	box_depth_inward_checkbox.add_theme_font_size_override("font_size", int(10 * ui_scale))
	box_depth_inward_checkbox.button_pressed = true
	_on_depth_inward_checkbox_toggled(true)




func set_flipped(flipped: bool) -> void:
	_updating_ui = true
	_flip_face_btn.button_pressed = flipped
	_updating_ui = false


func is_flipped() -> bool:
	return _flip_face_btn.button_pressed if _flip_face_btn else false


func update_status(rotation_steps: int, tilt_index: int, is_flipped: bool) -> void:
	if not _status_label:
		return

	var rotation_deg: int = rotation_steps * 90
	var parts: PackedStringArray = []

	parts.append(str(rotation_deg) + "°")

	if tilt_index > 0:
		parts.append("T" + str(tilt_index))

	if is_flipped:
		parts.append("F")

	_status_label.text = " ".join(parts)

	_updating_ui = true
	_flip_face_btn.button_pressed = is_flipped
	_updating_ui = false



func sync_from_settings(tilemap_settings: TileMapLayerSettings) -> void:
	if not tilemap_settings:
		return
	_updating_ui = true
	_current_settings = tilemap_settings

	if _current_settings:
		show_hide_arch_tiles(_current_settings.enable_arched_tiles)

	
	if box_texture_repeat_checkbox:
		box_texture_repeat_checkbox.button_pressed = (_current_settings.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT)

	if box_depth_inward_checkbox:
		box_depth_inward_checkbox.button_pressed = (_current_settings.depth_growth_mode == GlobalConstants.DepthGrowthMode.INWARD)

	smart_select_mode_option_btn.select(_current_settings.smart_select_mode)
	smart_operation_opt_btn.selected = _current_settings.smart_operations_main_mode

	smart_fill_mode_opt_btn.selected = _current_settings.smart_fill_mode
	smart_fill_width_spin_box.value = _current_settings.smart_fill_width
	smart_fill_direction_opt_btn.selected = _current_settings.smart_fill_quad_growth_dir
	smart_fill_face_flip_check_box.button_pressed = _current_settings.smart_fill_flip_face
	smart_fill_ramp_sides_check_box.button_pressed = _current_settings.smart_fill_ramp_sides

	mesh_mode_dropdown.selected = _current_settings.mesh_mode
	mesh_mode_depth_spin_box.value = _current_settings.current_depth_scale
	arch_radius_spin_box.value = _current_settings.arch_radius_ratio
	_update_mesh_mode_controls_visibility(_current_settings.mesh_mode)

	

	sculp_brush_dropdown.selected = _current_settings.sculpt_brush_type
	print("Syncing sculpt brush type: ", _current_settings.sculpt_brush_type)
	sculpt_brush_size_hslider.value = _current_settings.sculpt_brush_size
	sculp_draw_bottom_check_box.button_pressed = _current_settings.sculpt_draw_bottom
	sculp_draw_top_check_box.button_pressed = _current_settings.sculpt_draw_top
	sculp_flip_sides_check_box.button_pressed = _current_settings.sculpt_flip_sides
	sculp_flip_top_check_box.button_pressed = _current_settings.sculpt_flip_top
	sculp_flip_bottom_check_box.button_pressed = _current_settings.sculpt_flip_bottom


	if _freeze_uv_btn:
		_freeze_uv_btn.button_pressed = _current_settings.freeze_uv_on_rotation
		



	match tilemap_settings.main_app_mode:
		GlobalConstants.MainAppMode.MANUAL:
			main_tiling_group.visible = true
			manual_mode_group.visible = true
			smart_operations_group.visible = false
			sculp_mode_group.visible = false
			vertex_edit_group.visible = false
			self.visible = true
		GlobalConstants.MainAppMode.AUTOTILE:
			main_tiling_group.visible = true
			manual_mode_group.visible = false
			smart_operations_group.visible = false
			sculp_mode_group.visible = false
			vertex_edit_group.visible = false
			self.visible = true
		GlobalConstants.MainAppMode.SMART_OPERATIONS:
			main_tiling_group.visible = false
			manual_mode_group.visible = false
			smart_operations_group.visible = true
			sculp_mode_group.visible = false
			vertex_edit_group.visible = false
			self.visible = true
		GlobalConstants.MainAppMode.ANIMATED_TILES:
			main_tiling_group.visible = false
			manual_mode_group.visible = false
			smart_operations_group.visible = false
			sculp_mode_group.visible = false
			vertex_edit_group.visible = false
			self.visible = true
		GlobalConstants.MainAppMode.SCULPT:
			main_tiling_group.visible = false
			manual_mode_group.visible = false
			smart_operations_group.visible = false
			sculp_mode_group.visible = true
			vertex_edit_group.visible = false
			self.visible = true
		GlobalConstants.MainAppMode.VERTEX_EDIT:
			main_tiling_group.visible = false
			manual_mode_group.visible = false
			smart_operations_group.visible = false
			sculp_mode_group.visible = false
			vertex_edit_group.visible = true
			self.visible = true
		GlobalConstants.MainAppMode.SETTINGS:
			self.visible = false
		_:
			main_tiling_group.visible = true
			manual_mode_group.visible = true
			smart_operations_group.visible = true
			sculp_mode_group.visible = true
			vertex_edit_group.visible = false
			self.visible = true
	
	box_prism_group.visible = true if (mesh_mode_dropdown.selected == GlobalConstants.MeshMode.BOX_MESH or mesh_mode_dropdown.selected == GlobalConstants.MeshMode.PRISM_MESH) else false

	on_smart_operations_dropdown_changed(tilemap_settings.smart_operations_main_mode)
	_updating_ui = false

func show_hide_arch_tiles(enable_arched_tiles: bool) -> void:
	mesh_mode_dropdown.create_items_from_enum()
	sculp_brush_dropdown.create_items_from_enum()

	if not enable_arched_tiles:
		for i in range(mesh_mode_dropdown.item_count - 1, -1, -1):
			if mesh_mode_dropdown.get_item_id(i) >= GlobalConstants.MeshMode.FLAT_ARCH:
				mesh_mode_dropdown.remove_item(i)

		if mesh_mode_dropdown.get_selected_id() >= GlobalConstants.MeshMode.FLAT_ARCH:
			mesh_mode_dropdown.select(0)
			_on_mesh_mode_selected(0)

		sculp_brush_dropdown.remove_item(GlobalConstants.SculptBrushType.ARCHED_RECT)
		sculp_brush_dropdown.select(0)
		_on_sculp_brush_selected(0)


func update_tile_position(world_pos: Vector3, grid_pos: Vector3, current_plane:int) -> void:

	match current_plane:
		0, 1:
			grid_pos.y += GlobalConstants.GRID_ALIGNMENT_OFFSET.y
		2, 3:
			grid_pos.z += GlobalConstants.GRID_ALIGNMENT_OFFSET.z
		4, 5:
			grid_pos.x += GlobalConstants.GRID_ALIGNMENT_OFFSET.x
		_:
			pass

	if tile_world_pos_label:
		tile_world_pos_label.text = "World: (%.1f, %.1f, %.1f)" % [world_pos.x, world_pos.y, world_pos.z]
	if tile_grid_pos_label:
		tile_grid_pos_label.text = "Grid: (%.1f, %.1f, %.1f)" % [grid_pos.x, grid_pos.y, grid_pos.z]

func _on_rotate_right_pressed() -> void:
	rotate_btn_pressed.emit(-1)


func _on_rotate_left_pressed() -> void:
	rotate_btn_pressed.emit(+1)


func _on_tilt_pressed() -> void:
	var reverse: bool = Input.is_key_pressed(KEY_SHIFT)
	tilt_btn_pressed.emit(reverse)


func _on_reset_pressed() -> void:
	reset_btn_pressed.emit()


func _on_flip_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	flip_btn_pressed.emit()


func _on_freeze_uv_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	freeze_uv_changed.emit(pressed)

func _on_create_sprite_mesh_btn_pressed() -> void: 	
	if not _current_settings or _current_settings.selected_tiles.size() == 0:
		push_warning("SpriteMesh error: No tile selected for SpriteMesh generation")
		return

	if _current_settings.tileset_texture == null:
		push_warning("SpriteMesh error: No texture loaded for SpriteMesh generation")
		return

	var current_grid_size: float = _current_settings.grid_size
	current_grid_size = current_grid_size if current_grid_size > 0 else GlobalConstants.DEFAULT_GRID_SIZE
	
	var filter_mode: int = _current_settings.texture_filter_mode


	GlobalTileMapEvents.emit_request_sprite_mesh_creation(_current_settings.tileset_texture , _current_settings.selected_tiles, _current_settings.tile_size, current_grid_size, filter_mode)

func _on_mesh_mode_selected(index: int) -> void:
	if _updating_ui:
		return
	var selected_mode: int = mesh_mode_dropdown.get_selected_id()
	_update_mesh_mode_controls_visibility(selected_mode)

	mesh_mode_selection_changed.emit(selected_mode)

	box_prism_group.visible = true if (selected_mode == GlobalConstants.MeshMode.BOX_MESH or selected_mode == GlobalConstants.MeshMode.PRISM_MESH) else false


func _on_mesh_mode_depth_changed(value: float) -> void:
	if _updating_ui:
		return
	mesh_mode_depth_changed.emit(value)

func _on_arch_radius_ratio_changed(value: float) -> void:
	if _updating_ui:
		return
	arch_radius_ratio_changed.emit(value)

func _update_mesh_mode_controls_visibility(mesh_mode: int) -> void:
	var is_arch: bool = mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH or mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_I or mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER or mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I or mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP or mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I or mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO or mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C or mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I or mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S or mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I
	arch_radius_lbl.visible = is_arch
	arch_radius_spin_box.visible = is_arch

func on_smart_operations_dropdown_changed(index_mode: int) -> void:
	smart_operations_mode_changed.emit(index_mode)

	smart_select_group.visible = false
	smart_fill_group.visible = false
	match index_mode:
		GlobalConstants.SmartOperationsMainMode.SMART_FILL:
			smart_fill_group.visible = true
		GlobalConstants.SmartOperationsMainMode.SMART_SELECT:
			smart_select_group.visible = true


func _on_smart_select_mode_changed(mode: GlobalConstants.SmartSelectionMode) -> void:
	if _updating_ui:
		return

	smart_select_dropdown_changed.emit(smart_select_mode_option_btn.get_selected_id())


func _on_smart_select_replaceUV_pressed() -> void:
	smart_select_operation_btn_pressed.emit(GlobalConstants.SmartSelectionOperation.REPLACE_UV)

	pass


func _on_smart_select_delete_pressed() -> void:
	smart_select_operation_btn_pressed.emit(GlobalConstants.SmartSelectionOperation.DELETE)

	pass

func _on_smart_select_clear_pressed():
	smart_select_operation_btn_pressed.emit(GlobalConstants.SmartSelectionOperation.CLEAR)


func _on_smart_select_replace_mesh_pressed() -> void:
	smart_select_operation_btn_pressed.emit(GlobalConstants.SmartSelectionOperation.REPLACE_MESH_TYPE)


func get_smart_select_target_mesh_mode() -> GlobalConstants.MeshMode:
	return smart_select_target_mesh_opt.get_selected_id() as GlobalConstants.MeshMode


func _on_sculp_brush_selected(index: int) -> void:
	sculp_brush_changed.emit(sculp_brush_dropdown.get_selected_id(), sculpt_brush_size_hslider.value)

func _on_sculpt_brush_size_changed(value: float) -> void:
	sculp_brush_changed.emit(sculp_brush_dropdown.get_selected_id(), sculpt_brush_size_hslider.value)

func _on_sculpt_mode_ui_changed(_arg = null):
	sculp_mode_options_changed.emit(
		sculp_draw_top_check_box.button_pressed,
		sculp_draw_bottom_check_box.button_pressed,
		sculp_flip_sides_check_box.button_pressed,
		sculp_flip_top_check_box.button_pressed,
		sculp_flip_bottom_check_box.button_pressed)

func _emit_smart_fill_changed() -> void:
	smart_fill_changed.emit(
		smart_fill_mode_opt_btn.get_selected_id(),
		smart_fill_width_spin_box.value,
		smart_fill_direction_opt_btn.get_selected_id(),
		smart_fill_face_flip_check_box.button_pressed,
		smart_fill_ramp_sides_check_box.button_pressed)



func _on_vertex_convert_pressed() -> void:
	vertex_convert_pressed.emit()


func _on_vertex_delete_pressed() -> void:
	vertex_delete_pressed.emit()



func _on_texture_repeat_checkbox_toggled(check_box_pressed: bool) -> void:
	if _updating_ui:
		return

	var texture_mode: int = GlobalConstants.TextureRepeatMode.REPEAT if check_box_pressed else GlobalConstants.TextureRepeatMode.DEFAULT

	texture_repeat_mode_changed.emit(texture_mode)

func _on_depth_inward_checkbox_toggled(check_box_pressed: bool) -> void:
	if _updating_ui:
		return

	var depth_growth_mode: int = GlobalConstants.DepthGrowthMode.INWARD if check_box_pressed else GlobalConstants.DepthGrowthMode.OUTWARD

	depth_growth_mode_changed.emit(depth_growth_mode)
