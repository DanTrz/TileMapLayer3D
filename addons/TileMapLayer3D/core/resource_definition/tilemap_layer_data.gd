@tool
class_name TileMapLayerData
extends Resource


@export var tileset: TileSet = null:
	set(value):
		if tileset != value:
			tileset = value
			emit_changed()

@export var normal_texture: Texture2D = null:
	set(value):
		if normal_texture != value:
			normal_texture = value
			emit_changed()

@export var _tile_positions: PackedVector3Array = PackedVector3Array()

## UV rect data: 4 floats per tile (x, y, width, height) - 16 bytes per tile.
## Authoritative for rendering — preserves freeform picks (e.g. 64x32 in a 32x32 scene)
## that don't correspond to any registered atlas cell. Never overwritten by atlas resolution.
@export var _tile_uv_rects: PackedFloat32Array = PackedFloat32Array()

@export var _tile_atlas_source_ids: PackedInt32Array = PackedInt32Array()

@export var _tile_atlas_coords: PackedInt32Array = PackedInt32Array()

const ATLAS_COORDS_STRIDE: int = 2

@export var _tile_flags: PackedInt32Array = PackedInt32Array()

@export var _flags_format_version: int = 0

@export var _tile_transform_indices: PackedInt32Array = PackedInt32Array()

## Sparse storage for non-default transform params
## Each entry: 5 floats (spin_angle, tilt_angle, diagonal_scale, tilt_offset, depth_scale)
## BREAKING: Scenes saved with old 4-float format (before commit 3019248) cannot be loaded
## See CLAUDE.md for migration instructions
@export var _tile_transform_data: PackedFloat32Array = PackedFloat32Array()

@export var _tile_custom_transforms: Dictionary = {}

@export var _vertex_tile_corners: Dictionary = {}

@export var _tile_anim_indices: PackedInt32Array = PackedInt32Array()
@export var _tile_anim_data: PackedFloat32Array = PackedFloat32Array()
