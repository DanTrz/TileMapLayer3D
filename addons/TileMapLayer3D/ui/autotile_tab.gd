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

## Emitted when TileSet content changes (terrains added, peering bits painted, etc.)
## Use this to trigger rebuild of autotile lookup tables
signal tileset_data_changed()

## Emitted when autotile depth scale changes (for BOX/PRISM mesh modes)
signal autotile_depth_changed(depth: float)

# === NODE REFERENCES (scene-based) ===

@onready var _tileset_path_label: Label = %TileSetPathLabel
@onready var _load_tileset_button: Button = %LoadTileSetButton
@onready var _create_tileset_button: Button = %CreateTileSetButton
@onready var _save_tileset_button: Button = %SaveTileSetButton
@onready var _open_editor_button: Button = %OpenEditorButton
@onready var _terrain_list: ItemList = %TerrainList
@onready var _status_label: Label = %StatusLabel
@onready var _load_dialog: FileDialog = %AutotileLoadDialog
@onready var _save_dialog: FileDialog = %AutotileSaveDialog

# Terrain management UI
@onready var _add_terrain_button: Button = %AddTerrainButton
@onready var _remove_terrain_button: Button = %RemoveTerrainButton
@onready var _terrain_name_input: LineEdit = %TerrainNameInput
@onready var _terrain_color_picker: ColorPickerButton = %TerrainColorPicker

# Depth control (scene-based node reference)
@onready var auto_tile_detph_spin_box: SpinBox = %AutoTileDetphSpinBox

# === STATE ===

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

	# REMOVED: Hardcoded depth initialization
	# Depth will be set by plugin's _edit() → set_depth_value()
	# Settings are the source of truth, not UI initialization



func _connect_signals() -> void:
	# TileSet buttons
	if not _load_tileset_button.pressed.is_connected(_on_load_pressed):
		_load_tileset_button.pressed.connect(_on_load_pressed)

	if not _create_tileset_button.pressed.is_connected(_on_create_pressed):
		_create_tileset_button.pressed.connect(_on_create_pressed)

	if not _save_tileset_button.pressed.is_connected(_on_save_pressed):
		_save_tileset_button.pressed.connect(_on_save_pressed)

	if not _open_editor_button.pressed.is_connected(_on_open_editor_pressed):
		_open_editor_button.pressed.connect(_on_open_editor_pressed)

	# Terrain list
	if not _terrain_list.item_selected.is_connected(_on_terrain_selected):
		_terrain_list.item_selected.connect(_on_terrain_selected)

	# File dialogs
	if not _load_dialog.file_selected.is_connected(_on_load_dialog_file_selected):
		_load_dialog.file_selected.connect(_on_load_dialog_file_selected)

	if not _save_dialog.file_selected.is_connected(_on_save_dialog_file_selected):
		_save_dialog.file_selected.connect(_on_save_dialog_file_selected)

	# Terrain management buttons
	if not _add_terrain_button.pressed.is_connected(_on_add_terrain_pressed):
		_add_terrain_button.pressed.connect(_on_add_terrain_pressed)

	if not _remove_terrain_button.pressed.is_connected(_on_remove_terrain_pressed):
		_remove_terrain_button.pressed.connect(_on_remove_terrain_pressed)

	# Depth spinbox
	if auto_tile_detph_spin_box and not auto_tile_detph_spin_box.value_changed.is_connected(_on_depth_changed):
		auto_tile_detph_spin_box.value_changed.connect(_on_depth_changed)




## Handler for depth spinbox value change
func _on_depth_changed(value: float) -> void:
	if _is_loading_depth:
		return
	autotile_depth_changed.emit(value)


## Set depth value programmatically (used when restoring from settings)
func set_depth_value(depth: float) -> void:
	if auto_tile_detph_spin_box:
		_is_loading_depth = true
		auto_tile_detph_spin_box.value = depth
		_is_loading_depth = false


## Get current depth value from spinbox
func get_depth_value() -> float:
	if auto_tile_detph_spin_box:
		return auto_tile_detph_spin_box.value
	return 0.1  # Default


# === BUTTON HANDLERS ===

func _on_load_pressed() -> void:
	_load_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_DEFAULT))


func _on_create_pressed() -> void:
	# Get tile size and texture from parent TilesetPanel (Manual Tab) - single source of truth
	var tile_size: Vector2i = GlobalConstants.DEFAULT_TILE_SIZE  # Fallback
	var texture: Texture2D = null
	var parent_panel: TilesetPanel = _find_parent_tileset_panel()
	if parent_panel:
		tile_size = parent_panel.get_tile_size()
		texture = parent_panel.get_tileset_texture()

	# Create a new TileSet with the correct tile size
	var tileset := TileSet.new()
	tileset.tile_size = tile_size

	# Add default terrain set
	tileset.add_terrain_set(0)
	tileset.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)

	# If texture exists in Manual tab, auto-add atlas source with tile grid
	if texture:
		# Check if texture is compressed and auto-fix if needed
		if _is_texture_compressed(texture):
			_update_status("Fixing compressed texture for TileSet compatibility...")
			var fixed: bool = await _auto_fix_texture_compression(texture)
			if fixed:
				# Reload texture after reimport to get uncompressed version
				texture = ResourceLoader.load(texture.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)

		_add_atlas_source_with_texture(tileset, texture, tile_size)
		set_tileset(tileset)
		var tiles_x: int = int(texture.get_width()) / tile_size.x
		var tiles_y: int = int(texture.get_height()) / tile_size.y
		_update_status("New TileSet created with atlas (%dx%d tiles). Configure terrains and paint peering bits." % [tiles_x, tiles_y])
	else:
		set_tileset(tileset)
		_update_status("New TileSet created (tile size: %dx%d). Load texture in Manual tab first, or add atlas source manually." % [tile_size.x, tile_size.y])


func _on_save_pressed() -> void:
	if _current_tileset:
		_save_dialog.popup_centered(GlobalUtil.scale_ui_size(GlobalConstants.UI_DIALOG_SIZE_DEFAULT))


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

	# Add terrain to TileSet using color from picker
	_current_tileset.add_terrain(terrain_set, terrain_index)
	_current_tileset.set_terrain_name(terrain_set, terrain_index, terrain_name)
	_current_tileset.set_terrain_color(terrain_set, terrain_index, _terrain_color_picker.color)

	# Clear input and set new random color for next terrain
	_terrain_name_input.text = ""
	_terrain_color_picker.color = _generate_random_color()
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
	return Color(
		randf_range(GlobalConstants.TERRAIN_COLOR_MIN, GlobalConstants.TERRAIN_COLOR_MAX),
		randf_range(GlobalConstants.TERRAIN_COLOR_MIN, GlobalConstants.TERRAIN_COLOR_MAX),
		randf_range(GlobalConstants.TERRAIN_COLOR_MIN, GlobalConstants.TERRAIN_COLOR_MAX)
	)


## Called when the TileSet resource changes externally (e.g., in Godot's TileSet Editor)
func _on_tileset_resource_changed() -> void:
	# Prevent recursive updates during our own modifications
	if _is_loading:
		return
	# Refresh terrain list to reflect external changes
	refresh_terrains()
	# Refresh label in case resource_path changed (e.g., after scene save embeds the resource)
	if _current_tileset and _tileset_path_label:
		_tileset_path_label.text = _current_tileset.resource_path if _current_tileset.resource_path else "Unsaved TileSet"
	# Notify parent that TileSet data changed (for rebuilding autotile engine)
	tileset_data_changed.emit()


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
		_status_label.add_theme_color_override("font_color", GlobalConstants.STATUS_WARNING_COLOR)


func _clear_texture_warning() -> void:
	# Reset status label color to default gray
	if _status_label:
		_status_label.add_theme_color_override("font_color", GlobalConstants.STATUS_DEFAULT_COLOR)


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

	# Disconnect from old tileset's changed signal
	if _current_tileset and _current_tileset.changed.is_connected(_on_tileset_resource_changed):
		_current_tileset.changed.disconnect(_on_tileset_resource_changed)

	_current_tileset = tileset

	if tileset:
		# Connect to new tileset's changed signal for real-time updates
		if not tileset.changed.is_connected(_on_tileset_resource_changed):
			tileset.changed.connect(_on_tileset_resource_changed)
		_terrain_reader = TileSetTerrainReader.new(tileset)
		if _tileset_path_label:
			_tileset_path_label.text = tileset.resource_path if tileset.resource_path else "Unsaved TileSet"
		if _save_tileset_button:
			_save_tileset_button.disabled = false
		if _open_editor_button:
			_open_editor_button.disabled = false
		if _add_terrain_button:
			_add_terrain_button.disabled = false
		if _remove_terrain_button:
			_remove_terrain_button.disabled = true  # Re-enabled when terrain selected
		_populate_terrain_list()
	else:
		_terrain_reader = null
		if _tileset_path_label:
			_tileset_path_label.text = "No TileSet loaded"
		if _save_tileset_button:
			_save_tileset_button.disabled = true
		if _open_editor_button:
			_open_editor_button.disabled = true
		if _add_terrain_button:
			_add_terrain_button.disabled = true
		if _remove_terrain_button:
			_remove_terrain_button.disabled = true
		if _terrain_list:
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


## Refresh the TileSet path label (call when tab becomes visible to catch resource_path changes after save)
func refresh_path_label() -> void:
	if _tileset_path_label and _current_tileset:
		_tileset_path_label.text = _current_tileset.resource_path if _current_tileset.resource_path else "Unsaved TileSet"
	elif _tileset_path_label:
		_tileset_path_label.text = "No TileSet loaded"


## Select a terrain by ID
func select_terrain(terrain_id: int) -> void:
	for i: int in range(_terrain_list.item_count):
		if _terrain_list.get_item_metadata(i) == terrain_id:
			_terrain_list.select(i)
			break


# === PRIVATE METHODS ===

func _populate_terrain_list() -> void:
	_terrain_list.clear()

	if not _terrain_reader:
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
			_status_label.add_theme_color_override("font_color", GlobalConstants.STATUS_DEFAULT_COLOR)


## Find parent TilesetPanel by traversing up the scene tree
## Used to get tile_size from Manual Tab when creating TileSets
func _find_parent_tileset_panel() -> TilesetPanel:
	var node: Node = get_parent()
	while node:
		if node is TilesetPanel:
			return node as TilesetPanel
		node = node.get_parent()
	return null


## Creates a TileSetAtlasSource from texture and adds it to the TileSet
## Automatically creates tile grid covering the entire texture
func _add_atlas_source_with_texture(tileset: TileSet, texture: Texture2D, tile_size: Vector2i) -> void:
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = tile_size

	# Add to tileset at source ID 0
	tileset.add_source(atlas, GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID)

	# Create tiles for entire texture grid
	var texture_size: Vector2i = Vector2i(int(texture.get_width()), int(texture.get_height()))
	var tiles_x: int = texture_size.x / tile_size.x
	var tiles_y: int = texture_size.y / tile_size.y

	for y in range(tiles_y):
		for x in range(tiles_x):
			atlas.create_tile(Vector2i(x, y))


## Fixes compressed texture by changing import settings to Lossless and reimporting
## Returns true if successful, false if failed
func _auto_fix_texture_compression(texture: Texture2D) -> bool:
	if not texture or texture.resource_path.is_empty():
		return false

	var texture_path: String = texture.resource_path
	var import_path: String = texture_path + ".import"

	# Step 1: Modify .import file
	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		_update_status("Error: Cannot access .import file for texture")
		return false

	# Change to Lossless (0) - required for TileSet peering bit painting
	config.set_value("params", "compress/mode", 0)

	if config.save(import_path) != OK:
		_update_status("Error: Cannot save .import file")
		return false

	# Step 2: Trigger reimport
	var editor_fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	editor_fs.reimport_files([texture_path])

	# Step 3: Wait for reimport to complete (async)
	await editor_fs.filesystem_changed

	_update_status("Texture decompressed successfully!")
	return true
