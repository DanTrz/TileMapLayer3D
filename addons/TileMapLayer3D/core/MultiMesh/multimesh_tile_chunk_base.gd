@tool
class_name MultiMeshTileChunkBase
extends MultiMeshInstance3D

## Chunk container for MultiMesh instances. Base class for Quads or Tris MultiMeshTileChunks.
## Responsibility: MultiMesh management and core MM seetings
var mesh_mode_type: GlobalConstants.MeshMode = GlobalConstants.MeshMode.FLAT_SQUARE

#  Store chunk index to avoid O(N) Array.find() lookups
var chunk_index: int = -1  # Index in parent TileMapLayer3D chunk array

var tile_count: int = 0  # Number of tiles currently in this chunk
var tile_refs: Dictionary = {}  # int (tile_key) -> instance_index

#  Reverse lookup to avoid O(N) search when removing tiles
var instance_to_key: Dictionary = {}  # int (instance_index) -> int (tile_key)

# Spatial region tracking for dual-criteria chunking
# Tiles are assigned to chunks based on both mesh type AND spatial region
var region_key: Vector3i = Vector3i.ZERO  # Which spatial region this chunk belongs to
var region_key_packed: int = 0  # Packed version for fast dictionary lookup

# Texture repeat mode for BOX_MESH and PRISM_MESH chunks
# Used to distinguish between DEFAULT (edge stripes) and REPEAT (full texture) chunks
var texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT

const MAX_TILES: int = GlobalConstants.CHUNK_MAX_TILES

func is_full() -> bool:
	return tile_count >= MAX_TILES

func has_space() -> bool:
	return tile_count < MAX_TILES