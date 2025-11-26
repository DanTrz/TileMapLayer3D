@tool
class_name CursorPlaneVisualizer
extends Node3D

## Visualizes the three invisible cursor planes with dotted grid lines
## Helps debug and verify proper grid alignment across all three axes

@export var grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE:
	set(value):
		if not Engine.is_editor_hint(): return
		if value > 0.0:
			grid_size = value
			_update_visualization()

@export var grid_extent: int = GlobalConstants.DEFAULT_GRID_EXTENT:  # How many grid lines to show in each direction
	set(value):
		if not Engine.is_editor_hint(): return
		grid_extent = max(1, value)
		_update_visualization()

@export var line_color: Color = GlobalConstants.DEFAULT_GRID_LINE_COLOR:
	set(value):
		if not Engine.is_editor_hint(): return
		line_color = value
		_update_visualization()

@export var visible_planes: bool = true:
	set(value):
		if not Engine.is_editor_hint(): return
		visible_planes = value
		_update_visibility()

# Grid and Plane Colors
@export var active_overlay_alpha: float = GlobalConstants.ACTIVE_OVERLAY_ALPHA  # Slightly more visible since it's the only one
@export var grid_line_alpha: float = GlobalConstants.ACTIVE_GRID_LINE_ALPHA  # Slightly more visible since it's the only one

# Visual components - grid lines
var _yz_plane: MeshInstance3D = null  # Perpendicular to X-axis (right plane)
var _xz_plane: MeshInstance3D = null  # Perpendicular to Y-axis (horizontal plane)
var _xy_plane: MeshInstance3D = null  # Perpendicular to Z-axis (front plane)

# Visual components - colored overlays
var _yz_overlay: MeshInstance3D = null
var _xz_overlay: MeshInstance3D = null
var _xy_overlay: MeshInstance3D = null




func _ready() -> void:
	if not Engine.is_editor_hint(): return
	_create_plane_visuals()
	_create_plane_overlays()
	_update_visualization()

## Creates the three plane visualizers
func _create_plane_visuals() -> void:
	# YZ Plane (perpendicular to X-axis, faces right)
	_yz_plane = _create_plane_mesh(Vector3.RIGHT, Color(1, 0, 0, 0.15))
	_yz_plane.name = "YZPlane"
	add_child(_yz_plane)

	# XZ Plane (perpendicular to Y-axis, faces up/down - horizontal)
	_xz_plane = _create_plane_mesh(Vector3.UP, Color(0, 1, 0, 0.15))
	_xz_plane.name = "XZPlane"
	add_child(_xz_plane)

	# XY Plane (perpendicular to Z-axis, faces forward)
	_xy_plane = _create_plane_mesh(Vector3.FORWARD, Color(0, 0, 1, 0.15))
	_xy_plane.name = "XYPlane"
	add_child(_xy_plane)

## Creates a single plane mesh with grid lines
func _create_plane_mesh(normal: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()

	# Create ImmediateMesh for drawing grid lines
	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	mesh_instance.mesh = immediate_mesh

	# Create unshaded material for grid lines
	# NOTE: Uses default render_priority (0) which is correct - grid lines should
	# render behind tiles (which also use priority 0) and behind highlights (priority 10).
	# See GlobalConstants.DEFAULT_RENDER_PRIORITY for the standard tile render priority.
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = line_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Show from both sides
	mesh_instance.material_override = material

	return mesh_instance

## Creates colored plane overlays that highlight the active plane
func _create_plane_overlays() -> void:
	var overlay_size: float = float(grid_extent) * grid_size
	# Push overlay back slightly so it appears behind tiles
	var push_back: float = GlobalConstants.get_plane_pushback(grid_size)

	# YZ Plane overlay (red tint) - perpendicular to X
	_yz_overlay = _create_plane_overlay(Vector3.RIGHT, GlobalConstants.YZ_PLANE_COLOR, overlay_size)
	_yz_overlay.name = "YZOverlay"
	_yz_overlay.position = Vector3(push_back, 0, 0)  # Push back on X axis
	add_child(_yz_overlay)

	# XZ Plane overlay (green tint) - perpendicular to Y
	_xz_overlay = _create_plane_overlay(Vector3.UP, GlobalConstants.XZ_PLANE_COLOR, overlay_size)
	_xz_overlay.name = "XZOverlay"
	_xz_overlay.position = Vector3(0, push_back, 0)  # Push back on Y axis
	add_child(_xz_overlay)

	# XY Plane overlay (blue tint) - perpendicular to Z
	_xy_overlay = _create_plane_overlay(Vector3.FORWARD, GlobalConstants.XY_PLANE_COLOR, overlay_size)
	_xy_overlay.name = "XYOverlay"
	_xy_overlay.position = Vector3(0, 0, push_back)  # Push back on Z axis
	add_child(_xy_overlay)

## Creates a single semi-transparent plane overlay
func _create_plane_overlay(normal: Vector3, color: Color, size: float) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()

	# Create a quad mesh for the plane
	var plane_mesh: PlaneMesh = PlaneMesh.new()

	# Orient the plane based on its normal
	if normal == Vector3.UP:
		# XZ plane (horizontal)
		plane_mesh.size = Vector2(size * 2, size * 2)
		plane_mesh.orientation = PlaneMesh.FACE_Y
	elif normal == Vector3.RIGHT:
		# YZ plane (perpendicular to X)
		plane_mesh.size = Vector2(size * 2, size * 2)
		plane_mesh.orientation = PlaneMesh.FACE_X
	else: # Vector3.FORWARD
		# XY plane (perpendicular to Z)
		plane_mesh.size = Vector2(size * 2, size * 2)
		plane_mesh.orientation = PlaneMesh.FACE_Z

	mesh_instance.mesh = plane_mesh

	# Create semi-transparent material
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color  # Start invisible
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material

	return mesh_instance

## Updates the grid visualization for all planes
func _update_visualization() -> void:
	if not is_inside_tree():
		return

	if _yz_plane:
		_draw_plane_grid(_yz_plane, Vector3.RIGHT)
	if _xz_plane:
		_draw_plane_grid(_xz_plane, Vector3.UP)
	if _xy_plane:
		_draw_plane_grid(_xy_plane, Vector3.FORWARD)

## Draws a grid on a plane using ImmediateMesh
func _draw_plane_grid(mesh_instance: MeshInstance3D, normal: Vector3) -> void:
	var immediate_mesh: ImmediateMesh = mesh_instance.mesh as ImmediateMesh
	if not immediate_mesh:
		return

	# Clear previous mesh
	immediate_mesh.clear_surfaces()

	# Determine the two perpendicular axes for this plane
	var axis1: Vector3
	var axis2: Vector3
	var depth_offset: Vector3  # Push grid back along plane normal

	# Get per-axis push-back values
	var push_back_vec: Vector3 = GlobalConstants.get_visual_grid_pushback(grid_size)

	if normal == Vector3.RIGHT:  # YZ plane
		axis1 = Vector3.UP
		axis2 = Vector3.FORWARD
		depth_offset = Vector3.RIGHT * push_back_vec.x  # Use X component for YZ plane
	elif normal == Vector3.UP:  # XZ plane
		axis1 = Vector3.RIGHT
		axis2 = Vector3.FORWARD
		depth_offset = Vector3.UP * push_back_vec.y  # Use Y component for XZ plane
	else:  # Vector3.FORWARD - XY plane
		axis1 = Vector3.RIGHT
		axis2 = Vector3.UP
		depth_offset = Vector3.FORWARD * push_back_vec.z  # Use Z component for XY plane

	# Get visual offset (purely cosmetic - does NOT affect cursor/placement logic)
	# Combines horizontal offset (0.5, 0.5, 0.5) with depth push-back
	var visual_offset: Vector3 = GlobalConstants.get_visual_grid_offset(grid_size) + depth_offset

	# Begin drawing lines
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Draw grid lines along axis1
	for i in range(-grid_extent, grid_extent + 1):
		var offset: float = float(i) * grid_size
		var start: Vector3 = axis1 * offset + axis2 * (-grid_extent * grid_size) + visual_offset
		var end: Vector3 = axis1 * offset + axis2 * (grid_extent * grid_size) + visual_offset

		_draw_dotted_line(immediate_mesh, start, end, GlobalConstants.get_dash_length(grid_size))

	# Draw grid lines along axis2
	for i in range(-grid_extent, grid_extent + 1):
		var offset: float = float(i) * grid_size
		var start: Vector3 = axis2 * offset + axis1 * (-grid_extent * grid_size) + visual_offset
		var end: Vector3 = axis2 * offset + axis1 * (grid_extent * grid_size) + visual_offset

		_draw_dotted_line(immediate_mesh, start, end, GlobalConstants.get_dash_length(grid_size))

	immediate_mesh.surface_end()

## Draws a dotted line between two points
func _draw_dotted_line(mesh: ImmediateMesh, start: Vector3, end: Vector3, dash_length: float) -> void:
	var direction: Vector3 = end - start
	var distance: float = direction.length()
	var normalized_dir: Vector3 = direction.normalized()

	var current_pos: float = 0.0
	var is_dash: bool = true

	while current_pos < distance:
		var next_pos: float = min(current_pos + dash_length, distance)

		if is_dash:
			mesh.surface_add_vertex(start + normalized_dir * current_pos)
			mesh.surface_add_vertex(start + normalized_dir * next_pos)

		current_pos = next_pos
		is_dash = not is_dash

## Updates visibility of all planes
func _update_visibility() -> void:
	if _yz_plane:
		_yz_plane.visible = visible_planes
	if _xz_plane:
		_xz_plane.visible = visible_planes
	if _xy_plane:
		_xy_plane.visible = visible_planes

## Sets which plane is active (shows only active plane, hides others)
## active_plane_normal: Vector3.RIGHT (YZ), Vector3.UP (XZ), or Vector3.FORWARD (XY)
func set_active_plane(active_plane_normal: Vector3) -> void:
	if not visible_planes:
		print("trying to set_active_plane - no planes visible - returning")
		return

	# print("set_active_plane - activating planes")

	# HIDE inactive planes, SHOW only active plane (reduces visual clutter)
	var is_yz_active: bool = (active_plane_normal == Vector3.RIGHT)
	var is_xz_active: bool = (active_plane_normal == Vector3.UP)
	var is_xy_active: bool = (active_plane_normal == Vector3.FORWARD)

	# Show/hide grid lines based on active plane
	if _yz_plane:
		_yz_plane.visible = is_yz_active
	if _xz_plane:
		_xz_plane.visible = is_xz_active
	if _xy_plane:
		_xy_plane.visible = is_xy_active

	# Show/hide colored overlays based on active plane
	if _yz_overlay:
		_yz_overlay.visible = is_yz_active
	if _xz_overlay:
		_xz_overlay.visible = is_xz_active
	if _xy_overlay:
		_xy_overlay.visible = is_xy_active

	# Set active plane color to full brightness
	var active_grid_color: Color = Color(line_color.r, line_color.g, line_color.b, grid_line_alpha)

	if is_yz_active and _yz_plane and _yz_plane.material_override:
		var mat: StandardMaterial3D = _yz_plane.material_override as StandardMaterial3D
		mat.albedo_color = active_grid_color
		if _yz_overlay and _yz_overlay.material_override:
			var overlay_mat: StandardMaterial3D = _yz_overlay.material_override as StandardMaterial3D
			overlay_mat.albedo_color = Color(1, 0, 0, active_overlay_alpha)  # Red

	if is_xz_active and _xz_plane and _xz_plane.material_override:
		var mat: StandardMaterial3D = _xz_plane.material_override as StandardMaterial3D
		mat.albedo_color = active_grid_color
		if _xz_overlay and _xz_overlay.material_override:
			var overlay_mat: StandardMaterial3D = _xz_overlay.material_override as StandardMaterial3D
			overlay_mat.albedo_color = Color(0, 1, 0, active_overlay_alpha)  # Green

	if is_xy_active and _xy_plane and _xy_plane.material_override:
		var mat: StandardMaterial3D = _xy_plane.material_override as StandardMaterial3D
		mat.albedo_color = active_grid_color
		if _xy_overlay and _xy_overlay.material_override:
			var overlay_mat: StandardMaterial3D = _xy_overlay.material_override as StandardMaterial3D
			overlay_mat.albedo_color = Color(0, 0, 1, active_overlay_alpha)  # Blue

## Updates the material color
func _update_material_color() -> void:
	var planes: Array[MeshInstance3D] = [_yz_plane, _xz_plane, _xy_plane]
	for plane in planes:
		if plane and plane.material_override:
			(plane.material_override as StandardMaterial3D).albedo_color = line_color
