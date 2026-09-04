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

enum State { IDLE, CHASE, TELEGRAPH, CHARGE, RECOVER, HURT, DEAD }

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
@export var charge_distance: float = 6.0
@export var charge_max_time: float = 1.2   ## sécurité anti-blocage
@export var recover_time: float = 0.9      ## fenêtre de punition pour le joueur
@export var charge_damage: int = 1
@export var charge_cooldown: float = 1.2

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

@onready var player: CharacterBody3D = get_node(player_path)
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var health_bar: Node3D = $HealthBar
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
var _knockback := Vector3.ZERO
var _hit_player := false             ## un seul dégât par charge

var _mat: StandardMaterial3D
var _base_color: Color
var _base_scale := Vector3.ONE
var _flash_tween: Tween
var _tele_tween: Tween


func _ready() -> void:
	health = max_health
	_base_scale = mesh.scale

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

	# Il continue de viser pendant l'armement : le joueur doit vraiment esquiver,
	# pas juste marcher sur le côté
	var dir: Vector3 = _dir_to_player()
	_face(dir, delta * 0.6)

	# Léger tassement puis détente, comme un ressort qu'on comprime
	var k: float = _t / telegraph_time
	mesh.scale = _base_scale * Vector3(
		1.0 + k * 0.25,
		1.0 - k * 0.2,
		1.0 + k * 0.25
	)

	if _t >= telegraph_time:
		_charge_dir = _dir_to_player()
		_charge_start = global_position
		_hit_player = false
		attack_box.monitoring = true
		mesh.scale = _base_scale
		_set_state(State.CHARGE)


func _charge(_delta: float) -> void:
	velocity.x = _charge_dir.x * charge_speed
	velocity.z = _charge_dir.z * charge_speed

	_check_charge_hit()

	var travelled: float = Vector2(
		global_position.x - _charge_start.x,
		global_position.z - _charge_start.z
	).length()

	var blocked: bool = get_slide_collision_count() > 0 and _t > 0.05

	if travelled >= charge_distance or blocked or _t >= charge_max_time:
		# Choc contre un mur ou un autre ennemi : arrêt net, pas de glissade
		if blocked:
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


## Le joueur se prend la charge ? On cherche sa HurtBox de torse, pas sa
## capsule : c'est le buste visible qui encaisse.
## _hit_player garantit un seul dégât par charge, sans quoi un ennemi qui
## traverse le joueur lui inflige des dégâts à chaque frame de contact.
func _check_charge_hit() -> void:
	if _hit_player:
		return

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
		return


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