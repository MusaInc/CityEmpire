"""Project a photographic face texture onto a hero's real face UVs.

The source (art/hero/sources/jules-portrait-reference.jpeg) is a head-scan
style unwrap: frontal face, ears to the sides, neck below. Every face texel's
3D position is mapped into it through a thin-plate spline fitted on matched
landmarks (eyes, brows, nose base, mouth, chin, ears, hairline), in a
cylindrical (angle around the head, height) frame. Hair, background and the
eye openings in the photo are masked and in-filled with surrounding skin; the
photo's own pore and freckle relief becomes a detail normal. The result is
stored divided by the hero's skin tint because the game multiplies it back.
"""
import math

import bpy
import numpy as np
from mathutils import Vector

from build_b_surface import packed_image, pixels
from garment_kit import _dilate, raster_uv
from hero_finish import material_vertices

CY = .03          # head axis (y) for the cylindrical frame
RADIUS = .09      # metres per radian, keeps both frame axes metric

# Pixel landmarks in the 1254 px Jules source (measured on a 50 px grid).
JULES_IMAGE = {
    'eye_l': (470, 422), 'eye_r': (783, 422),
    'brow_l': (455, 325), 'brow_r': (800, 325),
    'subnasale': (627, 645), 'mouth': (627, 760),
    'corner_l': (500, 760), 'corner_r': (757, 760),
    'chin': (627, 965), 'hairline': (627, 190),
    'tragus_l': (150, 550), 'tragus_r': (1105, 550),
    'ear_top_l': (85, 405), 'ear_top_r': (1170, 405),
    'lobe_l': (125, 645), 'lobe_r': (1130, 645),
}


def srgb_to_linear(c):
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= .0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - .055)


def _tps_fit(src, dst, reg=1e-7):
    n = len(src)
    d = np.linalg.norm(src[:, None] - src[None], axis=-1)
    K = np.where(d > 0, d * d * np.log(np.maximum(d, 1e-12)), 0) + reg * np.eye(n)
    P = np.hstack([np.ones((n, 1)), src])
    A = np.zeros((n + 3, n + 3))
    A[:n, :n], A[:n, n:], A[n:, :n] = K, P, P.T
    b = np.zeros((n + 3, 2))
    b[:n] = dst
    return src, np.linalg.solve(A, b)


def _tps_apply(model, pts, chunk=200000):
    src, coef = model
    n = len(src)
    out = np.empty((len(pts), 2))
    for s in range(0, len(pts), chunk):
        p = pts[s:s + chunk]
        d = np.linalg.norm(p[:, None] - src[None], axis=-1)
        K = np.where(d > 0, d * d * np.log(np.maximum(d, 1e-12)), 0)
        out[s:s + chunk] = K @ coef[:n] + coef[n] + p @ coef[n + 1:]
    return out


def _frame(p, eye_z):
    p = np.atleast_2d(p)
    return np.stack([RADIUS * np.arctan2(p[:, 0], p[:, 1] - CY), p[:, 2] - eye_z], axis=1)


def _blur(img, sigma):
    r = int(3 * sigma)
    k = np.exp(-(np.arange(-r, r + 1) / sigma) ** 2 / 2)
    k /= k.sum()
    out = img
    for axis in (0, 1):
        pad = [(0, 0)] * img.ndim
        pad[axis] = (r, r)
        q = np.pad(out, pad, mode='edge')
        out = sum(k[i] * np.take(q, range(i, i + img.shape[axis]), axis=axis) for i in range(2 * r + 1))
    return out


def _fill(img, keep):
    """Push-pull in-fill of masked pixels from the surrounding kept ones."""
    levels = []
    c, w = img * keep[..., None], keep.astype(np.float32)
    while min(w.shape) > 4:
        levels.append((c, w))
        h, wd = (w.shape[0] // 2) * 2, (w.shape[1] // 2) * 2
        c = c[:h, :wd].reshape(h // 2, 2, wd // 2, 2, 3).sum((1, 3))
        w = w[:h, :wd].reshape(h // 2, 2, wd // 2, 2).sum((1, 3))
    filled = c / np.maximum(w, 1e-6)[..., None]
    for c, w in reversed(levels):
        up = np.repeat(np.repeat(filled, 2, 0), 2, 1)
        up = np.pad(up, ((0, c.shape[0] - up.shape[0]), (0, c.shape[1] - up.shape[1]), (0, 0)), mode='edge')
        own = c / np.maximum(w, 1e-6)[..., None]
        a = np.clip(w, 0, 1)[..., None]
        filled = own * a + up * (1 - a)
    return filled


def _source(path):
    image = bpy.data.images.load(str(path), check_existing=True)
    w, h = image.size
    arr = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]
    return arr  # top-left origin, sRGB-encoded values


def _mesh_landmarks(face, shell, eyes):
    basis = face.data.shape_keys.key_blocks[0].data if face.data.shape_keys else face.data.vertices
    skin = [basis[i].co.copy() for i in material_vertices(face, ('hero_skin_face_',))]
    brow = [basis[i].co.copy() for i in material_vertices(face, ('hero_brow',))]
    eye_z = (eyes[0].z + eyes[1].z) / 2
    eye_y = (eyes[0].y + eyes[1].y) / 2
    mid = [p for p in skin if abs(p.x) < .003 and p.y > eye_y - .02]
    tip = max(mid, key=lambda p: p.y)
    sub = min((p for p in mid if tip.z - .03 < p.z < tip.z - .003), key=lambda p: p.y)
    chin = min(mid, key=lambda p: p.z)
    # Mouth: the deepest midline notch between the lips (below the nose).
    band = [p for p in mid if eye_z - .085 < p.z < sub.z - .015]
    mouth = min(band, key=lambda p: p.y + 3 * abs(p.z - (eye_z - .065)))
    lm = {'eye_l': eyes[0] if eyes[0].x < 0 else eyes[1], 'eye_r': eyes[1] if eyes[1].x > 0 else eyes[0],
          'subnasale': sub, 'mouth': mouth, 'chin': chin}
    for side, sign in (('l', -1), ('r', 1)):
        e = lm['eye_' + side]
        lm['brow_' + side] = Vector((e.x * 1.08, e.y + .012, e.z + .0175))
        lm['corner_' + side] = Vector((sign * .020, mouth.y - .008, mouth.z))
        band = [p for p in skin if sign * p.x > 0 and eye_z - .065 < p.z < eye_z + .03]
        reach = max(abs(p.x) for p in band)
        ear = [p for p in band if abs(p.x) > reach - .011]
        top = max(ear, key=lambda p: p.z)
        lobe = min(ear, key=lambda p: p.z)
        midz = [p for p in ear if abs(p.z - (top.z + lobe.z) / 2) < .006]
        lm['ear_top_' + side], lm['lobe_' + side] = top, lobe
        lm['tragus_' + side] = max(midz, key=lambda p: p.y) if midz else (top + lobe) / 2
    # Hairline: the scalp cap's front rim over the forehead.
    if shell is not None:
        rim = [v.co for v in shell.data.vertices if abs(v.co.x) < .012 and v.co.y > eye_y - .035
               and v.co.z > eye_z + .02]
        hz = min((p.z for p in rim), default=eye_z + .065) + .004
    else:
        hz = eye_z + .065
    lm['hairline'] = Vector((0, eye_y + .01, hz))
    return lm, eye_z


def drop_geometry_brows(face):
    import bmesh
    slot = next((i for i, m in enumerate(face.data.materials) if m.name.startswith('hero_brow')), None)
    if slot is None:
        return
    bm = bmesh.new()
    bm.from_mesh(face.data)
    faces = [f for f in bm.faces if f.material_index == slot]
    verts = {v for f in faces for v in f.verts}
    bmesh.ops.delete(bm, geom=faces, context='FACES_ONLY')
    bmesh.ops.delete(bm, geom=[v for v in verts if not v.link_faces], context='VERTS')
    bm.to_mesh(face.data)
    bm.free()
    face.data.update()


def trim_scalp_rim(shell, face, eyes, density=.93):
    """Remove the cap's opaque feather band over the forehead: the photo's
    own fine hairline shows there instead of a flat tinted strip."""
    import bmesh
    eye = (eyes[0] + eyes[1]) * .5
    layer = shell.data.uv_layers.get('ClothFreedom')
    if layer is None:
        return
    bm = bmesh.new()
    bm.from_mesh(shell.data)
    uv = bm.loops.layers.uv['ClothFreedom']
    doomed = [f for f in bm.faces if f.material_index == 0
              and max(l[uv].uv.y for l in f.loops) < density
              and f.calc_center_median().y > eye.y - .11 and f.calc_center_median().z > eye.z - .03]
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(shell.data)
    bm.free()
    shell.data.update()
    # Relax the cut (it followed the triangles) into a smooth hairline.
    from mathutils.bvhtree import BVHTree
    from hero_polish import smooth_side_hairline
    slot = next(i for i, m in enumerate(face.data.materials) if m.name.startswith('hero_skin_face_'))
    skin = BVHTree.FromPolygons([v.co for v in face.data.vertices],
                                [tuple(p.vertices) for p in face.data.polygons if p.material_index == slot])
    smooth_side_hairline(shell, skin, eye, iterations=70, min_abs_x=0)


def project_portrait(face, shell, identity, eyes, source_path, tint, output, image_landmarks=JULES_IMAGE):
    slot = next(i for i, m in enumerate(face.data.materials) if m.name.startswith('hero_skin_face_'))
    shader = face.data.materials[slot].node_tree.nodes['Principled BSDF']
    colour_node = shader.inputs['Base Color'].links[0].from_node
    normal_node = shader.inputs['Normal'].links[0].from_node
    normal_image = normal_node.inputs['Color'].links[0].from_node
    size = colour_node.image.size[0]

    if shell is not None:
        trim_scalp_rim(shell, face, eyes)
    lm, eye_z = _mesh_landmarks(face, shell, eyes)
    keys = [k for k in image_landmarks if k in lm]
    src = _frame(np.array([tuple(lm[k]) for k in keys]), eye_z)
    dst = np.array([image_landmarks[k] for k in keys], dtype=np.float64)
    model = _tps_fit(src, dst)
    for k, s, d, f in zip(keys, src, dst, _tps_apply(model, src)):
        assert np.linalg.norm(f - d) < 2, (k, f, d)

    photo = _source(source_path)
    H, W = photo.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    lum = photo @ np.array([.2126, .7152, .0722])
    background = lum < .03
    brows = sum(((xx - bx) / 150.) ** 2 + ((yy - by) / 45.) ** 2 < 1
                for k, (bx, by) in image_landmarks.items() if k.startswith('brow'))
    hair = (lum < .17) & ((yy < 300) | (((xx < 260) | (xx > W - 260)) & (yy < 470))) & ~brows.astype(bool)
    openings = sum(((xx - ex) / 104.) ** 2 + ((yy - ey - 2) / 37.) ** 2 < 1
                   for k, (ex, ey) in image_landmarks.items() if k.startswith('eye')).astype(bool)
    near_eyes = sum(((xx - ex) / 135.) ** 2 + ((yy - ey - 6) / 62.) ** 2 < 1
                    for k, (ex, ey) in image_landmarks.items() if k.startswith('eye')).astype(bool)
    skinlike = ~(background | hair)
    fringe = hair & (_blur(skinlike.astype(np.float32), 9.0) > .06) & (yy < 360)
    keep = ~(background | (hair & ~fringe) | openings | (near_eyes & (lum < .30)))
    keep = _blur(keep.astype(np.float32), 1.5) > .98
    filled = _fill(photo, keep)
    # The photo's lid crease shadow and liner, spread over a deeper mesh
    # socket, read as a bruise: lift the broad shading, keep the fine detail.
    flum = filled @ np.array([.2126, .7152, .0722])
    skin_lum = np.median(flum[keep & ~near_eyes & (yy > 380) & (yy < 900)])
    socket = _blur(sum(((xx - ex) / 150.) ** 2 + ((yy - ey - 4) / 72.) ** 2 < 1
                       for k, (ex, ey) in image_landmarks.items() if k.startswith('eye')).astype(np.float32), 14)
    lift = np.clip(skin_lum * .97 / np.maximum(_blur(flum, 10), 1e-3), 1, 1.45)
    filled = filled * (1 + (lift - 1) * socket)[..., None]
    skin_mean = filled[keep & (yy > 450) & (yy < 900) & (np.abs(xx - W / 2) < 330)].mean(0)
    # Lids and sockets keep their shading but take the cheek's hue (the photo's
    # pink lids turned into an orange ring on the deeper mesh socket).
    flum = filled @ np.array([.2126, .7152, .0722])
    neutral = skin_mean / (skin_mean @ np.array([.2126, .7152, .0722])) * flum[..., None]
    filled = filled + (neutral - filled) * (.6 * socket)[..., None]
    detail = (lum - _blur(lum, 2.2)).astype(np.float32)

    pos, normals, used = raster_uv(face, size, material_index=slot)
    P = pos[used]
    uv = _tps_apply(model, _frame(P, eye_z))
    u = np.clip(uv[:, 0], 0, W - 1.001)
    v = np.clip(uv[:, 1], 0, H - 1.001)
    inside = (uv[:, 0] > 2) & (uv[:, 0] < W - 3) & (uv[:, 1] > 2) & (uv[:, 1] < H - 3)

    def sample(img):
        x0, y0 = u.astype(int), v.astype(int)
        fx, fy = u - x0, v - y0
        if img.ndim == 3:
            fx, fy = fx[:, None], fy[:, None]
        return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
                + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)

    colour = sample(filled)
    angle = np.abs(np.arctan2(P[:, 0], P[:, 1] - CY))
    outside = np.clip(np.maximum(np.maximum(-uv[:, 0], uv[:, 0] - W), np.maximum(-uv[:, 1], uv[:, 1] - H)) / 40, 0, 1)
    outside = np.maximum(outside, np.clip((angle - 1.65) / .25, 0, 1))
    colour = colour * (1 - outside[:, None]) + skin_mean * outside[:, None]
    covered = sample(keep.astype(np.float32)) * inside
    weight = np.ones(len(P))
    zmin = P[:, 2].min()
    weight *= np.clip((P[:, 2] - zmin - .004) / .03, 0, 1)

    tint_lin = srgb_to_linear(np.array(tint[:3], dtype=np.float64))
    albedo_lin = srgb_to_linear(colour) / tint_lin
    over = albedo_lin.max(axis=1, keepdims=True)
    albedo_lin = albedo_lin / np.maximum(over, 1.0)          # keep hue where it clips
    albedo = linear_to_srgb(albedo_lin)

    old = pixels(colour_node.image)[..., :3].copy()
    base = old[used]
    # Match the old map's tone at the seam so the neck joins the body.
    seam = weight < .5
    if seam.any():
        gain = (albedo[seam].mean(0) + 1e-4) / (base[seam].mean(0) + 1e-4)
        base = np.clip(base * gain, 0, 1)
    old[used] = base * (1 - weight[:, None]) + albedo * weight[:, None]
    colour_node.image = packed_image(output / f'face_{identity}_albedo.png', _dilate(old, used, 10))

    # Pore, freckle and lip-line relief from the photo as a detail normal.
    height = np.zeros(used.shape, np.float32)
    height[used] = -sample(detail) * .0016 * weight * (.4 + .6 * covered)
    # Start flat: the old map was baked for the previous face shape and
    # printed its planes (bright cheek patches) onto the new one.
    normal_map = np.ones((size, size, 3), np.float32) * np.array([0, 0, 1], np.float32)
    for axis, channel in ((0, 1), (1, 0)):
        valid = used & np.roll(used, 1, axis) & np.roll(used, -1, axis)
        lengths = np.linalg.norm(np.roll(pos, -1, axis) - np.roll(pos, 1, axis), axis=-1)
        relief = np.roll(height, -1, axis) - np.roll(height, 1, axis)
        normal_map[..., channel][valid] = (normal_map[..., channel][valid]
                                          - np.clip(relief[valid] / np.maximum(lengths[valid], .00024), -.35, .35))
    normal_map /= np.maximum(np.linalg.norm(normal_map, axis=-1, keepdims=True), 1e-6)
    normal_image.image = packed_image(output / f'face_{identity}_normal.png',
                                      _dilate(normal_map * .5 + .5, used, 7), normal=True)
    normal_node.inputs['Strength'].default_value = 1.0
    return {k: tuple(round(c, 4) for c in lm[k]) for k in keys}
