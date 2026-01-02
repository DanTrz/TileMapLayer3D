@tool
class_name DebugInfoGenerator
extends RefCounted
## Generates comprehensive diagnostic information for TileMapLayer3D nodes.
## v0.4.2 - Enhanced diagnostics for spatial chunking debugging.
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
	info += "======================================================================\n"
	info += "         TileMapLayer3D v0.4.2 DIAGNOSTIC REPORT                     \n"
	info += "======================================================================\n\n"

	# SECTION 1: System Overview
	info += _generate_system_overview(tile_map3d)

	# SECTION 2: Chunk Registry Overview
	info += _generate_registry_overview(tile_map3d)

	# SECTION 3: Per-Chunk Detailed Analysis (CRITICAL)
	info += _generate_chunk_analysis_section(tile_map3d)

	# SECTION 4: Columnar Storage Verification
	info += _generate_columnar_storage_section(tile_map3d)

	# SECTION 5: Cross-Check Storage vs Chunks
	info += _generate_cross_check_section(tile_map3d)

	# SECTION 6: Coordinate System Verification
	info += _generate_coordinate_verification_section(tile_map3d)

	# SECTION 7: Health Summary
	info += _generate_health_summary(tile_map3d, placement_manager)

	# SECTION 8: Frustum Culling Diagnostics
	info += _generate_frustum_culling_section(tile_map3d)

	info += "======================================================================\n"
	return info


## SECTION 1: System Overview
static func _generate_system_overview(tile_map3d: TileMapLayer3D) -> String:
	var report: String = "----------------------------------------------------------------------\n"
	report += " [1] SYSTEM OVERVIEW                                                 \n"
	report += "----------------------------------------------------------------------\n"

	report += "  Node Name: %s\n" % tile_map3d.name
	report += "  Grid Size: %.2f\n" % tile_map3d.grid_size

	if tile_map3d.settings and tile_map3d.settings.tileset_texture:
		var tex: Texture2D = tile_map3d.settings.tileset_texture
		report += "  Tileset: %s (%dx%d)\n" % [tex.resource_path.get_file(), tex.get_width(), tex.get_height()]
	else:
		report += "  Tileset: (none)\n"

	report += "  Total Tile Count: %d\n" % tile_map3d.get_tile_count()
	report += "  Chunk Region Size: %.0f units\n" % GlobalConstants.CHUNK_REGION_SIZE
	report += "  Max Tiles/Chunk: %d\n" % GlobalConstants.CHUNK_MAX_TILES
	report += "\n"
	return report


## SECTION 2: Chunk Registry Overview
static func _generate_registry_overview(tile_map3d: TileMapLayer3D) -> String:
	var report: String = "----------------------------------------------------------------------\n"
	report += " [2] CHUNK REGISTRIES                                                \n"
	report += "----------------------------------------------------------------------\n"

	var quad_regions: int = tile_map3d._chunk_registry_quad.size()
	var tri_regions: int = tile_map3d._chunk_registry_triangle.size()
	var box_regions: int = tile_map3d._chunk_registry_box.size()
	var box_repeat_regions: int = tile_map3d._chunk_registry_box_repeat.size()
	var prism_regions: int = tile_map3d._chunk_registry_prism.size()
	var prism_repeat_regions: int = tile_map3d._chunk_registry_prism_repeat.size()

	report += "  Quad Registry:         %d regions, %d chunks\n" % [quad_regions, tile_map3d._quad_chunks.size()]
	report += "  Triangle Registry:     %d regions, %d chunks\n" % [tri_regions, tile_map3d._triangle_chunks.size()]
	report += "  Box Registry:          %d regions, %d chunks\n" % [box_regions, tile_map3d._box_chunks.size()]
	report += "  Box-Repeat Registry:   %d regions, %d chunks\n" % [box_repeat_regions, tile_map3d._box_repeat_chunks.size()]
	report += "  Prism Registry:        %d regions, %d chunks\n" % [prism_regions, tile_map3d._prism_chunks.size()]
	report += "  Prism-Repeat Registry: %d regions, %d chunks\n" % [prism_repeat_regions, tile_map3d._prism_repeat_chunks.size()]

	var total_regions: int = quad_regions + tri_regions + box_regions + box_repeat_regions + prism_regions + prism_repeat_regions
	var total_chunks: int = _count_all_chunks(tile_map3d)
	report += "  -------------------------------------\n"
	report += "  TOTAL: %d regions, %d chunks\n" % [total_regions, total_chunks]
	report += "\n"
	return report


## SECTION 3: Per-Chunk Detailed Analysis (CRITICAL)
static func _generate_chunk_analysis_section(tile_map3d: TileMapLayer3D) -> String:
	var report: String = "----------------------------------------------------------------------\n"
	report += " [3] PER-CHUNK DETAILED ANALYSIS                                     \n"
	report += "----------------------------------------------------------------------\n"

	# Collect all chunks with their types
	var chunk_data: Array[Dictionary] = []

	for chunk in tile_map3d._quad_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_SQUARE"})
	for chunk in tile_map3d._triangle_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_TRIANGLE"})
	for chunk in tile_map3d._box_chunks:
		chunk_data.append({"chunk": chunk, "type": "BOX_MESH"})
	for chunk in tile_map3d._box_repeat_chunks:
		chunk_data.append({"chunk": chunk, "type": "BOX_REPEAT"})
	for chunk in tile_map3d._prism_chunks:
		chunk_data.append({"chunk": chunk, "type": "PRISM_MESH"})
	for chunk in tile_map3d._prism_repeat_chunks:
		chunk_data.append({"chunk": chunk, "type": "PRISM_REPEAT"})

	if chunk_data.is_empty():
		report += "  (No chunks to analyze)\n\n"
		return report

	for data in chunk_data:
		report += _analyze_single_chunk(data.chunk, data.type)

	return report


static func _analyze_single_chunk(chunk: MultiMeshTileChunkBase, type: String) -> String:
	if not chunk or not chunk.multimesh:
		return ""

	var report: String = ""
	report += "  +-- [%s] ------------------------------------\n" % chunk.name
	report += "  | Type: %s\n" % type
	report += "  | Region Key: %s\n" % str(chunk.region_key)
	report += "  |\n"

	# POSITIONING
	var expected_pos: Vector3 = Vector3(
		float(chunk.region_key.x) * GlobalConstants.CHUNK_REGION_SIZE,
		float(chunk.region_key.y) * GlobalConstants.CHUNK_REGION_SIZE,
		float(chunk.region_key.z) * GlobalConstants.CHUNK_REGION_SIZE
	)
	var pos_match: bool = chunk.position.is_equal_approx(expected_pos)

	report += "  | POSITIONING:\n"
	report += "  |   Node Position (local):  %s\n" % _vec3_str(chunk.position)
	report += "  |   Node Position (global): %s\n" % _vec3_str(chunk.global_position)
	report += "  |   Expected Position:      %s\n" % _vec3_str(expected_pos)
	if pos_match:
		report += "  |   Position Match: YES\n"
	else:
		report += "  |   Position Match: NO - MISMATCH!\n"
	report += "  |\n"

	# AABB
	var expected_aabb: AABB = GlobalConstants.CHUNK_LOCAL_AABB
	var aabb_match: bool = _aabb_matches(chunk.custom_aabb, expected_aabb)
	var world_aabb: AABB = AABB(chunk.global_position + chunk.custom_aabb.position, chunk.custom_aabb.size)

	report += "  | AABB:\n"
	report += "  |   Custom AABB:   Pos%s Size%s\n" % [_vec3_str(chunk.custom_aabb.position), _vec3_str(chunk.custom_aabb.size)]
	report += "  |   Expected AABB: Pos%s Size%s\n" % [_vec3_str(expected_aabb.position), _vec3_str(expected_aabb.size)]
	report += "  |   World AABB:    Pos%s Size%s\n" % [_vec3_str(world_aabb.position), _vec3_str(world_aabb.size)]
	if aabb_match:
		report += "  |   AABB Match: YES\n"
	else:
		report += "  |   AABB Match: NO - MISMATCH!\n"
	report += "  |\n"

	# TILES
	var tile_count: int = chunk.multimesh.visible_instance_count
	var capacity: int = chunk.multimesh.instance_count
	var usage_pct: float = (float(tile_count) / float(capacity)) * 100.0 if capacity > 0 else 0.0

	report += "  | TILES:\n"
	report += "  |   Count: %d / %d (%.1f%% usage)\n" % [tile_count, capacity, usage_pct]

	if tile_count > 0:
		# Calculate tile bounds
		var min_pos: Vector3 = Vector3(INF, INF, INF)
		var max_pos: Vector3 = Vector3(-INF, -INF, -INF)
		var outside_count: int = 0

		for i in range(tile_count):
			var pos: Vector3 = chunk.multimesh.get_instance_transform(i).origin
			min_pos.x = min(min_pos.x, pos.x)
			min_pos.y = min(min_pos.y, pos.y)
			min_pos.z = min(min_pos.z, pos.z)
			max_pos.x = max(max_pos.x, pos.x)
			max_pos.y = max(max_pos.y, pos.y)
			max_pos.z = max(max_pos.z, pos.z)
			if not chunk.custom_aabb.has_point(pos):
				outside_count += 1

		report += "  |\n"
		report += "  | TILE BOUNDS (from MultiMesh transforms):\n"
		report += "  |   Min Position: %s\n" % _vec3_str(min_pos)
		report += "  |   Max Position: %s\n" % _vec3_str(max_pos)
		report += "  |   Span: %s\n" % _vec3_str(max_pos - min_pos)

		if outside_count > 0:
			report += "  |   TILES OUTSIDE AABB: %d / %d (%.1f%%)\n" % [outside_count, tile_count, (float(outside_count)/float(tile_count))*100.0]
		else:
			report += "  |   All tiles within AABB bounds\n"

		# Sample first 5 tiles
		report += "  |\n"
		report += "  | SAMPLE TILES (first 5):\n"
		for i in range(min(5, tile_count)):
			var pos: Vector3 = chunk.multimesh.get_instance_transform(i).origin
			var in_aabb: bool = chunk.custom_aabb.has_point(pos)
			var status: String = "OK" if in_aabb else "OUTSIDE"
			report += "  |   [%d] Origin: %s  %s\n" % [i, _vec3_str(pos), status]

	report += "  +------------------------------------------------\n\n"
	return report


## SECTION 4: Columnar Storage Verification
static func _generate_columnar_storage_section(tile_map3d: TileMapLayer3D) -> String:
	var report: String = "----------------------------------------------------------------------\n"
	report += " [4] COLUMNAR STORAGE VERIFICATION                                   \n"
	report += "----------------------------------------------------------------------\n"

	var pos_count: int = tile_map3d._tile_positions.size()
	var uv_count: int = tile_map3d._tile_uv_rects.size() / 4  # 4 floats per UV rect
	var flags_count: int = tile_map3d._tile_flags.size()
	var transform_idx_count: int = tile_map3d._tile_transform_indices.size()
	var transform_data_count: int = tile_map3d._tile_transform_data.size() / 5  # 5 floats per entry

	report += "  Position Array:        %d entries\n" % pos_count
	report += "  UV Rect Array:         %d entries (%d floats / 4)\n" % [uv_count, tile_map3d._tile_uv_rects.size()]
	report += "  Flags Array:           %d entries\n" % flags_count
	report += "  Transform Indices:     %d entries\n" % transform_idx_count
	report += "  Transform Data:        %d entries (%d floats / 5)\n" % [transform_data_count, tile_map3d._tile_transform_data.size()]

	# Count tiles with custom transform params
	var tiles_with_params: int = 0
	for i in range(transform_idx_count):
		if tile_map3d._tile_transform_indices[i] >= 0:
			tiles_with_params += 1
	report += "  Tiles with transform params: %d / %d\n" % [tiles_with_params, pos_count]

	# Consistency check
	var consistent: bool = (pos_count == uv_count and pos_count == flags_count and pos_count == transform_idx_count)
	if consistent:
		report += "  Array consistency: All arrays same size\n"
	else:
		report += "  Array consistency: SIZE MISMATCH!\n"

	# Sample positions with expected regions
	if pos_count > 0:
		report += "\n  SAMPLE POSITIONS (first 5):\n"
		var region_size: float = GlobalConstants.CHUNK_REGION_SIZE
		for i in range(min(5, pos_count)):
			var grid_pos: Vector3 = tile_map3d._tile_positions[i]
			var expected_region: Vector3i = Vector3i(
				int(floor(grid_pos.x / region_size)),
				int(floor(grid_pos.y / region_size)),
				int(floor(grid_pos.z / region_size))
			)
			report += "    [%d] Grid Pos: %s -> Expected Region: %s\n" % [i, _vec3_str(grid_pos), str(expected_region)]

	report += "\n"
	return report


## SECTION 5: Cross-Check Storage vs Chunks
static func _generate_cross_check_section(tile_map3d: TileMapLayer3D) -> String:
	var report: String = "----------------------------------------------------------------------\n"
	report += " [5] CROSS-CHECK: Storage vs Chunks                                  \n"
	report += "----------------------------------------------------------------------\n"

	var storage_count: int = tile_map3d._tile_positions.size()
	var chunk_count: int = _count_visible_tiles_all_chunks(tile_map3d)
	var match_status: bool = (storage_count == chunk_count)

	report += "  Total tiles in storage: %d\n" % storage_count
	report += "  Total tiles in chunks:  %d\n" % chunk_count
	if match_status:
		report += "  Match: YES\n"
	else:
		report += "  Match: NO - MISMATCH by %d!\n" % abs(storage_count - chunk_count)

	# Count tiles per region from storage
	if storage_count > 0:
		var region_counts: Dictionary = {}  # Vector3i -> int
		var region_size: float = GlobalConstants.CHUNK_REGION_SIZE

		for i in range(storage_count):
			var grid_pos: Vector3 = tile_map3d._tile_positions[i]
			var region: Vector3i = Vector3i(
				int(floor(grid_pos.x / region_size)),
				int(floor(grid_pos.y / region_size)),
				int(floor(grid_pos.z / region_size))
			)
			if not region_counts.has(region):
				region_counts[region] = 0
			region_counts[region] += 1

		report += "\n  Tiles per region (from storage):\n"
		var sorted_regions: Array = region_counts.keys()
		sorted_regions.sort()
		for region in sorted_regions:
			report += "    Region %s: %d tiles\n" % [str(region), region_counts[region]]

	report += "\n"
	return report


## SECTION 6: Coordinate System Verification
static func _generate_coordinate_verification_section(tile_map3d: TileMapLayer3D) -> String:
	var report: String = "----------------------------------------------------------------------\n"
	report += " [6] COORDINATE SYSTEM VERIFICATION                                  \n"
	report += "----------------------------------------------------------------------\n"

	if tile_map3d._tile_positions.size() == 0:
		report += "  (No tiles to verify)\n\n"
		return report

	# Test with first tile
	var grid_pos: Vector3 = tile_map3d._tile_positions[0]
	var region_size: float = GlobalConstants.CHUNK_REGION_SIZE
	var region: Vector3i = Vector3i(
		int(floor(grid_pos.x / region_size)),
		int(floor(grid_pos.y / region_size)),
		int(floor(grid_pos.z / region_size))
	)
	var region_world_origin: Vector3 = Vector3(
		float(region.x) * region_size,
		float(region.y) * region_size,
		float(region.z) * region_size
	)
	var expected_local: Vector3 = grid_pos - region_world_origin

	report += "  Testing tile at storage[0]:\n"
	report += "    Stored Grid Position: %s\n" % _vec3_str(grid_pos)
	report += "    Calculated Region: %s\n" % str(region)
	report += "    Region World Origin: %s\n" % _vec3_str(region_world_origin)
	report += "    Expected Local Grid Pos: %s\n" % _vec3_str(expected_local)

	# Find chunk for this region and check first tile transform
	var found_chunk: MultiMeshTileChunkBase = null
	for chunk in tile_map3d._quad_chunks:
		if chunk.region_key == region:
			found_chunk = chunk
			break
	if not found_chunk:
		for chunk in tile_map3d._triangle_chunks:
			if chunk.region_key == region:
				found_chunk = chunk
				break
	if not found_chunk:
		for chunk in tile_map3d._box_chunks:
			if chunk.region_key == region:
				found_chunk = chunk
				break
	if not found_chunk:
		for chunk in tile_map3d._box_repeat_chunks:
			if chunk.region_key == region:
				found_chunk = chunk
				break
	if not found_chunk:
		for chunk in tile_map3d._prism_chunks:
			if chunk.region_key == region:
				found_chunk = chunk
				break
	if not found_chunk:
		for chunk in tile_map3d._prism_repeat_chunks:
			if chunk.region_key == region:
				found_chunk = chunk
				break

	if found_chunk and found_chunk.multimesh.visible_instance_count > 0:
		var chunk_pos: Vector3 = found_chunk.position
		var first_tile_origin: Vector3 = found_chunk.multimesh.get_instance_transform(0).origin

		report += "\n  Chunk for this region:\n"
		report += "    Chunk Name: %s\n" % found_chunk.name
		report += "    Chunk Position: %s\n" % _vec3_str(chunk_pos)
		report += "    First Tile Transform Origin: %s\n" % _vec3_str(first_tile_origin)

		# Determine if transform is in local or world space
		# Local space: origin should be roughly 0-50 range
		# World space: origin should be close to grid_pos * grid_size
		var world_pos_expected: Vector3 = (grid_pos + Vector3(0.5, 0.5, 0.5)) * tile_map3d.grid_size
		var local_pos_expected: Vector3 = (expected_local + Vector3(0.5, 0.5, 0.5)) * tile_map3d.grid_size

		var dist_to_world: float = first_tile_origin.distance_to(world_pos_expected)
		var dist_to_local: float = first_tile_origin.distance_to(local_pos_expected)
		var is_world_space: bool = dist_to_world < 5.0
		var is_local_space: bool = dist_to_local < 5.0

		report += "\n  Coordinate Space Analysis:\n"
		report += "    World pos expected: %s (dist: %.2f)\n" % [_vec3_str(world_pos_expected), dist_to_world]
		report += "    Local pos expected: %s (dist: %.2f)\n" % [_vec3_str(local_pos_expected), dist_to_local]

		if is_world_space:
			report += "    Transform appears to be: WORLD SPACE\n"
			report += "    WARNING: Tiles in WORLD space but chunk at region origin!\n"
			report += "       This will cause tiles to appear OUTSIDE the chunk AABB.\n"
		elif is_local_space:
			report += "    Transform appears to be: LOCAL SPACE\n"
		else:
			report += "    Transform appears to be: UNKNOWN/NEITHER\n"
	else:
		report += "\n  (No matching chunk found for region %s)\n" % str(region)

	report += "\n"
	return report


## SECTION 7: Health Summary
static func _generate_health_summary(tile_map3d: TileMapLayer3D, placement_manager: TilePlacementManager) -> String:
	var report: String = "----------------------------------------------------------------------\n"
	report += " [7] HEALTH SUMMARY                                                  \n"
	report += "----------------------------------------------------------------------\n"

	var issues: Array[String] = []
	var warnings: Array[String] = []
	var ok_items: Array[String] = []

	# Check 1: Data integrity
	var storage_count: int = tile_map3d._tile_positions.size()
	var chunk_count: int = _count_visible_tiles_all_chunks(tile_map3d)
	if storage_count == chunk_count:
		ok_items.append("Tile counts match (storage=%d, chunks=%d)" % [storage_count, chunk_count])
	else:
		issues.append("Tile count MISMATCH (storage=%d, chunks=%d)" % [storage_count, chunk_count])

	# Check 2: Chunk positions
	var all_chunks: Array = []
	all_chunks.append_array(tile_map3d._quad_chunks)
	all_chunks.append_array(tile_map3d._triangle_chunks)
	all_chunks.append_array(tile_map3d._box_chunks)
	all_chunks.append_array(tile_map3d._box_repeat_chunks)
	all_chunks.append_array(tile_map3d._prism_chunks)
	all_chunks.append_array(tile_map3d._prism_repeat_chunks)

	var pos_mismatches: int = 0
	for chunk in all_chunks:
		var expected_pos: Vector3 = Vector3(
			float(chunk.region_key.x) * GlobalConstants.CHUNK_REGION_SIZE,
			float(chunk.region_key.y) * GlobalConstants.CHUNK_REGION_SIZE,
			float(chunk.region_key.z) * GlobalConstants.CHUNK_REGION_SIZE
		)
		if not chunk.position.is_equal_approx(expected_pos):
			pos_mismatches += 1

	if pos_mismatches == 0:
		ok_items.append("All chunks positioned correctly")
	else:
		issues.append("%d chunks have WRONG positions!" % pos_mismatches)

	# Check 3: AABBs
	var expected_aabb: AABB = GlobalConstants.CHUNK_LOCAL_AABB
	var aabb_mismatches: int = 0
	for chunk in all_chunks:
		if not _aabb_matches(chunk.custom_aabb, expected_aabb):
			aabb_mismatches += 1

	if aabb_mismatches == 0:
		ok_items.append("All AABBs set correctly")
	else:
		issues.append("%d chunks have WRONG AABBs!" % aabb_mismatches)

	# Check 4: Tiles outside AABB
	var tiles_outside: int = _count_tiles_outside_aabb(tile_map3d, all_chunks)
	if tiles_outside == 0:
		ok_items.append("All tiles within AABB bounds")
	else:
		issues.append("%d tiles OUTSIDE chunk AABB bounds!" % tiles_outside)

	# Print results
	for item in ok_items:
		report += "  [OK] %s\n" % item
	for warning in warnings:
		report += "  [WARN] %s\n" % warning
	for issue in issues:
		report += "  [ERROR] %s\n" % issue

	# Recommendation
	report += "\n"
	if issues.size() == 0:
		report += "  STATUS: HEALTHY\n"
	else:
		report += "  STATUS: ISSUES DETECTED\n\n"
		report += "  DIAGNOSIS:\n"
		if tiles_outside > 0:
			report += "    - Tiles are being placed in WORLD coordinates but chunks expect LOCAL.\n"
			report += "    - Check build_tile_transform() - it may be calling grid_to_world()\n"
			report += "      which adds +0.5 alignment offset and multiplies by grid_size.\n"
			report += "    - Solution: Use local grid positions relative to chunk region.\n"

	report += "\n"
	return report


## SECTION 8: Frustum Culling Diagnostics
static func _generate_frustum_culling_section(tile_map3d: TileMapLayer3D) -> String:
	var report: String = "----------------------------------------------------------------------\n"
	report += " [8] FRUSTUM CULLING DIAGNOSTICS                                     \n"
	report += "----------------------------------------------------------------------\n"

	# Collect all chunks
	var all_chunks: Array = []
	all_chunks.append_array(tile_map3d._quad_chunks)
	all_chunks.append_array(tile_map3d._triangle_chunks)
	all_chunks.append_array(tile_map3d._box_chunks)
	all_chunks.append_array(tile_map3d._box_repeat_chunks)
	all_chunks.append_array(tile_map3d._prism_chunks)
	all_chunks.append_array(tile_map3d._prism_repeat_chunks)

	if all_chunks.is_empty():
		report += "  (No chunks to analyze)\n\n"
		return report

	report += "\n  AABB CONFIGURATION:\n"
	report += "    Expected Local AABB: pos%s size%s\n" % [
		_vec3_str(GlobalConstants.CHUNK_LOCAL_AABB.position),
		_vec3_str(GlobalConstants.CHUNK_LOCAL_AABB.size)
	]
	report += "    Region Size: %.0f units\n" % GlobalConstants.CHUNK_REGION_SIZE
	report += "\n"

	# Show world-space AABB for each chunk
	report += "  CHUNK WORLD-SPACE AABBs (for frustum culling):\n"
	report += "  ─────────────────────────────────────────────────────────────────\n"

	var aabb_issues: int = 0
	for chunk in all_chunks:
		var chunk_pos: Vector3 = chunk.position
		var local_aabb: AABB = chunk.custom_aabb

		# Calculate world-space AABB (what Godot uses for frustum culling)
		var world_aabb_pos: Vector3 = chunk_pos + local_aabb.position
		var world_aabb_end: Vector3 = world_aabb_pos + local_aabb.size

		# Calculate expected world AABB based on region
		var region_origin: Vector3 = Vector3(
			float(chunk.region_key.x) * GlobalConstants.CHUNK_REGION_SIZE,
			float(chunk.region_key.y) * GlobalConstants.CHUNK_REGION_SIZE,
			float(chunk.region_key.z) * GlobalConstants.CHUNK_REGION_SIZE
		)
		var expected_world_pos: Vector3 = region_origin + GlobalConstants.CHUNK_LOCAL_AABB.position
		var expected_world_end: Vector3 = expected_world_pos + GlobalConstants.CHUNK_LOCAL_AABB.size

		var pos_ok: bool = world_aabb_pos.distance_to(expected_world_pos) < 1.0
		var end_ok: bool = world_aabb_end.distance_to(expected_world_end) < 1.0

		var status: String = "[OK]" if (pos_ok and end_ok) else "[ERROR]"
		if not (pos_ok and end_ok):
			aabb_issues += 1

		report += "    %s %s (Region %s)\n" % [status, chunk.name, str(chunk.region_key)]
		report += "        Chunk Position: %s\n" % _vec3_str(chunk_pos)
		report += "        Local AABB: pos%s size%s\n" % [_vec3_str(local_aabb.position), _vec3_str(local_aabb.size)]
		report += "        World AABB: %s to %s\n" % [_vec3_str(world_aabb_pos), _vec3_str(world_aabb_end)]

		if not (pos_ok and end_ok):
			report += "        EXPECTED:   %s to %s\n" % [_vec3_str(expected_world_pos), _vec3_str(expected_world_end)]
		report += "\n"

	# Summary
	report += "  ─────────────────────────────────────────────────────────────────\n"
	if aabb_issues == 0:
		report += "  [OK] All %d chunks have correct world-space AABBs\n" % all_chunks.size()
	else:
		report += "  [ERROR] %d chunks have INCORRECT world-space AABBs!\n" % aabb_issues
		report += "          Frustum culling will NOT work correctly.\n"

	# Check for AABB overlap (expected with boundary padding)
	report += "\n  AABB OVERLAP CHECK:\n"
	report += "    With boundary padding (-0.5 to +50.5), adjacent chunks WILL overlap\n"
	report += "    by ~1 unit. This is EXPECTED to prevent tile clipping at boundaries.\n"
	report += "    Consequence: When camera is near region boundary, BOTH adjacent\n"
	report += "    chunks may render even if only one has visible tiles.\n"

	report += "\n"
	return report


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

## Helper: Format Vector3 nicely
static func _vec3_str(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


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


## Counts visible tiles across all 6 chunk types
static func _count_visible_tiles_all_chunks(tile_map3d: TileMapLayer3D) -> int:
	var total: int = 0

	for chunk in tile_map3d._quad_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._triangle_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._box_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._box_repeat_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._prism_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._prism_repeat_chunks:
		if chunk and chunk.multimesh:
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


## Helper: Gets all chunks from a TileMapLayer3D node (all 6 types)
static func _get_all_chunks_from_node(tile_map3d: TileMapLayer3D) -> Array:
	var all_chunks: Array = []
	all_chunks.append_array(tile_map3d._quad_chunks)
	all_chunks.append_array(tile_map3d._triangle_chunks)
	all_chunks.append_array(tile_map3d._box_chunks)
	all_chunks.append_array(tile_map3d._box_repeat_chunks)
	all_chunks.append_array(tile_map3d._prism_chunks)
	all_chunks.append_array(tile_map3d._prism_repeat_chunks)
	return all_chunks


# =============================================================================
# PUBLIC AABB VALIDATION & DEBUG FUNCTIONS
# =============================================================================

## Validates and fixes all chunk AABBs. Returns count of chunks fixed.
## Call this after rebuilding chunks or if visibility issues are suspected.
##
## IMPORTANT: Chunks are positioned at their region's world origin.
## The custom_aabb must be LOCAL (CHUNK_LOCAL_AABB), NOT world-space.
## Godot computes world AABB as: chunk.position + custom_aabb for frustum culling.
##
## @param tile_map3d: The TileMapLayer3D node to validate
## @returns: Number of chunks that had incorrect AABBs and were fixed
static func validate_and_fix_chunk_aabbs(tile_map3d: TileMapLayer3D) -> int:
	var fixed_count: int = 0
	var expected_aabb: AABB = GlobalConstants.CHUNK_LOCAL_AABB
	var all_chunks: Array = _get_all_chunks_from_node(tile_map3d)

	for chunk in all_chunks:
		if chunk and not _aabb_matches(chunk.custom_aabb, expected_aabb):
			chunk.custom_aabb = expected_aabb
			fixed_count += 1

	if fixed_count > 0:
		push_warning("TileMapLayer3D: Fixed %d chunks with incorrect AABBs" % fixed_count)

	return fixed_count


## Prints diagnostic information about all chunk AABBs.
## Use this to debug visibility issues - shows which chunks have correct AABBs.
## @param tile_map3d: The TileMapLayer3D node to inspect
static func print_chunk_aabbs(tile_map3d: TileMapLayer3D) -> void:
	print("=" .repeat(80))
	print("CHUNK AABB DIAGNOSTIC REPORT")
	print("=" .repeat(80))
	print("TileMapLayer3D position: %s" % tile_map3d.global_position)
	print("")

	var all_chunks: Array = _get_all_chunks_from_node(tile_map3d)

	if all_chunks.is_empty():
		print("No chunks found.")
		print("=" .repeat(80))
		return

	var correct_count: int = 0
	var incorrect_count: int = 0
	var expected_aabb: AABB = GlobalConstants.CHUNK_LOCAL_AABB

	for chunk in all_chunks:
		if not chunk:
			continue
		var is_correct: bool = _aabb_matches(chunk.custom_aabb, expected_aabb)
		var status: String = "[OK]" if is_correct else "[WRONG]"

		if is_correct:
			correct_count += 1
		else:
			incorrect_count += 1

		print("%s %s: region=%s, pos=%s, aabb=%s" % [status, chunk.name, chunk.region_key, chunk.position, chunk.custom_aabb])
		if not is_correct:
			print("   Expected: %s" % expected_aabb)

	print("")
	print("Summary: %d correct, %d incorrect" % [correct_count, incorrect_count])
	print("=" .repeat(80))


## Verifies that all tiles are contained within their chunk's AABB.
## Returns the number of tiles outside their chunk's AABB (should be 0).
## @param tile_map3d: The TileMapLayer3D node to verify
## @returns: Number of tiles found outside their chunk's AABB (0 = all good)
static func verify_tiles_in_aabbs(tile_map3d: TileMapLayer3D) -> int:
	var errors: int = 0
	var all_chunks: Array = _get_all_chunks_from_node(tile_map3d)

	for chunk in all_chunks:
		if not chunk or not chunk.multimesh:
			continue
		for i in range(chunk.multimesh.visible_instance_count):
			var pos: Vector3 = chunk.multimesh.get_instance_transform(i).origin
			if not chunk.custom_aabb.has_point(pos):
				print("[ERROR] TILE OUTSIDE AABB! Chunk=%s, TilePos=%s, AABB=%s" % [
					chunk.name, pos, chunk.custom_aabb
				])
				errors += 1

	if errors == 0:
		print("[OK] All tiles are within their chunk AABBs")
	else:
		print("[ERROR] Found %d tiles outside their chunk AABBs" % errors)

	return errors
