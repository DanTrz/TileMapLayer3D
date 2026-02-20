@tool
class_name TilesetDisplay
extends TextureRect

## Custom TextureRect for tileset display with input handling
## Pattern based on TileModeller's tileset_palette.gd

signal tile_drag_started(position: Vector2)
signal tile_drag_updated(position: Vector2)
signal tile_drag_ended(position: Vector2)
signal zoom_requested(direction: int, focal_point: Vector2)  # 1 = in, -1 = out
signal select_vertices_data_changed(tile: Vector2i, vertices: Array)  # Emitted when vertex are edited in POINTS mode

var tileset_panel: TilesetPanel = null

var _is_panning: bool = false

# TILE mode selection state
var _is_selecting: bool = false
var _select_start_tile: Vector2i = Vector2i.ZERO
var _select_end_tile: Vector2i = Vector2i.ZERO

# POINTS mode state (vertex editing mode)
var _dragging_vertex: bool = false
var _active_tile: Vector2i = Vector2i.ZERO
var _active_vertex: int = -1
var _hover_vertex: int = -1
var _tile_vertices: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]  # BL, BR, TR, TL


func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	# Get parent panel reference early
	if owner is TilesetPanel:
		tileset_panel = owner
	else:
		push_error("TilesetDisplay: Owner must be TilesetPanel!")

	# Connect draw signal
	draw.connect(_on_draw)


func _gui_input(event: InputEvent) -> void:
	if not tileset_panel or not texture:
		return

	# Route zoom to TilesetPanel via signal (Signal Up pattern)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var direction: int = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
				zoom_requested.emit(direction, event.position)
			accept_event()
			return
	
	# Pan with middle mouse button
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_is_panning = event.pressed
		accept_event()
		return

	if event is InputEventMouseMotion and _is_panning:
		tileset_panel.scroll_container.scroll_horizontal -= int(event.relative.x)
		tileset_panel.scroll_container.scroll_vertical -= int(event.relative.y)
		accept_event()
		return
	#end of Pan handling
	
	var tile_size: Vector2i = tileset_panel._tile_size
	var atlas_size: Vector2i = texture.get_size()

	# Route to appropriate handler based on UV select mode
	match tileset_panel.tile_uvmode_dropdown.selected:
		GlobalConstants.Tile_UV_Select_Mode.TILE:
			_handle_tile_selection(event, atlas_size, tile_size)
		GlobalConstants.Tile_UV_Select_Mode.POINTS:
			_handle_tile_vertex_edit(event, atlas_size, tile_size)
		_:
			push_warning("TilesetDisplay: Unknown Tile UV Select Mode!")


# ==============================================================================
# TILE MODE - Grid-based tile selection (current implementation)
# ==============================================================================

func _handle_tile_selection(event: InputEvent, atlas_size: Vector2i, tile_size: Vector2i) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Start selection
			_is_selecting = true
			_select_start_tile = _mouse_to_tile(event.position, atlas_size, tile_size)
			_select_end_tile = _select_start_tile
		else:
			# End selection - finalize tile list
			_is_selecting = false
			_finalize_tile_selection()

	elif event is InputEventMouseMotion and _is_selecting:
		# Update selection preview
		_select_end_tile = _mouse_to_tile(event.position, atlas_size, tile_size)
		_update_tile_selection_preview()


## clear the selection and selection preview
func clear_selection() -> void:
	tileset_panel._selected_tiles.clear()
	queue_redraw()


## Updates the selection preview during drag (doesn't modify saved state)
func _update_tile_selection_preview() -> void:
	if not tileset_panel:
		return

	tileset_panel._selected_tiles.clear()

	var min_x: int = min(_select_start_tile.x, _select_end_tile.x)
	var max_x: int = max(_select_start_tile.x, _select_end_tile.x)
	var min_y: int = min(_select_start_tile.y, _select_end_tile.y)
	var max_y: int = max(_select_start_tile.y, _select_end_tile.y)

	var tile_size: Vector2 = Vector2(tileset_panel._tile_size)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			# Convert tile coordinates to UV rectangle
			var uv_rect: Rect2 = Rect2(
				Vector2(x, y) * tile_size,
				tile_size
			)
			tileset_panel._selected_tiles.append(uv_rect)

	queue_redraw()


## Finalizes the tile selection and emits signals
func _finalize_tile_selection() -> void:
	if not tileset_panel or not texture:
		return

	tileset_panel._selected_tiles.clear()

	var min_x: int = min(_select_start_tile.x, _select_end_tile.x)
	var max_x: int = max(_select_start_tile.x, _select_end_tile.x)
	var min_y: int = min(_select_start_tile.y, _select_end_tile.y)
	var max_y: int = max(_select_start_tile.y, _select_end_tile.y)

	var tile_size: Vector2 = Vector2(tileset_panel._tile_size)
	var texture_size: Vector2 = texture.get_size()
	var tiles_added: int = 0

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			# CRITICAL: Enforce selection limit to prevent crashes
			if tiles_added >= GlobalConstants.PREVIEW_POOL_SIZE:
				var total_tiles: int = (max_x - min_x + 1) * (max_y - min_y + 1)
				push_warning("TilesetDisplay: Selection capped at %d tiles (tried to select %d)" % [GlobalConstants.PREVIEW_POOL_SIZE, total_tiles])
				break

			# Convert tile coordinates to UV rectangle
			var uv_rect: Rect2 = Rect2(
				Vector2(x, y) * tile_size,
				tile_size
			)

			# CRITICAL: Validate bounds - skip tiles outside texture
			if uv_rect.position.x >= texture_size.x or uv_rect.position.y >= texture_size.y:
				continue

			tileset_panel._selected_tiles.append(uv_rect)
			tiles_added += 1

		# Break outer loop if limit reached
		if tiles_added >= GlobalConstants.PREVIEW_POOL_SIZE:
			break

	# CRITICAL: Save selection to settings for persistence
	tileset_panel._save_ui_to_settings()

	# CRITICAL: Emit signals for SelectionManager and downstream systems
	tileset_panel._emit_selection_signals()

	# CRITICAL: Release focus to return input to 3D viewport (WASD navigation)
	if has_focus():
		release_focus()

	# Notify panel to update selection state
	tileset_panel.notify_property_list_changed()
	queue_redraw()


# ==============================================================================
# POINTS MODE - vertex editing (for custom tile shapes)
# ==============================================================================

func _handle_tile_vertex_edit(event: InputEvent, atlas_size: Vector2i, tile_size: Vector2i) -> void:
	# If no tile selected, can't edit vertex
	if tileset_panel._selected_tiles.is_empty():
		return

	# Mouse button events
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Check if clicking near a vertex handle
			var draw_rect := _get_texture_rect()
			var scale: Vector2 = draw_rect.size / Vector2(atlas_size)

			var handles := _get_vertices_screen_positions(
				_active_tile,
				_tile_vertices,
				draw_rect,
				Vector2(tile_size),
				scale
			)

			_active_vertex = _pick_vertices_screen(event.position, handles, scale)
			if _active_vertex != -1:
				_dragging_vertex = true
		else:
			# Mouse released - finalize vertex position
			if _dragging_vertex:
				_finalize_vertice_edit()
			_dragging_vertex = false
			_active_vertex = -1

	# Mouse motion events
	elif event is InputEventMouseMotion:
		if _dragging_vertex and _active_vertex != -1:
			# Drag active vertex
			var atlas_pixel := _mouse_to_atlas_pixel(event.position, atlas_size)
			var tile_origin := Vector2(_active_tile) * Vector2(tile_size)
			var pixel := atlas_pixel - tile_origin

			# Snap to pixels (can add subpixel snapping later)
			pixel.x = round(pixel.x)
			pixel.y = round(pixel.y)

			# Clamp to tile bounds
			pixel.x = clamp(pixel.x, 0, tile_size.x)
			pixel.y = clamp(pixel.y, 0, tile_size.y)

			_tile_vertices[_active_vertex] = pixel
			queue_redraw()

		elif not _dragging_vertex:
			# Hover detection - highlight vertex handle under mouse
			var hover_tile := _mouse_to_tile(event.position, atlas_size, tile_size)

			# Check if hovering over a selected tile
			var is_hovering_selected: bool = false
			for uv_rect in tileset_panel._selected_tiles:
				var tile_coord := Vector2i(
					int(uv_rect.position.x / tile_size.x),
					int(uv_rect.position.y / tile_size.y)
				)
				if tile_coord == hover_tile:
					is_hovering_selected = true
					break

			if not is_hovering_selected:
				_hover_vertex = -1
				queue_redraw()
				return

			var draw_rect := _get_texture_rect()
			var scale: Vector2 = draw_rect.size / Vector2(atlas_size)

			var handles := _get_vertices_screen_positions(
				hover_tile,
				_tile_vertices,
				draw_rect,
				Vector2(tile_size),
				scale
			)

			_hover_vertex = _pick_vertices_screen(event.position, handles, scale)
			_active_tile = hover_tile
			queue_redraw()


func _finalize_vertice_edit() -> void:
	# Emit signal with vertex data for TilesetPanel to handle
	select_vertices_data_changed.emit(_active_tile, _tile_vertices)
	print("TilesetDisplay: Vertice select edit finalized - tile: ", _active_tile, " vertex: ", _tile_vertices)


## Initialize vertex positions for a tile (called when switching to POINTS mode)
func initialize_tile_vertices(tile_coord: Vector2i, tile_size: Vector2i) -> void:
	_active_tile = tile_coord
	# Initialize vertex to tile bounds [BL, BR, TR, TL]
	_tile_vertices = [
		Vector2(0, tile_size.y),           # Bottom-Left
		Vector2(tile_size.x, tile_size.y), # Bottom-Right
		Vector2(tile_size.x, 0),           # Top-Right
		Vector2(0, 0)                      # Top-Left
	]
	queue_redraw()


func _get_vertices_screen_positions(
	tile: Vector2i,
	vertices: Array,
	draw_rect: Rect2,
	tile_size: Vector2,
	scale: Vector2
) -> Array:
	var result := []
	for c in vertices:
		result.append(
			draw_rect.position
			+ (Vector2(tile) * tile_size + c) * scale
		)
	return result


func _pick_vertices_screen(
	mouse_pos: Vector2,
	handles: Array,
	scale: Vector2
) -> int:
	var radius := _get_handle_pick_radius(scale)
	var max_dist_sq := radius * radius

	var best := -1
	var best_dist := INF

	for i in handles.size():
		var d := mouse_pos.distance_squared_to(handles[i])
		if d < max_dist_sq and d < best_dist:
			best_dist = d
			best = i

	return best


func _get_handle_pick_radius(scale: Vector2) -> float:
	# 6 px at 1:1, grows when zoomed out
	return max(6.0, 12.0 / scale.x)


func _mouse_to_atlas_pixel(pos: Vector2, atlas_size: Vector2i) -> Vector2:
	var draw_rect := _get_texture_rect()
	var local := pos - draw_rect.position
	var atlas_pos := local / draw_rect.size * Vector2(atlas_size)
	return atlas_pos


# ==============================================================================
# DRAWING
# ==============================================================================

func _on_draw() -> void:
	if not tileset_panel or not texture:
		return

	var draw_rect: Rect2 = _get_texture_rect()
	var scale: Vector2 = draw_rect.size / Vector2(texture.get_size())

	# Draw based on current UV select mode
	match tileset_panel.tile_uvmode_dropdown.selected:
		GlobalConstants.Tile_UV_Select_Mode.TILE:
			var tile_size_f: Vector2 = Vector2(tileset_panel._tile_size)
			_draw_tile_selection(draw_rect, tile_size_f, scale)
		GlobalConstants.Tile_UV_Select_Mode.POINTS:
			var tile_size_f: Vector2 = Vector2(tileset_panel._tile_size)
			_draw_vertices_handles(draw_rect, tile_size_f, scale)


## Draws selection rectangles for selected tiles
## @param draw_rect: Rectangle where texture is drawn (with centering offset)
## @param tile_size_f: Tile size in pixels (for reference, not used since we have UV rects)
## @param scale: Scale factor for drawing (texture pixels -> screen pixels)
func _draw_tile_selection(draw_rect: Rect2, tile_size_f: Vector2, scale: Vector2) -> void:
	for uv_rect in tileset_panel._selected_tiles:
		# UV rect is in texture pixel coordinates
		# Scale it to screen coordinates and offset by draw_rect position
		var screen_rect := Rect2(
			draw_rect.position + uv_rect.position * scale,
			uv_rect.size * scale
		)

		# Fill with semi-transparent color
		draw_rect(screen_rect, Color(0.3, 0.8, 1.0, 0.25), true)
		# Border with solid color
		draw_rect(screen_rect.grow(0.5), Color(0.3, 0.8, 1.0), false, 2.0)


## Draws vertex handles for POINTS mode (vertex editing)
## @param draw_rect: Rectangle where texture is drawn (with centering offset)
## @param tile_size_f: Tile size in pixels
## @param scale: Scale factor for drawing (texture pixels -> screen pixels)
func _draw_vertices_handles(draw_rect: Rect2, tile_size_f: Vector2, scale: Vector2) -> void:
	if tileset_panel._selected_tiles.is_empty():
		return

	# Draw tile outline for context
	for uv_rect in tileset_panel._selected_tiles:
		var screen_rect := Rect2(
			draw_rect.position + uv_rect.position * scale,
			uv_rect.size * scale
		)
		# Light outline to show tile bounds
		draw_rect(screen_rect, Color(0.5, 0.5, 0.5, 0.5), false, 1.0)

	# Draw vertex handles for active tile
	if not tileset_panel._selected_tiles.is_empty():
		var atlas_size: Vector2i = texture.get_size()
		var handles := _get_vertices_screen_positions(
			_active_tile,
			_tile_vertices,
			draw_rect,
			tile_size_f,
			scale
		)

		var handle_radius := _get_handle_pick_radius(scale)

		for i in handles.size():
			var handle_pos: Vector2 = handles[i]
			var handle_color: Color

			# Color coding: Active (red), Hover (yellow), Normal (white)
			if i == _active_vertex and _dragging_vertex:
				handle_color = Color(1.0, 0.2, 0.2, 1.0)  # Red - dragging
			elif i == _hover_vertex:
				handle_color = Color(1.0, 0.8, 0.0, 1.0)  # Yellow - hover
			else:
				handle_color = Color(1.0, 1.0, 1.0, 0.9)  # White - normal

			# Draw handle as circle with border
			draw_circle(handle_pos, handle_radius, handle_color)
			draw_arc(handle_pos, handle_radius, 0, TAU, 32, Color(0.0, 0.0, 0.0, 1.0), 2.0)

		# Draw lines connecting vertex to show quad shape
		if handles.size() == 4:
			var line_color := Color(0.3, 0.8, 1.0, 0.6)
			draw_line(handles[0], handles[1], line_color, 1.0)  # BL -> BR
			draw_line(handles[1], handles[2], line_color, 1.0)  # BR -> TR
			draw_line(handles[2], handles[3], line_color, 1.0)  # TR -> TL
			draw_line(handles[3], handles[0], line_color, 1.0)  # TL -> BL


# ==============================================================================
# COORDINATE HELPERS
# ==============================================================================

## Converts mouse position to tile coordinates
func _mouse_to_tile(pos: Vector2, atlas_size: Vector2i, tile_size: Vector2i) -> Vector2i:
	var draw_rect := _get_texture_rect()
	var local := pos - draw_rect.position
	var atlas_pos := local / draw_rect.size * Vector2(atlas_size)

	return Vector2i(
		int(atlas_pos.x / tile_size.x),
		int(atlas_pos.y / tile_size.y)
	)


## Gets the rectangle where the texture is actually drawn (accounting for centering and zoom)
## Based on TileModeller's get_texture_rect pattern
func _get_texture_rect() -> Rect2:
	if not texture:
		return Rect2()

	var tex_size: Vector2 = texture.get_size()  # Raw texture size — zoom is baked into self.size

	var view_size: Vector2 = size

	# Calculate scale to fit texture in view while maintaining aspect ratio
	var scale: float = min(
		view_size.x / tex_size.x,
		view_size.y / tex_size.y
	)

	var draw_size: Vector2 = tex_size * scale
	var offset: Vector2 = (view_size - draw_size) * 0.5  # Center the texture

	# Return rect with offset position for proper mouse coordinate transformation
	return Rect2(offset, draw_size)
