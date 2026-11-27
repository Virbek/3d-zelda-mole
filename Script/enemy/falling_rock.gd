extends Node3D
class_name FallingRock

## Caillou qui tombe du plafond pendant la revanche du boss. Une ombre
## s'élargit au sol, le bloc tombe, et éclate en morceaux à l'impact : il
## blesse le joueur s'il est encore dans l'ombre.
##
## Construit par script. Origine au sol, au centre de l'ombre.

const ROCK := Color("#8a7458")
const ROCK_DARK := Color("#5e4c38")
const DROP_HEIGHT: float = 9.0
const FALL_TIME: float = 0.32     ## la chute elle-même, à la fin de l'annonce

var radius: float = 1.1
var warn_time: float = 1.1       ## durée totale entre l'apparition de l'ombre et l'impact
var damage: int = 1

var _t: float = 0.0
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D
var _rock: MeshInstance3D
var _landed: bool = false


static func spawn(parent: Node, ground: Vector3, r: float, warn: float, dmg: int) -> FallingRock:
	var f := FallingRock.new()
	f.radius = r
	f.warn_time = warn
	f.damage = dmg
	parent.add_child(f)
	f.global_position = ground
	return f


func _ready() -> void:
	_shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	disc.radial_segments = 16
	_shadow.mesh = disc
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_color = Color(0.1, 0.06, 0.04, 0.0)
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.position.y = 0.03
	_shadow.scale = Vector3(0.2, 1.0, 0.2)
	add_child(_shadow)

	_rock = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius * 0.65
	s.height = radius * 1.1
	s.radial_segments = 6     # facettes : un bloc, pas une bille
	s.rings = 3
	_rock.mesh = s
	_rock.material_override = ToonBuilder.toon_material(ROCK, 0.015)
	_rock.rotation = Vector3(randf(), randf(), randf()) * TAU
	_rock.position.y = DROP_HEIGHT
	_rock.visible = false
	add_child(_rock)


func _physics_process(delta: float) -> void:
	_t += delta
	if _landed:
		return
	var k: float = clampf(_t / maxf(warn_time, 0.01), 0.0, 1.0)
	_shadow.scale = Vector3.ONE * lerpf(0.2, 1.0, k)
	_shadow.scale.y = 1.0
	_shadow_mat.albedo_color.a = 0.55 * k

	var fall_start: float = warn_time - FALL_TIME
	if _t >= fall_start:
		_rock.visible = true
		var f: float = clampf((_t - fall_start) / FALL_TIME, 0.0, 1.0)
		_rock.position.y = lerpf(DROP_HEIGHT, radius * 0.4, f * f)
		_rock.rotate_x(delta * 4.0)
	if _t >= warn_time:
		_impact()


func _impact() -> void:
	_landed = true
	Sfx.play("hit_heavy", global_position)
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.get_parent().has_method("shake"):
		cam.get_parent().shake(0.15)
	_hurt_player()
	_burst()
	_rock.visible = false
	var t := create_tween()
	t.tween_property(_shadow_mat, "albedo_color:a", 0.0, 0.3)
	t.tween_callback(queue_free)


func _hurt_player() -> void:
	var hurt := get_tree().get_first_node_in_group("player_hurt") as Area3D
	if hurt == null or not hurt.has_method("take_damage"):
		return
	var v: Vector3 = hurt.global_position - global_position
	if absf(v.y) > 2.5:
		return
	v.y = 0.0
	if v.length() > radius + 0.3:
		return
	hurt.take_damage(damage, v.normalized() if v.length() > 0.01 else Vector3.BACK)


## Éclats : quelques boîtes qui roulent et disparaissent.
func _burst() -> void:
	for i in 6:
		var c := MeshInstance3D.new()
		c.mesh = ToonBuilder.box(Vector3.ONE * randf_range(0.15, 0.3))
		c.material_override = ToonBuilder.toon_material(ROCK if i % 2 else ROCK_DARK, 0.0)
		add_child(c)
		c.position = Vector3(0.0, 0.3, 0.0)
		var out := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * randf_range(0.8, 1.6)
		var t := c.create_tween()
		t.tween_property(c, "position", out * 0.5 + Vector3.UP * randf_range(0.5, 0.9), 0.15).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "position", out + Vector3.UP * 0.1, 0.2).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(c, "scale", Vector3.ONE * 0.2, 0.3)
		t.tween_callback(c.queue_free)
