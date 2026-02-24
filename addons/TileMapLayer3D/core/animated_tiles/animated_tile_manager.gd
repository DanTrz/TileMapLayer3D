@tool
extends PanelContainer
class_name AnimatedTileManager


@onready var anim_tile_row: SpinBox = %AnimTileRow
@onready var anim_tile_col: SpinBox = %AnimTileCol
@onready var anim_tile_frames: SpinBox = %AnimTileFrames
@onready var anim_tile_speed: SpinBox = %AnimTileSpeed

@onready var create_anim_tile_button: Button = %CreateAnimTileButton
@onready var delete_anim_tile_button: Button = %DeleteAnimTileButton
@onready var anim_tile_items_list: ItemList = %AnimTileItemsList

var selected_tiles: Array[Rect2] = []
var base_tile_size: Vector2 = Vector2.ZERO


var current_node: TileMapLayer3D = null  # Reference passed by TileSetPanel

func _ready() -> void:
	_connect_signals()

func _connect_signals() -> void:
	if not anim_tile_items_list.item_selected.is_connected(_on_anim_tile_selected):
		anim_tile_items_list.item_selected.connect(_on_anim_tile_selected)

	if not create_anim_tile_button.pressed.is_connected(_on_create_anim_tile_btn_pressed):
		create_anim_tile_button.pressed.connect(_on_create_anim_tile_btn_pressed)

	if not delete_anim_tile_button.pressed.is_connected(_on_delete_anim_tile_btn_pressed):
		delete_anim_tile_button.pressed.connect(_on_delete_anim_tile_btn_pressed)


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
func on_tileset_selection_changed(selected_uv_tiles: Array[Rect2], _tile_size: Vector2) -> void:
	selected_tiles = selected_uv_tiles
	base_tile_size = _tile_size	
	print("AnimatedTileManager Updated Selected UVs: ", selected_tiles)

	# This method can be used to sync UV selection with animated tile settings if needed.
	# For example, you could check if the selected UV matches any animated tile's uv_rect and select it in the list.
	pass


func load_animated_tile_settings(default_idx_selected: int = 0) -> void:
	if not current_node:
		return
	
	var settings = current_node.settings
	if not settings:
		return

	anim_tile_items_list.clear()

	print("Loading animated tiles: ", settings.animate_tiles_list.size(), " found in settings.")
	for item_id in settings.animate_tiles_list.keys():
		var anim_data: TileAnimData = settings.animate_tiles_list[item_id]

		# Add an item to the UI List
		var anim_item_index = anim_tile_items_list.add_item(anim_data.display_name, null, true)

		#Ensure this item has the correct referecent to the animated tile data via metadata (used for selection sync and deletion)
		anim_tile_items_list.set_item_metadata(anim_item_index, anim_data.item_id)
	
	if anim_tile_items_list.get_item_count() > 0:
		var clamped_index: int = clampi(default_idx_selected, 0, anim_tile_items_list.get_item_count() - 1)
		anim_tile_items_list.select(clamped_index)
		_on_anim_tile_selected(clamped_index)


func _on_anim_tile_selected(selected_item_index: int) -> void:
	print("Animated Tile selected:", selected_item_index)

	if not current_node:
		return
	
	var settings = current_node.settings
	if not settings:
		return

	var item_id = anim_tile_items_list.get_item_metadata(selected_item_index)
	var anim_data: TileAnimData = settings.animate_tiles_list[item_id]
	if anim_data:
		settings.active_animated_tile = item_id
		anim_tile_row.value = anim_data.rows
		anim_tile_col.value = anim_data.columns
		anim_tile_frames.value = anim_data.frames
		anim_tile_speed.value = anim_data.speed
		print("Loaded tile data: ", anim_data.display_name, " with UVs: ", anim_data.selection_uv_rects)
	

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


	settings.animate_tiles_list[new_anim_data.item_id] = new_anim_data
	# Dictionary was modified in-place so the setter never fires -- must emit manually
	settings.emit_changed()

	# Reload list; newly added item will be last in the list
	var new_index: int = settings.animate_tiles_list.size() - 1
	load_animated_tile_settings(new_index)

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
	var item_id: int = anim_tile_items_list.get_item_metadata(selected_ui_index) as int

	if settings.animate_tiles_list.has(item_id):
		settings.animate_tiles_list.erase(item_id)
		settings.emit_changed()

	var new_select_index: int = maxi(selected_ui_index - 1, 0)
	load_animated_tile_settings(new_select_index)
