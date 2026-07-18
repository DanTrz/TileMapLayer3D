@tool
class_name TileMeshFactory
extends RefCounted


static var _cache: Dictionary = {}


static func get_mesh(
		mesh_mode: GlobalConstants.MeshMode,
		grid_size: float,
		texture_repeat: int = GlobalConstants.TextureRepeatMode.DEFAULT,
		arc_radius: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	var key: String = _cache_key(mesh_mode, grid_size, texture_repeat, arc_radius)
	var cached: ArrayMesh = _cache.get(key, null)
	if cached != null:
		return cached

	var mesh: ArrayMesh = _build_mesh(mesh_mode, grid_size, texture_repeat, arc_radius)
	_cache[key] = mesh
	return mesh


static func uses_colors(mesh_mode: GlobalConstants.MeshMode) -> bool:
	match mesh_mode:
		GlobalConstants.MeshMode.FLAT_TRIANGULE, \
		GlobalConstants.MeshMode.BOX_MESH, \
		GlobalConstants.MeshMode.PRISM_MESH:
			return false
		_:
			return true


static func is_arch_mode(mesh_mode: GlobalConstants.MeshMode) -> bool:
	match mesh_mode:
		GlobalConstants.MeshMode.FLAT_ARCH, \
		GlobalConstants.MeshMode.FLAT_ARCH_I, \
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER, \
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I, \
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP, \
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I, \
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO, \
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C, \
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I, \
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S, \
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
			return true
		_:
			return false


## Drop the entire cache (e.g. grid_size change). Strong refs released; chunks must be
## re-pointed at fresh meshes by the caller (rebuild) before the old ones go away.
static func invalidate() -> void:
	_cache.clear()


static func invalidate_arch() -> void:
	for key: String in _cache.keys():
		if key.begins_with("arch:"):
			_cache.erase(key)



static func _cache_key(
		mesh_mode: GlobalConstants.MeshMode,
		grid_size: float,
		texture_repeat: int,
		arc_radius: float
) -> String:
	if is_arch_mode(mesh_mode):
		return "arch:%d:%f:%f" % [int(mesh_mode), grid_size, arc_radius]
	return "%d:%f:%d" % [int(mesh_mode), grid_size, texture_repeat]


static func _build_mesh(
		mesh_mode: GlobalConstants.MeshMode,
		grid_size: float,
		texture_repeat: int,
		arc_radius: float
) -> ArrayMesh:
	var norm_rect: Rect2 = Rect2(0, 0, 1, 1)
	var norm_size: Vector2 = Vector2(1, 1)
	var world_size: Vector2 = Vector2(grid_size, grid_size)

	match mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE:
			return TileMeshGenerator.create_tile_quad(norm_rect, norm_size, world_size)
		GlobalConstants.MeshMode.FLAT_TRIANGULE:
			return TileMeshGenerator.create_tile_triangle(norm_rect, norm_size, world_size)
		GlobalConstants.MeshMode.BOX_MESH:
			if texture_repeat == GlobalConstants.TextureRepeatMode.REPEAT:
				return TileMeshGenerator.create_box_mesh_repeat(grid_size)
			return TileMeshGenerator.create_box_mesh(grid_size)
		GlobalConstants.MeshMode.PRISM_MESH:
			if texture_repeat == GlobalConstants.TextureRepeatMode.REPEAT:
				return TileMeshGenerator.create_prism_mesh_repeat(grid_size)
			return TileMeshGenerator.create_prism_mesh(grid_size)
		GlobalConstants.MeshMode.FLAT_ARCH:
			return TileMeshGenerator.create_arch_mesh(norm_rect, norm_size, world_size, arc_radius)
		GlobalConstants.MeshMode.FLAT_ARCH_I:
			return TileMeshGenerator.create_arch_i_mesh(norm_rect, norm_size, world_size, arc_radius)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
			return TileMeshGenerator.create_arch_corner_mesh(norm_rect, norm_size, world_size, arc_radius)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
			return TileMeshGenerator.create_arch_corner_i_mesh(norm_rect, norm_size, world_size, arc_radius)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
			return TileMeshGenerator.create_arch_corner_cap_mesh(norm_rect, norm_size, world_size, arc_radius)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
			return TileMeshGenerator.create_arch_corner_cap_i_mesh(norm_rect, norm_size, world_size, arc_radius)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
			return TileMeshGenerator.create_arch_corner_cap_duo_mesh(norm_rect, norm_size, world_size, arc_radius)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C:
			return TileMeshGenerator.create_arch_corner_c_mesh(norm_rect, norm_size, world_size, arc_radius)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I:
			return TileMeshGenerator.create_arch_corner_c_i_mesh(norm_rect, norm_size, world_size, arc_radius)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S:
			return TileMeshGenerator.create_arch_corner_s_mesh(norm_rect, norm_size, world_size, arc_radius)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
			return TileMeshGenerator.create_arch_corner_s_i_mesh(norm_rect, norm_size, world_size, arc_radius)

	push_error("TileMeshFactory: unknown mesh_mode %d, falling back to quad" % int(mesh_mode))
	return TileMeshGenerator.create_tile_quad(norm_rect, norm_size, world_size)
