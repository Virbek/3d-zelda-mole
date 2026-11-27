extends Node

## Cinématique d'arrivée, au tout premier lancement : la caméra se retourne
## vers le mur du bas de la salle de départ. Trois coups sourds font trembler
## et fissurer le mur, au quatrième il vole en éclats vers l'intérieur et la
## taupe entre par la brèche, depuis son tunnel. La caméra revient alors
## doucement derrière elle et le joueur reprend la main.
##
## Créée par le Dungeon (une fois), qui lui passe la salle, le joueur et la
## caméra. Se libère seule à la fin. Le mur qui casse est un bouchon de
## blocs posé dans la brèche (voir DungeonRoom.breach_south) : il ne sert
## qu'à la cinématique, les blocs restent ensuite au sol comme gravats.

signal finished

const SAVE_PATH := "user://progress.cfg"
const SpawnFxLib := preload("res://Script/fx/spawn_fx.gd")

## Déjà jouée pendant cette partie (survit aux rechargements de scène).
static var played_this_session: bool = false

var hit_times: Array[float] = [0.9, 1.8, 2.55]   ## coups sourds avant la casse
var break_time: float = 3.25
var walk_in_depth: float = 3.0     ## la taupe avance jusque-là dans la salle
var walk_in_time: float = 1.5
var camera_distance: float = 11.0  ## recul de la caméra face au mur
var camera_tilt: float = 0.2       ## part de l'inclinaison du jeu gardée (0 = à l'horizontale)
var fade_in_time: float = 1.2      ## fondu depuis le noir au début
var cut_lead: float = 0.12   ## la caméra normale revient juste avant la casse

var _room: Node3D
var _player: CharacterBody3D
var _rig: Node3D
var _blocks: Array[MeshInstance3D] = []
var _cracks: Array[MeshInstance3D] = []
var _crack_mat: Material


## mode : 0 = première fois seulement, 1 = à chaque lancement, 2 = jamais.
static func should_play(mode: int) -> bool:
	if mode == 2 or played_this_session:
		return false
	if mode == 1:
		return true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK and bool(cfg.get_value("intro", "seen", false)):
		return false
	return true


static func _mark_seen() -> void:
	played_this_session = true
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # garde les autres valeurs s'il existe déjà
	cfg.set_value("intro", "seen", true)
	cfg.save(SAVE_PATH)


func play(room: Node3D, player: CharacterBody3D, camera_rig: Node3D) -> void:
	_room = room
	_player = player
	_rig = camera_rig
	_mark_seen()

	var bp: Vector3 = room.call("breach_point")
	var wall_h: float = float(room.get("wall_height"))
	var thick: float = float(room.get("wall_thickness")) * 0.5
	var width: float = DungeonRoom.BREACH_WIDTH

	_build_plug(bp, width, wall_h, thick, room.get("wall_color"))
	# Vu de face, le mur du bas doit être un vrai mur, pas le muret du jeu
	room.call("set_intro_set", true)
	_fade_from_black()

	# Caméra retournée face au mur, plus rasante
	var saved_rot: Vector3 = Vector3.ZERO
	var saved_dist: float = 8.0
	var cam: Camera3D = null
	if _rig != null:
		cam = _rig.get("cam") as Camera3D
		saved_rot = _rig.rotation
		saved_dist = cam.position.z if cam != null else saved_dist
		_rig.set("cinematic", true)
		_rig.global_position = room.to_global(bp + Vector3.UP * 1.8)
		_rig.rotation = Vector3(saved_rot.x * camera_tilt, saved_rot.y + PI, saved_rot.z)
		if cam != null:
			cam.position.z = camera_distance

	# La taupe attend derrière le mur (dans son tunnel, ou dans le noir de
	# la salle voisine). Sa physique est suspendue : elle traverse l'épaisseur
	# du mur, guidée par la cinématique ; le rig, lui, continue de marcher.
	_player.set("controls_enabled", false)
	_player.velocity = Vector3.ZERO
	# Derrière le mur, la taupe est dans l'emprise de la salle voisine : le
	# Dungeon ne doit pas croire qu'elle y est entrée (voile, ennemis...)
	_set_dungeon_busy(true)
	# Au lancement, la taupe tombe encore de sa hauteur de départ : on attend
	# qu'elle touche le sol pour connaître sa hauteur debout (elle est hors
	# champ, derrière la caméra retournée)
	for i in 40:
		if _player.is_on_floor():
			break
		await get_tree().physics_frame
	_player.set_physics_process(false)
	var behind: float = 2.2 if bool(room.get("breach_tunnel")) else 1.1
	var tunnel: Vector3 = room.to_global(bp + Vector3.BACK * behind)
	_player.global_position = Vector3(tunnel.x, _player.global_position.y, tunnel.z)
	_player.rotation.y = 0.0   # regarde vers -Z : vers la salle
	var player_rig: Node = _player.get("rig")
	if player_rig != null and player_rig.has_method("snap_to_player"):
		player_rig.call("snap_to_player")

	# Coups sourds : le mur tremble, se fissure et bombe un peu plus à chaque fois
	var t0: float = 0.0
	for i in hit_times.size():
		await _wait(hit_times[i] - t0)
		t0 = hit_times[i]
		_thud(i, bp, width, wall_h)

	# Juste avant le coup qui brise le mur : coupe franche vers la caméra
	# normale du donjon (elle suit déjà la taupe, bornée à la salle)
	await _wait(maxf(break_time - t0 - cut_lead, 0.0))
	if _rig != null:
		_rig.rotation = saved_rot
		if cam != null:
			cam.position.z = saved_dist
		_rig.set("cinematic", false)
		room.call("set_intro_set", false)
		if _rig.has_method("set_bounds") and room.has_method("get_bounds"):
			_rig.call("set_bounds", room.call("get_bounds"), true)

	# Le mur cède
	await _wait(cut_lead)
	_break(bp, width)

	# La taupe entre par la brèche
	await _wait(0.25)
	var target: Vector3 = room.to_global(bp + Vector3.FORWARD * walk_in_depth)
	target.y = _player.global_position.y

	var walk := create_tween()
	walk.tween_property(_player, "global_position", target, walk_in_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await walk.finished

	_player.velocity = Vector3.ZERO
	_player.set_physics_process(true)
	_set_dungeon_busy(false)
	if _player.has_method("stop_auto_walk"):
		_player.call("stop_auto_walk")
	else:
		_player.set("controls_enabled", true)

	finished.emit()
	queue_free()


## Écran noir qui s'éclaircit : le premier coup sourd s'entend encore dans
## le noir.
func _fade_from_black() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90   # au-dessus du HUD
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	var t := create_tween()
	t.tween_interval(0.3)
	t.tween_property(black, "color:a", 0.0, fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(layer.queue_free)


## Suspend le suivi de salle du Dungeon (même verrou qu'un passage de porte).
func _set_dungeon_busy(on: bool) -> void:
	var d: Node = get_parent()
	if d != null and "_transitioning" in d:
		d.set("_transitioning", on)


func _wait(seconds: float) -> void:
	if seconds > 0.0:
		await get_tree().create_timer(seconds, false).timeout


## Le bouchon : des blocs de roche qui comblent la brèche sur toute la hauteur.
func _build_plug(bp: Vector3, width: float, height: float, thick: float, color: Color) -> void:
	var cols: int = 6
	var rows: int = 8
	var bw: float = width / float(cols)
	var bh: float = height / float(rows)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_crack_mat = ToonBuilder.toon_material(Color("#1a100a"), 0.0)
	for r in rows:
		for c in cols:
			var b := MeshInstance3D.new()
			b.mesh = ToonBuilder.box(Vector3(bw * 0.98, bh * 0.98, thick))
			b.material_override = ToonBuilder.toon_material(color.darkened(rng.randf_range(-0.05, 0.12)), 0.008)
			b.position = bp + Vector3(-width * 0.5 + bw * (float(c) + 0.5), bh * (float(r) + 0.5), 0.0)
			_room.call("add_decor", b)
			b.set_meta("home", b.position)
			_blocks.append(b)


## Un coup sourd : son, secousse, poussière, fissures, blocs qui bombent.
func _thud(index: int, bp: Vector3, width: float, height: float) -> void:
	var k: float = float(index + 1) / float(hit_times.size())
	var world: Vector3 = _room.to_global(bp)
	Sfx.play("boss_land", world, -2.0 + 3.0 * k)
	Sfx.play("hit_heavy", world, -4.0 + 3.0 * k)
	if _rig != null and _rig.has_method("shake"):
		_rig.call("shake", 0.3 + 0.35 * k)
	SpawnFxLib.sand_burst(_room, bp + Vector3.FORWARD * 0.4, 0.6 + 0.6 * k, 5 + index * 3, 0.6)

	# Fissures sur la face intérieure du mur
	for i in 3 + index * 2:
		var crack := MeshInstance3D.new()
		crack.mesh = ToonBuilder.box(Vector3(randf_range(0.5, 1.2), 0.05, 0.02))
		crack.material_override = _crack_mat
		crack.position = bp + Vector3(randf_range(-width * 0.4, width * 0.4), randf_range(0.4, height * 0.8), -float(_room.get("wall_thickness")) * 0.25 - 0.02)
		crack.rotation.z = randf_range(-1.2, 1.2)
		_room.call("add_decor", crack)
		_cracks.append(crack)

	# Les blocs sursautent et restent un peu plus bombés vers la salle
	for b in _blocks:
		var home: Vector3 = b.get_meta("home")
		var bulge: float = 0.06 * k * (1.0 - absf(home.x - bp.x) / (width * 0.6))
		var rest: Vector3 = home + Vector3.FORWARD * maxf(bulge, 0.0)
		var jolt: Vector3 = rest + Vector3(randf_range(-0.03, 0.03), randf_range(-0.02, 0.03), -0.08 * k)
		var tw := b.create_tween()
		tw.tween_property(b, "position", jolt, 0.05)
		tw.tween_property(b, "position", rest, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)



## Le mur vole en éclats vers l'intérieur ; les blocs retombent en gravats.
func _break(bp: Vector3, width: float) -> void:
	var world: Vector3 = _room.to_global(bp)
	Sfx.play("explosion", world, 2.0)
	Sfx.play("boss_land", world, 4.0)
	if _rig != null and _rig.has_method("shake"):
		_rig.call("shake", 1.1)
	for c in _cracks:
		if is_instance_valid(c):
			c.queue_free()
	_cracks.clear()
	SpawnFxLib.sand_burst(_room, bp + Vector3.FORWARD * 0.6, 2.0, 20, 1.6)
	SpawnFxLib.dust_ring(_room, bp + Vector3.FORWARD * 0.8, 4.5)

	for b in _blocks:
		var from: Vector3 = b.position
		# Plus le bloc est haut, plus il part loin ; le centre part tout droit
		var spread: float = (from.x - bp.x) / (width * 0.5)
		var land := Vector3(
			from.x + spread * randf_range(0.5, 1.8) + randf_range(-0.4, 0.4),
			0.12,
			bp.z - randf_range(1.0, 2.2) - from.y * randf_range(0.25, 0.55))
		var peak: Vector3 = from.lerp(land, 0.45) + Vector3.UP * randf_range(0.4, 1.2)
		var dur: float = randf_range(0.45, 0.7)
		var tw := b.create_tween().set_parallel(true)
		tw.tween_property(b, "position", peak, dur * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(b, "position", land, dur * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(b, "rotation", Vector3(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5), randf_range(-2.5, 2.5)), dur)
		tw.parallel().tween_property(b, "scale", Vector3.ONE * randf_range(0.55, 0.85), dur)
