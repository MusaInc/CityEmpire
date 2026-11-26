"""Rest-mesh fitting for WorldState's two fixed heroes and their wardrobe.

The same displacement follows each sewn panel and trim, including its
corrective shapes. The existing bind pose, weights and UVs still drive the
garments in Godot.
"""
import math

from mathutils import Vector

from wardrobe_quality import adjust_basis, smooth


def bell(value, radius):
    return math.exp(-(value / radius) ** 2)


def refine_wardrobe(rig, meshes, identity):
    if rig.get('worldstate_tailoring'):
        return
    bones = rig.data.bones
    shoulder = bones['b_upper_arm_r'].head_local.copy()
    elbow = bones['b_forearm_r'].head_local.copy()
    wrist = bones['b_hand_r'].head_local.copy()
    knee = bones['b_shin_r'].head_local.copy()
    ankle = bones['b_foot_r'].head_local.copy()
    arm_axis = (elbow - shoulder).normalized()
    chest = bones['b_chest'].head_local.z
    hips = bones['b_hips'].head_local.z
    waist = hips + (chest - hips) * .55
    ade = identity == 'ade'

    def body(p):
        x, y, z = p
        side = abs(x)
        sign = math.copysign(1, x)
        torso = 1 - smooth(.16, .26, side)
        waist_fill = bell(z - waist, .115)
        hip_fill = bell(z - hips, .105)
        # Clean natural athletic male V-taper for Ade (smooth drape, no waist pinch); balanced waist for Jules.
        if ade:
            chest_build = bell(z - (chest + .07), .105)
            dx = x * torso * (-.014 * waist_fill + .018 * chest_build + .008 * hip_fill)
            dy = (y - .025) * torso * (-.020 * waist_fill + .014 * chest_build)
            shoulder_zone = bell(side - (shoulder.x + .035), .065) * bell(z - (shoulder.z + .015), .075)
            dx -= sign * .005 * shoulder_zone
            dz = -.007 * shoulder_zone
        else:
            dx = x * torso * (-.016 * waist_fill)
            dy = (y - .025) * torso * (-.012 * waist_fill)
            dz = 0.0
        if side > .15 and z > elbow.z - .12:
            local = Vector((side, y, z)) - shoulder
            along = local.dot(arm_axis)
            radial = local - arm_axis * along
            radial.x *= sign
            sleeve = smooth(.15, .22, side) * bell(along - .068, .115)
            forearm = bell(along - (elbow - shoulder).length - .073, .077)
            amount = (.11 if ade else .08) * sleeve + .035 * forearm
            dx -= radial.x * amount
            dy -= radial.y * amount
            dz -= radial.z * amount
        return Vector((dx, dy, dz))

    def top_fit(p, cut):
        x, y, z = p
        delta = body(p)
        side = abs(x)
        torso = 1 - smooth(.162, .234, side)
        below_chest = bell(z - (waist + .005), .138)
        front = smooth(.025, .093, y)
        back = smooth(.024, -.055, y)
        fitted = cut in ('vest', 'fashion_tank', 'fashion_crop', 'fashion_bodysuit', 'fashion_squareneck')
        outer = cut in ('bomber', 'blazer', 'hoodie', 'fashion_jacket', 'fashion_racer', 'fashion_moto', 'fashion_pullover', 'fashion_cardigan')
        ease = .006 if fitted else (.013 if outer else .010)
        if not ade:
            ease *= .25
        delta.x += x * torso * below_chest * ease / .16
        delta.y += (front - .64 * back) * ease * .55 * torso * below_chest
        # Subtle natural drape folds without washboard vertical accordion stripes on the belly.
        local = Vector((side, y, z)) - shoulder
        along = local.dot(arm_axis)
        radial = local - arm_axis * along
        radial.x *= math.copysign(1, x)
        sleeve = smooth(.18, .25, side) * smooth(-.015, .05, along)
        sleeve *= 1 - smooth((elbow - shoulder).length + .085, (wrist - shoulder).length - .025, along)
        delta += radial * sleeve * (.025 if outer else .020)
        if outer and radial.length_squared > 1e-8:
            bend = along - (elbow - shoulder).length
            compression = bell(bend + .018 + radial.y * .3, .056)
            ridges = math.sin(bend * 140 + radial.y * 24) * compression
            delta += radial.normalized() * ridges * sleeve * .0016
        return delta

    def lower_fit(p, name):
        delta = body(p)
        if any(word in name for word in ('skirt', 'dress', 'slip')):
            return delta
        x, y, z = p
        side = abs(x)
        if not ade and ankle.z < z < knee.z:
            t = (z - ankle.z) / (knee.z - ankle.z)
            centre = ankle.lerp(knee, t)
            amount = .19 * smooth(.18, .48, t) * (1 - smooth(.67, .97, t))
            delta.x += math.copysign(1, x) * (centre.x - side) * amount
            delta.y += (centre.y - y) * amount
        if any(word in name for word in ('leggings', 'bikershorts', 'legs', 'skin')):
            return delta
        # Full seat and a straighter fall to the ankle. Keep the centre
        # seam and hem mating points together across trousers and trim.
        leg = smooth(.036, .08, side)
        thigh = bell(z - (hips - .195), .17) * leg
        knee_relief = bell(z - (hips - .42), .15) * leg
        ease = .008 if 'joggers' in name else .013
        if not ade:
            ease *= 1 - smooth(hips - .125, hips - .045, z)
        delta.x += math.copysign(ease * (.7 * thigh + .45 * knee_relief), x)
        delta.y += (smooth(.022, .071, y) - smooth(.01, -.066, y) * .65) * ease * (thigh + .42 * knee_relief)
        if 'chinos' in name:
            centre = .099 + max(0.0, hips - z) * .065
            crease = bell(side - centre, .013) * smooth(.04, .075, y)
            delta.y += .0035 * crease * (thigh + knee_relief) * ease / .013
        return delta

    def hand_fit(p):
        sign = math.copysign(1, p.x)
        local = Vector((abs(p.x), p.y, p.z)) - wrist
        hand_axis = (wrist - elbow).normalized()
        along = local.dot(hand_axis)
        radial = local - hand_axis * along
        radial.x *= sign
        return body(p) - radial * (.085 * smooth(.003, .035, along))

    def shoe_fit(p):
        toe = smooth(.095, .194, p.y) * (1 - smooth(.095, .18, p.z))
        return Vector((-p.x * toe * .022, -.012 * toe, 0))

    for obj in meshes:
        name = obj.name.lower()
        if name.startswith(('top_', 'topx_')) and not name.endswith('_skirt'):
            cut = name.split('_', 1)[1]
            for suffix in ('_trim', '_collar', '_zip', '_neck', '_trims', '_cuffs', '_hem', '_rib',
                           '_bindings', '_under', '_undershirt', '_fold', '_hood', '_drawcords',
                           '_pocket', '_pockets', '_buttons', '_straps'):
                if cut.endswith(suffix):
                    cut = cut.removesuffix(suffix)
                    break
            adjust_basis(obj, lambda p: top_fit(p, cut))
        elif name.startswith(('lower_', 'cargo_gusset', 'courier_cargo', 'courier_chinos', 'courier_waistband',
                              'fashion_legs', 'fashion_slip', 'fashion_biker', 'fashion_barefoot', 'fashion_cropped')) or name.endswith('_skirt'):
            adjust_basis(obj, lambda p: lower_fit(p, name))
        elif name.startswith(('skin_hands', 'courier_gloves')):
            adjust_basis(obj, hand_fit)
        elif name.startswith(('skin_arms', 'fashion_torso_skin', 'fashion_crop_skin', 'build b anatomy')):
            adjust_basis(obj, body)
        elif name.startswith(('footwear_', 'courier_trainers', 'courier_soles')):
            adjust_basis(obj, shoe_fit)

    if ade:
        add_derbies(rig, meshes)
        from aaa_ade_wardrobe import refine_ade_wardrobe
        refine_ade_wardrobe(rig, meshes)
    garments = {obj.name: obj for obj in meshes}
    if not ade:
        hip = bones['b_thigh_r'].head_local
        for name in ('Fashion_Legs', 'Fashion_Barefoot_Legs'):
            keys = garments[name].data.shape_keys.key_blocks
            clearance = keys.get('MidiSeatClearance')
            if clearance is None:
                continue
            for rest, adjusted in zip(keys[0].data, clearance.data):
                p = rest.co
                if p.z <= .635:
                    continue
                centre = knee.lerp(hip, (p.z - knee.z) / (hip.z - knee.z))
                centre.x *= math.copysign(1, p.x)
                weight = .70 * smooth(.635, .765, p.z)
                adjusted.co = p + Vector((centre.x - p.x, centre.y - p.y, -.007)) * weight
    seams = [] if ade else [
        ('Top_Fashion_Moto', 'Topx_Fashion_Moto_Topstitch', 1.045, 1.38, .074, .039),
        ('Top_Fashion_Racer', 'Topx_Fashion_Racer_Topstitch', 1.18, 1.395, .104, .023)]
    for shell, name, hem, chest_height, width, flare in seams:
        meshes.append(topstitch(garments[shell], name, hem, chest_height, width, flare))
    rig['worldstate_tailoring'] = 1


def topstitch(shell, name, hem, chest_height, width, flare):
    """Sew paired thread rows onto the front panel and inherit its skin weights."""
    import bpy
    from garment_kit import weights_from
    from wardrobe_quality import surface_tree

    tree = surface_tree(shell.data)
    verts, faces = [], []
    for side in (-1.0, 1.0):
        for offset in (0.0, .004):
            length = chest_height - hem
            for step in range(int(length / .006)):
                row = []
                for gap, across in ((0, -.0004), (0, .0004), (.0034, .0004), (.0034, -.0004)):
                    z = hem + step * .006 + gap
                    t = (z - hem) / length
                    x = side * (width + offset + flare * t * t + across)
                    point, normal, _, _ = tree.ray_cast(Vector((x, .48, z)), Vector((0, -1, 0)))
                    if point is None or normal.y < .25:
                        break
                    row.append(point + normal * .0013)
                if len(row) == 4:
                    corners = tuple(range(len(verts), len(verts) + 4))
                    faces.append(corners[::-1] if side > 0 else corners)
                    verts.extend(row)

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    trim = bpy.data.objects.new(name, mesh)
    shell.users_collection[0].objects.link(trim)
    trim.parent = shell.parent
    trim.matrix_world = shell.matrix_world.copy()
    thread = bpy.data.materials.get('hero_sewing_thread')
    if thread is None:
        thread = bpy.data.materials.new('hero_sewing_thread')
        thread.use_nodes = True
        shader = thread.node_tree.nodes['Principled BSDF']
        shader.inputs['Base Color'].default_value = (.062, .046, .037, 1.0)
        shader.inputs['Roughness'].default_value = .87
    mesh.materials.append(thread)
    weights_from(trim, shell)
    deform = trim.modifiers.new('Armature', 'ARMATURE')
    deform.object = shell.parent
    trim.hide_set(True)
    return trim


def add_derbies(rig, meshes):
    """Leather derbies on the trainer's last (2026-11-26 rebuild).

    The old derby was the whole trainer squashed – its padded tongue and flat
    trainer laces stood up as a flap on the instep. Now: upper and sole only,
    the toe lengthened and slimmed to a chisel, the cupsole thinned to a
    leather sole with a heel block, a closed facing over the instep and four
    pairs of round waxed laces crossing it.
    """
    import bpy
    from mathutils.bvhtree import BVHTree

    parts = []
    by_name = {obj.name: obj for obj in meshes}
    for name in ('Courier_Trainers', 'Courier_Soles'):
        source = by_name[name]
        part = source.copy()
        part.data = source.data.copy()
        source.users_collection[0].objects.link(part)
        part.parent = rig
        part.hide_set(False)
        part.hide_render = False
        for index, material in enumerate(part.data.materials):
            leather = material.copy()
            leather.name = 'hero_fashion_shoe_derby_' + material.name.removeprefix('hero_')
            shader = leather.node_tree.nodes.get('Principled BSDF')
            if shader:
                shader.inputs['Roughness'].default_value = .46 if name != 'Courier_Soles' else .72
            part.data.materials[index] = leather

        def shape(p, sole=name == 'Courier_Soles'):
            toe = smooth(.078, .17, p.y)
            centre = math.copysign(.118, p.x)
            # a lower, longer, narrower toe; the collar a touch lower
            dx = (centre - p.x) * (.12 + toe * .18)
            dz = -max(0.0, p.z - .01) * (.10 + toe * .34)
            if sole:
                # leather sole ~9 mm, the heel block 2 cm: thin the cupsole's
                # walls towards the toe
                dz += -max(0.0, p.z - .004) * .45 * smooth(.02, .09, p.y)
            return Vector((dx, .030 * toe, dz))

        adjust_basis(part, shape)
        parts.append(part)

    bpy.ops.object.select_all(action='DESELECT')
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    derby = bpy.context.view_layer.objects.active
    derby.name = 'Footwear_derbies'
    derby.data.name = derby.name

    # Laces: four crossing pairs of 1.2 mm round cord on the facing.
    me = derby.data
    tree = BVHTree.FromPolygons([v.co for v in me.vertices], [p.vertices[:] for p in me.polygons])
    lace = bpy.data.materials.get('hero_derby_lace') or bpy.data.materials.new('hero_derby_lace')
    lace.use_nodes = True
    bsdf = lace.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (.035, .030, .028, 1)
    bsdf.inputs['Roughness'].default_value = .5
    me.materials.append(lace)
    slot = len(me.materials) - 1
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    deform = bm.verts.layers.deform.verify()
    group_index = {}
    for side in ('l', 'r'):
        g = derby.vertex_groups.get('b_foot_' + side) or derby.vertex_groups.new(name='b_foot_' + side)
        group_index[side] = g.index
    for side, sx in (('l', -1), ('r', 1)):
        vs = [v.co for v in me.vertices if v.co.x * sx > 0]
        axis = sum((v.x for v in vs), 0.0) / max(1, len(vs))

        def on_top(x, y):
            hit = tree.ray_cast(Vector((x, y, .4)), Vector((0, 0, -1)))[0]
            return hit + Vector((0, 0, .0016)) if hit is not None else None

        for row in range(4):
            y0 = .056 + row * .0125
            for cross in (-1, 1):
                a = on_top(axis - .011 * cross, y0)
                b = on_top(axis + .011 * cross, y0 + .0125)
                if a is None or b is None:
                    continue
                ring = []
                d = (b - a).normalized()
                n1 = d.cross(Vector((0, 0, 1))).normalized()
                n2 = d.cross(n1).normalized()
                for t in range(7):
                    c = a.lerp(b, t / 6) + Vector((0, 0, .0012 * math.sin(math.pi * t / 6)))
                    ring.append([bm.verts.new(c + (n1 * math.cos(k * math.tau / 6) + n2 * math.sin(k * math.tau / 6)) * .0012)
                                 for k in range(6)])
                for t in range(6):
                    for k in range(6):
                        f = bm.faces.new((ring[t][k], ring[t][(k + 1) % 6], ring[t + 1][(k + 1) % 6], ring[t + 1][k]))
                        f.material_index = slot
                        f.smooth = True
                for r in ring:
                    for v in r:
                        v[deform][group_index[side]] = 1.0
    bm.to_mesh(me)
    bm.free()
    me.update()
    derby.select_set(False)
    derby.hide_set(True)
    meshes.append(derby)
