@tool
class_name UndoData
extends RefCounted


const BYTES_PER_TILE: int = 68
const BYTES_PER_TILE_V2: int = 117
const FORMAT_VERSION: int = 2

class UndoAreaData:
	extends RefCounted

	var tiles: PackedByteArray = PackedByteArray()
	var count: int = 0

	static func from_tiles(tiles_array: Array[PlacedTileInfo]) -> UndoAreaData:
		var area_data: UndoAreaData = UndoAreaData.new()
		var normalized_tiles: Array[PlacedTileInfo] = []
		for tile_info: PlacedTileInfo in tiles_array:
			if tile_info != null:
				normalized_tiles.append(tile_info)

		area_data.count = normalized_tiles.size()

		if area_data.count == 0:
			return area_data

		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(1 + area_data.count * BYTES_PER_TILE_V2)
		bytes.encode_u8(0, FORMAT_VERSION)

		var base: int = 1
		for tile_info in normalized_tiles:
			var o: int = base
			bytes.encode_float(o, tile_info.grid_pos.x)
			bytes.encode_float(o + 4, tile_info.grid_pos.y)
			bytes.encode_float(o + 8, tile_info.grid_pos.z)

			bytes.encode_half(o + 12, tile_info.uv_rect.position.x)
			bytes.encode_half(o + 14, tile_info.uv_rect.position.y)
			bytes.encode_half(o + 16, tile_info.uv_rect.size.x)
			bytes.encode_half(o + 18, tile_info.uv_rect.size.y)

			bytes.encode_u16(o + 20, tile_info.orientation)
			bytes.encode_u16(o + 22, tile_info.rotation)
			bytes.encode_u8(o + 24, 1 if tile_info.flip else 0)
			bytes.encode_u8(o + 25, tile_info.mode)
			bytes.encode_s16(o + 26, tile_info.terrain_id)

			bytes.encode_float(o + 28, tile_info.spin_angle_rad)
			bytes.encode_float(o + 32, tile_info.tilt_angle_rad)
			bytes.encode_float(o + 36, tile_info.diagonal_scale)
			bytes.encode_float(o + 40, tile_info.tilt_offset_factor)
			bytes.encode_float(o + 44, tile_info.depth_scale)
			bytes.encode_u8(o + 48, tile_info.texture_repeat_mode)

			bytes.encode_half(o + 49, tile_info.anim_step_x)
			bytes.encode_half(o + 51, tile_info.anim_step_y)
			bytes.encode_u8(o + 53, clampi(tile_info.anim_total_frames, 0, 255))
			bytes.encode_u8(o + 54, clampi(tile_info.anim_columns, 0, 255))
			bytes.encode_half(o + 55, tile_info.anim_speed_fps)
			bytes.encode_s32(o + 57, tile_info.atlas_source_id)
			bytes.encode_s16(o + 61, tile_info.atlas_coords.x)
			bytes.encode_s16(o + 63, tile_info.atlas_coords.y)
			bytes.encode_u8(o + 65, 1 if tile_info.freeze_uv else 0)
			bytes.encode_u8(o + 66, tile_info.depth_growth_mode & 0x1)

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

			base += BYTES_PER_TILE_V2

		area_data.tiles = bytes.compress(FileAccess.COMPRESSION_ZSTD)
		return area_data

	func to_tiles() -> Array:
		if count == 0:
			return []

		var v2_size: int = 1 + count * BYTES_PER_TILE_V2
		var decompressed: PackedByteArray = tiles.decompress(v2_size, FileAccess.COMPRESSION_ZSTD)
		var is_v2: bool = decompressed.size() == v2_size and decompressed.decode_u8(0) == FORMAT_VERSION

		if not is_v2:
			decompressed = tiles.decompress(count * BYTES_PER_TILE, FileAccess.COMPRESSION_ZSTD)

		var result: Array = []
		var base: int = 1 if is_v2 else 0

		for i: int in range(count):
			var tile_info := PlacedTileInfo.new()
			var o: int = base

			tile_info.grid_pos = Vector3(
				decompressed.decode_float(o),
				decompressed.decode_float(o + 4),
				decompressed.decode_float(o + 8)
			)

			tile_info.uv_rect = Rect2(
				decompressed.decode_half(o + 12),
				decompressed.decode_half(o + 14),
				decompressed.decode_half(o + 16),
				decompressed.decode_half(o + 18)
			)

			tile_info.orientation = decompressed.decode_u16(o + 20)
			tile_info.rotation = decompressed.decode_u16(o + 22)
			tile_info.flip = decompressed.decode_u8(o + 24) == 1
			tile_info.mode = decompressed.decode_u8(o + 25)
			tile_info.terrain_id = decompressed.decode_s16(o + 26)

			tile_info.spin_angle_rad = decompressed.decode_float(o + 28)
			tile_info.tilt_angle_rad = decompressed.decode_float(o + 32)
			tile_info.diagonal_scale = decompressed.decode_float(o + 36)
			tile_info.tilt_offset_factor = decompressed.decode_float(o + 40)
			tile_info.depth_scale = decompressed.decode_float(o + 44)
			tile_info.texture_repeat_mode = decompressed.decode_u8(o + 48)

			tile_info.anim_step_x = decompressed.decode_half(o + 49)
			tile_info.anim_step_y = decompressed.decode_half(o + 51)
			tile_info.anim_total_frames = decompressed.decode_u8(o + 53)
			tile_info.anim_columns = decompressed.decode_u8(o + 54)
			tile_info.anim_speed_fps = decompressed.decode_half(o + 55)

			tile_info.atlas_source_id = decompressed.decode_s32(o + 57)
			tile_info.atlas_coords = Vector2i(
				decompressed.decode_s16(o + 61),
				decompressed.decode_s16(o + 63)
			)
			tile_info.freeze_uv = decompressed.decode_u8(o + 65) == 1
			tile_info.depth_growth_mode = decompressed.decode_u8(o + 66)

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

			tile_info.tile_key = GlobalUtil.make_tile_key(tile_info.grid_pos, tile_info.orientation)

			result.append(tile_info)
			base += BYTES_PER_TILE_V2 if is_v2 else BYTES_PER_TILE

		return result
