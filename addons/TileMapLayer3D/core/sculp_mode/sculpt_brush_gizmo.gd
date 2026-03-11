class_name SculptBrushGizmo
extends EditorNode3DGizmo

## Ring segments and floor offset live in GlobalConstants (SCULPT_RING_SEGMENTS, SCULPT_GIZMO_GlobalConstants.SCULPT_GIZMO_FLOOR_OFFSET).


func _redraw() -> void:
	## ALWAYS clear first — removes all geometry from previous frame.
	clear()

	## Reach the plugin that owns this gizmo. Cast to access sculpt_manager.
	var gizmo_plugin: SculptBrushGizmoPlugin = get_plugin() as SculptBrushGizmoPlugin
	if not gizmo_plugin:
		return

	## All state lives in SculptManager. We read it here, never store it.
	var sm: SculptManager = gizmo_plugin.sculpt_manager
	if not sm or not sm.is_active:
		## is_active is false when cursor is off-floor or sculpt mode is off.
		return

	## Fetch named materials registered in SculptBrushGizmoPlugin._init().
	var cell_mat: Material = get_plugin().get_material("brush_cell", self)
	var pattern_mat: Material = get_plugin().get_material("brush_pattern", self)
	var pattern_ready_mat: Material = get_plugin().get_material("brush_pattern_ready", self)
	var raise_mat: Material = get_plugin().get_material("brush_raise", self)
	var lower_mat: Material = get_plugin().get_material("brush_lower", self)

	var center: Vector3 = sm.brush_world_pos
	var gs: float = sm.grid_size
	var radius: int = sm.brush_radius
	var raise_amount: float = sm.get_raise_amount()

	## The floor baseline used for ALL height calculations.
	## When in SETTING_HEIGHT: frozen at drag_anchor so the floor doesn't chase mouse.
	var floor_y: float
	if sm.state == SculptManager.SculptState.SETTING_HEIGHT:
		floor_y = sm.drag_anchor_world_pos.y + GlobalConstants.SCULPT_GIZMO_FLOOR_OFFSET
	else:
		floor_y = center.y + GlobalConstants.SCULPT_GIZMO_FLOOR_OFFSET

	var cell_mesh: PlaneMesh = PlaneMesh.new()
	cell_mesh.size = Vector2(gs * GlobalConstants.SCULPT_CELL_GAP_FACTOR, gs * GlobalConstants.SCULPT_CELL_GAP_FACTOR)

	# Snap cursor to grid for ring center and cell iteration.
	var snap_grid: Vector3 = GlobalUtil.world_to_grid(center, gs)
	var snap_x: int = roundi(snap_grid.x)
	var snap_z: int = roundi(snap_grid.z)
	var ring_center: Vector3 = GlobalUtil.grid_to_world(Vector3(snap_x, 0, snap_z), gs)
	ring_center.y = floor_y

	#DRAW Main brush pattern 
	#Only IDLE and DRAWING — hidden in PATTERN_READY/SETTING_HEIGHT
	var show_live_brush: bool = (
		sm.state == SculptManager.SculptState.IDLE or
		sm.state == SculptManager.SculptState.DRAWING
	)
	if show_live_brush:
		for dz: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if dx * dx + dz * dz > radius * radius:
					continue
				var grid_pos: Vector3 = Vector3(snap_x + dx, 0, snap_z + dz)
				var cell_pos: Vector3 = GlobalUtil.grid_to_world(grid_pos, gs)
				cell_pos.y = floor_y
				add_mesh(cell_mesh, cell_mat, Transform3D(Basis(), cell_pos))

	# DRAW - Cumulative brush pattern (Drag Operation)
	var show_pattern: bool = not sm.drag_pattern.is_empty() and (
		sm.state == SculptManager.SculptState.DRAWING or
		sm.state == SculptManager.SculptState.PATTERN_READY or
		sm.state == SculptManager.SculptState.SETTING_HEIGHT
	)
	if show_pattern:
		var use_mat: Material
		if sm.state == SculptManager.SculptState.DRAWING:
			use_mat = pattern_mat
		elif sm.is_hovering_pattern:
			## Hover hint: brighter yellow = "click here"
			use_mat = raise_mat
		else:
			use_mat = pattern_ready_mat

		for cell: Vector2i in sm.drag_pattern:
			var grid_pos: Vector3 = Vector3(cell.x, 0, cell.y)
			var pattern_pos: Vector3 = GlobalUtil.grid_to_world(grid_pos, gs)
			pattern_pos.y = floor_y
			add_mesh(cell_mesh, use_mat, Transform3D(Basis(), pattern_pos))

	# DRAW - HEIGHT PREVIEW
	if sm.state == SculptManager.SculptState.SETTING_HEIGHT and abs(raise_amount) > 0.01:
		var preview_mat: Material = raise_mat if raise_amount > 0.0 else lower_mat
		var preview_y: float = floor_y + raise_amount

		for cell: Vector2i in sm.drag_pattern:
			var grid_pos: Vector3 = Vector3(cell.x, 0, cell.y)
			var floor_pos: Vector3 = GlobalUtil.grid_to_world(grid_pos, gs)
			floor_pos.y = floor_y
			var preview_pos: Vector3 = floor_pos
			preview_pos.y = preview_y

			## Floating quad at target height
			add_mesh(cell_mesh, preview_mat, Transform3D(Basis(), preview_pos))

			## Vertical line: floor → preview (shows the raise/lower delta)
			var height_line: PackedVector3Array = PackedVector3Array()
			height_line.append(floor_pos)
			height_line.append(preview_pos)
			add_lines(height_line, preview_mat, false)

		## Console volume report — debug builds only to avoid log spam in production.
		if OS.is_debug_build():
			var direction: String = "RAISE" if raise_amount > 0.0 else "LOWER"
			print("[Sculpt] Volume ", direction,
				" | world_units=", snapped(raise_amount, 0.01),
				" | screen_px=", snapped(sm.drag_delta_y, 1.0),
				" | brush_pos=", center,
				" | pattern_cells=", sm.drag_pattern.size(),
				" | radius=", radius)
