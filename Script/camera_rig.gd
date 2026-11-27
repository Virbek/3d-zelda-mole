extends Node3D

@export var target: Node3D
@export var smoothing: float = 10.0
@export var height_offset: float = 1.0

@export_group("Zoom")
@export var size_normal: float = 12.0
@export var size_sprint: float = 14.5
@export var zoom_smoothing: float = 2.5
## Multiplie toutes les tailles ci-dessus (normal, sprint, combat, ciblage) :
## 1 = tel quel, plus grand = caméra plus éloignée.
@export var zoom_scale: float = 1.2
## Caméra en perspective : distance au joueur en taille normale. Le sprint,
## le combat et le ciblage la font reculer en proportion de leurs tailles.
@export var perspective_distance: float = 8.0

@export_group("Secousse")
@export var shake_decay: float = 4.0
@export var shake_amount: float = 0.5
@export var shake_speed: float = 28.0

@export_group("Ciblage")
@export var lock_focus_weight: float = 0.35    ## 0 = full joueur, 1 = full cible
@export var lock_smoothing_boost: float = 1.4
@export var size_lock_bonus: float = 1.5       ## léger dézoom quand une cible est verrouillée

@export_group("Cadrage combat")
@export var threat_range: float = 9.0        ## portée de prise en compte des ennemis
@export var threat_weight: float = 0.30      ## décalage max vers les ennemis
@export var threat_zoom: float = 2.0         ## dézoom quand des ennemis sont proches
@export var threat_smoothing: float = 3.0    ## lissage du barycentre

@export_group("Occlusion")
@export var occlusion_enabled: bool = true
@export var occlusion_mask: int = 1        ## calque du décor (murs, piliers, rampe)
@export var occlusion_alpha: float = 0.25  ## transparence de ce qui bloque la vue
@export var occlusion_fade_speed: float = 10.0
@export var occlusion_max_hits: int = 4    ## sécurité si plusieurs objets s'alignent
## Estompe aussi ce qui cache un ennemi, pas seulement le joueur.
@export var occlude_enemies: bool = true
@export var enemy_occlusion_range: float = 18.0  ## ennemis pris en compte autour du joueur
@export var enemy_aim_height: float = 0.8        ## point visé sur l'ennemi (milieu du corps)

@export_group("Salles")
## Marge entre le point suivi et les bords de la salle. Plus elle est grande,
## moins la caméra s'approche des murs (au-delà de la moitié de la salle,
## elle reste fixée au centre).
@export var bounds_margin: float = 4.0

var _has_bounds: bool = false
var _bounds := Rect2()
var _trans_t: float = 0.0
var _trans_dur: float = 0.0
var _trans_from := Vector3.ZERO

var _faded: Dictionary = {}   ## nœud visuel → alpha courant

var _threat := Vector3.ZERO
var _threat_w: float = 0.0

@onready var cam: Camera3D = $Camera3D

var _shake: float = 0.0
var _shake_time: float = 0.0

## En perspective, size ne fait rien : le zoom recule la caméra.
## perspective_distance correspond à size_normal ; les autres tailles en sont
## des multiples (sprint = 11.5 / 10 → 15 % plus loin).
var _zoom: float = 1.0

var lock_on: Node = null


func _ready() -> void:
	# Pas de dézoom visible au lancement : on part directement à la bonne taille
	_zoom = 1.0
	if _is_ortho():
		cam.size = size_normal * zoom_scale
	else:
		cam.position.z = perspective_distance


func _physics_process(delta: float) -> void:
	if target == null:
		return

	_update_threat(delta)
	_update_occlusion(delta)

	var focus: Vector3 = target.global_position + Vector3.UP * height_offset
	if _threat_w > 0.01:
		var tp: Vector3 = _threat
		tp.y = focus.y
		focus = focus.lerp(tp, threat_weight * _threat_w)

	focus = _clamp_to_bounds(focus)

	if _trans_dur > 0.0:
		# Glissement d'une salle à l'autre : trajectoire fixe et lissée, sans
		# le retard du suivi normal qui donnerait un départ mou.
		_trans_t += delta
		var k: float = smoothstep(0.0, 1.0, clampf(_trans_t / _trans_dur, 0.0, 1.0))
		global_position = _trans_from.lerp(focus, k)
		if _trans_t >= _trans_dur:
			_trans_dur = 0.0
	else:
		var t := 1.0 - exp(-smoothing * delta)
		global_position = global_position.lerp(focus, t)

	var wanted: float = size_sprint if target.is_sprinting else size_normal
	wanted += threat_zoom * _threat_w
	wanted *= zoom_scale

	# --- Zoom ---
	var zt := 1.0 - exp(-zoom_smoothing * delta)
	if _is_ortho():
		cam.size = lerpf(cam.size, wanted, zt)
	else:
		_zoom = lerpf(_zoom, wanted / maxf(size_normal * zoom_scale, 0.01), zt)
		cam.position.z = perspective_distance * _zoom

	# --- Secousse ---
	if _shake > 0.0:
		_shake = maxf(_shake - shake_decay * delta * _shake, 0.0)
		_shake_time += delta * shake_speed
		var s: float = _shake * _shake * shake_amount   # décroissance quadratique
		cam.position.x = sin(_shake_time) * s
		cam.position.y = cos(_shake_time * 1.37) * s
	else:
		cam.position.x = 0.0
		cam.position.y = 0.0


## Borne la caméra à une salle (rectangle x/z en coordonnées monde).
## instant : saute directement à la bonne position (premier affichage, réapparition).
func set_bounds(rect: Rect2, instant: bool = false) -> void:
	_bounds = rect
	_has_bounds = true
	_trans_dur = 0.0
	if instant and target != null:
		global_position = _clamp_to_bounds(target.global_position + Vector3.UP * height_offset)


## Change de salle en glissant pendant duration secondes.
func transition_to_bounds(rect: Rect2, duration: float) -> void:
	_bounds = rect
	_has_bounds = true
	_trans_from = global_position
	_trans_t = 0.0
	_trans_dur = maxf(duration, 0.01)


func clear_bounds() -> void:
	_has_bounds = false


func _clamp_to_bounds(p: Vector3) -> Vector3:
	if not _has_bounds:
		return p
	var inner: Rect2 = _bounds.grow(-bounds_margin)
	var c: Vector2 = _bounds.get_center()
	p.x = clampf(p.x, inner.position.x, inner.end.x) if inner.size.x > 0.0 else c.x
	p.z = clampf(p.z, inner.position.y, inner.end.y) if inner.size.y > 0.0 else c.y
	return p


func _is_ortho() -> bool:
	return cam.projection == Camera3D.PROJECTION_ORTHOGONAL


func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)

## Barycentre des ennemis proches, pondéré par leur proximité. Pas de cible
## unique : la caméra recule simplement vers le centre de gravité du danger,
## ce qui garde tout le monde dans le cadre sans que le joueur ait à désigner
## quoi que ce soit.
func _update_threat(delta: float) -> void:
	var sum := Vector3.ZERO
	var total: float = 0.0

	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var v: Vector3 = e.global_position - target.global_position
		v.y = 0.0
		var d: float = v.length()
		if d > threat_range:
			continue
		var w: float = 1.0 - (d / threat_range)
		sum += e.global_position * w
		total += w

	var t: float = 1.0 - exp(-threat_smoothing * delta)

	if total > 0.01:
		_threat = _threat.lerp(sum / total, t)
		_threat_w = lerpf(_threat_w, clampf(total, 0.0, 1.0), t)
	else:
		_threat_w = lerpf(_threat_w, 0.0, t)

## Pour le joueur et chaque ennemi proche, un rayon remonte vers la caméra.
## Ce qu'il traverse sur occlusion_mask est estompé ; on répète le tir en
## excluant ce qui vient d'être touché, pour attraper plusieurs objets alignés
## (deux piliers l'un derrière l'autre, par exemple).
##
## En orthographique, la ligne de vue d'un point est parallèle à l'axe de la
## caméra ; en perspective, elle part de la caméra elle-même.
func _update_occlusion(delta: float) -> void:
	if not occlusion_enabled or target == null:
		return

	var points: Array[Vector3] = [target.global_position + Vector3.UP * height_offset]
	if occlude_enemies:
		for e in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or not (e is Node3D):
				continue
			var ep: Vector3 = (e as Node3D).global_position
			if ep.distance_to(target.global_position) <= enemy_occlusion_range:
				# Centre et bords gauche/droite : un ennemi à cheval sur deux
				# tronçons de mur doit les faire estomper tous les deux.
				var c: Vector3 = ep + Vector3.UP * enemy_aim_height
				var side: Vector3 = cam.global_transform.basis.x * 0.45
				points.append(c)
				points.append(c - side)
				points.append(c + side)

	var blocking: Dictionary = {}
	var ortho: bool = _is_ortho()
	var back: Vector3 = cam.global_transform.basis.z * 60.0   # vers la caméra
	for p in points:
		_collect_blocking(p + back if ortho else cam.global_position, p, blocking)

	var t: float = 1.0 - exp(-occlusion_fade_speed * delta)
	var done: Array = []

	for visual in _faded.keys():
		var wanted: float = occlusion_alpha if blocking.has(visual) else 1.0
		var a: float = lerpf(_faded[visual], wanted, t)
		_faded[visual] = a
		_apply_alpha(visual, a)

		if not blocking.has(visual) and absf(a - 1.0) < 0.01:
			_apply_alpha(visual, 1.0)
			_set_transparent(visual, false)
			done.append(visual)

	for visual in done:
		_faded.erase(visual)


func _collect_blocking(from: Vector3, to: Vector3, blocking: Dictionary) -> void:
	var space := get_world_3d().direct_space_state
	var exclude: Array = []
	for i in occlusion_max_hits:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = occlusion_mask
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return

		var visual = hit.collider.get_meta("visual") if hit.collider.has_meta("visual") else null
		if visual != null and is_instance_valid(visual):
			blocking[visual] = true
			if not _faded.has(visual):
				_faded[visual] = 1.0
				_set_transparent(visual, true)

		exclude.append(hit.collider.get_rid())


## Les murs de l'arène sont des CSGBox3D (propriété material), ceux du
## donjon des MeshInstance3D (material_override) : on accepte les deux.
func _visual_mat(visual: Node3D) -> StandardMaterial3D:
	if visual is CSGShape3D:
		return (visual as CSGShape3D).get("material") as StandardMaterial3D
	if visual is GeometryInstance3D:
		return (visual as GeometryInstance3D).material_override as StandardMaterial3D
	return null


## Le visuel et ses enfants : un pilier détaillé (socle, bandes, chapiteau)
## doit s'estomper d'un bloc, pas seulement son volume principal.
func _visual_mats(visual: Node3D) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	var m: StandardMaterial3D = _visual_mat(visual)
	if m != null:
		out.append(m)
	for c in visual.get_children():
		if c is GeometryInstance3D:
			var cm := (c as GeometryInstance3D).material_override as StandardMaterial3D
			if cm != null:
				out.append(cm)
	return out


func _set_transparent(visual: Node3D, on: bool) -> void:
	for mat in _visual_mats(visual):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED


func _apply_alpha(visual: Node3D, a: float) -> void:
	for mat in _visual_mats(visual):
		mat.albedo_color.a = a