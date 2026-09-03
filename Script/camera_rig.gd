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


var _shake: float = 0.0
var _shake_time: float = 0.0

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var t := 1.0 - exp(-smoothing * delta)
	global_position = global_position.lerp(
		target.global_position + Vector3.UP * height_offset, t
	)

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