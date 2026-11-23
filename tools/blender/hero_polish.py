"""Second realism polish for the two fixed WorldState heroes.

Runs from hero_realism.finish_realism on the finished authoring meshes:
  * Jules: coiled, twisted-rope bun replaces the stacked ring bun; a smoothed
    side hairline (no step above the ear); fuller anatomical lips; a gentle
    symmetry and softness pass that keeps her identity.
  * Ade: flyaway cards that stood off the crop are laid back onto it.
Every face edit is applied as one delta to the basis and all shape keys, so
blink and expression keys keep working.
"""
import math

import bmesh
from mathutils import Vector
from mathutils.kdtree import KDTree

from hero_finish import material_vertices
from wardrobe_quality import smooth


def _bell(value, width):
    return math.exp(-(value / width) ** 2)


def _apply_delta(face, delta):
    keys = face.data.shape_keys.key_blocks if face.data.shape_keys else []
    for key in keys:
        for index, d in delta.items():
            key.data[index].co += d
    for index, d in delta.items():
        if keys:
            face.data.vertices[index].co = keys[0].data[index].co
        else:
            face.data.vertices[index].co += d
    face.data.update()


def _basis(face):
    keys = face.data.shape_keys
    return keys.key_blocks[0].data if keys else face.data.vertices


def shape_lips(face, eyes):
    """Fuller vermilion with a defined Cupid's bow; the lip seam stays put."""
    eye = (eyes[0] + eyes[1]) * .5
    basis = _basis(face)
    delta = {}
    for index in material_vertices(face, ('hero_skin_face_',)):
        p = basis[index].co
        dz = p.z - eye.z
        if not -.090 < dz < -.045 or abs(p.x) > .032:
            continue
        front = smooth(eye.y + .012, eye.y + .024, p.y)
        if front <= 0:
            continue
        across = math.exp(-(p.x / .0185) ** 4)
        lower = _bell(dz + .0715, .0058)
        upper = _bell(dz + .0595, .0047)
        bow = _bell(abs(p.x) - .0066, .0042) - .55 * _bell(p.x, .0030)
        border = _bell(dz + .0545, .0035)
        d = Vector((0,
                    (.0023 * lower + .0015 * upper) * across,
                    (-.0011 * _bell(dz + .0765, .0040) + .0007 * border * (1 + bow)) * across))
        # Corners tuck in slightly so the mouth doesn't look stretched.
        d.y -= .0006 * _bell(abs(p.x) - .023, .004) * _bell(dz + .065, .006)
        delta[index] = d * front
    _apply_delta(face, delta)


def balance_face(face, eyes, amount=.55, soften=.22):
    """Pull the two halves together (not mirror-perfect) and relax harsh
    planes away from the eyes and lips."""
    eye = (eyes[0] + eyes[1]) * .5
    basis = _basis(face)
    skin = material_vertices(face, ('hero_skin_face_',))
    points = {i: basis[i].co.copy() for i in skin}
    kd = KDTree(len(points))
    for i, co in points.items():
        kd.insert(co, i)
    kd.balance()
    delta = {}
    for i, p in points.items():
        if abs(p.x) < .002:
            continue
        mirror, j, dist = kd.find(Vector((-p.x, p.y, p.z)))
        if dist > .0025:
            continue
        target = Vector((-mirror.x, mirror.y, mirror.z))
        front = smooth(eye.y - .07, eye.y - .02, p.y)
        delta[i] = (target - p) * .5 * amount * front

    # Soften: one Laplacian step on the skin, masked off the eyes and mouth.
    bm = bmesh.new()
    bm.from_mesh(face.data)
    bm.verts.ensure_lookup_table()
    for i, p in points.items():
        v = bm.verts[i]
        ring = [e.other_vert(v).index for e in v.link_edges if e.other_vert(v).index in points]
        if len(ring) < 3 or v.is_boundary:
            continue
        near_eye = min((p - e).length for e in eyes)
        mouth = _bell(p.z - eye.z + .066, .016) * _bell(p.x, .028)
        mask = smooth(.016, .030, near_eye) * (1 - mouth) * smooth(eye.y - .06, eye.y - .01, p.y)
        avg = sum((points[r] for r in ring), Vector()) / len(ring)
        delta[i] = delta.get(i, Vector()) + (avg - p) * soften * mask
    bm.free()
    _apply_delta(face, delta)


def smooth_side_hairline(shell, skin, eye, iterations=36):
    """Relax the scalp outline so it turns smoothly over the ear (the old
    outline stepped down in a square notch); the rows behind follow."""
    data = shell.data
    count = {}
    for poly in data.polygons:
        if poly.material_index == 0:
            for edge in poly.edge_keys:
                count[edge] = count.get(edge, 0) + 1
    neighbours = {}
    for (a, b), n in count.items():
        if n == 1:
            neighbours.setdefault(a, []).append(b)
            neighbours.setdefault(b, []).append(a)
    rim = [i for i, ring in neighbours.items()
           if len(ring) == 2 and data.vertices[i].co.z > eye.z - .045 and abs(data.vertices[i].co.x) > .030]
    if not rim:
        return
    start = {i: data.vertices[i].co.copy() for i in rim}
    pos = dict(start)
    for _ in range(iterations):
        nxt = {}
        for i in rim:
            a, b = neighbours[i]
            pa = pos.get(a, data.vertices[a].co)
            pb = pos.get(b, data.vertices[b].co)
            nxt[i] = pos[i] + ((pa + pb) * .5 - pos[i]) * .5
        pos = nxt
    moved = {}
    for i in rim:
        hit = skin.find_nearest(pos[i])[0]
        target = pos[i] if hit is None else hit + (start[i] - (skin.find_nearest(start[i])[0] or start[i]))
        moved[i] = target - start[i]
    for i, d in moved.items():
        data.vertices[i].co += d
    # Carry the move two rows inward so no sliver faces fold over.
    adjacency = {}
    for e in data.edges:
        a, b = e.vertices
        adjacency.setdefault(a, set()).add(b)
        adjacency.setdefault(b, set()).add(a)
    frontier = moved
    for weight in (.6, .3):
        nxt = {}
        for i, d in frontier.items():
            for j in adjacency.get(i, ()):
                if j not in moved and j not in nxt:
                    nxt[j] = d * weight
        for j, d in nxt.items():
            data.vertices[j].co += d
        moved = {**moved, **nxt}
        frontier = nxt
    data.update()


def rebuild_bun(shell, groom, lengths_material='hero_hair_lengths'):
    """Replace the stacked ring tubes with one coiled, twisted rope of hair."""
    data = shell.data
    slot = next((i for i, m in enumerate(data.materials) if m.name.startswith(lengths_material)), None)
    if slot is None:
        return
    bm = bmesh.new()
    bm.from_mesh(data)
    old_faces = [f for f in bm.faces if f.material_index == slot]
    if not old_faces:
        bm.free()
        return
    old_verts = {v for f in old_faces for v in f.verts}
    centre = sum((v.co for v in old_verts), Vector()) / len(old_verts)
    bottom = min(v.co.z for v in old_verts)
    deform = bm.verts.layers.deform.verify()
    weights = dict(next(iter(old_verts))[deform])
    uv_layer = bm.loops.layers.uv.get('SurfaceUV') or bm.loops.layers.uv.active
    freedom = bm.loops.layers.uv.get('ClothFreedom')
    freedom_value = old_faces[0].loops[0][freedom].uv.copy() if freedom else None
    bmesh.ops.delete(bm, geom=list(old_verts), context='VERTS')

    base = Vector((centre.x, centre.y - .004, bottom + .027))
    turns, samples, sides = 2.6, 170, 12
    rings = []
    for k in range(samples + 1):
        s = k / samples
        theta = 1.9 + math.tau * turns * s
        radius = (.0365 - .0270 * s ** .8) * (1 + .07 * math.cos(2 * theta + .4))
        height = -.017 + .047 * s ** .8
        tube = .0205 * (1 - .42 * s) * smooth(0, .05, s) ** .5 * (1 - smooth(.90, 1, s) * .8) + .0012
        outward = Vector((math.cos(theta), math.sin(theta), 0))
        tangent = Vector((-math.sin(theta), math.cos(theta), 0))
        ring = []
        for j in range(sides):
            a = math.tau * j / sides
            twist = 3 * a - 7.5 * math.tau * s
            groove = 1 + .075 * math.cos(twist) + .03 * math.cos(2 * twist + 1.3)
            offset = outward * math.cos(a) * tube * groove + Vector((0, 0, .92 * math.sin(a) * tube * groove))
            p = base + outward * radius + Vector((0, 0, height)) + offset
            # Lean the knot back with the head's crown; a slight flattening
            # where the bottom coil presses on the scalp.
            rel = p - base
            p = base + Vector((rel.x, rel.y - .30 * rel.z, rel.z * (1 - .10 * smooth(0, -.03, rel.z))))
            ring.append(bm.verts.new(p))
        rings.append(ring)
    for v in (v for ring in rings for v in ring):
        for group, w in weights.items():
            v[deform][group] = w
    length = 0.0
    arc = [0.0]
    for k in range(1, len(rings)):
        length += (rings[k][0].co - rings[k - 1][0].co).length
        arc.append(length)
    new_faces = []
    for k in range(samples):
        for j in range(sides):
            quad = (rings[k][j], rings[k][(j + 1) % sides], rings[k + 1][(j + 1) % sides], rings[k + 1][j])
            f = bm.faces.new(quad)
            f.material_index = slot
            f.smooth = True
            for loop, (kk, jj) in zip(f.loops, ((k, j), (k, j + 1), (k + 1, j + 1), (k + 1, j))):
                s = kk / samples
                if uv_layer:
                    loop[uv_layer].uv = (jj / sides + 7.5 * s, arc[kk] / .25)
                if freedom:
                    loop[freedom].uv = freedom_value
            new_faces.append(f)
    for ends in (rings[0], rings[-1]):
        f = bm.faces.new(ends)
        f.material_index = slot
        new_faces.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=new_faces)
    bm.to_mesh(data)
    bm.free()
    data.update()

    # Wafts drafted for the ring bun float off the new knot: drop them.
    if groom is not None:
        gb = bmesh.new()
        gb.from_mesh(groom.data)
        remaining = set(gb.verts)
        doomed = []
        while remaining:
            island = [remaining.pop()]
            for v in island:
                for e in v.link_edges:
                    o = e.other_vert(v)
                    if o in remaining:
                        remaining.remove(o)
                        island.append(o)
            mid = sum((v.co for v in island), Vector()) / len(island)
            if (mid - base).length < .052 and mid.z > bottom + .004:
                doomed.extend(island)
        if doomed:
            bmesh.ops.delete(gb, geom=doomed, context='VERTS')
        gb.to_mesh(groom.data)
        gb.free()
        groom.data.update()


def tidy_flyaways(shell, groom, eye, limit=.0032):
    """Lay crop cards that stand off the cap back onto it (ragged top edge)."""
    from mathutils.bvhtree import BVHTree
    cap = BVHTree.FromPolygons([v.co for v in shell.data.vertices],
                               [tuple(p.vertices) for p in shell.data.polygons if p.material_index == 0])
    for v in groom.data.vertices:
        p = v.co
        if p.z < eye.z + .035:
            continue
        hit, normal, _, _ = cap.find_nearest(p)
        if hit is None:
            continue
        off = p - hit
        height = off.dot(normal)
        if height > limit:
            v.co = p - normal * (height - limit) * .85
    groom.data.update()
