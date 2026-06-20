@icon("uid://b2snx34kyfmpg")
@tool
class_name TileMapLayer3D
extends Node3D

## Custom container node for 2.5D tile placement using MultiMesh for performance


@export_group("TileMapSettings")
## Per-node config — kept as a Resource so it saves/restores cleanly with the scene
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

@export_group("TileMapData")
## TileMapLayer3D node main storage. Columnar Format for Serialization
## Each tile's data is stored across parallel arrays
@export var tile_map_data: TileMapLayerData = null

@export_group("Decal Mode")
## If true, tiles render as decals and add offset to FLAT tiles (only Flat Tiles)
@export var enable_decal_mode: bool = false: 
	set(value):
		enable_decal_mode = value
		_apply_decal_mode()
	
## Target node that will be the base node for the decals to apply on top of
@export var decal_target_node: TileMapLayer3D = null 
@export var render_priority: int = GlobalConstants.DEFAULT_RENDER_PRIORITY
var _chunk_shadow_casting: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

@export_group("Debug Controls")
@export var show_chunk_bounds: bool = false:
	set(value):
		show_chunk_bounds = value
		_update_chunk_debug_visualization()

@export_tool_button("Run Debug Report") var debug_report_button = validate_columnar_data_quality


const ATLAS_COORDS_STRIDE: int = TileMapLayerData.ATLAS_COORDS_STRIDE
## Runtime group used to find sibling TileMapLayer3D nodes and warn on shared tile data.
## Added via add_to_group() at runtime (non-persistent) — never serialized into the scene.
const _DUPLICATION_GUARD_GROUP: StringName = &"_tilemaplayer3d_data_guard"
const _LEGACY_FLAT_CHUNK_ARRAY_PROPERTIES: Dictionary = {
	"_quad_chunks": true,
	"_triangle_chunks": true,
	"_box_chunks": true,
	"_prism_chunks": true,
	"_box_repeat_chunks": true,
	"_prism_repeat_chunks": true,
	"_arch_corner_chunks": true,
	"_arch_chunks": true,
	"_arch_i_chunks": true,
	"_arch_corner_i_chunks": true,
	"_arch_corner_cap_chunks": true,
	"_arch_corner_cap_i_chunks": true,
	"_arch_corner_cap_duo_chunks": true,
	"_arch_corner_c_chunks": true,
	"_arch_corner_c_i_chunks": true,
	"_arch_corner_s_chunks": true,
	"_arch_corner_s_i_chunks": true,
}

# Compatibility proxies: TileMapLayerData owns persisted columnar storage, while
# existing TileMapLayer3D code can keep using the old field names.
var _tile_positions: PackedVector3Array:
	get:
		return create_tile_map_data()._tile_positions
	set(value):
		create_tile_map_data()._tile_positions = value

var _tile_uv_rects: PackedFloat32Array:
	get:
		return create_tile_map_data()._tile_uv_rects
	set(value):
		create_tile_map_data()._tile_uv_rects = value

var _tile_atlas_source_ids: PackedInt32Array:
	get:
		return create_tile_map_data()._tile_atlas_source_ids
	set(value):
		create_tile_map_data()._tile_atlas_source_ids = value

var _tile_atlas_coords: PackedInt32Array:
	get:
		return create_tile_map_data()._tile_atlas_coords
	set(value):
		create_tile_map_data()._tile_atlas_coords = value

var _tile_flags: PackedInt32Array:
	get:
		return create_tile_map_data()._tile_flags
	set(value):
		create_tile_map_data()._tile_flags = value

var _flags_format_version: int:
	get:
		return create_tile_map_data()._flags_format_version
	set(value):
		create_tile_map_data()._flags_format_version = value

var _tile_transform_indices: PackedInt32Array:
	get:
		return create_tile_map_data()._tile_transform_indices
	set(value):
		create_tile_map_data()._tile_transform_indices = value

var _tile_transform_data: PackedFloat32Array:
	get:
		return create_tile_map_data()._tile_transform_data
	set(value):
		create_tile_map_data()._tile_transform_data = value

var _tile_custom_transforms: Dictionary:
	get:
		return create_tile_map_data()._tile_custom_transforms
	set(value):
		create_tile_map_data()._tile_custom_transforms = value

var _vertex_tile_corners: Dictionary:
	get:
		return create_tile_map_data()._vertex_tile_corners
	set(value):
		create_tile_map_data()._vertex_tile_corners = value

var _tile_anim_indices: PackedInt32Array:
	get:
		return create_tile_map_data()._tile_anim_indices
	set(value):
		create_tile_map_data()._tile_anim_indices = value

var _tile_anim_data: PackedFloat32Array:
	get:
		return create_tile_map_data()._tile_anim_data
	set(value):
		create_tile_map_data()._tile_anim_data = value

# Region registries.
# Key: packed region key (int64 from RegionSystem.pack())
# Value: Array of chunks in that region (allows sub-chunks when capacity exceeded)
# RUNTIME only. Chunks are rebuilt from columnar storage on load.
# Each registry maps region_key_packed (int) -> Array[TileChunkRender].
var _chunk_registry_quad: Dictionary = {}
var _chunk_registry_triangle: Dictionary = {}
var _chunk_registry_box: Dictionary = {}
var _chunk_registry_box_repeat: Dictionary = {}
var _chunk_registry_prism: Dictionary = {}
var _chunk_registry_prism_repeat: Dictionary = {}
var _chunk_registry_arch_corner: Dictionary = {}
var _chunk_registry_arch: Dictionary = {}
var _chunk_registry_arch_i: Dictionary = {}
var _chunk_registry_arch_corner_i: Dictionary = {}
var _chunk_registry_arch_corner_cap: Dictionary = {}
var _chunk_registry_arch_corner_cap_i: Dictionary = {}
var _chunk_registry_arch_corner_cap_duo: Dictionary = {}
var _chunk_registry_arch_corner_c: Dictionary = {}
var _chunk_registry_arch_corner_c_i: Dictionary = {}
var _chunk_registry_arch_corner_s: Dictionary = {}
var _chunk_registry_arch_corner_s_i: Dictionary = {}

# Debug visualization state
var _chunk_bounds_mesh: MeshInstance3D = null

# INTERNAL STATE (derived from settings Resource and tile_map_data Resource)
var tileset_texture: Texture2D = null
var grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE
var texture_filter_mode: int = GlobalConstants.DEFAULT_TEXTURE_FILTER
var pixel_inset_value: float = GlobalConstants.DEFAULT_PIXEL_INSET
var _saved_tiles_lookup: Dictionary = {}  # int (tile_key) -> Array index
var current_mesh_mode: GlobalConstants.MeshMode = GlobalConstants.DEFAULT_MESH_MODE

var _tile_lookup: Dictionary = {}  # int (tile_key) -> TileRef
var region_system: RegionSystem = RegionSystem.new()  ## Single source of truth for all spatial region operations.
var _shared_material: ShaderMaterial = null
var _shared_material_double_sided: ShaderMaterial = null  # For BOX_MESH/PRISM_MESH
var _shared_material_box_repeat: ShaderMaterial = null  # For BOX_MESH/PRISM_MESH in REPEAT mode (depth-corrected sides)
var _is_rebuilt: bool = false  # Track if chunks were rebuilt from saved data
var _reindex_in_progress: bool = false  # Prevent concurrent reindex during tile operations
var _vertex_tile_mesh_instances: Dictionary = {}  # Runtime: tile_key → MeshInstance3D for vertex tiles
var _vertex_tile_material: ShaderMaterial = null  # Shared material for vertex tile meshes
var _cached_warnings: PackedStringArray = PackedStringArray()
var _warnings_dirty: bool = true
var _active_placement_manager: TilePlacementManager = null  # Runtime/debug bridge for SpatialIndex and batch validation

var collision_layer: int = GlobalConstants.DEFAULT_COLLISION_LAYER
var collision_mask: int = GlobalConstants.DEFAULT_COLLISION_MASK

# Highlight overlay manager - EDITOR ONLY
var _highlight_manager: TileHighlightManager = null
var _collision_body: StaticCollisionBody3D = null
var smart_selected_tiles: Array[int] = [] # Items current under "Smart Selection"

## Runtime Procedural API. Lazy-initialized
## Public entry point for game scripts to call runtime API
var runtime_api: TileMapRuntimeAPI = null:
	get:
		if not runtime_api:
			runtime_api = TileMapRuntimeAPI.new(self)
		return runtime_api

## Reference to a tile's location in the chunk system
## Used to lookup of tile instance data
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
	var mesh_mode: GlobalConstants.MeshMode  # Drives TileMeshFactory dispatch
	var registry: Dictionary  # Reference to the chunk registry dictionary
	var name_prefix: String  # Prefix for chunk naming (e.g., "SquareChunk")
	var needs_double_sided: bool  # True for BOX/PRISM (use double-sided material)
	var texture_repeat_mode: int  # GlobalConstants.TextureRepeatMode value


# Chunk configurations - lazily initialized on first access
var _chunk_configs: Dictionary = {}  # int (config_key) -> ChunkConfig

func _ready() -> void:
	# Required so NOTIFICATION_TRANSFORM_CHANGED fires — we re-sync chunk instance
	# transforms manually (RenderingServer instances aren't scene-graph children).
	set_notify_transform(true)

	tile_map_data = create_tile_map_data()

	check_data_migration()

	# Check if columnar atlas arrays are out of sync
	if _tile_positions.size() > 0:
		var expected_src_size: int = _tile_positions.size()
		var expected_coords_size: int = expected_src_size * ATLAS_COORDS_STRIDE
		if _tile_atlas_source_ids.size() != expected_src_size:
			var old_size: int = _tile_atlas_source_ids.size()
			_tile_atlas_source_ids.resize(expected_src_size)
			for i in range(old_size, expected_src_size):
				_tile_atlas_source_ids[i] = -1  # Freeform sentinel
		if _tile_atlas_coords.size() != expected_coords_size:
			var old_coords_size: int = _tile_atlas_coords.size()
			_tile_atlas_coords.resize(expected_coords_size)
			for i in range(old_coords_size, expected_coords_size):
				_tile_atlas_coords[i] = -1  # Freeform sentinel (paired with source_id == -1)

	# Rebuild chunks from columnar data
	_rebuild_chunks_from_saved_data(false)

	# Create highlight overlay manager (golden selection + red blocked) — shared editor + runtime
	_highlight_manager = TileHighlightManager.new(self, grid_size)
	_highlight_manager.create_overlays()

	_apply_decal_mode()

	# Items to Skip at runtime
	if not Engine.is_editor_hint(): return

	# Ensure settings exists and is connected
	if not settings:
		settings = TileMapLayerSettings.new()

	# Apply settings to internal state
	_apply_settings()

	# Only rebuild if chunks don't exist (first load)
	# With pre-created nodes, chunks already exist at runtime
	# Check runtime registries to see if we need to rebuild
	var all_chunks_empty: bool = not _has_any_chunks()
	var has_tile_data: bool = _tile_positions.size() > 0
	if has_tile_data and all_chunks_empty and not _is_rebuilt:
		call_deferred("_rebuild_chunks_from_saved_data", false) 

## Initialize/created TileMapLayerdata storage
func create_tile_map_data() -> TileMapLayerData:
	if tile_map_data == null:
		tile_map_data = TileMapLayerData.new()
	return tile_map_data

## Temp code to migrate data model from previous versions to 1.0.2+
func check_data_migration() -> void:
	# AUTO-MIGRATE: Check for old 4-float transform format and upgrade to 5-float
	if _tile_positions.size() > 0 and _tile_transform_data.size() > 0:
		var format: int = _detect_transform_data_format()
		if format == 4:
			_migrate_4float_to_5float()
		elif format == -1:
			push_warning("TileMapLayer3D: Transform data may be corrupted (unexpected size)")

	# AUTO-MIGRATE: Upgrade 2-bit mesh_mode to 3-bit layout in tile flags
	if _tile_positions.size() > 0 and _tile_flags.size() > 0:
		_migrate_flags_2bit_to_3bit_mesh_mode()

	# AUTO-MIGRATE: Upgrade v1 (3-bit mesh_mode in middle) to v2 (10-bit mesh_mode at top)
	if _tile_positions.size() > 0 and _tile_flags.size() > 0:
		_migrate_flags_v1_to_v2()

	# AUTO-MIGRATE: Backfill animation indices for old/partially-loaded scenes
	# Handles both empty (pre-animated-tiles) and partially-filled arrays
	if _tile_positions.size() > 0 and _tile_anim_indices.size() < _tile_positions.size():
		var old_size: int = _tile_anim_indices.size()
		_tile_anim_indices.resize(_tile_positions.size())
		for i in range(old_size, _tile_positions.size()):
			_tile_anim_indices[i] = -1  # Mark missing entries as static (non-animated)

	# AUTO-MIGRATE: Unify legacy TileSet fields into TileMapLayerData.
	if settings != null and settings._settings_format_version == 0:
		_migrate_settings_v0_to_v1()
	else:
		_migrate_settings_tileset_to_data()

	# AUTO-MIGRATE: Ensure required custom data layer definitions exist on any loaded TileSet.
	# Definitions only — no tile creation, no default writes. Those only run for new TileSets.
	if get_tileset() != null:
		TileAtlasResolver.ensure_layer_definitions(get_tileset())
	tileset_texture = TileAtlasResolver.get_active_texture(self)

func get_tileset() -> TileSet:
	return create_tile_map_data().tileset

func set_tileset(value: TileSet) -> void:
	var data: TileMapLayerData = create_tile_map_data()
	if data.tileset == value:
		return
	data.tileset = value
	if value != null:
		TileAtlasResolver.ensure_layer_definitions(value)
	tileset_texture = TileAtlasResolver.get_active_texture(self) if value != null else null
	_update_material()
	notify_property_list_changed()

##Temp code to migrate TileSet from Settings to Data (from version 1.0.1+)
func _migrate_settings_tileset_to_data() -> void:
	if settings == null:
		return
	var data: TileMapLayerData = create_tile_map_data()
	if data.tileset == null and settings.tileset != null:
		data.tileset = settings.tileset
		print_verbose("TileMapLayer3D: Migrated settings.tileset -> tile_map_data.tileset")
	if settings.tileset != null:
		settings.tileset = null


func _notification(what: int) -> void:
	# World / transform / visibility / teardown notifications must run in BOTH editor and
	# runtime — they drive RenderingServer instance binding for the chunk render objects.
	match what:
		NOTIFICATION_ENTER_WORLD:
			_bind_all_chunks_to_world()
			return
		NOTIFICATION_EXIT_WORLD:
			_unbind_all_chunks_from_world()
			return
		NOTIFICATION_TRANSFORM_CHANGED:
			_update_all_chunk_transforms()
			return
		NOTIFICATION_VISIBILITY_CHANGED:
			_apply_visibility_to_chunks()
			return
		NOTIFICATION_PREDELETE:
			# RIDs are not ref-counted — free them before this node is destroyed.
			_free_all_chunk_rids()
			return

	# Editor-only save hooks.
	if not Engine.is_editor_hint():
		return

	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			# Flush externally-saved data/settings resources to disk (useful when Res are saved externally)
			_save_external_resources_if_needed()

func _on_settings_changed() -> void:
	if not Engine.is_editor_hint(): return
	_apply_settings()
	_apply_decal_mode()

func _apply_settings() -> void:
	if not settings:
		return

	tileset_texture = TileAtlasResolver.get_active_texture(self)
	texture_filter_mode = settings.texture_filter_mode
	pixel_inset_value = settings.pixel_inset_value

	# Apply grid configuration
	var old_grid_size: float = grid_size
	grid_size = settings.grid_size

	# Apply rendering configuration
	render_priority = settings.render_priority

	# Apply collision configuration
	collision_layer = settings.collision_layer
	collision_mask = settings.collision_mask
	# alpha_threshold = settings.alpha_threshold

	# Sync mesh mode from settings (ensures correct mode after reload/deserialization)
	current_mesh_mode = settings.mesh_mode as GlobalConstants.MeshMode

	# Update material if texture or filter changed
	if tileset_texture:
		_update_material()

	# Handle grid size change - requires chunk rebuild with mesh recreation
	if abs(old_grid_size - grid_size) > 0.001 and get_tile_count() > 0:
		_rescale_custom_transforms(old_grid_size, grid_size)
		call_deferred("_rebuild_chunks_from_saved_data", true)

	notify_property_list_changed()


func _apply_decal_mode() -> void:
	# if not Engine.is_editor_hint(): return
	if enable_decal_mode:	
		if not is_instance_valid(decal_target_node):
			return
		# Ensure render priority is higher than target node
		if render_priority == decal_target_node.render_priority:
			render_priority = decal_target_node.render_priority + 1

		# Disable shadow casting for decal mode
		if _chunk_shadow_casting != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_chunk_shadow_casting = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		_update_material()
	else:
		# Restore default shadow casting when exiting decal mode
		if _chunk_shadow_casting != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			_chunk_shadow_casting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		
		_update_material()

## Rescales custom transform origins when grid_size changes.
func _rescale_custom_transforms(old_grid_size: float, new_grid_size: float) -> void:
	if _tile_custom_transforms.is_empty():
		return
	var ratio: float = new_grid_size / old_grid_size
	for key: int in _tile_custom_transforms:
		var t: Transform3D = _tile_custom_transforms[key]
		t.origin *= ratio
		_tile_custom_transforms[key] = t


## Rebuilds MultiMesh chunks from columnar storage — called on scene load and when grid_size changes.
func _rebuild_chunks_from_saved_data(force_mesh_rebuild: bool = false) -> void:
	if force_mesh_rebuild:
		TileMeshFactory.invalidate()

	# Clear runtime registries. Chunks are rebuilt from columnar data.
	# _clear_all_chunk_registries() frees every existing chunk's RIDs first (single choke
	# point) — required or each rebuild (load / grid-size change) would leak all chunks.
	_clear_all_chunk_registries()
	_tile_lookup.clear()
	region_system.clear()

	_saved_tiles_lookup.clear()
	var tile_count: int = get_tile_count()
	for i in range(tile_count):
		# Read position and orientation from columnar storage to build key
		var grid_pos: Vector3 = _tile_positions[i]
		var flags: int = _tile_flags[i]
		var orientation: int = flags & 0x1F  # Bits 0-4
		var tile_key: Variant = GlobalUtil.make_tile_key(grid_pos, orientation)
		_saved_tiles_lookup[tile_key] = i

	# TEMP CODE: Auto-migrate old string keys to integer keys (backward compatibility)
	if _saved_tiles_lookup.size() > 0:
		var first_key: Variant = _saved_tiles_lookup.keys()[0]
		if first_key is String:
			_saved_tiles_lookup = GlobalUtil.migrate_placement_data(_saved_tiles_lookup)

	# Recreate tiles from saved data from columnar
	for i in range(tile_count):
		if not tileset_texture:
			push_warning("Cannot rebuild tiles: no tileset texture")
			break

		# Read position directly from columnar storage
		var grid_position: Vector3 = _tile_positions[i]
		var uv_idx: int = i * 4
		var uv_rect: Rect2 = Rect2(
			_tile_uv_rects[uv_idx],
			_tile_uv_rects[uv_idx + 1],
			_tile_uv_rects[uv_idx + 2],
			_tile_uv_rects[uv_idx + 3]
		)

		# Unpack flags directly
		var flags: int = _tile_flags[i]
		var orientation: int = flags & 0x1F  # Bits 0-4
		var mesh_rotation: int = (flags >> 5) & 0x3  # Bits 5-6
		var mesh_mode: int = (flags >> 22) & 0x3FF  # Bits 22-31
		var is_face_flipped: bool = bool(flags & (1 << 7))  # Bit 7
		var texture_repeat_mode: int = (flags >> 16) & 0x1  # Bit 16
		var freeze_uv: bool = bool((flags >> GlobalConstants.TILE_FLAG_BIT_FREEZE_UV) & 0x1)

		# Read transform params if present 
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

		var world_position: Vector3 = GlobalUtil.grid_to_world(grid_position, grid_size)
		var chunk: TileChunkRender = get_or_create_chunk(mesh_mode, texture_repeat_mode, world_position)
		var instance_index: int = chunk.get_visible_instance_count()

		# Check for custom transform (smart fill sloped tiles) via Dictionary lookup
		var tile_key_rebuild: int = GlobalUtil.make_tile_key(grid_position, orientation)
		var transform: Transform3D

		## rebuild path 1 with custom transform, used by Smart Fill (does not maintaing Grid Alignment)
		if _tile_custom_transforms.has(tile_key_rebuild):
			# Use stored world-space transform, convert origin to chunk-local
			transform = _tile_custom_transforms[tile_key_rebuild]
			transform.origin -= RegionSystem.region_key_to_world_origin(chunk.region_key)
			if is_face_flipped:
				transform.basis = transform.basis * Basis.from_scale(Vector3(1, 1, -1))

		## rebuild path 2 (Standard) used by all other modes and perfect Grid Alignment
		else:
			var local_world_pos: Vector3 = RegionSystem.world_to_region_local(world_position)
			var local_grid_pos: Vector3 = GlobalUtil.world_to_grid(local_world_pos, grid_size)

			# Build transform using LOCAL position
			var tile_depth_growth_mode: int = (flags >> GlobalConstants.TILE_FLAG_BIT_DEPTH_GROWTH_MODE) & 0x1
			var invert_depth: bool = tile_depth_growth_mode == GlobalConstants.DepthGrowthMode.INWARD
			transform = GlobalUtil.build_tile_transform(
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
				depth_scale,
				invert_depth
			)

		# Apply orientation offset to prevent Z-fighting (flat tiles always; BOX/PRISM when setting enabled)
		var offset: Vector3 = GlobalUtil.calculate_flat_tile_offset(
			orientation, mesh_mode,
			settings.auto_resolve_box_z_fighting, enable_decal_mode

		)
		transform.origin += offset

		chunk.set_instance_transform(instance_index, transform)

		# Set UV data (encode freeze-UV rotation into alpha if active)
		var atlas_size: Vector2 = tileset_texture.get_size()
		var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(uv_rect, atlas_size)
		var custom_data: Color = uv_data.uv_color
		if freeze_uv:
			custom_data.a = GlobalUtil.encode_uv_freeze_rotation(uv_data.uv_max.y, mesh_rotation, true)
		chunk.set_instance_custom_data(instance_index, custom_data)

		# Set animation COLOR for FLAT_SQUARE chunks (only chunk type with use_colors = true)
		# COLOR = (step_x, step_y, total_frames, encoded_cols_and_speed)
		if mesh_mode == GlobalConstants.MeshMode.FLAT_SQUARE and _tile_anim_indices.size() > i:
			var anim_idx: int = _tile_anim_indices[i]
			if anim_idx >= 0:
				var ab: int = anim_idx * 5
				if ab + 4 < _tile_anim_data.size():
					var step_x: float = _tile_anim_data[ab]
					var step_y: float = _tile_anim_data[ab + 1]
					var total_frames: float = _tile_anim_data[ab + 2]
					var anim_columns: float = _tile_anim_data[ab + 3]
					var speed_fps: float = _tile_anim_data[ab + 4]
					var encoded_cols_speed: float = anim_columns + speed_fps / 256.0
					chunk.set_instance_color(instance_index, Color(
						step_x, step_y, total_frames, encoded_cols_speed))

		# Increment visible count
		chunk.set_visible_count(chunk.get_visible_instance_count() + 1)
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
		_register_tile_in_region(tile_key, i, chunk)

	# Rebuild standalone MeshInstance3D nodes for vertex-edited tiles
	if not _vertex_tile_corners.is_empty():
		_rebuild_vertex_tile_meshes()

	_is_rebuilt = true
	_update_material()

	# Bind freshly-created chunk instances to the scenario so a live rebuild (load /
	# grid-size change) shows immediately. No-op if not yet in a World3D — the
	# ENTER_WORLD sweep will bind them then.
	if is_inside_tree():
		_bind_all_chunks_to_world()


##Central method to coordinate all material updates
##TODO: Simplify/ Refactor this.. It is too complex 
func _update_material() -> void:
	if tileset_texture:
		# Always recreate materials to ensure filter mode is applied
		_shared_material = GlobalUtil.create_tile_material(tileset_texture, texture_filter_mode, render_priority)
		_shared_material_double_sided = GlobalUtil.create_tile_material(
			tileset_texture, texture_filter_mode, render_priority, false)
		_shared_material_box_repeat = GlobalUtil.create_box_repeat_tile_material(
			tileset_texture, texture_filter_mode, render_priority)

		# Apply pixel inset to all materials
		_shared_material.set_shader_parameter("inset_value", pixel_inset_value)
		_shared_material_double_sided.set_shader_parameter("inset_value", pixel_inset_value)
		_shared_material_box_repeat.set_shader_parameter("inset_value", pixel_inset_value)

		_apply_material_to_registry(_chunk_registry_quad, _shared_material)
		_apply_material_to_registry(_chunk_registry_triangle, _shared_material)
		_apply_material_to_registry(_chunk_registry_box, _shared_material_double_sided)
		_apply_material_to_registry(_chunk_registry_prism, _shared_material_double_sided)
		# REPEAT box/prism use the depth-corrected side-face shader (see create_box_repeat_tile_material)
		_apply_material_to_registry(_chunk_registry_box_repeat, _shared_material_box_repeat)
		_apply_material_to_registry(_chunk_registry_prism_repeat, _shared_material_box_repeat)
		_apply_material_to_registry(_chunk_registry_arch_corner, _shared_material)
		_apply_material_to_registry(_chunk_registry_arch, _shared_material)
		_apply_material_to_registry(_chunk_registry_arch_i, _shared_material)
		_apply_material_to_registry(_chunk_registry_arch_corner_i, _shared_material)
		_apply_material_to_registry(_chunk_registry_arch_corner_cap, _shared_material)
		_apply_material_to_registry(_chunk_registry_arch_corner_cap_i, _shared_material)
		_apply_material_to_registry(_chunk_registry_arch_corner_cap_duo, _shared_material)
		_apply_material_to_registry(_chunk_registry_arch_corner_c, _shared_material)
		_apply_material_to_registry(_chunk_registry_arch_corner_c_i, _shared_material)
		_apply_material_to_registry(_chunk_registry_arch_corner_s, _shared_material)
		_apply_material_to_registry(_chunk_registry_arch_corner_s_i, _shared_material)



## Updates pixel inset on shared materials without recreating them (real-time slider)
func set_pixel_inset(value: float) -> void:
	pixel_inset_value = clampf(value, 0.0, 1.0)
	if _shared_material:
		_shared_material.set_shader_parameter("inset_value", pixel_inset_value)
	if _shared_material_double_sided:
		_shared_material_double_sided.set_shader_parameter("inset_value", pixel_inset_value)
	if _shared_material_box_repeat:
		_shared_material_box_repeat.set_shader_parameter("inset_value", pixel_inset_value)


## Updates UV rect of an existing tile (for autotiling neighbor updates).
func update_tile_uv(
	tile_key: int,
	new_uv: Rect2,
	atlas_source_id: int = -1,
	atlas_coords: Vector2i = Vector2i(-1, -1)
) -> bool:
	# Get tile reference
	var tile_ref: TileRef = _tile_lookup.get(tile_key, null)
	if tile_ref == null:
		push_warning("update_tile_uv: tile_key ", tile_key, " not found in _tile_lookup (", _tile_lookup.size(), " entries)")
		return false

	# Get the chunk based on mesh mode
	var chunk: TileChunkRender = _get_chunk_by_ref(tile_ref)

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

	# Re-encode freeze-UV rotation into the alpha channel for frozen tiles
	var uv_tile_index: int = _saved_tiles_lookup.get(tile_key, -1)
	if uv_tile_index >= 0 and uv_tile_index < _tile_flags.size():
		var uv_flags: int = _tile_flags[uv_tile_index]
		if bool((uv_flags >> GlobalConstants.TILE_FLAG_BIT_FREEZE_UV) & 0x1):
			var uv_mesh_rotation: int = (uv_flags >> 5) & 0x3  # Bits 5-6
			custom_data.a = GlobalUtil.encode_uv_freeze_rotation(uv_data.uv_max.y, uv_mesh_rotation, true)

	# Update the MultiMesh instance
	chunk.set_instance_custom_data(tile_ref.instance_index, custom_data)

	# Update the TileRef
	tile_ref.uv_rect = new_uv

	# Update columnar storage if the tile exists there
	if _saved_tiles_lookup.has(tile_key):
		var tile_index: int = _saved_tiles_lookup[tile_key]
		if tile_index >= 0 and tile_index < get_tile_count():
			update_tile_uv_columnar(tile_index, new_uv, atlas_source_id, atlas_coords)

			# Clear animation data — UV replacement means this is now a static tile
			if tile_index < _tile_anim_indices.size():
				var old_anim_idx: int = _tile_anim_indices[tile_index]
				if old_anim_idx >= 0:
					# Remove the 5-float animation entry from sparse storage
					var anim_base: int = old_anim_idx * 5
					if anim_base + 4 < _tile_anim_data.size():
						for j in range(5):
							_tile_anim_data.remove_at(anim_base)
						# Update indices that pointed past the removed entry
						for j in range(_tile_anim_indices.size()):
							if _tile_anim_indices[j] > old_anim_idx:
								_tile_anim_indices[j] -= 1
					_tile_anim_indices[tile_index] = -1

	# Reset MultiMesh instance color to non-animated default (FLAT_SQUARE only)
	if tile_ref.mesh_mode == GlobalConstants.MeshMode.FLAT_SQUARE:
		chunk.set_instance_color(tile_ref.instance_index, Color(1, 1, 1, 1))

	return true

func get_shared_material(debug_show_red_backfaces: bool) -> ShaderMaterial:
	# Ensure material exists before returning
	if not _shared_material and tileset_texture:
		_shared_material = GlobalUtil.create_tile_material(tileset_texture, texture_filter_mode, render_priority, debug_show_red_backfaces)
	return _shared_material

func get_shared_material_double_sided() -> ShaderMaterial:
	if not _shared_material_double_sided and tileset_texture:
		_shared_material_double_sided = GlobalUtil.create_tile_material(
			tileset_texture, texture_filter_mode, render_priority, false)
	return _shared_material_double_sided

## Material for REPEAT-mode BOX/PRISM chunks: depth-corrects the side faces so a thin box
## shows a depth_scale slice of the texture instead of squashing the whole texture.
func get_shared_material_box_repeat() -> ShaderMaterial:
	if not _shared_material_box_repeat and tileset_texture:
		_shared_material_box_repeat = GlobalUtil.create_box_repeat_tile_material(
			tileset_texture, texture_filter_mode, render_priority)
		_shared_material_box_repeat.set_shader_parameter("inset_value", pixel_inset_value)
	return _shared_material_box_repeat


## Uses dual-system CHUNKING: tiles are grouped by BOTH mesh type AND spatial region.
## resolve_region_key is the single function for ALL region key computation.
func get_or_create_chunk(
	mesh_mode: GlobalConstants.MeshMode = GlobalConstants.MeshMode.FLAT_SQUARE,
	texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT,
	world_position: Vector3 = Vector3.ZERO
) -> TileChunkRender:
	var region_key: Vector3i = RegionSystem.resolve_region_key(world_position)
	var region_key_packed: int = RegionSystem.pack(region_key)
	var config: ChunkConfig = _get_chunk_config(mesh_mode, texture_repeat_mode)
	return _get_or_create_chunk_in_region(region_key, region_key_packed, config)


## Lazily initializes ChunkConfig on first access
func _get_chunk_config(mesh_mode: GlobalConstants.MeshMode, texture_repeat: int) -> ChunkConfig:
	var key: int = mesh_mode * 10 + texture_repeat
	if not _chunk_configs.has(key):
		_chunk_configs[key] = _create_chunk_config(mesh_mode, texture_repeat)
	return _chunk_configs[key]


#TODO: MOVE TO ANOTHER CLASS
func _create_chunk_config(mesh_mode: GlobalConstants.MeshMode, texture_repeat: int) -> ChunkConfig:
	var config := ChunkConfig.new()
	config.texture_repeat_mode = texture_repeat

	config.mesh_mode = mesh_mode

	match mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE:
			config.registry = _chunk_registry_quad
			config.name_prefix = "SquareChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_TRIANGULE:
			config.registry = _chunk_registry_triangle
			config.name_prefix = "TriangleChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.BOX_MESH:
			config.needs_double_sided = true
			if texture_repeat == GlobalConstants.TextureRepeatMode.REPEAT:
				config.registry = _chunk_registry_box_repeat
				config.name_prefix = "BoxRepeatChunk"
			else:
				config.registry = _chunk_registry_box
				config.name_prefix = "BoxChunk"
		GlobalConstants.MeshMode.PRISM_MESH:
			config.needs_double_sided = true
			if texture_repeat == GlobalConstants.TextureRepeatMode.REPEAT:
				config.registry = _chunk_registry_prism_repeat
				config.name_prefix = "PrismRepeatChunk"
			else:
				config.registry = _chunk_registry_prism
				config.name_prefix = "PrismChunk"
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
			config.registry = _chunk_registry_arch_corner
			config.name_prefix = "ArchCornerChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_ARCH:
			config.registry = _chunk_registry_arch
			config.name_prefix = "ArchChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_ARCH_I:
			config.registry = _chunk_registry_arch_i
			config.name_prefix = "ArchIChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
			config.registry = _chunk_registry_arch_corner_i
			config.name_prefix = "ArchCornerIChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
			config.registry = _chunk_registry_arch_corner_cap
			config.name_prefix = "ArchCornerCapChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
			config.registry = _chunk_registry_arch_corner_cap_i
			config.name_prefix = "ArchCornerCapIChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
			config.registry = _chunk_registry_arch_corner_cap_duo
			config.name_prefix = "ArchCornerCapDuoChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C:
			config.registry = _chunk_registry_arch_corner_c
			config.name_prefix = "ArchCornerCChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I:
			config.registry = _chunk_registry_arch_corner_c_i
			config.name_prefix = "ArchCornerCIChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S:
			config.registry = _chunk_registry_arch_corner_s
			config.name_prefix = "ArchCornerSChunk"
			config.needs_double_sided = false
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
			config.registry = _chunk_registry_arch_corner_s_i
			config.name_prefix = "ArchCornerSIChunk"
			config.needs_double_sided = false

	return config


#TODO: MOVE TO ANOTHER CLASS
## Generic chunk factory - creates or reuses a chunk in the specified region
func _get_or_create_chunk_in_region(
	region_key: Vector3i,
	region_key_packed: int,
	config: ChunkConfig
) -> TileChunkRender:
	# Get or create registry entry for this region
	if not config.registry.has(region_key_packed):
		config.registry[region_key_packed] = []

	var region_chunks: Array = config.registry[region_key_packed]

	# Try to reuse existing chunk with space in this region
	for chunk in region_chunks:
		if chunk.has_space():
			return chunk

	# Create new RenderingServer-backed chunk
	var chunk: TileChunkRender = TileChunkRender.new()
	chunk.mesh_mode_type = config.mesh_mode
	chunk.region_key = region_key
	chunk.region_key_packed = region_key_packed
	chunk.texture_repeat_mode = config.texture_repeat_mode
	chunk.chunk_index = region_chunks.size()
	chunk.region_origin = RegionSystem.region_key_to_world_origin(region_key)
	chunk.chunk_name = "%s_R%d_%d_%d_C%d" % [
		config.name_prefix,
		region_key.x, region_key.y, region_key.z,
		chunk.chunk_index
	]

	# Shared mesh from the factory (handles texture_repeat for BOX/PRISM, arc_radius for ARCH).
	var arc_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO
	if settings:
		arc_ratio = settings.arch_radius_ratio
	var mesh: ArrayMesh = TileMeshFactory.get_mesh(
		config.mesh_mode, grid_size, config.texture_repeat_mode, arc_ratio)
	chunk.create_rids(mesh, TileMeshFactory.uses_colors(config.mesh_mode), true)

	# Apply appropriate material.
	# REPEAT-mode BOX/PRISM use the depth-corrected box-repeat shader on their side faces;
	# everything else falls back to the standard double-sided / single-sided material.
	var is_box_or_prism: bool = (
		config.mesh_mode == GlobalConstants.MeshMode.BOX_MESH
		or config.mesh_mode == GlobalConstants.MeshMode.PRISM_MESH
	)
	var material: ShaderMaterial
	if is_box_or_prism and config.texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT:
		material = get_shared_material_box_repeat()
	elif config.needs_double_sided:
		material = get_shared_material_double_sided()
	else:
		material = get_shared_material(false)
	if material:
		chunk.set_material(material.get_rid())

	chunk.set_cast_shadow(_chunk_shadow_casting)

	# Bind to the rendering scenario now if the node is already in a World3D; otherwise
	# the ENTER_WORLD sweep / end-of-rebuild bind will pick it up.
	var scenario: RID = _current_scenario()
	if scenario.is_valid():
		chunk.bind_scenario(scenario)
		chunk.set_world_transform(global_transform)
		chunk.set_visible(is_visible_in_tree())

	region_chunks.append(chunk)
	return chunk


## Current rendering scenario, or an invalid RID if the node is not in a World3D yet.
func _current_scenario() -> RID:
	var w: World3D = get_world_3d() if is_inside_tree() else null
	return w.scenario if w else RID()


## Bind every chunk's instance to the active scenario and sync its transform + visibility.
## Idempotent — safe to call from ENTER_WORLD and from the end of a rebuild.
func _bind_all_chunks_to_world() -> void:
	var scenario: RID = _current_scenario()
	if not scenario.is_valid():
		return
	var gx: Transform3D = global_transform
	var vis: bool = is_visible_in_tree()
	for chunk in _get_all_chunks():
		if chunk:
			chunk.bind_scenario(scenario)
			chunk.set_world_transform(gx)
			chunk.set_visible(vis)


## Detach every chunk's instance from the scenario (node leaving the World3D). RIDs survive.
func _unbind_all_chunks_from_world() -> void:
	for chunk in _get_all_chunks():
		if chunk:
			chunk.unbind_scenario()


## Re-compose every chunk instance transform after the node moves/rotates/scales.
## One RID call per chunk; per-tile transforms stay multimesh-local.
func _update_all_chunk_transforms() -> void:
	if not is_inside_tree():
		return
	var gx: Transform3D = global_transform
	for chunk in _get_all_chunks():
		if chunk:
			chunk.set_world_transform(gx)


## Mirror node visibility onto the chunk instances (RS instances don't auto-follow it).
func _apply_visibility_to_chunks() -> void:
	var vis: bool = is_visible_in_tree()
	for chunk in _get_all_chunks():
		if chunk:
			chunk.set_visible(vis)

#TODO: MOVE TO ANOTHER CLASS or GLOBAL UTIL
## Helper to get chunk from TileRef based on mesh mode, texture repeat mode, and region.
## Uses region registries for O(1) lookup by region_key_packed + chunk_index.
func _get_chunk_by_ref(tile_ref: TileRef) -> TileChunkRender:
	if tile_ref.chunk_index < 0:
		return null

	var registry: Dictionary = _get_chunk_registry_for_mode(tile_ref.mesh_mode, tile_ref.texture_repeat_mode)
	if registry.is_empty():
		return null

	if registry.has(tile_ref.region_key_packed):
		var region_chunks: Array = registry[tile_ref.region_key_packed]
		if tile_ref.chunk_index < region_chunks.size():
			return region_chunks[tile_ref.chunk_index]

	return null

#TODO: MOVE TO ANOTHER CLASS or GLOBAL UTIL
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


## Fixes stale chunk_index values after chunk removal (indices are PER-REGION)
func reindex_chunks() -> void:
	# FIX P1-13: Prevent concurrent reindex during tile operations
	if _reindex_in_progress:
		push_warning("reindex_chunks called while already reindexing - skipping to prevent corruption")
		return

	_reindex_in_progress = true

	# Helper function to reindex chunks within a region registry
	var reindex_registry = func(registry: Dictionary, chunk_type_name: String) -> void:
		for region_key_packed: int in registry.keys():
			var region_chunks: Array = registry[region_key_packed]
			for i in range(region_chunks.size()):
				var chunk: TileChunkRender = region_chunks[i]
				if chunk.chunk_index != i:
					if GlobalConstants.DEBUG_CHUNK_MANAGEMENT:
						var region: Vector3i = RegionSystem.unpack(region_key_packed)
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
	reindex_registry.call(_chunk_registry_arch_corner, "arch_corner")
	reindex_registry.call(_chunk_registry_arch, "arch")
	reindex_registry.call(_chunk_registry_arch_i, "arch_i")
	reindex_registry.call(_chunk_registry_arch_corner_i, "arch_corner_i")
	reindex_registry.call(_chunk_registry_arch_corner_cap, "arch_corner_cap")
	reindex_registry.call(_chunk_registry_arch_corner_cap_i, "arch_corner_cap_i")
	reindex_registry.call(_chunk_registry_arch_corner_cap_duo, "arch_corner_cap_duo")
	reindex_registry.call(_chunk_registry_arch_corner_c, "arch_corner_c")
	reindex_registry.call(_chunk_registry_arch_corner_c_i, "arch_corner_c_i")
	reindex_registry.call(_chunk_registry_arch_corner_s, "arch_corner_s")
	reindex_registry.call(_chunk_registry_arch_corner_s_i, "arch_corner_s_i")

	_reindex_in_progress = false  # FIX P1-13: Reset flag when complete


## Returns all chunks across all mesh types; may include null entries from freed chunks
func _get_all_chunks() -> Array:
	var all_chunks: Array = []
	for registry: Dictionary in _get_all_chunk_registries():
		for region_chunks: Array in registry.values():
			all_chunks.append_array(region_chunks)
	return all_chunks


## Auto-rebuilds _tile_lookup from chunks if lookup fails
func get_tile_ref(tile_key: Variant) -> TileRef:
	var ref: TileRef = _tile_lookup.get(tile_key, null)

	#  If lookup fails, rebuild from chunks and retry
	if not ref:
		push_warning("TileMapLayer3D: TileRef not in _tile_lookup for key '", tile_key, "', rebuilding from chunks...")
		_rebuild_tile_lookup_from_chunks()
		ref = _tile_lookup.get(tile_key, null)

	return ref

## Mirror a tile_key→TileRef into the runtime _tile_lookup. The region_system
## entry is registered separately by save_tile_data_direct (live placement) or
## _register_tile_in_region (scene-load rebuild) so the columnar index passed in
## is always the correct, final value — no -1 sentinel + patch dance.
func add_tile_ref(tile_key: Variant, tile_ref: TileRef) -> void:
	_tile_lookup[tile_key] = tile_ref

func remove_tile_ref(tile_key: Variant) -> void:
	var old_ref: TileRef = _tile_lookup.get(tile_key, null)
	if old_ref:
		region_system.unregister_tile(tile_key, old_ref.region_key_packed)
	_tile_lookup.erase(tile_key)


## Register a tile + its columnar index into the region system.
## Used by the rebuild path where the columnar index is known.
func _register_tile_in_region(tile_key: int, columnar_index: int, chunk: TileChunkRender) -> void:
	region_system.register_tile(tile_key, columnar_index, chunk.region_key_packed)

## Auto-recovers from desync by regenerating TileRefs from runtime chunk data
## With region-based chunking, iterates region registries for correct chunk indices
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
				var chunk: TileChunkRender = region_chunks[chunk_index]
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
	rebuild_from_registry.call(
		_chunk_registry_arch_corner,
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_arch,
		GlobalConstants.MeshMode.FLAT_ARCH,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_arch_i,
		GlobalConstants.MeshMode.FLAT_ARCH_I,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_arch_corner_i,
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_arch_corner_cap,
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_arch_corner_cap_i,
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_arch_corner_cap_duo,
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_arch_corner_c,
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_arch_corner_c_i,
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_arch_corner_s,
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)
	rebuild_from_registry.call(
		_chunk_registry_arch_corner_s_i,
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I,
		GlobalConstants.TextureRepeatMode.DEFAULT
	)

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
	texture_repeat_mode: int = 0,  # 0=DEFAULT, 1=REPEAT
	freeze_uv: bool = false,  # Freeze UV/texture in place when mesh is rotated via Q/E
	anim_step_x: float = 0.0,
	anim_step_y: float = 0.0,
	anim_total_frames: int = 1,
	anim_columns: int = 1,
	anim_speed_fps: float = 0.0,
	custom_transform: Transform3D = Transform3D(),
	atlas_source_id: int = -1,  # -1 = freeform (no atlas binding)
	atlas_coords: Vector2i = Vector2i(-1, -1),  # (-1, -1) = freeform (no atlas binding)
	depth_growth_mode: int = 0  # 0=OUTWARD (default), 1=INWARD
) -> void:

	#Main tile ID is the tile_key, which is a hash of grid_pos + orientation.
	var tile_key: Variant = GlobalUtil.make_tile_key(grid_pos, orientation)

	# If tile already exists at this position, remove it first
	if _saved_tiles_lookup.has(tile_key):
		remove_saved_tile_data(tile_key)

	# Add tile to columnar storage
	var new_index: int = add_tile_direct(
		grid_pos, uv_rect, orientation, mesh_rotation, mesh_mode,
		is_face_flipped, terrain_id, spin_angle, tilt_angle,
		diagonal_scale, tilt_offset, depth_scale, texture_repeat_mode, freeze_uv,
		anim_step_x, anim_step_y, anim_total_frames, anim_columns, anim_speed_fps,
		atlas_source_id, atlas_coords, depth_growth_mode
	)
	_saved_tiles_lookup[tile_key] = new_index

	# Register the tile into the region system with its final columnar index.
	var tile_ref_live: TileRef = _tile_lookup.get(tile_key, null)
	if tile_ref_live:
		region_system.register_tile(tile_key, new_index, tile_ref_live.region_key_packed)

	# Mark flags format as current v2 (ensures fresh scenes never trigger migration)
	if _flags_format_version < 2:
		_flags_format_version = 2

	# Store custom transform in Dictionary (independent of columnar arrays)
	if custom_transform != Transform3D():
		_tile_custom_transforms[tile_key] = custom_transform
	else:
		_tile_custom_transforms.erase(tile_key)

	_mark_data_changed()
	_assert_data_quality_if_enabled("save_tile_data_direct")


## Flags the TileMapLayerData SubResource as changed so Godot re-serializes and ensure it gets saved
func _mark_data_changed() -> void:
	create_tile_map_data().emit_changed()


## Save TileMapLayer3D resources to disk during scene PRE_SAVE.
func _save_external_resources_if_needed() -> void:
	GlobalUtil._save_external_resource(self, tile_map_data, "tile_map_data")
	GlobalUtil._save_external_resource(self, settings, "settings")


## Called by placement manager on erase.
func remove_saved_tile_data(tile_key: Variant) -> void:
	if not _saved_tiles_lookup.has(tile_key):
		return

	var tile_index: int = _saved_tiles_lookup[tile_key]
	_remove_tile_columnar(tile_index)
	_saved_tiles_lookup.erase(tile_key)
	_tile_custom_transforms.erase(tile_key)

	# Stable shift-remove keeps saved row order deterministic. Patch every cached
	# columnar index that moved down by one.
	for key in _saved_tiles_lookup.keys():
		if _saved_tiles_lookup[key] > tile_index:
			_saved_tiles_lookup[key] -= 1

	for region_key in region_system._registry.keys():
		var region: TerrainRegionChunk = region_system._registry[region_key]
		for i in range(region.columnar_indices.size()):
			if region.columnar_indices[i] > tile_index:
				region.columnar_indices[i] -= 1

	_mark_data_changed()
	_assert_data_quality_if_enabled("remove_saved_tile_data")


## Catches the operation that introduces corruption, not just the corrupted state later.
func _assert_data_quality_if_enabled(operation: String) -> void:
	if not GlobalConstants.DEBUG_VALIDATE_AFTER_MUTATION:
		return
	if not Engine.is_editor_hint():
		return
	var result: Dictionary = DebugInfoGenerator.validate_columnar_data_quality(self, false)
	if not result.get("valid", true):
		push_error(
			"Columnar data-quality validation FAILED after %s — quality=%s score=%d errors=%s" % [
				operation,
				result.get("quality", "?"),
				int(result.get("score", 0)),
				result.get("errors", [])
			]
		)


## Called by AutotilePlacementExtension after setting terrain_id on placement_data
func update_saved_tile_terrain(tile_key: int, terrain_id: int) -> void:
	if not _saved_tiles_lookup.has(tile_key):
		return
	var tile_index: int = _saved_tiles_lookup[tile_key]
	if tile_index >= 0 and tile_index < get_tile_count():
		update_tile_terrain_columnar(tile_index, terrain_id)

func clear_collision_shapes(region_key: Vector3i = Vector3i.MAX) -> void:
	for child in get_children():
		if child is not StaticCollisionBody3D:
			continue
		for shape_node in child.get_children():
			if shape_node is not RegionCollisionShape:
				continue
			if region_key == Vector3i.MAX or shape_node.region_key == region_key:
				shape_node.shape = null
				shape_node.queue_free()


## Find a terrain Region from a world_pos
func get_region_for_world_pos(world_pos: Vector3) -> TerrainRegionChunk:
	return region_system.region_for_world_pos(world_pos)

## Return all regions within a certain AABB 
func get_regions_for_world_aabb(world_aabb: AABB) -> Array[TerrainRegionChunk]:
	return region_system.regions_for_world_aabb(world_aabb)


# --- Highlight Overlay Delegates ---

## Highlights tiles by positioning golden overlay boxes at their transforms
func highlight_tiles(tile_keys: Array[int]) -> void:
	if _highlight_manager:
		_highlight_manager.highlight_tiles(tile_keys)


func clear_highlights() -> void:
	if _highlight_manager:
		_highlight_manager.clear_highlights()


## Shows a red blocked-position highlight at the given grid position
func show_blocked_highlight(grid_pos: Vector3, orientation: int) -> void:
	if _highlight_manager:
		_highlight_manager.show_blocked(grid_pos, orientation)


func clear_blocked_highlight() -> void:
	if _highlight_manager:
		_highlight_manager.clear_blocked()


func is_blocked_highlight_visible() -> bool:
	return _highlight_manager.is_blocked_visible() if _highlight_manager else false


## Shift+Drag area preview highlight
func highlight_tiles_in_area(start_pos: Vector3, end_pos: Vector3, orientation: int, is_erase: bool) -> void:
	if _highlight_manager:
		_highlight_manager.highlight_tiles_in_area(start_pos, end_pos, orientation, is_erase)


## Paint hover preview highlight at cursor position
func highlight_at_preview(grid_pos: Vector3, orientation: int, selected_tiles: Array[Rect2], mesh_rotation: int) -> void:
	if _highlight_manager:
		_highlight_manager.highlight_at_preview(grid_pos, orientation, selected_tiles, mesh_rotation)

# --- Configuration Warnings ---

## Returns configuration warnings to display in the Godot Inspector
func _get_configuration_warnings() -> PackedStringArray:
	# Return cached warnings if still valid
	if not _warnings_dirty:
		return _cached_warnings

	_cached_warnings.clear()

	# Check 1: No TileSet configured (or unified TileSet has no atlas texture)
	if not settings or TileAtlasResolver.get_active_texture(self) == null:
		_cached_warnings.push_back("No TileSet configured. Load a texture in the Tileset panel — a TileSet will be created automatically.")

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



# --- Columnar Storage and migration ---

## Detects transform data format: returns 4 (old), 5 (current), or -1 (corrupted)
## TODO: TEMP - DELETE
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
## TODO: TEMP - DELETE
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


## Migrates tile flags from old 2-bit mesh_mode layout to new 3-bit layout.
## Old: bits 7-8 mesh_mode(2), bit 9 flip, bits 10-17 terrain, bit ## TODO: TEMP - DELETE
func _migrate_flags_2bit_to_3bit_mesh_mode() -> void:
	# Version-based migration: old scenes have _flags_format_version == 0 (field didn't exist).
	# Scenes saved after migration or created with new code have version >= 1.
	if _flags_format_version >= 1:
		return  # Already in 3-bit format

	# Safety: detect if data was already migrated by old heuristic code
	# but _flags_format_version wasn't set yet.
	# mesh_mode >= 4 can ONLY exist in new format (old format max was 3).
	for i in range(_tile_flags.size()):
		if ((_tile_flags[i] >> 7) & 0x7) >= 4:
			_flags_format_version = 1  # Already new format, just stamp version
			return

	# Also check terrain_id position: for terrain_id=-1 (raw 127, the most common),
	# old format has 127 at bits 10-17, new format has 127 at bits 11-18.
	# Reading from the wrong position gives 254 instead of 127 — easily distinguishable.
	for i in range(_tile_flags.size()):
		var flags: int = _tile_flags[i]
		var terrain_old: int = (flags >> 10) & 0xFF  # Old position
		var terrain_new: int = (flags >> 11) & 0xFF  # New position
		if terrain_new == 127 and terrain_old != 127:
			_flags_format_version = 1  # Already new format
			return
		if terrain_old == 127 and terrain_new != 127:
			break  # Confirmed old format, proceed with migration

	# Migrate all flags: old 2-bit layout → new 3-bit layout
	for i in range(_tile_flags.size()):
		var old_flags: int = _tile_flags[i]
		var orientation: int = old_flags & 0x1F
		var mesh_rotation: int = (old_flags >> 5) & 0x3
		var mesh_mode: int = (old_flags >> 7) & 0x3
		var is_flipped: int = (old_flags >> 9) & 0x1
		var terrain_id_raw: int = (old_flags >> 10) & 0xFF
		var texture_repeat: int = (old_flags >> 18) & 0x1

		var new_flags: int = 0
		new_flags |= orientation & 0x1F
		new_flags |= (mesh_rotation & 0x3) << 5
		new_flags |= (mesh_mode & 0x7) << 7
		new_flags |= is_flipped << 10
		new_flags |= (terrain_id_raw & 0xFF) << 11
		new_flags |= (texture_repeat & 0x1) << 19
		_tile_flags[i] = new_flags

	_flags_format_version = 1
	print("TileMapLayer3D: Migrated %d tile flags from 2-bit to 3-bit mesh_mode layout" % _tile_flags.size())


## Migrates tile flags from v1 (3-bit mesh_mode in middle) to v2 (10-bit mesh_mode at top).
## TODO: TEMP - DELETE
func _migrate_flags_v1_to_v2() -> void:
	if _flags_format_version >= 2:
		return  # Already in v2 format

	for i in range(_tile_flags.size()):
		var old: int = _tile_flags[i]
		# Read v1 fields
		var orientation: int = old & 0x1F                  # Bits 0-4
		var mesh_rotation: int = (old >> 5) & 0x3          # Bits 5-6
		var mesh_mode: int = (old >> 7) & 0x7              # Bits 7-9
		var is_flipped: int = (old >> 10) & 0x1            # Bit 10
		var terrain_id_raw: int = (old >> 11) & 0xFF       # Bits 11-18
		var shared_bit: int = (old >> 19) & 0x1            # Bit 19 (tex_repeat OR freeze_uv)

		# Write v2 fields
		var new_flags: int = 0
		new_flags |= orientation & 0x1F                    # Bits 0-4: orientation
		new_flags |= (mesh_rotation & 0x3) << 5            # Bits 5-6: mesh_rotation
		new_flags |= is_flipped << 7                       # Bit 7: is_face_flipped
		new_flags |= (terrain_id_raw & 0xFF) << 8          # Bits 8-15: terrain_id
		new_flags |= shared_bit << 16                      # Bit 16: texture_repeat_mode
		new_flags |= shared_bit << 17                      # Bit 17: freeze_uv (copy shared bit to both)
		new_flags |= (mesh_mode & 0x3FF) << 22             # Bits 22-31: mesh_mode
		_tile_flags[i] = new_flags

	_flags_format_version = 2
	print("TileMapLayer3D: Migrated %d tile flags from v1 to v2 layout (mesh_mode at top)" % _tile_flags.size())


## TODO: TEMP - DELETE
func _migrate_settings_v0_to_v1() -> void:
	if settings == null:
		return
	if settings._settings_format_version >= 1:
		return  # Already migrated
	var migrated_tileset: TileSet = get_tileset()

	# Decide which legacy resource to adopt as the unified TileSet.
	# Preference: existing autotile_tileset (richer — has terrains) > synthetic from texture.
	if migrated_tileset == null:
		if settings.tileset != null:
			migrated_tileset = settings.tileset
			print_verbose("TileMapLayer3D: Migrated settings.tileset -> tile_map_data.tileset")
		elif settings.autotile_tileset != null:
			migrated_tileset = settings.autotile_tileset
			settings.active_source_id = settings.autotile_source_id
			# Carry across renamed autotile fields
			settings.active_terrain_set = settings.autotile_terrain_set
			settings.active_terrain = settings.autotile_active_terrain
			print_verbose("TileMapLayer3D: Migrated autotile_tileset -> tile_map_data.tileset")
		elif settings.tileset_texture != null:
			var tile_size: Vector2i = settings.tile_size
			if tile_size.x <= 0 or tile_size.y <= 0:
				tile_size = GlobalConstants.DEFAULT_TILE_SIZE
			migrated_tileset = _build_synthetic_tileset(settings.tileset_texture, tile_size)
			settings.active_source_id = 0
			print_verbose("TileMapLayer3D: Synthesised TileSet from legacy tileset_texture (tile_size=%s)" % str(tile_size))
		else:
			# Nothing to migrate. Mark version so we don't re-check every load.
			settings._settings_format_version = 1
			return

		create_tile_map_data().tileset = migrated_tileset
		TileAtlasResolver.initialize_custom_data_for_tileset(migrated_tileset)
		# Legacy field is migration-only — clear it now that the value lives on
		# TileMapLayerData, so it stops being re-serialized on the next save.
		settings.tileset = null

	# Backfill atlas_coords for tiles already persisted in columnar storage.
	if _tile_positions.size() > 0:
		_backfill_atlas_coords_from_uv_rects()

	# v0 had a single `tile_size` driving both the picker UI and the TileSet grid.
	# In v1 those are separate fields — seed `picker_tile_size` from the v0 value
	# so users keep the picker grid they had before. `settings.tile_size` itself
	# is unchanged: it now represents the TileSet authoritative tile size.
	if settings.tile_size.x > 0 and settings.tile_size.y > 0:
		settings.picker_tile_size = settings.tile_size

	settings._settings_format_version = 1


## TODO: TEMP - DELETE Builds an in-memory TileSet wrapping a loose Texture2D so legacy scenes keep working until migrated.
func _build_synthetic_tileset(texture: Texture2D, tile_size: Vector2i) -> TileSet:
	# Collect the set of grid cells touched by existing tiles' uv_rects (deduped).
	var used_cells: Dictionary = {}
	var tile_count: int = _tile_positions.size()
	for i in range(tile_count):
		if i * 4 + 3 >= _tile_uv_rects.size():
			break
		var rx: float = _tile_uv_rects[i * 4]
		var ry: float = _tile_uv_rects[i * 4 + 1]
		var col: int = int(round(rx / float(tile_size.x)))
		var row: int = int(round(ry / float(tile_size.y)))
		used_cells[Vector2i(max(col, 0), max(row, 0))] = true
	return TileAtlasResolver.build_tileset_from_texture(texture, tile_size, used_cells)


## Backfill of atlas binding data from UV rects for legacy scenes that predate atlas binding. 
## TODO: TEMP - DELETE
func _backfill_atlas_coords_from_uv_rects() -> void:
	var tile_count: int = _tile_positions.size()
	if tile_count == 0:
		return
	var tileset: TileSet = get_tileset()
	if tileset == null:
		push_warning("TileMapLayer3D: cannot backfill atlas_coords - no tileset")
		return
	var ts_size: Vector2i = tileset.tile_size
	if ts_size.x <= 0 or ts_size.y <= 0:
		push_warning("TileMapLayer3D: cannot backfill atlas_coords — tileset.tile_size is invalid")
		return

	var src_id: int = settings.active_source_id

	_tile_atlas_source_ids.resize(tile_count)
	_tile_atlas_coords.resize(tile_count * 2)

	var bound_count: int = 0
	var freeform_count: int = 0
	for i in range(tile_count):
		# Default to freeform sentinel; only flip to bound if we can verify it.
		_tile_atlas_source_ids[i] = -1
		_tile_atlas_coords[i * ATLAS_COORDS_STRIDE] = -1
		_tile_atlas_coords[i * ATLAS_COORDS_STRIDE + 1] = -1

		if i * 4 + 3 >= _tile_uv_rects.size():
			freeform_count += 1
			continue

		var rect: Rect2 = Rect2(
			_tile_uv_rects[i * 4],
			_tile_uv_rects[i * 4 + 1],
			_tile_uv_rects[i * 4 + 2],
			_tile_uv_rects[i * 4 + 3]
		)
		var col: int = int(round(rect.position.x / float(ts_size.x)))
		var row: int = int(round(rect.position.y / float(ts_size.y)))
		var candidate: Vector2i = Vector2i(col, row)

		if TileAtlasResolver.coords_match_registered_cell(self, src_id, candidate, rect):
			_tile_atlas_source_ids[i] = src_id
			_tile_atlas_coords[i * ATLAS_COORDS_STRIDE] = candidate.x
			_tile_atlas_coords[i * ATLAS_COORDS_STRIDE + 1] = candidate.y
			bound_count += 1
		else:
			freeform_count += 1

	print_verbose("TileMapLayer3D: Backfill complete — %d bound, %d freeform" % [bound_count, freeform_count])


func get_tile_count() -> int:
	return _tile_positions.size()


# --- Columnar Access Helpers ---

func has_tile(tile_key: int) -> bool:
	return _saved_tiles_lookup.has(tile_key)


## Returns index into columnar arrays, or -1 if not found
func get_tile_index(tile_key: int) -> int:
	return _saved_tiles_lookup.get(tile_key, -1)

## Reads columnar storage and finds the TileInfo based on a TileKey
func get_tile_info_from_key(tile_key: int) -> PlacedTileInfo:
	return get_tile_info_at_index(get_tile_index(tile_key))

## Reads tile data at index from columnar storage into a typed transient wrapper.
## Used with get_tile_index to get a position og tile in the storage as index than retrive the TileInfo
func get_tile_info_at_index(index: int) -> PlacedTileInfo:
	if index < 0 or index >= _tile_positions.size():
		return null

	var result := PlacedTileInfo.new()
	result.grid_position = _tile_positions[index]

	# Unpack UV rect (4 floats per tile)
	var uv_idx: int = index * 4
	if uv_idx + 3 < _tile_uv_rects.size():
		result.uv_rect = Rect2(
			_tile_uv_rects[uv_idx],
			_tile_uv_rects[uv_idx + 1],
			_tile_uv_rects[uv_idx + 2],
			_tile_uv_rects[uv_idx + 3]
		)
	else:
		result.uv_rect = Rect2()

	# Atlas binding (always present in the result Dictionary).
	# Value of -1 means "freeform — no atlas binding".
	# Out-of-range rows (e.g. arrays not yet padded) are reported as freeform too
	if index < _tile_atlas_source_ids.size():
		result.atlas_source_id = _tile_atlas_source_ids[index]
	else:
		result.atlas_source_id = -1
	var ac_idx: int = index * ATLAS_COORDS_STRIDE
	if ac_idx + 1 < _tile_atlas_coords.size():
		result.atlas_coords = Vector2i(_tile_atlas_coords[ac_idx], _tile_atlas_coords[ac_idx + 1])
	else:
		result.atlas_coords = Vector2i(-1, -1)

	# Unpack flags
	var flags: int = _tile_flags[index]
	result.orientation = flags & 0x1F
	result.mesh_rotation = (flags >> 5) & 0x3
	result.mesh_mode = (flags >> 22) & 0x3FF  # Bits 22-31
	result.is_face_flipped = ((flags >> 7) & 0x1) == 1  # Bit 7
	result.terrain_id = ((flags >> 8) & 0xFF) - 128  # Bits 8-15
	result.texture_repeat_mode = (flags >> 16) & 0x1  # Bit 16
	result.freeze_uv = bool((flags >> GlobalConstants.TILE_FLAG_BIT_FREEZE_UV) & 0x1)  # Bit 17
	result.depth_growth_mode = (flags >> GlobalConstants.TILE_FLAG_BIT_DEPTH_GROWTH_MODE) & 0x1  # Bit 20

	# Transform params with CORRECT backward-compatible defaults
	# Old tiles without custom params were never stored (sparse threshold = 1.0)
	result.spin_angle_rad = 0.0
	result.tilt_angle_rad = 0.0
	result.diagonal_scale = 0.0
	result.tilt_offset_factor = 0.0
	result.depth_scale = 1.0  #  Default 1.0 for old tiles!

	# Read custom transform params if stored
	var transform_idx: int = _tile_transform_indices[index]
	if transform_idx >= 0:
		var param_base: int = transform_idx * 5  # 5 floats per entry
		if param_base + 4 < _tile_transform_data.size():
			result.spin_angle_rad = _tile_transform_data[param_base]
			result.tilt_angle_rad = _tile_transform_data[param_base + 1]
			result.diagonal_scale = _tile_transform_data[param_base + 2]
			result.tilt_offset_factor = _tile_transform_data[param_base + 3]
			result.depth_scale = _tile_transform_data[param_base + 4]

	# Animation data with defaults (static tile)
	result.anim_step_x = 0.0
	result.anim_step_y = 0.0
	result.anim_total_frames = 1
	result.anim_columns = 1
	result.anim_speed_fps = 0.0

	if _tile_anim_indices.size() > index:
		var anim_idx: int = _tile_anim_indices[index]
		if anim_idx >= 0:
			var anim_base: int = anim_idx * 5
			if anim_base + 4 < _tile_anim_data.size():
				result.anim_step_x = _tile_anim_data[anim_base]
				result.anim_step_y = _tile_anim_data[anim_base + 1]
				result.anim_total_frames = int(_tile_anim_data[anim_base + 2])
				result.anim_columns = int(_tile_anim_data[anim_base + 3])
				result.anim_speed_fps = _tile_anim_data[anim_base + 4]

	# Custom transform (smart fill sloped tiles) — Dictionary lookup by tile_key
	var grid_pos_for_key: Vector3 = _tile_positions[index]
	var ori_for_key: int = result.orientation
	var lookup_key: int = GlobalUtil.make_tile_key(grid_pos_for_key, ori_for_key)
	result.tile_key = lookup_key
	if _tile_custom_transforms.has(lookup_key):
		result.custom_transform = _tile_custom_transforms[lookup_key]
		result.has_custom_transform = true

	# Attach runtime region reference so callers can navigate to TerrainRegionChunk directly.
	var tile_ref: TileRef = _tile_lookup.get(lookup_key, null)
	if tile_ref:
		result.terrain_region_chunk = region_system.get_region(tile_ref.region_key_packed)

	return result


## Cheap conservative LOCAL-space AABB for the tile at this columnar index.
func read_tile_world_aabb_at_index(index: int) -> AABB:
	if index < 0 or index >= _tile_positions.size():
		return AABB()
	var grid_pos: Vector3 = _tile_positions[index]
	var center: Vector3 = (grid_pos + GlobalConstants.GRID_ALIGNMENT_OFFSET) * grid_size

	var flags: int = _tile_flags[index] if index < _tile_flags.size() else 0
	var orientation: int = flags & 0x1F
	var mesh_mode: int = (flags >> 22) & 0x3FF

	var depth_scale: float = 1.0
	if index < _tile_transform_indices.size():
		var transform_idx: int = _tile_transform_indices[index]
		if transform_idx >= 0:
			var param_base: int = transform_idx * 5 + 4
			if param_base < _tile_transform_data.size():
				depth_scale = _tile_transform_data[param_base]

	var half_g: float = grid_size * 0.5
	# Thin slab thickness for flat tiles — generous enough to cover any spin/tilt
	# parameter wobble plus FLAT_TILE_ORIENTATION_OFFSET. Cheap padding.
	var flat_thickness: float = grid_size * 0.05

	var is_flat: bool = (mesh_mode == GlobalConstants.MeshMode.FLAT_SQUARE
			or mesh_mode == GlobalConstants.MeshMode.FLAT_TRIANGULE)

	if is_flat and orientation <= 5:
		# Base-plane flat tile — thin slab perpendicular to the plane normal.
		var ext: Vector3
		match orientation:
			0, 1:  # FLOOR / CEILING — normal ±Y
				ext = Vector3(half_g, flat_thickness, half_g)
			2, 3:  # WALL_NORTH / WALL_SOUTH — normal ±Z
				ext = Vector3(half_g, half_g, flat_thickness)
			4, 5:  # WALL_EAST / WALL_WEST — normal ±X
				ext = Vector3(flat_thickness, half_g, half_g)
			_:
				ext = Vector3(half_g, half_g, half_g)
		return AABB(center - ext, ext * 2.0)

	# Fallback: tilted flats (6–17), BOX, PRISM, arch variants.
	# sqrt(2) covers 45° rotation; depth_scale extends one axis but we apply
	const SQRT2: float = 1.41421356
	var half: float = half_g * SQRT2 * maxf(1.0, depth_scale)
	var ext_v: Vector3 = Vector3(half, half, half)
	return AABB(center - ext_v, ext_v * 2.0)


# --- Vertex Tile Helpers ---

## Returns true if this tile has vertex-edited data
func has_vertex_corners(tile_key: int) -> bool:
	return _vertex_tile_corners.has(tile_key)


## Returns the 4 world-space corners [BL, BR, TR, TL], or empty array if not vertex-edited
func get_vertex_corners(tile_key: int) -> PackedVector3Array:
	if _vertex_tile_corners.has(tile_key):
		var raw = _vertex_tile_corners[tile_key]
		if raw is VertexTileEntry:
			return (raw as VertexTileEntry).corners
	return PackedVector3Array()


## Returns the full VertexTileEntry for a tile, or null if not found
func get_vertex_entry(tile_key: int) -> VertexTileEntry:
	if _vertex_tile_corners.has(tile_key):
		var raw = _vertex_tile_corners[tile_key]
		if raw is VertexTileEntry:
			return raw as VertexTileEntry
	return null


## Sets the full vertex entry for a tile
func set_vertex_entry(tile_key: int, entry: VertexTileEntry) -> void:
	_vertex_tile_corners[tile_key] = entry
	_mark_data_changed()


## Updates just the corners within an existing vertex entry
func set_vertex_corners(tile_key: int, corners: PackedVector3Array) -> void:
	if _vertex_tile_corners.has(tile_key):
		var raw = _vertex_tile_corners[tile_key]
		if raw is VertexTileEntry:
			(raw as VertexTileEntry).corners = corners
	else:
		var entry := VertexTileEntry.new()
		entry.corners = corners
		_vertex_tile_corners[tile_key] = entry
	_mark_data_changed()


## Removes vertex data for a tile
func erase_vertex_corners(tile_key: int) -> void:
	_vertex_tile_corners.erase(tile_key)
	_mark_data_changed()


## Returns the full vertex tile corners dictionary for iteration (used by TileMeshMerger)
func get_vertex_tile_corners() -> Dictionary:
	return _vertex_tile_corners


func get_tile_custom_transforms() -> Dictionary:
	return _tile_custom_transforms


## Build an ArrayMesh for a vertex tile quad from world-space corners and UV rect.
## Shared by VertexEditManager.rebuild_mesh() and _rebuild_vertex_tile_meshes().
func build_vertex_tile_mesh(corners_world: PackedVector3Array, uv_rect: Rect2,
		atlas_size: Vector2, node_inv: Transform3D) -> ArrayMesh:
	var uv_min: Vector2 = uv_rect.position / atlas_size
	var uv_max: Vector2 = (uv_rect.position + uv_rect.size) / atlas_size

	# UV mapping matches _add_square_to_arrays convention:
	# corner[0]=BL(-X,-Z) → top-left, corner[2]=TR(+X,+Z) → bottom-right
	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2(uv_min.x, uv_min.y),  # BL → top-left of texture
		Vector2(uv_max.x, uv_min.y),  # BR → top-right of texture
		Vector2(uv_max.x, uv_max.y),  # TR → bottom-right of texture
		Vector2(uv_min.x, uv_max.y),  # TL → bottom-left of texture
	])

	var local_corners: PackedVector3Array = PackedVector3Array()
	for corner: Vector3 in corners_world:
		local_corners.append(node_inv * corner)

	# Normal: edge2 × edge1 gives correct outward-facing direction (+Y for floor tiles)
	var edge1: Vector3 = local_corners[1] - local_corners[0]
	var edge2: Vector3 = local_corners[3] - local_corners[0]
	var normal: Vector3 = edge2.cross(edge1).normalized()
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
	return mesh


## Get or create the shared ShaderMaterial for vertex tile rendering.
func ensure_vertex_material() -> ShaderMaterial:
	if _vertex_tile_material and is_instance_valid(_vertex_tile_material):
		if _vertex_tile_material.get_shader_parameter("albedo_texture") != tileset_texture:
			_vertex_tile_material.set_shader_parameter("albedo_texture", tileset_texture)
		return _vertex_tile_material

	var shader: Shader = load("res://addons/TileMapLayer3D/shaders/tile_vertex_edit.gdshader")
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_texture", tileset_texture)
	_vertex_tile_material = mat
	return mat


## Rebuild all vertex tile MeshInstance3D nodes from data
func _rebuild_vertex_tile_meshes() -> void:
	# Clean up any stale mesh instances
	for key: int in _vertex_tile_mesh_instances.keys():
		var mesh_inst: MeshInstance3D = _vertex_tile_mesh_instances[key]
		if is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
	_vertex_tile_mesh_instances.clear()

	if not tileset_texture:
		return

	var atlas_size: Vector2 = tileset_texture.get_size()
	if atlas_size.x <= 0.0 or atlas_size.y <= 0.0:
		return

	var mat: ShaderMaterial = ensure_vertex_material()
	var node_inv: Transform3D = global_transform.affine_inverse()

	for tile_key: int in _vertex_tile_corners.keys():
		var raw = _vertex_tile_corners[tile_key]
		if not raw is VertexTileEntry:
			continue
		var entry: VertexTileEntry = raw
		var corners: PackedVector3Array = entry.corners
		if corners.size() != 4:
			continue

		var uv_rect: Rect2 = entry.uv_rect
		var mesh: ArrayMesh = build_vertex_tile_mesh(corners, uv_rect, atlas_size, node_inv)

		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		mesh_inst.name = "VertexTile_%d" % tile_key
		mesh_inst.mesh = mesh
		mesh_inst.material_override = mat
		add_child(mesh_inst)
		_vertex_tile_mesh_instances[tile_key] = mesh_inst


## Destroy a single vertex tile mesh instance (used by VertexEditManager)
func destroy_vertex_mesh_instance(tile_key: int) -> void:
	if _vertex_tile_mesh_instances.has(tile_key):
		var mesh_inst: MeshInstance3D = _vertex_tile_mesh_instances[tile_key]
		if is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
		_vertex_tile_mesh_instances.erase(tile_key)

## Returns terrain_id from columnar storage, or -1 if tile doesn't exist
func get_tile_terrain_id(tile_key: int) -> int:
	var index: int = get_tile_index(tile_key)
	if index < 0:
		return GlobalConstants.AUTOTILE_NO_TERRAIN  # -1

	var flags: int = _tile_flags[index]
	return ((flags >> 8) & 0xFF) - 128  # Extract terrain_id from bits 8-15


## Returns grid position from columnar storage, or Vector3.ZERO if tile doesn't exist
func get_tile_grid_position(tile_key: int) -> Vector3:
	var index: int = get_tile_index(tile_key)
	if index < 0:
		return Vector3.ZERO
	return _tile_positions[index]


## Returns UV rect from columnar storage, or empty Rect2 if tile doesn't exist
func get_tile_uv_rect(tile_key: int) -> Rect2:
	var index: int = get_tile_index(tile_key)
	if index < 0:
		return Rect2()
	var uv_idx: int = index * 4
	return Rect2(
		_tile_uv_rects[uv_idx],
		_tile_uv_rects[uv_idx + 1],
		_tile_uv_rects[uv_idx + 2],
		_tile_uv_rects[uv_idx + 3]
	)


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
	texture_repeat_mode: int = 0,  # TEXTURE_REPEAT: 0=DEFAULT, 1=REPEAT
	freeze_uv: bool = false,  # Freeze UV/texture in place when mesh is rotated via Q/E
	anim_step_x: float = 0.0,
	anim_step_y: float = 0.0,
	anim_total_frames: int = 1,
	anim_columns: int = 1,
	anim_speed_fps: float = 0.0,
	atlas_source_id: int = -1,  # -1 = freeform (no atlas binding)
	atlas_coords: Vector2i = Vector2i(-1, -1),  # (-1, -1) = freeform (no atlas binding)
	depth_growth_mode: int = 0  # 0=OUTWARD (default), 1=INWARD
) -> int:
	var index: int = _tile_positions.size()

	# Add position
	_tile_positions.append(grid_pos)

	# Add UV rect (4 floats)
	_tile_uv_rects.append(uv_rect.position.x)
	_tile_uv_rects.append(uv_rect.position.y)
	_tile_uv_rects.append(uv_rect.size.x)
	_tile_uv_rects.append(uv_rect.size.y)

	# Persist atlas binding. The picker decides bound vs freeform at placement time;
	_tile_atlas_source_ids.append(atlas_source_id)
	_tile_atlas_coords.append(atlas_coords.x)
	_tile_atlas_coords.append(atlas_coords.y)

	# Pack and add flags (texture_repeat_mode bit 16, freeze_uv bit 17, depth_growth_mode bit 20)
	_tile_flags.append(_pack_flags_direct(orientation, mesh_rotation, mesh_mode, is_face_flipped, terrain_id, texture_repeat_mode, freeze_uv, depth_growth_mode))

	# Check for non-default transform params
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

	# ensure _tile_anim_indices matches other arrays before appending
	# _tile_positions already has this tile appended, so anim indices should be exactly 1 less
	while _tile_anim_indices.size() < _tile_positions.size() - 1:
		_tile_anim_indices.append(-1)

	# Animation data (sparse, same pattern as transform data)
	var is_animated: bool = anim_total_frames > 1
	if is_animated:
		_tile_anim_indices.append(_tile_anim_data.size() / 5)  # 5 floats per entry
		_tile_anim_data.append(anim_step_x)
		_tile_anim_data.append(anim_step_y)
		_tile_anim_data.append(float(anim_total_frames))
		_tile_anim_data.append(float(anim_columns))
		_tile_anim_data.append(anim_speed_fps)
	else:
		_tile_anim_indices.append(-1)

	return index


func _pack_flags_direct(orientation: int, mesh_rotation: int, mesh_mode: int, is_face_flipped: bool, terrain_id: int, texture_repeat_mode: int = 0, freeze_uv: bool = false, depth_growth_mode: int = 0) -> int:
	var flags: int = 0
	flags |= orientation & 0x1F  # Bits 0-4: orientation (0-17)
	flags |= (mesh_rotation & 0x3) << 5  # Bits 5-6: mesh_rotation (0-3)
	flags |= (mesh_mode & 0x3FF) << 22  # Bits 22-31: mesh_mode (0-1023)
	if is_face_flipped:
		flags |= 1 << 7  # Bit 7: is_face_flipped
	flags |= ((terrain_id + 128) & 0xFF) << 8  # Bits 8-15: terrain_id + 128
	flags |= (texture_repeat_mode & 0x1) << 16  # Bit 16: texture_repeat_mode
	if freeze_uv:
		flags |= 1 << GlobalConstants.TILE_FLAG_BIT_FREEZE_UV  # Bit 17: freeze_uv
	flags |= (depth_growth_mode & 0x1) << GlobalConstants.TILE_FLAG_BIT_DEPTH_GROWTH_MODE  # Bit 20: depth_growth_mode
	return flags


## DO NOT CALL DIRECTLY. Use remove_saved_tile_data
## Removes the tile at [param index] using stable shift-remove on every parallel
func _remove_tile_columnar(index: int) -> void:
	if index < 0 or index >= _tile_positions.size():
		return

	_tile_positions.remove_at(index)

	var uv_idx: int = index * 4
	for i in range(4):
		_tile_uv_rects.remove_at(uv_idx)

	if index < _tile_atlas_source_ids.size():
		_tile_atlas_source_ids.remove_at(index)
	var ac_idx: int = index * ATLAS_COORDS_STRIDE
	for i in range(ATLAS_COORDS_STRIDE):
		if ac_idx < _tile_atlas_coords.size():
			_tile_atlas_coords.remove_at(ac_idx)

	_tile_flags.remove_at(index)

	var transform_idx: int = _tile_transform_indices[index]
	_tile_transform_indices.remove_at(index)

	if transform_idx >= 0:
		var param_base: int = transform_idx * 5
		if param_base + 4 < _tile_transform_data.size():
			for i in range(5):
				_tile_transform_data.remove_at(param_base)
			for i in range(_tile_transform_indices.size()):
				if _tile_transform_indices[i] > transform_idx:
					_tile_transform_indices[i] -= 1
					if _tile_transform_indices[i] < 0:
						push_error("_remove_tile_columnar: Transform index underflow at tile %d" % i)
						_tile_transform_indices[i] = -1
		else:
			push_error("_remove_tile_columnar: transform data index %d out of bounds (size=%d)" % [param_base, _tile_transform_data.size()])

	if index < _tile_anim_indices.size():
		var anim_idx: int = _tile_anim_indices[index]
		_tile_anim_indices.remove_at(index)

		if anim_idx >= 0:
			var anim_base: int = anim_idx * 5
			if anim_base + 4 < _tile_anim_data.size():
				for i in range(5):
					_tile_anim_data.remove_at(anim_base)
				for i in range(_tile_anim_indices.size()):
					if _tile_anim_indices[i] > anim_idx:
						_tile_anim_indices[i] -= 1
						if _tile_anim_indices[i] < 0:
							push_error("_remove_tile_columnar: Anim index underflow at tile %d" % i)
							_tile_anim_indices[i] = -1
			else:
				push_error("_remove_tile_columnar: anim data index %d out of bounds (size=%d)" % [anim_base, _tile_anim_data.size()])


## Updates a tile's uv_rect and (optionally) its atlas binding.
func update_tile_uv_columnar(
	index: int,
	uv_rect: Rect2,
	atlas_source_id: int = -1,
	atlas_coords: Vector2i = Vector2i(-1, -1)
) -> void:
	var uv_idx: int = index * 4
	_tile_uv_rects[uv_idx] = uv_rect.position.x
	_tile_uv_rects[uv_idx + 1] = uv_rect.position.y
	_tile_uv_rects[uv_idx + 2] = uv_rect.size.x
	_tile_uv_rects[uv_idx + 3] = uv_rect.size.y

	if index < _tile_atlas_source_ids.size():
		_tile_atlas_source_ids[index] = atlas_source_id
		var ac_idx: int = index * ATLAS_COORDS_STRIDE
		if ac_idx + 1 < _tile_atlas_coords.size():
			_tile_atlas_coords[ac_idx] = atlas_coords.x
			_tile_atlas_coords[ac_idx + 1] = atlas_coords.y

	_mark_data_changed()


func update_tile_terrain_columnar(index: int, terrain_id: int) -> void:
	var flags: int = _tile_flags[index]
	# Clear terrain bits and set new value
	flags &= ~(0xFF << 8)
	flags |= ((terrain_id + 128) & 0xFF) << 8
	_tile_flags[index] = flags
	_mark_data_changed()


func clear_all_tiles() -> void:
	_tile_positions.clear()
	_tile_uv_rects.clear()
	_tile_atlas_source_ids.clear()
	_tile_atlas_coords.clear()
	_tile_flags.clear()
	_tile_transform_indices.clear()
	_tile_transform_data.clear()
	_tile_custom_transforms.clear()
	_tile_anim_indices.clear()
	_tile_anim_data.clear()
	_saved_tiles_lookup.clear()

	# Clear vertex tiles and their runtime mesh instances
	for key: int in _vertex_tile_mesh_instances.keys():
		var mesh_inst = _vertex_tile_mesh_instances[key]
		if is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
	_vertex_tile_mesh_instances.clear()
	_vertex_tile_corners.clear()
	clear_runtime_chunks()

	_warnings_dirty = true  # FIX P2-24: Invalidate warnings on tile data change
	_mark_data_changed()
	notify_property_list_changed()


## Rebuilds the mesh geometry on all arch-type chunks when arc_radius_ratio changes.
## With shared meshes, we drop the cached arch meshes, build one fresh shared mesh per
## arch mesh_mode via the factory, and re-point every chunk's MultiMesh at it. Instance
## transforms and custom data are preserved.
func rebuild_arch_chunk_meshes() -> void:
	if not settings:
		return
	var radius_ratio: float = settings.arch_radius_ratio

	# Invalidate cached arch meshes so the factory rebuilds them at the new radius.
	TileMeshFactory.invalidate_arch()

	# (registry, mesh_mode) pairs for every arch variant.
	var arch_registries: Array = [
		[_chunk_registry_arch, GlobalConstants.MeshMode.FLAT_ARCH],
		[_chunk_registry_arch_i, GlobalConstants.MeshMode.FLAT_ARCH_I],
		[_chunk_registry_arch_corner, GlobalConstants.MeshMode.FLAT_ARCH_CORNER],
		[_chunk_registry_arch_corner_i, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I],
		[_chunk_registry_arch_corner_cap, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP],
		[_chunk_registry_arch_corner_cap_i, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I],
		[_chunk_registry_arch_corner_cap_duo, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO],
		[_chunk_registry_arch_corner_c, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C],
		[_chunk_registry_arch_corner_c_i, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I],
		[_chunk_registry_arch_corner_s, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S],
		[_chunk_registry_arch_corner_s_i, GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I],
	]

	for entry in arch_registries:
		var registry: Dictionary = entry[0]
		var mesh_mode: GlobalConstants.MeshMode = entry[1]
		if registry.is_empty():
			continue
		var new_mesh: ArrayMesh = TileMeshFactory.get_mesh(
			mesh_mode, grid_size, GlobalConstants.TextureRepeatMode.DEFAULT, radius_ratio)
		for region_chunks: Array in registry.values():
			for chunk in region_chunks:
				if chunk:
					chunk.set_mesh(new_mesh)


# --- Aabb Validation and Debug ---

## Ensures all chunks have the correct LOCAL AABB set
## Call this after rebuilding chunks or if visibility issues are suspected
func validate_and_fix_chunk_aabbs() -> int:
	return DebugInfoGenerator.validate_and_fix_chunk_aabbs(self)


func debug_print_chunk_aabbs() -> void:
	DebugInfoGenerator.print_chunk_aabbs(self)

func debug_verify_tiles_in_aabbs() -> int:
	return DebugInfoGenerator.verify_tiles_in_aabbs(self)

## Runs a read-only data-quality audit for columnar storage, lookup, regions, chunks, SpatialIndex, and batch state.
func validate_columnar_data_quality(print_report: bool = true) -> Dictionary:
	if print_report:
		return DebugInfoGenerator.print_columnar_data_quality_report(self)
	return DebugInfoGenerator.validate_columnar_data_quality(self)


## Returns the same audit as text without printing it.
func get_columnar_data_quality_report() -> String:
	return DebugInfoGenerator.generate_columnar_data_quality_report(self)


#region Debug Visualization

func _update_chunk_debug_visualization() -> void:
	if show_chunk_bounds:
		_create_or_update_chunk_bounds_mesh()
	else:
		_destroy_chunk_bounds_mesh()


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
			_draw_wireframe_box(immediate_mesh, chunk.region_origin, GlobalConstants.CHUNK_REGION_SIZE)
		immediate_mesh.surface_end()

	_chunk_bounds_mesh.mesh = immediate_mesh


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


func _destroy_chunk_bounds_mesh() -> void:
	if _chunk_bounds_mesh:
		_chunk_bounds_mesh.queue_free()
		_chunk_bounds_mesh = null


func _get_all_chunk_registries() -> Array[Dictionary]:
	return [
		_chunk_registry_quad,
		_chunk_registry_triangle,
		_chunk_registry_box,
		_chunk_registry_box_repeat,
		_chunk_registry_prism,
		_chunk_registry_prism_repeat,
		_chunk_registry_arch_corner,
		_chunk_registry_arch,
		_chunk_registry_arch_i,
		_chunk_registry_arch_corner_i,
		_chunk_registry_arch_corner_cap,
		_chunk_registry_arch_corner_cap_i,
		_chunk_registry_arch_corner_cap_duo,
		_chunk_registry_arch_corner_c,
		_chunk_registry_arch_corner_c_i,
		_chunk_registry_arch_corner_s,
		_chunk_registry_arch_corner_s_i,
	]


func _get_chunk_registry_for_mode(mesh_mode: int, texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT) -> Dictionary:
	match mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE:
			return _chunk_registry_quad
		GlobalConstants.MeshMode.FLAT_TRIANGULE:
			return _chunk_registry_triangle
		GlobalConstants.MeshMode.BOX_MESH:
			return _chunk_registry_box_repeat if texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT else _chunk_registry_box
		GlobalConstants.MeshMode.PRISM_MESH:
			return _chunk_registry_prism_repeat if texture_repeat_mode == GlobalConstants.TextureRepeatMode.REPEAT else _chunk_registry_prism
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER:
			return _chunk_registry_arch_corner
		GlobalConstants.MeshMode.FLAT_ARCH:
			return _chunk_registry_arch
		GlobalConstants.MeshMode.FLAT_ARCH_I:
			return _chunk_registry_arch_i
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_I:
			return _chunk_registry_arch_corner_i
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP:
			return _chunk_registry_arch_corner_cap
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_I:
			return _chunk_registry_arch_corner_cap_i
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_CAP_DUO:
			return _chunk_registry_arch_corner_cap_duo
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C:
			return _chunk_registry_arch_corner_c
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_C_I:
			return _chunk_registry_arch_corner_c_i
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S:
			return _chunk_registry_arch_corner_s
		GlobalConstants.MeshMode.FLAT_ARCH_CORNER_S_I:
			return _chunk_registry_arch_corner_s_i
	return {}


func _count_chunks_in_registry(registry: Dictionary) -> int:
	var count: int = 0
	for region_chunks: Array in registry.values():
		count += region_chunks.size()
	return count


func _has_any_chunks() -> bool:
	for registry: Dictionary in _get_all_chunk_registries():
		if _count_chunks_in_registry(registry) > 0:
			return true
	return false


## Frees every chunk's RIDs (single choke point) then empties the registries. RIDs are not
## ref-counted, so this MUST run before dropping the chunk references or they leak.
func _clear_all_chunk_registries() -> void:
	_free_all_chunk_rids()
	for registry: Dictionary in _get_all_chunk_registries():
		registry.clear()


## Sweep every registry and free each chunk's RenderingServer resources.
func _free_all_chunk_rids() -> void:
	for chunk in _get_all_chunks():
		if chunk:
			chunk.free_rids()


func _apply_material_to_registry(registry: Dictionary, material: ShaderMaterial) -> void:
	var material_rid: RID = material.get_rid() if material else RID()
	for region_chunks: Array in registry.values():
		for chunk in region_chunks:
			if chunk:
				chunk.set_material(material_rid)
				chunk.set_cast_shadow(_chunk_shadow_casting)


func clear_runtime_chunks() -> void:
	for chunk in _get_all_chunks():
		if chunk:
			chunk.free_rids()
			chunk.tile_refs.clear()
			chunk.instance_to_key.clear()
	# Registries cleared directly here (RIDs already freed above).
	for registry: Dictionary in _get_all_chunk_registries():
		registry.clear()
	_tile_lookup.clear()
	region_system.clear()
