extends Node3D

@export var tile_map_3d: TileMapLayer3D
@export var player: Node3D
@export var debug_tile_info: bool = true
@export var debug_highlight_on_query: bool = true

@export var terrain_lbl_3d: Label3D
@export var fame_skip: int = 12

var last_terrain_name: String = ""
var frame_count: int = 0
var _last_tile_key: int = -1

var player_feet_world_pos: Vector3:
	get:
		var shape = player.player_col_shape.shape as CapsuleShape3D
		if player and shape:
			var height_offset = (shape.height / 2.0) - (shape.height / 5.0)
			return player.global_position - Vector3(0, height_offset, 0)
		return Vector3.ZERO


func _process(_delta: float) -> void:
	if debug_tile_info:
		_check_player_terrain()




func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

func _check_player_terrain() -> void:
	if not tile_map_3d or not player:
		return
	
	await get_tree().process_frame
	frame_count += 1
	if frame_count % fame_skip == 0:
		_get_tile_at_player_feet()
		frame_count = 0


func _get_tile_at_player_feet() -> void:
	last_terrain_name = "No Terrain Found"
	var custom_data_value: Variant = null
	
	if not tile_map_3d or not player:
		return
	var ray_origin: Vector3 = Vector3(player.global_position.x, player_feet_world_pos.y, player.global_position.z)
	var tile_info: PlacedTileInfo = tile_map_3d.runtime_api.get_first_tile_from_raycast(ray_origin, Vector3.DOWN, 0.5)

	var tile_data : TileData = null
	if tile_info:
		tile_data = tile_map_3d.runtime_api.get_tile_data_from_key(tile_info.tile_key)
	if tile_data:

		custom_data_value = tile_data.get_custom_data("VariantTile") if tile_data.has_custom_data("VariantTile") else null;

		var variant_data: Variant = tile_map_3d.runtime_api.get_variant_tile_data(tile_info.tile_key)
		var collection_data: Variant = tile_map_3d.runtime_api.get_collection_tile_data(tile_info.tile_key)



		last_terrain_name = get_terrain_name(tile_data)

		terrain_lbl_3d.text = "VariantTile: %s\nCollectionTile: %s\nTerrain: %s" % [
			custom_data_value, 
			collection_data, 
			last_terrain_name]
	else:
		terrain_lbl_3d.text = "No tile data found"




		
	if debug_highlight_on_query and tile_info:
		tile_map_3d.highlight_tiles([tile_info.tile_key])

func get_terrain_name(tile_data: TileData) -> String:	
	var terrain_data:Variant = tile_data.terrain
	var terrain_set_id: int = tile_data.terrain_set

	var tile_set: TileSet = tile_map_3d.runtime_api.get_tileset()
	var terrain_name: String = "NoTerrain"
	if terrain_set_id != -1 and terrain_data != -1:
		terrain_name = tile_set.get_terrain_name(terrain_set_id, terrain_data)
	
	return terrain_name
