"""Skyport Airport kit: every reusable airport prop as one object in one GLB.

Run:  blender -b --factory-startup --python tools/blender/build_skyport.py -- assets/models [preview.png]

Conventions (as build_kit.py): Blender Z-up / +Y forward = Godot Y-up / -Z
forward, base-centre origins, metres. Each object is ONE surface whose
colours are baked to vertex colours (SkyportKit / skyport_kit.gdshader):
  alpha 1.0 = matte paint, 0.6 = gloss (metal, screens off), 0.0 = lamp /
  light box / screen (emissive, brighter at night).
Glazing stays a second surface on material "kit_glass" (Godot swaps in the
airport's glass). Nothing here is textured: the whole kit costs no texture
memory and each prop instanced by a MultiMesh is one or two draw calls.

Objects (Godot name = object name):
  airside:  jet_bridge (hall face at y=0 → cab door at y=46), gse_tug,
            gse_cart, gse_belt, gse_pushback, gse_fuel, gse_catering,
            gse_bus, gse_stairs, gse_gpu, gse_follow, runway_light,
            taxi_light, approach_bar, stand_sign, windsock, radar_mast,
            radar_head, fence (4 m panel), fence_gate
  terminal: checkin_island (24 m), seat_row, shop_unit, cafe_unit,
            fids_board, security_lane, gate_desk, carousel,
            indoor_planter, trolley, trolley_bay, info_desk,
            entrance_pod
  landside: gantry_sign (spans 16 m), taxi_shelter, fuel_canopy,
            fuel_kiosk, rental_canopy, rental_booth, barrier,
            bus_stop_airport, flag_pole
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import build_kit as kit  # noqa: E402
from build_kit import box, cyl, join, mat, reset, sphere  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "assets/models"
PREVIEW = ARGS[1] if len(ARGS) > 1 else ""
kit.OUT = OUT
os.makedirs(OUT, exist_ok=True)

reset()
P = {}


def M(name, rgb, kind="matte"):
    """Kit colour. kind: matte | gloss | lamp | glass."""
    m = mat(name, rgb, 0.6 if kind == "matte" else 0.25, 0.0,
            emit=rgb if kind == "lamp" else None)
    m["kind"] = kind
    P[name] = m
    return m


def srgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


white = M("white", srgb("e9eaea"))
offwhite = M("offwhite", srgb("d8d6d0"))
grey = M("grey", srgb("8d9196"))
steel = M("steel", srgb("a9aeb3"), "gloss")
dark = M("dark", srgb("2a2d31"))
tyre = M("tyre", srgb("17181a"))
yellow = M("yellow", srgb("e7b520"))
orange = M("orange", srgb("e5661e"))
red = M("red", srgb("b8322a"))
navy = M("navy", srgb("1e2f42"))
blue = M("blue", srgb("2c5d9b"))
teal = M("teal", srgb("2e8c8a"))
seat = M("seat", srgb("3d4a5c"))
leather = M("leather", srgb("5a3b2a"))
wood = M("wood", srgb("a37a52"))
stone = M("stone", srgb("cfc9bd"))
floor_dark = M("floor_dark", srgb("4a4c50"))
green = M("green", srgb("3f6b34"))
leaf = M("leaf", srgb("2f5a2a"))
soil = M("soil", srgb("4b3726"))
rubber = M("rubber", srgb("222326"))
belt = M("belt", srgb("303236"))
canvas = M("canvas", srgb("44607e"))
lamp_warm = M("lamp_warm", srgb("ffe2b0"), "lamp")
lamp_white = M("lamp_white", srgb("f4f7ff"), "lamp")
lamp_blue = M("lamp_blue", srgb("3c78ff"), "lamp")
lamp_green = M("lamp_green", srgb("3ee07a"), "lamp")
lamp_red = M("lamp_red", srgb("ff3326"), "lamp")
lamp_amber = M("lamp_amber", srgb("ffb02a"), "lamp")
screen = M("screen", srgb("2a4f7a"), "lamp")
sign_yellow = M("sign_yellow", srgb("f2c230"), "lamp")
sign_panel = M("sign_panel", srgb("1b2a3a"), "gloss")
glass = M("kit_glass", srgb("8fb0bd"), "glass")


def B(size, loc, m, bevel=0.0):
    return box("p", size, loc, m, bevel=bevel, segs=1)


def C(r, h, loc, m, verts=12, r2=None, axis="z"):
    ob = cyl("c", r, h, loc, m, verts, r2=r2)
    if axis != "z":
        # Rotate about its own centre (the helper puts the base at loc).
        me = ob.data
        c = Vector(loc) + Vector((0, 0, h / 2))
        rot = {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0)}[axis]
        from mathutils import Euler
        mx = Euler(rot).to_matrix()
        for v in me.vertices:
            v.co = mx @ (v.co - c) + c
    return ob


def wheel(x, y, r, w, m=tyre):
    return C(r, w, (x - w / 2, y, r), m, 12, axis="x")


def beam(a, b, w, h, m):
    """A box from point a to point b (w across, h up)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    L = d.length
    ob = B((w, L, h), (0, 0, 0), m)
    yaw = math.atan2(-d.x, d.y)
    pitch = math.atan2(d.z, math.hypot(d.x, d.y))
    from mathutils import Euler
    mx = Euler((pitch, 0, yaw), "XYZ").to_matrix()
    mid = (a + b) / 2
    for v in ob.data.vertices:
        v.co = mx @ v.co + mid
    return ob


OBJECTS = []


def done(name, parts):
    ob = join(name, parts)
    _bake(ob)
    OBJECTS.append(ob)
    return ob


def _bake(ob):
    """Material colours → vertex colours, one surface (+ glass)."""
    me = ob.data
    for m in list(me.materials):
        if m is None:
            continue
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    has_glass = False
    for poly in me.polygons:
        m = me.materials[poly.material_index] if me.materials else None
        if m is None:
            col = (1, 1, 1, 1)
        else:
            c = m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value
            a = {"matte": 1.0, "gloss": 0.6, "lamp": 0.0, "glass": 1.0}[m.get("kind", "matte")]
            col = (c[0], c[1], c[2], a)
            has_glass = has_glass or m.get("kind") == "glass"
        for li in poly.loop_indices:
            attr.data[li].color = col
    me.color_attributes.active_color = attr
    body = P.get("kit_body") or mat("kit_body", (1, 1, 1), 0.6)
    P["kit_body"] = body
    flags = [(me.materials[p.material_index].get("kind") == "glass") if me.materials else False for p in me.polygons]
    me.materials.clear()
    me.materials.append(body)
    if has_glass:
        me.materials.append(glass)
    for p, g in zip(me.polygons, flags):
        p.material_index = 1 if g else 0
        p.use_smooth = False


# ================================================================ airside
def jet_bridge():
    """Fixed link out of the hall (y 0..8), rotunda on its column at y 8,
    telescoping tunnel (two sections, glazed strip) to the cab at y 44..47,
    the drive column with its bogie under the outer tunnel. Floor at z 4.4."""
    p = []
    z = 4.4
    # Fixed glazed link.
    p.append(B((4.0, 8.0, 3.2), (0, 4.0, z + 1.6), offwhite))
    p.append(B((4.06, 7.6, 1.1), (0, 4.0, z + 1.9), glass))
    # Rotunda + column.
    p.append(C(3.0, 3.6, (0, 9.5, z - 0.2), offwhite, 16))
    p.append(C(3.1, 0.3, (0, 9.5, z + 3.4), grey, 16))
    p.append(C(0.7, z - 0.2, (0, 9.5, 0), grey, 10))
    p.append(C(1.6, 0.25, (0, 9.5, 0), dark, 10))
    # Tunnel: inner (wider) section, outer (narrower) section, ribs.
    p.append(B((3.6, 18.0, 3.1), (0, 21.5, z + 1.45), offwhite))
    p.append(B((3.3, 18.0, 2.8), (0, 37.0, z + 1.3), steel))
    for y in range(13, 46, 3):
        w = 3.72 if y < 31 else 3.42
        hh = 3.22 if y < 31 else 2.92
        p.append(B((w, 0.18, hh), (0, y, z + hh / 2 - 0.05), grey))
    # Glazed strip along both sides of the inner section.
    p.append(B((3.66, 17.0, 0.7), (0, 21.5, z + 2.0), glass))
    # Cab + bellows hood.
    p.append(B((4.6, 3.2, 3.3), (0.4, 46.6, z + 1.5), white))
    p.append(B((4.2, 0.8, 2.9), (0.4, 48.4, z + 1.5), rubber))
    p.append(B((4.62, 3.22, 0.5), (0.4, 46.6, z + 3.0), navy))
    # Drive column, bogie, wheels.
    for sx in (-1, 1):
        p.append(B((0.35, 0.35, z - 0.6), (sx * 1.0, 40.0, (z - 0.6) / 2 + 0.6), grey))
    p.append(B((3.2, 1.8, 0.7), (0, 40.0, 0.75), yellow))
    for sx in (-1.25, 1.25):
        p.append(wheel(sx, 40.0, 0.5, 0.45))
    # Service stair to the apron at the rotunda.
    for k in range(10):
        p.append(B((1.0, 0.32, 0.12), (3.4, 6.4 - k * 0.42, z - 0.44 * (k + 1) + 0.2), grey))
    p.append(beam((3.9, 7.0, z + 0.9), (3.9, 2.3, 0.9), 0.06, 0.06, yellow))
    # Gate number light box on the cab (the number is a Label3D in Godot).
    p.append(B((2.6, 0.1, 0.9), (0.4, 44.95, z + 3.9), lamp_white))
    p.append(B((2.8, 0.14, 1.05), (0.4, 45.02, z + 3.9), navy))
    done("jet_bridge", p)


def gse_tug():
    p = [B((1.5, 2.7, 0.75), (0, 0, 0.6), yellow, 0.04),
         B((1.4, 1.1, 0.06), (0, -0.4, 2.0), yellow),
         B((1.3, 1.0, 0.5), (0, 0.85, 1.2), dark)]
    for sx, sy in ((-0.62, 0.85), (0.62, 0.85), (-0.62, -0.85), (0.62, -0.85)):
        p.append(wheel(sx, sy, 0.32, 0.28))
        p.append(B((0.06, 0.06, 1.05), (sx * 0.95, sy * 0.4 - 0.4, 1.45), dark))
    p.append(B((0.9, 0.6, 0.45), (0, -0.45, 1.2), seat))
    p.append(B((0.12, 0.12, 0.12), (0, -0.4, 2.1), lamp_amber))
    p.append(B((0.5, 0.06, 0.12), (0, 1.36, 0.8), lamp_warm))
    done("gse_tug", p)


def gse_cart():
    p = [B((1.5, 2.6, 0.12), (0, 0, 0.55), grey),
         B((1.5, 2.6, 0.08), (0, 0, 1.95), canvas),
         B((1.52, 2.62, 1.3), (0, 0, 1.25), canvas)]
    for sx in (-0.72, 0.72):
        for sy in (-1.25, 1.25):
            p.append(B((0.08, 0.08, 1.45), (sx, sy, 1.25), steel))
    for sx, sy in ((-0.55, 0.9), (0.55, 0.9), (-0.55, -0.9), (0.55, -0.9)):
        p.append(wheel(sx, sy, 0.24, 0.16))
    p.append(beam((0, 1.3, 0.5), (0, 2.1, 0.35), 0.08, 0.08, dark))
    done("gse_cart", p)


def gse_belt():
    p = [B((1.8, 6.4, 0.6), (0, 0, 0.7), yellow, 0.03),
         B((1.2, 1.3, 1.0), (0, -2.4, 1.5), dark)]
    p.append(beam((0, -1.6, 1.2), (0, 3.6, 3.4), 0.9, 0.18, belt))
    for sx in (-0.5, 0.5):
        p.append(beam((sx, -1.6, 1.45), (sx, 3.6, 3.65), 0.06, 0.3, steel))
    p.append(beam((0, 1.6, 1.0), (0, 1.9, 2.5), 0.4, 0.2, grey))
    for sx, sy in ((-0.78, 2.0), (0.78, 2.0), (-0.78, -2.0), (0.78, -2.0)):
        p.append(wheel(sx, sy, 0.38, 0.3))
    p.append(B((0.12, 0.12, 0.12), (0, -2.4, 2.06), lamp_amber))
    done("gse_belt", p)


def gse_pushback():
    p = [B((2.6, 6.0, 1.1), (0, 0, 0.75), yellow, 0.06),
         B((2.2, 1.5, 0.9), (0, 1.6, 1.75), dark),
         B((2.25, 1.55, 0.6), (0, 1.6, 1.85), glass),
         B((0.6, 0.6, 0.3), (0, 3.15, 0.6), dark)]
    for sx, sy in ((-1.2, 2.0), (1.2, 2.0), (-1.2, -2.0), (1.2, -2.0)):
        p.append(wheel(sx, sy, 0.55, 0.42))
    p.append(B((0.14, 0.14, 0.14), (0, 1.6, 2.28), lamp_amber))
    done("gse_pushback", p)


def gse_fuel():
    p = [B((2.4, 2.2, 2.0), (0, 3.6, 1.45), white, 0.08),
         B((2.42, 0.9, 0.8), (0, 4.4, 2.0), glass),
         B((2.2, 7.0, 0.35), (0, -0.8, 0.9), dark),
         C(1.15, 6.4, (0, -4.0, 2.25), white, 16, axis="y"),
         B((2.36, 6.2, 0.18), (0, -0.8, 1.9), red),
         B((1.0, 1.0, 0.8), (0, -4.6, 1.2), grey),
         B((1.6, 0.4, 2.0), (0, 2.25, 2.4), steel)]
    for sx in (-1.0, 1.0):
        for sy in (3.6, -1.6, -3.0):
            p.append(wheel(sx, sy, 0.5, 0.4))
    p.append(B((0.15, 0.15, 0.15), (0, 3.6, 2.6), lamp_amber))
    done("gse_fuel", p)


def gse_catering():
    p = [B((2.4, 2.0, 1.9), (0, 3.4, 1.35), white, 0.06),
         B((2.42, 0.8, 0.75), (0, 4.1, 1.85), glass),
         B((2.2, 7.4, 0.35), (0, -0.4, 0.85), dark),
         B((2.5, 5.2, 2.6), (0, -1.2, 5.0), white),
         B((2.52, 5.22, 0.35), (0, -1.2, 4.0), teal),
         B((2.3, 1.2, 0.12), (0, 1.9, 6.1), grey)]
    for k in range(2):
        p.append(beam((-1.0, -3.4, 1.05 + k * 1.45), (-1.0, 1.0, 2.5 + k * 1.45), 0.12, 0.12, steel))
        p.append(beam((1.0, 1.0, 1.05 + k * 1.45), (1.0, -3.4, 2.5 + k * 1.45), 0.12, 0.12, steel))
    for sx in (-1.0, 1.0):
        for sy in (3.4, -2.4):
            p.append(wheel(sx, sy, 0.48, 0.38))
    done("gse_catering", p)


def gse_bus():
    """Apron bus: low floor, glazed all round, three doors on the right."""
    p = [B((3.0, 13.0, 0.9), (0, 0, 0.75), white, 0.05),
         B((3.0, 13.0, 0.4), (0, 0, 3.0), white, 0.05),
         B((3.04, 12.6, 1.8), (0, 0, 2.1), glass),
         B((3.06, 13.02, 0.22), (0, 0, 1.25), blue)]
    for y in (-5.5, -2.0, 2.0, 5.5):
        p.append(B((3.08, 0.2, 1.8), (0, y, 2.1), white))
    for sy in (-4.6, 4.6):
        for sx in (-1.3, 1.3):
            p.append(wheel(sx, sy, 0.45, 0.32))
    for sx in (-1.0, 1.0):
        p.append(B((0.5, 0.06, 0.2), (sx, 6.52, 0.9), lamp_warm))
        p.append(B((0.5, 0.06, 0.2), (sx, -6.52, 0.9), lamp_red))
    done("gse_bus", p)


def gse_stairs():
    p = [B((2.2, 6.0, 0.4), (0, 0, 0.75), white),
         B((2.0, 1.6, 1.4), (0, 2.2, 1.6), white)]
    for k in range(14):
        p.append(B((1.4, 0.36, 0.1), (0, -0.4 - k * 0.32, 1.1 + k * 0.28), grey))
    for sx in (-0.74, 0.74):
        p.append(beam((sx, -0.3, 2.0), (sx, -4.6, 5.0), 0.06, 0.06, yellow))
        p.append(beam((sx, -0.3, 1.0), (sx, -4.6, 4.0), 0.12, 0.3, white))
    p.append(B((1.6, 1.4, 0.12), (0, -5.0, 4.1), grey))
    for sx in (-0.95, 0.95):
        for sy in (2.0, -2.0):
            p.append(wheel(sx, sy, 0.4, 0.3))
    done("gse_stairs", p)


def gse_gpu():
    p = [B((1.3, 2.4, 1.3), (0, 0, 0.95), white, 0.05),
         B((1.32, 2.0, 0.3), (0, 0, 1.2), grey)]
    for sx, sy in ((-0.55, 0.8), (0.55, 0.8), (-0.55, -0.8), (0.55, -0.8)):
        p.append(wheel(sx, sy, 0.25, 0.18))
    done("gse_gpu", p)


def gse_follow():
    """FOLLOW ME car: compact pickup in yellow-black chequer with a light bar."""
    p = [B((1.85, 4.6, 0.75), (0, 0, 0.75), yellow, 0.08),
         B((1.7, 2.0, 0.65), (0, 0.4, 1.45), yellow, 0.06),
         B((1.72, 1.8, 0.45), (0, 0.4, 1.5), glass)]
    for k in range(6):
        p.append(B((1.87, 0.38, 0.2), (0, -2.0 + k * 0.76, 0.95), dark if k % 2 else yellow))
    p.append(B((1.2, 0.3, 0.16), (0, 0.4, 1.88), lamp_amber))
    for sx, sy in ((-0.8, 1.4), (0.8, 1.4), (-0.8, -1.4), (0.8, -1.4)):
        p.append(wheel(sx, sy, 0.34, 0.24))
    done("gse_follow", p)


def runway_light():
    done("runway_light", [C(0.08, 0.32, (0, 0, 0), dark, 6), C(0.13, 0.12, (0, 0, 0.32), lamp_white, 8)])


def taxi_light():
    done("taxi_light", [C(0.06, 0.22, (0, 0, 0), dark, 6), C(0.1, 0.1, (0, 0, 0.22), lamp_blue, 8)])


def approach_bar():
    """Approach light bar on three piles: 16 m wide, lamps along the top."""
    p = [B((16.0, 0.3, 0.3), (0, 0, 4.6), grey)]
    for x in (-6.5, 0.0, 6.5):
        p.append(C(0.4, 3.8, (x, 0, -3.0), dark, 8))
        p.append(C(0.16, 4.0, (x, 0, 0.6), grey, 6))
    for k in range(7):
        p.append(B((0.5, 0.5, 0.3), (-7.2 + k * 2.4, 0, 4.9), lamp_white))
    done("approach_bar", p)


def stand_sign():
    """Stand number board on a post (number via Label3D)."""
    p = [B((0.2, 0.2, 3.4), (0, 0, 1.7), grey),
         B((1.8, 0.16, 1.2), (0, 0, 3.9), sign_yellow),
         B((1.9, 0.2, 1.3), (0, -0.03, 3.9), dark)]
    done("stand_sign", p)


def windsock():
    p = [C(0.1, 9.0, (0, 0, 0), white, 8), C(0.6, 0.1, (0, 0, 0), grey, 8)]
    for k in range(5):
        p.append(C(0.55 - k * 0.07, 0.8, (0, 0.15 + k * 0.8, 8.4), orange if k % 2 == 0 else white, 10, r2=0.5 - k * 0.07, axis="y"))
    done("windsock", p)


def radar_mast():
    p = [B((3.0, 3.0, 2.0), (0, 0, 1.0), offwhite)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(beam((sx * 1.6, sy * 1.6, 2.0), (sx * 0.6, sy * 0.6, 16.0), 0.18, 0.18, white))
    for z in (5.0, 9.0, 13.0):
        f = 1.6 - (z - 2.0) / 14.0
        p.append(B((f * 2.0 + 0.2, 0.12, 0.12), (0, f, z), white))
        p.append(B((f * 2.0 + 0.2, 0.12, 0.12), (0, -f, z), white))
        p.append(B((0.12, f * 2.0 + 0.2, 0.12), (f, 0, z), white))
        p.append(B((0.12, f * 2.0 + 0.2, 0.12), (-f, 0, z), white))
    p.append(B((1.8, 1.8, 0.6), (0, 0, 16.2), grey))
    p.append(B((0.25, 0.25, 0.25), (0, 0, 16.6), lamp_red))
    done("radar_mast", p)


def radar_head():
    """Turns about its origin (top of radar_mast at 16.5 m)."""
    p = [C(0.4, 0.8, (0, 0, 0), grey, 8), B((7.0, 0.5, 1.6), (0, 0.4, 1.3), white),
         B((6.6, 0.12, 1.3), (0, 0.7, 1.3), offwhite)]
    done("radar_head", p)


def fence():
    """Security fence panel: 4 m, posts, rails, mesh (glass-like surface = see-through), barbed wire arm."""
    p = [B((0.08, 0.08, 3.0), (-2.0, 0, 1.5), steel),
         B((4.0, 0.05, 0.05), (0, 0, 2.95), steel),
         B((4.0, 0.05, 0.05), (0, 0, 0.15), steel),
         beam((-2.0, 0, 2.95), (-2.0, -0.45, 3.4), 0.05, 0.05, steel)]
    for z in (3.12, 3.27, 3.4):
        p.append(B((4.0, 0.02, 0.02), (0, -0.4 * (z - 2.95) / 0.45, z), grey))
    mesh = B((4.0, 0.02, 2.8), (0, 0, 1.55), glass)
    mesh.data.materials.clear()
    mesh.data.materials.append(P.setdefault("kit_mesh", _meshmat()))
    p.append(mesh)
    done("fence", p)


def _meshmat():
    m = mat("kit_mesh", (0.6, 0.62, 0.64), 0.6)
    m["kind"] = "glass"
    return m


def fence_gate():
    p = [B((0.3, 0.3, 3.2), (-4.0, 0, 1.6), yellow), B((0.3, 0.3, 3.2), (4.0, 0, 1.6), yellow),
         B((8.0, 0.08, 0.1), (0, 0, 2.6), steel), B((8.0, 0.08, 0.1), (0, 0, 0.3), steel)]
    for k in range(17):
        p.append(B((0.04, 0.04, 2.3), (-3.9 + k * 0.49, 0, 1.45), grey))
    # Gatehouse.
    p.append(B((3.2, 2.6, 2.8), (6.4, 0, 1.4), white))
    p.append(B((3.24, 2.64, 1.2), (6.4, 0, 1.7), glass))
    p.append(B((3.8, 3.2, 0.25), (6.4, 0, 2.95), navy))
    done("fence_gate", p)


# =============================================================== terminal
def checkin_island():
    """24 m: eight desks facing -Y, the bag belt behind, the back wall with
    light-box airline fascias, queue posts in front."""
    p = [B((24.0, 0.5, 3.4), (0, 2.1, 1.7), offwhite),
         B((24.4, 0.6, 0.9), (0, 2.1, 3.85), navy),
         B((24.0, 0.9, 0.45), (0, 1.15, 0.55), belt),
         B((24.0, 0.12, 0.7), (0, 1.62, 0.35), steel)]
    for k in range(8):
        x = -10.5 + k * 3.0
        p.append(B((2.2, 0.75, 1.05), (x, 0.0, 0.525), wood, 0.02))
        p.append(B((2.3, 0.8, 0.06), (x, 0.0, 1.08), stone))
        p.append(B((0.7, 0.4, 0.45), (x + 0.9, 0.55, 0.35), steel))    # (scale)
        p.append(B((0.55, 0.05, 0.38), (x - 0.3, 0.2, 1.35), dark))    # (monitor)
        p.append(B((2.4, 0.06, 0.55), (x, 1.82, 3.85), lamp_white))    # (fascia light box)
        p.append(B((0.5, 0.06, 0.3), (x, 1.82, 2.8), screen))
    for k in range(9):
        x = -12.0 + k * 3.0
        for y in (-2.0, -4.4):
            p.append(C(0.05, 0.95, (x, y, 0), steel, 6))
        p.append(B((3.0, 0.04, 0.06), (x + 1.5, -2.0, 0.92), dark))
    done("checkin_island", p)


def seat_row():
    """Six linked seats on a beam, 3.6 m, facing -Y."""
    p = [B((3.6, 0.1, 0.1), (0, 0.05, 0.4), steel)]
    for sx in (-1.5, 1.5):
        p.append(B((0.08, 0.5, 0.42), (sx, 0.05, 0.21), steel))
    for k in range(6):
        x = -1.5 + k * 0.6
        p.append(B((0.54, 0.5, 0.08), (x, 0.0, 0.46), seat))
        p.append(B((0.54, 0.08, 0.5), (x, 0.26, 0.76), seat))
    done("seat_row", p)


def shop_unit():
    """Duty-free / retail unit: 10 m front (glazed, facing -Y), 7 m deep,
    lit fascia, shelving, a counter."""
    p = [B((10.0, 7.0, 0.04), (0, 3.5, 0.02), stone),
         B((10.0, 0.3, 4.5), (0, 7.0, 2.25), offwhite),
         B((0.3, 7.0, 4.5), (-5.0, 3.5, 2.25), offwhite),
         B((0.3, 7.0, 4.5), (5.0, 3.5, 2.25), offwhite),
         B((10.0, 7.0, 0.2), (0, 3.5, 4.6), offwhite),
         B((10.2, 0.4, 0.8), (0, 0.0, 4.1), dark),
         B((8.6, 0.06, 0.55), (0, -0.22, 4.1), lamp_warm)]
    for x in (-3.0, 3.0):
        p.append(B((3.4, 0.06, 3.6), (x, 0.0, 1.8), glass))
    for x in (-4.6, 4.6):
        p.append(B((0.1, 0.1, 3.7), (x, 0.0, 1.85), steel))
    for k, x in enumerate((-3.0, 0.0, 3.0)):
        p.append(B((2.4, 0.5, 2.2), (x, 6.4, 1.1), wood))
        for z in (0.5, 1.0, 1.5, 2.0):
            p.append(B((2.3, 0.4, 0.2), (x, 6.3, z), [red, teal, yellow, white][(k + int(z * 2)) % 4]))
    for x in (-2.5, 2.5):
        p.append(B((1.6, 1.0, 0.95), (x, 3.6, 0.475), stone))
        for k in range(4):
            p.append(B((0.25, 0.25, 0.3), (x - 0.5 + k * 0.33, 3.6, 1.1), [orange, blue, white, red][k]))
    p.append(B((2.6, 0.7, 1.0), (3.0, 5.0, 0.5), wood))
    for x in (-3.0, 0.0, 3.0):
        p.append(B((0.6, 0.6, 0.05), (x, 3.5, 4.48), lamp_warm))
    done("shop_unit", p)


def cafe_unit():
    """Café: 10 m counter unit (open front, facing -Y) and tables outside."""
    p = [B((10.0, 5.0, 0.04), (0, 2.5, 0.02), wood),
         B((10.0, 0.3, 4.5), (0, 5.0, 2.25), dark),
         B((10.0, 5.0, 0.2), (0, 2.5, 4.6), offwhite),
         B((10.2, 0.4, 0.8), (0, 0.0, 4.1), leather),
         B((7.0, 0.06, 0.5), (0, -0.22, 4.1), lamp_warm),
         B((8.0, 0.8, 1.05), (0, 1.6, 0.525), wood),
         B((8.1, 0.9, 0.05), (0, 1.6, 1.07), stone),
         B((8.0, 0.4, 1.6), (0, 4.6, 1.8), steel),
         B((7.6, 0.06, 0.6), (0, 4.38, 2.9), screen)]
    for k in range(3):
        p.append(B((0.6, 0.4, 0.5), (-2.5 + k * 2.5, 1.6, 1.35), steel))
    for tx in (-3.5, 0.0, 3.5):
        ty = -2.6
        p.append(C(0.45, 0.04, (tx, ty, 0.74), stone, 12))
        p.append(C(0.05, 0.74, (tx, ty, 0), steel, 6))
        for a in (0.0, math.pi):
            cx = tx + math.cos(a) * 0.75
            p.append(B((0.42, 0.42, 0.06), (cx, ty, 0.45), leather))
            p.append(B((0.06, 0.42, 0.45), (cx + math.cos(a) * 0.21, ty, 0.7), leather))
            p.append(C(0.03, 0.45, (cx, ty, 0), steel, 6))
    done("cafe_unit", p)


def fids_board():
    """Departures board: two portrait screens back to back on a plinth."""
    p = [B((2.6, 0.5, 0.9), (0, 0, 0.45), stone),
         B((2.4, 0.35, 2.6), (0, 0, 2.2), dark),
         B((2.2, 0.38, 2.4), (0, 0, 2.2), screen)]
    for z in range(10):
        p.append(B((1.9, 0.39, 0.05), (0, 0, 1.2 + z * 0.22), lamp_amber if z % 3 == 0 else lamp_white))
    done("fids_board", p)


def security_lane():
    """X-ray tunnel with roller beds and a walk-through arch beside it."""
    p = [B((1.1, 3.0, 1.6), (0, 0, 0.8), offwhite),
         B((0.9, 2.4, 0.04), (0, 3.0, 0.78), belt),
         B((0.9, 2.4, 0.04), (0, -3.0, 0.78), belt),
         B((1.0, 2.4, 0.7), (0, 3.0, 0.38), steel),
         B((1.0, 2.4, 0.7), (0, -3.0, 0.38), steel),
         B((0.6, 0.06, 0.4), (0.4, -1.6, 1.3), screen)]
    for sx in (1.4, 2.4):
        p.append(B((0.12, 0.6, 2.2), (sx, 0, 1.1), offwhite))
    p.append(B((1.12, 0.6, 0.2), (1.9, 0, 2.3), offwhite))
    p.append(B((0.12, 0.08, 0.3), (1.9, -0.32, 2.3), lamp_green))
    done("security_lane", p)


def gate_desk():
    p = [B((2.4, 0.8, 1.05), (0, 0, 0.525), wood, 0.02),
         B((2.5, 0.85, 0.05), (0, 0, 1.07), stone),
         B((0.12, 0.12, 2.4), (1.6, 0, 1.2), steel),
         B((1.4, 0.12, 0.8), (1.6, 0, 2.8), screen),
         B((1.5, 0.14, 0.9), (1.6, 0.02, 2.8), dark)]
    done("gate_desk", p)


def carousel():
    """Baggage reclaim carousel: 14 × 4 m stadium loop with a feed hood."""
    p = [B((10.0, 3.8, 0.55), (0, 0, 0.28), steel),
         B((10.0, 2.6, 0.05), (0, 0, 0.58), belt)]
    for sx in (-5.0, 5.0):
        p.append(C(1.9, 0.55, (sx, 0, 0), steel, 16))
        p.append(C(1.3, 0.05, (sx, 0, 0.56), belt, 16))
    p.append(B((2.0, 2.0, 2.2), (0, 0, 1.7), offwhite))
    p.append(B((1.2, 0.08, 0.5), (0, -1.02, 2.4), screen))
    for k, x in enumerate((-4.0, -1.2, 2.5, 4.6)):
        p.append(B((0.6, 0.35, 0.4), (x, -1.4 + (k % 2) * 0.5, 0.8), [red, navy, dark, teal][k]))
    done("carousel", p)


def indoor_planter():
    p = [C(1.2, 0.7, (0, 0, 0), stone, 14), C(1.1, 0.05, (0, 0, 0.68), soil, 14),
         C(0.12, 3.4, (0, 0, 0.7), wood, 6)]
    for k in range(7):
        a = k * 2.4
        r = 0.6 + (k % 3) * 0.25
        p.append(sphere("s", 0.9 - (k % 2) * 0.2, (math.cos(a) * r * 0.7, math.sin(a) * r * 0.7, 3.4 + (k % 3) * 0.5), leaf, 8, 6))
    done("indoor_planter", p)


def trolley():
    p = [B((0.6, 1.0, 0.04), (0, 0, 0.3), steel),
         beam((0, -0.45, 0.32), (0, -0.55, 1.1), 0.56, 0.04, steel),
         B((0.6, 0.05, 0.05), (0, -0.58, 1.12), dark)]
    for sx, sy in ((-0.25, 0.4), (0.25, 0.4), (-0.25, -0.4), (0.25, -0.4)):
        p.append(wheel(sx, sy, 0.09, 0.05))
    done("trolley", p)


def trolley_bay():
    p = [B((0.1, 6.0, 1.0), (-0.7, 0, 0.5), steel), B((0.1, 6.0, 1.0), (0.7, 0, 0.5), steel),
         B((1.6, 6.0, 0.1), (0, 0, 2.4), navy), B((0.1, 0.1, 2.4), (-0.7, 2.9, 1.2), steel),
         B((0.1, 0.1, 2.4), (0.7, 2.9, 1.2), steel), B((0.1, 0.1, 2.4), (-0.7, -2.9, 1.2), steel),
         B((0.1, 0.1, 2.4), (0.7, -2.9, 1.2), steel)]
    for k in range(8):
        y = -2.4 + k * 0.62
        p.append(B((0.58, 0.9, 0.04), (0, y, 0.32 + k * 0.004), steel))
        p.append(beam((0, y - 0.4, 0.34), (0, y - 0.5, 1.1), 0.56, 0.04, steel))
    done("trolley_bay", p)


def info_desk():
    p = [C(2.0, 1.05, (0, 0, 0), wood, 20), C(2.1, 0.05, (0, 0, 1.05), stone, 20),
         C(1.2, 1.1, (0, 0, 0), offwhite, 16), C(0.15, 3.2, (0, 0, 1.1), steel, 8),
         B((1.4, 1.4, 1.4), (0, 0, 4.9), sign_yellow), B((1.5, 1.5, 1.5), (0, 0, 4.9), dark)]
    done("info_desk", p)


def entrance_pod():
    """Glazed vestibule (8 m wide, 4 m deep, sliding doors) with a canopy
    blade over it and a lit soffit, against the façade at y=0, out to -Y."""
    p = [B((8.0, 4.0, 0.12), (0, -2.0, 0.06), stone),
         B((8.0, 0.1, 3.6), (0, -4.0, 1.8), glass),
         B((0.1, 4.0, 3.6), (-4.0, -2.0, 1.8), glass),
         B((0.1, 4.0, 3.6), (4.0, -2.0, 1.8), glass),
         B((8.4, 4.4, 0.35), (0, -2.0, 3.8), offwhite)]
    for x in (-4.0, -1.6, 1.6, 4.0):
        p.append(B((0.14, 0.14, 3.6), (x, -4.0, 1.8), steel))
    p.append(B((3.2, 0.12, 0.2), (0, -4.0, 3.0), steel))
    # Canopy blade on two raking struts.
    p.append(B((14.0, 9.0, 0.3), (0, -5.0, 5.4), white))
    p.append(B((13.6, 8.6, 0.05), (0, -5.0, 5.22), lamp_warm))
    for x in (-5.9, 5.9):
        p.append(beam((x * 0.85, -7.4, 0.0), (x * 0.8, -5.6, 5.3), 0.3, 0.3, steel))
    done("entrance_pod", p)


# =============================================================== landside
def gantry_sign():
    """Overhead direction sign spanning 26 m (a dual carriageway): two posts,
    a truss, two blank panels (text by Label3D) facing -Y."""
    p = []
    for x in (-13.0, 13.0):
        p.append(B((0.55, 0.55, 7.6), (x, 0, 3.8), grey))
        p.append(B((1.3, 1.3, 0.5), (x, 0, 0.25), stone))
    for z in (6.6, 7.5):
        p.append(B((26.6, 0.25, 0.25), (0, 0.45, z), grey))
    for k in range(18):
        x = -12.8 + k * 1.42
        p.append(beam((x, 0.45, 6.6), (x + 1.42, 0.45, 7.5), 0.12, 0.12, grey))
    for x in (-5.5, 5.5):
        p.append(B((9.6, 0.12, 2.4), (x, 0.0, 6.5), navy))
        p.append(B((9.8, 0.08, 2.6), (x, 0.08, 6.5), white))
    done("gantry_sign", p)


def taxi_shelter():
    p = [B((12.0, 3.0, 0.15), (0, 0, 3.0), white), B((11.6, 2.6, 0.05), (0, 0, 2.9), lamp_warm),
         B((12.0, 0.08, 2.0), (0, 1.4, 1.6), glass)]
    for x in (-5.8, 0.0, 5.8):
        p.append(B((0.15, 0.15, 3.0), (x, 1.3, 1.5), steel))
    p.append(B((0.15, 0.15, 3.4), (-6.6, -1.2, 1.7), steel))
    p.append(B((1.6, 0.1, 1.0), (-6.6, -1.2, 3.6), sign_yellow))
    for x in (-3.0, 3.0):
        p.append(B((2.4, 0.5, 0.45), (x, 1.0, 0.45), wood))
    done("taxi_shelter", p)


def fuel_canopy():
    """Petrol station forecourt canopy 24 × 14 m on four columns with three
    pump islands under it (lengthwise along X)."""
    p = [B((24.0, 14.0, 1.0), (0, 0, 5.6), white),
         B((24.1, 14.1, 0.45), (0, 0, 5.75), red),
         B((23.4, 13.4, 0.05), (0, 0, 5.08), lamp_white)]
    for x in (-8.0, 8.0):
        for y in (-3.5, 3.5):
            p.append(B((0.5, 0.5, 5.1), (x, y, 2.55), offwhite))
    for y in (-4.5, 0.0, 4.5):
        p.append(B((14.0, 1.2, 0.2), (0, y, 0.1), stone))
        for x in (-4.5, 0.0, 4.5):
            p.append(B((0.9, 0.6, 1.9), (x, y, 1.15), offwhite))
            p.append(B((0.92, 0.62, 0.35), (x, y, 1.75), red))
            p.append(B((0.5, 0.63, 0.35), (x, y, 1.3), screen))
    done("fuel_canopy", p)


def fuel_kiosk():
    """The station shop: 16 × 10 m, glazed front facing -Y, lit fascia."""
    p = [B((16.0, 10.0, 4.2), (0, 5.0, 2.1), offwhite),
         B((15.0, 0.1, 2.8), (0, -0.02, 1.5), glass),
         B((16.2, 10.2, 0.6), (0, 5.0, 4.4), red),
         B((10.0, 0.05, 0.4), (0, -0.12, 4.4), lamp_white),
         B((2.0, 0.12, 2.4), (-5.0, -0.06, 1.2), steel)]
    for x in (-3.0, 3.0):
        p.append(B((1.6, 1.0, 1.0), (x * 2.2, 11.0, 0.5), grey))
    # Totem sign.
    p.append(B((1.6, 0.5, 7.0), (10.0, -6.0, 3.5), red))
    p.append(B((1.4, 0.52, 3.0), (10.0, -6.0, 4.6), lamp_white))
    done("fuel_kiosk", p)


def rental_canopy():
    """Rental car return / pick-up shade: 30 × 12 m on a row of columns."""
    p = [B((30.0, 12.0, 0.35), (0, 0, 4.0), offwhite),
         B((30.2, 0.5, 0.9), (0, -6.0, 3.85), teal),
         B((29.0, 11.0, 0.05), (0, 0, 3.8), lamp_white)]
    for x in (-14.0, -7.0, 0.0, 7.0, 14.0):
        p.append(B((0.35, 0.35, 3.85), (x, 0, 1.92), steel))
    done("rental_canopy", p)


def rental_booth():
    p = [B((8.0, 5.0, 3.4), (0, 0, 1.7), white),
         B((7.4, 0.1, 2.0), (0, -2.52, 1.6), glass),
         B((8.4, 5.4, 0.4), (0, 0, 3.6), teal),
         B((6.0, 0.06, 0.32), (0, -2.72, 3.6), lamp_white)]
    done("rental_booth", p)


def barrier():
    """Car park entry barrier with ticket machine (arm along +X)."""
    p = [B((0.5, 0.5, 1.1), (0, 0, 0.55), yellow),
         B((4.0, 0.1, 0.1), (2.2, 0, 1.0), white),
         B((0.5, 0.4, 1.4), (-1.0, -0.6, 0.7), grey),
         B((0.3, 0.05, 0.25), (-1.0, -0.82, 1.1), screen)]
    for k in range(4):
        p.append(B((0.45, 0.11, 0.11), (0.6 + k * 1.0, 0, 1.0), red))
    done("barrier", p)


def bus_stop_airport():
    p = [B((8.0, 2.2, 0.15), (0, 0, 2.8), offwhite), B((8.0, 0.08, 2.2), (0, 1.0, 1.4), glass),
         B((7.6, 2.0, 0.04), (0, 0, 2.7), lamp_warm), B((1.2, 0.2, 2.0), (-3.6, 0.2, 1.3), screen)]
    for x in (-3.9, 3.9):
        p.append(B((0.12, 0.12, 2.8), (x, 0.9, 1.4), steel))
    p.append(B((3.0, 0.45, 0.45), (1.0, 0.6, 0.45), wood))
    done("bus_stop_airport", p)


def flag_pole():
    p = [C(0.09, 12.0, (0, 0, 0), white, 8), C(0.4, 0.2, (0, 0, 0), stone, 8),
         B((0.04, 2.4, 1.5), (0, 1.25, 11.0), navy)]
    done("flag_pole", p)


def runway_light_g():
    done("runway_light_g", [C(0.08, 0.32, (0, 0, 0), dark, 6), C(0.14, 0.12, (0, 0, 0.32), lamp_green, 8)])


def runway_light_r():
    done("runway_light_r", [C(0.08, 0.32, (0, 0, 0), dark, 6), C(0.14, 0.12, (0, 0, 0.32), lamp_red, 8)])


def ceiling_lamp():
    """Suspended linear luminaire, 8 m, on two 6 m rods (origin = its underside)."""
    p = [B((8.0, 0.6, 0.25), (0, 0, 0.125), offwhite), B((7.8, 0.5, 0.05), (0, 0, 0.02), lamp_white)]
    for x in (-3.2, 3.2):
        p.append(B((0.04, 0.04, 6.0), (x, 0, 3.25), steel))
    done("ceiling_lamp", p)


def flood_head():
    """Apron floodlight head (fits the 32 m masts): six lamps tilted down
    towards -Y, origin at the mast top."""
    p = [B((6.4, 0.5, 0.4), (0, 0, 0.4), grey), B((6.4, 0.5, 0.4), (0, 0, 1.8), grey)]
    for k in range(6):
        x = -2.5 + k * 1.0
        p.append(B((0.8, 0.5, 0.95), (x, -0.55, 1.1), grey))
        p.append(B((0.7, 0.06, 0.85), (x, -0.82, 1.1), lamp_white))
    done("flood_head", p)


def edge_post():
    """Low apron edge marker / bollard with a lamp (kerb lines, forecourt)."""
    done("edge_post", [C(0.11, 0.9, (0, 0, 0), dark, 8), C(0.12, 0.12, (0, 0, 0.9), lamp_warm, 8)])


# ========================================================= infrastructure
# Normalised so one mesh serves every viaduct and bridge (Godot scales them):
#   pier_column – 1 × 1 cross-section, 1 m tall, chamfered corners, a shadow
#                groove up each face, a drip band near the top;
#   pier_head  – a hammerhead: span 1 along X, depth 1, thickness 1, tapered
#                underside, bearing plinths + bearings on top;
#   pier_foot  – the pile cap the column stands on (chamfered top);
#   deck_girders – the deck's underside, 1 m long (X), 1 m wide (Y), 1 m
#                deep: four I-girders, the drainage run and its outlets.
def _prism_xz(name, prof, depth, m):
    """Extrude a side profile [(x, z), ...] (counter-clockwise) along Y."""
    bm = bmesh.new()
    front = [bm.verts.new((x, -depth / 2, z)) for x, z in prof]
    back = [bm.verts.new((x, depth / 2, z)) for x, z in prof]
    bm.faces.new(front[::-1])
    bm.faces.new(back)
    n = len(prof)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit.new_obj(name, bm, m)


def _oct_col(r, c, h, z0, m):
    """Chamfered rectangle prism: half-size r (x) × r (y), chamfer c."""
    bm = bmesh.new()
    pts = [(r - c, -r), (r, -r + c), (r, r - c), (r - c, r), (-r + c, r), (-r, r - c), (-r, -r + c), (-r + c, -r)]
    lo = [bm.verts.new((x, y, z0)) for x, y in pts]
    hi = [bm.verts.new((x, y, z0 + h)) for x, y in pts]
    bm.faces.new(lo[::-1])
    bm.faces.new(hi)
    for i in range(8):
        j = (i + 1) % 8
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit.new_obj("oct", bm, m)


conc = M("concrete", srgb("b9b5ac"))
conc_dk = M("concrete_dk", srgb("8f8b84"))
bearing = M("bearing", srgb("3b3d40"), "gloss")


def pier_column():
    p = [_oct_col(0.5, 0.11, 1.0, 0.0, conc)]
    for sx, sy in ((0.0, -0.501), (0.0, 0.501)):
        p.append(B((0.05, 0.02, 1.0), (sx, sy, 0.5), conc_dk))
    for sx, sy in ((-0.501, 0.0), (0.501, 0.0)):
        p.append(B((0.02, 0.05, 1.0), (sx, sy, 0.5), conc_dk))
    done("pier_column", p)


def pier_head():
    prof = [(-0.5, -0.32), (-0.2, -1.0), (0.2, -1.0), (0.5, -0.32), (0.5, 0.0), (-0.5, 0.0)]
    p = [_prism_xz("head", prof, 1.0, conc)]
    p.append(B((1.01, 1.01, 0.06), (0, 0, -0.03), conc_dk))   # (drip band)
    for x in (-0.36, -0.12, 0.12, 0.36):
        p.append(B((0.1, 0.5, 0.06), (x, 0, 0.03), conc_dk))
        p.append(B((0.07, 0.36, 0.06), (x, 0, 0.09), bearing))
    done("pier_head", p)


def pier_foot():
    p = [B((1.0, 1.0, 0.7), (0, 0, -0.35), conc_dk),
         _prism_xz("foot_top", [(-0.5, 0.0), (0.5, 0.0), (0.4, 0.22), (-0.4, 0.22)], 1.0, conc_dk)]
    done("pier_foot", p)


def deck_girders():
    p = []
    for y in (-0.36, -0.12, 0.12, 0.36):
        p.append(B((1.0, 0.025, 0.86), (0, y, -0.45), conc))        # web
        p.append(B((1.0, 0.09, 0.12), (0, y, -0.9), conc))          # bottom flange
    p.append(B((1.0, 0.82, 0.08), (0, 0, -0.04), conc_dk))           # soffit slab line
    for y in (-0.47, 0.47):
        p.append(B((1.0, 0.012, 0.012), (0, y, -0.3), M("pipe", srgb("4a4f55"), "gloss")))
    done("deck_girders", p)


def underpass_lamp():
    """Soffit luminaire (fixed under decks over roads and paths)."""
    done("underpass_lamp", [B((1.2, 0.4, 0.15), (0, 0, -0.075), grey), B((1.1, 0.32, 0.03), (0, 0, -0.16), lamp_white)])


def clearance_sign():
    """Headroom sign for a deck edge over a road (text by Label3D)."""
    done("clearance_sign", [B((2.2, 0.1, 0.9), (0, 0, 0), white), B((2.0, 0.12, 0.7), (0, 0.0, 0), red),
                            B((0.06, 0.06, 0.6), (-0.8, 0.0, 0.6), grey), B((0.06, 0.06, 0.6), (0.8, 0.0, 0.6), grey)])


for f in (jet_bridge, gse_tug, gse_cart, gse_belt, gse_pushback, gse_fuel, gse_catering, gse_bus,
          gse_stairs, gse_gpu, gse_follow, runway_light, taxi_light, approach_bar, stand_sign, windsock,
          radar_mast, radar_head, fence, fence_gate, checkin_island, seat_row, shop_unit, cafe_unit,
          fids_board, security_lane, gate_desk, carousel, indoor_planter, trolley, trolley_bay,
          info_desk, entrance_pod, gantry_sign, taxi_shelter, fuel_canopy, fuel_kiosk, rental_canopy,
          rental_booth, barrier, bus_stop_airport, flag_pole, runway_light_g, runway_light_r, ceiling_lamp,
          flood_head, edge_post, pier_column, pier_head, pier_foot, deck_girders, underpass_lamp, clearance_sign):
    f()

# Lay them out on a grid so the preview shows everything (Godot reads each
# object's mesh and ignores this placement).
x = 0.0
for ob in OBJECTS:
    ob.location = (x, 0, 0)
    x += max(ob.dimensions.x, 2.0) + 3.0
for ob in OBJECTS:
    ob.location = (0, 0, 0)
kit.export("skyport_kit.glb", OBJECTS)

if PREVIEW:
    # Lineup render (Workbench, material colours) for review.
    x = 0.0
    row_y = 0.0
    for i, ob in enumerate(OBJECTS):
        w = max(ob.dimensions.x, 1.5)
        if x > 90.0:
            x = 0.0
            row_y += 26.0
        ob.location = (x + w / 2, row_y, 0)
        x += w + 2.5
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "VERTEX"
    sc.display.shading.light = "STUDIO"
    sc.render.resolution_x, sc.render.resolution_y = 2400, 1400
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.location = (48, -70, 55)
    cam.rotation_euler = (math.radians(52), 0, 0)
    cam.data.lens = 24
    sc.camera = cam
    sc.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
