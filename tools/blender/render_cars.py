"""Review renders of City Empire car bodies (before/after comparisons).

Run:  blender -b --factory-startup --python tools/blender/render_cars.py -- <vehicles dir> <out dir> <body,body,...> [paint hex,...]

For each body: front three-quarter, side, rear three-quarter and a close
three-quarter of the nose, on a grey studio floor with a sun + sky, wheels
fitted from bodies.json exactly as CarVisual places them (wheel_five).
Cycles on the CPU (headless, no GPU needed); identical cameras and light
for every body so before/after images line up.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, NAMES = ARGS[0], ARGS[1], ARGS[2].split(",")
PAINTS = ARGS[3].split(",") if len(ARGS) > 3 and ARGS[3] else []
os.makedirs(OUT, exist_ok=True)
DIMS = json.load(open(os.path.join(SRC, "bodies.json")))
DEFAULT_PAINT = {"kestrel": "c9c6bd", "marlin": "1d3a6b", "scout": "d8661a", "brute": "8a1410", "vanta": "16181c",
                 "halcyon": "e9e9ec", "stiletto": "d8b020", "goliath": "3a4a3a", "warden": "2b2f33",
                 "civ_van": "e8e8e4", "civ_box": "f0f0ea"}


def hexcol(h):
    h = h.lstrip("#")
    return tuple((int(h[i:i + 2], 16) / 255.0) ** 2.2 for i in (0, 2, 4))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.render.resolution_x = 960
    sc.render.resolution_y = 540
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.exposure = -0.7
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    sky = w.node_tree.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "NISHITA"
    sky.sun_elevation = math.radians(35)
    sky.sun_rotation = math.radians(140)
    w.node_tree.links.new(sky.outputs[0], w.node_tree.nodes["Background"].inputs[0])
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.35
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(140)))
    bpy.context.object.data.energy = 2.2
    bpy.context.object.data.angle = math.radians(3)
    bpy.ops.mesh.primitive_plane_add(size=60)
    fl = bpy.data.materials.new("floor")
    fl.use_nodes = True
    fl.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.32, 0.33, 1)
    fl.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.7
    bpy.context.object.data.materials.append(fl)


CLEAR = {"glass_clear": 0.35, "lens": 0.05, "lens_red": 0.75}


def paint(ob, col):
    # Transparent glazing / lenses as the game draws them (glTF round-trips
    # them opaque).
    for s in ob.material_slots:
        n = s.material.name.split(".")[0] if s.material else ""
        if n in CLEAR:
            b = s.material.node_tree.nodes.get("Principled BSDF")
            if b:
                b.inputs["Alpha"].default_value = CLEAR[n]
                b.inputs["Roughness"].default_value = 0.02
    for s in ob.material_slots:
        if s.material and s.material.name.split(".")[0] in ("paint",):
            m = s.material.copy()
            b = m.node_tree.nodes.get("Principled BSDF")
            if b:
                b.inputs["Base Color"].default_value = (*col, 1)
                b.inputs["Roughness"].default_value = 0.22
                b.inputs["Coat Weight"].default_value = 0.6
            s.material = m


def load(name, col):
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name + ".glb"))
    root = [o for o in bpy.context.selected_objects if o.parent is None]
    for o in bpy.context.selected_objects:
        if o.type == "MESH":
            paint(o, col)
    d = DIMS[name]
    track = d["W"] - d["tyre_w"] - 0.05
    wheel = "wheel_" + d.get("wheel", "five")
    if not os.path.exists(os.path.join(SRC, wheel + ".glb")):
        wheel = "wheel_five"
    for x in (1, -1):
        for ay in d["axles"]:
            bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, wheel + ".glb"))
            w = [o for o in bpy.context.selected_objects if o.parent is None][0]
            w.rotation_mode = "XYZ"
            w.scale = (d["tyre_w"] / 0.44, d["wheel_r"], d["wheel_r"])
            # glTF: Godot -Z forward = Blender +Y; the wheel's axle is X.
            w.location = (x * track / 2, ay, d["wheel_r"])
            w.rotation_euler = (0, 0, 0 if x > 0 else math.pi)
    return d


def cam(loc, target, lens=50):
    c = bpy.data.objects.get("cam")
    if c is None:
        bpy.ops.object.camera_add()
        c = bpy.context.object
        c.name = "cam"
        bpy.context.scene.camera = c
    c.location = loc
    c.data.lens = lens
    dirv = Vector(target) - Vector(loc)
    c.rotation_euler = dirv.to_track_quat("-Z", "Y").to_euler()


for n in NAMES:
    reset()
    col = hexcol(PAINTS[NAMES.index(n)] if NAMES.index(n) < len(PAINTS) else DEFAULT_PAINT.get(n, "aaaaaa"))
    d = load(n, col)
    L, H = d["L"], d["roof"]
    r = max(L, 4.2)
    views = {
        "front34": ((r * 0.95, r * 1.05, 1.45), (0, 0.1, H * 0.45), 50),
        "side": ((r * 1.75, 0, 0.95), (0, 0, H * 0.45), 50),
        "rear34": ((-r * 0.95, -r * 1.05, 1.7), (0, -0.1, H * 0.45), 50),
        "nose": ((L * 0.42, L * 0.62 + 1.4, 0.95), (0, L * 0.38, H * 0.4), 50),
        "front": ((0, r * 1.9, 0.8), (0, 0, H * 0.42), 50),
        "rear": ((0, -r * 1.9, 0.9), (0, 0, H * 0.42), 50),
        "side_l": ((-r * 1.75, 0, 0.95), (0, 0, H * 0.45), 50),
        "tail": ((-L * 0.42, -L * 0.62 - 1.4, 1.05), (0, -L * 0.38, H * 0.45), 50),
    }
    for vn, (loc, tgt, lens) in views.items():
        cam(loc, tgt, lens)
        bpy.context.scene.render.filepath = os.path.join(OUT, "%s_%s.png" % (n, vn))
        bpy.ops.render.render(write_still=True)
    print("RENDERED", n)
