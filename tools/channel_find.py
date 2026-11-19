#!/usr/bin/env python3
"""Slivers of sea between two pieces of land, from tools/channel_scan.gd's raster.
A sea cell is a sliver when land lies within MAX_W metres on both sides along
one of four axes (the two pieces facing each other across a narrow strip).
Clusters them; prints the biggest with their extent and mean width.
    python3 tools/channel_find.py <grid.bin> [max_width_m=14] [min_cells=6]"""
import struct, sys
import numpy as np

path = sys.argv[1]
max_w = float(sys.argv[2]) if len(sys.argv) > 2 else 14.0
min_cells = int(sys.argv[3]) if len(sys.argv) > 3 else 6
with open(path, "rb") as f:
    nx, nz = struct.unpack("<II", f.read(8))
    x0, z0, step = struct.unpack("<fff", f.read(12))
    g = np.frombuffer(f.read(nx * nz), dtype=np.uint8).reshape(nz, nx)
land = g == 1
sea = g == 0
k = int(max_w / step)
best = np.full(g.shape, np.inf)
for dz, dx in [(0, 1), (1, 0), (1, 1), (1, -1)]:
    unit = step * (2 ** 0.5 if dz and dx else 1.0)
    fwd = np.full(g.shape, np.inf)
    bwd = np.full(g.shape, np.inf)
    for s in range(k, 0, -1):
        sh = np.roll(np.roll(land, -s * dz, 0), -s * dx, 1)
        fwd[sh] = s * unit
        sh = np.roll(np.roll(land, s * dz, 0), s * dx, 1)
        bwd[sh] = s * unit
    best = np.minimum(best, fwd + bwd)
cand = sea & (best <= max_w)
# Cluster (8-connected).
from collections import deque
seen = np.zeros_like(cand)
out = []
for j, i in zip(*np.nonzero(cand)):
    if seen[j, i]:
        continue
    q = deque([(j, i)]); seen[j, i] = True; cells = []
    while q:
        a, b = q.popleft(); cells.append((a, b))
        for da in (-1, 0, 1):
            for db in (-1, 0, 1):
                c, d = a + da, b + db
                if 0 <= c < nz and 0 <= d < nx and cand[c, d] and not seen[c, d]:
                    seen[c, d] = True; q.append((c, d))
    if len(cells) >= min_cells:
        cz = np.array([c[0] for c in cells]); cx = np.array([c[1] for c in cells])
        w = np.mean([best[c] for c in cells])
        out.append((len(cells), x0 + cx.min() * step, z0 + cz.min() * step, x0 + cx.max() * step, z0 + cz.max() * step, w))
out.sort(reverse=True)
for n, ax, az, bx, bz, w in out[:40]:
    print(f"CHANNEL {n:4d} cells  x {ax:7.0f}..{bx:7.0f}  z {az:6.0f}..{bz:6.0f}  ~{w:4.1f} m wide  ({bx-ax:.0f} x {bz-az:.0f} m)")
print(f"{len(out)} clusters of >= {min_cells} cells")
