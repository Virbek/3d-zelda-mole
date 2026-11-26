# Prompts ElevenLabs (Sound Effects)

Le nom du fichier devient la clé du son : `chest_open.wav` donne `Sfx.play("chest_open", ...)`.
Il suffit de déposer le fichier dans `res://audio/sfx/`.

**Réglages par défaut :** durée la plus courte possible (0.5 à 1 s), *Prompt influence* entre 70 et 80 %.
**Suffixe à ajouter à chaque prompt :**

```
, dry, no reverb, no background noise, isolated game sound effect
```

La réverbération est ajoutée dans Godot (bus audio). Si ElevenLabs génère plusieurs sons d'affilée, ajoute `one single hit only`.
Pour un rendu plus toon : ajoute `slightly exaggerated, punchy, stylized`.

---

## 1. Sons manquants (déjà appelés par le code)

| Fichier | Où | Prompt |
|---|---|---|
| `spawn.wav` | apparition d'un ennemi ou d'un coffre | `Sand bursting up from the ground, short gritty whoosh with a mechanical clunk as something emerges` |
| `chest_open.wav` | ouverture du coffre | `Heavy rusty metal crate lid creaking open, latch clank, sand pouring off the lid` |
| `item_get.wav` | objet obtenu (UI) | `Short bright triumphant jingle, metallic chimes and a warm synth swell, 1.5 seconds, item acquired fanfare` |

## 2. Joueur

| Fichier | Prompt |
|---|---|
| `step_1/2/3.wav` | `Single footstep, heavy mechanical boot on a thin layer of sand over hard concrete, soft gritty crunch with a faint metal clink` |
| `swing.wav` | `Single fast punch whoosh, metal fist swinging through air, short sharp swoosh with faint servo whir, no impact` |
| `swing_off.wav` | `Short weak air swoosh, punch missing, light and quick, no impact` |
| `punch_1.wav` | `Single quick jab, metal gauntlet hitting a hard insect shell, snappy thump with light metallic click` |
| `punch_2.wav` | `Single solid hook punch, metal gauntlet hitting chitin, meaty thud with metallic rattle` |
| `punch_3.wav` | `Single heavy punch, mechanical gauntlet cracking a hard insect carapace, crunchy crack with deep thud` |
| `hit_light.wav` | `Single light impact, metal knuckles tapping a hard shell, short dull knock` |
| `hit_heavy.wav` | `Single massive punch impact, mechanical gauntlet slam, deep bass boom with metal crunch and hydraulic hiss` |
| `player_hurt.wav` | `Short pained grunt of a young adventurer getting hit, with metal armor rattle` |
| `player_dodge.wav` | `Quick dodge roll in sand, fast whoosh and gritty slide, cloth rustle` |
| `charge_loop.wav` *(boucle)* | `Mechanical gauntlet charging up, rising electric whine and humming servo, building energy, seamless loop` |
| `charge_release.wav` | `Charged punch release, electric discharge snap with a powerful air burst` |
| `slam.wav` | `Fists slamming into sandy ground, heavy earth thud, sand explosion and debris scatter` |
| `player_death.wav` | `Adventurer collapsing on sand, final exhausted grunt, metal gear clattering on the ground` |
| `heal.wav` | `Short warm healing chime, soft rising sparkle with a gentle hum` |

## 3. Ennemis

| Fichier | Prompt |
|---|---|
| `beetle_windup.wav` | `Giant stag beetle opening its mandibles, chitin creaking and clicking, threatening hiss` |
| `beetle_snap.wav` | `Giant beetle mandibles snapping shut, sharp hard chitin clack, fast and violent` |
| `hornet_shoot.wav` | `Giant hornet spitting a venom projectile, wet quick spit with a short buzzing burst` |
| `hornet_buzz.wav` *(boucle)* | `Giant hornet wings buzzing, low aggressive insect drone, seamless loop` |
| `shoot.wav` | `Small organic projectile launch, wet pop with a whistle` |
| `projectile_hit.wav` | `Venom glob splattering on stone, wet splat with a fizz` |
| `bomber_fuse.wav` | `Swollen insect about to burst, fast rising chittering and bubbling hiss, ticking tension` |
| `explosion.wav` | `Bloated insect bursting in an explosion, wet organic pop followed by a sandy blast boom` |
| `stun.wav` | `Insect stunned, dizzy chirping and chitin rattle, short wobbling tone` |
| `enemy_death.wav` | `Giant insect dying, final screech and shell cracking, body collapsing on sand` |

## 4. Boss

| Fichier | Prompt |
|---|---|
| `boss_windup.wav` | `Huge mechanical creature crouching before a leap, hydraulic pressure building, deep grinding gears and steam hiss` |
| `boss_jump.wav` | `Giant heavy creature launching into the air, powerful hydraulic burst and whoosh` |
| `boss_land.wav` | `Massive creature landing on sandy ground, huge earth-shaking boom, metal clang and sand shockwave` |
| `boss_hurt.wav` | `Giant creature roaring in pain, distorted insect screech mixed with metal grinding` |
| `boss_phase.wav` | `Monster enraged, loud furious roar with mechanical overload alarm and steam blast` |
| `boss_death.wav` | `Giant mechanical insect dying, long fading screech, metal collapsing and sparks crackling, 3 seconds` |

## 5. Donjon et objets

| Fichier | Prompt |
|---|---|
| `door_open.wav` | `Heavy rusty metal sliding door opening, grinding gears and sand falling from the frame` |
| `door_close.wav` | `Heavy metal door slamming shut, deep clang and dust` |
| `door_unlock.wav` | `Old mechanical lock unlocking with a key, heavy clunk, gears turning, satisfying click` |
| `door_deny.wav` | `Locked metal door rattling, short dull clunk, access denied` |
| `key_pickup.wav` | `Picking up a small metal key, bright jingle with a short sparkle` |
| `health_pickup.wav` | `Small energy orb collected, soft bright blip with a gentle chime` |
| `checkpoint.wav` | `Old machine powering on, electric hum rising with a soft confirmation beep` |
| `room_clear.wav` | `Short victory sting, metallic chimes and warm synth chord, 1.5 seconds` |

## 6. Interface

| Fichier | Prompt |
|---|---|
| `ui_move.wav` | `Tiny soft mechanical click, menu cursor move` |
| `ui_confirm.wav` | `Short satisfying mechanical button press with a bright beep` |
| `ui_back.wav` | `Short low soft click, menu cancel` |
| `pause.wav` | `Soft muffled whoosh down, game paused` |
| `game_over.wav` | `Sad slow descending synth tones with a distant metallic echo, 3 seconds` |

## 7. Ambiance (boucles longues)

Durée maximale (22 s), à mettre sur un `AudioStreamPlayer` en boucle, hors du `Sfx`.

| Fichier | Prompt |
|---|---|
| `amb_refinery.wav` | `Underground abandoned refinery buried in sand, low wind through cracks, distant metal creaks, faint dripping, sand trickling, eerie calm, seamless loop` |
| `amb_machines.wav` | `Distant old machinery humming deep underground, slow rhythmic clanking, faint steam hiss, seamless loop` |
| `amb_insects.wav` | `Distant giant insects chittering and scratching in the dark, sparse and unsettling, seamless loop` |

---

Tous ces sons sont branchés dans le code. Tant qu'un fichier manque, son événement reste simplement muet. *(boucle)* = le son est rejoué en continu : génère-le avec `seamless loop`.
