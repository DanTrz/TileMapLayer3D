# =============================================================================
# PURPOSE: Side toolbar UI component for TileMapLayer3D editor plugin
# =============================================================================
# This class manages the side toolbar with tile operation buttons:
#   - Rotation buttons (Q/E)
#   - Tilt button (R)
#   - Reset button (T)
#   - Flip button (F)
#   - Status display (current rotation/tilt/flip state)
#
# USAGE:
#   Created and managed by TileEditorUI
#   Added to CONTAINER_SPATIAL_EDITOR_SIDE_LEFT
# =============================================================================

@tool
class_name TileSideToolbar
extends VBoxContainer

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

# =============================================================================
# SECTION: MEMBER VARIABLES
# =============================================================================

## Rotate CCW button (Q)
var _rotate_ccw_button: Button = null

## Rotate CW button (E)
var _rotate_cw_button: Button = null

## Tilt button (R)
var _tilt_button: Button = null

## Reset button (T)
var _reset_button: Button = null

## Flip button (F)
var _flip_button: Button = null

## Status label
var _status_label: Label = null

## Flag to prevent signal loops
var _updating_ui: bool = false

# =============================================================================
# SECTION: INITIALIZATION
# =============================================================================

func _init() -> void:
	name = "TileSideToolbar"


func _ready() -> void:
	_create_ui()


## Create all UI components
func _create_ui() -> void:
	# Get editor scale for proper sizing (dynamic access for web export compatibility)
	var scale: float = 1.0
	var editor_theme: Theme = null
	if Engine.is_editor_hint():
		var ei: Object = Engine.get_singleton("EditorInterface")
		if ei:
			scale = ei.get_editor_scale()
			editor_theme = ei.get_editor_theme()

	# Set minimum width for toolbar
	custom_minimum_size.x = 36 * scale

	# --- Q and E Rotation Buttons ---
	_rotate_ccw_button = _create_toolbar_button("RotateRight", "Rotate tile 90° counter-clockwise (Q)", scale, editor_theme)
	_rotate_ccw_button.pressed.connect(_on_rotate_ccw_pressed)
	add_child(_rotate_ccw_button)

	_rotate_cw_button = _create_toolbar_button("RotateLeft", "Rotate tile 90° clockwise (E)", scale, editor_theme)
	_rotate_cw_button.pressed.connect(_on_rotate_cw_pressed)
	add_child(_rotate_cw_button)

	# --- Separator ---
	add_child(_create_separator())

	# --- Tilt/Reset Buttons ---
	_tilt_button = _create_toolbar_button("FadeCross", "Cycle tilt angle (R, Shift+R for reverse)", scale, editor_theme)
	_tilt_button.pressed.connect(_on_tilt_pressed)
	add_child(_tilt_button)

	_reset_button = _create_toolbar_button("EditorPositionUnselected", "Reset to flat orientation (T)", scale, editor_theme)
	_reset_button.pressed.connect(_on_reset_pressed)
	add_child(_reset_button)

	# --- Separator ---
	add_child(_create_separator())

	# --- Flip Button ---
	_flip_button = _create_toolbar_button("ExpandTree", "Flip tile face (F)", scale, editor_theme)
	_flip_button.toggle_mode = true
	_flip_button.toggled.connect(_on_flip_toggled)
	add_child(_flip_button)

	# --- Separator ---
	add_child(_create_separator())

	# --- Status Label ---
	_status_label = Label.new()
	_status_label.text = "0°"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", int(10 * scale))
	add_child(_status_label)


## Create a toolbar button with icon from editor theme
func _create_toolbar_button(icon_name: String, tooltip: String, scale: float, editor_theme: Theme) -> Button:
	var button := Button.new()
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(32, 32) * scale
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Load icon from editor theme
	if editor_theme and editor_theme.has_icon(icon_name, "EditorIcons"):
		button.icon = editor_theme.get_icon(icon_name, "EditorIcons")
	else:
		# Fallback to text if icon not found
		button.text = icon_name[0]  # Use first letter as fallback

	return button


## Create a horizontal separator
func _create_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.custom_minimum_size.y = 8
	return sep

# =============================================================================
# SECTION: PUBLIC METHODS
# =============================================================================

## Set flip button state
func set_flipped(flipped: bool) -> void:
	_updating_ui = true
	_flip_button.button_pressed = flipped
	_updating_ui = false


## Get flip state
func is_flipped() -> bool:
	return _flip_button.button_pressed if _flip_button else false


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
	_flip_button.button_pressed = is_flipped
	_updating_ui = false

# =============================================================================
# SECTION: SIGNAL HANDLERS
# =============================================================================

func _on_rotate_ccw_pressed() -> void:
	rotate_requested.emit(-1)


func _on_rotate_cw_pressed() -> void:
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
