class_name SpriteCollisionGenerator
extends RefCounted

## ============================================================================
## SPRITE COLLISION GENERATOR FOR GODOT 2.5D TILE PLACER
## ============================================================================

# Preload global constants
const GlobalConstants = preload("uid://ciwb78xe27lk6")
## Generates optimized collision shapes from sprite textures by tracing opaque pixels.
## Inspired by Sprite2Mesh approach but custom-built for our MultiMesh tile system.
##
## Key Features:
## - Marching squares algorithm for outline tracing
## - Shape caching per unique UV rect (massive performance boost)
## - Skips fully transparent tiles
## - Fallback to BoxShape3D for simple rectangles
## - Douglas-Peucker simplification for complex shapes

# ==============================================================================
# COLLISION SHAPE CACHE
# ==============================================================================

# Cache: "texture_rid:uv_rect_hash" -> Shape3D
static var _shape_cache: Dictionary = {}
static var _cache_stats: Dictionary = {"hits": 0, "misses": 0}

## Clears the collision shape cache
## Call this when unloading scenes or switching tilesets to prevent memory leaks
static func clear_cache() -> void:
	_shape_cache.clear()
	_cache_stats = {"hits": 0, "misses": 0}
	print("SpriteCollisionGenerator: Cache cleared")

## Returns cache statistics for debugging
static func get_cache_stats() -> Dictionary:
	return {
		"hits": _cache_stats.get("hits", 0),
		"misses": _cache_stats.get("misses", 0),
		"cached_shapes": _shape_cache.size(),
		"hit_rate": _cache_stats.get("hits", 0) / float(max(1, _cache_stats.get("hits", 0) + _cache_stats.get("misses", 0)))
	}

# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================

## Generates collision shape from texture region
## This is the main method to call from outside code
##
## @param texture: The tileset texture to sample
## @param uv_rect: The tile's UV rectangle in PIXELS (not normalized)
## @param grid_size: World size of tile in 3D space
## @param alpha_threshold: Pixels with alpha > this value are considered solid (default 0.5)
## @returns: Shape3D (ConvexPolygonShape3D or BoxShape3D) or null if fully transparent
static func generate_collision_from_texture(
	texture: Texture2D,
	uv_rect: Rect2,
	grid_size: float,
	alpha_threshold: float = 0.5
) -> Shape3D:

	# Check cache first
	var cache_key = _make_cache_key(texture, uv_rect)
	if _shape_cache.has(cache_key):
		if _cache_stats.has("hits"):
			_cache_stats["hits"] += 1
		else:
			_cache_stats["hits"] = 1
		return _shape_cache[cache_key]

	# Increment miss count safely
	if _cache_stats.has("misses"):
		_cache_stats["misses"] += 1
	else:
		_cache_stats["misses"] = 1

	# Get image data
	var image = texture.get_image()
	if not image:
		push_warning("SpriteCollisionGenerator: Cannot get image from texture")
		return _create_fallback_box(grid_size)

	# IMPORTANT: Decompress the image if it's compressed
	# get_pixel() doesn't work on compressed images
	if image.is_compressed():
		image.decompress()

	# Debug: Check if image data is valid
	if image.get_width() == 0 or image.get_height() == 0:
		push_warning("SpriteCollisionGenerator: Image has zero dimensions")
		return _create_fallback_box(grid_size)

	# Trace opaque pixel outline using marching squares
	var outline_points = _trace_opaque_outline(image, uv_rect, alpha_threshold)

	# Handle special cases
	if outline_points.is_empty():
		# Fully transparent - skip collision
		_shape_cache[cache_key] = null
		return null

	if _is_full_rectangle(outline_points, uv_rect.size):
		# Simple rectangle - use box shape for performance
		var box_shape = _create_fallback_box(grid_size)
		_shape_cache[cache_key] = box_shape
		return box_shape

	# Create convex shape from traced outline
	var shape = _create_convex_shape_2d(outline_points, uv_rect.size, grid_size)

	# Cache and return
	_shape_cache[cache_key] = shape
	return shape

# ==============================================================================
# CACHE KEY GENERATION
# ==============================================================================

## Creates unique cache key from texture and UV rect
static func _make_cache_key(texture: Texture2D, uv_rect: Rect2) -> String:
	var texture_id = texture.get_rid().get_id()
	# Use floor to handle floating point precision issues
	return "%d_%d_%d_%d_%d" % [
		texture_id,
		int(uv_rect.position.x),
		int(uv_rect.position.y),
		int(uv_rect.size.x),
		int(uv_rect.size.y)
	]

# ==============================================================================
# MARCHING SQUARES ALGORITHM
# ==============================================================================

## Traces the outline of opaque pixels using marching squares algorithm
## @param image: Source image to sample
## @param uv_rect: Rectangle region to trace (in pixels)
## @param alpha_threshold: Alpha cutoff for solid vs transparent
## @returns: Array of 2D points forming the outline, or empty if fully transparent
static func _trace_opaque_outline(
	image: Image,
	uv_rect: Rect2,
	alpha_threshold: float
) -> PackedVector2Array:

	var start_x = int(uv_rect.position.x)
	var start_y = int(uv_rect.position.y)
	var width = int(uv_rect.size.x)
	var height = int(uv_rect.size.y)

	# Safety checks
	if width <= 0 or height <= 0:
		return PackedVector2Array()

	# Build binary grid (true = opaque, false = transparent)
	var grid: Array = []
	var has_opaque = false

	for y in range(height + 1):
		var row: Array = []
		for x in range(width + 1):
			var pixel_x = start_x + x
			var pixel_y = start_y + y

			# Bounds check
			if pixel_x >= image.get_width() or pixel_y >= image.get_height():
				row.append(false)
				continue

			var pixel = image.get_pixel(pixel_x, pixel_y)
			var is_opaque = pixel.a > alpha_threshold
			row.append(is_opaque)
			if is_opaque:
				has_opaque = true
		grid.append(row)

	if not has_opaque:
		return PackedVector2Array()

	# Find all opaque pixels for simple convex hull
	var opaque_points: PackedVector2Array = []
	for y in range(height):
		for x in range(width):
			if grid[y][x]:
				opaque_points.append(Vector2(x, y))

	if opaque_points.is_empty():
		return PackedVector2Array()

	# Compute convex hull of opaque pixels
	var hull = _compute_convex_hull(opaque_points)

	# Simplify outline to reduce vertex count
	if hull.size() > 8:  # Only simplify if we have many points
		hull = _simplify_outline(hull, 1.5)

	return hull

# ==============================================================================
# CONVEX HULL ALGORITHM (Graham Scan)
# ==============================================================================

## Computes convex hull of 2D points using Graham scan algorithm
static func _compute_convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points

	# Find bottom-most point (lowest Y, then leftmost X)
	var start_idx = 0
	var start_point = points[0]
	for i in range(1, points.size()):
		var p = points[i]
		if p.y < start_point.y or (p.y == start_point.y and p.x < start_point.x):
			start_point = p
			start_idx = i

	# Sort points by polar angle relative to start point
	var sorted_points: Array = []
	for i in range(points.size()):
		if i != start_idx:
			sorted_points.append(points[i])

	sorted_points.sort_custom(func(a, b): return _polar_angle_less(a, b, start_point))

	# Graham scan
	var hull: PackedVector2Array = [start_point]

	for point in sorted_points:
		# Remove points that would create clockwise turn
		while hull.size() >= 2:
			var cross = _cross_product(hull[hull.size() - 2], hull[hull.size() - 1], point)
			if cross <= 0:  # Clockwise or collinear
				hull.remove_at(hull.size() - 1)
			else:
				break
		hull.append(point)

	return hull

## Helper: Compare polar angles for sorting
static func _polar_angle_less(a: Vector2, b: Vector2, origin: Vector2) -> bool:
	var cross = _cross_product(origin, a, b)
	if cross == 0:
		# Collinear - sort by distance
		return origin.distance_squared_to(a) < origin.distance_squared_to(b)
	return cross > 0  # Counter-clockwise

## Helper: Cross product for determining turn direction
static func _cross_product(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)

# ==============================================================================
# OUTLINE SIMPLIFICATION (Douglas-Peucker)
# ==============================================================================

## Simplifies outline using Douglas-Peucker algorithm
## Reduces vertex count while preserving shape
static func _simplify_outline(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() < 3:
		return points

	var simplified: PackedVector2Array = []
	_douglas_peucker_recursive(points, 0, points.size() - 1, epsilon, simplified)
	simplified.append(points[points.size() - 1])

	return simplified

## Recursive Douglas-Peucker implementation
static func _douglas_peucker_recursive(
	points: PackedVector2Array,
	start_idx: int,
	end_idx: int,
	epsilon: float,
	result: PackedVector2Array
) -> void:

	var max_dist = 0.0
	var max_idx = start_idx

	# Find point furthest from line segment
	for i in range(start_idx + 1, end_idx):
		var dist = _point_to_line_distance(
			points[i],
			points[start_idx],
			points[end_idx]
		)
		if dist > max_dist:
			max_dist = dist
			max_idx = i

	# If max distance exceeds epsilon, recurse
	if max_dist > epsilon:
		_douglas_peucker_recursive(points, start_idx, max_idx, epsilon, result)
		_douglas_peucker_recursive(points, max_idx, end_idx, epsilon, result)
	else:
		result.append(points[start_idx])

## Helper: Distance from point to line segment
static func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	var line_len_sq = line_vec.length_squared()

	if line_len_sq < 0.0001:
		return point_vec.length()

	var t = clampf(point_vec.dot(line_vec) / line_len_sq, 0.0, 1.0)
	var projection = line_start + t * line_vec
	return point.distance_to(projection)

# ==============================================================================
# SHAPE CREATION
# ==============================================================================

## Creates ConvexPolygonShape3D from 2D outline points
## Extrudes outline into thin 3D box
static func _create_convex_shape_2d(
	outline: PackedVector2Array,
	uv_size: Vector2,
	grid_size: float
) -> ConvexPolygonShape3D:

	var shape = ConvexPolygonShape3D.new()
	var points: PackedVector3Array = []

	var thickness = GlobalConstants.COLLISION_BOX_THICKNESS

	# Normalize coordinates to -0.5 to 0.5 range (centered at origin)
	for point in outline:
		var normalized_x = (point.x / uv_size.x) - 0.5
		var normalized_y = (point.y / uv_size.y) - 0.5

		# Scale by grid_size
		var world_x = normalized_x * grid_size
		var world_z = normalized_y * grid_size

		# Create bottom and top vertices (thin box)
		points.append(Vector3(world_x, -thickness / 2, world_z))
		points.append(Vector3(world_x, thickness / 2, world_z))

	shape.points = points
	return shape

## Creates fallback BoxShape3D for simple rectangles
static func _create_fallback_box(grid_size: float) -> BoxShape3D:
	var box = BoxShape3D.new()
	var thickness = GlobalConstants.COLLISION_BOX_THICKNESS
	box.size = Vector3(grid_size, thickness, grid_size)
	return box

## Checks if outline is a simple rectangle
static func _is_full_rectangle(outline: PackedVector2Array, uv_size: Vector2) -> bool:
	if outline.size() != 4:
		return false

	# Check if points form axis-aligned rectangle covering full UV rect
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF

	for point in outline:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)

	# Check if bounds match UV size (with small epsilon for floating point)
	var epsilon = 0.1
	return (
		abs(min_x) < epsilon and
		abs(min_y) < epsilon and
		abs(max_x - uv_size.x) < epsilon and
		abs(max_y - uv_size.y) < epsilon
	)
