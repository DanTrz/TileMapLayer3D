extends RefCounted


const Frame := preload("./frame.gd")

var image: Image
var position: Vector2i


func flip_h() -> Frame:
	image.flip_x()

	return self


func flip_v() -> Frame:
	image.flip_y()

	return self


func get_size() -> Vector2i:
	return image.get_size()


func get_position() -> Vector2i:
	return position


func get_width() -> int:
	return get_size().x


func get_height() -> int:
	return get_size().y
