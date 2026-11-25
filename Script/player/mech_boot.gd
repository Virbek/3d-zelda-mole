extends Node3D
class_name MechBoot

## Botte mécanique de la taupe, assortie aux gantelets : chaussure rouillée,
## coque d'acier sur la pointe, semelle épaisse, cheville cerclée d'une bande
## de danger, piston au talon et voyant cyan sur le côté extérieur.
##
## Origine au sol (sous la semelle), avant en -Z. Cotes en mètres : le rig
## compense l'échelle du nœud parent.

var side: float = 1.0          ## -1 pied gauche, +1 pied droit
var outline_width: float = 0.008


static func create(foot_side: float, outline: float = 0.008) -> MechBoot:
	var b := MechBoot.new()
	b.side = foot_side
	b.outline_width = outline
	b.name = "MechBoot"
	b._build()
	return b


func _build() -> void:
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
	m.material_override = ToonBuilder.toon_material(color, outline_width)
	add_child(m)
	return m
