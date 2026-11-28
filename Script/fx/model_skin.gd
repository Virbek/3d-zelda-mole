extends RefCounted
class_name ModelSkin

## Habille un modèle importé de Blender (.glb) avec le rendu toon du projet.
## Les scripts Blender (art_src/blender/*.py) nomment chaque matériau d'après
## sa couleur logique (« rust », « fur »...) : on remplace chaque surface par
## le matériau toon de la couleur correspondante, ou par un matériau
## lumineux non éclairé pour les noms listés dans `glow`.


## Sort le nœud `node_name` d'une scène importée, recentré sur l'origine.
## Permet de ranger plusieurs pièces (gauche / droite) dans un seul .glb.
static func extract(scene: PackedScene, node_name: String) -> Node3D:
	var inst: Node = scene.instantiate()
	var part: Node3D = inst.find_child(node_name, true, false) as Node3D
	if part == null:
		push_error("ModelSkin : « %s » introuvable dans %s" % [node_name, scene.resource_path])
		inst.free()
		return Node3D.new()
	part.get_parent().remove_child(part)
	part.position = Vector3.ZERO
	part.owner = null
	inst.free()
	return part


## Remplace les matériaux de toutes les surfaces sous `root`.
## colors : nom de matériau -> Color (toon + contour)
## glow   : nom de matériau -> Color (non éclairé, sans contour)
## thin   : noms de matériaux qui reçoivent un contour plus fin (moustaches...)
## Retourne les MeshInstance3D touchés (pour un material_overlay, par ex.).
static func apply(root: Node, colors: Dictionary, glow: Dictionary, outline: float, thin: Array = []) -> Array[MeshInstance3D]:
	var touched: Array[MeshInstance3D] = []
	var glow_cache: Dictionary = {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(s)
			var mat_name: String = src.resource_name if src != null else ""
			if glow.has(mat_name):
				if not glow_cache.has(mat_name):
					glow_cache[mat_name] = ToonBuilder.glow_material(glow[mat_name])
				mi.set_surface_override_material(s, glow_cache[mat_name])
			else:
				var color: Color = colors.get(mat_name, Color.MAGENTA)
				var w: float = outline * 0.5 if thin.has(mat_name) else outline
				mi.set_surface_override_material(s, ToonBuilder.toon_material(color, w, true))
		touched.append(mi)
	return touched
