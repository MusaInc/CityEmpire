#!/usr/bin/env python3
"""Character texture import policy (run after `godot --headless --editor --import --quit`
whenever the build adds textures; then import again).

Godot extracts the GLB's embedded textures as assets/models/character_*.png
and gives new ones lossless, full-size imports. Every character texture must
instead be VRAM-compressed (ASTC/ETC2 on iPhone) with mipmaps and a size cap:
  *_normal / *_norm  -> normal-map compression, 1024 (garment bodies 2048: seams/stitches)
  *_orm              -> 512
  everything else    -> 1024 (512 for skin/flat albedos)
Prints what it changed; exit 0 either way.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAP_512 = ('_orm', 'skin_albedo', 'shirt_body_albedo', 'trim_albedo', 'top_knit_normal', 'top_tee_albedo', 'top_polo_albedo',
           'top_jumper_albedo', 'top_blazer_albedo', 'face_', 'hair_')

changed = []
for imp in sorted((ROOT / 'assets/models').glob('character_*.png.import')) + [ROOT / 'assets/models/fabric_weave_normal.png.import',
                                                                             ROOT / 'assets/models/skin_pore_normal.png.import']:
    if not imp.exists():
        continue
    s = imp.read_text()
    stem = imp.name[:-len('.png.import')]
    normal = stem.endswith(('_normal', '_norm')) or 'normals' in stem
    cap = 512 if any(k in stem for k in CAP_512) else 1024
    if 'hair_locks_atlas' in stem:
        cap = 1024
    if stem in ('fabric_weave_normal', 'skin_pore_normal'):
        cap = 0
    want = {'compress/mode': '2', 'compress/normal_map': '1' if normal else '0', 'mipmaps/generate': 'true',
            'process/size_limit': str(cap), 'detect_3d/compress_to': '1'}
    t = s
    for k, v in want.items():
        t = re.sub(r'^%s=.*$' % re.escape(k), '%s=%s' % (k, v), t, flags=re.M)
    if t != s:
        imp.write_text(t)
        changed.append(stem)
print('IMPORT POLICY updated:', ', '.join(changed) if changed else 'nothing')
