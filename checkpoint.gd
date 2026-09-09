extends Area3D
class_name Checkpoint

## Dès que le joueur entre dans cette zone, on mémorise sa position comme
## point de réapparition pour la prochaine mort.

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	Checkpoints.set_checkpoint(global_position)