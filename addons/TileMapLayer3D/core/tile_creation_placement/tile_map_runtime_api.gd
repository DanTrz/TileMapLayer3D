class_name TileMapRuntimeAPI extends RefCounted
## Thin runtime wrapper around TilePlacementManager for procedural tile operations.
## Provides undo-free place/erase/query operations safe to call from game scripts at runtime.
## Instantiated lazily by TileMapLayer3D._get_runtime_api() — do not create directly.


var _tile_map: TileMapLayer3D
var _placement_manager: TilePlacementManager


func _init(tile_map: TileMapLayer3D) -> void:
	_tile_map = tile_map
	_placement_manager = TilePlacementManager.new()
	_placement_manager.tile_map_layer3d_root = tile_map
	_placement_manager.grid_size = tile_map.settings.grid_size
	_placement_manager.grid_snap_size = tile_map.settings.grid_snap_size
	_placement_manager.tileset_texture = tile_map.settings.tileset_texture


## Returns the snap plane normal matching how the editor snaps for each orientation.
## FLOOR/CEILING → UP  (snap X,Z; keep Y from world hit)
## WALL_NORTH/SOUTH → FORWARD  (snap X,Y; keep Z from world hit)
## WALL_EAST/WEST  → RIGHT     (snap Y,Z; keep X from world hit)
## Tilted (6+)     → ZERO      (full-axis snap — diagonal planes not axis-aligned)
static func get_snap_plane_for_orientation(orientation: int) -> Vector3:
	match orientation:
		GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
			return Vector3.UP
		GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
			return Vector3.FORWARD
		GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
			return Vector3.RIGHT
		_:
			return Vector3.ZERO  # Tilted: fall back to full-axis snap


## Snap [param grid_pos] to the nearest valid grid cell for [param orientation].
## Uses the same selective plane-snap the editor uses — only snaps axes that are
## parallel to the tile surface; the perpendicular axis is kept exact.
func snap_grid_pos(grid_pos: Vector3, orientation: int = -1) -> Vector3:
	var plane: Vector3 = get_snap_plane_for_orientation(orientation) if orientation >= 0 \
		else Vector3.ZERO
	return _placement_manager.snap_to_grid(grid_pos, plane)


## Place a tile at [param grid_pos] with the given [param uv_rect] and [param orientation].
##
## [param snap] — when true (default) the position is snapped using the same
## orientation-aware plane snap the editor uses (only parallel axes are snapped;
## the perpendicular axis is kept exact from the incoming grid position).
##
## [param tile_info] is an optional Dictionary for non-default properties:[br]
## [code]"mode"[/code] (int) — MeshMode (default: FLAT_SQUARE)[br]
## [code]"mesh_rotation"[/code] (int) — 0-3 (default: 0)[br]
## [code]"flip"[/code] (bool) — face flip (default: false)[br]
## [code]"terrain_id"[/code] (int) — autotile terrain (-1 = none)[br]
## [code]"depth_scale"[/code] (float) — BOX/PRISM depth (default: 0.1)[br]
## [code]"texture_repeat_mode"[/code] (int) — DEFAULT or REPEAT[br]
## [code]"freeze_uv"[/code] (bool) — lock UV on rotation (default: false)[br]
## [code]"spin_angle_rad"[/code], [code]"tilt_angle_rad"[/code], [code]"diagonal_scale"[/code], [code]"tilt_offset_factor"[/code] — transform overrides[br]
##
## Returns true on success.
func place_tile(grid_pos: Vector3, uv_rect: Rect2, orientation: int = 0,
		tile_info: Dictionary = {}, snap: bool = true) -> bool:
	var pos: Vector3 = snap_grid_pos(grid_pos, orientation) if snap else grid_pos
	var tile_key: int = GlobalUtil.make_tile_key(pos, orientation)
	var mesh_rotation: int = tile_info.get("mesh_rotation", 0)
	_placement_manager._do_place_tile(tile_key, pos, uv_rect, orientation, mesh_rotation, tile_info)
	return true


## Erase the tile at [param grid_pos] / [param orientation].
## [param snap] — snap using orientation-aware plane snap before lookup (default: true).
## Returns true if a tile existed and was removed, false if nothing was there.
func erase_tile(grid_pos: Vector3, orientation: int = 0, snap: bool = true) -> bool:
	var pos: Vector3 = snap_grid_pos(grid_pos, orientation) if snap else grid_pos
	var tile_key: int = GlobalUtil.make_tile_key(pos, orientation)
	if not _tile_map.has_tile(tile_key):
		return false
	_placement_manager._do_erase_tile(tile_key)
	return true


## Return all tile data at [param grid_pos] / [param orientation] as a Dictionary.
## [param snap] — snap using orientation-aware plane snap before lookup (default: true).
## Returns an empty Dictionary if no tile exists at that location.
## Dictionary keys match [method TileMapLayer3D.get_tile_data_at] output.
func get_tile(grid_pos: Vector3, orientation: int = 0, snap: bool = true) -> Dictionary:
	var pos: Vector3 = snap_grid_pos(grid_pos, orientation) if snap else grid_pos
	var tile_key: int = GlobalUtil.make_tile_key(pos, orientation)
	var index: int = _tile_map.get_tile_index(tile_key)
	if index < 0:
		return {}
	return _tile_map.get_tile_data_at(index)


## Defer GPU MultiMesh sync for bulk operations.
## Call before placing many tiles, then [method end_batch] when done.
## Supports nesting — each begin must have a matching end.
func begin_batch() -> void:
	_placement_manager.begin_batch_update()


## Flush pending GPU updates after a [method begin_batch] / [method end_batch] block.
func end_batch() -> void:
	_placement_manager.end_batch_update()
