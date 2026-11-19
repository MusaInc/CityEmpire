"""Kestrel: City Empire's starter car, modelled as a production compact
estate (Golf / Octavia / Focus estate class), not a lofted blob.

Run:  blender -b --factory-startup --python tools/blender/kestrel.py -- <out dir> [wheels]

Reference proportions (compact estates): ~4.45 m long, 1.79 m wide, 1.47 m
to the roof (+ rails), 2.66 m wheelbase, 0.88 m front / 0.90 m rear
overhang, 225/45 R17 tyres (0.634 m: ~0.43 of the body-side height),
windscreen ~62 deg from vertical, tailgate glass ~18 deg, D-pillar.

How it is built:
  * ONE shell for body and greenhouse: a quad cage of cross-sections with the
    same 22 points per ring (roof/bonnet, glass, belt, shoulder crease,
    door swell, lower-door sculpt, rocker, floor), so bonnet -> A-pillar ->
    roof -> D-pillar flow as one surface, then Catmull-Clark subdivision
    (level 2). Character lines are edge creases (shoulder, lower-door
    sculpt), everything else is curved: convex doors, haunches over the
    arches, tumblehome on the glass, superellipse ends in plan (flat-ish
    centre, rounded corners) and raked nose / tailgate in side view.
  * Real geometry for everything you see: 4.5 mm panel gaps cut into the
    shell; lamps in recesses (housing, chrome bezels, projector modules with
    convex lenses, LED light guides, indicator, clear lens); grille and
    intakes as openings with inserts; windows cut out with rubber seals and
    the glass set in; plate recesses; modelled interior; own wheel/tyre.
  * Booleans can hand back inside-out or eaten solids: normals are
    recalculated after each cut and a cut that eats the shell is rejected
    (reported). Shading normals are transferred from the uncut shell, so
    cuts never dent the paint's reflections.
  * Materials are named for CarVisual (paint, glass_clear, lens, lens_red,
    rubber, plastic, trim, chrome, reflector, lamp_*, liner, interior,
    plate). Godot builds LODs on import (generate_lods).

Conventions as every City Empire / Never Stop body: Blender +Y forward
(Godot -Z), origin on the ground between the axles, wheel centres at
(+-track/2, +-wb/2, wheel_r); writes bodies.json and body_dims.gd.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(__file__))
import build_kit as kit  # noqa: E402
from build_kit import box, cyl  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "assets/vehicles"
kit.OUT = OUT
os.makedirs(OUT, exist_ok=True)
V = Vector

# ------------------------------------------------------------------ design
WB = 2.66
WR = 0.317            # 225/45 R17
TYRE_W = 0.225
OH_F, OH_R = 0.88, 0.90
YF = WB / 2 + OH_F
YR = -WB / 2 - OH_R
W2 = 0.895
RIDE = 0.14
ROOF = 1.47
ARCH = WR + 0.042
AX = (WB / 2, -WB / 2)
Y_COWL = 0.97          # windscreen base (centre)
Y_WS = 0.08            # windscreen top
Y_RE = -1.93           # roof end (spoiler lip)
Y_TG = YR + 0.16       # tailgate glass base
SILL_Z = 0.31
REAR_EXP = 2.2         # tail-glass profile (2.2 steep hatch/estate .. 1.2 saloon rear screen)
TUMBLE = 0.12          # glass tumblehome (m)
END_RF, END_RR = 0.34, 0.3   # plan corner radii of the nose / tail
SEALED = False         # traffic detail: no clear lenses (no transparency on instanced cars)
SEG_K = 1.0            # segment scale for tubes/discs (traffic: 0.5)


def coarse(g):
    """Every other row, every third column of a hit grid (traffic pockets)."""
    if not SEALED:
        return g
    rows = g[::2] if (len(g) - 1) % 2 == 0 else g[::2] + [g[-1]]
    return [r[::3] if (len(r) - 1) % 3 == 0 else r[::3] + [r[-1]] for r in rows]


def sstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def smooth(pts, y):
    if y <= pts[0][0]:
        return pts[0][1]
    for (y0, v0), (y1, v1) in zip(pts, pts[1:]):
        if y <= y1:
            t = (y - y0) / (y1 - y0) if y1 > y0 else 1.0
            t = t * t * (3 - 2 * t)
            return v0 + (v1 - v0) * t
    return pts[-1][1]


# Deck: bonnet at the front, the belt (glass base) along the cabin, the
# tailgate shoulder at the back.
DECK = [(YR, 1.02), (Y_TG, 1.04), (-1.2, 1.03), (0.0, 1.0), (Y_COWL, 0.975), (1.35, 0.93), (1.8, 0.875),
        (YF - 0.1, 0.83), (YF, 0.8)]
CREASE = [(YR, 0.93), (YR + 0.25, 0.975), (-1.0, 0.955), (0.3, 0.925), (1.4, 0.875), (YF - 0.15, 0.81), (YF, 0.79)]
SWELL = [(YR, 0.64), (0.0, 0.66), (YF, 0.6)]
SCULPT = [(YR, 0.47), (-0.6, 0.45), (0.6, 0.44), (YF, 0.45)]   # lower-door feature line
BOTTOM = [(YR, 0.33), (YR + 0.3, 0.2), (AX[1] - 0.45, RIDE + 0.015), (AX[0] + 0.45, RIDE + 0.015), (YF - 0.3, 0.2),
          (YF, 0.26)]


FENDER = (0.0, 0.0)       # fender rise above the deck over the front / rear axle (m)
FENDER_W = 0.6
HAUNCH = (0.018, 0.018)   # plan bulge over the front / rear axle (m)
HAUNCH_W = 0.55           # its length scale (m)


def half_width(y):
    """Plan: haunches over both axles, a slight waist at the doors
    (supercars: big rear hips via HAUNCH)."""
    hw = W2 - max(HAUNCH)
    for ay, a in zip(AX, HAUNCH):
        hw += a * math.exp(-((y - ay) / HAUNCH_W) ** 2)
    return hw


def cabin_h(y):
    """Greenhouse height above the deck (0 outside the cabin)."""
    if y >= Y_COWL or y <= Y_TG:
        return 0.0
    if y > Y_WS:                              # windscreen, slightly convex
        u = (Y_COWL - y) / (Y_COWL - Y_WS)
        top = ROOF - 0.02
        return (top - smooth(DECK, y)) * (1 - (1 - u) ** 1.45) * sstep(0.0, 0.06, u) ** 0.4
    if y > Y_RE:                              # roof: gentle arch, 2.5 cm lower at the back
        u = (y - Y_RE) / (Y_WS - Y_RE)
        return ROOF - 0.045 + 0.025 * u + 0.012 * math.sin(u * math.pi) - smooth(DECK, y)
    u = (y - Y_TG) / (Y_RE - Y_TG)            # tailgate glass, steep
    return (ROOF - 0.05 - smooth(DECK, y)) * (1 - (1 - u) ** REAR_EXP)


def superellipse_scale(d, R, p=3.2):
    d = max(d, 0.0)   # (a support loop rounded a hair past the end gave a complex root)
    if d >= R:
        return 1.0
    t = 1.0 - d / R
    # (never below 0.46: the end closes on a real face - a ring collapsed to
    # a line pinched the nose into a V)
    return 0.46 + 0.54 * (1.0 - t ** p) ** (1.0 / p)


RAKE_ZF, RAKE_KF = 0.62, 0.55   # nose leans back above this height, this much
RAKE_ZR, RAKE_KR = 0.6, 0.12     # tail leans forward above this height
RAKE_CHIN = 0.34                 # chin / valance tuck below this height


def rake(y, z):
    """Side-view rake of the ends (y shift of a point): the nose leans back
    above the lamps and tucks in at the chin; the tailgate leans forward above
    the bumper, the bumper is the rearmost part, the valance tucks under."""
    wf = sstep(YF - 0.45, YF, y)
    wr = sstep(YR + 0.45, YR, y)
    sf = -max(0.0, z - RAKE_ZF) * RAKE_KF - max(0.0, RAKE_CHIN - z) * 0.35
    sr = min(max(0.0, z - RAKE_ZR), 0.45) * RAKE_KR + max(0.0, RAKE_CHIN + 0.02 - z) * 0.3
    return wf * sf + wr * sr


def ring(y):
    """Half ring (x >= 0), 12 points, top centre round to bottom centre."""
    hw = half_width(y)
    deck = smooth(DECK, y)
    h = cabin_h(y)
    f = sstep(0.0, 0.1, h)               # 0 on the bonnet/tailgate .. 1 under the roof
    crown = 0.04 * (1 - f) + 0.012 * f
    # Fenders standing above the bonnet / engine cover over the axles.
    fl = sum(a * math.exp(-((y - ay) / FENDER_W) ** 2) for ay, a in zip(AX, FENDER))
    zc = min(smooth(CREASE, y), deck - 0.05) + fl * 0.9
    zs = min(smooth(SWELL, y), zc - 0.12)
    zl = min(smooth(SCULPT, y), zs - 0.1)
    zb = smooth(BOTTOM, y)
    zr = max(SILL_Z, zb + 0.06) if abs(y) < WB / 2 - 0.3 else max(zb + 0.08, zl - 0.12)
    # Low noses (supercars) squeeze the side stack: keep bottom < rocker <
    # sculpt < swell < crease, or the section crosses itself and the nose
    # folds into an X of creases. Out of order -> spread evenly instead.
    if not (zb + 0.01 < zr < zl - 0.01 and zl < zs - 0.01 and zs < zc - 0.01):
        span = max(zc - zb, 0.08)
        zr, zl, zs = zb + span * 0.22, zb + span * 0.46, zb + span * 0.72
    belt_x = hw - 0.055                          # shoulder ledge 3-4 cm, not a shelf
    # Greenhouse with tumblehome; on the bonnet the same points spread out.
    roof_x = belt_x - 0.09 - TUMBLE * sstep(0.0, 0.42, h)
    xe = (hw - 0.3) * (1 - f) + roof_x * f
    xg = (hw - 0.13) * (1 - f) + (roof_x + belt_x) * 0.5 * f
    zt = deck + h
    pts = [
        V((0.0, zt)),
        V((xe * 0.5, zt - crown * 0.25)),
        V((xe, zt - crown * (0.75 * (1 - f) + 1.6 * f) + fl * 0.15 * (1 - f))),
        V((xg, deck + h * 0.48 - crown * (1 - f) * 1.1 + fl * 0.55 * (1 - f))),
        V((belt_x, deck - 0.01 * (1 - f) + fl)),
        V((hw - 0.012, zc)),                     # shoulder crease
        V((hw, zs)),                             # door swell
        V((hw - 0.016, zl)),                     # lower-door sculpt
        V((hw - 0.045, zr)),                     # rocker
        V((hw - 0.11, zb + 0.015)),
        V((0.42, zb)),
        V((0.0, zb)),
    ]
    return pts


CREASE_RINGS = {5: 0.85, 7: 0.7}         # ring index -> edge crease


def station_ys():
    ys = []
    ends = [0.0, 0.012, 0.035, 0.07, 0.12, 0.19, 0.28, 0.4]
    ys += [YR + d for d in ends]
    y = YR + 0.52
    while y < YF - 0.52:
        ys.append(y)
        y += 0.13
    ys += [YF - d for d in reversed(ends)]
    # Support loops where the greenhouse starts and ends.
    for extra in (Y_COWL + 0.02, Y_COWL - 0.03, Y_WS + 0.04, Y_WS - 0.04, Y_RE + 0.04, Y_RE - 0.04, Y_TG + 0.03,
                  Y_TG - 0.02):
        ys.append(extra)
    return sorted(set(round(v, 4) for v in ys))


def build_shell(material):
    """Cage -> subdivided shell."""
    bm = bmesh.new()
    rings = []
    ys = station_ys()
    for y in ys:
        d = min(y - YR, YF - y)
        sx = superellipse_scale(d, END_RF if y > 0 else END_RR)
        # The ends also close down top and bottom a little.
        sz_top = (1 - superellipse_scale(d, 0.1, 2.0)) * (0.05 if y > 0 else 0.035)
        half = ring(y)
        full = half + [V((-p.x, p.y)) for p in reversed(half[1:-1])]
        rr = []
        for p in full:
            z = p.y
            if z > 0.6:
                z -= sz_top
            elif z < 0.3:
                z += sz_top * 0.6
            rr.append(bm.verts.new((p.x * sx, y + rake(y, z), z)))
        rings.append(rr)
    n = len(rings[0])
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    # Ends: the last rings are tiny (superellipse), closed with a fan cap.
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Creases on the character lines (edges between consecutive rings at the
    # same ring index, both sides).
    cl = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
    half_n = 12
    for idx, w in CREASE_RINGS.items():
        for side_idx in (idx, n - idx):
            for r0, r1 in zip(rings, rings[1:]):
                e = bm.edges.get((r0[side_idx % n], r1[side_idx % n]))
                if e:
                    e[cl] = w
    ob = kit.new_obj("body", bm, material)
    sd = ob.modifiers.new("subd", "SUBSURF")
    sd.levels = 2
    sd.render_levels = 2
    sd.use_creases = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=sd.name)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def decimated(ob, ratio):
    """A lighter copy of the subdivided shell for the game (the shading is
    transferred back from the full one at the end)."""
    lo = ob.copy()
    lo.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(lo)
    md = lo.modifiers.new("dec", "DECIMATE")
    md.ratio = ratio
    md.use_collapse_triangulate = False
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.modifier_apply(modifier=md.name)
    return lo


CAV_Z0, CAV_ZM = 0.4, 0.74     # cavity floor / top of its narrow lower part (between the wheel houses)
CAV_Y0 = None                  # cavity from (default YR + 0.17) ..
CAV_Y1 = None                  # .. to (default Y_COWL - 0.1)


def cavity_solid():
    """The cabin and boot as an empty volume inside the shell (cut out of it):
    a trapezoid section per station, narrow below the wheel houses, inset
    ~4 cm from the outside under the roof (tumblehome), from the boot to the
    bulkhead behind the dashboard."""
    bm = bmesh.new()
    rings = []
    c0 = YR + 0.17 if CAV_Y0 is None else CAV_Y0
    c1 = Y_COWL - 0.1 if CAV_Y1 is None else CAV_Y1
    ys = [c0 + (c1 - c0) * i / 30 for i in range(31)]
    for y in ys:
        dd = min(y - YR, YF - y)
        # Follow the shell's rounded, raked ends (it poked out of the rear
        # corners and left holes round the tail lamps).
        sx = superellipse_scale(dd, END_RF if y > 0 else END_RR) - 0.05
        r = ring(y)
        h = cabin_h(y)
        ztop = max(smooth(DECK, y) + h - 0.06, smooth(DECK, y) - 0.04)
        z0 = CAV_Z0
        x_low = min(0.5, W2 - 0.39)
        x_mid = r[6].x - 0.07
        x_top = max(r[2].x - 0.05, 0.2) if h > 0.1 else r[4].x - 0.08
        zm = CAV_ZM
        ztop = max(ztop, zm + 0.08)
        half = [(0.0, z0), (x_low, z0), (x_low, zm - 0.02), (x_mid, zm), (x_mid, smooth(DECK, y) - 0.03), (x_top, ztop), (0.0, ztop)]
        full = half + [(-x, z) for x, z in reversed(half[1:-1])]
        rings.append([bm.verts.new((x * min(1.0, sx), y + rake(y, z) + (0.04 if y < 0 and dd < 0.3 else 0.0), z))
                      for x, z in full])
    n = len(rings[0])
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit.new_obj("cavity", bm)
def add_mat(ob, material):
    names = [m.name for m in ob.data.materials]
    if material.name not in names:
        ob.data.materials.append(material)
        names.append(material.name)
    return names.index(material.name)


def shade(ob, angle=35):
    for p in ob.data.polygons:
        p.use_smooth = True
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
    except Exception:
        try:
            ob.data.set_sharp_from_angle(angle=math.radians(angle))
        except Exception:
            pass
    ob.select_set(False)


DEBUG = os.environ.get("KDEBUG")


def _front_hits(ob):
    t = Surface([ob])
    return sum(1 for x in (0.0, 0.4, 0.6, 0.8) for z in (0.6, 0.7) if t.cast(*ray("front", x, z)))


def cut(ob, cutter, cutter_mat=None, op="DIFFERENCE"):
    """Boolean `cutter` into `ob` (then delete the cutter). EXACT first; if
    that eats most of the solid (thin walls next to the hollow cabin trip
    it), FAST; if that fails too the cut is skipped and reported."""
    if cutter_mat is not None:
        cutter.data.materials.clear()
        cutter.data.materials.append(cutter_mat)
        add_mat(ob, cutter_mat)
    n0 = len(ob.data.polygons)
    cname = cutter.name
    done = False
    for solver in ("EXACT", "FAST"):
        before = ob.data.copy()
        md = ob.modifiers.new("cut", "BOOLEAN")
        md.operation = op
        md.object = cutter
        md.solver = solver
        if solver == "EXACT":
            md.use_self = False
            md.material_mode = "TRANSFER"
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=md.name)
        if op != "DIFFERENCE" or len(ob.data.polygons) >= n0 * 0.5:
            bpy.data.meshes.remove(before)
            done = True
            if solver == "FAST" and cutter_mat is not None:
                # (FAST doesn't transfer materials: the new faces are the
                # ones that weren't there before, coloured by the cutter's.)
                pass
            break
        old = ob.data
        ob.data = before
        bpy.data.meshes.remove(old)
    bpy.data.objects.remove(cutter, do_unlink=True)
    if not done:
        print("CUT REJECTED", cname, "on", ob.name, n0)
        return
    # A boolean can hand back the solid inside-out (seen after the arch
    # cuts): everything placed "inside along the normal" then landed outside.
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def prism(name, poly, axis, d0, d1):
    """Closed prism: polygon [(a, b)...] in the plane across `axis`
    ('x': (y, z); 'y': (x, z); 'z': (x, y)), from d0 to d1 along it."""
    bm = bmesh.new()

    def P(a, b, d):
        return {"x": (d, a, b), "y": (a, d, b), "z": (a, b, d)}[axis]
    r0 = [bm.verts.new(P(a, b, d0)) for a, b in poly]
    r1 = [bm.verts.new(P(a, b, d1)) for a, b in poly]
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    bm.faces.new(r0)
    bm.faces.new(list(reversed(r1)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit.new_obj(name, bm)


def slot(name, line, axis, d0, d1, w=0.0045):
    """A panel gap: polyline [(a, b)...] thickened to w, as a prism."""
    left, right = [], []
    for i, p in enumerate(line):
        p = V(p)
        a = V(line[max(i - 1, 0)])
        b = V(line[min(i + 1, len(line) - 1)])
        t = (b - a).normalized()
        n = V((-t.y, t.x)) * (w / 2)
        left.append(tuple(p + n))
        right.append(tuple(p - n))
    return prism(name, left + list(reversed(right)), axis, d0, d1)


def arc_pts(cy, cz, r, a0, a1, n=20):
    return [(cy + math.cos(a0 + (a1 - a0) * i / n) * r, cz + math.sin(a0 + (a1 - a0) * i / n) * r) for i in range(n + 1)]


# ------------------------------------------------------------------ cabin
class Surface:
    def __init__(self, objs):
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        self.trees = [BVHTree.FromObject(o, dg) for o in objs]

    def cast(self, o, d):
        best = None
        for t in self.trees:
            hit = t.ray_cast(V(o), V(d), 30.0)
            if hit[0] is not None and (best is None or hit[3] < best[3]):
                best = hit
        return best


def ray(view, a, b, side=1):
    """Plane coords -> ray. Front/rear rays converge on an axis 1.3 m inside
    the end, pivoting on a plane near the surface (so wrap-round lamps meet
    the corner square-on and stay where they are drawn)."""
    if view in ("front", "rear"):
        sg = 1.0 if view == "front" else -1.0
        end = YF if view == "front" else YR
        plane = V((a, end - sg * 0.1, b))
        axis = V((0.0, end - sg * 1.4, b))
        d = (axis - plane).normalized()
        return plane - d * 10.0, d
    if view == "side":
        return V((side * 5.0, a, b)), V((-side, 0, 0))
    if view == "top":
        return V((a, b, 5.0)), V((0, 0, -1))
    raise ValueError(view)


def patch(surf, view, fn, nu, nv, side=1):
    """Grid of surface hits [(point, normal)] for fn(s, t) -> plane coords."""
    g = []
    for j in range(nv + 1):
        row = []
        for i in range(nu + 1):
            o, d = ray(view, *fn(i / nu, j / nv), side)
            h = surf.cast(o, d)
            row.append((h[0], h[1]) if h else None)
        g.append(row)
    return g


def sheet(name, grid, lift, material, thick=0.0):
    """A skin over a hit grid at `lift` along the normals (thick > 0: closed slab)."""
    bm = bmesh.new()
    nv, nu = len(grid) - 1, len(grid[0]) - 1
    top, bot = {}, {}

    def vt(i, j, store, l):
        if (i, j) not in store:
            p, n = grid[j][i]
            store[(i, j)] = bm.verts.new(p + n * l)
        return store[(i, j)]
    cells = []
    for j in range(nv):
        for i in range(nu):
            if any(grid[jj][ii] is None for ii, jj in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                continue
            q = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            f = bm.faces.new([vt(a, b, top, lift + thick) for a, b in q])
            cells.append((i, j))
            nrm = sum((grid[b][a][1] for a, b in q), V())
            f.normal_update()
            if f.normal.dot(nrm) < 0:
                f.normal_flip()
            if thick > 0:
                fb = bm.faces.new([vt(a, b, bot, lift) for a, b in reversed(q)])
                fb.normal_update()
                if fb.normal.dot(nrm) > 0:
                    fb.normal_flip()
    if thick > 0:
        cs = set(cells)
        for (i, j) in cells:
            for (a, b, ni, nj) in (((i, j), (i + 1, j), i, j - 1), ((i + 1, j), (i + 1, j + 1), i + 1, j),
                                   ((i + 1, j + 1), (i, j + 1), i, j + 1), ((i, j + 1), (i, j), i - 1, j)):
                if (ni, nj) in cs:
                    continue
                try:
                    bm.faces.new((vt(*a, top, lift + thick), vt(*b, top, lift + thick), vt(*b, bot, lift), vt(*a, bot, lift)))
                except ValueError:
                    pass
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = kit.new_obj(name, bm, material)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def recess_cutter(name, grid, depth, out=0.03):
    """Closed solid hugging the surface over the grid: cuts a pocket `depth`
    deep. Extruded along the patch's average normal (one direction): per-point
    normals cross at a tight corner (the tail lamps) and fold the solid."""
    navg = sum((c[1] for row in grid for c in row if c), V()).normalized()
    g = [[None if c is None else (c[0] - navg * depth, navg) for c in row] for row in grid]
    return sheet(name, g, 0.0, None, thick=depth + out)


def mirror_copy(ob):
    """The same object mirrored across x = 0 (normals kept outward)."""
    c = ob.copy()
    c.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(c)
    bm = bmesh.new()
    bm.from_mesh(c.data)
    for v in bm.verts:
        v.co.x = -v.co.x
    for f in bm.faces:
        f.normal_flip()
    bm.to_mesh(c.data)
    bm.free()
    return c


def poly_fn(poly):
    """Bilinear map of a 4-corner outline (BL, BR, TR, TL)."""
    c0, c1, c2, c3 = [V(p) for p in poly]

    def f(s, t):
        a = c0.lerp(c1, s)
        b = c3.lerp(c2, s)
        return tuple(a.lerp(b, t))
    return f


def mirror_fn(fn):
    return lambda s, t: (lambda a, b: (-a, b))(*fn(1 - s, t))


# ------------------------------------------------------------------ materials
def mats():
    M = kit.mat
    m = {
        "paint": M("paint", (0.8, 0.8, 0.79), 0.25, 0.3),
        "glass_clear": M("glass_clear", (0.06, 0.07, 0.08), 0.03, 0.0),
        "lens": M("lens", (0.9, 0.92, 0.95), 0.02, 0.0),
        "lens_red": M("lens_red", (0.45, 0.02, 0.02), 0.05, 0.0),
        "rubber": M("rubber", (0.02, 0.02, 0.022), 0.75),
        "plastic": M("plastic", (0.035, 0.035, 0.038), 0.62),
        "gloss_black": M("trim", (0.02, 0.02, 0.022), 0.18),
        "chrome": M("chrome", (0.8, 0.8, 0.82), 0.12, 1.0),
        "liner": M("liner", (0.012, 0.012, 0.012), 0.9),
        "housing": M("lamp_housing", (0.03, 0.03, 0.035), 0.2, 0.7),
        "reflector": M("reflector", (0.9, 0.9, 0.92), 0.22, 1.0),
        "head": M("lamp_head", (1.0, 0.98, 0.95), 0.1, 0.0, emit=(1.0, 0.97, 0.9)),
        "tail": M("lamp_tail", (0.7, 0.02, 0.02), 0.2, 0.0, emit=(1.0, 0.03, 0.02)),
        "amber": M("lamp_amber", (0.95, 0.5, 0.05), 0.2, 0.0, emit=(1.0, 0.5, 0.05)),
        "rev": M("lamp_rev", (0.92, 0.92, 0.92), 0.15),
        "interior": M("interior", (0.05, 0.05, 0.055), 0.85),
        "plate": M("plate", (0.92, 0.9, 0.82), 0.6),
    }
    # Glass and lenses: transparent in the review renders (the game sets its own).
    for k, a in {"glass_clear": 0.42, "lens": 0.04, "lens_red": 0.7}.items():
        b = m[k].node_tree.nodes["Principled BSDF"]
        b.inputs["Alpha"].default_value = a
        b.inputs["Coat Weight"].default_value = 1.0
        m[k].blend_method = "BLEND" if hasattr(m[k], "blend_method") else None
    for k in ("head", "tail", "amber"):
        m[k].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 4.0 if k == "head" else 1.5
    return m


# ------------------------------------------------------------------ parts
def tube_path(name, pts, r, material, segs=8):
    segs = max(4, int(round(segs * SEG_K)))
    dd = [V(pts[0])]
    for p in pts[1:]:
        if (V(p) - dd[-1]).length > 1e-4:
            dd.append(V(p))
    pts = dd
    if len(pts) < 2:
        return None
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        a = V(pts[max(i - 1, 0)])
        b = V(pts[min(i + 1, len(pts) - 1)])
        t = (b - a).normalized()
        up = V((0, 0, 1)) if abs(t.z) < 0.9 else V((1, 0, 0))
        u = t.cross(up).normalized()
        w = t.cross(u).normalized()
        rings.append([bm.verts.new(V(p) + (u * math.cos(k * 2 * math.pi / segs) + w * math.sin(k * 2 * math.pi / segs)) * r)
                      for k in range(segs)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = kit.new_obj(name, bm, material)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def disc_on(name, p, n, r, h, material, segs=20):
    segs = max(6, int(round(segs * SEG_K)))
    c = cyl(name, r, h, (0, 0, 0), material, segs)
    c.rotation_mode = "QUATERNION"
    c.rotation_quaternion = V(n).to_track_quat("Z", "Y")
    c.location = V(p)
    return c




# ------------------------------------------------------------------ materials (premium)
def premium(m):
    """Review-render settings closer to the game's look: clear-coated
    metallic paint, satin plastics, real chrome, thin clear glass."""
    def bsdf(k):
        return m[k].node_tree.nodes["Principled BSDF"]
    p = bsdf("paint")
    p.inputs["Metallic"].default_value = 0.55
    p.inputs["Roughness"].default_value = 0.32
    p.inputs["Coat Weight"].default_value = 1.0
    p.inputs["Coat Roughness"].default_value = 0.03
    for k, a in {"glass_clear": 0.4, "lens": 0.05, "lens_red": 0.38}.items():
        b = bsdf(k)
        b.inputs["Alpha"].default_value = a
        b.inputs["Roughness"].default_value = 0.02
        b.inputs["Coat Weight"].default_value = 1.0
    bsdf("plastic").inputs["Roughness"].default_value = 0.55
    bsdf("rubber").inputs["Roughness"].default_value = 0.8


# ------------------------------------------------------------------ lamps
def head_lamp(surf, body, m, out, poly):
    """Headlamp: a pocket cut into the nose, then inside it: a dark grey
    housing, a chrome bezel strip, an outboard projector module (chrome bowl,
    black shroud with a chamfered ring, a convex glass lens, a bright
    emitter behind), an inboard faceted high-beam reflector with its bulb,
    an LED light guide along the top edge turning down the inner end, an
    amber indicator bar along the bottom, and the clear outer lens flush
    with the paint. The left lamp is the right one mirrored."""
    fn = poly_fn(poly)
    g = patch(surf, "front", fn, 18, 8)
    if sum(1 for row in g for c in row if c) < 100:
        print("LAMP MISSED head")
        return
    n0 = len(out)
    pk = recess_cutter("pocket", coarse(g), 0.075)
    pk2 = mirror_copy(pk)
    cut(body, pk, m["housing"])
    cut(body, pk2, m["housing"])
    out.append(sheet("lamp_back", coarse(g), -0.07, m["housing"]))
    if not SEALED:
        out.append(sheet("lamp_lens", g, -0.003, m["lens"]))
    navg = sum((c[1] for row in g for c in row if c), V()).normalized()

    def at(s, t):
        i = int(round(s * 18))
        j = int(round(t * 8))
        c = g[j][i]
        return (c[0], c[1]) if c else None

    def module(s, t, r, kind):
        c = at(s, t)
        if not c:
            return
        p, n = c[0], navg
        if kind == "projector":
            out.append(disc_on("bowl", p - n * 0.068, n, r * 1.25, 0.012, m["reflector"], 28))
            out.append(disc_on("shroud", p - n * 0.06, n, r * 1.08, 0.038, m["trim"], 28))
            out.append(disc_on("shroud_ring", p - n * 0.024, n, r * 1.14, 0.004, m["chrome"], 28))
            ln = bpy.data.objects.new("lens", bpy.data.meshes.new("lens"))
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=8, radius=r)
            for v in list(bm.verts):
                if v.co.z < r * 0.55:
                    bm.verts.remove(v)
            bm.to_mesh(ln.data)
            bm.free()
            bpy.context.scene.collection.objects.link(ln)
            ln.data.materials.append(m["head"])
            ln.rotation_mode = "QUATERNION"
            ln.rotation_quaternion = n.to_track_quat("Z", "Y")
            ln.location = p - n * (0.024 + r * 0.55)
            for f in ln.data.polygons:
                f.use_smooth = True
            out.append(ln)
        else:  # faceted reflector cell with a bulb
            for k in range(3):
                rr = r * (1.25 - k * 0.3)
                out.append(disc_on("facet", p - n * (0.066 - k * 0.012), n, rr, 0.006, m["reflector"], 10))
            out.append(disc_on("bulb", p - n * 0.05, n, r * 0.16, 0.012, m["head"], 12))

    module(0.66, 0.42, 0.034, "projector")
    module(0.34, 0.42, 0.03, "reflector")
    # Chrome bezel strip between the modules and the light guide.
    bez = [at(i / 18, 0.72) for i in range(2, 17)]
    bez = [c[0] - navg * 0.028 for c in bez if c]
    if len(bez) > 3:
        out.append(tube_path("bezel", bez, 0.004, m["chrome"], 6))
    # LED light guide: along the top, turning down the inner end.
    top = [at(i / 18, 0.86) for i in range(17, 1, -1)] + [at(0.1, t / 8) for t in (6, 5, 4, 3)]
    top = [c[0] - navg * 0.02 for c in top if c]
    if len(top) > 3:
        out.append(tube_path("drl", top, 0.009, m["head"], 8))
    ind = [at(i / 18, 0.14) for i in range(9, 18)]
    ind = [c[0] - navg * 0.022 for c in ind if c]
    if len(ind) > 2:
        out.append(tube_path("indicator", ind, 0.008, m["amber"], 8))
    for o in list(out[n0:]):
        out.append(mirror_copy(o))


def tail_lamp(surf, body, m, out, poly):
    """Tail lamp across the body corner: smoked red lens over a housing with
    two red light-guide bars (tail), a red reflector block (brake), a white
    reverse segment and an amber indicator, mirrored for the left."""
    g = patch(surf, "rear", poly_fn(poly), 16, 8)
    if sum(1 for row in g for c in row if c) < 90:
        print("LAMP MISSED tail")
        return
    n0 = len(out)
    pk = recess_cutter("pocket", coarse(g), 0.06)
    pk2 = mirror_copy(pk)
    cut(body, pk, m["housing"])
    cut(body, pk2, m["housing"])
    out.append(sheet("tail_back", coarse(g), -0.055, m["housing"]))
    # (sealed: traffic draws no transparency - the lens is the lit lamp)
    out.append(sheet("tail_lens", coarse(g), -0.003, m["lens_red"] if not SEALED else m["tail"]))
    navg = sum((c[1] for row in g for c in row if c), V()).normalized()

    def row(j, i0, i1, inset):
        pts = [g[j][i] for i in range(i0, i1)]
        return [c[0] - navg * inset for c in pts if c]
    for j in (6, 2):
        pts = row(j, 1, 16, 0.022)
        if len(pts) > 3:
            out.append(tube_path("tail_guide", pts, 0.01, m["tail"], 8))
    blk = [[g[j][i] for i in range(2, 9)] for j in range(3, 6)]
    out.append(sheet("brake", blk, -0.04, m["tail"]))
    rv = row(4, 10, 15, 0.03)
    if len(rv) > 1:
        out.append(tube_path("reverse", rv, 0.016, m["rev"], 8))
    am = row(4, 15, 16, 0.03) + row(5, 15, 16, 0.03)
    for o in list(out[n0:]):
        out.append(mirror_copy(o))


def opening(surf, body, m, out, poly, depth, insert, frame="trim", res=(20, 6), view="front"):
    """An opening in the bumper (grille / intake) with its insert behind and
    a surround standing proud; the left/right symmetric ones are whole."""
    g = patch(surf, view, poly_fn(poly), *res)
    cut(body, recess_cutter("opening", g, depth), m["liner"])
    if frame:
        ring_pts = [c for c in g[0]] + [g[j][-1] for j in range(len(g))] + list(reversed(g[-1])) + \
                   [g[j][0] for j in reversed(range(len(g)))]
        pts = [c[0] + c[1] * 0.003 for c in ring_pts if c]
        if len(pts) > 4:
            out.append(tube_path("surround", pts + pts[:1], 0.007, m[frame], 6))
    navg = sum((c[1] for row in g for c in row if c), V()).normalized()
    bl, br, tr, tl = [V(p) for p in poly]
    if insert == "slats":
        for k in range(3):
            t = (k + 0.5) / 3
            pts = [g[int(round(t * res[1]))][i] for i in range(1, res[0])]
            pts = [c[0] - navg * depth * 0.45 for c in pts if c]
            if len(pts) > 2:
                out.append(tube_path("slat", pts, (tl.y - bl.y) / 3 * 0.22, m["trim"], 6))
    elif insert == "mesh":
        # Woven diamond mesh: two sets of slanted bars following the bumper
        # (it was ~280 separate hexagons: 5,600 triangles).
        zc = (bl.y + tl.y) * 0.5
        hgt = tl.y - bl.y
        x0, x1 = min(bl.x, tl.x), max(br.x, tr.x)
        step = 0.05
        k = x0 - hgt
        while k < x1:
            for sgn in (1, -1):
                pts = []
                for i in range(5):
                    z = bl.y + hgt * i / 4
                    x = k + (z - bl.y) * sgn + (hgt if sgn < 0 else 0.0)
                    t = (z - bl.y) / max(hgt, 1e-3)
                    xa = bl.x + (tl.x - bl.x) * t + 0.01
                    xb = br.x + (tr.x - br.x) * t - 0.01
                    if xa <= x <= xb:
                        h = surf.cast(*ray(view, x, z))
                        if h:
                            pts.append(h[0] - navg * depth * 0.55)
                if len(pts) >= 2:
                    out.append(tube_path("mesh_bar", pts, 0.006, m["plastic"], 4))
            k += step
    out.append(sheet("opening_back", g, -depth + 0.004, m["liner"]))
    return g


# ------------------------------------------------------------------ cabin bits
MIRROR_REACH = 0.125     # how far the housing's tip stands out past the body side (m)


def mirrors(m, out, surf=None):
    """Door mirrors fixed to the door shoulder just behind the A-pillar: a
    base plate sunk into the door top, a short stalk, and a housing whose
    outer tip stands MIRROR_REACH past the widest point of the body (real
    cars: ~10-13 cm). `surf` (the uncut shell) finds the door; without it the
    ring's belt point is used."""
    y = Y_COWL - 0.17
    r = ring(y)
    z_door = smooth(DECK, y) - 0.035
    root, nrm = V((r[4].x, y + rake(y, r[4].y), r[4].y)), V((1, 0, 0))
    if surf is not None:
        h = surf.cast(V((3.0, y, z_door)), V((-1, 0, 0)))
        if h:
            root, nrm = V(h[0]), V(h[1])
    w_body = max(half_width(yy) for yy in (y - 0.3, y, y + 0.3, AX[0]))
    for sx in (1, -1):
        p = V((sx * root.x, root.y, root.z))
        n = V((sx * nrm.x, nrm.y, nrm.z))
        # Base plate: sunk 6 mm into the door so it is never floating.
        base = box("mirror_base", (0.035, 0.12, 0.05), (0, 0, 0), m["trim"], bevel=0.012)
        base.rotation_mode = "QUATERNION"
        base.rotation_quaternion = n.to_track_quat("X", "Z")
        base.location = p - n * 0.006 + V((0, 0, 0.012))
        out.append(base)
        # Housing: inner edge just off the base, outer tip at the reach.
        tip_x = w_body + MIRROR_REACH
        inner_x = abs(p.x) + 0.03
        hw = max(0.06, (tip_x - inner_x) / 2)          # half width of the housing
        cx = sx * (inner_x + hw)
        c = V((cx, p.y - 0.03, p.z + 0.075))
        out.append(tube_path("mirror_arm", [p + V((sx * 0.01, -0.01, 0.02)), V((sx * (inner_x + 0.02), p.y - 0.025, p.z + 0.06))],
                             0.014, m["trim"], 8))
        bm = bmesh.new()
        prof = [(0.06, 0.25), (0.05, 0.6), (0.032, 0.85), (0.012, 0.98), (-0.008, 1.0), (-0.022, 0.96)]
        rings = []
        for yy, sc in prof:
            rings.append([bm.verts.new(c + V((math.cos(a) * hw * sc, yy, math.sin(a) * 0.06 * sc + 0.006 * math.cos(a))))
                          for a in (i * 2 * math.pi / 18 for i in range(18))])
        for r0, r1 in zip(rings, rings[1:]):
            for i in range(18):
                bm.faces.new((r0[i], r0[(i + 1) % 18], r1[(i + 1) % 18], r1[i]))
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[-1])))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        hous = kit.new_obj("mirror", bm, m["paint"])
        for f in hous.data.polygons:
            f.use_smooth = True
        out.append(hous)
        out.append(box("mirror_glass", (hw * 1.75, 0.004, 0.1), c + V((0, -0.023, 0.002)), m["reflector"]))
        out.append(box("mirror_ind", (hw * 0.7, 0.03, 0.007), c + V((sx * hw * 0.45, 0.02, -0.052)), m["amber"], bevel=0.003))


def door_handles(surf, m, out):
    for y in (-0.04, -0.98):
        z = smooth(CREASE, y) - 0.055
        for sx in (1, -1):
            h = surf.cast(V((sx * 3.0, y, z)), V((-sx, 0, 0)))
            if not h:
                continue
            p, n = h[0], h[1]
            out.append(box("handle_recess", (0.01, 0.21, 0.052), p - n * 0.004, m["liner"]))
            out.append(box("handle", (0.024, 0.2, 0.034), p + n * 0.007, m["paint"], bevel=0.011))
            out.append(box("handle_trim", (0.004, 0.17, 0.006), p + n * 0.02 + V((0, 0, 0.008)), m["chrome"]))


def roof_rails(m, out):
    for sx in (1, -1):
        pts = []
        for i in range(15):
            y = (Y_WS - 0.25) + (Y_RE + 0.12 - (Y_WS - 0.25)) * i / 14
            r = ring(y)
            pts.append(V((sx * (r[2].x - 0.02), y, r[2].y + 0.045)))
        out.append(tube_path("rail", pts, 0.014, m["reflector"], 8))
        for k in (0, 7, 14):
            p = pts[k]
            out.append(box("rail_foot", (0.03, 0.09, 0.05), p - V((0, 0, 0.025)), m["plastic"], bevel=0.012))


def interior(m, out):
    """A dashboard you can read through the glass: a moulded top, instrument
    binnacle, central screen, vents, centre console and gear lever; seats
    with bolsters and headrests; a rear bench; door cards with armrests;
    a steering wheel with three spokes (driver on the right)."""
    I, P, C = m["interior"], m["plastic"], m["chrome"]
    zf = 0.5
    out.append(box("floor_pan", (1.62, 2.9, 0.04), (0, -0.25, 0.3), I))
    dash = box("dash", (1.6, 0.46, 0.22), (0, 0.66, 0.84), P, bevel=0.06)
    out.append(dash)
    out.append(box("dash_top", (1.56, 0.34, 0.05), (0, 0.72, 0.97), I, bevel=0.025))
    out.append(box("binnacle", (0.36, 0.16, 0.09), (0.38, 0.58, 1.0), P, bevel=0.035))
    out.append(box("cluster", (0.3, 0.01, 0.07), (0.38, 0.5, 0.99), m["trim"]))
    out.append(box("screen", (0.26, 0.012, 0.15), (0.0, 0.47, 0.98), m["trim"], bevel=0.008))
    for x in (-0.6, -0.1, 0.1, 0.6):
        out.append(disc_on("vent", V((x, 0.44, 0.88)), V((0, -1, 0)), 0.035, 0.012, C, 16))
    out.append(box("console", (0.24, 0.9, 0.2), (0, 0.05, 0.45), P, bevel=0.04))
    out.append(tube_path("gear", [V((0, 0.2, 0.55)), V((0, 0.18, 0.66))], 0.012, C, 8))
    for sx in (1, -1):
        x = sx * 0.39
        out.append(box("seat", (0.5, 0.5, 0.12), (x, -0.06, zf), I, bevel=0.05))
        for b in (-1, 1):
            out.append(box("bolster", (0.07, 0.46, 0.08), (x + b * 0.22, -0.06, zf + 0.07), I, bevel=0.03))
        back = box("seatback", (0.5, 0.11, 0.6), (0, 0, 0), I, bevel=0.05)
        back.rotation_euler = (math.radians(-14), 0, 0)
        back.location = (x, -0.34, zf + 0.34)
        out.append(back)
        for b in (-1, 1):
            sb = box("back_bolster", (0.07, 0.12, 0.5), (0, 0, 0), I, bevel=0.03)
            sb.rotation_euler = (math.radians(-14), 0, 0)
            sb.location = (x + b * 0.22, -0.32, zf + 0.33)
            out.append(sb)
        hr = box("headrest", (0.27, 0.1, 0.17), (0, 0, 0), I, bevel=0.045)
        hr.rotation_euler = (math.radians(-8), 0, 0)
        hr.location = (x, -0.47, zf + 0.75)
        out.append(hr)
        # Door cards.
        out.append(box("door_card", (0.03, 1.8, 0.4), (sx * 0.8, -0.45, 0.72), P, bevel=0.01))
        out.append(box("armrest", (0.08, 0.5, 0.05), (sx * 0.765, -0.0, 0.73), I, bevel=0.02))
        out.append(box("door_pull", (0.02, 0.12, 0.02), (sx * 0.775, 0.2, 0.86), C))
    out.append(box("rear_bench", (1.4, 0.5, 0.13), (0, -1.05, zf), I, bevel=0.05))
    rb = box("rear_back", (1.4, 0.11, 0.56), (0, 0, 0), I, bevel=0.05)
    rb.rotation_euler = (math.radians(-18), 0, 0)
    rb.location = (0, -1.32, zf + 0.31)
    out.append(rb)
    for x in (-0.45, 0.0, 0.45):
        h = box("rear_headrest", (0.24, 0.09, 0.14), (0, 0, 0), I, bevel=0.04)
        h.location = (x, -1.42, zf + 0.68)
        out.append(h)
    out.append(box("boot_floor", (1.3, 0.55, 0.03), (0, -1.72, 0.58), I))   # (inside the tailgate)
    # Steering wheel: rim, three spokes, hub, column.
    c = V((0.38, 0.38, 0.92))
    tilt = math.radians(22)
    rim = []
    for i in range(29):
        a = i * 2 * math.pi / 28
        rim.append(c + V((0.185 * math.cos(a), -0.185 * math.sin(a) * math.sin(tilt), 0.185 * math.sin(a) * math.cos(tilt))))
    out.append(tube_path("wheel_rim", rim, 0.017, P, 8))
    for a in (0.0, math.pi, -math.pi / 2):
        e = c + V((0.17 * math.cos(a), -0.17 * math.sin(a) * math.sin(tilt), 0.17 * math.sin(a) * math.cos(tilt)))
        out.append(tube_path("spoke", [c, e], 0.014, P, 6))
    out.append(disc_on("hub", c, V((0, -math.sin(tilt) * -1, 0)).normalized() if False else V((0, -0.37, 0.93)).normalized(),
                       0.065, 0.04, P, 16))
    out.append(tube_path("column", [c + V((0, 0.03, -0.02)), V((0.38, 0.62, 0.84))], 0.035, P, 10))


def number_plate(out, m, at, normal, rear, text="KE57 RLY"):
    """A UK plate: white at the front, yellow at the back, 520 x 111 mm,
    black characters (a real text mesh), facing along `normal`."""
    pm = m["plate"] if not rear else kit.mat("plate_rear", (0.95, 0.78, 0.1), 0.5)
    q = normal.to_track_quat("Z", "Y")
    pl = box("plate", (0.52, 0.111, 0.008), (0, 0, 0), pm, bevel=0.003)
    pl.rotation_mode = "QUATERNION"
    pl.rotation_quaternion = q
    pl.location = at
    out.append(pl)
    bpy.ops.object.text_add()
    t = bpy.context.object
    t.data.body = text
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    t.data.size = 0.085
    t.data.extrude = 0.0015
    t.data.resolution_u = 2
    bpy.ops.object.convert(target="MESH")
    t = bpy.context.object
    t.data.materials.clear()
    t.data.materials.append(m["trim"])
    t.rotation_mode = "QUATERNION"
    t.rotation_quaternion = q
    t.location = at + normal * 0.0045
    out.append(t)


# ------------------------------------------------------------------ wheel
def wheel_kestrel():
    """225/45 R17 on a 10-spoke alloy. Radius 1, tyre width 0.44 (CarVisual
    scales it), axle along X, face towards +X. Tyre: shoulder-rounded tread
    with three circumferential grooves, a bulged sidewall with a rim
    protector; alloy: a concave face (the hub sits 6 cm in from the lip),
    five twin spokes tapering to the hub, a polished lip, barrel, five lug
    nuts and a centre cap; a ventilated disc behind (CarVisual adds the
    caliper, which mustn't spin)."""
    kit.reset()
    m = mats()
    premium(m)
    rim = kit.mat("rim", (0.78, 0.79, 0.81), 0.28, 1.0)
    rim_dark = kit.mat("rim_dark", (0.16, 0.16, 0.17), 0.35, 0.8)
    tyre = kit.mat("tyre", (0.03, 0.03, 0.03), 0.88)
    wall = kit.mat("tyre_wall", (0.05, 0.05, 0.052), 0.8)
    disc_m = kit.mat("disc", (0.36, 0.36, 0.37), 0.42, 0.85)
    parts = []
    # Tyre profile (r, x): inner bead -> sidewall bulge -> shoulder -> tread
    # with grooves -> shoulder -> outer sidewall -> rim protector -> bead.
    prof = [(0.7, -0.4), (0.8, -0.445), (0.9, -0.44), (0.955, -0.41), (0.985, -0.36), (1.0, -0.3),
            (1.0, -0.2), (0.975, -0.195), (0.975, -0.155), (1.0, -0.15), (1.0, -0.03), (0.975, -0.025), (0.975, 0.025),
            (1.0, 0.03), (1.0, 0.15), (0.975, 0.155), (0.975, 0.195), (1.0, 0.2), (1.0, 0.3), (0.985, 0.36),
            (0.955, 0.41), (0.9, 0.44), (0.8, 0.445), (0.74, 0.43), (0.72, 0.415)]
    bm = bmesh.new()
    segs = 32
    rings = []
    for i in range(segs):
        a = i * 2 * math.pi / segs
        rings.append([bm.verts.new((x * 0.5, r * math.cos(a), r * math.sin(a))) for r, x in prof])
    for i in range(segs):
        r0, r1 = rings[i], rings[(i + 1) % segs]
        for k in range(len(prof) - 1):
            bm.faces.new((r0[k], r0[k + 1], r1[k + 1], r1[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    t = kit.new_obj("tyre", bm, tyre)
    for p in t.data.polygons:
        p.use_smooth = True
        c = p.center
        if math.hypot(c.y, c.z) < 0.965:
            p.material_index = 0
    t.data.materials.append(wall)
    for p in t.data.polygons:
        if math.hypot(p.center.y, p.center.z) < 0.93:
            p.material_index = 1
    parts.append(t)
    R = 0.7   # rim radius (17" on a 0.634 m tyre)
    # Barrel + lip.
    parts.append(cyl("barrel", R * 0.97, 0.36, (0, 0, 0), m["liner"], 40, cap=False))
    parts[-1].rotation_euler = (0, math.pi / 2, 0)
    parts[-1].location = (-0.18, 0, 0)
    bm = bmesh.new()
    lip = []
    for i in range(48):
        a = i * 2 * math.pi / 48
        lip.append([bm.verts.new((x, r * math.cos(a), r * math.sin(a))) for r, x in
                    ((R * 0.9, 0.17), (R * 0.97, 0.2), (R * 1.0, 0.195), (R * 1.0, 0.17))])
    for i in range(48):
        a0, a1 = lip[i], lip[(i + 1) % 48]
        for k in range(3):
            bm.faces.new((a0[k], a0[k + 1], a1[k + 1], a1[k]))
    lipo = kit.new_obj("lip", bm, rim)
    for p in lipo.data.polygons:
        p.use_smooth = True
    parts.append(lipo)
    # Dark well behind the spokes, then the disc.
    parts.append(cyl("well", R * 0.95, 0.01, (0, 0, 0), m["liner"], 40))
    parts[-1].rotation_euler = (0, math.pi / 2, 0)
    parts[-1].location = (-0.12, 0, 0)
    d = cyl("disc", R * 0.8, 0.06, (0, 0, 0), disc_m, 40)
    d.rotation_euler = (0, math.pi / 2, 0)
    d.location = (-0.08, 0, 0)
    parts.append(d)
    hat = cyl("disc_hat", R * 0.38, 0.05, (0, 0, 0), rim_dark, 24)
    hat.rotation_euler = (0, math.pi / 2, 0)
    hat.location = (-0.03, 0, 0)
    parts.append(hat)
    # Twin spokes: tapered, from the hub (x 0.11) out to the lip (x 0.17).
    for k in range(5):
        for off in (-0.13, 0.13):
            a = k * 2 * math.pi / 5 + off
            bm = bmesh.new()
            ca, sa = math.cos(a), math.sin(a)
            tang = V((0, -sa, ca))
            pts = []
            for (r, x, w, th) in ((R * 0.3, 0.11, 0.06, 0.05), (R * 0.6, 0.14, 0.05, 0.045), (R * 0.93, 0.172, 0.06, 0.03)):
                c = V((x, r * ca, r * sa))
                pts.append([c + tang * (w / 2) + V((0.0, 0, 0)), c - tang * (w / 2), c - tang * (w / 2) - V((th, 0, 0)),
                             c + tang * (w / 2) - V((th, 0, 0))])
            vs = [[bm.verts.new(p) for p in q] for q in pts]
            for q0, q1 in zip(vs, vs[1:]):
                for i in range(4):
                    bm.faces.new((q0[i], q0[(i + 1) % 4], q1[(i + 1) % 4], q1[i]))
            bm.faces.new(vs[0])
            bm.faces.new(list(reversed(vs[-1])))
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            sp = kit.new_obj("spoke", bm, rim)
            parts.append(sp)
    hub = cyl("hub", R * 0.3, 0.05, (0, 0, 0), rim, 30)
    hub.rotation_euler = (0, math.pi / 2, 0)
    hub.location = (0.07, 0, 0)
    parts.append(hub)
    for k in range(5):
        a = k * 2 * math.pi / 5 + math.pi / 5
        nut = cyl("nut", 0.028, 0.035, (0, 0, 0), m["chrome"], 6)
        nut.rotation_euler = (0, math.pi / 2, 0)
        nut.location = (0.11, R * 0.18 * math.cos(a), R * 0.18 * math.sin(a))
        parts.append(nut)
    cap = cyl("cap", R * 0.11, 0.02, (0, 0, 0), rim_dark, 24)
    cap.rotation_euler = (0, math.pi / 2, 0)
    cap.location = (0.12, 0, 0)
    parts.append(cap)
    ob = kit.join("wheel", parts)
    kit.export("wheel_kestrel.glb", [ob])
    print("WHEEL tris", sum(len(p.vertices) - 2 for p in ob.data.polygons))


def glaze(body, clean, m, out, outline, axis, d0, d1, inset=0.008, seal="rubber", cut_body=True, glass=None):
    """A window: the glass is the uncut shell inside the outline (outer skin,
    set `inset` in), then the opening is cut through the body (its edges
    get the `seal` material)."""
    cutter = prism("glass_cut", outline, axis, d0, d1)
    piece = prism("glass_piece", outline, axis, d0, d1)
    gp = clean.copy()
    gp.data = clean.data.copy()
    bpy.context.scene.collection.objects.link(gp)
    gp.hide_render = False
    cut(gp, piece, None, "INTERSECT")
    gp.data.materials.clear()
    gp.data.materials.append(m["glass_clear"])
    for p in gp.data.polygons:
        p.material_index = 0
        p.use_smooth = True
    bm = bmesh.new()
    bm.from_mesh(gp.data)
    # keep only the outer skin (faces pointing out of the car)
    for f in list(bm.faces):
        nrm = f.normal
        cen = f.calc_center_median()
        if (axis == "x" and nrm.x * cen.x <= 0.05) or (axis == "z" and nrm.z <= 0.1) or (axis == "y" and nrm.y >= -0.1):
            bm.faces.remove(f)
    for v in bm.verts:
        if v.link_faces:
            nn = sum((f.normal for f in v.link_faces), V()).normalized()
            v.co -= nn * inset
    for v in [v for v in bm.verts if not v.link_faces]:
        bm.verts.remove(v)
    bm.to_mesh(gp.data)
    bm.free()
    dec = gp.modifiers.new("dec", "DECIMATE")
    dec.ratio = 0.3
    bpy.context.view_layer.objects.active = gp
    bpy.ops.object.modifier_apply(modifier=dec.name)
    out.append(gp)
    if cut_body:
        cut(body, cutter, m[seal])
    else:
        bpy.data.objects.remove(cutter, do_unlink=True)



# ------------------------------------------------------------------ build
def build():
    kit.reset()
    m = mats()
    m["trim"] = m["gloss_black"]
    premium(m)
    out = []
    clean = build_shell(m["paint"])          # full subdivided shell: shading + glass source
    clean.hide_render = True
    body = decimated(clean, 0.3)
    body.hide_render = False

    # Wheel arches: cut, open liner tunnel and a back wall inboard.
    for ay in AX:
        c = cyl("arch", ARCH, 0.62, (0, 0, 0), None, 48)
        c.rotation_euler = (0, math.pi / 2, 0)
        c.location = (W2 - 0.4, ay, WR)
        c2 = mirror_copy(c) if False else None
        cut(body, c, m["liner"])
        c = cyl("arch", ARCH, 0.62, (0, 0, 0), None, 48)
        c.rotation_euler = (0, math.pi / 2, 0)
        c.location = (-W2 - 0.22, ay, WR)
        cut(body, c, m["liner"])
        for sx in (1, -1):
            well = cyl("well", ARCH - 0.004, 0.34, (0, 0, 0), m["liner"], 24, cap=False)
            well.rotation_euler = (0, math.pi / 2, 0)
            well.location = (sx * 0.54 - (0.0 if sx > 0 else 0.34), ay, WR)
            out.append(well)
            wall = cyl("well_wall", ARCH - 0.004, 0.01, (0, 0, 0), m["liner"], 24)
            wall.rotation_euler = (0, math.pi / 2, 0)
            wall.location = (sx * 0.54 - (0.0 if sx > 0 else 0.01), ay, WR)
            out.append(wall)

    gap = m["liner"]
    # Doors: front edge behind the front arch, B-pillar line, rear edge round
    # the rear arch, door bottoms above the rocker.
    ra = ARCH + 0.035
    a0 = math.asin(max(-1.0, min(1.0, (SILL_Z - WR) / ra)))
    arc_r = [(AX[1] + math.cos(a) * ra, WR + math.sin(a) * ra) for a in (a0 + (1.15 - a0) * i / 9 for i in range(10))]
    arc_f = [(AX[0] - math.cos(a) * ra, WR + math.sin(a) * ra) for a in (a0 + (1.2 - a0) * i / 9 for i in range(10))]
    zc = lambda y: smooth(CREASE, y)
    lines = [
        arc_f + [(arc_f[-1][0] - 0.02, smooth(DECK, arc_f[-1][0]) - 0.012)],
        [(-0.17, SILL_Z), (-0.17, smooth(DECK, -0.17) - 0.012)],
        [(arc_f[0][0], SILL_Z), (arc_r[0][0], SILL_Z)],
        arc_r + [(arc_r[-1][0] - 0.01, smooth(DECK, arc_r[-1][0]) - 0.012)],
        # front bumper / wing, rear bumper / quarter
        [(YF - 0.34, 0.74), (YF - 0.38, 0.55), (AX[0] + ARCH + 0.025, 0.42)],
        [(YR + 0.3, 0.6), (YR + 0.33, 0.45), (AX[1] - ARCH - 0.025, 0.42)],
    ]
    for ln in lines:
        cut(body, slot("door_gap", ln, "x", -2.0, 2.0), gap)
    # Bonnet: along both wings and across the cowl.
    for sx in (1, -1):
        bon = [(sx * (half_width(y) - 0.13), y) for y in (Y_COWL + 0.04, 1.4, 1.8, YF - 0.2)]
        cut(body, slot("bonnet", bon, "z", 0.6, 1.3), gap)
    cut(body, slot("cowl", [(-0.75, Y_COWL + 0.05), (0.75, Y_COWL + 0.05)], "z", 0.7, 1.3, 0.006), gap)
    # Tailgate: inboard of the tail lamps, across above the bumper.
    tg = [(-0.6, 1.3), (-0.62, 0.62), (-0.58, 0.585), (0.58, 0.585), (0.62, 0.62), (0.6, 1.3)]
    cut(body, slot("tailgate", tg, "y", YR - 0.5, YR + 0.32), gap)
    cut(body, slot("rear_bumper", [(-0.74, 0.555), (0.74, 0.555)], "y", YR - 0.5, YR + 0.35), gap)
    cut(body, slot("front_bumper", [(-0.95, 0.6), (-0.45, 0.6)], "y", YF - 0.5, YF + 0.5), gap) if False else None
    # Fuel flap: a ring groove (outer disc minus inner disc, as one cutter).
    fo = prism("fuel", [(-1.62 + 0.088 * math.cos(a), 0.88 + 0.088 * math.sin(a)) for a in (i * 2 * math.pi / 20 for i in range(20))], "x", 0.5, 1.2)
    fi = prism("fuel_in", [(-1.62 + 0.083 * math.cos(a), 0.88 + 0.083 * math.sin(a)) for a in (i * 2 * math.pi / 20 for i in range(20))], "x", 0.4, 1.3)
    cut(fo, fi)
    cut(body, fo, gap)

    # Hollow cabin + boot (its walls are the headliner / door trims).
    cut(body, cavity_solid(), m["interior"])

    surf = Surface([body])
    probe = lambda x, z: surf.cast(*ray("front", x, z))
    # Nose: where the bonnet edge is (lamps go right under it).
    ztop = 0.0
    for z in [0.5 + i * 0.01 for i in range(50)]:
        h = probe(0.5, z)
        if h and h[1].y > 0.35 and h[0].y > YF - 0.45:
            ztop = z
    print("NOSE face top at x=0.5:", ztop)
    zl = ztop - 0.015
    head_lamp(surf, body, m, out, [(0.33, zl - 0.095), (0.8, zl - 0.07), (0.82, zl), (0.36, zl - 0.012)])
    surf = Surface([body])
    # Upper grille: slim, between the lamps, chrome bar along its top.
    opening(surf, body, m, out, [(-0.28, zl - 0.145), (0.28, zl - 0.145), (0.31, zl - 0.015), (-0.31, zl - 0.015)], 0.05, "slats",
            frame="chrome", res=(18, 5))
    surf = Surface([body])
    # Lower intake: integrated trapezoid, mesh insert, gloss-black surround.
    opening(surf, body, m, out, [(-0.44, 0.23), (0.44, 0.23), (0.5, 0.41), (-0.5, 0.41)], 0.06, "mesh", res=(22, 6))
    surf = Surface([body])
    # Corner intakes with fog lamps (left = mirrored right).
    g = patch(surf, "front", poly_fn([(0.58, 0.25), (0.76, 0.28), (0.74, 0.42), (0.6, 0.41)]), 10, 6)
    pk = recess_cutter("corner", g, 0.045)
    pk2 = mirror_copy(pk)
    cut(body, pk, m["plastic"])
    cut(body, pk2, m["plastic"])
    n0 = len(out)
    c = g[3][5]
    if c:
        out.append(disc_on("fog_bowl", c[0] - c[1] * 0.04, c[1], 0.034, 0.012, m["reflector"], 20))
        out.append(disc_on("fog_lens", c[0] - c[1] * 0.03, c[1], 0.028, 0.008, m["head"], 20))
    for o in list(out[n0:]):
        out.append(mirror_copy(o))
    surf = Surface([body])
    # Lower bumper: a black lip splitter across the chin, a chrome strip over
    # the intake, vertical air-curtain blades outboard of the fog lamps (the
    # bumper below the grille was one plain surface).
    g = patch(surf, "front", poly_fn([(-0.62, 0.17), (0.62, 0.17), (0.66, 0.225), (-0.66, 0.225)]), 22, 2)
    out.append(sheet("lip", g, 0.0, m["plastic"], thick=0.018))
    strip = [surf.cast(*ray("front", -0.48 + 0.96 * i / 16, 0.425)) for i in range(17)]
    strip = [h[0] + h[1] * 0.004 for h in strip if h]
    if len(strip) > 4:
        out.append(tube_path("intake_strip", strip, 0.006, m["chrome"], 6))
    n0 = len(out)
    gb = patch(surf, "front", poly_fn([(0.775, 0.26), (0.81, 0.27), (0.8, 0.46), (0.765, 0.45)]), 2, 6)
    pkb = recess_cutter("blade", gb, 0.03)
    pkb2 = mirror_copy(pkb)
    cut(body, pkb, m["plastic"])
    cut(body, pkb2, m["plastic"])
    surf = Surface([body])
    h = surf.cast(*ray("front", 0.0, zl - 0.05))
    if h:
        out.append(disc_on("badge", h[0] + h[1] * 0.004, h[1], 0.045, 0.01, m["chrome"], 28))
        out.append(disc_on("badge_in", h[0] + h[1] * 0.013, h[1], 0.034, 0.002, m["trim"], 28))
    h = surf.cast(*ray("front", 0.0, 0.495))
    if h:
        # On a flat black holder standing off the curved bumper.
        nf = V((0, 1, 0.12)).normalized()
        hold = box("plate_holder", (0.54, 0.125, 0.03), (0, 0, 0), m["plastic"], bevel=0.006)
        hold.rotation_mode = "QUATERNION"
        hold.rotation_quaternion = nf.to_track_quat("Z", "Y")
        hold.location = h[0] + nf * 0.006
        out.append(hold)
        number_plate(out, m, h[0] + nf * 0.026, nf, rear=False)

    # Rear: tail lamps across the D-pillar corner, plate recess, handle strip,
    # badge, reflectors, valance with diffuser, rear fog.
    # The layered WorldState tail lamp (tools/blender/ws_rear.py), as on every car.
    import ws_rear as R
    R.extra_mats(m)
    R.cluster(body, m, out, [(0.6, 0.82), (0.88, 0.84), (0.85, 1.02), (0.62, 1.0)], sig="C")
    surf = Surface([body])
    g = patch(surf, "rear", poly_fn([(-0.28, 0.63), (0.28, 0.63), (0.28, 0.76), (-0.28, 0.76)]), 10, 4)
    cut(body, recess_cutter("plate_pocket", g, 0.03), m["plastic"])
    surf = Surface([body])
    h = surf.cast(*ray("rear", 0.0, 0.695))
    if h:
        number_plate(out, m, h[0] + h[1] * 0.003, h[1], rear=True)
    h = surf.cast(*ray("rear", 0.0, 0.8))
    if h:
        out.append(box("tg_handle", (0.5, 0.015, 0.03), h[0] + h[1] * 0.008, m["chrome"], bevel=0.008))
        out.append(disc_on("badge_r", h[0] + h[1] * 0.002 + V((0, 0, 0.09)), h[1], 0.04, 0.008, m["chrome"], 24))
    g = patch(surf, "rear", poly_fn([(-0.7, 0.24), (0.7, 0.24), (0.74, 0.35), (-0.74, 0.35)]), 20, 3)
    cut(body, recess_cutter("valance", g, 0.025), m["plastic"])
    out.append(sheet("valance", g, -0.024, m["plastic"]))
    for sx in (1, -1):
        hh = surf.cast(*ray("rear", sx * 0.78, 0.44))
        if hh:
            out.append(box("reflector", (0.13, 0.012, 0.03), hh[0] + hh[1] * 0.002, m["lens_red"], bevel=0.006))
    hh = surf.cast(*ray("rear", -0.55, 0.3))
    if hh:
        out.append(box("rear_fog", (0.08, 0.012, 0.03), hh[0] + hh[1] * 0.001, m["tail"], bevel=0.006))

    # Glazing: windscreen, side windows (with B/C pillars and the quarter
    # light behind the D... estate C-pillar), tailgate glass.
    def zbelt(y):
        return smooth(DECK, y) + 0.004

    dlo = [(Y_COWL - 0.1, zbelt(Y_COWL - 0.1) + 0.01), (Y_WS + 0.02, ROOF - 0.09), (Y_RE + 0.14, ROOF - 0.11),
           (Y_TG + 0.17, zbelt(Y_TG + 0.17) + 0.14), (Y_TG + 0.17, zbelt(Y_TG + 0.17) + 0.01)]
    for sx in (1, -1):
        glaze(body, clean, m, out, dlo, "x", 0.3 * sx if sx > 0 else -2.0, 2.0 if sx > 0 else -0.3)
    yb, yt = Y_COWL - 0.05, Y_WS + 0.04
    wb_, wt_ = ring(yb)[2].x + 0.08, ring(yt)[2].x - 0.03
    glaze(body, clean, m, out, [(-wb_, yb), (wb_, yb), (wt_, yt), (-wt_, yt)], "z", 0.7, ROOF + 0.3)
    # Tailgate glass: flush on the tailgate (as real estates), a black ceramic
    # frit border behind it - no boolean into the thin tailgate.
    rs = Surface([clean])
    zroof = max((h[0].z for h in (rs.cast(V((0, y, 3.0)), V((0, 0, -1))) for y in [YR + 0.05 * i for i in range(12)]) if h),
                default=ROOF)
    zt_ = zroof - 0.07
    zb_ = zbelt(Y_TG) + 0.02
    xb_, xt_ = 0.6, 0.53
    gf = patch(rs, "rear", poly_fn([(-xb_ - 0.04, zb_ - 0.03), (xb_ + 0.04, zb_ - 0.03), (xt_ + 0.04, zt_ + 0.03), (-xt_ - 0.04, zt_ + 0.03)]), 16, 8)
    out.append(sheet("frit", gf, 0.002, m["trim"]))
    gg = patch(rs, "rear", poly_fn([(-xb_, zb_), (xb_, zb_), (xt_, zt_), (-xt_, zt_)]), 16, 8)
    out.append(sheet("tail_glass", gg, 0.005, m["glass_clear"]))
    # Spoiler: on the real roof end (found by probing), overhanging the glass.
    yend = min((y for y in [YR + 0.01 * i for i in range(60)]
                if (lambda h: h and h[0].z > zroof - 0.03)(rs.cast(V((0, y, 3.0)), V((0, 0, -1))))), default=Y_RE)
    # Pillars between the side windows: B (door split), C (rear door / quarter
    # light), gloss black, following the glass's lean.
    for yc, w in ((-0.17, 0.11), (AX[1] + 0.25, 0.09)):
        for sx in (1, -1):
            bm = bmesh.new()
            q = []
            for y in (yc - w / 2, yc + w / 2):
                r = ring(y)
                for (x, z) in ((r[4].x - 0.008, r[4].y), (r[2].x + 0.01, r[2].y - 0.05)):
                    q.append(V((sx * x, y, z)))
            a0_, a1_, b0_, b1_ = q
            o = V((sx * 0.012, 0, 0))
            vs = [bm.verts.new(v) for v in (a0_, b0_, b1_, a1_)] + [bm.verts.new(v + o) for v in (a0_, b0_, b1_, a1_)]
            for f in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
                bm.faces.new([vs[i] for i in f])
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            out.append(kit.new_obj("pillar", bm, m["trim"]))
    # Spoiler over the tailgate glass with the third brake lamp, wipers.
    r = ring(Y_RE)
    sp = box("spoiler", (r[2].x * 2 - 0.08, 0.16, 0.026), (0, 0, 0), m["paint"], bevel=0.012)
    sp.rotation_euler = (math.radians(-6), 0, 0)
    sp.location = (0, yend - 0.01, zroof - 0.012)
    out.append(sp)
    out.append(box("brake3", (0.34, 0.012, 0.014), (0, yend - 0.085, zroof - 0.03), m["tail"]))
    zc0 = smooth(DECK, Y_COWL - 0.04) + 0.02
    for x0 in (-0.05, 0.64):
        out.append(tube_path("wiper", [V((x0, Y_COWL - 0.03, zc0)), V((x0 - 0.58, Y_COWL - 0.11, zc0 + 0.05))], 0.008, m["plastic"]))
    out.append(tube_path("rear_wiper", [V((0.0, YR + 0.12, zbelt(Y_TG) + 0.07)), V((0.34, YR + 0.1, zbelt(Y_TG) + 0.12))],
                         0.007, m["plastic"]))
    # Sills (black) between the arches.
    surf = Surface([body])
    for sx in (1, -1):
        g = patch(surf, "side", poly_fn([(AX[1] + ARCH + 0.04, RIDE + 0.07), (AX[0] - ARCH - 0.04, RIDE + 0.07),
                                         (AX[0] - ARCH - 0.04, SILL_Z - 0.04), (AX[1] + ARCH + 0.04, SILL_Z - 0.04)]), 22, 3, sx)
        out.append(sheet("sill", g, 0.001, m["plastic"], thick=0.01))
    mirrors(m, out, Surface([clean]))
    door_handles(surf, m, out)
    roof_rails(m, out)
    interior(m, out)

    # Paint shading from the uncut shell.
    shade(body, 60)
    dt = body.modifiers.new("normals", "DATA_TRANSFER")
    dt.object = clean
    dt.use_loop_data = True
    dt.data_types_loops = {"CUSTOM_NORMAL"}
    dt.loop_mapping = "POLYINTERP_NEAREST"
    dt.max_distance = 0.012
    dt.use_max_distance = True
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=dt.name)
    bpy.data.objects.remove(clean, do_unlink=True)

    ob = kit.join("kestrel", [body] + [o for o in out if o is not None])
    kit.export("kestrel.glb", [ob])
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("KESTREL tris", tris, "materials", len(ob.data.materials))
    jpath = os.path.join(OUT, "bodies.json")
    dims = json.load(open(jpath)) if os.path.exists(jpath) else {}
    dims["kestrel"] = {"L": round(YF - YR, 3), "W": round(2 * W2, 3), "roof": ROOF, "wb": WB, "wheel_r": WR, "ride": RIDE,
                       "tyre_w": TYRE_W, "axles": [AX[0], AX[1]], "wheel": "kestrel"}
    with open(jpath, "w") as f:
        json.dump(dims, f, indent=1, sort_keys=True)
    with open(os.path.join(OUT, "body_dims.gd"), "w") as f:
        f.write("class_name BodyDims\nextends RefCounted\n## Generated by tools/blender/build_vehicles.py (Never Stop) and\n"
                "## tools/blender/kestrel.py (City Empire): real body dimensions (m). Do not edit.\n\n")
        f.write("const DIMS := " + json.dumps(dims, indent="\t", sort_keys=True) + "\n")


if __name__ == "__main__":
    build()
    if "wheels" in ARGS:
        wheel_kestrel()
    print("KESTREL DONE")
