extends Node3D
class_name MechBoot

## Botte mécanique de la taupe, assortie aux gantelets : chaussure rouillée,
## coque d'acier sur la pointe, semelle épaisse, cheville cerclée d'une bande
## de danger, piston au talon et voyant cyan sur le côté extérieur.
##
## Origine au sol (sous la semelle), avant en -Z. Cotes en mètres : le rig
## compense l'échelle du nœud parent.
##
## Modèle Blender (art_src/blender/gear.py -> Asset/Model/Player/boot.glb)
## quand use_model est vrai ; sinon l'ancienne version en primitives.

const MODEL: PackedScene = preload("res://Asset/Model/Player/boot.glb")
## Modèle Blender (true) ou ancienne construction en primitives (false).
static var use_model: bool = true
## Doit suivre BOOT_SCALE dans art_src/blender/gear.py
const MODEL_SCALE := 1.25

var side: float = 1.0          ## -1 pied gauche, +1 pied droit
var outline_width: float = 0.008


## Point d'attache du filament électrique : haut du manchon de cheville.
func ankle_anchor() -> Vector3:
	if use_model:
		return Vector3(0.0, 0.3, 0.06) * MODEL_SCALE
	return Vector3(0.0, 0.28, 0.06)


static func create(foot_side: float, outline: float = 0.008) -> MechBoot:
	var b := MechBoot.new()
	b.side = foot_side
	b.outline_width = outline
	b.name = "MechBoot"
	b._build()
	return b


func _build() -> void:
	if use_model:
		_build_model()
	else:
		_build_primitives()


func _build_model() -> void:
	var B := ToonBuilder
	var part: Node3D = ModelSkin.extract(MODEL, "Boot_" + ("L" if side < 0.0 else "R"))
	add_child(part)
	var colors: Dictionary = {
		"rust": B.RUST, "rust_dark": B.RUST_DARK, "steel": B.STEEL,
		"steel_dark": B.STEEL_DARK, "steel_light": B.STEEL_LIGHT, "hazard": B.HAZARD,
	}
	ModelSkin.apply(part, colors, {"screen": B.SCREEN}, outline_width)


func _build_primitives() -> void:
	var B := ToonBuilder

	# --- Semelle épaisse, qui dépasse un peu tout autour ---
	_part(B.box(Vector3(0.22, 0.05, 0.38)), Vector3(0.0, 0.025, -0.02), B.STEEL_DARK)
	# Crampons sous la semelle (vus de côté, ils épaississent la silhouette)
	for z: float in [-0.14, 0.0, 0.13]:
		_part(B.box(Vector3(0.2, 0.025, 0.05)), Vector3(0.0, 0.0, z), B.STEEL_DARK)

	# --- Chaussure rouillée ---
	_part(B.box(Vector3(0.19, 0.12, 0.28)), Vector3(0.0, 0.11, 0.01), B.RUST)
	# Languette plus sombre sur le dessus
	_part(B.box(Vector3(0.12, 0.04, 0.16)), Vector3(0.0, 0.18, -0.03), B.RUST_DARK)

	# --- Coque d'acier sur la pointe ---
	_part(B.box(Vector3(0.21, 0.1, 0.11)), Vector3(0.0, 0.09, -0.16), B.STEEL)

	# --- Cheville : manchon vertical + bande de danger ---
	_part(B.cylinder(0.095, 0.14), Vector3(0.0, 0.24, 0.06), B.STEEL_DARK)
	_part(B.cylinder(0.1, 0.03, 10), Vector3(0.0, 0.19, 0.06), B.HAZARD)

	# --- Piston au talon ---
	_part(B.cylinder(0.028, 0.14), Vector3(0.0, 0.13, 0.17), B.STEEL_LIGHT)
	_part(B.cylinder(0.04, 0.04), Vector3(0.0, 0.21, 0.17), B.STEEL_DARK)

	# --- Voyant cyan, côté extérieur ---
	var light := MeshInstance3D.new()
	light.mesh = B.box(Vector3(0.012, 0.035, 0.07))
	light.position = Vector3(0.1 * side, 0.12, 0.02)
	light.material_override = B.glow_material(B.SCREEN)
	add_child(light)


func _part(mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.material_override = ToonBuilder.toon_material(color, outline_width, true)
	add_child(m)
	return m
