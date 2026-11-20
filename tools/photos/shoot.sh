#!/bin/bash
# Property photos: every purchasable place, rendered in the real game from
# one start-up (src/empire/dev/tour.gd), estate-agent framing, afternoon sun.
#   1. godot ... -- --play --new --photo-targets=tools/photos/targets.jsonl
#   2. tools/photos/shoot.sh            -> assets/photos/<id>_<view>.jpg (640 px)
#   CLEAR=1: swing blocked views round to a clear line of sight;
#   CLEAR=redo ONLY=a,b: re-shoot only those of a,b that were blocked.
# PhotoBook (src/empire/ui/photo_book.gd) loads them lazily and caches them.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=assets/photos
mkdir -p "$OUT"
python3 tools/photos/make_tour.py tools/photos/targets.jsonl "$OUT/tour.txt"
LP_NUM_THREADS=6 xvfb-run -a -s "-screen 0 960x540x24 -nolisten tcp" godot --rendering-method mobile --resolution 960x540 \
  res://scenes/main.tscn -- --play --new --hour=${HOUR:-14.2} --weather=clear --nohud --tour="$OUT/tour.txt" \
  --tour-wait=${WAIT:-5} --tour-fov=54 --tour-jpg=640 --tour-nohero ${ONLY:+--tour-only=$ONLY} ${CLEAR:+--tour-clear=$CLEAR} 2>&1 | grep -E --line-buffered "TOUR_|SCRIPT|Parse"
rm -f "$OUT/tour.txt"
