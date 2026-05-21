extends Node3D

@export var tile_map_3d: TileMapLayer3D
@export var player: Node3D
@export var debug_highlight_on_query: bool = true
@export var terrain_lbl_3d: Label3D
@export var fame_skip: int = 12

var last_terrain_name: String = ""
var frame_count: int = 0
var _last_tile_key: int = -1

## Calculate the player world feet position
var player_feet_world_pos: Vector3:
	get:
		var shape = player.player_col_shape.shape as CapsuleShape3D
		if player and shape:
			# We subtract slightly less than the half-height, since Global Position is at center
			var height_offset = (shape.height / 2.0) - (shape.height / 5.0)
			return player.global_position - Vector3(0, height_offset, 0)
		return Vector3.ZERO


func _process(_delta: float) -> void:
	_check_player_terrain()
	pass



func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# match event.keycode:
	# 	KEY_F1: 

func _check_player_terrain() -> void:
	if not tile_map_3d or not player:
		return
	
	await get_tree().process_frame
	frame_count += 1
	if frame_count % fame_skip == 0:
		_get_tile_at_player_feet()
		frame_count = 0


## Get tile data at the player's feet position using raycast.
func _get_tile_at_player_feet() -> void:
	last_terrain_name = "No Terrain Found"
	var custom_data_value: Variant = null
	
	if not tile_map_3d or not player:
		return
	# Start the Raycast on player location and Y axis we use the player base (feet position)
	var ray_origin: Vector3 = Vector3(player.global_position.x, player_feet_world_pos.y, player.global_position.z)
	# Get the first tile that hits downwads
	var tile_info: PlacedTileInfo = tile_map_3d.runtime_api.get_first_tile_from_raycast(ray_origin, Vector3.DOWN, 0.5)

	# Get TileData from the tile key
	var tile_data : TileData = null
	if tile_info:
		tile_data = tile_map_3d.runtime_api.get_tile_data_from_key(tile_info.tile_key)
	if tile_data:

		##From here you can do whatever you want, like swapt the texture or get the Terrain Name, etc. 
		# Example 0: Retriving the value from custom_data for a giving custom_data layer
		custom_data_value = tile_data.get_custom_data("VariantTile") if tile_data.has_custom_data("VariantTile") else null;

		# Example 1: Retriving data from default VariantTile or CollectionTile data layers
		var variant_data: Variant = tile_map_3d.runtime_api.get_variant_tile_data(tile_info.tile_key)
		var collection_data: Variant = tile_map_3d.runtime_api.get_collection_tile_data(tile_info.tile_key)

		#Example 1: Swap the texture of all related items in the CollectionTiles
		# if tile_info.tile_key != _last_tile_key:
		# 	_last_tile_key = tile_info.tile_key
		# 	tile_map_3d.runtime_api.swap_tile_collection_texture(tile_info, true)

		#Example 2: Swap the texture of just the Source Tile
		# tile_map_3d.runtime_api.set_tile_texture(tile_info, true)  

		#Example 3: Return the TerrainName and CustomData value to a Label3D in the scene
		last_terrain_name = get_terrain_name(tile_data)

		#Debug to get the CustomData and TerrainName
		terrain_lbl_3d.text = "VariantTile: %s\nCollectionTile: %s\nTerrain: %s" % [
			custom_data_value, 
			collection_data, 
			last_terrain_name]
	else:
		terrain_lbl_3d.text = "No tile data found"




		
	#Optional DEBUG:
	if debug_highlight_on_query and tile_info:
		tile_map_3d.highlight_tiles([tile_info.tile_key])

func get_terrain_name(tile_data: TileData) -> String:	
	var terrain_data:Variant = tile_data.terrain
	var terrain_set_id: int = tile_data.terrain_set

	# Access the TileSet resource from your TileMapLayer
	var tile_set: TileSet = tile_map_3d.runtime_api.get_tileset()
	var terrain_name: String = "NoTerrain"
	# Check if the tile actually belongs to a terrain (returns -1 if it doesn't)
	if terrain_set_id != -1 and terrain_data != -1:
		terrain_name = tile_set.get_terrain_name(terrain_set_id, terrain_data)
	
	return terrain_name




# func get_tileset_atlas_data(tile_info: PlacedTileInfo, custom_data_name: String) -> TileData:
# 	if not tile_map_3d or not player:
# 		return
# 	terrain_lbl_3d.text = "No tile data found"
# 	if debug_highlight_on_query and tile_info:
# 		tile_map_3d.highlight_tiles([tile_info.tile_key])

# 	var data: TileData = tile_map_3d.runtime_api.get_tile_data(tile_info.tile_key)
# 	if data:
# 		var _custom_data:Variant
# 		if data.has_custom_data(custom_data_name):
# 			_custom_data = data.get_custom_data(custom_data_name)
# 		var terrain_data:Variant = data.terrain
# 		var terrain_set_id: int = data.terrain_set

# 		# Access the TileSet resource from your TileMapLayer
# 		var tile_set: TileSet = tile_map_3d.runtime_api.get_tileset()
# 		var terrain_name: String = "NoTerrain"
# 		# Check if the tile actually belongs to a terrain (returns -1 if it doesn't)
# 		if terrain_set_id != -1 and terrain_data != -1:
# 			terrain_name = tile_set.get_terrain_name(terrain_set_id, terrain_data)

# 		terrain_lbl_3d.text = terrain_name + " | Custom: " + str(_custom_data)
# 		return data

# 	return null
