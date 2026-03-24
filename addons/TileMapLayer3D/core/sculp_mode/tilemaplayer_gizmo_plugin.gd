class_name TileMapLayerGizmoPlugin
extends EditorNode3DGizmoPlugin

## The sculpt state hub. Set by the plugin after construction.
## Read by TileMapLayerGizmo._redraw() via get_plugin().sculpt_manager.
var sculpt_manager: SculptManager = null

## Smart Fill manager. Set by the plugin for preview rendering.
var smart_fill_manager: SmartFillManager = null

## Vertex Edit manager. Set by the plugin for handle interaction.
var vertex_edit_manager: VertexEditManager = null

var _active_tilema3d_node: TileMapLayer3D = null  # TileMapLayer3D

## Undo/redo manager reference for vertex handle commits
## Must be EditorUndoRedoManager from EditorPlugin.get_undo_redo()
var _undo_redo: Object = null


## The active gizmo instance. Stored so the plugin can call update_gizmos()
## without needing a separate lookup. Godot has no "get back the gizmo" API.
var current_gizmo: TileMapLayerGizmo = null


func _init() -> void:
	# Current brush cells: cyan/blue semi-transparent quads under cursor now.
	create_material("brush_cell", Color(0.2, 0.8, 1.0, 0.4), false, true)
	# Drag pattern cells (DRAWING): slightly darker cyan for accumulated swept area.
	# Visually distinct from current brush but in the same colour family.
	create_material("brush_pattern", Color(0.1, 0.5, 0.8, 0.3), false, true)
	# Pattern ready cells (PATTERN_READY): yellow — "click me to raise/lower".
	# Brighter when hovering (gizmo switches to brush_raise material for hover hint).
	create_material("brush_pattern_ready", Color(0.9, 0.8, 0.1, 0.4), false, true)
	# Raise preview: yellow semi-transparent quads at target height when raising.
	create_material("brush_raise", Color(1.0, 0.9, 0.0, 0.5), false, true)
	# Lower preview: red semi-transparent quads at target height when lowering.
	create_material("brush_lower", Color(1.0, 0.2, 0.2, 0.5), false, true)
	# Smart Fill: green start marker + cyan preview quad.
	create_material("smart_fill_start", GlobalConstants.SMART_FILL_START_MARKER_COLOR, false, true)
	create_material("smart_fill_preview", GlobalConstants.SMART_FILL_PREVIEW_COLOR, false, true)
	# Vertex Edit: RED handle material for corner dragging.
	create_handle_material("vertex_handle", false, null)

func set_active_node(tilemap_node: TileMapLayer3D, smart_fill_node: SmartFillManager, sculpt_node: SculptManager) -> void:
	_active_tilema3d_node = tilemap_node
	smart_fill_manager = smart_fill_node
	sculpt_manager = sculpt_node


func _has_gizmo(node: Node3D) -> bool:
	## Only attach this gizmo to TileMapLayer3D nodes.
	return node is TileMapLayer3D


func _create_gizmo(node: Node3D) -> EditorNode3DGizmo:
	## Called by Godot once per TileMapLayer3D in the scene.
	## We store the reference so the plugin can trigger redraws via update_gizmos().
	current_gizmo = TileMapLayerGizmo.new()
	return current_gizmo


func _get_gizmo_name() -> String:
	return "TileMapLayer Brush"


# --- Vertex Edit Handle Methods ---

func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	var names: Array[String] = ["BL", "BR", "TR", "TL"]
	if handle_id >= 0 and handle_id < 4:
		return names[handle_id]
	return "Unknown"


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	if not vertex_edit_manager or vertex_edit_manager.selected_tile_key == -1:
		return Vector3.ZERO
	var corners: PackedVector3Array = vertex_edit_manager.get_handle_positions(vertex_edit_manager.selected_tile_key)
	if handle_id >= 0 and handle_id < corners.size():
		return corners[handle_id]
	return Vector3.ZERO


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_point: Vector2) -> void:
	# NOTE: Gizmo handle methods kept for Godot API compliance, but actual dragging
	# is handled manually in _forward_3d_gui_input via VertexEditManager.begin_drag/drag_to/end_drag.
	if not vertex_edit_manager or vertex_edit_manager.selected_tile_key == -1:
		return
	if handle_id < 0 or handle_id > 3:
		return

	var tile_key: int = vertex_edit_manager.selected_tile_key
	var corners: PackedVector3Array = vertex_edit_manager.get_handle_positions(tile_key)
	if corners.size() != 4:
		return

	# Project screen point onto a camera-facing plane through the handle.
	# This prevents wild jumps when the tile plane is near-parallel to the view.
	var current_corner: Vector3 = corners[handle_id]
	var ray_from: Vector3 = camera.project_ray_origin(screen_point)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_point)
	var cam_plane: Plane = Plane(-camera.global_basis.z, current_corner)
	var hit: Variant = cam_plane.intersects_ray(ray_from, ray_dir)
	if hit == null:
		return

	# Snap to half-grid
	var snapped_pos: Vector3 = hit as Vector3
	var gs: float = _active_tilema3d_node.grid_size if _active_tilema3d_node else 1.0
	var half_gs: float = gs / 2.0
	snapped_pos.x = snapped(snapped_pos.x, half_gs)
	snapped_pos.y = snapped(snapped_pos.y, half_gs)
	snapped_pos.z = snapped(snapped_pos.z, half_gs)

	vertex_edit_manager.update_corner(tile_key, handle_id, snapped_pos)
	gizmo.get_node_3d().update_gizmos()


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	if not vertex_edit_manager or vertex_edit_manager.selected_tile_key == -1:
		return
	if handle_id < 0 or handle_id > 3:
		return

	var tile_key: int = vertex_edit_manager.selected_tile_key
	var node: Node3D = gizmo.get_node_3d()

	if cancel:
		# Revert to the saved position
		vertex_edit_manager.update_corner(tile_key, handle_id, restore as Vector3)
		node.update_gizmos()
		return

	# Create undo/redo action with correct history context
	if _undo_redo and node:
		var new_pos: Vector3 = vertex_edit_manager.get_handle_positions(tile_key)[handle_id]
		# Use object-specific history to avoid "history mismatch" error
		_undo_redo.create_action("Move Vertex Corner", 0, node)
		_undo_redo.add_do_method(vertex_edit_manager, "update_corner", tile_key, handle_id, new_pos)
		_undo_redo.add_undo_method(vertex_edit_manager, "update_corner", tile_key, handle_id, restore)
		_undo_redo.add_do_method(node, "update_gizmos")
		_undo_redo.add_undo_method(node, "update_gizmos")
		_undo_redo.commit_action(false)  # Don't execute again (already applied live)
