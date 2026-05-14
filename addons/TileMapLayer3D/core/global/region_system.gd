class_name RegionSystem
extends RefCounted

## Single source of truth for all spatial region operations.
## All tile placement, chunk creation, collision generation, mesh baking,
## and raycast culling route through this class.
##
## Static methods: pure math, no state, safe to call from anywhere.
## Instance methods: own the _registry (TerrainRegionChunk map), called via TileMapLayer3D.region_system.

# ---------------------------------------------------------------------------
# STATIC MATH — no instance state required
# ---------------------------------------------------------------------------

## Canonical world-pos → region key. The ONE function used everywhere a world
## position needs to be mapped to a 30-unit region.
##
## Boundary rule: a position lying exactly on a region boundary belongs to the
## lower (negative-side) region. The EPS subtraction enforces that for floats
## like world Z=0.0, which would otherwise floor to region 0; with EPS it floors
## to -1, matching ownership. EPS is small enough that grid-derived positions
## (e.g. world (0.5, 0.5, 0.5) from grid (0,0,0) with GRID_ALIGNMENT_OFFSET=0.5)
## still land firmly inside their expected region.
##
## All other map → region helpers in this file must call this — duplicating
## the math is a footgun: lookup vs registration would silently disagree.
static func resolve_region_key(world_pos: Vector3) -> Vector3i:
	const EPS: float = 1e-5
	var size: float = GlobalConstants.CHUNK_REGION_SIZE
	return Vector3i(
		int(floor((world_pos.x - EPS) / size)),
		int(floor((world_pos.y - EPS) / size)),
		int(floor((world_pos.z - EPS) / size))
	)


## Region key → world-space origin of that cube.
## Replaces every manual `Vector3(rk) * GlobalConstants.CHUNK_REGION_SIZE` in the codebase.
static func region_key_to_world_origin(rk: Vector3i) -> Vector3:
	return Vector3(rk) * GlobalConstants.CHUNK_REGION_SIZE


## Region key → tight world-space AABB (no boundary expansion).
static func region_aabb(rk: Vector3i) -> AABB:
	return AABB(region_key_to_world_origin(rk), Vector3.ONE * GlobalConstants.CHUNK_REGION_SIZE)


## The chunk-local AABB read directly from GlobalConstants.CHUNK_LOCAL_AABB.
## Used when setting chunk.custom_aabb — one reference so changing the constant
## in GlobalConstants immediately affects all chunk creation.
static func chunk_local_aabb() -> AABB:
	return GlobalConstants.CHUNK_LOCAL_AABB


## Pack a Vector3i region key into a single 64-bit integer (20 bits per axis).
## Valid range per axis: -524288 .. 524287, well beyond practical world bounds.
static func pack(rk: Vector3i) -> int:
	const MASK_20BIT: int = 0xFFFFF
	return ((rk.x & MASK_20BIT) << 40) | ((rk.y & MASK_20BIT) << 20) | (rk.z & MASK_20BIT)


## Unpack a 64-bit packed region key back to Vector3i, sign-extending each 20-bit field.
static func unpack(packed: int) -> Vector3i:
	const MASK_20BIT: int = 0xFFFFF
	var x: int = (packed >> 40) & MASK_20BIT
	var y: int = (packed >> 20) & MASK_20BIT
	var z: int = packed & MASK_20BIT
	if x >= 0x80000:
		x -= 0x100000
	if y >= 0x80000:
		y -= 0x100000
	if z >= 0x80000:
		z -= 0x100000
	return Vector3i(x, y, z)


## World pos → position relative to that region's origin.
## Uses resolve_region_key so the local offset matches the chunk assigned by get_or_create_chunk.
static func world_to_region_local(world_pos: Vector3) -> Vector3:
	return world_pos - region_key_to_world_origin(resolve_region_key(world_pos))



## All region keys whose chunk AABBs (GlobalConstants.CHUNK_LOCAL_AABB) physically
## overlap the given world AABB.  This is the ONLY correct way to ask
## "which regions are touched by this world-space area".
##
## CHUNK_LOCAL_AABB = AABB((-0.5,-0.5,-0.5), (CHUNK_REGION_SIZE+1, ...+1, ...+1))
## A chunk at region key R has effective world AABB:
##   AABB(R_origin + CHUNK_LOCAL_AABB.position, CHUNK_LOCAL_AABB.size)
##
## Derivation: chunk at R overlaps world_aabb when R_origin is in range:
##   world_aabb.position - chunk_local_end  ..  world_aabb.end - chunk_local_start
## where chunk_local_start = CHUNK_LOCAL_AABB.position (e.g. -0.5)
##       chunk_local_end   = CHUNK_LOCAL_AABB.position + CHUNK_LOCAL_AABB.size (e.g. 30.5)
static func overlapping_region_keys(world_aabb: AABB) -> Array[Vector3i]:
	var size: float = GlobalConstants.CHUNK_REGION_SIZE
	var local_min: Vector3 = GlobalConstants.CHUNK_LOCAL_AABB.position
	var local_max: Vector3 = GlobalConstants.CHUNK_LOCAL_AABB.position + GlobalConstants.CHUNK_LOCAL_AABB.size
	var search_min: Vector3 = world_aabb.position - local_max
	var search_max: Vector3 = world_aabb.end - local_min
	var min_key: Vector3i = Vector3i(
		int(floor(search_min.x / size)),
		int(floor(search_min.y / size)),
		int(floor(search_min.z / size))
	)
	var max_key: Vector3i = Vector3i(
		int(floor(search_max.x / size)),
		int(floor(search_max.y / size)),
		int(floor(search_max.z / size))
	)
	var result: Array[Vector3i] = []
	for x: int in range(min_key.x, max_key.x + 1):
		for y: int in range(min_key.y, max_key.y + 1):
			for z: int in range(min_key.z, max_key.z + 1):
				result.append(Vector3i(x, y, z))
	return result


# ---------------------------------------------------------------------------
# INSTANCE REGISTRY — owns the packed_key → TerrainRegionChunk map
# ---------------------------------------------------------------------------

var _registry: Dictionary = {}  # int (packed_region_key) → TerrainRegionChunk


## Return the TerrainRegionChunk for a packed key, or null if not present.
func get_region(packed: int) -> TerrainRegionChunk:
	return _registry.get(packed, null)


## Return existing TerrainRegionChunk or create a new one for the given packed key.
func get_or_create_region(packed: int) -> TerrainRegionChunk:
	if not _registry.has(packed):
		var rk: Vector3i = unpack(packed)
		_registry[packed] = TerrainRegionChunk.from_region_key(rk)
	return _registry[packed]


## All active TerrainRegionChunks.
func all_regions() -> Array[TerrainRegionChunk]:
	var result: Array[TerrainRegionChunk] = []
	for v in _registry.values():
		result.append(v as TerrainRegionChunk)
	return result


## Remove all regions.
func clear() -> void:
	_registry.clear()


## Return the TerrainRegionChunk whose region contains world_pos, or null.
func region_for_world_pos(world_pos: Vector3) -> TerrainRegionChunk:
	var packed: int = pack(resolve_region_key(world_pos))
	return _registry.get(packed, null)


## Return all TerrainRegionChunks whose chunk AABBs physically overlap world_aabb.
## Filters to only regions that actually exist in the registry.
func regions_for_world_aabb(world_aabb: AABB) -> Array[TerrainRegionChunk]:
	var result: Array[TerrainRegionChunk] = []
	for rk: Vector3i in overlapping_region_keys(world_aabb):
		var packed: int = pack(rk)
		var chunk: TerrainRegionChunk = _registry.get(packed, null)
		if chunk != null:
			result.append(chunk)
	return result


## Register a tile into its region. region_key_packed identifies the region.
## columnar_index is the tile's index in TileMapLayer3D's packed arrays.
func register_tile(tile_key: int, columnar_index: int, region_key_packed: int) -> void:
	var region: TerrainRegionChunk = get_or_create_region(region_key_packed)
	var existing: int = region.tile_keys.find(tile_key)
	if existing >= 0:
		region.columnar_indices[existing] = columnar_index
	else:
		region.add_tile(tile_key, columnar_index)


## Remove a tile from its region. Removes the region when it becomes empty.
func unregister_tile(tile_key: int, region_key_packed: int) -> void:
	var region: TerrainRegionChunk = _registry.get(region_key_packed, null)
	if region == null:
		return
	region.remove_tile(tile_key)
	if region.is_empty():
		_registry.erase(region_key_packed)
