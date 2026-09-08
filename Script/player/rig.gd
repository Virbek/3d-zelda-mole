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
## Le magnétisme dévie le poing vers l'ennemi visé. Comme le corps suit la main,
## une seule correction oriente toute la frappe — c'est ce qui permet de se
## passer d'un verrouillage de cible.
##
## Ce script ne gère QUE le visuel. La logique d'attaque (input, combo, dégâts)
## vit dans Combat.gd, qui pilote ce rig via play_attack / set_attack_progress /
## end_attack / play_charge / set_charge_progress / end_charge / play_punch /
## set_punch_progress / end_punch / hit_impact, et lit get_attack_position et
## get_magnet_target.

@export var player_path: NodePath

@export_group("Collision du rig")
@export var clip_enabled: bool = true
@export var body_clip_radius: float = 0.35   ## marge du buste au mur
@export var hand_clip_radius: float = 0.20   ## marge du poing au mur
@export var hand_stuck_time: float = 0.8     ## délai avant rappel de la main
@export_flags_3d_physics var clip_mask: int = 1   ## calque du décor

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
@export var charged_attract: float = 0.70   ## poids pour le poing chargé
@export var attract_speed: float = 12.0     ## vitesse de bascule entre pieds et main
@export var attract_gap: float = 0.55       ## distance à laquelle le corps suit la main
@export var attract_rise: float = 0.10      ## élévation du corps quand la main mène
@export var hand_lean_degrees: float = 75.0 ## inclinaison max quand la main mène

@export_group("Magnétisme")
@export var magnet_range: float = 3.5        ## portée de l'accrochage
@export var magnet_angle: float = 130.0      ## cône devant le joueur, en degrés
@export var magnet_strength: float = 0.75    ## 0 = aucun, 1 = le poing va pile dessus
@export var magnet_align_weight: float = 2.2 ## poids de l'alignement face à la distance
@export var magnet_standoff: float = 0.5     ## le poing s'arrête devant, pas dedans
@export var magnet_ramp_start: float = 0.35  ## avant ce point du coup (0-1) : aucune correction, l'arc est pur
@export var magnet_ramp_end: float = 0.85    ## à partir de ce point : correction à pleine puissance
@export_flags_3d_physics var magnet_mask: int = 2

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
@export var magnet_range_charged: float = 8.0



@export_group("Toupie")
@export var spin_radius: float = 0.95      ## rayon des poings pendant la rotation
@export var spin_rate: float = 16.0        ## rad/s
@export var spin_height: float = 0.75
@export var spin_body_tilt: float = 8.0    ## léger penché, en degrés
@export_group("Poing chargé")
## Ces trois durées doivent correspondre à celles de Combat.gd, qui pilote
## la progression : si elles divergent, le poing et sa hitbox se désynchronisent.
@export var punch_out_time: float = 0.14    ## aller
@export var punch_hold_time: float = 0.08   ## arrêt au bout
@export var punch_back_time: float = 0.22   ## retour
@export var punch_height: float = 0.85      ## hauteur de vol, relative au corps

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

var _spinning: bool = false
var _spin_k: float = 0.0
var _spin_angle_t: float = 0.0

## Poids courant de l'attraction par la main : 0 = pieds seuls, 1 = main seule.
## Lissé pour éviter les à-coups au début et à la fin d'un coup.
var _lead_w: float = 0.0

var _stuck_t := [0.0, 0.0]   ## index 0 = gauche, 1 = droite

## Attaque : 0 = aucune, 1 = main droite, 2 = main gauche, 3 = slam deux mains
var _atk_kind: int = 0
var _atk_t: float = 0.0
var _recover_t: float = 0.0
var _recover_side: float = 0.0   ## 0 = les deux mains récupèrent

## Cible du magnétisme. Non typée : un nœud libéré ne peut pas être assigné
## à une variable typée Node3D, ce qui ferait planter avant qu'on puisse tester.
var _magnet_target = null

## Charge : mise en place, puis cercle vertical devant le corps
var _charging: bool = false
var _charge_k: float = 0.0
var _spin_angle: float = 0.0
var _charge_from := Vector3.ZERO   ## d'où la main part
var _windup_t: float = 0.0         ## progression de la mise en place, 0 → 1

## Poing chargé : la main quitte le corps, vole, frappe, revient.
## Le joueur, lui, ne bouge pas — c'est ce qui distingue cette attaque du dash.
var _punching: bool = false
var _punch_k: float = 0.0          ## progression 0 → 1 sur l'aller-retour complet
var _punch_from := Vector3.ZERO
var _punch_target := Vector3.ZERO
var _punch_hit: bool = false       ## le poing a buté : il ne repart pas en avant

## Impact
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
	# La cible est libre entre deux coups (le marqueur peut donc l'afficher en
	# continu), mais verrouillée pendant une frappe : sinon le poing zigzaguerait
	# entre deux ennemis en plein mouvement.
	if _atk_kind == 0 and not _punching:
		_acquire_magnet()
	

	_update_lead(delta)
	_update_feet(delta)
	_update_body(delta)
	_update_charge_body()
	_update_hands(delta)


# ---------------------------------------------------------------- MAGNÉTISME

func get_magnet_target():
	if _magnet_target != null and not is_instance_valid(_magnet_target):
		_magnet_target = null
	return _magnet_target


## L'intention du joueur : sa direction d'entrée s'il pousse le stick,
## son orientation actuelle sinon.
func _player_intent() -> Vector3:
	var v := Vector3(
		Input.get_axis("move_left", "move_right"),
		0.0,
		Input.get_axis("move_forward", "move_back")
	).rotated(Vector3.UP, deg_to_rad(45.0))

	if v.length() > 0.15:
		return v.normalized()
	return -player.global_transform.basis.z


## La cible visée. Le critère n'est PAS la proximité seule : c'est le meilleur
## compromis entre proximité et alignement avec l'intention du joueur. Un ennemi
## un peu plus loin mais pile dans l'axe du stick gagne contre un ennemi collé
## sur le côté — sans ça le joueur ne peut pas choisir sa cible, ce qui est
## indispensable quand il n'y a pas de verrouillage.
func _acquire_magnet() -> void:
	_magnet_target = null

	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	# Portée élargie pendant la charge : le poing vole beaucoup plus loin
	# qu'un coup au contact, la recherche doit suivre.
	var reach: float = magnet_range_charged if _charging else magnet_range
	shape.radius = reach

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), _body_pos)
	params.collision_mask = magnet_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false

	var intent: Vector3 = _player_intent()
	var half: float = cos(deg_to_rad(magnet_angle) * 0.5)
	var best_score: float = -INF

	for hit in space.intersect_shape(params, 8):
		var e = hit.collider.get_parent()
		if e == null or not is_instance_valid(e):
			continue
		if not e.has_method("take_hit"):
			continue

		var to_e: Vector3 = e.global_position - _body_pos
		to_e.y = 0.0
		var d: float = to_e.length()
		if d < 0.01:
			continue

		var dir: Vector3 = to_e / d
		var align: float = intent.dot(dir)
		if align < half:
			continue   # hors du cône : on ne frappe jamais dans le dos

		var near: float = 1.0 - clampf(d / reach, 0.0, 1.0)
		var score: float = near + align * magnet_align_weight

		if score > best_score:
			best_score = score
			_magnet_target = e

## Dévie une position de main vers la cible. Comme le corps est attiré par la
## main, tout le personnage suit — le magnétisme oriente donc la frappe entière.
##
## La correction est nulle en début de coup et monte progressivement : sans
## cette rampe, la main est tirée vers la cible dès la première frame et
## l'arc de l'animation ne se voit plus, ça a l'air d'un téléport.
func _magnetize(pos: Vector3, t: float) -> Vector3:
	var target = get_magnet_target()
	if target == null:
		return pos

	var aim: Vector3 = target.global_position
	aim.y = pos.y   # on ne corrige que l'horizontale

	# Le poing s'arrête devant l'ennemi, pas dedans
	var to_aim: Vector3 = aim - _body_pos
	var d: float = to_aim.length()
	if d > 0.01:
		aim = _body_pos + to_aim / d * maxf(d - magnet_standoff, 0.3)

	var ramp: float = clampf(
		inverse_lerp(magnet_ramp_start, magnet_ramp_end, t), 0.0, 1.0
	)
	return pos.lerp(aim, magnet_strength * ramp)


# ------------------------------------------------------- ATTRACTION UNIFIÉE

## Poids visé de l'attraction par la main, selon ce qui se passe.
func _target_lead_weight() -> float:
	if _punching:
		return charged_attract
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
	if _punching:
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
	_acquire_magnet()   # verrouille la cible pour toute la durée du coup


## Combat.gd fait avancer le temps, pour que visuel et hitbox restent synchrones
func set_attack_progress(t: float) -> void:
	_atk_t = t


func end_attack() -> void:
	_recover_side = 0.0 if _atk_kind == 3 else (1.0 if _atk_kind == 1 else -1.0)
	_atk_kind = 0
	_recover_t = attack_recover

func get_attack_position(t: float, side: float) -> Vector3:
	var p: Vector3 = _slam_position(t, side) if _atk_kind == 3 \
		else _sweep_position(t, side)
	return _magnetize(p, t)


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


## dest : le point du monde que le poing doit atteindre (fourni par Combat.gd,
## qui a déjà résolu la cible et orienté le joueur).
func play_punch(power: float, dest: Vector3) -> void:
	_charging = false
	_punching = true
	_punch_k = 0.0
	_punch_hit = false
	_punch_from = hand_r.global_position
	_punch_target = dest
	_punch_target.y = _body_pos.y + punch_height


func set_punch_progress(k: float) -> void:
	_punch_k = clampf(k, 0.0, 1.0)


func end_punch() -> void:
	_punching = false


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
		_windup_t = minf(_windup_t + delta / maxf(charge_windup, 0.01), 1.0)
		var e: float = _windup_t * _windup_t * (3.0 - 2.0 * _windup_t)
		return _charge_from.lerp(center + Vector3.UP * radius, e)

	# --- Phase 2 : rotation. cos(0) = 1, donc on repart pile du sommet ---
	_spin_angle += lerpf(charge_spin_min, charge_spin_max, _charge_k) * delta

	return center \
		+ Vector3.UP * cos(_spin_angle) * radius \
		+ fwd * sin(_spin_angle) * radius


## Position de repos de la main droite, dans le repère du corps incliné.
func _hand_home() -> Vector3:
	return body.global_position + body.global_transform.basis \
		* Vector3(hand_offset.x, hand_offset.y, hand_offset.z)


## Aller vif, arrêt net, retour élastique. Le poing quitte vraiment le corps :
## c'est ce détachement qui rend l'attaque lisible à distance.
## Il réévalue sa cible à chaque frame : sans ça, un ennemi qui se décale
## pendant le vol est raté alors que le joueur avait bien visé.
func _punch_hand_position() -> Vector3:
	var total: float = punch_out_time + punch_hold_time + punch_back_time
	var t: float = _punch_k * total
	var out_end: float = punch_out_time
	var hold_end: float = punch_out_time + punch_hold_time

	if _punch_hit:
		if t < hold_end:
			return _impact_pos
		var kb: float = clampf((t - hold_end) / punch_back_time, 0.0, 1.0)
		return _impact_pos.lerp(_hand_home(), kb * kb)

	# Destination réévaluée : le poing suit sa cible si elle bouge
	var dest: Vector3 = _punch_target
	var tgt = get_magnet_target()
	if tgt != null:
		dest = tgt.global_position
		dest.y = _body_pos.y + punch_height

	if t < out_end:
		var k: float = t / out_end
		return _punch_from.lerp(dest, 1.0 - pow(1.0 - k, 3.0))

	if t < hold_end:
		return dest

	var kb: float = clampf((t - hold_end) / punch_back_time, 0.0, 1.0)
	return dest.lerp(_hand_home(), kb * kb)


## Effets propres à la charge : tassement et recul.
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


## Les pieds marchent normalement même pendant le poing chargé : le joueur
## reste au sol, seul son bras part. C'est la différence avec l'ancien dash.
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

	if clip_enabled:
		var anchor: Vector3 = player.global_position + Vector3.UP * body_height
		var clipped: Vector3 = _clip(anchor, _body_pos, body_clip_radius)
		if clipped != _body_pos:
			# On tue la vitesse qui pousse dans le mur, sinon le corps vibre
			var into: Vector3 = _body_pos - clipped
			into.y = 0.0
			if into.length() > 0.01:
				var n: Vector3 = -into.normalized()
				var v: float = _body_vel.dot(n)
				if v < 0.0:
					_body_vel -= n * v
			_body_pos = clipped

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

	if _spinning:
		body.rotation.y = _spin_angle_t
		body.rotation.x = deg_to_rad(spin_body_tilt) * _spin_k


# ---------------------------------------------------------------- MAINS

func _update_hands(delta: float) -> void:
	if _impact_t > 0.0:
		_impact_t = maxf(_impact_t - delta, 0.0)

	# Le temps de l'attaque est piloté par Combat.gd ; ici, juste la récupération
	if _atk_kind == 0 and _recover_t > 0.0:
		_recover_t = maxf(_recover_t - delta, 0.0)

	# Ces positions sont calculées une seule fois par frame : l'angle de rotation
	# de la charge s'incrémente dedans, l'appeler par main le ferait tourner double.
	var driven_pos := Vector3.ZERO
	if _charging:
		driven_pos = _charge_hand_position(delta)
	elif _punching:
		driven_pos = _punch_hand_position()

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
		if _spinning:
			h.pos = _spin_hand_position(h.side, delta)
			h.vel = Vector3.ZERO
			h.node.global_position = h.pos
			h.node.rotation = body.rotation
			continue
		if h.side == swing_side:
			local.z -= swing   # -Z = avant en Godot
		else:
			local.z += swing * 0.6

		# --- Charge et poing chargé : seule la main droite est pilotée ---
		# Testé AVANT l'impact : pendant le poing chargé, c'est
		# _punch_hand_position qui gère le blocage sur la cible.
		if h.side > 0.0 and (_charging or _punching):
			h.pos = driven_pos
			h.vel = Vector3.ZERO
			h.node.global_position = h.pos
			h.node.rotation = body.rotation
			continue

		# --- Impact : le poing est bloqué là où il a touché ---
		if _impact_t > 0.0 and (_impact_side == 0.0 or h.side == _impact_side):
			h.pos = _impact_pos
			h.vel = Vector3.ZERO
			h.node.global_position = h.pos
			h.node.rotation = body.rotation
			continue

		var target: Vector3 = body.global_position + b * local

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

		var idx: int = 1 if h.side > 0.0 else 0
		var clipped: Vector3 = _clip(body.global_position, h.pos, hand_clip_radius)

		if clipped.distance_to(h.pos) > 0.02:
			_stuck_t[idx] += delta
			h.pos = clipped
			h.vel = Vector3.ZERO

			# Bloquée trop longtemps : elle rentre plutôt que de rester plaquée
			# contre le mur, ce qui se lit comme un bug.
			if _stuck_t[idx] >= hand_stuck_time:
				_stuck_t[idx] = 0.0
				h.pos = body.global_position + b * Vector3(
					hand_offset.x * h.side, hand_offset.y, hand_offset.z
				)
		else:
			_stuck_t[idx] = 0.0

		h.node.global_position = h.pos
		h.node.rotation = body.rotation

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

	_impact_pos = current

	if _punching:
		_punch_hit = true

func play_spin() -> void:
	_spinning = true
	_spin_k = 0.0
	_spin_angle_t = 0.0


func set_spin_progress(k: float) -> void:
	_spin_k = clampf(k, 0.0, 1.0)


func end_spin() -> void:
	_spinning = false


## Les deux poings tournent en opposition, à hauteur de torse. Le rayon
## s'ouvre au démarrage et se referme à la fin : sans ça, les bras
## apparaissent et disparaissent d'un coup.
func _spin_hand_position(side: float, delta: float) -> Vector3:
	if side > 0.0:
		_spin_angle_t += spin_rate * delta   # incrémenté une seule fois

	# Ouverture/fermeture sur les 15 premiers et derniers pourcents
	var open: float = clampf(_spin_k / 0.15, 0.0, 1.0)
	var close: float = clampf((1.0 - _spin_k) / 0.15, 0.0, 1.0)
	var r: float = spin_radius * minf(open, close)

	var a: float = _spin_angle_t + (0.0 if side > 0.0 else PI)
	var center: Vector3 = _body_pos + Vector3.UP * (spin_height - body_height)

	return center + Vector3(cos(a), 0.0, sin(a)) * r


## Empêche une partie du rig de traverser le décor. Le rayon part de l'ancre
## (toujours dans un espace libre) et va vers la partie ; le premier mur
## rencontré devient la limite, décalée de la marge.
##
## Le rayon est forcé à l'horizontale : sinon il touche le sol dès que la
## partie descend, et la plaque n'importe où.
func _clip(from: Vector3, to: Vector3, radius: float) -> Vector3:
	if not clip_enabled:
		return to

	var a := from
	var b := to
	b.y = a.y   # test horizontal uniquement

	if a.distance_to(b) < 0.05:
		return to

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [player.get_rid()]
	q.collision_mask = clip_mask

	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return to

	var n: Vector3 = hit.normal
	n.y = 0.0
	if n.length() < 0.01:
		return to

	var clipped: Vector3 = hit.position + n.normalized() * radius
	clipped.y = to.y   # on garde la hauteur d'origine
	return clipped