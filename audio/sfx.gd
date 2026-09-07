extends Node

## Gestionnaire de sons. Autoload : Projet → Réglages → Autoloads, nom "Sfx".
##
## Pourquoi un gestionnaire central plutôt qu'un AudioStreamPlayer3D par nœud :
## un ennemi qui meurt appelle queue_free(), ce qui couperait net son propre
## son de mort. Ici les lecteurs vivent dans l'autoload et survivent à
## l'émetteur.
##
## Deux réservoirs : 2D pour l'interface et les actions du joueur (toujours
## au même volume), 3D positionné pour tout ce qui se passe dans le monde.
##
## Usage :
##   Sfx.play("hit_light", position)     — son positionné
##   Sfx.play_ui("heal")                 — son non positionné

@export var pool_size: int = 12
@export var master_volume_db: float = 0.0

## Variation aléatoire de hauteur, pour que dix coups d'affilée ne soient pas
## dix fois exactement le même échantillon — c'est ce qui fatigue l'oreille.
@export var pitch_variation: float = 0.12

## Empêche deux sons identiques de se superposer dans la même frame : sans ça
## un coup qui touche trois ennemis joue trois fois le même impact, ce qui
## sature au lieu de renforcer.
@export var dedup_window: float = 0.04

var sounds: Dictionary = {}

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _last_played: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # le hit stop ne coupe pas le son

	for i in pool_size:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 30.0
		p3.max_distance = 0.0    # 0 = pas de limite
		add_child(p3)
		_pool_3d.append(p3)

		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_pool_2d.append(p2)

	_load_sounds()


## Les sons vivent dans res://audio/sfx/. Le nom du fichier (sans extension)
## devient sa clé : hit_light.wav → Sfx.play("hit_light").
func _load_sounds() -> void:
	var dir := DirAccess.open("res://audio/sfx")
	if dir == null:
		push_warning("Sfx : dossier res://audio/sfx introuvable")
		return

	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			# .import apparaît dans les exports : on garde le nom de base
			var clean := f.trim_suffix(".import")
			if clean.get_extension() in ["wav", "ogg", "mp3"]:
				var key := clean.get_basename()
				var s: AudioStream = load("res://audio/sfx/" + clean)
				if s != null:
					sounds[key] = s
		f = dir.get_next()
	dir.list_dir_end()
	print("Sfx : ", sounds.size(), " sons chargés → ", sounds.keys())


## Son positionné dans le monde.
func play(key: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _take(key)
	if stream == null:
		return

	var p := _free_3d()
	if p == null:
		return

	p.stream = stream
	p.global_position = pos
	p.volume_db = master_volume_db + volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()


## Son non positionné : interface, retours du joueur.
func play_ui(key: String, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _take(key)
	if stream == null:
		return

	var p := _free_2d()
	if p == null:
		return

	p.stream = stream
	p.volume_db = master_volume_db + volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()


## Récupère le flux et applique la dédup. Renvoie null s'il faut ignorer.
func _take(key: String) -> AudioStream:
	if not sounds.has(key):
		return null

	var now: float = Time.get_ticks_msec() / 1000.0
	var last: float = _last_played.get(key, -999.0)
	if now - last < dedup_window:
		return null
	_last_played[key] = now

	return sounds[key]


## Recycle le plus ancien si tout est occupé : mieux vaut couper un son en
## cours que d'en perdre un nouveau, qui correspond à l'action présente.
func _free_3d() -> AudioStreamPlayer3D:
	for p in _pool_3d:
		if not p.playing:
			return p
	return _pool_3d[0] if _pool_3d.size() > 0 else null


func _free_2d() -> AudioStreamPlayer:
	for p in _pool_2d:
		if not p.playing:
			return p
	return _pool_2d[0] if _pool_2d.size() > 0 else null
