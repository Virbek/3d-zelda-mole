extends CharacterBody3D

## Ennemi chargeur : le BOUSIER DES DUNES. Repère le joueur, approche, marque
## un temps d'arrêt visible (télégraphe), fonce en ligne droite en poussant
## son boulet de sable, puis reste vulnérable un instant.
##
## Cycle du boulet : il charge tant que son boulet est entier. Le boulet se
## casse si le joueur le frappe ou s'il percute le joueur. Sans boulet, le
## bousier FUIT pour prendre de la distance, puis s'arrête et en FAÇONNE un
## nouveau (immobile, vulnérable : c'est la fenêtre pour le punir).
##
## Le télégraphe est le cœur du design : c'est lui qui rend la charge esquivable.
## Ne le raccourcis pas sous ~0.5s sans raison, le joueur n'aurait plus le temps
## de lire l'attaque.
##
## Il se déplace vers la capsule du joueur (stable) mais frappe sa HurtBox de
## torse (Area3D du groupe "player_hurt"). Viser le torse pour la navigation
## le ferait zigzaguer, puisque le buste oscille à chaque pas.

enum State { IDLE, CHASE, TELEGRAPH, CHARGE, RECOVER, HURT, STUNNED, DEAD, FLEE, BUILD, GRABBED }

signal died

@export var player_path: NodePath

@export_group("Vie")
@export var max_health: int = 5
@export var damage_per_hit: int = 1

@export_group("Détection")
## Vrai : attaque le joueur dès son apparition et ne lâche jamais (tous les
## ennemis d'une salle se battent). Faux : portées detect_range / lose_range.
@export var always_aggro: bool = true
@export var detect_range: float = 9.0      ## distance d'éveil
@export var lose_range: float = 13.0       ## distance d'abandon (plus grande : hystérésis)
@export var charge_range: float = 14.0     ## distance à laquelle il déclenche sa charge (de loin)
@export var lose_time: float = 4.0         ## délai avant abandon hors de portée

@export_group("Déplacement")
@export var chase_speed: float = 2.6
@export var turn_speed: float = 6.0
@export var gravity: float = 20.0

@export_group("Charge")
@export var telegraph_time: float = 0.6   ## temps d'arrêt avant de foncer
@export var charge_speed: float = 13.0
@export var charge_distance: float = 18.0   ## longueur max d'une charge
## La charge va jusqu'au joueur plus cette marge (le temps qu'il recule
## pendant l'annonce), sans dépasser charge_distance ni le premier mur.
@export var charge_overshoot: float = 4.0
@export var charge_max_time: float = 1.8   ## sécurité anti-blocage
@export var recover_time: float = 0.6      ## fenêtre de punition pour le joueur
@export var charge_damage: int = 1
@export var charge_cooldown: float = 0.7

@export_group("Couloir de charge")
@export var charge_zone_scene: PackedScene
@export var charge_width: float = 1.4      ## largeur du couloir affiché au sol
## Marge ajoutée à la demi-largeur du couloir pour juger qu'un autre ennemi
## le bloque (rayon approximatif de son corps).
@export var ally_clearance: float = 0.6

@export_group("Bousier et boulet")
## Apparence de bousier (sinon la capsule grise d'origine) et cycle du boulet.
@export var use_dung_beetle: bool = true
@export var start_with_ball: bool = true
@export var ball_bar_margin: float = 0.45   ## écart à l'écran entre le haut du boulet et la barre de vie
@export var beetle_scale: float = 0.7        ## taille du bousier (1 = modèle d'origine)
@export var ball_radius: float = 0.8
@export var ball_build_time: float = 2.2      ## temps pour façonner un boulet complet
@export var flee_speed: float = 6.5          ## sans boulet, il est plus rapide
@export var no_ball_speed_mult: float = 1.6   ## vitesse de poursuite sans boulet (× chase_speed)
## Boulet brisé par le joueur : part de la jauge d'étourdissement remplie
## d'un coup (0.5 = à moitié). Le bousier ne perd pas de vie.
@export var ball_break_stun_fill: float = 0.5
@export var flee_distance: float = 8.0        ## distance au joueur à atteindre avant de refaire un boulet
@export var flee_max_time: float = 2.5        ## au-delà (coincé contre un mur), il s'arrête quand même

@export_group("Encerclement")
@export var circle_distance: float = 8.0   ## il tourne à distance, en cherchant un angle de charge
@export var circle_speed: float = 2.2
@export var circle_dir: float = 1.0        ## 1 ou -1, tiré au sort au démarrage

@export_group("Recul")
@export var knockback_force: float = 3.5   ## recul d'un coup léger : faible, pour pouvoir enchaîner
## Multiplicateur max du recul pour un coup lourd (dégâts > damage_per_hit)
@export var heavy_knockback_mult: float = 2.5
@export var knockback_damping: float = 8.0
@export var hurt_time: float = 0.28

@export_group("Flash")
@export var flash_color := Color(1.0, 0.15, 0.15)
@export var telegraph_color := Color(1.0, 0.55, 0.1)
@export var flash_count: int = 3
@export var flash_duration: float = 0.4

@export_group("Mort")
@export var death_time: float = 0.45
@export var death_launch: float = 1.6

@export_group("Étourdissement")
@export var stun_duration: float = 1.0
@export var stun_color := Color(0.25, 1.0, 0.35)
@export var stun_wobble: float = 0.12   ## amplitude du vacillement
@export var stun_hits_required: int = 4     ## nombre de coups pour étourdir
@export var stun_drain_delay: float = 0.6   ## temps sans coup avant que la jauge commence à redescendre
@export var stun_drain_rate: float = 0.8    ## coups perdus par seconde, une fois la latence passée
## Ce que déclenche la commande réaction une fois étourdi. "whirl" : la taupe
## l'attrape et tourne sur elle-même en le tenant à bout de bras ; il frappe
## les ennemis autour et meurt à la fin.
@export var reaction: String = "whirl"

var player: CharacterBody3D = null
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var health_bar: Node3D = $HealthBar
@onready var stun_bar: Node3D = get_node_or_null("StunBar")
@onready var hurt_box: Area3D = $HurtBox
@onready var attack_box: Area3D = $AttackBox

var state: State = State.IDLE
var health: int

var _aggro: bool = false
var _lose_t: float = 0.0

var _t: float = 0.0                  ## temps passé dans l'état courant
var _cooldown: float = 0.0
var _charge_dir := Vector3.ZERO
var _charge_start := Vector3.ZERO
var _charge_reach: float = 0.0   ## charge_distance, éventuellement raccourcie par un mur détecté au télégraphe
var _knockback := Vector3.ZERO
var _hit_player := false             ## un seul dégât par charge
var _charge_zone: Node3D = null       ## un seul dégât par charge
var _stun_bar: float = 0.0
var _stun_idle_t: float = 0.0
var _stun_frame: int = -1             ## frame physique où l'étourdissement a commencé

var _stun_base_y: float = 0.0
var _saved_layers := Vector3i.ZERO    ## corps (calque, masque) et HurtBox (calque) pendant la saisie
var _ball_hit_player: bool = false    ## le boulet s'est cassé sur le joueur, pas sous ses coups

var _mat: StandardMaterial3D
var _base_color: Color
var _base_scale := Vector3.ONE
var _hit_react: HitReaction = null
var _flash_tween: Tween
var _tele_tween: Tween

var _model: DungBeetleModel = null
var _ball: SandBall = null
var _ball_shape: CollisionShape3D = null   ## le boulet bute contre les murs avec le bousier
var _has_ball: bool = false
var _build_progress: float = 0.0
var _last_pos := Vector3.ZERO
var _health_bar_home := Vector3.ZERO    ## position d'origine (scène) des barres
var _stun_bar_home := Vector3.ZERO


func _ready() -> void:
	player = get_node_or_null(player_path)
	if player == null:
		push_warning("%s : player introuvable" % name)
		set_physics_process(false)
		return
	add_to_group("enemy")
	health = max_health
	_base_scale = mesh.scale
	_hit_react = HitReaction.attach(mesh)
	_stun_base_y = mesh.position.y
	_mat = mesh.get_active_material(0).duplicate()
	mesh.material_override = _mat
	_base_color = _mat.albedo_color

	health_bar.set_ratio(1.0)
	attack_box.monitoring = false

	circle_dir = 1.0 if randf() > 0.5 else -1.0

	_health_bar_home = health_bar.position
	if stun_bar != null:
		_stun_bar_home = stun_bar.position
	if use_dung_beetle:
		_setup_dung_beetle()
	_last_pos = global_position


func _physics_process(delta: float) -> void:
	_t += delta
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)

	if state != State.STUNNED and state != State.DEAD and _stun_bar > 0.0:
		_stun_idle_t += delta
		if _stun_idle_t >= stun_drain_delay:
			_stun_bar = maxf(_stun_bar - stun_drain_rate * delta, 0.0)
			if stun_bar != null:
				stun_bar.set_ratio(_stun_bar / float(stun_hits_required))

	match state:
		State.IDLE:
			_idle(delta)
		State.CHASE:
			_chase(delta)
		State.TELEGRAPH:
			_telegraph(delta)
		State.CHARGE:
			_charge(delta)
		State.RECOVER:
			_recover(delta)
		State.HURT:
			_hurt(delta)
		State.STUNNED:
			_stunned(delta)
		State.FLEE:
			_flee(delta)
		State.BUILD:
			_build_ball(delta)
		State.DEAD, State.GRABBED:
			return

	_apply_gravity(delta)
	move_and_slide()


func _set_state(next: State) -> void:
	state = next
	_t = 0.0


# ---------------------------------------------------------------- ÉTATS

func _idle(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if always_aggro or _distance_to_player() < detect_range:
		_aggro = true
		_lose_t = 0.0
		_set_state(State.CHASE)


func _chase(delta: float) -> void:
	var d: float = _distance_to_player()

	# Il n'abandonne que si le joueur reste loin un certain temps
	if not always_aggro and d > lose_range:
		_lose_t += delta
		if _lose_t >= lose_time:
			_aggro = false
			_set_state(State.IDLE)
			return
	else:
		_lose_t = 0.0

	# Plus de boulet : il ne charge pas à mains nues, il part en refaire un
	if use_dung_beetle and not _has_ball:
		_set_state(State.FLEE)
		return

	# En recharge mais au contact : il tourne autour plutôt que de foncer
	# dans les jambes du joueur.
	if d < charge_range and _cooldown > 0.0:
		_circle(delta, d)
		return

	if d < charge_range and _cooldown <= 0.0:
		# Il garde sa place dans la file même quand le couloir est bouché
		AttackToken.enqueue(self)
		var dir_now: Vector3 = _dir_to_player()
		var blocker: Node3D = _ally_in_corridor(global_position, dir_now, _measure_charge_reach(global_position, dir_now))
		if blocker != null or not _has_clear_line_to_player():
			# Un pilier ou un autre ennemi coupe le couloir : charger
			# maintenant le percuterait. On se décale, du côté opposé à
			# l'ennemi gênant, jusqu'à trouver une ligne dégagée.
			if blocker != null:
				_step_away_from(blocker, dir_now)
			_circle(delta, d)
			return
		if AttackToken.request(self):
			_set_state(State.TELEGRAPH)
			_start_telegraph()
			return
		# Jeton pris : on tourne autour en attendant
		_circle(delta, d)
		return

	# Hors de portée de charge seulement : il se rapproche juste assez
	var dir: Vector3 = _dir_to_player()
	var spd: float = chase_speed * (no_ball_speed_mult if use_dung_beetle and not _has_ball else 1.0)
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	_face(dir, delta)


## Tourne autour du joueur en gardant ses distances, en attendant son tour.
func _circle(delta: float, d: float) -> void:
	var to_player: Vector3 = _dir_to_player()
	var tangent: Vector3 = to_player.cross(Vector3.UP) * circle_dir

	# Maintient la distance tout en tournant ; plus il est loin dans la file
	# d'attente, plus il tourne large, pour que les attendants s'étagent.
	var ring: float = circle_distance + 0.6 * float(clampi(AttackToken.queue_index(self), 0, 3))
	var radial: float = (d - ring) * 0.8
	var move: Vector3 = tangent + to_player * radial
	move = move.normalized()

	velocity.x = move.x * circle_speed
	velocity.z = move.z * circle_speed
	_face(to_player, delta)


func _telegraph(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	# La direction est déjà figée au tout début du télégraphe (voir
	# _start_telegraph) : on aligne le corps dessus plutôt que de continuer
	# à viser, pour que le couloir affiché au sol reste vrai jusqu'au bout.
	_face(_charge_dir, delta * 0.6)

	# Léger tassement puis détente, comme un ressort qu'on comprime
	var k: float = _t / telegraph_time
	mesh.scale = _base_scale * Vector3(
		1.0 + k * 0.25,
		1.0 - k * 0.2,
		1.0 + k * 0.25
	)

	if _t >= telegraph_time:
		# Un allié est entré dans le couloir pendant l'annonce : on annule
		# plutôt que de le percuter. Il retentera vite, d'un autre angle.
		if _ally_in_corridor(_charge_start, _charge_dir, _charge_reach) != null:
			_cancel_charge()
			return
		_hit_player = false
		attack_box.monitoring = true
		mesh.scale = _base_scale
		_set_state(State.CHARGE)


func _charge(_delta: float) -> void:
	velocity.x = _charge_dir.x * charge_speed
	velocity.z = _charge_dir.z * charge_speed

	if _check_charge_hit():
		return   # le recul vient d'être appliqué, ne pas l'écraser ci-dessous

	var travelled: float = Vector2(
		global_position.x - _charge_start.x,
		global_position.z - _charge_start.z
	).length()

	var blocked: bool = get_slide_collision_count() > 0 and _t > 0.05

	if travelled >= _charge_reach or blocked or _t >= charge_max_time:
		# Arrêt net dans tous les cas — sans ça, la vitesse de charge reste
		# active une frame de trop et le chargeur dépasse la zone affichée.
		velocity.x = 0.0
		velocity.z = 0.0
		attack_box.monitoring = false
		AttackToken.release(self)
		_cooldown = charge_cooldown
		_set_state(State.RECOVER)


func _recover(delta: float) -> void:
	# Décélération : il finit sa glissade, vulnérable
	velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)

	if _t >= recover_time:
		_set_state(State.CHASE)


func _hurt(delta: float) -> void:
	velocity.x = _knockback.x
	velocity.z = _knockback.z
	_knockback *= exp(-knockback_damping * delta)

	# Sans ça, un velocity.y accumulé pendant la charge pousse l'ennemi
	# dans le sol pendant que le recul l'envoie sur le côté.
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0

	if _t >= hurt_time:
		_set_state(State.CHASE)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta


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
	var target := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target, turn_speed * delta)


func _start_telegraph() -> void:
	if _tele_tween != null and _tele_tween.is_running():
		_tele_tween.kill()
	_tele_tween = create_tween()
	_tele_tween.tween_property(_mat, "albedo_color", telegraph_color, telegraph_time * 0.7)
	_tele_tween.tween_property(_mat, "albedo_color", _base_color, telegraph_time * 0.3)

	# La charge est décidée dès maintenant, pas à la fin du télégraphe : le
	# couloir affiché au sol doit être la vérité dès la première frame.
	_charge_dir = _dir_to_player()
	_charge_start = global_position
	_charge_reach = _measure_charge_reach(_charge_start, _charge_dir)
	_spawn_charge_zone()


## charge_distance est un maximum, pas une garantie : un mur plus proche doit
## couper la charge avant. On le mesure dès le télégraphe pour que la zone
## affichée au sol et l'arrêt réel de la charge pointent toujours au même
## endroit — jamais la zone n'annonce une portée que le chargeur n'atteindra
## pas.
func _measure_charge_reach(from: Vector3, dir: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var length: float = minf(_distance_to_player() + charge_overshoot, charge_distance)
	var to: Vector3 = from + dir * length
	var q := PhysicsRayQueryParameters3D.create(from, to)
	# Le joueur ne doit jamais agir comme un mur ici : la charge le traverse,
	# seul un vrai obstacle (mur, pilier) doit couper la mesure.
	q.exclude = [get_rid(), player.get_rid()]
	q.collision_mask = 1   # calque du décor

	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return length
	return from.distance_to(hit.position)


func _spawn_charge_zone() -> void:
	if charge_zone_scene == null:
		return
	_charge_zone = charge_zone_scene.instantiate()
	get_tree().current_scene.add_child(_charge_zone)
	_charge_zone.setup(_charge_start, _charge_dir, _charge_reach, charge_width, telegraph_time)


## Le joueur se prend la charge ? On cherche sa HurtBox de torse, pas sa
## capsule : c'est le buste visible qui encaisse.
## _hit_player garantit un seul dégât par charge, sans quoi un ennemi qui
## traverse le joueur lui inflige des dégâts à chaque frame de contact.
## Le joueur se prend la charge ? On cherche sa HurtBox de torse, pas sa
## capsule : c'est le buste visible qui encaisse.
## Renvoie true si le contact a eu lieu — la charge s'arrête alors net,
## avec un recul, plutôt que de continuer à pousser dans le joueur.
func _check_charge_hit() -> bool:
	if _hit_player:
		return false

	# Le boulet est devant : c'est lui qui percute, et il se casse sur le joueur
	if _ball != null:
		var touched: Area3D = _ball.player_contact()
		if touched != null and touched.has_method("take_damage"):
			var bd: Vector3 = touched.global_position - global_position
			bd.y = 0.0
			touched.take_damage(charge_damage, bd.normalized() if bd.length() > 0.01 else _charge_dir)
			_hit_player = true
			_ball_hit_player = true
			_ball.shatter()   # → _on_ball_broken
			_ball_hit_player = false
			_end_charge_with_recoil()
			return true

	for area in attack_box.get_overlapping_areas():
		if not area.is_in_group("player_hurt"):
			continue
		if not area.has_method("take_damage"):
			continue

		var dir: Vector3 = area.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.01:
			area.take_damage(charge_damage, dir.normalized())
		_hit_player = true
		_end_charge_with_recoil()
		return true

	return false


## Contact avec le joueur : arrêt net et recul, comme un choc contre un mur.
## Sans ça, le chargeur continue de pousser dans le joueur et peut rester
## plaqué contre lui plutôt que de repartir vulnérable en RECOVER.
func _end_charge_with_recoil() -> void:
	velocity.x = -_charge_dir.x * charge_speed * 0.5
	velocity.z = -_charge_dir.z * charge_speed * 0.5
	attack_box.monitoring = false
	AttackToken.release(self)
	_cooldown = charge_cooldown
	_set_state(State.RECOVER)


## Premier autre ennemi vivant dont le corps touche le couloir de charge
## [from, from + dir * length], ou null. Calcul géométrique et pas un rayon :
## les ennemis sont sur un autre calque que le décor, un rayon sur le
## calque 1 ne les voyait pas, et un rayon fin ratait ceux qui débordent
## à moitié dans le couloir.
func _ally_in_corridor(from: Vector3, dir: Vector3, length: float) -> Node3D:
	var half_w: float = charge_width * 0.5 + ally_clearance
	var best: Node3D = null
	var best_t: float = INF
	for n: Node in get_tree().get_nodes_in_group("enemy"):
		var e := n as Node3D
		if e == null or e == self or e.is_queued_for_deletion():
			continue
		var hb: Variant = e.get("hurt_box")
		if hb is Area3D and not (hb as Area3D).monitorable:
			continue   # en train de mourir
		var v: Vector3 = e.global_position - from
		if absf(v.y) > 1.6:
			continue   # volant bien au-dessus : la charge passe dessous
		v.y = 0.0
		var t: float = v.dot(dir)
		if t < 0.0 or t > length + ally_clearance:
			continue
		var lateral: float = (v - dir * t).length()
		if lateral < half_w and t < best_t:
			best = e
			best_t = t
	return best


## Choisit le sens de rotation qui éloigne du gêneur : s'il est à droite de
## la ligne de charge, on tourne vers la gauche, et inversement.
func _step_away_from(blocker: Node3D, dir: Vector3) -> void:
	var v: Vector3 = blocker.global_position - global_position
	v.y = 0.0
	var lateral: Vector3 = v - dir * v.dot(dir)
	var tangent: Vector3 = dir.cross(Vector3.UP) * circle_dir
	if tangent.dot(lateral) > 0.0:
		circle_dir = -circle_dir


## Annule une charge annoncée : zone retirée, jeton rendu, courte pause.
func _cancel_charge() -> void:
	if _tele_tween != null and _tele_tween.is_running():
		_tele_tween.kill()
	_mat.albedo_color = _base_color
	mesh.scale = _base_scale
	if _charge_zone != null and is_instance_valid(_charge_zone):
		_charge_zone.queue_free()
		_charge_zone = null
	AttackToken.release(self)
	_cooldown = charge_cooldown * 0.5
	_set_state(State.CHASE)


## Un couloir obstrué (pilier, autre ennemi) ferait rater le coup à coup
## sûr — mieux vaut se replacer que de charger dans le vide. Le joueur
## lui-même est exclu : il est la destination du rayon, pas un obstacle.
func _has_clear_line_to_player() -> bool:
	var from: Vector3 = global_position
	var to: Vector3 = player.global_position
	to.y = from.y

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid(), player.get_rid()]
	q.collision_mask = 1   # calque du décor (et des autres ennemis, tant que tu n'as pas séparé les calques)

	return space.intersect_ray(q).is_empty()


# ---------------------------------------------------------------- BOUSIER

func _setup_dung_beetle() -> void:
	# Le bousier est rangé sous le mesh : il hérite du tassement du
	# télégraphe, des secousses et du vacillement d'étourdissement.
	_model = DungBeetleModel.new()
	mesh.add_child(_model)
	_model.position.y = -_stun_base_y   # pattes au sol
	_model.scale = Vector3.ONE * beetle_scale
	mesh.mesh = null

	# Le boulet, lui, est posé devant, sur le corps (pas sous le mesh : il ne
	# doit pas s'écraser avec le télégraphe).
	_ball = SandBall.new()
	_ball.name = "SandBall"
	_ball.radius = ball_radius
	# Collé aux pattes avant (bout de la pelle ≈ 0,9 m devant, à l'échelle 1),
	# en mordant un peu dedans : il le tient, il ne le pousse pas à distance.
	_ball.position = Vector3(0.0, ball_radius, -(0.85 * beetle_scale + ball_radius * 0.85))
	add_child(_ball)
	_ball.broken.connect(_on_ball_broken)

	_ball_shape = CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = ball_radius * 0.95
	_ball_shape.shape = sh
	_ball_shape.position = _ball.position
	add_child(_ball_shape)

	_has_ball = start_with_ball
	_build_progress = 1.0 if start_with_ball else 0.0
	_ball.set_grow(_build_progress)
	_ball_shape.disabled = not _has_ball


func _on_ball_broken() -> void:
	_has_ball = false
	_build_progress = 0.0
	_ball_shape.set_deferred("disabled", true)
	if state == State.DEAD:
		return
	# Brisé par le joueur : la jauge d'étourdissement se remplit à moitié
	if not _ball_hit_player:
		add_stun(float(stun_hits_required) * ball_break_stun_fill)
		if state == State.STUNNED:
			_cancel_charge_state()
			return
	# Boulet cassé en plein façonnage : il repart fuir et recommencera de zéro
	if state == State.BUILD:
		_set_state(State.FLEE)
		return
	# Boulet cassé pendant l'annonce ou la charge : l'attaque s'arrête là
	if state == State.TELEGRAPH or state == State.CHARGE:
		if state == State.CHARGE and not _hit_player:
			velocity.x = 0.0
			velocity.z = 0.0
		_cancel_charge()
		attack_box.monitoring = false
		_set_state(State.RECOVER)


## Annule proprement annonce / charge en cours (zone au sol, boîte d'attaque).
func _cancel_charge_state() -> void:
	attack_box.monitoring = false
	AttackToken.release(self)
	if _charge_zone != null and is_instance_valid(_charge_zone):
		_charge_zone.queue_free()
		_charge_zone = null
	mesh.scale = _base_scale


## Sans boulet : il s'éloigne du joueur, puis s'arrête pour en refaire un.
func _flee(delta: float) -> void:
	var away: Vector3 = -_dir_to_player()
	# Contre un mur, il longe le mur plutôt que de pousser dedans
	if is_on_wall():
		var n: Vector3 = get_wall_normal()
		n.y = 0.0
		away = (away - n * away.dot(n)).normalized() + n * 0.3
		away = away.normalized()
	velocity.x = away.x * flee_speed
	velocity.z = away.z * flee_speed
	_face(away, delta)
	if _distance_to_player() >= flee_distance or _t >= flee_max_time:
		velocity.x = 0.0
		velocity.z = 0.0
		_ball.reset()
		_ball.set_grow(_build_progress)
		_set_state(State.BUILD)


## Immobile, tourné vers le joueur, il façonne le boulet devant lui.
## Interrompu par un coup, il lâche le boulet en cours, qui se casse : il
## devra fuir et tout recommencer.
func _build_ball(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_face(_dir_to_player(), delta * 0.5)
	_build_progress = minf(_build_progress + delta / ball_build_time, 1.0)
	_ball.set_grow(_build_progress)
	_ball.roll(delta * 1.2 * sin(_t * 5.0))   # il le tapote et le fait tourner
	if _build_progress >= 1.0:
		_has_ball = true
		_ball_shape.disabled = false
		_set_state(State.CHASE)


## Visuel du bousier : pattes, posture de poussée, yeux, boulet qui roule.
func _process(delta: float) -> void:
	if _model == null:
		return
	_model.set_tint(_mat.albedo_color, _base_color)

	var moved: Vector3 = global_position - _last_pos
	moved.y = 0.0
	_last_pos = global_position
	if _has_ball and _ball != null:
		# Avance dans la direction où il regarde : le boulet roule vers l'avant
		var fwd: Vector3 = -global_transform.basis.z
		_ball.roll(moved.dot(fwd))

	var push: float = 0.0
	var threat: float = 0.0
	match state:
		State.TELEGRAPH:
			push = clampf(_t / telegraph_time, 0.0, 1.0)
			threat = push
		State.CHARGE:
			push = 1.0
			threat = 1.0
		State.BUILD:
			push = 0.3 + 0.1 * sin(_t * 7.0)   # le corps suit le rythme des pattes
		_:
			push = 0.25 if _has_ball else 0.0
	_model.set_walk(Vector2(velocity.x, velocity.z).length(), delta)
	_model.set_push(push)
	_model.set_eyes_threat(threat)
	# Pattes avant au travail pendant le façonnage (après set_push, qui
	# les remet sinon en position de poussée)
	_model.set_shaping(_t if state == State.BUILD else -1.0)
	_place_bars_above_ball()


## En vue plongeante, le gros boulet cachait les barres posées au-dessus du
## corps. On les place au-dessus de ce qui est le plus haut À L'ÉCRAN : le
## corps ou le haut du boulet (dans le repère de la caméra, quel que soit le
## sens dans lequel le bousier regarde).
func _place_bars_above_ball() -> void:
	var home: Vector3 = to_global(_health_bar_home)
	var target: Vector3 = home
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and _ball != null and _ball.visible:
		var up: Vector3 = cam.global_basis.y
		var over_ball: Vector3 = _ball.visual_center() + up * (_ball.visual_radius() + ball_bar_margin)
		if over_ball.dot(up) > home.dot(up):
			target = over_ball
	health_bar.global_position = target
	if stun_bar != null:
		stun_bar.global_position = target + (to_global(_stun_bar_home) - home)


# ---------------------------------------------------------------- DÉGÂTS

## damage a une valeur par défaut : les coups normaux appellent take_hit(dir),
## le dash chargé passe ses propres dégâts.
func take_hit(direction: Vector3, damage: int = damage_per_hit, breaks_stun: bool = false) -> void:
	if state == State.DEAD:
		return

	health -= damage
	health_bar.set_ratio(float(health) / float(max_health))

	if health <= 0:
		_die(direction)
		return

	# Recul visible : plus marqué pour un coup lourd
	_hit_react.play(direction, clampf(float(damage) / float(maxi(damage_per_hit, 1)), 1.0, 2.0))

	# Étourdi, il encaisse sans se réveiller : seule l'attaque réaction
	# (finisher / toupie, breaks_stun = true) met fin à l'étourdissement.
	if state == State.STUNNED and not breaks_stun:
		return

	# Frappé pendant le façonnage : le boulet en cours lui échappe et se casse
	# (et il est étourdi, voir _on_ball_broken)
	if state == State.BUILD and _ball != null and _ball.is_present():
		_ball.shatter()
		if state == State.STUNNED:
			return

	# Une charge interrompue par un coup : c'est la récompense du joueur
	attack_box.monitoring = false
	AttackToken.release(self)
	mesh.scale = _base_scale
	mesh.rotation.z = 0.0
	mesh.position.y = _stun_base_y

	if _charge_zone != null and is_instance_valid(_charge_zone):
		_charge_zone.queue_free()
		_charge_zone = null

	# Coups légers : petit recul, l'ennemi reste à portée du combo.
	# Coups lourds (finisher, poing chargé) : recul proportionnel aux dégâts.
	var heavy: float = clampf(float(damage) / float(maxi(damage_per_hit, 1)), 1.0, heavy_knockback_mult)
	_knockback = direction * knockback_force * heavy
	_set_state(State.HURT)
	_flash()


func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	if _tele_tween != null and _tele_tween.is_running():
		_tele_tween.kill()

	var step: float = flash_duration / (flash_count * 2)
	_flash_tween = create_tween()
	for i in flash_count:
		_flash_tween.tween_property(_mat, "albedo_color", flash_color, step * 0.4)
		_flash_tween.tween_property(_mat, "albedo_color", _base_color, step * 1.6)


func _die(direction: Vector3) -> void:
	if _hit_react != null:
		_hit_react.stop()
	Sfx.play("enemy_death", global_position)
	_set_state(State.DEAD)
	died.emit()
	if _ball != null and _has_ball:
		_ball.shatter()
	# On coupe toutes les interactions immédiatement
	hurt_box.monitorable = false
	attack_box.monitoring = false
	set_collision_layer_value(1, false)
	health_bar.visible = false
	velocity = Vector3.ZERO
	AttackToken.release(self)

	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	if _tele_tween != null and _tele_tween.is_running():
		_tele_tween.kill()
	_mat.albedo_color = flash_color

	var away: Vector3 = global_position + direction * death_launch + Vector3.UP * 0.4

	var d := create_tween().set_parallel(true)
	d.tween_property(self, "global_position", away, death_time)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	d.tween_property(mesh, "scale", Vector3(1.3, 0.05, 1.3), death_time)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	d.tween_property(_mat, "albedo_color:a", 0.0, death_time)

	await d.finished
	queue_free()

## Rempli par le joueur à chaque coup reçu (1 par défaut) ; une fois le
## quota atteint, déclenche l'étourdissement tout seul. Le compteur se
## remet à zéro à chaque coup — c'est ce qui redonne du temps avant que
## la jauge ne commence réellement à redescendre.
func add_stun(amount: float = 1.0) -> void:
	if state == State.DEAD or state == State.STUNNED or state == State.GRABBED:
		return
	_stun_bar = clampf(_stun_bar + amount, 0.0, float(stun_hits_required))
	_stun_idle_t = 0.0
	if stun_bar != null:
		stun_bar.set_ratio(_stun_bar / float(stun_hits_required))
	if _stun_bar >= float(stun_hits_required) - 0.15:
		stun(stun_duration)


## Ce que la commande réaction du joueur déclenche une fois cet ennemi
## étourdi : "spin" pour la toupie, "finisher" pour le coup lourd ciblé.
func get_reaction() -> String:
	return reaction


## Appelé par le joueur. Un ennemi étourdi est immobile et ouvert à la toupie.
func stun(duration: float) -> void:
	if state == State.DEAD or state == State.GRABBED:
		return
	Sfx.play("stun", global_position)

	_stun_frame = Engine.get_physics_frames()

	_stun_bar = 0.0
	_stun_idle_t = 0.0
	if stun_bar != null:
		stun_bar.set_ratio(0.0)

	stun_duration = duration
	attack_box.monitoring = false

	
	AttackToken.release(self)
	mesh.scale = _base_scale
	velocity = Vector3.ZERO
	_cooldown = maxf(_cooldown, duration)

	_set_state(State.STUNNED)

	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	if _tele_tween != null and _tele_tween.is_running():
		_tele_tween.kill()
	_mat.albedo_color = stun_color

func _stunned(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	mesh.position.y = _stun_base_y + sin(_t * 9.0) * stun_wobble * 0.3
	mesh.rotation.z = sin(_t * 6.0) * stun_wobble

	# Vert vif seulement à portée : le joueur sait sans ambiguïté quand cliquer
	var d: float = _distance_to_player()
	_mat.albedo_color = stun_color if d <= 3.0 else stun_color.darkened(0.45)

	if _t >= stun_duration:
		mesh.position.y = _stun_base_y
		mesh.rotation.z = 0.0
		_mat.albedo_color = _base_color
		_set_state(State.CHASE)

func is_stunned() -> bool:
	return state == State.STUNNED


## Le joueur l'attrape (réaction "whirl"). Il ne bouge plus, ne collisionne
## plus et ne peut plus être frappé : c'est Combat qui le transporte.
func begin_grab() -> bool:
	if state != State.STUNNED:
		return false
	_saved_layers = Vector3i(collision_layer, collision_mask, hurt_box.collision_layer)
	collision_layer = 0
	collision_mask = 0
	hurt_box.collision_layer = 0
	velocity = Vector3.ZERO
	mesh.position.y = _stun_base_y
	mesh.rotation.z = 0.0
	_mat.albedo_color = stun_color
	_set_state(State.GRABBED)
	return true


## Relâché : il redevient un ennemi normal le temps du coup qui l'achève.
func end_grab() -> void:
	if state != State.GRABBED:
		return
	collision_layer = _saved_layers.x
	collision_mask = _saved_layers.y
	hurt_box.collision_layer = _saved_layers.z
	_mat.albedo_color = _base_color
	_set_state(State.HURT)


## Vrai pendant que l'ennemi prépare ou porte une attaque. Lu par le HUD
## pour signaler une menace hors de l'écran.
func is_threatening() -> bool:
	return state == State.TELEGRAPH or state == State.CHARGE
