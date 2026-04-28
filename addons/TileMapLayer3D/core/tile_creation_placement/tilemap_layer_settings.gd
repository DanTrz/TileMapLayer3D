@tool
class_name TileMapLayerSettings
extends Resource

## Per-node tilemap config (persists across saves)

# TILESET CONFIGURATION
@export_group("Tileset")

## Unified TileSet — single source of truth for texture, tile_size, and terrains.
## Both manual and autotile workflows read from this. Replaces tileset_texture
## and autotile_tileset; those fields remain only for backward-compatibility migration.
@export var tileset: TileSet = null:
	set(value):
		if tileset != value:
			tileset = value
			emit_changed()

## Which source within `tileset` manual mode draws from (default 0).
## Same value also drives autotile, so `autotile_source_id` is redundant going forward.
@export var active_source_id: int = GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID:
	set(value):
		if active_source_id != value:
			active_source_id = value
			emit_changed()

## Migration marker. 0 = legacy (tileset_texture / autotile_tileset still authoritative).
## 1 = unified `tileset` is authoritative. New resources start at 1 via create_default().
@export var _settings_format_version: int = 0:
	set(value):
		if _settings_format_version != value:
			_settings_format_version = value
			emit_changed()

## Parallel to `selected_tiles` — atlas coords resolved at pick time, used for storage writes.
@export var selected_atlas_coords: Array[Vector2i] = []:
	set(value):
		if selected_atlas_coords != value:
			selected_atlas_coords = value
			emit_changed()

## LEGACY — removed in Phase 6. Use TileAtlasResolver.get_active_texture(settings).
@export var tileset_texture: Texture2D = null:
	set(value):
		if tileset_texture != value:
			tileset_texture = value
			emit_changed()

## Pixel size of the picker grid in the Manual tab — drives the snap step for
## freeform drags and the visual cell overlay. Independent of `TileSet.tile_size`
## (the data authority for registered atlas cells) so users can drag oversized /
## off-grid regions without corrupting their TileSet's registered tiles.
@export var picker_tile_size: Vector2i = GlobalConstants.DEFAULT_TILE_SIZE:
	set(value):
		if picker_tile_size != value:
			picker_tile_size = value
			emit_changed()

## TileSet tile size at the settings level. Authored by the TileSet spinbox in
## the Manual tab. The handler also propagates the new value into the live
## `tileset.tile_size` and atlas `texture_region_size` (those are independent
## storages — there is no read-back mirror loop). Persisted on the node so a
## value exists even before a TileSet is configured.
## Distinct from `picker_tile_size`, which only drives the picker UI.
@export var tile_size: Vector2i = GlobalConstants.DEFAULT_TILE_SIZE:
	set(value):
		if tile_size != value:
			tile_size = value
			emit_changed()

@export var selected_tile_uv: Rect2 = Rect2():
	set(value):
		if selected_tile_uv != value:
			selected_tile_uv = value
			emit_changed()

@export var selected_tiles: Array[Rect2] = []:
	set(value):
		if selected_tiles != value:
			selected_tiles = value
			emit_changed()

@export_range(0.25, 4.0, 0.01) var tileset_zoom: float = GlobalConstants.TILESET_DEFAULT_ZOOM:
	set(value):
		if tileset_zoom != value:
			tileset_zoom = value
			emit_changed()

@export_enum("Nearest", "Nearest Mipmap", "Linear", "Linear Mipmap") var texture_filter_mode: int = GlobalConstants.DEFAULT_TEXTURE_FILTER:
	set(value):
		if texture_filter_mode != value:
			texture_filter_mode = value
			emit_changed()

@export_range(0.0, 1.0, 0.1) var pixel_inset_value: float = GlobalConstants.DEFAULT_PIXEL_INSET:
	set(value):
		if pixel_inset_value != value:
			pixel_inset_value = value
			emit_changed()


# GRID CONFIGURATION
@export_group("Grid and Tile Placement")

@export_range(0.1, 10.0, 0.1) var grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE:
	set(value):
		if grid_size != value:
			grid_size = value
			emit_changed()

## minimum 0.5 — smaller snaps break TileKeySystem's fixed-point encoding
@export_range(0.5, 2.0, 0.5) var grid_snap_size: float = GlobalConstants.DEFAULT_GRID_SNAP:
	set(value):
		if grid_snap_size != value:
			grid_snap_size = value
			emit_changed()

@export var enable_arched_tiles: bool = false:
	set(value):
		if enable_arched_tiles != value:
			enable_arched_tiles = value
			emit_changed()


@export_range(0.5, 2.0, 0.5) var cursor_step_size: float = GlobalConstants.DEFAULT_CURSOR_STEP_SIZE:
	set(value):
		if cursor_step_size != value:
			cursor_step_size = value
			emit_changed()

# RENDERING
@export_group("Rendering")

@export_range(-128, 127, 1) var render_priority: int = GlobalConstants.DEFAULT_RENDER_PRIORITY:
	set(value):
		if render_priority != value:
			render_priority = value
			emit_changed()

# COLLISION
@export_group("Collision")

@export var enable_collision: bool = true:
	set(value):
		if enable_collision != value:
			enable_collision = value
			emit_changed()

@export_flags_3d_physics var collision_layer: int = GlobalConstants.DEFAULT_COLLISION_LAYER:
	set(value):
		if collision_layer != value:
			collision_layer = value
			emit_changed()

@export_flags_3d_physics var collision_mask: int = GlobalConstants.DEFAULT_COLLISION_MASK:
	set(value):
		if collision_mask != value:
			collision_mask = value
			emit_changed()

@export_range(0.0, 1.0, 0.1) var alpha_threshold: float = GlobalConstants.DEFAULT_ALPHA_THRESHOLD:
	set(value):
		if alpha_threshold != value:
			alpha_threshold = value
			emit_changed()


# ANIMATED TILES CONFIGURATION
@export_group("AnimatedTiles")

@export var animate_tiles_list: Dictionary[int, TileAnimData] = {}:
	set(value):
		if animate_tiles_list != value:
			animate_tiles_list = value
			emit_changed()

@export var active_animated_tile: int = -1:
	set(value):
		if active_animated_tile != value:
			active_animated_tile = value
			emit_changed()

@export var has_animated_tile_selected: bool = false:
	set(value):
		if has_animated_tile_selected != value:
			has_animated_tile_selected = value
			emit_changed()


# AUTOTILE CONFIGURATION
@export_group("Autotile")

## Which terrain set within `tileset` is currently active for autotile painting.
## Replaces autotile_terrain_set. New name reflects unified-tileset architecture.
@export var active_terrain_set: int = GlobalConstants.AUTOTILE_DEFAULT_TERRAIN_SET:
	set(value):
		if active_terrain_set != value:
			active_terrain_set = value
			emit_changed()

## Currently selected terrain id (-1 = none). Replaces autotile_active_terrain.
@export var active_terrain: int = GlobalConstants.AUTOTILE_NO_TERRAIN:
	set(value):
		if active_terrain != value:
			active_terrain = value
			emit_changed()

## LEGACY — removed in Phase 6. Migrated into unified `tileset` on first load.
@export var autotile_tileset: TileSet = null:
	set(value):
		if autotile_tileset != value:
			autotile_tileset = value
			emit_changed()

## LEGACY — removed in Phase 6. Use `active_source_id`.
@export var autotile_source_id : int = GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID:
	set(value):
		if autotile_source_id != value:
			autotile_source_id = value
			emit_changed()

## LEGACY — removed in Phase 6. Use `active_terrain_set`.
@export var autotile_terrain_set: int = GlobalConstants.AUTOTILE_DEFAULT_TERRAIN_SET:
	set(value):
		if autotile_terrain_set != value:
			autotile_terrain_set = value
			emit_changed()

## LEGACY — removed in Phase 6. Use `active_terrain`.
@export var autotile_active_terrain : int = GlobalConstants.AUTOTILE_NO_TERRAIN:
	set(value):
		if autotile_active_terrain != value:
			autotile_active_terrain = value
			emit_changed()

## FLAT_SQUARE (0) or BOX_MESH (2) only — other modes not supported for autotile
@export var autotile_mesh_mode: int = GlobalConstants.MeshMode.FLAT_SQUARE:
	set(value):
		if autotile_mesh_mode != value:
			autotile_mesh_mode = value
			emit_changed()


@export_range(0.1, 1.0, 0.1) var autotile_depth_scale: float = 0.1:
	set(value):
		if autotile_depth_scale != value:
			autotile_depth_scale = clampf(value, 0.1, 1.0)
			emit_changed()

@export_group("Vertex Editing")

@export var uv_selection_mode: GlobalConstants.Tile_UV_Select_Mode = GlobalConstants.Tile_UV_Select_Mode.TILE: # Tile_UV_Select_Mode
	set(value):
		if uv_selection_mode != value:
			uv_selection_mode = value
			emit_changed()
# EDITOR STATE
@export_group("Sculpt Mode")

@export var sculpt_brush_type: GlobalConstants.SculptBrushType = GlobalConstants.SculptBrushType.DIAMOND:
	set(value):
		if sculpt_brush_type != value:
			sculpt_brush_type = value
			emit_changed()

@export_range(1, 3, 1) var sculpt_brush_size: float = GlobalConstants.SCULPT_BRUSH_SIZE_DEFAULT:
	set(value):
		if sculpt_brush_size != value:
			sculpt_brush_size = value
			emit_changed()

@export var sculpt_draw_top: bool = true:
	set(value):
		if sculpt_draw_top != value:
			sculpt_draw_top = value
			emit_changed()

@export var sculpt_draw_bottom: bool = false:
	set(value):
		if sculpt_draw_bottom != value:
			sculpt_draw_bottom = value
			emit_changed()

@export var sculpt_flip_sides: bool = false:
	set(value):
		if sculpt_flip_sides != value:
			sculpt_flip_sides = value
			emit_changed()

@export var sculpt_flip_top: bool = false:
	set(value):
		if sculpt_flip_top != value:
			sculpt_flip_top = value
			emit_changed()

@export var sculpt_flip_bottom: bool = false:
	set(value):
		if sculpt_flip_bottom != value:
			sculpt_flip_bottom = value
			emit_changed()

# @export var sculpt_arch_corners: bool = GlobalConstants.SCULPT_ARCH_CORNERS_DEFAULT:
# 	set(value):
# 		if sculpt_arch_corners != value:
# 			sculpt_arch_corners = value
# 			emit_changed()

@export_group("Smart Operations")

@export var smart_operations_main_mode: GlobalConstants.SmartOperationsMainMode = GlobalConstants.SmartOperationsMainMode.SMART_FILL:
	set(value):
		if smart_operations_main_mode != value:
			smart_operations_main_mode = value
			emit_changed()

@export var is_smart_select_active: bool = false:
	set(value):
		if is_smart_select_active != value:
			is_smart_select_active = value
			emit_changed()

@export var smart_select_mode: GlobalConstants.SmartSelectionMode = GlobalConstants.SmartSelectionMode.SINGLE_PICK:
	set(value):
		if smart_select_mode != value:
			smart_select_mode = value
			emit_changed()


@export var smart_fill_mode: GlobalConstants.SmartFillMode = GlobalConstants.SmartFillMode.FILL_RAMP:
	set(value):
		if smart_fill_mode != value:
			smart_fill_mode = value
			emit_changed()


@export var smart_fill_width: int = 1:
	set(value):
		if smart_fill_width != value:
			smart_fill_width = value
			emit_changed()


@export var smart_fill_quad_growth_dir: int = 0:
	set(value):
		if smart_fill_quad_growth_dir != value:
			smart_fill_quad_growth_dir = value
			emit_changed()

@export var smart_fill_flip_face: bool = false:
	set(value):
		if smart_fill_flip_face != value:
			smart_fill_flip_face = value
			emit_changed()

@export var smart_fill_ramp_sides: bool = false:
	set(value):
		if smart_fill_ramp_sides != value:
			smart_fill_ramp_sides = value
			emit_changed()

# EDITOR STATE
@export_group("Editor State")

@export var main_app_mode: GlobalConstants.MainAppMode = GlobalConstants.MainAppMode.MANUAL:
	set(value):
		if main_app_mode != value:
			main_app_mode = value
			emit_changed()

@export var selected_anchor_index: int = 0:  # 0 = top-left
	set(value):
		if selected_anchor_index != value:
			selected_anchor_index = value
			emit_changed()

@export var mesh_mode: int = 0:
	set(value):
		if mesh_mode != value:
			mesh_mode = value
			emit_changed()

@export_range(0.1, 1.0, 0.1) var current_depth_scale: float = 0.1:
	set(value):
		if current_depth_scale != value:
			current_depth_scale = clampf(value, 0.1, 1.0)
			emit_changed()

@export_range(0, 3, 1) var current_mesh_rotation: int = 0:  # 0=0° 1=90° 2=180° 3=270°
	set(value):
		if current_mesh_rotation != value:
			current_mesh_rotation = clampi(value, 0, 7)
			emit_changed()

@export var is_face_flipped: bool = false:
	set(value):
		if is_face_flipped != value:
			is_face_flipped = value
			emit_changed()

## DEFAULT = edge stripes on side faces, REPEAT = full texture on all faces
@export var texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT:
	set(value):
		if texture_repeat_mode != value:
			texture_repeat_mode = value
			emit_changed()

## Keep UV/texture fixed when rotating with Q/E
@export var freeze_uv_on_rotation: bool = false:
	set(value):
		if freeze_uv_on_rotation != value:
			freeze_uv_on_rotation = value
			emit_changed()

@export_range(0.1, 0.5, 0.1) var arch_radius_ratio: float = GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO:
	set(value):
		if arch_radius_ratio != value:
			arch_radius_ratio = clampf(value, GlobalConstants.ARCH_MIN_RADIUS_RATIO, GlobalConstants.ARCH_MAX_RADIUS_RATIO)
			emit_changed()

static func create_default() -> TileMapLayerSettings:
	var settings: TileMapLayerSettings = TileMapLayerSettings.new()
	# New resources skip migration — they're already in unified-tileset format.
	settings._settings_format_version = 1
	return settings

func duplicate_settings() -> TileMapLayerSettings:
	var new_settings: TileMapLayerSettings = TileMapLayerSettings.new()
	# Unified tileset
	new_settings.tileset = tileset
	new_settings.active_source_id = active_source_id
	new_settings._settings_format_version = _settings_format_version
	new_settings.selected_atlas_coords = selected_atlas_coords.duplicate()
	new_settings.picker_tile_size = picker_tile_size
	# Legacy fields (still serialised through Phase 5; removed in Phase 6)
	new_settings.tileset_texture = tileset_texture
	new_settings.tile_size = tile_size
	new_settings.selected_tile_uv = selected_tile_uv
	new_settings.selected_tiles = selected_tiles.duplicate()
	new_settings.tileset_zoom = tileset_zoom
	new_settings.texture_filter_mode = texture_filter_mode
	new_settings.pixel_inset_value = pixel_inset_value
	new_settings.grid_size = grid_size
	new_settings.grid_snap_size = grid_snap_size
	new_settings.cursor_step_size = cursor_step_size
	new_settings.render_priority = render_priority
	new_settings.enable_collision = enable_collision
	new_settings.collision_layer = collision_layer
	new_settings.collision_mask = collision_mask
	new_settings.alpha_threshold = alpha_threshold
	# Autotile settings (new + legacy)
	new_settings.active_terrain_set = active_terrain_set
	new_settings.active_terrain = active_terrain
	new_settings.autotile_tileset = autotile_tileset
	new_settings.autotile_source_id = autotile_source_id
	new_settings.autotile_terrain_set = autotile_terrain_set
	new_settings.autotile_active_terrain = autotile_active_terrain
	new_settings.autotile_mesh_mode = autotile_mesh_mode
	# Editor state
	new_settings.main_app_mode = main_app_mode
	new_settings.selected_anchor_index = selected_anchor_index
	new_settings.mesh_mode = mesh_mode
	new_settings.current_mesh_rotation = current_mesh_rotation
	new_settings.is_face_flipped = is_face_flipped
	new_settings.current_depth_scale = current_depth_scale
	new_settings.autotile_depth_scale = autotile_depth_scale
	new_settings.texture_repeat_mode = texture_repeat_mode
	new_settings.freeze_uv_on_rotation = freeze_uv_on_rotation
	new_settings.arch_radius_ratio = arch_radius_ratio
	new_settings.smart_operations_main_mode = smart_operations_main_mode
	new_settings.is_smart_select_active = is_smart_select_active
	new_settings.smart_select_mode = smart_select_mode
	new_settings.smart_fill_mode = smart_fill_mode
	new_settings.smart_fill_width = smart_fill_width
	new_settings.smart_fill_quad_growth_dir = smart_fill_quad_growth_dir
	new_settings.animate_tiles_list = animate_tiles_list
	new_settings.active_animated_tile = active_animated_tile
	return new_settings

func copy_from(other: TileMapLayerSettings) -> void:
	if not other:
		return

	# Unified tileset
	tileset = other.tileset
	active_source_id = other.active_source_id
	_settings_format_version = other._settings_format_version
	selected_atlas_coords = other.selected_atlas_coords.duplicate()
	picker_tile_size = other.picker_tile_size
	# Legacy fields
	tileset_texture = other.tileset_texture
	tile_size = other.tile_size
	selected_tile_uv = other.selected_tile_uv
	selected_tiles = other.selected_tiles.duplicate()
	tileset_zoom = other.tileset_zoom
	texture_filter_mode = other.texture_filter_mode
	pixel_inset_value = other.pixel_inset_value
	grid_size = other.grid_size
	grid_snap_size = other.grid_snap_size
	cursor_step_size = other.cursor_step_size
	render_priority = other.render_priority
	enable_collision = other.enable_collision
	collision_layer = other.collision_layer
	collision_mask = other.collision_mask
	alpha_threshold = other.alpha_threshold
	# Autotile settings (new + legacy)
	active_terrain_set = other.active_terrain_set
	active_terrain = other.active_terrain
	autotile_tileset = other.autotile_tileset
	autotile_source_id = other.autotile_source_id
	autotile_terrain_set = other.autotile_terrain_set
	autotile_active_terrain = other.autotile_active_terrain
	autotile_mesh_mode = other.autotile_mesh_mode
	# Editor state
	main_app_mode = other.main_app_mode
	selected_anchor_index = other.selected_anchor_index
	mesh_mode = other.mesh_mode
	current_mesh_rotation = other.current_mesh_rotation
	is_face_flipped = other.is_face_flipped
	current_depth_scale = other.current_depth_scale
	autotile_depth_scale = other.autotile_depth_scale
	texture_repeat_mode = other.texture_repeat_mode
	freeze_uv_on_rotation = other.freeze_uv_on_rotation
	arch_radius_ratio = other.arch_radius_ratio
	smart_operations_main_mode = other.smart_operations_main_mode
	is_smart_select_active = other.is_smart_select_active
	smart_select_mode = other.smart_select_mode
	smart_fill_mode = other.smart_fill_mode
	smart_fill_width = other.smart_fill_width
	smart_fill_quad_growth_dir = other.smart_fill_quad_growth_dir
	animate_tiles_list = other.animate_tiles_list
	active_animated_tile = other.active_animated_tile
