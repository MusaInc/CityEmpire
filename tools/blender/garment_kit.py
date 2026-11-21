# WorldState garment kit: the reusable tailoring pipeline for every top,
# exec'd by empire_wardrobe.py inside build_character.py's scope (J, ni,
# names, weights, RB, body, bf, part, mesh, subdiv, apply, material, wsum,
# FRONT, NECK_Y, HIP, _btree, TEX ...).
#
# Conventions (docs: art/hero/PIPELINE.md)
#   * Every garment is cut from the shared body (same vertex weights as the
#     skin, so it deforms with the gameplay rig exactly), then FITTED, not
#     pushed: per height slice the cloth spans the body's convex hull (it
#     bridges the spine groove, the sternum and the waist instead of
#     shrink-wrapping them) plus an ease, and hangs under gravity: going
#     down from the shoulders it can only come in at a limited taper (the
#     chest carries the cloth; darts let it in at the waist).
#   * Sleeves are tubes fitted the same way round the arm axis (hanging from
#     the bicep, tapering to the cuff).
#   * Layers: base layer (skin-tight) 0.4 cm, shirts 1.0 cm, knits 1.3 cm,
#     jackets 2.0 cm (EASE_LAYER): a garment worn over another fits that
#     layer's surface, so layers never cross.
#   * Detail lives in textures: seams, stitches and fine folds are baked into
#     a per-garment normal map from 3D seam definitions; collars, plackets,
#     cuffs and hems map into one shared trim atlas (trim_*.png) and every
#     fabric shares one tiling weave normal. Price changes the design, never
#     the rendering quality: every garment gets the same pipeline.
import math
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

EASE_LAYER = {'skin': .004, 'shirt': .010, 'knit': .013, 'jacket': .020}


def armw(j):
    return wsum(j, 'upper_arm_l', 'upper_arm_r', 'forearm_l', 'forearm_r', 'hand_l', 'hand_r')


def _smooth(a, n=2, axis=0, wrap=False):
    for _ in range(n):
        if wrap:
            a = (np.roll(a, 1, axis) + 2 * a + np.roll(a, -1, axis)) / 4
        else:
            b = a.copy()
            sl = [slice(None)] * a.ndim
            sl[axis] = slice(1, -1)
            s0 = [slice(None)] * a.ndim
            s0[axis] = slice(0, -2)
            s2 = [slice(None)] * a.ndim
            s2[axis] = slice(2, None)
            b[tuple(sl)] = (a[tuple(s0)] + 2 * a[tuple(sl)] + a[tuple(s2)]) / 4
            a = b
    return a


def _hull_radius(pts, nang):
    """Radius of the 2D convex hull of pts (around the origin) at nang angles
    (angle 0 = +Y)."""
    pts = sorted(set((round(p[0], 5), round(p[1], 5)) for p in pts))
    if len(pts) < 3:
        return None

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    hull = lo[:-1] + hi[:-1]
    out = np.zeros(nang)
    for k in range(nang):
        a = math.tau * k / nang
        d = (math.sin(a), math.cos(a))
        best = 0.0
        for i in range(len(hull)):
            p, q = hull[i], hull[(i + 1) % len(hull)]
            # ray o + t d against segment p-q
            ex, ey = q[0] - p[0], q[1] - p[1]
            den = d[0] * ey - d[1] * ex
            if abs(den) < 1e-12:
                continue
            t = (p[0] * ey - p[1] * ex) / den
            s = (p[0] * d[1] - p[1] * d[0]) / den
            if t > 0 and -1e-6 <= s <= 1 + 1e-6:
                best = max(best, t)
        out[k] = best
    return out


class TorsoFrame:
    """Height slices of the body's torso: centre line, convex-hull radius per
    angle (angle 0 = front)."""
    Z0, Z1, DZ, NA = .80, 1.64, .01, 96

    def __init__(self):
        nz = int(round((self.Z1 - self.Z0) / self.DZ)) + 1
        self.nz = nz
        self.zs = np.array([self.Z0 + i * self.DZ for i in range(nz)])
        ids = sorted({j for i in body for j in bf[i]})
        tors = [j for j in ids if armw(j) < .35 and wsum(j, 'head') < .5]
        self.cy = np.zeros(nz)
        self.hull = np.zeros((nz, self.NA))
        for zi, z in enumerate(self.zs):
            sl = [RB[j] for j in tors if abs(RB[j].z - z) < self.DZ * 1.2]
            if len(sl) < 6:
                self.cy[zi] = self.cy[zi - 1] if zi else NECK_Y
                self.hull[zi] = self.hull[zi - 1] if zi else .1
                continue
            ys = [p.y for p in sl]
            self.cy[zi] = (min(ys) + max(ys)) / 2
            h = _hull_radius([(p.x, (p.y - self.cy[zi]) * FRONT) for p in sl], self.NA)
            self.hull[zi] = h if h is not None else self.hull[zi - 1]
        self.cy = _smooth(self.cy, 6)
        self.hull = _smooth(_smooth(self.hull, 3, 0), 2, 1, wrap=True)

    def polar(self, co):
        zi = min(self.nz - 1, max(0, int(round((co.z - self.Z0) / self.DZ))))
        cy = float(np.interp(co.z, self.zs, self.cy))
        dx, dy = co.x, (co.y - cy) * FRONT
        a = math.atan2(dx, dy) % math.tau
        return zi, cy, a, math.hypot(dx, dy)

    def sample(self, table, zf, a):
        """Bilinear lookup of a (nz, NA) table."""
        zf = min(self.nz - 1.001, max(0.0, zf))
        z0 = int(zf)
        tz = zf - z0
        af = a / math.tau * self.NA
        a0 = int(af) % self.NA
        ta = af - int(af)
        a1 = (a0 + 1) % self.NA
        v0 = table[z0, a0] * (1 - ta) + table[z0, a1] * ta
        v1 = table[z0 + 1, a0] * (1 - ta) + table[z0 + 1, a1] * ta
        return v0 * (1 - tz) + v1 * tz


class ArmFrame:
    """Slices along one arm (bind pose: straight, 42 degrees out): hull
    radius per angle round the shoulder->wrist axis."""
    NT, NA = 64, 48

    def __init__(self, side):
        self.side = side
        self.a = J['upper_arm_' + side]
        self.h = J['hand_' + side]
        self.L = (self.h - self.a).length
        self.ax = (self.h - self.a) / self.L
        u = Vector((0, FRONT, 0))
        self.u = (u - self.ax * u.dot(self.ax)).normalized()
        self.w = self.ax.cross(self.u)
        ids = sorted({j for i in body for j in bf[i]})
        sx = -1 if side == 'l' else 1
        arm = [j for j in ids if wsum(j, 'upper_arm_' + side, 'forearm_' + side) > .6 and RB[j].x * sx > 0]
        self.ts = np.linspace(-.1, 1.05, self.NT)
        self.hull = np.zeros((self.NT, self.NA))
        pts = [(self._local(RB[j]), j) for j in arm]
        for ti, t in enumerate(self.ts):
            sl = [(p[1], p[2]) for p, j in pts if abs(p[0] - t) < .012]
            h = _hull_radius(sl, self.NA) if len(sl) >= 6 else None
            self.hull[ti] = h if h is not None else (self.hull[ti - 1] if ti else .05)
        self.hull = _smooth(_smooth(self.hull, 3, 0), 2, 1, wrap=True)
        # The arm's section right at the shoulder takes in chest / underarm
        # tissue weighted to the arm (build B most): a sleeve hung from it
        # ballooned into a pad. Cap the top 12% at the upper arm just below.
        ref = int(np.searchsorted(self.ts, .14))
        cap = self.hull[ref] * 1.05
        for ti, t in enumerate(self.ts):
            if t < .14:
                self.hull[ti] = np.minimum(self.hull[ti], cap)

    def _local(self, co):
        r = co - self.a
        return (r.dot(self.ax) / self.L, r.dot(self.w), r.dot(self.u))

    def polar(self, co):
        t, x, y = self._local(co)
        return t, math.atan2(x, y) % math.tau, math.hypot(x, y)

    def point(self, t, a, r):
        return self.a + self.ax * (t * self.L) + (self.w * math.sin(a) + self.u * math.cos(a)) * r

    def sample(self, table, t, a):
        tf = (t - self.ts[0]) / (self.ts[1] - self.ts[0])
        tf = min(self.NT - 1.001, max(0.0, tf))
        t0 = int(tf)
        tt = tf - t0
        af = a / math.tau * self.NA
        a0 = int(af) % self.NA
        ta = af - int(af)
        a1 = (a0 + 1) % self.NA
        v0 = table[t0, a0] * (1 - ta) + table[t0, a1] * ta
        v1 = table[t0 + 1, a0] * (1 - ta) + table[t0 + 1, a1] * ta
        return v0 * (1 - tt) + v1 * tt


_TF = None
_AF = {}


def frames():
    global _TF
    if _TF is None:
        _TF = TorsoFrame()
        _AF['l'] = ArmFrame('l')
        _AF['r'] = ArmFrame('r')
    return _TF, _AF


def _hang_torso(ease, taper_front, taper_side, top=1.46):
    """Fitted torso radius table: hull + ease, hanging from the shoulders."""
    tf, _ = frames()
    R = np.zeros_like(tf.hull)
    for k in range(tf.NA):
        a = math.tau * k / tf.NA
        side = abs(math.sin(a))
        taper = taper_front + (taper_side - taper_front) * side ** 2
        prev = None
        for zi in range(tf.nz - 1, -1, -1):
            z = tf.zs[zi]
            r = tf.hull[zi, k] + ease(a, z)
            if prev is not None and z < top:
                r = max(r, prev - taper * tf.DZ)
            R[zi, k] = r
            prev = r
    return _smooth(_smooth(R, 2, 0), 1, 1, wrap=True)


def _hang_arm(af, ease_t, taper=.06, t_top=.12):
    R = np.zeros_like(af.hull)
    for k in range(af.NA):
        prev = None
        for ti, t in enumerate(af.ts):
            r = af.hull[ti, k] + ease_t(t)
            if prev is not None and t > t_top:
                r = max(r, prev - taper * (af.ts[1] - af.ts[0]) * af.L)
            R[ti, k] = r
            prev = r
    return _smooth(_smooth(R, 2, 0), 1, 1, wrap=True)


def tailor(ob, layer='shirt', taper_front=.10, taper_side=.30, sleeve_ease=(.020, .016), sleeve_taper=.07,
           shoulder_ease=.004, back_extra=.004, cuff=None):
    """Fits the garment `ob` (cut from the body, body weights) to the body:
    hull + ease, hanging; sleeves as tapered tubes. `cuff` = (t_start, t_end,
    radius_fn(side, a)) gathers the sleeve end into a cuff's opening."""
    tf, afs = frames()
    base = EASE_LAYER[layer]

    def ease(a, z):
        back = max(0.0, -math.cos(a))
        e = base + back_extra * back
        k = max(0.0, min(1.0, (z - 1.40) / .06))
        return e + (shoulder_ease - e) * k
    RT = _hang_torso(ease, taper_front, taper_side)
    RA = {}
    for s, af in afs.items():
        def et(t, s=s):
            k = max(0.0, min(1.0, (t - .35) / .5))
            return sleeve_ease[0] + (sleeve_ease[1] - sleeve_ease[0]) * k
        RA[s] = _hang_arm(af, et, sleeve_taper)
    me = ob.data
    dg = ob.vertex_groups
    gidx = {g.index: g.name[2:] for g in dg}
    disp = []
    for v in me.vertices:
        wts = {gidx[g.group]: g.weight for g in v.groups if g.group in gidx}
        wa = sum(wts.get(b, 0) for b in ('upper_arm_l', 'upper_arm_r', 'forearm_l', 'forearm_r', 'hand_l', 'hand_r'))
        co = v.co.copy()
        side = 'l' if co.x < 0 else 'r'
        k = max(0.0, min(1.0, (wa - .25) / .5))
        k = k * k * (3 - 2 * k)
        pt = co
        if k < 1:
            zi, cy, a, r = tf.polar(co)
            zf = (co.z - tf.Z0) / tf.DZ
            want = tf.sample(RT, zf, a)
            if want > r:
                d = Vector((math.sin(a), FRONT * math.cos(a), 0))
                pt = Vector((0, cy, co.z)) + d * want
        pa = co
        if k > 0:
            af = afs[side]
            t, a, r = af.polar(co)
            want = af.sample(RA[side], t, a)
            if cuff is not None and t > cuff[0]:
                ct = min(1.0, (t - cuff[0]) / max(cuff[1] - cuff[0], 1e-4))
                ct = ct * ct * (3 - 2 * ct)
                want = want + (cuff[2](side, a) - want) * ct
            if want > r or cuff is not None and t > cuff[0]:
                pa = af.point(t, a, max(want, r + .002))
        disp.append((pt * (1 - k) + pa * k) - co)
    # Smooth the displacement field over the mesh (no lumps where the
    # torso and sleeve fits meet, or where the hull changes fast).
    nbr = [[] for _ in me.vertices]
    for e in me.edges:
        a_, b_ = e.vertices
        nbr[a_].append(b_)
        nbr[b_].append(a_)
    D = np.array([[d.x, d.y, d.z] for d in disp])
    for _ in range(6):
        D2 = D.copy()
        for i, nb in enumerate(nbr):
            if nb:
                D2[i] = D[i] * .5 + D[nb].mean(0) * .5
        D = D2
    for v, d in zip(me.vertices, D):
        v.co += Vector(d)
    me.update()
    clear_body(ob, .0035)


def clear_body(ob, gap):
    """Guarantees `gap` m of clearance from the skin (the fit's floor, not
    its shape: the shape comes from tailor)."""
    me = ob.data
    for v in me.vertices:
        hit = _btree.find_nearest(v.co)
        if hit[0] is None:
            continue
        p, n, _, d = hit
        side = (v.co - p).dot(n)
        if side < gap:
            v.co = p + n * gap
    me.update()


def iso_cut(bm, f):
    """Cuts a bmesh exactly along f's zero line (split crossing edges, join
    the splits across faces) and deletes where f < 0. Smooth curved cuts
    (necklines, hairlines) without plane facets or whole-face stair steps."""
    import bmesh
    vals = {v: f(v.co) for v in bm.verts}
    news = []
    for e in [e for e in bm.edges if (vals[e.verts[0]] < 0) != (vals[e.verts[1]] < 0)]:
        a, b = e.verts
        fa, fb = vals[a], vals[b]
        ne, nv = bmesh.utils.edge_split(e, a, fa / (fa - fb))
        vals[nv] = 0.0
        news.append(nv)
    bmesh.ops.connect_verts(bm, verts=news)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if vals.get(v, f(v.co)) < -1e-7], context='VERTS')


def clear_layer(ob, under, gap, zmax=9.0):
    """Layering: every vertex of `ob` at or below zmax stays `gap` m outside
    the garment `under` (e.g. a shirttail over the trousers' hips and
    pockets). Pushes along the under-layer's normal; fades over 3 cm above
    the pushed band so the cloth doesn't kink."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(under.data)
    bm.normal_update()
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    me = ob.data
    push = {}
    for v in me.vertices:
        if v.co.z > zmax:
            continue
        p, n, _, d = tree.find_nearest(v.co)
        if p is None:
            continue
        out = (v.co - p).dot(n)
        if out < gap and d < .12:   # (.06 left some hem vertices unpushed beside pushed ones: a torn edge)
            push[v.index] = n * (gap - out)
    # spread the push to neighbours so the hem moves as cloth, not spikes
    nbr = [[] for _ in me.vertices]
    for e in me.edges:
        a_, b_ = e.vertices
        nbr[a_].append(b_)
        nbr[b_].append(a_)
    D = {i: Vector(d) for i, d in push.items()}
    for _ in range(4):
        D2 = dict(D)
        for i, d in D.items():
            for j in nbr[i]:
                cand = d * .6
                if j not in D2 or D2[j].length < cand.length:
                    D2[j] = cand
        D = D2
    for i, d in D.items():
        me.vertices[i].co += d
    me.update()
    return len(push)


def tuck_into(ob, under, z_top, gap, blend=.02):
    """Tucks a garment into another (a shirt into trousers): at and below
    z_top every vertex is pulled `gap` m inside the under-layer's surface
    (never into the skin); the pull fades out over `blend` above, which
    leaves the cloth bloused over the waistband."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(under.data)
    bm.normal_update()
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    n = 0
    for v in ob.data.vertices:
        if v.co.z > z_top + blend:
            continue
        k = 1.0 if v.co.z <= z_top else 1 - (v.co.z - z_top) / blend
        p, nrm, _, d = tree.find_nearest(v.co)
        if p is None or d > .08:
            continue
        out = (v.co - p).dot(nrm)
        if out > -gap:
            v.co += nrm * (-gap - out) * k
            n += 1
    ob.data.update()
    clear_body(ob, .0025)
    return n


def shirttail(ob, hem, drop_center, drop_side, rows=4, flare=.004):
    """Extends the level hem down into a curved shirttail: longer at the
    centre front and back than at the side seams. The cloth carries on
    hanging straight (no shrink to the hips). UVs continue down each UV
    island at the island's own texel density (per-vertex 'down' gradient)."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    uvl = bm.loops.layers.uv.active
    tf, _ = frames()
    ring = [e for e in bm.edges if e.is_boundary and all(abs(v.co.z - hem) < 3e-4 for v in e.verts)]
    # per (edge, vert): uv on the edge's face, and d(uv)/d(drop)
    uvE = {}
    for e in ring:
        f = e.link_faces[0]
        for v in e.verts:
            lp = next(l for l in f.loops if l.vert == v)
            uv = lp[uvl].uv.copy()
            # the up-neighbour within this face (not along the hem)
            cand = [lp.link_loop_next, lp.link_loop_prev]
            up = max(cand, key=lambda l: l.vert.co.z - v.co.z)
            dz = up.vert.co.z - v.co.z
            g = (uv - up[uvl].uv) / dz if dz > 1e-4 else Vector((0, -1.0))
            if g.length > 6:
                g = g.normalized() * 6
            uvE[(e, v)] = (uv, g)
    for r in range(rows):
        drops = {}
        res = bmesh.ops.extrude_edge_only(bm, edges=ring)
        nv = {g for g in res['geom'] if isinstance(g, bmesh.types.BMVert)}
        parent = {}
        for v in nv:
            o = next(e.other_vert(v) for e in v.link_edges if e.other_vert(v) not in nv)
            parent[v] = o
            _, cy, a, _ = tf.polar(v.co)
            side = abs(math.sin(a)) ** 1.5
            total = drop_center + (drop_side - drop_center) * side
            h = Vector((v.co.x, v.co.y - cy, 0))
            out = h.normalized() if h.length > 1e-5 else Vector()
            step = total / rows
            v.co += Vector((0, 0, -step)) + out * (flare / rows)
            drops[v] = step
        new_ring = []
        nuvE = {}
        for e in ring:
            q = next(f for f in e.link_faces if any(l.vert in nv for l in f.loops))
            ne = next(ed for ed in q.edges if all(x in nv for x in ed.verts))
            for lp in q.loops:
                if lp.vert in nv:
                    o = parent[lp.vert]
                    uv, g = uvE[(e, o)]
                    nu = uv + g * drops[lp.vert]
                    lp[uvl].uv = nu
                    nuvE[(ne, lp.vert)] = (nu, g)
                else:
                    lp[uvl].uv = uvE[(e, lp.vert)][0]
            new_ring.append(ne)
        ring = new_ring
        uvE = nuvE
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def fold_relief(ob, folds):
    """Small static folds as geometry (silhouette-scale only: finer folds are
    in the normal map). folds: list of (mask(co) -> 0..1, wave(co) -> -1..1,
    amplitude m)."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.normal_update()
    for v in bm.verts:
        d = 0.0
        for mask, wave, amp in folds:
            m = mask(v.co)
            if m > 0:
                d += amp * m * wave(v.co)
        v.co += v.normal * d
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def pack_uvs(ob, margin=.004):
    """Re-packs a garment's UV islands without overlap (cut from the body,
    its islands are the skin's, and shirttail rows continue them into
    space that other islands use: baked maps must own every texel).
    Returns metres per UV unit (for the weave's repeat)."""
    active(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.pack_islands(rotate=False, scale=True, margin=margin)
    bpy.ops.object.mode_set(mode='OBJECT')
    me = ob.data
    me.calc_loop_triangles()
    uvl = me.uv_layers[0]
    a3 = a2 = 0.0
    for t in me.loop_triangles:
        a3 += t.area
        u = [uvl.data[l].uv for l in t.loops]
        a2 += abs((u[1] - u[0]).cross(u[2] - u[0])) / 2
    return math.sqrt(a3 / max(a2, 1e-9))


def face_out(ob, outward):
    """Winds the whole piece so its faces point along outward(centre) (the
    hero shader darkens back faces as the cloth's inside)."""
    import bmesh
    me = ob.data
    score = sum(p.normal.dot(outward(p.center)) * p.area for p in me.polygons)
    if score < 0:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
        me.update()


class SkinSurface:
    """Sample continuous skin weights from a finished garment's triangles."""

    def __init__(self, source):
        me = source.data
        me.calc_loop_triangles()
        self.triangles = [tuple(t.vertices) for t in me.loop_triangles]
        self.positions = [v.co.copy() for v in me.vertices]
        self.tree = BVHTree.FromPolygons(self.positions, self.triangles, all_triangles=True)
        group = {g.index: g.name for g in source.vertex_groups}
        self.weights = [{group[g.group]: g.weight for g in v.groups} for v in me.vertices]

    def at(self, co):
        nearest, _, index, _ = self.tree.find_nearest(co)
        if nearest is None:
            return {}
        ids = self.triangles[index]
        a, b, c = (self.positions[i] for i in ids)
        ab, ac, ap = b - a, c - a, nearest - a
        bb, bc, cc = ab.dot(ab), ab.dot(ac), ac.dot(ac)
        det = bb * cc - bc * bc
        if det <= 1e-14:
            return self.weights[ids[0]]
        u = (cc * ab.dot(ap) - bc * ac.dot(ap)) / det
        v = (bb * ac.dot(ap) - bc * ab.dot(ap)) / det
        result = {}
        for i, k in zip(ids, (1.0 - u - v, u, v)):
            for bone, weight in self.weights[i].items():
                result[bone] = result.get(bone, 0.0) + max(0.0, k) * weight
        return result


def follow_layer(ob, under, zmax, depth, k_max=.7):
    """Blend hanging hems continuously into the lower layer's deformation."""
    weights_from(ob, under, lambda co: min(1.0, (zmax - co.z) / depth) * k_max)


def weights_from(ob, src, k_fn=lambda co: 1.0):
    """Transfer surface skin weights to sewn trims and overlapping layers."""
    skin = SkinSurface(src)
    target = {g.name: g for g in ob.vertex_groups}
    for v in ob.data.vertices:
        k = max(0.0, min(1.0, k_fn(v.co)))
        if k == 0.0:
            continue
        sampled = skin.at(v.co)
        if not sampled:
            continue
        groups = [(ob.vertex_groups[g.group], g.weight) for g in v.groups]
        w = {group.name: weight * (1 - k) for group, weight in groups}
        for name, value in sampled.items():
            w[name] = w.get(name, 0.0) + value * k
        for group, _ in groups:
            group.remove([v.index])
        for name, value in w.items():
            if value > .002:
                if name not in target:
                    target[name] = ob.vertex_groups.new(name=name)
                target[name].add([v.index], value, 'REPLACE')


def fit_over_waist(ob, trousers, band, tucked, gap):
    """Make both trouser cuts share one anti-clipping waist fitting rule."""
    if tucked:
        tuck_into(ob, trousers, PANTS_TOP, gap)
        follow_layer(ob, trousers, PANTS_TOP + .026, .033, k_max=1.0)
    else:
        clear_layer(ob, trousers, gap, zmax=PANTS_TOP + .037)
        clear_layer(ob, band, .004, zmax=PANTS_TOP + .024)
        follow_layer(ob, trousers, PANTS_TOP + .028, .057, k_max=.88)


def drape_top(ob, amount, hem):
    """Low-frequency gravity folds and diagonal shoulder drag in the mesh."""
    tf, arms = frames()

    def torso_mask(co):
        side = 'l' if co.x < 0 else 'r'
        t, _, radius = arms[side].polar(co)
        if t > .055 and radius < .095:
            return 0.0
        return max(0.0, min(1.0, (co.z - hem) / .026, (1.48 - co.z) / .10))

    def hang(co):
        cy = float(np.interp(co.z, tf.zs, tf.cy))
        a = math.atan2(co.x, (co.y - cy) * FRONT)
        z = co.z
        tension = math.exp(-((z - (1.12 + .095 * abs(math.sin(a)))) / .18) ** 2)
        return tension * (.58 * math.sin(a * 8 + z * 7) + .42 * math.sin(a * 13 - z * 18 + .6))

    def drag(co):
        x = abs(co.x)
        z = co.z
        return math.exp(-((x - .15) / .075) ** 2 - ((z - 1.35) / .12) ** 2) * math.sin(z * 45 + x * 33)

    fold_relief(ob, [(torso_mask, hang, amount), (torso_mask, drag, amount * .65)])
    clear_body(ob, .003)


def enforce_skin_clearance(ob, names, gap, max_push):
    """Resolve local authored-mesh penetrations without reshaping loose panels."""
    me = ob.data
    for vertex in me.vertices:
        if not names(vertex.co):
            continue
        pos, normal, _, distance = _btree.find_nearest(vertex.co)
        if pos is None or distance > max_push:
            continue
        signed = (vertex.co - pos).dot(normal)
        if signed < gap:
            vertex.co += normal * min(gap - signed, max_push)
    me.update()

def lay_on_front(ob, under, direction, clearance):
    """Keep narrow overlay pieces in front of the whole fabric envelope."""
    me = under.data
    tree = BVHTree.FromPolygons([v.co for v in me.vertices], [list(f.vertices) for f in me.polygons])
    into = Vector((0, -direction, 0))
    for vertex in ob.data.vertices:
        p = vertex.co
        depths = [direction * p.y]
        for dx, dz in ((0, 0), (-.002, 0), (.002, 0), (0, -.005), (0, .005)):
            hit, _, _, _ = tree.ray_cast(Vector((p.x + dx, .45 * direction, p.z + dz)), into)
            if hit is not None and hit.y * direction > .04:
                depths.append(hit.y * direction + clearance)
        p.y = direction * max(depths)
    ob.data.update()


def hoodie_lining(tee, hood):
    """Use the fitted crew-neck as the visible lining inside the zip opening."""
    lining = tee.copy()
    lining.data = tee.data.copy()
    lining.name = 'Topx_Hoodie_Undershirt'
    bpy.context.collection.objects.link(lining)
    bm = bmesh.new()
    bm.from_mesh(lining.data)
    for centre, normal in (((0,0,1.19),(0,0,1)),((.162,0,0),(1,0,0)),((-.162,0,0),(1,0,0))):
        bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],
                               plane_co=centre,plane_no=normal)
    outside = [v for v in bm.verts if v.co.z<1.18999 or abs(v.co.x)>.16201]
    if outside:
        bmesh.ops.delete(bm,geom=outside,context='VERTS')
    bm.to_mesh(lining.data)
    bm.free()
    lining.data.update()
    shell = BVHTree.FromPolygons([v.co for v in hood.data.vertices], [list(p.vertices) for p in hood.data.polygons])
    for vertex in lining.data.vertices:
        co = vertex.co
        if (co.y-NECK_Y)*FRONT <= .029:
            continue
        from_front = Vector((co.x,NECK_Y+FRONT*.4,co.z))
        hit, _, _, _ = shell.ray_cast(from_front,Vector((0,-FRONT,0)))
        if hit is not None and (hit.y-NECK_Y)*FRONT > .036:
            co.y = FRONT*min(FRONT*co.y,FRONT*hit.y-.004)
    lining.data.update()
    trim_hoodie_lining(lining, FRONT, NECK_Y)
    lining.data.materials.clear()
    lining.data.materials.append(material('hero_hood_lining',(.105,.110,.120),.87))
    return lining



def trim_hoodie_lining(lining, front, neck_y):
    """Keep the jersey inside the zipper opening, clear of the folded hood."""
    bm = bmesh.new()
    bm.from_mesh(lining.data)

    def inside(co):
        rise = max(0.0,min(1.0,(co.z-1.30)/.23))
        half_width = .044 + .041*rise
        return min(half_width-abs(co.x),(co.y-neck_y)*front-.020)

    iso_cut(bm,inside)
    for vertex in bm.verts:
        co = vertex.co
        side = max(0.0,min(1.0,(abs(co.x)-.047)/.037))
        collar = max(0.0,min(1.0,(co.z-1.36)/.16))
        co.y -= front*.011*side*collar
    bm.to_mesh(lining.data)
    bm.free()
    lining.data.update()


def crisp(ob, angle=55):
    """Smooth shading with sharp edges above `angle` (cloth edges and rims
    read as cut edges, not puffy rounded ones; exported as split normals)."""
    active(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle), keep_sharp_edges=True)


def grid_mesh(name, P, UV, closed=False):
    """A quad grid from rows of points P[i][j] (i across, j along) with UVs."""
    ni_, nj = len(P), len(P[0])
    vs = [p for row in P for p in row]
    fs = []
    fu = []
    uv = [u for row in UV for u in row]
    jj = nj if closed else nj - 1
    for i in range(ni_ - 1):
        for j in range(jj):
            j2 = (j + 1) % nj
            q = [i * nj + j, i * nj + j2, (i + 1) * nj + j2, (i + 1) * nj + j]
            fs.append(q)
            fu.append(q)
    ob = mesh(name, vs, uv, fs, fu)
    return ob


def fourier_smooth(vals, keep=5):
    """Low-pass a periodic sequence (keeps `keep` harmonics)."""
    f = np.fft.rfft(np.asarray(vals, float))
    f[keep + 1:] = 0
    return np.fft.irfft(f, len(vals))


# ------------------------------------------------------------------ textures

def _save(name, arr, color=True):
    h, w = arr.shape[:2]
    img = np.concatenate([arr[:, :, :3], np.ones((h, w, 1), dtype=np.float32)], -1).astype(np.float32)
    im = bpy.data.images.new(name, w, h, alpha=False)
    if not color:
        im.colorspace_settings.name = 'Non-Color'
    im.pixels.foreach_set(img.ravel())
    im.filepath_raw = str(TEX / (name + '.png'))
    im.file_format = 'PNG'
    im.save()
    return TEX / (name + '.png')


def weave_normal(name='fabric_weave_normal', n=256, period=8):
    """One tiling plain/twill weave normal shared by every woven garment
    (tiny relief, read through mip-mapping as a soft fabric tooth)."""
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    u = x / period * math.tau
    v = y / period * math.tau
    # alternating over-under: warp threads where sin(u)>0 cross weft
    h = .5 * np.sin(u) * np.sign(np.sin(v * .5)) + .5 * np.sin(v) * np.sign(np.sin(u * .5))
    rng = np.random.default_rng(11)
    h += rng.normal(0, .18, (n, n)).astype(np.float32)
    h = (h + np.roll(h, 1, 0) + np.roll(h, 1, 1)) / 3
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * .5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * .5
    nrm = np.stack([-gx * .35, -gy * .35, np.ones_like(h)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    return _save(name, nrm * .5 + .5, False)


def pore_normal(name='skin_pore_normal', n=256):
    """Tiling skin micro-relief: fine pores and soft creases (shared by every
    skin surface through the hero shader's detail map)."""
    rng = np.random.default_rng(23)
    h = np.zeros((n, n), np.float32)
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    for _ in range(900):
        cx, cy = rng.random(2) * n
        r = rng.uniform(1.2, 2.4)
        dx = (x - cx + n / 2) % n - n / 2
        dy = (y - cy + n / 2) % n - n / 2
        h -= np.exp(-(dx * dx + dy * dy) / (r * r)) * rng.uniform(.4, 1.0)
    g = rng.normal(0, 1, (n, n)).astype(np.float32)
    for _ in range(3):
        g = (g + np.roll(g, 1, 0) + np.roll(g, -1, 0) + np.roll(g, 1, 1) + np.roll(g, -1, 1)) / 5
    h += g * 1.5
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * .5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * .5
    nrm = np.stack([-gx * .5, -gy * .5, np.ones_like(h)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    return _save(name, nrm * .5 + .5, False)


def raster_uv(ob, size, uv_name=None):
    """Rasterises the mesh into its UV space: per texel the 3D position,
    normal and a valid mask (for baking 3D seam definitions into textures)."""
    me = ob.data
    me.calc_loop_triangles()
    uvl = me.uv_layers[uv_name] if uv_name else me.uv_layers[0]
    P = np.zeros((size, size, 3), np.float32)
    N = np.zeros((size, size, 3), np.float32)
    M = np.zeros((size, size), bool)
    co = np.array([v.co[:] for v in me.vertices], np.float32)
    me_normals = np.array([v.normal[:] for v in me.vertices], np.float32)
    for tri in me.loop_triangles:
        uv = np.array([uvl.data[l].uv[:] for l in tri.loops], np.float32) * size
        vi = list(tri.vertices)
        x0, y0 = np.floor(uv.min(0)).astype(int)
        x1, y1 = np.ceil(uv.max(0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
        px = xs + .5
        py = ys + .5
        (ax, ay), (bx, by), (cx, cy) = uv
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
        l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
        l3 = 1 - l1 - l2
        inside = (l1 >= -.02) & (l2 >= -.02) & (l3 >= -.02)
        if not inside.any():
            continue
        L = np.stack([l1, l2, l3], -1)[inside]
        p = L @ co[vi]
        n = L @ me_normals[vi]
        P[ys[inside], xs[inside]] = p
        N[ys[inside], xs[inside]] = n
        M[ys[inside], xs[inside]] = True
    return P, N, M


def _dilate(a, m, it=12):
    a = a.copy()
    m = m.copy()
    for _ in range(it):
        acc = np.zeros_like(a)
        cnt = np.zeros(m.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sm = np.roll(np.roll(m, dy, 0), dx, 1)
            sa = np.roll(np.roll(a, dy, 0), dx, 1)
            acc += sa * sm[..., None]
            cnt += sm
        grow = (~m) & (cnt > 0)
        a[grow] = acc[grow] / cnt[grow][:, None]
        m = m | grow
    return a


def bake_detail(ob, name, size, height_fn, albedo_fn=None):
    """Bakes a tangent-space normal map (and optionally an albedo) for `ob`
    from a height field defined in 3D (height_fn(P, N) -> metres, arrays).
    The tangent frame follows the UVs (as Godot's mikktspace tangents do)."""
    P, N, M = raster_uv(ob, size)
    H = np.zeros(M.shape, np.float32)
    H[M] = height_fn(P[M], N[M])
    # world size of a texel along u and v, from the position map
    Pd = _dilate(P, M, 3)
    du = np.linalg.norm(np.roll(Pd, -1, 1) - np.roll(Pd, 1, 1), axis=-1) * .5
    dv = np.linalg.norm(np.roll(Pd, -1, 0) - np.roll(Pd, 1, 0), axis=-1) * .5
    du = np.clip(du, 1e-4, .02)
    dv = np.clip(dv, 1e-4, .02)
    Hd = _dilate(H[..., None], M, 3)[..., 0]
    gx = (np.roll(Hd, -1, 1) - np.roll(Hd, 1, 1)) * .5 / du
    gy = (np.roll(Hd, -1, 0) - np.roll(Hd, 1, 0)) * .5 / dv
    nrm = np.stack([-gx, -gy, np.ones_like(H)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    out = _dilate(nrm * .5 + .5, M, 16)
    out[~(_dilate(M[..., None].astype(np.float32), M, 16)[..., 0] > 0)] = (.5, .5, 1)
    npath = _save(name + '_normal', out, False)
    apath = None
    if albedo_fn is not None:
        A = np.ones((size, size, 3), np.float32)
        A[M] = albedo_fn(P[M], N[M], H[M])
        apath = _save(name + '_albedo', _dilate(A, M, 16))
    return npath, apath


def seam_height(dist, along, groove=.0006, width=.0011, stitch_off=.004, stitch_len=.0022, stitch_h=.00012):
    """Height profile of a sewn seam: a soft groove on the seam line, a
    topstitch bead `stitch_off` to each side, dashed every stitch_len."""
    g = -groove * np.exp(-(dist / width) ** 2)
    dash = (np.sin(along / stitch_len * math.pi) > -.2).astype(np.float32)
    s = stitch_h * np.exp(-((np.abs(dist) - stitch_off) / .00045) ** 2) * dash
    # the seam allowance under the cloth lifts it a touch beside the groove
    lift = .00025 * np.exp(-((np.abs(dist) - .006) / .004) ** 2)
    return g + s + lift


def trim_atlas(name='trim'):
    """Shared trim sheet (512^2), rows in v:
      0.00-0.25  band, topstitched both edges (placket, cuff, waistband)
      0.25-0.50  band, single edge stitch (collar leaf, hems)
      0.50-0.75  rib knit (cuffs, collars of knits)
      0.75-1.00  plain cloth (insides, facings)
    Normal + albedo (albedo near white: the garment tint colours it)."""
    n = 512
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    v = y / n
    u = x / n
    H = np.zeros((n, n), np.float32)
    A = np.ones((n, n), np.float32)
    # Each row is 1 unit high in v of 0.25; world height of a row ~ 4 cm
    # (UVs of trims are laid so that the row spans the band's width).
    def row(lo):
        return (v >= lo) & (v < lo + .25), (v - lo) / .25
    m, t = row(0.0)
    along = u * .30  # 30 cm per atlas width
    for e in (.12, .88):
        d = (t - e) * .04
        H[m] += (seam_height(d, along, groove=0, stitch_off=0, stitch_len=.0022, stitch_h=.00014))[m]
    H[m] += (.0004 * np.exp(-((t - .5) / .6) ** 2))[m]  # slight dome
    A[m] *= 1 - .06 * np.exp(-((t - .02) / .03) ** 2)[m] - .06 * np.exp(-((t - .98) / .03) ** 2)[m]
    m, t = row(.25)
    d = (t - .86) * .04
    H[m] += seam_height(d, along, groove=0, stitch_off=0, stitch_len=.0022, stitch_h=.00014)[m]
    m, t = row(.5)
    rib = np.sin(u * math.tau * 60)
    H[m] += (.00019 * rib)[m]
    A[m] *= (1 - .05 * (rib < 0))[m]
    gx = (np.roll(H, -1, 1) - np.roll(H, 1, 1)) * .5 / (.30 / n)
    gy = (np.roll(H, -1, 0) - np.roll(H, 1, 0)) * .5 / (.04 / (n * .25))
    nrm = np.stack([-gx, -gy, np.ones_like(H)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    return _save(name + '_normal', nrm * .5 + .5, False), _save(name + '_albedo', np.repeat(A[..., None], 3, -1))


TRIM_ROWS = {'band2': 0.0, 'band1': .25, 'rib': .5, 'plain': .75}


def trim_uv(ob, row, u_of, t_of):
    """UVs for a trim piece: u along the piece (u_of(co) in metres), t
    across it 0..1 (t_of(co)); mapped into the atlas row."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name='GarmentUV')
    uvl = me.uv_layers[0]
    lo = TRIM_ROWS[row]
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uvl.data[li].uv = (u_of(co) / .30, lo + .25 * max(0.0, min(1.0, t_of(co))) * .98 + .0025)
