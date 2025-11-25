# =============================================================================
# FILE: addons/TileMapLayer3D/core/autotile/tileset_terrain_reader.gd
# PURPOSE: Read terrain configuration from Godot's TileSet resource
# DEPENDENCIES: TileSet, TileSetAtlasSource, TileData (Godot built-in)
# =============================================================================
@tool
class_name TileSetTerrainReader
extends RefCounted

## Reads terrain data from a Godot TileSet resource.
## Provides a clean interface for accessing terrain configuration.
## This class is read-only - it does not modify the TileSet.

var _tileset: TileSet
var _source_id: int
var _terrain_set: int


func _init(tileset: TileSet, source_id: int = GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID, terrain_set: int = GlobalConstants.AUTOTILE_DEFAULT_TERRAIN_SET) -> void:
	_tileset = tileset
	_source_id = source_id
	_terrain_set = terrain_set


## Check if TileSet has valid terrain configuration
func is_valid() -> bool:
	if _tileset == null:
		return false
	if _tileset.get_source_count() == 0:
		return false
	if _tileset.get_terrain_sets_count() == 0:
		return false
	if _terrain_set >= _tileset.get_terrain_sets_count():
		return false
	return true


## Get all terrains in the terrain set
## Returns: Array of dictionaries with keys: id, name, color
func get_terrains() -> Array[Dictionary]:
	var terrains: Array[Dictionary] = []

	if not is_valid():
		return terrains

	var count: int = _tileset.get_terrains_count(_terrain_set)
	for i: int in range(count):
		terrains.append({
			"id": i,
			"name": _tileset.get_terrain_name(_terrain_set, i),
			"color": _tileset.get_terrain_color(_terrain_set, i),
		})

	return terrains


## Get terrain name by ID
func get_terrain_name(terrain_id: int) -> String:
	if not is_valid():
		return ""
	if terrain_id < 0 or terrain_id >= _tileset.get_terrains_count(_terrain_set):
		return ""
	return _tileset.get_terrain_name(_terrain_set, terrain_id)


## Get terrain color by ID
func get_terrain_color(terrain_id: int) -> Color:
	if not is_valid():
		return Color.WHITE
	if terrain_id < 0 or terrain_id >= _tileset.get_terrains_count(_terrain_set):
		return Color.WHITE
	return _tileset.get_terrain_color(_terrain_set, terrain_id)


## Get atlas source from TileSet
func get_atlas() -> TileSetAtlasSource:
	if _tileset == null:
		return null
	if not _tileset.has_source(_source_id):
		return null
	var source: TileSetSource = _tileset.get_source(_source_id)
	if source is TileSetAtlasSource:
		return source as TileSetAtlasSource
	return null


## Get tile size from TileSet
func get_tile_size() -> Vector2i:
	if _tileset == null:
		return GlobalConstants.DEFAULT_TILE_SIZE
	return _tileset.tile_size


## Get texture from atlas source
func get_texture() -> Texture2D:
	var atlas: TileSetAtlasSource = get_atlas()
	if atlas == null:
		return null
	return atlas.texture


## Get texture region size from atlas (may differ from tile_size)
func get_texture_region_size() -> Vector2i:
	var atlas: TileSetAtlasSource = get_atlas()
	if atlas == null:
		return get_tile_size()
	return atlas.texture_region_size


## Count tiles configured for a specific terrain
## Returns the number of tiles in the atlas that have this terrain as their center terrain
func count_configured_tiles(terrain_id: int) -> int:
	var atlas: TileSetAtlasSource = get_atlas()
	if atlas == null:
		return 0

	var count: int = 0
	var texture: Texture2D = atlas.texture
	if texture == null:
		return 0

	var texture_size: Vector2i = Vector2i(texture.get_size())
	var region_size: Vector2i = atlas.texture_region_size

	# Avoid division by zero
	if region_size.x <= 0 or region_size.y <= 0:
		return 0

	var grid_size := Vector2i(texture_size.x / region_size.x, texture_size.y / region_size.y)

	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var coords := Vector2i(x, y)
			if not atlas.has_tile(coords):
				continue
			var tile_data: TileData = atlas.get_tile_data(coords, 0)
			if tile_data == null:
				continue
			if tile_data.terrain_set == _terrain_set and tile_data.terrain == terrain_id:
				count += 1

	return count


## Get total number of terrains in the terrain set
func get_terrain_count() -> int:
	if not is_valid():
		return 0
	return _tileset.get_terrains_count(_terrain_set)


## Check if a specific terrain ID exists
func has_terrain(terrain_id: int) -> bool:
	if not is_valid():
		return false
	return terrain_id >= 0 and terrain_id < _tileset.get_terrains_count(_terrain_set)


## Get the terrain set mode (MATCH_CORNERS_AND_SIDES, MATCH_CORNERS, MATCH_SIDES)
func get_terrain_set_mode() -> TileSet.TerrainMode:
	if not is_valid():
		return TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES
	return _tileset.get_terrain_set_mode(_terrain_set)


## Get the TileSet being read
func get_tileset() -> TileSet:
	return _tileset


## Get the source ID being used
func get_source_id() -> int:
	return _source_id


## Get the terrain set being used
func get_terrain_set() -> int:
	return _terrain_set
