@tool
class_name PlacedTileData
extends Resource

## Transient, typed view of a placed TileMapLayer3D tile.
## The authoritative saved representation remains TileMapLayer3D's columnar arrays.

@export var tile_key: int = -1
@export var grid_position: Vector3 = Vector3.ZERO
@export var uv_rect: Rect2 = Rect2()
@export var orientation: int = 0
@export var mesh_rotation: int = 0
@export var mesh_mode: int = GlobalConstants.DEFAULT_MESH_MODE
@export var is_face_flipped: bool = false
@export var terrain_id: int = GlobalConstants.AUTOTILE_NO_TERRAIN
@export var spin_angle_rad: float = 0.0
@export var tilt_angle_rad: float = 0.0
@export var diagonal_scale: float = 0.0
@export var tilt_offset_factor: float = 0.0
@export var depth_scale: float = 1.0
@export var texture_repeat_mode: int = 0
@export var freeze_uv: bool = false
@export var anim_step_x: float = 0.0
@export var anim_step_y: float = 0.0
@export var anim_total_frames: int = 1
@export var anim_columns: int = 1
@export var anim_speed_fps: float = 0.0
@export var atlas_source_id: int = -1
@export var atlas_coords: Vector2i = Vector2i(-1, -1)
@export var custom_transform: Transform3D = Transform3D()
@export var has_custom_transform: bool = false
@export var snapped_grid_position: Vector3 = Vector3.ZERO
@export var world_position: Vector3 = Vector3.ZERO


var grid_pos: Vector3:
	get:
		return grid_position
	set(value):
		grid_position = value

var rotation: int:
	get:
		return mesh_rotation
	set(value):
		mesh_rotation = value

var mode: int:
	get:
		return mesh_mode
	set(value):
		mesh_mode = value

var flip: bool:
	get:
		return is_face_flipped
	set(value):
		is_face_flipped = value


static func from_dictionary(data: Dictionary) -> PlacedTileData:
	var tile_data := PlacedTileData.new()
	tile_data.tile_key = data.get("tile_key", -1)
	tile_data.grid_position = data.get("grid_position", data.get("grid_pos", Vector3.ZERO))
	tile_data.uv_rect = data.get("uv_rect", Rect2())
	tile_data.orientation = data.get("orientation", 0)
	tile_data.mesh_rotation = data.get("mesh_rotation", data.get("rotation", 0))
	tile_data.mesh_mode = data.get("mesh_mode", data.get("mode", GlobalConstants.DEFAULT_MESH_MODE))
	tile_data.is_face_flipped = data.get("is_face_flipped", data.get("flip", false))
	tile_data.terrain_id = data.get("terrain_id", GlobalConstants.AUTOTILE_NO_TERRAIN)
	tile_data.spin_angle_rad = data.get("spin_angle_rad", 0.0)
	tile_data.tilt_angle_rad = data.get("tilt_angle_rad", 0.0)
	tile_data.diagonal_scale = data.get("diagonal_scale", 0.0)
	tile_data.tilt_offset_factor = data.get("tilt_offset_factor", 0.0)
	tile_data.depth_scale = data.get("depth_scale", 1.0)
	tile_data.texture_repeat_mode = data.get("texture_repeat_mode", 0)
	tile_data.freeze_uv = data.get("freeze_uv", false)
	tile_data.anim_step_x = data.get("anim_step_x", 0.0)
	tile_data.anim_step_y = data.get("anim_step_y", 0.0)
	tile_data.anim_total_frames = data.get("anim_total_frames", 1)
	tile_data.anim_columns = data.get("anim_columns", 1)
	tile_data.anim_speed_fps = data.get("anim_speed_fps", 0.0)
	tile_data.atlas_source_id = data.get("atlas_source_id", -1)
	tile_data.atlas_coords = data.get("atlas_coords", Vector2i(-1, -1))
	tile_data.has_custom_transform = data.has("custom_transform")
	tile_data.custom_transform = data.get("custom_transform", Transform3D())
	tile_data.snapped_grid_position = data.get("snapped_grid_position", Vector3.ZERO)
	tile_data.world_position = data.get("world_position", Vector3.ZERO)
	return tile_data


func to_dictionary() -> Dictionary:
	var data: Dictionary = {
		"tile_key": tile_key,
		"grid_position": grid_position,
		"grid_pos": grid_position,
		"uv_rect": uv_rect,
		"orientation": orientation,
		"mesh_rotation": mesh_rotation,
		"rotation": mesh_rotation,
		"mesh_mode": mesh_mode,
		"mode": mesh_mode,
		"is_face_flipped": is_face_flipped,
		"flip": is_face_flipped,
		"terrain_id": terrain_id,
		"spin_angle_rad": spin_angle_rad,
		"tilt_angle_rad": tilt_angle_rad,
		"diagonal_scale": diagonal_scale,
		"tilt_offset_factor": tilt_offset_factor,
		"depth_scale": depth_scale,
		"texture_repeat_mode": texture_repeat_mode,
		"freeze_uv": freeze_uv,
		"anim_step_x": anim_step_x,
		"anim_step_y": anim_step_y,
		"anim_total_frames": anim_total_frames,
		"anim_columns": anim_columns,
		"anim_speed_fps": anim_speed_fps,
		"atlas_source_id": atlas_source_id,
		"atlas_coords": atlas_coords,
		"snapped_grid_position": snapped_grid_position,
		"world_position": world_position,
	}
	if has_custom_transform:
		data["custom_transform"] = custom_transform
	return data


func copy() -> PlacedTileData:
	var duplicate_data := PlacedTileData.new()
	duplicate_data.tile_key = tile_key
	duplicate_data.grid_position = grid_position
	duplicate_data.uv_rect = uv_rect
	duplicate_data.orientation = orientation
	duplicate_data.mesh_rotation = mesh_rotation
	duplicate_data.mesh_mode = mesh_mode
	duplicate_data.is_face_flipped = is_face_flipped
	duplicate_data.terrain_id = terrain_id
	duplicate_data.spin_angle_rad = spin_angle_rad
	duplicate_data.tilt_angle_rad = tilt_angle_rad
	duplicate_data.diagonal_scale = diagonal_scale
	duplicate_data.tilt_offset_factor = tilt_offset_factor
	duplicate_data.depth_scale = depth_scale
	duplicate_data.texture_repeat_mode = texture_repeat_mode
	duplicate_data.freeze_uv = freeze_uv
	duplicate_data.anim_step_x = anim_step_x
	duplicate_data.anim_step_y = anim_step_y
	duplicate_data.anim_total_frames = anim_total_frames
	duplicate_data.anim_columns = anim_columns
	duplicate_data.anim_speed_fps = anim_speed_fps
	duplicate_data.atlas_source_id = atlas_source_id
	duplicate_data.atlas_coords = atlas_coords
	duplicate_data.custom_transform = custom_transform
	duplicate_data.has_custom_transform = has_custom_transform
	duplicate_data.snapped_grid_position = snapped_grid_position
	duplicate_data.world_position = world_position
	return duplicate_data


func is_empty() -> bool:
	return false
