"""Build mobile-efficient 3D grass blade tufts and sculpted park/street hedges in Blender.
Exports assets/models/grass_tuft.glb and assets/models/hedge_cluster.glb.
Run: blender -b --factory-startup --python tools/blender/build_foliage_props.py
"""
import math
import os
import random
import bpy
import bmesh
from mathutils import Matrix, Vector

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models"))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_mat(name, rgba, rough=0.88):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgba, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.22
    return m


def export_glb(filename, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    print(f"EXPORTED {path}")


def build_grass_tuft():
    """Sculpted 3D grass blade tuft (18 tapered curved blades, ~54 tris, zero alpha overdraw)."""
    reset()
    rng = random.Random(4219)
    m_base = make_mat("grass_base", (0.14, 0.22, 0.09), 0.92)
    m_mid = make_mat("grass_mid", (0.21, 0.32, 0.13), 0.86)
    m_tip = make_mat("grass_tip", (0.31, 0.40, 0.16), 0.84)

    mesh = bpy.data.meshes.new("grass_tuft")
    obj = bpy.data.objects.new("grass_tuft", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(m_base)
    obj.data.materials.append(m_mid)
    obj.data.materials.append(m_tip)

    bm = bmesh.new()
    for i in range(18):
        ang = (i / 18.0) * math.tau + rng.uniform(-0.18, 0.18)
        rad = rng.uniform(0.02, 0.34)
        bx, by = math.cos(ang) * rad, math.sin(ang) * rad
        h = rng.uniform(0.16, 0.34)
        w = rng.uniform(0.022, 0.036)
        lean = rng.uniform(0.06, 0.18)
        dir_x, dir_y = math.cos(ang), math.sin(ang)
        perp_x, perp_y = -dir_y, dir_x

        # 3-segment tapered curved blade (base -> mid -> tip)
        v0 = bm.verts.new((bx - perp_x * w, by - perp_y * w, 0.0))
        v1 = bm.verts.new((bx + perp_x * w, by + perp_y * w, 0.0))
        mx, my, mz = bx + dir_x * lean * 0.45, by + dir_y * lean * 0.45, h * 0.55
        v2 = bm.verts.new((mx - perp_x * w * 0.58, my - perp_y * w * 0.58, mz))
        v3 = bm.verts.new((mx + perp_x * w * 0.58, my + perp_y * w * 0.58, mz))
        tx, ty, tz = bx + dir_x * lean, by + dir_y * lean, h
        v4 = bm.verts.new((tx, ty, tz))

        f1 = bm.faces.new((v0, v1, v3, v2))
        f1.material_index = 0 if i % 3 == 0 else 1
        f2 = bm.faces.new((v2, v3, v4))
        f2.material_index = 2 if i % 2 == 0 else 1

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    export_glb("grass_tuft.glb", [obj])


def build_hedge_cluster():
    """Organic 3D park/street shrub & hedge cluster with woody stems and varied leafy lobes."""
    reset()
    rng = random.Random(9012)
    m_stem = make_mat("hedge_stem", (0.18, 0.13, 0.09), 0.94)
    m_dk = make_mat("hedge_dk", (0.13, 0.23, 0.11), 0.88)
    m_mid = make_mat("hedge_mid", (0.20, 0.33, 0.15), 0.85)
    m_hi = make_mat("hedge_hi", (0.29, 0.42, 0.19), 0.82)

    mesh = bpy.data.meshes.new("hedge_cluster")
    obj = bpy.data.objects.new("hedge_cluster", mesh)
    bpy.context.collection.objects.link(obj)
    for m in (m_stem, m_dk, m_mid, m_hi):
        obj.data.materials.append(m)

    bm = bmesh.new()
    # Base woody stems
    for sx, sy in ((-0.25, 0.0), (0.0, 0.04), (0.25, -0.03)):
        ret = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=5,
            radius1=0.055, radius2=0.032, depth=0.38,
            matrix=Matrix.Translation((sx, sy, 0.18)),
        )
        for v in ret["verts"]:
            for f in v.link_faces:
                f.material_index = 0

    # Organic leafy foliage lobes
    lobes = [
        (0.0, 0.0, 0.56, 0.56, 0.42, 0.44, 2),
        (-0.44, 0.08, 0.46, 0.42, 0.38, 0.36, 1),
        (0.45, -0.06, 0.48, 0.44, 0.36, 0.38, 3),
        (-0.18, -0.24, 0.44, 0.34, 0.32, 0.30, 3),
        (0.20, 0.22, 0.50, 0.36, 0.32, 0.32, 1),
        (0.02, 0.05, 0.78, 0.34, 0.30, 0.26, 3),
    ]
    for lx, ly, lz, rx, ry, rz, mat_i in lobes:
        ret = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
        for v in ret["verts"]:
            wob = 1.0 + rng.uniform(-0.22, 0.22)
            v.co = Vector((lx + v.co.x * rx * wob, ly + v.co.y * ry * wob, max(0.06, lz + v.co.z * rz * wob)))
            for f in v.link_faces:
                f.material_index = mat_i

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    export_glb("hedge_cluster.glb", [obj])


if __name__ == "__main__":
    build_grass_tuft()
    build_hedge_cluster()
