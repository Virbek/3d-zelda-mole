extends Node3D
class_name StagBeetleModel

## Lucane-cisaille : apparence de l'ennemi de mêlée, construite en primitives.
## Gros corps rouillé sur six pattes d'acier, tête blindée, et deux
## mandibules-cisailles qui s'ouvrent pendant le télégraphe et claquent à
## la frappe.
##
## Origine au sol, avant en -Z (comme l'ennemi qui le porte). Le script de
## l'ennemi pilote :
##   - set_pincers(k) : 0 = fermées, 1 = grandes ouvertes
##   - set_walk(speed, delta) : balancement des pattes
##   - set_tint(current, base) : reporte les couleurs de télégraphe, de coup
##     et d'étourdissement sur toute la carapace
##   - set_eyes_threat(k) : yeux cyan → orange quand il attaque

@export var outline_width: float = 0.012
@export var pincer_closed_deg: float = 8.0    ## léger croisement des pointes, fermées
@export var pincer_open_deg: float = 38.0     ## ouverture max pendant le télégraphe
@export var tint_strength: float = 0.7        ## part max de la couleur d'alerte sur la carapace

var _pincers: Array[Node3D] = []              ## pivots gauche / droit
var _legs: Array[Node3D] = []                 ## pivots de hanche
var _leg_phase: float = 0.0
var _eye_mat: StandardMaterial3D

## Pour la teinte : chaque matériau toon et sa couleur d'origine
var _tinted: Array = []                       ## [ShaderMaterial, Color]


func _ready() -> void:
	_build()


# ---------------------------------------------------------------- PILOTAGE

func set_pincers(k: float) -> void:
	var a: float = deg_to_rad(lerpf(-pincer_closed_deg, pincer_open_deg, clampf(k, 0.0, 1.0)))
	for i in _pincers.size():
		var side: float = -1.0 if i == 0 else 1.0
		# Ouvrir = écarter la pointe vers l'extérieur
		_pincers[i].rotation.y = -a * side


func set_walk(speed: float, delta: float) -> void:
	_leg_phase += speed * 5.0 * delta
	var amp: float = clampf(speed / 3.0, 0.0, 1.0) * deg_to_rad(22.0)
	for i in _legs.size():
		# Trépied alterné : pattes 0, 3, 4 ensemble, puis 1, 2, 5
		var offset: float = 0.0 if i in [0, 3, 4] else PI
		_legs[i].rotation.x = sin(_leg_phase + offset) * amp


## current / base : couleur actuelle et couleur de repos du matériau que
## l'ennemi fait clignoter (télégraphe, coup reçu, étourdissement). Plus elle
## s'éloigne du repos, plus chaque pièce est mélangée vers cette couleur.
func set_tint(current: Color, base: Color) -> void:
	var diff: float = absf(current.r - base.r) + absf(current.g - base.g) + absf(current.b - base.b)
	var w: float = clampf(diff / 0.6, 0.0, 1.0) * tint_strength
	for entry in _tinted:
		var mat: ShaderMaterial = entry[0]
		var c: Color = entry[1]
		mat.set_shader_parameter("albedo_color", c.lerp(Color(current, 1.0), w))


func set_eyes_threat(k: float) -> void:
	if _eye_mat != null:
		_eye_mat.albedo_color = ToonBuilder.SCREEN.lerp(ToonBuilder.THREAT, clampf(k, 0.0, 1.0))


# ---------------------------------------------------------------- CONSTRUCTION

func _build() -> void:
	var B := ToonBuilder

	# --- Abdomen / élytres : le gros volume rouillé ---
	_part(B.box(Vector3(0.95, 0.42, 0.95)), Vector3(0.0, 0.78, 0.28), B.RUST)
	# Séparation des élytres + plaque sombre sur le dessus
	_part(B.box(Vector3(0.05, 0.06, 0.92)), Vector3(0.0, 1.01, 0.28), B.RUST_DARK)
	_part(B.box(Vector3(0.75, 0.08, 0.6)), Vector3(0.0, 1.0, 0.4), B.RUST_DARK)
	# Bande de danger à l'arrière
	_part(B.box(Vector3(0.97, 0.12, 0.08)), Vector3(0.0, 0.72, 0.74), B.HAZARD)
	# Pot d'échappement
	var pipe := _part(B.cylinder(0.06, 0.32), Vector3(0.3, 1.12, 0.6), B.STEEL_DARK)
	pipe.rotation.x = deg_to_rad(-20.0)

	# --- Thorax ---
	_part(B.box(Vector3(0.72, 0.38, 0.36)), Vector3(0.0, 0.8, -0.34), B.STEEL_DARK)

	# --- Tête blindée ---
	_part(B.box(Vector3(0.62, 0.3, 0.34)), Vector3(0.0, 0.84, -0.66), B.STEEL)
	_part(B.box(Vector3(0.5, 0.06, 0.3)), Vector3(0.0, 1.01, -0.66), B.RUST_DARK)

	# Yeux : non éclairés, cyan au repos
	_eye_mat = B.glow_material(B.SCREEN)
	for x: float in [-0.22, 0.22]:
		var eye := MeshInstance3D.new()
		eye.mesh = B.box(Vector3(0.1, 0.08, 0.04))
		eye.position = Vector3(x, 0.9, -0.84)
		eye.material_override = _eye_mat
		add_child(eye)

	# --- Mandibules-cisailles ---
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.2 * side, 0.78, -0.8)
		add_child(pivot)
		_pincers.append(pivot)

		# Lame de base, orientée vers l'avant et un peu vers l'extérieur
		var base := _part(B.box(Vector3(0.12, 0.12, 0.5)), Vector3(0.07 * side, 0.0, -0.24), B.STEEL_DARK, pivot)
		base.rotation.y = deg_to_rad(-12.0) * side
		# Pointe recourbée vers l'intérieur
		var tip := _part(B.box(Vector3(0.09, 0.09, 0.36)), Vector3(0.04 * side, 0.0, -0.6), B.STEEL_LIGHT, pivot)
		tip.rotation.y = deg_to_rad(28.0) * side
		# Dent intérieure
		_part(B.box(Vector3(0.1, 0.07, 0.06)), Vector3(-0.0 * side, 0.0, -0.36), B.STEEL_LIGHT, pivot)

	set_pincers(0.0)

	# --- Six pattes d'acier ---
	for z: float in [-0.3, 0.1, 0.5]:
		for side: float in [-1.0, 1.0]:
			var hip := Node3D.new()
			hip.position = Vector3(0.42 * side, 0.68, z)
			add_child(hip)
			_legs.append(hip)
			# Cuisse vers l'extérieur et le haut, puis tibia jusqu'au sol
			# Cuisse : monte vers l'extérieur (genou haut, silhouette d'insecte)
			var thigh := _part(B.box(Vector3(0.42, 0.08, 0.08)), Vector3(0.19 * side, 0.1, 0.0), B.STEEL_DARK, hip)
			thigh.rotation.z = deg_to_rad(28.0) * side
			# Genou : petite rotule rouillée
			_part(B.box(Vector3(0.1, 0.1, 0.1)), Vector3(0.38 * side, 0.2, 0.0), B.RUST_DARK, hip)
			# Tibia : redescend en s'écartant jusqu'au sol
			var shin := _part(B.box(Vector3(0.07, 0.78, 0.07)), Vector3(0.52 * side, -0.16, 0.0), B.STEEL, hip)
			shin.rotation.z = deg_to_rad(22.0) * side


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
