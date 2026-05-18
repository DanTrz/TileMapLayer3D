@tool
class_name AutotileTab
extends VBoxContainer

## UI for autotiling (TileSet management, terrain selection, status).

signal terrain_selected(terrain_id: int)

# --- Node References ---
@onready var _terrain_list: ItemList = %TerrainList

# Terrain management UI
@onready var _add_terrain_button: Button = %AddTerrainButton
@onready var _remove_terrain_button: Button = %RemoveTerrainButton
@onready var _terrain_name_input: LineEdit = %TerrainNameInput
@onready var _terrain_color_picker: ColorPickerButton = %TerrainColorPicker
@onready var open_tileset_editor_button: Button = %OpenTilesetEditorButton


# --- State ---
var _is_loading_depth: bool = false
var _current_tileset: TileSet = null
var _terrain_reader: TileSetTerrainReader = null
var _is_loading: bool = false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	call_deferred("_connect_signals")
	call_deferred("_initialize_ui_state")


## Initialize UI state that was previously done in _build_ui()
func _initialize_ui_state() -> void:
	# Set initial random color for terrain color picker
	if _terrain_color_picker:
		_terrain_color_picker.color = _generate_random_color()

	_remove_terrain_button.disabled = true


func _connect_signals() -> void:
	# Terrain list
	if not _terrain_list.item_selected.is_connected(_on_terrain_selected):
		_terrain_list.item_selected.connect(_on_terrain_selected)

	# Terrain management buttons
	if not _add_terrain_button.pressed.is_connected(_on_add_terrain_pressed):
		_add_terrain_button.pressed.connect(_on_add_terrain_pressed)

	if not _remove_terrain_button.pressed.is_connected(_on_remove_terrain_pressed):
		_remove_terrain_button.pressed.connect(_on_remove_terrain_pressed)

func _on_terrain_selected(index: int) -> void:
	if not _current_tileset:
		return
	print("_on_terrain_selected: ", index)
	var terrain_id: int = _terrain_list.get_item_metadata(index)
	terrain_selected.emit(terrain_id)

	var terrain_name: String = _terrain_list.get_item_text(index)
	# _update_status("Selected terrain: " + terrain_name)

	# Enable remove button when terrain is selected
	if _remove_terrain_button:
		_remove_terrain_button.disabled = false


func _on_add_terrain_pressed() -> void:
	if not _current_tileset:
		return

	if _current_tileset.get_terrain_sets_count() == 0:
		_current_tileset.add_terrain_set(0)
		_current_tileset.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)

	var terrain_name: String = _terrain_name_input.text.strip_edges()
	var terrain_set: int = 0

	# Default name if empty
	if terrain_name.is_empty():
		terrain_name = "Terrain " + str(_current_tileset.get_terrains_count(terrain_set))

	# Get next terrain index
	var terrain_index: int = _current_tileset.get_terrains_count(terrain_set)

	# Add terrain to TileSet using color from picker
	_current_tileset.add_terrain(terrain_set, terrain_index)
	_current_tileset.set_terrain_name(terrain_set, terrain_index, terrain_name)
	_current_tileset.set_terrain_color(terrain_set, terrain_index, _terrain_color_picker.color)

	# Clear input and set new random color for next terrain
	_terrain_name_input.text = ""
	_terrain_color_picker.color = _generate_random_color()
	refresh_terrains()
	# _update_status("Terrain '" + terrain_name + "' created")


func _on_remove_terrain_pressed() -> void:
	if not _current_tileset:
		return

	var selected: PackedInt32Array = _terrain_list.get_selected_items()
	if selected.is_empty():
		return

	var terrain_id: int = _terrain_list.get_item_metadata(selected[0])
	var terrain_name: String = _terrain_list.get_item_text(selected[0])

	# Remove terrain from TileSet
	_current_tileset.remove_terrain(0, terrain_id)

	# Disable remove button after removal
	_remove_terrain_button.disabled = true

	refresh_terrains()
	# _update_status("Terrain '" + terrain_name + "' removed")


func _generate_random_color() -> Color:
	return Color(
		randf_range(GlobalConstants.TERRAIN_COLOR_MIN, GlobalConstants.TERRAIN_COLOR_MAX),
		randf_range(GlobalConstants.TERRAIN_COLOR_MIN, GlobalConstants.TERRAIN_COLOR_MAX),
		randf_range(GlobalConstants.TERRAIN_COLOR_MIN, GlobalConstants.TERRAIN_COLOR_MAX)
	)


## Refresh terrain list (call when TileSet is modified externally)
func refresh_terrains() -> void:
	if _current_tileset:
		_terrain_reader = TileSetTerrainReader.new(_current_tileset)
		_populate_terrain_list()
		# Re-check texture format in case atlas was added/changed
		# _check_tileset_texture_format()

## Select a terrain by ID
func select_terrain(terrain_id: int) -> void:
	for i: int in range(_terrain_list.item_count):
		if _terrain_list.get_item_metadata(i) == terrain_id:
			_terrain_list.select(i)
			break

# --- Private Methods ---
func _populate_terrain_list() -> void:
	_terrain_list.clear()

	if not _terrain_reader:
		_terrain_list.add_item("No terrains configured")
		_terrain_list.set_item_disabled(0, true)
		# _update_status("No terrains found. Use 'Add Terrain' to create one.")
		return

	var terrains: Array[Dictionary] = _terrain_reader.get_terrains()

	if terrains.is_empty():
		_terrain_list.add_item("No terrains configured")
		_terrain_list.set_item_disabled(0, true)
		# _update_status("No terrains found. Use 'Add Terrain' to create one.")
		return

	for terrain: Dictionary in terrains:
		var terrain_id: int = terrain.id
		var terrain_name: String = terrain.name
		var terrain_color: Color = terrain.color

		var display_name: String = terrain_name if terrain_name else "Terrain " + str(terrain_id)
		var idx: int = _terrain_list.add_item(display_name)
		_terrain_list.set_item_metadata(idx, terrain_id)

		# Create color icon
		var icon := _create_color_icon(terrain_color)
		if icon:
			_terrain_list.set_item_icon(idx, icon)

	# _update_status("Found " + str(terrains.size()) + " terrain(s). Select one to paint.")


func _create_color_icon(color: Color) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(color)

	var tex := ImageTexture.create_from_image(img)
	return tex
