extends CharacterBody3D

## Ennemi kamikaze. Il ne frappe pas : il court sur le joueur et explose,
## soit en atteignant sa cible, soit en mourant.
##
## Son intérêt de design n'est pas la menace directe — il est lent et fragile —
## mais le fait qu'il transforme le SOL en problème. Le joueur ne peut plus
## rester où il veut, et le tuer au mauvais endroit lui coûte du terrain.
## C'est le seul ennemi qui rend la position du joueur plus importante que
## son timing.
##
## Il n'utilise pas le jeton d'attaque : il ne fait pas d'attaque au sens
## habituel, et l'attendre le rendrait inoffensif.

enum State { IDLE, CHASE, PRIMED, DEAD }

signal died

@export var player_path: NodePath
@export var blast_scene: PackedScene

@export_group("Vie")
@export var max_health: int = 2          ## fragile : il doit mourir vite
@export var damage_per_hit: int = 1

@export_group("Détection")
@export var detect_range: float = 11.0
@export var lose_range: float = 15.0
@export var trigger_range: float = 1.6   ## distance à laquelle il s'amorce

@export_group("Déplacement")
@export var chase_speed: float = 3.4
@export var accel: float = 9.0
@export var turn_speed: float = 5.0
@export var gravity: float = 20.0

@export_group("Amorçage")
@export var prime_time: float = 0.45     ## il se gonfle avant d'exploser
@export var prime_scale: float = 1.55

@export_group("Recul")
@export var knockback_force: float = 11.0
@export var knockback_damping: float = 9.0

@export_group("Couleurs")
@export var prime_color := Color(1.0, 0.4, 0.1)
@export var flash_color := Color(1.0, 0.15, 0.15)
@export var pulse_base: float = 2.5      ## pulsation au repos, en Hz
@export var pulse_near: float = 11.0     ## pulsation quand il est proche

@export_group("Butin")
@export var pickup_scene: PackedScene
@export var pickup_chance: float = 0.35
@export var pickup_max: int = 1

var state: State = State.IDLE
var health: int
var player: CharacterBody3D = null

var _t: float = 0.0
var _knockback := Vector3.ZERO
var _pulse_t: float = 0.0
var _hurt_t: float = 0.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var health_bar: Node3D = $HealthBar
@onready var hurt_box: Area3D = $HurtBox

var _mat: StandardMaterial3D
var _base_color: Color
var _base_scale := Vector3.ONE


func _ready() -> void:
	add_to_group("enemy")

	player = get_node_or_null(player_path)
	if player == null:
		push_warning("%s : player introuvable" % name)
		set_physics_process(false)
		return

	health = max_health
	_base_scale = mesh.scale
	var base := mesh.get_active_material(0)
	_mat = base.duplicate() if base != null else StandardMaterial3D.new()
	mesh.material_override = _mat
	_base_color = _mat.albedo_color

	health_bar.set_ratio(1.0)


func _physics_process(delta: float) -> void:
	_t += delta
	if _hurt_t > 0.0:
		_hurt_t = maxf(_hurt_t - delta, 0.0)

	match state:
		State.IDLE:
			_idle()
		State.CHASE:
			_chase(delta)
		State.PRIMED:
			_primed(delta)
		State.DEAD:
			return

	_pulse(delta)
	_apply_gravity(delta)
	move_and_slide()


func _set_state(next: State) -> void:
	state = next
	_t = 0.0


# ---------------------------------------------------------------- ÉTATS

func _idle() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _distance_to_player() < detect_range:
		_set_state(State.CHASE)


func _chase(delta: float) -> void:
	var d: float = _distance_to_player()

	if d > lose_range:
		_set_state(State.IDLE)
		return

	if d <= trigger_range:
		_set_state(State.PRIMED)
		return

	var dir: Vector3 = _dir_to_player()

	# Recul en cours : il subit avant de reprendre sa course
	if _hurt_t > 0.0:
		velocity.x = _knockback.x
		velocity.z = _knockback.z
		_knockback *= exp(-knockback_damping * delta)
		return

	velocity.x = move_toward(velocity.x, dir.x * chase_speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * chase_speed, accel * delta)
	_face(dir, delta)


## Il se fige et se gonfle. Ce temps d'arrêt est ce qui rend l'explosion
## esquivable : sans lui, atteindre le joueur voudrait dire le toucher.
func _primed(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)

	var k: float = _t / maxf(prime_time, 0.01)
	var s: float = lerpf(1.0, prime_scale, k)
	mesh.scale = _base_scale * Vector3(s, s * 0.85, s)
	_mat.albedo_color = _base_color.lerp(prime_color, k)

	if _t >= prime_time:
		_explode()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta


## Pulsation cardiaque : lente de loin, frénétique de près. Le joueur entend
## le danger monter sans avoir besoin de regarder l'ennemi.
func _pulse(delta: float) -> void:
	if state == State.PRIMED or state == State.DEAD:
		return

	var d: float = _distance_to_player()
	var near: float = 1.0 - clampf(d / maxf(detect_range, 0.01), 0.0, 1.0)
	_pulse_t += delta * lerpf(pulse_base, pulse_near, near)

	var p: float = (sin(_pulse_t) + 1.0) * 0.5
	_mat.albedo_color = _base_color.lerp(prime_color, p * 0.45 * near)

	var s: float = 1.0 + p * 0.06 * near
	mesh.scale = _base_scale * Vector3(s, 1.0 / s, s)


# ---------------------------------------------------------------- OUTILS

func _distance_to_player() -> float:
	var v: Vector3 = player.global_position - global_position
	v.y = 0.0
	return v.length()


func _dir_to_player() -> Vector3:
	var v: Vector3 = player.global_position - global_position
	v.y = 0.0
	if v.length() < 0.01:
		return -global_transform.basis.z
	return v.normalized()


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var a := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, a, turn_speed * delta)


# ---------------------------------------------------------------- DÉGÂTS

func take_hit(direction: Vector3, damage: int = damage_per_hit) -> void:
	if state == State.DEAD or state == State.PRIMED:
		return

	health -= damage
	health_bar.set_ratio(float(health) / float(max_health))

	if health <= 0:
		_die(direction)
		return

	_knockback = direction * knockback_force
	_hurt_t = 0.3
	mesh.scale = _base_scale


## Étourdir un kamikaze le désamorce temporairement : c'est la seule façon
## de le neutraliser sans déclencher son explosion.
func stun(duration: float) -> void:
	pass


func is_stunned() -> bool:
	return false


## Mort par les coups du joueur : il explose quand même. C'est tout l'intérêt
## de l'ennemi — le tuer ne suffit pas, il faut le tuer AU BON ENDROIT.
func _die(direction: Vector3) -> void:
	_drop_pickups()
	_explode()


func _explode() -> void:
	if state == State.DEAD:
		return
	_set_state(State.DEAD)
	died.emit()

	if blast_scene != null:
		var z: Node3D = blast_scene.instantiate()
		get_tree().current_scene.add_child(z)
		# Posée au sol sous l'ennemi, pas à sa hauteur : la zone est une
		# surface, elle doit être lisible depuis la caméra isométrique.
		z.global_position = Vector3(global_position.x, _ground_y(), global_position.z)

	hurt_box.monitorable = false
	set_collision_layer_value(1, false)
	health_bar.visible = false
	velocity = Vector3.ZERO

	var t := create_tween().set_parallel(true)
	t.tween_property(mesh, "scale", Vector3(0.05, 0.05, 0.05), 0.14)\
		.set_ease(Tween.EASE_IN)
	t.tween_property(_mat, "albedo_color:a", 0.0, 0.14)

	await t.finished
	queue_free()


func _ground_y() -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.0,
		global_position + Vector3.DOWN * 3.0
	)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return hit.position.y + 0.02 if not hit.is_empty() else global_position.y


func _drop_pickups() -> void:
	if pickup_scene == null or randf() > pickup_chance:
		return

	var n: int = 1 + (randi() % maxi(pickup_max, 1))
	for i in n:
		var p: Node3D = pickup_scene.instantiate()
		get_tree().current_scene.add_child(p)
		p.global_position = global_position + Vector3.UP * 0.6
