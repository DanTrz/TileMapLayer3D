class_name TileHighlightManager
extends RefCounted

## Manages all tile highlight overlays (golden selection + red blocked).
## Owns MultiMesh creation, material creation, transform positioning.
## Created by TileMapLayer3D, receives reference to it for tile data lookups.

var _tile_map: TileMapLayer3D
var _grid_size: float

# Golden highlight (multi-tile selection/preview)
var _highlight_mm: MultiMesh = null
var _highlight_instance: MultiMeshInstance3D = null
var _highlighted_keys: Array[int] = []

# Red blocked highlight (single tile, out-of-bounds warning)
var _blocked_mm: MultiMesh = null
var _blocked_instance: MultiMeshInstance3D = null
var _is_blocked_visible: bool = false


func _init(tile_map: TileMapLayer3D, p_grid_size: float) -> void:
	_tile_map = tile_map
	_grid_size = p_grid_size


## Call from TileMapLayer3D._ready() after node is in tree.
## Creates both the golden highlight overlay and the red blocked overlay.
func create_overlays() -> void:
	var pair: Array = _create_overlay_pair(
		GlobalConstants.MAX_HIGHLIGHTED_TILES,
		GlobalConstants.HIGHLIGHT_BOX_SCALE,
		GlobalConstants.HIGHLIGHT_BOX_THICKNESS,
		_create_material(GlobalConstants.TILE_HIGHLIGHT_COLOR),
		"TileHighlightOverlay"
	)
	_highlight_mm = pair[0]
	_highlight_instance = pair[1]

	var blocked_pair: Array = _create_overlay_pair(
		1,
		GlobalConstants.BLOCKED_HIGHLIGHT_BOX_SCALE,
		GlobalConstants.BLOCKED_HIGHLIGHT_BOX_THICKNESS,
		_create_material(GlobalConstants.TILE_BLOCKED_HIGHLIGHT_COLOR),
		"BlockedPositionHighlight"
	)
	_blocked_mm = blocked_pair[0]
	_blocked_instance = blocked_pair[1]


# ==============================================================================
# GOLDEN HIGHLIGHT (multi-tile selection/preview)
# ==============================================================================

## Highlights multiple tiles by positioning golden overlay boxes at their transforms.
## @param tile_keys: Array of integer tile keys to highlight
func highlight_tiles(tile_keys: Array[int]) -> void:
	if not _highlight_mm:
		return

	_highlighted_keys = tile_keys.duplicate()

	var count: int = mini(tile_keys.size(), _highlight_mm.instance_count)
	_highlight_mm.visible_instance_count = count

	for i: int in range(count):
		var tile_key: int = tile_keys[i]

		var parsed: Dictionary = TileKeySystem.unpack_tile_key(tile_key)
		var grid_pos: Vector3 = parsed.position
		var orientation: int = parsed.orientation

		var tile_index: int = _tile_map.get_tile_index(tile_key)
		if tile_index < 0:
			continue

		var tile_data: Dictionary = _tile_map.get_tile_data_at(tile_index)
		if tile_data.is_empty():
			continue

		var mesh_rotation: int = tile_data.get("mesh_rotation", 0)
		var is_face_flipped: bool = tile_data.get("is_face_flipped", false)

		var tile_transform: Transform3D = GlobalUtil.build_tile_transform(
			grid_pos, orientation, mesh_rotation, _grid_size, is_face_flipped
		)
		_highlight_mm.set_instance_transform(i, _apply_box_correction(tile_transform, 0.01))


## Clears all golden tile highlights.
func clear_highlights() -> void:
	if _highlight_mm:
		_highlight_mm.visible_instance_count = 0
		_highlighted_keys.clear()


## Returns the currently highlighted tile keys.
func get_highlighted_keys() -> Array[int]:
	return _highlighted_keys


# ==============================================================================
# RED BLOCKED HIGHLIGHT (single tile, out-of-bounds warning)
# ==============================================================================

## Shows a red blocked-position warning at a single grid position.
## Used when cursor is outside valid coordinate range.
## @param grid_pos: Grid position that is blocked
## @param orientation: Tile orientation (0-25)
func show_blocked(grid_pos: Vector3, orientation: int) -> void:
	if not _blocked_mm:
		return

	var tile_transform: Transform3D = GlobalUtil.build_tile_transform(
		grid_pos, orientation, 0, _grid_size, false
	)
	_blocked_mm.set_instance_transform(0, _apply_box_correction(tile_transform, 0.02))
	_blocked_mm.visible_instance_count = 1
	_is_blocked_visible = true


## Clears the red blocked position highlight.
func clear_blocked() -> void:
	if _blocked_mm:
		_blocked_mm.visible_instance_count = 0
		_is_blocked_visible = false


## Returns whether the blocked highlight is currently visible.
func is_blocked_visible() -> bool:
	return _is_blocked_visible


# ==============================================================================
# SELECTION QUERY: AREA HIGHLIGHT (Shift+Drag fill/erase preview)
# ==============================================================================

## Highlights tiles within a rectangular area (shows what will be affected).
## Detects ALL tiles within bounds, including half-grid positions (0.5 snap).
## @param start_pos: One corner of the selection rectangle
## @param end_pos: Opposite corner of the selection rectangle
## @param orientation: Active plane orientation (0-25)
## @param is_erase: True for erase mode (iterates existing tiles), false for paint mode (generates grid positions)
func highlight_tiles_in_area(start_pos: Vector3, end_pos: Vector3, orientation: int, is_erase: bool = false) -> void:
	# Calculate actual min/max bounds (user may have dragged in any direction)
	var min_pos: Vector3 = Vector3(
		min(start_pos.x, end_pos.x),
		min(start_pos.y, end_pos.y),
		min(start_pos.z, end_pos.z)
	)
	var max_pos: Vector3 = Vector3(
		max(start_pos.x, end_pos.x),
		max(start_pos.y, end_pos.y),
		max(start_pos.z, end_pos.z)
	)

	# Apply orientation-aware tolerance to match erase_area_with_undo() behavior
	# Tolerance applied ONLY on plane axes, NOT depth axis (prevents misleading preview)
	if is_erase:
		var tolerance: float = GlobalConstants.AREA_ERASE_SURFACE_TOLERANCE
		var tolerance_vector: Vector3 = GlobalUtil.get_orientation_tolerance(orientation, tolerance)
		min_pos -= tolerance_vector
		max_pos += tolerance_vector

	var tiles_to_highlight: Array[int] = []

	if is_erase:
		# ERASE MODE: Iterate through ALL existing tiles and check bounds
		const MAX_HIGHLIGHT_CHECK: int = 20000
		var total_tiles: int = _tile_map.get_tile_count()
		if total_tiles > MAX_HIGHLIGHT_CHECK:
			clear_highlights()
			return

		var total_in_bounds: int = 0
		for tile_idx: int in range(total_tiles):
			var tile_data: Dictionary = _tile_map.get_tile_data_at(tile_idx)
			if tile_data.is_empty():
				continue
			var tile_pos: Vector3 = tile_data.get("grid_position", Vector3.ZERO)

			var is_within_bounds: bool = (
				tile_pos.x >= min_pos.x and tile_pos.x <= max_pos.x and
				tile_pos.y >= min_pos.y and tile_pos.y <= max_pos.y and
				tile_pos.z >= min_pos.z and tile_pos.z <= max_pos.z
			)

			if is_within_bounds:
				total_in_bounds += 1
				var tile_orientation: int = tile_data.get("orientation", 0)
				var tile_key: int = GlobalUtil.make_tile_key(tile_pos, tile_orientation)
				if tiles_to_highlight.size() < GlobalConstants.MAX_HIGHLIGHTED_TILES:
					tiles_to_highlight.append(tile_key)

		if total_in_bounds > GlobalConstants.MAX_HIGHLIGHTED_TILES:
			push_warning("TileMapLayer3D: Area selection showing %d/%d tiles (erase will still affect all %d tiles)" % [
				GlobalConstants.MAX_HIGHLIGHTED_TILES, total_in_bounds, total_in_bounds])
	else:
		# PAINT MODE: Highlight tiles matching current orientation (supports half-grid with 0.5 snap)
		var snap_size: float = _tile_map.settings.grid_snap_size if _tile_map.settings else 1.0
		var positions: Array[Vector3] = GlobalUtil.get_grid_positions_in_area_with_snap(
			min_pos, max_pos, orientation, snap_size
		)

		var total_in_bounds: int = 0
		for grid_pos: Vector3 in positions:
			var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
			if _tile_map.has_tile(tile_key):
				total_in_bounds += 1
				if tiles_to_highlight.size() < GlobalConstants.MAX_HIGHLIGHTED_TILES:
					tiles_to_highlight.append(tile_key)

		if total_in_bounds > GlobalConstants.MAX_HIGHLIGHTED_TILES:
			push_warning("TileMapLayer3D: Area selection showing %d/%d tiles (fill will still affect all %d tiles)" % [
				GlobalConstants.MAX_HIGHLIGHTED_TILES, total_in_bounds, total_in_bounds])

	if tiles_to_highlight.is_empty():
		clear_highlights()
	else:
		highlight_tiles(tiles_to_highlight)


# ==============================================================================
# SELECTION QUERY: PREVIEW HIGHLIGHT (cursor hover during paint)
# ==============================================================================

## Highlights tiles at the cursor preview position (shows what will be replaced).
## For multi-tile selections, calculates offsets for each selected tile.
## @param grid_pos: Current cursor grid position
## @param orientation: Active plane orientation (0-25)
## @param selected_tiles: Array of selected UV rects (empty for single-tile)
## @param mesh_rotation: Current Q/E rotation (0-3)
func highlight_at_preview(grid_pos: Vector3, orientation: int, selected_tiles: Array[Rect2], mesh_rotation: int) -> void:
	var tiles_to_highlight: Array[int] = []

	if selected_tiles.size() > 1:
		# Multi-tile: calculate tile keys for each stamp position
		var anchor_uv_rect: Rect2 = selected_tiles[0]
		for tile_uv_rect: Rect2 in selected_tiles:
			var pixel_offset: Vector2 = tile_uv_rect.position - anchor_uv_rect.position
			var tile_pixel_size: Vector2 = tile_uv_rect.size
			var grid_offset_2d: Vector2 = pixel_offset / tile_pixel_size

			# Transform offset to 3D based on orientation
			var local_offset: Vector3 = Vector3(grid_offset_2d.x, 0, grid_offset_2d.y)
			var base_basis: Basis = GlobalUtil.get_tile_rotation_basis(orientation)
			var rotated_basis: Basis = GlobalUtil.apply_mesh_rotation(base_basis, orientation, mesh_rotation)
			var world_offset: Vector3 = rotated_basis * local_offset

			var tile_grid_pos: Vector3 = grid_pos + world_offset
			var multi_tile_key: int = GlobalUtil.make_tile_key(tile_grid_pos, orientation)

			if _tile_map.has_tile(multi_tile_key):
				tiles_to_highlight.append(multi_tile_key)
	else:
		# Single-tile check
		var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
		if _tile_map.has_tile(tile_key):
			tiles_to_highlight.append(tile_key)

	if tiles_to_highlight.is_empty():
		clear_highlights()
	else:
		highlight_tiles(tiles_to_highlight)


# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

## Applies BoxMesh rotation correction + surface normal offset to a tile transform.
## BoxMesh and QuadMesh have different default axis orientations, so a -90deg X
## rotation is needed. Then offset along surface normal prevents z-fighting.
## @param tile_transform: The base tile transform from build_tile_transform()
## @param offset: Distance along surface normal (0.01 for golden, 0.02 for blocked)
func _apply_box_correction(tile_transform: Transform3D, offset: float) -> Transform3D:
	var corrected: Transform3D = tile_transform
	var rotation_correction: Basis = Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	corrected.basis = corrected.basis * rotation_correction
	var surface_normal: Vector3 = corrected.basis.y.normalized()
	corrected.origin += surface_normal * offset
	return corrected


## Creates a StandardMaterial3D for highlight overlays.
## Unshaded, alpha-transparent, no depth test, double-sided.
## @param color: The albedo color (golden for selection, red for blocked)
func _create_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.render_priority = GlobalConstants.HIGHLIGHT_RENDER_PRIORITY
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Factory: creates a MultiMesh + MultiMeshInstance3D pair for highlight overlays.
## The MultiMeshInstance3D is added as a child of the TileMapLayer3D node.
## Owner is NOT set — highlight overlays are editor-only, not saved to scene.
func _create_overlay_pair(
	instance_count: int, box_scale: float, box_thickness: float,
	material: Material, overlay_name: String
) -> Array:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = instance_count
	mm.visible_instance_count = 0

	var box := BoxMesh.new()
	box.size = Vector3(_grid_size * box_scale, _grid_size * box_scale, box_thickness)
	mm.mesh = box

	var instance := MultiMeshInstance3D.new()
	instance.name = overlay_name
	instance.multimesh = mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = material

	_tile_map.add_child(instance)
	# DO NOT set owner - highlight overlay is editor-only, not saved to scene

	return [mm, instance]
