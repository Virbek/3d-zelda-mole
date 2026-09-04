extends Node

## Logique de combat du joueur : combo 3 coups, attaque chargée avec dash.
##
## Ce script ne dessine rien. Il pilote le rig via play_attack /
## set_attack_progress / end_attack / play_charge / set_charge_progress /
## end_charge / play_dash / set_dash_progress / end_dash, et lit
## get_attack_position pour ses hitbox.
##
## Le clic gauche est ambigu par nature : appui court = coup normal,
## appui maintenu = charge. On ne peut donc pas déclencher l'attaque au
## moment de l'appui — il faut attendre charge_delay pour trancher.

@export var rig_path: NodePath

@export_group("Combo")
@export var durations: Array[float] = [0.26, 0.24, 0.42]
@export var hit_windows: Array[Vector2] = [
	Vector2(0.25, 0.65),
	Vector2(0.20, 0.60),
	Vector2(0.30, 0.75),
]
@export var chain_open: float = 0.35     ## à partir de quand on peut bufferiser
@export var chain_grace: float = 0.25    ## fenêtre après un coup pour enchaîner
@export var hit_radius: float = 0.55
@export_flags_3d_physics var hit_mask: int = 2

@export_group("Bond du finisher")
@export var hop_force: float = 4.5
@export var hop_forward: float = 3.0

@export_group("Soin")
@export var full_combo_heal: int = 1     ## soin quand le coup 3 touche

@export_group("Attaque chargée")
@export var charge_delay: float = 0.15       ## maintien avant d'entrer en charge
@export var charge_ramp_time: float = 0.18   ## doit correspondre au charge_windup du rig
@export var charge_min_time: float = 0.30    ## en dessous : simple coup normal
@export var charge_max_time: float = 1.10    ## charge pleine

@export_group("Dash chargé")
@export var dash_distance_min: float = 5.0   ## portée à charge minimale
@export var dash_distance_max: float = 10.0   ## portée à charge pleine
@export var dash_speed_min: float = 15.0
@export var dash_speed_max: float = 26.0
@export var dash_max_time: float = 0.6       ## sécurité anti-blocage
@export var dash_radius: float = 1.4
@export var dash_damage: int = 3             ## dégâts à charge pleine
@export var dash_shake: float = 0.5

@export_group("Hit stop")
@export var hit_stop_time: float = 0.06
@export var hit_stop_scale: float = 0.05

@onready var player: CharacterBody3D = get_parent()
@onready var rig: Node3D = get_node(rig_path)

var is_charging: bool = false
var is_dashing: bool = false

## Progression de la mise en charge, 0 → 1. Lue par Player.gd pour ralentir
## le déplacement en même temps que le poing se met en place.
var charge_ramp: float = 0.0

var _step: int = 0                ## 0 = inactif, 1..3 = coup en cours
var _t: float = 0.0               ## progression normalisée du coup courant
var _last_step: int = 0
var _grace: float = 0.0
var _buffered: bool = false
var _hit_list: Array = []
var _prev_pos: Array = []

var _press_t: float = -1.0        ## -1 = aucun appui en attente
var _press_step: int = 1          ## coup que l'appui déclenchera s'il est relâché
var _charge_t: float = 0.0
var _healed_this_combo: bool = false

var _dash_t: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _dash_power: float = 0.0
var _dash_start: Vector3 = Vector3.ZERO
var _dash_dist: float = 0.0


var is_attacking: bool:
	get:
		return _step != 0


# ---------------------------------------------------------------- ENTRÉES

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("attack"):
		return
	if player.is_dodging or is_charging or is_dashing:
		return

	if _step == 0:
		# On ne lance rien tout de suite : il faut voir si le joueur maintient
		if _grace > 0.0 and _last_step < 3:
			_press_step = _last_step + 1
		else:
			_press_step = 1
		_press_t = 0.0
	elif _t >= chain_open and _step < 3:
		_buffered = true   # mémorisé, joué à la fin du coup courant


# ---------------------------------------------------------------- BOUCLE

func _physics_process(delta: float) -> void:
	_handle_charge(delta)

	if is_dashing:
		return

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
		_step = 0
		_t = 0.0
		_grace = chain_grace
		if _buffered and _last_step < 3:
			_start(_last_step + 1)


func _start(step: int) -> void:
	if step == 1:
		_healed_this_combo = false

	_step = step
	_last_step = step
	_t = 0.0
	_grace = 0.0
	_buffered = false
	_hit_list.clear()
	_prev_pos.clear()
	rig.play_attack(step)

	if step == 3:
		_hop()


func _hop() -> void:
	var fwd: Vector3 = -player.global_transform.basis.z
	player.velocity.y = hop_force
	player.velocity.x += fwd.x * hop_forward
	player.velocity.z += fwd.z * hop_forward


# ---------------------------------------------------------------- CHARGE

func _handle_charge(delta: float) -> void:
	if is_dashing:
		_process_dash(delta)
		return

	# Phase d'attente : coup normal ou début de charge ?
	if _press_t >= 0.0:
		_press_t += delta

		if player.is_dodging:
			_press_t = -1.0
			return

		if not Input.is_action_pressed("attack"):
			_press_t = -1.0
			_start(_press_step)
		elif _press_t >= charge_delay:
			_press_t = -1.0
			is_charging = true
			_charge_t = 0.0
			charge_ramp = 0.0
			rig.play_charge()
		return

	if is_charging:
		if player.is_dodging:
			is_charging = false
			charge_ramp = 0.0
			rig.end_charge()
			return

		# Le ralentissement suit la mise en place du poing
		charge_ramp = minf(charge_ramp + delta / maxf(charge_ramp_time, 0.01), 1.0)

		_charge_t = minf(_charge_t + delta, charge_max_time)
		rig.set_charge_progress(_charge_t / charge_max_time)

		if not Input.is_action_pressed("attack"):
			_release_charge()


func _release_charge() -> void:
	is_charging = false
	charge_ramp = 0.0
	rig.end_charge()

	# Charge avortée : on rend un coup normal plutôt que rien
	if _charge_t < charge_min_time:
		_start(_press_step)
		return

	var span: float = maxf(charge_max_time - charge_min_time, 0.01)
	_dash_power = clampf((_charge_t - charge_min_time) / span, 0.0, 1.0)

	_dash_dir = -player.global_transform.basis.z
	_dash_dir.y = 0.0
	_dash_dir = _dash_dir.normalized()

	_dash_dist = lerpf(dash_distance_min, dash_distance_max, _dash_power)
	_dash_start = player.global_position
	_dash_t = 0.0
	is_dashing = true
	_hit_list.clear()

	# Le poing vise un point fixe du monde : c'est là que le joueur s'arrêtera
	rig.play_dash(_dash_power, _dash_start + _dash_dir * _dash_dist)


func _process_dash(delta: float) -> void:
	_dash_t += delta
	var hit_something: bool = _dash_sweep()
	var spd: float = lerpf(dash_speed_min, dash_speed_max, _dash_power)
	player.velocity.x = _dash_dir.x * spd
	player.velocity.z = _dash_dir.z * spd

	_dash_sweep()

	# Le poing est synchronisé sur la distance parcourue, pas sur le temps :
	# si le joueur percute un mur, le poing s'arrête pile là où il en est.
	var travelled: float = Vector2(
		player.global_position.x - _dash_start.x,
		player.global_position.z - _dash_start.z
	).length()
	rig.set_dash_progress(clampf(travelled / maxf(_dash_dist, 0.01), 0.0, 1.0))

	var blocked: bool = player.get_slide_collision_count() > 0 and _dash_t > 0.03

	if hit_something or travelled >= _dash_dist or blocked or _dash_t >= dash_max_time:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		is_dashing = false
		rig.end_dash()
		_grace = chain_grace


func _dash_sweep() -> bool:
	var space := player.get_world_3d().direct_space_state

	var shape := SphereShape3D.new()
	shape.radius = dash_radius

	var center: Vector3 = player.global_position + _dash_dir * 0.7 + Vector3.UP * 0.8

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), center)
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
			var dmg: int = maxi(1, int(round(lerpf(1.0, float(dash_damage), _dash_power))))
			e.take_hit(_dash_dir, dmg)
			rig.hit_impact(1.0)
			_hit_stop()
			_shake(dash_shake * _dash_power)
			landed = true

	return landed

# ---------------------------------------------------------------- DÉGÂTS

func _check_hits(from_t: float, to_t: float) -> void:
	var w: Vector2 = hit_windows[_step - 1]
	if to_t < w.x or from_t > w.y:
		return

	var sides := [1.0, -1.0] if _step == 3 else [1.0 if _step == 1 else -1.0]

	for side in sides:
		var a: Vector3 = rig.get_attack_position(from_t, side)
		var b: Vector3 = rig.get_attack_position(to_t, side)
		if _sweep(a, b, side) and _step == 3 and not _healed_this_combo:
			_healed_this_combo = true
			if player.has_method("heal"):
				player.heal(full_combo_heal)


## Renvoie true si au moins un ennemi a été touché par ce balayage.
func _sweep(from: Vector3, to: Vector3, side: float) -> bool:
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
			_hit_stop()
			rig.hit_impact(0.0 if _step == 3 else side)

	return landed


# ---------------------------------------------------------------- RESSENTI

## Micro-gel du temps à l'impact. C'est ce qui donne le poids aux coups.
func _hit_stop() -> void:
	if hit_stop_time <= 0.0:
		return
	Engine.time_scale = hit_stop_scale
	await get_tree().create_timer(hit_stop_time * hit_stop_scale, true, false, true).timeout
	Engine.time_scale = 1.0


func _shake(strength: float) -> void:
	if strength <= 0.0:
		return
	var cam := player.get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("shake"):
		cam.get_parent().shake(strength)
