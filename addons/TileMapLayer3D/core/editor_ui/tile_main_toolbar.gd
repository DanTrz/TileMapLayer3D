@tool
class_name TileMainToolbar
extends VBoxContainer


signal main_toolbar_tiling_enabled_clicked(enabled: bool)

signal main_toolbar_mode_changed(mode: int, is_smart_select: bool)



@onready var enable_tiling_check_btn: CheckButton = %EnableTilingCheckBtn
@onready var manual_tile_button: Button = %ManualTileButton
@onready var smart_select_button: Button = %SmartSelectButton
@onready var auto_tile_button: Button = %AutoTileButton
@onready var animated_tiles_button: Button = %AnimatedTilesButton

@onready var sculp_tiles_button: Button = %SculpTilesButton
@onready var vertex_edit_button: Button = %VertexEditButton

@onready var settings_button: Button = %SettingsButton
var _updating_ui: bool = false

func _init() -> void:
	name = "TileMapLayer3DTopBar"

func _ready() -> void:
	prepare_ui_components()

func prepare_ui_components() -> void:
	enable_tiling_check_btn.toggled.connect(_on_enable_button_toggled)
	manual_tile_button.toggled.connect(_on_manual_button_toggled)
	smart_select_button.toggled.connect(_on_smartselect_button_toggled)
	auto_tile_button.toggled.connect(_on_auto_button_toggled)
	settings_button.toggled.connect(_on_settings_button_toggled)
	animated_tiles_button.toggled.connect(_on_animated_tiles_button_toggled)
	sculp_tiles_button.toggled.connect(_on_sculp_tiles_button_toggled)
	vertex_edit_button.toggled.connect(_on_vertex_edit_button_toggled)


	GlobalUtil.apply_button_theme(manual_tile_button, "BitMap", GlobalConstants.BUTTOM_MAIN_UI_SIZE)
	GlobalUtil.apply_button_theme(auto_tile_button, "TileSet", GlobalConstants.BUTTOM_MAIN_UI_SIZE)
	GlobalUtil.apply_button_theme(smart_select_button, "PluginScript", GlobalConstants.BUTTOM_MAIN_UI_SIZE)
	GlobalUtil.apply_button_theme(settings_button, "Tools", GlobalConstants.BUTTOM_MAIN_UI_SIZE)
	GlobalUtil.apply_button_theme(animated_tiles_button, "Animation", GlobalConstants.BUTTOM_MAIN_UI_SIZE)
	GlobalUtil.apply_button_theme(sculp_tiles_button, "TexturePreviewChannels", GlobalConstants.BUTTOM_MAIN_UI_SIZE)
	GlobalUtil.apply_button_theme(vertex_edit_button, "MeshItem", GlobalConstants.BUTTOM_MAIN_UI_SIZE)


func sync_from_settings(tilemap_settings: TileMapLayerSettings) -> void:
	if not tilemap_settings:
		_reset_to_defaults()
		return

	_updating_ui = true

	match tilemap_settings.main_app_mode:
		GlobalConstants.MainAppMode.MANUAL:
			manual_tile_button.button_pressed = true
		GlobalConstants.MainAppMode.AUTOTILE:
			auto_tile_button.button_pressed = true
		GlobalConstants.MainAppMode.SMART_OPERATIONS:
			smart_select_button.button_pressed = true
		GlobalConstants.MainAppMode.ANIMATED_TILES:
			animated_tiles_button.button_pressed = true
		GlobalConstants.MainAppMode.SCULPT:
			sculp_tiles_button.button_pressed = true
		GlobalConstants.MainAppMode.VERTEX_EDIT:
			vertex_edit_button.button_pressed = true
		GlobalConstants.MainAppMode.SETTINGS:
			settings_button.button_pressed = true
		_:
			manual_tile_button.button_pressed = true

	_updating_ui = false


func _reset_to_defaults() -> void:
	_updating_ui = true
	manual_tile_button.button_pressed = true
	_updating_ui = false


func set_enabled(enabled: bool) -> void:
	if enable_tiling_check_btn:
		enable_tiling_check_btn.set_pressed_no_signal(enabled)


func is_enabled() -> bool:
	if enable_tiling_check_btn:
		return enable_tiling_check_btn.button_pressed
	return false


func set_mode(mode: int) -> void:
	_updating_ui = true
	if mode == GlobalConstants.MainAppMode.AUTOTILE:
		auto_tile_button.button_pressed = true
	else:
		manual_tile_button.button_pressed = true
	_updating_ui = false


func _on_enable_button_toggled(pressed: bool) -> void:
	main_toolbar_tiling_enabled_clicked.emit(pressed)

func _on_manual_button_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if pressed:
		main_toolbar_mode_changed.emit(GlobalConstants.MainAppMode.MANUAL, false)

func _on_smartselect_button_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if pressed:
		main_toolbar_mode_changed.emit(GlobalConstants.MainAppMode.SMART_OPERATIONS, true)

func _on_auto_button_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if pressed:
		main_toolbar_mode_changed.emit(GlobalConstants.MainAppMode.AUTOTILE, false)

func _on_animated_tiles_button_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if pressed:
		main_toolbar_mode_changed.emit(GlobalConstants.MainAppMode.ANIMATED_TILES, false)

func _on_sculp_tiles_button_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if pressed:
		main_toolbar_mode_changed.emit(GlobalConstants.MainAppMode.SCULPT, false)


func _on_vertex_edit_button_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if pressed:
		main_toolbar_mode_changed.emit(GlobalConstants.MainAppMode.VERTEX_EDIT, false)


func _on_settings_button_toggled(pressed: bool) -> void:
	if _updating_ui:
		return
	if pressed:
		main_toolbar_mode_changed.emit(GlobalConstants.MainAppMode.SETTINGS, false)
