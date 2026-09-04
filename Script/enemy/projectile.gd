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

## Renseignés par le tireur au moment du spawn
var direction: Vector3 = Vector3.FORWARD
var shooter: Node3D = null

var _life: float = 0.0
var _dead: bool = false

@onready var mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_life += delta
	if _life >= lifetime:
		_pop()
		return

	global_position += direction * speed * delta
	mesh.rotate_y(spin_speed * delta)


## Zones : c'est ici que le joueur se fait toucher.
func _on_area_entered(area: Area3D) -> void:
	if _dead or not area.is_in_group("player_hurt"):
		return

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