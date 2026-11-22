"""Local fit corrections for the exported wardrobe and its gameplay skeleton."""

import math

from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree


SKIRTS = {
    'Lower_miniskirt': .638,
    'Lower_midiskirt': .381,
    'Lower_maxiskirt': .109,
    'Topx_Fashion_Fitteddress_Skirt': .616,
    'Topx_Fashion_Loosedress_Skirt': .464,
}
HEADPHONE_HAIRS = ('buzz', 'crop', 'fade', 'curls', 'pixie', 'ponytail', 'bun')


def smooth(lo, hi, value):
    t = max(0.0, min(1.0, (value - lo) / (hi - lo)))
    return t * t * (3 - 2 * t)


def surface_tree(mesh):
    return BVHTree.FromPolygons([v.co for v in mesh.vertices], [p.vertices[:] for p in mesh.polygons])


def adjust_basis(obj, deform):
    """Move a sewn panel and its existing pose correctives by the same amount."""
    keys = obj.data.shape_keys
    for vertex in obj.data.vertices:
        delta = deform(vertex.co.copy())
        if keys:
            for key in keys.key_blocks:
                key.data[vertex.index].co += delta
        vertex.co += delta
    obj.data.update()



TUCKED_TOPS = ('Top_Long', 'Top_Tq', 'Top_Short', 'Top_Shirt', 'Topx_Shirt_Trim',
               'Top_Vest', 'Top_Fashion_Tank', 'Top_Fashion_Camisole',
               'Top_Fashion_Bodysuit', 'Top_Fashion_Blouse')


def fit_tucked_waists(objects):
    """Draft tucked hems inside the overlapping trouser and shorts waistband."""
    bottoms = [objects.get(name) for name in ('Courier_Cargo', 'Courier_Chinos', 'Lower_jeans',
               'Lower_joggers', 'Lower_shorts', 'Lower_leggings', 'Lower_fitjeans', 'Lower_tailoredshorts')]
    bands = [(surface_tree(ob.data), max(v.co.z for v in ob.data.vertices))
             for ob in bottoms if ob is not None]
    waist = min(height for _, height in bands)

    def tucked_delta(point):
        if not .90 < point.z < waist + .019 or abs(point.x) > .24:
            return Vector()
        center = Vector((0, .018, point.z))
        ray = point - center
        if ray.length < .045:
            return Vector()
        direction = ray.normalized()
        radii = []
        for tree, height in bands:
            sample = center.copy()
            sample.z = min(height - .004, point.z)
            hit = tree.ray_cast(sample + direction * .36, -direction, .32)[0]
            if hit is not None:
                radii.append((hit - sample).dot(direction))
        if not radii:
            return Vector()
        clearance = .008 if point.z < waist - .004 else .005
        overlap = max(0.0, ray.length - min(radii) + clearance)
        return -direction * min(overlap, .026) * (1 - smooth(waist - .004, waist + .019, point.z))

    for name in TUCKED_TOPS:
        obj = objects.get(name)
        if obj is not None:
            adjust_basis(obj, tucked_delta)


def shorten_build_b_neck(point):
    """Blend a shorter neck into the trapezius while keeping the head intact."""
    blend = smooth(1.485, 1.643, point.z)
    lateral = 1 - smooth(.074, .158, abs(point.x))
    head = smooth(1.562, 1.643, point.z)
    return Vector((0, 0, -.052 * blend * max(lateral, head)))


def fit_denim_jacket(obj):
    """Lengthen the cropped edge into a fitted waistband and round its side seams."""
    def hem_delta(point):
        if abs(point.x) > .2:
            return Vector()
        hem = 1 - smooth(1.063, 1.145, point.z)
        seam = smooth(.07, .16, abs(point.x))
        return Vector((math.copysign(.004 * hem * seam, point.x),
                       (point.y - .025) * .07 * hem,
                       -hem * (.048 - .008 * seam)))

    adjust_basis(obj, hem_delta)


def fit_camisole_straps(straps, camisole, skin):
    """Set each strap over the shoulder and bury its ends into the sewn edge."""
    body = surface_tree(skin.data)
    fabric = surface_tree(camisole.data)

    def strap_delta(p):
        hit = body.ray_cast(Vector((p.x, p.y, 1.66)), Vector((0, 0, -1)))[0]
        crown = smooth(1.418, 1.474, p.z)
        z = p.z
        if hit is not None and abs(hit.z - p.z) < .075:
            z = p.z * (1 - crown) + (hit.z + .0045) * crown
        end = 1 - smooth(1.408, 1.447, p.z)
        nearest, normal, _, distance = fabric.find_nearest(p)
        if nearest is not None and distance < .065:
            stitched = nearest - normal * .001
            return Vector((0, 0, z - p.z)) * (1 - end) + (stitched - p) * end
        return Vector((0, 0, z - p.z))

    adjust_basis(straps, strap_delta)


def seated_leg_transforms(joints):
    """Build the skinning matrices for flexed thighs and upright shins."""
    transforms = {}
    for side, sign in [('l', -1), ('r', 1)]:
        hip = joints['thigh_' + side]
        knee = joints['shin_' + side]
        ankle = joints['foot_' + side]
        bind = Matrix.Rotation(-sign * math.radians(5), 3, 'Y')
        spread = Matrix.Rotation(-sign * math.radians(4), 3, 'Y')
        thigh = Matrix.Rotation(math.pi / 2, 3, 'X') @ spread @ bind.inverted()
        knee_pos = hip + thigh @ (knee - hip)
        shin = spread @ bind.inverted()
        ankle_pos = knee_pos + shin @ (ankle - knee)
        transforms['b_thigh_' + side] = (thigh, hip - thigh @ hip)
        transforms['b_shin_' + side] = (shin, knee_pos - shin @ knee)
        transforms['b_foot_' + side] = (shin, ankle_pos - shin @ ankle)
    return transforms


def skin_matrices(obj, transforms):
    groups = {group.index: group.name for group in obj.vertex_groups}
    identity = Matrix.Identity(3)
    for vertex in obj.data.vertices:
        blend = identity.copy()
        offset = Vector()
        for group in vertex.groups:
            transform = transforms.get(groups[group.group])
            if transform:
                rotation, translation = transform
                blend += (rotation - identity) * group.weight
                offset += translation * group.weight
        yield blend, offset


def fit_skirt_correctives(obj, joints, hem, layers):
    """Limit stride deformation and form the seated drape over the bent leg mesh."""
    keys = obj.data.shape_keys.key_blocks
    waist = max(v.co.z for v in obj.data.vertices)
    transforms = seated_leg_transforms(joints)
    lining = []
    for layer in layers:
        posed = [matrix @ vertex.co + offset for vertex, (matrix, offset)
                 in zip(layer.data.vertices, skin_matrices(layer, transforms))]
        lining.append(BVHTree.FromPolygons(posed, [p.vertices[:] for p in layer.data.polygons]))

    seated_key = obj.shape_key_add(name='Hem_Seated')
    for vertex, (matrix, offset) in zip(obj.data.vertices, skin_matrices(obj, transforms)):
        p = vertex.co
        fall = max(0.0, waist - p.z)
        angle = math.atan2(p.x, p.y - .02)
        forward = math.cos(angle)
        seam = math.sin(angle)
        front_stretch = smooth(.025, .19, fall)
        knee_release = 1 - (.43 if hem < .52 else .18) * smooth(.32, .66, fall)
        for name in ('Hem_Front', 'Hem_Back'):
            key = keys[name].data[vertex.index]
            delta = key.co - p
            delta.y *= (.94 if name == 'Hem_Front' else .83) * knee_release
            if name == 'Hem_Front':
                delta.z += .028 * front_stretch * smooth(.22, .83, forward)
            key.co = p + delta

        lap = smooth(-.76, .32, forward)
        lap_length = min(fall, .455)
        below_knee = max(0.0, fall - .455)
        weight = smooth(.052, .177, fall)
        drape = p.copy()
        drape.y += lap_length * (.82 * lap - .10) * weight + .094 * smooth(.25, .72, fall) * (1 - lap)
        drape.z += lap_length * (.94 * lap + .12) * weight
        drape.z -= .031 * lap * smooth(.22, .43, fall)
        drape.z = min(drape.z, waist - .008 + .015 * (1 - lap))
        drape.z -= .022 * smooth(.27, .50, fall) * (1 - lap)
        drape.z += .20 * below_knee * (1 - lap)
        drape.x += .022 * seam * weight * (1 - .75 * abs(forward))
        drape.y += .028 * lap * smooth(.07, .29, fall)

        # The thigh and slip define the raised fabric surface. Use the same
        # envelope on both sides of the slit to keep neighboring panels level.
        contact = smooth(.04, .103, fall) * smooth(.30, .80, lap)
        if contact > 0 and .04 < drape.y < .47 and drape.z > .85:
            rise = 0.0
            for layer in lining:
                for dx in (-.009, 0.0, .009):
                    query = Vector((drape.x + dx, drape.y, 1.13))
                    hit = layer.ray_cast(query, Vector((0, 0, -1)), .22)[0]
                    if hit is not None:
                        rise = max(rise, hit.z + .011 - drape.z)
            drape.z += min(rise, .095) * contact

        # Convert the drafted surface into a pre-skin morph to preserve the
        # sewn waist and avoid applying thigh rotation twice.
        target = matrix.inverted_safe() @ (drape - offset)
        seated_key.data[vertex.index].co = p.lerp(target, smooth(.025, .103, fall))


def fit_headphone_band(obj, scalp, hair_by_style, axis_height=1.719):
    """Fit the padded side of the band to each groom, keeping the metal yokes fixed."""
    # sweep() builds the band last, with 17 rings of 16 points. It is the
    # only component that crosses the crest of the head.
    band = list(obj.data.vertices)[-272:]
    if not band or min(v.co.x for v in band) >= -.055 or max(v.co.x for v in band) <= .055:
        raise ValueError(f'Headphone band topology changed on {obj.name}')
    head = surface_tree(scalp.data)
    if obj.data.shape_keys is None:
        obj.shape_key_add(name='Basis')
    for style in HEADPHONE_HAIRS:
        hair = surface_tree(hair_by_style[style].data)
        name = 'Fit_' + style
        key = obj.data.shape_keys.key_blocks.get(name) or obj.shape_key_add(name=name)
        for vertex in band:
            key.data[vertex.index].co = vertex.co
        offsets = []
        for start in range(0, len(band), 16):
            ring = band[start:start + 16]
            centre = sum((v.co for v in ring), Vector()) / 16
            normal = Vector((centre.x, 0, centre.z - axis_height)).normalized()
            underside = min((v.co - centre).dot(normal) for v in ring)
            fit = []
            for sample in (-.010, 0.0, .010):
                origin = centre + normal * .12 + Vector((0, sample, 0))
                for tree in (head, hair):
                    hit = tree.ray_cast(origin, -normal)[0]
                    if hit is not None:
                        fit.append((hit - centre).dot(normal))
            slide = max(-.023, min(.018, max(fit, default=underside) - underside + .0015))
            anchor = smooth(0, 5, min(start // 16, 16 - start // 16))
            offsets.append((normal, slide * anchor))
        for row, (normal, slide) in enumerate(offsets):
            previous = offsets[max(0, row - 1)][1]
            following = offsets[min(16, row + 1)][1]
            delta = normal * ((previous + 2 * slide + following) / 4 if 0 < row < 16 else 0)
            for vertex in band[row * 16:(row + 1) * 16]:
                key.data[vertex.index].co += delta


def fit_sandals(obj, feet, bare_legs):
    """Make the sole and closed leather straps from the posed foot's actual last."""
    import bpy
    import bmesh
    from mathutils.geometry import convex_hull_2d

    def plantar_delta(point):
        lift = .022 * (1 - smooth(-.010, .06, point.z))
        return Vector((0, 0, lift))

    for skin in (feet, bare_legs):
        adjust_basis(skin, plantar_delta)
    tree = surface_tree(feet.data)
    verts, faces, material_ids = [], [], []
    groups = {'l': [], 'r': []}

    def add_surface(side, rows, material):
        """Build a closed shell with a top, two beveled sides and an underside."""
        start = len(verts)
        count = len(rows[0])
        for row in rows:
            verts.extend(row)
        groups[side].extend(range(start, len(verts)))
        for j in range(len(rows) - 1):
            for i in range(count):
                a = start + j * count
                k = (i + 1) % count
                faces.append((a + i, a + k, a + count + k, a + count + i))
                material_ids.append(material)
        faces.extend((tuple(reversed(range(start, start + count))), tuple(range(len(verts) - count, len(verts)))))
        material_ids.extend((material, material))

    def sole_span(perimeter, y):
        hits = []
        for i, a in enumerate(perimeter):
            b = perimeter[i - 1]
            if min(a.y, b.y) < y < max(a.y, b.y):
                t = (y - a.y) / (b.y - a.y)
                hits.append(a.lerp(b, t).x)
        return min(hits), max(hits)

    for side, sign in (('l', -1), ('r', 1)):
        foot = [v.co for v in feet.data.vertices if v.co.x * sign > 0 and v.co.z < .056]
        points = [v.to_2d() for v in foot]
        outline = [points[i] for i in convex_hull_2d(points)]
        center = sum(outline, Vector((0, 0))) / len(outline)
        outline = [p + (p - center).normalized() * .005 for p in outline]
        # Two corner cuts round the region between toes and the heel counter.
        for _ in range(2):
            original = outline
            outline = [a.lerp(b, t) for a, b in zip(original, original[1:] + original[:1])
                       for t in (.18, .82)]
        layers = []
        for z, bevel in ((.001, .0018), (.003, 0), (.009, 0), (.011, .0014)):
            layers.append([Vector((*tuple(p - (p - center).normalized() * bevel), z)) for p in outline])
        add_surface(side, layers, 0)

        for front, width in ((.037, .017), (.084, .015), (.124, .013)):
            rows = []
            lanes = [front + width * t for t in (-.5, -.25, .25, .5)]
            spans = [sole_span(outline, y) for y in lanes]
            for i in range(21):
                u = i / 20
                section = []
                for y, (left, right) in zip(lanes, spans):
                    x = left + .001 + (right - left - .002) * u
                    hit = tree.ray_cast(Vector((x, y, .105)), Vector((0, 0, -1)), .105)[0]
                    height = .007 if hit is None else max(.007, hit.z + .0018)
                    section.append(Vector((x, y, height)))
                # The narrow cross-section turns over at the stitching line.
                rows.append(section + [p - Vector((0, 0, .0018)) for p in reversed(section)])
            add_surface(side, rows, 1)

    materials = list(obj.data.materials)
    old_mesh = obj.data
    mesh = bpy.data.meshes.new(obj.name + '_Fitted')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    for mat in materials:
        mesh.materials.append(mat)
    uv = mesh.uv_layers.new(name='SurfaceUV')
    for poly, slot in zip(mesh.polygons, material_ids):
        poly.material_index = slot
        poly.use_smooth = slot == 1 or len(poly.vertices) == 4
        for loop_index in poly.loop_indices:
            point = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = ((abs(point.x) - .13) * 7.5, (point.y + .05) * 4)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    obj.data = mesh
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    for side, indices in groups.items():
        obj.vertex_groups.new(name='b_foot_' + side).add(indices, 1, 'REPLACE')
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)
