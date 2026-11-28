# Frelon-perceur : modèle généré par script Blender.
#
#   blender -b -P art_src/blender/hornet.py
#
# Produit art_src/blender/hornet.blend (à retoucher à la main si besoin) et
# Asset/Model/Enemy/hornet.glb (importé par Godot).
#
# Les cotes sont écrites dans le repère Godot (Y haut, avant en -Z) puis
# converties : l'exporteur glTF repasse en Y haut à l'export.
#
# Contrat avec Script/enemy/hornet_model.gd (ne pas renommer) :
#   Body          : tout ce qui flotte (le script le monte à hover_height)
#   Abdomen       : pivot de l'abdomen recourbé (rotation X)
#   WingHinge_0..3: charnières des ailes, ordre avant-G, avant-D, arrière-G, arrière-D
#   Matériaux     : chitin, chitin_dark, accent, stinger (toon) ;
#                   eye, stripe (lumineux) ; wing (translucide)

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLEND_OUT = os.path.join(ROOT, "art_src", "blender", "hornet.blend")
GLB_OUT = os.path.join(ROOT, "Asset", "Model", "Enemy", "hornet.glb")

# Couleurs d'aperçu dans Blender seulement : Godot réapplique les siennes.
PREVIEW = {
    "chitin": (0.09, 0.06, 0.04),
    "chitin_dark": (0.03, 0.02, 0.015),
    "accent": (0.55, 0.3, 0.08),
    "stinger": (0.85, 0.78, 0.6),
    "eye": (0.37, 0.88, 1.0),
    "stripe": (0.78, 0.45, 0.23),
    "wing": (0.37, 0.88, 1.0),
}


def g(x: float, y: float, z: float) -> Vector:
    """Repère Godot -> repère Blender (Z haut, avant en +Y)."""
    return Vector((x, -z, y))


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name: str) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*PREVIEW[name], 1.0)
    return mat


def empty(name: str, pos: Vector, parent=None) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.08
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = pos
    return obj


def mesh_object(name: str, bm: bmesh.types.BMesh, mats: list, parent, pos: Vector) -> bpy.types.Object:
    for f in bm.faces:
        f.smooth = True
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


def ellipsoid_bm(radii: Vector, segs: int = 12, rings: int = 8, axis_y: bool = False) -> bmesh.types.BMesh:
    """Sphère low-poly mise à l'échelle. axis_y : pôles sur l'axe Y Blender
    (avant / arrière) pour que les anneaux tombent en tranches le long du corps."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    if axis_y:
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    for v in bm.verts:
        v.co = Vector((v.co.x * radii.x, v.co.y * radii.y, v.co.z * radii.z))
    return bm


def blob(name: str, center_g: tuple, radii_g: tuple, mat: str, parent, segs: int = 12, rings: int = 8) -> bpy.types.Object:
    rx, ry, rz = radii_g
    bm = ellipsoid_bm(Vector((rx, rz, ry)), segs, rings)
    return mesh_object(name, bm, [mat], parent, g(*center_g))


def limb(name: str, a_g: tuple, b_g: tuple, radius: float, mat: str, parent, segs: int = 6) -> bpy.types.Object:
    """Segment arrondi (ellipsoïde allongé) entre deux points, repère Godot."""
    a = g(*a_g)
    b = g(*b_g)
    d = b - a
    half = d.length * 0.5 + radius * 0.6
    bm = ellipsoid_bm(Vector((radius, half, radius)), segs, 6, axis_y=False)
    # Ellipsoïde construit le long de Y : on l'oriente vers d
    rot = Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix()
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rot)
    return mesh_object(name, bm, [mat], parent, (a + b) * 0.5)


def cone(name: str, base_g: tuple, tip_g: tuple, radius: float, mat: str, parent, segs: int = 8) -> bpy.types.Object:
    base = g(*base_g)
    tip = g(*tip_g)
    d = tip - base
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=0.0, depth=d.length)
    # create_cone : axe Z, centré -> on l'oriente vers la pointe
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rot)
    return mesh_object(name, bm, [mat], parent, (base + tip) * 0.5)


def wing(name: str, length: float, width: float, side: float, parent) -> bpy.types.Object:
    """Aile plate en goutte : large près de la charnière, arrondie au bout."""
    bm = bmesh.new()
    pts = []
    n = 14
    for i in range(n):
        t = 2.0 * math.pi * i / n
        x = (math.cos(t) * 0.5 + 0.5) * length
        # Bord d'attaque droit, bord de fuite bombé
        y = math.sin(t) * width * (0.35 if math.sin(t) > 0 else 0.6)
        y *= 0.55 + 0.45 * math.sin(math.pi * (x / length) ** 0.8)
        pts.append(bm.verts.new((x * side, y, 0.0)))
    bm.faces.new(pts if side > 0 else list(reversed(pts)))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-12.0 * side), 3, "Z"))
    obj = mesh_object(name, bm, ["wing"], parent, Vector((0, 0, 0)))
    for f in obj.data.polygons:
        f.use_smooth = False
    return obj


def abdomen_mesh(parent) -> bpy.types.Object:
    """Abdomen fuselé à rayures : une seule surface, faces rayées en 'stripe'."""
    length = 0.36
    center_y = -0.40      # Blender : vers l'arrière depuis la charnière
    center_z = -0.08
    bm = ellipsoid_bm(Vector((0.19, length, 0.17)), segs=14, rings=12, axis_y=True)
    for v in bm.verts:
        t = -v.co.y / length            # -1 avant, +1 arrière
        if t > 0.0:
            k = 1.0 - 0.5 * t * t       # l'arrière s'affine vers le dard
            v.co.x *= k
            v.co.z *= k
            v.co.z -= 0.05 * t * t      # et plonge un peu
        v.co.y += center_y
        v.co.z += center_z
    bands = [(-0.55, -0.3), (-0.05, 0.2), (0.42, 0.62)]
    for f in bm.faces:
        t = -(f.calc_center_median().y - center_y) / length
        f.material_index = 1 if any(a <= t < b for a, b in bands) else 0
    return mesh_object("Abdomen_mesh", bm, ["chitin", "stripe"], parent, Vector((0, 0, 0)))


def build() -> None:
    reset_scene()
    root = empty("Hornet", Vector((0, 0, 0)))
    body = empty("Body", Vector((0, 0, 0)), root)

    # --- Thorax, tête, yeux composés ---
    blob("Thorax", (0.0, 0.05, -0.06), (0.19, 0.17, 0.21), "chitin", body)
    blob("Thorax_spot", (0.0, 0.17, -0.1), (0.1, 0.05, 0.08), "accent", body, 10, 6)
    blob("Head", (0.0, 0.1, -0.34), (0.15, 0.14, 0.12), "chitin_dark", body)
    for side in (-1.0, 1.0):
        s = "L" if side < 0 else "R"
        blob(f"Eye_{s}", (0.1 * side, 0.13, -0.4), (0.065, 0.085, 0.055), "eye", body, 10, 6)
        # Mandibles en crochet
        cone(f"Mandible_{s}", (0.05 * side, 0.0, -0.43), (0.015 * side, -0.07, -0.52), 0.035, "accent", body)
        # Antennes coudées
        limb(f"Antenna_{s}_a", (0.04 * side, 0.22, -0.4), (0.1 * side, 0.38, -0.5), 0.018, "chitin_dark", body)
        limb(f"Antenna_{s}_b", (0.1 * side, 0.38, -0.5), (0.15 * side, 0.4, -0.64), 0.016, "chitin_dark", body)

    # --- Abdomen recourbable ---
    abdomen = empty("Abdomen", g(0.0, 0.0, 0.16), body)
    blob("Petiole", (0.0, -0.02, 0.03), (0.07, 0.07, 0.07), "chitin_dark", abdomen, 8, 6)
    abdomen_mesh(abdomen)
    cone("Stinger", (0.0, -0.17, 0.7), (0.0, -0.2, 0.9), 0.04, "stinger", abdomen)

    # --- Ailes : deux paires ---
    for idx, (z, length, width) in enumerate([(-0.08, 0.55, 0.2), (0.08, 0.4, 0.15)]):
        for j, side in enumerate((-1.0, 1.0)):
            hinge = empty(f"WingHinge_{idx * 2 + j}", g(0.1 * side, 0.2, z), body)
            wing(f"Wing_{idx * 2 + j}", length, width, side, hinge)

    # --- Six pattes pendantes, coudées ---
    for z in (-0.15, 0.0, 0.12):
        for side in (-1.0, 1.0):
            s = "L" if side < 0 else "R"
            hip = (0.11 * side, -0.08, z)
            knee = (0.24 * side, -0.18, z - 0.02)
            foot = (0.21 * side, -0.4, z + 0.06)
            limb(f"Leg_{s}{z:+.2f}_a", hip, knee, 0.025, "chitin_dark", body)
            limb(f"Leg_{s}{z:+.2f}_b", knee, foot, 0.02, "chitin_dark", body)

    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
    bpy.ops.export_scene.gltf(
        filepath=GLB_OUT,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    print("OK ->", GLB_OUT)


build()
