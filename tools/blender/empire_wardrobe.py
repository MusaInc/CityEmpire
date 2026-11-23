# City Empire wardrobe: everyday clothes for a business owner, exec'd by
# build_character.py (needs its body/part/push/weights helpers in scope).
# Every garment is cut from the same anatomy as the skin-tight tops (so it
# deforms with the rig exactly), then eased off the body, given a hem that
# hangs over the trouser waistband, and finished with real collars, ribs,
# plackets and buttons. Names: Top_<cut> is the garment the rig shows for a
# cut; Topx_<cut>_<part> are its extra pieces (shown with it).
#   tee · polo · shirt · jumper · hoodie (authored garment) · blazer (with
#   shirt and tie)

wardrobe = []
loose_tops = []
_fm = face_meshes[FACES[0][0]][0]   # (the first face of this body type)
FRONT = 1.0 if sum(v.co.y for v in _fm.data.vertices) / len(_fm.data.vertices) > J['neck'].y else -1.0
HIP = Vector((J['hips'].x, J['hips'].y, 0))
NECK_Y = J['neck'].y

# How far the trousers stand off the skin round the waist: the hems must clear it.
_btree = BVHTree.FromPolygons([RB[j] for j in range(len(RB))], [list(reversed(bf[i])) for i in body])
_gaps = []
for v in pants.data.vertices:
    if .9 < v.co.z < PANTS_TOP:
        hit = _btree.find_nearest(v.co)
        if hit[0] is not None:
            _gaps.append(hit[3])
PANTS_GAP = float(np.percentile(_gaps, 97)) if _gaps else .02
print('PANTS_GAP', round(PANTS_GAP, 4), 'FRONT', FRONT, flush=True)
exec(compile((ROOT / 'tools/blender/garment_kit.py').read_text(), 'garment_kit.py', 'exec'))
WEAVE = weave_normal()
TRIM_N, TRIM_A = trim_atlas()


exec(compile((ROOT / 'tools/blender/lower_wardrobe.py').read_text(), 'lower_wardrobe.py', 'exec'))


def wmat(name, color, rough, tex=None, normal=None):
    return material(name, color, rough, tex, normal)


lapel_mat = wmat('hero_lapel', (.14, .15, .17), .55, knit)
white_mat = wmat('hero_shirt_white', (.86, .87, .88), .6, knit)
tie_mat = wmat('hero_tie', (.05, .07, .16), .4)
button_mat = wmat('hero_button', (.82, .8, .76), .35)
dark_button_mat = wmat('hero_button_dark', (.04, .04, .045), .3)


def body_faces(lim, z_lo, z_hi=1.605, side_x=None):
    out = []
    for i in body:
        ok = True
        for j in bf[i]:
            p = RB[j]
            if p.z < z_lo or p.z > z_hi or wsum(j, 'hand_l', 'hand_r') > .45 or wsum(j, 'thigh_l', 'thigh_r') > .6:
                ok = False
                break
            if armish(j) and arm_t(j) > lim + .22:
                ok = False
                break
        if ok:
            out.append(i)
    return out


def front_of(co):
    return (co.y - NECK_Y) * FRONT


def _bisect(bm, co, no, kill):
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if kill(v.co)], context='VERTS')


NECK_EDGE = {}


def _oval_r(a, rx, rf, rb):
    # Radius of the neckline oval at angle a (0 = front).
    c = math.cos(a)
    return 1.0 / math.sqrt((math.sin(a) / rx) ** 2 + (c / (rf if c > 0 else rb)) ** 2)


def _neck_cut(bm, neck, drop, oval, K=28, cy=None):
    """Cuts the neck opening: an oval round the neck (rx at the sides, rf/rb
    front/back) above the plane through `neck` that dips `drop` towards the
    front. The shoulders outside the oval stay covered (a flat cut through
    the whole garment took the shoulder tops off with it: the trapezius
    stands higher than the neckline). The oval's sides are split first
    (only near the neck), so the opening has a clean edge."""
    rx, rf, rb = oval
    C = Vector((J['neck'].x, NECK_Y if cy is None else cy, 0))
    planes = []
    for k in range(K):
        a = math.tau * k / K
        d = Vector((math.sin(a), FRONT * math.cos(a), 0))
        planes.append((d, _oval_r(a, rx, rf, rb)))
    for d, r in planes:
        near = [f for f in bm.faces if f.calc_center_median().z > neck - .16
                and (Vector((f.calc_center_median().x, f.calc_center_median().y, 0)) - C).length < .2]
        if not near:
            continue
        ev = set()
        for f in near:
            ev.update(f.edges)
            ev.update(f.verts)
        bmesh.ops.bisect_plane(bm, geom=list(ev) + near, plane_co=C + d * r, plane_no=d)
    nrm = Vector((0, FRONT * drop, 1)).normalized()
    top = Vector((0, NECK_Y if cy is None else cy, neck))

    def inside(co):
        h = Vector((co.x, co.y, 0)) - C
        return all(h.dot(d) < r + 1e-5 for d, r in planes) and (co - top).dot(nrm) > 1e-5
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if inside(v.co)], context='VERTS')
    # The opening's edge, as (angle, radius, height) for the rib and collars.
    edge = []
    for v in bm.verts:
        h = Vector((v.co.x, v.co.y, 0)) - C
        if v.is_boundary and v.co.z > neck - .14 and h.length < max(oval) + .02:
            edge.append((math.atan2(h.x, h.y * FRONT) % math.tau, h.length, v.co.z))
    edge.sort()
    return edge


def edge_fn(name, idx):
    """z (idx 2) or radius (idx 1) of garment `name`'s neck opening at angle a,
    interpolated round the edge."""
    e = NECK_EDGE[name]

    def f(a):
        a %= math.tau
        lo = None
        hi = None
        for x in e:
            if x[0] <= a:
                lo = x
            elif hi is None:
                hi = x
        lo = lo or (e[-1][0] - math.tau,) + e[-1][1:]
        hi = hi or (e[0][0] + math.tau,) + e[0][1:]
        t = (a - lo[0]) / max(hi[0] - lo[0], 1e-6)
        return lo[idx] + (hi[idx] - lo[idx]) * t
    return f


def shell(name, lim, off, hem, neck=1.548, neck_drop=.5, arm_off=None, waist=None, subdivide=False, oval=(.088, .085, .075)):
    """A loose top cut from the body: `off` m off the skin (arms `arm_off`),
    eased round the waist to clear the trousers, cut level at `hem`, a crew
    neckline at `neck` (lower at the front by `neck_drop` × depth), and the
    sleeves cut square at `lim` (arm_t)."""
    ob, _ = part(name, body_faces(lim, hem - .05), RB, weights)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    if subdivide:
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
    bm.normal_update()
    waist = PANTS_GAP + .007 if waist is None else waist
    for v in bm.verts:
        d = off
        if any(True for _ in ()):
            pass
        horiz = Vector((v.co.x, v.co.y, 0)) - HIP
        in_arm = abs(v.co.x) > .2 and v.co.z > 1.15
        if in_arm and arm_off is not None:
            d = arm_off
        if v.co.z < 1.1 and not in_arm:
            k = max(0.0, min(1.0, (1.1 - v.co.z) / .14))
            d = max(d, off + (waist - off) * k)
        v.co += v.normal * d
    # Neckline (an oval round the neck, lower at the front), hem, sleeves.
    NECK_EDGE[name] = _neck_cut(bm, neck, neck_drop, oval)
    _bisect(bm, (0, 0, hem), (0, 0, 1), lambda co: co.z < hem - 1e-5)
    if lim < 9:
        for side, sx in [('l', -1), ('r', 1)]:
            a = J['upper_arm_' + side]
            e = J['forearm_' + side]
            h = J['hand_' + side]
            if lim <= 1.0:
                pt = a + (e - a) * lim
                ax = (e - a).normalized()
            else:
                pt = e + (h - e) * (lim - 1.0)
                ax = (h - e).normalized()

            def beyond(co, pt=pt, ax=ax, a=a):
                along = (co - pt).dot(ax)
                off_ = (co - a) - ax * (co - a).dot(ax)
                return along > 1e-5 and off_.length < .09
            _bisect(bm, tuple(pt), tuple(ax), beyond)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return ob


def boundary_loop_verts(bm, pred):
    return [v for v in bm.verts if v.is_boundary and pred(v.co)]


def skirt(ob, hem, rows):
    """Extends the level hem straight down in `rows` [(drop, flare)], each
    row pushed out from the hips by `flare` (a hem that hangs, not a band
    shrink-wrapped to the waist)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    edges = [e for e in bm.edges if e.is_boundary and all(abs(v.co.z - hem) < 2e-4 for v in e.verts)]
    for drop, flare in rows:
        res = bmesh.ops.extrude_edge_only(bm, edges=edges)
        nv = [g for g in res['geom'] if isinstance(g, bmesh.types.BMVert)]
        for v in nv:
            h = Vector((v.co.x, v.co.y, 0)) - HIP
            out = h.normalized() if h.length > 1e-4 else Vector((0, 0, 0))
            v.co += Vector((0, 0, -drop)) + out * flare
        edges = [g for g in res['geom'] if isinstance(g, bmesh.types.BMEdge) and all(v in nv for v in g.verts)]
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return ob


def finish(ob, mats, assign=None, rim=.003):
    for m in mats:
        ob.data.materials.append(m)
    if assign:
        for poly in ob.data.polygons:
            poly.material_index = assign(poly.center)
    so = ob.modifiers.new('Hem', 'SOLIDIFY')
    so.thickness = rim
    so.offset = -1
    so.use_rim_only = True
    apply(ob, so)
    # Weights for the new (extruded) rows: copy from the nearest original vertex.
    return ob


def reweight(ob):
    """Extruded hem rows and offset pieces need skin weights: each vertex takes
    the weights of the nearest body vertex (the hem follows hips and thighs
    like the top above it)."""
    kd_ids = list(range(len(RB)))
    from mathutils.kdtree import KDTree
    kd = KDTree(len(RB))
    for j in kd_ids:
        kd.insert(RB[j], j)
    kd.balance()
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    groups = {n: ob.vertex_groups.new(name='b_' + n) for n in ni}
    for v in ob.data.vertices:
        acc = np.zeros(len(names))
        tot = 0.0
        for co, j, d in kd.find_n(v.co, 4):
            w = 1.0 / max(d, .004)
            acc += weights[j] * w
            tot += w
        acc /= max(tot, 1e-8)
        # The hem below the waist moves with the hips, not one thigh.
        if v.co.z < .97 and abs(v.co.x) < .26:
            th = acc[ni['thigh_l']] + acc[ni['thigh_r']]
            acc[ni['hips']] += th * .55
            acc[ni['thigh_l']] *= .45
            acc[ni['thigh_r']] *= .45
        for n, i in ni.items():
            if acc[i] > .002:
                groups[n].add([v.index], float(acc[i]), 'REPLACE')


def neck_ring(name, mat, z_of, h, out0, out1, lean=0.0, gap=0.0, rows=3, drop_front=0.0, ring=40, target=None, r_of=None):
    """A band round the neckline: for each angle, from the neckline height
    z_of(angle) up `h` (negative: folds down), standing out0..out1 off the
    surface below (the garment `target`, or the skin). `gap` leaves the
    front open (radians each side)."""
    tree = target
    if tree is None:
        nfaces = [i for i in body if all(1.38 < RB[j].z < 1.7 for j in bf[i])]
        tree = BVHTree.FromPolygons([RB[j] for j in range(len(RB))], [list(reversed(bf[i])) for i in nfaces])
    nc = J['neck']
    angs = []
    for k in range(ring + 1 if gap > 0 else ring):
        a = (gap + (math.tau - 2 * gap) * k / ring) if gap > 0 else math.tau * k / ring
        angs.append(a)
    vs = []
    for a in angs:
        # Angle 0 is the front.
        d = Vector((math.sin(a), FRONT * math.cos(a), 0))
        fr = max(0.0, math.cos(a))
        z0 = z_of(a)
        for r in range(rows):
            t = r / (rows - 1)
            z = z0 + h * t - drop_front * fr * (1 - t if h < 0 else 0)
            if r_of is not None:
                # On the garment's own neck edge (z_of/r_of = edge_fn).
                q = Vector((nc.x, nc.y, z)) + d * r_of(a)
            else:
                o = Vector((nc.x, nc.y, z)) + d * .35
                hit = tree.ray_cast(o, -d)
                q = hit[0] if hit[0] is not None else Vector((nc.x, nc.y, z)) + d * .07
            vs.append(q + d * (out0 + (out1 - out0) * t) - d * lean * t)
    fs = []
    n = len(angs)
    for k in range(n - (1 if gap > 0 else 0)):
        k2 = (k + 1) % n
        for r in range(rows - 1):
            a_ = k * rows + r
            b_ = k2 * rows + r
            fs.append([a_, b_, b_ + 1, a_ + 1] if h > 0 else [a_ + 1, b_ + 1, b_, a_])
    ob = mesh(name, vs, [], fs, [])
    ob.data.materials.append(mat)
    so = ob.modifiers.new('Band', 'SOLIDIFY')
    so.thickness = .003
    so.offset = -1
    apply(ob, so)
    reweight(ob)
    return ob


def buttons(name, mat, target, zs, out=.004, r=.0065, x=0.0):
    vs = []
    fs = []
    for z in zs:
        o = Vector((x, NECK_Y + FRONT * .4, z))
        hit = target.ray_cast(o, Vector((0, -FRONT, 0)))
        c = hit[0] if hit[0] is not None else Vector((x, NECK_Y + FRONT * .1, z))
        c = c + Vector((0, FRONT * out, 0))
        base = len(vs)
        for k in range(8):
            a = math.tau * k / 8
            vs.append(c + Vector((math.cos(a) * r, 0, math.sin(a) * r)))
        vs.append(c + Vector((0, FRONT * .002, 0)))
        for k in range(8):
            fs.append([base + k, base + (k + 1) % 8, base + 8] if FRONT < 0 else [base + 8, base + (k + 1) % 8, base + k])
    ob = mesh(name, vs, [], fs, [])
    ob.data.materials.append(mat)
    reweight(ob)
    return ob


def tree_of(ob):
    return BVHTree.FromPolygons([v.co for v in ob.data.vertices], [list(p.vertices) for p in ob.data.polygons])


def neckline(neck, drop):
    # Height of the cut neckline at angle a (0 = front), matching shell().
    def z(a):
        fr = max(0.0, math.cos(a))
        return neck - drop * .065 * fr - .004
    return z


def add(ob, loose=True):
    wardrobe.append(ob)
    if loose:
        loose_tops.append(ob)
    return ob


# ---------------------------------------------------------------- shirt (tailored, long sleeve, worn untucked)
def tailored_top(name, hem, neck, neck_drop, oval, layer, sleeve_end=None, cuff=None, neck_cy=None, lim=9.0, neck_curve=None, **kw):
    """A top cut from the body, subdivided once, FITTED by the garment kit
    (hull + ease, hanging; sleeves as tubes), then cut: neckline oval, level
    hem (the shirttail extends it), sleeve ends square to the arm."""
    ob, _ = part(name, body_faces(lim, hem - .05), RB, weights)
    m = ob.modifiers.new('Fine', 'SUBSURF')
    m.levels = 1
    m.uv_smooth = 'PRESERVE_BOUNDARIES'
    apply(ob, m)
    tailor(ob, layer, cuff=cuff, **kw)
    drape_top(ob, {'shirt': .0025, 'knit': .0042, 'jacket': .0028, 'skin': .0008}[layer], hem)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    if neck_curve is None:
        NECK_EDGE[name] = _neck_cut(bm, neck, neck_drop, oval, cy=neck_cy)
    else:
        # a smooth neckline: keep everything below the curve Z(angle) round the neck
        def _nf(co):
            dx, dy = co.x - J['neck'].x, (co.y - NECK_CY) * FRONT
            if math.hypot(dx, dy) > .16 or co.z < 1.4:
                return 1.0
            return neck_curve(math.atan2(dx, dy) % math.tau) - co.z
        iso_cut(bm, _nf)
    _bisect(bm, (0, 0, hem), (0, 0, 1), lambda co: co.z < hem - 1e-5)
    if sleeve_end is not None:
        for side in ('l', 'r'):
            af = frames()[1][side]
            pt = af.a + af.ax * (sleeve_end * af.L)

            def beyond(co, pt=pt, ax=af.ax, a=af.a):
                along = (co - pt).dot(ax)
                off = (co - a) - ax * (co - a).dot(ax)
                return along > 1e-5 and off.length < .11
            _bisect(bm, tuple(pt), tuple(af.ax), beyond)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return ob


def weights_below(ob, hem):
    """Weights for the shirttail rows: the hem vertex above each one, the
    thighs' share moved onto the hips (the tail swings with the pelvis)."""
    vs = ob.data.vertices
    kd = KDTree(len(vs))
    top = [v for v in vs if v.co.z >= hem - 1e-4]
    for v in top:
        kd.insert(Vector((v.co.x, v.co.y, 0)), v.index)
    kd.balance()
    gi = {g.index: g for g in ob.vertex_groups}
    hips = ob.vertex_groups['b_hips']
    for v in vs:
        if v.co.z >= hem - 1e-4:
            continue
        _, src, _ = kd.find(Vector((v.co.x, v.co.y, 0)))
        w = {gi[g.group].name: g.weight for g in vs[src].groups}
        th = w.get('b_thigh_l', 0) + w.get('b_thigh_r', 0)
        for g in list(v.groups):
            gi[g.group].remove([v.index])
        w['b_hips'] = w.get('b_hips', 0) + th * .6
        for k in ('b_thigh_l', 'b_thigh_r'):
            if k in w:
                w[k] *= .4
        for k, x in w.items():
            if x > .002:
                ob.vertex_groups[k].add([v.index], x, 'REPLACE')


# The neck, measured. In this retarget the neck proper starts at ~1.60 m
# (below that is the trapezius slope); its axis sits midway between the
# throat and the nape (the chin and the shoulders pulled earlier estimates
# off). The collar stand is a near-cylinder round it with a finger's ease,
# and the shirt's neck opening is snapped onto the stand's base.
_nk_faces = [i for i in body if all(1.45 < RB[j].z < 1.72 for j in bf[i])]
_nk_tree = BVHTree.FromPolygons([RB[j] for j in range(len(RB))], [list(reversed(bf[i])) for i in _nk_faces])
_nk_ids = sorted({j for i in _nk_faces for j in bf[i]})
_ys = [RB[j].y for j in _nk_ids if abs(RB[j].x) < .02 and 1.585 < RB[j].z < 1.615 and wsum(j, 'head') < .5]
if len(_ys) < 2:   # (body type b: a slimmer, shorter neck - widen the band)
    _ys = [RB[j].y for j in _nk_ids if abs(RB[j].x) < .03 and 1.56 < RB[j].z < 1.64 and wsum(j, 'head') < .8]
NECK_CY = (max(_ys) + min(_ys)) / 2
if BODY == 'b':
    # Measure both sides of the actual neck at matching heights. Pooling
    # source vertices mixed the seam behind the shoulder with the throat.
    _neck_centres = []
    for _height in (1.567, 1.578, 1.589, 1.600):
        _front = _nk_tree.ray_cast(Vector((0,.26,_height)), Vector((0,-1,0)), .44)[0]
        _back = _nk_tree.ray_cast(Vector((0,-.20,_height)), Vector((0,1,0)), .44)[0]
        if _front is not None and _back is not None and .05 < _front.y - _back.y < .145:
            _neck_centres.append((_front.y + _back.y) * .5)
    if _neck_centres:
        NECK_CY = float(np.median(_neck_centres))
_NK_A = [math.tau * k / 72 for k in range(72)]


def _neck_ray(a, z):
    d = Vector((math.sin(a), FRONT * math.cos(a), 0))
    c = Vector((J['neck'].x, NECK_CY, z))
    hit = _nk_tree.ray_cast(c, d, .15)
    return (hit[0] - c).length if hit[0] is not None else .06


def _periodic(vals):
    v = list(vals)
    return lambda a: float(np.interp(a % math.tau, _NK_A + [math.tau], v + [v[0]]))


# stand radius: the neck at 1.62 (above the trapezius flare), smoothed
# Sides/back: the neck at 1.62 (lower, the trapezius flares and the collar
# would stand wide). Front: the throat over the stand's own height (1.565 to
# 1.60), which is fuller than at 1.62 - else the throat shows through.
COLLAR_LEVEL = -.051 if BODY == 'b' else 0.0
_nr = []
for a in _NK_A:
    fw = max(0.0, math.cos(a)) ** 2
    r_hi = _neck_ray(a, 1.62 + COLLAR_LEVEL)
    r_th = max(_neck_ray(a, z + COLLAR_LEVEL) for z in (1.565, 1.575, 1.585, 1.595, 1.605))
    _nr.append(r_hi + (max(r_hi, r_th) - r_hi) * fw)
_nr = [(_nr[k] + _nr[-k]) / 2 for k in range(72)]          # mirror-symmetric (left = right)
STAND_R = _periodic(fourier_smooth([r + .0065 + .0025 * max(0.0, math.cos(a)) ** 2 for r, a in zip(_nr, _NK_A)], 3))
STAND_Z0 = _periodic([1.598 + COLLAR_LEVEL - .03 * max(0.0, math.cos(a)) ** 1.5 for a in _NK_A])   # base: lower at the throat
STAND_H = _periodic([.026 - .003 * max(0.0, math.cos(a)) for a in _NK_A])
neck_r = lambda a, z: STAND_R(a) - .0065
COLLAR_EASE = (.0065, .0045)
SHIRT_NECK = 1.595 + COLLAR_LEVEL
SHIRT_OVAL = (STAND_R(math.pi / 2), STAND_R(0), STAND_R(math.pi))
SHIRT_NECK_DROP = .03 / STAND_R(0)
print('NECK centre y', round(NECK_CY, 4), 'stand radii side/front/back', [round(x, 4) for x in SHIRT_OVAL], flush=True)


def snap_neckline(ob, reach=.03, R=None, Z0=None):
    """Moves the garment's neck opening exactly onto the collar stand's base
    ring (and eases the cloth round it), so the stand is sewn on: no gap,
    no overlap."""
    me = ob.data
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    edge = [v for v in bm.verts if v.is_boundary and v.co.z > 1.5 and abs(v.co.y - NECK_CY) < .12 and abs(v.co.x) < .12]
    disp = {}
    for v in edge:
        a = math.atan2(v.co.x - J['neck'].x, (v.co.y - NECK_CY) * FRONT) % math.tau
        SR, SZ0 = R or STAND_R, Z0 or STAND_Z0
        tgt = Vector((J['neck'].x + math.sin(a) * SR(a), NECK_CY + FRONT * math.cos(a) * SR(a), SZ0(a)))
        disp[v.index] = tgt - v.co
    bm.free()
    kd = KDTree(len(disp))
    for i in disp:
        kd.insert(me.vertices[i].co, i)
    kd.balance()
    for v in me.vertices:
        if v.index in disp:
            v.co += disp[v.index]
            continue
        co, i, d = kd.find(v.co)
        if d < reach:
            k = (1 - d / reach) ** 2
            v.co += disp[i] * k
    me.update()


# Tucked in: the shirt ends 5.5 cm inside the trousers' waistband.
SHIRT_HEM = PANTS_TOP - .03   # tucked: ends 3 cm inside the waistband (behind the band)
SHIRT_SLEEVE_END, CUFF_T0, CUFF_T1 = .905, .895, 1.005   # ArmFrame t: 0 shoulder pivot, 1 wrist joint
CUFF_CLEAR = .011
TAIL_CENTRE, TAIL_SIDE = 0.0, 0.0   # tucked (garment_kit.shirttail makes an untucked tail)
WAIST_TOP = PANTS_TOP                # the trousers' waistband top (build_character cuts it level)


def cuff_radius(side, a):
    af = frames()[1][side]
    ti = int(np.searchsorted(af.ts, .965))
    row = _smooth(af.hull[ti].copy(), 6, 0, wrap=True)
    k = a / math.tau * af.NA
    i = int(k) % af.NA
    t = k - int(k)
    return float(row[i] * (1 - t) + row[(i + 1) % af.NA] * t) + CUFF_CLEAR


def _arm_of(co):
    side = 'l' if co.x < 0 else 'r'
    af = frames()[1][side]
    return af, af.polar(co)


def _shirt_folds():
    L = frames()[1]['r'].L

    def elbow_m(co):
        if abs(co.x) < .17:
            return 0.0
        af, (t, a, r) = _arm_of(co)
        return math.exp(-((t - .52) / .07) ** 2) * max(0.0, math.cos(a)) ** 2

    def elbow_w(co):
        _, (t, a, _) = _arm_of(co)
        centre = .52-.037*math.sin(2*a)
        return math.exp(-((t-centre)/.026)**2)-.50*math.exp(-((t-centre-.035)/.024)**2)

    def stack_m(co):
        if abs(co.x) < .17:
            return 0.0
        af, (t, a, r) = _arm_of(co)
        return max(0.0, min(1.0, (t - .70) / .08)) * max(0.0, min(1.0, (.905 - t) / .03))

    def stack_w(co):
        af, (t, a, r) = _arm_of(co)
        mid = .825+.026*math.sin(2*a+1)
        return math.exp(-((t-mid)/.029)**2) - .38*math.exp(-((t-mid-.036)/.018)**2)

    def drape_m(co):
        if abs(co.x) > .2 or co.z > 1.24:
            return 0.0
        _, cy, a, _ = frames()[0].polar(co)
        return min(1.0, (1.24 - co.z) / .2) * (.5 + .5 * abs(math.sin(a)))

    def drape_w(co):
        _, cy, a, _ = frames()[0].polar(co)
        return math.sin(a * 11 + co.z * 4) * .7 + .3 * math.sin(a * 23 - co.z * 9)
    def blouse_m(co):
        if abs(co.x) > .2:
            return 0.0
        return max(0.0, 1 - abs(co.z - (WAIST_TOP + .025)) / .03)

    def blouse_w(co):
        _, cy, a, _ = frames()[0].polar(co)
        return .5 + .5 * math.sin(a * 14 + math.sin(a * 5) * 1.5)
    def pit_m(co):
        # radiating folds from the armpit across the side-front and side-back
        sx = 1 if co.x > 0 else -1
        p = Vector((sx * .165, NECK_CY, 1.37))
        d = (co - p)
        r = d.length
        if r > .12 or abs(co.x) > .2:
            return 0.0
        return max(0.0, 1 - r / .12) * min(1.0, r / .025)

    def pit_w(co):
        sx = 1 if co.x > 0 else -1
        d = co - Vector((sx * .165, NECK_CY, 1.37))
        ang = math.atan2(d.z, d.y * FRONT)
        return math.sin(ang * 6 + d.length * 40)

    def shoulder_m(co):
        if co.z < 1.43 or abs(co.x) < .07 or abs(co.x) > .2:
            return 0.0
        return min(1.0, (co.z - 1.43) / .04) * min(1.0, (abs(co.x) - .07) / .04)

    def shoulder_w(co):
        return math.sin(abs(co.x) * 70 + (co.y - NECK_CY) * 55)

    def chest_m(co):
        if co.z < 1.2 or co.z > 1.45 or abs(co.x) > .17 or (co.y - NECK_CY) * FRONT < 0 or abs(co.x) < .025:
            return 0.0
        return math.sin(math.pi * (co.z - 1.2) / .25) * .7

    def chest_w(co):
        fold = co.z-(1.303+.47*(abs(co.x)-.09))
        return math.exp(-(fold/.025)**2)-.43*math.exp(-((fold-.025)/.023)**2)
    return [(elbow_m, elbow_w, .0022), (stack_m, stack_w, .0018), (drape_m, drape_w, .0012), (blouse_m, blouse_w, .003),
            (pit_m, pit_w, .003), (shoulder_m, shoulder_w, .0014), (chest_m, chest_w, .0013)]


def shirt_height(P, N):
    """Seams, topstitching and fine folds of the shirt, in 3D (metres)."""
    tf, afs = frames()
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    cy = np.interp(z, tf.zs, tf.cy)
    fy = (y - cy) * FRONT
    ang = np.arctan2(x, fy)
    H = np.zeros(len(P), np.float32)
    # arm coordinates (both sides at once)
    t = np.zeros(len(P))
    ar = np.zeros(len(P))
    aa = np.zeros(len(P))
    for side, sx in (('l', -1), ('r', 1)):
        af = afs[side]
        m = x * sx > 0
        r = P[m] - np.array(af.a)
        tt = r @ np.array(af.ax) / af.L
        px = r @ np.array(af.w)
        py = r @ np.array(af.u)
        t[m] = tt
        ar[m] = np.hypot(px, py)
        aa[m] = np.arctan2(px, py)
    on_arm = (np.abs(x) > .175) & (t > .02) & (ar < .1)
    L = afs['r'].L
    torso = ~on_arm
    # side seams (front/back panels), under the arm down to the hem
    d = fy * 1.0
    m = torso & (np.abs(x) > .1) & (z < 1.37)
    H[m] += seam_height(d[m], z[m])
    # shoulder seams: just behind the top of the shoulder
    cys = float(np.interp(1.5, tf.zs, tf.cy))
    m = torso & (z > 1.40) & (np.abs(x) > .06)
    H[m] += seam_height(((y - cys) * FRONT + .012)[m], x[m])
    # armholes (set-in sleeves): a near-vertical plane through the shoulder
    # tip down to the armpit (not square to the bind-pose arm, which is 42
    # degrees out: that drew the seam across the chest)
    for sx in (-1, 1):
        nx, nz = sx / math.hypot(1, .2), .2 / math.hypot(1, .2)
        d = (x - sx * .186) * nx + (z - 1.45) * nz
        m = (x * sx > .12) & (z > 1.28) & (np.abs(d) < .02)
        H[m] += seam_height(d[m], (z + fy)[m])
    # underarm sleeve seams, carrying on from the side seams
    for side, sx in (('l', -1), ('r', 1)):
        af = afs[side]
        dn = Vector((0, 0, -1)) - af.ax * Vector((0, 0, -1)).dot(af.ax)
        a0 = math.atan2(dn.dot(af.w), dn.dot(af.u))
        m = on_arm & (x * sx > 0) & (t > .06)
        da = (aa[m] - a0 + math.pi) % math.tau - math.pi
        H[m] += seam_height(da * ar[m], t[m] * L, stitch_off=.0)
    # back yoke (curved across the shoulder blades) and two back darts
    yoke = 1.405 + .25 * x ** 2
    m = torso & (fy < 0) & (np.abs(x) < .19) & (z > 1.3)
    H[m] += seam_height((z - yoke)[m], x[m])
    for dx in (-.085, .085):
        m = torso & (fy < 0) & (z < 1.26) & (z > .97)
        k = np.clip(1 - np.abs(z - 1.11) / .15, 0, 1)
        H[m] += (seam_height((x - dx)[m], z[m], stitch_off=0, stitch_h=0) * k[m])
    # hem: turned and topstitched 1.1 cm above the shirttail edge
    side = np.abs(np.sin(ang)) ** 1.5
    hem_z = SHIRT_HEM - (TAIL_CENTRE + (TAIL_SIDE - TAIL_CENTRE) * side)
    m = torso & (z < hem_z + .03)
    H[m] += seam_height((z - hem_z - .011)[m], ang[m] * .15, groove=.0, stitch_off=0)
    H[m] += (.0004 * np.clip(1 - (z - hem_z) / .011, 0, 1))[m]   # the turned double layer
    # fine folds: compression at the inner elbow, sleeve stacking, drape
    elbow = np.exp(-((t - .52) / .08) ** 2) * np.clip(np.cos(aa), 0, 1) * on_arm
    H += (.0006 * elbow * np.sin(t * L / .009 * math.pi + np.sin(aa * 3))).astype(np.float32)
    stack = np.clip((t - .72) / .1, 0, 1) * on_arm
    H += (.0005 * stack * np.sin(t * L / .011 * math.pi + aa * 2)).astype(np.float32)
    H += (.0004 * (z < 1.2) * torso * np.sin(ang * 31 + z * 23) * np.sin(z * 7 + ang)).astype(np.float32)
    for sx in (-1, 1):   # armpit drag lines
        d = P - np.array([sx * .165, NECK_CY, 1.37])
        r = np.linalg.norm(d, axis=1)
        m = (r < .14) & (x * sx > 0)
        H += (.0006 * m * np.clip(1 - r / .14, 0, 1) * np.sin(np.arctan2(d[:, 2], d[:, 1] * FRONT) * 9 + r * 70)).astype(np.float32)
    return H


def shirt_albedo(P, N, H):
    value = .94 + 37*np.clip(H,-.003,.0015) + .54*textile_grain('shorts',P,N)
    return np.repeat(np.clip(value, .76, .995)[:,None],3,1).astype(np.float32)


shirt = tailored_top('Top_Shirt', SHIRT_HEM, SHIRT_NECK, SHIRT_NECK_DROP, SHIRT_OVAL, 'shirt', sleeve_end=SHIRT_SLEEVE_END, neck_cy=NECK_CY,
                     cuff=(.80, SHIRT_SLEEVE_END, cuff_radius), taper_front=.10, taper_side=.32,
                     sleeve_ease=(.007, .008), sleeve_taper=.19, shoulder_ease=.0015)
snap_neckline(shirt)
# Worn with the top button undone: a V from the stand's ends down to the first
# fastened button (the closed collar is kept for the shirt under a tie).
OPEN_HALF = .026                     # half the opening at the collar's base
ZV = STAND_Z0(0) - .066              # the V's point: the first fastened button


def open_front(ob):
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    Hh = STAND_Z0(0) - ZV
    for sx in (-1, 1):
        nrm = Vector((sx * Hh, 0, -OPEN_HALF)).normalized()
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, ZV), plane_no=nrm)
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        if (c.y - NECK_CY) * FRONT > 0 and c.z > ZV and abs(c.x) < OPEN_HALF * (c.z - ZV) / Hh and c.z < STAND_Z0(0) + .03:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


# The same shirt, closed, for wearing under the jacket with a tie (trimmed to
# the front panel in the blazer section).
if BODY == 'a':
    shirt_closed = shirt.copy()
    shirt_closed.data = shirt.data.copy()
    bpy.context.collection.objects.link(shirt_closed)
open_front(shirt)
print('SHIRT tucked: pulled in', tuck_into(shirt, pants, WAIST_TOP, .007), flush=True)
follow_layer(shirt, pants, WAIST_TOP + .02, .04, k_max=1.0)
fold_relief(shirt, _shirt_folds())
SHIRT_UV_M = pack_uvs(shirt)
print('SHIRT uv metres/unit', round(SHIRT_UV_M, 3), flush=True)
_sn, _sa = bake_detail(shirt, 'shirt_body', 2048, shirt_height, shirt_albedo)
shirt_mat = material('hero_shirt', (.16, .17, .19), .74, _sa, _sn)
shirt_mat.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = 1.0
finish(shirt, [shirt_mat], rim=.0018)
add(shirt)
trim_mat = material('hero_shirt_trim', (.16, .17, .19), .72, TRIM_A, TRIM_N)
trim_mat.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = 1.0
hole_mat = wmat('hero_buttonhole', (.12, .125, .14), .8)


# ---- shirt construction: collar (stand + rolled leaf with points), placket,
# buttons and buttonholes, cuffs. Parametric curves fitted to the shirt's own
# neckline and arms, low-passed (the old collar was ray-cast onto the neck
# and came out as a zig-zag). All pieces UV into the shared trim atlas.
def _neck_curves(name, n=72):
    e = NECK_EDGE[name]
    zf, rf = edge_fn(name, 2), edge_fn(name, 1)
    angs = [math.tau * k / n for k in range(n)]
    z = fourier_smooth([zf(a) for a in angs], 4)
    r = fourier_smooth([rf(a) for a in angs], 4)
    zi = lambda a: float(np.interp(a % math.tau, angs + [math.tau], list(z) + [z[0]]))
    ri = lambda a: float(np.interp(a % math.tau, angs + [math.tau], list(r) + [r[0]]))
    return zi, ri


def _ring_pt(a, r, z):
    nc = J['neck']
    return Vector((nc.x + math.sin(a) * r, NECK_CY + FRONT * math.cos(a) * r, z))


def shirt_collar(name, gap=.05, leaf_w=(.040, .066), spread=.34, mat=None, garment=None, R=None, Z0=None, H=None, closed=True, button=True):
    """Two-piece shirt collar on the measured neck: a near-cylindrical stand
    (ends meeting at the throat over a collar button) and a leaf that rolls
    over the stand and lies on the shirt, with spread points. Every row is
    low-passed along the collar so the edges are clean lines."""
    st = tree_of(garment or shirt)
    SR, SZ0, SH = R or STAND_R, Z0 or STAND_Z0, H or STAND_H
    nA = 72
    angs = [gap + (math.tau - 2 * gap) * k / nA for k in range(nA + 1)]
    pt = lambda a, r, z: Vector((J['neck'].x + math.sin(a) * r, NECK_CY + FRONT * math.cos(a) * r, z))
    arc = [0.0]
    for k in range(1, len(angs)):
        arc.append(arc[-1] + (pt(angs[k], SR(angs[k]), 0) - pt(angs[k - 1], SR(angs[k - 1]), 0)).length)

    def smooth_row(row, it=12):
        xs = np.array([[p.x, p.y, p.z] for p in row])
        for _ in range(it):
            xs[1:-1] = (xs[:-2] + 2 * xs[1:-1] + xs[2:]) / 4
        return [Vector(x) for x in xs]
    SP, SU = [], []
    rows = 4
    # The stand wraps fully round and overlaps itself by ~1 cm at the throat
    # (the button tab lies 2.2 mm outside the under-lap): no gap at the front.
    sang = [-.1 + (math.tau + .2) * k / (nA + 8) for k in range(nA + 9)] if closed else list(angs)
    sarc = [0.0]
    for k in range(1, len(sang)):
        sarc.append(sarc[-1] + (pt(sang[k], SR(sang[k]), 0) - pt(sang[k - 1], SR(sang[k - 1]), 0)).length)
    for i in range(rows):
        t = i / (rows - 1)
        row, urow = [], []
        for k, a in enumerate(sang):
            lap = max(0.0, min(1.0, (a - (math.tau - .1)) / .05)) if closed else 0.0   # the over-lapping end
            z = SZ0(a) + SH(a) * t
            lean = .003 * (1 - max(0.0, math.cos(a)) ** 2)            # leans into the neck at the sides/back only
            row.append(pt(a, SR(a) - lean * t + .0022 * lap, z))
            urow.append((sarc[k] / .30, TRIM_ROWS['band1'] + .25 * (.06 + .88 * t)))
        SP.append(row)
        SU.append(urow)
    stand = grid_mesh(name.replace('Top_', 'Topx_') + '_Stand', SP, SU)
    face_out(stand, lambda c: Vector((c.x - J['neck'].x, c.y - NECK_CY, 0)))
    LP, LU = [], []
    prow = 8
    shirt_r = lambda a, z: (lambda h: (Vector((h.x - J['neck'].x, h.y - NECK_CY, 0)).length if h is not None else None))(
        st.ray_cast(Vector((J['neck'].x, NECK_CY, z)) + Vector((math.sin(a), FRONT * math.cos(a), 0)) * .3,
                    -Vector((math.sin(a), FRONT * math.cos(a), 0)))[0])
    # The leaf's outer edge: the point ON THE SHIRT a fixed cloth width w from
    # the roll line (3.8 cm round the back, 6.2 cm at the points), searched
    # down the shirt at the edge's angle. (A fixed drop in height put the edge
    # out on the shoulders, where the shirt slopes gently: club-like lobes.)
    edge = []
    for k, a in enumerate(angs):
        fr = max(0.0, math.cos(a))
        f = max(0.0, min(1.0, (fr - .55) / .45))
        f = f * f * (3 - 2 * f)
        w = leaf_w[0] + (leaf_w[1] - leaf_w[0]) * f
        side = 1 if math.sin(a) > 0 else -1
        a_e = a + side * spread * f
        top = SZ0(a) + SH(a)
        roll = pt(a, SR(a) - .003 + .0054, top + .0005)
        best = None
        z = top
        while z > top - .1:
            r = shirt_r(a_e, z)
            if r is not None:
                q = pt(a_e, r, z)
                if (q - roll).length >= w:
                    best = (a_e, r + .0032, z)
                    break
                best = (a_e, r + .0032, z)
            z -= .0015
        edge.append(best)
    er = np.array([e[1] for e in edge])
    ez = np.array([e[2] for e in edge])
    for _ in range(6):
        er[1:-1] = (er[:-2] + 2 * er[1:-1] + er[2:]) / 4
        ez[1:-1] = (ez[:-2] + 2 * ez[1:-1] + ez[2:]) / 4
    er = (er + er[::-1]) / 2       # angs are symmetric about the back: mirror left/right exactly
    ez = (ez + ez[::-1]) / 2
    for i in range(prow):
        s_ = i / (prow - 1)
        row, urow = [], []
        for k, a in enumerate(angs):
            top = SZ0(a) + SH(a)
            r0 = SR(a) - .003 + .0024
            a_e, re_, ze = edge[k][0], float(er[k]), float(ez[k])
            if s_ < .2:          # the roll over the stand's top edge (radius ~3 mm)
                u = s_ / .2
                q = (a, r0 + .003 * math.sin(u * math.pi / 2), top + .0028 * math.sin(u * math.pi))
            else:                # then the fall, lying 3 mm off the shirt
                u = (s_ - .2) / .8
                e = max(0.0, 1 - min(k, nA - k) / 1.5)
                u *= 1 - .05 * e * max(0.0, (u - .7) / .3) ** 2   # just take the point's corner off
                q0 = (a, r0 + .003, top + .0005)
                q = (q0[0] + (a_e - q0[0]) * u, q0[1] + (re_ - q0[1]) * u, q0[2] + (ze - q0[2]) * u)
            row.append(pt(*q))
            urow.append((arc[k] / .30, TRIM_ROWS['band1'] + .25 * (.04 + .9 * s_)))
        LP.append(row)
        LU.append(urow)
    # Keep the fall 3 mm off the shirt (nearest point on the shirt, robust),
    # then relax each row along the collar so the push leaves no kinks.
    for i in range(2, prow):
        for it in range(3):
            row = LP[i]
            for k, p_ in enumerate(row):
                hit = st.find_nearest(p_)
                if hit[0] is not None:
                    out = (p_ - hit[0]).dot(hit[1])
                    if out < .003:
                        row[k] = p_ + hit[1] * (.003 - out)
            xs = np.array([[p_.x, p_.y, p_.z] for p_ in row])
            xs[1:-1] = (xs[:-2] + 2 * xs[1:-1] + xs[2:]) / 4
            LP[i] = [Vector(x) for x in xs]
    leaf = grid_mesh(name.replace('Top_', 'Topx_') + '_Leaf', LP, LU)
    face_out(leaf, lambda c: Vector((c.x - J['neck'].x, c.y - NECK_CY, .6)))
    for o_, th in ((stand, .0016), (leaf, .0014)):
        so = o_.modifiers.new('Cloth', 'SOLIDIFY')
        so.thickness = th
        so.offset = -1 if o_ is stand else 1
        apply(o_, so)
        crisp(o_)
        o_.data.materials.append(mat)
    # collar button where the stand's ends meet
    cz = SZ0(0) + SH(0) * .5
    cb = None if not button else button_mesh('collarbtn', pt(-.035, SR(0) + .0022 + .0016 + .0011, cz), Vector((0, FRONT, 0)), r=.0045, mat=button_mat)
    zi = lambda a: SZ0(a)
    ri = lambda a: SR(a)
    return stand, leaf, zi, ri, cb


def shirt_placket(name, z_top, z_bot, w=.034, out=.0016, mat=None, garment=None):
    st = tree_of(garment or shirt)
    rows = int((z_top - z_bot) / .008) + 1
    P, U = [], []
    cols = 5
    for c in range(cols):
        t = c / (cols - 1)
        x = (t - .5) * w
        row, urow = [], []
        for k in range(rows):
            z = z_top - (z_top - z_bot) * k / (rows - 1)
            o = Vector((x, NECK_Y + FRONT * .4, z))
            hit = st.ray_cast(o, Vector((0, -FRONT, 0)))
            q = hit[0] if hit[0] is not None else Vector((x, NECK_Y + FRONT * .12, z))
            dome = .0006 * math.sin(math.pi * t)
            row.append(q + Vector((0, FRONT * (out + dome), 0)))
            urow.append(((z_top - z) / .30, TRIM_ROWS['band2'] + .25 * (.02 + .96 * t)))
        P.append(row)
        U.append(urow)
    ob = grid_mesh(name, P, U)
    face_out(ob, lambda c: Vector((0, FRONT, 0)))
    so = ob.modifiers.new('Cloth', 'SOLIDIFY')
    so.thickness = .0015
    so.offset = -1
    so.use_rim_only = True
    apply(ob, so)
    crisp(ob)
    ob.data.materials.append(mat)
    reweight(ob)
    return ob


def button_mesh(name, centre, normal, r=.0056, h=.0022, mat=None):
    """A sew-through shirt button: rounded rim, dished face, four holes."""
    import bmesh
    bm = bmesh.new()
    seg = 16
    prof = [(0, -h * .5), (r * .96, -h * .5), (r, -h * .2), (r, h * .3), (r * .9, h * .5), (r * .7, h * .32), (r * .3, h * .24), (0, h * .24)]
    rings = []
    for (rr, zz) in prof:
        rings.append([bm.verts.new((math.cos(math.tau * k / seg) * rr, math.sin(math.tau * k / seg) * rr, zz)) for k in range(seg)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new((r0[k], r0[(k + 1) % seg], r1[(k + 1) % seg], r1[k]))
    for k in range(4):   # holes: four dark dimples
        a = math.tau * k / 4 + math.pi / 4
        c = Vector((math.cos(a) * r * .28, math.sin(a) * r * .28, h * .25))
        ring = [bm.verts.new(c + Vector((math.cos(math.tau * j / 6) * r * .1, math.sin(math.tau * j / 6) * r * .1, .0002))) for j in range(6)]
        bot = bm.verts.new(c + Vector((0, 0, -h * .2)))
        for j in range(6):
            bm.faces.new((ring[j], ring[(j + 1) % 6], bot))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    rot = Vector((0, 0, 1)).rotation_difference(normal)
    ob.matrix_world = Matrix.Translation(centre) @ rot.to_matrix().to_4x4()
    active(ob)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for p_ in ob.data.polygons:
        p_.use_smooth = True
    ob.data.materials.append(mat)
    ob.data.uv_layers.new(name='GarmentUV')
    return ob


def shirt_buttons(placket, zs, mat, hole):
    pt = tree_of(placket)
    out = []
    for z in zs:
        hit = pt.ray_cast(Vector((0, NECK_Y + FRONT * .4, z)), Vector((0, -FRONT, 0)))
        if hit[0] is None:
            continue
        c = hit[0] + Vector((0, FRONT * .0013, 0))
        n = Vector((0, FRONT, 0))
        out.append(button_mesh('btn', c, n, mat=mat))
        # the buttonhole: a thread-bound slit peeking above and below the button
        P = [[c + Vector((dx, -FRONT * .0007, dz)) for dz in (-.0066, .0066)] for dx in (-.0008, .0008)]
        U = [[(.01, .78), (.06, .78)], [(.01, .8), (.06, .8)]]
        h = grid_mesh('hole', P, U)
        face_out(h, lambda c_: Vector((0, FRONT, 0)))
        h.data.materials.append(hole)
        out.append(h)
    return out


def shirt_cuff(side, t0=CUFF_T0, t1=CUFF_T1, mat=None, radius=None, trim_row='band2', btn=True, name='Cuff_'):
    radius = radius or cuff_radius
    af = frames()[1][side]
    nA = 40
    rows = 6
    P, U = [], []
    circ = 0.0
    for i in range(rows):
        t = t0 + (t1 - t0) * i / (rows - 1)
        s_ = i / (rows - 1)
        row, urow = [], []
        for k in range(nA + 1):
            a = math.tau * k / nA
            r = radius(side, a) + .0008 * math.sin(math.pi * s_)
            row.append(af.point(t, a, r))
        acc = [0.0]
        for k in range(1, nA + 1):
            acc.append(acc[-1] + (row[k] - row[k - 1]).length)
        for k in range(nA + 1):
            urow.append((acc[k] / .30, TRIM_ROWS[trim_row] + .25 * (.03 + .94 * s_)))
        P.append(row)
        U.append(urow)
    ob = grid_mesh(name + side, P, U)
    face_out(ob, lambda c: (c - af.a) - af.ax * (c - af.a).dot(af.ax))
    so = ob.modifiers.new('Cloth', 'SOLIDIFY')
    so.thickness = .0024
    so.offset = 1
    apply(ob, so)
    crisp(ob)
    ob.data.materials.append(mat)
    reweight(ob)
    # cuff button on the outer (thumb) side, near the cuff's lower edge
    dn = Vector((0, 0, -1)) - af.ax * Vector((0, 0, -1)).dot(af.ax)
    out_dir = (af.u * 0 + af.w * (1 if side == 'r' else -1))
    a_out = math.atan2(out_dir.dot(af.w), out_dir.dot(af.u))
    a_btn = a_out + (.6 if side == 'r' else -.6)
    tb = t0 + (t1 - t0) * .5
    c = af.point(tb, a_btn, radius(side, a_btn) + .0024 + .0011)
    n = (c - af.point(tb, a_btn, 0)).normalized()
    return ob, (button_mesh('cuffbtn', c, n, mat=button_mat) if btn else None)


def join_as(name, objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o_ in objs:
        o_.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


stand, leaf, _szi, _sri, collar_btn = shirt_collar('Top_Shirt', mat=trim_mat, gap=OPEN_HALF / STAND_R(0) + .02, spread=.28,
                                                  closed=False, button=False)
plk = shirt_placket('plk', ZV + .004, WAIST_TOP - .02, mat=trim_mat)
btns = shirt_buttons(plk, [ZV - .012 - .09 * k for k in range(6) if ZV - .012 - .09 * k > WAIST_TOP + .025], button_mat, hole_mat)
cuffs = []
for _side in ('l', 'r'):
    cf, cb = shirt_cuff(_side, mat=trim_mat)
    cuffs += [cf, cb]
# buttons and holes ride the placket's weights
for o_ in btns + [c for c in cuffs if c.name.startswith('cuffbtn')]:
    reweight(o_)
# Everything sewn on follows the shirt; only the collar stand's top edge
# shares a little of the neck's motion (it sits round the neck).
# The stand is sewn to the shirt at its base and wraps the neck at its top:
# weights go from the shirt's (base) to the neck skin's (top), so the throat
# never pushes through it when the head moves.
reweight(stand)


def _stand_t(co):
    a = math.atan2(co.x - J['neck'].x, (co.y - NECK_CY) * FRONT) % math.tau
    return max(0.0, min(1.0, (co.z - STAND_Z0(a)) / STAND_H(a)))


weights_from(stand, shirt, lambda co: 1.0 - .8 * _stand_t(co))
for o_ in [leaf, plk] + btns + cuffs:
    weights_from(o_, shirt)
breast_pocket = stitch_panel('Shirt breast pocket',shirt,
    [(.061,.113,0,1.385),(.054,.119,.0012,1.398),(.051,.123,.0023,1.425),(.050,.123,.0011,1.452)],
    trim_mat, clearance=.0028)
shirt_trims = [stand,leaf,plk]+btns+cuffs
if breast_pocket is not None:
    shirt_trims.append(breast_pocket)
trim = join_as('Topx_Shirt_Trim',shirt_trims)
add(trim, False)

# ---------------------------------------------------------------- everyday tops on the same pipeline
# Tee, polo and jumper: fitted by the garment kit like the shirt, worn
# untucked over the trousers (layer clearance + layer-following weights),
# necklines on the measured neck, trims from the shared atlas.
rib_trim = material('hero_rib', (.14, .15, .17), .8, TRIM_A, TRIM_N)
rib_trim.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = 1.0
TEE_HEM = PANTS_TOP - .035


def neck_ring_fit(z_back, z_front, ease):
    """A neckline ring at the base of the neck (crew necks, polo collars):
    radius from the measured neck at the ring's own height, low-passed and
    mirrored, so it sits on the neck's base without gaps or a wide stand."""
    Z = _periodic([z_back - (z_back - z_front) * max(0.0, math.cos(a)) ** 1.6 for a in _NK_A])
    r = [_neck_ray(a, Z(a)) + ease for a in _NK_A]
    r = [(r[k] + r[-k]) / 2 for k in range(72)]
    return _periodic(list(fourier_smooth(r, 3))), Z


def seams_fn(hem_fn, sleeve_hem_t=None, cuffed=False):
    """Seams for a set-in-sleeve top: side, shoulder, armhole, underarm and
    hem topstitching (+ a turned sleeve hem at ArmFrame t)."""
    def H(P, N):
        tf, afs = frames()
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        cy = np.interp(z, tf.zs, tf.cy)
        fy = (y - cy) * FRONT
        out = np.zeros(len(P), np.float32)
        t = np.zeros(len(P))
        ar = np.zeros(len(P))
        aa = np.zeros(len(P))
        for side, sx in (('l', -1), ('r', 1)):
            af = afs[side]
            m = x * sx > 0
            r = P[m] - np.array(af.a)
            t[m] = r @ np.array(af.ax) / af.L
            ar[m] = np.hypot(r @ np.array(af.w), r @ np.array(af.u))
            aa[m] = np.arctan2(r @ np.array(af.w), r @ np.array(af.u))
        on_arm = (np.abs(x) > .175) & (t > .02) & (ar < .1)
        torso = ~on_arm
        m = torso & (np.abs(x) > .1) & (z < 1.37)
        out[m] += seam_height(fy[m], z[m])
        cys = float(np.interp(1.5, tf.zs, tf.cy))
        m = torso & (z > 1.40) & (np.abs(x) > .06)
        out[m] += seam_height(((y - cys) * FRONT + .012)[m], x[m])
        for sx in (-1, 1):
            nx, nz = sx / math.hypot(1, .2), .2 / math.hypot(1, .2)
            d = (x - sx * .186) * nx + (z - 1.45) * nz
            m = (x * sx > .12) & (z > 1.28) & (np.abs(d) < .02)
            out[m] += seam_height(d[m], (z + fy)[m])
        ang = np.arctan2(x, fy)
        hz = np.array([hem_fn(a_) for a_ in ang])
        m = torso & (z < hz + .03)
        out[m] += seam_height((z - hz - .011)[m], ang[m] * .15, groove=.0, stitch_off=0)
        if sleeve_hem_t is not None:
            L = afs['r'].L
            m = on_arm & (np.abs(t - sleeve_hem_t + .02) < .03)
            out[m] += seam_height(((t - sleeve_hem_t + .02) * L)[m], aa[m] * .05, groove=.0, stitch_off=0)
        out += (.0004 * (z < 1.2) * torso * np.sin(ang * 31 + z * 23) * np.sin(z * 7 + ang)).astype(np.float32)
        return out
    return H


def plain_albedo(P, N, H, textile='joggers', grain=.72):
    a = .925 + 26 * np.clip(H, -.003, .002) + grain * textile_grain(textile, P, N)
    return np.repeat(np.clip(a, .74, .995)[:, None], 3, 1).astype(np.float32)


def leather_grain(points):
    x, y, z = points.T
    layer = np.sin(2120 * x + 780 * y + 880 * z + 1.4 * np.sin(3090 * y - 1910 * z))
    across = np.sin(2870 * z - 1850 * x + .9 * np.sin(1380 * y + 870 * x))
    return layer * across


def everyday_top(name, matname, layer, lim, sleeve_end, neck, ease, hem=TEE_HEM, tail=.04, sleeve_ease=(.016, .014),
                 cuff=None, base_rgb=(.16, .17, .19), rough=.78, textile='joggers', texture_name=None):
    if BODY == 'b':
        neck = (neck[0] + COLLAR_LEVEL, neck[1] + COLLAR_LEVEL + (.004 if name == 'Top_Tee' else 0.0))
        sleeve_ease = tuple(amount * .78 for amount in sleeve_ease)
    R_, Z_ = neck_ring_fit(neck[0], neck[1], ease)
    ob = tailored_top(name, hem, neck[0], (neck[0] - neck[1]) / R_(0), (R_(math.pi / 2), R_(0), R_(math.pi)), layer,
                      sleeve_end=sleeve_end, cuff=cuff, neck_cy=NECK_CY, lim=lim, taper_front=.12, taper_side=.3, neck_curve=Z_,
                      sleeve_ease=sleeve_ease, sleeve_taper=.1)
    # The neckline ring follows the garment where it actually is at neckline
    # height (it bridges the hollow of the throat: snapping it back onto the
    # skin there folded the cloth over), low-passed and mirrored.
    st_ = tree_of(ob)
    rr = []
    for a in _NK_A:
        d = Vector((math.sin(a), FRONT * math.cos(a), 0))
        c = Vector((J['neck'].x, NECK_CY, Z_(a) - .003))
        hit = st_.ray_cast(c + d * .25, -d)
        rr.append(max(R_(a), (Vector((hit[0].x - c.x, hit[0].y - c.y, 0)).length + .001) if hit[0] is not None else R_(a)))
    rr = [(rr[k] + rr[-k]) / 2 for k in range(72)]
    if BODY == 'b':
        rr = [min(radius, R_(a) + .0055) for radius, a in zip(rr, _NK_A)]
    R_ = _periodic(list(fourier_smooth(rr, 3)))
    snap_neckline(ob, R=R_, Z0=Z_, reach=.044)
    shirttail(ob, hem, tail, tail, rows=3, flare=.004)
    weights_below(ob, hem)
    if name == 'Top_Tee':
        def tension(co):
            if abs(co.x)>.205 or co.z>1.425:
                return 0.0
            shoulder = math.exp(-((abs(co.x)-.142)/.055)**2-((co.z-1.33)/.125)**2)
            waist = math.exp(-((co.z-1.066)/.084)**2) * min(1,abs(co.x)/.14)
            return .76*shoulder+.39*waist
        def ridges(co):
            k = co.z-1.32 - .49*(abs(co.x)-.14) - .14*co.y
            return math.exp(-(k/.022)**2)-.55*math.exp(-((k+.023)/.019)**2)
        fold_relief(ob,[(tension,ridges,.0046)])
    clear_layer(ob, pants, .007, zmax=PANTS_TOP + .03)
    # (the hem moves with the trousers under it: at .6 the hips pushed the
    # waistband and belt loops through the tee's hem in motion)
    follow_layer(ob, pants, PANTS_TOP + .03, .055, k_max=1.0)
    pack_uvs(ob)
    seams = seams_fn(lambda a: hem-tail, sleeve_end if cuff is None else None)
    if textile == 'leather':
        relief = lambda P,N: seams(P,N) + .00011 * leather_grain(P)
        def colour(P, N, H):
            grain = np.clip(.91 + 22 * H + .014 * leather_grain(P), .76, .98)
            return grain[:, None] * np.array([1, .983, .969])
    else:
        relief = seams
        colour = lambda P,N,H: plain_albedo(P,N,H,textile)
    nrm, alb = bake_detail(ob, texture_name or name.lower(), 1024, relief, colour)
    mat = material(matname, base_rgb, rough, alb, nrm)
    mat.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = 1.0
    finish(ob, [mat], rim=.0018)
    add(ob)
    return ob, R_, Z_


def rib_band(name, R_, Z_, h, garment, lean=.0012, ease_top=0.0):
    """Knitted neck rib on the measured neck ring (trim atlas rib row)."""
    nA = 72
    angs = [math.tau * k / nA for k in range(nA + 1)]
    pt = lambda a, r, z: Vector((J['neck'].x + math.sin(a) * r, NECK_CY + FRONT * math.cos(a) * r, z))
    P, U = [], []
    for i in range(3):
        t = i / 2
        row, urow = [], []
        acc = 0.0
        for k, a in enumerate(angs):
            if k:
                acc += (pt(a, R_(a), 0) - pt(angs[k - 1], R_(angs[k - 1]), 0)).length
            row.append(pt(a, R_(a) - lean * t + ease_top * t - .0012 * (1-t),
                          Z_(a) - .004 + (h + .004) * t))
            urow.append((acc / .30, TRIM_ROWS['rib'] + .25 * (.05 + .9 * t)))
        P.append(row)
        U.append(urow)
    ob = grid_mesh(name, P, U)
    face_out(ob, lambda c: Vector((c.x - J['neck'].x, c.y - NECK_CY, 0)))
    so = ob.modifiers.new('Cloth', 'SOLIDIFY')
    so.thickness = .0022
    so.offset = -1
    apply(ob, so)
    crisp(ob)
    ob.data.materials.append(rib_trim)
    reweight(ob)
    weights_from(ob, garment, lambda co: .96)
    return ob


SHORT_T = .36       # short sleeves end at ArmFrame t (about mid upper arm)
# Tee
tee, _tR, _tZ = everyday_top('Top_Tee', 'hero_tee', 'shirt', .78, SHORT_T, (1.577, 1.540), .004,
                            sleeve_ease=(.013,.014), tail=.047)
tee_trim = [rib_band('Topx_Tee_Rib', lambda a: _tR(a)+.0019, _tZ, .007 if BODY == 'b' else .010, tee, lean=.0017)]
tee_hull = tree_of(tee)
for side, af in frames()[1].items():
    def sleeve_opening(_, angle, af=af):
        inner = af.point(SHORT_T-.013,angle,0)
        outer = af.point(SHORT_T-.013,angle,.145)
        hit,_,_,_ = tee_hull.ray_cast(outer,(inner-outer).normalized())
        return af.polar(hit)[2]+.0017 if hit is not None else .049
    hem_piece,_ = shirt_cuff(side,SHORT_T-.025,SHORT_T+.001,mat=rib_trim,
                             radius=sleeve_opening,trim_row='band2',btn=False,name='TeeSleeveHem_')
    weights_from(hem_piece,tee)
    tee_trim.append(hem_piece)
add(join_as('Topx_Tee_Bindings',tee_trim),False)
# Polo: rib-less neckline with a knitted collar (stand + leaf, open) and a two-button placket.
polo, _pR, _pZ = everyday_top('Top_Polo', 'hero_polo', 'shirt', .78, SHORT_T, (1.592, 1.565), .0055, sleeve_ease=(.018, .017))
_pH = _periodic([.02 - .003 * max(0.0, math.cos(a)) for a in _NK_A])
pstand, pleaf, _, _, _ = shirt_collar('Top_Polo', gap=.16, leaf_w=(.036, .052), spread=.22, mat=rib_trim, garment=polo,
                                     R=_pR, Z0=_pZ, H=_pH, closed=False, button=False)
pplk = shirt_placket('pplk', _pZ(0) - .0005, _pZ(0) - .12, w=.03, mat=rib_trim, garment=polo)
pbtns = shirt_buttons(pplk, [_pZ(0) - .03, _pZ(0) - .085], button_mat, hole_mat)
reweight(pstand)
weights_from(pstand, polo, lambda co: .8)
for o_ in [pleaf, pplk] + pbtns:
    weights_from(o_, polo)
add(join_as('Topx_Polo_Trim', [pstand, pleaf, pplk] + pbtns), False)
# Jumper: knit, long sleeves gathered into rib cuffs, crew rib, rib hem band.
JUMPER_END = .93
jumper, _jR, _jZ = everyday_top('Top_Jumper', 'hero_knit', 'knit', 9.0, JUMPER_END, (1.588, 1.555), .0045,
                                sleeve_ease=(.02, .017), cuff=(.82, JUMPER_END, lambda sd, a: cuff_radius(sd, a) - .006),
                                rough=.9)
add(rib_band('Topx_Jumper_Rib', _jR, _jZ, .015, jumper, lean=.0014), False)
jparts = []
for _side in ('l', 'r'):
    cf, _ = shirt_cuff(_side, JUMPER_END - .01, 1.0, mat=rib_trim, radius=lambda sd, a: cuff_radius(sd, a) - .005, trim_row='rib',
                       btn=False, name='RibCuff_')
    weights_from(cf, jumper)
    jparts.append(cf)
add(join_as('Topx_Jumper_Cuffs', jparts), False)

# ---------------------------------------------------------------- hoodie
def open_hoodie_zip(hood):
    """Open a continuous V between the collar and the top of the zipper."""
    bm = bmesh.new()
    bm.from_mesh(hood.data)

    def opening(co):
        width = max(0.0,min(.052,(co.z-1.412)*.445))
        return max(abs(co.x)-width,.006-(co.y-NECK_CY)*FRONT)

    iso_cut(bm,opening)
    bm.to_mesh(hood.data)
    bm.free()
    hood.data.update()


def settle_hood_fold(fold, shell):
    """Bring the hanging outer hood panel back onto the shoulder blades."""
    hull = tree_of(shell)
    for vertex in fold.data.vertices:
        p = vertex.co
        rear = max(0.0,min(1.0,((NECK_CY-p.y)*FRONT-.074)/.080))
        if rear == 0:
            continue
        origin = Vector((p.x,NECK_CY-FRONT*.38,p.z))
        hit,_,_,_ = hull.ray_cast(origin,Vector((0,FRONT,0)))
        if hit is None or (NECK_CY-hit.y)*FRONT < .021:
            continue
        dy = (hit.y - FRONT*.018 - p.y)*(.80*rear)
        p.y += dy
        if fold.data.shape_keys:
            for target in fold.data.shape_keys.key_blocks:
                target.data[vertex.index].co.y += dy
    fold.data.update()


def folded_hood(shell, neck_radius, neck_height):
    """Two sewn hood panels folded onto the upper back, with a turned lip."""
    rows, uv = [], []
    for row in range(9):
        t = row/8
        points, texcoords = [], []
        for col in range(57):
            u = col/56
            a = .62+(math.tau-1.24)*u
            back = max(0,-math.cos(a))
            fade = math.sin(math.pi*u)**.68
            width = (.026 + .063*back)*fade
            r = neck_radius(a)+width*t
            z = neck_height(a) - .003
            z += (.009+.024*back)*math.sin(math.pi*t)*fade
            z -= (.029+.101*back)*t*t*fade
            y = NECK_CY+FRONT*math.cos(a)*r-.018*back*t
            points.append(Vector((math.sin(a)*r,y,z)))
            texcoords.append((u*1.65,.763+.220*t))
        rows.append(points)
        uv.append(texcoords)
    hood = grid_mesh('Topx_Hoodie_Fold',rows,uv)
    face_out(hood,lambda c: Vector((c.x,(c.y-NECK_CY)*.6,.32)))
    settle_hood_fold(hood,shell)
    weights_from(hood,shell)
    fleece = material('hero_hood_fold',(.14,.15,.17),.89,TRIM_A,TRIM_N)
    finish(hood,[fleece],rim=.0038)
    return hood


def fleece_hoodie():
    hem = PANTS_TOP-.037
    cuff_start = .927
    neck_r, neck_z = neck_ring_fit(1.581 + COLLAR_LEVEL, 1.542 + COLLAR_LEVEL, .010)
    hood = tailored_top('Top_Hoodie',hem,1.581 + COLLAR_LEVEL,1.0,
        (neck_r(math.pi/2),neck_r(0),neck_r(math.pi)),'knit',
        sleeve_end=cuff_start,cuff=(.80,cuff_start,lambda sd,a: cuff_radius(sd,a)+.001),
        neck_cy=NECK_CY,neck_curve=neck_z,taper_front=.09,taper_side=.21,
        sleeve_ease=(.011,.014) if BODY=='b' else (.015,.016),
        sleeve_taper=.115,shoulder_ease=.0037)
    snap_neckline(hood,R=neck_r,Z0=neck_z,reach=.037)
    shirttail(hood,hem,.048,.045,rows=4,flare=.005)
    weights_below(hood,hem)
    clear_layer(hood,pants,.010,zmax=PANTS_TOP+.034)
    open_hoodie_zip(hood)
    pack_uvs(hood)
    sewn = seams_fn(lambda _: hem-.046)

    def fleece_height(P,N):
        x,y,z = P.T
        mask = np.clip((1.42-z)/.04,0,1)*np.clip((y-.034)/.045,0,1)
        return sewn(P,N)+mask*seam_height(x-.005,z,groove=.00018,stitch_off=.006,stitch_len=.003)

    nrm, alb = bake_detail(hood,'fleece_shell',1024,fleece_height,plain_albedo)
    fleece = wmat('hero_fleece',(.16,.17,.19),.87,alb,nrm)
    fleece.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = .73
    finish(hood,[fleece],rim=.0036)
    add(hood)
    add(folded_hood(hood,neck_r,neck_z),False)
    cuffs = []
    for side in ('l','r'):
        cuff,_ = shirt_cuff(side,cuff_start-.013,1.005,mat=rib_trim,
            radius=lambda sd,a: cuff_radius(sd,a)+.001,trim_row='rib',btn=False,name='HoodCuff_')
        weights_from(cuff,hood)
        cuffs.append(cuff)
    add(join_as('Topx_Hoodie_Cuffs',cuffs),False)
    add(hoodie_lining(tee,hood),False)
    zipper_trim(hood,'Hoodie',1.418,hem-.038,.009)
    simplify_surface(hood,.68)

def zipper_trim(shell, cut, top, bottom, width):
    tape = bpy.data.materials.get('hero_zipper')
    if tape is None:
        tape = material('hero_zipper', (.105, .110, .12), .74, normal=TRIM_N)
        tape.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = .48
    tree = tree_of(shell)
    y_values = []
    for z in np.linspace(bottom, top, 22):
        hit, _, _, _ = tree.ray_cast(Vector((.007, NECK_CY + FRONT*.35, z)), Vector((0,-FRONT,0)))
        if hit is not None and (hit.y-NECK_CY)*FRONT > .032:
            y_values.append((z, hit.y + FRONT*.0024))
    if len(y_values) < 3:
        return
    points = [[Vector((.007+x, y, z)) for x in (-width/2,width/2)] for z,y in y_values]
    uvs = [[(z*5, .761), (z*5, .991)] for z,_ in y_values]
    zip_strip = grid_mesh('Zipper tape', points, uvs)
    face_out(zip_strip, lambda _: Vector((0, FRONT, 0)))
    weights_from(zip_strip, shell)
    finish(zip_strip, [tape], rim=.001)
    z, y = y_values[-1]
    pull = button_mesh('Zip slider', Vector((.007, y+FRONT*.0017, z-.008)),
                       Vector((0,FRONT,0)), r=.005, h=.0018, mat=dark_button_mat)
    weights_from(pull, shell)
    add(join_as('Topx_' + cut + '_Zip', [zip_strip, pull]), False)


fleece_hoodie()

# Zippered flight jacket with nylon shell, separate ribbed neck and wrists.
bomber, bomb_R, bomb_Z = everyday_top('Top_Bomber', 'hero_bomber', 'jacket', 9.0, .929,
                                    (1.589, 1.557), .009, hem=PANTS_TOP-.009, tail=.035,
                                    sleeve_ease=(.036,.026),
                                    cuff=(.80,.929,lambda sd,a: cuff_radius(sd,a)+.001),
                                    rough=.69, textile='shorts', texture_name='bomber_ripstop')
add(rib_band('Topx_Bomber_Neck', bomb_R, bomb_Z, .014, bomber), False)


def bomber_waist(shell):
    tree = tree_of(shell)
    rows, uv = [], []
    base_z = PANTS_TOP - .040
    for j in range(4):
        t = j/3
        cy = float(np.interp(base_z+t*.043, frames()[0].zs, frames()[0].cy))
        row, texcoords = [], []
        for k in range(49):
            a = k*math.tau/48
            radial = Vector((math.sin(a), FRONT*math.cos(a), 0))
            centre = Vector((0, cy, base_z+t*.043))
            hit, _, _, _ = tree.ray_cast(centre+radial*.35, -radial)
            if hit is None:
                return None
            row.append(hit+radial*(.0061+.0015*math.sin(t*math.pi)))
            texcoords.append((k*.032, .51+.225*t))
        rows.append(row)
        uv.append(texcoords)
    band = grid_mesh('Bomber waistband', rows, uv)
    face_out(band, lambda p: Vector((p.x,p.y,0)))
    weights_from(band, shell)
    finish(band, [rib_trim], rim=.002)
    return band


belt = bomber_waist(bomber)
bomber_trims = [belt] if belt is not None else []
for side in ('l','r'):
    cf, _ = shirt_cuff(side, .922, 1.002, mat=rib_trim,
                       radius=lambda sd,a: cuff_radius(sd,a)+.001, trim_row='rib', btn=False,
                       name='BomberCuff_')
    weights_from(cf, bomber)
    bomber_trims.append(cf)
for sign in (-1,1):
    rows = [(.090,.123,.001,1.066),(.101,.134,.002,1.080),(.124,.155,.001,1.150)]
    panel = stitch_panel('Slanted welt', bomber,
                         [(a,b,d,z) if sign>0 else (-b,-a,d,z) for a,b,d,z in rows],
                         rib_trim)
    if panel is not None:
        bomber_trims.append(panel)
add(join_as('Topx_Bomber_Trims', bomber_trims),False)
zipper_trim(bomber, 'Bomber', 1.54, PANTS_TOP-.035, .009)

# ---------------------------------------------------------------- blazer, shirt and tie
# Tailored on the same pipeline: jacket layer (2 cm ease), sleeves to the
# wrist, a straight hem covering the seat, a deep V from the neck to the
# button with a cutaway below it, notch lapels laid on the fronts, and a
# jacket collar round the back of the neck meeting the lapels.
if BODY == 'a':
    JK_R = _periodic([STAND_R(a) + .011 for a in _NK_A])
    JK_Z0 = _periodic([STAND_Z0(a) + .003 for a in _NK_A])
    JK_HEM = PANTS_TOP - .03
    BTN_Z = 1.06
    blazer = tailored_top('Top_Blazer', JK_HEM, SHIRT_NECK, SHIRT_NECK_DROP, (JK_R(math.pi / 2), JK_R(0), JK_R(math.pi)), 'jacket',
                          sleeve_end=.965, cuff=(.85, .965, lambda sd, a: cuff_radius(sd, a) + .007), neck_cy=NECK_CY, taper_front=.1,
                          taper_side=.24, sleeve_ease=(.024, .02), sleeve_taper=.1, shoulder_ease=.008)
    snap_neckline(blazer, R=JK_R, Z0=JK_Z0)
    shirttail(blazer, JK_HEM, .135, .125, rows=4, flare=.01)
    weights_below(blazer, JK_HEM)
    clear_layer(blazer, pants, .009, zmax=PANTS_TOP + .04)
    follow_layer(blazer, pants, PANTS_TOP, .12, k_max=.5)
    _V_TOP = (.082, 1.455)                 # where the lapel's edge meets the gorge
    _CUT_BOT = (.10, JK_HEM - .135)       # the cutaway's end at the hem


    def _jk_vw(z):
        if z >= _V_TOP[1]:
            return _V_TOP[0]
        if z >= BTN_Z:
            t = (z - BTN_Z) / (_V_TOP[1] - BTN_Z)
            return .011 + (_V_TOP[0] - .011) * t
        t = (BTN_Z - z) / (BTN_Z - _CUT_BOT[1])
        return .011 + (_CUT_BOT[0] - .011) * t ** 1.4


    bm = bmesh.new()
    bm.from_mesh(blazer.data)
    iso_cut(bm, lambda co: max(abs(co.x) - _jk_vw(co.z), .022 - (co.y - NECK_CY) * FRONT))
    bm.to_mesh(blazer.data)
    bm.free()
    blazer.data.update()
    pack_uvs(blazer)
    _jn, _ja = bake_detail(blazer, 'top_blazer', 1024, seams_fn(lambda a: JK_HEM - .13), plain_albedo)
    wool_mat = material('hero_blazer', (.16, .17, .19), .74, _ja, _jn)
    wool_mat.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = 1.0
    finish(blazer, [wool_mat], rim=.004)
    add(blazer)
    bt = tree_of(blazer)


    def lapel(sx):
        """A notch lapel lying on the front: from the roll point at the button up
        the V edge to the gorge, widening to 7 cm, its top cut at the notch."""
        P, U = [], []
        n_s, n_w = 22, 5
        for i in range(n_w):
            t = i / (n_w - 1)
            row, urow = [], []
            for k in range(n_s + 1):
                s_ = k / n_s
                z = BTN_Z + (_V_TOP[1] - BTN_Z) * s_
                w = .072 * min(1.0, s_ / .8) ** .9
                if s_ > .9:                     # the notch: the outer top corner cut back
                    w *= 1 - .45 * (s_ - .9) / .1 * t
                x_edge = _jk_vw(z)
                x = sx * (x_edge + w * t - .0008)
                sample_x = sx * (x_edge + max(.007, w * t))
                o = Vector((sample_x, NECK_CY + FRONT * .4, z))
                hit = bt.ray_cast(o, Vector((0, -FRONT, 0)))
                depth = hit[0].y if hit[0] is not None and (hit[0].y - NECK_CY)*FRONT > .028 else NECK_CY + FRONT * .112
                roll = .0035 * (1 - t) ** 2 + .0055
                row.append(Vector((x, depth + FRONT*roll, z)))
                urow.append((s_ * .45 / .30, TRIM_ROWS['plain'] + .25 * (.05 + .9 * t)))
            P.append(row)
            U.append(urow)
        ob = grid_mesh('lapel', P, U)
        face_out(ob, lambda c: Vector((0, FRONT, 0)))
        so = ob.modifiers.new('Cloth', 'SOLIDIFY')
        so.thickness = .002
        so.offset = -1
        so.use_rim_only = True
        apply(ob, so)
        crisp(ob)
        ob.data.materials.append(lapel_mat)
        weights_from(ob, blazer)
        return ob


    _lap = [lapel(-1), lapel(1)]
    _jgap = math.atan2(_V_TOP[0], JK_R(0)) + .1
    jst, jlf, _, _, _ = shirt_collar('Top_Blazer', gap=_jgap, leaf_w=(.034, .04), spread=.12, mat=wool_mat, garment=blazer, R=JK_R, Z0=JK_Z0,
                                     H=_periodic([.014 for a in _NK_A]), closed=False, button=False)
    reweight(jst)
    weights_from(jst, blazer, lambda co: .85)
    weights_from(jlf, blazer)
    _hit = bt.ray_cast(Vector((0, NECK_CY + FRONT * .4, BTN_Z - .012)), Vector((0, -FRONT, 0)))
    jbtn = button_mesh('jbtn', (_hit[0] if _hit[0] is not None else Vector((0, .12, BTN_Z))) + Vector((0, FRONT * .004, 0)),
                       Vector((0, FRONT, 0)), r=.0085, h=.003, mat=dark_button_mat)
    weights_from(jbtn, blazer)
    add(join_as('Topx_Blazer_Collar', [jst, jlf] + _lap + [jbtn]), False)
    # The shirt inside the V: the real tailored shirt (closed, collar-snapped,
    # tucked), trimmed to its front panel with clean plane cuts.
    sfront = shirt_closed
    tuck_into(sfront, pants, WAIST_TOP, .005)
    follow_layer(sfront, pants, WAIST_TOP + .02, .04, k_max=1.0)
    sfront.name = 'Topx_Blazer_Shirt'
    sfront.data.name = 'Topx_Blazer_Shirt'
    bm = bmesh.new()
    bm.from_mesh(sfront.data)
    for co, no in (((.15, 0, 0), (1, 0, 0)), ((-.15, 0, 0), (1, 0, 0))):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.calc_center_median().x) > .15 or (f.calc_center_median().y - NECK_CY) * FRONT < -.01
                               or f.calc_center_median().z < PANTS_TOP - .045], context='FACES')
    bm.to_mesh(sfront.data)
    bm.free()
    sfront.data.update()
    sfront.data.materials.clear()
    sfront.data.materials.append(white_mat)
    add(sfront, False)
    sft = tree_of(sfront)
    # The shirt under the jacket wears the closed, buttoned collar (with a tie).
    white_trim = material('hero_shirt_white_trim', (.86, .87, .88), .6, TRIM_A, TRIM_N)
    white_trim.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = 1.0
    bst, blf, _, _, bbtn = shirt_collar('Top_BlazerShirt', mat=white_trim, garment=shirt,
                                        gap=.10, leaf_w=(.029,.057), H=lambda a: STAND_H(a)*.74)
    reweight(bst)
    weights_from(bst, sfront, lambda co: .8)
    for o_ in [blf, bbtn]:
        weights_from(o_, sfront)
    add(join_as('Topx_Blazer_ShirtCollar', [bst, blf, bbtn]), False)
    def tie_piece(name, rows, lift):
        """A narrow silk blade and knot on a common smooth centreline."""
        P, U = [], []
        last_y = None
        for i, (z, width) in enumerate(rows):
            hit, _, _, _ = sft.ray_cast(Vector((0, NECK_CY + FRONT * .4, z)), Vector((0, -FRONT, 0)))
            depth = hit.y if hit is not None else NECK_CY + FRONT*(STAND_R(0) + .013)
            if last_y is not None:
                depth = min(last_y + .013, max(last_y - .013, depth))
            last_y = depth
            P.append([Vector((t*width*.5, depth + FRONT*(lift + .004*(1-abs(t))), z)) for t in (-1, 0, 1)])
            U.append([(t, i / max(1, len(rows) - 1)) for t in (0.0, .5, 1.0)])
        ob = grid_mesh(name, P, U)
        face_out(ob, lambda co: Vector((0, FRONT, 0)))
        solid = ob.modifiers.new('Silk edges', 'SOLIDIFY')
        solid.thickness = .0016
        solid.offset = -1
        solid.use_rim_only = True
        apply(ob, solid)
        ob.data.materials.append(tie_mat)
        lay_on_front(ob, sfront, FRONT, lift)
        weights_from(ob, sfront)
        add(ob, False)


    knot_top = STAND_Z0(0) + .008
    knot_bottom = knot_top - .034
    tie_piece('Topx_Blazer_Tie', [(knot_bottom - (knot_bottom - 1.101)*i/18, .031+.041*i/18) for i in range(19)]
              + [(1.084, .009)], .012)
    tie_piece('Topx_Blazer_Knot', [(knot_top, .038), (knot_top-.014, .036), (knot_bottom-.003, .022)], .016)

# ---------------------------------------------------------------- trouser waistband
# A finished 3.6 cm band round the trousers' cut top (it was a raw edge),
# topstitched, with seven belt loops and the fly button. Follows the trousers.
def waistband(block):
    tf, _ = frames()
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(block.data)
    bm.normal_update()
    ptree = BVHTree.FromBMesh(bm)
    bm.free()
    nA, rows, h = 96, 4, .036
    angs = [math.tau * k / nA for k in range(nA + 1)]
    R = []
    prev = None
    for i in range(rows):
        z = PANTS_TOP - h + h * i / (rows - 1)
        zs_ = min(z, PANTS_TOP - .004)        # sample safely inside the cut edge (rays slip past it)
        cy = float(np.interp(z, tf.zs, tf.cy))
        rr = []
        for k_, a in enumerate(angs[:-1]):
            d = Vector((math.sin(a), FRONT * math.cos(a), 0))
            hit = ptree.ray_cast(Vector((0, cy, zs_)) + d * .4, -d)
            if hit[0] is not None:
                rr.append(Vector((hit[0].x, hit[0].y - cy, 0)).length + .0016)
            else:
                rr.append(prev[k_] if prev else .16)
        prev = rr
        rr = [(rr[k] + rr[-k]) / 2 for k in range(nA)]
        R.append((cy, z, list(fourier_smooth(rr, 8))))
    P, U = [], []
    for i, (cy, z, rr) in enumerate(R):
        row, urow = [], []
        acc = 0.0
        for k, a in enumerate(angs):
            r = rr[k % nA]
            q = Vector((math.sin(a) * r, cy + FRONT * math.cos(a) * r, z))
            if k:
                acc += (q - row[-1]).length
            row.append(q)
            urow.append((acc / .30, TRIM_ROWS['band2'] + .25 * (.03 + .94 * i / (rows - 1))))
        P.append(row)
        U.append(urow)
    band = grid_mesh('band', P, U)
    face_out(band, lambda c: Vector((c.x, c.y - float(np.interp(c.z, tf.zs, tf.cy)), 0)))
    so = band.modifiers.new('Cloth', 'SOLIDIFY')
    so.thickness = .0025
    so.offset = -1
    apply(band, so)
    crisp(band)
    parts = [band]
    cy, z_mid, rr = R[1]
    for a0 in (.5, -.5, 1.45, -1.45, 2.35, -2.35, math.pi):
        k = int(round((a0 % math.tau) / math.tau * nA)) % nA
        LP, LU = [], []
        for j, dz in enumerate((-.002, -.034)):   # (top at the band's edge, as real loops)
            row = []
            for da in (-.035, .035):
                a = a0 + da
                kk = int(round((a % math.tau) / math.tau * nA)) % nA
                r = R[0][2][kk] + .0026
                row.append(Vector((math.sin(a) * r, cy + FRONT * math.cos(a) * r, PANTS_TOP + dz)))
            LP.append(row)
            LU.append([(.0, .76), (.04, .76)] if j == 0 else [(.0, .99), (.04, .99)])
        loop = grid_mesh('loop', LP, LU)
        face_out(loop, lambda c: Vector((c.x, c.y - cy, 0)))
        so = loop.modifiers.new('Cloth', 'SOLIDIFY')
        so.thickness = .002
        apply(loop, so)
        crisp(loop)
        parts.append(loop)
    for o_ in parts:
        o_.data.materials.append(band_mat)
    r0 = R[1][2][0] + .0025
    fb = button_mesh('flybtn', Vector((0, cy + FRONT * r0, PANTS_TOP - .018)), Vector((0, FRONT, 0)), r=.0075, h=.003, mat=dark_button_mat)
    parts.append(fb)
    ob = join_as('Courier_Waistband', parts)
    weights_from(ob, block)
    return ob


band_mat = material('hero_waistband', (.16, .17, .19), .85, TRIM_A, TRIM_N)
band_mat.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = 1.0
_wbo = waistband(pants)
add(_wbo, False)
for top in tops + loose_tops:
    if top.name in ('Top_Shirt', 'Top_Blazer'):
        continue
    if top in tops:
        fit_over_waist(top, pants, _wbo, True, .004)
    else:
        fit_over_waist(top, pants, _wbo, False, .009)

chinos = chinos_from_block(pants)
add(chinos, False)
for style in ('jeans','joggers','shorts'):
    for piece in lower_cut(pants, style):
        add(piece, False)
add_short_skin()
fit_over_waist(shirt, chinos, _wbo, True, .004)
if BODY == 'a':
    fit_over_waist(blazer, chinos, _wbo, False, .009)
finish_trainer(shoes)
for component in trainer_construction(shoes):
    add(component,False)
lace_mesh = trainer_laces(shoes)
if lace_mesh is not None:
    add(lace_mesh, False)
# Keep the high-resolution tailoring through fit, transfer and baking. The
# final render shells keep the openings and remove interior density.
shells = [(tee, .59), (polo, .59), (shirt, .58), (jumper, .57), (bomber, .62)]
if BODY == 'a':
    shells.extend([(blazer, .60), (sfront, .66)])
for garment_, ratio in shells:
    simplify_surface(garment_, ratio)
print('WARDROBE', [o.name for o in wardrobe], flush=True)
