class_name SpawnMarker
extends Node3D

## Annonce au sol d'un ennemi sur le point d'apparaître : un anneau se
## resserre pendant qu'un disque se remplit, puis un éclat marque l'arrivée.
## Le joueur voit où et quand l'ennemi arrive — plus d'apparition dans le dos.
##
## Le marqueur ne fait apparaître personne : le spawner attend `duration`
## puis instancie l'ennemi lui-même. Le marqueur se libère seul à la fin.
## Créé une fois par ennemi au début d'une vague, pas à chaque frame.

const COLOR := Color(0.75, 0.5, 1.0)

var _ring: MeshInstance3D
var _disc: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _disc_mat: StandardMaterial3D


## radius : taille au sol de l'ennemi annoncé. duration : temps avant l'apparition.
func play(duration: float, radius: float = 0.7) -> void:
	_build(radius)

	var t := create_tween().set_parallel(true)
	# L'anneau part large et se referme sur le point d'apparition
	_ring.scale = Vector3.ONE * 2.0
	t.tween_property(_ring, "scale", Vector3.ONE, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(_ring_mat, "albedo_color:a", 0.9, duration * 0.4)
	# Le disque se remplit : c'est le compte à rebours
	_disc.scale = Vector3(0.0, 1.0, 0.0)
	t.tween_property(_disc, "scale", Vector3.ONE, duration)
	t.tween_property(_disc_mat, "albedo_color:a", 0.55, duration)

	# Éclat d'arrivée, puis disparition
	var pop := t.chain()
	pop.tween_callback(_on_arrival)
	pop.set_parallel(true)
	pop.tween_property(_disc, "scale", Vector3(1.6, 1.0, 1.6), 0.2)\
		.set_ease(Tween.EASE_OUT)
	pop.tween_property(_ring, "scale", Vector3.ONE * 1.8, 0.2)\
		.set_ease(Tween.EASE_OUT)
	pop.tween_property(_disc_mat, "albedo_color:a", 0.0, 0.2)
	pop.tween_property(_ring_mat, "albedo_color:a", 0.0, 0.2)
	pop.chain().tween_callback(queue_free)


func _on_arrival() -> void:
	_disc_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	Sfx.play("spawn", global_position)


func _build(radius: float) -> void:
	_ring_mat = _make_mat()
	_disc_mat = _make_mat()

	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.85
	torus.outer_radius = radius
	torus.rings = 32
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.position.y = 0.04
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.85
	cyl.bottom_radius = radius * 0.85
	cyl.height = 0.02
	_disc = MeshInstance3D.new()
	_disc.mesh = cyl
	_disc.material_override = _disc_mat
	_disc.position.y = 0.03
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


func _make_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(COLOR, 0.0)
	return m
