extends CharacterBody3D

## Boss sauteur. Il bondit vers le joueur, reste suspendu pendant qu'une zone
## se remplit au sol, puis s'abat pile quand elle est pleine.
##
## LE CŒUR DU COMBAT : la zone SUIT le joueur pendant les 75 premiers pour cent
## du remplissage, puis se verrouille. Fuir tôt ne sert donc à rien — il faut
## attendre le verrouillage et sortir dans le dernier quart. C'est ce qui rend
## le combat lisible sans être un simple test de réflexes.
##
## ESCALADE : à chaque tiers de vie perdu, il enchaîne un saut de plus avant
## de se reposer. La règle ne change jamais, seule la densité augmente — le
## joueur n'a rien de nouveau à apprendre, il doit juste mieux exécuter.
##
## Il n'utilise pas le jeton d'attaque : il est seul dans son arène.

enum State { IDLE, WINDUP, AIRBORNE, LANDED, REST, HURT, DEAD }

signal died
signal health_changed(current: int, maximum: int)
signal phase_changed(phase: int)

@export var player_path: NodePath
@export var blast_scene: PackedScene

@export_group("Vie")
@export var max_health: int = 25
@export var damage_per_hit: int = 1

@export_group("Détection")
@export var detect_range: float = 16.0

@export_group("Saut")
@export var windup_time: float = 0.55     ## accroupissement avant le bond
@export var rise_time: float = 0.35       ## montée
@export var hover_height: float = 6.5     ## altitude de suspension
@export var fall_time: float = 0.22       ## chute, volontairement brutale
@export var land_time: float = 0.45       ## temps au sol après l'impact
@export var rest_time: float = 1.8        ## respiration entre deux séries

@export_group("Zone d'impact")
@export var blast_radius: float = 3.4
@export var blast_fuse: float = 1.5       ## durée du remplissage
@export var blast_lock: float = 0.75      ## fraction où la zone se fige
@export var blast_damage: int = 2

@export_group("Escalade")
@export var jumps_base: int = 1           ## sauts par série au départ
@export var chain_delay: float = 0.12     ## pause entre deux sauts d'une série

@export_group("Ressenti")
@export var squash_amount: float = 0.35   ## écrasement à l'armé et à l'impact
@export var land_shake: float = 0.8
@export var flash_color := Color(1.0, 0.15, 0.15)
@export var windup_color := Color(1.0, 0.55, 0.1)
@export var flash_count: int = 3
@export var flash_duration: float = 0.4

@export_group("Butin")
@export var pickup_scene: PackedScene
@export var pickup_count: int = 5         ## il en lâche toujours, il est unique

@export_group("Mort")
@export var death_time: float = 1.2

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var hurt_box: Area3D = $HurtBox

var state: State = State.IDLE
var health: int
var player: CharacterBody3D = null

var _t: float = 0.0
var _phase: int = 0                ## 0, 1, 2 selon les tiers de vie perdus
var _jumps_left: int = 0
var _zone: Node3D = null
var _start_pos := Vector3.ZERO
var _land_pos := Vector3.ZERO
var _ground_y: float = 0.0

var _mat: StandardMaterial3D
var _base_color: Color
var _base_scale := Vector3.ONE
var _flash_tween: Tween


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("boss")

	player = get_node_or_null(player_path)
	if player == null:
		push_warning("%s : player introuvable" % name)
		set_physics_process(false)
		return

	health = max_health
	_base_scale = mesh.scale
	_ground_y = global_position.y

	var base := mesh.get_active_material(0)
	_mat = base.duplicate() if base != null else StandardMaterial3D.new()
	mesh.material_override = _mat
	_base_color = _mat.albedo_color

	health_changed.emit(health, max_health)
	phase_changed.emit(_phase)


func _physics_process(delta: float) -> void:
	_t += delta

	match state:
		State.IDLE:
			_idle()
		State.WINDUP:
			_windup(delta)
		State.AIRBORNE:
			_airborne(delta)
		State.LANDED:
			_landed(delta)
		State.REST:
			_rest(delta)
		State.HURT:
			_hurt(delta)
		State.DEAD:
			return


func _set_state(next: State) -> void:
	state = next
	_t = 0.0


# ---------------------------------------------------------------- ÉTATS

func _idle() -> void:
	if _distance_to_player() < detect_range:
		_jumps_left = jumps_base + _phase
		_start_jump()


func _start_jump() -> void:
	_set_state(State.WINDUP)
	_face_player()

	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_mat, "albedo_color", windup_color, windup_time * 0.8)


## Il se tasse avant de partir. Sans cet armé, le bond serait illisible :
## le joueur n'aurait aucun signal pour anticiper.
func _windup(_delta: float) -> void:
	var k: float = clampf(_t / maxf(windup_time, 0.01), 0.0, 1.0)
	var s: float = 1.0 - squash_amount * k
	mesh.scale = _base_scale * Vector3(1.0 + squash_amount * k * 0.6, s, 1.0 + squash_amount * k * 0.6)
	_face_player()

	if _t >= windup_time:
		_launch()


func _launch() -> void:
	_start_pos = global_position
	_land_pos = global_position
	mesh.scale = _base_scale
	_mat.albedo_color = _base_color

	_spawn_zone()
	_set_state(State.AIRBORNE)


## Il monte, plane, puis s'abat quand la zone est pleine. La durée totale
## en l'air est calée sur le remplissage : les deux se terminent ensemble.
func _airborne(_delta: float) -> void:
	var total: float = blast_fuse
	var fall_start: float = maxf(total - fall_time, rise_time)

	if _t < rise_time:
		# Montée : ralentit en approchant du sommet
		var k: float = _t / rise_time
		var e: float = 1.0 - pow(1.0 - k, 2.0)
		global_position.y = _ground_y + hover_height * e
		mesh.scale = _base_scale * Vector3(0.85, 1.25, 0.85)

	elif _t < fall_start:
		# Suspension : il flotte pendant que le joueur lit la zone
		global_position.y = _ground_y + hover_height
		mesh.scale = _base_scale

		# Tant que la zone n'est pas verrouillée, il se place au-dessus d'elle
		if _zone != null and is_instance_valid(_zone) and not _zone.is_locked():
			_land_pos = _zone.global_position
			global_position.x = _land_pos.x
			global_position.z = _land_pos.z

	else:
		# Chute : brutale, sur la position verrouillée
		var k: float = clampf((_t - fall_start) / fall_time, 0.0, 1.0)
		var e: float = k * k
		global_position.y = lerpf(_ground_y + hover_height, _ground_y, e)
		global_position.x = lerpf(global_position.x, _land_pos.x, e)
		global_position.z = lerpf(global_position.z, _land_pos.z, e)
		mesh.scale = _base_scale * Vector3(0.8, 1.35, 0.8)

		if k >= 1.0:
			_impact()


func _impact() -> void:
	global_position.y = _ground_y
	mesh.scale = _base_scale * Vector3(1.0 + squash_amount, 1.0 - squash_amount, 1.0 + squash_amount)

	_shake(land_shake)
	_set_state(State.LANDED)


## Écrasement puis retour à la normale. Court : c'est une pause de lecture,
## pas une fenêtre de punition — celle-ci vient au REST.
func _landed(_delta: float) -> void:
	var k: float = clampf(_t / maxf(land_time, 0.01), 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 3.0)
	mesh.scale = _base_scale.lerp(_base_scale, e)
	mesh.scale = _base_scale * Vector3(
		lerpf(1.0 + squash_amount, 1.0, e),
		lerpf(1.0 - squash_amount, 1.0, e),
		lerpf(1.0 + squash_amount, 1.0, e)
	)

	if _t < land_time:
		return

	_jumps_left -= 1
	if _jumps_left > 0:
		# Enchaînement immédiat : c'est ce qui rend les phases tardives denses
		await get_tree().create_timer(chain_delay).timeout
		if state == State.LANDED:
			_start_jump()
	else:
		_set_state(State.REST)


## LA fenêtre du joueur. Tout le combat consiste à survivre aux sauts pour
## atteindre ces quelques secondes.
func _rest(_delta: float) -> void:
	if _t >= rest_time:
		_jumps_left = jumps_base + _phase
		_start_jump()


func _hurt(_delta: float) -> void:
	# Court : il ne doit pas être verrouillable en boucle par le joueur
	if _t >= 0.2:
		_set_state(State.REST)


# ---------------------------------------------------------------- ZONE

func _spawn_zone() -> void:
	if blast_scene == null:
		return

	_zone = blast_scene.instantiate()
	get_tree().current_scene.add_child(_zone)
	_zone.global_position = Vector3(player.global_position.x, _ground_y + 0.02, player.global_position.z)

	# La zone se configure elle-même ; le boss ne fait que lui dire qui suivre
	if _zone.has_method("setup_follow"):
		_zone.setup_follow(player, blast_fuse, blast_lock, blast_radius, blast_damage)


# ---------------------------------------------------------------- OUTILS

func _distance_to_player() -> float:
	var v: Vector3 = player.global_position - global_position
	v.y = 0.0
	return v.length()


func _face_player() -> void:
	var v: Vector3 = player.global_position - global_position
	v.y = 0.0
	if v.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-v.x, -v.z), 0.15)


func _shake(strength: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("shake"):
		cam.get_parent().shake(strength)


# ---------------------------------------------------------------- DÉGÂTS

## Intouchable en l'air : sinon le joueur le tue en le regardant monter,
## et tout le pattern s'effondre.
func take_hit(direction: Vector3, damage: int = damage_per_hit) -> void:
	if state == State.DEAD or state == State.AIRBORNE:
		return

	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)

	if health <= 0:
		_die()
		return

	_check_phase()
	_flash()


## Un tiers de vie perdu = un saut de plus par série.
func _check_phase() -> void:
	var lost: float = 1.0 - (float(health) / float(max_health))
	var p: int = clampi(int(lost * 3.0), 0, 2)

	if p == _phase:
		return

	_phase = p
	phase_changed.emit(_phase)

	# Il repart immédiatement : le passage de palier interrompt la respiration
	if state == State.REST:
		_jumps_left = jumps_base + _phase
		_start_jump()

	_shake(0.5)


func stun(_duration: float) -> void:
	pass    # un boss ne s'étourdit pas


func is_stunned() -> bool:
	return false


func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()

	var step: float = flash_duration / (flash_count * 2)
	_flash_tween = create_tween()
	for i in flash_count:
		_flash_tween.tween_property(_mat, "albedo_color", flash_color, step * 0.4)
		_flash_tween.tween_property(_mat, "albedo_color", _base_color, step * 1.6)


func _die() -> void:
	_set_state(State.DEAD)
	died.emit()

	if _zone != null and is_instance_valid(_zone):
		_zone.queue_free()

	hurt_box.monitorable = false
	set_collision_layer_value(1, false)

	_drop_pickups()

	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()

	# Mort lente : un boss ne disparaît pas comme un ennemi ordinaire
	var d := create_tween()
	for i in 5:
		d.tween_property(_mat, "albedo_color", flash_color, 0.08)
		d.tween_property(_mat, "albedo_color", _base_color, 0.08)
	d.set_parallel(true)
	d.tween_property(mesh, "scale", Vector3(1.6, 0.05, 1.6), death_time * 0.5)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	d.tween_property(_mat, "albedo_color:a", 0.0, death_time * 0.5)

	_shake(1.2)
	await d.finished
	queue_free()


func _drop_pickups() -> void:
	if pickup_scene == null:
		return

	for i in pickup_count:
		var p: Node3D = pickup_scene.instantiate()
		get_tree().current_scene.add_child(p)
		p.global_position = global_position + Vector3.UP * 0.8