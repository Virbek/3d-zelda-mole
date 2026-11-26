extends CharacterBody3D

## Boss sauteur. Il bondit vers le joueur, reste suspendu pendant qu'une zone
## se remplit au sol, puis s'abat pile quand elle est pleine.
##
## LE CŒUR DU COMBAT : en l'air, il POURSUIT le joueur avec un temps de retard,
## et la zone au sol est son ombre. Au verrouillage (75 % du remplissage) il
## se fige puis s'abat. Rester immobile = se faire écraser ; garder du
## mouvement = le voir tomber juste derrière soi.
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

@export_group("Poursuite aérienne")
## Réactivité de la poursuite : plus c'est haut, moins il a de retard.
@export var chase_rate: float = 2.5
## Vitesse horizontale max en l'air. Entre la marche (6) et le sprint (10)
## du joueur : marcher ne suffit pas à le semer, sprinter oui.
@export var chase_max_speed: float = 8.5

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

@export_group("Mort")
@export var death_time: float = 1.2

@export_group("Apparence")
@export var use_robot_model: bool = true   ## remplace la capsule par le robot « poings-blocs »

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
var _landed_resolved: bool = false
var _ground_y: float = 0.0
var _ground_resolved: bool = false
var _mesh_rest_y: float = 0.0
var _mesh_local_bottom: float = 0.0

var _mat: StandardMaterial3D
var _base_color: Color
var _base_scale := Vector3.ONE
var _hit_react: HitReaction = null
var _flash_tween: Tween
var _model: BossRobotModel = null


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
	_hit_react = HitReaction.attach(mesh)
	_mesh_rest_y = mesh.position.y
	if mesh.mesh != null:
		_mesh_local_bottom = mesh.mesh.get_aabb().position.y
	# _ground_y n'est PAS lu ici : l'arène fait add_child() avant de placer le
	# boss, donc sa position n'est pas encore la bonne. Voir _resolve_ground.
	_ground_y = global_position.y

	var base := mesh.get_active_material(0)
	_mat = base.duplicate() if base != null else StandardMaterial3D.new()
	mesh.material_override = _mat
	_base_color = _mat.albedo_color

	# Le robot est rangé sous le mesh : il hérite de l'écrasement, du recul
	# et de l'aplatissement à la mort. Cotes en mètres : on annule l'échelle
	# du mesh, et on pose ses pieds sur le bas de la capsule.
	if use_robot_model:
		_model = BossRobotModel.new()
		mesh.add_child(_model)
		_model.scale = Vector3.ONE / maxf(mesh.scale.y, 0.001)
		_model.position.y = _mesh_local_bottom
		mesh.mesh = null

	health_changed.emit(health, max_health)
	phase_changed.emit(_phase)


func _physics_process(delta: float) -> void:
	if not _ground_resolved:
		_ground_resolved = true
		_resolve_ground()
	_t += delta
	if state != State.AIRBORNE and global_position.y < _ground_y:
		global_position.y = _ground_y
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


## Visuel uniquement : pose des bras, yeux, couleurs de coup.
func _process(delta: float) -> void:
	if _model == null:
		return
	_model.set_tint(_mat.albedo_color, _base_color)
	var pose: String = "rest"
	var k: float = 0.0
	match state:
		State.WINDUP:
			pose = "windup"
			k = _t / maxf(windup_time, 0.01)
		State.AIRBORNE:
			var fall_start: float = maxf(blast_fuse - fall_time, rise_time)
			if _t < rise_time:
				pose = "rise"
			elif _t < fall_start:
				pose = "hover"
			else:
				pose = "fall"
				k = (_t - fall_start) / maxf(fall_time, 0.01)
		State.LANDED:
			pose = "landed"
			k = _t / maxf(land_time, 0.01)
		State.DEAD:
			pose = "dead"
	_model.drive(pose, k, delta)


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
	Sfx.play("boss_windup", global_position)
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
	_set_mesh_scale(_base_scale * Vector3(1.0 + squash_amount * k * 0.6, s, 1.0 + squash_amount * k * 0.6))
	_face_player()

	if _t >= windup_time:
		_launch()


func _launch() -> void:
	_start_pos = global_position
	_land_pos = global_position
	_set_mesh_scale(_base_scale)
	_mat.albedo_color = _base_color

	_spawn_zone()
	_set_state(State.AIRBORNE)
	Sfx.play("boss_jump", global_position, 2.0)


## Il monte, plane, puis s'abat quand la zone est pleine. La durée totale
## en l'air est calée sur le remplissage : les deux se terminent ensemble.
##
## Pendant toute la phase aérienne (montée comprise) il POURSUIT le joueur,
## avec toujours un temps de retard. La zone au sol est son ombre : elle
## le suit, lui, pas le joueur. Un joueur qui s'arrête se fait rattraper et
## écraser ; un joueur qui garde du mouvement le voit tomber juste derrière.
func _airborne(delta: float) -> void:
	var total: float = blast_fuse
	var fall_start: float = maxf(total - fall_time, rise_time)
	var locked: bool = _zone == null or not is_instance_valid(_zone) or _zone.is_locked()

	if _t < fall_start and not locked:
		_chase_player(delta)

	if _t < rise_time:
		# Montée : ralentit en approchant du sommet
		var k: float = _t / rise_time
		var e: float = 1.0 - pow(1.0 - k, 2.0)
		global_position.y = _ground_y + hover_height * e
		_set_mesh_scale(_base_scale * Vector3(0.85, 1.25, 0.85))

	elif _t < fall_start:
		# Suspension : il plane en poursuivant, puis se fige au verrouillage
		global_position.y = _ground_y + hover_height
		_set_mesh_scale(_base_scale)
		_face_player()
		if _zone != null and is_instance_valid(_zone):
			_land_pos = _zone.global_position

	else:
		# Chute : brutale, sur la position verrouillée
		var k: float = clampf((_t - fall_start) / fall_time, 0.0, 1.0)
		var e: float = k * k
		global_position.y = lerpf(_ground_y + hover_height, _ground_y, e)
		global_position.x = lerpf(global_position.x, _land_pos.x, e)
		global_position.z = lerpf(global_position.z, _land_pos.z, e)
		_set_mesh_scale(_base_scale * Vector3(0.8, 1.35, 0.8))

		if k >= 1.0:
			_impact()


func _impact() -> void:
	global_position.y = _ground_y
	_set_mesh_scale(_base_scale * Vector3(1.0 + squash_amount, 1.0 - squash_amount, 1.0 + squash_amount))

	_shake(land_shake)
	Sfx.play("boss_land", global_position, 3.0)
	_landed_resolved = false
	_set_state(State.LANDED)


## Écrasement puis retour à la normale. Court : c'est une pause de lecture,
## pas une fenêtre de punition — celle-ci vient au REST.
func _landed(_delta: float) -> void:
	var k: float = clampf(_t / maxf(land_time, 0.01), 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 3.0)
	_set_mesh_scale(_base_scale * Vector3(
  	lerpf(1.0 + squash_amount, 1.0, e),
  	lerpf(1.0 - squash_amount, 1.0, e),
  	lerpf(1.0 + squash_amount, 1.0, e)
  ))

	if _t < land_time or _landed_resolved:
		return
	_landed_resolved = true

	_jumps_left -= 1
	if _jumps_left > 0:
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
	_zone.global_position = Vector3(global_position.x, _ground_y + 0.02, global_position.z)

	# La zone est l'ombre du boss : elle suit le boss, pas le joueur. C'est
	# donc le retard du boss qui décide où il tombe.
	if _zone.has_method("setup_follow"):
		_zone.setup_follow(self, blast_fuse, blast_lock, blast_radius, blast_damage)


## Poursuite amortie : il vise le joueur mais n'y arrive jamais d'un coup.
## L'amortissement exponentiel crée le retard (proportionnel à la vitesse du
## joueur), le plafond de vitesse empêche les rattrapages instantanés.
func _chase_player(delta: float) -> void:
	var pos := Vector3(global_position.x, 0.0, global_position.z)
	var goal := Vector3(player.global_position.x, 0.0, player.global_position.z)
	var step: Vector3 = (goal - pos) * (1.0 - exp(-chase_rate * delta))
	step = step.limit_length(chase_max_speed * delta)
	global_position.x += step.x
	global_position.z += step.z


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

## Le pivot du boss est au CENTRE de sa capsule, pas à ses pieds. Prendre
## la position d'apparition comme « sol » l'enterrait donc à moitié à chaque
## atterrissage. On mesure le vrai sol sous lui et on y ajoute la distance
## pivot → bas de la capsule de collision.
func _resolve_ground() -> void:
	var feet: float = _feet_offset()
	var space := get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * (feet + 0.5)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 20.0)
	q.exclude = [get_rid()]
	if player != null:
		q.exclude.append(player.get_rid())
	q.collision_mask = 1   # calque du décor
	var hit := space.intersect_ray(q)

	if hit.is_empty():
		_ground_y = global_position.y
		return
	_ground_y = hit.position.y + feet
	if state != State.AIRBORNE:
		global_position.y = _ground_y


## Distance entre le pivot du boss et le bas de sa capsule de collision.
func _feet_offset() -> float:
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null or col.shape == null:
		return 0.0
	var half: float = 0.0
	if col.shape is CapsuleShape3D:
		half = (col.shape as CapsuleShape3D).height * 0.5
	elif col.shape is SphereShape3D:
		half = (col.shape as SphereShape3D).radius
	elif col.shape is BoxShape3D:
		half = (col.shape as BoxShape3D).size.y * 0.5
	return half * col.scale.y - col.position.y


## Le squash s'applique autour du pivot du mesh. Si ce pivot n'est pas à la
## base du modèle, rétrécir mesh.scale.y donne l'impression que le boss
## s'enfonce dans le sol. On compense en ancrant la base visuelle au niveau
## du sol, quelle que soit l'échelle appliquée.
func _set_mesh_scale(s: Vector3) -> void:
	mesh.scale = s
	mesh.position.y = _mesh_rest_y + _mesh_local_bottom * (_base_scale.y - s.y)

func _shake(strength: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("shake"):
		cam.get_parent().shake(strength)


# ---------------------------------------------------------------- DÉGÂTS

## Intouchable en l'air : sinon le joueur le tue en le regardant monter,
## et tout le pattern s'effondre.
func take_hit(direction: Vector3, damage: int = damage_per_hit, _breaks_stun: bool = false) -> void:
	if state == State.DEAD or state == State.AIRBORNE:
		return

	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)

	if health <= 0:
		_die()
		return

	# Recul visible : plus marqué pour un coup lourd
	_hit_react.play(direction, 0.5 * clampf(float(damage) / float(maxi(damage_per_hit, 1)), 1.0, 2.0))
	Sfx.play("boss_hurt", global_position)

	_flash()
	_check_phase()


## Un tiers de vie perdu = un saut de plus par série.
func _check_phase() -> void:
	var lost: float = 1.0 - (float(health) / float(max_health))
	var p: int = clampi(int(lost * 3.0), 0, 2)

	if p == _phase:
		return

	_phase = p
	phase_changed.emit(_phase)
	Sfx.play("boss_phase", global_position, 3.0)

	# Il repart immédiatement : le passage de palier interrompt la respiration
	if state == State.REST:
		_jumps_left = jumps_base + _phase
		_start_jump()

	_shake(0.5)


func stun(_duration: float) -> void:
	pass    # un boss ne s'étourdit pas


func is_stunned() -> bool:
	return false


## Vrai pendant que l'ennemi prépare ou porte une attaque. Lu par le HUD
## pour signaler une menace hors de l'écran.
func is_threatening() -> bool:
	return state == State.WINDUP


func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()

	var step: float = flash_duration / (flash_count * 2)
	_flash_tween = create_tween()
	for i in flash_count:
		_flash_tween.tween_property(_mat, "albedo_color", flash_color, step * 0.4)
		_flash_tween.tween_property(_mat, "albedo_color", _base_color, step * 1.6)


func _die() -> void:
	if _hit_react != null:
		_hit_react.stop()
	# Repli sur le cri d'ennemi tant que boss_death.wav n'existe pas
	Sfx.play("boss_death" if Sfx.sounds.has("boss_death") else "enemy_death", global_position, 4.0)
	_set_state(State.DEAD)
	died.emit()

	if _zone != null and is_instance_valid(_zone):
		_zone.queue_free()

	hurt_box.monitorable = false
	set_collision_layer_value(1, false)


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
