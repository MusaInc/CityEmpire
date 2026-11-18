"""WorldState street and park trees, near LOD (TreeKit draws its procedural
trees as the mid/far LOD).

Run:  blender -b --factory-startup --python tools/blender/ws_trees.py -- <out dir> [species,...]

Each species is grown, not blobbed: a curved, tapering trunk; primary limbs
set at the species' angles and spread; two more orders of branches; leaf
masses as many small irregular clumps on the outer twigs (so light gets
between them and the silhouette is broken), shaded darker inside the crown
and underneath. Everything is opaque (no alpha-cut cards: cheap on iPhone
GPUs); vertex colour carries the species colour with alpha 1 = foliage and
0 = bark, as tree.gdshader expects (it sways foliage, tints it per tree and
adds leaf breakup). Foliage normals bend outward from the crown centre so
the crown lights as a volume, not as facets. ~1.6-2.2k triangles a tree.

  plane   London plane: tall clear trunk, broad irregular crown, mottled bark
  lime    lime / linden: dense upright oval crown
  birch   silver birch: white banded trunk, airy drooping crown
  pine    Scots pine: bare orange-brown trunk, flat-topped tiers of needle pads
  cherry  flowering cherry: short trunk, wide vase of pink blossom
  poplar  Lombardy poplar: tight upright column
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector as V, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "assets/models"
ONLY = set(ARGS[1].split(",")) if len(ARGS) > 1 and ARGS[1] else set()
os.makedirs(OUT, exist_ok=True)


def lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


SPECIES = {
    # trunk h, trunk r, limbs, limb angle from vertical (deg), limb len, spread, crown centre y,
    # leaf top/bottom colours (sRGB), bark colour, clump size, clumps per tip, droop
    "plane": dict(th=3.6, tr=0.22, limbs=5, ang=48, ll=2.6, depth=3, leaf=((0.44, 0.6, 0.25), (0.15, 0.25, 0.1)),
                  bark=(0.56, 0.53, 0.43), clump=0.8, per_tip=1, droop=0.0, height=9.0),
    "lime": dict(th=2.8, tr=0.2, limbs=6, ang=30, ll=2.7, depth=3, leaf=((0.48, 0.63, 0.27), (0.17, 0.29, 0.12)),
                 bark=(0.36, 0.3, 0.24), clump=0.72, per_tip=1, droop=0.0, height=10.0),
    "birch": dict(th=3.2, tr=0.14, limbs=6, ang=34, ll=2.2, depth=3, leaf=((0.64, 0.72, 0.32), (0.3, 0.4, 0.16)),
                  bark=(0.87, 0.86, 0.81), clump=0.5, per_tip=1, droop=0.35, height=9.0),
    "pine": dict(th=5.2, tr=0.2, limbs=9, ang=70, ll=2.2, depth=2, leaf=((0.33, 0.48, 0.29), (0.13, 0.24, 0.14)),
                 bark=(0.55, 0.34, 0.22), clump=0.8, per_tip=1, droop=0.1, height=10.5),
    "cherry": dict(th=1.7, tr=0.18, limbs=5, ang=55, ll=2.1, depth=3, leaf=((0.98, 0.74, 0.82), (0.66, 0.42, 0.5)),
                   bark=(0.3, 0.2, 0.18), clump=0.58, per_tip=1, droop=0.0, height=5.2),
    "poplar": dict(th=1.6, tr=0.18, limbs=9, ang=12, ll=3.6, depth=2, leaf=((0.42, 0.57, 0.25), (0.15, 0.25, 0.1)),
                   bark=(0.36, 0.31, 0.25), clump=0.58, per_tip=1, droop=0.0, height=12.5),
}


class Mesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")
        self.leaf_normals = []   # (face, centre) for crown normals

    def tube(self, pts, radii, colour, sides=6, bands=False):
        rings = []
        for i, p in enumerate(pts):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
            t = (b - a).normalized()
            up = V((0, 0, 1)) if abs(t.z) < 0.95 else V((1, 0, 0))
            u = t.cross(up).normalized()
            w = t.cross(u).normalized()
            rings.append([self.bm.verts.new(p + (u * math.cos(k * 2 * math.pi / sides) + w * math.sin(k * 2 * math.pi / sides))
                                            * radii[i]) for k in range(sides)])
        for ri, (r0, r1) in enumerate(zip(rings, rings[1:])):
            for k in range(sides):
                f = self.bm.faces.new((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]))
                for lp in f.loops:
                    c = colour
                    if bands and (lp.vert.co.z * 3.1 + k * 0.37) % 1.0 < 0.17:
                        c = tuple(x * 0.32 for x in colour)
                    shade = 0.85 + 0.15 * math.sin(lp.vert.co.z * 4.0 + k)
                    lp[self.col] = (c[0] * shade, c[1] * shade, c[2] * shade, 0.0)

    def clump(self, centre, size, top, bot, crown_c, crown_r, rnd):
        """A leaf mass: an irregular icosahedron (20 faces) squashed and turned."""
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=1, radius=1.0)
        rot = Matrix.Rotation(rnd.uniform(0, math.pi), 3, V((rnd.random(), rnd.random(), rnd.random())).normalized())
        sc = V((size * rnd.uniform(0.8, 1.25), size * rnd.uniform(0.8, 1.25), size * rnd.uniform(0.55, 0.85)))
        vmap = {}
        for v in tmp.verts:
            d = v.co.copy()
            k = 1.0 + 0.28 * math.sin(d.x * 5.1 + centre.x) * math.sin(d.y * 4.3 + centre.y) * math.sin(d.z * 5.7 + centre.z)
            p = centre + rot @ V((d.x * sc.x, d.y * sc.y, d.z * sc.z)) * k
            vmap[v] = self.bm.verts.new(p)
        for f in tmp.faces:
            nf = self.bm.faces.new([vmap[v] for v in f.verts])
            for lp in nf.loops:
                p = lp.vert.co
                # Darker inside the crown and underneath, lighter on the sunny top.
                rel = (p - crown_c)
                outer = min(1.0, rel.length / max(crown_r, 0.1))
                h = max(0.0, min(1.0, 0.5 + 0.5 * rel.z / max(crown_r, 0.1)))
                t = 0.25 + 0.45 * h + 0.3 * outer
                jit = rnd.uniform(0.9, 1.08)
                c = tuple((b + (a - b) * t) * jit for a, b in zip(top, bot))
                lp[self.col] = (c[0], c[1], c[2], 1.0)
            self.leaf_normals.append((nf, crown_c))
        tmp.free()


def grow(sp, P, rnd):
    m = Mesh()
    bark = lin(P["bark"])
    top, bot = lin(P["leaf"][0]), lin(P["leaf"][1])
    H = P["height"]
    # Trunk: a gently curving line.
    lean = V((rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15), 1.0)).normalized()
    trunk_top = V((0, 0, 0)) + lean * P["th"]
    tpts = [V((0, 0, 0)).lerp(trunk_top, i / 5) + V((rnd.uniform(-0.04, 0.04), rnd.uniform(-0.04, 0.04), 0)) for i in range(6)]
    full_h = P["th"] + (H - P["th"]) * (0.75 if sp in ("pine", "poplar") else 0.45)
    # Leader continues up through the crown (thin).
    leader_top = V((0, 0, full_h))
    lpts = [trunk_top.lerp(leader_top, i / 4) for i in range(5)]
    m.tube(tpts, [P["tr"] * (1.25 if i == 0 else 1.0 - 0.25 * i / 5) for i in range(6)], bark, 7, bands=(sp == "birch"))
    m.tube(lpts, [P["tr"] * 0.72 * (1 - 0.8 * i / 4) for i in range(5)], bark, 5, bands=(sp == "birch"))
    crown_c = V((0, 0, (P["th"] + H) * 0.5 + (0.6 if sp == "cherry" else 0.0)))
    crown_r = (H - P["th"]) * 0.5 + 0.6
    tips = []

    def branch(start, direction, length, radius, depth):
        n = 4
        end = start + direction * length
        # Bend: up for most, down at the tips for birch, flat for pine.
        sag = V((0, 0, -P["droop"] * length * 0.5))
        pts = [start.lerp(end, i / (n - 1)) + sag * math.sin(math.pi * i / (n - 1)) * (i / (n - 1)) for i in range(n)]
        m.tube(pts, [radius * (1 - 0.6 * i / (n - 1)) for i in range(n)], bark, 5 if depth == 1 else 4)
        if depth >= P["depth"]:
            # Foliage along the whole outer twig, not only at its end
            # (crowns read as dense masses with gaps, not a few puffs).
            for q in pts[1:]:
                tips.append((q, direction))
            return
        if depth == P["depth"] - 1 and sp == "pine":
            for q in pts[2:]:
                tips.append((q, direction))
        kids = 3 if depth == 1 else 2
        for k in range(kids):
            t = 0.45 + 0.5 * k / max(kids - 1, 1)
            at = pts[0].lerp(pts[-1], t)
            ax = direction.cross(V((0, 0, 1))).normalized() if abs(direction.z) < 0.98 else V((1, 0, 0))
            spin = Matrix.Rotation(rnd.uniform(0, 2 * math.pi), 3, direction)
            tilt = Matrix.Rotation(math.radians(rnd.uniform(25, 45)), 3, ax)
            nd = (spin @ (tilt @ direction)).normalized()
            if sp == "poplar":
                nd = (nd + V((0, 0, 1.6))).normalized()
            if sp == "pine":
                nd = (nd * V((1, 1, 0.3))).normalized()
            branch(at, nd, length * rnd.uniform(0.5, 0.65), radius * 0.55, depth + 1)

    # Primary limbs: from the trunk top (pine: whorls up the leader).
    for i in range(P["limbs"]):
        a = i * 2 * math.pi / P["limbs"] + rnd.uniform(-0.3, 0.3)
        el = math.radians(P["ang"] + rnd.uniform(-8, 8))
        d = V((math.cos(a) * math.sin(el), math.sin(a) * math.sin(el), math.cos(el))).normalized()
        if sp == "pine":
            z = P["th"] + (full_h - P["th"]) * (i / P["limbs"]) ** 0.8
            start = V((0, 0, z))
            length = P["ll"] * (1.15 - 0.6 * i / P["limbs"])
        elif sp == "poplar":
            start = V((0, 0, P["th"] + (full_h - P["th"]) * i / P["limbs"] * 0.8))
            length = P["ll"] * (1.0 - 0.45 * i / P["limbs"])
        else:
            start = trunk_top.lerp(lpts[2], rnd.uniform(0.0, 1.0))
            length = P["ll"] * rnd.uniform(0.85, 1.15)
        branch(start, d, length, P["tr"] * 0.6, 1)
    # Leaf clumps on the twig tips (pine: flat needle pads; cherry: blossom).
    for (p, d) in tips:
        for k in range(P["per_tip"]):
            off = V((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.4, 0.8))) * P["clump"] * 0.6
            size = P["clump"] * rnd.uniform(0.75, 1.2)
            if sp == "pine":
                m.clump(p + off * V((1, 1, 0.3)), size, top, bot, crown_c, crown_r, rnd)
            else:
                m.clump(p + off, size, top, bot, crown_c, crown_r, rnd)
    # A crown cap so the top isn't see-through (not for pine/poplar tips).
    if sp not in ("pine",):
        for k in range(6 if sp != "poplar" else 8):
            a = rnd.uniform(0, 2 * math.pi)
            r = crown_r * rnd.uniform(0.1, 0.45) * (0.4 if sp == "poplar" else 1.0)
            z = crown_c.z + crown_r * rnd.uniform(0.1, 0.55) * (1.6 if sp == "poplar" else 1.0)
            m.clump(V((math.cos(a) * r, math.sin(a) * r, z)), P["clump"] * 1.3, top, bot, crown_c, crown_r, rnd)
    return m


def finish(m, name):
    me = bpy.data.meshes.new(name)
    faces_leaf = {f.index: c for f, c in m.leaf_normals} if False else None
    m.bm.to_mesh(me)
    # Foliage normals: outward from the crown centre blended with the face
    # (soft volume lighting); bark keeps its own.
    col = me.color_attributes["Col"]
    me.color_attributes.active_color = col
    normals = []
    for loop in me.loops:
        v = me.vertices[loop.vertex_index]
        normals.append(None)
    crown = sum((v.co for v in me.vertices), V()) / max(len(me.vertices), 1)
    for poly in me.polygons:
        is_leaf = col.data[poly.loop_start].color[3] > 0.5
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            if is_leaf:
                n = ((v - V((0, 0, crown.z))).normalized() * 0.7 + poly.normal * 0.3).normalized()
            else:
                n = poly.normal.copy()
            normals[li] = n
    for poly in me.polygons:
        poly.use_smooth = True   # (flat faces export face normals: the crowns came out faceted)
    me.normals_split_custom_set(normals)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new("tree")
    me.materials.append(mat)
    return ob


def export(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_vertex_color="NAME",
                              export_vertex_color_name="Col", export_all_vertex_colors=False)
    # (with "ACTIVE" the exporter wrote a white COLOR_0 and the real colours
    # as COLOR_1, which Godot ignores: the trees came out white)


for sp, P in SPECIES.items():
    if ONLY and sp not in ONLY:
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rnd = random.Random(sum(map(ord, sp)) * 7919)   # (hash() is salted per run)
    m = grow(sp, P, rnd)
    ob = finish(m, "tree_" + sp)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    export(ob, os.path.join(OUT, "tree_%s.glb" % sp))
    print("TREE", sp, "tris", tris, "height", round(max(v.co.z for v in ob.data.vertices), 2))
print("TREES DONE")
