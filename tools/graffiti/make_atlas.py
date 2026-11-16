"""Graffiti atlas for building.gdshader.

    python3 tools/graffiti/make_atlas.py

Reads art/graffiti/sheet_*.jpg (3 x 3 pieces each on white), keys out the
white background (flood-filled from each cell's edge, so white fills inside
letters stay), trims each piece, centres it in a 256 px cell (4 px clear
border against mip bleed) and writes assets/world/graffiti_atlas.png: 8 x 4
cells, pieces in reading order sheet by sheet (27 used).
"""
import glob
import os
import subprocess
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CELL, COLS, ROWS, PAD = 256, 8, 4, 4


def load(path):
    w, h = map(int, subprocess.check_output(["magick", "identify", "-format", "%w %h", path]).split())
    raw = subprocess.check_output(["magick", path, "-colorspace", "sRGB", "-depth", "8", "rgb:-"])
    return np.frombuffer(raw, np.uint8).reshape(h, w, 3).astype(np.float32)


def background(img):
    mn = img.min(axis=2)
    sat = img.max(axis=2) - mn
    cand = (mn > 222) & (sat < 26)
    bg = np.zeros_like(cand)
    bg[0, :], bg[-1, :], bg[:, 0], bg[:, -1] = cand[0, :], cand[-1, :], cand[:, 0], cand[:, -1]
    while True:   # flood fill by dilation inside the candidates
        grow = bg.copy()
        grow[1:, :] |= bg[:-1, :]
        grow[:-1, :] |= bg[1:, :]
        grow[:, 1:] |= bg[:, :-1]
        grow[:, :-1] |= bg[:, 1:]
        grow &= cand
        if (grow == bg).all():
            return bg
        bg = grow


def edge_scraps(fg):
    """Foreground touching the cell's edge that is only a scrap (a
    neighbouring piece's drip crossing the grid line)."""
    seed = np.zeros_like(fg)
    seed[0, :], seed[-1, :], seed[:, 0], seed[:, -1] = fg[0, :], fg[-1, :], fg[:, 0], fg[:, -1]
    comp = seed
    while True:
        grow = comp.copy()
        grow[1:, :] |= comp[:-1, :]
        grow[:-1, :] |= comp[1:, :]
        grow[:, 1:] |= comp[:, :-1]
        grow[:, :-1] |= comp[:, 1:]
        grow &= fg
        if (grow == comp).all():
            break
        comp = grow
    return comp if comp.sum() < 0.08 * fg.sum() else np.zeros_like(fg)


def blur(a):
    p = np.pad(a, 1, mode="edge")
    return sum(p[dy:dy + a.shape[0], dx:dx + a.shape[1]] for dy in range(3) for dx in range(3)) / 9.0


def resize(rgba, size):
    h, w = rgba.shape[:2]
    raw = np.clip(rgba, 0, 255).astype(np.uint8).tobytes()
    out = subprocess.check_output(["magick", "-size", f"{w}x{h}", "-depth", "8", "rgba:-", "-filter", "Lanczos",
                                   "-resize", f"{size}x{size}", "rgba:-"], input=raw)
    s = int(round(max(w, h) and size * min(w, h) / max(w, h)))
    nh, nw = (size, s) if h >= w else (s, size)
    return np.frombuffer(out, np.uint8).reshape(nh, nw, 4).astype(np.float32)


def main():
    atlas = np.zeros((ROWS * CELL, COLS * CELL, 4), np.float32)
    n = 0
    for sheet in sorted(glob.glob(os.path.join(ROOT, "art/graffiti/sheet_*.jpg"))):
        img = load(sheet)
        H, W = img.shape[:2]
        for r in range(3):
            for c in range(3):
                cell = img[r * H // 3:(r + 1) * H // 3, c * W // 3:(c + 1) * W // 3]
                fg = (~background(cell)).astype(np.float32)
                alpha = blur(blur(fg))
                # Lift the white fringe off the edges (un-mix from white).
                a3 = np.maximum(alpha, 0.05)[..., None]
                rgb = np.clip((cell - (1.0 - a3) * 255.0) / a3, 0, 255)
                rgb = np.where(alpha[..., None] > 0.99, cell, rgb)
                ys, xs = np.nonzero(alpha > 0.04)
                y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
                piece = np.dstack([rgb, alpha * 255.0])[y0:y1, x0:x1]
                small = resize(piece, CELL - 2 * PAD)
                ph, pw = small.shape[:2]
                cy, cx = (n // COLS) * CELL, (n % COLS) * CELL
                oy, ox = cy + (CELL - ph) // 2, cx + (CELL - pw) // 2
                atlas[oy:oy + ph, ox:ox + pw] = small
                n += 1
    out = os.path.join(ROOT, "assets/world/graffiti_atlas.png")
    raw = np.clip(atlas, 0, 255).astype(np.uint8).tobytes()
    subprocess.run(["magick", "-size", f"{COLS * CELL}x{ROWS * CELL}", "-depth", "8", "rgba:-", out], input=raw, check=True)
    print(f"{n} pieces -> {out}")


main()
