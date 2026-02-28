extends RefCounted
class_name SelectionManager

## Single source of truth for tile selection state.

## Emitted when tile selection changes (new tiles selected)
signal selection_changed(tiles: Array[Rect2], anchor: int)

## Emitted when selection is cleared
signal selection_cleared()

# --- Private State ---

var _tiles: Array[Rect2] = []
var _anchor_index: int = 0


# --- Public Api ---

## Selects one or more tiles
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


func get_tiles() -> Array[Rect2]:
	return _tiles.duplicate()


## WARNING: Do not modify the returned array!
func get_tiles_readonly() -> Array[Rect2]:
	return _tiles


func get_anchor() -> int:
	return _anchor_index


func has_selection() -> bool:
	return _tiles.size() > 0


func has_multi_selection() -> bool:
	return _tiles.size() > 1


func get_selection_count() -> int:
	return _tiles.size()


func get_first_tile() -> Rect2:
	if _tiles.size() > 0:
		return _tiles[0]
	return Rect2()


func get_anchor_tile() -> Rect2:
	if _tiles.size() > 0 and _anchor_index < _tiles.size():
		return _tiles[_anchor_index]
	return Rect2()


# --- Persistence Helpers ---

## Restores selection from saved settings (called on node selection)
## If emit_signals is true, subscribers like PlacementManager will sync.
func restore_from_settings(tiles: Array[Rect2], anchor: int, emit_signals: bool = false) -> void:
	_tiles = tiles.duplicate()
	_anchor_index = clampi(anchor, 0, maxi(0, _tiles.size() - 1))
	# Optionally emit signal so subscribers (like PlacementManager) can sync
	if emit_signals and _tiles.size() > 0:
		selection_changed.emit(_tiles, _anchor_index)


func get_data_for_settings() -> Dictionary:
	return {
		"tiles": _tiles.duplicate(),
		"anchor": _anchor_index
	}
