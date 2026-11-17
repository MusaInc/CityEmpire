#!/usr/bin/env bash
# Render road audit views:  tools/roads/shots.sh <views.txt> <out_dir> [game_dir]
# (game_dir: another checkout, e.g. a `git worktree` of the old commit for
# "before"). JOBS parallel (default 3). One PNG + log per view.
set -uo pipefail
views=${1:?views}; out=${2:?out}; game=${3:-$(cd "$(dirname "$0")/../.." && pwd)}
mkdir -p "$out"; views=$(realpath "$views"); out=$(realpath "$out")
cd "$game"
pids=()
while IFS= read -r v; do
  [ -z "$v" ] && continue
  n=${v%%:*}; r=${v#*:}; at=${r%%:*}; cam=${r#*:}
  [ -f "$out/$n.png" ] && continue
  timeout 420 xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-method mobile --resolution 1200x700 res://scenes/main.tscn -- \
    --play --new --hour=13 --at=$at --cam=$cam --nohud --stats --shot="$out/$n.png" --shot-at=20 > "$out/$n.log" 2>&1 &
  pids+=($!)
  if [ ${#pids[@]} -ge ${JOBS:-3} ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); fi
done < "$views"
wait
