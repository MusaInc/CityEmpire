"""City Swing street life: pedestrians, trees and street furniture.

Run:  blender -b --factory-startup --python tools/blender/build_street.py -- assets/models [preview.png]

Same conventions as build_kit.py (Z-up / +Y forward in Blender = Y-up / -Z
forward in Godot, base-centre origins, stable material names):
  * pedestrian.glb – walker for the GPU walk cycle (pedestrian.gdshader):
    legs inside |x| < 0.2 below the hips (0.86 m), arms outside |x| > 0.2.
    Materials "skin", "shirt", "pants", "hair", "shoes" are recoloured per
    instance in the shader.
  * tree.glb / tree_tall.glb – broad street tree and a columnar one; the
    canopy's lower clumps use "leaves_dark" so it reads as a volume.
  * bench, bin, hydrant, bollard, sign_post, bus_shelter, planter – merged
    into one street-furniture mesh per chunk in Godot (vertex colours from
    the material colours), so a whole chunk's furniture is one draw call.
Optional second argument: render a lineup (Workbench) for review.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import build_kit as kit  # noqa: E402  (helpers only; its __main__ doesn't run)
from build_kit import box, cyl, dome, export, join, mat, new_obj, reset, sphere  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "assets/models"
PREVIEW = next((arg for arg in ARGS[1:] if not arg.startswith("--")), "")
ONLY = next((arg.split("=", 1)[1].split(",") for arg in ARGS[1:] if arg.startswith("--only=")), ())
kit.OUT = OUT
os.makedirs(OUT, exist_ok=True)


def tapered(name, r0, r1, z0, z1, x, y, material, segs=8, sx=1.0, sy=1.0, cap=False):
    """Vertical tapered limb/torso piece from z0 (radius r0) to z1 (r1); open
    ends by default (they sit inside the next piece)."""
    ob = cyl(name, r0, z1 - z0, (x, y, z0), material, segs, r2=r1, cap=cap)
    ob.scale = (sx, sy, 1.0)
    return ob


# ------------------------------------------------------------ pedestrian
# Four body types (pedestrians.glb: objects person_0..3), each ONE surface:
# UV.x = what it is (+ 0.5; PART: shoes 0, skin 1, legs 2, hair 3, top 4,
# eyes 5, accent 6, tights 7) so the shaders colour it per person (vertex
# COLOR stays free for the MultiMesh instance colour), and UV.y tags
# the limb (+ 0.5) so they pose whole limbs round the hip / knee / shoulder /
# elbow instead of shearing by position:
#   0 body (static), 1 left leg, 2 right leg, 3 left arm, 4 right arm, 5 head.
BODY, LEG_L, LEG_R, ARM_L, ARM_R, HEAD = range(6)
PART = {"skin": 1, "shirt": 4, "pants": 2, "hair": 3, "shoes": 0, "eyes": 5, "accent": 6, "tights": 7}


def tag(ob, variant, limb, smooth_shade=True):
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    part = PART[me.materials[0].name] if me.materials else 0
    uv = me.uv_layers[0].data
    for i in range(len(uv)):
        uv[i].uv = (part + 0.5, limb + 0.5)
    for poly in me.polygons:
        poly.use_smooth = smooth_shade
    me.materials.clear()
    me.materials.append(_body_mat())
    return ob


def _body_mat():
    return mat("person", (1.0, 1.0, 1.0), 0.7)


def person(v, m):
    """One body type. v: 0 casual man, 1 man in a long coat, 2 woman in a
    skirt, 3 woman in trousers with a backpack."""
    p = []

    def add(ob, limb, smooth_shade=True):
        p.append(tag(ob, v, limb, smooth_shade))

    woman = v in (2, 3)
    sh = 0.165 if woman else 0.19      # shoulder half-width
    ax = 0.215 if woman else 0.235     # arm line
    for side, sx in ((LEG_L, -0.09), (LEG_R, 0.09)):
        legm = m["tights"] if v == 2 else m["pants"]
        add(tapered("thigh", 0.085 if not woman else 0.078, 0.066, 0.47, 0.92, sx, 0.0, legm, 8), side)
        add(tapered("shin", 0.064, 0.046, 0.09, 0.48, sx, 0.0, legm, 8), side)
        add(sphere("knee", 0.066, (sx, 0.0, 0.475), legm, 8, 4), side)
        add(box("shoe", (0.1, 0.26, 0.085), (sx, 0.045, 0.045), m["shoes"], bevel=0.035, segs=2), side, False)
    add(tapered("pelvis", 0.15 if not woman else 0.155, 0.16, 0.8, 0.98, 0, 0, m["pants"] if v != 2 else m["shirt"], 10, sy=0.72, cap=True), BODY)
    if v == 2:
        # A-line skirt over the thighs.
        add(tapered("skirt", 0.22, 0.155, 0.58, 0.98, 0, 0, m["pants"], 12, sy=0.8, cap=False), BODY)
    if v == 1:
        # Long coat: tails over the thighs, collar.
        add(tapered("coat_tail", 0.215, 0.17, 0.6, 0.98, 0, 0, m["shirt"], 12, sy=0.78, cap=False), BODY)
    waist = 0.135 if woman else 0.155
    add(tapered("waist", waist, sh - 0.005, 0.96, 1.25, 0, 0, m["shirt"], 10, sy=0.66), BODY)
    add(tapered("chest", sh - 0.005, sh - 0.025, 1.24, 1.44, 0, 0, m["shirt"], 10, sy=0.66, cap=True), BODY)
    if woman:
        add(sphere("bust", 0.1, (0, 0.045, 1.3), m["shirt"], 10, 6, scale=(1.35, 0.55, 0.65)), BODY)
    if v == 1:
        add(tapered("scarf", 0.075, 0.07, 1.4, 1.5, 0, 0, m["accent"], 12, cap=True), BODY)
    for side, k in ((ARM_L, -1), (ARM_R, 1)):
        add(sphere("shoulder", 0.072 if not woman else 0.062, (k * (sh + 0.0), 0, 1.385), m["shirt"], 10, 6), side)
        add(tapered("upper_arm", 0.052 if not woman else 0.045, 0.043, 1.12, 1.41, k * ax, 0.0, m["shirt"], 8), side)
        sleeve = m["skin"] if v == 0 else m["shirt"]
        add(tapered("forearm", 0.042 if not woman else 0.037, 0.033, 0.885, 1.13, k * ax, 0.01, sleeve, 8), side)
        add(sphere("elbow", 0.044 if not woman else 0.039, (k * ax, 0.005, 1.125), sleeve, 8, 4), side)
        add(sphere("hand", 0.043, (k * ax, 0.012, 0.85), m["skin"], 10, 6, scale=(0.75, 1.0, 1.35)), side)
    add(tapered("neck", 0.05 if not woman else 0.044, 0.046, 1.42, 1.56, 0, 0, m["skin"], 10), HEAD)
    add(sphere("head", 0.104, (0, 0.012, 1.645), m["skin"], 12, 8, scale=(0.86, 0.98, 1.1)), HEAD)
    add(sphere("nose", 0.022, (0, 0.105, 1.632), m["skin"], 6, 4, scale=(0.8, 1.0, 1.2)), HEAD)
    for k in (-1, 1):
        add(sphere("ear", 0.022, (k * 0.09, 0.0, 1.645), m["skin"], 6, 4, scale=(0.5, 1.0, 1.3)), HEAD)
        add(sphere("eye", 0.011, (k * 0.034, 0.094, 1.665), m["eyes"], 6, 4), HEAD)
    if v == 0:
        add(sphere("hair", 0.111, (0, -0.008, 1.67), m["hair"], 12, 6, scale=(0.93, 1.0, 0.86)), HEAD)
    elif v == 1:
        add(dome("beanie", 0.112, (0, -0.005, 1.68), m["accent"], 12, 4, 0.95), HEAD)
        add(tapered("beanie_rim", 0.113, 0.113, 1.665, 1.71, 0, -0.005, m["accent"], 12, sx=0.93), HEAD)
    elif v == 2:
        # Long hair falling to the shoulder blades.
        add(sphere("hair", 0.115, (0, -0.012, 1.675), m["hair"], 12, 6, scale=(0.95, 1.02, 0.9)), HEAD)
        add(tapered("hair_back", 0.1, 0.085, 1.3, 1.66, 0, -0.06, m["hair"], 12, sy=0.55, cap=True), HEAD)
        add(box("bag", (0.06, 0.2, 0.17), (-0.27, 0.0, 0.92), m["accent"], bevel=0.02, segs=1), BODY, False)
        add(box("strap", (0.012, 0.02, 0.62), (-0.2, 0.0, 1.17), m["accent"]), BODY, False)
    else:
        add(sphere("hair", 0.113, (0, -0.01, 1.675), m["hair"], 12, 6, scale=(0.94, 1.0, 0.88)), HEAD)
        add(sphere("ponytail", 0.05, (0, -0.12, 1.6), m["hair"], 10, 6, scale=(0.8, 1.0, 1.9)), HEAD)
        add(box("backpack", (0.26, 0.13, 0.32), (0, -0.16, 1.18), m["accent"], bevel=0.03, segs=2), BODY, False)
    return p


def pedestrian():
    reset()
    m = {
        "skin": mat("skin", (0.62, 0.45, 0.36), 0.6),
        "shirt": mat("shirt", (1.0, 1.0, 1.0), 0.8),
        "pants": mat("pants", (0.17, 0.19, 0.25), 0.85),
        "hair": mat("hair", (0.12, 0.09, 0.07), 0.7),
        "shoes": mat("shoes", (0.1, 0.1, 0.1), 0.5),
        "tights": mat("tights", (0.1, 0.1, 0.1), 0.5),
        "eyes": mat("eyes", (0.05, 0.04, 0.04), 0.3),
        "accent": mat("accent", (0.45, 0.28, 0.16), 0.6),
    }
    people = []
    for v in range(4):
        people.append(join("person_%d" % v, person(v, m)))
    export("pedestrians.glb", people)


# ------------------------------------------------------------------ trees
def lumpy(name, r, loc, material, subdiv=2, wobble=0.16, squash=1.0, seed=0.0):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    for v in bm.verts:
        n = v.co.normalized()
        v.co += n * wobble * r * math.sin(v.co.x * 3.1 + v.co.y * 2.3 + v.co.z * 1.7 + seed)
        v.co.z *= squash
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    return new_obj(name, bm, material)


def branch(name, a, b, r0, r1, material):
    d = Vector(b) - Vector(a)
    ob = cyl(name, r0, d.length, (0, 0, 0), material, 5, r2=r1)
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    ob.location = a
    return ob


def tree():
    """Broad street tree (plane/lime): forked trunk, irregular open crown."""
    reset()
    bark = mat("bark", (0.29, 0.22, 0.17), 0.9)
    leaf = mat("leaves", (0.34, 0.5, 0.24), 0.85)
    dark = mat("leaves_dark", (0.22, 0.36, 0.18), 0.9)
    parts = [cyl("trunk", 0.2, 2.6, (0, 0, 0), bark, 7, r2=0.13)]
    parts.append(branch("b1", (0, 0, 2.4), (0.9, 0.3, 3.9), 0.11, 0.05, bark))
    parts.append(branch("b2", (0, 0, 2.5), (-0.7, -0.4, 4.1), 0.1, 0.05, bark))
    parts.append(branch("b3", (0, 0, 2.5), (0.1, 0.1, 4.6), 0.1, 0.05, bark))
    clumps = ((0.15, 0.1, 4.9, 1.5, leaf), (1.15, 0.35, 4.2, 1.2, leaf), (-0.95, -0.45, 4.35, 1.25, leaf),
              (0.1, 0.6, 3.7, 1.15, dark))
    for i, (x, y, z, r, m) in enumerate(clumps):
        parts.append(lumpy("c", r, (x, y, z), m, 2, 0.16, 0.85, i * 1.3))
    export("tree.glb", [join("tree", parts)])


def tree_tall():
    """Columnar tree (hornbeam/poplar): slim, taller crown of stacked clumps."""
    reset()
    bark = mat("bark", (0.3, 0.24, 0.19), 0.9)
    leaf = mat("leaves", (0.3, 0.47, 0.22), 0.85)
    dark = mat("leaves_dark", (0.2, 0.33, 0.16), 0.9)
    parts = [cyl("trunk", 0.17, 2.4, (0, 0, 0), bark, 7, r2=0.11)]
    for i, (x, y, z, r, m) in enumerate(((0.05, 0.05, 6.0, 0.85, leaf), (-0.1, -0.05, 4.8, 1.1, leaf),
                                          (0.05, 0.12, 3.6, 0.95, dark))):
        parts.append(lumpy("c", r, (x, y, z), m, 2, 0.14, 1.25, i * 2.1))
    export("tree_tall.glb", [join("tree_tall", parts)])


# ------------------------------------------------------ street furniture
def furniture_mats():
    return {
        "iron": mat("iron", (0.11, 0.13, 0.13), 0.5, 0.6),
        "wood": mat("wood", (0.47, 0.31, 0.18), 0.8),
        "steel": mat("steel", (0.55, 0.57, 0.58), 0.4, 0.7),
        "red": mat("hydrant_red", (0.72, 0.12, 0.08), 0.5),
        "green": mat("sign_green", (0.1, 0.33, 0.22), 0.5),
        "white": mat("sign_white", (0.92, 0.91, 0.86), 0.6),
        "glass": mat("shelter_glass", (0.55, 0.66, 0.7), 0.15),
        "stone": mat("planter_stone", (0.62, 0.6, 0.56), 0.9),
        "leaf": mat("leaves", (0.3, 0.46, 0.22), 0.85),
        "ad": mat("shelter_ad", (0.95, 0.75, 0.3), 0.5),
    }


def bench():
    """Park bench facing +Y (towards the road when placed), 1.8 m."""
    reset()
    m = furniture_mats()
    p = []
    for x in (-0.75, 0.75):
        p.append(box("leg", (0.06, 0.5, 0.42), (x, 0.0, 0.21), m["iron"]))
        p.append(box("arm", (0.06, 0.45, 0.05), (x, 0.0, 0.62), m["iron"]))
        p.append(box("back_leg", (0.05, 0.05, 0.5), (x, -0.24, 0.65), m["iron"]))
    for i in range(4):
        y = -0.169 + i * 0.113
        p.append(box("slat", (1.8, 0.091, 0.037), (0, y, 0.44), m["wood"], bevel=0.006))
        for x in (-0.75, 0.75):
            p.append(cyl("fastener", 0.009, 0.002, (x, y, 0.459), m["steel"], 6))
    for i in range(3):
        p.append(box("back", (1.8, 0.035, 0.082), (0, -0.27 - i * 0.013, 0.57 + i * 0.107), m["wood"], bevel=0.005))
    export("bench.glb", [join("bench", p)])


def bin_():
    reset()
    m = furniture_mats()
    p = [cyl("plinth", 0.23, 0.08, (0, 0, 0), m["iron"], 14),
         cyl("body", 0.232, 0.66, (0, 0, 0.08), m["green"], 14, r2=0.245),
         cyl("lid", 0.254, 0.09, (0, 0, 0.89), m["iron"], 14, r2=0.232),
         cyl("liner", 0.192, 0.16, (0, 0, 0.725), m["iron"], 12, cap=False)]
    for x in (-0.203, 0.203):
        p.append(box("cap support", (0.054, 0.27, 0.17), (x, 0, 0.812), m["green"], bevel=0.009))
    p.append(box("lock escutcheon", (0.045, 0.006, 0.067), (0, 0.245, 0.637), m["steel"], bevel=0.004))
    export("bin.glb", [join("bin", p)])


def hydrant():
    reset()
    m = furniture_mats()
    p = [cyl("base", 0.16, 0.08, (0, 0, 0), m["red"], 8),
         cyl("body", 0.12, 0.52, (0, 0, 0.08), m["red"], 8),
         sphere("cap", 0.13, (0, 0, 0.62), m["red"], 8, 4, scale=(1, 1, 0.7)),
         cyl("nozzle", 0.05, 0.3, (0, 0, 0), m["steel"], 6)]
    noz = p[-1]
    noz.rotation_euler = (0, math.radians(90), 0)
    noz.location = (-0.15, 0, 0.42)
    export("hydrant.glb", [join("hydrant", p)])


def bollard():
    reset()
    m = furniture_mats()
    p = [cyl("base plate", 0.109, 0.027, (0, 0, 0), m["iron"], 12),
         cyl("post", 0.083, 0.842, (0, 0, 0.026), m["iron"], 12, r2=0.073),
         cyl("cap", 0.075, 0.027, (0, 0, 0.866), m["iron"], 12, r2=0.065),
         cyl("reflector", 0.078, 0.025, (0, 0, 0.756), m["white"], 12)]
    export("bollard.glb", [join("bollard", p)])


def sign_post():
    """Street-name sign on a post (two blades, crossed)."""
    reset()
    m = furniture_mats()
    p = [cyl("post", 0.04, 2.9, (0, 0, 0), m["iron"], 6)]
    p.append(box("blade", (0.9, 0.03, 0.2), (0.3, 0, 2.75), m["green"]))
    p.append(box("blade_face", (0.84, 0.035, 0.12), (0.3, 0, 2.75), m["white"]))
    b2 = box("blade2", (0.03, 0.9, 0.2), (0, 0.3, 2.5), m["green"])
    b3 = box("blade2_face", (0.035, 0.84, 0.12), (0, 0.3, 2.5), m["white"])
    export("sign_post.glb", [join("sign_post", p + [b2, b3])])


def bus_shelter():
    """3.6 m shelter, open side facing +Y (the road): roof, back glass, ad panel, bench."""
    reset()
    m = furniture_mats()
    p = [box("roof", (3.8, 1.5, 0.1), (0, -0.05, 2.45), m["iron"])]
    for x in (-1.75, 1.75):
        p.append(box("post", (0.08, 0.08, 2.4), (x, -0.62, 1.2), m["iron"]))
        p.append(box("post_f", (0.08, 0.08, 2.4), (x, 0.55, 1.2), m["iron"]))
    p.append(box("back_glass", (3.5, 0.03, 1.9), (0, -0.62, 1.25), m["glass"]))
    p.append(box("side_glass", (0.03, 1.1, 1.9), (-1.75, -0.05, 1.25), m["glass"]))
    p.append(box("ad", (0.06, 1.0, 1.6), (1.75, -0.05, 1.15), m["ad"]))
    p.append(box("seat", (1.8, 0.3, 0.05), (-0.5, -0.42, 0.5), m["steel"], bevel=0.01))
    p.append(box("rear gutter", (3.69, 0.095, 0.085), (0, -0.73, 2.39), m["steel"]))
    for x in (-1.75, 0.0, 1.75):
        p.append(box("mullion", (0.041, 0.066, 2.05), (x, -0.62, 1.26), m["iron"]))
        p.append(box("glazing channel", (1.75, 0.057, 0.036), (x * 0.5, -0.62, 0.278), m["steel"]))
    for x in (-1.3, 0.28):
        p.append(box("seat bracket", (0.062, 0.34, 0.086), (x, -0.44, 0.451), m["iron"]))
    export("bus_shelter.glb", [join("bus_shelter", p)])


def planter():
    reset()
    m = furniture_mats()
    p = [box("footing", (1.11, 1.11, 0.12), (0, 0, 0.06), m["stone"], bevel=0.018),
         box("soil", (1.08, 1.08, 0.16), (0, 0, 0.33), m["wood"])]
    for side in (-1, 1):
        p.append(box("long wall", (1.2, 0.087, 0.47), (0, side * 0.554, 0.295), m["stone"], bevel=0.013))
        p.append(box("short wall", (0.087, 1.04, 0.47), (side * 0.554, 0, 0.295), m["stone"], bevel=0.013))
    for x, y, z, r in ((0.07, -0.04, 0.70, 0.43), (-0.27, 0.13, 0.59, 0.24), (0.27, 0.25, 0.58, 0.22)):
        p.append(lumpy("leaf cluster", r, (x, y, z), m["leaf"], 1, 0.26, 0.8))
    export("planter.glb", [join("planter", p)])


def preview(path):
    """Workbench lineup of everything built here."""
    reset()
    files = ["pedestrians", "tree", "tree_tall", "bench", "bin", "hydrant", "bollard", "sign_post",
             "bus_shelter", "planter"]
    x = 0.0
    for f in files:
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, f + ".glb"))
        for o in bpy.context.selected_objects:
            o.location.x += x
        x += 4.5 if f in ("tree", "bus_shelter") else 2.4
    scn = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scn.collection.objects.link(cam)
    cam.location = (x * 0.47, -30.0, 4.0)
    cam.rotation_euler = (math.radians(86), 0, 0)
    cam.data.lens = 28
    scn.camera = cam
    scn.render.engine = "BLENDER_WORKBENCH"
    scn.display.shading.color_type = "MATERIAL"
    scn.display.shading.light = "STUDIO"
    scn.render.resolution_x = 1600
    scn.render.resolution_y = 600
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    for fn in (pedestrian, tree, tree_tall, bench, bin_, hydrant, bollard, sign_post, bus_shelter, planter):
        if not ONLY or fn.__name__.rstrip("_") in ONLY:
            fn()
    if PREVIEW:
        preview(PREVIEW)
    print("STREET DONE")
