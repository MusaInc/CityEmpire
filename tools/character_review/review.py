#!/usr/bin/env python3
"""WorldState character reconstruction: milestone captures, before/after
composites and the visual dashboard (art/character_review/index.html).

  python3 tools/character_review/review.py capture <id> [--quick] [--no-blender]
  python3 tools/character_review/review.py compare <id>
  python3 tools/character_review/review.py dashboard

capture  runs the Godot lab (tools/character_lab.gd, game renderer, real
         look/animation path) and the Blender review renders
         (tools/blender/render_character_review.py, Cycles, material + clay)
         into art/character_review/milestones/<id>/{godot,blender}, then
         compare + dashboard.
compare  builds side-by-side BEFORE (01_baseline) | AFTER (<id>) JPEGs for
         every shot both milestones have (identical cameras and lights).
Milestone titles, status and notes live in art/character_review/milestones.json.
Only stdlib + ffmpeg; every image is a real Godot or Blender render.
"""
import html, json, os, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REVIEW = ROOT / 'art/character_review'
MS = REVIEW / 'milestones'
CMP = REVIEW / 'compare'
META = REVIEW / 'milestones.json'
BASE = '01_baseline'
FONT = ROOT / 'assets/fonts/outfit_semibold.ttf'
XVFB = ['xvfb-run', '-a', '-s', '-screen 0 1280x1024x24']


def meta():
    return json.loads(META.read_text()) if META.exists() else {'milestones': []}


def save_meta(m):
    META.write_text(json.dumps(m, indent=2))


def run(cmd, **kw):
    print('$', ' '.join(map(str, cmd)), flush=True)
    return subprocess.run(cmd, check=True, **kw)


def capture(mid, quick=False, blender=True):
    g = MS / mid / 'godot'
    b = MS / mid / 'blender'
    g.mkdir(parents=True, exist_ok=True)
    b.mkdir(parents=True, exist_ok=True)
    jobs = []
    if blender:
        jobs.append(subprocess.Popen(['blender', '-b', '--factory-startup', '--python',
                                      str(ROOT / 'tools/blender/render_character_review.py'), '--',
                                      str(ROOT / 'assets/models/character.glb'), str(b), 'orange_shirt,tee_cap'],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    lab = XVFB + ['godot', '--path', str(ROOT), '--rendering-method', 'mobile', '--resolution', '800x1000',
                  '--fixed-fps', '30', 'res://tools/character_lab.tscn', '--', str(g)]
    if quick:
        run(lab + ['orange_shirt', 'all'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        run(lab[:-1] + [str(g / 'outfits'), 'tee_cap,polo_phones,blazer', 'idle'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for f in (g / 'outfits').glob('*.png'):
            f.replace(g / f.name)
        (g / 'outfits' / 'stats.json').replace(g / 'stats_outfits.json') if (g / 'outfits' / 'stats.json').exists() else None
        (g / 'outfits').rmdir()
    else:
        run(lab + ['all', 'all'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # neutral-light validation close-ups (no shadow can hide a defect)
    run(lab[:-1] + [str(g), 'orange_shirt', 'collar', 'neutral'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for j in jobs:
        j.wait()
    compare(mid)
    m = meta()
    for e in m['milestones']:
        if e['id'] == mid:
            e['captured'] = time.strftime('%Y-%m-%d %H:%M')
    save_meta(m)
    dashboard()


def _label(text):
    t = text.replace(':', '\\:').replace("'", '')
    return (f"drawtext=fontfile='{FONT}':text='{t}':x=14:y=12:fontsize=26:fontcolor=white:"
            "box=1:boxcolor=black@0.55:boxborderw=8")


def compare(mid):
    out = CMP / mid
    out.mkdir(parents=True, exist_ok=True)
    n = 0
    for src in ('godot', 'blender'):
        after_dir = MS / mid / src
        before_dir = MS / BASE / src
        for a in sorted(after_dir.glob('*.png')):
            bfile = before_dir / a.name
            dst = out / f'{src}__{a.stem}.jpg'
            thumb = MS / mid / src / f'{a.stem}.jpg'
            if not thumb.exists() or thumb.stat().st_mtime < a.stat().st_mtime:
                subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', str(a), '-vf', 'scale=480:-2',
                                '-q:v', '4', str(thumb)], check=True)
            if mid == BASE or not bfile.exists():
                continue
            if dst.exists() and dst.stat().st_mtime > max(a.stat().st_mtime, bfile.stat().st_mtime):
                n += 1
                continue
            fc = (f"[0]scale=600:-2,{_label('BEFORE  baseline')}[l];"
                  f"[1]scale=600:-2,{_label('AFTER  ' + mid)}[r];[l][r]hstack=2")
            subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', str(bfile), '-i', str(a),
                            '-filter_complex', fc, '-q:v', '3', str(dst)], check=True)
            n += 1
    print('COMPARE', mid, n, 'pairs', flush=True)


GROUPS = [
    ('Full body (idle)', lambda s: '__idle__' in s and s.split('__')[-1] in ('front', 'three_quarter', 'side', 'rear')),
    ('Close-ups: face, collar, chest, shoulder, cuff, hem', lambda s: '__idle__' in s and s.split('__')[-1] not in ('front', 'three_quarter', 'side', 'rear')),
    ('Walk & run', lambda s: '__walk__' in s or '__run__' in s),
    ('Seated driving, extended & bent arms', lambda s: any(k in s for k in ('__drive__', '__reach__', '__bent__'))),
    ('Neutral-light validation: collar, chest, shoulder', lambda s: s.endswith('__neutral')),
]


def _shots(mid):
    """(group title, [(name, compare jpg or None, after jpg)])"""
    out = []
    for src in ('godot', 'blender'):
        d = MS / mid / src
        if not d.exists():
            continue
        names = sorted(p.stem for p in d.glob('*.png'))
        if src == 'godot':
            for title, pred in GROUPS:
                for outfit in ('orange_shirt', 'tee_cap', 'polo_phones', 'blazer', 'hoodie', 'jumper'):
                    sel = [n for n in names if n.startswith(outfit + '__') and pred(n)]
                    if sel:
                        out.append((f'Godot · {outfit.replace("_", " ")} · {title}', [(n, CMP / mid / f'godot__{n}.jpg', d / f'{n}.jpg') for n in sel]))
        else:
            for outfit in ('orange_shirt', 'tee_cap'):
                mat = [n for n in names if n.startswith(outfit + '__') and '__clay_' not in n]
                clay = [n for n in names if n.startswith(outfit + '__clay_')]
                if clay:
                    out.append((f'Blender Cycles · clay (geometry only) · {outfit.replace("_", " ")}', [(n, CMP / mid / f'blender__{n}.jpg', d / f'{n}.jpg') for n in clay]))
                if mat:
                    out.append((f'Blender Cycles · material · {outfit.replace("_", " ")}', [(n, CMP / mid / f'blender__{n}.jpg', d / f'{n}.jpg') for n in mat]))
    return out


def _stats(mid):
    p = MS / mid / 'godot' / 'stats.json'
    return json.loads(p.read_text()) if p.exists() else {}


def dashboard():
    m = meta()
    rel = lambda p: os.path.relpath(p, REVIEW)
    e = html.escape
    parts = []
    nav = []
    timeline = []
    for ms in m['milestones']:
        mid = ms['id']
        st = ms.get('status', 'pending')
        nav.append(f'<a class="chip {st}" href="#{mid}">{e(ms["title"])}</a>')
        hero = MS / mid / 'godot' / 'orange_shirt__idle__three_quarter.jpg'
        face = MS / mid / 'godot' / 'orange_shirt__idle__face.jpg'
        if hero.exists():
            timeline.append(f'<figure><a href="#{mid}"><img loading="lazy" src="{rel(hero)}"><img loading="lazy" src="{rel(face) if face.exists() else rel(hero)}"></a>'
                            f'<figcaption>{e(ms["title"])}</figcaption></figure>')
        body = [f'<section id="{mid}"><h2><span class="dot {st}"></span>{e(ms["title"])} <small>{e(st)}'
                f'{" · captured " + e(ms["captured"]) if ms.get("captured") else ""}</small></h2>']
        if ms.get('notes'):
            body.append('<ul class="notes">' + ''.join(f'<li>{e(n)}</li>' for n in ms['notes']) + '</ul>')
        if ms.get('issues'):
            body.append('<p class="label">Found in review and fixed / open</p><ul class="notes issues">' + ''.join(f'<li>{e(n)}</li>' for n in ms['issues']) + '</ul>')
        st_ = _stats(mid).get('orange_shirt')
        if st_:
            body.append(f'<p class="stats">Orange outfit in-game: <b>{st_["triangles"]:,}</b> triangles · <b>{st_["draw_surfaces"]}</b> draw surfaces · '
                        f'texture memory {st_["texture_mem_mb"]} MB (whole lab scene)</p>')
        for title, shots in _shots(mid):
            body.append(f'<details {"open" if "orange" in title and "Full" in title else ""}><summary>{e(title)} <small>{len(shots)}</small></summary><div class="grid">')
            for n, c, a in shots:
                img = c if c.exists() else a
                if not img.exists():
                    continue
                full = (MS / mid / ('godot' if 'Godot' in title else 'blender') / f'{n}.png')
                body.append(f'<figure class="{"pair" if c.exists() else ""}"><a href="{rel(full)}" target="_blank"><img loading="lazy" src="{rel(img)}"></a>'
                            f'<figcaption>{e(n.replace("__", " · ").replace("_", " "))}</figcaption></figure>')
            body.append('</div></details>')
        body.append('</section>')
        parts.append(''.join(body))
    page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Character Reconstruction</title><style>
:root{{--bg:#f4f3ef;--fg:#1b1d21;--mut:#6b6f76;--card:#fff;--line:#e2e0da;--ok:#2f8f5b;--wip:#d9822b;--pend:#9aa0a8}}
@media (prefers-color-scheme:dark){{:root{{--bg:#131417;--fg:#ececea;--mut:#9a9ea6;--card:#1c1e22;--line:#2c2f35}}}}
body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}}
header,main{{max-width:1400px;margin:auto;padding:16px}}
h1{{margin:.2em 0;font-size:26px}} h2{{font-size:20px;margin:1.6em 0 .4em}} small{{color:var(--mut);font-weight:400;font-size:13px}}
.chips{{display:flex;flex-wrap:wrap;gap:6px}} .chip{{padding:4px 10px;border-radius:99px;border:1px solid var(--line);text-decoration:none;color:var(--fg);font-size:13px;background:var(--card)}}
.dot{{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:8px;background:var(--pend)}}
.done{{border-color:var(--ok)}} .dot.done{{background:var(--ok)}} .wip{{border-color:var(--wip)}} .dot.wip{{background:var(--wip)}}
.timeline{{display:flex;gap:10px;overflow-x:auto;padding:8px 0}} .timeline figure{{margin:0;flex:0 0 auto;width:220px}}
.timeline img{{width:108px;border-radius:6px;margin-right:4px}} figcaption{{font-size:12px;color:var(--mut)}}
details{{background:var(--card);border:1px solid var(--line);border-radius:10px;margin:8px 0;padding:8px 12px}} summary{{cursor:pointer;font-weight:600}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:10px;margin-top:10px}}
.grid figure{{margin:0}} .grid figure.pair{{grid-column:span 2}} .grid img{{width:100%;border-radius:6px;display:block}}
@media (max-width:700px){{.grid figure.pair{{grid-column:span 1}}}}
.notes li{{margin:2px 0}} .label{{font-weight:600;margin-bottom:0}} .stats{{color:var(--mut)}}
</style></head><body><header><h1>WorldState · Character reconstruction</h1>
<p>Every image is a real render: <b>Godot</b> (the game's mobile renderer, atmosphere and in-game look/animation path, <code>tools/character_lab.gd</code>) and <b>Blender Cycles</b> (<code>tools/blender/render_character_review.py</code>, material and clay passes). Identical cameras and lights at every milestone; pairs show BEFORE (baseline) | AFTER. Updated {e(time.strftime("%Y-%m-%d %H:%M"))}.</p>
<div class="chips">{"".join(nav)}</div>
<h2>Timeline</h2><div class="timeline">{"".join(timeline)}</div></header><main>{"".join(parts)}</main></body></html>'''
    (REVIEW / 'index.html').write_text(page)
    print('DASHBOARD', REVIEW / 'index.html', flush=True)


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'capture':
        capture(sys.argv[2], '--quick' in sys.argv, '--no-blender' not in sys.argv)
    elif cmd == 'compare':
        compare(sys.argv[2])
        dashboard()
    elif cmd == 'dashboard':
        dashboard()
