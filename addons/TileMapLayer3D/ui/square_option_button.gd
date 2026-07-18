@tool
class_name SquareOptionButton
extends OptionButton

@export var items_list: Dictionary[String, String]
@export var icon_size: Vector2 = Vector2(16, 16)


func _ready():
	create_items_from_enum()
	fit_to_longest_item = false
	clip_text = true
	
	add_theme_constant_override("arrow_margin", 0)
	add_theme_constant_override("h_separation", 0)
	
	item_selected.connect(_on_item_selected)
	
	_on_item_selected(selected)
	
	apply_opt_button_theme()

func _on_item_selected(_index: int):
	text = ""

func apply_opt_button_theme() -> void:
	var scale: float = GlobalUtil.get_editor_ui_scale()
		
	var icon_size = GlobalConstants.BUTTOM_CONTEXT_UI_SIZE  * scale
	custom_minimum_size = Vector2(icon_size, icon_size)

	fit_to_longest_item = false
	clip_text = true

func create_items_from_enum() -> void:
	clear()
	var scale: float = GlobalUtil.get_editor_ui_scale()
	var ei: Object = Engine.get_singleton("EditorInterface")

	var index = 0
	for value in items_list.values():
		
		var icon:Texture2D = null
		if EditorInterface.get_editor_theme().has_icon(value, "EditorIcons"):
			icon = ei.get_editor_theme().get_icon(value, "EditorIcons")
		else:
			icon = ei.get_editor_theme().get_icon("BoneMapperHandleCircle", "EditorIcons")
		
		var text = items_list.keys()[index]

		var image = icon.get_image()
		image.decompress()
		
		if icon_size.x <= 0 and icon_size.y <= 0:
			icon_size = Vector2(icon.get_width(), icon.get_height())

		image.resize(icon_size.x * scale, icon_size.y * scale, Image.INTERPOLATE_NEAREST)
		
		image.adjust_bcs(1.0, 1.0, 0.0)
		var grey_icon = ImageTexture.create_from_image(image)

		if not grey_icon:
			grey_icon = ei.get_editor_theme().get_icon("BoneMapperHandleCircle", "EditorIcons")
		
		add_icon_item(grey_icon, text, index)
		index += 1
