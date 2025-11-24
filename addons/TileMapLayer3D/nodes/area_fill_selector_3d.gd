@tool
class_name AreaFillSelector3D
extends Node3D

## Area Fill Selection Visualizer for TileMapLayer3D
##
## Provides visual feedback during Shift+Drag area selection for paint/erase fill operations.
## Shows:
## - Cyan selection box outlining the area bounds
## - Grid lines within the selection showing individual cells
##
## Usage Pattern (Signal UP, Call DOWN):
## 1. Plugin calls start_selection() when Shift+Click pressed
## 2. Plugin calls update_selection() during drag
## 3. AreaFillSelector emits selection_updated signal
## 4. Plugin calls complete_selection() on mouse release
## 5. AreaFillSelector emits selection_completed signal with bounds
##
## Responsibility: ONLY visual feedback - does NOT handle placement/erase logic

# ==============================================================================
# SIGNALS
# ==============================================================================

## Emitted when area selection starts (Shift+Click)
signal selection_started(start_pos: Vector3, orientation: int)

## Emitted during drag when selection area updates
signal selection_updated(start_pos: Vector3, end_pos: Vector3, orientation: int)

## Emitted when selection completes (mouse release)
## Returns min/max bounds for placement/erase logic
signal selection_completed(min_pos: Vector3, max_pos: Vector3, orientation: int)

## Emitted when selection is cancelled (Escape key or invalid drag)
signal selection_cancelled()

# ==============================================================================
# EXPORTED PROPERTIES
# ==============================================================================

@export_category("Selection Box")

## Grid size for positioning (synced with TileMapLayer3D)
@export var grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE:
	set(value):
		if grid_size != value:
			grid_size = value
			if not Engine.is_editor_hint(): return
			_update_visuals()

## Selection box color (semi-transparent cyan)
@export var box_color: Color = GlobalConstants.AREA_FILL_BOX_COLOR:
	set(value):
		if box_color != value:
			box_color = value
			if not Engine.is_editor_hint(): return
			_update_box_material()

## Grid line color within selection
@export var grid_line_color: Color = GlobalConstants.AREA_FILL_GRID_LINE_COLOR:
	set(value):
		if grid_line_color != value:
			grid_line_color = value
			if not Engine.is_editor_hint(): return
			_update_grid_material()

# ==============================================================================
# PRIVATE STATE
# ==============================================================================

## Current selection state
var is_selecting: bool = false

## Starting grid position (anchor point)
var start_grid_pos: Vector3 = Vector3.ZERO

## Current end grid position (drag point)
var end_grid_pos: Vector3 = Vector3.ZERO

## Active orientation (0-5 for floor/ceiling/walls)
var current_orientation: int = 0

## Active plane normal (UP/RIGHT/FORWARD)
var current_plane: Vector3 = Vector3.UP

## Selection box mesh instance
var _box_mesh: MeshInstance3D = null

## Grid lines mesh instance
var _grid_lines: MeshInstance3D = null

# ==============================================================================
# LIFECYCLE
# ==============================================================================

func _ready() -> void:
	if not Engine.is_editor_hint(): return

	_create_selection_box()
	_create_grid_lines()

	# Start hidden
	visible = false

# ==============================================================================
# PUBLIC API
# ==============================================================================

## Starts area selection at given grid position
## Called by plugin on Shift+Click
func start_selection(grid_pos: Vector3, orientation: int, plane: Vector3) -> void:
	if not Engine.is_editor_hint(): return

	is_selecting = true
	start_grid_pos = grid_pos
	end_grid_pos = grid_pos
	current_orientation = orientation
	current_plane = plane

	visible = true
	_update_visuals()

	selection_started.emit(grid_pos, orientation)

## Updates selection end point during drag
## Called by plugin during mouse movement
func update_selection(new_end_pos: Vector3) -> void:
	if not Engine.is_editor_hint(): return
	if not is_selecting:
		return

	end_grid_pos = new_end_pos
	_update_visuals()

	selection_updated.emit(start_grid_pos, end_grid_pos, current_orientation)

## Completes selection and returns bounds
## Called by plugin on mouse release
func complete_selection() -> Dictionary:
	if not Engine.is_editor_hint(): return {}
	if not is_selecting:
		return {}

	# Calculate min/max bounds
	var min_pos: Vector3 = Vector3(
		min(start_grid_pos.x, end_grid_pos.x),
		min(start_grid_pos.y, end_grid_pos.y),
		min(start_grid_pos.z, end_grid_pos.z)
	)
	var max_pos: Vector3 = Vector3(
		max(start_grid_pos.x, end_grid_pos.x),
		max(start_grid_pos.y, end_grid_pos.y),
		max(start_grid_pos.z, end_grid_pos.z)
	)

	# Check minimum size threshold
	var size: Vector3 = max_pos - min_pos
	if size.x < GlobalConstants.MIN_AREA_FILL_SIZE.x and \
	   size.y < GlobalConstants.MIN_AREA_FILL_SIZE.y and \
	   size.z < GlobalConstants.MIN_AREA_FILL_SIZE.z:
		# Selection too small - treat as single tile
		cancel_selection()
		return {}

	is_selecting = false
	visible = false

	var result: Dictionary = {
		"min_pos": min_pos,
		"max_pos": max_pos,
		"orientation": current_orientation
	}

	selection_completed.emit(min_pos, max_pos, current_orientation)

	return result

## Cancels current selection (Escape key or invalid drag)
func cancel_selection() -> void:
	if not Engine.is_editor_hint(): return

	is_selecting = false
	visible = false

	selection_cancelled.emit()

# ==============================================================================
# PRIVATE METHODS - Visual Creation
# ==============================================================================

## Creates the selection box mesh (cyan outline)
func _create_selection_box() -> void:
	if not Engine.is_editor_hint(): return

	_box_mesh = MeshInstance3D.new()
	_box_mesh.name = "SelectionBox"
	_box_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Create box mesh
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(grid_size, grid_size, grid_size)
	_box_mesh.mesh = box

	# Apply material
	_box_mesh.material_override = GlobalUtil.create_area_selection_material()

	add_child(_box_mesh)
	# Don't set owner - editor-only visualization, not saved

## Creates grid line visualization within selection
func _create_grid_lines() -> void:
	if not Engine.is_editor_hint(): return

	_grid_lines = MeshInstance3D.new()
	_grid_lines.name = "GridLines"
	_grid_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Material for grid lines (brighter cyan)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = grid_line_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.render_priority = 11  # Above selection box
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_grid_lines.material_override = material

	add_child(_grid_lines)
	# Don't set owner - editor-only visualization, not saved

# ==============================================================================
# PRIVATE METHODS - Visual Updates
# ==============================================================================

## Updates all visuals based on current selection bounds
func _update_visuals() -> void:
	if not Engine.is_editor_hint(): return
	if not _box_mesh or not _grid_lines:
		return

	# Calculate selection bounds
	var min_pos: Vector3 = Vector3(
		min(start_grid_pos.x, end_grid_pos.x),
		min(start_grid_pos.y, end_grid_pos.y),
		min(start_grid_pos.z, end_grid_pos.z)
	)
	var max_pos: Vector3 = Vector3(
		max(start_grid_pos.x, end_grid_pos.x),
		max(start_grid_pos.y, end_grid_pos.y),
		max(start_grid_pos.z, end_grid_pos.z)
	)

	# Calculate center and size in grid space
	var center_grid: Vector3 = (min_pos + max_pos) / 2.0
	var size_grid: Vector3 = max_pos - min_pos + Vector3.ONE  # +1 to include both endpoints

	# Convert to world space
	var center_world: Vector3 = GlobalUtil.grid_to_world(center_grid, grid_size)
	var size_world: Vector3 = size_grid * grid_size

	# Update selection box
	_update_box(center_world, size_world)

	# Update grid lines
	_update_grid(min_pos, max_pos)

## Updates selection box mesh position and scale
func _update_box(center: Vector3, size: Vector3) -> void:
	if not Engine.is_editor_hint(): return
	if not _box_mesh:
		return

	_box_mesh.position = center

	# Scale box to match selection area
	var box_mesh_data: BoxMesh = _box_mesh.mesh as BoxMesh
	if box_mesh_data:
		box_mesh_data.size = size

## Updates grid lines within selection area
func _update_grid(min_grid: Vector3, max_grid: Vector3) -> void:
	if not Engine.is_editor_hint(): return
	if not _grid_lines:
		return

	# Calculate grid cell count in selection
	var cell_count: Vector3i = Vector3i(
		int(max_grid.x - min_grid.x) + 1,
		int(max_grid.y - min_grid.y) + 1,
		int(max_grid.z - min_grid.z) + 1
	)

	# For now, skip grid line rendering (can add later for polish)
	# Focus on getting box visualization working first
	_grid_lines.visible = false

## Updates box material color
func _update_box_material() -> void:
	if not Engine.is_editor_hint(): return
	if not _box_mesh:
		return

	var material: StandardMaterial3D = _box_mesh.material_override as StandardMaterial3D
	if material:
		material.albedo_color = box_color

## Updates grid line material color
func _update_grid_material() -> void:
	if not Engine.is_editor_hint(): return
	if not _grid_lines:
		return

	var material: StandardMaterial3D = _grid_lines.material_override as StandardMaterial3D
	if material:
		material.albedo_color = grid_line_color
