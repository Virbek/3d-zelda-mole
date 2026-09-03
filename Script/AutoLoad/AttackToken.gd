extends Node

## Un seul ennemi peut attaquer à la fois. Les autres attendent leur tour.
## Sans ça, trois chargeurs simultanés donnent une situation inesquivable.

@export var max_concurrent: int = 1

var _holders: Array = []


## Demande le droit d'attaquer. Renvoie false s'il faut attendre.
func request(who: Node) -> bool:
	_cleanup()
	if who in _holders:
		return true
	if _holders.size() >= max_concurrent:
		return false
	_holders.append(who)
	return true


func release(who: Node) -> void:
	_holders.erase(who)


func _cleanup() -> void:
	# Un ennemi mort ne doit pas garder le jeton
	for h in _holders.duplicate():
		if not is_instance_valid(h):
			_holders.erase(h)