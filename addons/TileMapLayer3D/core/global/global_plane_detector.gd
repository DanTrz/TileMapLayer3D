class_name GlobalPlaneDetector
extends RefCounted

## Global singleton for plane/orientation detection and tilt state management
## Responsibility: Single Source of Truth for all plane detection and orientation state
##
## This centralizes ALL orientation and plane detection logic that was previously
## scattered across TilePlacementManager, Plugin, and other systems.
##
## Requirements:
## 1. Detect exact wall (EAST, WEST, NORTH, SOUTH, FLOOR, CEILING) - 6D detection
## 2. Detect when cursor is "on plane" vs "off plane"
## 3. Detect plane focus changes (switching from one plane to another)
##
## Usage:
##   # Query current state
##   var current_wall: int = GlobalPlaneDetector.get_current_orientation_6d()
##   var is_on_plane: bool = GlobalPlaneDetector.is_on_plane()
##
##   # Update state (called by plugin each frame)
##   GlobalPlaneDetector.update_from_camera(camera)
##
##   # Tilt management (R/T keys)
##   GlobalPlaneDetector.cycle_tilt_forward()
##   GlobalPlaneDetector.reset_to_flat()

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when auto-flip determines flip state should change
## @param flip_state: true = flipped (back face visible), false = normal (front face visible)
##
## Triggered when:
## - Plane changes AND auto-flip is enabled
## - User switches from NORTH/FLOOR/WEST to SOUTH/CEILING/EAST (or vice versa)
##
## Consumed by:
## - Plugin to update placement_manager.is_current_face_flipped
signal auto_flip_requested(flip_state: bool)

# ============================================================================
# STATE STORAGE (Single Source of Truth)
# ============================================================================

## Current detected orientation (18-state: 6 base + 12 tilted)
## This includes manual tilt state applied by R key
static var current_orientation_18d: int = GlobalUtil.TileOrientation.FLOOR

## Current detected base orientation (6-state: FLOOR, CEILING, WALL_*)
## This is the simplified orientation (no tilts)
static var current_orientation_6d: int = GlobalUtil.TileOrientation.FLOOR

## Previous base orientation (for change detection)
static var previous_orientation_6d: int = GlobalUtil.TileOrientation.FLOOR

## Whether cursor is currently on a plane (focused for placement)
static var is_cursor_on_plane: bool = false

## Last detected 3D plane normal (UP, RIGHT, or FORWARD)
static var current_plane_3d: Vector3 = Vector3.UP

# ============================================================================
# DETECTION METHODS (Stateless - Pure Functions)
# ============================================================================

## Determines which simplified 3 base plane is active based on camera viewing angle
## Returns Vector3: UP (floor/ceiling), RIGHT (east/west walls), FORWARD (north/south walls)
##
## This is used for:
## - Grid plane highlighting (CursorPlaneVisualizer)
## - Selective snapping (only snap axes parallel to plane)
## - Orientation detection
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
## Returns TileOrientation: CEILING, FLOOR, WALL_NORTH, WALL_SOUTH, WALL_EAST, or WALL_WEST
##
## This is the EXACT wall detection (Requirement #1)
## - Detects which of 6 walls/planes the camera is facing
## - Includes direction (not just axis)
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


## Determines tile orientation from cursor plane and camera angle (CURSOR_PLANE mode)
## Returns orientation that PRESERVES tilt state when user has manually tilted
## - Same plane (floor → floor): Preserve tilt (e.g., FLOOR_TILT_POS_X stays tilted)
## - Different plane (floor → wall): Reset tilt (e.g., FLOOR_TILT_POS_X → WALL_EAST)
## but manual tilt state (R key) persists until the user switches planes
static func detect_orientation_from_cursor_plane(plane_normal: Vector3, camera: Camera3D) -> int:
	# Step 1: Determine BASE orientation from plane normal
	var base_orientation: int

	if plane_normal == Vector3.UP:
		# XZ plane (horizontal) - FLOOR/CEILING base
		base_orientation = GlobalUtil.TileOrientation.FLOOR
	elif plane_normal == Vector3.RIGHT:
		# YZ plane (perpendicular to X-axis) - WALL_WEST base
		base_orientation = GlobalUtil.TileOrientation.WALL_WEST
	else: # Vector3.FORWARD
		# XY plane (perpendicular to Z-axis) - WALL_SOUTH base
		base_orientation = GlobalUtil.TileOrientation.WALL_SOUTH

	# Step 2: Check if user has manually tilted current_orientation_18d
	var current_base: int = _get_base_orientation(current_orientation_18d)

	# Step 3: Preserve tilt if still on same plane, reset if switching planes
	if current_base == base_orientation:
		# Same plane - preserve tilt state (e.g., FLOOR_TILT_POS_X stays tilted)
		return current_orientation_18d
	else:
		# Different plane - UPDATE current_orientation_18d and reset tilt
		current_orientation_18d = base_orientation  #   Update state so R key cycles correct tilt sequence
		return base_orientation


## Determines whether tile face should be flipped based on plane orientation
## Used by Auto-Flip feature to automatically orient tile faces toward camera
##
## @param orientation_6d: Base orientation (6D, no tilt)
## @return: true if face should be flipped, false for normal
static func determine_auto_flip_for_plane(orientation_6d: int) -> bool:
	match orientation_6d:
		GlobalUtil.TileOrientation.WALL_NORTH:
			return false  # Normal face
		GlobalUtil.TileOrientation.FLOOR:
			return false  # Normal face
		GlobalUtil.TileOrientation.WALL_WEST:
			return false  # Normal face
		GlobalUtil.TileOrientation.WALL_SOUTH:
			return true   # Flipped face
		GlobalUtil.TileOrientation.CEILING:
			return true   # Flipped face
		GlobalUtil.TileOrientation.WALL_EAST:
			return true   # Flipped face
		_:
			return false  # Default: normal face


## Determines whether tile face should be flipped during rotation operations
## Used during rotation operations to orient tile faces toward camera
##
## @param orientation_6d: Base orientation (6D, no tilt)
## @return: true if face should be flipped, false for normal
static func determine_rotation_flip_for_plane(orientation_6d: int) -> bool:
	match orientation_6d:
		GlobalUtil.TileOrientation.WALL_NORTH:
			return false  # Normal face
		GlobalUtil.TileOrientation.FLOOR:
			return false  # Normal face
		GlobalUtil.TileOrientation.WALL_WEST:
			return true  # Normal face
		GlobalUtil.TileOrientation.WALL_SOUTH:
			return true   # Flipped face
		GlobalUtil.TileOrientation.CEILING:
			return true   # Flipped face
		GlobalUtil.TileOrientation.WALL_EAST:
			return false   # Flipped face
		_:
			return false  # Default: normal face

# ============================================================================
# STATE UPDATE (Called by Plugin Each Frame)
# ============================================================================

## Updates all orientation state from camera and detects changes
## Call this from plugin's _update_preview() to keep state synchronized
##
## This method:
## - Updates current_orientation_6d (base plane)
## - Detects plane focus changes (Requirement #3)
## - Updates current_plane_3d for visualization
## - Triggers debug prints for testing
## - Emits auto_flip_requested signal on plane changes (for Auto-Flip feature)
##
## @param emitter: Node to emit signals from (pass plugin instance)
static func update_from_camera(camera: Camera3D, emitter: Node = null) -> void:
	if not camera:
		return

	# Store previous state for change detection
	previous_orientation_6d = current_orientation_6d

	# Detect current planes
	current_plane_3d = detect_active_plane_3d(camera)
	current_orientation_6d = detect_active_plane_6d(camera)

	# Detect plane focus changes (Requirement #3)
	if previous_orientation_6d != current_orientation_6d:
		print_plane_change(previous_orientation_6d, current_orientation_6d)

		# Reset to flat orientation on plane change (like T key)
		reset_to_flat()

		# Emit auto-flip signal for plugin to handle
		if emitter:
			var flip_state: bool = determine_auto_flip_for_plane(current_orientation_6d)
			emitter.emit_signal("auto_flip_requested", flip_state)


# ============================================================================
# TILT STATE MANAGEMENT (R/T Keys)
# ============================================================================

## Cycles forward through tilt states for current orientation (R key)
## Each base orientation has 3 states: flat → positive tilt → negative tilt → flat
static func cycle_tilt_forward() -> void:
	var tilt_sequence: Array = _get_tilt_sequence_for_orientation(current_orientation_18d)

	if tilt_sequence.is_empty():
		return

	# Find current position in sequence
	var current_index: int = tilt_sequence.find(current_orientation_18d)

	# Cycle to next state
	current_index = (current_index + 1) % tilt_sequence.size()
	current_orientation_18d = tilt_sequence[current_index]
	print("cycle_tilt_forward: ", get_orientation_name(current_orientation_18d), " - ", current_orientation_6d,  current_index)

	# Debug output with tilt info
	_debug_tilt_state()


## Cycles backward through tilt states (Shift+R key)
static func cycle_tilt_backward() -> void:
	var tilt_sequence: Array = _get_tilt_sequence_for_orientation(current_orientation_18d)

	if tilt_sequence.is_empty():
		return

	# Find current position in sequence
	var current_index: int = tilt_sequence.find(current_orientation_18d)

	# Cycle to previous state
	current_index = (current_index - 1) % tilt_sequence.size()
	if current_index < 0:
		current_index += tilt_sequence.size()
	current_orientation_18d = tilt_sequence[current_index]

	print("cycle_tilt_backward: ", get_orientation_name(current_orientation_18d), " - ", current_orientation_6d,  current_index)

	# Debug output
	_debug_tilt_state()


## Resets current orientation to its base (flat) state (T key)
static func reset_to_flat() -> void:
	var base_orientation: int = _get_base_orientation(current_orientation_18d)
	if base_orientation != current_orientation_18d:
		current_orientation_18d = base_orientation


# ============================================================================
# QUERY METHODS (Global Access)
# ============================================================================

## Returns current 18-state orientation (includes tilt)
static func get_current_orientation_18d() -> int:
	return current_orientation_18d


## Returns current 6-state base orientation (no tilt)
static func get_current_orientation_6d() -> int:
	return current_orientation_6d


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


## Returns human-readable name for any orientation
static func get_orientation_name(orientation: int) -> String:
	match orientation:
		GlobalUtil.TileOrientation.FLOOR: return "FLOOR"
		GlobalUtil.TileOrientation.CEILING: return "CEILING"
		GlobalUtil.TileOrientation.WALL_NORTH: return "WALL_NORTH"
		GlobalUtil.TileOrientation.WALL_SOUTH: return "WALL_SOUTH"
		GlobalUtil.TileOrientation.WALL_EAST: return "WALL_EAST"
		GlobalUtil.TileOrientation.WALL_WEST: return "WALL_WEST"
		GlobalUtil.TileOrientation.FLOOR_TILT_POS_X: return "FLOOR_TILT_POS_X"
		GlobalUtil.TileOrientation.FLOOR_TILT_NEG_X: return "FLOOR_TILT_NEG_X"
		GlobalUtil.TileOrientation.CEILING_TILT_POS_X: return "CEILING_TILT_POS_X"
		GlobalUtil.TileOrientation.CEILING_TILT_NEG_X: return "CEILING_TILT_NEG_X"
		GlobalUtil.TileOrientation.WALL_NORTH_TILT_POS_Y: return "WALL_NORTH_TILT_POS_Y"
		GlobalUtil.TileOrientation.WALL_NORTH_TILT_NEG_Y: return "WALL_NORTH_TILT_NEG_Y"
		GlobalUtil.TileOrientation.WALL_SOUTH_TILT_POS_Y: return "WALL_SOUTH_TILT_POS_Y"
		GlobalUtil.TileOrientation.WALL_SOUTH_TILT_NEG_Y: return "WALL_SOUTH_TILT_NEG_Y"
		GlobalUtil.TileOrientation.WALL_EAST_TILT_POS_X: return "WALL_EAST_TILT_POS_X"
		GlobalUtil.TileOrientation.WALL_EAST_TILT_NEG_X: return "WALL_EAST_TILT_NEG_X"
		GlobalUtil.TileOrientation.WALL_WEST_TILT_POS_X: return "WALL_WEST_TILT_POS_X"
		GlobalUtil.TileOrientation.WALL_WEST_TILT_NEG_X: return "WALL_WEST_TILT_NEG_X"
		_: return "UNKNOWN"


## Returns human-readable plane name (6D only)
static func get_plane_name(orientation: int) -> String:
	match orientation:
		GlobalUtil.TileOrientation.FLOOR: return "FLOOR"
		GlobalUtil.TileOrientation.CEILING: return "CEILING"
		GlobalUtil.TileOrientation.WALL_NORTH: return "WALL_NORTH"
		GlobalUtil.TileOrientation.WALL_SOUTH: return "WALL_SOUTH"
		GlobalUtil.TileOrientation.WALL_EAST: return "WALL_EAST"
		GlobalUtil.TileOrientation.WALL_WEST: return "WALL_WEST"
		_: return "UNKNOWN"


## Requirement #1: Print exact wall detection (6D)
## Prints current wall every time camera angle changes
static func print_current_wall() -> void:
	var wall_name: String = get_plane_name(current_orientation_6d)
	#print("Current Wall: ", wall_name, " (6D: ", current_orientation_6d, ", 18D: ", current_orientation_18d, ")")


## Requirement #3: Print plane focus changes
## Prints when switching from one wall/plane to another
static func print_plane_change(old_plane: int, new_plane: int) -> void:
	var old_name: String = get_plane_name(old_plane)
	var new_name: String = get_plane_name(new_plane)
	print("Plane Changed: ", old_name, " → ", new_name)


## Requirement #2: Print cursor on/off plane state
## Prints when cursor enters or exits a plane
static func print_cursor_plane_state(is_on: bool) -> void:
	#if is_on:
	#	print("Cursor On Plane: TRUE (focused for placement)")
	#else:
	#	print("Cursor On Plane: FALSE (off plane)")
	pass


# ============================================================================
# PRIVATE HELPERS
# ============================================================================

## Returns the 3-state tilt sequence for any orientation (flat, positive, negative)
static func _get_tilt_sequence_for_orientation(orientation: int) -> Array:
	match orientation:
		# Floor group
		GlobalUtil.TileOrientation.FLOOR, \
		GlobalUtil.TileOrientation.FLOOR_TILT_POS_X, \
		GlobalUtil.TileOrientation.FLOOR_TILT_NEG_X:
			return [
				GlobalUtil.TileOrientation.FLOOR,           # Flat
				GlobalUtil.TileOrientation.FLOOR_TILT_POS_X, # Forward tilt (+45° on X)
				GlobalUtil.TileOrientation.FLOOR_TILT_NEG_X  # Backward tilt (-45° on X)
			]

		# Ceiling group
		GlobalUtil.TileOrientation.CEILING, \
		GlobalUtil.TileOrientation.CEILING_TILT_POS_X, \
		GlobalUtil.TileOrientation.CEILING_TILT_NEG_X:
			return [
				GlobalUtil.TileOrientation.CEILING,
				GlobalUtil.TileOrientation.CEILING_TILT_POS_X,
				GlobalUtil.TileOrientation.CEILING_TILT_NEG_X
			]

		# North wall group
		GlobalUtil.TileOrientation.WALL_NORTH, \
		GlobalUtil.TileOrientation.WALL_NORTH_TILT_POS_Y, \
		GlobalUtil.TileOrientation.WALL_NORTH_TILT_NEG_Y:
			return [
				GlobalUtil.TileOrientation.WALL_NORTH,
				GlobalUtil.TileOrientation.WALL_NORTH_TILT_POS_Y,  # Lean right (+45° on Y)
				GlobalUtil.TileOrientation.WALL_NORTH_TILT_NEG_Y   # Lean left (-45° on Y)
			]

		# South wall group
		GlobalUtil.TileOrientation.WALL_SOUTH, \
		GlobalUtil.TileOrientation.WALL_SOUTH_TILT_POS_Y, \
		GlobalUtil.TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			return [
				GlobalUtil.TileOrientation.WALL_SOUTH,
				GlobalUtil.TileOrientation.WALL_SOUTH_TILT_POS_Y,
				GlobalUtil.TileOrientation.WALL_SOUTH_TILT_NEG_Y
			]

		# East wall group
		GlobalUtil.TileOrientation.WALL_EAST, \
		GlobalUtil.TileOrientation.WALL_EAST_TILT_POS_X, \
		GlobalUtil.TileOrientation.WALL_EAST_TILT_NEG_X:
			return [
				GlobalUtil.TileOrientation.WALL_EAST,
				GlobalUtil.TileOrientation.WALL_EAST_TILT_POS_X,  # Lean forward (+45° on X)
				GlobalUtil.TileOrientation.WALL_EAST_TILT_NEG_X   # Lean backward (-45° on X)
			]

		# West wall group
		GlobalUtil.TileOrientation.WALL_WEST, \
		GlobalUtil.TileOrientation.WALL_WEST_TILT_POS_X, \
		GlobalUtil.TileOrientation.WALL_WEST_TILT_NEG_X:
			return [
				GlobalUtil.TileOrientation.WALL_WEST,
				GlobalUtil.TileOrientation.WALL_WEST_TILT_POS_X,
				GlobalUtil.TileOrientation.WALL_WEST_TILT_NEG_X
			]

		_:
			return []


## Maps any tilted orientation back to its base (flat) orientation
static func _get_base_orientation(orientation: int) -> int:
	match orientation:
		GlobalUtil.TileOrientation.FLOOR, \
		GlobalUtil.TileOrientation.FLOOR_TILT_POS_X, \
		GlobalUtil.TileOrientation.FLOOR_TILT_NEG_X:
			return GlobalUtil.TileOrientation.FLOOR

		GlobalUtil.TileOrientation.CEILING, \
		GlobalUtil.TileOrientation.CEILING_TILT_POS_X, \
		GlobalUtil.TileOrientation.CEILING_TILT_NEG_X:
			return GlobalUtil.TileOrientation.CEILING

		GlobalUtil.TileOrientation.WALL_NORTH, \
		GlobalUtil.TileOrientation.WALL_NORTH_TILT_POS_Y, \
		GlobalUtil.TileOrientation.WALL_NORTH_TILT_NEG_Y:
			return GlobalUtil.TileOrientation.WALL_NORTH

		GlobalUtil.TileOrientation.WALL_SOUTH, \
		GlobalUtil.TileOrientation.WALL_SOUTH_TILT_POS_Y, \
		GlobalUtil.TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			return GlobalUtil.TileOrientation.WALL_SOUTH

		GlobalUtil.TileOrientation.WALL_EAST, \
		GlobalUtil.TileOrientation.WALL_EAST_TILT_POS_X, \
		GlobalUtil.TileOrientation.WALL_EAST_TILT_NEG_X:
			return GlobalUtil.TileOrientation.WALL_EAST

		GlobalUtil.TileOrientation.WALL_WEST, \
		GlobalUtil.TileOrientation.WALL_WEST_TILT_POS_X, \
		GlobalUtil.TileOrientation.WALL_WEST_TILT_NEG_X:
			return GlobalUtil.TileOrientation.WALL_WEST

		_:
			return orientation


## Debug output for tilt state changes
static func _debug_tilt_state() -> void:
	var orientation_name: String = get_orientation_name(current_orientation_18d)
	var plane_name: String = get_plane_name(current_orientation_6d)
	var tilt_info: String = ""

	# Add tilt axis and direction info
	match current_orientation_18d:
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
	if current_orientation_18d >= GlobalUtil.TileOrientation.FLOOR_TILT_POS_X:
		var scale_vec: Vector3 = GlobalUtil.get_scale_for_orientation(current_orientation_18d)
		if scale_vec.x > 1.0:
			tilt_info += " [X-SCALED 141%]"
		elif scale_vec.z > 1.0:
			tilt_info += " [Z-SCALED 141%]"
			
		print("📐 ", "current_orientation_6d: " , plane_name, " - current_orientation_18d: ", orientation_name, tilt_info)  # R/T key feedback
