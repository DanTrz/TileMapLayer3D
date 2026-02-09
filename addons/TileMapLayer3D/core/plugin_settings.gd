@tool
class_name TilePlacerPluginSettings
extends Resource

## Global Plugin Settings Resource
## Stores editor-wide preferences that persist across editor sessions
## This is separate from TileMapLayerSettings (which are per-node)
##
## Usage:
##   - Plugin loads/saves this via EditorSettings
##   - Settings apply globally to all TileMapLayer3D nodes
##   - Changes are saved when modified through UI

# ==============================================================================
# UI PREFERENCES
# ==============================================================================

@export_group("UI Preferences")

## Show placement plane grids in 3D viewport
@export var show_plane_grids: bool = true:
	set(value):
		if show_plane_grids != value:
			show_plane_grids = value
			emit_changed()

## Default placement mode when opening editor
@export_enum("Plane", "Point", "Surface") var default_placement_mode: int = 0:
	set(value):
		if default_placement_mode != value:
			default_placement_mode = value
			emit_changed()

# ==============================================================================
# DEFAULT VALUES FOR NEW NODES
# ==============================================================================

@export_group("New Node Defaults")

## Default tile size for newly created TileMapLayer3D nodes
@export var default_tile_size: Vector2i = GlobalConstants.DEFAULT_TILE_SIZE:
	set(value):
		if default_tile_size != value:
			default_tile_size = value
			emit_changed()

## Default grid size for newly created TileMapLayer3D nodes
@export_range(0.1, 10.0, 0.1) var default_grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE:
	set(value):
		if default_grid_size != value:
			default_grid_size = value
			emit_changed()

## Default texture filter for newly created TileMapLayer3D nodes
@export_enum("Nearest", "Nearest Mipmap", "Linear", "Linear Mipmap") var default_texture_filter: int = GlobalConstants.DEFAULT_TEXTURE_FILTER:
	set(value):
		if default_texture_filter != value:
			default_texture_filter = value
			emit_changed()

## Enable collision by default for newly created TileMapLayer3D nodes
@export var default_enable_collision: bool = true:
	set(value):
		if default_enable_collision != value:
			default_enable_collision = value
			emit_changed()

## Default alpha threshold for collision generation
@export_range(0.0, 1.0, 0.1) var default_alpha_threshold: float = GlobalConstants.DEFAULT_ALPHA_THRESHOLD:
	set(value):
		if default_alpha_threshold != value:
			default_alpha_threshold = value
			emit_changed()

# ==============================================================================
# EDITOR BEHAVIOR
# ==============================================================================

@export_group("Editor Behavior")

## Auto-save scene after tile placement operations
@export var auto_save_after_placement: bool = false:
	set(value):
		if auto_save_after_placement != value:
			auto_save_after_placement = value
			emit_changed()

## Show debug information in console
@export var show_debug_info: bool = false:
	set(value):
		if show_debug_info != value:
			show_debug_info = value
			emit_changed()

## Maximum undo/redo history steps
@export_range(10, 100, 1) var max_undo_steps: int = 50:
	set(value):
		if max_undo_steps != value:
			max_undo_steps = value
			emit_changed()

## Automatically flip tile faces based on camera-facing direction
## When enabled:
##   - NORTH/FLOOR/WEST walls → Normal face (not flipped)
##   - SOUTH/CEILING/EAST walls → Flipped face (back visible)
@export var enable_auto_flip: bool = GlobalConstants.DEFAULT_ENABLE_AUTO_FLIP:
	set(value):
		if enable_auto_flip != value:
			enable_auto_flip = value
			emit_changed()

# ==============================================================================
# UTILITY METHODS
# ==============================================================================

## Creates a new plugin settings Resource with default values
static func create_default() -> TilePlacerPluginSettings:
	var settings: TilePlacerPluginSettings = TilePlacerPluginSettings.new()
	return settings

## Saves settings to EditorSettings
func save_to_editor_settings(editor_settings: Object) -> void:
	if not editor_settings:
		return

	var base_path: String = "addons/TileMapLayer3D/"

	# UI Preferences
	editor_settings.set_setting(base_path + "show_plane_grids", show_plane_grids)
	editor_settings.set_setting(base_path + "default_placement_mode", default_placement_mode)

	# New Node Defaults
	editor_settings.set_setting(base_path + "default_tile_size", default_tile_size)
	editor_settings.set_setting(base_path + "default_grid_size", default_grid_size)
	editor_settings.set_setting(base_path + "default_texture_filter", default_texture_filter)
	editor_settings.set_setting(base_path + "default_enable_collision", default_enable_collision)
	editor_settings.set_setting(base_path + "default_alpha_threshold", default_alpha_threshold)

	# Editor Behavior
	editor_settings.set_setting(base_path + "auto_save_after_placement", auto_save_after_placement)
	editor_settings.set_setting(base_path + "show_debug_info", show_debug_info)
	editor_settings.set_setting(base_path + "max_undo_steps", max_undo_steps)
	editor_settings.set_setting(base_path + "enable_auto_flip", enable_auto_flip)

## Loads settings from EditorSettings
func load_from_editor_settings(editor_settings: Object) -> void:
	if not editor_settings:
		return

	var base_path: String = "addons/TileMapLayer3D/"

	# UI Preferences
	if editor_settings.has_setting(base_path + "show_plane_grids"):
		show_plane_grids = editor_settings.get_setting(base_path + "show_plane_grids")
	if editor_settings.has_setting(base_path + "default_placement_mode"):
		default_placement_mode = editor_settings.get_setting(base_path + "default_placement_mode")

	# New Node Defaults
	if editor_settings.has_setting(base_path + "default_tile_size"):
		default_tile_size = editor_settings.get_setting(base_path + "default_tile_size")
	if editor_settings.has_setting(base_path + "default_grid_size"):
		default_grid_size = editor_settings.get_setting(base_path + "default_grid_size")
	if editor_settings.has_setting(base_path + "default_texture_filter"):
		default_texture_filter = editor_settings.get_setting(base_path + "default_texture_filter")
	if editor_settings.has_setting(base_path + "default_enable_collision"):
		default_enable_collision = editor_settings.get_setting(base_path + "default_enable_collision")
	if editor_settings.has_setting(base_path + "default_alpha_threshold"):
		default_alpha_threshold = editor_settings.get_setting(base_path + "default_alpha_threshold")

	# Editor Behavior
	if editor_settings.has_setting(base_path + "auto_save_after_placement"):
		auto_save_after_placement = editor_settings.get_setting(base_path + "auto_save_after_placement")
	if editor_settings.has_setting(base_path + "show_debug_info"):
		show_debug_info = editor_settings.get_setting(base_path + "show_debug_info")
	if editor_settings.has_setting(base_path + "max_undo_steps"):
		max_undo_steps = editor_settings.get_setting(base_path + "max_undo_steps")
	if editor_settings.has_setting(base_path + "enable_auto_flip"):
		enable_auto_flip = editor_settings.get_setting(base_path + "enable_auto_flip")

## Returns a Dictionary representation of all settings (useful for debugging)
func to_dict() -> Dictionary:
	return {
		"show_plane_grids": show_plane_grids,
		"default_placement_mode": default_placement_mode,
		"default_tile_size": default_tile_size,
		"default_grid_size": default_grid_size,
		"default_texture_filter": default_texture_filter,
		"default_enable_collision": default_enable_collision,
		"default_alpha_threshold": default_alpha_threshold,
		"auto_save_after_placement": auto_save_after_placement,
		"show_debug_info": show_debug_info,
		"max_undo_steps": max_undo_steps,
		"enable_auto_flip": enable_auto_flip
	}
