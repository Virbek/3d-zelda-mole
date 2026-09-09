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

enum State { IDLE, REPOSITION, AIM, SHOOT, RECOVER, HURT, STUNNED, DEAD }

signal died

@export var player_path: NodePath
@export var projectile_scene: PackedScene

@export_group("Vie")
@export var max_health: int = 3
@export var damage_per_hit: int = 1

@export_group("Distances")
@export var detect_range: float = 13.0
@export var lose_range: float = 17.0
@export var keep_min: float = 5.0      ## trop près : il recule
@export var keep_max: float = 9.0      ## trop loin : il avance
@export var strafe_speed: float = 2.4
@export var flee_speed: float = 3.6    ## plus rapide en fuite qu'en approche

@export_group("Tir")
@export var aim_time: float = 1.0      ## télégraphe : c'est lui qui rend le tir esquivable
@export var shoot_recover: float = 0.6
@export var shoot_cooldown: float = 2.2
@export var muzzle_offset: float = 0.9 ## distance de spawn devant lui
@export var muzzle_height: float = 0.9
@export var lead_factor: float = 0.25  ## anticipation du déplacement du joueur

@export_group("Déplacement")
@export var turn_speed: float = 7.0
@export var gravity: float = 20.0

@export_group("Recul")
@export var knockback_force: float = 9.0
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
@export var stun_duration: float = 3.0
@export var stun_color := Color(0.25, 1.0, 0.35)
@export var stun_wobble: float = 0.12   ## amplitude du vacillement
@export var stun_hits_required: int = 6     ## nombre de coups pour étourdir
@export var stun_drain_delay: float = 0.6   ## temps sans coup avant que la jauge commence à redescendre
@export var stun_drain_rate: float = 0.8    ## coups perdus par seconde, une fois la latence passée
@export var reaction: String = "finisher"   ## ce que déclenche la commande réaction une fois étourdi

@export_group("Butin")
@export var pickup_scene: PackedScene
@export var pickup_chance: float = 0.45   ## probabilité d'en lâcher un
@export var pickup_max: int = 2           ## combien au maximum

var player: CharacterBody3D = null
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var health_bar: Node3D = $HealthBar
@onready var hurt_box: Area3D = $HurtBox
@onready var stun_bar: Node3D = get_node_or_null("StunBar")

var state: State = State.IDLE
var health: int

var _t: float = 0.0
var _cooldown: float = 0.0
var _knockback := Vector3.ZERO
var _strafe_dir: float = 1.0
var _stun_bar: float = 0.0
var _stun_idle_t: float = 0.0
var _player_hurt: Area3D = null

var _mat: StandardMaterial3D
var _base_color: Color
var _base_scale := Vector3.ONE
var _flash_tween: Tween

var _stun_base_y: float = 0.0


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
		_set_state(State.REPOSITION)


func _reposition(delta: float) -> void:
	var d: float = _distance_to_player()

	if d > lose_range:
		_set_state(State.IDLE)
		return

	# En bonne fourchette et rechargé : il vise
	if d >= keep_min and d <= keep_max and _cooldown <= 0.0:
		_set_state(State.AIM)
		_start_aim()
		return

	var to_player: Vector3 = _dir_to_player()
	var move := Vector3.ZERO
	var spd := strafe_speed

	if d < keep_min:
		move = -to_player                        # recule
		spd = flee_speed
	elif d > keep_max:
		move = to_player                         # approche
	else:
		move = to_player.cross(Vector3.UP) * _strafe_dir   # tourne en attendant

	move = move.normalized()
	velocity.x = move.x * spd
	velocity.z = move.z * spd
	_face(to_player, delta)


func _aim(delta: float) -> void:
	# Immobile pendant la visée : c'est sa fenêtre de vulnérabilité
	velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)

	_face(_dir_to_player(), delta)

	# Il se ramasse puis s'étire, comme une arbalète qu'on bande
	var k: float = _t / aim_time
	mesh.scale = _base_scale * Vector3(1.0 - k * 0.15, 1.0 + k * 0.3, 1.0 - k * 0.15)

	if _t >= aim_time:
		_set_state(State.SHOOT)


func _shoot() -> void:
	mesh.scale = _base_scale

	if projectile_scene != null:
		var p: Area3D = projectile_scene.instantiate()
		var dir: Vector3 = _aim_direction()

		get_tree().current_scene.add_child(p)
		p.global_position = global_position + dir * muzzle_offset + Vector3.UP * muzzle_height
		p.direction = dir
		p.shooter = self

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


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var target_angle: float = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, turn_speed * delta)


func _start_aim() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_mat, "albedo_color", aim_color, aim_time * 0.8)
	_flash_tween.tween_property(_mat, "albedo_color", _base_color, aim_time * 0.2)


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
	mesh.scale = _base_scale
	mesh.rotation.z = 0.0
	mesh.position.y = _stun_base_y
	# Un tir en préparation est annulé : c'est la récompense du joueur
	# qui a couvert la distance pour aller le déranger.
	mesh.scale = _base_scale

	_knockback = direction * knockback_force
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
	_set_state(State.DEAD)
	died.emit()
	_drop_pickups()
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


func is_stunned() -> bool:
	return state == State.STUNNED

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