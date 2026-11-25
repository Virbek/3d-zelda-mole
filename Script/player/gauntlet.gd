extends Node3D
class_name Gauntlet

## Gantelet mécanique de la taupe, construit en primitives (pas de modèle
## importé) : poing rouillé, jointures d'acier, manchette à rayures, deux
## pistons et un petit écran cyan sur le poignet.
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

## Côté de la main : -1 gauche, +1 droite. Le pouce est du côté intérieur.
var side: float = 1.0
var outline_width: float = 0.008

## Pièces qui reçoivent la lueur de charge (voir set_overlay).
var _parts: Array[MeshInstance3D] = []


static func create(hand_side: float, outline: float = 0.008) -> Gauntlet:
	var g := Gauntlet.new()
	g.side = hand_side
	g.outline_width = outline
	g.name = "Gauntlet"
	g._build()
	return g


## Applique (ou retire, avec null) un matériau par-dessus toutes les pièces.
## Sert au flash blanc de la charge pleine.
func set_overlay(mat: Material) -> void:
	for p in _parts:
		p.material_overlay = mat


# ---------------------------------------------------------------- CONSTRUCTION

func _build() -> void:
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
	_box(Vector3(0.22, 0.06, 0.05), Vector3(0.0, -0.06, -0.165), STEEL_DARK)

	# --- Pouce, côté intérieur ---
	var thumb := _box(Vector3(0.07, 0.07, 0.13), Vector3(inner * 0.15, -0.02, -0.08), STEEL)
	thumb.rotation.y = deg_to_rad(-12.0) * inner

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
	return ToonBuilder.toon_material(color, outline_width if outlined else 0.0)


## L'écran brille un peu, sans être affecté par l'éclairage.
func _screen_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = SCREEN
	return mat
