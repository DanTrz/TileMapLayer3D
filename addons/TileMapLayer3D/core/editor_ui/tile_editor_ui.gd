@tool
class_name TileEditorUI
extends RefCounted

const VIEWPORT_TOP: int = 1
const VIEWPORT_LEFT: int = 2
const VIEWPORT_RIGHT: int = 3
const VIEWPORT_BOTTOM: int = 4

const TileContextToolbarScene = preload("uid://dgitfqnhx4ghe")
const TileMainToolbarScene = preload("uid://dinh7e08nxmrc")



signal tiling_enabled_changed(enabled: bool)
signal tilemap_main_mode_changed(mode: int)
signal rotate_requested(direction: int)
signal tilt_requested(reverse: bool)
signal reset_requested()
signal flip_requested()

signal smart_select_operation_requested(smart_mode: GlobalConstants.SmartSelectionOperation)

signal smart_select_mode_changed(is_smart_select_on: bool, smart_mode: GlobalConstants.SmartSelectionMode)

signal vertex_convert_requested()
signal vertex_delete_requested()




var _plugin: Object = null
var _active_tilema3d_node: TileMapLayer3D = null
var _is_visible: bool = false


var _main_toolbar_scene: TileMainToolbar = null
var _context_toolbar: TileContextToolbar = null
var _main_toolbar_location: int = VIEWPORT_LEFT
var _contextual_toolbar_location: int = VIEWPORT_BOTTOM
var _tileset_panel: TilesetPanel = null


func initialize(plugin: Object) -> void:
	_plugin = plugin
	_create_main_toolbar()
	_create_context_toolbar()

	set_ui_visible(false)
	_sync_ui_from_node()


func cleanup() -> void:
	_disconnect_tileset_panel()
	_destroy_context_toolbar()
	_destroy_main_toolbar()
	_plugin = null
	_active_tilema3d_node = null
	_tileset_panel = null


func _create_main_toolbar() -> void:
	if not _plugin:
		return

	_main_toolbar_scene = TileMainToolbarScene.instantiate()
	
	_main_toolbar_scene.main_toolbar_tiling_enabled_clicked.connect(_on_tiling_enabled_changed)
	_main_toolbar_scene.main_toolbar_mode_changed.connect(_on_mode_changed)



	_plugin.add_control_to_container(_main_toolbar_location, _main_toolbar_scene)


func _destroy_main_toolbar() -> void:
	if _main_toolbar_scene and _plugin:
		_plugin.remove_control_from_container(_main_toolbar_location, _main_toolbar_scene)
		_main_toolbar_scene.queue_free()
		_main_toolbar_scene = null


func _create_context_toolbar() -> void:
	if not _plugin:
		return

	_context_toolbar = TileContextToolbarScene.instantiate()

	_context_toolbar.rotate_btn_pressed.connect(_on_rotate_btn_pressed)
	_context_toolbar.tilt_btn_pressed.connect(_on_tilt_btn_pressed)
	_context_toolbar.reset_btn_pressed.connect(_on_reset_btn_pressed)
	_context_toolbar.flip_btn_pressed.connect(_on_flip_btn_pressed)
	_context_toolbar.smart_select_dropdown_changed.connect(_on_smart_select_dropdown_changed)
	_context_toolbar.smart_select_operation_btn_pressed.connect(_on_smart_select_operation_btn_pressed)
	_context_toolbar.vertex_convert_pressed.connect(_on_vertex_convert_pressed)
	_context_toolbar.vertex_delete_pressed.connect(_on_vertex_delete_pressed)

	_plugin.add_control_to_container(_contextual_toolbar_location, _context_toolbar)


func _destroy_context_toolbar() -> void:
	if _context_toolbar and _plugin:
		_plugin.remove_control_from_container(_contextual_toolbar_location, _context_toolbar)
		_context_toolbar.queue_free()
		_context_toolbar = null


func _connect_tileset_panel() -> void:
	if not _tileset_panel:
		return

	if _tileset_panel.has_signal("tiling_mode_changed"):
		if not _tileset_panel.tiling_mode_changed.is_connected(_on_tileset_panel_mode_changed):
			_tileset_panel.tiling_mode_changed.connect(_on_tileset_panel_mode_changed)


func _disconnect_tileset_panel() -> void:
	if not _tileset_panel:
		return

	if _tileset_panel.has_signal("tiling_mode_changed"):
		if _tileset_panel.tiling_mode_changed.is_connected(_on_tileset_panel_mode_changed):
			_tileset_panel.tiling_mode_changed.disconnect(_on_tileset_panel_mode_changed)


func set_active_node(node: TileMapLayer3D) -> void:
	_active_tilema3d_node = node

	if node:
		_sync_ui_from_node()
	else:
		_reset_ui_state()


func set_tileset_panel(panel: Control) -> void:
	_disconnect_tileset_panel()

	_tileset_panel = panel

	_connect_tileset_panel()


func set_enabled(enabled: bool) -> void:
	if _main_toolbar_scene and _main_toolbar_scene.has_method("set_enabled"):
		_main_toolbar_scene.set_enabled(enabled)
	_is_visible = enabled


func is_enabled() -> bool:
	if _main_toolbar_scene and _main_toolbar_scene.has_method("is_enabled"):
		return _main_toolbar_scene.is_enabled()
	return false


func update_status(rotation_steps: int, tilt_index: int, is_flipped: bool) -> void:
	if _context_toolbar and _context_toolbar.has_method("update_status"):
		_context_toolbar.update_status(rotation_steps, tilt_index, is_flipped)


func set_ui_visible(visible: bool) -> void:
	if _main_toolbar_scene:
		_main_toolbar_scene.visible = visible

	if _context_toolbar:
		_context_toolbar.visible = visible
	_is_visible = visible


func _sync_ui_from_node() -> void:
	if not _active_tilema3d_node:
		return

	if _main_toolbar_scene and _main_toolbar_scene.has_method("sync_from_settings"):
		_main_toolbar_scene.sync_from_settings(_active_tilema3d_node.settings)

	if _context_toolbar and _context_toolbar.has_method("sync_from_settings"):
		_context_toolbar.sync_from_settings(_active_tilema3d_node.settings)



func _reset_ui_state() -> void:
	if _main_toolbar_scene and _main_toolbar_scene.has_method("sync_from_settings"):
		_main_toolbar_scene.sync_from_settings(null)
	
	if _context_toolbar and _context_toolbar.has_method("sync_from_settings"):
		_context_toolbar.sync_from_settings(null)


func _on_tiling_enabled_changed(pressed: bool) -> void:
	tiling_enabled_changed.emit(pressed)


func _on_mode_changed(mode: GlobalConstants.MainAppMode, is_smart_select: bool) -> void:
	if _active_tilema3d_node:
		var settings: TileMapLayerSettings = _active_tilema3d_node.get("settings")
		if settings:
			settings.main_app_mode = mode

	tilemap_main_mode_changed.emit(mode)

	if _tileset_panel and _tileset_panel.has_method("set_tiling_mode_from_external"):
		_tileset_panel.set_tiling_mode_from_external(mode)

	if mode == GlobalConstants.MainAppMode.AUTOTILE:
		smart_select_mode_changed.emit(false, 0)
	else:
		smart_select_mode_changed.emit(is_smart_select, _context_toolbar.smart_operation_opt_btn.get_selected_id())

	if _context_toolbar and _active_tilema3d_node and _context_toolbar.has_method("sync_from_settings"):
		_context_toolbar.sync_from_settings(_active_tilema3d_node.settings)


func _on_smart_select_dropdown_changed(smart_mode: GlobalConstants.SmartSelectionMode) -> void:
	if _active_tilema3d_node:
		smart_select_mode_changed.emit(_active_tilema3d_node.settings.is_smart_select_active, smart_mode)

func clear_smart_selection() -> void:
	if _active_tilema3d_node:
		_active_tilema3d_node.clear_highlights()
		_active_tilema3d_node.smart_selected_tiles.clear()


func _on_smart_select_operation_btn_pressed(smart_mode_operation: GlobalConstants.SmartSelectionOperation) -> void:
	smart_select_operation_requested.emit(smart_mode_operation)

	if smart_mode_operation == GlobalConstants.SmartSelectionOperation.CLEAR:
		clear_smart_selection()

func _on_tileset_panel_mode_changed(mode: int) -> void:
	if _main_toolbar_scene and _main_toolbar_scene.has_method("set_mode"):
		_main_toolbar_scene.set_mode(mode)
	# The plugin already handles this through its panel connection.


func _on_rotate_btn_pressed(direction: int) -> void:
	rotate_requested.emit(direction)


func _on_tilt_btn_pressed(reverse: bool) -> void:
	tilt_requested.emit(reverse)


func _on_reset_btn_pressed() -> void:
	reset_requested.emit()


func _on_flip_btn_pressed() -> void:
	flip_requested.emit()


func _on_vertex_convert_pressed() -> void:
	vertex_convert_requested.emit()


func _on_vertex_delete_pressed() -> void:
	vertex_delete_requested.emit()
