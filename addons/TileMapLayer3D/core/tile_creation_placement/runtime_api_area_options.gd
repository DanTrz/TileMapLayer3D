@tool
class_name RuntimeAPIAreaOptions
extends RefCounted

## Options for TileMapRuntimeAPI.place_area(), erase_area(), and highlight_area().
## Pass null (the default) to use all defaults.

## "origin" (default) or "center" — which corner of the area the anchor world pos maps to.
var anchor: String = "origin"
## When true (default), wraps the operation in begin_batch/end_batch for GPU efficiency.
var batch: bool = true
## When true (default), existing tiles at each cell are overwritten.
var overwrite: bool = true
## Optional tile properties to apply to each placed tile.
var tile_info: PlacedTileData = null
