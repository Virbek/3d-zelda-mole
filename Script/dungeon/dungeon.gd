@tool
extends Node3D
class_name Dungeon

## Donjon en salles de taille identique, décrit par une carte texte.
##
## TOUT le donjon est construit au démarrage (c'est léger : quelques boîtes
## par salle), mais une seule salle est « vivante » : ses ennemis n'existent
## que pendant que le joueur y est. Les autres salles sont recouvertes d'un
## voile noir.
##
## ─── LA CARTE ───────────────────────────────────────────────────────────
## Les salles sont sur les colonnes et lignes PAIRES (0, 2, 4…), les portes
## entre elles sur les positions IMPAIRES :
##
##       B            S  salle de départ (voir start_char)
##       !            .  ou espace : pas de salle
##   C-M-D            -  |  porte ouverte (horizontale / verticale)
##   |   |            =  !  porte verrouillée, il faut une clé
##   S=A K            espace entre deux salles : mur plein
##
## Chaque autre caractère est une salle ; son contenu vient du dictionnaire
## `rooms` (caractère → RoomData). Plusieurs salles peuvent partager le même
## caractère. Un caractère absent du dictionnaire donne une salle vide.
##
## Colonne → axe X, ligne → axe Z. La salle de départ est centrée sur ce nœud.
##
## Dans l'éditeur, le donjon est construit en aperçu (sans ennemis ni voile)
## et se met à jour à chaque modification. Ces nœuds d'aperçu n'ont pas de
## propriétaire : ils ne sont jamais enregistrés dans la scène. Le panneau
## « Donjon » (addons/dungeon_editor) permet d'éditer la carte à la souris.

signal keys_changed(count: int)
signal room_changed(cell: Vector2i)

@export var player_path: NodePath
@export var camera_rig_path: NodePath

@export_group("Carte")
## Une RoomData par case : chaque salle a son propre contenu, indépendant des
## autres. Rempli par le panneau « Donjon » de l'éditeur.
@export var layout_rooms: Dictionary[Vector2i, RoomData] = {}:
	set(v):
		layout_rooms = v
		queue_preview()
## Portes entre deux cases voisines : clé (a.x, a.y, b.x, b.y), valeur
## DOOR_OPEN ou DOOR_LOCKED.
@export var layout_doors: Dictionary[Vector4i, int] = {}:
	set(v):
		layout_doors = v
		queue_preview()
@export var start_cell := Vector2i.ZERO:
	set(v):
		start_cell = v
		queue_preview()

@export_group("Ancien format texte")
## Ancien format, lu seulement si layout_rooms est vide. Le panneau « Donjon »
## le convertit automatiquement en salles indépendantes.
@export_multiline var map: String = "":
	set(v):
		map = v
		queue_preview()
@export var rooms: Dictionary[String, RoomData] = {}:
	set(v):
		rooms = v
		queue_preview()
@export var start_char: String = "S"

@export_group("Dimensions")
@export var room_size := Vector2(20.0, 16.0):
	set(v):
		room_size = v
		queue_preview()
@export var wall_height: float = 4.0:
	set(v):
		wall_height = v
		queue_preview()
@export var wall_thickness: float = 1.0:
	set(v):
		wall_thickness = v
		queue_preview()
@export var door_width: float = 2.6:
	set(v):
		door_width = v
		queue_preview()
@export var door_height: float = 2.8:
	set(v):
		door_height = v
		queue_preview()

@export_group("Transition")
@export var transition_time: float = 0.6
@export var entry_depth: float = 1.8      ## distance parcourue dans la nouvelle salle après la porte
@export var walk_timeout: float = 1.5     ## sécurité : téléporte si le joueur reste coincé

@export_group("Scènes d'ennemis")
@export var charger_scene: PackedScene
@export var shooter_scene: PackedScene
@export var bomber_scene: PackedScene
@export var melee_scene: PackedScene
@export var boss_scene: PackedScene

@export_group("Couleurs")
@export var floor_color := Color(0.55, 0.52, 0.48)
@export var wall_color := Color(0.38, 0.36, 0.34)
@export var pillar_color := Color(0.45, 0.42, 0.40)

const DOOR_OPEN := 1
const DOOR_LOCKED := 2
const OPEN_CHARS := "-|"
const LOCKED_CHARS := "=!"
const EMPTY_CHARS := " ."

var keys: int = 0

var player: CharacterBody3D
var camera_rig: Node3D

var _rooms: Dictionary = {}           ## Vector2i → DungeonRoom
var _doors: Array[DungeonDoor] = []
var _closed: Array[DungeonDoor] = []  ## portes fermées par une salle qui enferme
var _current := Vector2i.ZERO
var _start := Vector2i.ZERO
var _transitioning: bool = false
var _ready_done: bool = false
var _preview_pending: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_preview()
		return
	player = get_node_or_null(player_path)
	camera_rig = get_node_or_null(camera_rig_path)
	if player == null:
		push_warning("Dungeon : player introuvable")
		set_physics_process(false)
		return

	_build()
	keys_changed.emit(keys)
	# Différé : le joueur a peut-être été replacé au checkpoint dans son _ready
	_enter_first_room.call_deferred()


# ---------------------------------------------------------------- CONSTRUCTION

## Lit la carte texte. Renvoie { "rooms": {Vector2i: lettre},
## "links": [[cell_a, cell_b, verrouillée], ...] }. Partagé avec l'éditeur.
static func parse_map(text: String) -> Dictionary:
	var lines: PackedStringArray = text.split("\n")
	var room_chars: Dictionary = {}
	var links: Array = []
	for r in lines.size():
		var line: String = lines[r]
		for c in line.length():
			var ch: String = line[c]
			if ch in EMPTY_CHARS:
				continue
			var even_r: bool = r % 2 == 0
			var even_c: bool = c % 2 == 0
			if even_r and even_c:
				room_chars[Vector2i(c / 2, r / 2)] = ch
				continue
			var a := Vector2i.ZERO
			var b := Vector2i.ZERO
			if even_r and not even_c:
				a = Vector2i((c - 1) / 2, r / 2)
				b = Vector2i((c + 1) / 2, r / 2)
			elif not even_r and even_c:
				a = Vector2i(c / 2, (r - 1) / 2)
				b = Vector2i(c / 2, (r + 1) / 2)
			else:
				continue
			if ch in OPEN_CHARS:
				links.append([a, b, false])
			elif ch in LOCKED_CHARS:
				links.append([a, b, true])
			else:
				push_warning("Dungeon : caractère '%s' ligne %d colonne %d ignoré (porte attendue : - | = !)" % [ch, r + 1, c + 1])
	return {"rooms": room_chars, "links": links}


## Écrit la carte texte à partir des salles et des portes (inverse de parse_map).
## links : [[cell_a, cell_b, verrouillée], ...] entre salles voisines.
static func compose_map(room_chars: Dictionary, links: Array) -> String:
	if room_chars.is_empty():
		return ""
	var mn := Vector2i(1 << 20, 1 << 20)
	var mx := Vector2i(-(1 << 20), -(1 << 20))
	for cell in room_chars:
		mn = Vector2i(mini(mn.x, cell.x), mini(mn.y, cell.y))
		mx = Vector2i(maxi(mx.x, cell.x), maxi(mx.y, cell.y))
	var w: int = (mx.x - mn.x) * 2 + 1
	var h: int = (mx.y - mn.y) * 2 + 1
	var grid: Array = []
	for r in h:
		var row: PackedStringArray = []
		row.resize(w)
		for c in w:
			# Les cases de salle vides prennent un point : jamais d'espace en
			# début de ligne, qui serait facile à perdre en éditant à la main.
			row[c] = "." if (r % 2 == 0 and c % 2 == 0) else " "
		grid.append(row)
	for cell in room_chars:
		var p: Vector2i = (cell - mn) * 2
		grid[p.y][p.x] = room_chars[cell]
	for l in links:
		var a: Vector2i = l[0]
		var b: Vector2i = l[1]
		var p: Vector2i = (a - mn) + (b - mn)   # = position du milieu, en coordonnées texte
		var horizontal: bool = a.y == b.y
		var ch: String
		if l[2]:
			ch = "=" if horizontal else "!"
		else:
			ch = "-" if horizontal else "|"
		grid[p.y][p.x] = ch
	var out: PackedStringArray = []
	for row in grid:
		out.append("".join(row).strip_edges(false, true))
	return "\n".join(out)


## Le donjon sous une forme unique, quel que soit le format enregistré :
## { "cells": {Vector2i: RoomData ou null}, "links": [[a, b, verrouillée]],
## "start": Vector2i }.
func get_model() -> Dictionary:
	var cells: Dictionary = {}
	var links: Array = []
	var start := Vector2i.ZERO
	if not layout_rooms.is_empty():
		for cell in layout_rooms:
			cells[cell] = layout_rooms[cell]
		for key in layout_doors:
			var k: Vector4i = key
			links.append([Vector2i(k.x, k.y), Vector2i(k.z, k.w), layout_doors[key] == DOOR_LOCKED])
		start = start_cell if cells.has(start_cell) else cells.keys()[0]
	else:
		var parsed: Dictionary = parse_map(map)
		var chars: Dictionary = parsed["rooms"]
		links = parsed["links"]
		for cell in chars:
			cells[cell] = rooms.get(chars[cell])
		if not chars.is_empty():
			start = chars.keys()[0]
			for cell in chars:
				if chars[cell] == start_char:
					start = cell
					break
	return {"cells": cells, "links": links, "start": start}


func _build() -> void:
	var model: Dictionary = get_model()
	var room_chars: Dictionary = model["cells"]
	var links: Array = model["links"]

	if room_chars.is_empty():
		if not Engine.is_editor_hint():
			push_warning("Dungeon : la carte ne contient aucune salle")
		return

	_start = model["start"]

	# Les portes d'abord : chaque salle doit savoir sur quels murs percer.
	var room_doors: Dictionary = {}   # Vector2i → { Vector2i dir → true }
	var valid_links: Array = []
	for l in links:
		var a: Vector2i = l[0]
		var b: Vector2i = l[1]
		if not room_chars.has(a) or not room_chars.has(b):
			push_warning("Dungeon : porte entre %s et %s mais une des salles manque" % [a, b])
			continue
		valid_links.append(l)
		if not room_doors.has(a):
			room_doors[a] = {}
		if not room_doors.has(b):
			room_doors[b] = {}
		room_doors[a][b - a] = true
		room_doors[b][a - b] = true

	var scenes: Dictionary = {
		"charger": charger_scene,
		"shooter": shooter_scene,
		"bomber": bomber_scene,
		"melee": melee_scene,
		"boss": boss_scene,
	}

	for cell in room_chars:
		var room := DungeonRoom.new()
		room.name = "Room_%d_%d" % [cell.x, cell.y]
		room.data = room_chars[cell]
		room.cell = cell
		room.room_size = room_size
		room.wall_height = wall_height
		room.wall_thickness = wall_thickness
		room.door_width = door_width
		room.door_height = door_height
		room.doors = room_doors.get(cell, {})
		room.player = player
		room.scenes = scenes
		room.floor_color = floor_color
		room.wall_color = wall_color
		room.pillar_color = pillar_color
		room.position = _cell_to_local(cell)
		add_child(room)
		room.build()
		room.cleared.connect(_on_room_cleared)
		room.key_collected.connect(_on_key_collected)
		_rooms[cell] = room

	for l in valid_links:
		var a: Vector2i = l[0]
		var b: Vector2i = l[1]
		var door := DungeonDoor.new()
		door.name = "Door_%d_%d__%d_%d" % [a.x, a.y, b.x, b.y]
		door.cell_a = a
		door.cell_b = b
		door.axis_x = a.y == b.y
		door.width = door_width
		door.height = door_height
		door.depth = wall_thickness
		door.state = DungeonDoor.DoorState.LOCKED if l[2] else DungeonDoor.DoorState.OPEN
		door.position = (_cell_to_local(a) + _cell_to_local(b)) * 0.5
		add_child(door)
		door.build()
		(_rooms[a] as DungeonRoom).add_veil_piece(door.half_a)
		(_rooms[b] as DungeonRoom).add_veil_piece(door.half_b)
		door.player_entered.connect(_on_door_entered)
		_doors.append(door)


## Aperçu dans l'éditeur : reconstruit tout, une fois par frame au plus.
func queue_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or _preview_pending:
		return
	_preview_pending = true
	_rebuild_preview.call_deferred()


func _rebuild_preview() -> void:
	_preview_pending = false
	if not is_inside_tree():
		return
	for child in get_children():
		# Les nœuds d'aperçu n'ont pas de propriétaire : ceux ajoutés à la
		# main dans la scène en ont un, on n'y touche pas.
		if child.owner == null:
			remove_child(child)
			child.queue_free()
	_rooms.clear()
	_doors.clear()
	_build()
	for cell in _rooms:
		(_rooms[cell] as DungeonRoom).set_veil(0.0, Vector3.RIGHT)


func _cell_to_local(cell: Vector2i) -> Vector3:
	var sp: Vector2 = room_size + Vector2(wall_thickness, wall_thickness)
	var d: Vector2i = cell - _start
	return Vector3(d.x * sp.x, 0.0, d.y * sp.y)


func _room_at(p: Vector3) -> Variant:
	for cell in _rooms:
		if (_rooms[cell] as DungeonRoom).contains(p):
			return cell
	return null


# ---------------------------------------------------------------- SALLE COURANTE

func _enter_first_room() -> void:
	if _rooms.is_empty():
		return
	var start_room: DungeonRoom = _rooms[_start]
	if not Checkpoints.has_checkpoint:
		Checkpoints.set_checkpoint(start_room.global_position + Vector3.UP)

	var found: Variant = _room_at(player.global_position)
	if found == null:
		player.global_position = start_room.global_position + Vector3.UP
		found = _start
	_snap_to(found)
	_ready_done = true


## Changement sans animation : premier affichage, réapparition, téléport.
func _snap_to(cell: Vector2i) -> void:
	if _rooms.has(_current) and _current != cell:
		(_rooms[_current] as DungeonRoom).deactivate()
	_reopen_closed()
	_current = cell
	for c in _rooms:
		(_rooms[c] as DungeonRoom).set_veil(0.0 if c == cell else 1.0, Vector3.RIGHT)
	var room: DungeonRoom = _rooms[cell]
	if camera_rig != null and camera_rig.has_method("set_bounds"):
		camera_rig.set_bounds(room.get_bounds(), true)
	room_changed.emit(cell)
	_activate(room)


func _activate(room: DungeonRoom) -> void:
	var alive: int = room.activate(player.global_position)
	# Toute salle où il y a un combat enferme le joueur jusqu'à la fin des
	# vagues. Les portes à clé, elles, restent simplement verrouillées.
	if alive > 0:
		for d in _doors:
			if d.connects(room.cell) and d.state == DungeonDoor.DoorState.OPEN:
				d.close()
				_closed.append(d)


func _reopen_closed() -> void:
	for d in _closed:
		d.open()
	_closed.clear()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not _ready_done or _transitioning:
		return
	# Filet de sécurité : si le joueur se retrouve ailleurs sans passer par une
	# porte (réapparition, téléport, bug de collision), on suit sans animation.
	var room: DungeonRoom = _rooms.get(_current)
	if room != null and room.contains(player.global_position):
		return
	var found: Variant = _room_at(player.global_position)
	if found != null:
		_snap_to(found)


# ---------------------------------------------------------------- PORTES

func _on_door_entered(door: DungeonDoor) -> void:
	if _transitioning or not _ready_done or not door.connects(_current):
		return

	match door.state:
		DungeonDoor.DoorState.LOCKED:
			if keys > 0:
				keys -= 1
				keys_changed.emit(keys)
				door.open()   # la porte re-signalera le joueur une fois ouverte
			else:
				door.deny()
		DungeonDoor.DoorState.OPEN:
			_transition(door)


func _transition(door: DungeonDoor) -> void:
	_transitioning = true

	var to_cell: Vector2i = door.other(_current)
	var from_room: DungeonRoom = _rooms[_current]
	var to_room: DungeonRoom = _rooms[to_cell]
	var d := Vector3(to_cell.x - _current.x, 0.0, to_cell.y - _current.y)

	from_room.deactivate()

	# Le voile glisse comme un rideau qui suit la caméra : il recouvre
	# l'ancienne salle en arrivant de son côté opposé, et découvre la nouvelle
	# en partant de la porte.
	from_room.animate_veil(0.0, 1.0, -d, transition_time)
	to_room.animate_veil(1.0, 0.0, d, transition_time)

	if camera_rig != null and camera_rig.has_method("transition_to_bounds"):
		camera_rig.transition_to_bounds(to_room.get_bounds(), transition_time)

	var target: Vector3 = door.global_position + d * (wall_thickness * 0.5 + entry_depth)
	await _auto_walk(target, d)

	_current = to_cell
	room_changed.emit(to_cell)
	_activate(to_room)
	_transitioning = false


## Le joueur traverse tout seul : il ne peut ni s'arrêter dans la porte ni
## faire demi-tour pendant le glissement.
func _auto_walk(target: Vector3, d: Vector3) -> void:
	var can_walk: bool = player.has_method("start_auto_walk")
	if can_walk:
		player.start_auto_walk(d)

	var t: float = 0.0
	while t < walk_timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var v: Vector3 = target - player.global_position
		v.y = 0.0
		if v.length() < 0.25 or not can_walk:
			break
		player.set_auto_walk_dir(v.normalized())

	if t >= walk_timeout or not can_walk:
		player.global_position = Vector3(target.x, player.global_position.y, target.z)

	# On laisse le glissement de caméra finir avant de rendre la main
	while t < transition_time:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if can_walk:
			player.set_auto_walk_dir(Vector3.ZERO)

	if can_walk:
		player.stop_auto_walk()


# ---------------------------------------------------------------- ÉVÉNEMENTS DE SALLE

func _on_room_cleared(room: DungeonRoom) -> void:
	if room.cell == _current:
		_play_clear_feedback()
		_reopen_closed()


## Ralenti + secousse sur le dernier ennemi : marque la fin du combat.
func _play_clear_feedback() -> void:
	HitStop.finale()
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("shake"):
		cam.get_parent().shake(0.4)


func _on_key_collected(_room: DungeonRoom) -> void:
	keys += 1
	keys_changed.emit(keys)
