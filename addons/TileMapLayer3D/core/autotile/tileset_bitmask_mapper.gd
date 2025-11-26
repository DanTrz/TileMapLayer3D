# =============================================================================
# FILE: addons/TileMapLayer3D/core/autotile/tileset_bitmask_mapper.gd
# PURPOSE: Build bitmask → UV lookup tables from TileSet terrain data
# DEPENDENCIES: TileSet, TileSetAtlasSource, TileData (Godot built-in)
# =============================================================================
@tool
class_name TileSetBitmaskMapper
extends RefCounted

## Builds lookup tables mapping bitmask patterns to tile UV coordinates.
## This is the core data structure for autotile placement.
## Scans TileSet for configured peering bits and creates fast UV lookup.

# =============================================================================
# GODOT PEERING BIT TO BITMASK MAPPING
# =============================================================================
# Maps Godot's TileSet.CellNeighbor enum to our standard bitmask values.
#
# IMPORTANT: The VALUE side of this dictionary MUST match the constants defined
# in GlobalConstants (AUTOTILE_BITMASK_N, AUTOTILE_BITMASK_E, etc.)
# Those are the Single Source of Truth for bitmask values.
#
# We can't use GlobalConstants directly here because TileSet enum values
# (the KEYS) are not available at const initialization time.
#
# Bitmask values (from GlobalConstants):
#   N=1 (AUTOTILE_BITMASK_N), E=2 (AUTOTILE_BITMASK_E)
#   S=4 (AUTOTILE_BITMASK_S), W=8 (AUTOTILE_BITMASK_W)
#   NE=16, SE=32, SW=64, NW=128
# =============================================================================
const PEERING_TO_BITMASK: Dictionary = {
	TileSet.CELL_NEIGHBOR_TOP_SIDE: 1,              # N = GlobalConstants.AUTOTILE_BITMASK_N
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 2,            # E = GlobalConstants.AUTOTILE_BITMASK_E
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 4,           # S = GlobalConstants.AUTOTILE_BITMASK_S
	TileSet.CELL_NEIGHBOR_LEFT_SIDE: 8,             # W = GlobalConstants.AUTOTILE_BITMASK_W
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: 16,     # NE = GlobalConstants.AUTOTILE_BITMASK_NE
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: 32,  # SE = GlobalConstants.AUTOTILE_BITMASK_SE
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: 64,   # SW = GlobalConstants.AUTOTILE_BITMASK_SW
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: 128,     # NW = GlobalConstants.AUTOTILE_BITMASK_NW
}

# Lookup table: terrain_id -> { bitmask -> Rect2 (UV) }
var _lookup: Dictionary = {}

var _tileset: TileSet
var _source_id: int
var _terrain_set: int
var _tile_size: Vector2i


func _init(tileset: TileSet, source_id: int = GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID, terrain_set: int = GlobalConstants.AUTOTILE_DEFAULT_TERRAIN_SET) -> void:
	_tileset = tileset
	_source_id = source_id
	_terrain_set = terrain_set
	_tile_size = tileset.tile_size if tileset else GlobalConstants.DEFAULT_TILE_SIZE


## Build the lookup table from TileSet
## Must be called after initialization and whenever TileSet changes
func build() -> void:
	_lookup.clear()

	if _tileset == null:
		return

	if not _tileset.has_source(_source_id):
		return

	var source: TileSetSource = _tileset.get_source(_source_id)
	if not source is TileSetAtlasSource:
		return

	var atlas: TileSetAtlasSource = source as TileSetAtlasSource
	if atlas.texture == null:
		return

	var texture_size: Vector2i = Vector2i(atlas.texture.get_size())
	var region_size: Vector2i = atlas.texture_region_size

	# Avoid division by zero
	if region_size.x <= 0 or region_size.y <= 0:
		return

	var grid_size := Vector2i(texture_size.x / region_size.x, texture_size.y / region_size.y)

	# Scan all tiles in the atlas
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var coords := Vector2i(x, y)
			if not atlas.has_tile(coords):
				continue

			var tile_data: TileData = atlas.get_tile_data(coords, 0)
			if tile_data == null:
				continue

			if tile_data.terrain_set != _terrain_set:
				continue

			var terrain_id: int = tile_data.terrain
			if terrain_id < 0:
				continue

			# Calculate bitmask from peering bits
			var bitmask: int = _calculate_bitmask(tile_data, terrain_id)

			# Store in lookup
			if not _lookup.has(terrain_id):
				_lookup[terrain_id] = {}

			var uv_rect := Rect2(
				float(coords.x * region_size.x),
				float(coords.y * region_size.y),
				float(region_size.x),
				float(region_size.y)
			)

			# If multiple tiles have same bitmask, keep first (could store array for random variation)
			if not _lookup[terrain_id].has(bitmask):
				_lookup[terrain_id][bitmask] = uv_rect


## Calculate bitmask from TileData peering bits
func _calculate_bitmask(tile_data: TileData, terrain_id: int) -> int:
	var bitmask: int = 0

	for peering_bit: int in PEERING_TO_BITMASK.keys():
		var peering_terrain: int = tile_data.get_terrain_peering_bit(peering_bit)
		if peering_terrain == terrain_id:
			bitmask |= PEERING_TO_BITMASK[peering_bit]

	return bitmask


## Get UV rect for a terrain + bitmask combination
## Returns empty Rect2 if not found (after trying fallbacks)
func get_uv(terrain_id: int, bitmask: int) -> Rect2:
	if not _lookup.has(terrain_id):
		return Rect2()

	if _lookup[terrain_id].has(bitmask):
		return _lookup[terrain_id][bitmask]

	# Try fallback: find best partial match
	return _find_fallback_uv(terrain_id, bitmask)


## Find best fallback when exact bitmask not found
## Strategy: Find tile whose peering bits are a subset of requested bitmask
func _find_fallback_uv(terrain_id: int, bitmask: int) -> Rect2:
	if not _lookup.has(terrain_id):
		return Rect2()

	var best_match: int = -1
	var best_score: int = -1

	for available_bitmask: int in _lookup[terrain_id].keys():
		# Check if available is subset of requested (all its bits are in requested)
		if (bitmask & available_bitmask) == available_bitmask:
			var score: int = _count_bits(available_bitmask)
			if score > best_score:
				best_score = score
				best_match = available_bitmask

	if best_match >= 0:
		return _lookup[terrain_id][best_match]

	# Last resort: return isolated tile (bitmask 0 = no neighbors)
	if _lookup[terrain_id].has(0):
		return _lookup[terrain_id][0]

	# Return first available tile for this terrain
	for available_bitmask: int in _lookup[terrain_id].keys():
		return _lookup[terrain_id][available_bitmask]

	return Rect2()


## Count set bits in an integer (population count)
func _count_bits(value: int) -> int:
	var count: int = 0
	while value:
		count += value & 1
		value >>= 1
	return count


## Get statistics about the lookup table
func get_stats() -> Dictionary:
	var stats := {
		"terrain_count": _lookup.size(),
		"terrains": {},
		"total_tiles": 0
	}

	for terrain_id: int in _lookup.keys():
		var tile_count: int = _lookup[terrain_id].size()
		stats.terrains[terrain_id] = tile_count
		stats.total_tiles += tile_count

	return stats


## Check if a terrain has any configured tiles
func has_terrain(terrain_id: int) -> bool:
	return _lookup.has(terrain_id) and _lookup[terrain_id].size() > 0


## Get all bitmasks available for a terrain
func get_available_bitmasks(terrain_id: int) -> Array[int]:
	var bitmasks: Array[int] = []
	if _lookup.has(terrain_id):
		for bitmask: int in _lookup[terrain_id].keys():
			bitmasks.append(bitmask)
	return bitmasks


## Check if lookup is empty (no tiles configured)
func is_empty() -> bool:
	return _lookup.is_empty()


## Get tile size used by the mapper
func get_tile_size() -> Vector2i:
	return _tile_size
