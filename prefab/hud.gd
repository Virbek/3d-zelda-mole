extends CanvasLayer

@export var player_path: NodePath
@export var pulse_intensity: float = 0.75
@export var pulse_decay: float = 1.8
@export var low_health_threshold: float = 0.34

@onready var player: CharacterBody3D = get_node(player_path)
@onready var fill: ColorRect = $HealthBar/Fill
@onready var vignette: ColorRect = $Vignette

var _mat: ShaderMaterial
var _pulse: float = 0.0
var _ratio: float = 1.0
var _shown: float = 1.0


func _ready() -> void:
	_mat = vignette.material as ShaderMaterial
	fill.pivot_offset = Vector2.ZERO
	player.health_changed.connect(_on_health_changed)
	# On lit l'état actuel plutôt que d'attendre la prochaine émission
	_ratio = float(player.health) / float(player.max_health)
	_shown = _ratio


func _on_health_changed(current: int, maximum: int) -> void:
	var new_ratio: float = float(current) / float(maximum)
	if new_ratio < _ratio:
		_pulse = pulse_intensity     # flash rouge seulement si on perd des PV
	_ratio = new_ratio


func _process(delta: float) -> void:
	# La barre se vide en glissant, pas d'un coup
	_shown = lerp(_shown, _ratio, 1.0 - exp(-9.0 * delta))
	fill.scale.x = maxf(_shown, 0.0)

	if _pulse > 0.0:
		_pulse = maxf(_pulse - pulse_decay * delta, 0.0)

	# Vignette permanente quand la vie est basse, par-dessus le flash
	var low: float = 0.0
	if _ratio <= low_health_threshold and _ratio > 0.0:
		low = (1.0 - _ratio / low_health_threshold) * 0.45
		low *= 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.004)   # pulsation lente

	_mat.set_shader_parameter("intensity", maxf(_pulse, low))