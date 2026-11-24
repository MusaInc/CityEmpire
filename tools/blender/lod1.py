"""Mid-distance LOD for any vehicle body: import <name>.glb, join its meshes
(material names kept: traffic shading keys on them), decimate to ~TARGET
triangles, export <name>_lod1.glb next to it.
Run: blender -b --factory-startup --python tools/blender/lod1.py -- assets/vehicles kestrel,marlin,...
"""
import os
import sys

import bpy

ARGS = sys.argv[sys.argv.index("--") + 1:]
DIR = ARGS[0]
NAMES = ARGS[1].split(",")
TARGET = int(ARGS[2]) if len(ARGS) > 2 else 1300
SUFFIX = ARGS[3] if len(ARGS) > 3 else "_lod1"   # "_traffic": the near traffic model (~6k)

for name in NAMES:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(DIR, name + ".glb"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        print("LOD1", name, "no mesh")
        continue
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    dec = ob.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, TARGET / max(tris, 1))
    dec.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="dec")
    ob.data.validate(clean_customdata=False)
    out = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(DIR, name + SUFFIX + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_materials="EXPORT")
    print("LOD1", name, tris, "->", out)
