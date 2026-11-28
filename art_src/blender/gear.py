# Gantelets et bottes mécaniques de la taupe, version arrondie.
#
#   blender -b -P art_src/blender/gear.py
#
# Produit art_src/blender/gear.blend, Asset/Model/Player/gauntlet.glb et
# Asset/Model/Player/boot.glb. Chaque .glb contient une version gauche (_L)
# et droite (_R) : le pouce et le voyant changent de côté.
#
# Mêmes cotes que Script/player/gauntlet.gd et mech_boot.gd, pour que le rig
# (portée, boîtes de coup, écart au corps) reste valable.
#
# Contrat Godot (ne pas renommer) :
#   Gauntlet_L / Gauntlet_R : racines, avant (jointures) en -Z
#     Fist_L|R : pièces visibles poing fermé seulement
#     Open_L|R : pièces visibles main ouverte seulement
#   Boot_L / Boot_R : racines, origine au sol sous la semelle, avant en -Z
#   Matériaux : rust, rust_dark, steel, steel_dark, steel_light, hazard (toon) ;
#               screen (lumineux)

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from toonkit import *  # noqa: E402,F401,F403
import toonkit  # noqa: E402
from mathutils import Vector  # noqa: E402

toonkit.PREVIEW.update({
    "rust": "#a8622f", "rust_dark": "#6e3a1e", "steel": "#8a8d8f",
    "steel_dark": "#4a4c4b", "steel_light": "#c7c7cc", "hazard": "#e0a23a",
    "screen": "#5fe1ff",
})


HAND_SCALE = 1.05   ## taille de la main (1 = mêmes cotes que gauntlet.gd) ; reporter dans Gauntlet.MODEL_SCALE
BOOT_SCALE = 1.25   ## taille du pied (1 = mêmes cotes que mech_boot.gd) ; reporter dans MechBoot.MODEL_SCALE


def rounded(name, center_g, half_g, mat, parent, power=0.5, segs=14, rings=10):
    """Boîte aux coins ronds (demi-tailles en repère Godot)."""
    return blob(name, center_g, half_g, mat, parent, segs, rings, boxy(half_g, power))


def along_z(name, z0, z1, x, y, radius, mat, parent, segs=14):
    """Cylindre couché le long de Z (l'axe du bras)."""
    return disk(name, (x, y, (z0 + z1) * 0.5), (0.0, 0.0, 1.0), radius, abs(z1 - z0), mat, parent, segs)


def upright(name, x, y0, y1, z, radius, mat, parent, segs=14):
    """Cylindre vertical."""
    return disk(name, (x, (y0 + y1) * 0.5, z), (0.0, 1.0, 0.0), radius, abs(y1 - y0), mat, parent, segs)


# ------------------------------------------------------------------ GANTELET

def build_gauntlet(side: float, at: Vector) -> None:
    s = "L" if side < 0 else "R"
    root = empty(f"Gauntlet_{s}", at)
    # Tout passe sous un pivot réduit : la racine reste à l'échelle 1 pour le rig
    root = empty(f"Hand_{s}", Vector((0, 0, 0)), root)
    root.scale = (HAND_SCALE, HAND_SCALE, HAND_SCALE)
    inner = -side

    # --- Poing : gros bloc rouillé arrondi + plaque de dessus ---
    rounded(f"G{s}_fist", (0.0, 0.0, -0.06), (0.135, 0.1, 0.095), "rust", root, 0.45)
    rounded(f"G{s}_plate", (0.0, 0.1, -0.05), (0.115, 0.022, 0.07), "rust_dark", root, 0.4)

    # --- Poing fermé : une seule rangée de doigts repliés + pouce ---
    fist = empty(f"Fist_{s}", Vector((0, 0, 0)), root)
    for i in range(4):
        x = -0.09 + 0.06 * i
        blob(f"G{s}_knuckle_{i}", (x, -0.005, -0.16), (0.03, 0.075, 0.035), "steel", fist, 10, 8)
    limb(f"G{s}_thumb", (inner * 0.13, -0.035, -0.01), (inner * 0.12, -0.03, -0.13), 0.036, "steel", fist, 10)

    # --- Main ouverte : les mêmes doigts, tendus depuis le bord du poing ---
    opened = empty(f"Open_{s}", Vector((0, 0, 0)), root)
    for i in range(4):
        x = -0.09 + 0.06 * i
        spread = math.radians(-6.0 + 4.0 * i)
        flen = 0.13 if i in (0, 3) else 0.15
        bx, bz = x, -0.14
        kx, kz = bx - math.sin(spread) * flen, bz - math.cos(spread) * flen
        limb(f"G{s}_finger_{i}", (bx, -0.01, bz), (kx, -0.02, kz), 0.03, "steel", opened, 8)
        tx, tz = kx - math.sin(spread) * 0.06, kz - math.cos(spread) * 0.06
        limb(f"G{s}_tip_{i}", (kx, -0.02, kz), (tx, -0.065, tz), 0.027, "steel", opened, 8)
    limb(f"G{s}_thumb_open", (inner * 0.12, -0.03, -0.06), (inner * 0.21, -0.07, -0.17), 0.033, "steel", opened, 10)
    upright(f"G{s}_emitter", 0.0, -0.115, -0.095, -0.06, 0.065, "steel_dark", opened)
    upright(f"G{s}_emitter_core", 0.0, -0.122, -0.11, -0.06, 0.045, "screen", opened)

    # --- Manchette du poignet, bande de danger, collerette ---
    along_z(f"G{s}_cuff", 0.02, 0.2, 0.0, 0.0, 0.125, "steel_dark", root, 16)
    along_z(f"G{s}_hazard", 0.025, 0.06, 0.0, 0.0, 0.133, "hazard", root, 16)
    along_z(f"G{s}_collar", 0.175, 0.205, 0.0, 0.0, 0.142, "rust_dark", root, 16)

    # --- Pistons sur le dessus ---
    for x in (-0.07, 0.07):
        along_z(f"G{s}_piston_{x:+.2f}", -0.06, 0.14, x, 0.12, 0.022, "steel_light", root, 8)
        along_z(f"G{s}_sleeve_{x:+.2f}", 0.09, 0.15, x, 0.12, 0.033, "steel_dark", root, 10)

    # --- Écran cyan sur le poignet ---
    rounded(f"G{s}_screen_box", (0.0, 0.13, 0.13), (0.05, 0.014, 0.04), "steel_dark", root, 0.4, 10, 6)
    rounded(f"G{s}_screen", (0.0, 0.142, 0.13), (0.038, 0.006, 0.028), "screen", root, 0.4, 10, 6)


# ------------------------------------------------------------------ BOTTE

def build_boot(side: float, at: Vector) -> None:
    s = "L" if side < 0 else "R"
    root = empty(f"Boot_{s}", at)
    # Pivot agrandi au sol : la semelle reste posée à y = 0
    root = empty(f"Foot_{s}", Vector((0, 0, 0)), root)
    root.scale = (BOOT_SCALE, BOOT_SCALE, BOOT_SCALE)

    # --- Semelle épaisse + crampons ---
    rounded(f"B{s}_sole", (0.0, 0.03, -0.02), (0.115, 0.028, 0.195), "steel_dark", root, 0.35)
    for z in (-0.14, 0.0, 0.13):
        rounded(f"B{s}_cleat_{z:+.2f}", (0.0, 0.006, z), (0.1, 0.012, 0.026), "steel_dark", root, 0.4, 10, 6)

    # --- Chaussure rouillée, bien ronde, languette ---
    rounded(f"B{s}_shoe", (0.0, 0.11, 0.01), (0.1, 0.075, 0.15), "rust", root, 0.65)
    rounded(f"B{s}_tongue", (0.0, 0.175, -0.04), (0.06, 0.022, 0.08), "rust_dark", root, 0.5)

    # --- Coque d'acier sur la pointe (demi-dôme) ---
    def front_half(v):
        if v.co.y < 0.0:                    # Blender +Y = avant : on écrase l'arrière
            v.co.y *= 0.3
    blob(f"B{s}_toecap", (0.0, 0.085, -0.13), (0.108, 0.072, 0.075), "steel", root, 14, 10, front_half)

    # --- Cheville : manchon + bande de danger ---
    upright(f"B{s}_ankle", 0.0, 0.17, 0.31, 0.06, 0.095, "steel_dark", root, 16)
    upright(f"B{s}_hazard", 0.0, 0.175, 0.205, 0.06, 0.101, "hazard", root, 16)
    blob(f"B{s}_ankle_top", (0.0, 0.31, 0.06), (0.095, 0.02, 0.095), "steel_dark", root, 16, 6)

    # --- Piston au talon ---
    upright(f"B{s}_piston", 0.0, 0.06, 0.2, 0.17, 0.028, "steel_light", root, 8)
    upright(f"B{s}_piston_cap", 0.0, 0.19, 0.23, 0.17, 0.04, "steel_dark", root, 10)

    # --- Voyant cyan, côté extérieur ---
    blob(f"B{s}_light", (0.098 * side, 0.12, 0.02), (0.01, 0.02, 0.036), "screen", root, 8, 6)


def build() -> None:
    reset_scene()
    for side in (-1.0, 1.0):
        build_gauntlet(side, Vector((side * 0.4, 0, 0.6)))
        build_boot(side, Vector((side * 0.4, 0, 0)))
    # Deux .glb séparés : on exporte chaque famille à part
    import bpy
    blend = os.path.join(toonkit.ROOT, "art_src", "blender", "gear.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    for prefix, out in (("Gauntlet_", "gauntlet.glb"), ("Boot_", "boot.glb")):
        bpy.ops.object.select_all(action="DESELECT")
        for obj in bpy.data.objects:
            top = obj
            while top.parent is not None:
                top = top.parent
            if top.name.startswith(prefix):
                obj.select_set(True)
        glb = os.path.join(toonkit.ROOT, "Asset", "Model", "Player", out)
        bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_yup=True,
                                  export_apply=True, export_materials="EXPORT", use_selection=True)
        print("OK ->", glb)


build()
