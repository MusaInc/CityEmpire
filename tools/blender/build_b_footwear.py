"""Shape the fitted Build B footwear and build its small construction details."""

from collections import Counter
import math

import bmesh
import bpy
from mathutils import Vector

from garment_kit import weights_from
from wardrobe_quality import adjust_basis, smooth, surface_tree


TRAINER_PARTS = ('Courier_Trainers', 'Courier_Soles', 'Courier_TrainerTongues', 'Courier_TrainerLaces')


def last_delta(p, joints):
    side = 'r' if p.x > 0 else 'l'
    axis = joints['foot_' + side].x
    sign = 1 if p.x > 0 else -1
    toe = smooth(.076, .180, p.y)
    loft = smooth(.002, .027, p.z) * (1 - smooth(.033, .098, p.z))
    x = -.105 * (p.x - axis) * toe - sign * .0048 * toe
    z = -.0043 * loft - .0028 * toe * smooth(.027, .062, p.z)
    return Vector((x, .0080 * toe, z))


def shader_material(name, colour, roughness):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*colour, 1)
    shader.inputs['Roughness'].default_value = roughness
    return material


def quad_grid(rows, closed=False):
    width = len(rows[0])
    faces = [(i * width + j, i * width + (j + 1) % width, (i + 1) * width + (j + 1) % width,
              (i + 1) * width + j)
             for i in range(len(rows) - 1) for j in range(width if closed else width - 1)]
    return [p for row in rows for p in row], faces


def insert_parts(obj, parts, replace=False):
    """Add shoe construction pieces to an existing skinned render mesh."""
    mesh = obj.data
    bm = bmesh.new()
    if not replace:
        bm.from_mesh(mesh)
    uv = bm.loops.layers.uv.get('SurfaceUV') or bm.loops.layers.uv.active or bm.loops.layers.uv.new('SurfaceUV')
    bm.loops.layers.uv.get('ClothFreedom') or bm.loops.layers.uv.new('ClothFreedom')
    deform = bm.verts.layers.deform.verify()
    groups = {}
    for side in ('l', 'r'):
        name = 'b_foot_' + side
        groups[side] = (obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)).index
    for points, faces, material in parts:
        slot = mesh.materials.find(material.name)
        if slot == -1:
            mesh.materials.append(material)
            slot = len(mesh.materials) - 1
        added = []
        patch = []
        for p in points:
            vert = bm.verts.new(p)
            side = 'r' if p.x > 0 else 'l'
            vert[deform][groups[side]] = 1
            added.append(vert)
        for indices in faces:
            face = bm.faces.new([added[i] for i in indices])
            face.material_index = slot
            face.smooth = True
            for loop in face.loops:
                p = loop.vert.co
                loop[uv].uv = (abs(p.x) * 7.1, (p.y + .055 + p.z * .35) * 4.2)
            patch.append(face)
        bmesh.ops.recalc_face_normals(bm, faces=patch)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def shoe_top(trees, x, y):
    hits = [tree.ray_cast(Vector((x, y, .19)), Vector((0, 0, -1)), .15)[0] for tree in trees]
    return max((p for p in hits if p is not None), key=lambda p: p.z, default=None)


def lace_parts(upper, tongue, joints, lace, trim):
    trees = [surface_tree(mesh.data) for mesh in (upper, tongue)]
    parts = []
    for side in ('l', 'r'):
        axis = joints['foot_' + side].x
        anchors = []
        for row in range(5):
            y = .054 + row * .0135
            span = .0227 - row * .0016
            left = shoe_top(trees, axis - span, y)
            right = shoe_top(trees, axis + span, y)
            if left is None or right is None:
                continue
            anchors.append((left, right))
            for p in (left, right):
                centre = p + Vector((0, 0, .0009))
                rings = []
                for radius, height in ((.0027, 0), (.00245, .00125), (.00154, .00125), (.0014, .00035)):
                    rings.append([centre + Vector((radius * math.cos(i * math.tau / 10),
                                                  radius * math.sin(i * math.tau / 10), height))
                                  for i in range(10)])
                parts.append((*quad_grid(rings, closed=True), trim))

        for lower, upper_anchors in zip(anchors, anchors[1:]):
            for pass_index in (0, 1):
                start, end = lower[pass_index], upper_anchors[1 - pass_index]
                direction = Vector((end.x - start.x, end.y - start.y, 0)).normalized()
                side_vec = direction.cross(Vector((0, 0, 1))) * .0013
                rows = []
                for i in range(10):
                    t = i / 9
                    point = start.lerp(end, t)
                    hit = shoe_top(trees, point.x, point.y)
                    if hit is None:
                        hit = point
                    loft = .0018 + (.0021 + pass_index * .0012) * math.sin(math.pi * t)
                    core = hit + Vector((0, 0, loft))
                    rows.append([core - side_vec, core + side_vec])
                parts.append((*quad_grid(rows), lace))
        if anchors:
            high_left, high_right = anchors[0]
            knot = (high_left + high_right) * .5
            support = shoe_top(trees, knot.x, knot.y)
            if support is not None:
                knot.z = support.z + .0045
                for sign in (-1, 1):
                    rows = []
                    for i in range(12):
                        t = i / 11
                        point = knot + Vector((sign * .014 * math.sin(math.pi * t),
                                               .0083 * math.sin(math.tau * t), .0038 * math.sin(math.pi * t)))
                        rows.append([point - Vector((0, .0010, 0)), point + Vector((0, .0010, 0))])
                    parts.append((*quad_grid(rows), lace))
    return parts


def collar_parts(upper, joints, trim):
    # The upper's own exposed ankle boundary is the guide for the rolled edge.
    mesh = upper.data
    border = Counter(tuple(sorted(k)) for poly in mesh.polygons for k in poly.edge_keys)
    parts = []
    for (a, b), count in border.items():
        if count != 1:
            continue
        p, q = mesh.vertices[a].co, mesh.vertices[b].co
        if min(p.z, q.z) < .052 or max(p.y, q.y) > .051:
            continue
        axis = joints['foot_r' if p.x > 0 else 'foot_l'].x
        radial = Vector(((p.x + q.x) / 2 - axis, (p.y + q.y) / 2 + .008, 0)).normalized()
        offset = radial * .0010
        rows = [[p + offset + Vector((0, 0, -.0021)), q + offset + Vector((0, 0, -.0021))],
                [p + offset + Vector((0, 0, .0009)), q + offset + Vector((0, 0, .0009))]]
        parts.append((*quad_grid(rows), trim))
    return parts


def sole_parts(sole, joints, trim, rubber):
    surface = surface_tree(sole.data)
    parts = []
    for side in ('l', 'r'):
        axis = joints['foot_' + side].x
        ring = []
        for z in (.0125, .0140, .0155):
            row = []
            centre = Vector((axis, .065, z))
            for i in range(64):
                a = i * math.tau / 64
                direction = Vector((math.sin(a), math.cos(a), 0))
                hit = surface.ray_cast(centre + direction * .19, -direction, .19)[0]
                row.append((hit if hit is not None else centre + direction * .043) + direction * .0012)
            ring.append(row)
        parts.append((*quad_grid(ring, closed=True), trim))
        for index, y in enumerate((-.025, -.006, .029, .068, .099, .130, .154)):
            half = .022 if index <= 2 else .026
            rows = []
            for height, bevel in ((-.0032, .0010), (.00055, 0)):
                row = []
                for x, travel in ((-half, -.0032), (-.0032, -.0032), (.0032, 0), (half, .0032),
                                  (half, .0066), (.0032, .0032), (-.0032, 0), (-half, 0)):
                    row.append(Vector((axis + math.copysign(max(0, abs(x) - bevel), x), y + travel, height)))
                rows.append(row)
            vertices, faces = quad_grid(rows, closed=True)
            width = len(rows[0])
            faces += [tuple(range(width - 1, -1, -1)), tuple(range(width, 2 * width))]
            parts.append((vertices, faces, rubber))
    return parts


def street_trainer(target, parts):
    """Use the fitted trainer construction for a lower-profile street last."""
    destination = target.data
    materials = {}
    points, polygons, specs = [], [], []
    for part in parts:
        mesh = part.data
        base = len(points)
        uv1 = mesh.uv_layers[0]
        uv2 = mesh.uv_layers.get('ClothFreedom')
        for vertex in mesh.vertices:
            p = vertex.co.copy()
            toe = smooth(.095, .186, p.y)
            p.y += .005 * toe
            p.z -= .0023 * smooth(.002, .030, p.z) * (1 - smooth(.038, .088, p.z))
            points.append(p)
        for poly in mesh.polygons:
            material = mesh.materials[poly.material_index]
            if material.name == 'hero_trainer_panels':
                if material not in materials:
                    clone = material.copy()
                    clone.name = 'hero_streettrainer_upper'
                    materials[material] = clone
                material = materials[material]
            polygons.append(tuple(i + base for i in poly.vertices))
            specs.append((material, [tuple(uv1.data[i].uv) for i in poly.loop_indices],
                          [tuple(uv2.data[i].uv) if uv2 is not None else (0, 0) for i in poly.loop_indices]))
    result = bpy.data.meshes.new(destination.name + '_Last')
    result.from_pydata(points, [], polygons)
    uv1 = result.uv_layers.new(name='SurfaceUV')
    uv2 = result.uv_layers.new(name='ClothFreedom', do_init=False)
    slots = {}
    for poly, (mat, uv, cloth) in zip(result.polygons, specs):
        if mat not in slots:
            slots[mat] = len(slots)
            result.materials.append(mat)
        poly.material_index = slots[mat]
        poly.use_smooth = True
        for loop_id, surface_uv, cloth_uv in zip(poly.loop_indices, uv, cloth):
            uv1.data[loop_id].uv = surface_uv
            uv2.data[loop_id].uv = cloth_uv
    result.uv_layers.active_index = 0
    result.update()
    target.data = result
    target.vertex_groups.clear()
    for side, sign in (('l', -1), ('r', 1)):
        group = target.vertex_groups.new(name='b_foot_' + side)
        group.add([i for i, p in enumerate(points) if p.x * sign > 0], 1.0, 'REPLACE')
    if not destination.users:
        bpy.data.meshes.remove(destination)


def fitted_leather_shoe(obj, joints, skin, style):
    """Loft separate leather uppers, turned openings and beveled rubber soles."""
    boot = style == 'boots'
    upper = obj.data.materials['hero_fashion_shoe_' + style]
    sole = obj.data.materials['hero_fashion_sole_' + style]
    edge = shader_material('hero_footwear_leather_edge', (.094, .075, .062), .64)
    upper.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = .56 if boot else .51
    legs = surface_tree(skin.data)
    angles = [i * math.tau / 48 for i in range(48)]
    parts = []

    def add(rows, material, caps=False):
        points, faces = quad_grid(rows, closed=True)
        if caps:
            count = len(rows[0])
            faces += [tuple(range(count - 1, -1, -1)), tuple(range(len(points) - count, len(points)))]
        parts.append((points, faces, material))

    for side, sign in (('l', -1), ('r', 1)):
        ankle, knee = (joints[name + '_' + side] for name in ('foot', 'shin'))

        def ankle_axis(z):
            return ankle.lerp(knee, (z - ankle.z) / (knee.z - ankle.z))

        def clear_ankle(row, gap):
            for p in row:
                if p.z < .055 or p.y > .062:
                    continue
                center = ankle_axis(p.z)
                direction = (p - center).normalized()
                hit = legs.ray_cast(center + direction * .087, -direction, .084)[0]
                if hit is not None:
                    p += direction * max(0, (hit - p).dot(direction) + gap)
            return row

        def last(z, width, front, back, heel_lift=0):
            row = []
            for a in angles:
                forward = math.cos(a)
                t = (1 + forward) * .5
                spread = .77 + .25 * smooth(.11, .58, t) + .14 * smooth(.54, .83, t)
                y = back + (front - back) * t
                x = ankle.x - sign * .012 * smooth(.032, .17, y) - width * spread * math.sin(a)
                taper = .005 * smooth(.140, .191, y)
                row.append(Vector((x, y, z + taper + heel_lift * (1 - smooth(-.010, .104, y)))))
            return row

        def cuff(z, gap):
            row = []
            for a in angles:
                height = z - .006 * math.cos(a) + .0015 * math.cos(2*a)
                center = ankle_axis(height)
                direction = Vector((-math.sin(a), math.cos(a), 0))
                hit = legs.ray_cast(center + direction * .087, -direction, .084)[0]
                row.append((hit if hit is not None else center + direction * .029) + direction * gap)
            return row

        if boot:
            add([last(z, w, f, b) for z, w, f, b in (
                (.002, .044, .187, -.043), (.006, .047, .191, -.046),
                (.016, .047, .191, -.046), (.021, .045, .189, -.044))], sole, caps=True)
            welt = last(.022, .044, .188, -.043)
            add([last(.018, .045, .189, -.044), welt], edge)
            lip = cuff(.159, .0080)
            add([welt, last(.035, .044, .184, -.044), clear_ankle(last(.051, .041, .159, -.046), .008),
                 clear_ankle(last(.069, .038, .117, -.046), .008),
                 clear_ankle(last(.087, .034, .076, -.047), .008),
                 cuff(.111, .008), cuff(.145, .0088), lip], upper)
            add([lip, cuff(.161, .0060), cuff(.160, .0045), cuff(.151, .0044)], edge)
        else:
            add([last(z, w, f, b, .024) for z, w, f, b in (
                (.004, .040, .187, -.043), (.006, .043, .191, -.045),
                (.012, .043, .191, -.045), (.014, .041, .189, -.044))], sole, caps=True)
            heel_rows = [[Vector((ankle.x - w * math.sin(a), -.015 + d * math.cos(a), z))
                          for a in angles] for z, w, d in (
                              (.002, .019, .022), (.006, .021, .024),
                              (.026, .022, .025), (.034, .022, .025))]
            add(heel_rows, sole, caps=True)
            lip = clear_ankle([Vector((ankle.x - .033 * math.sin(a),
                                      .008 + .050 * math.cos(a), .078 - .013 * math.cos(a)))
                               for a in angles], .005)
            add([last(.013, .041, .189, -.043, .024), last(.026, .042, .183, -.043, .022),
                 clear_ankle(last(.038, .039, .161, -.044, .020), .005),
                 clear_ankle(last(.049, .034, .116, -.043, .016), .005),
                 lip], upper)
            add([lip, [p.lerp(Vector((ankle.x, .008, p.z - .002)), .075) for p in lip],
                 [p.lerp(Vector((ankle.x, .008, p.z - .030)), .10) for p in lip]], edge)

    insert_parts(obj, parts, replace=True)
    weights_from(obj, skin, lambda p: smooth(.037, .066, p.z) * (1 - smooth(.050, .103, p.y)))


def fit_build_b_footwear(meshes, joints):
    wardrobe = {obj.name: obj for obj in meshes}
    trainer = [wardrobe[name] for name in TRAINER_PARTS]
    for obj in trainer[:3]:
        adjust_basis(obj, lambda p: last_delta(p, joints))
    upper, sole, tongue, laces = trainer
    trim = shader_material('hero_footwear_trim', (.34, .32, .29), .58)
    insert_parts(laces, lace_parts(upper, tongue, joints, laces.data.materials[0], trim), replace=True)
    insert_parts(tongue, collar_parts(upper, joints, trim))
    rubber = sole.data.materials.get('hero_outsole')
    insert_parts(sole, sole_parts(sole, joints, trim, rubber))
    street_trainer(wardrobe['Footwear_streettrainers'], trainer)
    for style in ('boots', 'heels'):
        fitted_leather_shoe(wardrobe['Footwear_' + style], joints, wardrobe['Fashion_Legs'], style)
    for name in ('hero_fashion_shoe_sandals', 'hero_fashion_sole_sandals'):
        mat = bpy.data.materials.get(name)
        if mat:
            mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = .68
