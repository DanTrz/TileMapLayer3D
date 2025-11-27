@tool
class_name TileKeySystem
extends RefCounted

## Integer-based tile key system for efficient tile position encoding.
##
## COORDINATE SYSTEM LIMITS:
## This system encodes 3D grid positions into 64-bit integer keys for O(1) lookups.
## Each axis uses 16-bit signed integers, limiting the grid coordinate range.
##
## Current Configuration (COORD_SCALE = 10.0):
##   - Grid Range: ±3,276.7 units from origin (0,0,0)
##   - Precision: 0.1 grid units (supports 0.5 half-grid positioning)
##   - World Range: ±3,276.7 × grid_size (e.g., with grid_size=1.0: ±3,276.7 meters)
##
## IMPORTANT: Tiles placed beyond ±3,276.7 grid units will experience:
##   - Coordinate clamping (tiles placed at wrong positions)
##   - Key collisions (multiple positions mapping to same key)
##   - Visual artifacts and placement failures
##
## The minimum supported snap size is 0.5 (half-grid). Smaller snap sizes
## (0.25, 0.125) are NOT supported with this configuration.
##
## See GlobalConstants.MAX_GRID_RANGE, MIN_SNAP_SIZE, GRID_PRECISION for limits.

# Coordinate scaling factor - determines precision vs range trade-off
# COORD_SCALE=10 => Grid range of ±3,276.7 from origin (0.1 precision, half-grid OK)
# COORD_SCALE=100 => Grid range of ±327.67 from origin (0.01 precision)
# COORD_SCALE=1000 => Grid range of ±32.767 from origin (0.001 precision)
const COORD_SCALE: float = 10.0

# Maximum coordinate value (16-bit signed: -32768 to 32767)
const MAX_COORD: int = 32767
const MIN_COORD: int = -32768

# Bit masks for packing/unpacking
const MASK_16BIT: int = 0xFFFF
const MASK_8BIT: int = 0xFF

##  Creates integer tile key from grid position and orientation
## @param grid_pos: Grid position (supports fractional values)
## @param orientation: Tile orientation (0-17)
## @returns: 64-bit integer key
static func make_tile_key_int(grid_pos: Vector3, orientation: int) -> int:
	# Convert to fixed-point integers (multiply by 1000 for 3 decimal precision)
	var ix: int = int(round(grid_pos.x * COORD_SCALE))
	var iy: int = int(round(grid_pos.y * COORD_SCALE))
	var iz: int = int(round(grid_pos.z * COORD_SCALE))

	# Clamp to valid range to prevent overflow
	ix = clampi(ix, MIN_COORD, MAX_COORD)
	iy = clampi(iy, MIN_COORD, MAX_COORD)
	iz = clampi(iz, MIN_COORD, MAX_COORD)

	# Apply 16-bit mask to handle negative numbers correctly
	ix = ix & MASK_16BIT
	iy = iy & MASK_16BIT
	iz = iz & MASK_16BIT

	# Pack into 64-bit integer
	# Note: In GDScript, left shift on 64-bit int works correctly
	var key: int = (ix << 48) | (iy << 32) | (iz << 16) | (orientation & MASK_8BIT)

	return key

## Unpacks integer tile key back to grid position and orientation
## Used for debugging and migration
## @param key: 64-bit integer key
## @returns: Dictionary with "position" (Vector3) and "orientation" (int)
static func unpack_tile_key(key: int) -> Dictionary:
	# Extract packed values
	var ix: int = (key >> 48) & MASK_16BIT
	var iy: int = (key >> 32) & MASK_16BIT
	var iz: int = (key >> 16) & MASK_16BIT
	var ori: int = key & MASK_8BIT

	# Convert from 16-bit unsigned to signed
	if ix >= 32768:
		ix -= 65536
	if iy >= 32768:
		iy -= 65536
	if iz >= 32768:
		iz -= 65536

	# Convert from fixed-point to float
	var pos: Vector3 = Vector3(
		float(ix) / COORD_SCALE,
		float(iy) / COORD_SCALE,
		float(iz) / COORD_SCALE
	)

	return {
		"position": pos,
		"orientation": ori
	}

## Migrates old string key to new integer key
## Used for backward compatibility when loading old scenes
## @param string_key: Old format "x,y,z,orientation"
## @returns: Integer key, or -1 if parsing fails
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

## DEBUG: Converts integer key to readable string for debugging
## @param key: 64-bit integer key
## @returns: String representation "x,y,z,ori"
static func key_to_string(key: int) -> String:
	var data: Dictionary = unpack_tile_key(key)
	var pos: Vector3 = data.position
	var ori: int = data.orientation

	return "%.3f,%.3f,%.3f,%d" % [pos.x, pos.y, pos.z, ori]

## Validates if coordinates are within supported range
## Uses GlobalConstants.MAX_GRID_RANGE for the limit check
## @param grid_pos: Grid position to validate
## @returns: true if position is within valid range, false if out of range
static func is_position_valid(grid_pos: Vector3) -> bool:
	var max_range: float = GlobalConstants.MAX_GRID_RANGE
	return (
		abs(grid_pos.x) <= max_range and
		abs(grid_pos.y) <= max_range and
		abs(grid_pos.z) <= max_range
	)

## Returns the maximum grid coordinate that can be encoded
## @returns: Maximum coordinate value (±32.767)
static func get_max_coordinate() -> float:
	return float(MAX_COORD) / COORD_SCALE

## Returns the coordinate precision (smallest representable difference)
## @returns: Precision value (0.001)
static func get_precision() -> float:
	return 1.0 / COORD_SCALE
