@tool
class_name AutotilePlacementExtension
extends RefCounted



signal tile_placed(grid_pos: Vector3, orientation: int, terrain_id: int)

signal neighbors_updated(update_count: int)


var _engine: AutotileEngine
var _placement_manager: TilePlacementManager
var _tile_map_layer: TileMapLayer3D


var enabled: bool = false

var current_terrain_id: int = GlobalConstants.AUTOTILE_NO_TERRAIN


func setup(
	engine: AutotileEngine,
	placement_manager: TilePlacementManager,
	tile_map_layer: TileMapLayer3D
) -> void:
	_engine = engine
	_placement_manager = placement_manager
	_tile_map_layer = tile_map_layer


func is_ready() -> bool:
	return (
		enabled and
		_engine != null and
		_engine.is_ready() and
		_placement_manager != null and
		_tile_map_layer != null and
		current_terrain_id >= 0
	)


func get_autotile_uv(grid_pos: Vector3, orientation: int) -> Rect2:
	if not is_ready():
		return Rect2()

	if not PlaneCoordinateMapper.is_supported_orientation(orientation):
		return Rect2()

	return _engine.get_autotile_uv(
		grid_pos, orientation, current_terrain_id, _tile_map_layer
	)


func on_tile_placed(grid_pos: Vector3, orientation: int) -> int:
	if not enabled or not _engine:
		return 0

	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
	_engine.invalidate_tile(tile_key)
	if _tile_map_layer and _tile_map_layer.has_tile(tile_key):
		_engine.get_autotile_uv(grid_pos, orientation, current_terrain_id, _tile_map_layer)

	var update_count: int = _update_neighbors(grid_pos, orientation)

	tile_placed.emit(grid_pos, orientation, current_terrain_id)
	return update_count


func on_tile_erased(grid_pos: Vector3, orientation: int, terrain_id: int) -> int:
	if not _engine:
		return 0

	if terrain_id < 0:
		return 0

	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
	_engine.invalidate_tile(tile_key)

	return _update_neighbors(grid_pos, orientation)


func _update_neighbors(grid_pos: Vector3, orientation: int) -> int:
	if not _engine or not _placement_manager or not _tile_map_layer:
		return 0

	var updates: Dictionary = _engine.update_neighbors(grid_pos, orientation, _tile_map_layer)

	if updates.is_empty():
		return 0

	_placement_manager.begin_batch_update()

	for tile_key: int in updates.keys():
		var new_uv: Rect2 = updates[tile_key]
		_update_tile_uv(tile_key, new_uv)

	_placement_manager.end_batch_update()

	neighbors_updated.emit(updates.size())
	return updates.size()


func _update_tile_uv(tile_key: int, new_uv: Rect2) -> void:
	if not _tile_map_layer or not _tile_map_layer.has_tile(tile_key):
		return

	var binding_src: int = -1
	var binding_coords: Vector2i = Vector2i(-1, -1)
	var settings: TileMapLayerSettings = _tile_map_layer.settings
	if settings != null and TileAtlasResolver.is_valid_tileset(_tile_map_layer):
		var ts_size: Vector2i = TileAtlasResolver.get_tile_size(_tile_map_layer)
		if ts_size.x > 0 and ts_size.y > 0:
			var src_id: int = settings.active_source_id
			var candidate: Vector2i = Vector2i(
				int(round(new_uv.position.x / float(ts_size.x))),
				int(round(new_uv.position.y / float(ts_size.y)))
			)
			if TileAtlasResolver.coords_match_registered_cell(_tile_map_layer, src_id, candidate, new_uv):
				binding_src = src_id
				binding_coords = candidate

	_tile_map_layer.update_tile_uv(tile_key, new_uv, binding_src, binding_coords)


func set_engine(engine: AutotileEngine) -> void:
	_engine = engine


func get_engine() -> AutotileEngine:
	return _engine


func set_enabled(value: bool) -> void:
	enabled = value


func set_terrain(terrain_id: int) -> void:
	current_terrain_id = terrain_id


func get_terrain() -> int:
	return current_terrain_id
