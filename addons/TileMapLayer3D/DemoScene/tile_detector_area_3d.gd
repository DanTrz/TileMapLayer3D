extends Area3D
@export var tile_map_layer_3d: TileMapLayer3D
@export var raycas_direction: Vector3 = Vector3.ZERO
@onready var start_point_marker_3d: Marker3D = $StartPointMarker3D

var is_door_open:bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.body_entered.connect(on_body_entered)

func on_body_entered(body: Node3D) -> void:
	# print("on_body_entered - Called")
	if body is TestPlayer:
		# print("body - Is TestPlayer: ", body.name)
		var tile_info: PlacedTileInfo = get_tile_info()
		if tile_info and tile_map_layer_3d:
			# tile_map_layer_3d.runtime_api.swap_tile_collection_texture(tile_info, true)
			tile_map_layer_3d.runtime_api.swap_tile_collection_texture(tile_info, true, 2, 0.15)
			tile_map_layer_3d.runtime_api.set_collision_for_region(tile_info, true, true)

func get_tile_info() -> PlacedTileInfo:
	if not tile_map_layer_3d:
		return
	var ray_origin: Vector3 = start_point_marker_3d.global_position
	var tile_info: PlacedTileInfo = tile_map_layer_3d.runtime_api.get_first_tile_from_raycast(ray_origin, raycas_direction, 0.5)
	return tile_info
