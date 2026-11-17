#!/usr/bin/env bash
# Character asset rebuild: Blender build -> Godot import -> texture import policy -> reimport.
set -euo pipefail
cd "$(dirname "$0")/../.."
LOG=${LOG:-/tmp/character_build.log}
blender -b --factory-startup --python tools/blender/build_character.py -- assets/models > "$LOG" 2>&1 || { tail -30 "$LOG"; exit 1; }
grep -q "COURIER EXPORTED" "$LOG" || { grep -A15 Traceback "$LOG" | head -40; exit 1; }
grep -E "COURIER EXPORTED|SHIRT|WARDROBE" "$LOG" | cut -c1-200
godot --headless --editor --import --quit > /dev/null 2>&1 || true
python3 tools/character_review/fix_imports.py
godot --headless --editor --import --quit > /dev/null 2>&1 || true
