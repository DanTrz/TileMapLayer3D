class_name TilePlacementManager
extends RefCounted

## Handles tile placement logic using MultiMesh for performance
## Controls Placement logic and MultiMesh instance management

## Enum for tile orientation modes (18-state system: 6 base + 12 tilted)
enum TileOrientation {
	# === BASE ORIENTATIONS (existing) ===
	FLOOR,           # 0 - Horizontal, facing up (Y+)
	CEILING,         # 1 - Horizontal, facing down (Y-)
	WALL_NORTH,      # 2 - Vertical, facing south (Z+)
	WALL_SOUTH,      # 3 - Vertical, facing north (Z-)
	WALL_EAST,       # 4 - Vertical, facing west (X-)
	WALL_WEST,       # 5 - Vertical, facing east (X+)

	# === TILTED VARIANTS (new - 45° rotations) ===
	# Floor/Ceiling tilts on X-axis (forward/backward ramps)
	FLOOR_TILT_POS_X,      # 6 - Floor tilted forward (+45° on X-axis, ramp up toward +Z)
	FLOOR_TILT_NEG_X,      # 7 - Floor tilted backward (-45° on X-axis, ramp down toward +Z)
	CEILING_TILT_POS_X,    # 8 - Ceiling tilted forward (+45° on X-axis)
	CEILING_TILT_NEG_X,    # 9 - Ceiling tilted backward (-45° on X-axis)

	# North/South walls tilt on Y-axis (left/right lean)
	WALL_NORTH_TILT_POS_Y, # 10 - North wall leaning right (+45° on Y-axis)
	WALL_NORTH_TILT_NEG_Y, # 11 - North wall leaning left (-45° on Y-axis)
	WALL_SOUTH_TILT_POS_Y, # 12 - South wall leaning right (+45° on Y-axis)
	WALL_SOUTH_TILT_NEG_Y, # 13 - South wall leaning left (-45° on Y-axis)

	# East/West walls tilt on X-axis (forward/backward lean)
	WALL_EAST_TILT_POS_X,  # 14 - East wall leaning forward (+45° on X-axis)
	WALL_EAST_TILT_NEG_X,  # 15 - East wall leaning backward (-45° on X-axis)
	WALL_WEST_TILT_POS_X,  # 16 - West wall leaning forward (+45° on X-axis)
	WALL_WEST_TILT_NEG_X,  # 17 - West wall leaning backward (-45° on X-axis)
}

var grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE
var tile_world_size: Vector2 = Vector2(1.0, 1.0)
var grid_snap_size: float = GlobalConstants.DEFAULT_GRID_SNAP_SIZE  # Snap resolution: 1.0 = full grid, 0.5 = half grid, 0.25 = quarter, etc.

var tile_map_layer3d_root: TileMapLayer3D = null
var tileset_texture: Texture2D = null
var current_tile_uv: Rect2 = Rect2()
# REMOVED: current_orientation_18d and current_orientation_6d - now in GlobalPlaneDetector singleton
var current_mesh_rotation: int = 0  # Mesh rotation state: 0-3 (0°, 90°, 180°, 270°)
var is_current_face_flipped: bool = false  # Face flip state: true = back face visible (F key)
var auto_detect_orientation: bool = false  # When true, use raycast normal to determine orientation

# Multi-tile selection state (Phase 4)
var multi_tile_selection: Array[Rect2] = []  # Multiple UV rects for multi-placement
var multi_tile_anchor_index: int = 0  # Anchor tile index in selection

# Shared material settings (Single Source of Truth for preview and placed tiles)
var texture_filter_mode: int = GlobalConstants.DEFAULT_TEXTURE_FILTER  # BaseMaterial3D.TextureFilter enum
# REMOVED: _cached_shader - now managed by GlobalUtil.create_tile_material()

# Placement modes
enum PlacementMode {
	CURSOR_PLANE,  # Place on invisible planes through cursor
	CURSOR,        # Place only at exact cursor position (precision mode)
	RAYCAST,       # Click on existing surfaces to place tiles
}
var placement_mode: PlacementMode = PlacementMode.CURSOR_PLANE
var cursor_3d: TileCursor3D = null  # Reference to 3D cursor node

# Track all placed tiles: int tile_key -> TilePlacerData
# Key format: 64-bit integer packing grid position + orientation (see TileKeySystem)
var _placement_data: Dictionary = {}  # int (tile_key) -> TilePlacerData

# Painting mode state (Phase 5)
var _paint_stroke_undo_redo: EditorUndoRedoManager = null  # Reference to undo/redo manager during active paint stroke
var _paint_stroke_active: bool = false  # True when a paint stroke is in progress

#  Batch update system for MultiMesh GPU sync optimization
#   Use depth counter instead of boolean to handle nested batch operations
# This prevents state corruption when operations are interrupted or nested
var _batch_depth: int = 0  # 0 = immediate mode, >0 = batch mode (nested depth)
var _pending_chunk_updates: Dictionary = {}  # MultiMeshTileChunkBase -> bool (chunks needing GPU update)
var _pending_chunk_cleanups: Array[MultiMeshTileChunkBase] = []  # Chunks to remove after batch completes (empty chunks)

var _spatial_index: SpatialIndex = SpatialIndex.new()

## Get the placement data dictionary for external read access
## Used by AutotilePlacementExtension to look up neighbors
func get_placement_data() -> Dictionary:
	return _placement_data


## Updates texture filter mode and notifies all systems to refresh materials
func set_texture_filter(filter_mode: int) -> void:
	if filter_mode < 0 or filter_mode > 3:
		push_warning("Invalid texture filter mode: ", filter_mode)
		return

	texture_filter_mode = filter_mode
	# print("TilePlacementManager: Texture filter set to ", GlobalConstants.TEXTURE_FILTER_OPTIONS[filter_mode])

	# Update TileMapLayer3D material
	if tile_map_layer3d_root:
		tile_map_layer3d_root.texture_filter_mode = filter_mode
		tile_map_layer3d_root._update_material()

##  Begin batch update mode
## Defers GPU sync until end_batch_update() is called
## Use this for multi-tile operations (area fill, multi-placement, etc.)
##   Supports nesting - multiple begin calls require matching end calls
func begin_batch_update() -> void:
	_batch_depth += 1

	if _batch_depth == 1:
		# First level - clear pending updates and cleanups
		_pending_chunk_updates.clear()
		_pending_chunk_cleanups.clear()
		if GlobalConstants.DEBUG_BATCH_UPDATES:
			print("BEGIN BATCH (depth=%d) - Cleared pending updates and cleanups" % _batch_depth)
	else:
		if GlobalConstants.DEBUG_BATCH_UPDATES:
			print("BEGIN BATCH (depth=%d) - Nested call" % _batch_depth)

##  End batch update mode
## Flushes all pending chunk updates to GPU in a single operation
## Call this after a batch of tile placements/removals
##   Must be called exactly once for each begin_batch_update()
func end_batch_update() -> void:
	if _batch_depth <= 0:
		push_warning("end_batch_update() called without matching begin_batch_update() - STATE CORRUPTION DETECTED!")
		_batch_depth = 0  # Emergency reset
		return

	_batch_depth -= 1

	if GlobalConstants.DEBUG_BATCH_UPDATES:
		print("END BATCH (depth=%d) - %d chunks pending" % [_batch_depth, _pending_chunk_updates.size()])

	# Only flush when we reach depth 0 (all nested batches complete)
	if _batch_depth == 0:
		# Flush all pending chunk updates to GPU (one update per chunk)
		var chunks_updated: int = 0
		for chunk in _pending_chunk_updates:
			if is_instance_valid(chunk):
				chunk.multimesh = chunk.multimesh  # Triggers GPU sync
				chunks_updated += 1
			else:
				push_warning("Invalid chunk in pending updates - skipping")

		_pending_chunk_updates.clear()

		if GlobalConstants.DEBUG_BATCH_UPDATES:
			print("BATCH COMPLETE - Updated %d chunks to GPU" % chunks_updated)

		# Safety check: Warn if no chunks were updated (possible state corruption)
		if chunks_updated == 0 and _pending_chunk_updates.size() > 0:
			push_warning("Batch update completed but all chunks were invalid - possible memory corruption")

		# Process pending chunk cleanups (empty chunks marked for removal)
		#   Process cleanups AFTER GPU updates to avoid accessing freed chunks
		var chunks_removed: int = 0
		for chunk in _pending_chunk_cleanups:
			if is_instance_valid(chunk) and chunk.tile_count == 0:
				_cleanup_empty_chunk_internal(chunk)
				chunks_removed += 1

		_pending_chunk_cleanups.clear()

		if GlobalConstants.DEBUG_CHUNK_MANAGEMENT and chunks_removed > 0:
			print("BATCH CLEANUP - Removed %d empty chunks" % chunks_removed)

## DATA INTEGRITY: Validates consistency between all tile tracking data structures
## Checks _placement_data, chunk.tile_refs, chunk.instance_to_key, and _spatial_index
## @returns: Dictionary with validation results and error details
func _validate_data_structure_integrity() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var stats: Dictionary = {
		"placement_data_size": _placement_data.size(),
		"spatial_index_size": _spatial_index.size(),
		"total_chunk_refs": 0,
		"errors_found": 0,
		"warnings_found": 0
	}

	# Check 1: Every tile in _placement_data must exist in its chunk's tile_refs
	for tile_key in _placement_data:
		var tile_data: TilePlacerData = _placement_data[tile_key]
		var tile_ref: TileMapLayer3D.TileRef = tile_map_layer3d_root.get_tile_ref(tile_key)

		if not tile_ref:
			errors.append("Tile key %d exists in _placement_data but has no TileRef" % tile_key)
			continue

		# Get the chunk this tile should be in
		var chunk: MultiMeshTileChunkBase
		if tile_ref.mesh_mode == GlobalConstants.MeshMode.MESH_SQUARE:
			if tile_ref.chunk_index >= tile_map_layer3d_root._quad_chunks.size():
				errors.append("Tile key %d has invalid chunk_index %d (max=%d)" % [tile_key, tile_ref.chunk_index, tile_map_layer3d_root._quad_chunks.size() - 1])
				continue
			chunk = tile_map_layer3d_root._quad_chunks[tile_ref.chunk_index]
		else:
			if tile_ref.chunk_index >= tile_map_layer3d_root._triangle_chunks.size():
				errors.append("Tile key %d has invalid chunk_index %d (max=%d)" % [tile_key, tile_ref.chunk_index, tile_map_layer3d_root._triangle_chunks.size() - 1])
				continue
			chunk = tile_map_layer3d_root._triangle_chunks[tile_ref.chunk_index]

		# Check chunk.tile_refs contains this tile
		if not chunk.tile_refs.has(tile_key):
			errors.append("Tile key %d exists in _placement_data but NOT in chunk.tile_refs (chunk_index=%d)" % [tile_key, tile_ref.chunk_index])

	# Check 2: Every tile in chunk.tile_refs must exist in _placement_data
	var all_chunks: Array[MultiMeshTileChunkBase] = []
	all_chunks.append_array(tile_map_layer3d_root._quad_chunks)
	all_chunks.append_array(tile_map_layer3d_root._triangle_chunks)

	for chunk in all_chunks:
		if not is_instance_valid(chunk):
			continue

		stats.total_chunk_refs += chunk.tile_refs.size()

		for tile_key in chunk.tile_refs:
			if not _placement_data.has(tile_key):
				errors.append("Tile key %d exists in chunk.tile_refs but NOT in _placement_data" % tile_key)

			# Check instance_to_key bidirectional consistency
			var instance_index: int = chunk.tile_refs[tile_key]
			if not chunk.instance_to_key.has(instance_index):
				errors.append("Tile key %d has instance %d in tile_refs but NOT in instance_to_key" % [tile_key, instance_index])
			elif chunk.instance_to_key[instance_index] != tile_key:
				errors.append("Bidirectional mapping broken: tile_refs[%d]=%d but instance_to_key[%d]=%d" % [
					tile_key, instance_index, instance_index, chunk.instance_to_key[instance_index]
				])

	# Check 3: Spatial index consistency (warning level - can be rebuilt)
	for tile_key in _placement_data:
		# Spatial index uses bucket-based system, so we can't directly check membership
		# Just verify counts match approximately
		pass

	if _spatial_index.size() != _placement_data.size():
		warnings.append("Spatial index size (%d) doesn't match _placement_data size (%d) - may need rebuild" % [
			_spatial_index.size(), _placement_data.size()
		])

	# Check 4: Chunk index consistency ( for chunk system stability)
	stats["quad_chunks_count"] = tile_map_layer3d_root._quad_chunks.size()
	stats["triangle_chunks_count"] = tile_map_layer3d_root._triangle_chunks.size()
	stats["chunk_index_mismatches"] = 0

	# Validate quad chunks
	for i in range(tile_map_layer3d_root._quad_chunks.size()):
		var chunk: MultiMeshTileChunkBase = tile_map_layer3d_root._quad_chunks[i]
		if not is_instance_valid(chunk):
			errors.append("Quad chunk at array index %d is invalid (freed or null)" % i)
			continue

		#   Verify chunk_index matches array position
		if chunk.chunk_index != i:
			errors.append("Quad chunk index mismatch: array[%d] but chunk.chunk_index=%d" % [i, chunk.chunk_index])
			stats.chunk_index_mismatches += 1

		# Verify all TileRefs pointing to this chunk have correct index
		for tile_key in chunk.tile_refs.keys():
			var tile_ref: TileMapLayer3D.TileRef = tile_map_layer3d_root.get_tile_ref(tile_key)
			if tile_ref and tile_ref.chunk_index != i:
				errors.append("Tile key %d in quad chunk array[%d] but TileRef.chunk_index=%d" % [tile_key, i, tile_ref.chunk_index])

	# Validate triangle chunks
	for i in range(tile_map_layer3d_root._triangle_chunks.size()):
		var chunk: MultiMeshTileChunkBase = tile_map_layer3d_root._triangle_chunks[i]
		if not is_instance_valid(chunk):
			errors.append("Triangle chunk at array index %d is invalid (freed or null)" % i)
			continue

		#   Verify chunk_index matches array position
		if chunk.chunk_index != i:
			errors.append("Triangle chunk index mismatch: array[%d] but chunk.chunk_index=%d" % [i, chunk.chunk_index])
			stats.chunk_index_mismatches += 1

		# Verify all TileRefs pointing to this chunk have correct index
		for tile_key in chunk.tile_refs.keys():
			var tile_ref: TileMapLayer3D.TileRef = tile_map_layer3d_root.get_tile_ref(tile_key)
			if tile_ref and tile_ref.chunk_index != i:
				errors.append("Tile key %d in triangle chunk array[%d] but TileRef.chunk_index=%d" % [tile_key, i, tile_ref.chunk_index])

	# Check 5: Detect empty chunks (should have been cleaned up)
	var empty_chunks: int = 0
	for chunk in all_chunks:
		if is_instance_valid(chunk) and chunk.tile_count == 0:
			empty_chunks += 1
			warnings.append("Empty chunk detected: chunk_index=%d mesh_mode=%d (should be cleaned up)" % [chunk.chunk_index, chunk.mesh_mode_type])

	stats["empty_chunks_found"] = empty_chunks

	# Check 6: Detect orphaned TileRefs (point to invalid/removed chunks)
	var orphaned_refs: int = 0
	for tile_key in tile_map_layer3d_root._tile_lookup.keys():
		var tile_ref: TileMapLayer3D.TileRef = tile_map_layer3d_root._tile_lookup[tile_key]

		# Validate chunk_index is within valid range for its mesh mode
		if tile_ref.mesh_mode == GlobalConstants.MeshMode.MESH_SQUARE:
			if tile_ref.chunk_index < 0 or tile_ref.chunk_index >= tile_map_layer3d_root._quad_chunks.size():
				errors.append("ORPHANED: TileRef key=%d has invalid quad chunk_index=%d (valid range: 0-%d)" %
				              [tile_key, tile_ref.chunk_index, tile_map_layer3d_root._quad_chunks.size() - 1])
				orphaned_refs += 1
		else:  # MESH_TRIANGLE
			if tile_ref.chunk_index < 0 or tile_ref.chunk_index >= tile_map_layer3d_root._triangle_chunks.size():
				errors.append("ORPHANED: TileRef key=%d has invalid triangle chunk_index=%d (valid range: 0-%d)" %
				              [tile_key, tile_ref.chunk_index, tile_map_layer3d_root._triangle_chunks.size() - 1])
				orphaned_refs += 1

	stats["orphaned_refs_found"] = orphaned_refs

	if orphaned_refs > 0:
		errors.append("🔥   Found %d orphaned TileRefs - these point to removed/invalid chunks!" % orphaned_refs)

	# Compile results
	stats.errors_found = errors.size()
	stats.warnings_found = warnings.size()

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"stats": stats
	}

## Snaps a grid position to the current grid_snap_size
## UNIFIED SNAPPING METHOD (Single Source of Truth)
## Snaps grid coordinates with optional selective plane-based snapping
##
## Parameters:
##   grid_pos: Position in grid coordinates to snap
##   plane_normal: Optional plane normal for selective snapping (default = Vector3.ZERO)
##                 - Vector3.ZERO: Full-axis snapping (all 3 axes)
##                 - Vector3.UP/RIGHT/FORWARD: Only snap axes PARALLEL to plane
##   snap_size: Optional snap resolution (default = -1.0, uses grid_snap_size)
##
## Returns grid coordinates that can be fractional (0.0, 0.5, 1.0, 1.5...)
## Example: snap_size=1.0 snaps to 0.0, 1.0, 2.0... (integer grid)
## Example: snap_size=0.5 snaps to 0.0, 0.5, 1.0, 1.5... (half grid)
##
## Usage:
##   snap_to_grid(pos)                    → Full axis snapping (CURSOR mode)
##   snap_to_grid(pos, Vector3.UP)        → Selective XZ snapping (CURSOR_PLANE mode)
##   snap_to_grid(pos, Vector3.ZERO, 1.0) → Full axis with custom resolution
func snap_to_grid(grid_pos: Vector3, plane_normal: Vector3 = Vector3.ZERO, snap_size: float = -1.0) -> Vector3:
	# Use member variable if snap_size not explicitly provided
	var resolution: float = snap_size if snap_size > 0.0 else grid_snap_size

	# FULL-AXIS SNAPPING: If no plane specified (Vector3.ZERO), snap all axes
	if plane_normal == Vector3.ZERO:
		return Vector3(
			snappedf(grid_pos.x, resolution),
			snappedf(grid_pos.y, resolution),
			snappedf(grid_pos.z, resolution)
		)

	# SELECTIVE PLANE-BASED SNAPPING: Only snap axes PARALLEL to the plane
	# The perpendicular axis (plane normal) is NOT snapped - keeps cursor exact position
	var snapped: Vector3 = grid_pos

	if plane_normal == Vector3.UP:
		# XZ plane: Snap X and Z, keep Y from cursor
		snapped.x = snappedf(grid_pos.x, resolution)
		snapped.z = snappedf(grid_pos.z, resolution)
		# snapped.y stays unchanged (locked to cursor plane)
	elif plane_normal == Vector3.RIGHT:
		# YZ plane: Snap Y and Z, keep X from cursor
		snapped.y = snappedf(grid_pos.y, resolution)
		snapped.z = snappedf(grid_pos.z, resolution)
		# snapped.x stays unchanged (locked to cursor plane)
	else: # Vector3.FORWARD
		# XY plane: Snap X and Y, keep Z from cursor
		snapped.x = snappedf(grid_pos.x, resolution)
		snapped.y = snappedf(grid_pos.y, resolution)
		# snapped.z stays unchanged (locked to cursor plane)

	return snapped

## CONSOLIDATED CURSOR_PLANE CALCULATION (Single Source of Truth)
## This method encapsulates ALL the logic for CURSOR_PLANE mode:
## - Raycast to cursor planes
## - Auto-detect active plane from camera
## - Auto-detect orientation from plane and camera
## - Apply selective snapping (only parallel axes)
##
## Returns Dictionary with keys:
##   - "grid_pos": Vector3 (snapped grid position)
##   - "orientation": TileOrientation (auto-detected)
##   - "active_plane": Vector3 (plane normal for highlighting)
func calculate_cursor_plane_placement(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	if not cursor_3d:
		push_warning("calculate_cursor_plane_placement: No cursor_3d reference")
		return {}

	# Step 1: Raycast to cursor plane
	var raw_pos: Vector3 = _raycast_to_cursor_plane(camera, screen_pos)

	# Step 2: Auto-detect active plane from camera angle (using GlobalPlaneDetector)
	var active_plane: Vector3 = GlobalPlaneDetector.detect_active_plane_3d(camera)

	# Step 3: Auto-detect orientation from plane and camera (using GlobalPlaneDetector)
	var orientation: TileOrientation = GlobalPlaneDetector.detect_orientation_from_cursor_plane(active_plane, camera)

	# Step 4: Apply selective snapping (only snap parallel axes, NOT perpendicular)
	var grid_pos: Vector3 = snap_to_grid(raw_pos, active_plane)

	# Return all computed values
	return {
		"grid_pos": grid_pos,
		"orientation": orientation,
		"active_plane": active_plane
	}

## Calculates 3D world-space position without plane constraint
## Used for area erase selection to allow true 3D volume selection across all planes
## Unlike calculate_cursor_plane_placement(), this does NOT lock to the active cursor plane
##
## Returns Dictionary with keys:
##   - "grid_pos": Vector3 (3D position in grid coordinates)
##
## Use Case: Area erase - allows selection box to span floor, walls, ceiling simultaneously
func calculate_3d_world_position(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	if not cursor_3d:
		push_warning("calculate_3d_world_position: No cursor_3d reference")
		return {}

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	# Problem: Using camera.distance_to(cursor) causes selection box to "float" upward
	# as mouse moves, because ray direction changes but distance stays constant
	# Solution: Intersect ray with cursor's active PLANE at consistent depth
	var cursor_world_pos: Vector3 = cursor_3d.get_world_position()
	var plane_normal: Vector3 = cursor_3d.get_plane_normal()

	# Ray-plane intersection formula: t = (plane_point - ray_origin).dot(plane_normal) / ray_dir.dot(plane_normal)
	var denominator: float = ray_dir.dot(plane_normal)

	# Safety check: If ray is parallel to plane (denominator ≈ 0), fallback to 3D distance
	var world_pos: Vector3
	if abs(denominator) < 0.0001:
		# Ray parallel to plane - use old method as fallback
		var camera_to_cursor_dist: float = camera.global_position.distance_to(cursor_world_pos)
		world_pos = ray_origin + ray_dir * camera_to_cursor_dist
		push_warning("calculate_3d_world_position: Ray parallel to cursor plane, using fallback")
	else:
		# Normal case: Ray-plane intersection
		var t: float = (cursor_world_pos - ray_origin).dot(plane_normal) / denominator
		world_pos = ray_origin + ray_dir * t

	# Convert world position to grid coordinates (same as _raycast_to_cursor_plane)
	# Subtract GRID_ALIGNMENT_OFFSET because plane was offset in plane-locked mode
	var grid_pos: Vector3 = (world_pos / grid_size) - GlobalConstants.GRID_ALIGNMENT_OFFSET

	return {"grid_pos": grid_pos}

## Handles tile placement at mouse position or cursor position with undo/redo
func handle_placement_with_undo(
	camera: Camera3D,
	screen_pos: Vector2,
	undo_redo: EditorUndoRedoManager
) -> void:
	if not tile_map_layer3d_root or not tileset_texture or not current_tile_uv.has_area():
		push_warning("Cannot place tile: missing configuration")
		return

	var grid_pos: Vector3
	var placement_orientation: TileOrientation = GlobalPlaneDetector.current_orientation_18d

	# Determine placement position based on mode
	if placement_mode == PlacementMode.CURSOR_PLANE:
		# CURSOR_PLANE mode: Use consolidated calculation (Single Source of Truth)
		var result: Dictionary = calculate_cursor_plane_placement(camera, screen_pos)
		if result.is_empty():
			return
		grid_pos = result.grid_pos
		placement_orientation = result.orientation

	# Check if tile already exists at this position+orientation
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, placement_orientation)
	if _placement_data.has(tile_key):
		_replace_tile_with_undo(tile_key, grid_pos, placement_orientation, undo_redo)
	else:
		_place_new_tile_with_undo(tile_key, grid_pos, placement_orientation, undo_redo)

## Handles tile erasure with undo/redo
## Supports both single-tile erase and box erase modes
func handle_erase_with_undo(
	camera: Camera3D,
	screen_pos: Vector2,
	undo_redo: EditorUndoRedoManager
) -> void:
	if not tile_map_layer3d_root:
		return

	var grid_pos: Vector3  # Support fractional grid positions
	var erase_orientation: int = GlobalPlaneDetector.current_orientation_18d  # Default to current orientation

	# Determine erase position based on mode
	if placement_mode == PlacementMode.CURSOR_PLANE:
		# CURSOR_PLANE mode: Use consolidated calculation (Single Source of Truth)
		var result: Dictionary = calculate_cursor_plane_placement(camera, screen_pos)
		if result.is_empty():
			return
		grid_pos = result.grid_pos
		erase_orientation = result.orientation

	# Single-tile erase mode
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, erase_orientation)
	if _placement_data.has(tile_key):
		_erase_tile_with_undo(tile_key, grid_pos, erase_orientation, undo_redo)

## Finds intersection with cursor planes (CURSOR_PLANE mode)
## Raycasts to the active cursor plane (CURSOR_PLANE mode)
## Returns grid position where the ray intersects the active cursor plane
func _raycast_to_cursor_plane(camera: Camera3D, screen_pos: Vector2) -> Vector3:
	if not cursor_3d:
		return Vector3.ZERO

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	var cursor_world_pos: Vector3 = cursor_3d.get_world_position()

	# Camera angle determines which plane is active (using GlobalPlaneDetector)
	var active_plane_normal: Vector3 = GlobalPlaneDetector.detect_active_plane_3d(camera)

	# Define only the active plane
	# Apply grid alignment offset so plane aligns with where tiles actually appear
	var plane_normal: Vector3 = active_plane_normal
	var plane_point: Vector3 = cursor_world_pos - (GlobalConstants.GRID_ALIGNMENT_OFFSET * grid_size)
	# var plane_point: Vector3 = cursor_world_pos

	# Calculate intersection using plane equation
	var denom: float = ray_dir.dot(plane_normal)

	# Check if ray is parallel to plane
	if abs(denom) < GlobalConstants.PARALLEL_PLANE_THRESHOLD:
		return cursor_3d.grid_position

	# Calculate intersection distance
	var t: float = (plane_point - ray_origin).dot(plane_normal) / denom

	# Check if intersection is behind camera
	if t < 0:
		return cursor_3d.grid_position

	# Calculate intersection point
	var intersection: Vector3 = ray_origin + ray_dir * t

	# Apply canvas bounds
	var cursor_grid: Vector3 = cursor_3d.grid_position
	var constrained_intersection: Vector3 = _apply_canvas_bounds(
		intersection,
		plane_normal,
		cursor_world_pos,
		cursor_grid
	)

	# NO SNAPPING - return fractional position directly as grid coordinates
	# Convert world position to grid position by dividing by grid_size
	# Subtract GRID_ALIGNMENT_OFFSET because the plane was offset (prevents double-offset when tile placement adds it back)
	return (constrained_intersection / grid_size) - GlobalConstants.GRID_ALIGNMENT_OFFSET

## Applies canvas bounds to an intersection point 
## Locks one axis to cursor position and constrains the other two axes within max_canvas_distance
## This creates a bounded "canvas" area around the cursor for placement
##
## Parameters:
##   intersection: World position of ray intersection with plane
##   plane_normal: Normal of the active plane (UP, RIGHT, or FORWARD)
##   cursor_world_pos: World position of the 3D cursor
##   cursor_grid_pos: Grid position of the 3D cursor
##
## Returns: Constrained world position within canvas bounds
func _apply_canvas_bounds(intersection: Vector3, plane_normal: Vector3, cursor_world_pos: Vector3, cursor_grid_pos: Vector3) -> Vector3:
	var constrained: Vector3 = intersection
	var max_distance: float = GlobalConstants.MAX_CANVAS_DISTANCE

	if plane_normal == Vector3.UP:
		# XZ plane (horizontal): Lock Y to cursor level, bound X and Z
		constrained.y = cursor_world_pos.y

		var max_x: float = (cursor_grid_pos.x + max_distance) * grid_size
		var min_x: float = (cursor_grid_pos.x - max_distance) * grid_size
		var max_z: float = (cursor_grid_pos.z + max_distance) * grid_size
		var min_z: float = (cursor_grid_pos.z - max_distance) * grid_size

		constrained.x = clampf(constrained.x, min_x, max_x)
		constrained.z = clampf(constrained.z, min_z, max_z)

	elif plane_normal == Vector3.RIGHT:
		# YZ plane (vertical, perpendicular to X): Lock X to cursor level, bound Y and Z
		constrained.x = cursor_world_pos.x

		var max_y: float = (cursor_grid_pos.y + max_distance) * grid_size
		var min_y: float = (cursor_grid_pos.y - max_distance) * grid_size
		var max_z: float = (cursor_grid_pos.z + max_distance) * grid_size
		var min_z: float = (cursor_grid_pos.z - max_distance) * grid_size

		constrained.y = clampf(constrained.y, min_y, max_y)
		constrained.z = clampf(constrained.z, min_z, max_z)

	else: # Vector3.FORWARD
		# XY plane (vertical, perpendicular to Z): Lock Z to cursor level, bound X and Y
		constrained.z = cursor_world_pos.z

		var max_x: float = (cursor_grid_pos.x + max_distance) * grid_size
		var min_x: float = (cursor_grid_pos.x - max_distance) * grid_size
		var max_y: float = (cursor_grid_pos.y + max_distance) * grid_size
		var min_y: float = (cursor_grid_pos.y - max_distance) * grid_size

		constrained.x = clampf(constrained.x, min_x, max_x)
		constrained.y = clampf(constrained.y, min_y, max_y)

	return constrained


# ==============================================================================
# REMOVED: Plane detection and tilt management methods moved to GlobalPlaneDetector
# ==============================================================================
# The following methods have been moved to the GlobalPlaneDetector singleton:
# - get_orientation_from_cursor_plane() → GlobalPlaneDetector.detect_orientation_from_cursor_plane()
# - cycle_tilt_forward() → GlobalPlaneDetector.cycle_tilt_forward()
# - cycle_tilt_backward() → GlobalPlaneDetector.cycle_tilt_backward()
# - reset_to_flat() → GlobalPlaneDetector.reset_to_flat()
# - _get_tilt_sequence_for_orientation() → GlobalPlaneDetector._get_tilt_sequence_for_orientation()
# - _get_base_orientation() → GlobalPlaneDetector._get_base_orientation()
# - _debug_tilt_state() → GlobalPlaneDetector._debug_tilt_state()
# - _get_orientation_name() → GlobalPlaneDetector.get_orientation_name()


## Adds a tile to the unified MultiMesh chunk system
## Uses chunk-based system (1000 tiles per chunk) with absolute grid positioning
## Supports fractional grid positions
## @param tile_key_override: Optional tile_key to use instead of generating from grid_pos + orientation
##                            for replace operations to maintain key consistency
func _add_tile_to_multimesh(
	grid_pos: Vector3,
	uv_rect: Rect2,
	orientation: TileOrientation = TileOrientation.FLOOR,
	mesh_rotation: int = 0,
	is_face_flipped: bool = false,
	tile_key_override: int = -1
) -> TileMapLayer3D.TileRef:
	# Get current mesh mode from the TileMapLayer3D node
	var mesh_mode: GlobalConstants.MeshMode = tile_map_layer3d_root.current_mesh_mode

	# Get or create a chunk with available space based on mesh mode
	var chunk: MultiMeshTileChunkBase = tile_map_layer3d_root.get_or_create_chunk(mesh_mode)

	# Get next available instance index within this chunk
	var instance_index: int = chunk.multimesh.visible_instance_count

	# Build transform using SINGLE SOURCE OF TRUTH (GlobalUtil.build_tile_transform)
	var transform: Transform3D = GlobalUtil.build_tile_transform(
		grid_pos, orientation, mesh_rotation, grid_size, tile_map_layer3d_root, is_face_flipped
	)
	chunk.multimesh.set_instance_transform(instance_index, transform)

	# Set instance custom data (UV rect for shader)
	var atlas_size: Vector2 = tileset_texture.get_size()
	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
	var custom_data: Color = uv_data.uv_color
	chunk.multimesh.set_instance_custom_data(instance_index, custom_data)

	# Make this instance visible
	chunk.multimesh.visible_instance_count = instance_index + 1
	chunk.tile_count += 1

	#   Use override key if provided (replace operation), otherwise generate from position
	# This prevents key mismatch when replacing tiles where grid_pos or orientation changes
	var tile_key: int = tile_key_override if tile_key_override != -1 else GlobalUtil.make_tile_key(grid_pos, orientation)
	chunk.tile_refs[tile_key] = instance_index

	#  Maintain reverse lookup for O(1) tile removal
	chunk.instance_to_key[instance_index] = tile_key

	# Create and store TileRef in the global lookup
	var tile_ref: TileMapLayer3D.TileRef = TileMapLayer3D.TileRef.new()

	#  Use pre-stored chunk_index instead of O(N) Array.find()
	tile_ref.chunk_index = chunk.chunk_index

	tile_ref.instance_index = instance_index
	tile_ref.uv_rect = uv_rect
	tile_ref.mesh_mode = mesh_mode  # Store the mesh mode
	
	tile_map_layer3d_root.add_tile_ref(tile_key, tile_ref)

	#  Defer GPU update if in batch mode, otherwise update immediately
	if chunk:
		if _batch_depth > 0:
			_pending_chunk_updates[chunk] = true  # Mark chunk for deferred update
		else:
			chunk.multimesh = chunk.multimesh  # Immediate GPU sync (single tile mode)

	return tile_ref

## Removes a tile from its MultiMesh chunk (unified system)
func _remove_tile_from_multimesh(tile_key: int) -> void:
	var tile_ref: TileMapLayer3D.TileRef = tile_map_layer3d_root.get_tile_ref(tile_key)

	if not tile_ref:
		push_warning("Attempted to remove tile that doesn't exist with key ", tile_key)
		return

	#   Get chunk from appropriate array with BOUNDS CHECKING
	# Prevents crash from orphaned TileRefs (pointing to removed chunks after cleanup)
	var chunk: MultiMeshTileChunkBase = null
	if tile_ref.mesh_mode == GlobalConstants.MeshMode.MESH_SQUARE:
		# Validate chunk_index before array access
		if tile_ref.chunk_index < 0 or tile_ref.chunk_index >= tile_map_layer3d_root._quad_chunks.size():
			push_error(" ORPHANED TILEREF: Tile key %d has invalid quad chunk_index %d (array size=%d) - cleaning up orphaned reference" %
			           [tile_key, tile_ref.chunk_index, tile_map_layer3d_root._quad_chunks.size()])
			# Clean up orphaned TileRef (likely from chunk that was removed during cleanup)
			tile_map_layer3d_root.remove_tile_ref(tile_key)
			_placement_data.erase(tile_key)
			_spatial_index.remove_tile(tile_key)
			return
		chunk = tile_map_layer3d_root._quad_chunks[tile_ref.chunk_index]
	else:  # MESH_TRIANGLE
		# Validate chunk_index before array access
		if tile_ref.chunk_index < 0 or tile_ref.chunk_index >= tile_map_layer3d_root._triangle_chunks.size():
			push_error(" ORPHANED TILEREF: Tile key %d has invalid triangle chunk_index %d (array size=%d) - cleaning up orphaned reference" %
			           [tile_key, tile_ref.chunk_index, tile_map_layer3d_root._triangle_chunks.size()])
			# Clean up orphaned TileRef (likely from chunk that was removed during cleanup)
			tile_map_layer3d_root.remove_tile_ref(tile_key)
			_placement_data.erase(tile_key)
			_spatial_index.remove_tile(tile_key)
			return
		chunk = tile_map_layer3d_root._triangle_chunks[tile_ref.chunk_index]

	# IMPORTANT: Use the CURRENT instance index from chunk's tile_refs, not the cached one in TileRef
	# The cached index becomes stale after swap-and-pop operations
	if not chunk.tile_refs.has(tile_key):
		# DATA CORRUPTION DETECTED: Tile exists in global ref but not in chunk's local tracking
		# This indicates a desync between _placement_data and chunk.tile_refs
		# Common causes: Replace operation key mismatch, interrupted batch operation
		push_error("DATA CORRUPTION: Tile key %d not found in chunk tile_refs (chunk_index=%d, mesh_mode=%d)" % [tile_key, tile_ref.chunk_index, tile_ref.mesh_mode])

		#  Try to find tile by brute force search through instance_to_key
		var found_instance: int = -1
		for instance_idx in chunk.instance_to_key:
			if chunk.instance_to_key[instance_idx] == tile_key:
				found_instance = instance_idx
				push_warning("  → Found tile by brute force at instance %d - rebuilding chunk.tile_refs entry" % instance_idx)
				chunk.tile_refs[tile_key] = instance_idx  # Rebuild the missing entry
				break

		# If still not found, clean up global data structures to prevent further corruption
		if found_instance == -1:
			push_error("  → Could not find tile in chunk - cleaning up global references")
			tile_map_layer3d_root.remove_tile_ref(tile_key)
			_placement_data.erase(tile_key)
			_spatial_index.remove_tile(tile_key)
			return

	var instance_index: int = chunk.tile_refs[tile_key]
	var last_visible_index: int = chunk.multimesh.visible_instance_count - 1

	# DEBUG: Uncomment for detailed removal tracing
	#print("REMOVE TRACE: tile_key=%s instance=%d last_visible=%d mesh_mode=%d" % [tile_key, instance_index, last_visible_index, tile_ref.mesh_mode])
	#print("BEFORE: visible_count=%d tile_count=%d tile_refs_size=%d instance_to_key_size=%d" % [
	#	chunk.multimesh.visible_instance_count, chunk.tile_count, chunk.tile_refs.size(), chunk.instance_to_key.size()
	#])

	# Swap-and-pop: move last visible instance to this index
	if instance_index < last_visible_index:
		# Safety check: ensure the last visible tile still exists in our lookup
		# (during multi-tile undo/erase, tiles may be removed in arbitrary order)
		if not chunk.instance_to_key.has(last_visible_index):
			# This is expected during batch operations - the last tile may have been removed already
			# Just skip the swap and continue with cleanup
			pass
		else:
			var last_transform: Transform3D = chunk.multimesh.get_instance_transform(last_visible_index)
			var last_custom_data: Color = chunk.multimesh.get_instance_custom_data(last_visible_index)

			chunk.multimesh.set_instance_transform(instance_index, last_transform)
			chunk.multimesh.set_instance_custom_data(instance_index, last_custom_data)

			#  Use reverse lookup for O(1) access instead of O(N) search
			var swapped_tile_key: int = chunk.instance_to_key[last_visible_index]

			# Update both forward and reverse lookups for the swapped tile
			chunk.tile_refs[swapped_tile_key] = instance_index
			chunk.instance_to_key[instance_index] = swapped_tile_key
			chunk.instance_to_key.erase(last_visible_index)

			# Update the global tile reference
			var swapped_ref: TileMapLayer3D.TileRef = tile_map_layer3d_root.get_tile_ref(swapped_tile_key)
			if swapped_ref:
				swapped_ref.instance_index = instance_index
				#print("SWAP DONE: tile '%s' now at instance %d" % [swapped_tile_key, instance_index])
			else:
				push_warning("TilePlacementManager: Swapped tile ref not found for key: ", swapped_tile_key)

	# Decrement visible count (hides the last visible instance)
	chunk.multimesh.visible_instance_count -= 1
	chunk.tile_count -= 1
	chunk.tile_refs.erase(tile_key)

	# If a swap occurred, instance_to_key[instance_index] was already updated to point to the swapped tile
	# Erasing it here would destroy that mapping and cause corruption
	if instance_index == last_visible_index:
		chunk.instance_to_key.erase(instance_index)

	#print("AFTER: visible_count=%d tile_count=%d tile_refs_size=%d instance_to_key_size=%d" % [
	#	chunk.multimesh.visible_instance_count, chunk.tile_count, chunk.tile_refs.size(), chunk.instance_to_key.size()
	#])

	tile_map_layer3d_root.remove_tile_ref(tile_key)

	#  Defer GPU update if in batch mode, otherwise update immediately
	if chunk:
		if _batch_depth > 0:
			_pending_chunk_updates[chunk] = true  # Mark chunk for deferred update
		else:
			#print("FORCING VISUAL REFRESH: Reassigning multimesh to multimesh_instance")
			chunk.multimesh = chunk.multimesh  # Immediate GPU sync (single tile mode)
			#print("  VISUAL REFRESH DONE")

	# Check if chunk is now empty and schedule cleanup
	#   Defer cleanup during batch mode to avoid chunk index corruption mid-operation
	if chunk.tile_count == 0:
		if _batch_depth > 0:
			# Batch mode: Schedule cleanup for end_batch_update()
			if not _pending_chunk_cleanups.has(chunk):
				_pending_chunk_cleanups.append(chunk)
				if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
					print("Chunk empty (batch mode) - scheduled for cleanup: chunk_index=%d mesh_mode=%d" % [chunk.chunk_index, tile_ref.mesh_mode])
		else:
			# Immediate mode: Clean up now
			_cleanup_empty_chunk_internal(chunk)

##   Removes empty chunk from chunk array and reindexes remaining chunks
## Called when a chunk becomes empty (tile_count == 0) to prevent array gaps
## Must reindex ALL remaining chunks to fix chunk_index corruption
## @param chunk: The empty chunk to remove (must have tile_count == 0)
func _cleanup_empty_chunk_internal(chunk: MultiMeshTileChunkBase) -> void:
	if chunk.tile_count != 0:
		push_warning("Attempted to cleanup non-empty chunk (tile_count=%d)" % chunk.tile_count)
		return

	# Determine mesh mode from chunk type
	var mesh_mode: GlobalConstants.MeshMode = chunk.mesh_mode_type

	#   Find chunk's current array index BEFORE removal
	# Need this to identify orphaned TileRefs pointing to this chunk
	var chunk_array_index: int = -1
	if mesh_mode == GlobalConstants.MeshMode.MESH_SQUARE:
		chunk_array_index = tile_map_layer3d_root._quad_chunks.find(chunk)
	else:
		chunk_array_index = tile_map_layer3d_root._triangle_chunks.find(chunk)

	if chunk_array_index == -1:
		push_warning("Chunk not found in array during cleanup - cannot proceed safely")
		return

	#   Clean up ALL orphaned TileRefs pointing to this chunk BEFORE removing it
	# Even if chunk.tile_count == 0, orphaned TileRefs may still exist in _tile_lookup
	# This happens when tiles were removed but TileRefs weren't cleaned up properly
	var orphaned_keys: Array[int] = []
	for tile_key in tile_map_layer3d_root._tile_lookup.keys():
		var tile_ref: TileMapLayer3D.TileRef = tile_map_layer3d_root._tile_lookup[tile_key]
		# Check if this TileRef points to the chunk we're about to remove
		if tile_ref.mesh_mode == mesh_mode and tile_ref.chunk_index == chunk_array_index:
			orphaned_keys.append(tile_key)

	# Remove all orphaned TileRefs found
	for tile_key in orphaned_keys:
		if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
			print("Cleaning orphaned TileRef: tile_key=%d (pointed to chunk being removed)" % tile_key)
		tile_map_layer3d_root.remove_tile_ref(tile_key)
		_placement_data.erase(tile_key)
		_spatial_index.remove_tile(tile_key)

	if orphaned_keys.size() > 0:
		push_warning(" Cleaned up %d orphaned TileRefs during chunk removal (chunk_index=%d)" % [orphaned_keys.size(), chunk_array_index])

	if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
		print("Removing empty chunk: chunk_index=%d mesh_mode=%d name=%s" % [chunk.chunk_index, mesh_mode, chunk.name])

	# Remove from appropriate chunk array
	if mesh_mode == GlobalConstants.MeshMode.MESH_SQUARE:
		var idx: int = tile_map_layer3d_root._quad_chunks.find(chunk)
		if idx != -1:
			tile_map_layer3d_root._quad_chunks.remove_at(idx)
			if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
				print("  → Removed from _quad_chunks at index %d (%d quad chunks remaining)" % [idx, tile_map_layer3d_root._quad_chunks.size()])
		else:
			push_warning("Empty quad chunk not found in _quad_chunks array")
	else:  # MESH_TRIANGLE
		var idx: int = tile_map_layer3d_root._triangle_chunks.find(chunk)
		if idx != -1:
			tile_map_layer3d_root._triangle_chunks.remove_at(idx)
			if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
				print("  → Removed from _triangle_chunks at index %d (%d triangle chunks remaining)" % [idx, tile_map_layer3d_root._triangle_chunks.size()])
		else:
			push_warning("Empty triangle chunk not found in _triangle_chunks array")

	# Free the chunk node
	if chunk.get_parent():
		chunk.get_parent().remove_child(chunk)
	chunk.queue_free()

	#   Reindex remaining chunks to fix chunk_index values
	# Without this, tile_ref.chunk_index will point to wrong array positions
	tile_map_layer3d_root.reindex_chunks()

	if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
		print("Chunk cleanup complete - reindexing done")

## Places new tile with undo/redo
func _place_new_tile_with_undo(tile_key: int, grid_pos: Vector3, orientation: TileOrientation, undo_redo: EditorUndoRedoManager) -> void:
	#   Create separate tile data for undo/redo to prevent object pool corruption
	# DO NOT reuse the same instance - undo system needs independent copies
	var tile_data: TilePlacerData = TileDataPool.acquire()  #  Use object pool
	tile_data.uv_rect = current_tile_uv
	tile_data.grid_position = grid_pos
	tile_data.orientation = orientation
	tile_data.mesh_rotation = current_mesh_rotation  # Store rotation state
	tile_data.is_face_flipped = is_current_face_flipped  # Store flip state (F key)
	tile_data.mesh_mode = tile_map_layer3d_root.current_mesh_mode

	undo_redo.create_action("Place Tile")
	undo_redo.add_do_method(self, "_do_place_tile", tile_key, grid_pos, current_tile_uv, orientation, current_mesh_rotation, tile_data)
	undo_redo.add_undo_method(self, "_undo_place_tile", tile_key)
	undo_redo.commit_action()

func _do_place_tile(tile_key: int, grid_pos: Vector3, uv_rect: Rect2, orientation: TileOrientation, mesh_rotation: int, data: TilePlacerData) -> void:
	# If tile already exists at this position, remove it first (prevents visual overlay)
	if _placement_data.has(tile_key):
		_remove_tile_from_multimesh(tile_key)

	# Preserve flip state and mesh mode if data was provided
	# Without this, triangle tiles get saved with mesh_mode=0 (squares) instead of 1 (triangles)
	var preserved_flip: bool = false
	var preserved_mode: int = tile_map_layer3d_root.current_mesh_mode
	if data:
		preserved_flip = data.is_face_flipped
		preserved_mode = data.mesh_mode

	# Always create fresh TilePlacerData to avoid Resource read-only errors
	# (Resources created with .new() in undo operations can't have non-@export properties assigned)
	var fresh_data: TilePlacerData = TileDataPool.acquire()  #  Use object pool
	fresh_data.uv_rect = uv_rect
	fresh_data.grid_position = grid_pos
	fresh_data.orientation = orientation
	fresh_data.mesh_rotation = mesh_rotation
	fresh_data.mesh_mode = preserved_mode
	fresh_data.is_face_flipped = preserved_flip

	# Without this, undo operations create NEW keys, causing chunk_index=-1 corruption
	var tile_ref = _add_tile_to_multimesh(grid_pos, uv_rect, orientation, mesh_rotation, preserved_flip, tile_key)
	fresh_data.multimesh_instance_index = tile_ref.instance_index

	_placement_data[tile_key] = fresh_data
	tile_map_layer3d_root.save_tile_data(fresh_data)

	#  Update spatial index for fast area queries
	_spatial_index.add_tile(tile_key, grid_pos)


func _undo_place_tile(tile_key: int) -> void:
	if _placement_data.has(tile_key):
		# NOTE: DO NOT release tile_data here - it's still referenced by undo/redo for potential redo
		# The data will be reused when redo is called with _do_place_tile()
		_remove_tile_from_multimesh(tile_key)
		_placement_data.erase(tile_key)

		# Remove from persistent storage
		tile_map_layer3d_root.remove_saved_tile_data(tile_key)


## Replaces existing tile with undo/redo
func _replace_tile_with_undo(tile_key: int, grid_pos: Vector3, orientation: TileOrientation, undo_redo: EditorUndoRedoManager) -> void:
	var existing_tile: TilePlacerData = _placement_data[tile_key]

	#   Create COPIES for both do and undo - cannot reuse instances that will be released
	var old_tile_copy: TilePlacerData = TileDataPool.acquire()
	old_tile_copy.uv_rect = existing_tile.uv_rect
	old_tile_copy.grid_position = existing_tile.grid_position
	old_tile_copy.orientation = existing_tile.orientation
	old_tile_copy.mesh_rotation = existing_tile.mesh_rotation
	old_tile_copy.is_face_flipped = existing_tile.is_face_flipped
	old_tile_copy.mesh_mode = existing_tile.mesh_mode

	var new_tile_data: TilePlacerData = TileDataPool.acquire()
	new_tile_data.uv_rect = current_tile_uv
	new_tile_data.grid_position = grid_pos
	new_tile_data.orientation = orientation
	new_tile_data.mesh_rotation = current_mesh_rotation
	new_tile_data.is_face_flipped = is_current_face_flipped
	new_tile_data.mesh_mode = tile_map_layer3d_root.current_mesh_mode

	undo_redo.create_action("Replace Tile")
	undo_redo.add_do_method(self, "_do_replace_tile", tile_key, grid_pos, new_tile_data.uv_rect, new_tile_data.orientation, new_tile_data.mesh_rotation, new_tile_data)
	undo_redo.add_undo_method(self, "_do_replace_tile", tile_key, grid_pos, old_tile_copy.uv_rect, old_tile_copy.orientation, old_tile_copy.mesh_rotation, old_tile_copy)
	undo_redo.commit_action()

func _do_replace_tile(tile_key: int, grid_pos: Vector3, new_uv_rect: Rect2, new_orientation: TileOrientation, new_rotation: int, new_data: TilePlacerData) -> void:
	# NOTE: DO NOT release old tile_data here - it's still referenced by undo/redo
	# The data will be reused when undo is called

	# Remove old tile (unified system doesn't need UV for removal)
	if _placement_data.has(tile_key):
		_remove_tile_from_multimesh(tile_key)

	# Without this, _add_tile_to_multimesh generates a NEW key from grid_pos + orientation,
	# causing mismatch between _placement_data (old key) and chunk.tile_refs (new key)
	var tile_ref: TileMapLayer3D.TileRef = _add_tile_to_multimesh(
		grid_pos, new_uv_rect, new_orientation, new_rotation, new_data.is_face_flipped, tile_key
	)
	# Note: multimesh_instance_index is managed by TileRef in the unified system
	_placement_data[tile_key] = new_data

	# Update spatial index (position may have changed)
	_spatial_index.remove_tile(tile_key)
	_spatial_index.add_tile(tile_key, grid_pos)

	# Save to persistent storage (replaces old data)
	tile_map_layer3d_root.save_tile_data(new_data)


## Erases tile with undo/redo
func _erase_tile_with_undo(tile_key: int, grid_pos: Vector3, orientation: TileOrientation, undo_redo: EditorUndoRedoManager) -> void:
	var existing_tile: TilePlacerData = _placement_data[tile_key]

	#   Create a COPY for undo - cannot reuse the instance that will be released
	var tile_data_copy: TilePlacerData = TileDataPool.acquire()
	tile_data_copy.uv_rect = existing_tile.uv_rect
	tile_data_copy.grid_position = existing_tile.grid_position
	tile_data_copy.orientation = existing_tile.orientation
	tile_data_copy.mesh_rotation = existing_tile.mesh_rotation
	tile_data_copy.is_face_flipped = existing_tile.is_face_flipped
	tile_data_copy.mesh_mode = existing_tile.mesh_mode

	undo_redo.create_action("Erase Tile")
	undo_redo.add_do_method(self, "_do_erase_tile", tile_key)
	undo_redo.add_undo_method(self, "_do_place_tile", tile_key, grid_pos, tile_data_copy.uv_rect, orientation, tile_data_copy.mesh_rotation, tile_data_copy)
	undo_redo.commit_action()

func _do_erase_tile(tile_key: int) -> void:
	if _placement_data.has(tile_key):
		#  Release tile data back to object pool
		var tile_data: TilePlacerData = _placement_data[tile_key]
		TileDataPool.release(tile_data)

		_remove_tile_from_multimesh(tile_key)
		_placement_data.erase(tile_key)

		# Remove from persistent storage
		tile_map_layer3d_root.remove_saved_tile_data(tile_key)

		#  Update spatial index for fast area queries
		_spatial_index.remove_tile(tile_key)


## Handles multi-tile placement with undo/redo (Phase 4)
## Places all tiles in multi_tile_selection at calculated positions relative to anchor
func handle_multi_placement_with_undo(
	camera: Camera3D,
	screen_pos: Vector2,
	undo_redo: EditorUndoRedoManager
) -> void:
	if not tile_map_layer3d_root or multi_tile_selection.is_empty():
		return

	var anchor_grid_pos: Vector3
	var placement_orientation: int = GlobalPlaneDetector.current_orientation_18d

	# Determine anchor position based on placement mode (same as single-tile placement)
	if placement_mode == PlacementMode.CURSOR_PLANE:
		var result: Dictionary = calculate_cursor_plane_placement(camera, screen_pos)
		if result.is_empty():
			return
		anchor_grid_pos = result.grid_pos
		placement_orientation = result.orientation

	# elif placement_mode == PlacementMode.CURSOR:
	# 	if not cursor_3d:
	# 		return
	# 	anchor_grid_pos = cursor_3d.grid_position

	# else: # PlacementMode.RAYCAST
	# 	var ray_result: Dictionary = _raycast_to_geometry(camera, screen_pos)
	# 	if ray_result.is_empty():
	# 		return
	# 	var world_pos: Vector3 = ray_result.position
	# 	var grid_coords: Vector3 = GlobalUtil.world_to_grid(world_pos, grid_size)
	# 	anchor_grid_pos = snap_to_grid(grid_coords)

	# Place all tiles with undo/redo
	_place_multi_tiles_with_undo(anchor_grid_pos, placement_orientation, undo_redo)

## Creates undo action for placing all tiles in selection
func _place_multi_tiles_with_undo(anchor_grid_pos: Vector3, orientation: TileOrientation, undo_redo: EditorUndoRedoManager) -> void:
	if multi_tile_selection.is_empty():
		return

	# Calculate all tile positions and data
	var tiles_to_place: Array[Dictionary] = []

	# Get anchor tile (first in selection)
	var anchor_uv_rect: Rect2 = multi_tile_selection[0]
	var anchor_pixel_pos: Vector2 = anchor_uv_rect.position
	var tile_pixel_size: Vector2 = anchor_uv_rect.size
	var atlas_size: Vector2 = tileset_texture.get_size()

	# Calculate position for each tile relative to anchor
	for i in range(multi_tile_selection.size()):
		var tile_uv_rect: Rect2 = multi_tile_selection[i]
		var tile_pixel_pos: Vector2 = tile_uv_rect.position

		# Calculate pixel offset from anchor
		var pixel_offset: Vector2 = tile_pixel_pos - anchor_pixel_pos

		# Convert to grid offset (in tiles)
		var grid_offset: Vector2 = pixel_offset / tile_pixel_size

		# Calculate 3D offset (same logic as tile_preview_3d.gd)
		# Atlas X → Local X, Atlas Y → Local Z
		var local_offset: Vector3 = Vector3(grid_offset.x, 0, grid_offset.y)

		# Calculate final grid position for this tile
		# Note: This offset is in LOCAL space before orientation is applied
		# We need to rotate it based on orientation to get proper world offset
		var world_offset: Vector3 = _transform_local_offset_to_world(local_offset, orientation, current_mesh_rotation)
		var tile_grid_pos: Vector3 = anchor_grid_pos + world_offset

		# Create tile key
		var tile_key: int = GlobalUtil.make_tile_key(tile_grid_pos, orientation)

		# Store tile info
		tiles_to_place.append({
			"tile_key": tile_key,
			"grid_pos": tile_grid_pos,
			"uv_rect": tile_uv_rect,
			"orientation": orientation,
			"mesh_rotation": current_mesh_rotation,
			"is_replacement": _placement_data.has(tile_key)
		})

	# Create single undo action for entire group
	undo_redo.create_action("Place Multi-Tiles (%d tiles)" % tiles_to_place.size())

	# Add do/undo methods for each tile
	for tile_info in tiles_to_place:
		if tile_info.is_replacement:
			# Tile already exists - need to create COPIES for both do and undo
			var existing_tile: TilePlacerData = _placement_data[tile_info.tile_key]

			#   Create a COPY of old data - cannot reuse instance that will be released
			var old_data_copy: TilePlacerData = TileDataPool.acquire()
			old_data_copy.uv_rect = existing_tile.uv_rect
			old_data_copy.grid_position = existing_tile.grid_position
			old_data_copy.orientation = existing_tile.orientation
			old_data_copy.mesh_rotation = existing_tile.mesh_rotation
			old_data_copy.is_face_flipped = existing_tile.is_face_flipped
			old_data_copy.mesh_mode = existing_tile.mesh_mode

			var new_data: TilePlacerData = TileDataPool.acquire()  #  Use object pool
			new_data.uv_rect = tile_info.uv_rect
			new_data.grid_position = tile_info.grid_pos
			new_data.orientation = tile_info.orientation
			new_data.mesh_rotation = tile_info.mesh_rotation
			new_data.is_face_flipped = is_current_face_flipped
			new_data.mesh_mode = tile_map_layer3d_root.current_mesh_mode

			undo_redo.add_do_method(self, "_do_replace_tile", tile_info.tile_key, tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation, new_data)
			undo_redo.add_undo_method(self, "_do_replace_tile", tile_info.tile_key, tile_info.grid_pos, old_data_copy.uv_rect, old_data_copy.orientation, old_data_copy.mesh_rotation, old_data_copy)
		else:
			# New tile placement
			var tile_data: TilePlacerData = TileDataPool.acquire()  #  Use object pool
			tile_data.uv_rect = tile_info.uv_rect
			tile_data.grid_position = tile_info.grid_pos
			tile_data.orientation = tile_info.orientation
			tile_data.mesh_rotation = tile_info.mesh_rotation
			tile_data.is_face_flipped = is_current_face_flipped  # All tiles in stamp use current flip state
			tile_data.mesh_mode = tile_map_layer3d_root.current_mesh_mode

			undo_redo.add_do_method(self, "_do_place_tile", tile_info.tile_key, tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation, tile_data)
			undo_redo.add_undo_method(self, "_undo_place_tile", tile_info.tile_key)

	#  Batch all MultiMesh updates into single GPU sync
	begin_batch_update()
	undo_redo.commit_action()
	end_batch_update()

## Transforms local offset (from preview calculation) to world offset based on orientation and rotation
## This is necessary because the preview uses parent basis rotation, but here we need to calculate
## each tile's absolute grid position
func _transform_local_offset_to_world(local_offset: Vector3, orientation: TileOrientation, mesh_rotation: int) -> Vector3:
	# Create the same basis that would be applied to the parent preview node
	var base_basis: Basis = GlobalUtil.get_orientation_basis(orientation)
	var rotated_basis: Basis = GlobalUtil.apply_mesh_rotation(base_basis, orientation, mesh_rotation)

	# Apply this basis to the local offset to get world offset
	return rotated_basis * local_offset

# ==============================================================================
# PAINTING MODE METHODS (Phase 5)
# ==============================================================================
## Painting mode allows continuous tile placement while dragging the mouse.
## These methods batch all painted tiles into a single undo action per stroke.

## Starts a new paint stroke (opens an undo action without committing)
## Call this when the user presses the mouse button to start painting
func start_paint_stroke(undo_redo: EditorUndoRedoManager, action_name: String = "Paint Tiles") -> void:
	if _paint_stroke_active:
		push_warning("TilePlacementManager: Paint stroke already active, ending previous stroke")
		end_paint_stroke()

	_paint_stroke_undo_redo = undo_redo
	_paint_stroke_active = true

	# Create undo action but don't commit yet - we'll add tiles to it during the stroke
	_paint_stroke_undo_redo.create_action(action_name)

## Paints a single tile at the specified position during an active paint stroke
## Returns true if tile was placed, false if skipped (already exists or no active stroke)
func paint_tile_at(grid_pos: Vector3, orientation: TileOrientation) -> bool:
	if not _paint_stroke_active or not _paint_stroke_undo_redo:
		push_warning("TilePlacementManager: Cannot paint tile - no active paint stroke")
		return false

	if not tile_map_layer3d_root:
		return false

	# Create tile key
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

	# Check if tile already exists at this position
	if _placement_data.has(tile_key):
		# Tile exists - replace it
		var old_data: TilePlacerData = _placement_data[tile_key]
		var new_data: TilePlacerData = TileDataPool.acquire()  #  Use object pool
		new_data.uv_rect = current_tile_uv
		new_data.grid_position = grid_pos
		new_data.orientation = orientation
		new_data.mesh_rotation = current_mesh_rotation
		new_data.mesh_mode = tile_map_layer3d_root.current_mesh_mode

		# Add to ongoing undo action
		_paint_stroke_undo_redo.add_do_method(self, "_do_replace_tile", tile_key, grid_pos, current_tile_uv, orientation, current_mesh_rotation, new_data)
		_paint_stroke_undo_redo.add_undo_method(self, "_do_replace_tile", tile_key, grid_pos, old_data.uv_rect, old_data.orientation, old_data.mesh_rotation, old_data)

		# Immediately execute for live visual feedback (commit_action will skip execution)
		_do_replace_tile(tile_key, grid_pos, current_tile_uv, orientation, current_mesh_rotation, new_data)
	else:
		# New tile placement
		var tile_data: TilePlacerData = TileDataPool.acquire()  #  Use object pool
		tile_data.uv_rect = current_tile_uv
		tile_data.grid_position = grid_pos
		tile_data.orientation = orientation
		tile_data.mesh_rotation = current_mesh_rotation
		tile_data.is_face_flipped = is_current_face_flipped  # Store current flip state
		tile_data.mesh_mode = tile_map_layer3d_root.current_mesh_mode

		# Add to ongoing undo action
		_paint_stroke_undo_redo.add_do_method(self, "_do_place_tile", tile_key, grid_pos, current_tile_uv, orientation, current_mesh_rotation, tile_data)
		_paint_stroke_undo_redo.add_undo_method(self, "_undo_place_tile", tile_key)

		# Immediately execute for live visual feedback (commit_action will skip execution)
		_do_place_tile(tile_key, grid_pos, current_tile_uv, orientation, current_mesh_rotation, tile_data)

	return true

## Paints multiple tiles (multi-tile stamp) at the specified anchor position during an active paint stroke
## Returns true if tiles were placed, false if skipped (no active stroke)
func paint_multi_tiles_at(anchor_grid_pos: Vector3, orientation: TileOrientation) -> bool:
	if not _paint_stroke_active or not _paint_stroke_undo_redo:
		push_warning("TilePlacementManager: Cannot paint multi-tiles - no active paint stroke")
		return false

	if not tile_map_layer3d_root or multi_tile_selection.is_empty():
		return false

	# Calculate all tile positions and data (same logic as handle_multi_placement_with_undo)
	var tiles_to_place: Array[Dictionary] = []

	# Get anchor tile (first in selection)
	var anchor_uv_rect: Rect2 = multi_tile_selection[0]
	var anchor_pixel_pos: Vector2 = anchor_uv_rect.position
	var tile_pixel_size: Vector2 = anchor_uv_rect.size

	# Calculate position for each tile relative to anchor
	for i in range(multi_tile_selection.size()):
		var tile_uv_rect: Rect2 = multi_tile_selection[i]
		var tile_pixel_pos: Vector2 = tile_uv_rect.position

		# Calculate pixel offset from anchor
		var pixel_offset: Vector2 = tile_pixel_pos - anchor_pixel_pos

		# Convert to grid offset (in tiles)
		var grid_offset: Vector2 = pixel_offset / tile_pixel_size

		# Calculate 3D offset
		var local_offset: Vector3 = Vector3(grid_offset.x, 0, grid_offset.y)

		# Transform to world offset based on orientation and rotation
		var world_offset: Vector3 = _transform_local_offset_to_world(local_offset, orientation, current_mesh_rotation)
		var tile_grid_pos: Vector3 = anchor_grid_pos + world_offset

		# Create tile key
		var tile_key: int = GlobalUtil.make_tile_key(tile_grid_pos, orientation)

		# Store tile info
		tiles_to_place.append({
			"tile_key": tile_key,
			"grid_pos": tile_grid_pos,
			"uv_rect": tile_uv_rect,
			"orientation": orientation,
			"mesh_rotation": current_mesh_rotation,
			"is_replacement": _placement_data.has(tile_key)
		})

	# Add do/undo methods for each tile to the ongoing paint stroke
	for tile_info in tiles_to_place:
		if tile_info.is_replacement:
			# Tile already exists - replace it
			var old_data: TilePlacerData = _placement_data[tile_info.tile_key]
			var new_data: TilePlacerData = TileDataPool.acquire()  #  Use object pool
			new_data.uv_rect = tile_info.uv_rect
			new_data.grid_position = tile_info.grid_pos
			new_data.orientation = tile_info.orientation
			new_data.mesh_rotation = tile_info.mesh_rotation
			new_data.mesh_mode = tile_map_layer3d_root.current_mesh_mode

			_paint_stroke_undo_redo.add_do_method(self, "_do_replace_tile", tile_info.tile_key, tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation, new_data)
			_paint_stroke_undo_redo.add_undo_method(self, "_do_replace_tile", tile_info.tile_key, tile_info.grid_pos, old_data.uv_rect, old_data.orientation, old_data.mesh_rotation, old_data)

			# Immediately execute for live visual feedback (commit_action will skip execution)
			_do_replace_tile(tile_info.tile_key, tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation, new_data)
		else:
			# New tile placement
			var tile_data: TilePlacerData = TileDataPool.acquire()  #  Use object pool
			tile_data.uv_rect = tile_info.uv_rect
			tile_data.grid_position = tile_info.grid_pos
			tile_data.orientation = tile_info.orientation
			tile_data.mesh_rotation = tile_info.mesh_rotation
			tile_data.is_face_flipped = is_current_face_flipped  # Store current flip state
			tile_data.mesh_mode = tile_map_layer3d_root.current_mesh_mode

			_paint_stroke_undo_redo.add_do_method(self, "_do_place_tile", tile_info.tile_key, tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation, tile_data)
			_paint_stroke_undo_redo.add_undo_method(self, "_undo_place_tile", tile_info.tile_key)

			# Immediately execute for live visual feedback (commit_action will skip execution)
			_do_place_tile(tile_info.tile_key, tile_info.grid_pos, tile_info.uv_rect, tile_info.orientation, tile_info.mesh_rotation, tile_data)

	return true

## Erases a single tile at the specified position during an active paint stroke
## Returns true if tile was erased, false if no tile exists or no active stroke
func erase_tile_at(grid_pos: Vector3, orientation: TileOrientation) -> bool:
	if not _paint_stroke_active or not _paint_stroke_undo_redo:
		push_warning("TilePlacementManager: Cannot erase tile - no active paint stroke")
		return false

	if not tile_map_layer3d_root:
		return false

	# Create tile key
	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

	# Check if tile exists at this position
	if not _placement_data.has(tile_key):
		return false  # No tile to erase

	# Get tile data for undo
	var tile_data: TilePlacerData = _placement_data[tile_key]

	# Add erase operation to ongoing paint stroke
	_paint_stroke_undo_redo.add_do_method(self, "_do_erase_tile", tile_key)
	_paint_stroke_undo_redo.add_undo_method(self, "_do_place_tile", tile_key, grid_pos, tile_data.uv_rect, orientation, tile_data.mesh_rotation, tile_data)

	# Immediately execute for live visual feedback (commit_action will skip execution)
	_do_erase_tile(tile_key)

	return true

## Ends the current paint stroke (commits the batched undo action)
## Call this when the user releases the mouse button
func end_paint_stroke() -> void:
	if not _paint_stroke_active:
		return

	# Commit the undo action (all painted tiles become one undo operation)
	# Pass false to skip execution since we already executed operations immediately during painting
	if _paint_stroke_undo_redo:
		_paint_stroke_undo_redo.commit_action(false)

	# Clear paint stroke state
	_paint_stroke_active = false
	_paint_stroke_undo_redo = null

## Syncs placement data from TileMapLayer3D's saved tiles
## Call this when loading an existing scene or selecting a TileMapLayer3D
##   Also rebuilds spatial index for area erase queries
func sync_from_tile_model() -> void:
	if not tile_map_layer3d_root:
		return

	#   If _tile_lookup is empty but saved_tiles exist, chunks haven't been rebuilt yet
	# This happens during scene reload because _rebuild_chunks_from_saved_data() is deferred
	# Force immediate rebuild to avoid false corruption errors during validation
	if tile_map_layer3d_root._tile_lookup.is_empty() and not tile_map_layer3d_root.saved_tiles.is_empty():
		print("sync_from_tile_model: _tile_lookup empty but %d saved_tiles exist - forcing immediate rebuild..." % tile_map_layer3d_root.saved_tiles.size())
		tile_map_layer3d_root._rebuild_chunks_from_saved_data(false)  # force_mesh_rebuild=false (meshes already correct)
		print("Immediate rebuild complete - _tile_lookup now has %d entries" % tile_map_layer3d_root._tile_lookup.size())

	# Clear existing data
	_placement_data.clear()
	_spatial_index.clear()  #   Clear spatial index to rebuild

	# Rebuild placement data AND spatial index from saved tiles
	var validation_errors: int = 0
	for tile_data in tile_map_layer3d_root.saved_tiles:
		var tile_key: int = GlobalUtil.make_tile_key(tile_data.grid_position, tile_data.orientation)
		_placement_data[tile_key] = tile_data

		#   Rebuild spatial index for area erase/fill queries
		# Without this, area erase returns zero tiles after project reload
		_spatial_index.add_tile(tile_key, tile_data.grid_position)

		# VALIDATION: Verify chunk mappings exist for this tile
		# After scene reload, _rebuild_chunks_from_saved_data() should have created these mappings
		var tile_ref: TileMapLayer3D.TileRef = tile_map_layer3d_root.get_tile_ref(tile_key)
		if not tile_ref:
			push_error("❌ CORRUPTION: Tile key %d in saved_tiles but has no TileRef" % tile_key)
			validation_errors += 1
			continue

		# Validate chunk exists and has this tile in its dictionaries
		var chunk: MultiMeshTileChunkBase = null
		if tile_ref.mesh_mode == GlobalConstants.MeshMode.MESH_SQUARE:
			if tile_ref.chunk_index >= 0 and tile_ref.chunk_index < tile_map_layer3d_root._quad_chunks.size():
				chunk = tile_map_layer3d_root._quad_chunks[tile_ref.chunk_index]
			else:
				push_error("❌ CORRUPTION: Tile key %d has invalid quad chunk_index %d (max %d)" % [tile_key, tile_ref.chunk_index, tile_map_layer3d_root._quad_chunks.size() - 1])
				validation_errors += 1
				continue
		else:  # MESH_TRIANGLE
			if tile_ref.chunk_index >= 0 and tile_ref.chunk_index < tile_map_layer3d_root._triangle_chunks.size():
				chunk = tile_map_layer3d_root._triangle_chunks[tile_ref.chunk_index]
			else:
				push_error("❌ CORRUPTION: Tile key %d has invalid triangle chunk_index %d (max %d)" % [tile_key, tile_ref.chunk_index, tile_map_layer3d_root._triangle_chunks.size() - 1])
				validation_errors += 1
				continue

		# Validate chunk.tile_refs has this tile
		if not chunk.tile_refs.has(tile_key):
			push_error("❌ CORRUPTION: Tile key %d has TileRef but not in chunk.tile_refs (chunk_index=%d)" % [tile_key, tile_ref.chunk_index])
			validation_errors += 1

		# Validate instance_to_key has reverse mapping
		var instance_index: int = chunk.tile_refs.get(tile_key, -1)
		if instance_index >= 0:
			if not chunk.instance_to_key.has(instance_index):
				push_error("❌ CORRUPTION: Tile key %d instance %d not in chunk.instance_to_key" % [tile_key, instance_index])
				validation_errors += 1
			elif chunk.instance_to_key[instance_index] != tile_key:
				push_error("❌ CORRUPTION: Tile key %d instance %d points to wrong key %d in instance_to_key" % [tile_key, instance_index, chunk.instance_to_key[instance_index]])
				validation_errors += 1

	if validation_errors > 0:
		push_error("🔥   sync_from_tile_model() found %d data corruption errors - chunk system may be inconsistent!" % validation_errors)
		print("TilePlacementManager: Synced %d tiles from model (spatial index rebuilt) - %d ERRORS DETECTED" % [_placement_data.size(), validation_errors])
	else:
		print("TilePlacementManager: Synced %d tiles from model (spatial index rebuilt) - validation passed " % _placement_data.size())

# ==============================================================================
# AREA FILL OPERATIONS (Paint/Erase Rectangular Region)
# ==============================================================================

## Fills a rectangular area with the current tile
## Creates a single undo action for the entire operation
##
## @param min_grid_pos: Minimum corner of selection (inclusive)
## @param max_grid_pos: Maximum corner of selection (inclusive)
## @param orientation: Active plane orientation (0-5)
## @param undo_redo: EditorUndoRedoManager for undo/redo support
## @returns: Number of tiles placed, or -1 if operation fails
## DEPRECATED: Old non-compressed method removed - see fill_area_with_undo_compressed()
## The non-compressed version had  bugs:
## - Line 1530: Never set new_tile_data.mesh_mode (caused triangle→square corruption)
## - Line 1553: Read mesh_mode from wrong tile (var existing_mode: int = tile_data.mesh_mode)
## - 60% more memory usage for undo history
## Removed 2025-01-20 in favor of compressed implementation

##  Compressed area fill with optimized undo storage
## Uses UndoAreaData for 60% memory reduction in undo history
## Recommended for large area fills (100+ tiles)
## @param min_grid_pos: Minimum grid corner (inclusive)
## @param max_grid_pos: Maximum grid corner (inclusive)
## @param orientation: Active plane orientation (0-5)
## @param undo_redo: EditorUndoRedoManager for undo/redo support
## @returns: Number of tiles placed, or -1 if operation fails
func fill_area_with_undo_compressed(
	min_grid_pos: Vector3,
	max_grid_pos: Vector3,
	orientation: int,
	undo_redo: EditorUndoRedoManager
) -> int:
	if not tile_map_layer3d_root:
		push_error("TilePlacementManager: Cannot fill area - no TileMapLayer3D set")
		return -1

	if current_tile_uv.size.x <= 0 or current_tile_uv.size.y <= 0:
		push_error("TilePlacementManager: Cannot fill area - no tile selected")
		return -1

	# Get all grid positions in the selected area
	var positions: Array[Vector3] = GlobalUtil.get_grid_positions_in_area(
		min_grid_pos,
		max_grid_pos,
		orientation
	)

	# Safety check: prevent massive fills
	if positions.size() > GlobalConstants.MAX_AREA_FILL_TILES:
		push_error("TilePlacementManager: Area too large (%d tiles, max %d)" % [positions.size(), GlobalConstants.MAX_AREA_FILL_TILES])
		return -1

	if positions.is_empty():
		return 0

	# Build lightweight tile list for compression
	var tiles_to_place: Array = []
	var existing_tiles: Array = []

	for grid_pos in positions:
		var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

		var tile_info: Dictionary = {
			"tile_key": tile_key,
			"grid_pos": grid_pos,
			"uv_rect": current_tile_uv,
			"orientation": orientation,
			"rotation": current_mesh_rotation,
			"flip": is_current_face_flipped,
			"mode": tile_map_layer3d_root.current_mesh_mode
		}

		# Store existing tiles for undo
		if _placement_data.has(tile_key):
			var existing: TilePlacerData = _placement_data[tile_key]
			var existing_info: Dictionary = {
				"tile_key": tile_key,
				"grid_pos": existing.grid_position,
				"uv_rect": existing.uv_rect,
				"orientation": existing.orientation,
				"rotation": existing.mesh_rotation,
				"flip": existing.is_face_flipped,
				"mode": existing.mesh_mode
			}
			existing_tiles.append(existing_info)

		tiles_to_place.append(tile_info)

	# Create compressed undo data
	var compressed_new: UndoData.UndoAreaData = UndoData.UndoAreaData.from_tiles(tiles_to_place)
	var compressed_old: UndoData.UndoAreaData = null
	if existing_tiles.size() > 0:
		compressed_old = UndoData.UndoAreaData.from_tiles(existing_tiles)

	# Single undo action with compressed data
	undo_redo.create_action("Fill Area (%d tiles)" % tiles_to_place.size())
	undo_redo.add_do_method(self, "_do_area_fill_compressed", compressed_new)
	undo_redo.add_undo_method(self, "_undo_area_fill_compressed", compressed_new, compressed_old)
	undo_redo.commit_action()

	return tiles_to_place.size()


##  Internal method - apply compressed area fill
## Called by undo/redo system to place tiles from compressed data
## @param area_data: Compressed UndoAreaData containing all tiles
func _do_area_fill_compressed(area_data: UndoData.UndoAreaData) -> void:
	#  Batch all updates into single GPU sync
	begin_batch_update()

	var tiles: Array = area_data.to_tiles()
	for tile_info in tiles:
		# Acquire pooled TilePlacerData
		var tile_data: TilePlacerData = TileDataPool.acquire()
		tile_data.grid_position = tile_info.grid_pos
		tile_data.uv_rect = tile_info.uv_rect
		tile_data.orientation = tile_info.orientation
		tile_data.mesh_rotation = tile_info.rotation
		tile_data.is_face_flipped = tile_info.flip
		tile_data.mesh_mode = tile_info.mode

		# Place tile
		_do_place_tile(
			tile_info.tile_key,
			tile_info.grid_pos,
			tile_info.uv_rect,
			tile_info.orientation,
			tile_info.rotation,
			tile_data
		)

	end_batch_update()


##  Internal method - undo compressed area fill
## Called by undo/redo system to restore previous state
## @param new_data: Compressed data of tiles that were placed (to remove)
## @param old_data: Compressed data of tiles that existed before (to restore)
func _undo_area_fill_compressed(new_data: UndoData.UndoAreaData, old_data: UndoData.UndoAreaData) -> void:
	#  Batch all updates into single GPU sync
	begin_batch_update()

	# Remove newly placed tiles
	var new_tiles: Array = new_data.to_tiles()
	for tile_info in new_tiles:
		_do_erase_tile(tile_info.tile_key)

	# Restore old tiles if any existed
	if old_data:
		var old_tiles: Array = old_data.to_tiles()
		for tile_info in old_tiles:
			# Acquire pooled TilePlacerData
			var tile_data: TilePlacerData = TileDataPool.acquire()
			tile_data.grid_position = tile_info.grid_pos
			tile_data.uv_rect = tile_info.uv_rect
			tile_data.orientation = tile_info.orientation
			tile_data.mesh_rotation = tile_info.rotation
			tile_data.is_face_flipped = tile_info.flip
			tile_data.mesh_mode = tile_info.mode

			# Restore tile
			_do_place_tile(
				tile_info.tile_key,
				tile_info.grid_pos,
				tile_info.uv_rect,
				tile_info.orientation,
				tile_info.rotation,
				tile_data
			)

	end_batch_update()


## Erases all tiles in a rectangular area
## Creates a single undo action for the entire operation
##
## IMPORTANT: This method detects ALL tiles within the selection bounds,
## including tiles placed at fractional grid positions (0.5, 0.25 snap).
## It iterates through all existing tiles and checks if their positions
## fall within the min/max bounds, rather than only checking integer grid positions.
##
## @param min_grid_pos: Minimum corner of selection (inclusive)
## @param max_grid_pos: Maximum corner of selection (inclusive)
## @param orientation: Active plane orientation (0-5, unused - all orientations checked)
## @param undo_redo: EditorUndoRedoManager for undo/redo support
## @returns: Number of tiles erased, or -1 if operation fails
##  Erases all tiles in a rectangular area with two-phase strategy
## Phase 1: Spatial index rough filter
## Phase 2: Precise bounds check (only if needed)
func erase_area_with_undo(
	min_grid_pos: Vector3,
	max_grid_pos: Vector3,
	orientation: int,
	undo_redo: EditorUndoRedoManager
) -> int:
	if not tile_map_layer3d_root:
		push_error("TilePlacementManager: Cannot erase area - no TileMapLayer3D set")
		return -1

	# Calculate actual min/max bounds (user may have dragged in any direction)
	var actual_min: Vector3 = Vector3(
		min(min_grid_pos.x, max_grid_pos.x),
		min(min_grid_pos.y, max_grid_pos.y),
		min(min_grid_pos.z, max_grid_pos.z)
	)
	var actual_max: Vector3 = Vector3(
		max(min_grid_pos.x, max_grid_pos.x),
		max(min_grid_pos.y, max_grid_pos.y),
		max(min_grid_pos.z, max_grid_pos.z)
	)

	# Apply orientation-aware tolerance
	var tolerance: float = GlobalConstants.AREA_ERASE_SURFACE_TOLERANCE
	var tolerance_vector: Vector3 = GlobalUtil.get_orientation_tolerance(orientation, tolerance)
	actual_min -= tolerance_vector
	actual_max += tolerance_vector

	# OPTIMIZATION: Calculate selection volume to choose strategy
	var selection_size: Vector3 = actual_max - actual_min
	var selection_volume: float = selection_size.x * selection_size.y * selection_size.z
	var selection_diagonal: float = selection_size.length()
	
	# Performance statistics
	var stats: Dictionary = {
		"total_tiles": _placement_data.size(),
		"selection_volume": selection_volume,
		"selection_diagonal": selection_diagonal
	}
	
	if GlobalConstants.DEBUG_AREA_OPERATIONS:
		print("Area Erase: %.1fx%.1fx%.1f (volume=%.1f, diagonal=%.1f)" % 
		      [selection_size.x, selection_size.y, selection_size.z, selection_volume, selection_diagonal])

	# PHASE 1: Choose optimal strategy based on selection characteristics
	var tiles_to_erase: Array[Dictionary] = []
	
	# Strategy A: Small precise selection - use spatial index with full bounds checking
	const SMALL_SELECTION_THRESHOLD: float = 100.0  # 10x10x1 or equivalent
	
	# Strategy B: Medium selection - use spatial index with relaxed checking  
	const MEDIUM_SELECTION_THRESHOLD: float = 1000.0  # 10x10x10 or equivalent
	
	# Strategy C: Large selection - skip spatial index, iterate all tiles
	# (faster for huge selections??????? How??)
	
	if selection_volume < SMALL_SELECTION_THRESHOLD:
		# STRATEGY A: Small selection - full precision
		if GlobalConstants.DEBUG_AREA_OPERATIONS:
			print("  → Using PRECISE strategy (small selection)")
		
		var candidate_tiles: Array = _spatial_index.get_tiles_in_area(actual_min, actual_max)
		
		for tile_key in candidate_tiles:
			if not _placement_data.has(tile_key):
				continue  # Tile was already removed
			
			var tile_data: TilePlacerData = _placement_data[tile_key]
			var tile_pos: Vector3 = tile_data.grid_position
			
			# Precise AABB check
			if (tile_pos.x >= actual_min.x and tile_pos.x <= actual_max.x and
				tile_pos.y >= actual_min.y and tile_pos.y <= actual_max.y and
				tile_pos.z >= actual_min.z and tile_pos.z <= actual_max.z):
				
				tiles_to_erase.append({
					"tile_key": tile_key,
					"grid_pos": tile_data.grid_position,
					"uv_rect": tile_data.uv_rect,
					"orientation": tile_data.orientation,
					"rotation": tile_data.mesh_rotation,
					"flip": tile_data.is_face_flipped,
					"mode": tile_data.mesh_mode
				})
	
	elif selection_volume < MEDIUM_SELECTION_THRESHOLD:
		# STRATEGY B: Medium selection - spatial index with quick checks
		if GlobalConstants.DEBUG_AREA_OPERATIONS:
			print("  → Using SPATIAL strategy (medium selection)")
		
		var candidate_tiles: Array = _spatial_index.get_tiles_in_area(actual_min, actual_max)
		
		# For medium selections, trust the spatial index more
		# Only do quick validation, not full bounds check
		for tile_key in candidate_tiles:
			if not _placement_data.has(tile_key):
				continue
			
			var tile_data: TilePlacerData = _placement_data[tile_key]
			
			# Quick sanity check - is tile remotely near selection?
			var tile_pos: Vector3 = tile_data.grid_position
			var quick_check: bool = (
				tile_pos.x >= actual_min.x - 1.0 and tile_pos.x <= actual_max.x + 1.0 and
				tile_pos.y >= actual_min.y - 1.0 and tile_pos.y <= actual_max.y + 1.0 and
				tile_pos.z >= actual_min.z - 1.0 and tile_pos.z <= actual_max.z + 1.0
			)
			
			if quick_check:
				tiles_to_erase.append({
					"tile_key": tile_key,
					"grid_pos": tile_data.grid_position,
					"uv_rect": tile_data.uv_rect,
					"orientation": tile_data.orientation,
					"rotation": tile_data.mesh_rotation,
					"flip": tile_data.is_face_flipped,
					"mode": tile_data.mesh_mode
				})
	
	else:
		# STRATEGY C: Large selection - direct iteration
		if GlobalConstants.DEBUG_AREA_OPERATIONS:
			print("  → Using DIRECT strategy (large selection)")
		
		# For massive selections, checking all tiles is actually faster
		# than spatial index overhead
		for tile_key in _placement_data:
			var tile_data: TilePlacerData = _placement_data[tile_key]
			var tile_pos: Vector3 = tile_data.grid_position
			
			# Simple AABB check
			if (tile_pos.x >= actual_min.x and tile_pos.x <= actual_max.x and
				tile_pos.y >= actual_min.y and tile_pos.y <= actual_max.y and
				tile_pos.z >= actual_min.z and tile_pos.z <= actual_max.z):
				
				tiles_to_erase.append({
					"tile_key": tile_key,
					"grid_pos": tile_data.grid_position,
					"uv_rect": tile_data.uv_rect,
					"orientation": tile_data.orientation,
					"rotation": tile_data.mesh_rotation,
					"flip": tile_data.is_face_flipped,
					"mode": tile_data.mesh_mode
				})
	
	if GlobalConstants.DEBUG_AREA_OPERATIONS:
		print("  → Found %d tiles to erase (from %d total)" % [tiles_to_erase.size(), stats.total_tiles])
	
	if tiles_to_erase.is_empty():
		return 0

	# PHASE 2: Batch erase with validation
	
	# Optional: Validate data integrity before large operation
	if GlobalConstants.DEBUG_DATA_INTEGRITY and tiles_to_erase.size() > 100:
		print("PRE-ERASE VALIDATION (%d tiles)..." % tiles_to_erase.size())
		var pre_validation: Dictionary = _validate_data_structure_integrity()
		if not pre_validation.valid:
			push_error("DATA CORRUPTION DETECTED BEFORE AREA ERASE:")
			for error in pre_validation.errors:
				push_error("  - %s" % error)

	# Create single undo action for entire area erase
	undo_redo.create_action("Erase Area (%d tiles)" % tiles_to_erase.size())

	# Add do/undo methods for each tile
	for tile_info in tiles_to_erase:
		var tile_key: int = tile_info.tile_key

		# Do = erase tile
		undo_redo.add_do_method(self, "_do_erase_tile", tile_key)

		# Undo = restore tile
		var restore_data: TilePlacerData = TileDataPool.acquire()
		restore_data.is_face_flipped = tile_info.flip
		restore_data.mesh_mode = tile_info.mode

		undo_redo.add_undo_method(
			self, "_do_place_tile",
			tile_key,
			tile_info.grid_pos,
			tile_info.uv_rect,
			tile_info.orientation,
			tile_info.rotation,
			restore_data
		)

	#  Batch all MultiMesh updates into single GPU sync
	begin_batch_update()
	undo_redo.commit_action()
	end_batch_update()

	# Optional: Validate data integrity after large operation
	if GlobalConstants.DEBUG_DATA_INTEGRITY and tiles_to_erase.size() > 100:
		print("POST-ERASE VALIDATION...")
		var post_validation: Dictionary = _validate_data_structure_integrity()
		if not post_validation.valid:
			push_error("DATA CORRUPTION DETECTED AFTER AREA ERASE:")
			for error in post_validation.errors:
				push_error("  - %s" % error)
		else:
			print("Data integrity validated - %d tiles remaining" % post_validation.stats.placement_data_size)

	return tiles_to_erase.size()


## HELPER: Creates a deep copy of TilePlacerData for undo/redo
##   Undo/redo system must use COPIES, not shared instances
## Reason: Object pool reuses instances - shared references lead to corruption
static func _copy_tile_data(source: TilePlacerData) -> TilePlacerData:
	var copy: TilePlacerData = TileDataPool.acquire()
	copy.uv_rect = source.uv_rect
	copy.grid_position = source.grid_position
	copy.orientation = source.orientation
	copy.mesh_rotation = source.mesh_rotation
	copy.is_face_flipped = source.is_face_flipped
	copy.mesh_mode = source.mesh_mode
	# NOTE: multimesh_instance_index is NOT copied - it's runtime-only and will be reassigned
	return copy

