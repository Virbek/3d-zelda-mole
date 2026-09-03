extends CharacterBody3D

@export var speed: float = 6.0
@export var acceleration: float = 25.0
@export var rotation_speed: float = 14.0
@export var gravity: float = 20.0

@export var sprint_speed: float = 10.0

@export_group("Esquive")
@export var dodge_speed: float = 16.0
@export var dodge_duration: float = 0.26
@export var dodge_cooldown: float = 0.18
@export var iframe_window := Vector2(0.05, 0.65)

@export_group("Vie")
@export var max_health: int = 5
@export var hurt_iframes: float = 0.9
@export var hurt_knockback: float = 7.0
@export var blink_interval: float = 0.08

signal health_changed(current: int, maximum: int)
signal died

var is_sprinting: bool = false
@onready var rig: Node3D = $Rig

const CAM_YAW := deg_to_rad(45.0)

var is_dodging: bool = false
var is_invulnerable: bool = false
var _dodge_t: float = 0.0
var _dodge_dir := Vector3.ZERO
var _dodge_cd: float = 0.0

var health: int
var _hurt_t: float = 0.0
var _blink_t: float = 0.0
var _dead := false

func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)

func _physics_process(delta: float) -> void:
	
	if _hurt_t > 0.0:
		_hurt_t = maxf(_hurt_t - delta, 0.0)
		_blink_t -= delta
		if _blink_t <= 0.0:
			_blink_t = blink_interval
			rig.visible = not rig.visible
		if _hurt_t == 0.0:
			rig.visible = true

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, CAM_YAW)

	if _dodge_cd > 0.0:
		_dodge_cd = maxf(_dodge_cd - delta, 0.0)

	if Input.is_action_just_pressed("dodge") and not is_dodging and _dodge_cd <= 0.0:
		is_dodging = true
		_dodge_t = 0.0
		_dodge_cd = dodge_duration + dodge_cooldown
		# Sans input directionnel : pas en arrière
		_dodge_dir = direction.normalized() if direction.length_squared() > 0.01 \
			else -global_transform.basis.z * -1.0

	is_sprinting = Input.is_action_pressed("sprint") and direction.length_squared() > 0.01

	var current_speed: float = sprint_speed if is_sprinting else speed

	var target := direction* current_speed

	velocity.x = move_toward(velocity.x, target.x, acceleration*delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration*delta)

	if direction.length_squared() > 0.01:
		var angle := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, angle, rotation_speed * delta)
	

	move_and_slide()

	if is_dodging:
		_dodge_t += delta / dodge_duration
		is_invulnerable = _dodge_t >= iframe_window.x and _dodge_t <= iframe_window.y

		# Tient la vitesse puis coupe net
		var e: float = 1.0 - pow(_dodge_t, 3.0)
		velocity.x = _dodge_dir.x * dodge_speed * e
		velocity.z = _dodge_dir.z * dodge_speed * e

		# Le perso regarde où il va
		var a := atan2(-_dodge_dir.x, -_dodge_dir.z)
		rotation.y = lerp_angle(rotation.y, a, 20.0 * delta)

		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= gravity * delta

		move_and_slide()

		if _dodge_t >= 1.0:
			is_dodging = false
			is_invulnerable = false
		return

func take_damage(amount: int, direction: Vector3) -> void:
	if _dead or is_invulnerable or _hurt_t > 0.0:
		return

	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)

	_hurt_t = hurt_iframes
	velocity.x += direction.x * hurt_knockback
	velocity.z += direction.z * hurt_knockback

	# Retour visuel : secousse + vignette
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("shake"):
		HitStop.hit(0.09, 0.0)
		cam.get_parent().shake(0.35)

	if health <= 0:
		_die()


	
func _die() -> void:
	_dead = true
	died.emit()
	rig.visible = true
	set_physics_process(false)

	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("shake"):
		cam.get_parent().shake(0.9)

	await get_tree().create_timer(1.2).timeout
	get_tree().reload_current_scene()
