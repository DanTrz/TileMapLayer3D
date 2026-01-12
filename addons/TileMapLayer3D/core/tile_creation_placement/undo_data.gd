@tool
class_name UndoData
extends RefCounted

## Compressed bulk storage for area undo/redo operations
## Uses PackedByteArray with ZSTD compression for efficient memory usage
##
## Format: 52 bytes per tile (packed binary):
## - Position: Vector3 (12 bytes: 3x float32)
## - UV Rect: Rect2 (8 bytes: 4x float16 half-precision)
## - Orientation: uint16 (2 bytes)
## - Rotation: uint16 (2 bytes)
## - Flip: uint8 (1 byte)
## - Mode: uint8 (1 byte)
## - Terrain ID: int16 (2 bytes)
## - spin_angle_rad: float32 (4 bytes)
## - tilt_angle_rad: float32 (4 bytes)
## - diagonal_scale: float32 (4 bytes)
## - tilt_offset_factor: float32 (4 bytes)
## - depth_scale: float32 (4 bytes)
## - Padding: 4 bytes (alignment to 8 bytes)
##
## With ZSTD compression: ~60-80% size reduction on repetitive data
##
## Example: 1000 tiles = 52KB uncompressed -> ~10-18KB compressed

const BYTES_PER_TILE: int = 52

class UndoAreaData:
	extends RefCounted

	var tiles: PackedByteArray = PackedByteArray()  # Compressed tile data
	var count: int = 0  # Number of tiles stored

	## Create compressed area data from tile info array
	## @param tiles_array: Array of dictionaries with tile data fields
	## @returns: Compressed UndoAreaData instance
	static func from_tiles(tiles_array: Array) -> UndoAreaData:
		var area_data: UndoAreaData = UndoAreaData.new()
		area_data.count = tiles_array.size()

		if area_data.count == 0:
			return area_data

		# Pack data into bytes (52 bytes per tile)
		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(tiles_array.size() * BYTES_PER_TILE)

		var offset: int = 0
		for tile_info in tiles_array:
			# Pack position (12 bytes - 3 floats)
			bytes.encode_float(offset, tile_info.grid_pos.x)
			bytes.encode_float(offset + 4, tile_info.grid_pos.y)
			bytes.encode_float(offset + 8, tile_info.grid_pos.z)

			# Pack UV rect (8 bytes - 4 half-floats for compact storage)
			bytes.encode_half(offset + 12, tile_info.uv_rect.position.x)
			bytes.encode_half(offset + 14, tile_info.uv_rect.position.y)
			bytes.encode_half(offset + 16, tile_info.uv_rect.size.x)
			bytes.encode_half(offset + 18, tile_info.uv_rect.size.y)

			# Pack basic tile data (8 bytes)
			bytes.encode_u16(offset + 20, tile_info.orientation)
			bytes.encode_u16(offset + 22, tile_info.rotation)
			bytes.encode_u8(offset + 24, 1 if tile_info.flip else 0)
			bytes.encode_u8(offset + 25, tile_info.mode)
			# Terrain ID as signed int16 (supports -1 for manual mode)
			bytes.encode_s16(offset + 26, tile_info.get("terrain_id", GlobalConstants.AUTOTILE_NO_TERRAIN))

			# Pack transform parameters (20 bytes - 5 floats)
			bytes.encode_float(offset + 28, tile_info.get("spin_angle_rad", 0.0))
			bytes.encode_float(offset + 32, tile_info.get("tilt_angle_rad", 0.0))
			bytes.encode_float(offset + 36, tile_info.get("diagonal_scale", 0.0))
			bytes.encode_float(offset + 40, tile_info.get("tilt_offset_factor", 0.0))
			bytes.encode_float(offset + 44, tile_info.get("depth_scale", 1.0))
			# Use padding byte 48 for texture_repeat_mode (0=DEFAULT, 1=REPEAT)
			bytes.encode_u8(offset + 48, tile_info.get("texture_repeat_mode", 0))
			# Bytes 49-51 remain as padding for alignment

			offset += BYTES_PER_TILE

		# Compress with ZSTD (best compression ratio for repetitive data)
		area_data.tiles = bytes.compress(FileAccess.COMPRESSION_ZSTD)
		return area_data

	## Decompress and restore tile info array
	## @returns: Array of tile info dictionaries
	func to_tiles() -> Array:
		if count == 0:
			return []

		# Decompress
		var decompressed: PackedByteArray = tiles.decompress(count * BYTES_PER_TILE, FileAccess.COMPRESSION_ZSTD)
		var result: Array = []

		var offset: int = 0
		for i in range(count):
			var tile_info: Dictionary = {}

			# Unpack position
			tile_info.grid_pos = Vector3(
				decompressed.decode_float(offset),
				decompressed.decode_float(offset + 4),
				decompressed.decode_float(offset + 8)
			)

			# Unpack UV rect
			tile_info.uv_rect = Rect2(
				decompressed.decode_half(offset + 12),
				decompressed.decode_half(offset + 14),
				decompressed.decode_half(offset + 16),
				decompressed.decode_half(offset + 18)
			)

			# Unpack basic tile data
			tile_info.orientation = decompressed.decode_u16(offset + 20)
			tile_info.rotation = decompressed.decode_u16(offset + 22)
			tile_info.flip = decompressed.decode_u8(offset + 24) == 1
			tile_info.mode = decompressed.decode_u8(offset + 25)
			tile_info.terrain_id = decompressed.decode_s16(offset + 26)

			# Unpack transform parameters
			tile_info.spin_angle_rad = decompressed.decode_float(offset + 28)
			tile_info.tilt_angle_rad = decompressed.decode_float(offset + 32)
			tile_info.diagonal_scale = decompressed.decode_float(offset + 36)
			tile_info.tilt_offset_factor = decompressed.decode_float(offset + 40)
			tile_info.depth_scale = decompressed.decode_float(offset + 44)
			# Decode texture_repeat_mode from padding byte 48 (0=DEFAULT, 1=REPEAT)
			tile_info.texture_repeat_mode = decompressed.decode_u8(offset + 48)

			# Generate tile key from position and orientation
			tile_info.tile_key = GlobalUtil.make_tile_key(tile_info.grid_pos, tile_info.orientation)

			result.append(tile_info)
			offset += BYTES_PER_TILE

		return result

	## Returns uncompressed size in bytes (for statistics)
	## @returns: Uncompressed data size
	func get_uncompressed_size() -> int:
		return count * BYTES_PER_TILE

	## Returns compressed size in bytes (for statistics)
	## @returns: Compressed data size
	func get_compressed_size() -> int:
		return tiles.size()

	## Returns compression ratio (compressed / uncompressed)
	## @returns: Ratio between 0.0 and 1.0 (lower is better compression)
	func get_compression_ratio() -> float:
		var uncompressed: int = get_uncompressed_size()
		if uncompressed == 0:
			return 0.0
		return float(get_compressed_size()) / float(uncompressed)
