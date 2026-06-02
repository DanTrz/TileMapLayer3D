@tool
class_name TileMapLayerData
extends Resource

## Per-node tilemap storage for all key data and columnar storage (persists across saves)

## Grid positions of all tiles (12 bytes per tile)
@export var _tile_positions: PackedVector3Array = PackedVector3Array()

## UV rect data: 4 floats per tile (x, y, width, height) - 16 bytes per tile.
## Authoritative for rendering — preserves freeform picks (e.g. 64x32 in a 32x32 scene)
## that don't correspond to any registered atlas cell. Never overwritten by atlas resolution.
@export var _tile_uv_rects: PackedFloat32Array = PackedFloat32Array()

## Per-tile TileSet source id. Parallel to _tile_positions.
## Sentinel value -1 means "freeform — no atlas binding".
## Always populated for every tile (in sync with _tile_positions.size()).
@export var _tile_atlas_source_ids: PackedInt32Array = PackedInt32Array()

## Per-tile atlas coordinates (ATLAS_COORDS_STRIDE ints per tile = coords.x, coords.y).
## Sentinel value (-1, -1) means "freeform — no atlas binding".
## Always populated for every tile (size = _tile_positions.size() * ATLAS_COORDS_STRIDE).
@export var _tile_atlas_coords: PackedInt32Array = PackedInt32Array()

## Number of ints stored per tile in `_tile_atlas_coords` (x, y).
const ATLAS_COORDS_STRIDE: int = 2

## Bitpacked flags per tile - 4 bytes per tile (v2 layout)
## Bits 0-4:   orientation (0-17)           5 bits
## Bits 5-6:   mesh_rotation (0-3)          2 bits
## Bit 7:      is_face_flipped              1 bit
## Bits 8-15:  terrain_id + 128             8 bits (allows -1 to 126)
## Bit 16:     texture_repeat_mode          1 bit
## Bit 17:     freeze_uv                    1 bit
## Bits 18-21: reserved                     4 bits (placeholder for future features)
## Bits 22-31: mesh_mode (0-1023)           10 bits (at end — no migration needed for new modes)
@export var _tile_flags: PackedInt32Array = PackedInt32Array()

## Flags format version: 0 = old 2-bit, 1 = 3-bit mesh_mode in middle, 2 = v2 (mesh_mode at top).
## Old scenes lack this field — Godot defaults it to 0, triggering cascading migration 0→1→2.
@export var _flags_format_version: int = 0

## Transform params index for tiles that need them (tilted tiles)
## Index into _tile_transform_data, -1 if using defaults - 4 bytes per tile
@export var _tile_transform_indices: PackedInt32Array = PackedInt32Array()

## Sparse storage for non-default transform params
## Each entry: 5 floats (spin_angle, tilt_angle, diagonal_scale, tilt_offset, depth_scale)
## BREAKING: Scenes saved with old 4-float format (before commit 3019248) cannot be loaded
## See CLAUDE.md for migration instructions
@export var _tile_transform_data: PackedFloat32Array = PackedFloat32Array()

## Custom transforms for smart fill sloped tiles (keyed by tile_key → Transform3D).
## Independent of columnar array indices — no sync issues with add/remove operations.
@export var _tile_custom_transforms: Dictionary = {}

## Vertex-edited tiles (keyed by tile_key → VertexTileEntry).
## These tiles are REMOVED from columnar storage and rendered as individual MeshInstance3D nodes.
@export var _vertex_tile_corners: Dictionary = {}

## Sparse storage for animation data (FLAT_SQUARE only)
## Same pattern as transform data: _tile_anim_indices[i] = -1 (static) or >= 0 (index into _tile_anim_data)
## Each _tile_anim_data entry: 5 floats [step_x, step_y, total_frames, anim_columns, speed_fps]
@export var _tile_anim_indices: PackedInt32Array = PackedInt32Array()
@export var _tile_anim_data: PackedFloat32Array = PackedFloat32Array()
