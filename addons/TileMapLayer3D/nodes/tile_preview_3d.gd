@tool
class_name TilePreview3D
extends Node3D

@export var grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE:
	set(value):
		if not Engine.is_editor_hint(): return
		if value > 0.0:
			grid_size = value
			_update_preview_mesh()

@export var preview_color: Color = GlobalConstants.DEFAULT_PREVIEW_COLOR:
	set(value):
		if not Engine.is_editor_hint(): return
		preview_color = value
		_update_preview_material()

@export var tile_model: Node3D = null

var _preview_mesh: MeshInstance3D = null
var _preview_material: ShaderMaterial = null
var _grid_indicator: MeshInstance3D = null

var _preview_instances: Array[MeshInstance3D] = []
var _preview_indicators: Array[MeshInstance3D] = []
var _is_multi_preview_active: bool = false

var preview_visible: bool = false
var preview_grid_position: Vector3 = Vector3.ZERO
var preview_orientation: int = 0
var preview_uv_rect: Rect2 = Rect2()
var preview_mesh_rotation: int = 0
var preview_is_face_flipped: bool = false
var preview_texture: Texture2D = null
var texture_filter_mode: int = GlobalConstants.DEFAULT_TEXTURE_FILTER
var current_mesh_mode: GlobalConstants.MeshMode = GlobalConstants.MeshMode.FLAT_SQUARE
var current_depth_scale: float = 1.0
var current_arch_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO

var _cached_uv_rect: Rect2 = Rect2()
var _cached_orientation: int = -1
var _cached_rotation: int = -1
var _cached_texture: Texture2D = null
var _cached_mesh_mode: GlobalConstants.MeshMode = -1
var _cached_flip: bool = false

func _ready() -> void:
	if not Engine.is_editor_hint(): return
	_create_preview_mesh()
	_create_grid_indicator()
	_create_preview_pool()

func _create_preview_mesh() -> void:
	_preview_mesh = MeshInstance3D.new()
	_preview_mesh.name = "PreviewMesh"
	_preview_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_preview_mesh)

func _create_grid_indicator() -> void:
	_grid_indicator = MeshInstance3D.new()
	_grid_indicator.name = "GridIndicator"
	_grid_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = GlobalConstants.PREVIEW_GRID_INDICATOR_SIZE
	_grid_indicator.mesh = box_mesh

	_grid_indicator.material_override = GlobalUtil.create_unshaded_material(GlobalConstants.PREVIEW_GRID_INDICATOR_COLOR)

	add_child(_grid_indicator)
	_grid_indicator.visible = false

func update_preview(
	grid_pos: Vector3,
	orientation: int,
	uv_rect: Rect2,
	texture: Texture2D,
	mesh_rotation: int = 0,
	is_face_flipped: bool = false,
	show: bool = true,
	is_decal = false
) -> void:
	preview_grid_position = grid_pos
	preview_orientation = orientation
	preview_uv_rect = uv_rect
	preview_mesh_rotation = mesh_rotation
	preview_is_face_flipped = is_face_flipped
	preview_texture = texture
	preview_visible = show

	if not show:
		hide_preview()
		return

	var transform: Transform3D = GlobalUtil.build_tile_transform(
		grid_pos, orientation, mesh_rotation, grid_size, is_face_flipped,
		0.0, 0.0, 0.0, 0.0,
		current_mesh_mode, current_depth_scale
	)

	position = transform.origin
	basis = Basis.IDENTITY

	if is_decal:
		position += GlobalUtil.get_rotation_axis_for_orientation(preview_orientation) * GlobalConstants.DECAL_NODE_OFFSET
		print("Preview decal offset: ", GlobalUtil.get_rotation_axis_for_orientation(preview_orientation) * GlobalConstants.DECAL_NODE_OFFSET)

	var needs_mesh_rebuild: bool = (
		_cached_uv_rect != uv_rect or
		_cached_orientation != orientation or
		_cached_rotation != mesh_rotation or
		_cached_texture != texture or
		_cached_mesh_mode != current_mesh_mode or
		_cached_flip != is_face_flipped
	)

	if needs_mesh_rebuild:
		_update_preview_mesh()
		_update_preview_material()

		_cached_uv_rect = uv_rect
		_cached_orientation = orientation
		_cached_rotation = mesh_rotation
		_cached_texture = texture
		_cached_mesh_mode = current_mesh_mode
		_cached_flip = is_face_flipped

	_preview_mesh.visible = true
	if _grid_indicator:
		_grid_indicator.visible = true

func hide_preview() -> void:
	preview_visible = false
	if _preview_mesh:
		_preview_mesh.visible = false
	if _grid_indicator:
		_grid_indicator.visible = false

	_hide_all_preview_instances()

func _create_preview_pool() -> void:
	for i in range(GlobalConstants.PREVIEW_POOL_SIZE):
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.name = "MultiPreviewMesh_%d" % i
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.visible = false
		add_child(mesh_instance)
		_preview_instances.append(mesh_instance)

		var indicator: MeshInstance3D = MeshInstance3D.new()
		indicator.name = "MultiPreviewIndicator_%d" % i
		indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = GlobalConstants.PREVIEW_GRID_INDICATOR_SIZE
		indicator.mesh = box_mesh

		indicator.material_override = GlobalUtil.create_unshaded_material(GlobalConstants.PREVIEW_GRID_INDICATOR_COLOR)

		indicator.visible = false
		add_child(indicator)
		_preview_indicators.append(indicator)

func _hide_all_preview_instances() -> void:
	for instance in _preview_instances:
		instance.visible = false
	for indicator in _preview_indicators:
		indicator.visible = false
	_is_multi_preview_active = false

func update_multi_preview(
	anchor_grid_pos: Vector3,
	selected_tiles: Array[Rect2],
	orientation: int,
	mesh_rotation: int = 0,
	texture: Texture2D = null,
	is_face_flipped: bool = false,
	show: bool = true
) -> void:
	if _preview_mesh:
		_preview_mesh.visible = false
	if _grid_indicator:
		_grid_indicator.visible = false

	if not show or selected_tiles.is_empty():
		_hide_all_preview_instances()
		return

	_is_multi_preview_active = true

	var transform: Transform3D = GlobalUtil.build_tile_transform(
		anchor_grid_pos, orientation, mesh_rotation, grid_size, is_face_flipped,
		0.0, 0.0, 0.0, 0.0,
		current_mesh_mode, current_depth_scale
	)

	position = transform.origin
	basis = transform.basis

	var first_tile_rect: Rect2 = selected_tiles[0]
	var first_tile_pixel_pos: Vector2 = first_tile_rect.position

	var active_texture: Texture2D = texture if texture else preview_texture
	if not active_texture:
		_hide_all_preview_instances()
		return

	var atlas_size: Vector2 = active_texture.get_size()

	var tile_count: int = min(selected_tiles.size(), GlobalConstants.PREVIEW_POOL_SIZE)
	for i in range(tile_count):
		var tile_uv_rect: Rect2 = selected_tiles[i]
		var tile_pixel_pos: Vector2 = tile_uv_rect.position

		var pixel_offset: Vector2 = tile_pixel_pos - first_tile_pixel_pos

		var tile_pixel_size: Vector2 = first_tile_rect.size
		var grid_offset: Vector2 = pixel_offset / tile_pixel_size

		var offset_3d: Vector3 = _calculate_3d_offset_for_orientation(grid_offset, orientation)

		_update_single_preview_instance(
			i,
			offset_3d,
			orientation,
			tile_uv_rect,
			active_texture,
			mesh_rotation
		)

	for i in range(tile_count, GlobalConstants.PREVIEW_POOL_SIZE):
		_preview_instances[i].visible = false
		_preview_indicators[i].visible = false

func _calculate_3d_offset_for_orientation(grid_offset: Vector2, orientation: int) -> Vector3:
	return Vector3(grid_offset.x, 0, grid_offset.y)

func _update_single_preview_instance(
	index: int,
	local_offset: Vector3,
	orientation: int,
	uv_rect: Rect2,
	texture: Texture2D,
	mesh_rotation: int
) -> void:
	if index < 0 or index >= _preview_instances.size():
		return

	var mesh_instance: MeshInstance3D = _preview_instances[index]
	var indicator: MeshInstance3D = _preview_indicators[index]

	var local_world_offset: Vector3 = local_offset * grid_size
	mesh_instance.position = local_world_offset
	indicator.position = local_world_offset

	var normalized_uv := Rect2(0, 0, 1, 1)
	var normalized_size := Vector2(1, 1)
	var mesh: ArrayMesh
	match current_mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE, GlobalConstants.MeshMode.BOX_MESH:
			mesh = TileMeshGenerator.create_tile_quad(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size)
			)
		GlobalConstants.MeshMode.FLAT_TRIANGULE, GlobalConstants.MeshMode.PRISM_MESH:
			mesh = TileMeshGenerator.create_tile_triangle(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size)
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
			mesh = TileMeshGenerator.create_arch_corner_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH:
			mesh = TileMeshGenerator.create_arch_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_I:
			mesh = TileMeshGenerator.create_arch_i_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
			mesh = TileMeshGenerator.create_arch_corner_i_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
			mesh = TileMeshGenerator.create_arch_corner_cap_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
			mesh = TileMeshGenerator.create_arch_corner_cap_i_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
			mesh = TileMeshGenerator.create_arch_corner_cap_duo_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C:
			mesh = TileMeshGenerator.create_arch_corner_c_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I:
			mesh = TileMeshGenerator.create_arch_corner_c_i_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S:
			mesh = TileMeshGenerator.create_arch_corner_s_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
			mesh = TileMeshGenerator.create_arch_corner_s_i_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)

	mesh_instance.mesh = mesh

	mesh_instance.basis = Basis.IDENTITY

	var atlas_size: Vector2 = texture.get_size()
	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var material: ShaderMaterial = GlobalUtil.create_preview_material(
		texture,
		uv_data.uv_min,
		uv_data.uv_max,
		texture_filter_mode,
		99
	)
	material.render_priority = 99
	mesh_instance.material_override = material

	var scale_factor: float = grid_size / GlobalConstants.DEFAULT_GRID_SIZE
	(indicator.mesh as BoxMesh).size = GlobalConstants.PREVIEW_GRID_INDICATOR_SIZE * scale_factor

	mesh_instance.visible = true
	indicator.visible = true

func _update_preview_mesh() -> void:
	if not _preview_mesh or not preview_texture:
		return

	var normalized_uv := Rect2(0, 0, 1, 1)
	var normalized_size := Vector2(1, 1)
	var mesh: ArrayMesh
	match current_mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE, GlobalConstants.MeshMode.BOX_MESH:
			mesh = TileMeshGenerator.create_tile_quad(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size)
			)
		GlobalConstants.MeshMode.FLAT_TRIANGULE, GlobalConstants.MeshMode.PRISM_MESH:
			mesh = TileMeshGenerator.create_tile_triangle(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size)
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
			mesh = TileMeshGenerator.create_arch_corner_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH:
			mesh = TileMeshGenerator.create_arch_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_I:
			mesh = TileMeshGenerator.create_arch_i_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
			mesh = TileMeshGenerator.create_arch_corner_i_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
			mesh = TileMeshGenerator.create_arch_corner_cap_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
			mesh = TileMeshGenerator.create_arch_corner_cap_i_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
			mesh = TileMeshGenerator.create_arch_corner_cap_duo_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C:
			mesh = TileMeshGenerator.create_arch_corner_c_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I:
			mesh = TileMeshGenerator.create_arch_corner_c_i_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S:
			mesh = TileMeshGenerator.create_arch_corner_s_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
			mesh = TileMeshGenerator.create_arch_corner_s_i_mesh(
				normalized_uv,
				normalized_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)

	_preview_mesh.mesh = mesh

	_preview_mesh.basis = GlobalUtil.build_tile_transform(
		Vector3.ZERO, preview_orientation, preview_mesh_rotation, grid_size, preview_is_face_flipped,
		0.0, 0.0, 0.0, 0.0,
		current_mesh_mode, current_depth_scale
	).basis

	if _grid_indicator and _grid_indicator.mesh:
		var scale_factor: float = grid_size / GlobalConstants.DEFAULT_GRID_SIZE
		(_grid_indicator.mesh as BoxMesh).size = GlobalConstants.PREVIEW_GRID_INDICATOR_SIZE * scale_factor

func _update_preview_material() -> void:
	if not _preview_mesh or not preview_texture:
		return

	var atlas_size: Vector2 = preview_texture.get_size()
	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(preview_uv_rect, atlas_size)

	_preview_material = GlobalUtil.create_preview_material(
		preview_texture,
		uv_data.uv_min,
		uv_data.uv_max,
		texture_filter_mode,
		99
	)
	_preview_material.render_priority = 99
	_preview_mesh.material_override = _preview_material


func update_color_preview(
	grid_pos: Vector3,
	orientation: int,
	color: Color,
	mesh_rotation: int = 0,
	is_face_flipped: bool = false,
	show: bool = true
) -> void:
	if not Engine.is_editor_hint():
		return

	preview_grid_position = grid_pos
	preview_orientation = orientation
	preview_mesh_rotation = mesh_rotation
	preview_is_face_flipped = is_face_flipped

	_is_multi_preview_active = false
	_hide_all_preview_instances()

	if not show:
		hide_preview()
		return

	var transform: Transform3D = GlobalUtil.build_tile_transform(
		grid_pos, orientation, mesh_rotation, grid_size, is_face_flipped,
		0.0, 0.0, 0.0, 0.0,
		current_mesh_mode, current_depth_scale
	)

	position = transform.origin
	basis = Basis.IDENTITY

	_update_color_mesh()
	_update_color_material(color)

	if _preview_mesh:
		_preview_mesh.visible = true
	if _grid_indicator:
		_grid_indicator.visible = true
	preview_visible = true


func _update_color_mesh() -> void:
	if not _preview_mesh:
		return

	var dummy_uv := Rect2(0, 0, 1, 1)
	var dummy_atlas_size := Vector2(1, 1)
	var mesh: ArrayMesh

	match current_mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE, GlobalConstants.MeshMode.BOX_MESH:
			mesh = TileMeshGenerator.create_tile_quad(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size)
			)
		GlobalConstants.MeshMode.FLAT_TRIANGULE, GlobalConstants.MeshMode.PRISM_MESH:
			mesh = TileMeshGenerator.create_tile_triangle(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size)
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
			mesh = TileMeshGenerator.create_arch_corner_mesh(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH:
			mesh = TileMeshGenerator.create_arch_mesh(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_I:
			mesh = TileMeshGenerator.create_arch_i_mesh(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
			mesh = TileMeshGenerator.create_arch_corner_i_mesh(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
			mesh = TileMeshGenerator.create_arch_corner_cap_mesh(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
			mesh = TileMeshGenerator.create_arch_corner_cap_i_mesh(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
			mesh = TileMeshGenerator.create_arch_corner_cap_duo_mesh(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C:
			mesh = TileMeshGenerator.create_arch_corner_c_mesh(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I:
			mesh = TileMeshGenerator.create_arch_corner_c_i_mesh(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S:
			mesh = TileMeshGenerator.create_arch_corner_s_mesh(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
			mesh = TileMeshGenerator.create_arch_corner_s_i_mesh(
				dummy_uv,
				dummy_atlas_size,
				Vector2(grid_size, grid_size),
				current_arch_radius_ratio
			)

	_preview_mesh.mesh = mesh

	_preview_mesh.basis = GlobalUtil.build_tile_transform(
		Vector3.ZERO, preview_orientation, preview_mesh_rotation, grid_size, preview_is_face_flipped,
		0.0, 0.0, 0.0, 0.0,
		current_mesh_mode, current_depth_scale
	).basis


func _update_color_material(color: Color) -> void:
	if not _preview_mesh:
		return

	_preview_mesh.material_override = GlobalUtil.create_unshaded_material(color, false, 99)
