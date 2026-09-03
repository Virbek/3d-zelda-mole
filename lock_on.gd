extends Node

@export_flags_3d_physics var enemy_mask: int = 2
@export var lock_range: float = 14.0
@export var lose_range: float = 18.0       ## on lâche la cible au-delà
@export var prefer_screen_center: float = 0.6  ## 0 = le plus proche, 1 = le plus centré

@export var marker_scene: PackedScene
@export var marker_height: float = 2.1

signal target_changed(target: Node3D)

@onready var player: CharacterBody3D = get_parent()

var target = null

var _marker: Node3D

func _ready() -> void:
	if marker_scene != null:
		_marker = marker_scene.instantiate()
		player.get_tree().current_scene.add_child.call_deferred(_marker)
		_marker.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("lock_on"):
		return

	if target != null:
		_clear()
	else:
		var t := _find_best()
		print("cible retenue: ", t)
		if t != null:
			target = t
			if t.has_signal("died"):
				t.died.connect(_clear, CONNECT_ONE_SHOT)
			target_changed.emit(target)

func _physics_process(delta: float) -> void:
	if target == null:
		if _marker != null:
			_marker.visible = false
		return

	if not is_instance_valid(target) or _flat_distance(target) > lose_range:
		_clear()
		return

	if _marker != null:
		_marker.visible = true
		_marker.global_position = target.global_position + Vector3.UP * marker_height
		_marker.rotate_y(delta * 2.0)


func _clear() -> void:
	target = null
	target_changed.emit(null)


func _flat_distance(node: Node3D) -> float:
	var v: Vector3 = node.global_position - player.global_position
	v.y = 0.0
	return v.length()


## Choisit l'ennemi le plus pertinent : proche ET vers le centre de l'écran
func _find_best() -> Node3D:
	var space := player.get_world_3d().direct_space_state
 
	var shape := SphereShape3D.new()
	shape.radius = lock_range
 
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), player.global_position)
	params.collision_mask = enemy_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false

 
	var results := space.intersect_shape(params, 24)
 
	var cam := player.get_viewport().get_camera_3d()
	var screen_center: Vector2 = player.get_viewport().get_visible_rect().size * 0.5
 
	var best: Node3D = null
	var best_score: float = -INF
 
	for hit in results:
		var col = hit.collider
		var e = col.get_parent()
 
		if e == null:
			continue
 
		if not e.has_method("take_hit"):
			continue
 
		var d: float = _flat_distance(e)
		var score: float = 1.0 - (d / lock_range)
 
		# Bonus pour ce qui est près du centre de l'écran
		if cam != null:
			if cam.is_position_behind(e.global_position):
				continue
			var sp: Vector2 = cam.unproject_position(e.global_position)
			var off: float = sp.distance_to(screen_center) / screen_center.length()
			score = lerp(score, 1.0 - off, prefer_screen_center)
 
		if score > best_score:
			best_score = score
			best = e
 
	return best
