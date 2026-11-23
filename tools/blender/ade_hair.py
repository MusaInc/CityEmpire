"""Fit Ade's short curly crop using the head-scan hairline, crown and fade."""
import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

from build_b_surface import falloff, packed_image
from garment_kit import _dilate, raster_uv
from portrait_project import ADE_IMAGE, _blur, _frame, _source, _tps_apply, fit_projection
from wardrobe_quality import smooth

CROWN = ((152, 150), 148)          # atlas crown patch: centre, radius (px)
SIDE = (0, 305, 315, 720)          # atlas side patch: x0, x1, y0 (curls), y1 (skin)
# Lower edge of the dense curls in the frontal unwrap, at the temple steps.
LINE_X = [0, 140, 336, 342, 424, 565, 706, 788, 797, 965, 1127]
LINE_Y = [228, 204, 174, 154, 130, 120, 129, 154, 178, 208, 231]


def _bilinear(img, u, v):
    u = np.clip(u, 0, img.shape[1] - 1.001)
    v = np.clip(v, 0, img.shape[0] - 1.001)
    x0, y0 = u.astype(int), v.astype(int)
    fx, fy = u - x0, v - y0
    if img.ndim == 3:
        fx, fy = fx[:, None], fy[:, None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
            + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


class Sources:
    def __init__(self, atlas_path, unwrap_path, projection, eye, head):
        self.atlas = _source(atlas_path)
        self.photo = _source(unwrap_path)
        self.model, self.eye_z, _ = projection
        self.eye, self.head = eye, head
        lum = self.photo @ np.array([.2126, .7152, .0722])
        self.lum = _blur(lum, 3.0)

    def photo_uv(self, P):
        uv = _tps_apply(self.model, _frame(P, self.eye_z))
        H, W = self.photo.shape[:2]
        edge = np.minimum.reduce([uv[:, 0], W - 1 - uv[:, 0], uv[:, 1], H - 1 - uv[:, 1]])
        inside = falloff(4, 32, edge) * falloff(self.head.y - .012, self.head.y + .026, P[:, 1])
        return uv, inside

    def crown(self, P):
        (cx, cy), r = CROWN
        rel = (P[:, :2] - np.array([self.head.x, self.head.y])) / .095
        dist = np.linalg.norm(rel, axis=1, keepdims=True)
        # Compress smoothly into the curl disc (a hard clamp pinned the whole
        # front to one edge pixel: vertical streaks).
        rel = rel * (.86 * np.tanh(dist / .86) / np.maximum(dist, 1e-6))
        return _bilinear(self.atlas, cx + rel[:, 0] * r, cy - rel[:, 1] * r)

    def back(self, P):
        x0, x1, y0, y1 = SIDE
        depth = self.eye.z + .062 - P[:, 2]
        t = np.clip(depth / .060, 0, 1)                                 # 0 curls .. 1 skin
        ang = np.arctan2(P[:, 0], P[:, 1] - self.head.y)
        u = x0 + 8 + (np.mod(ang * .095 * 2300, x1 - x0 - 16))
        # Above the fade, tile the curl rows instead of stretching one row.
        above = np.mod(-np.minimum(depth, 0) * 2300, 170)
        tri = np.where(above < 85, above, 170 - above)
        v = np.where(depth < 0, y0 + tri, y0 + t * (y1 - y0))
        return _bilinear(self.atlas, u, v)

    def coverage(self, P, roots):
        """Return fade opacity and the dense section that carries curl volume."""
        uv, inside = self.photo_uv(P)
        line = np.interp(uv[:, 0], LINE_X, LINE_Y)
        depth = uv[:, 1] - line
        temple = falloff(215, 240, np.abs(uv[:, 0] - 565))
        lum = _bilinear(self.lum, uv[:, 0], uv[:, 1])
        mass = 1 - falloff(-12, 12, depth)
        fade = (1 - falloff(.095, .36, lum)) * (1 - falloff(14, 118, depth))
        front = np.maximum(mass, fade * temple)
        cov = roots * (1 - inside) + front * inside
        contour = falloff(self.eye.z + .043, self.eye.z + .078, P[:, 2]) * roots
        return np.maximum(cov, contour), np.maximum(mass * inside, contour)

    def colour(self, P, N):
        uv, inside = self.photo_uv(P)
        photo = _bilinear(self.photo, uv[:, 0], uv[:, 1])
        depth = uv[:, 1] - np.interp(uv[:, 0], LINE_X, LINE_Y)
        fade = falloff(0, 55, depth)[:, None]
        photo = photo * (1 - fade) + np.minimum(photo, (.165, .121, .100)) * fade
        top = falloff(.23, .68, N[:, 2])[:, None]
        other = self.crown(P) * top + self.back(P) * (1 - top)
        w = inside[:, None] * (1 - .92 * top)
        return photo * w + other * (1 - w)


def _coil_atlas(size=512, strips=8, seed=5):
    """RGBA strips, each a ragged clump of small C-shaped curls (denser at
    the root, v = 0), so the card edge reads as tight curly fuzz."""
    rng = np.random.default_rng(seed)
    img = np.zeros((size, size, 4), np.float32)
    w = 1 / strips
    yy, xx = np.mgrid[0:size, 0:size // strips] / size
    for s in range(strips):
        patch = img[:, s * (size // strips):(s + 1) * (size // strips)]
        for k in range(46):
            v = rng.uniform(.04, .92) ** 1.4 * .95 + .02
            spread = .30 + .18 * (1 - v)
            cx = w * (.5 + rng.uniform(-spread, spread))
            rad = rng.uniform(.010, .017) * (1.15 - .4 * v)
            start, sweep = rng.uniform(0, math.tau), rng.uniform(3.2, 4.6)
            thick = rng.uniform(.0030, .0046)
            ring = np.abs(np.hypot(xx - cx, yy - v) - rad) < thick
            ang = np.mod(np.arctan2(yy - v, xx - cx) - start, math.tau) < sweep
            col = (.004 < xx) & (xx < w - .004)
            m = ring & ang & col
            lit = .055 + .07 * rng.random()
            patch[m, :3] = np.array([lit, lit * .83, lit * .72])
            patch[m, 3] = 1
    return img


def _make_local_material(obj, name):
    material = obj.data.materials[0].copy()
    material.name = name
    obj.data.materials[0] = material
    return material


def build_ade_hair(face, shell, groom, eyes, atlas_path, unwrap_path, output, projection=None):
    if projection is None:
        projection = fit_projection(face, shell, eyes, ADE_IMAGE)
    eye = (eyes[0] + eyes[1]) * .5
    slot = next(i for i, m in enumerate(face.data.materials) if m.name.startswith('hero_skin_face_'))
    skin = BVHTree.FromPolygons([v.co for v in face.data.vertices],
                                [tuple(p.vertices) for p in face.data.polygons if p.material_index == slot])
    cap_pts = [v.co for v in shell.data.vertices]
    head = Vector((0, sum(p.y for p in cap_pts) / len(cap_pts), 0))
    src = Sources(atlas_path, unwrap_path, projection, eye, head)

    # 1. Resolution for a curly silhouette.
    bm = bmesh.new()
    bm.from_mesh(shell.data)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    bm.to_mesh(shell.data)
    bm.free()
    shell.data.update()

    data = shell.data
    density = data.uv_layers['ClothFreedom']
    roots = np.zeros(len(data.vertices), np.float32)
    for loop in data.loops:
        roots[loop.vertex_index] = max(roots[loop.vertex_index], density.data[loop.index].uv.y)
    P = np.array([v.co for v in data.vertices])
    cov, mass = src.coverage(P, roots)

    # Sample the undeformed scalp so the photo stays registered to the face.
    size = 512
    pos, nrm, used = raster_uv(shell, size, material_index=0)
    col = np.full((size, size, 3), .07, np.float32)
    col[used] = src.colour(pos[used], nrm[used])

    rng = random.Random(41)
    samples = [v.co.copy() for v, weight in zip(data.vertices, mass) if weight > .7]
    anchors = rng.sample(samples, min(460, len(samples)))
    blobs = KDTree(len(anchors))
    for k, p in enumerate(anchors):
        blobs.insert(p, k)
    blobs.balance()
    skull = eye + Vector((0, -.073, .029))
    for v, amount in zip(data.vertices, mass):
        p = v.co
        ray = (p - skull).normalized()
        hit, _, _, _ = skin.ray_cast(p + ray * .010, -ray, .033)
        if hit is None:
            continue
        crown = smooth(eye.z + .049, eye.z + .092, p.z)
        amount = smooth(.28, .98, amount)
        _, i, d = blobs.find(p)
        clump = max(0.0, 1 - d / .008) ** 1.45 * (.35 + .65 * math.sin(i * 2.39) ** 2)
        lift = .0011 + amount * (.0021 + .0072 * crown + .0022 * clump)
        v.co = hit + ray * lift
    data.update()
    for loop in data.loops:
        density.data[loop.index].uv.y = min(1.0, float(cov[loop.vertex_index]) * 1.10)

    mat = _make_local_material(shell, 'hero_hair_ade_crop')
    bsdf = mat.node_tree.nodes['Principled BSDF']
    colour_node = bsdf.inputs['Base Color'].links[0].from_node
    colour_node.image = packed_image(output / 'hair_ade_crop_albedo.png', _dilate(col, used, 8))
    lum = col @ np.array([.2126, .7152, .0722])
    height = np.zeros(used.shape, np.float32)
    height[used] = (lum - _blur(lum, 2.0))[used] * .005
    nmap = np.ones((size, size, 3), np.float32) * np.array([0, 0, 1], np.float32)
    for axis, ch in ((0, 1), (1, 0)):
        ok = used & np.roll(used, 1, axis) & np.roll(used, -1, axis)
        ln = np.linalg.norm(np.roll(pos, -1, axis) - np.roll(pos, 1, axis), axis=-1)
        rel = np.roll(height, -1, axis) - np.roll(height, 1, axis)
        nmap[..., ch][ok] -= np.clip(rel[ok] / np.maximum(ln[ok], .0003), -.6, .6)
    nmap /= np.maximum(np.linalg.norm(nmap, axis=-1, keepdims=True), 1e-6)
    normal_link = bsdf.inputs['Normal'].links
    if normal_link:
        nimg = normal_link[0].from_node.inputs['Color'].links[0].from_node
        nimg.image = packed_image(output / 'hair_ade_crop_normal.png', _dilate(nmap * .5 + .5, used, 6), normal=True)
    bsdf.inputs['Roughness'].default_value = .75

    # 4. Coil cards on the curl mass, replacing the straight flyaways.
    cap = BVHTree.FromPolygons([v.co for v in data.vertices], [tuple(p.vertices) for p in data.polygons])
    gbm = bmesh.new()
    gbm.from_mesh(groom.data)
    bmesh.ops.delete(gbm, geom=gbm.verts[:], context='VERTS')
    uv = gbm.loops.layers.uv['SurfaceUV']
    fr = gbm.loops.layers.uv.get('ClothFreedom')
    deform = gbm.verts.layers.deform.verify()
    headg = groom.vertex_groups['b_head'].index
    roots = [v.co.copy() for v, c in zip(data.vertices, mass) if c > .82]
    rng.shuffle(roots)
    for root in roots[:820]:
        loc, n, _, _ = cap.find_nearest(root)
        if loc is None:
            continue
        tangent = n.cross(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))).normalized()
        out = (n * .50 + tangent * .50).normalized()
        side = n.cross(out).normalized() if n.cross(out).length > 1e-4 else tangent
        length, width = rng.uniform(.0037, .0065), rng.uniform(.0026, .0044)
        base = loc - n * .0008
        quad = [base - side * width, base + side * width,
                base + side * width * .8 + out * length, base - side * width * .8 + out * length]
        vs = [gbm.verts.new(q) for q in quad]
        for vv in vs:
            vv[deform][headg] = 1
        f = gbm.faces.new(vs)
        strip = rng.randrange(8)
        for loop, (a, b) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uv].uv = ((strip + .06 + .88 * a) / 8, b)
            if fr is not None:
                loop[fr].uv = (0, 1)
    gbm.to_mesh(groom.data)
    gbm.free()
    groom.data.update()
    gmat = _make_local_material(groom, 'hero_hair_cards_ade')
    tex = next(n for n in gmat.node_tree.nodes if n.type == 'TEX_IMAGE')
    atlas = _coil_atlas()
    img = bpy.data.images.new('hair_ade_coils', 512, 512, alpha=True)
    img.pixels.foreach_set(atlas[::-1].ravel())
    img.filepath_raw = str(output / 'hair_ade_coils.png')
    img.file_format = 'PNG'
    img.save()
    img.pack()
    tex.image = img
