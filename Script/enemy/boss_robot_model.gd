extends Node3D
class_name BossRobotModel

## Boss robot « poings-blocs », d'après le croquis : petite tête en dôme qui
## dépasse d'un grand corps-chaudière, deux bras identiques qui pendent
## jusqu'au sol et finissent par de gros poings carrés. Un réacteur à chaque
## coude : c'est lui qui le propulse en l'air.
##
## Origine au sol, avant en -Z, cotes en mètres. Le script du boss appelle
## drive(pose, k, delta) à chaque frame :
##   "rest"   : bras ballants, léger balancement
##   "windup" : (k 0 → 1) bras écartés, poings plantés, yeux qui virent à l'orange
##   "rise"   : poussée — bras sous le corps, flammes sous les poings
##   "hover"  : poings joints au-dessus de la tête
##   "fall"   : (k 0 → 1) les deux poings s'abattent vers le sol
##   "landed" : poings au sol après le fracas, puis retour au repos
##   "dead"   : bras qui retombent, yeux éteints

@export var outline_width: float = 0.02
@export var tint_strength: float = 0.7

const SHOULDER := Vector3(0.98, 2.2, 0.0)
const ARM_LEN := 2.0

## Angles des bras (bras droit ; le gauche est en miroir), en degrés.
## z : 0 = pend vers le sol, + = poing vers l'extérieur, -160 = au-dessus de la tête.
## x : + = poing vers l'avant.
const POSES := {
	"rest": Vector2(7.0, 0.0),
	"windup": Vector2(32.0, 10.0),
	"rise": Vector2(-4.0, -12.0),
	"hover": Vector2(-158.0, 8.0),
	"slam": Vector2(10.0, 34.0),
	"dead": Vector2(24.0, 18.0),
}

var _arms: Array[Node3D] = []         ## pivots d'épaule [gauche, droit]
var _flames: Array[Node3D] = []        ## supports de flamme (échelle Y = longueur)
var _nozzle_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _flame_mat: StandardMaterial3D
var _head: Node3D
var _tinted: Array = []               ## [ShaderMaterial, Color]
## Rage (phase 2) : 0 = couleurs d'origine, 1 = carcasse virée au rouge
var _rage: float = 0.0
var _rage_color := Color(0.85, 0.12, 0.08)
@export var rage_strength: float = 0.6   ## part de rouge sur la carcasse en rage complète
var _angle := Vector2(7.0, 0.0)
var _flame_k: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	_build()


# ---------------------------------------------------------------- PILOTAGE

func drive(pose: String, k: float, delta: float) -> void:
	_t += delta
	k = clampf(k, 0.0, 1.0)
	var want: Vector2 = POSES["rest"]
	var rate: float = 8.0
	var flame: float = 0.0
	var threat: float = 0.0
	match pose:
		"rest":
			want = POSES["rest"] + Vector2(sin(_t * 1.6) * 3.0, sin(_t * 1.1) * 4.0)
		"windup":
			want = (POSES["rest"] as Vector2).lerp(POSES["windup"], k)
			rate = 20.0
			threat = k
			flame = k * 0.25            # les réacteurs s'allument
		"rise":
			want = POSES["rise"]
			rate = 25.0
			flame = 1.0
			threat = 1.0
		"hover":
			want = POSES["hover"]
			rate = 10.0
			flame = 0.0                 # bras levés : la flamme pointerait vers le ciel
			threat = 1.0
		"fall":
			# Les poings restent levés puis claquent vers le sol à la fin
			var e: float = clampf((k - 0.25) / 0.75, 0.0, 1.0)
			want = (POSES["hover"] as Vector2).lerp(POSES["slam"], e * e)
			rate = 40.0
			threat = 1.0
		"landed":
			want = (POSES["slam"] as Vector2).lerp(POSES["rest"], k * k)
			rate = 30.0
			threat = 1.0 - k
		"dead":
			want = POSES["dead"]
			rate = 5.0

	var a: float = 1.0 - exp(-rate * delta)
	_angle = _angle.lerp(want, a)
	_flame_k = lerpf(_flame_k, flame, 1.0 - exp(-18.0 * delta))
	for i in _arms.size():
		var side: float = -1.0 if i == 0 else 1.0
		_arms[i].rotation = Vector3(deg_to_rad(_angle.y), 0.0, deg_to_rad(_angle.x) * side)
	for f in _flames:
		f.visible = _flame_k > 0.03
		f.scale = Vector3(1.0, 0.4 + _flame_k * (1.0 + sin(_t * 60.0) * 0.15), 1.0)
	_set_threat(threat if pose != "dead" else -1.0)


func set_tint(current: Color, base: Color) -> void:
	var diff: float = absf(current.r - base.r) + absf(current.g - base.g) + absf(current.b - base.b)
	var w: float = clampf(diff / 0.6, 0.0, 1.0) * tint_strength
	for entry in _tinted:
		var mat: ShaderMaterial = entry[0]
		var c: Color = (entry[1] as Color).lerp(_rage_color, _rage * rage_strength)
		mat.set_shader_parameter("albedo_color", c.lerp(Color(current, 1.0), w))


## Phase 2 : la carcasse vire au rouge et les yeux passent du cyan au rouge.
func set_rage(k: float, color: Color) -> void:
	_rage = clampf(k, 0.0, 1.0)
	_rage_color = color


## -1 = éteint (mort), 0 = cyan (machine active), 1 = orange (menace).
func _set_threat(k: float) -> void:
	if _eye_mat == null:
		return
	if k < 0.0:
		_eye_mat.albedo_color = ToonBuilder.STEEL_DARK
		_nozzle_mat.albedo_color = ToonBuilder.STEEL_DARK
		return
	var c: Color = ToonBuilder.SCREEN.lerp(_rage_color.lightened(0.25), _rage).lerp(ToonBuilder.THREAT, k)
	_eye_mat.albedo_color = c
	_nozzle_mat.albedo_color = c


# ---------------------------------------------------------------- CONSTRUCTION

func _build() -> void:
	var B := ToonBuilder
	_eye_mat = B.glow_material(B.SCREEN)
	_nozzle_mat = B.glow_material(B.SCREEN)
	_flame_mat = B.glow_material(Color(1.0, 0.55, 0.15))

	# --- Corps-chaudière : plus large en haut, base en jupe sombre ---
	var body := _cyl(0.78, 0.66, 2.0, Vector3(0.0, 1.4, 0.0), B.RUST, 14)
	body.name = "Boiler"
	_cyl(0.7, 0.72, 0.32, Vector3(0.0, 0.36, 0.0), B.RUST_DARK, 14)
	_cyl(0.8, 0.8, 0.2, Vector3(0.0, 1.45, 0.0), B.HAZARD, 14)
	# Col qui cache le bas de la tête (comme sur le croquis)
	_cyl(0.84, 0.82, 0.28, Vector3(0.0, 2.36, 0.0), B.RUST_DARK, 14)
	# Rivets sur deux rangées
	for row: float in [0.75, 2.05]:
		for i in 10:
			var a: float = TAU * float(i) / 10.0
			var r: float = 0.79 if row > 1.0 else 0.71
			_part(B.box(Vector3(0.07, 0.07, 0.07)), Vector3(sin(a) * r, row, cos(a) * r), B.STEEL_DARK)
	# Manomètre sur la poitrine
	var gauge := _cyl(0.24, 0.24, 0.08, Vector3(0.0, 1.9, -0.78), B.STEEL_DARK, 12)
	gauge.rotation.x = PI * 0.5
	var dial := _cyl(0.18, 0.18, 0.02, Vector3(0.0, 1.9, -0.83), B.STEEL_LIGHT, 12)
	dial.rotation.x = PI * 0.5
	var needle := _part(B.box(Vector3(0.03, 0.15, 0.02)), Vector3(0.05, 1.93, -0.85), B.THREAT)
	needle.rotation.z = deg_to_rad(-35.0)
	# Cheminées dans le dos
	for x: float in [-0.35, 0.35]:
		_cyl(0.1, 0.1, 0.7, Vector3(x, 2.4, 0.62), B.STEEL_DARK, 8)

	# --- Tête : petit dôme, deux yeux ---
	_head = Node3D.new()
	_head.position = Vector3(0.0, 2.48, -0.05)
	add_child(_head)
	var dome := SphereMesh.new()
	dome.radius = 0.44
	dome.height = 0.88
	dome.radial_segments = 12
	dome.rings = 6
	_part(dome, Vector3.ZERO, B.STEEL, _head)
	for x: float in [-0.15, 0.15]:
		var eye := MeshInstance3D.new()
		eye.mesh = B.box(Vector3(0.15, 0.09, 0.06))
		eye.position = Vector3(x, 0.17, -0.38)
		eye.rotation.x = deg_to_rad(-15.0)
		eye.material_override = _eye_mat
		_head.add_child(eye)

	# --- Bras identiques ---
	for side: float in [-1.0, 1.0]:
		_arms.append(_build_arm(side))


func _build_arm(side: float) -> Node3D:
	var B := ToonBuilder
	var pivot := Node3D.new()
	pivot.position = Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
	add_child(pivot)

	# Épaule : gros moyeu
	var hub := _cyl(0.3, 0.3, 0.34, Vector3.ZERO, B.STEEL_DARK, 10, pivot)
	hub.rotation.z = PI * 0.5
	# Bras : poutre rouillée + vérin d'acier sur l'avant
	_part(B.box(Vector3(0.42, 1.45, 0.42)), Vector3(0.0, -0.8, 0.0), B.RUST_DARK, pivot)
	_cyl(0.06, 0.06, 1.1, Vector3(0.0, -0.75, -0.25), B.STEEL_LIGHT, 8, pivot)
	_cyl(0.09, 0.09, 0.3, Vector3(0.0, -0.3, -0.25), B.STEEL_DARK, 8, pivot)
	# Réacteur au coude, tourné vers l'arrière et l'extérieur
	var nozzle := _cyl(0.12, 0.2, 0.3, Vector3(0.22 * side, -0.7, 0.24), B.STEEL_DARK, 10, pivot)
	nozzle.rotation = Vector3(deg_to_rad(60.0), 0.0, deg_to_rad(-30.0) * side)
	var core := MeshInstance3D.new()
	core.mesh = ToonBuilder.cylinder(0.12, 0.04, 10)
	core.material_override = _nozzle_mat
	core.position = Vector3(0.0, -0.14, 0.0)
	nozzle.add_child(core)

	# Poing-bloc : jointures vers le sol
	var wrist := -ARM_LEN + 0.42
	_part(B.box(Vector3(0.5, 0.16, 0.5)), Vector3(0.0, wrist + 0.32, 0.0), B.HAZARD, pivot)
	_part(B.box(Vector3(0.72, 0.6, 0.72)), Vector3(0.0, wrist, 0.0), B.STEEL, pivot)
	for i in 3:
		var z: float = lerpf(-0.22, 0.22, float(i) / 2.0)
		_part(B.box(Vector3(0.62, 0.14, 0.18)), Vector3(0.0, wrist - 0.36, z), B.STEEL_LIGHT, pivot)

	# Flamme de propulsion sous le poing (cachée au repos)
	var flame := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.3
	cone.bottom_radius = 0.02
	cone.height = 1.0
	cone.radial_segments = 8
	flame.mesh = cone
	flame.material_override = _flame_mat
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Le cône pend sous son support : étirer le support en Y l'allonge vers
	# le bas sans le décoller du poing
	var anchor := Node3D.new()
	anchor.position = Vector3(0.0, wrist - 0.43, 0.0)
	pivot.add_child(anchor)
	flame.position = Vector3(0.0, -0.5, 0.0)
	var holder := Node3D.new()
	anchor.add_child(holder)
	holder.add_child(flame)
	holder.visible = false
	_flames.append(holder)
	return pivot


func _part(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	var mat: Material = ToonBuilder.toon_material(color, outline_width)
	m.material_override = mat
	if mat is ShaderMaterial:
		_tinted.append([mat, color])
	(parent if parent != null else self).add_child(m)
	return m


func _cyl(top: float, bottom: float, h: float, pos: Vector3, color: Color, seg: int = 10, parent: Node3D = null) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return _part(c, pos, color, parent)
