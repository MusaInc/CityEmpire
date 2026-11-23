"""Jules facial anatomy, corrected against the reference portrait's
proportions (scaled by the 5.28 cm eye spacing: 5930 px/m).

Measured problems on the old mesh, and what this does about them:
  * Eye openings 13 mm tall with sclera showing above and below the iris
    (the "surprised" look). The photo: ~9 mm almond openings, the upper lid
    covering the top of the iris. -> re-cut both lid margins to an almond
    curve and slide the lids over the eyeball (radial distance kept), with
    the blink still closing.
  * Upper lip 15 mm proud of the philtrum, mouth 5.5 mm too low (long upper
    lip). -> raise the mouth along a vertical remap of the lower face and
    pull both lips back toward the philtrum/chin plane.
  * Flat bridge: no nasion. -> set the nasion back, keep the glabella,
    narrow and soften the bridge and the bulb of the tip.
Each edit is one delta applied to the basis and the expression keys (the
Blink key keeps its closed upper lid).
"""
import math

from mathutils import Vector

from hero_finish import material_vertices
from wardrobe_quality import smooth


def _bell(v, w):
    return math.exp(-(v / w) ** 2)


def _apply(face, delta, blink_delta=None):
    keys = face.data.shape_keys.key_blocks
    for key in keys:
        source = blink_delta if (key.name == 'Blink' and blink_delta is not None) else delta
        for i, d in source.items():
            key.data[i].co += d
    for i in set(delta) | set(blink_delta or {}):
        face.data.vertices[i].co = keys[0].data[i].co
    face.data.update()


def _eyeballs(face):
    basis = face.data.shape_keys.key_blocks[0].data
    eye = [basis[i].co.copy() for i in material_vertices(face, ('hero_eye',))]
    balls = []
    for sign in (-1, 1):
        side = [p for p in eye if sign * p.x > 0]
        c = sum(side, Vector()) / len(side)
        r = sum((p - c).length for p in side) / len(side)
        balls.append((c, r, sign))
    return balls


def _margin_table(points, c, sign):
    """Current upper/lower lid margins (dz) per medial-lateral position."""
    table = {}
    for p in points:
        dm = round((p.x - c.x) * sign * 1000)   # mm, + = lateral
        lo, hi = table.get(dm, (0.0, 0.0))
        table[dm] = (min(lo, p.z - c.z), max(hi, p.z - c.z))
    keys = sorted(table)

    def at(dm):
        mm = dm * 1000
        if mm <= keys[0]:
            return table[keys[0]]
        if mm >= keys[-1]:
            return table[keys[-1]]
        a = max(k for k in keys if k <= mm)
        b = min(k for k in keys if k >= mm)
        t = 0 if a == b else (mm - a) / (b - a)
        return tuple(table[a][j] * (1 - t) + table[b][j] * t for j in (0, 1))
    return at, keys[0] / 1000, keys[-1] / 1000


def almond_eyes(face):
    basis = face.data.shape_keys.key_blocks[0].data
    rim = material_vertices(face, ('hero_lid_rim',))
    skin = material_vertices(face, ('hero_skin_face_',))
    delta, blink = {}, {}
    corners = []
    for c, r, sign in _eyeballs(face):
        pts = [basis[i].co for i in rim if sign * basis[i].co.x > 0]
        margin, inner, outer = _margin_table(pts, c, sign)
        half = (outer - inner) / 2
        mid = (outer + inner) / 2

        def target(dm):
            t = max(0.0, 1 - ((dm - mid) / half) ** 2)
            corner = .0005 + (.0016 - .0005) * smooth(inner, outer, dm)
            upper = corner + .0053 * max(0.0, 1 - ((dm - mid + .0025) / half) ** 2) ** .62
            lower = corner - .0057 * max(0.0, 1 - ((dm - mid - .003) / half) ** 2) ** .85
            return lower, upper, t

        for i in set(rim) | set(skin):
            p = basis[i].co
            off = p - c
            if off.length > r + .0105 or off.y < 0:
                continue
            dm = off.x * sign
            if not inner - .004 < dm < outer + .004:
                continue
            lo0, hi0 = margin(dm)
            lo1, hi1, t = target(dm)
            # Keep the inner canthus as modelled (re-cutting it opened the
            # corner pocket): blend into the new margins across the inner third.
            keep = smooth(inner + .0015, inner + .0095, dm)
            lo1 = lo0 + (lo1 - lo0) * keep
            hi1 = hi0 + (hi1 - hi0) * smooth(inner + .001, inner + .007, dm)
            dz = off.z
            fade = smooth(outer + .001, outer - .0035, dm) * smooth(inner - .001, inner + .0035, dm)
            if dz >= 0 and hi0 > .0004:
                if dz <= hi0:
                    new = dz * hi1 / hi0
                else:
                    new = dz + (hi1 - hi0) * math.exp(-((dz - hi0) / .0065) ** 2)
                upper = True
            elif dz < 0 and lo0 < -.0004:
                if dz >= lo0:
                    new = dz * lo1 / lo0
                else:
                    new = dz + (lo1 - lo0) * math.exp(-((dz - lo0) / .0055) ** 2)
                upper = False
            else:
                continue
            q = Vector((p.x, p.y, c.z + dz + (new - dz) * fade))
            # Slide over the eyeball: keep the original distance from its centre.
            d0 = off.length
            if d0 < r + .0075:
                q = c + (q - c).normalized() * d0
            d = q - p
            if d.length_squared < 1e-14:
                continue
            delta[i] = d
            if not upper:
                blink[i] = d
        corners.append(c + Vector((sign * inner, 0, .0005)))
    _apply(face, delta, blink)


def relax_corners(face, corners, radius=.0045, iterations=14):
    """Settle the inner canthus, where the re-cut lids meet the fixed corner."""
    import bmesh
    keys = face.data.shape_keys.key_blocks
    basis = keys[0].data
    eye = set(material_vertices(face, ('hero_eye',)))
    bm = bmesh.new()
    bm.from_mesh(face.data)
    bm.verts.ensure_lookup_table()
    pts = {}
    for v in bm.verts:
        if v.index in eye:
            continue
        p = basis[v.index].co
        for c in corners:
            # The corner sits on the eyeball's front: compare in x/z only.
            q = Vector((p.x - c.x, 0, p.z - c.z))
            if q.length < radius and p.y > c.y - .004:
                pts[v.index] = 1 - q.length / radius
    ring = {i: [e.other_vert(bm.verts[i]).index for e in bm.verts[i].link_edges
                if e.other_vert(bm.verts[i]).index not in eye] for i in pts}
    bm.free()
    cur = {i: basis[i].co.copy() for i in set(pts) | {j for r in ring.values() for j in r}}
    start = {i: cur[i].copy() for i in pts}
    for step in range(iterations):
        k = .5 if step % 2 == 0 else -.52
        nxt = dict(cur)
        for i, w in pts.items():
            if len(ring[i]) < 2:
                continue
            avg = sum((cur[j] for j in ring[i]), Vector()) / len(ring[i])
            nxt[i] = cur[i] + (avg - cur[i]) * k * w
        cur = nxt
    delta = {i: cur[i] - start[i] for i in pts if (cur[i] - start[i]).length_squared > 1e-14}
    _apply(face, delta)


def lower_face(face, eye):
    """Raise the mouth (shorter upper lip) and set the lips back."""
    basis = face.data.shape_keys.key_blocks[0].data
    skin = material_vertices(face, ('hero_skin_face_',))
    knots = [(-.043, -.043), (-.065, -.0595), (-.099, -.0965), (-.118, -.118)]

    def remap(dz):
        if dz >= knots[0][0] or dz <= knots[-1][0]:
            return dz
        for (a, a2), (b, b2) in zip(knots, knots[1:]):
            if b <= dz <= a:
                t = (dz - a) / (b - a)
                t = t * t * (3 - 2 * t) * .35 + t * .65
                return a2 + (b2 - a2) * t
        return dz

    delta = {}
    for i in skin:
        p = basis[i].co
        dz = p.z - eye.z
        front = smooth(eye.y - .055, eye.y - .015, p.y)
        side = smooth(.070, .036, abs(p.x))
        # The nose's underside (nostril floor, columella, alar base) shares
        # this height band but stands well forward: it must not ride up.
        nose_base = smooth(eye.y + .026, eye.y + .032, p.y) * smooth(-.052, -.046, dz)
        nose_base = max(nose_base, smooth(.022, .010, abs(p.x)) * smooth(-.049, -.044, dz)
                        * smooth(eye.y + .018, eye.y + .026, p.y))
        d = Vector((0, 0, (remap(dz) - dz) * front * side * (1 - nose_base)))
        nz = dz + d.z
        # Lips: pull the vermilion back toward the philtrum / chin plane.
        lips = smooth(.030, .019, abs(p.x)) * smooth(-.077, -.071, nz) * smooth(-.047, -.053, nz)
        excess = max(0.0, (p.y - eye.y) - .0235)
        d.y -= .52 * excess * lips
        if d.length_squared > 1e-14:
            delta[i] = d
    _apply(face, delta)


def nose(face, eye):
    basis = face.data.shape_keys.key_blocks[0].data
    skin = material_vertices(face, ('hero_skin_face_',))
    delta = {}
    for i in skin:
        p = basis[i].co
        dz, ax = p.z - eye.z, abs(p.x)
        front = smooth(eye.y + .010, eye.y + .020, p.y)
        d = Vector()
        # Nasion set back between the eyes; glabella above keeps its projection.
        d.y -= .0034 * _bell(p.x, .011) * _bell(dz - .010, .009) * front
        # Narrow, slightly slimmer bridge.
        bridge = _bell(dz + .010, .014) * smooth(.016, .004, ax) * front
        d.x -= p.x * .14 * bridge
        # Soften the bulb of the tip and the alar flare.
        tip = _bell(p.x, .010) * _bell(dz + .031, .0065) * smooth(eye.y + .040, eye.y + .048, p.y)
        d.y -= .0016 * tip
        ala = _bell(ax - .0115, .0045) * _bell(dz + .035, .006)
        d.x -= p.x * .06 * ala
        if d.length_squared > 1e-14:
            delta[i] = d
    _apply(face, delta)


def narrow_face(face, eye):
    """Narrow the cheeks and jaw beyond the outer eye corners (the reference
    face is far narrower there); ears, scalp and neck seam stay put."""
    import bmesh
    basis = face.data.shape_keys.key_blocks[0].data
    skin = material_vertices(face, ('hero_skin_face_',))
    bm = bmesh.new()
    bm.from_mesh(face.data)
    bm.verts.ensure_lookup_table()
    seam = {v.index for v in bm.verts if v.is_boundary}
    bm.free()
    delta = {}
    for i in skin:
        if i in seam:
            continue
        p = basis[i].co
        ax, dz = abs(p.x), p.z - eye.z
        beyond = max(0.0, ax - .040)
        w = (smooth(eye.y - .060, eye.y - .030, p.y) * smooth(.080, .066, ax)
             * smooth(.012, -.004, dz) * smooth(-.130, -.112, dz))
        dx = -math.copysign(min(beyond, .028) * .19 * w, p.x)
        if abs(dx) > 1e-7:
            delta[i] = Vector((dx, 0, 0))
    _apply(face, delta)


def correct_anatomy(face, eyes):
    eye = (eyes[0] + eyes[1]) * .5
    almond_eyes(face)
    nose(face, eye)
    lower_face(face, eye)
    narrow_face(face, eye)
