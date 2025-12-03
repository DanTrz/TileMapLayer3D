class_name MeshBakeManager
extends RefCounted

## Centralized manager for all mesh baking operations
## Responsibility: Coordinate mesh baking workflows (alpha-aware, normal, streaming)
## This class extracts baking logic from the plugin to reduce bloat
##
## Usage:
##   var bake_result: Dictionary = MeshBakeManager.bake_to_static_mesh(tile_map_layer, bake_mode)
##   if bake_result.success:
##       var mesh_instance: MeshInstance3D = bake_result.mesh_instance

# ==============================================================================
# CONSTANTS
# ==============================================================================

enum BakeMode {
	NORMAL,          # Standard merge without alpha detection
	ALPHA_AWARE	,  # Custom alpha detection (excludes transparent pixels)	
	STREAMING,       # For large tile counts (10,000+)
}

# ==============================================================================
# MAIN BAKING INTERFACE
# ==============================================================================

## Main entry point for all baking operations
## Coordinates the baking workflow based on mode
##
## @param tile_map_layer: TileMapLayer3D node containing tiles to bake
## @param bake_mode: Which baking algorithm to use (NORMAL, ALPHA_AWARE, STREAMING)
## @param undo_redo: Optional EditorUndoRedoManager for editor integration
## @param parent_node: Parent node to add baked mesh to (for undo/redo)
## @returns: Dictionary with keys:
##   - success: bool - Whether bake succeeded
##   - mesh_instance: MeshInstance3D - The created mesh (if successful)
##   - error: String - Error message (if failed)
static func bake_to_static_mesh(
tile_map_node: TileMapLayer3D,
bake_mode: BakeMode,
undo_redo: EditorUndoRedoManager = null,
parent_node: Node = null,
add_to_scene: bool = true
) -> Dictionary:

	# Validate inputs
	if not tile_map_node:
		return {"success": false, "error": "No TileMapLayer3D provided"}

	if tile_map_node.saved_tiles.is_empty():
		return {"success": false, "error": "No tiles to bake"}

	# Execute bake based on mode
	var merge_result: Dictionary
	match bake_mode:
		BakeMode.ALPHA_AWARE:
			merge_result = _bake_alpha_aware(tile_map_node)
		BakeMode.STREAMING:
			merge_result = _bake_streaming(tile_map_node)
		_:  # BakeMode.NORMAL
			merge_result = _bake_normal(tile_map_node)

	# Check merge result
	if not merge_result.success:
		return merge_result

	# Create MeshInstance3D from result
	var mesh_instance: MeshInstance3D = _create_mesh_instance(
		merge_result.mesh,
		tile_map_node
	)

	# Add to scene with undo/redo if provided
	if add_to_scene:
		if undo_redo and parent_node:
			_add_to_scene_with_undo(mesh_instance, parent_node, tile_map_node, undo_redo)
		elif parent_node:
			parent_node.add_child(mesh_instance)
			mesh_instance.owner = parent_node.get_tree().edited_scene_root

	return {
		"success": true,
		"mesh_instance": mesh_instance,
		"merge_result": merge_result
	}

# ==============================================================================
# BAKING IMPLEMENTATIONS
# ==============================================================================

## Normal baking: Standard merge without alpha detection
static func _bake_normal(tile_map_layer: TileMapLayer3D) -> Dictionary:
	#print("🔨 Starting NORMAL bake for: ", tile_map_layer.name)
	var start_time: int = Time.get_ticks_msec()

	var merge_result: Dictionary = TileMeshMerger.merge_tiles_to_array_mesh(tile_map_layer)

	if merge_result.success:
		var elapsed: float = (Time.get_ticks_msec() - start_time) / 1000.0
		#print("Normal bake completed in %.2fs" % elapsed)
		pass

	return merge_result

## Alpha-aware baking: Custom alpha detection (excludes transparent pixels)
static func _bake_alpha_aware(tile_map_layer: TileMapLayer3D) -> Dictionary:
	#print("🔨 Starting ALPHA-AWARE bake for: ", tile_map_layer.name)
	var start_time: int = Time.get_ticks_msec()

	# Get atlas texture
	var atlas_texture: Texture2D = tile_map_layer.tileset_texture
	if not atlas_texture:
		return {"success": false, "error": "No tileset texture"}

	var atlas_size: Vector2 = atlas_texture.get_size()
	var grid_size: float = tile_map_layer.grid_size

	# Pre-allocate arrays
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()

	var tiles_processed: int = 0
	var total_vertices: int = 0

	# Process each tile
	for tile: TilePlacerData in tile_map_layer.saved_tiles:
		# Build transform using saved transform params for data persistency
		var transform: Transform3D = GlobalUtil.build_tile_transform(
			tile.grid_position,
			tile.orientation,
			tile.mesh_rotation,
			grid_size,
			tile.is_face_flipped,
			tile.spin_angle_rad,
			tile.tilt_angle_rad,
			tile.diagonal_scale,
			tile.tilt_offset_factor
		)

		#   Triangle tiles use standard geometry (no alpha detection)
		# Only square tiles benefit from alpha-aware mesh generation
		if tile.mesh_mode == GlobalConstants.MeshMode.FLAT_TRIANGULE:
			# Normalize UV rect using GlobalUtil (single source of truth)
			var uv_data: Dictionary = GlobalUtil.calculate_normalized_uv(tile.uv_rect, atlas_size)
			var uv_rect_normalized: Rect2 = Rect2(uv_data.uv_min, uv_data.uv_max - uv_data.uv_min)

			# Add standard triangle geometry using shared utility
			GlobalUtil.add_triangle_geometry(
				vertices, uvs, normals, indices,
				transform, uv_rect_normalized, grid_size
			)
			tiles_processed += 1
			total_vertices += 3
		else:
			# Generate alpha-aware geometry using BitMap API (for square tiles)
			var geom: Dictionary = AlphaMeshGenerator.generate_alpha_mesh(
				atlas_texture,
				tile.uv_rect,
				grid_size,
				0.1,  # alpha_threshold
				2.0   # epsilon (simplification)
			)

			if geom.success and geom.vertex_count > 0:
				# Add geometry to arrays
				var v_offset: int = vertices.size()

				for i: int in range(geom.vertices.size()):
					vertices.append(transform * geom.vertices[i])
					uvs.append(geom.uvs[i])
					normals.append(transform.basis * geom.normals[i])

				for idx: int in geom.indices:
					indices.append(v_offset + idx)

				tiles_processed += 1
				total_vertices += geom.vertex_count

	# Validate results
	if vertices.is_empty():
		return {"success": false, "error": "Alpha-aware merge resulted in 0 vertices"}

	# Create ArrayMesh using GlobalUtil
	var array_mesh: ArrayMesh = GlobalUtil.create_array_mesh_from_arrays(
		vertices, uvs, normals, indices,
		PackedFloat32Array(),  # Auto-generate tangents
		tile_map_layer.name + "_alpha_aware"
	)

	# Create material
	var material: StandardMaterial3D = GlobalUtil.create_baked_mesh_material(
		atlas_texture,
		tile_map_layer.texture_filter_mode,
		tile_map_layer.render_priority,
		true,  # enable_alpha
		true   # enable_toon_shading
	)

	array_mesh.surface_set_material(0, material)

	var elapsed: float = (Time.get_ticks_msec() - start_time) / 1000.0
	#print("Alpha-aware bake completed in %.2fs (%d tiles, %d vertices)" % [
	#	elapsed, tiles_processed, total_vertices
	#])

	return {
		"success": true,
		"mesh": array_mesh,
		"tile_count": tiles_processed,
		"vertex_count": total_vertices
	}

## Streaming baking: For large tile counts (10,000+)
static func _bake_streaming(tile_map_layer: TileMapLayer3D) -> Dictionary:
	#print("🔨 Starting STREAMING bake for: ", tile_map_layer.name)
	var start_time: int = Time.get_ticks_msec()

	# TODO: Add progress callback support if needed
	var merge_result: Dictionary = TileMeshMerger.merge_tiles_streaming(tile_map_layer)

	if merge_result.success:
		var elapsed: float = (Time.get_ticks_msec() - start_time) / 1000.0
		#print("Streaming bake completed in %.2fs" % elapsed)
		pass

	return merge_result

# ==============================================================================
# MESH INSTANCE CREATION
# ==============================================================================

## Creates MeshInstance3D from baked mesh
static func _create_mesh_instance(
	mesh: ArrayMesh,
	tile_map_layer: TileMapLayer3D
) -> MeshInstance3D:

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = tile_map_layer.name + "_Baked"
	mesh_instance.mesh = mesh
	mesh_instance.transform = tile_map_layer.transform

	return mesh_instance

## Adds mesh instance to scene with undo/redo support
static func _add_to_scene_with_undo(
	mesh_instance: MeshInstance3D,
	parent: Node,
	tile_map_layer: TileMapLayer3D,
	undo_redo: EditorUndoRedoManager
) -> void:

	undo_redo.create_action("Bake TileMapLayer3D to Static Mesh")

	# Add baked mesh
	undo_redo.add_do_method(parent, "add_child", mesh_instance)
	undo_redo.add_do_method(mesh_instance, "set_owner", parent.get_tree().edited_scene_root)
	undo_redo.add_do_property(mesh_instance, "name", mesh_instance.name)

	# Undo
	undo_redo.add_undo_method(parent, "remove_child", mesh_instance)

	undo_redo.commit_action()
