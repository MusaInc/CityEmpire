"""Copy the original GLB's vertex normals back onto a re-exported one where
Blender re-derived them (corners of real triangles next to zero-area ones
in a few fleet bodies). Triangles are matched by their exact positions
within a material; a vertex takes the original normal when every triangle
using it agrees. The NORMAL buffer is patched in place.
Usage: python3 tools/vehicle_tex/restore_normals.py <orig.glb> <new.glb>"""
import json, struct, sys
import numpy as np

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from verify_geometry import CT, NC  # noqa: E402


def parse(path):
    b = bytearray(open(path, "rb").read())
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    base = 20 + jl + 8
    return b, j, base


def view(b, j, base, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    off = base + bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    n = NC[a["type"]]
    arr = np.frombuffer(b, dtype=CT[a["componentType"]], count=a["count"] * n, offset=off)
    return (arr.reshape(a["count"], n) if n > 1 else arr), off


def corners(path):
    b, j, base = parse(path)
    out = {}
    for nd in j["nodes"]:
        if nd.get("mesh") is None:
            continue
        for pr in j["meshes"][nd["mesh"]]["primitives"]:
            mat = j["materials"][pr["material"]]["name"].split(".")[0]
            p, _ = view(b, j, base, pr["attributes"]["POSITION"])
            n, _ = view(b, j, base, pr["attributes"]["NORMAL"])
            idx, _ = view(b, j, base, pr["indices"])
            for t in idx.reshape(-1, 3):
                key = (nd.get("name"), mat, tuple(sorted(tuple(np.round(p[k], 4)) for k in t)))
                out[key] = {tuple(np.round(p[k], 4)): n[k].copy() for k in t}
    return out


def main(orig, new):
    ref = corners(orig)
    b, j, base = parse(new)
    fixed = 0
    for nd in j["nodes"]:
        if nd.get("mesh") is None:
            continue
        for pr in j["meshes"][nd["mesh"]]["primitives"]:
            mat = j["materials"][pr["material"]]["name"].split(".")[0]
            p, _ = view(b, j, base, pr["attributes"]["POSITION"])
            n, off = view(b, j, base, pr["attributes"]["NORMAL"])
            idx, _ = view(b, j, base, pr["indices"])
            want = {}
            for t in idx.reshape(-1, 3):
                key = (nd.get("name"), mat, tuple(sorted(tuple(np.round(p[k], 4)) for k in t)))
                src = ref.get(key)
                if src is None:
                    continue
                for k in t:
                    want.setdefault(int(k), []).append(src[tuple(np.round(p[k], 4))])
            new_n = n.copy()
            for k, cands in want.items():
                if all(np.linalg.norm(c - cands[0]) < 0.02 for c in cands) and np.linalg.norm(new_n[k] - cands[0]) > 0.02:
                    new_n[k] = cands[0]
                    fixed += 1
            b[off:off + new_n.nbytes] = new_n.astype(np.float32).tobytes()
    open(new, "wb").write(bytes(b))
    print("restored", fixed, "normals in", new)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
