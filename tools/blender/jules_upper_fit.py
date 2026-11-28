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


def seat_shoulder_joints(rig):
    """Place the humeral pivots cleanly inside the anatomical deltoid heads and
    keep upper_arm -> forearm connected along the real arm axis (zero elbow kink)."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    bones = rig.data.edit_bones
    for side in ('l', 'r'):
        shoulder = bones['b_upper_arm_' + side]
        elbow = bones['b_forearm_' + side]
        shoulder.use_connect = False
        elbow.use_connect = False
        sign = -1.0 if side == 'l' else 1.0
        # Place glenohumeral pivot at the true anatomical humeral head center
        # (slight 1.5cm anatomical drop, never 4.9cm!) and connect tail -> elbow!
        shoulder.head = Vector((sign * 0.158, -0.002, 1.406))
        shoulder.tail = elbow.head.copy()
        name = 'b_clavicle_' + side
        clavicle = bones.get(name) or bones.new(name)
        clavicle.parent = bones['b_chest']
        clavicle.head = Vector((sign * 0.032, 0.042, 1.416))
        clavicle.tail = shoulder.head.copy()
    bpy.ops.object.mode_set(mode='OBJECT')


def shoulder_line(p):
    """Natural female shoulder, trapezius slope, clavicle, deltoid cap, axillary
    folds, and straight toned upper-arm contour (zero rubber-hose inflation)."""
    x, y, z = p
    side = abs(x)
    sign = math.copysign(1.0, x)

    # Gentle trapezius-to-acromion slope (eliminates the flat horizontal shoulder shelf).
    trap = bell(side - 0.115, 0.042) * bell(z - 1.425, 0.030) * bell(y + 0.006, 0.055)
    # Delicate clavicle contour on the front upper chest.
    clav = bell(side - 0.095, 0.040) * bell(z - 1.404, 0.015) * smooth(0.018, 0.055, y)
    # Rounded anatomical deltoid cap centered around the humeral head (x~0.175, z~1.395).
    deltoid = bell(side - 0.178, 0.036) * bell(z - 1.394, 0.034) * bell(y + 0.002, 0.046)
    # Softly defined anterior & posterior axillary folds (natural armpit transition).
    axilla_f = bell(side - 0.142, 0.022) * bell(z - 1.340, 0.028) * smooth(0.025, 0.068, y)
    axilla_b = bell(side - 0.145, 0.025) * bell(z - 1.344, 0.030) * smooth(-0.015, -0.062, y)

    # Natural toned feminine waist-to-hip proportion (neither harsh wasp-waist shelf nor boxy cylinder).
    torso = 1.0 - smooth(0.155, 0.215, side)
    waist_restore = bell(z - 1.132, 0.072) * torso
    hip_shelf = bell(z - 1.048, 0.038) * torso

    # Keep the proximal upper arm slender, straight and toned (NO +63% vertical noodle puff!).
    arm_mask = smooth(0.165, 0.225, side) * smooth(0.42, 0.30, side) * smooth(1.22, 1.30, z) * smooth(1.45, 1.39, z)
    centre_z = 1.406 - 0.78 * max(0.0, side - 0.158)
    radial_z = z - centre_z

    dx = (sign * (0.0045 * deltoid - 0.0040 * axilla_f)
          + x * (0.044 * waist_restore - 0.022 * hip_shelf))
    dy = (0.0032 * clav + 0.0035 * deltoid - 0.0042 * axilla_f + 0.0028 * axilla_b
          + (y - 0.018) * (0.032 * waist_restore - 0.015 * hip_shelf))
    dz = (-0.0045 * trap + 0.0055 * deltoid + 0.0022 * clav - 0.08 * radial_z * arm_mask)
    return Vector((dx, dy, dz))


def smooth_bust_skin(torso):
    """Soften MakeHuman's raw sharp nipple-apex vertices on torso skin meshes into a
    smooth, natural rounded bust contour so fitted tops never shrink-wrap into cones."""
    neigh = vertex_neighbours(torso.data)
    pos = [v.co.copy() for v in torso.data.vertices]
    inf = {}
    for i, p in enumerate(pos):
        if not neigh[i]:
            continue
        w = (smooth(1.18, 1.23, p.z) * smooth(1.36, 1.30, p.z)
             * smooth(0.035, 0.080, p.y) * smooth(0.145, 0.025, abs(p.x)))
        if w > 0.02:
            inf[i] = w
    if not inf:
        return
    # 20 clean Laplacian passes flatten the sharp anatomical nipple vertices completely!
    rel = relax_patch(pos, neigh, inf, (0.56,) * 20)
    keys = torso.data.shape_keys.key_blocks if torso.data.shape_keys else []
    for i in inf:
        d = rel[i] - pos[i]
        torso.data.vertices[i].co = rel[i]
        for key in keys:
            key.data[i].co += d
    torso.data.update()


def clean_folded_back_neck(obj):
    """Remove ALL folded-under inward-facing solidify rim faces strictly along the back neckline
    (|x| < 0.135, z > 1.355, y < 0.018, normal.y > 0.04) without touching sleeve shoulders!"""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bad = [
        f for f in bm.faces
        if abs(f.calc_center_median().x) < 0.135
        and f.calc_center_median().y < 0.018 and f.calc_center_median().z > 1.355
        and f.normal.y > 0.04
    ]
    if bad:
        bmesh.ops.delete(bm, geom=bad, context='FACES')
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context='VERTS')
        bm.to_mesh(obj.data)
        obj.data.update()
    bm.free()


def smooth_neckline_rim(obj, sk_tree):
    """Smooth jagged V-neck, shoulder & back neckline boundary edges on cut knit tops."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    # Identify boundary vertices along the entire neckline (front V, shoulders & back neck).
    rim = {}
    for e in bm.edges:
        if e.is_boundary and all(v.co.z > 1.23 and abs(v.co.x) < 0.155 for v in e.verts):
            a, b = e.verts[0].index, e.verts[1].index
            rim.setdefault(a, []).append(b)
            rim.setdefault(b, []).append(a)
    bm.free()
    chain = {i: nbs for i, nbs in rim.items() if len(nbs) == 2}
    if not chain:
        return
    pos = {i: obj.data.vertices[i].co.copy() for i in rim}
    for _ in range(14):
        nxt = dict(pos)
        for i, (a, b) in chain.items():
            mid = (pos[a] + pos[b]) * 0.5
            cur = pos[i]
            p_new = cur.lerp(mid, 0.50)
            hit, nrm, _, dist = sk_tree.find_nearest(p_new)
            if hit is not None and nrm.length > 1e-4 and dist < 0.04:
                gap = (p_new - hit).dot(nrm)
                if gap < 0.0046:
                    p_new = hit + nrm * 0.0048
            nxt[i] = p_new
        pos = nxt
    keys = obj.data.shape_keys.key_blocks if obj.data.shape_keys else []
    neigh = vertex_neighbours(obj.data)
    deltas = {i: pos[i] - obj.data.vertices[i].co for i in chain}
    # Carry smoothing softly 2 rings inward so no sliver triangles fold along the neckline.
    ring1 = {}
    for i, d in deltas.items():
        for j in neigh[i]:
            if j not in deltas:
                ring1.setdefault(j, []).append(d)
    for j, ds in ring1.items():
        deltas[j] = (sum(ds, Vector()) / len(ds)) * 0.52
    for i, d in deltas.items():
        obj.data.vertices[i].co += d
        for key in keys:
            key.data[i].co += d
    obj.data.update()


def smooth_sleeve_hems(obj, sk_tree):
    """Smooth jagged sawtooth boundary edges at sleeve cuffs on cut knit tops."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    rim = {}
    for e in bm.edges:
        if e.is_boundary and all(abs(v.co.x) > 0.215 and v.co.z > 0.92 for v in e.verts):
            a, b = e.verts[0].index, e.verts[1].index
            rim.setdefault(a, []).append(b)
            rim.setdefault(b, []).append(a)
    bm.free()
    chain = {i: nbs for i, nbs in rim.items() if len(nbs) == 2}
    if not chain:
        return
    pos = {i: obj.data.vertices[i].co.copy() for i in rim}
    for _ in range(12):
        nxt = dict(pos)
        for i, (a, b) in chain.items():
            p_new = pos[i].lerp((pos[a] + pos[b]) * 0.5, 0.50)
            hit, nrm, _, dist = sk_tree.find_nearest(p_new)
            if hit is not None and nrm.length > 1e-4 and dist < 0.04:
                gap = (p_new - hit).dot(nrm)
                if gap < 0.0055:
                    p_new = hit + nrm * 0.0058
            nxt[i] = p_new
        pos = nxt
    keys = obj.data.shape_keys.key_blocks if obj.data.shape_keys else []
    neigh = vertex_neighbours(obj.data)
    deltas = {i: pos[i] - obj.data.vertices[i].co for i in chain}
    ring1 = {}
    for i, d in deltas.items():
        for j in neigh[i]:
            if j not in deltas:
                ring1.setdefault(j, []).append(d)
    for j, ds in ring1.items():
        deltas[j] = (sum(ds, Vector()) / len(ds)) * 0.50
    for i, d in deltas.items():
        obj.data.vertices[i].co += d
        for key in keys:
            key.data[i].co += d
    obj.data.update()


def chest_fit(p, strength, ripple, ease):
    x, y, z = p
    front = smooth(.052, .112, y)
    # Soft, smooth natural bust shaping (NO sharp protruding apex points!).
    cup = bell(abs(x) - .068, .048) * bell(z - 1.274, .046)
    point_soft = bell(abs(x) - .065, .022) * bell(z - 1.268, .022)
    bridge = bell(x, .030) * bell(z - 1.288, .050)
    cradle = bell(z - (1.216 - .008 * bell(abs(x) - .066, .038)), .024)
    cradle *= smooth(.132, .082, abs(x))
    waist = bell(z - 1.155, .072) * smooth(.168, .120, abs(x))
    fit = strength * (.0032 * cup - .0048 * point_soft - .0075 * bridge - .0060 * cradle)
    return shoulder_line(p) + Vector((0, front * (fit + waist * (ease + ripple * math.sin(42*x + 68*z))), 0))


def collar_boundary(obj):
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    edges = [(edge.verts[0].co.copy(), edge.verts[1].co.copy(),
              edge.verts[0].index, edge.verts[1].index) for edge in mesh.edges
             if edge.is_boundary and all(1.38 < v.co.z < 1.455 and abs(v.co.x) < .134 for v in edge.verts)]
    mesh.free()
    return edges


def close_skin_join(torso, head, head_edges):
    """Seat the torso seam tightly against the neck/clavicle patch with zero gap."""
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
        if (match-point).length < .026:
            targets[i] = match

    keys = torso.data.shape_keys.key_blocks
    for i, target in targets.items():
        # Overlap torso collar boundary 1.8mm UP and 0.35mm proud onto Face_jules's lower collar
        # so T-junction edges NEVER open a hairline black crack on the clavicle!
        seamed = target + Vector((0.0, 0.00035, 0.0018))
        torso.data.vertices[i].co = seamed
        for key in keys:
            key.data[i].co = seamed
    # Smoothly align the immediate 2 rings below the boundary to Face_jules's tangent plane
    # so the neck-to-chest join is C1-continuous with zero self-shadow hairline crease.
    neckline = surface_tree(head.data)
    neighbours = vertex_neighbours(torso.data)
    ring1 = {j for i in targets for j in neighbours[i] if j not in targets}
    for j in ring1:
        linked = [targets[k] for k in neighbours[j] if k in targets]
        if linked:
            avg_t = sum(linked, Vector()) / len(linked)
            cur = torso.data.vertices[j].co
            hit, nrm, _, _ = neckline.find_nearest(avg_t)
            if hit is not None and nrm.length > 1e-4:
                # Project ring1 gently toward the neck's tangent plane at the seam.
                plane_off = (cur - hit).dot(nrm)
                delta = -nrm * (plane_off * 0.42)
            else:
                delta = Vector((0.0, (avg_t.y - cur.y) * 0.28, 0.0))
            torso.data.vertices[j].co += delta
            for key in keys:
                key.data[j].co += delta
    def weight(point):
        _, _, _, distance = neckline.find_nearest(point, .022)
        return 0.0 if distance is None else smooth(.022, .001, distance)
    torso.data.update()
    weights_from(torso, head, weight)


def balance_arm_weights(obj, rig):
    """Spread shoulder deformation smoothly across chest, clavicle and upper_arm."""
    joints = rig.data.bones
    arms = {}
    for side in ('l', 'r'):
        root = joints['b_upper_arm_' + side].head_local
        arms[side] = (root, (joints['b_forearm_' + side].head_local - root).normalized())
    for vertex in obj.data.vertices:
        p = vertex.co
        if not (.105 < abs(p.x) < .290 and 1.28 < p.z < 1.49):
            continue
        side = 'l' if p.x < 0 else 'r'
        root, axis = arms[side]
        reach = (p - root).dot(axis)
        zone = smooth(.105, .142, abs(p.x)) * smooth(.295, .240, abs(p.x))
        zone *= smooth(1.285, 1.340, p.z) * smooth(1.485, 1.420, p.z)
        front_fold = bell(p.y - .072, .050) * bell(abs(p.x) - .136, .036)
        arm = smooth(.122, .225, abs(p.x) + .24 * reach - .022 * front_fold)
        clavicle = (1 - arm) * .32 * bell(p.z - 1.412, .044) * smooth(.090, .135, abs(p.x))
        blend_weights(obj, vertex, {'chest': 1 - arm - clavicle, 'upper_arm_' + side: arm,
                                   'clavicle_' + side: clavicle}, zone)


def shoulder_loops(torso):
    """Split the long shoulder edges so the cap and axillary fold curve smoothly."""
    mesh = bmesh.new()
    mesh.from_mesh(torso.data)
    edges = [edge for edge in mesh.edges if edge.is_manifold and all(
        .127 < abs(v.co.x) < .265 and 1.306 < v.co.z < 1.435 for v in edge.verts)]
    bmesh.ops.subdivide_edges(mesh, edges=edges, cuts=1, use_grid_fill=True)
    mesh.to_mesh(torso.data)
    mesh.free()
    torso.data.update()


def vertex_neighbours(mesh):
    neighbours = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        neighbours[a].append(b)
        neighbours[b].append(a)
    return neighbours


def relax_patch(positions, neighbours, influence, strengths):
    relaxed = [p.copy() for p in positions]
    for strength in strengths:
        changes = {}
        for i, amount in influence.items():
            centre = sum((relaxed[j] for j in neighbours[i]), Vector()) / len(neighbours[i])
            changes[i] = relaxed[i].lerp(centre, strength * amount)
        for i, point in changes.items():
            relaxed[i] = point
    return relaxed


def round_socket(torso):
    mesh = torso.data
    neighbours = vertex_neighbours(mesh)
    positions = [v.co.copy() for v in mesh.vertices]
    influence = {}
    for i, p in enumerate(positions):
        mask = smooth(.124, .145, abs(p.x)) * smooth(.278, .217, abs(p.x))
        mask *= smooth(1.295, 1.344, p.z) * smooth(1.448, 1.398, p.z)
        if mask > .01 and neighbours[i]:
            influence[i] = mask
    rounded = relax_patch(positions, neighbours, influence, (.54, -.27, .52, -.20, .36))
    for i in influence:
        delta = rounded[i] - positions[i]
        for key in mesh.shape_keys.key_blocks:
            key.data[i].co += delta
        mesh.vertices[i].co = rounded[i]
    mesh.update()


def pose_shoulder_correctives(torso, rig):
    """Relax the deltoid in forward and raised poses and bake back to bind space."""
    mesh = torso.data
    neighbours = vertex_neighbours(mesh)
    identity = Matrix.Identity(3)
    for side, sign in [('l', -1), ('r', 1)]:
        name = 'b_upper_arm_' + side
        pivot = rig.data.bones[name].head_local
        arm_index = torso.vertex_groups[name].index
        reach = Matrix.Rotation(math.radians(42), 3, 'X') @ Matrix.Rotation(math.radians(sign*30), 3, 'Y')
        lift = Matrix.Rotation(math.radians(-sign*60), 3, 'Y')
        for label, rotation in [('Reach', reach), ('Lift', lift)]:
            posed, influence, inverse = [], {}, {}
            for vertex in mesh.vertices:
                p = vertex.co
                weight = next((g.weight for g in vertex.groups if g.group == arm_index), 0.0)
                amount = smooth(.109, .132, sign*p.x) * smooth(.283, .231, sign*p.x)
                amount *= smooth(1.287, 1.330, p.z) * smooth(1.443, 1.403, p.z)
                transform = identity * (1-weight) + rotation * weight
                posed.append(pivot + transform @ (p - pivot))
                if amount > .01 and neighbours[vertex.index]:
                    influence[vertex.index] = amount
                    inverse[vertex.index] = transform.inverted_safe()
            relaxed = relax_patch(posed, neighbours, influence, (.69, -.15, .69, -.15, .66, .51))
            if label == 'Lift':
                for i in influence:
                    # Restore the upper deltoid envelope as the humerus
                    # abducts, then fair it into the clavicle and upper arm.
                    p = mesh.vertices[i].co
                    bridge = bell(sign*p.x - .175, .049) * bell(p.z - 1.385, .033)
                    bridge *= bell(p.y - .004, .064) * smooth(.117, .152, sign*p.x)
                    relaxed[i].z += .039 * bridge
                relaxed = relax_patch(relaxed, neighbours, influence, (.61, .45, -.23))
            correction = torso.shape_key_add(name=f'{label}_Shoulder_{side}')
            limit = .057 if label == 'Lift' else .028
            for i in influence:
                delta = inverse[i] @ (relaxed[i] - posed[i])
                if delta.length > limit:
                    delta = delta.normalized() * limit
                correction.data[i].co += delta


def follow_correctives(obj, source):
    """Interpolate the donor's pose deltas on each small fitted trim."""
    if source.data.shape_keys is None:
        return
    surface = SkinSurface(source)
    keys = source.data.shape_keys.key_blocks
    samples = [surface.tree.find_nearest(v.co) for v in obj.data.vertices]
    if obj.data.shape_keys is None:
        obj.shape_key_add(name='Basis')
    for source_key in keys:
        if not source_key.name.startswith(('Bend_Shoulder_', 'Reach_Shoulder_', 'Lift_Shoulder_')):
            continue
        if obj.data.shape_keys.key_blocks.get(source_key.name) is not None:
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
    """Drape sleek, flush athletic elastic straps over the shoulder and crossed at back."""
    body = surface_tree(torso.data)
    neckline = surface_tree(collection.models['Face_jules'].data)
    shell = surface_tree(clothing.data)
    elastic = collection.material('hero_fashion_top_jersey_bra_elastic', (.123, .127, .140), .76)
    for name in ('Straps', 'CrossLeft', 'CrossRight'):
        obsolete = collection.models.pop('Topx_Fashion_Crossbra_' + name, None)
        if obsolete is not None:
            if obsolete in collection.meshes:
                collection.meshes.remove(obsolete)
            bpy.data.objects.remove(obsolete, do_unlink=True)

    for sign, suffix in ((-1, 'Left'), (1, 'Right')):
        raw_outer, raw_inner = [], []
        for step in range(46):
            t = step / 45
            row_out, row_in = [], []
            for edge in (-1, 1):
                width = .0068 - .0010 * smooth(.20, .50, t)
                x = sign * (.076 + .014 * bell(t - .34, .20) - .145 * smooth(.48, 1, t)) + edge * width
                theta = math.pi * min(1.0, t / .54)
                elevation = 1.330 + .044 * smooth(.24, .50, t) - .108 * smooth(.54, 1, t)
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
                overlap = smooth(.16, .025, t) + smooth(.85, .98, t)
                if hem is not None and (hem-hit).dot(direction) > 0 and overlap:
                    hit = hit.lerp(hem, overlap)
                    normal = normal.lerp(hem_normal, overlap).normalized()
                # Taper strap lift cleanly at front/back bra anchor points so straps emerge seamlessly (no knots!).
                end_taper = smooth(0.0, 0.14, t) * smooth(1.0, 0.86, t)
                gap = 0.0008 + (0.0018 + (0.0014 * bell(t - .77, .12) if sign > 0 else 0)) * end_taper
                row_out.append(hit + normal * gap)
                row_in.append(hit + normal * (0.0002 * end_taper))
            raw_outer.append(row_out)
            raw_inner.append(row_in)
        # Smooth strap edges 3x along t to eliminate any step/knot where strap leaves bra hem!
        for _ in range(3):
            raw_outer = [raw_outer[0]] + [
                [raw_outer[i - 1][e] * 0.25 + raw_outer[i][e] * 0.50 + raw_outer[i + 1][e] * 0.25 for e in (0, 1)]
                for i in range(1, len(raw_outer) - 1)
            ] + [raw_outer[-1]]
            raw_inner = [raw_inner[0]] + [
                [raw_inner[i - 1][e] * 0.25 + raw_inner[i][e] * 0.50 + raw_inner[i + 1][e] * 0.25 for e in (0, 1)]
                for i in range(1, len(raw_inner) - 1)
            ] + [raw_inner[-1]]
        rings = [(raw_outer[i][0], raw_outer[i][1], raw_inner[i][1], raw_inner[i][0]) for i in range(len(raw_outer))]
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


def replace_cowldress_straps(collection, dress, torso):
    """Build sleek, taut silk spaghetti straps anchored DIRECTLY inside the actual
    front sweetheart peak and back upper hem of Top_Fashion_Cowldress (mathematically
    impossible to float or disconnect!)."""
    body = surface_tree(torso.data)
    neckline = surface_tree(collection.models['Face_jules'].data)
    shell = surface_tree(dress.data)
    silk = dress.data.materials[0]
    for name in ('Straps', 'CrossLeft', 'CrossRight', 'StrapLeft', 'StrapRight'):
        obsolete = collection.models.pop('Topx_Fashion_Cowldress_' + name, None)
        if obsolete is not None:
            if obsolete in collection.meshes:
                collection.meshes.remove(obsolete)
            bpy.data.objects.remove(obsolete, do_unlink=True)

    dress_verts = [v.co.copy() for v in dress.data.vertices]
    for sign, suffix in ((-1, 'Left'), (1, 'Right')):
        # Locate the ACTUAL highest front & back neckline vertices on the dress near strap X!
        front_cands = [p for p in dress_verts if p.y > 0.06 and abs(p.x - sign * 0.066) < 0.016 and p.z > 1.26]
        back_cands = [p for p in dress_verts if p.y < -0.02 and abs(p.x - sign * 0.072) < 0.018 and p.z > 1.22]
        if not front_cands or not back_cands:
            continue
        p_front = max(front_cands, key=lambda p: p.z)
        p_back = max(back_cands, key=lambda p: p.z)
        # Find shoulder top directly on the skin above collarbone.
        sh_x = sign * 0.088
        sh_hit, sh_n, _, _ = body.ray_cast(Vector((sh_x, 0.006, 1.60)), Vector((0.0, 0.0, -1.0)), 0.35)
        n_hit, n_n, _, _ = neckline.ray_cast(Vector((sh_x, 0.006, 1.60)), Vector((0.0, 0.0, -1.0)), 0.35)
        if n_hit is not None and (sh_hit is None or n_hit.z > sh_hit.z):
            sh_hit, sh_n = n_hit, n_n
        p_top = sh_hit if sh_hit is not None else Vector((sh_x, 0.006, 1.425))

        # Start 12mm BELOW front edge (cleanly tucked into bodice!) -> shoulder apex -> 12mm BELOW back edge!
        a0 = p_front + Vector((0.0, -0.002, -0.012))
        a1 = p_front + Vector((sign * 0.006, 0.004, 0.045))
        a2 = p_top + Vector((0.0, 0.018, 0.012))
        a3 = p_top + Vector((0.0, -0.026, 0.008))
        a4 = p_back + Vector((sign * 0.006, -0.004, 0.055))
        a5 = p_back + Vector((0.0, 0.002, -0.012))

        def eval_chain(t):
            # Two smooth cubic Bezier arcs joining seamlessly at shoulder top p_top!
            if t <= 0.5:
                u = t * 2.0
                m = 1.0 - u
                return (m**3)*a0 + 3*(m**2)*u*a1 + 3*m*(u**2)*a2 + (u**3)*p_top
            u = (t - 0.5) * 2.0
            m = 1.0 - u
            return (m**3)*p_top + 3*(m**2)*u*a3 + 3*m*(u**2)*a4 + (u**3)*a5

        steps = 40
        centres = []
        normals = []
        for s in range(steps):
            t = s / (steps - 1)
            pt = eval_chain(t)
            # Project onto body/neckline skin over the shoulder (0.14 < t < 0.86) and onto dress shell at ends!
            in_body = smooth(0.10, 0.22, t) * smooth(0.90, 0.78, t)
            b_near = body.find_nearest(pt)
            n_near = neckline.find_nearest(pt)
            best_s = b_near
            if n_near[0] is not None and (best_s[0] is None or n_near[3] < best_s[3]):
                best_s = n_near
            d_near = shell.find_nearest(pt)
            if in_body > 0.5 and best_s[0] is not None and best_s[1].length > 1e-4:
                base, nrm = best_s[0], best_s[1].normalized()
                centres.append(base + nrm * 0.0018)
                normals.append(nrm)
            elif d_near[0] is not None and d_near[1].length > 1e-4:
                base, nrm = d_near[0], d_near[1].normalized()
                # Tuck very ends cleanly inside dress shell; lift smoothly onto skin at edge.
                tuck = -0.0004 if (t < 0.09 or t > 0.91) else 0.0014
                centres.append(base + nrm * tuck)
                normals.append(nrm)
            else:
                centres.append(pt)
                normals.append(Vector((0.0, 0.0, 1.0)))

        # Smooth centreline twice so strap lies taut & crisp with zero kinks!
        for _ in range(2):
            centres = [centres[0]] + [
                centres[i - 1] * 0.25 + centres[i] * 0.50 + centres[i + 1] * 0.25
                for i in range(1, len(centres) - 1)
            ] + [centres[-1]]

        rings = []
        width = 0.0022
        for i in range(len(centres)):
            p_c = centres[i]
            n_c = normals[i]
            tang = (centres[min(len(centres) - 1, i + 1)] - centres[max(0, i - 1)]).normalized()
            side = tang.cross(n_c)
            if side.length < 1e-4:
                side = Vector((1.0, 0.0, 0.0))
            else:
                side.normalize()
            p_l = p_c - side * width
            p_r = p_c + side * width
            rings.append((p_l + n_c * 0.0012, p_r + n_c * 0.0012, p_r - n_c * 0.0006, p_l - n_c * 0.0006))

        vertices = [point for row in rings for point in row]
        faces = [(3, 2, 1, 0)]
        for ring in range(len(rings) - 1):
            i = ring * 4
            faces.extend((i + k, i + (k + 1) % 4, i + 4 + (k + 1) % 4, i + 4 + k) for k in range(4))
        faces.append(tuple(range(len(vertices) - 4, len(vertices))))
        name = f'Topx_Fashion_Cowldress_Strap{suffix}'
        collection.attach_panel(name, torso, vertices, [face[::-1] for face in faces], silk)
        strap_ob = collection.models[name]
        # Recalculate outward face normals so straps match the exact matte burgundy dress tone!
        bm_s = bmesh.new()
        bm_s.from_mesh(strap_ob.data)
        bmesh.ops.recalc_face_normals(bm_s, faces=bm_s.faces)
        bm_s.to_mesh(strap_ob.data)
        bm_s.free()
        strap_ob.data.update()
        follow_correctives(strap_ob, torso)


def bra_band(collection, clothing):
    """Wrap the lower seam with a sleek contoured folded elastic facing."""
    tree = surface_tree(clothing.data)
    elastic = collection.material('hero_fashion_top_jersey_bra_band', (.108, .111, .122), .79)
    points, faces = [], []
    samples = 72
    for i in range(samples):
        angle = i * math.tau / samples
        direction = Vector((math.sin(angle), math.cos(angle), 0))
        rows = []
        for lift in (.003, .007, .024, .027):
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
            rows.append(hit + direction * (.0022 if .003 < lift < .027 else -.0003))
        points.extend(rows)
    for i in range(samples):
        a, b = i*4, ((i+1)%samples)*4
        faces.extend((a+j, a+j+1, b+j+1, b+j) for j in range(3))
    name = 'Topx_Fashion_Crossbra_Elastic'
    collection.attach_panel(name, clothing, points, faces, elastic)
    follow_correctives(collection.models[name], clothing)


def fit_upper_collection(collection):
    models = collection.models
    seat_shoulder_joints(collection.rig)
    head = models['Face_jules']
    neckline_skin = surface_tree(head.data)
    head_edges = collar_boundary(head)
    for name in ('Fashion_Crop_Skin', 'Fashion_Torso_Skin', 'JulesSkin_Crossbra'):
        def skin_fit(point):
            _, _, _, distance = neckline_skin.find_nearest(point, .014)
            fade = 1.0 if distance is None else smooth(.002, .014, distance)
            return shoulder_line(point) * fade
        adjust_basis(models[name], skin_fit)
        smooth_bust_skin(models[name])
        shoulder_loops(models[name])
        round_socket(models[name])
        balance_arm_weights(models[name], collection.rig)
        close_skin_join(models[name], head, head_edges)
        pose_shoulder_correctives(models[name], collection.rig)

    for cut, strength, ripple, ease in (
        ('Ribcrop', .72, .0012, .001),
        ('Zipcrop', .58, .0016, .0025),
        ('Tailoredknit', .82, .0010, .001),
        ('Cowldress', .68, 0, 0),
    ):
        for name, ob in tuple(models.items()):
            if name == f'Top_Fashion_{cut}' or name.startswith(f'Topx_Fashion_{cut}_'):
                adjusted = cut not in ('Cowldress', 'Zipcrop') or not name.endswith(('_Skirt', '_Sash', '_Hood'))
                if adjusted:
                    adjust_basis(ob, lambda p: chest_fit(p, strength, ripple, ease))
                    if name.startswith('Top_Fashion_'):
                        balance_arm_weights(ob, collection.rig)
                        follow_correctives(ob, models['Fashion_Torso_Skin'])

    # Smooth bust contours, pull ALL Jules tops into a sleek skin-tight body-hugging fit,
    # and enforce exact skinning weight transfer across shoulder/armpit (ZERO clipping or pokes!).
    torso_skin = models['Fashion_Torso_Skin']
    crop_skin = models['Fashion_Crop_Skin']
    torso_tree = surface_tree(torso_skin.data)
    crop_tree = surface_tree(crop_skin.data)

    for top_name, sk_ob, sk_tree, min_gap, max_gap, hug_k in (
        ('Top_Fashion_Ribcrop', crop_skin, crop_tree, 0.0038, 0.0056, 0.78),
        ('Top_Fashion_Zipcrop', crop_skin, crop_tree, 0.0068, 0.0105, 0.48),
        ('Top_Fashion_Tailoredknit', torso_skin, torso_tree, 0.0036, 0.0054, 0.82),
        ('Top_Fashion_Cowldress', torso_skin, torso_tree, 0.0035, 0.0050, 0.85),
    ):
        top_ob = models.get(top_name)
        if top_ob is None:
            continue
        # 1. Smooth sharp bust protrusions & neckline pinches via Taubin relaxation.
        t_neigh = vertex_neighbours(top_ob.data)
        t_pos = [v.co.copy() for v in top_ob.data.vertices]
        t_inf = {}
        for i, p in enumerate(t_pos):
            if not t_neigh[i]:
                continue
            bust_zone = smooth(1.16, 1.22, p.z) * smooth(1.36, 1.31, p.z) * smooth(0.03, 0.09, p.y)
            if top_name == 'Top_Fashion_Cowldress':
                bust_zone = max(bust_zone, 0.72 * smooth(1.03, 1.12, p.z) * smooth(1.35, 1.29, p.z))
            if bust_zone > 0.02:
                t_inf[i] = min(1.0, bust_zone * 0.85)
        if t_inf:
            t_rel = relax_patch(t_pos, t_neigh, t_inf, (.50, -.22, .48, -.20, .44, -.18))
            for i in t_inf:
                d = t_rel[i] - t_pos[i]
                top_ob.data.vertices[i].co = t_rel[i]
                if top_ob.data.shape_keys:
                    for key in top_ob.data.shape_keys.key_blocks:
                        key.data[i].co += d
            top_ob.data.update()

        # 2. Skin-tight hugging pass: pull loose torso, waist & sleeve fabric closely onto the body
        #    while smoothly feathering over the upper shoulders/neck (NO hard z>1.45 cliff!).
        def hug_skin_tight(p):
            if p.z < 0.88 or p.z > 1.49:
                return Vector()
            top_fade = smooth(1.485, 1.425, p.z)
            hit, nrm, _, dist = sk_tree.find_nearest(p)
            if hit is None or nrm.length < 1e-4 or dist > 0.065:
                return Vector()
            gap = (p - hit).dot(nrm)
            # Armpit, deltoid & forearm clearance guard so arms NEVER poke through knit sleeves in walk/run/sit!
            is_armpit = smooth(0.085, 0.120, abs(p.x)) * smooth(0.220, 0.185, abs(p.x)) * smooth(1.24, 1.31, p.z)
            is_arm = smooth(0.165, 0.215, abs(p.x))
            arm_extra = 0.0046 if top_name in ('Top_Fashion_Ribcrop', 'Top_Fashion_Tailoredknit') else 0.0022
            floor_gap = min_gap + 0.0040 * is_armpit + arm_extra * is_arm
            if gap < floor_gap:
                return nrm * (floor_gap - gap)
            # Pull excess baggy fabric inward smoothly toward the body silhouette!
            ceil_gap = max_gap + 0.0034 * is_armpit + arm_extra * is_arm
            if gap > ceil_gap:
                # Keep subtle cleavage bridge AND underbust couture drape smooth (NEVER collapse into sharp nipple cones!).
                cleavage = bell(p.x, 0.024) * bell(p.z - 1.275, 0.045) * smooth(0.06, 0.12, p.y)
                underbust_guard = (bell(p.z - 1.242, 0.032) * smooth(0.06, 0.12, p.y) * smooth(0.115, 0.045, abs(p.x))
                                   if top_name == 'Top_Fashion_Cowldress' else 0.0)
                pull = min(0.022, (gap - ceil_gap) * hug_k) * (1.0 - 0.65 * cleavage) * (1.0 - 0.88 * underbust_guard) * top_fade
                return -nrm * pull
            return Vector()
        adjust_basis(top_ob, hug_skin_tight)

        # 2b. Dedicated Couture Bodice Smooth on Cowldress AFTER hugging:
        #     Tuck boxy side armpit corners cleanly onto ribcage, eliminate ANY pinched bust creases,
        #     and re-verify clean +4mm clearance over torso skin!
        if top_name == 'Top_Fashion_Cowldress':
            # Tuck outer side corners (|x| > 0.105, z > 1.20) flush onto ribcage so zero boxy wings stick out!
            def tuck_side_wings(p):
                if abs(p.x) < 0.098 or p.z < 1.18:
                    return Vector()
                centre = Vector((0.0, 0.015, p.z))
                radial = p - centre
                r_cur = radial.length
                if r_cur < 0.04:
                    return Vector()
                d = radial / r_cur
                hit = torso_tree.ray_cast(centre + d * 0.30, -d, 0.30)[0]
                if hit is None:
                    return Vector()
                r_body = (hit - centre).dot(d)
                excess = r_cur - (r_body + 0.0042)
                if excess > 0.0:
                    w_side = smooth(0.098, 0.128, abs(p.x)) * smooth(1.18, 1.25, p.z)
                    return -d * (excess * 0.92 * w_side)
                return Vector()
            adjust_basis(top_ob, tuck_side_wings)

            # Smooth the entire front bodice (bust -> underbust -> waist) with 10 clean volume-preserving steps!
            c_neigh = vertex_neighbours(top_ob.data)
            c_pos = [v.co.copy() for v in top_ob.data.vertices]
            c_inf = {
                i: 0.85 * smooth(1.03, 1.10, p.z) * smooth(1.335, 1.290, p.z) * smooth(0.01, 0.07, p.y)
                for i, p in enumerate(c_pos) if c_neigh[i]
            }
            c_inf = {i: w for i, w in c_inf.items() if w > 0.02}
            if c_inf:
                c_rel = relax_patch(c_pos, c_neigh, c_inf, (.52, -.20, .50, -.18, .48, -.16, .46, -.15, .42, .38))
                for i in c_inf:
                    d = c_rel[i] - c_pos[i]
                    top_ob.data.vertices[i].co = c_rel[i]
                    if top_ob.data.shape_keys:
                        for key in top_ob.data.shape_keys.key_blocks:
                            key.data[i].co += d
                top_ob.data.update()

            # Re-verify +4.2mm minimum clearance over torso skin so smoothing never causes skin pokes!
            def verify_cowl_clear(p):
                if p.z < 1.02 or p.y < 0.0:
                    return Vector()
                hit, nrm, _, dist = torso_tree.find_nearest(p)
                if hit is not None and nrm.length > 1e-4 and dist < 0.03:
                    gap = (p - hit).dot(nrm)
                    if gap < 0.0042:
                        return nrm * (0.0042 - gap)
                return Vector()
            adjust_basis(top_ob, verify_cowl_clear)

        elif top_name in ('Top_Fashion_Tailoredknit', 'Top_Fashion_Ribcrop'):
            # 2c. Remove folded-under back-neck rim faces (eliminates grey/black back-collar z-fighting!),
            #     smooth bust apex cleanly, and relax neckline contour!
            clean_folded_back_neck(top_ob)
            k_neigh = vertex_neighbours(top_ob.data)
            k_pos = [v.co.copy() for v in top_ob.data.vertices]
            k_inf = {
                i: 0.96 * smooth(1.17, 1.22, p.z) * smooth(1.37, 1.31, p.z) * smooth(0.025, 0.085, p.y)
                for i, p in enumerate(k_pos) if k_neigh[i]
            }
            k_inf = {i: w for i, w in k_inf.items() if w > 0.02}
            if k_inf:
                k_rel = relax_patch(k_pos, k_neigh, k_inf, (.56,) * 18)
                for i in k_inf:
                    d = k_rel[i] - k_pos[i]
                    top_ob.data.vertices[i].co = k_rel[i]
                    if top_ob.data.shape_keys:
                        for key in top_ob.data.shape_keys.key_blocks:
                            key.data[i].co += d
                top_ob.data.update()
            smooth_neckline_rim(top_ob, sk_tree)
            smooth_sleeve_hems(top_ob, sk_tree)

            def verify_knit_clear(p):
                if p.z < 1.13 or p.z > 1.48:
                    return Vector()
                hit, nrm, _, dist = sk_tree.find_nearest(p)
                if hit is not None and nrm.length > 1e-4 and dist < 0.035:
                    gap = (p - hit).dot(nrm)
                    need = 0.0056 + 0.0060 * smooth(0.145, 0.200, abs(p.x))
                    if gap < need:
                        return nrm * (need - gap)
                return Vector()
            adjust_basis(top_ob, verify_knit_clear)

        # 3. Copy exact shoulder, deltoid & upper-arm skinning weights from the worn torso skin
        #    so fitted sleeves deform 100% identically to the arm skin in idle, walk, run & sit poses!
        if top_name != 'Top_Fashion_Cowldress':
            def armpit_weight_mask(p):
                return (smooth(0.090, 0.130, abs(p.x))
                        * smooth(1.16, 1.24, p.z) * smooth(1.48, 1.41, p.z))
            weights_from(top_ob, sk_ob, armpit_weight_mask)
            if top_ob.data.shape_keys is not None:
                for sk_k in list(top_ob.data.shape_keys.key_blocks):
                    if sk_k.name.startswith(('Bend_Shoulder_', 'Reach_Shoulder_', 'Lift_Shoulder_')):
                        top_ob.shape_key_remove(sk_k)
            follow_correctives(top_ob, sk_ob)

        # 4. Keep buttons, plackets & zippers snapped snugly onto the tightened skin-tight tops!
        top_tree = surface_tree(top_ob.data)
        for tr_name, tr_ob in models.items():
            if tr_name.startswith(f'Topx_Fashion_{top_name.split("_")[-1]}_') and not tr_name.endswith(('_Skirt', '_Sash', '_Hood', '_Bra', '_Straps', '_StrapLeft', '_StrapRight', '_CrossLeft', '_CrossRight')):
                lift = 0.0028 if '_Zip' in tr_name else (0.0018 if tr_name.endswith('_Placket') else 0.0022)
                def snap_top_trim(p):
                    hit, nrm, _, dist = top_tree.find_nearest(p)
                    if hit is None or nrm.length < 1e-4 or dist > 0.045:
                        return Vector()
                    gap = (p - hit).dot(nrm)
                    return nrm * (lift - gap) * 0.94
                adjust_basis(tr_ob, snap_top_trim)

    # Polish unlocked Jules wardrobe silhouettes (dresses, blouses, tanks, jackets) with
    # smooth bust contours, clean skin clearance & matched shoulder weights so every look is AAA!
    for extra_name, min_g in (
        ('Top_Fashion_Blouse', 0.0052),
        ('Top_Fashion_Tank', 0.0042),
        ('Top_Fashion_Squareneck', 0.0042),
        ('Top_Fashion_Vest', 0.0048),
        ('Top_Fashion_Fitteddress', 0.0042),
        ('Top_Fashion_Loosedress', 0.0058),
        ('Top_Fashion_Onedress', 0.0042),
        ('Top_Fashion_Moto', 0.0068),
        ('Top_Fashion_Racer', 0.0065),
        ('Top_Fashion_Jacket', 0.0068),
        ('Top_Fashion_Pullover', 0.0072),
    ):
        ex_ob = models.get(extra_name)
        if ex_ob is None:
            continue
        # Soften any sharp bust apex on fitted tops/dresses.
        e_neigh = vertex_neighbours(ex_ob.data)
        e_pos = [v.co.copy() for v in ex_ob.data.vertices]
        e_inf = {
            i: 0.85 * smooth(1.18, 1.23, p.z) * smooth(1.36, 1.30, p.z) * smooth(0.03, 0.085, p.y)
            for i, p in enumerate(e_pos) if e_neigh[i]
        }
        e_inf = {i: w for i, w in e_inf.items() if w > 0.02}
        if e_inf:
            e_rel = relax_patch(e_pos, e_neigh, e_inf, (.48,) * 10)
            for i in e_inf:
                d = e_rel[i] - e_pos[i]
                ex_ob.data.vertices[i].co = e_rel[i]
                if ex_ob.data.shape_keys:
                    for key in ex_ob.data.shape_keys.key_blocks:
                        key.data[i].co += d
            ex_ob.data.update()
        def clear_extra_skin(p, mg=min_g):
            if p.z < 1.04 or p.z > 1.48:
                return Vector()
            hit, nrm, _, dist = torso_tree.find_nearest(p)
            if hit is not None and nrm.length > 1e-4 and dist < 0.035:
                gap = (p - hit).dot(nrm)
                need = mg + 0.0045 * smooth(0.145, 0.205, abs(p.x))
                if gap < need:
                    return nrm * (need - gap)
            return Vector()
        adjust_basis(ex_ob, clear_extra_skin)
        balance_arm_weights(ex_ob, collection.rig)
        follow_correctives(ex_ob, torso_skin)

    # Also smooth bust apex on Top_Fashion_Crossbra so the sports bra has a clean supportive athletic profile!
    crossbra = models.get('Top_Fashion_Crossbra')
    bra_skin = models.get('JulesSkin_Crossbra')
    if crossbra is not None and bra_skin is not None:
        cb_neigh = vertex_neighbours(crossbra.data)
        cb_pos = [v.co.copy() for v in crossbra.data.vertices]
        cb_inf = {
            i: 0.88 * smooth(1.20, 1.24, p.z) * smooth(1.35, 1.30, p.z) * smooth(0.04, 0.10, p.y)
            for i, p in enumerate(cb_pos) if cb_neigh[i]
        }
        cb_inf = {i: w for i, w in cb_inf.items() if w > 0.02}
        if cb_inf:
            cb_rel = relax_patch(cb_pos, cb_neigh, cb_inf, (.50, .46, .42, .38, .35))
            for i in cb_inf:
                d = cb_rel[i] - cb_pos[i]
                crossbra.data.vertices[i].co = cb_rel[i]
                if crossbra.data.shape_keys:
                    for key in crossbra.data.shape_keys.key_blocks:
                        key.data[i].co += d
            crossbra.data.update()
        bs_tree = surface_tree(bra_skin.data)
        def clear_bra_skin(p):
            hit, nrm, _, dist = bs_tree.find_nearest(p)
            if hit is not None and nrm.length > 1e-4 and dist < 0.025:
                gap = (p - hit).dot(nrm)
                if gap < 0.0038:
                    return nrm * (0.0038 - gap)
            return Vector()
        adjust_basis(crossbra, clear_bra_skin)

    # Keep Streetwear inner bra cleanly tucked inside Zipcrop sides so bra NEVER pokes through outer jacket!
    zipcrop = models.get('Top_Fashion_Zipcrop')
    zip_bra = models.get('Topx_Fashion_Zipcrop_Bra')
    if zipcrop is not None and zip_bra is not None:
        zip_tree = surface_tree(zipcrop.data)
        def tuck_zip_bra(p):
            # Preserve visible center bandeau between the open zippers (|x| < 0.055, front).
            if abs(p.x) < 0.055 and p.y > 0.04:
                return Vector()
            centre = Vector((0.0, 0.015, p.z))
            radial = p - centre
            r_in = radial.length
            if r_in < 0.03:
                return Vector()
            d = radial / r_in
            hit = zip_tree.ray_cast(centre + d * 0.35, -d, 0.35)[0]
            if hit is None:
                return Vector()
            max_r = (hit - centre).dot(d) - 0.007
            if r_in > max_r:
                return -d * ((r_in - max_r) * smooth(0.050, 0.078, abs(p.x)))
            return Vector()
        adjust_basis(zip_bra, tuck_zip_bra)

    # Re-drape Cowldress silk straps cleanly into the newly tightened sweetheart neckline!
    replace_cowldress_straps(collection, models['Top_Fashion_Cowldress'], models['Fashion_Torso_Skin'])

    bra = models['Top_Fashion_Crossbra']
    skin = models['JulesSkin_Crossbra']
    body = surface_tree(skin.data)

    def support(p):
        delta = chest_fit(p, 1.05, .0004, 0)
        direction = Vector((p.x, p.y-.018, 0)).normalized()
        origin = Vector((0, .018, p.z))
        side = smooth(.092, .134, abs(p.x)) * smooth(.105, .052, p.y)
        if side > .001:
            hit, _, _, _ = body.ray_cast(origin, direction, .23)
            if hit is not None:
                gap = max(0, (p-hit).dot(direction) - .0042)
                delta -= direction * min(.040, gap) * side
        if p.y > .065 and abs(p.x) < .145:
            hit = body.ray_cast(Vector((p.x, .35, p.z)), Vector((0, -1, 0)))[0]
            if hit is not None:
                original_gap = p.y - hit.y
                clearance = min(.0042, max(.0028, original_gap))
                delta.y = max(delta.y, hit.y + clearance - p.y)
        return delta

    adjust_basis(bra, support)
    # Smooth any tiny surface puckers on the bra cups so the knit reads clean & taut.
    b_neigh = vertex_neighbours(bra.data)
    b_pos = [v.co.copy() for v in bra.data.vertices]
    b_inf = {i: 0.72 * smooth(1.225, 1.255, p.z) * smooth(1.340, 1.310, p.z)
             for i, p in enumerate(b_pos) if b_neigh[i] and p.y > 0.04}
    b_rel = relax_patch(b_pos, b_neigh, b_inf, (.48, -.24, .44, -.20))
    for i, w in b_inf.items():
        if w > 0.01:
            d = b_rel[i] - b_pos[i]
            bra.data.vertices[i].co = b_rel[i]
            if bra.data.shape_keys:
                for key in bra.data.shape_keys.key_blocks:
                    key.data[i].co += d
    bra.data.update()

    # Re-enforce strict +4.5mm front cup clearance after smoothing so skin NEVER dimples through bra!
    def clear_bra_front(p):
        if p.y > 0.045 and abs(p.x) < 0.145 and 1.21 < p.z < 1.36:
            hit, nrm, _, _ = body.find_nearest(p)
            if hit is not None and nrm.y > 0.15:
                gap = (p - hit).dot(nrm)
                if gap < 0.0046:
                    return nrm * (0.0046 - gap)
        return Vector()
    adjust_basis(bra, clear_bra_front)

    for vertex in bra.data.vertices:
        p = vertex.co
        influence = smooth(.082, .125, abs(p.x)) * smooth(1.226, 1.27, p.z)
        if influence > .005:
            chest = smooth(1.210, 1.319, p.z)
            blend_weights(bra, vertex, {'chest': chest, 'spine': 1-chest}, influence)

    def neckline(p):
        x = abs(p.x)
        # Clean athletic scoop neckline with full supportive side wings (NO side-boob gap!).
        cup = bell(x - .072, .046)
        scoop = 1.324 + .022 * cup - .024 * smooth(.095, .148, x)
        back = 1.292 + .004 * smooth(.060, .135, x)
        limit = back + (scoop - back) * smooth(.032, .105, p.y)
        return limit - p.z

    collection.cut(bra, neckline, .0022)

    def bind_armhole(p):
        side = smooth(.090, .132, abs(p.x)) * smooth(.105, .052, p.y)
        upper = smooth(1.230, 1.280, p.z)
        if side * upper < .001:
            return Vector()
        direction = Vector((p.x, p.y-.018, 0)).normalized()
        hit, _, _, _ = body.ray_cast(Vector((0, .018, p.z)), direction, .23)
        gap = max(0, (p-hit).dot(direction) - .0050) if hit is not None else 0
        return -direction * min(.018, gap) * side * upper

    adjust_basis(bra, bind_armhole)
    replace_straps(collection, bra, skin)
    bra_band(collection, bra)
