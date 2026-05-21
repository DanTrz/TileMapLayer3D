@tool
class_name UndoData
extends RefCounted

## Compressed bulk storage for area undo/redo operations
## Uses PackedByteArray with ZSTD compression for efficient memory usage
##
## V1 format (68 bytes per tile — legacy, read-only):
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
## - texture_repeat_mode: uint8 (1 byte)
## - anim_step_x: float16 (2 bytes)
## - anim_step_y: float16 (2 bytes)
## - anim_total_frames: uint8 (1 byte)
## - anim_columns: uint8 (1 byte)
## - anim_speed_fps: float16 (2 bytes)
## - atlas_source_id: int32 (4 bytes)
## - atlas_coords.x: int16 (2 bytes)
## - atlas_coords.y: int16 (2 bytes)
## - freeze_uv: uint8 (1 byte)
## - depth_growth_mode: uint8 (1 byte)
## - Padding: 1 byte
##
## V2 format (117 bytes per tile — current):
## Bytes 0-67: identical to V1
## Byte 67: has_custom_transform uint8
## Bytes 68-115: custom_transform (12x float32)
##   [68-71] basis.x.x  [72-75] basis.x.y  [76-79] basis.x.z
##   [80-83] basis.y.x  [84-87] basis.y.y  [88-91] basis.y.z
##   [92-95] basis.z.x  [96-99] basis.z.y  [100-103] basis.z.z
##   [104-107] origin.x [108-111] origin.y  [112-115] origin.z
## Byte 116: padding
##
## Version detection: compressed stream starts with 1-byte version marker.
## Version 2 = V2 format. No marker (or unknown) = V1 fallback.
##
## With ZSTD compression: ~60-80% size reduction on repetitive data

const BYTES_PER_TILE: int = 68
const BYTES_PER_TILE_V2: int = 117
const FORMAT_VERSION: int = 2

class UndoAreaData:
	extends RefCounted

	var tiles: PackedByteArray = PackedByteArray()  # Compressed tile data
	var count: int = 0  # Number of tiles stored

	static func from_tiles(tiles_array: Array[PlacedTileInfo]) -> UndoAreaData:
		var area_data: UndoAreaData = UndoAreaData.new()
		var normalized_tiles: Array[PlacedTileInfo] = []
		for tile_info: PlacedTileInfo in tiles_array:
			if tile_info != null:
				normalized_tiles.append(tile_info)

		area_data.count = normalized_tiles.size()

		if area_data.count == 0:
			return area_data

		# Pack data into bytes (V2: 1-byte version prefix + 117 bytes per tile)
		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(1 + area_data.count * BYTES_PER_TILE_V2)
		bytes.encode_u8(0, FORMAT_VERSION)

		var base: int = 1
		for tile_info in normalized_tiles:
			var o: int = base
			# Pack position (12 bytes - 3 floats)
			bytes.encode_float(o, tile_info.grid_pos.x)
			bytes.encode_float(o + 4, tile_info.grid_pos.y)
			bytes.encode_float(o + 8, tile_info.grid_pos.z)

			# Pack UV rect (8 bytes - 4 half-floats for compact storage)
			bytes.encode_half(o + 12, tile_info.uv_rect.position.x)
			bytes.encode_half(o + 14, tile_info.uv_rect.position.y)
			bytes.encode_half(o + 16, tile_info.uv_rect.size.x)
			bytes.encode_half(o + 18, tile_info.uv_rect.size.y)

			# Pack basic tile data (8 bytes)
			bytes.encode_u16(o + 20, tile_info.orientation)
			bytes.encode_u16(o + 22, tile_info.rotation)
			bytes.encode_u8(o + 24, 1 if tile_info.flip else 0)
			bytes.encode_u8(o + 25, tile_info.mode)
			# Terrain ID as signed int16 (supports -1 for manual mode)
			bytes.encode_s16(o + 26, tile_info.terrain_id)

			# Pack transform parameters (20 bytes - 5 floats)
			bytes.encode_float(o + 28, tile_info.spin_angle_rad)
			bytes.encode_float(o + 32, tile_info.tilt_angle_rad)
			bytes.encode_float(o + 36, tile_info.diagonal_scale)
			bytes.encode_float(o + 40, tile_info.tilt_offset_factor)
			bytes.encode_float(o + 44, tile_info.depth_scale)
			# texture_repeat_mode (1 byte)
			bytes.encode_u8(o + 48, tile_info.texture_repeat_mode)

			# Pack animation data (8 bytes: offsets 49-56)
			bytes.encode_half(o + 49, tile_info.anim_step_x)
			bytes.encode_half(o + 51, tile_info.anim_step_y)
			bytes.encode_u8(o + 53, clampi(tile_info.anim_total_frames, 0, 255))
			bytes.encode_u8(o + 54, clampi(tile_info.anim_columns, 0, 255))
			bytes.encode_half(o + 55, tile_info.anim_speed_fps)
			# Atlas binding (8 bytes: offsets 57-64)
			bytes.encode_s32(o + 57, tile_info.atlas_source_id)
			bytes.encode_s16(o + 61, tile_info.atlas_coords.x)
			bytes.encode_s16(o + 63, tile_info.atlas_coords.y)
			bytes.encode_u8(o + 65, 1 if tile_info.freeze_uv else 0)
			bytes.encode_u8(o + 66, tile_info.depth_growth_mode & 0x1)

			# V2 extension: custom transform (bytes 67-116)
			bytes.encode_u8(o + 67, 1 if tile_info.has_custom_transform else 0)
			var ct: Transform3D = tile_info.custom_transform
			bytes.encode_float(o + 68, ct.basis.x.x)
			bytes.encode_float(o + 72, ct.basis.x.y)
			bytes.encode_float(o + 76, ct.basis.x.z)
			bytes.encode_float(o + 80, ct.basis.y.x)
			bytes.encode_float(o + 84, ct.basis.y.y)
			bytes.encode_float(o + 88, ct.basis.y.z)
			bytes.encode_float(o + 92, ct.basis.z.x)
			bytes.encode_float(o + 96, ct.basis.z.y)
			bytes.encode_float(o + 100, ct.basis.z.z)
			bytes.encode_float(o + 104, ct.origin.x)
			bytes.encode_float(o + 108, ct.origin.y)
			bytes.encode_float(o + 112, ct.origin.z)
			# Byte 116: padding

			base += BYTES_PER_TILE_V2

		# Compress with ZSTD (best compression ratio for repetitive data)
		area_data.tiles = bytes.compress(FileAccess.COMPRESSION_ZSTD)
		return area_data

	func to_tiles() -> Array:
		if count == 0:
			return []

		# Try V2 first: decompress with version prefix + 117 bytes/tile
		var v2_size: int = 1 + count * BYTES_PER_TILE_V2
		var decompressed: PackedByteArray = tiles.decompress(v2_size, FileAccess.COMPRESSION_ZSTD)
		var is_v2: bool = decompressed.size() == v2_size and decompressed.decode_u8(0) == FORMAT_VERSION

		if not is_v2:
			# V1 fallback: no version prefix, 68 bytes/tile
			decompressed = tiles.decompress(count * BYTES_PER_TILE, FileAccess.COMPRESSION_ZSTD)

		var result: Array = []
		var base: int = 1 if is_v2 else 0

		for i: int in range(count):
			var tile_info := PlacedTileInfo.new()
			var o: int = base

			# Unpack position
			tile_info.grid_pos = Vector3(
				decompressed.decode_float(o),
				decompressed.decode_float(o + 4),
				decompressed.decode_float(o + 8)
			)

			# Unpack UV rect
			tile_info.uv_rect = Rect2(
				decompressed.decode_half(o + 12),
				decompressed.decode_half(o + 14),
				decompressed.decode_half(o + 16),
				decompressed.decode_half(o + 18)
			)

			# Unpack basic tile data
			tile_info.orientation = decompressed.decode_u16(o + 20)
			tile_info.rotation = decompressed.decode_u16(o + 22)
			tile_info.flip = decompressed.decode_u8(o + 24) == 1
			tile_info.mode = decompressed.decode_u8(o + 25)
			tile_info.terrain_id = decompressed.decode_s16(o + 26)

			# Unpack transform parameters
			tile_info.spin_angle_rad = decompressed.decode_float(o + 28)
			tile_info.tilt_angle_rad = decompressed.decode_float(o + 32)
			tile_info.diagonal_scale = decompressed.decode_float(o + 36)
			tile_info.tilt_offset_factor = decompressed.decode_float(o + 40)
			tile_info.depth_scale = decompressed.decode_float(o + 44)
			tile_info.texture_repeat_mode = decompressed.decode_u8(o + 48)

			# Unpack animation data (offsets 49-56)
			tile_info.anim_step_x = decompressed.decode_half(o + 49)
			tile_info.anim_step_y = decompressed.decode_half(o + 51)
			tile_info.anim_total_frames = decompressed.decode_u8(o + 53)
			tile_info.anim_columns = decompressed.decode_u8(o + 54)
			tile_info.anim_speed_fps = decompressed.decode_half(o + 55)

			# Unpack atlas binding (offsets 57-64)
			tile_info.atlas_source_id = decompressed.decode_s32(o + 57)
			tile_info.atlas_coords = Vector2i(
				decompressed.decode_s16(o + 61),
				decompressed.decode_s16(o + 63)
			)
			tile_info.freeze_uv = decompressed.decode_u8(o + 65) == 1
			tile_info.depth_growth_mode = decompressed.decode_u8(o + 66)

			# V2: custom transform (byte 67 + bytes 68-115)
			if is_v2:
				tile_info.has_custom_transform = decompressed.decode_u8(o + 67) == 1
				if tile_info.has_custom_transform:
					tile_info.custom_transform = Transform3D(
						Basis(
							Vector3(
								decompressed.decode_float(o + 68),
								decompressed.decode_float(o + 72),
								decompressed.decode_float(o + 76)
							),
							Vector3(
								decompressed.decode_float(o + 80),
								decompressed.decode_float(o + 84),
								decompressed.decode_float(o + 88)
							),
							Vector3(
								decompressed.decode_float(o + 92),
								decompressed.decode_float(o + 96),
								decompressed.decode_float(o + 100)
							)
						),
						Vector3(
							decompressed.decode_float(o + 104),
							decompressed.decode_float(o + 108),
							decompressed.decode_float(o + 112)
						)
					)

			# Generate tile key from position and orientation
			tile_info.tile_key = GlobalUtil.make_tile_key(tile_info.grid_pos, tile_info.orientation)

			result.append(tile_info)
			base += BYTES_PER_TILE_V2 if is_v2 else BYTES_PER_TILE

		return result
