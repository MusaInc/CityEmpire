"""City Empire venues v1: walk-in interiors designed in Blender.

Run:  blender -b --factory-startup --python tools/blender/build_venues.py -- <out_dir> [render_dir] [only,ids]

Concept + asset pass for the "finish the game" plan (no game code yet):
  meridian   Meridian Prestige: luxury car showroom (hypercar gallery,
             turntable, sales desks, lounge, handover bay, mezzanine)
  kestrel    Kestrel Motors: friendly used-car showroom
  arden      Maison Arden: premium boutique (mannequins, brass rails,
             fitting rooms, shoe wall, watch counter)
  threadline Threadline: everyday clothes store
  lobby      Residential lobby + lift: street door, concierge, mailboxes,
             lift landing and a real lift car (doors as their own nodes)
  study      Apartment study: the "Empire Desk" corner (desk, screens,
             recruitment board, trophy wall)
  hq         HQ floor: reception, open-plan desks, corner office,
             boardroom, empire map wall

Each venue sits on its real footprint from SkyportIsland (metres; front
glass on -Y = the street side, which is Godot +Z after export... see the
per-venue note). Interactive pieces are separate named nodes so the game
can drive them: Door_L/Door_R, Turntable, RollerDoor, LiftCar,
LiftDoor_L/LiftDoor_R, CarDoor_L/CarDoor_R, plus "spot_*" empties for
interaction points and "car_*" / "npc_*" empties for display cars and
people. Review renders put the real car GLBs on the display spots.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
os.environ["CRAFT_NO_MAIN"] = "1"
import build_kit as kit  # noqa: E402
from build_kit import mat  # noqa: E402
import build_craft as bc  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "art/design/venues"
RENDER = ARGS[1] if len(ARGS) > 1 else ""
ONLY = set(ARGS[2].split(",")) if len(ARGS) > 2 and ARGS[2] else set()
os.makedirs(OUT, exist_ok=True)
if RENDER:
    os.makedirs(RENDER, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
FONTS = os.path.join(ROOT, "assets", "fonts", "brand")
TAU = math.tau


# ---------------------------------------------------------------- materials


def M():
    em = lambda n, c, s=4.0: _emit(n, c, s)  # noqa: E731
    return {
        "floor_dark": mat("floor_polished_dark", (0.035, 0.035, 0.04), 0.06, 0.0),
        "floor_light": mat("floor_polished_light", (0.62, 0.6, 0.57), 0.12, 0.0),
        "floor_tile": mat("floor_tile", (0.82, 0.82, 0.8), 0.35, 0.0),
        "floor_oak": mat("floor_oak", (0.42, 0.28, 0.17), 0.45, 0.0),
        "floor_stone": mat("floor_stone", (0.72, 0.68, 0.6), 0.25, 0.0),
        "carpet": mat("carpet", (0.18, 0.19, 0.21), 0.95, 0.0),
        "wall": mat("wall_plaster", (0.86, 0.85, 0.82), 0.8, 0.0),
        "wall_dark": mat("wall_dark", (0.07, 0.07, 0.08), 0.6, 0.0),
        "wall_warm": mat("wall_warm", (0.72, 0.64, 0.54), 0.75, 0.0),
        "ceiling": mat("ceiling", (0.9, 0.9, 0.9), 0.9, 0.0),
        "marble": mat("marble", (0.9, 0.89, 0.86), 0.12, 0.0),
        "marble_dark": mat("marble_dark", (0.06, 0.06, 0.07), 0.1, 0.0),
        "oak": mat("oak", (0.5, 0.34, 0.2), 0.5, 0.0),
        "walnut": mat("walnut", (0.24, 0.14, 0.08), 0.45, 0.0),
        "brass": mat("brass", (0.83, 0.62, 0.3), 0.22, 1.0),
        "gold": mat("gold", (0.9, 0.72, 0.38), 0.18, 1.0),
        "steel": mat("brushed_steel", (0.62, 0.63, 0.65), 0.28, 1.0),
        "black_steel": mat("black_steel", (0.04, 0.04, 0.045), 0.35, 0.8),
        "mirror": mat("mirror", (0.95, 0.95, 0.95), 0.02, 1.0),
        "glass": _glass("glass_clear"),
        "glass_tint": _glass("glass_tint", (0.55, 0.6, 0.62)),
        "leather": mat("leather_tan", (0.4, 0.22, 0.12), 0.55, 0.0),
        "leather_black": mat("leather_black", (0.03, 0.03, 0.03), 0.5, 0.0),
        "fabric": mat("fabric_grey", (0.38, 0.38, 0.4), 0.95, 0.0),
        "fabric_cream": mat("fabric_cream", (0.78, 0.74, 0.66), 0.95, 0.0),
        "velvet": mat("velvet_green", (0.06, 0.18, 0.13), 0.9, 0.0),
        "rubber": mat("rubber", (0.03, 0.03, 0.03), 0.9, 0.0),
        "plant": mat("foliage", (0.07, 0.2, 0.06), 0.75, 0.0),
        "pot": mat("pot", (0.15, 0.15, 0.15), 0.7, 0.0),
        "screen": em("screen", (0.25, 0.45, 0.85), 2.0),
        "screen_off": mat("screen_off", (0.01, 0.01, 0.012), 0.1, 0.0),
        "led": em("led_strip", (1.0, 0.93, 0.82), 6.0),
        "led_cool": em("led_cool", (0.85, 0.92, 1.0), 6.0),
        "led_gold": em("led_gold", (1.0, 0.75, 0.4), 5.0),
        "btn": em("lift_button", (0.9, 0.95, 1.0), 3.0),
        "red": mat("paint_red", (0.55, 0.05, 0.04), 0.4, 0.0),
        "kestrel_teal": mat("brand_teal", (0.0, 0.42, 0.42), 0.45, 0.0),
        "kestrel_yellow": mat("brand_yellow", (0.95, 0.72, 0.08), 0.45, 0.0),
        "white": mat("white_gloss", (0.88, 0.88, 0.88), 0.25, 0.0),
        "mannequin": mat("mannequin", (0.85, 0.84, 0.8), 0.3, 0.0),
        "skin_m": mat("mannequin_black", (0.04, 0.04, 0.045), 0.35, 0.0),
        "paper": mat("paper", (0.95, 0.94, 0.9), 0.9, 0.0),
    }


def _emit(name, c, s):
    m = mat(name, c, 0.4, 0.0, emit=c)
    m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = s
    return m


def _glass(name, tint=(0.9, 0.95, 0.95)):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*tint, 1)
    b.inputs["Roughness"].default_value = 0.02
    b.inputs["Transmission Weight"].default_value = 1.0
    b.inputs["IOR"].default_value = 1.45
    return m


_cloth = {}


def cloth(rgb):
    key = tuple(round(c, 3) for c in rgb)
    if key not in _cloth:
        _cloth[key] = mat(f"cloth_{len(_cloth)}", rgb, 0.9, 0.0)
    return _cloth[key]


# ---------------------------------------------------------------- primitives


def B(name, size, loc, m, bevel=0.0):
    ob = kit.box(name, size, loc, m, bevel=bevel, segs=2)
    return ob


def C(name, r, h, loc, m, verts=24, r2=None):
    return kit.cyl(name, r, h, loc, m, verts, r2)


def empty(name, loc, rot_z=0.0):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    e.rotation_euler = (0, 0, rot_z)
    bpy.context.scene.collection.objects.link(e)
    return e


def text(name, s, loc, size, m, font="Oswald.ttf", extrude=0.02, rot=(math.pi / 2, 0, 0), align="CENTER"):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = s
    try:
        cu.font = bpy.data.fonts.load(os.path.join(FONTS, font), check_existing=True)
    except RuntimeError:
        pass
    cu.size = size
    cu.extrude = extrude
    cu.align_x = align
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = rot
    ob.data.materials.append(m)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    return bpy.context.view_layer.objects.active


def plant(name, loc, h=1.6, m=None):
    parts = [C(name + "_pot", 0.32, 0.55, loc, m["pot"], 20, 0.26)]
    import random
    rnd = random.Random(hash(name) & 0xFFFF)
    for k in range(9):
        a = rnd.random() * TAU
        r = rnd.uniform(0.05, 0.3)
        z = loc[2] + 0.55 + rnd.uniform(0.25, h - 0.3)
        parts.append(kit.sphere(f"{name}_f{k}", rnd.uniform(0.22, 0.38), (loc[0] + math.cos(a) * r, loc[1] + math.sin(a) * r, z),
                                m["plant"], 10, 6, (1.0, 1.0, 1.25)))
    return parts


def chair_lounge(name, loc, rot, m, mat_seat):
    x, y, z = loc
    parts = [B(name + "_seat", (0.85, 0.8, 0.22), (0, 0, 0.32), mat_seat, 0.06),
             B(name + "_back", (0.85, 0.18, 0.5), (0, -0.34, 0.62), mat_seat, 0.06),
             B(name + "_armL", (0.14, 0.8, 0.35), (-0.42, 0, 0.5), mat_seat, 0.05),
             B(name + "_armR", (0.14, 0.8, 0.35), (0.42, 0, 0.5), mat_seat, 0.05)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(C(name + f"_leg{sx}{sy}", 0.02, 0.22, (sx * 0.36, sy * 0.32, 0.0), m["black_steel"], 8))
    ob = kit.join(name, parts)
    ob.rotation_euler = (0, 0, rot)
    ob.location = (x, y, z)
    return ob


def sofa(name, loc, rot, w, m, mat_seat):
    parts = [B(name + "_base", (w, 0.95, 0.3), (0, 0, 0.25), mat_seat, 0.05),
             B(name + "_cush", (w - 0.3, 0.75, 0.16), (0, 0.06, 0.48), mat_seat, 0.07),
             B(name + "_back", (w, 0.24, 0.5), (0, -0.36, 0.65), mat_seat, 0.08),
             B(name + "_armL", (0.2, 0.95, 0.32), (-w / 2 + 0.1, 0, 0.52), mat_seat, 0.07),
             B(name + "_armR", (0.2, 0.95, 0.32), (w / 2 - 0.1, 0, 0.52), mat_seat, 0.07),
             B(name + "_plinth", (w - 0.1, 0.85, 0.1), (0, 0, 0.05), m["black_steel"], 0.01)]
    ob = kit.join(name, parts)
    ob.rotation_euler = (0, 0, rot)
    ob.location = loc
    return ob


def office_chair(name, loc, rot, m):
    parts = [B(name + "_seat", (0.5, 0.5, 0.08), (0, 0, 0.48), m["leather_black"], 0.03),
             B(name + "_back", (0.48, 0.07, 0.6), (0, -0.25, 0.85), m["leather_black"], 0.03),
             C(name + "_post", 0.03, 0.4, (0, 0, 0.06), m["steel"], 8)]
    for k in range(5):
        a = TAU * k / 5
        parts.append(B(name + f"_foot{k}", (0.32, 0.04, 0.03), (math.cos(a) * 0.16, math.sin(a) * 0.16, 0.06), m["steel"]))
        parts[-1].rotation_euler = (0, 0, a)
    ob = kit.join(name, parts)
    ob.rotation_euler = (0, 0, rot)
    ob.location = loc
    return ob


def ceiling_light_lines(name, x0, x1, y0, y1, z, step, m, along="x", w=0.06):
    out = []
    if along == "x":
        y = y0
        while y <= y1 + 1e-6:
            out.append(B(f"{name}{len(out)}", (x1 - x0, w, 0.02), ((x0 + x1) / 2, y, z - 0.01), m))
            y += step
    else:
        x = x0
        while x <= x1 + 1e-6:
            out.append(B(f"{name}{len(out)}", (w, y1 - y0, 0.02), (x, (y0 + y1) / 2, z - 0.01), m))
            x += step
    return out


def curtain_wall(name, x0, x1, y, h, m, bay=2.4, door=None, transom=None, mull=0.08):
    """Glazed front along x at depth y (facing -y). door = (x_centre, width, height)."""
    if door:
        dl, dr, dh = door[0] - door[1] / 2, door[0] + door[1] / 2, door[2]
        parts = [B(name + "_glass_l", (dl - x0, 0.03, h), ((x0 + dl) / 2, y, h / 2), m["glass"]),
                 B(name + "_glass_r", (x1 - dr, 0.03, h), ((dr + x1) / 2, y, h / 2), m["glass"]),
                 B(name + "_glass_t", (dr - dl, 0.03, h - dh), (door[0], y, dh + (h - dh) / 2), m["glass"]),
                 B(name + "_door_head", (dr - dl, 0.22, 0.12), (door[0], y, dh + 0.06), m["black_steel"])]
    else:
        parts = [B(name + "_glass", (x1 - x0, 0.03, h), ((x0 + x1) / 2, y, h / 2), m["glass"])]
    n = max(1, int(round((x1 - x0) / bay)))
    for k in range(n + 1):
        x = x0 + (x1 - x0) * k / n
        if door and abs(x - door[0]) < door[1] / 2 - 0.05:
            continue
        parts.append(B(f"{name}_m{k}", (mull, 0.2, h), (x, y, h / 2), m["black_steel"]))
    parts.append(B(name + "_head", (x1 - x0, 0.22, 0.16), ((x0 + x1) / 2, y, h - 0.08), m["black_steel"]))
    if door:
        dl, dr = door[0] - door[1] / 2, door[0] + door[1] / 2
        parts.append(B(name + "_sill_l", (dl - x0, 0.24, 0.1), ((x0 + dl) / 2, y, 0.05), m["black_steel"]))
        parts.append(B(name + "_sill_r", (x1 - dr, 0.24, 0.1), ((dr + x1) / 2, y, 0.05), m["black_steel"]))
    else:
        parts.append(B(name + "_sill", (x1 - x0, 0.24, 0.1), ((x0 + x1) / 2, y, 0.05), m["black_steel"]))
    if transom:
        parts.append(B(name + "_tr", (x1 - x0, 0.16, 0.08), ((x0 + x1) / 2, y, transom), m["black_steel"]))
    return parts


def sliding_doors(prefix, xc, y, w, h, m):
    """Two glass leaves (nodes Door_L / Door_R, origin at their closed centre)."""
    nodes = []
    for s, nm in ((-1, "L"), (1, "R")):
        leaf = [B(f"{prefix}{nm}_g", (w / 2 - 0.04, 0.025, h - 0.1), (0, 0, h / 2), m["glass"]),
                B(f"{prefix}{nm}_fs", (0.05, 0.05, h), (s * (w / 4 - 0.03), 0, h / 2), m["black_steel"]),
                B(f"{prefix}{nm}_fb", (w / 2, 0.05, 0.06), (0, 0, 0.03), m["black_steel"]),
                B(f"{prefix}{nm}_ft", (w / 2, 0.05, 0.06), (0, 0, h - 0.03), m["black_steel"]),
                B(f"{prefix}{nm}_pull", (0.03, 0.06, 0.9), (-s * (w / 4 - 0.12), -0.05, 1.05), m["steel"])]
        ob = kit.join(f"Door_{nm}", leaf)
        ob.location = (xc + s * w / 4, y - 0.12, 0)   # (just outside the glass line: slides past it)
        nodes.append(ob)
    return nodes


def roller_door(name, xc, y, w, h, m):
    parts = []
    k = 0
    z = 0.0
    while z < h - 0.01:
        parts.append(B(f"{name}_s{k}", (w, 0.06, 0.14), (0, 0, z + 0.07), m["steel"], 0.01))
        z += 0.15
        k += 1
    parts.append(B(name + "_box", (w + 0.3, 0.5, 0.5), (0, -0.2, h + 0.25), m["black_steel"], 0.02))
    ob = kit.join("RollerDoor", parts)
    ob.location = (xc, y, 0)
    return ob


def turntable(loc, r, m, mat_top):
    parts = [C("tt_base", r, 0.16, (0, 0, 0), mat_top, 64),
             C("tt_led", r + 0.03, 0.03, (0, 0, 0.05), m["led_cool"], 64)]
    ob = kit.join("Turntable", parts)
    ob.location = loc
    return ob


def spot_ring(name, c, r, z, n, m):
    parts = []
    # Halo truss ring + downlights.
    ring = bc.tube(name + "_ring", [(c[0] + math.cos(TAU * k / 48) * r, c[1] + math.sin(TAU * k / 48) * r, z) for k in range(49)], 0.06, m["black_steel"], 8)
    parts.append(ring)
    for k in range(n):
        a = TAU * k / n
        p = (c[0] + math.cos(a) * r, c[1] + math.sin(a) * r, z - 0.18)
        parts.append(C(f"{name}_can{k}", 0.09, 0.22, p, m["black_steel"], 12))
        parts.append(C(f"{name}_lens{k}", 0.07, 0.01, (p[0], p[1], p[2] - 0.005), m["led"], 12))
    for k in range(3):
        a = TAU * k / 3
        parts.append(bc.tube(f"{name}_hang{k}", [(c[0] + math.cos(a) * r, c[1] + math.sin(a) * r, z), (c[0] + math.cos(a) * r, c[1] + math.sin(a) * r, z + 3.0)], 0.01, m["steel"], 4))
    return parts


def light_rig(c, r, z, n, energy=900, size=0.25, spot=False):
    """Render-only lights (not exported)."""
    out = []
    for k in range(n):
        a = TAU * k / n
        L = bpy.data.lights.new("rig", "SPOT" if spot else "AREA")
        L.energy = energy
        if spot:
            L.spot_size = math.radians(55)
            L.spot_blend = 0.6
        else:
            L.size = size
        o = bpy.data.objects.new("rig", L)
        o.location = (c[0] + math.cos(a) * r, c[1] + math.sin(a) * r, z)
        d = Vector((c[0], c[1], 0.5)) - o.location
        o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        o["render_only"] = True
        bpy.context.scene.collection.objects.link(o)
        out.append(o)
    return out


def area_grid(x0, x1, y0, y1, z, step, energy, size=1.5):
    out = []
    x = x0
    while x <= x1 + 1e-6:
        y = y0
        while y <= y1 + 1e-6:
            L = bpy.data.lights.new("grid", "AREA")
            L.energy = energy
            L.size = size
            o = bpy.data.objects.new("grid", L)
            o.location = (x, y, z)
            o["render_only"] = True
            bpy.context.scene.collection.objects.link(o)
            out.append(o)
            y += step
        x += step
    return out


# ---------------------------------------------------------------- people + clothes


def mannequin(name, loc, rot, m, top=None, bottom=None, pose=0.0, female=False):
    """Abstract display figure: lofted torso, egg head, tube limbs; garments lofted over it."""
    x, y, z = loc
    sk = m["mannequin"] if not female else m["skin_m"]
    sh = 0.21 if not female else 0.19
    parts = [C(name + "_base", 0.22, 0.03, (0, 0, 0), m["black_steel"], 24), C(name + "_pole", 0.015, 0.95, (0, -0.02, 0.03), m["steel"], 8)]
    torso = bc.body(name + "_torso", {"y0": 0.95, "y1": 1.58, "n_st": 14, "z": 0.0, "ends": False,
                                      "w": [(0.95, 0.17 if not female else 0.19), (1.08, 0.16), (1.25, 0.15 if not female else 0.13), (1.45, sh), (1.52, sh - 0.01), (1.58, 0.07)],
                                      "top": [(0.95, 0.11), (1.25, 0.1), (1.42, 0.12), (1.58, 0.06)], "bot": [(0.95, 0.1), (1.42, 0.1), (1.58, 0.06)],
                                      "n": 2.4, "smooth": 80}, sk, segs=20)
    # body() lofts along y: turn it upright (y -> z).
    for v in torso.data.vertices:
        v.co = Vector((v.co.x, -v.co.z, v.co.y))
    parts.append(torso)
    parts.append(C(name + "_neck", 0.05, 0.1, (0, 0, 1.58), sk, 12))
    parts.append(kit.sphere(name + "_head", 0.11, (0, 0, 1.76), sk, 16, 10, (0.85, 0.95, 1.15)))
    for s in (-1, 1):
        sw = pose * s
        parts.append(bc.tube(f"{name}_arm{s}", [(s * (sh + 0.01), 0, 1.5), (s * (sh + 0.05), 0.03 * sw, 1.2), (s * (sh + 0.06), 0.08 + 0.05 * sw, 0.92)], 0.04, sk, 10))
        parts.append(bc.tube(f"{name}_leg{s}", [(s * 0.09, 0, 0.97), (s * 0.1, 0.02, 0.5), (s * 0.1, 0.0, 0.06)], 0.06, sk, 10))
    if top is not None:
        t = bc.body(name + "_top", {"y0": 0.9, "y1": 1.56, "n_st": 12, "z": 0.0, "ends": False,
                                    "w": [(0.9, 0.2), (1.25, 0.18), (1.45, sh + 0.035), (1.56, 0.1)],
                                    "top": [(0.9, 0.13), (1.42, 0.14), (1.56, 0.08)], "bot": [(0.9, 0.12), (1.42, 0.12), (1.56, 0.08)],
                                    "n": 2.3, "smooth": 80}, cloth(top), segs=20)
        for v in t.data.vertices:
            v.co = Vector((v.co.x, -v.co.z, v.co.y))
        parts.append(t)
        for s in (-1, 1):
            parts.append(bc.tube(f"{name}_sleeve{s}", [(s * (sh + 0.01), 0, 1.5), (s * (sh + 0.05), 0.03 * pose * s, 1.2), (s * (sh + 0.06), 0.06, 1.0)], 0.055, cloth(top), 10))
    if bottom is not None:
        for s in (-1, 1):
            parts.append(bc.tube(f"{name}_trouser{s}", [(s * 0.06, 0, 1.0), (s * 0.1, 0.02, 0.5), (s * 0.1, 0.0, 0.1)], 0.075, cloth(bottom), 10))
        parts.append(B(name + "_waist", (0.36, 0.22, 0.12), (0, 0, 0.98), cloth(bottom), 0.06))
    ob = kit.join(name, parts)
    ob.rotation_euler = (0, 0, rot)
    ob.location = (x, y, z)
    return ob


def garment_hanging(name, x, y, z, rgb, long=False, m=None):
    """A shirt / jacket on a hanger, seen side-on on a rail (thin, shoulders + body)."""
    h = 0.95 if long else 0.7
    # (No bevels: a store holds ~1000 of these, and at game distance a plain
    # box reads the same. Bevelled they cost ~90k triangles per shop.)
    parts = [B(name + "_body", (0.06, 0.5, h), (0, 0, -h / 2 - 0.08), cloth(rgb)),
             B(name + "_sh", (0.07, 0.46, 0.06), (0, 0, -0.08), cloth(rgb)),
             bc.tube(name + "_hook", [(0, 0, 0.02), (0, 0.0, 0.1)], 0.006, m["steel"], 3)]
    ob = kit.join(name, parts)
    ob.location = (x, y, z)
    return ob


def rail(name, x0, x1, y, z, m, colours, mrail, long=False, spacing=0.11):
    parts = [bc.tube(name + "_bar", [(x0, y, z), (x1, y, z)], 0.016, mrail, 8)]
    for x in (x0, x1):
        parts.append(bc.tube(name + f"_post{x}", [(x, y, 0.0), (x, y, z)], 0.018, mrail, 8))
    out = [kit.join(name, parts)]
    n = int((x1 - x0 - 0.2) / spacing)
    for k in range(n):
        c = colours[k % len(colours)]
        g = garment_hanging(f"{name}_g{k}", x0 + 0.15 + k * spacing, y, z, c, long, M_CACHE)
        g.rotation_euler = (0, 0, math.pi / 2 + (0.05 if k % 2 else -0.04))
        out.append(g)
    return out


def folded_table(name, loc, w, d, m, colours, top_mat):
    x, y, z = loc
    parts = [B(name + "_top", (w, d, 0.06), (0, 0, 0.82), top_mat, 0.01),
             B(name + "_plinth", (w - 0.2, d - 0.2, 0.79), (0, 0, 0.395), top_mat, 0.01)]
    k = 0
    for ix in range(int(w / 0.42)):
        for iy in range(int(d / 0.42)):
            c = colours[k % len(colours)]
            k += 1
            for lvl in range(3 + (k % 3)):
                parts.append(B(f"{name}_f{ix}{iy}{lvl}", (0.34, 0.3, 0.045), (-w / 2 + 0.24 + ix * 0.42, -d / 2 + 0.22 + iy * 0.42, 0.875 + lvl * 0.046), cloth(c), 0.01))
    ob = kit.join(name, parts)
    ob.location = loc
    return ob


def shoe(name, loc, rgb, rot=0.0):
    s = bc.body(name, {"y0": -0.14, "y1": 0.14, "n_st": 10, "z": 0.045, "ends": True,
                       "w": [(-0.14, 0.035), (-0.08, 0.045), (0.06, 0.05), (0.14, 0.02)],
                       "top": [(-0.14, 0.06), (-0.06, 0.07), (0.02, 0.04), (0.14, 0.02)], "bot": 0.04, "n": 2.6}, cloth(rgb), segs=12)
    s.location = loc
    s.rotation_euler = (0, 0, rot)
    return s


def npc(name, loc, rot, m, outfit):
    """Placeholder person for the review renders (game uses crowd.glb)."""
    o = mannequin(name, loc, rot, m, top=outfit[0], bottom=outfit[1], pose=0.3)
    for p in o.data.polygons:
        pass
    # Drop the display stand.
    return o


M_CACHE = None


# ---------------------------------------------------------------- shell


def shell(m, w, d, h, floor_mat, wall_mat, ceil=True, front=True, back_mat=None):
    """Room on x in [-w/2, w/2], y in [0, d] (front glass at y = 0 faces the street), floor z 0."""
    parts = [B("floor", (w, d, 0.2), (0, d / 2, -0.1), floor_mat),
             B("wall_back", (w, 0.3, h), (0, d + 0.15, h / 2), back_mat or wall_mat),
             B("wall_l", (0.3, d, h), (-w / 2 - 0.15, d / 2, h / 2), wall_mat),
             B("wall_r", (0.3, d, h), (w / 2 + 0.15, d / 2, h / 2), wall_mat)]
    if ceil:
        parts.append(B("ceiling", (w, d, 0.3), (0, d / 2, h + 0.15), m["ceiling"]))
    return parts


# ---------------------------------------------------------------- venues


def v_meridian(m):
    """Meridian Prestige: 120 x 36 m footprint, 11 m. We use the front 60 x 28 m as the
    showroom (hypercar gallery left, main floor centre, handover + lounge right) and a
    mezzanine along the back."""
    W, D, H = 60.0, 28.0, 8.5
    parts, nodes, marks = [], [], []
    parts += shell(m, W, D, H, m["floor_dark"], m["wall_dark"], back_mat=m["wall_dark"])
    parts += curtain_wall("front", -W / 2, W / 2, 0.0, H, m, bay=3.0, door=(0.0, 4.0, 3.2), transom=3.4)
    nodes += sliding_doors("door", 0.0, 0.0, 3.6, 3.2, m)
    # Ceiling: dark with continuous light lines (the brand's "light blade").
    parts += ceiling_light_lines("blade", -W / 2 + 1, W / 2 - 1, 3.0, D - 7.0, H, 2.6, m["led"], along="x", w=0.05)
    # Brand wall (back, centre): illuminated letters on dark fluted panels.
    for k in range(40):
        parts.append(B(f"flute{k}", (0.22, 0.12, 5.2), (-9.6 + k * 0.5, D - 0.1, 2.6), m["wall_dark"], 0.03))
    parts.append(text("logo", "MERIDIAN", (0, D - 0.2, 4.2), 1.25, m["led_gold"], "PlayfairDisplay.ttf", 0.05))
    parts.append(text("logo2", "PRESTIGE", (0, D - 0.2, 3.1), 0.42, m["gold"], "Oswald.ttf", 0.02))
    # Hypercar gallery (left): raised black plinth, turntable under a halo of spots.
    gx, gy = -19.0, 12.0
    parts.append(C("gallery_plinth", 7.2, 0.12, (gx, gy, 0.0), m["marble_dark"], 72))
    nodes.append(turntable((gx, gy, 0.12), 3.4, m, m["marble_dark"]))
    parts += spot_ring("halo", (gx, gy), 4.4, 6.2, 16, m)
    marks.append(("car_turntable", (gx, gy, 0.28), math.radians(35)))
    marks.append(("spot_turntable", (gx + 4.6, gy - 3.2, 0.0), 0.0))
    # Main floor: four display cars on low plinths with spec totems.
    for k, (cx, cy, rz) in enumerate([(-6.0, 7.5, 25), (6.0, 7.5, -25), (-6.0, 17.5, 155), (6.0, 17.5, -155)]):
        parts.append(B(f"plinth{k}", (3.0, 6.0, 0.08), (cx, cy, 0.04), m["marble_dark"], 0.02))
        parts.append(B(f"plinth_led{k}", (3.04, 6.04, 0.015), (cx, cy, 0.005), m["led_cool"]))
        marks.append((f"car_{k}", (cx, cy, 0.08), math.radians(rz)))
        tx = cx + (2.4 if cx > 0 else -2.4)
        parts.append(B(f"totem{k}", (0.5, 0.08, 1.5), (tx, cy - 2.6, 0.75), m["black_steel"], 0.01))
        parts.append(B(f"totem_screen{k}", (0.42, 0.01, 0.9), (tx, cy - 2.65, 1.0), m["screen"]))
        marks.append((f"spot_car_{k}", (tx, cy - 3.2, 0.0), 0.0))
    # Configurator wall (right of centre): a big screen, a stool, colour swatches.
    parts.append(B("config_screen", (6.0, 0.1, 3.0), (17.5, D - 0.3, 2.6), m["screen"]))
    parts.append(B("config_frame", (6.3, 0.12, 3.3), (17.5, D - 0.2, 2.6), m["black_steel"]))
    for k in range(10):
        parts.append(C(f"swatch{k}", 0.09, 0.02, (15.2 + k * 0.5, D - 1.6, 1.0), cloth([(0.6, 0.05, 0.04), (0.9, 0.9, 0.88), (0.02, 0.02, 0.02), (0.08, 0.2, 0.45), (0.85, 0.42, 0.05),
                                                                                          (0.5, 0.52, 0.55), (0.1, 0.3, 0.12), (0.92, 0.75, 0.2), (0.35, 0.05, 0.25), (0.6, 0.62, 0.64)][k]), 16))
    parts.append(B("swatch_bar", (5.4, 0.5, 0.95), (17.5, D - 1.6, 0.48), m["marble"], 0.03))
    marks.append(("spot_configurator", (17.5, D - 2.6, 0.0), 0.0))
    # Sales desks: curved white marble pods with two chairs each.
    for k, (dx, dy) in enumerate([(14.0, 6.5), (21.0, 6.5)]):
        desk = bc.body(f"desk{k}", {"y0": -1.2, "y1": 1.2, "n_st": 12, "z": 0.37, "ends": False,
                                     "w": [(-1.2, 0.5), (0, 0.62), (1.2, 0.5)], "top": 0.38, "bot": 0.37, "n": 4.0}, m["marble"], segs=20)
        desk.rotation_euler = (0, 0, math.pi / 2)
        desk.location = (dx, dy, 0)
        parts.append(desk)
        parts.append(B(f"desk_top{k}", (2.6, 1.3, 0.04), (dx, dy, 0.77), m["marble"], 0.02))
        parts.append(B(f"desk_screen{k}", (0.6, 0.03, 0.38), (dx, dy + 0.35, 1.0), m["screen"]))
        parts.append(office_chair(f"desk_chair{k}", (dx, dy + 1.05, 0), math.pi, m))
        for s in (-1, 1):
            parts.append(chair_lounge(f"client{k}{s}", (dx + s * 0.6, dy - 1.2, 0), 0.0, m, m["leather"]))
        marks.append((f"npc_sales_{k}", (dx, dy + 1.0, 0.0), math.pi))
        marks.append((f"spot_sales_{k}", (dx, dy - 1.9, 0.0), 0.0))
    # Lounge: sofas, rug, coffee bar.
    parts.append(B("rug", (7.0, 5.0, 0.02), (22.0, 15.5, 0.01), m["carpet"]))
    parts.append(sofa("sofa_a", (22.0, 13.4, 0), 0.0, 3.0, m, m["leather"]))
    parts.append(sofa("sofa_b", (22.0, 17.8, 0), math.pi, 3.0, m, m["leather"]))
    parts.append(B("coffee_table", (1.6, 0.9, 0.38), (22.0, 15.6, 0.19), m["marble_dark"], 0.03))
    parts.append(B("bar", (5.0, 0.8, 1.1), (27.0, 21.0, 0.55), m["marble"], 0.03))
    parts.append(B("bar_back", (5.0, 0.5, 2.2), (27.0, 23.0, 1.1), m["walnut"], 0.02))
    parts.append(B("bar_shelf_led", (4.8, 0.05, 0.03), (27.0, 22.7, 1.6), m["led_gold"]))
    marks.append(("npc_barista", (27.0, 22.0, 0.0), math.pi))
    # Handover bay (front right): marked bay, a roller door to the forecourt.
    parts.append(B("handover_floor", (7.0, 9.0, 0.01), (25.5, 6.0, 0.005), m["marble_dark"]))
    parts += [B(f"handover_line{k}", (0.08, 9.0, 0.012), (22.0 + k * 7.0, 6.0, 0.008), m["led_cool"]) for k in range(2)]
    parts.append(text("handover_txt", "HANDOVER", (25.5, 9.8, 0.015), 0.6, m["gold"], "Oswald.ttf", 0.003, rot=(0, 0, 0)))
    nodes.append(roller_door("roller", 25.5, 0.05, 5.0, 3.6, m))
    marks.append(("car_handover", (25.5, 5.0, 0.0), 0.0))
    marks.append(("spot_handover", (21.4, 6.5, 0.0), 0.0))
    # Mezzanine along the back-left: glass balustrade, floating stair.
    mz = 4.0
    parts.append(B("mezz_slab", (24.0, 5.0, 0.3), (-16.0, D - 2.5, mz - 0.15), m["wall_dark"]))
    parts.append(B("mezz_floor", (24.0, 5.0, 0.02), (-16.0, D - 2.5, mz + 0.01), m["floor_oak"]))
    parts.append(B("mezz_glass", (24.0, 0.03, 1.05), (-16.0, D - 5.0, mz + 0.53), m["glass"]))
    parts.append(B("mezz_rail", (24.0, 0.06, 0.04), (-16.0, D - 5.0, mz + 1.06), m["brass"]))
    parts.append(B("mezz_fascia_led", (24.0, 0.02, 0.04), (-16.0, D - 5.02, mz - 0.25), m["led"]))
    for k in range(17):
        z = (k + 1) * mz / 17
        parts.append(B(f"stair{k}", (1.4, 0.3, 0.06), (-3.2, D - 5.6 - 6.0 + k * 0.32 + 0.3, z - 0.03), m["walnut"], 0.01))
    parts.append(B("stair_stringer", (0.06, 5.6, 0.3), (-2.45, D - 8.5, mz / 2), m["black_steel"]))
    for k in range(3):
        parts.append(sofa(f"mezz_sofa{k}", (-24.0 + k * 6.5, D - 1.4, mz), 0.0, 2.4, m, m["fabric"]))
    # Plants + bench seating along the glass.
    for x in (-27.0, -9.5, 9.5, 29.0):
        parts += plant(f"plant{x}", (x, 1.4, 0.0), 1.9, m)
    marks.append(("door_in", (0.0, -1.0, 0.0), 0.0))
    return parts, nodes, marks, {"size": [W, D, H], "cars": ["stiletto", "vanta", "halcyon", "warden", "brute", "stiletto"]}


def v_kestrel(m):
    """Kestrel Motors: bright, friendly used-car showroom (80 x 30 footprint; we use 40 x 20)."""
    W, D, H = 40.0, 20.0, 6.0
    parts, nodes, marks = [], [], []
    parts += shell(m, W, D, H, m["floor_tile"], m["wall"])
    # Tile grid lines.
    for k in range(1, int(W / 1.0)):
        parts.append(B(f"grout_x{k}", (0.012, D, 0.003), (-W / 2 + k, D / 2, 0.001), m["fabric"]))
    for k in range(1, int(D / 1.0)):
        parts.append(B(f"grout_y{k}", (W, 0.012, 0.003), (0, k, 0.001), m["fabric"]))
    parts += curtain_wall("front", -W / 2, W / 2, 0.0, H, m, bay=2.5, door=(-12.0, 2.4, 2.6), transom=2.8)
    nodes += sliding_doors("door", -12.0, 0.0, 2.2, 2.6, m)
    # Brand band: teal wall + yellow stripe, big logo.
    parts.append(B("brand_wall", (W, 0.05, 2.2), (0, D - 0.03, H - 1.1), m["kestrel_teal"]))
    parts.append(B("brand_stripe", (W, 0.06, 0.25), (0, D - 0.04, H - 2.3), m["kestrel_yellow"]))
    parts.append(text("logo", "KESTREL MOTORS", (0, D - 0.1, H - 1.0), 1.0, m["white"], "Righteous-Regular.ttf", 0.05))
    parts.append(text("tag", "QUALITY USED CARS  ·  PART EX WELCOME  ·  FINANCE AVAILABLE", (0, D - 0.1, H - 2.65), 0.32, m["kestrel_teal"], "Oswald.ttf", 0.01))
    # Ceiling panels.
    for ix in range(-3, 4):
        for iy in range(1, 4):
            parts.append(B(f"panel{ix}{iy}", (1.2, 1.2, 0.03), (ix * 5.5, iy * 5.0, H - 0.02), m["led"]))
    # Bunting.
    for row in range(3):
        y = 4.0 + row * 5.0
        for k in range(30):
            x = -W / 2 + 1.0 + k * 1.3
            sag = -0.35 * math.sin(math.pi * (k % 10) / 10)
            f = bc.loft(f"flag{row}{k}", [[Vector((x - 0.2, y, H - 0.4 + sag)), Vector((x + 0.2, y, H - 0.4 + sag)), Vector((x, y, H - 0.85 + sag))],
                                          [Vector((x - 0.2, y + 0.005, H - 0.4 + sag)), Vector((x + 0.2, y + 0.005, H - 0.4 + sag)), Vector((x, y + 0.005, H - 0.85 + sag))]],
                        [m["kestrel_yellow"], m["kestrel_teal"], m["red"], m["white"]][k % 4], cap=True)
            parts.append(f)
    # Five cars in a row with windscreen price boards; desk + waiting area.
    for k in range(5):
        cx = -14.0 + k * 6.5
        marks.append((f"car_{k}", (cx, 9.5, 0.0), math.radians(-90 + (8 if k % 2 else -8))))
        parts.append(B(f"price_stand{k}", (0.6, 0.05, 0.9), (cx + 1.8, 7.0, 0.85), m["white"], 0.02))
        parts.append(B(f"price_band{k}", (0.6, 0.06, 0.18), (cx + 1.8, 7.0, 1.2), m["kestrel_yellow"], 0.01))
        parts.append(C(f"price_post{k}", 0.025, 0.4, (cx + 1.8, 7.0, 0.0), m["steel"], 8))
        marks.append((f"spot_car_{k}", (cx + 1.8, 6.2, 0.0), 0.0))
    parts.append(B("sales_desk", (3.0, 0.9, 0.75), (13.0, 16.0, 0.375), m["white"], 0.02))
    parts.append(B("sales_desk_front", (3.0, 0.05, 0.6), (13.0, 15.53, 0.4), m["kestrel_teal"]))
    parts.append(B("sales_screen", (0.55, 0.03, 0.35), (13.0, 16.2, 0.98), m["screen"]))
    parts.append(office_chair("sales_chair", (13.0, 16.8, 0), math.pi, m))
    for s in (-1, 1):
        parts.append(office_chair(f"client{s}", (13.0 + s * 0.6, 15.0, 0), 0.0, m))
    marks.append(("npc_sales_0", (13.0, 16.7, 0.0), math.pi))
    marks.append(("spot_sales_0", (13.0, 14.6, 0.0), 0.0))
    parts.append(sofa("wait_sofa", (-14.0, 18.6, 0), 0.0, 2.6, m, m["fabric"]))
    parts.append(B("wait_table", (1.1, 0.6, 0.4), (-14.0, 17.4, 0.2), m["oak"], 0.02))
    parts.append(B("coffee_machine", (0.5, 0.45, 0.6), (-10.5, 19.3, 1.25), m["black_steel"], 0.02))
    parts.append(B("coffee_counter", (1.6, 0.6, 0.95), (-10.5, 19.3, 0.475), m["kestrel_teal"], 0.02))
    nodes.append(roller_door("roller", 15.0, 0.05, 4.0, 3.2, m))
    for x in (-19.0, 4.0, 19.0):
        parts += plant(f"plant{x}", (x, 1.0, 0.0), 1.5, m)
    return parts, nodes, marks, {"size": [W, D, H], "cars": ["kestrel", "scout", "civ_sedan", "civ_compact", "civ_suv"]}


ARDEN_COLS = [(0.05, 0.05, 0.06), (0.75, 0.7, 0.6), (0.2, 0.25, 0.32), (0.55, 0.42, 0.3), (0.9, 0.88, 0.84), (0.32, 0.08, 0.1), (0.15, 0.22, 0.17)]
THREAD_COLS = [(0.85, 0.2, 0.15), (0.1, 0.3, 0.65), (0.95, 0.85, 0.2), (0.12, 0.12, 0.12), (0.9, 0.9, 0.9), (0.3, 0.6, 0.35), (0.95, 0.5, 0.2), (0.6, 0.6, 0.62)]


def v_arden(m):
    """Maison Arden: 50 x 28 footprint; boutique floor 24 x 16, 5 m ceiling, warm stone and brass."""
    W, D, H = 24.0, 16.0, 5.0
    parts, nodes, marks = [], [], []
    parts += shell(m, W, D, H, m["floor_stone"], m["wall_warm"])
    parts += curtain_wall("front", -W / 2, W / 2, 0.0, H, m, bay=3.0, door=(0.0, 2.0, 3.0), transom=3.2)
    nodes += sliding_doors("door", 0.0, 0.0, 1.8, 3.0, m)
    # Arched niches along both side walls with brass rails.
    for s in (-1, 1):
        for k in range(4):
            y = 3.0 + k * 3.0
            x = s * (W / 2 - 0.25)
            parts.append(B(f"niche{s}{k}", (0.1, 2.4, 3.4), (x + s * 0.02, y, 1.7), m["wall"], 0.0))
            arch = bc.body(f"arch{s}{k}", {"y0": y - 1.2, "y1": y + 1.2, "n_st": 16, "z": 3.4, "ends": False,
                                           "w": 0.06, "top": [(y - 1.2, 0.02), (y, 0.9), (y + 1.2, 0.02)], "bot": 0.02, "n": 2.0}, m["wall"], segs=8)
            arch.location.x = x + s * 0.02
            parts.append(arch)
            parts.append(B(f"niche_led{s}{k}", (0.02, 2.3, 0.03), (x - s * 0.05, y, 3.3), m["led_gold"]))
            # Rails run along y here: build manually.
            r = bc.tube(f"rail_bar{s}{k}", [(x - s * 0.3, y - 1.0, 1.75), (x - s * 0.3, y + 1.0, 1.75)], 0.015, m["brass"], 8)
            parts.append(r)
            for j in range(12):
                g = garment_hanging(f"g{s}{k}{j}", x - s * 0.3, y - 0.9 + j * 0.165, 1.75, ARDEN_COLS[(j + k) % len(ARDEN_COLS)], long=k % 2 == 0, m=m)
                g.rotation_euler = (0, 0, 0.04 * (1 if j % 2 else -1))
                parts.append(g)
    # Centre: two display tables of folded knitwear, mannequins on a stone plinth.
    parts.append(folded_table("table_a", (-3.0, 6.0, 0), 2.4, 1.2, m, ARDEN_COLS, m["walnut"]))
    parts.append(folded_table("table_b", (3.0, 6.0, 0), 2.4, 1.2, m, ARDEN_COLS[3:] + ARDEN_COLS[:3], m["walnut"]))
    parts.append(C("plinth", 1.6, 0.25, (0, 2.9, 0), m["marble"], 48))
    looks = [((0.1, 0.12, 0.18), (0.75, 0.7, 0.6)), ((0.75, 0.7, 0.6), (0.05, 0.05, 0.06)), ((0.32, 0.08, 0.1), (0.2, 0.25, 0.32))]
    for k, (top, bot) in enumerate(looks):
        a = -0.9 + k * 0.9
        parts.append(mannequin(f"mq{k}", (math.sin(a) * 0.9, 2.9 + math.cos(a) * 0.5 - 0.3, 0.25), math.pi + a * 0.4, m, top, bot, pose=0.4 - k * 0.3))
        marks.append((f"spot_look_{k}", (math.sin(a) * 1.4, 1.3, 0.0), 0.0))
    # Chandelier ring.
    parts += spot_ring("chandelier", (0, 6.0), 2.2, H - 0.6, 24, {**m, "black_steel": m["brass"]})
    # Back: watch & jewellery counter (glass cases), cash desk, shoe wall, fitting rooms.
    parts.append(B("watch_counter", (4.0, 0.7, 0.9), (-5.5, 11.5, 0.45), m["walnut"], 0.02))
    parts.append(B("watch_case", (3.8, 0.6, 0.25), (-5.5, 11.5, 1.03), m["glass"]))
    parts.append(B("watch_led", (3.8, 0.55, 0.01), (-5.5, 11.5, 0.91), m["led"]))
    for k in range(8):
        parts.append(C(f"watch{k}", 0.05, 0.012, (-7.1 + k * 0.45, 11.5, 0.92), m["gold"], 16))
    marks.append(("spot_watches", (-5.5, 10.6, 0.0), 0.0))
    parts.append(B("cash_desk", (3.0, 0.8, 1.0), (5.5, 12.0, 0.5), m["marble"], 0.02))
    parts.append(B("cash_desk_band", (3.02, 0.82, 0.06), (5.5, 12.0, 0.25), m["brass"]))
    parts.append(B("till", (0.4, 0.3, 0.3), (5.0, 12.1, 1.15), m["screen_off"], 0.02))
    parts.append(text("bag_logo", "MAISON ARDEN", (5.5, 11.58, 0.62), 0.16, m["gold"], "PlayfairDisplay.ttf", 0.004))
    marks.append(("npc_cashier", (5.5, 12.8, 0.0), math.pi))
    marks.append(("spot_till", (5.5, 11.0, 0.0), 0.0))
    # Shoe wall: back wall, lit shelves.
    for row in range(5):
        z = 0.5 + row * 0.42
        parts.append(B(f"shoe_shelf{row}", (6.0, 0.35, 0.03), (0.0, D - 0.2, z), m["walnut"]))
        parts.append(B(f"shoe_led{row}", (6.0, 0.02, 0.02), (0.0, D - 0.05, z + 0.38), m["led_gold"]))
        for k in range(9):
            parts.append(shoe(f"shoe{row}{k}", (-2.6 + k * 0.65, D - 0.22, z + 0.015), [(0.05, 0.04, 0.03), (0.4, 0.22, 0.1), (0.9, 0.88, 0.85), (0.15, 0.1, 0.08)][(row + k) % 4], math.pi / 2))
    marks.append(("spot_shoes", (0.0, D - 1.6, 0.0), 0.0))
    parts.append(chair_lounge("shoe_seat", (0.0, D - 3.0, 0.0), math.pi, m, m["velvet"]))
    # Fitting rooms (right back): three cubicles, velvet curtains, a big mirror outside.
    for k in range(3):
        x = 8.2 + k * 1.3
        parts.append(B(f"fit_wall{k}", (0.06, 1.6, 2.4), (x - 0.65, D - 0.8, 1.2), m["walnut"]))
        cur = bc.loft(f"curtain{k}", [[Vector((x - 0.6 + 0.04 * j, D - 1.6 + 0.04 * math.sin(j * 1.3), z)) for j in range(29)] +
                                      [Vector((x - 0.6 + 0.04 * j, D - 1.6 + 0.04 * math.sin(j * 1.3) + 0.01, z)) for j in reversed(range(29))]
                                      for z in (0.05, 2.35)], m["velvet"], cap=False)
        parts.append(cur)
        parts.append(B(f"fit_mirror{k}", (1.0, 0.03, 1.9), (x, D - 0.05, 1.2), m["mirror"]))
    parts.append(B("fit_wall_end", (0.06, 1.6, 2.4), (8.2 + 3 * 1.3 - 0.65, D - 0.8, 1.2), m["walnut"]))
    parts.append(B("fit_header", (4.0, 1.6, 0.1), (9.5, D - 0.8, 2.45), m["walnut"]))
    parts.append(B("big_mirror", (1.4, 0.05, 2.4), (W / 2 - 0.4, 8.5, 1.3), m["mirror"]))
    parts.append(B("big_mirror_frame", (1.5, 0.04, 2.5), (W / 2 - 0.35, 8.5, 1.3), m["brass"]))
    marks.append(("spot_fitting", (9.5, D - 2.4, 0.0), 0.0))
    parts.append(text("logo", "MAISON ARDEN", (0, D - 0.18, 3.9), 0.62, m["gold"], "PlayfairDisplay.ttf", 0.03))
    for x in (-10.5, 10.5):
        parts += plant(f"plant{x}", (x, 1.1, 0.0), 1.8, m)
    return parts, nodes, marks, {"size": [W, D, H]}


def v_threadline(m):
    """Threadline: 46 x 24 footprint, floor 22 x 14, bright everyday store."""
    W, D, H = 22.0, 14.0, 4.6
    parts, nodes, marks = [], [], []
    parts += shell(m, W, D, H, m["floor_light"], m["wall"])
    parts += curtain_wall("front", -W / 2, W / 2, 0.0, H, m, bay=2.75, door=(0.0, 2.4, 2.8), transom=3.0)
    nodes += sliding_doors("door", 0.0, 0.0, 2.2, 2.8, m)
    parts += ceiling_light_lines("lines", -W / 2 + 1, W / 2 - 1, 2.0, D - 1.0, H, 2.0, m["led_cool"], along="x", w=0.08)
    parts.append(text("logo", "threadline", (0, D - 0.18, 3.3), 0.9, m["red"], "Pacifico-Regular.ttf", 0.04))
    # Wall bays: rails + face-outs + shelves of folds.
    for s in (-1, 1):
        x = s * (W / 2 - 0.3)
        for k in range(4):
            y = 2.0 + k * 2.8
            parts.append(B(f"bay_back{s}{k}", (0.05, 2.6, 2.4), (x + s * 0.2, y, 1.4), m["oak"]))
            parts.append(bc.tube(f"bay_rail{s}{k}", [(x - s * 0.15, y - 1.2, 1.5), (x - s * 0.15, y + 1.2, 1.5)], 0.014, m["steel"], 8))
            for j in range(13):
                parts.append(garment_hanging(f"tg{s}{k}{j}", x - s * 0.15, y - 1.1 + j * 0.18, 1.5, THREAD_COLS[(j * 3 + k) % len(THREAD_COLS)], m=m))
            parts.append(B(f"bay_shelf{s}{k}", (0.4, 2.4, 0.03), (x - s * 0.05, y, 2.1), m["oak"]))
            for j in range(5):
                for lvl in range(3):
                    parts.append(B(f"tf{s}{k}{j}{lvl}", (0.3, 0.34, 0.045), (x - s * 0.05, y - 0.95 + j * 0.47, 2.14 + lvl * 0.046), cloth(THREAD_COLS[(j + k + lvl) % len(THREAD_COLS)]), 0.01))
    # Centre floor: round rails, tables, mannequins on a low stage at the front.
    for k, (cx, cy) in enumerate([(-4.0, 6.0), (4.0, 6.0), (0.0, 9.5)]):
        parts.append(bc.tube(f"round{k}", [(cx + math.cos(TAU * j / 32) * 0.7, cy + math.sin(TAU * j / 32) * 0.7, 1.35) for j in range(33)], 0.014, m["steel"], 6))
        parts.append(C(f"round_post{k}", 0.02, 1.35, (cx, cy, 0), m["steel"], 8))
        parts.append(C(f"round_base{k}", 0.3, 0.03, (cx, cy, 0), m["steel"], 16))
        for j in range(20):
            a = TAU * j / 20
            g = garment_hanging(f"rg{k}{j}", cx + math.cos(a) * 0.7, cy + math.sin(a) * 0.7, 1.35, THREAD_COLS[(j + k) % len(THREAD_COLS)], m=m)
            g.rotation_euler = (0, 0, a)
            parts.append(g)
    parts.append(folded_table("table", (0.0, 4.6, 0), 2.6, 1.1, m, THREAD_COLS, m["oak"]))
    # Window stages either side of the entrance (a clear aisle in from the door).
    for sx in (-1, 1):
        parts.append(B(f"stage{sx}", (5.0, 1.4, 0.2), (sx * 5.5, 1.3, 0.1), m["oak"], 0.02))
        for k in range(2):
            j = k + (0 if sx < 0 else 2)
            parts.append(mannequin(f"mq{j}", (sx * (4.4 + k * 2.2), 1.3, 0.2), math.pi, m, THREAD_COLS[j * 2 % 8], THREAD_COLS[(j * 2 + 3) % 8], pose=0.3 * (1 if k % 2 else -1)))
    parts.append(B("cash_desk", (3.2, 0.8, 1.0), (6.5, D - 1.5, 0.5), m["white"], 0.02))
    parts.append(B("cash_band", (3.22, 0.82, 0.12), (6.5, D - 1.5, 0.92), m["red"]))
    marks.append(("npc_cashier", (6.5, D - 0.8, 0.0), math.pi))
    marks.append(("spot_till", (6.5, D - 2.5, 0.0), 0.0))
    for k in range(3):
        x = -8.0 + k * 1.4
        parts.append(B(f"fit_wall{k}", (0.06, 1.5, 2.3), (x - 0.7, D - 0.75, 1.15), m["white"]))
        parts.append(B(f"fit_curtain{k}", (1.3, 0.04, 2.1), (x, D - 1.5, 1.15), m["fabric"]))
    parts.append(B("fit_wall_end", (0.06, 1.5, 2.3), (-8.0 + 3 * 1.4 - 0.7, D - 0.75, 1.15), m["white"]))
    marks.append(("spot_fitting", (-6.6, D - 2.6, 0.0), 0.0))
    return parts, nodes, marks, {"size": [W, D, H]}


def lift_car(m, w=1.6, d=1.5, h=2.4):
    """The lift car (node LiftCar, origin = floor centre). Doors face -y."""
    parts = [B("car_floor", (w, d, 0.06), (0, d / 2, -0.03), m["marble_dark"]),
             B("car_ceiling", (w, d, 0.06), (0, d / 2, h + 0.03), m["steel"]),
             B("car_light", (w - 0.3, d - 0.3, 0.01), (0, d / 2, h - 0.005), m["led"]),
             B("car_back", (w, 0.04, h), (0, d, h / 2), m["mirror"]),
             B("car_l", (0.04, d, h), (-w / 2, d / 2, h / 2), m["steel"]),
             B("car_r", (0.04, d, h), (w / 2, d / 2, h / 2), m["steel"]),
             B("car_front_l", (0.3, 0.04, h), (-w / 2 + 0.15, 0.0, h / 2), m["steel"]),
             B("car_front_r", (0.3, 0.04, h), (w / 2 - 0.15, 0.0, h / 2), m["steel"]),
             B("car_front_top", (w, 0.04, 0.3), (0, 0.0, h - 0.15), m["steel"]),
             bc.tube("handrail", [(-w / 2 + 0.06, 0.2, 0.92), (-w / 2 + 0.06, d - 0.06, 0.92), (w / 2 - 0.06, d - 0.06, 0.92), (w / 2 - 0.06, 0.2, 0.92)], 0.018, m["brass"], 8),
             B("panel", (0.02, 0.32, 0.9), (w / 2 - 0.03, 0.4, 1.25), m["black_steel"]),
             B("indicator", (0.5, 0.02, 0.12), (0, 0.025, h - 0.2), m["screen_off"])]
    for k in range(8):
        parts.append(C(f"btn{k}", 0.022, 0.01, (0, 0, 0), m["btn"], 12))
        parts[-1].rotation_euler = (0, math.pi / 2, 0)
        parts[-1].location = (w / 2 - 0.045, 0.32 + (k % 2) * 0.12, 0.95 + (k // 2) * 0.13)
    parts.append(text("floor_no", "12", (0, 0.0, h - 0.2), 0.08, m["led_gold"], "Oswald.ttf", 0.003))
    car = kit.join("LiftCar", parts)
    doors = []
    for s, nm in ((-1, "L"), (1, "R")):
        dd = B(f"CarDoor_{nm}", (w / 2 - 0.15, 0.03, h - 0.3), (s * ((w - 0.6) / 4), -0.02, (h - 0.3) / 2), m["steel"])
        doors.append(dd)
    return car, doors


def v_lobby(m):
    """Residential lobby: street door, concierge, mailboxes, lift landing and the lift.
    Front (street) at y 0. Room 12 x 10, 4.2 m; lift shaft on the back wall."""
    W, D, H = 12.0, 10.0, 4.2
    parts, nodes, marks = [], [], []
    parts += shell(m, W, D, H, m["marble"], m["wall_warm"])
    # Floor inlay: dark border + brass lines.
    parts.append(B("inlay", (8.0, 6.0, 0.005), (0, 4.8, 0.002), m["marble_dark"]))
    parts.append(B("inlay2", (7.6, 5.6, 0.006), (0, 4.8, 0.003), m["marble"]))
    for k in range(-1, 2):
        parts.append(B(f"brass_line{k}", (0.03, 5.6, 0.007), (k * 2.0, 4.8, 0.004), m["brass"]))
    # Street front: stone portal, glass pivot door with a canopy.
    parts.append(B("front_wall_l", (4.6, 0.4, H), (-W / 2 + 2.3, -0.2, H / 2), m["wall_warm"]))
    parts.append(B("front_wall_r", (4.6, 0.4, H), (W / 2 - 2.3, -0.2, H / 2), m["wall_warm"]))
    parts.append(B("front_head", (2.8, 0.4, H - 3.0), (0, -0.2, 3.0 + (H - 3.0) / 2), m["wall_warm"]))
    parts.append(B("portal", (3.2, 0.5, 3.3), (0, -0.25, 1.65), m["marble_dark"], 0.02))
    parts.append(B("portal_cut", (2.6, 0.6, 3.0), (0, -0.25, 1.5), m["glass"]))
    nodes += sliding_doors("door", 0.0, -0.3, 2.4, 3.0, m)
    parts.append(B("canopy", (4.0, 1.6, 0.14), (0, -1.1, 3.4), m["black_steel"], 0.02))
    parts.append(B("canopy_led", (3.8, 0.02, 0.02), (0, -1.88, 3.33), m["led"]))
    parts.append(text("house_no", "No. 1  THE HARBOUR RESIDENCES", (0, -1.92, 3.42), 0.14, m["brass"], "Oswald.ttf", 0.004))
    marks.append(("door_in", (0, -2.0, 0.0), 0.0))
    # Concierge desk (left), mailboxes (right wall), seating, plants, pendant lights.
    parts.append(bc.body("concierge", {"y0": 3.0, "y1": 6.0, "n_st": 12, "x": -3.8, "z": 0.55, "ends": False,
                                       "w": [(3.0, 0.45), (4.5, 0.55), (6.0, 0.45)], "top": 0.55, "bot": 0.55, "n": 5.0}, m["walnut"], segs=16))
    parts.append(B("concierge_top", (1.3, 3.2, 0.05), (-3.8, 4.5, 1.12), m["marble"], 0.02))
    parts.append(B("concierge_led", (0.02, 3.0, 0.02), (-3.2, 4.5, 0.05), m["led_gold"]))
    parts.append(B("concierge_screen", (0.03, 0.5, 0.32), (-4.1, 4.5, 1.32), m["screen"]))
    marks.append(("npc_concierge", (-4.7, 4.5, 0.0), -math.pi / 2))
    marks.append(("spot_concierge", (-2.6, 4.5, 0.0), 0.0))
    for r in range(5):
        for c in range(6):
            parts.append(B(f"mailbox{r}{c}", (0.05, 0.36, 0.26), (W / 2 - 0.03, 2.6 + c * 0.38, 0.8 + r * 0.28), m["brass"], 0.005))
            parts.append(B(f"mailslot{r}{c}", (0.06, 0.2, 0.02), (W / 2 - 0.05, 2.6 + c * 0.38, 0.86 + r * 0.28), m["black_steel"]))
    marks.append(("spot_mail", (W / 2 - 1.0, 3.6, 0.0), 0.0))
    parts.append(sofa("lobby_sofa", (3.5, 7.0, 0), -math.pi / 2, 2.2, m, m["velvet"]))
    parts.append(B("lobby_table", (0.6, 1.2, 0.4), (2.4, 7.0, 0.2), m["marble_dark"], 0.03))
    for x in (-5.2, 5.2):
        parts += plant(f"plant{x}", (x, 1.0, 0.0), 2.0, m)
    for k, (px, py) in enumerate([(-2.0, 3.0), (2.0, 3.0), (0.0, 6.0)]):
        parts.append(bc.tube(f"pend_wire{k}", [(px, py, H), (px, py, H - 1.1)], 0.006, m["black_steel"], 4))
        parts.append(kit.sphere(f"pend{k}", 0.22, (px, py, H - 1.25), m["led_gold"], 16, 10))
    # Lift landing (back wall centre): stone surround, brass doors, call button, floor display.
    ly = D
    parts.append(B("lift_surround", (2.6, 0.12, 3.0), (0, ly - 0.06, 1.5), m["marble_dark"], 0.01))
    parts.append(B("lift_display", (0.5, 0.03, 0.14), (0, ly - 0.13, 2.65), m["screen_off"]))
    parts.append(text("lift_display_txt", "G", (0, ly - 0.15, 2.65), 0.1, m["led_gold"], "Oswald.ttf", 0.002))
    parts.append(B("call_plate", (0.12, 0.03, 0.26), (1.55, ly - 0.13, 1.2), m["brass"], 0.01))
    for k in range(2):
        b = C(f"call{k}", 0.025, 0.012, (0, 0, 0), m["btn"], 12)
        b.rotation_euler = (math.pi / 2, 0, 0)
        b.location = (1.55, ly - 0.15, 1.15 + k * 0.1)
        parts.append(b)
    for s, nm in ((-1, "L"), (1, "R")):
        dd = B(f"LiftDoor_{nm}", (0.8, 0.04, 2.4), (s * 0.4, ly - 0.16, 1.2), m["brass"], 0.005)
        nodes.append(dd)
    marks.append(("spot_lift_call", (1.2, ly - 0.9, 0.0), 0.0))
    # Shaft behind the landing + the car (sat at the ground floor).
    parts.append(B("shaft_back", (2.2, 0.2, 40.0), (0, ly + 1.9, 20.0), m["black_steel"]))
    parts.append(B("shaft_l", (0.2, 1.9, 40.0), (-1.1, ly + 0.95, 20.0), m["black_steel"]))
    parts.append(B("shaft_r", (0.2, 1.9, 40.0), (1.1, ly + 0.95, 20.0), m["black_steel"]))
    for s in (-1, 1):
        parts.append(B(f"guide{s}", (0.06, 0.1, 40.0), (s * 0.95, ly + 0.95, 20.0), m["steel"]))
    car, doors = lift_car(m)
    car.location = (0, ly + 0.15, 0.0)
    for dd in doors:
        dd.location = (dd.location.x, ly + 0.15 + dd.location.y, dd.location.z)
    nodes += [car] + doors
    marks.append(("lift_car_floor", (0, ly + 0.9, 0.0), 0.0))
    return parts, nodes, marks, {"size": [W, D, H], "lift": {"shaft": [0, ly + 0.95], "car_w": 1.6, "car_d": 1.5}}


def v_study(m):
    """Apartment study / Empire Desk (a 7 x 6 room with a window wall to the city)."""
    W, D, H = 7.0, 6.0, 3.0
    parts, nodes, marks = [], [], []
    parts += shell(m, W, D, H, m["floor_oak"], m["wall"])
    # Window wall (front, y 0) floor to ceiling.
    parts += curtain_wall("window", -W / 2, W / 2, 0.0, H, m, bay=1.75)
    # Desk facing the window: walnut slab, three screens, laptop, lamp, chair.
    parts.append(B("desk_top", (2.6, 1.0, 0.05), (0, 1.6, 0.76), m["walnut"], 0.01))
    for s in (-1, 1):
        parts.append(B(f"desk_leg{s}", (0.05, 0.9, 0.74), (s * 1.2, 1.6, 0.37), m["black_steel"]))
    for k, (x, rz) in enumerate([(-0.75, 0.35), (0.0, 0.0), (0.75, -0.35)]):
        sc = B(f"monitor{k}", (0.68, 0.025, 0.4), (0, 0, 0), m["screen"])
        fr = B(f"monitor_fr{k}", (0.7, 0.03, 0.42), (0, 0.01, 0), m["black_steel"])
        mon = kit.join(f"monitor_j{k}", [sc, fr])
        mon.rotation_euler = (0, 0, rz)
        mon.location = (x, 1.35 if k == 1 else 1.42, 1.15)
        parts.append(mon)
        parts.append(C(f"monitor_stand{k}", 0.02, 0.3, (x, 1.4, 0.79), m["steel"], 8))
    parts.append(B("laptop_base", (0.34, 0.24, 0.015), (0.0, 1.85, 0.79), m["steel"], 0.005))
    parts.append(B("keyboard", (0.45, 0.14, 0.015), (-0.3, 1.85, 0.79), m["black_steel"], 0.004))
    parts.append(office_chair("desk_chair", (0, 2.5, 0), 0.0, m))
    marks.append(("spot_empire_desk", (0, 2.6, 0.0), math.pi))
    # Recruitment board (left wall): cork + pinned CV cards; trophy wall (right).
    parts.append(B("board", (0.04, 2.4, 1.2), (-W / 2 + 0.05, 3.2, 1.55), m["oak"]))
    for k in range(10):
        parts.append(B(f"cv{k}", (0.01, 0.3, 0.38), (-W / 2 + 0.08, 2.2 + (k % 5) * 0.48, 1.25 + (k // 5) * 0.55), m["paper"]))
    parts.append(text("board_title", "HIRING", (-W / 2 + 0.09, 3.2, 2.3), 0.16, m["walnut"], "Oswald.ttf", 0.003, rot=(math.pi / 2, 0, math.pi / 2)))
    marks.append(("spot_recruitment", (-W / 2 + 1.0, 3.2, 0.0), -math.pi / 2))
    for r in range(3):
        parts.append(B(f"trophy_shelf{r}", (0.3, 2.4, 0.03), (W / 2 - 0.16, 3.2, 1.0 + r * 0.55), m["walnut"]))
        parts.append(B(f"trophy_led{r}", (0.02, 2.3, 0.02), (W / 2 - 0.05, 3.2, 1.5 + r * 0.55), m["led_gold"]))
        for k in range(4):
            y = 2.3 + k * 0.6
            if (r + k) % 3 == 0:
                parts.append(C(f"cup{r}{k}", 0.08, 0.28, (W / 2 - 0.16, y, 1.02 + r * 0.55), m["gold"], 16, 0.12))
            elif (r + k) % 3 == 1:
                parts.append(B(f"plaque{r}{k}", (0.04, 0.3, 0.38), (W / 2 - 0.2, y, 1.21 + r * 0.55), m["walnut"], 0.01))
            else:
                parts.append(kit.sphere(f"globe{r}{k}", 0.1, (W / 2 - 0.16, y, 1.13 + r * 0.55), m["brass"], 12, 8))
    marks.append(("spot_trophies", (W / 2 - 1.0, 3.2, 0.0), math.pi / 2))
    # Back wall: big TV (news / matchday), sofa, bookshelf.
    parts.append(B("tv", (2.2, 0.06, 1.25), (0, D - 0.08, 1.6), m["screen"]))
    parts.append(B("tv_frame", (2.25, 0.05, 1.3), (0, D - 0.04, 1.6), m["black_steel"]))
    parts.append(B("tv_unit", (2.8, 0.45, 0.45), (0, D - 0.25, 0.225), m["walnut"], 0.01))
    parts.append(sofa("study_sofa", (0, D - 2.1, 0), math.pi, 2.4, m, m["fabric_cream"]))
    marks.append(("spot_tv", (0, D - 2.6, 0.0), 0.0))
    parts.append(B("rug", (3.0, 2.2, 0.01), (0, D - 2.4, 0.005), m["carpet"]))
    for x in (-3.0, 3.0):
        parts += plant(f"plant{x}", (x, 0.7, 0.0), 1.4, m)
    return parts, nodes, marks, {"size": [W, D, H]}


def v_hq(m):
    """HQ floor in Meridian Tower: 30 x 20, 3.6 m; glass on three sides."""
    W, D, H = 30.0, 20.0, 3.6
    parts, nodes, marks = [], [], []
    parts += shell(m, W, D, H, m["carpet"], m["wall"])
    parts += curtain_wall("win_front", -W / 2, W / 2, 0.0, H, m, bay=1.5)
    parts += ceiling_light_lines("lines", -W / 2 + 1.5, W / 2 - 1.5, 2.0, D - 2.0, H, 3.0, m["led"], along="x", w=0.1)
    # Reception by the lifts (back right) with your logo.
    parts.append(B("reception", (3.6, 0.9, 1.1), (10.0, D - 3.2, 0.55), m["white"], 0.03))
    parts.append(B("reception_top", (3.8, 1.0, 0.05), (10.0, D - 3.2, 1.12), m["marble_dark"], 0.01))
    parts.append(B("logo_wall", (6.0, 0.1, 2.8), (10.0, D - 0.1, 1.5), m["walnut"]))
    parts.append(text("logo", "YOUR EMPIRE", (10.0, D - 0.18, 1.9), 0.42, m["led_gold"], "Oswald.ttf", 0.03))
    marks.append(("npc_receptionist", (10.0, D - 2.4, 0.0), math.pi))
    marks.append(("spot_reception", (10.0, D - 4.4, 0.0), 0.0))
    for k in range(2):
        parts.append(B(f"lift{k}", (1.4, 0.08, 2.4), (13.0 + k * 0.0 - 6.6 + k * 1.8, D - 0.06, 1.2), m["steel"]))
    marks.append(("lift_landing", (7.3, D - 1.2, 0.0), 0.0))
    # Open plan: 4 rows x 4 bench desks with monitors and chairs.
    for r in range(3):
        for c in range(4):
            x, y = -12.0 + c * 3.4, 3.5 + r * 3.6
            parts.append(B(f"bench{r}{c}", (3.0, 1.6, 0.04), (x, y, 0.74), m["white"], 0.01))
            parts.append(B(f"bench_leg{r}{c}", (3.0, 0.05, 0.72), (x, y, 0.36), m["black_steel"]))
            parts.append(B(f"screen_div{r}{c}", (3.0, 0.03, 0.35), (x, y, 0.94), m["fabric"]))
            for s in (-1, 1):
                for j in (-1, 1):
                    parts.append(B(f"mon{r}{c}{s}{j}", (0.55, 0.02, 0.32), (x + j * 0.75, y + s * 0.22, 1.0), m["screen"]))
                    parts.append(office_chair(f"chair{r}{c}{s}{j}", (x + j * 0.75, y + s * 1.05, 0), 0.0 if s > 0 else math.pi, m))
                    marks.append((f"npc_desk_{r}{c}{s}{j}", (x + j * 0.75, y + s * 1.0, 0.0), 0.0 if s > 0 else math.pi))
    # Corner office (front right): glass partitions, big desk, Empire Desk spot.
    parts.append(B("co_glass_a", (8.0, 0.03, H), (11.0, 7.0, H / 2), m["glass_tint"]))
    parts.append(B("co_glass_b", (0.03, 7.0, H), (7.0, 3.5, H / 2), m["glass_tint"]))
    parts.append(B("co_door_frame", (1.0, 0.05, 2.3), (8.2, 7.0, 1.15), m["black_steel"]))
    parts.append(B("co_rug", (5.0, 4.0, 0.01), (11.5, 3.5, 0.005), m["fabric_cream"]))
    parts.append(B("co_desk", (2.6, 1.1, 0.05), (11.5, 4.5, 0.76), m["walnut"], 0.01))
    parts.append(B("co_desk_body", (2.4, 0.9, 0.7), (11.5, 4.6, 0.37), m["walnut"], 0.01))
    parts.append(B("co_monitor", (1.0, 0.03, 0.55), (11.5, 4.9, 1.15), m["screen"]))
    parts.append(office_chair("co_chair", (11.5, 5.6, 0), math.pi, m))
    for s in (-1, 1):
        parts.append(chair_lounge(f"co_guest{s}", (11.5 + s * 0.7, 3.2, 0), 0.0, m, m["leather"]))
    marks.append(("spot_empire_desk", (11.5, 5.3, 0.0), math.pi))
    # Boardroom (front left): glass box, long table, 12 chairs, wall screen.
    parts.append(B("br_glass_a", (8.0, 0.03, H), (-11.0, 7.0, H / 2), m["glass_tint"]))
    parts.append(B("br_glass_b", (0.03, 7.0, H), (-7.0, 3.5, H / 2), m["glass_tint"]))
    parts.append(B("br_table", (5.0, 1.6, 0.06), (-11.0, 3.6, 0.75), m["walnut"], 0.03))
    parts.append(B("br_table_base", (3.0, 0.6, 0.72), (-11.0, 3.6, 0.36), m["black_steel"]))
    for k in range(6):
        for s in (-1, 1):
            parts.append(office_chair(f"br_chair{k}{s}", (-13.1 + k * 0.85, 3.6 + s * 1.1, 0), 0.0 if s < 0 else math.pi, m))
    parts.append(B("br_screen", (0.05, 2.4, 1.35), (-14.9, 3.6, 1.6), m["screen"]))
    marks.append(("spot_boardroom", (-8.4, 3.6, 0.0), math.pi / 2))
    # Empire map wall (back left): a huge screen with a lit map + a stand-up table.
    parts.append(B("map_wall", (8.0, 0.06, 2.5), (-9.0, D - 0.08, 1.6), m["screen"]))
    parts.append(B("map_frame", (8.2, 0.05, 2.7), (-9.0, D - 0.04, 1.6), m["black_steel"]))
    parts.append(B("map_table", (2.4, 1.2, 1.05), (-9.0, D - 2.6, 0.525), m["white"], 0.02))
    marks.append(("spot_map_wall", (-9.0, D - 3.6, 0.0), 0.0))
    for x in (-3.0, 3.0, 6.0):
        parts += plant(f"plant{x}", (x, D - 1.0, 0.0), 1.6, m)
    return parts, nodes, marks, {"size": [W, D, H]}



def v_craft_sales(m, aviation):
    W, D, H = (74.0, 42.0, 10.0) if aviation else (27.0, 46.0, 8.7)
    dark = m["wall_dark"] if aviation else m["wall"]
    floor = m["floor_stone"] if aviation else m["floor_oak"]
    trim = m["brass"] if aviation else m["steel"]
    ink = m["white"] if aviation else m["wall_dark"]
    parts = shell(m, W, D, H, floor, dark)
    glass_height = H - 1.65
    parts += curtain_wall("front", -W/2, W/2, .10, glass_height, m, bay=3.2,
                          door=(0, 4.8, 3.4), transom=3.5, mull=.13)
    parts += [
        B("fascia", (W+.55, .6, H-glass_height), (0, -.12, (H+glass_height)/2), dark),
        B("entrance_canopy", (9, 3.1, .28), (0, -1.36, 3.85), m["black_steel"], .035),
        B("entrance_lighting", (6, .09, .025), (0, -1.8, 3.70), m["led"]),
        B("threshold", (4.8, .8, .035), (0, .14, .016), m["rubber"]),
    ]
    nodes = sliding_doors("entrance_", 0, .14, 4.8, 3.4, m)
    # Broad ribs and recessed strips above the walkways, aligned with the bays.
    for y in range(4, int(D), 6):
        parts.append(B(f"beam_{y}", (W-.25, .28, .46), (0, y, H-.25), trim))
        parts.append(B(f"light_{y}", (W-3, .09, .025), (0, y, H-.49), m["led_cool"]))
    desk_x = W/2 - 5.0
    desk_y = 4.8 if aviation else 7.0
    parts += [
        B("reception", (4.6, .9, 1.05), (desk_x, desk_y, .52), m["walnut"], .05),
        B("desk_cap", (4.72, 1.04, .12), (desk_x, desk_y, 1.07), m["floor_stone"], .025),
        B("desk_inlay", (4.2, .035, .07), (desk_x, desk_y-.46, .73), trim),
        text("sales", "SALES", (desk_x, desk_y-.48, .45), .27, m["white"], "Oswald.ttf"),
        sofa("lounge", (-W/2+3.4, 5.5, 0), 0, 2.9, m, m["leather" if aviation else "fabric_cream"]),
        B("lounge_table", (1.5, .64, .46), (-W/2+3.4, 4.2, .23), m["walnut"], .04),
        text("rear_wordmark", "SKYPORT AVIATION" if aviation else "SKYPORT MARINA",
             (0, D-.07, H-2.3), 1.35, ink, "Oswald.ttf", .035),
    ]
    for x in (-W/2+1.25, W/2-1.25):
        parts += plant(f"palm_{x}", (x, 2.1, .05), 2.5, m)
    marks = [("spot_sales", (desk_x, desk_y-1.4, 0), 0)]
    if aviation:
        exhibits = [
            ("wren", -23, 13, 5.7, 10.2),
            ("kite", 0, 13, 6.0, 10.8),
            ("regent", 23, 15, 7.5, 13.8),
            ("skylark", -23, 31.5, 13.0, 10.2),
            ("merlin", 0, 32, 15.8, 12.4),
            ("aurora", 22, 30.2, 18.0, 20.8),
        ]
    else:
        exhibits = [
            ("dart", -7.5, 14, 3.8, 7.0),
            ("swift", -7.5, 30, 4.4, 10.0),
            ("majesty", 5.1, 25.4, 8.5, 30.6),
        ]
    for model, x, y, width, length in exhibits:
        parts += [
            B(f"{model}_inset", (width, length, .025), (x, y, .012), m["floor_light" if aviation else "floor_dark"], .008),
            B(f"{model}_edge", (width, .045, .022), (x, y-length/2+.07, .029), trim),
        ]
        if not aviation:
            # Short padded supports leave the hull shape visible from the aisle.
            for side in (-1, 1):
                parts.append(B(f"{model}_cradle_{side}", (width*.62, .38, .38),
                               (x, y+length*.20*side, .19), m["black_steel"], .04))
        marks += [
            (f"craft_{model}", (x, y, .04 if aviation else .55), 0),
            (f"inspect_{model}", (x-width*.33, y-length/2-.75, 0), 0),
        ]
    return parts, nodes, marks, {"size": [W, D, H]}


def v_aviation(m):
    return v_craft_sales(m, True)


def v_marina(m):
    return v_craft_sales(m, False)


VENUES = {"meridian": v_meridian, "kestrel": v_kestrel, "arden": v_arden, "threadline": v_threadline,
          "lobby": v_lobby, "study": v_study, "hq": v_hq, "aviation": v_aviation, "marina": v_marina}

CAR_TINTS = [(0.55, 0.03, 0.03), (0.02, 0.02, 0.025), (0.85, 0.85, 0.83), (0.06, 0.16, 0.36), (0.5, 0.5, 0.52), (0.85, 0.42, 0.05)]
OUTFITS = [((0.1, 0.12, 0.18), (0.2, 0.2, 0.22)), ((0.9, 0.9, 0.88), (0.1, 0.1, 0.12)), ((0.4, 0.15, 0.1), (0.75, 0.7, 0.6))]


# ---------------------------------------------------------------- build


def build(vid):
    global M_CACHE
    kit.reset()
    _cloth.clear()
    m = M()
    M_CACHE = m
    parts, nodes, marks, meta = VENUES[vid](m)
    static = kit.join("Venue", [p for p in parts if p is not None and p.type == "MESH"])
    for p in static.data.polygons:
        p.use_smooth = False
    empties = [empty(n, loc, rz) for n, loc, rz in marks]
    objs = [static] + nodes
    tris = bc.tri_count(objs)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs + empties:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, vid + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_materials="EXPORT")
    info = {"tris": tris, "size": meta["size"], "nodes": sorted(o.name for o in nodes),
            "marks": {n: [round(loc[0], 2), round(loc[2], 2), round(-loc[1], 2)] for n, loc, _ in marks}}
    print(f"VENUE {vid}: {tris} tris, {len(nodes)} nodes, {len(marks)} marks")
    if RENDER:
        render(vid, meta, marks, m)
    return info


def place_car(name, loc, rz, tint):
    p = os.path.join(ROOT, "assets", "vehicles", name + ".glb")
    if not os.path.exists(p):
        return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=p)
    new = [o for o in bpy.data.objects if o not in before]
    root = [o for o in new if o.parent is None]
    for o in root:
        o.rotation_mode = "XYZ"
        o.location = loc
        o.rotation_euler = (0, 0, rz)
    for o in new:
        if o.type != "MESH":
            continue
        for s in o.material_slots:
            if s.material and s.material.name.startswith("paint"):
                c = s.material.copy()
                c.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*tint, 1)
                c.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.15
                c.node_tree.nodes["Principled BSDF"].inputs["Coat Weight"].default_value = 1.0
                s.material = c
    # Wheels: the car GLBs are wheel-less bodies; add the shared wheel if present.
    dims = json.load(open(os.path.join(ROOT, "assets", "vehicles", "bodies.json"))).get(name)
    wp = os.path.join(ROOT, "assets", "vehicles", "wheel_five.glb")
    if dims and os.path.exists(wp):
        rot = __import__("mathutils").Matrix.Rotation(rz, 4, "Z")
        track = dims["W"] - dims["tyre_w"] - 0.05
        for x in (1, -1):
            for ay in dims["axles"]:
                before = set(bpy.data.objects)
                bpy.ops.import_scene.gltf(filepath=wp)
                w = [o for o in bpy.data.objects if o not in before and o.parent is None][0]
                w.rotation_mode = "XYZ"
                w.scale = (dims["tyre_w"] / 0.44, dims["wheel_r"], dims["wheel_r"])
                w.location = Vector(loc) + rot @ Vector((x * track / 2, ay, dims["wheel_r"]))
                w.rotation_euler = (0, 0, rz + (0 if x > 0 else math.pi))


def render(vid, meta, marks, m):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 40
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.render.resolution_x, sc.render.resolution_y = 1400, 820
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sun_elevation = math.radians(28)
    sky.sun_rotation = math.radians(200)
    nt.links.new(sky.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    nt.nodes["Background"].inputs["Strength"].default_value = 0.25
    W, D, H = meta["size"]
    # Hide the ceiling for no one: interior shots keep it. Lights: a grid of soft area lights.
    area_grid(-W / 2 + 2, W / 2 - 2, 2.0, D - 2.0, H - 0.25, max(3.0, min(W, D) / 4), 60 if H < 5 else 160, 1.2)
    cars = meta.get("cars", [])
    ci = 0
    for n, loc, rz in marks:
        if n.startswith("car_") and ci < len(cars):
            place_car(cars[ci], loc, rz, CAR_TINTS[ci % len(CAR_TINTS)])
            ci += 1
        elif n.startswith("npc_") and (not n.startswith("npc_desk") or hash(n) % 3 == 0):
            mannequin("p_" + n, (loc[0], loc[1], 0.0), rz, m, *OUTFITS[hash(n) % len(OUTFITS)], pose=0.2, female=hash(n) % 2 == 0)
    if vid == "meridian":
        light_rig((-19.0, 12.0), 4.4, 6.0, 6, 1200, spot=True)
    cam = bpy.data.cameras.new("cam")
    cam.lens = 22
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    views = {
        "meridian": [("entrance", (8.0, 1.2, 2.2), (-6.0, 18.0, 1.0)), ("gallery", (-11.0, 4.0, 3.2), (-20.0, 13.0, 0.6)), ("lounge", (12.0, 4.0, 2.0), (25.0, 18.0, 1.0))],
        "kestrel": [("entrance", (-17.0, 1.2, 2.0), (6.0, 14.0, 0.8)), ("desk", (5.0, 6.0, 1.8), (14.0, 17.0, 0.8))],
        "arden": [("entrance", (-3.0, 0.8, 1.8), (2.0, 12.0, 1.3)), ("back", (8.0, 6.0, 1.7), (-2.0, 14.5, 1.0))],
        "threadline": [("entrance", (-4.0, 0.8, 1.8), (2.0, 10.0, 1.2))],
        "lobby": [("door", (0.0, 0.6, 1.7), (0.5, 9.0, 1.4)), ("lift", (-1.5, 6.6, 1.6), (0.2, 10.5, 1.3)), ("street", (3.0, -7.0, 1.7), (0.0, 0.0, 2.0))],
        "study": [("desk", (-2.6, 4.8, 1.7), (0.3, 1.2, 0.9)), ("trophies", (-1.5, 1.5, 1.6), (3.0, 3.5, 1.4))],
        "hq": [("floor", (-13.0, 8.5, 1.8), (10.0, 6.0, 0.8)), ("office", (8.0, 6.5, 1.7), (12.0, 3.0, 0.9))],
    }[vid]
    for tag, eye, look in views:
        co.location = eye
        co.rotation_euler = (Vector(look) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(RENDER, f"{vid}_{tag}.png")
        bpy.ops.render.render(write_still=True)


def main():
    ids = [k for k in VENUES if not ONLY or k in ONLY]
    rp = os.path.join(OUT, "venues.json")
    report = json.load(open(rp)) if os.path.exists(rp) else {}
    for vid in ids:
        report[vid] = build(vid)
    json.dump(report, open(rp, "w"), indent=1, sort_keys=True)


main()
