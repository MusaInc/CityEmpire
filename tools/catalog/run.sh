#!/usr/bin/env bash
# Catalogue photography: Blender studio renders of every purchasable vehicle,
# aircraft and boat -> assets/ui/catalog/<model>_<view>.jpg (1280x720, q84).
#   tools/catalog/run.sh [model ...]     (default: every priced model)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RAW="${CAT_RAW:-$HOME/.cache/ce-catalog-raw}"
DST="$ROOT/assets/ui/catalog"
mkdir -p "$RAW" "$DST"
MODELS=("$@")
if [ ${#MODELS[@]} -eq 0 ]; then
  mapfile -t MODELS < <(python3 -I -c '
import json,sys
m=json.load(open(sys.argv[1]))["models"]
print("\n".join(k for k,v in m.items() if not k.startswith(("street_","used_"))))' "$ROOT/config/empire/vehicles.json")
fi
for M in "${MODELS[@]}"; do
  if [ -z "${CAT_FORCE:-}" ] && [ -f "$DST/${M}_detail.jpg" ]; then continue; fi
  blender -b --factory-startup --python "$ROOT/tools/blender/render_catalog.py" -- "$ROOT" "$RAW" "$M" 2>&1 | grep -E "^CATALOG|Error|Traceback" || true
  for V in hero side rear detail; do
    [ -f "$RAW/${M}_${V}.png" ] && convert "$RAW/${M}_${V}.png" -strip -quality 84 -sampling-factor 4:2:0 "$DST/${M}_${V}.jpg"
  done
done
du -sh "$DST"
