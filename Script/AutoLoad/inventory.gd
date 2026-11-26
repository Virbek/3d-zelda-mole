extends Node

## Inventaire du joueur. Autoload (nom « Inventory ») : il survit aux
## rechargements de scène, donc à une mort ou un retour au checkpoint.
##
## Les petites clés ne sont PAS stockées ici : elles appartiennent au donjon
## (Dungeon.keys). L'inventaire se contente de les lire pour l'affichage.
##
## Pour l'instant rien ne remplit les emplacements de combat et
## d'exploration : ils sont prêts pour les futurs objets.

signal changed

const COMBAT_SLOTS: int = 4
const EXPLORATION_SLOTS: int = 4
const KEY_ITEM_SLOTS: int = 9   ## 6×2 en bas de l'écran, moins clés / fragments / grande clé
const FRAGMENTS_PER_CELL: int = 4   ## fragments de pile d'énergie pour une cellule de vie

var combat_items: Array[ItemData] = []
var exploration_items: Array[ItemData] = []
var key_items: Array[ItemData] = []
var energy_fragments: int = 0
var has_boss_key: bool = false

## Coffres déjà vidés (hors petites clés) : « scène|x,y » → true. Sans ça,
## un rechargement au checkpoint refermerait le coffre et redonnerait l'objet.
var _opened_chests: Dictionary = {}


func _ready() -> void:
	combat_items.resize(COMBAT_SLOTS)
	exploration_items.resize(EXPLORATION_SLOTS)


## Range un objet trouvé (coffre, sol...) dans la bonne case.
func add_item(item: ItemData) -> void:
	if item == null:
		return
	match item.category:
		ItemData.Category.SMALL_KEY:
			return   # le donjon les compte déjà
		ItemData.Category.BOSS_KEY:
			has_boss_key = true
		ItemData.Category.ENERGY_FRAGMENT:
			energy_fragments += 1
		ItemData.Category.KEY_ITEM:
			key_items.append(item)
		ItemData.Category.COMBAT:
			_place(combat_items, item)
		ItemData.Category.EXPLORATION:
			_place(exploration_items, item)
	changed.emit()


## PV max gagnés grâce aux piles d'énergie complètes.
func bonus_max_health() -> int:
	return floori(float(energy_fragments) / float(FRAGMENTS_PER_CELL))


## Fragments de la pile en cours (0 à FRAGMENTS_PER_CELL - 1).
func current_cell_fragments() -> int:
	return energy_fragments % FRAGMENTS_PER_CELL


## Petites clés du donjon courant (0 hors donjon).
func small_keys() -> int:
	var d: Node = get_tree().get_first_node_in_group(&"dungeon")
	if d == null:
		return 0
	return int(d.get("keys"))


func is_chest_opened(chest_id: String) -> bool:
	return _opened_chests.has(chest_id)


func mark_chest_opened(chest_id: String) -> void:
	_opened_chests[chest_id] = true


func _place(slots: Array[ItemData], item: ItemData) -> void:
	for i in slots.size():
		if slots[i] == null:
			slots[i] = item
			return
	push_warning("Inventory : plus de place pour %s" % item.display_name)
