class_name TerrainRegionChunk
extends Resource

## Runtime-only spatial region container. Aggregates all tiles and MultiMesh chunk
## nodes that fall within one 30×30×30 world-unit cube (CHUNK_REGION_SIZE).
## Never exported/saved — rebuilt from columnar data on every scene load.
## Enables O(region) raycast culling, per-region bake, per-region collision gen.

## The 30-unit grid region this container covers.
var region_key: Vector3i = Vector3i.ZERO

## Packed 60-bit version of region_key for O(1) dictionary lookup.
var region_key_packed: int = 0

## World-space AABB covering this region exactly (set once in from_region_key).
var world_aabb: AABB = AABB()

## All tile_keys whose grid positions map to this region.
var tile_keys: Array[int] = []

## Parallel to tile_keys — columnar array index for each tile_key.
## Allows direct PackedArray access without a secondary _saved_tiles_lookup call.
var columnar_indices: Array[int] = []

## Vertex-edited tile keys assigned to this region for collision/mesh baking.
## These tiles are not in columnar storage, so they need explicit regional
## membership after conversion.
var vertex_tile_keys: Array[int] = []


## Build a TerrainRegionChunk for the given region key. Sets region_key,
## region_key_packed, and world_aabb. tile_keys / columnar_indices
## are populated separately by TileMapLayer3D.
static func from_region_key(rk: Vector3i) -> TerrainRegionChunk:
	var trc: TerrainRegionChunk = TerrainRegionChunk.new()
	trc.region_key = rk
	trc.region_key_packed = RegionSystem.pack(rk)
	var origin: Vector3 = RegionSystem.region_key_to_world_origin(rk)
	trc.world_aabb = AABB(origin, Vector3.ONE * GlobalConstants.CHUNK_REGION_SIZE)
	return trc


## Add a tile to this region. tile_index is the columnar array index.
func add_tile(tile_key: int, tile_index: int) -> void:
	tile_keys.append(tile_key)
	columnar_indices.append(tile_index)


## Add a vertex-edited tile to this region.
func add_vertex_tile(tile_key: int) -> void:
	if not vertex_tile_keys.has(tile_key):
		vertex_tile_keys.append(tile_key)


## Remove a tile from this region by tile_key. Returns true if found.
func remove_tile(tile_key: int) -> bool:
	var idx: int = tile_keys.find(tile_key)
	if idx < 0:
		return false
	tile_keys.remove_at(idx)
	columnar_indices.remove_at(idx)
	return true


## True when no tiles remain in this region.
func is_empty() -> bool:
	return tile_keys.is_empty() and vertex_tile_keys.is_empty()
