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
	region_chunk: TerrainRegionChunk = null,
	collision_only: bool = false
) -> Dictionary:
	var indices_override: Array[int] = region_chunk.columnar_indices if region_chunk != null else ([] as Array[int])
	var keys_override: Array[int] = region_chunk.tile_keys if region_chunk != null else ([] as Array[int])

	if alpha_aware:
		return _merge_alpha_aware(tile_map_layer, respect_tile_collision_custom_data, indices_override, keys_override, region_chunk, collision_only)
	else:
		return merge_tiles_to_array_mesh(tile_map_layer, respect_tile_collision_custom_data, indices_override, keys_override, region_chunk, collision_only)


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
	region_chunk: TerrainRegionChunk = null,
	collision_only: bool = false
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
	var base_mesh_data_cache: Dictionary = {}

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
				var box_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.BOX_MESH,
					grid_size,
					tile_info.texture_repeat_mode
				)
				var vert_count: int = _add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, box_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				vertex_offset += 24
				index_offset += 36

			GlobalConstants.MeshMode.PRISM_MESH:
				# For PRISM_MESH, create base mesh - depth_scale is applied via transform
				# Use texture_repeat_mode to select correct UV mapping (DEFAULT=stripes, REPEAT=full)
				var prism_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.PRISM_MESH,
					grid_size,
					tile_info.texture_repeat_mode
				)
				var vert_count: int = _add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, prism_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				vertex_offset += 24
				index_offset += 24

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
				# Generate arch corner mesh using settings radius, then add to arrays
				var arch_corner_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_corner_ratio
				)
				var arch_corner_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_corner_vert_count: int = arch_corner_quads * 6
				var _vert_count: int = _add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_corner_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				vertex_offset += arch_corner_vert_count
				index_offset += arch_corner_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH:
				# Generate arch mesh using settings radius, then add to arrays
				var arch_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_ratio
				)
				var arch_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_vert_count: int = arch_quads * 6
				var _vert_count3: int = _add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				vertex_offset += arch_vert_count
				index_offset += arch_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_I:
				# Generate arch-I mesh using settings radius, then add to arrays
				var arch_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_i_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_I,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_i_ratio
				)
				var arch_i_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_i_vert_count: int = arch_i_quads * 6
				var _vert_count4: int = _add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_i_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				vertex_offset += arch_i_vert_count
				index_offset += arch_i_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
				# Generate arch-corner-I mesh using settings radius, then add to arrays
				var arch_corner_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_i_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_corner_i_ratio
				)
				var arch_corner_i_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_corner_i_vert_count: int = arch_corner_i_quads * 6
				var _vert_count5: int = _add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_corner_i_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				vertex_offset += arch_corner_i_vert_count
				index_offset += arch_corner_i_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
				# Generate arch-corner-cap mesh using settings radius, then add to arrays
				var arch_corner_cap_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_cap_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_corner_cap_ratio
				)
				var arch_corner_cap_vert_count: int = (2 + GlobalConstants.ARCH_ARC_SEGMENTS) * 3
				var _vert_count6: int = _add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_corner_cap_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				vertex_offset += arch_corner_cap_vert_count
				index_offset += arch_corner_cap_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
				# Generate arch-corner-cap-I mesh using settings radius, then add to arrays
				var arch_corner_cap_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_cap_i_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_corner_cap_i_ratio
				)
				var arch_corner_cap_i_vert_count: int = GlobalConstants.ARCH_ARC_SEGMENTS * 3
				var _vert_count7: int = _add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_corner_cap_i_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				vertex_offset += arch_corner_cap_i_vert_count
				index_offset += arch_corner_cap_i_vert_count

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
				# Generate arch-corner-cap-duo mesh using settings radius, then add to arrays
				var arch_corner_cap_duo_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_duo_ratio = tile_map_layer.settings.arch_radius_ratio
				var arch_corner_cap_duo_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_corner_cap_duo_ratio
				)
				var arch_corner_cap_duo_vert_count: int = (2 + 2 * GlobalConstants.ARCH_ARC_SEGMENTS) * 3
				var _vert_count_duo: int = _add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, arch_corner_cap_duo_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
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
				var double_arc_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					tile_info.mesh_mode,
					grid_size,
					tile_info.texture_repeat_mode,
					double_arc_ratio
				)
				var double_arc_quads: int = 2 * GlobalConstants.ARCH_ARC_SEGMENTS + 1
				var double_arc_vert_count: int = double_arc_quads * 6
				var _vert_count_da: int = _add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					vertex_offset, index_offset,
					transform, uv_rect_normalized, double_arc_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
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

	var array_mesh: ArrayMesh
	if collision_only:
		array_mesh = _create_collision_array_mesh(vertices, indices, tile_map_layer.name + "_collision")
		var collision_elapsed: int = Time.get_ticks_msec() - start_time
		return {
			"success": true,
			"mesh": array_mesh,
			"material": null,
			"stats": {
				"tile_count": tile_map_layer.get_tile_count() + vertex_tile_count,
				"vertex_count": vertex_offset,
				"triangle_count": index_offset / 3,
				"merge_time_ms": collision_elapsed
			}
		}

	# Create the final ArrayMesh using GlobalUtil (single source of truth)
	array_mesh = GlobalUtil.create_array_mesh_from_arrays(
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


static func _create_collision_array_mesh(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	mesh_name: String = ""
) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh: ArrayMesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if not mesh_name.is_empty():
		array_mesh.resource_name = mesh_name
	return array_mesh


static func _get_base_mesh_data(
	cache: Dictionary,
	mesh_mode: int,
	grid_size: float,
	texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT,
	arch_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> Dictionary:
	var key: String = "%d|%.6f|%d|%.6f" % [mesh_mode, grid_size, texture_repeat_mode, arch_radius_ratio]
	if cache.has(key):
		return cache[key]

	var tile_size: Vector2 = Vector2(grid_size, grid_size)
	var mesh: ArrayMesh = null
	match mesh_mode:
		GlobalConstants.MeshMode.BOX_MESH:
			if texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
				mesh = TileMeshGenerator.create_box_mesh_repeat(grid_size)
			else:
				mesh = TileMeshGenerator.create_box_mesh(grid_size)
		GlobalConstants.MeshMode.PRISM_MESH:
			if texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
				mesh = TileMeshGenerator.create_prism_mesh_repeat(grid_size)
			else:
				mesh = TileMeshGenerator.create_prism_mesh(grid_size)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
			mesh = TileMeshGenerator.create_arch_corner_mesh(Rect2(0, 0, 1, 1), Vector2(1, 1), tile_size, arch_radius_ratio)
		GlobalConstants.MeshMode.FLAT_ARCH:
			mesh = TileMeshGenerator.create_arch_mesh(Rect2(0, 0, 1, 1), Vector2(1, 1), tile_size, arch_radius_ratio)
		GlobalConstants.MeshMode.FLAT_ARCH_I:
			mesh = TileMeshGenerator.create_arch_i_mesh(Rect2(0, 0, 1, 1), Vector2(1, 1), tile_size, arch_radius_ratio)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
			mesh = TileMeshGenerator.create_arch_corner_i_mesh(Rect2(0, 0, 1, 1), Vector2(1, 1), tile_size, arch_radius_ratio)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
			mesh = TileMeshGenerator.create_arch_corner_cap_mesh(Rect2(0, 0, 1, 1), Vector2(1, 1), tile_size, arch_radius_ratio)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
			mesh = TileMeshGenerator.create_arch_corner_cap_i_mesh(Rect2(0, 0, 1, 1), Vector2(1, 1), tile_size, arch_radius_ratio)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
			mesh = TileMeshGenerator.create_arch_corner_cap_duo_mesh(Rect2(0, 0, 1, 1), Vector2(1, 1), tile_size, arch_radius_ratio)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C:
			mesh = TileMeshGenerator.create_arch_corner_c_mesh(Rect2(0, 0, 1, 1), Vector2(1, 1), tile_size, arch_radius_ratio)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I:
			mesh = TileMeshGenerator.create_arch_corner_c_i_mesh(Rect2(0, 0, 1, 1), Vector2(1, 1), tile_size, arch_radius_ratio)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S:
			mesh = TileMeshGenerator.create_arch_corner_s_mesh(Rect2(0, 0, 1, 1), Vector2(1, 1), tile_size, arch_radius_ratio)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
			mesh = TileMeshGenerator.create_arch_corner_s_i_mesh(Rect2(0, 0, 1, 1), Vector2(1, 1), tile_size, arch_radius_ratio)

	if mesh == null or mesh.get_surface_count() == 0:
		return {}

	var arrays: Array = mesh.surface_get_arrays(0)
	var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_indices_raw = arrays[Mesh.ARRAY_INDEX]
	var src_indices: PackedInt32Array
	if src_indices_raw != null:
		src_indices = src_indices_raw
	else:
		src_indices = PackedInt32Array()
		src_indices.resize(src_verts.size())
		for i: int in range(src_verts.size()):
			src_indices[i] = i

	var data: Dictionary = {
		"vertices": src_verts,
		"uvs": arrays[Mesh.ARRAY_TEX_UV],
		"normals": arrays[Mesh.ARRAY_NORMAL],
		"indices": src_indices
	}
	cache[key] = data
	return data


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


static func _tile_allows_collision_at_index(
	tile_map_layer: TileMapLayer3D,
	index: int,
	respect_tile_collision_custom_data: bool,
	cache: Dictionary
) -> bool:
	if not respect_tile_collision_custom_data:
		return true
	if tile_map_layer == null or index < 0 or index >= tile_map_layer._tile_positions.size():
		return true
	if index >= tile_map_layer._tile_atlas_source_ids.size():
		return true

	var atlas_source_id: int = tile_map_layer._tile_atlas_source_ids[index]
	var ac_idx: int = index * TileMapLayer3D.ATLAS_COORDS_STRIDE
	if atlas_source_id < 0 or ac_idx + 1 >= tile_map_layer._tile_atlas_coords.size():
		return true

	var atlas_coords: Vector2i = Vector2i(tile_map_layer._tile_atlas_coords[ac_idx], tile_map_layer._tile_atlas_coords[ac_idx + 1])
	if atlas_coords.x < 0 or atlas_coords.y < 0:
		return true

	var cache_key: String = "%d|%d|%d" % [atlas_source_id, atlas_coords.x, atlas_coords.y]
	if cache.has(cache_key):
		return cache[cache_key]

	var allowed: bool = true
	if tile_map_layer.settings != null and tile_map_layer.settings.tileset != null and tile_map_layer.settings.tileset.has_source(atlas_source_id):
		var atlas: TileSetAtlasSource = tile_map_layer.settings.tileset.get_source(atlas_source_id) as TileSetAtlasSource
		if atlas != null and atlas.has_tile(atlas_coords):
			var tile_data: TileData = atlas.get_tile_data(atlas_coords, 0)
			if tile_data != null and tile_data.has_custom_data(GlobalConstants.CUSTOM_DATA_COLLISION):
				var collision_value: Variant = tile_data.get_custom_data(GlobalConstants.CUSTOM_DATA_COLLISION)
				if collision_value is bool:
					allowed = collision_value

	cache[cache_key] = allowed
	return allowed


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


static func _add_square_collision_dynamic(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	transform: Transform3D,
	grid_size: float
) -> void:
	var v_offset: int = vertices.size()
	var i_offset: int = indices.size()
	vertices.resize(v_offset + 4)
	indices.resize(i_offset + 6)

	var half_size: float = grid_size * 0.5
	vertices[v_offset] = transform * Vector3(-half_size, 0.0, -half_size)
	vertices[v_offset + 1] = transform * Vector3(half_size, 0.0, -half_size)
	vertices[v_offset + 2] = transform * Vector3(half_size, 0.0, half_size)
	vertices[v_offset + 3] = transform * Vector3(-half_size, 0.0, half_size)

	indices[i_offset] = v_offset
	indices[i_offset + 1] = v_offset + 1
	indices[i_offset + 2] = v_offset + 2
	indices[i_offset + 3] = v_offset
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

	return _add_mesh_data_to_arrays(
		vertices, uvs, normals, indices,
		v_offset, i_offset,
		transform, uv_rect,
		{
			"vertices": src_verts,
			"uvs": src_uvs,
			"normals": src_normals,
			"indices": src_indices
		},
		mesh_rotation, is_face_flipped
	)


static func _add_mesh_data_to_arrays(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	v_offset: int,
	i_offset: int,
	transform: Transform3D,
	uv_rect: Rect2,
	source_data: Dictionary,
	mesh_rotation: int = 0,
	is_face_flipped: bool = false,
	copy_surface_data: bool = true
) -> int:
	if source_data.is_empty():
		return 0

	var src_verts: PackedVector3Array = source_data["vertices"]
	var src_uvs: PackedVector2Array = source_data["uvs"]
	var src_normals: PackedVector3Array = source_data["normals"]
	var src_indices: PackedInt32Array = source_data["indices"]
	var vert_count: int = src_verts.size()
	var idx_count: int = src_indices.size()

	# Transform vertices to world space and copy data
	for i: int in range(vert_count):
		vertices[v_offset + i] = transform * src_verts[i]
		if copy_surface_data:
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


static func _merge_alpha_aware_region_collision_columnar(
	tile_map_layer: TileMapLayer3D,
	respect_tile_collision_custom_data: bool,
	region_chunk: TerrainRegionChunk
) -> Dictionary:
	var start_time: int = Time.get_ticks_msec()

	var atlas_texture: Texture2D = TileAtlasResolver.get_active_texture(tile_map_layer.settings)
	if not atlas_texture:
		return {"success": false, "error": "No tileset texture"}

	var atlas_size: Vector2 = atlas_texture.get_size()
	var grid_size: float = tile_map_layer.grid_size
	var arch_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
	if tile_map_layer.settings:
		arch_radius_ratio = tile_map_layer.settings.arch_radius_ratio

	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var dummy_uvs: PackedVector2Array = PackedVector2Array()
	var dummy_normals: PackedVector3Array = PackedVector3Array()
	var base_mesh_data_cache: Dictionary = {}
	var collision_custom_data_cache: Dictionary = {}

	var tiles_processed: int = 0
	var total_vertices: int = 0
	var profile_info_ms: int = 0
	var profile_collision_filter_ms: int = 0
	var profile_transform_ms: int = 0
	var profile_alpha_ms: int = 0
	var profile_append_ms: int = 0
	var profile_alpha_hits: int = 0
	var profile_alpha_misses: int = 0
	var profile_tiles_scanned: int = 0
	var profile_tiles_filtered: int = 0
	var profile_mesh_gen_ms: int = 0
	var profile_resize_ms: int = 0
	var profile_copy_ms: int = 0
	var profile_square_count: int = 0
	var profile_triangle_count: int = 0
	var profile_box_count: int = 0
	var profile_prism_count: int = 0
	var profile_arch_count: int = 0
	var profile_square_ms: int = 0
	var profile_triangle_ms: int = 0
	var profile_box_ms: int = 0
	var profile_prism_ms: int = 0
	var profile_arch_ms: int = 0

	var region_tile_keys: Array[int] = region_chunk.tile_keys
	var region_index: int = 0
	for tile_idx: int in region_chunk.columnar_indices:
		profile_tiles_scanned += 1
		var profile_step_start: int = Time.get_ticks_msec()
		var tile_key: int = region_tile_keys[region_index] if region_index < region_tile_keys.size() else -1
		region_index += 1
		if tile_idx < 0 or tile_idx >= tile_map_layer._tile_positions.size():
			profile_info_ms += Time.get_ticks_msec() - profile_step_start
			continue

		var grid_position: Vector3 = tile_map_layer._tile_positions[tile_idx]
		var uv_base: int = tile_idx * 4
		var uv_rect: Rect2 = Rect2()
		if uv_base + 3 < tile_map_layer._tile_uv_rects.size():
			uv_rect = Rect2(
				tile_map_layer._tile_uv_rects[uv_base],
				tile_map_layer._tile_uv_rects[uv_base + 1],
				tile_map_layer._tile_uv_rects[uv_base + 2],
				tile_map_layer._tile_uv_rects[uv_base + 3]
			)

		var flags: int = tile_map_layer._tile_flags[tile_idx]
		var orientation: int = flags & 0x1F
		var mesh_rotation: int = (flags >> 5) & 0x3
		var is_face_flipped: bool = ((flags >> 7) & 0x1) == 1
		var texture_repeat_mode: int = (flags >> 16) & 0x1
		var freeze_uv: bool = bool((flags >> GlobalConstants.TILE_FLAG_BIT_FREEZE_UV) & 0x1)
		var depth_growth_mode: int = (flags >> GlobalConstants.TILE_FLAG_BIT_DEPTH_GROWTH_MODE) & 0x1
		var mesh_mode: int = (flags >> 22) & 0x3FF

		var spin_angle_rad: float = 0.0
		var tilt_angle_rad: float = 0.0
		var diagonal_scale: float = 0.0
		var tilt_offset_factor: float = 0.0
		var depth_scale: float = 1.0
		if tile_idx < tile_map_layer._tile_transform_indices.size():
			var transform_idx: int = tile_map_layer._tile_transform_indices[tile_idx]
			if transform_idx >= 0:
				var param_base: int = transform_idx * 5
				if param_base + 4 < tile_map_layer._tile_transform_data.size():
					spin_angle_rad = tile_map_layer._tile_transform_data[param_base]
					tilt_angle_rad = tile_map_layer._tile_transform_data[param_base + 1]
					diagonal_scale = tile_map_layer._tile_transform_data[param_base + 2]
					tilt_offset_factor = tile_map_layer._tile_transform_data[param_base + 3]
					depth_scale = tile_map_layer._tile_transform_data[param_base + 4]

		if tile_key < 0:
			tile_key = GlobalUtil.make_tile_key(grid_position, orientation)
		profile_info_ms += Time.get_ticks_msec() - profile_step_start

		profile_step_start = Time.get_ticks_msec()
		if not _tile_allows_collision_at_index(tile_map_layer, tile_idx, respect_tile_collision_custom_data, collision_custom_data_cache):
			profile_collision_filter_ms += Time.get_ticks_msec() - profile_step_start
			profile_tiles_filtered += 1
			continue
		profile_collision_filter_ms += Time.get_ticks_msec() - profile_step_start

		profile_step_start = Time.get_ticks_msec()
		var transform: Transform3D
		if tile_map_layer._tile_custom_transforms.has(tile_key):
			transform = tile_map_layer._tile_custom_transforms[tile_key]
		else:
			transform = GlobalUtil.build_tile_transform(
				grid_position,
				orientation,
				mesh_rotation,
				grid_size,
				is_face_flipped,
				spin_angle_rad,
				tilt_angle_rad,
				diagonal_scale,
				tilt_offset_factor,
				mesh_mode,
				depth_scale,
				depth_growth_mode == GlobalConstants.DepthGrowthMode.INWARD
			)
		transform.origin += GlobalUtil.calculate_flat_tile_offset(
			orientation, mesh_mode,
			tile_map_layer.settings.auto_resolve_box_z_fighting
		)
		var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
		var uv_rect_normalized: Rect2 = Rect2(uv_data.uv_min, uv_data.uv_max - uv_data.uv_min)
		var mesh_uv_rot: int = 0 if freeze_uv else mesh_rotation
		profile_transform_ms += Time.get_ticks_msec() - profile_step_start

		match mesh_mode:
			GlobalConstants.MeshMode.FLAT_TRIANGULE:
				profile_step_start = Time.get_ticks_msec()
				profile_triangle_count += 1
				var tri_start_v: int = vertices.size()
				dummy_uvs.resize(tri_start_v)
				dummy_normals.resize(tri_start_v)
				GlobalUtil.add_triangle_geometry(vertices, dummy_uvs, dummy_normals, indices, transform, uv_rect_normalized, grid_size)
				tiles_processed += 1
				total_vertices += vertices.size() - tri_start_v
				var tri_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += tri_elapsed
				profile_triangle_ms += tri_elapsed

			GlobalConstants.MeshMode.FLAT_SQUARE:
				profile_step_start = Time.get_ticks_msec()
				profile_square_count += 1
				var raw_uv: Rect2 = uv_rect
				var pixel_uv: Rect2 = raw_uv
				if raw_uv.size.x < 2.0 and raw_uv.size.y < 2.0:
					pixel_uv = Rect2(raw_uv.position * atlas_size, raw_uv.size * atlas_size)

				if pixel_uv.size.x < 1.0 or pixel_uv.size.y < 1.0:
					_add_square_collision_dynamic(vertices, indices, transform, grid_size)
					tiles_processed += 1
					total_vertices += 4
				else:
					var alpha_was_cached: bool = AlphaMeshGenerator.has_cached_mesh(pixel_uv)
					var alpha_start: int = Time.get_ticks_msec()
					var geom: Dictionary = AlphaMeshGenerator.generate_alpha_mesh(atlas_texture, pixel_uv, grid_size, 0.1, 2.0)
					profile_alpha_ms += Time.get_ticks_msec() - alpha_start
					if alpha_was_cached:
						profile_alpha_hits += 1
					else:
						profile_alpha_misses += 1

					if geom.success and geom.vertex_count > 0:
						var v_offset: int = vertices.size()
						var i_offset: int = indices.size()
						var geom_vertex_count: int = geom.vertices.size()
						var geom_index_count: int = geom.indices.size()
						var resize_start: int = Time.get_ticks_msec()
						vertices.resize(v_offset + geom_vertex_count)
						indices.resize(i_offset + geom_index_count)
						profile_resize_ms += Time.get_ticks_msec() - resize_start

						var copy_start: int = Time.get_ticks_msec()
						for i: int in range(geom_vertex_count):
							vertices[v_offset + i] = transform * geom.vertices[i]
						for i: int in range(geom_index_count):
							indices[i_offset + i] = v_offset + geom.indices[i]
						profile_copy_ms += Time.get_ticks_msec() - copy_start
						tiles_processed += 1
						total_vertices += geom.vertex_count
					elif not geom.success:
						_add_square_collision_dynamic(vertices, indices, transform, grid_size)
						tiles_processed += 1
						total_vertices += 4
				var square_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += square_elapsed
				profile_square_ms += square_elapsed

			GlobalConstants.MeshMode.BOX_MESH, GlobalConstants.MeshMode.PRISM_MESH, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER, GlobalConstants.MeshMode.FLAT_ARCH, \
			GlobalConstants.MeshMode.FLAT_ARCH_I, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
				profile_step_start = Time.get_ticks_msec()
				if mesh_mode == GlobalConstants.MeshMode.BOX_MESH:
					profile_box_count += 1
				elif mesh_mode == GlobalConstants.MeshMode.PRISM_MESH:
					profile_prism_count += 1
				else:
					profile_arch_count += 1

				var mesh_gen_start: int = Time.get_ticks_msec()
				var mesh_data: Dictionary = _get_base_mesh_data(base_mesh_data_cache, mesh_mode, grid_size, texture_repeat_mode, arch_radius_ratio)
				profile_mesh_gen_ms += Time.get_ticks_msec() - mesh_gen_start
				if mesh_data.is_empty():
					continue

				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()
				var src_vertices: PackedVector3Array = mesh_data["vertices"]
				var src_indices: PackedInt32Array = mesh_data["indices"]
				var resize_start: int = Time.get_ticks_msec()
				vertices.resize(v_offset + src_vertices.size())
				indices.resize(i_offset + src_indices.size())
				profile_resize_ms += Time.get_ticks_msec() - resize_start

				var copy_start: int = Time.get_ticks_msec()
				_add_mesh_data_to_arrays(
					vertices, dummy_uvs, dummy_normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, mesh_data,
					mesh_uv_rot, is_face_flipped, false
				)
				profile_copy_ms += Time.get_ticks_msec() - copy_start
				tiles_processed += 1
				total_vertices += src_vertices.size()

				var mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += mode_elapsed
				if mesh_mode == GlobalConstants.MeshMode.BOX_MESH:
					profile_box_ms += mode_elapsed
				elif mesh_mode == GlobalConstants.MeshMode.PRISM_MESH:
					profile_prism_ms += mode_elapsed
				else:
					profile_arch_ms += mode_elapsed

	if vertices.is_empty():
		return {"success": false, "error": "No collision-enabled tiles to merge", "empty_region": true}

	var mesh_create_start: int = Time.get_ticks_msec()
	var array_mesh: ArrayMesh = _create_collision_array_mesh(vertices, indices, tile_map_layer.name + "_alpha_collision")
	var mesh_create_ms: int = Time.get_ticks_msec() - mesh_create_start
	var collision_elapsed: int = Time.get_ticks_msec() - start_time
	if GlobalConstants.DEBUG_BAKE_PROFILE:
		print("[TileMeshMerger] collision_merge_detail mode=alpha_columnar region=%s scanned=%d processed=%d filtered=%d info_ms=%d collision_filter_ms=%d transform_ms=%d alpha_ms=%d alpha_hits=%d alpha_misses=%d append_ms=%d mesh_gen_ms=%d resize_ms=%d copy_ms=%d square_count=%d triangle_count=%d box_count=%d prism_count=%d arch_count=%d square_ms=%d triangle_ms=%d box_ms=%d prism_ms=%d arch_ms=%d mesh_create_ms=%d total_ms=%d vertices=%d indices=%d" % [
			str(region_chunk.region_key), profile_tiles_scanned, tiles_processed,
			profile_tiles_filtered, profile_info_ms, profile_collision_filter_ms,
			profile_transform_ms, profile_alpha_ms, profile_alpha_hits, profile_alpha_misses,
			profile_append_ms, profile_mesh_gen_ms, profile_resize_ms, profile_copy_ms,
			profile_square_count, profile_triangle_count, profile_box_count, profile_prism_count, profile_arch_count,
			profile_square_ms, profile_triangle_ms, profile_box_ms, profile_prism_ms, profile_arch_ms,
			mesh_create_ms, collision_elapsed, vertices.size(), indices.size()
		])
	return {
		"success": true,
		"mesh": array_mesh,
		"material": null,
		"stats": {
			"tile_count": tiles_processed,
			"vertex_count": total_vertices,
			"merge_time_ms": collision_elapsed
		}
	}


# --- Alpha-Aware Merge ---

## Alpha-aware baking: excludes transparent pixels using AlphaMeshGenerator.
static func _merge_alpha_aware(
	tile_map_layer: TileMapLayer3D,
	respect_tile_collision_custom_data: bool = false,
	indices_override: Array[int] = [],
	keys_override: Array[int] = [],
	region_chunk: TerrainRegionChunk = null,
	collision_only: bool = false
) -> Dictionary:
	var start_time: int = Time.get_ticks_msec()

	var atlas_texture: Texture2D = TileAtlasResolver.get_active_texture(tile_map_layer.settings)
	if not atlas_texture:
		return {"success": false, "error": "No tileset texture"}

	var atlas_size: Vector2 = atlas_texture.get_size()
	var grid_size: float = tile_map_layer.grid_size
	if collision_only and region_chunk != null:
		return _merge_alpha_aware_region_collision_columnar(tile_map_layer, respect_tile_collision_custom_data, region_chunk)
	var base_mesh_data_cache: Dictionary = {}

	# Pre-allocate arrays
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()

	var tiles_processed: int = 0
	var total_vertices: int = 0
	var profile_info_ms: int = 0
	var profile_collision_filter_ms: int = 0
	var profile_transform_ms: int = 0
	var profile_alpha_ms: int = 0
	var profile_append_ms: int = 0
	var profile_alpha_hits: int = 0
	var profile_alpha_misses: int = 0
	var profile_tiles_scanned: int = 0
	var profile_tiles_filtered: int = 0
	var profile_mesh_gen_ms: int = 0
	var profile_resize_ms: int = 0
	var profile_copy_ms: int = 0
	var profile_square_count: int = 0
	var profile_triangle_count: int = 0
	var profile_box_count: int = 0
	var profile_prism_count: int = 0
	var profile_arch_count: int = 0
	var profile_square_ms: int = 0
	var profile_triangle_ms: int = 0
	var profile_box_ms: int = 0
	var profile_prism_ms: int = 0
	var profile_arch_ms: int = 0

	var _indices_to_scan: PackedInt32Array
	if region_chunk != null:
		_indices_to_scan = PackedInt32Array(indices_override)
	else:
		_indices_to_scan = PackedInt32Array(range(tile_map_layer.get_tile_count()))

	# Process each tile (region-filtered or full map)
	for tile_idx: int in _indices_to_scan:
		profile_tiles_scanned += 1
		var profile_step_start: int = Time.get_ticks_msec()
		var tile_info: PlacedTileInfo = tile_map_layer.get_tile_info_at_index(tile_idx)
		profile_info_ms += Time.get_ticks_msec() - profile_step_start
		if tile_info == null:
			continue
		profile_step_start = Time.get_ticks_msec()
		if not _tile_allows_collision(tile_map_layer, tile_info, respect_tile_collision_custom_data):
			profile_collision_filter_ms += Time.get_ticks_msec() - profile_step_start
			profile_tiles_filtered += 1
			continue
		profile_collision_filter_ms += Time.get_ticks_msec() - profile_step_start

		# Check for custom transform (ramp/smart fill tiles bypass standard orientation)
		profile_step_start = Time.get_ticks_msec()
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
		profile_transform_ms += Time.get_ticks_msec() - profile_step_start

		match tile_info.mesh_mode:
			GlobalConstants.MeshMode.FLAT_TRIANGULE:
				profile_step_start = Time.get_ticks_msec()
				profile_triangle_count += 1
				# Add standard triangle geometry using shared utility
				GlobalUtil.add_triangle_geometry(
					vertices, uvs, normals, indices,
					transform, uv_rect_normalized, grid_size
				)
				tiles_processed += 1
				total_vertices += 3
				var profile_mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += profile_mode_elapsed
				profile_triangle_ms += profile_mode_elapsed

			GlobalConstants.MeshMode.BOX_MESH:
				profile_step_start = Time.get_ticks_msec()
				profile_box_count += 1
				# Use full box mesh (same as regular merge) - includes all 6 faces
				# This ensures proper collision and baked mesh generation
				# depth_scale is applied via transform, not mesh generation
				# Use texture_repeat_mode to select correct UV mapping
				var profile_mesh_gen_start: int = Time.get_ticks_msec()
				var box_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.BOX_MESH,
					grid_size,
					tile_info.texture_repeat_mode
				)
				profile_mesh_gen_ms += Time.get_ticks_msec() - profile_mesh_gen_start
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				# Extend arrays for box geometry (24 vertices, 36 indices)
				var profile_resize_start: int = Time.get_ticks_msec()
				vertices.resize(v_offset + 24)
				uvs.resize(v_offset + 24)
				normals.resize(v_offset + 24)
				indices.resize(i_offset + 36)
				profile_resize_ms += Time.get_ticks_msec() - profile_resize_start

				var profile_copy_start: int = Time.get_ticks_msec()
				_add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, box_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				profile_copy_ms += Time.get_ticks_msec() - profile_copy_start

				tiles_processed += 1
				total_vertices += 24
				var profile_mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += profile_mode_elapsed
				profile_box_ms += profile_mode_elapsed

			GlobalConstants.MeshMode.PRISM_MESH:
				profile_step_start = Time.get_ticks_msec()
				profile_prism_count += 1
				# Use full prism mesh (same as regular merge) - includes all faces
				# This ensures proper collision and baked mesh generation
				# depth_scale is applied via transform, not mesh generation
				# Use texture_repeat_mode to select correct UV mapping
				var profile_mesh_gen_start: int = Time.get_ticks_msec()
				var prism_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.PRISM_MESH,
					grid_size,
					tile_info.texture_repeat_mode
				)
				profile_mesh_gen_ms += Time.get_ticks_msec() - profile_mesh_gen_start
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				# Extend arrays for prism geometry (24 vertices, 24 indices)
				var profile_resize_start: int = Time.get_ticks_msec()
				vertices.resize(v_offset + 24)
				uvs.resize(v_offset + 24)
				normals.resize(v_offset + 24)
				indices.resize(i_offset + 24)
				profile_resize_ms += Time.get_ticks_msec() - profile_resize_start

				var profile_copy_start: int = Time.get_ticks_msec()
				_add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, prism_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				profile_copy_ms += Time.get_ticks_msec() - profile_copy_start

				tiles_processed += 1
				total_vertices += 24
				var profile_mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += profile_mode_elapsed
				profile_prism_ms += profile_mode_elapsed

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
				profile_step_start = Time.get_ticks_msec()
				profile_arch_count += 1
				# Generate arch corner mesh and add to arrays (same as regular merge)
				var arch_corner_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_ratio = tile_map_layer.settings.arch_radius_ratio
				var profile_mesh_gen_start: int = Time.get_ticks_msec()
				var arch_corner_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_corner_ratio
				)
				profile_mesh_gen_ms += Time.get_ticks_msec() - profile_mesh_gen_start
				var arch_corner_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_corner_vert_count: int = arch_corner_quads * 6
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				var profile_resize_start: int = Time.get_ticks_msec()
				vertices.resize(v_offset + arch_corner_vert_count)
				uvs.resize(v_offset + arch_corner_vert_count)
				normals.resize(v_offset + arch_corner_vert_count)
				indices.resize(i_offset + arch_corner_vert_count)
				profile_resize_ms += Time.get_ticks_msec() - profile_resize_start

				var profile_copy_start: int = Time.get_ticks_msec()
				_add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, arch_corner_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				profile_copy_ms += Time.get_ticks_msec() - profile_copy_start

				tiles_processed += 1
				total_vertices += arch_corner_vert_count
				var profile_mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += profile_mode_elapsed
				profile_arch_ms += profile_mode_elapsed

			GlobalConstants.MeshMode.FLAT_ARCH:
				profile_step_start = Time.get_ticks_msec()
				profile_arch_count += 1
				# Generate arch mesh and add to arrays
				var arch_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_ratio = tile_map_layer.settings.arch_radius_ratio
				var profile_mesh_gen_start: int = Time.get_ticks_msec()
				var arch_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_ratio
				)
				profile_mesh_gen_ms += Time.get_ticks_msec() - profile_mesh_gen_start
				var arch_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_vert_count: int = arch_quads * 6
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				var profile_resize_start: int = Time.get_ticks_msec()
				vertices.resize(v_offset + arch_vert_count)
				uvs.resize(v_offset + arch_vert_count)
				normals.resize(v_offset + arch_vert_count)
				indices.resize(i_offset + arch_vert_count)
				profile_resize_ms += Time.get_ticks_msec() - profile_resize_start

				var profile_copy_start: int = Time.get_ticks_msec()
				_add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, arch_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				profile_copy_ms += Time.get_ticks_msec() - profile_copy_start

				tiles_processed += 1
				total_vertices += arch_vert_count
				var profile_mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += profile_mode_elapsed
				profile_arch_ms += profile_mode_elapsed

			GlobalConstants.MeshMode.FLAT_ARCH_I:
				profile_step_start = Time.get_ticks_msec()
				profile_arch_count += 1
				# Generate arch-I mesh and add to arrays
				var arch_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var profile_mesh_gen_start: int = Time.get_ticks_msec()
				var arch_i_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_I,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_i_ratio
				)
				profile_mesh_gen_ms += Time.get_ticks_msec() - profile_mesh_gen_start
				var arch_i_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_i_vert_count: int = arch_i_quads * 6
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				var profile_resize_start: int = Time.get_ticks_msec()
				vertices.resize(v_offset + arch_i_vert_count)
				uvs.resize(v_offset + arch_i_vert_count)
				normals.resize(v_offset + arch_i_vert_count)
				indices.resize(i_offset + arch_i_vert_count)
				profile_resize_ms += Time.get_ticks_msec() - profile_resize_start

				var profile_copy_start: int = Time.get_ticks_msec()
				_add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, arch_i_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				profile_copy_ms += Time.get_ticks_msec() - profile_copy_start

				tiles_processed += 1
				total_vertices += arch_i_vert_count
				var profile_mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += profile_mode_elapsed
				profile_arch_ms += profile_mode_elapsed

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
				profile_step_start = Time.get_ticks_msec()
				profile_arch_count += 1
				# Generate arch-corner-I mesh and add to arrays
				var arch_corner_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var profile_mesh_gen_start: int = Time.get_ticks_msec()
				var arch_corner_i_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_corner_i_ratio
				)
				profile_mesh_gen_ms += Time.get_ticks_msec() - profile_mesh_gen_start
				var arch_corner_i_quads: int = 1 + GlobalConstants.ARCH_ARC_SEGMENTS
				var arch_corner_i_vert_count: int = arch_corner_i_quads * 6
				var v_offset: int = vertices.size()
				var i_offset: int = indices.size()

				var profile_resize_start: int = Time.get_ticks_msec()
				vertices.resize(v_offset + arch_corner_i_vert_count)
				uvs.resize(v_offset + arch_corner_i_vert_count)
				normals.resize(v_offset + arch_corner_i_vert_count)
				indices.resize(i_offset + arch_corner_i_vert_count)
				profile_resize_ms += Time.get_ticks_msec() - profile_resize_start

				var profile_copy_start: int = Time.get_ticks_msec()
				_add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					v_offset, i_offset,
					transform, uv_rect_normalized, arch_corner_i_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				profile_copy_ms += Time.get_ticks_msec() - profile_copy_start

				tiles_processed += 1
				total_vertices += arch_corner_i_vert_count
				var profile_mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += profile_mode_elapsed
				profile_arch_ms += profile_mode_elapsed

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
				profile_step_start = Time.get_ticks_msec()
				profile_arch_count += 1
				# Generate arch-corner-cap mesh and add to arrays
				var arch_corner_cap_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_ratio = tile_map_layer.settings.arch_radius_ratio
				var profile_mesh_gen_start: int = Time.get_ticks_msec()
				var arch_corner_cap_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_corner_cap_ratio
				)
				profile_mesh_gen_ms += Time.get_ticks_msec() - profile_mesh_gen_start
				var arch_corner_cap_vert_count: int = (2 + GlobalConstants.ARCH_ARC_SEGMENTS) * 3
				var v_offset6: int = vertices.size()
				var i_offset6: int = indices.size()

				var profile_resize_start: int = Time.get_ticks_msec()
				vertices.resize(v_offset6 + arch_corner_cap_vert_count)
				uvs.resize(v_offset6 + arch_corner_cap_vert_count)
				normals.resize(v_offset6 + arch_corner_cap_vert_count)
				indices.resize(i_offset6 + arch_corner_cap_vert_count)
				profile_resize_ms += Time.get_ticks_msec() - profile_resize_start

				var profile_copy_start: int = Time.get_ticks_msec()
				_add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					v_offset6, i_offset6,
					transform, uv_rect_normalized, arch_corner_cap_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				profile_copy_ms += Time.get_ticks_msec() - profile_copy_start

				tiles_processed += 1
				total_vertices += arch_corner_cap_vert_count
				var profile_mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += profile_mode_elapsed
				profile_arch_ms += profile_mode_elapsed

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
				profile_step_start = Time.get_ticks_msec()
				profile_arch_count += 1
				# Generate arch-corner-cap-I mesh and add to arrays
				var arch_corner_cap_i_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_i_ratio = tile_map_layer.settings.arch_radius_ratio
				var profile_mesh_gen_start: int = Time.get_ticks_msec()
				var arch_corner_cap_i_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_corner_cap_i_ratio
				)
				profile_mesh_gen_ms += Time.get_ticks_msec() - profile_mesh_gen_start
				var arch_corner_cap_i_vert_count: int = GlobalConstants.ARCH_ARC_SEGMENTS * 3
				var v_offset7: int = vertices.size()
				var i_offset7: int = indices.size()

				var profile_resize_start: int = Time.get_ticks_msec()
				vertices.resize(v_offset7 + arch_corner_cap_i_vert_count)
				uvs.resize(v_offset7 + arch_corner_cap_i_vert_count)
				normals.resize(v_offset7 + arch_corner_cap_i_vert_count)
				indices.resize(i_offset7 + arch_corner_cap_i_vert_count)
				profile_resize_ms += Time.get_ticks_msec() - profile_resize_start

				var profile_copy_start: int = Time.get_ticks_msec()
				_add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					v_offset7, i_offset7,
					transform, uv_rect_normalized, arch_corner_cap_i_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				profile_copy_ms += Time.get_ticks_msec() - profile_copy_start

				tiles_processed += 1
				total_vertices += arch_corner_cap_i_vert_count
				var profile_mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += profile_mode_elapsed
				profile_arch_ms += profile_mode_elapsed

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
				profile_step_start = Time.get_ticks_msec()
				profile_arch_count += 1
				# Generate arch-corner-cap-duo mesh and add to arrays
				var arch_corner_cap_duo_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					arch_corner_cap_duo_ratio = tile_map_layer.settings.arch_radius_ratio
				var profile_mesh_gen_start: int = Time.get_ticks_msec()
				var arch_corner_cap_duo_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO,
					grid_size,
					tile_info.texture_repeat_mode,
					arch_corner_cap_duo_ratio
				)
				profile_mesh_gen_ms += Time.get_ticks_msec() - profile_mesh_gen_start
				var arch_corner_cap_duo_vert_count: int = (2 + 2 * GlobalConstants.ARCH_ARC_SEGMENTS) * 3
				var v_offset_duo: int = vertices.size()
				var i_offset_duo: int = indices.size()

				var profile_resize_start: int = Time.get_ticks_msec()
				vertices.resize(v_offset_duo + arch_corner_cap_duo_vert_count)
				uvs.resize(v_offset_duo + arch_corner_cap_duo_vert_count)
				normals.resize(v_offset_duo + arch_corner_cap_duo_vert_count)
				indices.resize(i_offset_duo + arch_corner_cap_duo_vert_count)
				profile_resize_ms += Time.get_ticks_msec() - profile_resize_start

				var profile_copy_start: int = Time.get_ticks_msec()
				_add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					v_offset_duo, i_offset_duo,
					transform, uv_rect_normalized, arch_corner_cap_duo_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				profile_copy_ms += Time.get_ticks_msec() - profile_copy_start

				tiles_processed += 1
				total_vertices += arch_corner_cap_duo_vert_count
				var profile_mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += profile_mode_elapsed
				profile_arch_ms += profile_mode_elapsed

			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S, \
			GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
				profile_step_start = Time.get_ticks_msec()
				profile_arch_count += 1
				# Generate double-arc mesh using settings radius
				var da_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
				if tile_map_layer.settings:
					da_ratio = tile_map_layer.settings.arch_radius_ratio
				var da_mode: int = tile_info.mesh_mode
				var profile_mesh_gen_start: int = Time.get_ticks_msec()
				var da_data: Dictionary = _get_base_mesh_data(
					base_mesh_data_cache,
					da_mode,
					grid_size,
					tile_info.texture_repeat_mode,
					da_ratio
				)
				profile_mesh_gen_ms += Time.get_ticks_msec() - profile_mesh_gen_start
				var da_quads: int = 2 * GlobalConstants.ARCH_ARC_SEGMENTS + 1
				var da_vert_count: int = da_quads * 6
				var v_offset_da: int = vertices.size()
				var i_offset_da: int = indices.size()

				var profile_resize_start: int = Time.get_ticks_msec()
				vertices.resize(v_offset_da + da_vert_count)
				uvs.resize(v_offset_da + da_vert_count)
				normals.resize(v_offset_da + da_vert_count)
				indices.resize(i_offset_da + da_vert_count)
				profile_resize_ms += Time.get_ticks_msec() - profile_resize_start

				var profile_copy_start: int = Time.get_ticks_msec()
				_add_mesh_data_to_arrays(
					vertices, uvs, normals, indices,
					v_offset_da, i_offset_da,
					transform, uv_rect_normalized, da_data,
					mesh_uv_rot, tile_info.is_face_flipped, not collision_only
				)
				profile_copy_ms += Time.get_ticks_msec() - profile_copy_start

				tiles_processed += 1
				total_vertices += da_vert_count
				var profile_mode_elapsed: int = Time.get_ticks_msec() - profile_step_start
				profile_append_ms += profile_mode_elapsed
				profile_arch_ms += profile_mode_elapsed

			GlobalConstants.MeshMode.FLAT_SQUARE, _:
				profile_square_count += 1
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
					profile_step_start = Time.get_ticks_msec()
					var fallback_uv: Rect2 = uv_rect_normalized if uv_rect_normalized.has_area() else Rect2(Vector2.ZERO, Vector2.ONE)
					_add_square_dynamic(vertices, uvs, normals, indices, transform, fallback_uv, grid_size)
					tiles_processed += 1
					total_vertices += 4
					var profile_square_fallback_elapsed: int = Time.get_ticks_msec() - profile_step_start
					profile_append_ms += profile_square_fallback_elapsed
					profile_square_ms += profile_square_fallback_elapsed
					continue

				# Generate alpha-aware geometry using BitMap API (for square tiles)
				var alpha_was_cached: bool = AlphaMeshGenerator.has_cached_mesh(pixel_uv)
				profile_step_start = Time.get_ticks_msec()
				var geom: Dictionary = AlphaMeshGenerator.generate_alpha_mesh(
					atlas_texture,
					pixel_uv,
					grid_size,
					0.1,  # alpha_threshold
					2.0   # epsilon (simplification)
				)
				profile_alpha_ms += Time.get_ticks_msec() - profile_step_start
				if alpha_was_cached:
					profile_alpha_hits += 1
				else:
					profile_alpha_misses += 1

				if geom.success and geom.vertex_count > 0:
					# Add geometry to arrays
					profile_step_start = Time.get_ticks_msec()
					var v_offset: int = vertices.size()
					var i_offset: int = indices.size()
					var geom_vertex_count: int = geom.vertices.size()
					var geom_index_count: int = geom.indices.size()

					var profile_resize_start: int = Time.get_ticks_msec()
					vertices.resize(v_offset + geom_vertex_count)
					uvs.resize(v_offset + geom_vertex_count)
					normals.resize(v_offset + geom_vertex_count)
					indices.resize(i_offset + geom_index_count)
					profile_resize_ms += Time.get_ticks_msec() - profile_resize_start

					var profile_copy_start: int = Time.get_ticks_msec()
					for i: int in range(geom_vertex_count):
						vertices[v_offset + i] = transform * geom.vertices[i]
						uvs[v_offset + i] = geom.uvs[i]
						normals[v_offset + i] = transform.basis * geom.normals[i]

					for i: int in range(geom_index_count):
						indices[i_offset + i] = v_offset + geom.indices[i]
					profile_copy_ms += Time.get_ticks_msec() - profile_copy_start

					tiles_processed += 1
					total_vertices += geom.vertex_count
					var profile_square_elapsed: int = Time.get_ticks_msec() - profile_step_start
					profile_append_ms += profile_square_elapsed
					profile_square_ms += profile_square_elapsed
				elif not geom.success:
					profile_step_start = Time.get_ticks_msec()
					var fallback_uv: Rect2 = uv_rect_normalized if uv_rect_normalized.has_area() else Rect2(Vector2.ZERO, Vector2.ONE)
					_add_square_dynamic(vertices, uvs, normals, indices, transform, fallback_uv, grid_size)
					tiles_processed += 1
					total_vertices += 4
					var profile_square_failure_elapsed: int = Time.get_ticks_msec() - profile_step_start
					profile_append_ms += profile_square_failure_elapsed
					profile_square_ms += profile_square_failure_elapsed

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

	var array_mesh: ArrayMesh
	if collision_only:
		var mesh_create_start: int = Time.get_ticks_msec()
		array_mesh = _create_collision_array_mesh(vertices, indices, tile_map_layer.name + "_alpha_collision")
		var mesh_create_ms: int = Time.get_ticks_msec() - mesh_create_start
		var collision_elapsed: int = Time.get_ticks_msec() - start_time
		if GlobalConstants.DEBUG_BAKE_PROFILE:
			print("[TileMeshMerger] collision_merge_detail mode=alpha region=%s scanned=%d processed=%d filtered=%d info_ms=%d collision_filter_ms=%d transform_ms=%d alpha_ms=%d alpha_hits=%d alpha_misses=%d append_ms=%d mesh_gen_ms=%d resize_ms=%d copy_ms=%d square_count=%d triangle_count=%d box_count=%d prism_count=%d arch_count=%d square_ms=%d triangle_ms=%d box_ms=%d prism_ms=%d arch_ms=%d mesh_create_ms=%d total_ms=%d vertices=%d indices=%d" % [
				str(region_chunk.region_key if region_chunk != null else Vector3i.MAX),
				profile_tiles_scanned,
				tiles_processed,
				profile_tiles_filtered,
				profile_info_ms,
				profile_collision_filter_ms,
				profile_transform_ms,
				profile_alpha_ms,
				profile_alpha_hits,
				profile_alpha_misses,
				profile_append_ms,
				profile_mesh_gen_ms,
				profile_resize_ms,
				profile_copy_ms,
				profile_square_count,
				profile_triangle_count,
				profile_box_count,
				profile_prism_count,
				profile_arch_count,
				profile_square_ms,
				profile_triangle_ms,
				profile_box_ms,
				profile_prism_ms,
				profile_arch_ms,
				mesh_create_ms,
				collision_elapsed,
				vertices.size(),
				indices.size()
			])
		return {
			"success": true,
			"mesh": array_mesh,
			"material": null,
			"stats": {
				"tile_count": tiles_processed,
				"vertex_count": total_vertices,
				"merge_time_ms": collision_elapsed
			}
		}

	# Create ArrayMesh using GlobalUtil
	array_mesh = GlobalUtil.create_array_mesh_from_arrays(
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
