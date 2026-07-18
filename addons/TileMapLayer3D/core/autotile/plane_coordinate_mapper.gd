@tool
class_name PlaneCoordinateMapper
extends RefCounted


const PLANE_AXES: Dictionary = {
	GlobalUtil.TileOrientation.FLOOR:      {"h_axis": "x", "v_axis": "z", "h_flip": false, "v_flip": false},
	GlobalUtil.TileOrientation.CEILING:    {"h_axis": "x", "v_axis": "z", "h_flip": false, "v_flip": true},
	# Walls need v_flip: true because 2D Y increases downward but 3D Y increases upward
	# Walls need h_flip swapped to compensate for the -90° X rotation in tile geometry
	# (the rotation flips the horizontal UV, so we invert the h_flip logic)
	GlobalUtil.TileOrientation.WALL_NORTH: {"h_axis": "x", "v_axis": "y", "h_flip": false,  "v_flip": true},
	GlobalUtil.TileOrientation.WALL_SOUTH: {"h_axis": "x", "v_axis": "y", "h_flip": true, "v_flip": true},
	GlobalUtil.TileOrientation.WALL_EAST:  {"h_axis": "z", "v_axis": "y", "h_flip": false,  "v_flip": true},
	GlobalUtil.TileOrientation.WALL_WEST:  {"h_axis": "z", "v_axis": "y", "h_flip": true,  "v_flip": true},
}

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

const BITMASK_VALUES: Dictionary = {
	"N": 1,
	"E": 2,
	"S": 4,
	"W": 8,
	"NE": 16,
	"SE": 32,
	"SW": 64,
	"NW": 128,
}


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


static func offset_to_3d(offset_2d: Vector2i, orientation: int, only_base_orientations: bool = true) -> Vector3:
	var lookup_orientation: int = orientation
	if not only_base_orientations:
		var entry: Dictionary = GlobalUtil.ORIENTATION_DATA.get(orientation, {})
		lookup_orientation = entry.get("base", orientation)
	var axes: Dictionary = PLANE_AXES.get(lookup_orientation, PLANE_AXES[GlobalUtil.TileOrientation.FLOOR])
	var result: Vector3 = Vector3.ZERO

	var h: int = offset_2d.x
	var v: int = offset_2d.y

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


static func get_neighbor_positions_3d(grid_pos: Vector3, orientation: int) -> Array[Vector3]:
	var neighbors: Array[Vector3] = []
	for dir_name: String in NEIGHBOR_OFFSETS_2D.keys():
		var offset_2d: Vector2i = NEIGHBOR_OFFSETS_2D[dir_name]
		var offset_3d: Vector3 = offset_to_3d(offset_2d, orientation)
		neighbors.append(grid_pos + offset_3d)
	return neighbors


static func get_neighbor_position_3d(grid_pos: Vector3, orientation: int, direction: String) -> Vector3:
	if not NEIGHBOR_OFFSETS_2D.has(direction):
		return grid_pos
	var offset_2d: Vector2i = NEIGHBOR_OFFSETS_2D[direction]
	var offset_3d: Vector3 = offset_to_3d(offset_2d, orientation)
	return grid_pos + offset_3d


static func get_direction_names() -> Array[String]:
	var names: Array[String] = []
	for dir: String in NEIGHBOR_OFFSETS_2D.keys():
		names.append(dir)
	return names


static func get_bitmask_for_direction(direction: String) -> int:
	return BITMASK_VALUES.get(direction, 0)


static func is_supported_orientation(orientation: int) -> bool:
	return PLANE_AXES.has(orientation)


static func get_axes_config(orientation: int) -> Dictionary:
	return PLANE_AXES.get(orientation, PLANE_AXES[GlobalUtil.TileOrientation.FLOOR])
