# Sons à trouver

Déposer les fichiers dans `audio/sfx/` en `.wav` ou `.ogg`. **Le nom du fichier est la clé** :
`dodge.wav` → `Sfx.play("dodge", …)`. Le gestionnaire varie déjà la hauteur de ±12 % à chaque
lecture, un seul échantillon par son suffit.

Conseils : sons courts (< 0,5 s sauf jingles), attaque franche, pas de silence en début de fichier.

Colonne **Branché** : ✅ = le code joue déjà ce son dès que le fichier existe · ❌ = l'appel reste à ajouter.

## Priorité 1 — combat (entendu à chaque seconde)

| Fichier | Moment | Ambiance | Branché |
|---|---|---|---|
| `hit_light` | Coup du combo, toupie | Impact sec, mat (coup de poing dans un sac) | ✅ (présent) |
| `hit_heavy` | Poing chargé, finisher | Impact grave + craquement, plus long | ✅ |
| `swing` | Départ de chaque coup du combo (même dans le vide) | Whoosh court et aigu | ✅ (présent) |
| `dodge` | Début de l'esquive | Whoosh/froissement rapide | ❌ |
| `player_hurt` | Le joueur prend un coup | Choc + petit cri ou grognement | ✅ (présent) |
| `enemy_death` | Mort d'un ennemi | « Pop » / dégonflement cartoon | ✅ (présent) |
| `stun` | Un ennemi devient étourdi | Petites étoiles / cloche « tiiing » | ✅ (présent) |

## Priorité 2 — attaques spéciales

| Fichier | Moment | Ambiance | Branché |
|---|---|---|---|
| `charge_start` | Début de la charge du poing | Montée électrique ou ressort qu'on tend | ❌ |
| `charge_full` | Charge au maximum (avec le flash) | « Ting » clair et brillant | ❌ |
| `punch_launch` | Le poing chargé part | Whoosh puissant, grave | ❌ |
| `spin` | Toupie (boucle pendant 1,6 s) | Tourbillon d'air | ❌ |

## Priorité 3 — ennemis

| Fichier | Moment | Ambiance | Branché |
|---|---|---|---|
| `enemy_telegraph` | Chargeur / mêlée qui prépare son attaque | Grognement ou raclement, bien lisible | ❌ |
| `enemy_charge` | Le chargeur fonce | Galop / ruée | ❌ |
| `shoot` | Le tireur tire | « Pew » ou crachat | ✅ (présent) |
| `projectile_hit` | Un projectile touche ou s'écrase | Petit splash / éclat | ❌ |
| `bomber_fuse` | Le kamikaze s'amorce | Mèche qui grésille | ❌ |
| `explosion` | Explosion du kamikaze | Boum cartoon | ✅ (présent) |
| `boss_land` | Atterrissage du boss | Impact très grave | ✅ (présent) |
| `boss_phase` | Le boss change de phase | Rugissement | ❌ |
| `spawn` | Un ennemi apparaît (fin de l'annonce au sol) | « Pouf » magique, court | ✅ |

## Priorité 4 — donjon et interface

| Fichier | Moment | Ambiance | Branché |
|---|---|---|---|
| `room_clear` | Dernier ennemi de la salle (avec le ralenti) | Petit jingle de victoire (1–2 s) | ❌ |
| `door_open` / `door_close` | Portes de salle | Pierre qui glisse | ❌ |
| `key_pickup` | Ramasser une clé | Jingle court, brillant | ❌ |
| `chest_open` | Ouvrir un coffre | Grincement + révélation | ❌ |
| `heal` | Soin ramassé ou PV regagné en frappant | Note montante douce | ❌ |
| `checkpoint` | Checkpoint activé | Carillon | ❌ |
| `player_death` | Mort du joueur | Chute / note descendante | ❌ |

## Optionnel

| Fichier | Moment | Ambiance |
|---|---|---|
| `footstep` | Retiré à la demande : fichier présent mais non joué | — |
