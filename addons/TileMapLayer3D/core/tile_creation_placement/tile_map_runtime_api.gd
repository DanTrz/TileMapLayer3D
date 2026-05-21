class_name TileMapRuntimeAPI extends RefCounted

var _tile_map: TileMapLayer3D
var _placement_manager: TilePlacementManager

const ORIENTATION :GlobalUtil.TileOrientation = GlobalUtil.TileOrientation
const ANY_ORIENTATION: int = -1
const BASE_ORIENTATIONS: Array[GlobalUtil.TileOrientation] = [
	GlobalUtil.TileOrientation.FLOOR,
	GlobalUtil.TileOrientation.CEILING,
	GlobalUtil.TileOrientation.WALL_NORTH,
	GlobalUtil.TileOrientation.WALL_SOUTH,
	GlobalUtil.TileOrientation.WALL_EAST,
	GlobalUtil.TileOrientation.WALL_WEST,
]
const ALL_ORIENTATIONS: Array[GlobalUtil.TileOrientation] = [
	GlobalUtil.TileOrientation.FLOOR,
	GlobalUtil.TileOrientation.CEILING,
	GlobalUtil.TileOrientation.WALL_NORTH,
	GlobalUtil.TileOrientation.WALL_SOUTH,
	GlobalUtil.TileOrientation.WALL_EAST,
	GlobalUtil.TileOrientation.WALL_WEST,
	GlobalUtil.TileOrientation.FLOOR_TILT_POS_X,
	GlobalUtil.TileOrientation.FLOOR_TILT_NEG_X,
	GlobalUtil.TileOrientation.CEILING_TILT_POS_X,
	GlobalUtil.TileOrientation.CEILING_TILT_NEG_X,
	GlobalUtil.TileOrientation.WALL_NORTH_TILT_POS_Y,
	GlobalUtil.TileOrientation.WALL_NORTH_TILT_NEG_Y,
	GlobalUtil.TileOrientation.WALL_NORTH_TILT_POS_X,
	GlobalUtil.TileOrientation.WALL_NORTH_TILT_NEG_X,
	GlobalUtil.TileOrientation.WALL_SOUTH_TILT_POS_Y,
	GlobalUtil.TileOrientation.WALL_SOUTH_TILT_NEG_Y,
	GlobalUtil.TileOrientation.WALL_SOUTH_TILT_POS_X,
	GlobalUtil.TileOrientation.WALL_SOUTH_TILT_NEG_X,
	GlobalUtil.TileOrientation.WALL_EAST_TILT_POS_X,
	GlobalUtil.TileOrientation.WALL_EAST_TILT_NEG_X,
	GlobalUtil.TileOrientation.WALL_EAST_TILT_POS_Y,
	GlobalUtil.TileOrientation.WALL_EAST_TILT_NEG_Y,
	GlobalUtil.TileOrientation.WALL_WEST_TILT_POS_X,
	GlobalUtil.TileOrientation.WALL_WEST_TILT_NEG_X,
	GlobalUtil.TileOrientation.WALL_WEST_TILT_POS_Y,
	GlobalUtil.TileOrientation.WALL_WEST_TILT_NEG_Y,
]

func _init(tile_map: TileMapLayer3D) -> void:
	_tile_map = tile_map
	_placement_manager = TilePlacementManager.new()
	_placement_manager.tile_map_layer3d_root = tile_map
	_tile_map._active_placement_manager = _placement_manager
	_sync_settings()


## Sync placement-manager state from the live TileMapLayerSettings resource.
## Called at the start of every public mutator so settings changes after init
## are honored (e.g. user updates grid_snap_size at runtime).
func _sync_settings() -> void:
	_placement_manager.grid_size = _tile_map.settings.grid_size
	_placement_manager.grid_snap_size = _tile_map.settings.grid_snap_size
	_placement_manager.tileset_texture = TileAtlasResolver.get_active_texture(_tile_map.settings)
	_placement_manager.current_depth_scale = _tile_map.settings.current_depth_scale
	_placement_manager.current_texture_repeat_mode = _tile_map.settings.texture_repeat_mode
	_placement_manager.current_depth_growth_mode = _tile_map.settings.depth_growth_mode
	_placement_manager.current_freeze_uv = _tile_map.settings.freeze_uv_on_rotation


## Place one tile from a world-space point.
## Coordinate conversion and snapping happen internally.
## [param orientation] — pass a value from [code]TileMapRuntimeAPI.ORIENTATION[/code] (e.g. [code]ORIENTATION.FLOOR[/code]).
func place_tile(world_pos: Vector3, uv_rect: Rect2, orientation: int = ORIENTATION.FLOOR, tile_info: PlacedTileInfo = null) -> bool:
	_sync_settings()

	return RunTimeAPIHelper._place_tile_at_storage(
		RunTimeAPIHelper._world_to_storage_grid(_tile_map, _placement_manager, world_pos),
		uv_rect, orientation, tile_info,_tile_map, _placement_manager)

## Erase one tile from a world-space point and exact orientation.
## Use find_tile(world_pos, ANY_ORIENTATION) first if the orientation is unknown.
func erase_tile(world_pos: Vector3, orientation: int = ORIENTATION.FLOOR) -> bool:
	_sync_settings()
	return RunTimeAPIHelper._erase_tile_at_storage(
		RunTimeAPIHelper._world_to_storage_grid(_tile_map, _placement_manager, world_pos),
		orientation, _tile_map, _placement_manager)

## Place an oriented rectangular area from a world-space anchor.
## This is the main high-level runtime building API.
## Pass an [RuntimeAPIAreaOptions] instance to control anchor, batching, overwrite, and per-tile properties.
func place_area(anchor_world: Vector3, orientation: int, size: Vector2i, uv_rect: Rect2, options: RuntimeAPIAreaOptions = null) -> Dictionary:
	_sync_settings()
	var result: Dictionary = RunTimeAPIHelper._new_result()
	if not RunTimeAPIHelper._validate_area_args(result, "place_area", orientation, size):
		return result

	var anchor_snapped_grid: Vector3 = RunTimeAPIHelper._area_anchor_snapped_grid(
		_tile_map, _placement_manager, anchor_world, orientation, size, options)
	var tile_info: PlacedTileInfo = options.tile_info if options != null else null
	var should_batch: bool = options.batch if options != null else true
	var overwrite: bool = options.overwrite if options != null else true

	result["anchor_grid"] = anchor_snapped_grid
	if should_batch:
		begin_batch()

	for snapped_grid_pos: Vector3 in RunTimeAPIHelper._area_snapped_grid_positions(anchor_snapped_grid, orientation, size):
		var storage_pos: Vector3 = RunTimeAPIHelper._snapped_grid_to_storage(_placement_manager, snapped_grid_pos, orientation)
		var tile_key: int = GlobalUtil.make_tile_key(storage_pos, orientation)
		if not overwrite and (_tile_map.has_tile(tile_key) or _tile_map.has_vertex_corners(tile_key)):
			result["skipped"] += 1
			continue
		if RunTimeAPIHelper._place_tile_at_storage(storage_pos, uv_rect, orientation, tile_info, _tile_map, _placement_manager):
			result["placed"] += 1
			result["tile_keys"].append(tile_key)
			var data: PlacedTileInfo = RunTimeAPIHelper._tile_data_for_snapped_grid(
				_tile_map, _placement_manager, snapped_grid_pos, orientation)
			if data != null:
				result["tiles"].append(data)
		else:
			result["skipped"] += 1

	if should_batch:
		end_batch()
	return result

## Erase an oriented rectangular area from a world-space anchor.
## Uses the same orientation, size, and anchor semantics as place_area().
func erase_area(anchor_world: Vector3, orientation: int, size: Vector2i, options: RuntimeAPIAreaOptions = null) -> Dictionary:
	_sync_settings()
	var result: Dictionary = RunTimeAPIHelper._new_result()
	if not RunTimeAPIHelper._validate_area_args(result, "erase_area", orientation, size):
		return result

	var anchor_snapped_grid: Vector3 = RunTimeAPIHelper._area_anchor_snapped_grid(
		_tile_map, _placement_manager, anchor_world, orientation, size, options)
	var should_batch: bool = options.batch if options != null else true

	result["anchor_grid"] = anchor_snapped_grid
	if should_batch:
		begin_batch()

	for snapped_grid_pos: Vector3 in RunTimeAPIHelper._area_snapped_grid_positions(anchor_snapped_grid, orientation, size):
		var storage_pos: Vector3 = RunTimeAPIHelper._snapped_grid_to_storage(_placement_manager, snapped_grid_pos, orientation)
		var tile_key: int = GlobalUtil.make_tile_key(storage_pos, orientation)
		if RunTimeAPIHelper._erase_tile_at_storage(storage_pos, orientation, _tile_map, _placement_manager):
			result["erased"] += 1
			result["tile_keys"].append(tile_key)
		else:
			result["skipped"] += 1

	if should_batch:
		end_batch()
	return result

## Find tile data at a world-space point.
## Pass an exact orientation for a specific lookup, or ANY_ORIENTATION (-1) to
## search the six base orientations. Returned data is enriched with tile_key,
## snapped_grid_position, and world_position.
func find_tile(world_pos: Vector3, orientation: int = ANY_ORIENTATION, tolerance_cells: int = 0) -> PlacedTileInfo:
	_sync_settings()
	return RunTimeAPIHelper.find_tile(_tile_map, _placement_manager, world_pos, orientation, tolerance_cells)

## Raycast from the world and return the first tile hit as PlacedTileInfo.
## Returns null if no tile was hit.
func get_first_tile_from_raycast(ray_origin: Vector3, ray_dir: Vector3, max_distance:float = INF) -> PlacedTileInfo:
	return SmartSelectManager.pick_tile_at(ray_origin, ray_dir, _tile_map, max_distance)

## Convert a world-space point to a snapped, orientation-aware grid tile-cell position.
## Convert the a world position into a grid-aligned integer/half-integer cell coordinate. This snaps the raw float position to the nearest valid tile center on grid, aligned to the given orientation.
## Usually used with grid_to_world_snapped()
func world_to_grid_snapped(world_pos: Vector3, orientation: int = ANY_ORIENTATION) -> Vector3:
	_sync_settings()
	return RunTimeAPIHelper.world_to_snapped_grid(_tile_map, _placement_manager, world_pos, orientation)


## Companion to world_to_grid_snapped(). Converts a snapped grid tile-cell position
## back to a world-space anchor suitable for place_tile / place_area / find_tile.
## Returns a world position that is "grid-aligned" and snapped to grid, so it is guaranteed to land on a valid tile center for that orientation.
func grid_to_world_snapped(snapped_grid_pos: Vector3, orientation: int = ANY_ORIENTATION) -> Vector3:
	_sync_settings()
	return RunTimeAPIHelper.snapped_grid_to_world(_tile_map, _placement_manager, snapped_grid_pos, orientation)


## Defer GPU MultiMesh sync for bulk operations.
## Call before placing many tiles, then call "end_batch" when done.
## Supports nesting — each begin must have a matching end.
func begin_batch() -> void:
	_placement_manager.begin_batch_update()


## Flush pending GPU updates after a begin_batch() call
func end_batch() -> void:
	_placement_manager.end_batch_update()


## Highlight a tile at a world position. Pass ANY_ORIENTATION (-1) to search the
## six base orientations. Returns true if a tile was found and highlighted.
func highlight_tile(world_pos: Vector3, orientation: int = ANY_ORIENTATION) -> bool:
	var data: PlacedTileInfo = find_tile(world_pos, orientation)
	if data == null:
		return false
	_tile_map.highlight_tiles([data.tile_key])
	return true


## Highlight an oriented rectangular tile area from a world-space anchor.
## Returns the number of tile keys highlighted (does not check that tiles exist
## at those keys — matches existing get_area_tile_keys() semantics).
func highlight_area(anchor_world: Vector3, orientation: int, size: Vector2i,
		options: RuntimeAPIAreaOptions = null) -> int:
	_sync_settings()
	var tile_keys: Array[int] = RunTimeAPIHelper.get_area_tile_keys(
		_tile_map, _placement_manager, anchor_world, orientation, size, options)
	if tile_keys.is_empty():
		return 0
	_tile_map.highlight_tiles(tile_keys)
	return tile_keys.size()


## Clear all runtime tile highlights.
func clear_highlights() -> void:
	_tile_map.clear_highlights()

## Bake and hot-swap collision for one TerrainRegionChunk based on the region for the tile.
## Get region_chunk from PlacedTileInfo.terrain_region_chunk after placing or erasing a tile.
## Coroutine: `await runtime_api.set_collision_for_region(tile_info, ...)`.
## RegionBaker runs the merge on a WorkerThreadPool task so the main thread keeps
## rendering during the bake — only the final shape build + attach happen on the
## main thread (~30 ms for a large region).
## Returns false only on error. Vertex-edited tiles bake every region they touch.
func set_collision_for_region(tile_info: PlacedTileInfo, alpha_aware: bool = false, backface_collision: bool = false) -> bool:
	if tile_info == null:
		return false
	var options: RegionBakeOptions = RegionBakeOptions.new()
	options.alpha_aware = alpha_aware
	options.backface_collision = backface_collision

	# Vertex-edited tiles aren't in columnar storage — they can straddle regions
	# via edited corners, so refresh every region their corners touch.
	if tile_info.terrain_region_chunk == null and tile_info.tile_key >= 0 \
			and _tile_map.has_vertex_corners(tile_info.tile_key):
		var regions: Array[TerrainRegionChunk] = TileMeshMerger.get_collision_regions_for_vertex_tile(
			_tile_map, tile_info.tile_key)
		var any_ok: bool = false
		for vertex_region: TerrainRegionChunk in regions:
			# RegionBaker.bake_collision returns null on empty region — that's a
			# valid success (shape cleared). The only true failure is a push_error.
			await RegionBaker.bake_collision(_tile_map, vertex_region, options)
			any_ok = true
		return any_ok

	await RegionBaker.bake_collision(_tile_map, tile_info.terrain_region_chunk, options)
	return true

## Return runtime settings and per-orientation diagnostics for an optional world point.
## Intended for debug UI / prints.
func get_debug_info(world_pos: Variant = null) -> Dictionary:
	return RunTimeAPIHelper.get_runtime_debug_info(_tile_map, _placement_manager, world_pos)

## Returns the TileData of the tile's bound atlas cell, or null for freeform tiles, or unknown cells.
## Uses the TileMapLayer3D "tile_key" to find the correspondent TileData object from the TileSetAtlasSource. This is the main entry point for runtime queries of atlas-side data like terrain and custom layers.
## TileData is a built-in Godot resource type that gives access to terrain, custom data layers, and information for a single tile in a TileSet
func get_tile_data_from_key(tile_key: int) -> TileData:
	var binding: Dictionary = RunTimeAPIHelper.get_tile_atlas_binding(_tile_map, tile_key)
	if binding.is_empty() or binding["is_freeform"]:
		return null
	var atlas: TileSetAtlasSource = RunTimeAPIHelper.get_atlas_source(_tile_map, int(binding["source_id"]))
	if atlas == null:
		return null
	var coords: Vector2i = binding["coords"]
	if not atlas.has_tile(coords):
		return null
	return atlas.get_tile_data(coords, 0)


## Returns the unified TileSet resource for read-only inspection (terrains, sources,
## custom data layers, etc.). Returns null if no TileSet has been configured.
func get_tileset() -> TileSet:
	if _tile_map.settings == null:
		return null
	return _tile_map.settings.tileset


## Convert a TileSet atlas cell coordinate to the pixel-space Rect2 used by this system.
## Useful for inspecting or caching the UV before calling swap_tile_texture().
func atlas_coord_to_uv_rect(atlas_coords: Vector2i, source_id: int = -1) -> Rect2:
	_sync_settings()
	var resolved_source: int = source_id if source_id >= 0 else _tile_map.settings.active_source_id
	return TileAtlasResolver.get_uv_rect_for_coords(_tile_map.settings, resolved_source, atlas_coords)


## Swap a placed tile's rendered texture to a different atlas cell at runtime.
## Pair with get_tile_data_from_key(tile_key) + TileData.get_custom_data() to read target coords.
## [param source_id] defaults to the active source when -1.
## Returns false if the tile does not exist or the atlas coords cannot be resolved.
func swap_tile_texture(tile_info: PlacedTileInfo, use_default_data_variant: bool = true, custom_atlas_coords: Vector2i = Vector2i(-1, -1),  ) -> bool:
	_sync_settings()
	var resolved_source:int = tile_info.atlas_source_id if tile_info.atlas_source_id else _tile_map.settings.active_source_id

	if use_default_data_variant:
		var variant_tile_data: Vector2i = get_variant_tile_data(tile_info.tile_key)
		custom_atlas_coords = variant_tile_data if variant_tile_data != null else custom_atlas_coords

	var new_uv: Rect2 = TileAtlasResolver.get_uv_rect_for_coords(_tile_map.settings, resolved_source, custom_atlas_coords)
	if not new_uv.has_area():
		push_error("TileMapRuntimeAPI.swap_tile_texture: could not resolve UV for coords %s (source %d)" % [custom_atlas_coords, resolved_source])
		return false

	if custom_atlas_coords == Vector2i(-1, -1):
		push_error("TileMapRuntimeAPI.swap_tile_texture: invalid atlas coords %s" % custom_atlas_coords)
		return false

	# print("Set new texture from atlas coords %s to new atlas coords %s  / tile_key %s (grid_pos %s)" % [tile_info.atlas_coords, custom_atlas_coords, tile_info.tile_key, tile_info.grid_position])
	return _tile_map.update_tile_uv(tile_info.tile_key, new_uv, resolved_source, custom_atlas_coords)

## Swap textures on all tiles in a group in one call.
## [param tile_info] — PlacedTileInfo of the sampled tile (from find_tile / get_first_tile_from_raycast).
##   Provides grid_position, orientation, and atlas_coords — no secondary lookup needed.
## [param collection_tiles_array] — atlas coords of every tile in the group
##   (read from the "CollectionTiles" custom data layer on the sampled tile).
##   Each entry's delta from the primary atlas_coords is used as the grid offset to find that member directly.
##   Every member must have a "VariantTile" (Vector2i) custom data layer with its swap-target atlas coords.
## [param use_default_collection_tiles] — Whether to use default collection tiles if the tile doesn't have them.
## [param source_id] defaults to the active source when -1.
func swap_tile_collection_texture(tile_info: PlacedTileInfo, follow_chain:bool = false, max_chain_steps: int = -1, step_change_time: float = 1.5) -> bool:
	_sync_settings()
	
	var collection_tile_data: PackedVector2Array = get_collection_tile_data(tile_info.tile_key)
	if collection_tile_data.is_empty() or collection_tile_data == null:
		# push_warning("Cannot Get any CollectionTiles from tile key: ", tile_info.tile_key,  " at Grid: ", tile_info.grid_position	)
		return false
	
	# print("NEW: swap_tile_collection_texture => TileColecction => " , collection_tile_data, " MaxSteps: ", max_chain_steps)

	var swap_count: int = 0
	var new_tile_key: int = -1
	var new_coords:Vector2i = Vector2i(-1, -1)
	var tile_info_updated: PlacedTileInfo = null

	for tile_coord: Vector2i in collection_tile_data:
		if tile_coord == tile_info.atlas_coords:
			new_tile_key = tile_info.tile_key
			# print("Trying to process tile at updated Grid Pos: " , tile_info.grid_position, " atlas coords: " , tile_info.atlas_coords)

		else:
			# Gind a Grid Position applying the offset based in the tile position in the collection
			var grid_position: Vector3 = tile_info.grid_position + PlaneCoordinateMapper.offset_to_3d(tile_coord - tile_info.atlas_coords, tile_info.orientation, false)
			# print("Orign TIle Grid Pos" , tile_info.grid_position , " - Offset Grid Pos = " , grid_position)
			new_tile_key = GlobalUtil.make_tile_key(grid_position, tile_info.orientation)
			# print("Trying to process tile at updated Grid Pos: " , grid_position, " TileCoord: ", tile_coord, " - new_tile_key: ", new_tile_key)

			var new_tile_info:PlacedTileInfo = _tile_map.get_tile_info_from_key(new_tile_key)
		
			#Check if the new tile in the offset position is part of the collection (safety guard)
			if new_tile_info and not collection_tile_data.has(new_tile_info.atlas_coords):
				print("TileMapRuntimeAPI.swap_tile_collection_texture: Skipping Tile at %s not part of the Collection" % grid_position)
				continue
		
		new_coords = get_variant_tile_data(new_tile_key)
		# print( "RESULT:  tile_coord: ", tile_coord, " // alternate_tile_coord: ", new_coords)

		tile_info_updated = _tile_map.get_tile_info_from_key(new_tile_key)

		if tile_info_updated != null and tile_info_updated.atlas_coords != Vector2i(-1, -1):
			swap_tile_texture(tile_info_updated, true, new_coords)
	
	swap_count += 1
	
	if swap_count >= max_chain_steps:
		return true

	if follow_chain:
		for step in max_chain_steps -1:
			await Engine.get_main_loop().create_timer(step_change_time).timeout
			new_tile_key = GlobalUtil.make_tile_key(tile_info.grid_position, tile_info.orientation)
			tile_info_updated = _tile_map.get_tile_info_from_key(new_tile_key)
			# print("Step:", step, " // swap_count: ", swap_count, " // MaxSteps: ", max_chain_steps,  " // Tile_info_coord: ", tile_info_updated.atlas_coords)
			swap_tile_collection_texture(tile_info_updated, follow_chain, (max_chain_steps - swap_count))
	
	return swap_count > 0



func get_variant_tile_data(tile_key: int) -> Vector2i:
	var tile_data: TileData = get_tile_data_from_key(tile_key)
	if tile_data == null or not tile_data.has_custom_data(GlobalConstants.CUSTOM_DATA_VARIANT_TILE):
		return Vector2i(-1, -1)
	return tile_data.get_custom_data(GlobalConstants.CUSTOM_DATA_VARIANT_TILE) as Vector2i


func get_collection_tile_data(tile_key: int) -> PackedVector2Array:
	var tile_data: TileData = get_tile_data_from_key(tile_key)
	if tile_data == null or not tile_data.has_custom_data(GlobalConstants.CUSTOM_DATA_COLLECTION_TILES):
		return PackedVector2Array()
	return tile_data.get_custom_data(GlobalConstants.CUSTOM_DATA_COLLECTION_TILES)


class RunTimeAPIHelper:
#region HELPER METHODS

	## Internal single-tile placement in storage-grid coordinates.
	## Final method in the Runtime API call stack before reaching TilePlacementManager.
	static func _place_tile_at_storage(grid_pos: Vector3, uv_rect: Rect2, orientation: int, tile_info: PlacedTileInfo, _tile_map: TileMapLayer3D,_placement_manager: TilePlacementManager) -> bool:
		if orientation < 0 or orientation >= GlobalUtil.TileOrientation.size():
			push_error("TileMapRuntimeAPI._place_tile_at_storage: invalid orientation %d (valid: 0-%d)" \
				% [orientation, GlobalUtil.TileOrientation.size() - 1])
			return false

		var pos: Vector3 = RunTimeAPIHelper.snap_grid_pos(_placement_manager, grid_pos, orientation)
		var tile_key: int = GlobalUtil.make_tile_key(pos, orientation)

		# A vertex-edited tile at this key would silently coexist with the new
		# columnar tile — both would render. Refuse rather than corrupt.
		if _tile_map.has_vertex_corners(tile_key):
			push_error("TileMapRuntimeAPI._place_tile_at_storage: vertex tile already at %s — erase it first" % pos)
			return false

		var placed_info: PlacedTileInfo
		if tile_info == null:
			placed_info = _placement_manager.create_tile_info(
				pos, uv_rect, orientation,
				_placement_manager.current_mesh_rotation,
				_placement_manager.is_current_face_flipped,
				_tile_map.current_mesh_mode
			)
		else:
			placed_info = tile_info
			if tile_info.mesh_mode == GlobalConstants.DEFAULT_MESH_MODE:
				placed_info.mesh_mode = _tile_map.current_mesh_mode
			if tile_info.depth_scale == 1.0:
				placed_info.depth_scale = _placement_manager.current_depth_scale
			if tile_info.texture_repeat_mode == 0:
				placed_info.texture_repeat_mode = _placement_manager.current_texture_repeat_mode
			if not tile_info.freeze_uv:
				placed_info.freeze_uv = _placement_manager.current_freeze_uv

		# Resolve atlas binding if not already provided — allows RuntimeAPI callers to omit
		# atlas_source_id/atlas_coords and still get correct terrain/custom data via get_tile_data_from_key().
		if placed_info.atlas_source_id < 0 and uv_rect.has_area():
			var settings: TileMapLayerSettings = _tile_map.settings
			var ts_size: Vector2i = TileAtlasResolver.get_tile_size(settings)
			if TileAtlasResolver.is_valid_tileset(settings) and ts_size.x > 0 and ts_size.y > 0:
				var src_id: int = settings.active_source_id
				var col: int = int(round(uv_rect.position.x / float(ts_size.x)))
				var row: int = int(round(uv_rect.position.y / float(ts_size.y)))
				var candidate: Vector2i = Vector2i(col, row)
				if TileAtlasResolver.coords_match_registered_cell(settings, src_id, candidate, uv_rect):
					placed_info.atlas_source_id = src_id
					placed_info.atlas_coords = candidate

		var mesh_rotation: int = placed_info.mesh_rotation
		_placement_manager._do_place_tile(tile_key, pos, uv_rect, orientation, mesh_rotation, placed_info)
		return true

	static func _area_offset(orientation: int, u: int, v: int) -> Vector3:
		match orientation:
			GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
				return Vector3(float(u), 0.0, float(v))
			GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
				return Vector3(float(u), float(v), 0.0)
			GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
				return Vector3(0.0, float(v), float(u))
			_:
				return Vector3(float(u), 0.0, float(v))


	## Internal single-tile erase in storage-grid coordinates.
	## Handles both columnar and vertex-edited tiles.
	static func _erase_tile_at_storage(grid_pos: Vector3, orientation: int, _tile_map: TileMapLayer3D,_placement_manager: TilePlacementManager) -> bool:
		var pos: Vector3 = RunTimeAPIHelper.snap_grid_pos(_placement_manager, grid_pos, orientation)
		var tile_key: int = GlobalUtil.make_tile_key(pos, orientation)

		# Vertex-edited tiles are NOT in _saved_tiles_lookup (has_tile() returns false).
		# They live in _vertex_tile_corners and are rendered as standalone MeshInstance3D.
		if _tile_map.has_vertex_corners(tile_key):
			_tile_map.destroy_vertex_mesh_instance(tile_key)
			_tile_map.erase_vertex_corners(tile_key)
			return true

		if not _tile_map.has_tile(tile_key):
			return false
		_placement_manager._do_erase_tile(tile_key)
		return true

	## Snap [param grid_pos] to the nearest valid grid cell for [param orientation].
	## Uses the same selective plane-snap the editor uses — only snaps axes that are
	## parallel to the tile surface; the perpendicular axis is kept exact.
	static func snap_grid_pos(placement_manager: TilePlacementManager, grid_pos: Vector3,
			orientation: int = TileMapRuntimeAPI.ANY_ORIENTATION) -> Vector3:
		var plane: Vector3 = get_snap_plane_for_orientation(orientation) if orientation >= 0 \
			else Vector3.ZERO
		return placement_manager.snap_to_grid(grid_pos, plane)

	## Returns the snap plane normal matching how the editor snaps for each orientation.
	## FLOOR/CEILING → UP  (snap X,Z; keep Y from world hit)
	## WALL_NORTH/SOUTH → FORWARD  (snap X,Y; keep Z from world hit)
	## WALL_EAST/WEST  → RIGHT     (snap Y,Z; keep X from world hit)
	## Tilted (6+)     → ZERO      (full-axis snap — diagonal planes not axis-aligned)
	static func get_snap_plane_for_orientation(orientation: int) -> Vector3:
		match orientation:
			GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
				return Vector3.UP
			GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
				return Vector3.FORWARD
			GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
				return Vector3.RIGHT
			_:
				return Vector3.ZERO  # Tilted: fall back to full-axis snap


	## Static implementation of TileMapRuntimeAPI.world_to_grid_snapped — see that
	## method's doc comment for the contrast with GlobalUtil.world_to_grid and a
	## worked example.
	static func world_to_snapped_grid(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager,
			world_pos: Vector3, orientation: int = TileMapRuntimeAPI.ANY_ORIENTATION) -> Vector3:
		var local_units: Vector3 = (world_pos - tile_map.global_position) / placement_manager.grid_size
		if not _is_base_orientation(orientation):
			return snap_grid_pos(placement_manager,
				GlobalUtil.world_to_grid(world_pos - tile_map.global_position, placement_manager.grid_size),
				orientation)

		match orientation:
			GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
				return Vector3(
					_snap_value(placement_manager, local_units.x - GlobalConstants.GRID_ALIGNMENT_OFFSET.x),
					_snap_value(placement_manager, local_units.y),
					_snap_value(placement_manager, local_units.z - GlobalConstants.GRID_ALIGNMENT_OFFSET.z)
				)
			GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
				return Vector3(
					_snap_value(placement_manager, local_units.x - GlobalConstants.GRID_ALIGNMENT_OFFSET.x),
					_snap_value(placement_manager, local_units.y - GlobalConstants.GRID_ALIGNMENT_OFFSET.y),
					_snap_value(placement_manager, local_units.z)
				)
			GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
				return Vector3(
					_snap_value(placement_manager, local_units.x),
					_snap_value(placement_manager, local_units.y - GlobalConstants.GRID_ALIGNMENT_OFFSET.y),
					_snap_value(placement_manager, local_units.z - GlobalConstants.GRID_ALIGNMENT_OFFSET.z)
				)
			_:
				return snap_grid_pos(placement_manager,
					GlobalUtil.world_to_grid(world_pos - tile_map.global_position, placement_manager.grid_size),
					orientation)


	## Static companion to TileMapRuntimeAPI.grid_to_world_snapped. Converts a
	## snapped tile-cell position back to a world-space anchor for the given
	## orientation, applying the same per-orientation alignment as
	## world_to_grid_snapped().
	static func snapped_grid_to_world(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager,
			snapped_grid_pos: Vector3, orientation: int = TileMapRuntimeAPI.ANY_ORIENTATION) -> Vector3:
		if not _is_base_orientation(orientation):
			return GlobalUtil.grid_to_world(snapped_grid_pos, placement_manager.grid_size) + tile_map.global_position

		match orientation:
			GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
				return Vector3(
					tile_map.global_position.x + (snapped_grid_pos.x + GlobalConstants.GRID_ALIGNMENT_OFFSET.x) * placement_manager.grid_size,
					tile_map.global_position.y + snapped_grid_pos.y * placement_manager.grid_size,
					tile_map.global_position.z + (snapped_grid_pos.z + GlobalConstants.GRID_ALIGNMENT_OFFSET.z) * placement_manager.grid_size
				)
			GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
				return Vector3(
					tile_map.global_position.x + (snapped_grid_pos.x + GlobalConstants.GRID_ALIGNMENT_OFFSET.x) * placement_manager.grid_size,
					tile_map.global_position.y + (snapped_grid_pos.y + GlobalConstants.GRID_ALIGNMENT_OFFSET.y) * placement_manager.grid_size,
					tile_map.global_position.z + snapped_grid_pos.z * placement_manager.grid_size
				)
			GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
				return Vector3(
					tile_map.global_position.x + snapped_grid_pos.x * placement_manager.grid_size,
					tile_map.global_position.y + (snapped_grid_pos.y + GlobalConstants.GRID_ALIGNMENT_OFFSET.y) * placement_manager.grid_size,
					tile_map.global_position.z + (snapped_grid_pos.z + GlobalConstants.GRID_ALIGNMENT_OFFSET.z) * placement_manager.grid_size
				)
			_:
				return GlobalUtil.grid_to_world(snapped_grid_pos, placement_manager.grid_size) + tile_map.global_position



	## Returns {source_id: int, coords: Vector2i, is_freeform: bool} for `tile_key`.
	## Returns an empty Dictionary if the tile_key is unknown.
	## Use this function to check if the TileMapLayer3D Tile in the Grid have a valid binding to an TileSet atlas cell, and if so, which one. Freeform tiles have is_freeform=true and source_id=-1.
	static func get_tile_atlas_binding(_tile_map: TileMapLayer3D, tile_key: int) -> Dictionary:
		if not _tile_map.has_tile(tile_key):
			return {}
		var index: int = _tile_map.get_tile_index(tile_key)
		if index < 0:
			return {}
		var data: PlacedTileInfo = _tile_map.get_tile_info_at_index(index)
		if data == null:
			return {}
		var src: int = data.atlas_source_id
		var coords: Vector2i = data.atlas_coords
		return {
			"source_id": src,
			"coords": coords,
			"is_freeform": src < 0,
		}


	## Returns the active TileSetAtlasSource (or one identified by `source_id`).
	## Pass -1 to use `settings.active_source_id`. Returns null if the TileSet is
	## missing or the requested source isn't an atlas source.
	static func get_atlas_source(_tile_map: TileMapLayer3D, source_id: int = -1) -> TileSetAtlasSource:
		if _tile_map.settings == null:
			return null
		var resolved: int = source_id
		if resolved < 0:
			resolved = _tile_map.settings.active_source_id
		if resolved < 0:
			return null
		if not TileAtlasResolver.is_valid_tileset(_tile_map.settings):
			return null
		return _tile_map.settings.tileset.get_source(resolved) as TileSetAtlasSource


	## Find tile data at a world-space point.
	## Pass an exact orientation for a specific lookup, or ANY_ORIENTATION (-1) to
	## search all 26 orientations (base + tilted/ramp variants). Returned data is enriched with tile_key, snapped_grid_position, and world_position.
	static func find_tile(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager, world_pos: Vector3, orientation: int = TileMapRuntimeAPI.ANY_ORIENTATION, tolerance_cells: int = 0) -> PlacedTileInfo:
		for candidate_orientation: int in _find_orientations(orientation):
			var snapped_grid_pos: Vector3 = world_to_snapped_grid(tile_map, placement_manager, world_pos, candidate_orientation)
			var data: PlacedTileInfo = _tile_data_for_snapped_grid(tile_map, placement_manager, snapped_grid_pos, candidate_orientation)
			if data != null:
				return data
			if tolerance_cells > 0:
				data = _find_tile_with_tolerance(tile_map, placement_manager, snapped_grid_pos, candidate_orientation, tolerance_cells)
				if data != null:
					return data
		return null

	## Search a square neighbourhood of radius `tolerance_cells` around `center_snapped_grid`.
	## Returns the closest tile (by squared distance), or null if none found.
	static func _find_tile_with_tolerance(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager,
			center_snapped_grid: Vector3, orientation: int, tolerance_cells: int) -> PlacedTileInfo:
		var step: float = placement_manager.grid_snap_size
		var best_data: PlacedTileInfo = null
		var best_dist_sq: float = INF
		for du: int in range(-tolerance_cells, tolerance_cells + 1):
			for dv: int in range(-tolerance_cells, tolerance_cells + 1):
				if du == 0 and dv == 0:
					continue
				var offset: Vector3 = _area_offset(orientation, du, dv) * step
				var candidate_pos: Vector3 = center_snapped_grid + offset
				var data: PlacedTileInfo = _tile_data_for_snapped_grid(tile_map, placement_manager, candidate_pos, orientation)
				if data == null:
					continue
				var dist_sq: float = offset.length_squared()
				if dist_sq < best_dist_sq:
					best_dist_sq = dist_sq
					best_data = data
		return best_data

	## Calculate the offset from an area anchor to the center of the area, in snapped grid units.
	static func _center_anchor_offset(orientation: int, size: Vector2i) -> Vector3:
		var half_u: int = int(floor(float(size.x) * 0.5))
		var half_v: int = int(floor(float(size.y) * 0.5))
		return -_area_offset(orientation, half_u, half_v)

	## Convert a world-space anchor to a snapped grid position, applying the same per-orientation alignment as world_to_grid_snapped().
	static func _area_anchor_snapped_grid(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager,
			anchor_world: Vector3, orientation: int, size: Vector2i, options: Variant) -> Vector3:
		var anchor_snapped_grid: Vector3 = world_to_snapped_grid(tile_map, placement_manager, anchor_world, orientation)
		if options != null and options.anchor == "center":
			anchor_snapped_grid += _center_anchor_offset(orientation, size)
		return anchor_snapped_grid

	## Generate a list of snapped grid positions covering an oriented rectangular area, given the anchor's snapped grid position.
	static func _area_snapped_grid_positions(anchor_snapped_grid: Vector3, orientation: int, size: Vector2i) -> Array[Vector3]:
		var positions: Array[Vector3] = []
		for u: int in range(size.x):
			for v: int in range(size.y):
				positions.append(anchor_snapped_grid + _area_offset(orientation, u, v))
		return positions

	## Convert a snapped grid position and orientation to a tile key for lookup.
	## Caller must ensure the snapped grid position is correctly aligned for the orientation (e.g. via world_to_snapped_grid or area anchor snapping).
	static func _tile_key_for_snapped_grid(placement_manager: TilePlacementManager, snapped_grid_pos: Vector3, orientation: int) -> int:
		return GlobalUtil.make_tile_key(_snapped_grid_to_storage(placement_manager, snapped_grid_pos, orientation), orientation)

	## Retrieve full tile data for a snapped grid position and orientation.
	## Enriches the raw columnar data with spatial context (key, snapped pos, world pos).
	static func _tile_data_for_snapped_grid(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager, snapped_grid_pos: Vector3, orientation: int) -> PlacedTileInfo:
		var storage_pos: Vector3 = _snapped_grid_to_storage(placement_manager, snapped_grid_pos, orientation)
		var tile_key: int = GlobalUtil.make_tile_key(storage_pos, orientation)
		var index: int = tile_map.get_tile_index(tile_key)
		if index < 0:
			return null

		# Get full ColumnarTileData from the tile key, then enrich it with spatial info for the caller.
		var data: PlacedTileInfo = tile_map.get_tile_info_at_index(index)
		if data == null:
			return null

		# Adds spatial context to the raw tile data — useful for callers to avoid redundant conversions/lookups.
		data.tile_key = tile_key
		data.snapped_grid_position = snapped_grid_pos
		data.world_position = snapped_grid_to_world(tile_map, placement_manager, snapped_grid_pos, orientation)
		return data


	static func _find_orientations(orientation: int) -> Array[GlobalUtil.TileOrientation]:
		if orientation == TileMapRuntimeAPI.ANY_ORIENTATION:
			return TileMapRuntimeAPI.ALL_ORIENTATIONS
		return [orientation]


	## Return tile keys for an oriented rectangular area.
	## Used by highlight wrappers and debugging. It does not check exists at those keys.
	static func get_area_tile_keys(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager,
			anchor_world: Vector3, orientation: int, size: Vector2i,
			options: Variant = null) -> Array[int]:
		var keys: Array[int] = []
		if not _is_base_orientation(orientation) or size.x <= 0 or size.y <= 0:
			return keys

		var anchor_snapped_grid: Vector3 = _area_anchor_snapped_grid(tile_map, placement_manager, anchor_world, orientation, size, options)
		for snapped_grid_pos: Vector3 in _area_snapped_grid_positions(anchor_snapped_grid, orientation, size):
			keys.append(_tile_key_for_snapped_grid(placement_manager, snapped_grid_pos, orientation))
		return keys

	## Initialize a result Dictionary for place_area / erase_area with default values.
	## Caller should populate "anchor_grid" and "tile_keys" as appropriate
	## Result Dictonary contains the info required to identify tiles to be placed and erased via "tile_keys" and "tiles"
	static func _new_result() -> Dictionary:
		return {
			"ok": true,
			"placed": 0,
			"erased": 0,
			"found": 0,
			"skipped": 0,
			"tile_keys": [],
			"tiles": [],
			"errors": [],
			"anchor_grid": Vector3.ZERO,
		}


	static func _is_base_orientation(orientation: int) -> bool:
		return TileMapRuntimeAPI.BASE_ORIENTATIONS.has(orientation)


	static func _append_error(result: Dictionary, message: String) -> void:
		result["ok"] = false
		result["errors"].append(message)


	static func _validate_area_args(result: Dictionary, operation: String, orientation: int, size: Vector2i) -> bool:
		if not _is_base_orientation(orientation):
			_append_error(result, "%s: orientation must be one of the six base orientations." % operation)
			return false
		if size.x <= 0 or size.y <= 0:
			_append_error(result, "%s: size must be greater than zero on both axes." % operation)
			return false
		return true


	# --- Coordinate Conversion Internals ---
	## Converts an arbitrary world-space position to a snapped grid position for tile lookup/placement.
	static func _world_to_storage_grid(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager,
			world_pos: Vector3) -> Vector3:
		return GlobalUtil.world_to_grid(world_pos - tile_map.global_position, placement_manager.grid_size)


	static func _snap_value(placement_manager: TilePlacementManager, value: float) -> float:
		return snappedf(value, placement_manager.grid_snap_size)


	## Converts user-facing snapped-grid coordinates to the storage grid used by tile keys.
	static func _snapped_grid_to_storage(placement_manager: TilePlacementManager,
			snapped_grid_pos: Vector3, orientation: int) -> Vector3:
		match orientation:
			GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
				return Vector3(
					snapped_grid_pos.x,
					snapped_grid_pos.y - GlobalConstants.GRID_ALIGNMENT_OFFSET.y,
					snapped_grid_pos.z
				)
			GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
				return Vector3(
					snapped_grid_pos.x,
					snapped_grid_pos.y,
					snapped_grid_pos.z - GlobalConstants.GRID_ALIGNMENT_OFFSET.z
				)
			GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
				return Vector3(
					snapped_grid_pos.x - GlobalConstants.GRID_ALIGNMENT_OFFSET.x,
					snapped_grid_pos.y,
					snapped_grid_pos.z
				)
			_:
				return snap_grid_pos(placement_manager, snapped_grid_pos, orientation)


	## Return runtime settings and optional per-orientation diagnostics for a point.
	## Intended for debug UI/prints
	static func get_runtime_debug_info(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager,
			world_pos: Variant = null) -> Dictionary:
		var info: Dictionary = {
			"grid_size": tile_map.settings.grid_size,
			"grid_snap_size": tile_map.settings.grid_snap_size,
			"global_position": tile_map.global_position,
			"tile_count": tile_map.get_tile_count(),
			"vertex_tile_count": tile_map.get_vertex_tile_corners().size(),
		}
		if world_pos is Vector3:
			var per_orientation: Dictionary = {}
			for orientation: int in TileMapRuntimeAPI.BASE_ORIENTATIONS:
				var snapped_grid_pos: Vector3 = world_to_snapped_grid(tile_map, placement_manager, world_pos, orientation)
				per_orientation[orientation] = {
					"snapped_grid_position": snapped_grid_pos,
					"world_position": snapped_grid_to_world(tile_map, placement_manager, snapped_grid_pos, orientation),
					"tile_key": _tile_key_for_snapped_grid(placement_manager, snapped_grid_pos, orientation),
					"has_tile": not _tile_data_for_snapped_grid(tile_map, placement_manager, snapped_grid_pos, orientation).is_empty(),
				}
			info["world_pos"] = world_pos
			info["orientations"] = per_orientation
		return info
	
