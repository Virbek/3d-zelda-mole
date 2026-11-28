extends RefCounted
class_name RoomDecor

## Décor d'une salle de la raffinerie ensevelie, construit par script :
##   - dunes de sable qui ont envahi les coins et le pied des murs
##   - poutres de soutènement contre les murs du fond et des côtés
##   - tuyaux rouillés le long du mur du fond
##   - bidons dans quelques coins (avec collision : ils arrêtent les tirs)
##
## Le mur côté caméra (+Z) reste nu : rien de haut ne doit cacher le joueur.
## Tout est tiré au sort à partir de la case de la salle : la même salle a
## toujours le même décor.

## Sable terne : sous les lampes orange, un sable vif vire à la lave
const SAND := Color("#9c8566")
const SAND_DARK := Color("#7d6a52")
const BEAM := Color("#5a3a22")
## Profondeur max dont une dune peut entrer dans le mur (le mur commun fait
## 1 m : chaque salle en porte 0,5 m, on reste en deçà).
const WALL_BITE := 0.35

var room: DungeonRoom
var rng := RandomNumberGenerator.new()
var hx: float
var hz: float
var _avoid: Array[Vector3] = []   ## piliers, coffre, clé : on ne pose rien dessus


static func build(r: DungeonRoom, avoid: Array[Vector3]) -> void:
	var d := RoomDecor.new()
	d.room = r
	d.hx = r.room_size.x * 0.5
	d.hz = r.room_size.y * 0.5
	d.rng.seed = hash(r.cell) + 1337
	d._avoid = avoid
	d._dunes()
	d._beams()
	d._pipes()
	d._barrels()


# ---------------------------------------------------------------- OUTILS

func _mesh(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.material_override = mat
	if parent != null:
		parent.add_child(m)
	else:
		room.add_decor(m)
	return m


func _toon(c: Color, outline: float = 0.0) -> Material:
	return ToonBuilder.toon_material(c, outline, false, true)


## Vrai si une porte occupe ce côté et que x (le long du mur) tombe dans son
## embrasure, avec une marge.
func _in_doorway(dir: Vector2i, along: float, margin: float = 1.0) -> bool:
	return room.doors.get(dir, false) and absf(along) < room.door_width * 0.5 + margin


func _free(p: Vector3, radius: float) -> bool:
	for a in _avoid:
		if Vector2(p.x - a.x, p.z - a.z).length() < radius:
			return false
	return true


# ---------------------------------------------------------------- DUNES

func _dunes() -> void:
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for c in corners:
		var r: float = rng.randf_range(1.5, 2.1)
		var sz: float = rng.randf_range(0.85, 1.15)
		_dune(Vector3(c.x * (hx - r + WALL_BITE), 0.0, c.y * (hz - r * sz + WALL_BITE)), r, sz)
	# Quelques tas le long des murs, hors des portes
	for i in 4:
		var side: int = rng.randi_range(0, 3)
		var t: float = rng.randf_range(-0.7, 0.7)
		var r: float = rng.randf_range(0.9, 1.4)
		var sz: float = rng.randf_range(0.85, 1.15)
		var p := Vector3.ZERO
		var dir := Vector2i.ZERO
		match side:
			0: p = Vector3(t * hx, 0.0, -hz + r * sz - WALL_BITE); dir = Vector2i(0, -1)
			1: p = Vector3(t * hx, 0.0, hz - r * sz + WALL_BITE); dir = Vector2i(0, 1)
			2: p = Vector3(-hx + r - WALL_BITE, 0.0, t * hz); dir = Vector2i(-1, 0)
			_: p = Vector3(hx - r + WALL_BITE, 0.0, t * hz); dir = Vector2i(1, 0)
		var along: float = p.x if dir.y != 0 else p.z
		if _in_doorway(dir, along, r + 0.8):
			continue
		_dune(p, r, sz)


## Dune alignée sur les axes de la salle (pas de rotation) : son étendue est
## connue, elle ne mord dans le mur que de WALL_BITE et ne ressort jamais
## dans la salle voisine (ni par-dessus son voile).
func _dune(p: Vector3, r: float, sz: float) -> void:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 10
	s.rings = 5
	var m := _mesh(s, p + Vector3(0.0, -0.05, 0.0), _toon(SAND if rng.randf() > 0.4 else SAND_DARK))
	m.scale = Vector3(r, rng.randf_range(0.25, 0.4), r * sz)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- POUTRES

## Étais verticaux contre les murs + poutre horizontale en haut du mur du fond.
func _beams() -> void:
	var h: float = room.wall_height
	var mat := _toon(BEAM, 0.01)
	var bracket := _toon(ToonBuilder.STEEL_DARK, 0.01)
	# Mur du fond (-Z) : étais tous les ~4 m, sauf devant la porte
	var xs: Array[float] = [-hx + 0.4, -hx * 0.25, hx * 0.25, hx - 0.4]
	for x in xs:
		if _in_doorway(Vector2i(0, -1), x, 0.6):
			continue
		_mesh(ToonBuilder.box(Vector3(0.3, h, 0.3)), Vector3(x, h * 0.5, -hz + 0.1), mat)
		_mesh(ToonBuilder.box(Vector3(0.36, 0.12, 0.36)), Vector3(x, h * 0.35, -hz + 0.1), bracket)
	# Poutre du haut, découpée pour que le voile la révèle progressivement
	var count: int = int(ceil(room.room_size.x / 2.0))
	var piece: float = room.room_size.x / float(count)
	for i in count:
		var x: float = -hx + piece * (float(i) + 0.5)
		if _in_doorway(Vector2i(0, -1), x, 0.2):
			continue
		_mesh(ToonBuilder.box(Vector3(piece, 0.28, 0.3)), Vector3(x, h - 0.2, -hz + 0.1), mat)
	# Murs latéraux : un étai au fond de chaque côté
	for side: float in [-1.0, 1.0]:
		var z: float = -hz * 0.75
		_mesh(ToonBuilder.box(Vector3(0.3, h, 0.3)), Vector3(side * (hx - 0.1), h * 0.5, z), mat)


# ---------------------------------------------------------------- TUYAUX

func _pipes() -> void:
	var y: float = 1.5
	var z: float = -hz + 0.28
	var rust := _toon(ToonBuilder.RUST, 0.01)
	var flange := _toon(ToonBuilder.STEEL_DARK, 0.01)
	var seg: float = 2.0
	var x: float = -hx + 0.6
	while x < hx - 0.6:
		var mid: float = x + seg * 0.5
		if not _in_doorway(Vector2i(0, -1), mid, 0.4):
			var pipe := _mesh(ToonBuilder.cylinder(0.12, seg), Vector3(mid, y, z), rust)
			pipe.rotation.z = PI * 0.5
			var f := _mesh(ToonBuilder.cylinder(0.17, 0.08), Vector3(x, y, z), flange)
			f.rotation.z = PI * 0.5
		x += seg
	# Un tuyau qui plonge dans le sol, près d'un coin du fond
	var vx: float = (-hx + 1.1) if rng.randf() > 0.5 else (hx - 1.1)
	_mesh(ToonBuilder.cylinder(0.12, y), Vector3(vx, y * 0.5, z), rust)


# ---------------------------------------------------------------- BIDONS

func _barrels() -> void:
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for c in corners:
		if rng.randf() < 0.45:
			continue
		var base := Vector3(c.x * (hx - 1.1), 0.0, c.y * (hz - 1.1))
		var n: int = rng.randi_range(1, 3)
		for i in n:
			var p: Vector3 = base + Vector3(-c.x * float(i % 2) * 0.75, 0.0, -c.y * floorf(float(i) / 2.0) * 0.75)
			if not _free(p, 1.6):
				continue
			_barrel(p)


func _barrel(p: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = p
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.36
	shape.height = 0.9
	col.shape = shape
	col.position.y = 0.45
	body.add_child(col)
	room.add_decor(body)

	var colors: Array[Color] = [ToonBuilder.RUST, ToonBuilder.RUST_DARK, Color("#5d5f3a")]
	var c: Color = colors[rng.randi_range(0, colors.size() - 1)]
	_mesh(ToonBuilder.cylinder(0.36, 0.9), Vector3(0.0, 0.45, 0.0), _toon(c, 0.01), body)
	_mesh(ToonBuilder.cylinder(0.37, 0.08), Vector3(0.0, 0.62, 0.0), _toon(ToonBuilder.HAZARD), body)
	_mesh(ToonBuilder.cylinder(0.37, 0.05), Vector3(0.0, 0.25, 0.0), _toon(ToonBuilder.STEEL_DARK), body)
	body.rotation.y = rng.randf_range(0.0, TAU)
