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
_fm = face_meshes['kai'][0]
FRONT = 1.0 if sum(v.co.y for v in _fm.data.vertices) / len(_fm.data.vertices) > J['neck'].y else -1.0
HIP = Vector((J['hips'].x, J['hips'].y, 0))
NECK_Y = J['neck'].y

# How far the trousers stand off the skin round the waist: the hems must clear it.
_btree = BVHTree.FromPolygons([RB[j] for j in range(len(RB))], [list(reversed(bf[i])) for i in body])
_gaps = []
for v in pants.data.vertices:
    if .9 < v.co.z < .985:
        hit = _btree.find_nearest(v.co)
        if hit[0] is not None:
            _gaps.append(hit[3])
PANTS_GAP = float(np.percentile(_gaps, 97)) if _gaps else .02
print('PANTS_GAP', round(PANTS_GAP, 4), 'FRONT', FRONT, flush=True)


def wmat(name, color, rough, tex=None, normal=None):
    return material(name, color, rough, tex, normal)


tee_mat = wmat('hero_tee', (.16, .17, .19), .78, knit, TEX/'top_knit_normal.png')
rib_mat = wmat('hero_rib', (.14, .15, .17), .8, knit, TEX/'top_knit_normal.png')
knit_mat = wmat('hero_knit', (.16, .17, .19), .9, knit, TEX/'top_knit_normal.png')
shirt_mat = wmat('hero_shirt', (.16, .17, .19), .62, knit)
wool_mat = wmat('hero_blazer', (.16, .17, .19), .74, knit, TEX/'top_knit_normal.png')
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


def _neck_cut(bm, neck, drop, oval, K=28):
    """Cuts the neck opening: an oval round the neck (rx at the sides, rf/rb
    front/back) above the plane through `neck` that dips `drop` towards the
    front. The shoulders outside the oval stay covered (a flat cut through
    the whole garment took the shoulder tops off with it: the trapezius
    stands higher than the neckline). The oval's sides are split first
    (only near the neck), so the opening has a clean edge."""
    rx, rf, rb = oval
    C = Vector((J['neck'].x, NECK_Y, 0))
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
    top = Vector((0, NECK_Y, neck))

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


def front_strip(name, mat, target, z0, z1, w0, w1, out, x=0.0, steps=14):
    """A strip down the front of `target` (a placket, a tie): z0→z1, width
    w0→w1, `out` m proud of it."""
    vs = []
    fs = []
    for k in range(steps + 1):
        t = k / steps
        z = z0 + (z1 - z0) * t
        w = w0 + (w1 - w0) * t
        for sx in (-1, 1):
            o = Vector((x + sx * w * .5, NECK_Y + FRONT * .4, z))
            hit = target.ray_cast(o, Vector((0, -FRONT, 0)))
            q = hit[0] if hit[0] is not None else Vector((o.x, NECK_Y + FRONT * .1, z))
            vs.append(q + Vector((0, FRONT * out, 0)))
    for k in range(steps):
        a = k * 2
        fs.append([a, a + 1, a + 3, a + 2] if FRONT > 0 else [a + 2, a + 3, a + 1, a])
    ob = mesh(name, vs, [], fs, [])
    ob.data.materials.append(mat)
    so = ob.modifiers.new('Strip', 'SOLIDIFY')
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


# ---------------------------------------------------------------- tee
SHORT = .62
tee = shell('Top_Tee', SHORT, .011, .94, neck=1.545, neck_drop=.55, arm_off=.016)
skirt(tee, .94, [(.035, .006), (.035, .004)])
finish(tee, [tee_mat])
reweight(tee)
add(tee)
add(neck_ring('Topx_Tee_Rib', rib_mat, edge_fn('Top_Tee', 2), .016, .004, .0, lean=.006, rows=3, r_of=edge_fn('Top_Tee', 1)), False)

# ---------------------------------------------------------------- polo
polo = shell('Top_Polo', SHORT, .011, .94, neck=1.548, neck_drop=.35, arm_off=.016, oval=(.085, .082, .074))
skirt(polo, .94, [(.035, .006), (.035, .004)])
finish(polo, [tee_mat])
reweight(polo)
add(polo)
pt = tree_of(polo)
# Collar: a stand, then folded down over itself; open at the front.
pz = edge_fn('Top_Polo', 2)
pr = edge_fn('Top_Polo', 1)
add(neck_ring('Topx_Polo_Stand', tee_mat, pz, .03, .003, -.004, lean=.004, rows=3, gap=.32, r_of=pr), False)
add(neck_ring('Topx_Polo_Fall', tee_mat, lambda a: pz(a) + .03, -.042, .004, .022, rows=3, gap=.26,
    drop_front=.02, r_of=pr), False)
add(front_strip('Topx_Polo_Placket', tee_mat, pt, 1.47, 1.37, .032, .032, .004), False)
add(buttons('Topx_Polo_Buttons', button_mat, pt, [1.455, 1.405], out=.008), False)

# ---------------------------------------------------------------- shirt (long sleeve, untucked)
shirt = shell('Top_Shirt', 9.0, .009, .94, neck=1.56, neck_drop=.3, arm_off=.013, oval=(.082, .08, .072))
skirt(shirt, .94, [(.04, .006), (.03, .003)])
finish(shirt, [shirt_mat])
reweight(shirt)
add(shirt)
stt = tree_of(shirt)
sz = edge_fn('Top_Shirt', 2)
sr = edge_fn('Top_Shirt', 1)
add(neck_ring('Topx_Shirt_Stand', shirt_mat, sz, .032, .003, -.004, lean=.004, rows=3, gap=.2, r_of=sr), False)
add(neck_ring('Topx_Shirt_Fall', shirt_mat, lambda a: sz(a) + .032, -.05, .004, .026, rows=3, gap=.14,
    drop_front=.035, r_of=sr), False)
add(front_strip('Topx_Shirt_Placket', shirt_mat, stt, 1.5, .88, .034, .034, .003), False)
add(buttons('Topx_Shirt_Buttons', button_mat, stt, [1.46, 1.36, 1.26, 1.16, 1.06, .96], out=.007), False)

# ---------------------------------------------------------------- jumper (crew knit)
jumper = shell('Top_Jumper', 9.0, .013, .94, neck=1.545, neck_drop=.5, arm_off=.016)
skirt(jumper, .94, [(.03, .004), (.035, -.004)])
finish(jumper, [knit_mat, rib_mat], lambda c: 1 if c.z < .9 else 0)
reweight(jumper)
add(jumper)
add(neck_ring('Topx_Jumper_Rib', rib_mat, edge_fn('Top_Jumper', 2), .022, .005, .0, lean=.007, rows=3, r_of=edge_fn('Top_Jumper', 1)), False)

# ---------------------------------------------------------------- hoodie (authored garment, hood down)
hood_src = SRC / 'elvs_hooded_sweat_jacket1'
if hood_src.exists():
    hoodie = garment('elvs_hooded_sweat_jacket1', 'Top_Hoodie')
    htex = recolor_texture(hood_src / 'hoodietex1.png', 'hoodie_albedo', (.9, .9, .9)) \
        if (hood_src / 'hoodietex1.png').exists() else None
    fleece = wmat('hero_fleece', (.16, .17, .19), .9, htex, hood_src / 'normalshoodie.png')
    hoodie.data.materials.clear()
    hoodie.data.materials.append(fleece)
    # Ease it off the body where the trousers sit and keep the cuffs clear of the hands.
    for v in hoodie.data.vertices:
        if v.co.z < 1.02 and abs(v.co.x) < .26:
            h = Vector((v.co.x, v.co.y, 0)) - HIP
            if h.length > 1e-4:
                v.co += h.normalized() * .008
    subdiv(hoodie, 1)
    so = hoodie.modifiers.new('Hem', 'SOLIDIFY')
    so.thickness = .003
    so.offset = -1
    so.use_rim_only = True
    apply(hoodie, so)
    add(hoodie)

# ---------------------------------------------------------------- blazer, shirt and tie
blazer = shell('Top_Blazer', 9.0, .02, .94, neck=1.565, neck_drop=.0, arm_off=.02, waist=PANTS_GAP + .016, subdivide=True,
               oval=(.095, .09, .08))
skirt(blazer, .94, [(.06, .012), (.07, .01)])
# Open front: a V from the collar to the button at the waist, then cut away
# below it.
bm = bmesh.new()
bm.from_mesh(blazer.data)


def _v_w(z):
    if z > 1.06:
        return .02 + .085 * min(1.0, (z - 1.06) / .42)
    if z < .99:
        return .012 + (.99 - z) * .55
    return .012


kill = [f for f in bm.faces if front_of(f.calc_center_median()) > .02 and abs(f.calc_center_median().x) < _v_w(f.calc_center_median().z)]
bmesh.ops.delete(bm, geom=kill, context='FACES')
bm.to_mesh(blazer.data)
bm.free()
blazer.data.update()


def _lapel(c):
    if front_of(c) > .015 and c.z > 1.08 and abs(c.x) < _v_w(c.z) + .045:
        return 1
    return 0


finish(blazer, [wool_mat, lapel_mat], _lapel, rim=.004)
for poly in blazer.data.polygons:
    if poly.material_index == 1:
        for vi in poly.vertices:
            v = blazer.data.vertices[vi]
            v.co.y += FRONT * .0015
reweight(blazer)
add(blazer)
bt = tree_of(blazer)
add(neck_ring('Topx_Blazer_Collar', wool_mat, edge_fn('Top_Blazer', 2), .035, .003, -.006, lean=.004, rows=3, gap=1.05,
    r_of=edge_fn('Top_Blazer', 1)), False)
add(buttons('Topx_Blazer_Button', dark_button_mat, bt, [1.0], out=.006, r=.008, x=.0), False)
# The shirt front inside the V (white), its collar, and the tie.
sf_faces = [i for i in body if all(front_of(RB[j]) > -.02 and abs(RB[j].x) < .13 and .95 < RB[j].z < 1.58
            and not armish(j) for j in bf[i])]
sfront, _ = part('Topx_Blazer_Shirt', sf_faces, RB, weights)
push(sfront, .008)
sfront.data.materials.append(white_mat)
add(sfront, False)
sft = tree_of(sfront)
_collar_r = lambda a: _oval_r(a, .074, .072, .066)  # (hugging the neck, inside the blazer's opening)
add(neck_ring('Topx_Blazer_ShirtStand', white_mat, lambda a: 1.555 - .02 * max(0.0, math.cos(a)), .03, .0, -.002, rows=3,
    gap=.18, r_of=_collar_r), False)
add(neck_ring('Topx_Blazer_ShirtFall', white_mat, lambda a: 1.585 - .02 * max(0.0, math.cos(a)), -.04, .002, .018, rows=3,
    gap=.12, drop_front=.03, r_of=_collar_r), False)
add(front_strip('Topx_Blazer_Tie', tie_mat, sft, 1.535, 1.03, .042, .078, .006, steps=18), False)
add(front_strip('Topx_Blazer_Knot', tie_mat, sft, 1.565, 1.53, .046, .034, .01, steps=3), False)

print('WARDROBE', [o.name for o in wardrobe], flush=True)
