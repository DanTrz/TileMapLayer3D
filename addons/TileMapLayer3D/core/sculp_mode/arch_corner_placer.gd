class_name ArchCornerPlacer
extends RefCounted
## Detects 90-degree wall corners in a sculpt brush cell grid and replaces
## sharp FLAT_SQUARE walls with arch corner tile recipes.
##
## Two coexisting patterns:
##   Wide Turn (preferred) — AC/ACI pair + spacer walls, requires >= 2 cells between corners.
##   Staircase (fallback)  — consecutive AC pairs with 0 spacers, only convex, spacing == 1.
## Concave corners always use Wide Turn (never staircase).


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Post-processes a sculpt tile_list in-place: detects corners in `cells`,
## removes flat wall / ceiling tiles at those corners, and appends arch recipes.
func apply_arch_corners(
		tile_list: Array[Dictionary],
		cells: Dictionary,
		top_y: float,
		_bottom_y: float,
		wall_base_y: float,
		abs_height_cells: int,
		_gs: float,
		uv_rect: Rect2,
		depth: float,
		flip_walls: bool) -> void:

	# Phase 2 — detect corners
	var corners: Array[Dictionary] = _detect_corners(cells)
	if corners.is_empty():
		return

	# Phase 3 — measure spacing & assign pattern
	_assign_patterns(corners)

	# Build removal set (tile_keys of flat walls + ceiling tiles to remove)
	var removal_keys: Dictionary = {}
	for corner: Dictionary in corners:
		if corner["pattern"] == &"skip":
			continue
		_collect_removal_keys(corner, wall_base_y, abs_height_cells, top_y, removal_keys)

	# Phase 4a — filter tile_list (single backwards pass)
	if not removal_keys.is_empty():
		var i: int = tile_list.size() - 1
		while i >= 0:
			if removal_keys.has(tile_list[i]["tile_key"]):
				tile_list.remove_at(i)
			i -= 1

	# Phase 4b — add arch tiles
	for corner: Dictionary in corners:
		if corner["pattern"] == &"skip":
			continue
		_add_arch_tiles(tile_list, corner, wall_base_y, abs_height_cells, top_y, uv_rect, depth, flip_walls)


# ---------------------------------------------------------------------------
# Phase 2 — Corner Detection
# ---------------------------------------------------------------------------

## Walks every SQUARE cell in `cells`, examines its 4 grid corners (half-grid
## positions), and identifies convex (1 filled) and concave (3 filled) junctions.
## Returns an array of corner dictionaries.
func _detect_corners(cells: Dictionary) -> Array[Dictionary]:
	var visited: Dictionary = {}  # Vector2i (corner*2) → true
	var result: Array[Dictionary] = []

	for cell_pos: Vector2i in cells:
		var cell_type: int = cells[cell_pos]
		# MVP: only process SQUARE cells at corners
		if cell_type != GlobalConstants.SculptCellType.SQUARE:
			continue

		# Check all 4 corners of this cell
		for dx: int in [-1, 1]:
			for dz: int in [-1, 1]:
				# Use integer-doubled coords to avoid float hashing
				var corner_key: Vector2i = Vector2i(cell_pos.x * 2 + dx, cell_pos.y * 2 + dz)
				if visited.has(corner_key):
					continue
				visited[corner_key] = true

				# Half-grid corner position
				var corner_x: float = float(cell_pos.x) + float(dx) * 0.5
				var corner_z: float = float(cell_pos.y) + float(dz) * 0.5

				# Check which of the 4 adjacent cells exist as SQUARE
				var nw_pos: Vector2i = Vector2i(int(corner_x - 0.5), int(corner_z - 0.5))
				var ne_pos: Vector2i = Vector2i(int(corner_x + 0.5), int(corner_z - 0.5))
				var sw_pos: Vector2i = Vector2i(int(corner_x - 0.5), int(corner_z + 0.5))
				var se_pos: Vector2i = Vector2i(int(corner_x + 0.5), int(corner_z + 0.5))

				var nw_filled: bool = _is_square_cell(cells, nw_pos)
				var ne_filled: bool = _is_square_cell(cells, ne_pos)
				var sw_filled: bool = _is_square_cell(cells, sw_pos)
				var se_filled: bool = _is_square_cell(cells, se_pos)
				var count: int = int(nw_filled) + int(ne_filled) + int(sw_filled) + int(se_filled)

				if count == 1:
					# Convex corner (outside) — single filled cell
					var dir: int = _get_convex_direction(nw_filled, ne_filled, sw_filled, se_filled)
					var filled_cell: Vector2i = _get_single_filled_cell(nw_pos, ne_pos, sw_pos, se_pos,
							nw_filled, ne_filled, sw_filled, se_filled)
					result.append({
						"corner_pos": Vector2(corner_x, corner_z),
						"direction": dir,
						"is_convex": true,
						"filled_cell": filled_cell,
						"pattern": &"wide",  # default, may change in Phase 3
					})
				elif count == 3:
					# Concave corner (inside) — single empty cell
					var dir: int = _get_concave_direction(nw_filled, ne_filled, sw_filled, se_filled)
					result.append({
						"corner_pos": Vector2(corner_x, corner_z),
						"direction": dir,
						"is_convex": false,
						"filled_cell": Vector2i.ZERO,  # not used for concave
						"pattern": &"wide",  # concave always wide
					})

	return result


## Returns true if the cell at `pos` exists in `cells` and is SQUARE.
func _is_square_cell(cells: Dictionary, pos: Vector2i) -> bool:
	return cells.has(pos) and cells[pos] == GlobalConstants.SculptCellType.SQUARE


## Convex direction: the filled cell's code label maps to ArchTurnDir with E/W mirrored.
## Verified against decoded TileMapLayer3D_Combined reference scene data:
##   nw cell filled (offset -0.5, -0.5) → ArchTurnDir.NE
##   ne cell filled (offset +0.5, -0.5) → ArchTurnDir.NW
##   sw cell filled (offset -0.5, +0.5) → ArchTurnDir.SE
##   se cell filled (offset +0.5, +0.5) → ArchTurnDir.SW
func _get_convex_direction(nw: bool, ne: bool, sw: bool, se: bool) -> int:
	if nw:
		return GlobalConstants.ArchTurnDir.NE
	if ne:
		return GlobalConstants.ArchTurnDir.NW
	if sw:
		return GlobalConstants.ArchTurnDir.SE
	if se:
		return GlobalConstants.ArchTurnDir.SW
	return GlobalConstants.ArchTurnDir.NE  # fallback — should never happen


## Concave direction: the empty cell's code label maps to ArchTurnDir with same E/W mirror.
## Same convention as convex — verified against decoded reference scene data.
func _get_concave_direction(nw: bool, ne: bool, sw: bool, se: bool) -> int:
	if not nw:
		return GlobalConstants.ArchTurnDir.NE
	if not ne:
		return GlobalConstants.ArchTurnDir.NW
	if not sw:
		return GlobalConstants.ArchTurnDir.SE
	if not se:
		return GlobalConstants.ArchTurnDir.SW
	return GlobalConstants.ArchTurnDir.NE  # fallback


## Returns the Vector2i of the single filled cell (for convex corners).
func _get_single_filled_cell(
		nw: Vector2i, ne: Vector2i, sw: Vector2i, se: Vector2i,
		nw_f: bool, ne_f: bool, sw_f: bool, se_f: bool) -> Vector2i:
	if nw_f:
		return nw
	if ne_f:
		return ne
	if sw_f:
		return sw
	if se_f:
		return se
	return Vector2i.ZERO  # fallback


# ---------------------------------------------------------------------------
# Phase 3 — Pattern Assignment (spacing measurement)
# ---------------------------------------------------------------------------

## Measures distance between adjacent corners along walls and assigns patterns:
##   - Concave → always "wide"
##   - Convex with spacing >= 2 → "wide"
##   - Convex with spacing == 1 → "staircase"
##   - Convex with spacing == 0 (shouldn't happen) → "skip"
func _assign_patterns(corners: Array[Dictionary]) -> void:
	for i: int in range(corners.size()):
		var corner: Dictionary = corners[i]
		# Concave corners always use wide turn
		if not corner["is_convex"]:
			corner["pattern"] = &"wide"
			continue

		# Measure spacing to nearest corner along either wall
		var spacing: int = _measure_spacing(corners, i)
		if spacing >= 2:
			corner["pattern"] = &"wide"
		elif spacing == 1:
			corner["pattern"] = &"staircase"
		else:
			corner["pattern"] = &"wide"  # isolated corner, wide is fine


## Measures the minimum distance (in grid cells) from corner at `idx` to
## any other corner that shares a wall edge direction. Returns a large number
## if no adjacent corner is found (isolated corner → treat as wide turn).
func _measure_spacing(corners: Array[Dictionary], idx: int) -> int:
	var corner: Dictionary = corners[idx]
	var pos: Vector2 = corner["corner_pos"]
	var min_dist: int = 100  # large default = effectively infinite

	for j: int in range(corners.size()):
		if j == idx:
			continue
		var other: Dictionary = corners[j]
		var other_pos: Vector2 = other["corner_pos"]

		# Check if corners share a wall axis (same X or same Z within tolerance)
		var dx: float = absf(other_pos.x - pos.x)
		var dz: float = absf(other_pos.y - pos.y)

		# Same wall axis: one component is 0, the other is the spacing
		if dx < 0.01:
			var dist: int = int(roundf(dz))
			if dist > 0 and dist < min_dist:
				min_dist = dist
		elif dz < 0.01:
			var dist: int = int(roundf(dx))
			if dist > 0 and dist < min_dist:
				min_dist = dist

	return min_dist


# ---------------------------------------------------------------------------
# Phase 4a — Collect tile_keys to remove
# ---------------------------------------------------------------------------

## Adds to `removal_keys` the tile_keys of flat wall tiles and ceiling tiles
## that should be removed at this corner across all Y layers.
func _collect_removal_keys(
		corner: Dictionary,
		wall_base_y: float,
		abs_height_cells: int,
		top_y: float,
		removal_keys: Dictionary) -> void:

	var dir: int = corner["direction"]
	var is_convex: bool = corner["is_convex"]
	var corner_pos: Vector2 = corner["corner_pos"]

	if is_convex:
		_collect_convex_removal_keys(corner, dir, wall_base_y, abs_height_cells, top_y, removal_keys)
	else:
		_collect_concave_removal_keys(corner_pos, dir, wall_base_y, abs_height_cells, top_y, removal_keys)


## For convex corners: remove 2 flat walls (from the single filled cell) per Y layer,
## plus the ceiling tile at the filled cell position.
## Computes wall positions from the filled cell's exposed edges (same approach as
## _add_convex_arch_tiles) to ensure removal matches what the sculpt system placed.
func _collect_convex_removal_keys(
		corner: Dictionary,
		_dir: int,
		wall_base_y: float,
		abs_height_cells: int,
		top_y: float,
		removal_keys: Dictionary) -> void:

	var filled: Vector2i = corner["filled_cell"]
	var corner_pos: Vector2 = corner["corner_pos"]
	var fx: float = float(filled.x)
	var fz: float = float(filled.y)

	# Compute wall positions from filled cell + corner position (same logic as placement)
	var w1_x: float
	var w1_z: float
	var w1_ori: int
	var w2_x: float
	var w2_z: float
	var w2_ori: int

	if corner_pos.y < fz:
		w1_x = fx; w1_z = fz - 0.5; w1_ori = 3
	else:
		w1_x = fx; w1_z = fz + 0.5; w1_ori = 2

	if corner_pos.x > fx:
		w2_x = fx + 0.5; w2_z = fz; w2_ori = 5
	else:
		w2_x = fx - 0.5; w2_z = fz; w2_ori = 4

	# Remove flat wall tiles at each Y layer
	for i: int in range(abs_height_cells):
		var wy: float = wall_base_y + float(i)
		removal_keys[GlobalUtil.make_tile_key(Vector3(w1_x, wy, w1_z), w1_ori)] = true
		removal_keys[GlobalUtil.make_tile_key(Vector3(w2_x, wy, w2_z), w2_ori)] = true

	# Remove ceiling tile at filled cell (orientation 0 = FLOOR)
	removal_keys[GlobalUtil.make_tile_key(Vector3(fx, top_y, fz), 0)] = true


## For concave corners: remove 2 flat walls from 2 different filled cells per Y layer.
## The empty cell is identified from the corner position and direction.
func _collect_concave_removal_keys(
		corner_pos: Vector2,
		dir: int,
		wall_base_y: float,
		abs_height_cells: int,
		_top_y: float,
		removal_keys: Dictionary) -> void:

	# For concave corners, 3 cells are filled, 1 empty. The 2 walls to remove
	# come from the 2 filled cells that share an edge with the empty cell.
	# We derive the wall positions from the junction corner position + direction.
	var jx: float = corner_pos.x
	var jz: float = corner_pos.y

	# Determine which 2 filled cells contribute walls at this concave junction.
	# The walls to remove are the ones facing INTO the empty cell.
	var wall1_pos_offset: Vector2 = Vector2.ZERO
	var wall1_ori: int = 0
	var wall2_pos_offset: Vector2 = Vector2.ZERO
	var wall2_ori: int = 0

	match dir:
		GlobalConstants.ArchTurnDir.NE:
			# Empty cell is NE of junction. Walls facing north (from SE cell) and east (from NW cell).
			# SE cell = (jx, jz), its north wall: (jx, jz - 0.5) ori=3
			wall1_pos_offset = Vector2(jx, jz - 0.5)
			wall1_ori = 3
			# NW cell = (jx - 1, jz - 1), its east wall: (jx - 0.5, jz - 1) ori=5
			wall2_pos_offset = Vector2(jx - 0.5, jz - 1.0)
			wall2_ori = 5
		GlobalConstants.ArchTurnDir.NW:
			# Empty cell is NW. Walls from SW cell (north) and NE cell (west).
			# SW cell = (jx - 1, jz), its north wall: (jx - 1, jz - 0.5) ori=3
			wall1_pos_offset = Vector2(jx - 1.0, jz - 0.5)
			wall1_ori = 3
			# NE cell = (jx, jz - 1), its west wall: (jx - 0.5, jz - 1) ori=4
			wall2_pos_offset = Vector2(jx - 0.5, jz - 1.0)
			wall2_ori = 4
		GlobalConstants.ArchTurnDir.SE:
			# Empty cell is SE. Walls from NE cell (south) and SW cell (east).
			# NE cell = (jx, jz - 1), its south wall: (jx, jz - 0.5) ori=2
			wall1_pos_offset = Vector2(jx, jz - 0.5)
			wall1_ori = 2
			# SW cell = (jx - 1, jz), its east wall: (jx - 0.5, jz) ori=5
			wall2_pos_offset = Vector2(jx - 0.5, jz)
			wall2_ori = 5
		GlobalConstants.ArchTurnDir.SW:
			# Empty cell is SW. Walls from NW cell (south) and SE cell (west).
			# NW cell = (jx - 1, jz - 1), its south wall: (jx - 1, jz - 0.5) ori=2
			wall1_pos_offset = Vector2(jx - 1.0, jz - 0.5)
			wall1_ori = 2
			# SE cell = (jx, jz), its west wall: (jx - 0.5, jz) ori=4
			wall2_pos_offset = Vector2(jx - 0.5, jz)
			wall2_ori = 4

	for i: int in range(abs_height_cells):
		var wy: float = wall_base_y + float(i)
		var w1: Vector3 = Vector3(wall1_pos_offset.x, wy, wall1_pos_offset.y)
		removal_keys[GlobalUtil.make_tile_key(w1, wall1_ori)] = true
		var w2: Vector3 = Vector3(wall2_pos_offset.x, wy, wall2_pos_offset.y)
		removal_keys[GlobalUtil.make_tile_key(w2, wall2_ori)] = true


# ---------------------------------------------------------------------------
# Phase 4b — Add arch tiles
# ---------------------------------------------------------------------------

## Appends arch wall tiles (per Y layer) and cap ceiling tile for one corner.
## For convex corners: arch walls go at the SAME positions as the flat walls they
## replace (computed from filled cell's exposed edges). Cap goes at filled cell.
func _add_arch_tiles(
		tile_list: Array[Dictionary],
		corner: Dictionary,
		wall_base_y: float,
		abs_height_cells: int,
		top_y: float,
		uv_rect: Rect2,
		depth: float,
		flip_walls: bool) -> void:

	var dir: int = corner["direction"]
	var is_convex: bool = corner["is_convex"]

	if is_convex:
		_add_convex_arch_tiles(tile_list, corner, dir, wall_base_y, abs_height_cells, top_y, uv_rect, depth, flip_walls)
	else:
		_add_concave_arch_tiles(tile_list, corner, dir, wall_base_y, abs_height_cells, top_y, uv_rect, depth, flip_walls)


## Convex: compute wall positions from filled cell's exposed edges.
func _add_convex_arch_tiles(
		tile_list: Array[Dictionary],
		corner: Dictionary,
		dir: int,
		wall_base_y: float,
		abs_height_cells: int,
		top_y: float,
		uv_rect: Rect2,
		depth: float,
		flip_walls: bool) -> void:

	var filled: Vector2i = corner["filled_cell"]
	var corner_pos: Vector2 = corner["corner_pos"]
	var fx: float = float(filled.x)
	var fz: float = float(filled.y)

	# Determine which 2 edges are exposed at this corner by comparing
	# filled cell position to corner position.
	# If corner is north of cell center (corner_z < cell_z) → -Z edge exposed
	# If corner is south of cell center (corner_z > cell_z) → +Z edge exposed
	# If corner is east of cell center (corner_x > cell_x) → +X edge exposed
	# If corner is west of cell center (corner_x < cell_x) → -X edge exposed

	var w1_x: float  # Z-axis wall (north or south edge)
	var w1_z: float
	var w1_ori: int
	var w2_x: float  # X-axis wall (east or west edge)
	var w2_z: float
	var w2_ori: int

	# Z-axis wall (north or south)
	if corner_pos.y < fz:  # corner is north of cell → -Z edge
		w1_x = fx
		w1_z = fz - 0.5
		w1_ori = 3  # SCULPT_WALL_NORTH → ori=3 (WALL_SOUTH)
	else:  # corner is south of cell → +Z edge
		w1_x = fx
		w1_z = fz + 0.5
		w1_ori = 2  # SCULPT_WALL_SOUTH → ori=2 (WALL_NORTH)

	# X-axis wall (east or west)
	if corner_pos.x > fx:  # corner is east of cell → +X edge
		w2_x = fx + 0.5
		w2_z = fz
		w2_ori = 5  # SCULPT_WALL_EAST → ori=5 (WALL_WEST)
	else:  # corner is west of cell → -X edge
		w2_x = fx - 0.5
		w2_z = fz
		w2_ori = 4  # SCULPT_WALL_WEST → ori=4 (WALL_EAST)

	# Select recipes based on direction
	var wall1_recipe: Array = GlobalConstants.ARCH_CONVEX_WALL1[dir]
	var wall2_recipe: Array = GlobalConstants.ARCH_CONVEX_WALL2[dir]
	var cap_recipe: Array = GlobalConstants.ARCH_CONVEX_CAP[dir]

	# Add wall tiles at each Y layer
	for i: int in range(abs_height_cells):
		var wy: float = wall_base_y + float(i)

		# Wall 1 (Z-axis wall) — same position as flat wall, arch mesh_mode + rotation
		_append_tile(tile_list,
			Vector3(w1_x, wy, w1_z),
			w1_ori,
			int(wall1_recipe[0]),  # mesh_mode
			int(wall1_recipe[2]),  # rotation
			uv_rect, depth, flip_walls)

		# Wall 2 (X-axis wall) — same position as flat wall, arch mesh_mode + rotation
		_append_tile(tile_list,
			Vector3(w2_x, wy, w2_z),
			w2_ori,
			int(wall2_recipe[0]),  # mesh_mode
			int(wall2_recipe[2]),  # rotation
			uv_rect, depth, flip_walls)

	# Cap ceiling tile at the filled cell position
	_append_tile(tile_list,
		Vector3(fx, top_y, fz),
		int(cap_recipe[1]),  # orientation (FLOOR=0)
		int(cap_recipe[0]),  # mesh_mode
		int(cap_recipe[2]),  # rotation
		uv_rect, depth, false)


## Concave: uses the direction-based offset approach (TODO: verify against data)
func _add_concave_arch_tiles(
		tile_list: Array[Dictionary],
		corner: Dictionary,
		dir: int,
		wall_base_y: float,
		abs_height_cells: int,
		top_y: float,
		uv_rect: Rect2,
		depth: float,
		flip_walls: bool) -> void:

	var corner_pos: Vector2 = corner["corner_pos"]

	var wall1_recipe: Array = GlobalConstants.ARCH_CONCAVE_WALL1[dir]
	var wall2_recipe: Array = GlobalConstants.ARCH_CONCAVE_WALL2[dir]
	var cap_recipe: Array = GlobalConstants.ARCH_CONCAVE_CAP[dir]

	# For concave, use the offset table (TODO: compute from cell edges like convex)
	var offsets: Array = GlobalConstants.ARCH_CORNER_OFFSETS[dir]
	var w1_x: float = corner_pos.x + offsets[0]
	var w1_z: float = corner_pos.y + offsets[1]
	var w2_x: float = corner_pos.x + offsets[2]
	var w2_z: float = corner_pos.y + offsets[3]
	var cap_x: float = corner_pos.x + offsets[4]
	var cap_z: float = corner_pos.y + offsets[5]

	for i: int in range(abs_height_cells):
		var wy: float = wall_base_y + float(i)

		_append_tile(tile_list,
			Vector3(w1_x, wy, w1_z),
			int(wall1_recipe[1]),
			int(wall1_recipe[0]),
			int(wall1_recipe[2]),
			uv_rect, depth, flip_walls)

		_append_tile(tile_list,
			Vector3(w2_x, wy, w2_z),
			int(wall2_recipe[1]),
			int(wall2_recipe[0]),
			int(wall2_recipe[2]),
			uv_rect, depth, flip_walls)

	_append_tile(tile_list,
		Vector3(cap_x, top_y, cap_z),
		int(cap_recipe[1]),
		int(cap_recipe[0]),
		int(cap_recipe[2]),
		uv_rect, depth, false)


## Creates a raw tile Dictionary and appends it to tile_list.
## Mirrors the format of SculptManager._sculpt_add_tile().
func _append_tile(
		tile_list: Array[Dictionary],
		grid_pos: Vector3,
		orientation: int,
		mesh_mode: int,
		mesh_rotation: int,
		uv_rect: Rect2,
		depth_scale: float,
		flip: bool) -> void:
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
	tile_list.append({
		"tile_key": tile_key,
		"grid_pos": grid_pos,
		"uv_rect": uv_rect,
		"orientation": orientation,
		"rotation": mesh_rotation,
		"flip": flip,
		"mode": mesh_mode,
		"terrain_id": GlobalConstants.AUTOTILE_NO_TERRAIN,
		"depth_scale": depth_scale,
		"texture_repeat_mode": 0,
	})
