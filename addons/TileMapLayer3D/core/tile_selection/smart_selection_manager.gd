class_name SmartSelectManager
extends RefCounted


const CARDINAL_DIRS: Array[String] = ["N", "E", "S", "W"]


static func pick_tile_at(ray_origin: Vector3, ray_dir: Vector3, tile_map_layer: TileMapLayer3D, max_distance: float = INF) -> PlacedTileInfo:
	var grid_size: float = tile_map_layer.settings.grid_size
	var world_ray_dir: Vector3 = ray_dir.normalized()
	if world_ray_dir.is_zero_approx():
		return null
	var node_inv: Transform3D = tile_map_layer.global_transform.affine_inverse()
	var local_ray_origin: Vector3 = node_inv * ray_origin
	var local_ray_end: Vector3 = node_inv * (ray_origin + world_ray_dir)
	if not is_inf(max_distance):
		local_ray_end = node_inv * (ray_origin + world_ray_dir * max_distance)
	var local_ray_vector: Vector3 = local_ray_end - local_ray_origin
	if local_ray_vector.is_zero_approx():
		return null
	var local_ray_dir: Vector3 = local_ray_vector.normalized()
	var local_max_distance: float = INF if is_inf(max_distance) else local_ray_vector.length()

	var closest_t: float = INF
	var closest_world_t: float = INF
	var closest_index: int = -1
	var closest_vertex_key: int = -1

	var tiles_tested: int = 0
	var tiles_full: int = 0
	var regions_hit: int = 0
	var diag_visited: Array[int] = [0]
	var debug_on: bool = GlobalConstants.DEBUG_PICK_RAYCAST

	# 3D DDA march through the region grid in distance order; falls back to O(N) scan if empty.
	var visited_chunks: Array[TerrainRegionChunk] = []
	var visited_t_enter: PackedFloat32Array = PackedFloat32Array()
	if not tile_map_layer.region_system._registry.is_empty():
		var diag_arg: Array[int] = diag_visited if debug_on else ([] as Array[int])
		tile_map_layer.region_system.ray_march_regions(
			local_ray_origin, local_ray_dir, local_max_distance,
			visited_chunks, visited_t_enter, diag_arg)

		var visited_count: int = visited_chunks.size()
		for r_idx: int in range(visited_count):
			var t_enter: float = visited_t_enter[r_idx]
			# Any region entered past the current closest hit cannot improve it.
			if closest_t < INF and t_enter >= closest_t:
				break
			var region: TerrainRegionChunk = visited_chunks[r_idx]
			# Catches diagonals where DDA stepped through the cell but the ray misses the AABB.
			if not region.world_aabb.intersects_ray(local_ray_origin, local_ray_dir):
				continue
			regions_hit += 1

			for col_idx: int in region.columnar_indices:
				if col_idx < 0:
					continue
				tiles_tested += 1
				var tile_aabb: AABB = tile_map_layer.read_tile_world_aabb_at_index(col_idx)
				if not tile_aabb.intersects_ray(local_ray_origin, local_ray_dir):
					continue
				tiles_full += 1
				var tile_info: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(col_idx)
				if tile_info == null:
					continue
				var transform: Transform3D = _build_tile_transform(tile_info, grid_size)
				var t: float = _ray_quad_intersect(local_ray_origin, local_ray_dir, transform, grid_size)
				if t <= 0.0 or t >= local_max_distance or t >= closest_t:
					continue
				var world_t: float = _world_hit_distance_from_local_t(
					local_ray_origin, local_ray_dir, t, tile_map_layer.global_transform, ray_origin)
				if world_t >= max_distance or world_t >= closest_world_t:
					continue
				closest_t = t
				closest_world_t = world_t
				closest_index = col_idx
				closest_vertex_key = -1

			# Vertex-edited corners are stored in WORLD space; Möller-Trumbore is single-sided so retry reversed.
			for vtx_key: int in region.vertex_tile_keys:
				tiles_tested += 1
				var raw_e = tile_map_layer.get_vertex_entry(vtx_key)
				if not raw_e is VertexTileEntry:
					continue
				var entry: VertexTileEntry = raw_e
				var corners: PackedVector3Array = entry.corners
				if corners.size() != 4:
					continue
				var t1: float = _ray_triangle_intersect(ray_origin, world_ray_dir, corners[3], corners[2], corners[1])
				if t1 < 0.0:
					t1 = _ray_triangle_intersect(ray_origin, world_ray_dir, corners[1], corners[2], corners[3])
				if t1 > 0.0 and t1 < closest_world_t and t1 < max_distance:
					closest_world_t = t1
					closest_t = t1
					closest_vertex_key = vtx_key
					closest_index = -1
				var t2: float = _ray_triangle_intersect(ray_origin, world_ray_dir, corners[3], corners[1], corners[0])
				if t2 < 0.0:
					t2 = _ray_triangle_intersect(ray_origin, world_ray_dir, corners[0], corners[1], corners[3])
				if t2 > 0.0 and t2 < closest_world_t and t2 < max_distance:
					closest_world_t = t2
					closest_t = t2
					closest_vertex_key = vtx_key
					closest_index = -1
	else:
		var tile_count: int = tile_map_layer.get_tile_count()
		tiles_tested = tile_count
		for i: int in range(tile_count):
			var tile_info: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(i)
			if tile_info == null:
				continue
			var transform: Transform3D = _build_tile_transform(tile_info, grid_size)
			var t: float = _ray_quad_intersect(local_ray_origin, local_ray_dir, transform, grid_size)
			if t > 0.0 and t < local_max_distance:
				var world_t: float = _world_hit_distance_from_local_t(
					local_ray_origin, local_ray_dir, t, tile_map_layer.global_transform, ray_origin)
				if world_t >= max_distance or world_t >= closest_world_t:
					continue
				closest_t = t
				closest_world_t = world_t
				closest_index = i
				closest_vertex_key = -1

	if debug_on:
		var hit_str: String = "none"
		if closest_vertex_key != -1:
			hit_str = "vtx:" + str(closest_vertex_key)
		elif closest_index >= 0:
			hit_str = "col:" + str(closest_index)
		print("[pick_tile_at] regions_visited=", diag_visited[0],
				"  regions_hit=", regions_hit,
				"  tiles_tested=", tiles_tested,
				"  tiles_full=", tiles_full,
				"  hit=", hit_str)

	if closest_vertex_key != -1:
		var vtx_entry: VertexTileEntry = tile_map_layer.get_vertex_entry(closest_vertex_key)
		var vertex_tile_info: PlacedTileInfo = vtx_entry.tile_info if vtx_entry != null else null
		if vertex_tile_info != null:
			vertex_tile_info.tile_key = closest_vertex_key
		return vertex_tile_info

	if closest_index < 0:
		return null

	var tile_info: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(closest_index)
	if tile_info == null:
		return null
	tile_info.tile_key = GlobalUtil.make_tile_key(tile_info.grid_position, tile_info.orientation)
	return tile_info


static func _world_hit_distance_from_local_t(local_ray_origin: Vector3, local_ray_dir: Vector3,
		t: float, node_transform: Transform3D, world_ray_origin: Vector3) -> float:
	var local_hit: Vector3 = local_ray_origin + local_ray_dir * t
	var world_hit: Vector3 = node_transform * local_hit
	return world_ray_origin.distance_to(world_hit)


static func pick_flood_fill(start_key: int, tile_map_layer: TileMapLayer3D,
		match_mode: GlobalConstants.SmartSelectionMode = GlobalConstants.SmartSelectionMode.CONNECTED_NEIGHBOR) -> Array[int]:
	var start_index: int = tile_map_layer.get_tile_index(start_key)
	if start_index < 0:
		return []

	var start_data: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(start_index)
	if start_data == null:
		return []
	var orientation: int = start_data.orientation
	var start_uv: Rect2 = start_data.uv_rect
	var start_mesh_mode: GlobalConstants.MeshMode = start_data.mesh_mode

	var base_orientation: int = orientation
	var is_tilted: bool = false
	if not PlaneCoordinateMapper.is_supported_orientation(orientation):
		var ori_data: Dictionary = GlobalUtil.ORIENTATION_DATA.get(orientation, {})
		if ori_data.is_empty():
			return [start_key]
		base_orientation = ori_data["base"]
		is_tilted = true

	var tilted_tiles: Array = []
	if is_tilted:
		var tile_count: int = tile_map_layer.get_tile_count()
		for i: int in range(tile_count):
			var data: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(i)
			if data == null or data.orientation != orientation:
				continue
			tilted_tiles.append({
				"key": GlobalUtil.make_tile_key(data.grid_position, orientation),
				"pos": data.grid_position
			})

	var snap: float = tile_map_layer.settings.grid_snap_size

	var visited: Dictionary = {}
	var queue: Array[int] = [start_key]
	var result: Array[int] = []

	while queue.size() > 0:
		var current_key: int = queue.pop_front()
		if visited.has(current_key):
			continue
		visited[current_key] = true
		result.append(current_key)

		var current_index: int = tile_map_layer.get_tile_index(current_key)
		var current_data: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(current_index)
		if current_data == null:
			continue
		var current_pos: Vector3 = current_data.grid_position

		if is_tilted:
			for candidate: Dictionary in tilted_tiles:
				if visited.has(candidate["key"]):
					continue
				if not _is_tilted_cardinal_neighbor(current_pos, candidate["pos"], base_orientation, snap):
					continue
				if not _neighbor_accepted(candidate["key"], match_mode, start_uv, start_mesh_mode, tile_map_layer):
					continue
				queue.append(candidate["key"])
		else:
			for dir: String in CARDINAL_DIRS:
				var neighbor_pos: Vector3 = PlaneCoordinateMapper.get_neighbor_position_3d(
					current_pos, base_orientation, dir)
				var neighbor_key: int = GlobalUtil.make_tile_key(neighbor_pos, orientation)
				if visited.has(neighbor_key):
					continue
				if not tile_map_layer.has_tile(neighbor_key):
					continue
				if not _neighbor_accepted(neighbor_key, match_mode, start_uv, start_mesh_mode, tile_map_layer):
					continue
				queue.append(neighbor_key)

	return result


## Horizontal loop select: connectivity is an exact edge-endpoint graph. A wall's XZ footprint is a
## 1-cell segment; two walls connect iff their endpoints touch, so a real gap can't leak onto a
## separate structure. All math is in grid_position cell units (invariant to grid_size / snap).
## FLOOR/CEILING starts fall back to a 4-neighbor cell flood.
static func pick_horizontal_loop(start_key: int, tile_map_layer: TileMapLayer3D) -> Array[int]:
	var start_index: int = tile_map_layer.get_tile_index(start_key)
	if start_index < 0:
		return []

	var start_data: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(start_index)
	if start_data == null:
		return []

	var scale: float = TileKeySystem.COORD_SCALE
	var band_y_q: int = roundi(start_data.grid_position.y * scale)

	if _wall_endpoint_keys(start_data).is_empty():
		return _floor_cell_flood(start_key, start_data, tile_map_layer, band_y_q, scale)

	var candidates: Array = []
	var endpoint_map: Dictionary = {}
	var start_cand: int = -1
	var tile_count: int = tile_map_layer.get_tile_count()
	for i: int in range(tile_count):
		var data: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(i)
		if data == null:
			continue
		if roundi(data.grid_position.y * scale) != band_y_q:
			continue
		var eks: Array[Vector2i] = _wall_endpoint_keys(data)
		if eks.size() != 2:
			continue
		var key: int = GlobalUtil.make_tile_key(data.grid_position, data.orientation)
		var cand_index: int = candidates.size()
		candidates.append({"key": key, "e0": eks[0], "e1": eks[1]})
		if key == start_key:
			start_cand = cand_index
		for ek: Vector2i in eks:
			var arr: Array = endpoint_map.get(ek, [])
			arr.append(cand_index)
			endpoint_map[ek] = arr

	if start_cand < 0:
		return [start_key]

	var visited: Dictionary = {}
	var queue: Array[int] = [start_cand]
	var result: Array[int] = []
	while queue.size() > 0:
		var current: int = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		result.append(candidates[current]["key"])
		for ek: Vector2i in [candidates[current]["e0"], candidates[current]["e1"]]:
			for other: int in endpoint_map.get(ek, []):
				if not visited.has(other):
					queue.append(other)

	return result


## The 2 XZ footprint endpoint keys for a wall, from its real transform (correct for flat and tilted).
## Returns [] for FLOOR/CEILING (depth axis "y"), which use the cell-flood branch.
static func _wall_endpoint_keys(tile: PlacedTileInfo) -> Array[Vector2i]:
	const HALF: float = 0.5
	const UNIT: float = 0.5
	var base_ori: int = tile.orientation
	var ori_data: Dictionary = GlobalUtil.ORIENTATION_DATA.get(tile.orientation, {})
	if not ori_data.is_empty():
		base_ori = ori_data.get("base", tile.orientation)

	if GlobalUtil.get_orientation_depth_axis(base_ori) == "y":
		return []

	# grid_size = 1.0 keeps endpoints in cell units; the 0.5 lattice + integer keys make connectivity exact.
	var t: Transform3D = GlobalUtil.build_tile_transform(
		tile.grid_position, tile.orientation, tile.mesh_rotation, 1.0, tile.is_face_flipped)
	var locals: Array[Vector3] = [
		Vector3(-HALF, 0.0, -HALF), Vector3(HALF, 0.0, -HALF),
		Vector3(HALF, 0.0, HALF), Vector3(-HALF, 0.0, HALF)]
	var seen: Dictionary = {}
	var keys: Array[Vector2i] = []
	for lc: Vector3 in locals:
		var w: Vector3 = t * lc
		var k: Vector2i = Vector2i(roundi(w.x / UNIT), roundi(w.z / UNIT))
		if not seen.has(k):
			seen[k] = true
			keys.append(k)
	return keys


static func _floor_cell_flood(start_key: int, start_data: PlacedTileInfo,
		tile_map_layer: TileMapLayer3D, band_y_q: int, scale: float) -> Array[int]:
	var start_base: int = GlobalUtil.ORIENTATION_DATA.get(
		start_data.orientation, {}).get("base", start_data.orientation)

	var cell_to_key: Dictionary = {}
	var tile_count: int = tile_map_layer.get_tile_count()
	for i: int in range(tile_count):
		var data: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(i)
		if data == null:
			continue
		if roundi(data.grid_position.y * scale) != band_y_q:
			continue
		if not _wall_endpoint_keys(data).is_empty():
			continue
		var base_ori: int = GlobalUtil.ORIENTATION_DATA.get(
			data.orientation, {}).get("base", data.orientation)
		if base_ori != start_base:
			continue
		var cell: Vector2i = Vector2i(roundi(data.grid_position.x), roundi(data.grid_position.z))
		cell_to_key[cell] = GlobalUtil.make_tile_key(data.grid_position, data.orientation)

	var start_cell: Vector2i = Vector2i(
		roundi(start_data.grid_position.x), roundi(start_data.grid_position.z))
	if not cell_to_key.has(start_cell):
		return [start_key]

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start_cell]
	var result: Array[int] = []
	while queue.size() > 0:
		var cell: Vector2i = queue.pop_front()
		if visited.has(cell) or not cell_to_key.has(cell):
			continue
		visited[cell] = true
		result.append(cell_to_key[cell])
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + d
			if cell_to_key.has(n) and not visited.has(n):
				queue.append(n)
	return result


static func _neighbor_accepted(neighbor_key: int, match_mode: GlobalConstants.SmartSelectionMode,
		start_uv: Rect2, start_mesh_mode: GlobalConstants.MeshMode, tile_map_layer: TileMapLayer3D) -> bool:
	match match_mode:
		GlobalConstants.SmartSelectionMode.CONNECTED_UV:
			return tile_map_layer.get_tile_uv_rect(neighbor_key).is_equal_approx(start_uv)
		GlobalConstants.SmartSelectionMode.CONNECTED_TILE_TYPE:
			var neighbor_info: PlacedTileInfo = tile_map_layer.get_tile_info_from_key(neighbor_key)
			return neighbor_info != null and neighbor_info.mesh_mode == start_mesh_mode
		_:
			return true


## Cardinal-neighbor test for tilted tiles. For 45° ramps dist²=2*snap²; threshold 2.5*snap² covers it.
static func _is_tilted_cardinal_neighbor(pos_a: Vector3, pos_b: Vector3,
		base_orientation: int, snap: float) -> bool:
	var axes: Dictionary = PlaneCoordinateMapper.PLANE_AXES[base_orientation]
	var dh: float = 0.0
	var dv: float = 0.0
	match axes["h_axis"]:
		"x": dh = absf(pos_b.x - pos_a.x)
		"y": dh = absf(pos_b.y - pos_a.y)
		"z": dh = absf(pos_b.z - pos_a.z)
	match axes["v_axis"]:
		"x": dv = absf(pos_b.x - pos_a.x)
		"y": dv = absf(pos_b.y - pos_a.y)
		"z": dv = absf(pos_b.z - pos_a.z)
	var step_lo: float = snap * 0.7
	var step_hi: float = snap * 1.3
	var zero_hi: float = snap * 0.3
	var h_is_step: bool = dh > step_lo and dh < step_hi
	var v_is_step: bool = dv > step_lo and dv < step_hi
	var h_is_zero: bool = dh < zero_hi
	var v_is_zero: bool = dv < zero_hi
	if not ((h_is_step and v_is_zero) or (h_is_zero and v_is_step)):
		return false
	return pos_a.distance_squared_to(pos_b) < snap * snap * 2.5


static func _ray_quad_intersect(ray_origin: Vector3, ray_dir: Vector3,
						 tile_transform: Transform3D, grid_size: float) -> float:
	var half: float = grid_size / 2.0
	var v0: Vector3 = tile_transform * Vector3(-half, 0.0, -half)
	var v1: Vector3 = tile_transform * Vector3( half, 0.0, -half)
	var v2: Vector3 = tile_transform * Vector3( half, 0.0,  half)
	var v3: Vector3 = tile_transform * Vector3(-half, 0.0,  half)
	var t1: float = _ray_triangle_intersect(ray_origin, ray_dir, v0, v1, v2)
	if t1 > 0.0:
		return t1
	return _ray_triangle_intersect(ray_origin, ray_dir, v0, v2, v3)

static func _ray_triangle_intersect(ray_origin: Vector3, ray_dir: Vector3,
							  v0: Vector3, v1: Vector3, v2: Vector3) -> float:
	var edge1: Vector3 = v1 - v0
	var edge2: Vector3 = v2 - v0
	var h: Vector3 = ray_dir.cross(edge2)
	var a: float = edge1.dot(h)
	if absf(a) < 0.00001:
		return -1.0
	var f: float = 1.0 / a
	var s: Vector3 = ray_origin - v0
	var u: float = f * s.dot(h)
	if u < 0.0 or u > 1.0:
		return -1.0
	var q: Vector3 = s.cross(edge1)
	var v: float = f * ray_dir.dot(q)
	if v < 0.0 or u + v > 1.0:
		return -1.0
	return f * edge2.dot(q)

static func _build_tile_transform(tile_info: PlacedTileInfo, grid_size: float) -> Transform3D:
	if tile_info.has_custom_transform:
		return tile_info.custom_transform
	return GlobalUtil.build_tile_transform(
		tile_info.grid_position, tile_info.orientation,
		tile_info.mesh_rotation, grid_size,
		tile_info.is_face_flipped, tile_info.spin_angle_rad,
		tile_info.tilt_angle_rad, tile_info.diagonal_scale,
		tile_info.tilt_offset_factor, tile_info.mesh_mode,
		tile_info.depth_scale,
		tile_info.depth_growth_mode == GlobalConstants.DepthGrowthMode.INWARD)
