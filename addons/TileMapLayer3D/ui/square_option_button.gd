@tool
class_name SquareOptionButton
extends OptionButton

@export var items_list: Dictionary[String, String] #ItemName and IconName

func _ready():
	create_items_from_enum()
	fit_to_longest_item = false
	clip_text = true
	
	# Strip internal padding for a compact layout
	add_theme_constant_override("arrow_margin", 0)
	add_theme_constant_override("h_separation", 0)
	
	# Clear text on selection so only the icon shows
	item_selected.connect(_on_item_selected)
	_on_item_selected(selected)
	
	apply_opt_button_theme()

func _on_item_selected(_index: int):
	text = ""

func apply_opt_button_theme() -> void:
	# Sizing based on editor scale
	var scale: float = GlobalUtil.get_editor_ui_scale()
	# var editor_theme: Theme = GlobalUtil.get_current_theme()
		
	var icon_size = GlobalConstants.BUTTOM_CONTEXT_UI_SIZE  * scale
	custom_minimum_size = Vector2(icon_size, icon_size)

	# Prevent button from growing to fit text
	fit_to_longest_item = false
	clip_text = true

func create_items_from_enum() -> void:
	clear()
	var ei: Object = Engine.get_singleton("EditorInterface")

	var index = 0
	for value in items_list.values():
		var icon:Texture2D = ei.get_editor_theme().get_icon(value, "EditorIcons")
		var text = items_list.keys()[index]

		var image = icon.get_image()
		image.decompress()
		image.resize(icon.get_width(), icon.get_height(), Image.INTERPOLATE_NEAREST)
		image.adjust_bcs(1.0, 1.0, 0.0)
		var grey_icon = ImageTexture.create_from_image(image)

		if not grey_icon:
			grey_icon = ei.get_editor_theme().get_icon("BoneMapperHandleCircle", "EditorIcons")
		add_icon_item(grey_icon, text, index)
		index += 1
