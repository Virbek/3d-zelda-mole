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
	var p := _player()
	if p != null:
		global_position = p.global_position + Vector3.UP * 3.0


## Par le groupe plutôt qu'un chemin en dur : la racine ne s'appelle pas
## pareil d'une scène à l'autre (TestingScene, DungeonTest...).
func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D
