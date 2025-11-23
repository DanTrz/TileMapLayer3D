@tool
class_name TilesetDisplay
extends TextureRect

## Custom TextureRect for tileset display with input handling
## Exists inside SubViewport to receive Camera2D-transformed input

signal tile_clicked(position: Vector2)
signal tile_drag_started(position: Vector2)
signal tile_drag_updated(position: Vector2)
signal tile_drag_ended(position: Vector2)
signal zoom_requested(direction: int, focal_point: Vector2)  # 1 = in, -1 = out

func _ready() -> void:
	if not Engine.is_editor_hint(): return
	# CRITICAL: Do NOT force MOUSE_FILTER_STOP here - it prevents Grid Size SpinBox from receiving input
	# Let the .tscn file control mouse_filter setting (should be MOUSE_FILTER_PASS)
	# print("TilesetDisplay: Ready and listening for input")

func _gui_input(event: InputEvent) -> void:
	# print("████ TILESET DISPLAY INPUT ████")
	# print("  Event: ", event.get_class())
	# if event is InputEventMouse:
	# 	print("  Position: ", event.position)
	# 	print("  Global Position: ", event.global_position)

	# CRITICAL: Only process input if mouse is within texture bounds
	# This prevents hijacking input from UI controls above (like Grid Size SpinBox)
	if event is InputEventMouse:
		var local_pos: Vector2 = event.position
		var texture_rect: Rect2 = Rect2(Vector2.ZERO, size)
		if not texture_rect.has_point(local_pos):
			# Mouse is outside texture bounds - don't consume event
			return

	if event is InputEventMouseButton:
		# print("  Button: ", event.button_index)
		# print("  Pressed: ", event.pressed)
		# print("  Ctrl: ", event.ctrl_pressed, " | Meta: ", event.meta_pressed)

		# Zoom handling
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.ctrl_pressed or event.meta_pressed:
				if event.pressed:
					var direction: int = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
					zoom_requested.emit(direction, event.position)
					accept_event()
					return
			# Let parent handle scrolling if no modifier
			return

		# Left click for tile selection
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# print("  → Emitting tile_drag_started")
				tile_drag_started.emit(event.position)
				accept_event()
			else:
				# print("  → Emitting tile_drag_ended")
				tile_drag_ended.emit(event.position)
				accept_event()

	elif event is InputEventMouseMotion:
		# print("  Motion: ", event.position)
		tile_drag_updated.emit(event.position)
