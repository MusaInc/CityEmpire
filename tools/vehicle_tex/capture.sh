#!/bin/bash
# In-game vehicle close-ups: tools/vehicle_tex/capture.sh <out_dir> "<model:view> ..." [hour] [weather]
# One godot at a time on the VPS. Views: front34 rear34 side side_l front rear nose tail.
set -uo pipefail
cd "$(dirname "$0")/../.."
out=${1:?out}; shots=${2:?"model:view ..."}; h=${3:-15}; w=${4:-clear}
mkdir -p "$out"
for s in $shots; do
  m=${s%%:*}; v=${s##*:}
  LP_NUM_THREADS=6 timeout 600 xvfb-run -a -s "-screen 0 1280x720x24 -nolisten tcp" godot --rendering-method mobile --resolution 1280x720 \
    res://scenes/main.tscn -- --play --new --hour=$h --weather=$w --nohud --own=$m --carcam=$v --shot="$out/${m}_${v}.png" --shot-at=${AT:-10} ${EXTRA:-} < /dev/null 2>&1 \
    | grep -E "SCRIPT ERROR|ERROR:" | grep -v Settings | head -5
  echo "shot $out/${m}_${v}.png $(test -f "$out/${m}_${v}.png" && echo ok || echo MISSING)"
done
