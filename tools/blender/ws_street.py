"""WorldState street furniture (replaces build_street.py / build_kit.py's
blocky versions: same file names, footprints, facings and material roles, so
placement, collision, night lighting (CityWorld.LAMP_HEAD) and the per-chunk
merge (vertex colours from material colours) all still fit).

Run:  blender -b --factory-startup --python tools/blender/ws_street.py -- <out dir> [names,...]

Modelled after real UK street furniture: a tapered galvanised lighting
column with a base door and a curved bracket to a slim LED lantern; a
cantilever traffic signal with backboards and hooded aspects and a
pedestrian push-button unit; a cast-iron-ended bench with timber slats; a
litter bin with a domed lid and plinth; a flared cast-iron bollard with
collars; a pillar hydrant; a framed street-name plate; a glazed bus shelter
with a canopy, framed glass, an illuminated ad panel, perch seat and a bus
stop flag; a stone planter with a layered shrub. A few hundred triangles
each (the furniture is merged per chunk and drawn within 190 m).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector as V

sys.path.insert(0, os.path.dirname(__file__))
import build_kit as kit  # noqa: E402
from build_kit import box, cyl, sphere, join, mat, reset  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "assets/models"
ONLY = set(ARGS[1].split(",")) if len(ARGS) > 1 and ARGS[1] else set()
kit.OUT = OUT


def export(name, parts):
    ob = join(name, [p for p in parts if p is not None])
    for poly in ob.data.polygons:
        poly.use_smooth = False
    kit.export(name + ".glb", [ob])
    print("STREET", name, sum(len(p.vertices) - 2 for p in ob.data.polygons), "tris")


def tube(name, pts, r, material, segs=8):
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        a = V(pts[max(i - 1, 0)]); b = V(pts[min(i + 1, len(pts) - 1)])
        t = (b - a).normalized()
        up = V((0, 0, 1)) if abs(t.z) < 0.95 else V((1, 0, 0))
        u = t.cross(up).normalized(); w = t.cross(u).normalized()
        rings.append([bm.verts.new(V(p) + (u * math.cos(k * 2 * math.pi / segs) + w * math.sin(k * 2 * math.pi / segs)) * r)
                      for k in range(segs)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]))
    bm.faces.new(list(reversed(rings[0]))); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit.new_obj(name, bm, material)


def lathe(name, prof, material, segs=12, z0=0.0):
    """Surface of revolution about Z: prof = [(r, z)...] bottom to top."""
    bm = bmesh.new()
    rings = [[bm.verts.new((r * math.cos(k * 2 * math.pi / segs), r * math.sin(k * 2 * math.pi / segs), z + z0))
              for k in range(segs)] for r, z in prof]
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]))
    if prof[0][0] > 0.001:
        bm.faces.new(list(reversed(rings[0])))
    if prof[-1][0] > 0.001:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit.new_obj(name, bm, material)


def M():
    return {
        "galv": mat("galvanised", (0.5, 0.52, 0.52), 0.55, 0.7),
        "iron": mat("iron", (0.07, 0.08, 0.08), 0.45, 0.6),
        "wood": mat("wood", (0.5, 0.34, 0.2), 0.8),
        "steel": mat("steel", (0.62, 0.63, 0.64), 0.35, 0.8),
        "red": mat("hydrant_red", (0.72, 0.12, 0.08), 0.5),
        "yellow": mat("hydrant_yellow", (0.92, 0.72, 0.1), 0.5),
        "green": mat("bin_green", (0.06, 0.2, 0.14), 0.45),
        "gold": mat("gold", (0.75, 0.6, 0.25), 0.35, 0.8),
        "white": mat("sign_white", (0.94, 0.94, 0.91), 0.6),
        "black": mat("sign_black", (0.04, 0.04, 0.045), 0.6),
        "glass": mat("shelter_glass", (0.58, 0.68, 0.72), 0.1),
        "stone": mat("planter_stone", (0.66, 0.64, 0.6), 0.9),
        "stone_dk": mat("planter_stone_dark", (0.5, 0.48, 0.45), 0.9),
        "leaf": mat("leaves", (0.28, 0.44, 0.2), 0.85),
        "leaf2": mat("leaves_light", (0.4, 0.56, 0.26), 0.85),
        "soil": mat("soil", (0.18, 0.13, 0.09), 0.95),
        "ad": mat("shelter_ad", (0.95, 0.78, 0.4), 0.5, 0.0, emit=(0.5, 0.42, 0.25)),
        "red_sign": mat("bus_red", (0.75, 0.1, 0.08), 0.5),
        "blue": mat("sign_blue", (0.08, 0.2, 0.55), 0.5),
    }


# ------------------------------------------------------------------ lighting
def streetlight():
    """7 m column, lantern 1.45 m out along +Y (Godot -Z) at 6.72-6.9 m."""
    reset()
    m = M()
    lamp = mat("lamp", (1.0, 0.93, 0.78), 0.3, 0.0, emit=(1.0, 0.86, 0.62))
    p = [lathe("column", [(0.13, 0.0), (0.13, 0.62), (0.115, 0.66), (0.095, 0.7), (0.07, 6.6), (0.065, 6.86)], m["galv"], 8)]
    p.append(box("door", (0.1, 0.012, 0.32), (0, 0.13, 0.32), m["galv"]))
    p.append(box("door_lock", (0.02, 0.016, 0.02), (0.03, 0.135, 0.38), m["iron"]))
    # Bracket: a curve out and slightly up, a thin tie under it.
    br = [(0, 0, 6.6), (0, 0.25, 6.82), (0, 0.65, 6.93), (0, 1.1, 6.95)]
    p.append(tube("bracket", br, 0.04, m["galv"], 6))
    p.append(tube("tie", [(0, 0.04, 6.35), (0, 0.55, 6.86)], 0.014, m["galv"], 5))
    # Lantern: slim tapered housing, flat LED panel under it (the glow material).
    bm = bmesh.new()
    prof = [(1.08, 0.12, 0.04), (1.25, 0.17, 0.07), (1.65, 0.17, 0.065), (1.83, 0.12, 0.035)]
    rings = []
    for y, w, h in prof:
        rings.append([bm.verts.new(v) for v in ((-w, y, 6.86), (w, y, 6.86), (w, y, 6.86 + h), (-w, y, 6.86 + h))])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(4):
            bm.faces.new((r0[k], r0[(k + 1) % 4], r1[(k + 1) % 4], r1[k]))
    bm.faces.new(list(reversed(rings[0]))); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    p.append(kit.new_obj("lantern", bm, m["galv"]))
    p.append(box("glow", (0.26, 0.6, 0.012), (0, 1.45, 6.85), lamp))
    export("streetlight", p)


def traffic_light():
    """Cantilever signal: pole on the kerb, mast arm out over the road (+X),
    two signal heads (backboards, three hooded aspects), a pole-mounted head
    for pedestrians and a push-button unit."""
    reset()
    m = M()
    head_m = mat("signal_head", (0.05, 0.05, 0.05), 0.55)
    red = mat("lamp_red", (0.9, 0.1, 0.05), 0.3, emit=(1.0, 0.12, 0.05))
    amber = mat("lamp_amber", (0.3, 0.22, 0.05), 0.3)
    green = mat("lamp_green", (0.05, 0.25, 0.1), 0.3)
    p = [lathe("pole", [(0.2, 0.0), (0.2, 0.55), (0.13, 0.6), (0.12, 6.2), (0.08, 6.25)], m["galv"], 10)]
    p.append(tube("arm", [(0, 0, 5.9), (2.0, 0, 5.95), (5.3, 0, 6.0)], 0.075, m["galv"], 8))
    p.append(tube("arm_tie", [(0, 0, 5.2), (2.4, 0, 5.92)], 0.03, m["galv"], 6))

    def signal(x, y, z, face=-1):
        out = []
        out.append(box("backboard", (0.62, 0.02, 1.25), (x, y + 0.13 * -face, z), m["black"], bevel=0.02))
        out.append(box("border", (0.66, 0.012, 1.29), (x, y + 0.14 * -face, z), m["white"], bevel=0.02))
        out.append(box("housing", (0.34, 0.24, 1.0), (x, y, z), head_m, bevel=0.03))
        for i, mm in enumerate((red, amber, green)):
            zz = z + 0.32 - i * 0.32
            ln = cyl("lens", 0.1, 0.03, (0, 0, 0), mm, 12)
            ln.rotation_euler = (math.radians(90), 0, 0)
            ln.location = (x, y + face * 0.12, zz)
            out.append(ln)
            hood = cyl("hood", 0.125, 0.18, (0, 0, 0), head_m, 10, cap=False)
            hood.rotation_euler = (math.radians(90), 0, 0)
            hood.location = (x, y + face * 0.12 + face * 0.0, zz + 0.0)
            hood.scale = (1.0, 1.0, 1.0)
            out.append(hood)
        return out

    for x in (2.6, 4.9):
        p += signal(x, 0.0, 5.3)
    p += signal(0.0, -0.32, 3.0)
    p.append(box("button", (0.16, 0.12, 0.3), (0.16, -0.12, 1.15), mat("button_yellow", (0.95, 0.75, 0.1), 0.5), bevel=0.02))
    export("traffic_light", p)


# ------------------------------------------------------------------ furniture
def bench():
    """1.8 m bench facing +Y: cast-iron ends (front leg, raked back leg, arm),
    timber slats with gaps. Box sections only: benches are merged into every
    street chunk, so ~250 triangles."""
    reset()
    m = M()
    p = []
    for x in (-0.8, 0.8):
        p.append(box("front_leg", (0.05, 0.05, 0.44), (x, 0.17, 0.22), m["iron"]))
        bl = box("back_leg", (0.05, 0.05, 0.9), (0, 0, 0), m["iron"])
        bl.rotation_euler = (math.radians(-12), 0, 0)
        bl.location = (x, -0.25, 0.44)
        p.append(bl)
        p.append(box("seat_rail", (0.05, 0.44, 0.04), (x, -0.02, 0.42), m["iron"]))
        p.append(box("arm", (0.05, 0.42, 0.035), (x, -0.04, 0.63), m["iron"]))
    for i in range(4):
        p.append(box("slat", (1.76, 0.085, 0.032), (0, 0.15 - i * 0.105, 0.455), m["wood"]))
    for i in range(3):
        z = 0.56 + i * 0.11
        y = -0.25 - i * 0.022
        p.append(box("back", (1.76, 0.03, 0.08), (0, y, z), m["wood"]))
    export("bench", p)


def bin_():
    """Litter bin: plinth, green body with a gold band, domed lid, aperture."""
    reset()
    m = M()
    p = [lathe("body", [(0.2, 0.0), (0.22, 0.04), (0.22, 0.1), (0.24, 0.12), (0.24, 0.82), (0.26, 0.85), (0.25, 0.9),
                        (0.2, 0.98), (0.1, 1.02), (0.0, 1.03)], m["green"], 10)]
    p.append(lathe("band", [(0.245, 0.7), (0.245, 0.74)], m["gold"], 10))
    p.append(box("aperture", (0.26, 0.04, 0.12), (0, 0.235, 0.76), m["iron"]))
    p.append(box("logo", (0.12, 0.012, 0.12), (0, 0.245, 0.42), m["gold"]))
    export("bin", p)


def hydrant():
    reset()
    m = M()
    p = [lathe("body", [(0.17, 0.0), (0.17, 0.06), (0.12, 0.1), (0.11, 0.48), (0.13, 0.5), (0.13, 0.56), (0.1, 0.62),
                        (0.06, 0.66), (0.0, 0.68)], m["red"], 12)]
    for a in (0, math.pi):
        n = cyl("nozzle", 0.045, 0.1, (0, 0, 0), m["steel"], 8)
        n.rotation_euler = (0, math.radians(90), a)
        n.location = (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.42)
        p.append(n)
    p.append(cyl("cap", 0.035, 0.05, (0, 0, 0.67), m["steel"], 6))
    export("hydrant", p)


def bollard():
    """Cast-iron bollard: flared base, collars, dome."""
    reset()
    m = M()
    p = [lathe("post", [(0.13, 0.0), (0.13, 0.05), (0.1, 0.12), (0.085, 0.18), (0.08, 0.7), (0.09, 0.72), (0.09, 0.76),
                        (0.08, 0.78), (0.085, 0.82), (0.06, 0.9), (0.0, 0.93)], m["iron"], 10)]
    p.append(lathe("band", [(0.083, 0.62), (0.083, 0.67)], m["white"], 10))
    export("bollard", p)


def sign_post():
    """Street-name plates (white, black border, black lettering band) on a
    post, two at right angles."""
    reset()
    m = M()
    p = [lathe("post", [(0.045, 0.0), (0.04, 2.9), (0.05, 2.93), (0.0, 2.98)], m["iron"], 8)]
    for (cx, cy, rot) in ((0.42, 0.0, 0.0), (0.0, 0.42, math.pi / 2)):
        z = 2.72 if rot == 0 else 2.46
        plate = box("plate", (0.9, 0.025, 0.22), (0, 0, 0), m["white"])
        border = box("border", (0.94, 0.02, 0.26), (0, 0, 0), m["black"])
        text = box("text", (0.62, 0.03, 0.07), (0, 0, 0), m["black"])
        for o in (plate, border, text):
            o.rotation_euler = (0, 0, rot)
            o.location = (cx, cy, z)
            p.append(o)
    export("sign_post", p)


def bus_shelter():
    """3.6 m glazed shelter, open side facing +Y: canopy roof with a fascia,
    four posts, framed back and end glass, illuminated ad panel, perch seat,
    and a bus-stop flag on its own pole."""
    reset()
    m = M()
    p = [box("roof", (3.9, 1.6, 0.06), (0, -0.05, 2.5), m["galv"], bevel=0.015)]
    p.append(box("fascia", (3.9, 0.06, 0.18), (0, 0.72, 2.42), m["iron"]))
    p.append(box("fascia_txt", (1.0, 0.065, 0.08), (0, 0.73, 2.42), m["white"]))
    for x in (-1.75, 1.75):
        for y in (-0.62, 0.55):
            p.append(box("post", (0.07, 0.07, 2.45), (x, y, 1.22), m["galv"]))
    for i, x in enumerate((-1.17, 0.0, 1.17)):
        p.append(box("glass", (1.12, 0.012, 1.85), (x, -0.62, 1.3), m["glass"]))
        p.append(box("rail", (1.16, 0.03, 0.04), (x, -0.62, 0.36), m["galv"]))
        p.append(box("rail_t", (1.16, 0.03, 0.04), (x, -0.62, 2.24), m["galv"]))
    p.append(box("end_glass", (0.012, 1.1, 1.85), (-1.75, -0.04, 1.3), m["glass"]))
    p.append(box("ad_frame", (0.12, 1.15, 1.75), (1.75, -0.04, 1.2), m["iron"], bevel=0.01))
    p.append(box("ad", (0.13, 1.0, 1.55), (1.75, -0.04, 1.2), m["ad"]))
    p.append(box("perch", (1.9, 0.18, 0.05), (-0.5, -0.5, 0.62), m["steel"], bevel=0.01))
    for x in (-1.3, 0.3):
        p.append(box("perch_leg", (0.05, 0.05, 0.6), (x, -0.55, 0.3), m["steel"]))
    p.append(lathe("flag_pole", [(0.045, 0.0), (0.04, 2.9)], m["galv"], 8, z0=0.0))
    flag = p[-1]
    flag.location = (2.25, 0.5, 0)
    p.append(box("flag", (0.03, 0.45, 0.45), (2.25, 0.5, 2.65), m["red_sign"], bevel=0.01))
    p.append(box("flag_txt", (0.035, 0.32, 0.14), (2.25, 0.5, 2.7), m["white"]))
    p.append(box("timetable", (0.03, 0.3, 0.4), (2.25, 0.5, 1.6), m["white"]))
    export("bus_shelter", p)


def planter():
    """Stone planter (plinth, tapered tub, coping) with a layered shrub."""
    reset()
    m = M()
    p = [box("plinth", (1.26, 1.26, 0.08), (0, 0, 0.04), m["stone_dk"], bevel=0.02)]
    bm = bmesh.new()
    for (w, z) in ((0.55, 0.08), (0.6, 0.5)):
        pass
    rings = [[bm.verts.new((sx * w, sy * w, z)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))] for w, z in ((0.55, 0.08), (0.6, 0.5))]
    for k in range(4):
        bm.faces.new((rings[0][k], rings[0][(k + 1) % 4], rings[1][(k + 1) % 4], rings[1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    p.append(kit.new_obj("tub", bm, m["stone"]))
    for sx, sy, w, d in ((0, 0.6, 1.28, 0.08), (0, -0.6, 1.28, 0.08), (0.6, 0, 0.08, 1.28), (-0.6, 0, 0.08, 1.28)):
        p.append(box("coping", (w, d, 0.06), (sx, sy, 0.53), m["stone_dk"]))
    p.append(box("soil", (1.12, 1.12, 0.02), (0, 0, 0.5), m["soil"]))
    import random
    rnd = random.Random(7)
    for i in range(6):
        a = i * 2.39
        r = 0.32 * math.sqrt((i + 0.5) / 6)
        c = (math.cos(a) * r, math.sin(a) * r, 0.68 + rnd.uniform(0, 0.25))
        s = sphere("shrub", rnd.uniform(0.24, 0.34), c, m["leaf"] if i % 3 else m["leaf2"], 6, 4, scale=(1, 1, 0.8))
        p.append(s)
    export("planter", p)


BUILD = {"streetlight": streetlight, "traffic_light": traffic_light, "bench": bench, "bin": bin_, "hydrant": hydrant,
         "bollard": bollard, "sign_post": sign_post, "bus_shelter": bus_shelter, "planter": planter}
for name, fn in BUILD.items():
    if ONLY and name not in ONLY:
        continue
    fn()
print("STREET DONE")
