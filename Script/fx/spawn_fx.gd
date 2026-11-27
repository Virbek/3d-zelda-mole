extends RefCounted
class_name SpawnFx

## Effets d'apparition des ennemis, à la place de l'ancien marqueur violet.
## Chaque arrivée se lit dans le décor de la raffinerie ensablée :
##   - par le sol (mêlée, bousier, bombardier) : le sable tremble et se
##     soulève, puis éclate quand l'ennemi en sort ;
##   - par le haut (abeille) et du ciel (boss) : une ombre grandit au sol à
##     l'endroit où il va arriver.
## Tout est construit en quelques primitives, une fois par apparition, et se
## libère seul.

const SAND := Color("#c9a36b")
const SAND_DARK := Color("#9c7a48")
const SHADOW := Color(0.08, 0.05, 0.03)


## Annonce au sol : le sable frémit (bosses qui montent et retombent) sur
## duration secondes. Le joueur voit où quelque chose va sortir.
static func ground_rumble(parent: Node3D, pos: Vector3, duration: float, radius: float) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	# Tache de sable remué
	var patch := _disc(radius * 1.1, _mat(SAND_DARK, 0.0))
	root.add_child(patch)
	patch.position.y = 0.02
	var pm := patch.material_override as StandardMaterial3D
	var t := root.create_tween().set_parallel(true)
	t.tween_property(pm, "albedo_color:a", 0.85, duration * 0.5)
	# Petites mottes qui sautillent : de plus en plus fort
	for i in 7:
		var c := MeshInstance3D.new()
		c.mesh = ToonBuilder.box(Vector3.ONE * randf_range(0.08, 0.15))
		c.material_override = ToonBuilder.toon_material(SAND if i % 2 else SAND_DARK, 0.0)
		root.add_child(c)
		var a: float = TAU * float(i) / 7.0 + randf() * 0.5
		c.position = Vector3(cos(a), 0.04, sin(a)) * radius * randf_range(0.3, 0.9)
		var hops := c.create_tween().set_loops(int(ceil(duration / 0.2)))
		var h: float = randf_range(0.05, 0.12)
		hops.tween_property(c, "position:y", 0.04 + h, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		hops.tween_property(c, "position:y", 0.04, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_interval(duration * 0.5)
	t.chain().tween_property(pm, "albedo_color:a", 0.0, 0.3)
	t.chain().tween_callback(root.queue_free)


## Ombre qui grandit et fonce jusqu'à l'arrivée (abeille, boss).
static func falling_shadow(parent: Node3D, pos: Vector3, duration: float, radius: float) -> void:
	var s := _disc(radius, _mat(SHADOW, 0.0))
	parent.add_child(s)
	s.position = pos + Vector3.UP * 0.03
	s.scale = Vector3(0.2, 1.0, 0.2)
	var m := s.material_override as StandardMaterial3D
	var t := s.create_tween().set_parallel(true)
	t.tween_property(s, "scale", Vector3.ONE, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(m, "albedo_color:a", 0.6, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_property(m, "albedo_color:a", 0.0, 0.25)
	t.chain().tween_callback(s.queue_free)


## Gerbe de sable : des mottes jaillissent et retombent autour de pos.
static func sand_burst(parent: Node3D, pos: Vector3, radius: float, count: int = 12, height: float = 1.0) -> void:
	for i in count:
		var c := MeshInstance3D.new()
		c.mesh = ToonBuilder.box(Vector3.ONE * randf_range(0.1, 0.24))
		c.material_override = ToonBuilder.toon_material(SAND if i % 3 else SAND_DARK, 0.0)
		parent.add_child(c)
		c.position = pos + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3)) * radius
		var out := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * radius * randf_range(0.8, 1.8)
		var peak: Vector3 = c.position + out * 0.5 + Vector3.UP * height * randf_range(0.6, 1.2)
		var land: Vector3 = c.position + out
		land.y = pos.y + 0.05
		var t := c.create_tween()
		t.tween_property(c, "position", peak, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(c, "position", land, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(c, "scale", Vector3.ONE * 0.2, 0.3)
		t.tween_callback(c.queue_free)


## Anneau de poussière qui s'élargit au ras du sol (impact du boss).
static func dust_ring(parent: Node3D, pos: Vector3, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 1.0
	torus.rings = 32
	ring.mesh = torus
	var m := _mat(SAND, 0.85)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.position = pos + Vector3.UP * 0.1
	ring.scale = Vector3(0.5, 0.4, 0.5)
	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector3(radius, 0.15, radius), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(m, "albedo_color:a", 0.0, 0.45).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(ring.queue_free)


static func _disc(radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var d := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.01
	c.radial_segments = 24
	d.mesh = c
	d.material_override = mat
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return d


static func _mat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	return m
