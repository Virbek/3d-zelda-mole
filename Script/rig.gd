extends Node3D

@export var player_path: NodePath

@export_group("Pieds")
@export var stance_width: float = 0.32     ## écartement latéral
@export var step_threshold: float = 0.55   ## distance avant de déclencher un pas
@export var step_duration: float = 0.16    ## durée d'un pas
@export var step_height: float = 0.22      ## hauteur de l'arc
@export var step_lead: float = 0.45        ## anticipation dans la direction du mouvement 

@export_group("Corps")
@export var body_height: float = 1.0
@export var stiffness: float = 90.0        ## force du champ d'attraction
@export var damping: float = 9.0           ## plus bas = plus de rebond
@export var lean_degrees: float = 14.0
@export var lean_pull_scale: float = 0.35   ## étirement (en unités) pour atteindre l'inclinaison max

@onready var player: CharacterBody3D = get_node(player_path)
@onready var body: Node3D = $Body
@onready var foot_l: Node3D = $FootL
@onready var foot_r: Node3D = $FootR
@export var sprint_lean_multiplier: float = 1.7
@export var sprint_lead_multiplier: float = 1.8

@export_group("Ressenti des pas")
@export var bob_height: float = 0.07      ## montée du corps pendant un pas
@export var sway_degrees: float = 5.0     ## roulis vers le pied d'appui
@export var push_impulse: float = 0.9     ## coup de reins au départ du pas
@export var land_impulse: float = 1.3     ## encaissement à la pose

class Foot:
	var node: Node3D
	var side: float = 1.0
	var planted := Vector3.ZERO
	var stepping := false
	var t := 0.0
	var from := Vector3.ZERO
	var to := Vector3.ZERO

var _feet := []
var _body_vel := Vector3.ZERO
var _body_pos := Vector3.ZERO

func _ready() -> void:
	for n in [body, foot_l, foot_r]:
		n.top_level = true

	for data in [[foot_l, -1.0], [foot_r, 1.0]]:
		var f := Foot.new()
		f.node = data[0]
		f.side = data[1]
		_feet.append(f)

	# Position initiale : pieds au repos, corps au-dessus
	for f in _feet:
		f.planted = _rest_target(f)
		f.node.global_position = f.planted
	_body_pos = player.global_position + Vector3.UP * body_height
	body.global_position = _body_pos

func _physics_process(delta: float) -> void:
	_update_feet(delta)
	_update_body(delta)

# Où le pied "devrait" être, compte tenu de la position et de la vitesse actuelles
func _rest_target(f: Foot) -> Vector3:
	var b := player.global_transform.basis
	var hv := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var lead := Vector3.ZERO
	if hv.length() > 0.1:
		var l := step_lead
		if player.is_sprinting:
			l *= sprint_lead_multiplier
		lead = hv.normalized() * l

	var p: Vector3 = player.global_position + b.x * f.side * stance_width + lead
	# Cherche le sol réel sous la position visée
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		p + Vector3.UP * 2.0,
		p + Vector3.DOWN * 2.0
	)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		p.y = player.global_position.y
	else:
		p.y = hit.position.y

	return p

func _update_feet(delta: float) -> void:
	# Faire avancer les pas en cours
	for f in _feet:
		if f.stepping:
			f.t += delta / step_duration
			if f.t >= 1.0:
				f.t = 1.0
				f.stepping = false
				f.planted = f.to
				_body_vel.y -= land_impulse
			var p: Vector3 = f.from.lerp(f.to, f.t)
			p.y += sin(f.t * PI) * step_height   # arc du pas
			f.node.global_position = p
		else:
			f.node.global_position = f.planted

	# Un seul pied en l'air à la fois
	for f in _feet:
		if f.stepping:
			return

	# Déclencher le pas du pied le plus en retard
	var worst: Foot = null
	var worst_dist := step_threshold
	for f in _feet:
		var d: float = f.planted.distance_to(_rest_target(f))
		if d > worst_dist:
			worst_dist = d
			worst = f

	if worst != null:
		worst.stepping = true
		worst.t = 0.0
		worst.from = worst.planted
		worst.to = _rest_target(worst)

		var dir: Vector3 = worst.to - worst.from
		dir.y = 0.0
		if dir.length() > 0.01:
			_body_vel += dir.normalized() * push_impulse

func _update_body(delta: float) -> void:
	var mid: Vector3 = (foot_l.global_position + foot_r.global_position) * 0.5
	var target: Vector3 = mid + Vector3.UP * body_height

	# --- Ressort : la traction, lente ---
	var to_target: Vector3 = target - _body_pos
	_body_vel += to_target * stiffness * delta
	_body_vel *= exp(-damping * delta)
	_body_pos += _body_vel * delta

	# --- Rythme des pas : rapide, hors ressort ---
	var step_t := -1.0
	var support := 0.0
	for f in _feet:
		if f.stepping:
			step_t = f.t
			support = -f.side   # l'appui est sur le pied resté au sol

	var bob := 0.0
	var sway := 0.0
	if step_t >= 0.0:
		var s := sin(step_t * PI)
		bob = s * bob_height
		sway = s * support * deg_to_rad(sway_degrees)

	body.global_position = _body_pos + Vector3.UP * bob

	# --- Inclinaison ---
	var pull := to_target
	pull.y = 0.0
	var local_pull: Vector3 = Basis(Vector3.UP, player.rotation.y).inverse() * pull
	local_pull /= lean_pull_scale

	var lean := deg_to_rad(lean_degrees)
	if player.is_sprinting:
		lean *= sprint_lean_multiplier
	body.rotation.y = player.rotation.y
	body.rotation.x = lerp(body.rotation.x, -clampf(local_pull.z, -1.0, 1.0) * lean, 10.0 * delta)
	body.rotation.z = lerp(body.rotation.z, clampf(local_pull.x, -1.0, 1.0) * lean, 10.0 * delta) + sway