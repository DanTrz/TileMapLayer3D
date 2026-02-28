@tool
class_name AlphaMeshGenerator
extends RefCounted

## Alpha-aware mesh generator using BitMap.opaque_to_polygons() + Geometry2D.triangulate_polygon().

# --- Constants ---

const ALPHA_THRESHOLD: float = 0.1
const SIMPLIFICATION_EPSILON: float = 2.0
const MIN_POLYGON_AREA: float = 16.0  # Minimum area in pixels squared

# --- Cache ---

static var _cache: Dictionary = {}

# --- Main Entry Point ---

## Generate alpha-aware mesh geometry for a tile.
## grid_size is ONLY used for transform, NOT vertex scaling.
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
		return _cache[cache_key]

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

# --- Image Extraction ---

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

# --- Bitmap Creation ---

## Create BitMap from image alpha channel
static func _create_bitmap_from_image(image: Image, threshold: float) -> BitMap:
	var bitmap: BitMap = BitMap.new()
	bitmap.create(Vector2i(image.get_width(), image.get_height()))

	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			bitmap.set_bit(x, y, pixel.a > threshold)

	return bitmap

# --- 3D Mesh Building From Polygons ---

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

# --- Helpers ---

## Calculate polygon area for filtering tiny polygons
static func _calculate_polygon_area(polygon: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = polygon.size()

	for i: int in range(n):
		var j: int = (i + 1) % n
		area += polygon[i].x * polygon[j].y
		area -= polygon[j].x * polygon[i].y

	return abs(area * 0.5)

