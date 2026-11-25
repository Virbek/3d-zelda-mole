extends Area3D

## Projectile en ligne droite. Se détruit au contact de la zone de dégâts
## du joueur, d'un mur, ou après expiration de sa durée de vie.
##
## Il traverse volontairement les autres ennemis : sinon un tireur placé
## derrière un chargeur ne pourrait jamais toucher, ce qui rend son
## comportement illisible pour le joueur.
##
## Le joueur n'est plus touché via sa capsule mais via la HurtBox portée par
## son torse : c'est le buste visible qui encaisse, pas les pieds.

@export var speed: float = 9.0
@export var damage: int = 1
@export var lifetime: float = 4.0
@export var spin_speed: float = 6.0
## Layers du décor qui arrêtent le tir (murs, poteaux : layer 1 par défaut).
@export_flags_3d_physics var world_mask: int = 1
## Distance au torse en dessous de laquelle une esquive "consomme" le tir.
@export var dodge_radius: float = 1.1

## Renseignés par le tireur au moment du spawn
var direction: Vector3 = Vector3.FORWARD
var shooter: Node3D = null

var _life: float = 0.0
var _dead: bool = false
## Vrai une fois que le joueur l'a esquivé : il ne peut plus le toucher,
## même si l'invincibilité se termine alors qu'il chevauche encore le torse.
var _dodged: bool = false
var _player_hurt: Area3D = null

@onready var mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	for n in get_tree().get_nodes_in_group("player_hurt"):
		_player_hurt = n as Area3D
		break


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_life += delta
	if _life >= lifetime:
		_pop()
		return

	var from: Vector3 = global_position
	var to: Vector3 = from + direction * speed * delta

	# Balayage : le décor n'est pas dans le masque de l'Area3D, et un tir
	# rapide pourrait de toute façon sauter par-dessus un poteau fin.
	var hit_pos: Variant = _sweep_world(from, to)
	if hit_pos != null:
		global_position = hit_pos
		_pop()
		return

	global_position = to
	mesh.rotate_y(spin_speed * delta)
	_check_dodge()


## Premier point de décor touché entre from et to, ou null.
func _sweep_world(from: Vector3, to: Vector3) -> Variant:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, world_mask)
	var exclude: Array[RID] = []
	if shooter is CollisionObject3D:
		exclude.append((shooter as CollisionObject3D).get_rid())
	# Joueur et ennemis ne bloquent pas le tir : on les exclut et on relance
	for i in 4:
		query.exclude = exclude
		var res: Dictionary = space.intersect_ray(query)
		if res.is_empty():
			return null
		var col: Object = res["collider"]
		if col is CharacterBody3D or col is RigidBody3D:
			exclude.append(res["rid"])
			continue
		return res["position"]
	return null


## Si le joueur esquive pendant que le tir passe sur lui, le tir est perdu.
func _check_dodge() -> void:
	if _dodged or _player_hurt == null or not is_instance_valid(_player_hurt):
		return
	if not _player_is_dodging():
		return
	if global_position.distance_to(_player_hurt.global_position) <= dodge_radius:
		_dodged = true


func _player_is_dodging() -> bool:
	if _player_hurt == null or not is_instance_valid(_player_hurt):
		return false
	var pl: Node = _player_hurt.get("player")
	if pl == null:
		return false
	return bool(pl.get("is_dodging")) or bool(pl.get("is_invulnerable"))


func _on_area_entered(area: Area3D) -> void:
	if _dead or _dodged or not area.is_in_group("player_hurt"):
		return
	# Toute la durée de l'esquive compte, pas seulement la fenêtre d'iframes
	if _player_is_dodging():
		_dodged = true
		return

	# On marque AVANT d'infliger : _pop passe par set_deferred, donc la zone
	# reste active jusqu'à la fin de la frame et peut retoucher entre-temps.
	_dead = true

	if area.has_method("take_damage"):
		var dir: Vector3 = area.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.01:
			area.take_damage(damage, dir.normalized())

	_pop()


## Corps : uniquement le décor. Le projectile s'écrase sur les murs.
func _on_body_entered(body: Node3D) -> void:
	if _dead or body == shooter:
		return

	# Les ennemis ne bloquent pas le tir
	if body.has_method("take_hit"):
		return

	# La capsule du joueur ne prend plus de dégâts : elle ne sert qu'au
	# déplacement. On la laisse passer pour ne pas absorber le tir devant
	# le torse, qui est la vraie cible.
	if body.has_method("take_damage"):
		return

	_pop()


## Petite implosion avant disparition : sans ça le projectile s'évapore
## sans qu'on comprenne qu'il a touché quelque chose.
func _pop() -> void:
	_dead = true
	set_deferred("monitoring", false)

	var t := create_tween().set_parallel(true)
	t.tween_property(mesh, "scale", Vector3(1.8, 1.8, 1.8), 0.12)\
		.set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.12)\
		.set_ease(Tween.EASE_IN)

	await t.finished
	queue_free()