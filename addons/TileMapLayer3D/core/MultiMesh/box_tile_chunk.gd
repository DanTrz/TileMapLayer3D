@tool
class_name BoxTileChunk
extends MultiMeshTileChunkBase

## Specialized chunk for box/extruded quad tiles
## Responsibility: Initialize and manage box tile MultiMesh

func _init() -> void:
	mesh_mode_type = GlobalConstants.MeshMode.BOX_MESH
	name = "BoxTileChunk"


## Initialize the MultiMesh with box mesh
## @param grid_size: Size of the grid cell
## @param texture_repeat_mode: DEFAULT (edge stripes) or REPEAT (full texture on all faces)
func setup_mesh(grid_size: float, texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT) -> void:
	#print("[TEXTURE_REPEAT] BoxTileChunk.setup_mesh: texture_repeat_mode=%d (0=DEFAULT, 1=REPEAT)" % texture_repeat_mode)
	# Create MultiMesh for boxes
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true
	# Create the box mesh based on texture repeat mode
	if texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
		#print("[TEXTURE_REPEAT] BoxTileChunk.setup_mesh: Calling create_box_mesh_repeat()")
		multimesh.mesh = TileMeshGenerator.create_box_mesh_repeat(grid_size)
	else:
		#print("[TEXTURE_REPEAT] BoxTileChunk.setup_mesh: Calling create_box_mesh()")
		multimesh.mesh = TileMeshGenerator.create_box_mesh(grid_size)

	# Set buffer size
	multimesh.instance_count = MAX_TILES
	multimesh.visible_instance_count = 0

	# LOCAL AABB for proper spatial chunking (v0.4.2)
	# Chunk will be positioned at region's world origin by TileMapLayer3D
	custom_aabb = GlobalConstants.CHUNK_LOCAL_AABB
