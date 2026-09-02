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
	body.global_position = player.global_position + Vector3.UP * body_height

func _physics_process(delta: float) -> void:
	_update_feet(delta)
	_update_body(delta)

# Où le pied "devrait" être, compte tenu de la position et de la vitesse actuelles
func _rest_target(f: Foot) -> Vector3:
	var b := player.global_transform.basis
	var hv := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var lead := Vector3.ZERO
	if hv.length() > 0.1:
		lead = hv.normalized() * step_lead

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

func _update_body(delta: float) -> void:
	var mid: Vector3 = (foot_l.global_position + foot_r.global_position) * 0.5
	var target: Vector3 = mid + Vector3.UP * body_height

	var to_target: Vector3 = target - body.global_position
	_body_vel += to_target * stiffness * delta
	_body_vel *= exp(-damping * delta)
	body.global_position += _body_vel * delta

	# L'étirement du ressort EST la force subie : on incline dessus.
	var pull := to_target
	pull.y = 0.0
	var local_pull: Vector3 = Basis(Vector3.UP, player.rotation.y).inverse() * pull
	local_pull /= lean_pull_scale

	var lean := deg_to_rad(lean_degrees)
	body.rotation.y = player.rotation.y
	# Tiré par les pieds : le bas suit la traction, le haut part en arrière
	body.rotation.x = lerp(body.rotation.x, -clampf(local_pull.z, -1.0, 1.0) * lean, 10.0 * delta)
	body.rotation.z = lerp(body.rotation.z, clampf(local_pull.x, -1.0, 1.0) * lean, 10.0 * delta)