@tool
class_name PrismTileChunk
extends MultiMeshTileChunkBase

## Specialized chunk for triangular prism tiles
## Responsibility: Initialize and manage prism tile MultiMesh

func _init() -> void:
	mesh_mode_type = GlobalConstants.MeshMode.PRISM_MESH
	name = "PrismTileChunk"


## Initialize the MultiMesh with prism mesh
## @param grid_size: Size of the grid cell
## @param texture_repeat_mode: DEFAULT (edge stripes) or REPEAT (full texture on all faces)
func setup_mesh(grid_size: float, texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT) -> void:
	#print("[TEXTURE_REPEAT] PrismTileChunk.setup_mesh: texture_repeat_mode=%d (0=DEFAULT, 1=REPEAT)" % texture_repeat_mode)
	# Create MultiMesh for prisms
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true
	# Create the prism mesh based on texture repeat mode
	if texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
		#print("[TEXTURE_REPEAT] PrismTileChunk.setup_mesh: Calling create_prism_mesh_repeat()")
		multimesh.mesh = TileMeshGenerator.create_prism_mesh_repeat(grid_size)
	else:
		#print("[TEXTURE_REPEAT] PrismTileChunk.setup_mesh: Calling create_prism_mesh()")
		multimesh.mesh = TileMeshGenerator.create_prism_mesh(grid_size)

	# Set buffer size
	multimesh.instance_count = MAX_TILES
	multimesh.visible_instance_count = 0

	# LOCAL AABB for proper spatial chunking (v0.4.2)
	# Chunk will be positioned at region's world origin by TileMapLayer3D
	custom_aabb = GlobalConstants.CHUNK_LOCAL_AABB
