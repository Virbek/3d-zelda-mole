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
## DOOR_OPEN, DOOR_LOCKED, ou DOOR_ONEWAY_A / DOOR_ONEWAY_B (grille à sens
## unique dont la dalle est dans la salle a / b de la clé).
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
## Cinématique d'arrivée : la taupe défonce le mur du bas de la salle de
## départ. Première fois = une seule fois pour de bon (sauvegardé dans
## user://progress.cfg) ; à chaque lancement = une fois par partie (pratique
## pour la régler).
@export_enum("Première fois", "À chaque lancement", "Jamais") var intro_mode: int = 1
## La salle de départ a une brèche au mur du bas, avec le tunnel derrière.
@export var start_breach: bool = true

## Hauteur visible du mur du fond (toile de fond, la collision reste à wall_height).
@export var back_wall_height: float = 6.5:
	set(v):
		back_wall_height = v
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
## Raffinerie ensevelie : terre et sable tassés au sol, roche brune aux murs,
## poutres d'acier rouillé pour les piliers.
@export var floor_color := Color("#7a5c3c")
@export var wall_color := Color("#4a3628")
@export var pillar_color := Color("#6e3a1e")

@export_group("Ambiance")
## Lumière, pénombre et poussière souterraines (null = scène telle quelle)
@export var ambiance: UndergroundAmbiance = UndergroundAmbiance.new()
@export var lamps_per_room: bool = true
@export var decor_per_room: bool = true   ## dunes, poutres, tuyaux, bidons, poussière

@export_group("Musique")
## Une seule musique pour tout le donjon (music_dungeon). En combat, des
## couches de rythme calées dessus (music_layer_1..3) entrent une à une.
@export var music_explore_db: float = -6.0
## Volume de chaque couche de combat une fois entrée : pouls, course, assaut
@export var music_layer_db: Array[float] = [-5.0, -7.0, -8.0]
## Secondes après le début du combat avant l'entrée de chaque couche
@export var music_layer_delay: Array[float] = [0.0, 6.0, 12.0]
@export var music_layer_fade_in: float = 1.5
## Fondu de sortie des couches quand la salle est vidée
@export var music_fade_time: float = 2.5

const DOOR_OPEN := 1
const DOOR_LOCKED := 2
const DOOR_ONEWAY_A := 3   ## grille fermée, dalle dans la salle (k.x, k.y)
const DOOR_ONEWAY_B := 4   ## grille fermée, dalle dans la salle (k.z, k.w)
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
const IntroCinematic := preload("res://Script/dungeon/intro_cinematic.gd")
var _transitioning: bool = false
var _ready_done: bool = false
var _preview_pending: bool = false

const MUSIC_SILENT_DB := -60.0
const MUSIC_LAYERS := ["music_layer_1", "music_layer_2", "music_layer_3"]
var _music_layers: Array[Node] = []   ## null si le fichier manque
var _in_combat: bool = false
var _music_tween: Tween = null


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_preview()
		return
	add_to_group(&"dungeon")   # l'inventaire y lit le nombre de clés
	player = get_node_or_null(player_path)
	camera_rig = get_node_or_null(camera_rig_path)
	if player == null:
		push_warning("Dungeon : player introuvable")
		set_physics_process(false)
		return

	keys_changed.connect(_sync_door_keys)
	_apply_ambiance()
	_start_ambient_sound()
	_build()
	_restore_progress()
	keys_changed.emit(keys)
	# Différé : le joueur a peut-être été replacé au checkpoint dans son _ready
	_enter_first_room.call_deferred()


## Cherche le WorldEnvironment et la lumière directionnelle voisins du
## donjon et leur applique l'ambiance souterraine.
func _apply_ambiance() -> void:
	if ambiance == null:
		return
	var env: Environment = null
	var sun: DirectionalLight3D = null
	var parent: Node = get_parent()
	if parent == null:
		return
	for c in parent.get_children():
		if c is WorldEnvironment and env == null:
			var we: WorldEnvironment = c
			if we.environment == null:
				we.environment = Environment.new()
			env = we.environment
		elif c is DirectionalLight3D and sun == null:
			sun = c
	ambiance.apply_to(env, sun)


## Fond sonore en boucle, en trois couches mixées bas. Enfants du donjon :
## ils s'arrêtent avec la scène, pas de doublon après un rechargement.
## Une couche dont le fichier manque est simplement ignorée.
func _start_ambient_sound() -> void:
	# Musique et couches démarrent dans la même frame et tournent toujours
	# ensemble (couches muettes hors combat) : elles restent calées au temps près.
	_make_native_loop("music_dungeon")
	for key: String in MUSIC_LAYERS:
		_make_native_loop(key)
	Sfx.attach_loop("music_dungeon", self, music_explore_db, false)
	for key: String in MUSIC_LAYERS:
		_music_layers.append(Sfx.attach_loop(key, self, MUSIC_SILENT_DB, false))

	Sfx.attach_loop("amb_refinery", self, -4.0, false)
	Sfx.attach_loop("amb_machines", self, -12.0, false)
	Sfx.attach_loop("amb_insects", self, -14.0, false)


## Boucle gérée par le flux lui-même, sans trou entre deux tours : la relance
## par « finished » d'attach_loop ferait dériver les couches les unes des autres.
func _make_native_loop(key: String) -> void:
	var s: AudioStreamWAV = Sfx.sounds.get(key) as AudioStreamWAV
	if s == null or s.loop_mode == AudioStreamWAV.LOOP_FORWARD:
		return
	s.loop_begin = 0
	s.loop_end = int(round(s.get_length() * s.mix_rate))
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD


## Combat : les couches de rythme entrent l'une après l'autre (pouls, course,
## assaut). Salle vidée : elles s'effacent toutes, la musique continue seule.
func _set_combat_music(on: bool) -> void:
	if player != null:
		player.set("in_combat", on)
	if on == _in_combat:
		return   # déjà dans le bon état (ex. réapparition dans une salle en combat)
	_in_combat = on

	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)

	var count: int = 0
	for i in _music_layers.size():
		var p: Node = _music_layers[i]
		if not is_instance_valid(p):
			continue
		if on:
			var db: float = music_layer_db[i] if i < music_layer_db.size() else -6.0
			var delay: float = music_layer_delay[i] if i < music_layer_delay.size() else 0.0
			_fade_loop(p, db, music_layer_fade_in, delay)
		else:
			_fade_loop(p, MUSIC_SILENT_DB, music_fade_time)
		count += 1
	if count == 0:
		_music_tween.kill()   # un tween sans étape lève une erreur


func _fade_loop(p: Node, to_db: float, duration: float, delay: float = 0.0) -> void:
	var from_db: float = float(p.get_meta("base_db", 0.0))
	_music_tween.tween_method(_set_loop_db.bind(p), from_db, to_db, duration).set_delay(delay)


## Passe par base_db pour que le réglage de volume global reste respecté.
## p en Variant : la boucle a pu être libérée pendant le fondu.
func _set_loop_db(db: float, p: Variant) -> void:
	if is_instance_valid(p):
		p.set_meta("base_db", db)
		p.set("volume_db", Sfx.master_volume_db + db)


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
			# Grille 2n+1 : la moitié entière d'un indice donne la case. Voulu.
			@warning_ignore_start("integer_division")
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
			@warning_ignore_restore("integer_division")
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
			var v: int = layout_doors[key]
			# 4e élément : salle de la dalle d'une grille à sens unique (ou null)
			var plate_cell: Variant = null
			if v == DOOR_ONEWAY_A:
				plate_cell = Vector2i(k.x, k.y)
			elif v == DOOR_ONEWAY_B:
				plate_cell = Vector2i(k.z, k.w)
			links.append([Vector2i(k.x, k.y), Vector2i(k.z, k.w), v == DOOR_LOCKED, plate_cell])
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
		room.back_wall_height = back_wall_height
		room.wall_thickness = wall_thickness
		room.door_width = door_width
		room.door_height = door_height
		room.doors = room_doors.get(cell, {})
		# Brèche au mur du bas de la salle de départ. Le tunnel de terre n'est
		# creusé derrière que s'il n'y a pas de salle de ce côté : sinon la
		# brèche donne sur le noir de la salle voisine (voilée).
		room.breach_south = start_breach and cell == _start
		room.breach_tunnel = not room_chars.has(cell + Vector2i(0, 1))
		room.player = player
		room.scenes = scenes
		room.floor_color = floor_color
		room.wall_color = wall_color
		room.pillar_color = pillar_color
		room.with_lamps = lamps_per_room
		room.with_decor = decor_per_room
		room.position = _cell_to_local(cell)
		add_child(room)
		room.build()
		room.cleared.connect(_on_room_cleared)
		room.exit_reached.connect(_on_exit_reached)
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
		door.ledge_height = (_rooms.values()[0] as DungeonRoom).ledge_height if not _rooms.is_empty() else 0.8
		door.depth = wall_thickness
		door.state = DungeonDoor.DoorState.LOCKED if l[2] else DungeonDoor.DoorState.OPEN
		if l.size() > 3 and l[3] != null:
			door.one_way = true
			door.plate_cell = l[3]
			door.state = DungeonDoor.DoorState.CLOSED
		door.position = (_cell_to_local(a) + _cell_to_local(b)) * 0.5
		add_child(door)
		door.build()
		(_rooms[a] as DungeonRoom).add_veil_piece(door.half_a)
		(_rooms[b] as DungeonRoom).add_veil_piece(door.half_b)
		if door.plate != null:
			(_rooms[door.plate_cell] as DungeonRoom).add_veil_piece(door.plate)
		door.plate_pressed.connect(_on_door_plate_pressed)
		door.player_entered.connect(_on_door_entered)
		door.unlock_requested.connect(_on_door_unlock_requested)
		door.has_key = keys > 0
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

	if found == _start and start_room.breach_south and IntroCinematic.should_play(intro_mode):
		var intro: Node = IntroCinematic.new()
		add_child(intro)
		intro.call("play", start_room, player, camera_rig)


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
	_set_combat_music(alive > 0)
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
			# On ne dépense plus la clé en touchant la porte : il faut appuyer
			# sur « interact » devant (voir _on_door_unlock_requested).
			if keys <= 0:
				door.deny()
		DungeonDoor.DoorState.CLOSED:
			# Grille à sens unique : elle ne s'ouvre que par sa dalle
			if door.is_one_way_shut():
				door.deny()
		DungeonDoor.DoorState.OPEN:
			_transition(door)


## Dalle d'une grille à sens unique : la grille s'ouvre pour de bon. Si un
## combat enferme la salle, elle attend la fin des vagues comme les autres.
func _on_door_plate_pressed(door: DungeonDoor) -> void:
	(_progress()["doors"] as Dictionary)[door.name] = true
	for d in _closed:
		if d.connects(_current):
			_closed.append(door)
			return
	door.open()


## Le joueur a appuyé devant une porte verrouillée.
func _on_door_unlock_requested(door: DungeonDoor) -> void:
	if _transitioning or not _ready_done or not door.connects(_current):
		return
	if keys <= 0:
		door.deny()
		return
	keys -= 1
	keys_changed.emit(keys)
	var prog: Dictionary = _progress()
	prog["keys"] = keys
	(prog["doors"] as Dictionary)[door.name] = true
	if player.has_method("begin_interaction"):
		player.begin_interaction(door.global_position)
	await door.play_unlock(player.global_position)
	# Rendu avant l'ouverture : la porte ouverte relance le passage
	# automatique, qui reprend lui-même les commandes du joueur.
	if player.has_method("end_interaction"):
		player.end_interaction()
	door.open()


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
	(_progress()["cleared"] as Dictionary)[room.cell] = true
	if room.cell == _current:
		# Salle vide dès l'entrée (aucun ennemi à faire apparaître) : elle est
		# « nettoyée » sans combat, donc pas de ralenti de fin de combat.
		if _in_combat:
			_play_clear_feedback()
		_reopen_closed()
		_set_combat_music(false)


## Le joueur passe la brèche ouverte par le boss : il s'avance dans la
## lumière, l'écran blanchit puis noircit, et « FIN » s'affiche.
var _ending: bool = false
const MAIN_MENU := "res://MainMenu.tscn"

func _on_exit_reached() -> void:
	if _ending:
		return
	_ending = true
	_transitioning = true
	if player.has_method("start_auto_walk"):
		player.start_auto_walk(Vector3.RIGHT)
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()

	var layer := CanvasLayer.new()
	layer.layer = 95
	add_child(layer)
	var veil := ColorRect.new()
	veil.color = Color(1.0, 0.93, 0.8, 0.0)   # d'abord la lumière du dehors
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(veil)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.modulate.a = 0.0
	layer.add_child(box)
	var font: Font = load("res://Font/SairaStencilOne.ttf") as Font
	for line in [["FIN", 120, Color("#f0c27a")], ["Merci d'avoir joué !", 40, Color("#e8dcc8")]]:
		var l := Label.new()
		l.text = line[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", line[1])
		l.add_theme_color_override("font_color", line[2])
		if font != null:
			l.add_theme_font_override("font", font)
		box.add_child(l)

	var t := create_tween()
	t.tween_property(veil, "color:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(veil, "color", Color(0.0, 0.0, 0.0, 1.0), 1.2)
	t.tween_callback(func() -> void:
		if player.has_method("stop_auto_walk"):
			player.set_auto_walk_dir(Vector3.ZERO)
	)
	t.tween_property(box, "modulate:a", 1.0, 1.0)
	# Puis retour au menu principal
	t.tween_interval(3.5)
	t.tween_property(box, "modulate:a", 0.0, 0.8)
	t.tween_callback(func() -> void:
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file(MAIN_MENU)
	)


## Ralenti + secousse sur le dernier ennemi : marque la fin du combat.
func _play_clear_feedback() -> void:
	HitStop.finale()
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("shake"):
		cam.get_parent().shake(0.4)


func _on_key_collected(room: DungeonRoom) -> void:
	keys += 1
	keys_changed.emit(keys)
	var prog: Dictionary = _progress()
	prog["keys"] = keys
	(prog["key_given"] as Dictionary)[room.cell] = true


# ---------------------------------------------------------------- PROGRESSION

## Progression mémorisée de CE donjon (créée vide au premier passage). Vit
## dans l'autoload Checkpoints : une mort recharge la scène, pas l'autoload.
func _progress() -> Dictionary:
	var scene: Node = get_tree().current_scene
	var id: String = "%s|%s" % [scene.scene_file_path if scene != null else "", get_path()]
	if not Checkpoints.dungeon_progress.has(id):
		Checkpoints.dungeon_progress[id] = {
			"keys": 0,
			"cleared": {},     ## Vector2i → true : salles nettoyées
			"key_given": {},   ## Vector2i → true : clé de la salle déjà ramassée
			"doors": {},       ## nom de porte → true : déverrouillée / grille ouverte
		}
	return Checkpoints.dungeon_progress[id]


## Après une mort : on remet le donjon dans l'état où le joueur l'a laissé.
## Les ennemis des salles nettoyées ne reviennent pas (sauf si la salle est
## réglée sur « les ennemis reviennent à chaque visite »).
func _restore_progress() -> void:
	var prog: Dictionary = _progress()
	keys = int(prog["keys"])
	var cleared: Dictionary = prog["cleared"]
	var key_given: Dictionary = prog["key_given"]
	for cell: Vector2i in _rooms:
		if cleared.has(cell) or key_given.has(cell):
			(_rooms[cell] as DungeonRoom).restore_progress(cleared.has(cell), key_given.has(cell))
	var opened: Dictionary = prog["doors"]
	for d in _doors:
		if opened.has(d.name):
			d.set_state_instant(DungeonDoor.DoorState.OPEN)
		d.has_key = keys > 0


## Les portes affichent « Ouvrir (clé) » ou « il faut une clé » selon le stock.
func _sync_door_keys(count: int) -> void:
	for d in _doors:
		d.has_key = count > 0
