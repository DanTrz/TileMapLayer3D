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
static var _cached_shader_double_sided: Shader = null



## Creates a StandardMaterial3D configured for unshaded rendering
## Single source of truth for simple unshaded materials used throughout the plugin.
##
## This replaces duplicate StandardMaterial3D creation code across:
## - TilePreview3D (grid indicators)
## - TileCursor3D (cursor center and axis lines)
## - CursorPlaneVisualizer (grid overlays)
## - AreaFillSelector3D (selection box)
##
## @param color: Albedo color (alpha determines transparency)
## @param cull_disabled: Whether to render both sides (default: false)
## @param render_priority: Material render priority (default: DEFAULT_RENDER_PRIORITY)
## @returns: StandardMaterial3D configured for unshaded, transparent rendering
##
## Example:
##   var material = GlobalUtil.create_unshaded_material(Color(1, 0.8, 0, 0.9))
##   indicator_mesh.material_override = material
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
		material.set_shader_parameter("albedo_texture", texture)
		material.set_shader_parameter("debug_show_backfaces", debug_show_red_backfaces)

		# 0-1 = Nearest (manual UV snap in shader), 2-3 = Linear (hardware bilinear)
		var use_nearest: bool = (filter_mode == 0 or filter_mode == 1)
		material.set_shader_parameter("use_nearest_texture", use_nearest)

	return material


# ==============================================================================
# SIGNAL CONNECTION UTILITIES
# ==============================================================================
# Safe signal connection/disconnection helpers to reduce boilerplate
# and prevent "signal already connected" or "signal not connected" errors.

## Safely connects a signal if not already connected
## Prevents duplicate connection errors that can occur during node switching
##
## @param sig: The signal to connect
## @param callable: The handler function to connect
##
## Example:
##   GlobalUtil.safe_connect(node.some_signal, _on_some_signal)
static func safe_connect(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)

## Safely disconnects a signal if currently connected
## Prevents "not connected" errors when cleaning up signal handlers
##
## @param sig: The signal to disconnect
## @param callable: The handler function to disconnect
##
## Example:
##   GlobalUtil.safe_disconnect(old_node.some_signal, _on_some_signal)
static func safe_disconnect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)


# ==============================================================================
# ORIENTATION & TRANSFORM UTILITIES
# ==============================================================================

# =============================================================================
# TILE ORIENTATION ENUM - SINGLE SOURCE OF TRUTH
# =============================================================================
# This is the CANONICAL definition of TileOrientation used throughout the codebase.
# All other files should reference GlobalUtil.TileOrientation, NOT define their own.
# This includes the 6 base orientation and all other tilted versions
#
# =============================================================================
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

# =============================================================================
# ORIENTATION DATA - CENTRAL LOOKUP TABLE
# =============================================================================
# This table stores all properties for each orientation in ONE place.
# When adding a new orientation, add an entry here and to the enum above.
#
# Properties:
#   "base": The base (flat) orientation this tilted variant belongs to
#   "scale": Non-uniform scale for 45° gap compensation (√2 ≈ 1.414)
#   "depth_axis": Which axis is perpendicular to the tile plane (for tolerance)
#   "tilt_offset_axis": Which axis needs position offset for tilted tiles
# =============================================================================
const ORIENTATION_DATA: Dictionary = {
	# === FLOOR GROUP ===
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

	# === CEILING GROUP ===
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

	# === WALL NORTH GROUP ===
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

	# === WALL SOUTH GROUP ===
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

	# === WALL EAST GROUP ===
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


	# === WALL WEST GROUP ===
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

# =============================================================================
# TILT SEQUENCES - For R key cycling
# =============================================================================
# Maps base orientation to its tilt cycle sequence [flat, +tilt, -tilt]
# Used by cycle_tilt_forward() and cycle_tilt_backward()
# =============================================================================
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


# =============================================================================
# ORIENTATION CONFLICT DETECTION
# =============================================================================
# Functions to detect when two orientations occupy the same plane and would
# visually overlap if placed at the same grid position.
# Uses depth_axis from ORIENTATION_DATA - tiles with same depth_axis conflict.
# =============================================================================

## Returns the depth axis for an orientation ("x", "y", or "z")
## Used to determine if two orientations conflict (same depth_axis = conflict)
static func get_orientation_depth_axis(orientation: int) -> String:
	var data: Dictionary = ORIENTATION_DATA.get(orientation, {})
	return data.get("depth_axis", "")

## Checks if two orientations conflict (occupy same plane, would overlap)
## Only BASE orientations (0-5) can conflict - tilted tiles (6+) never conflict.
## Examples: FLOOR/CEILING both have depth_axis "y", so they conflict.
##           WALL_NORTH/WALL_SOUTH both have depth_axis "z", so they conflict.
##           FLOOR + FLOOR_TILT_POS_X do NOT conflict (tilted tile at angle).
static func orientations_conflict(orientation_a: int, orientation_b: int) -> bool:
	if orientation_a == orientation_b:
		return false  # Same orientation is handled separately (replacement)
	# Only base orientations (0-5) can conflict - tilted tiles (6+) never conflict
	if orientation_a > 5 or orientation_b > 5:
		return false
	var axis_a: String = get_orientation_depth_axis(orientation_a)
	var axis_b: String = get_orientation_depth_axis(orientation_b)
	return axis_a != "" and axis_a == axis_b

## Returns the opposite-facing orientation for backface painting
## Used to detect when painting on opposite walls/floors/ceilings
## Only supports base orientations (0-5) - tilted tiles (6+) are not coplanar
## @param orientation: Current tile orientation (0-25)
## @returns: Opposite orientation, or -1 if no opposite (tilted orientations)
static func get_opposite_orientation(orientation: int) -> int:
	match orientation:
		TileOrientation.FLOOR:        return TileOrientation.CEILING
		TileOrientation.CEILING:      return TileOrientation.FLOOR
		TileOrientation.WALL_NORTH:   return TileOrientation.WALL_SOUTH
		TileOrientation.WALL_SOUTH:   return TileOrientation.WALL_NORTH
		TileOrientation.WALL_EAST:    return TileOrientation.WALL_WEST
		TileOrientation.WALL_WEST:    return TileOrientation.WALL_EAST
		_: return -1  # Tilted orientations (6-25) are not coplanar - no backface painting

## Calculates default orientation offset for flat tiles
## Every flat tile gets a tiny offset along its surface normal
## This prevents Z-fighting when opposite-facing tiles are at same position
## @param orientation: Tile orientation (0-25)
## @param mesh_mode: Mesh type (only applies to FLAT_SQUARE/FLAT_TRIANGULE)
## @returns: Offset vector (Vector3.ZERO for non-flat tiles)
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


# =============================================================================
# ORIENTATION LOOKUP FUNCTIONS
# =============================================================================
# These functions use ORIENTATION_DATA for simple property lookups,
# replacing multiple large match statements with single table lookups.
# =============================================================================

## Converts orientation enum to rotation basis.
## This defines how each tile orientation is rotated in 3D space.
##
## @param orientation: TileOrientation enum value
## @param tilt_angle: Optional custom tilt angle in radians (0.0 = use GlobalConstants.TILT_ANGLE_RAD)
## @returns: Basis representing the orientation rotation
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

		# === FLOOR/CEILING TILTS (X-axis rotation for forward/backward ramps) ===
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

		# === NORTH/SOUTH WALL TILTS (Y-axis rotation for left/right lean) ===
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

		# === EAST/WEST WALL TILTS (X-axis rotation for forward/backward lean) ===
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


## Returns the base (flat) plane orientation for any tile
## Example: FLOOR_TILT_POS_X → FLOOR, WALL_NORTH → WALL_NORTH
static func get_base_tile_orientation(orientation: int) -> TileOrientation:
	if ORIENTATION_DATA.has(orientation):
		return ORIENTATION_DATA[orientation]["base"]
	return orientation


## Returns the tilt sequence array for a base orientation
## Used by R key cycling: [flat, +tilt, -tilt]
## Example: FLOOR → [FLOOR, FLOOR_TILT_POS_X, FLOOR_TILT_NEG_X]
static func get_tilt_sequence(orientation: int) -> Array:
	var base: int = get_base_tile_orientation(orientation)
	return TILT_SEQUENCES.get(base, [])




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
## Uses ORIENTATION_DATA lookup table for 45° gap compensation and depth scaling.
##
## @param orientation: TileOrientation enum value
## @param scale_factor: Optional custom scale factor for diagonal tiles (0.0 = use GlobalConstants.DIAGONAL_SCALE_FACTOR)
## @param mesh_mode: MeshMode enum value (0 = FLAT_SQUARE, 1 = FLAT_TRIANGLE, 2 = BOX_MESH, 3 = PRISM_MESH)
## @param depth_scale: Depth multiplier for BOX/PRISM modes (1.0 = default, no change)
## @returns: Vector3 scale (1.0 for unscaled axes, custom factors for scaled axes)
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


## Returns the position offset to apply for tilted orientations
## Uses ORIENTATION_DATA lookup table for tilt offset axis
##
## @param orientation: The tile orientation (0-17)
## @param grid_size: Grid cell size in world units
## @param offset_factor: Optional custom offset factor (0.0 = use GlobalConstants.TILT_POSITION_OFFSET_FACTOR)
## @return Vector3: The offset to add to tile position (Vector3.ZERO if not tilted)
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


## Returns orientation-aware tolerance vector for area selection/erase
## Uses ORIENTATION_DATA lookup table for depth axis
##
## @param orientation: The tile orientation (0-17)
## @param tolerance: The tolerance value for plane axes (typically 0.6)
## @return Vector3: Tolerance vector with small depth tolerance (0.15)
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
## SINGLE SOURCE OF TRUTH for building tile transforms.
## Handles both new tile placement and rebuild from saved data.
##
## @param grid_pos: Grid position of the tile
## @param orientation: TileOrientation enum value (0-25)
## @param mesh_rotation: Mesh rotation 0-3 (0°, 90°, 180°, 270°)
## @param grid_size: Grid cell size in world units
## @param is_face_flipped: Whether the tile face is flipped (F key)
## @param spin_angle: Saved spin angle (0.0 = use GlobalConstants.SPIN_ANGLE_RAD)
## @param tilt_angle: Saved tilt angle (0.0 = use GlobalConstants.TILT_ANGLE_RAD)
## @param scale_factor: Saved scale factor (0.0 = use GlobalConstants.DIAGONAL_SCALE_FACTOR)
## @param offset_factor: Saved offset factor (0.0 = use GlobalConstants.TILT_POSITION_OFFSET_FACTOR)
## @param mesh_mode: MeshMode enum value for depth scaling (0 = FLAT_SQUARE default)
## @param depth_scale: Depth multiplier for BOX/PRISM modes (1.0 = default, no change)
## @returns: Complete Transform3D for MultiMesh.set_instance_transform()
##
## Example usage (new placement - uses GlobalConstants):
##   var transform = GlobalUtil.build_tile_transform(pos, ori, rot, 1.0)
##
## Example usage (rebuild from saved - uses per-tile values):
##   var transform = GlobalUtil.build_tile_transform(
##       grid_pos, orientation, mesh_rotation, grid_size,
##       is_face_flipped, spin_angle, tilt_angle,
##       diagonal_scale, tilt_offset_factor, mesh_mode, depth_scale
##   )
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
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()  # Y-axis of the basis is the surface normal

		TileOrientation.CEILING_TILT_POS_X, TileOrientation.CEILING_TILT_NEG_X:
			# Tilted ceiling - normal is angled between DOWN and FORWARD/BACK
			var basis: Basis = get_tile_rotation_basis(orientation)
			return basis.y.normalized()

		# === TILTED NORTH/SOUTH WALLS ===
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

		# === TILTED EAST/WEST WALLS ===
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

## Applies mesh rotation to an existing orientation basis
## This rotates the tile within its plane WITHOUT changing which surface it's on
##
## @param base_basis: The orientation basis from get_tile_rotation_basis()
## @param orientation: TileOrientation enum value (to determine rotation axis)
## @param rotation_steps: Number of 90° rotations (0-3)
## @param spin_angle: Optional custom spin angle in radians (0.0 = use GlobalConstants.SPIN_ANGLE_RAD)
## @returns: Basis with in-plane rotation applied
##
## Example: For a FLOOR tile with 90° rotation:
##   base_basis = Basis.IDENTITY (horizontal)
##   rotation_axis = Vector3.UP (perpendicular to floor)
##   final_basis rotates tile 90° around Y axis while staying on floor
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
# SPATIAL REGION UTILITIES (Chunk Partitioning)
# ==============================================================================
# These functions support the dual-criteria spatial chunking system.
# Tiles are assigned to chunks based on:
#   1. Mesh type + texture repeat mode (existing)
#   2. Spatial region (new) - fixed NxNxN unit grid cells
#
# Benefits:
#   - Better frustum culling (per-region AABB vs. global)
#   - Localized GPU updates when editing nearby tiles
#   - More predictable memory layout for spatial queries
# ==============================================================================

## Calculates the spatial region key from a grid/world position
## Uses fixed CHUNK_REGION_SIZE cubes (default 50x50x50 units)
## Region (0,0,0) covers [0, CHUNK_REGION_SIZE) on each axis
## Region (-1,0,0) covers [-CHUNK_REGION_SIZE, 0) on X axis, etc.
##
## @param world_pos: Position in world/grid coordinates
## @returns: Vector3i representing region indices (rx, ry, rz)
static func calculate_region_key(world_pos: Vector3) -> Vector3i:
	var region_size: float = GlobalConstants.CHUNK_REGION_SIZE
	return Vector3i(
		int(floor(world_pos.x / region_size)),
		int(floor(world_pos.y / region_size)),
		int(floor(world_pos.z / region_size))
	)


## Packs a Vector3i region key into a single 64-bit integer for Dictionary efficiency
## Format: (rx & 0xFFFFF) << 40 | (ry & 0xFFFFF) << 20 | (rz & 0xFFFFF)
## Supports region indices from -524,288 to 524,287 on each axis (±26,214,400 units at 50u regions)
##
## @param region: Region key as Vector3i
## @returns: 64-bit packed integer key
static func pack_region_key(region: Vector3i) -> int:
	const MASK_20BIT: int = 0xFFFFF  # 20 bits per axis = 1,048,575 max unsigned
	# Shift values to fit: x gets top 20 bits, y gets middle 20, z gets bottom 20
	return ((region.x & MASK_20BIT) << 40) | ((region.y & MASK_20BIT) << 20) | (region.z & MASK_20BIT)


## Unpacks a 64-bit packed region key back to Vector3i
## Inverse of pack_region_key()
##
## @param packed_key: 64-bit packed integer key
## @returns: Vector3i region indices
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


## Calculates the AABB (Axis-Aligned Bounding Box) for a spatial region
## Used for setting chunk custom_aabb for optimal frustum culling
##
## @param region: Region key as Vector3i
## @returns: AABB covering the region's spatial extent
static func get_region_aabb(region: Vector3i) -> AABB:
	var size: float = GlobalConstants.CHUNK_REGION_SIZE
	var origin: Vector3 = Vector3(
		float(region.x) * size,
		float(region.y) * size,
		float(region.z) * size
	)
	return AABB(origin, Vector3(size, size, size))


## Converts world grid position to local position relative to a chunk's region
## Used when setting MultiMesh instance transforms (which are local to the chunk)
##
## Example: world_grid_pos=(55,0,10), region_key=(1,0,0)
##   → region_origin = (50,0,0)
##   → local = (55,0,10) - (50,0,0) = (5,0,10)
##
## @param world_grid_pos: Position in world grid coordinates
## @param region_key: The region this chunk belongs to (Vector3i)
## @returns: Position relative to region origin
static func world_to_local_grid_pos(world_grid_pos: Vector3, region_key: Vector3i) -> Vector3:
	var region_size: float = GlobalConstants.CHUNK_REGION_SIZE
	var region_origin: Vector3 = Vector3(
		float(region_key.x) * region_size,
		float(region_key.y) * region_size,
		float(region_key.z) * region_size
	)
	return world_grid_pos - region_origin


## Converts local grid position back to world grid position
## Used when reading transforms for collision, mesh baking, etc.
##
## Example: local_grid_pos=(5,0,10), region_key=(1,0,0)
##   → region_origin = (50,0,0)
##   → world = (5,0,10) + (50,0,0) = (55,0,10)
##
## @param local_grid_pos: Position relative to chunk's region origin
## @param region_key: The region this chunk belongs to
## @returns: Position in world grid coordinates
static func local_to_world_grid_pos(local_grid_pos: Vector3, region_key: Vector3i) -> Vector3:
	var region_size: float = GlobalConstants.CHUNK_REGION_SIZE
	var region_origin: Vector3 = Vector3(
		float(region_key.x) * region_size,
		float(region_key.y) * region_size,
		float(region_key.z) * region_size
	)
	return local_grid_pos + region_origin


## Gets the world position for a chunk based on its region key
## This is where the chunk's Node3D.position property should be set
##
## Example: region_key=(1,0,2) → world_position = (50,0,100)
##
## @param region_key: The region this chunk belongs to
## @returns: World position for the chunk node
static func get_chunk_world_position(region_key: Vector3i) -> Vector3:
	var region_size: float = GlobalConstants.CHUNK_REGION_SIZE
	return Vector3(
		float(region_key.x) * region_size,
		float(region_key.y) * region_size,
		float(region_key.z) * region_size
	)


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


## Transforms UV coordinates for baking to match runtime shader behavior
## The runtime shader applies: vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y)
## Then samples from uv_rect. We must replicate this + rotation/flip for baked meshes.
##
## @param uv: Original UV coordinate in [0,1] local space
## @param mesh_rotation: 0-3 (0°, 90°, 180°, 270°) - Q/E rotation steps
## @param is_flipped: Whether face is horizontally flipped (F key)
## @returns: Transformed UV coordinate ready for atlas remapping
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
# AREA FILL UTILITIES
# ==============================================================================

## Returns all grid positions within a rectangular area on a specific plane
## Calculates which grid cells are included in the area based on orientation
##
## @param min_pos: Vector3 - Minimum corner of selection area (inclusive)
## @param max_pos: Vector3 - Maximum corner of selection area (inclusive)
## @param orientation: int - Active plane orientation (0-5 for floor/ceiling/walls)
## Returns all grid positions within a rectangular area on a specific plane
## SUPPORTS FRACTIONAL GRID POSITIONS (half-grid snapping via snap_size parameter)
##
## @param min_pos: Minimum corner of selection area (inclusive)
## @param max_pos: Maximum corner of selection area (inclusive)
## @param orientation: Active plane orientation (0-5)
## @param snap_size: Grid snap resolution (1.0 = full grid, 0.5 = half-grid)
## @returns: Array[Vector3] - All grid positions in the area at snap_size resolution
##
## Example:
##   # Full grid (1.0 snap)
##   var positions = GlobalUtil.get_grid_positions_in_area_with_snap(Vector3(0,0,0), Vector3(2,0,2), 0, 1.0)
##   # Returns: [Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0), ...]
##
##   # Half grid (0.5 snap)
##   var positions = GlobalUtil.get_grid_positions_in_area_with_snap(Vector3(0,0,0), Vector3(2,0,2), 0, 0.5)
##   # Returns: [Vector3(0,0,0), Vector3(0.5,0,0), Vector3(1.0,0,0), Vector3(1.5,0,0), Vector3(2.0,0,0), ...]
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

	# Render on top of scene (use centralized constant)
	material.render_priority = GlobalConstants.AREA_FILL_RENDER_PRIORITY

	# Always visible (ignore depth buffer)
	material.no_depth_test = true

	# Visible from both sides
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	return material


## Creates a StandardMaterial3D for grid line visualization
## Used by CursorPlaneVisualizer and AreaFillSelector3D for grid overlays
##
## Properties:
##   - Customizable color (passed as parameter)
##   - Alpha transparency enabled
##   - Unshaded (bright, doesn't react to light)
##   - Vertex color enabled (for per-vertex color variation)
##   - High render priority (renders on top)
##
## @param color: Color - The color for grid lines (alpha determines transparency)
## @returns: StandardMaterial3D configured for grid line visualization
##
## Example:
##   var material = GlobalUtil.create_grid_line_material(Color(0.5, 0.5, 0.5, 0.5))
##   grid_mesh.material_override = material
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


# ==============================================================================
# EDITOR UTILITIES AND UI SCALING UTILITIES (DPI-aware)
# ==============================================================================

## Returns the editor scale factor for DPI-aware UI sizing
## The editor scale is set via Editor Settings → Interface → Editor → Display Scale
## Note: The editor must be restarted for scale changes to take effect
##
## @returns: Scale factor (1.0 = 100%, 1.5 = 150%, 2.0 = 200%)
##
## Usage:
##   var scale: float = GlobalUtil.get_editor_scale()
##   button.custom_minimum_size = Vector2(100, 30) * scale
static func get_editor_scale() -> float:
	if Engine.is_editor_hint():
		var ei: Object = Engine.get_singleton("EditorInterface")
		if ei:
			return ei.get_editor_scale()
	return 1.0


## Scales a Vector2i by the editor scale factor for dialog/window sizes
## Use this for popup_centered() calls to ensure dialogs scale with DPI
##
## @param base_size: Base size at 100% scale
## @returns: Scaled size based on current editor scale
##
## Usage:
##   dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_DEFAULT))
static func scale_ui_size(base_size: Vector2i) -> Vector2i:
	var scale: float = get_editor_scale()
	return Vector2i(int(base_size.x * scale), int(base_size.y * scale))


## Scales an integer value by the editor scale factor for margins/padding
## Use this for theme_override_constants and custom_minimum_size values
##
## @param base_value: Base value at 100% scale
## @returns: Scaled value based on current editor scale
##
## Usage:
##   margin.add_theme_constant_override("margin_left", GlobalUtil.scale_ui_value(4))
static func scale_ui_value(base_value: int) -> int:
	return int(base_value * get_editor_scale())

static func get_editor_ui_scale() -> float:
	var ei: Object = Engine.get_singleton("EditorInterface")
	if ei:
		return ei.get_editor_scale()
	return 1.0

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

