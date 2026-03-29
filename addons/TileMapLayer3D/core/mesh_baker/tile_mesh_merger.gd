@tool
class_name TileMeshMerger
extends RefCounted

## Merges all tiles from a TileMapLayer3D into a single optimized ArrayMesh.

# --- Constants ---

## Enable debug logging for troubleshooting
const DEBUG_LOGGING: bool = false

# --- Unified Entry Point ---

## Main entry point for all mesh baking operations.
## This is the SINGLE function that should be called for baking.
static func merge_tiles(
	tile_map_layer: TileMapLayer3D,
	options: Dictionary = {}
) -> Dictionary:
	var alpha_aware: bool = options.get("alpha_aware", false)

	if alpha_aware:
		return _merge_alpha_aware(tile_map_layer)
	else:
		return merge_tiles_to_array_mesh(tile_map_layer)

# --- Main Merge Function ---

## Main merge function - returns dictionary with mesh and metadata.
static func merge_tiles_to_array_mesh(tile_map_layer: TileMapLayer3D) -> Dictionary:
	# Validation: Check tile_map_layer exists
	if not tile_map_layer:
		return {
			"success": false,
			"error": "No TileMapLayer3D provided"
		}

	# Validation: Check has tiles to merge (columnar OR vertex-edited)
	if tile_map_layer.get_tile_count() == 0 and tile_map_layer.get_vertex_tile_corners().is_empty():
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

	for i in range(tile_map_layer.get_tile_count()):
		var tile_data: Dictionary = tile_map_layer.get_tile_data_at(i)
		if tile_data.is_empty():
			continue
		match tile_data["mesh_mode"]:
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
				# Prism: Top triangle (3 verts) + Bottom triangle (3 verts)
				# + 3 side quads (6 verts each = 18 verts, 2 triangles each = 18 indices)
				# Total: 24 vertices, 24 indices (8 triangles)
				total_vertices += 24
				total_indices += 24

	# Add capacity for vertex-edited tiles (each is a quad: 4 verts, 6 indices)
	var vertex_tile_dict: Dictionary = tile_map_layer.get_vertex_tile_corners()
	var vertex_tile_count: int = vertex_tile_dict.size()
	total_vertices += vertex_tile_count * 4
	total_indices += vertex_tile_count * 6

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
	for tile_idx: int in range(tile_map_layer.get_tile_count()):
		var tile_data: Dictionary = tile_map_layer.get_tile_data_at(tile_idx)
		if tile_data.is_empty():
			continue

		# Check for custom transform (ramp/smart fill tiles bypass standard orientation)
		var transform: Transform3D
		if tile_data.has("custom_transform"):
			transform = tile_data["custom_transform"]
		else:
			# Build transform for this tile using GlobalUtil (single source of truth)
			# Uses saved transform params for data persistency
			# Passes mesh_mode and depth_scale for proper BOX/PRISM scaling
			transform = GlobalUtil.build_tile_transform(
				tile_data["grid_position"],
				tile_data["orientation"],
				tile_data["mesh_rotation"],
				grid_size,
				tile_data["is_face_flipped"],
				tile_data["spin_angle_rad"],
				tile_data["tilt_angle_rad"],
				tile_data["diagonal_scale"],
				tile_data["tilt_offset_factor"],
				tile_data["mesh_mode"],
				tile_data["depth_scale"]
			)

		#   Calculate exact UV coordinates from tile rect
		# Normalize pixel coordinates to [0,1] range for texture sampling
		var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(tile_data["uv_rect"], atlas_size)
		var uv_rect_normalized: Rect2 = Rect2(uv_data.uv_min, uv_data.uv_max - uv_data.uv_min)

		# Add geometry based on mesh mode
		# Pass mesh_rotation and is_face_flipped for correct UV transformation
		match tile_data["mesh_mode"]:
			GlobalConstants.MeshMode.FLAT_SQUARE:
				_add_square_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, grid_size,
					tile_data["mesh_rotation"], tile_data["is_face_flipped"]
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

				# Copy to pre-allocated arrays - UVs are already in atlas space from add_triangle_geometry
				# No transform_uv_for_baking needed (matches alpha-aware mode behavior)
				for i: int in range(3):
					vertices[vertex_offset + i] = temp_verts[i]
					uvs[vertex_offset + i] = temp_uvs[i]
					normals[vertex_offset + i] = temp_normals[i]

				for i: int in range(3):
					indices[index_offset + i] = temp_indices[i] + vertex_offset

				vertex_offset += 3
				index_offset += 3

			GlobalConstants.MeshMode.BOX_MESH:
				# For BOX_MESH, create base mesh - depth_scale is applied via transform
				# Use texture_repeat_mode to select correct UV mapping (DEFAULT=stripes, REPEAT=full)
				var box_mesh: ArrayMesh
				if tile_data["texture_repeat_mode"] == GlobalConstants.TextureRepeatMode.REPEAT:
					box_mesh = TileMeshGenerator.create_box_mesh_repeat(grid_size)
				else:
					box_mesh = TileMeshGenerator.create_box_mesh(grid_size)
				var vert_count: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, box_mesh,
					tile_data["mesh_rotation"], tile_data["is_face_flipped"]
				)
				vertex_offset += 24
				index_offset += 36

			GlobalConstants.MeshMode.PRISM_MESH:
				# For PRISM_MESH, create base mesh - depth_scale is applied via transform
				# Use texture_repeat_mode to select correct UV mapping (DEFAULT=stripes, REPEAT=full)
				var prism_mesh: ArrayMesh
				if tile_data["texture_repeat_mode"] == GlobalConstants.TextureRepeatMode.REPEAT:
					prism_mesh = TileMeshGenerator.create_prism_mesh_repeat(grid_size)
				else:
					prism_mesh = TileMeshGenerator.create_prism_mesh(grid_size)
				var vert_count: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, prism_mesh,
					tile_data["mesh_rotation"], tile_data["is_face_flipped"]
				)
				vertex_offset += 24
				index_offset += 24

		# Progress reporting for large merges (every 1000 tiles)
		#if tile_idx % 1000 == 0 and tile_idx > 0:
		#	print("  ⏳ Processed %d/%d tiles..." % [tile_idx, tile_map_layer.saved_tiles.size()])

	# Process vertex-edited tiles (stored separately from columnar data)
	if not vertex_tile_dict.is_empty():
		var node_inv: Transform3D = tile_map_layer.global_transform.affine_inverse()

		for tile_key: int in vertex_tile_dict.keys():
			var entry: Dictionary = vertex_tile_dict[tile_key]
			var corners: PackedVector3Array = entry.get("corners", PackedVector3Array())
			if corners.size() != 4:
				continue

			# Convert world-space corners to local-space
			var local_corners: PackedVector3Array = PackedVector3Array()
			for corner: Vector3 in corners:
				local_corners.append(node_inv * corner)

			# Normalize UV rect
			var uv_rect: Rect2 = entry.get("uv_rect", Rect2())
			var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
			var uv_rect_normalized: Rect2 = Rect2(uv_data.uv_min, uv_data.uv_max - uv_data.uv_min)

			_add_vertex_quad_to_arrays(
				vertices, uvs, normals, indices,
				vertex_offset, index_offset,
				local_corners, uv_rect_normalized
			)
			vertex_offset += 4
			index_offset += 6

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
			"tile_count": tile_map_layer.get_tile_count() + vertex_tile_count,
			"vertex_count": total_vertices,
			"triangle_count": total_indices / 3,
			"merge_time_ms": elapsed
		}
	}

# --- Geometry Processing ---

## Add square tile geometry to pre-allocated arrays.
static func _add_square_to_arrays(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	v_offset: int,
	i_offset: int,
	transform: Transform3D,
	uv_rect: Rect2,
	grid_size: float,
	mesh_rotation: int = 0,
	is_face_flipped: bool = false
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

	# Local UV coordinates in [0,1] space for each vertex
	# These will be transformed based on rotation/flip, then remapped to uv_rect
	var local_uvs: Array[Vector2] = [
		Vector2(0.0, 0.0),  # 0: bottom-left
		Vector2(1.0, 0.0),  # 1: bottom-right
		Vector2(1.0, 1.0),  # 2: top-right
		Vector2(0.0, 1.0)   # 3: top-left
	]

	# Transform vertices to world space and set data
	# Normal is transformed Y-axis of the tile's basis (surface normal)
	var normal: Vector3 = transform.basis.y.normalized()

	for i: int in range(4):
		vertices[v_offset + i] = transform * local_verts[i]
		# Apply rotation/flip directly (no Y-flip for flat tiles - matches alpha-aware mode)
		var final_uv: Vector2 = local_uvs[i]
		if is_face_flipped:
			final_uv.x = 1.0 - final_uv.x
		match mesh_rotation:
			1:  # 90° CCW
				final_uv = Vector2(final_uv.y, 1.0 - final_uv.x)
			2:  # 180°
				final_uv = Vector2(1.0 - final_uv.x, 1.0 - final_uv.y)
			3:  # 270° CCW
				final_uv = Vector2(1.0 - final_uv.y, final_uv.x)
		uvs[v_offset + i] = Vector2(
			uv_rect.position.x + final_uv.x * uv_rect.size.x,
			uv_rect.position.y + final_uv.y * uv_rect.size.y
		)
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


## Add vertex-edited tile quad geometry to pre-allocated arrays.
## Vertex tiles have arbitrary corners (not transform-derived), so this takes
## local-space corners directly instead of a Transform3D + grid_size.
## Corner order: [BL, BR, TR, TL] — matches build_vertex_tile_mesh() convention.
static func _add_vertex_quad_to_arrays(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	v_offset: int,
	i_offset: int,
	local_corners: PackedVector3Array,
	uv_rect_normalized: Rect2
) -> void:
	# Write corner positions directly
	for i: int in range(4):
		vertices[v_offset + i] = local_corners[i]

	# UV mapping: matches _add_square_to_arrays convention
	# corner[0]=BL(-X,-Z) → top-left, corner[2]=TR(+X,+Z) → bottom-right
	var uv_min: Vector2 = uv_rect_normalized.position
	var uv_max: Vector2 = uv_rect_normalized.position + uv_rect_normalized.size
	uvs[v_offset + 0] = Vector2(uv_min.x, uv_min.y)  # BL → top-left of texture
	uvs[v_offset + 1] = Vector2(uv_max.x, uv_min.y)  # BR → top-right of texture
	uvs[v_offset + 2] = Vector2(uv_max.x, uv_max.y)  # TR → bottom-right of texture
	uvs[v_offset + 3] = Vector2(uv_min.x, uv_max.y)  # TL → bottom-left of texture

	# Normal: edge2 × edge1 gives correct outward-facing direction (+Y for floor tiles)
	var edge1: Vector3 = local_corners[1] - local_corners[0]
	var edge2: Vector3 = local_corners[3] - local_corners[0]
	var normal: Vector3 = edge2.cross(edge1).normalized()
	if normal.is_zero_approx():
		normal = Vector3.UP  # Fallback for degenerate quads
	for i: int in range(4):
		normals[v_offset + i] = normal

	# Two triangles: [0,1,2] and [0,2,3]
	indices[i_offset + 0] = v_offset + 0
	indices[i_offset + 1] = v_offset + 1
	indices[i_offset + 2] = v_offset + 2
	indices[i_offset + 3] = v_offset + 0
	indices[i_offset + 4] = v_offset + 2
	indices[i_offset + 5] = v_offset + 3


## Add geometry from a procedural ArrayMesh (BOX_MESH/PRISM_MESH) to pre-allocated arrays.
static func _add_mesh_to_arrays(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	v_offset: int,
	i_offset: int,
	transform: Transform3D,
	uv_rect: Rect2,
	source_mesh: ArrayMesh,
	mesh_rotation: int = 0,
	is_face_flipped: bool = false
) -> int:
	if source_mesh.get_surface_count() == 0:
		return 0

	var arrays: Array = source_mesh.surface_get_arrays(0)
	var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var src_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	# Handle meshes without explicit indices (e.g., SurfaceTool without add_index calls)
	var src_indices_raw = arrays[Mesh.ARRAY_INDEX]
	var src_indices: PackedInt32Array
	if src_indices_raw != null:
		src_indices = src_indices_raw
	else:
		# Generate sequential indices for non-indexed meshes
		src_indices = PackedInt32Array()
		src_indices.resize(src_verts.size())
		for i: int in range(src_verts.size()):
			src_indices[i] = i

	var vert_count: int = src_verts.size()
	var idx_count: int = src_indices.size()

	# Transform vertices to world space and copy data
	for i: int in range(vert_count):
		vertices[v_offset + i] = transform * src_verts[i]
		# Transform UV based on rotation/flip, then remap to tile's UV rect
		var src_uv: Vector2 = src_uvs[i]
		var transformed_uv: Vector2 = GlobalUtil.transform_uv_for_baking(src_uv, mesh_rotation, is_face_flipped)
		uvs[v_offset + i] = Vector2(
			uv_rect.position.x + transformed_uv.x * uv_rect.size.x,
			uv_rect.position.y + transformed_uv.y * uv_rect.size.y
		)
		# Transform normal by the basis (rotation only, no translation)
		normals[v_offset + i] = (transform.basis * src_normals[i]).normalized()

	# Copy indices with offset
	for i: int in range(idx_count):
		indices[i_offset + i] = src_indices[i] + v_offset

	return vert_count


# --- Alpha-Aware Merge ---

## Alpha-aware baking: excludes transparent pixels using AlphaMeshGenerator.
static func _merge_alpha_aware(tile_map_layer: TileMapLayer3D) -> Dictionary:
	var start_time: int = Time.get_ticks_msec()

	# Get atlas texture
	var atlas_texture: Texture2D = tile_map_layer.tileset_texture
	if not atlas_texture:
		return {"success": false, "error": "No tileset texture"}

	var atlas_size: Vector2 = atlas_texture.get_size()
	var grid_size: float = tile_map_layer.grid_size

	# Pre-allocate arrays
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()

	var tiles_processed: int = 0
	var total_vertices: int = 0

	# Process each tile
	for tile_idx: int in range(tile_map_layer.get_tile_count()):
		var tile_data: Dictionary = tile_map_layer.get_tile_data_at(tile_idx)
		if tile_data.is_empty():
			continue

		# Check for custom transform (ramp/smart fill tiles bypass standard orientation)
		var transform: Transform3D
		if tile_data.has("custom_transform"):
			transform = tile_data["custom_transform"]
		else:
			# Build transform using saved transform params for data persistency
			# Passes mesh_mode and depth_scale for proper BOX/PRISM scaling
			transform = GlobalUtil.build_tile_transform(
				tile_data["grid_position"],
				tile_data["orientation"],
				tile_data["mesh_rotation"],
				grid_size,
				tile_data["is_face_flipped"],
				tile_data["spin_angle_rad"],
				tile_data["tilt_angle_rad"],
				tile_data["diagonal_scale"],
				tile_data["tilt_offset_factor"],
				tile_data["mesh_mode"],
				tile_data["depth_scale"]
			)

		# Normalize UV rect using GlobalUtil (single source of truth)
		var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(tile_data["uv_rect"], atlas_size)
		var uv_rect_normalized: Rect2 = Rect2(uv_data.uv_min, uv_data.uv_max - uv_data.uv_min)

		match tile_data["mesh_mode"]:
			GlobalConstants.MeshMode.FLAT_TRIANGULE:
				# Add standard triangle geometry using shared utility
				GlobalUtil.add_triangle_geometry(
					vertices, uvs, normals, indices,
					transform, uv_rect_normalized, grid_size
				)
				tiles_processed += 1
				total_vertices += 3

			GlobalConstants.MeshMode.BOX_MESH:
				# Use full box mesh (same as regular merge) - includes all 6 faces
				# This ensures proper collision and baked mesh generation
				# depth_scale is applied via transform, not mesh generation
				# Use texture_repeat_mode to select correct UV mapping
				var box_mesh: ArrayMesh
				if tile_data["texture_repeat_mode"] == GlobalConstants.TextureRepeatMode.REPEAT:
					box_mesh = TileMeshGenerator.create_box_mesh_repeat(grid_size)
				else:
					box_mesh = TileMeshGenerator.create_box_mesh(grid_size)
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				# Extend arrays for box geometry (24 vertices, 36 indices)
				vertices.resize(v_offset + 24)
				uvs.resize(v_offset + 24)
				normals.resize(v_offset + 24)
				indices.resize(i_offset + 36)

				_add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, box_mesh,
					tile_data["mesh_rotation"], tile_data["is_face_flipped"]
				)

				tiles_processed += 1
				total_vertices += 24

			GlobalConstants.MeshMode.PRISM_MESH:
				# Use full prism mesh (same as regular merge) - includes all faces
				# This ensures proper collision and baked mesh generation
				# depth_scale is applied via transform, not mesh generation
				# Use texture_repeat_mode to select correct UV mapping
				var prism_mesh: ArrayMesh
				if tile_data["texture_repeat_mode"] == GlobalConstants.TextureRepeatMode.REPEAT:
					prism_mesh = TileMeshGenerator.create_prism_mesh_repeat(grid_size)
				else:
					prism_mesh = TileMeshGenerator.create_prism_mesh(grid_size)
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				# Extend arrays for prism geometry (24 vertices, 24 indices)
				vertices.resize(v_offset + 24)
				uvs.resize(v_offset + 24)
				normals.resize(v_offset + 24)
				indices.resize(i_offset + 24)

				_add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, prism_mesh,
					tile_data["mesh_rotation"], tile_data["is_face_flipped"]
				)

				tiles_processed += 1
				total_vertices += 24

			GlobalConstants.MeshMode.FLAT_SQUARE, _:
				# Generate alpha-aware geometry using BitMap API (for square tiles)
				var geom: Dictionary = AlphaMeshGenerator.generate_alpha_mesh(
					atlas_texture,
					tile_data["uv_rect"],
					grid_size,
					0.1,  # alpha_threshold
					2.0   # epsilon (simplification)
				)

				if geom.success and geom.vertex_count > 0:
					# Add geometry to arrays
					var v_offset: int = vertices.size()

					for i: int in range(geom.vertices.size()):
						vertices.append(transform * geom.vertices[i])
						uvs.append(geom.uvs[i])
						normals.append(transform.basis * geom.normals[i])

					for idx: int in geom.indices:
						indices.append(v_offset + idx)

					tiles_processed += 1
					total_vertices += geom.vertex_count

	# Process vertex-edited tiles (always full quads, no alpha cropping)
	var vertex_tile_dict: Dictionary = tile_map_layer.get_vertex_tile_corners()
	if not vertex_tile_dict.is_empty():
		var node_inv: Transform3D = tile_map_layer.global_transform.affine_inverse()

		for tile_key: int in vertex_tile_dict.keys():
			var entry: Dictionary = vertex_tile_dict[tile_key]
			var corners: PackedVector3Array = entry.get("corners", PackedVector3Array())
			if corners.size() != 4:
				continue

			# Convert world-space corners to local-space
			var local_corners: PackedVector3Array = PackedVector3Array()
			for corner: Vector3 in corners:
				local_corners.append(node_inv * corner)

			# Normalize UV rect
			var uv_rect: Rect2 = entry.get("uv_rect", Rect2())
			var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
			var uv_rect_normalized: Rect2 = Rect2(uv_data.uv_min, uv_data.uv_max - uv_data.uv_min)

			var v_offset: int = vertices.size()
			var i_offset: int = indices.size()

			vertices.resize(v_offset + 4)
			uvs.resize(v_offset + 4)
			normals.resize(v_offset + 4)
			indices.resize(i_offset + 6)

			_add_vertex_quad_to_arrays(
				vertices, uvs, normals, indices,
				v_offset, i_offset,
				local_corners, uv_rect_normalized
			)

			tiles_processed += 1
			total_vertices += 4

	# Validate results
	if vertices.is_empty():
		return {"success": false, "error": "Alpha-aware merge resulted in 0 vertices"}

	# Create ArrayMesh using GlobalUtil
	var array_mesh: ArrayMesh = GlobalUtil.create_array_mesh_from_arrays(
		vertices, uvs, normals, indices,
		PackedFloat32Array(),  # Auto-generate tangents
		tile_map_layer.name + "_alpha_aware"
	)

	# Create material
	var material: StandardMaterial3D = GlobalUtil.create_baked_mesh_material(
		atlas_texture,
		tile_map_layer.texture_filter_mode,
		tile_map_layer.render_priority,
		true,  # enable_alpha
		true   # enable_toon_shading
	)

	array_mesh.surface_set_material(0, material)

	var elapsed: int = Time.get_ticks_msec() - start_time

	return {
		"success": true,
		"mesh": array_mesh,
		"material": material,
		"stats": {
			"tile_count": tiles_processed,
			"vertex_count": total_vertices,
			"merge_time_ms": elapsed
		}
	}
