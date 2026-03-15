class_name SculptBrushGizmoPlugin
extends EditorNode3DGizmoPlugin

## The sculpt state hub. Set by the plugin after construction.
## Read by SculptBrushGizmo._redraw() via get_plugin().sculpt_manager.
var sculpt_manager: SculptManager = null

## Smart Fill manager. Set by the plugin for preview rendering.
var smart_fill_manager: SmartFillManager = null

var _active_tilema3d_node: TileMapLayer3D = null  # TileMapLayer3D


## The active gizmo instance. Stored so the plugin can call update_gizmos()
## without needing a separate lookup. Godot has no "get back the gizmo" API.
var current_gizmo: SculptBrushGizmo = null


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
	current_gizmo = SculptBrushGizmo.new()
	return current_gizmo


func _get_gizmo_name() -> String:
	return "Sculpt Brush"
