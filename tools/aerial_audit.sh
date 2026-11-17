#!/usr/bin/env bash
# Aerial realism audit: fixed helicopter, street and shoreline cameras for
# before/after comparison, with the render cost of every frame.
#   tools/aerial_audit.sh <out_dir> [name ...]     (JOBS=2 parallel by default)
# Each view: name:at_x,at_z:cam_x,cam_y,cam_z,look_x,look_y,look_z
# (world metres; cam/look y are above the ground there; the hero stands at
# at_x,at_z, which also centres the streaming). heli_ref1 is the user's
# helicopter screenshots of 2026-11-17: ref1 877 ft south of the Commercial
# Island, ref2 879 ft over Skyport looking west, ref3 1,318 ft west of Westbank.
# Prints one RENDER_STATS line per view (draw calls, primitives, memory).
set -uo pipefail
cd "$(dirname "$0")/.."
out=${1:?out dir}; shift || true
mkdir -p "$out"
views=(
  # Helicopter altitude (877 ft ≈ 267 m, 2,000 ft ≈ 610 m).
  "heli_ref1:250,600:150,267,830,400,0,400"
  "heli_ref2:-300,1200:0,267,1170,-700,0,950"
  "heli_ref3:-800,0:-1650,400,380,-450,0,-180"
  "heli_2000ft:250,600:-100,610,1700,250,0,300"
  "heli_skyline:600,0:1150,267,450,550,0,-250"
  "heli_westbank:-700,0:-450,267,700,-850,0,-100"
  "heli_mountains:-700,0:-500,300,600,-1800,150,-1400"
  "heli_airport:-300,1500:200,200,1150,-450,0,1550"
  # Low passes and street level.
  "airport_low:-376,1558:-200,45,1450,-450,4,1620"
  "cbd_street:470,-195:470,3,-195,560,25,-260"
  "westbank_street:-800,0:-800,3,0,-760,8,-60"
  # Shorelines.
  "shore_headland:420,560:390,8,760,470,0,620"
  "shore_skyport:-700,1500:-860,10,1460,-700,0,1560"
  "shore_seawall:200,585:300,6,640,180,2,560"
  # Bridge ends (city and Skyport sides), from the air and from the road.
  "harbour_city_end:200,585:250,10,520,140,8,660"
  "westbank_city_end:-560,458:-600,10,400,-500,8,540"
  "harbour_ramp:236,545:236,3.5,545,175,3,611"
  "westbank_ramp:-587,414:-587,7,414,-544,6,485"
  "skyport_bridges:-200,980:-120,60,860,-220,4,1000"
  "bridges_air:-150,700:150,200,1050,-200,0,650"
)
want=" $* "
pids=()
for v in "${views[@]}"; do
  n=${v%%:*}; r=${v#*:}; at=${r%%:*}; cam=${r#*:}
  if [ $# -gt 0 ] && [[ "$want" != *" $n "* ]]; then continue; fi
  timeout 400 xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-method mobile --resolution 1452x600 res://scenes/main.tscn -- \
    --play --new --hour=14 --at=$at --cam=$cam --nohud --stats --shot="$out/$n.png" --shot-at=22 > "$out/$n.log" 2>&1 &
  pids+=($!)
  if [ ${#pids[@]} -ge ${JOBS:-2} ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); fi
done
wait
grep -h "RENDER_STATS\|SCRIPT ERROR" "$out"/*.log || true
