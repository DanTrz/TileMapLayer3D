@tool
class_name MultiMeshTileChunkBase
extends MultiMeshInstance3D

## Chunk container for MultiMesh instances. Base class for Quads or Tris MultiMeshTileChunks.
## Responsibility: MultiMesh management and core MM seetings
var mesh_mode_type: GlobalConstants.MeshMode = GlobalConstants.MeshMode.MESH_SQUARE

# PERFORMANCE: Store chunk index to avoid O(N) Array.find() lookups
var chunk_index: int = -1  # Index in parent TileMapLayer3D chunk array

var tile_count: int = 0  # Number of tiles currently in this chunk
var tile_refs: Dictionary = {}  # int (tile_key) -> instance_index

# PERFORMANCE: Reverse lookup to avoid O(N) search when removing tiles
var instance_to_key: Dictionary = {}  # int (instance_index) -> int (tile_key)

const MAX_TILES: int = GlobalConstants.CHUNK_MAX_TILES

func is_full() -> bool:
	return tile_count >= MAX_TILES

func has_space() -> bool:
	return tile_count < MAX_TILES