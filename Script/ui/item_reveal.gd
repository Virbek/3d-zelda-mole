extends CanvasLayer
class_name ItemReveal

## Écran « objet obtenu » : panneau en bas de l'écran avec l'image de
## l'objet, son nom et sa description. Tourne pendant que le jeu est en
## pause ; se ferme sur l'action « interact » ou ui_accept et émet closed.
##
## Construit par script, créé par le coffre au moment de l'ouverture.

signal closed

@export var min_show_time: float = 0.5   ## évite de fermer par erreur en appuyant encore sur la touche d'ouverture

var _root: Control
var _panel: PanelContainer
var _model_pivot: Node3D = null
var _shown_t: float = 0.0
var _closing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40   # sous le menu pause (50)


func show_item(item: ItemData) -> void:
	_build(item)
	_shown_t = 0.0
	_root.modulate.a = 0.0
	_panel.position.y += 40.0
	var t := create_tween().set_parallel(true)
	t.tween_property(_root, "modulate:a", 1.0, 0.2)
	t.tween_property(_panel, "position:y", _panel.position.y - 40.0, 0.25)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_shown_t += delta
	if _model_pivot != null:
		_model_pivot.rotation.y += 1.6 * delta


func _unhandled_input(event: InputEvent) -> void:
	if _closing or _shown_t < min_show_time:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	_closing = true
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.15)
	await t.finished
	closed.emit()
	queue_free()


# ---------------------------------------------------------------- INTERFACE

func _build(item: ItemData) -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Le panneau reste dans le tiers bas : le personnage, poing levé, est visible au-dessus.
	var bottom := MarginContainer.new()
	bottom.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom.add_theme_constant_override("margin_left", 80)
	bottom.add_theme_constant_override("margin_right", 80)
	bottom.add_theme_constant_override("margin_bottom", 40)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bottom)

	var anchor := VBoxContainer.new()
	anchor.alignment = BoxContainer.ALIGNMENT_END
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(anchor)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.1, 0.88)
	style.border_color = item.color
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 24
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", style)
	anchor.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_panel.add_child(row)

	row.add_child(_build_image(item))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 8)
	row.add_child(text)

	var got := Label.new()
	got.text = "Vous obtenez"
	got.add_theme_font_size_override("font_size", 16)
	got.modulate = Color(1.0, 1.0, 1.0, 0.7)
	text.add_child(got)

	var title := Label.new()
	title.text = item.display_name
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", item.color)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	text.add_child(title)

	var desc := Label.new()
	desc.text = item.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 360
	desc.add_theme_font_size_override("font_size", 20)
	text.add_child(desc)

	var hint := Label.new()
	hint.text = "A / E : continuer"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	text.add_child(hint)


## Image de l'objet : la texture si elle existe, sinon son modèle 3D qui
## tourne dans un petit monde à part (il ne voit pas le donjon).
func _build_image(item: ItemData) -> Control:
	const SIZE := 150
	if item.icon != null:
		var tex := TextureRect.new()
		tex.texture = item.icon
		tex.custom_minimum_size = Vector2(SIZE, SIZE)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex

	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(SIZE, SIZE)
	container.stretch = true

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(SIZE, SIZE)
	container.add_child(vp)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.05, 1.3)
	cam.fov = 40.0
	vp.add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(30.0), 0.0)
	vp.add_child(light)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.8)
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	vp.add_child(env)

	_model_pivot = Node3D.new()
	_model_pivot.rotation.z = deg_to_rad(-20.0)
	vp.add_child(_model_pivot)
	_model_pivot.add_child(item.build_model())
	return container
