#!/usr/bin/env python3
"""Musa shared foundation sync (WorldState = source of truth).

  tools/shared/sync.py            report: which shared files differ per game
  tools/shared/sync.py --apply    copy every 'copy' entry that differs (and
                                  its .import/.uid sidecars when present)
  tools/shared/sync.py --game cityswing   limit to one game

'merged' entries are never copied: they keep game-specific changes and are
only reported with a rough count of differing lines. Commit in each repo
after --apply (each game stays independently buildable).
"""
import argparse, difflib, filecmp, json, os, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def differing_lines(a, b):
    try:
        la = open(a, encoding="utf-8").read().splitlines()
        lb = open(b, encoding="utf-8").read().splitlines()
    except UnicodeDecodeError:
        return -1
    return sum(1 for l in difflib.unified_diff(la, lb, lineterm="", n=0)
               if l[:1] in "+-" and not l.startswith(("+++", "---")))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--game")
    a = ap.parse_args()
    man = json.load(open(os.path.join(ROOT, "tools/shared/manifest.json")))
    drift = 0
    for e in man["entries"]:
        src = os.path.join(ROOT, e["path"])
        for g in e["to"]:
            if a.game and g != a.game:
                continue
            dst = os.path.normpath(os.path.join(ROOT, man["games"][g], e["path"]))
            if not os.path.exists(src):
                print(f"MISSING-SRC {e['path']}")
                continue
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
