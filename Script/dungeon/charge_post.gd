@tool
extends StaticBody3D
class_name ChargePost

## Checkpoint : vieille borne de recharge de la raffinerie, posée dans une
## salle avec l'outil « S » de l'éditeur de donjon.
##
## Éteinte, son voyant est sombre et ses bandes de danger jaunes. Quand la
## taupe passe à côté, une décharge cyan relie la borne au gantelet, le
## voyant s'allume et un halo cyan reste au sol : c'est le point de
## réapparition. Une seule borne est active à la fois (la dernière touchée).
##
## Construite par script, comme le coffre. Origine au sol.

const CYAN := Color(0.25, 0.84, 0.88)
const DARK_LAMP := Color(0.29, 0.23, 0.19)

@export var trigger_radius: float = 1.8       ## distance qui active la borne
@export var respawn_offset := Vector3(0.0, 0.0, 1.3)   ## où réapparaît la taupe (devant la borne, côté caméra)
@export var arc_time: float = 0.45             ## durée de la décharge vers le gantelet

var _lamp_mat: StandardMaterial3D
var _stripe_mats: Array[ShaderMaterial] = []
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _light: OmniLight3D
var _arc: MeshInstance3D
var _arc_mesh: ImmediateMesh
var _arc_t: float = -1.0
var _arc_seed: int = 0
var _active: bool = false
var _player: Node3D = null


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group(&"charge_post")
	# Après une mort, la borne qui sert de point de réapparition est déjà allumée
	_set_active(_is_current(), false)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _arc_t >= 0.0:
		_arc_t += delta
		_draw_arc()
		if _arc_t >= arc_time:
			_arc_t = -1.0
			_arc_mesh.clear_surfaces()

	if _active:
		# Le voyant respire doucement
		var k: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004)
		_light.light_energy = 1.2 * k
		return

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var d := Vector2(_player.global_position.x - global_position.x, _player.global_position.z - global_position.z)
	if d.length() <= trigger_radius:
		_activate()


func respawn_point() -> Vector3:
	# +1 m : le pivot du joueur est au centre de sa capsule, pas à ses pieds
	# (comme la réapparition par défaut du donjon)
	return global_position + global_basis * respawn_offset + Vector3.UP * 1.0


func _is_current() -> bool:
	if not Checkpoints.has_checkpoint:
		return false
	return Checkpoints.position.distance_to(respawn_point()) < 0.05


func _activate() -> void:
	Checkpoints.set_checkpoint(respawn_point())
	# Les autres bornes s'éteignent : un seul point de réapparition à la fois
	for n in get_tree().get_nodes_in_group(&"charge_post"):
		if n != self and n.has_method("_set_active"):
			n._set_active(false, false)
	_set_active(true, true)
	Sfx.play("checkpoint" if Sfx.sounds.has("checkpoint") else "door_unlock", global_position, 2.0)
	_arc_t = 0.0
	_arc_seed = randi()


func _set_active(on: bool, animate: bool) -> void:
	_active = on
	_lamp_mat.albedo_color = CYAN if on else DARK_LAMP
	_light.visible = on
	_halo.visible = on
	for m in _stripe_mats:
		m.set_shader_parameter("albedo_color", CYAN if on else ToonBuilder.HAZARD)
	if on and animate:
		_halo.scale = Vector3(0.2, 1.0, 0.2)
		var t := create_tween()
		t.tween_property(_halo, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- DÉCHARGE

## Éclair en zigzag entre le voyant et le gantelet le plus proche, redessiné
## à chaque image avec un tracé différent : il crépite.
func _draw_arc() -> void:
	_arc_mesh.clear_surfaces()
	var target: Vector3 = _gauntlet_position()
	var from: Vector3 = _arc.to_local(global_position + Vector3.UP * 1.55)
	var to: Vector3 = _arc.to_local(target)
	var rng := RandomNumberGenerator.new()
	rng.seed = _arc_seed + int(_arc_t * 40.0)
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segs: int = 8
	for i in segs + 1:
		var k: float = float(i) / float(segs)
		var p: Vector3 = from.lerp(to, k)
		if i > 0 and i < segs:
			p += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.18
		_arc_mesh.surface_add_vertex(p)
	_arc_mesh.surface_end()


func _gauntlet_position() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		return global_position + Vector3.UP
	var rig: Node = _player.get("rig")
	if rig != null:
		var best: Node3D = null
		for n: String in ["HandL", "HandR"]:
			var h := rig.get_node_or_null(n) as Node3D
			if h != null and (best == null or h.global_position.distance_to(global_position) < best.global_position.distance_to(global_position)):
				best = h
		if best != null:
			return best.global_position
	return _player.global_position + Vector3.UP


# ---------------------------------------------------------------- CONSTRUCTION

func _build() -> void:
	var B := ToonBuilder

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 1.7, 0.7)
	col.shape = shape
	col.position.y = 0.85
	add_child(col)

	# Socle, fût rouillé, chapeau
	_part(B.box(Vector3(0.9, 0.12, 0.9)), Vector3(0.0, 0.06, 0.0), B.RUST_DARK)
	_part(B.box(Vector3(0.62, 1.3, 0.62)), Vector3(0.0, 0.77, 0.0), B.RUST)
	_part(B.box(Vector3(0.78, 0.16, 0.78)), Vector3(0.0, 1.5, 0.0), B.RUST_DARK)
	# Bandes de danger en bas du fût (deviennent cyan une fois active)
	for y: float in [0.24, 0.36]:
		var stripe := _part(B.box(Vector3(0.64, 0.06, 0.64)), Vector3(0.0, y, 0.0), B.HAZARD)
		if stripe.material_override is ShaderMaterial:
			_stripe_mats.append(stripe.material_override as ShaderMaterial)
	# Cadran / hublot côté caméra (+Z)
	_part(B.box(Vector3(0.42, 0.34, 0.05)), Vector3(0.0, 1.05, 0.32), B.STEEL_DARK)
	# Câble qui sort du fût et rentre dans le sol
	var cable := _part(B.cylinder(0.04, 0.55), Vector3(0.38, 0.4, 0.0), B.STEEL_DARK)
	cable.rotation.z = deg_to_rad(40.0)

	# Voyant : non éclairé, sombre éteint, cyan allumé
	_lamp_mat = B.glow_material(DARK_LAMP)
	var lamp := MeshInstance3D.new()
	lamp.mesh = B.box(Vector3(0.2, 0.18, 0.2))
	lamp.position = Vector3(0.0, 1.67, 0.0)
	lamp.material_override = _lamp_mat
	add_child(lamp)
	var face := MeshInstance3D.new()
	face.mesh = B.box(Vector3(0.18, 0.14, 0.03))
	face.position = Vector3(0.0, 1.05, 0.35)
	face.material_override = _lamp_mat
	add_child(face)

	_light = OmniLight3D.new()
	_light.light_color = CYAN
	_light.light_energy = 1.2
	_light.omni_range = 3.5
	_light.position = Vector3(0.0, 1.8, 0.0)
	add_child(_light)

	# Halo au sol : disque cyan translucide, lisible en vue de dessus
	_halo = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.4
	disc.bottom_radius = 1.4
	disc.height = 0.02
	disc.radial_segments = 24
	_halo.mesh = disc
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.albedo_color = Color(CYAN, 0.22)
	_halo.material_override = _halo_mat
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position.y = 0.03
	add_child(_halo)

	# Décharge : ligne recalculée à chaque image pendant l'activation
	_arc = MeshInstance3D.new()
	_arc_mesh = ImmediateMesh.new()
	_arc.mesh = _arc_mesh
	var arc_mat := StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.albedo_color = CYAN.lightened(0.4)
	_arc.material_override = arc_mat
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc)

	_set_active(false, false)


func _part(mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.material_override = ToonBuilder.toon_material(color, 0.012)
	add_child(m)
	return m
