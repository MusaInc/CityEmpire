"""Repair shattered lower trunks on WorldState trees and optimize LODs + textures for mobile.

Root cause fixed:
  world_tree_oak_{near,far}.glb and world_tree_pine_{near,far}.glb had their lower trunks
  (z = 0..3.5 m) collapsed into ~6-14 degenerate/flipped triangles by aggressive decimation,
  leaving floating tree canopies over shattered stumps in planters and parks. In addition,
  oak_far and pine_far kept ~3,000 bark triangles each and embedded 2.36 MB bark textures.

This script:
  1. Preserves each species' exact scale, canopy silhouette, material slot names, and UVs.
  2. Rebuilds a solid, outward-normal, organically flared & tapered trunk + primary limb
     collars for oak and pine (and roots birch solidly to z = -0.25 m) so no trunk ever
     shatters or floats on slopes/planters.
  3. Decimates ONLY upper twigs/branches (protecting the solid trunk via vertex group) to
     lean mobile budgets (~750-950 near bark tris, ~180-240 far bark tris).
  4. Downscales oversized embedded bark/foliage textures to crisp mobile resolutions
     (near: 512 bark / 1024 foliage; far: 256 bark / 512 foliage).
"""

import math
import os
import bpy
import bmesh
from mathutils import Vector

MODELS_DIR = os.path.abspath("assets/models")

SPECIES_CFG = {
    "oak": {
        "rebuild_trunk": True,
        "cut_z": 2.15,          # remove degenerate bark tris strictly below this height
        "trunk_top_z": 2.95,    # extend solid trunk up into the primary bough crown
        "r_root": 0.42,
        "r_base": 0.30,
        "r_mid": 0.25,
        "r_top": 0.22,
        "bend": (0.06, -0.04),
        "near_bark_tris": 900,
        "far_bark_tris": 220,
        "near_foliage_tris": 1050,
        "far_foliage_tris": 180,
    },
    "pine": {
        "rebuild_trunk": True,
        "cut_z": 4.85,
        "trunk_top_z": 6.15,
        "r_root": 0.32,
        "r_base": 0.23,
        "r_mid": 0.19,
        "r_top": 0.15,
        "bend": (0.05, 0.04),
        "near_bark_tris": 800,
        "far_bark_tris": 200,
        "near_foliage_tris": 900,
        "far_foliage_tris": 148,
    },
    "birch": {
        "rebuild_trunk": False,
        "cut_z": 0.0,
        "trunk_top_z": 2.6,
        "r_root": 0.22,
        "r_base": 0.16,
        "r_mid": 0.14,
        "r_top": 0.12,
        "bend": (0.0, 0.0),
        "near_bark_tris": 850,
        "far_bark_tris": 220,
        "near_foliage_tris": 774,
        "far_foliage_tris": 96,
    },
}


def apply_all_transforms(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def find_bark_and_foliage():
    bark_obj = None
    fol_obj = None
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        mnames = " ".join(m.name.lower() for m in o.data.materials if m)
        if "bark" in mnames or "scaffold" in o.name.lower():
            bark_obj = o
        elif "foliage" in mnames or "canopy" in o.name.lower():
            fol_obj = o
    return bark_obj, fol_obj


def add_tapered_trunk(bm, uv_layer, z_bottom, z_top, r_root, r_base, r_mid, r_top,
                      bend_xy, sides, rings, top_center_xy):
    """Add a clean, outward-facing, organically flared trunk + root anchor."""
    ring_verts = []
    for ri in range(rings + 1):
        t = ri / float(rings)
        z = z_bottom + (z_top - z_bottom) * t
        # Smooth organic taper with root buttress flare near ground (z <= 0.5 m)
        if z < 0.0:
            r = r_root * 1.06
        elif z < 0.55:
            ft = z / 0.55
            r = r_root * (1.0 - ft) ** 1.6 + r_base * (1.0 - (1.0 - ft) ** 1.6)
        else:
            ut = (z - 0.55) / max(z_top - 0.55, 0.1)
            r = r_base * (1.0 - ut) ** 2 + 2.0 * r_mid * ut * (1.0 - ut) + r_top * ut ** 2

        # Gentle S-curve into the exact upper bough hub
        sway = math.sin(t * math.pi)
        cx = top_center_xy[0] * (t ** 1.3) + bend_xy[0] * sway
        cy = top_center_xy[1] * (t ** 1.3) + bend_xy[1] * sway

        rv = []
        for si in range(sides):
            ang = (si / float(sides)) * math.tau
            # Subtle root buttress fluting near ground, subtle bark irregularity above
            flute = 1.0
            if z < 0.7:
                flute += 0.12 * (1.0 - max(z, 0.0) / 0.7) * math.cos(ang * 4.0 + 0.5)
            flute += 0.03 * math.sin(ang * 3.0 + z * 1.9)
            x = cx + math.cos(ang) * r * flute
            y = cy + math.sin(ang) * r * flute
            rv.append(bm.verts.new((x, y, z)))
        ring_verts.append((rv, z))

    created_faces = []
    for ri in range(rings):
        r0, z0 = ring_verts[ri]
        r1, z1 = ring_verts[ri + 1]
        for si in range(sides):
            sn = (si + 1) % sides
            v00, v01 = r0[si], r0[sn]
            v11, v10 = r1[sn], r1[si]
            f = bm.faces.new((v00, v01, v11, v10))
            f.smooth = True
            u0 = si / float(sides)
            u1 = (si + 1) / float(sides)
            uvs = [(u0, z0 * 0.45), (u1, z0 * 0.45), (u1, z1 * 0.45), (u0, z1 * 0.45)]
            for loop, uv in zip(f.loops, uvs):
                loop[uv_layer].uv = uv
            created_faces.append(f)

    # Cap top cleanly inside the bough junction so looking up never sees a hollow tube
    top_rv = ring_verts[-1][0]
    top_cap = bm.faces.new(top_rv)
    top_cap.smooth = True
    created_faces.append(top_cap)
    return created_faces


def add_limb_bridge(bm, uv_layer, p0, p1, r0, r1, sides=6):
    """Connect trunk top cleanly to a primary bough cluster."""
    d = p1 - p0
    length = d.length
    if length < 0.15:
        return []
    z_axis = d.normalized()
    ref = Vector((0, 0, 1)) if abs(z_axis.z) < 0.9 else Vector((1, 0, 0))
    x_axis = z_axis.cross(ref).normalized()
    y_axis = z_axis.cross(x_axis).normalized()

    rings_v = []
    for ri, (t, rad) in enumerate([(0.0, r0), (0.5, 0.5 * (r0 + r1)), (1.0, r1)]):
        c = p0.lerp(p1, t)
        rv = []
        for si in range(sides):
            ang = (si / float(sides)) * math.tau
            pt = c + (x_axis * math.cos(ang) + y_axis * math.sin(ang)) * rad
            rv.append(bm.verts.new(pt))
        rings_v.append((rv, t * length))

    faces = []
    for ri in range(len(rings_v) - 1):
        a, za = rings_v[ri]
        b, zb = rings_v[ri + 1]
        for si in range(sides):
            sn = (si + 1) % sides
            f = bm.faces.new((a[si], a[sn], b[sn], b[si]))
            f.smooth = True
            u0 = si / float(sides)
            u1 = (si + 1) / float(sides)
            for loop, uv in zip(f.loops, [(u0, za * 0.5), (u1, za * 0.5), (u1, zb * 0.5), (u0, zb * 0.5)]):
                loop[uv_layer].uv = uv
            faces.append(f)
    return faces


def decimate_mesh(obj, target_tris, protect_z_below=None):
    """Decimate mesh to target_tris while optionally protecting vertices below protect_z_below."""
    me = obj.data
    cur_tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if cur_tris <= target_tris:
        return
    ratio = max(0.04, min(0.98, target_tris / float(cur_tris)))

    vg_name = None
    if protect_z_below is not None:
        vg = obj.vertex_groups.new(name="UpperOnly")
        upper_ids = [v.index for v in me.vertices if v.co.z >= protect_z_below]
        if upper_ids:
            vg.add(upper_ids, 1.0, "REPLACE")
            vg_name = vg.name

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    mod = obj.modifiers.new(name="MobileDecimate", type="DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    if vg_name:
        mod.vertex_group = vg_name
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.select_set(False)
    if vg_name:
        obj.vertex_groups.remove(obj.vertex_groups[vg_name])


def trim_foliage_cards(fol_obj, target_tris):
    """Drop small/redundant leaf cards uniformly to hit mobile triangle budget cleanly."""
    bm = bmesh.new()
    bm.from_mesh(fol_obj.data)
    bm.faces.ensure_lookup_table()
    # Triangulate first so face count == tri count
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.faces.ensure_lookup_table()
    cur = len(bm.faces)
    if cur <= target_tris:
        bm.free()
        return

    # Group connected components (each leaf card is a 2-tri quad island)
    visited = set()
    islands = []
    for f in bm.faces:
        if f.index in visited:
            continue
        stack = [f]
        comp = []
        visited.add(f.index)
        while stack:
            cf = stack.pop()
            comp.append(cf)
            for e in cf.edges:
                for lf in e.link_faces:
                    if lf.index not in visited:
                        visited.add(lf.index)
                        stack.append(lf)
        # Keep larger/outer silhouette cards preferentially by deterministic spatial hash + area
        center = sum((v.co for cf in comp for v in cf.verts), Vector()) / max(1, sum(len(cf.verts) for cf in comp))
        area = sum(cf.calc_area() for cf in comp)
        islands.append((comp, center, area))

    keep_ratio = target_tris / float(cur)
    # Sort deterministically by angle + height so dropping removes evenly around the crown
    islands.sort(key=lambda item: (round(math.atan2(item[1].y, item[1].x), 2), round(item[1].z, 2)))
    n_keep = max(8, int(round(len(islands) * keep_ratio)))
    # Evenly spaced stride selection preserves uniform canopy fullness
    keep_idx = set(int(round(i * (len(islands) - 1) / max(1, n_keep - 1))) for i in range(n_keep))
    del_faces = []
    for idx, (comp, _, _) in enumerate(islands):
        if idx not in keep_idx:
            del_faces.extend(comp)
    if del_faces:
        bmesh.ops.delete(bm, geom=del_faces, context="FACES")
    bm.to_mesh(fol_obj.data)
    bm.free()
    fol_obj.data.update()


def resize_images(is_far):
    bark_max = 256 if is_far else 512
    fol_max = 512 if is_far else 1024
    for img in bpy.data.images:
        if img.size[0] == 0 or img.size[1] == 0:
            continue
        is_bark = "bark" in img.name.lower()
        lim = bark_max if is_bark else fol_max
        w, h = img.size[0], img.size[1]
        if max(w, h) > lim:
            # Touch pixels before scaling so Blender keeps the buffer in memory
            _ = img.pixels[0]
            scale = lim / float(max(w, h))
            nw = max(64, int(round(w * scale)))
            nh = max(64, int(round(h * scale)))
            img.scale(nw, nh)
            img.update()
            img.pack()
        elif is_bark and img.file_format != "JPEG":
            img.file_format = "JPEG"


def process_tree(species, lod):
    cfg = SPECIES_CFG[species]
    is_far = (lod == "far")
    glb_path = os.path.join(MODELS_DIR, f"world_tree_{species}_{lod}.glb")
    if not os.path.exists(glb_path):
        print(f"SKIP missing {glb_path}")
        return

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)

    bark_obj, fol_obj = find_bark_and_foliage()
    if bark_obj is None or fol_obj is None:
        print(f"ERROR missing bark/foliage in {glb_path}")
        return

    # Unparent while preserving world transform so coordinates are clean Z-up meters
    for o in [bark_obj, fol_obj]:
        mat = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mat
        apply_all_transforms(o)

    # Remove empty parent objects left over from glTF import
    for o in list(bpy.data.objects):
        if o not in (bark_obj, fol_obj):
            bpy.data.objects.remove(o, do_unlink=True)

    # 1. Repair bark trunk & decimate upper twigs
    if cfg["rebuild_trunk"]:
        bm = bmesh.new()
        bm.from_mesh(bark_obj.data)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        uv_layer = bm.loops.layers.uv.verify()

        cut_z = cfg["cut_z"]
        # Find where the upper bough hub is centered right above cut_z
        band_pts = [v.co.copy() for v in bm.verts if cut_z <= v.co.z <= cut_z + 1.8]
        if band_pts:
            # Nearest-to-axis cluster gives the true central trunk/bough hub
            core_pts = sorted(band_pts, key=lambda p: p.x * p.x + p.y * p.y)[:max(6, len(band_pts) // 4)]
            cx = sum(p.x for p in core_pts) / len(core_pts)
            cy = sum(p.y for p in core_pts) / len(core_pts)
            cx = max(-0.35, min(0.35, cx))
            cy = max(-0.35, min(0.35, cy))
        else:
            cx, cy = 0.0, 0.0

        # Delete the broken/shattered faces below cut_z
        bad_faces = [f for f in bm.faces if all(v.co.z < cut_z + 0.35 for v in f.verts)
                     or min(v.co.z for v in f.verts) < cut_z - 0.15]
        if bad_faces:
            bmesh.ops.delete(bm, geom=bad_faces, context="FACES")

        # Clean loose verts
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")

        # Build solid, continuous, flared trunk from z=-0.25m up into the bough crown
        sides = 6 if is_far else 10
        rings = 5 if is_far else 9
        add_tapered_trunk(
            bm, uv_layer,
            z_bottom=-0.28,
            z_top=cfg["trunk_top_z"],
            r_root=cfg["r_root"],
            r_base=cfg["r_base"],
            r_mid=cfg["r_mid"],
            r_top=cfg["r_top"],
            bend_xy=cfg["bend"],
            sides=sides,
            rings=rings,
            top_center_xy=(cx, cy),
        )

        # Bridge from trunk collar out into 4 compass quadrants of the lower boughs
        # so the trunk flows naturally into the upper crown limbs with zero floating gaps.
        hub = Vector((cx, cy, cfg["trunk_top_z"] - 0.30))
        bough_candidates = [v.co.copy() for v in bm.verts
                            if cfg["trunk_top_z"] - 0.2 <= v.co.z <= cfg["trunk_top_z"] + 1.6
                            and (v.co.x - cx) ** 2 + (v.co.y - cy) ** 2 > 0.35 ** 2]
        if bough_candidates:
            for qi in range(4):
                q_ang0 = qi * (math.pi * 0.5) - math.pi
                q_ang1 = q_ang0 + math.pi * 0.5
                q_pts = [p for p in bough_candidates
                         if q_ang0 <= math.atan2(p.y - cy, p.x - cx) < q_ang1]
                if not q_pts:
                    continue
                # Aim at an inner/lower point in this quadrant's bough cluster
                q_pts.sort(key=lambda p: (p - hub).length)
                target = q_pts[min(len(q_pts) - 1, len(q_pts) // 3)]
                # Clamp reach so bridges stay chunky and natural
                vec = target - hub
                if vec.length > 1.8:
                    target = hub + vec.normalized() * 1.8
                add_limb_bridge(
                    bm, uv_layer, hub, target,
                    r0=cfg["r_top"] * 0.72,
                    r1=cfg["r_top"] * 0.38,
                    sides=5 if is_far else 7,
                )

        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(bark_obj.data)
        bm.free()
        bark_obj.data.update()

        # Decimate ONLY upper twigs/branches above trunk_top_z so our solid trunk stays pristine
        target_bark = cfg["far_bark_tris"] if is_far else cfg["near_bark_tris"]
        decimate_mesh(bark_obj, target_bark, protect_z_below=cfg["trunk_top_z"] + 0.15)
    else:
        # Birch: extend base slightly below ground (-0.22m) so it never floats on sloped curbs,
        # recalculate normals, and decimate upper branches to mobile budget.
        bm = bmesh.new()
        bm.from_mesh(bark_obj.data)
        for v in bm.verts:
            if v.co.z < 0.08:
                v.co.z -= 0.22
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(bark_obj.data)
        bm.free()
        bark_obj.data.update()
        target_bark = cfg["far_bark_tris"] if is_far else cfg["near_bark_tris"]
        decimate_mesh(bark_obj, target_bark, protect_z_below=2.4)

    # Ensure smooth shading on bark
    for p in bark_obj.data.polygons:
        p.use_smooth = True

    # 2. Trim foliage to mobile triangle budget
    target_fol = cfg["far_foliage_tris"] if is_far else cfg["near_foliage_tris"]
    trim_foliage_cards(fol_obj, target_fol)

    # 3. Downscale embedded textures for mobile VRAM & IPA size
    resize_images(is_far)

    bark_tris = sum(len(p.vertices) - 2 for p in bark_obj.data.polygons)
    fol_tris = sum(len(p.vertices) - 2 for p in fol_obj.data.polygons)

    # Export clean glTF binary with Bark + Foliage meshes
    bpy.ops.object.select_all(action="DESELECT")
    bark_obj.select_set(True)
    fol_obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_jpeg_quality=84,
        export_yup=True,
    )
    sz_kb = os.path.getsize(glb_path) / 1024.0
    print(f"OK {species}_{lod}: bark={bark_tris} tris, foliage={fol_tris} tris, size={sz_kb:.0f} KB")


def main():
    for species in ("oak", "pine", "birch"):
        for lod in ("near", "far"):
            process_tree(species, lod)


if __name__ == "__main__":
    main()
