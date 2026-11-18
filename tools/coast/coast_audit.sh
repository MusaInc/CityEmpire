#!/usr/bin/env bash
# Coast audit (2026-11-18 coast overhaul): fixed views all round the three
# islands – aerial (150 m out, 75 m up), from a boat (45 m out) and on the
# promenade – rendered from ONE start-up per process (--tour), 2 processes.
#   tools/coast/coast_audit.sh <out_dir> [views.txt]
# Without views.txt the views are picked fresh from the coastlines:
#   godot --headless -s res://tools/coast/coast_dump.gd -- <out>/coasts.json
#   python3 tools/coast/pick_views.py   (reads coasts.json in the cwd)
# Each line: name:at_x,at_z:cam_x,cam_y,cam_z,look_x,look_y,look_z (world m).
# Prints one TOUR_SHOT line per view (draw calls, primitives).
set -u
cd "$(dirname "$0")/../.."
out=${1:?out dir}; mkdir -p "$out"
v=${2:-}
if [ -z "$v" ]; then
  timeout 300 godot --headless -s res://tools/coast/coast_dump.gd -- "$out/coasts.json" >/dev/null 2>&1
  (cd "$out" && python3 "$OLDPWD/tools/coast/pick_views.py" > views.txt)
  v="$out/views.txt"
fi
n=$(grep -c . "$v"); h=$(( (n + 1) / 2 ))
head -$h "$v" > "$out/v1.txt"; tail -n +$((h + 1)) "$v" > "$out/v2.txt"
for k in 1 2; do
  timeout 2400 xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-method mobile --resolution 1280x720 res://scenes/main.tscn -- \
    --play --new --hour=14 --time=14 --nohud --tour="$out/v$k.txt" --tour-wait=${WAIT:-6} > "$out/log$k.txt" 2>&1 &
done
wait
grep -ah "TOUR_SHOT\|SCRIPT ERROR" "$out"/log*.txt
