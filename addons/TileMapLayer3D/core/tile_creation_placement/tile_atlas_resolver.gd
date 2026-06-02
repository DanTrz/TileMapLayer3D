@tool
## Single resolver between TileMapLayer3D/TileMapLayerData and the unified TileSet resource.
## Every read site that needs texture / tile_size / atlas geometry funnels through here.
class_name TileAtlasResolver
extends RefCounted

static var required_layers: Dictionary[String, Variant] = {
		GlobalConstants.CUSTOM_DATA_ANIMATED:   TYPE_BOOL,
		GlobalConstants.CUSTOM_DATA_VARIANT_TILE:   TYPE_VECTOR2I,
		GlobalConstants.CUSTOM_DATA_COLLECTION_TILES: TYPE_PACKED_VECTOR2_ARRAY,
		GlobalConstants.CUSTOM_DATA_COLLISION: TYPE_BOOL}

static var required_layer_defaults: Dictionary[String, Variant] = {
		GlobalConstants.CUSTOM_DATA_ANIMATED: false,
		GlobalConstants.CUSTOM_DATA_VARIANT_TILE: Vector2i(-1, -1),
		GlobalConstants.CUSTOM_DATA_COLLECTION_TILES: PackedVector2Array(),
		GlobalConstants.CUSTOM_DATA_COLLISION: true}


static func get_tileset(source: Variant) -> TileSet:
	if source == null:
		return null
	if source is TileMapLayer3D:
		return (source as TileMapLayer3D).get_tileset()
	if source is TileMapLayerData:
		return (source as TileMapLayerData).tileset
	return null


static func get_active_source_id(source: Variant) -> int:
	if source is TileMapLayer3D:
		var tile_map: TileMapLayer3D = source as TileMapLayer3D
		return tile_map.settings.active_source_id if tile_map.settings else GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID
	if source is TileMapLayerSettings:
		return (source as TileMapLayerSettings).active_source_id
	return GlobalConstants.AUTOTILE_DEFAULT_SOURCE_ID


static func _get_settings(source: Variant) -> TileMapLayerSettings:
	if source is TileMapLayer3D:
		return (source as TileMapLayer3D).settings
	if source is TileMapLayerSettings:
		return source as TileMapLayerSettings
	return null


static func is_valid_tileset(source: Variant) -> bool:
	var tileset: TileSet = get_tileset(source)
	if tileset == null:
		return false
	var source_id: int = get_active_source_id(source)
	if not tileset.has_source(source_id):
		return false
	var src: TileSetSource = tileset.get_source(source_id)
	return src is TileSetAtlasSource


static func get_active_atlas(source: Variant) -> TileSetAtlasSource:
	if not is_valid_tileset(source):
		return null
	return get_tileset(source).get_source(get_active_source_id(source)) as TileSetAtlasSource


static func get_active_texture(source: Variant) -> Texture2D:
	var atlas: TileSetAtlasSource = get_active_atlas(source)
	if atlas != null and atlas.texture != null:
		return atlas.texture
	# Legacy fallback during migration phases — removed in Phase 6
	var settings: TileMapLayerSettings = _get_settings(source)
	if settings != null and "tileset_texture" in settings:
		return settings.tileset_texture
	return null


static func get_tile_size(source: Variant) -> Vector2i:
	var tileset: TileSet = get_tileset(source)
	if tileset != null:
		return tileset.tile_size
	# Settings-level fallback when no TileSet is loaded yet (settings.tile_size
	# is its own persisted field; not derived from `tileset.tile_size`).
	var settings: TileMapLayerSettings = _get_settings(source)
	if settings != null and "tile_size" in settings:
		return settings.tile_size
	return GlobalConstants.DEFAULT_TILE_SIZE


static func get_atlas_size(source: Variant) -> Vector2i:
	var tex: Texture2D = get_active_texture(source)
	if tex == null:
		return Vector2i.ZERO
	return tex.get_size()


## Returns the pixel-space Rect2 of the tile at (source_id, coords) in the atlas.
static func get_uv_rect_for_coords(source: Variant, source_id: int, coords: Vector2i) -> Rect2:
	var tileset: TileSet = get_tileset(source)
	if tileset == null or not tileset.has_source(source_id):
		return Rect2()
	var atlas: TileSetAtlasSource = tileset.get_source(source_id) as TileSetAtlasSource
	if atlas == null:
		return Rect2()
	if not atlas.has_tile(coords):
		# Tile is not registered in the atlas; synthesise the rect from texture_region_size
		# so downstream code can still render. Won't include atlas margins.
		var size: Vector2i = atlas.texture_region_size
		return Rect2(Vector2(coords * size), Vector2(size))
	return atlas.get_tile_texture_region(coords)


## Quantises a free-form pixel rect picked in the manual UI to the nearest atlas cell.
## Used at selection-commit time to convert legacy Rect2 picks into atlas_coords.
static func pixel_rect_to_atlas_coords(source: Variant, source_id: int, pixel_rect: Rect2) -> Vector2i:
	var ts_size: Vector2i = get_tile_size(source)
	if ts_size.x <= 0 or ts_size.y <= 0:
		return Vector2i.ZERO
	# Use the rect's top-left; round to nearest cell.
	var col: int = int(round(pixel_rect.position.x / float(ts_size.x)))
	var row: int = int(round(pixel_rect.position.y / float(ts_size.y)))
	return Vector2i(max(col, 0), max(row, 0))


## Builds a fresh in-memory TileSet wrapping a loose Texture2D
## Optionally pre-creates atlas cells for a set of coords (sparse migration); when `used_cells` is empty, no cells are created
## (Quick Setup leaves cell registration to the user's first pick).
static func build_tileset_from_texture(texture: Texture2D, tile_size: Vector2i, used_cells: Dictionary = {}
) -> TileSet:
	var size: Vector2i = tile_size
	if size.x <= 0 or size.y <= 0:
		size = GlobalConstants.DEFAULT_TILE_SIZE

	var tileset: TileSet = TileSet.new()
	tileset.tile_size = size

	var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = size
	tileset.add_source(atlas, 0)

	if texture != null and not used_cells.is_empty():
		var atlas_size: Vector2i = texture.get_size()
		var grid_w: int = int(atlas_size.x / float(size.x))
		var grid_h: int = int(atlas_size.y / float(size.y))
		for coords in used_cells.keys():
			# create_tile fails silently on out-of-range coords — guard explicitly.
			if coords.x >= 0 and coords.x < grid_w and coords.y >= 0 and coords.y < grid_h:
				atlas.create_tile(coords)

	initialize_custom_data_for_tileset(tileset)
	return tileset


## One-time initializer for freshly loaded/created TileSets or legacy migration.
## It does the expensive/default-writing cell pass only when the TileSet did not
## already contain any TileMapLayer3D custom data layer.
static func initialize_custom_data_for_tileset(tileset: TileSet) -> void:
	if tileset == null:
		return
	
	if get_missing_custom_data_layers(tileset).size() == 0:
		return  # All required layers already exist; assume cells are populated
	
	create_missing_data_layers(tileset)


## Mutates `atlas.texture_region_size` without deleting registered cells.
## This preserves per-tile TileSet data (terrain bits, custom data, physics,
## navigation, occlusion, animation, etc.) and matches Godot's native TileSet
## editor behavior when changing atlas region size.
static func set_atlas_region_size_preserving_tiles(atlas: TileSetAtlasSource, new_size: Vector2i) -> bool:
	if atlas == null:
		return false
	if new_size.x <= 0 or new_size.y <= 0:
		return false
	if atlas.texture_region_size == new_size:
		return true  # No-op — already at target size
	atlas.texture_region_size = new_size
	return true


## Backward-compatible name for older call sites.
static func safe_set_atlas_region_size(atlas: TileSetAtlasSource, new_size: Vector2i) -> bool:
	return set_atlas_region_size_preserving_tiles(atlas, new_size)



## Adds missing custom data layer definitions (name + type) ONLY.
## Does NOT create atlas tiles or write per-tile defaults.
## Safe to call on every scene load — never touches existing tile data.
static func ensure_layer_definitions(tileset: TileSet) -> void:
	if tileset == null:
		return
	var missing_layers: Dictionary[String, Variant] = get_missing_custom_data_layers(tileset)
	if missing_layers.is_empty():
		return
	for layer_name: String in missing_layers.keys():
		var layer_idx: int = tileset.get_custom_data_layers_count()
		tileset.add_custom_data_layer(layer_idx)
		tileset.set_custom_data_layer_name(layer_idx, layer_name)
		tileset.set_custom_data_layer_type(layer_idx, missing_layers[layer_name])
	tileset.emit_changed()


## Full initializer for freshly created TileSets: creates missing layer definitions,
## pre-creates all atlas tiles, and writes per-tile defaults for each new layer.
## Only call this for new or migrated TileSets — never on scene load.
static func create_missing_data_layers(tileset: TileSet) -> void:
	if tileset == null:
		return
	var missing_layers: Dictionary[String, Variant] = get_missing_custom_data_layers(tileset)
	if missing_layers.is_empty():
		return

	#Ensure all Tiles are Created
	create_all_missing_tiles(tileset)

	# Add the custom_layers and set their default value
	for layer_name: String in missing_layers.keys():
		var value_type: Variant =  missing_layers[layer_name]
		var layer_idx: int = tileset.get_custom_data_layers_count()

		tileset.add_custom_data_layer(layer_idx)
		tileset.set_custom_data_layer_name(layer_idx, layer_name)
		tileset.set_custom_data_layer_type(layer_idx, value_type)

		# Set default values for the new layer
		set_custom_data_for_layer(tileset, layer_name, required_layer_defaults[layer_name])

	tileset.emit_changed()


static func get_missing_custom_data_layers(tileset: TileSet) -> Dictionary[String, Variant]:
	if tileset == null:
		return {}

	var missing_layers: Dictionary[String, Variant] = {}

	for layer_name: String in required_layers.keys():
		if not tileset.has_custom_data_layer_by_name(layer_name):
			missing_layers[layer_name] = required_layers[layer_name]

	return missing_layers

static func set_custom_data_for_layer(tileset: TileSet, layer_name: String, value: Variant) -> void:
	if tileset == null or layer_name == "" or value == null:
		return

	if not tileset.has_custom_data_layer_by_name(layer_name):
		push_warning("Layer '%s' not found in TileSet; cannot set custom data." % layer_name)
		return

	for source_index in tileset.get_source_count():
		var source_id :int = tileset.get_source_id(source_index)
		var atlas_source :TileSetAtlasSource = tileset.get_source(source_id) as TileSetAtlasSource
		if atlas_source == null:
			continue

		for tile_index in atlas_source.get_tiles_count():
			var coords :Vector2i= atlas_source.get_tile_id(tile_index)
			var tile_data :TileData= atlas_source.get_tile_data(coords, 0)

			if tile_data != null:
				tile_data.set_custom_data(layer_name, value)

static func create_all_missing_tiles(tileset: TileSet) -> void:
	if tileset == null:
		return

	for source_idx: int in range(tileset.get_source_count()):
		var source_id: int = tileset.get_source_id(source_idx)
		var atlas_source: TileSetAtlasSource = tileset.get_source(source_id) as TileSetAtlasSource
		if atlas_source == null or atlas_source.texture == null:
			continue

		var texture_size: Vector2i = Vector2i(atlas_source.texture.get_size())
		var tile_size: Vector2i = atlas_source.texture_region_size
		if tile_size.x <= 0 or tile_size.y <= 0:
			continue

		var columns: int = int(texture_size.x / float(tile_size.x))
		var rows: int = int(texture_size.y / float(tile_size.y))

		for y: int in range(rows):
			for x: int in range(columns):
				var coords := Vector2i(x, y)

				if not atlas_source.has_tile(coords):
					atlas_source.create_tile(coords)


## Returns true if (source_id, coords) names a registered atlas tile whose pixel
## region matches `expected_rect`. Used during migration to decide whether a legacy
## tile should be marked bound (cell exists and matches) or freeform (no honest match).
## Float comparison uses an integer round-trip since atlas regions are pixel-aligned.
static func coords_match_registered_cell(
	source: Variant,
	source_id: int,
	coords: Vector2i,
	expected_rect: Rect2
) -> bool:
	var tileset: TileSet = get_tileset(source)
	if tileset == null or not tileset.has_source(source_id):
		return false
	if coords.x < 0 or coords.y < 0:
		return false
	var atlas: TileSetAtlasSource = tileset.get_source(source_id) as TileSetAtlasSource
	if atlas == null:
		return false
	if not atlas.has_tile(coords):
		return false
	var actual: Rect2 = atlas.get_tile_texture_region(coords)
	# Atlas regions are pixel-aligned; a small epsilon is sufficient.
	return (
		absf(actual.position.x - expected_rect.position.x) < 0.5
		and absf(actual.position.y - expected_rect.position.y) < 0.5
		and absf(actual.size.x - expected_rect.size.x) < 0.5
		and absf(actual.size.y - expected_rect.size.y) < 0.5
	)


## Returns true if the unified `tileset` is missing but legacy fields are populated —
## i.e., this settings resource needs migration. Cheap check, safe to call from _ready().
