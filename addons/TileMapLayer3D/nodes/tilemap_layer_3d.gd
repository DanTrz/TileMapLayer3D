@icon("uid://b2snx34kyfmpg")
@tool
class_name TileMapLayer3D
extends Node3D

## Custom container node for 2.5D tile placement using MultiMesh for performance
## Responsibility: MultiMesh management, material configuration, tile group organization 

# Preload collision generator for collision system
const CollisionGenerator = preload("uid://cu1e5kkaoxgun")


@export_group("TileMapData")
## Settings Resource containing all per-node configuration
## This is the single source of truth for node properties
@export var settings: TileMapLayerSettings:
	set(value):
		if settings != value:
			# Disconnect from old settings Resource
			if settings and settings.changed.is_connected(_on_settings_changed):
				settings.changed.disconnect(_on_settings_changed)

			settings = value

			# Ensure settings exists
			if not settings:
				settings = TileMapLayerSettings.new()

			# Connect to new settings Resource
			if settings and not settings.changed.is_connected(_on_settings_changed):
				settings.changed.connect(_on_settings_changed)

			# Apply settings to internal state
			_apply_settings()
# Persistent tile data (saved to scene) - This remains @export as it's actual data, not settings
## DEPRECATED - kept temporarily for one-time migration from old scenes
## Will be cleared after migration and should be empty in new scenes
@export var saved_tiles: Array[TilePlacerData] = []

# ============================================================================
# TILE STORAGE - Columnar Format for Efficient Serialization
# ============================================================================
# Each tile's data is stored across parallel arrays for compact binary storage.
# This replaces Array[TilePlacerData] which creates bloated SubResource entries.

## Grid positions of all tiles (12 bytes per tile)
@export var _tile_positions: PackedVector3Array = PackedVector3Array()

## UV rect data: 4 floats per tile (x, y, width, height) - 16 bytes per tile
@export var _tile_uv_rects: PackedFloat32Array = PackedFloat32Array()

## Bitpacked flags per tile - 4 bytes per tile
## Bits 0-4: orientation (0-17)
## Bits 5-6: mesh_rotation (0-3)
## Bits 7-8: mesh_mode (0-3)
## Bit 9: is_face_flipped
## Bits 10-17: terrain_id + 128 (allows -1 to 126)
@export var _tile_flags: PackedInt32Array = PackedInt32Array()

## Transform params index for tiles that need them (tilted tiles)
## Index into _tile_transform_data, -1 if using defaults - 4 bytes per tile
@export var _tile_transform_indices: PackedInt32Array = PackedInt32Array()

## Sparse storage for non-default transform params
## Each entry: 5 floats (spin_angle, tilt_angle, diagonal_scale, tilt_offset, depth_scale)
## BREAKING: Scenes saved with old 4-float format (before commit 3019248) cannot be loaded
## See CLAUDE.md for migration instructions
@export var _tile_transform_data: PackedFloat32Array = PackedFloat32Array()


@export var _quad_chunks: Array[SquareTileChunk] = []  # Chunks for FLAT_SQUARE tiles
@export var _triangle_chunks: Array[TriangleTileChunk] = []  # Chunks for FLAT_TRIANGULE tiles
@export var _box_chunks: Array[BoxTileChunk] = []  # Chunks for BOX_MESH tiles (DEFAULT texture mode)
@export var _prism_chunks: Array[PrismTileChunk] = []  # Chunks for PRISM_MESH tiles (DEFAULT texture mode)
@export var _box_repeat_chunks: Array[BoxTileChunk] = []  # Chunks for BOX_MESH tiles (REPEAT texture mode)
@export var _prism_repeat_chunks: Array[PrismTileChunk] = []  # Chunks for PRISM_MESH tiles (REPEAT texture mode)

@export_group("Decal Mode")
@export var decal_mode: bool = false  # If true, tiles render as decals (no overlap z-fighting)
@export var decal_target_node: TileMapLayer3D = null  # Node to use as base for decal offset calculations
@export var decal_y_offset: float = 0.01  # Pushes the node upwards to avoid z-fighting when in decal mode
@export var decal_z_offset: float = 0.01  # Pushes the node forwards to avoid z-fighting when in decal mode
@export var render_priority: int = GlobalConstants.DEFAULT_RENDER_PRIORITY
var _chunk_shadow_casting: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON  # Default shadow casting setting for chunks
# var decal_target_position: Vector3 = Vector3(self.global_position.y +decal_y_offset	, self.global_position.z + decal_z_offset, self.global_position.x) # Internal storage for decal target position



# INTERNAL STATE (derived from settings Resource)
var tileset_texture: Texture2D = null
var grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE
var texture_filter_mode: int = GlobalConstants.DEFAULT_TEXTURE_FILTER
#  Lookup dictionary for fast saved_tiles access
var _saved_tiles_lookup: Dictionary = {}  # int (tile_key) -> Array index
# MultiMesh infrastructure - UNIFIED system (all tiles regardless of UV) - RUNTIME ONLY
# var _unified_chunks: Array[MultiMeshTileChunkBase] = []  # Array of chunks for ALL tiles #TODO:REMOVE
var current_mesh_mode: GlobalConstants.MeshMode = GlobalConstants.DEFAULT_MESH_MODE



var _tile_lookup: Dictionary = {}  # int (tile_key) -> TileRef
var _shared_material: ShaderMaterial = null
var _shared_material_double_sided: ShaderMaterial = null  # For BOX_MESH/PRISM_MESH (no debug backfaces)
var _is_rebuilt: bool = false  # Track if chunks were rebuilt from saved data
var _buffers_stripped: bool = false  # FIX P0-5: Track strip/restore state to prevent race condition
var _reindex_in_progress: bool = false  # FIX P1-13: Prevent concurrent reindex during tile operations
var _cached_warnings: PackedStringArray = PackedStringArray()  # FIX P2-24: Cache configuration warnings
var _warnings_dirty: bool = true  # FIX P2-24: Track when warnings need recomputation

# INTERNAL STATE (derived from settings Resource)
# var enable_collision: bool = true
var collision_layer: int = GlobalConstants.DEFAULT_COLLISION_LAYER
var collision_mask: int = GlobalConstants.DEFAULT_COLLISION_MASK

# Highlight overlay system for Box Erase feature - EDITOR ONLY
var _highlight_multimesh: MultiMesh = null
var _highlight_instance: MultiMeshInstance3D = null
var _highlighted_tile_keys: Array[int] = []

# Blocked position highlight overlay - shows when cursor is outside valid range - EDITOR ONLY
var _blocked_highlight_multimesh: MultiMesh = null
var _blocked_highlight_instance: MultiMeshInstance3D = null
var _is_blocked_highlight_visible: bool = false

## Reference to a tile's location in the chunk system
class TileRef:
	var chunk_index: int = -1
	var instance_index: int = -1
	var uv_rect: Rect2 = Rect2()
	var mesh_mode: GlobalConstants.MeshMode = GlobalConstants.MeshMode.FLAT_SQUARE
	var texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT  # For BOX/PRISM chunks

func _ready() -> void:
	# RUNTIME: Rebuild chunks from columnar data (MultiMesh instance data isn't serialized)
	# SHARED: Runs in both editor and runtime
	_rebuild_chunks_from_saved_data(false)

	# EDITOR-ONLY: Skip at runtime
	if not Engine.is_editor_hint(): return

	# _rebuild_chunks_from_saved_data(false)


	# Ensure settings exists and is connected
	if not settings:
		settings = TileMapLayerSettings.new()
		# print("TileMapLayer3D: Created default settings Resource")

	# Apply settings to internal state
	_apply_settings()

	# Create highlight overlay for Box Erase feature
	_create_highlight_overlay()

	# Create blocked highlight overlay for out-of-bounds positions
	_create_blocked_highlight_overlay()

	# Migrate legacy properties from old scenes (if needed)
	# call_deferred("_migrate_legacy_properties") #TODO: Not working properly, removing for now

	# Only rebuild if chunks don't exist (migration or first load)
	# With pre-created nodes, chunks already exist at runtime
	# Check all chunk arrays to see if we need to rebuild
	var all_chunks_empty: bool = _quad_chunks.is_empty() and _triangle_chunks.is_empty() and _box_chunks.is_empty() and _prism_chunks.is_empty()
	var has_tile_data: bool = saved_tiles.size() > 0 or _tile_positions.size() > 0
	if has_tile_data and all_chunks_empty and not _is_rebuilt:
		call_deferred("_rebuild_chunks_from_saved_data", false)  # force_mesh_rebuild=false (mesh already correct from save)

func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return

	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			# Migrate old format if needed (one-time)
			if saved_tiles.size() > 0 and _tile_positions.size() == 0:
				_migrate_to_columnar_storage()

			# Strip chunk buffer data - it's rebuilt from tile data on load
			_strip_chunk_buffers_for_save()

		NOTIFICATION_EDITOR_POST_SAVE:
			# Restore tile rendering after save
			_restore_chunk_buffers_after_save()

func _process(delta: float) -> void:
	if not Engine.is_editor_hint(): return
	if decal_mode and decal_target_node:
		_apply_decal_mode()

func _apply_decal_mode() -> void:
	if not Engine.is_editor_hint(): return

	# FIX P0-3: Validate decal_target_node is still valid before accessing properties
	# Node could be deleted, become invalid, or be set to null between frames
	if not is_instance_valid(decal_target_node):
		return

	var target_pos := Vector3(
		decal_target_node.global_position.x,
		decal_target_node.global_position.y + decal_y_offset,
		decal_target_node.global_position.z + decal_z_offset)

	#Auto Offset position based on the Base Node (Y and Z).
	if not global_position.is_equal_approx(target_pos):
		global_position = target_pos
		_update_material()
		# print("TileMapLayer3D: Applying decal mode offset. New Position: " + str(self.global_position) +  "Target Node: " + str(decal_target_node.name))

	#Change rendering server layer. +1#
	if render_priority == decal_target_node.render_priority:
		render_priority = decal_target_node.render_priority + 1
		_update_material() #Update materials to ensure Cast shadows off for decal mode

	#Update materials to ensure Cast shadows off for decal mode
	if _chunk_shadow_casting != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_chunk_shadow_casting = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_update_material()
	# 	print("TileMapLayer3D: Decal mode active." +
	# "Updated render priority to " + str(render_priority) +
	# "New Position: " + str(self.global_position) +
	# "Target Node: " + str(decal_target_node.name))

## Called when settings Resource changes
func _on_settings_changed() -> void:
	if not Engine.is_editor_hint(): return
	_apply_settings()

## Applies settings from Resource to internal state
func _apply_settings() -> void:
	if not settings:
		return

	# Apply tileset configuration
	tileset_texture = settings.tileset_texture
	texture_filter_mode = settings.texture_filter_mode

	# Apply grid configuration
	var old_grid_size: float = grid_size
	grid_size = settings.grid_size

	# Apply grid tilt offset configuration
	# zAxis_tilt_offset = settings._zAxis_tilt_offset
	# yAxis_tilt_offset = settings._yAxis_tilt_offset
	# xAxis_tilt_offset = settings._xAxis_tilt_offset

	# Apply rendering configuration
	render_priority = settings.render_priority

	# Apply collision configuration
	# var old_collision_enabled: bool = enable_collision
	# enable_collision = settings.enable_collision
	collision_layer = settings.collision_layer
	collision_mask = settings.collision_mask
	# alpha_threshold = settings.alpha_threshold

	# Update material if texture or filter changed
	if tileset_texture:
		_update_material()

	# Handle grid size change - requires chunk rebuild with mesh recreation
	if abs(old_grid_size - grid_size) > 0.001 and get_tile_count() > 0:
		#print("TileMapLayer3D: Grid size changed to ", grid_size, ", rebuilding chunks...")
		call_deferred("_rebuild_chunks_from_saved_data", true)  # force_mesh_update_material_rebuild=true

	# Handle collision enable/disable
	# if old_collision_enabled != enable_collision:
	# 	if enable_collision and saved_tiles.size() > 0:
	# 		call_deferred("generate_simple_collision_shapes")
	# 	elif not enable_collision:
	# 		call_deferred("clear_collision_shapes")

	notify_property_list_changed()

## Rebuilds MultiMesh chunks from saved tile data (called on scene load)
## If force_mesh_rebuild is true, recreates mesh geometry (needed when grid_size changes)
func _rebuild_chunks_from_saved_data(force_mesh_rebuild: bool = false) -> void:
	# Allow rebuild even if already rebuilt (e.g., when grid_size changes)
	# Note: _is_rebuilt flag prevents automatic rebuild on _ready
	# but manual calls (from grid_size change) should always rebuild

	# STEP 1: Clear arrays first
	_quad_chunks.clear()
	_triangle_chunks.clear()
	_box_chunks.clear()
	_prism_chunks.clear()
	_box_repeat_chunks.clear()
	_prism_repeat_chunks.clear()
	_tile_lookup.clear()

	# STEP 2: Find and categorize existing saved chunk nodes from scene file
	for child in get_children():
		if child is SquareTileChunk:
			var chunk = child as SquareTileChunk
			
			# Reset runtime state
			chunk.tile_count = 0
			chunk.tile_refs.clear()
			chunk.instance_to_key.clear()
			
			# Handle mesh rebuild if needed (grid size change)
			if force_mesh_rebuild:
				chunk.multimesh.visible_instance_count = 0
				chunk.multimesh.instance_count = 0
				
				chunk.multimesh.mesh = TileMeshGenerator.create_tile_quad(
					Rect2(0, 0, 1, 1),
					Vector2(1, 1),
					Vector2(grid_size, grid_size)
				)
				
				chunk.multimesh.instance_count = MultiMeshTileChunkBase.MAX_TILES
			else:
				chunk.multimesh.visible_instance_count = 0
			
			_quad_chunks.append(chunk)
			
		elif child is TriangleTileChunk:
			var chunk = child as TriangleTileChunk

			# Reset runtime state
			chunk.tile_count = 0
			chunk.tile_refs.clear()
			chunk.instance_to_key.clear()

			# Handle mesh rebuild if needed
			if force_mesh_rebuild:
				chunk.multimesh.visible_instance_count = 0
				chunk.multimesh.instance_count = 0

				chunk.multimesh.mesh = TileMeshGenerator.create_tile_triangle(
					Rect2(0, 0, 1, 1),
					Vector2(1, 1),
					Vector2(grid_size, grid_size)
				)

				chunk.multimesh.instance_count = MultiMeshTileChunkBase.MAX_TILES
			else:
				chunk.multimesh.visible_instance_count = 0

			_triangle_chunks.append(chunk)

		elif child is BoxTileChunk:
			var chunk = child as BoxTileChunk
			var is_repeat: bool = chunk.name.begins_with("BoxRepeatChunk_")

			# Reset runtime state
			chunk.tile_count = 0
			chunk.tile_refs.clear()
			chunk.instance_to_key.clear()

			# Handle mesh rebuild if needed
			if force_mesh_rebuild:
				chunk.multimesh.visible_instance_count = 0
				chunk.multimesh.instance_count = 0
				if is_repeat:
					chunk.multimesh.mesh = TileMeshGenerator.create_box_mesh_repeat(grid_size)
				else:
					chunk.multimesh.mesh = TileMeshGenerator.create_box_mesh(grid_size)
				chunk.multimesh.instance_count = MultiMeshTileChunkBase.MAX_TILES
			else:
				chunk.multimesh.visible_instance_count = 0
				# CRITICAL FIX: ALWAYS ensure REPEAT chunks have the correct mesh
				# This handles chunks that were created before the REPEAT fix was applied
				if is_repeat:
					chunk.multimesh.mesh = TileMeshGenerator.create_box_mesh_repeat(grid_size)

			# Append to correct array based on texture mode
			if is_repeat:
				_box_repeat_chunks.append(chunk)
			else:
				_box_chunks.append(chunk)

		elif child is PrismTileChunk:
			var chunk = child as PrismTileChunk
			var is_repeat: bool = chunk.name.begins_with("PrismRepeatChunk_")

			# Reset runtime state
			chunk.tile_count = 0
			chunk.tile_refs.clear()
			chunk.instance_to_key.clear()

			# Handle mesh rebuild if needed
			if force_mesh_rebuild:
				chunk.multimesh.visible_instance_count = 0
				chunk.multimesh.instance_count = 0
				if is_repeat:
					chunk.multimesh.mesh = TileMeshGenerator.create_prism_mesh_repeat(grid_size)
				else:
					chunk.multimesh.mesh = TileMeshGenerator.create_prism_mesh(grid_size)
				chunk.multimesh.instance_count = MultiMeshTileChunkBase.MAX_TILES
			else:
				chunk.multimesh.visible_instance_count = 0
				# CRITICAL FIX: ALWAYS ensure REPEAT chunks have the correct mesh
				# This handles chunks that were created before the REPEAT fix was applied
				if is_repeat:
					chunk.multimesh.mesh = TileMeshGenerator.create_prism_mesh_repeat(grid_size)

			# Append to correct array based on texture mode
			if is_repeat:
				_prism_repeat_chunks.append(chunk)
			else:
				_prism_chunks.append(chunk)

	# STEP 3: Sort chunk arrays by name index to maintain order
	_quad_chunks.sort_custom(func(a, b):
		var idx_a: int = int(a.name.replace("SquareChunk_", "").replace("TileChunk_", ""))
		var idx_b: int = int(b.name.replace("SquareChunk_", "").replace("TileChunk_", ""))
		return idx_a < idx_b
	)

	# When chunks are loaded from scene file, chunk_index resets to -1 (default value)
	# because it's not an @export property. Without this, ALL TileRefs created from
	# these chunks will have chunk_index=-1, causing orphaned reference errors.
	for i in range(_quad_chunks.size()):
		_quad_chunks[i].chunk_index = i
		if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
			print("Updated quad chunk '%s' → chunk_index=%d" % [_quad_chunks[i].name, i])

	_triangle_chunks.sort_custom(func(a, b):
		var idx_a: int = int(a.name.replace("TriangleChunk_", "").replace("TileChunk_", ""))
		var idx_b: int = int(b.name.replace("TriangleChunk_", "").replace("TileChunk_", ""))
		return idx_a < idx_b
	)

	# Update chunk_index to match sorted array positions
	for i in range(_triangle_chunks.size()):
		_triangle_chunks[i].chunk_index = i
		if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
			print(" Updated triangle chunk '%s' → chunk_index=%d" % [_triangle_chunks[i].name, i])

	# Sort and index box chunks
	_box_chunks.sort_custom(func(a, b):
		var idx_a: int = int(a.name.replace("BoxChunk_", "").replace("TileChunk_", ""))
		var idx_b: int = int(b.name.replace("BoxChunk_", "").replace("TileChunk_", ""))
		return idx_a < idx_b
	)
	for i in range(_box_chunks.size()):
		_box_chunks[i].chunk_index = i
		if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
			print(" Updated box chunk '%s' → chunk_index=%d" % [_box_chunks[i].name, i])

	# Sort and index prism chunks
	_prism_chunks.sort_custom(func(a, b):
		var idx_a: int = int(a.name.replace("PrismChunk_", "").replace("TileChunk_", ""))
		var idx_b: int = int(b.name.replace("PrismChunk_", "").replace("TileChunk_", ""))
		return idx_a < idx_b
	)
	for i in range(_prism_chunks.size()):
		_prism_chunks[i].chunk_index = i
		if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
			print(" Updated prism chunk '%s' → chunk_index=%d" % [_prism_chunks[i].name, i])

	# Sort and index box REPEAT chunks (TEXTURE_REPEAT mode)
	_box_repeat_chunks.sort_custom(func(a, b):
		var idx_a: int = int(a.name.replace("BoxRepeatChunk_", "").replace("TileChunk_", ""))
		var idx_b: int = int(b.name.replace("BoxRepeatChunk_", "").replace("TileChunk_", ""))
		return idx_a < idx_b
	)
	for i in range(_box_repeat_chunks.size()):
		_box_repeat_chunks[i].chunk_index = i
		if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
			print(" Updated box repeat chunk '%s' → chunk_index=%d" % [_box_repeat_chunks[i].name, i])

	# Sort and index prism REPEAT chunks (TEXTURE_REPEAT mode)
	_prism_repeat_chunks.sort_custom(func(a, b):
		var idx_a: int = int(a.name.replace("PrismRepeatChunk_", "").replace("TileChunk_", ""))
		var idx_b: int = int(b.name.replace("PrismRepeatChunk_", "").replace("TileChunk_", ""))
		return idx_a < idx_b
	)
	for i in range(_prism_repeat_chunks.size()):
		_prism_repeat_chunks[i].chunk_index = i
		if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
			print(" Updated prism repeat chunk '%s' → chunk_index=%d" % [_prism_repeat_chunks[i].name, i])

	# STEP 4: Rebuild saved_tiles lookup dictionary from columnar storage
	_saved_tiles_lookup.clear()
	var tile_count: int = get_tile_count()
	for i in range(tile_count):
		# Read position and orientation from columnar storage to build key
		var grid_pos: Vector3 = _tile_positions[i]
		var flags: int = _tile_flags[i]
		var orientation: int = flags & 0x1F  # Bits 0-4
		var tile_key: Variant = GlobalUtil.make_tile_key(grid_pos, orientation)
		_saved_tiles_lookup[tile_key] = i

	# Auto-migrate old string keys to integer keys (backward compatibility)
	# Detects if scene was saved with old string key format and converts to integer keys
	if _saved_tiles_lookup.size() > 0:
		var first_key: Variant = _saved_tiles_lookup.keys()[0]
		if first_key is String:
			_saved_tiles_lookup = GlobalUtil.migrate_placement_data(_saved_tiles_lookup)

	# STEP 5: Recreate tiles from saved data (READ DIRECTLY FROM COLUMNAR STORAGE)
	# ⚠️ DO NOT use get_tile_at() here - it creates deprecated TilePlacerData objects
	# Read columnar arrays directly for correct default handling
	for i in range(tile_count):
		if not tileset_texture:
			push_warning("Cannot rebuild tiles: no tileset texture")
			break

		# Read position directly from columnar storage
		var grid_position: Vector3 = _tile_positions[i]

		# Read UV rect directly (4 floats per tile)
		var uv_idx: int = i * 4
		var uv_rect := Rect2(
			_tile_uv_rects[uv_idx],
			_tile_uv_rects[uv_idx + 1],
			_tile_uv_rects[uv_idx + 2],
			_tile_uv_rects[uv_idx + 3]
		)

		# Unpack flags directly
		var flags: int = _tile_flags[i]
		var orientation: int = flags & 0x1F  # Bits 0-4
		var mesh_rotation: int = (flags >> 5) & 0x3  # Bits 5-6
		var mesh_mode: int = (flags >> 7) & 0x3  # Bits 7-8
		var is_face_flipped: bool = bool(flags & (1 << 9))  # Bit 9
		var texture_repeat_mode: int = (flags >> 18) & 0x1  # Bit 18: TEXTURE_REPEAT mode

		# Read transform params if present (CRITICAL: Proper default handling)
		var spin_angle_rad: float = 0.0
		var tilt_angle_rad: float = 0.0
		var diagonal_scale: float = 0.0
		var tilt_offset_factor: float = 0.0
		var depth_scale: float = 1.0  # DEFAULT for backward compatibility!

		var transform_idx: int = _tile_transform_indices[i]
		if transform_idx >= 0:
			# Custom params stored - read all 5 floats
			var param_base: int = transform_idx * 5
			spin_angle_rad = _tile_transform_data[param_base]
			tilt_angle_rad = _tile_transform_data[param_base + 1]
			diagonal_scale = _tile_transform_data[param_base + 2]
			tilt_offset_factor = _tile_transform_data[param_base + 3]
			depth_scale = _tile_transform_data[param_base + 4]
		# else: use defaults (depth_scale stays 1.0 for old tiles)

		# Get or create appropriate chunk type (texture_repeat_mode for BOX/PRISM)
		var chunk: MultiMeshTileChunkBase = get_or_create_chunk(mesh_mode, texture_repeat_mode)
		var instance_index: int = chunk.multimesh.visible_instance_count

		# Build transform using saved parameters
		var transform: Transform3D = GlobalUtil.build_tile_transform(
			grid_position,
			orientation,
			mesh_rotation,
			grid_size,
			is_face_flipped,
			spin_angle_rad,
			tilt_angle_rad,
			diagonal_scale,
			tilt_offset_factor,
			mesh_mode,
			depth_scale
		)

		# Apply flat tile orientation offset (always, for flat tiles only)
		# Each orientation pushes slightly along its surface normal to prevent Z-fighting
		var offset: Vector3 = GlobalUtil.calculate_flat_tile_offset(orientation, mesh_mode)
		transform.origin += offset

		chunk.multimesh.set_instance_transform(instance_index, transform)

		# Set UV data
		var atlas_size: Vector2 = tileset_texture.get_size()
		var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
		var custom_data: Color = uv_data.uv_color
		chunk.multimesh.set_instance_custom_data(instance_index, custom_data)

		# Increment visible count
		chunk.multimesh.visible_instance_count += 1
		chunk.tile_count += 1

		# Create tile ref with chunk-type-specific indexing
		var tile_ref: TileRef = TileRef.new()
		tile_ref.mesh_mode = mesh_mode
		tile_ref.texture_repeat_mode = texture_repeat_mode  # For BOX/PRISM chunk selection

		# FIX P1-6: Use chunk.chunk_index directly (O(1)) instead of .find() (O(n))
		# The chunk_index is already set during chunk creation in _create_or_get_chunk_*()
		tile_ref.chunk_index = chunk.chunk_index

		tile_ref.instance_index = instance_index
		tile_ref.uv_rect = uv_rect

		# Add to lookup using compound key
		var tile_key: int = GlobalUtil.make_tile_key(grid_position, orientation)
		_tile_lookup[tile_key] = tile_ref
		chunk.tile_refs[tile_key] = instance_index
		chunk.instance_to_key[instance_index] = tile_key

	_is_rebuilt = true
	_update_material()

func _update_material() -> void:
	if tileset_texture:
		# Always recreate materials to ensure filter mode is applied
		_shared_material = GlobalUtil.create_tile_material(tileset_texture, texture_filter_mode, render_priority)
		_shared_material_double_sided = GlobalUtil.create_tile_material(
			tileset_texture, texture_filter_mode, render_priority, false)

		# Update material on all square chunks
		for chunk in _quad_chunks:
			if chunk:
				chunk.material_override = _shared_material
				chunk.cast_shadow = _chunk_shadow_casting

		# Update material on all triangle chunks
		for chunk in _triangle_chunks:
			if chunk:
				chunk.material_override = _shared_material
				chunk.cast_shadow = _chunk_shadow_casting

		# Update material on all box chunks (no backfaces)
		for chunk in _box_chunks:
			if chunk:
				chunk.material_override = _shared_material_double_sided
				chunk.cast_shadow = _chunk_shadow_casting

		# Update material on all prism chunks (no backfaces)
		for chunk in _prism_chunks:
			if chunk:
				chunk.material_override = _shared_material_double_sided
				chunk.cast_shadow = _chunk_shadow_casting

		# Update material on all box REPEAT chunks (TEXTURE_REPEAT mode)
		for chunk in _box_repeat_chunks:
			if chunk:
				chunk.material_override = _shared_material_double_sided
				chunk.cast_shadow = _chunk_shadow_casting

		# Update material on all prism REPEAT chunks (TEXTURE_REPEAT mode)
		for chunk in _prism_repeat_chunks:
			if chunk:
				chunk.material_override = _shared_material_double_sided
				chunk.cast_shadow = _chunk_shadow_casting


## Update the UV rect of an existing tile (for autotiling neighbor updates)
## Returns true if update succeeded
func update_tile_uv(tile_key: int, new_uv: Rect2) -> bool:
	if not Engine.is_editor_hint():
		push_warning("update_tile_uv: Not in editor mode")
		return false

	# Get tile reference
	var tile_ref: TileRef = _tile_lookup.get(tile_key, null)
	if tile_ref == null:
		push_warning("update_tile_uv: tile_key ", tile_key, " not found in _tile_lookup (", _tile_lookup.size(), " entries)")
		return false

	# Get the chunk based on mesh mode
	var chunk: MultiMeshTileChunkBase = _get_chunk_by_ref(tile_ref)

	if chunk == null:
		push_warning("update_tile_uv: chunk is null for tile_key ", tile_key, " (chunk_index=", tile_ref.chunk_index, ")")
		return false

	# Calculate new UV data
	if not tileset_texture:
		push_warning("update_tile_uv: tileset_texture is null! Cannot update UV.")
		return false

	var atlas_size: Vector2 = tileset_texture.get_size()
	var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(new_uv, atlas_size)
	var custom_data: Color = uv_data.uv_color

	# Update the MultiMesh instance
	chunk.multimesh.set_instance_custom_data(tile_ref.instance_index, custom_data)

	# Update the TileRef
	tile_ref.uv_rect = new_uv

	# Update columnar storage if the tile exists there
	if _saved_tiles_lookup.has(tile_key):
		var tile_index: int = _saved_tiles_lookup[tile_key]
		if tile_index >= 0 and tile_index < get_tile_count():
			update_tile_uv_columnar(tile_index, new_uv)

	return true

func get_shared_material(debug_show_red_backfaces: bool) -> ShaderMaterial:
	# Ensure material exists before returning
	if not _shared_material and tileset_texture:
		_shared_material = GlobalUtil.create_tile_material(tileset_texture, texture_filter_mode, render_priority, debug_show_red_backfaces)
	return _shared_material

## Returns shared material with debug_show_backfaces disabled (for BOX_MESH/PRISM_MESH)
func get_shared_material_double_sided() -> ShaderMaterial:
	if not _shared_material_double_sided and tileset_texture:
		_shared_material_double_sided = GlobalUtil.create_tile_material(
			tileset_texture, texture_filter_mode, render_priority, false)
	return _shared_material_double_sided


## Gets or creates a chunk with available space based on mesh mode
## Returns a MultiMeshTileChunkBase with available space
func get_or_create_chunk(mesh_mode: GlobalConstants.MeshMode = GlobalConstants.MeshMode.FLAT_SQUARE, texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT) -> MultiMeshTileChunkBase:
	match mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE:
			return _get_or_create_square_chunk()
		GlobalConstants.MeshMode.FLAT_TRIANGULE:
			return _get_or_create_triangle_chunk()
		GlobalConstants.MeshMode.BOX_MESH:
			if texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
				return _get_or_create_box_repeat_chunk()
			return _get_or_create_box_chunk()
		GlobalConstants.MeshMode.PRISM_MESH:
			if texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
				return _get_or_create_prism_repeat_chunk()
			return _get_or_create_prism_chunk()
		_:
			push_warning("Unknown mesh mode: %d, falling back to FLAT_SQUARE" % mesh_mode)
			return _get_or_create_square_chunk()


func _get_or_create_square_chunk() -> SquareTileChunk:
	# Try to find existing square chunk with space
	for chunk in _quad_chunks:
		if chunk.has_space():
			return chunk

	# Create new square chunk
	var chunk := SquareTileChunk.new()
	chunk.chunk_index = _quad_chunks.size()
	chunk.name = "SquareChunk_%d" % chunk.chunk_index
	chunk.setup_mesh(grid_size)
	chunk.material_override = get_shared_material(false) #TODO: #DEBUG BACKFACE SHADER
	chunk.cast_shadow = _chunk_shadow_casting

	if not chunk.get_parent():
		add_child.bind(chunk, true).call_deferred()
		# (func(): chunk.owner = get_tree().edited_scene_root).call_deferred()#TODO: #DEBUG FILE SIZE

	_quad_chunks.append(chunk)
	return chunk


func _get_or_create_triangle_chunk() -> TriangleTileChunk:
	# Try to find existing triangle chunk with space
	for chunk in _triangle_chunks:
		if chunk.has_space():
			return chunk

	# Create new triangle chunk
	var chunk := TriangleTileChunk.new()
	chunk.chunk_index = _triangle_chunks.size()
	chunk.name = "TriangleChunk_%d" % chunk.chunk_index
	chunk.setup_mesh(grid_size)
	chunk.material_override = get_shared_material(false)
	chunk.cast_shadow = _chunk_shadow_casting

	if not chunk.get_parent():
		add_child.bind(chunk, true).call_deferred()
		# (func(): chunk.owner = get_tree().edited_scene_root).call_deferred()#TODO: #DEBUG FILE SIZE

	_triangle_chunks.append(chunk)
	return chunk


func _get_or_create_box_chunk() -> BoxTileChunk:
	# Try to find existing box chunk with space
	for chunk in _box_chunks:
		if chunk.has_space():
			return chunk

	# Create new box chunk
	var chunk := BoxTileChunk.new()
	chunk.chunk_index = _box_chunks.size()
	chunk.name = "BoxChunk_%d" % chunk.chunk_index
	chunk.setup_mesh(grid_size)
	chunk.material_override = get_shared_material_double_sided()
	chunk.cast_shadow = _chunk_shadow_casting

	if not chunk.get_parent():
		add_child.bind(chunk, true).call_deferred()
		# (func(): chunk.owner = get_tree().edited_scene_root).call_deferred()#TODO: #DEBUG FILE SIZE

	_box_chunks.append(chunk)
	return chunk


func _get_or_create_prism_chunk() -> PrismTileChunk:
	# Try to find existing prism chunk with space
	for chunk in _prism_chunks:
		if chunk.has_space():
			return chunk

	# Create new prism chunk
	var chunk := PrismTileChunk.new()
	chunk.chunk_index = _prism_chunks.size()
	chunk.name = "PrismChunk_%d" % chunk.chunk_index
	chunk.setup_mesh(grid_size)
	chunk.material_override = get_shared_material_double_sided()
	chunk.cast_shadow = _chunk_shadow_casting

	if not chunk.get_parent():
		add_child.bind(chunk, true).call_deferred()
		# (func(): chunk.owner = get_tree().edited_scene_root).call_deferred()#TODO: #DEBUG FILE SIZE

	_prism_chunks.append(chunk)
	return chunk


## Creates or returns a BOX chunk with REPEAT texture mode (full texture on all faces)
func _get_or_create_box_repeat_chunk() -> BoxTileChunk:
	print("[TEXTURE_REPEAT] BOX_REPEAT_CHUNK: Called, existing chunks=%d" % _box_repeat_chunks.size())
	# Try to find existing box repeat chunk with space
	for chunk in _box_repeat_chunks:
		if chunk.has_space():
			print("[TEXTURE_REPEAT] BOX_REPEAT_CHUNK: Reusing existing chunk '%s'" % chunk.name)
			return chunk

	# Create new box repeat chunk
	var chunk := BoxTileChunk.new()
	chunk.chunk_index = _box_repeat_chunks.size()
	chunk.name = "BoxRepeatChunk_%d" % chunk.chunk_index
	chunk.setup_mesh(grid_size, GlobalConstants.TextureRepeatMode.REPEAT)
	chunk.material_override = get_shared_material_double_sided()
	chunk.cast_shadow = _chunk_shadow_casting
	print("[TEXTURE_REPEAT] BOX_REPEAT_CHUNK: Created NEW chunk '%s' with REPEAT mode" % chunk.name)

	if not chunk.get_parent():
		add_child.bind(chunk, true).call_deferred()

	_box_repeat_chunks.append(chunk)
	return chunk


## Creates or returns a PRISM chunk with REPEAT texture mode (full texture on all faces)
func _get_or_create_prism_repeat_chunk() -> PrismTileChunk:
	print("[TEXTURE_REPEAT] PRISM_REPEAT_CHUNK: Called, existing chunks=%d" % _prism_repeat_chunks.size())
	# Try to find existing prism repeat chunk with space
	for chunk in _prism_repeat_chunks:
		if chunk.has_space():
			print("[TEXTURE_REPEAT] PRISM_REPEAT_CHUNK: Reusing existing chunk '%s'" % chunk.name)
			return chunk

	# Create new prism repeat chunk
	var chunk := PrismTileChunk.new()
	chunk.chunk_index = _prism_repeat_chunks.size()
	chunk.name = "PrismRepeatChunk_%d" % chunk.chunk_index
	chunk.setup_mesh(grid_size, GlobalConstants.TextureRepeatMode.REPEAT)
	chunk.material_override = get_shared_material_double_sided()
	chunk.cast_shadow = _chunk_shadow_casting
	print("[TEXTURE_REPEAT] PRISM_REPEAT_CHUNK: Created NEW chunk '%s' with REPEAT mode" % chunk.name)

	if not chunk.get_parent():
		add_child.bind(chunk, true).call_deferred()

	_prism_repeat_chunks.append(chunk)
	return chunk


## Helper to get chunk from TileRef based on mesh mode and texture repeat mode
## For BOX_MESH and PRISM_MESH, checks texture_repeat_mode to select correct chunk array
func _get_chunk_by_ref(tile_ref: TileRef) -> MultiMeshTileChunkBase:
	if tile_ref.chunk_index < 0:
		return null

	match tile_ref.mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE:
			if tile_ref.chunk_index < _quad_chunks.size():
				return _quad_chunks[tile_ref.chunk_index]
		GlobalConstants.MeshMode.FLAT_TRIANGULE:
			if tile_ref.chunk_index < _triangle_chunks.size():
				return _triangle_chunks[tile_ref.chunk_index]
		GlobalConstants.MeshMode.BOX_MESH:
			# Check texture repeat mode for BOX chunks
			if tile_ref.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
				if tile_ref.chunk_index < _box_repeat_chunks.size():
					return _box_repeat_chunks[tile_ref.chunk_index]
			else:
				if tile_ref.chunk_index < _box_chunks.size():
					return _box_chunks[tile_ref.chunk_index]
		GlobalConstants.MeshMode.PRISM_MESH:
			# Check texture repeat mode for PRISM chunks
			if tile_ref.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
				if tile_ref.chunk_index < _prism_repeat_chunks.size():
					return _prism_repeat_chunks[tile_ref.chunk_index]
			else:
				if tile_ref.chunk_index < _prism_chunks.size():
					return _prism_chunks[tile_ref.chunk_index]
	return null

##   Reindexes all chunks after removal to fix chunk_index corruption
## When chunks are removed, remaining chunks shift in array but chunk_index stays stale
## This causes tile_ref.chunk_index to point to wrong array positions
## Call this after removing chunks to restore consistency
func reindex_chunks() -> void:
	# FIX P1-13: Prevent concurrent reindex during tile operations
	if _reindex_in_progress:
		push_warning("reindex_chunks called while already reindexing - skipping to prevent corruption")
		return

	_reindex_in_progress = true

	# Reindex quad chunks
	for i in range(_quad_chunks.size()):
		var chunk: MultiMeshTileChunkBase = _quad_chunks[i]
		if chunk.chunk_index != i:
			if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
				print("Reindexing quad chunk: old_index=%d → new_index=%d (tile_count=%d)" % [chunk.chunk_index, i, chunk.tile_count])

			chunk.chunk_index = i

			# Update ALL TileRefs that point to this chunk
			for tile_key in chunk.tile_refs.keys():
				var tile_ref: TileRef = _tile_lookup.get(tile_key)
				if tile_ref:
					tile_ref.chunk_index = i
				else:
					push_warning("Reindex: tile_key %d in chunk.tile_refs but not in _tile_lookup" % tile_key)

	# Reindex triangle chunks
	for i in range(_triangle_chunks.size()):
		var chunk: MultiMeshTileChunkBase = _triangle_chunks[i]
		if chunk.chunk_index != i:
			if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
				print("Reindexing triangle chunk: old_index=%d → new_index=%d (tile_count=%d)" % [chunk.chunk_index, i, chunk.tile_count])

			chunk.chunk_index = i

			# Update ALL TileRefs that point to this chunk
			for tile_key in chunk.tile_refs.keys():
				var tile_ref: TileRef = _tile_lookup.get(tile_key)
				if tile_ref:
					tile_ref.chunk_index = i
				else:
					push_warning("Reindex: tile_key %d in chunk.tile_refs but not in _tile_lookup" % tile_key)

	# Reindex box chunks
	for i in range(_box_chunks.size()):
		var chunk: MultiMeshTileChunkBase = _box_chunks[i]
		if chunk.chunk_index != i:
			if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
				print("Reindexing box chunk: old_index=%d → new_index=%d (tile_count=%d)" % [chunk.chunk_index, i, chunk.tile_count])

			chunk.chunk_index = i

			# Update ALL TileRefs that point to this chunk
			for tile_key in chunk.tile_refs.keys():
				var tile_ref: TileRef = _tile_lookup.get(tile_key)
				if tile_ref:
					tile_ref.chunk_index = i
				else:
					push_warning("Reindex: tile_key %d in chunk.tile_refs but not in _tile_lookup" % tile_key)

	# Reindex prism chunks
	for i in range(_prism_chunks.size()):
		var chunk: MultiMeshTileChunkBase = _prism_chunks[i]
		if chunk.chunk_index != i:
			if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
				print("Reindexing prism chunk: old_index=%d → new_index=%d (tile_count=%d)" % [chunk.chunk_index, i, chunk.tile_count])

			chunk.chunk_index = i

			# Update ALL TileRefs that point to this chunk
			for tile_key in chunk.tile_refs.keys():
				var tile_ref: TileRef = _tile_lookup.get(tile_key)
				if tile_ref:
					tile_ref.chunk_index = i
				else:
					push_warning("Reindex: tile_key %d in chunk.tile_refs but not in _tile_lookup" % tile_key)

	# Reindex box REPEAT chunks (TEXTURE_REPEAT mode)
	for i in range(_box_repeat_chunks.size()):
		var chunk: MultiMeshTileChunkBase = _box_repeat_chunks[i]
		if chunk.chunk_index != i:
			if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
				print("Reindexing box repeat chunk: old_index=%d → new_index=%d (tile_count=%d)" % [chunk.chunk_index, i, chunk.tile_count])

			chunk.chunk_index = i

			# Update ALL TileRefs that point to this chunk
			for tile_key in chunk.tile_refs.keys():
				var tile_ref: TileRef = _tile_lookup.get(tile_key)
				if tile_ref:
					tile_ref.chunk_index = i
				else:
					push_warning("Reindex: tile_key %d in chunk.tile_refs but not in _tile_lookup" % tile_key)

	# Reindex prism REPEAT chunks (TEXTURE_REPEAT mode)
	for i in range(_prism_repeat_chunks.size()):
		var chunk: MultiMeshTileChunkBase = _prism_repeat_chunks[i]
		if chunk.chunk_index != i:
			if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
				print("Reindexing prism repeat chunk: old_index=%d → new_index=%d (tile_count=%d)" % [chunk.chunk_index, i, chunk.tile_count])

			chunk.chunk_index = i

			# Update ALL TileRefs that point to this chunk
			for tile_key in chunk.tile_refs.keys():
				var tile_ref: TileRef = _tile_lookup.get(tile_key)
				if tile_ref:
					tile_ref.chunk_index = i
				else:
					push_warning("Reindex: tile_key %d in chunk.tile_refs but not in _tile_lookup" % tile_key)

	_reindex_in_progress = false  # FIX P1-13: Reset flag when complete

## Gets the tile reference at a tile key (for removal/editing)
## Auto-rebuilds _tile_lookup from chunks if lookup fails
func get_tile_ref(tile_key: Variant) -> TileRef:
	var ref: TileRef = _tile_lookup.get(tile_key, null)

	#  If lookup fails, rebuild from chunks and retry
	if not ref:
		push_warning("TileMapLayer3D: TileRef not in _tile_lookup for key '", tile_key, "', rebuilding from chunks...")
		_rebuild_tile_lookup_from_chunks()
		ref = _tile_lookup.get(tile_key, null)

	return ref

## Adds a tile reference to the lookup
func add_tile_ref(tile_key: Variant, tile_ref: TileRef) -> void:
	_tile_lookup[tile_key] = tile_ref

## Removes a tile reference from the lookup
func remove_tile_ref(tile_key: Variant) -> void:
	_tile_lookup.erase(tile_key)

## Rebuilds _tile_lookup dictionary from current chunk data
##  Call this when tile_ref lookup fails to auto-recover from desync
## This regenerates all TileRef objects from the runtime chunk.tile_refs dictionaries
func _rebuild_tile_lookup_from_chunks() -> void:
	_tile_lookup.clear()

	# Rebuild from square chunks
	for chunk_index: int in range(_quad_chunks.size()):
		var chunk: SquareTileChunk = _quad_chunks[chunk_index]
		for tile_key: int in chunk.tile_refs.keys():
			var instance_index: int = chunk.tile_refs[tile_key]

			# Create TileRef from chunk data
			var tile_ref: TileRef = TileRef.new()
			tile_ref.chunk_index = chunk_index
			tile_ref.instance_index = instance_index
			tile_ref.mesh_mode = GlobalConstants.MeshMode.FLAT_SQUARE

			_tile_lookup[tile_key] = tile_ref

	# Rebuild from triangle chunks
	for chunk_index: int in range(_triangle_chunks.size()):
		var chunk: TriangleTileChunk = _triangle_chunks[chunk_index]
		for tile_key: int in chunk.tile_refs.keys():
			var instance_index: int = chunk.tile_refs[tile_key]

			# Create TileRef from chunk data
			var tile_ref: TileRef = TileRef.new()
			tile_ref.chunk_index = chunk_index
			tile_ref.instance_index = instance_index
			tile_ref.mesh_mode = GlobalConstants.MeshMode.FLAT_TRIANGULE

			_tile_lookup[tile_key] = tile_ref

	# Rebuild from box chunks (DEFAULT texture mode)
	for chunk_index: int in range(_box_chunks.size()):
		var chunk: BoxTileChunk = _box_chunks[chunk_index]
		for tile_key: int in chunk.tile_refs.keys():
			var instance_index: int = chunk.tile_refs[tile_key]

			# Create TileRef from chunk data
			var tile_ref: TileRef = TileRef.new()
			tile_ref.chunk_index = chunk_index
			tile_ref.instance_index = instance_index
			tile_ref.mesh_mode = GlobalConstants.MeshMode.BOX_MESH
			tile_ref.texture_repeat_mode = GlobalConstants.TextureRepeatMode.DEFAULT

			_tile_lookup[tile_key] = tile_ref

	# Rebuild from prism chunks (DEFAULT texture mode)
	for chunk_index: int in range(_prism_chunks.size()):
		var chunk: PrismTileChunk = _prism_chunks[chunk_index]
		for tile_key: int in chunk.tile_refs.keys():
			var instance_index: int = chunk.tile_refs[tile_key]

			# Create TileRef from chunk data
			var tile_ref: TileRef = TileRef.new()
			tile_ref.chunk_index = chunk_index
			tile_ref.instance_index = instance_index
			tile_ref.mesh_mode = GlobalConstants.MeshMode.PRISM_MESH
			tile_ref.texture_repeat_mode = GlobalConstants.TextureRepeatMode.DEFAULT

			_tile_lookup[tile_key] = tile_ref

	# Rebuild from box REPEAT chunks (TEXTURE_REPEAT mode)
	for chunk_index: int in range(_box_repeat_chunks.size()):
		var chunk: BoxTileChunk = _box_repeat_chunks[chunk_index]
		for tile_key: int in chunk.tile_refs.keys():
			var instance_index: int = chunk.tile_refs[tile_key]

			# Create TileRef from chunk data
			var tile_ref: TileRef = TileRef.new()
			tile_ref.chunk_index = chunk_index
			tile_ref.instance_index = instance_index
			tile_ref.mesh_mode = GlobalConstants.MeshMode.BOX_MESH
			tile_ref.texture_repeat_mode = GlobalConstants.TextureRepeatMode.REPEAT

			_tile_lookup[tile_key] = tile_ref

	# Rebuild from prism REPEAT chunks (TEXTURE_REPEAT mode)
	for chunk_index: int in range(_prism_repeat_chunks.size()):
		var chunk: PrismTileChunk = _prism_repeat_chunks[chunk_index]
		for tile_key: int in chunk.tile_refs.keys():
			var instance_index: int = chunk.tile_refs[tile_key]

			# Create TileRef from chunk data
			var tile_ref: TileRef = TileRef.new()
			tile_ref.chunk_index = chunk_index
			tile_ref.instance_index = instance_index
			tile_ref.mesh_mode = GlobalConstants.MeshMode.PRISM_MESH
			tile_ref.texture_repeat_mode = GlobalConstants.TextureRepeatMode.REPEAT

			_tile_lookup[tile_key] = tile_ref

## ✅ DIRECT COLUMNAR API - Save tile data directly (NO TilePlacerData)
## This is the PREFERRED way to save tiles - bypasses deprecated TilePlacerData
func save_tile_data_direct(
	grid_pos: Vector3,
	uv_rect: Rect2,
	orientation: int,
	mesh_rotation: int,
	mesh_mode: int,
	is_face_flipped: bool,
	terrain_id: int = -1,
	spin_angle: float = 0.0,
	tilt_angle: float = 0.0,
	diagonal_scale: float = 0.0,
	tilt_offset: float = 0.0,
	depth_scale: float = 0.1,
	texture_repeat_mode: int = 0  # TEXTURE_REPEAT: 0=DEFAULT, 1=REPEAT
) -> void:
	print("[TEXTURE_REPEAT] SAVE_DIRECT: grid_pos=%s, mesh_mode=%d, texture_repeat_mode=%d" % [grid_pos, mesh_mode, texture_repeat_mode])

	# Generate tile key for lookup
	var tile_key: Variant = GlobalUtil.make_tile_key(grid_pos, orientation)

	# Use lookup dictionary to check for existing tile
	# If tile already exists at this position, remove it first (will be re-added below)
	if _saved_tiles_lookup.has(tile_key):
		remove_saved_tile_data(tile_key)

	# Add tile to columnar storage
	var new_index: int = add_tile_direct(
		grid_pos, uv_rect, orientation, mesh_rotation, mesh_mode,
		is_face_flipped, terrain_id, spin_angle, tilt_angle,
		diagonal_scale, tilt_offset, depth_scale, texture_repeat_mode
	)
	_saved_tiles_lookup[tile_key] = new_index
	print("[TEXTURE_REPEAT] SAVE_DIRECT: Saved at columnar index=%d" % new_index)


## Saves tile data to persistent storage (called by placement manager)
## Uses columnar storage for efficient scene file serialization
## ⚠️ DEPRECATED - Use save_tile_data_direct() instead
## ⚠️ USES DEPRECATED TilePlacerData - Only for PLACEMENT operations
func save_tile_data(tile_data: TilePlacerData) -> void:
	# Generate tile key for lookup
	var tile_key: Variant = GlobalUtil.make_tile_key(tile_data.grid_position, tile_data.orientation)

	# Use lookup dictionary to check for existing tile
	# If tile already exists at this position, remove it first (will be re-added below)
	if _saved_tiles_lookup.has(tile_key):
		remove_saved_tile_data(tile_key)

	# Add tile to columnar storage
	var new_index: int = add_tile_columnar(tile_data)
	_saved_tiles_lookup[tile_key] = new_index

## Removes saved tile data (called by placement manager on erase)
## Uses columnar storage for efficient scene file serialization
func remove_saved_tile_data(tile_key: Variant) -> void:
	# Use lookup dictionary instead of O(N) search
	if not _saved_tiles_lookup.has(tile_key):
		return  # Tile not found

	var tile_index: int = _saved_tiles_lookup[tile_key]

	# Remove from columnar storage
	remove_tile_columnar(tile_index)
	_saved_tiles_lookup.erase(tile_key)

	# IMPORTANT: Update lookup indices for all tiles after the removed one
	# because their indices shifted down by 1
	for key in _saved_tiles_lookup.keys():
		if _saved_tiles_lookup[key] > tile_index:
			_saved_tiles_lookup[key] -= 1


## Updates the terrain_id on a saved tile (for autotile persistence)
## Called by AutotilePlacementExtension after setting terrain_id on placement_data
## Uses columnar storage for efficient scene file serialization
func update_saved_tile_terrain(tile_key: int, terrain_id: int) -> void:
	if not _saved_tiles_lookup.has(tile_key):
		return
	var tile_index: int = _saved_tiles_lookup[tile_key]
	if tile_index >= 0 and tile_index < get_tile_count():
		update_tile_terrain_columnar(tile_index, terrain_id)


func clear_collision_shapes() -> void:
	# FIRST: Delete external .res file independently (doesn't require collision body to exist)
	_delete_external_collision_file()

	# THEN: Clean up any collision bodies in the scene
	var _current_collisions_bodies: Array[StaticCollisionBody3D] = []

	for body in self.get_children():
		if body is StaticCollisionBody3D:
			_current_collisions_bodies.append(body)

	for body in _current_collisions_bodies:
		if is_instance_valid(body):
			# Remove from parent and free
			if body.get_parent():
				body.get_parent().remove_child(body)
			body.queue_free()

	_current_collisions_bodies.clear()


## Deletes external .res collision file by computing the expected path
## This works even if no collision body exists in the scene
## File pattern: {SceneName}_CollisionData/{SceneName}_{NodeName}_collision.res
func _delete_external_collision_file() -> void:
	if not Engine.is_editor_hint():
		return

	# Get scene path to compute collision file location
	var tree: SceneTree = get_tree()
	if not tree:
		return

	var scene_root: Node = tree.edited_scene_root
	if not scene_root:
		return

	var scene_path: String = scene_root.scene_file_path
	if scene_path.is_empty():
		return

	var scene_name: String = scene_path.get_file().get_basename()
	var scene_dir: String = scene_path.get_base_dir()

	# Compute expected collision file path
	var collision_folder_name: String = scene_name + "_CollisionData"
	var collision_folder: String = scene_dir.path_join(collision_folder_name)
	var collision_filename: String = scene_name + "_" + self.name + "_collision.res"
	var collision_path: String = collision_folder.path_join(collision_filename)

	# Check if file exists and delete it
	if FileAccess.file_exists(collision_path):
		var dir: DirAccess = DirAccess.open(collision_folder)
		if dir:
			var error: Error = dir.remove(collision_filename)
			if error == OK:
				print("Deleted external collision file: ", collision_path)
			else:
				push_warning("Failed to delete collision file: ", collision_path, " Error: ", error)
	else:
		# Debug: File doesn't exist at expected location
		pass  # Silently skip if file doesn't exist


## LEGACY: Deletes external .res collision file from collision body's resource_path
## Kept for backward compatibility with scenes that have different file locations
func _delete_external_collision_resource(body: StaticCollisionBody3D) -> void:
	for child in body.get_children():
		if not (child is CollisionShape3D) or not child.shape:
			continue

		var resource_path: String = child.shape.resource_path
		if resource_path.is_empty():
			continue

		# Verify this is our collision file format: {Scene}_{NodeName}_collision.res
		# Only delete if it matches THIS node's name exactly
		var expected_suffix: String = "_" + self.name + "_collision.res"
		if not resource_path.ends_with(expected_suffix):
			continue

		# Delete the external file
		var dir: DirAccess = DirAccess.open(resource_path.get_base_dir())
		if dir:
			var error: Error = dir.remove(resource_path.get_file())
			if error == OK:
				print("Deleted external collision (from body): ", resource_path)
			else:
				push_warning("Failed to delete collision file: ", resource_path)

## Returns whether a tile has collision generated
# func has_collision_for_tile(tile_key: String) -> bool:
# 	return _collision_tile_keys.has(tile_key)

## Clears the collision shape cache (useful when switching tilesets)
func clear_collision_cache() -> void:
	CollisionGenerator.clear_shape_cache()
	# print("TileMapLayer3D: Collision shape cache cleared")

# ==============================================================================
# BOX ERASE HIGHLIGHT OVERLAY SYSTEM
# ==============================================================================

## Creates the highlight overlay MultiMesh for Box Erase feature
## This creates a pool of semi-transparent boxes that can be positioned over tiles
## Editor-only - not saved to scene
func _create_highlight_overlay() -> void:
	# Create MultiMesh for highlight boxes
	_highlight_multimesh = MultiMesh.new()
	_highlight_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_highlight_multimesh.instance_count = GlobalConstants.MAX_HIGHLIGHTED_TILES
	_highlight_multimesh.visible_instance_count = 0

	# Create thin box mesh for highlighting (slightly larger than tile)
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(grid_size * 1.05, grid_size * 1.05, 0.1)  # 5% larger, thin overlay
	_highlight_multimesh.mesh = box

	# Create instance node
	_highlight_instance = MultiMeshInstance3D.new()
	_highlight_instance.name = "TileHighlightOverlay"
	_highlight_instance.multimesh = _highlight_multimesh
	_highlight_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Apply highlight material using GlobalUtil
	_highlight_instance.material_override = GlobalUtil.create_highlight_material()

	add_child(_highlight_instance)
	# DO NOT set owner - highlight overlay is editor-only, not saved to scene

## Highlights tiles by positioning overlay boxes at their transforms
## @param tile_keys: Array of tile keys to highlight (format: "x,y,z,orientation")
func highlight_tiles(tile_keys: Array[int]) -> void:
	if not _highlight_multimesh:
		return

	# Store highlighted keys for potential later use
	_highlighted_tile_keys = tile_keys.duplicate()

	# Limit to available instance count
	var count: int = mini(tile_keys.size(), _highlight_multimesh.instance_count)
	_highlight_multimesh.visible_instance_count = count

	# Position highlight boxes at each tile's position
	for i: int in range(count):
		var tile_key: int = tile_keys[i]

		# Unpack integer tile key to get grid position and orientation
		var parsed: Dictionary = TileKeySystem.unpack_tile_key(tile_key)

		var grid_pos: Vector3 = parsed.position
		var orientation: int = parsed.orientation

		# Get saved tile data to retrieve rotation and flip state
		# ⚠️ TODO: Refactor to read columnar directly instead of using deprecated get_tile_at()
		var tile_data: TilePlacerData = null
		if _saved_tiles_lookup.has(tile_key):
			var tile_index: int = _saved_tiles_lookup[tile_key]
			if tile_index >= 0 and tile_index < get_tile_count():
				tile_data = get_tile_at(tile_index)  # DEPRECATED but acceptable for editor highlights

		if not tile_data:
			continue

		# Build transform using SAME method as actual tiles
		var tile_transform: Transform3D = GlobalUtil.build_tile_transform(
			grid_pos,
			orientation,
			tile_data.mesh_rotation,  # Q/E rotation
			grid_size,
			tile_data.is_face_flipped  # F key flip
		)

		# Create highlight transform (same transform, with rotation correction for BoxMesh)
		var highlight_transform: Transform3D = tile_transform

		#Rotate 90 degrees around X-axis to align BoxMesh with QuadMesh orientation
		# BoxMesh and QuadMesh have different default axis orientations
		var rotation_correction: Basis = Basis(Vector3.RIGHT, deg_to_rad(-90.0))
		highlight_transform.basis = highlight_transform.basis * rotation_correction

		# Offset slightly outward along surface normal to prevent z-fighting
		var surface_normal: Vector3 = highlight_transform.basis.y.normalized()
		highlight_transform.origin += surface_normal * 0.01  # 1cm offset

		# Set highlight instance transform
		_highlight_multimesh.set_instance_transform(i, highlight_transform)

## Clears all tile highlights
func clear_highlights() -> void:
	if _highlight_multimesh:
		_highlight_multimesh.visible_instance_count = 0
		_highlighted_tile_keys.clear()

# ==============================================================================
# BLOCKED POSITION HIGHLIGHT (Out-of-bounds warning)
# ==============================================================================

## Creates the blocked position highlight overlay (bright red box)
## Used to show when cursor is outside valid coordinate range (±3,276.7)
## Editor-only - not saved to scene
func _create_blocked_highlight_overlay() -> void:
	# Create MultiMesh for blocked highlight (single instance only)
	_blocked_highlight_multimesh = MultiMesh.new()
	_blocked_highlight_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_blocked_highlight_multimesh.instance_count = 1  # Only need one for cursor position
	_blocked_highlight_multimesh.visible_instance_count = 0

	# Create box mesh for blocked highlight (same size as tiles)
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(grid_size * 1.1, grid_size * 1.1, 0.15)  # 10% larger, slightly thicker
	_blocked_highlight_multimesh.mesh = box

	# Create instance node
	_blocked_highlight_instance = MultiMeshInstance3D.new()
	_blocked_highlight_instance.name = "BlockedPositionHighlight"
	_blocked_highlight_instance.multimesh = _blocked_highlight_multimesh
	_blocked_highlight_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Apply blocked highlight material (bright red)
	_blocked_highlight_instance.material_override = GlobalUtil.create_blocked_highlight_material()

	add_child(_blocked_highlight_instance)
	# DO NOT set owner - highlight overlay is editor-only, not saved to scene

## Shows a blocked position highlight at the given grid position
## Replaces the normal tile preview to indicate placement is not allowed
## @param grid_pos: Grid position that is blocked
## @param orientation: Tile orientation (0-17)
func show_blocked_highlight(grid_pos: Vector3, orientation: int) -> void:
	if not _blocked_highlight_multimesh:
		return

	# Build transform for the blocked position
	var blocked_transform: Transform3D = GlobalUtil.build_tile_transform(
		grid_pos,
		orientation,
		0,  # No rotation
		grid_size,
		false  # No flip
	)

	# Rotate 90 degrees around X-axis to align BoxMesh with QuadMesh orientation
	var rotation_correction: Basis = Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	blocked_transform.basis = blocked_transform.basis * rotation_correction

	# Offset slightly outward along surface normal to prevent z-fighting
	var surface_normal: Vector3 = blocked_transform.basis.y.normalized()
	blocked_transform.origin += surface_normal * 0.02  # 2cm offset (more visible than regular highlight)

	# Set the transform and show
	_blocked_highlight_multimesh.set_instance_transform(0, blocked_transform)
	_blocked_highlight_multimesh.visible_instance_count = 1
	_is_blocked_highlight_visible = true

## Clears the blocked position highlight
func clear_blocked_highlight() -> void:
	if _blocked_highlight_multimesh:
		_blocked_highlight_multimesh.visible_instance_count = 0
		_is_blocked_highlight_visible = false

## Returns whether the blocked highlight is currently visible
func is_blocked_highlight_visible() -> bool:
	return _is_blocked_highlight_visible

# ==============================================================================
# CONFIGURATION WARNINGS
# ==============================================================================

## Returns configuration warnings to display in the Godot Inspector
## Shows warnings for missing texture, excessive tile count, or out-of-bounds tiles
## FIX P2-24: Uses caching to avoid O(n) tile iteration on every Inspector update
func _get_configuration_warnings() -> PackedStringArray:
	# Return cached warnings if still valid
	if not _warnings_dirty:
		return _cached_warnings

	_cached_warnings.clear()

	# Check 1: No tileset texture configured
	if not settings or not settings.tileset_texture:
		_cached_warnings.push_back("No tileset texture configured. Assign a texture in the Inspector (Settings > Tileset Texture).")

	# Check 2: Tile count exceeds recommended maximum
	# Use get_tile_count() - this is the authoritative runtime count
	# The columnar storage is updated during runtime tile operations
	var total_tiles: int = get_tile_count()
	if total_tiles > GlobalConstants.MAX_RECOMMENDED_TILES:
		_cached_warnings.push_back("Tile count (%d) exceeds recommended maximum (%d). Performance may degrade. Consider using multiple TileMapLayer3D nodes." % [
			total_tiles,
			GlobalConstants.MAX_RECOMMENDED_TILES
		])

	# Check 3: Tiles outside valid coordinate range
	var out_of_bounds_count: int = 0
	for i in range(total_tiles):
		var grid_pos: Vector3 = _tile_positions[i]
		if not TileKeySystem.is_position_valid(grid_pos):
			out_of_bounds_count += 1

	if out_of_bounds_count > 0:
		_cached_warnings.push_back("Found %d tiles outside valid coordinate range (±%.1f). These tiles may display incorrectly." % [
			out_of_bounds_count,
			GlobalConstants.MAX_GRID_RANGE
		])

	_warnings_dirty = false
	return _cached_warnings


## FIX P2-24: Invalidate warning cache when tile data changes
func _invalidate_warnings() -> void:
	_warnings_dirty = true
	update_configuration_warnings()
# ==============================================================================
# LEGACY PROPERTY MIGRATION
# ==============================================================================

# ## Migrates old @export properties to new settings Resource
# ## Called once on _ready() for scenes saved with old property format
# ## This allows backward compatibility with existing scenes
# func _migrate_legacy_properties() -> void:
# 	# Check if this is a legacy scene (has old properties but no settings Resource)
# 	# NOTE: Old properties would have been exported but are now regular vars
# 	# We can't directly detect them, but if settings exists, no migration needed
# 	if settings and settings.tileset_texture:
# 		return  # Already using new format

# 	# If settings exists but is empty, check if we had a texture loaded previously
# 	# This happens when reopening an old scene that was never migrated
# 	var needs_migration: bool = false

# 	# Check if we have data that suggests this was a working scene
# 	if saved_tiles.size() > 0:
# 		needs_migration = true

# 	if not needs_migration:
# 		return  # Nothing to migrate

# 	# print("TileMapLayer3D: Migrating legacy properties to settings Resource...")

# 	# Ensure settings Resource exists
# 	if not settings:
# 		settings = TileMapLayerSettings.new()

# 	# NOTE: Since old @export properties are now regular vars, they'll have default values
# 	# We can't migrate them automatically. User will need to re-set texture in Inspector.
# 	# This is acceptable as it only affects old scenes opened for the first time.

# 	# print("TileMapLayer3D: Migration complete. Please re-configure texture and settings in Inspector if needed.")

# ==============================================================================
# COLUMNAR STORAGE - Migration and Access Functions
# ==============================================================================

## One-time migration from Array[TilePlacerData] to columnar storage
## ⚠️ USES DEPRECATED TilePlacerData - ONLY for migration from old format
## This is the ONLY place where reading TilePlacerData from saved_tiles[] is acceptable
func _migrate_to_columnar_storage() -> void:
	if saved_tiles.is_empty():
		return

	print("TileMapLayer3D: Migrating %d tiles to columnar storage..." % saved_tiles.size())

	var count: int = saved_tiles.size()
	_tile_positions.resize(count)
	_tile_uv_rects.resize(count * 4)
	_tile_flags.resize(count)
	_tile_transform_indices.resize(count)

	var transform_entries: Array[PackedFloat32Array] = []

	for i in range(count):
		var tile: TilePlacerData = saved_tiles[i]

		# Store position
		_tile_positions[i] = tile.grid_position

		# Store UV rect (4 floats)
		var uv_idx: int = i * 4
		_tile_uv_rects[uv_idx] = tile.uv_rect.position.x
		_tile_uv_rects[uv_idx + 1] = tile.uv_rect.position.y
		_tile_uv_rects[uv_idx + 2] = tile.uv_rect.size.x
		_tile_uv_rects[uv_idx + 3] = tile.uv_rect.size.y

		# Pack flags into single int32
		_tile_flags[i] = _pack_tile_flags(tile)

		# Check for non-default transform params
		# IMPORTANT: depth_scale sparse storage threshold is 1.0 for backward compatibility
		# (Old tiles saved with depth=1.0 were not stored, so we must keep 1.0 as "default" marker)
		# New UI default is 0.1, but storage checks against 1.0 to preserve old scenes
		var has_params: bool = (
			tile.spin_angle_rad != 0.0 or
			tile.tilt_angle_rad != 0.0 or
			tile.diagonal_scale != 0.0 or
			tile.tilt_offset_factor != 0.0 or
			tile.depth_scale != 1.0
		)

		if has_params:
			_tile_transform_indices[i] = transform_entries.size()
			var params := PackedFloat32Array([
				tile.spin_angle_rad,
				tile.tilt_angle_rad,
				tile.diagonal_scale,
				tile.tilt_offset_factor,
				tile.depth_scale
			])
			transform_entries.append(params)
		else:
			_tile_transform_indices[i] = -1

	# Flatten transform entries
	_tile_transform_data.clear()
	for params in transform_entries:
		_tile_transform_data.append_array(params)

	# Clear old storage
	saved_tiles.clear()

	print("TileMapLayer3D: Migration complete! %d tiles, %d with transform params" % [count, transform_entries.size()])


## ⚠️ DEPRECATED - Use _pack_flags_direct() instead
## ⚠️ USES DEPRECATED TilePlacerData - Only for MIGRATION operations
func _pack_tile_flags(tile: TilePlacerData) -> int:
	var flags: int = 0
	flags |= (tile.orientation & 0x1F)                  # Bits 0-4
	flags |= (tile.mesh_rotation & 0x3) << 5            # Bits 5-6
	flags |= (tile.mesh_mode & 0x3) << 7                # Bits 7-8
	flags |= (1 if tile.is_face_flipped else 0) << 9    # Bit 9
	flags |= ((tile.terrain_id + 128) & 0xFF) << 10     # Bits 10-17
	flags |= (tile.texture_repeat_mode & 0x1) << 18     # Bit 18: texture repeat mode
	print("[TEXTURE_REPEAT] PACK_FLAGS: texture_repeat_mode=%d → bit18=%d, flags=%d" % [tile.texture_repeat_mode, (flags >> 18) & 1, flags])
	return flags


## Unpacks int32 flags into tile properties
## ⚠️ USES DEPRECATED TilePlacerData - Only for get_tile_at() compatibility
func _unpack_tile_flags(flags: int, tile: TilePlacerData) -> void:
	tile.orientation = flags & 0x1F
	tile.mesh_rotation = (flags >> 5) & 0x3
	tile.mesh_mode = (flags >> 7) & 0x3
	tile.is_face_flipped = ((flags >> 9) & 0x1) == 1
	tile.terrain_id = ((flags >> 10) & 0xFF) - 128
	tile.texture_repeat_mode = (flags >> 18) & 0x1  # Bit 18: texture repeat mode
	print("[TEXTURE_REPEAT] UNPACK_FLAGS: flags=%d → texture_repeat_mode=%d" % [flags, tile.texture_repeat_mode])


## Returns the number of tiles stored
func get_tile_count() -> int:
	return _tile_positions.size()


## ⚠️⚠️⚠️ DEPRECATED - DO NOT USE ⚠️⚠️⚠️
## Gets tile data at index as TilePlacerData (for compatibility ONLY)
##
## ❌ DO NOT USE THIS IN NEW CODE
## This creates deprecated TilePlacerData objects with wrong defaults
## causing bugs with backward compatibility
##
## ✅ USE INSTEAD: Read columnar arrays directly in your code
## See _rebuild_chunks_from_saved_data() for correct pattern
func get_tile_at(index: int) -> TilePlacerData:
	# Bounds check for index
	if index < 0 or index >= _tile_positions.size():
		push_error("get_tile_at: Index %d out of bounds (size=%d)" % [index, _tile_positions.size()])
		return null

	var tile := TilePlacerData.new()
	tile.grid_position = _tile_positions[index]

	var uv_idx: int = index * 4
	# Bounds check for UV array
	if uv_idx + 3 >= _tile_uv_rects.size():
		push_error("get_tile_at: UV index %d out of bounds (size=%d)" % [uv_idx, _tile_uv_rects.size()])
		return null

	tile.uv_rect = Rect2(
		_tile_uv_rects[uv_idx],
		_tile_uv_rects[uv_idx + 1],
		_tile_uv_rects[uv_idx + 2],
		_tile_uv_rects[uv_idx + 3]
	)

	_unpack_tile_flags(_tile_flags[index], tile)

	# Get transform params if non-default
	var transform_idx: int = _tile_transform_indices[index]
	if transform_idx >= 0:
		var param_base: int = transform_idx * 5  # 5 floats per entry

		# FIX P0-1: Validate transform data format before accessing
		# Scenes saved with old 4-float format will fail this check
		var expected_size: int = param_base + 5
		if _tile_transform_data.size() < expected_size:
			push_error("get_tile_at: Transform data format mismatch at index %d. Expected %d floats, have %d. Scene may use old 4-float format - see CLAUDE.md for migration." % [index, expected_size, _tile_transform_data.size()])
			# Return tile with default transform params rather than crashing
			tile.depth_scale = 1.0
			return tile

		# Read all 5 params (assumes current 5-float format)
		tile.spin_angle_rad = _tile_transform_data[param_base]
		tile.tilt_angle_rad = _tile_transform_data[param_base + 1]
		tile.diagonal_scale = _tile_transform_data[param_base + 2]
		tile.tilt_offset_factor = _tile_transform_data[param_base + 3]
		tile.depth_scale = _tile_transform_data[param_base + 4]
	else:
		# BACKWARD COMPATIBILITY: No custom params stored
		# This means tile used old defaults when saved
		# depth_scale sparse threshold is 1.0, so tiles without custom params get 1.0
		tile.depth_scale = 1.0

	return tile


## ⚠️ DEPRECATED - Use add_tile_direct() instead
## ⚠️ USES DEPRECATED TilePlacerData - Only for PLACEMENT operations
## This function exists ONLY for backward compatibility with old code paths
func add_tile_columnar(tile: TilePlacerData) -> int:
	var index: int = _tile_positions.size()

	_tile_positions.append(tile.grid_position)

	_tile_uv_rects.append(tile.uv_rect.position.x)
	_tile_uv_rects.append(tile.uv_rect.position.y)
	_tile_uv_rects.append(tile.uv_rect.size.x)
	_tile_uv_rects.append(tile.uv_rect.size.y)

	_tile_flags.append(_pack_tile_flags(tile))

	# Check for non-default transform params
	# IMPORTANT: depth_scale sparse storage threshold is 1.0 for backward compatibility
	# (Old tiles saved with depth=1.0 were not stored, so we must keep 1.0 as "default" marker)
	# New UI default is 0.1, but storage checks against 1.0 to preserve old scenes
	var has_params: bool = (
		tile.spin_angle_rad != 0.0 or
		tile.tilt_angle_rad != 0.0 or
		tile.diagonal_scale != 0.0 or
		tile.tilt_offset_factor != 0.0 or
		tile.depth_scale != 1.0
	)

	if has_params:
		_tile_transform_indices.append(_tile_transform_data.size() / 5)  # 5 floats per entry
		_tile_transform_data.append(tile.spin_angle_rad)
		_tile_transform_data.append(tile.tilt_angle_rad)
		_tile_transform_data.append(tile.diagonal_scale)
		_tile_transform_data.append(tile.tilt_offset_factor)
		_tile_transform_data.append(tile.depth_scale)
	else:
		_tile_transform_indices.append(-1)

	return index


## ✅ DIRECT COLUMNAR API - Add tile directly to storage (NO TilePlacerData)
## This is the PREFERRED way to add tiles - bypasses deprecated TilePlacerData
func add_tile_direct(
	grid_pos: Vector3,
	uv_rect: Rect2,
	orientation: int,
	mesh_rotation: int,
	mesh_mode: int,
	is_face_flipped: bool,
	terrain_id: int = -1,
	spin_angle: float = 0.0,
	tilt_angle: float = 0.0,
	diagonal_scale: float = 0.0,
	tilt_offset: float = 0.0,
	depth_scale: float = 0.1,  # NEW tile default
	texture_repeat_mode: int = 0  # TEXTURE_REPEAT: 0=DEFAULT, 1=REPEAT
) -> int:
	var index: int = _tile_positions.size()

	# Add position
	_tile_positions.append(grid_pos)

	# Add UV rect (4 floats)
	_tile_uv_rects.append(uv_rect.position.x)
	_tile_uv_rects.append(uv_rect.position.y)
	_tile_uv_rects.append(uv_rect.size.x)
	_tile_uv_rects.append(uv_rect.size.y)

	# Pack and add flags (includes texture_repeat_mode in bit 18)
	_tile_flags.append(_pack_flags_direct(orientation, mesh_rotation, mesh_mode, is_face_flipped, terrain_id, texture_repeat_mode))

	# Check for non-default transform params
	# IMPORTANT: depth_scale sparse storage threshold is 1.0 for backward compatibility
	# (Old tiles saved with depth=1.0 were not stored, so we must keep 1.0 as "default" marker)
	# New tile default is 0.1, but storage checks against 1.0 to preserve old scenes
	var has_params: bool = (
		spin_angle != 0.0 or
		tilt_angle != 0.0 or
		diagonal_scale != 0.0 or
		tilt_offset != 0.0 or
		depth_scale != 1.0
	)

	if has_params:
		_tile_transform_indices.append(_tile_transform_data.size() / 5)  # 5 floats per entry
		_tile_transform_data.append(spin_angle)
		_tile_transform_data.append(tilt_angle)
		_tile_transform_data.append(diagonal_scale)
		_tile_transform_data.append(tilt_offset)
		_tile_transform_data.append(depth_scale)
	else:
		_tile_transform_indices.append(-1)

	return index


## Helper to pack flags directly (no TilePlacerData)
func _pack_flags_direct(orientation: int, mesh_rotation: int, mesh_mode: int, is_face_flipped: bool, terrain_id: int, texture_repeat_mode: int = 0) -> int:
	var flags: int = 0
	flags |= orientation & 0x1F  # Bits 0-4: orientation (0-17)
	flags |= (mesh_rotation & 0x3) << 5  # Bits 5-6: mesh_rotation (0-3)
	flags |= (mesh_mode & 0x3) << 7  # Bits 7-8: mesh_mode (0-3)
	if is_face_flipped:
		flags |= 1 << 9  # Bit 9: is_face_flipped
	# Bits 10-17: terrain_id + 128 (range -128 to 127 stored as 0 to 255)
	flags |= ((terrain_id + 128) & 0xFF) << 10
	# Bit 18: texture_repeat_mode (0=DEFAULT, 1=REPEAT) for BOX/PRISM meshes
	flags |= (texture_repeat_mode & 0x1) << 18
	print("[TEXTURE_REPEAT] PACK_FLAGS_DIRECT: texture_repeat_mode=%d → bit18=%d, flags=%d" % [texture_repeat_mode, (flags >> 18) & 1, flags])
	return flags


## Removes a tile from columnar storage by index
func remove_tile_columnar(index: int) -> void:
	if index < 0 or index >= _tile_positions.size():
		return

	# Remove from position array
	_tile_positions.remove_at(index)

	# Remove from UV array (4 elements)
	var uv_idx: int = index * 4
	for i in range(4):
		_tile_uv_rects.remove_at(uv_idx)

	# Remove from flags
	_tile_flags.remove_at(index)

	# Handle transform params
	var transform_idx: int = _tile_transform_indices[index]
	_tile_transform_indices.remove_at(index)

	if transform_idx >= 0:
		# Remove transform data (5 floats per entry)
		var param_base: int = transform_idx * 5

		# FIX P0-4: Validate param_base is within bounds before removal
		if param_base + 4 >= _tile_transform_data.size():
			push_error("remove_tile_columnar: Transform data index %d out of bounds (size=%d)" % [param_base, _tile_transform_data.size()])
			return

		for i in range(5):
			_tile_transform_data.remove_at(param_base)

		# Update indices that pointed past the removed entry
		for i in range(_tile_transform_indices.size()):
			if _tile_transform_indices[i] > transform_idx:
				_tile_transform_indices[i] -= 1
				# FIX P0-4: Validate index didn't underflow
				if _tile_transform_indices[i] < 0:
					push_error("remove_tile_columnar: Transform index underflow at tile %d" % i)
					_tile_transform_indices[i] = -1  # Reset to "no params"


## Updates UV rect for a tile at index
func update_tile_uv_columnar(index: int, uv_rect: Rect2) -> void:
	var uv_idx: int = index * 4
	_tile_uv_rects[uv_idx] = uv_rect.position.x
	_tile_uv_rects[uv_idx + 1] = uv_rect.position.y
	_tile_uv_rects[uv_idx + 2] = uv_rect.size.x
	_tile_uv_rects[uv_idx + 3] = uv_rect.size.y


## Updates terrain_id for a tile at index
func update_tile_terrain_columnar(index: int, terrain_id: int) -> void:
	var flags: int = _tile_flags[index]
	# Clear terrain bits and set new value
	flags &= ~(0xFF << 10)
	flags |= ((terrain_id + 128) & 0xFF) << 10
	_tile_flags[index] = flags


## Clears all tile data from columnar storage
func clear_all_tiles() -> void:
	_tile_positions.clear()
	_tile_uv_rects.clear()
	_tile_flags.clear()
	_tile_transform_indices.clear()
	_tile_transform_data.clear()
	_saved_tiles_lookup.clear()
	_warnings_dirty = true  # FIX P2-24: Invalidate warnings on tile data change


# ==============================================================================
# SAVE/RESTORE HELPERS - Strip MultiMesh buffers for scene file size reduction
# ==============================================================================

## Strips MultiMesh buffer data before scene save (reduces file size)
## Runtime rebuilds from columnar tile data in _ready()
func _strip_chunk_buffers_for_save() -> void:
	# FIX P0-5: Prevent double-stripping on rapid save operations
	if _buffers_stripped:
		return  # Already stripped, don't strip again
	_buffers_stripped = true

	for chunk in _quad_chunks:
		if chunk and chunk.multimesh:
			chunk.multimesh.visible_instance_count = 0
	for chunk in _triangle_chunks:
		if chunk and chunk.multimesh:
			chunk.multimesh.visible_instance_count = 0
	for chunk in _box_chunks:
		if chunk and chunk.multimesh:
			chunk.multimesh.visible_instance_count = 0
	for chunk in _prism_chunks:
		if chunk and chunk.multimesh:
			chunk.multimesh.visible_instance_count = 0


## Restores MultiMesh buffer data after scene save
func _restore_chunk_buffers_after_save() -> void:
	# FIX P0-5: Only restore if buffers were stripped
	if not _buffers_stripped:
		return  # Not stripped, nothing to restore
	_buffers_stripped = false
	call_deferred("_rebuild_chunks_from_saved_data", false)
