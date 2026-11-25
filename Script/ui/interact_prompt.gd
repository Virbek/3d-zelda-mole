extends Node3D
class_name InteractPrompt

## Indication « E : Ouvrir » d'un objet interactif, affichée en bas de l'écran
## dans un cadre rectangulaire (bord gris clair, fond sombre).
## Affiche la touche du dernier périphérique utilisé (clavier ou manette).
## Le parent décide quand l'afficher et quoi dire via show_action / show_text.
##
## Tous les prompts partagent une même couche d'interface : s'il y en a
## plusieurs visibles en même temps, ils s'empilent au lieu de se chevaucher.

const ACTION := "interact"

## Police de toutes les bulles de texte. Si le fichier manque, Godot
## retombe sur sa police par défaut.
const FONT_PATH := "res://Font/SairaStencilOne.ttf"

# Palette « rouille et sable », partagée par toutes les bulles de texte
const BORDER_COLOR := Color("#c8743a")        ## rouille
const BG_COLOR := Color(0.09, 0.067, 0.047, 0.94)  ## brun très sombre (#17110c)
const TITLE_COLOR := Color("#f0c27a")         ## sable doré
const TEXT_COLOR := Color("#e8dcc8")          ## sable clair
const MUTED_COLOR := Color("#a89478")         ## sable passé

## Teinte du texte. Lue par la porte pour savoir quel message est affiché.
var modulate: Color = Color.WHITE

var _using_pad: bool = false
var _verb: String = ""
var _panel: PanelContainer = null
var _label: Label = null

static var _box: VBoxContainer = null
static var _theme: Theme = null


func _ready() -> void:
	visible = false
	ensure_action()
	if Engine.is_editor_hint():
		return
	_build()


func _exit_tree() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null


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


## Cadre commun à toutes les bulles de texte : rectangle net, bord gris
## clair, intérieur gris très sombre. Aussi utilisé par l'écran d'objet.
static func make_box_style(border: int = 3) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(border)
	style.set_corner_radius_all(0)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


## Thème partagé par les bulles : il ne porte que la police.
static func ui_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	if ResourceLoader.exists(FONT_PATH):
		_theme.default_font = load(FONT_PATH) as Font
	return _theme


## « <touche> : verbe »
func show_action(verb: String) -> void:
	_verb = verb
	_set_text("%s : %s" % ["A" if _using_pad else "E", verb], Color.WHITE)


## Texte libre, sans touche (ex. « Il faut une clé »).
func show_text(t: String, color: Color = Color(1.0, 0.6, 0.5)) -> void:
	_verb = ""
	_set_text(t, color)


func hide_prompt() -> void:
	visible = false
	if _panel != null:
		_panel.visible = false


func _set_text(t: String, color: Color) -> void:
	modulate = color
	visible = true
	if _label == null:
		return
	_label.text = t
	# Blanc = message d'action standard : affiché dans le ton sable de la palette
	_label.add_theme_color_override("font_color", TEXT_COLOR if color == Color.WHITE else color)
	_panel.visible = true


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


# ---------------------------------------------------------------- INTERFACE

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", make_box_style())
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.visible = false
	_panel.theme = ui_theme()

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 14)
	_panel.add_child(_label)

	_shared_box().add_child(_panel)


## Colonne partagée, collée en bas au centre de l'écran.
func _shared_box() -> VBoxContainer:
	if _box != null and is_instance_valid(_box):
		return _box

	var layer := CanvasLayer.new()
	layer.layer = 30   # sous l'écran d'objet (40) et le menu pause (50)
	get_tree().root.add_child.call_deferred(layer)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_bottom", 48)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(margin)

	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.add_theme_constant_override("separation", 8)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_box)
	return _box
