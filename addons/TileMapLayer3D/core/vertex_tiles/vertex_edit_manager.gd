class_name VertexEditManager
extends RefCounted

## Manages vertex-edited tiles: conversion, rendering, corner manipulation.
## Vertex-edited tiles are REMOVED from columnar storage and get their own
## MeshInstance3D with arbitrary quad corners (non-affine shapes like trapezoids).
##
## Storage format: _vertex_tile_corners[tile_key] = {
##   "corners": PackedVector3Array [BL, BR, TR, TL] (world space),
##   "uv_rect": Rect2 (atlas pixel coordinates),
##   "tile_data": Dictionary (full snapshot for undo — re-create in columnar storage)
## }

## Currently selected tile key for editing (-1 = none)
var selected_tile_key: int = -1

## Reference to the TileMapLayer3D data node
var _tile_map: TileMapLayer3D = null

## Shared material for all vertex-edited tile meshes
var _vertex_material: ShaderMaterial = null

## Runtime dictionary of MeshInstance3D nodes (NOT persisted, rebuilt on load)
## tile_key (int) → MeshInstance3D
var _vertex_tile_meshes: Dictionary = {}

# --- Handle Dragging State ---
## Which corner (0-3) is currently being dragged, or -1 if none
var _dragging_handle: int = -1
## The corner position before the drag started (for undo)
var _drag_start_pos: Vector3 = Vector3.ZERO
## Screen-space hit radius for handle picking (pixels)
const HANDLE_SCREEN_RADIUS: float = 20.0


## Initialize with the active TileMapLayer3D node
func set_tile_map(tile_map: TileMapLayer3D) -> void:
	_tile_map = tile_map
	_vertex_material = null
	_vertex_tile_meshes.clear()
	selected_tile_key = -1


## Returns true if this tile has vertex-edited corners
func is_vertex_tile(tile_key: int) -> bool:
	if not _tile_map:
		return false
	return _tile_map.has_vertex_corners(tile_key)


## Select a vertex tile for editing (shows gizmo handles)
func select_tile(tile_key: int) -> void:
	selected_tile_key = tile_key


## Deselect current tile
func deselect() -> void:
	selected_tile_key = -1


## Get the 4 corner positions for the currently selected tile
func get_handle_positions(tile_key: int) -> PackedVector3Array:
	if not _tile_map:
		return PackedVector3Array()
	return _tile_map.get_vertex_corners(tile_key)


## Get the full vertex tile entry (corners + uv_rect + tile_data snapshot)
func get_vertex_entry(tile_key: int) -> Dictionary:
	if not _tile_map:
		return {}
	return _tile_map.get_vertex_entry(tile_key)


## Test if a screen position hits a handle. Returns handle index (0-3) or -1.
func pick_handle_at(camera: Camera3D, screen_pos: Vector2) -> int:
	if not _tile_map or selected_tile_key == -1:
		return -1
	var corners: PackedVector3Array = _tile_map.get_vertex_corners(selected_tile_key)
	if corners.size() != 4:
		return -1

	var best_idx: int = -1
	var best_dist: float = HANDLE_SCREEN_RADIUS

	for i: int in range(4):
		# Project world corner to screen
		var screen_corner: Vector2 = camera.unproject_position(corners[i])
		var dist: float = screen_pos.distance_to(screen_corner)
		if dist < best_dist:
			best_dist = dist
			best_idx = i

	return best_idx


## Begin dragging a handle. Returns true if a handle was picked.
func begin_drag(camera: Camera3D, screen_pos: Vector2) -> bool:
	var handle: int = pick_handle_at(camera, screen_pos)
	if handle < 0:
		return false
	_dragging_handle = handle
	var corners: PackedVector3Array = _tile_map.get_vertex_corners(selected_tile_key)
	_drag_start_pos = corners[handle]
	return true


## Update dragging handle position from mouse movement.
## Uses a camera-facing plane through the handle so dragging feels intuitive
## regardless of tile orientation (no wild jumps on tilted/rotated tiles).
func drag_to(camera: Camera3D, screen_pos: Vector2) -> void:
	if _dragging_handle < 0 or selected_tile_key == -1 or not _tile_map:
		return
	var corners: PackedVector3Array = _tile_map.get_vertex_corners(selected_tile_key)
	if corners.size() != 4:
		return

	var current_corner: Vector3 = corners[_dragging_handle]
	var ray_from: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	# Always project onto a camera-facing plane through the handle position.
	# This prevents wild jumps when the tile plane is near-parallel to the view.
	var cam_plane: Plane = Plane(-camera.global_basis.z, current_corner)
	var hit: Variant = cam_plane.intersects_ray(ray_from, ray_dir)
	if hit == null:
		return

	# Snap to half-grid
	var snapped_pos: Vector3 = hit as Vector3
	var gs: float = _tile_map.grid_size
	var half_gs: float = gs / 2.0
	snapped_pos.x = snapped(snapped_pos.x, half_gs)
	snapped_pos.y = snapped(snapped_pos.y, half_gs)
	snapped_pos.z = snapped(snapped_pos.z, half_gs)

	update_corner(selected_tile_key, _dragging_handle, snapped_pos)


## End dragging. Returns Dictionary with drag info for undo, or empty if no drag.
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


## Returns true if currently dragging a handle
func is_dragging() -> bool:
	return _dragging_handle >= 0


## Convert a normal tile to vertex-editable.
## Snapshots tile data, removes from columnar storage, creates vertex mesh.
## Returns true on success, false if tile not found or already converted.
func convert_tile(tile_key: int) -> bool:
	if not _tile_map:
		return false
	if _tile_map.has_vertex_corners(tile_key):
		return false  # Already a vertex tile

	var tile_index: int = _tile_map.get_tile_index(tile_key)
	if tile_index < 0:
		return false  # Tile doesn't exist

	# Warn if approaching threshold
	if _tile_map._vertex_tile_corners.size() >= GlobalConstants.VERTEX_TILE_WARNING_THRESHOLD:
		push_warning("VertexEditManager: %d vertex tiles — performance may degrade." % _tile_map._vertex_tile_corners.size())

	# Snapshot tile data BEFORE removing from columnar storage
	var tile_data: Dictionary = _tile_map.get_tile_data_at(tile_index)
	if tile_data.is_empty():
		return false
	var uv_rect: Rect2 = tile_data.get("uv_rect", Rect2())

	# Compute initial corners from the tile's current transform
	var corners: PackedVector3Array = _compute_initial_corners(tile_key, tile_data)
	if corners.size() != 4:
		return false

	# Store vertex entry with snapshot (persisted via @export on TileMapLayer3D)
	var entry: Dictionary = {
		"corners": corners,
		"uv_rect": uv_rect,
		"tile_data": tile_data,
	}
	_tile_map.set_vertex_entry(tile_key, entry)

	# Remove tile from columnar storage entirely — it's now a vertex-only tile
	_tile_map.remove_saved_tile_data(tile_key)

	# Rebuild chunks (the removed tile will no longer appear in MultiMesh)
	_tile_map._rebuild_chunks_from_saved_data()

	# Create standalone MeshInstance3D
	rebuild_mesh(tile_key)

	return true


## Undo helper: restore a converted tile back to columnar storage.
## Called by undo system to reverse a convert_tile() operation.
func undo_convert_tile(tile_key: int) -> void:
	if not _tile_map:
		return
	var entry: Dictionary = _tile_map.get_vertex_entry(tile_key)
	if entry.is_empty():
		return

	var tile_data: Dictionary = entry.get("tile_data", {})
	if tile_data.is_empty():
		return

	# Destroy vertex mesh
	_destroy_mesh_instance(tile_key)

	# Remove from vertex storage
	_tile_map.erase_vertex_corners(tile_key)

	# Re-save to columnar storage from snapshot
	_restore_tile_to_columnar(tile_key, tile_data)

	# Rebuild chunks so the tile reappears in MultiMesh
	_tile_map._rebuild_chunks_from_saved_data()

	# Deselect if this was the selected tile
	if selected_tile_key == tile_key:
		selected_tile_key = -1


## Delete a vertex-edited tile completely — removes from ALL storage.
func delete_vertex_tile(tile_key: int) -> void:
	if not _tile_map:
		return
	if not _tile_map.has_vertex_corners(tile_key):
		return

	# Destroy MeshInstance3D
	_destroy_mesh_instance(tile_key)

	# Remove from vertex storage
	_tile_map.erase_vertex_corners(tile_key)

	# Deselect if this was the selected tile
	if selected_tile_key == tile_key:
		selected_tile_key = -1


## Undo helper: restore a deleted vertex tile from its snapshot.
func undo_delete_vertex_tile(tile_key: int, entry: Dictionary) -> void:
	if not _tile_map:
		return

	# Restore vertex entry
	_tile_map.set_vertex_entry(tile_key, entry)

	# Rebuild mesh
	rebuild_mesh(tile_key)


## Update a single corner position and rebuild the mesh
func update_corner(tile_key: int, corner_idx: int, new_pos: Vector3) -> void:
	if not _tile_map:
		return
	var corners: PackedVector3Array = _tile_map.get_vertex_corners(tile_key)
	if corners.size() != 4 or corner_idx < 0 or corner_idx > 3:
		return
	corners[corner_idx] = new_pos
	_tile_map.set_vertex_corners(tile_key, corners)
	rebuild_mesh(tile_key)


## Update the UV rect of a vertex tile and rebuild its mesh.
## Used by Smart Select REPLACE to swap textures on converted tiles.
func update_vertex_tile_uv(tile_key: int, new_uv: Rect2) -> void:
	if not _tile_map:
		return
	var entry: Dictionary = _tile_map.get_vertex_entry(tile_key)
	if entry.is_empty():
		return
	entry["uv_rect"] = new_uv
	_tile_map.set_vertex_entry(tile_key, entry)
	rebuild_mesh(tile_key)


## Rebuild the MeshInstance3D for a vertex tile from its stored data.
## Reads UV from the vertex entry snapshot (NOT columnar storage — tile was removed).
func rebuild_mesh(tile_key: int) -> void:
	if not _tile_map:
		return
	var entry: Dictionary = _tile_map.get_vertex_entry(tile_key)
	if entry.is_empty():
		return
	var corners: PackedVector3Array = entry.get("corners", PackedVector3Array())
	if corners.size() != 4:
		return
	var uv_rect: Rect2 = entry.get("uv_rect", Rect2())

	if not _tile_map.tileset_texture:
		return
	var atlas_size: Vector2 = _tile_map.tileset_texture.get_size()
	if atlas_size.x <= 0.0 or atlas_size.y <= 0.0:
		return

	# Normalized UVs from atlas rect
	var uv_min: Vector2 = uv_rect.position / atlas_size
	var uv_max: Vector2 = (uv_rect.position + uv_rect.size) / atlas_size

	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2(uv_min.x, uv_max.y),  # BL
		Vector2(uv_max.x, uv_max.y),  # BR
		Vector2(uv_max.x, uv_min.y),  # TR
		Vector2(uv_min.x, uv_min.y),  # TL
	])

	# Convert world-space corners to local space (relative to TileMapLayer3D node)
	# MeshInstance3D is a child of _tile_map, so vertices must be in _tile_map local space
	var node_inv: Transform3D = _tile_map.global_transform.affine_inverse()
	var local_corners: PackedVector3Array = PackedVector3Array()
	for corner: Vector3 in corners:
		local_corners.append(node_inv * corner)

	# Compute normal from cross product of edges
	var edge1: Vector3 = local_corners[1] - local_corners[0]
	var edge2: Vector3 = local_corners[3] - local_corners[0]
	var normal: Vector3 = edge1.cross(edge2).normalized()
	if normal.is_zero_approx():
		normal = Vector3.UP  # Fallback for degenerate quads
	var normals: PackedVector3Array = PackedVector3Array([normal, normal, normal, normal])

	var indices: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 2, 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = local_corners
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_inst: MeshInstance3D = _get_or_create_mesh_instance(tile_key)
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _get_or_create_material()


## Rebuild all vertex tile meshes (called when plugin selects node).
## If the node already created mesh instances in _rebuild_vertex_tile_meshes(),
## this reuses them (just updates the mesh data).
func rebuild_all_vertex_meshes() -> void:
	if not _tile_map:
		return
	# Sync local cache with node's dictionary
	_vertex_tile_meshes = _tile_map._vertex_tile_mesh_instances.duplicate()

	# Rebuild each vertex tile (reuses existing MeshInstance3D nodes)
	for tile_key: int in _tile_map._vertex_tile_corners.keys():
		rebuild_mesh(tile_key)


# --- Private Methods ---

## Compute the initial 4 WORLD-space corners for a tile being converted.
## Uses the tile_data snapshot (already read before removal from columnar storage).
## Corners are stored in world space to match _set_handle() which stores world positions
## from camera ray intersection. All consumers (gizmo, rebuild_mesh) convert world→local.
func _compute_initial_corners(tile_key: int, tile_data: Dictionary) -> PackedVector3Array:
	var grid_pos: Vector3 = tile_data["grid_position"]
	var orientation: int = tile_data["orientation"]
	var mesh_rotation: int = tile_data["mesh_rotation"]
	var is_face_flipped: bool = tile_data["is_face_flipped"]
	var spin_angle_rad: float = tile_data["spin_angle_rad"]
	var tilt_angle_rad: float = tile_data["tilt_angle_rad"]
	var diagonal_scale: float = tile_data["diagonal_scale"]
	var tilt_offset_factor: float = tile_data["tilt_offset_factor"]
	var mesh_mode: int = tile_data["mesh_mode"]
	var depth_scale: float = tile_data["depth_scale"]
	var g_size: float = _tile_map.grid_size

	var transform: Transform3D
	if _tile_map._tile_custom_transforms.has(tile_key):
		transform = _tile_map._tile_custom_transforms[tile_key]
	else:
		transform = GlobalUtil.build_tile_transform(
			grid_pos, orientation, mesh_rotation, g_size,
			is_face_flipped, spin_angle_rad, tilt_angle_rad,
			diagonal_scale, tilt_offset_factor, mesh_mode, depth_scale
		)
		# build_tile_transform already sets origin via grid_to_world (+ tilt_offset for tilted tiles)
		# Convert from local space to world space by adding node position
		transform.origin += _tile_map.global_position

	# Base quad corners (local space, centered at origin on XZ plane)
	var half: float = g_size / 2.0
	var local_corners: PackedVector3Array = PackedVector3Array([
		Vector3(-half, 0.0, half),   # BL
		Vector3(half, 0.0, half),    # BR
		Vector3(half, 0.0, -half),   # TR
		Vector3(-half, 0.0, -half),  # TL
	])

	# Transform local quad corners to world space via the tile transform
	var world_corners: PackedVector3Array = PackedVector3Array()
	for corner: Vector3 in local_corners:
		world_corners.append(transform * corner)
	return world_corners


## Restore a tile from its data snapshot back to columnar storage
func _restore_tile_to_columnar(tile_key: int, tile_data: Dictionary) -> void:
	if not _tile_map:
		return
	_tile_map.save_tile_data_direct(
		tile_data["grid_position"],
		tile_data.get("uv_rect", Rect2()),
		tile_data["orientation"],
		tile_data["mesh_rotation"],
		tile_data["mesh_mode"],
		tile_data["is_face_flipped"],
		tile_data.get("terrain_id", -1),
		tile_data.get("spin_angle_rad", 0.0),
		tile_data.get("tilt_angle_rad", 0.0),
		tile_data.get("diagonal_scale", 0.0),
		tile_data.get("tilt_offset_factor", 0.0),
		tile_data.get("depth_scale", 1.0),
		tile_data.get("texture_repeat_mode", 0),
	)


## Get or create the shared StandardMaterial3D for vertex tile rendering.
## Reuses the node's material if available to avoid duplicates.
func _get_or_create_material() -> ShaderMaterial:
	# Prefer the node's shared material (created during _rebuild_vertex_tile_meshes)
	if _tile_map._vertex_tile_material and is_instance_valid(_tile_map._vertex_tile_material):
		if _tile_map._vertex_tile_material.get_shader_parameter("albedo_texture") != _tile_map.tileset_texture:
			_tile_map._vertex_tile_material.set_shader_parameter("albedo_texture", _tile_map.tileset_texture)
		_vertex_material = _tile_map._vertex_tile_material
		return _vertex_material

	if _vertex_material and is_instance_valid(_vertex_material):
		if _vertex_material.get_shader_parameter("albedo_texture") != _tile_map.tileset_texture:
			_vertex_material.set_shader_parameter("albedo_texture", _tile_map.tileset_texture)
		return _vertex_material

	var shader: Shader = load("res://addons/TileMapLayer3D/shaders/tile_vertex_edit.gdshader")
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_texture", _tile_map.tileset_texture)
	_vertex_material = mat
	_tile_map._vertex_tile_material = mat
	return mat


## Get or create a MeshInstance3D for a vertex tile.
## Uses the node's _vertex_tile_mesh_instances dictionary to avoid duplicates on reload.
func _get_or_create_mesh_instance(tile_key: int) -> MeshInstance3D:
	# Check node's dictionary first (may have been created by _rebuild_vertex_tile_meshes)
	if _tile_map._vertex_tile_mesh_instances.has(tile_key):
		var existing: MeshInstance3D = _tile_map._vertex_tile_mesh_instances[tile_key]
		if is_instance_valid(existing):
			return existing

	# Also check our local cache (for meshes created this session before node rebuild)
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


## Destroy a vertex tile's MeshInstance3D
func _destroy_mesh_instance(tile_key: int) -> void:
	# Clean up from both dictionaries
	if _tile_map:
		_tile_map.destroy_vertex_mesh_instance(tile_key)
	if _vertex_tile_meshes.has(tile_key):
		var mesh_inst: MeshInstance3D = _vertex_tile_meshes[tile_key]
		if is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
		_vertex_tile_meshes.erase(tile_key)
