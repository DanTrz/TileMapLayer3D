@tool
class_name AlphaMeshGenerator
extends RefCounted

## Alpha-aware mesh generator using Godot's BitMap API
## Generates optimized mesh geometry that excludes transparent pixels
## Author: Claude Code (2025)
## Algorithm: BitMap.opaque_to_polygons() + Geometry2D.triangulate_polygon()

# ==============================================================================
# CONSTANTS
# ==============================================================================

const ALPHA_THRESHOLD: float = 0.1
const SIMPLIFICATION_EPSILON: float = 2.0
const MIN_POLYGON_AREA: float = 16.0  # Minimum area in pixels squared

# ==============================================================================
# CACHE
# ==============================================================================

static var _cache: Dictionary = {}
static var _cache_hits: int = 0
static var _cache_misses: int = 0

# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================

## Generate alpha-aware mesh geometry for a tile
## @param texture: Atlas texture
## @param uv_rect: Tile region in pixel coordinates
## @param grid_size: World size of tile (ONLY used for transform, NOT vertex scaling)
## @param alpha_threshold: Pixels with alpha <= threshold are transparent
## @param epsilon: Simplification factor (higher = fewer vertices)
## @returns: Dictionary with success, vertices, uvs, normals, indices, stats
static func generate_alpha_mesh(
	texture: Texture2D,
	uv_rect: Rect2,
	grid_size: float,
	alpha_threshold: float = ALPHA_THRESHOLD,
	epsilon: float = SIMPLIFICATION_EPSILON
) -> Dictionary:

	# Check cache
	var cache_key: String = "%d_%d_%d_%d" % [
		int(uv_rect.position.x),
		int(uv_rect.position.y),
		int(uv_rect.size.x),
		int(uv_rect.size.y)
	]

	if _cache.has(cache_key):
		_cache_hits += 1
		return _cache[cache_key]

	_cache_misses += 1

	# Step 1: Extract tile region
	var tile_image: Image = _extract_tile_region(texture, uv_rect)
	if not tile_image:
		return {"success": false, "error": "Failed to extract tile region"}

	var tile_width: int = tile_image.get_width()
	var tile_height: int = tile_image.get_height()

	# Step 2: Create BitMap from alpha channel
	var bitmap: BitMap = _create_bitmap_from_image(tile_image, alpha_threshold)

	# Step 3: Extract polygons using BitMap API (does Moore neighborhood + Marching Squares)
	var polygons: Array[PackedVector2Array] = bitmap.opaque_to_polygons(
		Rect2i(0, 0, tile_width, tile_height),
		epsilon
	)

	if polygons.is_empty():
		var empty_result: Dictionary = {
			"success": true,
			"vertices": PackedVector3Array(),
			"uvs": PackedVector2Array(),
			"normals": PackedVector3Array(),
			"indices": PackedInt32Array(),
			"vertex_count": 0,
			"triangle_count": 0
		}
		_cache[cache_key] = empty_result
		return empty_result

	# Step 4: Build 3D mesh from polygons
	var result: Dictionary = _build_3d_mesh_from_polygons(
		polygons,
		uv_rect,
		texture.get_size(),
		grid_size
	)

	# Cache result
	_cache[cache_key] = result

	return result

# ==============================================================================
# IMAGE EXTRACTION
# ==============================================================================

## Extract tile region from atlas texture
static func _extract_tile_region(texture: Texture2D, uv_rect: Rect2) -> Image:
	var atlas_image: Image = texture.get_image()
	if not atlas_image:
		push_error("Cannot get image from texture")
		return null

	# Decompress if needed (for get_region)
	if atlas_image.is_compressed():
		atlas_image.decompress()

	# Extract tile region
	var tile_image: Image = atlas_image.get_region(uv_rect)

	return tile_image

# ==============================================================================
# BITMAP CREATION
# ==============================================================================

## Create BitMap from image alpha channel
static func _create_bitmap_from_image(image: Image, threshold: float) -> BitMap:
	var bitmap: BitMap = BitMap.new()
	bitmap.create(Vector2i(image.get_width(), image.get_height()))

	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			bitmap.set_bit(x, y, pixel.a > threshold)

	return bitmap

# ==============================================================================
# 3D MESH BUILDING FROM POLYGONS
# ==============================================================================

## Build 3D mesh from 2D polygons
static func _build_3d_mesh_from_polygons(
	polygons: Array[PackedVector2Array],
	uv_rect: Rect2,
	atlas_size: Vector2,
	grid_size: float
) -> Dictionary:

	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()

	var total_triangles: int = 0

	for polygon: PackedVector2Array in polygons:
		if polygon.size() < 3:
			continue

		# Filter out tiny polygons
		var area: float = _calculate_polygon_area(polygon)
		if area < MIN_POLYGON_AREA:
			continue

		# Triangulate using Godot's built-in Delaunay triangulation
		var triangulated: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)

		if triangulated.is_empty():
			continue

		# Add vertices
		var vertex_offset: int = vertices.size()

		for point: Vector2 in polygon:
			# Normalize to [0-1] within tile (point is in pixel coords 0-48)
			var norm: Vector2 = Vector2(
				point.x / uv_rect.size.x,
				point.y / uv_rect.size.y
			)

			#   Convert to LOCAL 3D space (centered at origin)
			# Do NOT apply grid_size here - that's done by transform in plugin
			var pos_3d: Vector3 = Vector3(
				(norm.x - 0.5) * grid_size,
				0.0,
				(norm.y - 0.5) * grid_size
			)
			vertices.append(pos_3d)

			# Calculate UV coordinate in atlas
			var uv: Vector2 = (uv_rect.position + point) / atlas_size
			uvs.append(uv)

			# Normal pointing up
			normals.append(Vector3.UP)

		# Add triangle indices with offset
		for idx: int in triangulated:
			indices.append(vertex_offset + idx)

		total_triangles += triangulated.size() / 3

	return {
		"success": true,
		"vertices": vertices,
		"uvs": uvs,
		"normals": normals,
		"indices": indices,
		"vertex_count": vertices.size(),
		"triangle_count": total_triangles
	}

# ==============================================================================
# HELPERS
# ==============================================================================

## Calculate polygon area for filtering tiny polygons
static func _calculate_polygon_area(polygon: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = polygon.size()

	for i: int in range(n):
		var j: int = (i + 1) % n
		area += polygon[i].x * polygon[j].y
		area -= polygon[j].x * polygon[i].y

	return abs(area * 0.5)

# ==============================================================================
# CACHE MANAGEMENT
# ==============================================================================

## Clear geometry cache
static func clear_cache() -> void:
	_cache.clear()
	_cache_hits = 0
	_cache_misses = 0

## Get cache statistics
static func get_cache_stats() -> Dictionary:
	var total: int = _cache_hits + _cache_misses
	var hit_rate: float = (float(_cache_hits) / float(total) * 100.0) if total > 0 else 0.0

	return {
		"total_entries": _cache.size(),
		"hits": _cache_hits,
		"misses": _cache_misses,
		"hit_rate": hit_rate
	}
