@tool
extends EditorPlugin

## Ajoute le panneau « Donjon » en bas de l'éditeur. Il s'active quand un
## nœud Dungeon est sélectionné dans la scène.

const DockScript := preload("res://addons/dungeon_editor/dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = DockScript.new()
	_dock.name = "Donjon"
	_dock.undo_redo = get_undo_redo()
	add_control_to_bottom_panel(_dock, "Donjon")


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null


func _handles(object: Object) -> bool:
	return object is Dungeon


func _edit(object: Object) -> void:
	if _dock != null:
		_dock.set_dungeon(object as Dungeon)


func _make_visible(visible: bool) -> void:
	if visible and _dock != null:
		make_bottom_panel_item_visible(_dock)
