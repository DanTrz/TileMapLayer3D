@tool
class_name BoxTileChunk
extends MultiMeshTileChunkBase

## Specialized chunk for box/extruded quad tiles
## Responsibility: Initialize and manage box tile MultiMesh

func _init() -> void:
	mesh_mode_type = GlobalConstants.MeshMode.BOX_MESH
	name = "BoxTileChunk"


## Initialize the MultiMesh with box mesh
func setup_mesh(grid_size: float) -> void:
	# Create MultiMesh for boxes
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true

	# Create the box mesh (thickness = 10% of grid_size)
	multimesh.mesh = TileMeshGenerator.create_box_mesh(grid_size)

	# Set buffer size
	multimesh.instance_count = MAX_TILES
	multimesh.visible_instance_count = 0

	# Apply custom AABB for visibility
	custom_aabb = GlobalConstants.CHUNK_CUSTOM_AABB
