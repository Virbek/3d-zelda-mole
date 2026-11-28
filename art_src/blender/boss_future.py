# Boss « poings-blocs », version robot RÉTRO-FUTUR années 60 (concept, 3e jet).
#
#   blender -b -P art_src/blender/boss_future.py
#
# Produit art_src/blender/boss_future.blend et Asset/Model/Concept/boss_future.glb.
#
# Même silhouette et mêmes cotes que Script/enemy/boss_robot_model.gd :
# petite tête ronde à deux yeux qui dépasse d'un grand corps (le col cache le
# bas de la tête), deux bras identiques qui pendent jusqu'au sol, gros poings,
# réacteur à chaque coude.
#
# Jets rejetés : 1) œuf blanc + visière (« EVE »), 2) armure anguleuse
# (« Gundam »). Choix de l'utilisateur : le futur vu par les années 60 —
# métal brossé arrondi, hublot, voyants, antennes à boule, ailettes de fusée,
# bras en accordéon, gros yeux ronds.
#
# Nœuds : Head, Arm_L / Arm_R (pivots d'épaule, bras vers -Y), Flame_L / Flame_R
# Matériaux toon : alu, alu_dark, cream, teal, rubber, glass
# Matériaux lumineux : cyan, bulb

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from toonkit import *  # noqa: E402,F401,F403
import toonkit  # noqa: E402
from mathutils import Vector  # noqa: E402

toonkit.PREVIEW.update({
    "alu": "#9aa3aa", "alu_dark": "#6c747a", "cream": "#e2cfa0", "teal": "#2f8a8a",
    "rubber": "#2a2c2e", "glass": "#244a52", "cyan": "#5fe1ff", "bulb": "#fff0b8",
})
toonkit.SMOOTH = True

SHOULDER = (0.98, 2.2, 0.0)
ARM_LEN = 2.0


def ring(name, y, r, h, mat, parent, segs=32):
    """Anneau chromé autour du corps (profil arrondi)."""
    prof = [(r - 0.03, y - h / 2), (r, y - h / 2 + 0.01), (r + 0.015, y), (r, y + h / 2 - 0.01), (r - 0.03, y + h / 2)]
    return finish(name, lathe(prof, segs, closed=True), [mat], parent)


def build_body(root) -> None:
    # Corps-obus : base étroite, ventre large, épaules arrondies
    key = [(0.44, 0.52), (0.62, 0.7), (0.76, 1.0), (0.82, 1.4), (0.82, 1.8), (0.77, 2.1), (0.66, 2.3)]
    prof = [(0.0, 0.5)]
    for (r0, y0), (r1, y1) in zip(key, key[1:]):
        for i in range(4):
            t = i / 4
            prof.append((r0 + (r1 - r0) * t, y0 + (y1 - y0) * t))
    prof += [key[-1], (0.0, 2.32)]
    bm = lathe(prof, 32)
    # Bande crème sur le ventre (deux tons, très années 60)
    for f in bm.faces:
        y = f.calc_center_median().z
        f.material_index = 1 if 1.0 < y < 1.32 else 0
    finish("B_body", bm, ["alu", "cream"], root)
    ring("B_band_low", 0.98, 0.765, 0.06, "alu_dark", root)
    ring("B_band_high", 2.02, 0.79, 0.06, "alu_dark", root)

    # Hublot sur la poitrine : cerclage, vitre sombre, tubes cyan derrière
    disk("B_porthole_rim", (0.0, 1.66, -0.8), (0.0, 0.0, -1.0), 0.27, 0.08, "alu_dark", root, 24)
    disk("B_porthole_glass", (0.0, 1.66, -0.84), (0.0, 0.0, -1.0), 0.21, 0.02, "glass", root, 24)
    for x in (-0.09, 0.0, 0.09):
        limb(f"B_tube_{x:+.2f}", (x, 1.53, -0.855), (x, 1.79, -0.855), 0.022, "cyan", root, 8)
    for i in range(8):
        a = 2 * math.pi * i / 8
        disk(f"B_rivet_{i}", (math.cos(a) * 0.245, 1.66 + math.sin(a) * 0.245, -0.85), (0.0, 0.0, -1.0),
             0.018, 0.02, "alu", root, 8)
    # Rangée de voyants sur la bande crème
    for i in range(5):
        x = -0.3 + 0.15 * i
        a = math.asin(x / 0.8)
        r = 0.81
        disk(f"B_light_rim_{i}", (math.sin(a) * r, 1.16, -math.cos(a) * r), (math.sin(a), 0.0, -math.cos(a)),
             0.045, 0.04, "alu_dark", root, 12)
        blob(f"B_light_{i}", (math.sin(a) * (r + 0.025), 1.16, -math.cos(a) * (r + 0.025)), (0.03, 0.03, 0.03),
             "cyan" if i % 2 == 0 else "bulb", root, 10, 6)
    # Grille de haut-parleur sous les voyants
    for i in range(4):
        y = 0.82 - 0.06 * i
        rr = 0.73 - 0.04 * i
        finish(f"B_grille_{i}", lathe([(rr + 0.012, y - 0.012), (rr + 0.022, y), (rr + 0.012, y + 0.012)], 8,
                                       closed=True, a0=-28, a1=28), ["alu_dark"], root)

    # Trois ailettes de fusée qui posent l'engin au sol + tuyère
    for i in range(3):
        a = 2 * math.pi * i / 3 + math.pi / 3
        fin = blob(f"B_fin_{i}", (0.0, 0.0, 0.0), (0.05, 0.36, 0.26), "teal", root, 12, 8,
                   boxy((0.05, 0.36, 0.26), 0.7))
        fin.location = g(math.sin(a) * 0.62, 0.36, -math.cos(a) * 0.62)
        fin.rotation_euler = (0.0, 0.0, -a)
    cone("B_nozzle", (0.0, 0.52, 0.0), (0.0, 0.28, 0.0), 0.3, "alu_dark", root, 20)
    disk("B_nozzle_glow", (0.0, 0.3, 0.0), (0.0, 1.0, 0.0), 0.16, 0.02, "cyan", root, 16)

    # Col chromé évasé qui cache le bas de la tête
    finish("B_collar", lathe([(0.45, 2.26), (0.72, 2.28), (0.8, 2.4), (0.74, 2.46), (0.45, 2.46)], 32, closed=True),
           ["alu_dark"], root)


def build_head(root) -> None:
    head = empty("Head", g(0.0, 2.55, -0.05), root)
    blob("B_dome", (0.0, 0.0, 0.0), (0.42, 0.4, 0.42), "alu", head, 24, 14)
    ring("B_head_band", 0.04, 0.425, 0.05, "teal", head, 28)
    # Gros yeux ronds : lampes cerclées de chrome
    for x in (-0.15, 0.15):
        a = math.asin(x / 0.42)
        r = 0.4
        c = (math.sin(a) * r, 0.14, -math.cos(a) * r)
        n = (math.sin(a), 0.15, -math.cos(a))
        disk(f"B_eye_rim_{x:+.2f}", c, n, 0.1, 0.06, "alu_dark", head, 18)
        blob(f"B_eye_{x:+.2f}", (c[0] + n[0] * 0.035, c[1] + 0.005, c[2] + n[2] * 0.035), (0.075, 0.075, 0.03),
             "bulb", head, 14, 8)
    # Bouche-grille
    for i in range(3):
        y = -0.06 - 0.045 * i
        limb(f"B_mouth_{i}", (-0.1, y, -0.4), (0.1, y, -0.4), 0.012, "alu_dark", head, 6)
    # Oreilles-disques et antennes à boule
    for side in (-1.0, 1.0):
        disk(f"B_ear_{side:+.0f}", (0.42 * side, 0.05, 0.0), (1.0, 0.0, 0.0), 0.12, 0.08, "teal", head, 16)
        limb(f"B_antenna_{side:+.0f}", (0.43 * side, 0.12, 0.0), (0.6 * side, 0.55, 0.05), 0.012, "alu_dark", head, 6)
        blob(f"B_antenna_ball_{side:+.0f}", (0.61 * side, 0.57, 0.05), (0.04, 0.04, 0.04), "cyan", head, 10, 6)
    # Petite parabole sur le dessus
    cone("B_dish_stem", (0.0, 0.36, 0.0), (0.0, 0.5, 0.0), 0.03, "alu_dark", head, 8)
    disk("B_dish", (0.0, 0.5, 0.0), (0.0, 1.0, -0.3), 0.12, 0.02, "alu", head, 16)


def build_arm(root, side: float) -> None:
    s = "L" if side < 0 else "R"
    arm = empty(f"Arm_{s}", g(SHOULDER[0] * side, SHOULDER[1], SHOULDER[2]), root)
    # Épaule : boule chromée cerclée
    blob(f"B{s}_shoulder", (0.0, 0.0, 0.0), (0.28, 0.28, 0.28), "alu", arm, 18, 12)
    disk(f"B{s}_shoulder_band", (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), 0.29, 0.06, "teal", arm, 20)
    # Bras en accordéon : anneaux alternés caoutchouc / alu
    n = 14
    for i in range(n):
        y0 = -0.24 - (1.22 / n) * i
        mat = "rubber" if i % 2 == 0 else "alu_dark"
        rad = 0.17 if i % 2 == 0 else 0.2
        disk(f"B{s}_rib_{i}", (0.0, y0 - 0.044, 0.0), (0.0, 1.0, 0.0), rad, 1.22 / n, mat, arm, 16)
    # Fusée de coude, avec ses ailettes
    rocket_c = (0.24 * side, -0.82, 0.18)
    limb(f"B{s}_rocket", (rocket_c[0], rocket_c[1] + 0.15, rocket_c[2] - 0.08),
         (rocket_c[0], rocket_c[1] - 0.12, rocket_c[2] + 0.1), 0.08, "teal", arm, 12)
    cone(f"B{s}_rocket_nozzle", (rocket_c[0], rocket_c[1] - 0.1, rocket_c[2] + 0.09),
         (rocket_c[0], rocket_c[1] - 0.2, rocket_c[2] + 0.16), 0.07, "alu_dark", arm, 10)
    disk(f"B{s}_rocket_glow", (rocket_c[0], rocket_c[1] - 0.2, rocket_c[2] + 0.165), (0.0, -0.6, 0.8),
         0.05, 0.02, "cyan", arm, 10)
    # Poignet chromé, gros poing-boule avec cerclage et trois plots
    disk(f"B{s}_wrist", (0.0, -1.5, 0.0), (0.0, 1.0, 0.0), 0.24, 0.08, "alu_dark", arm, 20)
    wrist = -ARM_LEN + 0.42
    blob(f"B{s}_fist", (0.0, wrist, 0.0), (0.36, 0.32, 0.36), "alu", arm, 22, 14)
    disk(f"B{s}_fist_band", (0.0, wrist, 0.0), (0.0, 1.0, 0.0), 0.365, 0.07, "teal", arm, 24)
    for i in range(3):
        z = -0.18 + 0.18 * i
        blob(f"B{s}_stud_{i}", (0.0, wrist - 0.3, z), (0.07, 0.05, 0.07), "alu_dark", arm, 10, 6)
    empty(f"Flame_{s}", g(0.0, wrist - 0.43, 0.0), arm)


def build() -> None:
    reset_scene()
    root = empty("BossFuture", Vector((0, 0, 0)))
    build_body(root)
    build_head(root)
    for side in (-1.0, 1.0):
        build_arm(root, side)
    save_and_export("art_src/blender/boss_future.blend", "Asset/Model/Concept/boss_future.glb")


build()
