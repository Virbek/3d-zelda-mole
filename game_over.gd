extends CanvasLayer

## Écran de fin de partie. Construit par script pour éviter un .tscn à
## maintenir à la main. Écoute `player.died`, laisse le temps à la secousse
## de mort de jouer, fait un fondu au noir avec le titre et deux boutons.
## Les boutons restent désactivés jusqu'à la fin du fondu, pour éviter un
## clic accidentel pendant l'animation.

@export var player_path: NodePath
@export var fade_delay: float = 1.0     ## laisse la secousse de mort se jouer avant le fondu
@export var fade_duration: float = 0.8

@onready var player: CharacterBody3D = get_node(player_path)

var _overlay: ColorRect
var _title: Label
var _buttons: VBoxContainer
var _retry_button: Button
var _quit_button: Button
var _t: float = 0.0
var _fading: bool = false
var _ready_to_interact: bool = false


func _ready() -> void:
	visible = false
	_build_ui()
	player.died.connect(_on_player_died)


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_title = Label.new()
	_title.text = "GAME OVER"
	_title.add_theme_font_size_override("font_size", 48)
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.position.y -= 60
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.modulate.a = 0.0
	_overlay.add_child(_title)

	_buttons = VBoxContainer.new()
	_buttons.set_anchors_preset(Control.PRESET_CENTER)
	_buttons.position.y += 20
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.modulate.a = 0.0
	_overlay.add_child(_buttons)

	_retry_button = Button.new()
	_retry_button.text = "Recommencer"
	_retry_button.custom_minimum_size = Vector2(200, 44)
	_retry_button.disabled = true
	_retry_button.pressed.connect(_on_retry_pressed)
	_buttons.add_child(_retry_button)

	_quit_button = Button.new()
	_quit_button.text = "Quitter"
	_quit_button.custom_minimum_size = Vector2(200, 44)
	_quit_button.disabled = true
	_quit_button.pressed.connect(_on_quit_pressed)
	_buttons.add_child(_quit_button)


func _on_player_died() -> void:
	visible = true
	_t = 0.0
	_fading = false
	_ready_to_interact = false
	_retry_button.disabled = true
	_quit_button.disabled = true


func _process(delta: float) -> void:
	if not visible:
		return

	_t += delta

	if not _fading and _t >= fade_delay:
		_fading = true
		_t = 0.0

	if _fading:
		var k: float = clampf(_t / fade_duration, 0.0, 1.0)
		_overlay.color.a = k * 0.75
		_title.modulate.a = k
		_buttons.modulate.a = k

		if k >= 1.0 and not _ready_to_interact:
			_ready_to_interact = true
			_retry_button.disabled = false
			_quit_button.disabled = false
			_retry_button.grab_focus()


func _on_retry_pressed() -> void:
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	get_tree().quit()