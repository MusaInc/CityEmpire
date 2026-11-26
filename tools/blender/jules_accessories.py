"""Fit Jules's existing hoops, crew socks and fixed updo to the character."""
import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Vector

from build_b_surface import surface_detail
from hero_groom import eye_centre, mesh_tree, ribbon, strand_opacity, tied_freedom
from wardrobe_quality import adjust_basis, smooth


def fit_hoops(face):
    """Rebuild Jules's 18k gold hoops cleanly hanging naturally from her actual
    pierced earlobes (outward normals, clean Y-Z hang with subtle 10-deg cant)."""
    material = face.data.materials.find('hero_earring_gold')
    skin_slot = face.data.materials.find('hero_skin_face_jules')
    if material < 0 or skin_slot < 0:
        return
    skin = mesh_tree(face.data, skin_slot)
    eye = eye_centre(face)

    bm = bmesh.new()
    bm.from_mesh(face.data)
    old_hoops = [v for f in bm.faces if f.material_index == material for v in f.verts]
    if old_hoops:
        bmesh.ops.delete(bm, geom=list(set(old_hoops)), context='VERTS')

    shapes = list(bm.verts.layers.shape.values())
    deform = bm.verts.layers.deform.verify()
    uv_l = bm.loops.layers.uv.get('SurfaceUV') or bm.loops.layers.uv.active
    fr_l = bm.loops.layers.uv.get('ClothFreedom')
    head_g = face.vertex_groups['b_head'].index

    maj_seg, min_seg = 36, 12
    maj_r, min_r = 0.0124, 0.00145
    new_faces = []
    for sign in (-1, 1):
        # Locate actual earlobe underside/outer surface via multi-height probe.
        best_anchor = None
        for dz_try in (-0.042, -0.044, -0.046, -0.040):
            for dy_try in (-0.060, -0.063, -0.057):
                hit, _, _, _ = skin.ray_cast(Vector((sign * 0.16, eye.y + dy_try, eye.z + dz_try)), Vector((-sign, 0, 0)), 0.12)
                if hit is not None and abs(hit.x) > 0.066:
                    best_anchor = hit
                    break
            if best_anchor is not None:
                break
        if best_anchor is None:
            continue
        # Hang naturally vertically in the Y-Z plane with a subtle 10-degree outward cant.
        cant = math.radians(10.0 * sign)
        nx_plane = Vector((math.cos(cant), 0.0, math.sin(cant)))
        ez_plane = Vector((-math.sin(cant), 0.0, math.cos(cant)))
        ey_plane = Vector((0.0, 1.0, 0.0))
        # Top of hoop pierces cleanly through the earlobe center; ring hangs directly below it.
        ring_center = best_anchor + Vector((sign * 0.0005, 0.0, 0.0010)) - ez_plane * maj_r

        rings = []
        for i in range(maj_seg):
            a = math.tau * i / maj_seg
            radial = ey_plane * math.cos(a) + ez_plane * math.sin(a)
            spine_pt = ring_center + radial * maj_r
            row = []
            for j in range(min_seg):
                b = math.tau * j / min_seg
                pt = spine_pt + (radial * math.cos(b) + nx_plane * math.sin(b)) * min_r
                v = bm.verts.new(pt)
                v[deform][head_g] = 1.0
                for layer in shapes:
                    v[layer] = pt
                row.append(v)
            rings.append(row)
        for i in range(maj_seg):
            inext = (i + 1) % maj_seg
            for j in range(min_seg):
                jnext = (j + 1) % min_seg
                f = bm.faces.new((rings[i][j], rings[inext][j], rings[inext][jnext], rings[i][jnext]))
                f.material_index = material
                f.smooth = True
                for lp in f.loops:
                    if uv_l is not None:
                        lp[uv_l].uv = (i / maj_seg, j / min_seg)
                    if fr_l is not None:
                        lp[fr_l].uv = (0.0, 1.0)
                new_faces.append(f)

    if new_faces:
        bmesh.ops.recalc_face_normals(bm, faces=new_faces)
    bm.to_mesh(face.data)
    bm.free()
    # Remove any stray duplicate ClothFreedom.001 UV layer so SurfaceUV + ClothFreedom stay clean.
    for uv_name in [u.name for u in face.data.uv_layers if u.name.startswith('ClothFreedom.')]:
        face.data.uv_layers.remove(face.data.uv_layers[uv_name])

    mat = face.data.materials[material]
    if mat and mat.use_nodes:
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        if bsdf is not None:
            bsdf.inputs['Base Color'].default_value = (0.92, 0.74, 0.34, 1.0)
            bsdf.inputs['Metallic'].default_value = 0.86
            bsdf.inputs['Roughness'].default_value = 0.22
            if 'Specular IOR Level' in bsdf.inputs:
                bsdf.inputs['Specular IOR Level'].default_value = 0.65
    face.data.update()


def refit_necklaces(collection):
    """Rebuild all Jules necklaces AFTER final shoulder/chest/neck shaping so every
    chain drapes flush against the real neck and collarbone skin (ZERO floating or kinks!)."""
    from garment_kit import weights_from
    from wardrobe_quality import surface_tree

    models = collection.models
    face = models['Face_jules']
    torso = models['Fashion_Torso_Skin']
    crop_skin = models.get('Fashion_Crop_Skin')
    skin_trees = [surface_tree(ob.data) for ob in (face, torso, crop_skin) if ob is not None]

    # Measure true neck center at z = 1.445.
    neck_pts = [v.co for v in face.data.vertices if 1.43 < v.co.z < 1.47 and abs(v.co.x) < 0.08]
    nc_y = sum(p.y for p in neck_pts) / len(neck_pts) if neck_pts else 0.015

    specs = (
        ('day', (0.93, 0.76, 0.38), 0.052, 0.0012, 0.0062),
        ('street', (0.84, 0.86, 0.90), 0.036, 0.0018, 0.0056),
        ('office', (0.88, 0.69, 0.30), 0.058, 0.0012, 0.0064),
        ('evening', (0.94, 0.78, 0.40), 0.066, 0.0013, 0.0070),
    )

    def probe_skin(pt, d_radial):
        """Find outermost skin surface across Face_jules, Fashion_Torso_Skin & Fashion_Crop_Skin."""
        origin = Vector((0.0, nc_y, pt.z)) + d_radial * 0.28
        cands = []
        for tr in skin_trees:
            h = tr.ray_cast(origin, -d_radial, 0.32)
            if h[0] is not None and h[1].length > 1e-4:
                cands.append((h[0], h[1].normalized(), (h[0] - Vector((0.0, nc_y, pt.z))).dot(d_radial)))
        if cands:
            best = max(cands, key=lambda item: item[2])
            return best[0], best[1]
        best_n = None
        for tr in skin_trees:
            n = tr.find_nearest(pt)
            if n[0] is not None and (best_n is None or n[3] < best_n[3]):
                best_n = n
        if best_n is not None:
            return best_n[0], best_n[1].normalized()
        return pt, d_radial

    def enforce_surface_clearance(pt, min_gap):
        """Push point strictly outward along the nearest skin normal across ALL skin meshes."""
        cur = pt.copy()
        for _ in range(3):
            worst_push = Vector()
            for tr in skin_trees:
                hit, nrm, _, dist = tr.find_nearest(cur)
                if hit is not None and nrm.length > 1e-4 and dist < 0.025:
                    n_u = nrm.normalized()
                    gap = (cur - hit).dot(n_u)
                    if gap < min_gap:
                        push = n_u * (min_gap - gap)
                        if push.length > worst_push.length:
                            worst_push = push
            if worst_push.length < 1e-6:
                break
            cur += worst_push
        return cur

    for style, colour, drop, wire_r, pend_r in specs:
        obj = models.get('JulesAccessory_' + style)
        if obj is None:
            continue
        n_seg = 64
        centres = []
        normals = []
        # Seat chain snugly right onto the collarbone/neck skin (wire_r + 1.1mm clearance -> zero hovering & zero clipping!).
        min_center_gap = wire_r + 0.0011
        for j in range(n_seg):
            a = math.tau * j / n_seg  # 0 = front center sternum, pi = back of neck
            front = 0.5 * (1.0 + math.cos(a))
            d_rad = Vector((math.sin(a), math.cos(a), 0.0))
            z = 1.454 - drop * (front ** 2.2) - 0.016 * (1.0 - abs(math.cos(a)))
            hit, nrm = probe_skin(Vector((0.0, nc_y, z)) + d_rad * 0.07, d_rad)
            pt = enforce_surface_clearance(hit + nrm * min_center_gap, min_center_gap)
            centres.append(pt)
            normals.append(nrm)

        # Smooth centreline radially & vertically 6 passes while strictly maintaining clearance over ALL skins!
        for _ in range(6):
            nxt = []
            for j in range(n_seg):
                sm = centres[(j - 1) % n_seg] * 0.25 + centres[j] * 0.50 + centres[(j + 1) % n_seg] * 0.25
                sm = enforce_surface_clearance(sm, min_center_gap)
                nxt.append(sm)
            centres = nxt

        bm = bmesh.new()
        uv_l = bm.loops.layers.uv.new('SurfaceUV')
        fr_l = bm.loops.layers.uv.new('ClothFreedom')
        sides = 10
        rings = []
        for j in range(n_seg):
            p_c = centres[j]
            tang = (centres[(j + 1) % n_seg] - centres[(j - 1) % n_seg]).normalized()
            n_c = normals[j]
            b_c = tang.cross(n_c)
            if b_c.length < 1e-4:
                b_c = Vector((0.0, 0.0, 1.0))
            else:
                b_c.normalize()
            n_c = b_c.cross(tang).normalized()
            row = []
            for k in range(sides):
                ang = math.tau * k / sides
                v = bm.verts.new(p_c + (n_c * math.cos(ang) + b_c * math.sin(ang)) * wire_r)
                row.append(v)
            rings.append(row)
        chain_faces = []
        for j in range(n_seg):
            jn = (j + 1) % n_seg
            for k in range(sides):
                kn = (k + 1) % sides
                f = bm.faces.new((rings[j][k], rings[jn][k], rings[jn][kn], rings[j][kn]))
                f.smooth = True
                for lp in f.loops:
                    lp[uv_l].uv = (j / n_seg, k / sides)
                    lp[fr_l].uv = (0.0, 1.0)
                chain_faces.append(f)

        # Clean domed, beveled 3D medallion pendant (closed uv-ellipsoid: ZERO edge normal flips, ZERO z-fighting!).
        p0 = centres[0] + Vector((0.0, 0.0, -pend_r * 0.92))
        p_hit, p_nrm = probe_skin(p0, Vector((0.0, 1.0, 0.0)))
        p_pos = enforce_surface_clearance(p_hit + p_nrm * (0.0018 + 0.0009), 0.0025)
        px_ax = Vector((1.0, 0.0, 0.0))
        pz_ax = px_ax.cross(p_nrm).normalized()
        p_lat, p_lon = 8, 18
        pend_rings = []
        for i in range(1, p_lat):
            phi = math.pi * i / p_lat  # 0 (front dome) .. pi (back dome)
            sp, cp = math.sin(phi), math.cos(phi)
            row = []
            for k in range(p_lon):
                ang = math.tau * k / p_lon
                pt = (p_pos
                      + px_ax * (math.cos(ang) * sp * pend_r)
                      + pz_ax * (math.sin(ang) * sp * pend_r * 1.12)
                      + p_nrm * (cp * 0.0016))
                row.append(bm.verts.new(pt))
            pend_rings.append(row)
        v_front = bm.verts.new(p_pos + p_nrm * 0.0016)
        v_back = bm.verts.new(p_pos - p_nrm * 0.0016)
        pend_faces = []
        for k in range(p_lon):
            kn = (k + 1) % p_lon
            f0 = bm.faces.new((v_front, pend_rings[0][k], pend_rings[0][kn]))
            f0.smooth = True
            pend_faces.append(f0)
            for i in range(len(pend_rings) - 1):
                fi = bm.faces.new((pend_rings[i][k], pend_rings[i + 1][k], pend_rings[i + 1][kn], pend_rings[i][kn]))
                fi.smooth = True
                pend_faces.append(fi)
            f1 = bm.faces.new((pend_rings[-1][k], v_back, pend_rings[-1][kn]))
            f1.smooth = True
            pend_faces.append(f1)
        for f in pend_faces:
            for lp in f.loops:
                lp[uv_l].uv = (0.5, 0.5)
                lp[fr_l].uv = (0.0, 1.0)

        bmesh.ops.recalc_face_normals(bm, faces=chain_faces)
        bmesh.ops.recalc_face_normals(bm, faces=pend_faces)
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.uv_layers.active_index = 0
        obj.data.update()

        # Assign smooth anatomical weights from chest/neck so necklace follows upper torso & breathing seamlessly!
        for g in list(obj.vertex_groups):
            obj.vertex_groups.remove(g)
        chest_g = obj.vertex_groups.new(name='b_chest')
        neck_g = obj.vertex_groups.new(name='b_neck')
        for v in obj.data.vertices:
            back_w = smooth(nc_y + 0.015, nc_y - 0.045, v.co.y) * smooth(1.425, 1.468, v.co.z) * 0.35
            neck_g.add([v.index], back_w, 'REPLACE')
            chest_g.add([v.index], 1.0 - back_w, 'REPLACE')
        for mat in obj.data.materials:
            if mat and mat.use_nodes:
                bsdf = mat.node_tree.nodes.get('Principled BSDF')
                if bsdf:
                    bsdf.inputs['Base Color'].default_value = (*colour, 1.0)
                    bsdf.inputs['Metallic'].default_value = 0.85
                    bsdf.inputs['Roughness'].default_value = 0.24


def raise_socks(collection):
    name = 'Fashion_Lounge_Socks'
    old = collection.models.pop(name)
    knit = old.data.materials[0]
    collection.meshes.remove(old)
    bpy.data.objects.remove(old, do_unlink=True)
    # Knitted over the LARGER of the two leg skins it is worn with: the biker
    # legs (sports bottoms) stand 1.5-6 mm proud of the plain legs round the
    # ankle, and a sock knitted on the plain legs vanished under them.
    donor = 'Fashion_Biker_Legs' if 'Fashion_Biker_Legs' in collection.models else 'Fashion_Legs'
    socks = collection.clone(donor, name)
    collection.cut(socks, lambda p: min(p.z - .055, .236 - p.z), .0025)
    socks.data.materials.clear()
    socks.data.materials.append(knit)
    joints = collection.rig.data.bones

    def knit_clearance(p):
        side = 'l' if p.x < 0 else 'r'
        ankle = joints['b_foot_' + side].head_local
        knee = joints['b_shin_' + side].head_local
        centre = ankle.lerp(knee, (p.z - ankle.z) / (knee.z - ankle.z))
        radial = Vector((p.x-centre.x, p.y-centre.y, 0)).normalized()
        cuff = smooth(.218, .230, p.z)
        # Tucked in only below the LOW trainer's collar (~7 cm): tucked from
        # 12 cm the low trainers showed a band of bare ankle under a floating
        # sock (2026-11-26). The high-tops are opened round the ankle
        # (jules_finish) to take the sock's 3 mm.
        in_shoe = 1.0 - smooth(.052, .074, p.z)
        return radial * ((.0032 + .0016 * cuff) * (1.0 - in_shoe) - .0040 * in_shoe)

    adjust_basis(socks, knit_clearance)


def cap_fibres(points, _normals):
    x, y, z = points.T
    # The brushed strands converge toward the tie. Keep the fine breakup
    # under the existing broader locks and the approved hairline texture.
    phi = np.arctan2(x + .005, y + .070)
    spread = np.hypot(x + .005, y + .070)
    phase = 274 * phi + 2.1 * np.sin(spread*123 + z*56)
    ribbons = np.sin(phase) + .43 * np.sin(phase * 1.71 - z * 217)
    return (1 + .024 * ribbons)[:, None], .000075 * ribbons


def add_updo_strands(groom, shell, eye):
    """Lay tapered strand cards along existing scalp and wound bun surfaces."""
    batch = ([], [], [])
    rng = random.Random(19277)
    lengths = shell.data.materials.find('hero_hair_lengths_b')
    skin = mesh_tree(shell.data, 0)
    coil = mesh_tree(shell.data, lengths)
    coil_indices = {i for p in shell.data.polygons if p.material_index == lengths for i in p.vertices}
    knot = sum((shell.data.vertices[i].co for i in coil_indices), Vector()) / len(coil_indices)

    for strand in range(56):
        phi = strand * 2.399963
        bundle = strand >= 30
        if bundle:
            tree, origin = coil, knot
        else:
            tree, origin = skin, Vector((0, eye.y - .080, eye.z + .021))
        centres, normals = [], []
        for step in range(9):
            t = step / 8
            sweep = phi + (.95 if bundle else .27) * t
            height = .46 + .22 * math.sin(phi*2) - .27 * t if bundle else .38 + .54*t
            direction = Vector((math.sin(sweep), math.cos(sweep), height)).normalized()
            hit, normal, _, _ = tree.ray_cast(origin + direction*.27, -direction, .27)
            if hit is None or normal.dot(direction) < .10:
                break
            if centres and (hit-centres[-1]).length > .024:
                break
            lift = (.0009 if bundle else .0013) * math.sin(math.pi*t) + .00045*t - .00021
            centres.append(hit + normal*lift)
            normals.append(normal)
        if len(centres) >= 7:
            ribbon(batch, centres, normals, rng.uniform(.00115, .0028), strand % 8)

    points, polygons, texels = batch
    bm = bmesh.new()
    bm.from_mesh(groom.data)
    tex = bm.loops.layers.uv.get('SurfaceUV')
    motion = bm.loops.layers.uv.get('ClothFreedom')
    weights = bm.verts.layers.deform.verify()
    head = groom.vertex_groups['b_head'].index
    verts = [bm.verts.new(p) for p in points]
    for vertex in verts:
        vertex[weights][head] = 1.0
    for indices in polygons:
        face = bm.faces.new([verts[i] for i in indices])
        face.smooth = True
        for corner, index in zip(face.loops, indices):
            corner[tex].uv = texels[index]
            p = corner.vert.co
            corner[motion].uv = (tied_freedom(p, eye, 'bun')*.60, strand_opacity(p, eye, 'bun'))
    bm.to_mesh(groom.data)
    bm.free()
    groom.data.update()


def finish_jules_accessories(collection, output):
    if collection.rig.get('jules_accessory_fit'):
        return
    output.mkdir(parents=True, exist_ok=True)
    models = collection.models
    face = models['Face_jules']
    fit_hoops(face)
    refit_necklaces(collection)
    raise_socks(collection)
    shell = models['Hair_bun_jules']
    from aaa_hair import rebuild_jules_hair
    from hero_realism import eye_centres
    rebuild_jules_hair(face, shell, models['Groom_bun_jules'], eye_centres(face), output)
    collection.rig['jules_accessory_fit'] = 1
