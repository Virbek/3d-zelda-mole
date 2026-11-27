extends Node3D
class_name SandBall

## Boulet de sable compacté que le bousier façonne puis pousse en bélier.
##
## Il se casse dès qu'il existe, même tout petit en cours de façonnage :
## quand le joueur le frappe (le poing touche sa HurtBox, sur le même calque
## que celle des ennemis : le combat lui appelle take_hit), quand un dard du
## slam le traverse (groupe « breakable »), ou quand il percute le joueur
## pendant une charge (l'ennemi appelle shatter()). Dans les deux cas il émet `broken` vers le bousier, qui va
## fuir pour en refaire un.
##
## Construit par script. Origine = centre du boulet.

signal broken

const SAND := Color("#c9a36b")
const SAND_DARK := Color("#9c7a48")
const PLAYER_HURT_LAYER: int = 4     ## calque 3 : HurtBox du joueur
const HIT_LAYER: int = 2             ## calque 2 : là où les poings cherchent

@export var radius: float = 0.55
@export var chunk_count: int = 12
@export var chunk_lifetime: float = 0.6

var _visual: Node3D
var _hurt: Area3D
var _contact: Area3D
var _grow: float = 1.0
var _intact: bool = true


func _ready() -> void:
	add_to_group(&"breakable")
	_build()


# ---------------------------------------------------------------- PILOTAGE

## 0 = rien, 1 = boulet complet. Le boulet ne peut être frappé ou percuter
## qu'une fois complet.
func set_grow(k: float) -> void:
	_grow = clampf(k, 0.0, 1.0)
	_visual.scale = Vector3.ONE * maxf(_grow, 0.001)
	_visual.position.y = -radius * (1.0 - _grow)   # posé au sol pendant qu'il grossit
	visible = _grow > 0.0 and _intact
	_hurt.monitorable = _grow > 0.0 and _intact     # frappable dès qu'il existe
	_contact.monitoring = _grow >= 1.0 and _intact  # ne percute qu'une fois fini


## Fait tourner le boulet comme s'il roulait de `distance` mètres vers l'avant.
func roll(distance: float) -> void:
	_visual.rotate_x(-distance / radius)


## Centre visible du boulet : plus bas tant qu'il grossit (posé au sol).
func visual_center() -> Vector3:
	return _visual.global_position


## Rayon visible actuel.
func visual_radius() -> float:
	return radius * _grow


func is_intact() -> bool:
	return _intact and _grow >= 1.0


## Le boulet touche-t-il la HurtBox du joueur ? Renvoie l'Area3D touchée.
func player_contact() -> Area3D:
	if not is_intact():
		return null
	for a in _contact.get_overlapping_areas():
		if a.is_in_group("player_hurt"):
			return a
	return null


## Prêt pour un nouveau boulet (après la fuite).
## Le boulet existe-t-il à l'écran (même petit) ?
func is_present() -> bool:
	return _intact and _grow > 0.0


func reset() -> void:
	_intact = true
	set_grow(0.0)


## Appelé par les poings du joueur (même interface qu'un ennemi).
func take_hit(_direction: Vector3, _damage: int = 1, _breaks_stun: bool = false) -> void:
	shatter()


func shatter() -> void:
	if not _intact:
		return
	_intact = false
	_set_active(false)
	_burst()
	visible = false
	broken.emit()


# ---------------------------------------------------------------- INTERNE

func _set_active(on: bool) -> void:
	_hurt.monitorable = on
	_contact.monitoring = on


func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	var ball := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10   # facettes visibles : look low-poly
	s.rings = 6
	ball.mesh = s
	ball.material_override = ToonBuilder.toon_material(SAND, 0.012)
	_visual.add_child(ball)

	# Mottes et cailloux pris dans le sable : montrent qu'il roule
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 9:
		var clump := MeshInstance3D.new()
		clump.mesh = ToonBuilder.box(Vector3.ONE * rng.randf_range(0.1, 0.2))
		clump.material_override = ToonBuilder.toon_material(SAND_DARK, 0.0)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		clump.position = dir * radius * 0.95
		clump.rotation = Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
		_visual.add_child(clump)

	var shape := SphereShape3D.new()
	shape.radius = radius * 1.05

	_hurt = Area3D.new()
	_hurt.name = "HurtBox"
	_hurt.collision_layer = HIT_LAYER
	_hurt.collision_mask = 0
	_hurt.monitoring = false
	var hs := CollisionShape3D.new()
	hs.shape = shape
	_hurt.add_child(hs)
	add_child(_hurt)

	_contact = Area3D.new()
	_contact.name = "Contact"
	_contact.collision_layer = 0
	_contact.collision_mask = PLAYER_HURT_LAYER
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_contact.add_child(cs)
	add_child(_contact)


## Éclats de sable qui volent et retombent : quelques boîtes, une seule fois.
func _burst() -> void:
	Sfx.play("hit_heavy", global_position)
	var parent: Node = get_tree().current_scene
	if parent == null:
		return
	# Un petit boulet en cours de façonnage éclate en moins de morceaux, plus petits
	var k: float = maxf(_grow, 0.35)
	var origin: Vector3 = _visual.global_position
	for i in maxi(int(round(float(chunk_count) * k)), 4):
		var c := MeshInstance3D.new()
		c.mesh = ToonBuilder.box(Vector3.ONE * randf_range(0.12, 0.26) * k)
		c.material_override = ToonBuilder.toon_material(SAND if i % 3 else SAND_DARK, 0.0)
		parent.add_child(c)
		c.global_position = origin + Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.3), randf_range(-0.3, 0.3))
		var out := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * randf_range(0.8, 1.8)
		var peak: Vector3 = c.global_position + out * 0.5 + Vector3.UP * randf_range(0.5, 1.1)
		var land: Vector3 = c.global_position + out
		land.y = origin.y - radius * _grow + 0.05
		var t := c.create_tween()
		t.tween_property(c, "global_position", peak, chunk_lifetime * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(c, "global_position", land, chunk_lifetime * 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(c, "scale", Vector3.ONE * 0.2, chunk_lifetime * 0.6)
		t.tween_callback(c.queue_free)
