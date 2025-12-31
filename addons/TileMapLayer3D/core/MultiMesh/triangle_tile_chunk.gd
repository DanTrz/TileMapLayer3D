@tool
class_name TriangleTileChunk
extends MultiMeshTileChunkBase

## Specialized chunk for triangular tiles
## Responsibility: Initialize and manage triangle tile MultiMesh

func _init() -> void:
	mesh_mode_type = GlobalConstants.MeshMode.FLAT_TRIANGULE
	name = "TriangleTileChunk"

## Initialize the MultiMesh with triangle mesh
func setup_mesh(grid_size: float) -> void:
	# Create MultiMesh for triangles
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	
	# Create the triangle mesh
	multimesh.mesh = TileMeshGenerator.create_tile_triangle(
		Rect2(0, 0, 1, 1),  # Normalized rect
		Vector2(1, 1),      # Normalized size
		Vector2(grid_size, grid_size)  # Physical world size
	)


	# Set buffer size (triangles may need fewer instances)
	multimesh.instance_count = MAX_TILES
	multimesh.visible_instance_count = 0

	# LOCAL AABB for proper spatial chunking (v0.4.2)
	# Chunk will be positioned at region's world origin by TileMapLayer3D
	custom_aabb = GlobalConstants.CHUNK_LOCAL_AABB

