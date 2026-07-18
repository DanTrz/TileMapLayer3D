class_name RegionSystem
extends RefCounted


# ---------------------------------------------------------------------------
# STATIC MATH — no instance state required
# ---------------------------------------------------------------------------

static func resolve_region_key(world_pos: Vector3) -> Vector3i:
	const EPS: float = 1e-5
	var size: float = GlobalConstants.CHUNK_REGION_SIZE
	return Vector3i(
		int(floor((world_pos.x - EPS) / size)),
		int(floor((world_pos.y - EPS) / size)),
		int(floor((world_pos.z - EPS) / size))
	)


static func region_key_to_world_origin(rk: Vector3i) -> Vector3:
	return Vector3(rk) * GlobalConstants.CHUNK_REGION_SIZE


static func region_aabb(rk: Vector3i) -> AABB:
	return AABB(region_key_to_world_origin(rk), Vector3.ONE * GlobalConstants.CHUNK_REGION_SIZE)


static func chunk_local_aabb() -> AABB:
	return GlobalConstants.CHUNK_LOCAL_AABB


static func pack(rk: Vector3i) -> int:
	const MASK_20BIT: int = 0xFFFFF
	return ((rk.x & MASK_20BIT) << 40) | ((rk.y & MASK_20BIT) << 20) | (rk.z & MASK_20BIT)


static func unpack(packed: int) -> Vector3i:
	const MASK_20BIT: int = 0xFFFFF
	var x: int = (packed >> 40) & MASK_20BIT
	var y: int = (packed >> 20) & MASK_20BIT
	var z: int = packed & MASK_20BIT
	if x >= 0x80000:
		x -= 0x100000
	if y >= 0x80000:
		y -= 0x100000
	if z >= 0x80000:
		z -= 0x100000
	return Vector3i(x, y, z)


static func world_to_region_local(world_pos: Vector3) -> Vector3:
	return world_pos - region_key_to_world_origin(resolve_region_key(world_pos))



static func overlapping_region_keys(world_aabb: AABB) -> Array[Vector3i]:
	var size: float = GlobalConstants.CHUNK_REGION_SIZE
	var local_min: Vector3 = GlobalConstants.CHUNK_LOCAL_AABB.position
	var local_max: Vector3 = GlobalConstants.CHUNK_LOCAL_AABB.position + GlobalConstants.CHUNK_LOCAL_AABB.size
	var search_min: Vector3 = world_aabb.position - local_max
	var search_max: Vector3 = world_aabb.end - local_min
	var min_key: Vector3i = Vector3i(
		int(floor(search_min.x / size)),
		int(floor(search_min.y / size)),
		int(floor(search_min.z / size))
	)
	var max_key: Vector3i = Vector3i(
		int(floor(search_max.x / size)),
		int(floor(search_max.y / size)),
		int(floor(search_max.z / size))
	)
	var result: Array[Vector3i] = []
	for x: int in range(min_key.x, max_key.x + 1):
		for y: int in range(min_key.y, max_key.y + 1):
			for z: int in range(min_key.z, max_key.z + 1):
				result.append(Vector3i(x, y, z))
	return result



var _registry: Dictionary = {}


func get_region(packed: int) -> TerrainRegionChunk:
	return _registry.get(packed, null)


func get_or_create_region(packed: int) -> TerrainRegionChunk:
	if not _registry.has(packed):
		var rk: Vector3i = unpack(packed)
		_registry[packed] = TerrainRegionChunk.from_region_key(rk)
	return _registry[packed]


func all_regions() -> Array[TerrainRegionChunk]:
	var result: Array[TerrainRegionChunk] = []
	for v in _registry.values():
		result.append(v as TerrainRegionChunk)
	return result


func clear() -> void:
	_registry.clear()


func region_for_world_pos(world_pos: Vector3) -> TerrainRegionChunk:
	var packed: int = pack(resolve_region_key(world_pos))
	return _registry.get(packed, null)


func regions_for_world_aabb(world_aabb: AABB) -> Array[TerrainRegionChunk]:
	var result: Array[TerrainRegionChunk] = []
	for rk: Vector3i in overlapping_region_keys(world_aabb):
		var packed: int = pack(rk)
		var chunk: TerrainRegionChunk = _registry.get(packed, null)
		if chunk != null:
			result.append(chunk)
	return result


func register_tile(tile_key: int, columnar_index: int, region_key_packed: int) -> void:
	var region: TerrainRegionChunk = get_or_create_region(region_key_packed)
	var existing: int = region.tile_keys.find(tile_key)
	if existing >= 0:
		region.columnar_indices[existing] = columnar_index
	else:
		region.add_tile(tile_key, columnar_index)


func unregister_tile(tile_key: int, region_key_packed: int) -> void:
	var region: TerrainRegionChunk = _registry.get(region_key_packed, null)
	if region == null:
		return
	region.remove_tile(tile_key)
	if region.is_empty():
		_registry.erase(region_key_packed)


func register_vertex_tile(tile_key: int, world_pos: Vector3) -> void:
	var packed: int = pack(resolve_region_key(world_pos))
	get_or_create_region(packed).add_vertex_tile(tile_key)


func unregister_vertex_tile(tile_key: int, region_key_packed: int) -> void:
	var region: TerrainRegionChunk = _registry.get(region_key_packed, null)
	if region == null:
		return
	region.remove_vertex_tile(tile_key)
	if region.is_empty():
		_registry.erase(region_key_packed)


func ray_march_regions(
		ray_origin: Vector3,
		ray_dir: Vector3,
		max_distance: float,
		out_chunks: Array[TerrainRegionChunk],
		out_t_enter: PackedFloat32Array,
		diag_visited: Array[int] = []) -> void:
	out_chunks.clear()
	out_t_enter.clear()
	if _registry.is_empty():
		return
	var size: float = GlobalConstants.CHUNK_REGION_SIZE

	var rk: Vector3i = resolve_region_key(ray_origin)

	var step_x: int = 0
	var step_y: int = 0
	var step_z: int = 0
	var t_delta_x: float = INF
	var t_delta_y: float = INF
	var t_delta_z: float = INF
	var t_max_x: float = INF
	var t_max_y: float = INF
	var t_max_z: float = INF

	if absf(ray_dir.x) > 1e-9:
		step_x = 1 if ray_dir.x > 0.0 else -1
		t_delta_x = size / absf(ray_dir.x)
		var next_boundary_x: float = float(rk.x + (1 if step_x > 0 else 0)) * size
		t_max_x = (next_boundary_x - ray_origin.x) / ray_dir.x
	if absf(ray_dir.y) > 1e-9:
		step_y = 1 if ray_dir.y > 0.0 else -1
		t_delta_y = size / absf(ray_dir.y)
		var next_boundary_y: float = float(rk.y + (1 if step_y > 0 else 0)) * size
		t_max_y = (next_boundary_y - ray_origin.y) / ray_dir.y
	if absf(ray_dir.z) > 1e-9:
		step_z = 1 if ray_dir.z > 0.0 else -1
		t_delta_z = size / absf(ray_dir.z)
		var next_boundary_z: float = float(rk.z + (1 if step_z > 0 else 0)) * size
		t_max_z = (next_boundary_z - ray_origin.z) / ray_dir.z

	# Hard safety cap so a degenerate ray (all step=0) can't loop forever.
	# Bound by the registry size plus a small constant — any well-formed ray
	# crosses at most this many cells before t exceeds max_distance.
	var safety_cap: int = _registry.size() + 8

	var t_current: float = 0.0
	var diag_count: int = 0
	while t_current <= max_distance and safety_cap > 0:
		safety_cap -= 1
		diag_count += 1
		var packed: int = pack(rk)
		var chunk: TerrainRegionChunk = _registry.get(packed, null)
		if chunk != null:
			out_chunks.append(chunk)
			out_t_enter.append(t_current)

		if t_max_x < t_max_y and t_max_x < t_max_z:
			t_current = t_max_x
			rk.x += step_x
			t_max_x += t_delta_x
		elif t_max_y < t_max_z:
			t_current = t_max_y
			rk.y += step_y
			t_max_y += t_delta_y
		else:
			t_current = t_max_z
			rk.z += step_z
			t_max_z += t_delta_z

		# Axis-aligned ray (no step on that axis) leaves t_max at INF, so the
		# branch never picks it. If ALL three are INF the ray has zero direction
		# and we already emitted the starting cell — bail out.
		if step_x == 0 and step_y == 0 and step_z == 0:
			break

	if not diag_visited.is_empty():
		diag_visited[0] = diag_count
