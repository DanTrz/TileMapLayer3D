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

	# Persistent Data (what gets saved to scene)
	info += "   PERSISTENT DATA (Saved to Scene):\n"
	info += "   Saved Tiles: %d\n" % tile_map3d.saved_tiles.size()

	# Count mesh_mode distribution in saved_tiles
	var saved_squares: int = 0
	var saved_triangles: int = 0
	for tile_data in tile_map3d.saved_tiles:
		if tile_data.mesh_mode == GlobalConstants.MeshMode.MESH_SQUARE:
			saved_squares += 1
		elif tile_data.mesh_mode == GlobalConstants.MeshMode.MESH_TRIANGLE:
			saved_triangles += 1

	info += "   └─ Squares (mesh_mode=0): %d tiles\n" % saved_squares
	info += "   └─ Triangles (mesh_mode=1): %d tiles\n" % saved_triangles
	info += "\n"

	# Runtime Data (regenerated each load)
	var total_chunks: int = tile_map3d._quad_chunks.size() + tile_map3d._triangle_chunks.size()
	info += "   RUNTIME DATA (Not Saved):\n"
	info += "   Square Chunks: %d\n" % tile_map3d._quad_chunks.size()
	info += "   Triangle Chunks: %d\n" % tile_map3d._triangle_chunks.size()
	info += "   Total Active Chunks: %d\n" % total_chunks
	info += "   Total MultiMesh Instances: %d\n" % total_chunks
	info += "   Tile Lookup Entries: %d\n" % tile_map3d._tile_lookup.size()

	# Count mesh_mode distribution in _tile_lookup (TileRefs)
	var lookup_squares: int = 0
	var lookup_triangles: int = 0
	for tile_key in tile_map3d._tile_lookup.keys():
		var tile_ref: TileMapLayer3D.TileRef = tile_map3d._tile_lookup[tile_key]
		if tile_ref.mesh_mode == GlobalConstants.MeshMode.MESH_SQUARE:
			lookup_squares += 1
		elif tile_ref.mesh_mode == GlobalConstants.MeshMode.MESH_TRIANGLE:
			lookup_triangles += 1

	info += "   └─ TileRefs with mesh_mode=0 (Square): %d\n" % lookup_squares
	info += "   └─ TileRefs with mesh_mode=1 (Triangle): %d\n" % lookup_triangles
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

	var orientation_name: String = GlobalPlaneDetector.get_orientation_name(GlobalPlaneDetector.current_tile_orientation_18d)
	info += "   Current Orientation: %s (%d)\n" % [orientation_name, GlobalPlaneDetector.current_tile_orientation_18d]
	info += "   Current Mesh Mode: %s\n" % ("Triangle" if tile_map3d.current_mesh_mode == GlobalConstants.MeshMode.MESH_TRIANGLE else "Square")

	# Data consistency checks
	info += "\n"
	info += "DATA CONSISTENCY:\n"
	var saved_count: int = tile_map3d.saved_tiles.size()
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

	# MESH_MODE INTEGRITY CHECK - Detects triangle→square conversion bug
	info += "\n"
	info += "MESH_MODE INTEGRITY CHECK:\n"

	# Count tiles actually in chunks
	var chunk_squares: int = 0
	var chunk_triangles: int = 0

	for chunk in tile_map3d._quad_chunks:
		chunk_squares += chunk.tile_count

	for chunk in tile_map3d._triangle_chunks:
		chunk_triangles += chunk.tile_count

	# Compare saved_tiles → _tile_lookup
	info += "   saved_tiles squares: %d → _tile_lookup squares: %d" % [saved_squares, lookup_squares]
	if saved_squares == lookup_squares:
		info += " \n"
	else:
		info += " ✗ MISMATCH!\n"

	info += "   saved_tiles triangles: %d → _tile_lookup triangles: %d" % [saved_triangles, lookup_triangles]
	if saved_triangles == lookup_triangles:
		info += " \n"
	else:
		info += " ✗ MISMATCH!\n"

	info += "\n"

	# Compare chunk contents
	info += "   Square chunks contain: %d tiles" % chunk_squares
	if chunk_squares == saved_squares:
		info += " \n"
	else:
		info += " ✗ Expected %d!\n" % saved_squares

	info += "   Triangle chunks contain: %d tiles" % chunk_triangles
	if chunk_triangles == saved_triangles:
		info += " \n"
	else:
		info += " ✗ Expected %d!\n" % saved_triangles

	# Overall status
	var all_consistent: bool = (
		saved_squares == lookup_squares and
		saved_triangles == lookup_triangles and
		chunk_squares == saved_squares and
		chunk_triangles == saved_triangles
	)

	info += "\n"
	if all_consistent:
		info += "   ALL mesh_mode data consistent!\n"
	else:
		info += "CORRUPTION DETECTED!\n"
		if saved_triangles > 0 and lookup_triangles == 0:
			info += "       %d triangles converted to squares during reload!\n" % saved_triangles
		elif saved_triangles > lookup_triangles:
			info += "       %d triangles lost!\n" % (saved_triangles - lookup_triangles)

	# Sample tile data for debugging (first 5 triangles and first 5 squares)
	info += "\n"
	info += "  SAMPLE TILE DATA (for debugging):\n"

	# Show first 5 triangle tiles from saved_tiles
	var triangle_count: int = 0
	info += "   TRIANGLES (first 5 from saved_tiles):\n"
	for tile_data in tile_map3d.saved_tiles:
		if tile_data.mesh_mode == GlobalConstants.MeshMode.MESH_TRIANGLE:
			triangle_count += 1
			if triangle_count <= 5:
				info += "      %d. grid_pos=%s, mesh_mode=%d, uv=%s, orientation=%d\n" % [
					triangle_count,
					tile_data.grid_position,
					tile_data.mesh_mode,
					tile_data.uv_rect,
					tile_data.orientation
				]
			else:
				break

	if triangle_count == 0:
		info += "      (No triangles found in saved_tiles)\n"

	# Show first 5 square tiles from saved_tiles
	var square_count: int = 0
	info += "   SQUARES (first 5 from saved_tiles):\n"
	for tile_data in tile_map3d.saved_tiles:
		if tile_data.mesh_mode == GlobalConstants.MeshMode.MESH_SQUARE:
			square_count += 1
			if square_count <= 5:
				info += "      %d. grid_pos=%s, mesh_mode=%d, uv=%s, orientation=%d\n" % [
					square_count,
					tile_data.grid_position,
					tile_data.mesh_mode,
					tile_data.uv_rect,
					tile_data.orientation
				]
			else:
				break

	if square_count == 0:
		info += "      (No squares found in saved_tiles)\n"

	info += "\n"
	info += "═══════════════════════════════════════════════\n"

	return info


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
