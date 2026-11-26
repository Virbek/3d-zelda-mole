extends Node

## Logique de combat du joueur.
##
## Trois outils qui ne se recouvrent pas :
##   - le combo, en boucle 1→2→1→2..., au contact
##   - le poing chargé, à distance : le bras part seul ; s'il accroche un
##     ennemi, le joueur est propulsé jusqu'à lui pour enchaîner le combo
##   - la commande réaction, débloquée près d'un ennemi étourdi : toupie,
##     coup lourd ciblé (finisher) ou slam (attraper l'abeille, la fracasser
##     au sol, dards en étoile) selon ce que l'ennemi étourdi préfère
##
## L'étourdissement n'est plus une chance sur un coup : chaque ennemi a sa
## propre jauge, remplie par les coups reçus (voir add_stun sur l'ennemi),
## qui se vide de lui-même si on arrête de le frapper.
##
## RÉPARTITION DES RÔLES :
##   - les pieds portent le déplacement (capsule du Player, au sol)
##   - le torse porte les dégâts subis   (HurtBox enfant de Body)
##   - les poings portent les dégâts infligés (FistBox enfant de HandL/HandR)
##
## Les hitbox ne sont donc pas calculées : ce sont de vraies Area3D attachées
## aux mains. Là où le poing se dessine, il frappe.
##
## Le clic gauche est ambigu par nature : appui court = coup normal,
## appui maintenu = charge. On ne peut pas déclencher l'attaque au moment
## de l'appui — il faut attendre charge_delay pour trancher.

@export var rig_path: NodePath
@export var fist_box_l_path: NodePath
@export var fist_box_r_path: NodePath

@export_group("Combo")
## Index 0 et 1 : les deux coups de la boucle. Index 2 : réservé au finisher,
## déclenché uniquement par la commande réaction sur un ennemi étourdi.
@export var durations: Array[float] = [0.18, 0.16, 0.42]
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
@export var finisher_damage_multiplier: float = 2.5
## Durée du coup lourd déclenché par la commande réaction. Remplace
## durations[2] : un finisher trop long casse le rythme du combat.
@export var finisher_duration: float = 0.45
## Distance à laquelle le joueur s'arrête devant l'ennemi étourdi.
@export var finisher_standoff: float = 1.2
## Vitesse max du bond vers l'ennemi étourdi (évite de traverser la salle).
@export var finisher_max_speed: float = 12.0

@export_group("Rapprochement")
@export var lunge_range: float = 3.5
## Poussée de départ (m/s) : freinée ensuite par l'accélération du joueur,
## 5 m/s donne un glissé d'environ un demi-mètre.
@export var lunge_speed: Array[float] = [5.0, 5.0, 4.0]
@export var lunge_standoff: float = 1.6  ## en dessous, pas de rapprochement

@export_group("Attaque chargée")
@export var charge_delay: float = 0.15       ## maintien avant d'entrer en charge
@export var charge_ramp_time: float = 0.18   ## doit valoir le charge_windup du rig
@export var charge_min_time: float = 0.30    ## en dessous : simple coup normal
@export var charge_max_time: float = 1.10    ## charge pleine

@export_group("Poing chargé")
## Ces trois durées doivent correspondre à celles du rig, qui dessine le vol.
@export var punch_out_time: float = 0.14
@export var punch_hold_time: float = 0.08
@export var punch_back_time: float = 0.22
@export var punch_range_min: float = 3.0
@export var punch_range_max: float = 7.0
@export var punch_damage: int = 3
@export var punch_shake: float = 0.5
## Quand le poing chargé touche, le joueur est propulsé jusqu'à l'ennemi
## (le poing reste accroché, le corps est tiré vers lui), prêt à enchaîner.
@export var zip_speed: float = 24.0
@export var zip_standoff: float = 1.3      ## distance d'arrivée devant l'ennemi
@export var zip_max_time: float = 0.4      ## sécurité : abandon si l'ennemi est inatteignable
@export var zip_arrive_shake: float = 0.25

@export_group("Toupie")
@export var spin_trigger_range: float = 3.0  ## distance à l'ennemi étourdi
@export var spin_duration: float = 0.9
@export var spin_damage: int = 1
@export var spin_tick: float = 0.25          ## délai entre deux dégâts sur le même ennemi
@export var spin_shake: float = 0.2

@export_group("Slam (abeille)")
## Attraper l'abeille étourdie, la lever au-dessus de la tête, la fracasser
## au sol : elle éclate en dards qui partent en étoile autour du joueur.
@export var slam_grab_time: float = 0.14     ## l'abeille rejoint les mains
@export var slam_duration: float = 0.62      ## armé + abattement + retour (anim coup 3 du rig)
@export var slam_damage: int = 4             ## sur l'abeille fracassée
@export var slam_needle_count: int = 5
@export var slam_needle_damage: int = 2
@export var slam_needle_height: float = 0.6  ## hauteur de vol des dards
@export var slam_shake: float = 0.6

@export_group("Esquive")
## Un clic fait pendant l'esquive est gardé ce temps-là, puis rejoué à la sortie.
## Un peu moins que la durée de l'esquive : un clic du tout début est oublié.
@export var dodge_buffer_time: float = 0.2

@export_group("Indication de réaction")
@export var prompt_height: float = 2.2
@export var prompt_color := Color(1.0, 0.85, 0.2)

@export_group("Hit stop")
@export var hit_stop_time: float = 0.0            ## coup du combo (0 = pas de gel)
@export var finisher_hit_stop_time: float = 0.11  ## coup lourd
@export var hit_stop_scale: float = 0.0           ## 0 = arrêt net, plus sec qu'un ralenti

@export_group("Impact")
@export var hit_shake: float = 0.15        ## secousse caméra d'un coup du combo
@export var finisher_shake: float = 0.45   ## secousse caméra du coup lourd

@onready var player: CharacterBody3D = get_parent()
@onready var rig: Node3D = get_node(rig_path)
@onready var fist_l: Area3D = get_node_or_null(fist_box_l_path)
@onready var fist_r: Area3D = get_node_or_null(fist_box_r_path)

var is_charging: bool = false
var is_punching: bool = false
var is_spinning: bool = false
var is_slamming: bool = false

var _slam_target: Node3D = null
var _slam_t: float = 0.0          ## temps écoulé depuis le début du slam
var _slam_grab_from := Vector3.ZERO
var _slam_impacted: bool = false

## Progression de la mise en charge, 0 → 1. Lue par Player.gd pour ralentir
## le déplacement en même temps que le poing se met en place.
var charge_ramp: float = 0.0
var _charge_sound: Node = null    ## boucle de charge du gantelet, null hors charge

var _step: int = 0                ## 0 = inactif, 1/2 = boucle, 3 = finisher
var _t: float = 0.0               ## progression normalisée du coup courant
var _last_step: int = 0
var _grace: float = 0.0
var _buffered: bool = false
var _hit_list: Array = []

var _press_t: float = -1.0        ## -1 = aucun appui en attente
var _press_step: int = 1          ## coup que l'appui déclenchera s'il est relâché
var _charge_t: float = 0.0

var _punch_t: float = 0.0
var _punch_power: float = 0.0

## Ennemi accroché par le poing chargé, vers lequel le joueur est tiré.
var _zip_target: Node3D = null
var _zip_t: float = 0.0

var _spin_t: float = 0.0
var _spin_hits: Dictionary = {}   ## ennemi → temps du dernier dégât

var _dodge_buffer_t: float = 0.0

## Ennemi étourdi visé par le coup lourd en cours. Tant qu'il est défini,
## le joueur ne contrôle plus ni sa direction ni son déplacement.
var _finisher_target: Node3D = null

var _sparks: HitSparks = null

var _prompt: Label3D = null
var _using_pad: bool = false      ## dernier périphérique utilisé, pour le texte de la touche
var _prompt_t: float = 0.0


var is_attacking: bool:
	get:
		return _step != 0

## Vrai pendant le coup lourd verrouillé sur un ennemi étourdi.
var is_finishing: bool:
	get:
		return _step == 3 and _finisher_target != null

## Vrai pendant que le joueur est tiré vers l'ennemi accroché.
var is_zipping: bool:
	get:
		return _zip_target != null

## Le joueur ne contrôle plus son déplacement et est invincible : Combat
## pilote le corps (coup lourd ou propulsion du poing chargé).
var is_movement_locked: bool:
	get:
		return is_finishing or is_zipping or is_slamming


func _ready() -> void:
	_build_prompt()
	_sparks = HitSparks.new()
	_sparks.name = "HitSparks"
	add_child(_sparks)
	if fist_l == null or fist_r == null:
		push_warning("Combat : FistBox manquantes, les coups ne toucheront rien")
		return
	_set_fists(false, false)


## Le coup 1 mène au coup 2, le coup 2 reboucle sur le coup 1. Le coup 3
## (finisher) n'est jamais atteint par cette boucle — il ne se déclenche que
## via la commande réaction, voir _start_finisher.
func _next_combo_step(current: int) -> int:
	return 1 if current >= 2 else current + 1


# ---------------------------------------------------------------- ENTRÉES

func _unhandled_input(event: InputEvent) -> void:
	# Passage de porte en cours : pas d'attaque
	if not player.controls_enabled:
		return

	# --- Commande réaction : uniquement près d'un ennemi étourdi ---
	if event.is_action_pressed("actionEvenement"):
		if is_spinning or is_slamming or is_charging or is_punching or player.is_dodging or _step != 0:
			return
		var target = _find_stunned_nearby()
		if target == null:
			return
		var reaction: String = target.get_reaction() if target.has_method("get_reaction") else "spin"
		if reaction == "finisher":
			_start_finisher(target)
		elif reaction == "slam" and target.has_method("begin_grab"):
			_start_slam(target)
		else:
			_start_spin()
		return

	if not event.is_action_pressed("attack"):
		return
	if player.is_dodging:
		# Mémorisé : rejoué à la sortie de l'esquive (voir _consume_dodge_buffer)
		_dodge_buffer_t = dodge_buffer_time
		return
	if is_charging or is_punching or is_spinning or is_slamming:
		return

	if _step == 0:
		# On ne lance rien tout de suite : il faut voir si le joueur maintient
		if _grace > 0.0:
			_press_step = _next_combo_step(_last_step)
		else:
			_press_step = 1
		_press_t = 0.0
	elif _t >= chain_open and _step != 3:
		_buffered = true   # mémorisé, joué à la fin du coup courant


# ---------------------------------------------------------------- BOUCLE

func _physics_process(delta: float) -> void:
	if is_slamming:
		_process_slam(delta)
		return
	if is_spinning:
		_process_spin(delta)
		return

	_consume_dodge_buffer(delta)
	_handle_charge(delta)

	if is_punching:
		return

	if _grace > 0.0:
		_grace = maxf(_grace - delta, 0.0)
		if _grace == 0.0:
			_last_step = 0

	if _step == 0:
		return

	var dur: float = finisher_duration if _step == 3 else durations[_step - 1]
	_t += delta / maxf(dur, 0.01)
	if _step == 3:
		_steer_finisher(dur)
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
		if _finisher_target != null:
			_finisher_target = null
			rig.set_forced_magnet(null)
		_step = 0
		_t = 0.0
		_grace = chain_grace
		if _buffered:
			_start(_next_combo_step(_last_step))


## Un clic pendant l'esquive est rejoué dès qu'elle se termine, comme un
## appui frais : relâché → coup normal, maintenu → charge.
func _consume_dodge_buffer(delta: float) -> void:
	if _dodge_buffer_t <= 0.0:
		return
	_dodge_buffer_t = maxf(_dodge_buffer_t - delta, 0.0)
	if player.is_dodging or not player.controls_enabled:
		return
	if _step != 0 or _press_t >= 0.0 or is_charging or is_punching:
		return
	_dodge_buffer_t = 0.0
	_press_step = _next_combo_step(_last_step) if _grace > 0.0 else 1
	_press_t = 0.0


func _start(step: int) -> void:
	_step = step
	_last_step = step
	_t = 0.0
	_grace = 0.0
	_buffered = false
	_hit_list.clear()
	rig.play_attack(step)
	# Le whoosh part même dans le vide : c'est lui qui dit « le coup est parti »
	Sfx.play_ui("swing", -8.0 if step != 3 else -4.0)

	_lunge(step)

	if step == 3:
		_hop()


func _hop() -> void:
	player.velocity.y = hop_force
	# Verrouillé sur une cible : c'est _steer_finisher qui gère l'horizontale
	if _finisher_target != null:
		return
	var fwd: Vector3 = -player.global_transform.basis.z
	player.velocity.x += fwd.x * hop_forward
	player.velocity.z += fwd.z * hop_forward


## Pendant le coup lourd : le joueur reste tourné vers l'ennemi étourdi et
## bondit pour arriver pile devant lui au moment où la fenêtre de coup s'ouvre.
func _steer_finisher(dur: float) -> void:
	if _finisher_target == null:
		return
	if not is_instance_valid(_finisher_target):
		_finisher_target = null
		rig.set_forced_magnet(null)
		return

	var to_t: Vector3 = _finisher_target.global_position - player.global_position
	to_t.y = 0.0
	var d: float = to_t.length()
	if d > 0.01:
		player.rotation.y = atan2(-to_t.x, -to_t.z)

	# Temps restant avant l'impact ; une fois l'impact atteint, on se pose
	var hit_at: float = hit_windows[2].x
	var remaining: float = (hit_at - _t) * dur
	if remaining <= 0.0 or d <= finisher_standoff:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		return
	var spd: float = minf((d - finisher_standoff) / maxf(remaining, 0.05), finisher_max_speed)
	var dir: Vector3 = to_t / d
	player.velocity.x = dir.x * spd
	player.velocity.z = dir.z * spd


## Le finisher n'est plus une suite du combo : c'est ce que déclenche la
## commande réaction sur un ennemi dont c'est la réaction préférée. On
## réutilise telle quelle la mécanique du coup 3 (animation, bond, fenêtre
## de coup à l'index 2), juste sur demande plutôt qu'en enchaînement.
func _start_finisher(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return

	var to_t: Vector3 = target.global_position - player.global_position
	to_t.y = 0.0
	if to_t.length() > 0.01:
		player.rotation.y = atan2(-to_t.x, -to_t.z)

	_finisher_target = target as Node3D
	# Le poing vise l'ennemi étourdi, pas celui vers lequel pousse le stick
	rig.set_forced_magnet(target)
	_start(3)


## Rapproche doucement le joueur de sa cible au démarrage d'un coup, et
## l'oriente vers elle. Seulement entre lunge_standoff et lunge_range : au
## contact on ne bouge pas, trop loin on ne « téléporte » pas.
func _lunge(step: int) -> void:
	var target = rig.get_magnet_target()
	if target == null:
		return

	var to_e: Vector3 = target.global_position - player.global_position
	to_e.y = 0.0
	var d: float = to_e.length()
	if d < lunge_standoff or d > lunge_range:
		return

	player.rotation.y = atan2(-to_e.x, -to_e.z)

	var push: Vector3 = to_e.normalized() * lunge_speed[step - 1]
	player.velocity.x = push.x
	player.velocity.z = push.z


# ---------------------------------------------------------------- POINGS

func _set_fists(left: bool, right: bool) -> void:
	if fist_l == null or fist_r == null:
		return
	fist_l.monitoring = left
	fist_r.monitoring = right


## Lit ce que les poings touchent réellement. La liste évite qu'un même
## ennemi encaisse plusieurs fois le même coup, frame après frame.
func _collect_hits() -> void:
	for fist in [fist_l, fist_r]:
		if fist == null or not fist.monitoring:
			continue

		for area in fist.get_overlapping_areas():
			var e = area.get_parent()
			if e == null or not is_instance_valid(e) or e in _hit_list:
				continue
			if e.has_method("add_stun"):
				e.add_stun()
			if player.has_method("add_recover_hit"):
				player.add_recover_hit()

			_hit_list.append(e)

			var dir: Vector3 = e.global_position - player.global_position
			dir.y = 0.0
			if dir.length() > 0.01:
				if _step == 3 and "damage_per_hit" in e:
					var dmg: int = maxi(1, int(round(float(e.damage_per_hit) * finisher_damage_multiplier)))
					e.take_hit(dir.normalized(), dmg, true)   # attaque réaction : réveille l'étourdi
				else:
					e.take_hit(dir.normalized())

			if _step == 3:
				_play_hit_sound("hit_heavy", e.global_position, 3.0)
			else:
				_play_punch_sound(e.global_position)
			_sparks.burst(fist.global_position, dir, _step == 3)
			# Gel du temps réservé aux gros coups : le combo reste fluide
			if _step == 3:
				_hit_stop(true)
			_shake(finisher_shake if _step == 3 else hit_shake)

			var side: float = 1.0 if fist == fist_r else -1.0
			rig.hit_impact(0.0 if _step == 3 else side)


# ---------------------------------------------------------------- CHARGE

func _handle_charge(delta: float) -> void:
	if is_punching:
		_process_punch(delta)
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
			_charge_sound = Sfx.attach_loop("charge_loop", player, -6.0, false)
		return

	if is_charging:
		if player.is_dodging:
			is_charging = false
			charge_ramp = 0.0
			rig.end_charge()
			Sfx.stop_loop(_charge_sound)
			_charge_sound = null
			return

		# Le ralentissement suit la mise en place du poing
		charge_ramp = minf(charge_ramp + delta / maxf(charge_ramp_time, 0.01), 1.0)

		var was_full: bool = _charge_t >= charge_max_time
		_charge_t = minf(_charge_t + delta, charge_max_time)
		rig.set_charge_progress(_charge_t / charge_max_time)
		if not was_full and _charge_t >= charge_max_time:
			rig.charge_full_flash()
			_shake(0.12)

		if not Input.is_action_pressed("attack"):
			_release_charge()


func _release_charge() -> void:
	is_charging = false
	charge_ramp = 0.0
	rig.end_charge()
	Sfx.stop_loop(_charge_sound)
	_charge_sound = null

	# Charge avortée : on rend un coup normal plutôt que rien
	if _charge_t < charge_min_time:
		_start(_press_step)
		return

	var span: float = maxf(charge_max_time - charge_min_time, 0.01)
	_punch_power = clampf((_charge_t - charge_min_time) / span, 0.0, 1.0)

	# La cible du magnétisme sert de destination ; à défaut, droit devant.
	var dist: float = lerpf(punch_range_min, punch_range_max, _punch_power)
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	var dest: Vector3 = player.global_position + fwd.normalized() * dist

	var t = rig.get_magnet_target()
	if t != null:
		var to_t: Vector3 = t.global_position - player.global_position
		to_t.y = 0.0
		# Plus de test de distance : si le magnétisme l'a accroché, c'est
		# qu'il est dans sa portée élargie — le poing peut l'atteindre.
		dest = t.global_position
		player.rotation.y = atan2(-to_t.x, -to_t.z)

	_punch_t = 0.0
	is_punching = true
	_hit_list.clear()
	_set_fists(false, true)
	rig.play_punch(_punch_power, dest)
	Sfx.play_ui("swing", -3.0)
	Sfx.play_ui("charge_release", lerpf(-6.0, 0.0, _punch_power))


func _process_punch(delta: float) -> void:
	var total: float = punch_out_time + punch_hold_time + punch_back_time

	# Propulsion : le poing reste figé à l'impact pendant que le corps le rejoint
	if _zip_target != null:
		_punch_hits()
		_process_zip(delta, total)
		return

	_punch_t += delta
	rig.set_punch_progress(_punch_t / total)

	# Le poing ne frappe qu'à l'aller et pendant l'arrêt : au retour il rentre
	if _punch_t <= punch_out_time + punch_hold_time:
		_punch_hits()
	else:
		_set_fists(false, false)

	if _punch_t >= total:
		is_punching = false
		_set_fists(false, false)
		rig.end_punch()
		_grace = chain_grace


func _punch_hits() -> void:
	if fist_r == null:
		return
	for area in fist_r.get_overlapping_areas():
		var e = area.get_parent()
		if e == null or not is_instance_valid(e) or e in _hit_list:
			continue
		if e.has_method("add_stun"):
			e.add_stun()
		if player.has_method("add_recover_hit"):
			player.add_recover_hit()

		_hit_list.append(e)

		var dir: Vector3 = e.global_position - player.global_position
		dir.y = 0.0
		if dir.length() > 0.01:
			var dmg: int = maxi(1, int(round(lerpf(1.0, float(punch_damage), _punch_power))))
			e.take_hit(dir.normalized(), dmg)

		rig.hit_impact(1.0)
		_play_hit_sound("hit_heavy", e.global_position, 3.0)
		_sparks.burst(fist_r.global_position, dir, true)
		_hit_stop(true)   # poing chargé : gros coup
		_shake(punch_shake * _punch_power)

		# Premier ennemi accroché : c'est vers lui que le joueur part
		if _zip_target == null and e is Node3D:
			_zip_target = e
			_zip_t = 0.0


## Tire le joueur vers l'ennemi accroché. À l'arrivée, le poing chargé se
## termine aussitôt et le combo est disponible (coup 1).
func _process_zip(delta: float, total: float) -> void:
	_zip_t += delta
	# Le poing reste à l'arrêt sur l'impact tant que le corps n'est pas arrivé
	rig.set_punch_progress(minf(_punch_t, punch_out_time + punch_hold_time) / total)

	var arrived: bool = false
	if not is_instance_valid(_zip_target) or _zip_t >= zip_max_time:
		arrived = true
	else:
		var to_t: Vector3 = _zip_target.global_position - player.global_position
		to_t.y = 0.0
		var d: float = to_t.length()
		if d <= zip_standoff:
			arrived = true
		else:
			var dir: Vector3 = to_t / d
			player.rotation.y = atan2(-dir.x, -dir.z)
			# Ne dépasse pas le point d'arrivée en une frame
			var spd: float = minf(zip_speed, (d - zip_standoff) / maxf(delta, 0.001))
			player.velocity.x = dir.x * spd
			player.velocity.z = dir.z * spd

	if not arrived:
		return

	_zip_target = null
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	_shake(zip_arrive_shake)
	is_punching = false
	_set_fists(false, false)
	rig.end_punch()
	# Enchaînement direct : le prochain clic part en coup 1 du combo
	_last_step = 0
	_grace = chain_grace


# ---------------------------------------------------------------- TOUPIE

## La toupie ne se déclenche que près d'un ennemi étourdi : c'est ce qui en
## fait une récompense du combo, pas un outil disponible en permanence.
func _find_stunned_nearby():
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("is_stunned"):
			continue
		if not e.is_stunned():
			continue
		var v: Vector3 = e.global_position - player.global_position
		v.y = 0.0
		if v.length() <= spin_trigger_range:
			return e
	return null


func _start_spin() -> void:
	is_spinning = true
	_spin_t = 0.0
	_spin_hits.clear()
	_step = 0
	_t = 0.0
	_grace = 0.0
	_buffered = false
	_press_t = -1.0
	_set_fists(true, true)
	rig.play_spin()


func _process_spin(delta: float) -> void:
	_spin_t += delta
	rig.set_spin_progress(_spin_t / maxf(spin_duration, 0.01))

	_spin_hits_check()

	if _spin_t >= spin_duration:
		cancel_spin()


## Termine la toupie. Appelé à la fin normale, ou par le joueur quand il
## esquive : l'esquive doit toujours partir immédiatement.
func cancel_spin() -> void:
	if not is_spinning:
		return
	is_spinning = false
	_set_fists(false, false)
	rig.end_spin()
	_grace = chain_grace


## Contrairement au combo, un même ennemi peut être touché plusieurs fois :
## la toupie inflige des dégâts répétés tant qu'on reste dedans.
func _spin_hits_check() -> void:
	for fist in [fist_l, fist_r]:
		if fist == null:
			continue

		for area in fist.get_overlapping_areas():
			var e = area.get_parent()
			if e == null or not is_instance_valid(e):
				continue
			if not e.has_method("take_hit"):
				continue

			var last: float = _spin_hits.get(e, -999.0)
			if _spin_t - last < spin_tick:
				continue
			_spin_hits[e] = _spin_t

			var dir: Vector3 = e.global_position - player.global_position
			dir.y = 0.0
			if dir.length() > 0.01:
				e.take_hit(dir.normalized(), spin_damage, true)   # attaque réaction
			_play_punch_sound(e.global_position, -3.0)
			_sparks.burst(fist.global_position, dir)
			_shake(spin_shake)


# ---------------------------------------------------------------- SLAM

## Réaction de l'abeille : le joueur l'attrape à deux mains, la lève
## au-dessus de sa tête et la fracasse au sol. On réutilise l'animation du
## coup 3 du rig (armé haut, abattement), l'abeille suit simplement les mains.
func _start_slam(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.begin_grab():
		return

	is_slamming = true
	_slam_target = target as Node3D
	_slam_t = 0.0
	_slam_impacted = false
	_slam_grab_from = _slam_target.global_position
	_step = 0
	_t = 0.0
	_grace = 0.0
	_buffered = false
	_press_t = -1.0
	_set_fists(false, false)

	player.velocity.x = 0.0
	player.velocity.z = 0.0
	var to_t: Vector3 = _slam_target.global_position - player.global_position
	to_t.y = 0.0
	if to_t.length() > 0.01:
		player.rotation.y = atan2(-to_t.x, -to_t.z)

	# Pas de magnétisme : les mains tiennent l'abeille, elles ne visent rien
	rig.set_forced_magnet(null)
	rig.play_attack(3)
	rig.set_attack_progress(0.0)
	Sfx.play_ui("swing", -4.0)


func _process_slam(delta: float) -> void:
	_slam_t += delta
	player.velocity.x = 0.0
	player.velocity.z = 0.0

	var held: bool = _slam_target != null and is_instance_valid(_slam_target)
	var hands: Vector3 = (rig.hand_l.global_position + rig.hand_r.global_position) * 0.5

	# --- 1. Saisie : l'abeille est tirée jusqu'aux mains ---
	if _slam_t < slam_grab_time:
		if held:
			var k: float = _slam_t / maxf(slam_grab_time, 0.01)
			_slam_target.global_position = _slam_grab_from.lerp(hands, k * k * (3.0 - 2.0 * k))
		return

	# --- 2. Armé + abattement : l'abeille suit les mains ---
	var t: float = (_slam_t - slam_grab_time) / maxf(slam_duration, 0.01)
	rig.set_attack_progress(minf(t, 1.0))

	if not _slam_impacted:
		if held:
			_slam_target.global_position = hands
		if t >= rig.slam_strike_end:
			_slam_impact(hands)

	if t >= 1.0:
		_end_slam()


## L'impact : l'abeille est écrasée au sol et les dards partent en étoile.
func _slam_impact(hands: Vector3) -> void:
	_slam_impacted = true
	var ground: Vector3 = Vector3(hands.x, player.global_position.y, hands.z)
	var ignore: Array[Node] = []

	if _slam_target != null and is_instance_valid(_slam_target):
		ignore.append(_slam_target)
		_slam_target.global_position = ground
		var dir: Vector3 = ground - player.global_position
		dir.y = 0.0
		_slam_target.end_grab()
		_slam_target.take_hit(dir.normalized() if dir.length() > 0.01 else -player.global_transform.basis.z,
			slam_damage, true)   # attaque réaction
		_sparks.burst(ground, Vector3.UP, true)

	# Étoile régulière, la première pointe dans le regard du joueur
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var origin: Vector3 = player.global_position
	origin.y += slam_needle_height
	var count: int = maxi(slam_needle_count, 1)
	for i in count:
		var d: Vector3 = fwd.rotated(Vector3.UP, TAU * float(i) / float(count))
		SlamNeedle.spawn(get_tree().current_scene, origin + d * 0.5, d, slam_needle_damage, ignore)

	_play_hit_sound("hit_heavy", ground, 4.0)
	Sfx.play("slam", ground, 2.0)
	Sfx.play("hornet_shoot", ground)
	_hit_stop(true)
	_shake(slam_shake)


func _end_slam() -> void:
	# Sécurité : si l'impact n'a pas eu lieu, on relâche quand même l'abeille
	if not _slam_impacted and _slam_target != null and is_instance_valid(_slam_target):
		_slam_target.end_grab()
	is_slamming = false
	_slam_target = null
	rig.end_attack()
	_grace = chain_grace


# ---------------------------------------------------------------- RESSENTI

## Micro-gel du temps à l'impact. C'est ce qui donne le poids aux coups.
func _hit_stop(heavy: bool = false) -> void:
	var dur: float = finisher_hit_stop_time if heavy else hit_stop_time
	if dur <= 0.0:
		return
	# Passe par l'autoload : un seul propriétaire de Engine.time_scale, sinon
	# deux gels concurrents se remettent mutuellement à 1.0.
	HitStop.hit(dur, hit_stop_scale)


## Coup du combo : une des trois variantes punch_1..3, jamais la même deux
## fois de suite.
var _punch_variant: int = 0

func _play_punch_sound(pos: Vector3, volume_db: float = 0.0) -> void:
	_punch_variant = (_punch_variant + 1 + randi() % 2) % 3
	_play_hit_sound("punch_%d" % (_punch_variant + 1), pos, volume_db)


## Joue key s'il existe, sinon retombe sur hit_light : un son manquant
## ne doit pas rendre un coup muet.
func _play_hit_sound(key: String, pos: Vector3, volume_db: float = 0.0) -> void:
	Sfx.play(key if Sfx.sounds.has(key) else "hit_light", pos, volume_db)


func _shake(strength: float) -> void:
	if strength <= 0.0:
		return
	var cam := player.get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("shake"):
		cam.get_parent().shake(strength)


## Ce que le clic droit ferait maintenant. Vide = rien de disponible.
## Une seule touche pour plusieurs actions : c'est cette chaîne qui dit
## au joueur laquelle, plutôt que de le laisser deviner.
func get_available_action() -> String:
	var target = _reaction_target()
	if target == null:
		return ""
	return target.get_reaction() if target.has_method("get_reaction") else "spin"


## L'ennemi étourdi sur lequel la commande réaction partirait maintenant.
func _reaction_target():
	if is_spinning or is_slamming or is_charging or is_punching or player.is_dodging or _step != 0:
		return null
	if not player.controls_enabled:
		return null
	return _find_stunned_nearby()


# ---------------------------------------------------------------- INDICATION

## Étiquette flottante au-dessus de l'ennemi étourdi à portée : elle affiche
## la touche de la commande réaction. Créée par script, partagée par tous les
## ennemis — c'est la portée du joueur qu'elle signale, pas l'ennemi lui-même.
func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.top_level = true
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.render_priority = 10
	_prompt.font_size = 72
	_prompt.outline_size = 18
	_prompt.pixel_size = 0.006
	_prompt.modulate = prompt_color
	_prompt.outline_modulate = Color.BLACK
	_prompt.visible = false
	add_child(_prompt)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadMotion and absf(event.axis_value) < 0.3:
			return
		_using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_using_pad = false


func _process(delta: float) -> void:
	if _prompt == null:
		return
	var target = _reaction_target()
	if target == null or not is_instance_valid(target):
		_prompt.visible = false
		_prompt_t = 0.0
		return

	_prompt.text = _action_key_text("actionEvenement")
	_prompt.global_position = target.global_position + Vector3.UP * prompt_height
	# Apparition en pop puis légère pulsation, pour attirer l'œil sans clignoter
	_prompt_t += delta
	var pop: float = minf(_prompt_t / 0.12, 1.0)
	var pulse: float = 1.0 + 0.08 * sin(_prompt_t * 8.0)
	_prompt.scale = Vector3.ONE * lerpf(1.6, 1.0, pop) * pulse
	_prompt.visible = true


## Texte de la touche liée à action, pour le périphérique utilisé en dernier.
func _action_key_text(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if _using_pad and ev is InputEventJoypadButton:
			const PAD_NAMES := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 6: "Start", 9: "LB", 10: "RB"}
			return PAD_NAMES.get(ev.button_index, "Bouton %d" % ev.button_index)
		if not _using_pad and ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT:
					return "Clic gauche"
				MOUSE_BUTTON_RIGHT:
					return "Clic droit"
				MOUSE_BUTTON_MIDDLE:
					return "Clic molette"
		if not _using_pad and ev is InputEventKey:
			var code: Key = ev.keycode
			if code == KEY_NONE:
				code = DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode)
			return OS.get_keycode_string(code)
	return "?"