extends Area3D
@export var tile_map_layer_3d: TileMapLayer3D
@export var raycas_direction: Vector3 = Vector3.ZERO
@onready var start_point_marker_3d: Marker3D = $StartPointMarker3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.body_entered.connect(on_body_entered)

func on_body_entered(body: Node3D) -> void:
	if body is TestPlayer:
		print("body entered: ", body.name)
		var tile_info: PlacedTileInfo = get_tile_info()
		if tile_info and tile_map_layer_3d:
			tile_map_layer_3d.runtime_api.set_tile_texture_group(tile_info, true)
			tile_map_layer_3d.runtime_api.generate_collision_async(true, true)

func get_tile_info() -> PlacedTileInfo:
	if not tile_map_layer_3d:
		return
	# Start the Raycast on player location and Y axis we use the player base (feet position)
	var ray_origin: Vector3 = start_point_marker_3d.global_position
	# Get the first tile that hits downwads
	var tile_info: PlacedTileInfo = tile_map_layer_3d.runtime_api.get_first_tile_from_raycast(ray_origin, raycas_direction, 0.5)
	
	if tile_info:
		print(tile_info.atlas_coords)
		return tile_info
		
	print("No TileInfo")
	return null
