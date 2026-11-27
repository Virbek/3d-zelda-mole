extends Node3D
class_name SlamNeedle

## Aiguille (dard d'abeille) projetée par la réaction « slam » : l'abeille
## fracassée au sol éclate en dards qui filent en étoile autour du joueur.
##
## Elle file en ligne droite au ras du sol, traverse les ennemis (chacun n'est
## touché qu'une fois) et s'arrête contre un mur ou en fin de portée.
## Construite par script : pas de scène à maintenir.

@export var speed: float = 16.0
@export var max_range: float = 9.0
@export var hit_radius: float = 0.8          ## rayon de touche (à l'horizontale)
@export var damage: int = 2
@export var pierce: bool = true              ## traverse les ennemis
@export_flags_3d_physics var wall_mask: int = 1
@export var core_color := Color(1.0, 0.85, 0.35)
@export var glow_color := Color(1.0, 0.45, 0.08)

var _dir := Vector3.FORWARD
var _travelled: float = 0.0
var _hit: Array[Node] = []
var _done: bool = false


## Crée une aiguille et l'ajoute à la scène. `ignore` : ennemis à ne pas
## toucher (l'abeille qui vient d'être fracassée, par exemple).
static func spawn(parent: Node, origin: Vector3, dir: Vector3, dmg: int,
		ignore: Array[Node] = []) -> SlamNeedle:
	var n := SlamNeedle.new()
	n.damage = dmg
	n._dir = Vector3(dir.x, 0.0, dir.z).normalized()
	n._hit = ignore.duplicate()
	parent.add_child(n)
	n.global_position = origin
	return n


func _ready() -> void:
	_build()
	if _dir.length_squared() > 0.001:
		look_at(global_position + _dir, Vector3.UP)


## Un fin cône clair entouré d'un halo additif plus large : lisible de haut
## et dans la pénombre du donjon.
func _build() -> void:
	for layer: Array in [[0.035, 0.7, core_color], [0.09, 0.85, glow_color]]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = layer[0]
		cone.height = layer[1]
		cone.radial_segments = 8
		cone.rings = 1
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = layer[2]
		if layer[2] == glow_color:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color.a = 0.55
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Le cylindre est vertical : on le couche pour que la pointe (haut)
		# regarde vers -Z, l'avant du nœud après look_at.
		mi.rotation.x = -PI * 0.5
		add_child(mi)


func _physics_process(delta: float) -> void:
	if _done:
		return

	var step: float = speed * delta
	var from: Vector3 = global_position
	var to: Vector3 = from + _dir * step

	# Mur : l'aiguille se plante et s'arrête là
	var q := PhysicsRayQueryParameters3D.create(from, to, wall_mask)
	var wall := get_world_3d().direct_space_state.intersect_ray(q)
	if not wall.is_empty():
		global_position = wall.position
		_finish()
		return

	global_position = to
	_travelled += step

	var targets: Array[Node] = get_tree().get_nodes_in_group("enemy")
	# Objets cassables (boulet de sable du bousier...) : touchés aussi
	targets.append_array(get_tree().get_nodes_in_group(&"breakable"))
	for e in targets:
		if not is_instance_valid(e) or e in _hit or not e.has_method("take_hit"):
			continue
		var reach: float = hit_radius
		if e.has_method("is_present"):
			if not e.is_present():
				continue
			# Gros objet : touché dès que le dard frôle sa surface
			reach = hit_radius * 0.5 + float(e.visual_radius())
		var v: Vector3 = (e.visual_center() if e.has_method("visual_center") else (e as Node3D).global_position) - global_position
		v.y = 0.0
		if v.length() > reach:
			continue
		_hit.append(e)
		e.take_hit(_dir, damage)
		if not pierce:
			_finish()
			return

	if _travelled >= max_range:
		_finish()


## Petit rétrécissement plutôt qu'une disparition sèche.
func _finish() -> void:
	_done = true
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ONE * 0.01, 0.12)
	t.tween_callback(queue_free)
