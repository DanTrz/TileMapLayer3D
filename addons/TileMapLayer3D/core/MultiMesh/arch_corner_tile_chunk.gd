@tool
class_name ArchCornerTileChunk
extends MultiMeshTileChunkBase

## Specialized chunk for FLAT_ARCH_CORNER tiles (flat with curved arc at one end).

func _init() -> void:
	mesh_mode_type = GlobalConstants.MeshMode.FLAT_ARCH_CORNER
	name = "ArchCornerTileChunk"

## Initialize the MultiMesh with arch corner mesh
func setup_mesh(grid_size: float, arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO) -> void:
	# Create MultiMesh for arch corner tiles
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true

	# Create the arch corner mesh (flat + curved arc segment)
	multimesh.mesh = TileMeshGenerator.create_arch_corner_mesh(
		Rect2(0, 0, 1, 1),  # Normalized rect
		Vector2(1, 1),       # Normalized size
		Vector2(grid_size, grid_size),  # Physical world size
		arc_radius_ratio
	)

	# Set buffer size
	multimesh.instance_count = MAX_TILES
	multimesh.visible_instance_count = 0

	# LOCAL AABB for proper spatial chunking (v0.4.2)
	# Chunk will be positioned at region's world origin by TileMapLayer3D
	custom_aabb = GlobalConstants.CHUNK_LOCAL_AABB
