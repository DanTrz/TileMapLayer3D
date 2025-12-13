extends RefCounted


const Quad = preload("./quad.gd")

var image: Image
var show_side_quads := true
var show_back_quads := true
var alpha_threshold: float: set = set_alpha_threshold
var uv_correction: float: set = set_uv_correction


func set_alpha_threshold(new_alpha_threshold: float) -> void:
	assert(alpha_threshold >= 0 and alpha_threshold <= 1)

	alpha_threshold = new_alpha_threshold


func set_uv_correction(new_uv_correction: float) -> void:
	assert(uv_correction >= 0 and uv_correction <= 1)

	uv_correction = new_uv_correction


func generate_quads() -> Array:
	var quads = []

	quads.append_array(_generate_front_quads())

	if show_back_quads:
		var back_quads = []
		for quad in quads:
			back_quads.append(quad.get_back_face().translate(Vector3.FORWARD))

		quads.append_array(back_quads)

	if show_side_quads:
		quads.append_array(_generate_side_quads())

	return quads


func _generate_front_quads() -> Array:
	var quads: Array = []

	var pixels_to_render := _get_visible_pixels()

	for x in range(image.get_width()):
		for y in range(image.get_height()):
			if pixels_to_render.get_bit(x, y):
				var rect := _get_front_quad_rect_at(x, y, pixels_to_render)
				quads.append(_generate_front_quad(rect))
				pixels_to_render.set_bit_rect(rect, false)

	return quads


func _get_front_quad_rect_at(x0: int, y0: int, pixels_to_render: BitMap) -> Rect2i:
	var rect := Rect2i(x0, y0, 1, 1)
	var expand_width := true
	var expand_height := true

	while expand_width or expand_height:
		if expand_width:
			if rect.end.x < image.get_width() and range(rect.position.y, rect.end.y).all(
				func(y: int) -> bool: return pixels_to_render.get_bit(rect.end.x, y)
			):
				rect.size.x += 1
			else:
				expand_width = false

		if expand_height:
			if rect.end.y < image.get_height() and range(rect.position.x, rect.end.x).all(
				func(x: int) -> bool: return pixels_to_render.get_bit(x, rect.end.y)
			):
				rect.size.y += 1
			else:
				expand_height = false

	return rect


func _generate_side_quads() -> Array:
	var quads = []
	var visible_pixels := _get_visible_pixels()

	quads.append_array(_generate_left_quads(visible_pixels))
	quads.append_array(_generate_right_quads(visible_pixels))
	quads.append_array(_generate_top_quads(visible_pixels))
	quads.append_array(_generate_bottom_quads(visible_pixels))

	return quads


func _generate_left_quads(visible_pixels: BitMap) -> Array:
	return _generate_vertical_quads(
		visible_pixels,
		func (x: int, y: int) -> bool:
			return x == 0 or not visible_pixels.get_bit(x - 1, y),
		func (rect: Rect2i) -> Quad:
			return _generate_front_quad(rect)\
				.rotate_along_side(SIDE_LEFT, deg_to_rad(-90))\
				.translate(Vector3.FORWARD)
	)


func _generate_right_quads(visible_pixels: BitMap) -> Array:
	var width := visible_pixels.get_size().x

	return _generate_vertical_quads(
		visible_pixels,
		func (x: int, y: int) -> bool:
			return x == width - 1 or not visible_pixels.get_bit(x + 1, y),
		func (rect: Rect2i) -> Quad:
			return _generate_front_quad(rect)\
				.rotate_along_side(SIDE_RIGHT, deg_to_rad(90))\
				.translate(Vector3.FORWARD)
	)


func _generate_top_quads(visible_pixels: BitMap) -> Array:
	return _generate_horizontal_quads(
		visible_pixels,
		func (x: int, y: int) -> bool:
			return y == 0 or not visible_pixels.get_bit(x, y - 1),
		func (rect: Rect2i) -> Quad:
			return _generate_front_quad(rect)\
				.rotate_along_side(SIDE_TOP, deg_to_rad(-90))\
				.translate(Vector3.FORWARD)
	)


func _generate_bottom_quads(visible_pixels: BitMap) -> Array:
	var height := visible_pixels.get_size().y

	return _generate_horizontal_quads(
		visible_pixels,
		func (x: int, y: int) -> bool:
			return y == height - 1 or not visible_pixels.get_bit(x, y + 1),
		func (rect: Rect2i) -> Quad:
			return _generate_front_quad(rect)\
				.rotate_along_side(SIDE_BOTTOM, deg_to_rad(90))\
				.translate(Vector3.FORWARD)
	)


func _generate_vertical_quads(
	visible_pixels: BitMap,
	side_visible: Callable,
	create_quad: Callable
) -> Array:

	var quads = []

	var rendering_quad := false
	var y0: float

	for x in range(visible_pixels.get_size().x):
		for y in range(visible_pixels.get_size().y):
			if visible_pixels.get_bit(x, y) and side_visible.call(x, y):
				if not rendering_quad:
					y0 = y
					rendering_quad = true
			elif rendering_quad:
				quads.append(create_quad.call(Rect2i(x, y0, 1, y - y0)))
				rendering_quad = false

		if rendering_quad:
			quads.append(create_quad.call(Rect2i(x, y0, 1, visible_pixels.get_size().y - y0)))
			rendering_quad = false

	return quads


func _generate_horizontal_quads(
	visible_pixels: BitMap,
	side_visible: Callable,
	create_quad: Callable
) -> Array:

	var quads = []

	var rendering_quad := false
	var x0: float

	for y in range(visible_pixels.get_size().y):
		for x in range(visible_pixels.get_size().x):
			if visible_pixels.get_bit(x, y) and side_visible.call(x, y):
				if not rendering_quad:
					x0 = x
					rendering_quad = true
			elif rendering_quad:
				quads.append(create_quad.call(Rect2i(x0, y, x - x0, 1)))
				rendering_quad = false

		if rendering_quad:
			quads.append(create_quad.call(Rect2i(x0, y, visible_pixels.get_size().x - x0, 1)))
			rendering_quad = false

	return quads


func _generate_front_quad(rect: Rect2i):
	assert(_is_inside_image(rect))

	return Quad.new([
		Vector3(rect.position.x, image.get_height() - rect.position.y, 0),
		Vector3(rect.end.x, image.get_height() - rect.position.y, 0),
		Vector3(rect.end.x, image.get_height() - rect.end.y, 0),
		Vector3(rect.position.x, image.get_height() - rect.end.y, 0),
	], _generate_quad_uvs(rect))


func _generate_quad_uvs(rect: Rect2i) -> Array[Vector2]:
	var corr := _get_uv_correction(rect)
	var uv_rect := Rect2(rect).grow_individual(-corr.x, -corr.y, -corr.x, -corr.y)

	var u0 := float(uv_rect.position.x) / image.get_width()
	var v0 := float(uv_rect.position.y) / image.get_height()
	var u1 := float(uv_rect.end.x) / image.get_width()
	var v1 := float(uv_rect.end.y) / image.get_height()

	return [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]


func _get_uv_correction(rect: Rect2i) -> Vector2:
	return Vector2(
		0.5 * (1.0 if absf(rect.position.x - rect.end.x) <= 1 else uv_correction),
		0.5 * (1.0 if absf(rect.position.y - rect.end.y) <= 1 else uv_correction),
	)


func _is_inside_image(rect: Rect2i) -> bool:
	return rect.position >= Vector2i.ZERO and rect.end <= image.get_size()


func _get_visible_pixels() -> BitMap:
	var visible_pixels = BitMap.new()
	visible_pixels.create_from_image_alpha(image, alpha_threshold)
	return visible_pixels
