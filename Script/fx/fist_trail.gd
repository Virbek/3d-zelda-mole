class_name FistTrail
extends MeshInstance3D

## Traînée d'air derrière un poing : un ruban qui suit `target`, toujours
## tourné vers la caméra, qui s'affine et s'efface vers la queue.
##
## Le parent (le rig) l'allume pendant un coup avec `emitting`. Les points
## vieillissent avec le temps du jeu : pendant le hit stop, la traînée reste
## figée, comme le reste de l'impact.
##
## Un seul ImmediateMesh reconstruit chaque image, jamais d'instanciation.

@export var lifetime: float = 0.14        ## durée de vie d'un point du ruban
@export var width: float = 0.32           ## largeur à la tête (près du poing)
@export var min_speed: float = 3.0        ## en dessous, le poing ne « fend » pas l'air
@export var min_step: float = 0.04        ## distance minimale entre deux points
@export var color := Color(1.0, 0.97, 0.9, 0.75)
@export var max_points: int = 24
## Saut plus grand que ça en une image (téléportation, replacement) : on
## repart d'un ruban vide plutôt que de tirer un trait à travers l'écran.
@export var max_jump: float = 1.0

var target: Node3D
var emitting: bool = false

var _points: Array[Vector3] = []
var _ages: Array[float] = []
var _last_pos := Vector3.ZERO
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	# Pas de culling sur une boîte englobante qui ne suit pas le ruban
	extra_cull_margin = 16384.0


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var pos: Vector3 = target.global_position

	for i in _ages.size():
		_ages[i] += delta
	while not _ages.is_empty() and _ages[0] >= lifetime:
		_ages.pop_front()
		_points.pop_front()

	if pos.distance_to(_last_pos) > max_jump:
		_points.clear()
		_ages.clear()
	elif emitting and delta > 0.0:
		var speed: float = pos.distance_to(_last_pos) / delta
		if speed >= min_speed and (_points.is_empty() or pos.distance_to(_points[-1]) >= min_step):
			_points.append(pos)
			_ages.append(0.0)
			if _points.size() > max_points:
				_points.pop_front()
				_ages.pop_front()
	_last_pos = pos

	_rebuild(pos)


func _rebuild(head: Vector3) -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos: Vector3 = cam.global_position

	# Le poing lui-même ferme le ruban tant qu'on émet : pas de trou à la tête
	var pts: Array[Vector3] = _points.duplicate()
	var ages: Array[float] = _ages.duplicate()
	if emitting:
		pts.append(head)
		ages.append(0.0)

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var p: Vector3 = pts[i]
		var along: Vector3
		if i < pts.size() - 1:
			along = pts[i + 1] - p
		else:
			along = p - pts[i - 1]
		var to_cam: Vector3 = cam_pos - p
		var side: Vector3 = along.cross(to_cam)
		if side.length_squared() < 0.000001:
			side = Vector3.UP
		side = side.normalized()

		# Fin à la queue, large à la tête ; s'efface en vieillissant
		var life: float = 1.0 - clampf(ages[i] / lifetime, 0.0, 1.0)
		var tail: float = float(i) / float(pts.size() - 1)
		var w: float = width * 0.5 * life * (0.25 + 0.75 * tail)
		var c := Color(color.r, color.g, color.b, color.a * life * (0.3 + 0.7 * tail))
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p + side * w)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p - side * w)
	_mesh.surface_end()
