#!/usr/bin/env python3
"""targets.jsonl (--photo-targets) -> a --tour file: name:at_x,at_z:from,to
(hero/streaming at the target, absolute heights)."""
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f, open(dst, "w") as o:
    for ln in f:
        t = json.loads(ln)
        name = (t["id"] + "_" + t["view"]).replace(":", "_").replace("/", "_").replace(" ", "_")
        fr, to = t["from"], t["to"]
        o.write("%s:%.2f,%.2f:%s\n" % (name, to[0], to[2], ",".join("%.2f" % v for v in fr + to)))
