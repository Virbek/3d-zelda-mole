extends Control

## Barre de vie du boss, en bas de l'écran.
##
## Deux couches de remplissage : la barre rouge suit la vie instantanément,
## la barre blanche derrière rattrape avec un retard. Cet écart rend visible
## la quantité de dégâts d'un seul coup — sans lui, une barre qui descend
## lentement ne dit rien sur la force de ce qui vient de se passer.
##
## Les marques de tiers sont dessinées par-dessus : le joueur voit ainsi
## à l'avance quand le boss va passer au palier suivant.

@export var boss_group: String = "boss"
@export var bar_height: float = 26.0
@export var bar_margin: float = 42.0      ## distance au bas de l'écran
@export var side_margin: float = 0.16     ## fraction de largeur laissée de chaque côté

@export_group("Couleurs")
@export var back_color := Color(0.08, 0.06, 0.07, 0.85)
@export var chip_color := Color(0.95, 0.9, 0.85, 0.9)   ## barre retardée
@export var fill_color := Color(0.85, 0.15, 0.15)
@export var border_color := Color(0.9, 0.85, 0.8, 0.35)
@export var tick_color := Color(0.05, 0.04, 0.05, 0.75)

@export_group("Animation")
@export var chip_delay: float = 0.35      ## avant que la barre blanche parte
@export var chip_speed: float = 2.2
@export var appear_time: float = 0.5
@export var shake_on_hit: float = 6.0     ## secousse de la barre à l'impact

var _boss: Node = null
var _ratio: float = 1.0
var _chip: float = 1.0
var _chip_t: float = 0.0
var _shake: float = 0.0
var _visible_k: float = 0.0   ## 0 = cachée, 1 = affichée


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_find_boss()


func _process(delta: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		_find_boss()

	var want: float = 1.0 if (_boss != null and is_instance_valid(_boss)) else 0.0
	_visible_k = move_toward(_visible_k, want, delta / maxf(appear_time, 0.01))

	# La barre blanche attend, puis rattrape : c'est ce délai qui donne
	# du poids aux gros coups.
	if _chip > _ratio:
		_chip_t += delta
		if _chip_t >= chip_delay:
			_chip = move_toward(_chip, _ratio, chip_speed * delta)
	else:
		_chip = _ratio

	if _shake > 0.0:
		_shake = maxf(_shake - delta * 24.0, 0.0)

	if _visible_k > 0.0 or want > 0.0:
		queue_redraw()


func _find_boss() -> void:
	for n in get_tree().get_nodes_in_group(boss_group):
		if not is_instance_valid(n):
			continue
		_boss = n
		_ratio = 1.0
		_chip = 1.0
		if n.has_signal("health_changed") and not n.health_changed.is_connected(_on_health):
			n.health_changed.connect(_on_health)
		return


func _on_health(current: int, maximum: int) -> void:
	_ratio = float(current) / float(maxi(maximum, 1))
	_chip_t = 0.0
	_shake = 1.0


func _draw() -> void:
	if _visible_k <= 0.01:
		return

	var vp: Vector2 = get_viewport_rect().size
	var w: float = vp.x * (1.0 - side_margin * 2.0)
	var x: float = vp.x * side_margin

	# Elle monte depuis le bas de l'écran à l'apparition
	var slide: float = (1.0 - _visible_k) * (bar_height + bar_margin)
	var y: float = vp.y - bar_margin - bar_height + slide

	if _shake > 0.0:
		x += randf_range(-_shake, _shake) * shake_on_hit
		y += randf_range(-_shake, _shake) * shake_on_hit * 0.5

	var a: float = _visible_k

	# Fond
	draw_rect(Rect2(x - 3.0, y - 3.0, w + 6.0, bar_height + 6.0),
		Color(back_color, back_color.a * a))

	# Barre retardée, puis barre de vie par-dessus
	if _chip > 0.0:
		draw_rect(Rect2(x, y, w * _chip, bar_height),
			Color(chip_color, chip_color.a * a))
	if _ratio > 0.0:
		draw_rect(Rect2(x, y, w * _ratio, bar_height),
			Color(fill_color, fill_color.a * a))

	# Marques de tiers : le joueur anticipe le changement de phase
	for i in 2:
		var tx: float = x + w * (float(i + 1) / 3.0)
		draw_line(Vector2(tx, y), Vector2(tx, y + bar_height),
			Color(tick_color, tick_color.a * a), 2.0)

	# Contour
	draw_rect(Rect2(x - 3.0, y - 3.0, w + 6.0, bar_height + 6.0),
		Color(border_color, border_color.a * a), false, 2.0)