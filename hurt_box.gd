extends Area3D

## Zone de dégâts du joueur, attachée au torse. Comme Body est en top_level,
## cette Area3D suit le mesh où qu'il aille — c'est donc le buste visible qui
## se fait toucher, pas la capsule de déplacement restée au sol.
##
## Elle ne contient aucune logique : la vie, l'invulnérabilité et la mort
## restent dans Player.gd. Ce script n'est qu'un relais.
##
## Montage : Layer 3 (dégâts joueur), aucun masque, groupe "player_hurt".

@export var player_path: NodePath

@onready var player: CharacterBody3D = get_node(player_path)


func _ready() -> void:
	add_to_group("player_hurt")

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	# Une zone non-monitorable est invisible pour les attaques ennemies.
	# Plus sûr qu'un filtre dans take_damage : le projectile passe au travers
	# au lieu d'exploser sans faire de dégâts.
	monitorable = not player.is_invulnerable

## Appelé par les attaques ennemies qui trouvent cette zone.
func take_damage(amount: int, direction: Vector3) -> void:
	if player == null or player.is_invulnerable:
		return
	if player.has_method("take_damage"):
		player.take_damage(amount, direction)


## Les ennemis visent ce point plutôt que la capsule : ils frappent là où
## le joueur se voit, ce qui rend les esquives lisibles.
func get_aim_position() -> Vector3:
	return global_position