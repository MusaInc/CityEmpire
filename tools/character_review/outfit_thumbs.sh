#!/usr/bin/env bash
# Outfit card thumbnails for the Style screen (assets/ui/hero_outfits/<id>.jpg),
# rendered by the GAME (tools/character_lab.tscn, Mobile renderer) from
# config/hero_outfits.json, so a card shows exactly what you'll wear.
#   tools/character_review/outfit_thumbs.sh [id,id,...]
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/outfit-thumbs.XXXXXX)
python3 - "$work/audit.json" "${1:-}" <<'EOF'
import json, sys
only = set(filter(None, sys.argv[2].split(',')))
d = json.load(open('config/hero_outfits.json'))
out = {}
for body, face in (('a', 'hero_ade'), ('b', 'hero_jules')):
    for o in d[body]:
        if only and o['id'] not in only:
            continue
        look = dict(o['look']); look['body'] = body; look['face'] = face
        out[o['id']] = look
json.dump(out, open(sys.argv[1], 'w'))
EOF
xvfb-run -a -s "-screen 0 1280x1024x24" godot --rendering-method mobile --resolution 800x1000 --fixed-fps 30 \
  res://tools/character_lab.tscn -- "$work/out" audit idle game three_quarter "$work/audit.json" > "$work/lab.log" 2>&1
for png in "$work"/out/*__idle__three_quarter*.png; do
  id=$(basename "$png" | sed 's/__idle.*//')
  convert "$png" -resize 256x320 -gravity north -crop 256x308+0+6 +repage -quality 86 "assets/ui/hero_outfits/$id.jpg"
  echo "assets/ui/hero_outfits/$id.jpg"
done
rm -rf "$work"
