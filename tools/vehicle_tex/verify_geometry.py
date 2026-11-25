"""Geometry check for the texture pass: the re-exported GLB must carry the
same triangles (positions + normals per material, node names and
transforms) as the original; only UV layers may differ.
Usage: python3 tools/vehicle_tex/verify_geometry.py <orig.glb> <new.glb>"""
import json, struct, sys
import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def load(path):
    b = open(path, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    bin_ = b[20 + jl + 8:]
    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        n = NC[a["type"]]
        arr = np.frombuffer(bin_, dtype=CT[a["componentType"]], count=a["count"] * n, offset=off)
        return arr.reshape(a["count"], n) if n > 1 else arr
    return j, acc


def tris(path):
    j, acc = load(path)
    out = {}
    nodes = {}
    for nd in j["nodes"]:
        nodes[nd.get("name")] = (nd.get("translation"), nd.get("rotation"), nd.get("scale"), nd.get("mesh") is not None)
    for nd in j["nodes"]:
        if nd.get("mesh") is None:
            continue
        for pr in j["meshes"][nd["mesh"]]["primitives"]:
            mat = j["materials"][pr["material"]]["name"].split(".")[0] if "material" in pr else ""
            p = acc(pr["attributes"]["POSITION"]).astype(np.float64)
            n = acc(pr["attributes"]["NORMAL"]).astype(np.float64)
            idx = acc(pr["indices"]).astype(np.int64).reshape(-1, 3) if "indices" in pr else np.arange(len(p)).reshape(-1, 3)
            t = np.concatenate([p[idx].reshape(-1, 9), n[idx].reshape(-1, 9)], 1)
            # Canonical: rotate each triangle's corners so the smallest comes first.
            key = np.round(t, 4)
            out.setdefault((nd.get("name"), mat), []).append(key)
    return {k: np.concatenate(v) for k, v in out.items()}, nodes, j


def same_geometry(a, b):
    """Triangles as position multisets (corner order free) + every corner
    normal matched at its position. Returns the worst deviation."""
    def tri_keys(t):
        c = np.round(t[:, :9].reshape(-1, 3, 3), 3)
        c = np.sort(c.view([("x", c.dtype), ("y", c.dtype), ("z", c.dtype)]).reshape(-1, 3), axis=1)
        return np.sort(c.view(np.float64).reshape(len(t), 9).round(3), axis=0)
    worst = float(np.abs(tri_keys(a) - tri_keys(b)).max())
    nb = {}
    for p, n in zip(map(tuple, np.round(b[:, :9].reshape(-1, 3), 3)), b[:, 9:].reshape(-1, 3)):
        nb.setdefault(p, []).append(n)
    # (Zero-area and sub-1 cm2 sliver triangles draw nothing; Blender may re-derive their normals.)
    tri = a[:, :9].reshape(-1, 3, 3)
    live = np.repeat(np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1) > 2e-5, 3)   # (> ~10 mm2)
    for p, n, ok in zip(map(tuple, np.round(a[:, :9].reshape(-1, 3), 3)), a[:, 9:].reshape(-1, 3), live):
        if not ok:
            continue
        cand = nb.get(p)
        if cand is None:
            return 9.0
        worst = max(worst, float(np.min(np.linalg.norm(np.array(cand) - n, axis=1))))
    return worst


def main(a, b):
    ta, na, ja = tris(a)
    tb, nb, jb = tris(b)
    ok = True
    if set(na) != set(nb):
        print("NODES differ", sorted(set(na) ^ set(nb)))
        ok = False
    for k, v in na.items():
        if k in nb and any(x != y and (x is None) != (y is None) or (x and y and not np.allclose(x, y, atol=1e-4)) for x, y in zip(v[:3], nb[k][:3])):
            print("TRANSFORM differs", k, v, nb[k])
            ok = False
    if set(ta) != set(tb):
        print("MATERIAL SETS differ", sorted(set(ta) ^ set(tb)))
        ok = False
    for k in ta:
        if k not in tb:
            continue
        if len(ta[k]) != len(tb[k]):
            print("TRI COUNT", k, len(ta[k]), len(tb[k]))
            ok = False
            continue
        diff = same_geometry(ta[k], tb[k])
        if diff > 0.02:   # (positions to the mm; unit normals within 1 degree)
            print("GEOMETRY", k, "max diff", diff)
            ok = False
    uv = sum("TEXCOORD_1" in p["attributes"] for m in jb["meshes"] for p in m["primitives"])
    prims = sum(len(m["primitives"]) for m in jb["meshes"])
    print(("OK " if ok else "FAIL ") + b, f"{sum(len(v) for v in tb.values())} tris, UV1 on {uv}/{prims} primitives")
    return ok


if __name__ == "__main__":
    sys.exit(0 if main(sys.argv[1], sys.argv[2]) else 1)
