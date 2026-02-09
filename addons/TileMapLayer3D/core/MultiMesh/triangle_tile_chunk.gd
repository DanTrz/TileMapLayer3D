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
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true
	
	# ТЕПЕРЬ ВЫЗОВ ВЫГЛЯДИТ ТАК:
	multimesh.mesh = TileMeshGenerator.create_tile_triangle(Vector2(grid_size, grid_size))

	multimesh.instance_count = MAX_TILES
	multimesh.visible_instance_count = 0
	custom_aabb = GlobalConstants.CHUNK_LOCAL_AABB
