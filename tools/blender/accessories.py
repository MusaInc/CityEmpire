# WorldState accessories, fitted per face (exec'd by build_character.py; uses
# its scope: mesh, material, active, apply, J, GROUP_FACES, bf ...).
#
# Every accessory is built from that face's measured landmarks (eye centres,
# corneas, nose bridge, temple and ear positions, scalp shape), skinned 100%
# to the head bone, and named Acc_<model>_<face> (model = the shop item's
# model id: shades, cap, beanie, headphones). CharacterRig shows the fitted
# version for the worn face and hides the generic gear.glb piece.
#
# Hair under hats (CharacterRig.HAT_HAIR): caps and headphones sit on a crop's
# volume (taller cuts are worn as a crop under them); a beanie sits on a buzz.
import math
import bmesh
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ACC_MATS = {}


def acc_mat(name, color, rough, metal=0.0):
    if name not in ACC_MATS:
        m = material(name, color, rough)
        m.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value = metal
        ACC_MATS[name] = m
    return ACC_MATS[name]


def _skin_head(ob):
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    vg = ob.vertex_groups.new(name='b_head')
    vg.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')
    # Joined primitives bring a partial UV layer (zero on everything else):
    # drop it so the export step unwraps the whole piece.
    while ob.data.uv_layers:
        ob.data.uv_layers.remove(ob.data.uv_layers[0])
    active(ob)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(50), keep_sharp_edges=True)
    # (No placeholder UV layer: the export step unwraps meshes without UVs;
    # an all-zero layer gave degenerate tangents -> NaN normals -> sparkles.)


def sweep(name, path, section, closed=False, twist_up=Vector((0, 0, 1)), uv_len=.1):
    """Sweeps a closed 2D section [(across, up)] (or a callable i -> section)
    along path points. Frames: tangent, `up` kept from twist_up."""
    bm = bmesh.new()
    rings = []
    n = len(path)
    for i, p in enumerate(path):
        a = path[(i - 1) % n] if closed or i > 0 else path[0]
        b = path[(i + 1) % n] if closed or i < n - 1 else path[-1]
        t = (b - a).normalized()
        up = twist_up(i) if callable(twist_up) else twist_up
        side = t.cross(up).normalized()
        upv = side.cross(t).normalized()
        sec = section(i) if callable(section) else section
        rings.append([bm.verts.new(p + side * x + upv * y) for x, y in sec])
    m = len(rings[0])
    seg = n if closed else n - 1
    uvs = []
    for i in range(seg):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for k in range(m):
            f = bm.faces.new((r0[k], r0[(k + 1) % m], r1[(k + 1) % m], r1[k]))
    if not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def rrect(w, h, r, n=3):
    """Rounded rectangle section, centred, counter-clockwise."""
    pts = []
    r = min(r, w / 2 - 1e-5, h / 2 - 1e-5)
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def join(name, objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


class HeadFit:
    """Landmarks of one face (rig bind pose, metres)."""

    def __init__(self, fid, pos, skin, ecz, ecy):
        me = skin.data
        self.tree = BVHTree.FromPolygons([v.co for v in me.vertices], [list(p.vertices) for p in me.polygons])
        ev = {}
        for side in ('l', 'r'):
            pts = [pos[j] for i in GROUP_FACES['helper-%s-eye' % side] for j in bf[i]]
            c = sum(pts, Vector()) / len(pts)
            ev['L' if c.x < 0 else 'R'] = (c, max(p.y for p in pts))
        self.eye = {'L': ev['L'][0], 'R': ev['R'][0]}
        self.cornea_y = max(ev['L'][1], ev['R'][1])
        self.ez, self.ey = ecz, ecy
        self.ipd = (self.eye['R'] - self.eye['L']).length
        hit = self.tree.ray_cast(Vector((0, self.ey + .3, self.ez + .002)), Vector((0, -1, 0)))
        self.bridge_y = hit[0].y if hit[0] else self.cornea_y + .006
        # Head centre for scalp sampling (inside the skull)
        self.hc = Vector((0, self.ey - .085, self.ez + .02))

    def side_x(self, y, z, sx):
        """Head surface |x| at (y, z) on side sx (ray from outside in)."""
        hit = self.tree.ray_cast(Vector((sx * .3, y, z)), Vector((-sx, 0, 0)))
        return abs(hit[0].x) if hit[0] else .075

    def scalp(self, d):
        """Scalp point along direction d from the head centre (or, after
        on_hair(), the outer surface of that hair cut)."""
        hit = self.tree.ray_cast(self.hc + d * .3, -d)
        p = hit[0] if hit[0] else self.hc + d * .1
        for t in getattr(self, 'hair_trees', []):
            h = t.ray_cast(self.hc + d * .3, -d)
            if h[0] is not None and (h[0] - self.hc).length > (p - self.hc).length:
                p = h[0]
        return p

    def on_hair(self, *hair_obs):
        """Fit to the outside of these hair meshes (the cut worn under the hat)."""
        self.hair_trees = [BVHTree.FromPolygons([v.co for v in o.data.vertices], [list(q.vertices) for q in o.data.polygons])
                           for o in hair_obs]

    def ear(self, sx):
        """Ear root (where a temple arm or cup meets the head): the outermost
        skin near the ear's height, back from the eyes."""
        best = None
        for dy in np.linspace(-.06, -.11, 11):
            for dz in np.linspace(-.04, .01, 11):
                x = self.side_x(self.ey + dy, self.ez + dz, sx)
                if best is None or x > best[0]:
                    best = (x, self.ey + dy, self.ez + dz)
        return Vector((sx * best[0], best[1], best[2]))


# ------------------------------------------------------------------ shades
def make_shades(fid, hf):
    """Acetate sunglasses: a wrapped front with rounded-rectangle rims (a
    shade wider at the top), a keyhole bridge on the nose, curved tinted
    lenses, two rivets, temple arms that hug the head and hook behind the
    ears."""
    frame_m = acc_mat('hero_shade_frame', (.018, .018, .02), .34)
    lens_m = acc_mat('hero_shade_lens', (.02, .025, .03), .05)
    metal_m = acc_mat('hero_shade_metal', (.75, .74, .72), .25, 1.0)
    a, b, ex = .0255, .0205, 3.0          # lens half width / height, superellipse
    cx = max(.031, hf.ipd / 2 + .001)       # lens centres on the pupils
    cz = hf.ez - .003
    rim_w, depth = .0042, .0046
    wrap = .16
    y0 = max(hf.bridge_y + .0008 + depth, hf.cornea_y + .011 + depth * .5)

    def yf(x):  # the front's wrap: set back toward the temples
        return y0 - wrap * x * x

    def outline(sx, grow, n=48):
        pts = []
        for k in range(n):
            t = math.tau * k / n
            c, s = math.cos(t), math.sin(t)
            x = a * np.sign(c) * abs(c) ** (2 / ex)
            z = b * np.sign(s) * abs(s) ** (2 / ex)
            x *= 1 + .07 * (z / b)               # wider at the brow line
            if z > 0:
                z *= 1 - .08 * (x * sx > 0) * (x * sx) / a   # top line dips a touch outward
            nrm = Vector((x / a ** 2, 0, z / b ** 2)).normalized()
            p = Vector((sx * cx + x, 0, cz + z)) + Vector((nrm.x, 0, nrm.z)) * grow
            p.y = yf(p.x)
            pts.append(p)
        return pts
    parts = []
    for sx in (-1, 1):
        rim_c = outline(sx, rim_w * .5)
        sec = rrect(rim_w, depth, .0014)
        # section across = in-plane outward, up = depth (toward the face)
        rim = sweep('rim', rim_c, [(x, y) for x, y in sec], closed=True, twist_up=Vector((0, -1, 0)))
        parts.append(rim)
        # lens: a curved cap inside the rim
        inner = outline(sx, .0006)
        bm = bmesh.new()
        ctr = Vector((sx * cx, yf(sx * cx) + .0016, cz))
        cv = bm.verts.new(ctr)
        rings = []
        for r in (.33, .66, 1.0):
            ring = []
            for p in inner:
                q = ctr.lerp(p, r)
                q.y = yf(q.x) + .0016 * (1 - r * r) - .0003
                ring.append(bm.verts.new(q))
            rings.append(ring)
        m = len(inner)
        for k in range(m):
            bm.faces.new((cv, rings[0][k], rings[0][(k + 1) % m]))
        for r0, r1 in zip(rings, rings[1:]):
            for k in range(m):
                bm.faces.new((r0[k], r1[k], r1[(k + 1) % m], r0[(k + 1) % m]))
        for f in bm.faces:
            if f.normal.y < 0:
                f.normal_flip()
        me = bpy.data.meshes.new('lens')
        bm.to_mesh(me)
        bm.free()
        lens = bpy.data.objects.new('lens', me)
        bpy.context.collection.objects.link(lens)
        lens.data.materials.append(lens_m)
        parts.append(lens)
        # rivets at the outer top corner
        rv = Vector((sx * (cx + a * .72), yf(sx * (cx + a * .72)) + depth * .5 + .0002, cz + b * .62))
        bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=.0016, depth=.001, location=rv, rotation=(math.pi / 2, 0, 0))
        r_ = bpy.context.object
        active(r_)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        r_.data.materials.append(metal_m)
        parts.append(r_)
        # end piece + temple arm: from the rim's outer top, back along the
        # head (2.5 mm off the skin), over the ear root and down behind it.
        hx = sx * (cx + a + rim_w * .6)
        hz = cz + b * .55
        hy = yf(hx) - depth * .2
        ear = hf.ear(sx)
        path = [Vector((hx, hy, hz)), Vector((hx + sx * .004, hy - .01, hz))]
        for k in range(1, 7):
            y = hy - .01 - (hy - .01 - (ear.y + .004)) * k / 6
            z = hz + (ear.z + .012 - hz) * (k / 6) ** 1.5
            x = hf.side_x(y, z, sx) + .0028
            path.append(Vector((sx * max(x, abs(path[-1].x) - .002), y, z)))
        # hook behind the ear
        e = path[-1]
        for k, (dy, dz) in enumerate(((-.008, -.006), (-.013, -.017), (-.014, -.03))):
            x = hf.side_x(e.y + dy, e.z + dz, sx) + .0022
            path.append(Vector((sx * x, e.y + dy, e.z + dz)))
        # smooth the path
        P = [p.copy() for p in path]
        for _ in range(3):
            for i in range(1, len(P) - 1):
                P[i] = P[i] * .5 + (path[i - 1] + path[i + 1]) * .25
            path = [p.copy() for p in P]
        nP = len(path)
        temple = sweep('temple', path, lambda i: rrect(.0052 - .0022 * i / (nP - 1), .0024, .0009), twist_up=Vector((sx, 0, 0)))
        parts.append(temple)
    # keyhole bridge between the rims' inner top
    bz = cz + b * .45
    bx = cx - a - rim_w * .2
    bridge_path = [Vector((-bx, 0, bz)), Vector((-bx * .5, 0, bz + .0028)), Vector((0, 0, bz + .0036)), Vector((bx * .5, 0, bz + .0028)), Vector((bx, 0, bz))]
    for p in bridge_path:
        p.y = yf(p.x)
    parts.append(sweep('bridge', bridge_path, rrect(.0038, depth * .9, .0012), twist_up=Vector((0, -1, 0))))
    for p in parts:
        if not p.data.materials:
            p.data.materials.append(frame_m)
    ob = join('Acc_shades_' + fid, parts)
    _skin_head(ob)
    return ob


# ------------------------------------------------------------------ head-wear
def scalp_grid(hf, offset_fn, rows, cols, el0=-.2, el1=1.0):
    """(cols x rows) points over the scalp: azimuth round the head (0 =
    front), elevation el0..el1 (radians from the head centre's horizontal)."""
    G = []
    for i in range(rows):
        el = el0 + (el1 - el0) * i / (rows - 1)
        row = []
        for k in range(cols):
            az = math.tau * k / cols
            d = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
            p = hf.scalp(d)
            row.append(p + d * offset_fn(az, el))
        G.append(row)
    return G


def grid_obj(name, G, closed_cols=True, cap_top=None):
    bm = bmesh.new()
    V = [[bm.verts.new(p) for p in row] for row in G]
    cols = len(G[0])
    for i in range(len(G) - 1):
        for k in range(cols if closed_cols else cols - 1):
            k2 = (k + 1) % cols
            bm.faces.new((V[i][k], V[i][k2], V[i + 1][k2], V[i + 1][k]))
    if cap_top is not None:
        t = bm.verts.new(cap_top)
        for k in range(cols):
            bm.faces.new((V[-1][k], V[-1][(k + 1) % cols], t))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


HAIR_TOP = .021   # a crop's lift on top (make_hair) + a little
HAIR_SIDE = .007


def _band_el(hf, az, front, side, back):
    """Elevation of a hat's lower edge at azimuth az: just above the brows at
    the front, over the ear tops at the sides, the nape at the back."""
    c = math.cos(az)
    s = abs(math.sin(az))
    z = front * max(c, 0) ** 2 + back * max(-c, 0) ** 2 + side * s ** 2
    return z


def make_cap(fid, hf):
    """Six-panel baseball cap: a crown on a crop's volume, panel seams, a
    curved peak, top button, a strap arch at the back."""
    fab = acc_mat('hero_cap', (.16, .17, .19), .78)
    peak_m = acc_mat('hero_cap_peak', (.14, .15, .17), .7)
    def off(az, el):
        return .0075   # clears the crop's clumps between the fit samples
    rows, cols = 10, 48
    G = []
    for i in range(rows):
        row = []
        for k in range(cols):
            az = math.tau * k / cols
            el_lo = _band_el(hf, az, .28, .1, -.1)
            el = el_lo + (1.42 - el_lo) * (i / (rows - 1)) ** .85
            d = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
            p = hf.scalp(d) + d * off(az, el)
            # panel seams: six shallow grooves running up to the button
            seam = min(abs(((az * 3 / math.pi) % 1) - .5) for _ in [0])
            p += d * (-.0012 * math.exp(-((.5 - seam) / .05) ** 2) * (i > 0))
            row.append(p)
        G.append(row)
    top = hf.scalp(Vector((0, 0, 1))) + Vector((0, 0, .0075))
    crown = grid_obj('crown', G, cap_top=top)
    crown.data.materials.append(fab)
    # Peak: from the front band, curved down at the sides, 7 cm long.
    P = []
    for i in range(5):
        t = i / 4
        row = []
        for k in range(17):
            u = (k / 16 - .5) * 2           # -1..1 across
            az = u * .95
            el_lo = _band_el(hf, az, .28, .1, -.1)
            d = Vector((math.sin(az) * math.cos(el_lo), math.cos(az) * math.cos(el_lo), math.sin(el_lo)))
            base = hf.scalp(d) + d * (off(az, el_lo) + .001)
            fwd = Vector((math.sin(az) * .35, 1, 0)).normalized()
            L = .072 * (1 - .55 * u * u) ** .5
            p = base + fwd * L * t + Vector((0, 0, -.012 * t * t - .006 * t * u * u))
            row.append(p)
        P.append(row)
    peak = grid_obj('peak', P, closed_cols=False)
    so = peak.modifiers.new('t', 'SOLIDIFY')
    so.thickness = .004
    so.use_rim_only = True   # single sheet + edge: closed thin shells self-shadow (acne) on mobile
    apply(peak, so)
    peak.data.materials.append(peak_m)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=.0075, location=top + Vector((0, 0, -.002)))
    btn = bpy.context.object
    btn.scale = (1, 1, .45)
    active(btn)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    btn.data.materials.append(fab)
    so = crown.modifiers.new('t', 'SOLIDIFY')
    so.thickness = .0025
    so.offset = -1
    so.use_rim_only = True
    apply(crown, so)
    ob = join('Acc_cap_' + fid, [crown, peak, btn])
    _skin_head(ob)
    return ob


def make_beanie(fid, hf):
    """Rib-knit beanie on a buzz cut: a soft crown with a slight slouch, and a
    folded cuff above the brows and over the ear tops."""
    knit = acc_mat('hero_beanie', (.16, .17, .19), .92)
    rows, cols = 14, 56
    G = []
    for i in range(rows):
        row = []
        for k in range(cols):
            az = math.tau * k / cols
            el_lo = _band_el(hf, az, .33, .02, -.22)
            t = i / (rows - 1)
            el = el_lo + (1.5 - el_lo) * t ** .9
            d = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
            o = .004 + .01 * max(0.0, math.sin(el)) ** 3 * (1 + .25 * max(0.0, -math.cos(az)))   # slouch to the back
            rib = .0007 * math.sin(az * 64)
            p = hf.scalp(d) + d * (o + rib)
            row.append(p)
        G.append(row)
    top = hf.scalp(Vector((0, -.12, 1)).normalized()) + Vector((0, -.006, .02))
    dome = grid_obj('dome', G, cap_top=top)
    # Cuff: the first 4.5 cm folded up, standing 5 mm proud of the dome.
    C = []
    for i in range(4):
        row = []
        for k in range(cols):
            az = math.tau * k / cols
            el_lo = _band_el(hf, az, .33, .02, -.22)
            el = el_lo - .02 + .38 * i / 3
            d = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
            o = .009 + .0016 * math.sin(math.pi * i / 3)
            row.append(hf.scalp(d) + d * (o + .0009 * math.sin(az * 64)))
        C.append(row)
    cuff = grid_obj('cuff', C)
    for o_ in (dome, cuff):
        so = o_.modifiers.new('t', 'SOLIDIFY')
        so.thickness = .003
        so.offset = -1
        so.use_rim_only = True
        apply(o_, so)
        o_.data.materials.append(knit)
    ob = join('Acc_beanie_' + fid, [dome, cuff])
    _skin_head(ob)
    return ob


def make_headphones(fid, hf):
    """Over-ear headphones: cushioned cups centred on the measured ears, yokes,
    sliders and a padded band resting on the hair."""
    shell = acc_mat('hero_phones_shell', (.03, .03, .033), .35)
    pad = acc_mat('hero_phones_pad', (.02, .02, .022), .6)
    metal = acc_mat('hero_shade_metal', (.75, .74, .72), .25, 1.0)
    parts = []
    tops = []
    for sx in (-1, 1):
        ear = hf.ear(sx)
        # The cushion rests on the side of the head round the ear (the head
        # plane just in front of the ear), enclosing it; the ear sits in the cup.
        x_head = hf.side_x(ear.y + .035, ear.z, sx)
        c = Vector((sx * (x_head + .009), ear.y + .004, ear.z - .004))
        out = Vector((sx, 0, 0))
        bpy.ops.mesh.primitive_torus_add(major_radius=.03, minor_radius=.011, major_segments=32, minor_segments=10,
                                         location=c, rotation=(0, math.pi / 2, 0))
        cu = bpy.context.object
        cu.scale = (1, 1, 1.18)
        active(cu)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        cu.data.materials.append(pad)
        cup_c = c + out * max(.016, abs(ear.x) - x_head + .002)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=12, radius=.041, location=cup_c)
        cup = bpy.context.object
        cup.scale = (.42, 1, 1.15)
        active(cup)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bm = bmesh.new()
        bm.from_mesh(cup.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if (v.co.x - cup_c.x) * sx < -.004], context='VERTS')
        bm.to_mesh(cup.data)
        bm.free()
        cup.data.materials.append(shell)
        top = cup_c + Vector((0, 0, .046))
        tops.append(top)
        yoke = sweep('yoke', [cup_c + Vector((0, -.036, .02)), top + Vector((0, -.02, .006)), top + Vector((0, 0, .01)),
                              top + Vector((0, .02, .006)), cup_c + Vector((0, .036, .02))], rrect(.004, .006, .0015),
                     twist_up=out)
        yoke.data.materials.append(metal)
        parts += [cu, cup, yoke]
    # band: over the head through the crown, 1.4 cm above the hair top
    path = []
    for k in range(17):
        t = k / 16
        az = (-math.pi / 2) + math.pi * t
        el = math.radians(8) + (math.pi / 2 - math.radians(8)) * math.sin(math.pi * t)
        d = Vector((math.sin(az) * math.cos(el) * (1 if az >= 0 else 1), -.12 * math.cos(el), math.sin(el))).normalized()
        d = Vector((math.cos(el) * (1 if t > .5 else -1) * abs(math.cos(math.pi * t)), -.1, math.sin(el) + (1 - abs(math.cos(math.pi * t))))).normalized()
        p = hf.scalp(d) + d * .009
        path.append(p)
    path[0] = tops[0] + Vector((0, 0, .01))
    path[-1] = tops[1] + Vector((0, 0, .01))
    P = [p.copy() for p in path]
    for _ in range(4):
        for i in range(1, len(P) - 1):
            P[i] = (path[i - 1] + path[i] * 2 + path[i + 1]) / 4
        path = [p.copy() for p in P]
    band = sweep('band', path, rrect(.03, .009, .004), twist_up=lambda i: (path[i] - hf.hc).normalized())
    band.data.materials.append(pad)
    parts.append(band)
    ob = join('Acc_headphones_' + fid, parts)
    _skin_head(ob)
    return ob


def make_accessories(fid, pos, skin, ecz, ecy, hair):
    """hair: style -> that face's hair mesh. Hats sit on the cut worn under
    them (CharacterRig.HAT_HAIR): cap on the crop, beanie on the buzz,
    headphones' band over every short cut."""
    hf = HeadFit(fid, pos, skin, ecz, ecy)
    out = [make_shades(fid, hf)]
    hf.on_hair(hair['crop'])
    out.append(make_cap(fid, hf))
    hf.on_hair(hair['buzz'])
    out.append(make_beanie(fid, hf))
    hf.on_hair(*[hair[k] for k in ('buzz', 'crop', 'fade', 'curls', 'pixie')])
    out.append(make_headphones(fid, hf))
    print('ACCESSORIES', fid, 'bridge', round(hf.bridge_y, 4), 'cornea', round(hf.cornea_y, 4), 'ipd', round(hf.ipd, 4), flush=True)
    return out
