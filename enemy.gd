extends StaticBody3D

@export var knockback_distance: float = 0.9
@export var knockback_time: float = 0.18
@export var recover_time: float = 0.35
@export var flash_color := Color(1.0, 0.15, 0.15)
@export var flash_count: int = 3
@export var flash_duration: float = 0.4

@onready var mesh: MeshInstance3D = $MeshInstance3D

var _mat: StandardMaterial3D
var _base_color: Color
var _home := Vector3.ZERO
var _tween: Tween
var _flash_tween: Tween

func _ready() -> void:
	_home = global_position
	_mat = mesh.get_active_material(0).duplicate()
	mesh.set_surface_override_material(0, _mat)
	_base_color = _mat.albedo_color

func take_hit(direction: Vector3) -> void:
	_knockback(direction)
	_flash()

func _knockback(direction: Vector3) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()

	var away: Vector3 = _home + direction * knockback_distance

	_tween = create_tween()
	_tween.tween_property(self, "global_position", away, knockback_time)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	_tween.tween_property(self, "global_position", _home, recover_time)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()

	var step: float = flash_duration / (flash_count * 2)
	_flash_tween = create_tween()
	for i in flash_count:
		_flash_tween.tween_property(_mat, "albedo_color", flash_color, step * 0.4)
		_flash_tween.tween_property(_mat, "albedo_color", _base_color, step * 1.6)
