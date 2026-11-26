"""WorldState fleet: traffic, parked and service vehicles built with the
Kestrel's generator (tools/blender/kestrel.py) at traffic detail.

Run:  blender -b --factory-startup --python tools/blender/ws_fleet.py -- <out dir> [names,...]

Each body is the same subdivision-cage shell as the Kestrel (one surface for
body and greenhouse, creased shoulder and lower-door lines, curved panels,
rounded raked ends), with real panel gaps and lamps in recesses, but sized
for instancing: the shell is decimated hard (shading from the full shell),
the glass is sealed and tinted (no cabin, no transparency), lenses are the
lit lamps themselves, and there is no interior. Proportions are taken from
real cars of each class:

  civ_compact    supermini hatch (Polo / Fiesta class)  4.05 x 1.75 x 1.47 m, wb 2.55
  civ_sedan      D-segment saloon (Passat / Mondeo)     4.80 x 1.83 x 1.46 m, wb 2.79
  civ_taxi       the saloon with a roof sign
  civ_suv        compact SUV (Tiguan / RAV4)            4.60 x 1.86 x 1.68 m, wb 2.69
  civ_van        mid panel van (Transit Custom)         5.00 x 2.00 x 1.98 m, wb 2.93
  civ_police     UK police estate, Battenburg livery and light bar
  civ_ambulance  the van as a UK ambulance (yellow, green checks, beacons)
  wheel_traffic  a light alloy wheel for all of them (~300 triangles)

Writes each GLB plus its dimensions into bodies.json / body_dims.gd.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector as V

sys.path.insert(0, os.path.dirname(__file__))
import kestrel as K  # noqa: E402  (its build() only runs as a script)
import ws_rear as R  # noqa: E402
import build_kit as kit  # noqa: E402
from build_kit import box, cyl  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "assets/vehicles"
ONLY = set(ARGS[1].split(",")) if len(ARGS) > 1 and ARGS[1] else set()
kit.OUT = OUT


# ------------------------------------------------------------------ designs
def design(L, W, H, wb, oh_f, wr, ride, belt, nose, kind, tyre_w=0.215, boot=None):
    """Globals for kestrel.py's shell from a few real-world numbers.
    kind: hatch | estate | saloon | suv | van."""
    oh_r = L - wb - oh_f
    YF, YR = wb / 2 + oh_f, -wb / 2 - oh_r
    AX = (wb / 2, -wb / 2)
    d = dict(WB=wb, WR=wr, TYRE_W=tyre_w, OH_F=oh_f, OH_R=oh_r, YF=YF, YR=YR, W2=W / 2, RIDE=ride, ROOF=H,
             ARCH=wr + 0.042, AX=AX, SILL_Z=ride + 0.17, TUMBLE=0.12, END_RF=0.34, END_RR=0.3, REAR_EXP=2.2,
             SEALED=False, SEG_K=0.5,
             # A real cabin, as the cars you buy (2026-11-26: "all vehicles need
             # to be just as good as each other"): cavity sized from the ride.
             CAV_Z0=ride + 0.26, CAV_ZM=ride + 0.6, CAV_Y0=None, CAV_Y1=None)
    if kind == "saloon":
        d.update(Y_COWL=AX[0] - 0.36, Y_WS=AX[0] - 1.18, Y_RE=AX[1] + 0.62, Y_TG=AX[1] - 0.12, REAR_EXP=1.25)
    elif kind == "hatch":
        # Supermini: the roof drops away from above the rear wheel.
        d.update(Y_COWL=AX[0] - 0.37, Y_WS=AX[0] - 1.17, Y_RE=AX[1] + 0.12, Y_TG=YR + 0.1, REAR_EXP=1.5)
    elif kind == "estate":
        d.update(Y_COWL=AX[0] - 0.36, Y_WS=AX[0] - 1.25, Y_RE=YR + 0.3, Y_TG=YR + 0.16)
    elif kind == "suv":
        d.update(Y_COWL=AX[0] - 0.3, Y_WS=AX[0] - 1.1, Y_RE=YR + 0.24, Y_TG=YR + 0.1, TUMBLE=0.1, END_RF=0.3, END_RR=0.24)
    elif kind == "van":
        d.update(Y_COWL=AX[0] + 0.32, Y_WS=AX[0] - 0.42, Y_RE=YR + 0.06, Y_TG=YR + 0.02, TUMBLE=0.05, END_RF=0.32,
                 END_RR=0.12, REAR_EXP=1.0)
        d["CAV_Y0"] = AX[0] - (wr + 0.042) - 0.95    # cab only (bulkhead behind the seats)
    cowl = belt - 0.025
    bonnet = [(d["Y_COWL"] + (YF - d["Y_COWL"]) * t, cowl - (cowl - nose) * t ** 1.6) for t in (0.3, 0.6, 0.85)]
    rear_z = (boot if boot else belt + 0.02)
    d["DECK"] = sorted([(YR, rear_z - 0.01), (d["Y_TG"], rear_z), ((d["Y_TG"] + 0.0) / 2 - 0.4, belt + 0.03),
                        (0.0, belt), (d["Y_COWL"], cowl)] + bonnet + [(YF - 0.1, nose + 0.03), (YF, nose)])
    k = belt - ride
    d["CREASE"] = [(YR, rear_z - 0.09), (YR + 0.25, rear_z - 0.05), (0.0, belt - 0.075), (AX[0] + 0.1, belt - 0.12),
                   (YF - 0.15, nose + 0.01), (YF, nose - 0.01)]
    d["SWELL"] = [(YR, ride + 0.58 * k), (0.0, ride + 0.6 * k), (YF, ride + 0.54 * k)]
    d["SCULPT"] = [(YR, ride + 0.38 * k), (0.0, ride + 0.36 * k), (YF, ride + 0.36 * k)]
    d["BOTTOM"] = [(YR, ride + 0.19), (YR + 0.3, ride + 0.06), (AX[1] - 0.45, ride + 0.015), (AX[0] + 0.45, ride + 0.015),
                   (YF - 0.3, ride + 0.06), (YF, ride + 0.12)]
    d["_kind"] = kind
    d["_belt"] = belt
    d["_nose"] = nose
    d["_boot"] = rear_z
    return d


DESIGNS = {
    "civ_compact": design(4.05, 1.75, 1.47, 2.55, 0.82, 0.305, 0.14, 0.98, 0.79, "hatch"),
    "civ_sedan": design(4.8, 1.83, 1.46, 2.79, 0.92, 0.325, 0.14, 1.0, 0.78, "saloon", boot=1.02),
    "civ_taxi": design(4.8, 1.83, 1.46, 2.79, 0.92, 0.325, 0.14, 1.0, 0.78, "saloon", boot=1.02),
    "civ_suv": design(4.6, 1.86, 1.68, 2.69, 0.92, 0.36, 0.2, 1.12, 0.92, "suv", tyre_w=0.235),
    "civ_van": design(5.0, 2.0, 1.98, 2.93, 0.95, 0.34, 0.18, 1.12, 0.98, "van", tyre_w=0.225),
    "civ_police": design(4.62, 1.8, 1.48, 2.68, 0.88, 0.32, 0.14, 1.0, 0.8, "estate"),
    "civ_ambulance": design(5.0, 2.0, 1.98, 2.93, 0.95, 0.34, 0.18, 1.12, 0.98, "van", tyre_w=0.225),
}


REGS = {"civ_compact": "CP19 KLM", "civ_sedan": "SD68 WRT", "civ_taxi": "TX21 CAB", "civ_suv": "SV70 HNR",
        "civ_van": "VN62 DLV", "civ_police": "PL17 CEW", "civ_ambulance": "AM20 NHS"}


def use(name):
    d = DESIGNS[name]
    for k, v in d.items():
        if not k.startswith("_"):
            setattr(K, k, v)
    return d


# ------------------------------------------------------------------ build
def glass_sheet(surf, m, out, view, poly, side=1, lift=0.011, frit=0.025, res=(7, 3)):
    """Sealed glass laid over the shell (tinted, no cut), on a black border."""
    fn = K.poly_fn(poly)
    if frit:
        c = [V(p) for p in poly]
        cen = sum(c, V((0, 0))) / 4
        big = [tuple(cen + (p - cen) * (1 + frit / max((p - cen).length, 1e-3))) for p in c]
        gf = K.patch(surf, view, K.poly_fn(big), res[0], res[1], side)
        # (well under the glass: 2 mm apart they z-fought in the game at
        # distance - black blotches on the glass)
        out.append(K.sheet("frit", gf, min(0.003, lift - 0.004), m["trim"]))
    g = K.patch(surf, view, fn, res[0], res[1], side)
    out.append(K.sheet("glass", g, lift, m["glass"]))


def gap_decal(surf, m, out, line, view, w=0.006, side=1, lift=0.0015):
    """A panel gap as a thin dark strip laid on the paint (traffic: a boolean
    cut costs ~300 triangles a line through the shell; at traffic distances
    a 4.5 mm gap reads the same)."""
    pts = [V(p) for p in line]
    dense = []
    for a, b in zip(pts, pts[1:]):
        n = max(1, math.ceil((b - a).length / 0.055))
        dense += [a.lerp(b, i / n) for i in range(n)]
    dense.append(pts[-1])
    sides = (1, -1) if view == "side" and side == 0 else (side,)
    for sd in sides:
        row0, row1 = [], []
        for i, p in enumerate(dense):
            q = dense[min(i + 1, len(dense) - 1)] - dense[max(i - 1, 0)]
            nrm = V((-q.y, q.x)).normalized() * (w / 2) if q.length > 1e-6 else V((0, w / 2))
            h0 = surf.cast(*K.ray(view, *(p + nrm), sd))
            h1 = surf.cast(*K.ray(view, *(p - nrm), sd))
            row0.append((h0[0], h0[1]) if h0 else None)
            row1.append((h1[0], h1[1]) if h1 else None)
        out.append(K.sheet("gap", [row0, row1], lift, m["liner"]))


def livery(surf, m, out, y0, y1, z0, z1, cols, rows=2, cell=0.24):
    """Battenburg checks along both sides between two heights."""
    n = int((y1 - y0) / cell)
    for i in range(n):
        for r in range(rows):
            mt = m[cols[(i + r) % 2]]
            za = z0 + (z1 - z0) * r / rows
            zb = z0 + (z1 - z0) * (r + 1) / rows
            ya, yb = y0 + i * cell, y0 + (i + 1) * cell
            for sd in (1, -1):
                g = K.patch(surf, "side", K.poly_fn([(ya, za), (yb, za), (yb, zb), (ya, zb)]), 3, 2, sd)
                if all(c for row in g for c in row):
                    out.append(K.sheet("livery", g, 0.0025, mt))


def cabin_interior(m, out, kind, doors):
    """The Kestrel's interior (dashboard, binnacle, screen, vents, console,
    bolstered seats, door cards, steering wheel) refitted to this car: moved
    to its cowl, its floor and its roof (low cars get low-slung seats), wider
    or narrower with the body, rear bench only where there are rear seats."""
    tmp = []
    K.interior(m, tmp)
    dash_names = ("dash", "dash_top", "binnacle", "cluster", "gauge_ring", "screen", "screen_bezel",
                  "vent", "wheel_rim", "spoke", "hub", "hub_badge", "column", "pedal")
    rear_names = ("rear_bench", "rear_back", "rear_headrest")
    rear = (doors == 4 or kind == "hatch") and kind not in ("pickup", "van", "box")
    dash, seats, back = [], [], []
    for o in tmp:
        base = o.name.split(".")[0]
        if base in ("floor_pan", "boot_floor", "door_card", "armrest", "door_pull") or (base in rear_names and not rear):
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        (dash if base in dash_names else back if base in rear_names else seats).append(o)
    dy = K.Y_COWL - 0.97
    kx = (K.W2 - 0.095) / 0.8
    # Kestrel: cavity floor 0.4, headrest tops 1.34 under a 1.41 cavity roof.
    room = K.ROOF - 0.06 - K.CAV_Z0
    sz = min(1.0, (room - 0.07) / 0.94)
    if seats:
        g = kit.join("seats", seats)
        g.location = (0, dy, K.CAV_Z0 - 0.4 * sz)
        g.scale = (kx, 1.0, sz)
        out.append(g)
    # Door cards fitted to this cabin: inside the door skin, only as long as
    # the cabin (the Kestrel's 1.8 m cards, widened, came out through the
    # side intakes of the mid-engined cars).
    y1 = K.Y_COWL - 0.3
    y0 = max(K.CAV_Y0 + 0.08 if K.CAV_Y0 is not None else K.YR + 0.4, y1 - (1.95 if rear else 1.15))
    yc = (y0 + y1) / 2
    zc = K.smooth(K.DECK, yc) - 0.2
    xc = K.ring(yc)[6].x - 0.12
    for sx in (1, -1):
        out.append(box("door_card", (0.03, y1 - y0, 0.34), (sx * xc, yc, zc), m["plastic"], bevel=0.01))
        out.append(box("armrest", (0.07, min(0.5, y1 - y0 - 0.2), 0.045), (sx * (xc - 0.04), y1 - 0.45, zc - 0.03),
                       m["interior"], bevel=0.018))
    if back:
        # Rear seats under the roof, not under the rear screen (saloons and
        # coupes: the headrests poked through it).
        need = max(0.0, (K.Y_RE + 0.05) - (-1.42 + dy))
        ry = min(need, 0.28)
        if need > ry + 0.02:     # (no room under the roof: lose the rear headrests)
            for o in [o for o in back if o.name.startswith("rear_headrest")]:
                back.remove(o)
                bpy.data.objects.remove(o, do_unlink=True)
        g = kit.join("rear_seats", back)
        g.location = (0, dy + ry, K.CAV_Z0 - 0.4 * sz)
        g.scale = (kx, 1.0, sz)
        out.append(g)
    if dash:
        g = kit.join("dash", dash)
        dz = K.smooth(K.DECK, K.Y_COWL) - 0.975
        g.location = (0, dy, dz)
        g.scale = (kx, 1.0, 1.0)
        out.append(g)


def build_traffic(name):
    d = use(name)
    kind = d["_kind"]
    kit.reset()
    m = K.mats()
    m["trim"] = m["gloss_black"]
    m["glass"] = kit.mat("glass", (0.05, 0.06, 0.08), 0.08)
    for k, rgb, em in (("livery_blue", (0.04, 0.16, 0.62), None), ("livery_yellow", (0.98, 0.85, 0.05), None),
                       ("livery_green", (0.1, 0.55, 0.22), None), ("beacon_blue", (0.1, 0.3, 1.0), (0.1, 0.3, 1.0)),
                       ("sign", (1.0, 0.86, 0.35), (1.0, 0.8, 0.3))):
        m[k] = kit.mat(k, rgb, 0.35, 0.0, emit=em)
    out = []
    clean = K.build_shell(m["paint"])
    clean.hide_render = True
    body = K.decimated(clean, {"van": 0.07, "suv": 0.11}.get(kind, 0.085))   # (0.06 dented the nose round the lamp pockets)
    W2, AX, WR, ARCH, RIDE, YF, YR = K.W2, K.AX, K.WR, K.ARCH, K.RIDE, K.YF, K.YR
    belt, nose, boot = d["_belt"], d["_nose"], d["_boot"]
    # Arches + dark wells.
    for ay in AX:
        for sx in (1, -1):
            c = cyl("arch", ARCH, 0.62, (0, 0, 0), None, 20)
            c.rotation_euler = (0, math.pi / 2, 0)
            c.location = ((W2 - 0.4) if sx > 0 else (-W2 - 0.22), ay, WR)
            K.cut(body, c, m["liner"])
            well = cyl("well", ARCH - 0.004, 0.3, (0, 0, 0), m["liner"], 12, cap=False)
            well.rotation_euler = (0, math.pi / 2, 0)
            well.location = (sx * (W2 - 0.34) - (0.0 if sx > 0 else 0.3), ay, WR)
            out.append(well)
    gap = m["liner"]
    # Doors (vans: a cab door and a sliding-door line), bonnet, boot/tailgate.
    ra = ARCH + 0.035
    a0 = math.asin(max(-1.0, min(1.0, (K.SILL_Z - WR) / ra)))
    arc_f = [(AX[0] - math.cos(a) * ra, WR + math.sin(a) * ra) for a in (a0 + (1.2 - a0) * i / 7 for i in range(8))]
    arc_r = [(AX[1] + math.cos(a) * ra, WR + math.sin(a) * ra) for a in (a0 + (1.15 - a0) * i / 7 for i in range(8))]
    top = lambda y: K.smooth(K.DECK, y) - 0.012
    if kind == "van":
        yb = AX[0] - ARCH - 0.75
        lines = [arc_f + [(arc_f[-1][0] - 0.02, top(arc_f[-1][0]))], [(yb, K.SILL_Z), (yb, top(yb) + 0.5)],
                 [(arc_f[0][0], K.SILL_Z), (AX[1] + ARCH + 0.1, K.SILL_Z)], [(yb - 1.25, K.SILL_Z + 0.02), (yb - 1.25, top(yb) + 0.5)]]
    else:
        ymid = (arc_f[0][0] + arc_r[0][0]) / 2 + 0.08
        lines = [arc_f + [(arc_f[-1][0] - 0.02, top(arc_f[-1][0]))], [(ymid, K.SILL_Z), (ymid, top(ymid))],
                 [(arc_f[0][0], K.SILL_Z), (arc_r[0][0], K.SILL_Z)], arc_r + [(arc_r[-1][0] - 0.01, top(arc_r[-1][0]))]]
    gap_surface = K.Surface([body])
    gs = K.Surface([clean])
    width = 0.0105 if kind == "van" else 0.006
    for ln in lines:
        gap_decal(gap_surface, m, out, ln, "side", w=width, side=0, lift=0.006)
    if kind == "van":
        # Separate pull handles either side of the sliding door's leading
        # shut line. The rear door track follows the curved body surface.
        for door_y in (yb + 0.17, yb - 0.19):
            for sd in (1, -1):
                hit = gap_surface.cast(*K.ray("side", door_y, belt - 0.045, sd))
                if hit:
                    at, normal = hit[:2]
                    out.append(box("handle_seal", (0.015, 0.214, 0.063), at + normal * 0.005, m["liner"], bevel=0.006))
                    out.append(box("pull_handle", (0.035, 0.175, 0.031), at + normal * 0.018, m["plastic"], bevel=0.009))
        track_y0, track_y1 = yb - 1.30, YR + 0.31
        track_z = belt + 0.075
        gap_decal(gap_surface, m, out, [(track_y0, track_z), (track_y1, track_z)],
                  "side", w=0.021, side=0, lift=0.006)
    for sx in (1, -1):
        bon = [(sx * (K.half_width(y) - 0.13), y) for y in (K.Y_COWL + 0.04, (K.Y_COWL + YF) / 2, YF - 0.2)]
        if YF - 0.2 > K.Y_COWL + 0.1:
            gap_decal(gap_surface, m, out, bon, "top", lift=0.004)
    if kind == "saloon":
        xi = W2 * 0.5 - 0.018          # (lines up with the boot's rear shut line)
        for sx in (1, -1):
            gap_decal(gs, m, out, [(sx * xi, K.Y_TG + 0.03), (sx * xi, YR + 0.1)], "top")
        gap_decal(gs, m, out, [(-xi, K.Y_TG + 0.03), (xi, K.Y_TG + 0.03)], "top")
    surf = K.Surface([body])
    # Nose: lamps right under the bonnet edge, grille, lower intake, plate.
    ztop = 0.0
    for z in [0.4 + i * 0.01 for i in range(110)]:
        h = surf.cast(*K.ray("front", W2 * 0.55, z))
        if h and h[1].y > 0.35 and h[0].y > YF - 0.45:
            ztop = z
    zl = ztop - 0.015
    lh = 0.09 if kind != "van" else 0.13
    K.head_lamp(surf, body, m, out, [(W2 * 0.38, zl - lh), (W2 * 0.89, zl - lh * 0.75), (W2 * 0.91, zl), (W2 * 0.41, zl - 0.012)])
    surf = K.Surface([body])
    gh = 0.13 if kind != "van" else 0.2
    K.opening(surf, body, m, out, [(-W2 * 0.31, zl - gh), (W2 * 0.31, zl - gh), (W2 * 0.35, zl - 0.015), (-W2 * 0.35, zl - 0.015)],
              0.045, "slats", frame="chrome" if kind in ("saloon", "suv") else "trim", res=(14, 4))
    surf = K.Surface([body])
    K.opening(surf, body, m, out, [(-W2 * 0.5, RIDE + 0.09), (W2 * 0.5, RIDE + 0.09), (W2 * 0.56, RIDE + 0.25),
                                   (-W2 * 0.56, RIDE + 0.25)], 0.05, "slats", res=(14, 3))
    surf = K.Surface([body])
    h = surf.cast(*K.ray("front", 0.0, RIDE + 0.34))
    if h:
        nf = V((0, 1, 0.1)).normalized()
        K.number_plate(out, m, h[0] + nf * 0.012, nf, rear=False, text=REGS.get(name, "WS24 TRF"))
    # Rear (tools/blender/ws_rear.py, sealed variant) and front details.
    R.rear_end(body, clean, m, out, kind, set(), belt=belt, rear=boot, reg=REGS.get(name, "WS24 TRF"), sealed=True,
               pipes=[(W2 * 0.62, RIDE + 0.12, 0.03, "round")] if kind != "van" else [(W2 * 0.7, RIDE + 0.1, 0.032, "round")])
    R.front_end(body, clean, m, out, kind, zl=zl, lamp_poly=[(W2 * 0.38, zl - lh), (W2 * 0.89, zl - lh * 0.75), (W2 * 0.91, zl),
                                                            (W2 * 0.41, zl - 0.012)])
    # Glass: a real cabin (2026-11-26) – the shell hollowed out, every window
    # cut through with clear glass set in a rubber seal, the Kestrel's
    # interior fitted inside (as the cars you can buy: ws_cars). Van rear
    # doors stay sealed (the cargo hold behind the cab's bulkhead).
    K.cut(body, K.cavity_solid(), m["interior"])
    rs = K.Surface([body])

    def glass_sheet(_surf, m_, out_, view, poly, sd=1):
        axis, d0, d1 = {"side": ("x", 0.3 if sd > 0 else -2.0, 2.0 if sd > 0 else -0.3),
                        "top": ("z", 0.5, K.ROOF + 0.3), "rear": ("y", YR - 0.5, YR + 0.7)}[view]
        if kind == "van" and view == "rear":
            K.glaze(body, clean, m_, out_, poly, axis, d0, d1, inset=-0.014, cut_body=False, glass=m_["glass"])
        else:
            K.glaze(body, clean, m_, out_, poly, axis, d0, d1)
        R.outline_trim(gs, m_, out_, poly, view, sd, mat="trim", r=0.0065, lift=0.01, step=0.08)

    zb = lambda y: K.smooth(K.DECK, y) + 0.02
    if kind == "van":
        yf0, yr0 = K.Y_COWL - 0.12, K.Y_WS - 0.1
        for sd in (1, -1):
            glass_sheet(rs, m, out, "side", [(yr0 - 0.45, zb(yr0)), (yf0, zb(yf0)), (K.Y_WS + 0.05, K.ROOF - 0.12),
                                             (yr0 - 0.45, K.ROOF - 0.12)], sd)
    else:
        yf0 = K.Y_COWL - 0.1
        yr0 = K.Y_TG + (0.2 if kind != "saloon" else 0.12) if kind != "saloon" else K.Y_RE - 0.15
        zr = K.ROOF - 0.1
        for sd in (1, -1):
            glass_sheet(rs, m, out, "side", [(yr0, zb(yr0)), (yf0, zb(yf0)), (K.Y_WS + 0.03, zr), (yr0 + (0.25 if kind == "saloon" else 0.05), zr)], sd)
    # Windscreen (from above), rear screen.
    rw = K.ring(K.Y_COWL - 0.05)[2].x
    glass_sheet(rs, m, out, "top", [(-rw - 0.06, K.Y_COWL - 0.05), (rw + 0.06, K.Y_COWL - 0.05),
                                    (K.ring(K.Y_WS + 0.04)[2].x - 0.02, K.Y_WS + 0.04), (-K.ring(K.Y_WS + 0.04)[2].x + 0.02, K.Y_WS + 0.04)])
    if kind == "saloon":
        rx = K.ring(K.Y_RE - 0.05)[2].x - 0.02
        glass_sheet(rs, m, out, "top", [(-rx, K.Y_TG + 0.08), (rx, K.Y_TG + 0.08), (rx, K.Y_RE - 0.05), (-rx, K.Y_RE - 0.05)])
    else:
        zt = K.ROOF - 0.08
        z0 = zb(K.Y_TG) + 0.03 if kind != "van" else RIDE + 1.0
        glass_sheet(rs, m, out, "rear", [(-W2 * 0.62, z0), (W2 * 0.62, z0), (W2 * 0.55, zt), (-W2 * 0.55, zt)])
    n0 = len(out)
    cabin_interior(m, out, kind, 2 if kind == "van" else 4)
    # (Traffic: the seats and dash at half density – the same at street
    # distance; ~4k triangles a car saved.)
    for o in out[n0:]:
        if o is not None and o.name.split(".")[0] in ("seats", "rear_seats", "dash"):
            dm = o.modifiers.new("dec", "DECIMATE")
            dm.ratio = 0.45
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=dm.name)
    # B-pillar black (not vans).
    if kind != "van":
        ymid = (arc_f[0][0] + arc_r[0][0]) / 2 + 0.08
        for sd in (1, -1):
            g = K.patch(gs, "side", K.poly_fn([(ymid - 0.05, zb(ymid) - 0.02), (ymid + 0.05, zb(ymid) - 0.02),
                                               (ymid + 0.05, K.ROOF - 0.08), (ymid - 0.05, K.ROOF - 0.08)]), 2, 4, sd)
            out.append(K.sheet("b_pillar", g, 0.0175, m["trim"]))
    K.mirrors(m, out, gs)
    # Black sills, roof extras per role.
    surf = K.Surface([body])
    for sd in (1, -1):
        g = K.patch(surf, "side", K.poly_fn([(AX[1] + ARCH + 0.04, RIDE + 0.07), (AX[0] - ARCH - 0.04, RIDE + 0.07),
                                             (AX[0] - ARCH - 0.04, K.SILL_Z - 0.04), (AX[1] + ARCH + 0.04, K.SILL_Z - 0.04)]), 10, 2, sd)
        out.append(K.sheet("sill", g, 0.001, m["plastic"], thick=0.008))
    roof_at = lambda y: (rs.cast(V((0, y, 4.0)), V((0, 0, -1))) or [V((0, y, K.ROOF))])[0].z
    if name == "civ_taxi":
        y = (K.Y_WS + K.Y_RE) / 2 + 0.1
        out.append(box("taxi_sign", (0.62, 0.2, 0.14), (0, y, roof_at(y) + 0.07), m["sign"], bevel=0.03))
        out.append(box("taxi_base", (0.66, 0.24, 0.025), (0, y, roof_at(y) + 0.008), m["trim"], bevel=0.008))
    if name in ("civ_police", "civ_ambulance"):
        y = K.Y_WS - 0.25
        z = roof_at(y)
        out.append(box("lightbar", (1.1 if name == "civ_police" else 1.5, 0.26, 0.05), (0, y, z + 0.03), m["trim"], bevel=0.015))
        for i in range(6):
            out.append(box("beacon", (0.16, 0.2, 0.07), (-0.45 + i * 0.18, y, z + 0.085), m["beacon_blue"], bevel=0.02))
        cols = ["livery_blue", "livery_yellow"] if name == "civ_police" else ["livery_green", "livery_yellow"]
        livery(surf, m, out, AX[1] - ARCH + 0.05, AX[0] - 0.05, K.SILL_Z + 0.04, K.smooth(K.CREASE, 0.0) - 0.06, cols)
        if name == "civ_ambulance":
            for sx in (1, -1):
                out.append(box("rear_beacon", (0.12, 0.08, 0.12), (sx * (W2 - 0.12), YR + 0.08, K.ROOF - 0.06), m["beacon_blue"], bevel=0.02))
    if kind in ("suv", "estate"):
        K.roof_rails(m, out)
    # Shading from the full shell.
    K.shade(body, 60)
    dt = body.modifiers.new("normals", "DATA_TRANSFER")
    dt.object = clean
    dt.use_loop_data = True
    dt.data_types_loops = {"CUSTOM_NORMAL"}
    dt.loop_mapping = "POLYINTERP_NEAREST"
    dt.max_distance = 0.02
    dt.use_max_distance = True
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=dt.name)
    bpy.data.objects.remove(clean, do_unlink=True)
    ob = kit.join(name, [body] + [o for o in out if o is not None])
    ob.data.validate(clean_customdata=False)
    kit.export(name + ".glb", [ob])
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    # Mid-distance LOD (~1.2k triangles): the same car collapsed; the
    # traffic draws it between CAR_NEAR and CAR_MID.
    lo = ob.copy()
    lo.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(lo)
    dec = lo.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, 1200.0 / max(tris, 1))
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.modifier_apply(modifier=dec.name)
    # (No zero-area triangles: Blender merges them on re-import and the
    # texture pipeline's geometry check then rejects the file.)
    bm = bmesh.new()
    bm.from_mesh(lo.data)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
    bm.to_mesh(lo.data)
    bm.free()
    lo.data.validate(clean_customdata=False)
    kit.export(name + "_lod1.glb", [lo])
    print("FLEET", name, "lod1 tris", sum(len(p.vertices) - 2 for p in lo.data.polygons))
    print("FLEET", name, "tris", tris, "materials", len(ob.data.materials))
    return {"L": round(YF - YR, 3), "W": round(2 * W2, 3), "roof": K.ROOF, "wb": K.WB, "wheel_r": WR, "ride": RIDE,
            "tyre_w": K.TYRE_W, "axles": [AX[0], AX[1]], "wheel": "traffic"}


def wheel_traffic():
    """~300-triangle alloy for instanced traffic: tyre (20 sides, rounded
    shoulders), a dished five-spoke face, dark well. Radius 1, width 0.44,
    axle X, face +X (like every WorldState wheel)."""
    kit.reset()
    tyre = kit.mat("tyre", (0.03, 0.03, 0.03), 0.88)
    rim = kit.mat("rim", (0.72, 0.73, 0.75), 0.3, 1.0)
    dark = kit.mat("liner", (0.015, 0.015, 0.015), 0.9)
    prof = [(0.68, -0.4), (0.9, -0.44), (1.0, -0.3), (1.0, 0.3), (0.9, 0.44), (0.7, 0.42)]
    bm = bmesh.new()
    seg = 20
    rings = [[bm.verts.new((x * 0.5, r * math.cos(a), r * math.sin(a))) for r, x in prof]
             for a in (i * 2 * math.pi / seg for i in range(seg))]
    for i in range(seg):
        r0, r1 = rings[i], rings[(i + 1) % seg]
        for k in range(len(prof) - 1):
            bm.faces.new((r0[k], r0[k + 1], r1[k + 1], r1[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    t = kit.new_obj("tyre", bm, tyre)
    for p in t.data.polygons:
        p.use_smooth = True
    parts = [t]
    back = cyl("well", 0.68, 0.01, (0, 0, 0), dark, 16)
    back.rotation_euler = (0, math.pi / 2, 0)
    back.location = (0.0, 0, 0)
    parts.append(back)
    for k in range(5):
        a = k * 2 * math.pi / 5
        s = box("spoke", (0.05, 0.14, 0.62), (0, 0, 0), rim)
        s.rotation_euler = (-a, 0, 0)
        s.location = (0.15, math.sin(a) * 0.31, math.cos(a) * 0.31)
        parts.append(s)
    lip = cyl("lip", 0.7, 0.03, (0, 0, 0), rim, 20, r2=0.66, cap=False)   # (a capped lip hid the spokes)
    lip.rotation_euler = (0, math.pi / 2, 0)
    lip.location = (0.15, 0, 0)
    parts.append(lip)
    hub = cyl("hub", 0.16, 0.04, (0, 0, 0), rim, 10)
    hub.rotation_euler = (0, math.pi / 2, 0)
    hub.location = (0.15, 0, 0)
    parts.append(hub)
    ob = kit.join("wheel", parts)
    kit.export("wheel_traffic.glb", [ob])
    print("FLEET wheel_traffic tris", sum(len(p.vertices) - 2 for p in ob.data.polygons))


if __name__ == "__main__":
    jpath = os.path.join(OUT, "bodies.json")
    dims = json.load(open(jpath)) if os.path.exists(jpath) else {}
    for name in DESIGNS:
        if ONLY and name not in ONLY:
            continue
        dims[name] = build_traffic(name)
    if not ONLY or "wheel_traffic" in ONLY:
        wheel_traffic()
    with open(jpath, "w") as f:
        json.dump(dims, f, indent=1, sort_keys=True)
    with open(os.path.join(OUT, "body_dims.gd"), "w") as f:
        f.write("class_name BodyDims\nextends RefCounted\n## Generated by tools/blender/build_vehicles.py (Never Stop),\n"
                "## tools/blender/kestrel.py and tools/blender/ws_fleet.py (City Empire): real body dimensions (m). Do not edit.\n\n")
        f.write("const DIMS := " + json.dumps(dims, indent="\t", sort_keys=True) + "\n")
    print("FLEET DONE")
