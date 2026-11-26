extends Area3D
class_name Checkpoint

## Dès que le joueur entre dans cette zone, on mémorise sa position comme
## point de réapparition pour la prochaine mort.

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	# Son seulement au premier passage : Checkpoints survit au rechargement,
	# donc réapparaître dessus ne le rejoue pas.
	var is_new: bool = not Checkpoints.has_checkpoint \
			or not Checkpoints.position.is_equal_approx(global_position)
	Checkpoints.set_checkpoint(global_position)
	if is_new:
		Sfx.play("checkpoint", global_position)