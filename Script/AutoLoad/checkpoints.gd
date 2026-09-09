extends Node

## Autoload. Mémorise le dernier checkpoint franchi et gère le fondu noir
## qui masque la relance de la scène — sans lui, on voit un instant le
## joueur à sa position de scène d'origine avant que tout ne se remette
## en place au checkpoint.

@export var fade_out_time: float = 0.35
@export var fade_in_time: float = 0.45
@export var hold_time: float = 0.15   ## reste noir un instant après le reload, le temps que tout s'installe

var position: Vector3 = Vector3.ZERO
var has_checkpoint: bool = false

var _overlay: ColorRect


func _ready() -> void:
	_build_overlay()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100   # au-dessus de tout le reste, HUD compris
	add_child(layer)

	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)


func set_checkpoint(pos: Vector3) -> void:
	position = pos
	has_checkpoint = true


func respawn() -> void:
	var fade_out := create_tween()
	fade_out.tween_property(_overlay, "color:a", 1.0, fade_out_time)
	await fade_out.finished

	get_tree().reload_current_scene()
	await get_tree().create_timer(hold_time).timeout

	var fade_in := create_tween()
	fade_in.tween_property(_overlay, "color:a", 0.0, fade_in_time)