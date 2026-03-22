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

## Current active TileMapLayer3D node and PlaceManager References
var _active_tilema3d_node: TileMapLayer3D = null  # TileMapLayer3D
var placement_manager: TilePlacementManager = null

## Emitted when we have a list of tiles resolved from the Brush Volume area
signal sculpt_tiles_created(tile_list: Array[Dictionary])

var state: SculptState = SculptState.IDLE

## When true, the bottom floor tiles are skipped 
var draw_base_floor: bool = false

## When true, the top ceiling tiles are skipped
var draw_base_ceiling: bool = true

## When true, floor tiles have their faces flipped
var flip_floor_faces: bool = false

## When true, ceiling tiles have their faces flipped
var flip_ceiling_faces: bool = false

## When true, wall tiles (flat + tilted) have their faces flipped
var flip_wall_faces: bool = false

## When true, sculpt skips positions that already have a tile (non-destructive)
var non_destructive: bool = true

## When true (and non_destructive is true), replaces existing boundary triangle
## floor/ceiling tiles if the new volume has a different shape at that cell.
var replace_boundary_triangles: bool = true

# --- Brush position state ---

## Grid-space center of the brush (snapped to grid), updated each mouse move.
## Receives grid coordinates from calculate_cursor_plane_placement().
var brush_grid_pos: Vector3 = Vector3.ZERO

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

## Grid-space position frozen when Stage 2 begins (LMB clicked on pattern).
## Floor cells stay at this Y — they don't chase the mouse.
var drag_anchor_grid_pos: Vector3 = Vector3.ZERO

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
func set_active_node(tilemap_node: TileMapLayer3D, placement_mgr: TilePlacementManager) -> void:
	_active_tilema3d_node = tilemap_node
	placement_manager = placement_mgr
	rebuild_brush_shape_template()
	sync_from_settings()

func sync_from_settings() -> void:
	if _active_tilema3d_node:
		draw_base_floor = _active_tilema3d_node.settings.sculpt_draw_bottom
		draw_base_ceiling = _active_tilema3d_node.settings.sculpt_draw_top
		flip_floor_faces = _active_tilema3d_node.settings.sculpt_flip_bottom
		flip_ceiling_faces = _active_tilema3d_node.settings.sculpt_flip_top
		flip_wall_faces = _active_tilema3d_node.settings.sculpt_flip_sides


## Called every mouse move to update the brush world position.
## orientation comes from placement_manager.calculate_cursor_plane_placement()
## Returns early and deactivates brush if surface is not FLOOR.
func update_brush_position(grid_pos: Vector3, p_grid_size: float, orientation: int, p_grid_snap_size: float = 1.0) -> void:
	## MVP: only sculpt on FLOOR. Any other orientation hides the brush.
	if orientation != GlobalConstants.SCULPT_FLOOR_ORIENTATION:
		is_active = false
		return

	brush_grid_pos = grid_pos
	grid_size = p_grid_size
	grid_snap_size = p_grid_snap_size
	is_active = true

	## Stage 1: accumulate cells while drawing.
	if state == SculptState.DRAWING:
		_accumulate_brush_cells()

	## PATTERN_READY: check if cursor is hovering a cell in the committed pattern.
	## This drives the "clickable" visual hint in the gizmo.
	if state == SculptState.PATTERN_READY:
		var cell: Vector2i = Vector2i(roundi(grid_pos.x), roundi(grid_pos.z))
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
				drag_anchor_grid_pos = brush_grid_pos
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
			var raise: float = get_raise_amount()
			# if abs(raise) >= 0.000:
			
			_build_tile_list(drag_pattern.duplicate(), drag_anchor_grid_pos.y, raise, grid_size)

			state = SculptState.IDLE
			drag_pattern.clear()
			drag_delta_y = 0.0
			is_hovering_pattern = false


## Build the tile list based on Brush drag_pattern 3D volume
func _build_tile_list(cells: Dictionary, base_y: float, raise_amount: float, gs: float) -> void:
	if not _active_tilema3d_node or not placement_manager:
		return

	# Get latest configruation settgings and update local vaariables first.
	sync_from_settings()

	var uv_rect: Rect2 = placement_manager.current_tile_uv
	var height_in_grid: float = raise_amount / gs
	var abs_height_cells: int = absi(roundi(height_in_grid))
	# if abs_height_cells == 0:
	# 	return

	var bottom_floor_y: float = minf(base_y, base_y + height_in_grid)
	var top_floor_y: float = maxf(base_y, base_y + height_in_grid)
	# Walls sit at integer Y midpoints between floors (bottom_floor_y + 0.5 + i)
	var wall_base_y: float = bottom_floor_y + 0.5

	var tile_list: Array[Dictionary] = []
	var depth: float = _active_tilema3d_node.settings.current_depth_scale if _active_tilema3d_node.settings else 0.1

	# 1. Handle TOP BASE CEILING 
	if draw_base_ceiling:
		for cell: Vector2i in cells:
			var cell_type: int = cells[cell]
			var mapping: Vector2i = GlobalConstants.SCULPT_CELL_TO_TILE[cell_type]
			_sculpt_add_tile(tile_list, Vector3(float(cell.x), top_floor_y, float(cell.y)),
				0, mapping.x, mapping.y, uv_rect, depth, flip_ceiling_faces)

	# 2. Handle BOTTOM FLOOR
	if draw_base_floor:
		for cell: Vector2i in cells:
			var cell_type: int = cells[cell]
			var mapping: Vector2i = GlobalConstants.SCULPT_CELL_TO_TILE[cell_type]
			_sculpt_add_tile(tile_list, Vector3(float(cell.x), bottom_floor_y, float(cell.y)),
				0, mapping.x, mapping.y, uv_rect, depth, flip_floor_faces)

	# 3. Handle FLAT WALLS
	var wall_faces: Array = [
		[0, 1, GlobalConstants.SCULPT_WALL_SOUTH],    ## +Z neighbor
		[0, -1, GlobalConstants.SCULPT_WALL_NORTH],   ## -Z neighbor
		[1, 0, GlobalConstants.SCULPT_WALL_EAST],     ## +X neighbor
		[-1, 0, GlobalConstants.SCULPT_WALL_WEST],    ## -X neighbor
	]

	for cell: Vector2i in cells:
		var cell_type: int = cells[cell]
		# Get which directions to check for this cell type (legs only for triangles)
		var leg_dirs: Array = GlobalConstants.SCULPT_TRI_LEGS[cell_type]

		for wf: Array in wall_faces:
			var ndx: int = wf[0]
			var ndz: int = wf[1]

			# Skip directions that aren't legs for triangle cells
			var is_leg: bool = false
			for leg: Array in leg_dirs:
				if leg[0] == ndx and leg[1] == ndz:
					is_leg = true
					break
			if not is_leg:
				continue

			# Skip if neighbor fully covers this edge
			var neighbor_key: Vector2i = Vector2i(cell.x + ndx, cell.y + ndz)
			if cells.has(neighbor_key):
				var neighbor_type: int = cells[neighbor_key]
				# Triangle neighbors only cover the edge on their leg sides.
				# If the reverse direction is NOT a leg (hypotenuse), edge is partially exposed.
				var neighbor_covers_edge: bool = true
				if neighbor_type != GlobalConstants.SculptCellType.SQUARE:
					var neighbor_legs: Array = GlobalConstants.SCULPT_TRI_LEGS[neighbor_type]
					var reverse_is_leg: bool = false
					for leg: Array in neighbor_legs:
						if leg[0] == -ndx and leg[1] == -ndz:
							reverse_is_leg = true
							break
					neighbor_covers_edge = reverse_is_leg
				if neighbor_covers_edge:
					continue

			# Place flat wall at each Y layer
			var wall_data: Vector3 = wf[2]
			var wall_ori: int = int(wall_data.z)
			for i: int in range(abs_height_cells):
				var wy: float = wall_base_y + float(i)
				var wpos: Vector3 = Vector3(float(cell.x) + wall_data.x, wy, float(cell.y) + wall_data.y)
				_sculpt_add_tile(tile_list, wpos, wall_ori,
					GlobalConstants.MeshMode.FLAT_SQUARE, 0, uv_rect, depth, flip_wall_faces)

	# 4. Handle TILTED WALLS (45° bevels at triangle hypotenuses)
	for cell: Vector2i in cells:
		var cell_type: int = cells[cell]
		if cell_type == GlobalConstants.SculptCellType.SQUARE:
			continue

		var tilt_data: Vector3 = GlobalConstants.SCULPT_TRI_TILT_WALL[cell_type]
		var tilt_ori: int = int(tilt_data.z)
		for i: int in range(abs_height_cells):
			var wy: float = wall_base_y + float(i)
			var tpos: Vector3 = Vector3(float(cell.x) + tilt_data.x, wy, float(cell.y) + tilt_data.y)
			_sculpt_add_tile(tile_list, tpos, tilt_ori,
				GlobalConstants.MeshMode.FLAT_SQUARE, 0, uv_rect, depth, flip_wall_faces)

	if not tile_list.is_empty():
		#Emit it
		sculpt_tiles_created.emit(tile_list)

## Helper: creates a tile dictionary and appends it to tile_list.
func _sculpt_add_tile(tile_list: Array[Dictionary], grid_pos: Vector3, orientation: int, mesh_mode: int, mesh_rotation: int, uv_rect: Rect2, depth_scale: float, p_flip: bool = false) -> void:
	# Compensate triangle rotation when flipping. The Z-flip in
	# build_tile_transform shifts the triangle one quadrant (CW).
	# Adding 3 steps (= one step CCW) cancels the shift.
	var actual_rotation: int = mesh_rotation
	if p_flip and mesh_mode == GlobalConstants.MeshMode.FLAT_TRIANGULE:
		actual_rotation = (mesh_rotation + 3) % 4
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
	if non_destructive and _active_tilema3d_node and _active_tilema3d_node.has_tile(tile_key):
		if not replace_boundary_triangles:
			return
		# Check if existing tile is a triangle floor/ceiling that should be replaced
		var index: int = _active_tilema3d_node.get_tile_index(tile_key)
		if index < 0:
			return
		var existing_flags: int = _active_tilema3d_node._tile_flags[index]
		var existing_ori: int = existing_flags & 0x1F
		var existing_mode: int = (existing_flags >> 7) & 0x3
		var existing_rotation: int = (existing_flags >> 5) & 0x3
		# Only replace triangle floor/ceiling tiles (not walls)
		if existing_ori > 1:
			return
		if existing_mode != GlobalConstants.MeshMode.FLAT_TRIANGULE:
			return
		# Only replace if the new tile is actually different
		if mesh_mode == existing_mode and actual_rotation == existing_rotation:
			return
		# Allow replacement — fall through to append
	tile_list.append({
		"tile_key": tile_key, "grid_pos": grid_pos, "uv_rect": uv_rect,
		"orientation": orientation, "rotation": actual_rotation,
		"flip": p_flip, "mode": mesh_mode,
		"terrain_id": GlobalConstants.AUTOTILE_NO_TERRAIN,
		"depth_scale": depth_scale, "texture_repeat_mode": 0
	})

















#------------------------------------------------------
#------------------------------------------------------
#------------------------------------------------------
#------------------------------------------------------


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
	brush_grid_pos = Vector3.ZERO
	drag_anchor_grid_pos = Vector3.ZERO
	drag_pattern.clear()


## Adds all cells currently under the brush to drag_pattern.
## Reads cell type directly from _brush_template so SQUARE/TRIANGLE is encoded in the data.
## Called each mouse move during Stage 1 so the pattern grows as you sweep.
func _accumulate_brush_cells() -> void:
	var cx: int = roundi(brush_grid_pos.x)
	var cz: int = roundi(brush_grid_pos.z)
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
	if existing == GlobalConstants.SculptCellType.SQUARE or incoming == GlobalConstants.SculptCellType.SQUARE:
		return GlobalConstants.SculptCellType.SQUARE
	if existing == incoming:
		return existing
	# Any two different triangles merge to SQUARE (complementary or not)
	return GlobalConstants.SculptCellType.SQUARE


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


