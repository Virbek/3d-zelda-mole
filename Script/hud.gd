extends CanvasLayer

@export var player_path: NodePath
@export var pulse_intensity: float = 0.75
@export var pulse_decay: float = 1.8
@export var low_health_threshold: float = 0.34

@export_group("Barres de vie")
@export var bar_width: float = 14.0
@export var bar_height: float = 46.0
@export var bar_gap: float = 6.0
@export var bar_color := Color(0.85, 0.2, 0.2)
@export var recover_color := Color(0.9, 0.65, 0.2)   ## pendant la récupération, avant de compter comme une vie
@export var empty_color := Color(0.15, 0.15, 0.15, 0.6)
@export var outline_color := Color(0.0, 0.0, 0.0, 1.0)
@export var outline_width: float = 2.0

@onready var player: CharacterBody3D = get_node(player_path)
@onready var vignette: ColorRect = $Vignette

var _mat: ShaderMaterial
var _pulse: float = 0.0
var _ratio: float = 1.0

var _fills: Array[ColorRect] = []
var _styles: Array[StyleBoxFlat] = []


func _ready() -> void:
	_mat = vignette.material as ShaderMaterial
	_build_bars()

	player.health_changed.connect(_on_health_changed)
	player.recover_changed.connect(_on_recover_changed)

	_ratio = float(player.health) / float(player.max_health)
	_refresh_bars(player.health, 0.0, player.recover_hits_required)


## Une barre par pv max, construite par script — pas de .tscn à maintenir.
func _build_bars() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(bar_gap))
	row.position = Vector2(24, 24)
	add_child(row)

	for i in player.max_health:
		var style := StyleBoxFlat.new()
		style.bg_color = empty_color
		style.set_border_width_all(0)
		style.border_color = outline_color

		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(bar_width, bar_height)
		panel.add_theme_stylebox_override("panel", style)
		row.add_child(panel)

		var fill := ColorRect.new()
		fill.color = bar_color
		fill.size = Vector2(bar_width, bar_height)
		fill.pivot_offset = Vector2(0.0, bar_height)  # ancré en bas : le remplissage monte
		fill.scale.y = 0.0
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(fill)

		_fills.append(fill)
		_styles.append(style)


## i < health           : vie acquise, pleine, contour noir
## i == health           : emplacement en cours de récupération, sans contour
## i > health             : pas encore perdue/récupérée, vide
func _refresh_bars(health: int, recover_progress: float, recover_required: int) -> void:
	for i in _fills.size():
		var fill := _fills[i]
		var style := _styles[i]

		if i < health:
			fill.scale.y = 1.0
			fill.color = bar_color
			style.set_border_width_all(outline_width)
		elif i == health and recover_required > 0:
			fill.scale.y = clampf(recover_progress / float(recover_required), 0.0, 1.0)
			fill.color = recover_color
			style.set_border_width_all(0)
		else:
			fill.scale.y = 0.0
			style.set_border_width_all(0)


func _on_health_changed(current: int, maximum: int) -> void:
	var new_ratio: float = float(current) / float(maximum)
	if new_ratio < _ratio:
		_pulse = pulse_intensity     # flash rouge seulement si on perd des PV
	_ratio = new_ratio
	_refresh_bars(current, 0.0, player.recover_hits_required)


func _on_recover_changed(progress: float, required: int) -> void:
	_refresh_bars(player.health, progress, required)


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - pulse_decay * delta, 0.0)

	# Vignette permanente quand la vie est basse, par-dessus le flash
	var low: float = 0.0
	if _ratio <= low_health_threshold and _ratio > 0.0:
		low = (1.0 - _ratio / low_health_threshold) * 0.45
		low *= 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.004)   # pulsation lente

	_mat.set_shader_parameter("intensity", maxf(_pulse, low))