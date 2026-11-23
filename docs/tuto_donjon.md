# Tuto : créer un donjon

Tout se fait à la souris dans le panneau **Donjon**, en bas de l'éditeur Godot.
Plus besoin d'aligner des lettres à la main.

Exemple complet : ouvre `DungeonTest.tscn` et clique sur le nœud **Dungeon**.

---

## 0. Activer le panneau (une seule fois)

Le plugin est déjà activé dans le projet. Si l'onglet **Donjon** n'apparaît
pas en bas de l'éditeur :

1. **Projet → Paramètres du projet → Plugins**.
2. Coche **Activé** sur la ligne « Éditeur de donjon ».

Si tu viens de récupérer ces fichiers, **ferme et rouvre le projet** une fois
pour que Godot charge le plugin.

---

## 1. Mettre un donjon dans une scène

Le plus simple : duplique `DungeonTest.tscn` et pars de là.

Pour une nouvelle scène :

1. Ajoute un nœud **Node3D**, nomme-le `Dungeon` et attache-lui le script
   `Script/dungeon/dungeon.gd`.
2. Dans l'inspecteur du Dungeon :
   - **Player Path** → ton nœud `Player` ;
   - **Camera Rig Path** → ton nœud `CameraRig` ;
   - **Scènes d'ennemis** : glisse `Enemy.tscn` (chargeur), `EnemyShooter.tscn`,
     `EnemyBomber.tscn`, `EnemyMelee.tscn` et `Boss/1Boss.tscn`.
3. Sur le nœud **Hud**, renseigne **Dungeon Path** pour afficher le compteur de clés.
4. Supprime l'`Arena` de la scène s'il y en a une.

Le donjon apparaît directement dans la vue 3D de l'éditeur (sans ennemis) et se
met à jour à chaque modification. La salle de départ est centrée sur le nœud
`Dungeon`.

---

## 2. Le panneau « Donjon »

Clique sur le nœud **Dungeon** dans la scène : l'onglet **Donjon** s'ouvre en
bas. Il a deux moitiés :

- **à gauche, la carte** : quelles salles, où, et les portes entre elles ;
- **à droite, la salle sélectionnée** : son décor et ses vagues d'ennemis.

Chaque modification s'annule avec **Ctrl+Z**. Les salles sont enregistrées
avec la scène : sauvegarde-la (**Ctrl+S**).

---

## 3. Construire la carte

**Chaque case de la carte est une salle indépendante** : modifier une salle ne
change jamais les autres.

| Action | Effet |
|---|---|
| **Clic gauche sur une case vide** (marquée `+`) | crée une nouvelle salle vide |
| **Clic gauche sur une salle** | la sélectionne et l'ouvre à droite pour l'éditer |
| **Clic droit sur une salle** | la supprime (avec ses portes) |
| **Clic sur le trait** entre deux salles voisines | mur → porte ouverte → porte à clé → mur |
| Bouton **Salle de départ = sélection** | le joueur commence dans la salle sélectionnée |

Pour gagner du temps, coche **Nouvelle salle = copie de la salle sélectionnée** :
la prochaine salle créée part d'une copie de celle que tu as sélectionnée.
C'est une vraie copie : tu peux ensuite la modifier sans toucher l'originale.

Sur la carte, chaque salle affiche un résumé : **Départ**, nombre de
**vagues**, **clé**. Les salles de combat sont rouges, les autres bleues.

Couleur des traits entre deux salles :

- **gris** : mur plein ;
- **jaune** : porte ouverte ;
- **rouge** : porte verrouillée (il faut une clé).

La salle de départ a un **contour blanc**, celle que tu édites un
**contour jaune**. Une rangée de cases libres entoure toujours la carte pour
pouvoir l'agrandir.

En jeu, devant chaque porte, un marquage au sol reprend ces couleurs (gris =
porte fermée pendant un combat).

Les salles sont enregistrées **dans la scène** : pense à sauvegarder la scène
(**Ctrl+S**) après tes modifications.

---

## 4. Dessiner une salle : décor et ennemis

**Clic gauche** sur une salle de la carte : elle s'affiche à droite, vue de
dessus. Le haut de la grille est le fond de la salle (nord), le bas est côté
caméra. Une case = 2 m (une salle de 20 × 20 fait 10 × 10 cases).

Les **traits jaunes sur les bords** montrent où sont les portes de cette salle.
Ne bloque pas leur passage et ne mets pas d'ennemi juste devant : le joueur
arrive par là.

### Le calque « Décor »

| Outil | Effet |
|---|---|
| **P Bloc** | un bloc qui remplit la case ; plusieurs blocs côte à côte font un mur |
| **C Coffre** | position du coffre (un seul par salle) |
| **k Clé** | où apparaît la clé quand la salle est vidée (une seule) |

### Les vagues d'ennemis

1. Clique sur **+ Vague** : un calque « Vague 1 » est créé et sélectionné.
2. Choisis un ennemi : **m** corps à corps, **c** chargeur, **s** tireur,
   **b** kamikaze, **B** boss.
3. **Clic gauche** pour poser, **clic droit** pour effacer. Tu peux glisser.
4. **+ Vague** à nouveau pour la vague suivante.

En jeu :

- la vague 1 apparaît quand le joueur entre ;
- quand tous ses ennemis sont morts, on attend la **pause entre deux vagues**,
  puis la vague suivante apparaît ;
- après la dernière vague, la salle est **vidée** : portes rouvertes, clé ou
  coffre donnés.

Le calque **Décor** montre aussi tous les ennemis en transparence. Chaque
calque de vague montre le décor en transparence, pour placer les ennemis
autour des blocs.

**Supprimer cette vague** retire la vague affichée.

---

## 5. Règles de la salle

À droite de la grille :

- **Combat = salle fermée** : dès qu'une salle a des ennemis, ses portes se
  ferment derrière le joueur et se rouvrent quand toutes les vagues sont
  vaincues. Il n'y a rien à cocher. Les portes à clé restent verrouillées.
- **Les ennemis reviennent à chaque visite** : sinon, une salle vidée reste vide.
  Une salle quittée **avant** d'être vidée recommence à la vague 1 de toute façon.
- **Clé** :
  - *Pas de clé* ;
  - *Clé quand la salle est vidée* : apparaît sur la case **k** (ou au centre) ;
  - *Coffre dès l'arrivée* : le coffre est sur la case **C**, il s'ouvre quand
	on le touche et donne une clé ;
  - *Coffre quand la salle est vidée* : le coffre n'apparaît qu'à la fin.
- **Pause entre deux vagues** : en secondes.
- **Ouvrir dans l'inspecteur** : pour les réglages avancés (nombre d'ennemis
  placés au hasard, piliers en couronne…).

Chaque porte verrouillée consomme une clé. Vérifie qu'on peut récupérer chaque
clé **sans** passer par la porte qu'elle ouvre.

---

## 6. Recette rapide : ajouter une salle de combat au nord du départ

1. Clique sur le nœud **Dungeon** → onglet **Donjon**.
2. Sur la carte, clic gauche sur la case `+` **au-dessus** de la salle de départ.
3. Clique sur le trait entre les deux salles : il devient **jaune** (porte ouverte).
4. La nouvelle salle est sélectionnée à droite.
5. Calque **Décor**, outil **P Bloc** : pose 4 blocs autour du centre.
   Outil **k Clé** : clique au centre.
6. **+ Vague** → outil **s Tireur** : deux tireurs en haut de la salle.
7. **+ Vague** → outil **m Corps à corps** : trois ennemis au milieu.
8. Choisis **Clé quand la salle est vidée** (les portes se fermeront
   d'elles-mêmes pendant le combat).
9. **Ctrl+S** pour sauvegarder la scène, puis **F6** pour la lancer.

---

## 7. Caméra

Sur le **CameraRig** :

- **Rotation** `(-50, 0, 0)` : `-50` = inclinaison (vers `-90` = plus de dessus,
  vers `-30` = plus de face) ; `0` = salles droites (`45` = diagonale).
- **Size Normal** / **Size Sprint** : le zoom, puisque la caméra est
  orthographique. Plus petit = plus proche du joueur.
- **Bounds Margin** : de combien la caméra s'approche des murs. Elle suit le
  joueur sans sortir de la salle. Une marge d'au moins la moitié de la salle
  (10 pour une salle de 20 × 20) donne une caméra fixe au centre, comme sur NES.

Les commandes du joueur suivent l'angle de la caméra : haut sur le stick = haut
de l'écran.

---

## Bon à savoir

- **Taille des salles** : groupe **Dimensions** du Dungeon (toutes les salles
  ont la même taille). Si tu la changes, la grille des salles change aussi
  (une case = 2 m) : redessine les salles concernées.
- À la mort, la scène est rechargée : clés, portes ouvertes et salles vidées
  sont remises à zéro, et le joueur réapparaît dans la salle de départ ou au
  dernier `checkpoint` franchi.
- Tout le donjon est construit au démarrage, mais seule la salle où se trouve
  le joueur est dessinée et a des ennemis : ajouter des salles coûte très peu.
- Les avertissements (lettre inconnue, scène d'ennemi manquante…) s'affichent
  dans la console **Sortie** de Godot.

---

## Annexe : anciens donjons avec des lettres

Avant, la carte était un texte où chaque lettre renvoyait à une salle partagée
(toutes les `C` avaient le même contenu). Quand tu sélectionnes un Dungeon
dans cet ancien format, le panneau le **convertit automatiquement** : chaque
case reçoit sa propre copie de sa salle, et plus rien n'est partagé
(Ctrl+Z pour annuler). Les fichiers de `data/dungeon/` ne sont alors plus
utilisés par ce donjon.

Les grilles **Layout** et **Waves** d'une salle restent visibles dans
l'inspecteur (un caractère par case de 2 m, `.` = vide), mais le panneau les
écrit pour toi.
