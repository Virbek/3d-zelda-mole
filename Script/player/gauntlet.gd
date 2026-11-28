extends Node3D
class_name Gauntlet

## Gantelet mécanique de la taupe : poing rouillé, doigts d'acier, manchette
## à rayures, deux pistons et un petit écran cyan sur le poignet.
##
## Modèle Blender (art_src/blender/gear.py -> Asset/Model/Player/gauntlet.glb)
## quand use_model est vrai ; sinon l'ancienne version en primitives.
##
## Orienté comme la main qui le porte : l'avant (les jointures) est en -Z.
## Toutes les cotes sont en mètres, dans le repère monde : le rig compense
## l'échelle du nœud parent.
##
## Rendu toon du projet (3 tons + contour noir), palette « rouille et sable ».

const RUST := Color("#a8622f")
const RUST_DARK := Color("#6e3a1e")
const STEEL := Color("#8a8d8f")
const STEEL_DARK := Color("#4a4c4b")
const STEEL_LIGHT := Color("#c7c7cc")
const HAZARD := Color("#e0a23a")
const SCREEN := Color("#5fe1ff")

const MODEL: PackedScene = preload("res://Asset/Model/Player/gauntlet.glb")
## Modèle Blender (true) ou ancienne construction en primitives (false).
static var use_model: bool = true
## Doit suivre HAND_SCALE dans art_src/blender/gear.py
const MODEL_SCALE := 1.05

## Côté de la main : -1 gauche, +1 droite. Le pouce est du côté intérieur.
var side: float = 1.0
var outline_width: float = 0.008

## Pièces qui reçoivent la lueur de charge (voir set_overlay).
var _parts: Array[MeshInstance3D] = []
## Pièces visibles seulement poing fermé / seulement main ouverte.
var _fist_only: Array[Node3D] = []
var _open_only: Array[Node3D] = []


static func create(hand_side: float, outline: float = 0.008) -> Gauntlet:
	var g := Gauntlet.new()
	g.side = hand_side
	g.outline_width = outline
	g.name = "Gauntlet"
	g._build()
	return g


## Applique (ou retire, avec null) un matériau par-dessus toutes les pièces.
## Sert au flash blanc de la charge pleine.
## Point d'attache du filament électrique : arrière de la manchette.
## Avec le modèle Blender, suit son échelle (HAND_SCALE de gear.py).
func cuff_anchor() -> Vector3:
	if use_model:
		return Vector3(0.0, 0.0, 0.2 * MODEL_SCALE)
	return Vector3(0.0, 0.0, 0.2)


func set_overlay(mat: Material) -> void:
	for p in _parts:
		p.material_overlay = mat


## Main ouverte (doigts tendus, paume vers -Y) ou poing fermé.
func set_open(open: bool) -> void:
	for n in _fist_only:
		n.visible = not open
	for n in _open_only:
		n.visible = open


# ---------------------------------------------------------------- CONSTRUCTION

func _build() -> void:
	if use_model:
		_build_model()
	else:
		_build_primitives()


func _build_model() -> void:
	var s: String = "L" if side < 0.0 else "R"
	var part: Node3D = ModelSkin.extract(MODEL, "Gauntlet_" + s)
	add_child(part)
	var colors: Dictionary = {
		"rust": RUST, "rust_dark": RUST_DARK, "steel": STEEL,
		"steel_dark": STEEL_DARK, "steel_light": STEEL_LIGHT, "hazard": HAZARD,
	}
	_parts = ModelSkin.apply(part, colors, {"screen": SCREEN}, outline_width)
	var fist: Node3D = part.find_child("Fist_" + s, true, false) as Node3D
	var opened: Node3D = part.find_child("Open_" + s, true, false) as Node3D
	if fist != null:
		_fist_only.append(fist)
	if opened != null:
		_open_only.append(opened)
	set_open(false)


func _build_primitives() -> void:
	var inner: float = -side   # côté du pouce

	# --- Poing : le gros bloc rouillé ---
	_box(Vector3(0.26, 0.2, 0.18), Vector3(0.0, 0.0, -0.06), RUST)
	# Plaque de dessus, plus sombre : casse le bloc en deux volumes lisibles
	_box(Vector3(0.24, 0.04, 0.14), Vector3(0.0, 0.11, -0.05), RUST_DARK)

	# --- Jointures : quatre plaques d'acier qui portent l'impact ---
	for i in 4:
		var x: float = lerpf(-0.09, 0.09, float(i) / 3.0)
		_box(Vector3(0.055, 0.075, 0.06), Vector3(x, 0.03, -0.17), STEEL)
	# Doigts repliés sous les jointures
	_fist_only.append(_box(Vector3(0.22, 0.06, 0.05), Vector3(0.0, -0.06, -0.165), STEEL_DARK))

	# --- Pouce, côté intérieur ---
	var thumb := _box(Vector3(0.07, 0.07, 0.13), Vector3(inner * 0.15, -0.02, -0.08), STEEL)
	thumb.rotation.y = deg_to_rad(-12.0) * inner
	_fist_only.append(thumb)

	_build_open_hand(inner)

	# --- Manchette du poignet ---
	_cylinder(0.125, 0.18, Vector3(0.0, 0.0, 0.11), STEEL_DARK)
	# Bande à rayures de danger au bord de la manchette
	_cylinder(0.132, 0.035, Vector3(0.0, 0.0, 0.04), HAZARD)
	# Collerette arrière
	_cylinder(0.14, 0.03, Vector3(0.0, 0.0, 0.19), RUST_DARK)

	# --- Pistons : relient la manchette au poing, sur le dessus ---
	for x: float in [-0.07, 0.07]:
		_cylinder(0.022, 0.2, Vector3(x, 0.12, 0.04), STEEL_LIGHT)
		_cylinder(0.032, 0.06, Vector3(x, 0.12, 0.12), STEEL_DARK)

	# --- Écran cyan sur le poignet : « machine vivante » ---
	_box(Vector3(0.1, 0.025, 0.08), Vector3(0.0, 0.13, 0.13), STEEL_DARK)
	var screen := _box(Vector3(0.075, 0.012, 0.055), Vector3(0.0, 0.145, 0.13), SCREEN, false)
	screen.material_override = _screen_material()


## Main ouverte : quatre doigts tendus dans le prolongement des jointures,
## bouts légèrement relevés vers la paume (-Y), pouce écarté, et un petit
## émetteur cyan au creux de la paume. Cachée par défaut.
func _build_open_hand(inner: float) -> void:
	for i in 4:
		var x: float = lerpf(-0.09, 0.09, float(i) / 3.0)
		var spread: float = lerpf(-6.0, 6.0, float(i) / 3.0)
		var flen: float = 0.13 if i == 0 or i == 3 else 0.15
		var finger := Node3D.new()
		finger.position = Vector3(x, -0.06, -0.19)
		finger.rotation.y = deg_to_rad(-spread)
		add_child(finger)
		_open_only.append(finger)
		_box_in(finger, Vector3(0.05, 0.045, flen), Vector3(0.0, 0.0, -flen * 0.5), STEEL_DARK)
		# Phalange du bout, recourbée vers la paume : main en coupe
		var tip := Node3D.new()
		tip.position = Vector3(0.0, 0.0, -flen)
		tip.rotation.x = deg_to_rad(-35.0)
		finger.add_child(tip)
		_box_in(tip, Vector3(0.048, 0.042, 0.07), Vector3(0.0, 0.0, -0.035), STEEL)

	# Pouce écarté vers l'extérieur
	var thumb := Node3D.new()
	thumb.position = Vector3(inner * 0.13, -0.03, -0.07)
	thumb.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(40.0) * inner, 0.0)
	add_child(thumb)
	_open_only.append(thumb)
	_box_in(thumb, Vector3(0.065, 0.06, 0.15), Vector3(0.0, 0.0, -0.075), STEEL)

	# Émetteur au creux de la paume : la clé « flotte » au-dessus
	var ring := _cylinder(0.065, 0.02, Vector3(0.0, -0.105, -0.06), STEEL_DARK)
	ring.rotation = Vector3.ZERO
	_open_only.append(ring)
	var core := _cylinder(0.045, 0.012, Vector3(0.0, -0.115, -0.06), SCREEN)
	core.rotation = Vector3.ZERO
	core.material_override = _screen_material()
	_open_only.append(core)

	set_open(false)


func _box_in(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := _box(size, pos, color)
	remove_child(m)
	parent.add_child(m)
	return m


func _box(size: Vector3, pos: Vector3, color: Color, outlined: bool = true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(mesh, pos, Vector3.ZERO, color, outlined)


## Cylindre couché le long de Z (l'axe du bras).
func _cylinder(radius: float, length: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10   # low poly : les facettes se voient, c'est voulu
	mesh.rings = 1
	return _add(mesh, pos, Vector3(PI * 0.5, 0.0, 0.0), color, true)


func _add(mesh: Mesh, pos: Vector3, rot: Vector3, color: Color, outlined: bool) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.rotation = rot
	m.material_override = _toon_material(color, outlined)
	add_child(m)
	_parts.append(m)
	return m


func _toon_material(color: Color, outlined: bool) -> Material:
	return ToonBuilder.toon_material(color, outline_width if outlined else 0.0, true)


## L'écran brille un peu, sans être affecté par l'éclairage.
func _screen_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = SCREEN
	return mat
