@tool
class_name DebugInfoGenerator
extends RefCounted
## Generates debug information for TileMapLayer3D nodes.
## Extracted from TileMapLayer3D_plugin.gd to reduce plugin bloat.
##
## Usage:
##   DebugInfoGenerator.print_report(tile_map3d, placement_manager)


## Prints debug information about the TileMapLayer3D node to the console.
## Output can be copied from Godot's Output panel.
## @param tile_map3d: The TileMapLayer3D node to analyze
## @param placement_manager: The TilePlacementManager instance
static func print_report(tile_map3d: TileMapLayer3D, placement_manager: TilePlacementManager) -> void:
	if not tile_map3d:
		push_warning("DebugInfoGenerator: No TileMapLayer3D provided")
		return

	var info: String = generate_report(tile_map3d, placement_manager)
	print(info)


## Generates a debug report string for the TileMapLayer3D node.
## @param tile_map3d: The TileMapLayer3D node to analyze
## @param placement_manager: The TilePlacementManager instance
## @return: A formatted string containing debug information
static func generate_report(tile_map3d: TileMapLayer3D, placement_manager: TilePlacementManager) -> String:
	if not tile_map3d:
		return "ERROR: No TileMapLayer3D provided"

	var info: String = "\n"
	info += "═══════════════════════════════════════════════\n"
	info += "   TileMapLayer3D Debug Info\n"
	info += "═══════════════════════════════════════════════\n\n"

	# Basic Info
	info += "   Node: %s\n" % tile_map3d.name
	info += "   Grid Size: %s\n" % tile_map3d.grid_size
	info += "   Tileset: %s\n" % (tile_map3d.tileset_texture.resource_path if tile_map3d.tileset_texture else "None")
	info += "\n"

	# Tile counts summary
	info += "TILE COUNTS:\n"
	info += "   Saved Tiles: %d\n" % tile_map3d.get_tile_count()
	info += "   Tile Lookup Entries: %d\n" % tile_map3d._tile_lookup.size()

	# Runtime chunks summary
	var total_chunks: int = tile_map3d._quad_chunks.size() + tile_map3d._triangle_chunks.size() + tile_map3d._box_chunks.size() + tile_map3d._prism_chunks.size()
	info += "   Total Chunks: %d (Square: %d, Triangle: %d, Box: %d, Prism: %d)\n" % [
		total_chunks,
		tile_map3d._quad_chunks.size(),
		tile_map3d._triangle_chunks.size(),
		tile_map3d._box_chunks.size(),
		tile_map3d._prism_chunks.size()
	]
	info += "\n"

	# Check for issues
	var total_visible_tiles: int = 0
	var total_capacity: int = 0
	info += "CHUNK DETAILS:\n"

	# Square chunks
	if tile_map3d._quad_chunks.size() > 0:
		info += "  SQUARE CHUNKS:\n"
		for i in range(tile_map3d._quad_chunks.size()):
			var chunk: SquareTileChunk = tile_map3d._quad_chunks[i]
			var visible: int = chunk.multimesh.visible_instance_count
			var capacity: int = chunk.multimesh.instance_count
			total_visible_tiles += visible
			total_capacity += capacity

			var usage_percent: float = (float(visible) / float(capacity)) * GlobalConstants.PERCENT_MULTIPLIER
			info += "    Square Chunk %d: %d/%d tiles (%.1f%% full)\n" % [i, visible, capacity, usage_percent]

			# Warn if chunk is nearly full
			if usage_percent > GlobalConstants.CHUNK_WARNING_THRESHOLD:
				info += "      WARNING: Chunk nearly full!\n"

	# Triangle chunks
	if tile_map3d._triangle_chunks.size() > 0:
		info += "  TRIANGLE CHUNKS:\n"
		for i in range(tile_map3d._triangle_chunks.size()):
			var chunk: TriangleTileChunk = tile_map3d._triangle_chunks[i]
			var visible: int = chunk.multimesh.visible_instance_count
			var capacity: int = chunk.multimesh.instance_count
			total_visible_tiles += visible
			total_capacity += capacity

			var usage_percent: float = (float(visible) / float(capacity)) * GlobalConstants.PERCENT_MULTIPLIER
			info += "    Triangle Chunk %d: %d/%d tiles (%.1f%% full)\n" % [i, visible, capacity, usage_percent]

			if usage_percent > GlobalConstants.CHUNK_WARNING_THRESHOLD:
				info += "      WARNING: Chunk nearly full!\n"

	# Box chunks
	if tile_map3d._box_chunks.size() > 0:
		info += "  BOX CHUNKS:\n"
		for i in range(tile_map3d._box_chunks.size()):
			var chunk: BoxTileChunk = tile_map3d._box_chunks[i]
			var visible: int = chunk.multimesh.visible_instance_count
			var capacity: int = chunk.multimesh.instance_count
			total_visible_tiles += visible
			total_capacity += capacity

			var usage_percent: float = (float(visible) / float(capacity)) * GlobalConstants.PERCENT_MULTIPLIER
			info += "    Box Chunk %d: %d/%d tiles (%.1f%% full)\n" % [i, visible, capacity, usage_percent]

			if usage_percent > GlobalConstants.CHUNK_WARNING_THRESHOLD:
				info += "      WARNING: Chunk nearly full!\n"

	# Prism chunks
	if tile_map3d._prism_chunks.size() > 0:
		info += "  PRISM CHUNKS:\n"
		for i in range(tile_map3d._prism_chunks.size()):
			var chunk: PrismTileChunk = tile_map3d._prism_chunks[i]
			var visible: int = chunk.multimesh.visible_instance_count
			var capacity: int = chunk.multimesh.instance_count
			total_visible_tiles += visible
			total_capacity += capacity

			var usage_percent: float = (float(visible) / float(capacity)) * GlobalConstants.PERCENT_MULTIPLIER
			info += "    Prism Chunk %d: %d/%d tiles (%.1f%% full)\n" % [i, visible, capacity, usage_percent]

			if usage_percent > GlobalConstants.CHUNK_WARNING_THRESHOLD:
				info += "      WARNING: Chunk nearly full!\n"

	info += "   TOTAL: %d tiles across %d chunks\n" % [total_visible_tiles, total_chunks]
	info += "   Total Capacity: %d tiles\n" % total_capacity
	info += "\n"

	# Scan for rogue MeshInstance3D nodes (shouldn't exist!)
	info += "SCENE TREE SCAN:\n"

	var counts: Dictionary = _count_node_types_recursive(tile_map3d)
	var mesh_instance_count: int = counts.get("mesh", 0)
	var multimesh_instance_count: int = counts.get("multimesh", 0)
	var cursor_count: int = counts.get("cursor", 0)
	var total_children: int = counts.get("total", 0)
	var cursor_mesh_count: int = counts.get("cursor_meshes", 0)

	info += "   Total Children: %d\n" % total_children
	info += "   MultiMeshInstance3D: %d (expected: %d)\n" % [multimesh_instance_count, total_chunks]
	info += "   TileCursor3D: %d (expected: 0 or 1)\n" % cursor_count
	info += "   MeshInstance3D: %d\n" % mesh_instance_count

	# Break down MeshInstance3D sources
	if cursor_count > 0:
		info += "      └─ Cursor visuals: %d (center + 3 axes)\n" % cursor_mesh_count
	var non_cursor_meshes: int = mesh_instance_count - cursor_mesh_count
	if non_cursor_meshes > 0:
		info += "      └─ Other MeshInstance3D: %d\n" % non_cursor_meshes

	# Check for issues
	if cursor_count > 1:
		info += "       WARNING: Found %d cursors (should be 0 or 1)\n" % cursor_count

	if multimesh_instance_count != total_chunks:
		info += "       WARNING: MultiMesh count mismatch!\n"
		info += "         Expected %d, found %d\n" % [total_chunks, multimesh_instance_count]

	# Only warn about non-cursor MeshInstance3D nodes
	if non_cursor_meshes > 0:
		info += "       WARNING: Found %d non-cursor MeshInstance3D nodes!\n" % non_cursor_meshes
		info += "         Tiles should use MultiMesh, not individual MeshInstance3D.\n"

		# List all non-cursor MeshInstance3D nodes with details
		var non_cursor_list: Array = counts.get("non_cursor_mesh_details", [])
		for mesh_info in non_cursor_list:
			info += "         • '%s' (type: %s, parent: '%s')\n" % [mesh_info.name, mesh_info.type, mesh_info.parent]

	info += "\n"

	# Placement Manager State
	info += "PLACEMENT MANAGER:\n"
	if placement_manager:
		info += "   Tracked Tiles: %d\n" % placement_manager._placement_data.size()
		var mode_name: String = GlobalConstants.PLACEMENT_MODE_NAMES[placement_manager.placement_mode]
		info += "   Mode: %s\n" % mode_name
	else:
		info += "   (Placement manager not available)\n"



	var orientation_name: String = GlobalUtil.TileOrientation.keys()[GlobalPlaneDetector.current_tile_orientation_18d]
	info += "   Current Orientation: %s (%d)\n" % [orientation_name, GlobalPlaneDetector.current_tile_orientation_18d]

	var mesh_mode_name: String = "Unknown"
	match tile_map3d.current_mesh_mode:
		GlobalConstants.MeshMode.FLAT_SQUARE:
			mesh_mode_name = "Square"
		GlobalConstants.MeshMode.FLAT_TRIANGULE:
			mesh_mode_name = "Triangle"
		GlobalConstants.MeshMode.BOX_MESH:
			mesh_mode_name = "Box"
		GlobalConstants.MeshMode.PRISM_MESH:
			mesh_mode_name = "Prism"
	info += "   Current Mesh Mode: %s (%d)\n" % [mesh_mode_name, tile_map3d.current_mesh_mode]

	# Data consistency checks
	info += "\n"
	info += "DATA CONSISTENCY:\n"
	var saved_count: int = tile_map3d.get_tile_count()
	var tracked_count: int = placement_manager._placement_data.size() if placement_manager else 0
	var visible_count: int = total_visible_tiles

	info += "   Saved Tiles: %d\n" % saved_count
	info += "   Tracked Tiles: %d\n" % tracked_count
	info += "   Visible Tiles: %d\n" % visible_count

	if saved_count != tracked_count:
		info += "       WARNING: Saved/Tracked mismatch! (%d vs %d)\n" % [saved_count, tracked_count]

	if saved_count != visible_count:
		info += "       WARNING: Saved/Visible mismatch! (%d vs %d)\n" % [saved_count, visible_count]

	if saved_count == tracked_count and saved_count == visible_count:
		info += "       All counts match!\n"

	# MESH_MODE INTEGRITY CHECK - Detects mesh mode conversion bug
	info += "\n"
	info += "MESH_MODE INTEGRITY CHECK:\n"

	# Count mesh_mode distribution in saved tiles (columnar storage)
	var saved_squares: int = 0
	var saved_triangles: int = 0
	var saved_boxes: int = 0
	var saved_prisms: int = 0
	for i in range(tile_map3d.get_tile_count()):
		var tile_data: TilePlacerData = tile_map3d.get_tile_at(i)
		match tile_data.mesh_mode:
			GlobalConstants.MeshMode.FLAT_SQUARE:
				saved_squares += 1
			GlobalConstants.MeshMode.FLAT_TRIANGULE:
				saved_triangles += 1
			GlobalConstants.MeshMode.BOX_MESH:
				saved_boxes += 1
			GlobalConstants.MeshMode.PRISM_MESH:
				saved_prisms += 1

	# Count mesh_mode distribution in _tile_lookup (TileRefs)
	var lookup_squares: int = 0
	var lookup_triangles: int = 0
	var lookup_boxes: int = 0
	var lookup_prisms: int = 0
	for tile_key in tile_map3d._tile_lookup.keys():
		var tile_ref: TileMapLayer3D.TileRef = tile_map3d._tile_lookup[tile_key]
		match tile_ref.mesh_mode:
			GlobalConstants.MeshMode.FLAT_SQUARE:
				lookup_squares += 1
			GlobalConstants.MeshMode.FLAT_TRIANGULE:
				lookup_triangles += 1
			GlobalConstants.MeshMode.BOX_MESH:
				lookup_boxes += 1
			GlobalConstants.MeshMode.PRISM_MESH:
				lookup_prisms += 1

	# Count tiles actually in chunks
	var chunk_squares: int = 0
	var chunk_triangles: int = 0
	var chunk_boxes: int = 0
	var chunk_prisms: int = 0

	for chunk in tile_map3d._quad_chunks:
		chunk_squares += chunk.tile_count
	for chunk in tile_map3d._triangle_chunks:
		chunk_triangles += chunk.tile_count
	for chunk in tile_map3d._box_chunks:
		chunk_boxes += chunk.tile_count
	for chunk in tile_map3d._prism_chunks:
		chunk_prisms += chunk.tile_count

	# Check consistency
	var all_consistent: bool = (
		saved_squares == lookup_squares and saved_squares == chunk_squares and
		saved_triangles == lookup_triangles and saved_triangles == chunk_triangles and
		saved_boxes == lookup_boxes and saved_boxes == chunk_boxes and
		saved_prisms == lookup_prisms and saved_prisms == chunk_prisms
	)

	if all_consistent:
		info += "   ✓ All mesh_mode data consistent\n"
		info += "      Squares: %d, Triangles: %d, Boxes: %d, Prisms: %d\n" % [saved_squares, saved_triangles, saved_boxes, saved_prisms]
	else:
		info += "   ✗ CORRUPTION DETECTED!\n"
		info += "      Saved → Lookup → Chunks:\n"
		info += "      Squares:   %d → %d → %d %s\n" % [saved_squares, lookup_squares, chunk_squares, "" if saved_squares == lookup_squares and saved_squares == chunk_squares else "✗"]
		info += "      Triangles: %d → %d → %d %s\n" % [saved_triangles, lookup_triangles, chunk_triangles, "" if saved_triangles == lookup_triangles and saved_triangles == chunk_triangles else "✗"]
		info += "      Boxes:     %d → %d → %d %s\n" % [saved_boxes, lookup_boxes, chunk_boxes, "" if saved_boxes == lookup_boxes and saved_boxes == chunk_boxes else "✗"]
		info += "      Prisms:    %d → %d → %d %s\n" % [saved_prisms, lookup_prisms, chunk_prisms, "" if saved_prisms == lookup_prisms and saved_prisms == chunk_prisms else "✗"]
		if saved_triangles > 0 and lookup_triangles == 0:
			info += "      → %d triangles converted to squares during reload!\n" % saved_triangles

	# COLUMNAR STORAGE & FILE SIZE OPTIMIZATION
	info += "\n"
	info += "COLUMNAR STORAGE & FILE SIZE:\n"
	info += _generate_storage_report(tile_map3d)

	info += "\n"
	info += "═══════════════════════════════════════════════\n"

	return info


## Generates storage optimization report section
static func _generate_storage_report(tile_map3d: TileMapLayer3D) -> String:
	var report: String = ""

	# Migration status
	var legacy_count: int = tile_map3d.saved_tiles.size()
	var columnar_count: int = tile_map3d._tile_positions.size()

	if legacy_count > 0 and columnar_count == 0:
		report += "   ⚠ MIGRATION PENDING: %d tiles in legacy saved_tiles\n" % legacy_count
		report += "      → Save scene to trigger migration\n"
	elif legacy_count > 0 and columnar_count > 0:
		report += "   ⚠ PARTIAL MIGRATION: %d legacy + %d columnar\n" % [legacy_count, columnar_count]
		report += "      → Save scene to complete migration\n"
	else:
		report += "   ✓ Using columnar storage (optimized)\n"

	# Array sizes
	report += "\n"
	report += "   Columnar Arrays:\n"
	report += "      _tile_positions: %d entries (%.1f KB)\n" % [
		tile_map3d._tile_positions.size(),
		tile_map3d._tile_positions.size() * 12.0 / 1024.0  # Vector3 = 12 bytes
	]
	report += "      _tile_uv_rects: %d floats (%.1f KB)\n" % [
		tile_map3d._tile_uv_rects.size(),
		tile_map3d._tile_uv_rects.size() * 4.0 / 1024.0  # float = 4 bytes
	]
	report += "      _tile_flags: %d entries (%.1f KB)\n" % [
		tile_map3d._tile_flags.size(),
		tile_map3d._tile_flags.size() * 4.0 / 1024.0  # int32 = 4 bytes
	]
	report += "      _tile_transform_indices: %d entries (%.1f KB)\n" % [
		tile_map3d._tile_transform_indices.size(),
		tile_map3d._tile_transform_indices.size() * 4.0 / 1024.0
	]
	report += "      _tile_transform_data: %d floats (%.1f KB)\n" % [
		tile_map3d._tile_transform_data.size(),
		tile_map3d._tile_transform_data.size() * 4.0 / 1024.0
	]

	# Transform data sparsity (key optimization metric)
	report += "\n"
	report += "   Transform Data Sparsity:\n"
	var tiles_with_transform: int = 0
	var tiles_without_transform: int = 0
	for i in range(tile_map3d._tile_transform_indices.size()):
		if tile_map3d._tile_transform_indices[i] >= 0:
			tiles_with_transform += 1
		else:
			tiles_without_transform += 1

	var total_tiles: int = tiles_with_transform + tiles_without_transform
	if total_tiles > 0:
		var sparsity_percent: float = (float(tiles_without_transform) / float(total_tiles)) * 100.0
		report += "      Tiles with transform data: %d (tilted)\n" % tiles_with_transform
		report += "      Tiles using defaults: %d (flat)\n" % tiles_without_transform
		report += "      Sparsity: %.1f%% " % sparsity_percent
		if sparsity_percent > 80.0:
			report += "✓ (excellent)\n"
		elif sparsity_percent > 50.0:
			report += "(good)\n"
		else:
			report += "⚠ (many tilted tiles)\n"
	else:
		report += "      (No tiles)\n"

	# Estimated storage efficiency
	report += "\n"
	report += "   Estimated Storage:\n"
	if total_tiles > 0:
		# Base: position(12) + uv(16) + flags(4) + transform_index(4) = 36 bytes/tile
		# Transform data: 16 bytes per tile that has it
		var base_bytes: int = total_tiles * 36
		var transform_bytes: int = tiles_with_transform * 16
		var total_bytes: int = base_bytes + transform_bytes
		var bytes_per_tile: float = float(total_bytes) / float(total_tiles)

		report += "      Base storage: %.1f KB (%d tiles × 36 bytes)\n" % [base_bytes / 1024.0, total_tiles]
		report += "      Transform storage: %.1f KB (%d tiles × 16 bytes)\n" % [transform_bytes / 1024.0, tiles_with_transform]
		report += "      Total estimated: %.1f KB\n" % (total_bytes / 1024.0)
		report += "      Bytes per tile: %.1f " % bytes_per_tile

		if bytes_per_tile <= 45.0:
			report += "✓ (optimal: ~44 expected for flat tiles)\n"
		elif bytes_per_tile <= 55.0:
			report += "(good: mix of flat/tilted)\n"
		elif bytes_per_tile <= 82.0:
			report += "⚠ (check transform data sparsity)\n"
		else:
			report += "✗ (inefficient - check for issues)\n"
	else:
		report += "      (No tiles to measure)\n"

	return report


## Helper to recursively count node types in scene tree
static func _count_node_types_recursive(node: Node) -> Dictionary:
	var counts: Dictionary = {
		"mesh": 0,
		"multimesh": 0,
		"cursor": 0,
		"cursor_meshes": 0,
		"total": 0,
		"non_cursor_mesh_details": []
	}

	_count_nodes_helper(node, counts, false)
	return counts


## Recursive helper for counting nodes
static func _count_nodes_helper(node: Node, counts: Dictionary, is_inside_cursor: bool) -> void:
	for child in node.get_children():
		counts["total"] += 1

		var child_is_cursor: bool = child is TileCursor3D

		if child is MeshInstance3D:
			counts["mesh"] += 1
			# Track if this mesh is a child of a cursor
			if is_inside_cursor or child_is_cursor:
				counts["cursor_meshes"] += 1
			else:
				# This is a non-cursor mesh - collect details
				var parent_node: Node = child.get_parent()
				var mesh_details: Dictionary = {
					"name": child.name,
					"type": child.get_class(),
					"parent": parent_node.name if parent_node else "None"
				}
				counts["non_cursor_mesh_details"].append(mesh_details)
		elif child is MultiMeshInstance3D:
			counts["multimesh"] += 1
		elif child_is_cursor:
			counts["cursor"] += 1

		# Recurse, marking if we're inside a cursor
		_count_nodes_helper(child, counts, is_inside_cursor or child_is_cursor)
