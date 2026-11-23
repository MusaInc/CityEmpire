"""Export the new collection against the approved Jules authoring file."""
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hero_export import export_playable
from jules_collection import build_jules_collection

destination = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
destination.mkdir(parents=True, exist_ok=True)
rig = bpy.data.objects['CourierRig']
objects = [obj for obj in rig.children if obj.type == 'MESH']
build_jules_collection(rig, objects)
export_playable(bpy, rig, objects, destination / 'character_b.glb', 'b')
bpy.ops.wm.save_as_mainfile(filepath=str(destination / 'courier_b.blend'), compress=True)
