class_name RegionBaker
extends RefCounted

## Single-call bake pipeline for the TileMapLayer3D. One code path for editor
## and runtime, one class — replaces the old MeshBaker + CollisionGenerator pair.
##
## Two entry points — both work for full-map or one TerrainRegionChunk:
##   * bake_mesh()      — returns a fresh MeshInstance3D (visual bake; caller
##                        owns parenting, naming, and undo/redo).
##   * bake_collision() — replaces the RegionCollisionShape for the region on
##                        the layer's StaticCollisionBody3D and returns the
##                        ConcavePolygonShape3D it built (null on empty region).
##
## Both are coroutines (`await`-able). The heavy work runs on a WorkerThreadPool
## task so the main thread keeps rendering at 60 FPS during the bake:
##
##   Worker thread:  TileMeshMerger.merge_tiles (~200 ms for a large region)
##                   + index→face-vertex expansion for collision (~50 ms)
##   Main thread:    ConcavePolygonShape3D.set_faces (~20 ms)
##                   + RegionCollisionShape attach (~15 ms)
##
## Why this shape and not a pure-sync call:
##   * A sync call blocks the main thread for the full merge duration (~300 ms
##     for a 2000-tile region). That visibly freezes the game for ~12 frames.
##   * The old (pre-refactor) CollisionGenerator already did the heavy work
##     off-thread for the same reason — that was the architectural piece worth
##     keeping. What it got wrong was the snapshot copy, the wrapper class
##     proliferation, and the editor/runtime fork.
##
## Why ConcavePolygonShape3D.set_faces() and not MeshInstance3D.create_trimesh_collision():
##   * create_trimesh_collision() requires the MeshInstance3D be in the scene
##     tree, which forces the call to the main thread.
##   * The GDScript index→face expansion + set_faces() can run on the worker
##     (extraction) and main thread (set_faces only). That's a smaller main-
##     thread footprint than create_trimesh_collision() AND it matches the
##     fast path the user observed before the refactor.
##
## Concurrency: each call captures its own region_chunk reference at entry,
## then the worker reads the region's tile_keys / columnar_indices arrays
## directly. Those arrays are only mutated by TilePlacementManager on the main
## thread, and the user has confirmed no bake is ever triggered during a paint
## stroke. The defensive TerrainRegionChunk.duplicate() the old code did is
## therefore unnecessary.
##
## Serialization: multiple stacked calls (e.g. game script swapping textures
## across many regions in one frame) chain through a static gate so workers
## don't fight each other for the columnar arrays.

const _PROFILE_TAG: String = "[RegionBaker]"


## Inner serializer. Static singleton owning the slot_free signal so awaiters
## can chain when a bake is already in flight. Counting (not boolean) so future
## opt-in concurrent bakes only need to bump _max_in_flight.
class _Serializer extends RefCounted:
	signal slot_free
	var in_flight: int = 0

# Lazy init via _get_serializer() — declaring `static var _serializer: _Serializer
# = _Serializer.new()` reads as null at runtime in Godot 4.6 when the initializer
# touches an inner class declared in the same script (load-order race). The lazy
# accessor sidesteps that entirely.
static var _serializer: _Serializer = null

static func _get_serializer() -> _Serializer:
	if _serializer == null:
		_serializer = _Serializer.new()
	return _serializer


## Per-call job carrying the worker-to-main signal. Each bake creates one,
## awaits its `done` signal, then discards it. Holding a strong ref via the
## bound Callable on the worker keeps the job alive until completion.
class _BakeJob extends RefCounted:
	signal done(payload: Dictionary)


# --- Public API ---


## Bake the region's geometry to a fresh MeshInstance3D and return it.
## region_chunk == null bakes the full map. Caller is responsible for
## add_child / set_owner / undo. Returns null on failure or empty region.
## Coroutine — `await RegionBaker.bake_mesh(...)`.
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


## Bake collision for one region (or full map when region_chunk == null).
## Replaces the existing RegionCollisionShape for that region on tile_map's
## StaticCollisionBody3D. Returns the new shape, or null when the region has
## no eligible collision tiles (stale shape is still cleared in that case).
## Coroutine — `await RegionBaker.bake_collision(...)`.
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
	# extract_faces=true → worker also expands surface indices into a flat
	# face-vertex array so the main thread only does set_faces() + attach.
	var payload: Dictionary = await _run_merge_on_worker(tile_map, region_chunk, options, true)
	var t_main_start: int = Time.get_ticks_msec()
	_release_slot()

	var merge_ms: int = int(payload.get("merge_ms", 0))
	var extract_ms: int = int(payload.get("extract_ms", 0))

	# Empty region (no eligible collision tiles): clear stale shape, return null
	# as a successful "this region has no collision now" signal.
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

	# Main-thread work: build shape + attach. set_faces is C++ and fast (~20 ms
	# for 60k indices), attach is a few node mutations (~15 ms).
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


# --- Worker dispatch ---


## Dispatch the merge to a WorkerThreadPool task and await its completion.
## When [param extract_faces] is true the worker also expands the surface
## index buffer into a flat face-vertex PackedVector3Array (for set_faces()).
##
## Returns a Dictionary:
##   success: bool
##   error / empty_region: optional failure metadata from TileMeshMerger
##   mesh: ArrayMesh (mesh path only)
##   face_verts: PackedVector3Array (collision path only)
##   merge_ms: int
##   extract_ms: int (collision path only)
static func _run_merge_on_worker(
		tile_map: TileMapLayer3D,
		region_chunk: TerrainRegionChunk,
		options: RegionBakeOptions,
		extract_faces: bool
	) -> Dictionary:
	var job: _BakeJob = _BakeJob.new()
	# The Callable holds a strong ref to `job` for the duration of the worker
	# task, so the RefCounted survives across the deferred emit. Same trick the
	# old CollisionGenerator used via _collision_generators.
	var task: Callable = func() -> void:
		var result: Dictionary = _merge_worker_body(tile_map, region_chunk, options, extract_faces)
		job.done.emit.call_deferred(result)
	WorkerThreadPool.add_task(task)
	var payload: Dictionary = await job.done
	return payload


## Runs on the WorkerThreadPool. Pure data path — no scene-tree access.
## TileMeshMerger.merge_tiles + surface_get_arrays + the index→face expansion
## are all safe off the main thread (verified against the previous
## CollisionGenerator._run_on_thread implementation).
static func _merge_worker_body(
		tile_map: TileMapLayer3D,
		region_chunk: TerrainRegionChunk,
		options: RegionBakeOptions,
		extract_faces: bool
	) -> Dictionary:
	var t_merge: int = Time.get_ticks_msec()
	# Pass extract_faces as the merger's `collision_only` flag. When true, the
	# merger gates the per-mode breakdown print (collision_merge_detail) ON and
	# routes into its tighter collision-only code paths. When false (bake_mesh),
	# the merger stays on its visual path which builds UVs/normals/material.
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

	# Collision path: expand the index buffer into a flat face-vertex array.
	# Same loop as the pre-refactor CollisionGenerator. Runs on the worker so
	# the main thread never pays for it.
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
			# Bounds-check: a stale TerrainRegionChunk.columnar_indices would
			# report cleanly instead of crashing the worker with "Bad address index".
			push_error("%s index %d out of range (verts=%d) — aborting bake." % [_PROFILE_TAG, vi, vert_count])
			out["success"] = false
			out["error"] = "stale_index"
			return out
		face_verts[i] = packed_verts[vi]

	out["success"] = true
	out["face_verts"] = face_verts
	out["extract_ms"] = Time.get_ticks_msec() - t_extract
	return out


# --- Serialization ---


## Block until no bake is in flight, then claim the slot. Multiple awaiters
## are woken on each slot_free emission and re-check the counter, so the
## first wake claims the slot and others loop.
static func _acquire_slot() -> void:
	var s: _Serializer = _get_serializer()
	while s.in_flight > 0:
		await s.slot_free
	s.in_flight += 1


static func _release_slot() -> void:
	var s: _Serializer = _get_serializer()
	s.in_flight -= 1
	if s.in_flight < 0:
		s.in_flight = 0  # defensive — should never go negative
	s.slot_free.emit()


# --- Scene-tree helpers (main thread only) ---


## Install [shape] as the collision for [region_key] on [tile_map]'s
## StaticCollisionBody3D. Two code paths:
##
##   HOT (existing node found): swap the existing RegionCollisionShape's
##   `.shape` property in place. No queue_free, no add_child, one physics
##   shape-replace instead of detach+attach. This is the runtime hot-swap path.
##
##   COLD (no existing node for this region): create a new RegionCollisionShape,
##   parent it under the body. First-time bake, or after a "Clear Collisions"
##   editor action that wiped the body's children.
##
## When [owner] is non-null (editor save path) the new node is owned by that
## scene root so it persists in the .tscn. The hot path doesn't touch ownership
## because the existing node already has it.
static func _attach_region_shape(
		tile_map: TileMapLayer3D,
		shape: ConcavePolygonShape3D,
		region_key: Vector3i,
		owner: Node
	) -> RegionCollisionShape:
	var body: StaticCollisionBody3D = _get_or_create_collision_body(tile_map, owner)
	var existing: RegionCollisionShape = _find_existing_shape_for_region(body, region_key)
	if existing != null:
		# Hot path: in-place shape replace. Godot Physics treats this as a single
		# shape-data update instead of a detach + attach pair.
		existing.shape = shape
		return existing
	# Cold path: build a fresh node for this region.
	var collision_shape: RegionCollisionShape = RegionCollisionShape.new()
	collision_shape.name = "Region_%d_%d_%d" % [region_key.x, region_key.y, region_key.z]
	collision_shape.region_key = region_key
	collision_shape.shape = shape
	body.add_child(collision_shape)
	if owner != null:
		collision_shape.owner = owner
	return collision_shape


## Linear lookup over the body's children for a RegionCollisionShape whose
## region_key matches. O(children) — typically tens for a fully baked scene.
## Returns null when no match (cold-path trigger).
static func _find_existing_shape_for_region(
		body: StaticCollisionBody3D, region_key: Vector3i
	) -> RegionCollisionShape:
	for child in body.get_children():
		if child is RegionCollisionShape and child.region_key == region_key:
			return child
	return null


## Cached StaticCollisionBody3D lookup. tile_map._collision_body holds a strong
## ref that survives across calls; on first call (or after a clear) we re-scan.
## owner is used only when we have to create the body fresh.
static func _get_or_create_collision_body(tile_map: TileMapLayer3D, owner: Node) -> StaticCollisionBody3D:
	var cached: StaticCollisionBody3D = tile_map._collision_body
	if cached != null and is_instance_valid(cached) and cached.get_parent() == tile_map:
		return cached
	# Re-scan once — covers scene-load case where the body exists as a child
	# but the cache wasn't populated yet.
	for child in tile_map.get_children():
		if child is StaticCollisionBody3D:
			tile_map._collision_body = child
			return child
	# None found: build one. Match the editor naming convention.
	var body: StaticCollisionBody3D = StaticCollisionBody3D.new()
	body.name = tile_map.name + "_Collision"
	body.collision_layer = tile_map.collision_layer
	body.collision_mask = tile_map.collision_mask
	tile_map.add_child(body)
	if owner != null:
		body.owner = owner
	tile_map._collision_body = body
	return body


# --- Helpers ---


static func _region_key(region_chunk: TerrainRegionChunk) -> Vector3i:
	return region_chunk.region_key if region_chunk != null else Vector3i.MAX


static func _count_tiles(region_chunk: TerrainRegionChunk, tile_map: TileMapLayer3D) -> int:
	if region_chunk != null:
		return region_chunk.tile_keys.size() + region_chunk.vertex_tile_keys.size()
	return tile_map.get_tile_count() + tile_map.get_vertex_tile_corners().size()


## Profile line emitted once per bake call. Fields:
##   merge_ms     — worker-thread merge cost (TileMeshMerger.merge_tiles)
##   extract_ms   — worker-thread index→face-vertex expansion (collision only)
##   set_faces_ms — main-thread shape build (set_faces + backface_collision + attach)
##   main_ms      — total main-thread block (deferred-callback + shape + attach)
##   total_ms     — wall-clock end-to-end including worker
## Gated by GlobalConstants.DEBUG_BAKE_PROFILE.
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
