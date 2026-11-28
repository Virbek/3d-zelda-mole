# Objets du donjon (raffinerie ensablée) : bidon cabossé, tronçon de tuyau.
#
#   blender -b -P art_src/blender/props.py
#
# Produit art_src/blender/props.blend et Asset/Model/Dungeon/props.glb.
# Mêmes gabarits que les primitives de Script/dungeon/room_decor.gd :
#   Barrel : origine au sol, rayon 0.36, hauteur 0.9
#   Pipe   : tronçon de 2 m couché le long de X, centré, bride côté -X,
#            collier de fixation qui part vers le mur (-Z)
# Matériaux : barrel (teinte tirée au sort par le jeu), barrel_rust, hazard,
#             steel_dark, rust, rust_dark

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from toonkit import *  # noqa: E402,F401,F403
import toonkit  # noqa: E402
from mathutils import Vector  # noqa: E402

toonkit.PREVIEW.update({
    "barrel": "#a8622f", "barrel_rust": "#5e2e16", "hazard": "#e0a23a",
    "steel_dark": "#4a4c4b", "rust": "#a8622f", "rust_dark": "#6e3a1e",
})


def build_barrel(at: Vector) -> None:
    root = empty("Barrel", at)
    rnd = random.Random(7)
    r, h = 0.35, 0.9
    # Profil : léger ventre, deux cerclages en relief, bord du couvercle
    prof = [(0.0, 0.0), (r - 0.02, 0.0), (r, 0.02)]
    for y in [0.06, 0.12, 0.2, 0.28, 0.3, 0.32, 0.4, 0.5, 0.58, 0.6, 0.62, 0.7, 0.78, 0.84]:
        bulge = 0.012 * math.sin(math.pi * y / h)
        ring = 0.014 if (abs(y - 0.3) < 0.011 or abs(y - 0.6) < 0.011) else 0.0
        prof.append((r + bulge + ring, y))
    prof += [(r, 0.88), (r + 0.012, 0.9), (r - 0.03, 0.905), (r - 0.04, 0.89), (0.0, 0.885)]
    bm = lathe(prof, 20)
    # Bosses : deux enfoncements, comme un bidon qui a vécu
    dents = [(math.radians(40.0), 0.45, 0.06), (math.radians(200.0), 0.72, 0.045)]
    for v in bm.verts:
        a = math.atan2(v.co.x, v.co.y)
        for da, dy, depth in dents:
            d_ang = math.atan2(math.sin(a - da), math.cos(a - da))
            k = math.exp(-(d_ang / 0.45) ** 2 - ((v.co.z - dy) / 0.12) ** 2)
            rad = Vector((v.co.x, v.co.y, 0.0))
            if rad.length > 0.01:
                rad.normalize()
                v.co -= rad * depth * k
    # Matériaux par face : bande de danger, coulures de rouille
    for f in bm.faces:
        c = f.calc_center_median()
        y = c.z
        a = math.atan2(c.x, c.y)
        drip = 0.5 + 0.5 * math.sin(a * 5.0 + 1.3) * math.sin(a * 3.0)
        if 0.66 < y < 0.76:
            f.material_index = 2
        elif y > 0.86 or y < 0.03:
            f.material_index = 3
        elif drip > 0.72 and y > 0.2 + 0.3 * (1.0 - drip) or (y < 0.12 and rnd.random() < 0.5):
            f.material_index = 1
        else:
            f.material_index = 0
    finish("Barrel_body", bm, ["barrel", "barrel_rust", "hazard", "steel_dark"], root)
    # Bonde sur le couvercle
    disk("Barrel_cap", (0.14, 0.905, 0.08), (0.0, 0.03, 0.0), 0.045, 0.03, "steel_dark", root, 8)


def build_pipe(at: Vector) -> None:
    root = empty("Pipe", at)
    length, r = 2.0, 0.12
    # Tube légèrement irrégulier : pas un cylindre parfait
    n = 10
    bm = None
    import bmesh
    bm = bmesh.new()
    segs = 12
    rings = []
    for i in range(n + 1):
        x = -length / 2 + length * i / n
        rr = r * (1.0 + 0.03 * math.sin(i * 2.1))
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            ring.append(bm.verts.new(g(x, math.cos(a) * rr, math.sin(a) * rr)))
        rings.append(ring)
    for i in range(n):
        for j in range(segs):
            k = (j + 1) % segs
            f = bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
            # Plaques de rouille plus sombre, sur le dessous et par endroits
            a = 2 * math.pi * (j + 0.5) / segs
            f.material_index = 1 if math.cos(a) < -0.5 else 0
    finish("Pipe_tube", bm, ["rust", "rust_dark"], root)
    # Bride boulonnée côté -X
    x0 = -length / 2
    disk("Pipe_flange", (x0, 0.0, 0.0), (1.0, 0.0, 0.0), 0.175, 0.07, "steel_dark", root, 14)
    for j in range(6):
        a = 2 * math.pi * j / 6 + 0.3
        disk(f"Pipe_bolt_{j}", (x0 + 0.045, math.cos(a) * 0.14, math.sin(a) * 0.14), (1.0, 0.0, 0.0),
             0.022, 0.03, "steel_dark", root, 6)
    # Collier de fixation au milieu, qui rentre dans le mur
    disk("Pipe_clamp", (0.25, 0.0, 0.0), (1.0, 0.0, 0.0), 0.14, 0.06, "rust_dark", root, 12)
    blob("Pipe_bracket", (0.25, 0.0, -0.2), (0.04, 0.04, 0.12), "steel_dark", root, 6, 4,
         boxy((0.04, 0.04, 0.12), 0.4))


def build() -> None:
    reset_scene()
    build_barrel(Vector((0, 0, 0)))
    build_pipe(Vector((2, 0, 1)))
    save_and_export("art_src/blender/props.blend", "Asset/Model/Dungeon/props.glb")


build()
