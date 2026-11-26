extends CanvasLayer

## Écran d'inventaire. Autoload (nom « InventoryMenu »), construit par script.
##
##   ┌──────────────┬──────────────────────────────┐
##   │   portrait   │  [ ][ ][ ][ ]  ← combat      │
##   │  de la taupe │  [ ][ ][ ][ ]  ← exploration │
##   │   (de face)  │  ┌ description ────────────┐ │
##   ├──────────────┴──────────────────────────────┤
##   │   [clés][frag][grande clé][ ][ ][ ]         │
##   │   [ ][ ][ ][ ][ ][ ]   ← objets clés        │
##   └─────────────────────────────────────────────┘
##
## I / Tab ou Select ouvrent et ferment ; Échap / Start ferment aussi.
## Le jeu est en pause pendant l'affichage.

const ACTION := "inventory"
const PAUSE_ACTION := "pause"

const EMPTY_TEXT := "Vide"
const SLOT_SIZE := 76
const PORTRAIT_SIZE := Vector2i(230, 290)
## Pose calme du portrait : gantelets qui pendent le long du corps.
const PORTRAIT_HAND_DROP: float = -0.42   ## hauteur des mains dans le repère du corps
const PORTRAIT_HAND_GAP: float = 0.16     ## écart entre la surface du corps et le centre du gantelet
const PORTRAIT_HAND_PITCH_DEG: float = -90.0  ## poings tournés vers le sol au lieu de l'avant

const SLOT_BG := Color(0.13, 0.095, 0.065, 1.0)
const SLOT_EMPTY_BORDER := Color("#5a3a22")
const RED := Color(0.78, 0.21, 0.17)
const INK := Color(0.05, 0.03, 0.02)

var _root: Control
var _portrait_vp: SubViewport      ## studio hors écran : sert seulement à prendre la photo
var _portrait_rect: TextureRect    ## la photo affichée, une image fixe
var _portrait_pivot: Node3D
var _portrait_cam: Camera3D
var _equip_grid: GridContainer   ## 4×2 : rangée du haut = combat, du bas = exploration
var _found_grid: GridContainer   ## 6×2 : clés, fragments, grande clé, puis objets clés
var _desc_title: Label
var _desc_text: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	_register_action()
	_build_ui()
	visible = false


func _register_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	for code: Key in [KEY_I, KEY_TAB]:
		var key := InputEventKey.new()
		key.physical_keycode = code
		InputMap.action_add_event(ACTION, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_BACK
	InputMap.action_add_event(ACTION, pad)


## Fermeture dans _input : sinon Tab serait mangé par la navigation des
## boutons (ui_focus_next) avant d'arriver ici.
func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(ACTION) or event.is_action_pressed(PAUSE_ACTION)):
		Sfx.play_ui("ui_back")
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible and event.is_action_pressed(ACTION) and _can_open():
		open()
		get_viewport().set_input_as_handled()


func _can_open() -> bool:
	if get_tree().paused:
		return false
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null:
		return false
	if p.has_method("is_dead") and p.is_dead():
		return false
	return true


func open() -> void:
	Sfx.play_ui("pause")
	get_tree().paused = true
	_refresh()
	_take_portrait()
	visible = true
	var first: Control = _equip_grid.get_child(0) as Control
	if first != null:
		first.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false
	_clear_portrait()


# ---------------------------------------------------------------- CONTENU

func _refresh() -> void:
	_clear(_equip_grid)
	_add_equipment(Inventory.combat_items)
	_add_equipment(Inventory.exploration_items)

	_clear(_found_grid)
	var keys: int = Inventory.small_keys()
	_found_grid.add_child(_make_slot(
		_item_thumb(ItemData.small_key(), keys > 0),
		"x%d" % keys,
		"Petites clés",
		"Ouvrent les portes verrouillées de ce donjon. Restent dans le donjon où on les trouve."))

	var frag: int = Inventory.current_cell_fragments()
	var frag_icon := FragmentIcon.new()
	frag_icon.count = frag
	frag_icon.total = Inventory.FRAGMENTS_PER_CELL
	_found_grid.add_child(_make_slot(
		frag_icon,
		"%d/%d" % [frag, Inventory.FRAGMENTS_PER_CELL],
		"Fragments de pile d'énergie",
		"Réunis-en %d pour reformer une pile : une cellule de vie en plus." % Inventory.FRAGMENTS_PER_CELL))

	var boss_key := ItemData.new()
	boss_key.color = Color("#d9a441")
	_found_grid.add_child(_make_slot(
		_item_thumb(boss_key, Inventory.has_boss_key, 1.35),
		"",
		"Grande clé" if Inventory.has_boss_key else "Grande clé — introuvable",
		"Ouvre la porte blindée du gardien de la raffinerie." if Inventory.has_boss_key
			else "Quelque part dans ce donjon…"))

	for i in Inventory.KEY_ITEM_SLOTS:
		if i < Inventory.key_items.size():
			var it: ItemData = Inventory.key_items[i]
			_found_grid.add_child(_make_slot(_item_thumb(it, true), "", it.display_name, it.description))
		else:
			_found_grid.add_child(_make_slot(null, "", EMPTY_TEXT, ""))


func _add_equipment(items: Array[ItemData]) -> void:
	for it: ItemData in items:
		if it == null:
			_equip_grid.add_child(_make_slot(null, "", EMPTY_TEXT, ""))
		else:
			_equip_grid.add_child(_make_slot(_item_thumb(it, true), "", it.display_name, it.description))


func _clear(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


# ---------------------------------------------------------------- CASES

func _make_slot(content: Control, badge: String, title: String, desc: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	b.focus_mode = Control.FOCUS_ALL
	var filled: bool = content != null
	b.add_theme_stylebox_override("normal", _slot_style(InteractPrompt.BORDER_COLOR if filled else SLOT_EMPTY_BORDER, 2))
	b.add_theme_stylebox_override("hover", _slot_style(InteractPrompt.TITLE_COLOR, 2))
	b.add_theme_stylebox_override("pressed", _slot_style(InteractPrompt.TITLE_COLOR, 3))
	b.add_theme_stylebox_override("focus", _slot_style(InteractPrompt.TITLE_COLOR, 3))

	if content != null:
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 6
		content.offset_top = 6
		content.offset_right = -6
		content.offset_bottom = -6
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(content)
	else:
		# Case vide : deux rivets dans les coins, rien d'autre
		var rivets := RivetIcon.new()
		rivets.set_anchors_preset(Control.PRESET_FULL_RECT)
		rivets.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(rivets)

	if badge != "":
		var l := Label.new()
		l.text = badge
		l.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
		l.offset_right = -4
		l.offset_bottom = -1
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", InteractPrompt.TEXT_COLOR)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 5)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)

	b.focus_entered.connect(func() -> void:
		Sfx.play_ui("ui_move", -6.0)
		_show_description(title, desc))
	b.mouse_entered.connect(b.grab_focus)
	return b


func _slot_style(border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SLOT_BG
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(0)
	return s


func _show_description(title: String, desc: String) -> void:
	_desc_title.text = title
	_desc_text.text = desc


## Modèle 3D d'un objet, figé, dans un petit monde à part. `lit` = false le
## rend en silhouette sombre (objet pas encore trouvé).
func _item_thumb(item: ItemData, lit: bool, zoom: float = 1.0) -> Control:
	if item.icon != null:
		var tex := TextureRect.new()
		tex.texture = item.icon
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if not lit:
			tex.modulate = Color(0.15, 0.12, 0.1, 0.8)
		return tex

	var container := SubViewportContainer.new()
	container.stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(SLOT_SIZE, SLOT_SIZE)
	container.add_child(vp)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.05, 1.5 / zoom)
	cam.fov = 40.0
	vp.add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(30.0), 0.0)
	vp.add_child(light)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.8)
	vp.add_child(env)

	var pivot := Node3D.new()
	pivot.rotation.z = deg_to_rad(-25.0)
	vp.add_child(pivot)
	pivot.add_child(item.build_model())

	if not lit:
		container.modulate = Color(0.12, 0.09, 0.07, 0.9)
	return container


# ---------------------------------------------------------------- PORTRAIT

## Copie visuelle du personnage (corps, tenue, gantelets, bottes), sans
## scripts ni collisions, remise en POSE CALME (mains le long du corps) et vue de face : la pose
## réelle en jeu (course, coup en cours) donnait des membres de travers.
## Le rendu est fait une seule fois, l'image reste figée.
func _rebuild_portrait() -> void:
	_clear_portrait()
	_portrait_pivot = Node3D.new()
	_portrait_pivot.rotation.y = PI   # le modèle regarde -Z, la caméra est en +Z
	_portrait_vp.add_child(_portrait_pivot)

	var p := get_tree().get_first_node_in_group("player") as Node3D
	var rig: Node3D = p.get("rig") as Node3D if p != null else null
	if rig == null:
		return

	# Pose de repos, dans le repère du joueur (avant = -Z), avec les réglages du rig
	var body_h: float = float(rig.get("body_height"))
	var hand_x: float = MoleOutfit.body_radius(PORTRAIT_HAND_DROP) + PORTRAIT_HAND_GAP
	var stance: float = float(rig.get("stance_width"))
	var rest: Dictionary = {
		"Body": Vector3(0.0, body_h, 0.0),
		"HandL": Vector3(-hand_x, PORTRAIT_HAND_DROP + body_h, 0.0),
		"HandR": Vector3(hand_x, PORTRAIT_HAND_DROP + body_h, 0.0),
		"FootL": Vector3(-stance, 0.0, 0.0),
		"FootR": Vector3(stance, 0.0, 0.0),
	}

	var to_local: Transform3D = Transform3D(Basis(Vector3.UP, p.rotation.y), p.global_position).affine_inverse()
	for part: String in rest.keys():
		var src := rig.get_node_or_null(part) as Node3D
		if src == null:
			continue
		var copy := src.duplicate(0) as Node3D   # 0 : ni scripts, ni signaux, ni groupes
		_strip_non_visual(copy)
		copy.top_level = false
		_portrait_pivot.add_child(copy)
		var pos: Vector3 = rest[part]
		if part.begins_with("Foot"):
			pos.y = (to_local * src.global_position).y   # les pieds restent au sol
		var basis := Basis.from_scale(src.global_basis.get_scale())
		if part.begins_with("Hand"):
			basis = Basis(Vector3.RIGHT, deg_to_rad(PORTRAIT_HAND_PITCH_DEG)) * basis
		copy.transform = Transform3D(basis, pos)

	_frame_portrait()


## Pose la copie dans le studio, rend UNE image, la garde en texture fixe,
## puis vide le studio : rien ne peut plus bouger à l'écran.
func _take_portrait() -> void:
	_rebuild_portrait()
	_portrait_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img: Image = _portrait_vp.get_texture().get_image()
	_portrait_rect.texture = ImageTexture.create_from_image(img)
	_portrait_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_clear_portrait()


func _clear_portrait() -> void:
	if _portrait_pivot != null and is_instance_valid(_portrait_pivot):
		_portrait_pivot.queue_free()
	_portrait_pivot = null


func _strip_non_visual(n: Node) -> void:
	for c in n.get_children():
		if c is CollisionObject3D or c is CollisionShape3D or c is AudioStreamPlayer3D \
				or c is GPUParticles3D or c is CPUParticles3D or c is RayCast3D \
				or c is ShapeCast3D or c is Camera3D or not (c is Node3D):
			n.remove_child(c)
			c.free()
		else:
			_strip_non_visual(c)


## Cadre la caméra sur la boîte englobante des maillages visibles.
func _frame_portrait() -> void:
	var box := AABB()
	var first: bool = true
	for m: Node in _portrait_pivot.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var center: Vector3 = box.get_center()
	var half_h: float = maxf(box.size.y, box.size.x * float(PORTRAIT_SIZE.y) / float(PORTRAIT_SIZE.x)) * 0.5 * 1.12
	var dist: float = half_h / tan(deg_to_rad(_portrait_cam.fov * 0.5)) + box.size.z * 0.5
	_portrait_cam.position = center + Vector3(0.0, half_h * 0.08, dist)
	_portrait_cam.look_at(center, Vector3.UP)


# ---------------------------------------------------------------- INTERFACE

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = InteractPrompt.ui_theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var frame := PanelContainer.new()
	var fs := InteractPrompt.make_box_style(4)
	fs.set_content_margin_all(20)
	frame.add_theme_stylebox_override("panel", fs)
	center.add_child(frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	frame.add_child(col)

	col.add_child(_title_label("INVENTAIRE", 30))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	col.add_child(top)

	top.add_child(_build_portrait_panel())

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right)

	_equip_grid = _slot_grid(Inventory.COMBAT_SLOTS)
	right.add_child(_equip_grid)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	right.add_child(_build_description_box())

	var rule := ColorRect.new()
	rule.color = InteractPrompt.BORDER_COLOR
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)

	var objects_title := Label.new()
	objects_title.text = "OBJETS"
	objects_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objects_title.add_theme_font_size_override("font_size", 18)
	objects_title.add_theme_color_override("font_color", InteractPrompt.TITLE_COLOR)
	col.add_child(objects_title)

	_found_grid = _slot_grid(6)
	_found_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_found_grid)

	var hint := Label.new()
	hint.text = "Flèches / croix : parcourir   ·   I / Tab / Select : fermer"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", InteractPrompt.MUTED_COLOR)
	col.add_child(hint)


func _build_portrait_panel() -> Control:
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.2, 0.14, 0.09, 1.0)
	ps.border_color = InteractPrompt.BORDER_COLOR
	ps.set_border_width_all(3)
	ps.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", ps)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	panel.add_child(stack)

	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(PORTRAIT_SIZE)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stack.add_child(_portrait_rect)

	# Pas dans un SubViewportContainer : le conteneur remet le rendu en
	# continu dès qu'il redevient visible. Ici on décide seul quand rendre.
	_portrait_vp = SubViewport.new()
	_portrait_vp.own_world_3d = true
	_portrait_vp.transparent_bg = true
	_portrait_vp.size = PORTRAIT_SIZE
	_portrait_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_portrait_vp)

	_portrait_cam = Camera3D.new()
	_portrait_cam.fov = 30.0
	_portrait_cam.position = Vector3(0.0, 0.8, 4.0)
	_portrait_vp.add_child(_portrait_cam)

	var key_light := DirectionalLight3D.new()
	key_light.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(25.0), 0.0)
	_portrait_vp.add_child(key_light)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.68, 0.6)
	_portrait_vp.add_child(env)

	# Plaque de nom rivetée sous le portrait
	var plate := PanelContainer.new()
	var pls := StyleBoxFlat.new()
	pls.bg_color = InteractPrompt.BORDER_COLOR
	pls.set_content_margin_all(4)
	plate.add_theme_stylebox_override("panel", pls)
	stack.add_child(plate)
	var name_label := Label.new()
	name_label.text = "LA TAUPE"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", INK)
	plate.add_child(name_label)
	return panel


func _build_description_box() -> Control:
	var box := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = SLOT_BG
	s.border_color = SLOT_EMPTY_BORDER
	s.set_border_width_all(2)
	s.set_content_margin_all(10)
	box.add_theme_stylebox_override("panel", s)
	box.custom_minimum_size = Vector2(0, 86)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)

	_desc_title = Label.new()
	_desc_title.add_theme_font_size_override("font_size", 17)
	_desc_title.add_theme_color_override("font_color", InteractPrompt.TITLE_COLOR)
	v.add_child(_desc_title)

	_desc_text = Label.new()
	_desc_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_text.custom_minimum_size.x = 300
	_desc_text.add_theme_font_size_override("font_size", 13)
	_desc_text.add_theme_color_override("font_color", InteractPrompt.TEXT_COLOR)
	v.add_child(_desc_text)
	return box


func _slot_grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	return g


func _title_label(t: String, size: int) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", InteractPrompt.TITLE_COLOR)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	return l


# ---------------------------------------------------------------- ICÔNES

## Pile d'énergie en cours de reconstruction : une pile verticale découpée
## en segments, cyan pour chaque fragment trouvé.
class FragmentIcon extends Control:
	var count: int = 0
	var total: int = 4

	func _draw() -> void:
		var w: float = size.x * 0.42
		var h: float = size.y * 0.74
		var body := Rect2(Vector2((size.x - w) * 0.5, size.y - h - size.y * 0.06), Vector2(w, h))
		# Borne en haut
		var tip := Rect2(Vector2(size.x * 0.5 - w * 0.2, body.position.y - 6.0), Vector2(w * 0.4, 6.0))
		draw_rect(tip.grow(2.0), INK)
		draw_rect(tip, Color(0.62, 0.62, 0.6))
		# Coque rouille + trait noir
		draw_rect(body.grow(5.0), InteractPrompt.BORDER_COLOR)
		draw_rect(body.grow(2.0), INK)
		draw_rect(body, Color(0.2, 0.14, 0.1))
		# Segments, du bas vers le haut
		var gap: float = 3.0
		var seg_h: float = (body.size.y - gap * float(total + 1)) / float(total)
		for i in total:
			var y: float = body.end.y - gap - seg_h * float(i + 1) - gap * float(i)
			var seg := Rect2(Vector2(body.position.x + gap, y), Vector2(body.size.x - gap * 2.0, seg_h))
			if i < count:
				draw_rect(seg, ItemData.ENERGY_CYAN)
				draw_rect(Rect2(seg.position, Vector2(seg.size.x, 3.0)), ItemData.ENERGY_CYAN.lightened(0.5))
			else:
				draw_rect(seg, Color(0.12, 0.09, 0.07))


## Case vide : rivets dans les coins.
class RivetIcon extends Control:
	func _draw() -> void:
		var m: float = 9.0
		for p: Vector2 in [Vector2(m, m), Vector2(size.x - m, m), Vector2(m, size.y - m), Vector2(size.x - m, size.y - m)]:
			draw_circle(p, 3.0, SLOT_EMPTY_BORDER)
