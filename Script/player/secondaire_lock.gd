extends Node3D

## Montre qui sera frappé au prochain coup. Sans lock, c'est la seule
## information qui dit au joueur ce que le magnétisme a choisi — sans elle,
## la correction automatique devient de l'aléatoire de son point de vue.

@export var rig_path: NodePath
@export var height: float = 1.4
@export var spin_speed: float = 2.0
@export var follow_speed: float = 18.0

@onready var rig: Node3D = get_node(rig_path)


func _ready() -> void:
	top_level = true

	var m := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.25
	torus.outer_radius = 0.35
	m.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Toujours visible, même à travers un mur ou un ennemi
	mat.no_depth_test = true
	mat.render_priority = 10
	m.material_override = mat

	add_child(m)
	visible = false


func _physics_process(_delta: float) -> void:
	global_position = player_pos() + Vector3.UP * 3.0


func player_pos() -> Vector3:
	return get_node("/root/Node3D/Player").global_position
