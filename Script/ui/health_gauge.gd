class_name HealthGauge
extends Control

## Barre de vie « conduite + manomètre » (DA rouille et sable).
## Le tuyau riveté est découpé en sections (1 par PV), le cadran à droite
## affiche la récupération par coups portés : l'aiguille monte à chaque coup
## (cyan) et clignote orange quand la progression retombe.
## Le HUD parent pousse l'état via set_health() / set_recover() : pas de
## référence au joueur ici.

@export_group("Dimensions")
@export var pipe_length: float = 250.0
@export var pipe_height: float = 22.0
@export var gauge_radius: float = 30.0
@export var segment_gap: float = 4.0
@export var outline_width: float = 3.0

@export_group("Couleurs")
@export var rust_color := Color(0.54, 0.29, 0.15)
@export var rust_dark_color := Color(0.35, 0.18, 0.09)
@export var ink_color := Color(0.05, 0.03, 0.02)
@export var sand_color := Color(0.85, 0.72, 0.48)
@export var health_color := Color(0.78, 0.21, 0.17)
@export var health_light_color := Color(0.88, 0.33, 0.25)
@export var empty_color := Color(0.12, 0.08, 0.05, 0.85)
@export var recover_color := Color(0.25, 0.84, 0.88)   ## cyan : machine active
@export var drain_color := Color(0.94, 0.54, 0.14)     ## orange : ça retombe

@export_group("Animation")
@export var needle_speed: float = 14.0        ## lissage de l'aiguille
@export var hit_kick_deg: float = 10.0        ## dépassement de l'aiguille à chaque coup
@export var drain_hold_time: float = 0.15     ## durée sans baisse avant de quitter l'état « retombe »
@export var flash_duration: float = 0.35

const NEEDLE_MIN_DEG: float = -120.0
const NEEDLE_MAX_DEG: float = 120.0

var _health: int = 0
var _max_health: int = 1
var _progress: float = 0.0
var _required: int = 1

var _needle_deg: float = NEEDLE_MIN_DEG
var _kick: float = 0.0
var _draining_t: float = 0.0
var _flash_t: float = 0.0
var _flash_index: int = -1
var _shake: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_min_size()


func _update_min_size() -> void:
	var w: float = pipe_length + 12.0 + gauge_radius * 2.0 + outline_width * 4.0
	var h: float = maxf(pipe_height, gauge_radius * 2.0) + outline_width * 4.0
	custom_minimum_size = Vector2(w, h)
	size = custom_minimum_size


func set_health(current: int, maximum: int) -> void:
	if current > _health and _max_health == maximum and current > 0:
		_flash_index = current - 1
		_flash_t = flash_duration
	elif current < _health:
		_shake = 1.0
	_health = current
	_max_health = maxi(maximum, 1)
	queue_redraw()


func set_recover(progress: float, required: int) -> void:
	if progress > _progress + 0.001:
		_kick = hit_kick_deg
		_draining_t = 0.0
	elif progress < _progress - 0.0001 and progress > 0.0:
		_draining_t = drain_hold_time
	elif progress <= 0.0:
		_draining_t = 0.0
	_progress = progress
	_required = maxi(required, 1)


func _process(delta: float) -> void:
	var full: bool = _health >= _max_health
	var ratio: float = 0.0 if full else clampf(_progress / float(_required), 0.0, 1.0)
	var target: float = lerpf(NEEDLE_MIN_DEG, NEEDLE_MAX_DEG, ratio) + _kick
	_needle_deg = lerpf(_needle_deg, target, 1.0 - exp(-needle_speed * delta))
	_kick = move_toward(_kick, 0.0, hit_kick_deg * 6.0 * delta)
	_draining_t = maxf(_draining_t - delta, 0.0)
	_flash_t = maxf(_flash_t - delta, 0.0)
	_shake = maxf(_shake - delta * 4.0, 0.0)
	queue_redraw()


func _is_draining() -> bool:
	return _draining_t > 0.0 and _progress > 0.0


func _draw() -> void:
	var shake_off := Vector2.ZERO
	if _shake > 0.0:
		shake_off = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 3.0 * _shake

	var ow: float = outline_width
	var center_y: float = ow * 2.0 + maxf(pipe_height, gauge_radius * 2.0) * 0.5
	var pipe_rect := Rect2(Vector2(ow * 2.0, center_y - pipe_height * 0.5) + shake_off, Vector2(pipe_length, pipe_height))
	_draw_pipe(pipe_rect)

	# Raccord entre le tuyau et le cadran
	var gauge_center := Vector2(pipe_rect.end.x + 12.0 + gauge_radius, center_y) + shake_off
	var joint := Rect2(Vector2(pipe_rect.end.x + ow, center_y - 7.0) + shake_off, Vector2(12.0 + 2.0, 14.0))
	draw_rect(joint, rust_color)
	draw_rect(joint, ink_color, false, 2.0)

	_draw_gauge(gauge_center)


func _draw_pipe(r: Rect2) -> void:
	var ow: float = outline_width
	# Contour rouille extérieur + trait noir
	draw_rect(r.grow(ow * 2.0), rust_color)
	draw_rect(r.grow(ow), ink_color)
	draw_rect(r, empty_color)

	var n: int = _max_health
	var seg_w: float = (r.size.x - segment_gap * float(n - 1)) / float(n)
	for i in n:
		var sr := Rect2(Vector2(r.position.x + float(i) * (seg_w + segment_gap), r.position.y), Vector2(seg_w, r.size.y))
		if i < _health:
			var col: Color = health_color
			if i == _flash_index and _flash_t > 0.0:
				col = health_color.lerp(Color.WHITE, _flash_t / flash_duration)
			draw_rect(sr, col)
			draw_rect(Rect2(sr.position, Vector2(sr.size.x, 5.0)), health_light_color)
		if i < n - 1:
			# Bride rivetée entre deux sections
			var flange := Rect2(Vector2(sr.end.x, r.position.y - ow * 2.0), Vector2(segment_gap, r.size.y + ow * 4.0))
			draw_rect(flange, rust_color)
			draw_circle(Vector2(flange.get_center().x, flange.position.y + 2.5), 1.5, ink_color)
			draw_circle(Vector2(flange.get_center().x, flange.end.y - 2.5), 1.5, ink_color)


func _draw_gauge(c: Vector2) -> void:
	var r: float = gauge_radius
	var ow: float = outline_width
	draw_circle(c, r + ow * 2.0, rust_color)
	draw_circle(c, r + ow, ink_color)
	draw_circle(c, r, sand_color)

	# Zones : orange au départ (retombe), cyan à l'arrivée (PV regagné)
	var arc_r: float = r - 6.0
	var a0: float = _gauge_angle(NEEDLE_MIN_DEG)
	var a1: float = _gauge_angle(NEEDLE_MIN_DEG + 50.0)
	var a2: float = _gauge_angle(NEEDLE_MAX_DEG - 50.0)
	var a3: float = _gauge_angle(NEEDLE_MAX_DEG)
	draw_arc(c, arc_r, a0, a1, 16, drain_color, 5.0)
	draw_arc(c, arc_r, a2, a3, 16, recover_color, 5.0)

	# Graduations : une par coup requis
	for k in _required + 1:
		var t: float = float(k) / float(_required)
		var a: float = _gauge_angle(lerpf(NEEDLE_MIN_DEG, NEEDLE_MAX_DEG, t))
		var dir := Vector2(cos(a), sin(a))
		var filled: bool = _health < _max_health and float(k) <= _progress and k > 0
		var tick_col: Color = recover_color if filled else ink_color
		draw_line(c + dir * (r - 11.0), c + dir * (r - 2.0), tick_col, 2.0 if not filled else 3.0)

	# Aiguille
	var needle_col: Color = ink_color.lerp(rust_dark_color, 0.5)
	if _health < _max_health:
		needle_col = recover_color
		if _is_draining():
			var blink: bool = int(Time.get_ticks_msec() / 180.0) % 2 == 0
			needle_col = drain_color if blink else drain_color.darkened(0.35)
	var na: float = _gauge_angle(_needle_deg)
	var tip: Vector2 = c + Vector2(cos(na), sin(na)) * (r - 5.0)
	draw_line(c, tip, ink_color, 5.0)
	draw_line(c, tip, needle_col, 3.0)
	draw_circle(c, 4.5, ink_color)
	draw_circle(c, 2.0, rust_color)


## 0° = vers le haut, positif = sens horaire (repère écran, y vers le bas).
func _gauge_angle(deg: float) -> float:
	return -PI * 0.5 + deg_to_rad(deg)
