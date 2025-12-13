extends RefCounted


const Quad = preload("./quad.gd")

var vertices: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]:
	set = set_vertices
var uvs: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]:
	set = set_uvs


func _init(vertices: Array[Vector3], uvs: Array[Vector2]) -> void:
	set_vertices(vertices)
	set_uvs(uvs)


func render(st: SurfaceTool) -> void:
	st.set_smooth_group(-1)
	st.set_uv(uvs[0])
	st.add_vertex(vertices[0])
	st.set_uv(uvs[1])
	st.add_vertex(vertices[1])
	st.set_uv(uvs[2])
	st.add_vertex(vertices[2])

	st.set_smooth_group(-1)
	st.set_uv(uvs[0])
	st.add_vertex(vertices[0])
	st.set_uv(uvs[2])
	st.add_vertex(vertices[2])
	st.set_uv(uvs[3])
	st.add_vertex(vertices[3])


func set_vertices(new_vertices: Array[Vector3]) -> Quad:
	assert(vertices.size() == 4)

	vertices = new_vertices

	return self


func set_uvs(new_uvs: Array[Vector2]) -> Quad:
	assert(new_uvs.size() == 4)
	assert(new_uvs.all(func(uv: Vector2) -> bool:
		return uv >= Vector2.ZERO and uv <= Vector2.ONE
	))

	uvs = new_uvs

	return self


func get_center() -> Vector3:
	return (
		Vector3(
			max(vertices[0].x, vertices[1].x, vertices[2].x, vertices[3].x),
			max(vertices[0].y, vertices[1].y, vertices[2].y, vertices[3].y),
			max(vertices[0].z, vertices[1].z, vertices[2].z, vertices[3].z),
		) +
		Vector3(
			min(vertices[0].x, vertices[1].x, vertices[2].x, vertices[3].x),
			min(vertices[0].y, vertices[1].y, vertices[2].y, vertices[3].y),
			min(vertices[0].z, vertices[1].z, vertices[2].z, vertices[3].z),
		)) / 2


func get_uvs_center() -> Vector2:
	return (
		Vector2(
			max(uvs[0].x, uvs[1].x, uvs[2].x, uvs[3].x),
			max(uvs[0].y, uvs[1].y, uvs[2].y, uvs[3].y),
		) +
		Vector2(
			min(uvs[0].x, uvs[1].x, uvs[2].x, uvs[3].x),
			min(uvs[0].y, uvs[1].y, uvs[2].y, uvs[3].y),
		)) / 2


func duplicate() -> Quad:
	return Quad.new(vertices.duplicate(), uvs.duplicate())


func translate(translation: Vector3) -> Quad:
	for i in range(4):
		vertices[i] += translation

	return self


func rotate(axis: Vector3, angle: float) -> Quad:
	for i in range(4):
		vertices[i] = vertices[i].rotated(axis.normalized(), angle)

	return self


func scale(factor: Vector3) -> Quad:
	for i in range(4):
		vertices[i] *= factor

	return self


func rotate_along_side(side: int, angle: float) -> Quad:
	var h_translation := vertices[2] - vertices[3]
	var v_translation := vertices[0] - vertices[3]
	var h_axis := h_translation.normalized()
	var v_axis := v_translation.normalized()

	match(side):
		SIDE_LEFT:
			var translation := (h_translation).rotated(v_axis, angle)
			vertices[1] = vertices[0] + translation
			vertices[2] = vertices[3] + translation
		SIDE_TOP:
			var translation := (-v_translation).rotated(h_axis, angle)
			vertices[2] = vertices[1] + translation
			vertices[3] = vertices[0] + translation
		SIDE_RIGHT:
			var translation := (-h_translation).rotated(v_axis, angle)
			vertices[0] = vertices[1] + translation
			vertices[3] = vertices[2] + translation
		SIDE_BOTTOM:
			var translation := (v_translation).rotated(h_axis, angle)
			vertices[0] = vertices[3] + translation
			vertices[1] = vertices[2] + translation
		_:
			assert(false)

	return self


func translate_uvs(translation: Vector2) -> Quad:
	for i in range(4):
		uvs[i] += translation

	return self


func scale_uvs(factor: Vector2) -> Quad:
	for i in range(4):
		uvs[i] *= factor

	return self


func get_back_face() -> Quad:
	return duplicate().flip_vertices_h().flip_uvs_h()

	return self


func flip_vertices_h() -> Quad:
	vertices = [vertices[1], vertices[0], vertices[3], vertices[2]]

	return self


func flip_vertices_v() -> Quad:
	vertices = [vertices[3], vertices[2], vertices[1], vertices[0]]

	return self


func flip_uvs_h() -> Quad:
	uvs = [uvs[1], uvs[0], uvs[3], uvs[2]]

	return self


func flip_uvs_v() -> Quad:
	uvs = [uvs[3], uvs[2], uvs[1], uvs[0]]

	return self
