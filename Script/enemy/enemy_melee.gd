extends CharacterBody3D

## Ennemi de corps à corps. Marche sur le joueur, s'arrête à portée, arme
## son coup (télégraphe), frappe un arc devant lui, puis reste vulnérable.
##
## Le télégraphe est ce qui rend le coup esquivable : il se penche en arrière
## et change de couleur. La direction est verrouillée peu avant la frappe —
## un coup qui suit le joueur jusqu'au dernier instant serait impossible à
## esquiver par un pas de côté.
##
## Comme le chargeur, il prend le jeton d'attaque : sans jeton, il tourne
## autour du joueur à distance en attendant son tour.
##
## Il se déplace vers la capsule du joueur (stable) mais frappe sa HurtBox de
## torse (Area3D du groupe "player_hurt").

enum State { IDLE, CHASE, WINDUP, STRIKE, RECOVER, HURT, STUNNED, DEAD }

signal died

@export var player_path: NodePath

@export_group("Vie")
@export var max_health: int = 6
@export var damage_per_hit: int = 1

@export_group("Détection")
@export var detect_range: float = 10.0
@export var lose_range: float = 14.0       ## plus grande que detect_range : hystérésis
@export var lose_time: float = 4.0

@export_group("Déplacement")
@export var chase_speed: float = 3.2
@export var accel: float = 14.0
@export var turn_speed: float = 8.0
@export var gravity: float = 20.0
@export var stop_distance: float = 1.3     ## il ne pousse pas le joueur, il s'arrête devant

@export_group("Attaque")
@export var attack_range: float = 1.9      ## distance à laquelle il arme son coup
@export var windup_time: float = 0.55      ## télégraphe : ne descends pas sous ~0.4s
@export var windup_track: float = 0.6      ## part du télégraphe pendant laquelle il suit encore le joueur
@export var strike_time: float = 0.18      ## fenêtre active de la frappe
@export var strike_lunge: float = 4.5      ## petit pas en avant pendant la frappe
@export var recover_time: float = 0.7      ## fenêtre de punition pour le joueur
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.0
@export var lean_angle: float = 0.45       ## inclinaison (radians) pendant l'armement

@export_group("Encerclement")
@export var circle_distance: float = 3.5
@export var circle_speed: float = 2.2

@export_group("Recul")
@export var knockback_force: float = 9.0
@export var knockback_damping: float = 8.0
@export var hurt_time: float = 0.28

@export_group("Couleurs")
@export var flash_color := Color(1.0, 0.15, 0.15)
@export var telegraph_color := Color(1.0, 0.55, 0.1)
@export var flash_count: int = 3
@export var flash_duration: float = 0.4

@export_group("Mort")
@export var death_time: float = 0.45
@export var death_launch: float = 1.6

@export_group("Étourdissement")
@export var stun_duration: float = 3.0
@export var stun_color := Color(0.25, 1.0, 0.35)
@export var stun_wobble: float = 0.12
@export var stun_hits_required: int = 4
@export var stun_drain_delay: float = 0.6
@export var stun_drain_rate: float = 0.8
@export var reaction: String = "finisher"   ## ce que déclenche la commande réaction une fois étourdi

var player: CharacterBody3D = null
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var health_bar: Node3D = $HealthBar
@onready var stun_bar: Node3D = get_node_or_null("StunBar")
@onready var hurt_box: Area3D = $HurtBox
@onready var attack_box: Area3D = $AttackBox

var state: State = State.IDLE
var health: int

var _t: float = 0.0
var _cooldown: float = 0.0
var _lose_t: float = 0.0
var _circle_dir: float = 1.0
var _strike_dir := Vector3.ZERO
var _knockback := Vector3.ZERO
var _hit_player: bool = false             ## un seul dégât par frappe
var _stun_bar: float = 0.0
var _stun_idle_t: float = 0.0
var _stun_frame: int = -1             ## frame physique où l'étourdissement a commencé

var _mat: StandardMaterial3D
var _base_color: Color
var _base_scale := Vector3.ONE
var _hit_react: HitReaction = null
var _base_mesh_y: float = 0.0
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
	_hit_react = HitReaction.attach(mesh)
	_base_mesh_y = mesh.position.y
	var base := mesh.get_active_material(0)
	_mat = base.duplicate() if base != null else StandardMaterial3D.new()
	mesh.material_override = _mat
	_base_color = _mat.albedo_color

	health_bar.set_ratio(1.0)
	attack_box.monitoring = false
	_circle_dir = 1.0 if randf() > 0.5 else -1.0


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
			_idle()
		State.CHASE:
			_chase(delta)
		State.WINDUP:
			_windup(delta)
		State.STRIKE:
			_strike(delta)
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

func _idle() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _distance_to_player() < detect_range:
		_lose_t = 0.0
		_set_state(State.CHASE)


func _chase(delta: float) -> void:
	var d: float = _distance_to_player()

	if d > lose_range:
		_lose_t += delta
		if _lose_t >= lose_time:
			_set_state(State.IDLE)
			return
	else:
		_lose_t = 0.0

	var dir: Vector3 = _dir_to_player()

	var can_attack: bool = _cooldown <= 0.0 and AttackToken.is_available(self)

	if d <= attack_range and can_attack and AttackToken.request(self):
		_start_windup()
		return

	# Pas de jeton (ou en recharge) : il garde ses distances en tournant,
	# plutôt que de rester collé au joueur sans rien faire. Le jeton n'est
	# demandé qu'au contact, pour ne pas le monopoliser pendant l'approche.
	if not can_attack and d < circle_distance + 1.0:
		_circle(delta, d)
		return

	var target_speed: float = chase_speed if d > stop_distance else 0.0
	velocity.x = move_toward(velocity.x, dir.x * target_speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * target_speed, accel * delta)
	_face(dir, delta)


## Tourne autour du joueur en gardant ses distances, en attendant son tour.
func _circle(delta: float, d: float) -> void:
	var to_player: Vector3 = _dir_to_player()
	var tangent: Vector3 = to_player.cross(Vector3.UP) * _circle_dir
	var radial: float = (d - circle_distance) * 0.8
	var move: Vector3 = (tangent + to_player * radial).normalized()

	velocity.x = move_toward(velocity.x, move.x * circle_speed, accel * delta)
	velocity.z = move_toward(velocity.z, move.z * circle_speed, accel * delta)
	_face(to_player, delta)


func _windup(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)

	var k: float = clampf(_t / windup_time, 0.0, 1.0)

	# Il suit le joueur au début, puis la direction se fige : le dernier
	# tiers du télégraphe est la fenêtre d'esquive latérale.
	if k < windup_track:
		_strike_dir = _dir_to_player()
	_face(_strike_dir, delta)

	# Il se penche en arrière en se tassant, comme pour prendre son élan
	mesh.rotation.x = lean_angle * k
	mesh.scale = _base_scale * Vector3(1.0 + k * 0.12, 1.0 - k * 0.12, 1.0 + k * 0.12)

	if _t >= windup_time:
		mesh.scale = _base_scale
		_hit_player = false
		attack_box.monitoring = true
		_set_state(State.STRIKE)


func _strike(_delta: float) -> void:
	# Petit pas en avant : la frappe couvre la distance qu'un joueur gagne
	# en reculant d'un demi-pas, mais pas plus.
	velocity.x = _strike_dir.x * strike_lunge
	velocity.z = _strike_dir.z * strike_lunge
	rotation.y = atan2(-_strike_dir.x, -_strike_dir.z)

	# Bascule rapide vers l'avant : c'est le coup visible
	var k: float = clampf(_t / strike_time, 0.0, 1.0)
	mesh.rotation.x = lerpf(lean_angle, -lean_angle * 0.8, minf(k * 2.5, 1.0))

	_check_strike_hit()

	if _t >= strike_time:
		attack_box.monitoring = false
		velocity.x = 0.0
		velocity.z = 0.0
		AttackToken.release(self)
		_cooldown = attack_cooldown
		_set_state(State.RECOVER)


func _recover(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)

	# Il se redresse lentement : la posture penchée signale qu'il est ouvert
	var k: float = clampf(_t / recover_time, 0.0, 1.0)
	mesh.rotation.x = lerpf(-lean_angle * 0.8, 0.0, k * k)

	if _t >= recover_time:
		mesh.rotation.x = 0.0
		_set_state(State.CHASE)


func _hurt(delta: float) -> void:
	velocity.x = _knockback.x
	velocity.z = _knockback.z
	_knockback *= exp(-knockback_damping * delta)

	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0

	if _t >= hurt_time:
		_set_state(State.CHASE)


func _stunned() -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	mesh.position.y = _base_mesh_y + sin(_t * 9.0) * stun_wobble * 0.3
	mesh.rotation.z = sin(_t * 6.0) * stun_wobble

	# Vert vif seulement à portée : le joueur sait sans ambiguïté quand cliquer
	var d: float = _distance_to_player()
	_mat.albedo_color = stun_color if d <= 3.0 else stun_color.darkened(0.45)

	if _t >= stun_duration:
		_reset_pose()
		_mat.albedo_color = _base_color
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
	var target: float = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target, turn_speed * delta)


func _start_windup() -> void:
	_strike_dir = _dir_to_player()
	_set_state(State.WINDUP)

	if _tele_tween != null and _tele_tween.is_running():
		_tele_tween.kill()
	_tele_tween = create_tween()
	_tele_tween.tween_property(_mat, "albedo_color", telegraph_color, windup_time * 0.8)
	_tele_tween.tween_property(_mat, "albedo_color", _base_color, windup_time * 0.2)


## Cherche la HurtBox de torse du joueur dans l'arc de frappe.
## _hit_player garantit un seul dégât par coup, même si la zone reste
## superposée plusieurs frames.
func _check_strike_hit() -> void:
	if _hit_player:
		return

	for area in attack_box.get_overlapping_areas():
		if not area.is_in_group("player_hurt"):
			continue
		if not area.has_method("take_damage"):
			continue

		var dir: Vector3 = area.global_position - global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else _strike_dir
		area.take_damage(attack_damage, dir)
		_hit_player = true
		return


func _reset_pose() -> void:
	mesh.scale = _base_scale
	mesh.rotation = Vector3.ZERO
	mesh.position.y = _base_mesh_y


func _kill_tweens() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	if _tele_tween != null and _tele_tween.is_running():
		_tele_tween.kill()


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

	# Recul visible : plus marqué pour un coup lourd
	_hit_react.play(direction, clampf(float(damage) / float(maxi(damage_per_hit, 1)), 1.0, 2.0))

	# Le joueur appelle add_stun AVANT take_hit : le coup qui vient de remplir
	# la jauge ne doit pas annuler l'étourdissement qu'il a lui-même déclenché.
	# Tout coup suivant, lui, réveille l'ennemi (il passe en HURT ci-dessous).
	if state == State.STUNNED and Engine.get_physics_frames() == _stun_frame:
		return

	# Un coup pendant l'armement l'annule : c'est la récompense du joueur
	# qui frappe le premier.
	attack_box.monitoring = false
	AttackToken.release(self)
	_reset_pose()

	_knockback = direction * knockback_force
	_set_state(State.HURT)
	_flash()


func _flash() -> void:
	_kill_tweens()
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
	hurt_box.monitorable = false
	attack_box.monitoring = false
	set_collision_layer_value(1, false)
	health_bar.visible = false
	if stun_bar != null:
		stun_bar.visible = false
	velocity = Vector3.ZERO
	AttackToken.release(self)

	_kill_tweens()
	_reset_pose()
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


## Rempli par le joueur à chaque coup reçu ; une fois le quota atteint,
## déclenche l'étourdissement tout seul.
func add_stun(amount: float = 1.0) -> void:
	if state == State.DEAD or state == State.STUNNED:
		return
	_stun_bar = clampf(_stun_bar + amount, 0.0, float(stun_hits_required))
	_stun_idle_t = 0.0
	if stun_bar != null:
		stun_bar.set_ratio(_stun_bar / float(stun_hits_required))
	if _stun_bar >= float(stun_hits_required) - 0.15:
		stun(stun_duration)


func get_reaction() -> String:
	return reaction


func stun(duration: float) -> void:
	if state == State.DEAD:
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
	_reset_pose()
	velocity = Vector3.ZERO
	_cooldown = maxf(_cooldown, attack_cooldown)

	_set_state(State.STUNNED)
	_kill_tweens()
	_mat.albedo_color = stun_color


func is_stunned() -> bool:
	return state == State.STUNNED


## Vrai pendant que l'ennemi prépare ou porte une attaque. Lu par le HUD
## pour signaler une menace hors de l'écran.
func is_threatening() -> bool:
	return state == State.WINDUP or state == State.STRIKE
