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
	var is_tilted: bool = false
	if not PlaneCoordinateMapper.is_supported_orientation(orientation):
		var ori_data: Dictionary = GlobalUtil.ORIENTATION_DATA.get(orientation, {})
		if ori_data.is_empty():
			return [start_key]
		base_orientation = ori_data["base"]
		is_tilted = true

	# For tilted tiles: build 2D → Array of candidates lookup
	# Multiple tiles can project to same 2D pos (parallel ramps at different depths)
	var pos_2d_lookup: Dictionary = {}  # Vector2i → Array[Dictionary{key, pos}]
	if is_tilted:
		var tile_count: int = tile_map_layer.get_tile_count()
		for i: int in range(tile_count):
			var data: Dictionary = tile_map_layer.get_tile_data_at(i)
			if data["orientation"] != orientation:
				continue
			var pos_2d: Vector2i = PlaneCoordinateMapper.to_2d(data["grid_position"], base_orientation)
			var key: int = GlobalUtil.make_tile_key(data["grid_position"], orientation)
			if not pos_2d_lookup.has(pos_2d):
				pos_2d_lookup[pos_2d] = []
			pos_2d_lookup[pos_2d].append({"key": key, "pos": data["grid_position"]})

	# BFS
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
		var current_pos: Vector3 = tile_map_layer.get_tile_data_at(current_index)["grid_position"]

		if is_tilted:
			# Tilted path: 2D projected neighbors with closest-distance filter
			var current_2d: Vector2i = PlaneCoordinateMapper.to_2d(current_pos, base_orientation)
			for offset: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var neighbor_2d: Vector2i = current_2d + offset
				if not pos_2d_lookup.has(neighbor_2d):
					continue
				# Pick closest candidate from same ramp (not a parallel ramp)
				var neighbor_key: int = _find_closest_tile(pos_2d_lookup[neighbor_2d], current_pos)
				if neighbor_key < 0:
					continue
				if visited.has(neighbor_key):
					continue
				if match_uv:
					var neighbor_uv: Rect2 = tile_map_layer.get_tile_uv_rect(neighbor_key)
					if not neighbor_uv.is_equal_approx(start_uv):
						continue
				queue.append(neighbor_key)
		else:
			# Base path: direct neighbor calculation (no lookup needed)
			for dir: String in CARDINAL_DIRS:
				var neighbor_pos: Vector3 = PlaneCoordinateMapper.get_neighbor_position_3d(
					current_pos, base_orientation, dir)
				var neighbor_key: int = GlobalUtil.make_tile_key(neighbor_pos, orientation)
				if visited.has(neighbor_key):
					continue
				if not tile_map_layer.has_tile(neighbor_key):
					continue
				if match_uv:
					var neighbor_uv: Rect2 = tile_map_layer.get_tile_uv_rect(neighbor_key)
					if not neighbor_uv.is_equal_approx(start_uv):
						continue
				queue.append(neighbor_key)

	return result


## Find closest tile from candidates to reference position.
## Returns tile_key or -1 if none within adjacency threshold.
## Adjacent tilted tiles are max ~1.12 units apart (sqrt(1² + 0.5²)).
func _find_closest_tile(candidates: Array, ref_pos: Vector3) -> int:
	var best_key: int = -1
	var best_dist_sq: float = 2.25  # 1.5² — threshold for adjacent tiles
	for candidate: Dictionary in candidates:
		var dist_sq: float = ref_pos.distance_squared_to(candidate["pos"])
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_key = candidate["key"]
	return best_key



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
