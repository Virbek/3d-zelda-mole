extends Node3D

@export var target: Node3D
@export var smoothing: float = 10.0
@export var height_offset: float = 1.0

@export_group("Zoom")
@export var size_normal: float = 12.0
@export var size_sprint: float = 14.5
@export var zoom_smoothing: float = 2.5

@onready var cam: Camera3D = $Camera3D

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var t := 1.0 - exp(-smoothing * delta)
	global_position = global_position.lerp(
		target.global_position + Vector3.UP * height_offset, t
	)

	var wanted: float = size_sprint if target.is_sprinting else size_normal
	var zt := 1.0 - exp(-zoom_smoothing * delta)
	cam.size = lerp(cam.size, wanted, zt)
