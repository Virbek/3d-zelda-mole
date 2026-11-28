extends RefCounted
class_name ToonBuilder

## Outils partagés pour construire des modèles en primitives avec le rendu
## toon du projet (3 tons + contour noir). Utilisé par le gantelet du joueur
## et les ennemis insectes.

const TOON_SHADER_PATH := "res://Shader/toon.gdshader"
const OUTLINE_SHADER_PATH := "res://Shader/outline.gdshader"

## Couleur d'ombre : brun chaud, pour rester dans la palette rouille et sable.
const SHADOW := Color(0.28, 0.18, 0.14)

# Palette commune
const RUST := Color("#a8622f")
const RUST_DARK := Color("#6e3a1e")
const STEEL := Color("#8a8d8f")
const STEEL_DARK := Color("#4a4c4b")
const STEEL_LIGHT := Color("#c7c7cc")
const HAZARD := Color("#e0a23a")
const SCREEN := Color("#5fe1ff")
const THREAT := Color("#ff7a2a")


## rim : liseré clair sur les bords côté lumière (personnages et ennemis ;
## pas le décor, où un grand sol vu en rasant s'éclaircirait en entier).
## grime : salissures du décor (taches de rouille, pied plus sombre, grain).
## Objets fixes seulement : le motif est calculé en coordonnées monde.
static func toon_material(color: Color, outline_width: float = 0.01, rim: bool = false, grime: bool = false) -> Material:
	var shader: Shader = load(TOON_SHADER_PATH) as Shader
	if shader == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = color
		return fallback

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("use_texture", false)
	mat.set_shader_parameter("shadow_color", SHADOW)
	if rim:
		mat.set_shader_parameter("rim_amount", 1.0)
	if grime:
		mat.set_shader_parameter("grime", 1.0)

	if outline_width > 0.0:
		var outline_shader: Shader = load(OUTLINE_SHADER_PATH) as Shader
		if outline_shader != null:
			var outline := ShaderMaterial.new()
			outline.shader = outline_shader
			outline.set_shader_parameter("outline_width", outline_width)
			mat.next_pass = outline
	return mat


## Matériau non éclairé : yeux, écrans, voyants.
static func glow_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## Cylindre low poly (facettes visibles, c'est voulu).
static func cylinder(radius: float, height: float, segments: int = 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m
