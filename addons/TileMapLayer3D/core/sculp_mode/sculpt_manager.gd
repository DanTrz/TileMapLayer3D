class_name SculptManager
extends RefCounted


enum SculptState {
	IDLE,           ## No interaction
	DRAWING,        ## LMB held, sweeping area — NO height change yet
	PATTERN_READY,  ## LMB released, pattern visible, waiting for height click
	SETTING_HEIGHT  ## Clicked on pattern, dragging to raise/lower
}

var state: SculptState = SculptState.IDLE

# --- Brush position state ---

## World-space center of the brush (snapped to grid), updated each mouse move.
var brush_world_pos: Vector3 = Vector3.ZERO

## Brush radius in grid cells. 1 = 3x3, 2 = 5x5, 3 = 7x7.
var brush_radius: int = GlobalConstants.SCULPT_BRUSH_RADIUS_DEFAULT

## Grid cell size in world units. Read from TileMapLayerSettings.grid_size.
var grid_size: float = 1.0

## True only when cursor is over a valid FLOOR tile position.
## Gizmo will not draw when this is false.
var is_active: bool = false

# --- Height drag state (Stage 2 only) ---

## World position frozen when Stage 2 begins (LMB clicked on pattern).
## Floor cells stay at this Y — they don't chase the mouse.
var drag_anchor_world_pos: Vector3 = Vector3.ZERO

## Screen Y position when Stage 2 LMB was first pressed.
var drag_start_screen_y: float = 0.0

## Current raise/lower delta in screen pixels.
##   > 0 = raise (dragged upward on screen)
##   < 0 = lower (dragged downward on screen)
var drag_delta_y: float = 0.0

## Accumulated set of all cells touched during Stage 1 (the draw stroke).
## Key   = Vector2i(cell_x, cell_z) in grid coordinates
## Value = float sample weight 1.0 (full strength for MVP, falloff later)
## Persists through PATTERN_READY. Cleared only on Stage 2 completion or reset.
var drag_pattern: Dictionary[Vector2i, float] = {}

## True when cursor is hovering over a cell that exists in drag_pattern.
## Used in PATTERN_READY to show a "clickable" hint to the user.
var is_hovering_pattern: bool = false


## Called every mouse move to update the brush world position.
## orientation comes from placement_manager.calculate_cursor_plane_placement()
## Returns early and deactivates brush if surface is not FLOOR.
func update_brush_position(grid_pos: Vector3, p_grid_size: float, orientation: int) -> void:
	## MVP: only sculpt on FLOOR. Any other orientation hides the brush.
	if orientation != GlobalConstants.SCULPT_FLOOR_ORIENTATION:
		is_active = false
		return

	brush_world_pos = grid_pos
	grid_size = p_grid_size
	is_active = true

	## Stage 1: accumulate cells while drawing.
	if state == SculptState.DRAWING:
		_accumulate_brush_cells()

	## PATTERN_READY: check if cursor is hovering a cell in the committed pattern.
	## This drives the "clickable" visual hint in the gizmo.
	if state == SculptState.PATTERN_READY:
		var grid: Vector3 = GlobalUtil.world_to_grid(grid_pos, grid_size)
		var cell: Vector2i = Vector2i(roundi(grid.x), roundi(grid.z))
		is_hovering_pattern = drag_pattern.has(cell)


## Called when LMB is pressed.
## Stage 1: begins accumulating cells.
## PATTERN_READY: if hovering pattern, begins Stage 2 height drag.
func on_mouse_press(screen_y: float) -> void:
	match state:
		SculptState.IDLE, SculptState.DRAWING:
			## Begin Stage 1 — fresh draw stroke.
			state = SculptState.DRAWING
			drag_pattern.clear()
			drag_delta_y = 0.0
			_accumulate_brush_cells()

		SculptState.PATTERN_READY:
			## Only enter Stage 2 if clicking inside the committed pattern.
			if is_hovering_pattern:
				state = SculptState.SETTING_HEIGHT
				drag_start_screen_y = screen_y
				drag_anchor_world_pos = brush_world_pos
				drag_delta_y = 0.0


## Called every mouse move while LMB is held.
## Stage 1: cells accumulate via update_brush_position — nothing extra here.
## Stage 2: update the raise/lower delta from screen Y movement.
func on_mouse_move(screen_y: float) -> void:
	if state == SculptState.SETTING_HEIGHT:
		## Screen Y increases downward → drag UP = start_y - current_y > 0 = RAISE
		drag_delta_y = drag_start_screen_y - screen_y


## Called when LMB is released.
## Stage 1 end: commit the drawn pattern and wait for Stage 2 click.
## Stage 2 end: apply height (future), clear and return to IDLE.
func on_mouse_release() -> void:
	match state:
		SculptState.DRAWING:
			if drag_pattern.is_empty():
				state = SculptState.IDLE
			else:
				## Pattern committed — wait for the user to click on it.
				state = SculptState.PATTERN_READY
				is_hovering_pattern = false

		SculptState.SETTING_HEIGHT:
			## TODO: Apply tile placement here (future phase).
			state = SculptState.IDLE
			drag_pattern.clear()
			drag_delta_y = 0.0
			is_hovering_pattern = false


## Returns the world-unit raise/lower amount from the current height drag.
## Use this for actual terrain modification and gizmo height preview.
func get_raise_amount() -> float:
	return drag_delta_y * GlobalConstants.SCULPT_DRAG_SENSITIVITY


## Resets all state. Called when sculpt mode is disabled or node deselected.
func reset() -> void:
	state = SculptState.IDLE
	is_active = false
	is_hovering_pattern = false
	drag_delta_y = 0.0
	brush_world_pos = Vector3.ZERO
	drag_anchor_world_pos = Vector3.ZERO
	drag_pattern.clear()


## Adds all cells currently under the brush circle to drag_pattern.
## Called each mouse move during Stage 1 so the pattern grows as you sweep.
## Uses circle mask: dx² + dz² ≤ radius² to match what the gizmo draws.
## Uses GlobalUtil.world_to_grid() so coordinates respect GRID_ALIGNMENT_OFFSET.
func _accumulate_brush_cells() -> void:
	var grid: Vector3 = GlobalUtil.world_to_grid(brush_world_pos, grid_size)
	var cx: int = roundi(grid.x)
	var cz: int = roundi(grid.z)

	for dz: int in range(-brush_radius, brush_radius + 1):
		for dx: int in range(-brush_radius, brush_radius + 1):
			## Circle mask — matches gizmo rendering
			if dx * dx + dz * dz > brush_radius * brush_radius:
				continue
			var cell: Vector2i = Vector2i(cx + dx, cz + dz)
			## Only add new cells — never overwrite existing entries
			if not drag_pattern.has(cell):
				drag_pattern[cell] = 1.0
