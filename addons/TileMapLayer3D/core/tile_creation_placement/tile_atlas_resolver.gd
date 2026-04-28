@tool
## Single seam between TileMapLayerSettings and the unified TileSet resource.
## Every read site that needs texture / tile_size / atlas geometry funnels through here.
class_name TileAtlasResolver
extends RefCounted


static func is_valid_tileset(settings: TileMapLayerSettings) -> bool:
	if settings == null:
		return false
	if settings.tileset == null:
		return false
	var source_id: int = settings.active_source_id
	if not settings.tileset.has_source(source_id):
		return false
	var src: TileSetSource = settings.tileset.get_source(source_id)
	return src is TileSetAtlasSource


static func get_active_atlas(settings: TileMapLayerSettings) -> TileSetAtlasSource:
	if not is_valid_tileset(settings):
		return null
	return settings.tileset.get_source(settings.active_source_id) as TileSetAtlasSource


static func get_active_texture(settings: TileMapLayerSettings) -> Texture2D:
	var atlas: TileSetAtlasSource = get_active_atlas(settings)
	if atlas != null and atlas.texture != null:
		return atlas.texture
	# Legacy fallback during migration phases — removed in Phase 6
	if settings != null and "tileset_texture" in settings:
		return settings.tileset_texture
	return null


static func get_tile_size(settings: TileMapLayerSettings) -> Vector2i:
	if settings != null and settings.tileset != null:
		return settings.tileset.tile_size
	# Settings-level fallback when no TileSet is loaded yet (settings.tile_size
	# is its own persisted field; not derived from `tileset.tile_size`).
	if settings != null and "tile_size" in settings:
		return settings.tile_size
	return GlobalConstants.DEFAULT_TILE_SIZE


static func get_atlas_size(settings: TileMapLayerSettings) -> Vector2i:
	var tex: Texture2D = get_active_texture(settings)
	if tex == null:
		return Vector2i.ZERO
	return tex.get_size()


## Returns the pixel-space Rect2 of the tile at (source_id, coords) in the atlas.
static func get_uv_rect_for_coords(settings: TileMapLayerSettings, source_id: int, coords: Vector2i) -> Rect2:
	if not is_valid_tileset(settings):
		return Rect2()
	var atlas: TileSetAtlasSource = settings.tileset.get_source(source_id) as TileSetAtlasSource
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
static func pixel_rect_to_atlas_coords(settings: TileMapLayerSettings, source_id: int, pixel_rect: Rect2) -> Vector2i:
	var ts_size: Vector2i = get_tile_size(settings)
	if ts_size.x <= 0 or ts_size.y <= 0:
		return Vector2i.ZERO
	# Use the rect's top-left; round to nearest cell.
	var col: int = int(round(pixel_rect.position.x / float(ts_size.x)))
	var row: int = int(round(pixel_rect.position.y / float(ts_size.y)))
	return Vector2i(max(col, 0), max(row, 0))


## Builds a fresh in-memory TileSet wrapping a loose Texture2D — single source of
## truth for both the migration path (legacy `tileset_texture` → unified) and the
## Manual-tab Quick Setup path. Optionally pre-creates atlas cells for a set of
## coords (sparse migration); when `used_cells` is empty, no cells are created
## (Quick Setup leaves cell registration to the user's first pick).
static func build_tileset_from_texture(
	texture: Texture2D,
	tile_size: Vector2i,
	used_cells: Dictionary = {}
) -> TileSet:
	var size: Vector2i = tile_size
	if size.x <= 0 or size.y <= 0:
		size = GlobalConstants.DEFAULT_TILE_SIZE

	var ts: TileSet = TileSet.new()
	ts.tile_size = size

	var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = size
	ts.add_source(atlas, 0)

	if texture != null and not used_cells.is_empty():
		var atlas_size: Vector2i = texture.get_size()
		var grid_w: int = int(atlas_size.x / float(size.x))
		var grid_h: int = int(atlas_size.y / float(size.y))
		for coords in used_cells.keys():
			# create_tile fails silently on out-of-range coords — guard explicitly.
			if coords.x >= 0 and coords.x < grid_w and coords.y >= 0 and coords.y < grid_h:
				atlas.create_tile(coords)

	return ts


## Mutates `atlas.texture_region_size` only if the atlas has no registered tiles.
## Changing the region size while cells are registered puts the TileSet into an
## inconsistent state (each registered cell still claims the new, possibly-overlapping
## region). Returns true if the mutation went through, false if it was refused.
## Use Godot's TileSet editor to edit region size on a populated atlas.
static func safe_set_atlas_region_size(atlas: TileSetAtlasSource, new_size: Vector2i) -> bool:
	if atlas == null:
		return false
	if atlas.texture_region_size == new_size:
		return true  # No-op — already at target size
	if atlas.get_tiles_count() > 0:
		push_warning("TileAtlasResolver: refused to change atlas.texture_region_size — %d cells registered. Edit the TileSet via Godot's TileSet editor instead." % atlas.get_tiles_count())
		return false
	atlas.texture_region_size = new_size
	return true


## Returns true if (source_id, coords) names a registered atlas tile whose pixel
## region matches `expected_rect`. Used during migration to decide whether a legacy
## tile should be marked bound (cell exists and matches) or freeform (no honest match).
## Float comparison uses an integer round-trip since atlas regions are pixel-aligned.
static func coords_match_registered_cell(
	settings: TileMapLayerSettings,
	source_id: int,
	coords: Vector2i,
	expected_rect: Rect2
) -> bool:
	if not is_valid_tileset(settings):
		return false
	if coords.x < 0 or coords.y < 0:
		return false
	var atlas: TileSetAtlasSource = settings.tileset.get_source(source_id) as TileSetAtlasSource
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
static func needs_legacy_migration(settings: TileMapLayerSettings) -> bool:
	if settings == null:
		return false
	if settings.tileset != null:
		return false
	if "tileset_texture" in settings and settings.tileset_texture != null:
		return true
	if "autotile_tileset" in settings and settings.autotile_tileset != null:
		return true
	return false
