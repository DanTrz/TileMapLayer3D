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

var _active_tilema3d_node: TileMapLayer3D = null
var placement_manager: TilePlacementManager = null

signal sculpt_tiles_created(tile_list: Array[Dictionary])
signal sculpt_erase_tiles_requested(cells: Dictionary, min_y: float, max_y: float)

var state: SculptState = SculptState.IDLE

var draw_base_floor: bool = false
var draw_base_ceiling: bool = true
var flip_floor_faces: bool = false
var flip_ceiling_faces: bool = false
var flip_wall_faces: bool = false

var use_arch_corners: bool = false  # unused — see ArchCornerPlacer (disabled)

## Skip positions that already have a tile
var non_destructive: bool = true
## Replace boundary triangle floor/ceiling tiles when the new volume shape differs
var replace_boundary_triangles: bool = true

var brush_grid_pos: Vector3 = Vector3.ZERO
var brush_size: int = GlobalConstants.SCULPT_BRUSH_SIZE_DEFAULT
var brush_type: GlobalConstants.SculptBrushType = GlobalConstants.SculptBrushType.DIAMOND
## Key = Vector2i(dx, dz) offset from center, value = SculptCellType
var _brush_template: Dictionary[Vector2i, int] = {}

var grid_size: float = 1.0
var grid_snap_size: float = GlobalConstants.DEFAULT_GRID_SNAP_SIZE
var is_active: bool = false

const DEBUG_ARCH_WIDE_TURNS: bool = true

var drag_anchor_grid_pos: Vector3 = Vector3.ZERO
var drag_start_screen_y: float = 0.0
var drag_delta_y: float = 0.0  # > 0 = raise, < 0 = lower

## Vector2i(cell_x, cell_z) → SculptCellType, accumulated during the draw stroke
var drag_pattern: Dictionary[Vector2i, int] = {}
var is_hovering_pattern: bool = false


func _init() -> void:
	rebuild_brush_shape_template()

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


func update_brush_position(grid_pos: Vector3, p_grid_size: float, orientation: int, p_grid_snap_size: float = 1.0) -> void:
	if orientation != GlobalConstants.SCULPT_FLOOR_ORIENTATION:
		is_active = false
		return

	brush_grid_pos = grid_pos
	grid_size = p_grid_size
	grid_snap_size = p_grid_snap_size
	is_active = true

	if state == SculptState.DRAWING:
		_accumulate_brush_cells()

	if state == SculptState.PATTERN_READY:
		var cell: Vector2i = Vector2i(roundi(grid_pos.x), roundi(grid_pos.z))
		is_hovering_pattern = drag_pattern.has(cell)


func on_mouse_press(screen_y: float) -> void:
	match state:
		SculptState.IDLE, SculptState.DRAWING:
			state = SculptState.DRAWING
			drag_pattern.clear()
			drag_delta_y = 0.0
			_accumulate_brush_cells()

		SculptState.PATTERN_READY:
			if is_hovering_pattern:
				state = SculptState.SETTING_HEIGHT
				drag_start_screen_y = screen_y
				drag_anchor_grid_pos = brush_grid_pos
				drag_delta_y = 0.0

func on_mouse_move(screen_y: float) -> void:
	if state == SculptState.SETTING_HEIGHT:
		drag_delta_y = drag_start_screen_y - screen_y  # positive = raised


func on_mouse_release() -> void:
	match state:
		SculptState.DRAWING:
			if drag_pattern.is_empty():
				state = SculptState.IDLE
			else:
				state = SculptState.PATTERN_READY
				is_hovering_pattern = false

		SculptState.SETTING_HEIGHT:
			var raise: float = get_raise_amount()
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


func _build_tile_list(cells: Dictionary, base_y: float, raise_amount: float, gs: float) -> void:
	var tile_list: Array[Dictionary] = _create_sculpt_volume_tile_list(cells, base_y, raise_amount, gs)
	if not tile_list.is_empty():
		#Emit it
		sculpt_tiles_created.emit(tile_list)


func _create_sculpt_volume_tile_list(cells: Dictionary, base_y: float, raise_amount: float, gs: float) -> Array[Dictionary]:
	if not _active_tilema3d_node or not placement_manager:
		return []

	sync_from_settings()

	var uv_rect: Rect2 = placement_manager.current_tile_uv
	var height_in_grid: float = raise_amount / gs
	var abs_height_cells: int = absi(roundi(height_in_grid))

	var bottom_floor_y: float = minf(base_y, base_y + height_in_grid)
	var top_floor_y: float = maxf(base_y, base_y + height_in_grid)
	# Walls sit at integer Y midpoints between floors (bottom_floor_y + 0.5 + i)
	var wall_base_y: float = bottom_floor_y + 0.5

	var tile_list: Array[Dictionary] = []
	var depth: float = _active_tilema3d_node.settings.current_depth_scale if _active_tilema3d_node.settings else 0.1

	# Ceiling — skip ARCH_CAP cells (no arch caps in non-arch mode)
	if draw_base_ceiling:
		for cell: Vector2i in cells:
			var cell_type: int = cells[cell]
			if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
				continue
			var mapping: Vector2i = GlobalConstants.SCULPT_CELL_TO_TILE[cell_type]
			_sculpt_add_tile(tile_list, Vector3(float(cell.x), top_floor_y, float(cell.y)),
				0, mapping.x, mapping.y, uv_rect, depth, flip_ceiling_faces)

	# Floor
	if draw_base_floor:
		for cell: Vector2i in cells:
			var cell_type: int = cells[cell]
			if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
				continue
			var mapping: Vector2i = GlobalConstants.SCULPT_CELL_TO_TILE[cell_type]
			_sculpt_add_tile(tile_list, Vector3(float(cell.x), bottom_floor_y, float(cell.y)),
				0, mapping.x, mapping.y, uv_rect, depth, flip_floor_faces)

	# Flat walls — emit only on open edges (no neighbor covering that side)
	var wall_faces: Array = [
		[0, 1, GlobalConstants.SCULPT_WALL_SOUTH],
		[0, -1, GlobalConstants.SCULPT_WALL_NORTH],
		[1, 0, GlobalConstants.SCULPT_WALL_EAST],
		[-1, 0, GlobalConstants.SCULPT_WALL_WEST],
	]

	for cell: Vector2i in cells:
		var cell_type: int = cells[cell]
		if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
			continue
		var leg_dirs: Array = GlobalConstants.SCULPT_TRI_LEGS[cell_type]

		for wf: Array in wall_faces:
			var ndx: int = wf[0]
			var ndz: int = wf[1]

			# Triangles only expose walls on their leg sides
			var is_leg: bool = false
			for leg: Array in leg_dirs:
				if leg[0] == ndx and leg[1] == ndz:
					is_leg = true
					break
			if not is_leg:
				continue

			var neighbor_key: Vector2i = Vector2i(cell.x + ndx, cell.y + ndz)
			if cells.has(neighbor_key):
				var neighbor_type: int = cells[neighbor_key]
				if neighbor_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
					continue  # arch caps count as full coverage
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

			var wall_data: Vector3 = wf[2]
			var wall_ori: int = int(wall_data.z)
			for i: int in range(abs_height_cells):
				var wy: float = wall_base_y + float(i)
				var wpos: Vector3 = Vector3(float(cell.x) + wall_data.x, wy, float(cell.y) + wall_data.y)
				_sculpt_add_tile(tile_list, wpos, wall_ori,
					GlobalConstants.MeshMode.FLAT_SQUARE, 0, uv_rect, depth, flip_wall_faces)

	# Tilted walls — 45° bevels at triangle hypotenuses
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

	# Ceiling — SQUARE → FLAT_SQUARE, ARCH_CAP → FLAT_ARCH_CORNER_CAP
	if draw_base_ceiling:
		for cell: Vector2i in cells:
			var cell_type: int = cells[cell]
			var mapping: Vector2i = GlobalConstants.SCULPT_CELL_TO_TILE[cell_type]
			_sculpt_add_tile(tile_list, Vector3(float(cell.x), top_floor_y, float(cell.y)),
				0, mapping.x, mapping.y, uv_rect, depth, flip_ceiling_faces)

	# Floor — SQUARE cells only (no floor tile under arch corners)
	if draw_base_floor:
		for cell: Vector2i in cells:
			var cell_type: int = cells[cell]
			if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
				continue
			var mapping: Vector2i = GlobalConstants.SCULPT_CELL_TO_TILE[cell_type]
			_sculpt_add_tile(tile_list, Vector3(float(cell.x), bottom_floor_y, float(cell.y)),
				0, mapping.x, mapping.y, uv_rect, depth, flip_floor_faces)

	# Flat walls — SQUARE cells only; ARCH_CAP neighbors count as full coverage
	var wall_faces: Array = [
		[0, 1, GlobalConstants.SCULPT_WALL_SOUTH],
		[0, -1, GlobalConstants.SCULPT_WALL_NORTH],
		[1, 0, GlobalConstants.SCULPT_WALL_EAST],
		[-1, 0, GlobalConstants.SCULPT_WALL_WEST],
	]

	for cell: Vector2i in cells:
		var cell_type: int = cells[cell]
		if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
			continue  # arch corner walls handled below

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

	# Arch corner walls — 2 FLAT_ARCH_CORNER tiles per ARCH_CAP cell
	for cell: Vector2i in cells:
		var cell_type: int = cells[cell]
		if cell_type < GlobalConstants.SculptCellType.ARCH_CAP_NE:
			continue

		var dir: int = cell_type - GlobalConstants.SculptCellType.ARCH_CAP_NE  # 0=NE,1=NW,2=SE,3=SW
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

	# Post-process: replace staircase AC walls with S-curve, add CAPI caps
	_apply_arch_staircase_turn_post_process(
		tile_list, cells, top_floor_y, wall_base_y, abs_height_cells, uv_rect, depth)

	if not tile_list.is_empty():
		sculpt_tiles_created.emit(tile_list)

func _sculpt_add_tile(tile_list: Array[Dictionary], grid_pos: Vector3, orientation: int, mesh_mode: int, mesh_rotation: int, uv_rect: Rect2, depth_scale: float, p_flip: bool = false) -> void:
	# Flipping a triangle shifts it one quadrant CW — add 3 steps CCW to cancel
	var actual_rotation: int = mesh_rotation
	if p_flip and mesh_mode == GlobalConstants.MeshMode.FLAT_TRIANGULE:
		actual_rotation = (mesh_rotation + 3) % 4
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
	if non_destructive and _active_tilema3d_node and _active_tilema3d_node.has_tile(tile_key):
		# ARCHED_RECT exception: allow FLAT_SQUARE to overwrite FLAT_ARCH_CORNER_CAP / CAP_I tiles
		var _arch_cap_override: bool = false
		if brush_type == GlobalConstants.SculptBrushType.ARCHED_RECT \
				and mesh_mode == GlobalConstants.MeshMode.FLAT_SQUARE:
			var _idx: int = _active_tilema3d_node.get_tile_index(tile_key)
			if _idx >= 0:
				var _ex_mode: int = (_active_tilema3d_node._tile_flags[_idx] >> 7) & 0x7
				_arch_cap_override = (
					_ex_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP
					or _ex_mode == GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I
				)
		if not _arch_cap_override:
			if not replace_boundary_triangles:
				return
			# Allow replacing triangle floor/ceiling tiles with different shapes
			var index: int = _active_tilema3d_node.get_tile_index(tile_key)
			if index < 0:
				return
			var existing_flags: int = _active_tilema3d_node._tile_flags[index]
			var existing_ori: int = existing_flags & 0x1F
			var existing_mode: int = (existing_flags >> 22) & 0x3FF
			var existing_rotation: int = (existing_flags >> 5) & 0x3
			if existing_ori > 1:
				return
			if existing_mode != GlobalConstants.MeshMode.FLAT_TRIANGULE:
				return
			if mesh_mode == existing_mode and actual_rotation == existing_rotation:
				return
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


## Staircase post-process: AC walls → S-curve, adds CAP_I ceiling on adjacent squares
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

	var s_change_keys: Dictionary = {}   # wall tile_keys: AC → S
	var cap_removal_keys: Dictionary = {}  # ceiling CAP tile_keys to remove

	for run: Array in runs:
		var dir: int = run[0]["dir"]
		var step: Array = GlobalConstants.ARCH_STAIRCASE_STEP[dir]
		var sdx: int = int(step[0])
		var sdz: int = int(step[1])
		var same_sign: bool = sdx * sdz > 0

		var wall1_ori: int = int(GlobalConstants.ARCH_CONVEX_WALL1[dir][1])
		var wall2_ori: int = int(GlobalConstants.ARCH_CONVEX_WALL2[dir][1])

		for pair_idx: int in range(run.size() - 1):
			var cell_a: Vector2i = run[pair_idx]["cell"]
			var cell_b: Vector2i = run[pair_idx + 1]["cell"]
			var ax: float = float(cell_a.x)
			var az: float = float(cell_a.y)
			var bx: float = float(cell_b.x)
			var bz: float = float(cell_b.y)

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

			# NE/SW (opposite signs): gap = cellA.Wall2 + cellB.Wall1
			# NW/SE (same signs):     gap = cellA.Wall1 + cellB.Wall2
			var gap_pos_1: Vector3
			var gap_ori_1: int
			var gap_pos_2: Vector3
			var gap_ori_2: int
			if not same_sign:
				gap_pos_1 = a_w2; gap_ori_1 = wall2_ori
				gap_pos_2 = b_w1; gap_ori_2 = wall1_ori
			else:
				gap_pos_1 = a_w1; gap_ori_1 = wall1_ori
				gap_pos_2 = b_w2; gap_ori_2 = wall2_ori

			for yi: int in range(abs_height_cells):
				var wy: float = wall_base_y + float(yi)
				s_change_keys[GlobalUtil.make_tile_key(
					Vector3(gap_pos_1.x, wy, gap_pos_1.z), gap_ori_1)] = true
				s_change_keys[GlobalUtil.make_tile_key(
					Vector3(gap_pos_2.x, wy, gap_pos_2.z), gap_ori_2)] = true

		for entry: Dictionary in run:
			var cell: Vector2i = entry["cell"]
			cap_removal_keys[GlobalUtil.make_tile_key(
				Vector3(float(cell.x), top_floor_y, float(cell.y)), 0)] = true

	# Backwards pass: change AC→S in-place, remove old CAPs
	var i: int = tile_list.size() - 1
	while i >= 0:
		var tile: Dictionary = tile_list[i]
		var tk: int = tile["tile_key"]
		if cap_removal_keys.has(tk):
			tile_list.remove_at(i)
		elif s_change_keys.has(tk):
			tile["mode"] = GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S
		i -= 1

	# Re-add ceiling CAPs (one per cell) and CAPIi (one per consecutive pair)
	for run: Array in runs:
		var dir: int = run[0]["dir"]
		var cap_rot: int = int(GlobalConstants.ARCH_STAIRCASE_CAP_ROT[dir])
		var capi_rot: int = int(GlobalConstants.ARCH_STAIRCASE_CAPI_ROT[dir])
		var capi_off: Array = GlobalConstants.ARCH_STAIRCASE_CAPI_OFFSET[dir]

		if draw_base_ceiling:
			for entry: Dictionary in run:
				var cell: Vector2i = entry["cell"]
				_sculpt_add_tile(tile_list,
					Vector3(float(cell.x), top_floor_y, float(cell.y)), 0,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP, cap_rot,
					uv_rect, depth, false)

			# CAPI sits at the "knee" between each consecutive pair
			for pair_idx: int in range(run.size() - 1):
				var cell_a: Vector2i = run[pair_idx]["cell"]
				_sculpt_add_tile(tile_list,
					Vector3(float(cell_a.x) + float(capi_off[0]),
						top_floor_y,
						float(cell_a.y) + float(capi_off[1])), 0,
					GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I, capi_rot,
					uv_rect, depth, false)


## Returns runs of 2+ same-direction ARCH_CAP cells each stepped by ARCH_STAIRCASE_STEP
func _find_staircase_runs(cells: Dictionary) -> Array[Array]:
	var arch_caps: Dictionary = {}  # Vector2i → dir (0-3)
	for cell_pos: Vector2i in cells:
		var cell_type: int = cells[cell_pos]
		if cell_type >= GlobalConstants.SculptCellType.ARCH_CAP_NE:
			arch_caps[cell_pos] = cell_type - GlobalConstants.SculptCellType.ARCH_CAP_NE

	var visited: Dictionary = {}
	var runs: Array[Array] = []

	for cell: Vector2i in arch_caps:
		if visited.has(cell):
			continue
		var dir: int = arch_caps[cell]
		var step: Array = GlobalConstants.ARCH_STAIRCASE_STEP[dir]
		var sdx: int = int(step[0])
		var sdz: int = int(step[1])

		# Walk backwards to chain start
		var start: Vector2i = cell
		var prev: Vector2i = Vector2i(start.x - sdx, start.y - sdz)
		while arch_caps.has(prev) and arch_caps[prev] == dir and not visited.has(prev):
			start = prev
			prev = Vector2i(start.x - sdx, start.y - sdz)

		# Walk forwards to build the run
		var run: Array = []
		var current: Vector2i = start
		while arch_caps.has(current) and arch_caps[current] == dir and not visited.has(current):
			visited[current] = true
			run.append({"cell": current, "dir": dir})
			current = Vector2i(current.x + sdx, current.y + sdz)

		if run.size() >= 2:
			runs.append(run)

	return runs















func get_raise_amount() -> float:
	var raw: float = drag_delta_y * GlobalConstants.SCULPT_DRAG_SENSITIVITY
	var snap_step: float = grid_size * grid_snap_size
	return snappedf(raw, snap_step)



func on_cancel() -> void:
	state = SculptState.IDLE
	drag_pattern.clear()
	drag_delta_y = 0.0
	is_hovering_pattern = false


func reset() -> void:
	state = SculptState.IDLE
	is_active = false
	is_hovering_pattern = false
	drag_delta_y = 0.0
	brush_grid_pos = Vector3.ZERO
	drag_anchor_grid_pos = Vector3.ZERO
	drag_pattern.clear()


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


## SQUARE always wins; any two different triangles also promote to SQUARE
func _merge_cell_type(existing: int, incoming: int) -> int:
	if existing == GlobalConstants.SculptCellType.SQUARE or incoming == GlobalConstants.SculptCellType.SQUARE:
		return GlobalConstants.SculptCellType.SQUARE
	if existing == incoming:
		return existing
	return GlobalConstants.SculptCellType.SQUARE


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


## 3x3 rectangle with ARCH_CAP corners
func _shape_arched_rect() -> void:
	_brush_template[Vector2i(-1, -1)] = arch_cap_sw
	_brush_template[Vector2i( 0, -1)] = quad_cell
	_brush_template[Vector2i( 1, -1)] = arch_cap_se

	_brush_template[Vector2i(-1,  0)] = quad_cell
	_brush_template[Vector2i( 0,  0)] = quad_cell
	_brush_template[Vector2i( 1,  0)] = quad_cell

	_brush_template[Vector2i(-1,  1)] = arch_cap_nw
	_brush_template[Vector2i( 0,  1)] = quad_cell
	_brush_template[Vector2i( 1,  1)] = arch_cap_ne


## Flat lookup table per radius — no procedural math
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


##       [SE]
##  [NE] [ S] [SW]
##       [NW]
func _shape_diamond_r1() -> void:
	_brush_template[Vector2i(-1, -1)] = tris_SE
	_brush_template[Vector2i( 0, -1)] = quad_cell
	_brush_template[Vector2i( 1, -1)] = tris_SW

	_brush_template[Vector2i(-1,  0)] = quad_cell
	_brush_template[Vector2i( 0,  0)] = quad_cell
	_brush_template[Vector2i( 1,  0)] = quad_cell

	_brush_template[Vector2i(-1,  1)] = tris_NE
	_brush_template[Vector2i( 0,  1)] = quad_cell
	_brush_template[Vector2i( 1,  1)] = tris_NW




##            [SE] [SW]
##       [SE] [ S] [ S] [SW]
##  [NE] [ S] [ S] [ S] [NW]
##       [NE] [ S] [ S] [NW]
##            [NE] [NW]
func _shape_diamond_r2() -> void:
	_brush_template[Vector2i(-1, -2)] = tris_SE
	_brush_template[Vector2i( 0, -2)] = quad_cell
	_brush_template[Vector2i( 1, -2)] = tris_SW

	_brush_template[Vector2i(-2, -1)] = tris_SE
	_brush_template[Vector2i(-1, -1)] = quad_cell
	_brush_template[Vector2i( 0, -1)] = quad_cell
	_brush_template[Vector2i( 1, -1)] = quad_cell
	_brush_template[Vector2i( 2, -1)] = tris_SW

	_brush_template[Vector2i(-2,  0)] = quad_cell
	_brush_template[Vector2i(-1,  0)] = quad_cell
	_brush_template[Vector2i( 0,  0)] = quad_cell
	_brush_template[Vector2i( 1,  0)] = quad_cell
	_brush_template[Vector2i( 2,  0)] = quad_cell

	_brush_template[Vector2i(-2,  1)] = tris_NE
	_brush_template[Vector2i(-1,  1)] = quad_cell
	_brush_template[Vector2i( 0,  1)] = quad_cell
	_brush_template[Vector2i( 1,  1)] = quad_cell
	_brush_template[Vector2i( 2,  1)] = tris_NW

	_brush_template[Vector2i(-1,  2)] = tris_NE
	_brush_template[Vector2i( 0,  2)] = quad_cell
	_brush_template[Vector2i( 1,  2)] = tris_NW



## 7x7 diamond
func _shape_diamond_r3() -> void:
	_brush_template[Vector2i(-1, -3)] = tris_SE
	_brush_template[Vector2i( 0, -3)] = quad_cell
	_brush_template[Vector2i( 1, -3)] = tris_SW

	_brush_template[Vector2i(-2, -2)] = tris_SE
	_brush_template[Vector2i(-1, -2)] = quad_cell
	_brush_template[Vector2i( 0, -2)] = quad_cell
	_brush_template[Vector2i( 1, -2)] = quad_cell
	_brush_template[Vector2i( 2, -2)] = tris_SW

	_brush_template[Vector2i(-3, -1)] = tris_SE
	_brush_template[Vector2i(-2, -1)] = quad_cell
	_brush_template[Vector2i(-1, -1)] = quad_cell
	_brush_template[Vector2i( 0, -1)] = quad_cell
	_brush_template[Vector2i( 1, -1)] = quad_cell
	_brush_template[Vector2i( 2, -1)] = quad_cell
	_brush_template[Vector2i( 3, -1)] = tris_SW

	_brush_template[Vector2i(-3,  0)] = quad_cell
	_brush_template[Vector2i(-2,  0)] = quad_cell
	_brush_template[Vector2i(-1,  0)] = quad_cell
	_brush_template[Vector2i( 0,  0)] = quad_cell
	_brush_template[Vector2i( 1,  0)] = quad_cell
	_brush_template[Vector2i( 2,  0)] = quad_cell
	_brush_template[Vector2i( 3,  0)] = quad_cell

	_brush_template[Vector2i(-3,  1)] = tris_NE
	_brush_template[Vector2i(-2,  1)] = quad_cell
	_brush_template[Vector2i(-1,  1)] = quad_cell
	_brush_template[Vector2i( 0,  1)] = quad_cell
	_brush_template[Vector2i( 1,  1)] = quad_cell
	_brush_template[Vector2i( 2,  1)] = quad_cell
	_brush_template[Vector2i( 3,  1)] = tris_NW

	_brush_template[Vector2i(-2,  2)] = tris_NE
	_brush_template[Vector2i(-1,  2)] = quad_cell
	_brush_template[Vector2i( 0,  2)] = quad_cell
	_brush_template[Vector2i( 1,  2)] = quad_cell
	_brush_template[Vector2i( 2,  2)] = tris_NW

	_brush_template[Vector2i(-1,  3)] = tris_NE
	_brush_template[Vector2i( 0,  3)] = quad_cell
	_brush_template[Vector2i( 1,  3)] = tris_NW




### BACKUP DO NOT DELETE
# func _cell_in_brush(dx: int, dz: int) -> bool:
# 	## Circle:
# 	return dx * dx + dz * dz <= brush_size * brush_size
#     ## Diamond:
# 	# return abs(dx) + abs(dz) <= brush_size
# 	## Square:
# 	# return true
