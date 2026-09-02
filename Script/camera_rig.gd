extends Node3D

@export var target: Node3D
@export var smoothing: float = 10.0

func _physics_process(delta: float) -> void:
    if target == null:
        return
    var t := 1.0 - exp(-smoothing * delta)
    global_position = global_position.lerp(target.global_position, t)
