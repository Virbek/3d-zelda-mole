extends Node3D

## Couloir de charge affiché au sol, dans le même esprit que blast_zone.gd :
## le remplissage EST le télégraphe. Contrairement à la zone d'explosion,
## rien ne détone ici — les dégâts sont déjà gérés par l'AttackBox du
## chargeur lui-même. Cette zone est purement l'indication visuelle,
## remplacée par le chargeur qui la parcourt une fois le télégraphe fini.
##
## Le contour montre tout de suite le couloir complet et fixe (la charge est
## décidée dès le début du télégraphe, voir enemy.gd::_start_telegraph) ;
## le remplissage grandit depuis le chargeur vers l'avant, pour indiquer le
## temps restant avant qu'il ne fonce pour de vrai.

@export var length: float = 6.0     ## = charge_distance du chargeur
@export var width: float = 1.4
@export var telegraph_time: float = 0.75

@export_group("Couleurs")
@export var fill_color := Color(1.0, 0.35, 0.12, 0.5)
@export var outline_color := Color(1.0, 0.75, 0.2, 0.85)
@export var flash_color := Color(1.0, 0.95, 0.7, 0.95)

@export_group("Ressenti")
@export var pulse_speed: float = 9.0
@export var pulse_start: float = 0.65
@export var fade_time: float = 0.18

var _t: float = 0.0
var _done: bool = false

var _fill: MeshInstance3D
var _outline: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _outline_mat: StandardMaterial3D


func _ready() -> void:
	_build()


## Positionne, oriente et dimensionne le couloir. origin = point de départ
## de la charge, dir = direction horizontale normalisée.
func setup(origin: Vector3, dir: Vector3, dist: float, w: float, tele_time: float) -> void:
	length = maxf(dist, 0.1)
	width = maxf(w, 0.1)
	telegraph_time = tele_time

	global_position = origin
	if dir.length() > 0.01:
		rotation.y = atan2(-dir.x, -dir.z)

	if _outline != null:
		_rebuild_outline()


func _build() -> void:
	_outline = MeshInstance3D.new()
	_outline.mesh = BoxMesh.new()
	_outline_mat = _make_mat(outline_color)
	_outline.material_override = _outline_mat
	_outline.position.y = 0.04
	add_child(_outline)

	_fill = MeshInstance3D.new()
	var fill_box := BoxMesh.new()
	fill_box.size = Vector3(width, 0.02, 0.001)
	_fill.mesh = fill_box
	_fill_mat = _make_mat(fill_color)
	_fill.material_override = _fill_mat
	_fill.position.y = 0.02
	add_child(_fill)

	_rebuild_outline()


func _rebuild_outline() -> void:
	var box: BoxMesh = _outline.mesh
	box.size = Vector3(width, 0.015, length)
	_outline.position.x = 0.0
	_outline.position.z = -length * 0.5


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
	var k: float = clampf(_t / maxf(telegraph_time, 0.01), 0.0, 1.0)

	# Le couloir grandit depuis le chargeur vers l'avant : c'est le temps
	# restant qu'on lit, exactement comme le disque de blast_zone.
	var len_now: float = length * k
	var box: BoxMesh = _fill.mesh
	box.size = Vector3(width, 0.02, maxf(len_now, 0.001))
	_fill.position.z = -len_now * 0.5

	if k >= pulse_start:
		var p: float = (sin(_t * pulse_speed) + 1.0) * 0.5
		_fill_mat.albedo_color = fill_color.lerp(flash_color, p * 0.6)
		_outline_mat.albedo_color = outline_color.lerp(flash_color, p)

	if _t >= telegraph_time:
		_finish()


## Pas de détonation ici : le chargeur prend le relais. On s'efface juste.
func _finish() -> void:
	_done = true

	var t := create_tween().set_parallel(true)
	t.tween_property(_fill_mat, "albedo_color:a", 0.0, fade_time)
	t.tween_property(_outline_mat, "albedo_color:a", 0.0, fade_time)

	await t.finished
	queue_free()