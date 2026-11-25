#!/bin/bash
# WorldState vehicle texture pipeline over the fleet (tools/blender/ws_texture.py).
#   tools/vehicle_tex/run.sh [name-regex]     e.g. 'kestrel|wheel_kestrel'
# Library first, then each GLB in place: unwrap + bake + re-export, checked
# against the original geometry (tools/vehicle_tex/verify_geometry.py; the
# originals are kept in $ORIG, default art/vehicle_tex_orig - gitignored).
# Bodies before their entries (entries take the processed body's UVs).
set -uo pipefail
cd "$(dirname "$0")/../.."
FILTER=${1:-.*}
ORIG=${ORIG:-art/vehicle_tex_orig}
TEX=assets/vehicles/tex
mkdir -p "$HOME/.cache/ws_vehicle_tex"
TMP=$(mktemp -d -p "$HOME/.cache/ws_vehicle_tex")   # (/tmp is a small RAM disk on the VPS)
mkdir -p "$TEX" "$ORIG"
BL="blender -b --factory-startup --python tools/blender/ws_texture.py --"
if [ -z "${SKIP_LIB:-}" ]; then $BL library "$TEX" 2>&1 | grep -E "^LIB|Error|Traceback"; fi

jobs=()
# name|dir|res|kind
for b in kestrel courier_van civ_box marlin scout brute vanta goliath warden halcyon stiletto \
         police_patrol police_interceptor police_heavy mammoth civ_bus \
         civ_sedan civ_compact civ_suv civ_taxi civ_van civ_police civ_ambulance; do
  r=2048; case $b in civ_sedan|civ_compact|civ_suv|civ_taxi|civ_van|civ_police|civ_ambulance) r=1024;; esac
  jobs+=("$b|assets/vehicles|$r|body")
done
for b in kestrel marlin scout brute vanta goliath warden halcyon; do jobs+=("${b}_traffic|assets/vehicles|1024|body"); done
for b in kestrel marlin scout brute vanta goliath warden halcyon civ_sedan civ_compact civ_suv civ_taxi civ_van civ_police civ_ambulance; do
  jobs+=("${b}_lod1|assets/vehicles|512|body"); done
for w in blade center deep dish five kestrel mesh multi offroad rally split steel traffic turbine y5; do
  jobs+=("wheel_$w|assets/vehicles|512|wheel"); done
for e in assets/vehicle_entries/*.glb; do jobs+=("$(basename "$e" .glb)|assets/vehicle_entries|0|entry"); done
for c in wren kite regent skylark merlin dart swift; do jobs+=("$c|assets/craft|1024|craft"); done
for c in aurora majesty liner; do jobs+=("$c|assets/craft|2048|craft"); done
for m in car_hatch car_sedan car_suv car_taxi car_van; do jobs+=("$m|assets/models|512|body"); done
for m in cargo_ship train_cab train_car; do jobs+=("$m|assets/models|1024|model"); done

fail=0
for j in "${jobs[@]}"; do
  IFS='|' read -r name dir res kind <<< "$j"
  echo "$name" | grep -Eq "^($FILTER)$" || continue
  [ -n "${KIND:-}" ] && [ "$kind" != "$KIND" ] && continue
  src="$dir/$name.glb"
  [ -f "$src" ] || { echo "SKIP $src (missing)"; continue; }
  keep="$ORIG/${dir#assets/}/$name.glb"
  mkdir -p "$(dirname "$keep")"
  [ -f "$keep" ] || cp "$src" "$keep"
  out="$TMP/$name.glb"
  start=$(date +%s)
  if [ "$kind" = entry ]; then
    $BL vehicle "$keep" "$out" - 0 entry "assets/vehicles/$name.glb" > "$TMP/log" 2>&1
  else
    bake="$TEX/${name}_bake.png"
    [ "$dir" = assets/vehicle_entries ] && bake=-
    $BL vehicle "$keep" "$out" "$bake" "$res" "$kind" > "$TMP/log" 2>&1
  fi
  if ! grep -q "^DONE" "$TMP/log"; then
    echo "FAIL $name"; grep -E "Error|Traceback|line" "$TMP/log" | tail -5; fail=1; continue
  fi
  # (Blender can re-derive a few normals beside zero-area triangles: copy
  # the originals back, then check again.)
  if python3 tools/vehicle_tex/verify_geometry.py "$keep" "$out" > /dev/null || \
     { python3 tools/vehicle_tex/restore_normals.py "$keep" "$out" && python3 tools/vehicle_tex/verify_geometry.py "$keep" "$out"; }; then
    cp "$out" "$src"
    echo "  $name: $(grep -E '^UNWRAP' "$TMP/log" | cut -c8-) $(( $(date +%s) - start ))s"
  else
    echo "FAIL geometry $name (kept original)"; fail=1
  fi
done
rm -rf "$TMP"
exit $fail
