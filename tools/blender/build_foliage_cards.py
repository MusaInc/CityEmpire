"""Card foliage: bushes, hedges, shrubs, flower beds and grass tufts built
from alpha-tested cards on one small shared atlas (replaces the faceted
solid hedge_cluster / grass_tuft that read as green rocks and flat grass).

Run:  blender -b --factory-startup --python tools/blender/build_foliage_cards.py -- <repo> [preview.png]

Writes
  assets/world/foliage_atlas.png  512 × 512 RGBA: four regions (UV quarters)
      (0, 0)   broadleaf cluster  – many small leaves, three greens, alpha
      (.5, 0)  small-leaf / box   – dense fine leaves (hedges, box balls)
      (0, .5)  grass blades       – thin tapered blades, varied heights
      (.5, .5) flowers + leaves   – white / pink / purple / yellow heads
  assets/models/foliage_kit.glb   objects (base-centred, metres):
      bush_round, bush_low, shrub_tall, hedge_block (2 m long), box_ball,
      flower_bed (1.6 m clump), grass_tuft (0.5 m clump)
Every card's normal points away from the plant's centre (soft, rounded
lighting instead of flat cards); COLOR.r = height factor (0 at the base,
1 at the top) for the wind sway in foliage.gdshader; COLOR.gb = the card's
own 0..1 coordinates (the shader frays card edges into a leafy outline).
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
REPO = ARGS[0] if ARGS else "."
PREVIEW = ARGS[1] if len(ARGS) > 1 else ""
R = random.Random(7)
S = 512


# ------------------------------------------------------------------ atlas
def atlas():
    img = np.zeros((S, S, 4), dtype=np.float32)
    H = S // 2

    def blit_leaf(cx, cy, length, width, ang, col, x0, y0):
        # An ellipse leaf with a darker midrib, drawn into quarter (x0, y0).
        r = int(max(length, width)) + 2
        ca, sa = math.cos(ang), math.sin(ang)
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                u = (dx * ca + dy * sa) / length
                v = (-dx * sa + dy * ca) / width
                d = u * u + v * v
                if d <= 1.0:
                    x = int(cx + dx)
                    y = int(cy + dy)
                    if x0 <= x < x0 + H and y0 <= y < y0 + H:
                        shade = 0.82 + 0.25 * (1.0 - d) + 0.1 * u
                        rib = 0.8 if abs(v) < 0.12 else 1.0
                        img[y, x, :3] = np.clip(np.array(col) * shade * rib, 0, 1)
                        img[y, x, 3] = 1.0

    greens = [(0.18, 0.33, 0.10), (0.24, 0.42, 0.13), (0.30, 0.47, 0.16), (0.14, 0.27, 0.09), (0.36, 0.50, 0.18)]
    # Broadleaf cluster: leaves on short twigs radiating in a round cluster.
    for k in range(420):
        a = R.random() * math.tau
        rr = math.sqrt(R.random()) * (H * 0.44)
        blit_leaf(H * 0.5 + math.cos(a) * rr, H * 0.5 + math.sin(a) * rr, R.uniform(7, 12), R.uniform(3.5, 5.5),
                  a + R.uniform(-0.6, 0.6), greens[R.randrange(5)], 0, 0)
    # Fine leaves (box, privet): many tiny leaves filling the square.
    for k in range(3200):
        blit_leaf(H + R.uniform(4, H - 4), R.uniform(4, H - 4), R.uniform(3, 5), R.uniform(1.6, 2.6),
                  R.random() * math.pi, greens[R.randrange(5)], H, 0)
    # Grass blades: tapered, slightly curved, from the bottom edge.
    for k in range(150):
        bx = R.uniform(6, H - 6)
        h = R.uniform(0.45, 0.98) * (H - 6)
        lean = R.uniform(-0.35, 0.35)
        w0 = R.uniform(2.0, 3.6)
        g = [(0.26, 0.42, 0.14), (0.33, 0.50, 0.17), (0.22, 0.36, 0.12), (0.42, 0.52, 0.22), (0.50, 0.52, 0.28)][R.randrange(5)]
        for t in np.linspace(0, 1, int(h)):
            y = int(S - 1 - t * h)
            x = bx + lean * t * t * h * 0.5
            w = w0 * (1.0 - t) + 0.4
            for dx in range(int(-w), int(w) + 1):
                xi = int(x + dx)
                if 0 <= xi < H and H <= y < S:
                    img[y, xi, :3] = np.array(g) * (0.7 + 0.45 * t)
                    img[y, xi, 3] = 1.0
    # Flowers over leaves.
    for k in range(500):
        blit_leaf(H + R.uniform(4, H - 4), H + R.uniform(4, H - 4), R.uniform(4, 7), R.uniform(2, 3.2),
                  R.random() * math.pi, greens[R.randrange(5)], H, H)
    petals = [(0.95, 0.95, 0.92), (0.92, 0.45, 0.65), (0.6, 0.38, 0.8), (0.98, 0.78, 0.22), (0.95, 0.35, 0.3)]
    for k in range(120):
        cx, cy = H + R.uniform(8, H - 8), H + R.uniform(8, H - 8)
        col = petals[R.randrange(5)]
        for p in range(5):
            a = p * math.tau / 5 + R.random()
            blit_leaf(cx + math.cos(a) * 3, cy + math.sin(a) * 3, 3.4, 2.2, a, col, H, H)
        blit_leaf(cx, cy, 1.6, 1.6, 0, (0.95, 0.8, 0.2), H, H)
    # Bleed colour into transparent texels (mip edges stay green, not black).
    rgb = img[:, :, :3].copy()
    a = img[:, :, 3]
    for _ in range(6):
        sh = [np.roll(rgb, s, axis=ax) for s in (-1, 1) for ax in (0, 1)]
        sa = [np.roll(a, s, axis=ax) for s in (-1, 1) for ax in (0, 1)]
        acc = sum(x * y[:, :, None] for x, y in zip(sh, sa))
        cnt = sum(sa)
        fill = (a == 0) & (cnt > 0)
        rgb[fill] = acc[fill] / cnt[fill][:, None]
        a = np.where(fill, 0.001, a)
    img[:, :, :3] = rgb
    im = bpy.data.images.new("foliage_atlas", S, S, alpha=True)
    im.pixels = np.flipud(img).ravel()
    path = os.path.join(REPO, "assets/world/foliage_atlas.png")
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    print("ATLAS", path)


# ------------------------------------------------------------------ cards
def card_mesh(name, cards):
    """cards: [(centre Vector, right Vector (half width), up Vector (half
    height), uv rect (u0, v0, u1, v1), plant centre for the normal)]."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.color.new("Col")
    top = max(c[0].z + c[2].z for c in cards)
    for c, rgt, up, r, pc in cards:
        corners = [c - rgt - up, c + rgt - up, c + rgt + up, c - rgt + up]
        uvs = [(r[0], r[1]), (r[2], r[1]), (r[2], r[3]), (r[0], r[3])]
        vs = [bm.verts.new(p) for p in corners]
        for vv in vs:
            n = vv.co - pc
            n.z = n.z * 0.6 + 0.5
            vv.normal = n.normalized()
        f = bm.faces.new(vs)
        for lp, t, cl in zip(f.loops, uvs, ((0, 0), (1, 0), (1, 1), (0, 1))):
            lp[uv].uv = t
            h = max(0.0, lp.vert.co.z) / max(top, 0.01)
            lp[col] = (h, cl[0], cl[1], 1.0)   # (G, B: card-local u, v for the ragged edge fade)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    # Keep the outward normals (custom split normals).
    me.normals_split_custom_set_from_vertices([v.normal for v in me.vertices])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.get("foliage") or bpy.data.materials.new("foliage")
    me.materials.append(mat)
    return ob


Q = {"broad": (0.0, 0.5, 0.5, 1.0), "fine": (0.5, 0.5, 1.0, 1.0), "grass": (0.0, 0.0, 0.5, 0.5), "flower": (0.5, 0.0, 1.0, 0.5)}


def sub(q, k):
    """A random sub-rect (60–100 %) of an atlas quarter: no two cards alike."""
    u0, v0, u1, v1 = Q[q]
    f = R.uniform(0.6, 1.0)
    w = (u1 - u0) * f
    h = (v1 - v0) * f
    a = u0 + R.uniform(0, (u1 - u0) - w)
    b = v0 + R.uniform(0, (v1 - v0) - h)
    return (a, b, a + w, b + h)


def blob(name, rx, ry, rz, n, q, card, lift=0.0):
    """Cards over an ellipsoid, each facing out and tilted at random."""
    cards = []
    pc = Vector((0, 0, rz * 0.45 + lift))
    for k in range(n):
        z = R.uniform(-0.25, 1.0)
        a = R.random() * math.tau
        r = math.sqrt(max(0.0, 1.0 - z * z))
        c = Vector((math.cos(a) * r * rx, math.sin(a) * r * ry, lift + rz * (0.5 + 0.5 * z)))
        out = (c - pc).normalized()
        rgt = out.cross(Vector((0, 0, 1)))
        if rgt.length < 0.1:
            rgt = Vector((1, 0, 0))
        rgt = rgt.normalized()
        up = rgt.cross(out).normalized()
        tw = R.uniform(-0.7, 0.7)
        rgt, up = rgt * math.cos(tw) + up * math.sin(tw), up * math.cos(tw) - rgt * math.sin(tw)
        s = card * R.uniform(0.8, 1.2)
        cards.append((c, rgt * s, up * s, sub(q, k), pc))
    return card_mesh(name, cards)


def grass(name, n, h, spread):
    cards = []
    pc = Vector((0, 0, -0.5))
    for k in range(n):
        a = R.random() * math.pi
        rgt = Vector((math.cos(a), math.sin(a), 0)) * R.uniform(0.18, 0.28)
        hh = h * R.uniform(0.7, 1.15)
        c = Vector((R.uniform(-spread, spread), R.uniform(-spread, spread), hh * 0.5))
        up = Vector((R.uniform(-0.08, 0.08), R.uniform(-0.08, 0.08), 1.0)).normalized() * hh * 0.5
        cards.append((c, rgt, up, sub("grass", k), pc))
    return card_mesh(name, cards)


def hedge(name, L, W, H, n):
    cards = []
    pc = Vector((0, 0, H * 0.4))
    for k in range(n):
        face = R.random()
        if face < 0.3:
            c = Vector((R.uniform(-L / 2, L / 2), R.uniform(-W / 2, W / 2), H + R.uniform(-0.05, 0.08)))
        else:
            sx = R.choice((-1, 1))
            if R.random() < 0.8:
                c = Vector((R.uniform(-L / 2, L / 2), sx * W / 2 + R.uniform(-0.05, 0.08), R.uniform(0.1, H)))
            else:
                c = Vector((sx * L / 2 + R.uniform(-0.05, 0.08), R.uniform(-W / 2, W / 2), R.uniform(0.1, H)))
        out = (c - pc)
        out.z *= 0.4
        out = out.normalized()
        rgt = out.cross(Vector((0, 0, 1)))
        if rgt.length < 0.1:
            rgt = Vector((1, 0, 0))
        rgt = rgt.normalized()
        up = rgt.cross(out).normalized()
        s = R.uniform(0.32, 0.45)
        cards.append((c, rgt * s, up * s, sub("fine", k), pc))
    return card_mesh(name, cards)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    atlas()
    objs = [
        blob("bush_round", 0.75, 0.7, 1.1, 46, "broad", 0.42),
        blob("bush_low", 0.9, 0.8, 0.6, 34, "broad", 0.36),
        blob("shrub_tall", 0.5, 0.5, 1.9, 44, "broad", 0.4, 0.15),
        blob("box_ball", 0.45, 0.45, 0.85, 34, "fine", 0.3),
        hedge("hedge_block", 2.0, 0.8, 1.05, 70),
        blob("flower_bed", 0.8, 0.8, 0.45, 30, "flower", 0.32),
        grass("grass_tuft", 9, 0.42, 0.16),
    ]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    path = os.path.join(REPO, "assets/models/foliage_kit.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_vertex_color="ACTIVE",
                              export_normals=True)
    print("FOLIAGE", path, sum(len(o.data.polygons) for o in objs), "cards")
    if PREVIEW:
        x = 0.0
        for o in objs:
            o.location = (x, 0, 0)
            x += 2.6
        mat = bpy.data.materials["foliage"]
        mat.use_nodes = True
        nt = mat.node_tree
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images["foliage_atlas"]
        bsdf = nt.nodes["Principled BSDF"]
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.blend_method = "CLIP" if hasattr(mat, "blend_method") else None
        sc = bpy.context.scene
        sc.render.engine = "BLENDER_EEVEE_NEXT"
        sc.render.resolution_x, sc.render.resolution_y = 1600, 600
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        sc.collection.objects.link(cam)
        cam.location = (7.8, -9.0, 3.2)
        cam.rotation_euler = (math.radians(76), 0, 0)
        sc.camera = cam
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sun.rotation_euler = (0.7, 0.2, 0.5)
        sc.collection.objects.link(sun)
        w = bpy.data.worlds.new("w")
        sc.world = w
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.7, 0.8, 1)
        sc.render.filepath = PREVIEW
        bpy.ops.render.render(write_still=True)


main()
