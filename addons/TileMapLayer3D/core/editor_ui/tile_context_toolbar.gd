# =============================================================================
# PURPOSE: Context UI component for TileMapLayer3D editor plugin
# =============================================================================
# This class manages the side toolbar with tile operation buttons:
#   - Rotation buttons (Q/E)
#   - Tilt button (R)
#   - Reset button (T)
#   - Flip button (F)
#   - Status display (current rotation/tilt/flip state)
@tool
class_name TileContextToolbar
extends HBoxContainer

# =============================================================================
# SECTION: SIGNALS
# =============================================================================

## Emitted when rotation is requested (direction: +1 CW, -1 CCW)
signal rotate_requested(direction: int)

## Emitted when tilt cycling is requested (shift: bool for reverse)
signal tilt_requested(reverse: bool)

## Emitted when reset to flat is requested
signal reset_requested()

## Emitted when face flip is requested
signal flip_requested()

## Emitted when SmartSelect button is pressed -# FUTURE FEATURE #TODO # DEBUG
signal smart_select_requested(is_toggle: bool)

# =============================================================================
# SECTION: MEMBER VARIABLES
# =============================================================================

## Rotate Right button (Q)
@onready var _rotate_right_btn: Button = $RotateRightBtn
## Rotate Left button (E)
@onready var _rotate_left_btn: Button = $RotateLeftBtn
## Tilt button (R)
@onready var _cycle_tilt_btn: Button = $CycleTiltBtn
## Reset button (T)
@onready var _reset_orientation_btn: Button = $ResetOrientationBtn
## Flip button (F)
@onready var _flip_face_btn: Button = $FlipFaceBtn
## Status label
@onready var _status_label: Label = $StatusLabel
## SmartSelect button (G) - FUTURE FEATURE #TODO # DEBUG
@onready var smart_select_btn: Button = $SmartSelectBtn

## UI Variables
var _updating_ui: bool = false
var ui_scale: float = 1.0
var editor_theme: Theme = null


# =============================================================================
# SECTION: INITIALIZATION
# =============================================================================

func _init() -> void:
	name = "TileContextToolbar"


func _ready() -> void:
	prepare_ui_components()
	

func prepare_ui_components() -> void:
	#Rotate Right (Q)
	_rotate_right_btn.pressed.connect(_on_rotate_right_pressed)
	apply_button_theme(_rotate_right_btn, "RotateRight")

	#Rotate Left (E)
	_rotate_left_btn.pressed.connect(_on_rotate_left_pressed)
	apply_button_theme(_rotate_left_btn, "RotateLeft")

	# Tilt (R)
	_cycle_tilt_btn.pressed.connect(_on_tilt_pressed)
	apply_button_theme(_cycle_tilt_btn, "FadeCross")

	# Reset (T)
	_reset_orientation_btn.pressed.connect(_on_reset_pressed)
	apply_button_theme(_reset_orientation_btn, "EditorPositionUnselected")

	# Flip (F)
	_flip_face_btn.toggled.connect(_on_flip_toggled)
	apply_button_theme(_flip_face_btn, "ExpandTree")

	#SmartSelect button (G) - FUTURE FEATURE #TODO # DEBUG
	smart_select_btn.pressed.connect(_on_smart_select_pressed)
	apply_button_theme(smart_select_btn, "EditPivot")

	# --- Status Label ---
	_status_label.text = "0°"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", int(10 * ui_scale))


func apply_button_theme(button: Button, icon_name: String) -> void:
	# Get editor scale and theme for proper sizing and icons
	if Engine.is_editor_hint():
		var ei: Object = Engine.get_singleton("EditorInterface")
		if ei:
			ui_scale = ei.get_editor_scale()
			editor_theme = ei.get_editor_theme()

	# Set minimum width for toolbar
	button.custom_minimum_size.x = 36 * ui_scale
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	if editor_theme and editor_theme.has_icon(icon_name, "EditorIcons"):
		button.icon = editor_theme.get_icon(icon_name, "EditorIcons")
	else:
		# Fallback to text if icon not found
		button.text = icon_name[0]  # Use first letter as fallback

## Set flip button state
func set_flipped(flipped: bool) -> void:
	_updating_ui = true
	_flip_face_btn.button_pressed = flipped
	_updating_ui = false


## Get flip state
func is_flipped() -> bool:
	return _flip_face_btn.button_pressed if _flip_face_btn else false


## Update the status display
## @param rotation_steps: Current rotation (0-3 = 0°, 90°, 180°, 270°)
## @param tilt_index: Current tilt index (0 = flat)
## @param is_flipped: Whether face is flipped
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

	# Sync tiling mode
	smart_select_btn.button_pressed = tilemap_settings.smart_select_mode
	# print("Syncing Smart Select from Settings - Mode is: ", tilemap_settings.smart_select_mode)

	_updating_ui = false

# =============================================================================
# SECTION: SIGNAL HANDLERS
# =============================================================================

func _on_rotate_right_pressed() -> void:
	rotate_requested.emit(-1)


func _on_rotate_left_pressed() -> void:
	rotate_requested.emit(+1)


func _on_tilt_pressed() -> void:
	# Check if shift is held for reverse tilt
	var reverse: bool = Input.is_key_pressed(KEY_SHIFT)
	tilt_requested.emit(reverse)


func _on_reset_pressed() -> void:
	reset_requested.emit()


func _on_flip_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	flip_requested.emit()


func _on_smart_select_pressed() -> void:
	# FUTURE FEATURE - TODO - DEBUG
	if _updating_ui:
		return
	smart_select_requested.emit(smart_select_btn.button_pressed)
	# print("Smart Select button pressed - Toggle is: ", smart_select_btn.button_pressed)

