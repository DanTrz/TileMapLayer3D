@tool
class_name TileMapLayer3DPlugin
extends EditorPlugin

const TileEditorUIClass = preload("uid://dy4cagfxufhpy")
const RegionBakerClass = preload("res://addons/TileMapLayer3D/core/mesh_baker/region_baker.gd")
const RegionBakeOptionsClass = preload("res://addons/TileMapLayer3D/core/mesh_baker/region_bake_options.gd")

var tileset_panel: TilesetPanel = null
var _bottom_panel_button: Button = null

var editor_ui: TileEditorUI = null
var placement_manager: TilePlacementManager = null
var current_tile_map3d: TileMapLayer3D = null
var tile_cursor: TileCursor3D = null
var tile_preview: TilePreview3D = null
var is_active: bool = false

var selection_manager: SelectionManager = null

var _autotile_engine: AutotileEngine = null
var _autotile_extension: AutotilePlacementExtension = null

# _sculpt_manager is the single source of truth for sculpt state; the gizmo reads from it.
var _sculpt_gizmo_plugin: TileMapLayerGizmoPlugin = null
var _sculpt_manager: SculptManager = null

var _smart_fill_manager: SmartFillManager = null

var _vertex_edit_manager: VertexEditManager = null


var plugin_settings: TilePlacerPluginSettings = null

signal auto_flip_requested(flip_state: bool)

signal tile_position_updated(world_pos: Vector3, grid_pos: Vector3, current_plane: int)

var _last_preview_update_time: float = 0.0

var _last_preview_screen_pos: Vector2 = Vector2.INF
var _last_preview_grid_pos: Vector3 = Vector3.INF

var _cached_local_mouse_pos: Vector2 = Vector2.ZERO

var _is_painting: bool = false
var _is_erasing: bool = false
var _last_painted_position: Vector3 = Vector3.INF
var _last_paint_update_time: float = 0.0

var area_fill_selector: AreaFillSelector3D = null
var _area_fill_operator: AreaFillOperator = null

var _tile_count_warning_shown: bool = false
var _last_tile_count: int = 0


func _enter_tree() -> void:
	print("TileMapLayer3D: Plugin enabled")

	_sculpt_manager = SculptManager.new()
	_sculpt_manager.sculpt_tiles_created.connect(_on_sculpt_tiles_created)
	_sculpt_manager.sculpt_erase_tiles_requested.connect(_on_sculpt_erase_tiles_requested)
	_smart_fill_manager = SmartFillManager.new()
	_vertex_edit_manager = VertexEditManager.new()
	_sculpt_gizmo_plugin = TileMapLayerGizmoPlugin.new()
	_sculpt_gizmo_plugin.vertex_edit_manager = _vertex_edit_manager

	add_node_3d_gizmo_plugin(_sculpt_gizmo_plugin)


	plugin_settings = TilePlacerPluginSettings.new()
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	plugin_settings.load_from_editor_settings(editor_settings)

	var panel_scene: PackedScene = load("uid://bvxqm8r7yjwqr")
	tileset_panel = panel_scene.instantiate() as TilesetPanel

	_bottom_panel_button = add_control_to_bottom_panel(tileset_panel, "TileMapLayer3D")

	tileset_panel.tile_selected.connect(_on_tile_selected)
	tileset_panel.multi_tile_selected.connect(_on_multi_tile_selected)
	tileset_panel.tileset_loaded.connect(_on_tileset_loaded)
	tileset_panel.orientation_changed.connect(_on_orientation_changed)
	tileset_panel.placement_mode_changed.connect(_on_placement_mode_changed)
	tileset_panel.show_plane_grids_changed.connect(_on_show_plane_grids_changed)
	tileset_panel.cursor_step_size_changed.connect(_on_cursor_step_size_changed)
	auto_flip_requested.connect(_on_auto_flip_requested)
	tileset_panel.grid_snap_size_changed.connect(_on_grid_snap_size_changed)
	tileset_panel.box_z_fighting_changed.connect(_on_box_z_fighting_changed)
	tileset_panel.grid_size_changed.connect(_on_grid_size_changed)
	tileset_panel.texture_filter_changed.connect(_on_texture_filter_changed)
	tileset_panel.pixel_inset_changed.connect(_on_pixel_inset_changed)
	tileset_panel.create_collision_requested.connect(_on_create_collision_requested)
	tileset_panel.clear_collisions_requested.connect(_on_clear_collisions_requested)
	tileset_panel._bake_mesh_requested.connect(_on_bake_mesh_requested)
	tileset_panel.clear_tiles_requested.connect(_clear_all_tiles)
	tileset_panel.show_debug_info_requested.connect(_on_show_debug_info_requested)

	tileset_panel.autotile_tileset_changed.connect(_on_autotile_tileset_changed)
	tileset_panel.autotile_terrain_selected.connect(_on_autotile_terrain_selected)
	tileset_panel.autotile_data_changed.connect(_on_autotile_data_changed)
	tileset_panel.clear_tileset_requested.connect(_on_clear_tileset_requested)


	editor_ui = TileEditorUIClass.new()
	editor_ui.initialize(self)
	editor_ui.set_tileset_panel(tileset_panel)
	editor_ui.tiling_enabled_changed.connect(_on_tool_toggled)
	editor_ui.tilemap_main_mode_changed.connect(_on_tilemap_main_mode_changed)
	editor_ui.rotate_requested.connect(_on_editor_ui_rotate_requested)
	editor_ui.tilt_requested.connect(_on_editor_ui_tilt_requested)
	editor_ui.reset_requested.connect(_on_editor_ui_reset_requested)
	editor_ui.flip_requested.connect(_on_editor_ui_flip_requested)
	editor_ui.smart_select_operation_requested.connect(_on_editor_ui_smart_select_operation_requested)
	editor_ui._context_toolbar.mesh_mode_selection_changed.connect(_on_mesh_mode_selection_changed)
	editor_ui._context_toolbar.mesh_mode_depth_changed.connect(_on_mesh_mode_depth_changed)
	editor_ui._context_toolbar.arch_radius_ratio_changed.connect(_on_arch_radius_ratio_changed)
	editor_ui._context_toolbar.freeze_uv_changed.connect(_on_freeze_uv_changed)


	editor_ui._context_toolbar.smart_operations_mode_changed.connect(_on_smart_operations_mode_changed)
	editor_ui.smart_select_mode_changed.connect(_on_smart_select_mode_changed)
	editor_ui._context_toolbar.sculp_brush_changed.connect(_on_sculp_mode_brush_changed)
	editor_ui._context_toolbar.sculp_mode_options_changed.connect(_on_sculp_mode_options_changed)
	editor_ui._context_toolbar.smart_fill_changed.connect(_on_smart_fill_changed)
	editor_ui.vertex_convert_requested.connect(_on_vertex_convert_requested)
	editor_ui.vertex_delete_requested.connect(_on_vertex_delete_requested)

	editor_ui._context_toolbar.texture_repeat_mode_changed.connect(_on_texture_repeat_mode_changed)

	editor_ui._context_toolbar.depth_growth_mode_changed.connect(_on_depth_growth_mode_changed)



	tile_position_updated.connect(editor_ui._context_toolbar.update_tile_position)

	GlobalTileMapEvents.connect_request_sprite_mesh_creation(_on_request_sprite_mesh_creation)

	placement_manager = TilePlacementManager.new()
	_vertex_edit_manager.set_placement_manager(placement_manager)

	selection_manager = SelectionManager.new()
	selection_manager.selection_changed.connect(_on_selection_manager_changed)
	selection_manager.selection_cleared.connect(_on_selection_manager_cleared)

	tileset_panel.set_selection_manager(selection_manager)

	hide_bottom_panel_and_ui()


func _exit_tree() -> void:
	GlobalTileMapEvents.disconnect_request_sprite_mesh_creation(_on_request_sprite_mesh_creation)

	if plugin_settings:
		var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
		plugin_settings.save_to_editor_settings(editor_settings)

	if tileset_panel:
		remove_control_from_bottom_panel(tileset_panel)
		tileset_panel.queue_free()

	if editor_ui:
		editor_ui.cleanup()
		editor_ui = null

	if placement_manager:
		placement_manager = null

	if _sculpt_gizmo_plugin:
		remove_node_3d_gizmo_plugin(_sculpt_gizmo_plugin)
		_sculpt_gizmo_plugin = null
	if _sculpt_manager:
		_sculpt_manager.reset()
		_sculpt_manager = null
	if _smart_fill_manager:
		_smart_fill_manager.reset()
		_smart_fill_manager = null


	_autotile_engine = null
	_autotile_extension = null

	print("TileMapLayer3D: Plugin disabled")

func _handles(object: Object) -> bool:
	return object is TileMapLayer3D

func _edit(object: Object) -> void:
	_clear_selection()

	_is_painting = false
	_is_erasing = false
	if _area_fill_operator:
		_area_fill_operator.reset_state()
	_invalidate_preview()

	if current_tile_map3d:
		current_tile_map3d.clear_highlights()
		current_tile_map3d._active_placement_manager = null

	if current_tile_map3d and current_tile_map3d.settings:
		GlobalUtil.safe_disconnect(current_tile_map3d.settings.changed, _on_current_node_settings_changed)

	if object is TileMapLayer3D:
		current_tile_map3d = object as TileMapLayer3D
		if not current_tile_map3d.settings:
			current_tile_map3d.settings = TileMapLayerSettings.new()

			if plugin_settings:
				current_tile_map3d.settings.tile_size = plugin_settings.default_tile_size
				current_tile_map3d.settings.picker_tile_size = plugin_settings.default_tile_size
				current_tile_map3d.settings.grid_size = plugin_settings.default_grid_size
				current_tile_map3d.settings.texture_filter_mode = plugin_settings.default_texture_filter
				current_tile_map3d.settings.enable_collision = plugin_settings.default_enable_collision
				current_tile_map3d.settings.alpha_threshold = plugin_settings.default_alpha_threshold

		current_tile_map3d.current_mesh_mode = current_tile_map3d.settings.mesh_mode as GlobalConstants.MeshMode

		show_bottom_panel_and_ui()

		GlobalUtil.safe_connect(current_tile_map3d.settings.changed, _on_current_node_settings_changed)

		placement_manager.active_tile_map_layer3d = current_tile_map3d
		current_tile_map3d._active_placement_manager = placement_manager
		placement_manager.grid_size = current_tile_map3d.settings.grid_size

		var resolved_texture: Texture2D = TileAtlasResolver.get_active_texture(current_tile_map3d)
		if resolved_texture:
			placement_manager.tileset_texture = resolved_texture
			placement_manager.texture_filter_mode = current_tile_map3d.settings.texture_filter_mode

		placement_manager.current_mesh_rotation = current_tile_map3d.settings.current_mesh_rotation
		placement_manager.is_current_face_flipped = current_tile_map3d.settings.is_face_flipped

		var current_mode: GlobalConstants.MainAppMode = current_tile_map3d.settings.main_app_mode
		var correct_depth: float = current_tile_map3d.settings.current_depth_scale

		placement_manager.current_depth_scale = correct_depth
		placement_manager.current_texture_repeat_mode = current_tile_map3d.settings.texture_repeat_mode
		placement_manager.current_depth_growth_mode = current_tile_map3d.settings.depth_growth_mode if current_tile_map3d.settings.depth_growth_mode != null else GlobalConstants.DepthGrowthMode.OUTWARD
		placement_manager.current_freeze_uv = current_tile_map3d.settings.freeze_uv_on_rotation

		if tileset_panel:
			current_mode = current_tile_map3d.settings.main_app_mode
			tileset_panel.set_active_node(current_tile_map3d)
		if editor_ui:
			editor_ui.set_active_node(current_tile_map3d)
		if tile_preview:
			tile_preview.current_depth_scale = correct_depth
		if _sculpt_manager:
			_sculpt_manager.set_active_node(current_tile_map3d, placement_manager)
		if _smart_fill_manager:
			_smart_fill_manager.set_active_node(current_tile_map3d, placement_manager)
		if tile_preview:
			tile_preview.current_mesh_mode = current_tile_map3d.current_mesh_mode
			if current_tile_map3d.settings:
				tile_preview.current_arch_radius_ratio = current_tile_map3d.settings.arch_radius_ratio

		if _sculpt_gizmo_plugin:
			_sculpt_gizmo_plugin.set_active_node(current_tile_map3d, _smart_fill_manager, _sculpt_manager)
			_sculpt_gizmo_plugin._undo_redo = get_undo_redo()
		if _vertex_edit_manager:
			_vertex_edit_manager.set_tile_map(current_tile_map3d)
			_vertex_edit_manager.rebuild_all_vertex_meshes()


		placement_manager.sync_from_tile_model()
		call_deferred("_setup_cursor")
		call_deferred("_setup_autotile_extension")
	else:
		if current_tile_map3d:
			current_tile_map3d._active_placement_manager = null
		current_tile_map3d = null
		tileset_panel.set_active_node(null)
		if _sculpt_manager:
			_sculpt_manager.set_active_node(null, null)
			_sculpt_manager.reset()
		if _smart_fill_manager:
			_smart_fill_manager.set_active_node(null, null)
			_smart_fill_manager.reset()
		if _sculpt_gizmo_plugin:
			_sculpt_gizmo_plugin.set_active_node(null, null, null)
		if _vertex_edit_manager:
			_vertex_edit_manager.set_tile_map(null)

		_cleanup_cursor()
		hide_bottom_panel_and_ui()

func hide_bottom_panel_and_ui() -> void:
	if _bottom_panel_button:
		_bottom_panel_button.visible = false
	if editor_ui:
		editor_ui.set_ui_visible(false)

func show_bottom_panel_and_ui() -> void:
	if _bottom_panel_button:
		_bottom_panel_button.visible = true
	if tileset_panel:
		make_bottom_panel_item_visible(tileset_panel)
	if editor_ui:
		editor_ui.set_ui_visible(true)

func _setup_cursor() -> void:
	_cleanup_cursor()

	_remove_saved_cursors()

	tile_cursor = TileCursor3D.new()
	tile_cursor.grid_size = current_tile_map3d.grid_size
	tile_cursor.name = "TileCursor3D"

	if plugin_settings:
		tile_cursor.show_plane_grids = plugin_settings.show_plane_grids

	# Runtime-only: never set owner so the cursor isn't saved to the scene.
	current_tile_map3d.add_child(tile_cursor)

	tile_preview = TilePreview3D.new()
	tile_preview.grid_size = current_tile_map3d.grid_size
	tile_preview.texture_filter_mode = placement_manager.texture_filter_mode
	tile_preview.tile_model = current_tile_map3d
	tile_preview.current_mesh_mode = current_tile_map3d.current_mesh_mode
	tile_preview.name = "TilePreview3D"
	current_tile_map3d.add_child(tile_preview)
	tile_preview.hide_preview()

	area_fill_selector = AreaFillSelector3D.new()
	area_fill_selector.grid_size = current_tile_map3d.grid_size
	area_fill_selector.name = "AreaFillSelector3D"
	current_tile_map3d.add_child(area_fill_selector)

	_area_fill_operator = AreaFillOperator.new()
	_area_fill_operator.setup(area_fill_selector, placement_manager, current_tile_map3d)
	_area_fill_operator.highlight_requested.connect(_on_highlight_tiles_in_area)
	_area_fill_operator.clear_highlights_requested.connect(_on_area_fill_clear_highlights)
	_area_fill_operator.out_of_bounds_warning.connect(_on_area_fill_out_of_bounds)

	placement_manager.cursor_3d = tile_cursor

func _remove_saved_cursors() -> void:
	if not current_tile_map3d:
		return

	for child in current_tile_map3d.get_children():
		if child is TileCursor3D:
			child.queue_free()

func _setup_autotile_extension() -> void:
	if not current_tile_map3d or not placement_manager:
		return

	if not _autotile_extension:
		_autotile_extension = AutotilePlacementExtension.new()

	if current_tile_map3d.settings:
		var settings: TileMapLayerSettings = current_tile_map3d.settings
		var resolved_tileset: TileSet = current_tile_map3d.get_tileset()
		if resolved_tileset == null:
			resolved_tileset = settings.autotile_tileset

		var has_terrains: bool = resolved_tileset != null and resolved_tileset.get_terrain_sets_count() > 0
		if has_terrains:
			_autotile_engine = AutotileEngine.new(resolved_tileset)
			_autotile_extension.setup(_autotile_engine, placement_manager, current_tile_map3d)
			_autotile_extension.set_engine(_autotile_engine)

			var restored_terrain: int = settings.active_terrain
			if restored_terrain < 0:
				restored_terrain = settings.autotile_active_terrain
			if restored_terrain >= 0:
				_autotile_extension.set_terrain(restored_terrain)

			if tileset_panel and tileset_panel.auto_tile_tab:
				if restored_terrain >= 0:
					tileset_panel.auto_tile_tab.select_terrain(restored_terrain)

			# Without this, loaded autotiles won't recognize new neighbors after scene reload.
			_autotile_engine.rebuild_bitmask_cache(current_tile_map3d)
		else:
			_autotile_extension.setup(null, placement_manager, current_tile_map3d)

	_autotile_extension.set_enabled(_is_autotile_mode())


func _cleanup_cursor() -> void:
	if tile_cursor:
		if is_instance_valid(tile_cursor):
			tile_cursor.queue_free()
		tile_cursor = null
		placement_manager.cursor_3d = null

	if tile_preview:
		if is_instance_valid(tile_preview):
			tile_preview.queue_free()
		tile_preview = null

	if area_fill_selector:
		if is_instance_valid(area_fill_selector):
			area_fill_selector.queue_free()
		area_fill_selector = null

	if _area_fill_operator:
		_area_fill_operator = null

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_active or not current_tile_map3d:
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouse:
		_cached_local_mouse_pos = event.position

	if event is InputEventKey and event.pressed:
		var result = _handle_mesh_rotations(event, camera)

		if result == AFTER_GUI_INPUT_STOP:
			return result

		# PASS falls through so WASD cursor movement can still handle the key.
		var cursor_based_mode: bool = (placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR_PLANE or placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR)
		if cursor_based_mode and tile_cursor:
			return _handle_cursor3d_movement(event, camera)

	if event is InputEventMouseMotion:
		_handle_mouse_painting_movement(event, camera)

	if event is InputEventMouseButton:
		return _handle_mouse_button_press(event, camera)

	return AFTER_GUI_INPUT_PASS

func _handle_mesh_rotations(event: InputEventKey, camera: Camera3D) -> int:
	if is_active:
		var needs_update: bool = false

		if event.physical_keycode == KEY_ESCAPE:
			if _area_fill_operator and _area_fill_operator.is_selecting:
				_area_fill_operator.cancel()
				return AFTER_GUI_INPUT_STOP
			return AFTER_GUI_INPUT_PASS

		if _is_autotile_mode():
			return AFTER_GUI_INPUT_PASS

		if _is_animated_tile_mode():
			return AFTER_GUI_INPUT_PASS

		if _is_vertex_edit_mode():
			if event.keycode == KEY_DELETE and _vertex_edit_manager:
				_on_vertex_delete_requested()
				return AFTER_GUI_INPUT_STOP
			return AFTER_GUI_INPUT_PASS

		match event.physical_keycode:
			KEY_Q:
				placement_manager.current_mesh_rotation = (placement_manager.current_mesh_rotation - 1) % GlobalConstants.MAX_SPIN_ROTATION_STEPS
				if placement_manager.current_mesh_rotation < 0:
					placement_manager.current_mesh_rotation += GlobalConstants.MAX_SPIN_ROTATION_STEPS
				needs_update = true

			KEY_E:
				placement_manager.current_mesh_rotation = (placement_manager.current_mesh_rotation + 1) % GlobalConstants.MAX_SPIN_ROTATION_STEPS
				needs_update = true

			KEY_F:
				placement_manager.is_current_face_flipped = not placement_manager.is_current_face_flipped
				needs_update = true

			KEY_R:
				if event.shift_pressed:
					GlobalPlaneDetector.cycle_tilt_backward()
				else:
					GlobalPlaneDetector.cycle_tilt_forward()
				needs_update = true

				var should_be_flipped: bool = GlobalPlaneDetector.determine_rotation_flip_for_plane(GlobalPlaneDetector.current_plane_6d)

				placement_manager.is_current_face_flipped = should_be_flipped


			KEY_T:
				GlobalPlaneDetector.reset_to_flat()
				placement_manager.current_mesh_rotation = 0
				needs_update = true
				var default_flip: bool = GlobalPlaneDetector.determine_auto_flip_for_plane(GlobalPlaneDetector.current_plane_6d)
				placement_manager.is_current_face_flipped = default_flip

		if needs_update:
			if current_tile_map3d and current_tile_map3d.settings:

				current_tile_map3d.settings.current_mesh_rotation = placement_manager.current_mesh_rotation

				current_tile_map3d.settings.is_face_flipped = placement_manager.is_current_face_flipped

			if tile_preview:
				_update_preview(camera, _cached_local_mouse_pos, true)

			_update_side_toolbar_status()

			update_overlays()

			return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS

func _handle_cursor3d_movement(event: InputEventKey, camera: Camera3D) -> int:
	# Don't process WASD if a UI control has focus.
	var focused_control: Control = get_editor_interface().get_base_control().get_viewport().gui_get_focus_owner()
	if focused_control and (focused_control is LineEdit or focused_control is SpinBox or focused_control is TextEdit):
		return AFTER_GUI_INPUT_PASS

	var shift_pressed: bool = event.shift_pressed
	var handled: bool = false
	var move_vector: Vector3 = Vector3.ZERO
	var basis: Basis = camera.global_transform.basis

	match event.physical_keycode:
		KEY_W:
			if shift_pressed:
				move_vector = GlobalUtil._get_snapped_cardinal_vector(basis.y)
			else:
				move_vector = GlobalUtil._get_snapped_cardinal_vector(-basis.z)
			handled = true
		KEY_S:
			if shift_pressed:
				move_vector = GlobalUtil._get_snapped_cardinal_vector(-basis.y)
			else:
				move_vector = GlobalUtil._get_snapped_cardinal_vector(basis.z)
			handled = true
		KEY_A:
			move_vector = GlobalUtil._get_snapped_cardinal_vector(-basis.x)
			handled = true
		KEY_D:
			move_vector = GlobalUtil._get_snapped_cardinal_vector(basis.x)
			handled = true

	if handled:
		if move_vector.length_squared() > 0.0:
			tile_cursor.move_by(Vector3i(move_vector))
		return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS

func _handle_mouse_painting_movement(event: InputEvent, camera: Camera3D) -> void:
	if _is_vertex_edit_mode():
		if _vertex_edit_manager and _vertex_edit_manager.is_dragging():
			_vertex_edit_manager.drag_to(camera, event.position)
			current_tile_map3d.update_gizmos()
		return

	var current_time: float = Time.get_ticks_msec() / 1000.0
	var is_area_selecting: bool = _area_fill_operator and _area_fill_operator.is_selecting

	if is_area_selecting:
		_area_fill_operator.update(camera, event.position)

	if not is_area_selecting:
		var quick_result: Dictionary = placement_manager.calculate_cursor_plane_placement(camera, event.position)

		if not quick_result.is_empty():
			var grid_pos: Vector3 = quick_result.grid_pos

			if _should_update_preview(event.position, grid_pos):
				if current_time - _last_preview_update_time >= GlobalConstants.PREVIEW_UPDATE_INTERVAL:
					_update_preview(camera, event.position, false)
					_last_preview_update_time = current_time
					_last_preview_screen_pos = event.position
					_last_preview_grid_pos = grid_pos

	# Full raycast — smart-fill tiles can be at any height (slopes, ramps).
	if is_smart_fill_mode() and _smart_fill_manager and _smart_fill_manager.state == SmartFillManager.SmartFillState.START_SET:
		if current_time - _last_paint_update_time >= GlobalConstants.PAINT_UPDATE_INTERVAL:
			var sf_result: PlacedTileInfo = SmartSelectManager.pick_tile_at(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position), current_tile_map3d)

			if sf_result != null:
				var sf_tile_info: PlacedTileInfo = sf_result
				var sf_grid_pos: Vector3 = sf_tile_info.grid_position
				var sf_world_pos: Vector3 = GlobalUtil.grid_to_world(sf_grid_pos, current_tile_map3d.settings.grid_size)
				_smart_fill_manager.update_preview(sf_world_pos)
			else:
				_smart_fill_manager.clear_preview()
			current_tile_map3d.update_gizmos()
			_last_paint_update_time = current_time
		return

	if _is_sculpting_mode() and _sculpt_manager and _sculpt_gizmo_plugin and current_time - _last_paint_update_time >= GlobalConstants.PAINT_UPDATE_INTERVAL:
		var quick_result: Dictionary = placement_manager.calculate_cursor_plane_placement(camera, event.position)

		if not quick_result.is_empty():
			_sculpt_manager.update_brush_position(quick_result.grid_pos, current_tile_map3d.settings.grid_size, quick_result.orientation, current_tile_map3d.settings.grid_snap_size)
			_sculpt_manager.on_mouse_move(event.position.y)
			if tile_cursor:
				tile_cursor.set_active_plane(quick_result.active_plane)
			current_tile_map3d.update_gizmos()

		_last_paint_update_time = current_time
		return


	if (_is_painting or _is_erasing) and current_time - _last_paint_update_time >= GlobalConstants.PAINT_UPDATE_INTERVAL:
		_paint_tile_at_mouse(camera, event.position, _is_erasing)
		_last_paint_update_time = current_time

func _handle_mouse_button_press(event: InputEvent, camera: Camera3D) -> int:
	var saved_transform: Transform3D = camera.global_transform

	var is_area_selecting: bool = _area_fill_operator and _area_fill_operator.is_selecting
	var is_left: bool = event.button_index == MOUSE_BUTTON_LEFT
	var is_right: bool = event.button_index == MOUSE_BUTTON_RIGHT
	var is_wheel_up: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
	var is_wheel_down: bool = event.button_index == MOUSE_BUTTON_WHEEL_DOWN

	if not (is_left or is_right or is_wheel_up or is_wheel_down):
		return AFTER_GUI_INPUT_PASS


	if event.pressed and is_smart_operations_mode():
		if is_smart_fill_mode():
			if is_right:
				if _smart_fill_manager:
					_smart_fill_manager.reset()
					current_tile_map3d.clear_highlights()
					current_tile_map3d.update_gizmos()
					return AFTER_GUI_INPUT_STOP

			if is_left:
				if current_tile_map3d.settings.smart_fill_mode == GlobalConstants.SmartFillMode.FILL_RAMP:
					if _smart_fill_manager:
						var result: PlacedTileInfo = SmartSelectManager.pick_tile_at(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position), current_tile_map3d)

						match _smart_fill_manager.state:
							SmartFillManager.SmartFillState.IDLE:
								if result != null:
									_smart_fill_manager.set_start(result, result.tile_key, current_tile_map3d.settings.grid_size)
									current_tile_map3d.highlight_tiles([result.tile_key])
									current_tile_map3d.update_gizmos()

							SmartFillManager.SmartFillState.START_SET:
								if result != null and result.tile_key != _smart_fill_manager.start_tile_key:
									_smart_fill_manager.set_end(result, result.tile_key, current_tile_map3d.settings.grid_size)

									_smart_fill_manager._execute_smart_fill_ramp( self)
									_smart_fill_manager.reset()
									current_tile_map3d.clear_highlights()
									current_tile_map3d.update_gizmos()
					return AFTER_GUI_INPUT_STOP

		if is_smart_select_mode():
			if is_right:
				current_tile_map3d.clear_highlights()
				current_tile_map3d.smart_selected_tiles.clear()
				return AFTER_GUI_INPUT_STOP

			if not is_left:
				return AFTER_GUI_INPUT_PASS

			var result: PlacedTileInfo = SmartSelectManager.pick_tile_at(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position), current_tile_map3d)

			if result == null:
				current_tile_map3d.clear_highlights()
				current_tile_map3d.smart_selected_tiles.clear()
				return AFTER_GUI_INPUT_STOP

			match current_tile_map3d.settings.smart_select_mode:
				GlobalConstants.SmartSelectionMode.SINGLE_PICK:
					var tile_key: int = result.tile_key
					if current_tile_map3d.smart_selected_tiles.has(tile_key):
						current_tile_map3d.smart_selected_tiles.erase(tile_key)
					else:
						current_tile_map3d.smart_selected_tiles.append(tile_key)
					var dbg_idx: int = current_tile_map3d.get_tile_index(tile_key)
					if dbg_idx >= 0:
						var dbg_tile_info: PlacedTileInfo = current_tile_map3d.get_tile_info_at_index(dbg_idx)
						var dbg_grid_pos: Vector3 = dbg_tile_info.grid_position
						var dbg_world_pos: Vector3 = GlobalUtil.grid_to_world(dbg_grid_pos, current_tile_map3d.settings.grid_size)
						print("SINGLE_PICK tile_key=%d | grid_pos=%s | world_pos=%s | orientation=%s  | mesh_mode=%s | mesh_depth=%s | texture_repeate=%s" % [tile_key, dbg_grid_pos, dbg_world_pos, dbg_tile_info.orientation, dbg_tile_info.mesh_mode, dbg_tile_info.depth_scale, dbg_tile_info.texture_repeat_mode ])

				GlobalConstants.SmartSelectionMode.CONNECTED_UV:
					current_tile_map3d.smart_selected_tiles = SmartSelectManager.pick_flood_fill(
						result.tile_key, current_tile_map3d, GlobalConstants.SmartSelectionMode.CONNECTED_UV)

				GlobalConstants.SmartSelectionMode.CONNECTED_NEIGHBOR:
					current_tile_map3d.smart_selected_tiles = SmartSelectManager.pick_flood_fill(
						result.tile_key, current_tile_map3d, GlobalConstants.SmartSelectionMode.CONNECTED_NEIGHBOR)

				GlobalConstants.SmartSelectionMode.CONNECTED_TILE_TYPE:
					current_tile_map3d.smart_selected_tiles = SmartSelectManager.pick_flood_fill(
						result.tile_key, current_tile_map3d, GlobalConstants.SmartSelectionMode.CONNECTED_TILE_TYPE)

				GlobalConstants.SmartSelectionMode.HORIZONTAL_LOOP:
					current_tile_map3d.smart_selected_tiles = SmartSelectManager.pick_horizontal_loop(
						result.tile_key, current_tile_map3d)
				_:
					pass

			current_tile_map3d.highlight_tiles(current_tile_map3d.smart_selected_tiles)
			return AFTER_GUI_INPUT_STOP

	if not (is_left or is_right):
		return AFTER_GUI_INPUT_PASS

	if _is_vertex_edit_mode() and _vertex_edit_manager:
		if is_right:
			current_tile_map3d.clear_highlights()
			current_tile_map3d.smart_selected_tiles.clear()
			_vertex_edit_manager.deselect()
			current_tile_map3d.update_gizmos()
			return AFTER_GUI_INPUT_STOP

		if is_left:
			if event.pressed:
				if _vertex_edit_manager.selected_tile_key != -1 and _vertex_edit_manager.begin_drag(camera, event.position):
					return AFTER_GUI_INPUT_STOP
				_handle_vertex_edit_click(camera, event.position)
				return AFTER_GUI_INPUT_STOP
			else:
				if _vertex_edit_manager.is_dragging():
					var drag_result: Dictionary = _vertex_edit_manager.end_drag()
					if not drag_result.is_empty() and drag_result["old_pos"] != drag_result["new_pos"]:
						var undo_redo: EditorUndoRedoManager = get_undo_redo()
						undo_redo.create_action("Move Vertex Corner", 0, current_tile_map3d)
						undo_redo.add_do_method(_vertex_edit_manager, "update_corner", drag_result["tile_key"], drag_result["handle"], drag_result["new_pos"])
						undo_redo.add_undo_method(_vertex_edit_manager, "update_corner", drag_result["tile_key"], drag_result["handle"], drag_result["old_pos"])
						undo_redo.add_do_method(current_tile_map3d, "update_gizmos")
						undo_redo.add_undo_method(current_tile_map3d, "update_gizmos")
						undo_redo.commit_action(false)
				return AFTER_GUI_INPUT_STOP

	# Consume LMB in sculpt mode, else the editor's selection system deselects our node.
	if _is_sculpting_mode() and _sculpt_manager:
		if is_right and event.pressed:
			_sculpt_manager.reset()
			current_tile_map3d.update_gizmos()
			return AFTER_GUI_INPUT_STOP
		if is_left:
			if event.pressed:
				_sculpt_manager.on_mouse_press(event.position.y)
			else:
				_sculpt_manager.on_mouse_release()
				current_tile_map3d.update_gizmos()
			return AFTER_GUI_INPUT_STOP

	var is_erase: bool = is_right
	if event.pressed and not _is_sculpting_mode():
		if event.shift_pressed and _area_fill_operator and not _is_animated_tile_mode():
			_area_fill_operator.start(camera, event.position, is_erase)
			return AFTER_GUI_INPUT_STOP

		_start_stroke(is_erase)
		placement_manager.start_paint_stroke(get_undo_redo(), _get_stroke_action_name(is_erase))
		_paint_tile_at_mouse(camera, event.position, is_erase)
		return AFTER_GUI_INPUT_STOP
	else:
		if is_area_selecting:
			_complete_area_fill()
			return AFTER_GUI_INPUT_STOP

		if _is_painting or _is_erasing:
			_end_stroke()
			return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS

func _start_stroke(is_erase: bool) -> void:
	_is_painting = not is_erase
	_is_erasing = is_erase
	_last_painted_position = Vector3.INF
	_last_paint_update_time = 0.0

func _end_stroke() -> void:
	placement_manager.end_paint_stroke()
	_is_painting = false
	_is_erasing = false
	_mark_scene_dirty()

func _get_stroke_action_name(is_erase: bool) -> String:
	if is_erase:
		return "Erase Tiles"
	elif _has_multi_tile_selection():
		return "Paint Multi-Tiles"
	else:
		return "Paint Tiles"

func _should_update_preview(screen_pos: Vector2, grid_pos: Vector3 = Vector3.INF) -> bool:
	if _last_preview_screen_pos != Vector2.INF:
		var screen_delta: float = screen_pos.distance_to(_last_preview_screen_pos)
		if screen_delta < GlobalConstants.PREVIEW_MIN_MOVEMENT:
			return false

	if grid_pos != Vector3.INF and _last_preview_grid_pos != Vector3.INF:
		var grid_delta: float = grid_pos.distance_to(_last_preview_grid_pos)

		# Threshold scales with snap size so 0.5 snap isn't blocked by a fixed 1.0 threshold.
		var snap_size: float = placement_manager.grid_snap_size if placement_manager else 1.0
		var grid_threshold: float = snap_size * GlobalConstants.PREVIEW_GRID_MOVEMENT_MULTIPLIER

		if grid_delta < grid_threshold:
			return false

	return true

func _update_preview(camera: Camera3D, screen_pos: Vector2, force_update: bool = false) -> void:
	if not tile_preview or not tile_cursor or not placement_manager.tileset_texture:
		return

	if current_tile_map3d and is_smart_select_mode():
		tile_preview.hide_preview()
		return

	if not force_update:
		if not _should_update_preview(screen_pos):
			return

	_last_preview_screen_pos = screen_pos

	GlobalPlaneDetector.update_from_camera(camera, self)

	var has_multi_selection: bool = _has_multi_tile_selection()
	var has_autotile_ready: bool = _is_autotile_mode() and _autotile_extension and _autotile_extension.is_ready()

	if not has_multi_selection and not placement_manager.current_tile_uv.has_area() and not has_autotile_ready:
		tile_preview.hide_preview()
		if current_tile_map3d:
			current_tile_map3d.clear_highlights()
		return

	var preview_grid_pos: Vector3
	var preview_orientation: int = GlobalPlaneDetector.current_tile_orientation_18d

	if placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR_PLANE:
		var result: Dictionary = placement_manager.calculate_cursor_plane_placement(camera, screen_pos)
		if result.is_empty():
			tile_preview.hide_preview()
			if current_tile_map3d:
				current_tile_map3d.clear_highlights()
			return
		preview_grid_pos = result.grid_pos
		preview_orientation = result.orientation

		if tile_cursor:
			tile_cursor.set_active_plane(result.active_plane)

	elif placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR:
		var raw_pos = tile_cursor.grid_position
		preview_grid_pos = placement_manager.snap_to_grid(raw_pos)

	else:
		var ray_result: Dictionary = placement_manager._raycast_to_geometry(camera, screen_pos)
		if ray_result.is_empty():
			tile_preview.hide_preview()
			if current_tile_map3d:
				current_tile_map3d.clear_highlights()
			return
		var grid_coords: Vector3 = GlobalUtil.world_to_grid(ray_result.position, placement_manager.grid_size)
		preview_grid_pos = placement_manager.snap_to_grid(grid_coords)

	var world_pos: Vector3 = _grid_to_absolute_world(preview_grid_pos)
	tile_position_updated.emit(world_pos, preview_grid_pos, GlobalPlaneDetector.current_plane_6d)

	if not TileKeySystem.is_position_valid(preview_grid_pos):
		if current_tile_map3d:
			current_tile_map3d.show_blocked_highlight(preview_grid_pos, preview_orientation)
		tile_preview.hide_preview()
		return

	if current_tile_map3d:
		current_tile_map3d.clear_blocked_highlight()
	if has_multi_selection:
		tile_preview.update_multi_preview(
			preview_grid_pos,
			_get_selected_tiles(),
			preview_orientation,
			placement_manager.current_mesh_rotation,
			placement_manager.tileset_texture,
			placement_manager.is_current_face_flipped,
			true
		)
	elif has_autotile_ready:
		var terrain_color: Color = _autotile_engine.get_terrain_color(_autotile_extension.current_terrain_id)
		terrain_color.a = 0.7
		tile_preview.update_color_preview(
			preview_grid_pos,
			preview_orientation,
			terrain_color,
			placement_manager.current_mesh_rotation,
			placement_manager.is_current_face_flipped,
			true
		)
	else:
		tile_preview.update_preview(
			preview_grid_pos,
			preview_orientation,
			placement_manager.current_tile_uv,
			placement_manager.tileset_texture,
			placement_manager.current_mesh_rotation,
			placement_manager.is_current_face_flipped,
			true,
			current_tile_map3d.enable_decal_mode
		)

	_highlight_tiles_at_preview_position(preview_grid_pos, preview_orientation, has_multi_selection)




func _paint_tile_at_mouse(camera: Camera3D, screen_pos: Vector2, is_erase: bool) -> void:
	if not placement_manager:
		return

	var grid_pos: Vector3
	var orientation: int = GlobalPlaneDetector.current_tile_orientation_18d

	if placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR_PLANE:
		var result: Dictionary = placement_manager.calculate_cursor_plane_placement(camera, screen_pos)
		if result.is_empty():
			return
		grid_pos = result.grid_pos
		orientation = result.orientation

	elif placement_manager.placement_mode == TilePlacementManager.PlacementMode.CURSOR:
		var raw_pos: Vector3 = tile_cursor.grid_position if tile_cursor else Vector3.ZERO
		grid_pos = placement_manager.snap_to_grid(raw_pos)

	else:
		var ray_result: Dictionary = placement_manager._raycast_to_geometry(camera, screen_pos)
		if ray_result.is_empty():
			return
		var grid_coords: Vector3 = GlobalUtil.world_to_grid(ray_result.position, placement_manager.grid_size)
		grid_pos = placement_manager.snap_to_grid(grid_coords)

	if not TileKeySystem.is_position_valid(grid_pos):
		if current_tile_map3d:
			current_tile_map3d.show_blocked_highlight(grid_pos, orientation)
		push_warning("TileMapLayer3D: Cannot place tile at position %s - outside valid range (±%.1f)" % [grid_pos, GlobalConstants.MAX_GRID_RANGE])
		return

	if current_tile_map3d:
		current_tile_map3d.clear_blocked_highlight()

	# Distance check (not equality) to absorb floating-point jitter between drags.
	if _last_painted_position.distance_to(grid_pos) < GlobalConstants.MIN_PAINT_GRID_DISTANCE:
		return

	if is_erase:
		var terrain_id: int = GlobalConstants.AUTOTILE_NO_TERRAIN
		if _autotile_extension:
			var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
			if current_tile_map3d.has_tile(tile_key):
				terrain_id = current_tile_map3d.get_tile_terrain_id(tile_key)

		placement_manager.erase_tile_at(grid_pos, orientation)

		if _autotile_extension and terrain_id >= 0:
			_autotile_extension.on_tile_erased(grid_pos, orientation, terrain_id)
	else:
		if _is_animated_tile_mode():

			if not current_tile_map3d.settings.has_animated_tile_selected:
				push_warning("Animated Tile Mode active: No animated tile selected. Normal painting operations are blocked until an animated tile is selected.")
				return

			var anim_id: int = current_tile_map3d.settings.active_animated_tile
			if anim_id >= 0 and current_tile_map3d.settings.animate_tiles_list.has(anim_id):
				var anim: TileAnimData = current_tile_map3d.settings.animate_tiles_list[anim_id]
				if not anim.selection_uv_rects.is_empty():
					var atlas_size: Vector2 = placement_manager.tileset_texture.get_size()
					var info: Dictionary = GlobalUtil.compute_anim_frame_info(anim, atlas_size)
					if info.is_empty():
						return

					placement_manager.current_anim_step_x = info["anim_step_x"]
					placement_manager.current_anim_step_y = info["anim_step_y"]
					placement_manager.current_anim_total_frames = anim.frames
					placement_manager.current_anim_columns = anim.columns
					placement_manager.current_anim_speed_fps = anim.speed

					# Animated tiles are FLAT_SQUARE only.
					var orig_mesh_mode: GlobalConstants.MeshMode = current_tile_map3d.current_mesh_mode
					current_tile_map3d.current_mesh_mode = GlobalConstants.MeshMode.FLAT_SQUARE

					if placement_manager.multi_tile_selection.size() > 1:
						placement_manager.paint_multi_tiles_at(grid_pos, orientation)
					else:
						placement_manager.paint_tile_at(grid_pos, orientation)

					current_tile_map3d.current_mesh_mode = orig_mesh_mode
					placement_manager.current_anim_step_x = 0.0
					placement_manager.current_anim_step_y = 0.0
					placement_manager.current_anim_total_frames = 1
					placement_manager.current_anim_columns = 1
					placement_manager.current_anim_speed_fps = 0.0
			return
		elif _has_multi_tile_selection():
			placement_manager.paint_multi_tiles_at(grid_pos, orientation)
		elif _is_autotile_mode() and _autotile_extension and _autotile_extension.is_ready():
			var autotile_uv: Rect2 = _autotile_extension.get_autotile_uv(grid_pos, orientation)
			if autotile_uv.has_area():
				var original_uv: Rect2 = placement_manager.current_tile_uv
				var original_src: int = placement_manager.current_atlas_source_id
				var original_coords: Vector2i = placement_manager.current_atlas_coords
				var original_terrain_id: int = placement_manager.current_terrain_id
				placement_manager.current_tile_uv = autotile_uv
				var autotile_binding: Array = _resolve_autotile_binding(autotile_uv)
				placement_manager.current_atlas_source_id = autotile_binding[0]
				placement_manager.current_atlas_coords = autotile_binding[1]
				placement_manager.current_terrain_id = _autotile_extension.current_terrain_id

				var original_mesh_mode: GlobalConstants.MeshMode = current_tile_map3d.current_mesh_mode
				var original_depth_scale: float = placement_manager.current_depth_scale
				if current_tile_map3d.settings:
					current_tile_map3d.current_mesh_mode = current_tile_map3d.settings.mesh_mode
					placement_manager.current_depth_scale = current_tile_map3d.settings.current_depth_scale

				var old_autotile_updates: Array[Dictionary] = _collect_replaced_autotile_updates(grid_pos, orientation)
				var placed: bool = placement_manager.paint_tile_at(grid_pos, orientation)

				current_tile_map3d.current_mesh_mode = original_mesh_mode
				placement_manager.current_depth_scale = original_depth_scale
				placement_manager.current_tile_uv = original_uv
				placement_manager.current_atlas_source_id = original_src
				placement_manager.current_atlas_coords = original_coords
				placement_manager.current_terrain_id = original_terrain_id

				if placed:
					for update_info: Dictionary in old_autotile_updates:
						_autotile_extension.on_tile_erased(
							update_info["grid_pos"],
							update_info["orientation"],
							update_info["terrain_id"]
						)
					_autotile_extension.on_tile_placed(grid_pos, orientation)
		else:
			placement_manager.paint_tile_at(grid_pos, orientation)

	_last_painted_position = grid_pos

	_check_tile_count_warning()

# Only updates configuration warnings on threshold crossings to avoid an O(n) scan per op.
func _check_tile_count_warning() -> void:
	if not current_tile_map3d or not placement_manager:
		return

	var total_tiles: int = current_tile_map3d.get_tile_count()
	var threshold: int = int(GlobalConstants.MAX_RECOMMENDED_TILES * GlobalConstants.TILE_COUNT_WARNING_THRESHOLD)
	var limit: int = GlobalConstants.MAX_RECOMMENDED_TILES

	var was_over_limit: bool = _last_tile_count > limit
	var is_over_limit: bool = total_tiles > limit
	var was_over_threshold: bool = _last_tile_count >= threshold
	var is_over_threshold: bool = total_tiles >= threshold

	if was_over_limit != is_over_limit or was_over_threshold != is_over_threshold:
		current_tile_map3d.update_configuration_warnings()

	_last_tile_count = total_tiles

	if total_tiles < threshold:
		_tile_count_warning_shown = false
		return

	if not _tile_count_warning_shown:
		push_warning("TileMapLayer3D: Tile count (%d) is at %.0f%% of recommended maximum (%d). Consider splitting into multiple TileMapLayer3D nodes for better performance." % [
			total_tiles,
			GlobalConstants.TILE_COUNT_WARNING_THRESHOLD * 100,
			GlobalConstants.MAX_RECOMMENDED_TILES
		])
		_tile_count_warning_shown = true


func _on_tool_toggled(pressed: bool) -> void:
	is_active = pressed

func _on_tile_selected(uv_rect: Rect2) -> void:
	if selection_manager:
		selection_manager.select([uv_rect], 0)

	if placement_manager:
		placement_manager.current_mesh_rotation = 0
		if current_tile_map3d and current_tile_map3d.settings:
			current_tile_map3d.settings.current_mesh_rotation = 0

	if tile_preview:
		tile_preview._hide_all_preview_instances()

func _on_multi_tile_selected(uv_rects: Array[Rect2], anchor_index: int) -> void:
	if _is_autotile_mode():
		return

	if selection_manager:
		selection_manager.select(uv_rects, anchor_index)

	if placement_manager:
		placement_manager.current_mesh_rotation = 0
		if current_tile_map3d and current_tile_map3d.settings:
			current_tile_map3d.settings.current_mesh_rotation = 0

func _on_tileset_loaded(texture: Texture2D) -> void:
	placement_manager.tileset_texture = texture
	if current_tile_map3d:
		current_tile_map3d.tileset_texture = texture
		current_tile_map3d.update_configuration_warnings()

func _on_orientation_changed(orientation: int) -> void:
	GlobalPlaneDetector.current_tile_orientation_18d = orientation

func _on_placement_mode_changed(mode: int) -> void:
	placement_manager.placement_mode = mode as TilePlacementManager.PlacementMode

	if tile_cursor:
		tile_cursor.visible = (mode == 0 or mode == 1)

func _on_auto_flip_requested(flip_state: bool) -> void:
	if not plugin_settings or not plugin_settings.enable_auto_flip:
		return

	if placement_manager:
		placement_manager.is_current_face_flipped = flip_state

		placement_manager.current_mesh_rotation = 0

		if current_tile_map3d and current_tile_map3d.settings:
			current_tile_map3d.settings.current_mesh_rotation = 0
			current_tile_map3d.settings.is_face_flipped = flip_state


func _on_selection_manager_changed(tiles: Array[Rect2], anchor: int) -> void:
	var settings: TileMapLayerSettings = current_tile_map3d.settings if current_tile_map3d else null
	var bindings: Array = _resolve_selection_bindings(tiles, current_tile_map3d)
	var source_ids: Array[int] = bindings[0]
	var coords_list: Array[Vector2i] = bindings[1]

	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.selected_tiles = tiles.duplicate()
		current_tile_map3d.settings.selected_atlas_coords = coords_list.duplicate()
		current_tile_map3d.settings.selected_anchor_index = anchor

	if placement_manager:
		if tiles.size() == 1:
			placement_manager.current_tile_uv = tiles[0]
			placement_manager.current_atlas_source_id = source_ids[0]
			placement_manager.current_atlas_coords = coords_list[0]
			placement_manager.multi_tile_selection.clear()
			placement_manager.multi_tile_atlas_source_ids.clear()
			placement_manager.multi_tile_atlas_coords.clear()
			placement_manager.multi_tile_anchor_index = 0
		else:
			placement_manager.multi_tile_selection = tiles.duplicate()
			placement_manager.multi_tile_atlas_source_ids = source_ids.duplicate()
			placement_manager.multi_tile_atlas_coords = coords_list.duplicate()
			placement_manager.multi_tile_anchor_index = anchor


# Returns [source_id, coords] for an autotile rect; freeform sentinel if it doesn't map to a cell.
func _resolve_autotile_binding(autotile_uv: Rect2) -> Array:
	var settings: TileMapLayerSettings = current_tile_map3d.settings if current_tile_map3d else null
	if settings == null or not TileAtlasResolver.is_valid_tileset(current_tile_map3d):
		return [-1, Vector2i(-1, -1)]
	var ts_size: Vector2i = TileAtlasResolver.get_tile_size(current_tile_map3d)
	if ts_size.x <= 0 or ts_size.y <= 0:
		return [-1, Vector2i(-1, -1)]
	var src_id: int = settings.active_source_id
	var candidate: Vector2i = Vector2i(
		int(round(autotile_uv.position.x / float(ts_size.x))),
		int(round(autotile_uv.position.y / float(ts_size.y)))
	)
	if TileAtlasResolver.coords_match_registered_cell(current_tile_map3d, src_id, candidate, autotile_uv):
		return [src_id, candidate]
	return [-1, Vector2i(-1, -1)]


# Captures old autotile neighborhoods that normal placement may erase/replace.
func _collect_replaced_autotile_updates(grid_pos: Vector3, orientation: int) -> Array[Dictionary]:
	var updates: Array[Dictionary] = []
	if not current_tile_map3d or not placement_manager:
		return updates

	var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
	if current_tile_map3d.has_tile(tile_key):
		var terrain_id: int = current_tile_map3d.get_tile_terrain_id(tile_key)
		if terrain_id >= 0:
			updates.append({
				"grid_pos": grid_pos,
				"orientation": orientation,
				"terrain_id": terrain_id
			})
		return updates

	var conflicting_key: int = placement_manager._find_conflicting_tile_key(grid_pos, orientation)
	if conflicting_key == -1:
		return updates

	var old_info: PlacedTileInfo = current_tile_map3d.get_tile_info_from_key(conflicting_key)
	if old_info != null and old_info.terrain_id >= 0:
		updates.append({
			"grid_pos": old_info.grid_position,
			"orientation": old_info.orientation,
			"terrain_id": old_info.terrain_id
		})

	return updates


# Returns [Array[int] source_ids, Array[Vector2i] coords] parallel to `tiles`.
func _resolve_selection_bindings(tiles: Array[Rect2], tile_map: TileMapLayer3D) -> Array:
	var source_ids: Array[int] = []
	var coords_list: Array[Vector2i] = []
	var settings: TileMapLayerSettings = tile_map.settings if tile_map else null
	var src_id: int = settings.active_source_id if settings != null else -1
	var ts_size: Vector2i = TileAtlasResolver.get_tile_size(tile_map)
	var has_valid_atlas: bool = TileAtlasResolver.is_valid_tileset(tile_map) and ts_size.x > 0 and ts_size.y > 0
	for rect in tiles:
		var bound_src: int = -1
		var bound_coords: Vector2i = Vector2i(-1, -1)
		if has_valid_atlas:
			var col: int = int(round(rect.position.x / float(ts_size.x)))
			var row: int = int(round(rect.position.y / float(ts_size.y)))
			var candidate: Vector2i = Vector2i(col, row)
			if TileAtlasResolver.coords_match_registered_cell(tile_map, src_id, candidate, rect):
				bound_src = src_id
				bound_coords = candidate
		source_ids.append(bound_src)
		coords_list.append(bound_coords)
	return [source_ids, coords_list]


func _on_selection_manager_cleared() -> void:
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.selected_tiles.clear()
		current_tile_map3d.settings.selected_atlas_coords.clear()
		current_tile_map3d.settings.selected_anchor_index = 0

	if placement_manager:
		placement_manager.current_tile_uv = Rect2()
		placement_manager.current_atlas_source_id = -1
		placement_manager.current_atlas_coords = Vector2i(-1, -1)
		placement_manager.multi_tile_selection.clear()
		placement_manager.multi_tile_atlas_source_ids.clear()
		placement_manager.multi_tile_atlas_coords.clear()
		placement_manager.multi_tile_anchor_index = 0

	if tileset_panel:
		tileset_panel.tileset_display.clear_selection()

	if tile_preview:
		tile_preview.hide_preview()
		tile_preview._hide_all_preview_instances()

func _on_request_sprite_mesh_creation(current_texture: Texture2D, selected_tiles: Array[Rect2], tile_size: Vector2i, grid_size: float, filter_mode: int) -> void:
	if not current_tile_map3d or not tile_cursor:
		push_warning("No TileMapLayer3D selected")
		return

	SpriteMeshGenerator.generate_sprite_mesh_instance(
		current_tile_map3d,
		current_texture,
		selected_tiles,
		tile_size,
		grid_size,
		tile_cursor.global_position,
		filter_mode,
		get_undo_redo()
	)



func _on_create_collision_requested(bake_mode: GlobalConstants.BakeMode, backface_collision: bool, save_external_collision: bool) -> void:
	if not current_tile_map3d:
		push_warning("No TileMapLayer3D selected")
		return
	if not current_tile_map3d.get_parent():
		push_error("TileMapLayer3D has no parent node")
		return

	var regions: Array[TerrainRegionChunk] = TileMeshMerger.get_collision_regions(current_tile_map3d, true)
	if regions.is_empty():
		push_warning("[CollisionGen] No regions found — tile map has no tiles or was not loaded.")
		return

	# One upfront clear so per-region clears inside bake_collision are no-ops on this path.
	current_tile_map3d.clear_collision_shapes(Vector3i.MAX)

	var options: RegionBakeOptions = RegionBakeOptions.new()
	options.alpha_aware = bake_mode == GlobalConstants.BakeMode.ALPHA_AWARE
	options.backface_collision = backface_collision
	options.attach_owner = current_tile_map3d.get_tree().edited_scene_root

	var pending: Array = []
	for region_chunk: TerrainRegionChunk in regions:
		var shape: ConcavePolygonShape3D = await RegionBaker.bake_collision(current_tile_map3d, region_chunk, options)
		if shape != null:
			pending.append([shape, region_chunk.region_key])

	if save_external_collision and not pending.is_empty():
		_save_collision_shapes_parallel(pending)


func _save_collision_shapes_parallel(pending: Array) -> void:
	var scene_path: String = current_tile_map3d.get_tree().edited_scene_root.scene_file_path
	if scene_path.is_empty():
		return
	var scene_name: String = scene_path.get_file().get_basename()
	var folder: String = scene_path.get_base_dir().path_join(scene_name + GlobalConstants.SAVE_FOLDER_NAME)
	DirAccess.make_dir_absolute(folder)

	var save_tasks: Array = []
	for entry: Array in pending:
		var shape: ConcavePolygonShape3D = entry[0]
		var region_key: Vector3i = entry[1]
		var suffix: String = "" if region_key == Vector3i.MAX \
			else "_%d_%d_%d" % [region_key.x, region_key.y, region_key.z]
		var filename: String = "%s_%s_collision%s.res" % [scene_name, current_tile_map3d.name, suffix]
		var path: String = folder.path_join(filename)
		# Delete before saving: in-place overwrite makes Godot emit UID warnings.
		if FileAccess.file_exists(path):
			var del_dir: DirAccess = DirAccess.open(folder)
			if del_dir:
				del_dir.remove(filename)
		shape.resource_path = path
		save_tasks.append([shape, path])

	var tasks: Array = save_tasks
	var task_count: int = tasks.size()
	var save_one: Callable = func(i: int) -> void:
		var t: Array = tasks[i]
		if ResourceSaver.save(t[0], t[1]) != OK:
			push_warning("[CollisionGen] failed to save: %s" % t[1])
	var group_id: int = WorkerThreadPool.add_group_task(save_one, task_count, -1, true)
	WorkerThreadPool.wait_for_group_task_completion(group_id)


func _on_clear_collisions_requested() -> void:
	if not current_tile_map3d:
		push_warning("No TileMapLayer3D selected")
		return

	current_tile_map3d.clear_collision_shapes()
	_free_collision_bodies()
	_delete_all_collision_res_files()
	print("All collision shapes cleared from TileMapLayer3D: ", current_tile_map3d.name)


func _free_collision_bodies() -> void:
	for child in current_tile_map3d.get_children():
		if child is StaticCollisionBody3D:
			current_tile_map3d.remove_child(child)
			child.queue_free()
	current_tile_map3d._collision_body = null


func _delete_all_collision_res_files() -> void:
	var scene_path: String = current_tile_map3d.get_tree().edited_scene_root.scene_file_path
	if scene_path.is_empty():
		return
	var scene_name: String = scene_path.get_file().get_basename()
	var folder: String = scene_path.get_base_dir().path_join(scene_name + GlobalConstants.SAVE_FOLDER_NAME)
	var dir: DirAccess = DirAccess.open(folder)
	if not dir:
		return
	var prefix: String = scene_name + "_" + current_tile_map3d.name + "_collision"
	dir.list_dir_begin()
	var filename: String = dir.get_next()
	while filename != "":
		if filename.begins_with(prefix) and filename.ends_with(".res"):
			dir.remove(filename)
		filename = dir.get_next()
	dir.list_dir_end()


func _on_bake_mesh_requested(bake_mode: GlobalConstants.BakeMode) -> void:
	if not Engine.is_editor_hint(): return

	if not current_tile_map3d:
		push_error("No TileMapLayer3D selected for merge bake")
		return

	var parent: Node = current_tile_map3d.get_parent()
	if not parent:
		push_error("TileMapLayer3D has no parent node")
		return

	var options: RegionBakeOptions = RegionBakeOptions.new()
	options.alpha_aware = bake_mode == GlobalConstants.BakeMode.ALPHA_AWARE

	var mesh_instance: MeshInstance3D = await RegionBaker.bake_mesh(current_tile_map3d, null, options)
	if mesh_instance == null:
		push_error("Bake TileMapLayer3D failed")
		return

	mesh_instance.name = current_tile_map3d.name + "_Baked"
	mesh_instance.transform = current_tile_map3d.transform

	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	undo_redo.create_action("Bake TileMapLayer3D to Static Mesh")
	undo_redo.add_do_method(parent, "add_child", mesh_instance)
	undo_redo.add_do_method(mesh_instance, "set_owner", parent.get_tree().edited_scene_root)
	undo_redo.add_do_property(mesh_instance, "name", mesh_instance.name)
	undo_redo.add_undo_method(parent, "remove_child", mesh_instance)
	undo_redo.commit_action()


func _clear_all_tiles() -> void:
	if not current_tile_map3d:
		push_warning("No TileMapLayer3D selected")
		return

	var confirm_dialog: ConfirmationDialog = ConfirmationDialog.new()
	confirm_dialog.dialog_text = "Clear all tiles from '%s'?\n\nThis action cannot be undone." % current_tile_map3d.name
	confirm_dialog.title = "Clear All Tiles"
	confirm_dialog.confirmed.connect(_do_clear_all_tiles)

	EditorInterface.get_base_control().add_child(confirm_dialog)
	confirm_dialog.popup_centered()

	confirm_dialog.visibility_changed.connect(func():
		if not confirm_dialog.visible:
			confirm_dialog.queue_free()
	)

func _do_clear_all_tiles() -> void:
	if not current_tile_map3d:
		return

	if _vertex_edit_manager:
		_vertex_edit_manager.clear_all_vertex_tiles()

	if current_tile_map3d:
		current_tile_map3d.smart_selected_tiles.clear()
		current_tile_map3d.clear_highlights()

	var tile_count: int = current_tile_map3d.get_tile_count()
	current_tile_map3d.clear_all_tiles()

	current_tile_map3d.clear_runtime_chunks()

	current_tile_map3d.clear_collision_shapes()

	current_tile_map3d.notify_property_list_changed()

func _on_show_debug_info_requested() -> void:
	DebugInfoGenerator.print_report(current_tile_map3d, placement_manager)


func _on_show_plane_grids_changed(enabled: bool) -> void:
	if tile_cursor:
		tile_cursor.show_plane_grids = enabled

	if plugin_settings:
		plugin_settings.show_plane_grids = enabled

func _on_cursor_step_size_changed(step_size: float) -> void:
	if tile_cursor:
		tile_cursor.cursor_step_size = step_size

func _on_grid_snap_size_changed(snap_size: float) -> void:
	if placement_manager:
		placement_manager.grid_snap_size = snap_size

func _on_mesh_mode_selection_changed(mesh_mode: GlobalConstants.MeshMode) -> void:
	if current_tile_map3d:
		current_tile_map3d.current_mesh_mode = mesh_mode
		current_tile_map3d.settings.mesh_mode = mesh_mode

	if tile_preview and not _is_autotile_mode():
		tile_preview.current_mesh_mode = mesh_mode
		var camera = get_viewport().get_camera_3d()
		if camera:
			_update_preview(camera, get_viewport().get_mouse_position())

func _on_mesh_mode_depth_changed(depth: float) -> void:
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.current_depth_scale = depth

	if not _is_autotile_mode() and placement_manager:
		placement_manager.current_depth_scale = depth

	if not _is_autotile_mode() and tile_preview:
		tile_preview.current_depth_scale = depth
		var camera = get_viewport().get_camera_3d()
		if camera:
			_update_preview(camera, get_viewport().get_mouse_position())


func _on_arch_radius_ratio_changed(ratio: float) -> void:
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.arch_radius_ratio = ratio
		current_tile_map3d.rebuild_arch_chunk_meshes()

	if tile_preview:
		tile_preview.current_arch_radius_ratio = ratio
		var camera = get_viewport().get_camera_3d()
		if camera:
			_update_preview(camera, get_viewport().get_mouse_position())


func _on_texture_repeat_mode_changed(mode: int) -> void:
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.texture_repeat_mode = mode
	if placement_manager:
		placement_manager.current_texture_repeat_mode = mode

func _on_depth_growth_mode_changed(mode: int) -> void:
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.depth_growth_mode = mode
	if placement_manager:
		placement_manager.current_depth_growth_mode = mode


func _on_box_z_fighting_changed(enabled: bool) -> void:
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.auto_resolve_box_z_fighting = enabled
	if current_tile_map3d:
		current_tile_map3d._rebuild_chunks_from_saved_data()


func _on_freeze_uv_changed(enabled: bool) -> void:
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.freeze_uv_on_rotation = enabled
	if placement_manager:
		placement_manager.current_freeze_uv = enabled


func _on_sculp_mode_brush_changed(brush_type: GlobalConstants.SculptBrushType, brush_size: float) -> void:
	if current_tile_map3d and _sculpt_manager:
		current_tile_map3d.settings.sculpt_brush_type = brush_type
		current_tile_map3d.settings.sculpt_brush_size = brush_size
		_sculpt_manager.rebuild_brush_shape_template()
		print("Sculpt brush changed - Type: ", brush_type, " Size: ", brush_size)

func _on_sculp_mode_options_changed(draw_top: bool, draw_bottom: bool, flip_sides: bool, flip_top: bool, flip_bottom: bool) -> void:
	if current_tile_map3d:
		current_tile_map3d.settings.sculpt_draw_top = draw_top
		current_tile_map3d.settings.sculpt_draw_bottom = draw_bottom
		current_tile_map3d.settings.sculpt_flip_top = flip_top
		current_tile_map3d.settings.sculpt_flip_sides = flip_sides
		current_tile_map3d.settings.sculpt_flip_bottom = flip_bottom


func _on_smart_operations_mode_changed(mode: GlobalConstants.SmartOperationsMainMode) -> void:
	if current_tile_map3d:
		current_tile_map3d.settings.smart_operations_main_mode = mode
		current_tile_map3d.update_gizmos()

	match mode:
		GlobalConstants.SmartOperationsMainMode.SMART_FILL:
			if editor_ui:
				editor_ui.clear_smart_selection()
		GlobalConstants.SmartOperationsMainMode.SMART_SELECT:
			if _smart_fill_manager:
				_smart_fill_manager.reset()
			if current_tile_map3d:
				current_tile_map3d.clear_highlights()


func _on_smart_select_mode_changed(is_smart_select_on: bool, smart_mode: GlobalConstants.SmartSelectionMode) -> void:
	if not is_smart_select_on and current_tile_map3d:
		editor_ui.clear_smart_selection()

	if _smart_fill_manager:
		_smart_fill_manager.reset()

	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.is_smart_select_active = is_smart_select_on

		if smart_mode != current_tile_map3d.settings.smart_select_mode:
			editor_ui.clear_smart_selection()
			current_tile_map3d.settings.smart_select_mode = smart_mode

	if current_tile_map3d:
		current_tile_map3d.update_gizmos()


func _on_smart_fill_changed(fill_mode: int, width: float, fill_direction: int, flip_faces: bool, ramp_sides: bool) -> void:
	if current_tile_map3d:
		current_tile_map3d.settings.smart_fill_mode = fill_mode
		current_tile_map3d.settings.smart_fill_width = width
		current_tile_map3d.settings.smart_fill_quad_growth_dir = fill_direction
		current_tile_map3d.settings.smart_fill_flip_face = flip_faces
		current_tile_map3d.settings.smart_fill_ramp_sides = ramp_sides
		current_tile_map3d.update_gizmos()




# Tile recalc + chunk rebuild happen in TileMapLayer3D._apply_settings() via Settings.changed.
func _on_grid_size_changed(new_size: float) -> void:
	if placement_manager:
		placement_manager.grid_size = new_size

	if tile_cursor:
		tile_cursor.grid_size = new_size

	if tile_preview:
		tile_preview.grid_size = new_size

	if area_fill_selector:
		area_fill_selector.grid_size = new_size

	# Clear collision only if grid_size actually changed (not on re-selecting a node).
	if current_tile_map3d and not is_equal_approx(current_tile_map3d.grid_size, new_size):
		current_tile_map3d.clear_collision_shapes()

func _on_texture_filter_changed(filter_mode: int) -> void:
	if placement_manager:
		placement_manager.set_texture_filter(filter_mode)

	if tile_preview:
		tile_preview.texture_filter_mode = filter_mode
		tile_preview._update_preview_material()

func _on_pixel_inset_changed(value: float) -> void:
	if current_tile_map3d:
		current_tile_map3d.set_pixel_inset(value)


func _complete_area_fill() -> void:
	if not _area_fill_operator:
		return

	var result: int = _area_fill_operator.complete(
		get_undo_redo(),
		_do_area_fill,
		_do_area_erase
	)

	if result > 0:
		_check_tile_count_warning()
		_mark_scene_dirty()


func _do_area_fill(min_pos: Vector3, max_pos: Vector3, orientation: int) -> int:
	if not placement_manager:
		return -1

	if _is_animated_tile_mode():
		return -1

	if _is_autotile_mode() and _autotile_extension and _autotile_extension.is_ready():
		return _fill_area_autotile(min_pos, max_pos, orientation)
	else:
		return placement_manager.fill_area_with_undo_compressed(min_pos, max_pos, orientation, get_undo_redo())


func _do_area_erase(min_pos: Vector3, max_pos: Vector3, orientation: int, undo_redo: EditorUndoRedoManager) -> int:
	if not placement_manager:
		return -1
	return placement_manager.erase_area_with_undo(min_pos, max_pos, orientation, undo_redo)


func _on_area_fill_clear_highlights() -> void:
	if current_tile_map3d:
		current_tile_map3d.clear_highlights()


func _on_area_fill_out_of_bounds(position: Vector3, orientation: int) -> void:
	if current_tile_map3d:
		current_tile_map3d.show_blocked_highlight(position, orientation)


# Three-phase autotile fill: place with placeholder UV, recalc UVs, update external neighbors.
func _fill_area_autotile(min_pos: Vector3, max_pos: Vector3, orientation: int) -> int:
	if not _autotile_extension or not _autotile_extension.is_ready():
		push_error("Autotile area fill: Extension not ready")
		return -1

	if not placement_manager or not current_tile_map3d:
		push_error("Autotile area fill: Missing placement manager or tile map")
		return -1

	var snap_size: float = placement_manager.grid_size if placement_manager else 1.0
	var positions: Array[Vector3] = GlobalUtil.get_grid_positions_in_area_with_snap(
		min_pos, max_pos, orientation, snap_size
	)

	if positions.is_empty():
		return 0

	if positions.size() > GlobalConstants.MAX_AREA_FILL_TILES:
		push_error("Autotile area fill: Area too large (%d tiles, max %d)" % [positions.size(), GlobalConstants.MAX_AREA_FILL_TILES])
		return -1

	var original_mesh_mode: GlobalConstants.MeshMode = current_tile_map3d.current_mesh_mode
	if current_tile_map3d.settings:
		current_tile_map3d.current_mesh_mode = current_tile_map3d.settings.mesh_mode

	placement_manager.start_paint_stroke(get_undo_redo(), "Autotile Area Fill (%d tiles)" % positions.size())

	placement_manager.begin_batch_update()

	var original_uv: Rect2 = placement_manager.current_tile_uv
	var original_src: int = placement_manager.current_atlas_source_id
	var original_coords: Vector2i = placement_manager.current_atlas_coords
	var original_terrain_id: int = placement_manager.current_terrain_id
	var terrain_id: int = _autotile_extension.current_terrain_id

	var placeholder_uv: Rect2 = _autotile_extension.get_autotile_uv(positions[0], orientation)
	if not placeholder_uv.has_area():
		placement_manager.end_batch_update()
		placement_manager.end_paint_stroke()
		current_tile_map3d.current_mesh_mode = original_mesh_mode
		placement_manager.current_terrain_id = original_terrain_id
		return 0

	var placeholder_binding: Array = _resolve_autotile_binding(placeholder_uv)

	var placed_positions: Array[Vector3] = []
	var tile_keys: Array[int] = []

	placement_manager.current_tile_uv = placeholder_uv
	placement_manager.current_atlas_source_id = placeholder_binding[0]
	placement_manager.current_atlas_coords = placeholder_binding[1]
	placement_manager.current_terrain_id = terrain_id
	for grid_pos: Vector3 in positions:
		if placement_manager.paint_tile_at(grid_pos, orientation):
			placed_positions.append(grid_pos)
			tile_keys.append(GlobalUtil.make_tile_key(grid_pos, orientation))

	placement_manager.current_tile_uv = original_uv
	placement_manager.current_atlas_source_id = original_src
	placement_manager.current_atlas_coords = original_coords
	placement_manager.current_terrain_id = original_terrain_id

	if placed_positions.is_empty():
		placement_manager.end_batch_update()
		placement_manager.end_paint_stroke()
		current_tile_map3d.current_mesh_mode = original_mesh_mode
		return 0

	# Now that all tiles have terrain_ids, bitmask calculation is correct.
	for i in range(placed_positions.size()):
		var grid_pos: Vector3 = placed_positions[i]
		var tile_key: int = tile_keys[i]

		var correct_uv: Rect2 = _autotile_extension.get_autotile_uv(grid_pos, orientation)

		if current_tile_map3d.has_tile(tile_key) and correct_uv.has_area():
			var current_uv: Rect2 = current_tile_map3d.get_tile_uv_rect(tile_key)
			if current_uv != correct_uv:
				var correct_binding: Array = _resolve_autotile_binding(correct_uv)
				current_tile_map3d.update_tile_uv(tile_key, correct_uv, correct_binding[0], correct_binding[1])

	var filled_set: Dictionary = {}
	for grid_pos: Vector3 in placed_positions:
		var key: int = GlobalUtil.make_tile_key(grid_pos, orientation)
		filled_set[key] = true

	var external_neighbors: Dictionary = {}
	for grid_pos: Vector3 in placed_positions:
		var neighbors: Array[Vector3] = PlaneCoordinateMapper.get_neighbor_positions_3d(grid_pos, orientation)
		for neighbor_pos: Vector3 in neighbors:
			var neighbor_key: int = GlobalUtil.make_tile_key(neighbor_pos, orientation)
			if not filled_set.has(neighbor_key) and current_tile_map3d.has_tile(neighbor_key):
				external_neighbors[neighbor_key] = neighbor_pos

	for neighbor_key: int in external_neighbors.keys():
		var neighbor_pos: Vector3 = external_neighbors[neighbor_key]

		var neighbor_terrain_id: int = current_tile_map3d.get_tile_terrain_id(neighbor_key)

		if neighbor_terrain_id < 0:
			continue

		var engine: AutotileEngine = _autotile_extension.get_engine()
		if engine:
			var new_bitmask: int = engine.calculate_bitmask(
				neighbor_pos, orientation, neighbor_terrain_id, current_tile_map3d
			)
			var new_uv: Rect2 = engine.get_uv_for_bitmask(neighbor_terrain_id, new_bitmask, engine.position_seed(neighbor_pos))

			var current_neighbor_uv: Rect2 = current_tile_map3d.get_tile_uv_rect(neighbor_key)
			if new_uv.has_area() and current_neighbor_uv != new_uv:
				var neighbor_binding: Array = _resolve_autotile_binding(new_uv)
				current_tile_map3d.update_tile_uv(neighbor_key, new_uv, neighbor_binding[0], neighbor_binding[1])

	placement_manager.end_batch_update()

	placement_manager.end_paint_stroke()

	current_tile_map3d.current_mesh_mode = original_mesh_mode

	return placed_positions.size()

func _on_highlight_tiles_in_area(start_pos: Vector3, end_pos: Vector3, orientation: int, is_erase: bool) -> void:
	if current_tile_map3d:
		current_tile_map3d.highlight_tiles_in_area(start_pos, end_pos, orientation, is_erase)


func _highlight_tiles_at_preview_position(grid_pos: Vector3, orientation: int, is_multi: bool) -> void:
	if not current_tile_map3d:
		return
	var selected: Array[Rect2] = []
	if is_multi:
		selected = _get_selected_tiles()
	var rotation: int = placement_manager.current_mesh_rotation if placement_manager else 0
	current_tile_map3d.highlight_at_preview(grid_pos, orientation, selected, rotation)


# Autotile placement requires default orientation — no user rotations.
func _reset_autotile_transforms() -> void:
	if not placement_manager:
		return
	GlobalPlaneDetector.reset_to_flat()
	placement_manager.current_mesh_rotation = 0
	var default_flip: bool = GlobalPlaneDetector.determine_auto_flip_for_plane(GlobalPlaneDetector.current_plane_6d)
	placement_manager.is_current_face_flipped = default_flip

	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.current_mesh_rotation = 0
		current_tile_map3d.settings.is_face_flipped = default_flip

	if tile_preview and current_tile_map3d and current_tile_map3d.settings:
		tile_preview.current_mesh_mode = current_tile_map3d.settings.mesh_mode


func _on_tilemap_main_mode_changed(mode: GlobalConstants.MainAppMode) -> void:

	if _sculpt_manager and current_tile_map3d:
		_sculpt_manager.reset()
		current_tile_map3d.update_gizmos()

	if _smart_fill_manager and current_tile_map3d:
		_smart_fill_manager.reset()
		current_tile_map3d.update_gizmos()

	if _vertex_edit_manager:
		_vertex_edit_manager.deselect()
		if current_tile_map3d:
			current_tile_map3d.update_gizmos()
			current_tile_map3d.smart_selected_tiles.clear()
			current_tile_map3d.clear_highlights()

	if current_tile_map3d:
		current_tile_map3d.settings.is_smart_select_active = false
		current_tile_map3d.smart_selected_tiles.clear()
		current_tile_map3d.clear_highlights()

	_set_tiling_mode_to_settings(mode)

	# Each mode has its own tile context, so always clear selection on any mode change.
	_clear_selection()
	if mode == GlobalConstants.MainAppMode.AUTOTILE:
		_reset_autotile_transforms()
	elif mode == GlobalConstants.MainAppMode.ANIMATED_TILES:
		if current_tile_map3d:
			current_tile_map3d.current_mesh_mode = GlobalConstants.MeshMode.FLAT_SQUARE

	if _autotile_extension:
		_autotile_extension.set_enabled(mode == GlobalConstants.MainAppMode.AUTOTILE)

	if tile_preview and current_tile_map3d and current_tile_map3d.settings:
		if mode == GlobalConstants.MainAppMode.AUTOTILE:
			tile_preview.current_mesh_mode = current_tile_map3d.settings.mesh_mode
		elif mode == GlobalConstants.MainAppMode.ANIMATED_TILES:
			tile_preview.current_mesh_mode = GlobalConstants.MeshMode.FLAT_SQUARE
		else:
			current_tile_map3d.current_mesh_mode = current_tile_map3d.settings.mesh_mode
			tile_preview.current_mesh_mode = current_tile_map3d.current_mesh_mode

	call_deferred("_sync_depth_for_mode", mode)

	_invalidate_preview()

	show_bottom_panel_and_ui()

func _on_editor_ui_rotate_requested(direction: int) -> void:
	if not placement_manager:
		return

	placement_manager.current_mesh_rotation = (placement_manager.current_mesh_rotation + direction) % GlobalConstants.MAX_SPIN_ROTATION_STEPS
	if placement_manager.current_mesh_rotation < 0:
		placement_manager.current_mesh_rotation += GlobalConstants.MAX_SPIN_ROTATION_STEPS

	_update_after_transform_change()


func _on_editor_ui_tilt_requested(reverse: bool) -> void:
	if reverse:
		GlobalPlaneDetector.cycle_tilt_backward()
	else:
		GlobalPlaneDetector.cycle_tilt_forward()

	var should_be_flipped: bool = GlobalPlaneDetector.determine_auto_flip_for_plane(GlobalPlaneDetector.current_plane_6d)
	if placement_manager:
		placement_manager.is_current_face_flipped = should_be_flipped

	_update_after_transform_change()


func _on_editor_ui_reset_requested() -> void:
	GlobalPlaneDetector.reset_to_flat()

	if placement_manager:
		placement_manager.current_mesh_rotation = 0
		var default_flip: bool = GlobalPlaneDetector.determine_auto_flip_for_plane(GlobalPlaneDetector.current_plane_6d)
		placement_manager.is_current_face_flipped = default_flip

	_update_after_transform_change()


func _on_editor_ui_flip_requested() -> void:
	if not placement_manager:
		return

	placement_manager.is_current_face_flipped = not placement_manager.is_current_face_flipped

	_update_after_transform_change()

func _on_editor_ui_smart_select_operation_requested(smart_mode_operation: GlobalConstants.SmartSelectionOperation) -> void:
	if not current_tile_map3d:
		return

	if not current_tile_map3d.settings.is_smart_select_active or current_tile_map3d.smart_selected_tiles.is_empty():
		push_warning("Smart Select: No active selection to operate on")
		return

	match smart_mode_operation:
		GlobalConstants.SmartSelectionOperation.DELETE:
			_delete_selected_tiles()

		GlobalConstants.SmartSelectionOperation.REPLACE_UV:
			var current_uv: Rect2 = selection_manager.get_first_tile()
			if not current_uv.has_area():
				print("Smart Select: No tile selected in TilesetPanel")
				return

			var tile_count: int = current_tile_map3d.smart_selected_tiles.size()
			var undo_redo: EditorUndoRedoManager = get_undo_redo()
			undo_redo.create_action("Smart Select Replace UV tiles: " +  str(tile_count), UndoRedo.MERGE_DISABLE, current_tile_map3d)

			var new_binding: Array = placement_manager._binding_for_uv_rect(current_uv)
			var new_atlas_source_id: int = new_binding[0]
			var new_atlas_coords: Vector2i = new_binding[1]

			for key: int in current_tile_map3d.smart_selected_tiles:
				if _vertex_edit_manager and _vertex_edit_manager.is_vertex_tile(key):
					var vtx_entry: VertexTileEntry = _vertex_edit_manager.get_vertex_entry(key)
					var old_uv: Rect2 = vtx_entry.uv_rect if vtx_entry != null else Rect2()
					undo_redo.add_do_method(_vertex_edit_manager, "update_vertex_tile_uv", key, current_uv)
					undo_redo.add_undo_method(_vertex_edit_manager, "update_vertex_tile_uv", key, old_uv)
					continue

				var existing_info: PlacedTileInfo = placement_manager._get_existing_tile_info(key)
				if existing_info == null:
					continue
				var old_uv: Rect2 = existing_info.uv_rect
				undo_redo.add_do_method(current_tile_map3d, "update_tile_uv",
						key, current_uv, new_atlas_source_id, new_atlas_coords)
				undo_redo.add_undo_method(current_tile_map3d, "update_tile_uv",
						key, old_uv, existing_info.atlas_source_id, existing_info.atlas_coords)

			undo_redo.commit_action()
			_mark_scene_dirty()

		GlobalConstants.SmartSelectionOperation.REPLACE_MESH_TYPE:
			_replace_selected_tiles_mesh_type()

# mesh_mode is in the packed flags (not the tile_key), so this is a delete + re-add at the same key.
func _replace_selected_tiles_mesh_type() -> void:
	if not current_tile_map3d:
		return
	var keys: Array[int] = current_tile_map3d.smart_selected_tiles
	if keys.is_empty():
		push_warning("Replace Mesh Type: No active selection to operate on")
		return

	var target_mode: GlobalConstants.MeshMode = editor_ui._context_toolbar.get_smart_select_target_mesh_mode()

	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	undo_redo.create_action("Smart Select Replace Mesh Type: %d" % keys.size(), 0, current_tile_map3d)

	for key: int in keys:
		if _vertex_edit_manager and _vertex_edit_manager.is_vertex_tile(key):
			continue
		var existing: PlacedTileInfo = placement_manager._get_existing_tile_info(key)
		if existing == null:
			continue

		var new_info: PlacedTileInfo = existing.copy()
		new_info.mesh_mode = target_mode
		new_info.depth_scale = 1.0
		new_info.spin_angle_rad = 0.0
		new_info.tilt_angle_rad = 0.0
		new_info.diagonal_scale = 0.0
		new_info.tilt_offset_factor = 0.0
		# Clear stored slope/custom transform, else the custom-transform branch reuses the old
		# off-grid transform, placing the new BOX/PRISM off-grid and reintroducing Z-fighting.
		new_info.has_custom_transform = false
		new_info.custom_transform = Transform3D()

		var pos: Vector3 = existing.grid_position
		var ori: int = existing.orientation
		var uv: Rect2 = existing.uv_rect
		var rot: int = existing.mesh_rotation

		undo_redo.add_do_method(placement_manager, "_do_erase_tile", key)
		undo_redo.add_do_method(placement_manager, "_do_place_tile", key, pos, uv, ori, rot, new_info)
		undo_redo.add_undo_method(placement_manager, "_do_erase_tile", key)
		undo_redo.add_undo_method(placement_manager, "_do_place_tile", key, pos, uv, ori, rot, existing)

	undo_redo.add_do_method(current_tile_map3d, "update_gizmos")
	undo_redo.add_undo_method(current_tile_map3d, "update_gizmos")
	undo_redo.commit_action()

	current_tile_map3d.highlight_tiles(current_tile_map3d.smart_selected_tiles)

func _update_after_transform_change() -> void:
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.current_mesh_rotation = placement_manager.current_mesh_rotation
		current_tile_map3d.settings.is_face_flipped = placement_manager.is_current_face_flipped

	if tile_preview:
		var camera: Camera3D = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
		if camera:
			_update_preview(camera, _cached_local_mouse_pos, true)

	_update_side_toolbar_status()

	update_overlays()


func _update_side_toolbar_status() -> void:
	if not editor_ui:
		return

	var rotation_steps: int = 0
	if placement_manager:
		rotation_steps = placement_manager.current_mesh_rotation

	var tilt_index: int = 0
	var current_orientation: int = GlobalPlaneDetector.current_tile_orientation_18d
	var tilt_sequence: Array = GlobalUtil.get_tilt_sequence(current_orientation)
	if tilt_sequence.size() > 0:
		var pos: int = tilt_sequence.find(current_orientation)
		if pos > 0:
			tilt_index = pos

	var is_flipped: bool = false
	if placement_manager:
		is_flipped = placement_manager.is_current_face_flipped

	editor_ui.update_status(rotation_steps, tilt_index, is_flipped)





func _sync_depth_for_mode(mode: GlobalConstants.MainAppMode) -> void:
	if not current_tile_map3d or not placement_manager:
		return

	var correct_depth: float = current_tile_map3d.settings.current_depth_scale

	placement_manager.current_depth_scale = correct_depth

	if tile_preview:
		tile_preview.current_depth_scale = correct_depth


func _sync_autotile_texture() -> void:
	if not _autotile_engine or not current_tile_map3d:
		return
	var resolved_texture: Texture2D = TileAtlasResolver.get_active_texture(current_tile_map3d)
	if resolved_texture == null:
		push_warning("Autotile: TileSet has no atlas texture - neighbor updates will fail!")
		return
	placement_manager.tileset_texture = resolved_texture
	current_tile_map3d.tileset_texture = resolved_texture
	current_tile_map3d.update_configuration_warnings()
	# Only update the display texture: a full settings reload cycles back here → stack overflow.
	if tileset_panel:
		tileset_panel.set_tileset_texture(resolved_texture)


func _on_autotile_tileset_changed(tileset: TileSet) -> void:
	if _autotile_engine:
		_autotile_engine = null

	if not tileset:
		if _autotile_extension:
			_autotile_extension.set_engine(null)
		return

	_autotile_engine = AutotileEngine.new(tileset)
	_sync_autotile_texture()

	if not _autotile_extension:
		_autotile_extension = AutotilePlacementExtension.new()

	if placement_manager and current_tile_map3d:
		_autotile_extension.setup(_autotile_engine, placement_manager, current_tile_map3d)

	_autotile_extension.set_engine(_autotile_engine)
	_autotile_extension.set_enabled(_is_autotile_mode())


func _on_autotile_terrain_selected(terrain_id: int) -> void:
	if _autotile_extension:
		_autotile_extension.set_terrain(terrain_id)

	_reset_autotile_transforms()

	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.active_terrain = terrain_id
		current_tile_map3d.settings.autotile_active_terrain = terrain_id


func _on_autotile_data_changed() -> void:
	if _autotile_engine:
		_autotile_engine.rebuild_lookup()
		_sync_autotile_texture()


func _on_clear_tileset_requested() -> void:
	if _autotile_engine:
		_autotile_engine = null
	if _autotile_extension:
		_autotile_extension.set_engine(null)

	if current_tile_map3d and current_tile_map3d.settings:
		var settings: TileMapLayerSettings = current_tile_map3d.settings
		current_tile_map3d.set_tileset(null)
		settings.tileset_texture = null
		current_tile_map3d.tileset_texture = null
		settings.active_source_id = GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID
		settings.active_terrain_set = GlobalConstants.AUTOTILE_DEFAULT_TERRAIN_SET
		settings.active_terrain = GlobalConstants.AUTOTILE_NO_TERRAIN
		settings.autotile_tileset = null
		settings.autotile_source_id = GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID
		settings.autotile_terrain_set = GlobalConstants.AUTOTILE_DEFAULT_TERRAIN_SET
		settings.autotile_active_terrain = GlobalConstants.AUTOTILE_NO_TERRAIN

	if tileset_panel and tileset_panel.auto_tile_tab:
		tileset_panel.auto_tile_tab.refresh_terrains()


func _on_sculpt_tiles_created(tile_list: Array[PlacedTileInfo]) -> void:
	if not current_tile_map3d or not placement_manager:
		return

	if tile_list.is_empty():
		return

	var overwritten_tiles: Array[PlacedTileInfo] = []
	for tile_info: PlacedTileInfo in tile_list:
		if current_tile_map3d.has_tile(tile_info.tile_key):
			var existing: PlacedTileInfo = placement_manager._get_existing_tile_info(tile_info.tile_key)
			if existing != null:
				overwritten_tiles.append(existing)

	var undo_redo: Object = get_undo_redo()
	undo_redo.create_action("Sculpt Place Tiles", UndoRedo.MERGE_DISABLE, current_tile_map3d)
	undo_redo.add_do_method(self, "_do_sculpt_place_tiles", tile_list)
	undo_redo.add_undo_method(self, "_undo_sculpt_place_tiles", tile_list, overwritten_tiles)
	undo_redo.commit_action()
	_mark_scene_dirty()

	if current_tile_map3d:
		current_tile_map3d.update_gizmos()


func _do_sculpt_place_tiles(tile_list: Array[PlacedTileInfo]) -> void:
	if not current_tile_map3d or not placement_manager:
		return

	var saved_mode: int = current_tile_map3d.current_mesh_mode
	placement_manager.begin_batch_update()

	for tile_info: PlacedTileInfo in tile_list:
		current_tile_map3d.current_mesh_mode = tile_info.mesh_mode
		placement_manager._do_place_tile(
			tile_info.tile_key,
			tile_info.grid_position,
			tile_info.uv_rect,
			tile_info.orientation,
			tile_info.mesh_rotation,
			tile_info
		)

	placement_manager.end_batch_update()
	current_tile_map3d.current_mesh_mode = saved_mode


func _undo_sculpt_place_tiles(tile_list: Array[PlacedTileInfo], overwritten_tiles: Array[PlacedTileInfo] = []) -> void:
	if not current_tile_map3d or not placement_manager:
		return

	var saved_mode: int = current_tile_map3d.current_mesh_mode
	placement_manager.begin_batch_update()

	for tile_info: PlacedTileInfo in tile_list:
		placement_manager._undo_place_tile(tile_info.tile_key)

	for tile_info: PlacedTileInfo in overwritten_tiles:
		current_tile_map3d.current_mesh_mode = tile_info.mesh_mode
		placement_manager._do_place_tile(
			tile_info.tile_key,
			tile_info.grid_position,
			tile_info.uv_rect,
			tile_info.orientation,
			tile_info.mesh_rotation,
			tile_info
		)

	placement_manager.end_batch_update()
	current_tile_map3d.current_mesh_mode = saved_mode

func _snapshot_existing_tile_for_undo(tile_key: int) -> PlacedTileInfo:
	if not current_tile_map3d or not placement_manager or not current_tile_map3d.has_tile(tile_key):
		return null

	return placement_manager._get_existing_tile_info(tile_key)


func _tile_matches_sculpt_cells(tile_info: PlacedTileInfo, cells: Dictionary, min_y: float, max_y: float) -> bool:
	var pos: Vector3 = tile_info.grid_position
	var y_tolerance: float = 0.001
	if pos.y < min_y - y_tolerance or pos.y > max_y + y_tolerance:
		return false

	var orientation: int = tile_info.orientation
	var base_orientation: int = GlobalUtil.get_base_tile_orientation(orientation)

	match base_orientation:
		GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
			return cells.has(Vector2i(roundi(pos.x), roundi(pos.z)))

		GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
			var cell_x: int = roundi(pos.x)
			var cell_z0: int = floori(pos.z)
			var cell_z1: int = ceili(pos.z)
			return cells.has(Vector2i(cell_x, cell_z0)) or cells.has(Vector2i(cell_x, cell_z1))

		GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
			var cell_x0: int = floori(pos.x)
			var cell_x1: int = ceili(pos.x)
			var cell_z: int = roundi(pos.z)
			return cells.has(Vector2i(cell_x0, cell_z)) or cells.has(Vector2i(cell_x1, cell_z))

		_:
			return cells.has(Vector2i(roundi(pos.x), roundi(pos.z)))


func _get_sculpt_cells_bounds(cells: Dictionary) -> Dictionary:
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF

	for cell: Vector2i in cells:
		min_x = minf(min_x, float(cell.x))
		max_x = maxf(max_x, float(cell.x))
		min_z = minf(min_z, float(cell.y))
		max_z = maxf(max_z, float(cell.y))

	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
	}


func _on_sculpt_erase_tiles_requested(cells: Dictionary, min_y: float, max_y: float) -> void:
	if not current_tile_map3d or not placement_manager:
		return

	if cells.is_empty():
		return

	var bounds: Dictionary = _get_sculpt_cells_bounds(cells)
	var half: float = GlobalConstants.MIN_SNAP_SIZE
	var query_min := Vector3(bounds["min_x"] - half, min_y, bounds["min_z"] - half)
	var query_max := Vector3(bounds["max_x"] + half, max_y, bounds["max_z"] + half)

	var candidate_tiles: Array = placement_manager._spatial_index.get_tiles_in_area(query_min, query_max)
	var tiles_to_erase: Array = []
	var seen_keys: Dictionary = {}
	for tile_key: int in candidate_tiles:
		if tile_key == -1 or seen_keys.has(tile_key):
			continue
		seen_keys[tile_key] = true

		if not current_tile_map3d.has_tile(tile_key):
			continue

		var tile_info: PlacedTileInfo = placement_manager._get_existing_tile_info(tile_key)
		if tile_info == null:
			continue
		if not _tile_matches_sculpt_cells(tile_info, cells, min_y, max_y):
			continue

		var existing_info: PlacedTileInfo = _snapshot_existing_tile_for_undo(tile_key)
		if existing_info == null:
			continue
		tiles_to_erase.append(existing_info)

	if tiles_to_erase.is_empty():
		return

	var undo_redo: Object = get_undo_redo()
	undo_redo.create_action("Sculpt Erase Tiles", UndoRedo.MERGE_DISABLE, current_tile_map3d)
	for tile_info: PlacedTileInfo in tiles_to_erase:
		undo_redo.add_do_method(placement_manager, "_do_erase_tile", tile_info.tile_key)
		undo_redo.add_undo_method(
			placement_manager, "_do_place_tile",
			tile_info.tile_key, tile_info.grid_position, tile_info.uv_rect,
			tile_info.orientation, tile_info.mesh_rotation, tile_info
		)

	placement_manager.begin_batch_update()
	undo_redo.commit_action()
	placement_manager.end_batch_update()
	_mark_scene_dirty()

	if current_tile_map3d:
		current_tile_map3d.update_gizmos()


# Marking an already-dirty scene is a no-op, so this belt-and-suspenders call is harmless.
func _mark_scene_dirty() -> void:
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _is_autotile_mode() -> bool:
	if current_tile_map3d and current_tile_map3d.settings:
		return current_tile_map3d.settings.main_app_mode == GlobalConstants.MainAppMode.AUTOTILE
	return false

func _is_animated_tile_mode() -> bool:
	if current_tile_map3d and current_tile_map3d.settings:
		return current_tile_map3d.settings.main_app_mode == GlobalConstants.MainAppMode.ANIMATED_TILES
	return false

func _is_animated_tile_mod() -> bool:
	if current_tile_map3d and current_tile_map3d.settings:
		return current_tile_map3d.settings.main_app_mode == GlobalConstants.MainAppMode.ANIMATED_TILES
	return false

func is_smart_operations_mode() -> bool:
	if current_tile_map3d and current_tile_map3d.settings:
		return current_tile_map3d.settings.main_app_mode == GlobalConstants.MainAppMode.SMART_OPERATIONS
	return false

func is_smart_select_mode() -> bool:
	if current_tile_map3d and current_tile_map3d.settings:
		return current_tile_map3d.settings.main_app_mode == GlobalConstants.MainAppMode.SMART_OPERATIONS and current_tile_map3d.settings.smart_operations_main_mode == GlobalConstants.SmartOperationsMainMode.SMART_SELECT
	return false

func is_smart_fill_mode() -> bool:
	if current_tile_map3d and current_tile_map3d.settings:
		return current_tile_map3d.settings.main_app_mode == GlobalConstants.MainAppMode.SMART_OPERATIONS and current_tile_map3d.settings.smart_operations_main_mode == GlobalConstants.SmartOperationsMainMode.SMART_FILL
	return false

func _is_sculpting_mode() -> bool:
	if current_tile_map3d and current_tile_map3d.settings:
		return current_tile_map3d.settings.main_app_mode == GlobalConstants.MainAppMode.SCULPT
	return false

func _is_vertex_edit_mode() -> bool:
	if current_tile_map3d and current_tile_map3d.settings:
		return current_tile_map3d.settings.main_app_mode == GlobalConstants.MainAppMode.VERTEX_EDIT
	return false
func _get_selected_tiles() -> Array[Rect2]:
	if selection_manager:
		return selection_manager.get_tiles_readonly()
	return []

func _has_multi_tile_selection() -> bool:
	if selection_manager:
		return selection_manager.has_multi_selection()
	return false

func _get_selection_anchor_index() -> int:
	if selection_manager:
		return selection_manager.get_anchor()
	return 0

func _set_tiling_mode_to_settings(mode: int) -> void:
	if current_tile_map3d and current_tile_map3d.settings:
		current_tile_map3d.settings.main_app_mode = mode

func _clear_selection() -> void:
	if selection_manager:
		selection_manager.clear()

func _invalidate_preview() -> void:
	if tile_preview:
		tile_preview.hide_preview()
		tile_preview._hide_all_preview_instances()
	_last_preview_grid_pos = Vector3.INF
	_last_preview_screen_pos = Vector2.INF


func _grid_to_absolute_world(grid_pos: Vector3) -> Vector3:
	var local_world: Vector3 = GlobalUtil.grid_to_world(grid_pos, placement_manager.grid_size)
	if current_tile_map3d:
		# to_global applies the node's full transform (position AND scale), matching rendering.
		return current_tile_map3d.to_global(local_world)
	return local_world


func _on_current_node_settings_changed() -> void:
	if not current_tile_map3d or not current_tile_map3d.settings:
		return

	var settings: TileMapLayerSettings = current_tile_map3d.settings

	current_tile_map3d.current_mesh_mode = settings.mesh_mode as GlobalConstants.MeshMode
	if tile_preview and not _is_autotile_mode():
		tile_preview.current_mesh_mode = current_tile_map3d.current_mesh_mode

	if _autotile_extension:
		_autotile_extension.set_enabled(settings.main_app_mode == GlobalConstants.MainAppMode.AUTOTILE)

	# Sync external selection edits (e.g. Inspector) back into SelectionManager.
	if selection_manager:
		var current_selection = selection_manager.get_tiles_readonly()
		if current_selection != settings.selected_tiles:
			selection_manager.restore_from_settings(settings.selected_tiles, settings.selected_anchor_index, true)


func _handle_vertex_edit_click(camera: Camera3D, screen_pos: Vector2) -> void:
	if not _vertex_edit_manager or not current_tile_map3d:
		return

	var pick_result: PlacedTileInfo = SmartSelectManager.pick_tile_at(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos), current_tile_map3d)

	if pick_result == null:
		current_tile_map3d.clear_highlights()
		current_tile_map3d.smart_selected_tiles.clear()
		_vertex_edit_manager.deselect()
		current_tile_map3d.update_gizmos()
		return

	var tile_key: int = pick_result.tile_key
	var is_vtx: bool = _vertex_edit_manager.is_vertex_tile(tile_key)

	if current_tile_map3d.smart_selected_tiles.has(tile_key):
		current_tile_map3d.smart_selected_tiles.erase(tile_key)
		if _vertex_edit_manager.selected_tile_key == tile_key:
			_vertex_edit_manager.deselect()
	else:
		current_tile_map3d.smart_selected_tiles.append(tile_key)

	if is_vtx and current_tile_map3d.smart_selected_tiles.has(tile_key):
		_vertex_edit_manager.select_tile(tile_key)
	else:
		_vertex_edit_manager.deselect()

	current_tile_map3d.highlight_tiles(current_tile_map3d.smart_selected_tiles)
	current_tile_map3d.update_gizmos()


func _on_vertex_convert_requested() -> void:
	if not _vertex_edit_manager or not current_tile_map3d:
		return
	var selected_keys: Array[int] = current_tile_map3d.smart_selected_tiles
	if selected_keys.is_empty():
		return

	var to_convert: Array[int] = []
	for tile_key: int in selected_keys:
		if not _vertex_edit_manager.is_vertex_tile(tile_key):
			to_convert.append(tile_key)

	if to_convert.is_empty():
		if selected_keys.size() == 1:
			_vertex_edit_manager.select_tile(selected_keys[0])
			current_tile_map3d.update_gizmos()
		return

	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	undo_redo.create_action("Convert to Vertex Tiles", 0, current_tile_map3d)
	for tile_key: int in to_convert:
		undo_redo.add_do_method(_vertex_edit_manager, "convert_tile", tile_key)
		undo_redo.add_undo_method(_vertex_edit_manager, "undo_convert_tile", tile_key)
	undo_redo.add_do_method(current_tile_map3d, "update_gizmos")
	undo_redo.add_undo_method(current_tile_map3d, "update_gizmos")
	undo_redo.commit_action()

	_vertex_edit_manager.select_tile(to_convert[0])
	current_tile_map3d.update_gizmos()


func _on_vertex_delete_requested() -> void:
	_delete_selected_tiles()


# Unified delete for both normal (columnar) tiles and vertex-edited (converted) tiles.
func _delete_selected_tiles() -> void:
	if not current_tile_map3d:
		return
	var selected_keys: Array[int] = current_tile_map3d.smart_selected_tiles
	if selected_keys.is_empty():
		push_warning("Delete: No active selection to operate on")
		return

	var normal_keys: Array[int] = []
	var vertex_keys: Array[int] = []
	var vertex_backups: Dictionary = {}

	for tile_key: int in selected_keys:
		if _vertex_edit_manager and _vertex_edit_manager.is_vertex_tile(tile_key):
			vertex_keys.append(tile_key)
			vertex_backups[tile_key] = _vertex_edit_manager.get_vertex_entry(tile_key)
		elif current_tile_map3d.has_tile(tile_key):
			normal_keys.append(tile_key)

	if normal_keys.is_empty() and vertex_keys.is_empty():
		return

	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	var total_count: int = normal_keys.size() + vertex_keys.size()
	undo_redo.create_action("Delete %d Tile(s)" % total_count, 0, current_tile_map3d)

	for key: int in normal_keys:
		var existing_info: PlacedTileInfo = placement_manager._get_existing_tile_info(key)
		if existing_info == null:
			continue
		var pos: Vector3 = existing_info.grid_position
		var ori: int = existing_info.orientation
		var uv_rect: Rect2 = existing_info.uv_rect
		var rotation: int = existing_info.mesh_rotation
		undo_redo.add_do_method(placement_manager, "_do_erase_tile", key)
		undo_redo.add_undo_method(placement_manager, "_do_place_tile", key, pos, uv_rect, ori, rotation, existing_info)

	for key: int in vertex_keys:
		undo_redo.add_do_method(_vertex_edit_manager, "delete_vertex_tile", key)
		undo_redo.add_undo_method(_vertex_edit_manager, "undo_delete_vertex_tile", key, vertex_backups[key])

	undo_redo.add_do_method(current_tile_map3d, "update_gizmos")
	undo_redo.add_undo_method(current_tile_map3d, "update_gizmos")
	undo_redo.commit_action()

	if _vertex_edit_manager:
		_vertex_edit_manager.deselect()
	current_tile_map3d.smart_selected_tiles.clear()
	current_tile_map3d.clear_highlights()
	current_tile_map3d.update_gizmos()
