"""Refit and export an existing fixed hero.

blender -b art/hero/courier.blend --python tools/blender/refit_hero.py -- ade /path/to/output
"""
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hero_export import export_playable
from hero_tailoring import refine_wardrobe


identity, destination = sys.argv[sys.argv.index('--') + 1:]
suffix = {'ade': '', 'jules': '_b'}[identity]
output = Path(destination).resolve()
output.mkdir(parents=True, exist_ok=True)
rig = bpy.data.objects['CourierRig']
meshes = [obj for obj in rig.children if obj.type == 'MESH']
refine_wardrobe(rig, meshes, identity)
export_playable(bpy, rig, meshes, output / f'character{suffix}.glb', suffix.removeprefix('_'))
bpy.ops.wm.save_as_mainfile(filepath=str(output / f'courier{suffix}.blend'), compress=True)
