extends Node3D

## Zone d'explosion au sol. Le cercle se remplit du centre vers l'extérieur,
## puis détone d'un coup. Le remplissage EST le télégraphe : le joueur lit le
## temps restant et la surface à quitter dans un seul visuel.
##
## Deux modes :
##   - FIXE (bombardier) : posée où l'ennemi est mort, elle ne bouge plus.
##   - SUIVI (boss) : elle colle au joueur pendant les premiers 75 %, puis se
##     verrouille. Fuir tôt ne sert à rien — il faut attendre le verrouillage
##     et sortir dans le dernier quart. C'est ce qui en fait une décision
##     plutôt qu'un simple réflexe.
##
## Les dégâts ne sont appliqués qu'à la détonation. Une zone qui blesse en
## continu punirait le joueur qui traverse, alors qu'on veut punir celui qui reste.

signal detonated

@export var radius: float = 2.6
@export var fuse_time: float = 1.4        ## durée du compte à rebours
@export var damage: int = 2
@export var shake: float = 0.7
@export var hits_enemies: bool = true     ## le souffle touche aussi les ennemis

@export_group("Couleurs")
@export var fill_color := Color(1.0, 0.35, 0.12, 0.55)
@export var ring_color := Color(1.0, 0.75, 0.2, 0.9)
@export var lock_color := Color(1.0, 0.2, 0.1, 1.0)   ## contour au verrouillage
@export var flash_color := Color(1.0, 0.95, 0.7, 0.95)

@export_group("Ressenti")
@export var pulse_speed: float = 9.0      ## vitesse du clignotement final
@export var pulse_start: float = 0.65     ## à partir de quelle fraction ça pulse
@export var blast_time: float = 0.22      ## durée du flash d'explosion
@export var follow_speed: float = 14.0    ## rapidité du suivi en mode boss

var _t: float = 0.0
var _done: bool = false

## Mode suivi
var _target: Node3D = null
var _lock_at: float = 1.0                 ## fraction à laquelle on se fige
var _locked: bool = false
var _ground_y: float = 0.0

var _fill: MeshInstance3D
var _ring: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D


func _ready() -> void:
	_ground_y = global_position.y
	_build()


## Passe la zone en mode suivi. Appelé par le boss juste après l'instanciation.
func setup_follow(target: Node3D, fuse: float, lock_at: float,
		r: float, dmg: int) -> void:
	_target = target
	fuse_time = fuse
	_lock_at = clampf(lock_at, 0.0, 1.0)
	radius = r
	damage = dmg
	hits_enemies = false      # le boss ne se blesse pas lui-même

	if _ring != null:
		_rebuild_sizes()


func is_locked() -> bool:
	return _locked or _target == null


## Deux disques : le contour fixe montre la zone dangereuse dès la première
## frame, le remplissage montre le temps restant. Séparer les deux permet au
## joueur de juger la distance avant même de lire le remplissage.
func _build() -> void:
	_ring = MeshInstance3D.new()
	_ring.mesh = TorusMesh.new()
	_ring_mat = _make_mat(ring_color)
	_ring.material_override = _ring_mat
	_ring.position.y = 0.04
	add_child(_ring)

	_fill = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 32
	_fill.mesh = disc
	_fill_mat = _make_mat(fill_color)
	_fill.material_override = _fill_mat
	_fill.position.y = 0.02
	_fill.scale = Vector3(0.01, 1.0, 0.01)
	add_child(_fill)

	_rebuild_sizes()


func _rebuild_sizes() -> void:
	var t: TorusMesh = _ring.mesh
	t.inner_radius = radius - 0.08
	t.outer_radius = radius


## Non éclairé et sans test de profondeur : la zone doit rester lisible même
## sous un ennemi ou dans l'ombre d'un pilier.
func _make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 5
	return m


func _physics_process(delta: float) -> void:
	if _done:
		return

	_t += delta
	var k: float = clampf(_t / maxf(fuse_time, 0.01), 0.0, 1.0)

	_update_follow(k, delta)

	# Le disque grandit du centre vers le bord
	_fill.scale = Vector3(radius * k, 1.0, radius * k)

	# Clignotement sur la fin : dernier avertissement
	if k >= pulse_start:
		var p: float = (sin(_t * pulse_speed) + 1.0) * 0.5
		_fill_mat.albedo_color = fill_color.lerp(flash_color, p * 0.6)
		if not _locked:
			_ring_mat.albedo_color = ring_color.lerp(flash_color, p)

	if _t >= fuse_time:
		_detonate()


## Suit la cible jusqu'au verrouillage. Le contour vire au rouge à l'instant
## précis où la zone se fige : c'est LE signal qui dit au joueur de partir.
func _update_follow(k: float, delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return

	if k >= _lock_at:
		if not _locked:
			_locked = true
			_ring_mat.albedo_color = lock_color
			_ring.scale = Vector3(1.12, 1.0, 1.12)
			var t := create_tween()
			t.tween_property(_ring, "scale", Vector3.ONE, 0.14)
		return

	var goal := Vector3(_target.global_position.x, _ground_y, _target.global_position.z)
	global_position = global_position.lerp(goal, 1.0 - exp(-follow_speed * delta))


func _detonate() -> void:
	_done = true
	detonated.emit()

	# Un seul test au moment de l'explosion : c'est la position à cet instant
	# qui compte, pas le fait d'être passé dans la zone.
	for area in get_tree().get_nodes_in_group("player_hurt"):
		if not is_instance_valid(area):
			continue
		var v: Vector3 = area.global_position - global_position
		v.y = 0.0
		if v.length() > radius:
			continue
		if area.has_method("take_damage"):
			var dir: Vector3 = v.normalized() if v.length() > 0.01 else Vector3.FORWARD
			area.take_damage(damage, dir)

	if hits_enemies:
		for e in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or not e.has_method("take_hit"):
				continue
			var v: Vector3 = e.global_position - global_position
			v.y = 0.0
			if v.length() > radius or v.length() < 0.01:
				continue
			e.take_hit(v.normalized(), damage)

	_shake()
	_blast()


func _shake() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("shake"):
		cam.get_parent().shake(shake)


func _blast() -> void:
	_fill_mat.albedo_color = flash_color
	_ring_mat.albedo_color = flash_color

	var t := create_tween().set_parallel(true)
	t.tween_property(_fill, "scale", Vector3(radius * 1.25, 1.0, radius * 1.25), blast_time)\
		.set_ease(Tween.EASE_OUT)
	t.tween_property(_fill_mat, "albedo_color:a", 0.0, blast_time)
	t.tween_property(_ring_mat, "albedo_color:a", 0.0, blast_time)
	t.tween_property(_ring, "scale", Vector3(1.25, 1.0, 1.25), blast_time)\
		.set_ease(Tween.EASE_OUT)

	await t.finished
	queue_free()