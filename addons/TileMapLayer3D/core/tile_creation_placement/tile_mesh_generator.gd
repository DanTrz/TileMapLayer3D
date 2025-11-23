class_name TileMeshGenerator
extends RefCounted

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
