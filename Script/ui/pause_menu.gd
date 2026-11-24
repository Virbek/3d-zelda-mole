extends CanvasLayer

## Menu pause. Autoload (nom « PauseMenu ») : disponible dans toutes les
## scènes sans rien ajouter aux .tscn. Construit par script.
##
## Échap ou Start ouvrent / ferment le menu. Pas ui_cancel : il contient le
## bouton B de la manette, qui sert déjà à l'esquive.
##
## Le menu tourne en PROCESS_MODE_ALWAYS ; le reste du jeu est figé par
## get_tree().paused.

const ACTION := "pause"

var _root: Control
var _resume_button: Button
var _volume_slider: HSlider
var _volume_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50   # au-dessus du HUD, sous le fondu des checkpoints (100)
	_register_action()
	_build_ui()
	visible = false


## L'action est créée ici plutôt que dans project.godot : le menu reste
## autonome, et on peut toujours la redéfinir dans les réglages du projet.
func _register_action() -> void:
	# Par défaut, ui_accept n'a que des touches clavier : sans ça, impossible
	# de valider un bouton à la manette (menu pause comme game over).
	var has_pad_accept := false
	for ev in InputMap.action_get_events("ui_accept"):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_A:
			has_pad_accept = true
	if not has_pad_accept:
		var accept := InputEventJoypadButton.new()
		accept.button_index = JOY_BUTTON_A
		InputMap.action_add_event("ui_accept", accept)

	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event(ACTION, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_START
	InputMap.action_add_event(ACTION, pad)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION):
		return
	if visible:
		resume()
	elif _can_pause():
		open()
	get_viewport().set_input_as_handled()


## Pas de pause pendant la mort (l'écran de game over prend le relais).
func _can_pause() -> bool:
	# Déjà en pause pour autre chose (écran « objet obtenu ») : on ne s'en mêle pas
	if get_tree().paused:
		return false
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return false
	if p.has_method("is_dead") and p.is_dead():
		return false
	return true


func open() -> void:
	get_tree().paused = true
	visible = true
	_sync_volume()
	_resume_button.grab_focus()


func resume() -> void:
	visible = false
	get_tree().paused = false


# ---------------------------------------------------------------- BOUTONS

func _on_restart_pressed() -> void:
	resume()
	# Même chemin qu'une mort : fondu, rechargement, retour au dernier checkpoint
	Checkpoints.respawn()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_volume_changed(value: float) -> void:
	Sfx.master_volume_db = value
	_volume_label.text = "Volume des effets : %d dB" % int(value)
	Sfx.play_ui("hit_light")   # aperçu immédiat du nouveau volume


func _sync_volume() -> void:
	_volume_slider.set_value_no_signal(Sfx.master_volume_db)
	_volume_label.text = "Volume des effets : %d dB" % int(Sfx.master_volume_db)


# ---------------------------------------------------------------- INTERFACE

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

	_resume_button = _add_button(box, "Reprendre", resume)
	_add_button(box, "Recommencer au checkpoint", _on_restart_pressed)

	_volume_label = Label.new()
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_volume_label)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = -40.0
	_volume_slider.max_value = 6.0
	_volume_slider.step = 1.0
	_volume_slider.custom_minimum_size = Vector2(260, 24)
	_volume_slider.value_changed.connect(_on_volume_changed)
	box.add_child(_volume_slider)

	_add_button(box, "Quitter", _on_quit_pressed)

	var hint := Label.new()
	hint.text = "Flèches / croix : choisir   ·   Entrée / A : valider   ·   Échap / Start : reprendre"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1.0, 1.0, 1.0, 0.7)
	box.add_child(hint)


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 44)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b
