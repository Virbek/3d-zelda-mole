class_name HitSparks
extends Node3D

## Gerbes d'étincelles à l'impact. Un petit réservoir d'émetteurs créés une
## fois pour toutes et rejoués à chaque coup : rien n'est instancié pendant
## le combat. Deux tailles : coup léger (combo, toupie) et coup lourd (poing
## chargé, finisher).
##
## Les particules suivent Engine.time_scale : pendant le hit stop, la gerbe
## reste figée à son premier instant, ce qui renforce l'impact.

@export var light_pool_size: int = 6
@export var heavy_pool_size: int = 3
@export var spark_color := Color(1.0, 0.88, 0.45)

var _light: Array[GPUParticles3D] = []
var _heavy: Array[GPUParticles3D] = []
var _light_i: int = 0
var _heavy_i: int = 0


func _ready() -> void:
	top_level = true
	for i in light_pool_size:
		_light.append(_build_emitter(10, 4.0, 7.5, 0.22, 0.8))
	for i in heavy_pool_size:
		_heavy.append(_build_emitter(22, 6.0, 11.0, 0.32, 1.4))


## pos : point d'impact. dir : direction du coup (du joueur vers l'ennemi).
func burst(pos: Vector3, dir: Vector3, heavy: bool = false) -> void:
	var e: GPUParticles3D
	if heavy:
		e = _heavy[_heavy_i]
		_heavy_i = (_heavy_i + 1) % _heavy.size()
	else:
		e = _light[_light_i]
		_light_i = (_light_i + 1) % _light.size()

	var d: Vector3 = dir
	d.y = 0.0
	if d.length_squared() < 0.0001:
		d = Vector3.FORWARD
	d = d.normalized()

	# L'émetteur projette le long de son -Z local : on l'oriente vers le coup
	e.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP), pos)
	e.restart()


func _build_emitter(amount: int, vel_min: float, vel_max: float, lifetime: float, size: float) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.25, -1.0)
	pm.spread = 55.0
	pm.initial_velocity_min = vel_min
	pm.initial_velocity_max = vel_max
	pm.gravity = Vector3(0.0, -14.0, 0.0)
	pm.damping_min = 4.0
	pm.damping_max = 8.0
	pm.scale_min = 0.6 * size
	pm.scale_max = 1.2 * size
	pm.particle_flag_align_y = true   # l'étincelle s'étire dans le sens de sa vitesse

	# Rétrécit jusqu'à disparaître : pas de transparence à trier
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = spark_color

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.22, 0.04)
	mesh.material = mat

	var e := GPUParticles3D.new()
	e.amount = amount
	e.lifetime = lifetime
	e.one_shot = true
	e.explosiveness = 1.0
	e.local_coords = false
	e.emitting = false
	e.process_material = pm
	e.draw_pass_1 = mesh
	e.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	add_child(e)
	return e
