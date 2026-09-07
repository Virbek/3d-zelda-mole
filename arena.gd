extends Node3D

## Arène de test : construit la salle par script, puis enchaîne des vagues
## avant de lâcher le boss.
##
## Tout est procédural pour que l'itération soit rapide — changer un nombre
## suffit à changer la salle, sans passer par l'éditeur ni risquer de casser
## les UIDs d'une scène.
##
## La salle n'est pas un rectangle vide : les piliers créent des angles morts
## contre les tireurs et donnent des obstacles aux chargeurs, la plateforme
## casse la planéité. Un combat testé dans le vide ne dit rien.

signal wave_started(index: int, total: int)
signal wave_cleared(index: int)
signal boss_started
signal arena_cleared

@export var player_path: NodePath

@export_group("Scènes")
@export var charger_scene: PackedScene
@export var shooter_scene: PackedScene
@export var bomber_scene: PackedScene
@export var boss_scene: PackedScene

@export_group("Dimensions")
@export var room_size := Vector2(20.0, 20.0)
@export var wall_height: float = 4.0
@export var wall_thickness: float = 1.0   ## épais : évite le tunneling à grande vitesse

@export_group("Obstacles")
@export var pillar_count: int = 4
@export var pillar_size: float = 1.2
@export var pillar_spread: float = 0.42   ## fraction de la salle, depuis le centre
@export var platform_size := Vector3(6.0, 0.9, 5.0)
@export var platform_corner := Vector2(-1.0, -1.0)  ## signe x, signe z
@export var ramp_length: float = 5.0
@export var ramp_width: float = 2.5
@export var ramp_thickness: float = 0.4

@export_group("Vagues")
## Chaque vague : x = chargeurs, y = tireurs, z = bombardiers.
@export var waves: Array[Vector3i] = [
	Vector3i(2, 0, 0),
	Vector3i(1, 2, 1),
	Vector3i(2, 1, 2),
]
@export var spawn_margin: float = 3.0     ## distance aux murs
@export var spawn_min_from_player: float = 7.0
@export var wave_delay: float = 1.6       ## respiration entre deux vagues
@export var start_delay: float = 1.0

@export_group("Boss")
@export var spawn_boss: bool = true
@export var boss_delay: float = 2.5       ## pause avant son arrivée
@export var boss_distance: float = 8.0    ## distance au joueur à l'apparition

@export_group("Couleurs")
@export var floor_color := Color(0.55, 0.52, 0.48)
@export var wall_color := Color(0.38, 0.36, 0.34)
@export var pillar_color := Color(0.45, 0.42, 0.40)

@onready var player: CharacterBody3D = get_node(player_path)

var _wave: int = -1
var _alive: int = 0
var _running: bool = false
var _boss_phase: bool = false
var _spawn_points: Array[Vector3] = []


func _ready() -> void:
	_build_room()
	_collect_spawn_points()

	await get_tree().create_timer(start_delay).timeout
	_next_wave()


# ---------------------------------------------------------------- CONSTRUCTION

func _build_room() -> void:
	var hx: float = room_size.x * 0.5
	var hz: float = room_size.y * 0.5

	_add_box("Floor",
		Vector3(room_size.x, wall_thickness, room_size.y),
		Vector3(0.0, -wall_thickness * 0.5, 0.0),
		floor_color)

	# Les murs débordent en largeur pour ne pas laisser d'interstice aux angles
	_add_box("WallN",
		Vector3(room_size.x + wall_thickness * 2.0, wall_height, wall_thickness),
		Vector3(0.0, wall_height * 0.5, -hz - wall_thickness * 0.5),
		wall_color)
	_add_box("WallS",
		Vector3(room_size.x + wall_thickness * 2.0, wall_height, wall_thickness),
		Vector3(0.0, wall_height * 0.5, hz + wall_thickness * 0.5),
		wall_color)
	_add_box("WallW",
		Vector3(wall_thickness, wall_height, room_size.y),
		Vector3(-hx - wall_thickness * 0.5, wall_height * 0.5, 0.0),
		wall_color)
	_add_box("WallE",
		Vector3(wall_thickness, wall_height, room_size.y),
		Vector3(hx + wall_thickness * 0.5, wall_height * 0.5, 0.0),
		wall_color)

	# Piliers en couronne, décalés du centre pour laisser un espace de combat
	for i in pillar_count:
		var a: float = TAU * float(i) / float(pillar_count) + PI * 0.25
		var p := Vector3(
			cos(a) * room_size.x * pillar_spread,
			wall_height * 0.5,
			sin(a) * room_size.y * pillar_spread
		)
		_add_box("Pillar%d" % i,
			Vector3(pillar_size, wall_height, pillar_size),
			p, pillar_color)

	# Plateforme dans un coin : le dénivelé teste le rig et les raycasts de pied
	var pp := Vector3(
		signf(platform_corner.x) * (hx - platform_size.x * 0.5 - 0.5),
		platform_size.y * 0.5,
		signf(platform_corner.y) * (hz - platform_size.z * 0.5 - 0.5)
	)
	_add_box("Platform", platform_size, pp, pillar_color)
	_add_ramp(pp)


## Rampe d'accès. Elle est enfoncée sous le niveau du sol : son arête basse
## doit passer sous zéro, sinon elle forme une marche que le CharacterBody3D
## refuse de franchir.
func _add_ramp(platform_pos: Vector3) -> void:
	var h: float = platform_size.y
	var sx: float = signf(platform_corner.x)
	var sz: float = signf(platform_corner.y)
	var along_x: bool = platform_size.x >= platform_size.z

	var dir := Vector3(-sx, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, -sz)
	var edge: Vector3 = platform_pos + dir * (
		(platform_size.x if along_x else platform_size.z) * 0.5
	)
	edge.y = h

	var center: Vector3 = edge + dir * (ramp_length * 0.5)
	center.y = h * 0.5 - ramp_thickness * 0.5

	var box := CSGBox3D.new()
	box.name = "Ramp"
	box.size = Vector3(
		ramp_length if along_x else ramp_width,
		ramp_thickness,
		ramp_width if along_x else ramp_length
	)
	box.position = center
	box.use_collision = true

	var angle: float = atan2(h, ramp_length)
	if along_x:
		box.rotation.z = angle * sx
	else:
		box.rotation.x = -angle * sz

	var mat := StandardMaterial3D.new()
	mat.albedo_color = pillar_color
	box.material = mat
	add_child(box)


## CSGBox3D plutôt que MeshInstance + StaticBody : une seule ligne pour avoir
## la collision, et le résultat reste éditable à la main si besoin.
func _add_box(n: String, size: Vector3, pos: Vector3, color: Color) -> void:
	var box := CSGBox3D.new()
	box.name = n
	box.size = size
	box.position = pos
	box.use_collision = true

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat

	add_child(box)


# ---------------------------------------------------------------- SPAWNS

## Points répartis en anneau, filtrés pour ne pas tomber dans un pilier.
func _collect_spawn_points() -> void:
	_spawn_points.clear()

	var hx: float = room_size.x * 0.5 - spawn_margin
	var hz: float = room_size.y * 0.5 - spawn_margin

	for i in 12:
		var a: float = TAU * float(i) / 12.0
		var p := Vector3(cos(a) * hx, 0.3, sin(a) * hz)

		var clear := true
		for c in get_children():
			if c is CSGBox3D and c.name.begins_with("Pillar"):
				if Vector2(p.x - c.position.x, p.z - c.position.z).length() < pillar_size + 1.0:
					clear = false
					break

		if clear:
			_spawn_points.append(p)


## Le point le plus loin du joueur parmi ceux disponibles : un ennemi qui
## apparaît dans le dos du joueur est frustrant, pas difficile.
func _pick_spawn(used: Array) -> Vector3:
	var best := Vector3.ZERO
	var best_d: float = -1.0

	for p in _spawn_points:
		if p in used:
			continue
		var d: float = Vector2(
			p.x - player.global_position.x,
			p.z - player.global_position.z
		).length()
		if d < spawn_min_from_player:
			continue
		if d > best_d:
			best_d = d
			best = p

	# Aucun point valide : on relâche la contrainte plutôt que de ne rien spawner
	if best_d < 0.0 and _spawn_points.size() > 0:
		best = _spawn_points[randi() % _spawn_points.size()]

	return best


# ---------------------------------------------------------------- VAGUES

func _next_wave() -> void:
	_wave += 1

	if _wave >= waves.size():
		_start_boss()
		return

	var w: Vector3i = waves[_wave]
	var used: Array = []

	_alive = 0
	_running = true
	wave_started.emit(_wave + 1, waves.size())

	for i in w.x:
		var p: Vector3 = _pick_spawn(used)
		used.append(p)
		_spawn(charger_scene, p)

	for i in w.y:
		var p: Vector3 = _pick_spawn(used)
		used.append(p)
		_spawn(shooter_scene, p)

	for i in w.z:
		var p: Vector3 = _pick_spawn(used)
		used.append(p)
		_spawn(bomber_scene, p)

	# Sécurité : une vague vide bloquerait la progression
	if _alive == 0:
		_on_enemy_died()


func _spawn(scene: PackedScene, pos: Vector3) -> void:
	if scene == null:
		push_warning("Arena : scène d'ennemi manquante")
		return

	var e: CharacterBody3D = scene.instantiate()

	# Avant add_child : les @onready de l'ennemi lisent player_path pendant
	# son entrée dans l'arbre, donc il doit déjà être renseigné.
	e.player_path = player.get_path()

	add_child(e)
	e.global_position = global_position + pos

	if e.has_signal("died"):
		e.died.connect(_on_enemy_died)

	_alive += 1


func _on_enemy_died() -> void:
	_alive -= 1
	if _alive > 0 or not _running:
		return

	_running = false

	if _boss_phase:
		arena_cleared.emit()
		return

	wave_cleared.emit(_wave + 1)
	await get_tree().create_timer(wave_delay).timeout
	_next_wave()


# ---------------------------------------------------------------- BOSS

## Le boss arrive après une pause plus longue que les entre-vagues : ce silence
## est ce qui le distingue d'une quatrième vague ordinaire.
func _start_boss() -> void:
	if not spawn_boss or boss_scene == null:
		_running = false
		arena_cleared.emit()
		return

	await get_tree().create_timer(boss_delay).timeout

	# En face du joueur, à distance, sur le sol : le boss lit _ground_y dans
	# son _ready et s'en sert comme référence pour tous ses sauts.
	var away: Vector3 = player.global_position - global_position
	away.y = 0.0
	var dir: Vector3 = -away.normalized() if away.length() > 0.5 else Vector3.FORWARD

	var limit: float = minf(room_size.x, room_size.y) * 0.5 - spawn_margin
	var pos: Vector3 = player.global_position + dir * minf(boss_distance, limit)
	pos.y = global_position.y

	_boss_phase = true
	_alive = 0
	_running = true

	var b: CharacterBody3D = boss_scene.instantiate()
	b.player_path = player.get_path()
	add_child(b)
	b.global_position = pos

	if b.has_signal("died"):
		b.died.connect(_on_enemy_died)

	_alive = 1
	boss_started.emit()
