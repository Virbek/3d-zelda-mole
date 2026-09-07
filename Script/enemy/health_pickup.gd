extends Area3D

## Morceau de vie lâché à la mort d'un ennemi.
##
## Il ne se ramasse pas au contact immédiat : il attend un court instant avant
## d'être actif (le temps que le joueur voie qu'il est tombé), puis se met à
## voler vers lui dès qu'il approche. Sans cette attirance, le joueur doit
## marcher précisément dessus en plein combat, ce qui casse le rythme.

@export var heal_amount: int = 1
@export var lifetime: float = 12.0
@export var arm_time: float = 0.35        ## délai avant de pouvoir être ramassé

@export_group("Éjection")
@export var pop_up: float = 3.2
@export var pop_side: float = 1.8
@export var fall_gravity: float = 12.0
@export var bounce: float = 0.45
@export var floor_y: float = 0.25         ## hauteur de repos au sol

@export_group("Attirance")
@export var attract_range: float = 2.6
@export var attract_speed: float = 11.0
@export var pickup_range: float = 0.5

@export_group("Ressenti")
@export var spin_speed: float = 3.0
@export var bob_amount: float = 0.12
@export var bob_speed: float = 4.0
@export var blink_before_end: float = 3.0 ## clignote avant de disparaître

@onready var mesh: MeshInstance3D = $MeshInstance3D

var _vel := Vector3.ZERO
var _life: float = 0.0
var _t: float = 0.0
var _rest_y: float = 0.0
var _grounded: bool = false
var _taken: bool = false
var _player: Node3D = null


func _ready() -> void:
	_vel = Vector3(
		randf_range(-pop_side, pop_side),
		pop_up,
		randf_range(-pop_side, pop_side)
	)
	_rest_y = global_position.y + floor_y

	for n in get_tree().get_nodes_in_group("player_hurt"):
		_player = n
		break


func _physics_process(delta: float) -> void:
	if _taken:
		return

	_t += delta
	_life += delta

	if _life >= lifetime:
		_vanish()
		return

	# Clignotement de fin de vie : le joueur doit pouvoir décider de courir
	if _life >= lifetime - blink_before_end:
		var f: float = fmod(_life * 8.0, 1.0)
		mesh.visible = f > 0.4

	mesh.rotate_y(spin_speed * delta)

	if _grounded:
		_idle_float(delta)
	else:
		_fall(delta)


## Rebond puis repos. Le rebond sert à indiquer où l'objet s'est arrêté.
func _fall(delta: float) -> void:
	_vel.y -= fall_gravity * delta
	global_position += _vel * delta

	if global_position.y <= _rest_y and _vel.y < 0.0:
		global_position.y = _rest_y
		if absf(_vel.y) > 1.0:
			_vel.y = -_vel.y * bounce
			_vel.x *= 0.5
			_vel.z *= 0.5
		else:
			_vel = Vector3.ZERO
			_grounded = true
			_t = 0.0


func _idle_float(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var to_p: Vector3 = _player.global_position - global_position
	var d: float = to_p.length()

	if d <= pickup_range:
		_collect()
		return

	if d <= attract_range:
		# Accélère en approchant : donne l'impression d'être aspiré
		var k: float = 1.0 - (d / attract_range)
		global_position += to_p.normalized() * attract_speed * (0.3 + k) * delta
	else:
		global_position.y = _rest_y + sin(_t * bob_speed) * bob_amount


func _collect() -> void:
	if _taken:
		return
	_taken = true

	if _player != null and _player.has_method("heal"):
		_player.heal(heal_amount)

	var t := create_tween().set_parallel(true)
	t.tween_property(mesh, "scale", Vector3(2.2, 2.2, 2.2), 0.16)\
		.set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position:y", position.y + 0.7, 0.16)
	await t.finished
	queue_free()


func _vanish() -> void:
	_taken = true
	var t := create_tween()
	t.tween_property(mesh, "scale", Vector3.ZERO, 0.15).set_ease(Tween.EASE_IN)
	await t.finished
	queue_free()
