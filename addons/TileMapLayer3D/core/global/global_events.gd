class_name GlobalEvents
extends RefCounted

static var _instance: GlobalEvents = null

signal tile_texture_selected(texture: Texture2D, grid_size: Vector2)
#TODO # DEBUG # TESTING
static func get_instance() -> GlobalEvents:
	# Only create in editor - returns null at runtime
	if not Engine.is_editor_hint():
		return null
	if _instance == null:
		_instance = GlobalEvents.new()
	return _instance

## Emits the tile_texture_selected signal with the given texture
## Does not impact Tiling or the TileMapLayer3D directly. Only used for SpriteMesh integration
static func emit_tile_texture_selected(texture: Texture2D, grid_size: Vector2) -> void:
	var inst = get_instance()
	if inst:
		inst.tile_texture_selected.emit(texture, grid_size)
		print("GlobalEvents: Emitted tile_texture_selected signal.")
		
		
## Emits the tile_texture_selected signal with the given texture
## Does not impact Tiling or the TileMapLayer3D directly. Only used for SpriteMesh integration.
static func connect_tile_texture_selected(callable: Callable) -> void:
	var inst : GlobalEvents = get_instance()
	if inst:
		inst.tile_texture_selected.connect(callable)
		print("GlobalEvents: connected tile_texture_selected signal.")
