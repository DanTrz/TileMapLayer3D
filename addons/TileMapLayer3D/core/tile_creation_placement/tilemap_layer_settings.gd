@tool
class_name TileMapLayerSettings
extends Resource

## Settings Resource for TileMapLayer3D nodes
## Stores all per-node configuration that should persist across scene saves
## This is the single source of truth for node-specific properties

# TILESET CONFIGURATION
@export_group("Tileset")

@export var tileset_texture: Texture2D = null:
	set(value):
		if tileset_texture != value:
			tileset_texture = value
			emit_changed()

@export var tile_size: Vector2i = GlobalConstants.DEFAULT_TILE_SIZE:
	set(value):
		if tile_size != value:
			tile_size = value
			emit_changed()

## Selected tile UV rect (for restoring selection when switching nodes)
@export var selected_tile_uv: Rect2 = Rect2():
	set(value):
		if selected_tile_uv != value:
			selected_tile_uv = value
			emit_changed()

## Multi-tile selection (array of UV rects)
@export var selected_tiles: Array[Rect2] = []:
	set(value):
		if selected_tiles != value:
			selected_tiles = value
			emit_changed()

## Tileset panel zoom level (1.0 = 100%, original size)
## Preserves zoom when switching between nodes
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
@export_group("Grid")

@export_range(0.1, 10.0, 0.1) var grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE:
	set(value):
		if grid_size != value:
			grid_size = value
			emit_changed()

## Grid snap size - minimum 0.5 (half-grid) due to coordinate system precision
## See TileKeySystem and GlobalConstants.MIN_SNAP_SIZE for limits
@export_range(0.5, 2.0, 0.5) var grid_snap_size: float = GlobalConstants.DEFAULT_GRID_SNAP:
	set(value):
		if grid_snap_size != value:
			grid_snap_size = value
			emit_changed()

## Cursor step size - minimum 0.5 due to coordinate system precision
## See TileKeySystem and GlobalConstants.MIN_SNAP_SIZE for limits
@export_range(0.5, 2.0, 0.5) var cursor_step_size: float = GlobalConstants.DEFAULT_CURSOR_STEP_SIZE:
	set(value):
		if cursor_step_size != value:
			cursor_step_size = value
			emit_changed()

# RENDERING
@export_group("Rendering")

## Shader rendering mode for tiles (Default or Toon)
@export var shader_mode: GlobalConstants.ShaderMode = GlobalConstants.ShaderMode.DEFAULT:
	set(value):
		if shader_mode != value:
			shader_mode = value
			emit_changed()

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

## List of animated tile definitions 
@export var animate_tiles_list: Dictionary[int, TileAnimData] = {}:
	set(value):
		if animate_tiles_list != value:
			animate_tiles_list = value
			emit_changed()

## Currently active animated tile for painting (-1 = none selected)
@export var active_animated_tile: int = -1:
	set(value):
		if active_animated_tile != value:
			active_animated_tile = value
			emit_changed()

## Checks if an animated tile is currently selected 
@export var has_animated_tile_selected: bool = false:
	set(value):
		if has_animated_tile_selected != value:
			has_animated_tile_selected = value
			emit_changed()


# AUTOTILE CONFIGURATION
@export_group("Autotile")

## Reference to the TileSet resource for autotiling
## Contains terrain definitions and peering bit configurations
@export var autotile_tileset: TileSet = null:
	set(value):
		if autotile_tileset != value:
			autotile_tileset = value
			emit_changed()

## Atlas source ID within the TileSet (usually 0)
## Most TileSets use source 0 as the primary atlas
@export var autotile_source_id: int = GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID:
	set(value):
		if autotile_source_id != value:
			autotile_source_id = value
			emit_changed()

## Which terrain set to use (usually 0)
## Most TileSets use terrain set 0 as the primary set
@export var autotile_terrain_set: int = GlobalConstants.AUTOTILE_DEFAULT_TERRAIN_SET:
	set(value):
		if autotile_terrain_set != value:
			autotile_terrain_set = value
			emit_changed()

## Currently active terrain for painting (-1 = none selected)
## Persists the last selected terrain for convenience
@export var autotile_active_terrain: int = GlobalConstants.AUTOTILE_NO_TERRAIN:
	set(value):
		if autotile_active_terrain != value:
			autotile_active_terrain = value
			emit_changed()

## Mesh mode for autotile placement (separate from manual mesh_mode)
## Only FLAT_SQUARE (0) and BOX_MESH (2) supported for autotile
@export var autotile_mesh_mode: int = GlobalConstants.MeshMode.FLAT_SQUARE:
	set(value):
		if autotile_mesh_mode != value:
			autotile_mesh_mode = value
			emit_changed()


## Autotile depth scale for BOX/PRISM mesh modes (0.1 - 1.0)
## Persists autotile depth setting when switching nodes (Autotile tab)
@export_range(0.1, 1.0, 0.1) var autotile_depth_scale: float = 0.1:
	set(value):
		if autotile_depth_scale != value:
			autotile_depth_scale = clampf(value, 0.1, 1.0)
			emit_changed()

@export_group("Vertex Editing")

## UV Select mode: 0 = TILE, 1 = POINTS
## Used to determine how to select the TExture from TileSetPanel
@export var uv_selection_mode: GlobalConstants.Tile_UV_Select_Mode = GlobalConstants.Tile_UV_Select_Mode.TILE: # Tile_UV_Select_Mode
	set(value):
		if uv_selection_mode != value:
			uv_selection_mode = value
			emit_changed()

# SHADER PARAMETERS
@export_group("Shader Parameters")

# Tile MultiMesh
@export var shader_albedo_color: Color = Color.WHITE:
	set(value):
		if shader_albedo_color != value:
			shader_albedo_color = value
			emit_changed()

@export_range(0.0, 1.0) var shader_alpha_threshold: float = 0.5:
	set(value):
		if shader_alpha_threshold != value:
			shader_alpha_threshold = value
			emit_changed()

@export var shader_use_nearest_texture: bool = true:
	set(value):
		if shader_use_nearest_texture != value:
			shader_use_nearest_texture = value
			emit_changed()

@export var shader_debug_show_backfaces: bool = false:
	set(value):
		if shader_debug_show_backfaces != value:
			shader_debug_show_backfaces = value
			emit_changed()

# Lighting Base
@export_range(1, 8) var shader_cuts: int = 3:
	set(value):
		if shader_cuts != value:
			shader_cuts = value
			emit_changed()

@export_range(0.0, 1.0) var shader_step_smoothness: float = 0.1:
	set(value):
		if shader_step_smoothness != value:
			shader_step_smoothness = value
			emit_changed()

@export_range(-2.0, 2.0) var shader_wrap: float = 0.0:
	set(value):
		if shader_wrap != value:
			shader_wrap = value
			emit_changed()

@export_range(1.0, 8.0) var shader_steepness: float = 1.0:
	set(value):
		if shader_steepness != value:
			shader_steepness = value
			emit_changed()

@export var shader_use_attenuation: bool = true:
	set(value):
		if shader_use_attenuation != value:
			shader_use_attenuation = value
			emit_changed()

@export var shader_clamp_diffuse_to_max: bool = false:
	set(value):
		if shader_clamp_diffuse_to_max != value:
			shader_clamp_diffuse_to_max = value
			emit_changed()

# Shadow Stylization
@export var shader_use_ramp: bool = false:
	set(value):
		if shader_use_ramp != value:
			shader_use_ramp = value
			emit_changed()

@export var shader_ramp_texture: Texture2D = null:
	set(value):
		if shader_ramp_texture != value:
			shader_ramp_texture = value
			emit_changed()

@export var shader_shadow_tint: Color = Color(0.2, 0.2, 0.3, 1.0):
	set(value):
		if shader_shadow_tint != value:
			shader_shadow_tint = value
			emit_changed()

@export_range(0.0, 1.0) var shader_shadow_tint_amount: float = 0.3:
	set(value):
		if shader_shadow_tint_amount != value:
			shader_shadow_tint_amount = value
			emit_changed()

@export var shader_use_borders: bool = false:
	set(value):
		if shader_use_borders != value:
			shader_use_borders = value
			emit_changed()

@export_range(0.0, 0.5, 0.001) var shader_border_width: float = 0.01:
	set(value):
		if shader_border_width != value:
			shader_border_width = value
			emit_changed()

# Specular
@export var shader_use_specular: bool = true:
	set(value):
		if shader_use_specular != value:
			shader_use_specular = value
			emit_changed()

@export_range(0.0, 1.0) var shader_specular_strength: float = 1.0:
	set(value):
		if shader_specular_strength != value:
			shader_specular_strength = value
			emit_changed()

@export_range(0.0, 32.0) var shader_specular_shininess: float = 16.0:
	set(value):
		if shader_specular_shininess != value:
			shader_specular_shininess = value
			emit_changed()

@export var shader_specular_map: Texture2D = null:
	set(value):
		if shader_specular_map != value:
			shader_specular_map = value
			emit_changed()

# Normal Map
@export var shader_normal_texture: Texture2D = null:
	set(value):
		if shader_normal_texture != value:
			shader_normal_texture = value
			emit_changed()

@export_range(0.0, 1.0) var shader_normal_strength: float = 1.0:
	set(value):
		if shader_normal_strength != value:
			shader_normal_strength = value
			emit_changed()

# Rim Light
@export var shader_use_rim: bool = true:
	set(value):
		if shader_use_rim != value:
			shader_use_rim = value
			emit_changed()

@export var shader_rim_color: Color = Color.WHITE:
	set(value):
		if shader_rim_color != value:
			shader_rim_color = value
			emit_changed()

@export_range(0.0, 16.0) var shader_rim_amount: float = 2.0:
	set(value):
		if shader_rim_amount != value:
			shader_rim_amount = value
			emit_changed()

@export_range(0.0, 1.0) var shader_rim_smoothness: float = 0.2:
	set(value):
		if shader_rim_smoothness != value:
			shader_rim_smoothness = value
			emit_changed()

@export_range(0.0, 1.0) var shader_rim_mask_shadow: float = 1.0:
	set(value):
		if shader_rim_mask_shadow != value:
			shader_rim_mask_shadow = value
			emit_changed()

@export_range(0.0, 1.0) var shader_rim_blend: float = 1.0:
	set(value):
		if shader_rim_blend != value:
			shader_rim_blend = value
			emit_changed()

# Pattern General
@export var shader_use_pattern: bool = false:
	set(value):
		if shader_use_pattern != value:
			shader_use_pattern = value
			emit_changed()

@export_enum("Standard_Texture", "Dither3D") var shader_pattern_type: int = 1:
	set(value):
		if shader_pattern_type != value:
			shader_pattern_type = value
			emit_changed()

@export_range(0.0, 1.0) var shader_pattern_blend: float = 1.0:
	set(value):
		if shader_pattern_blend != value:
			shader_pattern_blend = value
			emit_changed()

# Pattern Standard Texture
@export var shader_pattern_texture: Texture2D = null:
	set(value):
		if shader_pattern_texture != value:
			shader_pattern_texture = value
			emit_changed()

@export_enum("UV", "Screen", "Local Screen") var shader_pattern_uv_mode: int = 2:
	set(value):
		if shader_pattern_uv_mode != value:
			shader_pattern_uv_mode = value
			emit_changed()

@export var shader_pattern_tiling: float = 32.0:
	set(value):
		if shader_pattern_tiling != value:
			shader_pattern_tiling = value
			emit_changed()

@export_range(0.0, 1.0) var shader_pattern_amount: float = 0.5:
	set(value):
		if shader_pattern_amount != value:
			shader_pattern_amount = value
			emit_changed()

@export_range(0.0, 1.0) var shader_pattern_smoothness: float = 0.5:
	set(value):
		if shader_pattern_smoothness != value:
			shader_pattern_smoothness = value
			emit_changed()

# Pattern Dither3D
@export var shader_dither_tex_3d: Texture3D = null:
	set(value):
		if shader_dither_tex_3d != value:
			shader_dither_tex_3d = value
			emit_changed()

@export var shader_dither_ramp_tex: Texture2D = null:
	set(value):
		if shader_dither_ramp_tex != value:
			shader_dither_ramp_tex = value
			emit_changed()

@export_range(2.0, 10.0) var shader_dither_dot_scale: float = 5.0:
	set(value):
		if shader_dither_dot_scale != value:
			shader_dither_dot_scale = value
			emit_changed()

@export_range(0.0, 2.0) var shader_dither_contrast: float = 1.0:
	set(value):
		if shader_dither_contrast != value:
			shader_dither_contrast = value
			emit_changed()

@export_range(0.0, 5.0) var shader_dither_input_exposure: float = 1.0:
	set(value):
		if shader_dither_input_exposure != value:
			shader_dither_input_exposure = value
			emit_changed()

@export_range(-1.0, 1.0) var shader_dither_input_offset: float = 0.0:
	set(value):
		if shader_dither_input_offset != value:
			shader_dither_input_offset = value
			emit_changed()

@export_range(0.0, 2.0, 0.01) var shader_dither_softness: float = 0.1:
	set(value):
		if shader_dither_softness != value:
			shader_dither_softness = value
			emit_changed()

@export_range(0.0, 1.0) var shader_dither_size_variability: float = 0.0:
	set(value):
		if shader_dither_size_variability != value:
			shader_dither_size_variability = value
			emit_changed()

@export_range(0.0, 2.0) var shader_dither_stretch_smoothness: float = 1.0:
	set(value):
		if shader_dither_stretch_smoothness != value:
			shader_dither_stretch_smoothness = value
			emit_changed()

@export var shader_dither_inverse_dots: bool = false:
	set(value):
		if shader_dither_inverse_dots != value:
			shader_dither_inverse_dots = value
			emit_changed()

@export var shader_dither_radial_compensation: bool = false:
	set(value):
		if shader_dither_radial_compensation != value:
			shader_dither_radial_compensation = value
			emit_changed()

@export var shader_dither_quantize_layers: bool = false:
	set(value):
		if shader_dither_quantize_layers != value:
			shader_dither_quantize_layers = value
			emit_changed()

# EDITOR STATE
@export_group("Sculpt Mode")

## Brush Type used in Sculpt Mode (Enum defined in Global Constants)
@export var sculpt_brush_type: GlobalConstants.SculptBrushType = GlobalConstants.SculptBrushType.DIAMOND:
	set(value):
		if sculpt_brush_type != value:
			sculpt_brush_type = value
			emit_changed()

## Brush Size used in Sculpt Mode 
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

@export_group("Smart Operations")

## Main mode for Smart Operations (Enum defined in Global Constants)
@export var smart_operations_main_mode: GlobalConstants.SmartOperationsMainMode = GlobalConstants.SmartOperationsMainMode.SMART_FILL:
	set(value):
		if smart_operations_main_mode != value:
			smart_operations_main_mode = value
			emit_changed()

## Determines if the feature smart_select is active or not
@export var is_smart_select_active: bool = false:
	set(value):
		if is_smart_select_active != value:
			is_smart_select_active = value
			emit_changed()

## Smart selection mode - determines how the smart selection algorithm behaves
## SINGLE_PICK = 0, # Pick tiles individually - Additive selection
## CONNECTED_UV = 1, # Smart Selection of all neighbours that share the same UV - Tile Texture
## CONNECTED_NEIGHBOR = 2, # Smart Selection of all neighbours on the same plane and rotation
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

## Main App mode: Manual, Auto-Tile, etc
## Persists which tab is active for this node
@export var main_app_mode: GlobalConstants.MainAppMode = GlobalConstants.MainAppMode.MANUAL:
	set(value):
		if main_app_mode != value:
			main_app_mode = value
			emit_changed()

## Multi-tile selection anchor index (0 = top-left)
## Used for stamp placement reference point
@export var selected_anchor_index: int = 0:
	set(value):
		if selected_anchor_index != value:
			selected_anchor_index = value
			emit_changed()

## Mesh mode: 0 = Square, 1 = Triangle
## Persists the mesh type for this node
@export var mesh_mode: int = 0:
	set(value):
		if mesh_mode != value:
			mesh_mode = value
			emit_changed()

## Current depth scale for BOX/PRISM mesh modes (0.1 - 1.0)
## Persists depth setting when switching nodes (Manual tab)
@export_range(0.1, 1.0, 0.1) var current_depth_scale: float = 0.1:
	set(value):
		if current_depth_scale != value:
			current_depth_scale = clampf(value, 0.1, 1.0)
			emit_changed()

## Current mesh rotation (0-3 = 0°, 90°, 180°, 270°)
## Persists Q/E rotation state when switching nodes
@export_range(0, 3, 1) var current_mesh_rotation: int = 0:
	set(value):
		if current_mesh_rotation != value:
			current_mesh_rotation = clampi(value, 0, 7)
			emit_changed()

## Current face flip state (F key toggle)
## Persists flip state when switching nodes
@export var is_face_flipped: bool = false:
	set(value):
		if is_face_flipped != value:
			is_face_flipped = value
			emit_changed()

## Texture repeat mode for BOX/PRISM mesh modes
## DEFAULT = Side faces use edge stripes, REPEAT = All faces use full texture
## Persists texture mode setting when switching nodes
@export var texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT:
	set(value):
		if texture_repeat_mode != value:
			texture_repeat_mode = value
			emit_changed()

# UTILITY METHODS
## Creates a new settings Resource with default values
static func create_default() -> TileMapLayerSettings:
	var settings: TileMapLayerSettings = TileMapLayerSettings.new()
	return settings

## Creates a duplicate of this settings Resource
func duplicate_settings() -> TileMapLayerSettings:
	var new_settings: TileMapLayerSettings = TileMapLayerSettings.new()
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
	# Autotile settings
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
	new_settings.smart_operations_main_mode = smart_operations_main_mode
	new_settings.is_smart_select_active = is_smart_select_active
	new_settings.smart_select_mode = smart_select_mode
	new_settings.smart_fill_mode = smart_fill_mode
	new_settings.smart_fill_width = smart_fill_width
	new_settings.smart_fill_quad_growth_dir = smart_fill_quad_growth_dir
	new_settings.animate_tiles_list = animate_tiles_list
	new_settings.active_animated_tile = active_animated_tile
	# Shader parameters
	new_settings.shader_albedo_color = shader_albedo_color
	new_settings.shader_alpha_threshold = shader_alpha_threshold
	new_settings.shader_use_nearest_texture = shader_use_nearest_texture
	new_settings.shader_debug_show_backfaces = shader_debug_show_backfaces
	new_settings.shader_cuts = shader_cuts
	new_settings.shader_step_smoothness = shader_step_smoothness
	new_settings.shader_wrap = shader_wrap
	new_settings.shader_steepness = shader_steepness
	new_settings.shader_use_attenuation = shader_use_attenuation
	new_settings.shader_clamp_diffuse_to_max = shader_clamp_diffuse_to_max
	new_settings.shader_use_ramp = shader_use_ramp
	new_settings.shader_ramp_texture = shader_ramp_texture
	new_settings.shader_shadow_tint = shader_shadow_tint
	new_settings.shader_shadow_tint_amount = shader_shadow_tint_amount
	new_settings.shader_use_borders = shader_use_borders
	new_settings.shader_border_width = shader_border_width
	new_settings.shader_use_specular = shader_use_specular
	new_settings.shader_specular_strength = shader_specular_strength
	new_settings.shader_specular_shininess = shader_specular_shininess
	new_settings.shader_specular_map = shader_specular_map
	new_settings.shader_normal_texture = shader_normal_texture
	new_settings.shader_normal_strength = shader_normal_strength
	new_settings.shader_use_rim = shader_use_rim
	new_settings.shader_rim_color = shader_rim_color
	new_settings.shader_rim_amount = shader_rim_amount
	new_settings.shader_rim_smoothness = shader_rim_smoothness
	new_settings.shader_rim_mask_shadow = shader_rim_mask_shadow
	new_settings.shader_rim_blend = shader_rim_blend
	new_settings.shader_use_pattern = shader_use_pattern
	new_settings.shader_pattern_type = shader_pattern_type
	new_settings.shader_pattern_blend = shader_pattern_blend
	new_settings.shader_pattern_texture = shader_pattern_texture
	new_settings.shader_pattern_uv_mode = shader_pattern_uv_mode
	new_settings.shader_pattern_tiling = shader_pattern_tiling
	new_settings.shader_pattern_amount = shader_pattern_amount
	new_settings.shader_pattern_smoothness = shader_pattern_smoothness
	new_settings.shader_dither_tex_3d = shader_dither_tex_3d
	new_settings.shader_dither_ramp_tex = shader_dither_ramp_tex
	new_settings.shader_dither_dot_scale = shader_dither_dot_scale
	new_settings.shader_dither_contrast = shader_dither_contrast
	new_settings.shader_dither_input_exposure = shader_dither_input_exposure
	new_settings.shader_dither_input_offset = shader_dither_input_offset
	new_settings.shader_dither_softness = shader_dither_softness
	new_settings.shader_dither_size_variability = shader_dither_size_variability
	new_settings.shader_dither_stretch_smoothness = shader_dither_stretch_smoothness
	new_settings.shader_dither_inverse_dots = shader_dither_inverse_dots
	new_settings.shader_dither_radial_compensation = shader_dither_radial_compensation
	new_settings.shader_dither_quantize_layers = shader_dither_quantize_layers
	return new_settings

## Copies values from another settings Resource
func copy_from(other: TileMapLayerSettings) -> void:
	if not other:
		return

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
	# Autotile settings
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
	smart_operations_main_mode = other.smart_operations_main_mode
	is_smart_select_active = other.is_smart_select_active
	smart_select_mode = other.smart_select_mode
	smart_fill_mode = other.smart_fill_mode
	smart_fill_width = other.smart_fill_width
	smart_fill_quad_growth_dir = other.smart_fill_quad_growth_dir
	animate_tiles_list = other.animate_tiles_list
	active_animated_tile = other.active_animated_tile
	# Shader parameters
	shader_albedo_color = other.shader_albedo_color
	shader_alpha_threshold = other.shader_alpha_threshold
	shader_use_nearest_texture = other.shader_use_nearest_texture
	shader_debug_show_backfaces = other.shader_debug_show_backfaces
	shader_cuts = other.shader_cuts
	shader_step_smoothness = other.shader_step_smoothness
	shader_wrap = other.shader_wrap
	shader_steepness = other.shader_steepness
	shader_use_attenuation = other.shader_use_attenuation
	shader_clamp_diffuse_to_max = other.shader_clamp_diffuse_to_max
	shader_use_ramp = other.shader_use_ramp
	shader_ramp_texture = other.shader_ramp_texture
	shader_shadow_tint = other.shader_shadow_tint
	shader_shadow_tint_amount = other.shader_shadow_tint_amount
	shader_use_borders = other.shader_use_borders
	shader_border_width = other.shader_border_width
	shader_use_specular = other.shader_use_specular
	shader_specular_strength = other.shader_specular_strength
	shader_specular_shininess = other.shader_specular_shininess
	shader_specular_map = other.shader_specular_map
	shader_normal_texture = other.shader_normal_texture
	shader_normal_strength = other.shader_normal_strength
	shader_use_rim = other.shader_use_rim
	shader_rim_color = other.shader_rim_color
	shader_rim_amount = other.shader_rim_amount
	shader_rim_smoothness = other.shader_rim_smoothness
	shader_rim_mask_shadow = other.shader_rim_mask_shadow
	shader_rim_blend = other.shader_rim_blend
	shader_use_pattern = other.shader_use_pattern
	shader_pattern_type = other.shader_pattern_type
	shader_pattern_blend = other.shader_pattern_blend
	shader_pattern_texture = other.shader_pattern_texture
	shader_pattern_uv_mode = other.shader_pattern_uv_mode
	shader_pattern_tiling = other.shader_pattern_tiling
	shader_pattern_amount = other.shader_pattern_amount
	shader_pattern_smoothness = other.shader_pattern_smoothness
	shader_dither_tex_3d = other.shader_dither_tex_3d
	shader_dither_ramp_tex = other.shader_dither_ramp_tex
	shader_dither_dot_scale = other.shader_dither_dot_scale
	shader_dither_contrast = other.shader_dither_contrast
	shader_dither_input_exposure = other.shader_dither_input_exposure
	shader_dither_input_offset = other.shader_dither_input_offset
	shader_dither_softness = other.shader_dither_softness
	shader_dither_size_variability = other.shader_dither_size_variability
	shader_dither_stretch_smoothness = other.shader_dither_stretch_smoothness
	shader_dither_inverse_dots = other.shader_dither_inverse_dots
	shader_dither_radial_compensation = other.shader_dither_radial_compensation
	shader_dither_quantize_layers = other.shader_dither_quantize_layers
