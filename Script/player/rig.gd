extends Node3D

## Rig procédural style Rayman : pieds/mains détachés, corps tiré par un ressort.
## Les nœuds Body, FootL, FootR, HandL, HandR sont mis en top_level : ils vivent
## en coordonnées monde et peuvent donc prendre du retard sur le Player.
##
## RÈGLE CENTRALE : le corps est toujours attiré par une extrémité motrice.
## Au repos et à la marche, ce sont les pieds — l'attraction vient du bas, donc
## le buste décroche en arrière, comme pris de vitesse. Dès qu'une main frappe,
## l'attraction bascule vers elle — elle vient du haut et de l'avant, donc le
## buste part en avant. C'est le même calcul dans les deux cas ; seuls le point
## d'attraction et le signe de l'inclinaison changent.
##
## Ce script ne gère QUE le visuel. La logique d'attaque (input, combo, dégâts)
## vit dans Combat.gd, qui pilote ce rig via play_attack / set_attack_progress /
## end_attack / play_charge / set_charge_progress / end_charge / play_dash /
## set_dash_progress / end_dash, et lit get_attack_position pour ses hitbox.

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
@export var lean_degrees: float = 20.0      ## inclinaison max quand les pieds mènent
@export var lean_pull_scale: float = 0.35   ## étirement (unités) pour l'inclinaison max
@export var lean_speed: float = 14.0        ## rapidité de la bascule

@export_group("Attraction par les mains")
@export var punch_attract: float = 0.40     ## poids de la main pour un coup simple
@export var slam_attract: float = 0.55      ## poids pour le coup 3
@export var dash_attract: float = 1.0       ## poids pour le dash chargé
@export var attract_speed: float = 12.0     ## vitesse de bascule entre pieds et main
@export var attract_gap: float = 0.55       ## distance à laquelle le corps suit la main
@export var attract_rise: float = 0.10      ## élévation du corps quand la main mène
@export var hand_lean_degrees: float = 75.0 ## inclinaison max quand la main mène

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

@export_group("Attaque chargée")
@export var charge_windup: float = 0.18     ## mise en place avant que ça tourne
@export var charge_orbit_min: float = 0.18  ## rayon du cercle au début de la charge
@export var charge_orbit_max: float = 0.42  ## rayon à charge pleine
@export var charge_spin_min: float = 9.0    ## vitesse de rotation (rad/s) au début
@export var charge_spin_max: float = 38.0   ## vitesse à charge pleine
@export var charge_crouch: float = 0.15     ## tassement du corps
@export var charge_lean_back: float = 0.22  ## recul du corps pendant l'armement
@export var charge_shake: float = 0.03      ## vibration à charge pleine

@export_group("Dash chargé")
@export var dash_lead_fraction: float = 0.35  ## le poing arrive à 35% du trajet
@export var dash_hand_height: float = 0.85
@export var dash_feet_trail: float = 0.55     ## retard des pieds derrière le corps
@export var dash_feet_lift: float = 0.45      ## hauteur à laquelle ils pendent
@export var dash_feet_spread: float = 0.22    ## écartement pendant le vol
@export var dash_feet_catch: float = 6.0      ## vitesse de rattrapage du corps
@export var dash_land_impulse: float = 2.2    ## encaissement à la réception

@export_group("Impact")
@export var impact_hold: float = 0.10      ## durée du blocage du poing
@export var impact_recoil: float = 0.12    ## léger recul au contact

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

## Poids courant de l'attraction par la main : 0 = pieds seuls, 1 = main seule.
## Lissé pour éviter les à-coups au début et à la fin d'un coup.
var _lead_w: float = 0.0

## Attaque : 0 = aucune, 1 = main droite, 2 = main gauche, 3 = slam deux mains
var _atk_kind: int = 0
var _atk_t: float = 0.0
var _recover_t: float = 0.0
var _recover_side: float = 0.0   ## 0 = les deux mains récupèrent

## Charge : mise en place, puis cercle vertical devant le corps
var _charging: bool = false
var _charge_k: float = 0.0
var _spin_angle: float = 0.0
var _charge_from := Vector3.ZERO   ## d'où la main part
var _windup_t: float = 0.0         ## progression de la mise en place, 0 → 1
var _dash_hit: bool = false

## Dash : le poing se plante à un point fixe du monde, le corps vient l'y rejoindre
var _dashing: bool = false
var _dash_k: float = 0.0
var _dash_power: float = 0.0
var _dash_from := Vector3.ZERO
var _dash_target := Vector3.ZERO
var _fist_pos := Vector3.ZERO
##Impact
var _impact_t: float = 0.0
var _impact_pos := Vector3.ZERO
var _impact_side: float = 0.0

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
	_update_lead(delta)
	_update_feet(delta)
	_update_body(delta)
	_update_charge_body()
	_update_hands(delta)


# ------------------------------------------------------- ATTRACTION UNIFIÉE

## Poids visé de l'attraction par la main, selon ce qui se passe.
func _target_lead_weight() -> float:
	if _dashing:
		return dash_attract
	if _charging:
		return 0.0          # la charge tire le corps en arrière, pas en avant
	match _atk_kind:
		1, 2:
			return punch_attract
		3:
			return slam_attract
	return 0.0


func _update_lead(delta: float) -> void:
	var t: float = 1.0 - exp(-attract_speed * delta)
	_lead_w = lerpf(_lead_w, _target_lead_weight(), t)


## La main qui mène le mouvement. Lue avec une frame de retard, ce qui est
## exactement ce qu'on veut : le corps réagit après la main, pas avec elle.
func _lead_hand_position() -> Vector3:
	if _dashing:
		return hand_r.global_position
	if _atk_kind == 3:
		return (hand_l.global_position + hand_r.global_position) * 0.5
	if _atk_kind == 2:
		return hand_l.global_position
	return hand_r.global_position


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


# ---------------------------------------------------------------- API CHARGE

func play_charge() -> void:
	_charging = true
	_charge_k = 0.0
	_spin_angle = 0.0
	_windup_t = 0.0
	_charge_from = hand_r.global_position


func set_charge_progress(k: float) -> void:
	_charge_k = clampf(k, 0.0, 1.0)


func end_charge() -> void:
	_charging = false


## target : le point du monde où le poing va se planter (fourni par Combat.gd)
func play_dash(power: float, target: Vector3) -> void:
	_charging = false
	_dashing = true
	_dash_hit = false
	_dash_k = 0.0
	_dash_power = clampf(power, 0.0, 1.0)
	_dash_from = hand_r.global_position
	_dash_target = target + Vector3.UP * dash_hand_height


func set_dash_progress(k: float) -> void:
	_dash_k = clampf(k, 0.0, 1.0)


func end_dash() -> void:
	_dashing = false
	_body_vel.y -= dash_land_impulse
	for f in _feet:
		f.planted = _rest_target(f)
		f.stepping = false


## Centre du cercle de charge : la position de repos de la main droite.
## On ne prend PAS sa position réelle : en déplacement le ressort la laisse
## traîner derrière, et ce retard serait figé pour toute la charge.
func _charge_center() -> Vector3:
	return player.global_transform * Vector3(
		hand_offset.x, hand_offset.y + body_height, hand_offset.z
	)


## Deux temps : la main rejoint d'abord le sommet du cercle, puis tourne.
func _charge_hand_position(delta: float) -> Vector3:
	var center: Vector3 = _charge_center()
	var fwd: Vector3 = -player.global_transform.basis.z
	var radius: float = lerpf(charge_orbit_min, charge_orbit_max, _charge_k)

	# --- Phase 1 : mise en place, la main monte au sommet du cercle ---
	if _windup_t < 1.0:
		_windup_t = minf(_windup_t + delta / charge_windup, 1.0)
		var e: float = _windup_t * _windup_t * (3.0 - 2.0 * _windup_t)
		return _charge_from.lerp(center + Vector3.UP * radius, e)

	# --- Phase 2 : rotation. cos(0) = 1, donc on repart pile du sommet ---
	_spin_angle += lerpf(charge_spin_min, charge_spin_max, _charge_k) * delta

	return center \
		+ Vector3.UP * cos(_spin_angle) * radius \
		+ fwd * sin(_spin_angle) * radius


## Le poing atteint son point d'impact bien avant le joueur, puis l'attend.
func _dash_hand_position() -> Vector3:
	if _impact_t > 0.0 or _dash_hit:
		return _impact_pos

	var k: float = clampf(_dash_k / dash_lead_fraction, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 3.0)
	return _dash_from.lerp(_dash_target, e)


## Effets propres à la charge : tassement et recul. Le dash, lui, passe
## entièrement par l'attraction unifiée de _update_body.
func _update_charge_body() -> void:
	if not _charging:
		return

	var fwd: Vector3 = -player.global_transform.basis.z
	var shake: float = _charge_k * charge_shake

	body.global_position += -fwd * charge_lean_back * _charge_k \
		+ Vector3.DOWN * charge_crouch * _charge_k \
		+ Vector3(
			randf_range(-shake, shake),
			randf_range(-shake, shake),
			randf_range(-shake, shake)
		)


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
	# Pendant le dash, les pieds ne marchent plus : ils traînent derrière le corps
	if _dashing:
		_update_dash_feet(delta)
		return

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


## Les pieds pendent derrière le corps, comme emportés par le poids du poing.
func _update_dash_feet(delta: float) -> void:
	var fwd: Vector3 = -player.global_transform.basis.z
	var right: Vector3 = player.global_transform.basis.x
	var t: float = 1.0 - exp(-dash_feet_catch * delta)

	for f in _feet:
		var target: Vector3 = body.global_position \
			- fwd * dash_feet_trail \
			- Vector3.UP * dash_feet_lift \
			+ right * f.side * dash_feet_spread

		f.node.global_position = f.node.global_position.lerp(target, t)
		f.stepping = false
		f.t = 0.0
		# Le pied "atterrit" là où il est : évite un retour brutal à la fin du dash
		f.planted = _rest_target(f)


# ---------------------------------------------------------------- CORPS

func _update_body(delta: float) -> void:
	# --- Le point qui attire le corps ---
	var mid: Vector3 = (foot_l.global_position + foot_r.global_position) * 0.5
	var foot_anchor: Vector3 = mid + Vector3.UP * body_height
	var target: Vector3 = foot_anchor

	if _lead_w > 0.01:
		var lead_pos: Vector3 = _lead_hand_position()

		# Le corps se place en retrait de la main, dans l'axe main-corps :
		# ça marche aussi bien pour un coup latéral que pour une frappe avant.
		var to_hand: Vector3 = lead_pos - _body_pos
		to_hand.y = 0.0
		var dir: Vector3 = to_hand.normalized() if to_hand.length() > 0.01 \
			else -player.global_transform.basis.z

		var hand_anchor: Vector3 = lead_pos - dir * attract_gap
		hand_anchor.y = foot_anchor.y + attract_rise

		target = foot_anchor.lerp(hand_anchor, _lead_w)

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

	# --- Inclinaison : dictée par l'origine de la traction ---
	# Tiré par le bas (pieds) : le haut décroche en arrière.
	# Tiré par le haut (main) : le haut part en avant. D'où le signe qui bascule.
	var pull := to_target
	pull.y = 0.0
	var local_pull: Vector3 = Basis(Vector3.UP, player.rotation.y).inverse() * pull
	local_pull /= lean_pull_scale

	var lean_max: float = lerpf(lean_degrees, hand_lean_degrees, _lead_w)
	if player.is_sprinting and _lead_w < 0.01:
		lean_max *= sprint_lean_multiplier
	var lean := deg_to_rad(lean_max)

	var lean_sign: float = lerpf(1.0, -1.0, _lead_w)
	var t: float = 1.0 - exp(-lean_speed * delta)

	body.rotation.y = player.rotation.y
	body.rotation.x = lerp(
		body.rotation.x,
		-clampf(local_pull.z, -1.0, 1.0) * lean * lean_sign,
		t
	)
	body.rotation.z = lerp(
		body.rotation.z,
		clampf(local_pull.x, -1.0, 1.0) * lean * lean_sign,
		t
	) + sway


# ---------------------------------------------------------------- MAINS

func _update_hands(delta: float) -> void:

	if _impact_t > 0.0:
		_impact_t = maxf(_impact_t - delta, 0.0)
	# Le temps de l'attaque est piloté par Combat.gd ; ici, juste la récupération
	if _atk_kind == 0 and _recover_t > 0.0:
		_recover_t = maxf(_recover_t - delta, 0.0)

	# La position de charge est calculée une seule fois par frame : l'angle de
	# rotation s'incrémente dedans, l'appeler par main le ferait tourner double.
	var charge_pos := Vector3.ZERO
	if _charging:
		charge_pos = _charge_hand_position(delta)
	elif _dashing:
		_fist_pos = _dash_hand_position()

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
		if _impact_t > 0.0 and (_impact_side == 0.0 or h.side == _impact_side):
			h.pos = _impact_pos
			h.vel = Vector3.ZERO
			h.node.global_position = h.pos
			h.node.rotation = body.rotation
			continue
		var target: Vector3 = body.global_position + b * local

		# --- Charge et dash : seul le poing droit est piloté ---
		if h.side > 0.0 and (_charging or _dashing):
			h.pos = charge_pos if _charging else _fist_pos
			h.vel = Vector3.ZERO
			h.node.global_position = h.pos
			h.node.rotation = body.rotation
			continue

		# --- Cette main est-elle pilotée par l'attaque en cours ? ---
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


## Le poing bute sur ce qu'il a touché au lieu de poursuivre sa trajectoire.
func hit_impact(side: float) -> void:
	_impact_side = side
	_impact_t = impact_hold

	var current: Vector3 = hand_r.global_position if side > 0.0 else hand_l.global_position
	var back: Vector3 = _body_pos - current
	back.y = 0.0
	if back.length() > 0.01:
		current += back.normalized() * impact_recoil

	if _dashing :
		_dash_hit = true
	_impact_pos = current
