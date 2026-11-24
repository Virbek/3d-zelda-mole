extends Node

## Ralentit brièvement le temps global à l'impact.
## Le nœud doit tourner en mode ALWAYS pour continuer à décompter
## pendant que le reste du jeu est ralenti.
##
## Le décompte se fait en temps réel (horloge système) : avec une échelle à 0,
## le delta de _process vaut 0 et un décompte basé dessus ne finirait jamais.

var _end_usec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## duration : durée réelle en secondes. scale : 0 = arrêt total, 0.15 = très lent
func hit(duration: float, scale: float = 0.0) -> void:
	var end: int = Time.get_ticks_usec() + int(duration * 1_000_000.0)
	# Un impact plus long écrase un impact plus court en cours
	if end <= _end_usec:
		return
	_end_usec = end
	Engine.time_scale = scale


## Ralenti de fin de combat : plus long et moins figé qu'un hit stop, pour
## laisser voir le dernier ennemi tomber. Écrase tout gel plus court en cours.
func finale(duration: float = 0.55, scale: float = 0.15) -> void:
	_end_usec = 0
	hit(duration, scale)


func _process(_delta: float) -> void:
	if _end_usec == 0:
		return
	if Time.get_ticks_usec() >= _end_usec:
		_end_usec = 0
		Engine.time_scale = 1.0
