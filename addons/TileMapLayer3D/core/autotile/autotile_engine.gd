@tool
class_name AutotileEngine
extends RefCounted


signal lookup_rebuilt()

var _tileset: TileSet
var _source_id: int
var _terrain_set: int

var _reader: TileSetTerrainReader
var _mapper: TileSetBitmaskMapper

var _bitmask_cache: Dictionary = {}


func _init(tileset: TileSet = null, source_id: int = GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID, terrain_set: int = GlobalConstants.AUTOTILE_DEFAULT_TERRAIN_SET) -> void:
	if tileset:
		setup(tileset, source_id, terrain_set)


func setup(tileset: TileSet, source_id: int = GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID, terrain_set: int = GlobalConstants.AUTOTILE_DEFAULT_TERRAIN_SET) -> void:
	_tileset = tileset
	_source_id = source_id
	_terrain_set = terrain_set

	if tileset:
		_reader = TileSetTerrainReader.new(tileset, source_id, terrain_set)
		_mapper = TileSetBitmaskMapper.new(tileset, source_id, terrain_set)
		rebuild_lookup()
	else:
		_reader = null
		_mapper = null


func rebuild_lookup() -> void:
	if _mapper:
		_mapper.build()
		_bitmask_cache.clear()
		lookup_rebuilt.emit()


func rebuild_bitmask_cache(tile_map_layer: TileMapLayer3D) -> void:
	_bitmask_cache.clear()

	if not tile_map_layer:
		return

	var cached_count: int = 0
	var tile_count: int = tile_map_layer.get_tile_count()

	for i in range(tile_count):
		var tile_info: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(i)
		if tile_info == null:
			continue

		var terrain_id: int = tile_info.terrain_id

		if terrain_id < 0:
			continue

		var grid_pos: Vector3 = tile_info.grid_position
		var orientation: int = tile_info.orientation
		var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

		var bitmask: int = calculate_bitmask(
			grid_pos,
			orientation,
			terrain_id,
			tile_map_layer
		)
		_bitmask_cache[tile_key] = bitmask
		cached_count += 1

	pass


func is_ready() -> bool:
	return _reader != null and _reader.is_valid() and _mapper != null and not _mapper.is_empty()


func get_terrains() -> Array[Dictionary]:
	if _reader:
		return _reader.get_terrains()
	return []


func get_terrain_count() -> int:
	if _reader:
		return _reader.get_terrain_count()
	return 0


func calculate_bitmask(
	grid_pos: Vector3,
	orientation: int,
	terrain_id: int,
	tile_map_layer: TileMapLayer3D
) -> int:
	var bitmask: int = 0

	for dir_name: String in PlaneCoordinateMapper.NEIGHBOR_OFFSETS_2D.keys():
		var offset_2d: Vector2i = PlaneCoordinateMapper.NEIGHBOR_OFFSETS_2D[dir_name]
		var offset_3d: Vector3 = PlaneCoordinateMapper.offset_to_3d(offset_2d, orientation)
		var neighbor_pos: Vector3 = grid_pos + offset_3d

		if _has_matching_terrain(neighbor_pos, orientation, terrain_id, tile_map_layer):
			bitmask |= PlaneCoordinateMapper.BITMASK_VALUES[dir_name]

	return bitmask


func _has_matching_terrain(
	grid_pos: Vector3,
	orientation: int,
	terrain_id: int,
	tile_map_layer: TileMapLayer3D
) -> bool:
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

	if not tile_map_layer.has_tile(tile_key):
		return false

	return tile_map_layer.get_tile_terrain_id(tile_key) == terrain_id


func get_autotile_uv(
	grid_pos: Vector3,
	orientation: int,
	terrain_id: int,
	tile_map_layer: TileMapLayer3D
) -> Rect2:
	if not is_ready():
		return Rect2()

	var bitmask: int = calculate_bitmask(
		grid_pos, orientation, terrain_id, tile_map_layer
	)

	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
	_bitmask_cache[tile_key] = bitmask

	return _mapper.get_uv(terrain_id, bitmask, _mapper.position_seed(grid_pos))


func update_neighbors(
	grid_pos: Vector3,
	orientation: int,
	tile_map_layer: TileMapLayer3D
) -> Dictionary:
	var updates: Dictionary = {}

	var neighbors: Array[Vector3] = PlaneCoordinateMapper.get_neighbor_positions_3d(
		grid_pos, orientation
	)

	for neighbor_pos: Vector3 in neighbors:
		var tile_key: int = GlobalUtil.make_tile_key(neighbor_pos, orientation)

		if not tile_map_layer.has_tile(tile_key):
			continue

		var neighbor_terrain_id: int = tile_map_layer.get_tile_terrain_id(tile_key)

		if neighbor_terrain_id < 0:
			continue

		var new_bitmask: int = calculate_bitmask(
			neighbor_pos, orientation, neighbor_terrain_id, tile_map_layer
		)

		var old_bitmask: int = _bitmask_cache.get(tile_key, -1)

		if new_bitmask != old_bitmask:
			var new_uv: Rect2 = _mapper.get_uv(neighbor_terrain_id, new_bitmask, _mapper.position_seed(neighbor_pos))
			updates[tile_key] = new_uv
			_bitmask_cache[tile_key] = new_bitmask

	return updates


func invalidate_tile(tile_key: int) -> void:
	_bitmask_cache.erase(tile_key)


func get_uv_for_bitmask(terrain_id: int, bitmask: int, seed_int: int = GlobalConstants.AUTOTILE_NO_SEED) -> Rect2:
	if _mapper:
		return _mapper.get_uv(terrain_id, bitmask, seed_int)
	return Rect2()


func position_seed(grid_pos: Vector3) -> int:
	if _mapper:
		return _mapper.position_seed(grid_pos)
	return GlobalConstants.AUTOTILE_NO_SEED


func clear_cache() -> void:
	_bitmask_cache.clear()


func get_tile_size() -> Vector2i:
	if _reader:
		return _reader.get_tile_size()
	return GlobalConstants.DEFAULT_TILE_SIZE


func get_texture() -> Texture2D:
	if _reader:
		return _reader.get_texture()
	return null


func get_terrain_name(terrain_id: int) -> String:
	if _reader:
		return _reader.get_terrain_name(terrain_id)
	return ""


func get_terrain_color(terrain_id: int) -> Color:
	if _reader:
		return _reader.get_terrain_color(terrain_id)
	return Color.WHITE


func has_terrain_tiles(terrain_id: int) -> bool:
	if _mapper:
		return _mapper.has_terrain(terrain_id)
	return false


func count_terrain_tiles(terrain_id: int) -> int:
	if _reader:
		return _reader.count_configured_tiles(terrain_id)
	return 0


func get_tileset() -> TileSet:
	return _tileset


func get_stats() -> Dictionary:
	var stats := {
		"ready": is_ready(),
		"cache_size": _bitmask_cache.size(),
		"tileset": _tileset.resource_path if _tileset else "null",
		"source_id": _source_id,
		"terrain_set": _terrain_set,
	}
	if _mapper:
		stats["mapper"] = _mapper.get_stats()
	if _reader:
		stats["terrain_count"] = _reader.get_terrain_count()
	return stats
