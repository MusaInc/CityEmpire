#!/usr/bin/env python3
"""Top-down paint map of a city's streets, straight from the baked road field
(tools/roads/dump_field.gd) with ground.gdshader's marking rules (no noise,
no wear), plus defect highlighting:

  magenta   asphalt that no road's carriageway covers (unmarked tarmac:
            a surface/field mismatch)
  orange    pavement/grass where the field says carriageway (a kerb drawn
            through a road)
  cyan      paint on a junction box or on pavement (should never happen)

  paint_map.py <dump_dir> <island|westbank> <out.png> [x0 z0 x1 z1] [--px=0.25]
Prints counts of each defect class (m²) and the worst clusters.
"""
import json, sys, os, subprocess, math
import numpy as np

args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--"))
d, isl, out = args[0], args[1], args[2]
M = json.load(open(os.path.join(d, isl + ".json")))
F = np.fromfile(os.path.join(d, isl + "_field.f32"), dtype=np.float32).reshape(M["h"], M["w"], 4)
F = F.astype(np.float16).astype(np.float32)   # (the GPU texture is RGBA half)
px = float(opts.get("px", "0.25"))
rx, rz, cell = M["rect"][0], M["rect"][1], M["cell"]
if len(args) >= 7:
    x0, z0, x1, z1 = map(float, args[3:7])
else:
    xs = [p[0] for p in M["coast"]]; zs = [p[1] for p in M["coast"]]
    x0, z0, x1, z1 = min(xs) - 10, min(zs) - 10, max(xs) + 10, max(zs) + 10
W = int((x1 - x0) / px); H = int((z1 - z0) / px)
X = x0 + (np.arange(W) + 0.5) * px
Z = z0 + (np.arange(H) + 0.5) * px


def fill(polys, value, grid):
    """Even-odd scanline fill of polygon rings (list of rings) into grid."""
    for ring_set in polys:
        edges = []
        for ring in ring_set:
            r = np.array(ring, dtype=np.float64)
            if len(r) < 3:
                continue
            a = r; b = np.roll(r, -1, axis=0)
            edges.append(np.concatenate([a, b], axis=1))
        if not edges:
            continue
        E = np.concatenate(edges)
        zmin = max(E[:, [1, 3]].min(), z0); zmax = min(E[:, [1, 3]].max(), z1)
        j0 = max(int((zmin - z0) / px) - 1, 0); j1 = min(int((zmax - z0) / px) + 2, H)
        for j in range(j0, j1):
            z = Z[j]
            za, zb = E[:, 1], E[:, 3]
            m = (za <= z) != (zb <= z)
            if not m.any():
                continue
            e = E[m]
            t = (z - e[:, 1]) / (e[:, 3] - e[:, 1])
            xi = np.sort(e[:, 0] + t * (e[:, 2] - e[:, 0]))
            for k in range(0, len(xi) - 1, 2):
                i0 = max(int(math.ceil((xi[k] - x0) / px - 0.5)), 0)
                i1 = min(int(math.floor((xi[k + 1] - x0) / px - 0.5)) + 1, W)
                if i1 > i0:
                    grid[j, i0:i1] = value


# Ground: 0 sea, 1 asphalt, 2 pavement, 3 grass
G = np.zeros((H, W), np.uint8)
fill([[M["coast"]]], 1, G)
for b in M["blocks"]:
    v = 3 if b["kind"] in ("park", "green") else 2
    fill([[b["poly"]] + b["holes"]], v, G)

# Field: blended by hand like ground.gdshader's road_sample().
u = (X - rx) / cell - 0.5
v = (Z - rz) / cell - 0.5
iu = np.clip(np.floor(u).astype(int), 0, M["w"] - 2); fu = np.clip(u - np.floor(u), 0, 1)
iv = np.clip(np.floor(v).astype(int), 0, M["h"] - 2); fv = np.clip(v - np.floor(v), 0, 1)
T = [F[iv][:, iu], F[iv][:, iu + 1], F[iv + 1][:, iu], F[iv + 1][:, iu + 1]]
FU = fu[None, :]; FV = fv[:, None]
WT = [(1 - FU) * (1 - FV), FU * (1 - FV), (1 - FU) * FV, FU * FV]
near_i = (FU >= 0.5).astype(int) + 2 * (FV >= 0.5).astype(int)
tn = np.choose(near_i[..., None] * np.ones((1, 1, 4), int), T)
xs = np.stack([t[..., 0] for t in T]); hws = np.abs(np.stack([t[..., 1] for t in T]))
mag = (np.abs(xs) > hws + 1.0).any(axis=0)
xs = np.where(mag[None], np.abs(xs), xs)
# (Texels of another road – a jump bigger than the cell – take the nearest
# texel's offset: blended across two roads, 'across' swept through 0 and
# every line value along a junction box's edge: squiggles.)
xn = np.choose(near_i, xs)
xs = np.where(np.abs(xs - xn[None]) > 1.6 * cell, xn[None], xs)
zs = np.stack([t[..., 2] for t in T]); zl = zs - np.floor(zs / 64.0) * 64.0
dz = zl - zl[0:1]
zl = zl + 64.0 * (dz < -32) - 64.0 * (dz > 32)
wts = np.stack(np.broadcast_arrays(*WT))
rf = np.zeros(tn.shape, np.float32)
rf[..., 0] = (xs * wts).sum(0)
rf[..., 1] = tn[..., 1]
rf[..., 2] = np.mod((zl * wts).sum(0), 64.0) + np.floor(tn[..., 2] / 64.0) * 64.0
rf[..., 3] = (np.stack([t[..., 3] for t in T]) * wts).sum(0)
outside = ((X[None, :] < rx) | (X[None, :] > rx + M["w"] * cell) | (Z[:, None] < rz) | (Z[:, None] > rz + M["h"] * cell))
rf[outside] = (100.0, 0.0, 0.0, 100.0)

def band(x, w, aa):
    return 1.0 - np.clip((np.abs(x) - w) / aa + 0.5, 0.0, 1.0)

aa = px * 0.6
hw = np.abs(rf[..., 1])
f2 = np.mod(hw * 2.0, 1.0)
ring = ((f2 >= 0.3) & (f2 <= 0.7)).astype(np.float32)
hw = hw - 0.25 * ring
a = np.abs(rf[..., 0])
on = a < hw
other = rf[..., 3]
kerb = np.minimum(a - hw, other)
across = rf[..., 0]
avenue = (rf[..., 1] < 0).astype(np.float32)
zf = np.floor(rf[..., 2] / 64.0)
along = rf[..., 2] - zf * 64.0
flag_side = np.where(zf < 1.5, 1.0, -1.0)
arm = (1 - ring) * (zf >= 0.5)
from_j = other
lane = on & (other > 0)
lines_from = np.where(arm > 0.5, 10.0, np.where(avenue > 0.5, 6.0, 5.6))
# Junction straight ahead along the road? (ground.gdshader: j_aligned)
gaz, gax = np.gradient(along)
gaz = gaz * (np.abs(gaz) < 8 * px); gax = gax * (np.abs(gax) < 8 * px)
gfz, gfx = np.gradient(other)
fj_cos = (gax * gfx + gaz * gfz) / (np.hypot(gax, gaz) * np.hypot(gfx, gfz) + 1e-5)
j_aligned = np.clip((np.abs(fj_cos) - 0.72) / 0.1, 0, 1)
yel = ring < 0.5
centre = np.where((avenue > 0.5) & (ring < 0.5), band(a - 0.22, 0.07, aa) * (from_j >= lines_from),
                  band(across, 0.07, aa) * (from_j >= lines_from) * (np.mod(along / 9.0, 1.0) <= 0.333))
divider = avenue * (1 - ring) * (hw >= 10.0) * band(a - 5.1, 0.07, aa) * (from_j >= lines_from) * (np.mod(along / 9.0, 1.0) <= 0.33)
edge = avenue * (1 - ring) * band(a - (hw - 2.5), 0.07, aa) * (from_j >= lines_from)
z_lo = np.where(arm > 0.5, 5.5, 1.0)
zu = np.mod((across + hw - 1.5) / 1.2, 1.0)
zebra = band(zu - 0.5, 0.25, aa / 1.2) * (from_j <= z_lo + 3.0) * (from_j >= z_lo) * (a <= hw - 1.0) * (1 - ring) * j_aligned
stop = band(from_j - 4.8, 0.22, aa) * (a >= 0.3) * (a <= hw - 0.3) * (1 - ring) * (1 - arm) * j_aligned
entry = arm * (across * flag_side >= 0) * (a >= 1.4) * (a <= hw - 0.3)
giveway = j_aligned * entry * np.maximum(band(from_j - 0.45, 0.15, aa), band(from_j - 1.05, 0.15, aa)) * (np.mod(a, 1.0) <= 0.6)
ghost = j_aligned * arm * (from_j >= 0.3) * (from_j <= z_lo - 0.7) * (a <= 1.25) * np.maximum(band(a - 1.15, 0.07, aa), band(np.mod((along + a) / 1.4, 1.0) - 0.5, 0.12, aa / 1.4))
ring_in = ring * (across * flag_side >= 0)
ring_edge = ring * (1 - ring_in) * band(a - (hw - 0.45), 0.07, aa) * (from_j >= 1.5)
apron = ring_in * (a >= hw - 3.0)
apron_line = ring_in * band(a - (hw - 3.15), 0.1, aa)
bays = (1 - avenue) * (1 - ring) * (1 - arm) * (hw >= 6.9) * (from_j >= 8.0)
bay_edge = band(a - (hw - 2.55), 0.05, aa) * bays
bay_tick = band(np.mod(along / 13.5, 1.0) * 13.5 - 6.75, 0.05, aa) * (a >= hw - 2.55) * (a <= hw - 0.45) * bays
white_p = np.maximum.reduce([divider, edge, zebra, stop, giveway, ghost, ring_edge, apron_line, bay_edge * 0.9, bay_tick * 0.9]) * lane
yellow_p = centre * lane * yel
white_p = np.maximum(white_p, centre * lane * ~yel)
apron_p = apron * lane

img = np.zeros((H, W, 3), np.float32)
img[G == 0] = (0.12, 0.25, 0.38)
img[G == 1] = (0.27, 0.27, 0.28)
img[G == 2] = (0.66, 0.66, 0.63)
img[G == 3] = (0.32, 0.5, 0.25)
img[(G == 1) & on & (other <= 0)] = (0.31, 0.31, 0.32)          # junction box
kerbstone = (G == 2) & (kerb >= 0) & (kerb < 0.32)
img[kerbstone] = (0.82, 0.82, 0.8)
tact = (G == 2) & ((a - hw) <= 1.15) & (other >= z_lo) & (other <= z_lo + 3.0)
img[tact] = (0.74, 0.62, 0.42)
asph = (G == 1)[..., None]
img = np.where(asph & (apron_p[..., None] > 0.5), np.array([0.47, 0.43, 0.4]), img)
img = np.where(asph, img * (1 - white_p[..., None]) + np.array([0.92, 0.92, 0.88]) * white_p[..., None], img)
img = np.where(asph, img * (1 - yellow_p[..., None]) + np.array([0.92, 0.76, 0.25]) * yellow_p[..., None], img)
# Defects.
unmarked = (G == 1) & ~on
kerb_through = (G >= 2) & on & (a < hw - 0.6)
img[unmarked] = img[unmarked] * 0.4 + np.array([0.9, 0.1, 0.8]) * 0.6
img[kerb_through] = img[kerb_through] * 0.4 + np.array([1.0, 0.5, 0.0]) * 0.6
area = px * px
print(f"PAINT_MAP {isl}: unmarked asphalt {unmarked.sum() * area:.0f} m², kerb through carriageway {kerb_through.sum() * area:.0f} m²")


def clusters(mask, label, n=12, cellm=12.0):
    cs = max(int(cellm / px), 1)
    hh, ww = mask.shape[0] // cs, mask.shape[1] // cs
    m = mask[:hh * cs, :ww * cs].reshape(hh, cs, ww, cs).sum(axis=(1, 3)) * area
    idx = np.dstack(np.unravel_index(np.argsort(-m.ravel()), m.shape))[0][:n]
    for (j, i) in idx:
        if m[j, i] < 3.0:
            break
        print(f"  {label} {m[j, i]:.0f} m² @ {x0 + (i + 0.5) * cs * px:.0f},{z0 + (j + 0.5) * cs * px:.0f}")

clusters(unmarked, "unmarked")
clusters(kerb_through, "kerb_through")
ppm = out + ".ppm"
with open(ppm, "wb") as fh:
    fh.write(b"P6 %d %d 255\n" % (W, H))
    fh.write((np.clip(img, 0, 1) * 255).astype(np.uint8).tobytes())
subprocess.run(["convert", ppm, out], check=True)
os.remove(ppm)
