@tool
extends Resource
class_name RoomData

## Contenu d'une salle de donjon. La forme de la salle (taille, murs, portes)
## est décidée par le Dungeon et sa carte texte ; cette ressource ne décrit
## que ce qui se passe DEDANS. Une même RoomData peut servir à plusieurs
## salles : il suffit d'utiliser le même caractère dans la carte.
##
## Placement précis : `layout` et chaque vague de `waves` sont de petits
## dessins texte (une ligne = une rangée, un caractère = une case de 2 m).
## Une salle de 20 × 16 a donc 10 colonnes × 8 lignes. Le haut du dessin est
## le fond de la salle (nord), le bas est côté caméra. Le plus simple est de
## les dessiner à la souris dans le panneau « Donjon » de l'éditeur.
##
##   layout : P pilier   C coffre   k coffre de fin de combat   . vide
##   vagues : c chargeur   s tireur   b kamikaze   m corps à corps   B boss

enum KeySource {
	NONE,            ## pas de clé dans cette salle
	ON_CLEAR,        ## un coffre à clé apparaît sur la case « k » quand tous les ennemis sont morts
	CHEST,           ## un coffre contenant une clé est là dès l'arrivée
	CHEST_ON_CLEAR,  ## le coffre n'apparaît qu'une fois la salle vidée
}

@export_group("Vagues")
## Une vague par élément. La suivante arrive quand la précédente est morte.
## Laisse vide pour utiliser les nombres aléatoires du groupe « Ennemis ».
@export_multiline var waves: PackedStringArray = PackedStringArray()
@export var wave_delay: float = 1.0      ## pause entre deux vagues

@export_group("Ennemis (placement aléatoire)")
@export var chargers: int = 0
@export var shooters: int = 0
@export var bombers: int = 0
@export var melees: int = 0
@export var boss: bool = false
## Les ennemis reviennent à chaque nouvelle entrée, même si la salle a déjà été vidée.
@export var respawn_enemies: bool = false
@export var spawn_min_from_player: float = 5.0

@export_group("Règles")
## Plus utilisé : toute salle avec des ennemis enferme désormais le joueur.
## Gardé pour ne pas casser les salles déjà enregistrées.
@export var lock_in: bool = false
@export var key_source: KeySource = KeySource.NONE

@export_group("Disposition")
## Piliers, coffre et clé placés case par case (voir en haut du fichier).
@export_multiline var layout: String = ""
## Piliers en couronne, utilisés seulement si layout ne contient aucun P.
@export var pillar_count: int = 0
@export var pillar_spread: float = 0.3   ## fraction de la salle, depuis le centre
@export var pillar_size: float = 1.2


func enemy_count() -> int:
	return chargers + shooters + bombers + melees + (1 if boss else 0)


## Découpe un dessin texte en cases. Renvoie [{ "ch": String, "col": int,
## "row": int }] pour chaque caractère non vide, plus la taille de la grille.
static func parse_grid(text: String) -> Dictionary:
	var lines: PackedStringArray = text.strip_edges(false, true).split("\n")
	# On ignore les lignes vides du début (pratique dans l'inspecteur)
	while lines.size() > 0 and lines[0].strip_edges() == "":
		lines.remove_at(0)
	var cols: int = 0
	var cells: Array = []
	for r in lines.size():
		var line: String = lines[r].strip_edges(false, true)
		cols = maxi(cols, line.length())
		for c in line.length():
			var ch: String = line[c]
			if ch == "." or ch == " ":
				continue
			cells.append({"ch": ch, "col": c, "row": r})
	return {"cells": cells, "cols": cols, "rows": lines.size()}
