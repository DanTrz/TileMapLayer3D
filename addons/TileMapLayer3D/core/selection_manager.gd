extends RefCounted
class_name SelectionManager

## ============================================================================
## SELECTION MANAGER - Single Source of Truth for Tile Selection
## ============================================================================
## This class is the ONLY place where tile selection state should live.
## All other components (Plugin, TilesetPanel, PlacementManager) should
## subscribe to signals from this manager rather than maintaining their own
## selection state.
##
## This eliminates the "scattered selection state" bug where selection data
## could get out of sync between Settings, PlacementManager, and UI.
##
## Usage:
##   var selection_manager = SelectionManager.new()
##   selection_manager.selection_changed.connect(_on_selection_changed)
##   selection_manager.select([uv_rect1, uv_rect2], anchor_index)
##   selection_manager.clear()

## Emitted when tile selection changes (new tiles selected)
## @param tiles: Array of UV Rect2 values for selected tiles
## @param anchor: Index of the anchor tile (for multi-tile placement origin)
signal selection_changed(tiles: Array[Rect2], anchor: int)

## Emitted when selection is cleared
signal selection_cleared()

# =============================================================================
# PRIVATE STATE - Only this class modifies these values
# =============================================================================

var _tiles: Array[Rect2] = []
var _anchor_index: int = 0


# =============================================================================
# PUBLIC API - Selection Management
# =============================================================================

## Selects one or more tiles
## @param tiles: Array of UV Rect2 values for selected tiles
## @param anchor: Index of the anchor tile (default: 0)
func select(tiles: Array[Rect2], anchor: int = 0) -> void:
	# Duplicate to prevent external modification
	_tiles = tiles.duplicate()
	_anchor_index = clampi(anchor, 0, maxi(0, _tiles.size() - 1))
	selection_changed.emit(_tiles, _anchor_index)


## Clears the current selection
func clear() -> void:
	_tiles.clear()
	_anchor_index = 0
	selection_cleared.emit()


## Returns the currently selected tiles (read-only copy)
func get_tiles() -> Array[Rect2]:
	return _tiles.duplicate()


## Returns the raw tiles array (for performance when read-only access is guaranteed)
## WARNING: Do not modify the returned array!
func get_tiles_readonly() -> Array[Rect2]:
	return _tiles


## Returns the anchor index
func get_anchor() -> int:
	return _anchor_index


## Returns true if any tiles are selected
func has_selection() -> bool:
	return _tiles.size() > 0


## Returns true if multiple tiles are selected
func has_multi_selection() -> bool:
	return _tiles.size() > 1


## Returns the number of selected tiles
func get_selection_count() -> int:
	return _tiles.size()


## Returns the first selected tile UV (or empty Rect2 if none)
func get_first_tile() -> Rect2:
	if _tiles.size() > 0:
		return _tiles[0]
	return Rect2()


## Returns the anchor tile UV (or empty Rect2 if none)
func get_anchor_tile() -> Rect2:
	if _tiles.size() > 0 and _anchor_index < _tiles.size():
		return _tiles[_anchor_index]
	return Rect2()


# =============================================================================
# PERSISTENCE HELPERS
# =============================================================================
# These methods help sync with TileMapLayerSettings for scene persistence

## Restores selection from saved settings (called on node selection)
## @param tiles: Array of UV Rect2 values to restore
## @param anchor: Anchor index to restore
## @param emit_signals: If true, emits selection_changed signal so subscribers sync
##                      Set to true when PlacementManager needs to be updated
##                      Set to false for pure state restoration without side effects
func restore_from_settings(tiles: Array[Rect2], anchor: int, emit_signals: bool = false) -> void:
	_tiles = tiles.duplicate()
	_anchor_index = clampi(anchor, 0, maxi(0, _tiles.size() - 1))
	# Optionally emit signal so subscribers (like PlacementManager) can sync
	if emit_signals and _tiles.size() > 0:
		selection_changed.emit(_tiles, _anchor_index)


## Returns data for saving to settings
func get_data_for_settings() -> Dictionary:
	return {
		"tiles": _tiles.duplicate(),
		"anchor": _anchor_index
	}
