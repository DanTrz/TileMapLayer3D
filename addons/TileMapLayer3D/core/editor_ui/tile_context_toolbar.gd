@tool
class_name TileContextToolbar
extends HBoxContainer

# --- Signals ---

## Emitted when rotation is requested (direction: +1 CW, -1 CCW)
signal rotate_btn_pressed(direction: int)

## Emitted when tilt cycling is requested (shift: bool for reverse)
signal tilt_btn_pressed(reverse: bool)

## Emitted when reset to flat is requested
signal reset_btn_pressed()

## Emitted when face flip is requested
signal flip_btn_pressed()

##Emmited when SmartSelect Mode is changed
signal smart_select_dropdown_changed(smart_mode: GlobalConstants.SmartSelectionMode)

## Emitted when SmartSelect operations REPLACE/DELETE buttons are pressed 
signal smart_select_operation_btn_pressed(smart_mode_operation: GlobalConstants.SmartSelectionOperation)
##	Emitted when mesh mode is selected from dropdown
signal mesh_mode_selection_changed(mesh_mode: GlobalConstants.MeshMode)
## Emitted when mesh mode depth spinbox value changes (for BOX/PRISM depth scaling)
signal mesh_mode_depth_changed(depth: float)

# Emitted when autotile mesh mode changes (FLAT_SQUARE or BOX_MESH only)
signal autotile_mesh_mode_changed(mesh_mode: int)
# Emitted when autotile depth scale changes (for BOX/PRISM mesh modes)
signal autotile_depth_changed(depth: float)

## Emitted when Sculpt Mode Brush changed (Size and Type)
signal sculp_brush_changed(brush_type: GlobalConstants.SculptBrushType, brush_size: float)

## Emitted when Any of the UI settings on Sculpt Mode changed 
signal sculp_mode_options_changed(draw_top: bool, draw_bottom: bool, flip_sides: bool, flip_top: bool, flip_bottom: bool)

signal smart_operations_mode_changed(smart_mode: GlobalConstants.SmartOperationsMainMode)

signal smart_fill_changed(fill_mode: int, width: float, fill_direction: int, flip_face: bool, ramp_sides: bool)

## Emitted when Vertex Edit Convert button is pressed
signal vertex_convert_pressed()

## Emitted when Vertex Edit Delete button is pressed
signal vertex_delete_pressed()

## Emitted when freeze-UV toggle is changed
signal freeze_uv_changed(enabled: bool)

# --- Member Variables ---

## Main UI Node Groups to show/hide based on mode
@onready var manual_mode_group: FlowContainer = %ManualModeGroup
@onready var auto_tile_mode_group: FlowContainer = %AutoTileModeGroup
@onready var sculp_mode_group: HBoxContainer = %SculpModeGroup

#smart operations groups
@onready var smart_operations_group: HBoxContainer = %SmartOperationtGroup
@onready var smart_select_group: HBoxContainer = %SmartSelectGroup
@onready var smart_fill_group: HBoxContainer = %SmartFillGroup

# Vertex Edit group
@onready var vertex_edit_group: HBoxContainer = %VertexEditGroup
@onready var vertex_convert_btn: Button = %VertexConvertBtn
@onready var vertex_delete_btn: Button = %VertexDeleteBtn

## Rotate Right button (Q)
@onready var _rotate_right_btn: Button = %RotateRightBtn
## Rotate Left button (E)
@onready var _rotate_left_btn: Button = %RotateLeftBtn
## Tilt button (R)
@onready var _cycle_tilt_btn: Button = %CycleTiltBtn
## Reset button (T)
@onready var _reset_orientation_btn: Button = %ResetOrientationBtn
## Flip button (F)
@onready var _flip_face_btn: Button = %FlipFaceBtn
## Freeze UV toggle (created programmatically after flip button)
@onready var _freeze_uv_btn: Button = %FreezeUVBtn
## Status label
@onready var _status_label: Label = %StatusLabel



@onready var smart_operation_opt_btn: OptionButton = %SmartOperationOptBtn
#Smart Select Controls
@onready var smart_select_mode_option_btn: OptionButton = %SmartSelectionModeOptBtn
@onready var smart_select_replace_btn: Button = %SmartSelectReplaceBtn
@onready var smart_select_delete_btn: Button = %SmartSelectDeleteBtn
@onready var smart_select_clear_btn: Button = %SmartSelectClearBtn
#Smart Fill Controls
@onready var smart_fill_mode_opt_btn: OptionButton = %SmartFillModeOptBtn
@onready var smart_fill_width_spin_box: SpinBox = %SmartFillWidthSpinBox
@onready var smart_fill_direction_opt_btn: OptionButton = %SmartFillDirectionOptBtn
@onready var smart_fill_face_flip_check_box: CheckBox = %SmartFillFaceFlipCheckBox
@onready var smart_fill_ramp_sides_check_box: CheckBox = %SmartFillRampSidesCheckBox

@onready var mesh_mode_dropdown: OptionButton = %MeshModeDropdown
@onready var mesh_mode_depth_spin_box: SpinBox = %MeshModeDepthSpinBox
@onready var auto_tile_mode_dropdown: OptionButton = %AutoTileModeDropdown
@onready var auto_tile_detph_spin_box: SpinBox = %AutoTileDetphSpinBox


@onready var mesh_mode_label: Label = %MeshModeLabel
@onready var mesh_mode_depth_lbl: Label = %MeshModeDepthLbl
# @onready var tile_size_label: Label = $ManualModeGroup/TileSizeControls/TileSizeLabel
@onready var tile_world_pos_label: Label = %TileWorldPosLabel
@onready var tile_grid_pos_label: Label = %TileGridPosLabel


#Sculp Mode Controls
# @onready var sculp_mode_btn: Button = %SculpModeBtn
@onready var sculp_brush_dropdown: OptionButton = %SculpBrushDropdown
@onready var sculpt_brush_size_hslider: HSlider = %SculptBrushSizeHSlider

@onready var sculp_draw_top_check_box: CheckBox = $SculpModeGroup/DrawTilesHBoxContainer/VBoxContainer/SculpDrawTopCheckBox
@onready var sculp_draw_bottom_check_box: CheckBox = $SculpModeGroup/DrawTilesHBoxContainer/VBoxContainer2/SculpDrawBottomCheckBox
@onready var sculp_flip_sides_check_box: CheckBox = $SculpModeGroup/FlipTilesHBoxContainer/VBoxContainer5/SculpFlipSidesCheckBox
@onready var sculp_flip_top_check_box: CheckBox = $SculpModeGroup/FlipTilesHBoxContainer/VBoxContainer3/SculpFlipTopCheckBox
@onready var sculp_flip_bottom_check_box: CheckBox = $SculpModeGroup/FlipTilesHBoxContainer/VBoxContainer4/SculpFlipBottomCheckBox


## UI Variables
var _updating_ui: bool = false

# --- Initialization ---

func _init() -> void:
	name = "TileContextToolbar"


func _ready() -> void:
	prepare_ui_components()
	

func prepare_ui_components() -> void:
	#Rotate Right (Q)
	_rotate_right_btn.pressed.connect(_on_rotate_right_pressed)
	GlobalUtil.apply_button_theme(_rotate_right_btn, "RotateRight", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	#Rotate Left (E)
	_rotate_left_btn.pressed.connect(_on_rotate_left_pressed)
	GlobalUtil.apply_button_theme(_rotate_left_btn, "RotateLeft", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	# Tilt (R)
	_cycle_tilt_btn.pressed.connect(_on_tilt_pressed)
	GlobalUtil.apply_button_theme(_cycle_tilt_btn, "FadeCross", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	# Reset (T)
	_reset_orientation_btn.pressed.connect(_on_reset_pressed)
	GlobalUtil.apply_button_theme(_reset_orientation_btn, "EditorPositionUnselected", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	# Flip (F)
	_flip_face_btn.toggled.connect(_on_flip_toggled)
	GlobalUtil.apply_button_theme(_flip_face_btn, "ExpandTree", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	# Freeze UV toggle — insert after flip button
	_freeze_uv_btn.toggled.connect(_on_freeze_uv_toggled)
	GlobalUtil.apply_button_theme(_freeze_uv_btn, "Pin", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	smart_select_replace_btn.pressed.connect(_on_smart_select_replace_pressed)
	GlobalUtil.apply_button_theme(smart_select_replace_btn, "Loop", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE) #Loop

	smart_select_delete_btn.pressed.connect(_on_smart_select_delete_pressed)
	GlobalUtil.apply_button_theme(smart_select_delete_btn, "Remove", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE) # Remove

	smart_select_clear_btn.pressed.connect(_on_smart_select_clear_pressed)
	GlobalUtil.apply_button_theme(smart_select_clear_btn, "Clear", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	# sculp_mode_btn.pressed.connect(_on_sculp_mode_btn_pressed)
	# GlobalUtil.apply_button_theme(sculp_mode_btn, "Sculpt", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	var ui_scale: float = GlobalUtil.get_editor_ui_scale()

	smart_operation_opt_btn.item_selected.connect(on_smart_operations_dropdown_changed)
	smart_operation_opt_btn.add_theme_font_size_override("font_size", int(10 * ui_scale))
	smart_operation_opt_btn.custom_minimum_size.x = GlobalConstants.BUTTOM_CONTEXT_UI_SIZE * ui_scale

	smart_select_mode_option_btn.item_selected.connect(_on_smart_select_mode_changed)
	smart_select_mode_option_btn.add_theme_font_size_override("font_size", int(10 * ui_scale))
	smart_select_mode_option_btn.custom_minimum_size.x = GlobalConstants.BUTTOM_CONTEXT_UI_SIZE * ui_scale

	# --- Status Label ---
	_status_label.text = "0°"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_label.label_settings.font_size = int(10 * ui_scale)

	# --- All other Labels ---
	# tile_size_label.label_settings.font_size = int(8 * ui_scale)
	tile_world_pos_label.label_settings.font_size = int(8 * ui_scale)
	tile_grid_pos_label.label_settings.font_size = int(8  * ui_scale)
	mesh_mode_label.label_settings.font_size = int(10 * ui_scale)
	mesh_mode_depth_lbl.label_settings.font_size = int(10 * ui_scale)

	# --- Spinbox controls  ---
	# tile_size_x.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	# tile_size_y.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	mesh_mode_depth_spin_box.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))

	mesh_mode_dropdown.item_selected.connect(_on_mesh_mode_selected)
	mesh_mode_depth_spin_box.value_changed.connect(_on_mesh_mode_depth_changed)

	#Sculp Mode controls
	sculp_brush_dropdown.item_selected.connect(_on_sculp_brush_selected)
	sculpt_brush_size_hslider.value_changed.connect(_on_sculpt_brush_size_changed)

	#Auto Tile Controls
	auto_tile_mode_dropdown.item_selected.connect(_on_auto_tile_mode_selected)
	auto_tile_detph_spin_box.value_changed.connect(_on_auto_tile_depth_changed)

	# Vertex Edit Controls
	vertex_convert_btn.pressed.connect(_on_vertex_convert_pressed)
	GlobalUtil.apply_button_theme(vertex_convert_btn, "MeshItem", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)
	vertex_delete_btn.pressed.connect(_on_vertex_delete_pressed)
	GlobalUtil.apply_button_theme(vertex_delete_btn, "Remove", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	#Smart Fill Controls
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

	# Rotation
	parts.append(str(rotation_deg) + "°")

	# Tilt indicator
	if tilt_index > 0:
		parts.append("T" + str(tilt_index))

	# Flip indicator
	if is_flipped:
		parts.append("F")

	_status_label.text = " ".join(parts)

	# Update flip button state
	_updating_ui = true
	_flip_face_btn.button_pressed = is_flipped
	_updating_ui = false



func sync_from_settings(tilemap_settings: TileMapLayerSettings) -> void:
	if not tilemap_settings:
		return
	_updating_ui = true

	# UI Items to sync:
	smart_select_mode_option_btn.select(tilemap_settings.smart_select_mode)
	smart_operation_opt_btn.selected = tilemap_settings.smart_operations_main_mode

	smart_fill_mode_opt_btn.selected = tilemap_settings.smart_fill_mode
	smart_fill_width_spin_box.value = tilemap_settings.smart_fill_width
	smart_fill_direction_opt_btn.selected = tilemap_settings.smart_fill_quad_growth_dir
	smart_fill_face_flip_check_box.button_pressed = tilemap_settings.smart_fill_flip_face
	smart_fill_ramp_sides_check_box.button_pressed = tilemap_settings.smart_fill_ramp_sides

	mesh_mode_dropdown.selected = tilemap_settings.mesh_mode
	mesh_mode_depth_spin_box.value = tilemap_settings.current_depth_scale

	auto_tile_mode_dropdown.selected = tilemap_settings.autotile_mesh_mode
	auto_tile_detph_spin_box.value = tilemap_settings.autotile_depth_scale

	sculp_brush_dropdown.selected = tilemap_settings.sculpt_brush_type
	sculpt_brush_size_hslider.value = tilemap_settings.sculpt_brush_size
	sculp_draw_bottom_check_box.button_pressed = tilemap_settings.sculpt_draw_bottom
	sculp_draw_top_check_box.button_pressed = tilemap_settings.sculpt_draw_top
	sculp_flip_sides_check_box.button_pressed = tilemap_settings.sculpt_flip_sides
	sculp_flip_top_check_box.button_pressed = tilemap_settings.sculpt_flip_top
	sculp_flip_bottom_check_box.button_pressed = tilemap_settings.sculpt_flip_bottom

	if _freeze_uv_btn:
		_freeze_uv_btn.button_pressed = tilemap_settings.freeze_uv_on_rotation

	# Sync visibility from mode + smart select state
	match tilemap_settings.main_app_mode:
		GlobalConstants.MainAppMode.MANUAL:
			manual_mode_group.visible = true
			smart_operations_group.visible = false
			auto_tile_mode_group.visible = false
			sculp_mode_group.visible = false
			vertex_edit_group.visible = false
			self.visible = true
		GlobalConstants.MainAppMode.AUTOTILE:
			manual_mode_group.visible = false
			smart_operations_group.visible = false
			auto_tile_mode_group.visible = true
			sculp_mode_group.visible = false
			vertex_edit_group.visible = false
			self.visible = true
		GlobalConstants.MainAppMode.SMART_OPERATIONS:
			manual_mode_group.visible = false
			smart_operations_group.visible = true
			auto_tile_mode_group.visible = false
			sculp_mode_group.visible = false
			vertex_edit_group.visible = false
			self.visible = true
		GlobalConstants.MainAppMode.ANIMATED_TILES:
			manual_mode_group.visible = false
			smart_operations_group.visible = false
			auto_tile_mode_group.visible = false
			sculp_mode_group.visible = false
			vertex_edit_group.visible = false
			# Animated mode: No context toolbar controls needed.
			# Manual operations (mesh mode, depth, Q/E/R/T/F) are blocked; FLAT_SQUARE is forced.
			self.visible = true
		GlobalConstants.MainAppMode.SCULPT:
			manual_mode_group.visible = false
			smart_operations_group.visible = false
			auto_tile_mode_group.visible = false
			sculp_mode_group.visible = true
			vertex_edit_group.visible = false
			self.visible = true
		GlobalConstants.MainAppMode.VERTEX_EDIT:
			manual_mode_group.visible = false
			smart_operations_group.visible = false
			auto_tile_mode_group.visible = false
			sculp_mode_group.visible = false
			vertex_edit_group.visible = true
			self.visible = true
		GlobalConstants.MainAppMode.SETTINGS:
			self.visible = false
		_:
			manual_mode_group.visible = true
			smart_operations_group.visible = true
			auto_tile_mode_group.visible = true
			sculp_mode_group.visible = true
			vertex_edit_group.visible = false
			self.visible = true
		
	on_smart_operations_dropdown_changed(tilemap_settings.smart_operations_main_mode)
	_updating_ui = false


func update_tile_position(world_pos: Vector3, grid_pos: Vector3, current_plane:int) -> void:

	match current_plane:
		0, 1: 
			grid_pos.y += GlobalConstants.GRID_ALIGNMENT_OFFSET.y # Y plane
		2, 3: 
			grid_pos.z += GlobalConstants.GRID_ALIGNMENT_OFFSET.z # Z plane
		4, 5: 
			grid_pos.x += GlobalConstants.GRID_ALIGNMENT_OFFSET.x # X plane
		_: 
			pass

	# print("plane is:" , current_plane)
	if tile_world_pos_label:
		tile_world_pos_label.text = "World: (%.1f, %.1f, %.1f)" % [world_pos.x, world_pos.y, world_pos.z]
	if tile_grid_pos_label:
		tile_grid_pos_label.text = "Grid: (%.1f, %.1f, %.1f)" % [grid_pos.x, grid_pos.y, grid_pos.z]
# --- Signal Handlers ---

func _on_rotate_right_pressed() -> void:
	rotate_btn_pressed.emit(-1)


func _on_rotate_left_pressed() -> void:
	rotate_btn_pressed.emit(+1)


func _on_tilt_pressed() -> void:
	# Check if shift is held for reverse tilt
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


func _on_mesh_mode_selected(index: int) -> void:
	if _updating_ui:
		return
	mesh_mode_selection_changed.emit(mesh_mode_dropdown.get_selected_id())

func _on_mesh_mode_depth_changed(value: float) -> void:
	if _updating_ui:
		return
	mesh_mode_depth_changed.emit(value)

func _on_auto_tile_mode_selected(index: int) -> void:
	if _updating_ui:
		return

	autotile_mesh_mode_changed.emit(auto_tile_mode_dropdown.get_selected_id())

func _on_auto_tile_depth_changed(value: float) -> void:
	if _updating_ui:
		return

	autotile_depth_changed.emit(value)

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
	# print("Smart Select mode changed - Mode is: ", mode)


func _on_smart_select_replace_pressed() -> void:
	smart_select_operation_btn_pressed.emit(GlobalConstants.SmartSelectionOperation.REPLACE)

	pass


func _on_smart_select_delete_pressed() -> void:
	smart_select_operation_btn_pressed.emit(GlobalConstants.SmartSelectionOperation.DELETE)

	pass

func _on_smart_select_clear_pressed():
	smart_select_operation_btn_pressed.emit(GlobalConstants.SmartSelectionOperation.CLEAR)

# func _on_sculp_mode_btn_pressed():
# 	print("Sculp mode button pressed")
# 	sculp_mode_btn_pressed.emit()

func _on_sculp_brush_selected(index: int) -> void:
	# print("Sculp brush type selected index: ", index)
	sculp_brush_changed.emit(sculp_brush_dropdown.get_selected_id(), sculpt_brush_size_hslider.value)

func _on_sculpt_brush_size_changed(value: float) -> void:
	# print("Sculp brush size changed: ", value)
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


# --- Vertex Edit Handlers ---

func _on_vertex_convert_pressed() -> void:
	vertex_convert_pressed.emit()


func _on_vertex_delete_pressed() -> void:
	vertex_delete_pressed.emit()
