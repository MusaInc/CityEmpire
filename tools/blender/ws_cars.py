"""WorldState owned cars: the cars you buy, built with the Kestrel's shell
generator (tools/blender/kestrel.py) at player-car detail.

Run:  blender -b --factory-startup --python tools/blender/ws_cars.py -- <out dir> [names,...]

Each car is one subdivision-cage shell (body and greenhouse as one surface,
creased character lines) shaped from real proportions of its class, with
panel gaps, lamps in recesses, openings with inserts, sealed tinted glass
on black frit and class kit (wings, diffusers, intakes, bed, roof rack...):

  marlin    sport saloon (M5 / Giulia QV class)       4.86 x 1.90 x 1.43, wb 2.88
  scout     rally hatch (GR Yaris / WRX class)        4.02 x 1.84 x 1.46, wb 2.56
  brute     muscle coupe (Mustang / Challenger)       4.95 x 1.96 x 1.36, wb 2.92
  vanta     front-engine sports coupe (F-type / 911)  4.47 x 1.90 x 1.29, wb 2.52
  goliath   lifted crew-cab pickup (Raptor class)     5.70 x 2.12 x 1.98, wb 3.50
  warden    armoured box 4x4 (G-class / Defender)     4.86 x 2.00 x 1.98, wb 2.90
  halcyon   mid-engine supercar (720S / Huracan)      4.56 x 1.98 x 1.17, wb 2.64
  stiletto  wedge hypercar                            4.78 x 2.06 x 1.10, wb 2.72
  civ_box   box truck you own (Luton body)            6.40 x 2.24 x 3.00, wb 3.60

and their wheels (wheel_<style>.glb, radius 1, width 0.44, axle X, face +X).
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
import kestrel as K  # noqa: E402
import ws_fleet as F  # noqa: E402
import ws_rear as R  # noqa: E402
import build_kit as kit  # noqa: E402
from build_kit import box, cyl  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "assets/vehicles"
ONLY = set(ARGS[1].split(",")) if len(ARGS) > 1 and ARGS[1] else set()
kit.OUT = OUT
os.makedirs(OUT, exist_ok=True)

TUNABLES = ["FENDER", "FENDER_W", "HAUNCH", "HAUNCH_W", "RAKE_ZF", "RAKE_KF", "RAKE_ZR", "RAKE_KR", "RAKE_CHIN", "TUMBLE", "END_RF",
            "END_RR", "REAR_EXP", "SEALED", "SEG_K", "CREASE_RINGS", "CAV_Z0", "CAV_ZM", "CAV_Y0", "CAV_Y1"]
DEFAULTS = {k: getattr(K, k) for k in TUNABLES}


# ------------------------------------------------------------------ designs
def design(L, W, H, wb, oh_f, wr, ride, belt, nose, kind, tyre_w, cab, rear_z=None, tail_z=None, bon_exp=1.6,
           crease=None, **kw):
    """Shell globals for kestrel.py from real numbers.
    cab(AX, YF, YR) -> (Y_COWL, Y_WS, Y_RE, Y_TG); rear_z: deck height
    behind the greenhouse (boot lid / engine cover / bed rails)."""
    oh_r = L - wb - oh_f
    YF, YR = wb / 2 + oh_f, -wb / 2 - oh_r
    AX = (wb / 2, -wb / 2)
    d = dict(DEFAULTS)
    d.update(WB=wb, WR=wr, TYRE_W=tyre_w, OH_F=oh_f, OH_R=oh_r, YF=YF, YR=YR, W2=W / 2, RIDE=ride, ROOF=H,
             ARCH=wr + 0.045, AX=AX, SILL_Z=ride + 0.17, SEALED=False, SEG_K=0.8,
             CAV_Z0=ride + 0.26, CAV_ZM=ride + 0.6, CAV_Y0=None, CAV_Y1=None)
    yc, yw, yre, ytg = cab(AX, YF, YR)
    d.update(Y_COWL=yc, Y_WS=yw, Y_RE=yre, Y_TG=ytg)
    if kind == "mid":                      # engine bay behind the seats stays solid
        d["CAV_Y0"] = yre - 0.02
    elif kind in ("pickup", "box"):          # cabin only in the cab
        d["CAV_Y0"] = ytg + 0.06
    elif kind == "van":
        d["CAV_Y0"] = AX[0] - (wr + 0.045) - 0.95
    rz = rear_z if rear_z is not None else belt + 0.02
    tz = tail_z if tail_z is not None else rz - 0.01
    cowl = belt - 0.02
    pts = [(YR, tz), (min(YR + 0.18, ytg - 0.02), rz)]
    if ytg - 0.05 > pts[-1][0]:
        pts.append((ytg, rz))
    mid = (ytg + yc) / 2
    if ytg + 0.1 < mid < yc - 0.1:
        pts.append((mid, belt))
    pts.append((yc, cowl))
    for t in (0.3, 0.6, 0.85):
        pts.append((yc + (YF - yc) * t, cowl - (cowl - nose) * t ** bon_exp))
    pts += [(YF - 0.1, nose + 0.025), (YF, nose)]
    d["DECK"] = sorted(pts)
    k = belt - ride
    d["CREASE"] = crease or [(YR, rz - 0.09), (YR + 0.25, rz - 0.05), (0.0, belt - 0.075), (AX[0] + 0.1, belt - 0.11),
                             (YF - 0.15, nose + 0.01), (YF, nose - 0.01)]
    d["SWELL"] = [(YR, ride + 0.58 * k), (0.0, ride + 0.6 * k), (YF, ride + 0.54 * k)]
    d["SCULPT"] = [(YR, ride + 0.38 * k), (0.0, ride + 0.36 * k), (YF, ride + 0.36 * k)]
    d["BOTTOM"] = [(YR, ride + 0.17), (YR + 0.3, ride + 0.05), (AX[1] - 0.45, ride + 0.012), (AX[0] + 0.45, ride + 0.012),
                   (YF - 0.3, ride + 0.05), (YF, ride + 0.1)]
    d.update(kw)
    d["_kind"], d["_belt"], d["_nose"], d["_rear"] = kind, belt, nose, rz
    return d


CARS = {
    "marlin": dict(label="MARLIN GT", reg="MA21 RLN",
        d=design(4.86, 1.9, 1.43, 2.88, 0.88, 0.345, 0.12, 0.99, 0.76, "saloon", 0.255,
                 lambda AX, YF, YR: (AX[0] - 0.42, AX[0] - 1.28, AX[1] + 0.58, AX[1] - 0.2), rear_z=1.01,
                 HAUNCH=(0.03, 0.04), TUMBLE=0.14, REAR_EXP=1.2, END_RF=0.36, END_RR=0.32),
        wheel="multi", paint="1d3a6b", feats=["lip_spoiler", "quad_pipes", "skirts", "splitter", "vents_front", "light_bar"],
        grille="saloon", lamps="slim", doors=4),
    "scout": dict(label="SCOUT RS", reg="SC07 UTR",
        d=design(4.02, 1.84, 1.46, 2.56, 0.84, 0.33, 0.16, 0.98, 0.78, "hatch", 0.235,
                 lambda AX, YF, YR: (AX[0] - 0.38, AX[0] - 1.2, AX[1] + 0.05, YR + 0.2),
                 HAUNCH=(0.05, 0.06), HAUNCH_W=0.5, TUMBLE=0.13, REAR_EXP=1.6, END_RF=0.34, END_RR=0.28),
        wheel="rally", paint="d8661a", paint2="f2f2f2", feats=["roof_spoiler", "light_pod", "mudflaps",
                                                                "skirts", "splitter", "twin_pipe", "side_stripe", "flares"],
        grille="mesh", lamps="slim", doors=4),
    "brute": dict(label="BRUTE 8", reg="BR08 UTE",
        d=design(4.95, 1.96, 1.36, 2.92, 0.98, 0.36, 0.13, 0.99, 0.86, "muscle", 0.285,
                 lambda AX, YF, YR: (AX[0] - 0.9, AX[0] - 1.66, AX[1] + 0.42, AX[1] - 0.22), rear_z=1.0, bon_exp=2.4,
                 HAUNCH=(0.02, 0.05), TUMBLE=0.13, REAR_EXP=1.35, END_RF=0.2, END_RR=0.18, RAKE_ZF=0.95, RAKE_KF=0.2,
                 RAKE_ZR=0.85, RAKE_KR=0.05),
        wheel="dish", paint="8a1410", paint2="f0efe8", feats=["bonnet_bulge", "stripes", "duck_tail", "quad_pipes", "light_bar",
                                                               "skirts", "splitter"],
        grille="wide", lamps="round", doors=2),
    "vanta": dict(label="VANTA S", reg="VA12 NTA",
        d=design(4.47, 1.9, 1.29, 2.52, 0.92, 0.345, 0.11, 0.9, 0.64, "coupe", 0.275,
                 lambda AX, YF, YR: (AX[0] - 0.72, AX[0] - 1.62, AX[1] + 0.2, YR + 0.28), rear_z=0.96, bon_exp=1.3,
                 HAUNCH=(0.03, 0.075), HAUNCH_W=0.62, FENDER=(0.05, 0.05), TUMBLE=0.18, REAR_EXP=1.05, END_RF=0.42, END_RR=0.3),
        wheel="y5", paint="16181c", feats=["duck_tail", "quad_pipes", "skirts", "splitter", "diffuser", "gills",
                                            "light_bar"],
        grille="intake", lamps="slim", doors=2),
    "halcyon": dict(label="HALCYON R", reg="HA19 LCY",
        d=design(4.56, 1.98, 1.15, 2.64, 1.0, 0.35, 0.1, 0.84, 0.44, "mid", 0.3,
                 lambda AX, YF, YR: (AX[0] - 0.12, AX[0] - 1.1, AX[0] - 1.72, YR + 0.32), rear_z=0.9, tail_z=0.86,
                 bon_exp=1.2, crease=None, HAUNCH=(0.035, 0.09), HAUNCH_W=0.62, TUMBLE=0.2, REAR_EXP=0.95,
                 FENDER=(0.1, 0.07), END_RF=0.5, END_RR=0.32, RAKE_ZF=0.36, RAKE_KF=0.1, RAKE_CHIN=0.14, RAKE_ZR=0.7),
        dec=0.34, wheel="center", paint="e9e9ec", feats=["side_intakes", "rear_wing", "diffuser", "louvres", "splitter",
                                                "skirts", "centre_pipes", "light_bar"],
        grille="supercar", lamps="blade", doors=1),
    "stiletto": dict(label="STILETTO", reg="ST11 LTO",
        d=design(4.78, 2.06, 1.1, 2.72, 1.06, 0.36, 0.09, 0.8, 0.4, "mid", 0.32,
                 lambda AX, YF, YR: (AX[0] + 0.05, AX[0] - 1.02, AX[0] - 1.58, YR + 0.26), rear_z=0.9, tail_z=0.88,
                 bon_exp=1.05, HAUNCH=(0.04, 0.1), HAUNCH_W=0.6, TUMBLE=0.22, REAR_EXP=0.9, END_RF=0.26, END_RR=0.2,
                 FENDER=(0.12, 0.06), RAKE_ZF=0.34, RAKE_KF=0.12, RAKE_CHIN=0.13, RAKE_ZR=0.66, RAKE_KR=0.04),
        dec=0.34, wheel="center", paint="d8b020", feats=["side_intakes", "big_wing", "diffuser", "louvres", "splitter", "skirts",
                                                "quad_pipes_high", "light_bar", "fins"],
        grille="supercar", lamps="blade", doors=1),
    "goliath": dict(label="GOLIATH", reg="GO22 LTH",
        d=design(5.7, 2.12, 1.98, 3.5, 0.98, 0.43, 0.34, 1.42, 1.34, "pickup", 0.315,
                 lambda AX, YF, YR: (AX[0] - 0.45, AX[0] - 1.12, AX[0] - 2.42, AX[0] - 2.47), rear_z=1.4, tail_z=1.38,
                 bon_exp=2.0, HAUNCH=(0.02, 0.02), TUMBLE=0.07, REAR_EXP=9.0, END_RF=0.2, END_RR=0.1, RAKE_ZF=1.5,
                 RAKE_KF=0.15, RAKE_ZR=1.6, RAKE_KR=0.0, RAKE_CHIN=0.6),
        dec=0.3, wheel="offroad", paint="3a4a3a", feats=["bed", "light_bar_roof", "bull_bar", "flares", "steps", "tow"],
        grille="truck", lamps="square", doors=4),
    "warden": dict(label="WARDEN", reg="WA05 RDN",
        d=design(4.86, 2.0, 1.98, 2.9, 0.82, 0.42, 0.32, 1.36, 1.28, "box4x4", 0.31,
                 lambda AX, YF, YR: (AX[0] - 0.32, AX[0] - 0.74, YR + 0.06, YR + 0.03), rear_z=1.36,
                 bon_exp=3.0, HAUNCH=(0.0, 0.0), TUMBLE=0.035, REAR_EXP=12.0, END_RF=0.1, END_RR=0.08, RAKE_ZF=1.6,
                 RAKE_KF=0.05, RAKE_ZR=1.6, RAKE_KR=0.0, RAKE_CHIN=0.55, CREASE_RINGS={5: 1.0, 7: 0.9}),
        dec=0.3, wheel="offroad", paint="2b2f33", feats=["roof_rack", "bull_bar", "spare", "flares", "steps", "armour"],
        grille="slats", lamps="round", doors=4),
    # Police: Never Stop's pursuit units and City Empire's police, on the
    # same shell as the cars you own (catalogue livery: paint + paint2).
    "police_patrol": dict(label="POLICE", reg="PL24 PTR",
        d=design(4.82, 1.88, 1.44, 2.9, 0.92, 0.355, 0.14, 0.99, 0.77, "saloon", 0.255,
                 lambda AX, YF, YR: (AX[0] - 0.42, AX[0] - 1.28, AX[1] + 0.58, AX[1] - 0.2), rear_z=1.01,
                 HAUNCH=(0.02, 0.03), TUMBLE=0.13, REAR_EXP=1.25, END_RF=0.32, END_RR=0.3),
        wheel="steel", paint="10141f", paint2="eceef0",
        feats=["lightbar", "push_bar", "livery_doors", "police_text", "spot_lamp", "grille_strobes"],
        grille="saloon", lamps="slim", doors=4),
    "police_interceptor": dict(label="POLICE", reg="PL24 INT",
        d=design(4.48, 1.92, 1.27, 2.62, 0.9, 0.355, 0.12, 0.9, 0.66, "coupe", 0.29,
                 lambda AX, YF, YR: (AX[0] - 0.7, AX[0] - 1.6, AX[1] + 0.2, YR + 0.28), rear_z=0.97, bon_exp=1.3,
                 HAUNCH=(0.03, 0.07), HAUNCH_W=0.6, FENDER=(0.04, 0.04), TUMBLE=0.17, REAR_EXP=1.05, END_RF=0.4, END_RR=0.3),
        wheel="y5", paint="0b0c0e", paint2="c4f226",
        feats=["lightbar_low", "battenburg", "police_text", "splitter", "skirts", "quad_pipes", "diffuser", "grille_strobes"],
        grille="intake", lamps="slim", doors=2),
    "police_heavy": dict(label="POLICE", reg="PL24 HVY",
        d=design(4.98, 2.08, 1.98, 2.96, 0.86, 0.43, 0.32, 1.36, 1.26, "box4x4", 0.32,
                 lambda AX, YF, YR: (AX[0] - 0.32, AX[0] - 0.76, YR + 0.06, YR + 0.03), rear_z=1.36,
                 bon_exp=3.0, HAUNCH=(0.0, 0.0), TUMBLE=0.04, REAR_EXP=12.0, END_RF=0.12, END_RR=0.09, RAKE_ZF=1.6,
                 RAKE_KF=0.05, RAKE_ZR=1.6, RAKE_KR=0.0, RAKE_CHIN=0.55, CREASE_RINGS={5: 1.0, 7: 0.9}),
        dec=0.3, wheel="offroad", paint="15181d", paint2="eceef0",
        feats=["lightbar", "bull_bar", "livery_doors", "police_text", "flares", "steps", "spot_lamp", "grille_strobes"],
        grille="slats", lamps="square", doors=4),
    "ws_van": dict(label="CARGO", reg="VN64 WSE",
        d=design(5.0, 2.0, 1.98, 2.93, 0.95, 0.34, 0.18, 1.12, 0.98, "van", 0.235,
                 lambda AX, YF, YR: (AX[0] + 0.32, AX[0] - 0.42, YR + 0.06, YR + 0.02), rear_z=1.12, bon_exp=1.4,
                 HAUNCH=(0.012, 0.012), TUMBLE=0.05, REAR_EXP=1.0, END_RF=0.32, END_RR=0.12),
        wheel="steel", paint="e9e6df", feats=["sliding_door", "steps_rear", "roof_bars", "skirts_plastic"],
        grille="mesh", lamps="square", doors=2),
    "civ_bus": dict(label="CITYLINK", reg="BU64 CTY",
        d=design(10.4, 2.5, 3.0, 5.6, 2.3, 0.5, 0.28, 1.2, 1.15, "bus", 0.32,
                 lambda AX, YF, YR: (YF - 0.16, YF - 0.45, YR + 0.1, YR + 0.06), rear_z=1.2, tail_z=1.2,
                 bon_exp=1.0, HAUNCH=(0.0, 0.0), TUMBLE=0.03, REAR_EXP=14.0, END_RF=0.22, END_RR=0.16, RAKE_ZF=2.5,
                 RAKE_KF=0.0, RAKE_ZR=2.5, RAKE_KR=0.0, RAKE_CHIN=0.5, CREASE_RINGS={5: 1.0, 7: 0.9}),
        wheel="steel", paint="b0201a", feats=["bus_kit"], grille="bus", lamps="square", doors=0, dec=0.3),
    "courier_van": dict(label="COURIER", reg="VN62 DLV",
        d=design(5.0, 2.0, 1.98, 2.93, 0.95, 0.34, 0.18, 1.12, 0.98, "van", 0.225,
                 lambda AX, YF, YR: (AX[0] - 0.35, AX[0] - 1.02, YR + 0.18, YR + 0.1),
                 rear_z=1.22, tail_z=1.22, TUMBLE=0.075, END_RF=0.17, END_RR=0.03),
        dec=0.27, wheel="steel", paint="e9e6df", feats=["sliding_door", "skirt_clad"],
        grille="slats", lamps="square", doors=2),
    "civ_box": dict(label="HAULER", reg="BX70 WSE",
        d=design(6.4, 2.24, 2.3, 3.6, 1.0, 0.44, 0.3, 1.32, 1.2, "box", 0.28,
                 lambda AX, YF, YR: (AX[0] + 0.25, AX[0] - 0.38, AX[0] - 0.95, AX[0] - 1.0), rear_z=1.0, tail_z=0.98,
                 bon_exp=1.4, HAUNCH=(0.0, 0.0), TUMBLE=0.05, REAR_EXP=9.0, END_RF=0.24, END_RR=0.06, RAKE_ZF=1.6,
                 RAKE_KF=0.1, RAKE_ZR=2.0, RAKE_KR=0.0, RAKE_CHIN=0.55),
        wheel="steel", paint="e9e6df", feats=["cargo_box", "steps"], grille="truck", lamps="square", doors=2, box_h=2.62, dec=0.3),
    "mammoth": dict(label="MAMMOTH", reg="MM07 HVY",
        d=design(6.6, 2.34, 2.42, 3.7, 1.05, 0.55, 0.48, 1.5, 1.4, "box", 0.36,
                 lambda AX, YF, YR: (AX[0] + 0.25, AX[0] - 0.38, AX[0] - 0.98, AX[0] - 1.03), rear_z=1.12, tail_z=1.1,
                 bon_exp=1.4, HAUNCH=(0.0, 0.0), TUMBLE=0.05, REAR_EXP=9.0, END_RF=0.22, END_RR=0.06, RAKE_ZF=1.8,
                 RAKE_KF=0.08, RAKE_ZR=2.2, RAKE_KR=0.0, RAKE_CHIN=0.7),
        wheel="steel", paint="c8a020", feats=["cargo_box", "steps", "bull_bar", "light_bar_roof"], grille="truck",
        lamps="square", doors=2, box_h=2.88, cargo="tipper", dec=0.3),
}

# Halcyon gets a sharper waist line rising over the rear hips.
_h = CARS["halcyon"]["d"]
_h["CREASE"] = [(_h["YR"], 0.8), (_h["AX"][1], 0.84), (-0.3, 0.76), (_h["AX"][0], 0.72), (_h["YF"] - 0.25, 0.52), (_h["YF"], 0.42)]
_s = CARS["stiletto"]["d"]
_s["CREASE"] = [(_s["YR"], 0.78), (_s["AX"][1], 0.82), (-0.4, 0.74), (_s["AX"][0], 0.7), (_s["YF"] - 0.25, 0.47), (_s["YF"], 0.38)]


def use(d):
    for k, v in d.items():
        if not k.startswith("_"):
            setattr(K, k, v)


# ------------------------------------------------------------------ parts
def mats():
    m = K.mats()
    K.premium(m)
    m["trim"] = m["gloss_black"]
    m["glass"] = kit.mat("glass", (0.04, 0.05, 0.065), 0.06)
    m["paint2"] = kit.mat("paint2", (0.9, 0.9, 0.9), 0.3)
    m["carbon"] = kit.mat("carbon", (0.05, 0.05, 0.056), 0.28, 0.35)
    m["cladding"] = kit.mat("cladding", (0.075, 0.075, 0.08), 0.85)
    m["bed"] = kit.mat("bed", (0.05, 0.05, 0.05), 0.95)
    m["beacon_blue"] = kit.mat("beacon_blue", (0.1, 0.3, 1.0), 0.3, 0.0, emit=(0.1, 0.3, 1.0))
    m["amber"] = m["amber"]
    return m


def loft(name, sections, material, cap=True, smooth=True):
    """Quad loft through closed point loops of equal length."""
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in s] for s in sections]
    n = len(rings[0])
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(n):
            bm.faces.new((r0[i], r0[(i + 1) % n], r1[(i + 1) % n], r1[i]))
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = kit.new_obj(name, bm, material)
    for p in ob.data.polygons:
        p.use_smooth = smooth
    return ob


def airfoil(chord, thick, n=10):
    """Closed airfoil outline (y, z) in the plane, leading edge at +y."""
    up, lo = [], []
    for i in range(n + 1):
        t = i / n
        x = (1 - math.cos(t * math.pi)) / 2          # 0 lead .. 1 trail
        yt = 5 * thick * (0.2969 * math.sqrt(x) - 0.126 * x - 0.3516 * x * x + 0.2843 * x ** 3 - 0.1036 * x ** 4)
        camber = 0.04 * thick / 0.12 * (1 - (2 * x - 1) ** 2)
        up.append((-x * chord, (camber + yt) * chord))
        lo.append((-x * chord, (camber - yt) * chord))
    return up + list(reversed(lo[1:-1]))


def wing(m, out, y, z, span, chord, thick=0.1, upright_h=0.3, angle=8, plates=True, mat="carbon", uprights=True,
         base_z=None):
    """Rear wing: airfoil blade, end plates, swan-neck or pylon uprights."""
    pf = airfoil(chord, thick)
    a = math.radians(angle)
    rot = lambda q: (q[0] * math.cos(a) - q[1] * math.sin(a), q[0] * math.sin(a) + q[1] * math.cos(a))
    pf = [rot(q) for q in pf]
    secs = []
    for x in (-span / 2, -span / 2 + 0.02, 0.0, span / 2 - 0.02, span / 2):
        lift = 0.012 * (1 - (2 * x / span) ** 2)     # a slight arch
        secs.append([V((x, y + q[0] + chord * 0.5, z + q[1] + lift)) for q in pf])
    out.append(loft("wing", secs, m[mat]))
    if plates:
        for sx in (1, -1):
            out.append(box("endplate", (0.008, chord * 1.05, 0.075), (sx * (span / 2 + 0.004), y - 0.01, z - 0.012),
                           m[mat], bevel=0.004))
    if uprights:
        bz = base_z if base_z is not None else z - upright_h
        for sx in (1, -1):
            x = sx * span * 0.32
            # Pylon: a tapered blade from the deck up to the underside of the
            # wing (the swan necks were thin rods floating at the tail).
            yb0, yb1 = y - chord * 0.35, y + chord * 0.15
            sec = []
            for zz, k in ((bz - 0.03, 1.0), (z - 0.032, 0.62)):
                yc = (yb0 + yb1) / 2 - (1 - k) * chord * 0.2
                hl = (yb1 - yb0) / 2 * k
                sec.append([V((x + dx, yc + dy, zz)) for dx, dy in ((0.009, hl), (0.009, -hl), (-0.009, -hl), (-0.009, hl))])
            out.append(loft("pylon", sec, m[mat], smooth=False))


def side_window_poly(kind, belt_y):
    pass


def tube(name, pts, r, material, segs=8):
    return K.tube_path(name, [V(p) for p in pts], r, material, segs)


def pipe(m, out, x, y, z, r=0.045, length=0.12, shape="round"):
    c = cyl("pipe", r, length, (0, 0, 0), m["chrome"], 20, cap=False)
    c.rotation_euler = (math.pi / 2, 0, 0)
    c.location = (x, y + length / 2, z)
    out.append(c)
    inner = cyl("pipe_in", r * 0.82, 0.01, (0, 0, 0), m["liner"], 20)
    inner.rotation_euler = (math.pi / 2, 0, 0)
    inner.location = (x, y + 0.03, z)
    out.append(inner)


def side_opening(surf, body, m, out, poly, depth=0.08, slats=3):
    """Intake in the body side (both sides): pocket, dark back, slats."""
    for sd in (1, -1):
        g = K.patch(surf, "side", K.poly_fn(poly), 10, 5, sd)
        if sum(1 for row in g for c in row if c) < 40:
            print("SIDE OPENING MISSED", poly)
            continue
        K.cut(body, K.recess_cutter("intake", g, depth), m["liner"])
        # (the dark back well in front of the pocket's floor: a FAST-solver
        # cut leaves that floor in body paint - a pale slab in the intake)
        out.append(K.sheet("intake_back", g, -depth * 0.6, m["liner"]))
        navg = sum((c[1] for row in g for c in row if c), V()).normalized()
        for k in range(slats):
            j = int(round((k + 0.5) / slats * 5))
            pts = [c[0] - navg * depth * 0.3 for c in g[j][1:-1] if c]
            if len(pts) > 2:
                out.append(K.tube_path("slat", pts, 0.008, m["trim"], 6))


def bulge(surf, m, out, poly, height, view="top", res=(10, 8)):
    """A raised paint panel (bonnet power bulge) that blends into the body."""
    g = K.patch(surf, view, K.poly_fn(poly), *res)
    nv, nu = len(g) - 1, len(g[0]) - 1
    for j in range(nv + 1):
        for i in range(nu + 1):
            c = g[j][i]
            if c is None:
                continue
            s, t = i / nu, j / nv
            w = math.sin(math.pi * s) ** 0.6 * math.sin(math.pi * min(1.0, t * 1.15)) ** 0.5
            g[j][i] = (c[0] + c[1] * (height * w - 0.004), c[1])
    out.append(K.sheet("bulge", g, 0.0, m["paint"]))


def stripe(surf, m, out, x0, x1, y0, y1, mat="paint2"):
    g = K.patch(surf, "top", K.poly_fn([(x0, y0), (x1, y0), (x1, y1), (x0, y1)]), 2, 30)
    out.append(K.sheet("stripe", g, 0.0022, m[mat]))


def top_lamps(surf, m, out):
    """Supercar headlamps laid into the bonnet's front slope (seen from
    above): a dark glossy housing, an LED blade along its outer edge turning
    down the corner, two small projector lenses; no cut (the leading edge
    is too thin for a pocket)."""
    YF, W2 = K.YF, K.W2
    for sx in (1, -1):
        poly = [(sx * W2 * 0.48, YF - 0.06), (sx * W2 * 0.86, YF - 0.2), (sx * W2 * 0.8, YF - 0.36), (sx * W2 * 0.5, YF - 0.2)]
        if sx < 0:
            poly = [poly[1], poly[0], poly[3], poly[2]]
        g = K.patch(surf, "top", K.poly_fn(poly), 10, 5)
        if sum(1 for row in g for c in row if c) < 30:
            print("LAMP MISSED top")
            continue
        out.append(K.sheet("lamp_housing", g, 0.004, m["housing"]))
        out.append(K.sheet("lamp_lens", g, 0.009, m["lens"]))
        edge = [c[0] + c[1] * 0.007 for c in (g[1] if sx > 0 else g[1]) if c]
        if len(edge) > 2:
            out.append(K.tube_path("drl", edge, 0.007, m["head"], 6))
        for (i, j) in ((3, 3), (6, 3)):
            c = g[j][i]
            if c:
                centre, nrm = c[:2]
                out.append(K.disc_on("projector_bezel", centre + nrm * 0.006, nrm, 0.031, 0.002, m["trim"], 16))
                out.append(K.disc_on("projector", centre + nrm * 0.008, nrm, 0.019, 0.004, m["head"], 16))


def bus_interior(m, out):
    """Rows of double seats each side of the aisle (moquette, grab handles),
    the driver's seat and wheel up front, a pale ceiling under the roof."""
    I, P, C = m["interior"], m["plastic"], m["chrome"]
    zf = K.CAV_Z0
    y = K.Y_COWL - 1.6
    while y > K.YR + 0.9:
        for sx in (1, -1):
            x = sx * (K.W2 - 0.52)
            out.append(box("bus_seat", (0.86, 0.42, 0.1), (x, y, zf + 0.42), I, bevel=0.03))
            bk = box("bus_back", (0.86, 0.08, 0.5), (0, 0, 0), I, bevel=0.03)
            bk.rotation_euler = (math.radians(-10), 0, 0)
            bk.location = (x, y - 0.22, zf + 0.7)
            out.append(bk)
            out.append(K.tube_path("grab", [V((x - sx * 0.43, y - 0.26, zf + 0.9)), V((x - sx * 0.43, y - 0.26, zf + 1.0))],
                                   0.012, C, 6))
        y -= 0.82
    out.append(box("drv_seat", (0.5, 0.48, 0.12), (K.W2 - 0.55, K.Y_COWL - 0.95, zf + 0.45), I, bevel=0.04))
    bk = box("drv_back", (0.5, 0.1, 0.62), (0, 0, 0), I, bevel=0.04)
    bk.rotation_euler = (math.radians(-12), 0, 0)
    bk.location = (K.W2 - 0.55, K.Y_COWL - 1.2, zf + 0.8)
    out.append(bk)
    out.append(box("dash", (2 * K.W2 - 0.3, 0.4, 0.3), (0, K.Y_COWL - 0.3, K.smooth(K.DECK, K.Y_COWL) - 0.2), P, bevel=0.05))
    c = V((K.W2 - 0.55, K.Y_COWL - 0.6, K.smooth(K.DECK, K.Y_COWL) + 0.0))
    out.append(K.tube_path("bus_wheel", [c + V((0.25 * math.cos(a), 0.06 * math.sin(a), 0.22 * math.sin(a)))
                                         for a in (i * 2 * math.pi / 24 for i in range(25))], 0.02, P, 6))
    out.append(box("ceiling", (2 * K.W2 - 0.3, K.Y_COWL - K.YR - 0.8, 0.02), (0, (K.Y_COWL + K.YR) / 2, K.ROOF - 0.08),
                   kit.mat("headliner", (0.6, 0.6, 0.58), 0.9)))


def bus_kit(spec, m, out, gs, poly, zb, zr):
    """Single-deck bus: window pillars along both sides, the glazed
    two-leaf entrance door on the kerb side (left), a destination display
    over the windscreen, a roof air-con pod."""
    W2, RIDE, YF, YR = K.W2, K.RIDE, K.YF, K.YR
    y_front, y_back = poly[1][0], poly[0][0]
    n = int((y_front - y_back) / 1.15)
    for i in range(1, n):
        y = y_back + i * (y_front - y_back) / n
        for sd in (1, -1):
            g = K.patch(gs, "side", K.poly_fn([(y - 0.05, zb(y) - 0.03), (y + 0.05, zb(y) - 0.03), (y + 0.05, zr + 0.03),
                                               (y - 0.05, zr + 0.03)]), 2, 6, sd)
            out.append(K.sheet("bus_pillar", g, -0.012, m["trim"], thick=0.016))
    # Entrance door: glazed leaves below the window line, rubber edges.
    yd0, yd1 = K.AX[0] - K.ARCH - 0.05 - 1.1, K.AX[0] - K.ARCH - 0.05
    g = K.patch(gs, "side", K.poly_fn([(yd0, RIDE + 0.22), (yd1, RIDE + 0.22), (yd1, zb(yd1) - 0.02), (yd0, zb(yd0) - 0.02)]),
                10, 6, -1)
    out.append(K.sheet("door_glass", g, 0.006, m["glass"]))
    for y in (yd0, (yd0 + yd1) / 2, yd1):
        F.gap_decal(gs, m, out, [(y, RIDE + 0.2), (y, zr)], "side", w=0.03, side=-1, lift=0.008)
    for z in (RIDE + 0.21, zb(yd1) - 0.01):
        F.gap_decal(gs, m, out, [(yd0, z), (yd1, z)], "side", w=0.03, side=-1, lift=0.008)
    # Destination display over the windscreen.
    h = gs.cast(*K.ray("front", 0.0, K.ROOF - 0.2))
    if h:
        out.append(box("dest_box", (2 * W2 - 0.4, 0.04, 0.2), h[0] + V((0, 0.0, 0)), m["trim"], bevel=0.01))
        R.script(out, {"chrome": m["amber"]}, "42  CITY CENTRE", h[0] + V((0, 0.02, 0)), V((0, 1, 0)), size=0.09)
    out.append(box("ac_pod", (1.6, 2.2, 0.18), (0, (YF + YR) / 2 + 1.2, K.ROOF + 0.09), m["paint"], bevel=0.06, segs=3))
    out.append(box("ac_grille", (1.2, 1.6, 0.01), (0, (YF + YR) / 2 + 1.2, K.ROOF + 0.185), m["trim"]))


def truck_lamp(m, out, x, z, y):
    """A commercial rear combination lamp: black housing, chrome bowls, tail /
    brake, amber indicator, white reverse and red fog cells under a clear
    lens with a chrome bezel."""
    out.append(box("tl_housing", (0.46, 0.07, 0.15), (x, y + 0.01, z), m["trim"], bevel=0.015))
    cells = [(-0.165, m["tail"]), (-0.055, m["amber"]), (0.055, m["rev"]), (0.165, m["tail"])]
    for dx, mt in cells:
        out.append(K.disc_on("tl_bowl", V((x + dx, y - 0.018, z)), V((0, -1, 0)), 0.045, 0.008, m["reflector"], 16))
        for kx in (-0.02, 0.0, 0.02):
            for kz in (-0.02, 0.0, 0.02):
                out.append(K.disc_on("tl_led", V((x + dx + kx, y - 0.026, z + kz)), V((0, -1, 0)), 0.0065, 0.004, mt, 8))
    for dx in (-0.11, 0.0, 0.11):
        out.append(box("tl_div", (0.006, 0.02, 0.12), (x + dx, y - 0.03, z), m["chrome"]))
    out.append(box("tl_lens", (0.44, 0.012, 0.13), (x, y - 0.035, z), m["lens"], bevel=0.008))
    out.append(K.tube_path("tl_bezel", [V((x + 0.225 * math.cos(a) / max(abs(math.cos(a)), abs(math.sin(a)) * 3.2),
                                           y - 0.04, z + 0.07 * math.sin(a) / max(abs(math.cos(a)) / 3.2, abs(math.sin(a)))))
                                       for a in (i * 2 * math.pi / 40 for i in range(41))], 0.004, m["chrome"], 4))


def truck_rear(spec, m, out, y0, z0):
    """Rear of a truck body: combination lamps on the sill, an underride bar
    with red/amber marker boards and reflex reflectors, a lit number plate."""
    W2, RIDE = K.W2, K.RIDE
    w = 2 * W2
    for sx in (1, -1):
        truck_lamp(m, out, sx * (W2 - 0.3), z0 - 0.06, y0 - 0.03)
        out.append(box("mud", (0.45, 0.012, 0.36), (sx * (W2 - 0.3), K.AX[1] - K.ARCH - 0.06, RIDE + 0.14), m["rubber"],
                       bevel=0.004))
    # Underride bar on two arms, marker boards and reflectors on it.
    ub = RIDE + 0.12
    out.append(box("underride", (w - 0.24, 0.1, 0.12), (0, y0 + 0.02, ub), m["trim"], bevel=0.015))
    for sx in (1, -1):
        out.append(box("underride_arm", (0.08, 0.1, z0 - ub - 0.05), (sx * 0.62, y0 + 0.08, (z0 + ub) / 2), m["trim"]))
        out.append(box("marker_board", (0.42, 0.008, 0.1), (sx * (W2 - 0.4), y0 - 0.032, ub), kit.mat("plate_rear", (0.95, 0.78, 0.1), 0.5)))
        for k in range(4):
            st = box("marker_stripe", (0.03, 0.006, 0.12), (0, 0, 0), m["reflex"])
            st.rotation_euler = (0, math.radians(45), 0)
            st.location = (sx * (W2 - 0.55 + k * 0.1), y0 - 0.037, ub)
            out.append(st)
        out.append(box("reflex_tri", (0.08, 0.01, 0.06), (sx * (W2 - 0.14), y0 - 0.03, ub), m["reflex"], bevel=0.004))
    K.number_plate(out, m, V((0, y0 - 0.032, ub)), V((0, -1, 0)), rear=True, text=spec.get("reg", "WS24 TRK"))
    out.append(box("plate_lamp", (0.08, 0.02, 0.02), (0, y0 - 0.03, ub + 0.075), m["rev"], bevel=0.004))


def cargo_box(spec, m, out):
    """Box-truck body behind the cab: panelled box on the chassis with
    corner posts, rub rails, a roller shutter, side markers, the truck rear
    (lamps, underride, plate); spec["cargo"] == "tipper": a steel tipper
    body with ribs, a hinged tailgate and the tipping ram."""
    YR, W2, RIDE = K.YR, K.W2, K.RIDE
    y0, y1 = YR + 0.02, K.Y_TG - 0.06
    z0, z1 = spec["d"]["_rear"] + 0.02, spec["box_h"]
    w = 2 * W2
    yc, zc = (y0 + y1) / 2, (z0 + z1) / 2
    # Ladder chassis: two rails with cross members under the body, back to
    # the cab; a fuel tank and the battery box between the axles; side
    # under-run guards; mudguards over the rear wheels; a sub-frame.
    yt = K.Y_TG + 0.3
    for sx in (1, -1):
        out.append(box("rail", (0.08, yt - y0, 0.24), (sx * 0.42, (yt + y0) / 2, z0 - 0.17), m["trim"], bevel=0.01))
        out.append(box("subframe", (0.1, y1 - y0, 0.1), (sx * 0.42, yc, z0 - 0.03), m["trim"]))
    for i in range(5):
        out.append(box("cross", (0.84, 0.06, 0.12), (0, y0 + 0.1 + i * (yt - y0 - 0.2) / 4, z0 - 0.17), m["trim"]))
    ya, yb_ = K.AX[1] + K.ARCH + 0.15, K.AX[0] - K.ARCH - 0.2
    if yb_ - ya > 0.6:
        tank = cyl("fuel_tank", 0.24, min(1.0, yb_ - ya - 0.3), (0, 0, 0), m["reflector"], 20)
        tank.rotation_euler = (math.pi / 2, 0, 0)
        tank.location = (W2 - 0.45, ya + 0.2, RIDE + 0.42)
        out.append(tank)
        for sx in (1, -1):
            for z in (RIDE + 0.12, RIDE + 0.3):
                out.append(box("side_guard", (0.04, yb_ - ya, 0.06), (sx * (W2 - 0.08), (ya + yb_) / 2, z), m["trim"], bevel=0.008))
    for sx in (1, -1):
        pts = [V((sx * (W2 - 0.2), K.AX[1] + math.cos(a) * (K.WR + 0.1), K.WR + math.sin(a) * (K.WR + 0.1)))
               for a in (math.radians(10 + 160 * i / 12) for i in range(13))]
        out.append(K.tube_path("mudguard", pts, 0.05, m["trim"], 6))
        g = [[(p + V((sx * dx, 0, 0)), V((sx, 0, 0))) for p in pts] for dx in (-0.16, 0.14)]
        out.append(K.sheet("mudguard_top", g, 0.0, m["trim"]))
    if spec.get("cargo") == "tipper":
        # Tapered tub: wider at the top, a ribbed steel side, top rail.
        secs = []
        for y in (y1, y0):
            secs.append([V((x, y, z)) for x, z in ((W2 - 0.08, z0), (W2, z1), (-W2, z1), (-W2 + 0.08, z0))])
        tub = loft("tub", secs, m["paint"], smooth=False)
        out.append(tub)
        out.append(box("tub_floor", (w - 0.2, y1 - y0, 0.06), (0, yc, z0 + 0.02), m["trim"]))
        for sx in (1, -1):
            n = int((y1 - y0) / 0.42)
            for i in range(n + 1):
                y = y0 + 0.06 + i * (y1 - y0 - 0.12) / n
                out.append(box("tub_rib", (0.05, 0.07, z1 - z0 - 0.04), (sx * (W2 - 0.03), y, zc), m["paint"], bevel=0.008))
            out.append(box("tub_rail", (0.08, y1 - y0 + 0.04, 0.07), (sx * W2, yc, z1 + 0.01), m["paint"], bevel=0.012))
            out.append(box("tub_rail_lo", (0.06, y1 - y0, 0.06), (sx * (W2 - 0.07), yc, z0 + 0.06), m["trim"], bevel=0.01))
            for y in (y0 + 0.5, yc, y1 - 0.5):
                out.append(box("marker", (0.02, 0.07, 0.04), (sx * (W2 - 0.05), y, z0 - 0.02), m["amber"], bevel=0.004))
        # Hinged tailgate with its top pins, a canopy over the cab.
        out.append(box("tailgate", (w - 0.04, 0.08, z1 - z0 - 0.02), (0, y0 - 0.02, zc), m["paint"], bevel=0.02))
        for i in range(4):
            out.append(box("gate_rib", (0.06, 0.03, z1 - z0 - 0.1), (-W2 * 0.75 + i * W2 * 0.5, y0 - 0.07, zc), m["paint"],
                           bevel=0.008))
        for sx in (1, -1):
            out.append(cyl("gate_pin", 0.035, 0.1, (sx * (W2 - 0.05), y0 - 0.02, z1 - 0.03), m["chrome"], 12))
        out.append(box("canopy", (w - 0.1, 0.45, 0.05), (0, y1 + 0.2, z1 + 0.02), m["paint"], bevel=0.015))
        ram = K.tube_path("ram", [V((0, y1 - 0.05, z0 - 0.2)), V((0, y1 - 0.2, z0 + 0.25))], 0.07, m["chrome"], 12)
        out.append(ram)
    else:
        out.append(box("cargo", (w - 0.02, y1 - y0, z1 - z0), (0, yc, zc), m["paint"], bevel=0.03, segs=2))
        for sx in (1, -1):
            for y in (y0 + 0.03, y1 - 0.03):
                out.append(box("post", (0.07, 0.07, z1 - z0 + 0.02), (sx * (W2 - 0.02), y, zc), m["reflector"], bevel=0.01))
            for z in (z0 + 0.05, z1 - 0.04):
                out.append(box("rail", (0.04, y1 - y0, 0.06), (sx * (W2 + 0.0), yc, z), m["reflector"], bevel=0.008))
            out.append(box("rub", (0.05, y1 - y0 - 0.2, 0.08), (sx * (W2 + 0.01), yc, z0 + 0.35), m["trim"], bevel=0.01))
            n = int((y1 - y0) / 0.6)
            for i in range(1, n):
                out.append(box("rib", (0.02, 0.05, z1 - z0 - 0.2), (sx * (W2 - 0.0), y0 + i * (y1 - y0) / n, zc), m["paint"]))
            for y in (y0 + 0.4, yc, y1 - 0.4):
                out.append(box("marker", (0.02, 0.07, 0.04), (sx * (W2 + 0.02), y, z0 + 0.2), m["amber"], bevel=0.004))
        # Roller shutter: slats in a frame, a chrome handle and lock.
        out.append(box("shutter_frame", (w - 0.1, 0.04, z1 - z0 - 0.06), (0, y0 - 0.005, zc), m["reflector"]))
        z = z0 + 0.08
        while z < z1 - 0.1:
            out.append(box("slat", (w - 0.24, 0.035, 0.07), (0, y0 - 0.025, z + 0.035), m["paint"], bevel=0.008))
            z += 0.085
        out.append(box("handle", (0.3, 0.04, 0.035), (0, y0 - 0.06, z0 + 0.22), m["chrome"], bevel=0.012))
        out.append(cyl("lock", 0.025, 0.02, (0.25, y0 - 0.05, z0 + 0.22), m["chrome"], 12))
        for sx in (1, -1):
            out.append(box("top_marker", (0.07, 0.03, 0.04), (sx * (W2 - 0.08), y0 - 0.02, z1 - 0.06), m["tail"], bevel=0.006))
    truck_rear(spec, m, out, y0, z0)


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


def police_lightbar(m, out, y, z, low=False):
    """Low-profile LED light bar on two roof feet: a black extrusion, red /
    blue LED modules (CarVisual's beacon shader flashes the halves), white
    take-down lamps, an amber traffic advisor facing back, all under a clear
    lens with a polished end cap each side."""
    w = 1.16 if not low else 0.9
    h = 0.075 if not low else 0.05
    d = 0.28 if not low else 0.22
    zc = z + 0.045 + h / 2
    for sx in (1, -1):
        out.append(box("lb_foot", (0.07, 0.14, 0.05), (sx * w * 0.36, y, z + 0.02), m["plastic"], bevel=0.01))
    out.append(box("lb_base", (w, d, h * 0.45), (0, y, zc - h * 0.28), m["trim"], bevel=0.012))
    n = 8
    for i in range(n):
        x = -w / 2 + 0.08 + (w - 0.16) * (i + 0.5) / n
        if abs(x) < 0.09:
            continue
        mat = m["beacon_blue"]
        out.append(box("lb_led", ((w - 0.16) / n - 0.02, d - 0.05, h * 0.5), (x, y, zc + h * 0.05), mat, bevel=0.006))
    for sx in (1, -1):
        out.append(box("lb_takedown", (0.06, 0.01, h * 0.42), (sx * 0.045, y + d / 2 - 0.02, zc), m["head"], bevel=0.004))
    for i in range(6):
        x = -0.25 + i * 0.1
        out.append(box("lb_advisor", (0.07, 0.01, h * 0.35), (x, y - d / 2 + 0.02, zc), m["amber"], bevel=0.003))
    out.append(box("lb_lens", (w - 0.02, d + 0.01, h * 0.8), (0, y, zc + h * 0.08), m["lens"], bevel=0.025, segs=3))
    for sx in (1, -1):
        out.append(box("lb_cap", (0.03, d + 0.015, h * 0.85), (sx * (w / 2 - 0.005), y, zc + h * 0.05), m["chrome"], bevel=0.012))


# ------------------------------------------------------------------ build
def build_car(name):
    spec = CARS[name]
    d = spec["d"]
    use(d)
    kind = d["_kind"]
    feats = set(spec["feats"])
    kit.reset()
    m = mats()
    out = []
    clean = K.build_shell(m["paint"])
    clean.hide_render = True
    body = K.decimated(clean, spec.get("dec", 0.16))
    W2, AX, WR, ARCH, RIDE, YF, YR = K.W2, K.AX, K.WR, K.ARCH, K.RIDE, K.YF, K.YR
    belt, nose, rear = d["_belt"], d["_nose"], d["_rear"]
    hw = K.half_width
    # Trucks: the shell is the cab only - everything behind its back wall
    # goes (the body was carrying on under the load box as a fat hull).
    if kind == "box":
        yb = K.Y_TG - 0.03
        for ob in (body, clean):
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            r = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, yb, 0), plane_no=(0, 1, 0), clear_inner=True)
            edges = [e for e in r["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
            if edges:
                f = bmesh.ops.contextual_create(bm, geom=edges)    # cab back wall
                for fc in f.get("faces", []):
                    fc.material_index = 0
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(ob.data)
            bm.free()
        K.CAV_Y0 = max(K.CAV_Y0, yb + 0.05) if K.CAV_Y0 is not None else yb + 0.05
    # Pickup bed / truck body seat: cut the load bed out behind the cab.
    if "bed" in feats:
        y0, y1 = YR + 0.1, K.Y_TG - 0.1
        c = box("bedcut", (2 * (W2 - 0.08), y1 - y0, 2.0), (0, (y0 + y1) / 2, RIDE + 0.62 + 1.0), None)
        K.cut(body, c, m["bed"])
        K.cut(clean, box("bedcut2", (2 * (W2 - 0.08), y1 - y0, 2.0), (0, (y0 + y1) / 2, RIDE + 0.62 + 1.0), None))
        out.append(box("bed_floor", (2 * (W2 - 0.1), y1 - y0, 0.02), (0, (y0 + y1) / 2, RIDE + 0.63), m["bed"]))
        for sx in (1, -1):
            out.append(box("bed_rail", (0.1, y1 - y0 + 0.16, 0.035), (sx * (W2 - 0.06), (y0 + y1) / 2, rear + 0.01),
                           m["cladding"], bevel=0.01))
    # Arches + dark wells.
    for ay in AX:
        for sx in (1, -1):
            c = cyl("arch", ARCH, 0.7, (0, 0, 0), None, 36)
            c.rotation_euler = (0, math.pi / 2, 0)
            c.location = ((W2 - 0.4) if sx > 0 else (-W2 - 0.3), ay, WR)
            K.cut(body, c, m["liner"])
            well = cyl("well", ARCH - 0.004, 0.36, (0, 0, 0), m["liner"], 24, cap=False)
            well.rotation_euler = (0, math.pi / 2, 0)
            well.location = (sx * (W2 - 0.38) - (0.0 if sx > 0 else 0.36), ay, WR)
            out.append(well)
            wall = cyl("well_wall", ARCH - 0.004, 0.01, (0, 0, 0), m["liner"], 24)
            wall.rotation_euler = (0, math.pi / 2, 0)
            wall.location = (sx * (W2 - 0.38) - (0.0 if sx > 0 else 0.01), ay, WR)
            out.append(wall)
    # Panel gaps.
    ra = ARCH + 0.035
    a0 = math.asin(max(-1.0, min(1.0, (K.SILL_Z - WR) / ra)))
    arc_f = [(AX[0] - math.cos(a) * ra, WR + math.sin(a) * ra) for a in (a0 + (1.2 - a0) * i / 7 for i in range(8))]
    arc_r = [(AX[1] + math.cos(a) * ra, WR + math.sin(a) * ra) for a in (a0 + (1.15 - a0) * i / 7 for i in range(8))]
    top = lambda y: K.smooth(K.DECK, y) - 0.012
    doors = spec["doors"]
    yd0 = arc_f[0][0]
    if doors == 0:                                    # bus: its doors are glass (bus_kit)
        lines = []
    elif doors == 1:                                    # supercar: dihedral door ahead of the intake
        yd1 = K.Y_RE - 0.05
        lines = [[(yd0 - 0.02, K.SILL_Z), (yd0, top(yd0))], [(yd1, K.SILL_Z + 0.04), (yd1 + 0.08, top(yd1 + 0.08))],
                 [(yd0, K.SILL_Z), (yd1, K.SILL_Z + 0.04)]]
    elif doors == 2:
        yd1 = max(arc_r[0][0] + 0.45, K.Y_RE + 0.1)
        if kind == "van":
            yd1 = AX[0] - ARCH - 0.75
        elif kind == "box":
            yd1 = K.Y_TG + 0.06
        lines = [arc_f + [(arc_f[-1][0] - 0.02, top(arc_f[-1][0]))], [(yd1, K.SILL_Z), (yd1 + 0.04, top(yd1 + 0.04))],
                 [(arc_f[0][0], K.SILL_Z), (yd1, K.SILL_Z)]]
    else:
        ymid = (arc_f[0][0] + arc_r[0][0]) / 2 + 0.08
        lines = [arc_f + [(arc_f[-1][0] - 0.02, top(arc_f[-1][0]))], [(ymid, K.SILL_Z), (ymid, top(ymid))],
                 [(arc_f[0][0], K.SILL_Z), (arc_r[0][0], K.SILL_Z)]]
        if kind != "pickup":
            lines.append(arc_r + [(arc_r[-1][0] - 0.01, top(arc_r[-1][0]))])
        else:
            yb = K.Y_TG + 0.02
            lines.append([(yb, K.SILL_Z), (yb, top(yb))])
    # Use the actual rendered shell, including the wheel-arch cuts.
    gs = K.Surface([body])
    for ln in lines:
        F.gap_decal(gs, m, out, ln, "side", side=0)
    for sx in (1, -1):
        bon = [(sx * (hw(y) - (0.16 if kind != "mid" else 0.3)), y) for y in (K.Y_COWL + 0.04, (K.Y_COWL + YF) / 2, YF - 0.2)]
        if kind != "mid" and YF - 0.2 > K.Y_COWL + 0.1:
            F.gap_decal(gs, m, out, bon, "top", w=0.0035, lift=0.0018)
    if kind in ("saloon", "muscle", "coupe"):
        for sx in (1, -1):
            xi = W2 * (0.5 if kind != "muscle" else 0.56) - 0.018     # (lines up with the rear shut line)
            F.gap_decal(gs, m, out, [(sx * xi, K.Y_TG + 0.03), (sx * xi, YR + 0.1)], "top")
        F.gap_decal(gs, m, out, [(-xi, K.Y_TG + 0.03), (xi, K.Y_TG + 0.03)], "top")
    elif kind == "mid":
        # Engine cover outline between the buttresses.
        rx = K.ring(K.Y_RE - 0.1)[2].x - 0.06
        F.gap_decal(gs, m, out, [(-rx, K.Y_RE - 0.35), (rx, K.Y_RE - 0.35), (rx * 0.9, YR + 0.35), (-rx * 0.9, YR + 0.35),
                                 (-rx, K.Y_RE - 0.35)], "top")
    surf = K.Surface([body])
    # ---- nose
    ztop = 0.0
    for z in [0.3 + i * 0.01 for i in range(150)]:
        h = surf.cast(*K.ray("front", W2 * 0.55, z))
        if h and h[1].y > 0.3 and h[0].y > YF - 0.5:
            ztop = z
    zl = ztop - 0.015
    if kind == "mid":
        zl = nose + 0.01
    lamps = spec["lamps"]
    if lamps == "blade":
        lp = [(W2 * 0.5, zl - 0.05), (W2 * 0.9, zl - 0.02), (W2 * 0.93, zl), (W2 * 0.52, zl - 0.01)]
    elif lamps == "slim":
        lp = [(W2 * 0.42, zl - 0.075), (W2 * 0.9, zl - 0.055), (W2 * 0.92, zl), (W2 * 0.44, zl - 0.01)]
    elif lamps == "round":
        lp = [(W2 * 0.55, zl - 0.17), (W2 * 0.88, zl - 0.17), (W2 * 0.88, zl - 0.02), (W2 * 0.55, zl - 0.02)]
    else:  # square (trucks)
        lp = [(W2 * 0.55, zl - 0.2), (W2 * 0.92, zl - 0.2), (W2 * 0.92, zl - 0.02), (W2 * 0.55, zl - 0.02)]
    if lamps == "blade":
        top_lamps(surf, m, out)
    else:
        K.head_lamp(surf, body, m, out, lp)
    surf = K.Surface([body])
    gr = spec["grille"]
    if gr == "kidney":
        for sx in (1, -1):
            K.opening(surf, body, m, out, [(sx * 0.03, zl - 0.16), (sx * 0.3, zl - 0.16), (sx * 0.31, zl - 0.02),
                                           (sx * 0.04, zl - 0.02)] if sx > 0 else
                      [(-0.3, zl - 0.16), (-0.03, zl - 0.16), (-0.04, zl - 0.02), (-0.31, zl - 0.02)],
                      0.05, "slats", frame="chrome", res=(8, 4))
            surf = K.Surface([body])
        K.opening(surf, body, m, out, [(-W2 * 0.55, RIDE + 0.1), (W2 * 0.55, RIDE + 0.1), (W2 * 0.6, RIDE + 0.26),
                                       (-W2 * 0.6, RIDE + 0.26)], 0.06, "mesh", res=(16, 3))
    elif gr == "saloon":
        K.opening(surf, body, m, out, [(-W2 * 0.36, zl - 0.17), (W2 * 0.36, zl - 0.17), (W2 * 0.4, zl - 0.02),
                                       (-W2 * 0.4, zl - 0.02)], 0.05, "mesh", frame="chrome", res=(14, 4))
        surf = K.Surface([body])
        K.opening(surf, body, m, out, [(-W2 * 0.55, RIDE + 0.1), (W2 * 0.55, RIDE + 0.1), (W2 * 0.6, RIDE + 0.24),
                                       (-W2 * 0.6, RIDE + 0.24)], 0.06, "mesh", res=(16, 3))
        surf = K.Surface([body])
        for sx in (1, -1):
            q = [(sx * W2 * 0.7, RIDE + 0.1), (sx * W2 * 0.9, RIDE + 0.12), (sx * W2 * 0.88, RIDE + 0.28),
                 (sx * W2 * 0.72, RIDE + 0.26)]
            if sx < 0:
                q = [q[1], q[0], q[3], q[2]]
            K.opening(surf, body, m, out, q, 0.05, "slats", res=(6, 3))
            surf = K.Surface([body])
    elif gr in ("mesh", "intake", "wide"):
        gh = {"mesh": 0.24, "intake": 0.2, "wide": 0.2}[gr]
        top_z = zl - (0.03 if gr != "intake" else 0.11)
        gw = {"mesh": 0.62, "intake": 0.5, "wide": 0.78}[gr]
        K.opening(surf, body, m, out, [(-W2 * gw, top_z - gh), (W2 * gw, top_z - gh), (W2 * (gw + 0.04), top_z),
                                       (-W2 * (gw + 0.04), top_z)], 0.06, "mesh" if gr != "wide" else "slats",
                  frame="chrome" if gr == "wide" else "trim", res=(16, 4))
        surf = K.Surface([body])
        if gr != "wide":
            for sx in (1, -1):
                q = [(sx * W2 * 0.68, RIDE + 0.1), (sx * W2 * 0.9, RIDE + 0.12), (sx * W2 * 0.9, RIDE + 0.24),
                     (sx * W2 * 0.68, RIDE + 0.24)]
                if sx < 0:
                    q = [q[1], q[0], q[3], q[2]]
                K.opening(surf, body, m, out, q, 0.05, "mesh", res=(6, 3))
                surf = K.Surface([body])
    elif gr == "supercar":
        # Two big corner intakes and a centre splitter channel.
        for sx in (1, -1):
            q = [(sx * W2 * 0.4, RIDE + 0.06), (sx * W2 * 0.8, RIDE + 0.07), (sx * W2 * 0.76, RIDE + 0.24),
                 (sx * W2 * 0.45, RIDE + 0.2)]
            if sx < 0:
                q = [q[1], q[0], q[3], q[2]]
            K.opening(surf, body, m, out, q, 0.07, "slats", frame=None, res=(8, 4))
            surf = K.Surface([body])
        K.opening(surf, body, m, out, [(-W2 * 0.3, RIDE + 0.07), (W2 * 0.3, RIDE + 0.07), (W2 * 0.26, RIDE + 0.17),
                                       (-W2 * 0.26, RIDE + 0.17)], 0.06, "mesh", frame=None, res=(10, 2))
    elif gr == "bus":
        # Bus front: a slim slatted intake low in the bumper, the panel above
        # left clean for the lamps and the maker's badge.
        K.opening(surf, body, m, out, [(-W2 * 0.42, RIDE + 0.22), (W2 * 0.42, RIDE + 0.22), (W2 * 0.44, RIDE + 0.4),
                                       (-W2 * 0.44, RIDE + 0.4)], 0.05, "slats", frame="chrome", res=(16, 4))
    elif gr in ("truck", "slats"):
        gt = zl - 0.01
        gb = RIDE + (0.5 if gr == "truck" else 0.48)
        K.opening(surf, body, m, out, [(-W2 * 0.5, gb), (W2 * 0.5, gb), (W2 * 0.52, gt), (-W2 * 0.52, gt)], 0.06,
                  "slats" if gr == "slats" else "mesh", frame="chrome" if gr == "truck" else "trim", res=(16, 6))
    if gr in ("saloon", "mesh", "intake", "wide") and "light_pod" not in feats:
        R.fog_lamp(body, m, out, W2 * 0.79, RIDE + 0.33, 0.03)
    elif gr in ("truck", "slats") and kind != "box":
        R.fog_lamp(body, m, out, W2 * 0.74, RIDE + 0.4, 0.036)
    R.front_end(body, clean, m, out, kind, zl=zl, lamp_poly=lp, badge=gr not in ("kidney",))
    surf = K.Surface([body])
    # Front plate (not on supercars: they run without one).
    if kind not in ("mid",):
        h = surf.cast(*K.ray("front", 0.0, RIDE + (0.34 if kind not in ("pickup", "box4x4") else 0.42)))
        if h:
            nf = V((0, 1, 0.1)).normalized()
            hold = box("plate_holder", (0.54, 0.125, 0.026), (0, 0, 0), m["plastic"], bevel=0.006)
            hold.rotation_mode = "QUATERNION"
            hold.rotation_quaternion = nf.to_track_quat("Z", "Y")
            hold.location = h[0] + nf * 0.006
            out.append(hold)
            K.number_plate(out, m, h[0] + nf * 0.024, nf, rear=False, text=spec.get("reg", "WS24 EMP"))
    # ---- tail (tools/blender/ws_rear.py: the same rear kit on every vehicle)
    pipes = []
    if "quad_pipes" in feats:
        sh = "oval" if kind == "muscle" else "round"
        pipes = [(W2 * 0.5, RIDE + 0.125, 0.038, sh), (W2 * 0.64, RIDE + 0.125, 0.038, sh)]
    elif "twin_pipe" in feats:
        pipes = [(W2 * 0.62, RIDE + 0.13, 0.048, "round")]
    elif "centre_pipes" in feats:
        pipes = [(0.11, rear - 0.43, 0.05, "round")]
    elif "quad_pipes_high" in feats:
        pipes = [(0.07, rear - 0.44, 0.038, "hex"), (0.19, rear - 0.44, 0.038, "hex")]
    elif kind in ("pickup", "box4x4"):
        pipes = [(W2 * 0.6, RIDE + 0.12, 0.045, "round")]
    R.rear_end(body, clean, m, out, "box4x4" if kind == "bus" else kind, feats, belt=belt, rear=rear, label=spec.get("label", ""),
               reg=spec.get("reg", "WS24 EMP"), doors=doors, pipes=pipes,
               plate_z=(rear - 0.3) if kind == "mid" else None)
    if kind == "mid":
        # Mesh grille over the engine-bay outlet between the lamps.
        surf = K.Surface([body])
        g = K.opening(surf, body, m, out, [(-W2 * 0.46, rear - 0.215), (W2 * 0.46, rear - 0.215), (W2 * 0.48, rear - 0.15),
                                           (-W2 * 0.48, rear - 0.15)], 0.11, "mesh", frame="chrome", res=(16, 3), view="rear")
        # Second layer deep inside: horizontal heat-shield slats.
        nv_ = len(g) - 1
        navg = sum((c[1] for row in g for c in row if c), V()).normalized()
        for j in (1, 2):
            pts = [c[0] - navg * 0.085 for c in g[j][1:-1] if c]
            if len(pts) > 2:
                out.append(K.tube_path("heat_slat", pts, 0.008, m["reflector"], 6))
    surf = K.Surface([body])
    # ---- glass (sealed, tinted, on black frit)
    rs = K.Surface([body])   # (on the decimated shell the game draws: on the full one paint poked through)
    zb = lambda y: K.smooth(K.DECK, y) + 0.02
    yf0 = K.Y_COWL - 0.1
    zr = K.ROOF - (0.09 if kind != "mid" else 0.07)
    if kind == "mid":
        yr0 = K.Y_RE - 0.32
        poly = [(yr0, zb(yr0) + 0.05), (yf0, zb(yf0)), (K.Y_WS + 0.03, zr), (K.Y_RE - 0.02, zr)]
    elif kind == "saloon" or kind == "muscle":
        yr0 = K.Y_RE - 0.15
        poly = [(yr0, zb(yr0)), (yf0, zb(yf0)), (K.Y_WS + 0.03, zr), (yr0 + 0.25, zr)]
    elif kind == "coupe":
        yr0 = K.Y_RE - 0.25
        poly = [(yr0, zb(yr0)), (yf0, zb(yf0)), (K.Y_WS + 0.03, zr), (K.Y_RE + 0.05, zr)]
    elif kind in ("pickup", "box"):
        yr0 = K.Y_TG + 0.08
        poly = [(yr0, zb(yr0)), (yf0, zb(yf0)), (K.Y_WS + 0.03, zr), (yr0, zr)]
    elif kind == "van":
        yr0 = AX[0] - ARCH - 0.78
        poly = [(yr0, zb(yr0)), (yf0, zb(yf0)), (K.Y_WS + 0.05, zr), (yr0, zr)]
    elif kind == "bus":
        yr0 = YR + 0.4
        poly = [(yr0, zb(yr0)), (yf0, zb(yf0)), (K.Y_WS + 0.05, zr), (yr0, zr)]
    else:
        yr0 = K.Y_TG + (0.2 if kind != "box4x4" else 0.1)
        poly = [(yr0, zb(yr0)), (yf0, zb(yf0)), (K.Y_WS + 0.03, zr), (yr0 + 0.05, zr)]
    cabin = spec.get("cabin", True)
    if cabin:
        # A real cabin (as the Kestrel): the shell hollowed out, the side
        # windows and windscreen cut through with clear glass set in, an
        # interior you can see through them.
        K.cut(body, K.cavity_solid(), m["interior"])
        for sd in (1, -1):
            K.glaze(body, clean, m, out, poly, "x", 0.3 if sd > 0 else -2.0, 2.0 if sd > 0 else -0.3)
        yb_, yt_ = K.Y_COWL - 0.05, K.Y_WS + 0.04
        wb_, wt_ = K.ring(yb_)[2].x + 0.08, K.ring(yt_)[2].x - 0.03
        K.glaze(body, clean, m, out, [(-wb_, yb_), (wb_, yb_), (wt_, yt_), (-wt_, yt_)], "z",
                K.smooth(K.DECK, K.Y_COWL) - 0.12, K.ROOF + 0.3)
        # Seals round every opening (chrome window line on saloons), wipers.
        for sd in (1, -1):
            R.outline_trim(gs, m, out, poly, "side", sd, mat="chrome" if kind in ("saloon",) else "trim", r=0.0065)
        R.outline_trim(gs, m, out, [(-wb_, yb_), (wb_, yb_), (wt_, yt_), (-wt_, yt_)], "top", r=0.007)
        R.wipers(m, out, K.Y_COWL - 0.03, K.smooth(K.DECK, K.Y_COWL) + 0.015, K.ring(K.Y_COWL)[2].x)
        if kind == "bus":
            bus_interior(m, out)
        else:
            cabin_interior(m, out, kind, doors)
        rs = K.Surface([body])
    else:
        for sd in (1, -1):
            F.glass_sheet(rs, m, out, "side", poly, sd, lift=0.013, res=(16, 8))
    if not cabin:
        rw = K.ring(K.Y_COWL - 0.05)[2].x
        F.glass_sheet(rs, m, out, "top", [(-rw - 0.04, K.Y_COWL - 0.05), (rw + 0.04, K.Y_COWL - 0.05),
                                      (K.ring(K.Y_WS + 0.04)[2].x - 0.02, K.Y_WS + 0.04),
                                      (-K.ring(K.Y_WS + 0.04)[2].x + 0.02, K.Y_WS + 0.04)], lift=0.013, res=(14, 10))
    if kind in ("saloon", "muscle", "coupe") and cabin:
        # Rear screen cut through too: you see the cabin from behind.
        rx = K.ring(K.Y_RE - 0.05)[2].x - 0.03
        y_lo = K.Y_TG + 0.08 if kind != "coupe" else K.Y_TG + 0.35
        K.glaze(body, clean, m, out, [(-rx * 0.9, y_lo), (rx * 0.9, y_lo), (rx, K.Y_RE - 0.05), (-rx, K.Y_RE - 0.05)], "z",
                K.smooth(K.DECK, y_lo) - 0.1, K.ROOF + 0.3)
        R.outline_trim(gs, m, out, [(-rx * 0.9, y_lo), (rx * 0.9, y_lo), (rx, K.Y_RE - 0.05), (-rx, K.Y_RE - 0.05)], "top", r=0.007)
        rs = K.Surface([body])
    elif kind in ("saloon", "muscle", "coupe"):
        rx = K.ring(K.Y_RE - 0.05)[2].x - 0.03
        y_lo = K.Y_TG + 0.06 if kind != "coupe" else K.Y_TG + 0.35
        F.glass_sheet(rs, m, out, "top", [(-rx * 0.92, y_lo), (rx * 0.92, y_lo), (rx, K.Y_RE - 0.05), (-rx, K.Y_RE - 0.05)],
                      lift=0.013, res=(14, 8))
    elif kind == "mid":
        rx = K.ring(K.Y_RE - 0.05)[2].x - 0.05
        F.glass_sheet(rs, m, out, "top", [(-rx * 0.85, K.Y_RE - 0.3), (rx * 0.85, K.Y_RE - 0.3), (rx, K.Y_RE - 0.02),
                                          (-rx, K.Y_RE - 0.02)], lift=0.013, res=(10, 6))
    elif kind in ("pickup", "box"):
        F.glass_sheet(rs, m, out, "rear", [(-W2 * 0.5, belt + 0.1), (W2 * 0.5, belt + 0.1), (W2 * 0.48, K.ROOF - 0.1),
                                           (-W2 * 0.48, K.ROOF - 0.1)]) if False else None
    else:
        zt = K.ROOF - 0.08
        z0 = zb(K.Y_TG) + 0.03
        F.glass_sheet(rs, m, out, "rear", [(-W2 * 0.56, z0), (W2 * 0.56, z0), (W2 * 0.46, zt - 0.02), (-W2 * 0.46, zt - 0.02)],
                      lift=0.014, res=(14, 8))
    if "bus_kit" in feats:
        bus_kit(spec, m, out, gs, poly, zb, zr)
    # B-pillar (4-door).
    if doors == 4:
        ymid = (arc_f[0][0] + arc_r[0][0]) / 2 + 0.08
        for sd in (1, -1):
            # (on the uncut shell: the window opening runs through here)
            g = K.patch(gs, "side", K.poly_fn([(ymid - 0.05, zb(ymid) - 0.03), (ymid + 0.05, zb(ymid) - 0.03), (ymid + 0.05, zr + 0.03),
                                               (ymid - 0.05, zr + 0.03)]), 2, 6, sd)
            out.append(K.sheet("b_pillar", g, -0.012, m["trim"], thick=0.016))
    if kind == "box4x4":
        yc = K.Y_TG + 0.75
        for sd in (1, -1):
            g = K.patch(gs, "side", K.poly_fn([(yc - 0.07, zb(yc) - 0.03), (yc + 0.07, zb(yc) - 0.03), (yc + 0.07, zr + 0.03),
                                               (yc - 0.07, zr + 0.03)]), 2, 6, sd)
            out.append(K.sheet("c_pillar", g, -0.012, m["paint"], thick=0.014))
    K.mirrors(m, out, gs)
    surf = K.Surface([body])
    roof_at = lambda y: (rs.cast(V((0, y, 4.0)), V((0, 0, -1))) or [V((0, y, K.ROOF))])[0].z
    rear_at = lambda y: (rs.cast(V((W2 * 0.52, y, 4.0)), V((0, 0, -1))) or [V((0, y, rear))])[0].z
    # ---- class kit
    if "skirts" in feats:
        for sd in (1, -1):
            g = K.patch(surf, "side", K.poly_fn([(AX[1] + ARCH + 0.04, RIDE + 0.03), (AX[0] - ARCH - 0.04, RIDE + 0.03),
                                                 (AX[0] - ARCH - 0.04, K.SILL_Z - 0.05), (AX[1] + ARCH + 0.04, K.SILL_Z - 0.05)]),
                        12, 2, sd)
            out.append(K.sheet("skirt", g, 0.002, m["carbon"], thick=0.02))
    if "splitter" in feats:
        h = surf.cast(*K.ray("front", 0.0, RIDE + 0.05))
        yy = h[0].y if h else YF - 0.1
        out.append(box("splitter", (2 * W2 * 0.8, 0.1, 0.016), (0, yy - 0.05, RIDE + 0.01), m["carbon"], bevel=0.006))
    if "lip_spoiler" in feats:
        g = K.patch(surf, "top", K.poly_fn([(-W2 * 0.78, YR + 0.07), (W2 * 0.78, YR + 0.07), (W2 * 0.76, YR + 0.12),
                                            (-W2 * 0.76, YR + 0.12)]), 16, 1)
        out.append(K.sheet("lip", g, 0.0, m["carbon"], thick=0.025))
    if "duck_tail" in feats:
        g = K.patch(surf, "top", K.poly_fn([(-W2 * 0.8, YR + 0.05), (W2 * 0.8, YR + 0.05), (W2 * 0.78, YR + 0.2),
                                            (-W2 * 0.78, YR + 0.2)]), 16, 4)
        nv = len(g) - 1
        for j in range(nv + 1):
            for i in range(len(g[0])):
                c = g[j][i]
                if c:
                    g[j][i] = (c[0] + V((0, 0, 0.045 * (1 - j / nv) ** 1.5)), c[1])
        out.append(K.sheet("ducktail", g, 0.0, m["paint"], thick=0.01))
    if "roof_spoiler" in feats:
        # Hatch spoiler: a slim lip carrying the roof line on past the
        # tailgate glass (no plank on stilts), the third brake lamp under it.
        y = K.Y_RE
        z = roof_at(y + 0.06)
        rx = K.ring(y)[2].x
        wing(m, out, y - 0.02, z - 0.018, 2 * rx - 0.07, 0.17, 0.09, angle=-6, plates=False, mat="paint", uprights=False)
        R.third_brake(m, out, y - 0.1, z - 0.045, 0.3)
    elif kind in ("saloon", "muscle", "coupe"):
        R.third_brake(m, out, K.Y_RE - 0.02, roof_at(K.Y_RE + 0.04) - 0.035, 0.32)
    if "rear_wing" in feats:
        z = rear + 0.17
        wing(m, out, YR + 0.3, z, 2 * W2 * 0.8, 0.26, 0.11, angle=6, base_z=rear_at(YR + 0.3))
    if "big_wing" in feats:
        z = rear + 0.27
        wing(m, out, YR + 0.3, z, 2 * W2 * 0.84, 0.3, 0.12, angle=10, base_z=rear_at(YR + 0.3))
    if "louvres" in feats:
        # Folded extractors pick up highlights and have a real trailing edge.
        # Keep the shell solid underneath, without a wide dark strip on paint.
        deck = K.Surface([body])
        for i in range(6):
            y = K.Y_RE - 0.55 - i * 0.12
            if y < YR + 0.45:
                break
            rx = K.ring(y)[2].x * (0.56 - i * 0.025)
            shape = K.poly_fn([(-rx, y - 0.024), (rx, y - 0.024),
                               (rx * 0.94, y + 0.020), (-rx * 0.94, y + 0.020)])
            hits = K.patch(deck, "top", shape, 16, 2, 1)
            rows = []
            for row in hits:
                projected = []
                for hit in row:
                    if hit is None:
                        projected.append(None)
                        continue
                    point, normal = hit
                    t = min(1.0, max(0.0, (point.y - y + 0.024) / 0.044))
                    lift = (1.0 - (abs(point.x) / max(0.01, rx)) ** 4) * (0.003 + 0.019 * t)
                    projected.append((point + normal * lift, normal))
                rows.append(projected)
            out.append(K.sheet("folded extractor", rows, 0.001, m["paint"], thick=0.007))
    if "roof_scoop_mid" in feats or "roof_scoop" in feats:
        y = K.Y_WS - 0.35 if "roof_scoop" in feats else K.Y_RE - 0.15
        z = roof_at(y)
        sc = loft("scoop", [[V((x * sx, y + yy, z + zz)) for sx, x, zz in
                             ((1, 0.13, -0.01), (1, 0.1, 0.055), (-1, 0.1, 0.055), (-1, 0.13, -0.01))]
                            for yy in (0.2, 0.0, -0.3)], m["paint"], smooth=False)
        out.append(sc)
        out.append(box("scoop_mouth", (0.19, 0.01, 0.045), (0, y + 0.205, z + 0.024), m["liner"]))
    if "side_intakes" in feats:
        yb0, yb1 = AX[1] + ARCH + 0.12, K.Y_RE - 0.12
        zc = K.smooth(K.CREASE, (yb0 + yb1) / 2)
        side_opening(surf, body, m, out, [(yb0, RIDE + 0.3), (yb1, RIDE + 0.25), (yb1 - 0.05, zc - 0.05),
                                          (yb0 + 0.1, zc - 0.03)], depth=0.1, slats=3)
        surf = K.Surface([body])
    if "gills" in feats:
        y = AX[0] - ARCH - 0.08
        side_opening(surf, body, m, out, [(y - 0.3, RIDE + 0.36), (y, RIDE + 0.36), (y, RIDE + 0.46), (y - 0.26, RIDE + 0.46)],
                     depth=0.04, slats=2)
        surf = K.Surface([body])
    if "vents_front" in feats:
        y = AX[0] - ARCH - 0.06
        side_opening(surf, body, m, out, [(y - 0.22, RIDE + 0.48), (y, RIDE + 0.5), (y, RIDE + 0.56), (y - 0.2, RIDE + 0.55)],
                     depth=0.03, slats=1)
        surf = K.Surface([body])
    if "bonnet_bulge" in feats:
        bulge(surf, m, out, [(-0.3, K.Y_COWL + 0.05), (0.3, K.Y_COWL + 0.05), (0.26, YF - 0.35), (-0.26, YF - 0.35)], 0.055)
        out.append(box("scoop_mouth", (0.36, 0.01, 0.035), (0, YF - 0.36, K.smooth(K.DECK, YF - 0.36) + 0.03), m["liner"]))
    if "stripes" in feats:
        for x0 in (-0.26, 0.08):
            stripe(surf, m, out, x0, x0 + 0.18, YR + 0.05, YF - 0.03)
    if "side_stripe" in feats:
        for sd in (1, -1):
            g = K.patch(surf, "side", K.poly_fn([(AX[1] - 0.2, K.SILL_Z + 0.05), (AX[0] + 0.25, K.SILL_Z + 0.05),
                                                 (AX[0] + 0.25, K.SILL_Z + 0.13), (AX[1] - 0.2, K.SILL_Z + 0.13)]), 24, 1, sd)
            out.append(K.sheet("stripe", g, 0.0022, m["paint2"]))
    if "flares" in feats:
        for ay in AX:
            for sx in (1, -1):
                pts = []
                for i in range(15):
                    a = math.radians(-8 + 196 * i / 14)
                    pts.append(V((sx * (W2 + 0.012), ay + math.cos(a) * (ARCH + 0.03), WR + math.sin(a) * (ARCH + 0.03))))
                out.append(K.tube_path("flare", pts, 0.035 if kind in ("pickup", "box4x4") else 0.022,
                                       m["cladding" if kind in ("pickup", "box4x4", "hatch") else "paint"], 8))
    if "mudflaps" in feats:
        for ay in AX:
            for sx in (1, -1):
                out.append(box("mudflap", (0.22, 0.012, 0.2), (sx * (W2 - 0.14), ay - ARCH - 0.02, RIDE + 0.08),
                               m["rubber"]))
    if "light_pod" in feats:
        h = surf.cast(*K.ray("front", 0.0, zl - 0.15))
        if h:
            for i in range(4):
                x = -0.36 + i * 0.24
                c = cyl("spot", 0.075, 0.07, (0, 0, 0), m["trim"], 16)
                c.rotation_euler = (-math.pi / 2, 0, 0)
                c.location = (x, h[0].y + 0.1, zl - 0.15)
                out.append(c)
                c = cyl("spot_lens", 0.064, 0.01, (0, 0, 0), m["head"], 16)
                c.rotation_euler = (-math.pi / 2, 0, 0)
                c.location = (x, h[0].y + 0.17, zl - 0.15)
                out.append(c)
            out.append(box("pod_bar", (1.0, 0.04, 0.04), (0, h[0].y + 0.06, zl - 0.15), m["trim"]))
    if "light_bar_roof" in feats:
        y = K.Y_WS - 0.12
        z = roof_at(y)
        out.append(box("lightbar", (1.3, 0.12, 0.09), (0, y, z + 0.06), m["trim"], bevel=0.02))
        out.append(box("lightbar_lens", (1.24, 0.01, 0.06), (0, y + 0.062, z + 0.06), m["head"]))
    if "bull_bar" in feats:
        h = surf.cast(*K.ray("front", 0.0, RIDE + 0.45))
        yy = (h[0].y if h else YF) + 0.1
        for sx in (1, -1):
            out.append(K.tube_path("bar_up", [V((sx * 0.42, yy, RIDE + 0.2)), V((sx * 0.42, yy + 0.02, RIDE + 0.78)),
                                              V((sx * 0.3, yy - 0.04, RIDE + 0.9))], 0.035, m["trim"], 10))
        out.append(K.tube_path("bar_x", [V((-0.6, yy, RIDE + 0.32)), V((0.6, yy, RIDE + 0.32))], 0.04, m["trim"], 10))
        out.append(box("skid", (0.8, 0.22, 0.02), (0, yy - 0.2, RIDE + 0.08), m["trim"], bevel=0.006))
    if "roof_rack" in feats:
        y0, y1 = K.Y_WS - 0.1, K.Y_RE + 0.1
        z = roof_at((y0 + y1) / 2) + 0.08
        rx = K.ring((y0 + y1) / 2)[2].x - 0.02
        for sx in (1, -1):
            out.append(K.tube_path("rack_side", [V((sx * rx, y0, z)), V((sx * rx, y1, z))], 0.018, m["trim"], 8))
        for i in range(7):
            y = y0 + (y1 - y0) * i / 6
            out.append(K.tube_path("rack_x", [V((-rx, y, z)), V((rx, y, z))], 0.014, m["trim"], 6))
            if i % 3 == 0:
                for sx in (1, -1):
                    out.append(box("rack_leg", (0.03, 0.05, 0.1), (sx * rx, y, z - 0.05), m["trim"]))
        out.append(box("rack_lamps", (0.9, 0.08, 0.08), (0, y0 + 0.04, z + 0.06), m["trim"], bevel=0.01))
        for i in range(4):
            c = cyl("lamp", 0.05, 0.01, (0, 0, 0), m["head"], 12)
            c.rotation_euler = (-math.pi / 2, 0, 0)
            c.location = (-0.33 + i * 0.22, y0 + 0.085, z + 0.06)
            out.append(c)
    if "spare" in feats:
        # Spare on the side-hinged tailgate: a real tyre (rounded shoulders,
        # tread blocks), a domed paint cover with a chrome ring and badge,
        # on a black carrier bracket.
        yc, zc, rr = YR - 0.14, RIDE + 0.8, WR * 0.98
        bm = bmesh.new()
        prof = [(0.66, 0.11), (0.86, 0.125), (0.97, 0.1), (1.0, 0.06), (1.0, -0.06), (0.97, -0.1), (0.86, -0.125), (0.66, -0.11)]
        segs = 36
        rings = [[bm.verts.new((math.cos(a) * rr * pr, yc + px, zc + math.sin(a) * rr * pr)) for pr, px in prof]
                 for a in (i * 2 * math.pi / segs for i in range(segs))]
        for i in range(segs):
            r0, r1 = rings[i], rings[(i + 1) % segs]
            for k in range(len(prof) - 1):
                bm.faces.new((r0[k], r0[k + 1], r1[k + 1], r1[k]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        ty = kit.new_obj("spare", bm, m["rubber"])
        for f in ty.data.polygons:
            f.use_smooth = True
        out.append(ty)
        for i in range(18):
            a = i * 2 * math.pi / 18
            lug = box("spare_lug", (0.07, 0.2, 0.03), (0, 0, 0), m["rubber"], bevel=0.008)
            lug.rotation_euler = (0, -a, 0)
            lug.location = (math.cos(a) * rr * 0.995, yc, zc + math.sin(a) * rr * 0.995)
            out.append(lug)
        bm = bmesh.new()
        prof = [(0.0, -0.17), (0.4, -0.165), (0.75, -0.15), (0.82, -0.12)]
        cr = [[bm.verts.new((math.cos(a) * rr * pr, yc + py, zc + math.sin(a) * rr * pr)) for pr, py in prof]
              for a in (i * 2 * math.pi / segs for i in range(segs))]
        for i in range(segs):
            r0, r1 = cr[i], cr[(i + 1) % segs]
            for k in range(len(prof) - 1):
                bm.faces.new((r0[k], r0[k + 1], r1[k + 1], r1[k]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        cv = kit.new_obj("spare_cover", bm, m["paint"])
        for f in cv.data.polygons:
            f.use_smooth = True
        out.append(cv)
        out.append(K.tube_path("spare_ring", [V((math.cos(a) * rr * 0.8, yc - 0.13, zc + math.sin(a) * rr * 0.8))
                                              for a in (i * 2 * math.pi / 36 for i in range(37))], 0.012, m["chrome"], 6))
        out.append(K.disc_on("spare_badge", V((0, yc - 0.172, zc)), V((0, -1, 0)), 0.06, 0.006, m["chrome"], 24))
        out.append(box("carrier", (0.5, 0.1, 0.06), (0, YR + 0.0, zc), m["trim"], bevel=0.01))
    if "steps" in feats:
        for sx in (1, -1):
            out.append(box("step", (0.14, AX[0] - AX[1] - 2 * ARCH - 0.1, 0.035),
                           (sx * (W2 - 0.03), (AX[0] + AX[1]) / 2, RIDE - 0.02), m["trim"], bevel=0.01))
    if "armour" in feats:
        for sd in (1, -1):
            g = K.patch(surf, "side", K.poly_fn([(AX[1] + ARCH + 0.06, RIDE + 0.05), (AX[0] - ARCH - 0.06, RIDE + 0.05),
                                                 (AX[0] - ARCH - 0.06, K.SILL_Z + 0.08), (AX[1] + ARCH + 0.06, K.SILL_Z + 0.08)]),
                        12, 2, sd)
            out.append(K.sheet("armour", g, 0.004, m["cladding"], thick=0.03))
    if "tow" in feats:
        # Step bumper across the tail and a receiver hitch under it.
        out.append(box("step_bumper", (2 * W2 - 0.12, 0.16, 0.13), (0, YR + 0.02, RIDE + 0.2), m["chrome"], bevel=0.03, segs=3))
        out.append(box("step_pad", (0.5, 0.05, 0.012), (0, YR + 0.02, RIDE + 0.272), m["rubber"]))
        out.append(box("tow", (0.07, 0.22, 0.07), (0, YR - 0.1, RIDE + 0.06), m["trim"], bevel=0.008))
        out.append(box("gate_handle", (0.22, 0.03, 0.05), (0, YR + 0.005, rear - 0.07), m["trim"], bevel=0.01))
    if "lightbar" in feats or "lightbar_low" in feats:
        police_lightbar(m, out, K.Y_WS - 0.32, roof_at(K.Y_WS - 0.32), low="lightbar_low" in feats)
    if "livery_doors" in feats:
        # Two-tone: the doors in the second colour, as a real patrol car.
        y0, y1 = AX[1] + ARCH + 0.06, AX[0] - ARCH - 0.06
        z0, z1 = K.SILL_Z + 0.02, K.smooth(K.CREASE, (y0 + y1) / 2) - 0.03
        for sd in (1, -1):
            g = K.patch(gs, "side", K.poly_fn([(y0, z0), (y1, z0), (y1, z1), (y0, z1)]), 24, 5, sd)
            out.append(K.sheet("livery", g, 0.0024, m["paint2"]))
    if "battenburg" in feats:
        F.livery(gs, m, out, AX[1] + ARCH + 0.04, AX[0] - ARCH - 0.04, K.SILL_Z + 0.03,
                 K.smooth(K.CREASE, 0.0) - 0.05, ["paint2", "paint"], rows=2, cell=0.2)
    if "police_text" in feats:
        yt = (AX[0] + AX[1]) / 2 + 0.05
        zt = K.smooth(K.CREASE, yt) - (0.17 if "battenburg" not in feats else 0.0) + (0.035 if "battenburg" in feats else 0.0)
        for sd in (1, -1):
            h = gs.cast(V((sd * 3.0, yt, zt)), V((-sd, 0, 0)))
            if h:
                R.script(out, {"chrome": m["paint" if "battenburg" not in feats else "paint2"]}, "POLICE", h[0] + h[1] * 0.002,
                         h[1], size=0.12 if "battenburg" not in feats else 0.075)
    if "push_bar" in feats:
        h = surf.cast(*K.ray("front", 0.0, RIDE + 0.3))
        yy = (h[0].y if h else YF) + 0.06
        for sx in (1, -1):
            out.append(K.tube_path("push_up", [V((sx * 0.36, yy - 0.08, RIDE + 0.12)), V((sx * 0.36, yy, RIDE + 0.2)),
                                               V((sx * 0.36, yy, RIDE + 0.55)), V((sx * 0.3, yy - 0.06, RIDE + 0.64))],
                                   0.026, m["trim"], 8))
            out.append(box("push_pad", (0.06, 0.03, 0.3), (sx * 0.36, yy + 0.028, RIDE + 0.38), m["rubber"], bevel=0.01))
        for z in (RIDE + 0.26, RIDE + 0.5):
            out.append(K.tube_path("push_x", [V((-0.36, yy, z)), V((0.36, yy, z))], 0.022, m["trim"], 8))
    if "grille_strobes" in feats:
        h = surf.cast(*K.ray("front", W2 * 0.3, zl - 0.07))
        if h:
            for sx in (1, -1):
                st = box("strobe", (0.07, 0.012, 0.022), h[0] + h[1] * 0.006, m["beacon_blue"], bevel=0.004)
                st.location.x = sx * abs(h[0].x)
                out.append(st)
    if "spot_lamp" in feats:
        y = K.Y_COWL - 0.12
        r_ = K.ring(y)
        p0 = V((r_[4].x + 0.02, y, r_[4].y + 0.05))
        out.append(K.tube_path("spot_post", [p0, p0 + V((0.03, 0.0, 0.12))], 0.012, m["chrome"], 6))
        sp = cyl("spot", 0.055, 0.12, (0, 0, 0), m["chrome"], 16)
        sp.rotation_euler = (-math.pi / 2, 0, 0)
        sp.location = p0 + V((0.03, -0.06, 0.15))
        out.append(sp)
        out.append(K.disc_on("spot_lens", p0 + V((0.03, 0.065, 0.15)), V((0, 1, 0)), 0.048, 0.004, m["head"], 16))
    # Door handles: flush pull handles at the trailing edge of every door,
    # just under the shoulder (one shape on every car).
    hys = []
    if doors == 0:
        pass
    elif doors == 4:
        hys = [ymid - 0.14, arc_r[0][0] + 0.02] if kind != "pickup" else [ymid - 0.14, K.Y_TG - 0.12]
    elif doors == 2:
        hys = [yd1 - 0.14]
    else:
        hys = [yd1 - 0.1]
    for y in hys:
        z = K.smooth(K.CREASE, y) - (0.07 if kind not in ("pickup", "box4x4", "van", "box") else 0.12)
        for sx in (1, -1):
            h = surf.cast(V((sx * 3.0, y, z)), V((-sx, 0, 0)))
            if not h:
                continue
            p, n = h[0], h[1]
            out.append(box("handle_recess", (0.008, 0.2, 0.05), p - n * 0.003, m["liner"]))
            out.append(box("handle", (0.022, 0.19, 0.03), p + n * 0.007, m["paint"] if doors > 1 else m["trim"], bevel=0.01))
    if "sliding_door" in feats:
        yb = AX[0] - ARCH - 0.75
        F.gap_decal(gs, m, out, [(yb - 1.25, K.SILL_Z + 0.02), (yb - 1.25, K.ROOF - 0.25)], "side", side=0)
        for sd in (1, -1):
            g = K.patch(surf, "side", K.poly_fn([(yb - 1.2, K.ROOF - 0.32), (yb - 0.05, K.ROOF - 0.32), (yb - 0.05, K.ROOF - 0.3),
                                                 (yb - 1.2, K.ROOF - 0.3)]), 12, 1, sd)
            out.append(K.sheet("slide_rail", g, 0.006, m["trim"], thick=0.012))
        F.gap_decal(gs, m, out, [(0.0, RIDE + 0.3), (0.0, K.ROOF - 0.1)], "rear")
    if "roof_bars" in feats:
        for y in (K.Y_WS - 0.3, (K.Y_WS + YR) / 2, YR + 0.4):
            z = roof_at(y)
            out.append(box("roof_bar", (2 * W2 - 0.3, 0.05, 0.035), (0, y, z + 0.06), m["trim"], bevel=0.01))
            for sx in (1, -1):
                out.append(box("bar_foot", (0.06, 0.08, 0.06), (sx * (W2 - 0.2), y, z + 0.02), m["plastic"]))
    if "skirts_plastic" in feats:
        for sd in (1, -1):
            g = K.patch(surf, "side", K.poly_fn([(AX[1] + ARCH + 0.04, RIDE + 0.05), (AX[0] - ARCH - 0.04, RIDE + 0.05),
                                                 (AX[0] - ARCH - 0.04, K.SILL_Z), (AX[1] + ARCH + 0.04, K.SILL_Z)]), 12, 2, sd)
            out.append(K.sheet("skirt", g, 0.002, m["cladding"], thick=0.012))
    if "steps_rear" in feats:
        out.append(box("rear_step", (1.0, 0.18, 0.05), (0, YR + 0.02, RIDE + 0.12), m["cladding"], bevel=0.01))
    if "cargo_box" in feats:
        cargo_box(spec, m, out)
    if "fins" in feats:
        for sx in (1, -1):
            y0 = K.Y_RE - 0.2
            pts = [V((sx * (K.ring(y)[2].x - 0.03), y, K.smooth(K.DECK, y) + K.cabin_h(y) + 0.0)) for y in
                   [y0 - (y0 - (YR + 0.3)) * i / 8 for i in range(9)]]
            for p in pts:
                p.z += 0.0
            out.append(K.tube_path("fin", pts, 0.012, m["carbon"], 6))
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
    print("CAR", name, "tris", tris, "materials", len(ob.data.materials))
    return {"L": round(YF - YR, 3), "W": round(2 * W2, 3), "roof": K.ROOF, "wb": K.WB, "wheel_r": WR, "ride": RIDE,
            "tyre_w": K.TYRE_W, "axles": [AX[0], AX[1]], "wheel": spec["wheel"]}


# ------------------------------------------------------------------ wheels
WHEELS = {
    # name: rim radius (of the tyre's 1.0), spokes, style, tread
    "multi": (0.74, 10, "twin", "road"),     # sport saloon: 10 twin spokes
    "rally": (0.68, 6, "turbine", "road"),   # rally: white 6-spoke
    "dish": (0.7, 5, "dish", "road"),        # muscle: deep-dish 5-spoke
    "y5": (0.76, 5, "y", "road"),            # coupe: 5 Y-spokes
    "center": (0.78, 10, "center", "road"),  # supercar: centre-lock, 10 slim spokes
    "offroad": (0.6, 8, "beadlock", "mud"),  # 4x4: beadlock, chunky tread
    "steel": (0.64, 8, "steel", "road"),     # van / truck: painted steel with round holes
}


def build_wheel(name):
    R, n, style, tread = WHEELS[name]
    kit.reset()
    m = K.mats()
    rim = kit.mat("rim", (0.78, 0.79, 0.81), 0.28, 1.0)
    rim_dark = kit.mat("rim_dark", (0.12, 0.12, 0.13), 0.35, 0.8)
    tyre = kit.mat("tyre", (0.03, 0.03, 0.03), 0.88)
    wall = kit.mat("tyre_wall", (0.05, 0.05, 0.052), 0.8)
    disc_m = kit.mat("disc", (0.36, 0.36, 0.37), 0.42, 0.85)
    face = rim if style != "beadlock" else rim_dark
    if style == "turbine":
        face = kit.mat("paint2", (0.92, 0.92, 0.9), 0.35)
    parts = []
    # Tyre: bead -> sidewall -> shoulder -> tread (grooves or blocks).
    sw = [(R - 0.01, -0.42), (R + (1 - R) * 0.35, -0.45), (R + (1 - R) * 0.75, -0.44), (0.985, -0.38), (1.0, -0.32)]
    if tread == "road":
        tr = [(1.0, -0.2), (0.975, -0.195), (0.975, -0.155), (1.0, -0.15), (1.0, -0.03), (0.975, -0.025), (0.975, 0.025),
              (1.0, 0.03), (1.0, 0.15), (0.975, 0.155), (0.975, 0.195), (1.0, 0.2)]
    else:
        tr = [(1.0, -0.25), (1.0, 0.25)]
    prof = sw + tr + [(x[0], -x[1]) for x in reversed(sw)]
    segs = 36 if tread == "road" else 32
    bm = bmesh.new()
    rings = [[bm.verts.new((x * 0.5, r * math.cos(a), r * math.sin(a))) for r, x in prof]
             for a in (i * 2 * math.pi / segs for i in range(segs))]
    for i in range(segs):
        r0, r1 = rings[i], rings[(i + 1) % segs]
        for k in range(len(prof) - 1):
            bm.faces.new((r0[k], r0[k + 1], r1[k + 1], r1[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    t = kit.new_obj("tyre", bm, tyre)
    t.data.materials.append(wall)
    for p in t.data.polygons:
        p.use_smooth = True
        if math.hypot(p.center.y, p.center.z) < 0.93:
            p.material_index = 1
    parts.append(t)
    if tread == "mud":
        # Staggered tread blocks round the crown and over the shoulders.
        for i in range(24):
            a = i * 2 * math.pi / 24
            for k, (x, wdt) in enumerate(((-0.17, 0.14), (0.02, 0.14), (0.19, 0.12))):
                xx = x + (0.05 if i % 2 else -0.05)
                b = box("lug", (wdt * 0.5, 0.15, 0.07), (0, 0, 0), tyre)
                b.rotation_euler = (a - math.pi / 2, 0, 0)
                b.location = (xx * 0.5 / 0.25 * 0.25, 1.0 * math.cos(a), 1.0 * math.sin(a))
                parts.append(b)
    # Barrel, lip, well, disc and hat.
    c = cyl("barrel", R * 0.97, 0.36, (0, 0, 0), m["liner"], 40, cap=False)
    c.rotation_euler = (0, math.pi / 2, 0)
    c.location = (-0.18, 0, 0)
    parts.append(c)
    lipd = 0.2 if style != "dish" else 0.21
    bm = bmesh.new()
    lip = [[bm.verts.new((x, r * math.cos(a), r * math.sin(a))) for r, x in
            ((R * 0.88, lipd - 0.03), (R * 0.97, lipd), (R * 1.0, lipd - 0.005), (R * 1.0, lipd - 0.03))]
           for a in (i * 2 * math.pi / 48 for i in range(48))]
    for i in range(48):
        a0, a1 = lip[i], lip[(i + 1) % 48]
        for k in range(3):
            bm.faces.new((a0[k], a0[k + 1], a1[k + 1], a1[k]))
    lo = kit.new_obj("lip", bm, rim if style != "center" else rim_dark)
    for p in lo.data.polygons:
        p.use_smooth = True
    parts.append(lo)
    c = cyl("well", R * 0.95, 0.01, (0, 0, 0), m["liner"], 40)
    c.rotation_euler = (0, math.pi / 2, 0)
    c.location = (-0.12, 0, 0)
    parts.append(c)
    dr = R * (0.86 if style in ("center", "y", "twin") else 0.78)
    c = cyl("disc", dr, 0.06, (0, 0, 0), disc_m, 44)
    c.rotation_euler = (0, math.pi / 2, 0)
    c.location = (-0.08, 0, 0)
    parts.append(c)
    # Ventilated brake rotor slots / drilled cooling holes & machined centre-cap bezel.
    if style in ("center", "y", "twin", "dish"):
        for i in range(24):
            a = i * 2 * math.pi / 24
            for rr in (dr * 0.70, dr * 0.85):
                h = cyl("hole", 0.013, 0.006, (0, 0, 0), m["liner"], 6)
                h.rotation_euler = (0, math.pi / 2, 0)
                h.location = (-0.017, rr * math.cos(a + rr * 3), rr * math.sin(a + rr * 3))
                parts.append(h)
    # Rim lip valve stem + metallic centre-cap accent ring.
    vs = cyl("valve", 0.011, 0.045, (0, 0, 0), m["chrome"], 8)
    vs.location = (lipd - 0.025, 0, R * 0.90)
    parts.append(vs)
    cap_ring = cyl("cap_ring", R * 0.17, 0.018, (0, 0, 0), m["chrome"], 20)
    cap_ring.rotation_euler = (0, math.pi / 2, 0)
    cap_ring.location = (0.14 if style != "dish" else 0.07, 0, 0)
    parts.append(cap_ring)
    c = cyl("hat", R * 0.36, 0.05, (0, 0, 0), rim_dark, 24)
    c.rotation_euler = (0, math.pi / 2, 0)
    c.location = (-0.03, 0, 0)
    parts.append(c)

    def spoke(a, r0, r1, w0, w1, x0, x1, th=0.04, mat=face):
        bm = bmesh.new()
        ca, sa = math.cos(a), math.sin(a)
        tang = V((0, -sa, ca))
        qs = []
        for r, x, w in ((r0, x0, w0), ((r0 + r1) / 2, (x0 + x1) / 2 + 0.01, (w0 + w1) / 2), (r1, x1, w1)):
            c = V((x, r * ca, r * sa))
            qs.append([c + tang * (w / 2), c - tang * (w / 2), c - tang * (w / 2) - V((th, 0, 0)),
                       c + tang * (w / 2) - V((th, 0, 0))])
        vs = [[bm.verts.new(p) for p in q] for q in qs]
        for q0, q1 in zip(vs, vs[1:]):
            for i in range(4):
                bm.faces.new((q0[i], q0[(i + 1) % 4], q1[(i + 1) % 4], q1[i]))
        bm.faces.new(vs[0])
        bm.faces.new(list(reversed(vs[-1])))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return kit.new_obj("spoke", bm, mat)

    hub_r = R * 0.28
    if style == "twin":
        for k in range(n // 2):
            for off in (-0.1, 0.1):
                parts.append(spoke(k * 2 * math.pi / (n // 2) + off, hub_r, R * 0.93, 0.05, 0.045, 0.12, 0.185))
    elif style == "y":
        for k in range(n):
            a = k * 2 * math.pi / n
            parts.append(spoke(a, hub_r, R * 0.55, 0.075, 0.06, 0.13, 0.16))
            for off in (-0.2, 0.2):
                parts.append(spoke(a + off * 0.6, R * 0.5, R * 0.94, 0.045, 0.035, 0.16, 0.19))
    elif style == "center":
        for k in range(n):
            parts.append(spoke(k * 2 * math.pi / n + 0.05, hub_r * 0.8, R * 0.95, 0.04, 0.03, 0.12, 0.19, th=0.035))
    elif style == "dish":
        # Deep dish: spokes sit far back, a wide polished step out to the lip.
        for k in range(n):
            parts.append(spoke(k * 2 * math.pi / n, hub_r, R * 0.82, 0.12, 0.1, 0.02, 0.05, th=0.04))
        bm = bmesh.new()
        st = [[bm.verts.new((x, r * math.cos(a), r * math.sin(a))) for r, x in
               ((R * 0.8, 0.04), (R * 0.84, 0.05), (R * 0.9, 0.17), (R * 0.95, 0.18))]
              for a in (i * 2 * math.pi / 48 for i in range(48))]
        for i in range(48):
            a0, a1 = st[i], st[(i + 1) % 48]
            for k in range(3):
                bm.faces.new((a0[k], a0[k + 1], a1[k + 1], a1[k]))
        dd = kit.new_obj("dish", bm, m["chrome"])
        for p in dd.data.polygons:
            p.use_smooth = True
        parts.append(dd)
    elif style == "turbine":
        for k in range(n):
            parts.append(spoke(k * 2 * math.pi / n, hub_r, R * 0.93, 0.13, 0.17, 0.12, 0.17, th=0.035))
    elif style == "steel":
        # Dished steel disc with eight round vents.
        bm = bmesh.new()
        st = [[bm.verts.new((x, r * math.cos(a), r * math.sin(a))) for r, x in
               ((hub_r, 0.1), (R * 0.45, 0.1), (R * 0.6, 0.13), (R * 0.85, 0.12), (R * 0.95, 0.17))]
              for a in (i * 2 * math.pi / 40 for i in range(40))]
        for i in range(40):
            a0, a1 = st[i], st[(i + 1) % 40]
            for k in range(4):
                bm.faces.new((a0[k], a0[k + 1], a1[k + 1], a1[k]))
        sd_ = kit.new_obj("steel_disc", bm, rim)
        for p in sd_.data.polygons:
            p.use_smooth = True
        parts.append(sd_)
        for k in range(n):
            a = k * 2 * math.pi / n
            h = cyl("vent", R * 0.09, 0.01, (0, 0, 0), m["liner"], 12)
            h.rotation_euler = (0, math.pi / 2, 0)
            h.location = (0.128, R * 0.72 * math.cos(a), R * 0.72 * math.sin(a))
            parts.append(h)
    elif style == "beadlock":
        for k in range(n):
            parts.append(spoke(k * 2 * math.pi / n, hub_r, R * 0.86, 0.1, 0.12, 0.1, 0.13, th=0.05))
        bl = cyl("beadlock", R * 1.01, 0.04, (0, 0, 0), rim_dark, 40, r2=R * 1.01, cap=False)
        bl.rotation_euler = (0, math.pi / 2, 0)
        bl.location = (0.17, 0, 0)
        parts.append(bl)
        for i in range(20):
            a = i * 2 * math.pi / 20
            b = cyl("bolt", 0.014, 0.02, (0, 0, 0), m["chrome"], 6)
            b.rotation_euler = (0, math.pi / 2, 0)
            b.location = (0.21, R * 0.96 * math.cos(a), R * 0.96 * math.sin(a))
            parts.append(b)
    hub = cyl("hub", hub_r, 0.05, (0, 0, 0), face, 30)
    hub.rotation_euler = (0, math.pi / 2, 0)
    hub.location = (0.09 if style != "dish" else 0.0, 0, 0)
    parts.append(hub)
    if style == "center":
        nut = cyl("centre_nut", hub_r * 0.55, 0.06, (0, 0, 0), kit.mat("caliper", (0.75, 0.08, 0.05), 0.35), 6)
        nut.rotation_euler = (0, math.pi / 2, 0)
        nut.location = (0.12, 0, 0)
        parts.append(nut)
    else:
        nn = 5 if style != "beadlock" else 6
        for k in range(nn):
            a = k * 2 * math.pi / nn + math.pi / nn
            nut = cyl("nut", 0.026, 0.035, (0, 0, 0), m["chrome"], 6)
            nut.rotation_euler = (0, math.pi / 2, 0)
            nut.location = ((0.12 if style != "dish" else 0.03), hub_r * 0.62 * math.cos(a), hub_r * 0.62 * math.sin(a))
            parts.append(nut)
        cap = cyl("cap", hub_r * 0.38, 0.02, (0, 0, 0), rim_dark, 24)
        cap.rotation_euler = (0, math.pi / 2, 0)
        cap.location = ((0.13 if style != "dish" else 0.04), 0, 0)
        parts.append(cap)
    ob = kit.join("wheel", parts)
    kit.export("wheel_%s.glb" % name, [ob])
    print("WHEEL", name, "tris", sum(len(p.vertices) - 2 for p in ob.data.polygons))


if __name__ == "__main__":
    jpath = os.path.join(OUT, "bodies.json")
    dims = json.load(open(jpath)) if os.path.exists(jpath) else {}
    for name in CARS:
        if ONLY and name not in ONLY:
            continue
        dims[name] = build_car(name)
    for w in WHEELS:
        if not ONLY or "wheel_" + w in ONLY or "wheels" in ONLY:
            build_wheel(w)
    with open(jpath, "w") as f:
        json.dump(dims, f, indent=1, sort_keys=True)
    with open(os.path.join(OUT, "body_dims.gd"), "w") as f:
        f.write("class_name BodyDims\nextends RefCounted\n## Generated by tools/blender/build_vehicles.py (Never Stop),\n"
                "## tools/blender/kestrel.py, ws_fleet.py and ws_cars.py (City Empire): real body dimensions (m). Do not edit.\n\n")
        f.write("const DIMS := " + json.dumps(dims, indent="\t", sort_keys=True) + "\n")
    print("CARS DONE")
