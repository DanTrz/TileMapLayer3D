@tool
class_name TileKeySystem
extends RefCounted


# Coordinate scaling factor - determines precision vs range trade-off
# COORD_SCALE=10 => Grid range of ±3,276.7 from origin (0.1 precision, half-grid OK)
# COORD_SCALE=100 => Grid range of ±327.67 from origin (0.01 precision)
# COORD_SCALE=1000 => Grid range of ±32.767 from origin (0.001 precision)
const COORD_SCALE: float = 10.0

const MAX_COORD: int = 32767
const MIN_COORD: int = -32768

const MASK_16BIT: int = 0xFFFF
const MASK_8BIT: int = 0xFF

static func make_tile_key_int(grid_pos: Vector3, orientation: int) -> int:
	# Convert to fixed-point integers (multiply by 1000 for 3 decimal precision)
	var ix: int = int(round(grid_pos.x * COORD_SCALE))
	var iy: int = int(round(grid_pos.y * COORD_SCALE))
	var iz: int = int(round(grid_pos.z * COORD_SCALE))

	ix = clampi(ix, MIN_COORD, MAX_COORD)
	iy = clampi(iy, MIN_COORD, MAX_COORD)
	iz = clampi(iz, MIN_COORD, MAX_COORD)

	ix = ix & MASK_16BIT
	iy = iy & MASK_16BIT
	iz = iz & MASK_16BIT

	var key: int = (ix << 48) | (iy << 32) | (iz << 16) | (orientation & MASK_8BIT)

	return key

static func unpack_tile_key(key: int) -> Dictionary:
	var ix: int = (key >> 48) & MASK_16BIT
	var iy: int = (key >> 32) & MASK_16BIT
	var iz: int = (key >> 16) & MASK_16BIT
	var ori: int = key & MASK_8BIT

	if ix >= 32768:
		ix -= 65536
	if iy >= 32768:
		iy -= 65536
	if iz >= 32768:
		iz -= 65536

	var pos: Vector3 = Vector3(
		float(ix) / COORD_SCALE,
		float(iy) / COORD_SCALE,
		float(iz) / COORD_SCALE
	)

	return {
		"position": pos,
		"orientation": ori
	}

static func migrate_string_key(string_key: String) -> int:
	var parts: PackedStringArray = string_key.split(",")

	if parts.size() != 4:
		push_warning("TileKeySystem: Invalid string key format: ", string_key)
		return -1

	var x: float = parts[0].to_float()
	var y: float = parts[1].to_float()
	var z: float = parts[2].to_float()
	var ori: int = parts[3].to_int()

	return make_tile_key_int(Vector3(x, y, z), ori)

static func key_to_string(key: int) -> String:
	var data: Dictionary = unpack_tile_key(key)
	var pos: Vector3 = data.position
	var ori: int = data.orientation

	return "%.3f,%.3f,%.3f,%d" % [pos.x, pos.y, pos.z, ori]

static func is_position_valid(grid_pos: Vector3) -> bool:
	var max_range: float = GlobalConstants.MAX_GRID_RANGE
	return (
		abs(grid_pos.x) <= max_range and
		abs(grid_pos.y) <= max_range and
		abs(grid_pos.z) <= max_range
	)

static func get_max_coordinate() -> float:
	return float(MAX_COORD) / COORD_SCALE

static func get_precision() -> float:
	return 1.0 / COORD_SCALE
