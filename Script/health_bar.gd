extends Node3D

@export var hide_when_full: bool = true
@export var fade_delay: float = 2.5
@onready var fill_pivot: Node3D = $FillPivot

var _ratio: float = 1.0
var _timer: float = 0.0


func _ready() -> void:
	if hide_when_full:
		visible = false



func set_ratio(value: float) -> void:
	_ratio = clampf(value, 0.0, 1.0)
	fill_pivot.scale.x = maxf(_ratio, 0.001)
	_timer = fade_delay
	visible = true


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		global_rotation = cam.global_rotation
	
	if not hide_when_full or not visible:
		return
	if _ratio >= 1.0 or _ratio <= 0.0:
		_timer = maxf(_timer - delta, 0.0)
		if _timer == 0.0:
			visible = false