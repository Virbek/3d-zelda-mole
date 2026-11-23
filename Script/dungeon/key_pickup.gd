extends Area3D
class_name KeyPickup

## Clé ramassable. Construite par script (pas de .tscn) : la salle qui la fait
## apparaître est prévenue par le signal collected, et c'est le Dungeon qui
## tient le compte des clés.

signal collected

@export var color := Color(1.0, 0.82, 0.2)
@export var spin_speed: float = 2.5
@export var bob_height: float = 0.15
@export var hover_y: float = 0.8

var _visual: Node3D
var _t: float = 0.0
var _taken: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitorable = false

	var col := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.8
	col.shape = s
	col.position.y = hover_y
	add_child(col)

	_visual = Node3D.new()
	_visual.position.y = hover_y
	add_child(_visual)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.6
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.1
	torus.outer_radius = 0.22
	ring.mesh = torus
	ring.rotation.x = PI * 0.5
	ring.position.y = 0.3
	ring.material_override = mat
	_visual.add_child(ring)

	_add_part(Vector3(0.09, 0.5, 0.09), Vector3(0.0, -0.08, 0.0), mat)
	_add_part(Vector3(0.16, 0.07, 0.09), Vector3(0.1, -0.22, 0.0), mat)
	_add_part(Vector3(0.12, 0.07, 0.09), Vector3(0.08, -0.32, 0.0), mat)

	body_entered.connect(_on_body_entered)

	# Petite apparition : elle sort de terre plutôt que de surgir d'un coup
	_visual.scale = Vector3.ONE * 0.01
	create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.35)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _add_part(size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	_visual.add_child(m)


func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	_visual.rotation.y += spin_speed * delta
	_visual.position.y = hover_y + sin(_t * 3.0) * bob_height


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	set_deferred("monitoring", false)
	collected.emit()

	var t := create_tween().set_parallel(true)
	t.tween_property(_visual, "position:y", hover_y + 1.2, 0.3)
	t.tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.3).set_ease(Tween.EASE_IN)
	await t.finished
	queue_free()
