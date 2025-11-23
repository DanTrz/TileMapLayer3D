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

@export_range(0.125, 2.0, 0.125) var grid_snap_size: float = GlobalConstants.DEFAULT_GRID_SNAP:
	set(value):
		if grid_snap_size != value:
			grid_snap_size = value
			emit_changed()

@export_range(0.25, 2.0, 0.25) var cursor_step_size: float = GlobalConstants.DEFAULT_CURSOR_STEP_SIZE:
	set(value):
		if cursor_step_size != value:
			cursor_step_size = value
			emit_changed()

# @export var _zAxis_tilt_offset: Vector3 = Vector3.ZERO: #south or north
# 	set(value):
# 		_zAxis_tilt_offset = value
# 		emit_changed()

# @export var _yAxis_tilt_offset: Vector3 = Vector3.ZERO: # floor or celling
# 	set(value):
# 		_yAxis_tilt_offset = value
# 		emit_changed()

# @export var _xAxis_tilt_offset: Vector3 = Vector3.ZERO: # east or west
# 	set(value):
# 		_xAxis_tilt_offset = value
# 		emit_changed()



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
		"alpha_threshold": alpha_threshold
	}
