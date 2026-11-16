"""City Empire craft v2: helicopters, planes and boats in the cars' style.

Run:  blender -b --factory-startup --python tools/blender/build_craft.py -- <out_dir> [render_dir] [only,ids]

Design brief: the aircraft and boats were boxes in vertex colours
(src/vehicle/craft_models.gd) next to section-lofted Never Stop cars. These
are built the same way the cars are:
  * Bodies are lofts through cross-sections (super-ellipses whose width,
    top, bottom and squareness are curves along the length), so a bubble
    trainer, a turbine pod and a jet fuselage are each their own shape.
  * Wings, tailplanes, fins, rotor blades and propellers are lofted airfoils
    (chord, sweep, dihedral, thickness per station).
  * Windows, cheatlines and boot stripes are patches projected onto the
    body (BVH ray casts), so they follow every curve.
  * Hulls are lofted deep-vee sections with a chine, flare and sheer.

Conventions (as the cars): Blender +Y forward -> Godot -Z, Z up -> Y up.
Aircraft origin on the ground under the body's centre (wheels / skids at
z 0); boats' origin on the waterline. Moving parts are separate nodes with
their origin on their pivot so the game can animate them:
  Rotor, RotorBlur, TailRotor, Prop, Prop_L, Prop_R, Gear (retracts),
plus Body. Materials are named for what Godot keys off: paint (the owner's
colour), paint2 (trim colour), glass, lamp_* (emissive), rotor_blur (alpha).
Writes <out_dir>/craft.json with each model's dimensions, pivots and
triangle count.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(__file__))
import build_kit as kit  # noqa: E402
from build_kit import mat  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "art/design/craft"
RENDER = ARGS[1] if len(ARGS) > 1 else ""
ONLY = set(ARGS[2].split(",")) if len(ARGS) > 2 and ARGS[2] else set()
os.makedirs(OUT, exist_ok=True)
if RENDER:
    os.makedirs(RENDER, exist_ok=True)

TAU = math.tau


# ---------------------------------------------------------------- curves


def interp(pts, x):
    """Smoothstep through [(x, y), ...] sorted by x. Numbers pass through."""
    if not isinstance(pts, (list, tuple)):
        return pts
    if x <= pts[0][0]:
        return pts[0][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x <= x1:
            t = (x - x0) / (x1 - x0) if x1 > x0 else 1.0
            t = t * t * (3 - 2 * t)
            return y0 + (y1 - y0) * t
    return pts[-1][1]


def lin(pts, x):
    if not isinstance(pts, (list, tuple)):
        return pts
    if x <= pts[0][0]:
        return pts[0][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x <= x1:
            t = (x - x0) / (x1 - x0) if x1 > x0 else 1.0
            return y0 + (y1 - y0) * t
    return pts[-1][1]


def cv(v, x):
    """A curve value: number, smooth list, or {"lin": list}."""
    if isinstance(v, dict):
        return lin(v["lin"], x)
    return interp(v, x)


# ---------------------------------------------------------------- materials


def hexrgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def mats(paint, trim):
    m = {
        "paint": mat("paint", paint, 0.22, 0.35),
        "paint2": mat("paint2", trim, 0.28, 0.3),
        "white": mat("gelcoat", (0.88, 0.88, 0.86), 0.22, 0.05),
        "glass": mat("glass", (0.02, 0.03, 0.04), 0.06, 0.0),
        "trim": mat("trim", (0.045, 0.045, 0.05), 0.6),
        "seam": mat("seam", (0.012, 0.012, 0.014), 0.8),
        "metal": mat("metal", (0.55, 0.56, 0.58), 0.32, 0.9),
        "chrome": mat("chrome", (0.82, 0.82, 0.84), 0.1, 1.0),
        "tyre": mat("tyre", (0.03, 0.03, 0.03), 0.85),
        "rim": mat("rim", (0.7, 0.71, 0.74), 0.25, 1.0),
        "blade": mat("blade", (0.08, 0.08, 0.09), 0.45, 0.25),
        "tip": mat("blade_tip", (0.9, 0.75, 0.1), 0.4),
        "intake": mat("intake", (0.012, 0.012, 0.015), 0.9),
        "exhaust": mat("exhaust", (0.2, 0.17, 0.15), 0.45, 0.8),
        "teak": mat("teak", (0.42, 0.27, 0.15), 0.72),
        "cushion": mat("cushion", (0.86, 0.84, 0.78), 0.85),
        "antifoul": mat("antifoul", (0.07, 0.09, 0.13), 0.8),
        "grey": mat("fairing", (0.62, 0.64, 0.67), 0.4, 0.2),
        "leather": mat("leather", (0.32, 0.2, 0.13), 0.6),
        "nav_red": mat("lamp_nav_red", (0.8, 0.05, 0.03), 0.3, 0.0, emit=(1.0, 0.05, 0.03)),
        "nav_green": mat("lamp_nav_green", (0.05, 0.8, 0.25), 0.3, 0.0, emit=(0.05, 1.0, 0.3)),
        "strobe": mat("lamp_strobe", (0.95, 0.95, 0.95), 0.2, 0.0, emit=(1.0, 1.0, 1.0)),
        "lamp": mat("lamp_head", (0.95, 0.95, 0.92), 0.1, 0.0, emit=(1.0, 0.95, 0.85)),
    }
    blur = bpy.data.materials.new("rotor_blur")
    blur.use_nodes = True
    b = blur.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.05, 0.05, 0.06, 1)
    b.inputs["Alpha"].default_value = 0.16
    b.inputs["Roughness"].default_value = 0.6
    blur.blend_method = "BLEND" if hasattr(blur, "blend_method") else None
    m["blur"] = blur
    return m


def set_smooth(ob, angle=40):
    for p in ob.data.polygons:
        p.use_smooth = True
    try:
        ob.data.set_sharp_from_angle(angle=math.radians(angle))
    except AttributeError:
        pass
    return ob


def link(name, bm, material=None):
    return kit.new_obj(name, bm, material)


def assign(ob, material, pred):
    """Faces whose centre/normal satisfy pred(c, n) take `material`."""
    names = [m.name if m else "" for m in ob.data.materials]
    if material.name not in names:
        ob.data.materials.append(material)
        names.append(material.name)
    idx = names.index(material.name)
    for p in ob.data.polygons:
        if pred(p.center, p.normal):
            p.material_index = idx


# ---------------------------------------------------------------- lofts


def loft(name, rings, material, cap=True, smooth=40):
    bm = bmesh.new()
    vr = [[bm.verts.new(v) for v in r] for r in rings]
    n = len(rings[0])
    for a, b in zip(vr, vr[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap:
        for r in (vr[0], vr[-1]):
            f = bm.faces.new(r if r is vr[-1] else list(reversed(r)))
            bmesh.ops.poke(bm, faces=[f])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = link(name, bm, material)
    return set_smooth(ob, smooth)


def superellipse(cx, cz, w, top, bot, n, segs=24):
    """Ring round (cx, cz): half width w, up `top`, down `bot`, squareness n (2 = ellipse)."""
    pts = []
    for i in range(segs):
        a = TAU * i / segs + math.pi / 2  # start at the top
        c, s = math.cos(a), math.sin(a)
        x = w * math.copysign(abs(c) ** (2 / n), c)
        h = top if s >= 0 else bot
        z = h * math.copysign(abs(s) ** (2 / n), s)
        pts.append((cx + x, cz + z))
    return pts


def body(name, P, material, segs=24):
    """Fuselage / pod: P has y0, y1 (tail..nose), stations n_st, and curves of y:
    w (half width), top, bot (from the axis), z (axis height), n (squareness), x (sideways)."""
    y0, y1 = P["y0"], P["y1"]
    ns = P.get("n_st", 40)
    ys = []
    for i in range(ns + 1):
        t = i / ns
        # Dense at both ends for round noses and tail cones.
        t = 0.5 - 0.5 * math.cos(math.pi * t) if P.get("ends", True) else t
        ys.append(y0 + (y1 - y0) * t)
    rings = []
    for y in ys:
        w = max(0.004, cv(P["w"], y))
        top = max(0.004, cv(P["top"], y))
        bot = max(0.004, cv(P["bot"], y))
        ring = superellipse(cv(P.get("x", 0.0), y), cv(P["z"], y), w, top, bot, cv(P.get("n", 2.4), y), segs)
        rings.append([Vector((x, y, z)) for x, z in ring])
    return loft(name, rings, material, cap=True, smooth=P.get("smooth", 50))


def airfoil(thick, camber=0.02, n=9):
    """Closed airfoil (x along chord 0..1 from the leading edge, z) from the TE round the top."""
    xs = [0.5 - 0.5 * math.cos(math.pi * i / n) for i in range(n + 1)]
    def yt(x):
        return 5 * thick * (0.2969 * math.sqrt(x) - 0.126 * x - 0.3516 * x * x + 0.2843 * x ** 3 - 0.1036 * x ** 4)
    def yc(x):
        return camber * 4 * x * (1 - x)
    top = [(x, yc(x) + yt(x)) for x in reversed(xs)]
    bot = [(x, yc(x) - yt(x)) for x in xs[1:-1]]
    return top + bot


def surface(name, stations, material, vertical=False, thick=0.12, camber=0.02, n=9, cap=True):
    """Lifting surface through stations [(span_pos, base, le_y, chord[, thick])].
    Horizontal: span along x, base = z.  Vertical: span along z, base = x."""
    rings = []
    for st in stations:
        s, base, le, c = st[0], st[1], st[2], st[3]
        t = st[4] if len(st) > 4 else thick
        prof = airfoil(t, 0.0 if vertical else camber, n)
        ring = []
        for u, d in prof:
            y = le - u * c
            if vertical:
                ring.append(Vector((base + d * c, y, s)))
            else:
                ring.append(Vector((s, y, base + d * c)))
        rings.append(ring)
    return loft(name, rings, material, cap=cap, smooth=55)


def wing(name, half, material, root_x=0.0, **kw):
    """Symmetric wing from a half-wing station list [(x>=0, z, le_y, chord[, t])]."""
    st = [(-s[0], *s[1:]) for s in reversed(half)] + list(half)
    if root_x == 0.0 and half[0][0] == 0.0:
        st = [(-s[0], *s[1:]) for s in reversed(half[1:])] + list(half)
    return surface(name, st, material, **kw)


def tube(name, pts, r, material, segs=8, cap=True):
    """A round tube along a polyline (skids, rails, struts)."""
    pts = [Vector(p) for p in pts]
    rings = []
    for i, p in enumerate(pts):
        a = pts[max(0, i - 1)]
        b = pts[min(len(pts) - 1, i + 1)]
        t = (b - a).normalized()
        up = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        u = t.cross(up).normalized()
        v = u.cross(t).normalized()
        rings.append([p + (u * math.cos(TAU * k / segs) + v * math.sin(TAU * k / segs)) * r for k in range(segs)])
    return loft(name, rings, material, cap=cap, smooth=70)


def disc(name, r, loc, material, axis="y", segs=20, depth=0.0, r2=None):
    """Thin cylinder / cone along an axis: axis 'x', 'y' or 'z'."""
    ob = kit.cyl(name, r, max(depth, 0.002), (0, 0, -max(depth, 0.002) / 2), material, segs, r2)
    if axis == "x":
        ob.rotation_euler = (0, math.pi / 2, 0)
    elif axis == "y":
        ob.rotation_euler = (-math.pi / 2, 0, 0)
    ob.location = loc
    apply(ob)
    return set_smooth(ob, 30)


def apply(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def rbox(name, size, loc, material, bevel=0.03):
    ob = kit.box(name, size, loc, material, bevel=bevel, segs=2)
    return ob


# ---------------------------------------------------------------- projected patches


class Proj:
    """Ray-cast patches (windows, stripes) onto one target object."""

    def __init__(self, target):
        dg = bpy.context.evaluated_depsgraph_get()
        self.bvh = BVHTree.FromObject(target, dg)

    def patch(self, name, material, axis, a0, a1, lo, hi, r=0.0, off=0.012, na=None, nb=6):
        """axis: '+x' / '-x' (a = y, b = z), '+z' (a = x, b = y, from above),
        '+y' (a = x, b = z, from the front), '-y' (from behind).
        lo/hi: curves of a (b range); r: corner radius in a."""
        big = na is None and off >= 0.012
        na = na or max(4, int(abs(a1 - a0) / 0.12))
        if axis in ("+z", "+y", "-y") or big:
            # Canopies and noses curve hard: a finer grid, a little more lift.
            na = max(na, min(int(abs(a1 - a0) / 0.05), 48))
            nb = max(nb, 16)
            off = max(off, 0.022)
        bm = bmesh.new()
        grid = []
        for i in range(na + 1):
            a = a0 + (a1 - a0) * i / na
            b0, b1 = cv(lo, a), cv(hi, a)
            d = min(a - a0, a1 - a)
            if r > 0 and d < r:
                inset = r - math.sqrt(max(0.0, r * r - (r - d) ** 2))
                b0, b1 = b0 + inset, b1 - inset
                if b1 < b0:
                    b0 = b1 = (b0 + b1) / 2
            col = []
            for j in range(nb + 1):
                b = b0 + (b1 - b0) * j / nb
                if axis in ("+x", "-x"):
                    o, d3 = Vector((30 if axis == "+x" else -30, a, b)), Vector((-1 if axis == "+x" else 1, 0, 0))
                elif axis == "+z":
                    o, d3 = Vector((a, b, 40)), Vector((0, 0, -1))
                elif axis == "+y":
                    o, d3 = Vector((a, 60, b)), Vector((0, -1, 0))
                else:
                    o, d3 = Vector((a, -60, b)), Vector((0, 1, 0))
                hit = self.bvh.ray_cast(o, d3)
                if hit[0] is None:
                    col.append(None)
                    continue
                nrm = hit[1] if hit[1].dot(d3) < 0 else -hit[1]
                col.append(bm.verts.new(hit[0] + nrm * off))
            grid.append(col)
        for i in range(na):
            for j in range(nb):
                q = (grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
                if None in q or len({id(v) for v in q}) < 3:
                    continue
                uq = []
                for v in q:
                    if v not in uq:
                        uq.append(v)
                try:
                    bm.faces.new(uq)
                except ValueError:
                    pass
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        ob = link(name, bm, material)
        # Face outward: flip if the patch faces into the ray.
        flip = {"+x": Vector((1, 0, 0)), "-x": Vector((-1, 0, 0)), "+z": Vector((0, 0, 1)),
                "+y": Vector((0, 1, 0)), "-y": Vector((0, -1, 0))}[axis]
        if ob.data.polygons and sum(p.normal.dot(flip) for p in ob.data.polygons) < 0:
            for p in ob.data.polygons:
                p.flip()
        return set_smooth(ob, 60)

    def both(self, name, material, a0, a1, lo, hi, r=0.0, **kw):
        return [self.patch(name + "_r", material, "+x", a0, a1, lo, hi, r, **kw),
                self.patch(name + "_l", material, "-x", a0, a1, lo, hi, r, **kw)]

    def outline(self, name, material, a0, a1, b0, b1, w=0.025, **kw):
        """A door seam: two uprights + a header, both sides."""
        out = []
        out += self.both(name + "_a", material, a0, a0 + w, b0, b1, off=0.006, na=2, nb=10)
        out += self.both(name + "_b", material, a1 - w, a1, b0, b1, off=0.006, na=2, nb=10)
        out += self.both(name + "_t", material, a0, a1, b1 - w, b1, off=0.006, nb=1)
        out += self.both(name + "_s", material, a0, a1, b0, b0 + w, off=0.006, nb=1)
        return out

    def windows(self, name, material, ys, w, lo, hi, r=0.08, **kw):
        """A row of separate windows (centres ys, width w) on both sides."""
        out = []
        for k, y in enumerate(ys):
            out += self.both(f"{name}{k}", material, y - w / 2, y + w / 2, lo, hi, r, na=6, nb=5, **kw)
        return out


# ---------------------------------------------------------------- shared parts


def lamp(name, loc, material, r=0.06):
    return kit.sphere(name, r, loc, material, 8, 5)


def nav_lights(m, wingtip_l, wingtip_r, tail=None, beacon=None, belly=None):
    out = [lamp("nav_l", wingtip_l, m["nav_red"]), lamp("nav_r", wingtip_r, m["nav_green"])]
    if tail:
        out.append(lamp("strobe_tail", tail, m["strobe"]))
    if beacon:
        out.append(lamp("beacon", beacon, m["nav_red"], 0.08))
    if belly:
        out.append(lamp("beacon_belly", belly, m["nav_red"], 0.08))
    return out


def wheel(name, loc, r, w, m, axis="x"):
    t = disc(name + "_t", r, loc, m["tyre"], axis, 16, w)
    h = disc(name + "_h", r * 0.55, Vector(loc) + Vector((0.0 if axis != "x" else 0.0, 0, 0)), m["rim"], axis, 12, w + 0.02)
    return [t, h]


def blade(name, r0, r1, chord0, chord1, thick, m, tip=None, z=0.0, twist=0.0):
    """One blade along +x from r0 to r1 (airfoil leading edge towards +y)."""
    st = []
    for i in range(5):
        t = i / 4
        s = r0 + (r1 - r0) * t
        c = chord0 + (chord1 - chord0) * t
        st.append((s, z, c * 0.3, c, thick))
    ob = surface(name, st, m["blade"], thick=thick, camber=0.0, n=5)
    if tip is not None:
        assign(ob, tip, lambda c, n: c.x > r1 - 0.25)
    return ob


def rotor(name, n_blades, r, chord, m, hub_r=0.16, tip=True, phase=0.0, droop=0.0):
    """Main rotor in its own frame (origin = hub)."""
    parts = []
    for k in range(n_blades):
        b = blade(f"{name}_b{k}", hub_r * 1.4, r, chord * 1.1, chord * 0.85, 0.11, m, m["tip"] if tip else None)
        if droop:
            for v in b.data.vertices:
                v.co.z -= droop * (max(0.0, v.co.x) / r) ** 2
        b.rotation_euler = (0, 0, phase + TAU * k / n_blades)
        apply(b)
        parts.append(b)
    parts.append(kit.cyl(name + "_hub", hub_r, 0.22, (0, 0, -0.11), m["metal"], 14))
    parts.append(kit.cyl(name + "_cap", hub_r * 0.75, 0.12, (0, 0, 0.11), m["trim"], 14, r2=hub_r * 0.3))
    for k in range(n_blades):
        a = phase + TAU * k / n_blades
        g = rbox(f"{name}_grip{k}", (hub_r * 1.6, 0.11, 0.08), (math.cos(a) * hub_r * 1.2, math.sin(a) * hub_r * 1.2, 0), m["metal"], 0.015)
        g.rotation_euler = (0, 0, a)
        apply(g)
        parts.append(g)
    return kit.join(name, parts, (0, 0, 0))


def blur_disc(name, r, m, axis="z", segs=32):
    bm = bmesh.new()
    ring = []
    for i in range(segs):
        a = TAU * i / segs
        if axis == "z":
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), 0)))
        elif axis == "x":
            ring.append(bm.verts.new((0, r * math.cos(a), r * math.sin(a))))
        else:
            ring.append(bm.verts.new((r * math.cos(a), 0, r * math.sin(a))))
    f = bm.faces.new(ring)
    bmesh.ops.poke(bm, faces=[f])
    return link(name, bm, m["blur"])


def propeller(name, n, r, m, spinner_r, spinner_len, chord=0.16):
    """Prop in its own frame: spins about Y (forward), origin = hub."""
    parts = []
    for k in range(n):
        b = blade(f"{name}_b{k}", spinner_r * 0.8, r, chord, chord * 0.6, 0.12, m, m["tip"])
        b.rotation_euler = (0, math.radians(18), 0)  # pitch
        apply(b)
        b.rotation_euler = (0, TAU * k / n, 0)
        apply(b)
        parts.append(b)
    sp = body(name + "_spinner", {"y0": -0.05, "y1": spinner_len, "n_st": 10, "z": 0.0,
                                  "w": [(-0.05, spinner_r), (spinner_len * 0.4, spinner_r * 0.92), (spinner_len, 0.01)],
                                  "top": [(-0.05, spinner_r), (spinner_len * 0.4, spinner_r * 0.92), (spinner_len, 0.01)],
                                  "bot": [(-0.05, spinner_r), (spinner_len * 0.4, spinner_r * 0.92), (spinner_len, 0.01)],
                                  "n": 2.0, "ends": False}, m["paint2"], segs=14)
    parts.append(sp)
    return kit.join(name, parts, (0, 0, 0))


def nacelle(name, y0, y1, x, z, r, m, inlet=True, exhaust=True, shape=None):
    L = y1 - y0
    P = {"y0": y0, "y1": y1, "n_st": 22, "x": x, "z": z, "n": 2.0, "ends": False,
         "w": shape or [(y0, r * 0.62), (y0 + L * 0.25, r), (y1 - L * 0.12, r * 0.98), (y1, r * 0.9)]}
    P["top"] = P["w"]
    P["bot"] = P["w"]
    ob = body(name, P, m["paint"], segs=20)
    out = [ob]
    if inlet:
        out.append(disc(name + "_in", r * 0.82, (x, y1 + 0.004, z), m["intake"], "y", 20, 0.01))
        out.append(disc(name + "_lip", r * 0.93, (x, y1 - 0.01, z), m["metal"], "y", 20, 0.03))
    if exhaust:
        out.append(disc(name + "_ex", r * 0.5, (x, y0 - 0.02, z), m["exhaust"], "y", 16, 0.08, r2=r * 0.42))
    return out


def gear_leg(name, top, bottom, wheel_r, wheel_w, m, twin=False, fork=True):
    """Strut from top to bottom + wheel(s) at the bottom (axle along x)."""
    out = [tube(name + "_strut", [top, bottom + Vector((0, 0, wheel_r * 0.9))], 0.05, m["metal"], 8)]
    c = Vector(bottom) + Vector((0, 0, wheel_r))
    offs = [-wheel_w * 0.7, wheel_w * 0.7] if twin else [0.0]
    for k, dx in enumerate(offs):
        out += wheel(f"{name}_w{k}", c + Vector((dx, 0, 0)), wheel_r, wheel_w, m)
    if twin:
        out.append(tube(name + "_axle", [c - Vector((wheel_w, 0, 0)), c + Vector((wheel_w, 0, 0))], 0.035, m["metal"], 6))
    return out


def tri_count(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    n = 0
    for o in objs:
        me = o.evaluated_get(dg).to_mesh()
        n += sum(len(p.vertices) - 2 for p in me.polygons)
        o.evaluated_get(dg).to_mesh_clear()
    return n


# ---------------------------------------------------------------- helicopters


def heli(spec_id, S, m):
    """Wren (bubble trainer), Kite (turbine with a fenestron), Regent (twin executive)."""
    L = S["size"][2]
    R = S["rotor_r"]
    kind = spec_id
    parts, nodes = [], {}
    nose = L * 0.5 - (0.2 if kind != "wren" else 0.6)
    if kind == "wren":
        # Bubble cabin, slim boom, cradle of skids, piston engine on show.
        cab = body("cabin", {"y0": -0.9, "y1": nose, "n_st": 30, "z": 1.45,
                             "w": [(-0.9, 0.45), (-0.2, 0.62), (0.9, 0.66), (1.6, 0.55), (nose - 0.25, 0.3), (nose, 0.04)],
                             "top": [(-0.9, 0.35), (0.0, 0.7), (0.8, 0.78), (1.5, 0.62), (nose - 0.2, 0.22), (nose, 0.02)],
                             "bot": [(-0.9, 0.45), (0.0, 0.62), (1.2, 0.6), (nose - 0.2, 0.3), (nose, 0.04)],
                             "n": [(-0.9, 2.6), (0.6, 2.1), (nose, 2.0)]}, m["paint"])
        pj = Proj(cab)
        # Bubble: glass over the whole front above the waist and down the nose.
        glass = [pj.patch("bubble_top", m["glass"], "+z", -0.6, 0.6, -0.05, {"lin": [(-0.6, 2.7), (0, 3.4), (0.6, 2.7)]}, r=0.25, nb=10),
                 *pj.both("door", m["glass"], -0.15, 2.5, [(-0.15, 1.3), (1.4, 1.15), (2.5, 1.2)], [(-0.15, 1.95), (0.5, 2.05), (1.6, 1.9), (2.5, 1.45)], r=0.22),
                 pj.patch("chin", m["glass"], "+y", -0.45, 0.45, [(-0.45, 1.05), (0, 0.95), (0.45, 1.05)], [(-0.45, 1.65), (0, 1.85), (0.45, 1.65)], r=0.2, nb=8)]
        parts += [cab] + glass
        # Exposed engine deck + mast fairing.
        parts.append(body("engine", {"y0": -1.9, "y1": -0.4, "n_st": 14, "z": 1.55, "ends": False,
                                     "w": [(-1.9, 0.18), (-1.4, 0.36), (-0.6, 0.4), (-0.4, 0.35)],
                                     "top": [(-1.9, 0.18), (-1.2, 0.5), (-0.5, 0.58), (-0.4, 0.4)],
                                     "bot": [(-1.9, 0.2), (-1.2, 0.35), (-0.4, 0.35)], "n": 3.0}, m["metal"]))
        parts.append(kit.cyl("mast", 0.07, 0.75, (0, -0.3, 2.05), m["metal"], 10))
        parts.append(body("mast_fair", {"y0": -0.75, "y1": 0.1, "n_st": 10, "z": 2.15, "ends": False,
                                        "w": [(-0.75, 0.05), (-0.4, 0.16), (0.1, 0.1)], "top": [(-0.75, 0.05), (-0.35, 0.22), (0.1, 0.05)],
                                        "bot": 0.12, "n": 2.0}, m["paint"]))
        boom_y0, boom_y1, boom_z = -L * 0.5 + 0.3, -1.5, 1.7
        parts.append(body("boom", {"y0": boom_y0, "y1": boom_y1, "n_st": 12, "z": {"lin": [(boom_y0, 1.82), (boom_y1, 1.62)]}, "ends": False,
                                   "w": {"lin": [(boom_y0, 0.07), (boom_y1, 0.12)]}, "top": {"lin": [(boom_y0, 0.07), (boom_y1, 0.12)]},
                                   "bot": {"lin": [(boom_y0, 0.07), (boom_y1, 0.12)]}, "n": 2.0}, m["paint"]))
        ty = boom_y0 + 0.15
        parts.append(surface("fin", [(1.55, 0.0, ty + 0.55, 0.85, 0.1), (2.55, 0.0, ty + 0.15, 0.5, 0.1)], m["paint2"], vertical=True))
        parts.append(surface("fin_low", [(0.95, 0.0, ty + 0.4, 0.5, 0.1), (1.8, 0.0, ty + 0.5, 0.75, 0.1)], m["paint2"], vertical=True))
        parts.append(wing("stab", [(0.0, 1.8, ty + 0.9, 0.42), (0.65, 1.86, ty + 0.85, 0.32)], m["paint2"], thick=0.1))
        tr_at = Vector((-0.2, boom_y0 + 0.05, 2.12))
        skid_x, cross = 0.95, [0.55, -0.8]
    elif kind == "kite":
        cab = body("cabin", {"y0": -1.3, "y1": nose, "n_st": 34, "z": 1.5,
                             "w": [(-1.3, 0.5), (-0.4, 0.75), (1.0, 0.78), (2.6, 0.62), (nose - 0.2, 0.25), (nose, 0.03)],
                             "top": [(-1.3, 0.45), (-0.5, 0.85), (1.2, 0.92), (2.5, 0.6), (nose - 0.15, 0.1), (nose, 0.02)],
                             "bot": [(-1.3, 0.5), (-0.2, 0.72), (2.0, 0.66), (nose - 0.25, 0.28), (nose, 0.03)],
                             "n": [(-1.3, 2.8), (1.0, 2.6), (nose, 2.1)]}, m["paint"])
        pj = Proj(cab)
        glass = [pj.patch("screen", m["glass"], "+z", -0.7, 0.7, {"lin": [(-0.7, 2.25), (0, 2.4), (0.7, 2.25)]}, {"lin": [(-0.7, 3.25), (0, 3.55), (0.7, 3.25)]}, r=0.25, nb=10),
                 pj.patch("chin", m["glass"], "+y", -0.5, 0.5, [(-0.5, 1.15), (0, 1.05), (0.5, 1.15)], [(-0.5, 1.6), (0, 1.75), (0.5, 1.6)], r=0.2, nb=6),
                 *pj.both("front_door", m["glass"], 1.05, 2.35, [(1.05, 1.5), (2.35, 1.45)], [(1.05, 2.15), (2.35, 1.95)], r=0.15),
                 *pj.both("rear_door", m["glass"], -0.55, 0.85, 1.55, [(-0.55, 2.0), (0.85, 2.18)], r=0.18),
                 *pj.both("door_line", m["seam"], 0.9, 0.97, 0.95, 2.25, off=0.006, na=2, nb=8)]
        stripe = pj.both("stripe", m["paint2"], -1.25, nose - 0.4, {"lin": [(-1.25, 1.15), (nose - 0.4, 1.05)]}, {"lin": [(-1.25, 1.27), (nose - 0.4, 1.15)]}, off=0.008)
        parts += [cab] + glass + stripe
        parts.append(body("cowl", {"y0": -2.7, "y1": 0.6, "n_st": 20, "z": 2.25, "ends": False,
                                   "w": [(-2.7, 0.2), (-1.8, 0.45), (-0.3, 0.52), (0.6, 0.2)],
                                   "top": [(-2.7, 0.15), (-1.6, 0.42), (-0.2, 0.5), (0.6, 0.02)],
                                   "bot": [(-2.7, 0.22), (0.6, 0.4)], "n": 3.2}, m["paint"]))
        for s in (-1, 1):
            parts.append(rbox(f"inlet{s}", (0.04, 0.42, 0.22), (s * 0.5, -0.6, 2.3), m["intake"], 0.01))
        parts.append(disc("exhaust", 0.16, (0, -2.72, 2.27), m["exhaust"], "y", 14, 0.2, r2=0.13))
        parts.append(kit.cyl("mast", 0.09, 0.45, (0, -0.4, 2.7), m["metal"], 10))
        boom_y0, boom_y1 = -L * 0.5 + 0.25, -2.0
        parts.append(body("boom", {"y0": boom_y0, "y1": boom_y1, "n_st": 14, "z": {"lin": [(boom_y0, 2.0), (boom_y1, 1.85)]}, "ends": False,
                                   "w": {"lin": [(boom_y0, 0.13), (boom_y1, 0.3)]}, "top": {"lin": [(boom_y0, 0.15), (boom_y1, 0.38)]},
                                   "bot": {"lin": [(boom_y0, 0.12), (boom_y1, 0.32)]}, "n": 2.4}, m["paint"]))
        ty = boom_y0
        # Fenestron: a shrouded fan in a thick fin.
        fen_c = Vector((0, ty + 0.25, 2.25))
        fin = surface("fin", [(1.65, 0.0, ty + 1.05, 1.35, 0.2), (2.9, 0.0, ty + 0.5, 0.85, 0.14), (3.25, 0.0, ty + 0.32, 0.6, 0.12)], m["paint"], vertical=True)
        parts.append(fin)
        parts.append(disc("fen_ring", 0.42, fen_c, m["trim"], "x", 20, 0.26))
        parts.append(disc("fen_hole", 0.36, fen_c, m["intake"], "x", 20, 0.28))
        parts.append(wing("stab", [(0.0, 2.05, ty + 1.6, 0.5), (0.9, 2.05, ty + 1.5, 0.38)], m["paint"], thick=0.1))
        for s in (-1, 1):
            parts.append(surface(f"endplate{s}", [(1.75, s * 0.92, ty + 1.62, 0.45, 0.08), (2.35, s * 0.92, ty + 1.48, 0.32, 0.08)], m["paint2"], vertical=True))
        tr_at = fen_c
        skid_x, cross = 1.05, [0.75, -0.9]
    else:  # regent
        cab = body("cabin", {"y0": -2.7, "y1": nose, "n_st": 40, "z": 1.55,
                             "w": [(-2.7, 0.6), (-1.6, 0.98), (2.2, 1.0), (3.6, 0.8), (nose - 0.35, 0.36), (nose, 0.03)],
                             "top": [(-2.7, 0.5), (-1.6, 0.9), (2.0, 0.95), (3.3, 0.72), (nose - 0.25, 0.22), (nose, 0.02)],
                             "bot": [(-2.7, 0.35), (-1.6, 0.8), (3.0, 0.78), (nose - 0.35, 0.4), (nose, 0.03)],
                             "n": [(-2.7, 2.6), (0.0, 3.2), (3.0, 2.8), (nose, 2.2)]}, m["paint"])
        pj = Proj(cab)
        glass = [pj.patch("screen", m["glass"], "+z", -0.85, 0.85, {"lin": [(-0.85, 3.35), (0, 3.5), (0.85, 3.35)]}, {"lin": [(-0.85, 4.45), (0, 4.75), (0.85, 4.45)]}, r=0.3, nb=10),
                 *pj.both("cockpit_side", m["glass"], 3.05, 4.15, [(3.05, 1.65), (4.15, 1.55)], [(3.05, 2.35), (4.15, 2.0)], r=0.18),
                 *pj.windows("cabin_win", m["glass"], [-1.35, -0.3, 0.75, 1.8], 0.78, 1.72, 2.2, r=0.14)]
        trim = pj.both("cheat", m["paint2"], -2.6, nose - 0.5, {"lin": [(-2.6, 1.28), (nose - 0.5, 1.2)]}, {"lin": [(-2.6, 1.4), (nose - 0.5, 1.3)]}, off=0.008)
        trim += pj.both("door_line", m["seam"], -1.9, -1.85, 1.1, 2.4, off=0.006, na=2, nb=8)
        trim += pj.both("door_line2", m["seam"], 2.45, 2.5, 1.1, 2.4, off=0.006, na=2, nb=8)
        parts += [cab] + glass + trim
        parts.append(lamp("radar", (0, nose - 0.05, 1.5), m["paint"], 0.18))
        parts.append(body("cowl", {"y0": -3.6, "y1": 1.0, "n_st": 22, "z": 2.4, "ends": False,
                                   "w": [(-3.6, 0.3), (-2.6, 0.75), (0.2, 0.8), (1.0, 0.3)],
                                   "top": [(-3.6, 0.2), (-2.4, 0.5), (0.2, 0.55), (1.0, 0.02)],
                                   "bot": [(-3.6, 0.3), (1.0, 0.4)], "n": 3.4}, m["paint"]))
        for s in (-1, 1):
            parts.append(disc(f"exhaust{s}", 0.16, (s * 0.5, -3.3, 2.55), m["exhaust"], "y", 14, 0.25, r2=0.13))
            parts.append(rbox(f"inlet{s}", (0.05, 0.6, 0.3), (s * 0.78, 0.1, 2.5), m["intake"], 0.01))
            # Sponsons for the retracting main gear.
            parts.append(body(f"sponson{s}", {"y0": -1.8, "y1": 0.4, "n_st": 12, "x": s * 1.05, "z": 1.0, "ends": True,
                                              "w": [(-1.8, 0.08), (-1.2, 0.32), (0.0, 0.32), (0.4, 0.1)],
                                              "top": [(-1.8, 0.1), (-1.2, 0.3), (0.4, 0.15)], "bot": [(-1.8, 0.08), (-1.0, 0.28), (0.4, 0.1)], "n": 2.6}, m["paint"]))
        parts.append(kit.cyl("mast", 0.11, 0.42, (0, -0.6, 2.9), m["metal"], 12))
        boom_y0, boom_y1 = -L * 0.5 + 0.3, -2.8
        parts.append(body("boom", {"y0": boom_y0, "y1": boom_y1, "n_st": 14, "z": {"lin": [(boom_y0, 2.25), (boom_y1, 1.9)]}, "ends": False,
                                   "w": {"lin": [(boom_y0, 0.15), (boom_y1, 0.45)]}, "top": {"lin": [(boom_y0, 0.18), (boom_y1, 0.5)]},
                                   "bot": {"lin": [(boom_y0, 0.14), (boom_y1, 0.38)]}, "n": 2.6}, m["paint"]))
        ty = boom_y0
        parts.append(surface("fin", [(2.1, 0.0, ty + 1.25, 1.4, 0.14), (3.6, 0.0, ty + 0.55, 0.9, 0.12)], m["paint"], vertical=True))
        parts.append(wing("stab", [(0.0, 2.35, ty + 2.0, 0.65), (1.35, 2.35, ty + 1.85, 0.48)], m["paint"], thick=0.1))
        tr_at = Vector((-0.24, ty + 0.65, 3.15))
        skid_x, cross = None, None
    # Rotor head height and the tail rotor.
    hub_z = {"wren": 2.82, "kite": 3.18, "regent": 3.4}[kind]
    hub_y = {"wren": -0.3, "kite": -0.4, "regent": -0.6}[kind]
    blades = {"wren": 2, "kite": 3, "regent": 5}[kind]
    chord = {"wren": 0.2, "kite": 0.26, "regent": 0.32}[kind]
    rot = rotor("Rotor", blades, R, chord, m, hub_r=0.12 if kind == "wren" else 0.18, droop=0.12)
    rot.location = (0, hub_y, hub_z)
    nodes["Rotor"] = rot
    bl = blur_disc("RotorBlur", R, m)
    bl.location = (0, hub_y, hub_z + 0.02)
    nodes["RotorBlur"] = bl
    if kind == "kite":
        fan = []
        for k in range(9):
            b = blade(f"fan{k}", 0.08, 0.35, 0.09, 0.07, 0.1, m)
            b.rotation_euler = (math.radians(20), 0, 0)
            apply(b)
            b.rotation_euler = (TAU * k / 9, 0, 0)
            apply(b)
            # blade lies along x; turn it into the fin's plane (y-z)
            b.rotation_euler = (0, 0, math.pi / 2)
            apply(b)
            fan.append(b)
        fan.append(disc("fan_hub", 0.09, (0, 0, 0), m["metal"], "x", 12, 0.12))
        tr = kit.join("TailRotor", fan)
        tr.rotation_euler = (0, math.pi / 2, 0)
        apply(tr)
    else:
        tr_r = {"wren": 0.6, "regent": 1.05}[kind]
        tr = rotor("TailRotor", 2 if kind == "wren" else 4, tr_r, 0.1 if kind == "wren" else 0.14, m, hub_r=0.06, tip=True)
        tr.rotation_euler = (0, math.pi / 2, 0)
        apply(tr)
    tr.location = tr_at
    nodes["TailRotor"] = tr
    # Undercarriage.
    if skid_x:
        for s in (-1, 1):
            y0, y1 = -L * 0.5 + 2.6, nose - 0.3
            parts.append(tube(f"skid{s}", [(s * skid_x, y0, 0.06), (s * skid_x, y1 - 0.4, 0.06),
                                            (s * skid_x, y1 - 0.12, 0.13), (s * skid_x, y1, 0.32)], 0.05, m["metal"], 8))
            for k, cy in enumerate(cross):
                parts.append(tube(f"cross{s}{k}", [(s * skid_x, cy, 0.08), (s * skid_x * 0.95, cy, 0.55),
                                                     (s * 0.5, cy, 0.95)], 0.045, m["metal"], 8))
        nodes_gear = None
    else:
        g = []
        g += gear_leg("nose_gear", Vector((0, 3.2, 1.0)), Vector((0, 3.2, 0.0)), 0.2, 0.14, m, twin=True)
        for s in (-1, 1):
            g += gear_leg(f"main{s}", Vector((s * 1.05, -0.7, 0.85)), Vector((s * 1.12, -0.7, 0.0)), 0.3, 0.2, m)
        nodes_gear = kit.join("Gear", g, (0, 0, 1.0))
    if nodes_gear:
        nodes["Gear"] = nodes_gear
    # Lights.
    span = 0.8 if kind == "wren" else 1.0
    parts += nav_lights(m, (-span, -0.2, 1.5), (span, -0.2, 1.5), tail=(0, -L * 0.5 + 0.2, 2.0),
                        beacon=(0, -1.6, {"wren": 2.1, "kite": 2.72, "regent": 2.95}[kind]))
    parts.append(lamp("landing", (0, nose - 0.4, 0.95), m["lamp"], 0.08))
    return parts, nodes


# ---------------------------------------------------------------- planes


def plane(spec_id, S, m):
    span, L = S["size"][0], S["size"][2]
    parts, nodes = [], {}
    kind = spec_id
    if kind == "skylark":
        # High-wing, four-seat, fixed tricycle gear with spats, two-blade prop.
        n0, t0, zc = 3.55, -L * 0.5, 1.35
        fus = body("fuselage", {"y0": t0, "y1": n0, "n_st": 40, "z": [(t0, 1.65), (-1.0, 1.42), (n0, 1.3)],
                                "w": [(t0, 0.06), (-1.6, 0.36), (0.0, 0.56), (1.6, 0.56), (2.9, 0.5), (n0, 0.32)],
                                "top": [(t0, 0.1), (-1.8, 0.35), (-0.4, 0.62), (1.4, 0.68), (1.9, 0.5), (2.9, 0.32), (n0, 0.22)],
                                "bot": [(t0, 0.06), (-1.6, 0.25), (0.0, 0.55), (2.5, 0.55), (n0, 0.32)],
                                "n": [(t0, 2.0), (0.0, 2.6), (n0, 2.2)]}, m["white"])
        pj = Proj(fus)
        parts += [fus,
                  pj.patch("screen", m["glass"], "+y", -0.5, 0.5, [(-0.5, 1.68), (0, 1.66), (0.5, 1.68)], [(-0.5, 2.0), (0, 2.03), (0.5, 2.0)], r=0.06, nb=6),
                  *pj.both("door", m["glass"], 0.55, 1.65, [(0.55, 1.42), (1.65, 1.38)], [(0.55, 1.98), (1.65, 1.98)], r=0.12),
                  *pj.both("rear_win", m["glass"], -0.65, 0.4, 1.45, [(-0.65, 1.8), (0.4, 1.98)], r=0.14),
                  *pj.both("cheat", m["paint2"], t0 + 0.5, n0 - 0.05, {"lin": [(t0 + 0.5, 1.55), (0, 1.24), (n0, 1.2)]}, {"lin": [(t0 + 0.5, 1.7), (0, 1.38), (n0, 1.33)]}, off=0.008),
                  *pj.both("cheat2", m["paint"], t0 + 0.6, n0 - 0.05, {"lin": [(t0 + 0.6, 1.47), (0, 1.12), (n0, 1.1)]}, {"lin": [(t0 + 0.6, 1.52), (0, 1.18), (n0, 1.15)]}, off=0.008)]
        wz = 2.07
        w = wing("wing", [(0.0, wz, 1.55, 1.5), (span * 0.25, wz + 0.04, 1.55, 1.5), (span * 0.5, wz + 0.1, 1.45, 1.1)], m["white"], thick=0.13)
        parts.append(w)
        assign(w, m["paint2"], lambda c, n: abs(c.x) > span * 0.5 - 0.5)
        for s in (-1, 1):
            parts.append(tube(f"strut{s}", [(s * 0.55, 0.9, 0.95), (s * span * 0.3, 1.0, wz - 0.05)], 0.05, m["white"], 6))
        parts.append(surface("fin", [(1.6, 0.0, t0 + 1.4, 1.5, 0.11), (3.05, 0.0, t0 + 0.55, 0.85, 0.1)], m["white"], vertical=True))
        parts.append(surface("dorsal", [(1.7, 0.0, t0 + 2.4, 2.2, 0.06), (2.0, 0.0, t0 + 1.5, 1.1, 0.08)], m["white"], vertical=True))
        assign(parts[-2], m["paint2"], lambda c, n: 2.3 < c.z < 2.6)
        parts.append(wing("stab", [(0.0, 1.62, t0 + 1.0, 0.95), (1.75, 1.62, t0 + 0.85, 0.65)], m["white"], thick=0.1))
        prop = propeller("Prop", 2, 0.95, m, 0.17, 0.42)
        prop.location = (0, n0 + 0.02, 1.32)
        nodes["Prop"] = prop
        nodes["PropBlur"] = blur_disc("PropBlur", 0.95, m, "y")
        nodes["PropBlur"].location = (0, n0 + 0.1, 1.32)
        g = gear_leg("nose", Vector((0, 2.9, 0.9)), Vector((0, 2.95, 0.0)), 0.2, 0.13, m)
        for s in (-1, 1):
            g.append(tube(f"main_leg{s}", [(s * 0.45, 0.25, 0.9), (s * 1.15, 0.2, 0.3)], 0.05, m["metal"], 6))
            g += wheel(f"main{s}", Vector((s * 1.18, 0.2, 0.26)), 0.26, 0.15, m)
            g.append(body(f"spat{s}", {"y0": -0.25, "y1": 0.75, "n_st": 10, "x": s * 1.18, "z": 0.3, "ends": True,
                                       "w": [(-0.25, 0.04), (0.0, 0.13), (0.4, 0.13), (0.75, 0.04)], "top": [(-0.25, 0.06), (0.2, 0.2), (0.75, 0.04)],
                                       "bot": [(-0.25, 0.05), (0.2, 0.2), (0.75, 0.04)], "n": 2.2}, m["white"]))
        gear = kit.join("Gear", g, (0, 0, 0.9))
        nodes["Gear"] = gear
        nodes["Gear"]["fixed"] = True
        parts += nav_lights(m, (-span * 0.5, 1.0, wz + 0.1), (span * 0.5, 1.0, wz + 0.1), tail=(0, t0 + 0.05, 1.66), beacon=(0, t0 + 0.75, 3.06))
        parts.append(lamp("landing", (-span * 0.28, 1.56, wz - 0.02), m["lamp"], 0.07))
    elif kind == "merlin":
        # Low-wing twin turboprop with a T-tail and retractable gear.
        n0, t0 = L * 0.5, -L * 0.5
        fus = body("fuselage", {"y0": t0, "y1": n0, "n_st": 46, "z": [(t0, 1.95), (-2.5, 1.55), (n0, 1.3)],
                                "w": [(t0, 0.08), (-3.4, 0.5), (-1.2, 0.78), (2.6, 0.78), (4.4, 0.55), (n0, 0.04)],
                                "top": [(t0, 0.18), (-3.4, 0.55), (-1.0, 0.82), (2.6, 0.84), (3.6, 0.62), (4.5, 0.32), (n0, 0.04)],
                                "bot": [(t0, 0.08), (-3.4, 0.45), (-1.0, 0.75), (3.0, 0.72), (n0, 0.04)],
                                "n": [(t0, 2.0), (0.0, 2.25), (n0, 2.0)]}, m["white"])
        pj = Proj(fus)
        parts += [fus,
                  pj.patch("screen", m["glass"], "+z", -0.62, 0.62, {"lin": [(-0.62, 3.55), (0, 3.62), (0.62, 3.55)]}, {"lin": [(-0.62, 4.35), (0, 4.6), (0.62, 4.35)]}, r=0.15, nb=8),
                  *pj.both("cockpit_side", m["glass"], 2.95, 3.65, [(2.95, 1.72), (3.65, 1.68)], [(2.95, 2.18), (3.65, 1.98)], r=0.1),
                  *pj.windows("win", m["glass"], [-1.8, -0.9, 0.0, 0.9, 1.8], 0.42, 1.68, 2.0, r=0.15),
                  *pj.both("cheat", m["paint2"], t0 + 0.6, n0 - 0.3, {"lin": [(t0 + 0.6, 1.92), (-2.5, 1.38), (n0 - 0.3, 1.18)]}, {"lin": [(t0 + 0.6, 2.05), (-2.5, 1.5), (n0 - 0.3, 1.3)]}, off=0.008),
                  *pj.both("cheat_hi", m["paint2"], t0 + 0.8, 2.6, {"lin": [(t0 + 0.8, 2.12), (-2.5, 1.6), (2.6, 1.6)]}, {"lin": [(t0 + 0.8, 2.15), (-2.5, 1.63), (2.6, 1.63)]}, off=0.008)]
        parts.append(body("belly_fair", {"y0": -1.8, "y1": 2.0, "n_st": 12, "z": 0.95, "ends": True,
                                         "w": [(-1.8, 0.3), (-0.8, 0.95), (1.0, 0.95), (2.0, 0.4)], "top": 0.3,
                                         "bot": [(-1.8, 0.05), (-0.6, 0.25), (1.0, 0.25), (2.0, 0.05)], "n": 3.0}, m["white"]))
        wz = 0.92
        w = wing("wing", [(0.0, wz, 1.9, 2.0), (2.6, wz + 0.12, 1.8, 1.75), (span * 0.5, wz + 0.32, 1.25, 0.95)], m["white"], thick=0.15)
        parts.append(w)
        for s in (-1, 1):
            ex = s * 2.6
            parts += nacelle(f"nac{s}", -0.9, 3.0, ex, wz + 0.15, 0.4, m, inlet=False, exhaust=False,
                             shape=[(-0.9, 0.08), (0.0, 0.32), (1.8, 0.4), (2.7, 0.38), (3.0, 0.28)])
            parts.append(rbox(f"lip{s}", (0.22, 0.12, 0.12), (ex, 2.85, wz - 0.12), m["intake"], 0.02))
            parts.append(disc(f"stack{s}", 0.08, (ex + s * 0.38, 2.1, wz + 0.2), m["exhaust"], "x", 10, 0.12))
            p = propeller(f"Prop_{'L' if s < 0 else 'R'}", 4, 1.15, m, 0.2, 0.45)
            p.location = (ex, 3.02, wz + 0.15)
            nodes[p.name] = p
            pb = blur_disc(f"PropBlur_{'L' if s < 0 else 'R'}", 1.15, m, "y")
            pb.location = (ex, 3.1, wz + 0.15)
            nodes[pb.name] = pb
        fin = surface("fin", [(2.0, 0.0, t0 + 2.2, 2.3, 0.12), (3.55, 0.0, t0 + 1.0, 1.3, 0.11)], m["white"], vertical=True)
        parts.append(fin)
        assign(fin, m["paint2"], lambda c, n: 2.4 < c.z < 3.1)
        parts.append(wing("stab", [(0.0, 3.55, t0 + 1.25, 1.2), (2.4, 3.6, t0 + 0.9, 0.75)], m["white"], thick=0.1))
        g = gear_leg("nose", Vector((0, 4.4, 0.95)), Vector((0, 4.45, 0.0)), 0.22, 0.14, m)
        for s in (-1, 1):
            g += gear_leg(f"main{s}", Vector((s * 2.6, 0.9, 0.85)), Vector((s * 2.6, 0.9, 0.0)), 0.33, 0.18, m, twin=True)
        nodes["Gear"] = kit.join("Gear", g, (0, 0, 0.95))
        parts += nav_lights(m, (-span * 0.5, 1.0, wz + 0.32), (span * 0.5, 1.0, wz + 0.32), tail=(0, t0 + 0.6, 3.62), beacon=(0, t0 + 1.5, 4.0), belly=(0, -1.0, 0.68))
        parts.append(lamp("landing", (0, 4.6, 1.0), m["lamp"], 0.07))
    elif kind == "aurora":
        # Business jet: area-ruled fuselage, swept wing with winglets, rear engines, T-tail.
        n0, t0 = L * 0.5, -L * 0.5
        fus = body("fuselage", {"y0": t0, "y1": n0, "n_st": 56, "z": [(t0, 2.55), (-6.0, 2.0), (n0, 1.75)],
                                "w": [(t0, 0.1), (-7.0, 0.55), (-5.0, 0.92), (5.0, 0.98), (7.6, 0.75), (9.0, 0.4), (n0, 0.03)],
                                "top": [(t0, 0.3), (-7.0, 0.62), (-4.8, 1.0), (5.2, 1.02), (7.0, 0.8), (8.6, 0.42), (n0, 0.03)],
                                "bot": [(t0, 0.1), (-6.5, 0.55), (-4.5, 0.95), (6.0, 0.95), (8.6, 0.55), (n0, 0.03)],
                                "n": 2.05}, m["white"])
        pj = Proj(fus)
        parts += [fus,
                  pj.patch("screen", m["glass"], "+z", -0.72, 0.72, {"lin": [(-0.72, 7.3), (0, 7.45), (0.72, 7.3)]}, {"lin": [(-0.72, 8.15), (0, 8.4), (0.72, 8.15)]}, r=0.2, nb=8),
                  *pj.both("cockpit_side", m["glass"], 7.0, 7.85, [(7.0, 2.22), (7.85, 2.12)], [(7.0, 2.55), (7.85, 2.38)], r=0.1),
                  *pj.windows("win", m["glass"], [-3.4 + 1.05 * k for k in range(8)], 0.46, 2.1, 2.62, r=0.2),
                  *pj.both("cheat", m["paint2"], t0 + 1.2, n0 - 0.6, {"lin": [(t0 + 1.2, 2.3), (-6.0, 1.62), (n0 - 0.6, 1.3)]}, {"lin": [(t0 + 1.2, 2.45), (-6.0, 1.78), (n0 - 0.6, 1.42)]}, off=0.008),
                  *pj.both("cheat2", m["paint"], t0 + 1.4, 6.0, {"lin": [(t0 + 1.4, 2.5), (-6.0, 1.84), (6.0, 1.5)]}, {"lin": [(t0 + 1.4, 2.55), (-6.0, 1.88), (6.0, 1.54)]}, off=0.008),
                  *pj.outline("door", m["seam"], 5.2, 6.2, 1.35, 2.85)]
        parts.append(body("wing_fair", {"y0": -3.4, "y1": 2.5, "n_st": 14, "z": 1.15, "ends": True,
                                        "w": [(-3.4, 0.4), (-2.0, 1.12), (1.0, 1.15), (2.5, 0.6)], "top": 0.4,
                                        "bot": [(-3.4, 0.1), (-1.6, 0.3), (1.0, 0.3), (2.5, 0.1)], "n": 3.0}, m["white"]))
        wz = 1.05
        hs = span * 0.5
        w = wing("wing", [(0.0, wz, 2.2, 3.6, 0.13), (1.3, wz + 0.06, 2.0, 3.2, 0.12), (hs - 0.3, wz + 0.55, -1.6, 1.15, 0.1), (hs, wz + 0.6, -1.95, 0.95, 0.09)], m["white"], thick=0.12)
        parts.append(w)
        for s in (-1, 1):
            parts.append(surface(f"winglet{s}", [(wz + 0.6, s * hs, -1.95, 0.95, 0.08), (wz + 1.85, s * (hs + 0.45), -3.0, 0.42, 0.08)], m["paint2"], vertical=True))
            # Rear engine on a pylon.
            ex = s * 1.75
            parts += nacelle(f"eng{s}", -8.6, -5.4, ex, 3.05, 0.55, m)
            parts.append(rbox(f"pylon{s}", (0.9, 1.6, 0.16), (s * 1.15, -6.9, 2.85), m["white"], 0.06))
        fin = surface("fin", [(3.2, 0.0, t0 + 3.3, 3.0, 0.11), (6.0, 0.0, t0 + 1.0, 1.7, 0.1)], m["white"], vertical=True)
        parts.append(fin)
        assign(fin, m["paint2"], lambda c, n: c.z > 4.6)
        parts.append(wing("stab", [(0.0, 6.0, t0 + 1.4, 1.75, 0.1), (3.3, 6.15, t0 + 0.2, 0.9, 0.09)], m["white"], thick=0.1))
        g = gear_leg("nose", Vector((0, 7.4, 1.2)), Vector((0, 7.5, 0.0)), 0.22, 0.14, m, twin=True)
        for s in (-1, 1):
            g += gear_leg(f"main{s}", Vector((s * 1.6, -1.6, 1.05)), Vector((s * 1.7, -1.6, 0.0)), 0.38, 0.2, m, twin=True)
        nodes["Gear"] = kit.join("Gear", g, (0, 0, 1.2))
        parts += nav_lights(m, (-hs - 0.42, -2.95, wz + 1.8), (hs + 0.42, -2.95, wz + 1.8), tail=(0, t0 + 0.05, 2.6), beacon=(0, -1.0, 3.6), belly=(0, -1.0, 0.82))
        parts.append(lamp("landing", (0, 8.3, 1.05), m["lamp"], 0.08))
    else:  # liner
        n0, t0 = L * 0.5, -L * 0.5
        R0, zc = 1.98, 3.85
        fus = body("fuselage", {"y0": t0, "y1": n0, "n_st": 60, "z": [(t0, zc + 1.4), (-10.0, zc + 0.05), (n0, zc - 0.55)],
                                "w": [(t0, 0.2), (-14.5, 0.9), (-10.0, R0), (13.0, R0), (16.0, 1.5), (17.4, 0.75), (n0, 0.05)],
                                "top": [(t0, 0.35), (-14.5, 1.0), (-10.0, R0 + 0.05), (13.5, R0 + 0.05), (16.0, 1.35), (17.4, 0.6), (n0, 0.05)],
                                "bot": [(t0, 0.2), (-13.0, 0.9), (-9.5, R0), (14.0, R0), (16.5, 1.4), (n0, 0.05)],
                                "n": 2.0}, m["white"])
        pj = Proj(fus)
        parts += [fus,
                  pj.patch("screen", m["glass"], "+z", -1.0, 1.0, {"lin": [(-1.0, 15.85), (0, 16.05), (1.0, 15.85)]}, {"lin": [(-1.0, 16.55), (0, 16.85), (1.0, 16.55)]}, r=0.1, nb=6),
                  *pj.both("cockpit_side", m["glass"], 15.2, 16.0, [(15.2, 4.52), (16.0, 4.42)], [(15.2, 4.85), (16.0, 4.72)], r=0.06),
                  *pj.both("win_band", m["glass"], -11.5, 12.5, zc + 0.3, zc + 0.62, r=0.15, off=0.01, na=60, nb=3),
                  *pj.both("cheat", m["paint2"], -13.5, n0 - 0.8, {"lin": [(-13.5, zc - 0.32), (n0 - 0.8, zc - 0.9)]}, {"lin": [(-13.5, zc - 0.05), (n0 - 0.8, zc - 0.62)]}, off=0.008),
                  *pj.outline("door_f", m["seam"], 12.6, 13.6, zc - 1.2, zc + 0.95),
                  *pj.outline("door_r", m["seam"], -12.5, -11.6, zc - 1.0, zc + 0.95)]
        parts.append(body("belly_fair", {"y0": -7.5, "y1": 3.5, "n_st": 14, "z": zc - 1.75, "ends": True,
                                         "w": [(-7.5, 0.6), (-5.0, 1.9), (2.0, 1.9), (3.5, 0.8)], "top": 0.4,
                                         "bot": [(-7.5, 0.1), (-4.0, 0.45), (2.0, 0.45), (3.5, 0.1)], "n": 2.8}, m["grey"]))
        wz = zc - 1.55
        hs = span * 0.5
        w = wing("wing", [(0.0, wz, 3.6, 7.6, 0.13), (1.9, wz + 0.1, 3.3, 7.0, 0.12), (6.2, wz + 0.45, 0.4, 4.0, 0.11),
                          (hs - 0.35, wz + 1.2, -6.8, 1.6, 0.1), (hs, wz + 1.25, -7.1, 1.4, 0.1)], m["white"], thick=0.12)
        parts.append(w)
        for s in (-1, 1):
            parts.append(surface(f"winglet{s}", [(wz + 1.25, s * hs, -7.1, 1.4, 0.08), (wz + 3.4, s * (hs + 0.25), -8.3, 0.6, 0.08)], m["paint2"], vertical=True))
            ex = s * 5.9
            parts += nacelle(f"eng{s}", -1.4, 3.4, ex, wz - 0.95, 0.98, m,
                             shape=[(-1.4, 0.55), (-0.8, 0.85), (1.8, 1.02), (3.1, 1.0), (3.4, 0.92)])
            parts.append(disc(f"spinner{s}", 0.3, (ex, 3.35, wz - 0.95), m["metal"], "y", 14, 0.4, r2=0.02))
            parts.append(rbox(f"pylon{s}", (0.22, 3.4, 0.8), (ex, 0.9, wz - 0.2), m["grey"], 0.05))
            # Flap track fairings.
            for k, fx in enumerate((3.0, 8.0, 12.0)):
                fy = lin([(0, 3.6 - 7.6), (6.2, 0.4 - 4.0), (hs, -7.1 - 1.4)], fx)
                parts.append(body(f"track{s}{k}", {"y0": fy - 1.2, "y1": fy + 0.9, "n_st": 8, "x": s * fx, "z": wz + lin([(0, 0), (6.2, 0.45), (hs, 1.25)], fx) - 0.1,
                                                   "w": [(fy - 1.2, 0.02), (fy - 0.4, 0.12), (fy + 0.9, 0.04)], "top": 0.08,
                                                   "bot": [(fy - 1.2, 0.04), (fy - 0.2, 0.3), (fy + 0.9, 0.04)], "n": 2.0}, m["grey"]))
        fin = surface("fin", [(zc + 1.4, 0.0, t0 + 6.4, 5.6, 0.11), (zc + 7.6, 0.0, t0 + 2.2, 2.3, 0.1)], m["paint2"], vertical=True)
        parts.append(fin)
        parts.append(wing("stab", [(0.0, zc + 1.0, t0 + 4.4, 3.4, 0.1), (6.0, zc + 1.6, t0 + 1.6, 1.4, 0.09)], m["white"], thick=0.1))
        parts.append(disc("apu", 0.25, (0, t0 - 0.05, zc + 1.45), m["exhaust"], "y", 10, 0.3))
        g = gear_leg("nose", Vector((0, 13.8, 2.3)), Vector((0, 13.9, 0.0)), 0.38, 0.22, m, twin=True)
        for s in (-1, 1):
            g += gear_leg(f"main{s}", Vector((s * 3.0, -1.6, 2.3)), Vector((s * 3.0, -1.6, 0.0)), 0.6, 0.38, m, twin=True)
        nodes["Gear"] = kit.join("Gear", g, (0, 0, 2.3))
        parts += nav_lights(m, (-hs - 0.25, -8.3, wz + 3.4), (hs + 0.25, -8.3, wz + 3.4), tail=(0, t0 + 0.1, zc + 1.4), beacon=(0, -2.0, zc + 2.05), belly=(0, -2.0, zc - 2.25))
    return parts, nodes


# ---------------------------------------------------------------- boats


def hull(name, P, m, segs_side=7):
    """Deep-vee hull: stations along y; at each, keel depth, deadrise, chine, flare, sheer.
    Ring: keel -> chine -> sheer (topside) -> deck edge -> deck centre, mirrored."""
    y0, y1 = P["y0"], P["y1"]
    rings = []
    ns = P.get("n_st", 36)
    for i in range(ns + 1):
        t = i / ns
        y = y0 + (y1 - y0) * t
        hw = max(0.01, cv(P["beam"], y))
        keel = cv(P["keel"], y)
        chine_z = cv(P["chine_z"], y)
        chine_w = hw * cv(P.get("chine_w", 0.86), y)
        sheer = cv(P["sheer"], y)
        flare = cv(P.get("flare", 0.0), y)
        camber = P.get("camber", 0.06)
        half = [Vector((0.0, keel))]
        # Bottom: keel to chine, slightly convex.
        for k in range(1, 4):
            u = k / 3
            x = chine_w * u
            z = keel + (chine_z - keel) * (u ** 0.85)
            half.append(Vector((x, z)))
        half.append(Vector((chine_w + 0.04 * hw, chine_z + 0.01)))  # chine flat (spray rail)
        # Topside: chine to sheer with flare.
        for k in range(1, segs_side):
            u = k / segs_side
            x = chine_w + (hw - chine_w) * math.sin(u * math.pi / 2) + flare * u * u
            z = chine_z + (sheer - chine_z) * u
            half.append(Vector((x, z)))
        half.append(Vector((hw + flare, sheer)))
        half.append(Vector(((hw + flare) * 0.55, sheer + camber * 0.8)))
        half.append(Vector((0.0, sheer + camber)))
        ring = half + [Vector((-p.x, p.y)) for p in reversed(half[1:-1])]
        rings.append([Vector((p.x, y, p.y)) for p in ring])
    ob = loft(name, rings, m["paint"], cap=True, smooth=35)
    return ob


def sheer_rail(name, P, m, material, inset=0.0, dz=0.03, r=0.05, y_end=None):
    """A rail / rubbing strake following the hull's sheer line, both sides, meeting at the bow."""
    y0, y1 = P["y0"], y_end if y_end is not None else P["y1"]
    out = []
    for s in (-1, 1):
        pts = []
        n = 28
        for i in range(n + 1):
            y = y0 + 0.05 + (y1 - y0 - 0.05) * i / n
            hw = max(0.0, cv(P["beam"], y) + cv(P.get("flare", 0.0), y) - inset)
            pts.append((s * hw, y, cv(P["sheer"], y) + dz))
        out.append(tube(f"{name}{s}", pts, r, material, 8))
    return out


def hull_mats(hb, m, top=None):
    """Antifouling below the waterline, the owner's colour on the topsides, a white deck."""
    assign(hb, m["antifoul"], lambda c, n: c.z < -0.02 and n.z < 0.7)
    assign(hb, m["white"], lambda c, n: n.z > 0.75 and c.z > 0.2)
    if top is not None:
        assign(hb, top, lambda c, n: n.z > 0.75 and c.z > 0.2)


def boat(spec_id, S, m):
    W, H, L = S["size"]
    parts, nodes = [], {}
    kind = spec_id
    if kind == "dart":
        y0, y1 = -L * 0.5, L * 0.5
        HP = {"y0": y0, "y1": y1, "n_st": 34,
              "beam": [(y0, 0.92), (0.5, 1.0), (y1 - 1.2, 0.72), (y1 - 0.3, 0.2), (y1, 0.03)],
              "keel": [(y0, -0.32), (0.8, -0.42), (y1 - 0.8, -0.2), (y1, 0.42)],
              "chine_z": [(y0, -0.12), (y1 - 1.0, -0.05), (y1, 0.4)],
              "sheer": [(y0, 0.48), (0.0, 0.52), (y1, 0.72)], "flare": [(y0, 0.0), (y1 - 1.5, 0.05), (y1, 0.0)],
              "camber": 0.03}
        hb = hull("hull", HP, m)
        parts.append(hb)
        hull_mats(hb, m)
        parts += Proj(hb).both("boot", m["white"], y0 + 0.05, y1 - 0.5, {"lin": [(y0, 0.04), (y1 - 0.5, 0.2)]}, {"lin": [(y0, 0.1), (y1 - 0.5, 0.26)]}, off=0.008)
        parts += sheer_rail("rub", HP, m, m["white"], 0.0, 0.0, 0.05)
        deck = 0.52
        # Open cockpit: sole, seats, console with a wraparound screen.
        parts.append(rbox("sole", (1.5, 3.0, 0.02), (0, -0.6, 0.56), m["teak"], 0.005))
        parts.append(rbox("bench", (1.6, 0.55, 0.4), (0, y0 + 0.75, deck + 0.18), m["cushion"], 0.08))
        parts.append(rbox("bench_back", (1.6, 0.14, 0.42), (0, y0 + 0.5, deck + 0.42), m["cushion"], 0.06))
        for s in (-1, 1):
            parts.append(rbox(f"seat{s}", (0.5, 0.5, 0.35), (s * 0.42, -0.25, deck + 0.18), m["cushion"], 0.07))
            parts.append(rbox(f"seatb{s}", (0.5, 0.12, 0.42), (s * 0.42, -0.52, deck + 0.45), m["cushion"], 0.05))
            parts.append(rbox(f"console{s}", (0.6, 0.55, 0.5), (s * 0.44, 0.55, deck + 0.25), m["white"], 0.06))
        parts.append(rbox("dash", (0.42, 0.18, 0.08), (0.44, 0.55, deck + 0.55), m["trim"], 0.02))
        parts.append(kit.cyl("wheel", 0.15, 0.03, (0.44, 0.42, deck + 0.55), m["trim"], 14))
        scr = tube("screen_frame", [(-0.8, 0.95, deck + 0.5), (-0.5, 0.88, deck + 0.85), (0.5, 0.88, deck + 0.85), (0.8, 0.95, deck + 0.5)], 0.015, m["chrome"], 6, cap=True)
        parts.append(scr)
        parts.append(surface("screen", [(-0.8, deck + 0.42, 0.98, 0.07, 0.3), (-0.45, deck + 0.42, 1.12, 0.07, 0.3),
                                        (0.45, deck + 0.42, 1.12, 0.07, 0.3), (0.8, deck + 0.42, 0.98, 0.07, 0.3)], m["glass"], thick=0.3, n=3))
        for s in (-1, 1):
            parts.append(tube(f"rail{s}", [(s * 0.55, y1 - 1.6, deck + 0.12), (s * 0.55, y1 - 1.5, deck + 0.38), (s * 0.15, y1 - 0.3, deck + 0.42), (0, y1 - 0.15, deck + 0.3)], 0.016, m["chrome"], 6))
        parts.append(rbox("bow_cushion", (1.0, 1.0, 0.12), (0, y1 - 1.6, deck + 0.04), m["cushion"], 0.05))
        mots = [0.0]
    elif kind == "swift":
        y0, y1 = -L * 0.5, L * 0.5
        HP = {"y0": y0, "y1": y1, "n_st": 40,
              "beam": [(y0, 1.12), (0.5, 1.2), (y1 - 1.8, 0.86), (y1 - 0.4, 0.22), (y1, 0.03)],
              "keel": [(y0, -0.48), (1.0, -0.58), (y1 - 1.2, -0.3), (y1, 0.55)],
              "chine_z": [(y0, -0.16), (y1 - 1.6, -0.08), (y1, 0.5)],
              "sheer": [(y0, 0.6), (0.0, 0.66), (y1, 0.88)], "flare": [(y0, 0.0), (y1 - 2.2, 0.08), (y1, 0.0)],
              "camber": 0.04}
        hb = hull("hull", HP, m)
        parts.append(hb)
        pj = Proj(hb)
        hull_mats(hb, m)
        parts += sheer_rail("rub", HP, m, m["chrome"], 0.0, 0.0, 0.03)
        parts += pj.both("boot", m["paint2"], y0 + 0.05, y1 - 0.4, {"lin": [(y0, 0.02), (y1 - 0.4, 0.2)]}, {"lin": [(y0, 0.12), (y1 - 0.4, 0.3)]}, off=0.008)
        parts += pj.both("flash", m["white"], 0.0, y1 - 0.9, {"lin": [(0.0, 0.42), (y1 - 0.9, 0.62)]}, {"lin": [(0.0, 0.47), (y1 - 0.9, 0.7)]}, off=0.008)
        deck = 0.66
        parts.append(rbox("sole", (1.8, 3.6, 0.02), (0, -1.0, 0.71), m["teak"], 0.005))
        parts.append(rbox("sunpad", (2.0, 1.3, 0.22), (0, y0 + 0.8, deck + 0.12), m["cushion"], 0.08))
        parts.append(rbox("aft_seat", (1.9, 0.6, 0.42), (0, y0 + 1.75, deck + 0.18), m["cushion"], 0.08))
        for s in (-1, 1):
            parts.append(rbox(f"bolster{s}", (0.55, 0.6, 0.48), (s * 0.48, -0.4, deck + 0.2), m["cushion"], 0.08))
            parts.append(rbox(f"bolsterb{s}", (0.55, 0.14, 0.5), (s * 0.48, -0.72, deck + 0.5), m["cushion"], 0.05))
        parts.append(rbox("helm", (1.6, 0.7, 0.55), (0, 0.5, deck + 0.25), m["white"], 0.1))
        parts.append(rbox("dash", (1.3, 0.3, 0.06), (0, 0.42, deck + 0.56), m["trim"], 0.02))
        parts.append(kit.cyl("wheel", 0.17, 0.03, (0.45, 0.28, deck + 0.6), m["trim"], 14))
        parts.append(surface("screen", [(-1.0, deck + 0.5, 0.85, 0.5, 0.06), (-0.6, deck + 0.85, 0.95, 0.45, 0.06),
                                        (0.6, deck + 0.85, 0.95, 0.45, 0.06), (1.0, deck + 0.5, 0.85, 0.5, 0.06)], m["glass"], thick=0.06, n=4))
        parts.append(rbox("hatch", (0.6, 0.6, 0.03), (0, y1 - 1.9, cv(HP["sheer"], y1 - 1.9) + 0.05), m["glass"], 0.02))
        for s in (-1, 1):
            parts.append(tube(f"rail{s}", [(s * 0.75, y1 - 2.6, deck + 0.16), (s * 0.75, y1 - 2.5, deck + 0.42), (s * 0.2, y1 - 0.5, deck + 0.45), (0, y1 - 0.25, deck + 0.3)], 0.018, m["chrome"], 6))
            parts.append(lamp(f"nav{s}", (s * 1.12, 0.8, deck + 0.12), m["nav_green" if s > 0 else "nav_red"], 0.04))
        mots = [-0.42, 0.42]
    else:  # majesty yacht
        y0, y1 = -L * 0.5, L * 0.5
        hb = hull("hull", {"y0": y0 + 1.2, "y1": y1, "n_st": 56,
                            "beam": [(y0, 3.05), (0.0, 3.25), (6.0, 3.1), (y1 - 4.0, 2.2), (y1 - 1.0, 0.6), (y1, 0.06)],
                            "keel": [(y0, -1.2), (2.0, -1.45), (y1 - 4.0, -1.0), (y1 - 0.5, 1.2), (y1, 1.5)],
                            "chine_z": [(y0, -0.35), (y1 - 5.0, -0.2), (y1, 1.5)],
                            "sheer": [(y0, 1.25), (0.0, 1.35), (y1 - 4.0, 1.9), (y1, 2.35)], "flare": [(y0, 0.0), (y1 - 7.0, 0.18), (y1, 0.05)],
                            "chine_w": 0.82, "camber": 0.12}, m, segs_side=9)
        parts.append(hb)
        pj = Proj(hb)
        hull_mats(hb, m)
        parts += pj.both("boot", m["white"], y0 + 1.3, y1 - 1.6, {"lin": [(y0, 0.0), (y1 - 1.6, 0.3)]}, {"lin": [(y0, 0.16), (y1 - 1.6, 0.48)]}, off=0.01)
        parts += pj.both("hullwin", m["glass"], -2.2, 3.4, [(-2.2, 0.55), (3.4, 0.62)], [(-2.2, 0.85), (3.4, 0.92)], r=0.15, off=0.012)
        parts += pj.both("hullwin2", m["glass"], 5.0, 7.6, [(5.0, 0.72), (7.6, 0.85)], [(5.0, 0.92), (7.6, 1.05)], r=0.1, off=0.012)
        deck = 1.4
        # Swim platform.
        parts.append(rbox("platform", (6.0, 1.6, 0.14), (0, y0 + 0.8, 0.38), m["teak"], 0.04))
        for k in range(3):
            parts.append(rbox(f"step{k}", (2.2, 0.32, 0.12), (0, y0 + 1.75 + k * 0.3, 0.55 + k * 0.3), m["teak"], 0.03))
        # Main deck saloon: a lofted superstructure with a long tinted window band.
        sup = body("saloon", {"y0": -9.0, "y1": 6.4, "n_st": 30, "z": deck + 1.1, "ends": False,
                              "w": [(-9.0, 2.75), (0.0, 2.8), (4.0, 2.6), (6.4, 1.6)],
                              "top": [(-9.0, 1.15), (3.5, 1.15), (6.4, 0.35)],
                              "bot": 1.12, "n": 5.0, "smooth": 35}, m["white"], segs=28)
        parts.append(sup)
        sp = Proj(sup)
        parts += sp.both("saloon_glass", m["glass"], -8.4, 5.6, deck + 0.75, {"lin": [(-8.4, deck + 1.95), (4.0, deck + 1.95), (5.6, deck + 1.65)]}, r=0.5, off=0.015)
        parts.append(sp.patch("saloon_front", m["glass"], "+y", -2.1, 2.1, deck + 1.0, [(-2.1, deck + 1.65), (0, deck + 1.85), (2.1, deck + 1.65)], r=0.4, nb=6, off=0.015))
        parts.append(rbox("aft_deck", (5.4, 4.0, 0.08), (0, -11.0, deck + 0.02), m["teak"], 0.02))
        parts.append(rbox("aft_sofa", (4.2, 0.8, 0.5), (0, -12.0, deck + 0.3), m["cushion"], 0.1))
        parts.append(rbox("aft_table", (1.6, 0.9, 0.06), (0, -10.8, deck + 0.72), m["teak"], 0.02))
        parts.append(rbox("foredeck_pad", (3.6, 2.4, 0.18), (0, 8.8, deck + 0.42), m["cushion"], 0.1))
        # Flybridge: a lower, shorter deck house, hardtop on a radar arch.
        fly = body("flybridge", {"y0": -7.0, "y1": 4.0, "n_st": 20, "z": deck + 2.62, "ends": False,
                                 "w": [(-7.0, 2.55), (2.0, 2.45), (4.0, 1.4)], "top": [(-7.0, 0.38), (2.5, 0.38), (4.0, 0.12)],
                                 "bot": 0.36, "n": 5.0, "smooth": 35}, m["white"], segs=24)
        parts.append(fly)
        parts += Proj(fly).both("fly_band", m["paint"], -6.8, 3.6, deck + 2.42, deck + 2.62, r=0.3, off=0.012)
        parts.append(rbox("fly_screen", (2.6, 0.08, 0.4), (0, 3.2, deck + 3.2), m["glass"], 0.03))
        parts.append(rbox("fly_helm", (1.6, 0.8, 0.8), (0, 2.2, deck + 3.4), m["white"], 0.12))
        parts.append(rbox("fly_sofa", (3.6, 1.6, 0.42), (0, -1.5, deck + 3.2), m["cushion"], 0.12))
        parts.append(rbox("fly_lounge", (3.0, 2.2, 0.2), (0, -5.2, deck + 3.1), m["cushion"], 0.1))
        for s in (-1, 1):
            parts.append(tube(f"arch{s}", [(s * 2.0, -3.4, deck + 3.0), (s * 1.95, -3.0, deck + 4.6), (s * 1.6, -2.4, deck + 5.3)], 0.12, m["white"], 10))
            parts.append(tube(f"rail{s}", [(s * 2.75, -9.2, deck + 1.05), (s * 2.9, 0.0, deck + 1.05), (s * 2.4, 8.0, deck + 1.05), (s * 0.9, 12.8, deck + 1.0), (0, 13.6, deck + 0.95)], 0.03, m["chrome"], 6))
            parts.append(tube(f"fly_rail{s}", [(s * 2.45, -6.8, deck + 3.6), (s * 2.45, 2.2, deck + 3.6)], 0.025, m["chrome"], 6))
        parts.append(rbox("hardtop", (4.2, 5.2, 0.16), (0, -1.0, deck + 5.35), m["white"], 0.08))
        parts.append(rbox("arch_bar", (3.4, 0.6, 0.2), (0, -2.4, deck + 5.25), m["white"], 0.08))
        parts.append(kit.cyl("radar", 0.38, 0.22, (0, -1.6, deck + 5.43), m["white"], 18))
        parts.append(kit.cyl("dome", 0.28, 0.32, (0.9, -2.2, deck + 5.43), m["white"], 14, r2=0.2))
        parts.append(kit.cyl("mast", 0.04, 1.4, (-0.9, -2.4, deck + 5.43), m["metal"], 8))
        parts.append(lamp("mast_light", (-0.9, -2.4, deck + 6.85), m["strobe"], 0.06))
        parts.append(rbox("tender", (3.2, 1.4, 0.55), (0, -6.4, deck + 3.2), m["trim"], 0.25))
        parts.append(rbox("anchor", (0.3, 0.12, 0.45), (0.5, y1 - 0.9, 1.6), m["chrome"], 0.04))
        for s in (-1, 1):
            parts.append(lamp(f"nav{s}", (s * 2.8, 5.6, deck + 1.6), m["nav_green" if s > 0 else "nav_red"], 0.06))
        mots = []
        nodes["Wake"] = None
    # Outboards (own node: they tilt and steer).
    if mots:
        o = []
        for k, x in enumerate(mots):
            yo = -L * 0.5 - 0.25
            big = kind == "swift"
            h = 0.85 if big else 0.7
            o.append(body(f"cowl{k}", {"y0": yo - 0.4, "y1": yo + 0.35, "n_st": 10, "x": x, "z": 0.75 if big else 0.62, "ends": True,
                                       "w": 0.22 if big else 0.18, "top": [(yo - 0.4, 0.18), (yo, 0.28), (yo + 0.35, 0.2)],
                                       "bot": 0.2, "n": 2.6}, m["trim"]))
            o.append(rbox(f"leg{k}", (0.12, 0.26, h), (x, yo - 0.02, 0.6 - h / 2 + 0.05), m["trim"], 0.04))
            o.append(rbox(f"skeg{k}", (0.03, 0.2, 0.2), (x, yo - 0.02, 0.6 - h - 0.05), m["trim"], 0.01))
            o.append(disc(f"prop{k}", 0.14, (x, yo - 0.18, 0.6 - h + 0.08), m["metal"], "y", 10, 0.06))
            o.append(rbox(f"stripe{k}", (0.012, 0.5, 0.05), (x + (0.225 if big else 0.185), yo, 0.72 if big else 0.6), m["paint"], 0.0))
        nodes["Outboard"] = kit.join("Outboard", o, (0, -L * 0.5 - 0.1, 0.5))
    nodes.pop("Wake", None)
    return parts, nodes


# ---------------------------------------------------------------- build + export


SPECS = {}


def load_specs():
    here = os.path.dirname(os.path.abspath(__file__))
    cfg = json.load(open(os.path.join(here, "..", "..", "config", "empire", "vehicles.json")))
    for k, v in cfg["models"].items():
        if v.get("class") in ("heli", "plane", "boat"):
            SPECS[k] = v
    SPECS["liner"] = {"class": "plane", "name": "Airliner (AirTraffic)", "size": [34, 12.6, 36], "paint": "#f2f2f2", "trim": "#1f4f8f"}


def build(cid):
    S = SPECS[cid]
    kit.reset()
    m = mats(hexrgb(S["paint"]), hexrgb(S.get("trim", "#2a2f36")))
    if S["class"] == "heli":
        parts, nodes = heli(cid, S, m)
    elif S["class"] == "plane":
        parts, nodes = plane(cid, S, m)
    else:
        parts, nodes = boat(cid, S, m)
    bodyob = kit.join("Body", parts)
    for o in [bodyob] + list(nodes.values()):
        for p in o.data.polygons:
            p.use_smooth = True
        try:
            o.data.set_sharp_from_angle(angle=math.radians(45))
        except AttributeError:
            pass
    objs = [bodyob] + list(nodes.values())
    # Pivots: each node keeps its own origin (set where it was built / placed).
    for o in nodes.values():
        if o.name in ("Gear", "Outboard"):
            continue
    info = {"class": S["class"], "tris": tri_count(objs),
            "nodes": {o.name: [round(o.location.x, 3), round(o.location.z, 3), round(-o.location.y, 3)] for o in nodes.values()}}
    mn = Vector((1e9, 1e9, 1e9))
    mx = -mn
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            mn = Vector((min(mn[i], w[i]) for i in range(3)))
            mx = Vector((max(mx[i], w[i]) for i in range(3)))
    info["bounds_godot"] = {"min": [round(mn.x, 2), round(mn.z, 2), round(-mx.y, 2)], "max": [round(mx.x, 2), round(mx.z, 2), round(-mn.y, 2)]}
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    path = os.path.join(OUT, cid + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")
    print(f"CRAFT {cid}: {info['tris']} tris, nodes {sorted(info['nodes'])}")
    if RENDER:
        render(cid, S, objs)
    return info


# ---------------------------------------------------------------- review renders


def render(cid, S, objs):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 32
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 1200, 760
    sc.view_settings.exposure = -0.6
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sun_elevation = math.radians(32)
    sky.sun_rotation = math.radians(150)
    try:
        sky.sky_type = "NISHITA"
    except TypeError:
        pass
    nt.links.new(sky.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    nt.nodes["Background"].inputs["Strength"].default_value = 0.12
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 2.2
    sun.angle = math.radians(2)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(55), 0, math.radians(150))
    sc.collection.objects.link(so)
    # Ground: apron concrete for aircraft, water for boats.
    size = max(S["size"][0], S["size"][2])
    bpy.ops.mesh.primitive_plane_add(size=size * 8, location=(0, 0, 0))
    g = bpy.context.active_object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gb = gm.node_tree.nodes["Principled BSDF"]
    if S["class"] == "boat":
        gb.inputs["Base Color"].default_value = (0.02, 0.07, 0.09, 1)
        gb.inputs["Roughness"].default_value = 0.08
        noise = gm.node_tree.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 3.0
        bump = gm.node_tree.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.15
        gm.node_tree.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        gm.node_tree.links.new(bump.outputs["Normal"], gb.inputs["Normal"])
    else:
        gb.inputs["Base Color"].default_value = (0.13, 0.13, 0.13, 1)
        gb.inputs["Roughness"].default_value = 0.85
    g.data.materials.append(gm)
    # Hide the blur discs in the beauty shot (they're for motion).
    for o in objs:
        if "Blur" in o.name:
            o.hide_render = True
    cam = bpy.data.cameras.new("cam")
    cam.lens = 50
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    mn = Vector((1e9, 1e9, 1e9))
    mx = -mn
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            mn = Vector((min(mn[i], w[i]) for i in range(3)))
            mx = Vector((max(mx[i], w[i]) for i in range(3)))
    c = (mn + mx) / 2
    rad = (mx - mn).length / 2
    for tag, az, el in (("34", 50, 16), ("side", 0, 4), ("rear", -130, 24)):
        d = rad * 2.25
        a, e = math.radians(az), math.radians(el)
        co.location = c + Vector((math.cos(a) * math.cos(e) * d, math.sin(a) * math.cos(e) * d, math.sin(e) * d + rad * 0.1))
        look = (c - co.location)
        co.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(RENDER, f"{cid}_{tag}.png")
        bpy.ops.render.render(write_still=True)


def main():
    load_specs()
    ids = [k for k in SPECS if not ONLY or k in ONLY]
    report = {}
    rp = os.path.join(OUT, "craft.json")
    if os.path.exists(rp):
        report = json.load(open(rp))
    for cid in ids:
        report[cid] = build(cid)
    json.dump(report, open(rp, "w"), indent=1, sort_keys=True)


if __name__ == "__main__" and not os.environ.get("CRAFT_NO_MAIN"):
    main()
