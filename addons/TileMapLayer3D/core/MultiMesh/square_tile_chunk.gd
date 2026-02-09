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
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true
	
	# ТЕПЕРЬ ВЫЗОВ ВЫГЛЯДИТ ТАК:
	multimesh.mesh = TileMeshGenerator.create_tile_quad(Vector2(grid_size, grid_size))

	multimesh.instance_count = MAX_TILES
	multimesh.visible_instance_count = 0
	custom_aabb = GlobalConstants.CHUNK_LOCAL_AABB
