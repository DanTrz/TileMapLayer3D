@tool
class_name AreaFillOperator
extends RefCounted


signal highlight_requested(start_pos: Vector3, end_pos: Vector3, orientation: int, is_erase: bool)

signal clear_highlights_requested()

signal out_of_bounds_warning(position: Vector3, orientation: int)


var is_selecting: bool = false
var _start_pos: Vector3 = Vector3.ZERO
var _start_orientation: int = 0
var _is_erase_mode: bool = false


var _area_fill_selector: AreaFillSelector3D
var _placement_manager: TilePlacementManager
var _tile_map3d: TileMapLayer3D


## Sets up the operator with required dependencies.
## Must be called before using start/update/complete.
func setup(
	area_fill_selector: AreaFillSelector3D,
	placement_manager: TilePlacementManager,
	tile_map3d: TileMapLayer3D
) -> void:
	_area_fill_selector = area_fill_selector
	_placement_manager = placement_manager
	_tile_map3d = tile_map3d


func set_tile_map(tile_map3d: TileMapLayer3D) -> void:
	_tile_map3d = tile_map3d


func is_ready() -> bool:
	return _area_fill_selector != null and _placement_manager != null


func is_area_selecting() -> bool:
	return is_selecting


func is_erase_mode() -> bool:
	return _is_erase_mode



func start(camera: Camera3D, screen_pos: Vector2, is_erase: bool) -> void:
	if not is_ready():
		return

	var result: Dictionary

	if is_erase:
		result = _placement_manager.calculate_3d_world_position(camera, screen_pos)
	else:
		result = _placement_manager.calculate_cursor_plane_placement(camera, screen_pos)

	if result.is_empty():
		return

	is_selecting = true
	_is_erase_mode = is_erase
	_start_pos = result.grid_pos
	_start_orientation = result.get("orientation", 0)

	_area_fill_selector.start_selection(
		result.grid_pos,
		result.get("orientation", 0),
		result.get("active_plane", Vector3.UP)
	)


func update(camera: Camera3D, screen_pos: Vector2) -> void:
	if not is_selecting or not is_ready():
		return

	var result: Dictionary

	if _is_erase_mode:
		result = _placement_manager.calculate_3d_world_position(camera, screen_pos)
	else:
		result = _placement_manager.calculate_cursor_plane_placement(camera, screen_pos)

	if result.is_empty():
		return

	_area_fill_selector.update_selection(result.grid_pos)

	highlight_requested.emit(_start_pos, result.grid_pos, _start_orientation, _is_erase_mode)


func complete(
	undo_redo: Object,
	fill_callback: Callable,
	erase_callback: Callable
) -> int:
	if not is_selecting or not is_ready():
		cancel()
		return -1

	var selection: Dictionary = _area_fill_selector.complete_selection()

	if selection.is_empty():
		cancel()
		return -1

	var min_pos: Vector3 = selection.min_pos
	var max_pos: Vector3 = selection.max_pos
	var orientation: int = selection.orientation

	if not _is_erase_mode and not _is_area_within_bounds(min_pos, max_pos):
		push_warning("TileMapLayer3D: Area fill blocked - selection extends beyond valid range (±%.1f)" % GlobalConstants.MAX_GRID_RANGE)
		out_of_bounds_warning.emit(_start_pos, orientation)
		cancel()
		return -1

	var result: int = -1
	if _is_erase_mode:
		result = erase_callback.call(min_pos, max_pos, orientation, undo_redo)
	else:
		result = fill_callback.call(min_pos, max_pos, orientation)

	clear_highlights_requested.emit()

	is_selecting = false

	return result


func cancel() -> void:
	if _area_fill_selector:
		_area_fill_selector.cancel_selection()

	clear_highlights_requested.emit()
	is_selecting = false


func reset_state() -> void:
	is_selecting = false
	_start_pos = Vector3.ZERO
	_start_orientation = 0
	_is_erase_mode = false

	if _area_fill_selector:
		_area_fill_selector.cancel_selection()



func _is_area_within_bounds(min_pos: Vector3, max_pos: Vector3) -> bool:
	var max_range: float = GlobalConstants.MAX_GRID_RANGE
	return (
		abs(min_pos.x) <= max_range and abs(min_pos.y) <= max_range and abs(min_pos.z) <= max_range and
		abs(max_pos.x) <= max_range and abs(max_pos.y) <= max_range and abs(max_pos.z) <= max_range
	)


func get_start_pos() -> Vector3:
	return _start_pos


func get_start_orientation() -> int:
	return _start_orientation
