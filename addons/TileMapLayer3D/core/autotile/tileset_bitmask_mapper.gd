@tool
class_name TileSetBitmaskMapper
extends RefCounted


const PEERING_TO_BITMASK: Dictionary = {
	TileSet.CELL_NEIGHBOR_TOP_SIDE: 1,
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE: 2,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: 4,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE: 8,
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: 16,
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: 32,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: 64,
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: 128,
}

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

	if region_size.x <= 0 or region_size.y <= 0:
		return

	var grid_size := Vector2i(texture_size.x / region_size.x, texture_size.y / region_size.y)

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

			var bitmask: int = _calculate_bitmask(tile_data, terrain_id)

			if not _lookup.has(terrain_id):
				_lookup[terrain_id] = {}

			var uv_rect := Rect2(
				float(coords.x * region_size.x),
				float(coords.y * region_size.y),
				float(region_size.x),
				float(region_size.y)
			)

			var prob: float = maxf(tile_data.probability, 0.0)
			if not _lookup[terrain_id].has(bitmask):
				_lookup[terrain_id][bitmask] = []
			_lookup[terrain_id][bitmask].append({"uv": uv_rect, "prob": prob})


func _calculate_bitmask(tile_data: TileData, terrain_id: int) -> int:
	var bitmask: int = 0

	for peering_bit: int in PEERING_TO_BITMASK.keys():
		var peering_terrain: int = tile_data.get_terrain_peering_bit(peering_bit)
		if peering_terrain == terrain_id:
			bitmask |= PEERING_TO_BITMASK[peering_bit]

	return bitmask


func get_uv(terrain_id: int, bitmask: int, seed_int: int = GlobalConstants.AUTOTILE_NO_SEED) -> Rect2:
	if not _lookup.has(terrain_id):
		return Rect2()

	if _lookup[terrain_id].has(bitmask):
		return _pick_variant(_lookup[terrain_id][bitmask], seed_int)

	return _find_fallback_uv(terrain_id, bitmask, seed_int)


func _pick_variant(candidates: Array, seed_int: int) -> Rect2:
	var n: int = candidates.size()
	if n == 0:
		return Rect2()
	if n == 1:
		return candidates[0]["uv"]
	if seed_int == GlobalConstants.AUTOTILE_NO_SEED:
		return candidates[GlobalConstants.AUTOTILE_VARIANT_DEFAULT_INDEX]["uv"]

	var total: float = 0.0
	for c: Dictionary in candidates:
		total += c["prob"]
	if total <= 0.0:
		return candidates[GlobalConstants.AUTOTILE_VARIANT_DEFAULT_INDEX]["uv"]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_int
	var roll: float = rng.randf() * total

	var cumulative: float = 0.0
	for c: Dictionary in candidates:
		cumulative += c["prob"]
		if roll < cumulative:
			return c["uv"]

	return candidates[n - 1]["uv"]


## Position hash → seed int. Quantizes by COORD_SCALE (stable for half-grid 0.5)
## then folds axes with spatial-hash primes. Purely positional: orientation and
## bitmask are intentionally excluded so a cell keeps its variant across neighbor
## recomputes (folding bitmask in would re-roll = flicker).
func position_seed(grid_pos: Vector3) -> int:
	var ix: int = int(round(grid_pos.x * TileKeySystem.COORD_SCALE))
	var iy: int = int(round(grid_pos.y * TileKeySystem.COORD_SCALE))
	var iz: int = int(round(grid_pos.z * TileKeySystem.COORD_SCALE))
	return ix + iy * GlobalConstants.AUTOTILE_HASH_PRIME_Y + iz * GlobalConstants.AUTOTILE_HASH_PRIME_Z


func _find_fallback_uv(terrain_id: int, bitmask: int, seed_int: int = GlobalConstants.AUTOTILE_NO_SEED) -> Rect2:
	if not _lookup.has(terrain_id):
		return Rect2()

	var best_match: int = -1
	var best_score: int = -1

	for available_bitmask: int in _lookup[terrain_id].keys():
		if (bitmask & available_bitmask) == available_bitmask:
			var score: int = _count_bits(available_bitmask)
			if score > best_score:
				best_score = score
				best_match = available_bitmask

	if best_match >= 0:
		return _pick_variant(_lookup[terrain_id][best_match], seed_int)

	if _lookup[terrain_id].has(0):
		return _pick_variant(_lookup[terrain_id][0], seed_int)

	for available_bitmask: int in _lookup[terrain_id].keys():
		return _pick_variant(_lookup[terrain_id][available_bitmask], seed_int)

	return Rect2()


func _count_bits(value: int) -> int:
	var count: int = 0
	while value:
		count += value & 1
		value >>= 1
	return count


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


func has_terrain(terrain_id: int) -> bool:
	return _lookup.has(terrain_id) and _lookup[terrain_id].size() > 0


func get_available_bitmasks(terrain_id: int) -> Array[int]:
	var bitmasks: Array[int] = []
	if _lookup.has(terrain_id):
		for bitmask: int in _lookup[terrain_id].keys():
			bitmasks.append(bitmask)
	return bitmasks


func is_empty() -> bool:
	return _lookup.is_empty()


func get_tile_size() -> Vector2i:
	return _tile_size
