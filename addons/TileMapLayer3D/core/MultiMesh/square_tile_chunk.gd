@tool
class_name SquareTileChunk
extends MultiMeshTileChunkBase

## Specialized chunk for square/quad tiles
## Responsibility: Initialize and manage square tile MultiMesh

func _init() -> void:
	mesh_mode_type = GlobalConstants.MeshMode.FLAT_SQUARE
	name = "QuadTileChunk"

## Initialize the MultiMesh with quad mesh
func setup_mesh(grid_size: float) -> void:
	# Create MultiMesh for squares
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	
	# Create the quad mesh
	multimesh.mesh = TileMeshGenerator.create_tile_quad(
		Rect2(0, 0, 1, 1),  # Normalized rect
		Vector2(1, 1),      # Normalized size
		Vector2(grid_size, grid_size)  # Physical world size
	)

	# multimesh.mesh = TileMeshGenerator.create_quad_from_local_box_mesh(grid_size)
	
	# Set buffer size
	multimesh.instance_count = MAX_TILES
	multimesh.visible_instance_count = 0

	# Set large AABB to prevent frustum culling issues
	# NOTE: Region-based AABBs were removed due to precision issues with Godot's frustum culling
	# See v0.4.1 fix - using large global AABB for reliable visibility
	custom_aabb = GlobalConstants.CHUNK_CUSTOM_AABB