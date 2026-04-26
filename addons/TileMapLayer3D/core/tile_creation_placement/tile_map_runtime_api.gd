class_name TileMapRuntimeAPI extends RefCounted
## Runtime placement/query helper used by TileMapLayer3D's public runtime_* methods.
##
## Coordinate spaces used here:
## - world: normal Node3D world coordinates; this is what gameplay scripts should use.
## - map: user-facing tile coordinates. For base orientations, face-parallel axes are
##   tile indices and the perpendicular axis is the exact face plane.
## - storage grid: internal TileMapLayer3D coordinates used by tile keys/transforms.
##
## Prefer world/area methods for gameplay. Use map methods for procedural builders
## that intentionally count tile steps.
## Instantiated lazily by TileMapLayer3D._get_runtime_api() — do not create directly.


var _tile_map: TileMapLayer3D
var _placement_manager: TilePlacementManager

const ANY_ORIENTATION: int = -1
const BASE_ORIENTATIONS: Array[int] = [
	GlobalUtil.TileOrientation.FLOOR,
	GlobalUtil.TileOrientation.CEILING,
	GlobalUtil.TileOrientation.WALL_NORTH,
	GlobalUtil.TileOrientation.WALL_SOUTH,
	GlobalUtil.TileOrientation.WALL_EAST,
	GlobalUtil.TileOrientation.WALL_WEST,
]


# --- Setup and Result Helpers ---

func _init(tile_map: TileMapLayer3D) -> void:
	_tile_map = tile_map
	_placement_manager = TilePlacementManager.new()
	_placement_manager.tile_map_layer3d_root = tile_map
	_sync_settings()


## Sync placement-manager state from the live TileMapLayerSettings resource.
## Called at the start of every public mutator so settings changes after init
## are honored (e.g. user updates grid_snap_size at runtime).
func _sync_settings() -> void:
	_placement_manager.grid_size = _tile_map.settings.grid_size
	_placement_manager.grid_snap_size = _tile_map.settings.grid_snap_size
	_placement_manager.tileset_texture = _tile_map.settings.tileset_texture


func _new_result() -> Dictionary:
	return {
		"ok": true,
		"placed": 0,
		"erased": 0,
		"found": 0,
		"skipped": 0,
		"tile_keys": [],
		"tiles": [],
		"errors": [],
		"anchor_grid": Vector3.ZERO,
	}


func _is_base_orientation(orientation: int) -> bool:
	return BASE_ORIENTATIONS.has(orientation)


func _append_error(result: Dictionary, message: String) -> void:
	result["ok"] = false
	result["errors"].append(message)


func _validate_area_args(result: Dictionary, operation: String, orientation: int, size: Vector2i) -> bool:
	if not _is_base_orientation(orientation):
		_append_error(result, "%s: orientation must be one of the six base orientations." % operation)
		return false
	if size.x <= 0 or size.y <= 0:
		_append_error(result, "%s: size must be greater than zero on both axes." % operation)
		return false
	return true


# --- Coordinate Conversion Internals ---

func _world_to_storage_grid(world_pos: Vector3) -> Vector3:
	_sync_settings()
	return GlobalUtil.world_to_grid(world_pos - _tile_map.global_position, _placement_manager.grid_size)


func _snap_value(value: float) -> float:
	return snappedf(value, _placement_manager.grid_snap_size)


## Converts user-facing map coordinates to the storage grid used by tile keys.
func _logical_map_to_storage(logical_map_pos: Vector3, orientation: int) -> Vector3:
	match orientation:
		GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
			return Vector3(
				logical_map_pos.x,
				logical_map_pos.y - GlobalConstants.GRID_ALIGNMENT_OFFSET.y,
				logical_map_pos.z
			)
		GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
			return Vector3(
				logical_map_pos.x,
				logical_map_pos.y,
				logical_map_pos.z - GlobalConstants.GRID_ALIGNMENT_OFFSET.z
			)
		GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
			return Vector3(
				logical_map_pos.x - GlobalConstants.GRID_ALIGNMENT_OFFSET.x,
				logical_map_pos.y,
				logical_map_pos.z
			)
		_:
			return snap_grid_pos(logical_map_pos, orientation)


# --- Area Iteration Internals ---

func _area_offset(orientation: int, u: int, v: int) -> Vector3:
	match orientation:
		GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
			return Vector3(float(u), 0.0, float(v))
		GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
			return Vector3(float(u), float(v), 0.0)
		GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
			return Vector3(0.0, float(v), float(u))
		_:
			return Vector3(float(u), 0.0, float(v))


func _center_anchor_offset(orientation: int, size: Vector2i) -> Vector3:
	var half_u: int = int(floor(float(size.x) * 0.5))
	var half_v: int = int(floor(float(size.y) * 0.5))
	return -_area_offset(orientation, half_u, half_v)


func _area_anchor_map(anchor_world: Vector3, orientation: int, size: Vector2i, options: Dictionary) -> Vector3:
	var anchor_map: Vector3 = world_to_map(anchor_world, orientation)
	if str(options.get("anchor", "origin")) == "center":
		anchor_map += _center_anchor_offset(orientation, size)
	return anchor_map


func _area_map_positions(anchor_map: Vector3, orientation: int, size: Vector2i) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for u: int in range(size.x):
		for v: int in range(size.y):
			positions.append(anchor_map + _area_offset(orientation, u, v))
	return positions


func _tile_key_for_logical_map(logical_map_pos: Vector3, orientation: int) -> int:
	return GlobalUtil.make_tile_key(_logical_map_to_storage(logical_map_pos, orientation), orientation)


func _tile_data_for_logical_map(logical_map_pos: Vector3, orientation: int) -> Dictionary:
	var storage_pos: Vector3 = _logical_map_to_storage(logical_map_pos, orientation)
	var tile_key: int = GlobalUtil.make_tile_key(storage_pos, orientation)
	var index: int = _tile_map.get_tile_index(tile_key)
	if index < 0:
		return {}
	var data: Dictionary = _tile_map.get_tile_data_at(index)
	data["tile_key"] = tile_key
	data["map_position"] = logical_map_pos
	data["world_position"] = map_to_world(logical_map_pos, orientation)
	return data


func _find_orientations(orientation: int) -> Array[int]:
	if orientation == ANY_ORIENTATION:
		return BASE_ORIENTATIONS
	return [orientation]


# --- Public Coordinate Helpers ---

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
	_sync_settings()
	var plane: Vector3 = get_snap_plane_for_orientation(orientation) if orientation >= 0 \
		else Vector3.ZERO
	return _placement_manager.snap_to_grid(grid_pos, plane)


## Convert a world-space point to user-facing map coordinates.
##
## Use this when game/procedural logic wants to count tile offsets from a world
## hit or player position. For base orientations, the result is face-aware:
## FLOOR/CEILING use X/Z tile cells and a Y plane; walls use their two face axes
## plus the perpendicular face plane.
func world_to_map(world_pos: Vector3, orientation: int = ANY_ORIENTATION) -> Vector3:
	_sync_settings()
	var local_units: Vector3 = (world_pos - _tile_map.global_position) / _placement_manager.grid_size
	if not _is_base_orientation(orientation):
		return snap_grid_pos(GlobalUtil.world_to_grid(world_pos - _tile_map.global_position, _placement_manager.grid_size), orientation)

	match orientation:
		GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
			return Vector3(
				_snap_value(local_units.x - GlobalConstants.GRID_ALIGNMENT_OFFSET.x),
				_snap_value(local_units.y),
				_snap_value(local_units.z - GlobalConstants.GRID_ALIGNMENT_OFFSET.z)
			)
		GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
			return Vector3(
				_snap_value(local_units.x - GlobalConstants.GRID_ALIGNMENT_OFFSET.x),
				_snap_value(local_units.y - GlobalConstants.GRID_ALIGNMENT_OFFSET.y),
				_snap_value(local_units.z)
			)
		GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
			return Vector3(
				_snap_value(local_units.x),
				_snap_value(local_units.y - GlobalConstants.GRID_ALIGNMENT_OFFSET.y),
				_snap_value(local_units.z - GlobalConstants.GRID_ALIGNMENT_OFFSET.z)
			)
		_:
			return snap_grid_pos(GlobalUtil.world_to_grid(world_pos - _tile_map.global_position, _placement_manager.grid_size), orientation)


## Convert user-facing map coordinates to a world-space anchor.
##
## This is the companion to world_to_map(). The result is suitable for
## place_tile_at_world(), place_area(), find_tile_at_world(), and highlights.
func map_to_world(map_pos: Vector3, orientation: int = ANY_ORIENTATION) -> Vector3:
	_sync_settings()
	if not _is_base_orientation(orientation):
		return GlobalUtil.grid_to_world(map_pos, _placement_manager.grid_size) + _tile_map.global_position

	match orientation:
		GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
			return Vector3(
				_tile_map.global_position.x + (map_pos.x + GlobalConstants.GRID_ALIGNMENT_OFFSET.x) * _placement_manager.grid_size,
				_tile_map.global_position.y + map_pos.y * _placement_manager.grid_size,
				_tile_map.global_position.z + (map_pos.z + GlobalConstants.GRID_ALIGNMENT_OFFSET.z) * _placement_manager.grid_size
			)
		GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
			return Vector3(
				_tile_map.global_position.x + (map_pos.x + GlobalConstants.GRID_ALIGNMENT_OFFSET.x) * _placement_manager.grid_size,
				_tile_map.global_position.y + (map_pos.y + GlobalConstants.GRID_ALIGNMENT_OFFSET.y) * _placement_manager.grid_size,
				_tile_map.global_position.z + map_pos.z * _placement_manager.grid_size
			)
		GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
			return Vector3(
				_tile_map.global_position.x + map_pos.x * _placement_manager.grid_size,
				_tile_map.global_position.y + (map_pos.y + GlobalConstants.GRID_ALIGNMENT_OFFSET.y) * _placement_manager.grid_size,
				_tile_map.global_position.z + (map_pos.z + GlobalConstants.GRID_ALIGNMENT_OFFSET.z) * _placement_manager.grid_size
			)
		_:
			return GlobalUtil.grid_to_world(map_pos, _placement_manager.grid_size) + _tile_map.global_position


# --- Single-Tile Placement, Erase, and Query ---

## Place one tile from user-facing map coordinates.
##
## Use this for procedural builders that already work in tile steps. Gameplay
## code usually wants place_tile_at_world() or place_area().
func place_tile_at_map(map_pos: Vector3, uv_rect: Rect2, orientation: int = 0,
		tile_info: Dictionary = {}) -> bool:
	if _is_base_orientation(orientation):
		return place_tile(_logical_map_to_storage(map_pos, orientation), uv_rect, orientation, tile_info)
	return place_tile(map_pos, uv_rect, orientation, tile_info)


## Place one tile from a world-space point.
##
## This backs TileMapLayer3D.place_tile_runtime() and accepts the same "point
## near the intended surface" input as gameplay scripts.
func place_tile_at_world(world_pos: Vector3, uv_rect: Rect2, orientation: int = 0,
		tile_info: Dictionary = {}) -> bool:
	return place_tile(_world_to_storage_grid(world_pos), uv_rect, orientation, tile_info)


## Erase one tile from a world-space point and exact orientation.
##
## Use find_tile_at_world(world_pos, ANY_ORIENTATION) first if the orientation is
## unknown.
func erase_tile_at_world(world_pos: Vector3, orientation: int = 0) -> bool:
	return erase_tile(_world_to_storage_grid(world_pos), orientation)


## Return raw tile data at a world-space point for one exact orientation.
##
## This is a direct lookup. It does not search other orientations. Use
## find_tile_at_world() when a user/game script wants "whatever tile is there".
func get_tile_at_world_pos(world_pos: Vector3, orientation: int = 0) -> Dictionary:
	return get_tile_at_grid_pos(_world_to_storage_grid(world_pos), orientation)


## Return the internal tile key for a world-space point and exact orientation.
##
## Most user scripts should not need keys directly. This exists for highlight
## integration, debugging, and advanced cache/index code.
func get_tile_key_at_world(world_pos: Vector3, orientation: int) -> int:
	var map_pos: Vector3 = world_to_map(world_pos, orientation)
	if _is_base_orientation(orientation):
		return _tile_key_for_logical_map(map_pos, orientation)
	return GlobalUtil.make_tile_key(snap_grid_pos(_world_to_storage_grid(world_pos), orientation), orientation)


## Find tile data at a world-space point.
##
## Pass an exact orientation for a specific lookup, or ANY_ORIENTATION (-1) to
## search the six base orientations. Returned data is enriched with tile_key,
## map_position, and world_position.
func find_tile_at_world(world_pos: Vector3, orientation: int = ANY_ORIENTATION) -> Dictionary:
	for candidate_orientation: int in _find_orientations(orientation):
		var map_pos: Vector3 = world_to_map(world_pos, candidate_orientation)
		var data: Dictionary = _tile_data_for_logical_map(map_pos, candidate_orientation)
		if not data.is_empty():
			return data
	return {}


## Internal single-tile placement in storage-grid coordinates.
##
## This is the lowest-level runtime placement method. Public wrappers generally
## call place_tile_at_world(), place_tile_at_map(), or place_area() so callers do
## not need to know storage-grid offsets.
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
## Returns true if placement succeeded. Returns false (with push_error) if input
## is invalid: orientation out of range, or a vertex-edited tile already lives at
## that key (vertex tiles must be erased first via [method erase_tile]).
##
## Note: defaults for omitted [param tile_info] keys are runtime constants, NOT
## the user's TileMapLayerSettings — the procedural API does not carry editor mode state.
func place_tile(grid_pos: Vector3, uv_rect: Rect2, orientation: int = 0,
		tile_info: Dictionary = {}) -> bool:
	if orientation < 0 or orientation >= GlobalUtil.TileOrientation.size():
		push_error("TileMapRuntimeAPI.place_tile: invalid orientation %d (valid: 0-%d)" \
			% [orientation, GlobalUtil.TileOrientation.size() - 1])
		return false

	var pos: Vector3 = snap_grid_pos(grid_pos, orientation)
	var tile_key: int = GlobalUtil.make_tile_key(pos, orientation)

	# A vertex-edited tile at this key would silently coexist with the new
	# columnar tile — both would render. Refuse rather than corrupt.
	if _tile_map.has_vertex_corners(tile_key):
		push_error("TileMapRuntimeAPI.place_tile: vertex tile already at %s — erase it first" % pos)
		return false

	var mesh_rotation: int = tile_info.get("mesh_rotation", 0)
	_placement_manager._do_place_tile(tile_key, pos, uv_rect, orientation, mesh_rotation, tile_info)
	return true


## Internal single-tile erase in storage-grid coordinates.
##
## Handles both columnar and vertex-edited tiles. Use erase_tile_at_world() or
## erase_area() from user-facing API paths.
func erase_tile(grid_pos: Vector3, orientation: int = 0) -> bool:
	var pos: Vector3 = snap_grid_pos(grid_pos, orientation)
	var tile_key: int = GlobalUtil.make_tile_key(pos, orientation)

	# Vertex-edited tiles are NOT in _saved_tiles_lookup (has_tile() returns false).
	# They live in _vertex_tile_corners and are rendered as standalone MeshInstance3D.
	if _tile_map.has_vertex_corners(tile_key):
		_tile_map.destroy_vertex_mesh_instance(tile_key)
		_tile_map.erase_vertex_corners(tile_key)
		return true

	if not _tile_map.has_tile(tile_key):
		return false
	_placement_manager._do_erase_tile(tile_key)
	return true


## Internal exact lookup in storage-grid coordinates.
##
## Returns raw TileMapLayer3D tile data for one orientation, or {} if missing.
## Use find_tile_at_world() when orientation is unknown or enriched output helps.
func get_tile_at_grid_pos(grid_pos: Vector3, orientation: int = 0) -> Dictionary:
	var pos: Vector3 = snap_grid_pos(grid_pos, orientation)
	var tile_key: int = GlobalUtil.make_tile_key(pos, orientation)
	var index: int = _tile_map.get_tile_index(tile_key)
	if index < 0:
		return {}
	return _tile_map.get_tile_data_at(index)


## Raycast from the world and return the first tile hit as a Dictionary of its data.
## Returns an empty Dictionary if no tile was hit.
func get_first_tile_from_raycast(ray_origin: Vector3, ray_dir: Vector3) -> Dictionary:
	return SmartSelectManager.pick_tile_at(ray_origin, ray_dir, _tile_map)


# --- Rectangular Area Operations ---

## Place an oriented rectangular area from a world-space anchor.
##
## This is the main high-level runtime building primitive. size is measured along
## the face axes:
## - FLOOR/CEILING: X/Z
## - WALL_NORTH/WALL_SOUTH: X/Y
## - WALL_EAST/WALL_WEST: Z/Y
##
## options:
## - "anchor": "origin" (default) or "center"
## - "batch": true (default)
## - "overwrite": true (default)
## - "tile_info": Dictionary passed to place_tile()
func place_area(anchor_world: Vector3, orientation: int, size: Vector2i,
		uv_rect: Rect2, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = _new_result()
	if not _validate_area_args(result, "place_area", orientation, size):
		return result

	var anchor_map: Vector3 = _area_anchor_map(anchor_world, orientation, size, options)
	var tile_info: Dictionary = options.get("tile_info", {})
	var should_batch: bool = options.get("batch", true)
	var overwrite: bool = options.get("overwrite", true)

	result["anchor_grid"] = anchor_map
	if should_batch:
		begin_batch()

	for map_pos: Vector3 in _area_map_positions(anchor_map, orientation, size):
		var storage_pos: Vector3 = _logical_map_to_storage(map_pos, orientation)
		var tile_key: int = GlobalUtil.make_tile_key(storage_pos, orientation)
		if not overwrite and (_tile_map.has_tile(tile_key) or _tile_map.has_vertex_corners(tile_key)):
			result["skipped"] += 1
			continue
		if place_tile(storage_pos, uv_rect, orientation, tile_info):
			result["placed"] += 1
			result["tile_keys"].append(tile_key)
			var data: Dictionary = _tile_data_for_logical_map(map_pos, orientation)
			if not data.is_empty():
				result["tiles"].append(data)
		else:
			result["skipped"] += 1

	if should_batch:
		end_batch()
	return result


## Erase an oriented rectangular area from a world-space anchor.
##
## Uses the same orientation, size, and anchor semantics as place_area().
func erase_area(anchor_world: Vector3, orientation: int, size: Vector2i,
		options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = _new_result()
	if not _validate_area_args(result, "erase_area", orientation, size):
		return result

	var anchor_map: Vector3 = _area_anchor_map(anchor_world, orientation, size, options)
	var should_batch: bool = options.get("batch", true)

	result["anchor_grid"] = anchor_map
	if should_batch:
		begin_batch()

	for map_pos: Vector3 in _area_map_positions(anchor_map, orientation, size):
		var tile_key: int = _tile_key_for_logical_map(map_pos, orientation)
		if erase_tile(_logical_map_to_storage(map_pos, orientation), orientation):
			result["erased"] += 1
			result["tile_keys"].append(tile_key)
		else:
			result["skipped"] += 1

	if should_batch:
		end_batch()
	return result


## Return tile keys for an oriented rectangular area.
##
## Used by highlight wrappers and debugging. It does not check whether tiles
## currently exist at those keys.
func get_area_tile_keys(anchor_world: Vector3, orientation: int, size: Vector2i,
		options: Dictionary = {}) -> Array[int]:
	var keys: Array[int] = []
	if not _is_base_orientation(orientation) or size.x <= 0 or size.y <= 0:
		return keys

	var anchor_map: Vector3 = _area_anchor_map(anchor_world, orientation, size, options)
	for map_pos: Vector3 in _area_map_positions(anchor_map, orientation, size):
		keys.append(_tile_key_for_logical_map(map_pos, orientation))
	return keys


## Return runtime settings and optional per-orientation diagnostics for a point.
##
## Intended for debug UI/prints, not gameplay decisions.
func get_runtime_debug_info(world_pos: Variant = null) -> Dictionary:
	var info: Dictionary = {
		"grid_size": _tile_map.settings.grid_size,
		"grid_snap_size": _tile_map.settings.grid_snap_size,
		"global_position": _tile_map.global_position,
		"tile_count": _tile_map.get_tile_count(),
		"vertex_tile_count": _tile_map.get_vertex_tile_corners().size(),
	}
	if world_pos is Vector3:
		var per_orientation: Dictionary = {}
		for orientation: int in BASE_ORIENTATIONS:
			var map_pos: Vector3 = world_to_map(world_pos, orientation)
			per_orientation[orientation] = {
				"map_position": map_pos,
				"world_position": map_to_world(map_pos, orientation),
				"tile_key": _tile_key_for_logical_map(map_pos, orientation),
				"has_tile": not _tile_data_for_logical_map(map_pos, orientation).is_empty(),
			}
		info["world_pos"] = world_pos
		info["orientations"] = per_orientation
	return info






## Defer GPU MultiMesh sync for bulk operations.
## Call before placing many tiles, then [method end_batch] when done.
## Supports nesting — each begin must have a matching end.
func begin_batch() -> void:
	_placement_manager.begin_batch_update()


## Flush pending GPU updates after a [method begin_batch] / [method end_batch] block.
func end_batch() -> void:
	_placement_manager.end_batch_update()
