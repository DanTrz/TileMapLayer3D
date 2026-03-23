@tool
extends PanelContainer
class_name AnimatedTileManager


@onready var anim_tile_row: SpinBox = %AnimTileRow
@onready var anim_tile_col: SpinBox = %AnimTileCol
@onready var anim_tile_frames: SpinBox = %AnimTileFrames
@onready var anim_tile_speed: SpinBox = %AnimTileSpeed
@onready var anim_tile_display_name: LineEdit = %AnimTileDisplayName

@onready var create_anim_tile_button: Button = %CreateAnimTileButton
@onready var delete_anim_tile_button: Button = %DeleteAnimTileButton
@onready var anim_tile_items_list: ItemList = %AnimTileItemsList

## Emitted when user selects an AnimTile record, carrying the frame 0 tiles to auto-select
signal anim_tile_frame0_selected(tiles: Array[Rect2])

var selected_tiles: Array[Rect2] = []
var base_tile_size: Vector2 = Vector2.ZERO
var current_texture: Texture2D = null

var current_node: TileMapLayer3D = null  # Reference passed by TileSetPanel

func _ready() -> void:
	_connect_signals()
	_load_default_ui_values()

func _load_default_ui_values() -> void:
	anim_tile_row.value = 1
	anim_tile_col.value = 1
	anim_tile_frames.value = 1
	anim_tile_speed.value = 1.0
	anim_tile_display_name.text = "AnimTile Name..."

	var ui_scale: float = GlobalUtil.get_editor_ui_scale()
	anim_tile_row.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	anim_tile_col.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	anim_tile_frames.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))
	anim_tile_speed.get_line_edit().add_theme_font_size_override("font_size", int(10 * ui_scale))

	anim_tile_display_name.add_theme_font_size_override("font_size", int(10 * ui_scale))
	
	GlobalUtil.apply_button_theme(create_anim_tile_button, "New", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)
	GlobalUtil.apply_button_theme(delete_anim_tile_button, "Remove", GlobalConstants.BUTTOM_CONTEXT_UI_SIZE)

	anim_tile_items_list.add_theme_font_size_override("font_size", int(10 * ui_scale))



func _connect_signals() -> void:
	if not anim_tile_items_list.item_selected.is_connected(_on_anim_tile_selected):
		anim_tile_items_list.item_selected.connect(_on_anim_tile_selected)

	if not create_anim_tile_button.pressed.is_connected(_on_create_anim_tile_btn_pressed):
		create_anim_tile_button.pressed.connect(_on_create_anim_tile_btn_pressed)

	if not delete_anim_tile_button.pressed.is_connected(_on_delete_anim_tile_btn_pressed):
		delete_anim_tile_button.pressed.connect(_on_delete_anim_tile_btn_pressed)

	# anim_tile_items_list.focus_exited.connect(func(): deselect_all())
	anim_tile_items_list.empty_clicked.connect(func(_pos: Vector2, _btn: int): set_anim_tile_selection(false))

#anim_tile_items_list.empty_clicked.connect(func(): set_anim_tile_selection(false))


## Resolves an ItemList UI index to the persistent dictionary key (item_id).
## The ItemList is always rebuilt from settings.animate_tiles_list.keys() in order,
## so UI index N corresponds to dictionary keys()[N]. Returns -1 if out of range.
func _get_item_id_at(ui_index: int) -> int:
	if not current_node or not current_node.settings:
		return -1
	var keys: Array = current_node.settings.animate_tiles_list.keys()
	if ui_index < 0 or ui_index >= keys.size():
		return -1
	return keys[ui_index]


## Returns max(existing_keys) + 1 to avoid ID collisions after deletions
func _generate_next_id(settings: TileMapLayerSettings) -> int:
	if settings.animate_tiles_list.is_empty():
		return 0
	var max_id: int = 0
	for key: int in settings.animate_tiles_list.keys():
		if key > max_id:
			max_id = key
	return max_id + 1


## This method is called by the TileSetPanel when the user changes their UV selection in the TileSet editor.
func on_tileset_selection_changed(selected_uv_tiles: Array[Rect2], _tile_size: Vector2,programmatically: bool) -> void:
	selected_tiles = selected_uv_tiles
	base_tile_size = _tile_size
	if not programmatically:
		set_anim_tile_selection(false)
	
	# print("AnimatedTileManager Updated Selected UVs: ", selected_tiles)

func set_anim_tile_selection(selected: bool) -> void:
	if current_node and current_node.settings:
		current_node.settings.has_animated_tile_selected = selected
		if not selected:
			current_node.settings.active_animated_tile = -1
			deselect_all()

func load_animated_tile_settings(_current_texture: Texture2D , _default_idx_selected: int = 0) -> void:
	if not current_node or not current_node.settings or not _current_texture:
		return

	current_texture = _current_texture
	var settings = current_node.settings

	anim_tile_items_list.clear()

	#Loop through the animated tiles in settings and populate the UI list
	for item_id in settings.animate_tiles_list.keys():
		var anim_data: TileAnimData = settings.animate_tiles_list[item_id]

		#Get item icon from TileSet Texture using the first UV rect (if available) as a reference
		var item_icon: Texture = null
		if _current_texture:
			if not anim_data.selection_uv_rects.is_empty():
				# var first_uv_rect: Rect2 = anim_data.selection_uv_rects[0]
				item_icon = GlobalUtil.get_first_frame_texture(_current_texture, anim_data)	

		# Add an item to the UI List (index matches dictionary keys() order)
		anim_tile_items_list.add_item(anim_data.display_name, item_icon, true)

	if anim_tile_items_list.item_count > 0:
		var clamped_index: int = clampi(_default_idx_selected, 0, anim_tile_items_list.item_count - 1)
		anim_tile_items_list.select(clamped_index)
		_on_anim_tile_selected(clamped_index)


func _on_anim_tile_selected(selected_item_index: int) -> void:
	if not current_node:
		return
	var settings: TileMapLayerSettings = current_node.settings
	if not settings:
		return
	var item_id: int = _get_item_id_at(selected_item_index)
	if item_id < 0:
		return
	if not settings.animate_tiles_list.has(item_id):
		push_warning("AnimatedTileManager: Animation ID not found in settings: ", str(item_id))
		return

	set_anim_tile_selection(true) 
	var anim_data: TileAnimData = settings.animate_tiles_list[item_id]
	if anim_data:
		settings.active_animated_tile = item_id
		anim_tile_row.value = anim_data.rows
		anim_tile_col.value = anim_data.columns
		anim_tile_frames.value = anim_data.frames
		anim_tile_speed.value = anim_data.speed
		anim_tile_display_name.text = anim_data.display_name

		# Auto-select frame 0 tiles in the tileset display (Signal Up pattern)
		var frame0_tiles: Array[Rect2] = GlobalUtil.get_anim_frame0_tiles(anim_data)
		if not frame0_tiles.is_empty():
			anim_tile_frame0_selected.emit(frame0_tiles)
	

func _on_create_anim_tile_btn_pressed() -> void:
	if not current_node:
		return

	var settings: TileMapLayerSettings = current_node.settings
	if not settings:
		return

	var new_anim_data: TileAnimData = TileAnimData.new()
	# Use max(existing_keys) + 1 to avoid ID collisions after deletions
	new_anim_data.item_id = _generate_next_id(settings)
	new_anim_data.display_name = "New AnimTile - ID: " + str(new_anim_data.item_id)
	# Duplicate to prevent shared array reference between UI state and saved data
	new_anim_data.selection_uv_rects = selected_tiles.duplicate()
	new_anim_data.rows = int(anim_tile_row.value)
	new_anim_data.columns = int(anim_tile_col.value)
	new_anim_data.frames = int(anim_tile_frames.value)
	new_anim_data.speed = anim_tile_speed.value
	new_anim_data.base_tile_size = base_tile_size
	new_anim_data.display_name = anim_tile_display_name.text


	settings.animate_tiles_list[new_anim_data.item_id] = new_anim_data
	# Dictionary was modified in-place so the setter never fires -- must emit manually
	settings.emit_changed()

	# Reload list; newly added item will be last in the list
	var new_index: int = settings.animate_tiles_list.size() - 1
	load_animated_tile_settings(current_texture,new_index)

func _on_delete_anim_tile_btn_pressed() -> void:
	if not current_node:
		return

	var settings: TileMapLayerSettings = current_node.settings
	if not settings:
		return

	var selected_indices: PackedInt32Array = anim_tile_items_list.get_selected_items()
	if selected_indices.is_empty():
		return

	var selected_ui_index: int = selected_indices[0]

	# Resolve UI index → dictionary key BEFORE any modification
	var item_id: int = _get_item_id_at(selected_ui_index)
	if item_id < 0:
		return

	if settings.animate_tiles_list.has(item_id):
		var anim_data: TileAnimData = settings.animate_tiles_list[item_id]
		var display_name: String = anim_data.display_name if anim_data else "ID:%d" % item_id
		push_warning("Deleting animation definition. Existing placed tiles will keep their baked animation data: ", display_name)
		settings.animate_tiles_list.erase(item_id)
		anim_tile_items_list.remove_item(selected_ui_index)
		settings.emit_changed()

	var new_select_index: int = maxi(selected_ui_index - 1, 0)

	if anim_tile_items_list.item_count > 0:
		load_animated_tile_settings(current_texture, new_select_index)
	else:
		_load_default_ui_values()
		settings.active_animated_tile = -1


func deselect_all() -> void:
	if not current_node:
		return
	anim_tile_items_list.deselect_all()  # Deselect to prevent confusion about which item is being edited
	# print("Delected all items in the list and deselected.")
