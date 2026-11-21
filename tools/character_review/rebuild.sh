#!/usr/bin/env bash
# Rebuild the Blender character sources, both gameplay rigs and both crowd LODs.
set -euo pipefail
cd "$(dirname "$0")/../.."
log_dir=${CHARACTER_BUILD_LOG_DIR:-$(mktemp -d /tmp/worldstate-character.XXXXXX)}
mkdir -p "$log_dir"
blender_args=(-b -t "${CHARACTER_BUILD_THREADS:-4}" --factory-startup --python-exit-code 1)

build() {
	local name=$1 script=$2
	if ! OPENBLAS_NUM_THREADS=1 blender "${blender_args[@]}" --python "tools/blender/$script.py" -- assets/models > "$log_dir/$name.log" 2>&1; then
		tail -40 "$log_dir/$name.log"
		exit 1
	fi
	awk '/^COURIER EXPORTED|^CROWD DONE/' "$log_dir/$name.log"
}

for body in ${HERO_BODY:-a b}; do
	HERO_BODY=$body build "hero-$body" build_character
done
CROWD_TARGET=3100 build crowd-near build_crowd
CROWD_TARGET=900 CROWD_OUT=crowd_far.glb build crowd-far build_crowd
godot --headless --editor --import --quit > "$log_dir/import.log" 2>&1
python3 tools/character_review/fix_imports.py
godot --headless --editor --import --quit > "$log_dir/import-textures.log" 2>&1
printf 'Build logs in %s\n' "$log_dir"
