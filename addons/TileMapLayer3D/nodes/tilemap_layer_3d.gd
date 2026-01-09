@icon("uid://b2snx34kyfmpg")
@tool
class_name TileMapLayer3D
extends Node3D

## Custom container node for 2.5D tile placement using MultiMesh for performance
## Responsibility: MultiMesh management, material configuration, tile group organization 


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


# Flat chunk arrays - for iteration and persistence (chunks are child nodes)
# NOTE: Chunks are NOT saved to scene file - they're rebuilt from columnar data on load
@export var _quad_chunks: Array[SquareTileChunk] = []  # Chunks for FLAT_SQUARE tiles
@export var _triangle_chunks: Array[TriangleTileChunk] = []  # Chunks for FLAT_TRIANGULE tiles
@export var _box_chunks: Array[BoxTileChunk] = []  # Chunks for BOX_MESH tiles (DEFAULT texture mode)
@export var _prism_chunks: Array[PrismTileChunk] = []  # Chunks for PRISM_MESH tiles (DEFAULT texture mode)
@export var _box_repeat_chunks: Array[BoxTileChunk] = []  # Chunks for BOX_MESH tiles (REPEAT texture mode)
@export var _prism_repeat_chunks: Array[PrismTileChunk] = []  # Chunks for PRISM_MESH tiles (REPEAT texture mode)

# Region registries - for fast spatial chunk lookup (dual-criteria chunking)
# Key: packed region key (int64 from GlobalUtil.pack_region_key())
# Value: Array of chunks in that region (allows sub-chunks when capacity exceeded)
# RUNTIME ONLY - rebuilt from chunk names during _rebuild_chunks_from_saved_data()
var _chunk_registry_quad: Dictionary = {}  # int -> Array[SquareTileChunk]
var _chunk_registry_triangle: Dictionary = {}  # int -> Array[TriangleTileChunk]
var _chunk_registry_box: Dictionary = {}  # int -> Array[BoxTileChunk]
var _chunk_registry_box_repeat: Dictionary = {}  # int -> Array[BoxTileChunk]
var _chunk_registry_prism: Dictionary = {}  # int -> Array[PrismTileChunk]
var _chunk_registry_prism_repeat: Dictionary = {}  # int -> Array[PrismTileChunk]

@export_group("Decal Mode")
@export var decal_mode: bool = false  # If true, tiles render as decals (no overlap z-fighting)
@export var decal_target_node: TileMapLayer3D = null  # Node to use as base for decal offset calculations
@export var decal_y_offset: float = 0.01  # Pushes the node upwards to avoid z-fighting when in decal mode
@export var decal_z_offset: float = 0.01  # Pushes the node forwards to avoid z-fighting when in decal mode
@export var render_priority: int = GlobalConstants.DEFAULT_RENDER_PRIORITY
var _chunk_shadow_casting: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

@export_group("Debug Controls")
@export var show_chunk_bounds: bool = false:
	set(value):
		show_chunk_bounds = value
		_update_chunk_debug_visualization()

# Debug visualization state
var _chunk_bounds_mesh: MeshInstance3D = null

# INTERNAL STATE (derived from settings Resource)
var tileset_texture: Texture2D = null
var grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE
var texture_filter_mode: int = GlobalConstants.DEFAULT_TEXTURE_FILTER
var _saved_tiles_lookup: Dictionary = {}  # int (tile_key) -> Array index
var current_mesh_mode: GlobalConstants.MeshMode = GlobalConstants.DEFAULT_MESH_MODE

var _tile_lookup: Dictionary = {}  # int (tile_key) -> TileRef
var _shared_material: ShaderMaterial = null
var _shared_material_double_sided: ShaderMaterial = null  # For BOX_MESH/PRISM_MESH
var _is_rebuilt: bool = false  # Track if chunks were rebuilt from saved data
var _buffers_stripped: bool = false  # Track strip/restore state to prevent race condition
var _reindex_in_progress: bool = false  # Prevent concurrent reindex during tile operations
var _cached_warnings: PackedStringArray = PackedStringArray()
var _warnings_dirty: bool = true

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
## Used for fast O(1) lookup of tile instance data
class TileRef:
	var chunk_index: int = -1  # Index within the region's chunk array (sub-chunk index)
	var instance_index: int = -1  # Instance index within the chunk's MultiMesh
	var uv_rect: Rect2 = Rect2()
	var mesh_mode: GlobalConstants.MeshMode = GlobalConstants.MeshMode.FLAT_SQUARE
	var texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT  # For BOX/PRISM chunks
	var region_key_packed: int = 0  # Packed spatial region key for chunk registry lookup


## Configuration for chunk factory - defines chunk type-specific properties
## Used by _get_or_create_chunk_in_region() to create appropriate chunk type
class ChunkConfig:
	var chunk_class: Script  # Script class for chunk creation (e.g., SquareTileChunk)
	var registry: Dictionary  # Reference to the chunk registry dictionary
	var flat_array: Array  # Reference to the flat chunk array
	var name_prefix: String  # Prefix for chunk naming (e.g., "SquareChunk")
	var needs_double_sided: bool  # True for BOX/PRISM (use double-sided material)
	var texture_repeat_mode: int  # GlobalConstants.TextureRepeatMode value


# Chunk configurations - lazily initialized on first access
var _chunk_configs: Dictionary = {}  # int (config_key) -> ChunkConfig


func _ready() -> void:
	# AUTO-MIGRATE: Check for old 4-float transform format and upgrade to 5-float
	if _tile_positions.size() > 0 and _tile_transform_data.size() > 0:
		var format: int = _detect_transform_data_format()
		if format == 4:
			_migrate_4float_to_5float()
		elif format == -1:
			push_warning("TileMapLayer3D: Transform data may be corrupted (unexpected size)")

	# RUNTIME: Rebuild chunks from columnar data (MultiMesh instance data isn't serialized)
	# SHARED: Runs in both editor and runtime
	_rebuild_chunks_from_saved_data(false)

	# EDITOR-ONLY: Skip at runtime
	if not Engine.is_editor_hint(): return

	# Ensure settings exists and is connected
	if not settings:
		settings = TileMapLayerSettings.new()

	# Apply settings to internal state
	_apply_settings()

	# Create highlight overlay for Box Erase feature
	_create_highlight_overlay()

	# Create blocked highlight overlay for out-of-bounds positions
	_create_blocked_highlight_overlay()

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
	# Ensure render priority is higher than target node
	if render_priority == decal_target_node.render_priority:
		render_priority = decal_target_node.render_priority + 1
		_update_material()

	# Disable shadow casting for decal mode
	if _chunk_shadow_casting != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_chunk_shadow_casting = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_update_material()

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
		call_deferred("_rebuild_chunks_from_saved_data", true)

	notify_property_list_changed()

## Rebuilds MultiMesh chunks from saved tile data (called on scene load)
## If force_mesh_rebuild is true, recreates mesh geometry (needed when grid_size changes)
func _rebuild_chunks_from_saved_data(force_mesh_rebuild: bool = false) -> void:
	# Allow rebuild even if already rebuilt (e.g., when grid_size changes)
	# Note: _is_rebuilt flag prevents automatic rebuild on _ready
	# but manual calls (from grid_size change) should always rebuild

	# STEP 1: Clear flat arrays AND region registries
	_quad_chunks.clear()
	_triangle_chunks.clear()
	_box_chunks.clear()
	_prism_chunks.clear()
	_box_repeat_chunks.clear()
	_prism_repeat_chunks.clear()
	_chunk_registry_quad.clear()
	_chunk_registry_triangle.clear()
	_chunk_registry_box.clear()
	_chunk_registry_box_repeat.clear()
	_chunk_registry_prism.clear()
	_chunk_registry_prism_repeat.clear()
	_tile_lookup.clear()

	# DESTROY all existing chunk children before creating new ones
	# Chunks are runtime-only (not saved to scene) so we always recreate from tile data
	# This prevents stale chunks from accumulating across rebuilds
	for child in get_children():
		if child is MultiMeshTileChunkBase:
			child.queue_free()

	# NOTE: STEP 2 and STEP 3 removed - they were designed for "chunks saved to scene file"
	# but chunks are NOT saved (no owner set). Chunks are always created fresh by STEP 5.

	# STEP 4 (was STEP 2/3 - removed dead code for unsaved chunks): Rebuild saved_tiles lookup dictionary from columnar storage
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

		# Convert grid to world for correct region calculation
		# CRITICAL: chunk regions are 50x50x50 WORLD units, not grid units!
		var world_position: Vector3 = GlobalUtil.grid_to_world(grid_position, grid_size)
		var chunk: MultiMeshTileChunkBase = get_or_create_chunk(mesh_mode, texture_repeat_mode, world_position)
		var instance_index: int = chunk.multimesh.visible_instance_count

		# Get local world position, then convert back to local grid for transform
		# build_tile_transform expects GRID coordinates, then internally converts to world
		var local_world_pos: Vector3 = GlobalUtil.world_to_local_grid_pos(world_position, chunk.region_key)
		var local_grid_pos: Vector3 = GlobalUtil.world_to_grid(local_world_pos, grid_size)

		# Build transform using LOCAL position
		var transform: Transform3D = GlobalUtil.build_tile_transform(
			local_grid_pos,
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
		tile_ref.region_key_packed = chunk.region_key_packed  # For spatial chunk lookup

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

	# NOTE: validate_and_fix_chunk_aabbs() removed from automatic call in v0.4.1
	# Local AABB is set in setup_mesh() via GlobalConstants.CHUNK_LOCAL_AABB
	# Chunks are positioned at region origins for proper spatial frustum culling

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


## Gets or creates a chunk for the specified mesh mode and grid position
## Uses DUAL-CRITERIA CHUNKING: tiles are grouped by BOTH mesh type AND spatial region
## @param mesh_mode: Type of mesh (FLAT_SQUARE, BOX_MESH, etc.)
## @param texture_repeat_mode: Texture mode for BOX/PRISM meshes
## @param grid_position: Grid position of the tile (used to determine spatial region)
## @returns: MultiMeshTileChunkBase with available space in the correct region
func get_or_create_chunk(
	mesh_mode: GlobalConstants.MeshMode = GlobalConstants.MeshMode.FLAT_SQUARE,
	texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT,
	grid_position: Vector3 = Vector3.ZERO
) -> MultiMeshTileChunkBase:
	# Calculate spatial region from grid position
	var region_key: Vector3i = GlobalUtil.calculate_region_key(grid_position)
	var region_key_packed: int = GlobalUtil.pack_region_key(region_key)

	# Get chunk config for the mesh mode + texture repeat combination
	var config: ChunkConfig = _get_chunk_config(mesh_mode, texture_repeat_mode)
	return _get_or_create_chunk_in_region(region_key, region_key_packed, config)


## Gets or creates the ChunkConfig for a given mesh mode and texture repeat mode
## Lazily initializes configs on first access
## @param mesh_mode: Type of mesh (FLAT_SQUARE, BOX_MESH, etc.)
## @param texture_repeat: Texture repeat mode (DEFAULT or REPEAT)
## @returns: ChunkConfig for the specified mode combination
func _get_chunk_config(mesh_mode: GlobalConstants.MeshMode, texture_repeat: int) -> ChunkConfig:
	var key: int = mesh_mode * 10 + texture_repeat
	if not _chunk_configs.has(key):
		_chunk_configs[key] = _create_chunk_config(mesh_mode, texture_repeat)
	return _chunk_configs[key]


## Creates a new ChunkConfig for the specified mesh mode and texture repeat mode
## @param mesh_mode: Type of mesh
## @param texture_repeat: Texture repeat mode
## @returns: Configured ChunkConfig instance
func _create_chunk_config(mesh_mode: GlobalConstants.MeshMode, texture_repeat: int) -> ChunkConfig:
	var config := ChunkConfig.new()
	config.texture_repeat_mode = texture_repeat

	match mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE:
			config.chunk_class = SquareTileChunk
			config.registry = _chunk_registry_quad
			config.flat_array = _quad_chunks
			config.name_prefix = "SquareChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_TRIANGULE:
			config.chunk_class = TriangleTileChunk
			config.registry = _chunk_registry_triangle
			config.flat_array = _triangle_chunks
			config.name_prefix = "TriangleChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.BOX_MESH:
			config.chunk_class = BoxTileChunk
			config.needs_double_sided = true
			if texture_repeat == GlobalConstants.TextureRepeatMode.REPEAT:
				config.registry = _chunk_registry_box_repeat
				config.flat_array = _box_repeat_chunks
				config.name_prefix = "BoxRepeatChunk"
			else:
				config.registry = _chunk_registry_box
				config.flat_array = _box_chunks
				config.name_prefix = "BoxChunk"
		GlobalConstants.MeshMode.PRISM_MESH:
			config.chunk_class = PrismTileChunk
			config.needs_double_sided = true
			if texture_repeat == GlobalConstants.TextureRepeatMode.REPEAT:
				config.registry = _chunk_registry_prism_repeat
				config.flat_array = _prism_repeat_chunks
				config.name_prefix = "PrismRepeatChunk"
			else:
				config.registry = _chunk_registry_prism
				config.flat_array = _prism_chunks
				config.name_prefix = "PrismChunk"

	return config


## Generic chunk factory - creates or reuses a chunk in the specified region
## Replaces 6 duplicate _get_or_create_*_chunk_in_region functions
## @param region_key: Spatial region coordinates (Vector3i)
## @param region_key_packed: Packed region key for dictionary lookup
## @param config: ChunkConfig defining chunk type specifics
## @returns: Chunk with space for new tiles
func _get_or_create_chunk_in_region(
	region_key: Vector3i,
	region_key_packed: int,
	config: ChunkConfig
) -> MultiMeshTileChunkBase:
	# Get or create registry entry for this region
	if not config.registry.has(region_key_packed):
		config.registry[region_key_packed] = []

	var region_chunks: Array = config.registry[region_key_packed]

	# Try to reuse existing chunk with space in this region
	for chunk in region_chunks:
		if chunk.has_space():
			return chunk

	# Create new chunk using the configured class
	var chunk: MultiMeshTileChunkBase = config.chunk_class.new()
	chunk.region_key = region_key
	chunk.region_key_packed = region_key_packed
	chunk.chunk_index = region_chunks.size()
	chunk.name = "%s_R%d_%d_%d_C%d" % [
		config.name_prefix,
		region_key.x, region_key.y, region_key.z,
		chunk.chunk_index
	]

	# Setup mesh (handles texture_repeat_mode internally for BOX/PRISM)
	if config.texture_repeat_mode != GlobalConstants.TextureRepeatMode.DEFAULT:
		chunk.texture_repeat_mode = config.texture_repeat_mode
		chunk.setup_mesh(grid_size, config.texture_repeat_mode)
	else:
		chunk.setup_mesh(grid_size)

	# Apply appropriate material
	if config.needs_double_sided:
		chunk.material_override = get_shared_material_double_sided()
	else:
		chunk.material_override = get_shared_material(false)

	chunk.cast_shadow = _chunk_shadow_casting
	# PROPER SPATIAL CHUNKING (v0.4.2): Position chunk at region's world origin
	chunk.position = GlobalUtil.get_chunk_world_position(region_key)
	chunk.custom_aabb = GlobalConstants.CHUNK_LOCAL_AABB

	if not chunk.get_parent():
		add_child.bind(chunk, true).call_deferred()

	region_chunks.append(chunk)
	config.flat_array.append(chunk)
	return chunk


## Helper to get chunk from TileRef based on mesh mode, texture repeat mode, and region
## Uses region registries for O(1) lookup by region_key_packed + chunk_index
## Falls back to flat array lookup for backward compatibility with pre-region TileRefs
func _get_chunk_by_ref(tile_ref: TileRef) -> MultiMeshTileChunkBase:
	if tile_ref.chunk_index < 0:
		return null

	# Get the appropriate registry based on mesh mode and texture repeat mode
	var registry: Dictionary
	match tile_ref.mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE:
			registry = _chunk_registry_quad
		GlobalConstants.MeshMode.FLAT_TRIANGULE:
			registry = _chunk_registry_triangle
		GlobalConstants.MeshMode.BOX_MESH:
			if tile_ref.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
				registry = _chunk_registry_box_repeat
			else:
				registry = _chunk_registry_box
		GlobalConstants.MeshMode.PRISM_MESH:
			if tile_ref.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
				registry = _chunk_registry_prism_repeat
			else:
				registry = _chunk_registry_prism
		_:
			return null

	# Try registry lookup first (fast path for region-aware tiles)
	if registry.has(tile_ref.region_key_packed):
		var region_chunks: Array = registry[tile_ref.region_key_packed]
		if tile_ref.chunk_index < region_chunks.size():
			return region_chunks[tile_ref.chunk_index]

	# Fallback: Try flat array lookup for backward compatibility
	# This handles TileRefs created before region tracking was added
	match tile_ref.mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE:
			if tile_ref.chunk_index < _quad_chunks.size():
				return _quad_chunks[tile_ref.chunk_index]
		GlobalConstants.MeshMode.FLAT_TRIANGULE:
			if tile_ref.chunk_index < _triangle_chunks.size():
				return _triangle_chunks[tile_ref.chunk_index]
		GlobalConstants.MeshMode.BOX_MESH:
			if tile_ref.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
				if tile_ref.chunk_index < _box_repeat_chunks.size():
					return _box_repeat_chunks[tile_ref.chunk_index]
			else:
				if tile_ref.chunk_index < _box_chunks.size():
					return _box_chunks[tile_ref.chunk_index]
		GlobalConstants.MeshMode.PRISM_MESH:
			if tile_ref.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
				if tile_ref.chunk_index < _prism_repeat_chunks.size():
					return _prism_repeat_chunks[tile_ref.chunk_index]
			else:
				if tile_ref.chunk_index < _prism_chunks.size():
					return _prism_chunks[tile_ref.chunk_index]

	return null


## Parses region key from chunk name for legacy support and scene loading
## Legacy format: "SquareChunk_0" → returns Vector3i.ZERO
## New format: "SquareChunk_R0_0_0_C0" → extracts region Vector3i(0, 0, 0)
func _parse_region_from_chunk_name(chunk_name: String) -> Vector3i:
	# Check if this is the new region-aware naming format
	if "_R" not in chunk_name:
		# Legacy format - assign to default region (0, 0, 0)
		return Vector3i.ZERO

	# Parse new format: "TypeChunk_R{x}_{y}_{z}_C{idx}"
	# Examples: "SquareChunk_R0_0_0_C0", "BoxRepeatChunk_R-1_2_0_C1"
	var parts: PackedStringArray = chunk_name.split("_")

	# Format: [Type, R{x}, {y}, {z}, C{idx}]
	# Minimum parts for valid format: TypeChunk_R0_0_0_C0 = 5 parts
	if parts.size() >= 5:
		# parts[1] should be "R{x}" - remove the "R" prefix
		var x_str: String = parts[1]
		if x_str.begins_with("R"):
			x_str = x_str.substr(1)  # Remove "R" prefix

		# parts[2] is "{y}", parts[3] is "{z}"
		var x_val: int = int(x_str) if x_str.is_valid_int() else 0
		var y_val: int = int(parts[2]) if parts[2].is_valid_int() else 0
		var z_val: int = int(parts[3]) if parts[3].is_valid_int() else 0

		return Vector3i(x_val, y_val, z_val)

	# Fallback to default region if parsing fails
	return Vector3i.ZERO


## Parses chunk index from chunk name for sorting within regions
## Legacy format: "SquareChunk_0" → returns 0
## New format: "SquareChunk_R0_0_0_C1" → returns 1 (the C{idx} part)
func _parse_chunk_index_from_name(chunk_name: String) -> int:
	# Check if this is the new region-aware naming format with _C{idx}
	if "_C" in chunk_name:
		# Parse new format: "TypeChunk_R{x}_{y}_{z}_C{idx}"
		var c_pos: int = chunk_name.rfind("_C")
		if c_pos >= 0:
			var idx_str: String = chunk_name.substr(c_pos + 2)  # Skip "_C"
			if idx_str.is_valid_int():
				return int(idx_str)

	# Legacy format: "SquareChunk_0", "BoxChunk_1", etc.
	# Find the last underscore and parse the number after it
	var last_underscore: int = chunk_name.rfind("_")
	if last_underscore >= 0:
		var idx_str: String = chunk_name.substr(last_underscore + 1)
		if idx_str.is_valid_int():
			return int(idx_str)

	# Fallback to 0 if parsing fails
	return 0


##   Reindexes all chunks after removal to fix chunk_index corruption
## When chunks are removed, remaining chunks shift in array but chunk_index stays stale
## This causes tile_ref.chunk_index to point to wrong array positions
## Call this after removing chunks to restore consistency
## NOTE: With region-based chunking, indices are PER-REGION, not global
func reindex_chunks() -> void:
	# FIX P1-13: Prevent concurrent reindex during tile operations
	if _reindex_in_progress:
		push_warning("reindex_chunks called while already reindexing - skipping to prevent corruption")
		return

	_reindex_in_progress = true

	# Helper function to reindex chunks within a region registry
	# Returns the updated flat array for that chunk type
	var reindex_registry = func(registry: Dictionary, chunk_type_name: String) -> void:
		for region_key_packed: int in registry.keys():
			var region_chunks: Array = registry[region_key_packed]
			for i in range(region_chunks.size()):
				var chunk: MultiMeshTileChunkBase = region_chunks[i]
				if chunk.chunk_index != i:
					if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
						var region: Vector3i = GlobalUtil.unpack_region_key(region_key_packed)
						print("Reindexing %s chunk R(%d,%d,%d): old_index=%d → new_index=%d (tile_count=%d)" % [
							chunk_type_name, region.x, region.y, region.z, chunk.chunk_index, i, chunk.tile_count
						])

					chunk.chunk_index = i

					# Update ALL TileRefs that point to this chunk
					for tile_key in chunk.tile_refs.keys():
						var tile_ref: TileRef = _tile_lookup.get(tile_key)
						if tile_ref:
							tile_ref.chunk_index = i
						else:
							push_warning("Reindex: tile_key %d in chunk.tile_refs but not in _tile_lookup" % tile_key)

	# Reindex all region registries
	reindex_registry.call(_chunk_registry_quad, "quad")
	reindex_registry.call(_chunk_registry_triangle, "triangle")
	reindex_registry.call(_chunk_registry_box, "box")
	reindex_registry.call(_chunk_registry_prism, "prism")
	reindex_registry.call(_chunk_registry_box_repeat, "box_repeat")
	reindex_registry.call(_chunk_registry_prism_repeat, "prism_repeat")

	# Also rebuild flat arrays to stay in sync
	_rebuild_flat_chunk_arrays()

	_reindex_in_progress = false  # FIX P1-13: Reset flag when complete


## Rebuilds flat chunk arrays from region registries
## Called after reindexing to keep flat arrays in sync with registries
func _rebuild_flat_chunk_arrays() -> void:
	_quad_chunks.clear()
	_triangle_chunks.clear()
	_box_chunks.clear()
	_prism_chunks.clear()
	_box_repeat_chunks.clear()
	_prism_repeat_chunks.clear()

	# Collect all chunks from registries into flat arrays
	for region_chunks: Array in _chunk_registry_quad.values():
		for chunk in region_chunks:
			_quad_chunks.append(chunk)

	for region_chunks: Array in _chunk_registry_triangle.values():
		for chunk in region_chunks:
			_triangle_chunks.append(chunk)

	for region_chunks: Array in _chunk_registry_box.values():
		for chunk in region_chunks:
			_box_chunks.append(chunk)

	for region_chunks: Array in _chunk_registry_prism.values():
		for chunk in region_chunks:
			_prism_chunks.append(chunk)

	for region_chunks: Array in _chunk_registry_box_repeat.values():
		for chunk in region_chunks:
			_box_repeat_chunks.append(chunk)

	for region_chunks: Array in _chunk_registry_prism_repeat.values():
		for chunk in region_chunks:
			_prism_repeat_chunks.append(chunk)


## Returns all chunks across all mesh types as a single array
## Useful for iteration operations that apply to all chunk types
## @returns: Array containing all chunks (may include null entries from freed chunks)
func _get_all_chunks() -> Array:
	var all_chunks: Array = []
	all_chunks.append_array(_quad_chunks)
	all_chunks.append_array(_triangle_chunks)
	all_chunks.append_array(_box_chunks)
	all_chunks.append_array(_box_repeat_chunks)
	all_chunks.append_array(_prism_chunks)
	all_chunks.append_array(_prism_repeat_chunks)
	return all_chunks


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
## Call this when tile_ref lookup fails to auto-recover from desync
## This regenerates all TileRef objects from the runtime chunk.tile_refs dictionaries
## NOTE: With region-based chunking, we iterate region registries to get correct chunk indices
func _rebuild_tile_lookup_from_chunks() -> void:
	_tile_lookup.clear()

	# Helper to rebuild TileRefs from a registry
	var rebuild_from_registry = func(
		registry: Dictionary,
		mesh_mode: GlobalConstants.MeshMode,
		texture_repeat_mode: int
	) -> void:
		for region_key_packed: int in registry.keys():
			var region_chunks: Array = registry[region_key_packed]
			for chunk_index: int in range(region_chunks.size()):
				var chunk: MultiMeshTileChunkBase = region_chunks[chunk_index]
				for tile_key: int in chunk.tile_refs.keys():
					var instance_index: int = chunk.tile_refs[tile_key]

					# Create TileRef from chunk data with region info
					var tile_ref: TileRef = TileRef.new()
					tile_ref.chunk_index = chunk_index  # Per-region index
					tile_ref.instance_index = instance_index
					tile_ref.mesh_mode = mesh_mode
					tile_ref.texture_repeat_mode = texture_repeat_mode
					tile_ref.region_key_packed = region_key_packed

					_tile_lookup[tile_key] = tile_ref

	# Rebuild from all registries
	rebuild_from_registry.call(
		_chunk_registry_quad,
		GlobalConstants.MeshMode.FLAT_SQUARE,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_triangle,
		GlobalConstants.MeshMode.FLAT_TRIANGULE,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_box,
		GlobalConstants.MeshMode.BOX_MESH,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_prism,
		GlobalConstants.MeshMode.PRISM_MESH,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_box_repeat,
		GlobalConstants.MeshMode.BOX_MESH,
		GlobalConstants.TextureRepeatMode.REPEAT
	)
	rebuild_from_registry.call(
		_chunk_registry_prism_repeat,
		GlobalConstants.MeshMode.PRISM_MESH,
		GlobalConstants.TextureRepeatMode.REPEAT
	)

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
	texture_repeat_mode: int = 0  # 0=DEFAULT, 1=REPEAT
) -> void:
	# Generate tile key for lookup
	var tile_key: Variant = GlobalUtil.make_tile_key(grid_pos, orientation)

	# If tile already exists at this position, remove it first
	if _saved_tiles_lookup.has(tile_key):
		remove_saved_tile_data(tile_key)

	# Add tile to columnar storage
	var new_index: int = add_tile_direct(
		grid_pos, uv_rect, orientation, mesh_rotation, mesh_mode,
		is_face_flipped, terrain_id, spin_angle, tilt_angle,
		diagonal_scale, tilt_offset, depth_scale, texture_repeat_mode
	)
	_saved_tiles_lookup[tile_key] = new_index


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

# ==============================================================================
# BOX ERASE HIGHLIGHT OVERLAY SYSTEM
# ==============================================================================

## Factory function to create a highlight overlay MultiMesh + Instance pair
## @param instance_count: Number of instances in the MultiMesh pool
## @param box_scale: Scale multiplier for box size relative to grid_size
## @param box_thickness: Z dimension of the highlight box
## @param material: Material to apply to the MultiMeshInstance3D
## @param overlay_name: Name for the MultiMeshInstance3D node
## @returns: Array containing [MultiMesh, MultiMeshInstance3D]
func _create_highlight_overlay_pair(
	instance_count: int,
	box_scale: float,
	box_thickness: float,
	material: Material,
	overlay_name: String
) -> Array:
	# Create MultiMesh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = instance_count
	mm.visible_instance_count = 0

	# Create box mesh
	var box := BoxMesh.new()
	box.size = Vector3(grid_size * box_scale, grid_size * box_scale, box_thickness)
	mm.mesh = box

	# Create instance node
	var instance := MultiMeshInstance3D.new()
	instance.name = overlay_name
	instance.multimesh = mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = material

	add_child(instance)
	# DO NOT set owner - highlight overlay is editor-only, not saved to scene

	return [mm, instance]


## Creates the highlight overlay MultiMesh for Box Erase feature
## This creates a pool of semi-transparent boxes that can be positioned over tiles
## Editor-only - not saved to scene
func _create_highlight_overlay() -> void:
	var pair: Array = _create_highlight_overlay_pair(
		GlobalConstants.MAX_HIGHLIGHTED_TILES,
		GlobalConstants.HIGHLIGHT_BOX_SCALE,
		GlobalConstants.HIGHLIGHT_BOX_THICKNESS,
		GlobalUtil.create_highlight_material(),
		"TileHighlightOverlay"
	)
	_highlight_multimesh = pair[0]
	_highlight_instance = pair[1]

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
	var pair: Array = _create_highlight_overlay_pair(
		1,  # Only need one for cursor position
		GlobalConstants.BLOCKED_HIGHLIGHT_BOX_SCALE,
		GlobalConstants.BLOCKED_HIGHLIGHT_BOX_THICKNESS,
		GlobalUtil.create_blocked_highlight_material(),
		"BlockedPositionHighlight"
	)
	_blocked_highlight_multimesh = pair[0]
	_blocked_highlight_instance = pair[1]

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
# LEGACY CHUNK NODE CLEANUP
# ==============================================================================

## Removes old chunk nodes that were saved to scene file but are no longer needed
## Called after rebuild completes to clean up legacy scenes
func _cleanup_orphaned_chunk_nodes() -> void:
	var orphaned_count: int = 0
	for child in get_children():
		if child is MultiMeshTileChunkBase:
			# Check if this chunk has any tiles
			if child.tile_count == 0 and child.multimesh.visible_instance_count == 0:
				child.queue_free()
				orphaned_count += 1

	if orphaned_count > 0:
		print("TileMapLayer3D: Cleaned up %d orphaned legacy chunk nodes" % orphaned_count)


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

	# Clean up orphaned chunk nodes that were saved in old scene format
	_cleanup_orphaned_chunk_nodes()


## Detects transform data format (4-float old format vs 5-float current format)
## @returns: 4, 5, or -1 (unknown/corrupted)
func _detect_transform_data_format() -> int:
	var tiles_with_transform: int = 0
	for idx in _tile_transform_indices:
		if idx >= 0:
			tiles_with_transform += 1

	if tiles_with_transform == 0:
		return 5  # No transform data, assume current format

	var data_size: int = _tile_transform_data.size()
	var expected_5float: int = tiles_with_transform * 5
	var expected_4float: int = tiles_with_transform * 4

	if data_size == expected_5float:
		return 5
	elif data_size == expected_4float:
		return 4
	else:
		return -1  # Unknown/corrupted


## Migrates transform data from 4-float to 5-float format
## Adds depth_scale=1.0 as 5th float for each entry
func _migrate_4float_to_5float() -> void:
	var old_data: PackedFloat32Array = _tile_transform_data.duplicate()
	_tile_transform_data.clear()

	var entry_count: int = old_data.size() / 4
	for i in range(entry_count):
		var base: int = i * 4
		_tile_transform_data.append(old_data[base])      # spin_angle_rad
		_tile_transform_data.append(old_data[base + 1])  # tilt_angle_rad
		_tile_transform_data.append(old_data[base + 2])  # diagonal_scale
		_tile_transform_data.append(old_data[base + 3])  # tilt_offset_factor
		_tile_transform_data.append(1.0)                  # depth_scale (default)

	print("TileMapLayer3D: Migrated %d transform entries from 4-float to 5-float format" % entry_count)


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
	return flags


## Unpacks int32 flags into tile properties
## ⚠️ USES DEPRECATED TilePlacerData - Only for get_tile_at() compatibility
func _unpack_tile_flags(flags: int, tile: TilePlacerData) -> void:
	tile.orientation = flags & 0x1F
	tile.mesh_rotation = (flags >> 5) & 0x3
	tile.mesh_mode = (flags >> 7) & 0x3
	tile.is_face_flipped = ((flags >> 9) & 0x1) == 1
	tile.terrain_id = ((flags >> 10) & 0xFF) - 128
	tile.texture_repeat_mode = (flags >> 18) & 0x1


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

		# Validate transform data size (should rarely trigger after auto-migration)
		var expected_size: int = param_base + 5
		if _tile_transform_data.size() < expected_size:
			push_error("get_tile_at: Transform data size insufficient (have %d, need %d)" % [
				_tile_transform_data.size(), expected_size
			])
			# Use defaults rather than crashing
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
	for chunk in _box_repeat_chunks:
		if chunk and chunk.multimesh:
			chunk.multimesh.visible_instance_count = 0
	for chunk in _prism_repeat_chunks:
		if chunk and chunk.multimesh:
			chunk.multimesh.visible_instance_count = 0


## Restores MultiMesh buffer data after scene save
func _restore_chunk_buffers_after_save() -> void:
	# FIX P0-5: Only restore if buffers were stripped
	if not _buffers_stripped:
		return  # Not stripped, nothing to restore
	_buffers_stripped = false
	call_deferred("_rebuild_chunks_from_saved_data", false)


# ==============================================================================
# AABB VALIDATION & DEBUG - Delegates to DebugInfoGenerator
# ==============================================================================

## Ensures all chunks have the correct LOCAL AABB set.
## Call this after rebuilding chunks or if visibility issues are suspected.
## @returns: Number of chunks that had incorrect AABBs and were fixed
func validate_and_fix_chunk_aabbs() -> int:
	return DebugInfoGenerator.validate_and_fix_chunk_aabbs(self)


## Prints diagnostic information about all chunk AABBs.
## Use this to debug visibility issues - shows which chunks have correct AABBs.
## Call from editor console: $TileMapLayer3D.debug_print_chunk_aabbs()
func debug_print_chunk_aabbs() -> void:
	DebugInfoGenerator.print_chunk_aabbs(self)


## Verifies that all tiles are contained within their chunk's AABB.
## Returns the number of tiles outside their chunk's AABB (should be 0).
## Call from editor console: $TileMapLayer3D.debug_verify_tiles_in_aabbs()
## @returns: Number of tiles found outside their chunk's AABB (0 = all good)
func debug_verify_tiles_in_aabbs() -> int:
	return DebugInfoGenerator.verify_tiles_in_aabbs(self)


# ==============================================================================
#region DEBUG VISUALIZATION
# ==============================================================================

## Updates chunk boundary wireframe visualization based on show_chunk_bounds flag
func _update_chunk_debug_visualization() -> void:
	if show_chunk_bounds:
		_create_or_update_chunk_bounds_mesh()
	else:
		_destroy_chunk_bounds_mesh()


## Creates or updates the wireframe mesh showing chunk boundaries
func _create_or_update_chunk_bounds_mesh() -> void:
	# Create mesh instance if needed
	if not _chunk_bounds_mesh:
		_chunk_bounds_mesh = MeshInstance3D.new()
		_chunk_bounds_mesh.name = "_ChunkBoundsDebug"
		_chunk_bounds_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_chunk_bounds_mesh)

	# Create immediate mesh for wireframe drawing
	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = GlobalConstants.DEBUG_CHUNK_BOUNDS_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Draw wireframe for each chunk
	var all_chunks: Array = _get_all_chunks()
	if all_chunks.size() > 0:
		immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
		for chunk in all_chunks:
			_draw_wireframe_box(immediate_mesh, chunk.position, GlobalConstants.CHUNK_REGION_SIZE)
		immediate_mesh.surface_end()

	_chunk_bounds_mesh.mesh = immediate_mesh


## Draws a wireframe box at the given position with the given size
func _draw_wireframe_box(mesh: ImmediateMesh, pos: Vector3, size: float) -> void:
	var s: float = size
	# 8 corners of the box
	var corners: Array[Vector3] = [
		pos + Vector3(0, 0, 0),      # 0: bottom-front-left
		pos + Vector3(s, 0, 0),      # 1: bottom-front-right
		pos + Vector3(s, 0, s),      # 2: bottom-back-right
		pos + Vector3(0, 0, s),      # 3: bottom-back-left
		pos + Vector3(0, s, 0),      # 4: top-front-left
		pos + Vector3(s, s, 0),      # 5: top-front-right
		pos + Vector3(s, s, s),      # 6: top-back-right
		pos + Vector3(0, s, s),      # 7: top-back-left
	]

	# Bottom face edges (4)
	mesh.surface_add_vertex(corners[0]); mesh.surface_add_vertex(corners[1])
	mesh.surface_add_vertex(corners[1]); mesh.surface_add_vertex(corners[2])
	mesh.surface_add_vertex(corners[2]); mesh.surface_add_vertex(corners[3])
	mesh.surface_add_vertex(corners[3]); mesh.surface_add_vertex(corners[0])

	# Top face edges (4)
	mesh.surface_add_vertex(corners[4]); mesh.surface_add_vertex(corners[5])
	mesh.surface_add_vertex(corners[5]); mesh.surface_add_vertex(corners[6])
	mesh.surface_add_vertex(corners[6]); mesh.surface_add_vertex(corners[7])
	mesh.surface_add_vertex(corners[7]); mesh.surface_add_vertex(corners[4])

	# Vertical edges (4)
	mesh.surface_add_vertex(corners[0]); mesh.surface_add_vertex(corners[4])
	mesh.surface_add_vertex(corners[1]); mesh.surface_add_vertex(corners[5])
	mesh.surface_add_vertex(corners[2]); mesh.surface_add_vertex(corners[6])
	mesh.surface_add_vertex(corners[3]); mesh.surface_add_vertex(corners[7])


## Destroys the chunk bounds debug mesh
func _destroy_chunk_bounds_mesh() -> void:
	if _chunk_bounds_mesh:
		_chunk_bounds_mesh.queue_free()
		_chunk_bounds_mesh = null

#endregion
