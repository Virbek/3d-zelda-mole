extends CanvasLayer

@export var player_path: NodePath
@export var pulse_intensity: float = 0.75
@export var pulse_decay: float = 1.8
@export var low_health_threshold: float = 0.34

## Optionnel : un Dungeon dont on affiche le nombre de clés.
@export var dungeon_path: NodePath

@export_group("Barre de vie")
@export var gauge_position := Vector2(24, 24)

@onready var player: CharacterBody3D = get_node(player_path)
@onready var vignette: ColorRect = $Vignette

var _mat: ShaderMaterial
var _pulse: float = 0.0
var _ratio: float = 1.0

var _gauge: HealthGauge


func _ready() -> void:
	_mat = vignette.material as ShaderMaterial
	_gauge = HealthGauge.new()
	_gauge.name = "HealthGauge"
	_gauge.position = gauge_position
	add_child(_gauge)

	var threats := OffscreenThreats.new()
	threats.name = "OffscreenThreats"
	add_child(threats)

	player.health_changed.connect(_on_health_changed)
	player.recover_changed.connect(_on_recover_changed)

	_ratio = float(player.health) / float(player.max_health)
	_gauge.set_health(player.health, player.max_health)
	_gauge.set_recover(0.0, player.recover_hits_required)

	var dungeon: Node = get_node_or_null(dungeon_path) if not dungeon_path.is_empty() else null
	if dungeon != null and dungeon.has_signal("keys_changed"):
		_build_key_label()
		dungeon.keys_changed.connect(_on_keys_changed)
		_on_keys_changed(dungeon.keys)


var _key_label: Label


func _build_key_label() -> void:
	_key_label = Label.new()
	_key_label.position = gauge_position + Vector2(0.0, _gauge.size.y + 10.0)
	_key_label.add_theme_font_size_override("font_size", 26)
	_key_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.85))
	_key_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_key_label.add_theme_constant_override("outline_size", 6)
	add_child(_key_label)


func _on_keys_changed(count: int) -> void:
	if _key_label != null:
		_key_label.text = "Clés : %d" % count


func _on_health_changed(current: int, maximum: int) -> void:
	var new_ratio: float = float(current) / float(maximum)
	if new_ratio < _ratio:
		_pulse = pulse_intensity     # flash rouge seulement si on perd des PV
	_ratio = new_ratio
	_gauge.set_health(current, maximum)


func _on_recover_changed(progress: float, required: int) -> void:
	_gauge.set_recover(progress, required)


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - pulse_decay * delta, 0.0)

	# Vignette permanente quand la vie est basse, par-dessus le flash
	var low: float = 0.0
	if _ratio <= low_health_threshold and _ratio > 0.0:
		low = (1.0 - _ratio / low_health_threshold) * 0.45
		low *= 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.004)   # pulsation lente

	_mat.set_shader_parameter("intensity", maxf(_pulse, low))
