# Outils partagés par les scripts de modèles (taupe, équipement, ennemis).
# Les cotes sont données dans le repère Godot (Y haut, avant en -Z) et
# converties par g() ; l'exporteur glTF repasse en Y haut.

import math
import os

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

## Couleurs d'aperçu dans Blender (Godot réapplique les siennes par nom).
PREVIEW: dict = {}


def hex_rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def g(x: float, y: float, z: float) -> Vector:
    """Repère Godot -> Blender (Z haut, avant en +Y)."""
    return Vector((x, -z, y))


def material(name: str) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*hex_rgb(PREVIEW.get(name, "#ff00ff")), 1.0)
    return mat


def empty(name: str, pos: Vector, parent=None) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.1
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = pos
    return obj


## False : facettes visibles (ombrage plat), pour les formes anguleuses.
SMOOTH = True


def finish(name: str, bm: bmesh.types.BMesh, mats: list, parent, pos: Vector = Vector()) -> bpy.types.Object:
    for f in bm.faces:
        f.smooth = SMOOTH
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(material(m))
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = pos
    return obj


# ------------------------------------------------------------------ FORMES

def lathe(profile: list, segs: int = 16, closed: bool = False, a0: float = 0.0, a1: float = 360.0) -> bmesh.types.BMesh:
    """Tour : profil [(rayon, hauteur)] en repère Godot, tourné autour de Y.
    Angle 0 = avant (-Z Godot). Rayon 0 en bout de profil = pôle.
    closed : le profil est une boucle (anneau, bord de chapeau).
    a0/a1 : secteur angulaire en degrés (bandeau partiel)."""
    bm = bmesh.new()
    full = abs((a1 - a0) - 360.0) < 1e-6
    n_ang = segs if full else segs + 1
    rings = []
    for (r, y) in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new(g(0.0, y, 0.0))])
            continue
        ring = []
        for i in range(n_ang):
            a = math.radians(a0 + (a1 - a0) * i / segs)
            ring.append(bm.verts.new(g(math.sin(a) * r, y, -math.cos(a) * r)))
        rings.append(ring)
    pairs = list(zip(rings, rings[1:]))
    if closed:
        pairs.append((rings[-1], rings[0]))
    for ra, rb in pairs:
        for i in range(n_ang if full else n_ang - 1):
            j = (i + 1) % n_ang
            if len(ra) == 1:
                bm.faces.new((ra[0], rb[i], rb[j]))
            elif len(rb) == 1:
                bm.faces.new((ra[i], ra[j], rb[0]))
            else:
                bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
    return bm


def ellipsoid(radii_g: tuple, segs: int = 12, rings: int = 8) -> bmesh.types.BMesh:
    rx, ry, rz = radii_g
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * rx, v.co.y * rz, v.co.z * ry))
    return bm


def blob(name, center_g, radii_g, mat, parent, segs=12, rings=8, deform=None):
    bm = ellipsoid(radii_g, segs, rings)
    if deform is not None:
        for v in bm.verts:
            deform(v)
    return finish(name, bm, [mat], parent, g(*center_g))


def oriented(bm: bmesh.types.BMesh, axis_from: Vector, a: Vector, b: Vector) -> Vector:
    d = b - a
    rot = axis_from.rotation_difference(d.normalized()).to_matrix()
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rot)
    return (a + b) * 0.5


def limb(name, a_g, b_g, radius, mat, parent, segs=6):
    """Segment arrondi entre deux points (repère Godot)."""
    a, b = g(*a_g), g(*b_g)
    half = (b - a).length * 0.5 + radius * 0.6
    bm = ellipsoid((radius, radius, half), segs, 6)  # long sur Z Godot = Y Blender
    mid = oriented(bm, Vector((0, 1, 0)), a, b)
    return finish(name, bm, [mat], parent, mid)


def disk(name, center_g, normal_g, radius, depth, mat, parent, segs=12):
    """Cylindre court (verre, rivet, bouchon) orienté selon normal_g."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=radius, depth=depth)
    c = g(*center_g)
    n = g(*normal_g)
    mid = oriented(bm, Vector((0, 0, 1)), c - n * 0.5, c + n * 0.5)
    return finish(name, bm, [mat], parent, mid)


def boxy(radii_g: tuple, power: float = 0.55):
    """Déforme une sphère vers une boîte aux coins ronds (sac en toile)."""
    rx, ry, rz = radii_g
    lim = (rx, rz, ry)                      # Blender x, y, z
    def f(v):
        for i in range(3):
            c = v.co[i] / lim[i]
            v.co[i] = math.copysign(abs(c) ** power, c) * lim[i]
    return f


def cone(name, base_g, tip_g, radius, mat, parent, segs=8):
    """Cône plein de base_g vers tip_g (repère Godot) : dents, oreilles, dard."""
    base, tip = g(*base_g), g(*tip_g)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=0.0, depth=(tip - base).length)
    mid = oriented(bm, Vector((0, 0, 1)), base, tip)
    return finish(name, bm, [mat], parent, mid)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def save_and_export(blend_rel: str, glb_rel: str) -> None:
    blend = os.path.join(ROOT, blend_rel)
    glb = os.path.join(ROOT, glb_rel)
    os.makedirs(os.path.dirname(glb), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_yup=True,
                              export_apply=True, export_materials="EXPORT")
    print("OK ->", glb)
