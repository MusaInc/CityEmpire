#!/usr/bin/env bash
# Whole-map audit views (three islands, bridges, airport, coasts, ground).
# Same cameras every run, for before/after comparison.
#   tools/map_audit.sh <out_dir> [name ...]     (JOBS=2 parallel by default)
# Each view: name:at_x,at_z:cam_x,cam_y,cam_z,look_x,look_y,look_z (world metres;
# the hero stands at at_x,at_z, which also centres the streaming)
set -uo pipefail
cd "$(dirname "$0")/.."
out=${1:?out dir}; shift || true
mkdir -p "$out"
views=(
  "all_south:-200,1500:-250,1500,3300,-250,0,500"
  "all_north:200,-200:300,1300,-1900,-250,0,700"
  "skyport_air:-300,1500:650,480,600,-380,0,1450"
  "skyport_west:-700,1500:-1350,260,1500,-500,0,1450"
  "terminal_land:-376,1558:-372,3.2,1536,-398,6,1700"
  "terminal_air:-560,1650:-640,40,1780,-430,6,1600"
  "airport_entry:-200,1100:-160,30,1040,-330,4,1250"
  "port_east:60,1350:330,110,1350,40,0,1380"
  "skyport_quay:-200,980:-120,22,860,-220,4,1000"
  "harbour_bridge:100,800:330,45,880,40,12,740"
  "harbour_city_end:200,585:250,10,520,140,8,660"
  "westbank_bridge:-450,700:-700,45,860,-420,12,690"
  "westbank_city_end:-560,458:-600,10,400,-500,8,540"
  "strait:-200,-20:-260,70,-330,-200,10,60"
  "commercial_south:500,620:520,35,950,500,15,520"
  "westbank_west:-1150,0:-1500,60,250,-1000,15,0"
  "commercial_east:1050,0:1450,70,250,900,20,-50"
  "cbd_street:470,-195:470,3,-195,560,25,-260"
  "westbank_street:-800,0:-800,3,0,-760,8,-60"
  "skyport_town:20,1180:-40,6,1150,40,8,1220"
  "harbour_ramp:236,545:236,3.5,545,175,3,611"
  "harbour_ramp_side:236,545:234,25,636,190,2,595"
  "westbank_ramp:-587,414:-587,7,414,-544,6,485"
  "westbank_ramp_side:-587,414:-500,25,442,-552,4,472"
)
want=" $* "
pids=()
for v in "${views[@]}"; do
  n=${v%%:*}; r=${v#*:}; at=${r%%:*}; cam=${r#*:}
  # (--view is relative to the hero, who stands at --at: convert.)
  cam=$(awk -v a="$at" -v c="$cam" 'BEGIN{split(a,A,",");split(c,C,",");
    printf "%g,%g,%g,%g,%g,%g", C[1]-A[1], C[2], C[3]-A[2], C[4]-A[1], C[5], C[6]-A[2]}')
  if [ $# -gt 0 ] && [[ "$want" != *" $n "* ]]; then continue; fi
  timeout 400 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method mobile --resolution 1280x720 res://scenes/main.tscn -- \
    --play --new --hour=14 --at=$at --view=$cam --nohud --shot="$out/$n.png" --shot-at=22 > "$out/$n.log" 2>&1 &
  pids+=($!)
  if [ ${#pids[@]} -ge ${JOBS:-2} ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); fi
done
wait
