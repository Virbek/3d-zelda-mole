extends Node

## Jetons d'attaque : au plus `max_concurrent` ennemis attaquent en même temps.
## Sans ça, trois chargeurs simultanés donnent une situation inesquivable.
##
## FILE D'ATTENTE : un ennemi prêt à frapper s'inscrit (enqueue / request).
## Les places libérées sont données dans l'ordre d'arrivée, et un ennemi qui
## vient d'attaquer repart en fin de file. Résultat : ils attaquent chacun
## leur tour, et ceux qui attendent tournent autour du joueur.
##
## Un ennemi qui cesse de se manifester (mort, étourdi, parti) sort tout seul
## de la file au bout de `stale_time` : pas besoin de le retirer à la main
## dans chaque état.

@export var max_concurrent: int = 2
@export var stale_time: float = 0.5   ## secondes sans signe de vie avant d'être retiré de la file

# Volontairement NON typés : un ennemi libéré sans release() (rechargement
# de scène, sortie de salle) devient une instance invalide, et un Array[Node]
# refuse alors de l'effacer. Le jeton restait bloqué pour toujours.
var _holders: Array = []
var _queue: Array = []
var _last_seen: Dictionary = {}       ## Node -> ms du dernier enqueue/request


## Inscrit l'ennemi dans la file (ou rafraîchit sa place). À appeler chaque
## frame tant qu'il attend son tour.
func enqueue(who: Node) -> void:
	_cleanup()
	_last_seen[who] = Time.get_ticks_msec()
	if who in _holders or who in _queue:
		return
	_queue.append(who)


## Demande le droit d'attaquer. Inscrit l'ennemi dans la file s'il n'y est
## pas ; renvoie true seulement quand c'est son tour.
func request(who: Node) -> bool:
	enqueue(who)
	if who in _holders:
		return true
	if not _is_turn(who):
		return false
	_queue.erase(who)
	_holders.append(who)
	return true


## Dit si request() réussirait, sans prendre le jeton. Permet à un ennemi
## d'approcher sans monopoliser une place tant qu'il n'est pas au contact.
func is_available(who: Node) -> bool:
	_cleanup()
	if who in _holders:
		return true
	if who in _queue:
		return _is_turn(who)
	# Pas inscrit : il ne passerait que si personne n'attend devant lui
	return _queue.size() < _free_slots()


## Fin d'attaque (ou interruption) : la place passe au suivant, et l'ennemi
## devra se réinscrire, donc en fin de file.
func release(who: Node) -> void:
	_holders.erase(who)
	_queue.erase(who)
	_last_seen.erase(who)


## Rang dans la file (0 = prochain), -1 si absent. Utile pour étaler les
## ennemis en attente autour du joueur.
func queue_index(who: Node) -> int:
	return _queue.find(who)


func _free_slots() -> int:
	return maxi(max_concurrent - _holders.size(), 0)


func _is_turn(who: Node) -> bool:
	var i: int = _queue.find(who)
	return i >= 0 and i < _free_slots()


func _cleanup() -> void:
	var now: int = Time.get_ticks_msec()
	var limit: int = int(stale_time * 1000.0)

	# Un ennemi mort ne doit pas garder le jeton. Retrait par index : erase()
	# compare les valeurs, ce qui est fragile avec une instance libérée.
	for i in range(_holders.size() - 1, -1, -1):
		if not is_instance_valid(_holders[i]):
			_holders.remove_at(i)

	# Un ennemi qui ne se manifeste plus libère sa place dans la file
	for i in range(_queue.size() - 1, -1, -1):
		var q: Variant = _queue[i]
		if not is_instance_valid(q) or now - int(_last_seen.get(q, 0)) > limit:
			_queue.remove_at(i)

	# Les clés d'instances libérées ne servent plus à rien
	for k in _last_seen.keys():
		if not is_instance_valid(k):
			_last_seen.erase(k)
