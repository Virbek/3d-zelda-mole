# Instructions du Projet Godot 4 (3D)

## Environnement & Version
- Moteur : Godot 4.x
- Espace : 3D (`Node3D`, `CharacterBody3D`, `RigidBody3D`, `Camera3D`, `MeshInstance3D`)
- Langage : GDScript avec typage statique strict obligatoire.

## Conventions de Code GDScript
- Syntaxe moderne Godot 4 :
  - Annotations : `@export`, `@onready`
  - Signaux : `signal nom_du_signal(valeur: float)`
  - Émission : `nom_du_signal.emit(valeur)`
  - Connexion : `source.nom_du_signal.connect(_on_callback)`
- Toujours typer les variables, paramètres et retours :
  `func calculate_velocity(input_dir: Vector3, delta: float) -> Vector3:`
- Nommage : `snake_case` pour variables/fonctions/fichiers, `PascalCase` pour classes/nœuds, `UPPER_SNAKE` pour constantes.

## Bonnes Pratiques 3D
- Physique et mouvements :
  - Déplacements continus et contrôleurs dans `_physics_process(delta: float)`.
  - Utiliser `CharacterBody3D` avec `move_and_slide()` pour les entités contrôlées.
  - Utiliser les vecteurs et repères globaux/locaux de manière explicite (`global_transform.basis`, `Vector3.UP`).
  - Gérer les collisions avec des formes primitives (`BoxShape3D`, `CapsuleShape3D`, `SphereShape3D`) plutôt que des maillages complexes quand c'est possible.
- Performance :
  - Éviter d'instancier ou de détruire massivement des nœuds 3D à chaque frame.
  - Séparer la logique visuelle (`_process`) de la logique physique (`_physics_process`).

## Architecture & Fichiers
- Règle de communication : les parents contrôlent leurs enfants, les enfants émettent des signaux vers le haut.
- Ne pas modifier manuellement les fichiers `.tscn` textuels pour éviter de corrompre les UIDs et dépendances ; privilégier la logique en script ou la création procédurale de nœuds si nécessaire.
- Structure de base modulaire : séparer le code réutilisable, les données (`Resource`) et les scènes de test.
