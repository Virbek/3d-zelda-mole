extends Node3D

## Chaque morceau du .fbx (cylinder, tube, sphere...) a déjà sa propre
## texture assignée par l'import (via les slots de matériaux FBX). On
## récupère cette texture d'origine avant de l'écraser par le matériau
## toon, morceau par morceau — pas besoin de mapper les 9 PNG à la main.

@export var toon_shader: Shader
@export var outline_shader: Shader
@export var outline_width: float = 0.012
@export var outline_skip: Array[String] = ["plane", "plane_1", "plane_2", "plane_3", "plane_4"]  ## pièces fines : pas de contour dessus


func _ready() -> void:
	_apply_to_all(self)


func _apply_to_all(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var count: int = node.mesh.get_surface_count()
		for i in count:
			_apply_toon(node, i)

	for child in node.get_children():
		_apply_to_all(child)


func _apply_toon(mesh_instance: MeshInstance3D, surface: int) -> void:
	var original: Material = mesh_instance.get_active_material(surface)
	var tex: Texture2D = null
	if original is BaseMaterial3D:
		tex = (original as BaseMaterial3D).albedo_texture

	var toon_mat := ShaderMaterial.new()
	toon_mat.shader = toon_shader
	toon_mat.set_shader_parameter("use_texture", tex != null)
	if tex != null:
		toon_mat.set_shader_parameter("albedo_texture", tex)
		toon_mat.set_shader_parameter("albedo_color", Color(1.0, 1.0, 1.0, 1.0))

	# Les pièces fines (planes) font du z-fighting si on gonfle leurs deux
	# faces le long de normales opposées : on leur retire simplement le
	# contour plutôt que de chercher une épaisseur qui marche pour tout.
	if not outline_skip.has(mesh_instance.name):
		var outline_mat := ShaderMaterial.new()
		outline_mat.shader = outline_shader
		outline_mat.set_shader_parameter("outline_width", outline_width)
		toon_mat.next_pass = outline_mat

	mesh_instance.set_surface_override_material(surface, toon_mat)