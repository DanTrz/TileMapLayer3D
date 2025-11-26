# =============================================================================
# FILE: addons/TileMapLayer3D/core/autotile/autotile_engine.gd
# PURPOSE: Main autotiling orchestration - coordinates all operations
# DEPENDENCIES: TileSetTerrainReader, TileSetBitmaskMapper, PlaneCoordinateMapper
# =============================================================================
@tool
class_name AutotileEngine
extends RefCounted

## Main autotiling engine. Coordinates bitmask calculation,
## tile matching, and neighbor updates using Godot's TileSet data.
##
## Usage:
##   var engine := AutotileEngine.new(tileset)
##   var uv := engine.get_autotile_uv(grid_pos, orientation, terrain_id, placement_data)

signal lookup_rebuilt()

var _tileset: TileSet
var _source_id: int
var _terrain_set: int

var _reader: TileSetTerrainReader
var _mapper: TileSetBitmaskMapper

# Bitmask cache for placed tiles: tile_key (int) -> bitmask (int)
var _bitmask_cache: Dictionary = {}


func _init(tileset: TileSet = null, source_id: int = GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID, terrain_set: int = GlobalConstants.AUTOTILE_DEFAULT_TERRAIN_SET) -> void:
	if tileset:
		setup(tileset, source_id, terrain_set)


## Configure the engine with a TileSet
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


## Rebuild lookup tables from TileSet
## Call this when TileSet terrain configuration changes
func rebuild_lookup() -> void:
	if _mapper:
		_mapper.build()
		_bitmask_cache.clear()
		lookup_rebuilt.emit()


## Rebuilds bitmask cache from existing placement data (called after scene load)
## This ensures neighbor detection works correctly for tiles placed before reload
func rebuild_bitmask_cache(placement_data: Dictionary) -> void:
	_bitmask_cache.clear()

	var cached_count: int = 0
	for tile_key: int in placement_data.keys():
		var tile_data: TilePlacerData = placement_data[tile_key]

		# Only cache autotiled tiles (terrain_id >= 0)
		if tile_data.terrain_id < 0:
			continue

		var bitmask: int = calculate_bitmask(
			tile_data.grid_position,
			tile_data.orientation,
			tile_data.terrain_id,
			placement_data
		)
		_bitmask_cache[tile_key] = bitmask
		cached_count += 1

	if cached_count > 0:
		print("AutotileEngine: Rebuilt bitmask cache for ", cached_count, " autotiled tiles")


## Check if engine is ready for autotiling
func is_ready() -> bool:
	return _reader != null and _reader.is_valid() and _mapper != null and not _mapper.is_empty()


## Get all available terrains from the TileSet
func get_terrains() -> Array[Dictionary]:
	if _reader:
		return _reader.get_terrains()
	return []


## Get count of terrains in the TileSet
func get_terrain_count() -> int:
	if _reader:
		return _reader.get_terrain_count()
	return 0


## Calculate bitmask for a position based on its neighbors
## placement_data: Dictionary of tile_key -> TilePlacerData
func calculate_bitmask(
	grid_pos: Vector3,
	orientation: int,
	terrain_id: int,
	placement_data: Dictionary
) -> int:
	var bitmask: int = 0

	for dir_name: String in PlaneCoordinateMapper.NEIGHBOR_OFFSETS_2D.keys():
		var offset_2d: Vector2i = PlaneCoordinateMapper.NEIGHBOR_OFFSETS_2D[dir_name]
		var offset_3d: Vector3 = PlaneCoordinateMapper.offset_to_3d(offset_2d, orientation)
		var neighbor_pos: Vector3 = grid_pos + offset_3d

		if _has_matching_terrain(neighbor_pos, orientation, terrain_id, placement_data):
			bitmask |= PlaneCoordinateMapper.BITMASK_VALUES[dir_name]

	return bitmask


## Check if a position has a tile with matching terrain
func _has_matching_terrain(
	grid_pos: Vector3,
	orientation: int,
	terrain_id: int,
	placement_data: Dictionary
) -> bool:
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

	if not placement_data.has(tile_key):
		return false

	var tile_data: TilePlacerData = placement_data[tile_key]
	return tile_data.terrain_id == terrain_id


## Get UV rect for autotile placement at a position
## Returns the correct UV based on neighboring tiles
func get_autotile_uv(
	grid_pos: Vector3,
	orientation: int,
	terrain_id: int,
	placement_data: Dictionary
) -> Rect2:
	if not is_ready():
		return Rect2()

	var bitmask: int = calculate_bitmask(
		grid_pos, orientation, terrain_id, placement_data
	)

	# Cache bitmask for this position
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
	_bitmask_cache[tile_key] = bitmask

	return _mapper.get_uv(terrain_id, bitmask)


## Update all neighbors of a position and return UV changes
## Returns: Dictionary of tile_key -> new_uv (Rect2)
## Call this after placing or removing a tile
func update_neighbors(
	grid_pos: Vector3,
	orientation: int,
	placement_data: Dictionary
) -> Dictionary:
	var updates: Dictionary = {}  # tile_key -> new_uv

	var neighbors: Array[Vector3] = PlaneCoordinateMapper.get_neighbor_positions_3d(
		grid_pos, orientation
	)

	for neighbor_pos: Vector3 in neighbors:
		var tile_key: int = GlobalUtil.make_tile_key(neighbor_pos, orientation)

		# Skip if no tile at this position
		if not placement_data.has(tile_key):
			continue

		var neighbor_data: TilePlacerData = placement_data[tile_key]

		# Skip if not an autotiled tile
		if neighbor_data.terrain_id < 0:
			continue

		# Calculate new bitmask
		var new_bitmask: int = calculate_bitmask(
			neighbor_pos, orientation, neighbor_data.terrain_id, placement_data
		)

		# Check if bitmask changed
		var old_bitmask: int = _bitmask_cache.get(tile_key, -1)

		if new_bitmask != old_bitmask:
			var new_uv: Rect2 = _mapper.get_uv(neighbor_data.terrain_id, new_bitmask)
			updates[tile_key] = new_uv
			_bitmask_cache[tile_key] = new_bitmask

	return updates


## Invalidate cached bitmask for a tile (call when tile is removed)
func invalidate_tile(tile_key: int) -> void:
	_bitmask_cache.erase(tile_key)


## Clear all cached bitmasks
func clear_cache() -> void:
	_bitmask_cache.clear()


## Get tile size from TileSet
func get_tile_size() -> Vector2i:
	if _reader:
		return _reader.get_tile_size()
	return GlobalConstants.DEFAULT_TILE_SIZE


## Get texture from TileSet
func get_texture() -> Texture2D:
	if _reader:
		return _reader.get_texture()
	return null


## Get terrain name by ID
func get_terrain_name(terrain_id: int) -> String:
	if _reader:
		return _reader.get_terrain_name(terrain_id)
	return ""


## Get terrain color by ID
func get_terrain_color(terrain_id: int) -> Color:
	if _reader:
		return _reader.get_terrain_color(terrain_id)
	return Color.WHITE


## Check if a terrain has configured tiles
func has_terrain_tiles(terrain_id: int) -> bool:
	if _mapper:
		return _mapper.has_terrain(terrain_id)
	return false


## Get count of tiles configured for a terrain
func count_terrain_tiles(terrain_id: int) -> int:
	if _reader:
		return _reader.count_configured_tiles(terrain_id)
	return 0


## Get the TileSet being used
func get_tileset() -> TileSet:
	return _tileset


## Get stats for debugging
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
