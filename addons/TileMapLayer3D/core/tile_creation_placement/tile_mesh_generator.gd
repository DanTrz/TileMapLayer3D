class_name TileMeshGenerator
extends RefCounted

## Static utility class for generating 3D tile meshes from 2D tile UV data
## Supports: FLAT_SQUARE, FLAT_TRIANGULE, BOX_MESH, PRISM_MESH

## Creates a box mesh for BOX_MESH mode
## Thickness = grid_size * MESH_THICKNESS_RATIO * depth_scale
## UV Mapping:
##   - TOP/BOTTOM/BACK faces: Full tile texture (0-1 UV)
##   - LEFT/RIGHT/FRONT faces: Edge stripe from adjacent texture edge
static func create_box_mesh(grid_size: float = 1.0, depth_scale: float = 1.0) -> ArrayMesh:
	var thickness: float = grid_size * GlobalConstants.MESH_THICKNESS_RATIO * depth_scale
	var stripe: float = GlobalConstants.MESH_SIDE_UV_STRIPE_RATIO

	# Create BoxMesh with correct dimensions
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(grid_size, thickness, grid_size)

	# Convert to ArrayMesh to access vertex data
	var st: SurfaceTool = SurfaceTool.new()
	st.create_from(box, 0)
	var array_mesh: ArrayMesh = st.commit()

	# Get the arrays to modify
	var arrays: Array = array_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = PackedColorArray()

	colors.resize(vertices.size())
	# colors.fill(Color(0, 0, 0, 0))
	arrays[Mesh.ARRAY_COLOR] = colors

	# Face positions for identification
	var half_size: float = grid_size / 2.0
	var half_thickness: float = thickness / 2.0

	# Offset all vertices so mesh rests ON the grid plane (Y=0) instead of centered
	# Bottom face at Y=0, Top face at Y=thickness
	for i in range(vertices.size()):
		vertices[i].y += half_thickness
	arrays[Mesh.ARRAY_VERTEX] = vertices

	for i in range(vertices.size()):
		var v: Vector3 = vertices[i]

		# Calculate base U/V from X/Z position (used by most faces)
		var base_u: float = (v.x + half_size) / grid_size
		var base_v: float = 1.0 - ((v.z + half_size) / grid_size)

		if is_equal_approx(v.y, thickness):
			# TOP FACE (Y = thickness) - full texture
			uvs[i] = Vector2(base_u, base_v)

		elif is_equal_approx(v.y, 0.0):
			# BOTTOM FACE (Y = 0) - same as top (full texture)
			uvs[i] = Vector2(base_u, base_v)

		elif is_equal_approx(v.z, half_size):
			# BACK FACE (Z+) - same as top (full texture)
			uvs[i] = Vector2(base_u, base_v)

		elif is_equal_approx(v.x, half_size):
			# RIGHT SIDE (X+) - sample right column (U = 1-stripe to 1)
			var y_normalized: float = v.y / thickness
			uvs[i] = Vector2(lerpf(1.0 - stripe, 1.0, y_normalized), base_v)

		elif is_equal_approx(v.x, -half_size):
			# LEFT SIDE (X-) - sample left column (U = 0 to stripe)
			var y_normalized: float = v.y / thickness
			uvs[i] = Vector2(lerpf(0.0, stripe, y_normalized), base_v)

		elif is_equal_approx(v.z, -half_size):
			# FRONT FACE (Z-) - sample bottom row (V = 1-stripe to 1)
			var y_normalized: float = v.y / thickness
			uvs[i] = Vector2(base_u, lerpf(1.0 - stripe, 1.0, y_normalized))

	arrays[Mesh.ARRAY_TEX_UV] = uvs

	# Rebuild the mesh with modified data
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return result


## Creates a triangular prism mesh for PRISM_MESH mode
## Thickness = grid_size * MESH_THICKNESS_RATIO * depth_scale
## UV Mapping:
##   - TOP/BOTTOM faces: Full tile texture (0-1 UV)
##   - FRONT edge (Z-): Bottom row stripe from texture
##   - LEFT edge (X-): Left column stripe from texture
##   - DIAGONAL edge: Right column stripe from texture
static func create_prism_mesh(grid_size: float = 1.0, depth_scale: float = 1.0) -> ArrayMesh:
	var thickness: float = grid_size * GlobalConstants.MESH_THICKNESS_RATIO * depth_scale
	var stripe: float = GlobalConstants.MESH_SIDE_UV_STRIPE_RATIO
	var half_size: float = grid_size / 2.0

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Prism vertices (triangular cross-section extruded along Y)
	# Mesh rests ON the grid plane (Y=0) instead of centered
	# Top face (Y = thickness) - triangle
	var top_bl := Vector3(-half_size, thickness, -half_size)  # Bottom-left
	var top_br := Vector3(half_size, thickness, -half_size)   # Bottom-right
	var top_tl := Vector3(-half_size, thickness, half_size)   # Top-left

	# Bottom face (Y = 0) - triangle (sits on grid plane)
	var bot_bl := Vector3(-half_size, 0.0, -half_size)
	var bot_br := Vector3(half_size, 0.0, -half_size)
	var bot_tl := Vector3(-half_size, 0.0, half_size)

	# UVs for top face (matching flat triangle layout)
	var uv_bl := Vector2(0, 1)
	var uv_br := Vector2(1, 1)
	var uv_tl := Vector2(0, 0)

	# --- Top Face (textured) ---
	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(Vector3.UP)
	st.set_uv(uv_bl)
	st.add_vertex(top_bl)
	st.set_uv(uv_br)
	st.add_vertex(top_br)
	st.set_uv(uv_tl)
	st.add_vertex(top_tl)

	# --- Bottom Face ---
	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(Vector3.DOWN)
	st.set_uv(uv_bl)
	st.add_vertex(bot_tl)
	st.set_uv(uv_br)
	st.add_vertex(bot_br)
	st.set_uv(uv_tl)
	st.add_vertex(bot_bl)

	# --- Side Faces ---
	# Side types: 0=FRONT (bottom row), 1=LEFT (left col), 2=DIAGONAL (right col)
	# Side 1: Front edge (bl-br at Z-) - sample bottom row
	_add_prism_side_quad(st, bot_bl, bot_br, top_br, top_bl, stripe, 0)
	# Side 2: Left edge (tl-bl at X-) - sample left column
	_add_prism_side_quad(st, bot_tl, bot_bl, top_bl, top_tl, stripe, 1)
	# Side 3: Diagonal edge (br-tl) - sample right column
	_add_prism_side_quad(st, bot_br, bot_tl, top_tl, top_br, stripe, 2)

	st.generate_tangents()
	return st.commit()


## Creates a box mesh for BOX_MESH mode with REPEAT texture mode
## All 6 faces use full tile texture (uniform 0-1 UVs)
## Thickness = grid_size * MESH_THICKNESS_RATIO * depth_scale
static func create_box_mesh_repeat(grid_size: float = 1.0, depth_scale: float = 1.0) -> ArrayMesh:
	var thickness: float = grid_size * GlobalConstants.MESH_THICKNESS_RATIO * depth_scale

	# Create BoxMesh with correct dimensions
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(grid_size, thickness, grid_size)

	# Convert to ArrayMesh to access vertex data
	var st: SurfaceTool = SurfaceTool.new()
	st.create_from(box, 0)
	var array_mesh: ArrayMesh = st.commit()

	# Get the arrays to modify
	var arrays: Array = array_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = PackedColorArray()


	colors.resize(vertices.size())
	# colors.fill(Color(0, 0, 0, 0))
	arrays[Mesh.ARRAY_COLOR] = colors

	# Face positions for identification
	var half_size: float = grid_size / 2.0
	var half_thickness: float = thickness / 2.0

	# Offset all vertices so mesh rests ON the grid plane (Y=0) instead of centered
	# Bottom face at Y=0, Top face at Y=thickness
	for i in range(vertices.size()):
		vertices[i].y += half_thickness
	arrays[Mesh.ARRAY_VERTEX] = vertices

	# Get normals array for face detection
	# BoxMesh has 24 vertices (6 faces × 4 corners), each with a unique normal
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	# REPEAT MODE: All faces use full texture (0-1 UV range)
	# Use NORMALS to detect which face a vertex belongs to (not positions!)
	for i in range(vertices.size()):
		var v: Vector3 = vertices[i]
		var n: Vector3 = normals[i]

		# Calculate base U/V from X/Z position (used by horizontal faces)
		var base_u: float = (v.x + half_size) / grid_size
		var base_v: float = 1.0 - ((v.z + half_size) / grid_size)

		# Use normal to detect face (> 0.5 for floating-point safety)
		if n.y > 0.5:
			# TOP FACE (normal pointing up) - full texture based on X/Z
			uvs[i] = Vector2(base_u, base_v)

		elif n.y < -0.5:
			# BOTTOM FACE (normal pointing down) - full texture based on X/Z
			uvs[i] = Vector2(base_u, base_v)

		elif n.z > 0.5:
			# BACK FACE (Z+) - full texture based on X/Y
			var y_normalized: float = 1.0 - (v.y / thickness)
			uvs[i] = Vector2(base_u, y_normalized)

		elif n.z < -0.5:
			# FRONT FACE (Z-) - full texture based on X/Y (mirrored)
			var y_normalized: float = 1.0 - (v.y / thickness)
			uvs[i] = Vector2(1.0 - base_u, y_normalized)

		elif n.x > 0.5:
			# RIGHT SIDE (X+) - full texture based on Z/Y
			var z_normalized: float = (v.z + half_size) / grid_size
			var y_normalized: float = 1.0 - (v.y / thickness)
			uvs[i] = Vector2(z_normalized, y_normalized)

		elif n.x < -0.5:
			# LEFT SIDE (X-) - full texture based on Z/Y (mirrored)
			var z_normalized: float = 1.0 - ((v.z + half_size) / grid_size)
			var y_normalized: float = 1.0 - (v.y / thickness)
			uvs[i] = Vector2(z_normalized, y_normalized)

	arrays[Mesh.ARRAY_TEX_UV] = uvs

	# Rebuild the mesh with modified data
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return result


## Creates a triangular prism mesh for PRISM_MESH mode with REPEAT texture mode
## All 5 faces use full tile texture (uniform 0-1 UVs)
## Thickness = grid_size * MESH_THICKNESS_RATIO * depth_scale
static func create_prism_mesh_repeat(grid_size: float = 1.0, depth_scale: float = 1.0) -> ArrayMesh:
	var thickness: float = grid_size * GlobalConstants.MESH_THICKNESS_RATIO * depth_scale
	var half_size: float = grid_size / 2.0

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Prism vertices (triangular cross-section extruded along Y)
	# Mesh rests ON the grid plane (Y=0) instead of centered
	# Top face (Y = thickness) - triangle
	var top_bl := Vector3(-half_size, thickness, -half_size)  # Bottom-left
	var top_br := Vector3(half_size, thickness, -half_size)   # Bottom-right
	var top_tl := Vector3(-half_size, thickness, half_size)   # Top-left

	# Bottom face (Y = 0) - triangle (sits on grid plane)
	var bot_bl := Vector3(-half_size, 0.0, -half_size)
	var bot_br := Vector3(half_size, 0.0, -half_size)
	var bot_tl := Vector3(-half_size, 0.0, half_size)

	# UVs for top/bottom faces (matching flat triangle layout)
	var uv_bl := Vector2(0, 1)
	var uv_br := Vector2(1, 1)
	var uv_tl := Vector2(0, 0)

	# --- Top Face (Full Texture) ---
	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(Vector3.UP)
	st.set_uv(uv_bl)
	st.add_vertex(top_bl)
	st.set_uv(uv_br)
	st.add_vertex(top_br)
	st.set_uv(uv_tl)
	st.add_vertex(top_tl)

	# --- Bottom Face (Full Texture) ---
	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(Vector3.DOWN)
	st.set_uv(uv_bl)
	st.add_vertex(bot_tl)
	st.set_uv(uv_br)
	st.add_vertex(bot_br)
	st.set_uv(uv_tl)
	st.add_vertex(bot_bl)

	# --- Side Faces (3 Quads as 6 Triangles, Full Texture) ---
	# Side 1: Front edge (bl-br at Z-)
	_add_prism_side_quad_repeat(st, bot_bl, bot_br, top_br, top_bl)
	# Side 2: Left edge (tl-bl at X-)
	_add_prism_side_quad_repeat(st, bot_tl, bot_bl, top_bl, top_tl)
	# Side 3: Diagonal edge (br-tl)
	_add_prism_side_quad_repeat(st, bot_br, bot_tl, top_tl, top_br)

	st.generate_tangents()
	return st.commit()


## Helper to add a quad (2 triangles) for prism sides with full texture UVs (REPEAT mode)
## All side faces use uniform 0-1 UV mapping
static func _add_prism_side_quad_repeat(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	var normal: Vector3 = (v1 - v0).cross(v3 - v0).normalized()
	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(normal)

	# Full texture UVs for all side faces
	# v0, v1 are bottom edge (Y-), v2, v3 are top edge (Y+)
	var uv0 := Vector2(0.0, 1.0)  # bottom-left
	var uv1 := Vector2(1.0, 1.0)  # bottom-right
	var uv2 := Vector2(1.0, 0.0)  # top-right
	var uv3 := Vector2(0.0, 0.0)  # top-left

	# Triangle 1
	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_uv(uv1)
	st.add_vertex(v1)
	st.set_uv(uv2)
	st.add_vertex(v2)
	# Triangle 2
	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_uv(uv2)
	st.add_vertex(v2)
	st.set_uv(uv3)
	st.add_vertex(v3)


## Helper to add a quad (2 triangles) for prism sides with edge UV sampling
## side_type: 0=FRONT (bottom row), 1=LEFT (left col), 2=DIAGONAL (right col)
static func _add_prism_side_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, stripe: float, side_type: int) -> void:
	var normal: Vector3 = (v1 - v0).cross(v3 - v0).normalized()
	st.set_color(Color(0, 0, 0, 0))
	st.set_normal(normal)

	# Calculate UVs based on side type
	# v0, v1 are bottom edge (Y-), v2, v3 are top edge (Y+)
	# For edge stripes: map thickness direction to stripe width
	var uv0: Vector2
	var uv1: Vector2
	var uv2: Vector2
	var uv3: Vector2

	match side_type:
		0:  # FRONT (Z-) - sample bottom row (V = 1-stripe to 1)
			# Horizontal span maps to U, thickness maps to V within stripe
			uv0 = Vector2(0.0, 1.0)                    # bottom-left
			uv1 = Vector2(1.0, 1.0)                    # bottom-right
			uv2 = Vector2(1.0, 1.0 - stripe)          # top-right
			uv3 = Vector2(0.0, 1.0 - stripe)          # top-left
		1:  # LEFT (X-) - sample left column (U = 0 to stripe)
			# Vertical span maps to V, thickness maps to U within stripe
			uv0 = Vector2(0.0, 1.0)                    # bottom-front
			uv1 = Vector2(0.0, 0.0)                    # bottom-back
			uv2 = Vector2(stripe, 0.0)                # top-back
			uv3 = Vector2(stripe, 1.0)                # top-front
		2:  # DIAGONAL - sample right column (U = 1-stripe to 1)
			# Diagonal span maps to V, thickness maps to U within stripe
			uv0 = Vector2(1.0, 1.0)                    # bottom-right
			uv1 = Vector2(1.0, 0.0)                    # bottom-left (diagonal)
			uv2 = Vector2(1.0 - stripe, 0.0)          # top-left
			uv3 = Vector2(1.0 - stripe, 1.0)          # top-right

	# Triangle 1
	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_uv(uv1)
	st.add_vertex(v1)
	st.set_uv(uv2)
	st.add_vertex(v2)
	# Triangle 2
	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_uv(uv2)
	st.add_vertex(v2)
	st.set_uv(uv3)
	st.add_vertex(v3)


## Creates a quad mesh for MULTIMESH
static func create_tile_quad(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0)) -> ArrayMesh:

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Calculate normalized UV coordinates [0, 1] using GlobalUtil
	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	# Calculate world-space half dimensions
	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0

	# Vertex 0: Bottom-left
	st.set_uv(Vector2(uv_min.x, uv_max.y))
	st.add_vertex(Vector3(-half_width, 0.0, -half_height))

	# Vertex 1: Bottom-right
	st.set_uv(Vector2(uv_max.x, uv_max.y))
	st.add_vertex(Vector3(half_width, 0.0, -half_height))

	# Vertex 2: Top-right
	st.set_uv(Vector2(uv_max.x, uv_min.y))
	st.add_vertex(Vector3(half_width, 0.0, half_height))

	# Vertex 3: Top-left
	st.set_uv(Vector2(uv_min.x, uv_min.y))
	st.add_vertex(Vector3(-half_width, 0.0, half_height))

	# Indices
	st.add_index(0)
	st.add_index(1)
	st.add_index(2)
	st.add_index(0)
	st.add_index(2)
	st.add_index(3)

	st.generate_normals()
	st.generate_tangents()

	return st.commit()

## Creates a triangle mesh for MULTIMESH
static func create_tile_triangle(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0)) -> ArrayMesh:
	
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Calculate normalized UV coordinates [0, 1] using GlobalUtil
	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	# Calculate world-space half dimensions
	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0

	# Vertex 0: Bottom-left
	st.set_uv(Vector2(uv_min.x, uv_max.y))
	st.add_vertex(Vector3(-half_width, 0.0, -half_height))

	# Vertex 1: Bottom-right
	st.set_uv(Vector2(uv_max.x, uv_max.y))
	st.add_vertex(Vector3(half_width, 0.0, -half_height))

	# Vertex 2: Top-left
	st.set_uv(Vector2(uv_min.x, uv_min.y))
	st.add_vertex(Vector3(-half_width, 0.0, half_height))
	
	# Indices
	st.add_index(0)
	st.add_index(1)
	st.add_index(2)
	
	st.generate_normals()
	st.generate_tangents()
	
	return st.commit()
