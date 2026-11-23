@tool
extends StaticBody3D
class_name DungeonChest

## Coffre. S'ouvre quand le joueur le touche ; c'est la salle (son parent)
## qui décide de ce qu'il contient, via le signal opened.

signal opened

@export var body_color := Color(0.45, 0.27, 0.12)
@export var trim_color := Color(1.0, 0.82, 0.2)
@export var size := Vector3(1.3, 0.75, 0.9)

var is_open: bool = false
var _lid_pivot: Node3D


func _ready() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position.y = size.y * 0.5
	add_child(col)

	var wood := StandardMaterial3D.new()
	wood.albedo_color = body_color
	var gold := StandardMaterial3D.new()
	gold.albedo_color = trim_color
	gold.metallic = 0.6

	_add_box(self, size, Vector3(0.0, size.y * 0.5, 0.0), wood)
	_add_box(self, Vector3(size.x + 0.04, 0.08, size.z + 0.04), Vector3(0.0, size.y * 0.75, 0.0), gold)

	# Le couvercle pivote autour de son arête arrière
	_lid_pivot = Node3D.new()
	_lid_pivot.position = Vector3(0.0, size.y, -size.z * 0.5)
	add_child(_lid_pivot)
	var lid_h: float = 0.3
	_add_box(_lid_pivot, Vector3(size.x + 0.06, lid_h, size.z + 0.06), Vector3(0.0, lid_h * 0.5, size.z * 0.5), wood)
	_add_box(_lid_pivot, Vector3(0.2, 0.22, 0.06), Vector3(0.0, 0.0, size.z + 0.04), gold)

	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var acol := CollisionShape3D.new()
	var ashape := BoxShape3D.new()
	ashape.size = size + Vector3(1.0, 1.0, 1.0)
	acol.shape = ashape
	acol.position.y = size.y * 0.5
	area.add_child(acol)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _add_box(parent: Node3D, s: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	m.mesh = b
	m.position = pos
	m.material_override = mat
	parent.add_child(m)


func _on_body_entered(body: Node3D) -> void:
	if is_open or not body.is_in_group("player"):
		return
	open()


func open() -> void:
	if is_open:
		return
	is_open = true
	create_tween().tween_property(_lid_pivot, "rotation:x", -deg_to_rad(110.0), 0.35)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	opened.emit()


## Le coffre déjà ouvert lors d'une visite précédente reste ouvert.
func set_open_instant() -> void:
	is_open = true
	_lid_pivot.rotation.x = -deg_to_rad(110.0)
