class_name CollisionGenerator extends RefCounted

## Pure async bake pipeline: builds a ConcavePolygonShape3D from a TileMapLayer3D's tiles.
## Mesh merge runs on WorkerThreadPool; shape construction and signal emission are deferred
## to the main thread. Callers are responsible for building the StaticCollisionBody3D,
## adding it to the scene tree, and (in the editor) saving the .res file.

## Emitted on the main thread once the shape is ready (or bake failed).
## shape is null when success is false OR when the region is intentionally empty
## (no eligible collision tiles): in that case success is true and the caller
## should clear any existing collision for that region.
## region_key is Vector3i.MAX for full-map, or the region's key for regional bakes.
signal completed(success: bool, shape: ConcavePolygonShape3D, region_key: Vector3i)

var _tile_map_ref: WeakRef
var _alpha_aware: bool = false
var _backface: bool = false
var _running: bool = false
var _region_chunk: TerrainRegionChunk = null
var _region_key_snapshot: Vector3i = Vector3i.MAX
var _last_empty_region: bool = false


## Kick off collision baking. Pass region_chunk to bake only that 30-unit region;
## null = full map. Returns false when already running, tile_map is null, or the
## tile_map has no geometry. completed(false, null, Vector3i.MAX) is still emitted
## (deferred) on those failure paths so awaiters never hang.
func start(tile_map: TileMapLayer3D, alpha_aware: bool = false, backface_collision: bool = false, region_chunk: TerrainRegionChunk = null) -> bool:
	if _running:
		return false
	if tile_map == null:
		completed.emit.call_deferred(false, null, Vector3i.MAX)
		return false
	if tile_map.get_tile_count() == 0 and tile_map.get_vertex_tile_corners().is_empty():
		push_warning("[CollisionGenerator] start: no tiles to generate collision from.")
		completed.emit.call_deferred(false, null, Vector3i.MAX)
		return false

	_tile_map_ref = weakref(tile_map)
	_alpha_aware = alpha_aware
	_backface = backface_collision
	# Snapshot the region's mutable index lists on the main thread so a concurrent
	# editor paint/erase cannot mutate them out from under the worker.
	if region_chunk != null:
		var snapshot: TerrainRegionChunk = TerrainRegionChunk.from_region_key(region_chunk.region_key)
		snapshot.tile_keys = region_chunk.tile_keys.duplicate()
		snapshot.columnar_indices = region_chunk.columnar_indices.duplicate()
		snapshot.vertex_tile_keys = region_chunk.vertex_tile_keys.duplicate()
		_region_chunk = snapshot
		_region_key_snapshot = region_chunk.region_key
	else:
		_region_chunk = null
		_region_key_snapshot = Vector3i.MAX
	_last_empty_region = false
	_running = true
	WorkerThreadPool.add_task(_run_on_thread)
	return true


## True between start() and the corresponding completed emission.
func is_running() -> bool:
	return _running


## Runs on WorkerThreadPool. Builds the face-vertex array from the merged ArrayMesh.
## Safe off the main thread — TileMeshMerger.merge_tiles and surface_get_arrays
## do not touch scene-tree state.
func _run_on_thread() -> void:
	# Guard against caller misuse where start() was bypassed: _tile_map_ref would
	# be null and dereferencing it crashes the worker with "Bad address index".
	if _tile_map_ref == null:
		_apply_on_main.call_deferred(PackedVector3Array(), false)
		return
	var tile_map: TileMapLayer3D = _tile_map_ref.get_ref()
	if tile_map == null:
		_apply_on_main.call_deferred(PackedVector3Array(), false)
		return

	var array_mesh: ArrayMesh = _build_mesh(tile_map)
	if array_mesh == null:
		# Treat "no eligible tiles for this region" as a successful empty bake so
		# callers can clear stale collision shapes deterministically.
		_apply_on_main.call_deferred(PackedVector3Array(), _last_empty_region)
		return

	var surface_arrays: Array = array_mesh.surface_get_arrays(0)
	var packed_verts: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
	var packed_indices: PackedInt32Array = surface_arrays[Mesh.ARRAY_INDEX]
	var vert_count: int = packed_verts.size()
	var face_verts: PackedVector3Array = PackedVector3Array()
	face_verts.resize(packed_indices.size())
	for i: int in range(packed_indices.size()):
		var vi: int = packed_indices[i]
		# Bounds-check every index so a stale TerrainRegionChunk.columnar_indices
		# (e.g. not patched after a shift-remove) reports cleanly instead of
		# crashing the worker thread with "Bad address index".
		if vi < 0 or vi >= vert_count:
			push_error("[CollisionGenerator] index %d out of range (verts=%d) for region %s — aborting bake." % [vi, vert_count, _region_key_snapshot])
			_apply_on_main.call_deferred(PackedVector3Array(), false)
			return
		face_verts[i] = packed_verts[vi]

	_apply_on_main.call_deferred(face_verts, true)


func _build_mesh(tile_map: TileMapLayer3D) -> ArrayMesh:
	var merge_result: Dictionary = TileMeshMerger.merge_tiles(
		tile_map, _alpha_aware, true, _region_chunk
	)
	if not merge_result.get("success", false):
		var error_msg: String = merge_result.get("error", "unknown error")
		# Region with no eligible tiles is a valid outcome (e.g. every tile in the
		# region was filtered out by the Collision custom data layer). The caller
		# should clear any stale shape for that region instead of leaving it.
		if merge_result.get("empty_region", false):
			_last_empty_region = true
			return null
		push_error("[CollisionGenerator] mesh merge failed — %s" % error_msg)
		return null
	var array_mesh: ArrayMesh = merge_result.mesh
	if array_mesh == null or array_mesh.get_surface_count() == 0:
		push_error("[CollisionGenerator] merged mesh has no surfaces.")
		return null
	return array_mesh


## Runs on the main thread (deferred). Builds the ConcavePolygonShape3D and emits completed.
## Does not touch the scene tree — callers are responsible for all body/shape management.
## When the region has no eligible tiles, emits (true, null, region_key) so the caller
## can clear the region's existing shape.
func _apply_on_main(face_verts: PackedVector3Array, merge_ok: bool) -> void:
	var region_key: Vector3i = _region_key_snapshot
	# _running is cleared on the main thread (this method is deferred), so a caller
	# polling is_running() between WorkerThreadPool.add_task and this call may briefly
	# see true after the worker is actually done. Prefer awaiting `completed` instead.
	_running = false

	if not merge_ok:
		completed.emit(false, null, region_key)
		return

	if _tile_map_ref.get_ref() == null:
		completed.emit(false, null, region_key)
		return

	if face_verts.is_empty():
		# Empty region — success with null shape signals "clear collision for this region".
		completed.emit(true, null, region_key)
		return

	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	shape.set_faces(face_verts)
	shape.backface_collision = _backface
	completed.emit(true, shape, region_key)


## Attach a RegionCollisionShape carrying [param shape] to [param body], replacing
## any existing shape for [param region_key]. Used by both the editor plugin and
## the runtime API so the attach logic stays in one place. When [param owner] is
## non-null, the new shape becomes a child of that scene root (editor save path);
## leave null for runtime hot-swap (no scene ownership needed).
static func attach_region_shape(
	tile_map: TileMapLayer3D,
	body: StaticCollisionBody3D,
	shape: ConcavePolygonShape3D,
	region_key: Vector3i,
	owner: Node = null
) -> RegionCollisionShape:
	tile_map.clear_collision_shapes(region_key)
	var collision_shape: RegionCollisionShape = RegionCollisionShape.new()
	collision_shape.name = "Region_%d_%d_%d" % [region_key.x, region_key.y, region_key.z]
	collision_shape.region_key = region_key
	collision_shape.shape = shape
	body.add_child(collision_shape)
	if owner != null:
		collision_shape.owner = owner
	return collision_shape
