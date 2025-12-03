@tool
class_name PrismTileChunk
extends MultiMeshTileChunkBase

## Specialized chunk for triangular prism tiles
## Responsibility: Initialize and manage prism tile MultiMesh

func _init() -> void:
	mesh_mode_type = GlobalConstants.MeshMode.PRISM_MESH
	name = "PrismTileChunk"


## Initialize the MultiMesh with prism mesh
func setup_mesh(grid_size: float) -> void:
	# Create MultiMesh for prisms
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true

	# Create the prism mesh (thickness = 10% of grid_size)
	multimesh.mesh = TileMeshGenerator.create_prism_mesh(grid_size)

	# Set buffer size
	multimesh.instance_count = MAX_TILES
	multimesh.visible_instance_count = 0

	# Apply custom AABB for visibility
	custom_aabb = GlobalConstants.CHUNK_CUSTOM_AABB
