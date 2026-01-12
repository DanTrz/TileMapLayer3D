@tool
@icon("icons/sprite_mesh_instance.svg")
class_name SpriteMeshInstance
extends MeshInstance3D
##Integration and based on (https://github.com/98teg/SpriteMesh)** by [98teg](https://github.com/98teg) - A Godot plugin for creating 3D meshes from 2D sprites. Licensed under the MIT License.

## [SpriteMeshInstance], which inherit from [MeshInstance], is used to create the meshes based on
## the sprite. It is inspired by [Sprite3D], so many of its properties behave similarly.


const Quad = preload("./scripts/quad.gd")
const Frame = preload("./scripts/frame.gd")
const GreedyAlgorithm = preload("./scripts/greedy_algorithm.gd")

## [Texture2D] object to draw.
@export var spritemesh_texture: Texture2D: set = set_texture

@export_group("Mesh Properties")
## Depth of the mesh, measured in pixels.
@export_range(0, 128, 0.01, "suffix:px") var depth := 1.0: set = set_depth
## The size of one pixel's width on the sprite to scale it in 3D.
@export_range(0, 128, 0.01, "suffix:m") var pixel_size := 0.01: set = set_pixel_size
## If [code]true[/code], mesh can be seen from the back as well, if [code]false[/code], it is
## invisible when looking at it from behind.
@export var double_sided := true: set = set_double_sided

@export_group("Position")
## If [code]true[/code], mesh will be centered.
@export var centered := true: set = set_centered
## The mesh's placing offset.
@export var offset := Vector3.ZERO: set = set_offset
## If [code]true[/code], mesh is flipped horizontally.
@export var flip_h := false: set = set_flip_h
## If [code]true[/code], mesh is flipped vertically.
@export var flip_v := false: set = set_flip_v
## The direction in which the front of the mesh faces.
@export var axis := Vector3.AXIS_Z: set = set_axis

@export_group("Animation")
## The number of columns in the sprite sheet.
@export_range(1, 16384) var hframes := 1: set = set_hframes
## The number of rows in the sprite sheet.
@export_range(1, 16384) var vframes := 1: set = set_vframes
## Current frame to display from sprite sheet. [member hframes] or [member vframes] must be greater
## than [code]1[/code].
@export_range(0, 16383) var frame := 0: set = set_frame
## Coordinates of the frame to display from sprite sheet. This is as an alias for the frame
## property. [member hframes] or [member vframes] must be greater than [code]1[/code].
@export var frame_coords := Vector2i(0, 0): set = set_frame_coords

@export_group("Region")
## If [code]true[/code], the sprite will use [member region_rect] and display only the specified
## part of its spritemesh_texture.
@export var region_enabled := false: set = set_region_enabled
## The region of the atlas spritemesh_texture to display. [member region_enabled] must be [code]true[/code].
@export var region_rect := Rect2i(0, 0, 0, 0): set = set_region_rect

@export_group("Generation Parameters")
## The maximum value of alpha for the algorithm to not render a given pixel.
@export_range(0, 1) var alpha_threshold := 0.0: set = set_alpha_threshold
## Sometimes, the UV mapping would leak the color of adjacent pixels into parts of the mesh where
## they shouldn't be. As a result, some lines of color may appear at the border of some faces.
## [br]
## This property aims to fix this problem. When its value increases, the UV mapping would move
## inwards. Be careful, as it would also produce misalignment.
@export_range(0, 1) var uv_correction := 0.0: set = set_uv_correction

@export_group("Generated SpriteMesh")
## The result of the algorithm. It would generate automatically in the editor, or after calling
## [method update_sprite_mesh] in code.
@export var generated_sprite_mesh: SpriteMesh = null: set = set_generated_sprite_mesh

var _pending_update := false
var _seconds_left := 0.0


func _init():
	# Create unique SpriteMesh instance per node (avoid shared default resource)
	if generated_sprite_mesh == null:
		generated_sprite_mesh = SpriteMesh.new()


func _ready():
	_pending_update = false

	# Sync mesh from persisted generated_sprite_mesh on scene load
	if generated_sprite_mesh and generated_sprite_mesh.meshes.size() > 0:
		mesh = get_mesh_with_index(frame)
		if generated_sprite_mesh.material:
			material_override = generated_sprite_mesh.material

	# #DEBUG #TESTING # TEST #TODO
	# GlobalTileMapEvents.connect_tile_texture_selected(_on_tile_selected)

# #DEBUG #TESTING # TEST #TODO
# func _on_tile_selected(tile_texture: Texture2D, grid_size: Vector2):
# 	# Guard: ignore invalid textures
# 	if tile_texture == null: return
	
# 	var tex_size := tile_texture.get_size()
# 	if tex_size.x <= 0 or tex_size.y <= 0: return
	
# 	print("Tile Selection received in " + self.name)
# 	spritemesh_texture = tile_texture
# 	pixel_size = grid_size.x / tex_size.x
# 	_request_update()
# 	#DEBUG #TESTING # TEST #TODO

func _process(delta: float):
	if Engine.is_editor_hint() and _pending_update:
		if _seconds_left <= 0:
			_pending_update = false
			generated_sprite_mesh = await _generate_sprite_mesh()
		else:
			_seconds_left -= delta


## Generates the meshes and material given the current properties.
func update_sprite_mesh() -> void:
	if _pending_update:
		_pending_update = false
		generated_sprite_mesh = await _generate_sprite_mesh()


## Returns the mesh that corresponds to a frame of the animation, represented by its [param index].
func get_mesh_with_index(index: int) -> ArrayMesh:
	var size := generated_sprite_mesh.meshes.size()
	if(size == 0):
		return ArrayMesh.new()
	return generated_sprite_mesh.meshes[index % size]


func _request_update() -> void:
	_pending_update = true

	if Engine.is_editor_hint():
		_seconds_left = 1


func _generate_sprite_mesh(custom_material: StandardMaterial3D = null) -> SpriteMesh:
	var sprite_mesh := SpriteMesh.new()
	sprite_mesh.changed.connect(_apply_generated_sprite_mesh)

	if spritemesh_texture == null:
		return sprite_mesh

	sprite_mesh.meshes = _generate_meshes()

	if custom_material:
		sprite_mesh.material = custom_material
	else:
		# Use centralized material creation (GlobalUtil) for consistent toon shading
		sprite_mesh.material = GlobalUtil.create_baked_mesh_material(
			spritemesh_texture,
			0,     # filter_mode: Nearest (default for sprites)
			0,     # render_priority
			true,  # enable_alpha
			true   # enable_toon_shading
		)

	return sprite_mesh


func _generate_meshes() -> Array[ArrayMesh]:
	var meshes: Array[ArrayMesh] = []

	var st := SurfaceTool.new()
	var algorithm := GreedyAlgorithm.new()

	algorithm.show_side_quads = depth != 0
	algorithm.show_back_quads = double_sided
	algorithm.alpha_threshold = alpha_threshold
	algorithm.uv_correction = uv_correction

	for frame in _get_frames():
		algorithm.image = frame.image

		var quads = algorithm.generate_quads()
		
		#DEBUG #TESTING # TEST #TODO
		# Skip fully transparent frames - no quads to render
		if quads.is_empty():
			meshes.append(ArrayMesh.new())  # Add empty mesh to keep frame indices aligned
			continue

		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		for quad in quads:
			_transform_quad(quad, frame)
			quad.render(st)

		st.index()

		st.generate_normals()
		st.generate_tangents()

		st.optimize_indices_for_cache()

		meshes.append(st.commit())

		st.clear()

	return meshes


func _transform_quad(quad: Quad, frame: Frame) -> void:
	if centered:
		quad.translate(Vector3(-frame.get_width() / 2.0, -frame.get_height() / 2.0, 0.5))

	quad.scale(Vector3(pixel_size, pixel_size, pixel_size * depth))

	quad.translate(pixel_size * offset)

	match axis:
		Vector3.AXIS_X:
			quad.rotate(Vector3.UP, deg_to_rad(90))
		Vector3.AXIS_Y:
			quad.rotate(Vector3.LEFT, deg_to_rad(90))

	quad.scale_uvs(Vector2(frame.get_size()) / spritemesh_texture.get_size())
	quad.translate_uvs(Vector2(frame.get_position()) / spritemesh_texture.get_size())

	if flip_h:
		quad.flip_uvs_h()
		quad.translate_uvs(
			Vector2(
				frame.get_width() / spritemesh_texture.get_size().x - 2 * (
					quad.get_uvs_center().x - (frame.position.x / spritemesh_texture.get_size().x)
				),
				0,
			))

	if flip_v:
		quad.flip_uvs_v()
		quad.translate_uvs(
			Vector2(
				0,
				frame.get_height() / spritemesh_texture.get_size().y - 2 * (
					quad.get_uvs_center().y - (frame.position.y / spritemesh_texture.get_size().y)
				),
			))


func _apply_generated_sprite_mesh() -> void:
	mesh = get_mesh_with_index(frame)
	# Apply material from generated_sprite_mesh (for manual editor workflow)
	if generated_sprite_mesh and generated_sprite_mesh.material:
		material_override = generated_sprite_mesh.material


func _clear_sprite_mesh() -> void:
	if get_surface_override_material_count() != 0:
		set_surface_override_material(0, null)

	mesh = null


func _get_frames() -> Array:
	var image := spritemesh_texture.get_image()
	image.decompress()
	if region_enabled:
		image = image.get_region(region_rect)

	var frame_offset := region_rect.position if region_enabled else Vector2i.ZERO
	var frame_size := Vector2i(image.get_width() / hframes, image.get_height() / vframes)

	var frames: Array = []

	for i in range(vframes):
		for j in range(hframes):
			var frame := Frame.new()
			var frame_position := Vector2i(j * frame_size.x, i * frame_size.y)

			frame.image = image.get_region(Rect2i(frame_position, frame_size))
			frame.position = frame_offset + frame_position

			if flip_h:
				frame.flip_h()

			if flip_v:
				frame.flip_v()

			frames.append(frame)

	return frames


func set_texture(new_texture: Texture2D) -> void:
	spritemesh_texture = new_texture

	_request_update()


func set_depth(new_depth: float) -> void:
	depth = clampf(new_depth, 0, 128)

	_request_update()


func set_pixel_size(new_pixel_size: float) -> void:
	pixel_size = clampf(new_pixel_size, 0, 128)

	_request_update()


func set_double_sided(new_double_sided: bool) -> void:
	double_sided = new_double_sided

	_request_update()


func set_centered(new_centered: bool) -> void:
	centered = new_centered

	_request_update()


func set_offset(new_offset: Vector3) -> void:
	offset = new_offset

	_request_update()


func set_flip_h(new_flip_h: bool) -> void:
	flip_h = new_flip_h

	_request_update()


func set_flip_v(new_flip_v: bool) -> void:
	flip_v = new_flip_v

	_request_update()


func set_axis(new_axis: int) -> void:
	axis = clampi(new_axis, 0, 2)

	_request_update()


func set_hframes(new_hframes: int) -> void:
	hframes = clampi(new_hframes, 1, 16384)

	_request_update()


func set_vframes(new_vframes: int) -> void:
	vframes = clampi(new_vframes, 1, 16384)

	_request_update()


func set_frame(new_frame: int) -> void:
	if frame == new_frame:
		return

	frame = absi(new_frame) % (hframes * vframes)

	if generated_sprite_mesh.meshes.size() != 0:
		mesh = get_mesh_with_index(frame)

	frame_coords = Vector2i(frame % hframes, frame / hframes)


func set_frame_coords(new_frame_coords: Vector2i) -> void:
	if frame_coords == new_frame_coords:
		return

	frame_coords = Vector2i(
		absi(new_frame_coords.x) % hframes,
		absi(new_frame_coords.y) % vframes,
	)

	frame = frame_coords.x + frame_coords.y * hframes


func set_region_enabled(new_region_enabled: bool) -> void:
	region_enabled = new_region_enabled

	_request_update()


func set_region_rect(new_region_rect: Rect2) -> void:
	if spritemesh_texture == null:
		region_rect = Rect2(0, 0, 1, 1)
		return

	region_rect.position.x = clampi(new_region_rect.position.x, 0, spritemesh_texture.get_width() - 1)
	region_rect.position.y = clampi(new_region_rect.position.y, 0, spritemesh_texture.get_height() - 1)
	region_rect.size.x = clampi(
		new_region_rect.size.x, 1, spritemesh_texture.get_width() - region_rect.position.x
	)
	region_rect.size.y = clampi(
		new_region_rect.size.y, 1, spritemesh_texture.get_height() - region_rect.position.y
	)

	_request_update()


func set_alpha_threshold(new_alpha_threshold: float) -> void:
	alpha_threshold = clampf(new_alpha_threshold, 0, 1)

	_request_update()


func set_uv_correction(new_uv_correction: float) -> void:
	uv_correction = clampf(new_uv_correction, 0, 30)

	_request_update()


func set_generated_sprite_mesh(new_generated_sprite_mesh: SpriteMesh) -> void:
	generated_sprite_mesh = new_generated_sprite_mesh

	if generated_sprite_mesh == null:
		_clear_sprite_mesh()
		return

	if not generated_sprite_mesh.changed.is_connected(_apply_generated_sprite_mesh):
		generated_sprite_mesh.changed.connect(_apply_generated_sprite_mesh)

	_apply_generated_sprite_mesh()


func get_texture():
	return spritemesh_texture


func get_depth() -> float:
	return depth


func get_pixel_size() -> float:
	return pixel_size


func is_double_sided() -> bool:
	return double_sided


func is_centered() -> bool:
	return centered


func get_offset() -> Vector3:
	return offset


func is_flip_h() -> bool:
	return flip_h


func is_flip_v() -> bool:
	return flip_v


func get_axis() -> int:
	return axis


func get_hframes() -> int:
	return hframes


func get_vframes() -> int:
	return vframes


func get_frame() -> int:
	return frame


func get_frame_coords() -> Vector2i:
	return frame_coords


func is_region_enabled() -> bool:
	return region_enabled


func get_region_rect() -> Rect2i:
	return region_rect


func get_alpha_threshold() -> float:
	return alpha_threshold


func get_uv_correction() -> float:
	return uv_correction


func get_generated_sprite_mesh() -> SpriteMesh:
	return generated_sprite_mesh
