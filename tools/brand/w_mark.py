#!/usr/bin/env python3
"""WorldState brand mark: one gold W (high-contrast thick/thin strokes).

  python3 tools/brand/w_mark.py <out_dir> [--preview]

Writes the mark geometry (assets/brand/w_mark.json, unit box), the alpha mask
the game tints in a shader (w_mask.png), the app icon (icon_1024.png), the
launch splash (launch.png) and a review sheet. One geometry for everything.
"""
import json, math, sys, os
from PIL import Image, ImageDraw, ImageFilter

# ---- geometry (unit box: x 0..1, y 0..H, y down) -------------------------
# A high-contrast W: thick down-strokes, hairline up-strokes, pointed base
# vertices and a flat-cut middle apex – a type-cut letter, nothing added.
H = 0.78
THICK = 0.165   # down-strokes (horizontal width)
THIN = 0.050    # up-strokes
BL, BR, MID = 0.262, 0.738, 0.5   # base vertices and the middle apex

def _x(a, b, c, d):
    """Intersection of line ab with line cd."""
    (x1, y1), (x2, y2), (x3, y3), (x4, y4) = a, b, c, d
    den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
    return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))

def strokes():
    P1, P2 = (BL, H), (BR, H)
    q1 = _x((THICK, 0), (BL + THICK, H), (MID - THIN / 2, 0), (BL - THIN, H))
    q2 = _x((MID + THICK / 2, 0), (BR + THICK, H), (1 - THIN, 0), (BR - THIN, H))
    return [
        [(0, 0), (THICK, 0), q1, P1],                              # thick down
        [(MID - THIN / 2, 0), (MID + THIN / 2, 0), P1, q1],        # hairline up
        [(MID - THICK / 2, 0), (MID + THICK / 2, 0), q2, P2],      # thick down
        [(1 - THIN, 0), (1, 0), P2, q2],                           # hairline up
    ]

def clip_bottom(polys):
    return polys

def draw_mask(w_px, pad=0.0, ss=4):
    """Alpha mask of the W filling w_px wide (height = w_px*H) at ss x supersample."""
    W = int(w_px * ss); Hh = int(w_px * H * ss)
    im = Image.new("L", (W, Hh), 0)
    d = ImageDraw.Draw(im)
    for p in strokes():
        d.polygon([(x * W, y * W) for x, y in p], fill=255)
    # clip anything outside the cap/base lines (vertex overshoot)
    return im.resize((int(w_px), int(w_px * H)), Image.LANCZOS)

GOLD = [(0.00, (246, 226, 168)), (0.38, (225, 189, 106)), (0.70, (196, 152, 72)), (1.00, (160, 116, 46))]
def gold_at(t):
    for (a, ca), (b, cb) in zip(GOLD, GOLD[1:]):
        if t <= b:
            k = (t - a) / (b - a)
            return tuple(int(ca[i] + (cb[i] - ca[i]) * k) for i in range(3))
    return GOLD[-1][1]

def gold_fill(w, h):
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            # mostly vertical, slight diagonal so the strokes read as metal
            t = min(1, max(0, (y / h) * 0.85 + (x / w) * 0.15))
            px[x, y] = gold_at(t)
    return im

NAVY_TOP, NAVY_BOT = (16, 24, 40), (6, 9, 17)
SPLASH_BG = (9, 13, 22)   # = project.godot boot_splash/bg_color and Brand.NAVY_DEEP
def navy_bg(w, h, glow=True, flat=False):
    if flat:
        return Image.new("RGB", (w, h), SPLASH_BG)
    im = Image.new("RGB", (w, h))
    px = im.load()
    cx, cy = w * 0.5, h * 0.42
    R = math.hypot(w, h) * 0.6
    for y in range(h):
        for x in range(w):
            t = y / h
            c = [NAVY_TOP[i] + (NAVY_BOT[i] - NAVY_TOP[i]) * t for i in range(3)]
            if glow:
                g = max(0.0, 1.0 - math.hypot(x - cx, y - cy) / R)
                c = [c[0] + 10 * g * g, c[1] + 12 * g * g, c[2] + 18 * g * g]
            px[x, y] = tuple(int(v) for v in c)
    return im

def compose(size_w, size_h, mark_w, cy_frac=0.5, glow=True, flat=False):
    bg = navy_bg(size_w, size_h, glow, flat)
    m = draw_mask(mark_w)
    g = gold_fill(m.width, m.height)
    x = (size_w - m.width) // 2
    y = int(size_h * cy_frac - m.height / 2)
    # soft shadow under the mark for depth on the icon
    if not flat:
        sh = Image.new("L", bg.size, 0); sh.paste(m, (x, y + int(mark_w * 0.012)))
        sh = sh.filter(ImageFilter.GaussianBlur(mark_w * 0.02))
        bg = Image.composite(Image.new("RGB", bg.size, (2, 3, 6)), bg, sh.point(lambda v: v * 0.55))
    bg.paste(g, (x, y), m)
    return bg

def wordmark(height=120, ink=(241, 236, 226)):
    """W + tracked WORLDSTATE caps (Inter Medium), transparent background."""
    from PIL import ImageFont
    here = os.path.dirname(os.path.abspath(__file__))
    font = ImageFont.truetype(os.path.join(here, "../../assets/fonts/inter/Inter-Medium.ttf"), int(height * 0.52))
    mw = int(height / H)
    m = draw_mask(mw)
    g = gold_fill(m.width, m.height)
    track = int(height * 0.16)
    text = "WORLDSTATE"
    widths = [font.getbbox(c)[2] for c in text]
    tw = sum(widths) + track * (len(text) - 1)
    gap = int(height * 0.42)
    im = Image.new("RGBA", (mw + gap + tw + 4, height), (0, 0, 0, 0))
    im.paste(g, (0, 0), m)
    d = ImageDraw.Draw(im)
    x = mw + gap
    asc, desc = font.getmetrics()
    y = (height - int(height * 0.52 * 0.73)) // 2 - (asc - int(height * 0.52 * 0.73))
    for c, w in zip(text, widths):
        d.text((x, y), c, font=font, fill=ink + (255,))
        x += w + track
    return im


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    json.dump({"aspect": H, "strokes": strokes()}, open(os.path.join(out, "w_mark.json"), "w"), indent=1)
    mask = draw_mask(1024)
    full = Image.new("L", (1024, 1024), 0); full.paste(mask, (0, (1024 - mask.height) // 2))
    mask.save(os.path.join(out, "w_mask.png"))
    compose(1024, 1024, 520, 0.5).save(os.path.join(out, "icon_1024.png"))
    # launch: square, mark at 22% of the side (boot.gd draws it the same size)
    compose(2048, 2048, int(2048 * 0.22), 0.5, glow=False, flat=True).save(os.path.join(out, "launch.png"))
    wordmark(120).save(os.path.join(out, "wordmark.png"))
    if "--preview" in sys.argv:
        sheet = Image.new("RGB", (1400, 560), (40, 40, 44))
        ic = compose(1024, 1024, 520, 0.5)
        sheet.paste(ic.resize((512, 512), Image.LANCZOS), (20, 24))
        x = 560
        for s in (180, 120, 87, 60, 40, 29):
            t = ic.resize((s, s), Image.LANCZOS)
            r = Image.new("L", (s, s), 0); ImageDraw.Draw(r).rounded_rectangle((0, 0, s - 1, s - 1), s * 0.225, fill=255)
            sheet.paste(t, (x, 40), r); x += s + 24
        sheet.save(os.path.join(out, "review.png"))
