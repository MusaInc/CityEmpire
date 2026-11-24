"""Surface and fit finish for the assembled Jules collection.

Works on skinned mesh coordinates. UV islands, weights and pose shapes remain
the contract between these meshes and the game.
"""
import math

import numpy as np
from mathutils import Vector

from build_b_surface import falloff, surface_detail
from garment_kit import seam_height, weights_from
from jules_accessories import finish_jules_accessories
from jules_collection import project_trim_uv
from wardrobe_quality import adjust_basis, smooth
from jules_upper_fit import fit_upper_collection


def bell(value, radius):
    return math.exp(-(value / radius) ** 2)


def shell_delta(p, side, depth):
    return Vector((p.x * side, (p.y - .020) * depth, 0))


def finish_sewn_details(collection):
    if collection.rig.get('jules_sewn_detail_uv'):
        return
    models = collection.models
    front = {'Topx_Fashion_Ribcrop_Placket', 'Lower_beltedmini_Buckle'}
    for name, ob in models.items():
        if name.startswith('Lower_utilitymini_Pocket'):
            project_trim_uv(ob.data, models['Lower_utilitymini'])
        if name in front or name == 'Topx_Fashion_Cowldress_Sash':
            for polygon in ob.data.polygons:
                outward = (Vector((polygon.center.x, polygon.center.y - .019, 0))
                           if name.endswith('_Sash') else Vector((0, 1, 0)))
                if polygon.normal.dot(outward) < 0:
                    polygon.flip()
            ob.data.update()
        if not ob.data.uv_layers and (name.startswith(('JulesAccessory_', 'Topx_Fashion_'))
                                      or name.startswith('Lower_beltedmini_')):
            project_trim_uv(ob.data)
    collection.rig['jules_sewn_detail_uv'] = 1


def finish_jules_collection(collection, output):
    """Refit the existing sewn panels and bake new textile relief."""
    if collection.rig.get('jules_surface_finish'):
        finish_sewn_details(collection)
        finish_jules_accessories(collection, output)
        return
    models = collection.models
    output.mkdir(parents=True, exist_ok=True)
    b = collection.rig.data.bones
    knee_z = b['b_shin_r'].head_local.z
    ankle_z = b['b_foot_r'].head_local.z

    def jeans(p):
        # Sculpted skin-tight high-waisted skinny jeans hugging hips, thighs, knees and calves!
        sign = 1.0 if p.x >= 0 else -1.0
        leg_center = .098 + max(0.0, .82 - p.z) * .062
        side = abs(p.x) - leg_center
        crease = bell(p.z - knee_z, .082) * smooth(.035, .092, p.y)
        stack = bell(p.z - (ankle_z + .095), .050)
        front = smooth(.027, .101, p.y)
        folds = .0024 * math.cos(p.z * 122 + side * 34) * crease
        folds += .0028 * math.cos(p.z * 162 + side * 27) * stack * front
        rise = bell(p.z - 1.011, .047)
        # Taper legs tightly around each leg axis below the crotch (z < 0.86) and hug hips closely!
        in_leg = smooth(.88, .74, p.z)
        calf = smooth(.62, .22, p.z)
        shrink = (.20 + .16 * calf) * in_leg * smooth(.018, .055, abs(p.x))
        hip_hug = .065 * bell(p.z - .93, .085)
        dx = -(p.x - sign * leg_center) * shrink - p.x * (.048 * rise + hip_hug)
        dy = -(p.y - .015) * (shrink * .92 + .052 * rise + hip_hug) + folds
        return Vector((dx, dy, 0))

    adjust_basis(models['Lower_relaxeddenim'], jeans)

    # Clean, continuous, tailored mini-skirt silhouette (NO conflicting shrink + mushroom hem explosion!).
    from wardrobe_quality import surface_tree
    from jules_upper_fit import relax_patch, vertex_neighbours
    legs_ob = models.get('Fashion_Legs')
    biker_ob = models.get('Fashion_Biker_Legs')
    if legs_ob is not None:
        # Subtle upper-thigh recess strictly under skirts + clean forefoot recess inside high-tops.
        def refine_legs_clearance(p):
            dx = dy = dz = 0.0
            if 0.68 < p.z < 0.94:
                w_th = smooth(0.68, 0.75, p.z) * smooth(0.94, 0.87, p.z)
                cx = math.copysign(0.095, p.x)
                dx -= (p.x - cx) * 0.065 * w_th
                dy -= (p.y - 0.015) * 0.065 * w_th
            if p.z < 0.115:
                w_ft = smooth(0.115, 0.075, p.z)
                cx = math.copysign(0.105, p.x)
                dx -= (p.x - cx) * 0.14 * w_ft
                dy -= (p.y - 0.055) * 0.14 * w_ft
                dz -= 0.004 * w_ft * smooth(0.03, 0.08, p.z)
            return Vector((dx, dy, dz))
        adjust_basis(legs_ob, refine_legs_clearance)

        legs_tree = surface_tree(legs_ob.data)
        # Ensure skinny/relaxed denim stays cleanly fitted (+5.5mm minimum clearance over actual leg geometry).
        denim_ob = models.get('Lower_relaxeddenim')
        if denim_ob is not None:
            def clear_skinny_jeans(p):
                if p.z > 0.82 or p.z < 0.08:
                    return Vector()
                hit, nrm, _, dist = legs_tree.find_nearest(p)
                if hit is None or nrm.length < 1e-4 or dist > 0.06:
                    return Vector()
                gap = (p - hit).dot(nrm)
                if gap < 0.0055:
                    return nrm * (0.0055 - gap)
                if gap > 0.0110:
                    return -nrm * min(0.018, (gap - 0.0110) * 0.72)
                return Vector()
            adjust_basis(denim_ob, clear_skinny_jeans)

        # Shrink Fashion_Slip cleanly inward so the dark inner slip NEVER pokes through mini skirts or gown!
        slip_ob = models.get('Fashion_Slip')
        if slip_ob is not None:
            adjust_basis(slip_ob, lambda p: Vector((-p.x * 0.24, -(p.y - 0.015) * 0.24, 0.0)))

        # Clean, sleek, continuous tailored mini-skirts (preserves intact continuous skirt topology
        # and pelvis/thigh blend weights so there are ZERO torn holes, ZERO front split & ZERO mushroom flare!).
        def skirt_fit(p, shaped):
            hem = smooth(1.005, .715, p.z)
            hip = bell(p.z - .905, .068)
            panel = math.atan2(p.x, p.y - .019)
            folds = math.cos(panel * 8 + (p.z - .75) * 10) * hem * (.0018 if shaped else .0026)
            # Sleek tailored A-line (utility) vs pencil (belted) silhouette matching refined hip proportions.
            depth = -.085 if shaped else -.042
            side = -.128 if shaped else -.082
            folds += (.009 if shaped else .006) * hip * smooth(.025, .090, p.y)
            delta = shell_delta(p, side * hem, depth * hem)
            delta.y += folds * math.cos(panel)
            delta.x += folds * math.sin(panel)
            return delta

        for skirt_name, shaped in (('Lower_beltedmini', True), ('Lower_utilitymini', False)):
            sk_ob = models.get(skirt_name)
            if sk_ob is None:
                continue
            adjust_basis(sk_ob, lambda p, sh=shaped: skirt_fit(p, sh))
            # Enforce clean outward +9mm clearance over Fashion_Legs & Fashion_Slip (strictly outward only, zero collapse!).
            def verify_mini_clear(p):
                if p.z < 0.65 or p.z > 1.03:
                    return Vector()
                hit, nrm, _, dist = legs_tree.find_nearest(p)
                if hit is not None and nrm.length > 1e-4 and dist < 0.045:
                    gap = (p - hit).dot(nrm)
                    if gap < 0.0095:
                        return nrm * (0.0095 - gap)
                return Vector()
            adjust_basis(sk_ob, verify_mini_clear)

        # Keep belt, buckle and utility pockets snapped flush onto the tailored skirts with matching weights!
        for parent_name, trim_prefixes, lift in (
            ('Lower_beltedmini', ('Lower_beltedmini_Belt', 'Lower_beltedmini_Buckle'), 0.0026),
            ('Lower_utilitymini', ('Lower_utilitymini_Pocket',), 0.0024),
        ):
            p_ob = models.get(parent_name)
            if p_ob is None:
                continue
            p_tree = surface_tree(p_ob.data)
            for t_name, t_ob in models.items():
                if any(t_name.startswith(pref) for pref in trim_prefixes):
                    def snap_trim(p):
                        hit, nrm, _, _ = p_tree.find_nearest(p)
                        if hit is None or nrm.length < 1e-4:
                            return Vector()
                        gap = (p - hit).dot(nrm)
                        return nrm * (lift - gap) * 0.92
                    adjust_basis(t_ob, snap_trim)
                    weights_from(t_ob, p_ob)

    # Clean, smooth athletic compression shorts from high waist (1.02) down to mid-thigh (0.68) — ZERO balloon hips!
    # Measure directly from Lower_leggings (full hip + thigh surface) instead of Fashion_Biker_Legs (which ends at z=0.68)!
    comp_ref = models.get('Lower_leggings') or biker_ob
    if comp_ref is not None and 'Lower_sprintshorts' in models:
        comp_tree = surface_tree(comp_ref.data)
        def hug_compression_shorts(p):
            if p.z > 1.03 or p.z < 0.64:
                return Vector()
            hit, nrm, _, dist = comp_tree.find_nearest(p)
            if hit is None or nrm.length < 1e-4 or dist > 0.09:
                return Vector()
            gap = (p - hit).dot(nrm)
            if gap < 0.0038:
                return nrm * (0.0038 - gap)
            if gap > 0.0062:
                return -nrm * min(0.036, (gap - 0.0062) * 0.92)
            return Vector()
        adjust_basis(models['Lower_sprintshorts'], hug_compression_shorts)
        # Smooth out any slight seam ridge on shorts.
        sh_ob = models['Lower_sprintshorts']
        sh_neigh = vertex_neighbours(sh_ob.data)
        sh_pos = [v.co.copy() for v in sh_ob.data.vertices]
        sh_inf = {i: 0.72 * smooth(1.015, 0.94, p.z) * smooth(0.66, 0.72, p.z) for i, p in enumerate(sh_pos) if sh_neigh[i]}
        sh_inf = {i: w for i, w in sh_inf.items() if w > 0.02}
        if sh_inf:
            sh_rel = relax_patch(sh_pos, sh_neigh, sh_inf, (.48, .44, .40, .36))
            for i in sh_inf:
                d = sh_rel[i] - sh_pos[i]
                sh_ob.data.vertices[i].co = sh_rel[i]
                if sh_ob.data.shape_keys:
                    for key in sh_ob.data.shape_keys.key_blocks:
                        key.data[i].co += d
            sh_ob.data.update()
            # Re-verify +4.0mm floor clearance over leggings/biker skin after smoothing!
            def verify_shorts_clear(p):
                hit, nrm, _, dist = comp_tree.find_nearest(p)
                if hit is not None and nrm.length > 1e-4 and dist < 0.05:
                    gap = (p - hit).dot(nrm)
                    if gap < 0.0040:
                        return nrm * (0.0040 - gap)
                return Vector()
            adjust_basis(sh_ob, verify_shorts_clear)

    def satin(p):
        angle = math.atan2(p.x, p.y - .019)
        lower = smooth(.92, .45, p.z)
        sweep = angle * 6 + p.z * 9.0
        cloth = .0030 * math.sin(sweep) * lower
        # Sleek figure-hugging evening column silhouette around hips/thighs with clean calf room!
        hip_taper = .10 * smooth(1.02, .74, p.z) * smooth(.48, .72, p.z)
        hem_taper = .03 * smooth(.72, .22, p.z)
        shrink = hip_taper + hem_taper
        return Vector((
            -p.x * shrink + cloth * math.sin(angle),
            -(p.y - .019) * (shrink * .88) + cloth * math.cos(angle),
            -.0020 * lower * math.sin(angle * 3),
        ))

    for name, ob in tuple(models.items()):
        if name.startswith('Topx_Fashion_Cowldress_') or name == 'Top_Fashion_Cowldress':
            adjust_basis(ob, satin)

    # Enforce strict +18mm radial clearance on Formal Gown skirt over JulesSkin_Cowldress (zero calf/hip poke!).
    gown_sk = models.get('Topx_Fashion_Cowldress_Skirt')
    gown_legs = models.get('JulesSkin_Cowldress_Bare') or models.get('JulesSkin_Cowldress')
    if gown_sk is not None and gown_legs is not None:
        gl_tree = surface_tree(gown_legs.data)
        def clear_gown_legs(p):
            if p.z > 0.98 or p.z < 0.08:
                return Vector()
            centre = Vector((0.0, 0.015, p.z))
            radial = p - centre
            r_cur = radial.length
            if r_cur < 0.03:
                return Vector()
            d = radial / r_cur
            hit = gl_tree.ray_cast(centre + d * 0.42, -d, 0.42)[0]
            if hit is None:
                return Vector()
            need = ((hit - centre).dot(d) + 0.022) - r_cur
            return d * need if need > 0.0 else Vector()
        adjust_basis(gown_sk, clear_gown_legs)

    fit_upper_collection(collection)

    # Snap formal dress sash tightly onto the newly tightened bodice/skirt waist,
    # match skirt waist seamlessly to bodice waist, and smooth the front center skirt crease!
    sash = models.get('Topx_Fashion_Cowldress_Sash')
    bodice = models.get('Top_Fashion_Cowldress')
    gown_sk = models.get('Topx_Fashion_Cowldress_Skirt')
    if bodice is not None and gown_sk is not None:
        bod_tree = surface_tree(bodice.data)
        # Seamless waist join: match skirt top waist (z > 0.96) smoothly to bodice hem radius!
        def blend_gown_waist(p):
            if p.z < 0.95:
                return Vector()
            w = smooth(0.95, 1.03, p.z)
            centre = Vector((0.0, 0.015, p.z))
            radial = p - centre
            r_cur = radial.length
            if r_cur < 0.03:
                return Vector()
            d = radial / r_cur
            hit = bod_tree.ray_cast(centre + d * 0.30, -d, 0.30)[0]
            if hit is None:
                return Vector()
            target_r = (hit - centre).dot(d) + 0.0020
            return d * ((target_r - r_cur) * 0.82 * w)
        adjust_basis(gown_sk, blend_gown_waist)

        # Close & WELD the front slit seam above z = 0.72 (located at x ~ -0.018!) so ZERO
        # vertical black seam line appears above the slit, and slim the outer hip flare so
        # Jules's relaxed right hand hangs completely clear of the gown!
        def close_gown_seam(p):
            delta = Vector()
            if p.z > 0.72 and p.y > 0.02 and abs(p.x + 0.017) < 0.022:
                w_close = smooth(0.72, 0.78, p.z) * smooth(0.022, 0.003, abs(p.x + 0.017))
                delta += Vector(((-0.017 - p.x) * 0.96 * w_close, 0.0012 * w_close, 0.0))
            if 0.72 < p.z < 0.98 and abs(p.x) > 0.14:
                w_hip = smooth(0.72, 0.80, p.z) * smooth(0.98, 0.91, p.z) * smooth(0.14, 0.195, abs(p.x))
                delta.x -= math.copysign(0.016 * w_hip, p.x)
            return delta
        adjust_basis(gown_sk, close_gown_seam)

        import bmesh as _bm_g
        bm_g = _bm_g.new()
        bm_g.from_mesh(gown_sk.data)
        seam_vs = [v for v in bm_g.verts if v.is_boundary and v.co.z > 0.73 and v.co.y > 0.02 and abs(v.co.x + 0.017) < 0.022]
        if len(seam_vs) >= 2:
            _bm_g.ops.remove_doubles(bm_g, verts=seam_vs, dist=0.016)
            _bm_g.ops.recalc_face_normals(bm_g, faces=bm_g.faces)
            bm_g.to_mesh(gown_sk.data)
            gown_sk.data.update()
        bm_g.free()

        sk_neigh = vertex_neighbours(gown_sk.data)
        sk_pos = [v.co.copy() for v in gown_sk.data.vertices]
        sk_inf = {
            i: 0.92 * smooth(0.45, 0.58, p.z) * smooth(1.03, 0.96, p.z) * smooth(0.01, 0.07, p.y) * smooth(0.075, 0.006, abs(p.x))
            for i, p in enumerate(sk_pos) if sk_neigh[i]
        }
        sk_inf = {i: w for i, w in sk_inf.items() if w > 0.02}
        if sk_inf:
            sk_rel = relax_patch(sk_pos, sk_neigh, sk_inf, (.55, .50, .46, .42, .38, .35))
            for i in sk_inf:
                d = sk_rel[i] - sk_pos[i]
                gown_sk.data.vertices[i].co = sk_rel[i]
                if gown_sk.data.shape_keys:
                    for key in gown_sk.data.shape_keys.key_blocks:
                        key.data[i].co += d
            gown_sk.data.update()

    if sash is not None and bodice is not None and gown_sk is not None:
        bod_tree = surface_tree(bodice.data)
        sk_tree = surface_tree(gown_sk.data)
        def snap_sash(p):
            h1 = bod_tree.find_nearest(p)
            h2 = sk_tree.find_nearest(p)
            best = h1 if (h1[0] is not None and (h2[0] is None or h1[3] < h2[3])) else h2
            if best[0] is None or best[1].length < 1e-4:
                return Vector()
            gap = (p - best[0]).dot(best[1])
            return best[1] * (0.0030 - gap) * 0.92
        adjust_basis(sash, snap_sash)

    # One descriptor per principal textile. The maps use real-world stitch
    # spacing and are baked into the existing packed UVs.
    textiles = {
        'Lower_relaxeddenim': ('denim', .84, .82),
        'Top_Fashion_Ribcrop': ('rib', .84, .68),
        'Top_Fashion_Zipcrop': ('shell', .70, .71),
        'Lower_utilitymini': ('shell', .82, .72),
        'Top_Fashion_Tailoredknit': ('rib', .79, .65),
        'Lower_beltedmini': ('crepe', .76, .54),
        'Top_Fashion_Crossbra': ('stretch', .76, .67),
        'Lower_sprintshorts': ('stretch', .78, .68),
        'Top_Fashion_Cowldress': ('satin', .52, .28),
        'Topx_Fashion_Cowldress_Skirt': ('satin', .54, .28),
    }
    for name, (fabric, roughness, strength) in textiles.items():
        garment = models[name]
        shader = garment.data.materials[0].node_tree.nodes.get('Principled BSDF')
        collection.roughness(shader, roughness)
        shader.inputs['Specular IOR Level'].default_value = .28 if fabric == 'satin' else .20
        shader.inputs['Sheen Weight'].default_value = .24 if fabric in ('rib', 'shell', 'crepe') else .18
        anisotropy = shader.inputs.get('Anisotropic')
        if fabric == 'satin' and anisotropy is not None:
            anisotropy.default_value = .12
        if shader.inputs['Normal'].is_linked and shader.inputs['Base Color'].is_linked:
            surface_detail(garment, output, textile_field(fabric, name), strength,
                           texture_key="jules_" + name.lower())

    # Delicate flush pocket topstitching seated tightly onto the denim with outward +Y normals!
    denim = models['Lower_relaxeddenim']
    thread = collection.material('hero_jules_denim_thread', (.76, .64, .44), .84)
    for side, tag in [(-1, 'L'), (1, 'R')]:
        points = [(side * (0.072 + .066*t + .026*t*t), 1.010 - .110*t)
                  for t in (i/21 for i in range(22))]
        t_name = f'Lower_relaxeddenim_PocketThread{tag}'
        collection.surface_strip(t_name, denim, points, .00035, thread, .00075)
        t_ob = models.get(t_name)
        if t_ob is not None:
            for poly in t_ob.data.polygons:
                if poly.normal.y < 0.0:
                    poly.flip()
            t_ob.data.update()
    shoe = models['Footwear_highstreet']
    # Give high-tops clean room around the ankle and forefoot so socks NEVER poke through!
    adjust_basis(shoe, lambda p: Vector((math.copysign(.0042 * smooth(.03, .11, p.z), p.x),
                                         .0068 * smooth(.065, .158, p.y),
                                         .0055 * bell(p.y - .114, .048) * smooth(.040, .082, p.z))))
    # Keep socks cleanly outside ankle skin in walk/run/sit & recess biker forefoot cleanly inside shoes!
    socks = models.get('Fashion_Lounge_Socks')
    if socks is not None:
        def fit_socks(p):
            w = smooth(0.18, 0.06, p.z)
            cx = math.copysign(0.105, p.x)
            radial = Vector((p.x - cx, p.y - 0.012, 0.0))
            if radial.length < 1e-4:
                return Vector()
            return radial.normalized() * (0.0032 * w)
        adjust_basis(socks, fit_socks)
    biker_legs = models.get('Fashion_Biker_Legs')
    if biker_legs is not None:
        def tuck_biker_foot(p):
            if p.z >= 0.12:
                return Vector()
            w = smooth(0.12, 0.065, p.z)
            cx = math.copysign(0.105, p.x)
            return Vector((-(p.x - cx) * 0.14 * w, -(p.y - 0.04) * 0.14 * w, 0.0))
        adjust_basis(biker_legs, tuck_biker_foot)
    for name in ('Footwear_highstreet', 'Footwear_pumps', 'Footwear_eveningstraps'):
        for mat in models[name].data.materials:
            if mat.name.startswith(('hero_fashion_shoe_', 'hero_streettrainer_upper')):
                shader = mat.node_tree.nodes.get('Principled BSDF')
                collection.roughness(shader, .48 if name == 'Footwear_pumps' else .66)
                shader.inputs['Specular IOR Level'].default_value = .24 if name == 'Footwear_highstreet' else .34
    for name, ob in models.items():
        if name.startswith('JulesAccessory_'):
            for mat in ob.data.materials:
                shader = mat.node_tree.nodes.get('Principled BSDF')
                shader.inputs['Metallic'].default_value = .54
                collection.roughness(shader, .26)

    collection.rig['jules_surface_finish'] = 1
    finish_sewn_details(collection)
    finish_jules_accessories(collection, output)


def textile_field(style, name):
    """Return the textile's dye and tangent relief in metres."""
    grains = {'denim': .000098, 'rib': .000165, 'shell': .000067,
              'crepe': .000082, 'stretch': .000063, 'satin': .000018}

    def evaluate(p, n):
        x, y, z = p.T
        a = np.arctan2(x, y - .019)
        axis = np.where(n[:, 1] > 0, x, y)
        front = falloff(.012, .086, y)
        grain = (np.sin(axis * 2350 + z * 1168) * np.sin(z * 1910 - axis*520)
                 + .43 * np.sin((axis + z) * 4231))
        if style == 'rib':
            grain = np.cos(axis*1960 + z*58) + .35*grain
        if style == 'denim':
            # Subtle, non-aliasing fine twill weave (eliminates diagonal zebra moire across legs!).
            grain = 0.32 * np.cos((axis + z * .55) * 1450) * np.cos(z * 1120) + 0.25 * grain
        relief = grains[style] * grain
        dye = 1 + grain * (.014 if style == 'satin' else (.015 if style == 'denim' else .022))
        if style == 'denim':
            thigh = np.exp(-((z-.79)/.16)**2) * front
            knee_fade = np.exp(-((z-.52)/.09)**2) * front
            wash = (.12 * thigh + .06 * knee_fade) * np.exp(-((np.abs(x)-.108)/.058)**2)
            whisker = np.sin((z + np.abs(x)*.20)*155 + x*12)
            dye *= (.925 + wash + .018 * whisker * thigh)
            relief += .000055 * whisker * thigh
            relief += seam_height(np.abs(x) - (.166 + (.99-z)*.056), z, groove=.00028,
                                  width=.0016, stitch_off=.0028, stitch_len=.0027, stitch_h=.00023)
        elif style in ('stretch','shell','crepe'):
            zhem = .718 if name.startswith('Lower_') else 1.204 if style == 'stretch' else 1.164
            relief += seam_height(z-zhem, a, groove=.00013, width=.002,
                                  stitch_off=.0029, stitch_len=.0032, stitch_h=.00012)
        return dye[:, None], relief

    return evaluate
