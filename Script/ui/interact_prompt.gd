extends Label3D
class_name InteractPrompt

## Indication flottante « E : Ouvrir » au-dessus d'un objet interactif.
## Affiche la touche du dernier périphérique utilisé (clavier ou manette).
## Le parent décide quand l'afficher et quoi dire via show_action / show_text.

const ACTION := "interact"

var _using_pad: bool = false
var _verb: String = ""


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	pixel_size = 0.0018
	font_size = 20
	outline_size = 8
	render_priority = 10
	visible = false
	ensure_action()


## L'action est créée par script : aucun réglage du projet à toucher.
## Redéfinissable dans Projet → Réglages → Contrôles.
static func ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	InputMap.action_add_event(ACTION, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	InputMap.action_add_event(ACTION, pad)


## « <touche> : verbe »
func show_action(verb: String) -> void:
	_verb = verb
	text = "%s : %s" % ["A" if _using_pad else "E", verb]
	modulate = Color.WHITE
	visible = true


## Texte libre, sans touche (ex. « Il faut une clé »).
func show_text(t: String, color: Color = Color(1.0, 0.6, 0.5)) -> void:
	_verb = ""
	text = t
	modulate = color
	visible = true


func hide_prompt() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	var pad: bool = _using_pad
	if event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.3:
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	if pad != _using_pad:
		_using_pad = pad
		if visible and _verb != "":
			show_action(_verb)
