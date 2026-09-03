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

@export_group("Ciblage")
@export var lock_focus_weight: float = 0.35    ## 0 = full joueur, 1 = full cible
@export var lock_smoothing_boost: float = 1.4
@export var size_lock_bonus: float = 1.5       ## léger dézoom quand une cible est verrouillée

@onready var cam: Camera3D = $Camera3D

var _shake: float = 0.0
var _shake_time: float = 0.0

var lock_on: Node = null


func _ready() -> void:
	if target != null:
		lock_on = target.get_node_or_null("LockOn")
	if lock_on == null:
		push_warning("CameraRig : LockOn introuvable sous le target")


func _physics_process(delta: float) -> void:
	if target == null:
		return

	# --- Point visé : le joueur, ou un point entre joueur et cible si lock actif ---
	var focus: Vector3 = target.global_position + Vector3.UP * height_offset
	var speed := smoothing
	var locked := false

	if lock_on != null and lock_on.target != null and is_instance_valid(lock_on.target):
		locked = true
		var enemy_point: Vector3 = lock_on.target.global_position + Vector3.UP * height_offset
		focus = focus.lerp(enemy_point, lock_focus_weight)
		speed = smoothing * lock_smoothing_boost

	var t := 1.0 - exp(-speed * delta)
	global_position = global_position.lerp(focus, t)

	# --- Zoom ---
	var wanted: float = size_sprint if target.is_sprinting else size_normal
	if locked:
		wanted += size_lock_bonus
	var zt := 1.0 - exp(-zoom_smoothing * delta)
	cam.size = lerp(cam.size, wanted, zt)

	# --- Secousse ---
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