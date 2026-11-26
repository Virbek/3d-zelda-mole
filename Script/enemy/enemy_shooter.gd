extends CharacterBody3D

## Ennemi à distance. Cherche à rester dans une fourchette de distance
## (ni collé, ni hors de portée), vise avec un télégraphe, puis tire.
##
## Contrairement au chargeur, il ne prend PAS le jeton d'attaque : sinon
## un seul ennemi agirait à l'écran et les tireurs resteraient muets.
## Son télégraphe est plus long en compensation.
##
## Il vise la HurtBox du torse plutôt que la capsule du joueur : il tire donc
## là où le joueur se voit, et les esquives deviennent lisibles.

enum State { IDLE, REPOSITION, AIM, SHOOT, RECOVER, HURT, STUNNED, DEAD, GRABBED }

signal died

@export var player_path: NodePath
@export var projectile_scene: PackedScene

@export_group("Vie")
@export var max_health: int = 3
@export var damage_per_hit: int = 1

@export_group("Distances")
@export var detect_range: float = 13.0
@export var lose_range: float = 17.0
@export var flee_range: float = 5.5    ## trop près : il fuit
@export var keep_max: float = 9.0      ## trop loin : il avance
@export var strafe_speed: float = 2.4
@export var run_speed: float = 3.2     ## vitesse de fuite à distance (le joueur reste bien plus rapide)
## Au contact, il décroche mal : sa fuite tombe à cette part de run_speed,
## pour que le joueur puisse enchaîner quelques coups avant qu'il s'éloigne.
@export var close_flee_factor: float = 0.45
@export var close_range: float = 2.2
@export var panic_range: float = 3.2   ## si le joueur arrive à cette distance pendant la visée, il abandonne et fuit
@export var wall_probe: float = 1.6    ## distance de détection des murs dans la direction de fuite

@export_group("Tir")
@export var aim_time: float = 1.0      ## télégraphe : c'est lui qui rend le tir esquivable
## Tir à bout portant : collé au joueur, il tire quand même, avec une visée
## plus courte (part de aim_time) qu'il n'annule pas.
@export var close_aim_factor: float = 0.6
@export var close_shot_range: float = 3.0
@export var shoot_recover: float = 0.4
@export var shoot_cooldown: float = 1.6
@export var muzzle_offset: float = 0.75 ## distance de spawn devant lui (pointe du dard recourbé)
@export var muzzle_height: float = 0.75
@export var lead_factor: float = 0.25  ## anticipation du déplacement du joueur
@export var projectile_speed: float = 6.5  ## écrase la vitesse du projectile
## Layers du décor qui bloquent la ligne de vue (murs, poteaux).
@export_flags_3d_physics var sight_mask: int = 1

@export_group("Déplacement")
@export var turn_speed: float = 7.0
@export var gravity: float = 20.0

@export_group("Recul")
@export var knockback_force: float = 3.5   ## recul d'un coup léger : faible, pour pouvoir enchaîner
## Multiplicateur max du recul pour un coup lourd (dégâts > damage_per_hit)
@export var heavy_knockback_mult: float = 2.5
@export var knockback_damping: float = 8.0
@export var hurt_time: float = 0.28

@export_group("Couleurs")
@export var aim_color := Color(0.9, 0.85, 0.2)
@export var flash_color := Color(1.0, 0.15, 0.15)
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
## Ce que déclenche la commande réaction une fois étourdi. "slam" : le joueur
## l'attrape, la fracasse au sol et elle éclate en dards autour de lui.
## ("spin" reste disponible si on veut revenir à la toupie.)
@export var reaction: String = "slam"

var player: CharacterBody3D = null
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var health_bar: Node3D = $HealthBar
@onready var hurt_box: Area3D = $HurtBox
@onready var stun_bar: Node3D = get_node_or_null("StunBar")

var state: State = State.IDLE
var health: int

var _t: float = 0.0
var _buzz: Node = null    ## bourdonnement d'ailes en boucle
var _cooldown: float = 0.0
var _knockback := Vector3.ZERO
var _strafe_dir: float = 1.0
var _stun_bar: float = 0.0
var _stun_idle_t: float = 0.0
var _stun_frame: int = -1             ## frame physique où l'étourdissement a commencé
var _saved_layers := Vector3i.ZERO    ## corps (calque, masque) et HurtBox (calque) pendant la saisie
var _player_hurt: Area3D = null

var _mat: StandardMaterial3D
var _base_color: Color
var _base_scale := Vector3.ONE
var _hit_react: HitReaction = null
var _flash_tween: Tween

var _stun_base_y: float = 0.0

## Apparence du frelon-perceur (null si désactivée : on garde la capsule)
@export var use_hornet_model: bool = true
var _model: HornetModel = null
var _close_shot: bool = false   ## la visée en cours est un tir à bout portant


func _ready() -> void:
	player = get_node_or_null(player_path)
	if player == null:
		push_warning("%s : player introuvable" % name)
		set_physics_process(false)
		return
	add_to_group("enemy")
	health = max_health
	_buzz = Sfx.attach_loop("hornet_buzz", self, -10.0)
	_base_scale = mesh.scale
	_hit_react = HitReaction.attach(mesh)
	_stun_base_y = mesh.position.y
	_mat = mesh.get_active_material(0).duplicate()
	mesh.material_override = _mat
	_base_color = _mat.albedo_color

	# Le frelon est rangé sous le mesh : il hérite de l'étirement de visée,
	# du vacillement d'étourdissement et de l'écrasement à la mort.
	if use_hornet_model:
		_model = HornetModel.new()
		mesh.add_child(_model)
		_model.position.y = -_stun_base_y   # repère au sol
		mesh.mesh = null

	health_bar.set_ratio(1.0)
	_strafe_dir = 1.0 if randf() > 0.5 else -1.0
	# Décale les premiers tirs pour éviter les salves synchronisées
	_cooldown = randf_range(0.0, shoot_cooldown)

	# La zone de dégâts du joueur vit sur son torse, pas sur sa capsule
	for n in get_tree().get_nodes_in_group("player_hurt"):
		_player_hurt = n
		break


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
		State.REPOSITION:
			_reposition(delta)
		State.AIM:
			_aim(delta)
		State.SHOOT:
			_shoot()
		State.RECOVER:
			_recover(delta)
		State.HURT:
			_hurt(delta)
		State.STUNNED:
			_stunned()
		State.DEAD, State.GRABBED:
			return   # saisi : c'est le joueur qui le déplace

	_apply_gravity(delta)
	move_and_slide()


## Visuel uniquement : abdomen qui se recourbe pour viser, rayures qui
## s'allument, ailes et flottement.
func _process(delta: float) -> void:
	if _model == null:
		return
	_model.set_tint(_mat.albedo_color, _base_color)
	var curl: float = 0.0
	var threat: float = 0.0
	match state:
		State.AIM:
			curl = clampf(_t / maxf(_aim_duration() * 0.7, 0.01), 0.0, 1.0)
			threat = clampf(_t / maxf(_aim_duration(), 0.01), 0.0, 1.0)
		State.SHOOT:
			curl = 1.0
			threat = 1.0
		State.RECOVER:
			curl = 1.0 - clampf(_t / maxf(shoot_recover, 0.01), 0.0, 1.0)
	_model.set_curl(curl)
	_model.set_threat(threat)
	_model.fly(Vector2(velocity.x, velocity.z).length(), delta)


func _aim_duration() -> float:
	return aim_time * (close_aim_factor if _close_shot else 1.0)


func _set_state(next: State) -> void:
	state = next
	_t = 0.0


# ---------------------------------------------------------------- ÉTATS

func _idle(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _distance_to_player() < detect_range:
		_set_state(State.REPOSITION)


func _reposition(delta: float) -> void:
	var d: float = _distance_to_player()

	if d > lose_range:
		_set_state(State.IDLE)
		return

	# En bonne fourchette, rechargé et avec une ligne de vue dégagée : il vise.
	# Sinon il continue de tourner autour pour trouver un angle.
	if d >= flee_range and d <= keep_max and _cooldown <= 0.0 and _has_line_of_sight():
		_close_shot = false
		_set_state(State.AIM)
		_start_aim()
		return

	# Le joueur lui colle aux ailes : plutôt que de seulement fuir, il riposte
	if d <= close_shot_range and _cooldown <= 0.0 and _has_line_of_sight():
		_close_shot = true
		_set_state(State.AIM)
		_start_aim()
		return

	var to_player: Vector3 = _dir_to_player()
	var move := Vector3.ZERO
	var spd := strafe_speed

	if d < flee_range:
		move = _flee_direction(-to_player)       # fuit en évitant les murs
		# Lent au contact, il accélère à mesure qu'il prend de la distance
		var k: float = clampf((d - close_range) / maxf(flee_range - close_range, 0.01), 0.0, 1.0)
		spd = run_speed * lerpf(close_flee_factor, 1.0, k)
	elif d > keep_max:
		move = to_player                         # approche
	else:
		move = to_player.cross(Vector3.UP) * _strafe_dir   # tourne en attendant

	move = move.normalized()
	velocity.x = move.x * spd
	velocity.z = move.z * spd
	# En fuite, il regarde où il court ; sinon il garde le joueur en vue
	_face(move if d < flee_range else to_player, delta)


## Direction de fuite : à l'opposé du joueur si possible, sinon l'angle libre
## le plus proche. Coincé de partout, il longe le mur pour tenter de passer.
func _flee_direction(away: Vector3) -> Vector3:
	away.y = 0.0
	if away.length() < 0.01:
		away = global_transform.basis.z
	away = away.normalized()
	for deg: float in [0.0, 35.0, 70.0, 105.0]:
		for side: float in [_strafe_dir, -_strafe_dir]:
			var dir: Vector3 = away.rotated(Vector3.UP, deg_to_rad(deg) * side)
			if _path_clear(dir):
				return dir
			if deg == 0.0:
				break
	# Dos au mur : il le longe, et ne change de côté que si celui-ci est bloqué
	var slide: Vector3 = away.cross(Vector3.UP) * _strafe_dir
	if not _path_clear(slide):
		_strafe_dir = -_strafe_dir
		slide = -slide
	return slide


func _path_clear(dir: Vector3) -> bool:
	var from: Vector3 = global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * wall_probe, sight_mask)
	query.exclude = [get_rid()]
	var res: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if res.is_empty():
		return true
	# Le joueur ou un autre ennemi ne sont pas des murs
	return res["collider"] is CharacterBody3D


func _aim(delta: float) -> void:
	# Immobile pendant la visée : c'est sa fenêtre de vulnérabilité
	velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)

	_face(_dir_to_player(), delta)

	# Le joueur a foncé sur lui : il abandonne son tir et prend la fuite
	# (sauf s'il a justement armé un tir à bout portant)
	if not _close_shot and _distance_to_player() < panic_range:
		_cancel_aim()
		_cooldown = maxf(_cooldown, 0.8)
		return

	# Il se ramasse puis s'étire, comme une arbalète qu'on bande
	var k: float = _t / _aim_duration()
	mesh.scale = _base_scale * Vector3(1.0 - k * 0.15, 1.0 + k * 0.3, 1.0 - k * 0.15)

	if _t >= _aim_duration():
		# Le joueur s'est caché derrière un obstacle : tir annulé
		if not _has_line_of_sight():
			_cancel_aim()
			return
		_set_state(State.SHOOT)


func _shoot() -> void:
	mesh.scale = _base_scale

	if projectile_scene != null:
		var p: Area3D = projectile_scene.instantiate()
		var dir: Vector3 = _aim_direction()

		get_tree().current_scene.add_child(p)
		p.global_position = global_position + dir * muzzle_offset + Vector3.UP * muzzle_height
		p.direction = dir
		p.speed = projectile_speed
		p.shooter = self
		Sfx.play("hornet_shoot", global_position)

	_cooldown = shoot_cooldown
	_set_state(State.RECOVER)


func _recover(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)

	if _t >= shoot_recover:
		_set_state(State.REPOSITION)


func _hurt(delta: float) -> void:
	velocity.x = _knockback.x
	velocity.z = _knockback.z
	_knockback *= exp(-knockback_damping * delta)

	if _t >= hurt_time:
		_set_state(State.REPOSITION)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta


# ---------------------------------------------------------------- OUTILS

## Le point à viser : le torse s'il est disponible, la capsule sinon.
func _aim_point() -> Vector3:
	if _player_hurt != null and is_instance_valid(_player_hurt):
		return _player_hurt.global_position
	return player.global_position


func _distance_to_player() -> float:
	var v: Vector3 = _aim_point() - global_position
	v.y = 0.0
	return v.length()


func _dir_to_player() -> Vector3:
	var v: Vector3 = _aim_point() - global_position
	v.y = 0.0
	if v.length() < 0.01:
		return -global_transform.basis.z
	return v.normalized()


## Vise légèrement devant le joueur s'il se déplace : un tir toujours
## parfaitement centré est trop facile à esquiver par simple strafe.
func _aim_direction() -> Vector3:
	var predicted: Vector3 = _aim_point()
	predicted += Vector3(player.velocity.x, 0.0, player.velocity.z) * lead_factor

	var v: Vector3 = predicted - (global_position + Vector3.UP * muzzle_height)
	v.y = 0.0
	if v.length() < 0.01:
		return -global_transform.basis.z
	return v.normalized()


## Vrai si aucun élément de décor ne sépare la bouche du canon du torse.
func _has_line_of_sight() -> bool:
	var from: Vector3 = global_position + Vector3.UP * muzzle_height
	var to: Vector3 = _aim_point()
	var query := PhysicsRayQueryParameters3D.create(from, to, sight_mask)
	var exclude: Array[RID] = [get_rid()]
	var space := get_world_3d().direct_space_state
	for i in 6:
		query.exclude = exclude
		var res: Dictionary = space.intersect_ray(query)
		if res.is_empty():
			return true
		# Joueur et autres ennemis ne cachent pas la cible (le tir les traverse)
		var col: Object = res["collider"]
		if col is CharacterBody3D or col is RigidBody3D:
			exclude.append(res["rid"])
			continue
		return false
	return true


func _cancel_aim() -> void:
	mesh.scale = _base_scale
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_mat.albedo_color = _base_color
	_strafe_dir = -_strafe_dir   # change de côté pour chercher un angle
	_cooldown = 0.4
	_set_state(State.REPOSITION)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var target_angle: float = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, turn_speed * delta)


func _start_aim() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_mat, "albedo_color", aim_color, _aim_duration() * 0.8)
	_flash_tween.tween_property(_mat, "albedo_color", _base_color, _aim_duration() * 0.2)


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

	mesh.scale = _base_scale
	mesh.rotation.z = 0.0
	mesh.position.y = _stun_base_y
	# Un tir en préparation est annulé : c'est la récompense du joueur
	# qui a couvert la distance pour aller le déranger.
	mesh.scale = _base_scale

	# Coups légers : petit recul, l'ennemi reste à portée du combo.
	# Coups lourds (finisher, poing chargé) : recul proportionnel aux dégâts.
	var heavy: float = clampf(float(damage) / float(maxi(damage_per_hit, 1)), 1.0, heavy_knockback_mult)
	_knockback = direction * knockback_force * heavy
	_set_state(State.HURT)
	_flash()


func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()

	var step: float = flash_duration / (flash_count * 2)
	_flash_tween = create_tween()
	for i in flash_count:
		_flash_tween.tween_property(_mat, "albedo_color", flash_color, step * 0.4)
		_flash_tween.tween_property(_mat, "albedo_color", _base_color, step * 1.6)


func _die(direction: Vector3) -> void:
	if _hit_react != null:
		_hit_react.stop()
	Sfx.play("enemy_death", global_position)
	Sfx.stop_loop(_buzz)
	_buzz = null
	_set_state(State.DEAD)
	died.emit()
	hurt_box.monitorable = false
	set_collision_layer_value(1, false)
	health_bar.visible = false
	velocity = Vector3.ZERO

	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
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
	Sfx.play("stun", global_position)

	_stun_frame = Engine.get_physics_frames()

	_stun_bar = 0.0
	_stun_idle_t = 0.0
	if stun_bar != null:
		stun_bar.set_ratio(0.0)

	mesh.scale = _base_scale     # annule l'étirement de visée en cours
	velocity = Vector3.ZERO
	_stun_base_y = mesh.position.y
	_cooldown = maxf(_cooldown, duration)   # pas de tir dès le réveil

	_set_state(State.STUNNED)

	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_mat.albedo_color = stun_color
	stun_duration = duration


## Le joueur l'attrape (réaction "slam"). Il ne bouge plus, ne collisionne
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


## Relâché (juste avant l'impact) : il redevient un ennemi normal. Le coup
## qui suit décide s'il meurt ou s'il est sonné.
func end_grab() -> void:
	if state != State.GRABBED:
		return
	collision_layer = _saved_layers.x
	collision_mask = _saved_layers.y
	hurt_box.collision_layer = _saved_layers.z
	_mat.albedo_color = _base_color
	_set_state(State.REPOSITION)


func is_stunned() -> bool:
	return state == State.STUNNED


## Vrai pendant que l'ennemi prépare ou porte une attaque. Lu par le HUD
## pour signaler une menace hors de l'écran.
func is_threatening() -> bool:
	return state == State.AIM

func _stunned() -> void:
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
		_set_state(State.REPOSITION)
