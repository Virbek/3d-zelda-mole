extends Node

## Logique de combat du joueur : combo 3 coups, attaque chargée avec dash.
##
## RÉPARTITION DES RÔLES :
##   - les pieds portent le déplacement (capsule du Player, au sol)
##   - le torse porte les dégâts subis   (HurtBox enfant de Body)
##   - les poings portent les dégâts infligés (FistBox enfant de HandL/HandR)
##
## Les hitbox ne sont donc plus calculées : ce sont de vraies Area3D attachées
## aux mains. Là où le poing se dessine, il frappe. Plus aucun risque que la
## zone de dégâts et le visuel divergent.
##
## Le clic gauche est ambigu par nature : appui court = coup normal,
## appui maintenu = charge. On ne peut pas déclencher l'attaque au moment
## de l'appui — il faut attendre charge_delay pour trancher.

@export var rig_path: NodePath
@export var fist_box_l_path: NodePath
@export var fist_box_r_path: NodePath

@export_group("Combo")
@export var durations: Array[float] = [0.26, 0.24, 0.42]
@export var hit_windows: Array[Vector2] = [
	Vector2(0.25, 0.65),
	Vector2(0.20, 0.60),
	Vector2(0.30, 0.75),
]
@export var chain_open: float = 0.35     ## à partir de quand on peut bufferiser
@export var chain_grace: float = 0.25    ## fenêtre après un coup pour enchaîner

@export_group("Bond du finisher")
@export var hop_force: float = 4.5
@export var hop_forward: float = 3.0

@export_group("Soin")
@export var full_combo_heal: int = 1     ## soin quand le coup 3 touche

@export_group("Attaque chargée")
@export var charge_delay: float = 0.15       ## maintien avant d'entrer en charge
@export var charge_ramp_time: float = 0.18   ## doit valoir le charge_windup du rig
@export var charge_min_time: float = 0.30    ## en dessous : simple coup normal
@export var charge_max_time: float = 1.10    ## charge pleine

@export_group("Dash chargé")
@export var dash_distance_min: float = 2.0   ## portée à charge minimale
@export var dash_distance_max: float = 4.5   ## portée à charge pleine
@export var dash_speed_min: float = 15.0
@export var dash_speed_max: float = 26.0
@export var dash_max_time: float = 0.6       ## sécurité anti-blocage
@export var dash_damage: int = 3             ## dégâts à charge pleine
@export var dash_shake: float = 0.5

@export_group("Hit stop")
@export var hit_stop_time: float = 0.06
@export var hit_stop_scale: float = 0.05

@onready var player: CharacterBody3D = get_parent()
@onready var rig: Node3D = get_node(rig_path)
@onready var fist_l: Area3D = get_node(fist_box_l_path)
@onready var fist_r: Area3D = get_node(fist_box_r_path)

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


func _ready() -> void:
	_set_fists(false, false)


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

	_t += delta / durations[_step - 1]
	rig.set_attack_progress(minf(_t, 1.0))

	# --- Fenêtre de coup : on n'active les poings que sur cet intervalle ---
	var w: Vector2 = hit_windows[_step - 1]
	var open: bool = _t >= w.x and _t <= w.y

	if _step == 3:
		_set_fists(open, open)
	elif _step == 1:
		_set_fists(false, open)
	else:
		_set_fists(open, false)

	if open:
		_collect_hits()

	if _t >= 1.0:
		rig.end_attack()
		_set_fists(false, false)
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
	rig.play_attack(step)

	if step == 3:
		_hop()


func _hop() -> void:
	var fwd: Vector3 = -player.global_transform.basis.z
	player.velocity.y = hop_force
	player.velocity.x += fwd.x * hop_forward
	player.velocity.z += fwd.z * hop_forward


# ---------------------------------------------------------------- POINGS

func _set_fists(left: bool, right: bool) -> void:
	fist_l.monitoring = left
	fist_r.monitoring = right


## Lit ce que les poings touchent réellement. La liste évite qu'un même
## ennemi encaisse plusieurs fois le même coup, frame après frame.
func _collect_hits() -> void:
	for fist in [fist_l, fist_r]:
		if not fist.monitoring:
			continue

		for area in fist.get_overlapping_areas():
			var e = area.get_parent()
			if e == null or e in _hit_list:
				continue
			if not e.has_method("take_hit"):
				continue

			_hit_list.append(e)

			var dir: Vector3 = e.global_position - player.global_position
			dir.y = 0.0
			if dir.length() > 0.01:
				e.take_hit(dir.normalized())

			_hit_stop()

			var side: float = 1.0 if fist == fist_r else -1.0
			rig.hit_impact(0.0 if _step == 3 else side)

			# Le soin ne récompense que le finisher qui touche vraiment
			if _step == 3 and not _healed_this_combo:
				_healed_this_combo = true
				if player.has_method("heal"):
					player.heal(full_combo_heal)


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
	_set_fists(false, true)   # seul le poing droit frappe pendant le dash

	# Le poing vise un point fixe du monde : c'est là que le joueur s'arrêtera
	rig.play_dash(_dash_power, _dash_start + _dash_dir * _dash_dist)


func _process_dash(delta: float) -> void:
	_dash_t += delta

	var spd: float = lerpf(dash_speed_min, dash_speed_max, _dash_power)
	player.velocity.x = _dash_dir.x * spd
	player.velocity.z = _dash_dir.z * spd

	var hit_something: bool = _dash_hits()

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
		_set_fists(false, false)
		rig.end_dash()
		_grace = chain_grace


## Renvoie true si le poing a percuté un ennemi pendant le dash.
func _dash_hits() -> bool:
	var landed := false

	for area in fist_r.get_overlapping_areas():
		var e = area.get_parent()
		if e == null or e in _hit_list:
			continue
		if not e.has_method("take_hit"):
			continue

		_hit_list.append(e)

		var dmg: int = maxi(1, int(round(lerpf(1.0, float(dash_damage), _dash_power))))
		e.take_hit(_dash_dir, dmg)
		rig.hit_impact(1.0)
		_hit_stop()
		_shake(dash_shake * _dash_power)
		landed = true

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
