@tool
class_name VertexTileEntry
extends Resource

## Persistent data for a single vertex-edited tile.
## Stored in TileMapLayer3D._vertex_tile_corners[tile_key].

## World-space corner positions [BL, BR, TR, TL].
@export var corners: PackedVector3Array = PackedVector3Array()
## UV rect within the atlas texture.
@export var uv_rect: Rect2 = Rect2()
## Snapshot of the original columnar tile data (used for undo).
@export var tile_info: PlacedTileInfo = null
