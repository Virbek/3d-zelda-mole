@tool
extends StaticBody3D
class_name RelicPedestal

## Piédestal de relique : vieux socle de machine de la raffinerie, posé dans
## une salle avec l'outil « R » de l'éditeur de donjon. Un objet rare flotte
## au-dessus, pris dans un rai de lumière qui tombe du plafond ; par défaut
## c'est le prisme, qui projette un éventail de couleurs sur le sable.
##
## Le joueur s'approche et appuie sur « interact » : même mise en scène que
## le coffre (jeu figé, objet brandi, panneau). L'objet n'est donné qu'une
## fois pour toute la partie, même après une mort.
##
## Construit par script. Origine au sol.

signal taken(item: ItemData)

const PRISM_PATH := "res://data/items/prism.tres"
const BEAM_COLOR := Color(1.0, 0.95, 0.82)

@export var item: ItemData                      ## vide = le prisme
@export var interact_range: float = 1.6         ## distance au bord du socle
@export var float_height: float = 1.85          ## hauteur de l'objet au-dessus du sol
@export var spin_speed: float = 0.6             ## vitesse de rotation (radians par seconde)
@export var prompt_height: float = 2.3
@export var relic_scale: float = 1.8            ## l'objet est plus gros sur son socle que dans la main

## Identifiant unique dans la partie, donné par la salle (sert à ne pas
## redonner l'objet après une mort).
var save_id: String = ""

var is_taken: bool = false
var _relic: Node3D
var _relic_pivot: Node3D
var _spectrum: Node3D
var _beam_mat: StandardMaterial3D
var _light: OmniLight3D
var _prongs: Array[Node3D] = []
var _prompt: InteractPrompt
var _player: Node3D = null
var _t: float = 0.0


func _ready() -> void:
	if item == null and ResourceLoader.exists(PRISM_PATH):
		item = load(PRISM_PATH) as ItemData
	_build()
	if Engine.is_editor_hint():
		return
	_prompt = InteractPrompt.new()
	_prompt.position.y = prompt_height
	add_child(_prompt)
	if save_id != "" and Inventory.is_chest_opened(save_id):
		_set_taken_instant()


func _process(delta: float) -> void:
	_t += delta
	if not is_taken and _relic_pivot != null:
		_relic_pivot.rotation.y += spin_speed * delta
		_relic_pivot.position.y = float_height + sin(_t * 1.6) * 0.06
		_spectrum.rotation.y = _relic_pivot.rotation.y
	if Engine.is_editor_hint() or _prompt == null:
		return
	if _can_take():
		if not _prompt.visible:
			_prompt.show_action("Prendre")
	else:
		_prompt.hide_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not event.is_action_pressed(InteractPrompt.ACTION):
		return
	if _can_take():
		get_viewport().set_input_as_handled()
		_take_sequence()


func _can_take() -> bool:
	if is_taken or item == null or get_tree().paused:
		return false
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null or not _player.has_method("can_interact") or not _player.can_interact():
		return false
	var d := Vector2(_player.global_position.x - global_position.x, _player.global_position.z - global_position.z)
	return d.length() <= interact_range + 0.5


func _take_sequence() -> void:
	is_taken = true
	_prompt.hide_prompt()
	var p: Node3D = _player
	p.begin_interaction(global_position)

	# 1. Les griffes du socle s'ouvrent, l'objet s'éteint sur place
	Sfx.play("chest_open", global_position)
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	for prong in _prongs:
		t.tween_property(prong, "rotation:x", prong.rotation.x - deg_to_rad(35.0), 0.35)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_relic_pivot, "scale", Vector3.ONE * 0.01, 0.3)
	t.tween_property(_spectrum, "scale", Vector3(0.01, 1.0, 0.01), 0.3)
	await get_tree().create_timer(0.35, true, false, true).timeout
	_relic_pivot.visible = false
	_spectrum.visible = false

	# 2. Jeu en pause, le personnage lève l'objet
	get_tree().paused = true
	Sfx.play_ui("item_discover")
	var rig: Node = p.get("rig")
	if rig != null and rig.has_method("present_item"):
		await (rig.present_item(item.build_model()) as Tween).finished

	# 3. Panneau : nom, image, description
	var reveal := ItemReveal.new()
	get_tree().root.add_child(reveal)
	reveal.show_item(item)
	await reveal.closed
	Inventory.add_item(item)
	if save_id != "":
		Inventory.mark_chest_opened(save_id)

	# 4. Retour au jeu : le rai de lumière reste, plus faible, sur un socle vide
	if rig != null and rig.has_method("end_present"):
		await (rig.end_present() as Tween).finished
	var dim := create_tween().set_parallel(true)
	dim.tween_property(_beam_mat, "albedo_color:a", 0.04, 0.6)
	dim.tween_property(_light, "light_energy", 0.3, 0.6)
	get_tree().paused = false
	p.end_interaction()
	taken.emit(item)


## Objet déjà pris lors d'une vie précédente : socle vide, griffes ouvertes.
func _set_taken_instant() -> void:
	is_taken = true
	_relic_pivot.visible = false
	_spectrum.visible = false
	for prong in _prongs:
		prong.rotation.x -= deg_to_rad(35.0)
	_beam_mat.albedo_color.a = 0.04
	_light.light_energy = 0.3


# ---------------------------------------------------------------- CONSTRUCTION

func _build() -> void:
	var B := ToonBuilder

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.55
	shape.height = 1.2
	col.shape = shape
	col.position.y = 0.6
	add_child(col)

	# Socle à gradins, octogonal (vieux support de machine)
	_part(B.cylinder(0.95, 0.16, 8), Vector3(0.0, 0.08, 0.0), B.RUST_DARK)
	_part(B.cylinder(0.72, 0.16, 8), Vector3(0.0, 0.24, 0.0), B.RUST)
	# Sable accumulé contre la base
	var sand := _part(B.cylinder(1.15, 0.06, 10), Vector3(0.25, 0.03, 0.2), Color("#c9a36b"))
	sand.scale = Vector3(1.0, 1.0, 0.7)
	# Fût d'acier, bande de danger, collerette
	_part(B.cylinder(0.32, 0.8, 8), Vector3(0.0, 0.72, 0.0), B.STEEL_DARK)
	_part(B.cylinder(0.34, 0.08, 8), Vector3(0.0, 0.5, 0.0), B.HAZARD)
	_part(B.cylinder(0.5, 0.1, 8), Vector3(0.0, 1.15, 0.0), B.STEEL)
	# Rivets sur la collerette
	for i in 8:
		var a: float = TAU * float(i) / 8.0 + PI / 8.0
		_part(B.box(Vector3(0.06, 0.05, 0.06)), Vector3(sin(a) * 0.45, 1.22, cos(a) * 0.45), B.STEEL_DARK)

	# Trois griffes qui tiennent l'objet sans le toucher
	for i in 3:
		var a: float = TAU * float(i) / 3.0
		var hinge := Node3D.new()
		hinge.position = Vector3(sin(a) * 0.38, 1.2, cos(a) * 0.38)
		hinge.rotation.y = a
		add_child(hinge)
		var claw := _part(B.box(Vector3(0.08, 0.36, 0.08)), Vector3(0.0, 0.16, 0.0), B.RUST, hinge)
		claw.rotation.x = deg_to_rad(-18.0)
		_part(B.box(Vector3(0.1, 0.06, 0.14)), Vector3(0.0, 0.33, -0.08), B.RUST_DARK, hinge)
		_prongs.append(hinge)

	# L'objet qui flotte
	_relic_pivot = Node3D.new()
	_relic_pivot.position.y = float_height
	add_child(_relic_pivot)
	if item != null:
		_relic = item.build_model()
		_relic.scale = Vector3.ONE * relic_scale
		_relic_pivot.add_child(_relic)

	# Rai de lumière qui tombe d'une fente du plafond
	var beam := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 0.85
	cone.height = 4.0
	cone.radial_segments = 12
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = cone
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(BEAM_COLOR, 0.1)
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 2.0
	add_child(beam)

	# Éventail de couleurs projeté au sol par le prisme
	_spectrum = Node3D.new()
	_spectrum.position.y = 0.02
	add_child(_spectrum)
	var is_prism: bool = item != null and item.id == ItemData.PRISM_ID
	if is_prism:
		var n: int = ItemData.SPECTRUM.size()
		for i in n:
			var k: float = float(i) / float(n - 1) - 0.5
			var strip := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(0.22, 2.2)
			strip.mesh = pm
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			sm.albedo_color = Color(ItemData.SPECTRUM[i], 0.45)
			strip.material_override = sm
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var ang: float = k * deg_to_rad(36.0)
			strip.rotation.y = ang
			strip.position = Basis(Vector3.UP, ang) * Vector3(0.0, 0.0, -1.9) + Vector3.UP * 0.005 * float(i)
			_spectrum.add_child(strip)

	_light = OmniLight3D.new()
	_light.light_color = BEAM_COLOR
	_light.light_energy = 1.4
	_light.omni_range = 4.0
	_light.position.y = float_height + 0.3
	add_child(_light)


func _part(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D = self) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.material_override = ToonBuilder.toon_material(color, 0.012, false, true)
	parent.add_child(m)
	return m
