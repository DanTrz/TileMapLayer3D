class_name GlobalPlaneDetector
extends RefCounted



signal auto_flip_requested(flip_state: bool)


static var current_tile_orientation_18d: int = GlobalUtil.TileOrientation.FLOOR

static var current_plane_6d: int = GlobalUtil.TileOrientation.FLOOR

static var previous_plane_6d: int = GlobalUtil.TileOrientation.FLOOR

static var is_cursor_on_plane: bool = false

static var current_plane_3d: Vector3 = Vector3.UP


static func detect_active_plane_3d(camera: Camera3D) -> Vector3:
	# 1. Get the camera's forward vector (-Z axis because Godot conventions)
	var camera_forward: Vector3 = -camera.global_transform.basis.z

	var abs_x: float = abs(camera_forward.x)
	var abs_y: float = abs(camera_forward.y)
	var abs_z: float = abs(camera_forward.z)

	if abs_y > abs_x and abs_y > abs_z:
		return Vector3.UP
	elif abs_x > abs_z:
		return Vector3.RIGHT
	else:
		return Vector3.FORWARD


static func detect_active_plane_6d(camera: Camera3D) -> int:
	# 1. Get the camera's forward vector (-Z axis because Godot conventions)
	var camera_forward: Vector3 = -camera.global_transform.basis.z

	var abs_x: float = abs(camera_forward.x)
	var abs_y: float = abs(camera_forward.y)
	var abs_z: float = abs(camera_forward.z)

	if abs_y > abs_x and abs_y > abs_z:
		if camera_forward.y > 0:
			return GlobalUtil.TileOrientation.CEILING
		else:
			return GlobalUtil.TileOrientation.FLOOR

	elif abs_x > abs_y and abs_x > abs_z:
		if camera_forward.x > 0:
			return GlobalUtil.TileOrientation.WALL_EAST
		else:
			return GlobalUtil.TileOrientation.WALL_WEST

	else:
		if camera_forward.z > 0:
			return GlobalUtil.TileOrientation.WALL_SOUTH
		else:
			return GlobalUtil.TileOrientation.WALL_NORTH


static func detect_orientation_from_cursor_plane(plane_normal: Vector3, camera: Camera3D) -> int:
	var base_orientation_6d: int = detect_active_plane_6d(camera)

	var current_base: int = _get_base_orientation(current_tile_orientation_18d)

	if current_base == base_orientation_6d:
		return current_tile_orientation_18d
	else:
		current_tile_orientation_18d = base_orientation_6d
		return base_orientation_6d


static func determine_auto_flip_for_plane(orientation_6d: int) -> bool:
	match orientation_6d:
		GlobalUtil.TileOrientation.FLOOR:
			return false
		GlobalUtil.TileOrientation.CEILING:
			return false
		GlobalUtil.TileOrientation.WALL_NORTH:
			return false
		GlobalUtil.TileOrientation.WALL_SOUTH:
			return false
		GlobalUtil.TileOrientation.WALL_EAST:
			return false
		GlobalUtil.TileOrientation.WALL_WEST:
			return false
		_:
			return false


static func determine_rotation_flip_for_plane(orientation_6d: int) -> bool:
	match orientation_6d:
		GlobalUtil.TileOrientation.FLOOR:
			return false
		GlobalUtil.TileOrientation.CEILING:
			return true
		GlobalUtil.TileOrientation.WALL_NORTH:
			return false
		GlobalUtil.TileOrientation.WALL_SOUTH:
			return false
		GlobalUtil.TileOrientation.WALL_EAST:
			return false
		GlobalUtil.TileOrientation.WALL_WEST:
			return false
		_:
			return false


static func update_from_camera(camera: Camera3D, emitter: Node = null) -> void:
	if not camera:
		return

	previous_plane_6d = current_plane_6d

	current_plane_3d = detect_active_plane_3d(camera)
	current_plane_6d = detect_active_plane_6d(camera)

	if previous_plane_6d != current_plane_6d:
		print_plane_change(previous_plane_6d, current_plane_6d)

		reset_to_flat()

		if emitter:
			var flip_state: bool = determine_auto_flip_for_plane(current_plane_6d)
			emitter.emit_signal("auto_flip_requested", flip_state)



static func cycle_tilt_forward() -> void:
	var tilt_sequence: Array = _get_tilt_sequence_for_orientation(current_tile_orientation_18d)

	if tilt_sequence.is_empty():
		return

	var current_index: int = tilt_sequence.find(current_tile_orientation_18d)

	current_index = (current_index + 1) % tilt_sequence.size()
	current_tile_orientation_18d = tilt_sequence[current_index]

	print("cycle_tilt_forward: ", GlobalUtil.TileOrientation.keys()[current_tile_orientation_18d], " - ", current_plane_6d,  current_index)

	_debug_tilt_state()


static func cycle_tilt_backward() -> void:
	var tilt_sequence: Array = _get_tilt_sequence_for_orientation(current_tile_orientation_18d)

	if tilt_sequence.is_empty():
		return

	var current_index: int = tilt_sequence.find(current_tile_orientation_18d)

	current_index = (current_index - 1) % tilt_sequence.size()
	if current_index < 0:
		current_index += tilt_sequence.size()
	current_tile_orientation_18d = tilt_sequence[current_index]

	print("cycle_tilt_backward: ", GlobalUtil.TileOrientation.keys()[current_tile_orientation_18d], " - ", current_plane_6d,  current_index)

	_debug_tilt_state()


static func reset_to_flat() -> void:
	var base_orientation: int = _get_base_orientation(current_tile_orientation_18d)
	if base_orientation != current_tile_orientation_18d:
		current_tile_orientation_18d = base_orientation



static func get_current_plane_3d() -> Vector3:
	return current_plane_3d


static func is_on_plane() -> bool:
	return is_cursor_on_plane


static func set_cursor_on_plane(on_plane: bool) -> void:
	if is_cursor_on_plane != on_plane:
		is_cursor_on_plane = on_plane
		print_cursor_plane_state(on_plane)


static func print_plane_change(old_plane: int, new_plane: int) -> void:
	var old_name: String = GlobalUtil.TileOrientation.keys()[old_plane]
	var new_name: String = GlobalUtil.TileOrientation.keys()[new_plane]
	print("Plane Changed: ", old_name, " → ", new_name)


static func print_cursor_plane_state(is_on: bool) -> void:
	pass



static func _get_tilt_sequence_for_orientation(orientation: int) -> Array:
	return GlobalUtil.get_tilt_sequence(orientation)


static func _get_base_orientation(orientation: int) -> int:
	return GlobalUtil.get_base_tile_orientation(orientation)


static func _debug_tilt_state() -> void:
	var orientation_name: String = GlobalUtil.TileOrientation.keys()[current_tile_orientation_18d]
	var plane_name: String = GlobalUtil.TileOrientation.keys()[current_plane_6d]
	var tilt_info: String = ""

	match current_tile_orientation_18d:
		GlobalUtil.TileOrientation.FLOOR_TILT_POS_X:
			tilt_info = " (X-axis +45° - ramp forward)"
		GlobalUtil.TileOrientation.FLOOR_TILT_NEG_X:
			tilt_info = " (X-axis -45° - ramp backward)"
		GlobalUtil.TileOrientation.CEILING_TILT_POS_X:
			tilt_info = " (X-axis +45°)"
		GlobalUtil.TileOrientation.CEILING_TILT_NEG_X:
			tilt_info = " (X-axis -45°)"
		GlobalUtil.TileOrientation.WALL_NORTH_TILT_POS_Y:
			tilt_info = " (Y-axis +45° - lean right)"
		GlobalUtil.TileOrientation.WALL_NORTH_TILT_NEG_Y:
			tilt_info = " (Y-axis -45° - lean left)"
		GlobalUtil.TileOrientation.WALL_SOUTH_TILT_POS_Y:
			tilt_info = " (Y-axis +45° - lean right)"
		GlobalUtil.TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			tilt_info = " (Y-axis -45° - lean left)"
		GlobalUtil.TileOrientation.WALL_EAST_TILT_POS_X:
			tilt_info = " (X-axis +45° - lean forward)"
		GlobalUtil.TileOrientation.WALL_EAST_TILT_NEG_X:
			tilt_info = " (X-axis -45° - lean backward)"
		GlobalUtil.TileOrientation.WALL_WEST_TILT_POS_X:
			tilt_info = " (X-axis +45° - lean forward)"
		GlobalUtil.TileOrientation.WALL_WEST_TILT_NEG_X:
			tilt_info = " (X-axis -45° - lean backward)"

	if current_tile_orientation_18d >= GlobalUtil.TileOrientation.FLOOR_TILT_POS_X:
		var scale_vec: Vector3 = GlobalUtil.get_scale_for_orientation(current_tile_orientation_18d)
		if scale_vec.x > 1.0:
			tilt_info += " [X-SCALED 141%]"
		elif scale_vec.z > 1.0:
			tilt_info += " [Z-SCALED 141%]"
			
		print("📐 ", "Current_plane_6d: " ,current_plane_6d , " / Current_tile_orientation_18d: " ,current_tile_orientation_18d ," / Oriet_name:  " , orientation_name, tilt_info)
