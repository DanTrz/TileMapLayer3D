class_name TileMapLayerGizmo
extends EditorNode3DGizmo

func _redraw() -> void:
	clear()

	var gizmo_plugin: TileMapLayerGizmoPlugin = get_plugin() as TileMapLayerGizmoPlugin
	if not gizmo_plugin:
		return
	
	if gizmo_plugin._active_tilema3d_node:
		match gizmo_plugin._active_tilema3d_node.settings.main_app_mode:
			GlobalConstants.MainAppMode.SMART_OPERATIONS:
					_draw_smart_fill_preview(gizmo_plugin)

			GlobalConstants.MainAppMode.SCULPT:
					_draw_sculpt_preview(gizmo_plugin)

			GlobalConstants.MainAppMode.VERTEX_EDIT:
					_draw_vertex_edit_handles(gizmo_plugin)

func _draw_vertex_edit_handles(gizmo_plugin: TileMapLayerGizmoPlugin) -> void:
	var vem: VertexEditManager = gizmo_plugin.vertex_edit_manager
	if not vem or vem.selected_tile_key == -1:
		return

	var corners: PackedVector3Array = vem.get_handle_positions(vem.selected_tile_key)
	if corners.size() != 4:
		return

	# All gizmo geometry must be in LOCAL space (relative to the TileMapLayer3D node)
	var node: Node3D = get_node_3d()
	var node_inv: Transform3D = node.global_transform.affine_inverse() if node else Transform3D()

	var local_corners: PackedVector3Array = PackedVector3Array()
	for corner: Vector3 in corners:
		local_corners.append(node_inv * corner)

	var wireframe_mat: Material = get_plugin().get_material("vertex_wireframe", self)

	var lines: PackedVector3Array = PackedVector3Array()
	lines.append(local_corners[0]); lines.append(local_corners[1])
	lines.append(local_corners[1]); lines.append(local_corners[2])
	lines.append(local_corners[2]); lines.append(local_corners[3])
	lines.append(local_corners[3]); lines.append(local_corners[0])
	lines.append(local_corners[0]); lines.append(local_corners[2])
	lines.append(local_corners[1]); lines.append(local_corners[3])
	add_lines(lines, wireframe_mat, false)

	var handle_mat: Material = get_plugin().get_material("vertex_handle", self)
	add_handles(local_corners, handle_mat, PackedInt32Array([0, 1, 2, 3]))


func _draw_sculpt_preview(gizmo_plugin: TileMapLayerGizmoPlugin) -> void:
	## All state lives in SculptManager. We read it here, never store it.
	var sculpt_manager: SculptManager = gizmo_plugin.sculpt_manager
	if not sculpt_manager or not sculpt_manager.is_active:
		return

	var cell_mat: Material = get_plugin().get_material("brush_cell", self)
	var pattern_mat: Material = get_plugin().get_material("brush_pattern", self)
	var pattern_ready_mat: Material = get_plugin().get_material("brush_pattern_ready", self)
	var raise_mat: Material = get_plugin().get_material("brush_raise", self)
	var lower_mat: Material = get_plugin().get_material("brush_lower", self)

	var center: Vector3 = sculpt_manager.brush_grid_pos
	var gs: float = sculpt_manager.grid_size
	var radius: int = sculpt_manager.brush_type
	var raise_amount: float = sculpt_manager.get_raise_amount()

	var floor_y: float
	if sculpt_manager.state == SculptManager.SculptState.SETTING_HEIGHT:
		var anchor_world_y: float = (sculpt_manager.drag_anchor_grid_pos.y + GlobalConstants.GRID_ALIGNMENT_OFFSET.y) * gs
		floor_y = anchor_world_y + GlobalConstants.SCULPT_GIZMO_FLOOR_OFFSET
	else:
		var center_world_y: float = (center.y + GlobalConstants.GRID_ALIGNMENT_OFFSET.y) * gs
		floor_y = center_world_y + GlobalConstants.SCULPT_GIZMO_FLOOR_OFFSET

	var cell_mesh: PlaneMesh = PlaneMesh.new()
	cell_mesh.size = Vector2(gs * GlobalConstants.SCULPT_CELL_GAP_FACTOR, gs * GlobalConstants.SCULPT_CELL_GAP_FACTOR)

	var h: float = gs * 0.5 * GlobalConstants.SCULPT_CELL_GAP_FACTOR
	var gap_size: float = gs * GlobalConstants.SCULPT_CELL_GAP_FACTOR
	var tri_meshes: Array[ArrayMesh] = [
		null,
		_make_triangle_mesh(h, GlobalConstants.SculptCellType.TRI_NE),
		_make_triangle_mesh(h, GlobalConstants.SculptCellType.TRI_NW),
		_make_triangle_mesh(h, GlobalConstants.SculptCellType.TRI_SE),
		_make_triangle_mesh(h, GlobalConstants.SculptCellType.TRI_SW),
		_make_arch_cap_gizmo_mesh(gap_size, 0),
		_make_arch_cap_gizmo_mesh(gap_size, 3),
		_make_arch_cap_gizmo_mesh(gap_size, 1),
		_make_arch_cap_gizmo_mesh(gap_size, 2),
	]

	var snap_x: int = roundi(center.x)
	var snap_z: int = roundi(center.z)
	var ring_center: Vector3 = GlobalUtil.grid_to_world(Vector3(snap_x, 0, snap_z), gs)
	ring_center.y = floor_y

	var show_live_brush: bool = (
		sculpt_manager.state == SculptManager.SculptState.IDLE or
		sculpt_manager.state == SculptManager.SculptState.DRAWING
	)
	if show_live_brush:
		for offset: Vector2i in sculpt_manager._brush_template:
			var cell_type: int = sculpt_manager._brush_template[offset]
			var grid_pos: Vector3 = Vector3(snap_x + offset.x, 0, snap_z + offset.y)
			var cell_pos: Vector3 = GlobalUtil.grid_to_world(grid_pos, gs)
			cell_pos.y = floor_y
			if cell_type == GlobalConstants.SculptCellType.SQUARE:
				add_mesh(cell_mesh, cell_mat, Transform3D(Basis(), cell_pos))
			else:
				add_mesh(tri_meshes[cell_type], cell_mat, Transform3D(Basis(), cell_pos))

	var show_pattern: bool = not sculpt_manager.drag_pattern.is_empty() and (
		sculpt_manager.state == SculptManager.SculptState.DRAWING or
		sculpt_manager.state == SculptManager.SculptState.PATTERN_READY or
		sculpt_manager.state == SculptManager.SculptState.SETTING_HEIGHT
	)
	if show_pattern:
		var use_mat: Material
		if sculpt_manager.state == SculptManager.SculptState.DRAWING:
			use_mat = pattern_mat
		elif sculpt_manager.is_hovering_pattern:
			use_mat = raise_mat
		else:
			use_mat = pattern_ready_mat

		for cell: Vector2i in sculpt_manager.drag_pattern:
			var cell_type: int = sculpt_manager.drag_pattern[cell]
			var grid_pos: Vector3 = Vector3(cell.x, 0, cell.y)
			var pattern_pos: Vector3 = GlobalUtil.grid_to_world(grid_pos, gs)
			pattern_pos.y = floor_y
			if cell_type == GlobalConstants.SculptCellType.SQUARE:
				add_mesh(cell_mesh, use_mat, Transform3D(Basis(), pattern_pos))
			else:
				add_mesh(tri_meshes[cell_type], use_mat, Transform3D(Basis(), pattern_pos))

	if sculpt_manager.state == SculptManager.SculptState.SETTING_HEIGHT and abs(raise_amount) > 0.01:
		var preview_mat: Material = raise_mat if raise_amount > 0.0 else lower_mat
		var preview_y: float = floor_y + raise_amount

		for cell: Vector2i in sculpt_manager.drag_pattern:
			var cell_type: int = sculpt_manager.drag_pattern[cell]
			var grid_pos: Vector3 = Vector3(cell.x, 0, cell.y)
			var floor_pos: Vector3 = GlobalUtil.grid_to_world(grid_pos, gs)
			floor_pos.y = floor_y
			var preview_pos: Vector3 = floor_pos
			preview_pos.y = preview_y

			if cell_type == GlobalConstants.SculptCellType.SQUARE:
				add_mesh(cell_mesh, preview_mat, Transform3D(Basis(), preview_pos))
			else:
				add_mesh(tri_meshes[cell_type], preview_mat, Transform3D(Basis(), preview_pos))

			var height_line: PackedVector3Array = PackedVector3Array()
			height_line.append(floor_pos)
			height_line.append(preview_pos)
			add_lines(height_line, preview_mat, false)



func _draw_smart_fill_preview(gizmo_plugin: TileMapLayerGizmoPlugin) -> void:
	var sfm: SmartFillManager = gizmo_plugin.smart_fill_manager
	if not sfm or sfm.state == SmartFillManager.SmartFillState.IDLE:
		return

	var start_mat: Material = get_plugin().get_material("smart_fill_start", self)
	var gs: float = sfm.grid_size

	var marker_mesh: PlaneMesh = PlaneMesh.new()
	marker_mesh.size = Vector2(gs * GlobalConstants.SCULPT_CELL_GAP_FACTOR, gs * GlobalConstants.SCULPT_CELL_GAP_FACTOR)
	var marker_pos: Vector3 = sfm.start_world_pos
	marker_pos.y += GlobalConstants.SCULPT_GIZMO_FLOOR_OFFSET
	add_mesh(marker_mesh, start_mat, Transform3D(Basis(), marker_pos))

	if not sfm.preview_active:
		return

	var quad_verts: PackedVector3Array = sfm.get_preview_quad_vertices()
	if quad_verts.size() != 4:
		return

	var preview_mat: Material = get_plugin().get_material("smart_fill_preview", self)

	var v: PackedVector3Array = PackedVector3Array()
	## Offset slightly above surface to prevent z-fighting.
	var offset: Vector3 = Vector3(0, GlobalConstants.SCULPT_GIZMO_FLOOR_OFFSET, 0)
	var c0: Vector3 = quad_verts[0] + offset
	var c1: Vector3 = quad_verts[1] + offset
	var c2: Vector3 = quad_verts[2] + offset
	var c3: Vector3 = quad_verts[3] + offset
	v.append(c0); v.append(c1); v.append(c2)
	v.append(c0); v.append(c2); v.append(c3)
	v.append(c0); v.append(c2); v.append(c1)
	v.append(c0); v.append(c3); v.append(c2)

	var quad_arrays: Array = []
	quad_arrays.resize(Mesh.ARRAY_MAX)
	quad_arrays[Mesh.ARRAY_VERTEX] = v
	var quad_mesh: ArrayMesh = ArrayMesh.new()
	quad_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, quad_arrays)
	add_mesh(quad_mesh, preview_mat, Transform3D())

	if sfm._active_tilema3d_node and sfm._active_tilema3d_node.settings.smart_fill_ramp_sides:
		var side_verts: PackedVector3Array = PackedVector3Array()
		var surface_normal: Vector3 = sfm._get_surface_normal()
		var v0: Vector3 = quad_verts[0]
		var v1: Vector3 = quad_verts[1]
		var v2: Vector3 = quad_verts[2]
		var v3: Vector3 = quad_verts[3]

		var side_edges: Array[Array] = [
			[v0, v3],
			[v1, v2],
		]
		for side_edge: Array in side_edges:
			var edge_s: Vector3 = side_edge[0] as Vector3
			var edge_e: Vector3 = side_edge[1] as Vector3
			var hdiff: float = (edge_e - edge_s).dot(surface_normal)
			if absf(hdiff) < 0.01:
				continue
			var low_pt: Vector3 = edge_s if hdiff > 0.0 else edge_e
			var high_pt: Vector3 = edge_e if hdiff > 0.0 else edge_s
			var abs_h: float = absf(hdiff)
			var ground_h: Vector3 = high_pt - surface_normal * abs_h

			var ground_span: float = (ground_h - low_pt).length()
			var h_dist: float = ground_span / gs
			var v_dist: float = abs_h / gs
			var h_ceil: int = ceili(h_dist)
			var v_ceil: int = ceili(v_dist)
			var h_steps: int = h_ceil if (h_dist >= 0.75 and h_dist / float(h_ceil) >= 0.75) else maxi(1, floori(h_dist))
			var v_steps: int = v_ceil if (v_dist >= 0.75 and v_dist / float(v_ceil) >= 0.75) else maxi(1, floori(v_dist))
			if h_steps == 0 or v_steps == 0:
				continue
			var h_sv: Vector3 = (ground_h - low_pt) / float(h_steps)
			var v_step_size: float = abs_h / float(v_steps)
			var v_sv: Vector3 = surface_normal * v_step_size

			for col_idx: int in range(h_steps):
				var co: Vector3 = low_pt + h_sv * float(col_idx)
				var diag_left: float = abs_h * float(col_idx) / float(h_steps)
				var diag_right: float = abs_h * float(col_idx + 1) / float(h_steps)
				var full_rows: int = floori(diag_left / v_step_size)

				for row_idx: int in range(full_rows):
					var sbl: Vector3 = co + v_sv * float(row_idx)
					var sbr: Vector3 = co + h_sv + v_sv * float(row_idx)
					var str_v: Vector3 = co + h_sv + v_sv * float(row_idx + 1)
					var stl: Vector3 = co + v_sv * float(row_idx + 1)
					side_verts.append(sbl); side_verts.append(sbr); side_verts.append(str_v)
					side_verts.append(sbl); side_verts.append(str_v); side_verts.append(stl)
					side_verts.append(sbl); side_verts.append(str_v); side_verts.append(sbr)
					side_verts.append(sbl); side_verts.append(stl); side_verts.append(str_v)
				var row_top: float = float(full_rows) * v_step_size
				var tbl: Vector3 = co + surface_normal * row_top
				var tbr: Vector3 = co + h_sv + surface_normal * row_top
				var ttl: Vector3 = co + h_sv + surface_normal * diag_right
				side_verts.append(tbl); side_verts.append(tbr); side_verts.append(ttl)
				side_verts.append(tbl); side_verts.append(ttl); side_verts.append(tbr)
				if diag_left - row_top > 0.001:
					var gbl: Vector3 = co + surface_normal * row_top
					var gbr: Vector3 = co + h_sv + surface_normal * diag_right
					var gtl: Vector3 = co + surface_normal * diag_left
					side_verts.append(gbl); side_verts.append(gbr); side_verts.append(gtl)
					side_verts.append(gbl); side_verts.append(gtl); side_verts.append(gbr)

		if side_verts.size() > 0:
			var side_arrays: Array = []
			side_arrays.resize(Mesh.ARRAY_MAX)
			side_arrays[Mesh.ARRAY_VERTEX] = side_verts
			var side_mesh: ArrayMesh = ArrayMesh.new()
			side_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, side_arrays)
			add_mesh(side_mesh, preview_mat, Transform3D())


func _make_triangle_mesh(h: float, cell_type: int) -> ArrayMesh:
	var a: Vector3
	var b: Vector3
	var c: Vector3
	match cell_type:
		GlobalConstants.SculptCellType.TRI_NE:
			a = Vector3( h, 0, -h);  b = Vector3(-h, 0, -h);  c = Vector3( h, 0,  h)
		GlobalConstants.SculptCellType.TRI_NW:
			a = Vector3(-h, 0, -h);  b = Vector3( h, 0, -h);  c = Vector3(-h, 0,  h)
		GlobalConstants.SculptCellType.TRI_SE:
			a = Vector3( h, 0,  h);  b = Vector3(-h, 0,  h);  c = Vector3( h, 0, -h)
		_:
			a = Vector3(-h, 0,  h);  b = Vector3( h, 0,  h);  c = Vector3(-h, 0, -h)

	var v: PackedVector3Array = PackedVector3Array()
	v.append(a); v.append(b); v.append(c)
	v.append(a); v.append(c); v.append(b)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_arch_cap_gizmo_mesh(cell_size: float, mesh_rotation: int) -> ArrayMesh:
	var size: Vector2 = Vector2(cell_size, cell_size)
	var cap_mesh: ArrayMesh = TileMeshGenerator.create_arch_corner_cap_mesh(
		Rect2(0, 0, 1, 1), Vector2(1, 1), size,
		GlobalConstants.ARCH_DEFAULT_RADIUS_RATIO)
	if mesh_rotation == 0:
		return cap_mesh
	var angle: float = float(mesh_rotation) * PI * 0.5
	var rot_basis: Basis = Basis(Vector3.UP, angle)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arrays: Array = cap_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i: int in range(0, verts.size(), 3):
		var v0: Vector3 = rot_basis * verts[i]
		var v1: Vector3 = rot_basis * verts[i + 1]
		var v2: Vector3 = rot_basis * verts[i + 2]
		st.add_vertex(v0); st.add_vertex(v1); st.add_vertex(v2)
	return st.commit()
