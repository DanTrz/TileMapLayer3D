class_name VertexEditManager
extends RefCounted


var selected_tile_key: int = -1

var _tile_map: TileMapLayer3D = null
var _placement_manager: TilePlacementManager = null

var _vertex_material: ShaderMaterial = null

var _vertex_tile_meshes: Dictionary = {}

var _dragging_handle: int = -1
var _drag_start_pos: Vector3 = Vector3.ZERO
const HANDLE_SCREEN_RADIUS: float = 20.0


func set_tile_map(tile_map: TileMapLayer3D) -> void:
	_tile_map = tile_map
	_vertex_material = null
	_vertex_tile_meshes.clear()
	selected_tile_key = -1


func set_placement_manager(placement_manager: TilePlacementManager) -> void:
	_placement_manager = placement_manager


func is_vertex_tile(tile_key: int) -> bool:
	if not _tile_map:
		return false
	return _tile_map.has_vertex_corners(tile_key)


func select_tile(tile_key: int) -> void:
	selected_tile_key = tile_key


func deselect() -> void:
	selected_tile_key = -1


func get_handle_positions(tile_key: int) -> PackedVector3Array:
	if not _tile_map:
		return PackedVector3Array()
	return _tile_map.get_vertex_corners(tile_key)


func get_vertex_entry(tile_key: int) -> VertexTileEntry:
	if not _tile_map:
		return null
	return _tile_map.get_vertex_entry(tile_key)


func pick_handle_at(camera: Camera3D, screen_pos: Vector2) -> int:
	if not _tile_map or selected_tile_key == -1:
		return -1
	var corners: PackedVector3Array = _tile_map.get_vertex_corners(selected_tile_key)
	if corners.size() != 4:
		return -1

	var best_idx: int = -1
	var best_dist: float = HANDLE_SCREEN_RADIUS

	for i: int in range(4):
		var screen_corner: Vector2 = camera.unproject_position(corners[i])
		var dist: float = screen_pos.distance_to(screen_corner)
		if dist < best_dist:
			best_dist = dist
			best_idx = i

	return best_idx


func begin_drag(camera: Camera3D, screen_pos: Vector2) -> bool:
	var handle: int = pick_handle_at(camera, screen_pos)
	if handle < 0:
		return false
	_dragging_handle = handle
	var corners: PackedVector3Array = _tile_map.get_vertex_corners(selected_tile_key)
	_drag_start_pos = corners[handle]
	return true


## Project a screen point onto a camera-facing plane through anchor, then snap to half-grid. null on miss.
func project_to_snapped_position(camera: Camera3D, screen_pos: Vector2,
		anchor: Vector3, grid_size: float) -> Variant:
	var ray_from: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	var cam_plane: Plane = Plane(-camera.global_basis.z, anchor)
	var hit: Variant = cam_plane.intersects_ray(ray_from, ray_dir)
	if hit == null:
		return null

	var snapped_pos: Vector3 = hit as Vector3
	var half_gs: float = grid_size / 2.0
	snapped_pos.x = snapped(snapped_pos.x, half_gs)
	snapped_pos.y = snapped(snapped_pos.y, half_gs)
	snapped_pos.z = snapped(snapped_pos.z, half_gs)
	return snapped_pos


func drag_to(camera: Camera3D, screen_pos: Vector2) -> void:
	if _dragging_handle < 0 or selected_tile_key == -1 or not _tile_map:
		return
	var corners: PackedVector3Array = _tile_map.get_vertex_corners(selected_tile_key)
	if corners.size() != 4:
		return

	var result: Variant = project_to_snapped_position(camera, screen_pos, corners[_dragging_handle], _tile_map.grid_size)
	if result == null:
		return

	update_corner(selected_tile_key, _dragging_handle, result as Vector3)


func end_drag() -> Dictionary:
	if _dragging_handle < 0 or selected_tile_key == -1:
		_dragging_handle = -1
		return {}
	var corners: PackedVector3Array = _tile_map.get_vertex_corners(selected_tile_key)
	var result: Dictionary = {
		"tile_key": selected_tile_key,
		"handle": _dragging_handle,
		"old_pos": _drag_start_pos,
		"new_pos": corners[_dragging_handle],
	}
	_dragging_handle = -1
	return result


func is_dragging() -> bool:
	return _dragging_handle >= 0


## Convert a normal tile to vertex-editable. Snapshots data, removes from columnar storage, creates vertex mesh.
func convert_tile(tile_key: int) -> bool:
	if not _tile_map:
		return false
	if _tile_map.has_vertex_corners(tile_key):
		return false

	var tile_index: int = _tile_map.get_tile_index(tile_key)
	if tile_index < 0:
		return false

	var vertex_entries: Dictionary = _tile_map.get_vertex_tile_corners()
	if vertex_entries.size() >= GlobalConstants.VERTEX_TILE_WARNING_THRESHOLD:
		push_warning("VertexEditManager: %d vertex tiles — performance may degrade." % vertex_entries.size())

	# Snapshot BEFORE removing from columnar storage.
	var tile_info: PlacedTileInfo = _tile_map.get_tile_info_at_index(tile_index)
	if tile_info == null:
		return false

	# Only FLAT_SQUARE can be represented as a 4-corner quad.
	if tile_info.mesh_mode != GlobalConstants.MeshMode.FLAT_SQUARE:
		push_warning("VertexEditManager: Only FLAT_SQUARE tiles can be converted to vertex-editable.")
		return false

	var uv_rect: Rect2 = tile_info.uv_rect

	var corners: PackedVector3Array = _compute_initial_corners(tile_key, tile_info)
	if corners.size() != 4:
		return false

	var entry := VertexTileEntry.new()
	entry.corners = corners
	entry.uv_rect = uv_rect
	entry.tile_info = tile_info
	_tile_map.set_vertex_entry(tile_key, entry)

	if _placement_manager:
		_placement_manager.remove_tile_everywhere(tile_key)
	else:
		_tile_map.remove_saved_tile_data(tile_key)

	_tile_map._rebuild_chunks_from_saved_data()

	rebuild_mesh(tile_key)

	return true


func undo_convert_tile(tile_key: int) -> void:
	if not _tile_map:
		return
	var entry: VertexTileEntry = _tile_map.get_vertex_entry(tile_key)
	if entry == null:
		return

	var tile_info: PlacedTileInfo = entry.tile_info
	if tile_info == null:
		return

	_destroy_mesh_instance(tile_key)

	# Unregister BEFORE erasing the entry (needs corners); columnar rebuild re-adds it as a normal tile.
	_tile_map._unregister_vertex_tile_from_region(tile_key)

	_tile_map.erase_vertex_corners(tile_key)

	_restore_tile_to_columnar(tile_key, tile_info)

	_tile_map._rebuild_chunks_from_saved_data()
	if _placement_manager:
		_placement_manager.sync_from_tile_model()

	if selected_tile_key == tile_key:
		selected_tile_key = -1


func delete_vertex_tile(tile_key: int) -> void:
	if not _tile_map:
		return
	if not _tile_map.has_vertex_corners(tile_key):
		return

	_destroy_mesh_instance(tile_key)

	# Unregister BEFORE erasing the entry (needs corners to resolve region).
	_tile_map._unregister_vertex_tile_from_region(tile_key)

	_tile_map.erase_vertex_corners(tile_key)

	if selected_tile_key == tile_key:
		selected_tile_key = -1


func undo_delete_vertex_tile(tile_key: int, entry: VertexTileEntry) -> void:
	if not _tile_map:
		return

	_tile_map.set_vertex_entry(tile_key, entry)

	_tile_map._register_vertex_tile_in_region(tile_key)

	rebuild_mesh(tile_key)


func clear_all_vertex_tiles() -> void:
	if not _tile_map:
		return

	# Copy keys to avoid mutating during iteration.
	var keys: Array = _tile_map.get_vertex_tile_corners().keys()
	for key: int in keys:
		delete_vertex_tile(key)

	_vertex_tile_meshes.clear()
	selected_tile_key = -1


func update_corner(tile_key: int, corner_idx: int, new_pos: Vector3) -> void:
	if not _tile_map:
		return
	var corners: PackedVector3Array = _tile_map.get_vertex_corners(tile_key)
	if corners.size() != 4 or corner_idx < 0 or corner_idx > 3:
		return
	# Moving a corner can shift the centroid across a region boundary — re-register from the new centroid.
	_tile_map._unregister_vertex_tile_from_region(tile_key)
	corners[corner_idx] = new_pos
	_tile_map.set_vertex_corners(tile_key, corners)
	_tile_map._register_vertex_tile_in_region(tile_key)
	rebuild_mesh(tile_key)


func update_vertex_tile_uv(tile_key: int, new_uv: Rect2) -> void:
	if not _tile_map:
		return
	var entry: VertexTileEntry = _tile_map.get_vertex_entry(tile_key)
	if entry == null:
		return
	entry.uv_rect = new_uv
	_tile_map.set_vertex_entry(tile_key, entry)
	rebuild_mesh(tile_key)


func rebuild_mesh(tile_key: int) -> void:
	if not _tile_map:
		return
	var entry: VertexTileEntry = _tile_map.get_vertex_entry(tile_key)
	if entry == null:
		return
	var corners: PackedVector3Array = entry.corners
	if corners.size() != 4:
		return
	var uv_rect: Rect2 = entry.uv_rect

	if not _tile_map.tileset_texture:
		return
	var atlas_size: Vector2 = _tile_map.tileset_texture.get_size()
	if atlas_size.x <= 0.0 or atlas_size.y <= 0.0:
		return

	var node_inv: Transform3D = _tile_map.global_transform.affine_inverse()
	var mesh: ArrayMesh = _tile_map.build_vertex_tile_mesh(corners, uv_rect, atlas_size, node_inv)

	var mesh_inst: MeshInstance3D = _get_or_create_mesh_instance(tile_key)
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _get_or_create_material()


func rebuild_all_vertex_meshes() -> void:
	if not _tile_map:
		return
	_vertex_tile_meshes = _tile_map._vertex_tile_mesh_instances.duplicate()

	for tile_key: int in _tile_map.get_vertex_tile_corners().keys():
		rebuild_mesh(tile_key)


## Compute the initial 4 WORLD-space corners for a tile being converted.
## World space matches _set_handle() which stores world positions from camera ray intersection.
func _compute_initial_corners(tile_key: int, tile_info: PlacedTileInfo) -> PackedVector3Array:
	var grid_pos: Vector3 = tile_info.grid_position
	var orientation: int = tile_info.orientation
	var mesh_rotation: int = tile_info.mesh_rotation
	var is_face_flipped: bool = tile_info.is_face_flipped
	var spin_angle_rad: float = tile_info.spin_angle_rad
	var tilt_angle_rad: float = tile_info.tilt_angle_rad
	var diagonal_scale: float = tile_info.diagonal_scale
	var tilt_offset_factor: float = tile_info.tilt_offset_factor
	var mesh_mode: int = tile_info.mesh_mode
	var depth_scale: float = tile_info.depth_scale
	var g_size: float = _tile_map.grid_size

	var transform: Transform3D
	var custom_transforms: Dictionary = _tile_map.get_tile_custom_transforms()
	if custom_transforms.has(tile_key):
		transform = custom_transforms[tile_key]
	else:
		transform = GlobalUtil.build_tile_transform(
			grid_pos, orientation, mesh_rotation, g_size,
			is_face_flipped, spin_angle_rad, tilt_angle_rad,
			diagonal_scale, tilt_offset_factor, mesh_mode, depth_scale
		)
		# build_tile_transform sets a local origin; convert to world.
		transform.origin += _tile_map.global_position

	# Winding must match _add_square_to_arrays for correct face orientation.
	var half: float = g_size / 2.0
	var local_corners: PackedVector3Array = PackedVector3Array([
		Vector3(-half, 0.0, -half),
		Vector3(half, 0.0, -half),
		Vector3(half, 0.0, half),
		Vector3(-half, 0.0, half),
	])

	var world_corners: PackedVector3Array = PackedVector3Array()
	for corner: Vector3 in local_corners:
		world_corners.append(transform * corner)
	return world_corners


func _restore_tile_to_columnar(tile_key: int, tile_info: PlacedTileInfo) -> void:
	if not _tile_map:
		return
	_tile_map.save_tile_data_direct(
		tile_info.grid_position,
		tile_info.uv_rect,
		tile_info.orientation,
		tile_info.mesh_rotation,
		tile_info.mesh_mode,
		tile_info.is_face_flipped,
		tile_info.terrain_id,
		tile_info.spin_angle_rad,
		tile_info.tilt_angle_rad,
		tile_info.diagonal_scale,
		tile_info.tilt_offset_factor,
		tile_info.depth_scale,
		tile_info.texture_repeat_mode,
		tile_info.freeze_uv,
		tile_info.anim_step_x, tile_info.anim_step_y, tile_info.anim_total_frames, tile_info.anim_columns, tile_info.anim_speed_fps,
		tile_info.custom_transform if tile_info.has_custom_transform else Transform3D(),
		tile_info.atlas_source_id,
		tile_info.atlas_coords,
	)


func _get_or_create_material() -> ShaderMaterial:
	_vertex_material = _tile_map.ensure_vertex_material()
	return _vertex_material


func _get_or_create_mesh_instance(tile_key: int) -> MeshInstance3D:
	if _tile_map._vertex_tile_mesh_instances.has(tile_key):
		var existing: MeshInstance3D = _tile_map._vertex_tile_mesh_instances[tile_key]
		if is_instance_valid(existing):
			return existing

	if _vertex_tile_meshes.has(tile_key):
		var existing: MeshInstance3D = _vertex_tile_meshes[tile_key]
		if is_instance_valid(existing):
			_tile_map._vertex_tile_mesh_instances[tile_key] = existing
			return existing

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "VertexTile_%d" % tile_key
	_tile_map.add_child(mesh_inst)
	_vertex_tile_meshes[tile_key] = mesh_inst
	_tile_map._vertex_tile_mesh_instances[tile_key] = mesh_inst
	return mesh_inst


func _destroy_mesh_instance(tile_key: int) -> void:
	if _tile_map:
		_tile_map.destroy_vertex_mesh_instance(tile_key)
	if _vertex_tile_meshes.has(tile_key):
		var mesh_inst: MeshInstance3D = _vertex_tile_meshes[tile_key]
		if is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
		_vertex_tile_meshes.erase(tile_key)
