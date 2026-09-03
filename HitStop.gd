extends Node

## Ralentit brièvement le temps global à l'impact.
## Le nœud doit tourner en mode ALWAYS pour continuer à décompter
## pendant que le reste du jeu est ralenti.

var _remaining: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## duration : durée réelle en secondes. scale : 0 = arrêt total, 0.15 = très lent
func hit(duration: float, scale: float = 0.0) -> void:
	# Un impact plus fort écrase un impact plus faible en cours
	if duration <= _remaining:
		return
	_remaining = duration
	Engine.time_scale = scale


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return

	# get_process_delta_time est déjà affecté par time_scale,
	# on repasse donc en temps réel pour décompter correctement
	_remaining -= delta / maxf(Engine.time_scale, 0.001)

	if _remaining <= 0.0:
		_remaining = 0.0
		Engine.time_scale = 1.0