class_name GlobalPlaneDetector
extends RefCounted

## Global singleton for plane/orientation detection and tilt state management

# --- Signals ---

## Emitted when auto-flip determines flip state should change on plane change
signal auto_flip_requested(flip_state: bool)

# --- State Storage ---

## Current detected tile orientation (18-state: 6 base + 12 tilted)
## This includes manual tilt state applied by R key
static var current_tile_orientation_18d: int = GlobalUtil.TileOrientation.FLOOR

## Current detected plane base orientation (6-state: FLOOR, CEILING, WALL_*)
## This is the simplified plane orientation 
static var current_plane_6d: int = GlobalUtil.TileOrientation.FLOOR

## Previous base orientation (for change detection)
static var previous_plane_6d: int = GlobalUtil.TileOrientation.FLOOR

## Whether cursor is currently on a plane (focused for placement)
static var is_cursor_on_plane: bool = false

## Last detected 3D plane normal (UP, RIGHT, or FORWARD)
static var current_plane_3d: Vector3 = Vector3.UP

# --- Detection Methods ---

## Determines which simplified 3 base plane is active based on camera viewing angle
static func detect_active_plane_3d(camera: Camera3D) -> Vector3:
	# 1. Get the camera's forward vector (-Z axis because Godot conventions)
	var camera_forward: Vector3 = -camera.global_transform.basis.z

	# 2. Find the axis the camera forward vector is most aligned with (the dominant axis).
	var abs_x: float = abs(camera_forward.x)
	var abs_y: float = abs(camera_forward.y)
	var abs_z: float = abs(camera_forward.z)

	# 3. Determine the dominant axis and return the corresponding plane normal
	# Check for the Y-axis (Up/Down)
	if abs_y > abs_x and abs_y > abs_z:
		return Vector3.UP       # XZ plane (horizontal) - looking up/down
	elif abs_x > abs_z:
		return Vector3.RIGHT    # YZ plane - looking left/right
	else:
		return Vector3.FORWARD  # XY plane - looking forward/back


## Determines which one of 6 base planes is active based on camera viewing angle
static func detect_active_plane_6d(camera: Camera3D) -> int:
	# 1. Get the camera's forward vector (-Z axis because Godot conventions)
	var camera_forward: Vector3 = -camera.global_transform.basis.z

	# 2. Find the axis the camera forward vector is most aligned with (the dominant axis).
	var abs_x: float = abs(camera_forward.x)
	var abs_y: float = abs(camera_forward.y)
	var abs_z: float = abs(camera_forward.z)

	# 3. Determine the dominant axis and return the corresponding 6D orientation
	if abs_y > abs_x and abs_y > abs_z:
		if camera_forward.y > 0:
			return GlobalUtil.TileOrientation.CEILING  # +Y: Looking Up
		else:
			return GlobalUtil.TileOrientation.FLOOR    # -Y: Looking Down

	# Check for the X-axis (Right/Left)
	elif abs_x > abs_y and abs_x > abs_z:
		if camera_forward.x > 0:
			return GlobalUtil.TileOrientation.WALL_EAST  # +X: Looking Right
		else:
			return GlobalUtil.TileOrientation.WALL_WEST  # -X: Looking Left

	# The Z-axis is the only one remaining (Forward/Back)
	else: # abs_z is the dominant component
		if camera_forward.z > 0:
			return GlobalUtil.TileOrientation.WALL_SOUTH  # +Z: Looking South (Back)
		else:
			return GlobalUtil.TileOrientation.WALL_NORTH  # -Z: Looking North (Forward)


## Determines tile orientation from cursor plane and camera angle
## Preserves tilt state on same plane, resets tilt when switching planes.
static func detect_orientation_from_cursor_plane(plane_normal: Vector3, camera: Camera3D) -> int:
	# Step 1: Use 6D detection to get exact plane (not 3-plane approximation)
	var base_orientation_6d: int = detect_active_plane_6d(camera)

	# Step 2: Check if user has manually tilted current_tile_orientation_18d
	var current_base: int = _get_base_orientation(current_tile_orientation_18d)

	# Step 3: Preserve tilt if still on same base plane, reset if switching planes
	if current_base == base_orientation_6d:
		# Same plane - preserve tilt state (e.g., FLOOR_TILT_POS_X stays tilted)
		return current_tile_orientation_18d
	else:
		# Different plane - UPDATE current_tile_orientation_18d and reset tilt
		current_tile_orientation_18d = base_orientation_6d
		return base_orientation_6d


## Determines whether tile face should be flipped based on plane orientation
static func determine_auto_flip_for_plane(orientation_6d: int) -> bool:
	match orientation_6d:
		GlobalUtil.TileOrientation.FLOOR:
			return false  # Looking down at floor - normal orientation
		GlobalUtil.TileOrientation.CEILING:
			return false  # Looking up at ceiling - basis handles flip via 180° rotation
		GlobalUtil.TileOrientation.WALL_NORTH:
			return false  # Looking north - normal orientation
		GlobalUtil.TileOrientation.WALL_SOUTH:
			return false   # Looking south - need horizontal mirror
		GlobalUtil.TileOrientation.WALL_EAST:
			return false  # Looking east - normal orientation
		GlobalUtil.TileOrientation.WALL_WEST:
			return false   # Looking west - need horizontal mirror
		_:
			return false  # Default: normal face


## Determines whether tile face should be flipped during rotation operations
static func determine_rotation_flip_for_plane(orientation_6d: int) -> bool:
	match orientation_6d:
		GlobalUtil.TileOrientation.FLOOR:
			return false
		GlobalUtil.TileOrientation.CEILING:
			return true   # Rotation on ceiling needs flip
		GlobalUtil.TileOrientation.WALL_NORTH:
			return false
		GlobalUtil.TileOrientation.WALL_SOUTH:
			return false
		GlobalUtil.TileOrientation.WALL_EAST:
			return false
		GlobalUtil.TileOrientation.WALL_WEST:
			return false
		_:
			return false  # Default: normal face

# --- State Update ---

## Updates all orientation state from camera and detects plane changes
static func update_from_camera(camera: Camera3D, emitter: Node = null) -> void:
	if not camera:
		return

	# Store previous state for change detection
	previous_plane_6d = current_plane_6d

	# Detect current planes
	current_plane_3d = detect_active_plane_3d(camera)
	current_plane_6d = detect_active_plane_6d(camera)

	# Detect plane focus changes (Requirement #3)
	if previous_plane_6d != current_plane_6d:
		print_plane_change(previous_plane_6d, current_plane_6d)

		# Reset to flat orientation on plane change (like T key)
		reset_to_flat()

		# Emit auto-flip signal for plugin to handle
		if emitter:
			var flip_state: bool = determine_auto_flip_for_plane(current_plane_6d)
			emitter.emit_signal("auto_flip_requested", flip_state)


# --- Tilt State Management ---

## Cycles forward through tilt states for current orientation (R key)
## Each base orientation has 3 states: flat → positive tilt → negative tilt → flat
static func cycle_tilt_forward() -> void:
	var tilt_sequence: Array = _get_tilt_sequence_for_orientation(current_tile_orientation_18d)

	if tilt_sequence.is_empty():
		return

	# Find current position in sequence
	var current_index: int = tilt_sequence.find(current_tile_orientation_18d)

	# Cycle to next state
	current_index = (current_index + 1) % tilt_sequence.size()
	current_tile_orientation_18d = tilt_sequence[current_index]

	print("cycle_tilt_forward: ", GlobalUtil.TileOrientation.keys()[current_tile_orientation_18d], " - ", current_plane_6d,  current_index)

	# Debug output with tilt info
	_debug_tilt_state()


## Cycles backward through tilt states (Shift+R key)
static func cycle_tilt_backward() -> void:
	var tilt_sequence: Array = _get_tilt_sequence_for_orientation(current_tile_orientation_18d)

	if tilt_sequence.is_empty():
		return

	# Find current position in sequence
	var current_index: int = tilt_sequence.find(current_tile_orientation_18d)

	# Cycle to previous state
	current_index = (current_index - 1) % tilt_sequence.size()
	if current_index < 0:
		current_index += tilt_sequence.size()
	current_tile_orientation_18d = tilt_sequence[current_index]

	print("cycle_tilt_backward: ", GlobalUtil.TileOrientation.keys()[current_tile_orientation_18d], " - ", current_plane_6d,  current_index)

	# Debug output
	_debug_tilt_state()


## Resets current orientation to its base (flat) state (T key)
static func reset_to_flat() -> void:
	var base_orientation: int = _get_base_orientation(current_tile_orientation_18d)
	if base_orientation != current_tile_orientation_18d:
		current_tile_orientation_18d = base_orientation


# --- Query Methods ---

## Returns current 3D plane normal (UP, RIGHT, or FORWARD)
static func get_current_plane_3d() -> Vector3:
	return current_plane_3d


## Returns whether cursor is currently on a plane (Requirement #2)
## Note: This will be set by the plugin based on raycast success
static func is_on_plane() -> bool:
	return is_cursor_on_plane


## Sets cursor on-plane state (called by plugin after raycast)
static func set_cursor_on_plane(on_plane: bool) -> void:
	if is_cursor_on_plane != on_plane:
		is_cursor_on_plane = on_plane
		print_cursor_plane_state(on_plane)

## Prints current wall every time camera angle changes
static func print_current_wall() -> void:
	var wall_name: String = GlobalUtil.TileOrientation.keys()[current_plane_6d]
	#print("Current Wall: ", wall_name, " (6D: ", current_plane_6d, ", 18D: ", current_tile_orientation_18d, ")")



## Prints when switching from one wall/plane to another
static func print_plane_change(old_plane: int, new_plane: int) -> void:
	var old_name: String = GlobalUtil.TileOrientation.keys()[old_plane]
	var new_name: String = GlobalUtil.TileOrientation.keys()[new_plane]
	# print("Plane Changed: ", old_name, " → ", new_name)


## Prints when cursor enters or exits a plane
static func print_cursor_plane_state(is_on: bool) -> void:
	#if is_on:
	#	print("Cursor On Plane: TRUE (focused for placement)")
	#else:
	#	print("Cursor On Plane: FALSE (off plane)")
	pass


# --- Private Helpers ---

## Returns the 3-state tilt sequence for any orientation (flat, positive, negative)
## Now delegates to GlobalUtil.get_tilt_sequence() which uses TILT_SEQUENCES lookup
static func _get_tilt_sequence_for_orientation(orientation: int) -> Array:
	return GlobalUtil.get_tilt_sequence(orientation)


## Maps any tilted orientation back to its base (flat) orientation
## Now delegates to GlobalUtil.get_base_orientation() which uses ORIENTATION_DATA lookup
static func _get_base_orientation(orientation: int) -> int:
	return GlobalUtil.get_base_tile_orientation(orientation)


## Debug output for tilt state changes
static func _debug_tilt_state() -> void:
	var orientation_name: String = GlobalUtil.TileOrientation.keys()[current_tile_orientation_18d]
	var plane_name: String = GlobalUtil.TileOrientation.keys()[current_plane_6d]
	var tilt_info: String = ""

	# Add tilt axis and direction info
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

	# Show scaling info for tilted states (non-uniform scaling by axis)
	if current_tile_orientation_18d >= GlobalUtil.TileOrientation.FLOOR_TILT_POS_X:
		var scale_vec: Vector3 = GlobalUtil.get_scale_for_orientation(current_tile_orientation_18d)
		if scale_vec.x > 1.0:
			tilt_info += " [X-SCALED 141%]"
		elif scale_vec.z > 1.0:
			tilt_info += " [Z-SCALED 141%]"
			
		print("📐 ", "Current_plane_6d: " ,current_plane_6d , " / Current_tile_orientation_18d: " ,current_tile_orientation_18d ," / Oriet_name:  " , orientation_name, tilt_info)  # R/T key feedback
