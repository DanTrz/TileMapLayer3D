@tool
class_name TileChunkRender
extends RefCounted

## RenderingServer-backed replacement for the old MultiMeshTileChunkBase scene-tree node.
## One TileChunkRender == one render batch (one chunk, up to MAX_TILES tiles), exactly the
## conceptual unit the old MultiMeshInstance3D node was. It owns two RIDs:
##   - multimesh_rid : the MultiMesh buffer (per-tile transform/custom_data/color)
##   - instance_rid  : the scenario instance (the cullable unit; node-less twin of the
##                     old MultiMeshInstance3D). instance_set_custom_aabb on THIS is the
##                     per-chunk frustum-cull box — NOT per tile.
##
## RIDs are NOT ref-counted: a TileChunkRender being garbage-collected does NOT free its
## RIDs. They MUST be freed explicitly via free_rids() (see TileMapLayer3D free points).

# --- RenderingServer resources ---
var multimesh_rid: RID
var instance_rid: RID
var _scenario_bound: bool = false

# --- Identity / metadata (mirrors the old MultiMeshTileChunkBase fields) ---
var mesh_mode_type: GlobalConstants.MeshMode = GlobalConstants.MeshMode.FLAT_SQUARE
var chunk_index: int = -1  # Index within the region's chunk array
var tile_count: int = 0  # Number of tiles currently in this chunk
var tile_refs: Dictionary = {}  # int (tile_key) -> instance_index
var instance_to_key: Dictionary = {}  # int (instance_index) -> int (tile_key)
var region_key: Vector3i = Vector3i.ZERO
var region_key_packed: int = 0
var texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT
var chunk_name: String = ""  # Replaces Node.name (debug strings only)

# --- Buffer format + render state ---
var _use_colors: bool = false
var _use_custom_data: bool = true
var _visible_instance_count: int = 0  # Dual role: next-free cursor AND GPU visible count
var region_origin: Vector3 = Vector3.ZERO  # RegionSystem.region_key_to_world_origin(region_key)

const MAX_TILES: int = GlobalConstants.CHUNK_MAX_TILES


func is_full() -> bool:
	return tile_count >= MAX_TILES

func has_space() -> bool:
	return tile_count < MAX_TILES


# ---------------------------------------------------------------------------
# RID lifecycle
# ---------------------------------------------------------------------------

## Create the MultiMesh + instance RIDs and allocate the buffer. The shared mesh comes
## from TileMeshFactory. Scenario / world transform / material / shadow are applied
## separately (they need the owning node's context).
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


## Bind the instance to a rendering scenario (only valid while the owning node is in a World3D).
func bind_scenario(scenario: RID) -> void:
	if not instance_rid.is_valid() or not scenario.is_valid():
		return
	RenderingServer.instance_set_scenario(instance_rid, scenario)
	_scenario_bound = true


## Detach from the scenario (node left the World3D). Does NOT free RIDs.
func unbind_scenario() -> void:
	if not instance_rid.is_valid():
		return
	RenderingServer.instance_set_scenario(instance_rid, RID())
	_scenario_bound = false


## Position the instance in world/scenario space. Per-tile transforms stay multimesh-local
## (relative to region_origin); this composes the node transform with the region offset.
func set_world_transform(node_global_transform: Transform3D) -> void:
	if not instance_rid.is_valid():
		return
	RenderingServer.instance_set_transform(
		instance_rid, node_global_transform * Transform3D(Basis(), region_origin))


func set_material(material_rid: RID) -> void:
	if not instance_rid.is_valid():
		return
	RenderingServer.instance_geometry_set_material_override(instance_rid, material_rid)


## setting is a GeometryInstance3D.SHADOW_CASTING_SETTING_* int; those values map 1:1 to
## RenderingServer.SHADOW_CASTING_SETTING_*.
func set_cast_shadow(setting: int) -> void:
	if not instance_rid.is_valid():
		return
	RenderingServer.instance_geometry_set_cast_shadows_setting(instance_rid, setting)


func set_visible(v: bool) -> void:
	if not instance_rid.is_valid():
		return
	RenderingServer.instance_set_visible(instance_rid, v)


## World-space origin of this chunk given the owning node's transform (debug helper).
func get_world_origin(node_global_transform: Transform3D) -> Vector3:
	return (node_global_transform * Transform3D(Basis(), region_origin)).origin


## Free both RIDs. Double-free safe (guards is_valid + nulls). RefCounted GC will NOT do
## this for us — call from the explicit free points.
func free_rids() -> void:
	if instance_rid.is_valid():
		RenderingServer.free_rid(instance_rid)
		instance_rid = RID()
	if multimesh_rid.is_valid():
		RenderingServer.free_rid(multimesh_rid)
		multimesh_rid = RID()
	_scenario_bound = false


# ---------------------------------------------------------------------------
# Per-instance pass-throughs (replace the old chunk.multimesh.* calls 1:1)
# ---------------------------------------------------------------------------

func get_visible_instance_count() -> int:
	return _visible_instance_count


## Set the visible-instance cursor AND push it to the GPU. Keep all cursor changes routed
## through here so _visible_instance_count and the RenderingServer count stay in lockstep.
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


## Re-point this chunk's MultiMesh at a new shared mesh (used by arch-radius rebuild).
func set_mesh(mesh: Mesh) -> void:
	if multimesh_rid.is_valid() and mesh != null:
		RenderingServer.multimesh_set_mesh(multimesh_rid, mesh.get_rid())


# ---------------------------------------------------------------------------
# Bulk upload (Phase D) — one PackedFloat32Array for the whole chunk
# ---------------------------------------------------------------------------

## Upload a prebuilt buffer (transform 12 [+color 4][+custom_data 4] per instance) and set
## the visible count in one call. Caller is responsible for matching the allocate flags.
func upload_buffer(buffer: PackedFloat32Array, visible_count: int) -> void:
	if not multimesh_rid.is_valid():
		return
	RenderingServer.multimesh_set_buffer(multimesh_rid, buffer)
	set_visible_count(visible_count)


## Per-instance float stride for this chunk's buffer layout (transform + optional color/custom).
func buffer_stride() -> int:
	var stride: int = 12
	if _use_colors:
		stride += 4
	if _use_custom_data:
		stride += 4
	return stride
