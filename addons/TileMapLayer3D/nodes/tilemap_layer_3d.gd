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
		if not Engine.is_editor_hint(): return
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
## Each entry: 4 floats (spin_angle, tilt_angle, diagonal_scale, tilt_offset)
@export var _tile_transform_data: PackedFloat32Array = PackedFloat32Array()

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

var _quad_chunks: Array[SquareTileChunk] = []  # Chunks for FLAT_SQUARE tiles
var _triangle_chunks: Array[TriangleTileChunk] = []  # Chunks for FLAT_TRIANGULE tiles
var _box_chunks: Array[BoxTileChunk] = []  # Chunks for BOX_MESH tiles
var _prism_chunks: Array[PrismTileChunk] = []  # Chunks for PRISM_MESH tiles


var _tile_lookup: Dictionary = {}  # int (tile_key) -> TileRef
var _shared_material: ShaderMaterial = null
var _shared_material_no_backfaces: ShaderMaterial = null  # For BOX_MESH/PRISM_MESH (no debug backfaces)
var _is_rebuilt: bool = false  # Track if chunks were rebuilt from saved data

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

func _ready() -> void:
	if not Engine.is_editor_hint(): return
	set_meta("_godot25d_tile_model", true)

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

			# Reset runtime state
			chunk.tile_count = 0
			chunk.tile_refs.clear()
			chunk.instance_to_key.clear()

			# Handle mesh rebuild if needed
			if force_mesh_rebuild:
				chunk.multimesh.visible_instance_count = 0
				chunk.multimesh.instance_count = 0
				chunk.multimesh.mesh = TileMeshGenerator.create_box_mesh(grid_size)
				chunk.multimesh.instance_count = MultiMeshTileChunkBase.MAX_TILES
			else:
				chunk.multimesh.visible_instance_count = 0

			_box_chunks.append(chunk)

		elif child is PrismTileChunk:
			var chunk = child as PrismTileChunk

			# Reset runtime state
			chunk.tile_count = 0
			chunk.tile_refs.clear()
			chunk.instance_to_key.clear()

			# Handle mesh rebuild if needed
			if force_mesh_rebuild:
				chunk.multimesh.visible_instance_count = 0
				chunk.multimesh.instance_count = 0
				chunk.multimesh.mesh = TileMeshGenerator.create_prism_mesh(grid_size)
				chunk.multimesh.instance_count = MultiMeshTileChunkBase.MAX_TILES
			else:
				chunk.multimesh.visible_instance_count = 0

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

	# STEP 5: Recreate tiles from saved data (using columnar storage)
	for i in range(tile_count):
		var tile_data: TilePlacerData = get_tile_at(i)
		if not tileset_texture:
			push_warning("Cannot rebuild tiles: no tileset texture")
			break

		# Determine mesh mode from saved data (backward compatible)
		var mesh_mode: int = tile_data.mesh_mode
		
		# Get or create appropriate chunk type
		var chunk: MultiMeshTileChunkBase = get_or_create_chunk(mesh_mode)
		var instance_index: int = chunk.multimesh.visible_instance_count

		# Build transform using SINGLE SOURCE OF TRUTH with per-tile saved transform params
		# This ensures data persistency - tiles are reconstructed with their original
		# transform parameters even if GlobalConstants have changed since placement
		var transform: Transform3D = GlobalUtil.build_tile_transform(
			tile_data.grid_position,
			tile_data.orientation,
			tile_data.mesh_rotation,
			grid_size,
			tile_data.is_face_flipped,
			tile_data.spin_angle_rad,
			tile_data.tilt_angle_rad,
			tile_data.diagonal_scale,
			tile_data.tilt_offset_factor
		)
		chunk.multimesh.set_instance_transform(instance_index, transform)

		# Set UV data
		var atlas_size: Vector2 = tileset_texture.get_size()
		var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(tile_data.uv_rect, atlas_size)
		var custom_data: Color = uv_data.uv_color
		chunk.multimesh.set_instance_custom_data(instance_index, custom_data)

		# Increment visible count
		chunk.multimesh.visible_instance_count += 1
		chunk.tile_count += 1

		# Create tile ref with chunk-type-specific indexing
		var tile_ref: TileRef = TileRef.new()

		# Set mesh_mode to match chunk type
		# Without this, TileRef defaults to MESH_SQUARE, causing triangle tiles
		tile_ref.mesh_mode = mesh_mode

		# Store chunk index based on type
		match mesh_mode:
			GlobalConstants.MeshMode.FLAT_SQUARE:
				tile_ref.chunk_index = _quad_chunks.find(chunk)
			GlobalConstants.MeshMode.FLAT_TRIANGULE:
				tile_ref.chunk_index = _triangle_chunks.find(chunk)
			GlobalConstants.MeshMode.BOX_MESH:
				tile_ref.chunk_index = _box_chunks.find(chunk)
			GlobalConstants.MeshMode.PRISM_MESH:
				tile_ref.chunk_index = _prism_chunks.find(chunk)

		tile_ref.instance_index = instance_index
		tile_ref.uv_rect = tile_data.uv_rect

		# Add to lookup using compound key
		var tile_key: int = GlobalUtil.make_tile_key(tile_data.grid_position, tile_data.orientation)
		_tile_lookup[tile_key] = tile_ref
		chunk.tile_refs[tile_key] = instance_index
		chunk.instance_to_key[instance_index] = tile_key

	_is_rebuilt = true
	_update_material()

func _update_material() -> void:
	if tileset_texture:
		# Always recreate materials to ensure filter mode is applied
		_shared_material = GlobalUtil.create_tile_material(tileset_texture, texture_filter_mode, render_priority)
		_shared_material_no_backfaces = GlobalUtil.create_tile_material(
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
				chunk.material_override = _shared_material_no_backfaces
				chunk.cast_shadow = _chunk_shadow_casting

		# Update material on all prism chunks (no backfaces)
		for chunk in _prism_chunks:
			if chunk:
				chunk.material_override = _shared_material_no_backfaces
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

func get_shared_material(debug_show_backfaces: bool) -> ShaderMaterial:
	# Ensure material exists before returning
	if not _shared_material and tileset_texture:
		_shared_material = GlobalUtil.create_tile_material(tileset_texture, texture_filter_mode, render_priority, debug_show_backfaces)
	return _shared_material


## Returns shared material with debug_show_backfaces disabled (for BOX_MESH/PRISM_MESH)
func get_shared_material_no_backfaces() -> ShaderMaterial:
	if not _shared_material_no_backfaces and tileset_texture:
		_shared_material_no_backfaces = GlobalUtil.create_tile_material(
			tileset_texture, texture_filter_mode, render_priority, false)
	return _shared_material_no_backfaces


## Gets or creates a chunk with available space based on mesh mode
## Returns a MultiMeshTileChunkBase with available space
func get_or_create_chunk(mesh_mode: GlobalConstants.MeshMode = GlobalConstants.MeshMode.FLAT_SQUARE) -> MultiMeshTileChunkBase:
	match mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE:
			return _get_or_create_square_chunk()
		GlobalConstants.MeshMode.FLAT_TRIANGULE:
			return _get_or_create_triangle_chunk()
		GlobalConstants.MeshMode.BOX_MESH:
			return _get_or_create_box_chunk()
		GlobalConstants.MeshMode.PRISM_MESH:
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
	chunk.material_override = get_shared_material(true)
	chunk.cast_shadow = _chunk_shadow_casting

	if not chunk.get_parent():
		add_child.bind(chunk, true).call_deferred()

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
	chunk.material_override = get_shared_material(true)
	chunk.cast_shadow = _chunk_shadow_casting

	if not chunk.get_parent():
		add_child.bind(chunk, true).call_deferred()

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
	chunk.material_override = get_shared_material_no_backfaces()
	chunk.cast_shadow = _chunk_shadow_casting

	if not chunk.get_parent():
		add_child.bind(chunk, true).call_deferred()

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
	chunk.material_override = get_shared_material_no_backfaces()
	chunk.cast_shadow = _chunk_shadow_casting

	if not chunk.get_parent():
		add_child.bind(chunk, true).call_deferred()

	_prism_chunks.append(chunk)
	return chunk


## Helper to get chunk from TileRef based on mesh mode
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
			if tile_ref.chunk_index < _box_chunks.size():
				return _box_chunks[tile_ref.chunk_index]
		GlobalConstants.MeshMode.PRISM_MESH:
			if tile_ref.chunk_index < _prism_chunks.size():
				return _prism_chunks[tile_ref.chunk_index]
	return null

##   Reindexes all chunks after removal to fix chunk_index corruption
## When chunks are removed, remaining chunks shift in array but chunk_index stays stale
## This causes tile_ref.chunk_index to point to wrong array positions
## Call this after removing chunks to restore consistency
func reindex_chunks() -> void:
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

	# Rebuild from box chunks
	for chunk_index: int in range(_box_chunks.size()):
		var chunk: BoxTileChunk = _box_chunks[chunk_index]
		for tile_key: int in chunk.tile_refs.keys():
			var instance_index: int = chunk.tile_refs[tile_key]

			# Create TileRef from chunk data
			var tile_ref: TileRef = TileRef.new()
			tile_ref.chunk_index = chunk_index
			tile_ref.instance_index = instance_index
			tile_ref.mesh_mode = GlobalConstants.MeshMode.BOX_MESH

			_tile_lookup[tile_key] = tile_ref

	# Rebuild from prism chunks
	for chunk_index: int in range(_prism_chunks.size()):
		var chunk: PrismTileChunk = _prism_chunks[chunk_index]
		for tile_key: int in chunk.tile_refs.keys():
			var instance_index: int = chunk.tile_refs[tile_key]

			# Create TileRef from chunk data
			var tile_ref: TileRef = TileRef.new()
			tile_ref.chunk_index = chunk_index
			tile_ref.instance_index = instance_index
			tile_ref.mesh_mode = GlobalConstants.MeshMode.PRISM_MESH

			_tile_lookup[tile_key] = tile_ref

## Saves tile data to persistent storage (called by placement manager)
## Uses columnar storage for efficient scene file serialization
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
	var _current_collisions_bodies: Array[StaticCollisionBody3D] = []

	for body in self.get_children():
		if body is StaticCollisionBody3D:
		# if body is StaticCollisionBody3D or body.name == "CollisionObjects":
			_current_collisions_bodies.append(body)

	# print("TileMapLayer3D: Clearing %d collision bodies..." % _current_collisions_bodies.size())

	for body in _current_collisions_bodies:
		if is_instance_valid(body):
			# Remove from parent first to ensure it's removed from scene tree
			if body.get_parent():
				body.get_parent().remove_child(body)
			body.queue_free()
	
	_current_collisions_bodies.clear()
	# _temp_collision_bodies.clear()
	# _collision_tile_keys.clear()

	# print("TileMapLayer3D: Collision cleared")

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
		var tile_data: TilePlacerData = null
		if _saved_tiles_lookup.has(tile_key):
			var tile_index: int = _saved_tiles_lookup[tile_key]
			if tile_index >= 0 and tile_index < get_tile_count():
				tile_data = get_tile_at(tile_index)

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
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()

	# Check 1: No tileset texture configured
	if not settings or not settings.tileset_texture:
		warnings.push_back("No tileset texture configured. Assign a texture in the Inspector (Settings > Tileset Texture).")

	# Check 2: Tile count exceeds recommended maximum
	# Use get_tile_count() - this is the authoritative runtime count
	# The columnar storage is updated during runtime tile operations
	var total_tiles: int = get_tile_count()
	if total_tiles > GlobalConstants.MAX_RECOMMENDED_TILES:
		warnings.push_back("Tile count (%d) exceeds recommended maximum (%d). Performance may degrade. Consider using multiple TileMapLayer3D nodes." % [
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
		warnings.push_back("Found %d tiles outside valid coordinate range (±%.1f). These tiles may display incorrectly." % [
			out_of_bounds_count,
			GlobalConstants.MAX_GRID_RANGE
		])

	return warnings
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
		var has_params: bool = (
			tile.spin_angle_rad != 0.0 or
			tile.tilt_angle_rad != 0.0 or
			tile.diagonal_scale != 0.0 or
			tile.tilt_offset_factor != 0.0
		)

		if has_params:
			_tile_transform_indices[i] = transform_entries.size()
			var params := PackedFloat32Array([
				tile.spin_angle_rad,
				tile.tilt_angle_rad,
				tile.diagonal_scale,
				tile.tilt_offset_factor
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


## Packs tile properties into a single int32
func _pack_tile_flags(tile: TilePlacerData) -> int:
	var flags: int = 0
	flags |= (tile.orientation & 0x1F)                  # Bits 0-4
	flags |= (tile.mesh_rotation & 0x3) << 5            # Bits 5-6
	flags |= (tile.mesh_mode & 0x3) << 7                # Bits 7-8
	flags |= (1 if tile.is_face_flipped else 0) << 9    # Bit 9
	flags |= ((tile.terrain_id + 128) & 0xFF) << 10     # Bits 10-17
	return flags


## Unpacks int32 flags into tile properties
func _unpack_tile_flags(flags: int, tile: TilePlacerData) -> void:
	tile.orientation = flags & 0x1F
	tile.mesh_rotation = (flags >> 5) & 0x3
	tile.mesh_mode = (flags >> 7) & 0x3
	tile.is_face_flipped = ((flags >> 9) & 0x1) == 1
	tile.terrain_id = ((flags >> 10) & 0xFF) - 128


## Returns the number of tiles stored
func get_tile_count() -> int:
	return _tile_positions.size()


## Gets tile data at index as TilePlacerData (for compatibility)
func get_tile_at(index: int) -> TilePlacerData:
	var tile := TilePlacerData.new()
	tile.grid_position = _tile_positions[index]

	var uv_idx: int = index * 4
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
		var param_base: int = transform_idx * 4
		tile.spin_angle_rad = _tile_transform_data[param_base]
		tile.tilt_angle_rad = _tile_transform_data[param_base + 1]
		tile.diagonal_scale = _tile_transform_data[param_base + 2]
		tile.tilt_offset_factor = _tile_transform_data[param_base + 3]

	return tile


## Adds a tile to columnar storage
func add_tile_columnar(tile: TilePlacerData) -> int:
	var index: int = _tile_positions.size()

	_tile_positions.append(tile.grid_position)

	_tile_uv_rects.append(tile.uv_rect.position.x)
	_tile_uv_rects.append(tile.uv_rect.position.y)
	_tile_uv_rects.append(tile.uv_rect.size.x)
	_tile_uv_rects.append(tile.uv_rect.size.y)

	_tile_flags.append(_pack_tile_flags(tile))

	# Check for non-default transform params
	var has_params: bool = (
		tile.spin_angle_rad != 0.0 or
		tile.tilt_angle_rad != 0.0 or
		tile.diagonal_scale != 0.0 or
		tile.tilt_offset_factor != 0.0
	)

	if has_params:
		_tile_transform_indices.append(_tile_transform_data.size() / 4)
		_tile_transform_data.append(tile.spin_angle_rad)
		_tile_transform_data.append(tile.tilt_angle_rad)
		_tile_transform_data.append(tile.diagonal_scale)
		_tile_transform_data.append(tile.tilt_offset_factor)
	else:
		_tile_transform_indices.append(-1)

	return index


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
		# Remove transform data (4 floats)
		var param_base: int = transform_idx * 4
		for i in range(4):
			_tile_transform_data.remove_at(param_base)

		# Update indices that pointed past the removed entry
		for i in range(_tile_transform_indices.size()):
			if _tile_transform_indices[i] > transform_idx:
				_tile_transform_indices[i] -= 1


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


# ==============================================================================
# SAVE/RESTORE HELPERS - Strip MultiMesh buffers for scene file size reduction
# ==============================================================================

## Strips MultiMesh buffer data before scene save
func _strip_chunk_buffers_for_save() -> void:
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
	call_deferred("_rebuild_chunks_from_saved_data", false)
