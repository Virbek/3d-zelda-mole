extends Node3D
class_name DungBeetleModel

## Bousier des dunes : apparence de l'ennemi chargeur, en primitives toon.
## Insecte VIVANT (pas de métal) : carapace vert-noir bombée, tête en pelle
## dentelée qui sert à façonner le boulet, six pattes épineuses, les deux
## pattes avant longues et plates pour pousser.
##
## Origine au sol, avant en -Z (comme l'ennemi qui le porte). Le script de
## l'ennemi pilote :
##   - set_walk(speed, delta) : balancement des pattes
##   - set_push(k)            : 0 = debout, 1 = tête baissée, arrière levé
##                              (pose d'annonce et de poussée)
##   - set_tint(current, base): couleurs de télégraphe / coup / étourdissement
##   - set_eyes_threat(k)     : yeux ambre → orange quand il attaque
##   - set_shaping(t)         : pattes avant qui ramassent et tapotent le
##                              sable à tour de rôle (façonnage du boulet) ;
##                              t < 0 rend la main à set_push

const CHITIN := Color("#2f3a2a")        ## carapace vert-noir
const CHITIN_LIGHT := Color("#4c5e3e")  ## reflets des élytres
const CHITIN_DARK := Color("#1c2219")   ## dessous, pattes
const SHOVEL := Color("#5a4a2c")        ## bord de la pelle, terreux
const EYE := Color("#d9a441")           ## ambre

@export var outline_width: float = 0.012
@export var tint_strength: float = 0.7
@export var push_pitch_deg: float = 16.0   ## inclinaison du corps en poussée
@export var shaping_speed: float = 7.0     ## cadence des pattes avant pendant le façonnage

var _body_pivot: Node3D                 ## tout le corps : incliné par set_push
var _legs: Array[Node3D] = []
var _front_legs: Array[Node3D] = []
var _leg_phase: float = 0.0
var _push: float = 0.0
var _eye_mat: StandardMaterial3D
var _tinted: Array = []                 ## [ShaderMaterial, Color]


func _ready() -> void:
	_build()


# ---------------------------------------------------------------- PILOTAGE

func set_walk(speed: float, delta: float) -> void:
	_leg_phase += speed * 6.0 * delta
	var amp: float = clampf(speed / 3.0, 0.0, 1.0) * deg_to_rad(24.0)
	for i in _legs.size():
		var offset: float = 0.0 if i in [0, 3, 4] else PI
		_legs[i].rotation.x = sin(_leg_phase + offset) * amp


func set_push(k: float) -> void:
	_push = clampf(k, 0.0, 1.0)
	# Pivot au niveau des pattes avant : l'arrière se lève, la tête plonge
	_body_pivot.rotation.x = -deg_to_rad(push_pitch_deg) * _push
	for leg in _front_legs:
		leg.rotation.x = -deg_to_rad(35.0) * _push


## Façonnage : chaque patte avant décrit une boucle, en alternance avec
## l'autre. Elle s'abaisse et ratisse vers l'intérieur (ramasse le sable),
## puis remonte et vient tapoter le haut du boulet.
func set_shaping(t: float) -> void:
	if t < 0.0:
		for leg in _front_legs:
			leg.rotation.y = 0.0
			leg.rotation.z = 0.0
		return
	for i in _front_legs.size():
		var side: float = -1.0 if i == 0 else 1.0
		var ph: float = t * shaping_speed + (PI if i == 1 else 0.0)
		var leg: Node3D = _front_legs[i]
		# Haut / bas : levée pour tapoter, abaissée pour ramasser
		leg.rotation.x = -deg_to_rad(20.0) + sin(ph) * deg_to_rad(38.0)
		# Ratissage vers l'intérieur pendant la descente
		leg.rotation.y = cos(ph) * deg_to_rad(28.0) * side
		# Petit roulis : la palette racle le sol à plat
		leg.rotation.z = sin(ph + 0.6) * deg_to_rad(12.0) * side


func set_tint(current: Color, base: Color) -> void:
	var diff: float = absf(current.r - base.r) + absf(current.g - base.g) + absf(current.b - base.b)
	var w: float = clampf(diff / 0.6, 0.0, 1.0) * tint_strength
	for entry in _tinted:
		var mat: ShaderMaterial = entry[0]
		var c: Color = entry[1]
		mat.set_shader_parameter("albedo_color", c.lerp(Color(current, 1.0), w))


func set_eyes_threat(k: float) -> void:
	if _eye_mat != null:
		_eye_mat.albedo_color = EYE.lerp(ToonBuilder.THREAT, clampf(k, 0.0, 1.0))


# ---------------------------------------------------------------- CONSTRUCTION

func _build() -> void:
	var B := ToonBuilder

	_body_pivot = Node3D.new()
	_body_pivot.position = Vector3(0.0, 0.3, -0.35)   # charnière vers l'avant
	add_child(_body_pivot)
	var root := Node3D.new()
	root.position = -_body_pivot.position
	_body_pivot.add_child(root)

	# --- Abdomen bombé : deux élytres arrondies ---
	var abdomen := _part(_sphere(0.5, 0.36), Vector3(0.0, 0.48, 0.18), CHITIN, root)
	abdomen.scale = Vector3(1.0, 0.85, 1.15)
	# Sillon entre les élytres + reflets
	_part(B.box(Vector3(0.04, 0.05, 0.9)), Vector3(0.0, 0.79, 0.18), CHITIN_DARK, root)
	for side: float in [-1.0, 1.0]:
		var shine := _part(B.box(Vector3(0.18, 0.04, 0.5)), Vector3(0.2 * side, 0.76, 0.1), CHITIN_LIGHT, root)
		shine.rotation.z = deg_to_rad(14.0) * side

	# --- Thorax (pronotum) large et lisse ---
	var thorax := _part(_sphere(0.36, 0.26), Vector3(0.0, 0.5, -0.38), CHITIN, root)
	thorax.scale = Vector3(1.25, 0.8, 0.9)

	# --- Tête en pelle, bord dentelé ---
	var head := _part(B.box(Vector3(0.6, 0.12, 0.3)), Vector3(0.0, 0.4, -0.68), CHITIN_DARK, root)
	head.rotation.x = deg_to_rad(12.0)
	for i in 5:
		var x: float = -0.24 + 0.12 * float(i)
		var tooth := _part(B.box(Vector3(0.07, 0.06, 0.12)), Vector3(x, 0.36, -0.86), SHOVEL, root)
		tooth.rotation.x = deg_to_rad(20.0)

	# Yeux ambre de chaque côté de la pelle
	_eye_mat = B.glow_material(EYE)
	for x: float in [-0.27, 0.27]:
		var eye := MeshInstance3D.new()
		eye.mesh = B.box(Vector3(0.07, 0.07, 0.07))
		eye.position = Vector3(x, 0.47, -0.62)
		eye.material_override = _eye_mat
		root.add_child(eye)

	# Antennes courtes en massue
	for side: float in [-1.0, 1.0]:
		var ant := _part(B.box(Vector3(0.03, 0.03, 0.2)), Vector3(0.16 * side, 0.52, -0.8), CHITIN_DARK, root)
		ant.rotation = Vector3(deg_to_rad(30.0), deg_to_rad(25.0) * side, 0.0)
		_part(B.box(Vector3(0.07, 0.05, 0.07)), Vector3(0.2 * side, 0.58, -0.88), SHOVEL, root)

	# --- Six pattes épineuses ---
	# Avant : longues et plates, tendues vers l'avant pour pousser le boulet
	for z: float in [-0.42, -0.02, 0.38]:
		for side: float in [-1.0, 1.0]:
			var hip := Node3D.new()
			hip.position = Vector3(0.34 * side, 0.36, z)
			root.add_child(hip)
			_legs.append(hip)
			var front: bool = z < -0.3
			if front:
				_front_legs.append(hip)
				var arm := _part(B.box(Vector3(0.09, 0.07, 0.42)), Vector3(0.08 * side, -0.06, -0.2), CHITIN_DARK, hip)
				arm.rotation.y = deg_to_rad(-12.0) * side
				# Râteau plat au bout
				_part(B.box(Vector3(0.14, 0.05, 0.1)), Vector3(0.12 * side, -0.12, -0.42), SHOVEL, hip)
				continue
			var thigh := _part(B.box(Vector3(0.34, 0.07, 0.07)), Vector3(0.15 * side, 0.06, 0.0), CHITIN_DARK, hip)
			thigh.rotation.z = deg_to_rad(30.0) * side
			var shin := _part(B.box(Vector3(0.06, 0.46, 0.06)), Vector3(0.38 * side, -0.14, 0.04 if z > 0.0 else 0.0), CHITIN_DARK, hip)
			shin.rotation.z = deg_to_rad(18.0) * side
			# Épines
			for k in 2:
				var spine := _part(B.box(Vector3(0.1, 0.025, 0.025)), Vector3(0.42 * side, -0.05 - 0.13 * float(k), 0.0), CHITIN_LIGHT, hip)
				spine.rotation.z = deg_to_rad(-25.0) * side


func _sphere(radius: float, height_half: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = height_half * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


func _part(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	var mat: Material = ToonBuilder.toon_material(color, outline_width)
	m.material_override = mat
	if mat is ShaderMaterial:
		_tinted.append([mat, color])
	parent.add_child(m)
	return m
