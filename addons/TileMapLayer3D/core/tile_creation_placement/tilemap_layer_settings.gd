@tool
class_name TileMapLayerSettings
extends Resource

## Settings Resource for TileMapLayer3D nodes
## Stores all per-node configuration that should persist across scene saves
## This is the single source of truth for node-specific properties

# ==============================================================================
# TILESET CONFIGURATION
# ==============================================================================

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

# ==============================================================================
# GRID CONFIGURATION
# ==============================================================================

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

# ==============================================================================
# RENDERING
# ==============================================================================

@export_group("Rendering")

@export_range(-128, 127, 1) var render_priority: int = GlobalConstants.DEFAULT_RENDER_PRIORITY:
	set(value):
		if render_priority != value:
			render_priority = value
			emit_changed()

# ==============================================================================
# COLLISION
# ==============================================================================

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

# ==============================================================================
# AUTOTILE CONFIGURATION
# ==============================================================================

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


@export_group("Vertex Editing")

## UV Select mode: 0 = TILE, 1 = POINTS
## Used to determine how to select the TExture from TileSetPanel
@export var uv_selection_mode: GlobalConstants.Tile_UV_Select_Mode = GlobalConstants.Tile_UV_Select_Mode.TILE: # Tile_UV_Select_Mode
	set(value):
		if uv_selection_mode != value:
			uv_selection_mode = value
			emit_changed()


# ==============================================================================
# EDITOR STATE
# ==============================================================================
# These properties persist the editor UI state per-node, ensuring:
# - Each node has isolated state (Node A can't corrupt Node B)
# - State persists with scene save
# - Node switching restores correct state automatically

@export_group("Editor State")

## Main App mode: Manual, Auto-Tile, etc
## Persists which tab is active for this node
@export var main_app_mode: GlobalConstants.MainAppMode = GlobalConstants.MainAppMode.MANUAL:
	set(value):
		if main_app_mode != value:
			main_app_mode = value
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

## Current depth scale for BOX/PRISM mesh modes (0.1 - 1.0)
## Persists depth setting when switching nodes (Manual tab)
@export_range(0.1, 1.0, 0.1) var current_depth_scale: float = 0.1:
	set(value):
		if current_depth_scale != value:
			current_depth_scale = clampf(value, 0.1, 1.0)
			emit_changed()

## Autotile depth scale for BOX/PRISM mesh modes (0.1 - 1.0)
## Persists autotile depth setting when switching nodes (Autotile tab)
@export_range(0.1, 1.0, 0.1) var autotile_depth_scale: float = 0.1:
	set(value):
		if autotile_depth_scale != value:
			autotile_depth_scale = clampf(value, 0.1, 1.0)
			emit_changed()

## Texture repeat mode for BOX/PRISM mesh modes
## DEFAULT = Side faces use edge stripes, REPEAT = All faces use full texture
## Persists texture mode setting when switching nodes
@export var texture_repeat_mode: int = GlobalConstants.TextureRepeatMode.DEFAULT:
	set(value):
		if texture_repeat_mode != value:
			texture_repeat_mode = value
			emit_changed()

# ==============================================================================
# UTILITY METHODS
# ==============================================================================

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
	new_settings.is_smart_select_active = is_smart_select_active
	new_settings.smart_select_mode = smart_select_mode
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
	is_smart_select_active = other.is_smart_select_active
	smart_select_mode = other.smart_select_mode




## Returns a Dictionary representation of all settings (useful for debugging)
func to_dict() -> Dictionary:
	return {
		"tileset_texture": tileset_texture.resource_path if tileset_texture else "null",
		"tile_size": tile_size,
		"texture_filter_mode": texture_filter_mode,
		"grid_size": grid_size,
		"grid_snap_size": grid_snap_size,
		"render_priority": render_priority,
		"enable_collision": enable_collision,
		"collision_layer": collision_layer,
		"collision_mask": collision_mask,
		"alpha_threshold": alpha_threshold,
		# Autotile settings
		"autotile_tileset": autotile_tileset.resource_path if autotile_tileset else "null",
		"autotile_source_id": autotile_source_id,
		"autotile_terrain_set": autotile_terrain_set,
		"autotile_active_terrain": autotile_active_terrain,
		"autotile_mesh_mode": autotile_mesh_mode,
		# Editor state
		"main_app_mode": main_app_mode,
		"selected_anchor_index": selected_anchor_index,
		"mesh_mode": mesh_mode,
		"current_mesh_rotation": current_mesh_rotation,
		"is_face_flipped": is_face_flipped,
		"smart_select_mode": smart_select_mode
	}
