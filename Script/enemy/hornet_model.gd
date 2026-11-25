extends Node3D
class_name HornetModel

## Frelon-perceur : apparence de l'ennemi tireur, construite en primitives.
## Petit robot volant : thorax et tête d'acier, yeux cyan, abdomen à rayures
## terminé par un dard, quatre ailes translucides qui battent vite.
##
## Origine au sol, avant en -Z. Le corps flotte à hover_height.
## Le script du tireur pilote :
##   - set_curl(k)    : 0 = abdomen derrière, 1 = recourbé sous le corps, dard
##                      pointé vers l'avant (pendant la visée et le tir)
##   - set_threat(k)  : rayures et yeux qui s'allument (télégraphe)
##   - set_tint(c, b) : couleurs de coup reçu / étourdissement
##   - fly(speed, delta) : battement d'ailes, flottement, inclinaison en vol

@export var outline_width: float = 0.01
@export var hover_height: float = 1.0
@export var curl_angle_deg: float = 140.0   ## rotation de l'abdomen recourbé
@export var tint_strength: float = 0.7

const STRIPE_REST := Color("#c8743a")
const STRIPE_HOT := Color("#ffb24a")

var _body: Node3D            ## tout ce qui flotte
var _abdomen: Node3D         ## pivot de l'abdomen
var _wings: Array[Node3D] = []
var _eye_mat: StandardMaterial3D
var _stripe_mat: StandardMaterial3D
var _tinted: Array = []      ## [ShaderMaterial, Color]
var _t: float = 0.0
var _curl: float = 0.0


func _ready() -> void:
	_build()


# ---------------------------------------------------------------- PILOTAGE

func set_curl(k: float) -> void:
	_curl = clampf(k, 0.0, 1.0)
	if _abdomen != null:
		# Ease : l'abdomen part lentement puis claque en position de tir
		var e: float = _curl * _curl * (3.0 - 2.0 * _curl)
		_abdomen.rotation.x = deg_to_rad(10.0 + (curl_angle_deg - 10.0) * e)


func set_threat(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	if _eye_mat != null:
		_eye_mat.albedo_color = ToonBuilder.SCREEN.lerp(ToonBuilder.THREAT, k)
	if _stripe_mat != null:
		_stripe_mat.albedo_color = STRIPE_REST.lerp(STRIPE_HOT, k)


func set_tint(current: Color, base: Color) -> void:
	var diff: float = absf(current.r - base.r) + absf(current.g - base.g) + absf(current.b - base.b)
	var w: float = clampf(diff / 0.6, 0.0, 1.0) * tint_strength
	for entry in _tinted:
		var mat: ShaderMaterial = entry[0]
		var c: Color = entry[1]
		mat.set_shader_parameter("albedo_color", c.lerp(Color(current, 1.0), w))


func fly(speed: float, delta: float) -> void:
	_t += delta
	if _body == null:
		return
	# Flottement + inclinaison vers l'avant quand il file
	_body.position.y = hover_height + sin(_t * 3.2) * 0.06
	_body.rotation.x = -clampf(speed / 4.5, 0.0, 1.0) * deg_to_rad(18.0)
	# Battement d'ailes : rapide, en opposition avant / arrière
	for i in _wings.size():
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var phase: float = 0.0 if i < 2 else 0.6
		_wings[i].rotation.z = side * deg_to_rad(18.0 + sin(_t * 38.0 + phase) * 28.0)


# ---------------------------------------------------------------- CONSTRUCTION

func _build() -> void:
	var B := ToonBuilder
	_body = Node3D.new()
	_body.position.y = hover_height
	add_child(_body)

	# --- Thorax et tête ---
	_part(_body, B.box(Vector3(0.36, 0.32, 0.4)), Vector3(0.0, 0.05, -0.05), B.STEEL_DARK)
	_part(_body, B.box(Vector3(0.3, 0.26, 0.26)), Vector3(0.0, 0.1, -0.34), B.STEEL)
	# Mandibules
	for x: float in [-0.07, 0.07]:
		_part(_body, B.box(Vector3(0.05, 0.05, 0.12)), Vector3(x, -0.02, -0.5), B.STEEL_LIGHT)
	# Yeux : non éclairés, cyan au repos
	_eye_mat = B.glow_material(B.SCREEN)
	for x: float in [-0.1, 0.1]:
		var eye := MeshInstance3D.new()
		eye.mesh = B.box(Vector3(0.09, 0.1, 0.04))
		eye.position = Vector3(x, 0.13, -0.48)
		eye.material_override = _eye_mat
		_body.add_child(eye)
	# Antennes
	for x: float in [-0.07, 0.07]:
		var ant := _part(_body, B.box(Vector3(0.025, 0.25, 0.025)), Vector3(x * 1.6, 0.32, -0.4), B.STEEL_DARK)
		ant.rotation = Vector3(deg_to_rad(-30.0), 0.0, deg_to_rad(-20.0 if x < 0.0 else 20.0))

	# --- Abdomen à rayures + dard ---
	_abdomen = Node3D.new()
	_abdomen.position = Vector3(0.0, 0.0, 0.16)
	_body.add_child(_abdomen)
	_stripe_mat = B.glow_material(STRIPE_REST)
	var segs: Array = [
		# [taille, z, y]
		[Vector3(0.36, 0.32, 0.3), 0.18, -0.03],
		[Vector3(0.3, 0.27, 0.26), 0.43, -0.07],
		[Vector3(0.22, 0.2, 0.2), 0.64, -0.11],
	]
	for i in segs.size():
		var s: Vector3 = segs[i][0]
		var z: float = segs[i][1]
		var y: float = segs[i][2]
		_part(_abdomen, B.box(s), Vector3(0.0, y, z), Color("#1a130d"))
		# Bande qui s'allume pendant la visée (légèrement plus grande : dépasse)
		var band := MeshInstance3D.new()
		band.mesh = B.box(Vector3(s.x + 0.02, s.y + 0.02, s.z * 0.45))
		band.position = Vector3(0.0, y, z)
		band.material_override = _stripe_mat
		_abdomen.add_child(band)
	var stinger := _part(_abdomen, ToonBuilder.cylinder(0.035, 0.28, 8), Vector3(0.0, -0.13, 0.86), B.STEEL_LIGHT)
	stinger.rotation.x = PI * 0.5

	# --- Ailes : deux paires translucides ---
	var wing_mat := StandardMaterial3D.new()
	wing_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wing_mat.albedo_color = Color(0.37, 0.88, 1.0, 0.35)
	for pair: Array in [[-0.08, 0.55, 0.2], [0.08, 0.4, 0.15]]:
		for side: float in [-1.0, 1.0]:
			var hinge := Node3D.new()
			hinge.position = Vector3(0.12 * side, 0.22, pair[0])
			_body.add_child(hinge)
			_wings.append(hinge)
			var wing := MeshInstance3D.new()
			wing.mesh = B.box(Vector3(pair[1], 0.015, pair[2]))
			wing.position = Vector3(pair[1] * 0.5 * side, 0.0, 0.05)
			wing.rotation.y = deg_to_rad(-12.0) * side
			wing.material_override = wing_mat
			wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hinge.add_child(wing)

	# --- Pattes pendantes ---
	for z: float in [-0.15, 0.0, 0.12]:
		for side: float in [-1.0, 1.0]:
			var leg := _part(_body, B.box(Vector3(0.03, 0.28, 0.03)), Vector3(0.15 * side, -0.2, z), B.STEEL_DARK)
			leg.rotation = Vector3(deg_to_rad(15.0), 0.0, deg_to_rad(18.0) * side)

	set_curl(0.0)


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	var mat: Material = ToonBuilder.toon_material(color, outline_width)
	m.material_override = mat
	if mat is ShaderMaterial:
		_tinted.append([mat, color])
	parent.add_child(m)
	return m
