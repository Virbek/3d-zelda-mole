extends Node3D

## Rig procédural style Rayman : pieds/mains détachés, corps tiré par un ressort.
## Les nœuds Body, FootL, FootR, HandL, HandR sont mis en top_level : ils vivent
## en coordonnées monde et peuvent donc prendre du retard sur le Player.
##
## Ce script ne gère QUE le visuel. La logique d'attaque (input, combo, dégâts)
## vit dans Combat.gd, qui pilote ce rig via play_attack / set_attack_progress /
## end_attack et lit get_attack_position pour ses hitbox.

@export var player_path: NodePath

@export_group("Pieds")
@export var stance_width: float = 0.30      ## écartement latéral des pieds
@export var step_threshold: float = 0.50    ## distance avant de déclencher un pas
@export var step_duration: float = 0.20     ## durée d'un pas
@export var step_height: float = 0.20       ## hauteur de l'arc du pas
@export var step_lead: float = 0.45         ## anticipation dans la direction du mouvement

@export_group("Corps")
@export var body_height: float = 1.00
@export var stiffness: float = 90.0         ## force du champ d'attraction
@export var damping: float = 6.0            ## plus bas = plus de rebond
@export var lean_degrees: float = 20.0
@export var lean_pull_scale: float = 0.35   ## étirement (unités) pour l'inclinaison max

@export_group("Ressenti des pas")
@export var bob_height: float = 0.07        ## montée du corps pendant un pas
@export var sway_degrees: float = 5.0       ## roulis vers le pied d'appui
@export var push_impulse: float = 0.9       ## coup de reins au départ du pas
@export var land_impulse: float = 1.3       ## encaissement à la pose

@export_group("Sprint")
@export var sprint_lean_multiplier: float = 1.7
@export var sprint_lead_multiplier: float = 1.8
@export var sprint_swing_multiplier: float = 1.6

@export_group("Esquive")
@export var dodge_step_duration: float = 0.11
@export var dodge_lead_multiplier: float = 2.6

@export_group("Mains")
@export var hand_offset := Vector3(0.55, 0.02, 0.05)  ## x latéral, y hauteur, z arrière
@export var hand_stiffness: float = 55.0
@export var hand_damping: float = 7.0
@export var hand_swing: float = 0.35

@export_group("Attaque")
@export var attack_reach: float = 0.85      ## rayon du balayage circulaire
@export var attack_height: float = 0.15     ## hauteur relative au centre du corps
@export var attack_arc: float = 180.0       ## amplitude du balayage en degrés
@export var attack_recover: float = 0.12    ## retour progressif au ressort

@export_group("Coup 3 (frappe verticale)")
@export var slam_wind_end: float = 0.45     ## fin de l'armé (fraction du coup)
@export var slam_strike_end: float = 0.72   ## fin de l'abattement
@export var slam_top: float = 1.15          ## hauteur au sommet de l'armé
@export var slam_back: float = 0.55         ## recul derrière le corps à l'armé
@export var slam_reach: float = 1.20        ## avancée au point d'impact
@export var slam_bottom: float = -0.30      ## hauteur au point d'impact
@export var slam_spread: float = 0.30       ## écartement des mains au repos
@export var slam_join: float = 0.06         ## écartement au sommet (mains collées)

@onready var player: CharacterBody3D = get_node(player_path)
@onready var body: Node3D = $Body
@onready var foot_l: Node3D = $FootL
@onready var foot_r: Node3D = $FootR
@onready var hand_l: Node3D = $HandL
@onready var hand_r: Node3D = $HandR


class Foot:
	var node: Node3D
	var side: float = 1.0
	var planted := Vector3.ZERO
	var stepping := false
	var t := 0.0
	var from := Vector3.ZERO
	var to := Vector3.ZERO


class Hand:
	var node: Node3D
	var side: float = 1.0
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO


var _feet := []
var _hands := []

var _body_pos := Vector3.ZERO
var _body_vel := Vector3.ZERO

var _was_dodging := false

## Attaque : 0 = aucune, 1 = main droite, 2 = main gauche, 3 = slam deux mains
var _atk_kind: int = 0
var _atk_t: float = 0.0
var _recover_t: float = 0.0
var _recover_side: float = 0.0   ## 0 = les deux mains récupèrent


func _ready() -> void:
	for n in [body, foot_l, foot_r, hand_l, hand_r]:
		n.top_level = true

	for data in [[foot_l, -1.0], [foot_r, 1.0]]:
		var f := Foot.new()
		f.node = data[0]
		f.side = data[1]
		_feet.append(f)

	for f in _feet:
		f.planted = _rest_target(f)
		f.node.global_position = f.planted

	_body_pos = player.global_position + Vector3.UP * body_height
	body.global_position = _body_pos

	for data in [[hand_l, -1.0], [hand_r, 1.0]]:
		var h := Hand.new()
		h.node = data[0]
		h.side = data[1]
		h.pos = _body_pos + Vector3(hand_offset.x * h.side, hand_offset.y, hand_offset.z)
		h.node.global_position = h.pos
		_hands.append(h)


func _physics_process(delta: float) -> void:
	_update_feet(delta)
	_update_body(delta)
	_update_hands(delta)


# ---------------------------------------------------------------- API ATTAQUE
# Appelée par Combat.gd. Le rig ne décide de rien, il joue.

## kind : 1 = main droite, 2 = main gauche, 3 = slam des deux mains
func play_attack(kind: int) -> void:
	_atk_kind = kind
	_atk_t = 0.0


## Combat.gd fait avancer le temps, pour que visuel et hitbox restent synchrones
func set_attack_progress(t: float) -> void:
	_atk_t = t


func end_attack() -> void:
	_recover_side = 0.0 if _atk_kind == 3 else (1.0 if _atk_kind == 1 else -1.0)
	_atk_kind = 0
	_recover_t = attack_recover


## Position d'une main à l'instant t. side : 1 = droite, -1 = gauche
func get_attack_position(t: float, side: float) -> Vector3:
	if _atk_kind == 3:
		return _slam_position(t, side)
	return _sweep_position(t, side)


## Balayage circulaire horizontal.
## Ancrage sur le corps (distance constante au buste),
## orientation sur le Player (cap stable, jamais incliné).
func _sweep_position(t: float, side: float) -> Vector3:
	var half := deg_to_rad(attack_arc) * 0.5

	# Adoucit le départ et la fin sans changer les extrémités
	var e: float = t * t * (3.0 - 2.0 * t)

	# La main droite balaye droite -> gauche, la gauche fait l'inverse
	var angle: float = lerp(-half, half, e) * side

	var fwd := Vector3.FORWARD.rotated(Vector3.UP, player.rotation.y)
	var dir: Vector3 = fwd.rotated(Vector3.UP, angle)

	var origin: Vector3 = body.global_position + Vector3.UP * attack_height
	return origin + dir * attack_reach


## Frappe verticale : armé haut et en arrière, abattement en arc, retour en garde.
func _slam_position(t: float, side: float) -> Vector3:
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, player.rotation.y)
	var right := Vector3.RIGHT.rotated(Vector3.UP, player.rotation.y)

	# Points clés de la trajectoire, en coordonnées (avant, hauteur)
	var p_rest := Vector2(hand_offset.z * -1.0, hand_offset.y)
	var p_top := Vector2(-slam_back, slam_top)
	var p_hit := Vector2(slam_reach, slam_bottom)

	var pos: Vector2
	var spread: float

	if t < slam_wind_end:
		# --- 1. Armé : les mains montent en arrière et se rejoignent ---
		var k: float = t / slam_wind_end
		var e: float = k * k * (3.0 - 2.0 * k)   # doux au départ et à l'arrivée
		pos = p_rest.lerp(p_top, e)
		spread = lerp(slam_spread, slam_join, e)

	elif t < slam_strike_end:
		# --- 2. Abattement : arc vertical, accélération brutale ---
		var k: float = (t - slam_wind_end) / (slam_strike_end - slam_wind_end)
		var e: float = pow(k, 2.4)

		# Arc de cercle : le centre est devant et en haut du corps
		var a_start := atan2(p_top.y, p_top.x)
		var a_end := atan2(p_hit.y, p_hit.x)
		var radius: float = lerp(p_top.length(), p_hit.length(), e)
		var a: float = lerp_angle(a_start, a_end, e)

		pos = Vector2(cos(a), sin(a)) * radius
		spread = slam_join

	else:
		# --- 3. Retour en garde ---
		var k: float = (t - slam_strike_end) / (1.0 - slam_strike_end)
		var e: float = k * k * (3.0 - 2.0 * k)
		pos = p_hit.lerp(p_rest, e)
		spread = lerp(slam_join, slam_spread, e)

	return body.global_position \
		+ fwd * pos.x \
		+ Vector3.UP * pos.y \
		+ right * side * spread


# ---------------------------------------------------------------- PIEDS

## Où le pied "devrait" être, compte tenu de la position et de la vitesse actuelles.
func _rest_target(f: Foot) -> Vector3:
	var b: Basis = player.global_transform.basis
	var hv := Vector3(player.velocity.x, 0.0, player.velocity.z)

	var lead := Vector3.ZERO
	if hv.length() > 0.1:
		var l := step_lead
		if player.is_dodging:
			l *= dodge_lead_multiplier
		elif player.is_sprinting:
			l *= sprint_lead_multiplier
		lead = hv.normalized() * l

	var p: Vector3 = player.global_position + b.x * f.side * stance_width + lead

	# Cherche le sol réel sous la position visée
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		p + Vector3.UP * 2.0,
		p + Vector3.DOWN * 2.0
	)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		p.y = player.global_position.y
	else:
		p.y = hit.position.y

	return p


func _update_feet(delta: float) -> void:
	# Au démarrage de l'esquive, les deux pieds décollent ensemble : ça fait un bond
	if player.is_dodging and not _was_dodging:
		for f in _feet:
			f.stepping = true
			f.t = 0.0
			f.from = f.planted
			f.to = _rest_target(f)
		_body_vel += _feet[0].to - _feet[0].from
	_was_dodging = player.is_dodging

	# 1. Faire avancer les pas en cours
	for f in _feet:
		if f.stepping:
			var dur: float = dodge_step_duration if player.is_dodging else step_duration
			f.t += delta / dur
			if f.t >= 1.0:
				f.t = 1.0
				f.stepping = false
				f.planted = f.to
				_body_vel.y -= land_impulse
			var p: Vector3 = f.from.lerp(f.to, f.t)
			p.y += sin(f.t * PI) * step_height
			f.node.global_position = p
		else:
			f.node.global_position = f.planted

	# 2. Un seul pied en l'air à la fois (sauf au départ de l'esquive, ci-dessus)
	for f in _feet:
		if f.stepping:
			return

	# 3. Déclencher le pas du pied le plus en retard
	var worst: Foot = null
	var worst_dist := step_threshold
	for f in _feet:
		var d: float = f.planted.distance_to(_rest_target(f))
		if d > worst_dist:
			worst_dist = d
			worst = f

	if worst != null:
		worst.stepping = true
		worst.t = 0.0
		worst.from = worst.planted
		worst.to = _rest_target(worst)

		var dir: Vector3 = worst.to - worst.from
		dir.y = 0.0
		if dir.length() > 0.01:
			_body_vel += dir.normalized() * push_impulse


# ---------------------------------------------------------------- CORPS

func _update_body(delta: float) -> void:
	var mid: Vector3 = (foot_l.global_position + foot_r.global_position) * 0.5
	var target: Vector3 = mid + Vector3.UP * body_height

	# --- Ressort : la traction, lente ---
	var to_target: Vector3 = target - _body_pos
	_body_vel += to_target * stiffness * delta
	_body_vel *= exp(-damping * delta)
	_body_pos += _body_vel * delta

	# --- Rythme des pas : rapide, hors ressort ---
	var step_t := -1.0
	var support := 0.0
	for f in _feet:
		if f.stepping:
			step_t = f.t
			support = -f.side   # l'appui est sur le pied resté au sol

	var bob := 0.0
	var sway := 0.0
	if step_t >= 0.0:
		var s: float = sin(step_t * PI)
		bob = s * bob_height
		sway = s * support * deg_to_rad(sway_degrees)

	body.global_position = _body_pos + Vector3.UP * bob

	# --- Inclinaison : tiré par les pieds, le haut part en arrière ---
	var pull := to_target
	pull.y = 0.0
	var local_pull: Vector3 = Basis(Vector3.UP, player.rotation.y).inverse() * pull
	local_pull /= lean_pull_scale

	var lean := deg_to_rad(lean_degrees)
	if player.is_sprinting:
		lean *= sprint_lean_multiplier

	body.rotation.y = player.rotation.y
	body.rotation.x = lerp(body.rotation.x, -clampf(local_pull.z, -1.0, 1.0) * lean, 10.0 * delta)
	body.rotation.z = lerp(body.rotation.z, clampf(local_pull.x, -1.0, 1.0) * lean, 10.0 * delta) + sway


# ---------------------------------------------------------------- MAINS

func _update_hands(delta: float) -> void:
	# Le temps de l'attaque est piloté par Combat.gd ; ici, juste la récupération
	if _atk_kind == 0 and _recover_t > 0.0:
		_recover_t = maxf(_recover_t - delta, 0.0)

	# --- Balancement : la main opposée au pied en l'air part devant ---
	var swing := 0.0
	var swing_side := 0.0
	for f in _feet:
		if f.stepping:
			swing = sin(f.t * PI) * hand_swing
			if player.is_sprinting:
				swing *= sprint_swing_multiplier
			swing_side = -f.side

	# On travaille dans le repère du corps : les mains héritent de son inclinaison
	var b: Basis = body.global_transform.basis

	for h in _hands:
		var local := Vector3(hand_offset.x * h.side, hand_offset.y, hand_offset.z)
		if h.side == swing_side:
			local.z -= swing   # -Z = avant en Godot
		else:
			local.z += swing * 0.6

		var target: Vector3 = body.global_position + b * local

		# Cette main est-elle pilotée par l'attaque en cours ?
		var driven := false
		if _atk_kind == 3:
			driven = true
		elif _atk_kind == 1 and h.side > 0.0:
			driven = true
		elif _atk_kind == 2 and h.side < 0.0:
			driven = true

		if driven:
			h.pos = get_attack_position(_atk_t, h.side)
			h.vel = Vector3.ZERO
			h.node.global_position = h.pos
			h.node.rotation = body.rotation
			continue

		# Reprise en douceur après le coup : la raideur remonte progressivement
		var stiff := hand_stiffness
		if _recover_t > 0.0 and (_recover_side == 0.0 or h.side == _recover_side):
			stiff *= 1.0 - (_recover_t / attack_recover)

		h.vel += (target - h.pos) * stiff * delta
		h.vel *= exp(-hand_damping * delta)
		h.pos += h.vel * delta

		h.node.global_position = h.pos
		h.node.rotation = body.rotation