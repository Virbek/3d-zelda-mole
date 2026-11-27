@tool
extends Node3D
class_name DungeonRoom

## Une salle du donjon, construite par script à partir de sa RoomData.
##
## Le Dungeon la configure (taille, portes, scènes d'ennemis), puis appelle
## build(). Ensuite il ne fait que l'activer / la désactiver et animer son
## voile ; la salle gère elle-même ses ennemis, son coffre et sa clé, et
## prévient le Dungeon par signaux.
##
## Le voile est une dalle noire posée sur le sol, et tout ce qui dépasse
## (murs, piliers, coffre, clé) est masqué sous la partie voilée. Un bloc noir
## de la hauteur des murs aurait été plus simple, mais avec la caméra
## isométrique celui de la salle côté caméra masquait la moitié de la salle
## courante. Vu de l'intérieur, une porte ouverte donne donc sur du noir.
##
## Les murs sont découpés en tronçons de chunk_length : pendant une
## transition, ils apparaissent / disparaissent au fil du voile au lieu de
## surgir d'un bloc. Seule la salle courante est donc dessinée.

signal cleared(room: DungeonRoom)
signal key_collected(room: DungeonRoom)

# --- Rempli par le Dungeon avant build() ---
var data: RoomData
var cell := Vector2i.ZERO
var room_size := Vector2(20.0, 16.0)
var wall_height: float = 4.0
var wall_thickness: float = 1.0
var door_width: float = 2.4
var door_height: float = 2.8
var doors: Dictionary = {}       ## Vector2i (direction) → bool
var player: CharacterBody3D
var scenes: Dictionary = {}      ## "charger" / "shooter" / "bomber" / "melee" / "boss" → PackedScene
var floor_color := Color(0.55, 0.52, 0.48)
var wall_color := Color(0.38, 0.36, 0.34)
var pillar_color := Color(0.45, 0.42, 0.40)
var with_lamps: bool = true
var with_decor: bool = true

## Lampes murales : seule vraie source de lumière de la raffinerie ensevelie
const LAMP_COLOR := Color(1.0, 0.62, 0.3)
const LAMP_ENERGY := 0.65
const LAMP_RANGE := 7.0
## 1 = décroissance douce. Plus haut, la lumière se concentre en un point
## chaud sous l'applique (halo trop marqué sur le mur et le sol).
const LAMP_FALLOFF := 1.0

var chunk_length: float = 2.0

## Caméra en perspective, au-dessus de la salle : les murs de côté montrent
## leur face intérieure et ne cachent rien. Seul le mur du bas (+Z), vu de
## dessus, n'est qu'un muret. Les collisions gardent toute la hauteur.
var ledge_height: float = 0.8
## Hauteur visible des murs du fond et des côtés. Plus haute que la
## collision, elle bouche le vide que la perspective laisse voir au-dessus.
var back_wall_height: float = 6.5

## Décalage des pièces posées sur un mur ou un pilier, pour qu'aucune face
## ne soit exactement au même niveau qu'une autre (sinon elles scintillent).
const Z_LIFT := 0.02
var spawn_telegraph_time: float = 0.8   ## durée de l'annonce au sol avant qu'un ennemi apparaisse

var is_cleared: bool = false
var is_active: bool = false

var _veil: MeshInstance3D
var _veil_k: float = 1.0
var _veil_anchor := Vector3.RIGHT
var _veil_tween: Tween
var _pieces: Array[Node3D] = []   ## tout ce que le voile masque

var _enemies: Array[Node] = []
var _alive: int = 0
var _pillars: Array[Vector3] = []
var _pillar_radius: float = 0.6
var _chest_pos := Vector3.ZERO           ## case « C » du layout, centre sinon
var _key_pos := Vector3.ZERO             ## case « k » du layout, centre sinon
var _post_positions: Array[Vector3] = [] ## cases « S » du layout : bornes de recharge (checkpoints)
var _rematch: bool = false                ## le combat en cours est la revanche du boss
var _pedestal_positions: Array[Vector3] = [] ## cases « R » du layout : piédestaux de relique
var _wave: int = 0                       ## index de la vague en cours
var _activation: int = 0                 ## change à chaque entrée/sortie : annule les vagues en attente

## Lettre d'une vague → type d'ennemi.
const WAVE_KINDS := {"c": "charger", "s": "shooter", "b": "bomber", "m": "melee", "B": "boss"}
var _key_given: bool = false
var _chest: DungeonChest = null


var spacing: Vector2:
	get:
		return room_size + Vector2(wall_thickness, wall_thickness)


# ---------------------------------------------------------------- CONSTRUCTION

func build() -> void:
	if data == null:
		data = RoomData.new()

	var sp: Vector2 = spacing
	var hx: float = room_size.x * 0.5
	var hz: float = room_size.y * 0.5
	var ht: float = wall_thickness * 0.5   # chaque salle porte la moitié du mur commun

	# Le sol couvre aussi le dessous des murs : le passage d'une porte a un sol.
	_add_box("Floor", Vector3(sp.x, 1.0, sp.y), Vector3(0.0, -0.5, 0.0), floor_color, false)

	_build_wall(Vector2i(0, -1), sp.x, Vector3(0.0, 0.0, -hz - ht * 0.5), true, ht)
	_build_wall(Vector2i(0, 1), sp.x, Vector3(0.0, 0.0, hz + ht * 0.5), true, ht)
	_build_wall(Vector2i(-1, 0), room_size.y, Vector3(-hx - ht * 0.5, 0.0, 0.0), false, ht)
	_build_wall(Vector2i(1, 0), room_size.y, Vector3(hx + ht * 0.5, 0.0, 0.0), false, ht)

	_build_layout()
	if _pillars.is_empty():
		_build_pillars()
	if with_lamps:
		_build_lamps()
	if with_decor:
		var avoid: Array[Vector3] = _pillars.duplicate()
		avoid.append(_chest_pos)
		avoid.append(_key_pos)
		avoid.append_array(_post_positions)
		avoid.append_array(_pedestal_positions)
		RoomDecor.build(self, avoid)
	_spawn_charge_posts()
	_spawn_pedestals()
	_build_veil()

	# Le coffre est là où un « C » est dessiné dans le décor, et nulle part
	# ailleurs : le jeu montre exactement ce que montre l'éditeur. Seul
	# « coffre quand la salle est vidée » le fait attendre la fin du combat.
	if _has_chest() and data.key_source == RoomData.KeySource.CHEST:
		_spawn_chest(_chest_pos)


## Un mur, coupé en deux autour de la porte s'il y en a une, avec un linteau
## au-dessus : vu de la caméra, l'ouverture a une vraie forme de porte.
func _build_wall(dir: Vector2i, length: float, center: Vector3, along_x: bool, thick: float) -> void:
	var n: String = "Wall_%d_%d" % [dir.x, dir.y]
	var y: float = wall_height * 0.5

	if not doors.get(dir, false):
		_add_wall_run(n, length, center + Vector3(0.0, y, 0.0), along_x, thick, dir)
		return

	var seg: float = (length - door_width) * 0.5
	var off: float = door_width * 0.5 + seg * 0.5
	for s in [-1.0, 1.0]:
		var p: Vector3 = center + Vector3(0.0, y, 0.0)
		if along_x:
			p.x += off * s
		else:
			p.z += off * s
		_add_wall_run("%s_%d" % [n, int(s)], seg, p, along_x, thick, dir)

	var lintel_h: float = wall_height - door_height
	if lintel_h > 0.01:
		var lp: Vector3 = center + Vector3(0.0, door_height + lintel_h * 0.5, 0.0)
		var ls := Vector3(door_width, lintel_h, thick) if along_x else Vector3(thick, lintel_h, door_width)
		# Au-dessus d'un muret, un linteau flotterait : collision seule.
		# Sur un mur plus haut que la collision, il monte jusqu'en haut.
		var vh: float = _visual_wall_height(dir, lp)
		var lintel_visual: float = 0.0
		if vh > wall_height:
			lintel_visual = vh - door_height
		elif vh >= wall_height:
			lintel_visual = -1.0
		_add_box(n + "_Lintel", ls, lp, wall_color, true, lintel_visual)


## Un pan de mur, découpé en tronçons pour que le voile le révèle petit à petit.
func _add_wall_run(n: String, length: float, center: Vector3, along_x: bool, thick: float, dir: Vector2i = Vector2i.ZERO) -> void:
	var count: int = maxi(1, int(ceil(length / maxf(chunk_length, 0.5))))
	var piece: float = length / float(count)
	for i in count:
		var off: float = -length * 0.5 + piece * (float(i) + 0.5)
		var p: Vector3 = center + (Vector3(off, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, off))
		var size := Vector3(piece, wall_height, thick) if along_x else Vector3(thick, wall_height, piece)
		var vh: float = _visual_wall_height(dir, p)
		var mesh := _add_box("%s_%d" % [n, i], size, p, wall_color, true, vh if not is_equal_approx(vh, wall_height) else -1.0)
		if mesh != null:
			_add_wall_cap(mesh, size, vh)


## Hauteur visible d'un tronçon de mur. Bas (+Z) : muret, vu de dessus.
## Fond et côtés : une seule hauteur, sans palier. En perspective, les côtés
## montrent leur face intérieure et ne cachent rien.
func _visual_wall_height(dir: Vector2i, _p: Vector3) -> float:
	if dir == Vector2i(0, 1):
		return ledge_height
	return maxf(back_wall_height, wall_height)


## Arête de roche plus sombre sur le dessus d'un tronçon : vue de haut, le
## mur a un bord net au lieu d'un aplat uni.
func _add_wall_cap(wall: MeshInstance3D, size: Vector3, _visible_h: float) -> void:
	var cap := MeshInstance3D.new()
	var b := BoxMesh.new()
	# Débord seulement dans l'épaisseur du mur : dans la longueur, l'arête
	# chevaucherait celle du tronçon voisin (deux dessus confondus = z-fighting)
	var along_x: bool = size.x > size.z
	b.size = Vector3(size.x if along_x else size.x + 0.06, 0.12, size.z + 0.06 if along_x else size.z)
	cap.mesh = b
	var mesh_h: float = (wall.mesh as BoxMesh).size.y
	# Légèrement au-dessus du mur : sinon les deux dessus sont au même niveau
	cap.position = Vector3(0.0, mesh_h * 0.5 - 0.06 + Z_LIFT, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = wall_color.darkened(0.35)
	cap.material_override = m
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.add_child(cap)


## Convertit une case (colonne, rangée) d'une grille cols × rows en position
## locale : la grille est étirée sur tout l'intérieur de la salle.
## Taille de la grille de placement : une case = 2 m, comme dans le panneau
## « Donjon » de l'éditeur. Le jeu et l'éditeur placent donc tout au même endroit.
func grid_dims() -> Vector2i:
	return Vector2i(maxi(1, roundi(room_size.x / 2.0)), maxi(1, roundi(room_size.y / 2.0)))


func grid_to_local(col: int, row: int, cols: int, rows: int) -> Vector3:
	var cw: float = room_size.x / float(maxi(cols, 1))
	var ch: float = room_size.y / float(maxi(rows, 1))
	return Vector3(
		-room_size.x * 0.5 + cw * (float(col) + 0.5),
		0.0,
		-room_size.y * 0.5 + ch * (float(row) + 0.5)
	)


## Piliers (P), coffre (C) et emplacement de clé (k) placés case par case.
func _build_layout() -> void:
	if data.layout.strip_edges() == "":
		return
	var g: Dictionary = RoomData.parse_grid(data.layout)
	var dims: Vector2i = grid_dims()
	var cols: int = dims.x
	var rows: int = dims.y
	var cell_size := Vector2(room_size.x / float(maxi(cols, 1)), room_size.y / float(maxi(rows, 1)))
	var i: int = 0
	for c in g["cells"]:
		if c["col"] >= cols or c["row"] >= rows:
			continue   # hors de la salle (dessin plus grand que la grille)
		var pos: Vector3 = grid_to_local(c["col"], c["row"], cols, rows)
		match c["ch"]:
			"P", "#":
				# Un pilier remplit sa case : plusieurs P côte à côte font un mur.
				_pillars.append(pos)
				_pillar_radius = maxf(cell_size.x, cell_size.y) * 0.5
				var bs := Vector3(cell_size.x, wall_height, cell_size.y)
				var bh: float = _pillar_visual_height(pos)
				var block := _add_box("Block%d" % i, bs, pos + Vector3(0.0, wall_height * 0.5, 0.0), pillar_color, true, bh if bh < wall_height else -1.0)
				_decorate_pillar(block, bs, bh)
			"C":
				_chest_pos = pos
			"k":
				_key_pos = pos
			"S":
				_post_positions.append(pos)
			"R":
				_pedestal_positions.append(pos)
			_:
				push_warning("%s : caractère '%s' inconnu dans layout (P C k S R .)" % [name, c["ch"]])
		i += 1


func _build_pillars() -> void:
	for i in data.pillar_count:
		var a: float = TAU * float(i) / float(maxi(data.pillar_count, 1)) + PI * 0.25
		var p := Vector3(
			cos(a) * room_size.x * data.pillar_spread,
			wall_height * 0.5,
			sin(a) * room_size.y * data.pillar_spread
		)
		_pillars.append(Vector3(p.x, 0.0, p.z))
		_pillar_radius = data.pillar_size * 0.5
		var ps := Vector3(data.pillar_size, wall_height, data.pillar_size)
		var ph: float = _pillar_visual_height(p)
		var pillar := _add_box("Pillar%d" % i, ps, p, pillar_color, true, ph if ph < wall_height else -1.0)
		_decorate_pillar(pillar, ps, ph)


## En perspective, un pilier ne masque presque rien : pleine hauteur
## partout. Le rare pilier gênant est estompé par la caméra.
func _pillar_visual_height(_p: Vector3) -> float:
	return wall_height


## Colonne de soutènement de la raffinerie : socle de roche, fût rouillé,
## bandes d'acier, bande de danger et chapiteau. Tout est enfant du visuel
## principal (matériaux standards) : la caméra estompe la colonne d'un bloc.
func _decorate_pillar(pillar: MeshInstance3D, size: Vector3, visible_h: float) -> void:
	if pillar == null:
		return
	var h: float = minf(visible_h, wall_height)
	var bottom: float = -h * 0.5   # repère du visuel : centré sur sa hauteur
	var parts: Array = [
		# [taille XZ (× taille du pilier), hauteur, hauteur du centre depuis le sol, couleur]
		[1.18, 0.45, 0.225, wall_color.darkened(0.2)],          # socle de roche
		[1.06, 0.12, 1.0, Color("#4a4c4b")],                    # bande d'acier
		[1.07, 0.2, 1.45, Color("#e0a23a")],                    # bande de danger
		[1.06, 0.12, 2.6, Color("#4a4c4b")],                    # bande d'acier
		[1.14, 0.25, h - 0.125 + Z_LIFT, pillar_color.darkened(0.4)],    # chapiteau / cassure
	]
	for part in parts:
		var y: float = part[2]
		if y + part[1] * 0.5 > h + Z_LIFT + 0.01:
			continue   # colonne tronquée : la bande serait dans le vide
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(size.x * part[0], part[1], size.z * part[0])
		m.mesh = b
		m.position = Vector3(0.0, bottom + y, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = part[3]
		m.material_override = mat
		pillar.add_child(m)


## Quatre lampes accrochées aux murs : deux au fond, une de chaque côté
## (décalées vers le fond pour ne pas tomber dans l'embrasure des portes).
func _build_lamps() -> void:
	var hx: float = room_size.x * 0.5
	var hz: float = room_size.y * 0.5
	var y: float = wall_height * 0.7
	var inset: float = 0.12
	_add_lamp(Vector3(-hx * 0.5, y, -hz + inset), Vector3.BACK)
	_add_lamp(Vector3(hx * 0.5, y, -hz + inset), Vector3.BACK)
	_add_lamp(Vector3(-hx + inset, y, -hz * 0.4), Vector3.RIGHT)
	_add_lamp(Vector3(hx - inset, y, -hz * 0.4), Vector3.LEFT)


## Applique en acier + ampoule orange qui brille, et la lumière elle-même.
## facing : direction vers l'intérieur de la salle.
func _add_lamp(pos: Vector3, facing: Vector3) -> void:
	var lamp := Node3D.new()
	lamp.name = "Lamp"
	lamp.position = pos
	add_decor(lamp)   # masquée (et éteinte) tant que le voile couvre sa salle
	if facing.length() > 0.01:
		lamp.look_at_from_position(pos, pos + facing, Vector3.UP)

	var bracket := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.3, 0.16)
	bracket.mesh = bm
	bracket.position = Vector3(0.0, 0.0, -0.08)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#4a4c4b")
	bracket.material_override = steel
	lamp.add_child(bracket)

	var bulb := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.16, 0.18, 0.12)
	bulb.mesh = sm
	bulb.position = Vector3(0.0, -0.02, -0.2)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = LAMP_COLOR
	bulb.material_override = glow
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.add_child(bulb)

	var light := OmniLight3D.new()
	light.light_color = LAMP_COLOR
	light.light_energy = LAMP_ENERGY
	light.omni_range = LAMP_RANGE
	light.omni_attenuation = LAMP_FALLOFF
	# Les ombres viennent des lampes, pas du soleil : elles partent bien de la
	# source qu'on voit. Seules les lampes de la salle courante sont allumées.
	light.shadow_enabled = true
	light.shadow_blur = 1.5
	light.shadow_bias = 0.08
	# Écartée du mur : sinon le mur juste sous la lampe brûle
	light.position = Vector3(0.0, 0.2, -1.3)
	lamp.add_child(light)


## Ajoute un élément de décor à la salle et au voile : il reste caché tant
## que sa partie de la salle est voilée.
func add_decor(node: Node3D) -> void:
	add_child(node)
	_pieces.append(node)


func _build_veil() -> void:
	_veil = MeshInstance3D.new()
	_veil.name = "Veil"
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	_veil.mesh = b
	_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.BLACK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_veil.material_override = mat
	add_child(_veil)
	set_veil(1.0, Vector3.RIGHT)


## Visuel + collision primitive séparée, et le visuel en métadonnée pour que
## la caméra puisse l'estomper. MeshInstance3D plutôt que CSG : il y a
## beaucoup de tronçons, et un CSG recalcule son maillage à la création.
## veiled : le voile masque ce morceau (tout sauf le sol).
## visual_h : hauteur visible, posée sur le sol (-1 = celle de la collision,
## 0 = aucun visuel, collision seule). Renvoie le visuel (null si aucun).
func _add_box(n: String, size: Vector3, pos: Vector3, color: Color, veiled: bool = true, visual_h: float = -1.0) -> MeshInstance3D:
	var box: MeshInstance3D = null
	if visual_h != 0.0:
		box = MeshInstance3D.new()
		box.name = n
		var mesh := BoxMesh.new()
		mesh.size = size
		box.position = pos
		if visual_h > 0.0:
			mesh.size.y = visual_h
			box.position.y = pos.y - size.y * 0.5 + visual_h * 0.5
		box.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		box.material_override = mat
		add_child(box)
		if veiled:
			_pieces.append(box)

	var body := StaticBody3D.new()
	body.name = n + "Collision"
	body.position = pos
	body.set_meta("visual", box)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	return box


# ---------------------------------------------------------------- VOILE

## k = part de la salle couverte (1 = toute noire, 0 = visible).
## anchor = côté auquel le voile reste accroché pendant qu'il rétrécit/grandit.
func set_veil(k: float, anchor: Vector3) -> void:
	_veil_k = clampf(k, 0.0, 1.0)
	_veil_anchor = anchor
	_apply_veil(_veil_k)


func animate_veil(from_k: float, to_k: float, anchor: Vector3, duration: float) -> void:
	if _veil_tween != null and _veil_tween.is_running():
		_veil_tween.kill()
	_veil_anchor = anchor
	_apply_veil(from_k)
	_veil_tween = create_tween()
	_veil_tween.tween_method(_apply_veil, from_k, to_k, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _apply_veil(k: float) -> void:
	_veil_k = k
	var sp: Vector2 = spacing
	var along_x: bool = absf(_veil_anchor.x) > 0.5
	var side: float = signf(_veil_anchor.x) if along_x else signf(_veil_anchor.z)
	var full: float = sp.x if along_x else sp.y
	var length: float = full * k
	# Le voile couvre [edge, full/2] le long de l'axe, côté ancre
	var edge: float = full * 0.5 - length

	for piece in _pieces:
		if not is_instance_valid(piece):
			continue
		# Position relative à la salle : certaines pièces (moitiés de porte)
		# appartiennent au Dungeon, pas à la salle.
		var lp: Vector3 = to_local(piece.global_position)
		var along: float = (lp.x if along_x else lp.z) * side
		piece.visible = along < edge

	if k <= 0.001:
		_veil.visible = false
		return
	_veil.visible = true

	var h: float = 0.04
	var s := Vector3(sp.x, h, sp.y)
	var p := Vector3(0.0, h * 0.5 + 0.005, 0.0)
	var offset: float = (full - length) * 0.5
	if along_x:
		s.x = length
		p.x = side * offset
	else:
		s.z = length
		p.z = side * offset
	_veil.scale = s
	_veil.position = p


## Ajoute au voile de cette salle un objet qui n'est pas son enfant.
func add_veil_piece(piece: Node3D) -> void:
	_pieces.append(piece)
	_apply_veil(_veil_k)


# ---------------------------------------------------------------- ÉTAT

## Rectangle (x, z) de l'intérieur de la salle, en coordonnées monde.
func get_bounds() -> Rect2:
	return Rect2(
		global_position.x - room_size.x * 0.5,
		global_position.z - room_size.y * 0.5,
		room_size.x, room_size.y
	)


## Vrai si le point est dans l'emprise de la salle (murs compris).
func contains(p: Vector3) -> bool:
	var sp: Vector2 = spacing
	var l: Vector3 = p - global_position
	return absf(l.x) <= sp.x * 0.5 and absf(l.z) <= sp.y * 0.5


## Le joueur vient d'entrer. Renvoie le nombre d'ennemis apparus.
func activate(entry: Vector3) -> int:
	is_active = true
	_activation += 1
	_wave = 0
	if is_cleared and not data.respawn_enemies:
		if _rematch_ready():
			_spawn_rematch()
			return _alive
		return 0

	if data.waves.is_empty():
		_spawn_random(entry)
	else:
		_spawn_wave(0)
	if _alive == 0:
		_on_all_dead()
	return _alive


## Le joueur est parti : les survivants disparaissent (ils reviendront).
func deactivate() -> void:
	is_active = false
	_activation += 1   # une vague en attente ne doit pas apparaître après le départ
	_rematch = false
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	_alive = 0


# ---------------------------------------------------------------- ENNEMIS

## Une vague dessinée : chaque lettre fait apparaître un ennemi sur sa case.
func _spawn_wave(index: int) -> void:
	_enemies.clear()
	_alive = 0
	var g: Dictionary = RoomData.parse_grid(data.waves[index])
	for c in g["cells"]:
		var kind: String = WAVE_KINDS.get(c["ch"], "")
		if kind == "":
			push_warning("%s : lettre '%s' inconnue dans la vague %d (c s b m B .)" % [name, c["ch"], index + 1])
			continue
		var dims: Vector2i = grid_dims()
		if c["col"] >= dims.x or c["row"] >= dims.y:
			continue   # hors de la salle (dessin plus grand que la grille)
		_spawn(kind, grid_to_local(c["col"], c["row"], dims.x, dims.y))


func _spawn_random(entry: Vector3) -> void:
	_enemies.clear()
	_alive = 0
	var local_entry: Vector3 = to_local(entry)

	for i in data.chargers:
		_spawn("charger", _random_point(local_entry))
	for i in data.shooters:
		_spawn("shooter", _random_point(local_entry))
	for i in data.bombers:
		_spawn("bomber", _random_point(local_entry))
	for i in data.melees:
		_spawn("melee", _random_point(local_entry))
	if data.boss:
		# Le boss se pose au centre, ou de l'autre côté si le joueur y est déjà
		var p := Vector3.ZERO
		if local_entry.length() < data.spawn_min_from_player:
			p = -local_entry.normalized() * room_size.y * 0.25
		_spawn("boss", p)


## Revanche : salle de boss déjà gagnée, objet déclencheur en poche, et
## revanche pas encore remportée.
func _rematch_ready() -> bool:
	if Engine.is_editor_hint() or data.boss_rematch_item == &"":
		return false
	if not _has_boss():
		return false
	return Inventory.has_key_item(data.boss_rematch_item) and not Inventory.has_flag(_rematch_id())


func _has_boss() -> bool:
	if data.boss:
		return true
	for w in data.waves:
		if w.contains("B"):
			return true
	return false


func _rematch_id() -> String:
	return "%s|boss_rematch" % _chest_id()


## Seul le boss revient, sur sa case « B » (au centre sinon).
func _spawn_rematch() -> void:
	_enemies.clear()
	_alive = 0
	_rematch = true
	var pos := Vector3.ZERO
	var dims: Vector2i = grid_dims()
	for w in data.waves:
		for c in RoomData.parse_grid(w)["cells"]:
			if c["ch"] == "B":
				pos = grid_to_local(c["col"], c["row"], dims.x, dims.y)
	_spawn("boss", pos, {"rematch": true})


func _spawn(kind: String, local_pos: Vector3, props: Dictionary = {}) -> void:
	var scene: PackedScene = scenes.get(kind)
	if scene == null:
		push_warning("%s : scène '%s' manquante dans le Dungeon" % [name, kind])
		return
	# Compté tout de suite : la vague n'est pas finie tant qu'un ennemi
	# annoncé n'est pas encore apparu (portes, vague suivante...).
	_alive += 1
	var token: int = _activation

	# Annonce au sol, puis apparition. Si le joueur sort entre-temps,
	# deactivate() change _activation et l'ennemi n'apparaît jamais.
	var marker := SpawnMarker.new()
	add_child(marker)
	marker.position = local_pos
	marker.play(spawn_telegraph_time, 1.4 if kind == "boss" else 0.7)
	await get_tree().create_timer(spawn_telegraph_time, false).timeout
	if token != _activation or not is_active:
		return

	var e: Node3D = scene.instantiate()
	# Avant add_child : les ennemis lisent player_path dans leur _ready
	e.set("player_path", player.get_path())
	for k in props:
		e.set(k, props[k])
	add_child(e)
	e.position = local_pos + Vector3.UP * 0.05
	_enemies.append(e)
	if e.has_signal("died"):
		e.died.connect(_on_enemy_died)


## Un point libre : loin des murs, du joueur, des piliers et du coffre.
func _random_point(local_entry: Vector3) -> Vector3:
	var margin: float = 2.5
	var hx: float = room_size.x * 0.5 - margin
	var hz: float = room_size.y * 0.5 - margin
	var best := Vector3.ZERO
	var best_d: float = -1.0

	for attempt in 30:
		var p := Vector3(randf_range(-hx, hx), 0.0, randf_range(-hz, hz))
		if _blocked(p):
			continue
		var d: float = Vector2(p.x - local_entry.x, p.z - local_entry.z).length()
		if d >= data.spawn_min_from_player:
			return p
		if d > best_d:
			best_d = d
			best = p
	return best


func _blocked(p: Vector3) -> bool:
	for pl in _pillars:
		if Vector2(p.x - pl.x, p.z - pl.z).length() < _pillar_radius + 1.0:
			return true
	if _chest != null and Vector2(p.x - _chest_pos.x, p.z - _chest_pos.z).length() < 2.0:
		return true
	return false


func _on_enemy_died() -> void:
	_alive -= 1
	if _alive > 0 or not is_active:
		return
	if _rematch:
		# Revanche gagnée : elle ne revient plus, même après une mort
		_rematch = false
		Inventory.set_flag(_rematch_id())
		Sfx.play_ui("room_clear")
		_on_all_dead()
		return
	if _wave + 1 < data.waves.size():
		_next_wave()
	else:
		Sfx.play_ui("room_clear")
		_on_all_dead()


func _next_wave() -> void:
	var token: int = _activation
	await get_tree().create_timer(data.wave_delay).timeout
	# Le joueur est peut-être sorti (ou revenu) entre-temps
	if token != _activation or not is_active:
		return
	_wave += 1
	_spawn_wave(_wave)
	if _alive == 0:
		# Vague vide (ou lettres inconnues) : on passe directement à la suite
		_alive = 1
		_on_enemy_died()


func _on_all_dead() -> void:
	is_cleared = true
	_give_reward()
	cleared.emit(self)


# ---------------------------------------------------------------- RÉCOMPENSE

func _give_reward() -> void:
	match data.key_source:
		RoomData.KeySource.ON_CLEAR:
			# Plus de clé posée au sol : un coffre apparaît à la place de la
			# clé (case « k »), ou sur la case « C », sinon au centre.
			if _chest == null and not _key_given:
				var pos: Vector3 = _key_pos if data.layout.contains("k") else _chest_pos
				_spawn_chest.call_deferred(pos, true)
		RoomData.KeySource.CHEST_ON_CLEAR:
			if _chest == null and _has_chest():
				_spawn_chest.call_deferred(_chest_pos, true)


## Remet la salle dans l'état mémorisé par le donjon après une mort :
## nettoyée (plus d'ennemis), et coffre déjà présent / déjà ouvert.
func restore_progress(cleared: bool, key_given: bool) -> void:
	is_cleared = cleared
	_key_given = key_given
	# Coffre qui n'apparaît qu'à la fin du combat : il est déjà là
	if cleared and _chest == null:
		match data.key_source:
			RoomData.KeySource.ON_CLEAR:
				_spawn_chest(_key_pos if data.layout.contains("k") else _chest_pos)
			RoomData.KeySource.CHEST_ON_CLEAR:
				if _has_chest():
					_spawn_chest(_chest_pos)
	# Clé déjà prise : le coffre reste ouvert et vide
	if key_given and _chest != null and not _chest.is_open:
		_chest.set_open_instant()


## Une borne de recharge (checkpoint) par case « S » du décor.
func _spawn_charge_posts() -> void:
	for i in _post_positions.size():
		var post := ChargePost.new()
		post.name = "ChargePost%d" % i
		post.position = _post_positions[i]   # avant add_child : la borne lit sa position dans _ready
		add_child(post)
		_pieces.append(post)


## Un piédestal par case « R » du décor. Son objet n'est donné qu'une fois
## pour toute la partie (mémorisé comme un coffre ouvert).
func _spawn_pedestals() -> void:
	for i in _pedestal_positions.size():
		var ped := RelicPedestal.new()
		ped.name = "Pedestal%d" % i
		ped.item = data.pedestal_item   # vide = le prisme
		ped.position = _pedestal_positions[i]
		if not Engine.is_editor_hint():
			ped.save_id = "%s|R%d" % [_chest_id(), i]
		add_child(ped)
		_pieces.append(ped)


## Coffre seulement si le décor en contient un.
func _has_chest() -> bool:
	return data.layout.contains("C")


func _spawn_chest(local_pos: Vector3, animated: bool = false) -> void:
	_chest = DungeonChest.new()
	_chest.name = "Chest"
	_chest.item = data.chest_item   # vide = petite clé
	add_child(_chest)
	_chest.position = local_pos
	_chest.opened.connect(_on_chest_opened)
	_pieces.append(_chest)
	_apply_veil(_veil_k)
	# Objet déjà pris lors d'une vie précédente : le coffre reste ouvert et vide
	if _chest_persists() and not Engine.is_editor_hint() and Inventory.is_chest_opened(_chest_id()):
		_chest.set_open_instant()
		return
	if animated and not Engine.is_editor_hint():
		_chest.appear()
		_push_player_out_of(_chest)


## Un coffre qui apparaît sur le joueur l'enfermerait dans sa boîte de
## collision : on le décale juste à côté.
func _push_player_out_of(chest: DungeonChest) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var min_d: float = maxf(chest.size.x, chest.size.z) * 0.5 + 0.6
	var d := p.global_position - chest.global_position
	d.y = 0.0
	if d.length() >= min_d:
		return
	if d.length_squared() < 0.0001:
		d = Vector3.BACK   # côté caméra
	p.global_position = chest.global_position + d.normalized() * min_d + Vector3.UP * (p.global_position.y - chest.global_position.y)


## Le coffre a été ouvert et l'objet présenté : on applique son effet.
func _on_chest_opened(item: ItemData) -> void:
	if _chest_persists():
		Inventory.mark_chest_opened(_chest_id())
	if item.id == &"key" and not _key_given:
		_key_given = true
		_on_key_collected()


## Les petites clés se redonnent à chaque rechargement (le donjon repart de
## zéro) ; tout autre objet n'est donné qu'une fois pour toute la partie.
func _chest_persists() -> bool:
	return data.chest_item != null and data.chest_item.category != ItemData.Category.SMALL_KEY


func _chest_id() -> String:
	var scene: Node = get_tree().current_scene
	var path: String = scene.scene_file_path if scene != null else ""
	return "%s|%d,%d" % [path, cell.x, cell.y]


func _on_key_collected() -> void:
	key_collected.emit(self)
