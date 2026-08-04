class_name TilePlacementManager
extends RefCounted

var grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE
var tile_world_size: Vector2 = Vector2(1.0, 1.0)
var grid_snap_size: float = GlobalConstants.DEFAULT_GRID_SNAP_SIZE

var active_tile_map_layer3d: TileMapLayer3D = null
var tileset_texture: Texture2D = null
var current_tile_uv: Rect2 = Rect2()
# Sentinel (-1, Vector2i(-1, -1)) means freeform — no atlas binding.
var current_atlas_source_id: int = -1
var current_atlas_coords: Vector2i = Vector2i(-1, -1)
var current_mesh_rotation: int = 0
var is_current_face_flipped: bool = false
var auto_detect_orientation: bool = false
var current_depth_scale: float = 0.1
var current_texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT
var current_depth_growth_mode: int = GlobalConstants.DepthGrowthMode.OUTWARD
var current_terrain_id: int = GlobalConstants.AUTOTILE_NO_TERRAIN
var current_freeze_uv: bool = false
var current_anim_step_x: float = 0.0
var current_anim_step_y: float = 0.0
var current_anim_total_frames: int = 1
var current_anim_columns: int = 1
var current_anim_speed_fps: float = 0.0

var multi_tile_selection: Array[Rect2] = []
var multi_tile_anchor_index: int = 0
# Parallel atlas bindings for `multi_tile_selection`; same length and order. Sentinel = freeform.
var multi_tile_atlas_source_ids: Array[int] = []
var multi_tile_atlas_coords: Array[Vector2i] = []

var texture_filter_mode: int = GlobalConstants.DEFAULT_TEXTURE_FILTER

enum PlacementMode {
	CURSOR_PLANE,
	CURSOR,
	RAYCAST,
}
var placement_mode: PlacementMode = PlacementMode.CURSOR_PLANE
var cursor_3d: TileCursor3D = null

var _paint_stroke_undo_redo: Object = null
var _paint_stroke_active: bool = false

# Depth counter, not a bool, so nested begin/end pairs don't flush the GPU prematurely.
var _batch_depth: int = 0
var _pending_chunk_cleanups: Array[TileChunkRender] = []

var _spatial_index: SpatialIndex = SpatialIndex.new()

func remove_tile_everywhere(tile_key: int) -> void:
	if active_tile_map_layer3d and active_tile_map_layer3d.has_tile(tile_key):
		_remove_tile_from_multimesh(tile_key)
		active_tile_map_layer3d.remove_saved_tile_data(tile_key)
	_spatial_index.remove_tile(tile_key)


## Emergency recovery for aborted batch operations; normally balance begin/end instead.
func reset_batch_update_state() -> void:
	_batch_depth = 0
	_pending_chunk_cleanups.clear()


func get_batch_debug_state() -> Dictionary:
	return {
		"depth": _batch_depth,
		"pending_cleanups": _pending_chunk_cleanups.size()
	}


func get_spatial_index_tile_keys() -> Array:
	return _spatial_index.get_tile_keys()

func set_texture_filter(filter_mode: int) -> void:
	if filter_mode < 0 or filter_mode > GlobalConstants.MAX_TEXTURE_FILTER_MODE:
		push_warning("Invalid texture filter mode: ", filter_mode)
		return

	texture_filter_mode = filter_mode

	if active_tile_map_layer3d:
		active_tile_map_layer3d.texture_filter_mode = filter_mode
		active_tile_map_layer3d._update_material()


## Returns [source_id, coords] for uv_rect, preserving the binding decided at selection time.
func _binding_for_uv_rect(uv_rect: Rect2) -> Array:
	if uv_rect == current_tile_uv and current_atlas_source_id >= 0:
		return [current_atlas_source_id, current_atlas_coords]
	var n: int = mini(multi_tile_selection.size(), multi_tile_atlas_source_ids.size())
	for i in range(n):
		if multi_tile_selection[i] == uv_rect:
			return [multi_tile_atlas_source_ids[i], multi_tile_atlas_coords[i]]
	return [-1, Vector2i(-1, -1)]


## Authoritative factory for a NEW tile's PlacedTileInfo; use in all placement modes.
func create_tile_info(grid_pos: Vector3, uv_rect: Rect2, orientation: int,
		mesh_rotation: int, is_flipped: bool, mesh_mode: int,
		terrain_id: int = GlobalConstants.AUTOTILE_NO_TERRAIN,
		custom_transform: Transform3D = Transform3D(),
		has_custom_transform: bool = false) -> PlacedTileInfo:
	var binding: Array = _binding_for_uv_rect(uv_rect)
	var tile_info := PlacedTileInfo.new()
	tile_info.tile_key = GlobalUtil.make_tile_key(grid_pos, orientation)
	tile_info.grid_position = grid_pos
	tile_info.uv_rect = uv_rect
	tile_info.orientation = orientation
	tile_info.mesh_rotation = mesh_rotation
	tile_info.is_face_flipped = is_flipped
	tile_info.mesh_mode = mesh_mode
	tile_info.terrain_id = terrain_id if terrain_id != GlobalConstants.AUTOTILE_NO_TERRAIN else current_terrain_id
	tile_info.depth_scale = current_depth_scale
	tile_info.texture_repeat_mode = current_texture_repeat_mode
	tile_info.freeze_uv = current_freeze_uv
	tile_info.depth_growth_mode = current_depth_growth_mode
	tile_info.anim_step_x = current_anim_step_x
	tile_info.anim_step_y = current_anim_step_y
	tile_info.anim_total_frames = current_anim_total_frames
	tile_info.anim_columns = current_anim_columns
	tile_info.anim_speed_fps = current_anim_speed_fps
	tile_info.atlas_source_id = binding[0]
	tile_info.atlas_coords = binding[1]
	tile_info.custom_transform = custom_transform
	tile_info.has_custom_transform = has_custom_transform

	if orientation >= 6:
		tile_info.spin_angle_rad = GlobalConstants.SPIN_ANGLE_RAD
		tile_info.tilt_angle_rad = GlobalConstants.TILT_ANGLE_RAD
		tile_info.diagonal_scale = GlobalConstants.DIAGONAL_SCALE_FACTOR
		tile_info.tilt_offset_factor = GlobalConstants.TILT_POSITION_OFFSET_FACTOR
	else:
		tile_info.spin_angle_rad = 0.0
		tile_info.tilt_angle_rad = 0.0
		tile_info.diagonal_scale = 0.0
		tile_info.tilt_offset_factor = 0.0

	return tile_info


func _get_existing_tile_info(tile_key: int) -> PlacedTileInfo:
	if not active_tile_map_layer3d:
		return null

	var index: int = active_tile_map_layer3d.get_tile_index(tile_key)
	if index < 0:
		return null

	return active_tile_map_layer3d.get_tile_info_at_index(index)


## Batch update mode; nestable — every begin needs a matching end.
func begin_batch_update() -> void:
	_batch_depth += 1

	if _batch_depth == 1:
		_pending_chunk_cleanups.clear()
		if GlobalConstants.DEBUG_BATCH_UPDATES:
			print("BEGIN BATCH (depth=%d) - Cleared pending cleanups" % _batch_depth)
	else:
		if GlobalConstants.DEBUG_BATCH_UPDATES:
			print("BEGIN BATCH (depth=%d) - Nested call" % _batch_depth)

func end_batch_update() -> void:
	if _batch_depth <= 0:
		push_warning("end_batch_update() called without matching begin_batch_update() - STATE CORRUPTION DETECTED!")
		_batch_depth = 0
		return

	_batch_depth -= 1

	if GlobalConstants.DEBUG_BATCH_UPDATES:
		print("END BATCH (depth=%d) - %d chunk cleanups pending" % [_batch_depth, _pending_chunk_cleanups.size()])

	if _batch_depth == 0:
		if GlobalConstants.DEBUG_BATCH_UPDATES:
			print("BATCH COMPLETE")

		# Deferred to end-of-batch to avoid mid-op chunk reindexing.
		var chunks_removed: int = 0
		for chunk in _pending_chunk_cleanups:
			if chunk and chunk.tile_count == 0:
				_cleanup_empty_chunk_internal(chunk)
				chunks_removed += 1

		_pending_chunk_cleanups.clear()

		if GlobalConstants.DEBUG_CHUNK_MANAGEMENT and chunks_removed > 0:
			print("BATCH CLEANUP - Removed %d empty chunks" % chunks_removed)

func _validate_data_structure_integrity() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var columnar_tile_count: int = active_tile_map_layer3d.get_tile_count() if active_tile_map_layer3d else 0
	var stats: Dictionary = {
		"columnar_tile_count": columnar_tile_count,
		"spatial_index_size": _spatial_index.size(),
		"total_chunk_refs": 0,
		"errors_found": 0,
		"warnings_found": 0
	}

	for i in range(columnar_tile_count):
		var tile_info: PlacedTileInfo = active_tile_map_layer3d.get_tile_info_at_index(i)
		if tile_info == null:
			continue

		var grid_pos: Vector3 = tile_info.grid_position
		var orientation: int = tile_info.orientation
		var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

		var tile_ref: TileMapLayer3D.TileRef = active_tile_map_layer3d.get_tile_ref(tile_key)

		if not tile_ref:
			errors.append("Tile key %d exists in columnar storage but has no TileRef" % tile_key)
			continue

		var chunk: TileChunkRender = active_tile_map_layer3d._get_chunk_by_ref(tile_ref)

		if not chunk:
			errors.append("Tile key %d has invalid chunk reference (chunk_index=%d, region=%d, mesh_mode=%d)" % [tile_key, tile_ref.chunk_index, tile_ref.region_key_packed, tile_ref.mesh_mode])
			continue

		if not chunk.tile_refs.has(tile_key):
			errors.append("Tile key %d exists in columnar storage but NOT in chunk.tile_refs (chunk_index=%d)" % [tile_key, tile_ref.chunk_index])

	var all_chunks: Array = active_tile_map_layer3d._get_all_chunks()

	for chunk in all_chunks:
		if not chunk:
			continue

		stats.total_chunk_refs += chunk.tile_refs.size()

		for tile_key in chunk.tile_refs:
			if not active_tile_map_layer3d.has_tile(tile_key):
				errors.append("Tile key %d exists in chunk.tile_refs but NOT in columnar storage" % tile_key)

			var instance_index: int = chunk.tile_refs[tile_key]
			if not chunk.instance_to_key.has(instance_index):
				errors.append("Tile key %d has instance %d in tile_refs but NOT in instance_to_key" % [tile_key, instance_index])
			elif chunk.instance_to_key[instance_index] != tile_key:
				errors.append("Bidirectional mapping broken: tile_refs[%d]=%d but instance_to_key[%d]=%d" % [
					tile_key, instance_index, instance_index, chunk.instance_to_key[instance_index]
				])

	if _spatial_index.size() != columnar_tile_count:
		warnings.append("Spatial index size (%d) doesn't match columnar tile count (%d) - may need rebuild" % [
			_spatial_index.size(), columnar_tile_count
		])

	stats["quad_chunks_count"] = active_tile_map_layer3d._count_chunks_in_registry(active_tile_map_layer3d._chunk_registry_quad)
	stats["triangle_chunks_count"] = active_tile_map_layer3d._count_chunks_in_registry(active_tile_map_layer3d._chunk_registry_triangle)
	stats["box_chunks_count"] = active_tile_map_layer3d._count_chunks_in_registry(active_tile_map_layer3d._chunk_registry_box)
	stats["prism_chunks_count"] = active_tile_map_layer3d._count_chunks_in_registry(active_tile_map_layer3d._chunk_registry_prism)
	stats["chunk_index_mismatches"] = 0

	for registry: Dictionary in active_tile_map_layer3d._get_all_chunk_registries():
		for region_key_packed: int in registry.keys():
			var region_chunks: Array = registry[region_key_packed]
			for i in range(region_chunks.size()):
				var chunk: TileChunkRender = region_chunks[i]
				if not chunk:
					errors.append("Chunk at region %d index %d is invalid (freed or null)" % [region_key_packed, i])
					continue

				if chunk.chunk_index != i:
					errors.append("Chunk index mismatch: registry[%d][%d] but chunk.chunk_index=%d" % [region_key_packed, i, chunk.chunk_index])
					stats.chunk_index_mismatches += 1

				if chunk.region_key_packed != region_key_packed:
					errors.append("Chunk region mismatch: registry key=%d but chunk.region_key_packed=%d" % [region_key_packed, chunk.region_key_packed])

				for tile_key in chunk.tile_refs.keys():
					var tile_ref: TileMapLayer3D.TileRef = active_tile_map_layer3d.get_tile_ref(tile_key)
					if tile_ref and (tile_ref.chunk_index != i or tile_ref.region_key_packed != region_key_packed):
						errors.append("Tile key %d in registry[%d][%d] but TileRef points to region=%d chunk_index=%d" % [
							tile_key, region_key_packed, i, tile_ref.region_key_packed, tile_ref.chunk_index
						])

	var empty_chunks: int = 0
	for chunk in all_chunks:
		if chunk and chunk.tile_count == 0:
			empty_chunks += 1
			warnings.append("Empty chunk detected: chunk_index=%d mesh_mode=%d (should be cleaned up)" % [chunk.chunk_index, chunk.mesh_mode_type])

	stats["empty_chunks_found"] = empty_chunks

	var orphaned_refs: int = 0
	for tile_key in active_tile_map_layer3d._tile_lookup.keys():
		var tile_ref: TileMapLayer3D.TileRef = active_tile_map_layer3d._tile_lookup[tile_key]

		var chunk: TileChunkRender = active_tile_map_layer3d._get_chunk_by_ref(tile_ref)
		if not chunk:
			errors.append("ORPHANED: TileRef key=%d has invalid registry reference (mesh_mode=%d texture_repeat=%d region=%d chunk_index=%d)" %
						  [tile_key, tile_ref.mesh_mode, tile_ref.texture_repeat_mode, tile_ref.region_key_packed, tile_ref.chunk_index])
			orphaned_refs += 1

	stats["orphaned_refs_found"] = orphaned_refs

	if orphaned_refs > 0:
		errors.append("🔥   Found %d orphaned TileRefs - these point to removed/invalid chunks!" % orphaned_refs)

	stats.errors_found = errors.size()
	stats.warnings_found = warnings.size()

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"stats": stats
	}


func _is_in_bounds(pos: Vector3, min_b: Vector3, max_b: Vector3, tolerance: float = 0.0) -> bool:
	return (
		pos.x >= min_b.x - tolerance and pos.x <= max_b.x + tolerance and
		pos.y >= min_b.y - tolerance and pos.y <= max_b.y + tolerance and
		pos.z >= min_b.z - tolerance and pos.z <= max_b.z + tolerance
	)


## Unified grid snapping (Single Source of Truth).
## plane_normal=ZERO snaps all axes; UP/RIGHT/FORWARD only snaps axes parallel to that plane.
## snap_size defaults to grid_snap_size; minimum 0.5 (half-grid).
func snap_to_grid(grid_pos: Vector3, plane_normal: Vector3 = Vector3.ZERO, snap_size: float = -1.0) -> Vector3:
	var resolution: float = snap_size if snap_size > 0.0 else grid_snap_size

	if plane_normal == Vector3.ZERO:
		var max_range: float = GlobalConstants.MAX_GRID_RANGE
		return Vector3(
			clampf(snappedf(grid_pos.x, resolution), -max_range, max_range),
			clampf(snappedf(grid_pos.y, resolution), -max_range, max_range),
			clampf(snappedf(grid_pos.z, resolution), -max_range, max_range)
		)

	var snapped: Vector3 = grid_pos

	if plane_normal == Vector3.UP:
		snapped.x = snappedf(grid_pos.x, resolution)
		snapped.z = snappedf(grid_pos.z, resolution)
	elif plane_normal == Vector3.RIGHT:
		snapped.y = snappedf(grid_pos.y, resolution)
		snapped.z = snappedf(grid_pos.z, resolution)
	else:
		snapped.x = snappedf(grid_pos.x, resolution)
		snapped.y = snappedf(grid_pos.y, resolution)

	var max_range: float = GlobalConstants.MAX_GRID_RANGE
	snapped.x = clampf(snapped.x, -max_range, max_range)
	snapped.y = clampf(snapped.y, -max_range, max_range)
	snapped.z = clampf(snapped.z, -max_range, max_range)

	return snapped

## Consolidated CURSOR_PLANE calculation (Single Source of Truth).
## Raycasts, auto-detects plane/orientation, applies selective snapping.
## Returns Dictionary: "grid_pos", "orientation", "active_plane".
func calculate_cursor_plane_placement(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	if not cursor_3d:
		push_warning("calculate_cursor_plane_placement: No cursor_3d reference")
		return {}

	var raw_pos: Vector3 = _raycast_to_cursor_plane(camera, screen_pos)

	var active_plane: Vector3 = GlobalPlaneDetector.detect_active_plane_3d(camera)

	var orientation: GlobalUtil.TileOrientation = GlobalPlaneDetector.detect_orientation_from_cursor_plane(active_plane, camera)

	var grid_pos: Vector3 = snap_to_grid(raw_pos, active_plane)

	return {
		"grid_pos": grid_pos,
		"orientation": orientation,
		"active_plane": active_plane
	}

func calculate_3d_world_position(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	if not cursor_3d:
		push_warning("calculate_3d_world_position: No cursor_3d reference")
		return {}

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	# Problem: Using camera.distance_to(cursor) causes selection box to "float" upward
	# as mouse moves, because ray direction changes but distance stays constant
	# Solution: Intersect ray with cursor's active PLANE at consistent depth
	var cursor_world_pos: Vector3 = cursor_3d.get_world_position()
	var plane_normal: Vector3 = cursor_3d.get_plane_normal()

	var denominator: float = ray_dir.dot(plane_normal)

	var world_pos: Vector3
	if abs(denominator) < 0.0001:
		var camera_to_cursor_dist: float = camera.global_position.distance_to(cursor_world_pos)
		world_pos = ray_origin + ray_dir * camera_to_cursor_dist
		push_warning("calculate_3d_world_position: Ray parallel to cursor plane, using fallback")
	else:
		var t: float = (cursor_world_pos - ray_origin).dot(plane_normal) / denominator
		world_pos = ray_origin + ray_dir * t

	# Convert world position to LOCAL grid coordinates
	# 1. to_local applies the node's full inverse transform (position AND scale)
	# 2. Divide by grid_size to convert to grid units
	# 3. Subtract GRID_ALIGNMENT_OFFSET because plane was offset in plane-locked mode
	var local_pos: Vector3 = active_tile_map_layer3d.to_local(world_pos) if active_tile_map_layer3d else world_pos
	var grid_pos: Vector3 = (local_pos / grid_size) - GlobalConstants.GRID_ALIGNMENT_OFFSET

	return {"grid_pos": grid_pos}


func _raycast_to_cursor_plane(camera: Camera3D, screen_pos: Vector2) -> Vector3:
	if not cursor_3d:
		return Vector3.ZERO

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	var active_plane_normal: Vector3 = GlobalPlaneDetector.detect_active_plane_3d(camera)
	var plane_normal: Vector3 = active_plane_normal

	var cursor_local_pos: Vector3 = cursor_3d.grid_position * grid_size
	var plane_point_local: Vector3 = cursor_local_pos - (GlobalConstants.GRID_ALIGNMENT_OFFSET * grid_size)
	var plane_point: Vector3 = active_tile_map_layer3d.to_global(plane_point_local) if active_tile_map_layer3d else plane_point_local

	var denom: float = ray_dir.dot(plane_normal)

	if abs(denom) < GlobalConstants.PARALLEL_PLANE_THRESHOLD:
		return cursor_3d.grid_position

	var t: float = (plane_point - ray_origin).dot(plane_normal) / denom

	if t < 0:
		return cursor_3d.grid_position

	var intersection: Vector3 = ray_origin + ray_dir * t

	var local_intersection: Vector3 = active_tile_map_layer3d.to_local(intersection) if active_tile_map_layer3d else intersection

	# Convert local position to grid position by dividing by grid_size.
	# Subtract GRID_ALIGNMENT_OFFSET because the plane was offset (prevents double-offset when tile placement adds it back).
	var raw_grid_pos: Vector3 = (local_intersection / grid_size) - GlobalConstants.GRID_ALIGNMENT_OFFSET

	return _apply_canvas_bounds_grid(raw_grid_pos, plane_normal, cursor_3d.grid_position)

func _apply_canvas_bounds_grid(grid_pos: Vector3,plane_normal: Vector3,cursor_grid_pos: Vector3
) -> Vector3:
	var constrained := grid_pos
	var aligned_cursor := cursor_grid_pos - GlobalConstants.GRID_ALIGNMENT_OFFSET #Adjust for the offset applied to the cursor's grid position
	var max_distance := GlobalConstants.MAX_CANVAS_DISTANCE

	if plane_normal == Vector3.UP:
		constrained.y = aligned_cursor.y
		constrained.x = clampf(constrained.x, aligned_cursor.x - max_distance, aligned_cursor.x + max_distance)
		constrained.z = clampf(constrained.z, aligned_cursor.z - max_distance, aligned_cursor.z + max_distance)
	elif plane_normal == Vector3.RIGHT:
		constrained.x = aligned_cursor.x
		constrained.y = clampf(constrained.y, aligned_cursor.y - max_distance, aligned_cursor.y + max_distance)
		constrained.z = clampf(constrained.z, aligned_cursor.z - max_distance, aligned_cursor.z + max_distance)
	else:
		constrained.z = aligned_cursor.z
		constrained.x = clampf(constrained.x, aligned_cursor.x - max_distance, aligned_cursor.x + max_distance)
		constrained.y = clampf(constrained.y, aligned_cursor.y - max_distance, aligned_cursor.y + max_distance)

	return constrained

func _add_tile_to_multimesh(
	grid_pos: Vector3,
	uv_rect: Rect2,
	orientation: GlobalUtil.TileOrientation = GlobalUtil.TileOrientation.FLOOR,
	mesh_rotation: int = 0,
	is_face_flipped: bool = false,
	tile_key_override: int = -1,
	anim_step_x: float = 0.0,
	anim_step_y: float = 0.0,
	anim_total_frames: int = 1,
	anim_columns: int = 1,
	anim_speed_fps: float = 0.0,
	p_spin_angle: float = 0.0,
	p_tilt_angle: float = 0.0,
	p_diagonal_scale: float = 0.0,
	p_tilt_offset: float = 0.0,
	p_depth_scale: float = -1.0,
	p_custom_transform: Transform3D = Transform3D(),
	p_freeze_uv: bool = false,
	p_texture_repeat_mode: int = -1) -> TileMapLayer3D.TileRef:
	var mesh_mode: GlobalConstants.MeshMode = active_tile_map_layer3d.current_mesh_mode
	var texture_repeat_mode: int = current_texture_repeat_mode if p_texture_repeat_mode < 0 else p_texture_repeat_mode

	var world_pos: Vector3 = GlobalUtil.grid_to_world(grid_pos, grid_size)
	var chunk: TileChunkRender = active_tile_map_layer3d.get_or_create_chunk(mesh_mode, texture_repeat_mode, world_pos)

	var instance_index: int = chunk.get_visible_instance_count()

	var transform: Transform3D

	if p_custom_transform != Transform3D():
		var chunk_origin: Vector3 = RegionSystem.region_key_to_world_origin(chunk.region_key)
		transform = p_custom_transform
		transform.origin -= chunk_origin
		if is_face_flipped:
			transform.basis = transform.basis * Basis.from_scale(Vector3(1, 1, -1))
	else:
		var local_world_pos: Vector3 = RegionSystem.world_to_region_local(world_pos)
		var local_grid_pos: Vector3 = GlobalUtil.world_to_grid(local_world_pos, grid_size)
		var actual_depth: float = p_depth_scale if p_depth_scale >= 0.0 else current_depth_scale
		var invert_depth: bool = current_depth_growth_mode == GlobalConstants.DepthGrowthMode.INWARD
		transform = GlobalUtil.build_tile_transform(
			local_grid_pos, orientation, mesh_rotation, grid_size, is_face_flipped,
			p_spin_angle, p_tilt_angle, p_diagonal_scale, p_tilt_offset,
			mesh_mode, actual_depth, invert_depth
		)

	# Apply orientation offset to prevent Z-fighting (flat tiles always; BOX/PRISM when setting enabled)
	var offset: Vector3 = GlobalUtil.calculate_flat_tile_offset(
		orientation, mesh_mode,
		active_tile_map_layer3d.settings.auto_resolve_box_z_fighting,
		active_tile_map_layer3d.enable_decal_mode
	)
	transform.origin += offset

	chunk.set_instance_transform(instance_index, transform)

	var atlas_size: Vector2 = tileset_texture.get_size()
	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var custom_data: Color = uv_data.uv_color
	if p_freeze_uv:
		custom_data.a = GlobalUtil.encode_uv_freeze_rotation(uv_data.uv_max.y, mesh_rotation, true)
	chunk.set_instance_custom_data(instance_index, custom_data)

	var is_animated: bool = anim_total_frames > 1
	if is_animated and mesh_mode == GlobalConstants.MeshMode.FLAT_SQUARE:
		var encoded_cols_speed: float = float(anim_columns) + anim_speed_fps / 256.0
		chunk.set_instance_color(instance_index, Color(
			anim_step_x, anim_step_y,
			float(anim_total_frames), encoded_cols_speed))

	chunk.set_visible_count(instance_index + 1)
	chunk.tile_count += 1

	#   Use override key if provided (replace operation), otherwise generate from position
	# This prevents key mismatch when replacing tiles where grid_pos or orientation changes
	var tile_key: int = tile_key_override if tile_key_override != -1 else GlobalUtil.make_tile_key(grid_pos, orientation)
	chunk.tile_refs[tile_key] = instance_index

	chunk.instance_to_key[instance_index] = tile_key

	var tile_ref: TileMapLayer3D.TileRef = TileMapLayer3D.TileRef.new()

	tile_ref.chunk_index = chunk.chunk_index

	tile_ref.instance_index = instance_index
	tile_ref.uv_rect = uv_rect
	tile_ref.mesh_mode = mesh_mode
	tile_ref.texture_repeat_mode = texture_repeat_mode
	tile_ref.region_key_packed = chunk.region_key_packed

	active_tile_map_layer3d.add_tile_ref(tile_key, tile_ref)

	return tile_ref

func _remove_tile_from_multimesh(tile_key: int) -> void:
	var tile_ref: TileMapLayer3D.TileRef = active_tile_map_layer3d.get_tile_ref(tile_key)

	if not tile_ref:
		push_warning("Attempted to remove tile that doesn't exist with key ", tile_key)
		return

	var chunk: TileChunkRender = active_tile_map_layer3d._get_chunk_by_ref(tile_ref)
	var chunk_type_name: String = GlobalConstants.MeshMode.keys()[tile_ref.mesh_mode] if tile_ref.mesh_mode < GlobalConstants.MeshMode.size() else "unknown"

	if not chunk:
		push_error(" ORPHANED TILEREF: Tile key %d has invalid %s chunk_index %d (region_key=%d) - cleaning up orphaned reference" %
				   [tile_key, chunk_type_name, tile_ref.chunk_index, tile_ref.region_key_packed])
		active_tile_map_layer3d.remove_tile_ref(tile_key)
		_spatial_index.remove_tile(tile_key)
		return

	if not chunk.tile_refs.has(tile_key):
		push_error("DATA CORRUPTION: Tile key %d not found in chunk tile_refs (chunk_index=%d, mesh_mode=%d)" % [tile_key, tile_ref.chunk_index, tile_ref.mesh_mode])

		var found_instance: int = -1
		for instance_idx in chunk.instance_to_key:
			if chunk.instance_to_key[instance_idx] == tile_key:
				found_instance = instance_idx
				push_warning("  → Found tile by brute force at instance %d - rebuilding chunk.tile_refs entry" % instance_idx)
				chunk.tile_refs[tile_key] = instance_idx
				break

		if found_instance == -1:
			push_error("  → Could not find tile in chunk - cleaning up global references")
			active_tile_map_layer3d.remove_tile_ref(tile_key)
			_spatial_index.remove_tile(tile_key)
			return

	var instance_index: int = chunk.tile_refs[tile_key]
	var last_visible_index: int = chunk.get_visible_instance_count() - 1


	if instance_index < last_visible_index:
		if not chunk.instance_to_key.has(last_visible_index):
			pass
		else:
			var last_transform: Transform3D = chunk.get_instance_transform(last_visible_index)
			var last_custom_data: Color = chunk.get_instance_custom_data(last_visible_index)

			chunk.set_instance_transform(instance_index, last_transform)
			chunk.set_instance_custom_data(instance_index, last_custom_data)

			if chunk._use_colors:
				var last_color: Color = chunk.get_instance_color(last_visible_index)
				chunk.set_instance_color(instance_index, last_color)

			var swapped_tile_key: int = chunk.instance_to_key[last_visible_index]

			chunk.tile_refs[swapped_tile_key] = instance_index
			chunk.instance_to_key[instance_index] = swapped_tile_key
			chunk.instance_to_key.erase(last_visible_index)

			var swapped_ref: TileMapLayer3D.TileRef = active_tile_map_layer3d.get_tile_ref(swapped_tile_key)
			if swapped_ref:
				swapped_ref.instance_index = instance_index
			else:
				push_warning("TilePlacementManager: Swapped tile ref not found for key: ", swapped_tile_key)

	chunk.set_visible_count(chunk.get_visible_instance_count() - 1)
	chunk.tile_count -= 1
	chunk.tile_refs.erase(tile_key)

	if instance_index == last_visible_index:
		chunk.instance_to_key.erase(instance_index)


	active_tile_map_layer3d.remove_tile_ref(tile_key)


	if chunk.tile_count == 0:
		if _batch_depth > 0:
			if not _pending_chunk_cleanups.has(chunk):
				_pending_chunk_cleanups.append(chunk)
				if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
					print("Chunk empty (batch mode) - scheduled for cleanup: chunk_index=%d mesh_mode=%d" % [chunk.chunk_index, tile_ref.mesh_mode])
		else:
			_cleanup_empty_chunk_internal(chunk)

## Removes empty chunk from its region registry and reindexes remaining chunks.
## Chunk must have tile_count == 0.
func _cleanup_empty_chunk_internal(chunk: TileChunkRender) -> void:
	if chunk.tile_count != 0:
		push_warning("Attempted to cleanup non-empty chunk (tile_count=%d)" % chunk.tile_count)
		return

	var mesh_mode: GlobalConstants.MeshMode = chunk.mesh_mode_type
	var texture_repeat_mode: int = chunk.texture_repeat_mode
	var region_key_packed: int = chunk.region_key_packed

	var registry: Dictionary = active_tile_map_layer3d._get_chunk_registry_for_mode(mesh_mode, texture_repeat_mode)
	var chunk_type_name: String = GlobalConstants.MeshMode.keys()[mesh_mode].to_lower() if mesh_mode < GlobalConstants.MeshMode.size() else "unknown"
	if texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
		chunk_type_name += "_repeat"

	if not registry.has(region_key_packed):
		push_warning("Chunk registry has no region %d during cleanup for %s" % [region_key_packed, chunk_type_name])
		return

	var orphaned_keys: Array[int] = []
	for tile_key in active_tile_map_layer3d._tile_lookup.keys():
		var tile_ref: TileMapLayer3D.TileRef = active_tile_map_layer3d._tile_lookup[tile_key]
		# Check if this TileRef points to the exact chunk we're about to remove
		# Must match: mesh_mode, texture_repeat_mode, region, AND chunk_index within that region
		if tile_ref.mesh_mode == mesh_mode and \
		   tile_ref.texture_repeat_mode == texture_repeat_mode and \
		   tile_ref.region_key_packed == region_key_packed and \
		   tile_ref.chunk_index == chunk.chunk_index:
			orphaned_keys.append(tile_key)

	for tile_key in orphaned_keys:
		if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
			print("Cleaning orphaned TileRef: tile_key=%d (pointed to chunk being removed)" % tile_key)
		active_tile_map_layer3d.remove_tile_ref(tile_key)
		_spatial_index.remove_tile(tile_key)

	if orphaned_keys.size() > 0:
		push_warning("Cleaned up %d orphaned TileRefs during chunk removal (chunk=%s region=%d chunk_index=%d)" % [orphaned_keys.size(), chunk_type_name, region_key_packed, chunk.chunk_index])

	if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
		print("Removing empty chunk: chunk_index=%d mesh_mode=%d texture_repeat=%d region=%d name=%s" % [chunk.chunk_index, mesh_mode, texture_repeat_mode, region_key_packed, chunk.chunk_name])

	var region_chunks: Array = registry[region_key_packed]
	var region_idx: int = region_chunks.find(chunk)
	if region_idx == -1:
		push_warning("Empty %s chunk not found in registry region %d" % [chunk_type_name, region_key_packed])
		return

	region_chunks.remove_at(region_idx)
	if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
		print("  -> Removed from registry[%d] at index %d (%d chunks remaining in region)" % [region_key_packed, region_idx, region_chunks.size()])
	if region_chunks.is_empty():
		registry.erase(region_key_packed)
		if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
			print("  -> Removed empty region entry from registry")

	chunk.free_rids()

	active_tile_map_layer3d.reindex_chunks()

	if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
		print("Chunk cleanup complete - reindexing done")

func _do_place_tile(tile_key: int, grid_pos: Vector3, uv_rect: Rect2, orientation: int, mesh_rotation: int, tile_info: PlacedTileInfo = null) -> void:
	if active_tile_map_layer3d.has_tile(tile_key):
		_remove_tile_from_multimesh(tile_key)

	var data: PlacedTileInfo = tile_info
	var preserved_flip: bool = data.is_face_flipped if data != null else false
	var preserved_mode: int = data.mesh_mode if data != null else active_tile_map_layer3d.current_mesh_mode
	var terrain_id: int = data.terrain_id if data != null else GlobalConstants.AUTOTILE_NO_TERRAIN
	var texture_repeat: int = data.texture_repeat_mode if data != null else current_texture_repeat_mode
	var freeze_uv: bool = data.freeze_uv if data != null else current_freeze_uv
	var tile_depth_growth_mode: int = data.depth_growth_mode if data != null else current_depth_growth_mode

	var spin_angle: float = data.spin_angle_rad if data != null else 0.0
	var tilt_angle: float = data.tilt_angle_rad if data != null else 0.0
	var diagonal_scale: float = data.diagonal_scale if data != null else 0.0
	var tilt_offset: float = data.tilt_offset_factor if data != null else 0.0
	var depth_scale: float = data.depth_scale if data != null else current_depth_scale

	if orientation >= 6 and spin_angle == 0.0 and tilt_angle == 0.0:
		spin_angle = GlobalConstants.SPIN_ANGLE_RAD
		tilt_angle = GlobalConstants.TILT_ANGLE_RAD
		diagonal_scale = GlobalConstants.DIAGONAL_SCALE_FACTOR
		tilt_offset = GlobalConstants.TILT_POSITION_OFFSET_FACTOR

	var anim_step_x: float = data.anim_step_x if data != null else 0.0
	var anim_step_y: float = data.anim_step_y if data != null else 0.0
	var anim_frames: int = data.anim_total_frames if data != null else 1
	var anim_cols: int = data.anim_columns if data != null else 1
	var anim_speed: float = data.anim_speed_fps if data != null else 0.0

	var custom_transform: Transform3D = data.custom_transform if data != null and data.has_custom_transform else Transform3D()

	## Temporarily set the node's mesh mode to the tile's preserved mode so that
	## _add_tile_to_multimesh selects the correct chunk type (e.g. FLAT_TRIANGULE
	## side tiles must go into a triangle chunk, not the current FLAT_SQUARE chunk).
	var original_mesh_mode: int = active_tile_map_layer3d.current_mesh_mode
	active_tile_map_layer3d.current_mesh_mode = preserved_mode
	var original_depth_growth_mode: int = current_depth_growth_mode
	current_depth_growth_mode = tile_depth_growth_mode

	var tile_ref = _add_tile_to_multimesh(grid_pos, uv_rect, orientation, mesh_rotation, preserved_flip, tile_key,
		anim_step_x, anim_step_y, anim_frames, anim_cols, anim_speed,
		spin_angle, tilt_angle, diagonal_scale, tilt_offset, depth_scale,
		custom_transform, freeze_uv, texture_repeat)

	active_tile_map_layer3d.current_mesh_mode = original_mesh_mode
	current_depth_growth_mode = original_depth_growth_mode

	var atlas_source_id: int = data.atlas_source_id if data != null else -1
	var atlas_coords: Vector2i = data.atlas_coords if data != null else Vector2i(-1, -1)
	if atlas_source_id < 0 and uv_rect.has_area():
		var fallback: Array = _binding_for_uv_rect(uv_rect)
		atlas_source_id = fallback[0]
		atlas_coords = fallback[1]

	active_tile_map_layer3d.save_tile_data_direct(
		grid_pos, uv_rect, orientation, mesh_rotation, preserved_mode,
		preserved_flip, terrain_id, spin_angle, tilt_angle, diagonal_scale,
		tilt_offset, depth_scale, texture_repeat, freeze_uv,
		anim_step_x, anim_step_y, anim_frames, anim_cols, anim_speed,
		custom_transform,
		atlas_source_id, atlas_coords, tile_depth_growth_mode
	)

	_spatial_index.add_tile(tile_key, grid_pos)


func _undo_place_tile(tile_key: int) -> void:
	remove_tile_everywhere(tile_key)


func _do_replace_tile_dict(tile_key: int, grid_pos: Vector3, tile_info: PlacedTileInfo) -> void:
	if active_tile_map_layer3d.has_tile(tile_key):
		_remove_tile_from_multimesh(tile_key)

	var data: PlacedTileInfo = tile_info
	if data == null:
		return

	var uv_rect: Rect2 = data.uv_rect if data.uv_rect != Rect2() else current_tile_uv
	var orientation: int = data.orientation
	var rotation: int = data.mesh_rotation
	var flip: bool = data.is_face_flipped

	var anim_step_x: float = data.anim_step_x
	var anim_step_y: float = data.anim_step_y
	var anim_frames: int = data.anim_total_frames
	var anim_cols: int = data.anim_columns
	var anim_speed: float = data.anim_speed_fps

	var custom_transform: Transform3D = data.custom_transform if data.has_custom_transform else Transform3D()

	var replace_mode: int = data.mesh_mode
	var original_mesh_mode: int = active_tile_map_layer3d.current_mesh_mode
	active_tile_map_layer3d.current_mesh_mode = replace_mode
	var original_depth_growth_mode: int = current_depth_growth_mode
	current_depth_growth_mode = data.depth_growth_mode

	var replace_freeze_uv: bool = data.freeze_uv
	var tile_ref: TileMapLayer3D.TileRef = _add_tile_to_multimesh(
		grid_pos, uv_rect, orientation, rotation, flip, tile_key,
		anim_step_x, anim_step_y, anim_frames, anim_cols, anim_speed,
		data.spin_angle_rad,
		data.tilt_angle_rad,
		data.diagonal_scale,
		data.tilt_offset_factor,
		data.depth_scale,
		custom_transform, replace_freeze_uv, data.texture_repeat_mode
	)

	active_tile_map_layer3d.current_mesh_mode = original_mesh_mode
	current_depth_growth_mode = original_depth_growth_mode

	_spatial_index.remove_tile(tile_key)
	_spatial_index.add_tile(tile_key, grid_pos)

	active_tile_map_layer3d.save_tile_data_direct(
		grid_pos, uv_rect, orientation, rotation,
		data.mesh_mode,
		flip,
		data.terrain_id,
		data.spin_angle_rad,
		data.tilt_angle_rad,
		data.diagonal_scale,
		data.tilt_offset_factor,
		data.depth_scale,
		data.texture_repeat_mode,
		replace_freeze_uv,
		anim_step_x, anim_step_y, anim_frames, anim_cols, anim_speed,
		custom_transform,
		data.atlas_source_id,
		data.atlas_coords,
		data.depth_growth_mode
	)


func _do_erase_tile(tile_key: int) -> void:
	remove_tile_everywhere(tile_key)



func _find_conflicting_tile_key(grid_pos: Vector3, orientation: int) -> int:
	for other_orientation in range(GlobalUtil.TileOrientation.size()):
		if GlobalUtil.orientations_conflict(orientation, other_orientation):
			var other_key: int = GlobalUtil.make_tile_key(grid_pos, other_orientation)
			if active_tile_map_layer3d.has_tile(other_key):
				var existing_info: PlacedTileInfo = _get_existing_tile_info(other_key)
				var existing_mode: int = existing_info.mesh_mode if existing_info else GlobalConstants.MeshMode.FLAT_SQUARE
				var opposite_ori: int = GlobalUtil.get_opposite_orientation(orientation)

				if other_orientation == opposite_ori:
					var is_existing_flat: bool = (
						existing_mode == GlobalConstants.MeshMode.FLAT_SQUARE or
						existing_mode == GlobalConstants.MeshMode.FLAT_TRIANGULE or
						existing_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER or
						existing_mode == GlobalConstants.MeshMode.FLAT_ARCH or
						existing_mode == GlobalConstants.MeshMode.FLAT_ARCH_I or
						existing_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I or
						existing_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP or
					existing_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I or
					existing_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO or
					existing_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C or
					existing_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I or
					existing_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S or
					existing_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I
					)
					var is_new_flat: bool = (
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_SQUARE or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_TRIANGULE or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_I or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S or
						active_tile_map_layer3d.current_mesh_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I
					)
					if is_existing_flat and is_new_flat:
						continue
				return other_key
	return -1


func _replace_conflicting_tile_with_undo(
	old_key: int,
	new_key: int,
	grid_pos: Vector3,
	new_orientation: GlobalUtil.TileOrientation,
	undo_redo: Object) -> void:
	var old_tile_index: int = active_tile_map_layer3d.get_tile_index(old_key)
	if old_tile_index < 0:
		push_warning("_replace_conflicting_tile_with_undo: Old tile not found in columnar storage")
		return

	var old_tile_info: PlacedTileInfo = active_tile_map_layer3d.get_tile_info_at_index(old_tile_index)
	if old_tile_info == null:
		push_warning("_replace_conflicting_tile_with_undo: Failed to read old tile data")
		return

	var new_tile_info: PlacedTileInfo = create_tile_info(
		grid_pos, current_tile_uv, new_orientation,
		current_mesh_rotation, is_current_face_flipped,
		active_tile_map_layer3d.current_mesh_mode
	)

	undo_redo.create_action("Replace Tile", UndoRedo.MERGE_DISABLE, active_tile_map_layer3d)
	undo_redo.add_do_method(self, "_do_erase_tile", old_key)
	undo_redo.add_do_method(self, "_do_place_tile", new_key, grid_pos, current_tile_uv, new_orientation, current_mesh_rotation, new_tile_info)
	undo_redo.add_undo_method(self, "_do_erase_tile", new_key)
	undo_redo.add_undo_method(self, "_do_place_tile", old_key, old_tile_info.grid_pos, old_tile_info.uv_rect, old_tile_info.orientation, old_tile_info.rotation, old_tile_info)
	undo_redo.commit_action()




func _transform_local_offset_to_world(local_offset: Vector3, orientation: GlobalUtil.TileOrientation, mesh_rotation: int) -> Vector3:
	var base_basis: Basis = GlobalUtil.get_tile_rotation_basis(orientation)
	var rotated_basis: Basis = GlobalUtil.apply_mesh_rotation(base_basis, orientation, mesh_rotation)

	return rotated_basis * local_offset


func start_paint_stroke(undo_redo: Object, action_name: String = "Paint Tiles") -> void:
	if _paint_stroke_active:
		push_warning("TilePlacementManager: Paint stroke already active, ending previous stroke")
		end_paint_stroke()

	_paint_stroke_undo_redo = undo_redo
	_paint_stroke_active = true

	# Create undo action but don't commit yet - we'll add tiles to it during the stroke.
	# Pass active_tile_map_layer3d as custom_context so the EditorUndoRedoManager binds this
	# action to the edited scene and marks it unsaved (prevents silent data loss on reload).
	_paint_stroke_undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, active_tile_map_layer3d)

func paint_tile_at(grid_pos: Vector3, orientation: GlobalUtil.TileOrientation) -> bool:
	if not _paint_stroke_active or not _paint_stroke_undo_redo:
		push_warning("TilePlacementManager: Cannot paint tile - no active paint stroke")
		return false

	if not active_tile_map_layer3d:
		return false

	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

	if active_tile_map_layer3d.has_tile(tile_key):
		var old_tile_info: PlacedTileInfo = _get_existing_tile_info(tile_key)

		var new_tile_info: PlacedTileInfo = create_tile_info(
			grid_pos, current_tile_uv, orientation, current_mesh_rotation,
			is_current_face_flipped, active_tile_map_layer3d.current_mesh_mode
		)

		_paint_stroke_undo_redo.add_do_method(self, "_do_replace_tile_dict", tile_key, grid_pos, new_tile_info)
		_paint_stroke_undo_redo.add_undo_method(self, "_do_replace_tile_dict", tile_key,
			old_tile_info.grid_position, old_tile_info)

		_do_replace_tile_dict(tile_key, grid_pos, new_tile_info)
		return true

	var conflicting_key: int = _find_conflicting_tile_key(grid_pos, orientation)
	if conflicting_key != -1:
		var old_tile_info: PlacedTileInfo = _get_existing_tile_info(conflicting_key)
		var old_grid_pos: Vector3 = old_tile_info.grid_position
		var old_uv: Rect2 = old_tile_info.uv_rect
		var old_orientation: int = old_tile_info.orientation
		var old_rotation: int = old_tile_info.mesh_rotation

		var new_tile_info: PlacedTileInfo = create_tile_info(
			grid_pos, current_tile_uv, orientation, current_mesh_rotation,
			is_current_face_flipped, active_tile_map_layer3d.current_mesh_mode
		)

		_paint_stroke_undo_redo.add_do_method(self, "_do_erase_tile", conflicting_key)
		_paint_stroke_undo_redo.add_do_method(self, "_do_place_tile", tile_key, grid_pos, current_tile_uv, orientation, current_mesh_rotation, new_tile_info)
		_paint_stroke_undo_redo.add_undo_method(self, "_do_erase_tile", tile_key)
		_paint_stroke_undo_redo.add_undo_method(self, "_do_place_tile", conflicting_key, old_grid_pos, old_uv, old_orientation, old_rotation, old_tile_info)

		_do_erase_tile(conflicting_key)
		_do_place_tile(tile_key, grid_pos, current_tile_uv, orientation, current_mesh_rotation, new_tile_info)
		return true

	var tile_info: PlacedTileInfo = create_tile_info(
		grid_pos, current_tile_uv, orientation, current_mesh_rotation,
		is_current_face_flipped, active_tile_map_layer3d.current_mesh_mode
	)

	_paint_stroke_undo_redo.add_do_method(self, "_do_place_tile", tile_key, grid_pos, current_tile_uv, orientation, current_mesh_rotation, tile_info)
	_paint_stroke_undo_redo.add_undo_method(self, "_undo_place_tile", tile_key)

	_do_place_tile(tile_key, grid_pos, current_tile_uv, orientation, current_mesh_rotation, tile_info)

	return true

func paint_multi_tiles_at(anchor_grid_pos: Vector3, orientation: GlobalUtil.TileOrientation) -> bool:
	if not _paint_stroke_active or not _paint_stroke_undo_redo:
		push_warning("TilePlacementManager: Cannot paint multi-tiles - no active paint stroke")
		return false

	if not active_tile_map_layer3d or multi_tile_selection.is_empty():
		return false

	var tiles_to_place: Array[Dictionary] = []

	var anchor_uv_rect: Rect2 = multi_tile_selection[0]
	var anchor_pixel_pos: Vector2 = anchor_uv_rect.position
	var tile_pixel_size: Vector2 = anchor_uv_rect.size

	for i in range(multi_tile_selection.size()):
		var tile_uv_rect: Rect2 = multi_tile_selection[i]
		var tile_pixel_pos: Vector2 = tile_uv_rect.position

		var pixel_offset: Vector2 = tile_pixel_pos - anchor_pixel_pos

		var grid_offset: Vector2 = pixel_offset / tile_pixel_size

		var local_offset: Vector3 = Vector3(grid_offset.x, 0, grid_offset.y)

		var world_offset: Vector3 = _transform_local_offset_to_world(local_offset, orientation, current_mesh_rotation)
		var tile_grid_pos: Vector3 = anchor_grid_pos + world_offset

		var tile_key: int = GlobalUtil.make_tile_key(tile_grid_pos, orientation)

		var conflicting_key: int = -1
		var has_same_tile: bool = active_tile_map_layer3d.has_tile(tile_key)
		if not has_same_tile:
			conflicting_key = _find_conflicting_tile_key(tile_grid_pos, orientation)

		tiles_to_place.append({
			"tile_key": tile_key,
			"grid_pos": tile_grid_pos,
			"uv_rect": tile_uv_rect,
			"orientation": orientation,
			"mesh_rotation": current_mesh_rotation,
			"is_replacement": has_same_tile,
			"conflicting_key": conflicting_key
		})

	for tile_info in tiles_to_place:
		if tile_info.is_replacement:
			var old_tile_info: PlacedTileInfo = _get_existing_tile_info(tile_info.tile_key)
			var new_tile_info: PlacedTileInfo = create_tile_info(
				tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation,
				tile_info.mesh_rotation, is_current_face_flipped,
				active_tile_map_layer3d.current_mesh_mode
			)

			_paint_stroke_undo_redo.add_do_method(self, "_do_replace_tile_dict", tile_info.tile_key, tile_info.grid_pos, new_tile_info)
			_paint_stroke_undo_redo.add_undo_method(self, "_do_replace_tile_dict", tile_info.tile_key,
				old_tile_info.grid_position, old_tile_info)

			_do_replace_tile_dict(tile_info.tile_key, tile_info.grid_pos, new_tile_info)

		elif tile_info.conflicting_key != -1:
			var old_tile_dict: PlacedTileInfo = _get_existing_tile_info(tile_info.conflicting_key)
			var old_grid_pos: Vector3 = old_tile_dict.grid_position
			var old_uv: Rect2 = old_tile_dict.uv_rect
			var old_orientation: int = old_tile_dict.orientation
			var old_rotation: int = old_tile_dict.mesh_rotation

			var new_tile_dict: PlacedTileInfo = create_tile_info(
				tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation,
				is_current_face_flipped, active_tile_map_layer3d.current_mesh_mode
			)

			_paint_stroke_undo_redo.add_do_method(self, "_do_erase_tile", tile_info.conflicting_key)
			_paint_stroke_undo_redo.add_do_method(self, "_do_place_tile", tile_info.tile_key, tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation, new_tile_dict)
			_paint_stroke_undo_redo.add_undo_method(self, "_do_erase_tile", tile_info.tile_key)
			_paint_stroke_undo_redo.add_undo_method(self, "_do_place_tile", tile_info.conflicting_key, old_grid_pos, old_uv, old_orientation, old_rotation, old_tile_dict)

			_do_erase_tile(tile_info.conflicting_key)
			_do_place_tile(tile_info.tile_key, tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation, new_tile_dict)

		else:
			var tile_dict: PlacedTileInfo = create_tile_info(
				tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation,
				is_current_face_flipped, active_tile_map_layer3d.current_mesh_mode
			)

			_paint_stroke_undo_redo.add_do_method(self, "_do_place_tile", tile_info.tile_key, tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation, tile_dict)
			_paint_stroke_undo_redo.add_undo_method(self, "_undo_place_tile", tile_info.tile_key)

			_do_place_tile(tile_info.tile_key, tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation, tile_dict)

	return true

func erase_tile_at(grid_pos: Vector3, orientation: GlobalUtil.TileOrientation) -> bool:
	if not _paint_stroke_active or not _paint_stroke_undo_redo:
		push_warning("TilePlacementManager: Cannot erase tile - no active paint stroke")
		return false

	if not active_tile_map_layer3d:
		return false

	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

	if active_tile_map_layer3d.has_tile(tile_key):
		var tile_info: PlacedTileInfo = _get_existing_tile_info(tile_key)
		if tile_info == null:
			return false

		_paint_stroke_undo_redo.add_do_method(self, "_do_erase_tile", tile_key)
		_paint_stroke_undo_redo.add_undo_method(self, "_do_place_tile", tile_key, grid_pos,
			tile_info.uv_rect, orientation,
			tile_info.mesh_rotation, tile_info)

		_do_erase_tile(tile_key)
		return true

	var conflicting_key: int = _find_conflicting_tile_key(grid_pos, orientation)
	if conflicting_key != -1:
		var tile_info: PlacedTileInfo = _get_existing_tile_info(conflicting_key)
		if tile_info == null:
			return false
		var conflicting_grid_pos: Vector3 = tile_info.grid_position
		var conflicting_orientation: int = tile_info.orientation

		_paint_stroke_undo_redo.add_do_method(self, "_do_erase_tile", conflicting_key)
		_paint_stroke_undo_redo.add_undo_method(self, "_do_place_tile", conflicting_key,
			conflicting_grid_pos, tile_info.uv_rect,
			conflicting_orientation, tile_info.mesh_rotation, tile_info)

		_do_erase_tile(conflicting_key)
		return true

	return false

func end_paint_stroke() -> void:
	if not _paint_stroke_active:
		return

	if _paint_stroke_undo_redo:
		_paint_stroke_undo_redo.commit_action(false)

	_paint_stroke_active = false
	_paint_stroke_undo_redo = null


func sync_from_tile_model() -> void:
	if not active_tile_map_layer3d:
		return

	reset_batch_update_state()

	#   If _tile_lookup is empty but tiles exist, chunks haven't been rebuilt yet
	# This happens during scene reload because _rebuild_chunks_from_saved_data() is deferred
	# Force immediate rebuild to avoid false corruption errors during validation
	if active_tile_map_layer3d._tile_lookup.is_empty() and active_tile_map_layer3d.get_tile_count() > 0:
		active_tile_map_layer3d._rebuild_chunks_from_saved_data(false)

	_spatial_index.clear()

	var validation_errors: int = 0
	for tile_idx in range(active_tile_map_layer3d.get_tile_count()):
		var tile_info: PlacedTileInfo = active_tile_map_layer3d.get_tile_info_at_index(tile_idx)
		if tile_info == null:
			continue

		var grid_pos: Vector3 = tile_info.grid_position
		var orientation: int = tile_info.orientation
		var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

		_spatial_index.add_tile(tile_key, grid_pos)

		var tile_ref: TileMapLayer3D.TileRef = active_tile_map_layer3d.get_tile_ref(tile_key)
		if not tile_ref:
			push_error("❌ CORRUPTION: Tile key %d in columnar storage but has no TileRef" % tile_key)
			validation_errors += 1
			continue

		var chunk: TileChunkRender = active_tile_map_layer3d._get_chunk_by_ref(tile_ref)
		var chunk_type_name: String = GlobalConstants.MeshMode.keys()[tile_ref.mesh_mode] if tile_ref.mesh_mode < GlobalConstants.MeshMode.size() else "unknown"

		if not chunk:
			push_error("❌ CORRUPTION: Tile key %d has invalid %s chunk_index %d (region=%d)" % [tile_key, chunk_type_name, tile_ref.chunk_index, tile_ref.region_key_packed])
			validation_errors += 1
			continue

		if not chunk.tile_refs.has(tile_key):
			push_error("❌ CORRUPTION: Tile key %d has TileRef but not in chunk.tile_refs (chunk_index=%d)" % [tile_key, tile_ref.chunk_index])
			validation_errors += 1

		var instance_index: int = chunk.tile_refs.get(tile_key, -1)
		if instance_index >= 0:
			if not chunk.instance_to_key.has(instance_index):
				push_error("❌ CORRUPTION: Tile key %d instance %d not in chunk.instance_to_key" % [tile_key, instance_index])
				validation_errors += 1
			elif chunk.instance_to_key[instance_index] != tile_key:
				push_error("❌ CORRUPTION: Tile key %d instance %d points to wrong key %d in instance_to_key" % [tile_key, instance_index, chunk.instance_to_key[instance_index]])
				validation_errors += 1

	if validation_errors > 0:
		push_error("🔥   sync_from_tile_model() found %d data corruption errors - chunk system may be inconsistent!" % validation_errors)


func fill_area_with_undo_compressed(
	min_grid_pos: Vector3,
	max_grid_pos: Vector3,
	orientation: int,
	undo_redo: Object
) -> int:
	if not active_tile_map_layer3d:
		push_error("TilePlacementManager: Cannot fill area - no TileMapLayer3D set")
		return -1

	if current_tile_uv.size.x <= 0 or current_tile_uv.size.y <= 0:
		push_error("TilePlacementManager: Cannot fill area - no tile selected")
		return -1

	var positions: Array[Vector3] = GlobalUtil.get_grid_positions_in_area_with_snap(
		min_grid_pos,
		max_grid_pos,
		orientation,
		grid_size
	)

	if positions.size() > GlobalConstants.MAX_AREA_FILL_TILES:
		push_error("TilePlacementManager: Area too large (%d tiles, max %d)" % [positions.size(), GlobalConstants.MAX_AREA_FILL_TILES])
		return -1

	if positions.is_empty():
		return 0

	var tiles_to_place: Array[PlacedTileInfo] = []
	var existing_tiles: Array[PlacedTileInfo] = []
	var conflicting_tiles: Array[PlacedTileInfo] = []

	for grid_pos in positions:
		var tile_info: PlacedTileInfo = create_tile_info(
			grid_pos, current_tile_uv, orientation,
			current_mesh_rotation, is_current_face_flipped,
			active_tile_map_layer3d.current_mesh_mode
		)

		if active_tile_map_layer3d.has_tile(tile_info.tile_key):
			var existing: PlacedTileInfo = _get_existing_tile_info(tile_info.tile_key)
			if existing != null:
				existing_tiles.append(existing)
		else:
			var conflicting_key: int = _find_conflicting_tile_key(grid_pos, orientation)
			if conflicting_key != -1:
				var conflicting: PlacedTileInfo = _get_existing_tile_info(conflicting_key)
				if conflicting != null:
					conflicting_tiles.append(conflicting)

		tiles_to_place.append(tile_info)

	var compressed_new: UndoData.UndoAreaData = UndoData.UndoAreaData.from_tiles(tiles_to_place)
	var compressed_old: UndoData.UndoAreaData = null
	if existing_tiles.size() > 0:
		compressed_old = UndoData.UndoAreaData.from_tiles(existing_tiles)
	var compressed_conflicting: UndoData.UndoAreaData = null
	if conflicting_tiles.size() > 0:
		compressed_conflicting = UndoData.UndoAreaData.from_tiles(conflicting_tiles)

	undo_redo.create_action("Fill Area (%d tiles)" % tiles_to_place.size(), UndoRedo.MERGE_DISABLE, active_tile_map_layer3d)
	undo_redo.add_do_method(self, "_do_area_fill_compressed_with_conflicts", compressed_new, compressed_conflicting)
	undo_redo.add_undo_method(self, "_undo_area_fill_compressed_with_conflicts", compressed_new, compressed_old, compressed_conflicting)
	undo_redo.commit_action()

	return tiles_to_place.size()


func _do_area_fill_compressed_with_conflicts(area_data: UndoData.UndoAreaData, conflicting_data: UndoData.UndoAreaData) -> void:
	begin_batch_update()

	if conflicting_data:
		var conflicting_tiles: Array = conflicting_data.to_tiles()
		for tile_info in conflicting_tiles:
			_do_erase_tile(tile_info.tile_key)

	var tiles: Array = area_data.to_tiles()
	for tile_info in tiles:
		_do_place_tile(
			tile_info.tile_key,
			tile_info.grid_pos,
			tile_info.uv_rect,
			tile_info.orientation,
			tile_info.rotation,
			tile_info
		)

	end_batch_update()


func _undo_area_fill_compressed_with_conflicts(new_data: UndoData.UndoAreaData, old_data: UndoData.UndoAreaData, conflicting_data: UndoData.UndoAreaData) -> void:
	begin_batch_update()

	var new_tiles: Array = new_data.to_tiles()
	for tile_info in new_tiles:
		_do_erase_tile(tile_info.tile_key)

	if old_data:
		var old_tiles: Array = old_data.to_tiles()
		for tile_info in old_tiles:
			_do_place_tile(
				tile_info.tile_key,
				tile_info.grid_pos,
				tile_info.uv_rect,
				tile_info.orientation,
				tile_info.rotation,
				tile_info
			)

	if conflicting_data:
		var conflicting_tiles: Array = conflicting_data.to_tiles()
		for tile_info in conflicting_tiles:
			_do_place_tile(
				tile_info.tile_key,
				tile_info.grid_pos,
				tile_info.uv_rect,
				tile_info.orientation,
				tile_info.rotation,
				tile_info
			)

	end_batch_update()


func erase_area_with_undo(
	min_grid_pos: Vector3,
	max_grid_pos: Vector3,
	orientation: int,
	undo_redo: Object) -> int:
	if not active_tile_map_layer3d:
		push_error("TilePlacementManager: Cannot erase area - no TileMapLayer3D set")
		return -1

	var actual_min: Vector3 = Vector3(
		min(min_grid_pos.x, max_grid_pos.x),
		min(min_grid_pos.y, max_grid_pos.y),
		min(min_grid_pos.z, max_grid_pos.z)
	)
	var actual_max: Vector3 = Vector3(
		max(min_grid_pos.x, max_grid_pos.x),
		max(min_grid_pos.y, max_grid_pos.y),
		max(min_grid_pos.z, max_grid_pos.z)
	)

	var tolerance: float = GlobalConstants.AREA_ERASE_SURFACE_TOLERANCE
	var tolerance_vector: Vector3 = GlobalUtil.get_orientation_tolerance(orientation, tolerance)
	actual_min -= tolerance_vector
	actual_max += tolerance_vector

	var selection_size: Vector3 = actual_max - actual_min
	var selection_volume: float = selection_size.x * selection_size.y * selection_size.z
	var selection_diagonal: float = selection_size.length()

	var stats: Dictionary = {
		"total_tiles": active_tile_map_layer3d.get_tile_count(),
		"selection_volume": selection_volume,
		"selection_diagonal": selection_diagonal
	}

	if GlobalConstants.DEBUG_AREA_OPERATIONS:
		print("Area Erase: %.1fx%.1fx%.1f (volume=%.1f, diagonal=%.1f)" %
			  [selection_size.x, selection_size.y, selection_size.z, selection_volume, selection_diagonal])

	var tiles_to_erase: Array = []

	const SMALL_SELECTION_THRESHOLD: float = 100.0

	const MEDIUM_SELECTION_THRESHOLD: float = 1000.0


	if selection_volume < SMALL_SELECTION_THRESHOLD:
		# STRATEGY A: Small selection - full precision
		if GlobalConstants.DEBUG_AREA_OPERATIONS:
			print("  → Using PRECISE strategy (small selection)")

		var candidate_tiles: Array = _spatial_index.get_tiles_in_area(actual_min, actual_max)

		for tile_key in candidate_tiles:
			if not active_tile_map_layer3d.has_tile(tile_key):
				continue

			var tile_info: PlacedTileInfo = _get_existing_tile_info(tile_key)
			if tile_info == null:
				continue
			var tile_pos: Vector3 = tile_info.grid_position

			if (tile_pos.x >= actual_min.x and tile_pos.x <= actual_max.x and
				tile_pos.y >= actual_min.y and tile_pos.y <= actual_max.y and
				tile_pos.z >= actual_min.z and tile_pos.z <= actual_max.z):

				tiles_to_erase.append(tile_info)

	elif selection_volume < MEDIUM_SELECTION_THRESHOLD:
		if GlobalConstants.DEBUG_AREA_OPERATIONS:
			print("  → Using SPATIAL strategy (medium selection)")

		var candidate_tiles: Array = _spatial_index.get_tiles_in_area(actual_min, actual_max)

		for tile_key in candidate_tiles:
			if not active_tile_map_layer3d.has_tile(tile_key):
				continue

			var tile_info: PlacedTileInfo = _get_existing_tile_info(tile_key)
			if tile_info == null:
				continue

			var tile_pos: Vector3 = tile_info.grid_position
			if _is_in_bounds(tile_pos, actual_min, actual_max, 1.0):
				tiles_to_erase.append(tile_info)

	else:
		if GlobalConstants.DEBUG_AREA_OPERATIONS:
			print("  → Using DIRECT strategy (large selection)")

		var tile_count: int = active_tile_map_layer3d.get_tile_count()
		for i in range(tile_count):
			var tile_info: PlacedTileInfo = active_tile_map_layer3d.get_tile_info_at_index(i)
			if tile_info == null:
				continue

			var tile_pos: Vector3 = tile_info.grid_position

			if _is_in_bounds(tile_pos, actual_min, actual_max):
				var tile_orientation: int = tile_info.orientation
				var tile_key: int = GlobalUtil.make_tile_key(tile_pos, tile_orientation)
				tile_info.tile_key = tile_key
				tiles_to_erase.append(tile_info)

	if GlobalConstants.DEBUG_AREA_OPERATIONS:
		print("  → Found %d tiles to erase (from %d total)" % [tiles_to_erase.size(), stats.total_tiles])

	if tiles_to_erase.is_empty():
		return 0

	if GlobalConstants.DEBUG_DATA_INTEGRITY and tiles_to_erase.size() > 100:
		print("PRE-ERASE VALIDATION (%d tiles)..." % tiles_to_erase.size())
		var pre_validation: Dictionary = _validate_data_structure_integrity()
		if not pre_validation.valid:
			push_error("DATA CORRUPTION DETECTED BEFORE AREA ERASE:")
			for error in pre_validation.errors:
				push_error("  - %s" % error)

	undo_redo.create_action("Erase Area (%d tiles)" % tiles_to_erase.size(), UndoRedo.MERGE_DISABLE, active_tile_map_layer3d)

	for tile_info in tiles_to_erase:
		var tile_key: int = tile_info.tile_key

		undo_redo.add_do_method(self, "_do_erase_tile", tile_key)

		undo_redo.add_undo_method(
			self, "_do_place_tile",
			tile_key,
			tile_info.grid_pos,
			tile_info.uv_rect,
			tile_info.orientation,
			tile_info.rotation,
			tile_info
		)

	begin_batch_update()
	undo_redo.commit_action()
	end_batch_update()

	if GlobalConstants.DEBUG_DATA_INTEGRITY and tiles_to_erase.size() > 100:
		print("POST-ERASE VALIDATION...")
		var post_validation: Dictionary = _validate_data_structure_integrity()
		if not post_validation.valid:
			push_error("DATA CORRUPTION DETECTED AFTER AREA ERASE:")
			for error in post_validation.errors:
				push_error("  - %s" % error)
		else:
			print("Data integrity validated - %d tiles remaining" % post_validation.stats.columnar_tile_count)

	return tiles_to_erase.size()
