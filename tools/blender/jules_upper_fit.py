"""Fit the sewn upper panels to Jules's shoulder and chest."""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.geometry import barycentric_transform, intersect_point_line

from build_b_fit import blend_weights
from garment_kit import SkinSurface, weights_from
from wardrobe_quality import adjust_basis, smooth, surface_tree


def bell(value, radius):
    return math.exp(-(value / radius) ** 2)


def shoulder_line(p):
    x, y, z = p
    side = abs(x)
    cap = bell(side - .179, .056) * bell(z - 1.441, .045)
    pocket = bell(side - .147, .034) * bell(z - 1.355, .043)
    front = bell(y - .034, .044)
    return Vector((-x * .019 * cap + math.copysign(.0036 * pocket * front, x),
                   .0045 * pocket * front,
                   -.004 * cap + .005 * pocket * front))


def chest_fit(p, strength, ripple, ease):
    x, y, z = p
    front = smooth(.055, .114, y)
    apex = bell(abs(x) - .070, .038) * bell(z - 1.278, .041)
    bridge = bell(x, .035) * bell(z - 1.292, .054)
    cradle = bell(z - (1.220 - .011 * bell(abs(x) - .063, .034)), .025)
    cradle *= smooth(.133, .086, abs(x))
    waist = bell(z - 1.167, .076) * smooth(.172, .123, abs(x))
    fit = strength * (.004 * apex - .012 * bridge - .009 * cradle)
    return shoulder_line(p) + Vector((0, front * (fit + waist * (ease + ripple * math.sin(46*x + 75*z))), 0))


def collar_boundary(obj):
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    edges = [(edge.verts[0].co.copy(), edge.verts[1].co.copy(),
              edge.verts[0].index, edge.verts[1].index) for edge in mesh.edges
             if edge.is_boundary and all(1.38 < v.co.z < 1.455 and abs(v.co.x) < .134 for v in edge.verts)]
    mesh.free()
    return edges


def close_skin_join(torso, head, head_edges):
    """Seat the torso seam against the existing clavicle patch and match its skinning."""
    indices = {i for _, _, a, b in collar_boundary(torso) for i in (a, b)}
    original = {i: torso.data.vertices[i].co.copy() for i in indices}
    targets = {}
    for i, point in original.items():
        candidates = []
        for a, b, _, _ in head_edges:
            if (b-a).length_squared < 1e-12:
                continue
            _, t = intersect_point_line(point, a, b)
            candidates.append(a.lerp(b, min(1, max(0, t))))
        match = min(candidates, key=lambda p: (p - point).length_squared)
        if (match-point).length < .011:
            targets[i] = match

    keys = torso.data.shape_keys.key_blocks
    for i, target in targets.items():
        torso.data.vertices[i].co = target
        for key in keys:
            key.data[i].co = target
    neckline = surface_tree(head.data)
    def weight(point):
        _, _, _, distance = neckline.find_nearest(point, .012)
        return 0.0 if distance is None else smooth(.012, .001, distance)
    torso.data.update()
    weights_from(torso, head, weight)


def balance_arm_weights(obj, rig):
    """Spread the forward-arm load across the deltoid instead of one vertex row."""
    joints = rig.data.bones
    arms = {}
    for side in ('l', 'r'):
        root = joints['b_upper_arm_' + side].head_local
        arms[side] = (root, (joints['b_forearm_' + side].head_local - root).normalized())
    for vertex in obj.data.vertices:
        p = vertex.co
        if not (.118 < abs(p.x) < .280 and 1.29 < p.z < 1.49):
            continue
        side = 'l' if p.x < 0 else 'r'
        root, axis = arms[side]
        reach = (p - root).dot(axis)
        zone = smooth(.118, .149, abs(p.x)) * smooth(.280, .225, abs(p.x))
        zone *= smooth(1.29, 1.345, p.z) * smooth(1.49, 1.423, p.z)
        arm = smooth(-.014, .119, reach)
        blend_weights(obj, vertex, {'chest': 1-arm, 'upper_arm_' + side: arm}, zone)


def relax_forward_shoulders(torso, rig):
    """Relax the posed deltoid fold and put the correction back in bind space."""
    mesh = torso.data
    neighbours = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        neighbours[a].append(b)
        neighbours[b].append(a)
    identity = Matrix.Identity(3)
    for side, sign in [('l', -1), ('r', 1)]:
        name = 'b_upper_arm_' + side
        pivot = rig.data.bones[name].head_local
        arm_index = torso.vertex_groups[name].index
        rotation = Matrix.Rotation(math.radians(42), 3, 'X') @ Matrix.Rotation(math.radians(sign*30), 3, 'Y')
        posed, influence, inverse = [], {}, {}
        for vertex in mesh.vertices:
            p = vertex.co
            weight = next((g.weight for g in vertex.groups if g.group == arm_index), 0.0)
            amount = smooth(.123, .150, sign*p.x) * smooth(.264, .219, sign*p.x)
            amount *= smooth(1.305, 1.350, p.z) * smooth(1.466, 1.417, p.z)
            transform = identity * (1-weight) + rotation * weight
            posed.append(pivot + transform @ (p - pivot))
            if amount > .01 and neighbours[vertex.index]:
                influence[vertex.index] = amount
                inverse[vertex.index] = transform.inverted_safe()

        relaxed = [p.copy() for p in posed]
        for strength in (.61, -.20, .61, -.20, .51):
            changes = {}
            for i, amount in influence.items():
                centre = sum((relaxed[j] for j in neighbours[i]), Vector()) / len(neighbours[i])
                changes[i] = relaxed[i].lerp(centre, strength * amount)
            for i, point in changes.items():
                relaxed[i] = point

        correction = torso.shape_key_add(name='Reach_Shoulder_' + side)
        for i in influence:
            delta = inverse[i] @ (relaxed[i] - posed[i])
            if delta.length > .025:
                delta = delta.normalized() * .025
            correction.data[i].co += delta


def follow_correctives(obj, source):
    """Interpolate the donor's pose deltas on each small fitted trim."""
    if source.data.shape_keys is None:
        return
    surface = SkinSurface(source)
    keys = source.data.shape_keys.key_blocks
    samples = [surface.tree.find_nearest(v.co) for v in obj.data.vertices]
    obj.shape_key_add(name='Basis')
    for source_key in keys:
        if not source_key.name.startswith(('Bend_Shoulder_', 'Reach_Shoulder_')):
            continue
        key = obj.shape_key_add(name=source_key.name)
        for vertex, (hit, _, index, _) in zip(key.data, samples):
            if hit is None:
                continue
            ids = surface.triangles[index]
            a, b, c = [surface.positions[i] for i in ids]
            if (b-a).cross(c-a).length_squared < 1e-15:
                continue
            a, b, c = [source_key.data[i].co for i in ids]
            vertex.co += barycentric_transform(hit, *(surface.positions[i] for i in ids), a, b, c) - hit


def replace_straps(collection, clothing, torso):
    """Drape a flat ribbon over the shoulder and across to the opposite back."""
    body = surface_tree(torso.data)
    neckline = surface_tree(collection.models['Face_jules'].data)
    shell = surface_tree(clothing.data)
    elastic = collection.material('hero_fashion_top_jersey_bra_elastic', (.123, .127, .140), .74)
    for name in ('Straps', 'CrossLeft', 'CrossRight'):
        obsolete = collection.models.pop('Topx_Fashion_Crossbra_' + name)
        collection.meshes.remove(obsolete)
        bpy.data.objects.remove(obsolete, do_unlink=True)

    for sign, suffix in ((-1, 'Left'), (1, 'Right')):
        rings = []
        for step in range(46):
            t = step / 45
            points = []
            for edge in (-1, 1):
                width = .0088 - .0015 * smooth(.20, .49, t)
                x = sign * (.079 + .013 * bell(t - .32, .19) - .150 * smooth(.46, 1, t)) + edge * width
                theta = math.pi * min(1.0, t / .55)
                elevation = 1.327 + .038 * smooth(.25, .51, t) - .112 * smooth(.55, 1, t)
                pivot = Vector((x, .008, elevation))
                direction = Vector((0, math.cos(theta), math.sin(theta)))
                origin = pivot + direction * .24
                hit, normal, _, distance = body.ray_cast(origin, -direction, .40)
                shoulder, n, _, d = neckline.ray_cast(origin, -direction, .40)
                if shoulder is not None and shoulder.z < 1.47 and (hit is None or d < distance):
                    hit, normal = shoulder, n
                if hit is None:
                    raise RuntimeError(f'Jules shoulder strap left the body surface at sample {step} sign {sign} at {tuple(pivot)}')
                hem, hem_normal, _, _ = shell.ray_cast(origin, -direction, .25)
                overlap = smooth(.16, .018, t) + smooth(.87, .99, t)
                if hem is not None and (hem-hit).dot(direction) > 0 and overlap:
                    hit = hit.lerp(hem, overlap)
                    normal = normal.lerp(hem_normal, overlap).normalized()
                gap = .0045 + (0.0022 * bell(t - .77, .12) if sign > 0 else 0)
                points.append((hit + normal * gap, hit + normal * .0015))
            rings.append((points[0][0], points[1][0], points[1][1], points[0][1]))
        vertices = [point for row in rings for point in row]
        faces = [(3, 2, 1, 0)]
        for ring in range(len(rings) - 1):
            i = ring * 4
            faces.extend((i+k, i+(k+1)%4, i+4+(k+1)%4, i+4+k) for k in range(4))
        faces.append(tuple(range(len(vertices)-4, len(vertices))))
        name = f'Topx_Fashion_Crossbra_Support{suffix}'
        collection.attach_panel(name, torso, vertices, [face[::-1] for face in faces], elastic)
        strap = collection.models[name]
        follow_correctives(strap, torso)


def bra_band(collection, clothing):
    """Wrap the lower seam with a contoured folded elastic facing."""
    tree = surface_tree(clothing.data)
    elastic = collection.material('hero_fashion_top_jersey_bra_band', (.108, .111, .122), .77)
    points, faces = [], []
    samples = 72
    for i in range(samples):
        angle = i * math.tau / samples
        direction = Vector((math.sin(angle), math.cos(angle), 0))
        rows = []
        for lift in (.006, .011, .026, .030):
            def cast(z):
                origin = Vector((0, .018, z))
                return tree.ray_cast(origin + direction*.25, -direction, .25)[0]
            lo, hi = 1.18, 1.243
            for _ in range(9):
                mid = (lo+hi)/2
                if cast(mid) is None:
                    lo = mid
                else:
                    hi = mid
            hit = cast(hi + lift)
            if hit is None:
                raise RuntimeError(f'Jules bra band could not follow the hem at sample {i}')
            rows.append(hit + direction * (.0034 if .006 < lift < .030 else -.0004))
        points.extend(rows)
    for i in range(samples):
        a, b = i*4, ((i+1)%samples)*4
        faces.extend((a+j, a+j+1, b+j+1, b+j) for j in range(3))
    name = 'Topx_Fashion_Crossbra_Elastic'
    collection.attach_panel(name, clothing, points, faces, elastic)
    follow_correctives(collection.models[name], clothing)


def fit_upper_collection(collection):
    models = collection.models
    head = models['Face_jules']
    neckline_skin = surface_tree(head.data)
    head_edges = collar_boundary(head)
    for name in ('Fashion_Crop_Skin', 'Fashion_Torso_Skin', 'JulesSkin_Crossbra'):
        def skin_fit(point):
            _, _, _, distance = neckline_skin.find_nearest(point, .012)
            fade = 1.0 if distance is None else smooth(.002, .012, distance)
            return shoulder_line(point) * fade
        adjust_basis(models[name], skin_fit)
        balance_arm_weights(models[name], collection.rig)
        close_skin_join(models[name], head, head_edges)
        relax_forward_shoulders(models[name], collection.rig)

    for cut, strength, ripple, ease in (
        ('Ribcrop', .65, .0023, .001),
        ('Zipcrop', .52, .0031, .003),
        ('Tailoredknit', .77, .0016, .001),
        ('Cowldress', .60, 0, 0),
    ):
        for name, ob in tuple(models.items()):
            if name == f'Top_Fashion_{cut}' or name.startswith(f'Topx_Fashion_{cut}_'):
                adjusted = cut not in ('Cowldress', 'Zipcrop') or not name.endswith(('_Skirt', '_Sash', '_Hood'))
                if adjusted:
                    adjust_basis(ob, lambda p: chest_fit(p, strength, ripple, ease))
                    if name.startswith('Top_Fashion_'):
                        balance_arm_weights(ob, collection.rig)

    bra = models['Top_Fashion_Crossbra']
    skin = models['JulesSkin_Crossbra']
    body = surface_tree(skin.data)

    def support(p):
        delta = chest_fit(p, 1.25, .0009, 0)
        direction = Vector((p.x, p.y-.018, 0)).normalized()
        origin = Vector((0, .018, p.z))
        side = smooth(.065, .123, abs(p.x)) * smooth(.111, .058, p.y)
        if side > .001:
            hit, _, _, _ = body.ray_cast(origin + direction*.23, -direction, .23)
            if hit is not None:
                gap = max(0, (p-hit).dot(direction) - .007)
                delta -= direction * min(.034, gap) * side
        if p.y > .07 and abs(p.x) < .141:
            hit = body.ray_cast(Vector((p.x, .35, p.z)), Vector((0, -1, 0)))[0]
            if hit is not None:
                original_gap = p.y - hit.y
                clearance = min(.0045, original_gap)
                delta.y = max(delta.y, hit.y + clearance - p.y)
        return delta

    adjust_basis(bra, support)
    balance_arm_weights(bra, collection.rig)

    def neckline(p):
        x = abs(p.x)
        cup = bell(x - .076, .042)
        scoop = 1.316 + .030 * cup - .062 * smooth(.084, .143, x)
        back = 1.279 + .013 * smooth(.060, .133, x)
        limit = back + (scoop - back) * smooth(.042, .111, p.y)
        return limit - p.z

    collection.cut(bra, neckline, .0024)
    replace_straps(collection, bra, skin)
    bra_band(collection, bra)
