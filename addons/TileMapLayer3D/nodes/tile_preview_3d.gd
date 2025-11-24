@tool
class_name TilePreview3D
extends Node3D

## Visual preview/ghost of tile that will be placed 
## Shows where tile will appear and auto-rotates based on camera angle

@export var grid_size: float = GlobalConstants.DEFAULT_GRID_SIZE:
	set(value):
		if not Engine.is_editor_hint(): return
		if value > 0.0:
			grid_size = value
			_update_preview_mesh()

@export var preview_color: Color = GlobalConstants.DEFAULT_PREVIEW_COLOR:
	set(value):
		if not Engine.is_editor_hint(): return
		preview_color = value
		_update_material()

@export var tile_model: Node3D = null  # Reference to TileMapLayer3D for tilt offset access

# Single-tile preview components
var _preview_mesh: MeshInstance3D = null
var _preview_material: ShaderMaterial = null
var _grid_indicator: MeshInstance3D = null  # Small cube at grid position for clarity

# Multi-tile preview pool (Phase 3)
var _preview_instances: Array[MeshInstance3D] = []  # Pre-created pool of preview meshes
var _preview_indicators: Array[MeshInstance3D] = []  # Pre-created pool of grid indicators
var _is_multi_preview_active: bool = false  # Track if showing multiple tiles

# Current preview state
var preview_visible: bool = false
var preview_grid_position: Vector3 = Vector3.ZERO  # Supports fractional positions
var preview_orientation: int = 0  # TileOrientation
var preview_uv_rect: Rect2 = Rect2()
var preview_mesh_rotation: int = 0  # Mesh rotation: 0-3 (0°, 90°, 180°, 270°)
var preview_is_face_flipped: bool = false  # Face flip state (F key)
var preview_texture: Texture2D = null
var texture_filter_mode: int = GlobalConstants.DEFAULT_TEXTURE_FILTER
var current_mesh_mode: GlobalConstants.MeshMode = GlobalConstants.MeshMode.MESH_SQUARE

#  Cache last preview state to avoid unnecessary mesh rebuilds
var _cached_uv_rect: Rect2 = Rect2()
var _cached_orientation: int = -1
var _cached_rotation: int = -1
var _cached_texture: Texture2D = null
var _cached_mesh_mode: GlobalConstants.MeshMode = -1  # Cache mesh mode too
var _cached_flip: bool = false  # Cache flip state (F key)

func _ready() -> void:
	if not Engine.is_editor_hint(): return
	_create_preview_mesh()
	_create_grid_indicator()
	_create_preview_pool()

## Creates the preview mesh instance
func _create_preview_mesh() -> void:
	_preview_mesh = MeshInstance3D.new()
	_preview_mesh.name = "PreviewMesh"
	_preview_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_preview_mesh)
	# DO NOT set owner - preview is runtime-only

## Creates a small indicator at the grid position for visual clarity
func _create_grid_indicator() -> void:
	_grid_indicator = MeshInstance3D.new()
	_grid_indicator.name = "GridIndicator"
	_grid_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Small bright cube at grid position
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = GlobalConstants.PREVIEW_GRID_INDICATOR_SIZE
	_grid_indicator.mesh = box_mesh

	# Bright unshaded material so it's always visible
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = GlobalConstants.PREVIEW_GRID_INDICATOR_COLOR  # Bright yellow/orange
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid_indicator.material_override = material

	add_child(_grid_indicator)
	_grid_indicator.visible = false
	# DO NOT set owner - indicator is runtime-only

## Updates the preview to show a tile at a position with orientation
func update_preview(
	grid_pos: Vector3,
	orientation: int,
	uv_rect: Rect2,
	texture: Texture2D,
	mesh_rotation: int = 0,
	is_face_flipped: bool = false,
	show: bool = true
) -> void:
	preview_grid_position = grid_pos
	preview_orientation = orientation
	preview_uv_rect = uv_rect
	preview_mesh_rotation = mesh_rotation
	preview_is_face_flipped = is_face_flipped
	preview_texture = texture
	preview_visible = show

	if not show:
		hide_preview()
		return

	# UNIFIED TRANSFORM: Use same method as actual tile placement
	var transform: Transform3D = GlobalUtil.build_tile_transform(
		grid_pos, orientation, mesh_rotation, grid_size, tile_model, is_face_flipped
	)

	# Extract position (includes tilt offset for tilted orientations)
	#OLD code
	position = transform.origin
	basis = Basis.IDENTITY

	#  Only rebuild mesh/material if something actually changed
	var needs_mesh_rebuild: bool = (
		_cached_uv_rect != uv_rect or
		_cached_orientation != orientation or
		_cached_rotation != mesh_rotation or
		_cached_texture != texture or
		_cached_mesh_mode != current_mesh_mode or
		_cached_flip != is_face_flipped
	)

	if needs_mesh_rebuild:
		_update_preview_mesh()
		_update_material()

		# Update cache
		_cached_uv_rect = uv_rect
		_cached_orientation = orientation
		_cached_rotation = mesh_rotation
		_cached_texture = texture
		_cached_mesh_mode = current_mesh_mode
		_cached_flip = is_face_flipped

	# Show both preview and grid indicator
	_preview_mesh.visible = true
	if _grid_indicator:
		_grid_indicator.visible = true
		
## Hides the preview
func hide_preview() -> void:
	preview_visible = false
	if _preview_mesh:
		_preview_mesh.visible = false
	if _grid_indicator:
		_grid_indicator.visible = false

	# Also hide multi-preview instances
	_hide_all_preview_instances()

## Creates the preview pool for multi-tile selection (Phase 3)
func _create_preview_pool() -> void:
	# Pre-create pool of MeshInstance3D nodes for multi-preview
	for i in range(GlobalConstants.PREVIEW_POOL_SIZE):
		# Create preview mesh
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.name = "MultiPreviewMesh_%d" % i
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.visible = false
		add_child(mesh_instance)
		_preview_instances.append(mesh_instance)

		# Create grid indicator for this preview
		var indicator: MeshInstance3D = MeshInstance3D.new()
		indicator.name = "MultiPreviewIndicator_%d" % i
		indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = GlobalConstants.PREVIEW_GRID_INDICATOR_SIZE
		indicator.mesh = box_mesh

		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = GlobalConstants.PREVIEW_GRID_INDICATOR_COLOR
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		indicator.material_override = material

		indicator.visible = false
		add_child(indicator)
		_preview_indicators.append(indicator)

## Hides all preview instances in the pool
func _hide_all_preview_instances() -> void:
	for instance in _preview_instances:
		instance.visible = false
	for indicator in _preview_indicators:
		indicator.visible = false
	_is_multi_preview_active = false

## Updates the preview to show multiple tiles (Phase 3)
func update_multi_preview(
	anchor_grid_pos: Vector3,
	selected_tiles: Array[Rect2],
	orientation: int,
	mesh_rotation: int = 0,
	texture: Texture2D = null,
	is_face_flipped: bool = false,
	show: bool = true
) -> void:
	# Hide single-tile preview when showing multi-preview
	if _preview_mesh:
		_preview_mesh.visible = false
	if _grid_indicator:
		_grid_indicator.visible = false

	if not show or selected_tiles.is_empty():
		_hide_all_preview_instances()
		return

	_is_multi_preview_active = true

	# UNIFIED TRANSFORM: Use same method as actual tile placement
	var transform: Transform3D = GlobalUtil.build_tile_transform(
		anchor_grid_pos, orientation, mesh_rotation, grid_size, tile_model, is_face_flipped
	)

	# Extract position and basis
	position = transform.origin
	basis = transform.basis

	# Calculate tile offsets relative to anchor
	var first_tile_rect: Rect2 = selected_tiles[0]
	var first_tile_pixel_pos: Vector2 = first_tile_rect.position

	# Get texture size for calculations
	var active_texture: Texture2D = texture if texture else preview_texture
	if not active_texture:
		_hide_all_preview_instances()
		return

	var atlas_size: Vector2 = active_texture.get_size()

	# Show preview for each selected tile
	var tile_count: int = min(selected_tiles.size(), GlobalConstants.PREVIEW_POOL_SIZE)
	for i in range(tile_count):
		var tile_uv_rect: Rect2 = selected_tiles[i]
		var tile_pixel_pos: Vector2 = tile_uv_rect.position

		# Calculate pixel offset from anchor tile
		var pixel_offset: Vector2 = tile_pixel_pos - first_tile_pixel_pos

		# Convert pixel offset to grid offset
		var tile_pixel_size: Vector2 = first_tile_rect.size
		var grid_offset: Vector2 = pixel_offset / tile_pixel_size

		# Calculate 3D offset based on orientation
		var offset_3d: Vector3 = _calculate_3d_offset_for_orientation(grid_offset, orientation)

		# Update this preview instance
		_update_single_preview_instance(
			i,
			offset_3d,
			orientation,
			tile_uv_rect,
			active_texture,
			mesh_rotation
		)

	# Hide remaining unused instances
	for i in range(tile_count, GlobalConstants.PREVIEW_POOL_SIZE):
		_preview_instances[i].visible = false
		_preview_indicators[i].visible = false

## Calculates 3D offset from 2D grid offset based on orientation
func _calculate_3d_offset_for_orientation(grid_offset: Vector2, orientation: int) -> Vector3:
	# For ALL orientations, the offset is the same in local space
	# The parent's basis rotation handles the actual orientation
	return Vector3(grid_offset.x, 0, grid_offset.y)

## Updates a single preview instance from the pool - USES TileMeshGenerator
func _update_single_preview_instance(
	index: int,
	local_offset: Vector3,
	orientation: int,
	uv_rect: Rect2,
	texture: Texture2D,
	mesh_rotation: int
) -> void:
	if index < 0 or index >= _preview_instances.size():
		return

	var mesh_instance: MeshInstance3D = _preview_instances[index]
	var indicator: MeshInstance3D = _preview_indicators[index]

	# Convert grid offset to world offset
	var local_world_offset: Vector3 = local_offset * grid_size
	mesh_instance.position = local_world_offset
	indicator.position = local_world_offset

	# Use PREVIEW versions that include UV data in COLOR!
	var mesh: ArrayMesh
	if current_mesh_mode == GlobalConstants.MeshMode.MESH_SQUARE:
		mesh = TileMeshGenerator.create_preview_tile_quad(
			uv_rect,
			texture.get_size(),
			Vector2(grid_size, grid_size)
		)
	else:  # MESH_TRIANGLE
		mesh = TileMeshGenerator.create_preview_tile_triangle(
			uv_rect,
			texture.get_size(),
			Vector2(grid_size, grid_size)
		)
	
	mesh_instance.mesh = mesh

	# Keep instances at identity basis (parent handles rotation)
	mesh_instance.basis = Basis.IDENTITY

	# Apply material
	var material: ShaderMaterial = GlobalUtil.create_tile_material(texture, texture_filter_mode, 99)
	material.render_priority = 99
	mesh_instance.material_override = material

	# Scale indicator
	var scale_factor: float = grid_size / GlobalConstants.DEFAULT_GRID_SIZE
	(indicator.mesh as BoxMesh).size = GlobalConstants.PREVIEW_GRID_INDICATOR_SIZE * scale_factor

	# Show both
	mesh_instance.visible = true
	indicator.visible = true

## Updates the preview mesh based on current orientation - USES TileMeshGenerator
func _update_preview_mesh() -> void:
	if not _preview_mesh or not preview_texture:
		return

	# Use PREVIEW versions that include UV data in COLOR!
	var mesh: ArrayMesh
	if current_mesh_mode == GlobalConstants.MeshMode.MESH_SQUARE:
		mesh = TileMeshGenerator.create_preview_tile_quad(
			preview_uv_rect,
			preview_texture.get_size(),
			Vector2(grid_size, grid_size)
		)
	else:  # MESH_TRIANGLE
		mesh = TileMeshGenerator.create_preview_tile_triangle(
			preview_uv_rect,
			preview_texture.get_size(),
			Vector2(grid_size, grid_size)
		)
	
	_preview_mesh.mesh = mesh

	# Apply rotation, scaling, and flip
	_preview_mesh.basis = GlobalUtil.build_tile_basis(preview_orientation, preview_mesh_rotation, preview_is_face_flipped)

	# Scale grid indicator
	if _grid_indicator and _grid_indicator.mesh:
		var scale_factor: float = grid_size / GlobalConstants.DEFAULT_GRID_SIZE
		(_grid_indicator.mesh as BoxMesh).size = GlobalConstants.PREVIEW_GRID_INDICATOR_SIZE * scale_factor

## Updates the preview material
func _update_material() -> void:
	if not _preview_mesh or not preview_texture:
		return

	# Create or recreate material using GlobalUtil
	_preview_material = GlobalUtil.create_tile_material(preview_texture, texture_filter_mode, 99)
	_preview_material.render_priority = 99  # Force to show in front
	_preview_mesh.material_override = _preview_material
