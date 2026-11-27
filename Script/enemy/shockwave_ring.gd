extends Node3D
class_name ShockwaveRing

## Onde de choc du boss en phase 2 : un anneau qui part de ses pieds et
## s'élargit au ras du sol. Il touche le joueur une seule fois s'il se trouve
## dans la bande de l'anneau au moment où elle passe. Se passe en esquivant à
## travers (invincibilité de l'esquive) : la HurtBox du joueur ignore les
## dégâts pendant les iframes.
##
## Construit par script. Origine au sol, au centre de l'onde.

const WAVE_COLOR := Color(1.0, 0.45, 0.1)
const CORE_COLOR := Color(1.0, 0.85, 0.5)

var max_radius: float = 8.0
var duration: float = 0.9          ## temps pour atteindre max_radius
var thickness: float = 0.9         ## largeur de la bande qui fait mal
var damage: int = 2

var _t: float = 0.0
var _hit: bool = false
var _ring: MeshInstance3D
var _torus: TorusMesh
var _core: MeshInstance3D
var _core_torus: TorusMesh
var _mat: StandardMaterial3D


static func spawn(parent: Node, center: Vector3, radius: float, time: float, band: float, dmg: int) -> ShockwaveRing:
	var w := ShockwaveRing.new()
	w.max_radius = radius
	w.duration = time
	w.thickness = band
	w.damage = dmg
	parent.add_child(w)
	w.global_position = center
	return w


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(WAVE_COLOR, 0.85)

	_torus = TorusMesh.new()
	_torus.rings = 48
	_torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = _torus
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(1.0, 0.35, 1.0)   # écrasé : un bourrelet de sable, pas un donut
	add_child(_ring)

	# Liseré clair au sommet de la vague
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = CORE_COLOR
	_core_torus = TorusMesh.new()
	_core_torus.rings = 48
	_core_torus.ring_segments = 4
	_core = MeshInstance3D.new()
	_core.mesh = _core_torus
	_core.material_override = core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.position.y = 0.12
	_core.scale = Vector3(1.0, 0.3, 1.0)
	add_child(_core)
	_update_shape(0.05)


func _physics_process(delta: float) -> void:
	_t += delta
	var k: float = clampf(_t / maxf(duration, 0.01), 0.0, 1.0)
	# Départ rapide, puis ralentit en s'étalant
	var r: float = max_radius * (1.0 - pow(1.0 - k, 1.6))
	_update_shape(maxf(r, 0.05))
	_mat.albedo_color.a = 0.85 * (1.0 - k * 0.6)

	if not _hit:
		_check_player(r)

	if k >= 1.0:
		var t := create_tween()
		t.tween_property(_mat, "albedo_color:a", 0.0, 0.15)
		t.tween_callback(queue_free)
		set_physics_process(false)


func _update_shape(r: float) -> void:
	var half: float = thickness * 0.5
	_torus.inner_radius = maxf(r - half, 0.01)
	_torus.outer_radius = r + half
	_core_torus.inner_radius = maxf(r - 0.08, 0.01)
	_core_torus.outer_radius = r + 0.08


func _check_player(r: float) -> void:
	var hurt := get_tree().get_first_node_in_group("player_hurt") as Area3D
	if hurt == null or not hurt.has_method("take_damage"):
		return
	var v: Vector3 = hurt.global_position - global_position
	# Trop haut (plateforme au-dessus) : l'onde passe dessous
	if absf(v.y) > 2.0:
		return
	v.y = 0.0
	var d: float = v.length()
	if absf(d - r) > thickness * 0.5 + 0.35:
		return
	# Esquive en cours : l'onde passe à travers, et ne retouchera pas
	var pl: Node = hurt.get("player")
	if pl != null and (bool(pl.get("is_invulnerable")) or bool(pl.get("is_dodging"))):
		_hit = true
		return
	_hit = true
	hurt.take_damage(damage, v.normalized() if d > 0.01 else Vector3.FORWARD)
