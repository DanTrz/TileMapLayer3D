class_name SculptManager
extends RefCounted

var quad_cell: int = GlobalConstants.SculptCellType.SQUARE
var tris_NE: int = GlobalConstants.SculptCellType.TRI_NE
var tris_NW: int = GlobalConstants.SculptCellType.TRI_NW
var tris_SE: int = GlobalConstants.SculptCellType.TRI_SE
var tris_SW: int = GlobalConstants.SculptCellType.TRI_SW

enum SculptState {
	IDLE,           ## No interaction
	DRAWING,        ## LMB held, sweeping area — NO height change yet
	PATTERN_READY,  ## LMB released, pattern visible, waiting for height click
	SETTING_HEIGHT  ## Clicked on pattern, dragging to raise/lower
}

## Current active TileMapLayer3D node
var _active_tilema3d_node: TileMapLayer3D = null  # TileMapLayer3D

## Emitted when Stage 2 completes with a meaningful height delta.
## Plugin connects this to place tiles from the committed pattern.
signal volume_committed(cells: Dictionary, base_y: float, raise_amount: float, grid_size: float, no_base_floor: bool, no_base_ceiling: bool)

var state: SculptState = SculptState.IDLE

## When true, the bottom floor tiles are skipped — volume is open-ended at the base.
## Useful when sculpting on an existing floor to avoid overlapping tiles.
var no_base_floor: bool = true

## When true, the top ceiling tiles are skipped — volume is open-ended at the top.
var no_base_ceiling: bool = false

# --- Brush position state ---

## World-space center of the brush (snapped to grid), updated each mouse move.
var brush_world_pos: Vector3 = Vector3.ZERO

## Total extra cells outward from center in each direction.
## e.g. radius = 1 = 3x3, 2 = 5x5, 3 = 7x7.
var brush_size: int = GlobalConstants.SCULPT_BRUSH_SIZE_DEFAULT

## Brush shape type (e.g. diamond, square)
var brush_type: GlobalConstants.SculptBrushType = GlobalConstants.SculptBrushType.DIAMOND

## Pre-computed shape template for the current brush_size.
## Key   = Vector2i(dx, dz) offset from brush center
## dx = horizontal offset (columns) from brush center (negative = left, positive = right)
## dz = vertical offset (rows) from brush center (negative = up/north, positive = down/south)
var _brush_template: Dictionary[Vector2i, int] = {}


## Grid cell size in world units. Read from TileMapLayerSettings.grid_size.
var grid_size: float = 1.0

## Grid snap resolution. 1.0 = full grid, 0.5 = half grid.
## Read from TileMapLayerSettings.grid_snap_size.
var grid_snap_size: float = GlobalConstants.DEFAULT_GRID_SNAP_SIZE

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
## Value = GlobalConstants.SculptCellType int (0=SQUARE, 1-4=TRIANGLE direction)
## Persists through PATTERN_READY. Cleared only on Stage 2 completion or reset.
var drag_pattern: Dictionary[Vector2i, int] = {}

## True when cursor is hovering over a cell that exists in drag_pattern.
## Used in PATTERN_READY to show a "clickable" hint to the user.
var is_hovering_pattern: bool = false


func _init() -> void:
	rebuild_brush_shape_template()

## Called by plugin when _edit() is invoked
func set_active_node(node: TileMapLayer3D) -> void:
	_active_tilema3d_node = node


## Called every mouse move to update the brush world position.
## orientation comes from placement_manager.calculate_cursor_plane_placement()
## Returns early and deactivates brush if surface is not FLOOR.
func update_brush_position(grid_pos: Vector3, p_grid_size: float, orientation: int, p_grid_snap_size: float = 1.0) -> void:
	## MVP: only sculpt on FLOOR. Any other orientation hides the brush.
	if orientation != GlobalConstants.SCULPT_FLOOR_ORIENTATION:
		is_active = false
		return

	brush_world_pos = grid_pos
	grid_size = p_grid_size
	grid_snap_size = p_grid_snap_size
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
## Stage 1: begins accumulating cells. if hovering pattern, begins Stage 2 height drag.
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
## Stage 1: cells accumulate via update_brush_position
## Stage 2: update the raise/lower delta from screen Y movement.
func on_mouse_move(screen_y: float) -> void:
	if state == SculptState.SETTING_HEIGHT:
		## Screen Y increases downward → drag UP = start_y - current_y > 0 = RAISE
		drag_delta_y = drag_start_screen_y - screen_y


## Called when LMB is released.
## Stage 1 end: commit the drawn pattern and wait for Stage 2 click.
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
			print("Height drag ended with delta ", drag_delta_y, " pixels → raise amount ", get_raise_amount(), " world units.")
			var raise: float = get_raise_amount()
			# if abs(raise) >= 0.000:
				
			# Commit the sculpt volume with the current pattern and height delta.
			# This is what trigger the actual tile changes in the TileMapLayer3D.
			volume_committed.emit(drag_pattern.duplicate(), drag_anchor_world_pos.y, raise, grid_size, no_base_floor, no_base_ceiling)
			state = SculptState.IDLE
			drag_pattern.clear()
			drag_delta_y = 0.0
			is_hovering_pattern = false

## Returns the world-unit raise/lower amount from the current height drag.
## Snapped to grid_size * grid_snap_size increments so terrain always aligns with the grid.
func get_raise_amount() -> float:
	var raw: float = drag_delta_y * GlobalConstants.SCULPT_DRAG_SENSITIVITY
	var snap_step: float = grid_size * grid_snap_size
	return snappedf(raw, snap_step)



## Called on RMB press at any time — cancels everything and returns to IDLE.
func on_cancel() -> void:
	state = SculptState.IDLE
	drag_pattern.clear()
	drag_delta_y = 0.0
	is_hovering_pattern = false


## Resets all state. Called when sculpt mode is disabled or node deselected.
func reset() -> void:
	state = SculptState.IDLE
	is_active = false
	is_hovering_pattern = false
	drag_delta_y = 0.0
	brush_world_pos = Vector3.ZERO
	drag_anchor_world_pos = Vector3.ZERO
	drag_pattern.clear()


## Adds all cells currently under the brush to drag_pattern.
## Reads cell type directly from _brush_template so SQUARE/TRIANGLE is encoded in the data.
## Called each mouse move during Stage 1 so the pattern grows as you sweep.
func _accumulate_brush_cells() -> void:
	var grid: Vector3 = GlobalUtil.world_to_grid(brush_world_pos, grid_size)
	var cx: int = roundi(grid.x)
	var cz: int = roundi(grid.z)
	for offset: Vector2i in _brush_template:
		var cell: Vector2i = Vector2i(cx + offset.x, cz + offset.y)
		var new_type: int = _brush_template[offset]
		if not drag_pattern.has(cell):
			drag_pattern[cell] = new_type
		else:
			drag_pattern[cell] = _merge_cell_type(drag_pattern[cell], new_type)


## Merges two cell types, upgrading toward SQUARE when possible.
## SQUARE always wins. Complementary triangle pairs (NE+SW, NW+SE) merge to SQUARE.
func _merge_cell_type(existing: int, incoming: int) -> int:
	if existing == GlobalConstants.SculptCellType.SQUARE:
		return existing
	if incoming == GlobalConstants.SculptCellType.SQUARE:
		return incoming
	## Both are triangles — check if complementary
	var sum: int = existing + incoming
	## NE(1)+SW(4)=5, NW(2)+SE(3)=5 — complementary pairs both sum to 5
	if sum == GlobalConstants.SculptCellType.TRI_NE + GlobalConstants.SculptCellType.TRI_SW:
		return GlobalConstants.SculptCellType.SQUARE
	return existing


## Rebuilds _brush_template for the current brush_size
func rebuild_brush_shape_template() -> void:
	_brush_template.clear()

	if _active_tilema3d_node:
		brush_type = _active_tilema3d_node.settings.sculpt_brush_type
		brush_size = _active_tilema3d_node.settings.sculpt_brush_size

	match brush_type:
		GlobalConstants.SculptBrushType.DIAMOND:
			_shape_diamond()
		GlobalConstants.SculptBrushType.SQUARE:
			_shape_square()
		_:
			_shape_diamond()
		
	print("Rebuilt brush template for type ", brush_type, " size ", brush_size, " with ", _brush_template.size(), " cells.")

func _shape_square() -> void:
	for dz in range(-brush_size, brush_size + 1):
		for dx in range(-brush_size, brush_size + 1):
			_brush_template[Vector2i(dx, dz)] = GlobalConstants.SculptCellType.SQUARE


## DIAMOND shape — flat lookup table per radius.
## No loops, no math. Just a direct map of (dx, dz) → cell type.
func _shape_diamond() -> void:
	match brush_size:
		1:
			_shape_diamond_r1()
		2:
			_shape_diamond_r2()
		3:
			_shape_diamond_r3()
		_:
			_shape_diamond_r2()


## R=1: 3x3 diamond — 1 square center + 4 edge triangles
##       [ SE ]
##  [NE] [  S ] [SW]
##       [ NW ]
func _shape_diamond_r1() -> void:
	## Row dz=-1
	_brush_template[Vector2i( -1, -1)] = tris_SE
	_brush_template[Vector2i( 0, -1)] = quad_cell
	_brush_template[Vector2i( 1, -1)] = tris_SW

	## Row dz=0
	_brush_template[Vector2i( -1, 0)] = quad_cell
	_brush_template[Vector2i( 0, 0)] = quad_cell
	_brush_template[Vector2i( 1, 0)] = quad_cell

	## Row dz=1
	_brush_template[Vector2i( -1, 1)] = tris_NE
	_brush_template[Vector2i( 0, 1)] = quad_cell
	_brush_template[Vector2i( 1, 1)] = tris_NW




## R=2: 5x5 diamond — 5 square interior + 8 edge triangles
##            [SE]  [SW]
##       [SE] [ S]  [ S] [SW]
##  [NE] [ S] [ S]  [ S] [NW]
##       [NE] [ S]  [ S] [NW]
##            [NE]  [NW]
func _shape_diamond_r2() -> void:
	## Row dz=-2
	_brush_template[Vector2i(-1, -2)] = tris_SE
	_brush_template[Vector2i(0, -2)] = quad_cell
	_brush_template[Vector2i(1, -2)] = tris_SW

	## Row dz=-1
	_brush_template[Vector2i(-2, -1)] = tris_SE
	_brush_template[Vector2i(-1, -1)] = quad_cell
	_brush_template[Vector2i( 0, -1)] = quad_cell
	_brush_template[Vector2i( 1, -1)] = quad_cell
	_brush_template[Vector2i( 2, -1)] = tris_SW
	## Row dz=0
	_brush_template[Vector2i(-2,  0)] = quad_cell
	_brush_template[Vector2i(-1,  0)] = quad_cell
	_brush_template[Vector2i( 0,  0)] = quad_cell
	_brush_template[Vector2i( 1,  0)] = quad_cell
	_brush_template[Vector2i( 2,  0)] = quad_cell
	## Row dz=1
	_brush_template[Vector2i(-2,  1)] = tris_NE
	_brush_template[Vector2i(-1,  1)] = quad_cell
	_brush_template[Vector2i( 0,  1)] = quad_cell
	_brush_template[Vector2i( 1,  1)] = quad_cell
	_brush_template[Vector2i( 2,  1)] = tris_NW
	## Row dz=2
	_brush_template[Vector2i( -1,  2)] = tris_NE
	_brush_template[Vector2i( 0,  2)] = quad_cell
	_brush_template[Vector2i( 1,  2)] = tris_NW



## R=3: 7x7 diamond
func _shape_diamond_r3() -> void:
	## Row dz=-3
	_brush_template[Vector2i(-1, -3)] = tris_SE
	_brush_template[Vector2i( 0, -3)] = quad_cell
	_brush_template[Vector2i( 1, -3)] = tris_SW
	## Row dz=-2
	_brush_template[Vector2i(-2, -2)] = tris_SE
	_brush_template[Vector2i(-1, -2)] = quad_cell
	_brush_template[Vector2i( 0, -2)] = quad_cell
	_brush_template[Vector2i( 1, -2)] = quad_cell
	_brush_template[Vector2i( 2, -2)] = tris_SW
	## Row dz=-1
	_brush_template[Vector2i(-3, -1)] = tris_SE
	_brush_template[Vector2i(-2, -1)] = quad_cell
	_brush_template[Vector2i(-1, -1)] = quad_cell
	_brush_template[Vector2i( 0, -1)] = quad_cell
	_brush_template[Vector2i( 1, -1)] = quad_cell
	_brush_template[Vector2i( 2, -1)] = quad_cell
	_brush_template[Vector2i( 3, -1)] = tris_SW
	
	## Row dz=0
	_brush_template[Vector2i(-3,  0)] = quad_cell
	_brush_template[Vector2i(-2,  0)] = quad_cell
	_brush_template[Vector2i(-1,  0)] = quad_cell
	_brush_template[Vector2i( 0,  0)] = quad_cell
	_brush_template[Vector2i( 1,  0)] = quad_cell
	_brush_template[Vector2i( 2,  0)] = quad_cell
	_brush_template[Vector2i( 3,  0)] = quad_cell

	## Row dz=1
	_brush_template[Vector2i(-3, 1)] = tris_NE
	_brush_template[Vector2i(-2, 1)] = quad_cell
	_brush_template[Vector2i(-1, 1)] = quad_cell
	_brush_template[Vector2i( 0, 1)] = quad_cell
	_brush_template[Vector2i( 1, 1)] = quad_cell
	_brush_template[Vector2i( 2, 1)] = quad_cell
	_brush_template[Vector2i( 3, 1)] = tris_NW
	## Row dz=2
	_brush_template[Vector2i(-2, 2)] = tris_NE
	_brush_template[Vector2i(-1, 2)] = quad_cell
	_brush_template[Vector2i( 0, 2)] = quad_cell
	_brush_template[Vector2i( 1, 2)] = quad_cell
	_brush_template[Vector2i( 2, 2)] = tris_NW
	## Row dz=3
	_brush_template[Vector2i(-1, 3)] = tris_NE
	_brush_template[Vector2i( 0, 3)] = quad_cell
	_brush_template[Vector2i( 1, 3)] = tris_NW


### BACKUP DO NOT DELETE
# func _cell_in_brush(dx: int, dz: int) -> bool:
# 	## Circle:
# 	return dx * dx + dz * dz <= brush_size * brush_size  
#     ## Diamond: 
# 	# return abs(dx) + abs(dz) <= brush_size
# 	## Square:  
# 	# return true