class_name TileMeshGenerator
extends RefCounted


# static var local_mesh:BoxMesh = preload("uid://bsbwneod70p8n")


# static func create_quad_from_local_box_mesh() -> BoxMesh:
# 	var box_mesh:BoxMesh = local_mesh.duplicate(true) as BoxMesh
# 	return box_mesh

const LOCAL_MESH: BoxMesh = preload("uid://bsbwneod70p8n")

static func create_box_mesh(grid_size: float = 1.0) -> ArrayMesh:
	# Convert BoxMesh to ArrayMesh so we can modify vertex data
	var box: BoxMesh = LOCAL_MESH.duplicate(true) as BoxMesh

	# Scale the box dimensions (X/Z by grid_size, Y stays as thickness)
	box.size = Vector3(grid_size, box.size.y, grid_size)

	# Convert to ArrayMesh to access vertex data
	var st: SurfaceTool = SurfaceTool.new()
	st.create_from(box, 0)
	var array_mesh: ArrayMesh = st.commit()

	# Get the arrays to modify
	var arrays: Array = array_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = PackedColorArray()

	# Set all vertex colors to (0,0,0,0) for MultiMesh compatibility
	colors.resize(vertices.size())
	colors.fill(Color(0, 0, 0, 0))
	arrays[Mesh.ARRAY_COLOR] = colors

	# Remap UVs for the TOP face to match flat quad layout
	# BoxMesh top face vertices are at Y = height/2
	var half_size: float = grid_size / 2.0
	var top_y: float = box.size.y / 2.0

	for i in range(vertices.size()):
		var v: Vector3 = vertices[i]
		# Check if this vertex is on the top face (Y is at top)
		if is_equal_approx(v.y, top_y):
			# Remap UV based on X/Z position to match flat quad layout:
			# (-half, -half) -> UV(0, 1)  Bottom-left
			# (+half, -half) -> UV(1, 1)  Bottom-right
			# (+half, +half) -> UV(1, 0)  Top-right
			# (-half, +half) -> UV(0, 0)  Top-left
			var u: float = (v.x + half_size) / grid_size  # 0 to 1
			var tex_v: float = 1.0 - ((v.z + half_size) / grid_size)  # 1 to 0
			uvs[i] = Vector2(u, tex_v)
    
	arrays[Mesh.ARRAY_TEX_UV] = uvs

	# Rebuild the mesh with modified data
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return result

## Static utility class for generating 3D quad meshes from 2D tile UV data
## Responsibility: Mesh creation ONLY

## Creates a quad mesh for PREVIEW (includes UV data in COLOR)
## This version puts UV rect data in COLOR for the shader to use
static func create_preview_tile_quad(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0)
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Calculate normalized UV rect data for COLOR
	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_color: Color = uv_data.uv_color  # Contains (uv_min.x, uv_min.y, uv_max.x, uv_max.y)

	# Calculate world-space half dimensions
	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0

	# Define quad vertices with UV data in COLOR for preview
	# Vertex 0: Bottom-left
	st.set_color(uv_color)  # UV rect data for shader!
	st.set_uv(Vector2(0, 1))  # Standard 0-1 UV
	st.add_vertex(Vector3(-half_width, 0.0, -half_height))

	# Vertex 1: Bottom-right
	st.set_color(uv_color)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(Vector3(half_width, 0.0, -half_height))

	# Vertex 2: Top-right
	st.set_color(uv_color)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(Vector3(half_width, 0.0, half_height))

	# Vertex 3: Top-left
	st.set_color(uv_color)
	st.set_uv(Vector2(0, 0))
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

## Creates a triangle mesh for PREVIEW (includes UV data in COLOR)
static func create_preview_tile_triangle(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0)
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Calculate normalized UV rect data for COLOR
	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_color: Color = uv_data.uv_color
	
	# Calculate world-space half dimensions
	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0
	
	# Triangle vertices with UV data in COLOR
	# Vertex 0: Bottom-left
	st.set_color(uv_color)  # UV rect data for shader!
	st.set_uv(Vector2(0, 1))
	st.add_vertex(Vector3(-half_width, 0.0, -half_height))

	# Vertex 1: Bottom-right
	st.set_color(uv_color)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(Vector3(half_width, 0.0, -half_height))

	# Vertex 2: Top-left
	st.set_color(uv_color)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(Vector3(-half_width, 0.0, half_height))
	
	# Indices
	st.add_index(0)
	st.add_index(1)
	st.add_index(2)
	
	st.generate_normals()
	st.generate_tangents()
	
	return st.commit()

## Creates a quad mesh for MULTIMESH (COLOR must be zero)
## Original method - keeps COLOR at (0,0,0,0) for MultiMesh compatibility
static func create_tile_quad(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0)
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Calculate normalized UV coordinates [0, 1] using GlobalUtil
	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	# Calculate world-space half dimensions
	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0

	# IMPORTANT: For MultiMesh, vertex COLOR must be (0,0,0,0)
	# Vertex 0: Bottom-left
	st.set_color(Color(0, 0, 0, 0))  # MUST be zero for MultiMesh!
	st.set_uv(Vector2(uv_min.x, uv_max.y))
	st.add_vertex(Vector3(-half_width, 0.0, -half_height))

	# Vertex 1: Bottom-right
	st.set_color(Color(0, 0, 0, 0))
	st.set_uv(Vector2(uv_max.x, uv_max.y))
	st.add_vertex(Vector3(half_width, 0.0, -half_height))

	# Vertex 2: Top-right
	st.set_color(Color(0, 0, 0, 0))
	st.set_uv(Vector2(uv_max.x, uv_min.y))
	st.add_vertex(Vector3(half_width, 0.0, half_height))

	# Vertex 3: Top-left
	st.set_color(Color(0, 0, 0, 0))
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

## Creates a triangle mesh for MULTIMESH (COLOR must be zero)
static func create_tile_triangle(
	uv_rect: Rect2,
	atlas_size: Vector2,
	tile_world_size: Vector2 = Vector2(1.0, 1.0)
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Calculate normalized UV coordinates [0, 1] using GlobalUtil
	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var uv_min: Vector2 = uv_data.uv_min
	var uv_max: Vector2 = uv_data.uv_max

	# Calculate world-space half dimensions
	var half_width: float = tile_world_size.x / 2.0
	var half_height: float = tile_world_size.y / 2.0
	
	# IMPORTANT: For MultiMesh, vertex COLOR must be (0,0,0,0)
	# Vertex 0: Bottom-left
	st.set_color(Color(0, 0, 0, 0))  # MUST be zero for MultiMesh!
	st.set_uv(Vector2(uv_min.x, uv_max.y))
	st.add_vertex(Vector3(-half_width, 0.0, -half_height))

	# Vertex 1: Bottom-right
	st.set_color(Color(0, 0, 0, 0))
	st.set_uv(Vector2(uv_max.x, uv_max.y))
	st.add_vertex(Vector3(half_width, 0.0, -half_height))

	# Vertex 2: Top-left
	st.set_color(Color(0, 0, 0, 0))
	st.set_uv(Vector2(uv_min.x, uv_min.y))
	st.add_vertex(Vector3(-half_width, 0.0, half_height))
	
	# Indices
	st.add_index(0)
	st.add_index(1)
	st.add_index(2)
	
	st.generate_normals()
	st.generate_tangents()
	
	return st.commit()
