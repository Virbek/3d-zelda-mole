@tool
extends HSplitContainer

## Panneau « Donjon ». À gauche la carte (salles et portes), à droite la
## salle sélectionnée (décor et vagues d'ennemis). Tout se fait à la souris.
##
## Chaque case de la carte a SA propre salle : modifier une salle ne touche
## jamais les autres. Les salles sont enregistrées dans la scène elle-même
## (pense à sauvegarder la scène, Ctrl+S). Ctrl+Z annule chaque action.

const CELL := 56.0          ## taille d'une salle sur la carte
const DOOR := 16.0          ## épaisseur d'une case de porte
const RCELL := 34.0         ## taille d'une case dans l'éditeur de salle
const RMARGIN := 16.0       ## marge autour de la grille de salle (portes)

const DECOR_TOOLS := [
	["P", "Bloc", Color(0.45, 0.45, 0.48)],
	["C", "Coffre", Color(0.55, 0.33, 0.15)],
	["k", "Clé", Color(1.0, 0.82, 0.2)],
]
const ENEMY_TOOLS := [
	["m", "Corps à corps", Color(0.85, 0.35, 0.3)],
	["c", "Chargeur", Color(0.62, 0.62, 0.68)],
	["s", "Tireur", Color(0.9, 0.85, 0.3)],
	["b", "Kamikaze", Color(1.0, 0.55, 0.15)],
	["B", "Boss", Color(0.4, 0.45, 1.0)],
]
const KEY_SOURCES := ["Pas de clé", "Clé quand la salle est vidée", "Coffre dès l'arrivée", "Coffre quand la salle est vidée"]

var undo_redo: EditorUndoRedoManager
var dungeon: Dungeon

# --- Carte ---
var _cells: Dictionary = {}       ## Vector2i → RoomData (une par case)
var _links: Dictionary = {}       ## Vector4i (a.x, a.y, b.x, b.y) → verrouillée
var _start := Vector2i.ZERO
var _sel := Vector2i.ZERO         ## salle éditée à droite
var _has_sel: bool = false
var _org := Vector2i.ZERO         ## case affichée en haut à gauche
var _size := Vector2i(5, 5)       ## nombre de cases affichées
var _map_canvas: Control
var _copy_sel: CheckBox
var _msg: Label

# --- Salle ---
var _room_title: Label
var _layer: OptionButton
var _tool_box: HBoxContainer
var _tool: String = "P"
var _room_canvas: Control
var _room_opts: Control
var _respawn: CheckBox
var _key_src: OptionButton
var _wave_delay: SpinBox
var _room_drag: bool = false
var _room_drag_erase: bool = false
var _room_prop: String = ""
var _room_before: Variant
var _updating_ui: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(0, 330)
	_build_map_side()
	_build_room_side()
	if undo_redo != null and not undo_redo.history_changed.is_connected(_on_history_changed):
		undo_redo.history_changed.connect(_on_history_changed)
	_refresh_all()


# ================================================================ INTERFACE

func _build_map_side() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 380
	add_child(left)

	var title := Label.new()
	title.text = "Carte du donjon"
	title.add_theme_font_size_override("font_size", 16)
	left.add_child(title)

	var help := Label.new()
	help.text = "Clic gauche sur une case vide : nouvelle salle\nClic gauche sur une salle : l'éditer à droite\nClic droit sur une salle : la supprimer\nClic entre deux salles : mur → porte → porte à clé"
	help.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	left.add_child(help)

	_copy_sel = CheckBox.new()
	_copy_sel.text = "Nouvelle salle = copie de la salle sélectionnée"
	left.add_child(_copy_sel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_map_canvas = Control.new()
	_map_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_canvas.draw.connect(_draw_map)
	_map_canvas.gui_input.connect(_map_input)
	scroll.add_child(_map_canvas)

	var row := HBoxContainer.new()
	left.add_child(row)
	var start := Button.new()
	start.text = "Salle de départ = sélection"
	start.pressed.connect(_set_start)
	row.add_child(start)

	_msg = Label.new()
	_msg.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_msg)


func _build_room_side() -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)

	_room_title = Label.new()
	_room_title.add_theme_font_size_override("font_size", 16)
	right.add_child(_room_title)

	_room_opts = VBoxContainer.new()
	_room_opts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_room_opts)

	var row := HBoxContainer.new()
	_room_opts.add_child(row)
	var l := Label.new()
	l.text = "Calque :"
	row.add_child(l)
	_layer = OptionButton.new()
	_layer.item_selected.connect(func(_i: int) -> void: _on_layer_changed())
	row.add_child(_layer)
	var add_w := Button.new()
	add_w.text = "+ Vague"
	add_w.pressed.connect(_add_wave)
	row.add_child(add_w)
	var del_w := Button.new()
	del_w.text = "Supprimer cette vague"
	del_w.pressed.connect(_remove_wave)
	row.add_child(del_w)

	_tool_box = HBoxContainer.new()
	_room_opts.add_child(_tool_box)

	var hint := Label.new()
	hint.text = "Clic gauche : poser · Clic droit : effacer · Glisser pour peindre. Les traits jaunes au bord sont les portes."
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room_opts.add_child(hint)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_opts.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_room_canvas = Control.new()
	_room_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_room_canvas.draw.connect(_draw_room)
	_room_canvas.gui_input.connect(_room_input)
	scroll.add_child(_room_canvas)

	var opts := VBoxContainer.new()
	opts.custom_minimum_size.x = 280
	body.add_child(opts)
	var lock_info := Label.new()
	lock_info.text = "S'il y a des ennemis, les portes se ferment\njusqu'à la fin de la dernière vague."
	lock_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	opts.add_child(lock_info)
	_respawn = CheckBox.new()
	_respawn.text = "Les ennemis reviennent à chaque visite"
	_respawn.toggled.connect(func(on: bool) -> void: _set_room_prop("respawn_enemies", on))
	opts.add_child(_respawn)
	var kl := Label.new()
	kl.text = "Clé :"
	opts.add_child(kl)
	_key_src = OptionButton.new()
	for k in KEY_SOURCES:
		_key_src.add_item(k)
	_key_src.item_selected.connect(func(i: int) -> void:
		_set_room_prop("key_source", i)
		var res: RoomData = _room_res()
		if res != null and (i == RoomData.KeySource.CHEST or i == RoomData.KeySource.CHEST_ON_CLEAR) and not res.layout.contains("C"):
			_msg_text("Pose un coffre (outil C, calque Décor) : sans lui, il n'y aura pas de coffre en jeu."))
	opts.add_child(_key_src)
	var wl := Label.new()
	wl.text = "Pause entre deux vagues (s) :"
	opts.add_child(wl)
	_wave_delay = SpinBox.new()
	_wave_delay.min_value = 0.0
	_wave_delay.max_value = 10.0
	_wave_delay.step = 0.1
	_wave_delay.value_changed.connect(func(v: float) -> void: _set_room_prop("wave_delay", v))
	opts.add_child(_wave_delay)
	var insp := Button.new()
	insp.text = "Ouvrir dans l'inspecteur"
	insp.pressed.connect(func() -> void:
		var res: RoomData = _room_res()
		if res != null:
			EditorInterface.edit_resource(res))
	opts.add_child(insp)


# ================================================================ ÉTAT

func set_dungeon(d: Dungeon) -> void:
	dungeon = d
	if dungeon != null and dungeon.layout_rooms.is_empty() and dungeon.map.strip_edges() != "":
		_convert_legacy()
	_load_map()
	_has_sel = _has_sel and _cells.has(_sel)
	if not _has_sel and _cells.has(_start):
		_sel = _start
		_has_sel = true
	_refresh_all()


## Ancien format (carte texte + une salle par lettre) : chaque case reçoit sa
## propre copie de la salle de sa lettre. Plus rien n'est partagé ensuite.
func _convert_legacy() -> void:
	var model: Dictionary = dungeon.get_model()
	var new_rooms: Dictionary[Vector2i, RoomData] = {}
	for cell in model["cells"]:
		var src: RoomData = model["cells"][cell]
		new_rooms[cell] = src.duplicate(true) if src != null else RoomData.new()
	var new_doors: Dictionary[Vector4i, int] = {}
	for l in model["links"]:
		new_doors[_link_key(l[0], l[1])] = Dungeon.DOOR_LOCKED if l[2] else Dungeon.DOOR_OPEN
	var empty_rooms: Dictionary[String, RoomData] = {}
	_do_props("Rendre les salles indépendantes", {
		"layout_rooms": new_rooms,
		"layout_doors": new_doors,
		"start_cell": model["start"],
		"map": "",
		"rooms": empty_rooms,
	})
	_msg_text("Chaque salle a maintenant son propre contenu. Les fichiers de data/dungeon/ ne sont plus utilisés par ce donjon.")


func _on_history_changed() -> void:
	if _room_drag or dungeon == null or not is_instance_valid(dungeon):
		return
	_load_map()
	if not _cells.has(_sel):
		_has_sel = false
	_refresh_all()


func _load_map() -> void:
	_cells.clear()
	_links.clear()
	if dungeon == null:
		return
	for cell in dungeon.layout_rooms:
		_cells[cell] = dungeon.layout_rooms[cell]
	for key in dungeon.layout_doors:
		_links[key] = dungeon.layout_doors[key] == Dungeon.DOOR_LOCKED
	_start = dungeon.start_cell
	_update_bounds()


func _update_bounds() -> void:
	if _cells.is_empty():
		_org = Vector2i(-2, -2)
		_size = Vector2i(5, 5)
	else:
		var mn := Vector2i(1 << 20, 1 << 20)
		var mx := Vector2i(-(1 << 20), -(1 << 20))
		for c in _cells:
			mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
			mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
		# Une case libre tout autour pour pouvoir agrandir le donjon
		_org = mn - Vector2i.ONE
		_size = mx - mn + Vector2i(3, 3)
		_size = Vector2i(maxi(_size.x, 5), maxi(_size.y, 5))
	var pitch: float = CELL + DOOR
	if _map_canvas != null:
		_map_canvas.custom_minimum_size = Vector2(_size.x * pitch, _size.y * pitch)


func _refresh_all() -> void:
	if _map_canvas == null:
		return
	_refresh_room_panel()
	_map_canvas.queue_redraw()


func _msg_text(t: String) -> void:
	if _msg != null:
		_msg.text = t


## Applique plusieurs propriétés du Dungeon en une seule action annulable.
func _do_props(action: String, props: Dictionary) -> void:
	if undo_redo == null:
		for k in props:
			dungeon.set(k, props[k])
		_load_map()
		_refresh_all()
		return
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, dungeon)
	for k in props:
		undo_redo.add_do_property(dungeon, k, props[k])
		undo_redo.add_undo_property(dungeon, k, dungeon.get(k))
	undo_redo.commit_action()


func _rooms_dict() -> Dictionary[Vector2i, RoomData]:
	var d: Dictionary[Vector2i, RoomData] = {}
	for c in _cells:
		d[c] = _cells[c]
	return d


func _doors_dict() -> Dictionary[Vector4i, int]:
	var d: Dictionary[Vector4i, int] = {}
	for k in _links:
		d[k] = Dungeon.DOOR_LOCKED if _links[k] else Dungeon.DOOR_OPEN
	return d


# ================================================================ CARTE

func _link_key(a: Vector2i, b: Vector2i) -> Vector4i:
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		var t: Vector2i = a
		a = b
		b = t
	return Vector4i(a.x, a.y, b.x, b.y)


func _cell_rect(cell: Vector2i) -> Rect2:
	var pitch: float = CELL + DOOR
	var p: Vector2i = cell - _org
	return Rect2(p.x * pitch, p.y * pitch, CELL, CELL)


func _door_rect(a: Vector2i, b: Vector2i) -> Rect2:
	var r: Rect2 = _cell_rect(a)
	if b.x != a.x:
		return Rect2(r.position.x + CELL, r.position.y + CELL * 0.2, DOOR, CELL * 0.6)
	return Rect2(r.position.x + CELL * 0.2, r.position.y + CELL, CELL * 0.6, DOOR)


func _draw_map() -> void:
	var font: Font = ThemeDB.fallback_font
	for y in _size.y:
		for x in _size.x:
			var cell: Vector2i = _org + Vector2i(x, y)
			var r: Rect2 = _cell_rect(cell)
			if _cells.has(cell):
				var res: RoomData = _cells[cell]
				var col := Color(0.42, 0.5, 0.62)
				if res != null and res.waves.size() > 0:
					col = Color(0.62, 0.42, 0.42)   # salle de combat
				_map_canvas.draw_rect(r, col)
				# Résumé : départ, vagues, clé
				var lines: PackedStringArray = []
				if cell == _start:
					lines.append("Départ")
				if res != null:
					if res.waves.size() > 0:
						lines.append("%d vague%s" % [res.waves.size(), "s" if res.waves.size() > 1 else ""])
					if res.key_source != RoomData.KeySource.NONE:
						lines.append("clé")
				for i in lines.size():
					_map_canvas.draw_string(font, r.position + Vector2(4, 14 + i * 13), lines[i], HORIZONTAL_ALIGNMENT_LEFT, CELL - 6, 11, Color.WHITE)
				if cell == _start:
					_map_canvas.draw_rect(r.grow(-2), Color(1, 1, 1), false, 2.0)
				if _has_sel and cell == _sel:
					_map_canvas.draw_rect(r.grow(1), Color(1.0, 0.85, 0.2), false, 3.0)
			else:
				_map_canvas.draw_rect(r, Color(0.16, 0.16, 0.18))
				_map_canvas.draw_rect(r, Color(0.3, 0.3, 0.33), false, 1.0)
				_map_canvas.draw_string(font, r.position + Vector2(CELL * 0.5 - 5, CELL * 0.5 + 6), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.35, 0.35, 0.38))
			# Portes vers la droite et vers le bas
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var other: Vector2i = cell + d
				if not (_cells.has(cell) and _cells.has(other)):
					continue
				var key: Vector4i = _link_key(cell, other)
				var dc := Color(0.28, 0.28, 0.3)
				if _links.has(key):
					dc = Color(0.85, 0.25, 0.2) if _links[key] else Color(0.95, 0.8, 0.3)
				_map_canvas.draw_rect(_door_rect(cell, other), dc)


## Ce qu'il y a sous la souris : ["room", cell] ou ["door", a, b] ou [].
func _map_hit(pos: Vector2) -> Array:
	var pitch: float = CELL + DOOR
	var gx: int = int(floor(pos.x / pitch))
	var gy: int = int(floor(pos.y / pitch))
	var lx: float = pos.x - gx * pitch
	var ly: float = pos.y - gy * pitch
	var cell: Vector2i = _org + Vector2i(gx, gy)
	if lx < CELL and ly < CELL:
		return ["room", cell]
	if lx >= CELL and ly < CELL:
		return ["door", cell, cell + Vector2i(1, 0)]
	if ly >= CELL and lx < CELL:
		return ["door", cell, cell + Vector2i(0, 1)]
	return []


func _map_input(event: InputEvent) -> void:
	if dungeon == null or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var hit: Array = _map_hit(mb.position)
	if hit.is_empty():
		return
	if hit[0] == "door":
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_cycle_door(hit[1], hit[2])
		return
	var cell: Vector2i = hit[1]
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if _cells.has(cell):
			_select(cell)
		else:
			_add_room(cell)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and _cells.has(cell):
		_remove_room(cell)


func _select(cell: Vector2i) -> void:
	_sel = cell
	_has_sel = true
	_msg_text("")
	_refresh_all()


func _add_room(cell: Vector2i) -> void:
	var res: RoomData
	if _copy_sel.button_pressed and _has_sel and _cells.get(_sel) != null:
		res = (_cells[_sel] as RoomData).duplicate(true)
	else:
		res = RoomData.new()
	var rooms: Dictionary[Vector2i, RoomData] = _rooms_dict()
	rooms[cell] = res
	var props: Dictionary = {"layout_rooms": rooms}
	if _cells.is_empty():
		props["start_cell"] = cell
	_sel = cell
	_has_sel = true
	_do_props("Nouvelle salle", props)


func _remove_room(cell: Vector2i) -> void:
	var rooms: Dictionary[Vector2i, RoomData] = _rooms_dict()
	rooms.erase(cell)
	var doors: Dictionary[Vector4i, int] = _doors_dict()
	for key in doors.keys():
		var k: Vector4i = key
		if Vector2i(k.x, k.y) == cell or Vector2i(k.z, k.w) == cell:
			doors.erase(key)
	var props: Dictionary = {"layout_rooms": rooms, "layout_doors": doors}
	if cell == _start and not rooms.is_empty():
		props["start_cell"] = rooms.keys()[0]
	if _sel == cell:
		_has_sel = false
	_do_props("Supprimer une salle", props)
	_msg_text("Salle supprimée (Ctrl+Z pour annuler).")


func _cycle_door(a: Vector2i, b: Vector2i) -> void:
	if not (_cells.has(a) and _cells.has(b)):
		_msg_text("Une porte relie deux salles : pose d'abord les deux salles.")
		return
	_msg_text("")
	var doors: Dictionary[Vector4i, int] = _doors_dict()
	var key: Vector4i = _link_key(a, b)
	if not doors.has(key):
		doors[key] = Dungeon.DOOR_OPEN
	elif doors[key] == Dungeon.DOOR_OPEN:
		doors[key] = Dungeon.DOOR_LOCKED
	else:
		doors.erase(key)
	_do_props("Changer une porte", {"layout_doors": doors})


func _set_start() -> void:
	if not _has_sel:
		_msg_text("Clique d'abord sur une salle.")
		return
	_do_props("Salle de départ", {"start_cell": _sel})


# ================================================================ SALLE

func _room_res() -> RoomData:
	if dungeon == null or not _has_sel:
		return null
	return _cells.get(_sel)


func _grid_dims() -> Vector2i:
	if dungeon == null:
		return Vector2i(10, 8)
	return Vector2i(maxi(1, roundi(dungeon.room_size.x / 2.0)), maxi(1, roundi(dungeon.room_size.y / 2.0)))


func _empty_grid() -> String:
	var d: Vector2i = _grid_dims()
	var rows: PackedStringArray = []
	for r in d.y:
		rows.append(".".repeat(d.x))
	return "\n".join(rows)


## Dessin texte → tableau [rangée][colonne] de caractères, aux dimensions de la salle.
func _to_grid(text: String) -> Array:
	var d: Vector2i = _grid_dims()
	var g: Array = []
	for r in d.y:
		var row: Array = []
		row.resize(d.x)
		row.fill(".")
		g.append(row)
	var parsed: Dictionary = RoomData.parse_grid(text)
	for c in parsed["cells"]:
		if c["row"] < d.y and c["col"] < d.x:
			g[c["row"]][c["col"]] = c["ch"]
	return g


func _from_grid(g: Array) -> String:
	var rows: PackedStringArray = []
	for row in g:
		rows.append("".join(PackedStringArray(row)))
	return "\n".join(rows)


func _layer_is_decor() -> bool:
	return _layer.selected <= 0


func _wave_index() -> int:
	return _layer.selected - 1


func _refresh_room_panel() -> void:
	var res: RoomData = _room_res()
	_room_opts.visible = res != null
	if res == null:
		_room_title.text = "Clique sur une salle de la carte pour l'éditer."
		return
	_room_title.text = "Salle (%d, %d)%s" % [_sel.x, _sel.y, "  —  départ" if _sel == _start else ""]

	_updating_ui = true
	var keep: int = _layer.selected
	_layer.clear()
	_layer.add_item("Décor (blocs, coffre, clé)")
	for i in res.waves.size():
		_layer.add_item("Vague %d" % (i + 1))
	_layer.select(clampi(keep, 0, _layer.item_count - 1))
	_respawn.set_pressed_no_signal(res.respawn_enemies)
	_key_src.select(int(res.key_source))
	_wave_delay.set_value_no_signal(res.wave_delay)
	_updating_ui = false

	_rebuild_tools()
	var d: Vector2i = _grid_dims()
	_room_canvas.custom_minimum_size = Vector2(d.x * RCELL + RMARGIN * 2.0, d.y * RCELL + RMARGIN * 2.0)
	_room_canvas.queue_redraw()


func _on_layer_changed() -> void:
	if _updating_ui:
		return
	_rebuild_tools()
	_room_canvas.queue_redraw()


func _rebuild_tools() -> void:
	for c in _tool_box.get_children():
		c.queue_free()
	var tools: Array = DECOR_TOOLS if _layer_is_decor() else ENEMY_TOOLS
	var valid: bool = false
	for t in tools:
		if t[0] == _tool:
			valid = true
	if not valid:
		_tool = tools[0][0]
	var group := ButtonGroup.new()
	for t in tools:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = "%s  %s" % [t[0], t[1]]
		b.add_theme_color_override("font_color", t[2])
		b.add_theme_color_override("font_pressed_color", t[2].lightened(0.4))
		b.button_pressed = t[0] == _tool
		var ch: String = t[0]
		b.pressed.connect(func() -> void: _tool = ch)
		_tool_box.add_child(b)


func _tool_color(ch: String) -> Color:
	for t in DECOR_TOOLS + ENEMY_TOOLS:
		if t[0] == ch:
			return t[2]
	return Color(1, 0, 1)


## Côtés de la salle sélectionnée où il y a une porte, d'après la carte.
func _room_door_dirs() -> Array:
	var dirs: Array = []
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if _links.has(_link_key(_sel, _sel + d)):
			dirs.append(d)
	return dirs


func _draw_room() -> void:
	var res: RoomData = _room_res()
	if res == null:
		return
	var font: Font = ThemeDB.fallback_font
	var d: Vector2i = _grid_dims()
	var origin := Vector2(RMARGIN, RMARGIN)
	var full := Vector2(d.x * RCELL, d.y * RCELL)

	_room_canvas.draw_rect(Rect2(Vector2.ZERO, full + origin * 2.0), Color(0.3, 0.29, 0.27))
	_room_canvas.draw_rect(Rect2(origin, full), Color(0.55, 0.52, 0.48))

	# Portes : traits jaunes au milieu des murs concernés
	var dw: float = dungeon.door_width / dungeon.room_size.x * full.x
	var dh: float = dungeon.door_width / dungeon.room_size.y * full.y
	var yellow := Color(0.95, 0.8, 0.3)
	for dir in _room_door_dirs():
		var r := Rect2()
		if dir == Vector2i(0, -1):
			r = Rect2(origin.x + full.x * 0.5 - dw * 0.5, 0, dw, RMARGIN)
		elif dir == Vector2i(0, 1):
			r = Rect2(origin.x + full.x * 0.5 - dw * 0.5, origin.y + full.y, dw, RMARGIN)
		elif dir == Vector2i(-1, 0):
			r = Rect2(0, origin.y + full.y * 0.5 - dh * 0.5, RMARGIN, dh)
		else:
			r = Rect2(origin.x + full.x, origin.y + full.y * 0.5 - dh * 0.5, RMARGIN, dh)
		_room_canvas.draw_rect(r, yellow)

	# Quadrillage
	for x in d.x + 1:
		_room_canvas.draw_line(origin + Vector2(x * RCELL, 0), origin + Vector2(x * RCELL, full.y), Color(0, 0, 0, 0.15))
	for y in d.y + 1:
		_room_canvas.draw_line(origin + Vector2(0, y * RCELL), origin + Vector2(full.x, y * RCELL), Color(0, 0, 0, 0.15))

	# Décor, toujours affiché
	var decor: Array = _to_grid(res.layout)
	for y in d.y:
		for x in d.x:
			var ch: String = decor[y][x]
			if ch == ".":
				continue
			var r := Rect2(origin + Vector2(x, y) * RCELL, Vector2(RCELL, RCELL))
			var faded: bool = not _layer_is_decor()
			var col: Color = _tool_color(ch if ch != "#" else "P")
			if faded:
				col.a = 0.6
			_room_canvas.draw_rect(r.grow(-2), col)
			if ch != "P" and ch != "#":
				_room_canvas.draw_string(font, r.position + Vector2(11, 23), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.BLACK)

	# Ennemis : la vague éditée en plein, les autres en transparence
	for wi in res.waves.size():
		var current: bool = not _layer_is_decor() and wi == _wave_index()
		if not current and not _layer_is_decor():
			continue
		var g: Array = _to_grid(res.waves[wi])
		for y in d.y:
			for x in d.x:
				var ch: String = g[y][x]
				if ch == ".":
					continue
				var center: Vector2 = origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * RCELL
				var col: Color = _tool_color(ch)
				if not current:
					col.a = 0.35
				_room_canvas.draw_circle(center, RCELL * 0.38, col)
				_room_canvas.draw_string(font, center + Vector2(-6, 7), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0, 0, 0, col.a))


func _room_cell_at(pos: Vector2) -> Vector2i:
	var d: Vector2i = _grid_dims()
	var p: Vector2 = (pos - Vector2(RMARGIN, RMARGIN)) / RCELL
	var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
	if c.x < 0 or c.y < 0 or c.x >= d.x or c.y >= d.y:
		return Vector2i(-1, -1)
	return c


func _room_input(event: InputEvent) -> void:
	var res: RoomData = _room_res()
	if res == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		if mb.pressed:
			if not _layer_is_decor() and res.waves.is_empty():
				return
			_room_drag = true
			_room_drag_erase = mb.button_index == MOUSE_BUTTON_RIGHT
			_room_prop = "layout" if _layer_is_decor() else "waves"
			_room_before = res.get(_room_prop)
			if _room_before is PackedStringArray:
				_room_before = (_room_before as PackedStringArray).duplicate()
			_paint_room(_room_cell_at(mb.position))
		elif _room_drag:
			_room_drag = false
			_commit_room(_room_prop, _room_before, res.get(_room_prop), "Dessiner la salle")
	elif event is InputEventMouseMotion and _room_drag:
		_paint_room(_room_cell_at((event as InputEventMouseMotion).position))


func _paint_room(cell: Vector2i) -> void:
	if cell.x < 0:
		return
	var res: RoomData = _room_res()
	var ch: String = "." if _room_drag_erase else _tool
	if _layer_is_decor():
		var g: Array = _to_grid(res.layout)
		# Un seul coffre et une seule clé par salle : poser l'un déplace l'ancien
		if ch == "C" or ch == "k":
			for row in g:
				for i in row.size():
					if row[i] == ch:
						row[i] = "."
		if g[cell.y][cell.x] == ch:
			return
		g[cell.y][cell.x] = ch
		res.layout = _from_grid(g)
	else:
		var waves: PackedStringArray = res.waves.duplicate()
		var g2: Array = _to_grid(waves[_wave_index()])
		if g2[cell.y][cell.x] == ch:
			return
		g2[cell.y][cell.x] = ch
		waves[_wave_index()] = _from_grid(g2)
		res.waves = waves
	_room_canvas.queue_redraw()


func _commit_room(prop: String, before: Variant, after: Variant, action: String) -> void:
	var res: RoomData = _room_res()
	if res == null or before == after:
		return

	# Poser un coffre ou une clé sans avoir choisi d'où vient la clé : on
	# règle l'option pour toi, sinon l'objet n'aurait pas de sens en jeu.
	# À l'inverse, effacer le dernier coffre remet l'option à « Pas de clé ».
	var auto_key: int = -1
	if prop == "layout":
		var has_c: bool = str(after).contains("C")
		var chest_mode: bool = res.key_source == RoomData.KeySource.CHEST \
			or res.key_source == RoomData.KeySource.CHEST_ON_CLEAR
		if res.key_source == RoomData.KeySource.NONE:
			if has_c:
				auto_key = RoomData.KeySource.CHEST
			elif str(after).contains("k"):
				auto_key = RoomData.KeySource.ON_CLEAR
		elif chest_mode and not has_c:
			auto_key = RoomData.KeySource.NONE
	if auto_key >= 0:
		_msg_text("Option « Clé » réglée sur « %s »." % KEY_SOURCES[auto_key])

	if undo_redo == null:
		res.set(prop, after)
		if auto_key >= 0:
			res.key_source = auto_key
		_after_room_change(res)
		return
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, dungeon)
	undo_redo.add_do_property(res, prop, after)
	undo_redo.add_undo_property(res, prop, before)
	if auto_key >= 0:
		undo_redo.add_do_property(res, "key_source", auto_key)
		undo_redo.add_undo_property(res, "key_source", res.key_source)
	undo_redo.add_do_method(self, "_after_room_change", res)
	undo_redo.add_undo_method(self, "_after_room_change", res)
	undo_redo.commit_action()


func _set_room_prop(prop: String, value: Variant) -> void:
	if _updating_ui:
		return
	var res: RoomData = _room_res()
	if res == null:
		return
	_commit_room(prop, res.get(prop), value, "Modifier la salle")


func _after_room_change(res: RoomData) -> void:
	# Une salle enregistrée dans son propre fichier .tres est sauvegardée tout
	# de suite ; une salle intégrée à la scène l'est avec la scène (Ctrl+S).
	if res.resource_path != "" and not res.resource_path.contains("::"):
		ResourceSaver.save(res)
	if dungeon != null and is_instance_valid(dungeon):
		dungeon.queue_preview()
	_refresh_room_panel()


func _add_wave() -> void:
	var res: RoomData = _room_res()
	if res == null:
		return
	var before: PackedStringArray = res.waves.duplicate()
	var after: PackedStringArray = res.waves.duplicate()
	after.append(_empty_grid())
	_commit_room("waves", before, after, "Ajouter une vague")
	_layer.select(_layer.item_count - 1)
	_on_layer_changed()


func _remove_wave() -> void:
	var res: RoomData = _room_res()
	if res == null or _layer_is_decor():
		return
	var before: PackedStringArray = res.waves.duplicate()
	var after: PackedStringArray = res.waves.duplicate()
	after.remove_at(_wave_index())
	_commit_room("waves", before, after, "Supprimer une vague")
