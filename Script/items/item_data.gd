extends Resource
class_name ItemData

## Un objet qu'on peut trouver dans un coffre : ce qu'affiche l'écran
## « objet obtenu » (nom, description, image) et ce que le jeu en fait (id).
##
## Image : si `icon` est rempli, elle sert telle quelle (panneau et au-dessus
## du poing). Sinon on construit un petit modèle 3D, pour les objets connus
## du code (la clé).

@export var id: StringName = &"key"          ## ce que le jeu en fait : « key » donne une clé
@export var display_name: String = "Petite clé"
@export_multiline var description: String = "Ouvre une porte verrouillée de ce donjon."
@export var icon: Texture2D
@export var color := Color(1.0, 0.82, 0.2)   ## teinte du modèle et du halo


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
	return build_key_model(color)


## La clé, en primitives. Partagée avec KeyPickup.
static func build_key_model(c: Color) -> Node3D:
	var root := Node3D.new()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.metallic = 0.6
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 0.35

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.1
	torus.outer_radius = 0.22
	ring.mesh = torus
	ring.rotation.x = PI * 0.5
	ring.position.y = 0.3
	ring.material_override = mat
	root.add_child(ring)

	for part: Array in [
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
