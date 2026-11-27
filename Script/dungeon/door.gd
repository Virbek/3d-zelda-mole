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
##
## GRILLE À SENS UNIQUE (raccourci) : une grille toujours fermée. Une dalle
## de pression est posée au sol d'UN seul côté (plate_cell) ; marcher dessus
## ouvre la grille pour de bon. Depuis l'autre côté, impossible de passer :
## il faut faire le tour.

enum DoorState { OPEN, LOCKED, CLOSED }

signal player_entered(door: DungeonDoor)
signal unlock_requested(door: DungeonDoor)
signal plate_pressed(door: DungeonDoor)

var cell_a := Vector2i.ZERO
var cell_b := Vector2i.ZERO
var axis_x: bool = true          ## true : les deux salles sont côte à côte sur X
var width: float = 2.4
var height: float = 2.8
var depth: float = 1.0           ## épaisseur du mur traversé
var state: DoorState = DoorState.OPEN

## Grille à sens unique : salle où se trouve la dalle. Ignoré si one_way est faux.
var one_way: bool = false
var plate_cell := Vector2i.ZERO
var plate_distance: float = 2.2      ## distance de la dalle au mur, dans la salle
var plate_size: float = 1.3
## La dalle, à enregistrer sur le voile de sa salle (comme les moitiés de porte).
var plate: Node3D = null
var _plate_top: Node3D = null
var _plate_lamp: MeshInstance3D = null
var _plate_used: bool = false
var _plate_area: Area3D = null

var locked_color := Color(0.5, 0.3, 0.12)
var lock_color := Color(1.0, 0.82, 0.2)
var bars_color := Color(0.22, 0.22, 0.25)

## Marquage au sol de chaque côté de la porte : on la repère même quand le
## mur qui la porte est vu de profil. Sa couleur dit son état.
## Lumière qui déborde par la porte, au sol de chaque salle
var spill_length: float = 3.2         ## portée dans chaque salle
var spill_open_color := Color(1.0, 0.7, 0.38)
var spill_locked_color := Color(0.95, 0.22, 0.12)
var spill_closed_color := Color(0.85, 0.2, 0.12)
## Hauteur visible du battant côté salle où la porte est dans le muret du
## bas (vue en coupe) ; la collision garde toute la hauteur.
var ledge_height: float = 0.8

var _blocker: Node3D
var _plates: Array[Node3D] = []
## Moitiés du battant, côté cell_a et côté cell_b (masquées par le voile de leur salle).
var half_a: Node3D
var half_b: Node3D
var _mat: StandardMaterial3D
var _col: CollisionShape3D
var _trigger: Area3D
var _spill_mat: StandardMaterial3D
var _door_light: OmniLight3D
var _panels: Array[Node3D] = []      ## battant blindé (porte verrouillée)
var _bars: Array[Node3D] = []        ## grille (porte fermée pendant un combat)
var _tween: Tween
var _condemned: bool = false
const SpawnFxLib := preload("res://Script/fx/spawn_fx.gd")   ## fermée pour de bon (fin du jeu) : open() ne fait plus rien

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
	_mat = StandardMaterial3D.new()   # conservé pour compatibilité (non affiché)
	var dir := Vector3(cell_b.x - cell_a.x, 0.0, cell_b.y - cell_a.y)
	half_a = _build_half("HalfA", -dir, _half_height(-dir))
	half_b = _build_half("HalfB", dir, _half_height(dir))

	# Pas de marquage peint : la lumière de l'autre salle déborde par la porte
	_spill_mat = StandardMaterial3D.new()
	_spill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spill_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spill_mat.albedo_texture = _spill_texture()
	# Sans ça, le bord opposé du plan reprend le haut du dégradé (ligne lumineuse)
	_spill_mat.texture_repeat = false
	for side: Vector3 in [-dir, dir]:
		_build_spill(side)

	# Petite lumière dans l'embrasure : elle éclaire l'encadrement et le battant
	_door_light = OmniLight3D.new()
	_door_light.omni_range = 3.5
	_door_light.light_energy = 0.6
	_door_light.shadow_enabled = false
	_door_light.position.y = height * 0.6
	add_child(_door_light)

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

	if one_way:
		_build_plate()

	if not Engine.is_editor_hint():
		_prompt = InteractPrompt.new()
		_prompt.position.y = height + 0.4
		add_child(_prompt)

	set_state_instant(state)


## Dalle de pression au sol, dans la salle plate_cell, face à la porte.
## Cadre d'acier, plateau rouillé qui s'enfonce, voyant rouge → vert.
func _build_plate() -> void:
	var dir := Vector3(plate_cell.x - cell_a.x, 0.0, plate_cell.y - cell_a.y)
	if plate_cell == cell_a:
		dir = Vector3(cell_a.x - cell_b.x, 0.0, cell_a.y - cell_b.y)
	dir = dir.normalized()

	plate = Node3D.new()
	plate.name = "Plate"
	plate.position = dir * (depth * 0.5 + plate_distance)
	add_child(plate)

	var s: float = plate_size
	# Cadre : quatre bords d'acier
	var e: float = 0.14
	for side: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var along_x: bool = absf(side.z) > 0.5
		var size := Vector3(s + e * 2.0, 0.1, e) if along_x else Vector3(e, 0.1, s)
		_plain_box(plate, size, side * (s * 0.5 + e * 0.5) + Vector3.UP * 0.05, ToonBuilder.STEEL_DARK)

	# Plateau mobile, avec bandes de danger
	_plate_top = Node3D.new()
	plate.add_child(_plate_top)
	_plain_box(_plate_top, Vector3(s, 0.1, s), Vector3.UP * 0.07, ToonBuilder.RUST)
	for i in 3:
		var off: float = (float(i) - 1.0) * s * 0.3
		_plain_box(_plate_top, Vector3(s * 0.8, 0.02, 0.1), Vector3(0.0, 0.13, off), ToonBuilder.HAZARD)

	# Voyant au milieu : rouge tant que la grille est fermée
	_plate_lamp = _plain_box(_plate_top, Vector3(0.22, 0.05, 0.22), Vector3.UP * 0.15, Color(0.9, 0.15, 0.1))
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.95, 0.2, 0.1)
	_plate_lamp.material_override = lm

	if Engine.is_editor_hint():
		return
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(s, 1.0, s)
	col.shape = shape
	col.position.y = 0.5
	area.add_child(col)
	plate.add_child(area)
	_plate_area = area


## Boîte alignée sur le monde (la dalle n'a pas d'orientation propre).
func _plain_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = ToonBuilder.toon_material(color, 0.008)
	parent.add_child(m)
	return m


## Sondée à chaque frame plutôt que sur body_entered : en combat, la dalle
## ne réagit pas, et un joueur resté dessus jusqu'à la fin du combat doit
## l'enclencher sans avoir à en sortir puis y revenir.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _plate_used or _plate_area == null:
		return
	for body in _plate_area.get_overlapping_bodies():
		if body.is_in_group("player") and not bool(body.get("in_combat")):
			_press_plate()
			return


func _press_plate() -> void:
	_plate_used = true
	var t := create_tween().set_parallel(true)
	t.tween_property(_plate_top, "position:y", -0.06, 0.12)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _plate_lamp != null:
		(_plate_lamp.material_override as StandardMaterial3D).albedo_color = Color(0.3, 1.0, 0.35)
	Sfx.play("door_unlock", plate.global_position)
	plate_pressed.emit(self)


## Vrai pour une grille à sens unique que la dalle n'a pas encore ouverte.
func is_one_way_shut() -> bool:
	return one_way and not _plate_used


## Une moitié de porte, décalée d'un quart d'épaisseur vers side (la salle
## qui la voit). Deux apparences superposées, montrées selon l'état :
##   - battant blindé rouillé (verrouillée) : nervures d'acier, rivets, bande
##     de danger, volant de verrou ;
##   - grille de barreaux (fermée pendant un combat).
## h : hauteur visible (plus basse dans un muret, vue en coupe).
func _build_half(n: String, side: Vector3, h: float) -> Node3D:
	var half := Node3D.new()
	half.name = n
	half.position = side * depth * 0.25
	_blocker.add_child(half)
	var face: Vector3 = side * depth * 0.25   # face visible, côté salle
	var t: float = depth * 0.5                # épaisseur d'une moitié

	# --- Battant blindé ---
	var panel := Node3D.new()
	half.add_child(panel)
	_panels.append(panel)
	_box(panel, Vector3(width, h, t), Vector3(0.0, h * 0.5, 0.0), ToonBuilder.RUST_DARK)
	for y: float in [0.25, 0.55, 0.85]:
		if y * h > h - 0.1:
			continue
		_box(panel, Vector3(width + 0.04, 0.12, t + 0.06), Vector3(0.0, y * h, 0.0), ToonBuilder.STEEL_DARK)
	# Rivets sur la face visible
	for x: float in [-0.42, 0.42]:
		for y: float in [0.25, 0.55, 0.85]:
			if y * h > h - 0.1:
				continue
			_box(panel, Vector3(0.07, 0.07, 0.04), Vector3(x * width, y * h, 0.0) + face + side * 0.02, ToonBuilder.STEEL_LIGHT)
	# Bande de danger en bas
	var stripes: int = 6
	var sw: float = width / float(stripes)
	for i in stripes:
		var c: Color = ToonBuilder.HAZARD if i % 2 == 0 else Color("#1a130d")
		_box(panel, Vector3(sw, 0.18, 0.03), Vector3(-width * 0.5 + sw * (float(i) + 0.5), 0.12, 0.0) + face + side * 0.015, c)
	# Verrou : volant d'acier sur une plaque jaune (seulement si la hauteur le permet)
	if h > 1.4:
		var lock := Node3D.new()
		lock.position = Vector3(0.0, h * 0.55, 0.0) + face + side * 0.03
		panel.add_child(lock)
		_plates.append(lock)
		_box(lock, Vector3(0.55, 0.55, 0.05), Vector3.ZERO, ToonBuilder.HAZARD)
		var wheel := MeshInstance3D.new()
		wheel.mesh = ToonBuilder.cylinder(0.2, 0.06, 10)
		wheel.material_override = ToonBuilder.toon_material(ToonBuilder.STEEL, 0.008)
		wheel.position = side * 0.04
		wheel.rotation = Vector3(PI * 0.5, 0.0, 0.0) if not axis_x else Vector3(0.0, 0.0, PI * 0.5)
		lock.add_child(wheel)

	# --- Grille de barreaux ---
	var bars := Node3D.new()
	half.add_child(bars)
	_bars.append(bars)
	var count: int = 6
	for i in count:
		var x: float = -width * 0.5 + width * (float(i) + 0.5) / float(count)
		_box(bars, Vector3(0.1, h, 0.1), Vector3(x, h * 0.5, 0.0), ToonBuilder.STEEL_DARK)
	_box(bars, Vector3(width, 0.12, 0.14), Vector3(0.0, h * 0.35, 0.0), ToonBuilder.RUST)
	_box(bars, Vector3(width, 0.12, 0.14), Vector3(0.0, h - 0.1, 0.0), ToonBuilder.RUST)
	return half


## Hauteur visible de la moitié tournée vers side : basse si, pour cette
## salle, la porte est dans le muret du bas (la salle est au nord, +Z vers la
## caméra), pleine sinon.
func _half_height(side: Vector3) -> float:
	if not axis_x and side.z < -0.5:
		# side pointe vers la salle nord : pour elle, la porte est au sud
		return minf(ledge_height, height)
	return height


## Une boîte orientée dans le repère de la porte (largeur / hauteur / épaisseur).
func _box(parent: Node3D, size_whd: Vector3, pos_local: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = _oriented(size_whd)
	m.mesh = b
	# pos_local : x le long de la largeur, z dans l'épaisseur
	m.position = _oriented_pos(pos_local)
	m.material_override = ToonBuilder.toon_material(color, 0.008)
	parent.add_child(m)
	return m


func _oriented_pos(v: Vector3) -> Vector3:
	return Vector3(v.z, v.y, v.x) if axis_x else v


## Éventail de lumière au sol, dans la salle tournée vers side.
func _build_spill(side: Vector3) -> void:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	# Le dégradé s'éteint à mi-longueur du plan : l'éventail visible fait
	# spill_length de profondeur, et aucun bord du plan n'est éclairé.
	pm.size = Vector2(width * 2.6, spill_length * 2.0)
	m.mesh = pm
	m.position = side * (depth * 0.5 + spill_length) + Vector3(0.0, 0.02, 0.0)
	# La texture va de la porte (haut, opaque) vers la salle (bas, transparent)
	m.rotation.y = atan2(side.x, side.z)
	m.material_override = _spill_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)


func _spill_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 64
	tex.height = 64
	return tex


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
	if state == DoorState.OPEN or _condemned:
		return
	# Grille (porte de combat) : même « shruuu » qu'à la montée. Porte
	# blindée verrouillée : le grondement lourd.
	var sound: String = "door_close" if state == DoorState.CLOSED else "door_open"
	state = DoorState.OPEN
	Sfx.play(sound, global_position + Vector3.UP * height * 0.5, -2.0 if sound == "door_close" else 0.0)
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_apply_look()
	_tween.tween_property(_blocker, "position:y", -height, 0.35)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_on_opened)


## Condamnée pour de bon : grille fermée, planches clouées en croix et
## éboulis de chaque côté. Plus jamais rouverte (open() l'ignore).
func condemn() -> void:
	if _condemned:
		return
	_condemned = true
	if state != DoorState.CLOSED:
		close()
	var normal: Vector3 = _oriented(Vector3(0.0, 0.0, 1.0))
	var plank := Color("#7a5232")
	var rock := Color("#5e4632")
	var halves: Array = [[half_a, Vector3(cell_a.x - cell_b.x, 0.0, cell_a.y - cell_b.y)], [half_b, Vector3(cell_b.x - cell_a.x, 0.0, cell_b.y - cell_a.y)]]
	for entry in halves:
		var half: Node3D = entry[0]
		var side: Vector3 = entry[1]
		if half == null:
			continue
		# Côté de cette moitié, en « épaisseur » du repère de la porte
		var d: float = signf(side.dot(normal)) * (depth * 0.5 + 0.12)
		for k in [-1.0, 1.0]:
			var p := _box(self, Vector3(width * 1.15, 0.18, 0.06), Vector3(0.0, height * 0.5, d), plank)
			p.rotate(normal, k * 0.6)
			p.reparent(half)
		for i in 6:
			var r := _box(self, Vector3.ONE * randf_range(0.3, 0.6), Vector3(randf_range(-width * 0.5, width * 0.5), randf_range(0.1, 0.4), d + signf(d) * randf_range(0.1, 0.6)), rock)
			r.rotation = Vector3(randf(), randf(), randf())
			r.reparent(half)
	SpawnFxLib.sand_burst(self, Vector3.UP * 0.2, 1.6, 14, 1.0)
	Sfx.play("boss_land", global_position, -2.0)


## Des barreaux sortent du sol pour enfermer le joueur.
func close() -> void:
	if state == DoorState.CLOSED:
		return
	state = DoorState.CLOSED
	Sfx.play("door_close", global_position + Vector3.UP * height * 0.5, -2.0)
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
	Sfx.play("door_deny", global_position + Vector3.UP * height * 0.5)
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
	var c: Color = spill_open_color
	var energy: float = 0.6
	match state:
		DoorState.LOCKED:
			_show(_panels, true)
			_show(_bars, false)
			_set_plates(true)
			c = spill_locked_color
			energy = 0.35
		DoorState.CLOSED:
			_show(_panels, false)
			_show(_bars, true)
			_set_plates(false)
			c = spill_closed_color
			energy = 0.35
		_:
			_show(_panels, false)
			_show(_bars, true)
			_set_plates(false)
	if _spill_mat != null:
		# Verrouillée : lueur rouge plus faible que la lumière chaude d'un passage ouvert
		_spill_mat.albedo_color = Color(c, 0.85 if state == DoorState.OPEN else 0.6)
	if _door_light != null:
		_door_light.light_color = c
		_door_light.light_energy = energy


func _show(nodes: Array[Node3D], on: bool) -> void:
	for n in nodes:
		n.visible = on


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

	var key: Node3D = ItemData.build_key_model(ItemData.KEY_COLOR)
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
