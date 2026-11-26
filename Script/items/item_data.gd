extends Resource
class_name ItemData

## Un objet qu'on peut trouver dans un coffre : ce qu'affiche l'écran
## « objet obtenu » (nom, description, image) et ce que le jeu en fait (id).
##
## Image : si `icon` est rempli, elle sert telle quelle (panneau et au-dessus
## du poing). Sinon on construit un petit modèle 3D, pour les objets connus
## du code (la clé).

## Où l'objet se range dans l'inventaire.
enum Category {
	SMALL_KEY,        ## petite clé : comptée par le donjon, pas par l'inventaire
	BOSS_KEY,         ## grande clé du donjon
	ENERGY_FRAGMENT,  ## fragment de pile d'énergie : 4 = une cellule de vie en plus
	KEY_ITEM,         ## objet de quête / objet clé
	COMBAT,           ## objet équipable de combat
	EXPLORATION,      ## outil de traversée
}

@export var id: StringName = &"key"          ## ce que le jeu en fait : « key » donne une clé
@export var category: Category = Category.SMALL_KEY
@export var display_name: String = "Petite clé"
@export_multiline var description: String = "Ouvre une porte verrouillée de ce donjon."
@export var icon: Texture2D
const ENERGY_FRAGMENT_ID := &"energy_fragment"
const ENERGY_CYAN := Color(0.25, 0.84, 0.88)

## Couleur de la petite clé, partout où elle apparaît (coffre, sol, porte).
const KEY_COLOR := Color(0.82, 0.82, 0.85)

@export var color := KEY_COLOR   ## teinte du modèle et du halo


static func small_key() -> ItemData:
	return ItemData.new()


## Modèle 3D de l'objet, centré sur son origine, d'environ 0,6 m de haut.
func build_model() -> Node3D:
	if icon != null:
		var s := Sprite3D.new()
		s.texture = icon
		s.pixel_size = 0.6 / maxf(float(icon.get_height()), 1.0)
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		return s
	if id == ENERGY_FRAGMENT_ID:
		return build_energy_fragment_model()
	return build_key_model(color)


## La clé, en primitives. Partagée avec KeyPickup.
static func build_key_model(c: Color) -> Node3D:
	var root := Node3D.new()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.metallic = 0.5
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 0.2

	# Tête : un rectangle plein. Tige et dents en dessous.
	for part: Array in [
		[Vector3(0.36, 0.26, 0.09), Vector3(0.0, 0.3, 0.0)],
		[Vector3(0.09, 0.5, 0.09), Vector3(0.0, -0.08, 0.0)],
		[Vector3(0.16, 0.07, 0.09), Vector3(0.1, -0.22, 0.0)],
		[Vector3(0.12, 0.07, 0.09), Vector3(0.08, -0.32, 0.0)],
	]:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = part[0]
		m.mesh = b
		m.position = part[1]
		m.material_override = mat
		root.add_child(m)
	return root


## Fragment de pile d'énergie : un quart de grosse pile cylindrique, coque
## rouille cassée en biais, cœur cyan qui luit (machine encore active).
static func build_energy_fragment_model() -> Node3D:
	var root := Node3D.new()

	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.54, 0.29, 0.15)
	rust.roughness = 0.8

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.62, 0.6)
	steel.metallic = 0.4
	steel.roughness = 0.45

	var core := StandardMaterial3D.new()
	core.albedo_color = ENERGY_CYAN
	core.emission_enabled = true
	core.emission = ENERGY_CYAN
	core.emission_energy_multiplier = 1.6

	# Coque : un quartier de cylindre (CylinderMesh n'a pas de secteur, on
	# assemble trois plaques courbes approximées par des boîtes inclinées)
	var shell := Node3D.new()
	root.add_child(shell)
	for i in 3:
		var a: float = deg_to_rad(-30.0 + 30.0 * float(i))
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.17, 0.5, 0.06)
		m.mesh = b
		m.material_override = rust
		m.position = Vector3(sin(a) * 0.2, 0.0, cos(a) * 0.2)
		m.rotation.y = a
		shell.add_child(m)

	# Cœur lumineux à l'intérieur
	var c := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 0.46
	cyl.radial_segments = 10
	c.mesh = cyl
	c.material_override = core
	c.position = Vector3(0.0, 0.0, 0.08)
	root.add_child(c)

	# Bague acier en bas et plot de borne en haut (la pile se reconnaît)
	var ring := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.46, 0.07, 0.12)
	ring.mesh = rb
	ring.material_override = steel
	ring.position = Vector3(0.0, -0.24, 0.2)
	root.add_child(ring)

	var tip := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.1, 0.08, 0.1)
	tip.mesh = tb
	tip.material_override = steel
	tip.position = Vector3(0.0, 0.29, 0.1)
	root.add_child(tip)

	# Cassure en biais sur le dessus
	var shard := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.36, 0.06, 0.1)
	shard.mesh = sb
	shard.material_override = rust
	shard.position = Vector3(0.0, 0.25, 0.22)
	shard.rotation.z = deg_to_rad(18.0)
	root.add_child(shard)

	var glow := OmniLight3D.new()
	glow.light_color = ENERGY_CYAN
	glow.light_energy = 0.6
	glow.omni_range = 1.2
	glow.position = Vector3(0.0, 0.0, 0.3)
	root.add_child(glow)
	return root
