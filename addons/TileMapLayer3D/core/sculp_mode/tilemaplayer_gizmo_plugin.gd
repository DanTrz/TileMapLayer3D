class_name TileMapLayerGizmoPlugin
extends EditorNode3DGizmoPlugin

var sculpt_manager: SculptManager = null

var smart_fill_manager: SmartFillManager = null

var vertex_edit_manager: VertexEditManager = null

var _active_tilema3d_node: TileMapLayer3D = null

## Undo/redo manager reference for vertex handle commits
## Must be EditorUndoRedoManager from EditorPlugin.get_undo_redo()
var _undo_redo: Object = null


var current_gizmo: TileMapLayerGizmo = null


func _init() -> void:
	create_material("brush_cell", Color(0.2, 0.8, 1.0, 0.4), false, true)
	create_material("brush_pattern", Color(0.1, 0.5, 0.8, 0.3), false, true)
	create_material("brush_pattern_ready", Color(0.9, 0.8, 0.1, 0.4), false, true)
	create_material("brush_raise", Color(1.0, 0.9, 0.0, 0.5), false, true)
	create_material("brush_lower", Color(1.0, 0.2, 0.2, 0.5), false, true)
	create_material("smart_fill_start", GlobalConstants.SMART_FILL_START_MARKER_COLOR, false, true)
	create_material("smart_fill_preview", GlobalConstants.SMART_FILL_PREVIEW_COLOR, false, true)
	create_handle_material("vertex_handle", false, null)
	create_material("vertex_wireframe", GlobalConstants.VERTEX_WIREFRAME_COLOR, false, true)

func set_active_node(tile_map_node: TileMapLayer3D, smart_fill_node: SmartFillManager, sculpt_node: SculptManager) -> void:
	_active_tilema3d_node = tile_map_node
	smart_fill_manager = smart_fill_node
	sculpt_manager = sculpt_node


func _has_gizmo(node: Node3D) -> bool:
	return node is TileMapLayer3D


func _create_gizmo(node: Node3D) -> EditorNode3DGizmo:
	current_gizmo = TileMapLayerGizmo.new()
	return current_gizmo


func _get_gizmo_name() -> String:
	return "TileMapLayer Brush"



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
	if not vertex_edit_manager or vertex_edit_manager.selected_tile_key == -1:
		return
	if handle_id < 0 or handle_id > 3:
		return

	var tile_key: int = vertex_edit_manager.selected_tile_key
	var corners: PackedVector3Array = vertex_edit_manager.get_handle_positions(tile_key)
	if corners.size() != 4:
		return

	var gs: float = _active_tilema3d_node.grid_size if _active_tilema3d_node else 1.0
	var result: Variant = vertex_edit_manager.project_to_snapped_position(camera, screen_point, corners[handle_id], gs)
	if result == null:
		return

	vertex_edit_manager.update_corner(tile_key, handle_id, result as Vector3)
	gizmo.get_node_3d().update_gizmos()


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	if not vertex_edit_manager or vertex_edit_manager.selected_tile_key == -1:
		return
	if handle_id < 0 or handle_id > 3:
		return

	var tile_key: int = vertex_edit_manager.selected_tile_key
	var node: Node3D = gizmo.get_node_3d()

	if cancel:
		vertex_edit_manager.update_corner(tile_key, handle_id, restore as Vector3)
		node.update_gizmos()
		return

	if _undo_redo and node:
		var new_pos: Vector3 = vertex_edit_manager.get_handle_positions(tile_key)[handle_id]
		_undo_redo.create_action("Move Vertex Corner", 0, node)
		_undo_redo.add_do_method(vertex_edit_manager, "update_corner", tile_key, handle_id, new_pos)
		_undo_redo.add_undo_method(vertex_edit_manager, "update_corner", tile_key, handle_id, restore)
		_undo_redo.add_do_method(node, "update_gizmos")
		_undo_redo.add_undo_method(node, "update_gizmos")
		_undo_redo.commit_action(false)  # Don't execute again (already applied live)
