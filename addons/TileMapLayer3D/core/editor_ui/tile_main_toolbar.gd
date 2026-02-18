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
signal main_toolbar_tiling_enabled_clicked(enabled: bool)

## Emitted when any mode button is clicked (Manual/Smart Select/Auto)
## Carries both mode and smart select state as one atomic event
signal main_toolbar_mode_changed(mode: int, is_smart_select: bool)


# =============================================================================
# SECTION: MEMBER VARIABLES
# =============================================================================

## Enable toggle button
@onready var enable_tiling_check_btn: CheckButton = $EnableTilingCheckBtn


## Manual mode button
@onready var manual_tile_button: Button = $ManualTileButton

## Smart select mode button
@onready var smart_select_button: Button = $SmartSelectButton

## Auto mode button
@onready var auto_tile_button: Button = $AutoTileButton

## Flag to prevent signal loops during programmatic updates
var _updating_ui: bool = false

func _init() -> void:
	name = "TileMapLayer3DTopBar"

## Connect all UI components on READY via signals
func _ready() -> void:
	# Connect signals from UI components
	enable_tiling_check_btn.toggled.connect(_on_enable_button_toggled)
	manual_tile_button.toggled.connect(_on_manual_button_toggled)
	smart_select_button.toggled.connect(_on_smartselect_button_toggled)
	auto_tile_button.toggled.connect(_on_auto_button_toggled)

## Sync UI state from node settings
## @param settings: TileMapLayerSettings resource (or null to reset)
func sync_from_settings(tilemap_settings: TileMapLayerSettings) -> void:
	if not tilemap_settings:
		_reset_to_defaults()
		return

	_updating_ui = true

	# Sync tiling mode
	var tiling_mode: int = tilemap_settings.tiling_mode
	if tiling_mode == GlobalConstants.TileMode.AUTOTILE:
		auto_tile_button.button_pressed = true
	elif tiling_mode == GlobalConstants.TileMode.MANUAL and tilemap_settings.is_smart_select_active:
		smart_select_button.button_pressed = true
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

func _on_enable_button_toggled(pressed: bool) -> void:
	main_toolbar_tiling_enabled_clicked.emit(pressed)
	# print("Tiling enable toggled: " + str(pressed))

func _on_manual_button_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if pressed:
		main_toolbar_mode_changed.emit(GlobalConstants.TileMode.MANUAL, false)

func _on_smartselect_button_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if pressed:
		main_toolbar_mode_changed.emit(GlobalConstants.TileMode.MANUAL, true)

func _on_auto_button_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if pressed:
		main_toolbar_mode_changed.emit(GlobalConstants.TileMode.AUTOTILE, false)
