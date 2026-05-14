class_name CollisionGenerator extends RefCounted

## Pure async bake pipeline: builds a ConcavePolygonShape3D from a TileMapLayer3D's tiles.
## Mesh merge runs on WorkerThreadPool; shape construction and signal emission are deferred
## to the main thread. Callers are responsible for building the StaticCollisionBody3D,
## adding it to the scene tree, and (in the editor) saving the .res file.

## Emitted on the main thread once the shape is ready (or bake failed).
## shape is null when success is false.
## region_key is Vector3i.MAX for full-map, or the region's key for regional bakes.
signal completed(success: bool, shape: ConcavePolygonShape3D, region_key: Vector3i)

var _tile_map_ref: WeakRef
var _alpha_aware: bool = false
var _backface: bool = false
var _running: bool = false
var _region_chunk: TerrainRegionChunk = null


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
	_region_chunk = region_chunk
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
	var tile_map: TileMapLayer3D = _tile_map_ref.get_ref()
	if tile_map == null:
		_apply_on_main.call_deferred(PackedVector3Array(), false)
		return

	var array_mesh: ArrayMesh = _build_mesh(tile_map)
	if array_mesh == null:
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


func _build_mesh(tile_map: TileMapLayer3D) -> ArrayMesh:
	var merge_result: Dictionary = TileMeshMerger.merge_tiles(
		tile_map, _alpha_aware, true, _region_chunk
	)
	if not merge_result.get("success", false):
		push_error("[CollisionGenerator] mesh merge failed — %s" \
			% merge_result.get("error", "unknown error"))
		return null
	var array_mesh: ArrayMesh = merge_result.mesh
	if array_mesh == null or array_mesh.get_surface_count() == 0:
		push_error("[CollisionGenerator] merged mesh has no surfaces.")
		return null
	return array_mesh


## Runs on the main thread (deferred). Builds the ConcavePolygonShape3D and emits completed.
## Does not touch the scene tree — callers are responsible for all body/shape management.
func _apply_on_main(face_verts: PackedVector3Array, merge_ok: bool) -> void:
	var region_key: Vector3i = _region_chunk.region_key if _region_chunk != null else Vector3i.MAX
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
