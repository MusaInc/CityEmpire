from pathlib import Path
import sys
import bpy

repo, identity, destination = sys.argv[sys.argv.index('--') + 1:]
sys.path.insert(0, str(Path(repo) / 'tools/blender'))
from hero_export import export_playable
from hero_realism import finish_realism

out = Path(destination)
(out / 'textures').mkdir(parents=True, exist_ok=True)
rig = bpy.data.objects['CourierRig']
meshes = [child for child in rig.children if child.type == 'MESH']
finish_realism(rig, meshes, identity, out / 'textures')
suffix = '' if identity == 'ade' else '_b'
export_playable(bpy, rig, meshes, out / f'character{suffix}.glb', suffix.removeprefix('_'))
bpy.ops.wm.save_as_mainfile(filepath=str(out / f'courier{suffix}.blend'), compress=True)
