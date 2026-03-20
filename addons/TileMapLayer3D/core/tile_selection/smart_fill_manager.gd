class_name SmartFillManager
extends RefCounted

## Two-click surface fill with live preview.
## Step 1: Visual feedback only — no tiles generated.
## State is read by TileMapLayerGizmo._redraw() for rendering.

enum SmartFillState {
	IDLE,       ## No interaction
	START_SET,  ## Start tile selected, showing preview on mouse move
	END_SET,    ## End tile selected stops preview on mouse move. Start and End defined.
	# WIDTH_UPDATE,  ## Awaiting state to allow for Witdh change.
	# WIDTH_SET,  ## Awaiting state to allow for Witdh change.



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

# ## ## Growth direction for width adjustment: 0=center, 1=right, -1=left.
# var quad_growth_dir: int = 0
# ## Current fill width in tiles (1 = single row). Grows symmetrically in grid_size increments.
# ## Width=1 is center only, width=3 is center ± 1 tile, width=5 is center ± 2 tiles.
# var fill_width: int = 1

## Live preview position (updated every mouse move).
var preview_world_pos: Vector3 = Vector3.ZERO
var preview_active: bool = false  ## True only when mouse is over a real tile

## Grid size (from tilemap settings, set on start click).
var grid_size: float = 1.0

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
		push_warning("[SmartFill] No UV available")
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
	var is_flipped: bool = placement_manager.is_current_face_flipped
	var mesh_mode: int = _active_tilema3d_node.current_mesh_mode
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

	undo_redo.commit_action()


## Sets the start tile and transitions to START_SET.
func set_start(tile_data: Dictionary, tile_key: int, p_grid_size: float) -> void:
	print("set_start")
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
	print("set_end")
	end_tile_data = tile_data
	state = SmartFillState.END_SET
	preview_active = true


# ## Transitions from END_SET to WIDTH_UPDATE.
# ## Called by the plugin when the user enters the width adjustment phase.
# func enter_width_update() -> void:
# 	# if state != SmartFillState.END_SET:
# 	# 	return
# 	print("enter_width_update")
# 	# fill_width = 1
# 	state = SmartFillState.WIDTH_UPDATE
# 	preview_active = true

# func set_width() -> void:
# 	print("set_width")

# 	# if _active_tilema3d_node:
# 	# 	_active_tilema3d_node.settings.smart_fill_width = width

# 	preview_active = true
# 	state = SmartFillState.WIDTH_SET

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
	# if _active_tilema3d_node:
	# 	_active_tilema3d_node.settings.smart_fill_width = 1
	tile_transforms = []


## Returns the 4 corners of the preview quad as a PackedVector3Array.
## This data is cached locally and used for Tile creation
## It's also used by the gizmo to render the fill preview
## Returns the 4 corners of the preview quad as a PackedVector3Array.
## grow_direction: 0 = symmetric (default), 1 = grow right, -1 = grow left
func get_preview_quad_vertices(grow_direction: int = 1) -> PackedVector3Array:
	if not preview_active or state == SmartFillState.IDLE:
		return PackedVector3Array()

	var a: Vector3 = start_world_pos

	var fill_width: int = 1
	if _active_tilema3d_node:
		fill_width = _active_tilema3d_node.settings.smart_fill_width
		grow_direction = _active_tilema3d_node.settings.smart_fill_quad_growth_dir


	## Once end tile is set (END_SET, WIDTH_UPDATE, WIDTH_SET), use the locked position.
	## During START_SET, use the live mouse preview position.
	var b: Vector3
	if state != SmartFillState.START_SET and not end_tile_data.is_empty():
		b = GlobalUtil.grid_to_world(end_tile_data["grid_position"], grid_size)
	else:
		b = preview_world_pos

	# print("quad_growth_dir in get_preview_quad_vertices = ", grow_direction)
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

	## Row count from grid-space distance between start and end tiles.
	var start_grid: Vector3 = start_tile_data["grid_position"]
	var end_grid: Vector3 = end_tile_data["grid_position"]
	var diff: Vector3 = end_grid - start_grid
	if diff.length_squared() < 0.001:
		return result

	var surface_normal: Vector3 = _get_surface_normal()
	var axes: Array[Vector3] = _get_surface_axes(surface_normal)
	var proj_h: float = absf(diff.dot(axes[0]))
	var proj_v: float = absf(diff.dot(axes[1]))
	var step_count: int = roundi(maxf(proj_h, proj_v))

	if step_count <= 1:
		return result

	## Rows = steps between endpoints (exclusive of both).
	var row_count: int = step_count - 1

	## Subdivide the cached quad — same loop as get_fill_tile_transforms.
	var v0: Vector3 = cached_quad_vertices[0]
	var v1: Vector3 = cached_quad_vertices[1]
	var v2: Vector3 = cached_quad_vertices[2]
	var v3: Vector3 = cached_quad_vertices[3]

	for i: int in range(row_count):
		var t0: float = float(i) / float(row_count)
		var t1: float = float(i + 1) / float(row_count)

		var row_left_start: Vector3 = v0.lerp(v3, t0)
		var row_right_start: Vector3 = v1.lerp(v2, t0)
		var row_left_end: Vector3 = v0.lerp(v3, t1)
		var row_right_end: Vector3 = v1.lerp(v2, t1)

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
