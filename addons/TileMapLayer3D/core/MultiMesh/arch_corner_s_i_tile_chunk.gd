@tool
class_name ArchCornerSITileChunk
extends MultiMeshTileChunkBase

## Specialized chunk for FLAT_ARCH_CORNER_S_I tiles — inverted double-arc tile with
## arcs curving opposite directions (inverted S shape). Left arc -Y, right arc +Y.

func _init() -> void:
	mesh_mode_type = GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I
	name = "ArchCornerSITileChunk"

## Initialize the MultiMesh with inverted double-arc S-shape mesh
func setup_mesh(grid_size: float, arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO) -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true

	multimesh.mesh = TileMeshGenerator.create_arch_corner_s_i_mesh(
		Rect2(0, 0, 1, 1),
		Vector2(1, 1),
		Vector2(grid_size, grid_size),
		arc_radius_ratio
	)

	multimesh.instance_count = MAX_TILES
	multimesh.visible_instance_count = 0
	custom_aabb = GlobalConstants.CHUNK_LOCAL_AABB
