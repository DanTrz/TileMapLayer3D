@tool
class_name TileChunkRender
extends RefCounted


var multimesh_rid: RID
var instance_rid: RID
var _scenario_bound: bool = false

var mesh_mode_type: GlobalConstants.MeshMode = GlobalConstants.MeshMode.FLAT_SQUARE
var chunk_index: int = -1
var tile_count: int = 0
var tile_refs: Dictionary = {}
var instance_to_key: Dictionary = {}
var region_key: Vector3i = Vector3i.ZERO
var region_key_packed: int = 0
var texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT
var chunk_name: String = ""

var _use_colors: bool = false
var _use_custom_data: bool = true
var _visible_instance_count: int = 0
var region_origin: Vector3 = Vector3.ZERO

const MAX_TILES: int = GlobalConstants.CHUNK_MAX_TILES


func is_full() -> bool:
	return tile_count >= MAX_TILES

func has_space() -> bool:
	return tile_count < MAX_TILES



func create_rids(mesh: Mesh, use_colors: bool, use_custom_data: bool) -> void:
	_use_colors = use_colors
	_use_custom_data = use_custom_data

	multimesh_rid = RenderingServer.multimesh_create()
	RenderingServer.multimesh_allocate_data(
		multimesh_rid, MAX_TILES, RenderingServer.MULTIMESH_TRANSFORM_3D,
		use_colors, use_custom_data)
	if mesh != null:
		RenderingServer.multimesh_set_mesh(multimesh_rid, mesh.get_rid())
	RenderingServer.multimesh_set_visible_instances(multimesh_rid, 0)
	_visible_instance_count = 0

	instance_rid = RenderingServer.instance_create()
	RenderingServer.instance_set_base(instance_rid, multimesh_rid)
	RenderingServer.instance_set_custom_aabb(instance_rid, RegionSystem.chunk_local_aabb())


func bind_scenario(scenario: RID) -> void:
	if not instance_rid.is_valid() or not scenario.is_valid():
		return
	RenderingServer.instance_set_scenario(instance_rid, scenario)
	_scenario_bound = true


func unbind_scenario() -> void:
	if not instance_rid.is_valid():
		return
	RenderingServer.instance_set_scenario(instance_rid, RID())
	_scenario_bound = false


func set_world_transform(node_global_transform: Transform3D) -> void:
	if not instance_rid.is_valid():
		return
	RenderingServer.instance_set_transform(
		instance_rid, node_global_transform * Transform3D(Basis(), region_origin))


func set_material(material_rid: RID) -> void:
	if not instance_rid.is_valid():
		return
	RenderingServer.instance_geometry_set_material_override(instance_rid, material_rid)


func set_cast_shadow(setting: int) -> void:
	if not instance_rid.is_valid():
		return
	RenderingServer.instance_geometry_set_cast_shadows_setting(instance_rid, setting)


func set_visible(v: bool) -> void:
	if not instance_rid.is_valid():
		return
	RenderingServer.instance_set_visible(instance_rid, v)


func get_world_origin(node_global_transform: Transform3D) -> Vector3:
	return (node_global_transform * Transform3D(Basis(), region_origin)).origin


func free_rids() -> void:
	if instance_rid.is_valid():
		RenderingServer.free_rid(instance_rid)
		instance_rid = RID()
	if multimesh_rid.is_valid():
		RenderingServer.free_rid(multimesh_rid)
		multimesh_rid = RID()
	_scenario_bound = false



func get_visible_instance_count() -> int:
	return _visible_instance_count


func set_visible_count(n: int) -> void:
	_visible_instance_count = n
	if multimesh_rid.is_valid():
		RenderingServer.multimesh_set_visible_instances(multimesh_rid, n)


func set_instance_transform(index: int, xform: Transform3D) -> void:
	RenderingServer.multimesh_instance_set_transform(multimesh_rid, index, xform)

func get_instance_transform(index: int) -> Transform3D:
	return RenderingServer.multimesh_instance_get_transform(multimesh_rid, index)

func set_instance_custom_data(index: int, data: Color) -> void:
	RenderingServer.multimesh_instance_set_custom_data(multimesh_rid, index, data)

func get_instance_custom_data(index: int) -> Color:
	return RenderingServer.multimesh_instance_get_custom_data(multimesh_rid, index)

func set_instance_color(index: int, color: Color) -> void:
	if not _use_colors:
		return
	RenderingServer.multimesh_instance_set_color(multimesh_rid, index, color)

func get_instance_color(index: int) -> Color:
	if not _use_colors:
		return Color(0, 0, 0, 0)
	return RenderingServer.multimesh_instance_get_color(multimesh_rid, index)


func set_mesh(mesh: Mesh) -> void:
	if multimesh_rid.is_valid() and mesh != null:
		RenderingServer.multimesh_set_mesh(multimesh_rid, mesh.get_rid())



func upload_buffer(buffer: PackedFloat32Array, visible_count: int) -> void:
	if not multimesh_rid.is_valid():
		return
	RenderingServer.multimesh_set_buffer(multimesh_rid, buffer)
	set_visible_count(visible_count)


func buffer_stride() -> int:
	var stride: int = 12
	if _use_colors:
		stride += 4
	if _use_custom_data:
		stride += 4
	return stride
