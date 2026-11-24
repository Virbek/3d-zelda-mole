class_name DodgeGhosts
extends Node3D

## Images fantômes laissées derrière le joueur pendant l'esquive.
##
## Chaque fantôme est une « photo » translucide de tous les meshes du rig à
## un instant donné, qui s'efface en quelques dixièmes de seconde. Le modèle
## n'a pas de squelette : copier mesh + transformation globale suffit.
##
## Tout est créé une fois (réservoir de pool_size fantômes) puis réutilisé :
## aucune instanciation pendant le jeu. Le joueur pilote `active`.

@export var pool_size: int = 6
@export var interval: float = 0.045      ## délai entre deux fantômes
@export var fade_time: float = 0.25
@export var start_alpha: float = 0.45
@export var color := Color(0.55, 0.85, 1.0)

## Mis à vrai par le joueur tant qu'il esquive.
var active: bool = false

var _sources: Array[MeshInstance3D] = []
var _ghosts: Array[Node3D] = []
var _mats: Array[StandardMaterial3D] = []
var _tweens: Array = []
var _next: int = 0
var _timer: float = 0.0
var _was_active: bool = false


## source_root : le nœud dont tous les MeshInstance3D descendants sont copiés.
func setup(source_root: Node) -> void:
	top_level = true   # les fantômes restent sur place quand le joueur s'en va
	global_transform = Transform3D.IDENTITY
	_sources.clear()
	_collect(source_root)

	for i in pool_size:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color, 0.0)

		var ghost := Node3D.new()
		ghost.visible = false
		add_child(ghost)
		for src in _sources:
			var m := MeshInstance3D.new()
			m.mesh = src.mesh
			m.material_override = mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ghost.add_child(m)

		_ghosts.append(ghost)
		_mats.append(mat)
		_tweens.append(null)


func _collect(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		_sources.append(n)
	for c in n.get_children():
		_collect(c)


func _process(delta: float) -> void:
	if _ghosts.is_empty():
		return
	if active and not _was_active:
		_timer = 0.0     # premier fantôme dès le départ de l'esquive
	_was_active = active
	if not active:
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = interval
		_spawn()


func _spawn() -> void:
	var i: int = _next
	_next = (_next + 1) % _ghosts.size()

	var ghost: Node3D = _ghosts[i]
	var parts: Array[Node] = ghost.get_children()
	for k in _sources.size():
		var src: MeshInstance3D = _sources[k]
		var m := parts[k] as MeshInstance3D
		m.visible = src.is_visible_in_tree()
		m.global_transform = src.global_transform
	ghost.visible = true

	var mat: StandardMaterial3D = _mats[i]
	mat.albedo_color = Color(color, start_alpha)

	var old = _tweens[i]
	if old != null and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, fade_time)
	t.tween_callback(ghost.hide)
	_tweens[i] = t
