#!/bin/bash
# Visual-pass before/after views: tools/visual/shoot.sh <out_dir> [weather] [hour]
# One start-up per weather (tour.gd); ONE godot at a time on the VPS.
set -uo pipefail
cd "$(dirname "$0")/../.."
out=${1:?out}; w=${2:-clear}; h=${3:-14}
mkdir -p "$out"
# VIEWS="a b" limits the set.
grep -v '^#' tools/visual/views.txt | { if [ -n "${VIEWS:-}" ]; then grep -E "^($(echo $VIEWS | tr ' ' '|')):"; else cat; fi; } \
  | sed "s/^\([a-z_]*\):/\1_$w:/" > "$out/tour_$w.txt"
LP_NUM_THREADS=6 timeout 1500 xvfb-run -a -s "-screen 0 1280x720x24 -nolisten tcp" godot --rendering-method mobile --resolution 1280x720 \
  res://scenes/main.tscn -- --play --new --hour=$h --weather=$w --nohud --tour="$out/tour_$w.txt" --tour-wait=${WAIT:-7} --tour-nohero 2>&1 \
  | grep -E --line-buffered "TOUR_|SCRIPT ERROR" | grep -v Settings
