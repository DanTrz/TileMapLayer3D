extends Area3D
@export var tile_map_layer_3d: TileMapLayer3D
@export var raycas_direction: Vector3 = Vector3.ZERO

@onready var start_point_marker_3d: Marker3D = $StartPointMarker3D
@export var generate_collision: bool = false
@export var max_collection_step: int = 2

@onready var door_action_label: Label3D = $DoorActionLabel


var is_door_open:bool = false
var can_open_door:bool = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.body_entered.connect(on_body_entered)
	self.body_exited.connect(on_body_exited)

	can_open_door = false
	door_action_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F1:open_close_door()
		# KEY_F2: _erase_around_player()

func open_close_door() -> void:
	if not can_open_door:
		return
	var tile_info: PlacedTileInfo = get_tile_info()
	if tile_info and tile_map_layer_3d:
		tile_map_layer_3d.runtime_api.swap_tile_collection_texture(tile_info, true, max_collection_step, 0.15)
		if generate_collision:
			tile_map_layer_3d.runtime_api.set_collision_for_region(tile_info, true, true)
	is_door_open = true

func on_body_entered(body: Node3D) -> void:
	# print("on_body_entered - Called")
	if body is TestPlayer:
		can_open_door = true
		door_action_label.visible = true

func on_body_exited(body: Node3D) -> void:
	# print("on_body_exited - Called")
	if body is TestPlayer:
		can_open_door = false
		door_action_label.visible = false

func get_tile_info() -> PlacedTileInfo:
	if not tile_map_layer_3d:
		return
	var ray_origin: Vector3 = start_point_marker_3d.global_position
	var tile_info: PlacedTileInfo = tile_map_layer_3d.runtime_api.get_first_tile_from_raycast(ray_origin, raycas_direction, 5.5)
	return tile_info
