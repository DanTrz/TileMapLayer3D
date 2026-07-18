@tool
extends Resource
class_name TileAnimData

@export var item_id: int = 0:
	set(value):
		if item_id != value:
			item_id = value
			emit_changed()

@export var display_name: String = "":
	set(value):
		if display_name != value:
			display_name = value
			emit_changed()

@export var selection_uv_rects: Array[Rect2]= []:
	set(value):
		if selection_uv_rects != value:
			selection_uv_rects = value
			emit_changed()

@export var base_tile_size: Vector2 = Vector2(0, 0):
	set(value):
		if base_tile_size != value:
			base_tile_size = value
			emit_changed()


@export var rows: int = 1:
	set(value):
		value = maxi(value, 1)
		if rows != value:
			rows = value
			emit_changed()

@export var columns: int = 1:
	set(value):
		value = maxi(value, 1)
		if columns != value:
			columns = value
			emit_changed()

@export var frames: int = 1:
	set(value):
		value = maxi(value, 1)
		if frames != value:
			frames = value
			emit_changed()

@export var speed: float = 0.0:
	set(value):
		value = clampf(value, 0.0, 255.0)
		if speed != value:
			speed = value
			emit_changed()
