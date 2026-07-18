@tool
class_name TilePlacerPluginSettings
extends Resource

@export_group("UI Preferences")

@export var show_plane_grids: bool = true:
	set(value):
		if show_plane_grids != value:
			show_plane_grids = value
			emit_changed()

@export_enum("Plane", "Point", "Surface") var default_placement_mode: int = 0:
	set(value):
		if default_placement_mode != value:
			default_placement_mode = value
			emit_changed()

@export_group("New Node Defaults")

@export var default_tile_size: Vector2i = GlobalConstants.DEFAULT_TILE_SIZE:
	set(value):
		if default_tile_size != value:
			default_tile_size = value
			emit_changed()

@export_range(0.1, 10.0, 0.1) var default_grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE:
	set(value):
		if default_grid_size != value:
			default_grid_size = value
			emit_changed()

@export_enum("Nearest", "Nearest Mipmap", "Linear", "Linear Mipmap") var default_texture_filter: int = GlobalConstants.DEFAULT_TEXTURE_FILTER:
	set(value):
		if default_texture_filter != value:
			default_texture_filter = value
			emit_changed()

@export var default_enable_collision: bool = true:
	set(value):
		if default_enable_collision != value:
			default_enable_collision = value
			emit_changed()

@export_range(0.0, 1.0, 0.1) var default_alpha_threshold: float = GlobalConstants.DEFAULT_ALPHA_THRESHOLD:
	set(value):
		if default_alpha_threshold != value:
			default_alpha_threshold = value
			emit_changed()

@export_group("Editor Behavior")

@export var enable_auto_flip: bool = GlobalConstants.DEFAULT_ENABLE_AUTO_FLIP:
	set(value):
		if enable_auto_flip != value:
			enable_auto_flip = value
			emit_changed()

static func create_default() -> TilePlacerPluginSettings:
	var settings: TilePlacerPluginSettings = TilePlacerPluginSettings.new()
	return settings

func save_to_editor_settings(editor_settings: Object) -> void:
	if not editor_settings:
		return

	var base_path: String = "addons/TileMapLayer3D/"

	editor_settings.set_setting(base_path + "show_plane_grids", show_plane_grids)
	editor_settings.set_setting(base_path + "default_placement_mode", default_placement_mode)

	editor_settings.set_setting(base_path + "default_tile_size", default_tile_size)
	editor_settings.set_setting(base_path + "default_grid_size", default_grid_size)
	editor_settings.set_setting(base_path + "default_texture_filter", default_texture_filter)
	editor_settings.set_setting(base_path + "default_enable_collision", default_enable_collision)
	editor_settings.set_setting(base_path + "default_alpha_threshold", default_alpha_threshold)

	editor_settings.set_setting(base_path + "enable_auto_flip", enable_auto_flip)

func load_from_editor_settings(editor_settings: Object) -> void:
	if not editor_settings:
		return

	var base_path: String = "addons/TileMapLayer3D/"

	if editor_settings.has_setting(base_path + "show_plane_grids"):
		show_plane_grids = editor_settings.get_setting(base_path + "show_plane_grids")
	if editor_settings.has_setting(base_path + "default_placement_mode"):
		default_placement_mode = editor_settings.get_setting(base_path + "default_placement_mode")

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

	if editor_settings.has_setting(base_path + "enable_auto_flip"):
		enable_auto_flip = editor_settings.get_setting(base_path + "enable_auto_flip")
