class_name CollisionGenerator extends RefCounted

## Single async pipeline for building a ConcavePolygonShape3D from a TileMapLayer3D
## and attaching it under a StaticCollisionBody3D. Used by both the editor plugin
## (TileMapLayer3D_plugin._on_create_collision_requested) and the runtime API
## (TileMapRuntimeAPI.generate_collision). Mesh merge runs on WorkerThreadPool;
## scene-tree mutations are deferred to the main thread.

## Emitted on the main thread once the ConcavePolygonShape3D exists but BEFORE
## it is wrapped in a CollisionShape3D / StaticCollisionBody3D and added to the
## tree. Handlers may call replace_shape() to swap in a different instance
## (e.g. one reloaded from disk after ResourceSaver.save).
signal shape_ready(shape: ConcavePolygonShape3D)

## Emitted on the main thread after the StaticCollisionBody3D has been added
## under the tile_map. body is null when success is false.
signal completed(success: bool, body: StaticCollisionBody3D)

var _tile_map_ref: WeakRef
var _alpha_aware: bool = false
var _backface: bool = false
var _shape: ConcavePolygonShape3D = null
var _running: bool = false


## Kick off collision generation. Returns false synchronously when a generation
## is already in flight on this instance or when the tile_map has no geometry.
## On the empty-tilemap path, completed(false, null) is still emitted (deferred)
## so awaiters never hang.
func start(tile_map: TileMapLayer3D, options: Dictionary) -> bool:
	if _running:
		return false
	if tile_map == null:
		completed.emit.call_deferred(false, null)
		return false
	if tile_map.get_tile_count() == 0 and tile_map.get_vertex_tile_corners().is_empty():
		push_warning("[CollisionGenerator] start: no tiles to generate collision from.")
		completed.emit.call_deferred(false, null)
		return false

	_tile_map_ref = weakref(tile_map)
	_alpha_aware = options.get("alpha_aware", false)
	_backface = options.get("backface_collision", false)
	_running = true
	WorkerThreadPool.add_task(_run_on_thread)
	return true


## Replace the shape that will be wrapped in CollisionShape3D. Valid to call
## only from a shape_ready handler — the swap is observed when the generator
## continues building the body.
func replace_shape(new_shape: ConcavePolygonShape3D) -> void:
	if new_shape != null:
		_shape = new_shape


## True between start() and the corresponding completed emission.
func is_running() -> bool:
	return _running


## Runs on WorkerThreadPool. Builds the face-vertex array from the merged
## ArrayMesh — safe off the main thread because TileMeshMerger.merge_tiles
## and surface_get_arrays do not touch scene-tree state.
func _run_on_thread() -> void:
	var tile_map: TileMapLayer3D = _tile_map_ref.get_ref()
	if tile_map == null:
		_apply_on_main.call_deferred(PackedVector3Array(), false)
		return

	var merge_result: Dictionary = TileMeshMerger.merge_tiles(tile_map, {
		"alpha_aware": _alpha_aware,
		"respect_tile_collision_custom_data": true
	})
	if not merge_result.get("success", false):
		push_error("[CollisionGenerator] mesh merge failed — %s" \
			% merge_result.get("error", "unknown error"))
		_apply_on_main.call_deferred(PackedVector3Array(), false)
		return

	var array_mesh: ArrayMesh = merge_result.mesh
	if array_mesh == null or array_mesh.get_surface_count() == 0:
		push_error("[CollisionGenerator] merged mesh has no surfaces.")
		_apply_on_main.call_deferred(PackedVector3Array(), false)
		return

	var surface_arrays: Array = array_mesh.surface_get_arrays(0)
	var packed_verts: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
	var packed_indices: PackedInt32Array = surface_arrays[Mesh.ARRAY_INDEX]
	var face_verts: PackedVector3Array = PackedVector3Array()
	face_verts.resize(packed_indices.size())
	for i: int in range(packed_indices.size()):
		face_verts[i] = packed_verts[packed_indices[i]]

	_apply_on_main.call_deferred(face_verts, true)


## Runs on the main thread (deferred). Builds the shape, emits shape_ready
## (giving handlers a chance to replace_shape), then attaches the new body.
func _apply_on_main(face_verts: PackedVector3Array, merge_ok: bool) -> void:
	if not merge_ok:
		_running = false
		completed.emit(false, null)
		return

	var tile_map: TileMapLayer3D = _tile_map_ref.get_ref()
	if tile_map == null:
		_running = false
		completed.emit(false, null)
		return

	_shape = ConcavePolygonShape3D.new()
	_shape.set_faces(face_verts)
	_shape.backface_collision = _backface

	# Clear OLD collision (including any external .res file on disk) BEFORE
	# the editor's shape_ready handler writes the new .res. Inverting this
	# order causes clear_collision_shapes() to delete the .res we just wrote
	# (see tilemap_layer_3d.gd:_delete_external_collision_file).
	tile_map.clear_collision_shapes()

	shape_ready.emit(_shape)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.shape = _shape

	var static_body: StaticCollisionBody3D = StaticCollisionBody3D.new()
	static_body.collision_layer = tile_map.collision_layer
	static_body.collision_mask = tile_map.collision_mask
	static_body.add_child(collision_shape)
	tile_map.add_child(static_body)

	_running = false
	completed.emit(true, static_body)
