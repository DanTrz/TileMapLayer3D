class_name SmartFillManager
extends RefCounted

enum SmartFillState {
	IDLE,       ## No interaction
	START_SET,  ## Start tile selected, showing preview on mouse move
	END_SET,    ## End tile selected stops preview on mouse move. Start and End defined.
}

## Current active TileMapLayer3D node and PlaceManager References
var _active_tilema3d_node: TileMapLayer3D = null  # TileMapLayer3D
var placement_manager: TilePlacementManager = null

## Current state.
var state: SmartFillState = SmartFillState.IDLE

## Start tile data (set on click 1 via pick_tile_at).
var start_tile_data: Dictionary = {}
var start_tile_key: int = 0
var start_world_pos: Vector3 = Vector3.ZERO
var end_tile_data: Dictionary = {}

var tile_transforms: Array[Transform3D] = []
var cached_quad_vertices: PackedVector3Array = PackedVector3Array()

## Live preview position (updated every mouse move).
var preview_world_pos: Vector3 = Vector3.ZERO
var preview_active: bool = false  ## True only when mouse is over a real tile

## Grid size (from tilemap settings, set on start click).
var grid_size: float = 1.0

## ## Threshold for subdividing ramp sides (0.0 to 1.0).
## Lower equals more rows per column.
var row_division_sides_thres: float = 1.00

## Threshold for subdividing ramp faces (main ramp) (0.0 to 1.0).
var row_division_face_thres: float = 1.00




## Ratio threshold for diagonal detection (min/max projection).
## When both surface axis projections are similar (~35-55 degree range), snap to center.
const DIAGONAL_SNAP_THRESHOLD: float = 0.7

## Base orientation of the start tile (cached for perpendicular calculation).
var base_orientation: int = 0



## Called by plugin when _edit() is invoked
func set_active_node(tilemap_node: TileMapLayer3D, placement_mgr: TilePlacementManager) -> void:
	_active_tilema3d_node = tilemap_node
	placement_manager = placement_mgr
	# active_mode = _active_tilema3d_node.settings.smart_fill_mode


## Executes Smart Fill RAMP FILL: places tiles between start and end tiles using current UV selection in a ramp pattern.
func _execute_smart_fill_ramp(plugin: EditorPlugin) -> void:
	if not placement_manager or not _active_tilema3d_node:
		return

	if not _active_tilema3d_node.settings.smart_fill_mode == GlobalConstants.SmartFillMode.FILL_RAMP:
		return

	## Everything is already cached from the preview phase.
	if cached_quad_vertices.size() != 4:
		push_warning("[SmartFill] No cached preview quad")
		return

	# print("[SmartFill EXECUTE] fill_width=", fill_width)
	# print("[SmartFill EXECUTE] cached_quad=", cached_quad_vertices)
	var fill_width:int = 1
	if _active_tilema3d_node:
		fill_width = _active_tilema3d_node.settings.smart_fill_width

	var fill_positions: Array[Vector3] = get_fill_grid_positions(fill_width)
	if fill_positions.is_empty():
		return

	# print("[SmartFill EXECUTE] fill_positions count=", fill_positions.size(), " positions=", fill_positions)

	var uv_rect: Rect2 = placement_manager.current_tile_uv
	if uv_rect.size.x <= 0 or uv_rect.size.y <= 0:
		push_warning("[SmartFill] No UV Tile selected - First select a Tile in the TileSet Panel")
		return

	## Subdivide the CACHED preview quad into per-tile transforms.
	tile_transforms = get_fill_tile_transforms(fill_positions, fill_width)

	# print("[SmartFill EXECUTE] tile_transforms count=", tile_transforms.size())
	# for t_idx: int in range(tile_transforms.size()):
	# 	print("  transform[", t_idx, "] origin=", tile_transforms[t_idx].origin)

	if tile_transforms.size() != fill_positions.size():
		push_warning("[SmartFill] Transform count mismatch")
		return

	preview_active = false

	## Use base orientation for columnar storage (flat orientation, no tilt params).
	var orientation: int = base_orientation
	# var is_flipped: bool = placement_manager.is_current_face_flipped
	var is_flipped: bool = _active_tilema3d_node.settings.smart_fill_flip_face
	var mesh_mode: int = GlobalConstants.MeshMode.FLAT_SQUARE
	var depth_scale: float = placement_manager.current_depth_scale
	var texture_repeat: int = placement_manager.current_texture_repeat_mode

	## Place tiles directly 
	var undo_redo: Object = plugin.get_undo_redo()
	undo_redo.create_action("Smart Fill (%d tiles)" % fill_positions.size())

	for i: int in range(fill_positions.size()):
		var grid_pos: Vector3 = fill_positions[i]
		var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
		var tile_info: Dictionary = {
			"tile_key": tile_key,
			"grid_pos": grid_pos,
			"uv_rect": uv_rect,
			"orientation": orientation,
			"rotation": 0,
			"flip": is_flipped,
			"mode": mesh_mode,
			"terrain_id": GlobalConstants.AUTOTILE_NO_TERRAIN,
			"spin_angle_rad": 0.0,
			"tilt_angle_rad": 0.0,
			"diagonal_scale": 0.0,
			"tilt_offset_factor": 0.0,
			"depth_scale": depth_scale,
			"texture_repeat_mode": texture_repeat,
			"custom_transform": tile_transforms[i],
		}

		## Capture existing tile for undo if one exists at this position.
		var has_existing: bool = _active_tilema3d_node.has_tile(tile_key)
		var existing_info: Dictionary = {}
		if has_existing:
			existing_info = placement_manager._get_existing_tile_info(tile_key)

		undo_redo.add_do_method(placement_manager, "_do_place_tile",
			tile_key, grid_pos, uv_rect, orientation, 0, tile_info)

		if has_existing and not existing_info.is_empty():
			## Undo restores the previous tile.
			var undo_tile_info: Dictionary = {
				"grid_pos": existing_info.get("grid_position", grid_pos),
				"uv_rect": existing_info.get("uv_rect", Rect2()),
				"orientation": existing_info.get("orientation", orientation),
				"rotation": existing_info.get("mesh_rotation", 0),
				"flip": existing_info.get("is_face_flipped", false),
				"mode": existing_info.get("mesh_mode", GlobalConstants.MeshMode.FLAT_SQUARE),
				"terrain_id": existing_info.get("terrain_id", GlobalConstants.AUTOTILE_NO_TERRAIN),
				"spin_angle_rad": existing_info.get("spin_angle_rad", 0.0),
				"tilt_angle_rad": existing_info.get("tilt_angle_rad", 0.0),
				"diagonal_scale": existing_info.get("diagonal_scale", 0.0),
				"tilt_offset_factor": existing_info.get("tilt_offset_factor", 0.0),
				"depth_scale": existing_info.get("depth_scale", 1.0),
				"texture_repeat_mode": existing_info.get("texture_repeat_mode", 0),
				"custom_transform": existing_info.get("custom_transform", Transform3D()),
			}
			undo_redo.add_undo_method(placement_manager, "_do_place_tile",
				tile_key, existing_info.get("grid_position", grid_pos),
				existing_info.get("uv_rect", Rect2()),
				existing_info.get("orientation", orientation),
				existing_info.get("mesh_rotation", 0),
				undo_tile_info)
		else:
			## Undo erases the tile.
			undo_redo.add_undo_method(placement_manager, "_do_erase_tile", tile_key)

	## Place side fill tiles if enabled.
	if _active_tilema3d_node.settings.smart_fill_ramp_sides:
		var side_tiles: Array[Dictionary] = _compute_side_fill_tiles(
			uv_rect, is_flipped, depth_scale, texture_repeat)
		for side_data: Dictionary in side_tiles:
			var side_grid_pos: Vector3 = side_data["grid_pos"]
			var side_ori: int = side_data["orientation"]
			var side_key: int = GlobalUtil.make_tile_key(side_grid_pos, side_ori)
			var side_rotation: int = side_data["rotation"]

			var has_existing_side: bool = _active_tilema3d_node.has_tile(side_key)
			var existing_side_info: Dictionary = {}
			if has_existing_side:
				existing_side_info = placement_manager._get_existing_tile_info(side_key)

			undo_redo.add_do_method(placement_manager, "_do_place_tile",
				side_key, side_grid_pos, uv_rect, side_ori, side_rotation, side_data)

			if has_existing_side and not existing_side_info.is_empty():
				var undo_side_info: Dictionary = {
					"grid_pos": existing_side_info.get("grid_position", side_grid_pos),
					"uv_rect": existing_side_info.get("uv_rect", Rect2()),
					"orientation": existing_side_info.get("orientation", side_ori),
					"rotation": existing_side_info.get("mesh_rotation", 0),
					"flip": existing_side_info.get("is_face_flipped", false),
					"mode": existing_side_info.get("mesh_mode", GlobalConstants.MeshMode.FLAT_SQUARE),
					"terrain_id": existing_side_info.get("terrain_id", GlobalConstants.AUTOTILE_NO_TERRAIN),
					"spin_angle_rad": existing_side_info.get("spin_angle_rad", 0.0),
					"tilt_angle_rad": existing_side_info.get("tilt_angle_rad", 0.0),
					"diagonal_scale": existing_side_info.get("diagonal_scale", 0.0),
					"tilt_offset_factor": existing_side_info.get("tilt_offset_factor", 0.0),
					"depth_scale": existing_side_info.get("depth_scale", 1.0),
					"texture_repeat_mode": existing_side_info.get("texture_repeat_mode", 0),
					"custom_transform": existing_side_info.get("custom_transform", Transform3D()),
				}
				undo_redo.add_undo_method(placement_manager, "_do_place_tile",
					side_key, existing_side_info.get("grid_position", side_grid_pos),
					existing_side_info.get("uv_rect", Rect2()),
					existing_side_info.get("orientation", side_ori),
					existing_side_info.get("mesh_rotation", 0),
					undo_side_info)
			else:
				undo_redo.add_undo_method(placement_manager, "_do_erase_tile", side_key)

	undo_redo.commit_action()


## Sets the start tile and transitions to START_SET.
func set_start(tile_data: Dictionary, tile_key: int, p_grid_size: float) -> void:
	start_tile_data = tile_data
	start_tile_key = tile_key
	grid_size = p_grid_size
	base_orientation = GlobalUtil.get_base_tile_orientation(start_tile_data["orientation"])
	start_world_pos = GlobalUtil.grid_to_world(start_tile_data["grid_position"], grid_size)
	state = SmartFillState.START_SET
	preview_active = true


## Sets the end tile and transitions to END_SET.
## This completes the operation and this state triggers the plugin to create the tiles
func set_end(tile_data: Dictionary, tile_key: int, p_grid_size: float) -> void:
	end_tile_data = tile_data
	state = SmartFillState.END_SET
	preview_active = true


## Updates the preview position (called on mouse move when over a tile).
func update_preview(world_pos: Vector3) -> void:
	preview_world_pos = world_pos
	preview_active = true


## Hides the preview quad (called when mouse is NOT over a tile).
func clear_preview() -> void:
	preview_active = false


## Resets all state back to IDLE.
func reset() -> void:
	state = SmartFillState.IDLE
	start_tile_data = {}
	end_tile_data = {}
	start_tile_key = 0
	start_world_pos = Vector3.ZERO
	preview_world_pos = Vector3.ZERO
	preview_active = false
	cached_quad_vertices = PackedVector3Array()
	tile_transforms = []


## Returns the 4 corners of the preview quad as a PackedVector3Array.
## This data is cached locally and used for Tile creation.
## Also used by the gizmo to render the fill preview.
## Growth direction and width are read from settings (single source of truth).
func get_preview_quad_vertices() -> PackedVector3Array:
	if not preview_active or state == SmartFillState.IDLE:
		return PackedVector3Array()
	if not _active_tilema3d_node:
		return PackedVector3Array()

	var a: Vector3 = start_world_pos

	var fill_width: int = 1
	var grow_direction: int = 1
	fill_width = _active_tilema3d_node.settings.smart_fill_width
	grow_direction = _active_tilema3d_node.settings.smart_fill_quad_growth_dir


	## Once end tile is set (END_SET), use the locked position.
	## During START_SET, use the live mouse preview position.
	var b: Vector3
	if state != SmartFillState.START_SET and not end_tile_data.is_empty():
		b = GlobalUtil.grid_to_world(end_tile_data["grid_position"], grid_size)
	else:
		b = preview_world_pos

	## Direction from start center to target center.
	var fill_dir: Vector3 = b - a
	if fill_dir.length_squared() < 0.001:
		return PackedVector3Array()

	## Find the closest edge of the start tile toward the target tile.
	var half: float = grid_size * 0.5
	var edge_offset: Vector3 = _get_closest_edge_offset(fill_dir, half)

	## Quad starts at the start tile's edge, ends at the target tile's opposite edge.
	var edge_a: Vector3 = a + edge_offset
	var edge_b: Vector3 = b - edge_offset

	## Perpendicular direction for quad width.
	var perp: Vector3 = _get_perpendicular(fill_dir)

	## Compute left/right offsets based on grow direction.
	var left_offset: Vector3
	var right_offset: Vector3

	if grow_direction == 1: ## Anchor left edge (fixed), grow right.
		left_offset = -perp * half
		right_offset = -perp * half + perp * grid_size * float(fill_width)
	elif grow_direction == 2: ## Anchor right edge (fixed), grow left.
		right_offset = perp * half
		left_offset = perp * half - perp * grid_size * float(fill_width)
	else:
		## Symmetric growth
		var half_w: float = half * float(fill_width)
		left_offset = -perp * half_w
		right_offset = perp * half_w

	## Four corners of the quad.
	var verts: PackedVector3Array = PackedVector3Array()
	verts.append(edge_a + left_offset)   ## bottom-left
	verts.append(edge_a + right_offset)  ## top-left
	verts.append(edge_b + right_offset)  ## top-right
	verts.append(edge_b + left_offset)   ## bottom-right

	cached_quad_vertices = verts
	return verts



## Returns the offset from tile center to the closest edge in the direction of fill_dir.
func _get_closest_edge_offset(fill_dir: Vector3, half: float) -> Vector3:
	var surface_normal: Vector3 = _get_surface_normal()

	## Get the two axes that span the tile's surface plane.
	var axes: Array[Vector3] = _get_surface_axes(surface_normal)
	var axis_h: Vector3 = axes[0]
	var axis_v: Vector3 = axes[1]

	## Project fill_dir onto each axis, pick the one with larger projection.
	var proj_h: float = fill_dir.dot(axis_h)
	var proj_v: float = fill_dir.dot(axis_v)

	var abs_h: float = absf(proj_h)
	var abs_v: float = absf(proj_v)
	var max_proj: float = maxf(abs_h, abs_v)

	## Diagonal detection: both axes have similar projection → snap to center.
	if max_proj > 0.001 and minf(abs_h, abs_v) / max_proj >= DIAGONAL_SNAP_THRESHOLD:
		return Vector3.ZERO

	if abs_h >= abs_v:
		return axis_h * half * signf(proj_h)
	else:
		return axis_v * half * signf(proj_v)


## Returns the two axes that span the tile's surface plane.
func _get_surface_axes(surface_normal: Vector3) -> Array[Vector3]:
	match base_orientation:
		GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
			return [Vector3.RIGHT, Vector3.BACK]  ## X and Z
		GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
			return [Vector3.RIGHT, Vector3.UP]  ## X and Y
		GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
			return [Vector3.BACK, Vector3.UP]  ## Z and Y
		_:
			return [Vector3.RIGHT, Vector3.BACK]


## Returns grid positions by subdividing the cached preview quad and converting to grid space.
func get_fill_grid_positions(width: int = 1) -> Array[Vector3]:
	var result: Array[Vector3] = []

	if cached_quad_vertices.size() != 4:
		return result

	## Row count from preview quad's fill-direction edge length (what the user sees).
	var v0: Vector3 = cached_quad_vertices[0]
	var v1: Vector3 = cached_quad_vertices[1]
	var v2: Vector3 = cached_quad_vertices[2]
	var v3: Vector3 = cached_quad_vertices[3]

	## Fill-direction edge length (3D, includes height change).
	var fill_edge: Vector3 = v3 - v0
	var quad_fill_length: float = fill_edge.length()
	var fill_dist: float = quad_fill_length / grid_size



	var row_count: int = _compute_step_count(fill_dist, row_division_face_thres)
	if row_count == 0:
		return result



	## Subdivide the cached quad — same loop as get_fill_tile_transforms.
	for i: int in range(row_count):
		var t0: float = float(i) / float(row_count)
		var t1: float = float(i + 1) / float(row_count)

		var row_left_start: Vector3 = v0.lerp(v3, t0)
		var row_right_start: Vector3 = v1.lerp(v2, t0)
		var row_left_end: Vector3 = v0.lerp(v3, t1)
		var row_right_end: Vector3 = v1.lerp(v2, t1)

		var row_world_size: float = (row_left_end - row_left_start).length()


		for col: int in range(width):
			var s0: float = float(col) / float(width)
			var s1: float = float(col + 1) / float(width)

			## Sub-quad center via bilinear interpolation.
			var bl: Vector3 = row_left_start.lerp(row_right_start, s0)
			var tl: Vector3 = row_left_start.lerp(row_right_start, s1)
			var br: Vector3 = row_left_end.lerp(row_right_end, s0)
			var tr: Vector3 = row_left_end.lerp(row_right_end, s1)
			var center_world: Vector3 = (bl + tl + br + tr) / 4.0

			## Convert world → grid and snap to tile key precision (0.1).
			## Must match TileKeySystem.COORD_SCALE=10. Coarser snaps (1.0)
			## collapse diagonal columns into the same grid cell.
			var grid_pos: Vector3 = GlobalUtil.world_to_grid(center_world, grid_size)
			grid_pos = Vector3(
				snappedf(grid_pos.x, 0.1),
				snappedf(grid_pos.y, 0.1),
				snappedf(grid_pos.z, 0.1)
			)
			result.append(grid_pos)

	return result


## Computes world-space Transform3D for each fill tile by subdividing the preview quad.
func get_fill_tile_transforms(fill_positions: Array[Vector3], width: int = 1) -> Array[Transform3D]:
	var result: Array[Transform3D] = []

	if fill_positions.is_empty():
		return result

	## Use the cached preview quad — same geometry the user saw.
	if cached_quad_vertices.size() != 4:
		return result
	var v0: Vector3 = cached_quad_vertices[0]  ## BL = start-left
	var v1: Vector3 = cached_quad_vertices[1]  ## TL = start-right
	var v2: Vector3 = cached_quad_vertices[2]  ## TR = end-right
	var v3: Vector3 = cached_quad_vertices[3]  ## BR = end-left

	## Number of rows along fill direction (center-row tile count).
	var row_count: int = fill_positions.size() / maxi(width, 1)

	## Row-major ordering: for each row, emit all columns sequentially.
	## This matches the ordering in get_fill_grid_positions().
	for i: int in range(row_count):
		var t0: float = float(i) / float(row_count)
		var t1: float = float(i + 1) / float(row_count)

		## Full-width row edges by lerping along fill direction.
		var row_left_start: Vector3 = v0.lerp(v3, t0)
		var row_right_start: Vector3 = v1.lerp(v2, t0)
		var row_left_end: Vector3 = v0.lerp(v3, t1)
		var row_right_end: Vector3 = v1.lerp(v2, t1)

		for col: int in range(width):
			var s0: float = float(col) / float(width)
			var s1: float = float(col + 1) / float(width)

			## Bilinear interpolation: sub-quad corners.
			var bl: Vector3 = row_left_start.lerp(row_right_start, s0)
			var tl: Vector3 = row_left_start.lerp(row_right_start, s1)
			var br: Vector3 = row_left_end.lerp(row_right_end, s0)
			var tr: Vector3 = row_left_end.lerp(row_right_end, s1)

			var center: Vector3 = (bl + tl + br + tr) / 4.0
			var width_vec: Vector3 = bl - tl
			var fill_vec: Vector3 = br - bl
			var normal: Vector3 = fill_vec.cross(width_vec).normalized()

			var basis_x: Vector3 = width_vec / grid_size
			var basis_z: Vector3 = fill_vec / grid_size
			var basis_y: Vector3 = normal

			result.append(Transform3D(Basis(basis_x, basis_y, basis_z), center))

	return result


## Computes the perpendicular direction on the surface plane.
## For floors: perpendicular is on XZ plane (cross with Y-up).
## For walls: perpendicular is on the wall's plane.
func _get_perpendicular(fill_dir: Vector3) -> Vector3:
	var surface_normal: Vector3 = _get_surface_normal()
	var perp: Vector3 = fill_dir.cross(surface_normal).normalized()
	if perp.length_squared() < 0.001:
		## Fallback: fill_dir is parallel to normal (shouldn't happen for same-surface).
		perp = Vector3.RIGHT
	return perp


## Returns the surface normal for the base orientation.
func _get_surface_normal() -> Vector3:
	match base_orientation:
		GlobalUtil.TileOrientation.FLOOR:
			return Vector3.UP
		GlobalUtil.TileOrientation.CEILING:
			return Vector3.DOWN
		GlobalUtil.TileOrientation.WALL_NORTH:
			return Vector3(0, 0, 1)
		GlobalUtil.TileOrientation.WALL_SOUTH:
			return Vector3(0, 0, -1)
		GlobalUtil.TileOrientation.WALL_EAST:
			return Vector3(1, 0, 0)
		GlobalUtil.TileOrientation.WALL_WEST:
			return Vector3(-1, 0, 0)
		_:
			return Vector3.UP


## Returns the closest wall orientation (2-5) for a given outward-facing normal.
func _get_wall_orientation_for_normal(normal: Vector3) -> int:
	var best_dot: float = -2.0
	var best_ori: int = GlobalUtil.TileOrientation.WALL_NORTH
	var wall_normals: Array[Array] = [
		[GlobalUtil.TileOrientation.WALL_NORTH, Vector3(0, 0, 1)],
		[GlobalUtil.TileOrientation.WALL_SOUTH, Vector3(0, 0, -1)],
		[GlobalUtil.TileOrientation.WALL_EAST, Vector3(1, 0, 0)],
		[GlobalUtil.TileOrientation.WALL_WEST, Vector3(-1, 0, 0)],
	]
	for entry: Array in wall_normals:
		var d: float = normal.dot(entry[1] as Vector3)
		if d > best_dot:
			best_dot = d
			best_ori = entry[0] as int
	return best_ori


## Computes side fill tiles (FLAT_SQUARE + FLAT_TRIANGULE) for the ramp staircase.
## Returns an array of tile_info Dictionaries ready for placement.
## Each side is a right-angle triangle filled with a staircase pattern:
##   column 0 (low end):  1 triangle
##   column 1:            1 square + 1 triangle
##   column i:            i squares + 1 triangle
func _compute_side_fill_tiles(uv_rect: Rect2, is_flipped: bool,
		depth_scale: float, texture_repeat: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if cached_quad_vertices.size() != 4:
		return result
	if not _active_tilema3d_node:
		return result

	var v0: Vector3 = cached_quad_vertices[0]  ## start-left
	var v1: Vector3 = cached_quad_vertices[1]  ## start-right
	var v2: Vector3 = cached_quad_vertices[2]  ## end-right
	var v3: Vector3 = cached_quad_vertices[3]  ## end-left

	var surface_normal: Vector3 = _get_surface_normal()

	## Height difference along left and right ramp edges.
	var left_height_diff: float = (v3 - v0).dot(surface_normal)
	var right_height_diff: float = (v2 - v1).dot(surface_normal)

	## Skip if ramp is flat (no height change → no sides needed).
	if absf(left_height_diff) < 0.01 and absf(right_height_diff) < 0.01:
		return result

	## Row count from preview quad's fill-direction edge length (same as get_fill_grid_positions).
	var fill_edge: Vector3 = v3 - v0
	var quad_fill_length: float = fill_edge.length()
	var fill_dist: float = quad_fill_length / grid_size

	var row_count: int = _compute_step_count(fill_dist, row_division_face_thres)
	if row_count == 0:
		return result


	## Fill direction perpendicular to get wall normals.
	var fill_dir: Vector3 = v3 - v0
	var perp: Vector3 = _get_perpendicular(fill_dir)

	## Process both sides: left edge (v0→v3) and right edge (v1→v2).
	var side_edges: Array[Array] = [
		[v0, v3, -perp],  ## Left side: wall faces outward (-perp)
		[v1, v2, perp],   ## Right side: wall faces outward (+perp)
	]

	for side: Array in side_edges:
		var edge_start: Vector3 = side[0] as Vector3
		var edge_end: Vector3 = side[1] as Vector3
		var wall_normal: Vector3 = side[2] as Vector3

		var height_diff: float = (edge_end - edge_start).dot(surface_normal)
		if absf(height_diff) < 0.01:
			continue

		var wall_ori: int = _get_wall_orientation_for_normal(wall_normal)

		## Resolve low/high points so staircase always builds upward.
		var low_point: Vector3 = edge_start if height_diff > 0.0 else edge_end
		var high_point: Vector3 = edge_end if height_diff > 0.0 else edge_start
		var abs_height: float = absf(height_diff)

		## Ground projection of the high point (at low point's height level).
		var ground_high: Vector3 = high_point - surface_normal * abs_height

		## Side step count from the arithmetic mean of both dimensions.
		## Minimizes max deviation of h_step and v_step from grid_size.
		var ground_span: float = (ground_high - low_point).length()
		var h_dist: float = ground_span / grid_size
		var v_dist: float = abs_height / grid_size
		var mean_dist: float = (h_dist + v_dist) / 2.0
		var side_steps: int = _compute_step_count(mean_dist, row_division_sides_thres)
		if side_steps == 0:
			continue

		var h_step_vec: Vector3 = (ground_high - low_point) / float(side_steps)
		var v_step_vec: Vector3 = surface_normal * (abs_height / float(side_steps))

		## Check if the basis determinant is negative (face renders inward).
		var natural_face_dir: Vector3 = h_step_vec.cross(v_step_vec)
		var reverse_winding: bool = natural_face_dir.dot(wall_normal) > 0.0

		## Build staircase: each column has `col` squares below diagonal + 1 triangle.
		for col: int in range(side_steps):
			var col_origin: Vector3 = low_point + h_step_vec * float(col)

			## 1 - SQUARE LOGIC: Place squares below the diagonal (col squares for column col).
			for row: int in range(col):
				var sq_p0: Vector3 = col_origin + v_step_vec * float(row)
				var sq_p1: Vector3 = col_origin + h_step_vec + v_step_vec * float(row)
				var sq_p2: Vector3 = col_origin + h_step_vec + v_step_vec * float(row + 1)
				var sq_p3: Vector3 = col_origin + v_step_vec * float(row + 1)
				var sq_bl: Vector3 = sq_p1 if reverse_winding else sq_p0
				var sq_br: Vector3 = sq_p0 if reverse_winding else sq_p1
				var sq_tr: Vector3 = sq_p3 if reverse_winding else sq_p2
				var sq_tl: Vector3 = sq_p2 if reverse_winding else sq_p3
				var sq_transform: Transform3D = _build_quad_custom_transform(
					sq_bl, sq_br, sq_tr, sq_tl, wall_normal)
				var sq_center: Vector3 = (sq_bl + sq_br + sq_tr + sq_tl) / 4.0
				var sq_grid_pos: Vector3 = GlobalUtil.world_to_grid(sq_center, grid_size)
				sq_grid_pos = Vector3(
					snappedf(sq_grid_pos.x, 0.1),
					snappedf(sq_grid_pos.y, 0.1),
					snappedf(sq_grid_pos.z, 0.1))
				result.append({
					"grid_pos": sq_grid_pos,
					"uv_rect": uv_rect,
					"orientation": wall_ori,
					"rotation": 0,
					"flip": false,
					"mode": GlobalConstants.MeshMode.FLAT_SQUARE,
					"terrain_id": GlobalConstants.AUTOTILE_NO_TERRAIN,
					"spin_angle_rad": 0.0,
					"tilt_angle_rad": 0.0,
					"diagonal_scale": 0.0,
					"tilt_offset_factor": 0.0,
					"depth_scale": depth_scale,
					"texture_repeat_mode": texture_repeat,
					"custom_transform": sq_transform,
				})
	
			## TRIANGULE LOGIC: Place triangle at the diagonal (top of this column).
			var tri_p0: Vector3 = col_origin + v_step_vec * float(col)
			var tri_p1: Vector3 = col_origin + h_step_vec + v_step_vec * float(col)
			var tri_p2: Vector3 = col_origin + h_step_vec + v_step_vec * float(col + 1)
			## Always map right-angle vertex (p1) to BL for perpendicular edges.
			var tri_bl: Vector3 = tri_p1
			var tri_br: Vector3 = tri_p0
			var tri_tl: Vector3 = tri_p2
			## Check if THIS triangle's face points away from wall_normal.
			var tri_edge_x: Vector3 = tri_br - tri_bl
			var tri_edge_z: Vector3 = tri_tl - tri_bl
			var tri_face_dir: Vector3 = tri_edge_x.cross(tri_edge_z)
			var tri_needs_flip: bool = tri_face_dir.dot(wall_normal) > 0.0
			var tri_transform: Transform3D = _build_triangle_custom_transform(
				tri_bl, tri_br, tri_tl, wall_normal, tri_needs_flip)
			var tri_center: Vector3 = (tri_bl + tri_br + tri_tl) / 3.0
			var tri_grid_pos: Vector3 = GlobalUtil.world_to_grid(tri_center, grid_size)
			tri_grid_pos = Vector3(
				snappedf(tri_grid_pos.x, 0.1),
				snappedf(tri_grid_pos.y, 0.1),
				snappedf(tri_grid_pos.z, 0.1))
			result.append({
				"grid_pos": tri_grid_pos,
				"uv_rect": uv_rect,
				"orientation": wall_ori,
				"rotation": 0,
				"flip": false,
				"mode": GlobalConstants.MeshMode.FLAT_TRIANGULE,
				"terrain_id": GlobalConstants.AUTOTILE_NO_TERRAIN,
				"spin_angle_rad": 0.0,
				"tilt_angle_rad": 0.0,
				"diagonal_scale": 0.0,
				"tilt_offset_factor": 0.0,
				"depth_scale": depth_scale,
				"texture_repeat_mode": texture_repeat,
				"custom_transform": tri_transform,
			})

	return result


## Builds a custom Transform3D that maps the base FLAT_SQUARE mesh to 4 target world vertices.
## Base mesh: BL(-h,0,-h), BR(h,0,-h), TR(h,0,h), TL(-h,0,h) where h = grid_size/2.
func _build_quad_custom_transform(bl: Vector3, br: Vector3, tr: Vector3, tl: Vector3,
		wall_normal: Vector3) -> Transform3D:
	var edge_x: Vector3 = br - bl
	var edge_z: Vector3 = tl - bl
	## Negate both axes to rotate UV 180° (fixes upside-down texture).
	## Face direction unchanged: (-ex)×(-ez) = ex×ez.
	var basis_x: Vector3 = -edge_x / grid_size
	var basis_z: Vector3 = -edge_z / grid_size
	var basis_y: Vector3 = wall_normal.normalized()
	var origin: Vector3 = bl + 0.5 * edge_x + 0.5 * edge_z
	return Transform3D(Basis(basis_x, basis_y, basis_z), origin)


## Builds a custom Transform3D that maps the base FLAT_TRIANGULE mesh to 3 target world vertices.
## Base mesh: BL(-h,0,-h), BR(h,0,-h), TL(-h,0,h) where h = grid_size/2.
func _build_triangle_custom_transform(bl: Vector3, br: Vector3, tl: Vector3,
		wall_normal: Vector3, flip_face: bool = false) -> Transform3D:
	var edge_x: Vector3 = br - bl
	var edge_z: Vector3 = tl - bl
	var basis_x: Vector3 = edge_x / grid_size
	var basis_z: Vector3 = edge_z / grid_size
	if flip_face:
		var tmp: Vector3 = basis_x
		basis_x = basis_z
		basis_z = tmp
	var basis_y: Vector3 = wall_normal.normalized()
	var origin: Vector3 = bl + 0.5 * edge_x + 0.5 * edge_z
	return Transform3D(Basis(basis_x, basis_y, basis_z), origin)


## Computes step count using the given threshold.
## Prefers more steps (ceili) when each cell stays >= threshold of grid_size.
## Returns 0 if dist is below threshold (caller should skip).
func _compute_step_count(dist: float, thres: float) -> int:
	if dist < thres:
		return 0
	var count_ceil: int = ceili(dist)
	if dist / float(count_ceil) >= thres:
		return count_ceil
	return maxi(1, floori(dist))
