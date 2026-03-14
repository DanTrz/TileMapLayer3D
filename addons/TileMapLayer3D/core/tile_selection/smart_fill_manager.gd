class_name SmartFillManager
extends RefCounted

## Two-click surface fill with live preview.
## Step 1: Visual feedback only — no tiles generated.
## State is read by SculptBrushGizmo._redraw() for rendering.

enum SmartFillState {
	IDLE,       ## No interaction
	START_SET,  ## Start tile selected, showing preview on mouse move
	END_SET,    ## End tile selected, showing preview on mouse move

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
	print("_execute_smart_fill_ramp")

	if not placement_manager or not _active_tilema3d_node:
		return
	
	#Early return if not in the correct mode
	if not _active_tilema3d_node.settings.smart_fill_mode == GlobalConstants.SmartFillMode.FILL_RAMP:
		return
	
	if end_tile_data.is_empty():
		push_warning("[SmartFill] No end tile selected")
		return

	var fill_positions: Array[Vector3] = get_fill_grid_positions(end_tile_data)
	if fill_positions.is_empty():
		return

	var uv_rect: Rect2 = placement_manager.current_tile_uv
	if uv_rect.size.x <= 0 or uv_rect.size.y <= 0:
		push_warning("[SmartFill] No UV available. Make sure a Tile is selected in the TilesetPanel")
		return

	## Compute per-tile transforms directly from the preview quad geometry.
	## This bypasses the orientation/tilt parameter system entirely.
	var transforms: Array[Transform3D] = get_fill_tile_transforms(end_tile_data)
	if transforms.size() != fill_positions.size():
		push_warning("[SmartFill] Transform count mismatch: %d transforms vs %d positions" % [transforms.size(), fill_positions.size()])
		return

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
			"custom_transform": transforms[i],
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
	preview_active = false


## Sets the end tile and transitions to END_SET.
func set_end(tile_data: Dictionary, tile_key: int, p_grid_size: float) -> void:
	print("set_end")
	# start_tile_data = tile_data
	# start_tile_key = tile_key
	# grid_size = p_grid_size
	# base_orientation = GlobalUtil.get_base_tile_orientation(tile_data["orientation"])
	# start_world_pos = GlobalUtil.grid_to_world(tile_data["grid_position"], grid_size)
	end_tile_data = tile_data
	state = SmartFillState.END_SET
	preview_active = false

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


## Returns the 4 corners of the preview quad as a PackedVector3Array.
## Used by the gizmo to render the fill preview.
## The quad starts from the EDGE of the start tile closest to the preview tile,
## and ends at the EDGE of the preview tile closest to the start tile.
## Returns empty array if preview is not active.
func get_preview_quad_vertices() -> PackedVector3Array:
	if not preview_active or state != SmartFillState.START_SET:
		return PackedVector3Array()

	var a: Vector3 = start_world_pos
	var b: Vector3 = preview_world_pos

	## Direction from start center to preview center.
	var fill_dir: Vector3 = b - a
	if fill_dir.length_squared() < 0.001:
		return PackedVector3Array()

	## Find the closest edge of the start tile toward the preview tile.
	## Project fill_dir onto the tile's local axes and pick the dominant one.
	var half: float = grid_size * 0.5
	var edge_offset: Vector3 = _get_closest_edge_offset(fill_dir, half)

	## Quad starts at the start tile's edge, ends at the preview tile's opposite edge.
	var edge_a: Vector3 = a + edge_offset
	var edge_b: Vector3 = b - edge_offset

	## Perpendicular direction for quad width (one tile wide).
	var perp: Vector3 = _get_perpendicular(fill_dir)

	## Four corners of the quad.
	var verts: PackedVector3Array = PackedVector3Array()
	verts.append(edge_a - perp * half)  ## bottom-left
	verts.append(edge_a + perp * half)  ## top-left
	verts.append(edge_b + perp * half)  ## top-right
	verts.append(edge_b - perp * half)  ## bottom-right
	return verts


## Returns the offset from tile center to the closest edge in the direction of fill_dir.
## Projects fill_dir onto the tile's local axes and picks the dominant axis.
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


## Returns grid positions for tiles to fill the gap between start and end tiles.
## Walks from the start tile's edge to the end tile's edge along the dominant axis,
## interpolating the other coordinates (including height for ramps/slopes).
## Does NOT include the start tile or end tile positions themselves.
func get_fill_grid_positions(end_tile_data: Dictionary) -> Array[Vector3]:
	var result: Array[Vector3] = []

	var start_grid: Vector3 = start_tile_data["grid_position"]
	var end_grid: Vector3 = end_tile_data["grid_position"]

	## Direction from start to end in grid space.
	var diff: Vector3 = end_grid - start_grid
	if diff.length_squared() < 0.001:
		return result

	## Get surface axes to determine the fill direction.
	var surface_normal: Vector3 = _get_surface_normal()
	var axes: Array[Vector3] = _get_surface_axes(surface_normal)
	var axis_h: Vector3 = axes[0]
	var axis_v: Vector3 = axes[1]

	## Project onto surface axes to find the dominant fill direction.
	var proj_h: float = diff.dot(axis_h)
	var proj_v: float = diff.dot(axis_v)

	## The dominant axis determines step direction; the other axis interpolates.
	var step_axis: Vector3
	var step_count: int
	if absf(proj_h) >= absf(proj_v):
		step_axis = axis_h * signf(proj_h)
		step_count = roundi(absf(proj_h))
	else:
		step_axis = axis_v * signf(proj_v)
		step_count = roundi(absf(proj_v))

	if step_count <= 1:
		## Adjacent tiles — nothing to fill between them.
		return result

	## Walk from start+1 to end-1 (exclusive of both endpoints).
	## Interpolate ALL coordinates (including height) for ramp support.
	for i: int in range(1, step_count):
		var t: float = float(i) / float(step_count)
		var grid_pos: Vector3 = start_grid.lerp(end_grid, t)
		## Snap to grid integers to match tile key system.
		grid_pos = Vector3(
			snappedf(grid_pos.x, 1.0),
			snappedf(grid_pos.y, 0.5),
			snappedf(grid_pos.z, 1.0)
		)
		result.append(grid_pos)

	return result


## Returns the tilted orientation, mesh rotation, and custom transform params for fill tiles.
## Computes the actual tilt angle from the geometry (not limited to 45°).
## Returns: {orientation, mesh_rotation, tilt_angle_rad, diagonal_scale, tilt_offset_factor}
## If tiles are at the same height, returns the start tile's flat orientation with defaults.
func get_fill_transform_data(end_tile_data: Dictionary) -> Dictionary:
	var start_grid: Vector3 = start_tile_data["grid_position"]
	var end_grid: Vector3 = end_tile_data["grid_position"]
	var start_ori: int = start_tile_data["orientation"]
	var diff: Vector3 = end_grid - start_grid

	## Step count (same as get_fill_grid_positions uses).
	var surface_normal: Vector3 = _get_surface_normal()
	var axes: Array[Vector3] = _get_surface_axes(surface_normal)
	var proj_h: float = diff.dot(axes[0])
	var proj_v: float = diff.dot(axes[1])
	var step_count: int = maxi(roundi(absf(proj_h)), roundi(absf(proj_v)))
	if step_count == 0:
		step_count = 1

	## Height change per step.
	var height_per_step: float = diff.y / float(step_count)

	## No height difference — flat fill.
	if absf(height_per_step) < 0.01:
		return {
			"orientation": start_ori,
			"mesh_rotation": 0,
			"tilt_angle_rad": 0.0,
			"diagonal_scale": 0.0,
			"tilt_offset_factor": 0.0,
		}

	## Compute actual tilt angle from height per horizontal step.
	## One grid step = 1.0 horizontal, height_per_step vertical.
	var tilt_angle: float = atan2(absf(height_per_step), 1.0)

	## Diagonal scale: tile must stretch to cover the hypotenuse.
	var diagonal_scale: float = 1.0 / cos(tilt_angle)

	## Tilt offset: moves tile vertically so pivot aligns with grid.
	## Half the height per step, normalized to grid_size.
	var tilt_offset: float = absf(height_per_step) * 0.5

	## Determine tilted orientation and mesh rotation from direction.
	var going_up: bool = height_per_step > 0.0
	var mesh_rot: int = _get_horizontal_mesh_rotation(diff)

	match base_orientation:
		GlobalUtil.TileOrientation.FLOOR:
			var tilt_ori: int = GlobalUtil.TileOrientation.FLOOR_TILT_POS_X if going_up else GlobalUtil.TileOrientation.FLOOR_TILT_NEG_X
			return {
				"orientation": tilt_ori,
				"mesh_rotation": mesh_rot,
				"tilt_angle_rad": tilt_angle,
				"diagonal_scale": diagonal_scale,
				"tilt_offset_factor": tilt_offset,
			}
		GlobalUtil.TileOrientation.CEILING:
			var tilt_ori: int = GlobalUtil.TileOrientation.CEILING_TILT_POS_X if going_up else GlobalUtil.TileOrientation.CEILING_TILT_NEG_X
			return {
				"orientation": tilt_ori,
				"mesh_rotation": mesh_rot,
				"tilt_angle_rad": tilt_angle,
				"diagonal_scale": diagonal_scale,
				"tilt_offset_factor": tilt_offset,
			}
		_:
			## Wall orientations — use start orientation for now.
			return {
				"orientation": start_ori,
				"mesh_rotation": 0,
				"tilt_angle_rad": 0.0,
				"diagonal_scale": 0.0,
				"tilt_offset_factor": 0.0,
			}


## Determines mesh rotation based on horizontal direction of fill.
## Maps the dominant horizontal axis to a Q/E rotation step.
## mesh_rotation 0 = tilt faces +Z, 1 = +X, 2 = -Z, 3 = -X
func _get_horizontal_mesh_rotation(diff: Vector3) -> int:
	var abs_x: float = absf(diff.x)
	var abs_z: float = absf(diff.z)

	if abs_z >= abs_x:
		return 0 if diff.z > 0 else 2
	else:
		return 1 if diff.x > 0 else 3


## Computes world-space Transform3D for each fill tile by subdividing the preview quad.
## The preview quad defines the correct 3D surface — each tile gets a sub-quad of it.
## Returns one Transform3D per fill position. Bypasses orientation/tilt param system.
func get_fill_tile_transforms(end_tile_data: Dictionary) -> Array[Transform3D]:
	var result: Array[Transform3D] = []

	var fill_positions: Array[Vector3] = get_fill_grid_positions(end_tile_data)
	if fill_positions.is_empty():
		return result

	## Compute the full preview quad from start tile to end tile (same logic as get_preview_quad_vertices).
	var a: Vector3 = start_world_pos
	var end_grid: Vector3 = end_tile_data["grid_position"]
	var b: Vector3 = GlobalUtil.grid_to_world(end_grid, grid_size)

	var fill_dir: Vector3 = b - a
	if fill_dir.length_squared() < 0.001:
		return result

	var half: float = grid_size * 0.5
	var edge_offset: Vector3 = _get_closest_edge_offset(fill_dir, half)
	var perp: Vector3 = _get_perpendicular(fill_dir)

	## Full quad from start edge to end edge.
	var edge_a: Vector3 = a + edge_offset
	var edge_b: Vector3 = b - edge_offset

	var v0: Vector3 = edge_a - perp * half  ## start-left
	var v1: Vector3 = edge_a + perp * half  ## start-right
	var v2: Vector3 = edge_b + perp * half  ## end-right
	var v3: Vector3 = edge_b - perp * half  ## end-left

	var count: int = fill_positions.size()

	for i: int in range(count):
		var t0: float = float(i) / float(count)
		var t1: float = float(i + 1) / float(count)

		## Sub-quad corners by lerping along the fill direction.
		var bl: Vector3 = v0.lerp(v3, t0)
		var tl: Vector3 = v1.lerp(v2, t0)
		var br: Vector3 = v0.lerp(v3, t1)
		var tr: Vector3 = v1.lerp(v2, t1)

		## Center of this sub-tile.
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
