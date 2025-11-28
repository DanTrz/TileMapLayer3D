@tool
class_name AreaFillOperator
extends RefCounted
## Handles area fill/erase operations for TileMapLayer3D. 
## Encapsulates state and coordinates the selection workflow.
## Extracted from TileMapLayer3D_plugin.gd to reduce plugin bloat.
##
## Usage:
##   var operator = AreaFillOperator.new()
##   operator.setup(area_fill_selector, placement_manager, tile_map3d)
##   operator.start(camera, screen_pos, is_erase)
##   operator.update(camera, screen_pos)
##   operator.complete(undo_redo, fill_callback, erase_callback)
##   operator.cancel()

# =============================================================================
# SIGNALS
# =============================================================================

## Emitted when tiles should be highlighted during selection
signal highlight_requested(start_pos: Vector3, end_pos: Vector3, orientation: int, is_erase: bool)

## Emitted when highlights should be cleared
signal clear_highlights_requested()

## Emitted when selection extends beyond valid range
signal out_of_bounds_warning(position: Vector3, orientation: int)

# =============================================================================
# STATE VARIABLES (moved from Plugin)
# =============================================================================

var is_selecting: bool = false  ## True when Shift+Click+Drag active
var _start_pos: Vector3 = Vector3.ZERO  ## Starting grid position
var _start_orientation: int = 0  ## Orientation when selection started
var _is_erase_mode: bool = false  ## true = erase area, false = paint area

# =============================================================================
# DEPENDENCIES
# =============================================================================

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


## Updates the tile map reference (when user switches nodes)
func set_tile_map(tile_map3d: TileMapLayer3D) -> void:
	_tile_map3d = tile_map3d


## Checks if the operator is ready to use
func is_ready() -> bool:
	return _area_fill_selector != null and _placement_manager != null


## Returns true if currently in area selection mode
func is_area_selecting() -> bool:
	return is_selecting


## Returns true if current selection is in erase mode
func is_erase_mode() -> bool:
	return _is_erase_mode


# =============================================================================
# WORKFLOW METHODS
# =============================================================================

## Starts area selection at the given screen position.
## @param camera: The editor camera
## @param screen_pos: Mouse position on screen
## @param is_erase: True for erase mode, false for paint mode
func start(camera: Camera3D, screen_pos: Vector2, is_erase: bool) -> void:
	if not is_ready():
		return

	# Get starting position - use different raycasts for erase vs. paint
	var result: Dictionary

	if is_erase:
		# ERASE MODE: Use 3D world-space raycast (all planes)
		# Allows selection box to span floor, walls, ceiling simultaneously
		result = _placement_manager.calculate_3d_world_position(camera, screen_pos)
	else:
		# PAINT MODE: Use plane-locked raycast (single orientation)
		# Maintains existing behavior for area fill paint
		result = _placement_manager.calculate_cursor_plane_placement(camera, screen_pos)

	if result.is_empty():
		return

	is_selecting = true
	_is_erase_mode = is_erase
	_start_pos = result.grid_pos
	_start_orientation = result.get("orientation", 0)  # Safe fallback for 3D mode

	# Start visual selection box
	_area_fill_selector.start_selection(
		result.grid_pos,
		result.get("orientation", 0),
		result.get("active_plane", Vector3.UP)
	)


## Updates area selection during drag.
## @param camera: The editor camera
## @param screen_pos: Current mouse position on screen
func update(camera: Camera3D, screen_pos: Vector2) -> void:
	if not is_selecting or not is_ready():
		return

	# Get current mouse position - use different raycasts for erase vs. paint
	var result: Dictionary

	if _is_erase_mode:
		# ERASE MODE: Use 3D world-space raycast (all planes)
		result = _placement_manager.calculate_3d_world_position(camera, screen_pos)
	else:
		# PAINT MODE: Use plane-locked raycast (single orientation)
		result = _placement_manager.calculate_cursor_plane_placement(camera, screen_pos)

	if result.is_empty():
		return

	# Update selection box visual
	_area_fill_selector.update_selection(result.grid_pos)

	# Request highlight update (Plugin will handle this)
	highlight_requested.emit(_start_pos, result.grid_pos, _start_orientation, _is_erase_mode)


## Completes area fill/erase operation.
## @param undo_redo: The UndoRedo from EditorPlugin.get_undo_redo()
## @param fill_callback: Callable(min_pos, max_pos, orientation) -> int for fill operations
## @param erase_callback: Callable(min_pos, max_pos, orientation, undo_redo) -> int for erase operations
## @returns: Number of tiles affected, or -1 if operation fails/cancelled
func complete(
	undo_redo: EditorUndoRedoManager,
	fill_callback: Callable,
	erase_callback: Callable
) -> int:
	if not is_selecting or not is_ready():
		cancel()
		return -1

	# Get selection bounds
	var selection: Dictionary = _area_fill_selector.complete_selection()

	if selection.is_empty():
		# Selection was too small or invalid
		cancel()
		return -1

	var min_pos: Vector3 = selection.min_pos
	var max_pos: Vector3 = selection.max_pos
	var orientation: int = selection.orientation

	# POSITION VALIDATION: Only block FILL operations outside bounds
	# ERASE operations should ALWAYS be allowed regardless of position
	# (users need to be able to erase tiles from legacy data or older saves)
	if not _is_erase_mode and not _is_area_within_bounds(min_pos, max_pos):
		push_warning("TileMapLayer3D: Area fill blocked - selection extends beyond valid range (±%.1f)" % GlobalConstants.MAX_GRID_RANGE)
		out_of_bounds_warning.emit(_start_pos, orientation)
		cancel()
		return -1

	# Calculate tile count for confirmation
	var positions: Array[Vector3] = GlobalUtil.get_grid_positions_in_area(min_pos, max_pos, orientation)
	var tile_count: int = positions.size()

	# Check if we need user confirmation for large areas
	if tile_count > GlobalConstants.AREA_FILL_CONFIRM_THRESHOLD:
		# TODO: Add confirmation dialog in polish phase
		push_warning("TileMapLayer3D: Large area fill (%d tiles) - consider adding confirmation" % tile_count)

	# Perform fill or erase via callback
	var result: int = -1
	if _is_erase_mode:
		result = erase_callback.call(min_pos, max_pos, orientation, undo_redo)
	else:
		result = fill_callback.call(min_pos, max_pos, orientation)

	# Clear highlights
	clear_highlights_requested.emit()

	# Reset state
	is_selecting = false

	return result


## Cancels area selection without performing any operation.
func cancel() -> void:
	if _area_fill_selector:
		_area_fill_selector.cancel_selection()

	clear_highlights_requested.emit()
	is_selecting = false


## Resets all state (called when switching nodes)
func reset_state() -> void:
	is_selecting = false
	_start_pos = Vector3.ZERO
	_start_orientation = 0
	_is_erase_mode = false

	if _area_fill_selector:
		_area_fill_selector.cancel_selection()


# =============================================================================
# HELPER METHODS
# =============================================================================

## Checks if the area is within valid coordinate bounds
func _is_area_within_bounds(min_pos: Vector3, max_pos: Vector3) -> bool:
	# Inline check for performance (avoids 8 function calls)
	var max_range: float = GlobalConstants.MAX_GRID_RANGE
	return (
		abs(min_pos.x) <= max_range and abs(min_pos.y) <= max_range and abs(min_pos.z) <= max_range and
		abs(max_pos.x) <= max_range and abs(max_pos.y) <= max_range and abs(max_pos.z) <= max_range
	)


## Gets the start position of the current selection
func get_start_pos() -> Vector3:
	return _start_pos


## Gets the orientation of the current selection
func get_start_orientation() -> int:
	return _start_orientation
