class_name TileMeshGenerator
extends RefCounted


static func create_box_mesh(grid_size: float = 1.0, depth_scale: float = 1.0) -> ArrayMesh:
	var thickness: float = grid_size * GlobalConstants.MESH_THICKNESS_RATIO * depth_scale
	var stripe: float = GlobalConstants.MESH_SIDE_UV_STRIPE_RATIO

	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(grid_size, thickness, grid_size)

	var st: SurfaceTool = SurfaceTool.new()
	st.create_from(box, 0)
	var array_mesh: ArrayMesh = st.commit()

	var arrays: Array = array_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = PackedColorArray()

	colors.resize(vertices.size())
	arrays[Mesh.ARRAY_COLOR] = colors

	var half_size: float = grid_size / 2.0
	var half_thickness: float = thickness / 2.0

	# Offset so mesh rests on the grid plane (Y=0) instead of centered.
	for i in range(vertices.size()):
		vertices[i].y += half_thickness
	arrays[Mesh.ARRAY_VERTEX] = vertices

	for i in range(vertices.size()):
		var v: Vector3 = vertices[i]

		var base_u: float = (v.x + half_size) / grid_size
		var base_v: float = 1.0 - ((v.z + half_size) / grid_size)

		if is_equal_approx(v.y, thickness):
			uvs[i] = Vector2(base_u, base_v)

		elif is_equal_approx(v.y, 0.0):
			uvs[i] = Vector2(base_u, base_v)

		elif is_equal_approx(v.z, half_size):
			uvs[i] = Vector2(base_u, base_v)

		elif is_equal_approx(v.x, half_size):
			var y_normalized: float = v.y / thickness
			uvs[i] = Vector2(lerpf(1.0 - stripe, 1.0, y_normalized), base_v)

		elif is_equal_approx(v.x, -half_size):
			var y_normalized: float = v.y / thickness
			uvs[i] = Vector2(lerpf(0.0, stripe, y_normalized), base_v)

		elif is_equal_approx(v.z, -half_size):
			var y_normalized: float = v.y / thickness
			uvs[i] = Vector2(base_u, lerpf(1.0 - stripe, 1.0, y_normalized))

	arrays[Mesh.ARRAY_TEX_UV] = uvs

	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return result


static func create_prism_mesh(grid_size: float = 1.0, depth_scale: float = 1.0) -> ArrayMesh:
	var thickness: float = grid_size * GlobalConstants.MESH_THICKNESS_RATIO * depth_scale
	var stripe: float = GlobalConstants.MESH_SIDE_UV_STRIPE_RATIO
	var half_size: float = grid_size / 2.0

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Prism rests on the grid plane (Y=0): top at Y=thickness, bottom at Y=0.
	var top_bl := Vector3(-half_size, thickness, -half_size)
	var top_br := Vector3(half_size, thickness, -half_size)
	var top_tl := Vector3(-half_size, thickness, half_size)

	var bot_bl := Vector3(-half_size, 0.0, -half_size)
	var bot_br := Vector3(half_size, 0.0, -half_size)
	var bot_tl := Vector3(-half_size, 0.0, half_size)

	var uv_bl := Vector2(0, 1)
	var uv_br := Vector2(1, 1)
	var uv_tl := Vector2(0, 0)

	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(Vector3.UP)
	st.set_uv(uv_bl)
	st.add_vertex(top_bl)
	st.set_uv(uv_br)
	st.add_vertex(top_br)
	st.set_uv(uv_tl)
	st.add_vertex(top_tl)

	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(Vector3.DOWN)
	st.set_uv(uv_bl)
	st.add_vertex(bot_tl)
	st.set_uv(uv_br)
	st.add_vertex(bot_br)
	st.set_uv(uv_tl)
	st.add_vertex(bot_bl)

	# side_type: 0=FRONT (bottom row), 1=LEFT (left col), 2=DIAGONAL (right col)
	_add_prism_side_quad(st, bot_bl, bot_br, top_br, top_bl, stripe, 0)
	_add_prism_side_quad(st, bot_tl, bot_bl, top_bl, top_tl, stripe, 1)
	_add_prism_side_quad(st, bot_br, bot_tl, top_tl, top_br, stripe, 2)

	st.generate_tangents()
	return st.commit()


static func create_box_mesh_repeat(grid_size: float = 1.0, depth_scale: float = 1.0) -> ArrayMesh:
	var thickness: float = grid_size * GlobalConstants.MESH_THICKNESS_RATIO * depth_scale

	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(grid_size, thickness, grid_size)

	var st: SurfaceTool = SurfaceTool.new()
	st.create_from(box, 0)
	var array_mesh: ArrayMesh = st.commit()

	var arrays: Array = array_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = PackedColorArray()


	colors.resize(vertices.size())
	arrays[Mesh.ARRAY_COLOR] = colors

	var half_size: float = grid_size / 2.0
	var half_thickness: float = thickness / 2.0

	# Offset so mesh rests on the grid plane (Y=0) instead of centered.
	for i in range(vertices.size()):
		vertices[i].y += half_thickness
	arrays[Mesh.ARRAY_VERTEX] = vertices

	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	# Detect face by normal (not position) since repeat UVs vary per face.
	for i in range(vertices.size()):
		var v: Vector3 = vertices[i]
		var n: Vector3 = normals[i]

		var base_u: float = (v.x + half_size) / grid_size
		var base_v: float = 1.0 - ((v.z + half_size) / grid_size)

		if n.y > 0.5:
			uvs[i] = Vector2(base_u, base_v)

		elif n.y < -0.5:
			uvs[i] = Vector2(base_u, base_v)

		elif n.z > 0.5:
			var y_normalized: float = 1.0 - (v.y / thickness)
			uvs[i] = Vector2(base_u, y_normalized)

		elif n.z < -0.5:
			var y_normalized: float = 1.0 - (v.y / thickness)
			uvs[i] = Vector2(1.0 - base_u, y_normalized)

		elif n.x > 0.5:
			var z_normalized: float = (v.z + half_size) / grid_size
			var y_normalized: float = 1.0 - (v.y / thickness)
			uvs[i] = Vector2(z_normalized, y_normalized)

		elif n.x < -0.5:
			var z_normalized: float = 1.0 - ((v.z + half_size) / grid_size)
			var y_normalized: float = 1.0 - (v.y / thickness)
			uvs[i] = Vector2(z_normalized, y_normalized)

	arrays[Mesh.ARRAY_TEX_UV] = uvs

	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return result


static func create_prism_mesh_repeat(grid_size: float = 1.0, depth_scale: float = 1.0) -> ArrayMesh:
	var thickness: float = grid_size * GlobalConstants.MESH_THICKNESS_RATIO * depth_scale
	var half_size: float = grid_size / 2.0

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Prism rests on the grid plane (Y=0): top at Y=thickness, bottom at Y=0.
	var top_bl := Vector3(-half_size, thickness, -half_size)
	var top_br := Vector3(half_size, thickness, -half_size)
	var top_tl := Vector3(-half_size, thickness, half_size)

	var bot_bl := Vector3(-half_size, 0.0, -half_size)
	var bot_br := Vector3(half_size, 0.0, -half_size)
	var bot_tl := Vector3(-half_size, 0.0, half_size)

	var uv_bl := Vector2(0, 1)
	var uv_br := Vector2(1, 1)
	var uv_tl := Vector2(0, 0)

	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(Vector3.UP)
	st.set_uv(uv_bl)
	st.add_vertex(top_bl)
	st.set_uv(uv_br)
	st.add_vertex(top_br)
	st.set_uv(uv_tl)
	st.add_vertex(top_tl)

	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(Vector3.DOWN)
	st.set_uv(uv_bl)
	st.add_vertex(bot_tl)
	st.set_uv(uv_br)
	st.add_vertex(bot_br)
	st.set_uv(uv_tl)
	st.add_vertex(bot_bl)

	_add_prism_side_quad_repeat(st, bot_bl, bot_br, top_br, top_bl)
	_add_prism_side_quad_repeat(st, bot_tl, bot_bl, top_bl, top_tl)
	_add_prism_side_quad_repeat(st, bot_br, bot_tl, top_tl, top_br)

	st.generate_tangents()
	return st.commit()


static func _add_prism_side_quad_repeat(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	var normal: Vector3 = (v1 - v0).cross(v3 - v0).normalized()
	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(normal)

	# v0, v1 are bottom edge (Y-), v2, v3 are top edge (Y+).
	var uv0 := Vector2(0.0, 1.0)
	var uv1 := Vector2(1.0, 1.0)
	var uv2 := Vector2(1.0, 0.0)
	var uv3 := Vector2(0.0, 0.0)

	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_uv(uv1)
	st.add_vertex(v1)
	st.set_uv(uv2)
	st.add_vertex(v2)
	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_uv(uv2)
	st.add_vertex(v2)
	st.set_uv(uv3)
	st.add_vertex(v3)


## side_type: 0=FRONT (bottom row), 1=LEFT (left col), 2=DIAGONAL (right col).
## v0, v1 are bottom edge (Y-), v2, v3 top edge (Y+); thickness maps to stripe width.
static func _add_prism_side_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, stripe: float, side_type: int) -> void:
	var normal: Vector3 = (v1 - v0).cross(v3 - v0).normalized()
	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(normal)

	var uv0: Vector2
	var uv1: Vector2
	var uv2: Vector2
	var uv3: Vector2

	match side_type:
		0:
			uv0 = Vector2(0.0, 1.0)
			uv1 = Vector2(1.0, 1.0)
			uv2 = Vector2(1.0, 1.0 - stripe)
			uv3 = Vector2(0.0, 1.0 - stripe)
		1:
			uv0 = Vector2(0.0, 1.0)
			uv1 = Vector2(0.0, 0.0)
			uv2 = Vector2(stripe, 0.0)
			uv3 = Vector2(stripe, 1.0)
		2:
			uv0 = Vector2(1.0, 1.0)
			uv1 = Vector2(1.0, 0.0)
			uv2 = Vector2(1.0 - stripe, 0.0)
			uv3 = Vector2(1.0 - stripe, 1.0)

	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_uv(uv1)
	st.add_vertex(v1)
	st.set_uv(uv2)
	st.add_vertex(v2)
	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_uv(uv2)
	st.add_vertex(v2)
	st.set_uv(uv3)
	st.add_vertex(v3)


static func create_tile_quad(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0)) -> ArrayMesh:

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0

	st.set_uv(Vector2(uv_min.x, uv_max.y))
	st.add_vertex(Vector3(-half_width, 0.0, -half_height))

	st.set_uv(Vector2(uv_max.x, uv_max.y))
	st.add_vertex(Vector3(half_width, 0.0, -half_height))

	st.set_uv(Vector2(uv_max.x, uv_min.y))
	st.add_vertex(Vector3(half_width, 0.0, half_height))

	st.set_uv(Vector2(uv_min.x, uv_min.y))
	st.add_vertex(Vector3(-half_width, 0.0, half_height))

	st.add_index(0)
	st.add_index(1)
	st.add_index(2)
	st.add_index(0)
	st.add_index(2)
	st.add_index(3)

	st.generate_normals()
	st.generate_tangents()

	return st.commit()

static func create_tile_triangle(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0)) -> ArrayMesh:

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0

	st.set_uv(Vector2(uv_min.x, uv_max.y))
	st.add_vertex(Vector3(-half_width, 0.0, -half_height))

	st.set_uv(Vector2(uv_max.x, uv_max.y))
	st.add_vertex(Vector3(half_width, 0.0, -half_height))

	st.set_uv(Vector2(uv_min.x, uv_min.y))
	st.add_vertex(Vector3(-half_width, 0.0, half_height))

	st.add_index(0)
	st.add_index(1)
	st.add_index(2)

	st.generate_normals()
	st.generate_tangents()

	return st.commit()


## Flat quad with a 45° arc lifting off Y=0 at one end; two at 90° form a rounded corner.
## Arc: x = flat_end + R*sin(angle), y = R*(1-cos(angle)), angle 0..PI/4.
static func create_arch_corner_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0),
	arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0
	var grid_size: float = tile_world_size.x
	var arc_radius: float = arc_radius_ratio * grid_size
	var flat_end_x: float = half_width - arc_radius
	var segments: int = GlobalConstants.ARCH_ARC_SEGMENTS

	var flat_length: float = grid_size - arc_radius
	var arc_length: float = arc_radius * PI / 4.0
	var total_length: float = flat_length + arc_length

	var uv_width: float = uv_max.x - uv_min.x
	var uv_height: float = uv_max.y - uv_min.y

	# Each column along the path holds bottom (z=-hh) and top (z=+hh); total = 2 + SEGMENTS.
	var positions: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()

	positions.append(Vector3(-half_width, 0.0, -half_height))
	positions.append(Vector3(-half_width, 0.0, half_height))
	uvs.append(Vector2(uv_min.x, uv_max.y))
	uvs.append(Vector2(uv_min.x, uv_min.y))

	var flat_u: float = uv_min.x + uv_width * (flat_length / total_length)
	positions.append(Vector3(flat_end_x, 0.0, -half_height))
	positions.append(Vector3(flat_end_x, 0.0, half_height))
	uvs.append(Vector2(flat_u, uv_max.y))
	uvs.append(Vector2(flat_u, uv_min.y))

	for i in range(1, segments + 1):
		var angle: float = (PI / 4.0) * float(i) / float(segments)
		var arc_x: float = flat_end_x + arc_radius * sin(angle)
		var arc_y: float = -arc_radius * (1.0 - cos(angle))

		var arc_dist: float = arc_radius * angle
		var u: float = uv_min.x + uv_width * ((flat_length + arc_dist) / total_length)

		positions.append(Vector3(arc_x, arc_y, -half_height))
		positions.append(Vector3(arc_x, arc_y, half_height))
		uvs.append(Vector2(u, uv_max.y))
		uvs.append(Vector2(u, uv_min.y))

	var total_columns: int = 2 + segments
	for col in range(total_columns - 1):
		var bl: int = col * 2
		var tl: int = col * 2 + 1
		var br: int = (col + 1) * 2
		var tr: int = (col + 1) * 2 + 1

		st.set_uv(uvs[bl])
		st.add_vertex(positions[bl])
		st.set_uv(uvs[br])
		st.add_vertex(positions[br])
		st.set_uv(uvs[tr])
		st.add_vertex(positions[tr])

		st.set_uv(uvs[bl])
		st.add_vertex(positions[bl])
		st.set_uv(uvs[tr])
		st.add_vertex(positions[tr])
		st.set_uv(uvs[tl])
		st.add_vertex(positions[tl])

	st.generate_normals()
	st.generate_tangents()

	return st.commit()


## Inverted create_arch_corner_mesh: arc_y positive (curves +Y).
static func create_arch_corner_i_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0),
	arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0
	var grid_size: float = tile_world_size.x
	var arc_radius: float = arc_radius_ratio * grid_size
	var flat_end_x: float = half_width - arc_radius
	var segments: int = GlobalConstants.ARCH_ARC_SEGMENTS

	var flat_length: float = grid_size - arc_radius
	var arc_length: float = arc_radius * PI / 4.0
	var total_length: float = flat_length + arc_length

	var uv_width: float = uv_max.x - uv_min.x

	var positions: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()

	positions.append(Vector3(-half_width, 0.0, -half_height))
	positions.append(Vector3(-half_width, 0.0, half_height))
	uvs.append(Vector2(uv_min.x, uv_max.y))
	uvs.append(Vector2(uv_min.x, uv_min.y))

	var flat_u: float = uv_min.x + uv_width * (flat_length / total_length)
	positions.append(Vector3(flat_end_x, 0.0, -half_height))
	positions.append(Vector3(flat_end_x, 0.0, half_height))
	uvs.append(Vector2(flat_u, uv_max.y))
	uvs.append(Vector2(flat_u, uv_min.y))

	for i in range(1, segments + 1):
		var angle: float = (PI / 4.0) * float(i) / float(segments)
		var arc_x: float = flat_end_x + arc_radius * sin(angle)
		var arc_y: float = arc_radius * (1.0 - cos(angle))

		var arc_dist: float = arc_radius * angle
		var u: float = uv_min.x + uv_width * ((flat_length + arc_dist) / total_length)

		positions.append(Vector3(arc_x, arc_y, -half_height))
		positions.append(Vector3(arc_x, arc_y, half_height))
		uvs.append(Vector2(u, uv_max.y))
		uvs.append(Vector2(u, uv_min.y))

	var total_columns: int = 2 + segments
	for col in range(total_columns - 1):
		var bl: int = col * 2
		var tl: int = col * 2 + 1
		var br: int = (col + 1) * 2
		var tr: int = (col + 1) * 2 + 1

		st.set_uv(uvs[bl])
		st.add_vertex(positions[bl])
		st.set_uv(uvs[br])
		st.add_vertex(positions[br])
		st.set_uv(uvs[tr])
		st.add_vertex(positions[tr])

		st.set_uv(uvs[bl])
		st.add_vertex(positions[bl])
		st.set_uv(uvs[tr])
		st.add_vertex(positions[tr])
		st.set_uv(uvs[tl])
		st.add_vertex(positions[tl])

	st.generate_normals()
	st.generate_tangents()

	return st.commit()


static func create_arch_corner_cap_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0),
	arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0
	var grid_size: float = tile_world_size.x
	var arc_radius: float = arc_radius_ratio * grid_size
	var segments: int = GlobalConstants.ARCH_ARC_SEGMENTS

	var arc_center_x: float = half_width - arc_radius
	var arc_center_z: float = half_height - arc_radius


	var perimeter_pos: PackedVector3Array = PackedVector3Array()
	var perimeter_uv: PackedVector2Array = PackedVector2Array()

	var uv_width: float = uv_max.x - uv_min.x
	var uv_height: float = uv_max.y - uv_min.y


	perimeter_pos.append(Vector3(-half_width, 0.0, -half_height))
	perimeter_uv.append(Vector2(uv_min.x, uv_max.y))

	perimeter_pos.append(Vector3(half_width, 0.0, -half_height))
	perimeter_uv.append(Vector2(uv_max.x, uv_max.y))

	perimeter_pos.append(Vector3(half_width, 0.0, arc_center_z))
	var arc_start_v: float = uv_min.y + uv_height * (arc_radius / grid_size)
	perimeter_uv.append(Vector2(uv_max.x, arc_start_v))

	for i in range(1, segments):
		var angle: float = (PI / 2.0) * float(i) / float(segments)
		var arc_x: float = arc_center_x + arc_radius * cos(angle)
		var arc_z: float = arc_center_z + arc_radius * sin(angle)

		var u: float = uv_min.x + uv_width * ((arc_x + half_width) / grid_size)
		var v: float = uv_max.y - uv_height * ((arc_z + half_height) / grid_size)

		perimeter_pos.append(Vector3(arc_x, 0.0, arc_z))
		perimeter_uv.append(Vector2(u, v))

	perimeter_pos.append(Vector3(arc_center_x, 0.0, half_height))
	var arc_end_u: float = uv_max.x - uv_width * (arc_radius / grid_size)
	perimeter_uv.append(Vector2(arc_end_u, uv_min.y))

	perimeter_pos.append(Vector3(-half_width, 0.0, half_height))
	perimeter_uv.append(Vector2(uv_min.x, uv_min.y))

	var num_perimeter: int = perimeter_pos.size()
	for i in range(1, num_perimeter - 1):
		st.set_uv(perimeter_uv[0])
		st.add_vertex(perimeter_pos[0])
		st.set_uv(perimeter_uv[i])
		st.add_vertex(perimeter_pos[i])
		st.set_uv(perimeter_uv[i + 1])
		st.add_vertex(perimeter_pos[i + 1])

	st.generate_normals()
	st.generate_tangents()

	return st.commit()


static func create_arch_corner_cap_duo_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0),
	arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0
	var grid_size: float = tile_world_size.x
	var arc_radius: float = arc_radius_ratio * grid_size
	var segments: int = GlobalConstants.ARCH_ARC_SEGMENTS

	var arc1_center_x: float = half_width - arc_radius
	var arc1_center_z: float = half_height - arc_radius

	var arc2_center_x: float = -half_width + arc_radius
	var arc2_center_z: float = half_height - arc_radius

	var perimeter_pos: PackedVector3Array = PackedVector3Array()
	var perimeter_uv: PackedVector2Array = PackedVector2Array()

	var uv_width: float = uv_max.x - uv_min.x
	var uv_height: float = uv_max.y - uv_min.y

	perimeter_pos.append(Vector3(-half_width, 0.0, -half_height))
	perimeter_uv.append(Vector2(uv_min.x, uv_max.y))

	perimeter_pos.append(Vector3(half_width, 0.0, -half_height))
	perimeter_uv.append(Vector2(uv_max.x, uv_max.y))

	perimeter_pos.append(Vector3(half_width, 0.0, arc1_center_z))
	var arc1_start_v: float = uv_min.y + uv_height * (arc_radius / grid_size)
	perimeter_uv.append(Vector2(uv_max.x, arc1_start_v))

	for i: int in range(1, segments):
		var angle: float = (PI / 2.0) * float(i) / float(segments)
		var arc_x: float = arc1_center_x + arc_radius * cos(angle)
		var arc_z: float = arc1_center_z + arc_radius * sin(angle)
		var u: float = uv_min.x + uv_width * ((arc_x + half_width) / grid_size)
		var v: float = uv_max.y - uv_height * ((arc_z + half_height) / grid_size)
		perimeter_pos.append(Vector3(arc_x, 0.0, arc_z))
		perimeter_uv.append(Vector2(u, v))

	perimeter_pos.append(Vector3(arc1_center_x, 0.0, half_height))
	var arc1_end_u: float = uv_max.x - uv_width * (arc_radius / grid_size)
	perimeter_uv.append(Vector2(arc1_end_u, uv_min.y))

	perimeter_pos.append(Vector3(arc2_center_x, 0.0, half_height))
	var arc2_start_u: float = uv_min.x + uv_width * (arc_radius / grid_size)
	perimeter_uv.append(Vector2(arc2_start_u, uv_min.y))

	for i: int in range(1, segments):
		var angle: float = (PI / 2.0) + (PI / 2.0) * float(i) / float(segments)
		var arc_x: float = arc2_center_x + arc_radius * cos(angle)
		var arc_z: float = arc2_center_z + arc_radius * sin(angle)
		var u: float = uv_min.x + uv_width * ((arc_x + half_width) / grid_size)
		var v: float = uv_max.y - uv_height * ((arc_z + half_height) / grid_size)
		perimeter_pos.append(Vector3(arc_x, 0.0, arc_z))
		perimeter_uv.append(Vector2(u, v))

	perimeter_pos.append(Vector3(-half_width, 0.0, arc2_center_z))
	var arc2_end_v: float = uv_min.y + uv_height * (arc_radius / grid_size)
	perimeter_uv.append(Vector2(uv_min.x, arc2_end_v))

	var num_perimeter: int = perimeter_pos.size()
	for i: int in range(1, num_perimeter - 1):
		st.set_uv(perimeter_uv[0])
		st.add_vertex(perimeter_pos[0])
		st.set_uv(perimeter_uv[i])
		st.add_vertex(perimeter_pos[i])
		st.set_uv(perimeter_uv[i + 1])
		st.add_vertex(perimeter_pos[i + 1])

	st.generate_normals()
	st.generate_tangents()

	return st.commit()


static func create_arch_corner_cap_i_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0),
	arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0
	var grid_size: float = tile_world_size.x
	var arc_radius: float = arc_radius_ratio * grid_size
	var segments: int = GlobalConstants.ARCH_ARC_SEGMENTS

	var arc_center_x: float = half_width - arc_radius
	var arc_center_z: float = half_height - arc_radius

	var uv_width: float = uv_max.x - uv_min.x
	var uv_height: float = uv_max.y - uv_min.y


	var apex_pos: Vector3 = Vector3(half_width, 0.0, half_height)
	var apex_uv: Vector2 = Vector2(uv_max.x, uv_min.y)

	var arc_positions: PackedVector3Array = PackedVector3Array()
	var arc_uvs: PackedVector2Array = PackedVector2Array()

	for i in range(segments + 1):
		var angle: float = (PI / 2.0) * float(i) / float(segments)
		var arc_x: float = arc_center_x + arc_radius * cos(angle)
		var arc_z: float = arc_center_z + arc_radius * sin(angle)

		var u: float = uv_min.x + uv_width * ((arc_x + half_width) / grid_size)
		var v: float = uv_max.y - uv_height * ((arc_z + half_height) / grid_size)

		arc_positions.append(Vector3(arc_x, 0.0, arc_z))
		arc_uvs.append(Vector2(u, v))

	for i in range(segments):
		st.set_uv(apex_uv)
		st.add_vertex(apex_pos)
		st.set_uv(arc_uvs[i + 1])
		st.add_vertex(arc_positions[i + 1])
		st.set_uv(arc_uvs[i])
		st.add_vertex(arc_positions[i])

	st.generate_normals()
	st.generate_tangents()

	return st.commit()


static func create_arch_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0),
	arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0
	var grid_size: float = tile_world_size.x
	var arc_radius: float = arc_radius_ratio * grid_size
	var sweep_angle: float = PI / 4.0
	var flat_end_x: float = half_width - arc_radius * sin(sweep_angle)
	var segments: int = GlobalConstants.ARCH_ARC_SEGMENTS

	var flat_length: float = grid_size - arc_radius * sin(sweep_angle)
	var arc_length: float = arc_radius * sweep_angle
	var total_length: float = flat_length + arc_length

	var uv_width: float = uv_max.x - uv_min.x
	var uv_height: float = uv_max.y - uv_min.y


	var positions: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()

	positions.append(Vector3(-half_width, 0.0, -half_height))
	positions.append(Vector3(-half_width, 0.0, half_height))
	uvs.append(Vector2(uv_min.x, uv_max.y))
	uvs.append(Vector2(uv_min.x, uv_min.y))

	var flat_u: float = uv_min.x + uv_width * (flat_length / total_length)
	positions.append(Vector3(flat_end_x, 0.0, -half_height))
	positions.append(Vector3(flat_end_x, 0.0, half_height))
	uvs.append(Vector2(flat_u, uv_max.y))
	uvs.append(Vector2(flat_u, uv_min.y))

	for i in range(1, segments + 1):
		var angle: float = sweep_angle * float(i) / float(segments)
		var arc_x: float = flat_end_x + arc_radius * sin(angle)
		var arc_y: float = arc_radius * (1.0 - cos(angle))

		var arc_dist: float = arc_radius * angle
		var u: float = uv_min.x + uv_width * ((flat_length + arc_dist) / total_length)

		positions.append(Vector3(arc_x, arc_y, -half_height))
		positions.append(Vector3(arc_x, arc_y, half_height))
		uvs.append(Vector2(u, uv_max.y))
		uvs.append(Vector2(u, uv_min.y))

	var total_columns: int = 2 + segments
	for col in range(total_columns - 1):
		var bl: int = col * 2
		var tl: int = col * 2 + 1
		var br: int = (col + 1) * 2
		var tr: int = (col + 1) * 2 + 1

		st.set_uv(uvs[bl])
		st.add_vertex(positions[bl])
		st.set_uv(uvs[br])
		st.add_vertex(positions[br])
		st.set_uv(uvs[tr])
		st.add_vertex(positions[tr])

		st.set_uv(uvs[bl])
		st.add_vertex(positions[bl])
		st.set_uv(uvs[tr])
		st.add_vertex(positions[tr])
		st.set_uv(uvs[tl])
		st.add_vertex(positions[tl])

	st.generate_normals()
	st.generate_tangents()

	return st.commit()


static func create_arch_i_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0),
	arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0
	var grid_size: float = tile_world_size.x
	var arc_radius: float = arc_radius_ratio * grid_size
	var sweep_angle: float = PI / 4.0
	var flat_end_x: float = half_width - arc_radius * sin(sweep_angle)
	var segments: int = GlobalConstants.ARCH_ARC_SEGMENTS

	var flat_length: float = grid_size - arc_radius * sin(sweep_angle)
	var arc_length: float = arc_radius * sweep_angle
	var total_length: float = flat_length + arc_length

	var uv_width: float = uv_max.x - uv_min.x

	var positions: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()

	positions.append(Vector3(-half_width, 0.0, -half_height))
	positions.append(Vector3(-half_width, 0.0, half_height))
	uvs.append(Vector2(uv_min.x, uv_max.y))
	uvs.append(Vector2(uv_min.x, uv_min.y))

	var flat_u: float = uv_min.x + uv_width * (flat_length / total_length)
	positions.append(Vector3(flat_end_x, 0.0, -half_height))
	positions.append(Vector3(flat_end_x, 0.0, half_height))
	uvs.append(Vector2(flat_u, uv_max.y))
	uvs.append(Vector2(flat_u, uv_min.y))

	for i in range(1, segments + 1):
		var angle: float = sweep_angle * float(i) / float(segments)
		var arc_x: float = flat_end_x + arc_radius * sin(angle)
		var arc_y: float = -arc_radius * (1.0 - cos(angle))

		var arc_dist: float = arc_radius * angle
		var u: float = uv_min.x + uv_width * ((flat_length + arc_dist) / total_length)

		positions.append(Vector3(arc_x, arc_y, -half_height))
		positions.append(Vector3(arc_x, arc_y, half_height))
		uvs.append(Vector2(u, uv_max.y))
		uvs.append(Vector2(u, uv_min.y))

	var total_columns: int = 2 + segments
	for col in range(total_columns - 1):
		var bl: int = col * 2
		var tl: int = col * 2 + 1
		var br: int = (col + 1) * 2
		var tr: int = (col + 1) * 2 + 1

		st.set_uv(uvs[bl])
		st.add_vertex(positions[bl])
		st.set_uv(uvs[br])
		st.add_vertex(positions[br])
		st.set_uv(uvs[tr])
		st.add_vertex(positions[tr])

		st.set_uv(uvs[bl])
		st.add_vertex(positions[bl])
		st.set_uv(uvs[tr])
		st.add_vertex(positions[tr])
		st.set_uv(uvs[tl])
		st.add_vertex(positions[tl])

	st.generate_normals()
	st.generate_tangents()

	return st.commit()



static func create_arch_corner_c_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0),
	arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	return _build_double_arc_mesh(uv_rect, atlas_size, tile_world_size, arc_radius_ratio, -1.0, -1.0)


static func create_arch_corner_c_i_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0),
	arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	return _build_double_arc_mesh(uv_rect, atlas_size, tile_world_size, arc_radius_ratio, 1.0, 1.0)


static func create_arch_corner_s_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0),
	arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	return _build_double_arc_mesh(uv_rect, atlas_size, tile_world_size, arc_radius_ratio, 1.0, -1.0)


static func create_arch_corner_s_i_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0),
	arc_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
) -> ArrayMesh:
	return _build_double_arc_mesh(uv_rect, atlas_size, tile_world_size, arc_radius_ratio, -1.0, 1.0)


static func _build_double_arc_mesh(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2,
	arc_radius_ratio: float,
	left_y_sign: float,
	right_y_sign: float
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0
	var grid_size: float = tile_world_size.x
	var arc_radius: float = arc_radius_ratio * grid_size
	var flat_end_x: float = half_width - arc_radius
	var segments: int = GlobalConstants.ARCH_ARC_SEGMENTS

	var arc_length: float = arc_radius * PI / 4.0
	var flat_length: float = maxf(0.0, grid_size - 2.0 * arc_radius)
	var total_length: float = arc_length + flat_length + arc_length

	var uv_width: float = uv_max.x - uv_min.x

	var positions: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()

	for i in range(segments + 1):
		var angle: float = (PI / 4.0) * float(segments - i) / float(segments)
		var arc_x: float = -flat_end_x - arc_radius * sin(angle)
		var arc_y: float = left_y_sign * arc_radius * (1.0 - cos(angle))

		var path_dist: float = arc_length * (float(i) / float(segments))
		var u: float = uv_min.x + uv_width * (path_dist / total_length)

		positions.append(Vector3(arc_x, arc_y, -half_height))
		positions.append(Vector3(arc_x, arc_y, half_height))
		uvs.append(Vector2(u, uv_max.y))
		uvs.append(Vector2(u, uv_min.y))

	var flat_end_u: float = uv_min.x + uv_width * ((arc_length + flat_length) / total_length)
	positions.append(Vector3(flat_end_x, 0.0, -half_height))
	positions.append(Vector3(flat_end_x, 0.0, half_height))
	uvs.append(Vector2(flat_end_u, uv_max.y))
	uvs.append(Vector2(flat_end_u, uv_min.y))

	for i in range(1, segments + 1):
		var angle: float = (PI / 4.0) * float(i) / float(segments)
		var arc_x: float = flat_end_x + arc_radius * sin(angle)
		var arc_y: float = right_y_sign * arc_radius * (1.0 - cos(angle))

		var arc_dist: float = arc_radius * angle
		var u: float = uv_min.x + uv_width * ((arc_length + flat_length + arc_dist) / total_length)

		positions.append(Vector3(arc_x, arc_y, -half_height))
		positions.append(Vector3(arc_x, arc_y, half_height))
		uvs.append(Vector2(u, uv_max.y))
		uvs.append(Vector2(u, uv_min.y))

	var total_columns: int = 2 * segments + 2
	for col in range(total_columns - 1):
		var bl: int = col * 2
		var tl: int = col * 2 + 1
		var br: int = (col + 1) * 2
		var tr: int = (col + 1) * 2 + 1

		st.set_uv(uvs[bl])
		st.add_vertex(positions[bl])
		st.set_uv(uvs[br])
		st.add_vertex(positions[br])
		st.set_uv(uvs[tr])
		st.add_vertex(positions[tr])

		st.set_uv(uvs[bl])
		st.add_vertex(positions[bl])
		st.set_uv(uvs[tr])
		st.add_vertex(positions[tr])
		st.set_uv(uvs[tl])
		st.add_vertex(positions[tl])

	st.generate_normals()
	st.generate_tangents()

	return st.commit()

