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
	_placement_manager.active_tile_map_layer3d = tile_map
	_tile_map._active_placement_manager = _placement_manager
	_sync_settings()


func _sync_settings() -> void:
	_placement_manager.grid_size = _tile_map.settings.grid_size
	_placement_manager.grid_snap_size = _tile_map.settings.grid_snap_size
	_placement_manager.tileset_texture = TileAtlasResolver.get_active_texture(_tile_map)
	_placement_manager.current_depth_scale = _tile_map.settings.current_depth_scale
	_placement_manager.current_texture_repeat_mode = _tile_map.settings.texture_repeat_mode
	_placement_manager.current_depth_growth_mode = _tile_map.settings.depth_growth_mode
	_placement_manager.current_freeze_uv = _tile_map.settings.freeze_uv_on_rotation


func place_tile(world_pos: Vector3, uv_rect: Rect2, orientation: int = ORIENTATION.FLOOR, tile_info: PlacedTileInfo = null) -> bool:
	_sync_settings()

	return RunTimeAPIHelper._place_tile_at_storage(
		RunTimeAPIHelper._world_to_storage_grid(_tile_map, _placement_manager, world_pos),
		uv_rect, orientation, tile_info,_tile_map, _placement_manager)

func erase_tile(world_pos: Vector3, orientation: int = ORIENTATION.FLOOR) -> bool:
	_sync_settings()
	return RunTimeAPIHelper._erase_tile_at_storage(
		RunTimeAPIHelper._world_to_storage_grid(_tile_map, _placement_manager, world_pos),
		orientation, _tile_map, _placement_manager)

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

func find_tile(world_pos: Vector3, orientation: int = ANY_ORIENTATION, tolerance_cells: int = 0) -> PlacedTileInfo:
	_sync_settings()
	return RunTimeAPIHelper.find_tile(_tile_map, _placement_manager, world_pos, orientation, tolerance_cells)

func get_first_tile_from_raycast(ray_origin: Vector3, ray_dir: Vector3, max_distance:float = INF) -> PlacedTileInfo:
	return SmartSelectManager.pick_tile_at(ray_origin, ray_dir, _tile_map, max_distance)

func world_to_grid_snapped(world_pos: Vector3, orientation: int = ANY_ORIENTATION) -> Vector3:
	_sync_settings()
	return RunTimeAPIHelper.world_to_snapped_grid(_tile_map, _placement_manager, world_pos, orientation)


func grid_to_world_snapped(snapped_grid_pos: Vector3, orientation: int = ANY_ORIENTATION) -> Vector3:
	_sync_settings()
	return RunTimeAPIHelper.snapped_grid_to_world(_tile_map, _placement_manager, snapped_grid_pos, orientation)


## Defer GPU MultiMesh sync for bulk operations.
## Call before placing many tiles, then call "end_batch" when done.
## Supports nesting — each begin must have a matching end.
func begin_batch() -> void:
	_placement_manager.begin_batch_update()


func end_batch() -> void:
	_placement_manager.end_batch_update()


func highlight_tile(world_pos: Vector3, orientation: int = ANY_ORIENTATION) -> bool:
	var data: PlacedTileInfo = find_tile(world_pos, orientation)
	if data == null:
		return false
	_tile_map.highlight_tiles([data.tile_key])
	return true


func highlight_area(anchor_world: Vector3, orientation: int, size: Vector2i,
		options: RuntimeAPIAreaOptions = null) -> int:
	_sync_settings()
	var tile_keys: Array[int] = RunTimeAPIHelper.get_area_tile_keys(
		_tile_map, _placement_manager, anchor_world, orientation, size, options)
	if tile_keys.is_empty():
		return 0
	_tile_map.highlight_tiles(tile_keys)
	return tile_keys.size()


func clear_highlights() -> void:
	_tile_map.clear_highlights()

func set_collision_for_region(tile_info: PlacedTileInfo, alpha_aware: bool = false, backface_collision: bool = false) -> bool:
	if tile_info == null:
		return false
	var options: RegionBakeOptions = RegionBakeOptions.new()
	options.alpha_aware = alpha_aware
	options.backface_collision = backface_collision

	if tile_info.terrain_region_chunk == null and tile_info.tile_key >= 0 \
			and _tile_map.has_vertex_corners(tile_info.tile_key):
		var regions: Array[TerrainRegionChunk] = TileMeshMerger.get_collision_regions_for_vertex_tile(
			_tile_map, tile_info.tile_key)
		var any_ok: bool = false
		for vertex_region: TerrainRegionChunk in regions:
			await RegionBaker.bake_collision(_tile_map, vertex_region, options)
			any_ok = true
		return any_ok

	await RegionBaker.bake_collision(_tile_map, tile_info.terrain_region_chunk, options)
	return true

func get_debug_info(world_pos: Variant = null) -> Dictionary:
	return RunTimeAPIHelper.get_runtime_debug_info(_tile_map, _placement_manager, world_pos)

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


func get_tileset() -> TileSet:
	return _tile_map.get_tileset()


func atlas_coord_to_uv_rect(atlas_coords: Vector2i, source_id: int = -1) -> Rect2:
	_sync_settings()
	var resolved_source: int = source_id if source_id >= 0 else _tile_map.settings.active_source_id
	return TileAtlasResolver.get_uv_rect_for_coords(_tile_map, resolved_source, atlas_coords)


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

	var new_uv: Rect2 = TileAtlasResolver.get_uv_rect_for_coords(_tile_map, resolved_source, custom_atlas_coords)
	if not new_uv.has_area():
		push_error("TileMapRuntimeAPI.swap_tile_texture: could not resolve UV for coords %s (source %d)" % [custom_atlas_coords, resolved_source])
		return false

	if custom_atlas_coords == Vector2i(-1, -1):
		push_error("TileMapRuntimeAPI.swap_tile_texture: invalid atlas coords %s" % custom_atlas_coords)
		return false

	return _tile_map.update_tile_uv(tile_info.tile_key, new_uv, resolved_source, custom_atlas_coords)

func swap_tile_collection_texture(tile_info: PlacedTileInfo, follow_chain:bool = false, max_chain_steps: int = -1, step_change_time: float = 1.5) -> bool:
	_sync_settings()
	
	var collection_tile_data: PackedVector2Array = get_collection_tile_data(tile_info.tile_key)
	if collection_tile_data.is_empty() or collection_tile_data == null:
		return false
	

	var swap_count: int = 0
	var new_tile_key: int = -1
	var new_coords:Vector2i = Vector2i(-1, -1)
	var tile_info_updated: PlacedTileInfo = null

	for tile_coord: Vector2i in collection_tile_data:
		if tile_coord == tile_info.atlas_coords:
			new_tile_key = tile_info.tile_key

		else:
			var grid_position: Vector3 = tile_info.grid_position + PlaneCoordinateMapper.offset_to_3d(tile_coord - tile_info.atlas_coords, tile_info.orientation, false)
			new_tile_key = GlobalUtil.make_tile_key(grid_position, tile_info.orientation)

			var new_tile_info:PlacedTileInfo = _tile_map.get_tile_info_from_key(new_tile_key)
		
			if new_tile_info and not collection_tile_data.has(new_tile_info.atlas_coords):
				print("TileMapRuntimeAPI.swap_tile_collection_texture: Skipping Tile at %s not part of the Collection" % grid_position)
				continue
		
		new_coords = get_variant_tile_data(new_tile_key)

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

		if placed_info.atlas_source_id < 0 and uv_rect.has_area():
			var settings: TileMapLayerSettings = _tile_map.settings
			var ts_size: Vector2i = TileAtlasResolver.get_tile_size(_tile_map)
			if TileAtlasResolver.is_valid_tileset(_tile_map) and ts_size.x > 0 and ts_size.y > 0:
				var src_id: int = settings.active_source_id
				var col: int = int(round(uv_rect.position.x / float(ts_size.x)))
				var row: int = int(round(uv_rect.position.y / float(ts_size.y)))
				var candidate: Vector2i = Vector2i(col, row)
				if TileAtlasResolver.coords_match_registered_cell(_tile_map, src_id, candidate, uv_rect):
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


	static func _erase_tile_at_storage(grid_pos: Vector3, orientation: int, _tile_map: TileMapLayer3D,_placement_manager: TilePlacementManager) -> bool:
		var pos: Vector3 = RunTimeAPIHelper.snap_grid_pos(_placement_manager, grid_pos, orientation)
		var tile_key: int = GlobalUtil.make_tile_key(pos, orientation)

		if _tile_map.has_vertex_corners(tile_key):
			_tile_map.destroy_vertex_mesh_instance(tile_key)
			_tile_map.erase_vertex_corners(tile_key)
			return true

		if not _tile_map.has_tile(tile_key):
			return false
		_placement_manager._do_erase_tile(tile_key)
		return true

	static func snap_grid_pos(placement_manager: TilePlacementManager, grid_pos: Vector3,
			orientation: int = TileMapRuntimeAPI.ANY_ORIENTATION) -> Vector3:
		var plane: Vector3 = get_snap_plane_for_orientation(orientation) if orientation >= 0 \
			else Vector3.ZERO
		return placement_manager.snap_to_grid(grid_pos, plane)

	static func get_snap_plane_for_orientation(orientation: int) -> Vector3:
		match orientation:
			GlobalUtil.TileOrientation.FLOOR, GlobalUtil.TileOrientation.CEILING:
				return Vector3.UP
			GlobalUtil.TileOrientation.WALL_NORTH, GlobalUtil.TileOrientation.WALL_SOUTH:
				return Vector3.FORWARD
			GlobalUtil.TileOrientation.WALL_EAST, GlobalUtil.TileOrientation.WALL_WEST:
				return Vector3.RIGHT
			_:
				return Vector3.ZERO


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


	static func get_atlas_source(_tile_map: TileMapLayer3D, source_id: int = -1) -> TileSetAtlasSource:
		if _tile_map.settings == null:
			return null
		var resolved: int = source_id
		if resolved < 0:
			resolved = _tile_map.settings.active_source_id
		if resolved < 0:
			return null
		if not TileAtlasResolver.is_valid_tileset(_tile_map):
			return null
		return _tile_map.get_tileset().get_source(resolved) as TileSetAtlasSource


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

	static func _center_anchor_offset(orientation: int, size: Vector2i) -> Vector3:
		var half_u: int = int(floor(float(size.x) * 0.5))
		var half_v: int = int(floor(float(size.y) * 0.5))
		return -_area_offset(orientation, half_u, half_v)

	static func _area_anchor_snapped_grid(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager,
			anchor_world: Vector3, orientation: int, size: Vector2i, options: Variant) -> Vector3:
		var anchor_snapped_grid: Vector3 = world_to_snapped_grid(tile_map, placement_manager, anchor_world, orientation)
		if options != null and options.anchor == "center":
			anchor_snapped_grid += _center_anchor_offset(orientation, size)
		return anchor_snapped_grid

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

	static func _tile_data_for_snapped_grid(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager, snapped_grid_pos: Vector3, orientation: int) -> PlacedTileInfo:
		var storage_pos: Vector3 = _snapped_grid_to_storage(placement_manager, snapped_grid_pos, orientation)
		var tile_key: int = GlobalUtil.make_tile_key(storage_pos, orientation)
		var index: int = tile_map.get_tile_index(tile_key)
		if index < 0:
			return null

		var data: PlacedTileInfo = tile_map.get_tile_info_at_index(index)
		if data == null:
			return null

		data.tile_key = tile_key
		data.snapped_grid_position = snapped_grid_pos
		data.world_position = snapped_grid_to_world(tile_map, placement_manager, snapped_grid_pos, orientation)
		return data


	static func _find_orientations(orientation: int) -> Array[GlobalUtil.TileOrientation]:
		if orientation == TileMapRuntimeAPI.ANY_ORIENTATION:
			return TileMapRuntimeAPI.ALL_ORIENTATIONS
		return [orientation]


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


	static func _world_to_storage_grid(tile_map: TileMapLayer3D, placement_manager: TilePlacementManager,
			world_pos: Vector3) -> Vector3:
		return GlobalUtil.world_to_grid(world_pos - tile_map.global_position, placement_manager.grid_size)


	static func _snap_value(placement_manager: TilePlacementManager, value: float) -> float:
		return snappedf(value, placement_manager.grid_snap_size)


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
	
