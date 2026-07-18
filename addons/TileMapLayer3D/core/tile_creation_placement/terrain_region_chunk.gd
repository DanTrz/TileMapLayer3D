class_name TerrainRegionChunk
extends Resource

## Runtime-only spatial region container. Aggregates all tiles and MultiMesh chunk
## nodes that fall within one 30×30×30 world-unit cube (CHUNK_REGION_SIZE).
## Never exported/saved — rebuilt from columnar data on every scene load.
## Enables O(region) raycast culling, per-region bake, per-region collision gen.

var region_key: Vector3i = Vector3i.ZERO

var region_key_packed: int = 0

var world_aabb: AABB = AABB()

var tile_keys: Array[int] = []

var columnar_indices: Array[int] = []

var vertex_tile_keys: Array[int] = []


static func from_region_key(rk: Vector3i) -> TerrainRegionChunk:
	var trc: TerrainRegionChunk = TerrainRegionChunk.new()
	trc.region_key = rk
	trc.region_key_packed = RegionSystem.pack(rk)
	var origin: Vector3 = RegionSystem.region_key_to_world_origin(rk)
	trc.world_aabb = AABB(origin, Vector3.ONE * GlobalConstants.CHUNK_REGION_SIZE)
	return trc


func add_tile(tile_key: int, tile_index: int) -> void:
	tile_keys.append(tile_key)
	columnar_indices.append(tile_index)


func add_vertex_tile(tile_key: int) -> void:
	if not vertex_tile_keys.has(tile_key):
		vertex_tile_keys.append(tile_key)


func remove_vertex_tile(tile_key: int) -> bool:
	var idx: int = vertex_tile_keys.find(tile_key)
	if idx < 0:
		return false
	vertex_tile_keys.remove_at(idx)
	return true


func remove_tile(tile_key: int) -> bool:
	var idx: int = tile_keys.find(tile_key)
	if idx < 0:
		return false
	tile_keys.remove_at(idx)
	columnar_indices.remove_at(idx)
	return true


func is_empty() -> bool:
	return tile_keys.is_empty() and vertex_tile_keys.is_empty()
