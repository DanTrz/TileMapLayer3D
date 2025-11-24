extends RefCounted
class_name GlobalUtil

## ============================================================================
## GLOBAL UTILITY METHODS 
## ============================================================================
## This file centralizes all shared utility methods, material creation, and
## common processing functions used throughout the Plugin

# ==============================================================================
# MATERIAL CREATION (Single Source of Truth)
# ==============================================================================

# Cache shader resource for performance
static var _cached_shader: Shader = null

## Creates a ShaderMaterial for tile rendering
## This is the ONLY place where tile materials should be created.
##
## @param texture: The tileset texture to apply
## @param filter_mode: Texture filter mode (0-3)
##   0 = Nearest (pixel-perfect, default)
##   1 = Nearest Mipmap
##   2 = Linear (smooth)
##   3 = Linear Mipmap
## @returns: ShaderMaterial configured for tile rendering
static func create_tile_material(texture: Texture2D, filter_mode: int = 0, render_priority: int = 0) -> ShaderMaterial:
	# Cache shader resource for performance
	if not _cached_shader:
		_cached_shader = load("uid://huf0b1u2f55e")

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _cached_shader
	material.render_priority = render_priority

	# Set texture parameters for both samplers (nearest and linear)
	if texture:
		material.set_shader_parameter("albedo_texture_nearest", texture)
		material.set_shader_parameter("albedo_texture_linear", texture)

		# Set the boolean to choose which sampler to use
		# For now: 0-1 = Nearest, 2-3 = Linear
		var use_nearest: bool = (filter_mode == 0 or filter_mode == 1)
		material.set_shader_parameter("use_nearest_texture", use_nearest)

	return material


static func set_shader_render_priority(render_priority: int = 0) -> void:
	# Cache shader resource for performance
	if not _cached_shader:
		_cached_shader = load("uid://huf0b1u2f55e")
	
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _cached_shader
	material.render_priority = render_priority
	

# ==============================================================================
# ORIENTATION & TRANSFORM UTILITIES
# ==============================================================================

## Tile orientation enum (should match TilePlacementManager.TileOrientation)
## 18-state system: 6 base + 12 tilted variants for ramps, roofs, and slanted walls
enum TileOrientation {
	# === BASE ORIENTATIONS ===
	FLOOR = 0,
	CEILING = 1,
	WALL_NORTH = 2,
	WALL_SOUTH = 3,
	WALL_EAST = 4,
	WALL_WEST = 5,

	# === TILTED VARIANTS (45° rotations) ===
	# Floor/Ceiling tilts on X-axis
	FLOOR_TILT_POS_X = 6,
	FLOOR_TILT_NEG_X = 7,
	CEILING_TILT_POS_X = 8,
	CEILING_TILT_NEG_X = 9,

	# North/South walls tilt on Y-axis
	WALL_NORTH_TILT_POS_Y = 10,
	WALL_NORTH_TILT_NEG_Y = 11,
	WALL_SOUTH_TILT_POS_Y = 12,
	WALL_SOUTH_TILT_NEG_Y = 13,

	# East/West walls tilt on X-axis
	WALL_EAST_TILT_POS_X = 14,
	WALL_EAST_TILT_NEG_X = 15,
	WALL_WEST_TILT_POS_X = 16,
	WALL_WEST_TILT_NEG_X = 17
}

## Converts orientation enum to rotation basis
## This defines how each tile orientation is rotated in 3D space.
##
## @param orientation: TileOrientation enum value
## @returns: Basis representing the orientation rotation
static func get_orientation_basis(orientation: int) -> Basis:
	match orientation:
		TileOrientation.FLOOR:
			# Default: horizontal quad facing up (no rotation)
			return Basis.IDENTITY

		TileOrientation.CEILING:
			# Flip upside down (180° around X axis)
			return Basis(Vector3(1, 0, 0), PI)

		TileOrientation.WALL_NORTH:
			# Rotate 90° forward (around X axis) to face south (Z+)
			return Basis(Vector3(1, 0, 0), -PI / 2.0)

		TileOrientation.WALL_SOUTH:
			# Rotate 90° backward (around X axis) to face north (Z-)
			return Basis(Vector3(1, 0, 0), PI / 2.0)

		TileOrientation.WALL_EAST:
			# Rotate 90° right (around Z axis) to face west (X-)
			return Basis(Vector3(0, 0, 1), PI / 2.0)

		TileOrientation.WALL_WEST:
			# Rotate to face east (X+) with texture upright
			# Keep rot_x * rot_z order (plane aligned), try different angles
			var rot_z: Basis = Basis(Vector3(0, 0, 1), -PI / 2.0)  # Stand up on YZ plane
			var rot_x: Basis = Basis(Vector3(1, 0, 0), PI / 2.0)   # Try 90° instead of 180°
			return rot_x * rot_z

		# === FLOOR/CEILING TILTS (X-axis rotation for forward/backward ramps) ===
		TileOrientation.FLOOR_TILT_POS_X:
			# Floor tilted forward (ramp up toward +Z)
			# Rotate on X-axis (red axis) by +45°
			return Basis(Vector3.RIGHT, GlobalConstants.TILT_ANGLE_RAD)

		TileOrientation.FLOOR_TILT_NEG_X:
			# Floor tilted backward (ramp down toward -Z)
			# Rotate on X-axis by -45°
			return Basis(Vector3.RIGHT, -GlobalConstants.TILT_ANGLE_RAD)

		TileOrientation.CEILING_TILT_POS_X:
			# Ceiling tilted forward (inverted ramp)
			# First flip ceiling (180° on X), then apply +45° tilt
			var ceiling_base: Basis = Basis(Vector3.RIGHT, PI)
			var tilt: Basis = Basis(Vector3.RIGHT, GlobalConstants.TILT_ANGLE_RAD)
			return ceiling_base * tilt  # Apply tilt AFTER flip

		TileOrientation.CEILING_TILT_NEG_X:
			# Ceiling tilted backward
			var ceiling_base: Basis = Basis(Vector3.RIGHT, PI)
			var tilt: Basis = Basis(Vector3.RIGHT, -GlobalConstants.TILT_ANGLE_RAD)
			return ceiling_base * tilt

		# === NORTH/SOUTH WALL TILTS (Y-axis rotation for left/right lean) ===
		TileOrientation.WALL_NORTH_TILT_POS_Y:
			# North wall leaning right (toward +X)
			# First make vertical (north wall), then lean on Y-axis
			var wall_base: Basis = Basis(Vector3.RIGHT, -PI / 2.0)
			var tilt: Basis = Basis(Vector3.UP, GlobalConstants.TILT_ANGLE_RAD)
			return tilt * wall_base  # Apply wall rotation first, then tilt

		TileOrientation.WALL_NORTH_TILT_NEG_Y:
			# North wall leaning left (toward -X)
			var wall_base: Basis = Basis(Vector3.RIGHT, -PI / 2.0)
			var tilt: Basis = Basis(Vector3.UP, -GlobalConstants.TILT_ANGLE_RAD)
			return tilt * wall_base

		TileOrientation.WALL_SOUTH_TILT_POS_Y:
			# South wall leaning right (toward +X)
			var wall_base: Basis = Basis(Vector3.RIGHT, PI / 2.0)
			var tilt: Basis = Basis(Vector3.UP, GlobalConstants.TILT_ANGLE_RAD)
			return tilt * wall_base

		TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			# South wall leaning left (toward -X)
			var wall_base: Basis = Basis(Vector3.RIGHT, PI / 2.0)
			var tilt: Basis = Basis(Vector3.UP, -GlobalConstants.TILT_ANGLE_RAD)
			return tilt * wall_base

		# === EAST/WEST WALL TILTS (X-axis rotation for forward/backward lean) ===
		TileOrientation.WALL_EAST_TILT_POS_X:
			# East wall leaning forward (toward +Z)
			# First make vertical (east wall), then lean on X-axis
			var wall_base: Basis = Basis(Vector3.FORWARD, PI / 2.0)
			var tilt: Basis = Basis(Vector3.RIGHT, GlobalConstants.TILT_ANGLE_RAD)
			return wall_base * tilt  # Apply tilt AFTER wall rotation

		TileOrientation.WALL_EAST_TILT_NEG_X:
			# East wall leaning backward (toward -Z)
			var wall_base: Basis = Basis(Vector3.FORWARD, PI / 2.0)
			var tilt: Basis = Basis(Vector3.RIGHT, -GlobalConstants.TILT_ANGLE_RAD)
			return wall_base * tilt

		TileOrientation.WALL_WEST_TILT_POS_X:
			# West wall leaning forward (toward +Z)
			var rot_z: Basis = Basis(Vector3.FORWARD, -PI / 2.0)
			var rot_x: Basis = Basis(Vector3.RIGHT, PI / 2.0)
			var wall_base: Basis = rot_x * rot_z
			var tilt: Basis = Basis(Vector3.RIGHT, GlobalConstants.TILT_ANGLE_RAD)
			return wall_base * tilt

		TileOrientation.WALL_WEST_TILT_NEG_X:
			# West wall leaning backward (toward -Z)
			var rot_z: Basis = Basis(Vector3.FORWARD, -PI / 2.0)
			var rot_x: Basis = Basis(Vector3.RIGHT, PI / 2.0)
			var wall_base: Basis = rot_x * rot_z
			var tilt: Basis = Basis(Vector3.RIGHT, -GlobalConstants.TILT_ANGLE_RAD)
			return wall_base * tilt

		_:
			push_warning("Invalid orientation basis for rotation: ", orientation)
			return Basis.IDENTITY

## Helper to get the closest world cardinal vector (+/-X, +/-Y, +/-Z)
## from a camera's local direction vector.
## Returns a pure cardinal direction (e.g., Vector3(1, 0, 0), Vector3(0, -1, 0))
static func _get_snapped_cardinal_vector(direction_vector: Vector3) -> Vector3:
	# Find the dominant axis (largest absolute component)
	var abs_x: float = abs(direction_vector.x)
	var abs_y: float = abs(direction_vector.y)
	var abs_z: float = abs(direction_vector.z)

	# Return pure cardinal direction based on dominant axis
	if abs_x > abs_y and abs_x > abs_z:
		# X-axis is dominant
		return Vector3(sign(direction_vector.x), 0, 0)
	elif abs_y > abs_z:
		# Y-axis is dominant
		return Vector3(0, sign(direction_vector.y), 0)
	else:
		# Z-axis is dominant
		return Vector3(0, 0, sign(direction_vector.z))

## Returns non-uniform scale vector based on orientation
##  for eliminating gaps in 45° rotations
##
## Scaling Logic by Plane:
##   GREEN PLANE (Floor/Ceiling) → Rotate on X-axis → Scale Z (depth) by √2
##   BLUE PLANE (Wall N/S) → Rotate on Y-axis → Scale X (width) by √2
##   RED PLANE (Wall E/W) → Rotate on X-axis → Scale Z (depth) by √2
##
## Why Non-Uniform?
##   When a 1×1 tile rotates 45°, its diagonal (√2) projects onto the grid.
##   Scaling the perpendicular axis by √2 compensates for this projection.
##
## Example: Floor tile rotating forward (+45° on X-axis)
##   - Original: 1.0 width (X), 1.0 depth (Z)
##   - After 45° rotation: Width unchanged, depth projects as √2
##   - Solution: Scale Z by √2 BEFORE rotation → depth becomes 1.414
##   - Result: After rotation, projected depth = 1.414 × cos(45°) ≈ 1.0 
##
## @param orientation: TileOrientation enum value
## @returns: Vector3 scale (1.0 for unscaled axes, 1.414 for scaled axis)
static func get_scale_for_orientation(orientation: int) -> Vector3:
	match orientation:
		# Floor/Ceiling: Scale Z (depth) by √2
		TileOrientation.FLOOR_TILT_POS_X, \
		TileOrientation.FLOOR_TILT_NEG_X, \
		TileOrientation.CEILING_TILT_POS_X, \
		TileOrientation.CEILING_TILT_NEG_X:
			return Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR)

		# North/South walls: Scale X (width) by √2
		TileOrientation.WALL_NORTH_TILT_POS_Y, \
		TileOrientation.WALL_NORTH_TILT_NEG_Y, \
		TileOrientation.WALL_SOUTH_TILT_POS_Y, \
		TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			return Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0)

		# East/West walls: Scale Z (depth) by √2
		TileOrientation.WALL_EAST_TILT_POS_X, \
		TileOrientation.WALL_EAST_TILT_NEG_X, \
		TileOrientation.WALL_WEST_TILT_POS_X, \
		TileOrientation.WALL_WEST_TILT_NEG_X:
			return Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR)

		_:
			return Vector3.ONE  # No scaling for flat orientations (0-5)


## Returns the position offset to apply for tilted orientations
## Based on which axis/plane the tilt occurs on
##
## @param orientation: The tile orientation (0-17)
## @param tile_model: Reference to TileMapLayer3D node containing offset values
## @return Vector3: The offset to add to tile position (Vector3.ZERO if not tilted or no model)
static func get_tilt_offset_for_orientation(orientation: int, tilemap_node: TileMapLayer3D) -> Vector3:
	if not tilemap_node or orientation < TileOrientation.FLOOR_TILT_POS_X:
		return Vector3.ZERO  # No offset for flat tiles (0-5) or missing model

	#Offset the position by half size of the grid cell (due to scaling factor of 45 degrees rotation for tilted tiles)
	var offset_value: float = tilemap_node.settings.grid_size * GlobalConstants.TILT_POSITION_OFFSET_FACTOR

	match orientation:
		# Y-AXIS TILTS (Floor/Ceiling - GREEN plane)
		# Tilted on X-axis, so use Y-axis offset
		TileOrientation.FLOOR_TILT_POS_X, \
		TileOrientation.FLOOR_TILT_NEG_X, \
		TileOrientation.CEILING_TILT_POS_X, \
		TileOrientation.CEILING_TILT_NEG_X:
			# return tile_map_node.yAxis_tilt_offset
			return Vector3(0,offset_value,0)

		# Z-AXIS TILTS (North/South walls - BLUE plane)
		# Tilted on Y-axis, so use Z-axis offset
		TileOrientation.WALL_NORTH_TILT_POS_Y, \
		TileOrientation.WALL_NORTH_TILT_NEG_Y, \
		TileOrientation.WALL_SOUTH_TILT_POS_Y, \
		TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			# return tilemap_node.zAxis_tilt_offset
			return Vector3(0,0,offset_value)

		# X-AXIS TILTS (East/West walls - RED plane)
		# Tilted on X-axis, so use X-axis offset
		TileOrientation.WALL_EAST_TILT_POS_X, \
		TileOrientation.WALL_EAST_TILT_NEG_X, \
		TileOrientation.WALL_WEST_TILT_POS_X, \
		TileOrientation.WALL_WEST_TILT_NEG_X:
			return Vector3(offset_value,0,0)

		_:
			return Vector3.ZERO  # Should never reach here


## Returns orientation-aware tolerance vector for area selection/erase
##   Applies full tolerance on plane axes, small tolerance on depth axis
## This prevents depth bleed while handling floating point precision
##
## @param orientation: The tile orientation (0-17)
## @param tolerance: The tolerance value for plane axes (typically 0.6)
## @return Vector3: Tolerance vector with small depth tolerance (0.15)
##
## Example: FLOOR at Y=0 with tolerance 0.6
##   - Old behavior: bounds expand to Y ∈ [-0.6, +0.6] (catches tiles on top/below)
##   - New behavior: Y ∈ [-0.15, +0.15] (handles float precision, prevents cross-layer)
##   - X/Z expand by ±0.6 (full tolerance for fractional positions)
static func get_orientation_tolerance(orientation: int, tolerance: float) -> Vector3:
	var depth_tolerance: float = GlobalConstants.AREA_ERASE_DEPTH_TOLERANCE  # 0.15

	match orientation:
		# === FLOOR/CEILING: XZ plane, Y is depth ===
		TileOrientation.FLOOR, \
		TileOrientation.CEILING, \
		TileOrientation.FLOOR_TILT_POS_X, \
		TileOrientation.FLOOR_TILT_NEG_X, \
		TileOrientation.CEILING_TILT_POS_X, \
		TileOrientation.CEILING_TILT_NEG_X:
			return Vector3(tolerance, depth_tolerance, tolerance)  # Full tolerance on X/Z, small on Y (depth)

		# === NORTH/SOUTH WALLS: XY plane, Z is depth ===
		TileOrientation.WALL_NORTH, \
		TileOrientation.WALL_SOUTH, \
		TileOrientation.WALL_NORTH_TILT_POS_Y, \
		TileOrientation.WALL_NORTH_TILT_NEG_Y, \
		TileOrientation.WALL_SOUTH_TILT_POS_Y, \
		TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			return Vector3(tolerance, tolerance, depth_tolerance)  # Full tolerance on X/Y, small on Z (depth)

		# === EAST/WEST WALLS: YZ plane, X is depth ===
		TileOrientation.WALL_EAST, \
		TileOrientation.WALL_WEST, \
		TileOrientation.WALL_EAST_TILT_POS_X, \
		TileOrientation.WALL_EAST_TILT_NEG_X, \
		TileOrientation.WALL_WEST_TILT_POS_X, \
		TileOrientation.WALL_WEST_TILT_NEG_X:
			return Vector3(depth_tolerance, tolerance, tolerance)  # Full tolerance on Y/Z, small on X (depth)

		_:
			# Fallback: Conservative tolerance (same as FLOOR)
			push_warning("GlobalUtil.get_orientation_tolerance(): Unknown orientation %d, using FLOOR tolerance" % orientation)
			return Vector3(tolerance, depth_tolerance, tolerance)


# ## @deprecated INCORRECT: Uses uniform scaling (0.7071) instead of non-uniform scaling (1.414)
# ## Use build_tile_transform() instead - single source of truth for all transform construction
# ## This method will be removed in future versions
# static func get_orientation_basis_with_scale(orientation: int) -> Basis:
# 	push_warning("DEPRECATED: get_orientation_basis_with_scale() uses incorrect uniform scaling. Use build_tile_transform() instead.")
# 	var basis: Basis = get_orientation_basis(orientation)

# 	# Check if this is a tilted orientation that needs scaling
# 	# Tilted tiles (6-17) need 0.7071 scale to fit grid
# 	if orientation >= TileOrientation.FLOOR_TILT_POS_X:
# 		# Apply uniform scaling by TILT_SCALE_FACTOR (1/√2 ≈ 0.7071)
# 		var scale_basis: Basis = Basis.from_scale(
# 			Vector3.ONE * GlobalConstants.TILT_SCALE_FACTOR
# 		)
# 		basis = basis * scale_basis  # Apply scaling AFTER orientation rotation

# 	return basis


# ==============================================================================
# TRANSFORM CONSTRUCTION (SINGLE SOURCE OF TRUTH)
# ==============================================================================

## This is the SINGLE SOURCE OF TRUTH for all tile transform construction
##
## Transform order ( - DO NOT CHANGE):
##   1. Scale (non-uniform per-axis for tilted orientations)
##   2. Orient (base orientation: FLOOR, WALL_NORTH, etc.)
##   3. Rotate (Q/E mesh rotation: 0°, 90°, 180°, 270°)
##
## Why this order?
##   - Scale FIRST: Stretches the mesh before rotation (e.g., 1.0×1.414 rectangle)
##   - Orient SECOND: Rotates to correct plane (floor/wall/ceiling)
##   - Rotate LAST: Applies in-plane rotation (Q/E keys)
##
## @param grid_pos: Grid position (supports fractional: 0.5, 1.75, etc.)
## @param orientation: TileOrientation enum value (0-17)
## @param mesh_rotation: Mesh rotation 0-3 (0°, 90°, 180°, 270°)
## @param grid_size: Grid cell size in world units
## @returns: Complete Transform3D ready for MultiMesh.set_instance_transform()
##
## Example usage:
##   var transform: Transform3D = GlobalUtil.build_tile_transform(
##       Vector3(5, 0, 3), TileOrientation.FLOOR_TILT_POS_X, 1, 1.0, tile_model_root
##   )
##   chunk.multimesh.set_instance_transform(index, transform)
static func build_tile_transform(
	grid_pos: Vector3,
	orientation: int,
	mesh_rotation: int,
	grid_size: float,
	tile_map3d_node: TileMapLayer3D = null,
	is_face_flipped: bool = false
) -> Transform3D:
	var transform: Transform3D = Transform3D()

	# Step 1: Get non-uniform scale vector for this orientation
	var scale_vector: Vector3 = get_scale_for_orientation(orientation)
	var scale_basis: Basis = Basis.from_scale(scale_vector)

	# Step 2: Get orientation basis (WITHOUT built-in scaling)
	var orientation_basis: Basis = get_orientation_basis(orientation)

	# Step 3: Combine scale and orientation (ORDER !)
	# Scale FIRST, then orient
	var combined_basis: Basis = orientation_basis * scale_basis

	# Step 3.5: Apply face flip (F key) if needed - BEFORE mesh rotation
	if is_face_flipped:
		var flip_basis: Basis = Basis.from_scale(Vector3(1, 1, -1))  # Flip Z-axis (normal direction)
		combined_basis = combined_basis * flip_basis

	# Step 4: Apply mesh rotation (Q/E keys) if needed
	if mesh_rotation > 0:
		combined_basis = apply_mesh_rotation(combined_basis, orientation, mesh_rotation)

	# Step 5: Calculate world position
	var world_pos: Vector3 = grid_to_world(grid_pos, grid_size)

	# Step 6: Apply tilt offset for tilted orientations (6-17)
	if tile_map3d_node and orientation >= TileOrientation.FLOOR_TILT_POS_X:
		var tilt_offset: Vector3 = get_tilt_offset_for_orientation(orientation, tile_map3d_node)
		world_pos += tilt_offset

	# Step 7: Set final transform
	transform.basis = combined_basis
	transform.origin = world_pos

	return transform


##   Builds tile basis (rotation part only) for preview nodes
## Similar to build_tile_transform() but returns only the Basis (no position)
##
## @param orientation: TileOrientation enum value (0-17)
## @param mesh_rotation: Mesh rotation 0-3 (0°, 90°, 180°, 270°)
## @returns: Basis ready for Node3D.basis assignment
##
## Example usage:
##   preview_node.basis = GlobalUtil.build_tile_basis(
##       TileOrientation.FLOOR_TILT_POS_X, 1
##   )
static func build_tile_basis(orientation: int, mesh_rotation: int, is_face_flipped: bool = false) -> Basis:
	# Step 1: Get non-uniform scale vector for this orientation
	var scale_vector: Vector3 = get_scale_for_orientation(orientation)
	var scale_basis: Basis = Basis.from_scale(scale_vector)

	# Step 2: Get orientation basis (WITHOUT built-in scaling)
	var orientation_basis: Basis = get_orientation_basis(orientation)

	# Step 3: Combine scale and orientation (ORDER !)
	var combined_basis: Basis = orientation_basis * scale_basis

	# Step 3.5: Apply face flip (F key) if needed - BEFORE mesh rotation
	if is_face_flipped:
		var flip_basis: Basis = Basis.from_scale(Vector3(1, 1, -1))  # Flip Z-axis (normal direction)
		combined_basis = combined_basis * flip_basis

	# Step 4: Apply mesh rotation (Q/E keys) if needed
	if mesh_rotation > 0:
		combined_basis = apply_mesh_rotation(combined_basis, orientation, mesh_rotation)

	return combined_basis


# ==============================================================================
# MESH ROTATION ( Q/E rotation)
# ==============================================================================

## Returns the rotation axis for in-plane mesh rotation based on orientation
## This is the axis PERPENDICULAR to the tile's surface (the surface normal)
##
## @param orientation: TileOrientation enum value
## @returns: Vector3 axis for rotation (world-aligned)
##
static func get_rotation_axis_for_orientation(orientation: int) -> Vector3:
	match orientation:
		TileOrientation.FLOOR:
			return Vector3.UP  # Rotate around Y+ axis (horizontal surface facing up)

		TileOrientation.CEILING:
			return Vector3.DOWN  # Rotate around Y- axis (horizontal surface facing down)

		TileOrientation.WALL_NORTH:
			return Vector3.BACK  # Rotate around Z+ axis (vertical wall facing south)

		TileOrientation.WALL_SOUTH:
			return Vector3.FORWARD  # Rotate around Z- axis (vertical wall facing north)

		TileOrientation.WALL_EAST:
			return Vector3.LEFT  # Rotate around X- axis (vertical wall facing west)

		TileOrientation.WALL_WEST:
			return Vector3.RIGHT  # Rotate around X+ axis (vertical wall facing east)

		# === TILTED FLOOR/CEILING ===
		# For 45° tilted surfaces, calculate the normal vector
		TileOrientation.FLOOR_TILT_POS_X, TileOrientation.FLOOR_TILT_NEG_X:
			# Tilted floor - normal is angled between UP and FORWARD/BACK
			var basis: Basis = get_orientation_basis(orientation)
			return basis.y.normalized()  # Y-axis of the basis is the surface normal

		TileOrientation.CEILING_TILT_POS_X, TileOrientation.CEILING_TILT_NEG_X:
			# Tilted ceiling - normal is angled between DOWN and FORWARD/BACK
			var basis: Basis = get_orientation_basis(orientation)
			return basis.y.normalized()

		# === TILTED NORTH/SOUTH WALLS ===
		TileOrientation.WALL_NORTH_TILT_POS_Y, TileOrientation.WALL_NORTH_TILT_NEG_Y:
			# Tilted north wall - normal is angled between BACK and LEFT/RIGHT
			var basis: Basis = get_orientation_basis(orientation)
			return basis.z.normalized()  # Z-axis of the basis is the surface normal

		TileOrientation.WALL_SOUTH_TILT_POS_Y, TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			# Tilted south wall - normal is angled between FORWARD and LEFT/RIGHT
			var basis: Basis = get_orientation_basis(orientation)
			return basis.z.normalized()

		# === TILTED EAST/WEST WALLS ===
		TileOrientation.WALL_EAST_TILT_POS_X, TileOrientation.WALL_EAST_TILT_NEG_X:
			# Tilted east wall - normal is angled between LEFT and FORWARD/BACK
			var basis: Basis = get_orientation_basis(orientation)
			return basis.x.normalized()  # X-axis of the basis is the surface normal

		TileOrientation.WALL_WEST_TILT_POS_X, TileOrientation.WALL_WEST_TILT_NEG_X:
			# Tilted west wall - normal is angled between RIGHT and FORWARD/BACK
			var basis: Basis = get_orientation_basis(orientation)
			return basis.x.normalized()

		_:
			push_warning("Invalid axis orientation for rotation: ", orientation)
			return Vector3.UP

## Applies mesh rotation to an existing orientation basis
## This rotates the tile within its plane WITHOUT changing which surface it's on
##
## @param base_basis: The orientation basis from get_orientation_basis()
## @param orientation: TileOrientation enum value (to determine rotation axis)
## @param rotation_steps: Number of 90° rotations (0-3)
## @returns: Basis with in-plane rotation applied
##
## Example: For a FLOOR tile with 90° rotation:
##   base_basis = Basis.IDENTITY (horizontal)
##   rotation_axis = Vector3.UP (perpendicular to floor)
##   final_basis rotates tile 90° around Y axis while staying on floor
##
static func apply_mesh_rotation(base_basis: Basis, orientation: int, rotation_steps: int) -> Basis:
	if rotation_steps == 0:
		return base_basis

	# Get the rotation axis for this orientation (surface normal)
	var rotation_axis: Vector3 = get_rotation_axis_for_orientation(orientation)

	# Calculate rotation angle (90° per step)
	var angle: float = (rotation_steps % 4) * GlobalConstants.ROTATION_90_DEG

	# Create rotation basis around world-aligned axis
	var rotation_basis: Basis = Basis(rotation_axis, angle)

	#   Apply rotation AFTER orientation
	# Order: orientation positions tile on surface, rotation rotates within that surface
	return rotation_basis * base_basis

# ==============================================================================
# GRID & WORLD COORDINATE CONVERSION
# ==============================================================================

## Converts grid coordinates to world position
## Grid coordinates are integer or fractional positions in the logical grid.
## World position is the actual 3D position in the scene.
##
## @param grid_pos: Position in grid coordinates
## @param grid_size: Size of one grid cell in world units
## @returns: World position (Vector3)
##
## Formula: world_pos = (grid_pos + GRID_ALIGNMENT_OFFSET) * grid_size
## The offset centers tiles on grid coordinates.
static func grid_to_world(grid_pos: Vector3, grid_size: float) -> Vector3:
	return (grid_pos + GlobalConstants.GRID_ALIGNMENT_OFFSET) * grid_size

## Converts world position to grid coordinates
## This is the inverse of grid_to_world()
##
## @param world_pos: Position in world space
## @param grid_size: Size of one grid cell in world units
## @returns: Grid coordinates (Vector3, can be fractional)
##
## Formula: grid_pos = (world_pos / grid_size) - GRID_ALIGNMENT_OFFSET
static func world_to_grid(world_pos: Vector3, grid_size: float) -> Vector3:
	return (world_pos / grid_size) - GlobalConstants.GRID_ALIGNMENT_OFFSET

# ==============================================================================
# TILE KEY MANAGEMENT
# ==============================================================================

## Creates a unique tile key from grid position and orientation
## Tile keys are used to uniquely identify tiles in dictionaries and saved data.
## @param grid_pos: Grid coordinates (can be fractional)
## @param orientation: Tile orientation (0-17)
## @returns: 64-bit integer tile key
static func make_tile_key(grid_pos: Vector3, orientation: int) -> int:
	return TileKeySystem.make_tile_key_int(grid_pos, orientation)

## Parses a tile key back into components
## This is the inverse of make_tile_key()
##
## @param tile_key: String key in format "x,y,z,orientation"
## @returns: Dictionary with keys: "grid_pos" (Vector3), "orientation" (int)
##           Returns empty dictionary if parsing fails.
static func parse_tile_key(tile_key: String) -> Dictionary:
	var parts: PackedStringArray = tile_key.split(",")
	if parts.size() != 4:
		push_warning("Invalid tile key format: ", tile_key)
		return {}

	var grid_pos := Vector3(
		parts[0].to_float(),
		parts[1].to_float(),
		parts[2].to_float()
	)
	var orientation: int = parts[3].to_int()

	return {
		"grid_pos": grid_pos,
		"orientation": orientation
	}

##  Migrates Dictionary with string keys to integer keys
## Used for backward compatibility when loading old scenes
## @param old_dict: Dictionary with string or integer keys
## @returns: New Dictionary with all keys converted to integers
static func migrate_placement_data(old_dict: Dictionary) -> Dictionary:
	var new_dict: Dictionary = {}

	for old_key in old_dict.keys():
		if old_key is String:
			# Migrate string key to integer key
			var new_key: int = TileKeySystem.migrate_string_key(old_key)
			if new_key != -1:
				new_dict[new_key] = old_dict[old_key]
			else:
				push_warning("GlobalUtil: Failed to migrate tile key: ", old_key)
		else:
			# Already integer key
			new_dict[old_key] = old_dict[old_key]

	return new_dict

# ==============================================================================
# UV COORDINATE UTILITIES
# ==============================================================================

## Calculates normalized UV coordinates from pixel rect and atlas size
## SINGLE SOURCE OF TRUTH for UV calculations - used by preview and placed tiles
##
## This function eliminates code duplication across 5 files and ensures consistent
## UV handling between preview tiles and placed tiles, preventing texture bleeding issues.
##
## @param uv_rect: Pixel coordinates in atlas (e.g., Rect2(32, 0, 32, 32))
## @param atlas_size: Texture dimensions (e.g., Vector2(256, 256))
## @returns: Dictionary with keys:
##   - "uv_min" (Vector2): Normalized min UV [0-1] range
##   - "uv_max" (Vector2): Normalized max UV [0-1] range
##   - "uv_color" (Color): Packed format for shader (uv_min.x, uv_min.y, uv_max.x, uv_max.y)
##
##
## Example:
##   var uv_data = GlobalUtil.calculate_normalized_uv(Rect2(32, 0, 32, 32), Vector2(256, 256))
##   multimesh.set_instance_custom_data(index, uv_data.uv_color)
static func calculate_normalized_uv(uv_rect: Rect2, atlas_size: Vector2) -> Dictionary:
	var uv_min: Vector2 = uv_rect.position / atlas_size
	var uv_max: Vector2 = (uv_rect.position + uv_rect.size) / atlas_size
	var uv_color: Color = Color(uv_min.x, uv_min.y, uv_max.x, uv_max.y)

	return {
		"uv_min": uv_min,
		"uv_max": uv_max,
		"uv_color": uv_color
	}


static func create_tile_instance(
	grid_pos: Vector3,
	orientation: int,
	mesh_rotation: int,
	uv_rect: Rect2,
	texture: Texture2D,
	grid_size: float,
	is_preview: bool = false,
	mesh_mode: GlobalConstants.MeshMode = GlobalConstants.MeshMode.MESH_SQUARE,
	is_face_flipped: bool = false
) -> MeshInstance3D:
	var instance = MeshInstance3D.new()

	# Create appropriate mesh
	var mesh: ArrayMesh
	if is_preview:
		mesh = TileMeshGenerator.create_preview_tile_quad(uv_rect, texture.get_size(), Vector2(grid_size, grid_size))
	else:
		mesh = TileMeshGenerator.create_tile_quad(uv_rect, texture.get_size(), Vector2(grid_size, grid_size))

	instance.mesh = mesh
	instance.transform = build_tile_transform(grid_pos, orientation, mesh_rotation, grid_size, null, is_face_flipped)
	instance.material_override = create_tile_material(texture, GlobalConstants.DEFAULT_TEXTURE_FILTER, 0)

	return instance

# ==============================================================================
# DOCUMENTATION NOTES
# ==============================================================================

## ADDING NEW UTILITY METHODS:
##
# ==============================================================================
# MESH GEOMETRY HELPERS
# ==============================================================================

## Add triangle tile geometry to mesh arrays
## Used by both merge bake and alpha-aware bake for consistent triangle rendering
##
## @param vertices: PackedVector3Array to append vertices to
## @param uvs: PackedVector2Array to append UVs to
## @param normals: PackedVector3Array to append normals to
## @param indices: PackedInt32Array to append indices to
## @param transform: Transform3D to apply to vertices
## @param uv_rect: Rect2 in NORMALIZED [0-1] coordinates (NOT pixel coordinates)
## @param grid_size: World size of tile
static func add_triangle_geometry(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	transform: Transform3D,
	uv_rect: Rect2,
	grid_size: float
) -> void:

	var half_width: float = grid_size * 0.5
	var half_height: float = grid_size * 0.5

	# Define local vertices (right triangle, counter-clockwise)
	# These are in local tile space (centered at origin)
	# MUST MATCH tile_mesh_generator.gd geometry!
	var local_verts: Array[Vector3] = [
		Vector3(-half_width, 0.0, -half_height), # 0: bottom-left
		Vector3(half_width, 0.0, -half_height),  # 1: bottom-right
		Vector3(-half_width, 0.0, half_height)   # 2: top-left
	]

	#   UV coordinates for triangle in NORMALIZED [0-1] space
	# uv_rect should be pre-normalized before calling this function
	# Map triangle vertices to UV space - MUST MATCH generator UVs!
	var tile_uvs: Array[Vector2] = [
		uv_rect.position,                                    # 0: bottom-left UV
		Vector2(uv_rect.end.x, uv_rect.position.y),         # 1: bottom-right UV
		Vector2(uv_rect.position.x, uv_rect.end.y)          # 2: top-left UV
	]

	# Transform vertices to world space and set data
	var normal: Vector3 = transform.basis.y.normalized()
	var v_offset: int = vertices.size()

	for i: int in range(3):
		vertices.append(transform * local_verts[i])
		uvs.append(tile_uvs[i])
		normals.append(normal)

	# Set indices for single triangle (counter-clockwise winding)
	indices.append(v_offset + 0)
	indices.append(v_offset + 1)
	indices.append(v_offset + 2)

# ==============================================================================
# BAKED MESH MATERIAL CREATION
# ==============================================================================

## Creates StandardMaterial3D for baked mesh exports
## Single source of truth for all merge/bake material creation
##
## @param texture: Atlas texture to apply
## @param filter_mode: Texture filter mode (0-3)
##   0 = Nearest (pixel-perfect)
##   1 = Nearest Mipmap
##   2 = Linear (smooth)
##   3 = Linear Mipmap
## @param render_priority: Material render priority
## @param enable_alpha: Whether to enable alpha scissor transparency
## @param enable_toon_shading: Whether to use toon shading (diffuse + specular)
## @returns: Configured StandardMaterial3D ready for baked mesh
static func create_baked_mesh_material(
	texture: Texture2D,
	filter_mode: int = 0,
	render_priority: int = 0,
	enable_alpha: bool = true,
	enable_toon_shading: bool = true
) -> StandardMaterial3D:

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_BACK

	# Apply texture filter mode
	match filter_mode:
		0:  # Nearest
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		1:  # Nearest Mipmap
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		2:  # Linear
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		3:  # Linear Mipmap
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# Enable alpha transparency if requested
	if enable_alpha:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5

	# Enable toon shading if requested
	if enable_toon_shading:
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		material.specular_mode = BaseMaterial3D.SPECULAR_TOON

	material.render_priority = render_priority

	return material

# ==============================================================================
# MESH ARRAY UTILITIES
# ==============================================================================

## Creates ArrayMesh from packed arrays with optional tangent generation
## Single source of truth for all ArrayMesh creation in bake operations
##
## @param vertices: Vertex positions
## @param uvs: UV coordinates
## @param normals: Vertex normals
## @param indices: Triangle indices
## @param tangents: Optional pre-generated tangents (if null, will be generated)
## @param mesh_name: Optional resource name for the mesh
## @returns: Configured ArrayMesh ready for rendering
static func create_array_mesh_from_arrays(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	tangents: PackedFloat32Array = PackedFloat32Array(),
	mesh_name: String = ""
) -> ArrayMesh:

	# Generate tangents if not provided
	var final_tangents: PackedFloat32Array = tangents
	if final_tangents.is_empty():
		final_tangents = generate_tangents_for_mesh(vertices, uvs, normals, indices)

	# Create mesh arrays
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = final_tangents
	arrays[Mesh.ARRAY_INDEX] = indices

	# Create ArrayMesh
	var array_mesh: ArrayMesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	if not mesh_name.is_empty():
		array_mesh.resource_name = mesh_name

	return array_mesh

## Generates tangents using Godot's built-in MikkTSpace algorithm
## Tangents are required for proper normal mapping and lighting
## Single source of truth for tangent generation across all bake operations
##
## @param vertices: Vertex positions
## @param uvs: UV coordinates
## @param normals: Vertex normals
## @param indices: Triangle indices
## @returns: PackedFloat32Array of tangents (4 floats per vertex: x, y, z, w)
static func generate_tangents_for_mesh(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array
) -> PackedFloat32Array:

	var tangents: PackedFloat32Array = PackedFloat32Array()
	tangents.resize(vertices.size() * 4)

	# Use Godot's built-in tangent generation via SurfaceTool
	# This is more reliable than manual calculation and uses MikkTSpace
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Add vertices with their attributes
	for i: int in range(vertices.size()):
		st.set_uv(uvs[i])
		st.set_normal(normals[i])
		st.add_vertex(vertices[i])

	# Add indices
	for idx: int in indices:
		st.add_index(idx)

	# Generate tangents (MikkTSpace algorithm)
	st.generate_tangents()

	# Extract tangents from the generated mesh
	var temp_arrays: Array = st.commit_to_arrays()
	if temp_arrays[Mesh.ARRAY_TANGENT]:
		tangents = temp_arrays[Mesh.ARRAY_TANGENT]

	return tangents

# ==============================================================================
# TILE HIGHLIGHT OVERLAY UTILITIES
# ==============================================================================

## Creates a StandardMaterial3D for tile highlight overlay
## Single source of truth for highlight material creation
##
## Properties:
##   - Semi-transparent orange color (TILE_HIGHLIGHT_COLOR)
##   - Alpha transparency enabled
##   - Unshaded (bright, doesn't react to light)
##   - High render priority (renders on top of tiles)
##   - No depth testing (always visible through geometry)
##   - Double-sided (visible from both sides)
##
## @returns: StandardMaterial3D configured for highlight overlays
##
##
## Example:
##   var material = GlobalUtil.create_highlight_material()
##   highlight_mesh.material_override = material
static func create_highlight_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()

	# Semi-transparent orange color
	material.albedo_color = GlobalConstants.TILE_HIGHLIGHT_COLOR

	# Enable alpha transparency
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Unshaded = bright, no lighting calculations
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Render on top of tiles
	material.render_priority = 10

	# Always visible (ignore depth buffer)
	material.no_depth_test = true

	# Visible from both sides
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	return material

# ==============================================================================
# AREA FILL UTILITIES
# ==============================================================================

## Returns all grid positions within a rectangular area on a specific plane
## Calculates which grid cells are included in the area based on orientation
##
## @param min_pos: Vector3 - Minimum corner of selection area (inclusive)
## @param max_pos: Vector3 - Maximum corner of selection area (inclusive)
## @param orientation: int - Active plane orientation (0-5 for floor/ceiling/walls)
## @returns: Array[Vector3] - All grid positions in the area
##
##
## Example:
##   var positions = GlobalUtil.get_grid_positions_in_area(Vector3(0,0,0), Vector3(2,0,2), 0)
##   # Returns: [Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0), Vector3(0,0,1), ...]
##
## Note: Only iterates over the 2D plane defined by orientation
## - Floor/Ceiling (0,1): Varies X and Z, keeps Y constant
## - Walls (2-5): Varies based on wall normal
static func get_grid_positions_in_area(min_pos: Vector3, max_pos: Vector3, orientation: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []

	# Ensure min is actually minimum and max is maximum on all axes
	var actual_min: Vector3 = Vector3(
		min(min_pos.x, max_pos.x),
		min(min_pos.y, max_pos.y),
		min(min_pos.z, max_pos.z)
	)
	var actual_max: Vector3 = Vector3(
		max(min_pos.x, max_pos.x),
		max(min_pos.y, max_pos.y),
		max(min_pos.z, max_pos.z)
	)

	# Round to integer grid positions (area fill only works on whole cells)
	var min_grid: Vector3i = Vector3i(
		int(floor(actual_min.x)),
		int(floor(actual_min.y)),
		int(floor(actual_min.z))
	)
	var max_grid: Vector3i = Vector3i(
		int(floor(actual_max.x)),
		int(floor(actual_max.y)),
		int(floor(actual_max.z))
	)

	# Determine which axes to iterate based on orientation
	# Floor (0): XZ plane (Y constant)
	# Ceiling (1): XZ plane (Y constant)
	# North Wall (2): XY plane (Z constant)
	# South Wall (3): XY plane (Z constant)
	# East Wall (4): ZY plane (X constant)
	# West Wall (5): ZY plane (X constant)

	match orientation:
		TileOrientation.FLOOR, TileOrientation.CEILING:
			# Iterate over XZ plane
			for x in range(min_grid.x, max_grid.x + 1):
				for z in range(min_grid.z, max_grid.z + 1):
					positions.append(Vector3(x, actual_min.y, z))

		TileOrientation.WALL_NORTH, TileOrientation.WALL_SOUTH:
			# Iterate over XY plane
			for x in range(min_grid.x, max_grid.x + 1):
				for y in range(min_grid.y, max_grid.y + 1):
					positions.append(Vector3(x, y, actual_min.z))

		TileOrientation.WALL_EAST, TileOrientation.WALL_WEST:
			# Iterate over ZY plane
			for z in range(min_grid.z, max_grid.z + 1):
				for y in range(min_grid.y, max_grid.y + 1):
					positions.append(Vector3(actual_min.x, y, z))

		_:
			# Fallback: treat as floor (XZ plane)
			for x in range(min_grid.x, max_grid.x + 1):
				for z in range(min_grid.z, max_grid.z + 1):
					positions.append(Vector3(x, actual_min.y, z))

	return positions

## Creates a StandardMaterial3D for area fill selection box
## Semi-transparent cyan box that shows the area being selected
##
## Properties:
##   - Semi-transparent cyan color (AREA_FILL_BOX_COLOR)
##   - Alpha transparency enabled
##   - Unshaded (bright, doesn't react to light)
##   - High render priority (renders on top)
##   - No depth testing (always visible)
##   - Double-sided (visible from both sides)
##
## @returns: StandardMaterial3D configured for area selection visualization
##
##
## Example:
##   var material = GlobalUtil.create_area_selection_material()
##   selection_box_mesh.material_override = material
static func create_area_selection_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()

	# Semi-transparent cyan color
	material.albedo_color = GlobalConstants.AREA_FILL_BOX_COLOR

	# Enable alpha transparency
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Unshaded = bright, no lighting calculations
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Render on top of scene
	material.render_priority = 10

	# Always visible (ignore depth buffer)
	material.no_depth_test = true

	# Visible from both sides
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	return material

# ==============================================================================
# DOCUMENTATION GUIDELINES
# ==============================================================================

## When adding new utility methods, follow these guidelines:
##
## 1. Make methods static (no instance needed)
## 2. Use clear, descriptive names
## 3. Include comprehensive documentation:
##    - What the method does
##    - Parameters and their meaning
##    - Return value and type
##    - Where it's used
##    - Example usage if complex
## 4. Group related methods together
## 5. Update this documentation section
##
## WHEN TO ADD A METHOD HERE:
## - Method is used in 2+ different files
## - Method provides core functionality (grid conversion, material creation, etc.)
## - Method should have consistent behavior across the addon
##
## WHEN NOT TO ADD A METHOD HERE:
## - Method is specific to one class/feature
## - Method depends on instance state (use regular class methods instead)
## - Method is a simple wrapper with no shared logic
