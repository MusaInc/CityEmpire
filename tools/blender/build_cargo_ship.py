"""Build a detailed, mobile-efficient cargo container ship in Blender.
Exports assets/models/cargo_ship.glb (canonical 100 m length, facing -Y in Blender -> -Z in glTF,
waterline at Z=0, max mast air-draft ~16.8 m at 100 m length so even a 115 m port ship clears
the 22 m railway bridge and 24 m suspension bridge cleanly).
Run: blender -b --factory-startup --python tools/blender/build_cargo_ship.py
"""
import math
import os
import random
import bpy
import bmesh
from mathutils import Matrix, Vector

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "cargo_ship.glb"))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_mat(name, rgba, rough=0.6, metallic=0.1, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgba, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metallic
        if alpha < 0.99:
            bsdf.inputs["Alpha"].default_value = alpha
            m.blend_method = "BLEND"
    return m


def add_box(bm, center, size, mat_idx, rot_euler=(0.0, 0.0, 0.0)):
    sx, sy, sz = size
    m = Matrix.Translation(center) @ Matrix.Rotation(rot_euler[2], 4, "Z") @ Matrix.Rotation(rot_euler[1], 4, "Y") @ Matrix.Rotation(rot_euler[0], 4, "X") @ Matrix.Diagonal((sx, sy, sz, 1.0))
    ret = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    for v in ret["verts"]:
        for f in v.link_faces:
            f.material_index = mat_idx


def add_cyl(bm, center, r1, r2, depth, segs, mat_idx, rot_euler=(0.0, 0.0, 0.0)):
    m = Matrix.Translation(center) @ Matrix.Rotation(rot_euler[2], 4, "Z") @ Matrix.Rotation(rot_euler[1], 4, "Y") @ Matrix.Rotation(rot_euler[0], 4, "X")
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth, matrix=m)
    for v in ret["verts"]:
        for f in v.link_faces:
            f.material_index = mat_idx


def build_hull(bm, length, beam, m_boot, m_hull, m_deck, m_rust):
    """Sculpted flared cargo hull with bulbous bow, sheer line, transom stern, and forecastle."""
    # Stations along Y from bow (-L/2) to stern (+L/2)
    # Each station: (y_frac, half_beam_keel, half_beam_wl, half_beam_deck, z_deck)
    stations = [
        (-0.500, 0.00, 0.00, 0.02, 7.6),   # bow stem tip
        (-0.465, 0.08, 0.22, 0.42, 7.3),   # flared bow
        (-0.400, 0.34, 0.62, 0.80, 6.8),   # forward shoulder
        (-0.310, 0.72, 0.94, 1.00, 6.1),   # transition to parallel midbody
        (-0.180, 0.90, 1.00, 1.00, 5.8),
        ( 0.180, 0.90, 1.00, 1.00, 5.8),
        ( 0.340, 0.72, 0.96, 0.98, 5.9),   # aft run
        ( 0.445, 0.36, 0.76, 0.88, 6.1),
        ( 0.500, 0.18, 0.56, 0.78, 6.2),   # transom stern
    ]
    hb = beam * 0.5
    rings = []
    for yf, bk, bw, bd, zd in stations:
        y = yf * length
        # 5-point cross-section (port deck -> port wl -> keel -> stbd wl -> stbd deck)
        ring = [
            bm.verts.new((-bd * hb, y, zd)),
            bm.verts.new((-bw * hb, y, 0.8)),
            bm.verts.new((-bk * hb, y, -2.4)),
            bm.verts.new(( bk * hb, y, -2.4)),
            bm.verts.new(( bw * hb, y, 0.8)),
            bm.verts.new(( bd * hb, y, zd)),
        ]
        rings.append(ring)

    # Loft hull sides, bottom, and deck
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for j in range(5):
            try:
                f = bm.faces.new((r0[j], r0[j + 1], r1[j + 1], r1[j]))
                # j==0 and j==4 are upper topsides; j==1,2,3 are red anti-fouling boot-top/bottom
                f.material_index = m_hull if j in (0, 4) else m_boot
            except ValueError:
                pass
        # Main deck quad
        try:
            fd = bm.faces.new((r0[5], r0[0], r1[0], r1[5]))
            fd.material_index = m_deck
        except ValueError:
            pass

    # Cap transom stern
    rt = rings[-1]
    try:
        ft1 = bm.faces.new((rt[0], rt[1], rt[4], rt[5]))
        ft1.material_index = m_hull
        ft2 = bm.faces.new((rt[1], rt[2], rt[3], rt[4]))
        ft2.material_index = m_boot
    except ValueError:
        pass

    # Bulbous bow protruding at waterline
    add_cyl(bm, (0.0, -length * 0.495, -0.8), 1.05, 0.45, 5.2, 8, m_boot, rot_euler=(math.radians(90), 0, 0))

    # Gunwale bulwark / coaming along port & starboard midbody
    for side in (-1.0, 1.0):
        add_box(bm, (side * (hb - 0.18), 0.0, 6.25), (0.34, length * 0.64, 0.90), m_hull)
        # Subtle weathered rub-rail / rust strake along midbody
        add_box(bm, (side * (hb + 0.04), 0.0, 2.4), (0.12, length * 0.62, 0.35), m_rust)

    # Forecastle deckhouse, breakwater, anchor windlass & recessed anchors
    add_box(bm, (0.0, -length * 0.40, 7.15), (beam * 0.56, 7.5, 1.2), m_hull)
    add_box(bm, (0.0, -length * 0.36, 8.1), (beam * 0.58, 0.6, 1.2), m_hull)  # breakwater
    add_cyl(bm, (0.0, -length * 0.42, 8.0), 0.55, 0.55, 1.6, 8, m_rust, rot_euler=(0, math.radians(90), 0))  # windlass
    # Forward mast
    add_cyl(bm, (0.0, -length * 0.45, 10.6), 0.22, 0.12, 5.6, 6, m_deck)
    # Port & starboard anchors in hawsepipes
    for side in (-1.0, 1.0):
        ax = side * (hb * 0.56)
        ay = -length * 0.425
        add_box(bm, (ax, ay, 4.6), (0.35, 0.45, 1.65), m_rust)
        add_box(bm, (ax, ay, 3.8), (0.42, 1.35, 0.45), m_rust)


def build_cargo_ship():
    reset()
    rng = random.Random(20261124)

    # Weathered maritime PBR materials
    mats = [
        make_mat("boot_red", (0.42, 0.10, 0.08), 0.68, 0.15),       # 0
        make_mat("hull_navy", (0.09, 0.13, 0.18), 0.56, 0.28),      # 1
        make_mat("deck_grey", (0.24, 0.26, 0.27), 0.84, 0.10),      # 2
        make_mat("rust_steel", (0.28, 0.19, 0.14), 0.88, 0.35),     # 3
        make_mat("super_white", (0.84, 0.83, 0.80), 0.52, 0.08),    # 4
        make_mat("bridge_glass", (0.05, 0.09, 0.12), 0.08, 0.15, alpha=0.68),  # 5
        make_mat("crane_ochre", (0.72, 0.52, 0.14), 0.48, 0.32),    # 6
        make_mat("funnel_stripe", (0.76, 0.22, 0.12), 0.46, 0.22),  # 7
        make_mat("lifeboat_org", (0.86, 0.30, 0.06), 0.38, 0.10),   # 8
        make_mat("railing", (0.76, 0.77, 0.78), 0.42, 0.65),        # 9
        # Weathered shipping container palette (10..15)
        make_mat("box_rust", (0.56, 0.16, 0.12), 0.70, 0.22),       # 10
        make_mat("box_blue", (0.14, 0.29, 0.46), 0.68, 0.22),       # 11
        make_mat("box_green", (0.15, 0.36, 0.24), 0.72, 0.20),      # 12
        make_mat("box_ochre", (0.68, 0.48, 0.14), 0.70, 0.20),      # 13
        make_mat("box_slate", (0.34, 0.37, 0.40), 0.74, 0.22),      # 14
        make_mat("box_cream", (0.74, 0.71, 0.64), 0.74, 0.16),      # 15
    ]

    mesh = bpy.data.meshes.new("cargo_ship")
    obj = bpy.data.objects.new("cargo_ship", mesh)
    bpy.context.collection.objects.link(obj)
    for m in mats:
        obj.data.materials.append(m)

    bm = bmesh.new()
    L = 100.0
    B = 16.5

    # 1. Sculpted hull, forecastle, anchors
    build_hull(bm, L, B, 0, 1, 2, 3)

    # 2. Hatch coamings & multi-bay corrugated shipping container stacks
    bay_ys = [-27.0, -14.5, -2.0, 10.5]
    for bi, by in enumerate(bay_ys):
        # Steel hatch cover coaming under each bay
        add_box(bm, (0.0, by, 6.25), (B - 2.2, 11.4, 0.9), 3)
        # 5 container columns across the beam
        for col in range(5):
            cx = -5.4 + col * 2.7
            tiers = rng.randint(2, 3) if bi > 0 else rng.randint(1, 2)
            for t in range(tiers):
                cz = 7.85 + t * 2.35
                cmat = 10 + rng.randint(0, 5)
                # Main container box
                add_box(bm, (cx, by, cz), (2.42, 11.2, 2.26), cmat)
                # Subtle structural corner posts / top rail trim for non-blocky silhouette
                add_box(bm, (cx, by, cz + 1.13), (2.46, 11.24, 0.08), 3)

    # 3. Articulated maritime deck cranes between container bays
    for cy in (-20.75, 4.25):
        # Crane pedestal column
        add_cyl(bm, (0.0, cy, 9.8), 1.15, 0.95, 7.6, 8, 6)
        # Slewing crane house + operator cab
        add_box(bm, (0.0, cy + 0.3, 14.2), (2.2, 3.0, 2.2), 6)
        add_box(bm, (1.25, cy - 0.4, 14.3), (0.8, 1.3, 1.2), 5)
        # Long angled crane jib boom resting forward over the containers
        add_box(bm, (0.0, cy - 5.8, 15.8), (0.65, 13.0, 0.72), 6, rot_euler=(math.radians(-12), 0, 0))
        # Crane hook block
        add_box(bm, (0.0, cy - 11.2, 14.0), (0.45, 0.55, 0.75), 3)

    # 4. Aft tiered accommodation superstructure & bridge
    sz = 29.0
    # Lower deckhouses (3 stepped tiers)
    add_box(bm, (0.0, sz, 8.8), (B * 0.76, 11.5, 5.8), 4)
    add_box(bm, (0.0, sz + 0.4, 13.0), (B * 0.68, 9.6, 3.2), 4)
    # Recessed dark-glass wheelhouse / navigation bridge + wrap-around bridge wings
    add_box(bm, (0.0, sz - 0.8, 15.6), (B * 0.64, 5.2, 2.2), 4)
    # Bridge panoramic windows (slightly proud of dark interior backing)
    add_box(bm, (0.0, sz - 3.45, 15.8), (B * 0.60, 0.22, 1.05), 5)
    for side in (-1.0, 1.0):
        add_box(bm, (side * (B * 0.32 + 0.05), sz - 1.4, 15.8), (0.20, 3.8, 1.05), 5)
    # Wide bridge wings extending past the beam
    add_box(bm, (0.0, sz - 2.0, 15.0), (B + 2.2, 2.4, 1.15), 4)
    # Bridge wing safety railings
    add_box(bm, (0.0, sz - 3.15, 15.9), (B + 2.1, 0.10, 0.75), 9)
    # Porthole window strips on accommodation tiers
    for zy in (9.6, 11.8, 13.6):
        add_box(bm, (0.0, sz - 5.80 if zy < 12.5 else sz - 4.45, zy), (B * 0.58, 0.14, 0.55), 5)

    # 5. Funnel with livery band & twin exhaust pipes
    add_box(bm, (0.0, sz + 5.8, 14.5), (3.4, 5.2, 5.6), 1)
    add_box(bm, (0.0, sz + 5.8, 16.0), (3.52, 5.32, 1.25), 7)
    add_box(bm, (0.0, sz + 5.8, 17.4), (3.3, 4.9, 0.55), 3)
    for ex in (-0.7, 0.7):
        add_cyl(bm, (ex, sz + 6.4, 18.0), 0.34, 0.30, 1.1, 8, 3)

    # 6. Radar mast & scanner crossbar (kept compact so port ship clears 22 m bridge!)
    add_cyl(bm, (0.0, sz - 1.2, 18.2), 0.28, 0.14, 3.6, 6, 4)
    add_box(bm, (0.0, sz - 1.2, 19.2), (4.6, 0.22, 0.22), 9)  # radar yardarm
    add_box(bm, (0.0, sz - 1.6, 19.7), (1.8, 0.28, 0.24), 4)  # X-band radar scanner

    # 7. Free-fall / davit orange lifeboats on port & starboard sides
    for side in (-1.0, 1.0):
        add_box(bm, (side * (B * 0.42), sz + 1.5, 10.4), (1.6, 4.6, 1.35), 8)
        # Davit arms
        for dy in (-1.6, 1.6):
            add_box(bm, (side * (B * 0.40), sz + 1.5 + dy, 11.2), (0.35, 0.28, 1.4), 9)

    # 8. Deck safety railings along port & starboard gunwales + aft stern
    for side in (-1.0, 1.0):
        add_box(bm, (side * (B * 0.49), 0.0, 7.05), (0.08, L * 0.62, 0.10), 9)
        for ry in range(-28, 32, 6):
            add_box(bm, (side * (B * 0.49), float(ry), 6.65), (0.08, 0.08, 0.80), 9)
    # Stern mooring bollards
    for sx in (-4.2, -1.8, 1.8, 4.2):
        add_cyl(bm, (sx, L * 0.46, 6.55), 0.26, 0.24, 0.75, 6, 3)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    print(f"CARGO_SHIP_EXPORTED {OUT} tris={sum(len(p.vertices)-2 for p in mesh.polygons)}")


if __name__ == "__main__":
    build_cargo_ship()
