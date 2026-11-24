@tool
extends Node3D
class_name DungeonDoor

## Porte entre deux salles. Elle est partagée : elle n'appartient à aucune
## des deux, c'est le Dungeon qui la crée et qui la pilote.
##
## Elle ne décide de rien elle-même : quand le joueur entre dans sa zone,
## elle émet player_entered et le Dungeon choisit (transition, refus).
## Verrouillée, elle affiche « E : Ouvrir » quand le joueur est devant et
## émet unlock_requested quand il appuie ; le Dungeon dépense la clé.
##
## La zone de détection déborde dans les deux salles : sans ça, le joueur
## bloqué contre une porte verrouillée n'atteindrait jamais la zone.

enum DoorState { OPEN, LOCKED, CLOSED }

signal player_entered(door: DungeonDoor)
signal unlock_requested(door: DungeonDoor)

var cell_a := Vector2i.ZERO
var cell_b := Vector2i.ZERO
var axis_x: bool = true          ## true : les deux salles sont côte à côte sur X
var width: float = 2.4
var height: float = 2.8
var depth: float = 1.0           ## épaisseur du mur traversé
var state: DoorState = DoorState.OPEN

var locked_color := Color(0.5, 0.3, 0.12)
var lock_color := Color(1.0, 0.82, 0.2)
var bars_color := Color(0.22, 0.22, 0.25)

## Marquage au sol de chaque côté de la porte : on la repère même quand le
## mur qui la porte est vu de profil. Sa couleur dit son état.
var mark_length: float = 1.6          ## longueur dans chaque salle
var mark_open_color := Color(0.95, 0.78, 0.35)
var mark_locked_color := Color(0.85, 0.25, 0.2)
var mark_closed_color := Color(0.45, 0.45, 0.5)

var _blocker: Node3D
var _plates: Array[MeshInstance3D] = []
## Moitiés du battant, côté cell_a et côté cell_b (masquées par le voile de leur salle).
var half_a: Node3D
var half_b: Node3D
var _mat: StandardMaterial3D
var _col: CollisionShape3D
var _trigger: Area3D
var _mark_mat: StandardMaterial3D
var _tween: Tween

## Tenu à jour par le Dungeon : change le texte affiché devant la porte.
var has_key: bool = false
var interact_depth: float = 1.4      ## distance devant la porte (de chaque côté) où l'on peut l'ouvrir
var _prompt: InteractPrompt = null
var _unlocking: bool = false


func build() -> void:
	var size := _oriented(Vector3(width, height, depth))

	var body := StaticBody3D.new()
	body.name = "Body"
	_col = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	_col.shape = shape
	_col.position.y = height * 0.5
	body.add_child(_col)
	add_child(body)

	_blocker = Node3D.new()
	_blocker.name = "Blocker"
	add_child(_blocker)

	# Le battant est coupé en deux moitiés, une par salle : chaque salle masque
	# la sienne sous son voile. D'un seul bloc, la moitié côté salle voisine
	# dépasserait du voile (qui n'est qu'une dalle au sol).
	_mat = StandardMaterial3D.new()
	var gold := StandardMaterial3D.new()
	gold.albedo_color = lock_color
	gold.metallic = 0.6
	var dir := Vector3(cell_b.x - cell_a.x, 0.0, cell_b.y - cell_a.y)
	half_a = _build_half("HalfA", -dir, gold)
	half_b = _build_half("HalfB", dir, gold)

	# Le marquage traverse la porte et déborde dans les deux salles. Il reste
	# sous la dalle du voile : la moitié côté salle voilée est donc cachée.
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.emission_enabled = true
	_mark_mat.emission_energy_multiplier = 0.6
	var mark := MeshInstance3D.new()
	mark.name = "FloorMark"
	var mb := BoxMesh.new()
	mb.size = _oriented(Vector3(width * 0.9, 0.03, depth + mark_length * 2.0))
	mark.mesh = mb
	mark.position.y = 0.015
	mark.material_override = _mark_mat
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mark)

	_trigger = Area3D.new()
	_trigger.name = "Trigger"
	_trigger.collision_layer = 0
	_trigger.collision_mask = 1
	var tcol := CollisionShape3D.new()
	var tshape := BoxShape3D.new()
	tshape.size = _oriented(Vector3(width * 0.8, 2.0, depth + 1.2))
	tcol.shape = tshape
	tcol.position.y = 1.0
	_trigger.add_child(tcol)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)

	if not Engine.is_editor_hint():
		_prompt = InteractPrompt.new()
		_prompt.position.y = height + 0.4
		add_child(_prompt)

	set_state_instant(state)


## Une moitié de battant, décalée d'un quart d'épaisseur vers side, avec sa
## plaque de serrure sur la face visible.
func _build_half(n: String, side: Vector3, gold: Material) -> Node3D:
	var half := Node3D.new()
	half.name = n
	half.position = side * depth * 0.25
	_blocker.add_child(half)

	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = _oriented(Vector3(width, height, depth * 0.5))
	m.mesh = b
	m.position.y = height * 0.5
	m.material_override = _mat
	half.add_child(m)

	var plate := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = _oriented(Vector3(0.5, 0.6, 0.06))
	plate.mesh = pb
	plate.position = Vector3(0.0, height * 0.5, 0.0) + side * depth * 0.25
	plate.material_override = gold
	half.add_child(plate)
	_plates.append(plate)
	return half


## Une taille exprimée « largeur / hauteur / épaisseur » vers le repère monde.
func _oriented(v: Vector3) -> Vector3:
	return Vector3(v.z, v.y, v.x) if axis_x else v


func other(cell: Vector2i) -> Vector2i:
	return cell_b if cell == cell_a else cell_a


func connects(cell: Vector2i) -> bool:
	return cell == cell_a or cell == cell_b


func set_state_instant(s: DoorState) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	state = s
	_apply_look()
	var solid: bool = s != DoorState.OPEN
	_blocker.visible = solid
	_blocker.position.y = 0.0 if solid else -height
	_col.set_deferred("disabled", not solid)


## La porte s'enfonce dans le sol, puis laisse passer.
func open() -> void:
	if state == DoorState.OPEN:
		return
	state = DoorState.OPEN
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_apply_look()
	_tween.tween_property(_blocker, "position:y", -height, 0.35)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_on_opened)


## Des barreaux sortent du sol pour enfermer le joueur.
func close() -> void:
	if state == DoorState.CLOSED:
		return
	state = DoorState.CLOSED
	_apply_look()
	_col.set_deferred("disabled", false)
	_blocker.visible = true
	_blocker.position.y = -height
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_blocker, "position:y", 0.0, 0.25)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Refus : pas de clé. Une petite secousse dit « fermé » sans texte.
func deny() -> void:
	if _tween != null and _tween.is_running():
		return
	var axis: String = "position:z" if axis_x else "position:x"
	_tween = create_tween()
	for i in 3:
		_tween.tween_property(_blocker, axis, 0.06, 0.04)
		_tween.tween_property(_blocker, axis, -0.06, 0.04)
	_tween.tween_property(_blocker, axis, 0.0, 0.04)


func _on_opened() -> void:
	_blocker.visible = false
	_col.set_deferred("disabled", true)
	# Le joueur qui attendait contre la porte n'a pas « ré-entré » la zone :
	# on le signale à nouveau pour que le Dungeon le fasse passer.
	for b in _trigger.get_overlapping_bodies():
		if b.is_in_group("player"):
			player_entered.emit(self)
			return


func _apply_look() -> void:
	var mark: Color = mark_open_color
	match state:
		DoorState.LOCKED:
			_mat.albedo_color = locked_color
			_set_plates(true)
			mark = mark_locked_color
		DoorState.CLOSED:
			_mat.albedo_color = bars_color
			_set_plates(false)
			mark = mark_closed_color
		_:
			_mat.albedo_color = bars_color
			_set_plates(false)
	if _mark_mat != null:
		_mark_mat.albedo_color = mark
		_mark_mat.emission = mark


func _set_plates(on: bool) -> void:
	for p in _plates:
		p.visible = on


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_entered.emit(self)


# ---------------------------------------------------------------- SERRURE

func _process(_delta: float) -> void:
	if _prompt == null:
		return
	if state != DoorState.LOCKED or _unlocking or not _player_in_front():
		_prompt.hide_prompt()
	elif has_key:
		if not _prompt.visible or _prompt.modulate != Color.WHITE:
			_prompt.show_action("Ouvrir (clé)")
	else:
		_prompt.show_text("Verrouillée : il faut une clé")


func _unhandled_input(event: InputEvent) -> void:
	if _prompt == null or not event.is_action_pressed(InteractPrompt.ACTION):
		return
	if state == DoorState.LOCKED and not _unlocking and _player_in_front():
		get_viewport().set_input_as_handled()
		unlock_requested.emit(self)


## Joueur assez près de la porte, de l'un ou l'autre côté, et libre d'agir.
func _player_in_front() -> bool:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or (p.has_method("can_interact") and not p.can_interact()):
		return false
	var local: Vector3 = global_transform.affine_inverse() * p.global_position
	var lateral: float = local.z if axis_x else local.x
	var normal: float = local.x if axis_x else local.z
	return absf(lateral) <= width * 0.5 + 0.3 and absf(normal) <= depth * 0.5 + interact_depth


## La clé s'enfonce dans la serrure côté joueur et tourne. N'ouvre pas la
## porte : le Dungeon appelle open() ensuite, une fois le joueur relâché.
func play_unlock(player_pos: Vector3) -> void:
	_unlocking = true
	_prompt.hide_prompt()
	var n: Vector3 = Vector3.RIGHT if axis_x else Vector3.BACK
	var side: float = signf((player_pos - global_position).dot(n))
	if side == 0.0:
		side = 1.0
	var face: Vector3 = global_position + Vector3.UP * height * 0.5 + n * side * (depth * 0.5 + 0.08)

	var key: Node3D = ItemData.build_key_model(lock_color)
	add_child(key)
	key.top_level = true
	key.global_position = face + n * side * 0.7
	# Le modèle a son anneau en haut (+Y) et sa tige vers le bas : on couche
	# la clé pour que la tige pointe vers la serrure.
	var axis: Vector3 = n * side
	var base := Basis(axis.cross(Vector3.UP), axis, Vector3.UP)
	key.global_basis = base
	key.scale = Vector3.ONE * 0.01

	Sfx.play("door_unlock", face)
	var t := create_tween()
	t.tween_property(key, "scale", Vector3.ONE, 0.15)
	t.tween_property(key, "global_position", face + n * side * 0.25, 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Quart de tour dans la serrure
	t.tween_method(func(a: float) -> void: key.global_basis = Basis(axis, a) * base, 0.0, PI * 0.5, 0.2)
	t.tween_interval(0.1)
	t.tween_property(key, "scale", Vector3.ONE * 0.01, 0.12)
	await t.finished
	key.queue_free()
	_set_plates(false)
	_unlocking = false
