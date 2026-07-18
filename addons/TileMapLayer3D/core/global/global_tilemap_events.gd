class_name GlobalTileMapEvents
extends RefCounted

static var _instance: GlobalTileMapEvents = null

signal tile_texture_selected(texture: Texture2D, grid_size: Vector2)
signal request_sprite_mesh_creation(current_texture: Texture2D, selected_tiles: Array[Rect2], tile_size: Vector2i, grid_size: float, filter_mode: int)

static func get_instance() -> GlobalTileMapEvents:
	if not Engine.is_editor_hint():
		return null
	if _instance == null:
		_instance = GlobalTileMapEvents.new()
	return _instance

static func emit_request_sprite_mesh_creation(current_texture: Texture2D, selected_tiles: Array[Rect2], tile_size: Vector2i, grid_size: float, filter_mode: int) -> void:
	var inst = get_instance()
	if inst:
		inst.request_sprite_mesh_creation.emit(current_texture, selected_tiles, tile_size, grid_size, filter_mode)

static func connect_request_sprite_mesh_creation(callable: Callable) -> void:
	var inst: GlobalTileMapEvents = get_instance()
	if inst and not inst.request_sprite_mesh_creation.is_connected(callable):
		inst.request_sprite_mesh_creation.connect(callable)


static func disconnect_request_sprite_mesh_creation(callable: Callable) -> void:
	var inst: GlobalTileMapEvents = get_instance()
	if inst and inst.request_sprite_mesh_creation.is_connected(callable):
		inst.request_sprite_mesh_creation.disconnect(callable)
