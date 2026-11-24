class_name OffscreenThreats
extends Control

## Flèches au bord de l'écran pour chaque ennemi qui prépare une attaque
## hors du champ de la caméra. Elles pointent vers lui : le joueur sait de
## quel côté esquiver sans avoir vu le télégraphe.
##
## Un ennemi est « menaçant » s'il expose is_threatening() et qu'elle renvoie
## vrai (télégraphe, visée, amorçage...). Tout est dessiné dans _draw : aucun
## nœud créé par flèche.

@export var margin: float = 36.0        ## distance des flèches au bord de l'écran
@export var arrow_size: float = 22.0
@export var color := Color(1.0, 0.3, 0.2)

var _arrows: Array[Dictionary] = []     ## { pos: Vector2, angle: float }
var _t: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	_arrows.clear()

	var cam := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if cam != null and player != null:
		var origin: Vector3 = player.global_position + Vector3.UP
		var origin_2d: Vector2 = cam.unproject_position(origin)
		var rect := get_viewport_rect()
		var center: Vector2 = rect.size * 0.5
		var half: Vector2 = center - Vector2(margin, margin)

		for e in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or not e.has_method("is_threatening"):
				continue
			if not e.is_threatening():
				continue
			var world: Vector3 = (e as Node3D).global_position + Vector3.UP
			var behind: bool = cam.is_position_behind(world)
			var p: Vector2 = cam.unproject_position(world)
			if not behind and Rect2(Vector2.ZERO, rect.size).grow(-margin * 0.5).has_point(p):
				continue   # visible à l'écran : le télégraphe suffit

			# Direction à l'écran : on projette un point à 2 m du joueur vers
			# l'ennemi plutôt que l'ennemi lui-même. Loin et derrière le plan de
			# la caméra (fréquent en isométrique), sa projection serait inversée.
			var to_e: Vector3 = world - origin
			to_e.y = 0.0
			var dir: Vector2 = Vector2.ZERO
			if to_e.length_squared() > 0.0001:
				dir = cam.unproject_position(origin + to_e.normalized() * 2.0) - origin_2d
			if dir.length_squared() < 0.01:
				dir = Vector2.DOWN
			dir = dir.normalized()

			# Point du rectangle intérieur dans cette direction
			var tx: float = half.x / absf(dir.x) if absf(dir.x) > 0.0001 else INF
			var ty: float = half.y / absf(dir.y) if absf(dir.y) > 0.0001 else INF
			_arrows.append({"pos": center + dir * minf(tx, ty), "angle": dir.angle()})

	queue_redraw()


func _draw() -> void:
	if _arrows.is_empty():
		return
	var pulse: float = 1.0 + 0.15 * sin(_t * 14.0)
	var s: float = arrow_size * pulse
	for a in _arrows:
		var pos: Vector2 = a["pos"]
		var rot: float = a["angle"]
		var pts := PackedVector2Array([
			pos + Vector2(s, 0.0).rotated(rot),
			pos + Vector2(-s * 0.6, s * 0.7).rotated(rot),
			pos + Vector2(-s * 0.6, -s * 0.7).rotated(rot),
		])
		# Contour noir épais puis remplissage : lisible sur tous les sols
		var outline := PackedVector2Array(pts)
		outline.append(pts[0])
		draw_polyline(outline, Color.BLACK, 5.0, true)
		draw_colored_polygon(pts, color)
