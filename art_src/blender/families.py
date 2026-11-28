# Planche d'identité des familles d'ennemis : un représentant par famille.
#
#   blender -b -P art_src/blender/families.py
#
# Produit art_src/blender/families.blend et Asset/Model/Concept/families.glb :
#   Coyote   : animal augmenté (chair ronde + prothèses rouillées, lueur verte)
#   Sentinel : robot futuriste (céramique blanche, géométrie pure, cyan, flotte)
# L'insecte de la planche est le bousier déjà en jeu (DungBeetleModel).
#
# Origine au sol, avant en -Z (repère Godot).
# Matériaux toon : fur, fur_dark, rust, rust_dark, steel_dark, steel_light,
#   leather, bandage, ceramic, ceramic_dark, eye_dark
# Matériaux lumineux : toxic (vert), cyan

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from toonkit import *  # noqa: E402,F401,F403
import toonkit  # noqa: E402
from mathutils import Vector  # noqa: E402

toonkit.PREVIEW.update({
    "fur": "#9c8a6e", "fur_dark": "#5e4f3c", "rust": "#a8622f", "rust_dark": "#6e3a1e",
    "steel_dark": "#3e403f", "steel_light": "#c7c7cc", "leather": "#5a3a22",
    "bandage": "#d8cbb0", "ceramic": "#ece6da", "ceramic_dark": "#a9a49a",
    "eye_dark": "#141010", "toxic": "#8cff3a", "cyan": "#5fe1ff",
})


def rounded(name, center, half, mat, parent, power=0.5, segs=12, rings=8):
    return blob(name, center, half, mat, parent, segs, rings, boxy(half, power))


# ------------------------------------------------------------------ COYOTE

def build_coyote(at: Vector) -> None:
    root = empty("Coyote", at)

    # --- Corps : poitrail haut et bombé, arrière plus fin (silhouette de chasseur)
    blob("C_body", (0.0, 0.55, 0.08), (0.19, 0.19, 0.36), "fur", root, 14, 10)
    blob("C_chest", (0.0, 0.6, -0.2), (0.22, 0.24, 0.22), "fur", root, 14, 10)
    blob("C_belly", (0.0, 0.47, -0.05), (0.15, 0.1, 0.25), "fur_dark", root, 10, 6)

    # --- Tête, museau, oreilles (une déchirée)
    blob("C_head", (0.0, 0.8, -0.46), (0.14, 0.13, 0.15), "fur", root, 12, 8)

    def snout_taper(v):
        t = max(0.0, v.co.y / 0.13)
        v.co.x *= 1.0 - 0.35 * t
    blob("C_snout", (0.0, 0.77, -0.64), (0.075, 0.06, 0.13), "fur", root, 10, 6, snout_taper)
    blob("C_nose", (0.0, 0.79, -0.77), (0.03, 0.025, 0.025), "eye_dark", root, 6, 4)
    cone("C_ear_R", (0.08, 0.9, -0.44), (0.12, 1.06, -0.42), 0.045, "fur_dark", root, 6)
    cone("C_ear_L", (-0.08, 0.9, -0.44), (-0.1, 0.98, -0.43), 0.045, "fur_dark", root, 6)
    blob("C_eye_R", (0.085, 0.83, -0.57), (0.022, 0.022, 0.015), "eye_dark", root, 6, 4)
    # Œil augmenté : lentille verte cerclée d'acier
    disk("C_lens_ring", (-0.09, 0.83, -0.57), (-0.5, 0.0, -0.85), 0.042, 0.03, "steel_dark", root, 10)
    disk("C_lens", (-0.102, 0.83, -0.59), (-0.5, 0.0, -0.85), 0.03, 0.01, "toxic", root, 10)

    # --- Mâchoire hydraulique : plaque rouillée, dents d'acier, deux vérins
    rounded("C_jaw", (0.0, 0.69, -0.64), (0.07, 0.022, 0.12), "rust", root, 0.4)
    for i in range(4):
        z = -0.72 + 0.045 * i
        for x in (-0.05, 0.05):
            cone(f"C_tooth_{i}_{x:+.2f}", (x, 0.705, z), (x, 0.745, z), 0.012, "steel_light", root, 5)
    for x in (-0.085, 0.085):
        limb(f"C_piston_{x:+.2f}", (x, 0.7, -0.58), (x, 0.8, -0.46), 0.014, "steel_light", root, 6)
        limb(f"C_sleeve_{x:+.2f}", (x, 0.76, -0.5), (x, 0.81, -0.44), 0.022, "steel_dark", root, 6)

    # --- Pattes : trois en chair, l'avant gauche remplacée par un piston
    for x, z in ((0.13, 0.32), (-0.13, 0.32)):
        limb(f"C_thigh_{x:+.2f}_{z:+.2f}", (x, 0.5, z), (x * 1.05, 0.27, z + 0.08), 0.06, "fur", root, 8)
        limb(f"C_shin_{x:+.2f}_{z:+.2f}", (x * 1.05, 0.27, z + 0.08), (x, 0.04, z + 0.02), 0.035, "fur", root, 8)
        blob(f"C_paw_{x:+.2f}_{z:+.2f}", (x, 0.03, z - 0.01), (0.04, 0.03, 0.055), "fur_dark", root, 8, 5)
    limb("C_leg_FR_a", (0.13, 0.52, -0.22), (0.13, 0.26, -0.24), 0.05, "fur", root, 8)
    limb("C_leg_FR_b", (0.13, 0.26, -0.24), (0.13, 0.04, -0.26), 0.033, "fur", root, 8)
    blob("C_paw_FR", (0.13, 0.03, -0.29), (0.04, 0.03, 0.055), "fur_dark", root, 8, 5)
    # Bandage sur la patte arrière droite
    disk("C_bandage", (0.135, 0.38, 0.36), (0.0, 1.0, 0.25), 0.068, 0.06, "bandage", root, 10)
    # Prothèse : épaulière rouillée, cuisse-vérin, genou, tige, griffe d'acier
    blob("C_shoulder_plate", (-0.17, 0.6, -0.22), (0.07, 0.13, 0.13), "rust", root, 10, 6, boxy((0.07, 0.13, 0.13), 0.6))
    for i, (y, z) in enumerate(((0.66, -0.17), (0.6, -0.29), (0.53, -0.18))):
        disk(f"C_bolt_{i}", (-0.24, y, z), (-1.0, 0.0, 0.0), 0.014, 0.02, "steel_light", root, 6)
    limb("C_mech_upper", (-0.15, 0.5, -0.22), (-0.16, 0.28, -0.27), 0.04, "rust_dark", root, 8)
    disk("C_mech_knee", (-0.16, 0.28, -0.27), (1.0, 0.0, 0.0), 0.045, 0.05, "steel_dark", root, 10)
    limb("C_mech_rod", (-0.16, 0.27, -0.27), (-0.15, 0.05, -0.25), 0.02, "steel_light", root, 6)
    limb("C_mech_sleeve", (-0.16, 0.25, -0.27), (-0.155, 0.14, -0.26), 0.032, "steel_dark", root, 8)
    rounded("C_mech_foot", (-0.15, 0.025, -0.29), (0.045, 0.025, 0.06), "steel_dark", root, 0.45)

    # --- Réservoir de carburant vert sur le dos, sangles, tuyau vers le cou
    limb("C_tank", (0.0, 0.83, -0.06), (0.0, 0.83, 0.24), 0.09, "steel_dark", root, 12)
    limb("C_tank_glass", (0.0, 0.83, 0.0), (0.0, 0.83, 0.17), 0.094, "toxic", root, 12)
    for z in (-0.05, 0.22):
        disk(f"C_strap_{z:+.2f}", (0.0, 0.58, z), (0.0, 0.0, 1.0), 0.205, 0.045, "leather", root, 14)
    limb("C_hose_a", (0.0, 0.86, -0.09), (0.03, 0.93, -0.22), 0.02, "steel_dark", root, 6)
    limb("C_hose_b", (0.03, 0.93, -0.22), (0.05, 0.86, -0.36), 0.02, "steel_dark", root, 6)
    # Plaque de bidon vissée sur le flanc
    rounded("C_flank_plate", (0.19, 0.58, 0.12), (0.014, 0.09, 0.13), "rust", root, 0.4, 8, 6)

    # --- Queue touffue
    limb("C_tail", (0.0, 0.6, 0.42), (0.0, 0.62, 0.66), 0.065, "fur", root, 8)
    blob("C_tail_tip", (0.0, 0.62, 0.69), (0.05, 0.05, 0.06), "fur_dark", root, 8, 5)


# ------------------------------------------------------------------ SENTINELLE

def build_sentinel(at: Vector) -> None:
    root = empty("Sentinel", at)
    core = empty("Sentinel_core", g(0.0, 1.0, 0.0), root)

    # --- Noyau : deux hémisphères de céramique séparées par une fente cyan
    def top_half(v):
        v.co.z = max(v.co.z, 0.0)
    def bottom_half(v):
        v.co.z = min(v.co.z, 0.0)
    blob("S_top", (0.0, 0.035, 0.0), (0.32, 0.3, 0.32), "ceramic", core, 20, 12, top_half)
    blob("S_bottom", (0.0, -0.035, 0.0), (0.3, 0.26, 0.3), "ceramic_dark", core, 20, 12, bottom_half)
    disk("S_slit", (0.0, 0.0, 0.0), (0.0, 1.0, 0.0), 0.29, 0.05, "cyan", core, 20)

    # --- Œil unique : bague sombre, lentille cyan, pupille
    disk("S_eye_ring", (0.0, 0.09, -0.29), (0.0, 0.2, -1.0), 0.13, 0.07, "ceramic_dark", core, 16)
    disk("S_eye", (0.0, 0.095, -0.325), (0.0, 0.2, -1.0), 0.095, 0.02, "cyan", core, 16)
    disk("S_pupil", (0.0, 0.097, -0.337), (0.0, 0.2, -1.0), 0.035, 0.01, "eye_dark", core, 10)

    # --- Anneau qui orbite, incliné, avec trois balises
    ring = finish("S_ring", lathe([(0.48, -0.018), (0.54, -0.018), (0.54, 0.018), (0.48, 0.018)], 32, closed=True),
                  ["steel_light"], core)
    ring.rotation_euler = (math.radians(18.0), math.radians(-10.0), 0.0)
    for i in range(3):
        a = 2.0 * math.pi * i / 3.0
        b = blob(f"S_beacon_{i}", (math.sin(a) * 0.51, 0.0, -math.cos(a) * 0.51), (0.035, 0.035, 0.035), "cyan", core, 8, 6)
        b.parent = ring   # les balises tournent avec l'anneau
        b.location = g(math.sin(a) * 0.51, 0.0, -math.cos(a) * 0.51)

    # --- Boucliers latéraux qui flottent, détachés du corps
    for side in (-1.0, 1.0):
        s = "L" if side < 0 else "R"
        rounded(f"S_shield_{s}", (0.6 * side, -0.02, -0.06), (0.03, 0.2, 0.13), "ceramic", core, 0.45, 10, 8)
        rounded(f"S_shield_line_{s}", (0.633 * side, -0.02, -0.06), (0.006, 0.15, 0.02), "cyan", core, 0.4, 6, 4)

    # --- Antenne, propulseur cyan sous le corps
    limb("S_antenna", (0.06, 0.3, 0.06), (0.1, 0.48, 0.12), 0.012, "steel_light", core, 6)
    blob("S_antenna_tip", (0.1, 0.49, 0.12), (0.025, 0.025, 0.025), "cyan", core, 6, 4)
    cone("S_thruster", (0.0, -0.26, 0.0), (0.0, -0.4, 0.0), 0.12, "ceramic_dark", core, 14)
    cone("S_flame", (0.0, -0.36, 0.0), (0.0, -0.56, 0.0), 0.07, "cyan", core, 10)


def build() -> None:
    reset_scene()
    build_coyote(Vector((-1.5, 0, 0)))
    build_sentinel(Vector((1.5, 0, 0)))
    save_and_export("art_src/blender/families.blend", "Asset/Model/Concept/families.glb")


build()
