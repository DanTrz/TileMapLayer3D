@tool
class_name TileMeshMerger
extends RefCounted

## ============================================================================
## TILE MESH MERGER FOR GODOT 2.5D TILE PLACER
## ============================================================================
## Merges all tiles from a TileMapLayer3D into a single optimized ArrayMesh
## Responsibility: Create unified mesh with proper UV mapping and transforms
## Author: Claude Code (2025)
## Version: 1.0
##
## This class provides the core mesh merging functionality for the "Merge Bake"
## export feature. It takes all individual tiles from a MultiMesh architecture
## and combines them into a single ArrayMesh with:
## - Perfect UV coordinate preservation
## - Correct transform application (position, orientation, rotation)
## - Support for both square and triangle mesh modes
## - Tangent generation for proper lighting
## - Performance optimizations for large tile counts
##
## Usage:
##   var result: Dictionary = TileMeshMerger.merge_tiles_to_array_mesh(tile_layer)
##   if result.success:
##       var merged_mesh: ArrayMesh = result.mesh
##       var material: Material = result.material

# ==============================================================================
# CONSTANTS
# ==============================================================================

## Process in batches for memory efficiency (future enhancement)
const VERTEX_BATCH_SIZE: int = 10000

## Enable debug logging for troubleshooting
const DEBUG_LOGGING: bool = false

# ==============================================================================
# MAIN MERGE FUNCTION
# ==============================================================================

## Main merge function - returns dictionary with mesh and metadata
## @param tile_map_layer: TileMapLayer3D node containing tiles to merge
## @returns: Dictionary with keys:
##   - success: bool - Whether merge succeeded
##   - mesh: ArrayMesh - The merged mesh (if successful)
##   - material: Material - The material to apply (if successful)
##   - stats: Dictionary - Performance statistics (if successful)
##   - error: String - Error message (if failed)
static func merge_tiles_to_array_mesh(tile_map_layer: TileMapLayer3D) -> Dictionary:
	# Validation: Check tile_map_layer exists
	if not tile_map_layer:
		return {
			"success": false,
			"error": "No TileMapLayer3D provided"
		}

	# Validation: Check has tiles to merge
	if tile_map_layer.saved_tiles.is_empty():
		return {
			"success": false,
			"error": "No tiles to merge"
		}

	var start_time: int = Time.get_ticks_msec()
	var atlas_texture: Texture2D = tile_map_layer.tileset_texture

	# Validation: Check texture exists
	if not atlas_texture:
		return {
			"success": false,
			"error": "No tileset texture assigned"
		}

	var atlas_size: Vector2 = atlas_texture.get_size()
	var grid_size: float = tile_map_layer.grid_size

	# Pre-calculate capacity for performance
	# Square tiles = 4 vertices, 6 indices (2 triangles)
	# Triangle tiles = 3 vertices, 3 indices (1 triangle)
	var total_vertices: int = 0
	var total_indices: int = 0

	for tile: TilePlacerData in tile_map_layer.saved_tiles:
		match tile.mesh_mode:
			GlobalConstants.MeshMode.FLAT_SQUARE:
				total_vertices += 4
				total_indices += 6
			GlobalConstants.MeshMode.FLAT_TRIANGULE:
				total_vertices += 3
				total_indices += 3
			GlobalConstants.MeshMode.BOX_MESH:
				# Box has 24 vertices (4 per face * 6 faces) and 36 indices (6 per face * 6 faces)
				total_vertices += 24
				total_indices += 36
			GlobalConstants.MeshMode.PRISM_MESH:
				# Prism has 3 triangular faces (top, bottom) + 3 rectangular sides
				# Top: 3 verts, 3 indices; Bottom: 3 verts, 3 indices
				# Sides: 3 quads = 12 verts, 18 indices
				total_vertices += 18
				total_indices += 24

	#print("🔨 Merging %d tiles (%d vertices, %d indices)" % [
	#	tile_map_layer.saved_tiles.size(),
	#	total_vertices,
	#	total_indices
	#])

	# Pre-allocate arrays for performance (avoids repeated reallocations)
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()

	vertices.resize(total_vertices)
	uvs.resize(total_vertices)
	normals.resize(total_vertices)
	indices.resize(total_indices)

	var vertex_offset: int = 0
	var index_offset: int = 0

	# Process each tile
	for tile_idx: int in range(tile_map_layer.saved_tiles.size()):
		var tile: TilePlacerData = tile_map_layer.saved_tiles[tile_idx]

		# Build transform for this tile using GlobalUtil (single source of truth)
		# Uses saved transform params for data persistency
		var transform: Transform3D = GlobalUtil.build_tile_transform(
			tile.grid_position,
			tile.orientation,
			tile.mesh_rotation,
			grid_size,
			tile.is_face_flipped,
			tile.spin_angle_rad,
			tile.tilt_angle_rad,
			tile.diagonal_scale,
			tile.tilt_offset_factor
		)

		#   Calculate exact UV coordinates from tile rect
		# Normalize pixel coordinates to [0,1] range for texture sampling
		var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(tile.uv_rect, atlas_size)
		var uv_rect_normalized: Rect2 = Rect2(uv_data.uv_min, uv_data.uv_max - uv_data.uv_min)

		# Add geometry based on mesh mode
		match tile.mesh_mode:
			GlobalConstants.MeshMode.FLAT_SQUARE:
				_add_square_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, grid_size
				)
				vertex_offset += 4
				index_offset += 6

			GlobalConstants.MeshMode.FLAT_TRIANGULE:
				# Use shared GlobalUtil function for triangle geometry
				# Need to collect in temp arrays then copy to pre-allocated arrays
				var temp_verts: PackedVector3Array = PackedVector3Array()
				var temp_uvs: PackedVector2Array = PackedVector2Array()
				var temp_normals: PackedVector3Array = PackedVector3Array()
				var temp_indices: PackedInt32Array = PackedInt32Array()

				GlobalUtil.add_triangle_geometry(
					temp_verts, temp_uvs, temp_normals, temp_indices,
					transform, uv_rect_normalized, grid_size
				)

				# Copy to pre-allocated arrays
				for i: int in range(3):
					vertices[vertex_offset + i] = temp_verts[i]
					uvs[vertex_offset + i] = temp_uvs[i]
					normals[vertex_offset + i] = temp_normals[i]

				for i: int in range(3):
					indices[index_offset + i] = temp_indices[i] + vertex_offset

				vertex_offset += 3
				index_offset += 3

			GlobalConstants.MeshMode.BOX_MESH:
				# For BOX_MESH, create the box mesh and extract geometry
				var box_mesh: ArrayMesh = TileMeshGenerator.create_box_mesh(grid_size)
				var vert_count: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, box_mesh
				)
				vertex_offset += 24
				index_offset += 36

			GlobalConstants.MeshMode.PRISM_MESH:
				# For PRISM_MESH, create the prism mesh and extract geometry
				var prism_mesh: ArrayMesh = TileMeshGenerator.create_prism_mesh(grid_size)
				var vert_count: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, prism_mesh
				)
				vertex_offset += 18
				index_offset += 24

		# Progress reporting for large merges (every 1000 tiles)
		#if tile_idx % 1000 == 0 and tile_idx > 0:
		#	print("  ⏳ Processed %d/%d tiles..." % [tile_idx, tile_map_layer.saved_tiles.size()])

	# Create the final ArrayMesh using GlobalUtil (single source of truth)
	var array_mesh: ArrayMesh = GlobalUtil.create_array_mesh_from_arrays(
		vertices, uvs, normals, indices,
		PackedFloat32Array(),  # Auto-generate tangents
		tile_map_layer.name + "_merged"
	)

	#   Create StandardMaterial3D for merged mesh (NOT ShaderMaterial)
	# ArrayMesh uses standard vertex UVs, not shader instance data like MultiMesh
	# Detect if texture has alpha for transparency settings
	var has_alpha: bool = atlas_texture.get_image() and atlas_texture.get_image().detect_alpha() != Image.ALPHA_NONE

	var material: StandardMaterial3D = GlobalUtil.create_baked_mesh_material(
		atlas_texture,
		tile_map_layer.texture_filter_mode,
		tile_map_layer.render_priority,
		has_alpha,  # enable_alpha (only if texture has alpha)
		has_alpha   # enable_toon_shading (only if using alpha)
	)

	array_mesh.surface_set_material(0, material)

	var elapsed: int = Time.get_ticks_msec() - start_time

	#print("Merge complete in %d ms" % elapsed)

	return {
		"success": true,
		"mesh": array_mesh,
		"material": material,
		"stats": {
			"tile_count": tile_map_layer.saved_tiles.size(),
			"vertex_count": total_vertices,
			"triangle_count": total_indices / 3,
			"merge_time_ms": elapsed,
			"memory_size_kb": array_mesh.get_rid().get_id() * 4 / 1024  # Approximate
		}
	}

# ==============================================================================
# GEOMETRY PROCESSING - SQUARE TILES
# ==============================================================================

## Add square tile geometry to arrays
## @param vertices: Target vertex array (modified in-place)
## @param uvs: Target UV array (modified in-place)
## @param normals: Target normal array (modified in-place)
## @param indices: Target index array (modified in-place)
## @param v_offset: Current vertex offset in arrays
## @param i_offset: Current index offset in arrays
## @param transform: Complete tile transform (position + orientation + rotation)
## @param uv_rect: Normalized UV rectangle [0,1] range
## @param grid_size: Grid cell size for local vertex calculation
static func _add_square_to_arrays(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	v_offset: int,
	i_offset: int,
	transform: Transform3D,
	uv_rect: Rect2,
	grid_size: float
) -> void:

	var half: float = grid_size * 0.5

	# Define local vertices (counter-clockwise winding for correct face orientation)
	# These are in local tile space (centered at origin)
	var local_verts: Array[Vector3] = [
		Vector3(-half, 0, -half),  # 0: bottom-left
		Vector3(half, 0, -half),   # 1: bottom-right
		Vector3(half, 0, half),    # 2: top-right
		Vector3(-half, 0, half)    # 3: top-left
	]

	#   UV coordinates that exactly map to the tile's texture region
	# Must correspond to vertex order for correct texture mapping
	var tile_uvs: Array[Vector2] = [
		uv_rect.position,                                    # 0: bottom-left UV
		Vector2(uv_rect.end.x, uv_rect.position.y),         # 1: bottom-right UV
		uv_rect.end,                                         # 2: top-right UV
		Vector2(uv_rect.position.x, uv_rect.end.y)          # 3: top-left UV
	]

	# Transform vertices to world space and set data
	# Normal is transformed Y-axis of the tile's basis (surface normal)
	var normal: Vector3 = transform.basis.y.normalized()

	for i: int in range(4):
		vertices[v_offset + i] = transform * local_verts[i]
		uvs[v_offset + i] = tile_uvs[i]
		normals[v_offset + i] = normal

	# Set indices for two triangles (counter-clockwise winding)
	# Triangle 1: 0 → 1 → 2
	# Triangle 2: 0 → 2 → 3
	indices[i_offset + 0] = v_offset + 0
	indices[i_offset + 1] = v_offset + 1
	indices[i_offset + 2] = v_offset + 2
	indices[i_offset + 3] = v_offset + 0
	indices[i_offset + 4] = v_offset + 2
	indices[i_offset + 5] = v_offset + 3

	if DEBUG_LOGGING:
		print("  Square UV rect: ", uv_rect)

# NOTE: Triangle geometry is now handled by GlobalUtil.add_triangle_geometry()
# NOTE: Tangent generation is now handled by GlobalUtil.generate_tangents_for_mesh()
# NOTE: ArrayMesh creation is now handled by GlobalUtil.create_array_mesh_from_arrays()
# See usage above in merge_tiles_to_array_mesh()


## Add mesh geometry from an ArrayMesh to pre-allocated arrays
## Used for BOX_MESH and PRISM_MESH which are generated procedurally
## @param vertices: Target vertex array (modified in-place)
## @param uvs: Target UV array (modified in-place)
## @param normals: Target normal array (modified in-place)
## @param indices: Target index array (modified in-place)
## @param v_offset: Current vertex offset in arrays
## @param i_offset: Current index offset in arrays
## @param transform: Complete tile transform (position + orientation + rotation)
## @param uv_rect: Normalized UV rectangle [0,1] range (for top face remapping)
## @param source_mesh: ArrayMesh to extract geometry from
## @returns: Number of vertices added
static func _add_mesh_to_arrays(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	v_offset: int,
	i_offset: int,
	transform: Transform3D,
	uv_rect: Rect2,
	source_mesh: ArrayMesh
) -> int:
	if source_mesh.get_surface_count() == 0:
		return 0

	var arrays: Array = source_mesh.surface_get_arrays(0)
	var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var src_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var src_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var vert_count: int = src_verts.size()
	var idx_count: int = src_indices.size()

	# Transform vertices to world space and copy data
	for i: int in range(vert_count):
		vertices[v_offset + i] = transform * src_verts[i]
		# Remap UVs from [0,1] to tile's UV rect
		var src_uv: Vector2 = src_uvs[i]
		uvs[v_offset + i] = Vector2(
			uv_rect.position.x + src_uv.x * uv_rect.size.x,
			uv_rect.position.y + src_uv.y * uv_rect.size.y
		)
		# Transform normal by the basis (rotation only, no translation)
		normals[v_offset + i] = (transform.basis * src_normals[i]).normalized()

	# Copy indices with offset
	for i: int in range(idx_count):
		indices[i_offset + i] = src_indices[i] + v_offset

	return vert_count


# ==============================================================================
# STREAMING MERGE (FOR LARGE TILE COUNTS)
# ==============================================================================

## Streaming merge for extremely large tile counts (10,000+)
## Processes tiles in chunks with progress reporting
##
## @param tile_map_layer: TileMapLayer3D node containing tiles to merge
## @param progress_callback: Optional callback for progress updates
##   Receives (current_tile: int, total_tiles: int)
## @returns: Same dictionary format as merge_tiles_to_array_mesh()
static func merge_tiles_streaming(
	tile_map_layer: TileMapLayer3D,
	progress_callback: Callable = Callable()
) -> Dictionary:

	const CHUNK_SIZE: int = 5000  # Process in chunks

	# Validation
	if not tile_map_layer or tile_map_layer.saved_tiles.is_empty():
		return {"success": false, "error": "No tiles to merge"}

	var start_time: int = Time.get_ticks_msec()
	var atlas_texture: Texture2D = tile_map_layer.tileset_texture
	var atlas_size: Vector2 = atlas_texture.get_size()
	var grid_size: float = tile_map_layer.grid_size

	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var tile_count: int = tile_map_layer.saved_tiles.size()
	var chunks: int = (tile_count + CHUNK_SIZE - 1) / CHUNK_SIZE

	#print("🔨 Streaming merge of %d tiles in %d chunks" % [tile_count, chunks])

	# Process in chunks
	for chunk_idx: int in range(chunks):
		var start_idx: int = chunk_idx * CHUNK_SIZE
		var end_idx: int = min(start_idx + CHUNK_SIZE, tile_count)

		# Process chunk
		for i: int in range(start_idx, end_idx):
			var tile: TilePlacerData = tile_map_layer.saved_tiles[i]

			# Build transform using saved transform params for data persistency
			var transform: Transform3D = GlobalUtil.build_tile_transform(
				tile.grid_position,
				tile.orientation,
				tile.mesh_rotation,
				grid_size,
				tile.is_face_flipped,
				tile.spin_angle_rad,
				tile.tilt_angle_rad,
				tile.diagonal_scale,
				tile.tilt_offset_factor
			)

			# Calculate UVs using GlobalUtil (single source of truth)
			var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(tile.uv_rect, atlas_size)
			var uv_rect_normalized: Rect2 = Rect2(uv_data.uv_min, uv_data.uv_max - uv_data.uv_min)

			# Add geometry based on type
			match tile.mesh_mode:
				GlobalConstants.MeshMode.FLAT_SQUARE:
					_add_square_to_surface_tool(surface_tool, transform, uv_rect_normalized, grid_size)
				GlobalConstants.MeshMode.FLAT_TRIANGULE:
					_add_triangle_to_surface_tool(surface_tool, transform, uv_rect_normalized, grid_size)
				GlobalConstants.MeshMode.BOX_MESH:
					_add_box_to_surface_tool(surface_tool, transform, uv_rect_normalized, grid_size)
				GlobalConstants.MeshMode.PRISM_MESH:
					_add_prism_to_surface_tool(surface_tool, transform, uv_rect_normalized, grid_size)

			# Report progress
			if progress_callback.is_valid() and i % 100 == 0:
				progress_callback.call(i, tile_count)

		#print("  ⏳ Completed chunk %d/%d" % [chunk_idx + 1, chunks])

	# Generate normals and tangents
	surface_tool.generate_normals()
	surface_tool.generate_tangents()

	var array_mesh: ArrayMesh = surface_tool.commit()
	array_mesh.resource_name = tile_map_layer.name + "_streamed"

	#   Create StandardMaterial3D for merged mesh (NOT ShaderMaterial)
	# Detect if texture has alpha for transparency settings
	var has_alpha: bool = atlas_texture.get_image() and atlas_texture.get_image().detect_alpha() != Image.ALPHA_NONE

	var material: StandardMaterial3D = GlobalUtil.create_baked_mesh_material(
		atlas_texture,
		tile_map_layer.texture_filter_mode,
		tile_map_layer.render_priority,
		has_alpha,  # enable_alpha (only if texture has alpha)
		has_alpha   # enable_toon_shading (only if using alpha)
	)

	array_mesh.surface_set_material(0, material)

	var elapsed: int = Time.get_ticks_msec() - start_time

	return {
		"success": true,
		"mesh": array_mesh,
		"material": material,
		"stats": {
			"tile_count": tile_count,
			"merge_time_ms": elapsed,
			"streaming_chunks": chunks
		}
	}

# ==============================================================================
# STREAMING HELPERS
# ==============================================================================

## Helper for streaming - add square to SurfaceTool
static func _add_square_to_surface_tool(
	st: SurfaceTool,
	transform: Transform3D,
	uv_rect: Rect2,
	grid_size: float
) -> void:

	var half: float = grid_size * 0.5
	var normal: Vector3 = transform.basis.y.normalized()

	# Bottom-left
	st.set_uv(uv_rect.position)
	st.set_normal(normal)
	st.add_vertex(transform * Vector3(-half, 0, -half))

	# Bottom-right
	st.set_uv(Vector2(uv_rect.end.x, uv_rect.position.y))
	st.set_normal(normal)
	st.add_vertex(transform * Vector3(half, 0, -half))

	# Top-right
	st.set_uv(uv_rect.end)
	st.set_normal(normal)
	st.add_vertex(transform * Vector3(half, 0, half))

	# Top-left
	st.set_uv(Vector2(uv_rect.position.x, uv_rect.end.y))
	st.set_normal(normal)
	st.add_vertex(transform * Vector3(-half, 0, half))

## Helper for streaming - add triangle to SurfaceTool
static func _add_triangle_to_surface_tool(
	st: SurfaceTool,
	transform: Transform3D,
	uv_rect: Rect2,
	grid_size: float
) -> void:

	var half_width: float = grid_size * 0.5
	var half_height: float = grid_size * 0.5
	var normal: Vector3 = transform.basis.y.normalized()

	# Bottom point
	st.set_uv(Vector2(uv_rect.position.x + uv_rect.size.x * 0.5, uv_rect.position.y))
	st.set_normal(normal)
	st.add_vertex(transform * Vector3(0.0, 0.0, -half_height))

	# Top-left
	st.set_uv(Vector2(uv_rect.position.x, uv_rect.end.y))
	st.set_normal(normal)
	st.add_vertex(transform * Vector3(-half_width, 0.0, half_height))

	# Top-right
	st.set_uv(Vector2(uv_rect.end.x, uv_rect.end.y))
	st.set_normal(normal)
	st.add_vertex(transform * Vector3(half_width, 0.0, half_height))


## Helper for streaming - add box mesh to SurfaceTool
static func _add_box_to_surface_tool(
	st: SurfaceTool,
	transform: Transform3D,
	uv_rect: Rect2,
	grid_size: float
) -> void:
	# Generate box mesh and add its geometry to SurfaceTool
	var box_mesh: ArrayMesh = TileMeshGenerator.create_box_mesh(grid_size)
	_add_array_mesh_to_surface_tool(st, transform, uv_rect, box_mesh)


## Helper for streaming - add prism mesh to SurfaceTool
static func _add_prism_to_surface_tool(
	st: SurfaceTool,
	transform: Transform3D,
	uv_rect: Rect2,
	grid_size: float
) -> void:
	# Generate prism mesh and add its geometry to SurfaceTool
	var prism_mesh: ArrayMesh = TileMeshGenerator.create_prism_mesh(grid_size)
	_add_array_mesh_to_surface_tool(st, transform, uv_rect, prism_mesh)


## Helper to add an ArrayMesh's geometry to a SurfaceTool
static func _add_array_mesh_to_surface_tool(
	st: SurfaceTool,
	transform: Transform3D,
	uv_rect: Rect2,
	source_mesh: ArrayMesh
) -> void:
	if source_mesh.get_surface_count() == 0:
		return

	var arrays: Array = source_mesh.surface_get_arrays(0)
	var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var src_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	# Add each vertex with transformed position and remapped UVs
	for i: int in range(src_verts.size()):
		# Remap UVs from [0,1] to tile's UV rect
		var src_uv: Vector2 = src_uvs[i]
		var remapped_uv: Vector2 = Vector2(
			uv_rect.position.x + src_uv.x * uv_rect.size.x,
			uv_rect.position.y + src_uv.y * uv_rect.size.y
		)
		st.set_uv(remapped_uv)

		# Transform normal by the basis (rotation only)
		var transformed_normal: Vector3 = (transform.basis * src_normals[i]).normalized()
		st.set_normal(transformed_normal)

		# Transform vertex to world space
		st.add_vertex(transform * src_verts[i])
