extends Area3D
class_name KeyPickup

## Clé ramassable. Construite par script (pas de .tscn) : la salle qui la fait
## apparaître est prévenue par le signal collected, et c'est le Dungeon qui
## tient le compte des clés.

signal collected

@export var color := ItemData.KEY_COLOR
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

	_visual.add_child(ItemData.build_key_model(color))

	body_entered.connect(_on_body_entered)

	# Petite apparition : elle sort de terre plutôt que de surgir d'un coup
	_visual.scale = Vector3.ONE * 0.01
	create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.35)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	Sfx.play("key_pickup", global_position)
	collected.emit()

	var t := create_tween().set_parallel(true)
	t.tween_property(_visual, "position:y", hover_y + 1.2, 0.3)
	t.tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.3).set_ease(Tween.EASE_IN)
	await t.finished
	queue_free()
