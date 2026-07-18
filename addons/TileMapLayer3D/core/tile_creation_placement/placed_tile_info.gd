@tool
class_name PlacedTileInfo
extends Resource


@export var tile_key: int = -1

@export var grid_position: Vector3 = Vector3.ZERO

@export var uv_rect: Rect2 = Rect2()

@export var orientation: int = 0

@export var mesh_rotation: int = 0

@export var mesh_mode: GlobalConstants.MeshMode = GlobalConstants.DEFAULT_MESH_MODE

@export var is_face_flipped: bool = false

@export var terrain_id: int = GlobalConstants.AUTOTILE_NO_TERRAIN

@export var spin_angle_rad: float = 0.0

@export var tilt_angle_rad: float = 0.0

@export var diagonal_scale: float = 0.0

@export var tilt_offset_factor: float = 0.0

@export var depth_scale: float = 1.0

@export var texture_repeat_mode: int = 0

@export var freeze_uv: bool = false

@export var depth_growth_mode: int = GlobalConstants.DepthGrowthMode.OUTWARD

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


var terrain_region_chunk: TerrainRegionChunk = null


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



func copy() -> PlacedTileInfo:
	var duplicate_info_data := PlacedTileInfo.new()
	duplicate_info_data.tile_key = tile_key
	duplicate_info_data.grid_position = grid_position
	duplicate_info_data.uv_rect = uv_rect
	duplicate_info_data.orientation = orientation
	duplicate_info_data.mesh_rotation = mesh_rotation
	duplicate_info_data.mesh_mode = mesh_mode
	duplicate_info_data.is_face_flipped = is_face_flipped
	duplicate_info_data.terrain_id = terrain_id
	duplicate_info_data.spin_angle_rad = spin_angle_rad
	duplicate_info_data.tilt_angle_rad = tilt_angle_rad
	duplicate_info_data.diagonal_scale = diagonal_scale
	duplicate_info_data.tilt_offset_factor = tilt_offset_factor
	duplicate_info_data.depth_scale = depth_scale
	duplicate_info_data.texture_repeat_mode = texture_repeat_mode
	duplicate_info_data.freeze_uv = freeze_uv
	duplicate_info_data.depth_growth_mode = depth_growth_mode
	duplicate_info_data.anim_step_x = anim_step_x
	duplicate_info_data.anim_step_y = anim_step_y
	duplicate_info_data.anim_total_frames = anim_total_frames
	duplicate_info_data.anim_columns = anim_columns
	duplicate_info_data.anim_speed_fps = anim_speed_fps
	duplicate_info_data.atlas_source_id = atlas_source_id
	duplicate_info_data.atlas_coords = atlas_coords
	duplicate_info_data.custom_transform = custom_transform
	duplicate_info_data.has_custom_transform = has_custom_transform
	duplicate_info_data.snapped_grid_position = snapped_grid_position
	duplicate_info_data.world_position = world_position
	return duplicate_info_data


func is_empty() -> bool:
	return false
