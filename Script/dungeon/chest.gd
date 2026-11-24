@tool
extends StaticBody3D
class_name DungeonChest

## Coffre. Le joueur se place devant et appuie sur « interact » (E au
## clavier, A / croix à la manette) : le couvercle s'ouvre, le jeu se fige,
## le personnage lève l'objet au-dessus de sa tête et un panneau affiche son
## nom et sa description. Une fois le panneau fermé, opened(item) prévient la
## salle, qui décide de l'effet (une clé de plus, par exemple).

signal opened(item: ItemData)

@export var body_color := Color(0.45, 0.27, 0.12)
@export var trim_color := Color(1.0, 0.82, 0.2)
@export var size := Vector3(1.3, 0.75, 0.9)
@export var item: ItemData                    ## vide = une petite clé
@export var interact_range: float = 1.7       ## distance max entre le joueur et le bord du coffre
@export var lid_open_time: float = 0.45
@export var prompt_height: float = 1.7

var is_open: bool = false
var _lid_pivot: Node3D
var _visual: Node3D
var _light: OmniLight3D
var _prompt: InteractPrompt
var _player: Node3D = null


func _ready() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position.y = size.y * 0.5
	add_child(col)

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var wood := StandardMaterial3D.new()
	wood.albedo_color = body_color
	var gold := StandardMaterial3D.new()
	gold.albedo_color = trim_color
	gold.metallic = 0.6

	_add_box(_visual, size, Vector3(0.0, size.y * 0.5, 0.0), wood)
	_add_box(_visual, Vector3(size.x + 0.04, 0.08, size.z + 0.04), Vector3(0.0, size.y * 0.75, 0.0), gold)

	# Le couvercle pivote autour de son arête arrière
	_lid_pivot = Node3D.new()
	_lid_pivot.position = Vector3(0.0, size.y, -size.z * 0.5)
	_visual.add_child(_lid_pivot)
	var lid_h: float = 0.3
	_add_box(_lid_pivot, Vector3(size.x + 0.06, lid_h, size.z + 0.06), Vector3(0.0, lid_h * 0.5, size.z * 0.5), wood)
	_add_box(_lid_pivot, Vector3(0.2, 0.22, 0.06), Vector3(0.0, 0.0, size.z + 0.04), gold)

	if Engine.is_editor_hint():
		return

	if item == null:
		item = ItemData.small_key()

	# Lueur qui sort du coffre à l'ouverture
	_light = OmniLight3D.new()
	_light.position.y = size.y + 0.2
	_light.light_color = item.color
	_light.light_energy = 0.0
	_light.omni_range = 4.0
	add_child(_light)

	_prompt = InteractPrompt.new()
	_prompt.position.y = prompt_height
	add_child(_prompt)


func _add_box(parent: Node3D, s: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	m.mesh = b
	m.position = pos
	m.material_override = mat
	parent.add_child(m)


## Apparition en fin de combat : le coffre sort du sol au lieu de surgir.
func appear() -> void:
	_visual.scale = Vector3.ONE * 0.01
	create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.4)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("spawn", global_position)


# ---------------------------------------------------------------- INTERACTION

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _prompt == null:
		return
	if _can_open():
		if not _prompt.visible:
			_prompt.show_action("Ouvrir")
	else:
		_prompt.hide_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not event.is_action_pressed(InteractPrompt.ACTION):
		return
	if _can_open():
		get_viewport().set_input_as_handled()
		_open_sequence()


func _can_open() -> bool:
	if is_open or get_tree().paused:
		return false
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null or not _player.has_method("can_interact") or not _player.can_interact():
		return false
	# Distance au bord du coffre (pas à son centre) : marche aussi de côté
	var local: Vector3 = global_transform.affine_inverse() * _player.global_position
	var dx: float = maxf(absf(local.x) - size.x * 0.5, 0.0)
	var dz: float = maxf(absf(local.z) - size.z * 0.5, 0.0)
	return Vector2(dx, dz).length() <= interact_range


func _open_sequence() -> void:
	is_open = true
	_prompt.hide_prompt()
	var p: Node3D = _player
	p.begin_interaction(global_position)

	# 1. Le couvercle s'ouvre, une lueur sort (le monde tourne encore)
	Sfx.play("chest_open", global_position)
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	t.tween_property(_lid_pivot, "rotation:x", -deg_to_rad(110.0), lid_open_time)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_light, "light_energy", 3.0, lid_open_time)
	await get_tree().create_timer(lid_open_time, true, false, true).timeout

	# 2. Jeu en pause, le personnage lève l'objet
	get_tree().paused = true
	var rig: Node = p.get("rig")
	if rig != null and rig.has_method("present_item"):
		await (rig.present_item(item.build_model()) as Tween).finished
	Sfx.play_ui("item_get")

	# 3. Panneau : nom, image, description. Attend que le joueur valide.
	var reveal := ItemReveal.new()
	get_tree().root.add_child(reveal)
	reveal.show_item(item)
	await reveal.closed

	# 4. Retour au jeu
	if rig != null and rig.has_method("end_present"):
		await (rig.end_present() as Tween).finished
	create_tween().tween_property(_light, "light_energy", 0.4, 0.5)
	get_tree().paused = false
	p.end_interaction()
	opened.emit(item)


## Le coffre déjà ouvert lors d'une visite précédente reste ouvert.
func set_open_instant() -> void:
	is_open = true
	_lid_pivot.rotation.x = -deg_to_rad(110.0)
