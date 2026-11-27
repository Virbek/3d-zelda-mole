extends Control

## Menu principal, sobre : fond brun très sombre, titre au pochoir, deux
## boutons (Jouer, Quitter). Construit par script ; la scène MainMenu.tscn ne
## contient que ce nœud. C'est la scène de lancement du jeu, et on y revient
## après l'écran de fin.
##
## « Jouer » repart d'une partie neuve : checkpoint, progression du donjon,
## inventaire et cinématique d'intro sont remis à zéro.

const GAME_SCENE := "res://DungeonTest.tscn"
const GAME_TITLE := "La Taupe"            ## à remplacer par le vrai titre du jeu
const SUBTITLE := "Raffinerie ensablée"

const BG := Color("#0d0906")
const RUST := Color("#c8743a")
const SAND := Color("#f0c27a")
const TEXT := Color("#e8dcc8")
const MUTED := Color("#a89478")
const FONT_PATH := "res://Font/SairaStencilOne.ttf"

const IntroCinematic := preload("res://Script/dungeon/intro_cinematic.gd")

var _play_button: Button
var _fade: ColorRect
var _leaving: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	Engine.time_scale = 1.0
	_build()
	# Arrivée en fondu depuis le noir (début du jeu, retour de l'écran de fin)
	_fade.color.a = 1.0
	create_tween().tween_property(_fade, "color:a", 0.0, 0.6)
	# Différé : la mise en page doit être faite, sinon un survol fictif de
	# la souris peut donner le focus à un autre bouton au démarrage
	_play_button.grab_focus.call_deferred()


func _on_play() -> void:
	if _leaving:
		return
	_leaving = true
	Checkpoints.new_game()
	IntroCinematic.played_this_session = false
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.5)
	t.tween_callback(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))


func _on_quit() -> void:
	if _leaving:
		return
	get_tree().quit()


# ---------------------------------------------------------------- INTERFACE

func _build() -> void:
	var font: Font = load(FONT_PATH) as Font if ResourceLoader.exists(FONT_PATH) else null

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	center.add_child(box)

	var title := _label(GAME_TITLE, 96, SAND, font)
	box.add_child(title)

	# Fine ligne rouille sous le titre
	var line_holder := CenterContainer.new()
	var line := ColorRect.new()
	line.color = RUST
	line.custom_minimum_size = Vector2(320, 3)
	line_holder.add_child(line)
	box.add_child(line_holder)

	var sub := _label(SUBTITLE.to_upper(), 20, MUTED, font)
	sub.add_theme_constant_override("line_spacing", 0)
	box.add_child(_spacer(10))
	box.add_child(sub)
	box.add_child(_spacer(56))

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(buttons)
	_play_button = _button("Jouer", _on_play, font)
	buttons.add_child(_play_button)
	buttons.add_child(_button("Quitter", _on_quit, font))

	var hint := _label("Flèches / croix : choisir   ·   Entrée / A : valider", 14, MUTED.darkened(0.25), null)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position.y -= 36
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(hint)

	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _label(text: String, text_size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", text_size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Bouton plat : texte sable, cadre rouille quand il a le focus ou la souris.
func _button(text: String, callback: Callable, font: Font) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 52)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 26)
	if font != null:
		b.add_theme_font_override("font", font)
	b.add_theme_color_override("font_color", MUTED)
	b.add_theme_color_override("font_hover_color", SAND)
	b.add_theme_color_override("font_focus_color", SAND)
	b.add_theme_color_override("font_pressed_color", TEXT)

	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(0, 0, 0, 0)
	idle.set_border_width_all(2)
	idle.border_color = Color(RUST, 0.0)
	var active := StyleBoxFlat.new()
	active.bg_color = Color(0.09, 0.067, 0.047, 1.0)
	active.set_border_width_all(2)
	active.border_color = RUST
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", active)
	b.add_theme_stylebox_override("focus", active)
	b.add_theme_stylebox_override("pressed", active)

	b.pressed.connect(func() -> void: Sfx.play_ui("ui_confirm"))
	b.pressed.connect(callback)
	b.focus_entered.connect(func() -> void: Sfx.play_ui("ui_move", -6.0))
	b.mouse_entered.connect(func() -> void:
		if Input.get_last_mouse_velocity().length() > 0.0:
			b.grab_focus()
	)
	return b
