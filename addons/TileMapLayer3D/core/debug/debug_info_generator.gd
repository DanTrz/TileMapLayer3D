@tool
class_name DebugInfoGenerator
extends RefCounted
## Generates diagnostic information for TileMapLayer3D nodes.


static func print_report(tile_map3d: TileMapLayer3D, placement_manager: TilePlacementManager) -> void:
	if not tile_map3d:
		push_warning("DebugInfoGenerator: No TileMapLayer3D provided")
		return
	print(generate_report(tile_map3d, placement_manager))


## Strict data-quality audit for the columnar storage model.
## This is read-only: it never repairs, rebuilds, or mutates runtime state.
static func validate_columnar_data_quality(tile_map3d: TileMapLayer3D, include_live_manager: bool = true) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var checks: Array[String] = []
	var stats: Dictionary = {}

	if tile_map3d == null:
		return {
			"valid": false,
			"quality": "CRITICAL",
			"score": 0,
			"errors": ["TileMapLayer3D is null"],
			"warnings": [],
			"checks": [],
			"stats": {}
		}

	var row_count: int = tile_map3d._tile_positions.size()
	var expected_uv_floats: int = row_count * 4
	var expected_atlas_coord_ints: int = row_count * tile_map3d.ATLAS_COORDS_STRIDE

	stats["row_count"] = row_count
	stats["lookup_count"] = tile_map3d._saved_tiles_lookup.size()
	stats["tile_ref_count"] = tile_map3d._tile_lookup.size()
	stats["region_count"] = tile_map3d.region_system._registry.size()
	stats["chunk_tile_count"] = _count_visible_tiles_all_chunks(tile_map3d)
	stats["spatial_index_count"] = 0
	stats["batch_depth"] = 0
	stats["pending_chunk_updates"] = 0
	stats["pending_chunk_cleanups"] = 0

	_validate_columnar_array_lengths(tile_map3d, row_count, expected_uv_floats, expected_atlas_coord_ints, errors, warnings, checks)
	_validate_columnar_sparse_indices(tile_map3d, row_count, errors, checks)

	var row_keys: Dictionary = _validate_columnar_rows_and_lookup(tile_map3d, row_count, errors, checks)
	_validate_columnar_regions(tile_map3d, row_keys, errors, warnings, checks)
	_validate_columnar_chunks_and_tile_refs(tile_map3d, row_keys, errors, warnings, checks)
	if include_live_manager:
		_validate_placement_manager_state(tile_map3d, row_keys, errors, warnings, checks, stats)

	var score: int = clampi(100 - errors.size() * 20 - warnings.size() * 5, 0, 100)
	var quality: String = "PASS"
	if errors.size() > 0:
		quality = "CRITICAL" if errors.size() >= 3 else "FAIL"
	elif warnings.size() > 0:
		quality = "WARN"

	stats["error_count"] = errors.size()
	stats["warning_count"] = warnings.size()

	return {
		"valid": errors.is_empty(),
		"quality": quality,
		"score": score,
		"errors": errors,
		"warnings": warnings,
		"checks": checks,
		"stats": stats
	}


static func generate_columnar_data_quality_report(tile_map3d: TileMapLayer3D, include_live_manager: bool = true) -> String:
	var result: Dictionary = validate_columnar_data_quality(tile_map3d, include_live_manager)
	var stats: Dictionary = result.get("stats", {})

	var report: String = ""
	report += "----------------------------------------------------------------------\n"
	report += " COLUMNAR DATA QUALITY AUDIT                                          \n"
	report += "----------------------------------------------------------------------\n"
	report += "  Quality: %s\n" % result.get("quality", "UNKNOWN")
	report += "  Score:   %d / 100\n" % int(result.get("score", 0))
	report += "  Valid:   %s\n" % ("YES" if result.get("valid", false) else "NO")
	report += "\n"
	report += "  Rows:        %d\n" % int(stats.get("row_count", 0))
	report += "  Lookup:      %d\n" % int(stats.get("lookup_count", 0))
	report += "  TileRefs:    %d\n" % int(stats.get("tile_ref_count", 0))
	report += "  Regions:     %d\n" % int(stats.get("region_count", 0))
	report += "  Chunk tiles: %d\n" % int(stats.get("chunk_tile_count", 0))
	report += "  SpatialIdx:  %d\n" % int(stats.get("spatial_index_count", 0))
	report += "  Batch depth: %d\n" % int(stats.get("batch_depth", 0))

	var checks: Array = result.get("checks", [])
	var errors: Array = result.get("errors", [])
	var warnings: Array = result.get("warnings", [])

	if not checks.is_empty():
		report += "\n  CHECKS:\n"
		for check in checks:
			report += "    - %s\n" % str(check)

	if errors.is_empty() and warnings.is_empty():
		report += "\n  No data-quality issues found.\n"
	else:
		if not errors.is_empty():
			report += "\n  ERRORS:\n"
			for error in errors:
				report += "    - %s\n" % str(error)
		if not warnings.is_empty():
			report += "\n  WARNINGS:\n"
			for warning in warnings:
				report += "    - %s\n" % str(warning)

	report += "----------------------------------------------------------------------\n"
	return report


static func print_columnar_data_quality_report(tile_map3d: TileMapLayer3D) -> Dictionary:
	var result: Dictionary = validate_columnar_data_quality(tile_map3d, true)
	print(generate_columnar_data_quality_report(tile_map3d, true))
	return result


static func _validate_columnar_array_lengths(
	tile_map3d: TileMapLayer3D,
	row_count: int,
	expected_uv_floats: int,
	expected_atlas_coord_ints: int,
	errors: Array[String],
	warnings: Array[String],
	checks: Array[String]
) -> void:
	var starting_errors: int = errors.size()
	if tile_map3d._tile_uv_rects.size() != expected_uv_floats:
		errors.append("_tile_uv_rects has %d floats; expected %d for %d rows" % [
			tile_map3d._tile_uv_rects.size(), expected_uv_floats, row_count
		])
	if tile_map3d._tile_flags.size() != row_count:
		errors.append("_tile_flags has %d entries; expected %d" % [tile_map3d._tile_flags.size(), row_count])
	if tile_map3d._tile_atlas_source_ids.size() != row_count:
		errors.append("_tile_atlas_source_ids has %d entries; expected %d" % [
			tile_map3d._tile_atlas_source_ids.size(), row_count
		])
	if tile_map3d._tile_atlas_coords.size() != expected_atlas_coord_ints:
		errors.append("_tile_atlas_coords has %d ints; expected %d" % [
			tile_map3d._tile_atlas_coords.size(), expected_atlas_coord_ints
		])
	if tile_map3d._tile_transform_indices.size() != row_count:
		errors.append("_tile_transform_indices has %d entries; expected %d" % [
			tile_map3d._tile_transform_indices.size(), row_count
		])
	if tile_map3d._tile_anim_indices.size() != row_count:
		errors.append("_tile_anim_indices has %d entries; expected %d" % [
			tile_map3d._tile_anim_indices.size(), row_count
		])

	if tile_map3d._tile_transform_data.size() % 5 != 0:
		errors.append("_tile_transform_data size %d is not divisible by 5" % tile_map3d._tile_transform_data.size())
	if tile_map3d._tile_anim_data.size() % 5 != 0:
		errors.append("_tile_anim_data size %d is not divisible by 5" % tile_map3d._tile_anim_data.size())

	if row_count == 0 and (tile_map3d._saved_tiles_lookup.size() > 0 or tile_map3d.region_system._registry.size() > 0):
		warnings.append("No columnar rows, but lookup or region registry still has entries")

	if errors.size() == starting_errors:
		checks.append("PASS column array lengths and packed payload strides")


static func _validate_columnar_sparse_indices(
	tile_map3d: TileMapLayer3D,
	row_count: int,
	errors: Array[String],
	checks: Array[String]
) -> void:
	var starting_errors: int = errors.size()
	var transform_entry_count: int = tile_map3d._tile_transform_data.size() / 5
	var anim_entry_count: int = tile_map3d._tile_anim_data.size() / 5

	for i in range(min(row_count, tile_map3d._tile_transform_indices.size())):
		var transform_idx: int = tile_map3d._tile_transform_indices[i]
		if transform_idx < -1:
			errors.append("Row %d has invalid transform index %d" % [i, transform_idx])
		elif transform_idx >= transform_entry_count:
			errors.append("Row %d transform index %d is out of range (%d entries)" % [
				i, transform_idx, transform_entry_count
			])

	for i in range(min(row_count, tile_map3d._tile_anim_indices.size())):
		var anim_idx: int = tile_map3d._tile_anim_indices[i]
		if anim_idx < -1:
			errors.append("Row %d has invalid animation index %d" % [i, anim_idx])
		elif anim_idx >= anim_entry_count:
			errors.append("Row %d animation index %d is out of range (%d entries)" % [
				i, anim_idx, anim_entry_count
			])

	if errors.size() == starting_errors:
		checks.append("PASS sparse transform and animation row indices")


static func _validate_columnar_rows_and_lookup(
	tile_map3d: TileMapLayer3D,
	row_count: int,
	errors: Array[String],
	checks: Array[String]
) -> Dictionary:
	var starting_errors: int = errors.size()
	var row_keys: Dictionary = {}

	for i in range(row_count):
		if i >= tile_map3d._tile_flags.size():
			continue

		var grid_pos: Vector3 = tile_map3d._tile_positions[i]
		var flags: int = tile_map3d._tile_flags[i]
		var orientation: int = flags & 0x1F
		var tile_key: int = GlobalUtil.make_tile_key(grid_pos, orientation)

		if row_keys.has(tile_key):
			errors.append("Duplicate tile_key %d generated by rows %d and %d" % [tile_key, int(row_keys[tile_key]), i])
		else:
			row_keys[tile_key] = i

		if not tile_map3d._saved_tiles_lookup.has(tile_key):
			errors.append("Row %d generated tile_key %d, but lookup has no entry" % [i, tile_key])
			continue

		var lookup_index: int = int(tile_map3d._saved_tiles_lookup[tile_key])
		if lookup_index != i:
			errors.append("Lookup for tile_key %d points to row %d, but generated row is %d" % [
				tile_key, lookup_index, i
			])

	for key in tile_map3d._saved_tiles_lookup.keys():
		var lookup_index: int = int(tile_map3d._saved_tiles_lookup[key])
		if lookup_index < 0 or lookup_index >= row_count:
			errors.append("Lookup key %s points to out-of-range row %d" % [str(key), lookup_index])
			continue
		if not row_keys.has(int(key)):
			errors.append("Lookup key %s has no matching generated row key" % str(key))

	if errors.size() == starting_errors:
		checks.append("PASS row keys and _saved_tiles_lookup are bijective")

	return row_keys


static func _validate_columnar_regions(
	tile_map3d: TileMapLayer3D,
	row_keys: Dictionary,
	errors: Array[String],
	warnings: Array[String],
	checks: Array[String]
) -> void:
	var starting_errors: int = errors.size()
	var starting_warnings: int = warnings.size()
	var region_membership: Dictionary = {}

	for packed_key in tile_map3d.region_system._registry.keys():
		var region: TerrainRegionChunk = tile_map3d.region_system._registry[packed_key]
		if region == null:
			errors.append("Region registry key %s has null region" % str(packed_key))
			continue

		if region.tile_keys.size() != region.columnar_indices.size():
			errors.append("Region %s has %d tile_keys but %d columnar_indices" % [
				str(region.region_key), region.tile_keys.size(), region.columnar_indices.size()
			])

		var limit: int = mini(region.tile_keys.size(), region.columnar_indices.size())
		for i in range(limit):
			var tile_key: int = int(region.tile_keys[i])
			var columnar_index: int = int(region.columnar_indices[i])

			if region_membership.has(tile_key):
				errors.append("Tile key %d appears in multiple region entries" % tile_key)
			region_membership[tile_key] = packed_key

			if not tile_map3d._saved_tiles_lookup.has(tile_key):
				errors.append("Region %s contains tile_key %d missing from saved lookup" % [str(region.region_key), tile_key])
				continue

			var lookup_index: int = int(tile_map3d._saved_tiles_lookup[tile_key])
			if lookup_index != columnar_index:
				errors.append("Region %s tile_key %d has columnar_index %d, lookup says %d" % [
					str(region.region_key), tile_key, columnar_index, lookup_index
				])

			if not row_keys.has(tile_key):
				errors.append("Region %s tile_key %d has no matching columnar row" % [str(region.region_key), tile_key])

			if lookup_index >= 0 and lookup_index < tile_map3d._tile_positions.size():
				var world_pos: Vector3 = GlobalUtil.grid_to_world(tile_map3d._tile_positions[lookup_index], tile_map3d.grid_size)
				var expected_packed: int = RegionSystem.pack(RegionSystem.resolve_region_key(world_pos))
				if int(packed_key) != expected_packed:
					errors.append("Region membership mismatch for tile_key %d: registered in %s, expected %s" % [
						tile_key,
						str(RegionSystem.unpack(int(packed_key))),
						str(RegionSystem.unpack(expected_packed))
					])

	for tile_key in row_keys.keys():
		if not region_membership.has(tile_key):
			warnings.append("Tile key %d has a columnar row but no region entry" % int(tile_key))

	if errors.size() == starting_errors and warnings.size() == starting_warnings:
		checks.append("PASS region tile keys and columnar indices match lookup")


static func _validate_columnar_chunks_and_tile_refs(
	tile_map3d: TileMapLayer3D,
	row_keys: Dictionary,
	errors: Array[String],
	warnings: Array[String],
	checks: Array[String]
) -> void:
	var starting_errors: int = errors.size()
	var starting_warnings: int = warnings.size()
	var chunk_membership: Dictionary = {}

	for tile_key in row_keys.keys():
		var tile_ref: TileMapLayer3D.TileRef = tile_map3d._tile_lookup.get(tile_key, null)
		if tile_ref == null:
			warnings.append("Tile key %d has columnar row but no runtime TileRef" % int(tile_key))
			continue

		var chunk: MultiMeshTileChunkBase = tile_map3d._get_chunk_by_ref(tile_ref)
		if chunk == null:
			errors.append("Tile key %d has TileRef but chunk lookup failed (mode=%d, repeat=%d, region=%d, chunk_index=%d)" % [
				int(tile_key), tile_ref.mesh_mode, tile_ref.texture_repeat_mode, tile_ref.region_key_packed, tile_ref.chunk_index
			])
			continue

		if not chunk.tile_refs.has(tile_key):
			errors.append("Tile key %d has TileRef but is missing from chunk.tile_refs" % int(tile_key))
			continue

		var chunk_instance: int = int(chunk.tile_refs[tile_key])
		if chunk_instance != tile_ref.instance_index:
			errors.append("Tile key %d TileRef instance %d differs from chunk.tile_refs instance %d" % [
				int(tile_key), tile_ref.instance_index, chunk_instance
			])

		if not chunk.instance_to_key.has(chunk_instance):
			errors.append("Tile key %d chunk instance %d missing from instance_to_key" % [int(tile_key), chunk_instance])
		elif int(chunk.instance_to_key[chunk_instance]) != int(tile_key):
			errors.append("Tile key %d chunk instance %d reverse maps to %s" % [
				int(tile_key), chunk_instance, str(chunk.instance_to_key[chunk_instance])
			])

	for chunk in _get_all_valid_chunks(tile_map3d):
		for tile_key in chunk.tile_refs.keys():
			if chunk_membership.has(tile_key):
				errors.append("Tile key %d appears in multiple chunks" % int(tile_key))
			chunk_membership[tile_key] = chunk

			if not row_keys.has(tile_key):
				errors.append("Chunk %s contains tile_key %d missing from columnar rows" % [chunk.name, int(tile_key)])

			var instance_index: int = int(chunk.tile_refs[tile_key])
			if instance_index < 0 or instance_index >= chunk.multimesh.visible_instance_count:
				errors.append("Chunk %s tile_key %d has out-of-range instance %d (visible=%d)" % [
					chunk.name, int(tile_key), instance_index, chunk.multimesh.visible_instance_count
				])
			elif not chunk.instance_to_key.has(instance_index):
				errors.append("Chunk %s instance %d for tile_key %d missing reverse lookup" % [
					chunk.name, instance_index, int(tile_key)
				])

	for tile_key in row_keys.keys():
		if not chunk_membership.has(tile_key):
			warnings.append("Tile key %d has columnar row but no chunk membership" % int(tile_key))

	if errors.size() == starting_errors and warnings.size() == starting_warnings:
		checks.append("PASS runtime TileRefs and chunk instance maps match columnar rows")


static func _validate_placement_manager_state(
	tile_map3d: TileMapLayer3D,
	row_keys: Dictionary,
	errors: Array[String],
	warnings: Array[String],
	checks: Array[String],
	stats: Dictionary
) -> void:
	var placement_manager: TilePlacementManager = tile_map3d._active_placement_manager
	if placement_manager == null:
		warnings.append("No active TilePlacementManager; SpatialIndex and batch state were not validated")
		return

	var starting_errors: int = errors.size()
	var starting_warnings: int = warnings.size()

	var spatial_keys: Array = placement_manager.get_spatial_index_tile_keys()
	stats["spatial_index_count"] = spatial_keys.size()

	var spatial_membership: Dictionary = {}
	for key in spatial_keys:
		var tile_key: int = int(key)
		if spatial_membership.has(tile_key):
			errors.append("SpatialIndex contains duplicate tile_key %d" % tile_key)
		spatial_membership[tile_key] = true
		if not row_keys.has(tile_key):
			errors.append("SpatialIndex contains tile_key %d missing from columnar rows" % tile_key)

	for tile_key in row_keys.keys():
		if not spatial_membership.has(int(tile_key)):
			errors.append("Columnar tile_key %d missing from SpatialIndex" % int(tile_key))

	var batch_state: Dictionary = placement_manager.get_batch_debug_state()
	stats["batch_depth"] = int(batch_state.get("depth", 0))
	stats["pending_chunk_updates"] = int(batch_state.get("pending_updates", 0))
	stats["pending_chunk_cleanups"] = int(batch_state.get("pending_cleanups", 0))

	if stats["batch_depth"] != 0:
		errors.append("TilePlacementManager batch depth is %d outside an active operation" % stats["batch_depth"])
	if stats["pending_chunk_updates"] != 0:
		errors.append("TilePlacementManager has %d pending chunk updates after operation" % stats["pending_chunk_updates"])
	if stats["pending_chunk_cleanups"] != 0:
		errors.append("TilePlacementManager has %d pending chunk cleanups after operation" % stats["pending_chunk_cleanups"])

	if errors.size() == starting_errors and warnings.size() == starting_warnings:
		checks.append("PASS SpatialIndex and batch state match columnar rows")


static func _get_all_valid_chunks(tile_map3d: TileMapLayer3D) -> Array[MultiMeshTileChunkBase]:
	var result: Array[MultiMeshTileChunkBase] = []
	for chunk in tile_map3d._get_all_chunks():
		if chunk != null and is_instance_valid(chunk) and chunk is MultiMeshTileChunkBase:
			result.append(chunk)
	return result


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

	# SECTION 3: Per-Chunk Detailed Analysis 
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

	var debug_tex: Texture2D = TileAtlasResolver.get_active_texture(tile_map3d.settings) if tile_map3d.settings else null
	if debug_tex:
		var path_str: String = debug_tex.resource_path.get_file() if debug_tex.resource_path else "<embedded>"
		report += "  Tileset: %s (%dx%d)\n" % [path_str, debug_tex.get_width(), debug_tex.get_height()]
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
	var arch_regions: int = tile_map3d._chunk_registry_arch_corner.size()
	var arch_flat_regions: int = tile_map3d._chunk_registry_arch.size()
	var arch_i_regions: int = tile_map3d._chunk_registry_arch_i.size()
	var arch_corner_i_regions: int = tile_map3d._chunk_registry_arch_corner_i.size()
	var arch_corner_cap_regions: int = tile_map3d._chunk_registry_arch_corner_cap.size()
	var arch_corner_cap_i_regions: int = tile_map3d._chunk_registry_arch_corner_cap_i.size()
	var arch_corner_cap_duo_regions: int = tile_map3d._chunk_registry_arch_corner_cap_duo.size()

	report += "  Quad Registry:         %d regions, %d chunks\n" % [quad_regions, tile_map3d._quad_chunks.size()]
	report += "  Triangle Registry:     %d regions, %d chunks\n" % [tri_regions, tile_map3d._triangle_chunks.size()]
	report += "  Box Registry:          %d regions, %d chunks\n" % [box_regions, tile_map3d._box_chunks.size()]
	report += "  Box-Repeat Registry:   %d regions, %d chunks\n" % [box_repeat_regions, tile_map3d._box_repeat_chunks.size()]
	report += "  Prism Registry:        %d regions, %d chunks\n" % [prism_regions, tile_map3d._prism_chunks.size()]
	report += "  Prism-Repeat Registry: %d regions, %d chunks\n" % [prism_repeat_regions, tile_map3d._prism_repeat_chunks.size()]
	report += "  Arch-Corner Registry:  %d regions, %d chunks\n" % [arch_regions, tile_map3d._arch_corner_chunks.size()]
	report += "  Arch Registry:         %d regions, %d chunks\n" % [arch_flat_regions, tile_map3d._arch_chunks.size()]
	report += "  Arch-I Registry:       %d regions, %d chunks\n" % [arch_i_regions, tile_map3d._arch_i_chunks.size()]
	report += "  Arch-Corner-I Registry:%d regions, %d chunks\n" % [arch_corner_i_regions, tile_map3d._arch_corner_i_chunks.size()]
	report += "  Arch-Corner-Cap Registry:%d regions, %d chunks\n" % [arch_corner_cap_regions, tile_map3d._arch_corner_cap_chunks.size()]
	report += "  Arch-Corner-Cap-I Registry:%d regions, %d chunks\n" % [arch_corner_cap_i_regions, tile_map3d._arch_corner_cap_i_chunks.size()]
	report += "  Arch-Corner-Cap-Duo Registry:%d regions, %d chunks\n" % [arch_corner_cap_duo_regions, tile_map3d._arch_corner_cap_duo_chunks.size()]

	var total_regions: int = quad_regions + tri_regions + box_regions + box_repeat_regions + prism_regions + prism_repeat_regions + arch_regions + arch_flat_regions + arch_i_regions + arch_corner_i_regions + arch_corner_cap_regions + arch_corner_cap_i_regions + arch_corner_cap_duo_regions
	var total_chunks: int = _count_all_chunks(tile_map3d)
	report += "  -------------------------------------\n"
	report += "  TOTAL: %d regions, %d chunks\n" % [total_regions, total_chunks]
	report += "\n"
	return report


## SECTION 3: Per-Chunk Detailed Analysis
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
	for chunk in tile_map3d._arch_corner_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_ARCH_CORNER"})
	for chunk in tile_map3d._arch_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_ARCH"})
	for chunk in tile_map3d._arch_i_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_ARCH_I"})
	for chunk in tile_map3d._arch_corner_i_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_ARCH_CORNER_I"})
	for chunk in tile_map3d._arch_corner_cap_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_ARCH_CORNER_CAP"})
	for chunk in tile_map3d._arch_corner_cap_i_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_ARCH_CORNER_CAP_I"})
	for chunk in tile_map3d._arch_corner_cap_duo_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_ARCH_CORNER_CAP_DUO"})
	for chunk in tile_map3d._arch_corner_c_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_ARCH_CORNER_C"})
	for chunk in tile_map3d._arch_corner_c_i_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_ARCH_CORNER_C_I"})
	for chunk in tile_map3d._arch_corner_s_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_ARCH_CORNER_S"})
	for chunk in tile_map3d._arch_corner_s_i_chunks:
		chunk_data.append({"chunk": chunk, "type": "FLAT_ARCH_CORNER_S_I"})

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
	var expected_pos: Vector3 = RegionSystem.region_key_to_world_origin(chunk.region_key)
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
	var expected_aabb: AABB = RegionSystem.chunk_local_aabb()
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
	if not found_chunk:
		for chunk in tile_map3d._arch_corner_chunks:
			if chunk.region_key == region:
				found_chunk = chunk
				break
	if not found_chunk:
		for chunk in tile_map3d._arch_chunks:
			if chunk.region_key == region:
				found_chunk = chunk
				break
	if not found_chunk:
		for chunk in tile_map3d._arch_i_chunks:
			if chunk.region_key == region:
				found_chunk = chunk
				break
	if not found_chunk:
		for chunk in tile_map3d._arch_corner_i_chunks:
			if chunk.region_key == region:
				found_chunk = chunk
				break
	if not found_chunk:
		for chunk in tile_map3d._arch_corner_cap_chunks:
			if chunk.region_key == region:
				found_chunk = chunk
				break
	if not found_chunk:
		for chunk in tile_map3d._arch_corner_cap_i_chunks:
			if chunk.region_key == region:
				found_chunk = chunk
				break
	if not found_chunk:
		for chunk in tile_map3d._arch_corner_cap_duo_chunks:
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
	all_chunks.append_array(tile_map3d._arch_corner_chunks)
	all_chunks.append_array(tile_map3d._arch_chunks)
	all_chunks.append_array(tile_map3d._arch_i_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_i_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_cap_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_cap_i_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_cap_duo_chunks)

	var pos_mismatches: int = 0
	for chunk in all_chunks:
		var expected_pos: Vector3 = RegionSystem.region_key_to_world_origin(chunk.region_key)
		if not chunk.position.is_equal_approx(expected_pos):
			pos_mismatches += 1

	if pos_mismatches == 0:
		ok_items.append("All chunks positioned correctly")
	else:
		issues.append("%d chunks have WRONG positions!" % pos_mismatches)

	# Check 3: AABBs
	var expected_aabb: AABB = RegionSystem.chunk_local_aabb()
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
	all_chunks.append_array(tile_map3d._arch_corner_chunks)
	all_chunks.append_array(tile_map3d._arch_chunks)
	all_chunks.append_array(tile_map3d._arch_i_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_i_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_cap_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_cap_i_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_cap_duo_chunks)

	if all_chunks.is_empty():
		report += "  (No chunks to analyze)\n\n"
		return report

	report += "\n  AABB CONFIGURATION:\n"
	var _chunk_local_aabb: AABB = RegionSystem.chunk_local_aabb()
	report += "    Expected Local AABB: pos%s size%s\n" % [
		_vec3_str(_chunk_local_aabb.position),
		_vec3_str(_chunk_local_aabb.size)
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
		var region_origin: Vector3 = RegionSystem.region_key_to_world_origin(chunk.region_key)
		var chunk_local_aabb: AABB = RegionSystem.chunk_local_aabb()
		var expected_world_pos: Vector3 = region_origin + chunk_local_aabb.position
		var expected_world_end: Vector3 = expected_world_pos + chunk_local_aabb.size

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


# --- Helper Functions ---

static func _vec3_str(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


static func _aabb_matches(a: AABB, b: AABB, tolerance: float = 0.1) -> bool:
	return a.position.distance_to(b.position) < tolerance and a.size.distance_to(b.size) < tolerance


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
	for chunk in tile_map3d._arch_corner_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._arch_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._arch_i_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._arch_corner_i_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._arch_corner_cap_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._arch_corner_cap_i_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count
	for chunk in tile_map3d._arch_corner_cap_duo_chunks:
		if chunk and chunk.multimesh:
			total += chunk.multimesh.visible_instance_count

	return total


static func _count_all_chunks(tile_map3d: TileMapLayer3D) -> int:
	return (
		tile_map3d._quad_chunks.size() +
		tile_map3d._triangle_chunks.size() +
		tile_map3d._box_chunks.size() +
		tile_map3d._box_repeat_chunks.size() +
		tile_map3d._prism_chunks.size() +
		tile_map3d._prism_repeat_chunks.size() +
		tile_map3d._arch_corner_chunks.size() +
		tile_map3d._arch_chunks.size() +
		tile_map3d._arch_i_chunks.size() +
		tile_map3d._arch_corner_i_chunks.size() +
		tile_map3d._arch_corner_cap_chunks.size() +
		tile_map3d._arch_corner_cap_i_chunks.size() +
		tile_map3d._arch_corner_cap_duo_chunks.size()
	)


static func _get_all_chunks_from_node(tile_map3d: TileMapLayer3D) -> Array:
	var all_chunks: Array = []
	all_chunks.append_array(tile_map3d._quad_chunks)
	all_chunks.append_array(tile_map3d._triangle_chunks)
	all_chunks.append_array(tile_map3d._box_chunks)
	all_chunks.append_array(tile_map3d._box_repeat_chunks)
	all_chunks.append_array(tile_map3d._prism_chunks)
	all_chunks.append_array(tile_map3d._prism_repeat_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_chunks)
	all_chunks.append_array(tile_map3d._arch_chunks)
	all_chunks.append_array(tile_map3d._arch_i_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_i_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_cap_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_cap_i_chunks)
	all_chunks.append_array(tile_map3d._arch_corner_cap_duo_chunks)
	return all_chunks


# --- Public Aabb Validation and Debug ---

## Validates and fixes all chunk AABBs. Returns count of chunks fixed.
## custom_aabb must be LOCAL (RegionSystem.chunk_local_aabb()), not world-space.
static func validate_and_fix_chunk_aabbs(tile_map3d: TileMapLayer3D) -> int:
	var fixed_count: int = 0
	var expected_aabb: AABB = RegionSystem.chunk_local_aabb()
	var all_chunks: Array = _get_all_chunks_from_node(tile_map3d)

	for chunk in all_chunks:
		if chunk and not _aabb_matches(chunk.custom_aabb, expected_aabb):
			chunk.custom_aabb = expected_aabb
			fixed_count += 1

	if fixed_count > 0:
		push_warning("TileMapLayer3D: Fixed %d chunks with incorrect AABBs" % fixed_count)

	return fixed_count


## Prints diagnostic information about all chunk AABBs.
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
	var expected_aabb: AABB = RegionSystem.chunk_local_aabb()

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
