#!/usr/bin/env python3
"""Phone launcher tiles (assets/ui/apps/<app>.jpg) from real in-game imagery.

  python3 tools/brand/app_art.py <title_renders_dir>

Sources are the game's own pictures: the Blender studio renders of its cars,
boats, outfits and homes (assets/ui/...) and "art" views shot by the title
camera (--title-tour, config/empire/title_views.json). Each is cropped to the
tile's 16:9, given one shared grade (a touch of contrast, cool shadows, warm
highlights) so the grid reads as one set, and saved small (≈30 KB).
"""
import os, sys
from PIL import Image, ImageEnhance

W, H = 640, 360
# app: (source, (cx, cy) focus in 0..1, zoom ≥ 1)
TITLE = "@"   # prefix: a file in the title renders dir
SOURCES = {
    "businesses": ("assets/photos/shop_-880_-210_front.jpg", (0.5, 0.62), 1.25),
    "bank": (TITLE + "financial_night.png", (0.62, 0.45), 1.3),
    "vehicles": ("assets/ui/catalog/stiletto_hero.jpg", (0.5, 0.42), 1.15),
    "property": ("assets/ui/homes/penthouse.jpg", (0.5, 0.5), 1.0),
    "map": (TITLE + "art_map.png", (0.5, 0.5), 1.0),
    "jobs": ("assets/photos/logistics_front.jpg", (0.5, 0.55), 1.1),
    "market": ("assets/ui/catalog/majesty_hero.jpg", (0.5, 0.5), 1.1),
}


# Wardrobe: a lookbook lineup – the outfit portraits are small (256×308) and
# stand the hero at the same spot, so five full-height slices side by side.
LINEUP = ["ade_suit", "jules_casual", "ade_coat", "jules_formal", "ade_streetwear"]


def lineup():
    n = len(LINEUP)
    sw = W // n
    out = Image.new("RGB", (W, H))
    for i, name in enumerate(LINEUP):
        im = Image.open("assets/ui/hero_outfits/%s.jpg" % name).convert("RGB")
        k = H / im.height
        im = im.resize((round(im.width * k), H), Image.LANCZOS)
        cx = int(0.525 * im.width)
        out.paste(im.crop((cx - sw // 2, 0, cx - sw // 2 + sw, H)), (i * sw, 0))
    return out


def crop(im, focus, zoom):
    sw, sh = im.size
    tw = sw / zoom
    th = tw * H / W
    if th > sh / zoom:
        th = sh / zoom
        tw = th * W / H
    cx, cy = focus[0] * sw, focus[1] * sh
    x0 = min(max(cx - tw / 2, 0), sw - tw)
    y0 = min(max(cy - th / 2, 0), sh - th)
    return im.crop((int(x0), int(y0), int(x0 + tw), int(y0 + th))).resize((W, H), Image.LANCZOS)


def grade(im):
    im = ImageEnhance.Contrast(im).enhance(1.06)
    im = ImageEnhance.Color(im).enhance(0.94)
    r, g, b = im.split()
    # cool the shadows, warm the highlights a little
    b = b.point(lambda v: min(255, int(v + (14 * (1 - v / 255)))))
    r = r.point(lambda v: min(255, int(v + (8 * (v / 255)))))
    return Image.merge("RGB", (r, g, b))


if __name__ == "__main__":
    renders = sys.argv[1]
    out = "assets/ui/apps"
    os.makedirs(out, exist_ok=True)
    for app, (src, focus, zoom) in SOURCES.items():
        path = os.path.join(renders, src[1:]) if src.startswith(TITLE) else src
        if not os.path.exists(path):
            print("missing", app, path)
            continue
        im = grade(crop(Image.open(path).convert("RGB"), focus, zoom))
        dst = os.path.join(out, app + ".jpg")
        im.save(dst, quality=84, optimize=True, progressive=True)
        print(app, os.path.getsize(dst) // 1024, "KB")
    dst = os.path.join(out, "wardrobe.jpg")
    grade(lineup()).save(dst, quality=86, optimize=True, progressive=True)
    print("wardrobe", os.path.getsize(dst) // 1024, "KB")
