extends RefCounted
class_name SelectionManager

## Single source of truth for tile selection state.

signal selection_changed(tiles: Array[Rect2], anchor: int)
signal selection_cleared()

# --- Private State ---

var _tiles: Array[Rect2] = []
var _anchor_index: int = 0


# --- Public Api ---

func select(tiles: Array[Rect2], anchor: int = 0) -> void:
	_tiles = tiles.duplicate()
	_anchor_index = clampi(anchor, 0, maxi(0, _tiles.size() - 1))
	selection_changed.emit(_tiles, _anchor_index)


func clear() -> void:
	_tiles.clear()
	_anchor_index = 0
	selection_cleared.emit()


func get_tiles() -> Array[Rect2]:
	return _tiles.duplicate()


# returns internal array — caller must not mutate
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

# call on node selection; set emit_signals=true if PlacementManager needs to sync
func restore_from_settings(tiles: Array[Rect2], anchor: int, emit_signals: bool = false) -> void:
	_tiles = tiles.duplicate()
	_anchor_index = clampi(anchor, 0, maxi(0, _tiles.size() - 1))
	if emit_signals and _tiles.size() > 0:
		selection_changed.emit(_tiles, _anchor_index)


func get_data_for_settings() -> Dictionary:
	return {
		"tiles": _tiles.duplicate(),
		"anchor": _anchor_index
	}
