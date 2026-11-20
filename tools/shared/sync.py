#!/usr/bin/env python3
"""Musa shared foundation sync (WorldState = source of truth).

  tools/shared/sync.py            report: which shared files differ per game
  tools/shared/sync.py --apply    copy every 'copy' entry that differs (and
                                  its .import/.uid sidecars when present)
  tools/shared/sync.py --game cityswing   limit to one game
  tools/shared/sync.py --pin      record in each game's tools/shared/pinned.json
                                  the WorldState SHA and a sha256 per shared
                                  file it now holds (its accepted revision)

Sidecars: a differing .import (import settings) is reported and copied with
--apply; .uid files are never compared (each project's own identity).
Pins: the report flags a game file changed since it was pinned (a game-side
edit to bring back to WorldState, or to keep as an override).

'merged' entries are never copied: they keep game-specific changes and are
only reported with a rough count of differing lines. Commit in each repo
after --apply (each game stays independently buildable).
"""
import argparse, datetime, difflib, filecmp, hashlib, json, os, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def differing_lines(a, b):
    try:
        la = open(a, encoding="utf-8").read().splitlines()
        lb = open(b, encoding="utf-8").read().splitlines()
    except UnicodeDecodeError:
        return -1
    return sum(1 for l in difflib.unified_diff(la, lb, lineterm="", n=0)
               if l[:1] in "+-" and not l.startswith(("+++", "---")))


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()[:16] if os.path.exists(p) else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--game")
    ap.add_argument("--pin", action="store_true")
    a = ap.parse_args()
    man = json.load(open(os.path.join(ROOT, "tools/shared/manifest.json")))
    drift = 0
    pins = {}
    for g, rel in man["games"].items():
        pp = os.path.normpath(os.path.join(ROOT, rel, "tools/shared/pinned.json"))
        pins[g] = json.load(open(pp)) if os.path.exists(pp) else {"files": {}}
    for e in man["entries"]:
        src = os.path.join(ROOT, e["path"])
        for g in e["to"]:
            if a.game and g != a.game:
                continue
            dst = os.path.normpath(os.path.join(ROOT, man["games"][g], e["path"]))
            if not os.path.exists(src):
                print(f"MISSING-SRC {e['path']}")
                continue
            pinned = pins[g]["files"].get(e["path"])
            if pinned and os.path.exists(dst) and sha(dst) != pinned:
                print(f"edited   {g:10s} {e['path']}  (changed in the game since it was pinned)")
            side = ".import"  # (.uid differs per project by design: never compared)
            if os.path.exists(src + side) and os.path.exists(dst + side) and not filecmp.cmp(src + side, dst + side, shallow=False):
                print(f"sidecar  {g:10s} {e['path']}{side}  import settings differ")
                if a.apply and e["mode"] == "copy":
                    shutil.copy2(src + side, dst + side)
            if os.path.exists(dst) and filecmp.cmp(src, dst, shallow=False):
                continue
            drift += 1
            if e["mode"] == "merged":
                n = differing_lines(src, dst) if os.path.exists(dst) else "new"
                print(f"merged   {g:10s} {e['path']}  ({n} lines differ; merge by hand)")
                continue
            print(f"{'copy' if a.apply else 'differs'}  {g:10s} {e['path']}")
            if a.apply:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
                for side in (".import", ".uid"):
                    if os.path.exists(src + side) and not os.path.exists(dst + side):
                        shutil.copy2(src + side, dst + side)
    if drift == 0:
        print("all shared files in sync")
    if a.pin:
        head = subprocess.run(["git", "-C", ROOT, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        for g, rel in man["games"].items():
            if a.game and g != a.game:
                continue
            files = {e["path"]: sha(os.path.normpath(os.path.join(ROOT, rel, e["path"])))
                     for e in man["entries"] if g in e["to"]}
            out = {"source": "WorldState", "source_sha": head,
                   "pinned_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
                   "note": "sha256[:16] of each shared file as this game holds it (copy = WorldState's; merged = this game's own merge)",
                   "files": files}
            pp = os.path.normpath(os.path.join(ROOT, rel, "tools/shared/pinned.json"))
            os.makedirs(os.path.dirname(pp), exist_ok=True)
            json.dump(out, open(pp, "w"), indent=1)
            print(f"pinned   {g:10s} {len(files)} files at {head[:8]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
