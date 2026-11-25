extends Node3D
class_name MoleOutfit

## Tenue d'aventurière du désert de la taupe, en primitives : foulard rouge
## noué sous le museau, ceinture de cuir avec gourde, petit sac en toile
## (couverture roulée, mini-lanterne cyan).
##
## Rangée sous le nœud Body du rig : repère du corps, avant en -Z, haut en +Y.
## Mesures prises sur le modèle Mole2 : le corps est un cône bas-poly, rayon
## 0,39 m à y = -0,7 et 0,30 m à y = 0 (base du museau). Voir body_radius().

const LEATHER := Color("#5a3a22")
const CANVAS := Color("#8c7a52")
const CANVAS_DARK := Color("#5e5034")
const SCARF := Color("#b3261e")
const SCARF_DARK := Color("#7a1712")
const SAND := Color("#c9a26b")
const HAT := Color("#8a4f2a")
const HAT_DARK := Color("#5a3a22")
const LENS := Color("#111111")

var outline_width: float = 0.008

## Pente du cône du corps (inclinaison de la surface par rapport à la verticale)
const BODY_SLOPE := 0.09 / 0.7
## Écart entre le corps et le foulard / la ceinture : le corps est bas-poly,
## ses arêtes dépassent un anneau trop serré.
const SCARF_MARGIN := 0.05
const BELT_MARGIN := 0.04


## Rayon de la surface du corps à la hauteur y (repère Body).
static func body_radius(y: float) -> float:
	return 0.39 - BODY_SLOPE * (y + 0.7)


static func create(outline: float = 0.008) -> MoleOutfit:
	var o := MoleOutfit.new()
	o.outline_width = outline
	o.name = "Outfit"
	o._build()
	return o


func _build() -> void:
	_build_hat()
	_build_scarf()
	_build_belt()
	_build_backpack()


# ---------------------------------------------------------------- CHAPEAU

## Chapeau d'aventurière : calotte bas-poly pincée sur le dessus, bord épais
## (un bord trop fin fait des artefacts d'ombre) relevé sur les côtés,
## bandeau sombre, et les lunettes de protection posées sur la calotte.
## Le haut de la tête est vers y = 0,44, rayon ~0,26.
func _build_hat() -> void:
	var B := ToonBuilder
	var base_y: float = 0.38

	# Bord : disque bas-poly un peu ovale (plus long devant/derrière)
	var brim := _part(_frustum(0.44, 0.46, 0.05, 12), Vector3(0.0, base_y, 0.0), HAT)
	brim.scale = Vector3(1.0, 1.0, 1.12)
	# Côtés relevés, façon chapeau de cow-boy : fines languettes ovales
	# (disque aplati puis étiré vers l'avant et l'arrière), pour un bord arrondi
	for side: float in [-1.0, 1.0]:
		var flap := _part(_frustum(0.1, 0.1, 0.03, 12), Vector3(0.4 * side, base_y + 0.035, 0.0), HAT)
		flap.scale = Vector3(1.0, 1.0, 2.4)
		flap.rotation.z = deg_to_rad(24.0) * side

	# Calotte : tronc de cône, puis pli sur le dessus
	var crown_h: float = 0.25
	var crown_y: float = base_y + 0.025 + crown_h * 0.5
	_part(_frustum(0.2, 0.25, crown_h, 10), Vector3(0.0, crown_y, 0.0), HAT)
	_part(B.box(Vector3(0.05, 0.03, 0.3)), Vector3(0.0, base_y + 0.025 + crown_h + 0.005, 0.0), HAT_DARK)

	# Bandeau sombre au pied de la calotte
	_part(_frustum(0.248, 0.258, 0.06, 10), Vector3(0.0, base_y + 0.06, 0.0), HAT_DARK)

	# Lunettes de protection posées sur l'avant de la calotte
	var gy: float = crown_y + 0.02
	# Sangle qui fait le tour de la calotte
	_part(_frustum(0.218, 0.222, 0.025, 10), Vector3(0.0, gy, 0.0), LEATHER, false)
	for x: float in [-0.075, 0.075]:
		var z: float = -0.225
		var rim := _part(B.cylinder(0.058, 0.05, 10), Vector3(x, gy, z), B.STEEL_DARK)
		rim.rotation.x = PI * 0.5
		var lens := _part(B.cylinder(0.044, 0.012, 10), Vector3(x, gy, z - 0.027), LENS, false)
		lens.rotation.x = PI * 0.5
	# Pont entre les deux verres
	_part(B.box(Vector3(0.05, 0.02, 0.03)), Vector3(0.0, gy, -0.24), B.STEEL_DARK, false)


## Tronc de cône bas-poly (bas plus large que le haut).
func _frustum(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


# ---------------------------------------------------------------- FOULARD

func _build_scarf() -> void:
	var B := ToonBuilder
	var y: float = -0.12   # juste sous le museau
	var h: float = 0.13
	# Cône tronqué qui épouse le corps (plus étroit en haut)
	var ring := CylinderMesh.new()
	ring.top_radius = body_radius(y + h * 0.5) + SCARF_MARGIN
	ring.bottom_radius = body_radius(y - h * 0.5) + SCARF_MARGIN
	ring.height = h
	ring.radial_segments = 14
	ring.rings = 1
	_part(ring, Vector3(0.0, y, 0.0), SCARF)
	# Liseré sable, comme le motif du foulard du désert
	_part(B.cylinder(body_radius(y - 0.035) + SCARF_MARGIN + 0.006, 0.02, 14), Vector3(0.0, y - 0.035, 0.0), SAND, false)

	# Nœud et pans, sur le côté avant gauche (à 40° de l'axe avant)
	var a: float = deg_to_rad(40.0)
	var dir := Vector3(-sin(a), 0.0, -cos(a))
	var knot_r: float = body_radius(y) + SCARF_MARGIN + 0.04
	var knot := _part(B.box(Vector3(0.11, 0.1, 0.08)), dir * knot_r + Vector3(0.0, y - 0.01, 0.0), SCARF)
	knot.rotation.y = a
	var ty: float = y - 0.2
	var tail := _part(B.box(Vector3(0.1, 0.3, 0.035)), dir * (body_radius(ty) + 0.03) + Vector3(0.0, ty, 0.0), SCARF)
	tail.rotation = Vector3(deg_to_rad(7.0), a, deg_to_rad(-10.0))
	var tail2 := _part(B.box(Vector3(0.08, 0.22, 0.03)), (dir.rotated(Vector3.UP, deg_to_rad(-14.0))) * (body_radius(ty) + 0.04) + Vector3(0.0, ty + 0.03, 0.0), SCARF_DARK)
	tail2.rotation = Vector3(deg_to_rad(7.0), a - deg_to_rad(14.0), deg_to_rad(12.0))


# ---------------------------------------------------------------- CEINTURE

func _build_belt() -> void:
	var B := ToonBuilder
	var y: float = -0.6
	var r: float = body_radius(y) + BELT_MARGIN
	_part(B.cylinder(r, 0.08, 14), Vector3(0.0, y, 0.0), LEATHER)
	# Boucle d'acier devant
	_part(B.box(Vector3(0.11, 0.11, 0.03)), Vector3(0.0, y, -r - 0.01), B.STEEL)
	_part(B.box(Vector3(0.05, 0.05, 0.02)), Vector3(0.0, y, -r - 0.025), B.STEEL_DARK)

	# Gourde en acier, accrochée sur le côté droit
	var cx: float = r + 0.07
	_part(B.cylinder(0.075, 0.2, 10), Vector3(cx, y - 0.1, 0.06), B.STEEL)
	_part(B.cylinder(0.078, 0.03, 10), Vector3(cx, y - 0.06, 0.06), LEATHER)
	_part(B.cylinder(0.03, 0.05, 8), Vector3(cx, y + 0.02, 0.06), B.STEEL_DARK)


# ---------------------------------------------------------------- SAC

func _build_backpack() -> void:
	var B := ToonBuilder
	var cy: float = -0.24
	var tilt: float = atan(BODY_SLOPE)

	# Le sac est posé à plat contre le dos, incliné comme lui
	var pack := Node3D.new()
	pack.position = Vector3(0.0, cy, body_radius(cy))
	pack.rotation.x = -tilt
	add_child(pack)

	# Corps du sac + rabat
	_part(B.box(Vector3(0.42, 0.42, 0.18)), Vector3(0.0, 0.0, 0.09), CANVAS, true, pack)
	_part(B.box(Vector3(0.44, 0.12, 0.2)), Vector3(0.0, 0.16, 0.1), CANVAS_DARK, true, pack)
	# Poche à rayures de danger
	_part(B.box(Vector3(0.32, 0.16, 0.05)), Vector3(0.0, -0.08, 0.2), CANVAS_DARK, true, pack)
	_part(B.box(Vector3(0.33, 0.04, 0.052)), Vector3(0.0, -0.06, 0.2), B.HAZARD, true, pack)
	# Couverture rouge roulée sur le dessus
	var roll := _part(B.cylinder(0.075, 0.48, 10), Vector3(0.0, 0.29, 0.08), SCARF_DARK, true, pack)
	roll.rotation.z = PI * 0.5
	# Mini-lanterne cyan en bas du sac
	_part(B.box(Vector3(0.08, 0.1, 0.06)), Vector3(0.17, -0.26, 0.16), B.STEEL_DARK, true, pack)
	var glow := MeshInstance3D.new()
	glow.mesh = B.box(Vector3(0.05, 0.06, 0.065))
	glow.position = Vector3(0.17, -0.26, 0.16)
	glow.material_override = B.glow_material(B.SCREEN)
	pack.add_child(glow)

	# Bretelles visibles devant (le corps n'a ni bras ni épaules). Elles
	# partent sous le foulard (bas du foulard vers y = -0,19) et s'arrêtent
	# au-dessus de la ceinture (haut de la ceinture vers y = -0,56).
	var sy: float = -0.38
	for x: float in [-0.15, 0.15]:
		var strap := _part(B.box(Vector3(0.05, 0.3, 0.02)), Vector3(x, sy, -body_radius(sy) - 0.012), LEATHER)
		strap.rotation.x = tilt


func _part(mesh: Mesh, pos: Vector3, color: Color, outlined: bool = true, parent: Node3D = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.material_override = ToonBuilder.toon_material(color, outline_width if outlined else 0.0)
	(parent if parent != null else self).add_child(m)
	return m
