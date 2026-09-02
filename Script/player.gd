extends CharacterBody3D

@export var speed: float = 6.0
@export var acceleration: float = 25.0
@export var rotation_speed: float = 14.0
@export var gravity: float = 20.0

@export var sprint_speed: float = 10.0

var is_sprinting: bool = false

const CAM_YAW := deg_to_rad(45.0)

func _physics_process(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	
	var input := Input.get_vector("move_left", "move_right", "move_forward","move_back")

	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, CAM_YAW)

	is_sprinting = Input.is_action_pressed("sprint") and direction.length_squared() > 0.01

	var current_speed: float = sprint_speed if is_sprinting else speed

	var target := direction* current_speed

	velocity.x = move_toward(velocity.x, target.x, acceleration*delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration*delta)

	if direction.length_squared() > 0.01:
		var angle := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, angle, rotation_speed * delta)
	

	move_and_slide()