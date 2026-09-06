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
	visible = false


func _physics_process(delta: float) -> void:
	var t = rig.get_magnet_target()

	if t == null or not is_instance_valid(t):
		visible = false
		return

	if not visible:
		visible = true
		global_position = t.global_position + Vector3.UP * height

	var target: Vector3 = t.global_position + Vector3.UP * height
	global_position = global_position.lerp(target, 1.0 - exp(-follow_speed * delta))
	rotate_y(spin_speed * delta)
