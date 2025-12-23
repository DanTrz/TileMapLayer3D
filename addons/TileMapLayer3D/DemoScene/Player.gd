extends CharacterBody3D

var speed:float
const WALK_SPEED = 8.0
const SPRINT_SPEED = 12.0
const JUMP_VELOCITY = 4.5
@onready var fps_label_3d: Label3D = %FpsLabel3D


func _physics_process(delta: float) -> void:
	fps_label_3d.text = str(Engine.get_frames_per_second())
	# Add the gravity #
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump #
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	# Handle Sprint #
	if Input.is_action_pressed("ui_cancel"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	# Get the input direction and handle the movement/deceleration #
	# As good practice, you should replace UI actions with custom gameplay actions #
	var input_dir:Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction :Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		# Moving - apply velocity immediately
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		# Not moving - smooth deceleration
		if is_on_floor():
			velocity.x = lerp(velocity.x, 0.0, delta * 7.0)
			velocity.z = lerp(velocity.z, 0.0, delta * 7.0)
		else:
			velocity.x = lerp(velocity.x, 0.0, delta * 3.0)
			velocity.z = lerp(velocity.z, 0.0, delta * 3.0)
	
	move_and_slide()
