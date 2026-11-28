# Taupe exploratrice : modèle du corps + tenue, généré par script Blender.
#
#   blender -b -P art_src/blender/mole.py
#
# Produit art_src/blender/mole.blend et Asset/Model/Player/mole.glb.
# Cotes écrites dans le repère Godot du nœud Rig/Body (Y haut, avant en -Z,
# bas du corps à y = -0.72, sol à y = -1.0). Mains et pieds ne sont PAS ici :
# gantelets et bottes restent construits par le rig.
#
# Matériaux (Godot réapplique ses couleurs toon d'après ces noms) :
#   fur, fur_light, mask, eye, nose, whisker, hat, hat_dark, lens, steel,
#   steel_dark, scarf, scarf_dark, leather, canvas, canvas_dark, poncho, poncho_light, poncho_dark, bandana, bandana_dot ; lantern (lumineux)

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402
from toonkit import *  # noqa: E402,F401,F403
import toonkit  # noqa: E402

toonkit.PREVIEW.update({
    "fur": "#4e2e1d", "fur_light": "#6e4832", "mask": "#141010", "eye": "#e8d9b0",
    "nose": "#c0302a", "whisker": "#141010", "hat": "#8a4f2a", "hat_dark": "#5a3a22",
    "lens": "#111111", "steel": "#8a8d8f", "steel_dark": "#4a4c4b", "scarf": "#b3261e",
    "scarf_dark": "#7a1712", "leather": "#5a3a22", "canvas": "#8c7a52",
    "canvas_dark": "#5e5034", "lantern": "#5fe1ff",
    "shirt": "#b89a64", "shirt_dark": "#8c7448",
    "bandana": "#2c3a52", "bandana_dot": "#e8d3a2", "poncho": "#a3261d", "poncho_light": "#e8d3a2", "poncho_dark": "#4a1410",
})


# ------------------------------------------------------------------ PIÈCES

SLIM = 0.84   ## minceur du buste (1 = poire ronde) ; la tête garde sa taille


def slim(y: float) -> float:
    t = min(1.0, max(0.0, (y - 0.05) / 0.33))
    return SLIM + (1.0 - SLIM) * t


def body_profile() -> list:
    # Poire : large en bas, tête ronde en haut
    return [(r * slim(y), y) for (r, y) in [(0.0, -0.72), (0.22, -0.71), (0.37, -0.64), (0.44, -0.5), (0.46, -0.33),
            (0.44, -0.13), (0.38, 0.07), (0.32, 0.24), (0.27, 0.38), (0.2, 0.48),
            (0.1, 0.535), (0.0, 0.545)]]


def body_r(y: float) -> float:
    pts = body_profile()
    for (r0, y0), (r1, y1) in zip(pts, pts[1:]):
        if y0 <= y <= y1:
            return r0 + (r1 - r0) * (y - y0) / (y1 - y0)
    return 0.0


def build_body(root) -> None:
    finish("Body_mesh", lathe(body_profile(), 18), ["fur"], root)

    # Petits yeux noirs brillants, directement sur le pelage
    for side in (-1.0, 1.0):
        s = "L" if side < 0 else "R"
        a = math.radians(24.0 * side)
        r = body_r(0.32) + 0.005
        blob(f"Eye_{s}", (math.sin(a) * r, 0.325, -math.cos(a) * r), (0.034, 0.04, 0.02), "mask", root, 8, 6)
        r2 = r + 0.016
        a2 = a + math.radians(-3.0 * side)
        blob(f"Eye_glint_{s}", (math.sin(a2) * r2, 0.338, -math.cos(a2) * r2), (0.011, 0.011, 0.006), "eye", root, 6, 4)

    # Museau long, fuselé vers l'avant, un peu tombant
    def taper(v):
        t = max(0.0, v.co.y / 0.2)          # 0 à la base, 1 au bout (Blender +Y = avant)
        k = 1.0 - 0.45 * t
        v.co.x *= k
        v.co.z *= k
        v.co.z -= 0.04 * t * t
    blob("Snout", (0.0, 0.2, -0.38), (0.1, 0.085, 0.2), "fur_light", root, 12, 8, taper)
    blob("Nose", (0.0, 0.165, -0.57), (0.055, 0.05, 0.05), "nose", root, 10, 6)
    for side in (-1.0, 1.0):
        s = "L" if side < 0 else "R"
        for k, dy in enumerate((0.05, 0.0, -0.05)):
            limb(f"Whisker_{s}{k}", (0.05 * side, 0.18, -0.5), (0.27 * side, 0.18 + dy, -0.47 + 0.03 * k), 0.006, "whisker", root, 4)


def build_hat(root) -> None:
    hat = empty("Hat", g(0.0, 0.0, 0.0), root)
    # Calotte pincée sur le dessus, creusée au milieu
    crown = [(0.255, 0.41), (0.26, 0.47), (0.245, 0.53), (0.2, 0.575), (0.1, 0.585), (0.0, 0.565)]
    bm = lathe(crown, 16)
    for v in bm.verts:
        if v.co.z > 0.5:                   # pincement avant (Blender +Y)
            v.co.x *= 1.0 - 0.18 * max(0.0, v.co.y) / 0.25
    finish("Hat_crown", bm, ["hat"], hat)
    # Bandeau
    finish("Hat_band", lathe([(0.255, 0.415), (0.268, 0.42), (0.268, 0.45), (0.255, 0.455)], 16, closed=True), ["hat_dark"], hat)
    # Bord large et plat, à peine relevé sur les côtés
    brim = [(0.24, 0.405), (0.5, 0.4), (0.52, 0.415), (0.5, 0.43), (0.24, 0.44)]
    bm = lathe(brim, 24, closed=True)
    for v in bm.verts:
        side = abs(v.co.x) / 0.53
        front = max(0.0, v.co.y) / 0.53
        v.co.z += 0.03 * side ** 3 - 0.015 * front ** 2
    finish("Hat_brim", bm, ["hat"], hat)
    # Lunettes posées sur la calotte : sangle + deux verres noirs
    finish("Goggle_strap", lathe([(0.25, 0.465), (0.26, 0.47), (0.258, 0.505), (0.245, 0.51)], 16, closed=True), ["leather"], hat)
    for side in (-1.0, 1.0):
        s = "L" if side < 0 else "R"
        a = math.radians(20.0 * side)
        n = (math.sin(a), 0.15, -math.cos(a))
        c = (math.sin(a) * 0.25, 0.49, -math.cos(a) * 0.25)
        disk(f"Goggle_rim_{s}", c, (n[0] * 0.05, n[1] * 0.05, n[2] * 0.05), 0.055, 0.045, "steel_dark", hat)
        c2 = (c[0] + n[0] * 0.028, c[1] + n[1] * 0.028, c[2] + n[2] * 0.028)
        disk(f"Goggle_lens_{s}", c2, (n[0] * 0.01, n[1] * 0.01, n[2] * 0.01), 0.04, 0.012, "lens", hat)
    limb("Goggle_bridge", (-0.04, 0.5, -0.262), (0.04, 0.5, -0.262), 0.014, "steel_dark", hat)


def build_shirt(root) -> None:
    """Chemise d'exploratrice sans manches (pas de bras) : du foulard au
    bas-ventre, patte boutonnée, deux poches de poitrine, col sous le foulard."""
    ys = [-0.58, -0.5, -0.4, -0.3, -0.2, -0.1, 0.0, 0.08, 0.14]
    hem = [(body_r(-0.6) + 0.03, -0.61)]
    finish("Shirt", lathe(hem + [(body_r(y) + 0.016, y) for y in ys], 20), ["shirt"], root)
    # Patte de boutonnage + boutons
    finish("Shirt_placket", lathe([(body_r(y) + 0.022, y) for y in ys[:-1]], 2, a0=-5, a1=5), ["shirt_dark"], root)
    for y in (-0.5, -0.24, -0.1, 0.0):
        r = body_r(y) + 0.028
        disk(f"Button_{y:+.2f}", (0.0, y, -r), (0.0, 0.0, -0.01), 0.016, 0.01, "steel_dark", root, 6)
    # Poches de poitrine avec rabat
    for side in (-1.0, 1.0):
        s = "L" if side < 0 else "R"
        a0, a1 = (16.0, 40.0) if side > 0 else (-40.0, -16.0)
        pocket = [(body_r(y) + 0.026, y) for y in (-0.2, -0.15, -0.1, -0.06)]
        finish(f"Pocket_{s}", lathe(pocket, 4, a0=a0, a1=a1), ["shirt_dark"], root)
        flap = [(body_r(y) + 0.032, y) for y in (-0.08, -0.05, -0.03)]
        finish(f"Pocket_flap_{s}", lathe(flap, 4, a0=a0 - 1, a1=a1 + 1), ["shirt"], root)
    # Col : deux pointes qui dépassent sous le foulard
    for side in (-1.0, 1.0):
        s = "L" if side < 0 else "R"
        a = math.radians(14.0 * side)
        r = body_r(0.05) + 0.03
        blob(f"Collar_{s}", (math.sin(a) * r, 0.045, -math.cos(a) * r), (0.06, 0.05, 0.015), "shirt", root, 6, 4)


PONCHO_TOP, PONCHO_HEM = 0.1, -0.3


def poncho_r(y: float) -> float:
    t = min(1.0, max(0.0, (PONCHO_TOP - y) / (PONCHO_TOP - PONCHO_HEM)))   # 0 au col, 1 à l'ourlet
    return body_r(y) + 0.02 + 0.07 * t * t


def build_poncho(root) -> None:
    """Poncho de laine rouge façon western : tombe des épaules en s'évasant,
    bande de vagues crème entre deux liserés sombres, franges à l'ourlet."""
    top, hem = PONCHO_TOP, PONCHO_HEM
    n = 40
    prof = [(poncho_r(top + (hem - top) * i / n), top + (hem - top) * i / n) for i in range(n + 1)]
    bm = lathe(prof, 48)
    wave_y, wave_amp, wave_w = -0.175, 0.028, 0.02
    for f in bm.faces:
        c = f.calc_center_median()
        a = math.atan2(c.x, c.y)
        y = c.z
        yc = wave_y + wave_amp * math.sin(a * 7.0)
        if abs(y - yc) < wave_w:
            f.material_index = 1
        elif abs(y - (wave_y + 0.065)) < 0.009 or abs(y - (wave_y - 0.065)) < 0.009 or y < hem + 0.02:
            f.material_index = 2
        else:
            f.material_index = 0
    finish("Poncho", bm, ["poncho", "poncho_light", "poncho_dark"], root)
    # Franges sous l'ourlet
    r = body_r(hem) + 0.09
    for i in range(36):
        a = 2.0 * math.pi * i / 36
        x, z = math.sin(a) * r, -math.cos(a) * r
        limb(f"Fringe_{i}", (x, hem + 0.005, z), (x * 1.02, hem - 0.045, z * 1.02), 0.011, "poncho", root, 4)


def build_bandana(root) -> None:
    """Bandana de bandit : bande serrée autour du cou, grand triangle qui
    pend en pointe sur la poitrine, nœud et deux pans dans la nuque."""
    def over(y: float) -> float:
        # Juste par-dessus le poncho (ou le corps au-dessus du col)
        return max(body_r(y) + 0.02, poncho_r(y) if y <= PONCHO_TOP else 0.0) + 0.014

    # Bande du cou
    y0 = 0.13
    band = [(over(y0 - 0.035) - 0.01, y0 - 0.035), (over(y0 - 0.03) + 0.008, y0 - 0.03),
            (over(y0) + 0.012, y0), (over(y0 + 0.03) + 0.008, y0 + 0.03), (over(y0 + 0.035) - 0.01, y0 + 0.035)]
    finish("Bandana_band", lathe(band, 20, closed=True), ["bandana"], root)

    # Triangle sur la poitrine : maillage angle x hauteur, pointe en bas au centre
    import bmesh as _bm
    bm = _bm.new()
    cols, rows, half = 12, 7, 62.0
    grid = []
    for j in range(rows + 1):
        t = j / rows
        row = []
        for i in range(cols + 1):
            a_deg = -half + 2.0 * half * i / cols
            k = 1.0 - abs(a_deg) / half                     # 1 au centre, 0 aux bords
            drop = 0.03 + 0.24 * k                          # profondeur du pan à cet angle
            y = y0 - 0.02 - drop * t
            r = over(y) + 0.004 * (1.0 - t)
            a = math.radians(a_deg)
            row.append(bm.verts.new(g(math.sin(a) * r, y, -math.cos(a) * r)))
        grid.append(row)
    for j in range(rows):
        for i in range(cols):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            f.material_index = 1 if (i % 3 == 1 and j % 3 == 1) or (i % 3 == 2 and j % 3 == 2 and j < rows - 1) else 0
    finish("Bandana_front", bm, ["bandana", "bandana_dot"], root)

    # Nœud dans la nuque + deux pans
    rb = over(y0) + 0.03
    blob("Bandana_knot", (0.0, y0, rb), (0.045, 0.04, 0.035), "bandana", root, 8, 6)
    limb("Bandana_tail_a", (0.02, y0 - 0.01, rb + 0.01), (0.07, y0 - 0.13, rb + 0.03), 0.026, "bandana", root, 6)
    limb("Bandana_tail_b", (-0.02, y0 - 0.01, rb + 0.01), (-0.06, y0 - 0.11, rb + 0.035), 0.024, "bandana", root, 6)


def build_belt(root) -> None:
    y = -0.38
    r = body_r(y)
    ring = [(r - 0.01, y - 0.045), (r + 0.025, y - 0.042), (r + 0.03, y), (r + 0.025, y + 0.042), (r - 0.01, y + 0.045)]
    finish("Belt", lathe(ring, 20, closed=True), ["leather"], root)
    blob("Buckle", (0.0, y, -r - 0.03), (0.065, 0.055, 0.02), "steel", root, 10, 6)
    blob("Buckle_hole", (0.0, y, -r - 0.045), (0.03, 0.025, 0.01), "steel_dark", root, 8, 4)
    # Gourde en acier accrochée à la hanche gauche
    a = math.radians(-120.0)
    cx, cz = math.sin(a) * (r + 0.07), -math.cos(a) * (r + 0.07)
    bm = ellipsoid((0.1, 0.11, 0.045), 14, 8)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                     matrix=Vector((0, 1, 0)).rotation_difference(g(math.sin(a), 0, -math.cos(a)).normalized()).to_matrix())
    finish("Canteen", bm, ["steel"], root, g(cx, y - 0.15, cz))
    disk("Canteen_cap", (cx, y - 0.02, cz), (0.0, 0.04, 0.0), 0.028, 0.04, "steel_dark", root, 8)
    limb("Canteen_strap", (cx, y - 0.04, cz), (math.sin(a) * (r + 0.02), y, -math.cos(a) * (r + 0.02)), 0.012, "leather", root, 4)



def build_bag(root) -> None:
    y = -0.04
    z = body_r(y) + 0.07
    size = (0.21, 0.2, 0.09)
    blob("Bag", (0.0, y, z), size, "canvas", root, 14, 10, boxy(size))
    flap = (0.215, 0.075, 0.095)
    blob("Bag_flap", (0.0, y + 0.13, z + 0.01), flap, "canvas_dark", root, 14, 8, boxy(flap))
    pocket = (0.12, 0.065, 0.03)
    blob("Bag_pocket", (0.0, y - 0.07, z + 0.085), pocket, "canvas_dark", root, 10, 6, boxy(pocket))
    disk("Bag_clasp", (0.0, y + 0.06, z + 0.1), (0.0, 0.0, 0.015), 0.022, 0.015, "steel", root, 8)
    # Couverture rouge roulée sur le dessus, deux sangles fines
    limb("Blanket_roll", (-0.24, y + 0.26, z - 0.01), (0.24, y + 0.26, z - 0.01), 0.06, "scarf_dark", root, 10)
    for x in (-0.12, 0.12):
        disk(f"Blanket_tie_{x:+.2f}", (x, y + 0.26, z - 0.01), (0.022, 0.0, 0.0), 0.066, 0.022, "leather", root, 10)
    # Mini lanterne cyan sur le côté
    lx = 0.25
    blob("Lantern_glass", (lx, y - 0.04, z), (0.035, 0.05, 0.035), "lantern", root, 8, 6)
    disk("Lantern_top", (lx, y + 0.02, z), (0.0, 0.025, 0.0), 0.04, 0.025, "steel_dark", root, 8)
    disk("Lantern_bottom", (lx, y - 0.1, z), (0.0, 0.02, 0.0), 0.04, 0.02, "steel_dark", root, 8)
    # Bretelles qui passent sur les épaules
    for side in (-1.0, 1.0):
        s = "L" if side < 0 else "R"
        limb(f"Strap_{s}", (0.12 * side, y + 0.13, z - 0.06), (0.17 * side, 0.2, 0.18), 0.022, "leather", root, 6)
        limb(f"Strap_{s}_front", (0.17 * side, 0.2, 0.18), (0.24 * side, 0.12, -0.26), 0.022, "leather", root, 6)


def build() -> None:
    reset_scene()
    root = empty("Mole", Vector((0, 0, 0)))
    build_body(root)
    build_hat(root)
    build_poncho(root)
    build_bandana(root)
    build_belt(root)
    build_bag(root)

    save_and_export("art_src/blender/mole.blend", "Asset/Model/Player/mole.glb")


build()
