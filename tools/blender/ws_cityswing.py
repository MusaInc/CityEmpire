"""CitySwing's traffic cars from the WorldState fleet (tools/blender/ws_fleet.py),
so the third game shares the same vehicles.

Run:  blender -b --factory-startup --python tools/blender/ws_cityswing.py -- <WorldState vehicles dir> <CitySwing models dir>

CitySwing draws traffic as GPU-driven MultiMesh instances of one mesh per
kind (src/world/city_world.gd CAR_KINDS: car_sedan, car_hatch, car_suv,
car_taxi, car_van), one ShaderMaterial per surface keyed by material name
("paint" takes the instance colour, "car_glass" is the glass, "lamp*"
emits). So each car here is: the fleet body thinned to ~3.8k triangles (+1.6k of wheels) (the
lamps, plates, seams and lenses survive; LOD1's 1.1k would lose them), the
light traffic wheel merged in at the four wheel positions, glass renamed.
Same conventions as every WorldState body: +Y forward (Godot -Z), origin on
the ground between the axles.
"""
import json
import math
import os
import sys

import bpy

ARGS = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = ARGS[0], ARGS[1]
KINDS = {"car_sedan": "civ_sedan", "car_hatch": "civ_compact", "car_suv": "civ_suv", "car_taxi": "civ_taxi",
         "car_van": "civ_van"}
TARGET_TRIS = 3800
DIMS = json.load(open(os.path.join(SRC, "bodies.json")))


def imported(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before and o.type == "MESH"]


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


for out_name, body in KINDS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = imported(os.path.join(SRC, body + ".glb"))
    car = parts[0]
    bpy.context.view_layer.objects.active = car
    for o in parts:
        o.select_set(True)
    if len(parts) > 1:
        bpy.ops.object.join()
    car = bpy.context.view_layer.objects.active
    t0 = tris(car)
    if t0 > TARGET_TRIS:
        dec = car.modifiers.new("dec", "DECIMATE")
        dec.ratio = TARGET_TRIS / t0
        bpy.ops.object.modifier_apply(modifier=dec.name)
    d = DIMS[body]
    track = d["W"] - d["tyre_w"] - 0.05
    wheels = []
    for sx in (1, -1):
        for ay in d["axles"]:
            w = imported(os.path.join(SRC, "wheel_traffic.glb"))[0]
            w.rotation_mode = "XYZ"
            w.scale = (d["tyre_w"] / 0.44, d["wheel_r"], d["wheel_r"])
            w.location = (sx * track / 2, ay, d["wheel_r"])
            w.rotation_euler = (0, 0, 0 if sx > 0 else math.pi)
            wheels.append(w)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [car] + wheels:
        o.select_set(True)
    bpy.context.view_layer.objects.active = car
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.join()
    car = bpy.context.view_layer.objects.active
    car.name = "car"
    for s in car.material_slots:
        if s.material and s.material.name.split(".")[0] == "glass":
            s.material.name = "car_glass"
    bpy.ops.export_scene.gltf(filepath=os.path.join(DST, out_name + ".glb"), use_selection=True, export_format="GLB",
                              export_apply=True)
    print("CITYSWING", out_name, "from", body, "tris", tris(car), "(body was", t0, ")")
print("CITYSWING DONE")
