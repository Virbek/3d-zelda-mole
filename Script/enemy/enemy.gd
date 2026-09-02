extends StaticBody3D

@export var max_health: int = 5
@export var damage_per_hit: int = 1

@export_group("Recul")
@export var knockback_distance: float = 0.9
@export var knockback_time: float = 0.18
@export var recover_time: float = 0.35

@export_group("Flash")
@export var flash_color := Color(1.0, 0.15, 0.15)
@export var flash_count: int = 3
@export var flash_duration: float = 0.4

@export_group("Mort")
@export var death_time: float = 0.45
@export var death_launch: float = 1.6

signal died

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var health_bar: Node3D = $HealthBar
@onready var hurt_box: Area3D = $HurtBox

var health: int
var _mat: StandardMaterial3D
var _base_color: Color
var _home := Vector3.ZERO
var _tween: Tween
var _flash_tween: Tween
var _dead := false


func _ready() -> void:
	health = max_health
	_home = global_position
	_mat = mesh.get_active_material(0).duplicate()
	mesh.set_surface_override_material(0, _mat)
	_base_color = _mat.albedo_color
	health_bar.set_ratio(1.0)


func take_hit(direction: Vector3) -> void:
	if _dead:
		return

	health -= damage_per_hit
	health_bar.set_ratio(float(health) / float(max_health))

	if health <= 0:
		_die(direction)
		return

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


func _die(direction: Vector3) -> void:
	_dead = true
	died.emit()

	# On coupe tout de suite les interactions
	hurt_box.monitorable = false
	set_collision_layer_value(1, false)
	health_bar.visible = false

	if _tween != null and _tween.is_running():
		_tween.kill()
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()

	_mat.albedo_color = flash_color

	# Le corps part en arrière, s'écrase et disparaît
	var away: Vector3 = global_position + direction * death_launch + Vector3.UP * 0.4

	var d := create_tween().set_parallel(true)
	d.tween_property(self, "global_position", away, death_time)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	d.tween_property(self, "scale", Vector3(1.3, 0.05, 1.3), death_time)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	d.tween_property(_mat, "albedo_color:a", 0.0, death_time)

	await d.finished
	queue_free()
