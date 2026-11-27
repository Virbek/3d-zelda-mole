extends CharacterBody3D

## Boss sauteur. Il bondit vers le joueur, reste suspendu pendant qu'une zone
## se remplit au sol, puis s'abat pile quand elle est pleine.
##
## LE CŒUR DU COMBAT : en l'air, il POURSUIT le joueur avec un temps de retard,
## et la zone au sol est son ombre. Au verrouillage (75 % du remplissage) il
## se fige puis s'abat. Rester immobile = se faire écraser ; garder du
## mouvement = le voir tomber juste derrière soi.
##
## DEUX PHASES : en phase 1, un saut par série. Au seuil de vie (moitié par
## défaut), il devient intouchable, bondit au centre de la salle, vire au
## rouge en rugissant, puis attaque en phase 2 : deux sauts par série. La
## règle ne change jamais, seule la densité augmente — le joueur n'a rien de
## nouveau à apprendre, il doit juste mieux exécuter.
##
## En phase 2, avant de bondir, il fait un MINI-SAUT sur place qui libère une
## onde de choc circulaire au sol : il faut la passer en esquivant à travers.
## Ses sauts s'enchaînent aussi plus vite.
##
## REVANCHE (une fois le prisme pris) : la salle le refait apparaître, barre
## pleine. Il attaque d'emblée avec les coups de la phase 2, et chaque
## atterrissage envoie en plus une fissure en ligne droite vers le joueur.
## Au seuil de vie, il devient intouchable, revient au centre et martèle le
## sol : des cailloux tombent alors au hasard dans la salle jusqu'à la fin
## du combat, pendant qu'il reprend les mêmes coups.
##
## Il n'utilise pas le jeton d'attaque : il est seul dans son arène.

enum State { IDLE, WINDUP, AIRBORNE, LANDED, REST, HURT, DEAD, TRANSITION, HOP, FINISH, GRABBED, THROWN }

signal died
## Lancé par la taupe (fin de la revanche), il vient de percuter le mur.
signal crashed
signal health_changed(current: int, maximum: int)
signal phase_changed(phase: int)

@export var player_path: NodePath
@export var blast_scene: PackedScene

@export_group("Vie")
@export var max_health: int = 25
@export var damage_per_hit: int = 1

@export_group("Détection")
## Vrai : attaque le joueur dès son apparition et ne lâche jamais (tous les
## ennemis d'une salle se battent). Faux : portées detect_range / lose_range.
@export var always_aggro: bool = true
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

@export_group("Phase 2")
@export_range(0.05, 0.95) var phase2_threshold: float = 0.5   ## part de vie restante qui déclenche la phase 2
@export var rage_color := Color(0.85, 0.12, 0.08)
@export var transition_hop_time: float = 0.9     ## bond jusqu'au centre
@export var transition_hop_height: float = 4.0
@export var transition_roar_time: float = 1.4    ## sur place, il vire au rouge
## Plus nerveux en phase 2 : pause entre deux sauts d'une série et temps au sol
@export var p2_chain_delay: float = 0.0
@export var p2_land_time: float = 0.28

@export_group("Phase 2 — onde de choc")
@export var shockwave_enabled: bool = true
## false : une onde avant chaque série seulement ; true : avant chaque saut
@export var shockwave_every_jump: bool = false
@export var hop_windup: float = 0.55        ## armé du mini-saut (il se tasse et vire à l'orange)
@export var hop_air_time: float = 0.4       ## durée du mini-saut
@export var hop_height: float = 1.6
@export var hop_recover: float = 0.35       ## pause après l'onde, avant le vrai saut
## L'onde balaie toute la salle : son rayon va jusqu'au coin le plus éloigné.
## Ce rayon ne sert que si la salle est inconnue.
@export var shockwave_radius: float = 9.0
@export var shockwave_speed: float = 10.0   ## m/s : la durée suit la taille de la salle
@export var shockwave_thickness: float = 0.9
@export var shockwave_damage: int = 1

## Centre de la salle (facultatif). Vide : la salle de donjon parente, sinon
## l'endroit où il est apparu.
@export var arena_center_path: NodePath

@export_group("Revanche")
## Mis par la salle quand le boss revient après le prisme.
@export var rematch: bool = false
## Carcasse : le boss déjà vaincu, couché au sol, inerte (posé par la salle
## quand on y revient). Ni ennemi ni barre de vie.
@export var spawn_dead: bool = false
@export var topple_time: float = 0.7        ## durée de la chute en arrière à sa première mort
var _lie_offset_y: float = 0.0

@export_group("Fin de la revanche")
## À 0 PV pendant la revanche, il ne meurt pas : il reste sonné, et la
## commande réaction lance le coup final (la taupe le fait tourner et le
## jette dans le mur de la salle, qui cède).
@export var finish_color := Color(0.25, 1.0, 0.35)
@export var reaction_range: float = 4.5    ## distance d'où le joueur peut l'attraper
@export var whirl_reach: float = 1.9       ## tenu par le bras, à bout de main
@export var throw_time: float = 0.45       ## vol jusqu'au mur
@export var throw_beyond: float = 4.0      ## continue après le mur, puis disparaît
## Point du mur visé par le lancer (monde). Posé par la salle.
var throw_target := Vector3.INF
var whirl_keep_height: bool = true         ## tenu à hauteur du sol, pas des mains
var _saved_layers := Vector3i.ZERO
@export var line_enabled: bool = true
@export var line_speed: float = 12.0        ## m/s : un peu plus vite que le sprint
@export var line_width: float = 1.0
@export var line_damage: int = 1
@export var pound_count: int = 4            ## coups de poing au sol au seuil de vie
@export var pound_period: float = 0.6
@export var rock_interval: float = 0.55     ## un caillou toutes les X secondes
@export var rock_radius: float = 1.1
@export var rock_warn_time: float = 1.1     ## ombre au sol avant l'impact
@export var rock_damage: int = 1
@export var rock_wall_margin: float = 1.2

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
var _phase: int = 0                ## 0 = phase 1, 1 = phase 2
var _home := Vector3.ZERO           ## point d'apparition, centre de repli
var _trans_from := Vector3.ZERO
var _trans_to := Vector3.ZERO
var _trans_landed: bool = false
var _rage_k: float = 0.0
var _hop_done: bool = false          ## l'onde de ce saut est déjà partie
var _hop_landed: bool = false
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
var _rocks_on: bool = false          ## revanche, après le seuil : les cailloux tombent
var _rock_t: float = 0.0
var _rematch_split: bool = false     ## le seuil de la revanche est passé
var _pounds_done: int = 0


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

	# Revanche : directement les coups de la phase 2, déjà rouge
	if rematch:
		_phase = 1
		_rage_k = 1.0

	if spawn_dead:
		remove_from_group("enemy")
		remove_from_group("boss")
		state = State.DEAD
		hurt_box.monitorable = false
		set_collision_layer_value(1, false)
		set_physics_process(false)
		_set_lying(1.0)
		return

	health_changed.emit(health, max_health)
	phase_changed.emit(_phase)


func _physics_process(delta: float) -> void:
	if not _ground_resolved:
		_ground_resolved = true
		_resolve_ground()
		# Pas dans _ready : l'arène place le boss après l'avoir ajouté
		_home = global_position
	_t += delta
	if _rocks_on and state != State.DEAD:
		_rain_rocks(delta)
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
		State.TRANSITION:
			_transition(delta)
		State.HOP:
			_hop(delta)
		State.DEAD, State.FINISH, State.GRABBED, State.THROWN:
			return


## Visuel uniquement : pose des bras, yeux, couleurs de coup.
func _process(delta: float) -> void:
	if _model == null:
		return
	_model.set_tint(_mat.albedo_color, _base_color)
	_model.set_rage(_rage_k, rage_color)
	var pose: String = "rest"
	var k: float = 0.0
	if state == State.FINISH:
		# Sonné : vert vif qui pulse, bras ballants
		_mat.albedo_color = finish_color.lerp(_base_color, 0.25 + 0.25 * sin(_t * 8.0))
	match state:
		State.FINISH, State.GRABBED, State.THROWN:
			pose = "dead"
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
		State.HOP:
			if _t < hop_windup:
				pose = "windup"
				k = _t / maxf(hop_windup, 0.01)
			elif _t < hop_windup + hop_air_time:
				pose = "rise" if _t < hop_windup + hop_air_time * 0.5 else "fall"
				k = (_t - hop_windup) / maxf(hop_air_time, 0.01)
			else:
				pose = "landed"
				k = (_t - hop_windup - hop_air_time) / maxf(hop_recover, 0.01)
		State.TRANSITION:
			if _t < transition_hop_time:
				pose = "hover"
			elif rematch:
				# Martèlement : poings levés, puis abattus sur le sol
				var c: float = fmod(_t - transition_hop_time, pound_period) / pound_period
				if c < 0.55:
					pose = "hover"
				else:
					pose = "fall"
					k = 0.25 + (c - 0.55) / 0.45 * 0.75
			else:
				# Rugissement : bras qui se tassent comme pour un armé, en tremblant
				pose = "windup"
				k = 0.6 + 0.2 * sin(_t * 30.0)
		State.DEAD:
			pose = "dead"
	_model.drive(pose, k, delta)


func _set_state(next: State) -> void:
	state = next
	_t = 0.0


# ---------------------------------------------------------------- ÉTATS

func _idle() -> void:
	if always_aggro or _distance_to_player() < detect_range:
		_jumps_left = jumps_base + _phase
		_start_jump()


func _start_jump() -> void:
	# Phase 2 : le mini-saut et son onde passent avant le vrai saut
	if _phase >= 1 and shockwave_enabled and not _hop_done:
		var first_of_series: bool = _jumps_left >= jumps_base + _phase
		if shockwave_every_jump or first_of_series:
			_start_hop()
			return
	_hop_done = false
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
	if rematch and line_enabled:
		_send_line()


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

	var lt: float = p2_land_time if _phase >= 1 else land_time
	if _t < lt or _landed_resolved:
		return
	_landed_resolved = true

	_jumps_left -= 1
	if _jumps_left > 0:
		var delay: float = p2_chain_delay if _phase >= 1 else chain_delay
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
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
	# Pendant le passage en phase 2, il est intouchable
	if state == State.DEAD or state == State.AIRBORNE or state == State.TRANSITION:
		return

	if state == State.FINISH or state == State.GRABBED or state == State.THROWN:
		return

	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)

	if health <= 0:
		if rematch:
			_enter_finish()
		else:
			_die()
		return

	# Recul visible : plus marqué pour un coup lourd
	_hit_react.play(direction, 0.5 * clampf(float(damage) / float(maxi(damage_per_hit, 1)), 1.0, 2.0))
	Sfx.play("boss_hurt", global_position)

	_flash()
	_check_phase()


## Seuil atteint : passage en phase 2 (une seule fois).
func _check_phase() -> void:
	if rematch:
		if _rematch_split or float(health) > float(max_health) * phase2_threshold:
			return
		_rematch_split = true
		phase_changed.emit(2)
		_start_transition()
		return
	if _phase >= 1:
		return
	if float(health) > float(max_health) * phase2_threshold:
		return
	_phase = 1
	phase_changed.emit(_phase)
	_start_transition()


# ---------------------------------------------------------------- PHASE 2

## Mini-saut : armé (cercle d'alerte), petit bond sur place, onde au contact.
func _start_hop() -> void:
	_set_state(State.HOP)
	_hop_landed = false
	_face_player()
	Sfx.play("boss_windup", global_position)
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_mat, "albedo_color", windup_color, hop_windup * 0.8)


func _hop(_delta: float) -> void:
	velocity = Vector3.ZERO
	if _t < hop_windup:
		var k: float = clampf(_t / maxf(hop_windup, 0.01), 0.0, 1.0)
		_set_mesh_scale(_base_scale * Vector3(1.0 + squash_amount * k * 0.5, 1.0 - squash_amount * k, 1.0 + squash_amount * k * 0.5))
		_face_player()
		return

	var air: float = _t - hop_windup
	if air < hop_air_time:
		_mat.albedo_color = _base_color
		var k: float = air / maxf(hop_air_time, 0.01)
		global_position.y = _ground_y + hop_height * 4.0 * k * (1.0 - k)
		_set_mesh_scale(_base_scale * Vector3(0.9, 1.15, 0.9))
		return

	if not _hop_landed:
		_hop_landed = true
		global_position.y = _ground_y
		_set_mesh_scale(_base_scale * Vector3(1.0 + squash_amount, 1.0 - squash_amount, 1.0 + squash_amount))
		_shake(land_shake * 0.8)
		Sfx.play("boss_land", global_position, 3.0)
		Sfx.play("explosion" if Sfx.sounds.has("explosion") else "boss_land", global_position, 0.0)
		var feet := Vector3(global_position.x, _ground_y - _feet_offset() + 0.05, global_position.z)
		var radius: float = _room_reach(feet)
		ShockwaveRing.spawn(get_tree().current_scene, feet, radius, radius / maxf(shockwave_speed, 0.1), shockwave_thickness, shockwave_damage)
		return

	var rec: float = clampf((air - hop_air_time) / maxf(hop_recover, 0.01), 0.0, 1.0)
	_set_mesh_scale(_base_scale * Vector3(lerpf(1.0 + squash_amount, 1.0, rec), lerpf(1.0 - squash_amount, 1.0, rec), lerpf(1.0 + squash_amount, 1.0, rec)))
	if rec >= 1.0:
		_hop_done = true
		_start_jump()


## Distance entre `from` et le coin de la salle le plus éloigné : l'onde
## couvre toute la pièce, où que le boss se trouve.
func _room_reach(from: Vector3) -> float:
	var parent := get_parent() as Node3D
	if parent == null or not ("room_size" in parent):
		return shockwave_radius
	var size: Vector2 = parent.get("room_size")
	var c: Vector3 = parent.global_position
	var reach: float = 0.0
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			var corner := Vector2(c.x + size.x * sx, c.z + size.y * sz)
			reach = maxf(reach, corner.distance_to(Vector2(from.x, from.z)))
	return reach + shockwave_thickness


## Il coupe tout ce qu'il faisait, devient intouchable et bondit au centre.
func _start_transition() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_mat.albedo_color = _base_color
	if _zone != null and is_instance_valid(_zone):
		_zone.queue_free()
		_zone = null
	_set_mesh_scale(_base_scale)
	_trans_from = global_position
	_trans_to = _arena_center()
	_trans_to.y = _ground_y
	_trans_landed = false
	_pounds_done = 0
	_set_state(State.TRANSITION)
	Sfx.play("boss_jump", global_position, 2.0)
	_shake(0.5)


func _arena_center() -> Vector3:
	if not arena_center_path.is_empty():
		var n := get_node_or_null(arena_center_path) as Node3D
		if n != null:
			return n.global_position
	# Salle de donjon ou arène : leur origine est le centre de la pièce
	var parent := get_parent() as Node3D
	if parent != null and (parent is DungeonRoom or "room_size" in parent):
		return parent.global_position
	return _home


func _transition(_delta: float) -> void:
	velocity = Vector3.ZERO
	if _t < transition_hop_time:
		# Bond en cloche jusqu'au centre
		var k: float = clampf(_t / maxf(transition_hop_time, 0.01), 0.0, 1.0)
		var e: float = k * k * (3.0 - 2.0 * k)
		var p: Vector3 = _trans_from.lerp(_trans_to, e)
		p.y = _ground_y + transition_hop_height * 4.0 * k * (1.0 - k)
		global_position = p
		_face_player()
		return

	if not _trans_landed:
		_trans_landed = true
		global_position = _trans_to
		_set_mesh_scale(_base_scale * Vector3(1.0 + squash_amount, 1.0 - squash_amount, 1.0 + squash_amount))
		Sfx.play("boss_land", global_position, 3.0)
		Sfx.play("boss_phase", global_position, 3.0)
		_shake(land_shake)

	if rematch:
		_pound()
		return

	# Rugissement : il vire progressivement au rouge en tremblant
	var r: float = clampf((_t - transition_hop_time) / maxf(transition_roar_time, 0.01), 0.0, 1.0)
	_rage_k = r
	var wobble: float = sin(_t * 40.0) * 0.04 * (1.0 - r * 0.5)
	_set_mesh_scale(_base_scale * Vector3(1.0 + wobble, 1.0 - wobble, 1.0 + wobble))
	_face_player()
	if int(_t * 10.0) % 3 == 0:
		_shake(0.12)

	if r >= 1.0:
		_rage_k = 1.0
		_set_mesh_scale(_base_scale)
		_jumps_left = jumps_base + _phase
		_start_jump()


# ---------------------------------------------------------------- REVANCHE

## Fissure en ligne droite, de ses pieds vers le joueur.
func _send_line() -> void:
	var feet := Vector3(global_position.x, _ground_y - _feet_offset() + 0.02, global_position.z)
	var dir: Vector3 = player.global_position - feet
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = -global_basis.z
	FissureLine.spawn(get_tree().current_scene, feet, dir, _wall_distance(feet, dir.normalized()), line_speed, line_width, line_damage)


## Distance de `from` au mur de la salle en suivant `dir` : la fissure
## s'arrête au mur au lieu de le traverser.
func _wall_distance(from: Vector3, dir: Vector3) -> float:
	var parent := get_parent() as Node3D
	if parent == null or not ("room_size" in parent):
		return shockwave_radius
	var size: Vector2 = parent.get("room_size")
	var c: Vector3 = parent.global_position
	var best: float = INF
	if absf(dir.x) > 0.001:
		var wx: float = c.x + size.x * 0.5 * signf(dir.x)
		best = minf(best, (wx - from.x) / dir.x)
	if absf(dir.z) > 0.001:
		var wz: float = c.z + size.y * 0.5 * signf(dir.z)
		best = minf(best, (wz - from.z) / dir.z)
	return maxf(best - 0.4, 0.5)


## Au centre, il frappe le sol à plusieurs reprises. Le premier coup fait
## tomber les cailloux ; après le dernier, il reprend ses sauts.
func _pound() -> void:
	var local: float = _t - transition_hop_time
	var c: float = fmod(local, pound_period) / pound_period
	var n: int = int(local / pound_period)
	# Écrasement au moment où les poings touchent le sol
	var squash: float = clampf(1.0 - (c - 0.8) * 5.0, 0.0, 1.0) if c >= 0.8 else 0.0
	_set_mesh_scale(_base_scale * Vector3(1.0 + squash * 0.2, 1.0 - squash * 0.2, 1.0 + squash * 0.2))
	_face_player()
	if n >= _pounds_done and c >= 0.8 and _pounds_done < pound_count:
		_pounds_done += 1
		Sfx.play("boss_land", global_position, 2.0)
		_shake(land_shake * 0.6)
		if not _rocks_on:
			_rocks_on = true
			_rock_t = 0.0
	if local >= pound_period * float(pound_count) + 0.2:
		_set_mesh_scale(_base_scale)
		_jumps_left = jumps_base + _phase
		_start_jump()


func _rain_rocks(delta: float) -> void:
	_rock_t -= delta
	if _rock_t > 0.0:
		return
	_rock_t = rock_interval * randf_range(0.7, 1.3)
	var ground := Vector3(0.0, _ground_y - _feet_offset() + 0.02, 0.0)
	var parent := get_parent() as Node3D
	if parent != null and "room_size" in parent:
		var size: Vector2 = parent.get("room_size")
		var hx: float = size.x * 0.5 - rock_wall_margin
		var hz: float = size.y * 0.5 - rock_wall_margin
		ground.x = parent.global_position.x + randf_range(-hx, hx)
		ground.z = parent.global_position.z + randf_range(-hz, hz)
	else:
		var a: float = randf() * TAU
		var d: float = sqrt(randf()) * shockwave_radius
		ground.x = _home.x + cos(a) * d
		ground.z = _home.z + sin(a) * d
	FallingRock.spawn(get_tree().current_scene, ground, rock_radius, rock_warn_time, rock_damage)


func stun(_duration: float) -> void:
	pass    # un boss ne s'étourdit pas


func is_stunned() -> bool:
	return state == State.FINISH


func get_reaction() -> String:
	return "boss_throw"


## Revanche à 0 PV : il s'effondre à genoux, sonné, en attendant le coup final.
func _enter_finish() -> void:
	_rocks_on = false
	if _zone != null and is_instance_valid(_zone):
		_zone.queue_free()
		_zone = null
	if _hit_react != null:
		_hit_react.stop()
	velocity = Vector3.ZERO
	global_position.y = _ground_y
	_set_mesh_scale(_base_scale)
	_set_state(State.FINISH)
	Sfx.play("stun", global_position, 4.0)
	_shake(0.8)
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_mat.albedo_color = finish_color


## La taupe l'attrape par le bras : plus de collisions, Combat le transporte.
func begin_grab() -> bool:
	if state != State.FINISH:
		return false
	_saved_layers = Vector3i(collision_layer, collision_mask, hurt_box.collision_layer)
	collision_layer = 0
	collision_mask = 0
	hurt_box.collision_layer = 0
	_set_state(State.GRABBED)
	return true


## Lâché sans être lancé (esquive pendant la saisie) : de nouveau sonné.
func end_grab() -> void:
	if state != State.GRABBED:
		return
	collision_layer = _saved_layers.x
	collision_mask = _saved_layers.y
	hurt_box.collision_layer = _saved_layers.z
	global_position.y = _ground_y
	_set_state(State.FINISH)


## Lancé par la taupe : il vole vers throw_target en tournoyant, percute le
## mur (crashed), le traverse et disparaît dans le noir.
func throw_away() -> void:
	if state != State.GRABBED:
		return
	_set_state(State.THROWN)
	var from: Vector3 = global_position
	var to: Vector3 = throw_target if throw_target.is_finite() else from + Vector3.RIGHT * 8.0
	var dir: Vector3 = to - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
	var peak: Vector3 = from.lerp(to, 0.5) + Vector3.UP * 1.5
	var t := create_tween()
	t.tween_property(self, "global_position", peak, throw_time * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", to, throw_time * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(mesh, "rotation:z", -TAU * 1.25, throw_time).as_relative()
	t.tween_callback(func() -> void:
		Sfx.play("boss_death" if Sfx.sounds.has("boss_death") else "enemy_death", global_position, 4.0)
		crashed.emit()
	)
	t.tween_property(self, "global_position", to + dir * throw_beyond + Vector3.DOWN * 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(mesh, "scale", mesh.scale * 0.5, 0.35)
	t.tween_callback(func() -> void:
		_set_state(State.DEAD)
		remove_from_group("enemy")
		remove_from_group("boss")
		died.emit()
		queue_free()
	)


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
	_rocks_on = false
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

	# Première mort : il bascule en arrière et reste couché au sol. Seule la
	# revanche le fait disparaître pour de bon.
	if not rematch:
		d.kill()
		_mat.albedo_color = _base_color
		_lie_down()
		return

	await d.finished
	queue_free()


## Chute en arrière, rebond sur le dos, poussière : puis plus rien ne bouge.
func _lie_down() -> void:
	# Mort en plein armé de saut : le modèle était tassé. On lui rend sa
	# taille, sinon la carcasse au sol reste plus petite.
	if _hit_react != null:
		_hit_react.stop()
	_set_mesh_scale(_base_scale)
	mesh.rotation = Vector3.ZERO
	# Repart de la hauteur actuelle du mesh
	_lie_offset_y = mesh.position.y - _mesh_rest_y
	# Plus un ennemi : la barre de vie se cache, la caméra et les attaques
	# du joueur l'ignorent
	remove_from_group("enemy")
	remove_from_group("boss")
	var t := create_tween()
	# Mort en l'air (saut, bond) : il retombe d'abord au sol
	var height: float = global_position.y - _ground_y
	if height > 0.05:
		t.tween_property(self, "global_position:y", _ground_y, clampf(sqrt(height) * 0.25, 0.15, 0.5))\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(func() -> void:
			Sfx.play("boss_land", global_position, 0.0)
			_shake(0.6)
		)
	for i in 4:
		t.tween_property(_mat, "albedo_color", flash_color, 0.07)
		t.tween_property(_mat, "albedo_color", _base_color, 0.07)
	t.tween_method(_set_lying, 0.0, 1.0, topple_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_on_hit_ground)
	t.tween_method(_set_lying, 1.0, 0.93, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_lying, 0.93, 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _on_hit_ground() -> void:
	Sfx.play("boss_land", global_position, 2.0)
	_shake(1.0)
	var fx: GDScript = load("res://Script/fx/spawn_fx.gd") as GDScript
	var parent := get_parent() as Node3D
	if fx != null and parent != null:
		var back: Vector3 = global_transform.basis.z.normalized()
		var lp: Vector3 = parent.to_local(global_position + back * _lying_length() * 0.6)
		lp.y = parent.to_local(Vector3(0.0, _ground_y, 0.0)).y
		fx.call("sand_burst", parent, lp, 1.8, 18, 1.2)
		fx.call("dust_ring", parent, lp, 4.0)


## Hauteur du modèle (base → sommet), dans le repère du boss.
func _lying_length() -> float:
	return -_mesh_local_bottom * mesh.scale.y * 2.0


## k = 0 debout, 1 couché sur le dos. Le mesh pivote autour de sa base
## (+X : le haut part vers l'arrière, +Z) au lieu de son centre.
func _set_lying(k: float) -> void:
	var a: float = deg_to_rad(88.0) * k
	var half: float = -_mesh_local_bottom * mesh.scale.y
	var base := Vector3(0.0, _mesh_rest_y + _lie_offset_y * (1.0 - k) - half, 0.0)
	var thick: float = half * 0.45   # épaisseur du dos : il repose dessus, pas dans le sol
	mesh.rotation.x = a
	mesh.position = base + Vector3(0.0, half * cos(a) + thick * sin(a), half * sin(a))
