@tool
extends StaticBody3D
class_name DungeonChest

## Coffre : caisse à outils de la raffinerie (acier rouillé riveté, bande de
## danger, loquet à voyant cyan, couvercle qui pivote vers l'arrière).
##
## Le joueur se place devant et appuie sur « interact » (E au clavier, A /
## croix à la manette). La taupe se met face au coffre, pose les deux poings
## sur la lèvre du couvercle, le bascule en arrière, plonge les poings dedans
## et en ressort l'objet à deux mains au-dessus de sa tête ; un panneau
## affiche son nom et sa description. Une fois le panneau fermé, opened(item)
## prévient la salle, qui décide de l'effet (une clé de plus, par exemple).

signal opened(item: ItemData)

@export var body_color := ToonBuilder.RUST
@export var trim_color := ToonBuilder.STEEL     ## renforts, poignées, loquet
@export var size := Vector3(1.3, 0.75, 0.9)
@export var item: ItemData                    ## vide = une petite clé
@export var interact_range: float = 1.7       ## distance max entre le joueur et la face avant
@export var front_side_margin: float = 0.4    ## débord toléré de chaque côté de la face avant
@export var lid_open_time: float = 0.3
@export_group("Animation de la taupe")
@export var approach_time: float = 0.18   ## se place devant le coffre
@export var grab_time: float = 0.15       ## poings sur la lèvre du couvercle
@export var plunge_time: float = 0.35     ## poings plongés dans le coffre
@export var stand_distance: float = 0.8   ## distance entre la face avant et la taupe
@export var prompt_height: float = 1.7

var is_open: bool = false
var _lid_pivot: Node3D
var _visual: Node3D
var _light: OmniLight3D
var _prompt: InteractPrompt
var _player: Node3D = null
var _lamp_mat: StandardMaterial3D

const LID_H := 0.2           ## hauteur du couvercle (inclus dans size.y)
const LID_OPEN_DEG := 110.0
const LIP_X := 0.36          ## écart des poings sur la lèvre du couvercle


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

	_build_visual()

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


func _add_box(parent: Node3D, s: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	m.mesh = b
	m.position = pos
	m.material_override = mat
	parent.add_child(m)
	return m


## Caisse à outils de raffinerie, en primitives et rendu toon.
func _build_visual() -> void:
	var body_h: float = size.y - LID_H
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var rust := ToonBuilder.toon_material(body_color, 0.012)
	var rust_light := ToonBuilder.toon_material(body_color.lightened(0.15), 0.012)
	var steel := ToonBuilder.toon_material(trim_color, 0.01)
	var steel_dark := ToonBuilder.toon_material(ToonBuilder.STEEL_DARK, 0.0)
	var hazard := ToonBuilder.toon_material(ToonBuilder.HAZARD, 0.0)
	var ink := ToonBuilder.toon_material(Color("#20140c"), 0.0)

	# Caisse
	_add_box(_visual, Vector3(size.x, body_h, size.z), Vector3(0.0, body_h * 0.5, 0.0), rust)
	# Intérieur sombre, visible couvercle ouvert (les poings y plongent)
	_add_box(_visual, Vector3(size.x - 0.12, 0.01, size.z - 0.12), Vector3(0.0, body_h + 0.006, 0.0), ink)
	# Renforts d'acier aux quatre coins
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(_visual, Vector3(0.09, body_h + 0.02, 0.09), Vector3(sx * (hx - 0.035), body_h * 0.5, sz * (hz - 0.035)), steel)
	# Bande de danger sur la face avant
	var band_y: float = body_h * 0.45
	_add_box(_visual, Vector3(size.x - 0.18, 0.13, 0.02), Vector3(0.0, band_y, hz + 0.008), hazard)
	var stripes: int = 7
	for i in stripes:
		var x: float = lerpf(-hx + 0.16, hx - 0.16, float(i) / float(stripes - 1))
		var st := _add_box(_visual, Vector3(0.05, 0.11, 0.01), Vector3(x, band_y, hz + 0.022), ink)
		st.rotation.z = deg_to_rad(35.0)
	# Rivets
	for sx in [-1.0, 1.0]:
		for y in [0.08, body_h - 0.08]:
			_add_box(_visual, Vector3.ONE * 0.035, Vector3(sx * (hx - 0.13), y, hz + 0.01), steel_dark)
	# Poignées latérales
	for sx in [-1.0, 1.0]:
		_add_box(_visual, Vector3(0.05, 0.05, 0.34), Vector3(sx * (hx + 0.07), body_h * 0.7, 0.0), steel_dark)
		for sz in [-1.0, 1.0]:
			_add_box(_visual, Vector3(0.08, 0.05, 0.04), Vector3(sx * (hx + 0.035), body_h * 0.7, sz * 0.15), steel_dark)
	# Voyant du loquet : cyan tant que le coffre est fermé
	_add_box(_visual, Vector3(0.2, 0.14, 0.03), Vector3(0.0, body_h - 0.09, hz + 0.012), steel)
	_lamp_mat = ToonBuilder.glow_material(ToonBuilder.SCREEN)
	var lamp := _add_box(_visual, Vector3(0.07, 0.05, 0.02), Vector3(0.0, body_h - 0.1, hz + 0.03), _lamp_mat)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Couvercle : pivote autour de son arête arrière
	_lid_pivot = Node3D.new()
	_lid_pivot.position = Vector3(0.0, body_h, -hz)
	_visual.add_child(_lid_pivot)
	_add_box(_lid_pivot, Vector3(size.x + 0.04, LID_H, size.z + 0.04), Vector3(0.0, LID_H * 0.5, hz), rust_light)
	# Lèvre d'acier à l'avant (là où se posent les poings) et coins
	_add_box(_lid_pivot, Vector3(size.x + 0.06, 0.06, 0.05), Vector3(0.0, 0.03, size.z + 0.02), steel)
	for sx in [-1.0, 1.0]:
		_add_box(_lid_pivot, Vector3(0.1, LID_H + 0.02, 0.1), Vector3(sx * (hx - 0.03), LID_H * 0.5, size.z - 0.03), steel)
	# Patte du loquet, côté couvercle
	_add_box(_lid_pivot, Vector3(0.14, 0.12, 0.04), Vector3(0.0, 0.0, size.z + 0.03), steel_dark)


## Lèvre avant du couvercle, côté side (-1 gauche, 1 droite vu de la taupe), en monde.
func _lip_point(side: float) -> Vector3:
	return _lid_pivot.global_transform * Vector3(side * LIP_X, LID_H * 0.6, size.z + 0.12)


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
	# Seulement de face (+Z local, côté loquet) : de côté ou de derrière,
	# l'animation n'aurait pas de sens (les poings prennent la lèvre avant)
	var local: Vector3 = global_transform.affine_inverse() * _player.global_position
	if local.z < size.z * 0.5:
		return false
	if absf(local.x) > size.x * 0.5 + front_side_margin:
		return false
	return local.z - size.z * 0.5 <= interact_range


func _open_sequence() -> void:
	is_open = true
	_prompt.hide_prompt()
	var p: Node3D = _player
	p.begin_interaction(global_position)
	var rig: Node = p.get("rig")
	var animated: bool = rig != null and rig.has_method("pose_hands")

	# 0. La taupe se place bien en face du coffre
	var front: Vector3 = global_transform * Vector3(0.0, 0.0, size.z * 0.5 + stand_distance)
	front.y = p.global_position.y
	var face: Vector3 = global_position - front
	var go := create_tween().set_parallel(true)
	go.tween_property(p, "global_position", front, approach_time).set_trans(Tween.TRANS_SINE)
	go.tween_property(p, "rotation:y", p.rotation.y + angle_difference(p.rotation.y, atan2(-face.x, -face.z)), approach_time)
	await go.finished

	# 1. Les deux poings sur la lèvre du couvercle, le buste se penche
	if animated:
		rig.pose_begin()
		# Doigts vers le coffre, paumes posées sur le couvercle
		var deep: Vector3 = global_transform * Vector3(0.0, size.y, -size.z)
		await (rig.pose_hands(_lip_point(-1.0), _lip_point(1.0), grab_time, 12.0, 0.06, 0.05, deep, true) as Tween).finished

	# 2. Le couvercle bascule en arrière, les poings le suivent en poussant
	Sfx.play("chest_open", global_position)
	_lamp_mat.albedo_color = ToonBuilder.STEEL_DARK   # loquet ouvert : voyant éteint
	if animated:
		rig.pose_body(-6.0, 0.0, 0.0, lid_open_time)
	var t := create_tween().set_parallel(true)
	t.tween_method(_set_lid_and_hands.bind(rig if animated else null), 0.0, 1.0, lid_open_time)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_light, "light_energy", 3.0, lid_open_time)
	await t.finished

	# 3. Jeu en pause, les poings plongent dans le coffre
	get_tree().paused = true
	# Lancé avant la levée : la montée d'oud accompagne le geste et le gros
	# accord de cuivres tombe juste après que l'objet est brandi.
	Sfx.play_ui("item_discover")
	var inside: Vector3 = global_transform * Vector3(0.0, size.y - LID_H - 0.12, 0.05)
	if animated:
		var right: Vector3 = global_basis.x.normalized()
		# Doigts vers le fond du coffre
		var bottom: Vector3 = global_transform * Vector3(0.0, 0.0, 0.05)
		await (rig.pose_hands(inside - right * 0.17, inside + right * 0.17, plunge_time, 28.0, 0.16, 0.12, bottom) as Tween).finished

	# 4. L'objet ressort à deux mains, au-dessus de la tête
	if animated and rig.has_method("present_item_two_hands"):
		await (rig.present_item_two_hands(item.build_model(), inside) as Tween).finished
	elif rig != null and rig.has_method("present_item"):
		await (rig.present_item(item.build_model()) as Tween).finished

	# 5. Panneau : nom, image, description. Attend que le joueur valide.
	var reveal := ItemReveal.new()
	get_tree().root.add_child(reveal)
	reveal.show_item(item)
	await reveal.closed
	Inventory.add_item(item)

	# 6. Retour au jeu
	if rig != null and rig.has_method("end_present"):
		await (rig.end_present() as Tween).finished
	create_tween().tween_property(_light, "light_energy", 0.4, 0.5)
	get_tree().paused = false
	p.end_interaction()
	opened.emit(item)


## Ouverture du couvercle (k de 0 à 1). Les poings restent sur la lèvre
## jusqu'aux trois quarts, puis la lâchent : le couvercle finit seul.
func _set_lid_and_hands(k: float, rig: Node) -> void:
	_lid_pivot.rotation.x = -deg_to_rad(LID_OPEN_DEG) * k
	if rig != null and k <= 0.75:
		rig.place_hands(_lip_point(-1.0), _lip_point(1.0))


## Le coffre déjà ouvert lors d'une visite précédente reste ouvert.
func set_open_instant() -> void:
	is_open = true
	_lid_pivot.rotation.x = -deg_to_rad(LID_OPEN_DEG)
	if _lamp_mat != null:
		_lamp_mat.albedo_color = ToonBuilder.STEEL_DARK
