# Boss robot « poings-blocs » (concept d'origine, croquis du 2026-11-25),
# refait dans Blender : mêmes pièces et mêmes cotes que la version en
# primitives (Script/enemy/boss_robot_model.gd), en formes arrondies.
#
#   blender -b -P art_src/blender/boss.py
#
# Produit art_src/blender/boss.blend et Asset/Model/Enemy/boss.glb.
#
# Silhouette : petite tête en dôme qui dépasse d'un grand corps-chaudière
# rouillé (le col cache le bas de la tête), deux bras identiques qui pendent
# jusqu'au sol, gros poings-blocs, réacteur à chaque coude, cheminées dans le
# dos, manomètre sur la poitrine, bande de danger à rayures.
#
# Nœuds pilotés par le script du boss :
#   Head, Arm_L / Arm_R (pivots d'épaule, bras vers -Y),
#   Flame_L / Flame_R (sous les poings)
# Matériaux toon : rust, rust_dark, rust_light, steel, steel_dark, steel_light,
#   hazard, hazard_dark, cream, needle
# Matériaux lumineux (couleur pilotée par le jeu) : eye, nozzle

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from toonkit import *  # noqa: E402,F401,F403
import toonkit  # noqa: E402
from mathutils import Vector  # noqa: E402

toonkit.PREVIEW.update({
    "rust": "#a8622f", "rust_dark": "#6e3a1e", "rust_light": "#c07a42",
    "steel": "#8a8d8f", "steel_dark": "#4a4c4b", "steel_light": "#c7c7cc",
    "hazard": "#e0a23a", "hazard_dark": "#2a2420", "cream": "#e8dcc0",
    "needle": "#ff7a2a", "eye": "#5fe1ff", "nozzle": "#5fe1ff",
})
toonkit.SMOOTH = True

SHOULDER = (0.98, 2.2, 0.0)
ARM_LEN = 2.0
WRIST = -ARM_LEN + 0.42


def rounded(name, center, half, mat, parent, power=0.5, segs=14, rings=10):
    return blob(name, center, half, mat, parent, segs, rings, boxy(half, power))


def stripes(bm, period: float = 0.42, slant: float = 1.0) -> None:
    """Rayures de danger en biais : une face sur deux en hazard_dark (index 1)."""
    for f in bm.faces:
        c = f.calc_center_median()
        a = math.atan2(c.x, c.y)
        u = a * 0.8 + c.z * slant          # angle (le long du tour) + hauteur
        f.material_index = 1 if int(math.floor(u / period)) % 2 else 0


def band(name, y, r_in, r_out, h, parent, segs=48, rings=6) -> None:
    """Anneau à rayures de danger, finement découpé pour que les rayures suivent."""
    prof = [(r_in, y - h / 2)]
    for i in range(rings + 1):
        prof.append((r_out, y - h / 2 + h * i / rings))
    prof.append((r_in, y + h / 2))
    bm = lathe(prof, segs, closed=True)
    stripes(bm)
    finish(name, bm, ["hazard", "hazard_dark"], parent)


# ------------------------------------------------------------------ CORPS

def boiler_r(y: float) -> float:
    """Rayon de la chaudière : 0.66 en bas, 0.78 en haut, léger ventre."""
    t = min(1.0, max(0.0, (y - 0.4) / 2.0))
    return 0.66 + 0.12 * t + 0.03 * math.sin(math.pi * t)


def build_body(root) -> None:
    # Chaudière : tonneau arrondi, bords supérieurs adoucis
    prof = [(0.0, 0.42)]
    for i in range(17):
        y = 0.42 + (2.3 - 0.42) * i / 16
        prof.append((boiler_r(y), y))
    prof += [(boiler_r(2.38) - 0.04, 2.38), (0.0, 2.4)]
    finish("Boiler", lathe(prof, 28), ["rust"], root)

    # Jupe de base : anneau sombre avec rebord
    finish("Skirt", lathe([(0.62, 0.2), (0.74, 0.22), (0.77, 0.34), (0.74, 0.5), (0.62, 0.52)], 28, closed=True),
           ["rust_dark"], root)

    # Bande de danger à rayures autour du ventre
    band("Hazard_band", 1.45, boiler_r(1.45) - 0.02, boiler_r(1.45) + 0.03, 0.2, root)

    # Col épais qui cache le bas de la tête
    finish("Collar", lathe([(0.5, 2.22), (0.82, 2.24), (0.87, 2.36), (0.84, 2.48), (0.5, 2.5)], 28, closed=True),
           ["rust_dark"], root)

    # Rivets en dôme, sur deux rangées
    for row in (0.78, 2.05):
        r = boiler_r(row) + 0.005
        for i in range(12):
            a = 2.0 * math.pi * i / 12 + 0.13
            blob(f"Rivet_{row}_{i}", (math.sin(a) * r, row, -math.cos(a) * r), (0.04, 0.04, 0.04),
                 "steel_dark", root, 8, 5)

    # Pièces soudées : deux plaques plus claires, une bosse
    for name, a_deg, y, hw, hh in (("Patch_a", 48.0, 1.05, 0.18, 0.14), ("Patch_b", -125.0, 1.85, 0.14, 0.18)):
        a = math.radians(a_deg)
        r = boiler_r(y)
        span = math.degrees(hw / r)
        patch = [(boiler_r(yy) + 0.012, yy) for yy in (y - hh, y - hh / 2, y, y + hh / 2, y + hh)]
        finish(name, lathe(patch, 4, a0=a_deg - span, a1=a_deg + span), ["rust_light"], root)
        for k, (da, dy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
            aa = a + math.radians(span * 0.8 * da)
            yy = y + hh * 0.75 * dy
            blob(f"{name}_bolt_{k}", (math.sin(aa) * (r + 0.02), yy, -math.cos(aa) * (r + 0.02)),
                 (0.022, 0.022, 0.022), "steel_dark", root, 6, 4)

    # Manomètre sur la poitrine
    gy, gz = 1.9, -(boiler_r(1.9) + 0.02)
    disk("Gauge_bezel", (0.0, gy, gz), (0.0, 0.0, -1.0), 0.25, 0.1, "steel_dark", root, 20)
    disk("Gauge_dial", (0.0, gy, gz - 0.045), (0.0, 0.0, -1.0), 0.19, 0.02, "cream", root, 20)
    for i in range(7):
        a = math.radians(-120 + 40 * i)
        rounded(f"Gauge_tick_{i}", (math.sin(a) * 0.15, gy + math.cos(a) * 0.15, gz - 0.058),
                (0.008, 0.025, 0.004), "steel_dark", root, 0.4, 6, 4)
    needle = rounded("Gauge_needle", (0.0, 0.0, 0.0), (0.012, 0.09, 0.006), "needle", root, 0.4, 6, 4)
    needle.location = g(0.04, gy + 0.05, gz - 0.065)
    needle.rotation_euler = (0.0, math.radians(35.0), 0.0)
    blob("Gauge_hub", (0.0, gy, gz - 0.06), (0.025, 0.025, 0.015), "steel_dark", root, 8, 4)

    # Cheminées dans le dos, avec chapeau et collier
    for x in (-0.35, 0.35):
        disk(f"Chimney_{x:+.2f}", (x, 2.42, 0.62), (0.0, 1.0, 0.0), 0.1, 0.7, "steel_dark", root, 14)
        disk(f"Chimney_cap_{x:+.2f}", (x, 2.79, 0.62), (0.0, 1.0, 0.0), 0.135, 0.06, "rust_dark", root, 14)
        disk(f"Chimney_ring_{x:+.2f}", (x, 2.2, 0.62), (0.0, 1.0, 0.0), 0.12, 0.05, "steel", root, 14)


def build_head(root) -> None:
    head = empty("Head", g(0.0, 2.48, -0.05), root)
    blob("Dome", (0.0, 0.0, 0.0), (0.44, 0.44, 0.44), "steel", head, 22, 14)
    # Deux yeux en fentes arrondies, inclinés vers le bas comme sur le croquis
    for x in (-0.15, 0.15):
        a = math.asin(x / 0.44)
        r = 0.44 * math.sqrt(1.0 - (0.17 / 0.44) ** 2) + 0.004
        eye = rounded(f"Eye_{x:+.2f}", (0.0, 0.0, 0.0), (0.075, 0.045, 0.02), "eye", head, 0.45, 10, 6)
        eye.location = g(math.sin(a) * r, 0.17, -math.cos(a) * r)
        eye.rotation_euler = (math.radians(-15.0), 0.0, -a)
    # Boulons de part et d'autre
    for side in (-1.0, 1.0):
        disk(f"Head_bolt_{side:+.0f}", (0.43 * side, 0.02, 0.0), (1.0, 0.0, 0.0), 0.06, 0.05, "steel_dark", head, 10)


# ------------------------------------------------------------------ BRAS

def build_arm(root, side: float) -> None:
    s = "L" if side < 0 else "R"
    arm = empty(f"Arm_{s}", g(SHOULDER[0] * side, SHOULDER[1], SHOULDER[2]), root)

    # Épaule : gros moyeu couché le long de X, flasques
    disk(f"{s}_hub", (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), 0.3, 0.34, "steel_dark", arm, 20)
    for x in (-0.18, 0.18):
        disk(f"{s}_hub_cap_{x:+.2f}", (x, 0.0, 0.0), (1.0, 0.0, 0.0), 0.2, 0.04, "steel", arm, 16)

    # Bras : poutre rouillée aux arêtes arrondies
    rounded(f"{s}_beam", (0.0, -0.8, 0.0), (0.21, 0.725, 0.21), "rust_dark", arm, 0.35)
    for y in (-0.25, -1.35):
        for x in (-0.12, 0.12):
            blob(f"{s}_beam_rivet_{y}_{x:+.2f}", (x, y, -0.215), (0.03, 0.03, 0.02), "steel_dark", arm, 6, 4)

    # Vérin d'acier sur l'avant : tige + corps + attaches
    disk(f"{s}_rod", (0.0, -0.75, -0.25), (0.0, 1.0, 0.0), 0.06, 1.1, "steel_light", arm, 12)
    disk(f"{s}_sleeve", (0.0, -0.3, -0.25), (0.0, 1.0, 0.0), 0.095, 0.32, "steel_dark", arm, 12)
    for y in (-0.16, -1.28):
        rounded(f"{s}_clamp_{y}", (0.0, y, -0.23), (0.08, 0.035, 0.06), "steel", arm, 0.4, 8, 6)

    # Réacteur au coude, tourné vers l'arrière et l'extérieur
    n = (0.45 * side, -0.55, 0.7)
    base = (0.16 * side, -0.62, 0.15)
    tip = (base[0] + n[0] * 0.3, base[1] + n[1] * 0.3, base[2] + n[2] * 0.3)
    cone(f"{s}_nozzle_body", tip, base, 0.15, "steel_dark", arm, 16)
    disk(f"{s}_nozzle_ring", tip, n, 0.16, 0.05, "rust_dark", arm, 16)
    core = (tip[0] + n[0] * 0.02, tip[1] + n[1] * 0.02, tip[2] + n[2] * 0.02)
    disk(f"Nozzle_{s}", core, n, 0.1, 0.02, "nozzle", arm, 16)

    # Poing-bloc : collier à rayures, bloc d'acier arrondi, trois barres de jointures
    collar = rounded(f"{s}_cuff", (0.0, WRIST + 0.32, 0.0), (0.26, 0.085, 0.26), "hazard", arm, 0.35, 32, 10)
    import bmesh
    me = collar.data
    bm = bmesh.new()
    bm.from_mesh(me)
    stripes(bm, 0.36, 2.0)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(toonkit.material("hazard_dark"))
    rounded(f"{s}_fist", (0.0, WRIST, 0.0), (0.36, 0.3, 0.36), "steel", arm, 0.3, 16, 12)
    for i in range(3):
        z = -0.22 + 0.22 * i
        rounded(f"{s}_knuckle_{i}", (0.0, WRIST - 0.33, z), (0.31, 0.07, 0.085), "steel_light", arm, 0.4)
    for x in (-0.37, 0.37):
        for y in (-0.12, 0.12):
            blob(f"{s}_fist_bolt_{x:+.2f}_{y:+.2f}", (x, WRIST + y, -0.2), (0.012, 0.03, 0.03), "steel_dark", arm, 6, 4)

    empty(f"Flame_{s}", g(0.0, WRIST - 0.43, 0.0), arm)


def build() -> None:
    reset_scene()
    root = empty("Boss", Vector((0, 0, 0)))
    build_body(root)
    build_head(root)
    for side in (-1.0, 1.0):
        build_arm(root, side)
    save_and_export("art_src/blender/boss.blend", "Asset/Model/Enemy/boss.glb")


build()
