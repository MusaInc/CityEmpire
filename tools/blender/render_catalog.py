"""Studio catalogue photography of every purchasable vehicle, aircraft and boat.

Run (one model per Blender process keeps memory flat):
  blender -b --factory-startup --python tools/blender/render_catalog.py -- <project root> <out dir> <model> [views]

The phone's Garage / Marketplace / showroom cards show these pre-rendered
images (assets/ui/catalog/<model>_<view>.jpg, see tools/catalog/run.sh):
no live 3D in the interface. The models are the game's own GLBs
(assets/vehicles, assets/craft) in their catalogue paint, wheels fitted
exactly as CarVisual does (bodies.json):

  * cars      – a dark showroom cove: overhead softbox, two strip rims,
                glossy resin floor;
  * aircraft  – a concrete apron at golden hour;
  * boats     – open water at the end of the afternoon.

Views: hero (front three-quarter), side, rear (rear three-quarter), detail
(close on the nose / cockpit / helm). Cycles CPU, denoised.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
ROOT, OUT, MODEL = ARGS[0], ARGS[1], ARGS[2]
VIEWS = ARGS[3].split(",") if len(ARGS) > 3 and ARGS[3] else ["hero", "side", "rear", "detail"]
W, H = int(os.environ.get("CAT_W", "1280")), int(os.environ.get("CAT_H", "720"))
SAMPLES = int(os.environ.get("CAT_SAMPLES", "64"))
os.makedirs(OUT, exist_ok=True)

CAT = json.load(open(os.path.join(ROOT, "config/empire/vehicles.json")))["models"]
VEH = os.path.join(ROOT, "assets/vehicles")
CRAFT = os.path.join(ROOT, "assets/craft")
DIMS = json.load(open(os.path.join(VEH, "bodies.json")))

m = CAT[MODEL]
CLS = m.get("class", "car")


def lin(h, fallback="aaaaaa"):
    h = (h or fallback).lstrip("#")
    return tuple((int(h[i:i + 2], 16) / 255.0) ** 2.2 for i in (0, 2, 4))


PAINT = lin(m.get("paint"))
TRIM = lin(m.get("trim"), "2a2f36")


# ------------------------------------------------------------------ scene
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 8
    sc.cycles.transparent_max_bounces = 12
    sc.render.resolution_x = W
    sc.render.resolution_y = H
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.render.threads_mode = "AUTO"
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    return sc


def mat(name, col, rough=0.5, metal=0.0, coat=0.0, emit=None, emit_k=0.0):
    mt = bpy.data.materials.new(name)
    mt.use_nodes = True
    b = mt.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Coat Weight"].default_value = coat
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = emit_k
    return mt


def area(loc, rot, size, energy, col=(1, 1, 1), shape="RECTANGLE", size_y=None):
    bpy.ops.object.light_add(type="AREA", location=loc, rotation=rot)
    L = bpy.context.object.data
    L.shape = shape
    L.size = size
    L.size_y = size_y if size_y else size
    L.energy = energy
    L.color = col
    return bpy.context.object


def aim(ob, target):
    d = Vector(target) - ob.location
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def plane(size, loc, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_plane_add(size=size, location=loc, rotation=rot)
    bpy.context.object.data.materials.append(material)
    return bpy.context.object


def showroom(span):
    """Dark cove: a seamless curved backdrop, glossy resin floor."""
    sc = bpy.context.scene
    bg = sc.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.012, 0.012, 0.014, 1)
    bg.inputs[1].default_value = 1.0
    sc.view_settings.exposure = -0.3
    # floor + cove (a bent plane: floor running into a backdrop wall)
    floor = mat("resin", (0.030, 0.031, 0.034), rough=0.3, coat=0.25)
    bpy.ops.mesh.primitive_plane_add(size=1)
    ob = bpy.context.object
    me = ob.data
    import bmesh
    bm = bmesh.new()
    R, D, Hc = span * 6.0, span * 5.0, span * 3.0
    rows = []
    # profile in (y, z): floor from y=+D to y=-D*0.4, then a quarter circle up
    prof = [(D, 0.0), (-D * 0.4, 0.0)]
    rad = span * 1.6
    for i in range(1, 13):
        a = (math.pi * 0.5) * i / 12.0
        prof.append((-D * 0.4 - math.sin(a) * rad, rad - math.cos(a) * rad))
    prof.append((-D * 0.4 - rad, Hc))
    for (y, z) in prof:
        rows.append([bm.verts.new((x, y, z)) for x in (-R, R)])
    for a, b in zip(rows, rows[1:]):
        bm.faces.new((a[0], a[1], b[1], b[0]))
    bm.to_mesh(me)
    bm.free()
    me.materials.append(floor)
    for p in me.polygons:
        p.use_smooth = True
    # key softbox overhead, two long strip rims behind, a low warm fill
    k = area((0, 0.4 * span, span * 1.45), (0, 0, 0), span * 1.5, 900 * span, (1.0, 0.98, 0.95), size_y=span * 0.8)
    for sx in (-1, 1):
        r = area((sx * span * 1.2, -span * 0.9, span * 0.75), (0, 0, 0), span * 0.12, 260 * span, (0.92, 0.96, 1.0), size_y=span * 1.6)
        aim(r, (0, 0, span * 0.2))
    f = area((-span * 1.3, span * 2.2, span * 0.9), (0, 0, 0), span * 0.9, 60 * span, (1.0, 0.86, 0.68))
    aim(f, (0, 0, span * 0.25))


def outdoors(kind, span):
    """Nishita sky low in the sky + apron concrete or open water."""
    sc = bpy.context.scene
    nt = sc.world.node_tree
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "NISHITA"
    sky.sun_elevation = math.radians(16 if kind == "air" else 19)
    sky.sun_rotation = math.radians(215)
    sky.air_density = 1.2
    sky.dust_density = 0.8
    nt.links.new(sky.outputs[0], nt.nodes["Background"].inputs[0])
    nt.nodes["Background"].inputs[1].default_value = 0.22
    sc.view_settings.exposure = -0.6
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(74 if kind == "air" else 71), 0, math.radians(215 + 180)))
    sun = bpy.context.object.data
    sun.energy = 2.4
    sun.angle = math.radians(1.2)
    sun.color = (1.0, 0.82, 0.62)
    if kind == "air":
        mc = bpy.data.materials.new("apron")
        mc.use_nodes = True
        t = mc.node_tree
        b = t.nodes["Principled BSDF"]
        noise = t.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 3.0
        noise.inputs["Detail"].default_value = 12.0
        ramp = t.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (0.07, 0.068, 0.066, 1)
        ramp.color_ramp.elements[1].color = (0.13, 0.125, 0.12, 1)
        t.links.new(noise.outputs["Fac"], ramp.inputs[0])
        t.links.new(ramp.outputs[0], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = 0.78
        bump = t.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.15
        n2 = t.nodes.new("ShaderNodeTexNoise")
        n2.inputs["Scale"].default_value = 180.0
        t.links.new(n2.outputs["Fac"], bump.inputs["Height"])
        t.links.new(bump.outputs["Normal"], b.inputs["Normal"])
        plane(span * 60, (0, 0, 0), mc)
    else:
        mw = bpy.data.materials.new("sea")
        mw.use_nodes = True
        t = mw.node_tree
        b = t.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (0.006, 0.03, 0.045, 1)
        b.inputs["Roughness"].default_value = 0.04
        b.inputs["IOR"].default_value = 1.333
        wave = t.nodes.new("ShaderNodeTexWave")
        wave.inputs["Scale"].default_value = 0.9
        wave.inputs["Distortion"].default_value = 6.0
        wave.inputs["Detail"].default_value = 6.0
        n = t.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = 3.5
        mix = t.nodes.new("ShaderNodeMath")
        mix.operation = "ADD"
        t.links.new(wave.outputs["Fac"], mix.inputs[0])
        t.links.new(n.outputs["Fac"], mix.inputs[1])
        bump = t.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.22
        bump.inputs["Distance"].default_value = 0.4
        t.links.new(mix.outputs[0], bump.inputs["Height"])
        t.links.new(bump.outputs["Normal"], b.inputs["Normal"])
        plane(span * 80, (0, 0, 0), mw)


# ------------------------------------------------------------------ vehicle
CLEAR = {"glass": 0.42, "glass_clear": 0.3, "lens": 0.05, "lens_red": 0.38}


def dress(ob):
    for s in ob.material_slots:
        if not s.material or not s.material.use_nodes:
            continue
        n = s.material.name.split(".")[0]
        b = s.material.node_tree.nodes.get("Principled BSDF")
        if b is None:
            continue
        if n in CLEAR:
            b.inputs["Alpha"].default_value = CLEAR[n]
            b.inputs["Roughness"].default_value = 0.02
            if n in ("glass", "glass_clear"):
                b.inputs["Base Color"].default_value = (0.04, 0.05, 0.055, 1)
                if CLS != "car":
                    b.inputs["Alpha"].default_value = 0.92
                    b.inputs["Coat Weight"].default_value = 1.0
            if n == "lens_red":
                b.inputs["Base Color"].default_value = (0.42, 0.006, 0.006, 1)
        elif n in ("tyre", "tyre_wall", "rubber"):
            b.inputs["Base Color"].default_value = (0.012, 0.012, 0.013, 1)
            b.inputs["Specular IOR Level"].default_value = 0.15
            b.inputs["Roughness"].default_value = 0.85
        elif n == "rotor_blur" or n.endswith("blur"):
            ob.hide_render = True
        elif n in ("paint", "paint2", "gelcoat"):
            mm = s.material.copy()
            bb = mm.node_tree.nodes["Principled BSDF"]
            if n == "gelcoat":
                bb.inputs["Roughness"].default_value = 0.12
                bb.inputs["Coat Weight"].default_value = 0.6
                s.material = mm
                continue
            col = PAINT if n == "paint" else TRIM
            bb.inputs["Base Color"].default_value = (*col, 1)
            bb.inputs["Coat Weight"].default_value = 1.0
            bb.inputs["Coat Roughness"].default_value = 0.02
            if CLS == "car":
                # metallic base under a clear coat with fine flake (car_paint)
                bb.inputs["Metallic"].default_value = 0.62
                bb.inputs["Roughness"].default_value = 0.32
                t = mm.node_tree
                vor = t.nodes.new("ShaderNodeTexVoronoi")
                vor.inputs["Scale"].default_value = 2600.0
                bump = t.nodes.new("ShaderNodeBump")
                bump.inputs["Strength"].default_value = 0.08
                t.links.new(vor.outputs["Distance"], bump.inputs["Height"])
                t.links.new(bump.outputs["Normal"], bb.inputs["Normal"])
            else:
                bb.inputs["Metallic"].default_value = 0.15
                bb.inputs["Roughness"].default_value = 0.22
            s.material = mm


def import_glb(path):
    bpy.ops.import_scene.gltf(filepath=path)
    sel = list(bpy.context.selected_objects)
    for o in sel:
        if o.type == "MESH":
            dress(o)
        if "blur" in o.name.lower():
            o.hide_render = True
    return sel


def load_car():
    body = m.get("art", m.get("body", MODEL))
    if not os.path.exists(os.path.join(VEH, body + ".glb")):
        body = m.get("body", MODEL)
    import_glb(os.path.join(VEH, body + ".glb"))
    d = DIMS.get(m.get("body", body), DIMS.get(body))
    track = d["W"] - d["tyre_w"] - 0.05
    wheel = "wheel_" + d.get("wheel", "five")
    if not os.path.exists(os.path.join(VEH, wheel + ".glb")):
        wheel = "wheel_five"
    for x in (1, -1):
        for ay in d["axles"]:
            sel = import_glb(os.path.join(VEH, wheel + ".glb"))
            w = [o for o in sel if o.parent is None][0]
            w.rotation_mode = "XYZ"
            w.scale = (d["tyre_w"] / 0.44, d["wheel_r"], d["wheel_r"])
            # glTF: Godot -Z forward = Blender +Y; the wheel's axle is X.
            w.location = (x * track / 2, ay, d["wheel_r"])
            w.rotation_euler = (0, 0, 0 if x > 0 else math.pi)


def load_craft():
    import_glb(os.path.join(CRAFT, MODEL + ".glb"))


def bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in bpy.data.objects:
        if o.type != "MESH" or o.hide_render or o.name.startswith(("Plane", "resin", "Cove")) or not o.data.materials:
            continue
        if o.data.materials[0] and o.data.materials[0].name in ("resin", "apron", "sea", "line"):
            continue
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    return lo, hi


def camera(view, lo, hi):
    c = bpy.data.objects.get("cam")
    if c is None:
        bpy.ops.object.camera_add()
        c = bpy.context.object
        c.name = "cam"
        bpy.context.scene.camera = c
    size = hi - lo
    ctr = (lo + hi) * 0.5
    L = max(size.y, size.x * 0.8)
    Hh = size.z
    # (az from +Y = the nose; el above the ground)
    table = {
        "car": {"hero": (38, 9, 50, 0.86), "side": (90, 4, 70, 1.0), "rear": (148, 10, 50, 1.0), "detail": (22, 6, 85, 0.42)},
        "heli": {"hero": (35, 10, 40, 0.85), "side": (90, 5, 55, 1.0), "rear": (150, 12, 40, 1.0), "detail": (15, 4, 85, 0.36)},
        "plane": {"hero": (32, 11, 35, 0.78), "side": (100, 6, 40, 1.0), "rear": (155, 14, 35, 0.8), "detail": (18, 5, 85, 0.3)},
        "boat": {"hero": (35, 12, 40, 1.0), "side": (90, 5, 50, 1.0), "rear": (150, 16, 40, 1.0), "detail": (55, 32, 60, 0.55)},
    }[CLS]
    az, el, lens, frac = table[view]
    c.data.lens = lens
    c.data.sensor_width = 36
    fov_h = 2 * math.atan(18.0 / lens)
    fov_v = 2 * math.atan(18.0 * H / W / lens)
    # distance that fits the object's extent (frac < 1 = a close-up)
    ext_w = (abs(math.sin(math.radians(az))) * size.y + abs(math.cos(math.radians(az))) * size.x) * frac
    dist = max(ext_w * 0.5 / math.tan(fov_h * 0.5) * 1.18, Hh * frac * 0.5 / math.tan(fov_v * 0.5) * 1.35) + max(size.x, size.y) * 0.5 * frac
    tgt = Vector((ctr.x, ctr.y, lo.z + Hh * (0.42 if view != "detail" else 0.55)))
    if view == "detail":
        tgt = Vector((ctr.x, (hi.y - size.y * 0.18) if CLS != "boat" else ctr.y, lo.z + Hh * 0.55))
    a, e = math.radians(az), math.radians(el)
    off = Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e))) * dist
    c.location = tgt + off
    if c.location.z < 0.35:
        c.location.z = 0.35
    aim(c, tgt)
    c.data.dof.use_dof = view == "detail"
    c.data.dof.focus_distance = (c.location - tgt).length
    c.data.dof.aperture_fstop = 2.8


# ------------------------------------------------------------------ main
sc = reset()
if CLS == "car":
    load_car()
else:
    load_craft()
lo, hi = bounds()
span = max((hi - lo).y, (hi - lo).x, 3.0)
# boats: sit at the waterline (GLB origin = waterline); others on the ground
if CLS == "car":
    showroom(span)
else:
    outdoors("air" if CLS in ("heli", "plane") else "sea", span)
for v in VIEWS:
    camera(v, lo, hi)
    sc.render.filepath = os.path.join(OUT, "%s_%s.png" % (MODEL, v))
    bpy.ops.render.render(write_still=True)
    print("CATALOG", MODEL, v, flush=True)
