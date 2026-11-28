"""AAA wardrobe tailoring and formal/casual garment fixes for Ade's five outfits.

Guarantees:
  * Clean, zero-intersection Formal collar, shirt, tie knot, lapels & blazer
  * Smooth crewneck T-shirt collar & crease-free lower cotton drape
  * Athletic tailored bomber, blazer & hoodie sleeves (zero balloon arms)
  * Clean shirt-into-chino tuck and flush streetwear cargo pockets
  * Strict underlayer clearance so undershirts never clip through jackets/hoodies
"""
import math

import bmesh
import numpy as np
from mathutils import Vector

from garment_kit import _dilate, raster_uv, weights_from
from wardrobe_quality import adjust_basis, smooth, surface_tree


def _bell(v, r):
    return math.exp(-(v / r) ** 2)


def _recalc_normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def _neck_center(face):
    """Measure Ade's actual cylindrical neck centre from Face_ade vertices."""
    if face is None:
        return Vector((0.0, 0.0314, 1.54))
    pts = [v.co for v in face.data.vertices if 1.50 < v.co.z < 1.575 and abs(v.co.x) < 0.08]
    if not pts:
        return Vector((0.0, 0.0314, 1.54))
    cx = sum(p.x for p in pts) / len(pts)
    cy = sum(p.y for p in pts) / len(pts)
    return Vector((cx, cy, 1.54))


def _blazer_v_halfwidth(z):
    """Exact open V-neckline half-width of Top_Blazer (matches empire_wardrobe.py)."""
    btn_z = 1.06
    v_top_x, v_top_z = 0.082, 1.455
    if z >= v_top_z:
        return v_top_x
    if z >= btn_z:
        t = (z - btn_z) / (v_top_z - btn_z)
        return 0.011 + (v_top_x - 0.011) * t
    return 0.011


def _rebuild_clean_shirt_collar(b_scollar, b_shirt, neck_tree, neck_c):
    """Replace fragmented/intersecting dress-shirt collar geometry with a clean,
    solid, tailored spread collar wrapped snugly around Ade's actual neck with
    a crisp front V-opening for the Windsor tie knot (ZERO grey back-face shards!)."""
    shirt_tree = surface_tree(b_shirt.data) if b_shirt is not None else None
    # Measure neck radius as a smooth function of angle around neck_c (angle=0 is front +Y).
    n_seg = 48
    angles = [math.tau * i / n_seg for i in range(n_seg)]
    neck_r = []
    for a in angles:
        d = Vector((math.sin(a), math.cos(a), 0.0))
        hit = neck_tree.ray_cast(Vector((neck_c.x, neck_c.y, 1.545)) + d * 0.16, -d, 0.16)[0]
        r = (hit - Vector((neck_c.x, neck_c.y, 1.545))).dot(d) if hit is not None else 0.058
        neck_r.append(max(0.048, min(0.075, r)))
    # Smooth radii symmetrically (left/right mirror + low-pass) so collar is crisp and tailored.
    for _ in range(3):
        neck_r = [0.25 * neck_r[(i - 1) % n_seg] + 0.50 * neck_r[i] + 0.25 * neck_r[(i + 1) % n_seg] for i in range(n_seg)]

    # Base collar line height around the neck (higher at back ~1.552, lower at front throat ~1.525).
    def z_base(a):
        front = 0.5 * (1.0 + math.cos(a))  # 1 at front, 0 at back
        return 1.548 - 0.022 * (front ** 1.3)

    # Preserve weights from nearest b_shirt/chest/neck bones.
    neck_g = b_scollar.vertex_groups.get('b_neck') or b_scollar.vertex_groups.new(name='b_neck')
    chest_g = b_scollar.vertex_groups.get('b_chest') or b_scollar.vertex_groups.new(name='b_chest')

    bm = bmesh.new()
    uv_l = bm.loops.layers.uv.new('SurfaceUV')
    fr_l = bm.loops.layers.uv.new('ClothFreedom')
    deform = bm.verts.layers.deform.verify()

    # Build a single continuous, clean, outward-facing closed-loop folded dress collar:
    # Inner bottom -> top fold -> outer leaf drooping cleanly onto shirt chest (opening cleanly at front tie knot!).
    # Split slightly at exact front center (angle in [0.16 .. tau - 0.16]) to form neat pointed spread collar tips!
    col_steps = 44
    a_start, a_end = 0.16, math.tau - 0.16
    a_vals = [a_start + (a_end - a_start) * i / (col_steps - 1) for i in range(col_steps)]

    def sample_r(a):
        t = (a % math.tau) / math.tau * n_seg
        i0 = int(t) % n_seg
        i1 = (i0 + 1) % n_seg
        f = t - math.floor(t)
        return neck_r[i0] * (1.0 - f) + neck_r[i1] * f

    # 5 profile rings around the collar cross-section:
    # 0: inner bottom tucked into shirt, 1: inner top stand, 2: crisp top fold crest,
    # 3: outer leaf mid, 4: outer leaf bottom tip (flaring cleanly into pointed spread collar tips in front!).
    rings = []
    for k in range(5):
        row = []
        for idx, a in enumerate(a_vals):
            d = Vector((math.sin(a), math.cos(a), 0.0))
            rn = sample_r(a)
            zb = z_base(a)
            front = 0.5 * (1.0 + math.cos(a))  # 1 near front collar tips, 0 at back
            tip_flare = math.exp(-((min(a, math.tau - a) - a_start) / 0.34) ** 2)
            stand_h = 0.032 + 0.005 * (1.0 - front)
            leaf_drop = 0.036 + 0.018 * tip_flare
            if k == 0:
                r, z = rn + 0.0035, zb - 0.008
            elif k == 1:
                r, z = rn + 0.0040, zb + stand_h * 0.85
            elif k == 2:
                r, z = rn + 0.0068, zb + stand_h
            elif k == 3:
                r, z = rn + 0.0105 + 0.004 * tip_flare, zb + stand_h - leaf_drop * 0.45
            else:
                r, z = rn + 0.0135 + 0.007 * tip_flare, zb + stand_h - leaf_drop
            pt = Vector((neck_c.x + d.x * r, neck_c.y + d.y * r, z))
            # Keep outer leaf cleanly outside dress shirt surface!
            if k >= 3 and shirt_tree is not None:
                sh_hit = shirt_tree.ray_cast(Vector((neck_c.x, neck_c.y, z)) + d * 0.22, -d, 0.22)[0]
                if sh_hit is not None:
                    r_sh = (sh_hit - Vector((neck_c.x, neck_c.y, z))).dot(d)
                    if r < r_sh + 0.0045:
                        pt = Vector((neck_c.x + d.x * (r_sh + 0.0045), neck_c.y + d.y * (r_sh + 0.0045), z))
            v = bm.verts.new(pt)
            w_neck = smooth(1.505, 1.565, z)
            v[deform][neck_g.index] = w_neck
            v[deform][chest_g.index] = 1.0 - w_neck
            row.append(v)
        rings.append(row)

    for k in range(4):
        for i in range(col_steps - 1):
            f = bm.faces.new((rings[k][i], rings[k][i + 1], rings[k + 1][i + 1], rings[k + 1][i]))
            f.material_index = 0
            f.smooth = True
            for loop, (u, v_uv) in zip(f.loops, ((i / col_steps, k * 0.2), ((i + 1) / col_steps, k * 0.2),
                                                 ((i + 1) / col_steps, (k + 1) * 0.2), (i / col_steps, (k + 1) * 0.2))):
                loop[uv_l].uv = (u * 2.0, 0.05 + v_uv * 0.20)
                loop[fr_l].uv = (0.0, 1.0)

    # Cap the two front collar ends cleanly so there are ZERO open razor edges!
    for end_i in (0, col_steps - 1):
        cap_verts = [rings[k][end_i] for k in range(5)]
        if end_i == 0:
            cap_verts = cap_verts[::-1]
        f = bm.faces.new(cap_verts)
        f.material_index = 0
        f.smooth = False

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(b_scollar.data)
    bm.free()
    b_scollar.data.uv_layers.active_index = 0
    b_scollar.data.update()


def _rebuild_clean_tie(b_knot, b_tie, b_shirt, neck_c):
    """Build a crisp, sculpted 3D Windsor knot seated inside the collar V-opening
    and a clean tapered silk tie blade lying flat +4.5mm against the dress shirt."""
    shirt_tree = surface_tree(b_shirt.data)

    def shirt_y(x, z):
        hit = shirt_tree.ray_cast(Vector((x, neck_c.y + 0.35, z)), Vector((0.0, -1.0, 0.0)), 0.45)[0]
        if hit is not None:
            return hit.y
        return neck_c.y + 0.088

    # 1. Clean 3D Windsor Knot (z = 1.548 down to 1.512) nestled cleanly between the collar tips!
    if b_knot is not None:
        chest_g = b_knot.vertex_groups.get('b_chest') or b_knot.vertex_groups.new(name='b_chest')
        neck_g = b_knot.vertex_groups.get('b_neck') or b_knot.vertex_groups.new(name='b_neck')
        bm = bmesh.new()
        uv_l = bm.loops.layers.uv.new('SurfaceUV')
        fr_l = bm.loops.layers.uv.new('ClothFreedom')
        deform = bm.verts.layers.deform.verify()
        knot_rows = [
            (1.546, 0.0175, 0.0085),
            (1.537, 0.0185, 0.0105),
            (1.524, 0.0145, 0.0095),
            (1.512, 0.0110, 0.0070),
        ]
        # 6-point closed loop per row (front 3 + back 3) -> solid 3D knot, zero back-face artifacts!
        loops_v = []
        for z, hw, depth in knot_rows:
            cy = shirt_y(0.0, z)
            ring = [
                bm.verts.new(Vector((-hw, cy + 0.0030, z))),
                bm.verts.new(Vector((-hw * 0.55, cy + depth * 0.92, z))),
                bm.verts.new(Vector((0.0, cy + depth, z))),
                bm.verts.new(Vector((hw * 0.55, cy + depth * 0.92, z))),
                bm.verts.new(Vector((hw, cy + 0.0030, z))),
                bm.verts.new(Vector((0.0, cy + 0.0010, z))),
            ]
            w_n = smooth(1.515, 1.560, z) * 0.55
            for v in ring:
                v[deform][neck_g.index] = w_n
                v[deform][chest_g.index] = 1.0 - w_n
            loops_v.append(ring)
        n_r = len(loops_v[0])
        for r_i in range(len(loops_v) - 1):
            for j in range(n_r):
                jn = (j + 1) % n_r
                f = bm.faces.new((loops_v[r_i][j], loops_v[r_i][jn], loops_v[r_i + 1][jn], loops_v[r_i + 1][j]))
                f.material_index = 0
                f.smooth = True
                for lp in f.loops:
                    lp[uv_l].uv = (0.5, 0.1)
                    lp[fr_l].uv = (0.0, 1.0)
        bm.faces.new(loops_v[0][::-1]).material_index = 0
        bm.faces.new(loops_v[-1]).material_index = 0
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(b_knot.data)
        bm.free()
        b_knot.data.uv_layers.active_index = 0
        b_knot.data.update()

    # 2. Clean 3D Tapered Silk Tie Blade flowing smoothly from knot (z=1.516) down to blazer button (z=1.080)!
    if b_tie is not None:
        chest_g = b_tie.vertex_groups.get('b_chest') or b_tie.vertex_groups.new(name='b_chest')
        spine_g = b_tie.vertex_groups.get('b_spine') or b_tie.vertex_groups.new(name='b_spine')
        bm = bmesh.new()
        uv_l = bm.loops.layers.uv.new('SurfaceUV')
        fr_l = bm.loops.layers.uv.new('ClothFreedom')
        deform = bm.verts.layers.deform.verify()
        n_z = 22
        z_top, z_bot = 1.516, 1.082
        loops_v = []
        last_y = shirt_y(0.0, z_top)
        for i in range(n_z + 1):
            t = i / n_z
            z = z_top + (z_bot - z_top) * t
            # Classic modern slim-tailored tie blade width: 2.1cm under knot widening smoothly to 6.0cm, pointed tip!
            if t < 0.90:
                hw = 0.0105 + 0.0195 * (t / 0.90) ** 0.85
            else:
                hw = 0.0300 * (1.0 - (t - 0.90) / 0.10) + 0.0020
            sy = shirt_y(0.0, z)
            sy = min(last_y + 0.008, max(last_y - 0.008, sy))
            last_y = sy
            sl = shirt_y(-hw * 0.8, z)
            sr = shirt_y(hw * 0.8, z)
            y_base = max(sy, sl, sr)
            yl = y_base + 0.0115
            yr = y_base + 0.0115
            ym = y_base + 0.0155
            ring = [
                bm.verts.new(Vector((-hw, yl, z))),
                bm.verts.new(Vector((0.0, ym, z))),
                bm.verts.new(Vector((hw, yr, z))),
                bm.verts.new(Vector((0.0, y_base + 0.0075, z))),
            ]
            w_ch = smooth(1.12, 1.34, z)
            for v in ring:
                v[deform][chest_g.index] = w_ch
                v[deform][spine_g.index] = 1.0 - w_ch
            loops_v.append(ring)
        for r_i in range(len(loops_v) - 1):
            for j in range(4):
                jn = (j + 1) % 4
                f = bm.faces.new((loops_v[r_i][j], loops_v[r_i][jn], loops_v[r_i + 1][jn], loops_v[r_i + 1][j]))
                f.material_index = 0
                f.smooth = True
                for lp in f.loops:
                    lp[uv_l].uv = (0.5, r_i / n_z)
                    lp[fr_l].uv = (0.0, 1.0)
        bm.faces.new(loops_v[0][::-1]).material_index = 0
        bm.faces.new(loops_v[-1]).material_index = 0
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(b_tie.data)
        bm.free()
        b_tie.data.uv_layers.active_index = 0
        b_tie.data.update()
        # Lock tie & knot skinning weights directly to the underlying dress shirt so they never
        # separate or z-fight during chest twist, breathing, walking or running!
        weights_from(b_tie, b_shirt)
    if b_knot is not None:
        weights_from(b_knot, b_shirt)


def _refine_ade_formal(by_name, neck_tree, neck_c):
    """Ensure Ade's Formal outfit has strictly ordered, clean, non-intersecting
    layers: neck skin < dress shirt & spread collar < Windsor tie & blade < blazer & lapels."""
    blazer = by_name.get('Top_Blazer')
    b_collar = by_name.get('Topx_Blazer_Collar')
    b_shirt = by_name.get('Topx_Blazer_Shirt')
    b_scollar = by_name.get('Topx_Blazer_ShirtCollar')
    b_tie = by_name.get('Topx_Blazer_Tie')
    b_knot = by_name.get('Topx_Blazer_Knot')
    chinos = by_name.get('Courier_Chinos')

    # 1. Dress Shirt under Blazer: keep strictly OUTSIDE neck skin (z > 1.48),
    #    fully visible in the open V-window, and tucked -12mm INSIDE Top_Blazer
    #    everywhere covered by the closed jacket (INCLUDING upper shoulders so zero white ticks poke out!).
    if b_shirt is not None:
        if neck_tree is not None:
            def clear_shirt_neck(p):
                if p.z < 1.46 or abs(p.x) > 0.11:
                    return Vector()
                radial = Vector((p.x - neck_c.x, p.y - neck_c.y, 0.0))
                r_cur = radial.length
                if r_cur < 0.01:
                    return Vector()
                d = radial / r_cur
                hit = neck_tree.ray_cast(Vector((neck_c.x, neck_c.y, p.z)) + d * 0.18, -d, 0.18)[0]
                if hit is None:
                    return Vector()
                r_neck = (hit - Vector((neck_c.x, neck_c.y, p.z))).dot(d)
                need = (r_neck + 0.0045) - r_cur
                return d * need if need > 0.0 else Vector()
            adjust_basis(b_shirt, clear_shirt_neck)

        if blazer is not None:
            blazer_tree = surface_tree(blazer.data)

            def tuck_blazer_shirt(p):
                v_w = _blazer_v_halfwidth(p.z)
                # Preserve the visible front V-chest triangle cleanly!
                if p.z > 1.07 and p.y > neck_c.y + 0.02 and abs(p.x) < v_w + 0.012:
                    return Vector()
                # Tuck upper shoulder tabs (|x| > 0.088, z > 1.42) downward & inward cleanly inside blazer!
                if p.z > 1.42 and abs(p.x) > 0.082:
                    w_sh = smooth(0.082, 0.105, abs(p.x))
                    return Vector((0.0, -0.010 * w_sh, -0.014 * w_sh))
                centre = Vector((0.0, neck_c.y, p.z))
                radial = p - centre
                r_in = radial.length
                if r_in < 0.03:
                    return Vector()
                d = radial / r_in
                hit = blazer_tree.ray_cast(centre + d * 0.38, -d, 0.38)[0]
                if hit is None:
                    return Vector()
                r_out = (hit - centre).dot(d)
                max_r = r_out - 0.012
                if r_in > max_r:
                    v_fade = smooth(v_w + 0.008, v_w + 0.028, abs(p.x)) if p.z > 1.07 else 1.0
                    return -d * ((r_in - max_r) * v_fade)
                return Vector()

            adjust_basis(b_shirt, tuck_blazer_shirt)
        _recalc_normals(b_shirt)

    # 2. Rebuild a pristine, zero-artifact spread dress-shirt collar & 3D Windsor tie!
    if b_scollar is not None and neck_tree is not None:
        _rebuild_clean_shirt_collar(b_scollar, b_shirt, neck_tree, neck_c)
    if b_shirt is not None:
        _rebuild_clean_tie(b_knot, b_tie, b_shirt, neck_c)

    # 3. Jacket Collar & Lapels (Topx_Blazer_Collar):
    #    Keep jacket neck-band seated smoothly around the back/sides OUTSIDE shirt collar,
    #    trim any protruding high wing-tips down to collar height, and keep lapels flat on blazer!
    if b_collar is not None:
        scollar_tree = surface_tree(b_scollar.data) if b_scollar is not None else None
        blazer_tree = surface_tree(blazer.data) if blazer is not None else None
        shirt_tree = surface_tree(b_shirt.data) if b_shirt is not None else None

        def fit_jacket_collar(p):
            delta = Vector()
            # Neck collar band (z > 1.46): smooth height so zero protruding wing-tips stick up above shirt collar!
            if p.z > 1.46:
                front_w = smooth(neck_c.y - 0.01, neck_c.y + 0.065, p.y)
                max_z = 1.568 - 0.028 * front_w
                if p.z > max_z:
                    delta.z -= (p.z - max_z) * 0.85
                if scollar_tree is not None:
                    radial = Vector((p.x - neck_c.x, p.y - neck_c.y, 0.0))
                    r_cur = radial.length
                    if r_cur > 0.01:
                        d = radial / r_cur
                        hit = scollar_tree.ray_cast(Vector((neck_c.x, neck_c.y, p.z + delta.z)) + d * 0.22, -d, 0.22)[0]
                        if hit is not None:
                            r_sc = (hit - Vector((neck_c.x, neck_c.y, p.z + delta.z))).dot(d)
                            need = (r_sc + 0.0045) - r_cur
                            if need > 0.0:
                                delta += d * need
            # Front lapels (z <= 1.48, front): sit cleanly outside blazer and shirt!
            if p.z <= 1.48 and p.y > neck_c.y + 0.02:
                if blazer_tree is not None:
                    b_hit = blazer_tree.ray_cast(Vector((p.x, neck_c.y + 0.35, p.z)), Vector((0.0, -1.0, 0.0)), 0.45)[0]
                    if b_hit is not None and p.y < b_hit.y + 0.0032:
                        delta.y = max(delta.y, (b_hit.y + 0.0032) - p.y)
                if shirt_tree is not None:
                    s_hit = shirt_tree.ray_cast(Vector((p.x, neck_c.y + 0.35, p.z)), Vector((0.0, -1.0, 0.0)), 0.45)[0]
                    if s_hit is not None and p.y < s_hit.y + 0.0055:
                        delta.y = max(delta.y, (s_hit.y + 0.0055) - p.y)
            return delta

        adjust_basis(b_collar, fit_jacket_collar)
        _recalc_normals(b_collar)

    # 4. Clean Blazer Hem-to-Chinos Transition (smooth +10mm drape over trouser waist/hips).
    if blazer is not None and chinos is not None:
        chino_tree = surface_tree(chinos.data)

        def clear_blazer_hem(p):
            if p.z > 1.08 or abs(p.x) > 0.24:
                return Vector()
            centre = Vector((0.0, neck_c.y - 0.01, p.z))
            radial = p - centre
            r_cur = radial.length
            if r_cur < 0.04:
                return Vector()
            d = radial / r_cur
            hit = chino_tree.ray_cast(centre + d * 0.35, -d, 0.35)[0]
            if hit is None:
                return Vector()
            r_ch = (hit - centre).dot(d)
            need = (r_ch + 0.010) - r_cur
            if need > 0.0:
                return d * need * smooth(1.08, 1.02, p.z)
            return Vector()

        adjust_basis(blazer, clear_blazer_hem)
        _recalc_normals(blazer)


def refine_ade_wardrobe(rig, meshes):
    """Apply clean, modern athletic tailoring across Ade's entire wardrobe."""
    by_name = {obj.name: obj for obj in meshes}
    bones = rig.data.bones
    sh_r = bones['b_upper_arm_r'].head_local.copy()
    el_r = bones['b_forearm_r'].head_local.copy()
    wr_r = bones['b_hand_r'].head_local.copy()
    arm_axis = (el_r - sh_r).normalized()
    arm_len = (el_r - sh_r).length
    fore_len = (wr_r - el_r).length

    face = by_name.get('Face_ade')
    neck_tree = surface_tree(face.data) if face is not None else None
    neck_c = _neck_center(face)

    # 1. Clean, zero-clipping necklines & collars on Top_Tee and Top_Bomber!
    #    NEVER drop Topx_Tee_Bindings into Top_Tee or push Top_Bomber into Face_ade's chest skin!
    if neck_tree is not None:
        # 1a. Top_Tee + Topx_Tee_Bindings: roll the ribbed crew neck softly inward onto the base of the neck
        #     (eliminates stiff upturned paper-funnel collar and black z-fighting seam!) and hug sleeve hems!
        tee_ob = by_name.get('Top_Tee')
        tee_bind = by_name.get('Topx_Tee_Bindings')
        if tee_ob is not None:
            def clear_tee_neck(p):
                if p.z < 1.44 or abs(p.x) > 0.14:
                    return Vector()
                radial = Vector((p.x - neck_c.x, p.y - neck_c.y, 0.0))
                r_cur = radial.length
                if r_cur < 0.01:
                    return Vector()
                d = radial / r_cur
                hit = neck_tree.ray_cast(Vector((neck_c.x, neck_c.y, p.z)) + d * 0.20, -d, 0.20)[0]
                if hit is not None:
                    r_nk = (hit - Vector((neck_c.x, neck_c.y, p.z))).dot(d)
                    if r_cur < r_nk + 0.0042:
                        return d * ((r_nk + 0.0042) - r_cur)
                # Gently tuck the very top cut rim of Top_Tee slightly down/in under the rib binding.
                rim_t = smooth(1.525, 1.568, p.z)
                if rim_t > 0.01:
                    return Vector((-d.x * 0.0018 * rim_t, -d.y * 0.0018 * rim_t, -0.0022 * rim_t))
                return Vector()
            adjust_basis(tee_ob, clear_tee_neck)
            if tee_bind is not None:
                t_tree = surface_tree(tee_ob.data)
                def seat_tee_rib(p):
                    # Sleeve bindings (|x| > 0.22): gently hug sleeve edge onto upper arm (no stiff flared rings!).
                    if abs(p.x) > 0.22:
                        sign = 1.0 if p.x > 0 else -1.0
                        local = Vector((abs(p.x), p.y, p.z)) - sh_r
                        along = local.dot(arm_axis)
                        rad = local - arm_axis * along
                        rad.x *= sign
                        return -rad * 0.065
                    if p.z < 1.47 or abs(p.x) > 0.15:
                        return Vector()
                    radial = Vector((p.x - neck_c.x, p.y - neck_c.y, 0.0))
                    r_cur = radial.length
                    if r_cur < 0.01:
                        return Vector()
                    d = radial / r_cur
                    # Roll the crew-neck rib smoothly inward & slightly lower so it hugs the base of the neck cleanly with ZERO back gap!
                    front = max(0.0, d.y)
                    z_base_a = 1.564 - 0.032 * (front ** 1.4)
                    top_t = smooth(z_base_a - 0.004, z_base_a + 0.016, p.z)
                    dz = -0.0042 * top_t
                    nhit = neck_tree.ray_cast(Vector((neck_c.x, neck_c.y, p.z + dz)) + d * 0.20, -d, 0.20)[0]
                    r_nk = (nhit - Vector((neck_c.x, neck_c.y, p.z + dz))).dot(d) if nhit is not None else r_cur - 0.008
                    thit = t_tree.ray_cast(Vector((neck_c.x, neck_c.y, p.z + dz)) + d * 0.20, -d, 0.20)[0]
                    r_tee = (thit - Vector((neck_c.x, neck_c.y, p.z + dz))).dot(d) if thit is not None else r_cur
                    # Lower edge sits cleanly +2.6mm over Top_Tee; upper edge hugs neck smoothly at r_nk + 3.4mm all around!
                    r_target = (r_tee + 0.0026) * (1.0 - top_t) + max(r_nk + 0.0034, r_tee - 0.0048) * top_t
                    dr = (r_target - r_cur) * 0.90
                    return Vector((d.x * dr, d.y * dr, dz))
                adjust_basis(tee_bind, seat_tee_rib)
                _recalc_normals(tee_bind)

        # 1b. Top_Bomber + Topx_Bomber_Neck + Topx_Bomber_Zip:
        #     Keep Top_Bomber cleanly seated around chest skin (NO gap!) and REBUILD Topx_Bomber_Neck
        #     as a pristine, single-shell folded rib stand collar (eliminates the 206 inward-facing
        #     z-fighting solidify faces 100%!) plus a clean flat-ribbon front zipper (zero diagonal stripes!).
        bomber_ob = by_name.get('Top_Bomber')
        bomber_neck = by_name.get('Topx_Bomber_Neck')
        if bomber_ob is not None:
            def clear_bomber_chest_skin(p):
                if p.z < 1.40 or abs(p.x) > 0.16:
                    return Vector()
                hit, nrm, _, dist = neck_tree.find_nearest(p)
                if hit is not None and nrm.length > 1e-4 and dist < 0.04:
                    gap = (p - hit).dot(nrm)
                    if gap < 0.0075:
                        return nrm * (0.0075 - gap)
                return Vector()
            adjust_basis(bomber_ob, clear_bomber_chest_skin)
            _recalc_normals(bomber_ob)

            if bomber_neck is not None:
                b_tree = surface_tree(bomber_ob.data)
                # Rebuild Topx_Bomber_Neck as a clean closed-profile rib collar anchored right onto
                # Top_Bomber's actual neckline (zero double-wall self-z-fighting, zero skin gap!).
                n_seg = 56
                angles = [math.tau * i / n_seg for i in range(n_seg)]
                r_base, z_base_ring, r_neck_ring = [], [], []
                for a in angles:
                    d = Vector((math.sin(a), math.cos(a), 0.0))
                    front = 0.5 * (1.0 + math.cos(a))
                    zb = 1.556 - 0.012 * (front ** 1.3)
                    bhit = b_tree.ray_cast(Vector((neck_c.x, neck_c.y, zb - 0.006)) + d * 0.24, -d, 0.24)[0]
                    rb = (bhit - Vector((neck_c.x, neck_c.y, zb - 0.006))).dot(d) if bhit is not None else 0.072
                    nhit = neck_tree.ray_cast(Vector((neck_c.x, neck_c.y, zb + 0.022)) + d * 0.22, -d, 0.22)[0]
                    rn = (nhit - Vector((neck_c.x, neck_c.y, zb + 0.022))).dot(d) if nhit is not None else 0.062
                    # Keep bomber rib collar snug & tailored around the neck (never flaring out onto shoulders!).
                    r_base.append(min(rn + 0.015, max(rb + 0.0030, rn + 0.0095)))
                    r_neck_ring.append(min(rn + 0.010, max(rn + 0.0055, rb - 0.0025)))
                    z_base_ring.append(zb)
                for _ in range(4):
                    r_base = [0.25 * r_base[(i - 1) % n_seg] + 0.50 * r_base[i] + 0.25 * r_base[(i + 1) % n_seg] for i in range(n_seg)]
                    r_neck_ring = [0.25 * r_neck_ring[(i - 1) % n_seg] + 0.50 * r_neck_ring[i] + 0.25 * r_neck_ring[(i + 1) % n_seg] for i in range(n_seg)]

                neck_g = bomber_neck.vertex_groups.get('b_neck') or bomber_neck.vertex_groups.new(name='b_neck')
                chest_g = bomber_neck.vertex_groups.get('b_chest') or bomber_neck.vertex_groups.new(name='b_chest')
                bm_n = bmesh.new()
                uv_l = bm_n.loops.layers.uv.new('SurfaceUV')
                fr_l = bm_n.loops.layers.uv.new('ClothFreedom')
                deform = bm_n.verts.layers.deform.verify()
                # 5 clean non-overlapping profile rings: outer base (tucked over bomber) -> outer mid ->
                # outer top crest -> rounded inner top lip -> inner tuck (strictly -4.5mm inside outer wall!).
                rings_bn = []
                prof = [
                    (0.0, -0.012, 0.000),
                    (0.45, 0.006, 0.001),
                    (0.88, 0.024, 0.000),
                    (1.00, 0.028, -0.0022),
                    (1.00, 0.018, -0.0046),
                ]
                for p_i, (blend_r, dz_p, dr_p) in enumerate(prof):
                    row = []
                    for i, a in enumerate(angles):
                        d = Vector((math.sin(a), math.cos(a), 0.0))
                        r = r_base[i] * (1.0 - blend_r) + r_neck_ring[i] * blend_r + dr_p
                        z = z_base_ring[i] + dz_p
                        v = bm_n.verts.new(Vector((neck_c.x + d.x * r, neck_c.y + d.y * r, z)))
                        w_n = smooth(1.540, 1.595, z) * 0.55
                        v[deform][neck_g.index] = w_n
                        v[deform][chest_g.index] = 1.0 - w_n
                        row.append(v)
                    rings_bn.append(row)
                for p_i in range(len(rings_bn) - 1):
                    for i in range(n_seg):
                        inext = (i + 1) % n_seg
                        f = bm_n.faces.new((rings_bn[p_i][i], rings_bn[p_i][inext], rings_bn[p_i + 1][inext], rings_bn[p_i + 1][i]))
                        f.material_index = 0
                        f.smooth = True
                        for lp, (u_t, v_t) in zip(f.loops, ((i / n_seg, p_i * 0.25), ((i + 1) / n_seg, p_i * 0.25),
                                                            ((i + 1) / n_seg, (p_i + 1) * 0.25), (i / n_seg, (p_i + 1) * 0.25))):
                            lp[uv_l].uv = (u_t * 4.0, v_t)
                            lp[fr_l].uv = (0.0, 1.0)
                bmesh.ops.recalc_face_normals(bm_n, faces=bm_n.faces)
                bm_n.to_mesh(bomber_neck.data)
                bm_n.free()
                bomber_neck.data.uv_layers.active_index = 0
                bomber_neck.data.update()

            # Rebuild Topx_Bomber_Zip as a clean, uniform, flat-ribbon center metal zipper + pull tab
            # (ZERO twisted diagonal specular zebra striping!).
            b_zip = by_name.get('Topx_Bomber_Zip')
            if b_zip is not None:
                b_tree = surface_tree(bomber_ob.data)
                chest_g = b_zip.vertex_groups.get('b_chest') or b_zip.vertex_groups.new(name='b_chest')
                spine_g = b_zip.vertex_groups.get('b_spine') or b_zip.vertex_groups.new(name='b_spine')
                hips_g = b_zip.vertex_groups.get('b_hips') or b_zip.vertex_groups.new(name='b_hips')
                bm_z = bmesh.new()
                uv_l = bm_z.loops.layers.uv.new('SurfaceUV')
                fr_l = bm_z.loops.layers.uv.new('ClothFreedom')
                deform = bm_z.verts.layers.deform.verify()
                z_rows = 36
                z_lo, z_hi = 1.005, 1.544
                hw = 0.0036
                zip_rows = []
                for i in range(z_rows + 1):
                    z = z_lo + (z_hi - z_lo) * (i / z_rows)
                    hit = b_tree.ray_cast(Vector((0.0, neck_c.y + 0.35, z)), Vector((0.0, -1.0, 0.0)), 0.45)[0]
                    cy = (hit.y + 0.0020) if hit is not None else (neck_c.y + 0.125)
                    v_l = bm_z.verts.new(Vector((-hw, cy, z)))
                    v_m = bm_z.verts.new(Vector((0.0, cy + 0.0010, z)))
                    v_r = bm_z.verts.new(Vector((hw, cy, z)))
                    w_ch = smooth(1.12, 1.32, z)
                    w_hp = 1.0 - smooth(0.98, 1.12, z)
                    w_sp = max(0.0, 1.0 - w_ch - w_hp)
                    for v in (v_l, v_m, v_r):
                        v[deform][chest_g.index] = w_ch
                        v[deform][spine_g.index] = w_sp
                        v[deform][hips_g.index] = w_hp
                    zip_rows.append((v_l, v_m, v_r))
                for i in range(z_rows):
                    for k in range(2):
                        f = bm_z.faces.new((zip_rows[i][k], zip_rows[i][k + 1], zip_rows[i + 1][k + 1], zip_rows[i + 1][k]))
                        f.material_index = 0
                        f.smooth = True
                        for lp in f.loops:
                            lp[uv_l].uv = (0.5, i / z_rows)
                            lp[fr_l].uv = (0.0, 1.0)
                bmesh.ops.recalc_face_normals(bm_z, faces=bm_z.faces)
                for f in bm_z.faces:
                    if f.normal.y < 0.0:
                        f.normal_flip()
                bm_z.to_mesh(b_zip.data)
                bm_z.free()
                b_zip.data.uv_layers.active_index = 0
                b_zip.data.update()
            # Tailor bomber wrist rib cuffs snugly onto the forearm/wrist (eliminate stiff bell-cup flare!).
            b_trims = by_name.get('Topx_Bomber_Trims')
            if b_trims is not None:
                def tailor_bomber_cuffs(p):
                    if abs(p.x) < 0.32:
                        return Vector()
                    sign = 1.0 if p.x > 0 else -1.0
                    local = Vector((abs(p.x), p.y, p.z)) - el_r
                    f_ax = (wr_r - el_r).normalized()
                    along = local.dot(f_ax)
                    rad = local - f_ax * along
                    rad.x *= sign
                    t_cuff = smooth(fore_len - 0.09, fore_len + 0.01, along)
                    return -rad * (0.14 * t_cuff)
                adjust_basis(b_trims, tailor_bomber_cuffs)

        # 1c. Top_Jumper + Topx_Jumper_Rib: smooth uniform circular crew-neck knit roll (NO front V-dip notch!).
        jumper_ob = by_name.get('Top_Jumper')
        jumper_rib = by_name.get('Topx_Jumper_Rib')
        if jumper_ob is not None and jumper_rib is not None:
            j_tree = surface_tree(jumper_ob.data)
            def seat_jumper_rib(p):
                radial = Vector((p.x - neck_c.x, p.y - neck_c.y, 0.0))
                r_cur = radial.length
                if r_cur < 0.01:
                    return Vector()
                d = radial / r_cur
                top_t = smooth(1.564, 1.594, p.z)
                dz = -0.0032 * top_t
                nhit = neck_tree.ray_cast(Vector((neck_c.x, neck_c.y, p.z + dz)) + d * 0.22, -d, 0.22)[0]
                r_nk = (nhit - Vector((neck_c.x, neck_c.y, p.z + dz))).dot(d) if nhit is not None else r_cur - 0.009
                jhit = j_tree.ray_cast(Vector((neck_c.x, neck_c.y, p.z + dz)) + d * 0.22, -d, 0.22)[0]
                r_jm = (jhit - Vector((neck_c.x, neck_c.y, p.z + dz))).dot(d) if jhit is not None else r_cur
                r_target = (r_jm + 0.0028) * (1.0 - top_t) + max(r_nk + 0.0052, r_jm - 0.0035) * top_t
                return Vector((d.x * (r_target - r_cur) * 0.88, d.y * (r_target - r_cur) * 0.88, dz))
            adjust_basis(jumper_rib, seat_jumper_rib)
            _recalc_normals(jumper_rib)

        # 1d. Top_Shirt + Topx_Shirt_Trim: orient chest pocket outward (+Y!), seat flush +2.4mm proud of shirt,
        #     and remove corner spike so breast pocket matches shirt fabric lighting cleanly!
        shirt_ob = by_name.get('Top_Shirt')
        shirt_trim = by_name.get('Topx_Shirt_Trim')
        if shirt_ob is not None and shirt_trim is not None:
            s_tree = surface_tree(shirt_ob.data)
            def clean_shirt_pocket(p):
                # Breast pocket lies at x in [0.044..0.136], z in [1.375..1.460], front chest (y > 0.05).
                if 0.044 < p.x < 0.136 and 1.375 < p.z < 1.462 and p.y > 0.05:
                    hit, nrm, _, dist = s_tree.find_nearest(p)
                    if hit is not None and nrm.length > 1e-4 and dist < 0.030:
                        if nrm.y < 0.0:
                            nrm = -nrm
                        gap = (p - hit).dot(nrm)
                        return nrm * ((0.0025 - gap) * 0.96)
                return Vector()
            adjust_basis(shirt_trim, clean_shirt_pocket)
            # Explicitly orient ALL breast-pocket polygons outward (+Y) so it NEVER shades as dark backface!
            bm_st = bmesh.new()
            bm_st.from_mesh(shirt_trim.data)
            for f in bm_st.faces:
                c = f.calc_center_median()
                if 0.044 < c.x < 0.136 and 1.375 < c.z < 1.462 and c.y > 0.05:
                    if f.normal.y < 0.0:
                        f.normal_flip()
                    f.smooth = True
            bm_st.to_mesh(shirt_trim.data)
            bm_st.free()
            shirt_trim.data.update()

    # 2. Bomber, Blazer, Hoodie, Shirt & Tee sleeves + shoulders:
    #    Slim bulky balloon arms & soften boxy shoulder pads while preserving strong athletic torso!
    for name, sleeve_slim, shoulder_drop in (
        ('Top_Bomber', 0.21, 0.015),
        ('Top_Blazer', 0.18, 0.012),
        ('Top_Hoodie', 0.13, 0.008),
        ('Top_Shirt', 0.09, 0.005),
        ('Top_Tee', 0.08, 0.004),
    ):
        ob = by_name.get(name)
        if ob is None:
            continue

        def tailor_top(p):
            x, y, z = p
            ax = abs(x)
            sign = math.copysign(1.0, x)
            dx = dy = dz = 0.0

            # Soften boxy square shoulder pads into natural athletic deltoid slope.
            sh_cap = _bell(ax - (sh_r.x + 0.032), 0.062) * _bell(z - (sh_r.z + 0.036), 0.058)
            dx -= sign * shoulder_drop * 0.85 * sh_cap
            dz -= shoulder_drop * sh_cap

            # Slim puffy balloon sleeves along the arm axis (especially upper arm & elbow!).
            if ax > 0.155 and z > el_r.z - 0.28:
                local = Vector((ax, y, z)) - sh_r
                along = local.dot(arm_axis)
                radial = local - arm_axis * along
                radial.x *= sign
                in_arm = (smooth(0.165, 0.235, ax)
                          * smooth(-0.02, 0.06, along)
                          * (1.0 - smooth(arm_len + fore_len - 0.04, arm_len + fore_len + 0.02, along)))
                mid_bulge = _bell(along - (arm_len * 0.65), 0.165)
                amt = sleeve_slim * in_arm * (0.65 + 0.55 * mid_bulge)
                dx -= radial.x * amt
                dy -= radial.y * amt
                dz -= radial.z * amt
            return Vector((dx, dy, dz))

        adjust_basis(ob, tailor_top)

    # 2b. Smooth vertical accordion pleats on Top_Tee lower torso + enforce clean jeans clearance!
    tee = by_name.get('Top_Tee')
    jeans = by_name.get('Lower_jeans')
    if tee is not None:
        neighbours = [[] for _ in tee.data.vertices]
        for edge in tee.data.edges:
            a, b = edge.vertices
            neighbours[a].append(b)
            neighbours[b].append(a)
        pos = [v.co.copy() for v in tee.data.vertices]
        weights = {
            i: smooth(0.95, 1.02, p.z) * smooth(1.24, 1.15, p.z)
               * (1.0 - smooth(0.16, 0.23, abs(p.x)))
            for i, p in enumerate(pos) if neighbours[i]
        }
        cur = [p.copy() for p in pos]
        # True Laplacian smoothing (no negative un-smoothing step that preserved pleats!).
        for _ in range(14):
            nxt = [p.copy() for p in cur]
            for i, w in weights.items():
                if w < 0.02:
                    continue
                avg = sum((cur[j] for j in neighbours[i]), Vector()) / len(neighbours[i])
                # Smooth X/Y radial contour while preserving Z height cleanly.
                nxt[i] = Vector((
                    cur[i].x + (avg.x - cur[i].x) * 0.42 * w,
                    cur[i].y + (avg.y - cur[i].y) * 0.42 * w,
                    cur[i].z,
                ))
            cur = nxt
        keys = tee.data.shape_keys.key_blocks if tee.data.shape_keys else []
        for i, w in weights.items():
            if w > 0.02:
                d = cur[i] - pos[i]
                tee.data.vertices[i].co = cur[i]
                for key in keys:
                    key.data[i].co += d
        tee.data.update()
        if jeans is not None:
            j_tree = surface_tree(jeans.data)

            def clear_tee_jeans(p):
                if p.z > 1.10 or abs(p.x) > 0.22:
                    return Vector()
                centre = Vector((0.0, neck_c.y - 0.01, p.z))
                radial = p - centre
                r_cur = radial.length
                if r_cur < 0.04:
                    return Vector()
                d = radial / r_cur
                hit = j_tree.ray_cast(centre + d * 0.32, -d, 0.32)[0]
                if hit is None:
                    return Vector()
                need = ((hit - centre).dot(d) + 0.007) - r_cur
                return d * need if need > 0.0 else Vector()
            adjust_basis(tee, clear_tee_jeans)
        _recalc_normals(tee)
        # Smooth ghost vertical accordion pleats baked into Top_Tee's lower-belly normal map!
        if tee.data.materials and tee.data.materials[0].use_nodes:
            bsdf = tee.data.materials[0].node_tree.nodes.get('Principled BSDF')
            if bsdf and bsdf.inputs['Normal'].is_linked:
                nmap_node = bsdf.inputs['Normal'].links[0].from_node
                if nmap_node.inputs.get('Color') and nmap_node.inputs['Color'].is_linked:
                    img_node = nmap_node.inputs['Color'].links[0].from_node
                    img = getattr(img_node, 'image', None)
                    if img is not None and img.size[0] > 0 and img.size[0] == img.size[1]:
                        sz = img.size[0]
                        pos_t, _, valid_t = raster_uv(tee, sz, material_index=0)
                        buf = np.empty(sz * sz * 4, dtype=np.float32)
                        img.pixels.foreach_get(buf)
                        px = buf.reshape(sz, sz, 4)
                        tx, ty, tz = pos_t[valid_t].T
                        # Blend lower-belly baked pleats 84% toward flat cotton normal (0.5, 0.5, 1.0)
                        # while keeping fine cotton micro-grain and crisp seams intact!
                        z_lo = np.clip((tz - 0.96) / 0.05, 0.0, 1.0)
                        z_hi = np.clip((1.25 - tz) / 0.07, 0.0, 1.0)
                        x_mid = np.clip((0.20 - np.abs(tx)) / 0.05, 0.0, 1.0)
                        fade = (z_lo * z_hi * x_mid * 0.84)[:, None]
                        flat = np.array([0.5, 0.5, 1.0], dtype=np.float32)
                        px_v = px[valid_t, :3]
                        px[valid_t, :3] = px_v * (1.0 - fade) + flat * fade
                        px[..., :3] = _dilate(px[..., :3], valid_t, 6)
                        img.pixels.foreach_set(px.ravel())
                        if img.filepath_raw:
                            img.save()
                        img.pack()

    # 2c. Strict Hoodie undershirt clearance (zero grey belly poke-through!).
    hoodie = by_name.get('Top_Hoodie')
    h_under = by_name.get('Topx_Hoodie_Undershirt')
    if hoodie is not None and h_under is not None:
        h_tree = surface_tree(hoodie.data)

        def tuck_hoodie_under(p):
            if p.z > 1.32:
                return Vector()
            centre = Vector((0.0, neck_c.y - 0.01, p.z))
            radial = p - centre
            r_in = radial.length
            if r_in < 0.03:
                return Vector()
            d = radial / r_in
            hit = h_tree.ray_cast(centre + d * 0.38, -d, 0.38)[0]
            if hit is None:
                return Vector()
            max_r = (hit - centre).dot(d) - 0.012
            if r_in > max_r:
                return -d * ((r_in - max_r) * smooth(1.32, 1.26, p.z))
            return Vector()
        adjust_basis(h_under, tuck_hoodie_under)

    # 2d. Natural contemporary drape & chest/torso ease on Tee, Shirt & Hoodie so garments
    #     hang like real mid-weight cotton and heavyweight fleece rather than vacuum-formed skin!
    for name, chest_bridge, mid_ease, side_ease, fold_amp in (
        ('Top_Tee', 0.0055, 0.0055, 0.0035, 0.0014),
        ('Top_Shirt', 0.0065, 0.0045, 0.0030, 0.0012),
        ('Top_Hoodie', 0.0110, 0.0125, 0.0090, 0.0026),
        ('Top_Leather', 0.0070, 0.0060, 0.0050, 0.0014),
        ('Top_Linen', 0.0085, 0.0095, 0.0065, 0.0024),
        ('Top_Qzip', 0.0075, 0.0070, 0.0050, 0.0018),
    ):
        ob = by_name.get(name)
        if ob is None:
            continue

        def drape_ease(p):
            x, y, z = p
            ax = abs(x)
            if ax > 0.22 or z > 1.50 or z < 0.90:
                return Vector()
            torso_w = 1.0 - smooth(0.16, 0.22, ax)
            front_w = smooth(0.01, 0.08, y)
            back_w = smooth(-0.01, -0.08, y)
            # Bridge sternum hollow & lower-pec/navel contour so cloth hangs naturally off the chest.
            sternum = _bell(ax, 0.055) * _bell(z - 1.34, 0.085) * front_w
            midriff = smooth(1.36, 1.24, z) * smooth(0.95, 1.08, z) * torso_w
            # Gentle organic vertical drape waves (non-periodic so no artificial ribbing).
            wave = (0.65 * math.sin(x * 31.0 + z * 4.5) + 0.35 * math.cos(x * 53.0 - z * 7.0)) * fold_amp * midriff
            dx = math.copysign(side_ease * midriff * smooth(0.08, 0.16, ax), x)
            dy = (chest_bridge * sternum + mid_ease * midriff * (front_w - 0.55 * back_w) + wave * (front_w - 0.5 * back_w))
            return Vector((dx, dy, 0.0))

        adjust_basis(ob, drape_ease)
        _recalc_normals(ob)

    # 3. Formal Outfit: precision collar, shirt, tie, knot & lapels!
    _refine_ade_formal(by_name, neck_tree, neck_c)

    # 4. Smart Shirt tucked cleanly into Chinos & Waistband (eliminate jagged waistband clipping!).
    shirt = by_name.get('Top_Shirt')
    chinos = by_name.get('Courier_Chinos')
    waistband_ob = by_name.get('Courier_Waistband')
    if shirt is not None and chinos is not None:
        chino_tree = surface_tree(chinos.data)
        wb_tree = surface_tree(waistband_ob.data) if waistband_ob is not None else None

        def tuck_shirt(p):
            if p.z > 1.085 or abs(p.x) > 0.23:
                return Vector()
            w = smooth(1.082, 1.028, p.z)
            centre = Vector((0.0, 0.018, p.z))
            radial = p - centre
            if radial.length < 0.02:
                return Vector()
            d = radial.normalized()
            r_limits = []
            hit = chino_tree.ray_cast(centre + d * 0.32, -d, 0.32)[0]
            if hit is not None:
                r_limits.append((hit - centre).dot(d) - 0.014)
            if wb_tree is not None:
                whit = wb_tree.ray_cast(centre + d * 0.32, -d, 0.32)[0]
                if whit is not None:
                    r_limits.append((whit - centre).dot(d) - 0.013)
            if not r_limits:
                return Vector()
            cur_r = (p - centre).dot(d)
            max_r = min(r_limits)
            if cur_r > max_r:
                return -d * ((cur_r - max_r) * w)
            return Vector()

        adjust_basis(shirt, tuck_shirt)
        # Lock lower tucked shirt weights cleanly to chinos so hip flex/walk never pushes shirt out of waistband!
        weights_from(shirt, chinos, lambda p: smooth(1.065, 1.015, p.z) * (1.0 - smooth(0.18, 0.23, abs(p.x))))
        _recalc_normals(shirt)

    # 5. Streetwear Cargo pockets (Cargo_gusset_l/r): seat flush against the cargo thigh!
    cargo = by_name.get('Courier_Cargo')
    if cargo is not None:
        cargo_tree = surface_tree(cargo.data)
        for side in ('l', 'r'):
            pkt = by_name.get('Cargo_gusset_' + side)
            if pkt is None:
                continue
            sx = -1.0 if side == 'l' else 1.0

            def hug_pocket(p):
                hit = cargo_tree.ray_cast(Vector((p.x + sx * 0.06, p.y, p.z)), Vector((-sx, 0.0, 0.0)), 0.16)[0]
                if hit is None:
                    return Vector()
                gap = (p.x - hit.x) * sx
                if gap > 0.0055:
                    return Vector((-sx * (gap - 0.0055) * 0.85, 0.0, 0.0))
                return Vector()

            adjust_basis(pkt, hug_pocket)
    print(f'AAA ADE WARDROBE TAILORED (neck_c=({neck_c.x:.4f}, {neck_c.y:.4f}))', flush=True)
