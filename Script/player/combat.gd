extends Node

@export var rig_path: NodePath
@export_flags_3d_physics var hit_mask: int = 2
@export var hit_stop_times: Array[float] = [0.05, 0.06, 0.11]
@export_group("Timings")
## Durée de chaque coup du combo
@export var durations: Array[float] = [0.26, 0.24, 0.42]
## Début de la fenêtre d'enchaînement (fraction du coup)
@export var chain_open: float = 0.40
## Délai après la fin d'un coup avant reset du combo
@export var chain_grace: float = 0.35

@export_group("Hitbox")
@export var hit_radius: float = 0.22
@export var hit_windows: Array[Vector2] = [
	Vector2(0.05, 0.95),
	Vector2(0.05, 0.95),
	Vector2(0., 1.00),
]

@export_group("Coup 3")
@export var hop_force: float = 5.0
@export var hop_forward: float = 2.5

@onready var player: CharacterBody3D = get_parent()
@onready var rig: Node3D = get_node(rig_path)

@export var full_combo_heal: int = 1
var _step_landed: Array[bool] = [false, false, false]
var _healed_this_combo: bool = false
var _step: int = 0          ## 0 = au repos, 1..3 = coup en cours
var _t: float = 0.0
var _buffered: bool = false
var _grace: float = 0.0
var _hit_list := []
var _prev_pos := {}

var is_attacking: bool:
	get: return _step > 0


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("attack"):
		return
	if player.is_dodging:
		return

	if _step == 0:
		if _grace > 0.0 and _last_step < 3:
			_start(_last_step + 1)
		else:
			_start(1)
	elif _t >= chain_open and _step < 3:
		_buffered = true   # mémorisé, joué à la fin du coup courant


var _last_step: int = 0

func _start(step: int) -> void:
	if step == 1:
		_healed_this_combo = false

	# ↓ tout le reste de TA fonction d'origine, inchangé
	_step = step
	_last_step = step
	_t = 0.0
	_buffered = false
	_hit_list.clear()
	_prev_pos.clear()
	rig.play_attack(step)

	if step == 3:
		_hop()

func _hop() -> void:
	var fwd := -player.global_transform.basis.z
	player.velocity.y = hop_force
	player.velocity.x += fwd.x * hop_forward
	player.velocity.z += fwd.z * hop_forward


func _physics_process(delta: float) -> void:
	if _grace > 0.0:
		_grace = maxf(_grace - delta, 0.0)
		if _grace == 0.0:
			_last_step = 0

	if _step == 0:
		return

	var prev := _t
	_t += delta / durations[_step - 1]
	rig.set_attack_progress(minf(_t, 1.0))

	_check_hits(prev, minf(_t, 1.0))

	if _t >= 1.0:
		rig.end_attack()
		if _step == 3 and not (false in _step_landed):
			player.heal(full_combo_heal)
		_step = 0
		_t = 0.0
		_grace = chain_grace
		if _buffered and _last_step < 3:
			_start(_last_step + 1)


@export var sweep_substeps: int = 6   ## découpage du balayage par frame


func _check_hits(from_t: float, to_t: float) -> void:
	var w: Vector2 = hit_windows[_step - 1]
	if to_t < w.x or from_t > w.y:
		return

	var sides := [1.0, -1.0] if _step == 3 else [1.0 if _step == 1 else -1.0]

	for side in sides:
		var a: Vector3 = rig.get_attack_position(from_t, side)
		var b: Vector3 = rig.get_attack_position(to_t, side)
		if _sweep(a, b) and _step == 3 and not _healed_this_combo:
			_healed_this_combo = true
			player.heal(full_combo_heal)


func _sphere_at(center: Vector3, radius: float) -> void:
	var space := player.get_world_3d().direct_space_state

	var shape := SphereShape3D.new()
	shape.radius = radius

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = hit_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false

	for hit in space.intersect_shape(params, 8):
		var e = hit.collider.get_parent()
		if e in _hit_list:
			continue
		_hit_list.append(e)
		if e.has_method("take_hit"):
			var dir: Vector3 = e.global_position - player.global_position
			dir.y = 0.0
			if dir.length() > 0.01:
				e.take_hit(dir.normalized())
				HitStop.hit(hit_stop_times[_step - 1], 0.05)


func _sweep(from: Vector3, to: Vector3) -> bool:
	var space := player.get_world_3d().direct_space_state

	var shape := SphereShape3D.new()
	shape.radius = hit_radius + from.distance_to(to) * 0.5

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), (from + to) * 0.5)
	params.collision_mask = hit_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false

	var landed := false
	for hit in space.intersect_shape(params, 8):
		var e = hit.collider.get_parent()
		if e in _hit_list:
			continue
		_hit_list.append(e)
		if e.has_method("take_hit"):
			var dir: Vector3 = e.global_position - player.global_position
			dir.y = 0.0
			if dir.length() > 0.01:
				e.take_hit(dir.normalized())
			landed = true
	return landed
