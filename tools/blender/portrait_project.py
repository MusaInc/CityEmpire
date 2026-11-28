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
    sub = min((p for p in mid if tip.z - .03 < p.z < tip.z - .003), key=lambda p: p.y).copy()
    sub.x = 0
    # Chin = where the profile turns under, below its most forward point
    # (Ade's face mesh runs on down the throat, so not simply the lowest).
    front = {}
    for p in mid:
        if eye_z - .13 < p.z < eye_z - .075:
            k = round((p.z - eye_z) / .0015)
            if k not in front or p.y > front[k].y:
                front[k] = p
    jaw = [front[k] for k in sorted(front, reverse=True)]
    pog = max(jaw, key=lambda p: p.y)
    # Place chin landmark at the true bottom of the chin (not mid-chin) so Ade's goatee maps naturally without squashing.
    chin_drop = .018 if face.name == 'Face_ade' else .012
    chin = next((p for p in jaw if p.z < pog.z - .008 and p.y < pog.y - chin_drop), jaw[-1])
    # Mouth: the deepest midline notch between the lips (below the nose).
    band = [p for p in mid if eye_z - .085 < p.z < sub.z - .015]
    centre = [p for p in band if abs(p.x) < .0012] or band
    mouth = min(centre, key=lambda p: p.y + 3 * abs(p.z - (eye_z - MOUTH_DZ.get(face.name, .0595)))).copy()
    mouth.x = 0
    lm = {'eye_l': eyes[0] if eyes[0].x < 0 else eyes[1], 'eye_r': eyes[1] if eyes[1].x > 0 else eyes[0],
          'subnasale': sub, 'mouth': mouth, 'chin': chin}
    for side, sign in (('l', -1), ('r', 1)):
        e = lm['eye_' + side]
        lm['brow_' + side] = Vector((e.x * 1.08, e.y + .012, e.z + .0175))
        lm['corner_' + side] = Vector((sign * CORNER.get(face.name, .020), mouth.y - .008, mouth.z))
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


# Ade: the face panel cropped out of the supplied atlas (ade-face-atlas.jpeg,
# x 305..1432) -> ade-face-unwrap.jpeg. 250 px between the eyes.
ADE_IMAGE = {
    'eye_l': (440, 352), 'eye_r': (690, 352),
    'brow_l': (435, 280), 'brow_r': (695, 280),
    'subnasale': (570, 515), 'mouth': (567, 615),
    'corner_l': (450, 615), 'corner_r': (685, 615),
    'chin': (567, 800), 'hairline': (567, 135),
    'tragus_l': (160, 450), 'tragus_r': (975, 450),
    'ear_top_l': (95, 315), 'ear_top_r': (1035, 315),
    'lobe_l': (135, 545), 'lobe_r': (1000, 545),
}
HAIR_LUM = {'jules': .17, 'ade': .085}
MOUTH_DZ = {'Face_jules': .0595, 'Face_ade': .064}
CORNER = {'Face_jules': .020, 'Face_ade': .026}


def fit_projection(face, shell, eyes, image_landmarks):
    lm, eye_z = _mesh_landmarks(face, shell, eyes)
    keys = list(image_landmarks)
    src = _frame(np.array([tuple(lm[k]) for k in keys]), eye_z)
    dst = np.array([image_landmarks[k] for k in keys], dtype=np.float64)
    model = _tps_fit(src, dst)
    assert np.max(np.linalg.norm(_tps_apply(model, src) - dst, axis=1)) < 2
    return model, eye_z, {k: tuple(round(c, 4) for c in lm[k]) for k in keys}


def project_portrait(face, shell, identity, eyes, source_path, tint, output, image_landmarks=JULES_IMAGE, projection=None):
    slot = next(i for i, m in enumerate(face.data.materials) if m.name.startswith('hero_skin_face_'))
    shader = face.data.materials[slot].node_tree.nodes['Principled BSDF']
    colour_node = shader.inputs['Base Color'].links[0].from_node
    normal_node = shader.inputs['Normal'].links[0].from_node
    normal_image = normal_node.inputs['Color'].links[0].from_node
    size = colour_node.image.size[0]

    if shell is not None and identity == 'jules':
        # Keep smooth continuous scalp boundary (NEVER delete jagged sawtooth rim triangles!).
        from mathutils.bvhtree import BVHTree
        from hero_polish import smooth_side_hairline
        skin_bvh = BVHTree.FromPolygons([v.co for v in face.data.vertices],
                                        [tuple(p.vertices) for p in face.data.polygons if p.material_index == slot])
        smooth_side_hairline(shell, skin_bvh, (eyes[0] + eyes[1]) * .5, iterations=48, min_abs_x=0)
    model, eye_z, landmarks = projection or fit_projection(face, shell, eyes, image_landmarks)

    photo = _source(source_path)
    el, er = image_landmarks['eye_l'], image_landmarks['eye_r']
    sc = (er[0] - el[0]) / 313.0          # 1.0 for the Jules source
    ey0 = (el[1] + er[1]) / 2
    cx = (el[0] + er[0]) / 2
    H, W = photo.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    lum = photo @ np.array([.2126, .7152, .0722])
    background = lum < .03
    brows = sum(((xx - bx) / (150. * sc)) ** 2 + ((yy - by) / (45. * sc)) ** 2 < 1
                for k, (bx, by) in image_landmarks.items() if k.startswith('brow'))
    # For Jules, mask out the dark hair sweep & shadow sitting above the ears/temples so ZERO dark blotch bakes onto temple skin.
    temple_hair = (((xx < 360 * sc) | (xx > W - 360 * sc)) & (yy < ey0 + 52 * sc)) if identity == 'jules' \
        else (((xx < 260 * sc) | (xx > W - 260 * sc)) & (yy < ey0 + 48 * sc))
    upper_temple = (((xx < 415 * sc) | (xx > W - 415 * sc)) & (yy < ey0 - 25 * sc)) if identity == 'jules' else np.zeros_like(temple_hair)
    hair_thresh = .24 if identity == 'jules' else HAIR_LUM.get(identity, .085)
    hair = (((lum < hair_thresh) & ((yy < ey0 - 120 * sc) | temple_hair))
            | ((lum < .33) & upper_temple)) & ~brows.astype(bool)
    openings = sum(((xx - ex) / (104. * sc)) ** 2 + ((yy - ey - 2 * sc) / (37. * sc)) ** 2 < 1
                   for k, (ex, ey) in image_landmarks.items() if k.startswith('eye')).astype(bool)
    near_eyes = sum(((xx - ex) / (135. * sc)) ** 2 + ((yy - ey - 6 * sc) / (62. * sc)) ** 2 < 1
                    for k, (ex, ey) in image_landmarks.items() if k.startswith('eye')).astype(bool)
    skinlike = ~(background | hair)
    fringe = hair & (_blur(skinlike.astype(np.float32), 7.5 * sc) > .10) & (yy < ey0 - 74 * sc) & (np.abs(xx - cx) < 280 * sc)
    keep = ~(background | (hair & ~fringe) | openings | (near_eyes & (lum < .30)))
    keep = _blur(keep.astype(np.float32), 1.5) > .98
    filled = _fill(photo, keep)
    # The in-fill comes from coarse pyramid levels: soften it (not the photo).
    soft = _blur(filled, 5.0)
    hole = _blur((~keep).astype(np.float32), 3.0)[..., None]
    filled = filled * (1 - hole) + soft * hole
    # The photo's lid crease shadow and liner, spread over a deeper mesh
    # socket, read as a bruise: lift the broad shading, keep the fine detail.
    flum = filled @ np.array([.2126, .7152, .0722])
    cheeks = (yy > ey0 + 28 * sc) & (yy < ey0 + 200 * sc) & (np.abs(xx - cx) > 110 * sc) & (np.abs(xx - cx) < 300 * sc)
    skin_lum = np.median(flum[keep & ~near_eyes & cheeks])
    socket = _blur(sum(((xx - ex) / (150. * sc)) ** 2 + ((yy - ey - 4 * sc) / (72. * sc)) ** 2 < 1
                       for k, (ex, ey) in image_landmarks.items() if k.startswith('eye')).astype(np.float32), 14 * sc)
    lift = np.clip(skin_lum * .97 / np.maximum(_blur(flum, 10), 1e-3), 1, 1.45)
    filled = filled * (1 + (lift - 1) * socket)[..., None]
    skin_mean = filled[keep & cheeks].mean(0)
    # Lids and sockets keep their shading but take the cheek's hue (the photo's
    # pink lids turned into an orange ring on the deeper mesh socket).
    flum = filled @ np.array([.2126, .7152, .0722])
    neutral = skin_mean / (skin_mean @ np.array([.2126, .7152, .0722])) * flum[..., None]
    filled = filled + (neutral - filled) * (.6 * socket)[..., None]

    # Clean, feature-preserving photographic skin delighting without excessive smoothing:
    # preserve eyebrows, lips, nostrils, natural pores, freckles, and Ade's crisp stubble/beard!
    mx, my = image_landmarks['mouth']
    sx, sy = image_landmarks['subnasale']
    lips_m = (((xx - mx) / (145. * sc)) ** 2 + ((yy - my) / (68. * sc)) ** 2) < 1
    if identity == 'jules':
        # Remove the bright pale specular/teeth strip inside Jules's lip seam from the source photo
        # so closed resting lips show a natural soft rosy-brown lip crease instead of a white line!
        lip_slit = (((xx - mx) / (122. * sc)) ** 2 + ((yy - my + 2. * sc) / (20. * sc)) ** 2) < 1
        lip_body = lips_m & ~lip_slit & (flum < 0.44)
        if np.any(lip_body):
            lip_tone = np.median(filled[lip_body], axis=0) * np.array([0.82, 0.78, 0.78], dtype=np.float32)
            bright_slit = _blur((lip_slit & (flum > 0.40)).astype(np.float32), 2.5 * sc)
            bright_slit = np.clip(bright_slit * 1.45, 0.0, 1.0)[..., None]
            filled = filled * (1.0 - bright_slit) + lip_tone * bright_slit
            flum = filled @ np.array([.2126, .7152, .0722])
    nostril_m = (((xx - sx) / (90. * sc)) ** 2 + ((yy - sy + 14 * sc) / (46. * sc)) ** 2) < 1
    beard_m = np.zeros_like(lips_m)
    beard_hair_relief = np.zeros((H, W), dtype=np.float32)
    if identity == 'ade':
        # Preserve Ade's entire natural mustache, soul patch, goatee and cheek/jaw stubble 100% razor sharp!
        beard_m = (yy > my - 72 * sc) & (yy < my + 260 * sc) & (np.abs(xx - mx) < 340 * sc)
        # Enhance crisp individual facial-hair & stubble follicle definition via targeted micro-unsharp contrast
        # (replaces blurry smudges with crisp individual hair definition!).
        fine_hair = (flum - _blur(flum, 1.35 * sc))
        med_hair = (flum - _blur(flum, 3.0 * sc))
        moustache_zone = np.exp(-((xx - mx) / (125 * sc)) ** 2 - ((yy - (my - 36 * sc)) / (36 * sc)) ** 2)
        goatee_zone = np.exp(-((xx - mx) / (148 * sc)) ** 2 - ((yy - (my + 128 * sc)) / (95 * sc)) ** 2)
        stubble_zone = np.clip((yy - (ey0 + 115 * sc)) / (85 * sc), 0.0, 1.0) * np.exp(-((np.abs(xx - mx) - 195 * sc) / (135 * sc)) ** 2)
        hair_zone = np.clip(moustache_zone + goatee_zone + 0.70 * stubble_zone, 0.0, 1.0)
        # Crisp follicle sharpening in albedo (strictly on facial-hair zone, never noisy on cheeks).
        sharp_delta = np.clip((fine_hair * 0.92 + med_hair * 0.34) * hair_zone, -0.18, 0.18)[..., None]
        filled = np.clip(filled + sharp_delta, 0.0, 1.0)
        # Directional hair-strand relief for normal map: individual dark hairs stand subtly proud of skin!
        dark_hair = np.clip((skin_lum * 0.90 - flum) / max(skin_lum * 0.62, 0.05), 0.0, 1.0) * hair_zone
        strand_pattern = (0.55 * np.sin(xx * (1.95 / sc) + np.sin(yy * (0.28 / sc)) * 1.4)
                          + 0.45 * np.sin(xx * (3.60 / sc) - yy * (0.48 / sc)))
        beard_hair_relief = (dark_hair * (0.78 + 0.62 * strand_pattern) - fine_hair * 2.8 * hair_zone).astype(np.float32)
    # Preserve delicate upper-eyelid crease depth so eyes retain natural 3D orbital definition.
    lid_crease = sum(((xx - ex) / (112. * sc)) ** 2 + ((yy - ey + 28 * sc) / (20. * sc)) ** 2 < 1
                     for k, (ex, ey) in image_landmarks.items() if k.startswith('eye')).astype(bool)
    ear_m = (xx < 235 * sc) | (xx > W - 235 * sc)
    preserve = _blur((brows.astype(bool) | lips_m | nostril_m | beard_m | lid_crease | ear_m | openings | ~keep).astype(np.float32), 11.0 * sc)
    clean_skin = np.clip(1.0 - preserve, 0.0, 1.0)
    # 1. Gentle photo-lighting delighting on broad uneven forehead/cheek shadows without smudging pores.
    broad_lum = _blur(flum, 28.0 * sc)
    delight = np.clip((skin_lum * 0.99) / np.maximum(broad_lum, 1e-3), 0.91, 1.13)
    delit = filled * (1.0 + (delight - 1.0) * 0.34 * clean_skin)[..., None]
    # 2. Light frequency-separated cleanup keeping 82% of natural photographic pore & freckle micro-detail.
    smooth_col = _blur(delit, 9.0 * sc)
    micro_tex = delit - _blur(delit, 2.0 * sc)
    cleaned = smooth_col + micro_tex * 0.85
    filled = np.clip(delit * (1.0 - 0.22 * clean_skin[..., None]) + cleaned * (0.22 * clean_skin[..., None]), 0.0, 1.0)
    detail = (lum - _blur(lum, 2.0)).astype(np.float32)

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
    # Smoothly transition behind the ears into matching side-neck skin so ZERO ear-edge arc ever appears.
    ear_cut = 1.38 if identity == 'ade' else 1.54
    ear_blend = np.clip((angle - ear_cut) / (.42 if identity == 'ade' else .30), 0, 1)
    ear_blend = ear_blend * ear_blend * (3 - 2 * ear_blend)
    outside = np.maximum(outside, ear_blend)
    side_skin = skin_mean
    if identity == 'ade':
        edge_mask = (angle > 1.24) & (angle < 1.44) & (P[:, 2] > eye_z - 0.08) & (P[:, 2] < eye_z + 0.04) & inside
        if np.any(edge_mask):
            side_skin = np.median(colour[edge_mask], axis=0) * 0.72 + skin_mean * 0.28
    colour = colour * (1 - outside[:, None]) + side_skin * outside[:, None]
    covered = sample(keep.astype(np.float32)) * inside
    weight = np.ones(len(P))
    zmin = P[:, 2].min()
    if identity == 'ade':
        front = np.clip((P[:, 1] - .085) / .052, 0, 1)
        neck = np.clip((P[:, 2] - (1.575 - .052 * front)) / (.075 - .012 * front), 0, 1)
        weight *= neck * neck * (3 - 2 * neck)
    else:
        # Smooth 4.8cm feather down the lower neck/clavicle into EXACT hero_skin_body tone (zero chest seam!).
        neck = np.clip((P[:, 2] - zmin - .008) / .048, 0, 1)
        weight *= neck * neck * (3 - 2 * neck)

    tint_lin = srgb_to_linear(np.array(tint[:3], dtype=np.float64))
    albedo_lin = srgb_to_linear(colour) / tint_lin
    over = albedo_lin.max(axis=1, keepdims=True)
    albedo_lin = albedo_lin / np.maximum(over, 1.0)          # keep hue where it clips
    albedo = linear_to_srgb(albedo_lin)

    old = pixels(colour_node.image)[..., :3].copy()
    base = old[used]
    # Match the lower neck boundary EXACTLY to hero_skin_body's measured median RGB [0.953, 0.949, 0.941]
    # so there is ZERO tone jump where Face_jules meets Fashion_Torso_Skin / Fashion_Crop_Skin.
    if identity == 'jules':
        base = np.broadcast_to(np.array([0.953, 0.949, 0.941], dtype=np.float32), base.shape).copy()
    old[used] = base * (1 - weight[:, None]) + albedo * weight[:, None]
    colour_node.image = packed_image(output / f'face_{identity}_albedo.png', _dilate(old, used, 10))

    # Pore, freckle, lip-line and Ade's individual beard/moustache/stubble relief as a crisp detail normal.
    height = np.zeros(used.shape, np.float32)
    skin_relief = -sample(detail) * .00105 * weight * (.4 + .6 * covered)
    if identity == 'ade':
        beard_relief = sample(beard_hair_relief) * .00056 * weight * (.35 + .65 * covered)
        height[used] = skin_relief + beard_relief
    else:
        height[used] = skin_relief
    # Start flat: the old map was baked for the previous face shape and
    # printed its planes (bright cheek patches) onto the new one.
    normal_map = np.ones((size, size, 3), np.float32) * np.array([0, 0, 1], np.float32)
    for axis, channel in ((0, 1), (1, 0)):
        valid = used & np.roll(used, 1, axis) & np.roll(used, -1, axis)
        lengths = np.linalg.norm(np.roll(pos, -1, axis) - np.roll(pos, 1, axis), axis=-1)
        relief = np.roll(height, -1, axis) - np.roll(height, 1, axis)
        lim = .36 if identity == 'ade' else .24
        normal_map[..., channel][valid] = (normal_map[..., channel][valid]
                                          - np.clip(relief[valid] / np.maximum(lengths[valid], .00024), -lim, lim))
    normal_map /= np.maximum(np.linalg.norm(normal_map, axis=-1, keepdims=True), 1e-6)
    normal_image.image = packed_image(output / f'face_{identity}_normal.png',
                                      _dilate(normal_map * .5 + .5, used, 7), normal=True)
    normal_node.inputs['Strength'].default_value = 0.82 if identity == 'ade' else 0.76
    return landmarks


def photo_iris(face, atlas_path, centre, iris_px, output, size=512):
    """Resample a photographed eyeball into the ocular atlas layout (iris
    edge at r = .49 of the half-width) and use it for both eyes."""
    from build_b_surface import packed_image
    img = _source(atlas_path)
    yy, xx = (np.mgrid[0:size, 0:size] + .5) / size * 2 - 1
    scale = iris_px / .49
    u = centre[0] + xx * scale
    v = centre[1] + yy * scale
    u = np.clip(u, 0, img.shape[1] - 1.001)
    v = np.clip(v, 0, img.shape[0] - 1.001)
    x0, y0 = u.astype(int), v.astype(int)
    fx, fy = (u - x0)[..., None], (v - y0)[..., None]
    out = (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
           + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)
    out = out[::-1].astype(np.float32)   # Blender rows run bottom-up; values stay sRGB
    material = face.data.materials['hero_eye']
    node = material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].links[0].from_node
    node.image = packed_image(output / 'ocular_albedo.png', out)
