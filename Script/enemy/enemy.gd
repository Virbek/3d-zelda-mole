extends CharacterBody3D

## Ennemi chargeur. Repère le joueur, approche, marque un temps d'arrêt visible
## (télégraphe), fonce en ligne droite, puis reste vulnérable un instant.
##
## Le télégraphe est le cœur du design : c'est lui qui rend la charge esquivable.
## Ne le raccourcis pas sous ~0.5s sans raison, le joueur n'aurait plus le temps
## de lire l'attaque.
##
## Il se déplace vers la capsule du joueur (stable) mais frappe sa HurtBox de
## torse (Area3D du groupe "player_hurt"). Viser le torse pour la navigation
## le ferait zigzaguer, puisque le buste oscille à chaque pas.

enum State { IDLE, CHASE, TELEGRAPH, CHARGE, RECOVER, HURT, STUNNED, DEAD }

signal died

@export var player_path: NodePath

@export_group("Vie")
@export var max_health: int = 5
@export var damage_per_hit: int = 1

@export_group("Détection")
@export var detect_range: float = 9.0      ## distance d'éveil
@export var lose_range: float = 13.0       ## distance d'abandon (plus grande : hystérésis)
@export var charge_range: float = 6.5      ## distance à laquelle il déclenche sa charge
@export var lose_time: float = 4.0         ## délai avant abandon hors de portée

@export_group("Déplacement")
@export var chase_speed: float = 2.6
@export var turn_speed: float = 6.0
@export var gravity: float = 20.0

@export_group("Charge")
@export var telegraph_time: float = 0.75   ## temps d'arrêt avant de foncer
@export var charge_speed: float = 13.0
## Doit dépasser charge_range d'une bonne marge : sinon reculer tout droit
## pendant le télégraphe suffit à sortir du couloir avant que la charge ne
## parte. La marge doit couvrir la distance qu'un joueur peut parcourir en
## reculant pendant telegraph_time.
@export var charge_distance: float = 10.0
@export var charge_max_time: float = 1.2   ## sécurité anti-blocage
@export var recover_time: float = 0.9      ## fenêtre de punition pour le joueur
@export var charge_damage: int = 1
@export var charge_cooldown: float = 1.2

@export_group("Couloir de charge")
@export var charge_zone_scene: PackedScene
@export var charge_width: float = 1.4      ## largeur du couloir affiché au sol

@export_group("Encerclement")
@export var circle_distance: float = 4.5
@export var circle_speed: float = 2.2
@export var circle_dir: float = 1.0        ## 1 ou -1, tiré au sort au démarrage

@export_group("Recul")
@export var knockback_force: float = 9.0
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

@export_group("Butin")
@export var pickup_scene: PackedScene
@export var pickup_chance: float = 0.45   ## probabilité d'en lâcher un
@export var pickup_max: int = 2           ## combien au maximum

@export_group("Étourdissement")
@export var stun_duration: float = 3.0
@export var stun_color := Color(0.25, 1.0, 0.35)
@export var stun_wobble: float = 0.12   ## amplitude du vacillement
@export var stun_hits_required: int = 6     ## nombre de coups pour étourdir
@export var stun_drain_delay: float = 0.6   ## temps sans coup avant que la jauge commence à redescendre
@export var stun_drain_rate: float = 0.8    ## coups perdus par seconde, une fois la latence passée
@export var reaction: String = "spin"       ## ce que déclenche la commande réaction une fois étourdi

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

var _stun_base_y: float = 0.0

var _mat: StandardMaterial3D
var _base_color: Color
var _base_scale := Vector3.ONE
var _flash_tween: Tween
var _tele_tween: Tween


func _ready() -> void:
	player = get_node_or_null(player_path)
	if player == null:
		push_warning("%s : player introuvable" % name)
		set_physics_process(false)
		return
	add_to_group("enemy")
	health = max_health
	_base_scale = mesh.scale
	_stun_base_y = mesh.position.y
	_mat = mesh.get_active_material(0).duplicate()
	mesh.material_override = _mat
	_base_color = _mat.albedo_color

	health_bar.set_ratio(1.0)
	attack_box.monitoring = false

	circle_dir = 1.0 if randf() > 0.5 else -1.0


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
		State.DEAD:
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
	if _distance_to_player() < detect_range:
		_aggro = true
		_lose_t = 0.0
		_set_state(State.CHASE)


func _chase(delta: float) -> void:
	var d: float = _distance_to_player()

	# Il n'abandonne que si le joueur reste loin un certain temps
	if d > lose_range:
		_lose_t += delta
		if _lose_t >= lose_time:
			_aggro = false
			_set_state(State.IDLE)
			return
	else:
		_lose_t = 0.0

		
	if d < charge_range and _cooldown <= 0.0:
		if not _has_clear_line_to_player():
			# Un pilier ou un autre ennemi coupe le couloir : charger
			# maintenant raterait à coup sûr. On se replace en attendant une
			# meilleure ouverture plutôt que de partir dans le vide.
			_circle(delta, d)
			return
		if AttackToken.request(self):
			_set_state(State.TELEGRAPH)
			_start_telegraph()
			return
		# Jeton pris : on tourne autour en attendant
		_circle(delta, d)
		return

	var dir: Vector3 = _dir_to_player()
	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed
	_face(dir, delta)


## Tourne autour du joueur en gardant ses distances, en attendant son tour.
func _circle(delta: float, d: float) -> void:
	var to_player: Vector3 = _dir_to_player()
	var tangent: Vector3 = to_player.cross(Vector3.UP) * circle_dir

	# Maintient la distance tout en tournant
	var radial: float = (d - circle_distance) * 0.8
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
	var to: Vector3 = from + dir * charge_distance
	var q := PhysicsRayQueryParameters3D.create(from, to)
	# Le joueur ne doit jamais agir comme un mur ici : la charge le traverse,
	# seul un vrai obstacle (mur, pilier) doit couper la mesure.
	q.exclude = [get_rid(), player.get_rid()]
	q.collision_mask = 1   # calque du décor

	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return charge_distance
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


# ---------------------------------------------------------------- DÉGÂTS

## damage a une valeur par défaut : les coups normaux appellent take_hit(dir),
## le dash chargé passe ses propres dégâts.
func take_hit(direction: Vector3, damage: int = damage_per_hit) -> void:
	if state == State.DEAD:
		return

	health -= damage
	health_bar.set_ratio(float(health) / float(max_health))

	if health <= 0:
		_die(direction)
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

	_knockback = direction * knockback_force
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
	_set_state(State.DEAD)
	died.emit()
	_drop_pickups()
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
	if state == State.DEAD or state == State.STUNNED:
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
	if state == State.DEAD:
		return

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

func _stunned(delta: float) -> void:
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


## Le butin est lâché avant le tween de mort : sinon l'await retarde
## l'apparition d'une demi-seconde, et le lien de cause à effet se perd.
func _drop_pickups() -> void:
	if pickup_scene == null or randf() > pickup_chance:
		return

	var n: int = 1 + (randi() % maxi(pickup_max, 1))
	for i in n:
		var p: Area3D = pickup_scene.instantiate()
		get_tree().current_scene.add_child(p)
		p.global_position = global_position + Vector3.UP * 0.6
