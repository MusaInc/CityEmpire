#!/usr/bin/env python3
"""Shop sign atlas for ShopfrontKit: config/world/shop_brands.json ->
assets/world/shop_brands.png (2048x2048, 2 columns x 16 rows of 1024x128
fascia boards, row-major). RGB = the painted board with its lettering, A =
the lettering mask (lit at night). ImageMagick only.
  python3 tools/shopfronts/make_atlas.py"""
import json, os, subprocess, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
brands = json.load(open(os.path.join(ROOT, 'config/world/shop_brands.json')))['brands']
W, H = 1024, 128
tmp = tempfile.mkdtemp(dir=os.path.expanduser('~/.cache'))
cells = []
for i, b in enumerate(brands):
    font = os.path.join(ROOT, b['font'])
    txt = os.path.join(tmp, 'txt%02d.png' % i)
    # lettering mask: white text on black, fitted to the board with margins
    subprocess.run(['convert', '-size', '%dx%d' % (W - 120, H - 34), '-background', 'black', '-fill', 'white',
                    '-font', font, '-gravity', 'center', 'label:' + b['name'], txt], check=True)
    cell = os.path.join(tmp, 'cell%02d.png' % i)
    rgb = os.path.join(tmp, 'rgb%02d.png' % i)
    mask = os.path.join(tmp, 'mask%02d.png' % i)
    # mask: the lettering centred on the board plus a thin inset border line
    subprocess.run(['convert', '-size', '%dx%d' % (W, H), 'xc:black', txt, '-gravity', 'center', '-composite',
                    '+gravity', '-fill', 'none', '-stroke', 'white', '-strokewidth', '3',
                    '-draw', 'rectangle 10,10 %d,%d' % (W - 11, H - 11), mask], check=True)
    # board colour with the letter colour where the mask is
    letters = os.path.join(tmp, 'let%02d.png' % i)
    subprocess.run(['convert', '-size', '%dx%d' % (W, H), 'xc:' + b['fg'], mask, '-alpha', 'off',
                    '-compose', 'copy_opacity', '-composite', letters], check=True)
    subprocess.run(['convert', '-size', '%dx%d' % (W, H), 'xc:' + b['bg'], letters,
                    '-compose', 'over', '-composite', rgb], check=True)
    subprocess.run(['convert', rgb, mask, '-alpha', 'off', '-compose', 'copy_opacity', '-composite', cell], check=True)
    cells.append(cell)
rows = []
for r in range(16):
    row = os.path.join(tmp, 'row%02d.png' % r)
    pair = cells[r * 2:r * 2 + 2]
    while len(pair) < 2:
        pair.append(cells[0])
    subprocess.run(['convert'] + pair + ['+append', row], check=True)
    rows.append(row)
out = os.path.join(ROOT, 'assets/world/shop_brands.png')
subprocess.run(['convert'] + rows + ['-append', '-define', 'png:color-type=6', out], check=True)
print('ATLAS', out)
