# =============================================================================
# PURPOSE: Main menu toolbar UI component for TileMapLayer3D editor plugin
# =============================================================================
# This class manages the top toolbar controls including:
#   - Enable toggle (activate/deactivate plugin)
#   - Mode buttons (Manual / Auto tiling)

@tool
class_name TileMainToolbar
extends VBoxContainer

# =============================================================================
# SECTION: SIGNALS
# =============================================================================

## Emitted when enable toggle changes
signal tiling_enabled_changed(enabled: bool)

## Emitted when tiling mode changes (Manual/Auto)
signal tile_mode_changed(mode: int)


# =============================================================================
# SECTION: MEMBER VARIABLES
# =============================================================================

## Enable toggle button
# var _enable_toggle: CheckButton = null
@onready var enable_tiling_check_btn: CheckButton = $EnableTilingCheckBtn

# ## Mode button group (exclusive selection)
# var _mode_button_group: ButtonGroup = null

## Manual mode button
# var _manual_button: Button = null
@onready var manual_tile_button: Button = $ManualTileButton


## Auto mode button
# var _auto_button: Button = null
@onready var auto_tile_button: Button = $AutoTileButton

## Flag to prevent signal loops during programmatic updates
var _updating_ui: bool = false

func _init() -> void:
	name = "TileMapLayer3DTopBar"

## Connect all UI components on READY via signals
func _ready() -> void:
	# Connect signals from UI components
	enable_tiling_check_btn.toggled.connect(_on_enable_toggled)
	manual_tile_button.toggled.connect(_on_manual_toggled)
	auto_tile_button.toggled.connect(_on_auto_toggled)

## Sync UI state from node settings
## @param settings: TileMapLayerSettings resource (or null to reset)
func sync_from_settings(settings: Resource) -> void:
	if not settings:
		_reset_to_defaults()
		return

	_updating_ui = true

	# Sync tiling mode
	var tiling_mode: int = settings.get("tiling_mode") if settings.get("tiling_mode") != null else GlobalConstants.TileMode.MANUAL
	if tiling_mode == GlobalConstants.TileMode.AUTOTILE:
		auto_tile_button.button_pressed = true
	else:
		manual_tile_button.button_pressed = true

	_updating_ui = false


## Reset UI to default state
func _reset_to_defaults() -> void:
	_updating_ui = true
	manual_tile_button.button_pressed = true
	_updating_ui = false


## Set enabled state without triggering signal
## @param enabled: Whether plugin is enabled
func set_enabled(enabled: bool) -> void:
	if enable_tiling_check_btn:
		enable_tiling_check_btn.set_pressed_no_signal(enabled)


## Get whether plugin is enabled
func is_enabled() -> bool:
	if enable_tiling_check_btn:
		return enable_tiling_check_btn.button_pressed
	return false


## Set tiling mode without triggering signal
## @param mode: MODE_MANUAL or MODE_AUTOTILE
func set_mode(mode: int) -> void:
	_updating_ui = true
	if mode == GlobalConstants.TileMode.AUTOTILE:
		auto_tile_button.button_pressed = true
	else:
		manual_tile_button.button_pressed = true
	_updating_ui = false


# ## Get current tiling mode
# func get_mode() -> int:
# 	if auto_tile_button and auto_tile_button.button_pressed:
# 		return GlobalConstants.TILING_MODE_AUTOTILE
# 	return GlobalConstants.TILING_MODE_MANUAL

# =============================================================================
# SECTION: SIGNAL HANDLERS
# =============================================================================

func _on_enable_toggled(pressed: bool) -> void:
	tiling_enabled_changed.emit(pressed)
	# print("Tiling enable toggled: " + str(pressed))

func _on_manual_toggled(pressed: bool) -> void:
	# print("_on_manual_toggled called with pressed=" + str(pressed))
	if _updating_ui:
		return
	if pressed:
		tile_mode_changed.emit(GlobalConstants.TileMode.MANUAL)
		# print("Manual mode selected")


func _on_auto_toggled(pressed: bool) -> void:
	# print("_on_auto_toggled called with pressed=" + str(pressed))

	if _updating_ui:
		return
	if pressed:
		tile_mode_changed.emit(GlobalConstants.TileMode.AUTOTILE)
		# print("Auto mode selected")
