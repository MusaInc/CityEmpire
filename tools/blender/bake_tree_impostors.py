"""Tree impostors: each TreeKit species (world_tree_<sp>_far.glb) rendered
side-on into one small RGBA atlas, for the distant trees drawn as two
crossed cards (TreeImpostors). Without them trees existed only within 320 m
of a streamed chunk and appeared in front of you as you drove.

Run:  blender -b --factory-startup --python tools/blender/bake_tree_impostors.py -- <repo>
Writes assets/world/tree_impostors.png (3 × 256 wide, 256 tall: oak, birch,
pine) – each cell framed on the tree's own bounds, trunk base at the bottom
centre (TreeImpostors sizes its cards from the same bounds in Godot).
"""
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
REPO = ARGS[0] if ARGS else "."
SPECIES = ["oak", "birch", "pine"]
CELL = 256


def bake(sp):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(REPO, "assets/models/world_tree_%s_far.glb" % sp))
    obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in obs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    h = hi.z - lo.z
    wdt = max(hi.x - lo.x, hi.y - lo.y)
    size = max(h, wdt)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = CELL
    sc.view_settings.view_transform = "Standard"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = size
    sc.collection.objects.link(cam)
    # Square frame: trunk base at the bottom centre.
    cam.location = (0.0, -60.0, lo.z + size * 0.5)
    cam.rotation_euler = (1.5708, 0.0, 0.0)
    sc.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.2
    sun.rotation_euler = (0.9, 0.3, -0.5)
    sc.collection.objects.link(sun)
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.65, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    path = os.path.join(bpy.app.tempdir, "imp_%s.png" % sp)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(CELL, CELL, 4)
    print("IMPOSTOR", sp, "h %.2f w %.2f" % (h, wdt))
    return px


cells = [bake(sp) for sp in SPECIES]
atlas = np.concatenate(cells, axis=1)
# (The canopy cards are semi-transparent: from far away a crown reads as a
# solid mass, so densify the alpha and deepen the leaf colour a little.)
atlas[:, :, 3] = np.clip(atlas[:, :, 3] * 2.6 - 0.05, 0.0, 1.0)
atlas[:, :, :3] = np.clip(atlas[:, :, :3] * 0.8, 0.0, 1.0)
# Bleed colour into the clear texels (no dark fringes when mipmapped).
rgb = atlas[:, :, :3].copy()
a = atlas[:, :, 3].copy()
for _ in range(8):
    acc = np.zeros_like(rgb)
    cnt = np.zeros_like(a)
    for s, ax in ((1, 0), (-1, 0), (1, 1), (-1, 1)):
        acc += np.roll(rgb * (a[:, :, None] > 0.05), s, axis=ax)
        cnt += np.roll((a > 0.05).astype(np.float32), s, axis=ax)
    fill = (a <= 0.05) & (cnt > 0)
    rgb[fill] = acc[fill] / cnt[fill][:, None]
    a = np.where(fill, 0.06, a)
atlas[:, :, :3] = rgb
im = bpy.data.images.new("tree_impostors", CELL * len(SPECIES), CELL, alpha=True)
im.pixels = atlas.ravel()
im.filepath_raw = os.path.join(REPO, "assets/world/tree_impostors.png")
im.file_format = "PNG"
im.save()
print("ATLAS", im.filepath_raw)
