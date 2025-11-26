# =============================================================================
# FILE: addons/TileMapLayer3D/core/autotile/plane_coordinate_mapper.gd
# PURPOSE: Transform coordinates between 3D grid space and 2D plane space
# DEPENDENCIES: GlobalUtil (for TileOrientation enum)
# =============================================================================
@tool
class_name PlaneCoordinateMapper
extends RefCounted

## Transforms 3D grid coordinates to 2D plane coordinates.
## This is the KEY class that makes 2D autotiling work in 3D.
##
## Each 3D orientation (FLOOR, WALL_NORTH, etc.) maps to a 2D plane.
## This class handles the axis mapping and flipping for each orientation.
##
## Supported orientations (6 total):
##   FLOOR (0), CEILING (1), WALL_NORTH (2), WALL_SOUTH (3), WALL_EAST (4), WALL_WEST (5)

# Plane axis configuration per orientation
# h_axis: Which 3D axis maps to 2D horizontal (X)
# v_axis: Which 3D axis maps to 2D vertical (Y)
# h_flip: Whether to flip horizontal axis
# v_flip: Whether to flip vertical axis
const PLANE_AXES: Dictionary = {
	GlobalUtil.TileOrientation.FLOOR:      {"h_axis": "x", "v_axis": "z", "h_flip": false, "v_flip": false},
	GlobalUtil.TileOrientation.CEILING:    {"h_axis": "x", "v_axis": "z", "h_flip": false, "v_flip": false},
	# Walls need v_flip: true because 2D Y increases downward but 3D Y increases upward
	# Walls need h_flip swapped to compensate for the -90° X rotation in tile geometry
	# (the rotation flips the horizontal UV, so we invert the h_flip logic)
	GlobalUtil.TileOrientation.WALL_NORTH: {"h_axis": "x", "v_axis": "y", "h_flip": true,  "v_flip": true},
	GlobalUtil.TileOrientation.WALL_SOUTH: {"h_axis": "x", "v_axis": "y", "h_flip": false, "v_flip": true},
	GlobalUtil.TileOrientation.WALL_EAST:  {"h_axis": "z", "v_axis": "y", "h_flip": true,  "v_flip": true},
	GlobalUtil.TileOrientation.WALL_WEST:  {"h_axis": "z", "v_axis": "y", "h_flip": false, "v_flip": true},
}

## Standard 2D neighbor offsets for 8-directional autotiling
## These are used in 2D space, then converted to 3D via offset_to_3d()
const NEIGHBOR_OFFSETS_2D: Dictionary = {
	"N":  Vector2i(0, -1),
	"NE": Vector2i(1, -1),
	"E":  Vector2i(1, 0),
	"SE": Vector2i(1, 1),
	"S":  Vector2i(0, 1),
	"SW": Vector2i(-1, 1),
	"W":  Vector2i(-1, 0),
	"NW": Vector2i(-1, -1),
}

## Bitmask values for each direction (matches TileSetBitmaskMapper)
const BITMASK_VALUES: Dictionary = {
	"N": 1, "E": 2, "S": 4, "W": 8,
	"NE": 16, "SE": 32, "SW": 64, "NW": 128,
}


## Convert 3D grid position to 2D plane position
## Returns Vector2i representing position on the 2D autotiling plane
static func to_2d(grid_pos: Vector3, orientation: int) -> Vector2i:
	var axes: Dictionary = PLANE_AXES.get(orientation, PLANE_AXES[GlobalUtil.TileOrientation.FLOOR])

	var h: int = 0
	var v: int = 0

	match axes.h_axis:
		"x": h = roundi(grid_pos.x)
		"y": h = roundi(grid_pos.y)
		"z": h = roundi(grid_pos.z)

	match axes.v_axis:
		"x": v = roundi(grid_pos.x)
		"y": v = roundi(grid_pos.y)
		"z": v = roundi(grid_pos.z)

	if axes.h_flip:
		h = -h
	if axes.v_flip:
		v = -v

	return Vector2i(h, v)


## Convert 2D offset to 3D offset (for neighbor lookup)
## Takes a 2D neighbor offset and returns the corresponding 3D offset
static func offset_to_3d(offset_2d: Vector2i, orientation: int) -> Vector3:
	var axes: Dictionary = PLANE_AXES.get(orientation, PLANE_AXES[GlobalUtil.TileOrientation.FLOOR])
	var result: Vector3 = Vector3.ZERO

	var h: int = offset_2d.x
	var v: int = offset_2d.y

	# Apply flip (reverse the flip for offset conversion)
	if axes.h_flip:
		h = -h
	if axes.v_flip:
		v = -v

	match axes.h_axis:
		"x": result.x = float(h)
		"y": result.y = float(h)
		"z": result.z = float(h)

	match axes.v_axis:
		"x": result.x = float(v)
		"y": result.y = float(v)
		"z": result.z = float(v)

	return result


## Get all 8 neighbor positions in 3D for a given grid position and orientation
## Returns array of 8 Vector3 positions in order: N, NE, E, SE, S, SW, W, NW
static func get_neighbor_positions_3d(grid_pos: Vector3, orientation: int) -> Array[Vector3]:
	var neighbors: Array[Vector3] = []
	for dir_name: String in NEIGHBOR_OFFSETS_2D.keys():
		var offset_2d: Vector2i = NEIGHBOR_OFFSETS_2D[dir_name]
		var offset_3d: Vector3 = offset_to_3d(offset_2d, orientation)
		neighbors.append(grid_pos + offset_3d)
	return neighbors


## Get a single neighbor position by direction name
static func get_neighbor_position_3d(grid_pos: Vector3, orientation: int, direction: String) -> Vector3:
	if not NEIGHBOR_OFFSETS_2D.has(direction):
		return grid_pos
	var offset_2d: Vector2i = NEIGHBOR_OFFSETS_2D[direction]
	var offset_3d: Vector3 = offset_to_3d(offset_2d, orientation)
	return grid_pos + offset_3d


## Get direction names in order (for iteration)
static func get_direction_names() -> Array[String]:
	var names: Array[String] = []
	for dir: String in NEIGHBOR_OFFSETS_2D.keys():
		names.append(dir)
	return names


## Get bitmask value for a direction
static func get_bitmask_for_direction(direction: String) -> int:
	return BITMASK_VALUES.get(direction, 0)


## Check if an orientation is supported for autotiling
static func is_supported_orientation(orientation: int) -> bool:
	return PLANE_AXES.has(orientation)


## Get the axes configuration for an orientation
static func get_axes_config(orientation: int) -> Dictionary:
	return PLANE_AXES.get(orientation, PLANE_AXES[GlobalUtil.TileOrientation.FLOOR])
