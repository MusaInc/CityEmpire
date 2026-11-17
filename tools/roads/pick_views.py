#!/usr/bin/env python3
"""Camera views over the road network from tools/road_audit.gd's JSON.
   pick_views.py audit.json > views.txt
Each line: name:at_x,at_z:cam_x,cam_y,cam_z,look_x,look_y,look_z  (world m;
cam/look y above the ground there). Two per target: <name>_a (aerial, 95 m
up, nearly overhead) and <name>_s (driver's eye, 26 m out along an arm)."""
import json, sys, math
A = json.load(open(sys.argv[1]))
targets = []
def spread(items, n):
    if len(items) <= n: return items
    if n == 1: return [items[len(items) // 2]]
    return [items[int(i * (len(items) - 1) / (n - 1))] for i in range(n)]
want = {  # (island, type): how many
    ("island", "T_minor"): 3, ("island", "T_minor_on_major"): 3, ("island", "T_major"): 2,
    ("island", "crossroads"): 4, ("island", "roundabout"): 3, ("island", "roundabout_arm"): 2,
    ("westbank", "T_minor"): 2, ("westbank", "T_minor_on_major"): 2, ("westbank", "crossroads"): 2,
    ("westbank", "roundabout"): 1, ("westbank", "T_major"): 1,
    ("skyport", "node_3"): 5, ("skyport", "node_2"): 2, ("skyport", "end"): 3, ("skyport", "roundabout_arm"): 1,
}
for (isl, ty), n in want.items():
    js = sorted([j for j in A["junctions"] if j["island"] == isl and j["type"] == ty], key=lambda j: (j["at"][0], j["at"][1]))
    for k, j in enumerate(spread(js, n)):
        targets.append((f"{isl[:2]}_{ty}_{k}", j["at"], j.get("dir", [0, 0])))
dk = {}
for d in A["defects"]:
    if d["kind"] in ("grade",): continue
    dk.setdefault((d["island"], d["kind"]), []).append(d)
for (isl, kind), ds in dk.items():
    n = {"close_jn": 4, "off_land": 3}.get(kind, 8)
    for k, d in enumerate(spread(ds, n)):
        targets.append((f"{isl[:2]}_x_{kind}_{k}", d["at"], [0.0, 0.0]))
for name, at, d in targets:
    x, z = at
    hx, hz = x, z
    if "_roundabout_" in name and "arm" not in name:
        hx += 24.0   # (the player can't spawn on the central island: onto the ring)
    dx, dz = d
    if abs(dx) + abs(dz) < 0.1: dx, dz = 0.6, 0.8
    L = math.hypot(dx, dz); dx /= L; dz /= L
    # aerial: back along the arm and to one side, 45 m up
    ax, az = x + dx * 14 - dz * 9, z + dz * 14 + dx * 9
    print(f"{name}_a:{hx:.0f},{hz:.0f}:{ax:.1f},95,{az:.1f},{x:.1f},0,{z:.1f}")
    sx, sz = x + dx * 26 + (-dz) * 2.5, z + dz * 26 + dx * 2.5
    print(f"{name}_s:{hx:.0f},{hz:.0f}:{sx:.1f},1.6,{sz:.1f},{x:.1f},1.2,{z:.1f}")
