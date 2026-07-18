class_name RegionBaker
extends RefCounted

const _PROFILE_TAG: String = "[RegionBaker]"


class _Serializer extends RefCounted:
	signal slot_free
	var in_flight: int = 0

static var _serializer: _Serializer = null

static func _get_serializer() -> _Serializer:
	if _serializer == null:
		_serializer = _Serializer.new()
	return _serializer


# The bound Callable on the worker holds a strong ref, keeping the job alive
# across the deferred emit.
class _BakeJob extends RefCounted:
	signal done(payload: Dictionary)


static func bake_mesh(
		tile_map: TileMapLayer3D,
		region_chunk: TerrainRegionChunk = null,
		options: RegionBakeOptions = null
	) -> MeshInstance3D:
	if tile_map == null:
		return null
	options = options if options != null else RegionBakeOptions.new()
	var region_key: Vector3i = _region_key(region_chunk)
	var tile_count: int = _count_tiles(region_chunk, tile_map)

	await _acquire_slot()
	var t_start: int = Time.get_ticks_msec()
	var payload: Dictionary = await _run_merge_on_worker(tile_map, region_chunk, options, false)
	var t_main_start: int = Time.get_ticks_msec()
	_release_slot()

	if not payload.get("success", false):
		_emit_profile(region_key, tile_count,
			int(payload.get("merge_ms", 0)), 0, 0, 0,
			Time.get_ticks_msec() - t_start, "mesh",
			"skip(%s)" % payload.get("error", "no_geometry"))
		return null

	var array_mesh: ArrayMesh = payload.get("mesh")
	if array_mesh == null or array_mesh.get_surface_count() == 0:
		_emit_profile(region_key, tile_count,
			int(payload.get("merge_ms", 0)), 0, 0, 0,
			Time.get_ticks_msec() - t_start, "mesh", "skip(no_surfaces)")
		return null

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	var main_block_ms: int = Time.get_ticks_msec() - t_main_start
	_emit_profile(region_key, tile_count,
		int(payload.get("merge_ms", 0)), 0, 0, main_block_ms,
		Time.get_ticks_msec() - t_start, "mesh", "ok")
	return mesh_instance


# region_chunk == null bakes the full map. Returns null when the region has no
# eligible collision tiles (stale shape is still cleared in that case).
static func bake_collision(
		tile_map: TileMapLayer3D,
		region_chunk: TerrainRegionChunk = null,
		options: RegionBakeOptions = null
	) -> ConcavePolygonShape3D:
	if tile_map == null:
		return null
	options = options if options != null else RegionBakeOptions.new()
	var region_key: Vector3i = _region_key(region_chunk)
	var tile_count: int = _count_tiles(region_chunk, tile_map)

	await _acquire_slot()
	var t_start: int = Time.get_ticks_msec()
	# extract_faces=true → worker expands surface indices into a flat face-vertex
	# array so the main thread only does set_faces() + attach.
	var payload: Dictionary = await _run_merge_on_worker(tile_map, region_chunk, options, true)
	var t_main_start: int = Time.get_ticks_msec()
	_release_slot()

	var merge_ms: int = int(payload.get("merge_ms", 0))
	var extract_ms: int = int(payload.get("extract_ms", 0))

	if not payload.get("success", false):
		if payload.get("empty_region", false):
			tile_map.clear_collision_shapes(region_key)
			_emit_profile(region_key, tile_count, merge_ms, extract_ms, 0,
				Time.get_ticks_msec() - t_main_start,
				Time.get_ticks_msec() - t_start, "collision", "empty")
			return null
		push_error("%s merge failed for region %s: %s" % [
			_PROFILE_TAG, region_key, payload.get("error", "unknown")
		])
		_emit_profile(region_key, tile_count, merge_ms, extract_ms, 0,
			Time.get_ticks_msec() - t_main_start,
			Time.get_ticks_msec() - t_start, "collision", "fail")
		return null

	var face_verts: PackedVector3Array = payload.get("face_verts", PackedVector3Array())
	if face_verts.is_empty():
		tile_map.clear_collision_shapes(region_key)
		_emit_profile(region_key, tile_count, merge_ms, extract_ms, 0,
			Time.get_ticks_msec() - t_main_start,
			Time.get_ticks_msec() - t_start, "collision", "no_faces")
		return null

	# Main-thread only: build shape + attach.
	var t_shape: int = Time.get_ticks_msec()
	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	shape.set_faces(face_verts)
	shape.backface_collision = options.backface_collision
	var shape_ms: int = Time.get_ticks_msec() - t_shape

	var t_attach: int = Time.get_ticks_msec()
	_attach_region_shape(tile_map, shape, region_key, options.attach_owner)
	var attach_ms: int = Time.get_ticks_msec() - t_attach

	var main_block_ms: int = Time.get_ticks_msec() - t_main_start
	_emit_profile(region_key, tile_count, merge_ms, extract_ms, shape_ms + attach_ms,
		main_block_ms, Time.get_ticks_msec() - t_start, "collision", "ok")
	return shape


static func _run_merge_on_worker(
		tile_map: TileMapLayer3D,
		region_chunk: TerrainRegionChunk,
		options: RegionBakeOptions,
		extract_faces: bool
	) -> Dictionary:
	var job: _BakeJob = _BakeJob.new()
	var task: Callable = func() -> void:
		var result: Dictionary = _merge_worker_body(tile_map, region_chunk, options, extract_faces)
		job.done.emit.call_deferred(result)
	WorkerThreadPool.add_task(task)
	var payload: Dictionary = await job.done
	return payload


# Runs on the WorkerThreadPool — no scene-tree access. merge_tiles +
# surface_get_arrays + the index→face expansion are all safe off the main thread.
static func _merge_worker_body(
		tile_map: TileMapLayer3D,
		region_chunk: TerrainRegionChunk,
		options: RegionBakeOptions,
		extract_faces: bool
	) -> Dictionary:
	var t_merge: int = Time.get_ticks_msec()
	var merge_result: Dictionary = TileMeshMerger.merge_tiles(
		tile_map, options.alpha_aware, options.respect_collision_custom_data,
		region_chunk, extract_faces
	)
	var merge_ms: int = Time.get_ticks_msec() - t_merge

	var out: Dictionary = {
		"merge_ms": merge_ms,
		"extract_ms": 0,
	}
	if not merge_result.get("success", false):
		out["success"] = false
		out["error"] = merge_result.get("error", "unknown")
		out["empty_region"] = merge_result.get("empty_region", false)
		return out

	var array_mesh: ArrayMesh = merge_result.get("mesh")
	if array_mesh == null or array_mesh.get_surface_count() == 0:
		out["success"] = false
		out["error"] = "no_surfaces"
		return out

	if not extract_faces:
		out["success"] = true
		out["mesh"] = array_mesh
		return out

	var t_extract: int = Time.get_ticks_msec()
	var surface_arrays: Array = array_mesh.surface_get_arrays(0)
	var packed_verts: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
	var packed_indices: PackedInt32Array = surface_arrays[Mesh.ARRAY_INDEX]
	var vert_count: int = packed_verts.size()
	var face_verts: PackedVector3Array = PackedVector3Array()
	face_verts.resize(packed_indices.size())
	for i: int in range(packed_indices.size()):
		var vi: int = packed_indices[i]
		if vi < 0 or vi >= vert_count:
			# Bounds-check: a stale columnar_indices reports cleanly instead of
			# crashing the worker with "Bad address index".
			push_error("%s index %d out of range (verts=%d) — aborting bake." % [_PROFILE_TAG, vi, vert_count])
			out["success"] = false
			out["error"] = "stale_index"
			return out
		face_verts[i] = packed_verts[vi]

	out["success"] = true
	out["face_verts"] = face_verts
	out["extract_ms"] = Time.get_ticks_msec() - t_extract
	return out


# Block until no bake is in flight, then claim the slot. Awaiters are woken on
# each slot_free and re-check the counter, so only the first wake claims.
static func _acquire_slot() -> void:
	var s: _Serializer = _get_serializer()
	while s.in_flight > 0:
		await s.slot_free
	s.in_flight += 1


static func _release_slot() -> void:
	var s: _Serializer = _get_serializer()
	s.in_flight -= 1
	if s.in_flight < 0:
		s.in_flight = 0
	s.slot_free.emit()


# Main thread only.
static func _attach_region_shape(
		tile_map: TileMapLayer3D,
		shape: ConcavePolygonShape3D,
		region_key: Vector3i,
		owner: Node
	) -> RegionCollisionShape:
	var body: StaticCollisionBody3D = _get_or_create_collision_body(tile_map, owner)
	var existing: RegionCollisionShape = _find_existing_shape_for_region(body, region_key)
	if existing != null:
		# Hot path: in-place shape replace — Godot Physics treats this as a single
		# shape-data update instead of a detach + attach pair.
		existing.shape = shape
		return existing
	var collision_shape: RegionCollisionShape = RegionCollisionShape.new()
	collision_shape.name = "Region_%d_%d_%d" % [region_key.x, region_key.y, region_key.z]
	collision_shape.region_key = region_key
	collision_shape.shape = shape
	body.add_child(collision_shape)
	if owner != null:
		collision_shape.owner = owner
	return collision_shape


static func _find_existing_shape_for_region(
		body: StaticCollisionBody3D, region_key: Vector3i
	) -> RegionCollisionShape:
	for child in body.get_children():
		if child is RegionCollisionShape and child.region_key == region_key:
			return child
	return null


static func _get_or_create_collision_body(tile_map: TileMapLayer3D, owner: Node) -> StaticCollisionBody3D:
	var cached: StaticCollisionBody3D = tile_map._collision_body
	if cached != null and is_instance_valid(cached) and cached.get_parent() == tile_map:
		return cached
	# Re-scan once — covers scene-load where the body exists as a child but the
	# cache wasn't populated yet.
	for child in tile_map.get_children():
		if child is StaticCollisionBody3D:
			tile_map._collision_body = child
			return child
	var body: StaticCollisionBody3D = StaticCollisionBody3D.new()
	body.name = tile_map.name + "_Collision"
	body.collision_layer = tile_map.collision_layer
	body.collision_mask = tile_map.collision_mask
	tile_map.add_child(body)
	if owner != null:
		body.owner = owner
	tile_map._collision_body = body
	return body


static func _region_key(region_chunk: TerrainRegionChunk) -> Vector3i:
	return region_chunk.region_key if region_chunk != null else Vector3i.MAX


static func _count_tiles(region_chunk: TerrainRegionChunk, tile_map: TileMapLayer3D) -> int:
	if region_chunk != null:
		return region_chunk.tile_keys.size() + region_chunk.vertex_tile_keys.size()
	return tile_map.get_tile_count() + tile_map.get_vertex_tile_corners().size()


static func _emit_profile(
		region_key: Vector3i, tiles: int,
		merge_ms: int, extract_ms: int, set_faces_ms: int,
		main_ms: int, total_ms: int,
		kind: String, status: String
	) -> void:
	if not GlobalConstants.DEBUG_BAKE_PROFILE:
		return
	print("%s kind=%s region=%s tiles=%d merge_ms=%d extract_ms=%d set_faces_ms=%d main_ms=%d total_ms=%d status=%s" % [
		_PROFILE_TAG, kind, region_key, tiles,
		merge_ms, extract_ms, set_faces_ms, main_ms, total_ms, status
	])
