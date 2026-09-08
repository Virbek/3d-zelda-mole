extends Node3D

@export var target: Node3D
@export var smoothing: float = 10.0
@export var height_offset: float = 1.0

@export_group("Zoom")
@export var size_normal: float = 12.0
@export var size_sprint: float = 14.5
@export var zoom_smoothing: float = 2.5

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

var _faded: Dictionary = {}   ## nœud visuel → alpha courant

var _threat := Vector3.ZERO
var _threat_w: float = 0.0

@onready var cam: Camera3D = $Camera3D

var _shake: float = 0.0
var _shake_time: float = 0.0

var lock_on: Node = null


func _ready() -> void:
	return


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

	var t := 1.0 - exp(-smoothing * delta)
	global_position = global_position.lerp(focus, t)

	var wanted: float = size_sprint if target.is_sprinting else size_normal
	wanted += threat_zoom * _threat_w

	# --- Zoom ---
	
	
	var zt := 1.0 - exp(-zoom_smoothing * delta)
	cam.size = lerp(cam.size, wanted, zt)

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

## Rayon caméra → joueur. Ce qu'il traverse sur occlusion_mask est estompé ;
## on répète le tir en excluant ce qui vient d'être touché, pour attraper
## plusieurs objets alignés (deux piliers l'un derrière l'autre, par exemple).
func _update_occlusion(delta: float) -> void:
	if not occlusion_enabled or target == null:
		return

	var space := get_world_3d().direct_space_state
	var from: Vector3 = cam.global_position
	var to: Vector3 = target.global_position + Vector3.UP * height_offset

	var blocking: Dictionary = {}
	var exclude: Array = []

	for i in occlusion_max_hits:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = occlusion_mask
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break

		var visual = hit.collider.get_meta("visual") if hit.collider.has_meta("visual") else null
		if visual != null and is_instance_valid(visual):
			blocking[visual] = true
			if not _faded.has(visual):
				_faded[visual] = 1.0
				_set_transparent(visual, true)

		exclude.append(hit.collider.get_rid())

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


func _set_transparent(visual: Node3D, on: bool) -> void:
	var mat: StandardMaterial3D = visual.material
	if mat == null:
		return
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED


func _apply_alpha(visual: Node3D, a: float) -> void:
	var mat: StandardMaterial3D = visual.material
	if mat == null:
		return
	mat.albedo_color.a = a