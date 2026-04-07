class_name SculptManager
extends RefCounted

var quad_cell: int = GlobalConstants.SculptCellType.SQUARE
var tris_NE: int = GlobalConstants.SculptCellType.TRI_NE
var tris_NW: int = GlobalConstants.SculptCellType.TRI_NW
var tris_SE: int = GlobalConstants.SculptCellType.TRI_SE
var tris_SW: int = GlobalConstants.SculptCellType.TRI_SW
var arch_cap_ne: int = GlobalConstants.SculptCellType.ARCH_CAP_NE
var arch_cap_nw: int = GlobalConstants.SculptCellType.ARCH_CAP_NW
var arch_cap_se: int = GlobalConstants.SculptCellType.ARCH_CAP_SE
var arch_cap_sw: int = GlobalConstants.SculptCellType.ARCH_CAP_SW

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

signal sculpt_erase_tiles_requested(cells: Dictionary, min_y: float, max_y: float)

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

## When true, sharp 90-degree wall corners are replaced with arch tile recipes
var use_arch_corners: bool = false

## Handles arch corner detection and tile replacement
	## DO NOT USE ARCH CORNER PLACER> It's not WORKING and is causing more problems than it's solving. The current wall placement logic is good enough for now, and we can revisit arch corners later if we want to add them as a polish feature.
# var _arch_corner_placer: ArchCornerPlacer = ArchCornerPlacer.new()

## When true, sculpt skips positions that already have a tile (non-destructive)
var non_destructive: bool = false

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

const DEBUG_ARCH_WIDE_TURNS: bool = true

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
		use_arch_corners = _active_tilema3d_node.settings.sculpt_arch_corners


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
			
			match brush_type:
				GlobalConstants.SculptBrushType.ARCHED_RECT:
					_build_arch_tile_list(drag_pattern.duplicate(), drag_anchor_grid_pos.y, raise, grid_size)
				GlobalConstants.SculptBrushType.ERASE:
					_build_erase_volume_tile_list(drag_pattern.duplicate(), drag_anchor_grid_pos.y, raise, grid_size)
				_:
					_build_tile_list(drag_pattern.duplicate(), drag_anchor_grid_pos.y, raise, grid_size)

			#Reset state
			state = SculptState.IDLE
			drag_pattern.clear()
			drag_delta_y = 0.0
			is_hovering_pattern = false


## Build the tile list based on Brush drag_pattern 3D volume
func _build_tile_list(cells: Dictionary, base_y: float, raise_amount: float, gs: float) -> void:
	var tile_list: Array[Dictionary] = _create_sculpt_volume_tile_list(cells, base_y, raise_amount, gs)
	if not tile_list.is_empty():
		#Emit it
		sculpt_tiles_created.emit(tile_list)


func _create_sculpt_volume_tile_list(cells: Dictionary, base_y: float, raise_amount: float, gs: float) -> Array[Dictionary]:
	if not _active_tilema3d_node or not placement_manager:
		return []

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

	# 1. Handle TOP BASE CEILING — skip ARCH_CAP cells
	if draw_base_ceiling:
		for cell: Vector2i in cells:
			var cell_type: int = cells[cell]
			# Skip ARCH_CAP cells — handled separately in _build_arch_tile_list
			if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
				continue
			var mapping: Vector2i = GlobalConstants.SCULPT_CELL_TO_TILE[cell_type]
			_sculpt_add_tile(tile_list, Vector3(float(cell.x), top_floor_y, float(cell.y)),
				0, mapping.x, mapping.y, uv_rect, depth, flip_ceiling_faces)

	# 2. Handle BOTTOM FLOOR — skip ARCH_CAP cells
	if draw_base_floor:
		for cell: Vector2i in cells:
			var cell_type: int = cells[cell]
			# Skip ARCH_CAP cells — no floor at corners
			if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
				continue
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
		# Skip ARCH_CAP cells — handled separately in _build_arch_tile_list
		if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
			continue
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
				# ARCH_CAP neighbors are always full coverage (like SQUARE)
				if neighbor_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
					continue
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

	return tile_list

## Build tile list for ARCHED_RECT brush — hollow volumes with arch corner walls
func _build_arch_tile_list(cells: Dictionary, base_y: float, raise_amount: float, gs: float) -> void:
	if not _active_tilema3d_node or not placement_manager:
		return

	sync_from_settings()

	var uv_rect: Rect2 = placement_manager.current_tile_uv
	var height_in_grid: float = raise_amount / gs
	var abs_height_cells: int = absi(roundi(height_in_grid))

	var bottom_floor_y: float = minf(base_y, base_y + height_in_grid)
	var top_floor_y: float = maxf(base_y, base_y + height_in_grid)
	var wall_base_y: float = bottom_floor_y + 0.5

	var tile_list: Array[Dictionary] = []
	var depth: float = _active_tilema3d_node.settings.current_depth_scale if _active_tilema3d_node.settings else 0.1

	# 1. Ceiling — all cells (SQUARE uses FLAT_SQUARE, ARCH_CAP uses FLAT_ARCH_CORNER_CAP)
	if draw_base_ceiling:
		for cell: Vector2i in cells:
			var cell_type: int = cells[cell]
			var mapping: Vector2i = GlobalConstants.SCULPT_CELL_TO_TILE[cell_type]
			_sculpt_add_tile(tile_list, Vector3(float(cell.x), top_floor_y, float(cell.y)),
				0, mapping.x, mapping.y, uv_rect, depth, flip_ceiling_faces)

	# 2. Floor — SQUARE cells only (no floor under ARCH_CAP corners)
	if draw_base_floor:
		for cell: Vector2i in cells:
			var cell_type: int = cells[cell]
			if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
				continue
			var mapping: Vector2i = GlobalConstants.SCULPT_CELL_TO_TILE[cell_type]
			_sculpt_add_tile(tile_list, Vector3(float(cell.x), bottom_floor_y, float(cell.y)),
				0, mapping.x, mapping.y, uv_rect, depth, flip_floor_faces)

	# 3. Flat walls — SQUARE cells only, ARCH_CAP neighbors treated as full coverage
	var wall_faces: Array = [
		[0, 1, GlobalConstants.SCULPT_WALL_SOUTH],
		[0, -1, GlobalConstants.SCULPT_WALL_NORTH],
		[1, 0, GlobalConstants.SCULPT_WALL_EAST],
		[-1, 0, GlobalConstants.SCULPT_WALL_WEST],
	]

	for cell: Vector2i in cells:
		var cell_type: int = cells[cell]
		if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
			continue  # ARCH_CAP walls handled in step 4

		for wf: Array in wall_faces:
			var ndx: int = wf[0]
			var ndz: int = wf[1]

			# Skip if neighbor exists (SQUARE or ARCH_CAP both fully cover shared edges)
			var neighbor_key: Vector2i = Vector2i(cell.x + ndx, cell.y + ndz)
			if cells.has(neighbor_key):
				continue

			var wall_data: Vector3 = wf[2]
			var wall_ori: int = int(wall_data.z)
			for i: int in range(abs_height_cells):
				var wy: float = wall_base_y + float(i)
				var wpos: Vector3 = Vector3(float(cell.x) + wall_data.x, wy, float(cell.y) + wall_data.y)
				_sculpt_add_tile(tile_list, wpos, wall_ori,
					GlobalConstants.MeshMode.FLAT_SQUARE, 0, uv_rect, depth, flip_wall_faces)

	# 4. Arch corner walls — 2 FLAT_ARCH_CORNER walls per ARCH_CAP cell
	for cell: Vector2i in cells:
		var cell_type: int = cells[cell]
		if cell_type < GlobalConstants.SculptCellType.ARCH_CAP_NE:
			continue

		var dir: int = cell_type - GlobalConstants.SculptCellType.ARCH_CAP_NE  # 0=NE, 1=NW, 2=SE, 3=SW
		var wall1_recipe: Array = GlobalConstants.ARCH_CONVEX_WALL1[dir]
		var wall2_recipe: Array = GlobalConstants.ARCH_CONVEX_WALL2[dir]

		var x: float = float(cell.x)
		var z: float = float(cell.y)
		var w1_pos: Vector3
		var w2_pos: Vector3

		match dir:
			0:  # NE: south(+Z) and east(+X) walls
				w1_pos = Vector3(x, 0.0, z + 0.5)
				w2_pos = Vector3(x + 0.5, 0.0, z)
			1:  # NW: south(+Z) and west(-X) walls
				w1_pos = Vector3(x, 0.0, z + 0.5)
				w2_pos = Vector3(x - 0.5, 0.0, z)
			2:  # SE: north(-Z) and east(+X) walls
				w1_pos = Vector3(x, 0.0, z - 0.5)
				w2_pos = Vector3(x + 0.5, 0.0, z)
			3:  # SW: north(-Z) and west(-X) walls
				w1_pos = Vector3(x, 0.0, z - 0.5)
				w2_pos = Vector3(x - 0.5, 0.0, z)

		for i: int in range(abs_height_cells):
			var wy: float = wall_base_y + float(i)
			_sculpt_add_tile(tile_list, Vector3(w1_pos.x, wy, w1_pos.z),
				int(wall1_recipe[1]), int(wall1_recipe[0]), int(wall1_recipe[2]),
				uv_rect, depth, flip_wall_faces)
			_sculpt_add_tile(tile_list, Vector3(w2_pos.x, wy, w2_pos.z),
				int(wall2_recipe[1]), int(wall2_recipe[0]), int(wall2_recipe[2]),
				uv_rect, depth, flip_wall_faces)

	# 5a. Post-process staircase diagonals: replace AC walls with S-curve, add CAPI caps
	_apply_arch_staircase_turn_post_process(
		tile_list, cells, top_floor_y, wall_base_y, abs_height_cells, uv_rect, depth)

	# 5b. Post-process to replace any remaining 90-degree corners with arch-wide-turn recipes
	# _apply_arch_wide_turn_post_process(
	# 	tile_list, cells, top_floor_y, wall_base_y, abs_height_cells, uv_rect, depth)

	if not tile_list.is_empty():
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
		var existing_mode: int = (existing_flags >> 22) & 0x3FF
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

func _build_erase_volume_tile_list(cells: Dictionary, base_y: float, raise_amount: float, gs: float) -> void:
	if not _active_tilema3d_node or not placement_manager:
		return
	if cells.is_empty():
		return

	var height_in_grid: float = raise_amount / gs
	var min_y: float = minf(base_y, base_y + height_in_grid)
	var max_y: float = maxf(base_y, base_y + height_in_grid)
	sculpt_erase_tiles_requested.emit(cells.duplicate(), min_y, max_y)


func _apply_arch_wide_turn_post_process(
		tile_list: Array[Dictionary],
		_cells: Dictionary,
		top_floor_y: float,
		wall_base_y: float,
		abs_height_cells: int,
		uv_rect: Rect2,
		depth: float) -> void:
	if tile_list.is_empty() or abs_height_cells <= 0:
		return

	var candidates: Array[Dictionary] = _find_arch_wide_turn_candidates(tile_list, wall_base_y)
	if DEBUG_ARCH_WIDE_TURNS:
		print("SculptManager wide-turn pass: candidates=", candidates.size(), " walls=", abs_height_cells)
	if candidates.is_empty():
		return

	var removal_keys: Dictionary = {}
	for candidate: Dictionary in candidates:
		var dir: int = candidate["direction"]
		var corner_pos: Vector2 = candidate["corner_pos"]

		var offsets: Array = GlobalConstants.ARCH_CORNER_OFFSETS[dir]
		var wall1_recipe: Array = GlobalConstants.ARCH_CONCAVE_WALL1[dir]
		var wall2_recipe: Array = GlobalConstants.ARCH_CONCAVE_WALL2[dir]

		for i: int in range(abs_height_cells):
			var wy: float = wall_base_y + float(i)
			var wall1_pos: Vector3 = Vector3(corner_pos.x + offsets[0], wy, corner_pos.y + offsets[1])
			var wall2_pos: Vector3 = Vector3(corner_pos.x + offsets[2], wy, corner_pos.y + offsets[3])
			removal_keys[GlobalUtil.make_tile_key(wall1_pos, int(wall1_recipe[1]))] = true
			removal_keys[GlobalUtil.make_tile_key(wall2_pos, int(wall2_recipe[1]))] = true

	if DEBUG_ARCH_WIDE_TURNS:
		print("SculptManager wide-turn pass: removals=", removal_keys.size())
	if removal_keys.is_empty():
		return

	var i: int = tile_list.size() - 1
	while i >= 0:
		if removal_keys.has(tile_list[i]["tile_key"]):
			tile_list.remove_at(i)
		i -= 1

	for candidate: Dictionary in candidates:
		if DEBUG_ARCH_WIDE_TURNS:
			print("  applying wide-turn at ", candidate["corner_pos"], " dir=", candidate["direction"])
		_append_arch_wide_turn_tiles(
			tile_list, candidate, top_floor_y, wall_base_y, abs_height_cells, uv_rect, depth)


func _find_arch_wide_turn_candidates(tile_list: Array[Dictionary], wall_base_y: float) -> Array[Dictionary]:
	var flat_walls: Dictionary = {}
	var result: Array[Dictionary] = []
	var seen_caps: Dictionary = {}
	var patterns: Array = [
		[GlobalConstants.ArchTurnDir.NE, 3, 4, 0.5, -0.5],
		[GlobalConstants.ArchTurnDir.NW, 3, 5, -0.5, -0.5],
		[GlobalConstants.ArchTurnDir.SE, 2, 4, 0.5, 0.5],
		[GlobalConstants.ArchTurnDir.SW, 2, 5, -0.5, 0.5],
	]

	for tile: Dictionary in tile_list:
		var pos: Vector3 = tile["grid_pos"]
		var ori: int = tile["orientation"]
		var mode: int = tile["mode"]
		if mode != GlobalConstants.MeshMode.FLAT_SQUARE:
			continue
		if ori < 2 or ori > 5:
			continue
		if not is_equal_approx(pos.y, wall_base_y):
			continue
		flat_walls[_make_arch_wall_signature(pos.x, pos.z, ori)] = true

	for wall_sig: Vector3 in flat_walls.keys():
		for pattern: Array in patterns:
			var dir: int = pattern[0]
			var wall1_ori: int = pattern[1]
			var wall2_ori: int = pattern[2]
			var wall2_dx: float = pattern[3]
			var wall2_dz: float = pattern[4]

			if int(wall_sig.y) != wall1_ori:
				continue

			var wall2_sig: Vector3 = _make_arch_wall_signature(
				wall_sig.x + wall2_dx, wall_sig.z + wall2_dz, wall2_ori)
			if not flat_walls.has(wall2_sig):
				continue

			var cap_pos: Vector2i = Vector2i(int(roundi(wall_sig.x)), int(roundi(wall_sig.z + wall2_dz)))
			if seen_caps.has(cap_pos):
				continue
			seen_caps[cap_pos] = true

			var offsets: Array = GlobalConstants.ARCH_CORNER_OFFSETS[dir]
			result.append({
				"corner_pos": Vector2(float(cap_pos.x) - offsets[4], float(cap_pos.y) - offsets[5]),
				"direction": dir,
			})

	return result


func _append_arch_wide_turn_tiles(
		tile_list: Array[Dictionary],
		candidate: Dictionary,
		top_floor_y: float,
		wall_base_y: float,
		abs_height_cells: int,
		uv_rect: Rect2,
		depth: float) -> void:
	var dir: int = candidate["direction"]
	var corner_pos: Vector2 = candidate["corner_pos"]
	var offsets: Array = GlobalConstants.ARCH_CORNER_OFFSETS[dir]
	var wall1_recipe: Array = GlobalConstants.ARCH_CONCAVE_WALL1[dir]
	var wall2_recipe: Array = GlobalConstants.ARCH_CONCAVE_WALL2[dir]
	var cap_recipe: Array = GlobalConstants.ARCH_CONCAVE_CAP[dir]

	for i: int in range(abs_height_cells):
		var wy: float = wall_base_y + float(i)
		_sculpt_add_tile(
			tile_list,
			Vector3(corner_pos.x + offsets[0], wy, corner_pos.y + offsets[1]),
			int(wall1_recipe[1]),
			int(wall1_recipe[0]),
			int(wall1_recipe[2]),
			uv_rect,
			depth,
			flip_wall_faces)
		_sculpt_add_tile(
			tile_list,
			Vector3(corner_pos.x + offsets[2], wy, corner_pos.y + offsets[3]),
			int(wall2_recipe[1]),
			int(wall2_recipe[0]),
			int(wall2_recipe[2]),
			uv_rect,
			depth,
			flip_wall_faces)

	if draw_base_ceiling:
		_sculpt_add_tile(
			tile_list,
			Vector3(corner_pos.x + offsets[4], top_floor_y, corner_pos.y + offsets[5]),
			int(cap_recipe[1]),
			int(cap_recipe[0]),
			int(cap_recipe[2]),
			uv_rect,
			depth,
			false)


func _make_arch_wall_signature(x: float, z: float, orientation: int) -> Vector3:
	return Vector3(x, float(orientation), z)


## ---------------------------------------------------------------------------
## Staircase post-process: replaces FLAT_ARCH_CORNER walls with S-curve meshes
## and adds FLAT_ARCH_CORNER_CAP_I ceiling tiles on adjacent SQUARE cells.
## ---------------------------------------------------------------------------

func _apply_arch_staircase_turn_post_process(
		tile_list: Array[Dictionary],
		cells: Dictionary,
		top_floor_y: float,
		wall_base_y: float,
		abs_height_cells: int,
		uv_rect: Rect2,
		depth: float) -> void:
	if tile_list.is_empty() or abs_height_cells <= 0:
		return

	var runs: Array[Array] = _find_staircase_runs(cells)
	if runs.is_empty():
		return

	# Build sets of tile_keys: walls to change AC→S, and ceiling CAPs to remove
	var s_change_keys: Dictionary = {}
	var cap_removal_keys: Dictionary = {}

	for run: Array in runs:
		var dir: int = run[0]["dir"]
		var step: Array = GlobalConstants.ARCH_STAIRCASE_STEP[dir]
		var sdx: int = int(step[0])
		var sdz: int = int(step[1])
		var same_sign: bool = sdx * sdz > 0

		# Wall orientation lookups
		var wall1_ori: int = int(GlobalConstants.ARCH_CONVEX_WALL1[dir][1])
		var wall2_ori: int = int(GlobalConstants.ARCH_CONVEX_WALL2[dir][1])

		# For each consecutive pair, identify the 2 gap walls to change to S
		for pair_idx: int in range(run.size() - 1):
			var cell_a: Vector2i = run[pair_idx]["cell"]
			var cell_b: Vector2i = run[pair_idx + 1]["cell"]
			var ax: float = float(cell_a.x)
			var az: float = float(cell_a.y)
			var bx: float = float(cell_b.x)
			var bz: float = float(cell_b.y)

			# Compute wall positions for both cells (same logic as _build_arch_tile_list step 4)
			var a_w1: Vector3
			var a_w2: Vector3
			var b_w1: Vector3
			var b_w2: Vector3
			match dir:
				0:  # NE
					a_w1 = Vector3(ax, 0.0, az + 0.5); a_w2 = Vector3(ax + 0.5, 0.0, az)
					b_w1 = Vector3(bx, 0.0, bz + 0.5); b_w2 = Vector3(bx + 0.5, 0.0, bz)
				1:  # NW
					a_w1 = Vector3(ax, 0.0, az + 0.5); a_w2 = Vector3(ax - 0.5, 0.0, az)
					b_w1 = Vector3(bx, 0.0, bz + 0.5); b_w2 = Vector3(bx - 0.5, 0.0, bz)
				2:  # SE
					a_w1 = Vector3(ax, 0.0, az - 0.5); a_w2 = Vector3(ax + 0.5, 0.0, az)
					b_w1 = Vector3(bx, 0.0, bz - 0.5); b_w2 = Vector3(bx + 0.5, 0.0, bz)
				3:  # SW
					a_w1 = Vector3(ax, 0.0, az - 0.5); a_w2 = Vector3(ax - 0.5, 0.0, az)
					b_w1 = Vector3(bx, 0.0, bz - 0.5); b_w2 = Vector3(bx - 0.5, 0.0, bz)

			# Gap walls depend on step sign pattern:
			# opposite signs (NE, SW): cellA.Wall2 + cellB.Wall1
			# same signs (NW, SE): cellA.Wall1 + cellB.Wall2
			var gap_pos_1: Vector3
			var gap_ori_1: int
			var gap_pos_2: Vector3
			var gap_ori_2: int
			if not same_sign:  # NE, SW
				gap_pos_1 = a_w2; gap_ori_1 = wall2_ori
				gap_pos_2 = b_w1; gap_ori_2 = wall1_ori
			else:  # NW, SE
				gap_pos_1 = a_w1; gap_ori_1 = wall1_ori
				gap_pos_2 = b_w2; gap_ori_2 = wall2_ori

			for yi: int in range(abs_height_cells):
				var wy: float = wall_base_y + float(yi)
				s_change_keys[GlobalUtil.make_tile_key(
					Vector3(gap_pos_1.x, wy, gap_pos_1.z), gap_ori_1)] = true
				s_change_keys[GlobalUtil.make_tile_key(
					Vector3(gap_pos_2.x, wy, gap_pos_2.z), gap_ori_2)] = true

		# Ceiling CAPs to remove (one per cell in the run)
		for entry: Dictionary in run:
			var cell: Vector2i = entry["cell"]
			cap_removal_keys[GlobalUtil.make_tile_key(
				Vector3(float(cell.x), top_floor_y, float(cell.y)), 0)] = true

	# Single backwards pass: change AC→S in-place, remove old CAPs
	var i: int = tile_list.size() - 1
	while i >= 0:
		var tile: Dictionary = tile_list[i]
		var tk: int = tile["tile_key"]
		if cap_removal_keys.has(tk):
			tile_list.remove_at(i)
		elif s_change_keys.has(tk):
			tile["mode"] = GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S
		i -= 1

	# Append new ceiling tiles: CAP for every cell, CAPI only between consecutive pairs
	for run: Array in runs:
		var dir: int = run[0]["dir"]
		var cap_rot: int = int(GlobalConstants.ARCH_STAIRCASE_CAP_ROT[dir])
		var capi_rot: int = int(GlobalConstants.ARCH_STAIRCASE_CAPI_ROT[dir])
		var capi_off: Array = GlobalConstants.ARCH_STAIRCASE_CAPI_OFFSET[dir]

		if draw_base_ceiling:
			# Re-add CAP at every cell in the run (N caps)
			for entry: Dictionary in run:
				var cell: Vector2i = entry["cell"]
				_sculpt_add_tile(tile_list,
					Vector3(float(cell.x), top_floor_y, float(cell.y)), 0,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP, cap_rot,
					uv_rect, depth, false)

			# Add CAPI only between consecutive pairs (N-1 caps).
			# The CAPI sits at the "knee" cell between cellA and cellB.
			for pair_idx: int in range(run.size() - 1):
				var cell_a: Vector2i = run[pair_idx]["cell"]
				_sculpt_add_tile(tile_list,
					Vector3(float(cell_a.x) + float(capi_off[0]),
						top_floor_y,
						float(cell_a.y) + float(capi_off[1])), 0,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I, capi_rot,
					uv_rect, depth, false)


## Finds staircase runs: sequences of 2+ ARCH_CAP cells with the same direction,
## each consecutive pair separated by exactly one ARCH_STAIRCASE_STEP.
func _find_staircase_runs(cells: Dictionary) -> Array[Array]:
	# Collect ARCH_CAP cells and their directions
	var arch_caps: Dictionary = {}  # Vector2i → dir (0-3)
	for cell_pos: Vector2i in cells:
		var cell_type: int = cells[cell_pos]
		if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
			arch_caps[cell_pos] = cell_type - GlobalConstants.SculptCellType.ARCH_CAP_NE

	# Chain into runs of same-direction caps
	var visited: Dictionary = {}
	var runs: Array[Array] = []

	for cell: Vector2i in arch_caps:
		if visited.has(cell):
			continue
		var dir: int = arch_caps[cell]
		var step: Array = GlobalConstants.ARCH_STAIRCASE_STEP[dir]
		var sdx: int = int(step[0])
		var sdz: int = int(step[1])

		# Walk backwards to find chain start
		var start: Vector2i = cell
		var prev: Vector2i = Vector2i(start.x - sdx, start.y - sdz)
		while arch_caps.has(prev) and arch_caps[prev] == dir and not visited.has(prev):
			start = prev
			prev = Vector2i(start.x - sdx, start.y - sdz)

		# Walk forwards to build run
		var run: Array = []
		var current: Vector2i = start
		while arch_caps.has(current) and arch_caps[current] == dir and not visited.has(current):
			visited[current] = true
			run.append({"cell": current, "dir": dir})
			current = Vector2i(current.x + sdx, current.y + sdz)

		if run.size() >= 2:
			runs.append(run)

	return runs















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
		GlobalConstants.SculptBrushType.ARCHED_RECT:
			_shape_arched_rect()
		GlobalConstants.SculptBrushType.ERASE:
			_shape_square()
		_:
			_shape_diamond()
		

func _shape_square() -> void:
	for dz in range(-brush_size, brush_size + 1):
		for dx in range(-brush_size, brush_size + 1):
			_brush_template[Vector2i(dx, dz)] = GlobalConstants.SculptCellType.SQUARE


## ARCHED_RECT — rectangle with rounded corners using ARCH_CAP cell types.
## TODO: Add brush definitions here
func _shape_arched_rect() -> void:
	# Use to add Brush
	# _shape_diamond_r1() 
	_brush_template[Vector2i( -1, -1)] = arch_cap_sw
	_brush_template[Vector2i( 0, -1)] = quad_cell
	_brush_template[Vector2i( 1, -1)] = arch_cap_se

	_brush_template[Vector2i( -1, 0)] = quad_cell
	_brush_template[Vector2i( 0, 0)] = quad_cell
	_brush_template[Vector2i( 1, 0)] = quad_cell

	_brush_template[Vector2i( -1, 1)] = arch_cap_nw
	_brush_template[Vector2i( 0, 1)] = quad_cell
	_brush_template[Vector2i( 1, 1)] = arch_cap_ne


# 	var arch_cap_ne: int = GlobalConstants.SculptCellType.ARCH_CAP_NE
# var arch_cap_nw: int = GlobalConstants.SculptCellType.ARCH_CAP_NW
# var arch_cap_se: int = GlobalConstants.SculptCellType.ARCH_CAP_SE
# var arch_cap_sw: int = GlobalConstants.SculptCellType.ARCH_CAP_SW
	pass


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
