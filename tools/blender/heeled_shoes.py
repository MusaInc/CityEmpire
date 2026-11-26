"""Real heels for Jules (2026-11-26).

The pumps were a clone of a flat leather shoe with a 2.4 cm lift and the
"Evening Heels" a clone of the flat sandals – neither had a heel. In the game
a heeled foot now stands pitched onto the ball (CharacterRig.HEELS: the foot
bone turns toes-down by `pitch` and the ankle and pelvis ride higher by
BALL·sin(pitch)), so everything here is modelled in the foot's REST frame for
that pitch:

  * the forefoot of the shoe (and of every bare foot, as a "Heel" shape key)
    is bent up about the ball by `pitch`, so it lies flat on the ground once
    the foot is pitched;
  * the heel post leaves the heel seat along the world vertical – in the rest
    frame (0, sin p, -cos p) – and ends exactly on the ground plane (the plane
    through the ball, normal (0, -sin p, cos p)), with a rubber top-lift;
  * the pump is rebuilt as a fitted court shoe: low-cut leather upper with a
    turned top line, thin leather sole, pointed almond toe.

Frame: Blender rest pose, x across, y forward (toes), z up, ground z = 0.
"""
import math

import bmesh
import bpy
from mathutils import Vector

from build_b_footwear import insert_parts, quad_grid, shader_material
from garment_kit import weights_from
from wardrobe_quality import smooth, surface_tree

# Must match CharacterRig.HEELS / BALL.
PITCH = {'Footwear_pumps': 0.30, 'Footwear_eveningstraps': 0.40}
BALL = 0.13
BEND = 0.016          # half-width of the bend round the ball (m)
STRAP_PITCH = 0.40    # bare-foot "Heel" shape key (value 1 = this pitch)


def ball_y(joints, side):
    return joints['foot_' + side].y + BALL


def bend(p, yb, pitch):
    """Rotate the forefoot up about the ball line (y = yb, z = 0)."""
    a = pitch * smooth(yb - BEND, yb + BEND, p.y)
    if a <= 0.0:
        return p.copy()
    dy, z = p.y - yb, p.z
    c, s = math.cos(a), math.sin(a)
    return Vector((p.x, yb + dy * c - z * s, dy * s + z * c))


def side_of(p):
    return 'r' if p.x > 0 else 'l'


def heel_post(joints, side, pitch, seat_y, seat_z, shoe, cap, stiletto=True):
    """A tapered heel from the seat to the ground, plus its top-lift."""
    ankle = joints['foot_' + side]
    yb = ball_y(joints, side)
    d = Vector((0.0, math.sin(pitch), -math.cos(pitch)))
    n = Vector((0.0, -math.sin(pitch), math.cos(pitch)))
    top = Vector((ankle.x, seat_y, seat_z))
    length = (top - Vector((ankle.x, yb, 0.0))).dot(n)
    ring = 20
    rows = []
    # (t along the post, half-width across, half-depth along the foot)
    prof = ((0.0, .019, .024), (.12, .015, .018), (.45, .0085, .0095), (.82, .0055, .0060),
            (1.0, .0048, .0052)) if stiletto else \
           ((0.0, .019, .024), (.25, .016, .019), (1.0, .0135, .0150))
    lift = .004
    for t, w, dd in prof:
        c = top + d * (length - lift) * t
        rows.append([c + Vector((w * math.sin(a), dd * math.cos(a) * math.cos(pitch), dd * math.cos(a) * math.sin(pitch)))
                     for a in (i * math.tau / ring for i in range(ring))])
    pts, faces = quad_grid(rows, closed=True)
    parts = [(pts, faces, shoe)]
    # Top-lift: a short rubber cap that meets the ground.
    w, dd = prof[-1][1], prof[-1][2]
    c0 = top + d * (length - lift)
    caps = [[c + Vector((w * math.sin(a), dd * math.cos(a) * math.cos(pitch), dd * math.cos(a) * math.sin(pitch)))
             for a in (i * math.tau / ring for i in range(ring))] for c in (c0, c0 + d * lift)]
    pts2, faces2 = quad_grid(caps, closed=True)
    faces2 += [tuple(range(ring - 1, -1, -1)), tuple(range(ring, 2 * ring))]
    parts.append((pts2, faces2, cap))
    return parts


def court_shoe(obj, joints, legs, pitch):
    """A fitted court shoe (pump) for the pitched foot, rebuilt in place."""
    upper = obj.data.materials[0]
    sole = next((m for m in obj.data.materials if m and 'sole' in m.name), obj.data.materials[-1])
    edge = shader_material('hero_footwear_leather_edge', (.094, .075, .062), .64)
    lining = shader_material('hero_footwear_lining', (.16, .12, .10), .82)
    tree = surface_tree(legs.data)
    angles = [i * math.tau / 48 for i in range(48)]
    parts = []

    def add(rows, material, caps=False, bent=True, side='l'):
        if bent:
            yb = ball_y(joints, side)
            rows = [[bend(p, yb, pitch) for p in row] for row in rows]
        pts, faces = quad_grid(rows, closed=True)
        if caps:
            k = len(rows[0])
            faces += [tuple(range(k - 1, -1, -1)), tuple(range(len(pts) - k, len(pts)))]
        parts.append((pts, faces, material))

    for side, sign in (('l', -1), ('r', 1)):
        ankle, knee = joints['foot_' + side], joints['shin_' + side]

        def axis(z):
            return ankle.lerp(knee, (z - ankle.z) / (knee.z - ankle.z))

        def clear(row, gap):
            for p in row:
                if p.z < .02:
                    continue
                c = axis(p.z)
                c.y = p.y if p.y > ankle.y + .02 else c.y
                dr = Vector((p.x - c.x, p.y - c.y, 0.0))
                if dr.length < 1e-5:
                    continue
                dr.normalize()
                hit = tree.ray_cast(c + dr * .09, -dr, .09)[0]
                if hit is not None:
                    p += dr * max(0.0, (hit - p).dot(dr) + gap)
            return row

        def last(z, width, front, back, point=1.0):
            row = []
            for a in angles:
                fwd = math.cos(a)
                t = (1 + fwd) * .5
                spread = .76 + .25 * smooth(.11, .58, t) + .12 * smooth(.54, .80, t)
                # an almond toe: the last narrows in its front 4 cm
                spread *= 1.0 - .30 * point * smooth(.78, 1.0, t)
                y = back + (front - back) * t
                x = ankle.x - sign * .011 * smooth(.03, .17, y) - width * spread * math.sin(a)
                row.append(Vector((x, y, z)))
            return row

        # Thin leather sole (5 mm) with a bevelled edge.
        add([last(z, w, f, b) for z, w, f, b in (
            (.000, .038, .197, -.040), (.002, .041, .201, -.042),
            (.005, .041, .201, -.042), (.006, .039, .199, -.041))], sole, caps=True, side=side)
        # Upper: closed toe box, low-cut sides, the heel counter up the back;
        # the top line dips over the instep (a court shoe shows the toe cleavage).
        top_line = []
        for a in angles:
            fwd = math.cos(a)
            # (front: over the instep; back: inside the heel counter – it ran
            # 2.5 cm behind the heel cup and stood out as a flap)
            y = ankle.y + .006 + (.074 if fwd > 0 else .046) * fwd
            z = .036 + .019 * smooth(-.2, -1.0, fwd) - .004 * smooth(.3, 1.0, fwd)
            top_line.append(Vector((ankle.x - .032 * math.sin(a), y, z)))
        top_line = clear(top_line, .0035)
        rows = [last(.006, .040, .199, -.041), last(.016, .041, .193, -.042),
                clear(last(.026, .039, .178, -.043), .0035), clear(last(.034, .035, .150, -.043), .0035)]
        # Blend the last top row into the top line so the opening is smooth.
        rows.append([p.lerp(q, .55) for p, q in zip(rows[-1], top_line)])
        rows.append(top_line)
        add(rows, upper, side=side)
        # Turned top line (the leather folds over to the lining).
        inner = [p.lerp(Vector((ankle.x, p.y, p.z - .004)), .07) for p in top_line]
        add([top_line, inner, [p - Vector((0, 0, .012)) for p in inner]], lining, side=side)
        # The heel post.
        seat_y = ankle.y - .026
        parts += heel_post(joints, side, pitch, seat_y, .003, upper, edge, stiletto=True)

    insert_parts(obj, parts, replace=True)
    weights_from(obj, legs, lambda p: smooth(.030, .060, p.z) * (1 - smooth(.040, .100, p.y)))


def heel_sandal(obj, joints, pitch):
    """Strappy evening sandal: bend its sole and straps, add a stiletto."""
    mesh = obj.data
    for v in mesh.vertices:
        v.co = bend(v.co, ball_y(joints, side_of(v.co)), pitch)
    keys = mesh.shape_keys
    if keys:
        for kb in keys.key_blocks:
            for i, d in enumerate(kb.data):
                d.co = bend(d.co, ball_y(joints, side_of(d.co)), pitch)
    strap = mesh.materials[0]
    cap = shader_material('hero_footwear_leather_edge', (.094, .075, .062), .64)
    parts = []
    for side in ('l', 'r'):
        ankle = joints['foot_' + side]
        parts += heel_post(joints, side, pitch, ankle.y - .026, .002, strap, cap, stiletto=True)
    insert_parts(obj, parts)


def heel_shape_keys(meshes, joints):
    """Every mesh with a bare foot gets a "Heel" key: toes bent flat for STRAP_PITCH."""
    done = []
    for obj in meshes:
        if obj.type != 'MESH' or not any(s in obj.name for s in ('Feet', 'Barefoot', '_Bare')):
            continue
        mesh = obj.data
        if mesh.shape_keys is None:
            obj.shape_key_add(name='Basis', from_mix=False)
        if 'Heel' in mesh.shape_keys.key_blocks:
            continue
        basis = mesh.shape_keys.reference_key
        key = obj.shape_key_add(name='Heel', from_mix=False)
        moved = 0
        for i, b in enumerate(basis.data):
            p = b.co
            if p.z > .07:
                continue
            q = bend(p, ball_y(joints, side_of(p)), STRAP_PITCH)
            if (q - p).length > 1e-6:
                moved += 1
            key.data[i].co = q
        done.append((obj.name, moved))
    return done


def build_heels(meshes, joints):
    wardrobe = {o.name: o for o in meshes}
    legs = wardrobe.get('Fashion_Legs')
    if 'Footwear_pumps' in wardrobe and legs is not None:
        court_shoe(wardrobe['Footwear_pumps'], joints, legs, PITCH['Footwear_pumps'])
    if 'Footwear_eveningstraps' in wardrobe:
        heel_sandal(wardrobe['Footwear_eveningstraps'], joints, PITCH['Footwear_eveningstraps'])
    keys = heel_shape_keys(meshes, joints)
    print('HEELS pumps/eveningstraps rebuilt; Heel keys', keys)
