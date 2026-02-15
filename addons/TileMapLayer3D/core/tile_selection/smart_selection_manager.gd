class_name SmartSelectManager
extends RefCounted



## Cardinal directions only (4-connected flood fill, no diagonals)
const CARDINAL_DIRS: Array[String] = ["N", "E", "S", "W"]


## Pick the tile closest to camera at screen_pos.
## Returns { "tile_key": int, "tile_data": Dictionary, "index": int } or {} if no hit.
func pick_tile_at(camera: Camera3D, screen_pos: Vector2, tile_map_layer: TileMapLayer3D) -> Dictionary:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var grid_size: float = tile_map_layer.settings.grid_size

	var closest_t: float = INF
	var closest_index: int = -1

	var tile_count: int = tile_map_layer.get_tile_count()
	for i in range(tile_count):
		var tile_data: Dictionary = tile_map_layer.get_tile_data_at(i)
		var transform: Transform3D = _build_tile_transform(tile_data, grid_size)
		var t: float = _ray_quad_intersect(ray_origin, ray_dir, transform, grid_size)
		if t > 0.0 and t < closest_t:
			closest_t = t
			closest_index = i

	if closest_index < 0:
		return {}

	var tile_data: Dictionary = tile_map_layer.get_tile_data_at(closest_index)
	var grid_pos: Vector3 = tile_data["grid_position"]
	var orientation: int = tile_data["orientation"]
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
	return { "tile_key": tile_key, "tile_data": tile_data, "index": closest_index }

## Flood fill from a start tile, expanding to contiguous neighbors on the same plane.
## match_uv = true  → only expand to neighbors with identical UV (magic wand)
## match_uv = false → expand to ALL neighbors on same plane (connected region)
## Returns Array of tile_keys for all selected tiles (including start tile).
func pick_flood_fill(start_key: int, tile_map_layer: TileMapLayer3D, match_uv: bool = true) -> Array[int]:
	var start_index: int = tile_map_layer.get_tile_index(start_key)
	if start_index < 0:
		return []

	var start_data: Dictionary = tile_map_layer.get_tile_data_at(start_index)
	var orientation: int = start_data["orientation"]
	var start_uv: Rect2 = start_data["uv_rect"]

	# Map tilted orientations (6-25) to their base (0-5) for neighbor lookups
	var base_orientation: int = orientation
	if not PlaneCoordinateMapper.is_supported_orientation(orientation):
		var ori_data: Dictionary = GlobalUtil.ORIENTATION_DATA.get(orientation, {})
		if ori_data.is_empty():
			return [start_key]  # Unknown orientation
		base_orientation = ori_data["base"]

	var visited: Dictionary = {}  # tile_key → true
	var queue: Array[int] = [start_key]
	var result: Array[int] = []

	while queue.size() > 0:
		var current_key: int = queue.pop_front()
		if visited.has(current_key):
			continue
		visited[current_key] = true
		result.append(current_key)

		# Get grid_pos for neighbor lookup
		var current_index: int = tile_map_layer.get_tile_index(current_key)
		var current_pos: Vector3 = tile_map_layer.get_tile_data_at(current_index)["grid_position"]

		# Check 4 cardinal neighbors
		for dir: String in CARDINAL_DIRS:
			var neighbor_pos: Vector3 = PlaneCoordinateMapper.get_neighbor_position_3d(
				current_pos, base_orientation, dir)  # ← base for grid math
			var neighbor_key: int = GlobalUtil.make_tile_key(neighbor_pos, orientation)  # ← original for key

			if visited.has(neighbor_key):
				continue
			if not tile_map_layer.has_tile(neighbor_key):
				continue

			# UV match filter
			if match_uv:
				var neighbor_uv: Rect2 = tile_map_layer.get_tile_uv_rect(neighbor_key)
				if not neighbor_uv.is_equal_approx(start_uv):
					continue

			queue.append(neighbor_key)

	return result







func _ray_quad_intersect(ray_origin: Vector3, ray_dir: Vector3,
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

func _ray_triangle_intersect(ray_origin: Vector3, ray_dir: Vector3,
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

func _build_tile_transform(tile_data: Dictionary, grid_size: float) -> Transform3D:
	return GlobalUtil.build_tile_transform(
		tile_data["grid_position"], tile_data["orientation"],
		tile_data["mesh_rotation"], grid_size,
		tile_data["is_face_flipped"], tile_data["spin_angle_rad"],
		tile_data["tilt_angle_rad"], tile_data["diagonal_scale"],
		tile_data["tilt_offset_factor"], tile_data["mesh_mode"],
		tile_data["depth_scale"])
