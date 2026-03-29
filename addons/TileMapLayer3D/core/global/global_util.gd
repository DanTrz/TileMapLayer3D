extends RefCounted
class_name GlobalUtil

## Centralizes all shared utility methods, material creation, and common processing functions.

# --- Material Creation ---

# Cache shader resource for performance
static var _cached_shader: Shader = null
static var _cached_shader_double_sided: Shader = null
static var _cached_preview_shader: Shader = null



## Creates a StandardMaterial3D configured for unshaded, transparent rendering
static func create_unshaded_material(
	color: Color,
	cull_disabled: bool = false,
	render_priority: int = GlobalConstants.DEFAULT_RENDER_PRIORITY
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = render_priority
	if cull_disabled:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

## Creates a ShaderMaterial for tile rendering (ONLY place tile materials should be created)
static func create_tile_material(texture: Texture2D, filter_mode: int = 0, render_priority: int = 0, debug_show_red_backfaces: bool = true) -> ShaderMaterial:
	# Cache shader resource for performance
	if not _cached_shader:
		_cached_shader = load("uid://huf0b1u2f55e")

	if not _cached_shader_double_sided:
		_cached_shader_double_sided = load("uid://6otniuywb7v8")

	var material: ShaderMaterial = ShaderMaterial.new()

	if debug_show_red_backfaces:
		material.shader = _cached_shader
	else:
		material.shader = _cached_shader_double_sided
	# material.shader = _cached_shader
	material.render_priority = render_priority

	# Set texture and filter mode parameters
	if texture:
		material.set_shader_parameter("albedo_texture_nearest", texture)
		material.set_shader_parameter("albedo_texture_linear", texture)
		material.set_shader_parameter("debug_show_backfaces", debug_show_red_backfaces)

		# 0-1 = Nearest (hardware filter_nearest sampler), 2-3 = Linear (hardware filter_linear sampler)
		var use_nearest: bool = (filter_mode == 0 or filter_mode == 1)
		material.set_shader_parameter("use_nearest_texture", use_nearest)

	return material


## Creates a ShaderMaterial for PREVIEW tile rendering (uniform-based UV region)
static func create_preview_material(texture: Texture2D, uv_region_min: Vector2, uv_region_max: Vector2, filter_mode: int = 0, render_priority: int = 99
) -> ShaderMaterial:
	# Cache preview shader resource for performance
	if not _cached_preview_shader:
		_cached_preview_shader = load("uid://chk7vtf6p8lwg")
		# NOTE: Replace path with uid:// after first import in Godot editor

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _cached_preview_shader
	material.render_priority = render_priority

	if texture:
		material.set_shader_parameter("atlas_texture", texture)
		material.set_shader_parameter("uv_region_min", uv_region_min)
		material.set_shader_parameter("uv_region_max", uv_region_max)

		var use_nearest: bool = (filter_mode == 0 or filter_mode == 1)
		material.set_shader_parameter("use_nearest_texture", use_nearest)

	return material

## Updates an existing preview material's UV region without recreating it
static func update_preview_material_uv(material: ShaderMaterial,uv_region_min: Vector2,uv_region_max: Vector2
) -> void:
	if material:
		material.set_shader_parameter("uv_region_min", uv_region_min)
		material.set_shader_parameter("uv_region_max", uv_region_max)
# --- Signal Connection Utilities ---

## Safely connects a signal if not already connected
static func safe_connect(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)

## Safely disconnects a signal if currently connected
static func safe_disconnect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)


# --- Orientation and Transform Utilities ---
enum TileOrientation {
	# --- Base Orientations ---
	FLOOR = 0,
	CEILING = 1,
	WALL_NORTH = 2,
	WALL_SOUTH = 3,
	WALL_EAST = 4,
	WALL_WEST = 5,

	# --- Tilted Variants ---
	# Floor/Ceiling tilts on X-axis
	FLOOR_TILT_POS_X = 6,
	FLOOR_TILT_NEG_X = 7,
	CEILING_TILT_POS_X = 8,
	CEILING_TILT_NEG_X = 9,

	# North walls tilt on Y-axis
	WALL_NORTH_TILT_POS_Y = 10,
	WALL_NORTH_TILT_NEG_Y = 11,
	WALL_NORTH_TILT_POS_X = 12, 
	WALL_NORTH_TILT_NEG_X = 13, 

	# South walls tilt on Y-axis
	WALL_SOUTH_TILT_POS_Y = 14,
	WALL_SOUTH_TILT_NEG_Y = 15,
	WALL_SOUTH_TILT_POS_X = 16, 
	WALL_SOUTH_TILT_NEG_X = 17, 

	# East
	WALL_EAST_TILT_POS_X = 18,
	WALL_EAST_TILT_NEG_X = 19,
	WALL_EAST_TILT_POS_Y = 20, 
	WALL_EAST_TILT_NEG_Y = 21, 

	# west
	WALL_WEST_TILT_POS_X = 22,
	WALL_WEST_TILT_NEG_X = 23,
	WALL_WEST_TILT_POS_Y = 24, 
	WALL_WEST_TILT_NEG_Y = 25, 

}

# --- Orientation Data ---
const ORIENTATION_DATA: Dictionary = {
	# --- Floor Group ---
	TileOrientation.FLOOR: {
		"base": TileOrientation.FLOOR,
		"scale": Vector3.ONE,
		"depth_axis": "y",
		"tilt_offset_axis": "",
	},
	TileOrientation.FLOOR_TILT_POS_X: {
		"base": TileOrientation.FLOOR,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "y",
		"tilt_offset_axis": "y",
	},
	TileOrientation.FLOOR_TILT_NEG_X: {
		"base": TileOrientation.FLOOR,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "y",
		"tilt_offset_axis": "y",
	},

	# --- Ceiling Group ---
	TileOrientation.CEILING: {
		"base": TileOrientation.CEILING,
		"scale": Vector3.ONE,
		"depth_axis": "y",
		"tilt_offset_axis": "",
	},
	TileOrientation.CEILING_TILT_POS_X: {
		"base": TileOrientation.CEILING,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "y",
		"tilt_offset_axis": "y",
	},
	TileOrientation.CEILING_TILT_NEG_X: {
		"base": TileOrientation.CEILING,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "y",
		"tilt_offset_axis": "y",
	},

	# --- Wall North Group ---
	TileOrientation.WALL_NORTH: {
		"base": TileOrientation.WALL_NORTH,
		"scale": Vector3.ONE,
		"depth_axis": "z",
		"tilt_offset_axis": "",
	},
	TileOrientation.WALL_NORTH_TILT_POS_Y: {
		"base": TileOrientation.WALL_NORTH,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},
	TileOrientation.WALL_NORTH_TILT_NEG_Y: {
		"base": TileOrientation.WALL_NORTH,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},

	TileOrientation.WALL_NORTH_TILT_POS_X: {
		"base": TileOrientation.WALL_NORTH,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},
	TileOrientation.WALL_NORTH_TILT_NEG_X: {
		"base": TileOrientation.WALL_NORTH,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},

	# --- Wall South Group ---
	TileOrientation.WALL_SOUTH: {
		"base": TileOrientation.WALL_SOUTH,
		"scale": Vector3.ONE,
		"depth_axis": "z",
		"tilt_offset_axis": "",
	},
	TileOrientation.WALL_SOUTH_TILT_POS_Y: {
		"base": TileOrientation.WALL_SOUTH,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},
	TileOrientation.WALL_SOUTH_TILT_NEG_Y: {
		"base": TileOrientation.WALL_SOUTH,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},
	TileOrientation.WALL_SOUTH_TILT_POS_X: { 
		"base": TileOrientation.WALL_SOUTH,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},
	TileOrientation.WALL_SOUTH_TILT_NEG_X: { 
		"base": TileOrientation.WALL_SOUTH,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "z",
		"tilt_offset_axis": "z",
	},

	# --- Wall East Group ---
	TileOrientation.WALL_EAST: {
		"base": TileOrientation.WALL_EAST,
		"scale": Vector3.ONE,
		"depth_axis": "x",
		"tilt_offset_axis": "",
	},
	TileOrientation.WALL_EAST_TILT_POS_X: {
		"base": TileOrientation.WALL_EAST,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_EAST_TILT_NEG_X: {
		"base": TileOrientation.WALL_EAST,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_EAST_TILT_POS_Y: {  
		"base": TileOrientation.WALL_EAST,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_EAST_TILT_NEG_Y: {  
		"base": TileOrientation.WALL_EAST,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},


	# --- Wall West Group ---
	TileOrientation.WALL_WEST: {
		"base": TileOrientation.WALL_WEST,
		"scale": Vector3.ONE,
		"depth_axis": "x",
		"tilt_offset_axis": "",
	},
	TileOrientation.WALL_WEST_TILT_POS_X: {
		"base": TileOrientation.WALL_WEST,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_WEST_TILT_NEG_X: {
		"base": TileOrientation.WALL_WEST,
		"scale": Vector3(1.0, 1.0, GlobalConstants.DIAGONAL_SCALE_FACTOR),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_WEST_TILT_POS_Y: { 
		"base": TileOrientation.WALL_WEST,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
	TileOrientation.WALL_WEST_TILT_NEG_Y: {  
		"base": TileOrientation.WALL_WEST,
		"scale": Vector3(GlobalConstants.DIAGONAL_SCALE_FACTOR, 1.0, 1.0),
		"depth_axis": "x",
		"tilt_offset_axis": "x",
	},
}

# --- Tilt Sequences ---
const TILT_SEQUENCES: Dictionary = {
	TileOrientation.FLOOR: [
		TileOrientation.FLOOR,
		TileOrientation.FLOOR_TILT_POS_X,
		TileOrientation.FLOOR_TILT_NEG_X
	],
	TileOrientation.CEILING: [
		TileOrientation.CEILING,
		TileOrientation.CEILING_TILT_POS_X,
		TileOrientation.CEILING_TILT_NEG_X
	],
	TileOrientation.WALL_NORTH: [
		TileOrientation.WALL_NORTH,
		TileOrientation.WALL_NORTH_TILT_POS_Y,
		TileOrientation.WALL_NORTH_TILT_NEG_Y,
		TileOrientation.WALL_NORTH_TILT_NEG_X, 
		TileOrientation.WALL_NORTH_TILT_POS_X, 

	],
	TileOrientation.WALL_SOUTH: [
		TileOrientation.WALL_SOUTH,
		TileOrientation.WALL_SOUTH_TILT_POS_Y,
		TileOrientation.WALL_SOUTH_TILT_NEG_Y,
		TileOrientation.WALL_SOUTH_TILT_POS_X, 
		TileOrientation.WALL_SOUTH_TILT_NEG_X 
	],
	TileOrientation.WALL_EAST: [
		TileOrientation.WALL_EAST,
		TileOrientation.WALL_EAST_TILT_POS_X,
		TileOrientation.WALL_EAST_TILT_NEG_X,
		TileOrientation.WALL_EAST_TILT_POS_Y, 
		TileOrientation.WALL_EAST_TILT_NEG_Y 
	],
	TileOrientation.WALL_WEST: [
		TileOrientation.WALL_WEST,
		TileOrientation.WALL_WEST_TILT_POS_X,
		TileOrientation.WALL_WEST_TILT_NEG_X,
		TileOrientation.WALL_WEST_TILT_POS_Y,
		TileOrientation.WALL_WEST_TILT_NEG_Y
	],
}


# --- Orientation Conflict Detection ---

static func get_orientation_depth_axis(orientation: int) -> String:
	var data: Dictionary = ORIENTATION_DATA.get(orientation, {})
	return data.get("depth_axis", "")

## Checks if two base orientations (0-5) conflict (same depth_axis = overlap).
## Tilted tiles (6+) never conflict.
static func orientations_conflict(orientation_a: int, orientation_b: int) -> bool:
	if orientation_a == orientation_b:
		return false  # Same orientation is handled separately (replacement)
	# Only base orientations (0-5) can conflict - tilted tiles (6+) never conflict
	if orientation_a > 5 or orientation_b > 5:
		return false
	var axis_a: String = get_orientation_depth_axis(orientation_a)
	var axis_b: String = get_orientation_depth_axis(orientation_b)
	return axis_a != "" and axis_a == axis_b

## Returns the opposite-facing orientation for backface painting.
## Only base orientations (0-5); returns -1 for tilted.
static func get_opposite_orientation(orientation: int) -> int:
	match orientation:
		TileOrientation.FLOOR:        return TileOrientation.CEILING
		TileOrientation.CEILING:      return TileOrientation.FLOOR
		TileOrientation.WALL_NORTH:   return TileOrientation.WALL_SOUTH
		TileOrientation.WALL_SOUTH:   return TileOrientation.WALL_NORTH
		TileOrientation.WALL_EAST:    return TileOrientation.WALL_WEST
		TileOrientation.WALL_WEST:    return TileOrientation.WALL_EAST
		_: return -1  # Tilted orientations (6-25) are not coplanar - no backface painting

## Tiny offset along surface normal for flat tiles to prevent Z-fighting
static func calculate_flat_tile_offset(
	orientation: int,
	mesh_mode: int
) -> Vector3:
	# Only apply to flat mesh types (not BOX or PRISM which have thickness)
	if mesh_mode != GlobalConstants.MeshMode.FLAT_SQUARE and \
	   mesh_mode != GlobalConstants.MeshMode.FLAT_TRIANGULE:
		return Vector3.ZERO

	# Only apply if offset is enabled
	if GlobalConstants.FLAT_TILE_ORIENTATION_OFFSET <= 0.0:
		return Vector3.ZERO

	# Get surface normal for this orientation (includes tilted orientations)
	var normal: Vector3 = get_rotation_axis_for_orientation(orientation)

	# Return offset along the normal
	return normal * GlobalConstants.FLAT_TILE_ORIENTATION_OFFSET


# --- Orientation Lookup Functions ---

## Converts orientation enum to rotation basis.
## Pass tilt_angle=0.0 to use GlobalConstants.TILT_ANGLE_RAD.
static func get_tile_rotation_basis(orientation: int, tilt_angle: float = 0.0) -> Basis:
	# Use provided tilt_angle or default to GlobalConstants
	var actual_tilt: float = tilt_angle if tilt_angle != 0.0 else GlobalConstants.TILT_ANGLE_RAD

	match orientation:
		TileOrientation.FLOOR:
			# Default: horizontal quad facing up (no rotation)
			return Basis.IDENTITY

		TileOrientation.CEILING:
			# Flip upside down (180° around X axis)
			return Basis(Vector3(1, 0, 0), deg_to_rad(180))

		TileOrientation.WALL_NORTH:
			# Normal should point NORTH (-Z direction)
			# Rotate +90° around X: local Y (0,1,0) becomes world (0,0,-1)
			return Basis(Vector3(1, 0, 0), deg_to_rad(90))

		TileOrientation.WALL_SOUTH:
			# Normal should point SOUTH (+Z direction)
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-180))
			return Basis(Vector3(1, 0, 0), deg_to_rad(-90)) * rotation_correction

		TileOrientation.WALL_EAST:
			# Normal should point EAST (+X direction)
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-90))
			return Basis(Vector3(0, 0, 1), PI / 2.0) * rotation_correction

		TileOrientation.WALL_WEST:
			# Normal should point WEST (-X direction)
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(90))
			return Basis(Vector3(0, 0, 1), -PI / 2.0) * rotation_correction

		# --- Floor/Ceiling Tilts ---
		TileOrientation.FLOOR_TILT_POS_X:
			# Floor tilted forward (ramp up toward +Z)
			# Rotate on X-axis (red axis) by +tilt
			return Basis(Vector3.RIGHT, actual_tilt)

		TileOrientation.FLOOR_TILT_NEG_X:
			# Floor tilted backward (ramp down toward -Z)
			# Rotate on X-axis by -tilt
			return Basis(Vector3.RIGHT, -actual_tilt)

		TileOrientation.CEILING_TILT_POS_X:
			# Ceiling tilted forward (inverted ramp)
			# First flip ceiling (180° on X), then apply +tilt
			var ceiling_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(180))
			var tilt: Basis = Basis(Vector3.RIGHT, actual_tilt)
			return ceiling_base * tilt  # Apply tilt AFTER flip

		TileOrientation.CEILING_TILT_NEG_X:
			# Ceiling tilted backward
			var ceiling_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(180))
			var tilt: Basis = Basis(Vector3.RIGHT, -actual_tilt)
			return ceiling_base * tilt

		# --- North/South Wall Tilts ---
		TileOrientation.WALL_NORTH_TILT_POS_Y:
			# North wall leaning right (toward +X)
			# Base: +90° around X (corrected WALL_NORTH)
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(90))
			var tilt: Basis = Basis(Vector3.UP, actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_NORTH_TILT_NEG_Y:
			# North wall leaning left (toward -X)
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(90))
			var tilt: Basis = Basis(Vector3.UP, -actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_NORTH_TILT_POS_X: 
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(90))
			var tilt: Basis = Basis(Vector3.RIGHT, actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_NORTH_TILT_NEG_X:
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(90))
			var tilt: Basis = Basis(Vector3.RIGHT, -actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_SOUTH_TILT_POS_Y:
			# South wall leaning right (toward +X)
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-180))
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(-90)) * rotation_correction
			var tilt: Basis = Basis(Vector3.UP, actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			# South wall leaning left (toward -X)
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-180))
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(-90)) * rotation_correction
			var tilt: Basis = Basis(Vector3.UP, -actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_SOUTH_TILT_POS_X: 
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-180))
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(-90)) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, actual_tilt)
			return tilt * wall_base

		TileOrientation.WALL_SOUTH_TILT_NEG_X:
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-180))
			var wall_base: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(-90)) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, -actual_tilt)
			return tilt * wall_base

		# --- East/West Wall Tilts ---
		TileOrientation.WALL_EAST_TILT_POS_X:
			# East wall leaning forward (toward +Z)
			# Base: +90° around Z (corrected WALL_EAST)
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_EAST_TILT_NEG_X:
			# East wall leaning backward (toward -Z)
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, -actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_EAST_TILT_POS_Y: 
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.FORWARD, actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_EAST_TILT_NEG_Y: 
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(-90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.FORWARD, -actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_WEST_TILT_POS_X:
			# West wall leaning forward (toward +Z)
			# Base: -90° around Z (corrected WALL_WEST)
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), -PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_WEST_TILT_NEG_X:
			# West wall leaning backward (toward -Z)
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), -PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.RIGHT, -actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_WEST_TILT_POS_Y: 
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), -PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.FORWARD, actual_tilt)
			return wall_base * tilt

		TileOrientation.WALL_WEST_TILT_NEG_Y: 
			var rotation_correction = Basis(Vector3(0, 1, 0), deg_to_rad(90))
			var wall_base: Basis = Basis(Vector3(0, 0, 1), -PI / 2.0) * rotation_correction
			var tilt: Basis = Basis(Vector3.FORWARD, -actual_tilt)
			return wall_base * tilt

		_:
			push_warning("Invalid orientation basis for rotation: ", orientation)
			return Basis.IDENTITY


## Returns the base (flat) plane orientation for any tile (e.g. FLOOR_TILT_POS_X -> FLOOR)
static func get_base_tile_orientation(orientation: int) -> TileOrientation:
	if ORIENTATION_DATA.has(orientation):
		return ORIENTATION_DATA[orientation]["base"]
	return orientation


## Returns the tilt sequence array for R key cycling: [flat, +tilt, -tilt]
static func get_tilt_sequence(orientation: int) -> Array:
	var base: int = get_base_tile_orientation(orientation)
	return TILT_SEQUENCES.get(base, [])




## Returns the closest world cardinal vector from a direction vector
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

## Returns non-uniform scale vector for 45-degree gap compensation and depth scaling.
## Pass scale_factor=0.0 to use GlobalConstants.DIAGONAL_SCALE_FACTOR.
static func get_scale_for_orientation(
	orientation: int,
	scale_factor: float = 0.0,
	mesh_mode: int = 0,
	depth_scale: float = 1.0
) -> Vector3:
	if not ORIENTATION_DATA.has(orientation):
		return Vector3.ONE

	var base_scale: Vector3 = ORIENTATION_DATA[orientation]["scale"]
	var depth_axis: String = ORIENTATION_DATA[orientation]["depth_axis"]

	# Start with base scale (handles diagonal tiles with pre-defined scale)
	var result: Vector3 = base_scale

	# Apply custom diagonal scale factor if provided (overrides ORIENTATION_DATA scale)
	if scale_factor != 0.0 and base_scale != Vector3.ONE:
		result = Vector3.ONE
		if base_scale.x != 1.0:
			result.x = scale_factor
		if base_scale.y != 1.0:
			result.y = scale_factor
		if base_scale.z != 1.0:
			result.z = scale_factor

	# Apply depth scaling for BOX/PRISM mesh modes
	# Always scale Y - BOX/PRISM meshes have thickness on local Y axis (Y=0 to Y=thickness)
	# The orientation rotation (applied AFTER scale) will place this on the correct world axis
	if depth_scale != 1.0:
		var is_box_or_prism: bool = (
			mesh_mode == GlobalConstants.MeshMode.BOX_MESH or
			mesh_mode == GlobalConstants.MeshMode.PRISM_MESH
		)
		if is_box_or_prism:
			result.y *= depth_scale

	return result


## Returns the position offset for tilted orientations.
## Pass offset_factor=0.0 to use GlobalConstants.TILT_POSITION_OFFSET_FACTOR.
static func get_tilt_offset_for_orientation(orientation: int, grid_size: float, offset_factor: float = 0.0) -> Vector3:
	if not ORIENTATION_DATA.has(orientation):
		return Vector3.ZERO

	var offset_axis: String = ORIENTATION_DATA[orientation]["tilt_offset_axis"]
	if offset_axis.is_empty():
		return Vector3.ZERO  # Flat orientations have no offset

	# Use provided offset_factor or default to GlobalConstants
	var actual_factor: float = offset_factor if offset_factor != 0.0 else GlobalConstants.TILT_POSITION_OFFSET_FACTOR
	var offset_value: float = grid_size * actual_factor

	match offset_axis:
		"x": return Vector3(offset_value, 0, 0)
		"y": return Vector3(0, offset_value, 0)
		"z": return Vector3(0, 0, offset_value)
		_: return Vector3.ZERO


## Returns orientation-aware tolerance vector for area selection/erase.
## Uses small depth tolerance on the depth axis, full tolerance on plane axes.
static func get_orientation_tolerance(orientation: int, tolerance: float) -> Vector3:
	var depth_tolerance: float = GlobalConstants.AREA_ERASE_DEPTH_TOLERANCE

	if not ORIENTATION_DATA.has(orientation):
		push_warning("GlobalUtil.get_orientation_tolerance(): Unknown orientation %d, using FLOOR tolerance" % orientation)
		return Vector3(tolerance, depth_tolerance, tolerance)

	var depth_axis: String = ORIENTATION_DATA[orientation]["depth_axis"]

	match depth_axis:
		"x": return Vector3(depth_tolerance, tolerance, tolerance)  # YZ plane, X is depth
		"y": return Vector3(tolerance, depth_tolerance, tolerance)  # XZ plane, Y is depth
		"z": return Vector3(tolerance, tolerance, depth_tolerance)  # XY plane, Z is depth
		_: return Vector3(tolerance, depth_tolerance, tolerance)    # Fallback



# --- Transform Construction ---

## SINGLE SOURCE OF TRUTH for tile transform construction.
## Transform order (DO NOT CHANGE): Scale -> Orient -> Rotate.
## Pass 0.0 for spin/tilt/scale/offset to use GlobalConstants defaults.
static func build_tile_transform(
	grid_pos: Vector3,
	orientation: int,
	mesh_rotation: int,
	grid_size: float,
	is_face_flipped: bool = false,
	spin_angle: float = 0.0,
	tilt_angle: float = 0.0,
	scale_factor: float = 0.0,
	offset_factor: float = 0.0,
	mesh_mode: int = 0,
	depth_scale: float = 1.0,
) -> Transform3D:
	var transform: Transform3D = Transform3D()

	# Step 1: Get scale vector (includes diagonal scale and depth scale for BOX/PRISM)
	var scale_vector: Vector3 = get_scale_for_orientation(orientation, scale_factor, mesh_mode, depth_scale)

	# For triangular mesh types: swap X/Z scale when mesh rotation is odd (1 or 3).
	# Odd rotations (90°/270°) swap which triangle leg faces the tilt axis,
	# so the diagonal scale must follow by swapping X↔Z to prevent skew/distortion.
	# Square/Box meshes are symmetric and don't need this correction.
	var is_triangle_shape: bool = (
		mesh_mode == GlobalConstants.MeshMode.FLAT_TRIANGULE or
		mesh_mode == GlobalConstants.MeshMode.PRISM_MESH
	)
	if is_triangle_shape and mesh_rotation % 2 == 1:
		scale_vector = Vector3(scale_vector.z, scale_vector.y, scale_vector.x)

	var scale_basis: Basis = Basis.from_scale(scale_vector)

	# Step 2: Get orientation basis (passes tilt_angle - 0.0 means use GlobalConstants)
	var orientation_basis: Basis = get_tile_rotation_basis(orientation, tilt_angle)

	# Step 3: Combine scale and orientation (ORDER MATTERS!)
	var combined_basis: Basis = orientation_basis * scale_basis

	# Step 4: Apply face flip (F key) if needed - BEFORE mesh rotation
	if is_face_flipped:
		var flip_basis: Basis = Basis.from_scale(Vector3(1, 1, -1))
		combined_basis = combined_basis * flip_basis

	# Step 5: Apply mesh rotation (Q/E) - passes spin_angle (0.0 means use GlobalConstants)
	if mesh_rotation > 0:
		combined_basis = apply_mesh_rotation(combined_basis, orientation, mesh_rotation, spin_angle)

	# Step 6: Calculate world position
	var world_pos: Vector3 = grid_to_world(grid_pos, grid_size)

	# Step 7: Apply tilt offset (passes offset_factor - 0.0 means use GlobalConstants)
	if orientation >= TileOrientation.FLOOR_TILT_POS_X:
		var tilt_offset: Vector3 = get_tilt_offset_for_orientation(orientation, grid_size, offset_factor)
		world_pos += tilt_offset

	# Step 8: Set final transform
	transform.basis = combined_basis
	transform.origin = world_pos

	return transform

# --- Mesh Rotation ---

## Returns the surface normal for an orientation (axis perpendicular to tile plane)
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

		# --- Tilted Floor/Ceiling ---
		# For 45° tilted surfaces, calculate the normal vector
		TileOrientation.FLOOR_TILT_POS_X, TileOrientation.FLOOR_TILT_NEG_X:
			# Tilted floor - normal is angled between UP and FORWARD/BACK
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()  # Y-axis of the basis is the surface normal

		TileOrientation.CEILING_TILT_POS_X, TileOrientation.CEILING_TILT_NEG_X:
			# Tilted ceiling - normal is angled between DOWN and FORWARD/BACK
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		# --- Tilted North/South Walls ---
		# Tile mesh is flat quad with normal along local Y+, so basis.y is surface normal
		TileOrientation.WALL_NORTH_TILT_POS_Y, TileOrientation.WALL_NORTH_TILT_NEG_Y:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_NORTH_TILT_POS_X, TileOrientation.WALL_NORTH_TILT_NEG_X:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_SOUTH_TILT_POS_Y, TileOrientation.WALL_SOUTH_TILT_NEG_Y:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_SOUTH_TILT_POS_X, TileOrientation.WALL_SOUTH_TILT_NEG_X:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		# --- Tilted East/West Walls ---
		TileOrientation.WALL_EAST_TILT_POS_X, TileOrientation.WALL_EAST_TILT_NEG_X:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_EAST_TILT_POS_Y, TileOrientation.WALL_EAST_TILT_NEG_Y:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_WEST_TILT_POS_X, TileOrientation.WALL_WEST_TILT_NEG_X:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		TileOrientation.WALL_WEST_TILT_POS_Y, TileOrientation.WALL_WEST_TILT_NEG_Y:
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		_:
			push_warning("Invalid axis orientation for rotation: ", orientation)
			return Vector3.UP

## Applies in-plane mesh rotation (Q/E) without changing which surface the tile is on.
## Pass spin_angle=0.0 to use GlobalConstants.SPIN_ANGLE_RAD.
static func apply_mesh_rotation(base_basis: Basis, orientation: int, rotation_steps: int, spin_angle: float = 0.0) -> Basis:
	if rotation_steps == 0:
		return base_basis

	# Get the rotation axis for this orientation (surface normal)
	var rotation_axis: Vector3 = get_rotation_axis_for_orientation(orientation)

	# Use provided spin_angle or default to GlobalConstants
	var actual_angle: float = spin_angle if spin_angle != 0.0 else GlobalConstants.SPIN_ANGLE_RAD

	# Calculate rotation angle per step
	var angle: float = float(rotation_steps) * actual_angle

	# Create rotation basis around world-aligned axis
	var rotation_basis: Basis = Basis(rotation_axis, angle)

	#   Apply rotation AFTER orientation
	# Order: orientation positions tile on surface, rotation rotates within that surface
	return rotation_basis * base_basis

# --- Grid and World Coordinate Conversion ---

## Converts grid coordinates to world position: (grid_pos + GRID_ALIGNMENT_OFFSET) * grid_size
static func grid_to_world(grid_pos: Vector3, grid_size: float) -> Vector3:
	return (grid_pos + GlobalConstants.GRID_ALIGNMENT_OFFSET) * grid_size

## Converts world position to grid coordinates (inverse of grid_to_world)
static func world_to_grid(world_pos: Vector3, grid_size: float) -> Vector3:
	return (world_pos / grid_size) - GlobalConstants.GRID_ALIGNMENT_OFFSET

# --- Spatial Region Utilities ---

## Calculates the spatial region key (CHUNK_REGION_SIZE cubes) from a world position
static func calculate_region_key(world_pos: Vector3) -> Vector3i:
	var region_size: float = GlobalConstants.CHUNK_REGION_SIZE
	return Vector3i(
		int(floor(world_pos.x / region_size)),
		int(floor(world_pos.y / region_size)),
		int(floor(world_pos.z / region_size))
	)


## Packs a Vector3i region key into a single 64-bit integer (20 bits per axis)
static func pack_region_key(region: Vector3i) -> int:
	const MASK_20BIT: int = 0xFFFFF  # 20 bits per axis = 1,048,575 max unsigned
	# Shift values to fit: x gets top 20 bits, y gets middle 20, z gets bottom 20
	return ((region.x & MASK_20BIT) << 40) | ((region.y & MASK_20BIT) << 20) | (region.z & MASK_20BIT)


## Unpacks a 64-bit packed region key back to Vector3i (inverse of pack_region_key)
static func unpack_region_key(packed_key: int) -> Vector3i:
	const MASK_20BIT: int = 0xFFFFF
	var x: int = (packed_key >> 40) & MASK_20BIT
	var y: int = (packed_key >> 20) & MASK_20BIT
	var z: int = packed_key & MASK_20BIT
	# Handle signed values (if high bit of 20-bit segment is set, it's negative)
	if x >= 0x80000:  # 2^19 = 524288
		x -= 0x100000  # 2^20
	if y >= 0x80000:
		y -= 0x100000
	if z >= 0x80000:
		z -= 0x100000
	return Vector3i(x, y, z)


## Returns the AABB for a spatial region (used for chunk frustum culling)
static func get_region_aabb(region: Vector3i) -> AABB:
	var size: float = GlobalConstants.CHUNK_REGION_SIZE
	var origin: Vector3 = Vector3(
		float(region.x) * size,
		float(region.y) * size,
		float(region.z) * size
	)
	return AABB(origin, Vector3(size, size, size))


## Converts world grid position to local position relative to a chunk's region origin
static func world_to_local_grid_pos(world_grid_pos: Vector3, region_key: Vector3i) -> Vector3:
	var region_size: float = GlobalConstants.CHUNK_REGION_SIZE
	var region_origin: Vector3 = Vector3(
		float(region_key.x) * region_size,
		float(region_key.y) * region_size,
		float(region_key.z) * region_size
	)
	return world_grid_pos - region_origin


## Converts local grid position back to world grid position (inverse of world_to_local_grid_pos)
static func local_to_world_grid_pos(local_grid_pos: Vector3, region_key: Vector3i) -> Vector3:
	var region_size: float = GlobalConstants.CHUNK_REGION_SIZE
	var region_origin: Vector3 = Vector3(
		float(region_key.x) * region_size,
		float(region_key.y) * region_size,
		float(region_key.z) * region_size
	)
	return local_grid_pos + region_origin


## Gets the world position for a chunk node based on its region key
static func get_chunk_world_position(region_key: Vector3i) -> Vector3:
	var region_size: float = GlobalConstants.CHUNK_REGION_SIZE
	return Vector3(
		float(region_key.x) * region_size,
		float(region_key.y) * region_size,
		float(region_key.z) * region_size
	)


# --- Tile Key Management ---

## Creates a unique 64-bit tile key from grid position and orientation
static func make_tile_key(grid_pos: Vector3, orientation: int) -> int:
	return TileKeySystem.make_tile_key_int(grid_pos, orientation)

## Parses a string tile key ("x,y,z,orientation") back into grid_pos and orientation
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

## Migrates Dictionary with string keys to integer keys (backward compatibility)
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

# --- Uv Coordinate Utilities ---

## Calculates normalized UV coordinates from pixel rect and atlas size.
## Returns Dictionary with "uv_min", "uv_max", and "uv_color" (packed for shader).
static func calculate_normalized_uv(uv_rect: Rect2, atlas_size: Vector2) -> Dictionary:
	var uv_min: Vector2 = uv_rect.position / atlas_size
	var uv_max: Vector2 = (uv_rect.position + uv_rect.size) / atlas_size

	# Apply half-pixel inset ONLY for real atlas textures (not 1x1 template meshes)
	# Template meshes use Vector2(1,1) as atlas_size which would cause 0.5 inset (too large)
	#THIS WAS REMOVED as was creating weird issues on some resolutions
	# if atlas_size.x > 1.0 and atlas_size.y > 1.0:
	# 	var half_pixel: Vector2 = Vector2(0.5, 0.5) / atlas_size
	# 	uv_min += half_pixel
	# 	uv_max -= half_pixel

	var uv_color: Color = Color(uv_min.x, uv_min.y, uv_max.x, uv_max.y)

	return {
		"uv_min": uv_min,
		"uv_max": uv_max,
		"uv_color": uv_color
	}


## Encodes freeze-UV rotation data into the custom_data alpha channel (uv_max.y).
## When freeze_uv is false, returns uv_max_y unchanged (backward compatible).
## When freeze_uv is true, encodes mesh_rotation as offset: uv_max_y + (rotation + 1) * 2.0
## Shader decodes: freeze_info = int(floor(a / 2.0)); actual_y = a - freeze_info * 2.0
static func encode_uv_freeze_rotation(uv_max_y: float, mesh_rotation: int, freeze_uv: bool) -> float:
	if not freeze_uv:
		return uv_max_y
	return uv_max_y + float(mesh_rotation + 1) * 2.0


## Transforms UV coordinates for baking to match runtime shader behavior.
## Applies Y-flip, horizontal flip, and rotation to replicate shader UV logic.
static func transform_uv_for_baking(uv: Vector2, mesh_rotation: int, is_flipped: bool) -> Vector2:
	var result: Vector2 = uv

	# Step 1: Apply base Y-flip to match shader behavior
	# Shader does: vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y)
	result.y = 1.0 - result.y

	# Step 2: Apply horizontal flip if face is flipped
	if is_flipped:
		result.x = 1.0 - result.x

	# Step 3: Apply rotation (counter-clockwise to match vertex rotation)
	match mesh_rotation:
		1:  # 90° CCW
			result = Vector2(result.y, 1.0 - result.x)
		2:  # 180°
			result = Vector2(1.0 - result.x, 1.0 - result.y)
		3:  # 270° CCW
			result = Vector2(1.0 - result.y, result.x)

	return result


# --- Mesh Geometry Helpers ---

## Appends triangle tile geometry to mesh arrays.
## uv_rect must be in NORMALIZED [0-1] coordinates (NOT pixel coordinates).
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

# --- Baked Mesh Material Creation ---

## Creates StandardMaterial3D for baked mesh exports
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

# --- Mesh Array Utilities ---

## Creates ArrayMesh from packed arrays with optional tangent generation
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

## Generates tangents using Godot's MikkTSpace algorithm (4 floats per vertex)
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

# --- Area Fill Utilities ---

## Returns all grid positions within a rectangular area on a specific plane.
## Supports fractional grid positions via snap_size (1.0 = full, 0.5 = half-grid).
static func get_grid_positions_in_area_with_snap(
	min_pos: Vector3,
	max_pos: Vector3,
	orientation: int,
	snap_size: float = 1.0
) -> Array[Vector3]:
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

	# Snap bounds to grid resolution using snappedf()
	# This ensures we capture the correct start/end positions for the given snap size
	var min_snapped: Vector3 = Vector3(
		snappedf(actual_min.x, snap_size),
		snappedf(actual_min.y, snap_size),
		snappedf(actual_min.z, snap_size)
	)
	var max_snapped: Vector3 = Vector3(
		snappedf(actual_max.x, snap_size),
		snappedf(actual_max.y, snap_size),
		snappedf(actual_max.z, snap_size)
	)

	# Calculate number of steps (inclusive range)
	# Use round() to handle floating point precision issues
	var calc_steps = func(min_val: float, max_val: float) -> int:
		return int(round((max_val - min_val) / snap_size)) + 1

	match orientation:
		TileOrientation.FLOOR, TileOrientation.CEILING:
			# Iterate over XZ plane at snap_size resolution
			var x_steps: int = calc_steps.call(min_snapped.x, max_snapped.x)
			var z_steps: int = calc_steps.call(min_snapped.z, max_snapped.z)
			for i in range(x_steps):
				var x: float = min_snapped.x + (i * snap_size)
				for j in range(z_steps):
					var z: float = min_snapped.z + (j * snap_size)
					positions.append(Vector3(x, actual_min.y, z))

		TileOrientation.WALL_NORTH, TileOrientation.WALL_SOUTH:
			# Iterate over XY plane at snap_size resolution
			var x_steps: int = calc_steps.call(min_snapped.x, max_snapped.x)
			var y_steps: int = calc_steps.call(min_snapped.y, max_snapped.y)
			for i in range(x_steps):
				var x: float = min_snapped.x + (i * snap_size)
				for j in range(y_steps):
					var y: float = min_snapped.y + (j * snap_size)
					positions.append(Vector3(x, y, actual_min.z))

		TileOrientation.WALL_EAST, TileOrientation.WALL_WEST:
			# Iterate over ZY plane at snap_size resolution
			var z_steps: int = calc_steps.call(min_snapped.z, max_snapped.z)
			var y_steps: int = calc_steps.call(min_snapped.y, max_snapped.y)
			for i in range(z_steps):
				var z: float = min_snapped.z + (i * snap_size)
				for j in range(y_steps):
					var y: float = min_snapped.y + (j * snap_size)
					positions.append(Vector3(actual_min.x, y, z))

		_:
			# Fallback: treat as floor (XZ plane)
			var x_steps: int = calc_steps.call(min_snapped.x, max_snapped.x)
			var z_steps: int = calc_steps.call(min_snapped.z, max_snapped.z)
			for i in range(x_steps):
				var x: float = min_snapped.x + (i * snap_size)
				for j in range(z_steps):
					var z: float = min_snapped.z + (j * snap_size)
					positions.append(Vector3(x, actual_min.y, z))

	return positions

## Creates a semi-transparent material for area fill selection box visualization
static func create_area_selection_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()

	# Semi-transparent cyan color
	material.albedo_color = GlobalConstants.AREA_FILL_BOX_COLOR

	# Enable alpha transparency
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Unshaded = bright, no lighting calculations
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Render on top of scene (use centralized constant)
	material.render_priority = GlobalConstants.AREA_FILL_RENDER_PRIORITY

	# Always visible (ignore depth buffer)
	material.no_depth_test = true

	# Visible from both sides
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	return material


## Creates an unshaded material for grid line visualization with vertex color support
static func create_grid_line_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()

	# Use provided color
	material.albedo_color = color

	# Enable alpha transparency
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Unshaded = bright, no lighting calculations
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Enable vertex colors for per-vertex color variation
	material.vertex_color_use_as_albedo = true

	# Render on top of tiles (use centralized constant)
	material.render_priority = GlobalConstants.GRID_OVERLAY_RENDER_PRIORITY

	return material


# --- Editor and Ui Scaling Utilities ---

## Returns the editor scale factor for DPI-aware UI sizing
static func get_editor_scale() -> float:
	if Engine.is_editor_hint():
		var ei: Object = Engine.get_singleton("EditorInterface")
		if ei:
			return ei.get_editor_scale()
	return 1.0


## Scales a Vector2i by the editor scale factor for DPI-aware dialog sizes
static func scale_ui_size(base_size: Vector2i) -> Vector2i:
	var scale: float = get_editor_scale()
	return Vector2i(int(base_size.x * scale), int(base_size.y * scale))


## Scales an integer value by the editor scale factor for DPI-aware margins/padding
static func scale_ui_value(base_value: int) -> int:
	return int(base_value * get_editor_scale())

static func get_editor_ui_scale() -> float:
	var ei: Object = Engine.get_singleton("EditorInterface")
	if ei:
		return ei.get_editor_scale()
	return 1.0

static func get_current_theme() -> Theme:
	var ei: Object = Engine.get_singleton("EditorInterface")
	if ei:
		return ei.get_editor_theme()
	return null

static func apply_button_theme(button: Button, icon_name: String, size:float) -> void:
	# Get editor scale and theme for proper sizing and icons
	if Engine.is_editor_hint():
		var ui_scale: float = get_editor_ui_scale()
		var editor_theme: Theme = null
		var ei: Object = Engine.get_singleton("EditorInterface")
		
		if ei:
			editor_theme = ei.get_editor_theme()

		# Set minimum width for toolbar and minimum size for buttons based on editor scale

		var icon_size = size * ui_scale
		button.custom_minimum_size = Vector2(icon_size, icon_size)

		button.add_theme_font_size_override("font_size", int(10 * ui_scale))

		if editor_theme and editor_theme.has_icon(icon_name, "EditorIcons"):
			button.icon = editor_theme.get_icon(icon_name, "EditorIcons")
		else:
			# Fallback to text if icon not found
			button.text = icon_name  # Use the name passed as text if icon is missing


# --- Animated Tile Utilities ---


## Compute animation frame dimensions from a TileAnimData resource.
## Returns a Dictionary with: strip_size, frame_pixel_w, frame_pixel_h,
## frame_tiles_x, frame_tiles_y, tiles_per_frame, anim_step_x, anim_step_y.
## atlas_size is needed for step computation (pass Vector2.ZERO to skip step calc).
## Returns empty Dictionary if anim_data is invalid.
static func compute_anim_frame_info(anim_data: TileAnimData, atlas_size: Vector2 = Vector2.ZERO) -> Dictionary:
	var result: Dictionary = {}
	if anim_data.selection_uv_rects.is_empty() or anim_data.columns <= 0 or anim_data.rows <= 0:
		return result
	if anim_data.base_tile_size.x <= 0.0 or anim_data.base_tile_size.y <= 0.0:
		return result

	# Bounding box of all selection rects
	var first: Rect2 = anim_data.selection_uv_rects[0]
	var min_pos: Vector2 = first.position
	var max_end: Vector2 = first.position + first.size
	for rect: Rect2 in anim_data.selection_uv_rects:
		min_pos.x = minf(min_pos.x, rect.position.x)
		min_pos.y = minf(min_pos.y, rect.position.y)
		max_end.x = maxf(max_end.x, rect.position.x + rect.size.x)
		max_end.y = maxf(max_end.y, rect.position.y + rect.size.y)

	var strip_size: Vector2 = max_end - min_pos
	var frame_pixel_w: float = strip_size.x / anim_data.columns
	var frame_pixel_h: float = strip_size.y / anim_data.rows
	var frame_tiles_x: int = int(roundf(frame_pixel_w / anim_data.base_tile_size.x))
	var frame_tiles_y: int = int(roundf(frame_pixel_h / anim_data.base_tile_size.y))

	result["strip_size"] = strip_size
	result["frame_pixel_w"] = frame_pixel_w
	result["frame_pixel_h"] = frame_pixel_h
	result["frame_tiles_x"] = frame_tiles_x
	result["frame_tiles_y"] = frame_tiles_y
	result["tiles_per_frame"] = frame_tiles_x * frame_tiles_y

	if atlas_size.x > 0.0 and atlas_size.y > 0.0:
		result["anim_step_x"] = frame_pixel_w / atlas_size.x
		result["anim_step_y"] = frame_pixel_h / atlas_size.y

	return result


## Extract the tiles that belong to frame 0 from a TileAnimData.
## selection_uv_rects is row-major across the ENTIRE strip (all frames).
## Frame 0 occupies the first frame_tiles_x columns of each row.
## For a 4×4 tree with 3 anim columns: strip is 12 cols × 4 rows,
## frame 0 = columns 0-3 from each row.
static func get_anim_frame0_tiles(anim_data: TileAnimData) -> Array[Rect2]:
	var info: Dictionary = compute_anim_frame_info(anim_data)
	if info.is_empty():
		return []
	var frame_tiles_x: int = info["frame_tiles_x"]
	var frame_tiles_y: int = info["frame_tiles_y"]
	var strip_tiles_x: int = frame_tiles_x * anim_data.columns
	var result: Array[Rect2] = []
	for row: int in range(frame_tiles_y):
		for col: int in range(frame_tiles_x):
			var idx: int = row * strip_tiles_x + col
			if idx < anim_data.selection_uv_rects.size():
				result.append(anim_data.selection_uv_rects[idx])
	return result

static func get_first_frame_texture(tileset_texture: Texture2D, anim_data: TileAnimData) -> Texture:
	if not tileset_texture:
		return null

	var scale : float = get_editor_ui_scale()
	var icon_size: int = GlobalConstants.BUTTOM_CONTEXT_UI_SIZE * scale

	#Get the entire area for the uv_rects
	var frame0_tiles: Array[Rect2] = get_anim_frame0_tiles(anim_data)

	var min_pos: Vector2 = frame0_tiles[0].position
	var max_end: Vector2 = frame0_tiles[0].position + frame0_tiles[0].size
	for rect: Rect2 in frame0_tiles:
		min_pos.x = minf(min_pos.x, rect.position.x)
		min_pos.y = minf(min_pos.y, rect.position.y)
		max_end.x = maxf(max_end.x, rect.position.x + rect.size.x)
		max_end.y = maxf(max_end.y, rect.position.y + rect.size.y)
	
	var tile_region: Rect2 = Rect2(min_pos, max_end - min_pos)
	var image = tileset_texture.get_image().get_region(tile_region) 
	# var image = tileset_texture.get_image().get_region(uv_rects[0])# This gets ONLY THE FIRST TILE. 

	image.resize(icon_size, icon_size)  # Resize to icon size for display
	var region_texture = ImageTexture.new().create_from_image(image)
	return region_texture