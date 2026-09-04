extends Node3D

@export var target: Node3D
@export var smoothing: float = 10.0
@export var height_offset: float = 1.0

@export_group("Zoom")
@export var size_normal: float = 12.0
@export var size_sprint: float = 14.5
@export var zoom_smoothing: float = 2.5

@export_group("Secousse")
@export var shake_decay: float = 4.0
@export var shake_amount: float = 0.5
@export var shake_speed: float = 28.0

@onready var cam: Camera3D = $Camera3D
@export var lock_focus_weight: float = 0.35   # 0 = full joueur, 1 = full cible
@export var lock_smoothing_boost: float = 1.4 # légèrement plus réactive en combat

@onready var lock_on: Node = target.get_node_or_null("LockOn")


var _shake: float = 0.0
var _shake_time: float = 0.0

func _physics_process(delta: float) -> void:
	if target == null:
		return

	var focus_point: Vector3 = target.global_position
	var speed := smoothing

	if lock_on != null and lock_on.target != null and is_instance_valid(lock_on.target):
		focus_point = target.global_position.lerp(lock_on.target.global_position, lock_focus_weight)
		speed = smoothing * lock_smoothing_boost

	var t := 1.0 - exp(-speed * delta)
	global_position = global_position.lerp(focus_point, t)

	var wanted: float = size_sprint if target.is_sprinting else size_normal
	var zt := 1.0 - exp(-zoom_smoothing * delta)
	cam.size = lerp(cam.size, wanted, zt)

	if _shake > 0.0:
		_shake = maxf(_shake - shake_decay * delta * _shake, 0.0)
		_shake_time += delta * shake_speed
		var s: float = _shake * _shake * shake_amount   # décroissance quadratique
		cam.position.x = sin(_shake_time) * s
		cam.position.y = cos(_shake_time * 1.37) * s
	else:
		cam.position.x = 0.0
		cam.position.y = 0.0

func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)