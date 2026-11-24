class_name HitReaction
extends Node3D

## Réaction physique d'un ennemi touché : il s'écrase puis bascule en arrière,
## à l'opposé du joueur, avant de revenir en place avec un léger rebond.
##
## Ce nœud est un pivot intercalé entre l'ennemi et son mesh (voir attach).
## Les scripts d'ennemis modifient déjà mesh.scale et mesh.rotation pour leurs
## télégraphes, leur étourdissement ou leur visée : en animant le pivot plutôt
## que le mesh, la réaction se superpose à ces poses sans jamais les écraser.

@export var duration: float = 0.28
@export var tilt_degrees: float = 18.0
@export var squash: float = 0.22

var _tween: Tween = null
var _axis := Vector3.RIGHT
var _strength: float = 1.0


## Glisse un pivot au-dessus de mesh et le renvoie. Le mesh garde sa
## transformation locale : au repos, le pivot est neutre et rien ne bouge.
static func attach(mesh: Node3D) -> HitReaction:
	var parent: Node = mesh.get_parent()
	var pivot := HitReaction.new()
	pivot.name = "HitReaction"
	parent.add_child(pivot)
	parent.move_child(pivot, mesh.get_index())
	mesh.reparent(pivot, false)
	return pivot


## direction : sens du coup, dans le repère du monde (du joueur vers l'ennemi).
## strength : 1 pour un coup normal, plus pour un coup lourd.
func play(direction: Vector3, strength: float = 1.0) -> void:
	var parent := get_parent() as Node3D
	var local_dir: Vector3 = direction
	if parent != null:
		local_dir = parent.global_basis.inverse() * direction
	local_dir.y = 0.0
	if local_dir.length_squared() < 0.0001:
		local_dir = Vector3.BACK
	# Tourner autour de UP × dir fait pencher le haut du corps vers dir
	_axis = Vector3.UP.cross(local_dir.normalized()).normalized()
	_strength = strength

	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_apply, 0.0, 1.0, duration)


func stop() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	transform = Transform3D.IDENTITY


func _apply(t: float) -> void:
	# Pic immédiat, retour avec un léger dépassement dans l'autre sens
	var e: float = (1.0 - t) * (1.0 - t) * cos(t * PI * 1.6)
	var tilt: float = deg_to_rad(tilt_degrees) * _strength * e
	var s: float = squash * _strength * e
	var b := Basis(_axis, tilt) * Basis.from_scale(Vector3(1.0 + s, 1.0 - s, 1.0 + s))
	transform = Transform3D(b, Vector3.ZERO)
