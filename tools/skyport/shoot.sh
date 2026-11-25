#!/bin/bash
# Skyport review renders: tools/skyport/shoot.sh <out_dir> [weather] [hour]
# Views in tools/skyport/views_local.txt (island-local metres); VIEWS="a b".
# ONE godot at a time on the VPS.
set -uo pipefail
cd "$(dirname "$0")/../.."
out=${1:?out}; w=${2:-clear}; h=${3:-14}
mkdir -p "$out"
python3 - "$out/tour.txt" "${VIEWS:-}" "$h" <<'PY'
import sys
out, only, hour = sys.argv[1], sys.argv[2].split(), sys.argv[3]
def w(x, z):   # SkyportIsland.w2: local (x, z) -> world
    return -200.0 - (z + 36.0), 950.0 + (x - 1432.0)
lines = []
for ln in open("tools/skyport/views_local.txt"):
    ln = ln.strip()
    if not ln or ln.startswith("#"):
        continue
    nm, hero, cam = ln.split(":")
    if only and nm not in only:
        continue
    hx, hz = map(float, hero.split(","))
    c = list(map(float, cam.split(",")))
    a = w(hx, hz); f = w(c[0], c[2]); t = w(c[3], c[5])
    lines.append(f"{nm}_h{hour}:{a[0]:.1f},{a[1]:.1f}:{f[0]:.1f},{c[1]},{f[1]:.1f},{t[0]:.1f},{c[4]},{t[1]:.1f}")
open(out, "w").write("\n".join(lines) + "\n")
PY
LP_NUM_THREADS=6 timeout 2400 xvfb-run -a -s "-screen 0 1280x720x24 -nolisten tcp" godot --rendering-method mobile --resolution 1280x720 \
  res://scenes/main.tscn -- --play --new --hour=$h --weather=$w --nohud --tour="$out/tour.txt" --tour-wait=${WAIT:-7} --tour-nohero ${EXTRA:-} 2>&1 \
  | grep -E --line-buffered "TOUR_|SCRIPT ERROR|ERROR" | grep -v Settings
