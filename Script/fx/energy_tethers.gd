extends MeshInstance3D
class_name EnergyTethers

## Filaments électriques orange qui relient le corps de la taupe à ses
## membres flottants (gantelets, bottes). Chaque filament est un arc en
## zigzag qui crépite : ses points intermédiaires sont retirés au hasard
## plusieurs fois par seconde.
##
## Dessiné comme des rubans toujours tournés vers la caméra (une ligne de
## 1 pixel serait invisible vue de haut) : un halo orange large et
## transparent, puis un cœur clair et fin. Additif et non éclairé : il
## brille dans la pénombre du donjon.
##
## Les extrémités sont fournies par des Callable qui renvoient une position
## globale : le rig décide où sont les épaules, hanches, poignets, chevilles.

@export var segments: int = 9
@export var jitter: float = 0.05          ## écart max du zigzag au milieu de l'arc
@export var crackle_rate: float = 18.0     ## nouveaux zigzags par seconde
@export var core_width: float = 0.013
@export var halo_width: float = 0.06
@export var core_color := Color(1.0, 0.62, 0.25, 1.0)
@export var halo_color := Color(1.0, 0.32, 0.04, 0.6)
@export var max_length: float = 3.0       ## au-delà (ragdoll, téléport), le filament se coupe

## [Callable début, Callable fin, PackedVector3Array décalages courants]
var _links: Array = []
var _im := ImmediateMesh.new()
var _crackle_t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	material_override = mat
	_rng.randomize()


## Ajoute un filament entre deux points suivis (Callable -> Vector3 global).
func add_link(from: Callable, to: Callable) -> void:
	var offsets := PackedVector3Array()
	offsets.resize(segments + 1)
	_links.append([from, to, offsets])


func _process(delta: float) -> void:
	_crackle_t += delta
	var reroll: bool = _crackle_t >= 1.0 / maxf(crackle_rate, 0.01)
	if reroll:
		_crackle_t = 0.0

	_im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or _links.is_empty() or not is_visible_in_tree():
		return

	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for link in _links:
		var a: Vector3 = (link[0] as Callable).call()
		var b: Vector3 = (link[1] as Callable).call()
		if a.distance_to(b) > max_length or a.distance_to(b) < 0.02:
			continue
		var offsets: PackedVector3Array = link[2]
		if reroll:
			_reroll(offsets, a, b)
		var pts := PackedVector3Array()
		for i in segments + 1:
			var t: float = float(i) / float(segments)
			pts.append(a.lerp(b, t) + offsets[i])
		_ribbon(pts, cam.global_position, halo_width, halo_color)
		_ribbon(pts, cam.global_position, core_width, core_color)
	_im.surface_end()


## Nouveau zigzag : décalage perpendiculaire, nul aux extrémités, maximal
## au milieu (l'arc reste accroché aux deux bouts).
func _reroll(offsets: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	var dir: Vector3 = (b - a).normalized()
	var p1: Vector3 = dir.cross(Vector3.UP)
	if p1.length() < 0.1:
		p1 = dir.cross(Vector3.RIGHT)
	p1 = p1.normalized()
	var p2: Vector3 = dir.cross(p1).normalized()
	for i in offsets.size():
		var t: float = float(i) / float(offsets.size() - 1)
		var env: float = sin(t * PI)
		offsets[i] = (p1 * _rng.randf_range(-1.0, 1.0) + p2 * _rng.randf_range(-1.0, 1.0)) * jitter * env


## Ruban face caméra le long des points, en triangles.
func _ribbon(pts: PackedVector3Array, cam_pos: Vector3, width: float, color: Color) -> void:
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var seg: Vector3 = p1 - p0
		var to_cam: Vector3 = cam_pos - (p0 + p1) * 0.5
		var side: Vector3 = seg.cross(to_cam).normalized() * width * 0.5
		var v0: Vector3 = p0 - side
		var v1: Vector3 = p0 + side
		var v2: Vector3 = p1 + side
		var v3: Vector3 = p1 - side
		for v: Vector3 in [v0, v1, v2, v0, v2, v3]:
			_im.surface_set_color(color)
			_im.surface_add_vertex(v)
