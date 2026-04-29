@tool
## Wrapper data class for Tile Information that is used for tile placement and manipulation via scripts.
## Mostly used for lookups and retrieval of information from Columnar storage. The underlying data will remain stored as a columnar arrays.
class_name PlacedTileInfo
extends Resource


##Unique integer key encoding the tile's grid position and orientation. Primery key to find tiles and used for all lookups into the node's saved columnar arrays. Value -1 means unset.
@export var tile_key: int = -1

##Grid-aligned `Vector3` position (in tile grid units). Represents the logical cell where the tile is placed (snapped to the grid), not world coordinates.
@export var grid_position: Vector3 = Vector3.ZERO

##`Rect2` describing the texture UV region for this tile (x, y, w, h) in the tileset texture atlas.
@export var uv_rect: Rect2 = Rect2()

## Integer orientation index (0–17). Base flats use 0–5; tilted variants occupy higher indices.
## Maps to the enum TileOrientation in GlobalUtil. 
@export var orientation: int = 0

## Integer rotation step for the mesh (typically 0–3 for 0°,90°,180°,270° rotations).
@export var mesh_rotation: int = 0

## mesh_mode: Mesh type enum from `GlobalConstants` (e.g. flat, box, prism, triangle).
## maps to the enum MeshMode in GlobalConstants. Determines the 3D mesh variant used for this tile instance e.g. FLAT_SQUARE , FLAT_TRIANGULE, BOX_MESH, etc
@export var mesh_mode: GlobalConstants.MeshMode = GlobalConstants.DEFAULT_MESH_MODE

## When true the tile's face/UVs are mirrored and flipped (used for flipping visuals).
@export var is_face_flipped: bool = false

## TileSet terrain ID identifier (mostly used in AutoTile)
## Use `GlobalConstants.AUTOTILE_NO_TERRAIN` when not part of autotile.
@export var terrain_id: int = GlobalConstants.AUTOTILE_NO_TERRAIN

## Additional local spin rotation for the tile, in radians.
## Spin is applied after orientation and mesh rotation, allowing for dynamic rotation effects on top of the base tile orientation. Spin rotated in the same plane.
@export var spin_angle_rad: float = 0.0

## Tilt rotation for the tile, in radians. Used to "lean" the tile for visual variety, typically applied to create Ramps and lean the tile backwards or forwards in 45 degree increments.
@export var tilt_angle_rad: float = 0.0

## Diagonal scaling factor for diagonal or triangular mesh modes. Adjusts the scale of the tile along the diagonal axis to better fit the grid when placing items like slopes or ramps. 
@export var diagonal_scale: float = 0.0

## Fractional offset applied during tilt adjustments to nudge vertex positions.
@export var tilt_offset_factor: float = 0.0

## Y-axis depth/height scale for 3D meshes (box/prism). This controls the Z dimension of the tile's mesh when using "non-flat" mesh modes.
@export var depth_scale: float = 1.0

## Flag controlling texture repetition / tiling behavior on the mesh.
## Mostly used for box/prism meshes to determine if the texture should repeat across the faces or stretch to fit. Maps to the enum TextureRepeatMode in GlobalConstants.
@export var texture_repeat_mode: int = 0

##If true, UV coordinates are frozen and won't be altered by Rotation or Tilt operations. This is useful for certain tile types where the UV mapping should remain constant regardless of orientation changes.
@export var freeze_uv: bool = false

## Sub-frame animation offsets (used for animated atlas sampling).
## These represent the fractional offset in UV space for the current frame of an animation sequence
@export var anim_step_x: float = 0.0

## Sub-frame animation offsets (used for animated atlas sampling).
## These represent the fractional offset in UV space for the current frame of an animation sequence
@export var anim_step_y: float = 0.0

## Total number of frames in the animation sequence for this tile. Used to determine when to loop back the animation steps. A value of 1 means no animation (static tile).
@export var anim_total_frames: int = 1

## Number of columns in the animation layout on the atlas.
@export var anim_columns: int = 1

## Animation playback speed in frames-per-second.
@export var anim_speed_fps: float = 0.0

## Identifier for the atlas/texture source this tile references (-1 = none).
## This stores the atlas ID of the TileSet Resource "TileSetAtlasSource" that this tile is using
@export var atlas_source_id: int = -1

## Integer grid coordinates (column, row) inside the TileSet "TileSetAtlasSource"; 
## Used for reference and lookups to get the correct Tile Data from the TileSet.
## (-1,-1) if unset.
@export var atlas_coords: Vector2i = Vector2i(-1, -1)

## Optional `Transform3D` applied when `has_custom_transform` is true.
## Used by special operations only like Smart Ramp and tiles that require custom transform that are not "square-based" or "grid-aligned" tiles. 
@export var custom_transform: Transform3D = Transform3D()

## has_custom_transform: Boolean that toggles application of `custom_transform` to this tile instance.
@export var has_custom_transform: bool = false

## Grid position snapped to the tile grid, used for quick comparisons and lookups. This is computed from `grid_position` but it's snapped to guarantee grid alignment, which is important for certain operations and optimizations. 
@export var snapped_grid_position: Vector3 = Vector3.ZERO

## Tile world-space `Vector3` computed from `grid_position` for convenience to store the original location in world-space where the tile was placed.
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
