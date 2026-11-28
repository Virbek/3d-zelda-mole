extends Node3D
class_name HornetModel

## Frelon-perceur : apparence de l'ennemi tireur. Insecte vivant : thorax et
## tête de chitine, yeux composés cyan, abdomen fuselé à rayures terminé par
## un dard, quatre ailes translucides qui battent vite.
##
## Le modèle vient de Blender (art_src/blender/hornet.py -> hornet.glb). Ce
## script y retrouve les nœuds Body, Abdomen, WingHinge_0..3 par leur nom et
## remplace chaque matériau par son équivalent toon selon son nom.
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

const MODEL: PackedScene = preload("res://Asset/Model/Enemy/hornet.glb")

const STRIPE_REST := Color("#c8743a")
const STRIPE_HOT := Color("#ffb24a")
## Couleurs toon par nom de matériau Blender
const TOON_COLORS: Dictionary = {
	"chitin": Color("#2a1d14"),
	"chitin_dark": Color("#16100b"),
	"accent": Color("#b07a2e"),
	"stinger": Color("#e8d9b0"),
}

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
	var model: Node3D = MODEL.instantiate() as Node3D
	add_child(model)
	_body = model.find_child("Body", true, false) as Node3D
	_abdomen = model.find_child("Abdomen", true, false) as Node3D
	_body.position.y = hover_height
	for i in 4:
		_wings.append(model.find_child("WingHinge_%d" % i, true, false) as Node3D)

	_eye_mat = ToonBuilder.glow_material(ToonBuilder.SCREEN)
	_stripe_mat = ToonBuilder.glow_material(STRIPE_REST)
	var wing_mat := StandardMaterial3D.new()
	wing_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wing_mat.albedo_color = Color(0.37, 0.88, 1.0, 0.35)

	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(s)
			var mat_name: String = src.resource_name if src != null else ""
			match mat_name:
				"eye":
					mi.set_surface_override_material(s, _eye_mat)
				"stripe":
					mi.set_surface_override_material(s, _stripe_mat)
				"wing":
					mi.set_surface_override_material(s, wing_mat)
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_:
					var color: Color = TOON_COLORS.get(mat_name, TOON_COLORS["chitin"])
					var mat: Material = ToonBuilder.toon_material(color, outline_width, true)
					mi.set_surface_override_material(s, mat)
					if mat is ShaderMaterial:
						_tinted.append([mat, color])

	set_curl(0.0)
