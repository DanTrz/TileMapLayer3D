# =============================================================================
# FILE: addons/TileMapLayer3D/ui/autotile/autotile_tab.gd
# PURPOSE: Auto Tiling tab UI - TileSet management and terrain selection
# DEPENDENCIES: AutotileEngine, TileSetTerrainReader
# =============================================================================
@tool
class_name AutotileTab
extends VBoxContainer

## Auto Tiling tab content. Provides UI for:
## - Loading/creating/saving TileSet resources
## - Opening Godot's native TileSet editor
## - Selecting terrains for painting
## - Status display

# === SIGNALS ===

## Emitted when TileSet is loaded or changed
signal tileset_changed(tileset: TileSet)

## Emitted when user selects a terrain for painting
signal terrain_selected(terrain_id: int)

# === NODE REFERENCES ===

var _tileset_path_label: Label
var _load_tileset_button: Button
var _create_tileset_button: Button
var _save_tileset_button: Button
var _open_editor_button: Button
var _terrain_list: ItemList
var _status_label: Label
var _load_dialog: FileDialog
var _save_dialog: FileDialog

# Terrain management UI
var _add_terrain_button: Button
var _remove_terrain_button: Button
var _terrain_name_input: LineEdit

# === STATE ===

var _current_tileset: TileSet = null
var _terrain_reader: TileSetTerrainReader = null
var _is_loading: bool = false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	_build_ui()
	call_deferred("_connect_signals")


func _build_ui() -> void:
	# Main container with margin
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	margin.add_child(main_vbox)

	# === TILESET SECTION ===
	var tileset_label := Label.new()
	tileset_label.text = "TileSet Resource"
	tileset_label.add_theme_font_size_override("font_size", 14)
	main_vbox.add_child(tileset_label)

	# TileSet path display
	_tileset_path_label = Label.new()
	_tileset_path_label.text = "No TileSet loaded"
	_tileset_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	main_vbox.add_child(_tileset_path_label)

	# TileSet buttons row
	var tileset_buttons := HBoxContainer.new()
	main_vbox.add_child(tileset_buttons)

	_load_tileset_button = Button.new()
	_load_tileset_button.text = "Load"
	_load_tileset_button.tooltip_text = "Load an existing TileSet resource"
	tileset_buttons.add_child(_load_tileset_button)

	_create_tileset_button = Button.new()
	_create_tileset_button.text = "Create New"
	_create_tileset_button.tooltip_text = "Create a new TileSet resource"
	tileset_buttons.add_child(_create_tileset_button)

	_save_tileset_button = Button.new()
	_save_tileset_button.text = "Save As"
	_save_tileset_button.tooltip_text = "Save the TileSet to a file"
	_save_tileset_button.disabled = true
	tileset_buttons.add_child(_save_tileset_button)

	# Separator
	var sep1 := HSeparator.new()
	main_vbox.add_child(sep1)

	# Open TileSet Editor button
	_open_editor_button = Button.new()
	_open_editor_button.text = "Open TileSet Editor"
	_open_editor_button.tooltip_text = "Open Godot's native TileSet editor to configure terrains and peering bits"
	_open_editor_button.disabled = true
	main_vbox.add_child(_open_editor_button)

	# Separator
	var sep2 := HSeparator.new()
	main_vbox.add_child(sep2)

	# === TERRAIN SECTION ===
	var terrain_label := Label.new()
	terrain_label.text = "Select Terrain"
	terrain_label.add_theme_font_size_override("font_size", 14)
	main_vbox.add_child(terrain_label)

	# Terrain list
	_terrain_list = ItemList.new()
	_terrain_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_terrain_list.custom_minimum_size = Vector2(0, 100)
	_terrain_list.select_mode = ItemList.SELECT_SINGLE
	_terrain_list.allow_reselect = true
	main_vbox.add_child(_terrain_list)

	# === TERRAIN MANAGEMENT SECTION ===
	var terrain_input_row := HBoxContainer.new()
	main_vbox.add_child(terrain_input_row)

	_terrain_name_input = LineEdit.new()
	_terrain_name_input.placeholder_text = "Terrain name..."
	_terrain_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_input_row.add_child(_terrain_name_input)

	var terrain_buttons := HBoxContainer.new()
	main_vbox.add_child(terrain_buttons)

	_add_terrain_button = Button.new()
	_add_terrain_button.text = "Add Terrain"
	_add_terrain_button.tooltip_text = "Create a new terrain in this TileSet"
	_add_terrain_button.disabled = true
	terrain_buttons.add_child(_add_terrain_button)

	_remove_terrain_button = Button.new()
	_remove_terrain_button.text = "Remove"
	_remove_terrain_button.tooltip_text = "Remove the selected terrain"
	_remove_terrain_button.disabled = true
	terrain_buttons.add_child(_remove_terrain_button)

	# Separator
	var sep3 := HSeparator.new()
	main_vbox.add_child(sep3)

	# === STATUS SECTION ===
	_status_label = Label.new()
	_status_label.text = "Load a TileSet to begin"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	main_vbox.add_child(_status_label)

	# === FILE DIALOGS ===
	_load_dialog = FileDialog.new()
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.access = FileDialog.ACCESS_RESOURCES
	_load_dialog.filters = PackedStringArray(["*.tres ; TileSet Resource"])
	_load_dialog.title = "Load TileSet"
	add_child(_load_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_RESOURCES
	_save_dialog.filters = PackedStringArray(["*.tres ; TileSet Resource"])
	_save_dialog.title = "Save TileSet"
	add_child(_save_dialog)


func _connect_signals() -> void:
	if _load_tileset_button and not _load_tileset_button.pressed.is_connected(_on_load_pressed):
		_load_tileset_button.pressed.connect(_on_load_pressed)

	if _create_tileset_button and not _create_tileset_button.pressed.is_connected(_on_create_pressed):
		_create_tileset_button.pressed.connect(_on_create_pressed)

	if _save_tileset_button and not _save_tileset_button.pressed.is_connected(_on_save_pressed):
		_save_tileset_button.pressed.connect(_on_save_pressed)

	if _open_editor_button and not _open_editor_button.pressed.is_connected(_on_open_editor_pressed):
		_open_editor_button.pressed.connect(_on_open_editor_pressed)

	if _terrain_list and not _terrain_list.item_selected.is_connected(_on_terrain_selected):
		_terrain_list.item_selected.connect(_on_terrain_selected)

	if _load_dialog and not _load_dialog.file_selected.is_connected(_on_load_dialog_file_selected):
		_load_dialog.file_selected.connect(_on_load_dialog_file_selected)

	if _save_dialog and not _save_dialog.file_selected.is_connected(_on_save_dialog_file_selected):
		_save_dialog.file_selected.connect(_on_save_dialog_file_selected)

	# Terrain management buttons
	if _add_terrain_button and not _add_terrain_button.pressed.is_connected(_on_add_terrain_pressed):
		_add_terrain_button.pressed.connect(_on_add_terrain_pressed)

	if _remove_terrain_button and not _remove_terrain_button.pressed.is_connected(_on_remove_terrain_pressed):
		_remove_terrain_button.pressed.connect(_on_remove_terrain_pressed)


# === BUTTON HANDLERS ===

func _on_load_pressed() -> void:
	if _load_dialog:
		_load_dialog.popup_centered(Vector2i(800, 600))


func _on_create_pressed() -> void:
	# Create a new TileSet
	var tileset := TileSet.new()
	tileset.tile_size = GlobalConstants.DEFAULT_TILE_SIZE

	# Add default terrain set
	tileset.add_terrain_set(0)
	tileset.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)

	set_tileset(tileset)
	_update_status("New TileSet created. Add an atlas source and configure terrains in the TileSet Editor.")


func _on_save_pressed() -> void:
	if _save_dialog and _current_tileset:
		_save_dialog.popup_centered(Vector2i(800, 600))


func _on_open_editor_pressed() -> void:
	if _current_tileset:
		# This opens Godot's native TileSet editor in the bottom panel
		EditorInterface.edit_resource(_current_tileset)
		_update_status("TileSet Editor opened. Configure terrains and paint peering bits.")


func _on_terrain_selected(index: int) -> void:
	if _is_loading:
		return

	var terrain_id: int = _terrain_list.get_item_metadata(index)
	terrain_selected.emit(terrain_id)

	var terrain_name: String = _terrain_list.get_item_text(index)
	_update_status("Selected terrain: " + terrain_name)

	# Enable remove button when terrain is selected
	if _remove_terrain_button:
		_remove_terrain_button.disabled = false


func _on_add_terrain_pressed() -> void:
	if not _current_tileset:
		return

	var terrain_name: String = _terrain_name_input.text.strip_edges()
	var terrain_set: int = 0

	# Default name if empty
	if terrain_name.is_empty():
		terrain_name = "Terrain " + str(_current_tileset.get_terrains_count(terrain_set))

	# Get next terrain index
	var terrain_index: int = _current_tileset.get_terrains_count(terrain_set)

	# Add terrain to TileSet
	_current_tileset.add_terrain(terrain_set, terrain_index)
	_current_tileset.set_terrain_name(terrain_set, terrain_index, terrain_name)
	_current_tileset.set_terrain_color(terrain_set, terrain_index, _generate_random_color())

	# Clear input and refresh list
	_terrain_name_input.text = ""
	refresh_terrains()
	_update_status("Terrain '" + terrain_name + "' created")


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
	_update_status("Terrain '" + terrain_name + "' removed")


func _generate_random_color() -> Color:
	return Color(randf_range(0.3, 0.9), randf_range(0.3, 0.9), randf_range(0.3, 0.9))


## Check if a texture is using a compressed format that causes issues with TileSet editor
func _is_texture_compressed(texture: Texture2D) -> bool:
	if texture == null:
		return false

	var image: Image = texture.get_image()
	if image == null:
		return false

	var format: Image.Format = image.get_format()

	# Check for compressed formats that cause "Cannot blit_rect" errors
	# DXT/S3TC compression (Desktop)
	if format == Image.FORMAT_DXT1 or format == Image.FORMAT_DXT3 or format == Image.FORMAT_DXT5:
		return true
	# ETC compression (Mobile)
	if format == Image.FORMAT_ETC or format == Image.FORMAT_ETC2_R11 or format == Image.FORMAT_ETC2_R11S:
		return true
	if format == Image.FORMAT_ETC2_RG11 or format == Image.FORMAT_ETC2_RG11S:
		return true
	if format == Image.FORMAT_ETC2_RGB8 or format == Image.FORMAT_ETC2_RGBA8 or format == Image.FORMAT_ETC2_RGB8A1:
		return true
	# ASTC compression
	if format == Image.FORMAT_ASTC_4x4 or format == Image.FORMAT_ASTC_4x4_HDR:
		return true
	if format == Image.FORMAT_ASTC_8x8 or format == Image.FORMAT_ASTC_8x8_HDR:
		return true
	# BPTC/BC7 compression
	if format == Image.FORMAT_BPTC_RGBA or format == Image.FORMAT_BPTC_RGBF or format == Image.FORMAT_BPTC_RGBFU:
		return true

	return false


## Check the TileSet atlas texture and warn if compressed
func _check_tileset_texture_format() -> void:
	if _current_tileset == null:
		return

	if _current_tileset.get_source_count() == 0:
		return

	# Check each atlas source
	for i: int in range(_current_tileset.get_source_count()):
		var source_id: int = _current_tileset.get_source_id(i)
		var source: TileSetSource = _current_tileset.get_source(source_id)

		if source is TileSetAtlasSource:
			var atlas: TileSetAtlasSource = source as TileSetAtlasSource
			if atlas.texture and _is_texture_compressed(atlas.texture):
				_show_texture_warning(atlas.texture.resource_path)
				return

	# No compressed textures found - clear any previous warning
	_clear_texture_warning()


func _show_texture_warning(texture_path: String) -> void:
	var warning_msg: String = "WARNING: Atlas texture is compressed!\n"
	warning_msg += "Peering bit painting will fail in TileSet Editor.\n"
	warning_msg += "FIX: Select texture in FileSystem, change Import → Compress Mode to 'Lossless', click Reimport."

	_update_status(warning_msg, true)

	# Change status label color to yellow/orange for warning
	if _status_label:
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))


func _clear_texture_warning() -> void:
	# Reset status label color to default gray
	if _status_label:
		_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))


func _on_load_dialog_file_selected(path: String) -> void:
	var tileset: TileSet = load(path) as TileSet
	if tileset:
		set_tileset(tileset)
		_update_status("TileSet loaded: " + path.get_file())
	else:
		_update_status("Error: Failed to load TileSet from " + path)


func _on_save_dialog_file_selected(path: String) -> void:
	if _current_tileset:
		var error: Error = ResourceSaver.save(_current_tileset, path)
		if error == OK:
			_update_status("TileSet saved to: " + path.get_file())
		else:
			_update_status("Error: Failed to save TileSet (code: " + str(error) + ")")


# === PUBLIC METHODS ===

## Set the current TileSet (called by parent panel)
func set_tileset(tileset: TileSet) -> void:
	_is_loading = true

	_current_tileset = tileset

	if tileset:
		_terrain_reader = TileSetTerrainReader.new(tileset)
		_tileset_path_label.text = tileset.resource_path if tileset.resource_path else "Unsaved TileSet"
		_save_tileset_button.disabled = false
		_open_editor_button.disabled = false
		_add_terrain_button.disabled = false
		_remove_terrain_button.disabled = true  # Re-enabled when terrain selected
		_populate_terrain_list()
	else:
		_terrain_reader = null
		_tileset_path_label.text = "No TileSet loaded"
		_save_tileset_button.disabled = true
		_open_editor_button.disabled = true
		_add_terrain_button.disabled = true
		_remove_terrain_button.disabled = true
		_terrain_list.clear()

	tileset_changed.emit(tileset)

	# Check for compressed texture issues
	if tileset:
		call_deferred("_check_tileset_texture_format")

	_is_loading = false


## Get the current TileSet
func get_tileset() -> TileSet:
	return _current_tileset


## Refresh terrain list (call when TileSet is modified externally)
func refresh_terrains() -> void:
	if _current_tileset:
		_terrain_reader = TileSetTerrainReader.new(_current_tileset)
		_populate_terrain_list()
		# Re-check texture format in case atlas was added/changed
		_check_tileset_texture_format()


## Select a terrain by ID
func select_terrain(terrain_id: int) -> void:
	for i: int in range(_terrain_list.item_count):
		if _terrain_list.get_item_metadata(i) == terrain_id:
			_terrain_list.select(i)
			break


# === PRIVATE METHODS ===

func _populate_terrain_list() -> void:
	_terrain_list.clear()

	if not _terrain_reader or not _terrain_reader.is_valid():
		_terrain_list.add_item("No terrains configured")
		_terrain_list.set_item_disabled(0, true)
		_update_status("No terrains found. Use 'Add Terrain' to create one.")
		return

	var terrains: Array[Dictionary] = _terrain_reader.get_terrains()

	if terrains.is_empty():
		_terrain_list.add_item("No terrains configured")
		_terrain_list.set_item_disabled(0, true)
		_update_status("No terrains found. Use 'Add Terrain' to create one.")
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

	_update_status("Found " + str(terrains.size()) + " terrain(s). Select one to paint.")


func _create_color_icon(color: Color) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(color)

	var tex := ImageTexture.create_from_image(img)
	return tex


func _update_status(message: String, is_warning: bool = false) -> void:
	if _status_label:
		_status_label.text = message
		# Reset to default color unless it's a warning
		if not is_warning:
			_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
