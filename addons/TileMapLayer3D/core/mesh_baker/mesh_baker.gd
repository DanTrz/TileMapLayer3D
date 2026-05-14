class_name MeshBaker extends RefCounted

## Async pipeline for baking a TileMapLayer3D into a MeshInstance3D.
## Mirrors CollisionGenerator: TileMeshMerger.merge_tiles runs on WorkerThreadPool;
## scene-tree mutations are left to the caller after awaiting completed.

## Emitted on the main thread after the mesh is built.
## mesh_instance is null when success is false.
signal completed(success: bool, mesh_instance: MeshInstance3D)

var _tile_map_ref: WeakRef
var _alpha_aware: bool = false
var _region_chunk: TerrainRegionChunk = null
var _running: bool = false


## Kick off async baking. Pass region_chunk to bake only that 30-unit region;
## null = full map. Returns false when already running, tile_map is null,
## or the tile_map has no tiles. completed(false, null) is still emitted
## (deferred) on those failure paths so awaiters never hang.
func start(tile_map: TileMapLayer3D, alpha_aware: bool = false, region_chunk: TerrainRegionChunk = null) -> bool:
	if _running:
		return false
	if tile_map == null:
		completed.emit.call_deferred(false, null)
		return false
	if tile_map.get_tile_count() == 0 and tile_map.get_vertex_tile_corners().is_empty():
		push_warning("[MeshBaker] start: no tiles to bake.")
		completed.emit.call_deferred(false, null)
		return false

	_tile_map_ref = weakref(tile_map)
	_alpha_aware = alpha_aware
	_region_chunk = region_chunk
	_running = true
	WorkerThreadPool.add_task(_run_on_thread)
	return true


## True between start() and the corresponding completed emission.
func is_running() -> bool:
	return _running


## Runs on WorkerThreadPool. TileMeshMerger.merge_tiles and MeshInstance3D
## construction are safe off the main thread (no scene-tree access).
func _run_on_thread() -> void:
	var tile_map: TileMapLayer3D = _tile_map_ref.get_ref()
	if tile_map == null:
		_finish.call_deferred(null, false)
		return

	var merge_result: Dictionary = TileMeshMerger.merge_tiles(tile_map, _alpha_aware, false, _region_chunk)
	if not merge_result.get("success", false):
		push_error("[MeshBaker] mesh merge failed — %s" \
			% merge_result.get("error", "unknown error"))
		_finish.call_deferred(null, false)
		return

	var array_mesh: ArrayMesh = merge_result.get("mesh")
	if array_mesh == null:
		push_error("[MeshBaker] merge returned null mesh.")
		_finish.call_deferred(null, false)
		return

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	_finish.call_deferred(mesh_instance, true)


## Runs on the main thread (deferred). Emits completed so the caller can do
## scene-tree work (add_child, set_owner, undo/redo) on the main thread.
func _finish(mesh_instance: MeshInstance3D, ok: bool) -> void:
	_running = false
	completed.emit(ok, mesh_instance)
