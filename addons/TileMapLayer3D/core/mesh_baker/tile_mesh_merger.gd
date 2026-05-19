@tool
class_name TileMeshMerger
extends RefCounted

## Merges all tiles from a TileMapLayer3D into a single optimized ArrayMesh.

# --- Constants ---

## Enable debug logging for troubleshooting
const DEBUG_LOGGING: bool = false
const INVALID_PACKED_REGION: int = 0x7FFFFFFFFFFFFFFF

# --- Unified Entry Point ---

## Main entry point for all mesh baking operations.
## Pass region_chunk to process only tiles in that 30-unit region; null = full map.
static func merge_tiles(
	tile_map_layer: TileMapLayer3D,
	alpha_aware: bool = false,
	respect_tile_collision_custom_data: bool = false,
	region_chunk: TerrainRegionChunk = null
) -> Dictionary:
	var indices_override: Array[int] = region_chunk.columnar_indices if region_chunk != null else ([] as Array[int])
	var keys_override: Array[int] = region_chunk.tile_keys if region_chunk != null else ([] as Array[int])

	if alpha_aware:
		return _merge_alpha_aware(tile_map_layer, respect_tile_collision_custom_data, indices_override, keys_override, region_chunk)
	else:
		return merge_tiles_to_array_mesh(tile_map_layer, respect_tile_collision_custom_data, indices_override, keys_override, region_chunk)


## Return all existing columnar regions plus any vertex-only regions touched by
## edited vertex tile corners. Regional collision uses this so converted tiles
## still get baked after being removed from columnar storage.
##
## When [param for_editor_button] is true the live TerrainRegionChunk references
## are returned directly — the editor "Generate Collision" button is a synchronous
## user click with no concurrent paint stroke, so the defensive _copy_collision_region
## (which duplicates tile_keys / columnar_indices / vertex_tile_keys per region)
## is pure main-thread overhead. The runtime API path keeps the copy.
static func get_collision_regions(tile_map_layer: TileMapLayer3D, for_editor_button: bool = false) -> Array[TerrainRegionChunk]:
	var regions_by_key: Dictionary = {}
	for region: TerrainRegionChunk in tile_map_layer.region_system.all_regions():
		if region == null:
			continue
		regions_by_key[region.region_key_packed] = region if for_editor_button else _copy_collision_region(region)

	# When augmenting with vertex tiles we must copy any live reference once —
	# otherwise we'd mutate the live region's vertex_tile_keys. _copied_keys
	# tracks which regions we've already promoted to a copy so we don't recopy
	# on every vertex tile that lands in the same region.
	var _copied_keys: Dictionary = {}
	for tile_key: int in tile_map_layer.get_vertex_tile_corners().keys():
		var packed: int = _resolve_vertex_tile_region_key(tile_map_layer, tile_key)
		if packed == INVALID_PACKED_REGION:
			continue
		if not regions_by_key.has(packed):
			regions_by_key[packed] = TerrainRegionChunk.from_region_key(RegionSystem.unpack(packed))
			_copied_keys[packed] = true
		elif for_editor_button and not _copied_keys.has(packed):
			regions_by_key[packed] = _copy_collision_region(regions_by_key[packed])
			_copied_keys[packed] = true
		var collision_region: TerrainRegionChunk = regions_by_key[packed]
		collision_region.add_vertex_tile(tile_key)

	var result: Array[TerrainRegionChunk] = []
	for region in regions_by_key.values():
		result.append(region as TerrainRegionChunk)
	return result


## Return the collision regions touched by one vertex tile's edited corners.
## Used by runtime collision refresh when PlacedTileInfo no longer has a
## columnar TerrainRegionChunk.
static func get_collision_regions_for_vertex_tile(tile_map_layer: TileMapLayer3D, tile_key: int) -> Array[TerrainRegionChunk]:
	var result: Array[TerrainRegionChunk] = []
	var packed: int = _resolve_vertex_tile_region_key(tile_map_layer, tile_key)
	if packed == INVALID_PACKED_REGION:
		return result
	var existing: TerrainRegionChunk = tile_map_layer.region_system.get_region(packed)
	var collision_region: TerrainRegionChunk = _copy_collision_region(existing) if existing != null else TerrainRegionChunk.from_region_key(RegionSystem.unpack(packed))
	collision_region.add_vertex_tile(tile_key)
	result.append(collision_region)
	return result

# --- Main Merge Function ---

## Main merge function - returns dictionary with mesh and metadata.
static func merge_tiles_to_array_mesh(
	tile_map_layer: TileMapLayer3D,
	respect_tile_collision_custom_data: bool = false,
	indices_override: Array[int] = [],
	keys_override: Array[int] = [],
	region_chunk: TerrainRegionChunk = null
) -> Dictionary:
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
	var atlas_texture: Texture2D = TileAtlasResolver.get_active_texture(tile_map_layer.settings)

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

	var _indices_to_scan: PackedInt32Array
	if region_chunk != null:
		_indices_to_scan = PackedInt32Array(indices_override)
	else:
		_indices_to_scan = PackedInt32Array(range(tile_map_layer.get_tile_count()))
	# Capacity pre-pass: over-allocate to the unfiltered tile count and trim
	# at the end. Calling _tile_allows_collision here would double the C++
	# binding crossings (tileset.has_source / atlas.get_tile_data / get_custom_data)
	# for every tile — the geometry pass below is the source of truth and skips
	# filtered tiles via continue. PackedArray.resize down at the end is cheap.
	for i: int in _indices_to_scan:
		var tile_info: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(i)
		if tile_info == null:
			continue
		match tile_info.mesh_mode:
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
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
				# Arch corner mesh uses SurfaceTool (non-indexed): each quad = 6 verts
				# Columns = 2 + SEGMENTS, quads = columns - 1
				var arch_corner_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				total_vertices += arch_corner_quads * 6
				total_indices += arch_corner_quads * 6
			GlobalConstants.MeshMode.FLAT_ARCH:
				# Arch mesh: same structure as FLAT_ARCH_CORNER (1D strip)
				var arch_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				total_vertices += arch_quads * 6
				total_indices += arch_quads * 6
			GlobalConstants.MeshMode.FLAT_ARCH_I:
				# Arch-I mesh: same structure as FLAT_ARCH (1D strip)
				var arch_i_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				total_vertices += arch_i_quads * 6
				total_indices += arch_i_quads * 6
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
				# Arch-corner-I mesh: same structure as FLAT_ARCH_CORNER (1D strip)
				var arch_corner_i_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				total_vertices += arch_corner_i_quads * 6
				total_indices += arch_corner_i_quads * 6
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
				# Arch-corner-cap mesh: fan with (2 + SEGMENTS) triangles = (2 + SEGMENTS) * 3 verts
				var arch_corner_cap_vert_count: int = (2 + GlobalConstants.ARCH_ARC_SEGMENTS) * 3
				total_vertices += arch_corner_cap_vert_count
				total_indices += arch_corner_cap_vert_count
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
				# Arch-corner-cap-I mesh: fan with SEGMENTS triangles = SEGMENTS * 3 verts
				var arch_corner_cap_i_vert_count: int = GlobalConstants.ARCH_ARC_SEGMENTS * 3
				total_vertices += arch_corner_cap_i_vert_count
				total_indices += arch_corner_cap_i_vert_count
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
				# Arch-corner-cap-duo mesh: fan with (2 + 2*SEGMENTS) triangles = (2 + 2*SEGMENTS) * 3 verts
				var arch_corner_cap_duo_vert_count: int = (2 + 2 * GlobalConstants.ARCH_ARC_SEGMENTS) * 3
				total_vertices += arch_corner_cap_duo_vert_count
				total_indices += arch_corner_cap_duo_vert_count
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
				# Double-arc mesh: 2*SEGMENTS+1 quads = (2*SEGMENTS+1) * 6 verts
				var double_arc_quads: int = 2 * GlobalConstants.ARCH_ARC_SEGMENTS + 1
				total_vertices += double_arc_quads * 6
				total_indices += double_arc_quads * 6

	# Add capacity for vertex-edited tiles (each is a quad: 4 verts, 6 indices)
	var vertex_tile_dict: Dictionary = tile_map_layer.get_vertex_tile_corners()
	vertex_tile_dict = _filter_vertex_tiles_for_region(
		tile_map_layer, vertex_tile_dict, region_chunk, respect_tile_collision_custom_data, keys_override)
	var vertex_tile_count: int = vertex_tile_dict.size()
	total_vertices += vertex_tile_count * 4
	total_indices += vertex_tile_count * 6
	# Empty-region detection runs AFTER the geometry pass (line ~552) now that the
	# capacity counts are over-estimates: vertex_offset == 0 is the real signal.
	if total_vertices == 0 or total_indices == 0:
		return {
			"success": false,
			"error": "No collision-enabled tiles to merge" if respect_tile_collision_custom_data else "No tile geometry to merge",
			"empty_region": true
		}

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

	# Process each tile (region-filtered or full map)
	for tile_idx: int in _indices_to_scan:
		var tile_info: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(tile_idx)
		if tile_info == null:
			continue
		if not _tile_allows_collision(tile_map_layer, tile_info, respect_tile_collision_custom_data):
			continue

		# Check for custom transform (ramp/smart fill tiles bypass standard orientation)
		var transform: Transform3D
		if tile_info.has_custom_transform:
			transform = tile_info.custom_transform
		else:
			# Build transform for this tile using GlobalUtil (single source of truth)
			# Uses saved transform params for data persistency
			# Passes mesh_mode and depth_scale for proper BOX/PRISM scaling
			transform = GlobalUtil.build_tile_transform(
				tile_info.grid_position,
				tile_info.orientation,
				tile_info.mesh_rotation,
				grid_size,
				tile_info.is_face_flipped,
				tile_info.spin_angle_rad,
				tile_info.tilt_angle_rad,
				tile_info.diagonal_scale,
				tile_info.tilt_offset_factor,
				tile_info.mesh_mode,
				tile_info.depth_scale,
				tile_info.depth_growth_mode == GlobalConstants.DepthGrowthMode.INWARD
			)
		# Match live rendering: apply the same surface-normal offset used by the MultiMesh path
		transform.origin += GlobalUtil.calculate_flat_tile_offset(
			tile_info.orientation, tile_info.mesh_mode,
			tile_map_layer.settings.auto_resolve_box_z_fighting
		)

		#   Calculate exact UV coordinates from tile rect
		# Normalize pixel coordinates to [0,1] range for texture sampling
		var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(tile_info.uv_rect, atlas_size)
		var uv_rect_normalized: Rect2 = Rect2(uv_data.uv_min, uv_data.uv_max - uv_data.uv_min)

		# For freeze_uv: UV stays fixed in world space (shader counter-rotates; bake must match).
		# FLAT_SQUARE uses rotation when frozen (its convention differs from transform_uv_for_baking).
		# BOX/PRISM/arch use transform_uv_for_baking: pass 0 when frozen (no UV rotation).
		var mesh_uv_rot: int = 0 if tile_info.freeze_uv else tile_info.mesh_rotation

		# Add geometry based on mesh mode
		match tile_info.mesh_mode:
			GlobalConstants.MeshMode.FLAT_SQUARE:
				var uv_rot: int = tile_info.mesh_rotation if tile_info.freeze_uv else 0
				_add_square_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, grid_size,
					uv_rot, tile_info.is_face_flipped
				)
				vertex_offset += 4
				index_offset += 6

			GlobalConstants.MeshMode.FLAT_TRIANGULE:
				var temp_verts: PackedVector3Array = PackedVector3Array()
				var temp_uvs: PackedVector2Array = PackedVector2Array()
				var temp_normals: PackedVector3Array = PackedVector3Array()
				var temp_indices: PackedInt32Array = PackedInt32Array()

				GlobalUtil.add_triangle_geometry(
					temp_verts, temp_uvs, temp_normals, temp_indices,
					transform, uv_rect_normalized, grid_size
				)

				for i: int in range(3):
					vertices[vertex_offset + i] = temp_verts[i]
					# freeze_uv: apply same UV counter-rotation the shader applies
					if tile_info.freeze_uv and tile_info.mesh_rotation > 0:
						var uv: Vector2 = (temp_uvs[i] - uv_rect_normalized.position) / uv_rect_normalized.size
						match tile_info.mesh_rotation:
							1: uv = Vector2(uv.y, 1.0 - uv.x)
							2: uv = Vector2(1.0 - uv.x, 1.0 - uv.y)
							3: uv = Vector2(1.0 - uv.y, uv.x)
						uvs[vertex_offset + i] = uv_rect_normalized.position + uv * uv_rect_normalized.size
					else:
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
				if tile_info.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
					box_mesh = TileMeshGenerator.create_box_mesh_repeat(grid_size)
				else:
					box_mesh = TileMeshGenerator.create_box_mesh(grid_size)
				var vert_count: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, box_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)
				vertex_offset += 24
				index_offset += 36

			GlobalConstants.MeshMode.PRISM_MESH:
				# For PRISM_MESH, create base mesh - depth_scale is applied via transform
				# Use texture_repeat_mode to select correct UV mapping (DEFAULT=stripes, REPEAT=full)
				var prism_mesh: ArrayMesh
				if tile_info.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
					prism_mesh = TileMeshGenerator.create_prism_mesh_repeat(grid_size)
				else:
					prism_mesh = TileMeshGenerator.create_prism_mesh(grid_size)
				var vert_count: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, prism_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)
				vertex_offset += 24
				index_offset += 24

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
				# Generate arch corner mesh using settings radius, then add to arrays
				var arch_corner_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_mesh: ArrayMesh = TileMeshGenerator.create_arch_corner_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_corner_ratio
				)
				var arch_corner_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_corner_vert_count: int = arch_corner_quads * 6
				var _vert_count: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_corner_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)
				vertex_offset += arch_corner_vert_count
				index_offset += arch_corner_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH:
				# Generate arch mesh using settings radius, then add to arrays
				var arch_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_mesh: ArrayMesh = TileMeshGenerator.create_arch_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_ratio
				)
				var arch_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_vert_count: int = arch_quads * 6
				var _vert_count3: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)
				vertex_offset += arch_vert_count
				index_offset += arch_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_I:
				# Generate arch-I mesh using settings radius, then add to arrays
				var arch_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_i_mesh: ArrayMesh = TileMeshGenerator.create_arch_i_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_i_ratio
				)
				var arch_i_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_i_vert_count: int = arch_i_quads * 6
				var _vert_count4: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_i_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)
				vertex_offset += arch_i_vert_count
				index_offset += arch_i_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
				# Generate arch-corner-I mesh using settings radius, then add to arrays
				var arch_corner_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_i_mesh: ArrayMesh = TileMeshGenerator.create_arch_corner_i_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_corner_i_ratio
				)
				var arch_corner_i_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_corner_i_vert_count: int = arch_corner_i_quads * 6
				var _vert_count5: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_corner_i_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)
				vertex_offset += arch_corner_i_vert_count
				index_offset += arch_corner_i_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
				# Generate arch-corner-cap mesh using settings radius, then add to arrays
				var arch_corner_cap_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_cap_mesh: ArrayMesh = TileMeshGenerator.create_arch_corner_cap_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_corner_cap_ratio
				)
				var arch_corner_cap_vert_count: int = (2 + GlobalConstants.ARCH_ARC_SEGMENTS) * 3
				var _vert_count6: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_corner_cap_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)
				vertex_offset += arch_corner_cap_vert_count
				index_offset += arch_corner_cap_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
				# Generate arch-corner-cap-I mesh using settings radius, then add to arrays
				var arch_corner_cap_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_cap_i_mesh: ArrayMesh = TileMeshGenerator.create_arch_corner_cap_i_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_corner_cap_i_ratio
				)
				var arch_corner_cap_i_vert_count: int = GlobalConstants.ARCH_ARC_SEGMENTS * 3
				var _vert_count7: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_corner_cap_i_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)
				vertex_offset += arch_corner_cap_i_vert_count
				index_offset += arch_corner_cap_i_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
				# Generate arch-corner-cap-duo mesh using settings radius, then add to arrays
				var arch_corner_cap_duo_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_duo_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_cap_duo_mesh: ArrayMesh = TileMeshGenerator.create_arch_corner_cap_duo_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_corner_cap_duo_ratio
				)
				var arch_corner_cap_duo_vert_count: int = (2 + 2 * GlobalConstants.ARCH_ARC_SEGMENTS) * 3
				var _vert_count_duo: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_corner_cap_duo_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)
				vertex_offset += arch_corner_cap_duo_vert_count
				index_offset += arch_corner_cap_duo_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
				# Generate double-arc mesh using settings radius
				var double_arc_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					double_arc_ratio = tile_map_layer.settings.arch_radius_ratio
				var double_arc_mesh: ArrayMesh
				match tile_info.mesh_mode:
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C:
						double_arc_mesh = TileMeshGenerator.create_arch_corner_c_mesh(
							Rect2(0, 0, 1, 1), Vector2(1, 1),
							Vector2(grid_size, grid_size), double_arc_ratio
						)
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I:
						double_arc_mesh = TileMeshGenerator.create_arch_corner_c_i_mesh(
							Rect2(0, 0, 1, 1), Vector2(1, 1),
							Vector2(grid_size, grid_size), double_arc_ratio
						)
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S:
						double_arc_mesh = TileMeshGenerator.create_arch_corner_s_mesh(
							Rect2(0, 0, 1, 1), Vector2(1, 1),
							Vector2(grid_size, grid_size), double_arc_ratio
						)
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
						double_arc_mesh = TileMeshGenerator.create_arch_corner_s_i_mesh(
							Rect2(0, 0, 1, 1), Vector2(1, 1),
							Vector2(grid_size, grid_size), double_arc_ratio
						)
				var double_arc_quads: int = 2 * GlobalConstants.ARCH_ARC_SEGMENTS + 1
				var double_arc_vert_count: int = double_arc_quads * 6
				var _vert_count_da: int = _add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, double_arc_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)
				vertex_offset += double_arc_vert_count
				index_offset += double_arc_vert_count


		# Progress reporting for large merges (every 1000 tiles)
		#if tile_idx % 1000 == 0 and tile_idx > 0:
		#	print("  ⏳ Processed %d/%d tiles..." % [tile_idx, tile_map_layer.saved_tiles.size()])

	# Process vertex-edited tiles (stored separately from columnar data)
	if not vertex_tile_dict.is_empty():
		var node_inv: Transform3D = tile_map_layer.global_transform.affine_inverse()

		for tile_key: int in vertex_tile_dict.keys():
			var raw_entry = vertex_tile_dict[tile_key]
			if not raw_entry is VertexTileEntry:
				continue
			var entry: VertexTileEntry = raw_entry
			var corners: PackedVector3Array = entry.corners
			if corners.size() != 4:
				continue

			# Convert world-space corners to local-space
			var local_corners: PackedVector3Array = PackedVector3Array()
			for corner: Vector3 in corners:
				local_corners.append(node_inv * corner)

			# Normalize UV rect
			var uv_rect: Rect2 = entry.uv_rect
			var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
			var uv_rect_normalized: Rect2 = Rect2(uv_data.uv_min, uv_data.uv_max - uv_data.uv_min)

			_add_vertex_quad_to_arrays(
				vertices, uvs, normals, indices,
				vertex_offset, index_offset,
				local_corners, uv_rect_normalized
			)
			vertex_offset += 4
			index_offset += 6

	# Trim the over-allocated arrays down to what the geometry pass actually wrote.
	# Necessary because the capacity pre-pass no longer applies the collision filter,
	# so vertex_offset / index_offset are the real sizes.
	if vertex_offset == 0 or index_offset == 0:
		return {
			"success": false,
			"error": "No collision-enabled tiles to merge" if respect_tile_collision_custom_data else "No tile geometry to merge",
			"empty_region": true
		}
	if vertex_offset != total_vertices:
		vertices.resize(vertex_offset)
		uvs.resize(vertex_offset)
		normals.resize(vertex_offset)
	if index_offset != total_indices:
		indices.resize(index_offset)

	# Create the final ArrayMesh using GlobalUtil (single source of truth)
	var array_mesh: ArrayMesh = GlobalUtil.create_array_mesh_from_arrays(
		vertices, uvs, normals, indices,
		PackedFloat32Array(),  # Auto-generate tangents
		tile_map_layer.name + "_merged"
	)

	#   Create StandardMaterial3D for merged mesh (NOT ShaderMaterial)
	# ArrayMesh uses standard vertex UVs, not shader instance data like MultiMesh
	# Detect if texture has alpha for transparency settings
	var _alpha_img: Image = atlas_texture.get_image()
	if _alpha_img and _alpha_img.is_compressed():
		_alpha_img.decompress()
	var has_alpha: bool = _alpha_img != null and _alpha_img.detect_alpha() != Image.ALPHA_NONE

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


static func _filter_vertex_tiles_for_region(
	tile_map_layer: TileMapLayer3D,
	vertex_tile_dict: Dictionary,
	region_chunk: TerrainRegionChunk,
	respect_tile_collision_custom_data: bool,
	keys_override: Array[int] = []
) -> Dictionary:
	var filtered: Dictionary = {}
	var keys_set: Dictionary = {}
	if region_chunk != null:
		for k: int in region_chunk.vertex_tile_keys:
			keys_set[k] = true
		if keys_set.is_empty():
			return filtered
	elif not keys_override.is_empty():
		for k: int in keys_override:
			keys_set[k] = true
	for tile_key: int in vertex_tile_dict.keys():
		var raw_entry = vertex_tile_dict[tile_key]
		if not raw_entry is VertexTileEntry:
			continue
		if not keys_set.is_empty() and not keys_set.has(tile_key):
			continue
		var entry: VertexTileEntry = raw_entry
		if entry.corners.size() != 4:
			continue
		if not _tile_allows_collision(tile_map_layer, entry.tile_info, respect_tile_collision_custom_data):
			continue
		filtered[tile_key] = entry
	return filtered


static func _copy_collision_region(source: TerrainRegionChunk) -> TerrainRegionChunk:
	var result: TerrainRegionChunk = TerrainRegionChunk.from_region_key(source.region_key)
	result.tile_keys = source.tile_keys.duplicate()
	result.columnar_indices = source.columnar_indices.duplicate()
	result.vertex_tile_keys = source.vertex_tile_keys.duplicate()
	return result


static func _resolve_vertex_tile_region_key(tile_map_layer: TileMapLayer3D, tile_key: int) -> int:
	var raw_entry = tile_map_layer.get_vertex_entry(tile_key)
	if raw_entry == null or raw_entry.corners.size() != 4:
		return INVALID_PACKED_REGION
	var node_inv: Transform3D = tile_map_layer.global_transform.affine_inverse()
	var local_aabb: AABB = _vertex_entry_local_aabb(raw_entry, node_inv)
	return RegionSystem.pack(RegionSystem.resolve_region_key(local_aabb.get_center()))


static func _vertex_entry_local_aabb(entry: VertexTileEntry, node_inv: Transform3D) -> AABB:
	var first: Vector3 = node_inv * entry.corners[0]
	var min_pos: Vector3 = first
	var max_pos: Vector3 = first
	for i: int in range(1, entry.corners.size()):
		var p: Vector3 = node_inv * entry.corners[i]
		min_pos.x = minf(min_pos.x, p.x)
		min_pos.y = minf(min_pos.y, p.y)
		min_pos.z = minf(min_pos.z, p.z)
		max_pos.x = maxf(max_pos.x, p.x)
		max_pos.y = maxf(max_pos.y, p.y)
		max_pos.z = maxf(max_pos.z, p.z)
	return AABB(min_pos, max_pos - min_pos)


static func _tile_allows_collision(
	tile_map_layer: TileMapLayer3D,
	tile_info: PlacedTileInfo,
	respect_tile_collision_custom_data: bool
) -> bool:
	if not respect_tile_collision_custom_data:
		return true
	if tile_map_layer == null or tile_info == null:
		return true
	if tile_info.atlas_source_id < 0 or tile_info.atlas_coords.x < 0 or tile_info.atlas_coords.y < 0:
		return true
	if tile_map_layer.settings == null or tile_map_layer.settings.tileset == null:
		return true
	if not tile_map_layer.settings.tileset.has_source(tile_info.atlas_source_id):
		return true

	var atlas: TileSetAtlasSource = tile_map_layer.settings.tileset.get_source(tile_info.atlas_source_id) as TileSetAtlasSource
	if atlas == null or not atlas.has_tile(tile_info.atlas_coords):
		return true

	var tile_data: TileData = atlas.get_tile_data(tile_info.atlas_coords, 0)
	if tile_data == null or not tile_data.has_custom_data(GlobalConstants.CUSTOM_DATA_COLLISION):
		return true

	var collision_value: Variant = tile_data.get_custom_data(GlobalConstants.CUSTOM_DATA_COLLISION)
	if collision_value is bool:
		return collision_value
	return true

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

	# Local UV coordinates in [0,1] space for each vertex.
	# mesh_rotation applied here mirrors the shader's freeze-UV counter-rotation behavior.
	# Normal tiles pass mesh_rotation=0 (no UV rotation; mesh rotates via transform).
	# freeze_uv tiles pass the actual mesh_rotation so UVs counter-rotate to stay fixed.
	var local_uvs: Array[Vector2] = [
		Vector2(0.0, 0.0),  # 0: bottom-left
		Vector2(1.0, 0.0),  # 1: bottom-right
		Vector2(1.0, 1.0),  # 2: top-right
		Vector2(0.0, 1.0)   # 3: top-left
	]

	var normal: Vector3 = transform.basis.y.normalized()

	for i: int in range(4):
		vertices[v_offset + i] = transform * local_verts[i]
		var final_uv: Vector2 = local_uvs[i]
		if is_face_flipped:
			final_uv.x = 1.0 - final_uv.x
		match mesh_rotation:
			1:
				final_uv = Vector2(final_uv.y, 1.0 - final_uv.x)
			2:
				final_uv = Vector2(1.0 - final_uv.x, 1.0 - final_uv.y)
			3:
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


static func _add_square_dynamic(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	transform: Transform3D,
	uv_rect: Rect2,
	grid_size: float
) -> void:
	var v_offset: int = vertices.size()
	var i_offset: int = indices.size()
	vertices.resize(v_offset + 4)
	uvs.resize(v_offset + 4)
	normals.resize(v_offset + 4)
	indices.resize(i_offset + 6)
	_add_square_to_arrays(
		vertices, uvs, normals, indices,
		v_offset, i_offset,
		transform, uv_rect, grid_size
	)

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
static func _merge_alpha_aware(
	tile_map_layer: TileMapLayer3D,
	respect_tile_collision_custom_data: bool = false,
	indices_override: Array[int] = [],
	keys_override: Array[int] = [],
	region_chunk: TerrainRegionChunk = null
) -> Dictionary:
	var start_time: int = Time.get_ticks_msec()

	var atlas_texture: Texture2D = TileAtlasResolver.get_active_texture(tile_map_layer.settings)
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

	var _indices_to_scan: PackedInt32Array
	if region_chunk != null:
		_indices_to_scan = PackedInt32Array(indices_override)
	else:
		_indices_to_scan = PackedInt32Array(range(tile_map_layer.get_tile_count()))

	# Process each tile (region-filtered or full map)
	for tile_idx: int in _indices_to_scan:
		var tile_info: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(tile_idx)
		if tile_info == null:
			continue
		if not _tile_allows_collision(tile_map_layer, tile_info, respect_tile_collision_custom_data):
			continue

		# Check for custom transform (ramp/smart fill tiles bypass standard orientation)
		var transform: Transform3D
		if tile_info.has_custom_transform:
			transform = tile_info.custom_transform
		else:
			# Build transform using saved transform params for data persistency
			# Passes mesh_mode and depth_scale for proper BOX/PRISM scaling
			transform = GlobalUtil.build_tile_transform(
				tile_info.grid_position,
				tile_info.orientation,
				tile_info.mesh_rotation,
				grid_size,
				tile_info.is_face_flipped,
				tile_info.spin_angle_rad,
				tile_info.tilt_angle_rad,
				tile_info.diagonal_scale,
				tile_info.tilt_offset_factor,
				tile_info.mesh_mode,
				tile_info.depth_scale,
				tile_info.depth_growth_mode == GlobalConstants.DepthGrowthMode.INWARD
			)
		# Match live rendering: apply the same surface-normal offset used by the MultiMesh path
		transform.origin += GlobalUtil.calculate_flat_tile_offset(
			tile_info.orientation, tile_info.mesh_mode,
			tile_map_layer.settings.auto_resolve_box_z_fighting
		)

		# Normalize UV rect using GlobalUtil (single source of truth)
		var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(tile_info.uv_rect, atlas_size)
		var uv_rect_normalized: Rect2 = Rect2(uv_data.uv_min, uv_data.uv_max - uv_data.uv_min)

		var mesh_uv_rot: int = 0 if tile_info.freeze_uv else tile_info.mesh_rotation

		match tile_info.mesh_mode:
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
				if tile_info.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
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
					mesh_uv_rot, tile_info.is_face_flipped
				)

				tiles_processed += 1
				total_vertices += 24

			GlobalConstants.MeshMode.PRISM_MESH:
				# Use full prism mesh (same as regular merge) - includes all faces
				# This ensures proper collision and baked mesh generation
				# depth_scale is applied via transform, not mesh generation
				# Use texture_repeat_mode to select correct UV mapping
				var prism_mesh: ArrayMesh
				if tile_info.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
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
					mesh_uv_rot, tile_info.is_face_flipped
				)

				tiles_processed += 1
				total_vertices += 24

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
				# Generate arch corner mesh and add to arrays (same as regular merge)
				var arch_corner_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_mesh: ArrayMesh = TileMeshGenerator.create_arch_corner_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_corner_ratio
				)
				var arch_corner_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_corner_vert_count: int = arch_corner_quads * 6
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				vertices.resize(v_offset + arch_corner_vert_count)
				uvs.resize(v_offset + arch_corner_vert_count)
				normals.resize(v_offset + arch_corner_vert_count)
				indices.resize(i_offset + arch_corner_vert_count)

				_add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, arch_corner_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)

				tiles_processed += 1
				total_vertices += arch_corner_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH:
				# Generate arch mesh and add to arrays
				var arch_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_mesh: ArrayMesh = TileMeshGenerator.create_arch_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_ratio
				)
				var arch_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_vert_count: int = arch_quads * 6
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				vertices.resize(v_offset + arch_vert_count)
				uvs.resize(v_offset + arch_vert_count)
				normals.resize(v_offset + arch_vert_count)
				indices.resize(i_offset + arch_vert_count)

				_add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, arch_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)

				tiles_processed += 1
				total_vertices += arch_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_I:
				# Generate arch-I mesh and add to arrays
				var arch_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_i_mesh: ArrayMesh = TileMeshGenerator.create_arch_i_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_i_ratio
				)
				var arch_i_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_i_vert_count: int = arch_i_quads * 6
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				vertices.resize(v_offset + arch_i_vert_count)
				uvs.resize(v_offset + arch_i_vert_count)
				normals.resize(v_offset + arch_i_vert_count)
				indices.resize(i_offset + arch_i_vert_count)

				_add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, arch_i_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)

				tiles_processed += 1
				total_vertices += arch_i_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
				# Generate arch-corner-I mesh and add to arrays
				var arch_corner_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_i_mesh: ArrayMesh = TileMeshGenerator.create_arch_corner_i_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_corner_i_ratio
				)
				var arch_corner_i_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_corner_i_vert_count: int = arch_corner_i_quads * 6
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				vertices.resize(v_offset + arch_corner_i_vert_count)
				uvs.resize(v_offset + arch_corner_i_vert_count)
				normals.resize(v_offset + arch_corner_i_vert_count)
				indices.resize(i_offset + arch_corner_i_vert_count)

				_add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, arch_corner_i_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)

				tiles_processed += 1
				total_vertices += arch_corner_i_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
				# Generate arch-corner-cap mesh and add to arrays
				var arch_corner_cap_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_cap_mesh: ArrayMesh = TileMeshGenerator.create_arch_corner_cap_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_corner_cap_ratio
				)
				var arch_corner_cap_vert_count: int = (2 + GlobalConstants.ARCH_ARC_SEGMENTS) * 3
				var v_offset6: int = vertices.size()
				var i_offset6: int = indices.size()

				vertices.resize(v_offset6 + arch_corner_cap_vert_count)
				uvs.resize(v_offset6 + arch_corner_cap_vert_count)
				normals.resize(v_offset6 + arch_corner_cap_vert_count)
				indices.resize(i_offset6 + arch_corner_cap_vert_count)

				_add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					v_offset6, i_offset6,
					transform, uv_rect_normalized, arch_corner_cap_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)

				tiles_processed += 1
				total_vertices += arch_corner_cap_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
				# Generate arch-corner-cap-I mesh and add to arrays
				var arch_corner_cap_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_cap_i_mesh: ArrayMesh = TileMeshGenerator.create_arch_corner_cap_i_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_corner_cap_i_ratio
				)
				var arch_corner_cap_i_vert_count: int = GlobalConstants.ARCH_ARC_SEGMENTS * 3
				var v_offset7: int = vertices.size()
				var i_offset7: int = indices.size()

				vertices.resize(v_offset7 + arch_corner_cap_i_vert_count)
				uvs.resize(v_offset7 + arch_corner_cap_i_vert_count)
				normals.resize(v_offset7 + arch_corner_cap_i_vert_count)
				indices.resize(i_offset7 + arch_corner_cap_i_vert_count)

				_add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					v_offset7, i_offset7,
					transform, uv_rect_normalized, arch_corner_cap_i_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)

				tiles_processed += 1
				total_vertices += arch_corner_cap_i_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
				# Generate arch-corner-cap-duo mesh and add to arrays
				var arch_corner_cap_duo_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_duo_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_cap_duo_mesh: ArrayMesh = TileMeshGenerator.create_arch_corner_cap_duo_mesh(
					Rect2(0, 0, 1, 1), Vector2(1, 1),
					Vector2(grid_size, grid_size), arch_corner_cap_duo_ratio
				)
				var arch_corner_cap_duo_vert_count: int = (2 + 2 * GlobalConstants.ARCH_ARC_SEGMENTS) * 3
				var v_offset_duo: int = vertices.size()
				var i_offset_duo: int = indices.size()

				vertices.resize(v_offset_duo + arch_corner_cap_duo_vert_count)
				uvs.resize(v_offset_duo + arch_corner_cap_duo_vert_count)
				normals.resize(v_offset_duo + arch_corner_cap_duo_vert_count)
				indices.resize(i_offset_duo + arch_corner_cap_duo_vert_count)

				_add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					v_offset_duo, i_offset_duo,
					transform, uv_rect_normalized, arch_corner_cap_duo_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)

				tiles_processed += 1
				total_vertices += arch_corner_cap_duo_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
				# Generate double-arc mesh using settings radius
				var da_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					da_ratio = tile_map_layer.settings.arch_radius_ratio
				var da_mesh: ArrayMesh
				match tile_info.mesh_mode:
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C:
						da_mesh = TileMeshGenerator.create_arch_corner_c_mesh(
							Rect2(0, 0, 1, 1), Vector2(1, 1),
							Vector2(grid_size, grid_size), da_ratio
						)
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I:
						da_mesh = TileMeshGenerator.create_arch_corner_c_i_mesh(
							Rect2(0, 0, 1, 1), Vector2(1, 1),
							Vector2(grid_size, grid_size), da_ratio
						)
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S:
						da_mesh = TileMeshGenerator.create_arch_corner_s_mesh(
							Rect2(0, 0, 1, 1), Vector2(1, 1),
							Vector2(grid_size, grid_size), da_ratio
						)
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
						da_mesh = TileMeshGenerator.create_arch_corner_s_i_mesh(
							Rect2(0, 0, 1, 1), Vector2(1, 1),
							Vector2(grid_size, grid_size), da_ratio
						)
				var da_quads: int = 2 * GlobalConstants.ARCH_ARC_SEGMENTS + 1
				var da_vert_count: int = da_quads * 6
				var v_offset_da: int = vertices.size()
				var i_offset_da: int = indices.size()

				vertices.resize(v_offset_da + da_vert_count)
				uvs.resize(v_offset_da + da_vert_count)
				normals.resize(v_offset_da + da_vert_count)
				indices.resize(i_offset_da + da_vert_count)

				_add_mesh_to_arrays(
					vertices, uvs, normals, indices,
					v_offset_da, i_offset_da,
					transform, uv_rect_normalized, da_mesh,
					mesh_uv_rot, tile_info.is_face_flipped
				)

				tiles_processed += 1
				total_vertices += da_vert_count

			GlobalConstants.MeshMode.FLAT_SQUARE, _:
				# Convert uv_rect to pixel coords if stored in normalized (0-1) form.
				# Editor tiles use pixel coords; runtime API tiles may use normalized fractions.
				# Heuristic: both dimensions < 2.0 → normalized → multiply by atlas_size.
				var raw_uv: Rect2 = tile_info.uv_rect
				var pixel_uv: Rect2 = raw_uv
				if raw_uv.size.x < 2.0 and raw_uv.size.y < 2.0:
					pixel_uv = Rect2(raw_uv.position * atlas_size, raw_uv.size * atlas_size)

				if pixel_uv.size.x < 1.0 or pixel_uv.size.y < 1.0:
					# Missing atlas data cannot be alpha-cropped, but collision should
					# still cover the tile shape instead of disappearing.
					var fallback_uv: Rect2 = uv_rect_normalized if uv_rect_normalized.has_area() else Rect2(Vector2.ZERO, Vector2.ONE)
					_add_square_dynamic(vertices, uvs, normals, indices, transform, fallback_uv, grid_size)
					tiles_processed += 1
					total_vertices += 4
					continue

				# Generate alpha-aware geometry using BitMap API (for square tiles)
				var geom: Dictionary = AlphaMeshGenerator.generate_alpha_mesh(
					atlas_texture,
					pixel_uv,
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
				elif not geom.success:
					var fallback_uv: Rect2 = uv_rect_normalized if uv_rect_normalized.has_area() else Rect2(Vector2.ZERO, Vector2.ONE)
					_add_square_dynamic(vertices, uvs, normals, indices, transform, fallback_uv, grid_size)
					tiles_processed += 1
					total_vertices += 4

	# Process vertex-edited tiles (always full quads, no alpha cropping)
	var vertex_tile_dict: Dictionary = tile_map_layer.get_vertex_tile_corners()
	vertex_tile_dict = _filter_vertex_tiles_for_region(
		tile_map_layer, vertex_tile_dict, region_chunk, respect_tile_collision_custom_data, keys_override)
	if not vertex_tile_dict.is_empty():
		var node_inv: Transform3D = tile_map_layer.global_transform.affine_inverse()

		for tile_key: int in vertex_tile_dict.keys():
			var raw_entry = vertex_tile_dict[tile_key]
			if not raw_entry is VertexTileEntry:
				continue
			var entry: VertexTileEntry = raw_entry
			var corners: PackedVector3Array = entry.corners
			if corners.size() != 4:
				continue

			# Convert world-space corners to local-space
			var local_corners: PackedVector3Array = PackedVector3Array()
			for corner: Vector3 in corners:
				local_corners.append(node_inv * corner)

			# Normalize UV rect
			var uv_rect: Rect2 = entry.uv_rect
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
		var empty_error: String = "No collision-enabled tiles to merge" if respect_tile_collision_custom_data else "Alpha-aware merge resulted in 0 vertices"
		return {"success": false, "error": empty_error, "empty_region": true}

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
