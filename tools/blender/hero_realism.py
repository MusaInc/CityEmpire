"""Close-up mesh finishing for the fixed WorldState heroes."""
import math
import random
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from build_b_surface import packed_image, pixels
from garment_kit import _dilate, raster_uv
from hero_finish import material_vertices
from hero_groom import ribbon
from hero_polish import sculpt_face, shape_figure, balance_face, rebuild_bun, shape_lips, smooth_side_hairline
from portrait_wrap import smooth as smooth_array
from wardrobe_quality import adjust_basis, smooth


def surface(obj, material, coordinates=None):
    return BVHTree.FromPolygons(
        coordinates if coordinates is not None else [v.co for v in obj.data.vertices],
        [tuple(poly.vertices) for poly in obj.data.polygons if poly.material_index == material],
    )


def eye_centres(face):
    vertices = material_vertices(face, ('hero_eye',))
    sides = [[face.data.vertices[i].co for i in vertices if sign * face.data.vertices[i].co.x > 0]
             for sign in (-1, 1)]
    return [sum(side, Vector()) / len(side) for side in sides]


def face_planes(face, identity, eyes):
    """Change the orbital and mouth contours in the basis and every expression."""
    skin = material_vertices(face, ('hero_skin_face_',))
    eye_z = sum(eye.z for eye in eyes) / 2
    for key in face.data.shape_keys.key_blocks:
        for index in skin:
            point = key.data[index].co
            x, y, z = point
            eye = eyes[x > 0]
            dx, dz = x - eye.x, z - eye.z
            front = smooth(eye.y - .045, eye.y + .006, y)
            below = math.exp(-(dx / .020)**4 - ((dz + .012) / .007)**2)
            cheek = math.exp(-((abs(x) - .052) / .015)**2 - ((z - eye_z + .032) / .022)**2)
            jaw = math.exp(-((abs(x) - .053) / .022)**2 - ((z - eye_z + .083) / .019)**2)
            fold = math.exp(-((abs(x)-.025-(eye_z-z)*.13)/.011)**2
                            - ((z-eye_z+.064)/.022)**2)
            point.y += front * (-.0019 * below + .0019 * fold)
            if identity == 'jules':
                side = abs(x)
                cheek_front = smooth(eye.y-.061, eye.y+.001, y)
                # Correct the protruding lateral cheekbone spike cleanly inward and smooth lower-cheek transition.
                crest = math.exp(-((side-.043)/.019)**2 - ((dz+.027)/.020)**2)
                hollow = math.exp(-((side-.045)/.024)**2 - ((dz+.054)/.020)**2)
                point.y += cheek_front * (-.0088*crest + .0046*hollow)
                point.x -= math.copysign(.0036*cheek_front*crest, x)
                point.x *= 1 - .032 * jaw
                point.y += .0008 * front * math.exp(-(x/.025)**4 - ((z-eye_z+.066)/.008)**2)
            else:
                point.y -= .0015 * front * cheek
    basis = face.data.shape_keys.key_blocks[0]
    for vertex, point in zip(face.data.vertices, basis.data):
        vertex.co = point.co
    face.data.update()


def smooth_jules_cheeks(face, eyes):
    """Smooth Jules's lateral cheekbones and upper-cheek-to-jaw transition without
    distorting chin, mouth or eye landmarks, preserving all expression shape keys."""
    eye = (eyes[0] + eyes[1]) * 0.5
    keys = face.data.shape_keys.key_blocks
    basis = keys[0].data
    skin = material_vertices(face, ('hero_skin_face_',))
    pts = {i: basis[i].co.copy() for i in skin}
    bm = bmesh.new()
    bm.from_mesh(face.data)
    bm.verts.ensure_lookup_table()
    ring = {}
    for i in pts:
        v = bm.verts[i]
        if not v.is_boundary:
            ring[i] = [e.other_vert(v).index for e in v.link_edges if e.other_vert(v).index in pts]
    bm.free()

    cur = dict(pts)
    weights = {}
    for i, p in pts.items():
        dz = p.z - eye.z
        ax = abs(p.x)
        near_eye = min((p - e).length for e in eyes)
        # Focus on lateral cheekbone, mid-cheek AND soft smoothing of the bottom chin bar!
        outer_cheek = math.exp(-((ax - 0.044) / 0.020) ** 2 - ((dz + 0.032) / 0.024) ** 2)
        lower_chin = math.exp(-(p.x / 0.038) ** 4 - ((dz + 0.095) / 0.015) ** 2) * 0.65
        mouth_guard = 1.0 - math.exp(-(p.x / 0.030) ** 4 - ((dz + 0.064) / 0.016) ** 4)
        front = smooth(eye.y - 0.070, eye.y - 0.015, p.y)
        w = max(outer_cheek * smooth(0.018, 0.030, near_eye), lower_chin) * mouth_guard * front
        weights[i] = min(1.0, w)

    for step in range(28):
        k = 0.50 if step % 2 == 0 else -0.47
        nxt = dict(cur)
        for i, nb in ring.items():
            w = weights.get(i, 0.0)
            if w < 0.02 or len(nb) < 3:
                continue
            avg = sum((cur[j] for j in nb), Vector()) / len(nb)
            nxt[i] = cur[i] + (avg - cur[i]) * k * w
        cur = nxt

    delta = {}
    for i, p in pts.items():
        d = cur[i] - p
        dz = p.z - eye.z
        ax = abs(p.x)
        front = smooth(eye.y - 0.068, eye.y - 0.018, p.y)
        # Gentle additional smoothing of the exact malar peak so 3/4 silhouette is soft and natural.
        peak = math.exp(-((ax - 0.042) / 0.015) ** 2 - ((dz + 0.026) / 0.016) ** 2) * front
        d.y -= 0.0022 * peak
        d.x -= math.copysign(0.0012 * peak, p.x)
        # Smooth feminine oval chin/jawline without flattening or pinching an under-chin bar.
        low_chin = smooth(-0.072, -0.096, dz) * smooth(-0.126, -0.104, dz) * smooth(0.014, 0.044, ax) * front
        d.x -= p.x * 0.055 * low_chin
        d.y -= 0.0012 * low_chin
        chin_tip = math.exp(-(p.x / 0.018) ** 2 - ((dz + 0.098) / 0.012) ** 2) * front
        d.z -= 0.0014 * chin_tip
        under_chin = smooth(-0.102, -0.122, dz) * smooth(-0.145, -0.124, dz) * smooth(0.052, 0.014, ax) * smooth(eye.y - 0.050, eye.y + 0.004, p.y)
        d.y -= 0.0045 * under_chin
        d.z += 0.0026 * under_chin
        if d.length_squared > 1e-13:
            delta[i] = d

    for key in keys:
        for i, d in delta.items():
            key.data[i].co += d
    for i in delta:
        face.data.vertices[i].co = keys[0].data[i].co
    face.data.update()


def visible_lid(skin, eyeball, x, centre, upper):
    """Trace the boundary where the visible globe meets the sculpted lid."""
    direction = Vector((0, -1, 0))
    def samples(z):
        origin = Vector((x, centre.y + .075, z))
        return skin.ray_cast(origin, direction, .14)[0], eyeball.ray_cast(origin, direction, .14)[0]

    candidates = []
    for step in range(-28, 29):
        z = centre.z + step * .00033
        lid, globe = samples(z)
        if lid is not None and globe is not None and globe.y > lid.y + .00012:
            candidates.append(z)
    if not candidates:
        return None
    exposed = max(candidates) if upper else min(candidates)
    step = .00065 if upper else -.00062
    lid, _ = samples(exposed + step)
    return lid


def _add_tear_duct(bm, eye, sign, skin, eyeball, slot, weights, head, shapes):
    """Build a sculpted moist pinkish inner-canthus caruncle tucked snugly where
    upper and lower lids meet the medial sclera (eliminates angular hollow gaps)."""
    # Probe the medial edge of the visible eye opening.
    inner_x = None
    for step in range(4, 24):
        x = eye.x - sign * (0.0075 + step * 0.00045)
        u_pt = visible_lid(skin, eyeball, x, eye, True)
        l_pt = visible_lid(skin, eyeball, x, eye, False)
        if u_pt is not None and l_pt is not None:
            inner_x = x
        elif inner_x is not None:
            break
    if inner_x is None:
        inner_x = eye.x - sign * 0.0112
    # Anchor cleanly inside the medial corner pocket, resting softly against the sclera.
    c_x = inner_x + sign * 0.0004
    c_z = eye.z - 0.0005
    g_hit = eyeball.ray_cast(Vector((c_x, eye.y + 0.075, c_z)), Vector((0, -1, 0)), 0.14)[0]
    s_hit = skin.ray_cast(Vector((c_x, eye.y + 0.075, c_z)), Vector((0, -1, 0)), 0.14)[0]
    base_y = g_hit.y if g_hit is not None else (s_hit.y if s_hit is not None else eye.y + 0.011)
    centre = Vector((c_x, base_y + 0.00055, c_z))
    rx, ry, rz = 0.0020, 0.0012, 0.0015
    rings = []
    for i in range(5):
        phi = math.pi * (i + 0.5) / 5.0
        row = []
        for j in range(10):
            th = math.tau * j / 10.0
            # Slightly almond-tapered tear-duct mound facing outward (+Y).
            pt = centre + Vector((rx * math.sin(phi) * math.cos(th),
                                  ry * math.sin(phi) * math.sin(th),
                                  rz * math.cos(phi)))
            v = bm.verts.new(pt)
            v[weights][head] = 1.0
            for layer in shapes:
                v[layer] = pt
            row.append(v)
        rings.append(row)
    new_f = []
    for i in range(4):
        for j in range(10):
            jn = (j + 1) % 10
            f = bm.faces.new((rings[i][j], rings[i][jn], rings[i + 1][jn], rings[i + 1][j]))
            f.material_index = slot
            f.smooth = True
            new_f.append(f)
    for cap in (rings[0][::-1], rings[-1]):
        f = bm.faces.new(cap)
        f.material_index = slot
        f.smooth = True
        new_f.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=new_f)


def lashes(face, eyes, identity):
    """Build smooth eyelid waterline margins, sculpted inner-canthus tear ducts,
    and soft non-aliasing curved eyelashes rooted cleanly into the upper eyelid."""
    skin_slot = next(i for i, m in enumerate(face.data.materials) if m.name.startswith('hero_skin_face_'))
    eye_slot = face.data.materials.find('hero_eye')
    brow_slot = face.data.materials.find('hero_brow')
    rim_slot = face.data.materials.find('hero_lid_rim')
    skin, eyeball = surface(face, skin_slot), surface(face, eye_slot)
    blink = face.data.shape_keys.key_blocks['Blink']
    shut = surface(face, skin_slot, [v.co for v in blink.data])

    # Dedicated moist pinkish tear-duct caruncle material.
    caruncle_mat = bpy.data.materials.get('hero_tear_duct') or bpy.data.materials.new('hero_tear_duct')
    caruncle_mat.use_nodes = True
    c_bsdf = caruncle_mat.node_tree.nodes['Principled BSDF']
    c_bsdf.inputs['Base Color'].default_value = (0.54, 0.28, 0.25, 1.0) if identity == 'jules' else (0.42, 0.22, 0.19, 1.0)
    c_bsdf.inputs['Roughness'].default_value = 0.18
    caruncle_slot = face.data.materials.find('hero_tear_duct')
    if caruncle_slot < 0:
        caruncle_slot = len(face.data.materials)
        face.data.materials.append(caruncle_mat)

    bm = bmesh.new()
    bm.from_mesh(face.data)
    rim = {v for f in bm.faces if f.material_index == rim_slot for v in f.verts}
    bmesh.ops.delete(bm, geom=list(rim), context='VERTS')
    shapes = list(bm.verts.layers.shape.values())
    closed = bm.verts.layers.shape.get('Blink')
    weights = bm.verts.layers.deform.verify()
    head = face.vertex_groups['b_head'].index
    rng = random.Random(516)
    jules = identity == 'jules'
    lash_faces = []

    for eye in eyes:
        sign = 1 if eye.x > 0 else -1
        # 0. Sculpted inner-canthus tear duct (caruncle) sealing the medial corner naturally.
        _add_tear_duct(bm, eye, sign, skin, eyeball, caruncle_slot, weights, head, shapes)

        # 1. Continuous soft dark upper lash-line ribbon (grounds the upper lid cleanly, zero dotted aliasing!).
        band_steps = 24
        band_rows = []
        for s in range(band_steps + 1):
            across = 0.06 + 0.88 * (s / band_steps)
            x = eye.x + sign * ((across - 0.5) * 0.0246)
            root = visible_lid(skin, eyeball, x, eye, True)
            if root is None:
                continue
            arc = math.sin((s / band_steps) * math.pi) ** 0.55
            seam_z = eye.z - 0.0018 + sign * (x - eye.x) * 0.12
            shut_root = shut.ray_cast(Vector((x, eye.y + 0.075, seam_z)), Vector((0, -1, 0)), 0.14)[0]
            shift = (shut_root - root) if shut_root is not None else Vector()
            ext = (0.0021 if jules else 0.00110) * (0.45 + 0.55 * arc) * (0.80 + 0.34 * across)
            p_in = root + Vector((0.0, -0.0008, -0.00020))
            p_mid = root + Vector((sign * ext * 0.14 * across, ext * 0.48, -0.00005 + ext * (0.16 if jules else 0.05)))
            p_out = root + Vector((sign * ext * 0.28 * across, ext * 0.88, ext * (0.38 if jules else 0.14)))
            v0, v1, v2 = bm.verts.new(p_in), bm.verts.new(p_mid), bm.verts.new(p_out)
            for v, tip_k in ((v0, 0.0), (v1, 0.45), (v2, 1.0)):
                v[weights][head] = 1
                for layer in shapes:
                    v[layer] = v.co
                v[closed] = v.co + shift + Vector((0, 0, -0.65 * ext * tip_k))
            band_rows.append((v0, v1, v2))
        for a, b in zip(band_rows, band_rows[1:]):
            for k in range(2):
                quad = (a[k], b[k], b[k + 1], a[k + 1]) if sign > 0 else (a[k], a[k + 1], b[k + 1], b[k])
                poly = bm.faces.new(quad)
                poly.material_index = brow_slot
                poly.smooth = True
                lash_faces.append(poly)

        # 2. Delicate, gracefully swept overlapping lash fans for Jules (fine feather-tip curl, zero chunky dashes!).
        cluster_count = 36 if jules else 0
        for n in range(cluster_count):
            across = 0.08 + 0.86 * (n + 0.5) / cluster_count
            x = eye.x + sign * ((across - 0.5) * 0.0242)
            root = visible_lid(skin, eyeball, x, eye, True)
            if root is None:
                continue
            arc = math.sin(((n + 0.5) / cluster_count) * math.pi) ** 0.52
            wing = 0.72 + 0.52 * smooth(0.35, 0.92, across)
            length = 0.0033 * arc * wing * rng.uniform(0.90, 1.10)
            width = 0.00046 * rng.uniform(0.90, 1.10)
            seam_z = eye.z - 0.0018 + sign * (x - eye.x) * 0.12
            shut_root = shut.ray_cast(Vector((x, eye.y + 0.075, seam_z)), Vector((0, -1, 0)), 0.14)[0]
            shift = (shut_root - root) if shut_root is not None else Vector()
            rows = []
            for row in range(4):
                t = row / 3
                tip = root + Vector((sign * length * (0.12 + 0.74 * across) * t,
                                     -0.00035 + length * (0.86 * t - 0.16 * t * t),
                                     -0.00025 + length * (0.08 * t + 0.44 * t * t)))
                w_cur = width * (1.0 - 0.88 * t)
                vertices = [bm.verts.new(tip + Vector((side * w_cur, 0, 0))) for side in (-1, 1)]
                for v in vertices:
                    v[weights][head] = 1
                    for layer in shapes:
                        v[layer] = v.co
                    v[closed] = v.co + shift + Vector((0, 0, -0.68 * length * t))
                rows.append(vertices)
            for a, b in zip(rows, rows[1:]):
                poly = bm.faces.new((a[0], b[0], b[1], a[1]))
                poly.material_index = brow_slot
                poly.smooth = True
                lash_faces.append(poly)
    if lash_faces:
        bmesh.ops.recalc_face_normals(bm, faces=lash_faces)
    dental_arch(face, bm, skin, eyes, identity)
    bm.to_mesh(face.data)
    bm.free()
    face.data.update()


def dental_arch(face, bm, skin, eyes, identity):
    """Fit a rounded upper arch inside the existing lip seam."""
    enamel = bpy.data.materials.new('hero_enamel')
    enamel.use_nodes = True
    shader = enamel.node_tree.nodes['Principled BSDF']
    shader.inputs['Base Color'].default_value = (.56, .49, .39, 1)
    shader.inputs['Roughness'].default_value = .39
    slot = len(face.data.materials)
    face.data.materials.append(enamel)
    layers = list(bm.verts.layers.shape.values())
    smile = bm.verts.layers.shape.get('Smile')
    deform = bm.verts.layers.deform.verify()
    head = face.vertex_groups['b_head'].index
    eye = (eyes[0]+eyes[1])*.5
    mouth = eye.z - (.0649 if identity == 'jules' else .0709)
    for side in (-1, 1):
        edge = .00017
        for tooth, width in enumerate((.0069, .0053, .0054, .0046)):
            x = side * (edge + width*.5)
            edge += width + .00018
            z = mouth + .004 + .0018*(tooth/3)**1.5
            hit = skin.ray_cast(Vector((x, eye.y+.105, z)), Vector((0,-1,0)), .19)[0]
            if hit is None:
                continue
            # Seat upper dental arch deeply inside the oral cavity so teeth NEVER show a white line between closed lips.
            centre = Vector((x, hit.y-.0135, z+.0046))
            height = .0040 - .00036*tooth
            rows = []
            for level in (-1, -.70, .75, 1):
                row = []
                size = 1 - .34*abs(level)**5
                for step in range(8):
                    angle = math.tau*step/8
                    point = centre + Vector((size*width*.49*math.cos(angle),
                                             size*.0026*math.sin(angle), level*height))
                    vertex = bm.verts.new(point)
                    vertex[deform][head] = 1
                    for layer in layers:
                        vertex[layer] = point
                    vertex[smile] = point + Vector((0, 0, -.0012))
                    row.append(vertex)
                rows.append(row)
            for lower, upper in zip(rows, rows[1:]):
                for i in range(8):
                    j = (i+1) % 8
                    poly = bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
                    poly.material_index = slot
                    poly.smooth = True
            for row in (rows[0][::-1], rows[-1]):
                bm.faces.new(row).material_index = slot


def finish_complexion(face, identity, eyes, output):
    """Bake regional pigment and sparse microdetail into the existing portrait UVs."""
    slot = next(i for i, m in enumerate(face.data.materials) if m.name.startswith('hero_skin_face_'))
    material = face.data.materials[slot]
    shader = material.node_tree.nodes['Principled BSDF']
    node = shader.inputs['Base Color'].links[0].from_node
    size = node.image.size[0]
    positions, normals, valid = raster_uv(face, size, material_index=slot)
    x, y, z = positions[valid].T
    eye_z = sum(p.z for p in eyes) / 2
    eye_y = sum(p.y for p in eyes) / 2
    front = smooth_array(.07, .65, normals[valid, 1]) * smooth_array(eye_y-.067, eye_y-.010, y)
    level = z-eye_z
    cheek = np.exp(-((np.abs(x)-.039)/.027)**2 - ((level+.032)/.016)**2)*front
    temple = np.exp(-((np.abs(x)-.059)/.019)**2 - ((level-.013)/.028)**2)
    chin = np.exp(-(x/.039)**4 - ((level+.083)/.020)**2)*front
    cloud = np.sin(x*291+y*163+z*152) * np.sin(z*263-x*135+y*73)
    phase = np.sin(np.floor(x*1430)*38.741 + np.floor(z*1430)*83.861)
    grain = np.mod(phase*18917.13, 1)
    # Ultra-clean, healthy natural complexion (eliminate muddy blotches & noisy dark speckles!).
    pigment = (.004 * cloud - .005 * grain) * front
    freckles = np.zeros_like(x)
    rng = random.Random(973 if identity == 'jules' else 613)
    for _ in range(16 if identity == 'jules' else 5):
        cx, cz = rng.gauss(0, .028), rng.gauss(-.034, .007)
        r = rng.uniform(.00022, .00062)
        strength = rng.uniform(.010, .042)
        freckles += strength * np.exp(-((x - cx) / r)**2 - ((level - cz) / (r * .76))**2)
    pigment -= np.minimum(.065, freckles) * front
    warm = (.022 * cheek + .008 * temple) if identity == 'jules' else (.018 * cheek + .005 * temple)
    # No fake procedural chin/beard shadow (the photographic face texture already carries Ade's natural goatee!).
    shadow = 0.0
    colour = pixels(node.image)[..., :3].copy()
    colour[valid] *= (1 + pigment - shadow)[:, None]
    colour[valid] *= 1 + warm[:, None] * np.array([.23, -.41, -.86])
    node.image = packed_image(output / f'face_{identity}_albedo.png', _dilate(colour, valid, 8))
    if 'Subsurface Weight' in shader.inputs:
        shader.inputs['Subsurface Weight'].default_value = .052
        shader.inputs['Subsurface Radius'].default_value = (1.0, .38, .21)
        shader.inputs['Subsurface Scale'].default_value = .009
    orm_node = shader.inputs['Roughness'].links[0].from_node.inputs[0].links[0].from_node
    orm = pixels(orm_node.image)[..., :3].copy()
    size = orm.shape[0]
    positions, normals, valid = raster_uv(face, size, material_index=slot)
    x, y, z = positions[valid].T
    nose = np.exp(-(x / .017)**2 - ((z - eye_z + .026) / .024)**2)
    forehead = np.exp(-(x / .038)**2 - ((z - eye_z - .034) / .022)**2)
    cheek_hl = np.exp(-((np.abs(x) - .038) / .022)**2 - ((z - eye_z + .024) / .016)**2)
    lips_hl = np.exp(-(x / .024)**4 - ((z - eye_z + .064) / .009)**2)
    brow_zone = np.exp(-((np.abs(x) - .028) / .018)**2 - ((z - eye_z - .017) / .0065)**2)
    beard_rough = 0.0
    if identity == 'ade':
        # Matte facial hair roughness on moustache, goatee & jaw stubble so hair never has waxy skin gloss!
        stache = np.exp(-(x / .022)**2 - ((z - eye_z + .055) / .0065)**2)
        goatee = np.exp(-(x / .026)**2 - ((z - eye_z + .092) / .018)**2)
        stubble = np.exp(-((np.abs(x) - .044) / .026)**2 - ((z - eye_z + .074) / .026)**2) * 0.45
        beard_rough = np.clip(stache + goatee + stubble, 0.0, 1.0)
    rms = .018 * np.sin(x * 2912 + y * 927) * np.sin(z * 2123 - x * 1763)
    f_fac = np.maximum(0, normals[valid, 1])
    # Realistic human skin roughness: subtle natural T-zone & moist lips, satin-matte cheeks & jaw, matte brows/beard.
    base_rough = .61 - (.10 * nose + .05 * forehead + .035 * cheek_hl + .14 * lips_hl) * f_fac + .16 * brow_zone + .24 * beard_rough + rms
    orm[valid, 1] = np.clip(base_rough, .42, .88)
    if identity == 'jules':
        # Seamless clavicle match: blend lower-neck ORM AO -> 1.0 and roughness -> 0.56 (exact hero_skin_body values!).
        zmin_j = z.min()
        clav_blend = 1.0 - smooth_array(zmin_j + 0.008, zmin_j + 0.056, z)
        orm[valid, 0] = orm[valid, 0] * (1.0 - clav_blend) + 1.0 * clav_blend
        orm[valid, 1] = orm[valid, 1] * (1.0 - clav_blend) + 0.56 * clav_blend
    orm_node.image = packed_image(output / f'hero_skin_face_{identity}_orm.png', _dilate(orm, valid, 5), True)


def refine_scalp(face, shell, identity, eyes, output):
    """Fit the roots to the temples, then bake fine directional breakup into the cap."""
    skin_slot = next(i for i, m in enumerate(face.data.materials) if m.name.startswith('hero_skin_face_'))
    skin = surface(face, skin_slot)
    eye = (eyes[0] + eyes[1]) / 2
    skull = eye + Vector((0,-.069,.029))
    cap = {i for p in shell.data.polygons if p.material_index == 0 for i in p.vertices}
    for index in cap:
        p = shell.data.vertices[index].co
        ray = (p-skull).normalized()
        hit, _, _, _ = skin.ray_cast(p+ray*.018, -ray, .039)
        if hit is None:
            continue
        front = smooth(eye.y-.061, eye.y-.012, p.y)
        if identity == 'ade':
            side = 1 - smooth(eye.z+.021, eye.z+.065, p.z)
            gap = (p-hit).dot(ray)
            p += ray * max(-.0028*side, .0017-gap)
        else:
            part = -.006 + .054 * (eye.y-p.y)
            line = math.exp(-((p.x-part)/.007)**2) * front
            gap = (p-hit).dot(ray)
            p -= ray * min(.0017, max(0, gap-.0013)) * line
    shell.data.update()
    if identity == 'jules':
        smooth_side_hairline(shell, skin, eye)
        fade_front_rim(shell, skin, eye)

    mat = shell.data.materials[0]
    shader = mat.node_tree.nodes['Principled BSDF']
    shader.inputs['Roughness'].default_value = .68
    node = shader.inputs['Base Color'].links[0].from_node
    size = 512
    positions, _, valid = raster_uv(shell, size, material_index=0)
    x, y, z = positions[valid].T
    if identity == 'jules':
        off = x - (-.006 + .054*(eye.y-y))
        part = np.exp(-(off/.0016)**2) * smooth_array(eye.y-.062,eye.y+.002,y)
        theta = np.arctan2(np.abs(off), np.maximum(.009, .11+y-eye.y))
        phase = theta*525 + 3.6*np.sin(z*66-y*47) + 1.8*np.sin(theta*17)
        coarse = np.sin(theta*92 + y*69)**2
        density = shell.data.uv_layers['ClothFreedom']
        for p in shell.data.polygons:
            if p.material_index != 0:
                continue
            for loop, index in zip(p.loop_indices, p.vertices):
                q = shell.data.vertices[index].co
                centre = -.006 + .054*(eye.y-q.y)
                separation = math.exp(-((q.x-centre)/.0036)**2)*smooth(eye.y-.050,eye.y+.004,q.y)
                density.data[loop].uv.y *= 1 - .28*separation
    else:
        for poly in shell.data.polygons:
            for loop, i in zip(poly.loop_indices, poly.vertices):
                px, py, pz = shell.data.vertices[i].co
                temple = smooth(.036, .068, abs(px)) * smooth(eye.y-.115, eye.y-.038, py)
                nape = 1 - smooth(eye.y-.145, eye.y-.105, py)
                base = smooth(eye.z-.047, eye.z+.061, pz)
                depth = max(temple, nape)
                roots = shell.data.uv_layers['ClothFreedom'].data[loop].uv
                roots.y = min(roots.y, 1 - depth * (1-base)**.60)
        swept = x + .42*(y-eye.y) + .0018*np.sin(y*119+z*93)
        phase = swept*6180 + 6*np.sin(y*129-z*160)
        coarse = np.sin(swept*420 + z*267)**2
        part = 0
    fibre = .059*np.sin(phase) + .052*np.cos(phase*.59+y*229)
    shade = np.clip(.64 + .12*coarse + fibre + .14*part, .33, .95)
    colour = np.ones((size,size,3), np.float32)*.68
    colour[valid] = shade[:, None] * np.array([1.0, .966, .932])
    node.image = packed_image(output / Path(node.image.filepath).name, _dilate(colour, valid, 8))


def fade_front_rim(shell, skin, eye):
    """Feather Jules's front hairline: roots lie on the skin and thin out over
    a ragged, rounded band instead of ending on a blunt helmet edge."""
    data = shell.data
    count = {}
    for poly in data.polygons:
        if poly.material_index == 0:
            for edge in poly.edge_keys:
                count[edge] = count.get(edge, 0) + 1
    rim = {i for edge, n in count.items() if n == 1 for i in edge}
    rim = [data.vertices[i].co.copy() for i in rim
           if data.vertices[i].co.y > eye.y - .115 and data.vertices[i].co.z > eye.z - .030]
    if not rim:
        return
    from mathutils.kdtree import KDTree
    kd = KDTree(len(rim))
    for i, co in enumerate(rim):
        kd.insert(co, i)
    kd.balance()
    band = {}
    for vertex in data.vertices:
        p = vertex.co
        if p.y < eye.y - .085:
            continue
        _, _, dist = kd.find(p)
        # Wider at the temple corners so the outline turns a curve, not a step.
        corner = math.exp(-((abs(p.x) - .047) / .016)**2)
        width = .0085 + .0105 * corner
        ragged = .0022 * math.sin(p.x * 1630) * math.sin(p.z * 1170 + p.x * 310)
        t = smooth(0, width, dist + ragged)
        if t >= 1:
            continue
        band[vertex.index] = t
        hit, _, _, _ = skin.find_nearest(p)
        if hit is not None:
            vertex.co = hit + (p - hit) * (.25 + .75 * t)
    data.update()
    density = data.uv_layers['ClothFreedom']
    for poly in data.polygons:
        if poly.material_index != 0:
            continue
        for loop, index in zip(poly.loop_indices, poly.vertices):
            if index in band:
                uv = density.data[loop].uv
                uv.y = min(uv.y, .04 + .96 * band[index] ** 1.4)


def frame_bun(face, shell, groom, eyes):
    """Draft swept root-to-tip locks and flyaways around the actual face."""
    skin = surface(face, next(i for i, m in enumerate(face.data.materials)
                              if m.name.startswith('hero_skin_face_')))
    cap = surface(shell, 0)
    eye = (eyes[0] + eyes[1]) * .5
    mesh = groom.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    # The hanging ribbons are separate islands. Keep the scalp and bun wafts.
    remaining = set(bm.verts)
    while remaining:
        start = remaining.pop()
        island = [start]
        for vertex in island:
            for edge in vertex.link_edges:
                other = edge.other_vert(vertex)
                if other in remaining:
                    remaining.remove(other)
                    island.append(other)
        if min(v.co.z for v in island) < eye.z+.009 and max(v.co.y for v in island) > eye.y-.015:
            bmesh.ops.delete(bm, geom=island, context='VERTS')
    batch = ([], [], [])
    rng = random.Random(816)
    direction = Vector((0,-1,0))
    lock_motion = []
    for sign in (-1, 1):
        for lock in range(4):
            centres, normals = [], []
            phase = rng.uniform(-.13, .13)
            root_x = rng.uniform(.041, .053)
            strand_width = rng.uniform(.0007,.0022)
            length = rng.uniform(.144,.183) + (.012 if sign<0 else 0)
            for row in range(21):
                t = row/20
                z = eye.z + .075 - length*t
                x = sign * (root_x + .016*math.sin(min(1, t*1.24)*math.pi/2)
                            + .008*math.sin(t*math.tau+phase)*smooth(.15,.71,t))
                origin = Vector((x, eye.y+.087, z))
                root = cap.ray_cast(origin, direction, .16)[0] if row < 7 else None
                skin_hit = skin.ray_cast(origin, direction, .17)[0]
                y = eye.y - .004 + .024*math.sin(t*math.pi*1.16) - .025*t*t
                if skin_hit is not None:
                    y = max(y, skin_hit.y + .0018 + .007*math.sin(t*math.pi))
                if root is not None:
                    y = max(y, root.y + .0004)
                centres.append(Vector((x, y, z)))
                normals.append(Vector((sign*.42, 1, .21*(1-t))).normalized())
                lock_motion.extend([.073*smooth(.14,.98,t)]*2)
            ribbon(batch, centres, normals, strand_width, lock % 8)
    points, faces, texels = batch
    weights = bm.verts.layers.deform.verify()
    uv = bm.loops.layers.uv.active
    freedom = bm.loops.layers.uv.get('ClothFreedom')
    head = groom.vertex_groups['b_head'].index
    verts = [bm.verts.new(point) for point in points]
    lookup = {vertex: i for i, vertex in enumerate(verts)}
    for v in verts:
        v[weights][head] = 1
    for indices in faces:
        poly = bm.faces.new([verts[i] for i in indices])
        poly.smooth = True
        for loop in poly.loops:
            index = lookup[loop.vert]
            loop[uv].uv = texels[index]
            loop[freedom].uv = (lock_motion[index], .96)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def split_skirt_correctives(models):
    """Keep the free skirt panel following its own leg's stride."""
    for name in ('Lower_midiskirt', 'Lower_maxiskirt', 'Topx_Fashion_Loosedress_Skirt'):
        obj = models.get(name)
        if obj is None:
            continue
        keys = obj.data.shape_keys.key_blocks
        if name == 'Lower_midiskirt' and 'Hem_Seated' in keys:
            # Seated, the back panel hung from the hips straight through the
            # seat. Fold it forward under the seat instead (she sits on it).
            seated = keys['Hem_Seated']
            waist = max(v.co.z for v in obj.data.vertices)
            seat = waist - .200
            for vertex in obj.data.vertices:
                b = vertex.co
                back = smooth(.035, -.055, b.y)
                below = smooth(seat + .025, seat - .015, b.z)
                w = back * below
                if w <= 0:
                    continue
                target = Vector((b.x * .96, b.y * .5 + .035, seat - .004 + (seat - b.z) * .045))
                key = seated.data[vertex.index].co
                seated.data[vertex.index].co = key.lerp(target, w)
        for motion in ('Front', 'Back'):
            left = keys['Hem_' + motion]
            right = obj.shape_key_add(name='Hem_' + motion + '_Right')
            for vertex in obj.data.vertices:
                i = vertex.index
                basis = vertex.co
                original = left.data[i].co - basis
                # Crossfade through the middle seam without breaking the panel.
                right_weight = smooth(-.045, .045, basis.x)
                left.data[i].co = basis + original*(1-right_weight)
                right.data[i].co = basis + original*right_weight


def fit_jacket(models, rig, face, identity):
    """Fit the stand collar and sculpt compression folds around the elbow."""
    if identity == 'ade':
        jacket, collar = 'Top_Bomber', 'Topx_Bomber_Neck'
        collar_ease = .12
    else:
        jacket, collar = 'Top_Fashion_Moto', 'Topx_Fashion_Moto_Collar'
        collar_ease = .08
    top = models[jacket]
    stand = models[collar]
    high = max(v.co.z for v in stand.data.vertices)
    centre = sum((v.co for v in stand.data.vertices), Vector()) / len(stand.data.vertices)
    neck = surface(face, face.data.materials.find('hero_skin_face_' + identity))

    def shape_collar(point):
        height = smooth(high-.031, high-.003, point.z)
        radial = Vector((point.x-centre.x, point.y-centre.y, 0))
        direction = radial.normalized()
        hit = neck.ray_cast(point+direction*.036, -direction, .080)[0]
        gap = (point-hit).dot(direction) if hit is not None else 0
        ease = min(radial.length*collar_ease, max(0, gap-.006))
        return -direction * ease * height

    adjust_basis(stand, shape_collar)
    elbow = rig.data.bones['b_forearm_r'].head_local
    wrist = rig.data.bones['b_hand_r'].head_local
    axis = (wrist-elbow).normalized()

    def sleeve(point):
        side = 1 if point.x >= 0 else -1
        relative = Vector((abs(point.x), point.y, point.z)) - elbow
        along = relative.dot(axis)
        radial = relative - along*axis
        field = math.exp(-((along-.013)/.055)**2)
        crease = math.sin(along*258 + relative.y*73) + .40*math.sin(along*467-relative.z*117)
        offset = radial.normalized()*(.00165*crease*field) if radial.length else Vector()
        offset.x *= side
        return offset * smooth(.215, .270, abs(point.x))

    adjust_basis(top, sleeve)


def finish_realism(rig, meshes, identity, output):
    models = {obj.name: obj for obj in meshes}
    face = models['Face_' + identity]
    if face.get('worldstate_realism'):
        return
    eyes = eye_centres(face)
    face_planes(face, identity, eyes)
    if identity == 'jules':
        balance_face(face, eyes)
        sculpt_face(face, eyes)
        shape_lips(face, eyes)
        from jules_anatomy import correct_anatomy
        correct_anatomy(face, eyes)
        smooth_jules_cheeks(face, eyes)
        from portrait_project import drop_geometry_brows
        drop_geometry_brows(face)   # the photographic texture carries the brows
    else:
        from portrait_project import drop_geometry_brows
        from jules_anatomy import correct_ade
        drop_geometry_brows(face)
        correct_ade(face, eyes)
    lashes(face, eyes, identity)
    finish_complexion(face, identity, eyes, output)
    fit_jacket(models, rig, face, identity)
    shape_figure(rig, meshes, identity)
    style = 'crop' if identity == 'ade' else 'bun'
    shell = models[f'Hair_{style}_{identity}']
    refine_scalp(face, shell, identity, eyes, output)
    if identity == 'jules':
        frame_bun(face, shell, models['Groom_bun_jules'], eyes)
        split_skirt_correctives(models)
        rebuild_bun(shell, models['Groom_bun_jules'])
        from portrait_project import project_portrait
        source = Path(__file__).resolve().parents[2] / 'art/hero/sources/jules-portrait-reference.jpeg'
        print('PORTRAIT LANDMARKS', project_portrait(face, shell, identity, eyes, source, (.80, .50, .355), output))
        from hero_polish import hairline_cards
        from female_character import fit_jules_shoulders
        hairline_cards(face, shell, models['Groom_bun_jules'], eyes)
        anatomy = bpy.data.objects.get('Build B anatomy study')
        fit_jules_shoulders(rig, [*meshes, anatomy] if anatomy is not None else meshes, output)
    else:
        from portrait_project import ADE_IMAGE, fit_projection, project_portrait
        from ade_hair import build_ade_hair
        from aaa_hair import rebuild_ade_hair_realism
        from jules_anatomy import fit_ade_wrap
        sources = Path(__file__).resolve().parents[2] / 'art/hero/sources'
        projection = fit_projection(face, shell, eyes, ADE_IMAGE)
        print('PORTRAIT LANDMARKS', project_portrait(face, shell, identity, eyes, sources / 'ade-face-unwrap.jpeg',
                                                     (.72, .44, .30), output, ADE_IMAGE, projection))
        build_ade_hair(face, shell, models['Groom_crop_ade'], eyes, sources / 'ade-face-atlas.jpeg',
                       sources / 'ade-face-unwrap.jpeg', output, projection)
        rebuild_ade_hair_realism(face, shell, models['Groom_crop_ade'], eyes, output)
        fit_ade_wrap(face, eyes)
    face['worldstate_realism'] = 1
