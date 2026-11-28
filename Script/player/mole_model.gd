extends Node3D
class_name MoleModel

## Corps et tenue de la taupe, modélisés dans Blender
## (art_src/blender/mole.py -> Asset/Model/Player/mole.glb) : corps en poire,
## chapeau plat avec lunettes, bandana de bandit, poncho rouge à vagues,
## ceinture et gourde, petit sac avec couverture roulée et lanterne.
##
## Remplace l'ancien Mole2.fbx + MoleOutfit. Repère du nœud Rig/Body.

const MODEL: PackedScene = preload("res://Asset/Model/Player/mole.glb")

const COLORS: Dictionary = {
	"fur": Color("#4e2e1d"), "fur_light": Color("#6e4832"), "mask": Color("#141010"),
	"nose": Color("#c0302a"), "whisker": Color("#141010"),
	"hat": Color("#8a4f2a"), "hat_dark": Color("#5a3a22"), "lens": Color("#111111"),
	"steel": Color("#8a8d8f"), "steel_dark": Color("#4a4c4b"),
	"leather": Color("#5a3a22"), "canvas": Color("#8c7a52"), "canvas_dark": Color("#5e5034"),
	"scarf_dark": Color("#7a1712"),
	"poncho": Color("#a3261d"), "poncho_light": Color("#e8d3a2"), "poncho_dark": Color("#4a1410"),
	"bandana": Color("#2c3a52"), "bandana_dot": Color("#e8d3a2"),
}
const GLOW: Dictionary = {
	"eye": Color("#e8d9b0"),
	"lantern": Color("#5fe1ff"),
}

## Rayon extérieur (corps ou poncho) selon la hauteur, relevé sur le profil
## de mole.py (SLIM = 0.84). x = hauteur, y = rayon. À refaire si on change
## la silhouette dans Blender.
const RADIUS_TABLE: Array[Vector2] = [
	Vector2(-0.72, 0.0), Vector2(-0.66, 0.275), Vector2(-0.60, 0.328), Vector2(-0.54, 0.353),
	Vector2(-0.48, 0.372), Vector2(-0.42, 0.378), Vector2(-0.36, 0.47), Vector2(-0.30, 0.474),
	Vector2(-0.24, 0.449), Vector2(-0.18, 0.428), Vector2(-0.12, 0.408), Vector2(-0.06, 0.384),
	Vector2(0.00, 0.364), Vector2(0.06, 0.346), Vector2(0.12, 0.316), Vector2(0.18, 0.307),
	Vector2(0.24, 0.298), Vector2(0.30, 0.286), Vector2(0.36, 0.274), Vector2(0.42, 0.242),
	Vector2(0.48, 0.2), Vector2(0.54, 0.05),
]

var outline_width: float = 0.008


static func create(outline: float = 0.008) -> MoleModel:
	var m := MoleModel.new()
	m.outline_width = outline
	m.name = "MoleModel"
	m._build()
	return m


## Rayon de la silhouette à la hauteur y (repère Body), pour écarter les mains.
static func body_radius(y: float) -> float:
	if y <= RADIUS_TABLE[0].x:
		return RADIUS_TABLE[0].y
	for i in RADIUS_TABLE.size() - 1:
		var a: Vector2 = RADIUS_TABLE[i]
		var b: Vector2 = RADIUS_TABLE[i + 1]
		if y <= b.x:
			return lerpf(a.y, b.y, (y - a.x) / (b.x - a.x))
	return RADIUS_TABLE[RADIUS_TABLE.size() - 1].y


func _build() -> void:
	var model: Node3D = MODEL.instantiate() as Node3D
	add_child(model)
	ModelSkin.apply(model, COLORS, GLOW, outline_width, ["whisker"])
