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

## All MultiMeshTileChunkBase nodes (any mesh type) whose region_key matches.
## Multiple entries exist when a region has >1000 tiles (sub-chunks) or
## contains multiple mesh types (quad + triangle + box, etc.).
var chunks: Array[MultiMeshTileChunkBase] = []


## Build a TerrainRegionChunk for the given region key. Sets region_key,
## region_key_packed, and world_aabb. tile_keys / columnar_indices / chunks
## are populated separately by TileMapLayer3D.
static func from_region_key(rk: Vector3i) -> TerrainRegionChunk:
	var trc: TerrainRegionChunk = TerrainRegionChunk.new()
	trc.region_key = rk
	trc.region_key_packed = GlobalUtil.pack_region_key(rk)
	var origin: Vector3 = Vector3(rk) * GlobalConstants.CHUNK_REGION_SIZE
	trc.world_aabb = AABB(origin, Vector3.ONE * GlobalConstants.CHUNK_REGION_SIZE)
	return trc


## Add a tile to this region. tile_index is the columnar array index.
func add_tile(tile_key: int, tile_index: int) -> void:
	tile_keys.append(tile_key)
	columnar_indices.append(tile_index)


## Remove a tile from this region by tile_key. Returns true if found.
func remove_tile(tile_key: int) -> bool:
	var idx: int = tile_keys.find(tile_key)
	if idx < 0:
		return false
	tile_keys.remove_at(idx)
	columnar_indices.remove_at(idx)
	return true


## Register a chunk node for this region (avoids duplicates).
func add_chunk(chunk: MultiMeshTileChunkBase) -> void:
	if not chunks.has(chunk):
		chunks.append(chunk)


## Remove a chunk node reference (called when chunk is freed).
func remove_chunk(chunk: MultiMeshTileChunkBase) -> void:
	chunks.erase(chunk)


## True when no tiles remain in this region.
func is_empty() -> bool:
	return tile_keys.is_empty()
