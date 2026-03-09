@tool
extends Resource
class_name TileAnimData

@export var item_id: int = 0: # Unique ID for this animated tile (used for painting reference and for UI sync)
	set(value):
		if item_id != value:
			item_id = value
			emit_changed()

@export var display_name: String = "": # User-friendly name (e.g., "Water", "Torch")
	set(value):
		if display_name != value:
			display_name = value
			emit_changed()

@export var selection_uv_rects: Array[Rect2]= []: # Pixel-space rect covering ALL frames in atlas
	set(value):
		if selection_uv_rects != value:
			selection_uv_rects = value
			emit_changed()

@export var base_tile_size: Vector2 = Vector2(0, 0): # Size of a single tile frame in pixels (e.g., 32x32)
	set(value):
		if base_tile_size != value:
			base_tile_size = value
			emit_changed()


@export var rows: int = 1: # Number of rows in the spritesheet grid (min 1)
	set(value):
		value = maxi(value, 1)
		if rows != value:
			rows = value
			emit_changed()

@export var columns: int = 1: # Number of columns in the spritesheet grid (min 1)
	set(value):
		value = maxi(value, 1)
		if columns != value:
			columns = value
			emit_changed()

@export var frames: int = 1: # Total frames to play (min 1, may be ≤ columns × rows)
	set(value):
		value = maxi(value, 1)
		if frames != value:
			frames = value
			emit_changed()

@export var speed: float = 0.0: # Playback speed in frames per second (0-255, clamped for shader encoding)
	set(value):
		value = clampf(value, 0.0, 255.0)
		if speed != value:
			speed = value
			emit_changed()
