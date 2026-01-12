# =============================================================================
# FILE: addons/TileMapLayer3D/integration/autotile_placement_extension.gd
# PURPOSE: Integration layer for autotile placement into the existing system
# DEPENDENCIES: AutotileEngine, TilePlacementManager, TileMapLayer3D
# =============================================================================
@tool
class_name AutotilePlacementExtension
extends RefCounted

## Extension for autotile placement. Integrates with TilePlacementManager
## to provide automatic tile selection based on neighboring tiles.
##
## This class does NOT modify TilePlacementManager directly - it uses
## composition to provide autotiling functionality to the plugin.
##
## Usage:
##   1. Call get_autotile_uv() to get the correct UV before placing
##   2. Place the tile using the normal placement system
##   3. Call on_tile_placed() after placement to update neighbors

# === SIGNALS ===

## Emitted when autotile placement succeeds
signal tile_placed(grid_pos: Vector3, orientation: int, terrain_id: int)

## Emitted when neighbors are updated
signal neighbors_updated(update_count: int)

# === DEPENDENCIES ===

var _engine: AutotileEngine
var _placement_manager: TilePlacementManager
var _tile_map_layer: TileMapLayer3D

# === STATE ===

## Whether autotile mode is enabled
var enabled: bool = false

## Currently selected terrain for painting
var current_terrain_id: int = GlobalConstants.AUTOTILE_NO_TERRAIN


## Initialize with required dependencies
func setup(
	engine: AutotileEngine,
	placement_manager: TilePlacementManager,
	tile_map_layer: TileMapLayer3D
) -> void:
	_engine = engine
	_placement_manager = placement_manager
	_tile_map_layer = tile_map_layer


## Check if extension is ready to use
func is_ready() -> bool:
	return (
		enabled and
		_engine != null and
		_engine.is_ready() and
		_placement_manager != null and
		_tile_map_layer != null and
		current_terrain_id >= 0
	)


## Get the correct UV rect for autotile placement at a position
## This should be called by the plugin BEFORE placing a tile
## Returns empty Rect2 if autotiling is not ready
## Uses TileMapLayer3D columnar storage for neighbor lookups
func get_autotile_uv(grid_pos: Vector3, orientation: int) -> Rect2:
	if not is_ready():
		return Rect2()

	# Only support base 6 orientations for autotiling
	if not PlaneCoordinateMapper.is_supported_orientation(orientation):
		return Rect2()

	# Pass TileMapLayer3D for columnar storage access
	return _engine.get_autotile_uv(
		grid_pos, orientation, current_terrain_id, _tile_map_layer
	)


## Called by the plugin AFTER a tile has been placed to update neighbors
## Also sets the terrain_id on the placed tile
## Returns the number of neighbors updated
## Uses TileMapLayer3D columnar storage directly
func on_tile_placed(grid_pos: Vector3, orientation: int) -> int:
	if not enabled or not _engine:
		return 0

	# Update the terrain_id in columnar storage
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

	# Update terrain_id directly in columnar storage
	if _tile_map_layer and _tile_map_layer.has_tile(tile_key):
		_tile_map_layer.update_saved_tile_terrain(tile_key, current_terrain_id)

	# Update neighbors
	var update_count: int = _update_neighbors(grid_pos, orientation)

	tile_placed.emit(grid_pos, orientation, current_terrain_id)
	return update_count


## Called by the plugin AFTER a tile has been erased to update neighbors
## Returns the number of neighbors updated
func on_tile_erased(grid_pos: Vector3, orientation: int, terrain_id: int) -> int:
	if not _engine:
		return 0

	# Only update neighbors if the erased tile was autotiled
	if terrain_id < 0:
		return 0

	# Invalidate engine cache for this tile
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
	_engine.invalidate_tile(tile_key)

	# Update neighbors
	return _update_neighbors(grid_pos, orientation)


## Internal - Update all neighbors of a position
## Uses TileMapLayer3D columnar storage directly
func _update_neighbors(grid_pos: Vector3, orientation: int) -> int:
	if not _engine or not _placement_manager or not _tile_map_layer:
		return 0

	# Pass TileMapLayer3D for columnar storage access
	var updates: Dictionary = _engine.update_neighbors(grid_pos, orientation, _tile_map_layer)

	if updates.is_empty():
		return 0

	# Apply updates using batch mode from placement manager
	_placement_manager.begin_batch_update()

	for tile_key: int in updates.keys():
		var new_uv: Rect2 = updates[tile_key]
		_update_tile_uv(tile_key, new_uv)

	_placement_manager.end_batch_update()

	neighbors_updated.emit(updates.size())
	return updates.size()


## Internal - Update a tile's UV without changing its other properties
## Uses TileMapLayer3D columnar storage directly
func _update_tile_uv(tile_key: int, new_uv: Rect2) -> void:
	if not _tile_map_layer or not _tile_map_layer.has_tile(tile_key):
		return

	# Update the MultiMesh instance and columnar storage
	_tile_map_layer.update_tile_uv(tile_key, new_uv)


## Set the autotile engine
func set_engine(engine: AutotileEngine) -> void:
	_engine = engine


## Get the autotile engine
func get_engine() -> AutotileEngine:
	return _engine


## Set enabled state
func set_enabled(value: bool) -> void:
	enabled = value


## Set current terrain
func set_terrain(terrain_id: int) -> void:
	current_terrain_id = terrain_id


## Get the current terrain ID
func get_terrain() -> int:
	return current_terrain_id
