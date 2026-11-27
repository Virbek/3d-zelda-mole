extends Node3D
class_name FissureLine

## Attaque en ligne du boss pendant la revanche : à l'atterrissage, une
## fissure part de ses pieds vers le joueur et fait jaillir des pics de
## roche sur son passage. Le front de la fissure touche une seule fois ;
## on l'évite en s'écartant de la ligne, ou en esquivant à travers.
##
## Construit par script. Origine au sol, au départ de la ligne.

const ROCK := Color("#8a7458")
const ROCK_DARK := Color("#5e4c38")
const CRACK := Color(1.0, 0.55, 0.15)

var direction := Vector3.FORWARD
var length: float = 16.0
var speed: float = 12.0
var width: float = 1.0
var damage: int = 1
var spacing: float = 0.7          ## un pic tous les X mètres

var _head: float = 0.0
var _next_spike: float = 0.6     ## laisse le boss dégagé : pas de pic dans ses pieds
var _hit: bool = false
var _done: bool = false


static func spawn(parent: Node, origin: Vector3, dir: Vector3, len: float, spd: float, band: float, dmg: int) -> FissureLine:
	var f := FissureLine.new()
	dir.y = 0.0
	f.direction = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	f.length = len
	f.speed = spd
	f.width = band
	f.damage = dmg
	parent.add_child(f)
	f.global_position = origin
	return f


func _physics_process(delta: float) -> void:
	if _done:
		return
	_head = minf(_head + speed * delta, length)
	while _next_spike <= _head:
		_spawn_spike(_next_spike)
		_next_spike += spacing
	if not _hit:
		_check_player()
	if _head >= length:
		_done = true
		# Les pics se rétractent seuls ; on attend le dernier
		get_tree().create_timer(1.2).timeout.connect(queue_free)


func _spawn_spike(at: float) -> void:
	var side := direction.cross(Vector3.UP)
	var spike := MeshInstance3D.new()
	var h: float = randf_range(0.7, 1.1)
	spike.mesh = ToonBuilder.box(Vector3(randf_range(0.35, 0.5), h, randf_range(0.35, 0.5)))
	spike.material_override = ToonBuilder.toon_material(ROCK if randf() < 0.6 else ROCK_DARK, 0.01)
	spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spike)
	var base: Vector3 = direction * at + side * randf_range(-0.2, 0.2)
	spike.position = base + Vector3.DOWN * h * 0.5
	spike.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))

	# Lueur de fissure au pied du pic
	var glow := MeshInstance3D.new()
	glow.mesh = ToonBuilder.box(Vector3(0.18, 0.02, spacing + 0.1))
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(CRACK, 0.9)
	glow.material_override = gm
	add_child(glow)
	glow.position = direction * at + Vector3.UP * 0.02
	glow.look_at(global_position + glow.position + direction, Vector3.UP)

	var t := spike.create_tween()
	t.tween_property(spike, "position", base + Vector3.UP * h * 0.25, 0.08).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_interval(0.35)
	t.tween_property(spike, "position", base + Vector3.DOWN * h * 0.6, 0.3).set_ease(Tween.EASE_IN)
	t.tween_callback(spike.queue_free)
	var g := glow.create_tween()
	g.tween_interval(0.25)
	g.tween_property(gm, "albedo_color:a", 0.0, 0.4)
	g.tween_callback(glow.queue_free)


func _check_player() -> void:
	var hurt := get_tree().get_first_node_in_group("player_hurt") as Area3D
	if hurt == null or not hurt.has_method("take_damage"):
		return
	var v: Vector3 = hurt.global_position - global_position
	if absf(v.y) > 2.0:
		return
	v.y = 0.0
	var along: float = v.dot(direction)
	# Seul le front de la fissure fait mal (pas ce qui reste derrière)
	if along < _head - 1.4 or along > _head + 0.3 or along < 0.0:
		return
	var lateral: float = absf(v.dot(direction.cross(Vector3.UP)))
	if lateral > width * 0.5 + 0.35:
		return
	var pl: Node = hurt.get("player")
	if pl != null and (bool(pl.get("is_invulnerable")) or bool(pl.get("is_dodging"))):
		_hit = true
		return
	_hit = true
	hurt.take_damage(damage, direction)
