@tool
class_name DebugInfoGenerator
extends RefCounted
## Generates health/debug information for TileMapLayer3D nodes.
## Focused on critical system health metrics and spatial chunking status.
##
## Usage:
##   DebugInfoGenerator.print_report(tile_map3d, placement_manager)


## Prints health report to console
static func print_report(tile_map3d: TileMapLayer3D, placement_manager: TilePlacementManager) -> void:
	if not tile_map3d:
		push_warning("DebugInfoGenerator: No TileMapLayer3D provided")
		return
	print(generate_report(tile_map3d, placement_manager))


## Generates the health report string
static func generate_report(tile_map3d: TileMapLayer3D, placement_manager: TilePlacementManager) -> String:
	if not tile_map3d:
		return "ERROR: No TileMapLayer3D provided"

	var info: String = "\n"
	info += "=== TileMapLayer3D Health Report ===\n"
	info += "Node: %s | Grid: %.1f\n\n" % [tile_map3d.name, tile_map3d.grid_size]

	# SECTION 1: Data Integrity (most critical)
	info += _generate_integrity_section(tile_map3d, placement_manager)

	# SECTION 2: Spatial Chunking System Status
	info += _generate_chunking_section(tile_map3d)

	# SECTION 3: AABB Health Check (frustum culling)
	info += _generate_aabb_section(tile_map3d)

	# SECTION 4: Chunk Type Distribution
	info += _generate_chunk_types_section(tile_map3d)

	# SECTION 5: Storage Status (brief)
	info += _generate_storage_section(tile_map3d)

	info += "====================================\n"
	return info


## SECTION 1: Data Integrity Check - The most critical health metric
static func _generate_integrity_section(tile_map3d: TileMapLayer3D, placement_manager: TilePlacementManager) -> String:
	var report: String = "[DATA INTEGRITY]\n"

	var saved_count: int = tile_map3d.get_tile_count()
	var lookup_count: int = tile_map3d._tile_lookup.size()
	var tracked_count: int = placement_manager._placement_data.size() if placement_manager else -1

	# Count visible tiles across ALL chunk types
	var visible_count: int = _count_visible_tiles_all_chunks(tile_map3d)

	# Check if all counts match
	var is_healthy: bool = (saved_count == lookup_count and saved_count == visible_count)
	if placement_manager:
		is_healthy = is_healthy and (saved_count == tracked_count)

	if is_healthy:
		report += "  OK: All counts match (%d tiles)\n" % saved_count
	else:
		report += "  MISMATCH DETECTED!\n"
		report += "    Saved:   %d\n" % saved_count
		report += "    Lookup:  %d\n" % lookup_count
		report += "    Visible: %d\n" % visible_count
		if placement_manager:
			report += "    Tracked: %d\n" % tracked_count

	# Mesh mode consistency check (quick)
	var mesh_mode_ok: bool = _check_mesh_mode_consistency(tile_map3d)
	if mesh_mode_ok:
		report += "  OK: Mesh mode data consistent\n"
	else:
		report += "  ERROR: Mesh mode corruption detected!\n"

	report += "\n"
	return report


## SECTION 2: Spatial Chunking System Status
static func _generate_chunking_section(tile_map3d: TileMapLayer3D) -> String:
	var report: String = "[SPATIAL CHUNKING SYSTEM]\n"

	# Count unique regions across all registries
	var quad_regions: int = tile_map3d._chunk_registry_quad.size()
	var tri_regions: int = tile_map3d._chunk_registry_triangle.size()
	var box_regions: int = tile_map3d._chunk_registry_box.size()
	var box_repeat_regions: int = tile_map3d._chunk_registry_box_repeat.size()
	var prism_regions: int = tile_map3d._chunk_registry_prism.size()
	var prism_repeat_regions: int = tile_map3d._chunk_registry_prism_repeat.size()

	var total_regions: int = quad_regions + tri_regions + box_regions + box_repeat_regions + prism_regions + prism_repeat_regions

	# Check if spatial chunking is active (regions > 0 means tiles exist and chunking is working)
	var total_chunks: int = _count_all_chunks(tile_map3d)

	if total_chunks == 0:
		report += "  Status: No chunks (empty scene)\n"
	elif total_regions > 0:
		report += "  Status: ACTIVE\n"
		report += "  Region Size: %.0fx%.0fx%.0f units\n" % [
			GlobalConstants.CHUNK_REGION_SIZE,
			GlobalConstants.CHUNK_REGION_SIZE,
			GlobalConstants.CHUNK_REGION_SIZE
		]
		report += "  Max Tiles/Chunk: %d\n" % GlobalConstants.CHUNK_MAX_TILES
		report += "  Total Regions: %d | Total Chunks: %d\n" % [total_regions, total_chunks]

		# Show region distribution if multiple regions exist
		if total_regions > 1:
			report += "  Regions by Type:\n"
			if quad_regions > 0:
				report += "    Quad: %d regions, %d chunks\n" % [quad_regions, tile_map3d._quad_chunks.size()]
			if tri_regions > 0:
				report += "    Triangle: %d regions, %d chunks\n" % [tri_regions, tile_map3d._triangle_chunks.size()]
			if box_regions > 0:
				report += "    Box: %d regions, %d chunks\n" % [box_regions, tile_map3d._box_chunks.size()]
			if box_repeat_regions > 0:
				report += "    Box-Repeat: %d regions, %d chunks\n" % [box_repeat_regions, tile_map3d._box_repeat_chunks.size()]
			if prism_regions > 0:
				report += "    Prism: %d regions, %d chunks\n" % [prism_regions, tile_map3d._prism_chunks.size()]
			if prism_repeat_regions > 0:
				report += "    Prism-Repeat: %d regions, %d chunks\n" % [prism_repeat_regions, tile_map3d._prism_repeat_chunks.size()]
	else:
		# Legacy scene (no regions but has chunks)
		report += "  Status: LEGACY MODE (no spatial regions)\n"
		report += "  Total Chunks: %d\n" % total_chunks

	# Check for chunk health issues
	var chunk_issues: Array[String] = _check_chunk_health(tile_map3d)
	if chunk_issues.size() > 0:
		report += "  ISSUES:\n"
		for issue in chunk_issues:
			report += "    - %s\n" % issue

	report += "\n"
	return report


## SECTION 3: AABB Health Check - Ensures frustum culling works correctly
static func _generate_aabb_section(tile_map3d: TileMapLayer3D) -> String:
	var report: String = "[AABB HEALTH (Frustum Culling)]\n"

	# Expected AABB from GlobalConstants
	var expected_aabb: AABB = GlobalConstants.CHUNK_CUSTOM_AABB

	# Collect all chunks
	var all_chunks: Array = []
	all_chunks.append_array(tile_map3d._quad_chunks)
	all_chunks.append_array(tile_map3d._triangle_chunks)
	all_chunks.append_array(tile_map3d._box_chunks)
	all_chunks.append_array(tile_map3d._box_repeat_chunks)
	all_chunks.append_array(tile_map3d._prism_chunks)
	all_chunks.append_array(tile_map3d._prism_repeat_chunks)

	if all_chunks.is_empty():
		report += "  (No chunks to check)\n\n"
		return report

	# Check each chunk's AABB
	var correct_count: int = 0
	var wrong_count: int = 0
	var wrong_chunks: Array[String] = []

	for chunk in all_chunks:
		if not chunk:
			continue
		var has_correct_aabb: bool = _aabb_matches(chunk.custom_aabb, expected_aabb)
		if has_correct_aabb:
			correct_count += 1
		else:
			wrong_count += 1
			wrong_chunks.append("%s: %s" % [chunk.name, chunk.custom_aabb])

	# Report status
	if wrong_count == 0:
		report += "  OK: All %d chunks have correct AABB\n" % correct_count
		report += "  Expected: %s\n" % expected_aabb
	else:
		report += "  ERROR: %d/%d chunks have WRONG AABB!\n" % [wrong_count, correct_count + wrong_count]
		report += "  Expected: %s\n" % expected_aabb
		report += "  Wrong chunks:\n"
		for wrong_info in wrong_chunks.slice(0, 5):  # Show max 5
			report += "    - %s\n" % wrong_info
		if wrong_chunks.size() > 5:
			report += "    ... and %d more\n" % (wrong_chunks.size() - 5)

	# Check if tiles are within AABB bounds
	var tiles_outside: int = _count_tiles_outside_aabb(tile_map3d, all_chunks)
	if tiles_outside > 0:
		report += "  WARNING: %d tiles outside chunk AABB bounds!\n" % tiles_outside
	else:
		report += "  OK: All tiles within AABB bounds\n"

	report += "\n"
	return report


## Helper: Compare two AABBs with tolerance
static func _aabb_matches(a: AABB, b: AABB, tolerance: float = 0.1) -> bool:
	return a.position.distance_to(b.position) < tolerance and a.size.distance_to(b.size) < tolerance


## Helper: Count tiles outside their chunk's AABB
static func _count_tiles_outside_aabb(tile_map3d: TileMapLayer3D, all_chunks: Array) -> int:
	var count: int = 0
	for chunk in all_chunks:
		if not chunk or not chunk.multimesh:
			continue
		for i in range(chunk.multimesh.visible_instance_count):
			var pos: Vector3 = chunk.multimesh.get_instance_transform(i).origin
			if not chunk.custom_aabb.has_point(pos):
				count += 1
	return count


## SECTION 4: Chunk Type Distribution
static func _generate_chunk_types_section(tile_map3d: TileMapLayer3D) -> String:
	var report: String = "[CHUNK DISTRIBUTION]\n"

	# Gather stats for all 6 chunk types
	var stats: Array[Dictionary] = [
		_get_chunk_array_stats("Quad", tile_map3d._quad_chunks),
		_get_chunk_array_stats("Triangle", tile_map3d._triangle_chunks),
		_get_chunk_array_stats("Box", tile_map3d._box_chunks),
		_get_chunk_array_stats("Box-Repeat", tile_map3d._box_repeat_chunks),
		_get_chunk_array_stats("Prism", tile_map3d._prism_chunks),
		_get_chunk_array_stats("Prism-Repeat", tile_map3d._prism_repeat_chunks),
	]

	# Only show types that have chunks
	var has_any: bool = false
	for stat in stats:
		if stat.chunks > 0:
			has_any = true
			var usage_str: String = "%.0f%%" % stat.avg_usage if stat.avg_usage >= 0 else "N/A"
			var warning: String = " [FULL]" if stat.has_full_chunk else ""
			report += "  %s: %d chunks, %d tiles, avg %s%s\n" % [
				stat.name, stat.chunks, stat.tiles, usage_str, warning
			]

	if not has_any:
		report += "  (No chunks)\n"

	report += "\n"
	return report


## SECTION 4: Storage Status (brief)
static func _generate_storage_section(tile_map3d: TileMapLayer3D) -> String:
	var report: String = "[STORAGE]\n"

	var legacy_count: int = tile_map3d.saved_tiles.size()
	var columnar_count: int = tile_map3d._tile_positions.size()

	if legacy_count > 0 and columnar_count == 0:
		report += "  WARNING: Migration pending (%d legacy tiles)\n" % legacy_count
		report += "  -> Save scene to migrate\n"
	elif legacy_count > 0 and columnar_count > 0:
		report += "  WARNING: Partial migration\n"
	else:
		# Calculate bytes per tile
		if columnar_count > 0:
			var tiles_with_transform: int = 0
			for i in range(tile_map3d._tile_transform_indices.size()):
				if tile_map3d._tile_transform_indices[i] >= 0:
					tiles_with_transform += 1

			var base_bytes: int = columnar_count * 36  # position + uv + flags + index
			var transform_bytes: int = tiles_with_transform * 20  # 5 floats per transform
			var total_bytes: int = base_bytes + transform_bytes
			var bytes_per_tile: float = float(total_bytes) / float(columnar_count)

			report += "  Columnar: %d tiles (%.1f bytes/tile)\n" % [columnar_count, bytes_per_tile]
			report += "  Sparse transforms: %d/%d tiles\n" % [tiles_with_transform, columnar_count]
		else:
			report += "  Columnar: 0 tiles\n"

	report += "\n"
	return report


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

## Counts visible tiles across all 6 chunk types
static func _count_visible_tiles_all_chunks(tile_map3d: TileMapLayer3D) -> int:
	var total: int = 0

	for chunk in tile_map3d._quad_chunks:
		total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._triangle_chunks:
		total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._box_chunks:
		total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._box_repeat_chunks:
		total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._prism_chunks:
		total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._prism_repeat_chunks:
		total += chunk.multimesh.visible_instance_count

	return total


## Counts all chunks across all 6 types
static func _count_all_chunks(tile_map3d: TileMapLayer3D) -> int:
	return (
		tile_map3d._quad_chunks.size() +
		tile_map3d._triangle_chunks.size() +
		tile_map3d._box_chunks.size() +
		tile_map3d._box_repeat_chunks.size() +
		tile_map3d._prism_chunks.size() +
		tile_map3d._prism_repeat_chunks.size()
	)


## Quick mesh mode consistency check
static func _check_mesh_mode_consistency(tile_map3d: TileMapLayer3D) -> bool:
	# Count tiles by mesh_mode in saved data vs chunks
	var saved_by_mode: Dictionary = {0: 0, 1: 0, 2: 0, 3: 0}  # FLAT_SQUARE, FLAT_TRIANGLE, BOX, PRISM

	for i in range(tile_map3d.get_tile_count()):
		var tile: TilePlacerData = tile_map3d.get_tile_at(i)
		if saved_by_mode.has(tile.mesh_mode):
			saved_by_mode[tile.mesh_mode] += 1

	# Count in chunks (BOX and PRISM include both DEFAULT and REPEAT modes)
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
	for chunk in tile_map3d._box_repeat_chunks:
		chunk_boxes += chunk.tile_count  # REPEAT mode is still BOX_MESH
	for chunk in tile_map3d._prism_chunks:
		chunk_prisms += chunk.tile_count
	for chunk in tile_map3d._prism_repeat_chunks:
		chunk_prisms += chunk.tile_count  # REPEAT mode is still PRISM_MESH

	return (
		saved_by_mode[0] == chunk_squares and
		saved_by_mode[1] == chunk_triangles and
		saved_by_mode[2] == chunk_boxes and
		saved_by_mode[3] == chunk_prisms
	)


## Checks for chunk health issues
static func _check_chunk_health(tile_map3d: TileMapLayer3D) -> Array[String]:
	var issues: Array[String] = []

	# Check for chunks with mismatched tile_count vs visible_instance_count
	var all_chunks: Array = []
	all_chunks.append_array(tile_map3d._quad_chunks)
	all_chunks.append_array(tile_map3d._triangle_chunks)
	all_chunks.append_array(tile_map3d._box_chunks)
	all_chunks.append_array(tile_map3d._box_repeat_chunks)
	all_chunks.append_array(tile_map3d._prism_chunks)
	all_chunks.append_array(tile_map3d._prism_repeat_chunks)

	var mismatched_chunks: int = 0
	var orphaned_refs: int = 0

	for chunk in all_chunks:
		if chunk.tile_count != chunk.multimesh.visible_instance_count:
			mismatched_chunks += 1

		# Check for orphaned tile_refs (refs pointing to invalid instance indices)
		for tile_key in chunk.tile_refs.keys():
			var instance_idx: int = chunk.tile_refs[tile_key]
			if instance_idx < 0 or instance_idx >= chunk.multimesh.visible_instance_count:
				orphaned_refs += 1

	if mismatched_chunks > 0:
		issues.append("%d chunks have tile_count mismatch" % mismatched_chunks)
	if orphaned_refs > 0:
		issues.append("%d orphaned tile references" % orphaned_refs)

	# Check if any registry has chunks not in flat array (data structure corruption)
	var registry_vs_array_mismatch: bool = _check_registry_array_consistency(tile_map3d)
	if not registry_vs_array_mismatch:
		issues.append("Registry/array mismatch detected")

	return issues


## Checks if registries and flat arrays are consistent
static func _check_registry_array_consistency(tile_map3d: TileMapLayer3D) -> bool:
	# Count chunks in registries
	var registry_count: int = 0
	for region_chunks in tile_map3d._chunk_registry_quad.values():
		registry_count += region_chunks.size()
	for region_chunks in tile_map3d._chunk_registry_triangle.values():
		registry_count += region_chunks.size()
	for region_chunks in tile_map3d._chunk_registry_box.values():
		registry_count += region_chunks.size()
	for region_chunks in tile_map3d._chunk_registry_box_repeat.values():
		registry_count += region_chunks.size()
	for region_chunks in tile_map3d._chunk_registry_prism.values():
		registry_count += region_chunks.size()
	for region_chunks in tile_map3d._chunk_registry_prism_repeat.values():
		registry_count += region_chunks.size()

	var array_count: int = _count_all_chunks(tile_map3d)

	return registry_count == array_count


## Gets stats for a chunk array
static func _get_chunk_array_stats(name: String, chunks: Array) -> Dictionary:
	var stats: Dictionary = {
		"name": name,
		"chunks": chunks.size(),
		"tiles": 0,
		"avg_usage": -1.0,
		"has_full_chunk": false
	}

	if chunks.size() == 0:
		return stats

	var total_usage: float = 0.0
	for chunk in chunks:
		stats.tiles += chunk.tile_count
		var capacity: int = chunk.multimesh.instance_count
		if capacity > 0:
			var usage: float = (float(chunk.tile_count) / float(capacity)) * 100.0
			total_usage += usage
			if usage >= 95.0:
				stats.has_full_chunk = true

	stats.avg_usage = total_usage / float(chunks.size())
	return stats
