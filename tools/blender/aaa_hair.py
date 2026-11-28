"""AAA realistic layered hair systems for Jules and Ade.

Replaces helmet-like caps, soft-serve beehive coils, floating wire strands, and
flat-top cylinders with anatomically fitted skull caps, feathered hairlines,
and rich multi-layered alpha hair cards optimised for mobile rendering.
"""
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
from hero_groom import eye_centre, mesh_tree, ribbon, tied_freedom
from wardrobe_quality import smooth


def _bell(v, r):
    return math.exp(-(v / r) ** 2)


def generate_hair_card_atlas(output, filename='hair_locks_atlas.png', size=1024):
    """Build a crisp 8-strip multi-strand hair-card RGBA atlas.

    Strips 0-2: dense swept scalp/bun lock ribbons (rich multi-strand texture).
    Strips 3-5: medium layered locks with soft feathery tapered ends.
    Strips 6-7: delicate wispy tendrils and baby-hair hairline fronds.
    """
    strips = 8
    w_px = size // strips
    v = np.arange(size, dtype=np.float32)[:, None] / size
    alpha = np.zeros((size, size), np.float32)
    lum = np.full((size, size), 0.56, np.float32)
    warm = np.zeros((size, size), np.float32)
    rng = np.random.default_rng(314159)

    for s in range(strips):
        col = slice(s * w_px, (s + 1) * w_px)
        u_local = (np.arange(w_px, dtype=np.float32)[None, :] + 0.5) / w_px  # 0..1 across strip
        sa = alpha[:, col]
        sl = lum[:, col]
        sw = warm[:, col]

        if s < 3:
            # Fine silky layered hair lock with softly tapered wispy root AND tip (zero square blocky root ends!).
            n_strands = 84
            base_width = (0.011, 0.024)
            spread = 0.40
            body_env = np.clip((v - 0.04) / 0.18, 0, 1) * np.clip((0.96 - v) / 0.24, 0, 1)
            root_taper = np.clip(v / 0.22, 0.22, 1.0)
            body_u = np.exp(-((u_local - 0.5) / (0.26 * root_taper * (1.0 - 0.35 * v))) ** 2)
            body_strands = 0.5 + 0.5 * np.sin((u_local * 44.0 + 0.30 * np.sin(v * 8.0 + s)) * math.pi)
            body_a = body_env * body_u * (0.34 + 0.40 * body_strands)
            sa[:] = np.maximum(sa, body_a)
            sl[:] = np.where(body_a > 0.05, 0.50 + 0.26 * body_strands, sl)
        elif s < 6:
            # Medium feathered lock: delicate wispy root taper, fine multi-strand wispy tips.
            n_strands = 68
            base_width = (0.010, 0.022)
            spread = 0.41
            body_env = np.clip((v - 0.05) / 0.20, 0, 1) * np.clip((0.92 - v) / 0.30, 0, 1)
            root_taper = np.clip(v / 0.24, 0.20, 1.0)
            body_u = np.exp(-((u_local - 0.5) / (0.22 * root_taper * (1.0 - 0.42 * v))) ** 2)
            body_a = body_env * body_u * 0.30
            sa[:] = np.maximum(sa, body_a)
            sl[:] = np.where(body_a > 0.05, 0.54, sl)
        else:
            # Ultra-fine wispy tendril / feathered baby-hair lock.
            n_strands = 48
            base_width = (0.008, 0.019)
            spread = 0.38

        for _ in range(n_strands):
            root_u = 0.5 + rng.uniform(-spread, spread)
            tip_u = 0.5 + (root_u - 0.5) * rng.uniform(0.30, 0.72) + rng.uniform(-0.08, 0.08)
            wave_amp = rng.uniform(0.015, 0.055)
            wave_freq = rng.uniform(1.8, 4.2)
            phase = rng.uniform(0.0, math.tau)
            v_start = rng.uniform(0.0, 0.08)
            v_end = rng.uniform(0.68, 0.995)
            width = rng.uniform(*base_width) * (1.0 - 0.45 * v)
            center = root_u + (tip_u - root_u) * v + wave_amp * np.sin(v * wave_freq + phase) * np.sin(v * math.pi)
            env = np.clip((v - v_start) / 0.07, 0, 1) * np.clip((v_end - v) / 0.14, 0, 1)
            d = (u_local - center) / np.maximum(width, 0.004)
            fibre = np.exp(-d * d) * env
            tone = rng.uniform(0.46, 1.0) * (0.80 + 0.26 * np.sin(v * math.pi * 0.85))
            w_shift = rng.uniform(-0.05, 0.12)
            mask = fibre > sa * 0.72
            sl[:] = np.where(mask, tone, sl)
            sw[:] = np.where(mask, w_shift, sw)
            np.maximum(sa, fibre, out=sa)

        # Clean zero-alpha border between strips so mipmaps never bleed.
        edge = np.clip(np.minimum(u_local, 1.0 - u_local) / 0.045, 0.0, 1.0)
        sa *= edge

    r = np.clip(lum * (1.04 + warm), 0.0, 1.0)
    g = np.clip(lum * (0.98 + warm * 0.45), 0.0, 1.0)
    b = np.clip(lum * (0.91 - warm * 0.35), 0.0, 1.0)
    rgba = np.stack((r, g, b, np.clip(alpha, 0.0, 1.0)), axis=-1).astype(np.float32)

    img = bpy.data.images.get('hair_locks_atlas')
    if img is None or img.size[0] != size:
        img = bpy.data.images.new('hair_locks_atlas', size, size, alpha=True)
    img.alpha_mode = 'STRAIGHT'
    img.pixels.foreach_set(rgba.ravel())
    path = output / filename
    img.filepath_raw = str(path)
    img.file_format = 'PNG'
    img.save()
    img.pack()
    return img


def _assign_atlas(material, img):
    if material is None or not material.use_nodes:
        return
    for node in material.node_tree.nodes:
        if node.type == 'TEX_IMAGE':
            node.image = img


def _shape_jules_hairline_and_bun(face, shell, eyes, output):
    """Give Jules a soft curved female hairline (feathered alpha) and a lush,
    organic mid-low tousled bun instead of a rigid helmet + beehive swirl."""
    eye = (eyes[0] + eyes[1]) * 0.5
    skin_slot = next(i for i, m in enumerate(face.data.materials) if m.name.startswith('hero_skin_face_'))
    skin = mesh_tree(face.data, skin_slot)
    skull = Vector((0.0, eye.y - 0.068, eye.z + 0.028))

    data = shell.data
    lengths_slot = next((i for i, m in enumerate(data.materials)
                         if m.name.startswith('hero_hair_lengths')), None)
    tie_slots = [i for i, m in enumerate(data.materials) if m.name.startswith('hero_hair_tie')]

    # 1. Subdivide scalp cap cleanly AND remove the clunky floating plastic hair-tie ring
    #    (hair wraps organically around the bun base instead of a floating grey ring!).
    bm = bmesh.new()
    bm.from_mesh(data)
    if tie_slots:
        tie_verts = {v for f in bm.faces if f.material_index in tie_slots for v in f.verts}
        if tie_verts:
            bmesh.ops.delete(bm, geom=list(tie_verts), context='VERTS')
    cap_edges = [e for e in bm.edges if any(f.material_index == 0 for f in e.link_faces)
                 and not any(f.material_index == lengths_slot for f in e.link_faces)]
    if len([v for f in bm.faces if f.material_index == 0 for v in f.verts]) < 3200:
        bmesh.ops.subdivide_edges(bm, edges=cap_edges, cuts=1, use_grid_fill=True)

    # 2. Rebuild the bun core: chic, wider, softer organic tousled bun at crown-back.
    if lengths_slot is not None:
        old_faces = [f for f in bm.faces if f.material_index == lengths_slot]
        old_verts = {v for f in old_faces for v in f.verts}
        deform = bm.verts.layers.deform.verify()
        weights = dict(next(iter(old_verts))[deform]) if old_verts else {shell.vertex_groups['b_head'].index: 1.0}
        uv_layer = bm.loops.layers.uv.get('SurfaceUV') or bm.loops.layers.uv.active
        freedom = bm.loops.layers.uv.get('ClothFreedom')
        bmesh.ops.delete(bm, geom=list(old_verts), context='VERTS')

        # Position the bun gracefully at the upper-back crown (natural chic fuller chignon seated closer to skull).
        bun_center = Vector((0.002, eye.y - 0.138, eye.z + 0.088))
        rings_n, segs_n = 18, 28
        grid = []
        for i in range(rings_n + 1):
            v_t = i / rings_n
            phi = v_t * math.pi  # 0 (bottom) .. pi (top)
            sin_p, cos_p = math.sin(phi), math.cos(phi)
            row = []
            for j in range(segs_n):
                u_t = j / segs_n
                th = u_t * math.tau
                # Soft wider organic oval pillow bun with subtle braided/gathered hair waves.
                twist = 2.0 * th + 3.8 * v_t
                wave = 1.0 + 0.085 * math.cos(3.0 * twist) + 0.055 * math.sin(5.0 * th - 4.0 * v_t)
                rx = 0.060 * wave * (1.0 + 0.06 * math.sin(th + 0.4))
                ry = 0.046 * wave
                rz = 0.039 * wave
                local = Vector((rx * sin_p * math.cos(th),
                                ry * sin_p * math.sin(th),
                                -rz * cos_p))
                # Tilt naturally to follow the back-crown skull slope.
                tilt = math.radians(-30.0)
                ly = local.y * math.cos(tilt) - local.z * math.sin(tilt)
                lz = local.y * math.sin(tilt) + local.z * math.cos(tilt)
                pt = bun_center + Vector((local.x, ly, lz))
                vert = bm.verts.new(pt)
                for g_idx, g_w in weights.items():
                    vert[deform][g_idx] = g_w
                row.append(vert)
            grid.append(row)

        new_faces = []
        for i in range(rings_n):
            for j in range(segs_n):
                jn = (j + 1) % segs_n
                f = bm.faces.new((grid[i][j], grid[i][jn], grid[i + 1][jn], grid[i + 1][j]))
                f.material_index = lengths_slot
                f.smooth = True
                for loop, (ii, jj) in zip(f.loops, ((i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j))):
                    if uv_layer:
                        loop[uv_layer].uv = (jj / segs_n * 2.0, ii / rings_n)
                    if freedom:
                        # Subtle springy bun-outer motion during walking & running (pinned near scalp base).
                        loop[freedom].uv = (0.024 * math.sin(ii / rings_n * math.pi), 1.0)
                new_faces.append(f)
        bmesh.ops.recalc_face_normals(bm, faces=new_faces)

    bm.to_mesh(data)
    bm.free()
    data.update()

    # 3. Smooth the entire scalp hairline boundary (forehead, temples, AND nape) so ZERO
    #    jagged sawtooth edges remain, then seat gently onto the skull with generous alpha feathering!
    cap_verts = {i for p in data.polygons if p.material_index == 0 for i in p.vertices}
    edge_count = {}
    for p in data.polygons:
        if p.material_index == 0:
            for e in p.edge_keys:
                edge_count[e] = edge_count.get(e, 0) + 1
    rim_adj = {}
    for (a, b), c in edge_count.items():
        if c == 1:
            rim_adj.setdefault(a, []).append(b)
            rim_adj.setdefault(b, []).append(a)
    rim_ids = set(rim_adj.keys())
    # Relax the entire hairline contour (forehead + temples + nape) smoothly along the skull surface.
    rim_pos = {i: data.vertices[i].co.copy() for i in rim_ids}
    for _ in range(36):
        nxt = dict(rim_pos)
        for i, nbs in rim_adj.items():
            if len(nbs) == 2:
                mid = (rim_pos[nbs[0]] + rim_pos[nbs[1]]) * 0.5
                p_new = rim_pos[i].lerp(mid, 0.45)
                hit_s, _, _, _ = skin.find_nearest(p_new)
                if hit_s is not None:
                    ray_s = (hit_s - skull).normalized()
                    p_new = hit_s + ray_s * 0.00025
                nxt[i] = p_new
        rim_pos = nxt
    moved_rim = {i: rim_pos[i] - data.vertices[i].co for i in rim_ids}
    for i, d in moved_rim.items():
        data.vertices[i].co += d
    # Carry smoothing softly 2 rings inward so no sliver triangles fold along the rim.
    cap_adj = {}
    for p in data.polygons:
        if p.material_index == 0:
            for a, b in p.edge_keys:
                cap_adj.setdefault(a, set()).add(b)
                cap_adj.setdefault(b, set()).add(a)
    frontier = dict(moved_rim)
    visited_rim = set(moved_rim.keys())
    for weight_r in (0.55, 0.25):
        nxt_f = {}
        for i, d in frontier.items():
            for j in cap_adj.get(i, ()):
                if j not in visited_rim:
                    nxt_f.setdefault(j, []).append(d)
        frontier = {}
        for j, ds in nxt_f.items():
            avg_d = (sum(ds, Vector()) / len(ds)) * weight_r
            data.vertices[j].co += avg_d
            frontier[j] = avg_d
            visited_rim.add(j)
    data.update()

    rim_pts = [data.vertices[i].co.copy() for i in rim_ids]
    kd = KDTree(len(rim_pts))
    for k, co in enumerate(rim_pts):
        kd.insert(co, k)
    kd.balance()

    coverage = {}
    for i in cap_verts:
        p = data.vertices[i].co
        _, _, dist = kd.find(p)
        ray = (p - skull).normalized()
        hit, _, _, _ = skin.ray_cast(p + ray * 0.025, -ray, 0.055)

        # Softly arched natural feminine hairline with generous wispy feathering at temples & nape
        # (eliminates harsh scalloped edge above temples and dark solid nape step!).
        forehead = smooth(eye.y - 0.035, eye.y + 0.015, p.y)
        temple = _bell(abs(p.x) - 0.052, 0.028) * smooth(eye.y - 0.090, eye.y - 0.005, p.y)
        nape = smooth(eye.y - 0.085, eye.y - 0.145, p.y) * smooth(eye.z + 0.030, eye.z - 0.048, p.z)
        feather_w = 0.0135 + 0.0055 * forehead + 0.0065 * temple + 0.0065 * nape
        arch_bias = (-0.0038 * math.exp(-(p.x / 0.030) ** 2) + 0.0020 * temple) * forehead
        wisp = (0.0018 * math.sin(p.x * 380.0 + p.z * 160.0)
                + 0.0011 * math.cos(p.x * 760.0 - p.y * 280.0)
                + 0.0006 * math.sin(p.y * 540.0 + p.z * 490.0))
        cov = smooth(0.0020, feather_w, dist + wisp + arch_bias) ** 1.18
        coverage[i] = cov

        if hit is not None:
            crown_vol = smooth(eye.z + 0.014, eye.z + 0.105, p.z)
            angle = math.atan2(p.x, p.y - (eye.y - 0.06))
            ridge = 0.00065 * math.sin(angle * 48.0 + p.z * 52.0)
            target_gap = 0.00015 + (0.0022 + 0.0034 * crown_vol + ridge) * (cov ** 0.95)
            data.vertices[i].co = hit + ray * target_gap
    data.update()

    # Write smooth alpha coverage into ClothFreedom.y (read by hero_scalp_fade.gdshader).
    density = data.uv_layers.get('ClothFreedom')
    if density is not None:
        for p in data.polygons:
            if p.material_index == 0:
                for li, vi in zip(p.loop_indices, p.vertices):
                    density.data[li].uv.y = min(1.0, max(0.0, coverage.get(vi, 1.0)))
            else:
                for li in p.loop_indices:
                    density.data[li].uv.y = 1.0

    # 4. Bake crisp 1024px directional strand albedo & normal maps onto the scalp cap.
    mat = data.materials[0]
    bsdf = mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = 0.62
    size = 1024
    pos, _, used = raster_uv(shell, size, material_index=0)
    x, y, z = pos[used].T
    bun_y, bun_z = eye.y - 0.148, eye.z + 0.095
    ang = np.arctan2(x, np.maximum(0.015, y - bun_y))
    dist_b = np.hypot(x, y - bun_y)
    part_x = -0.010 + 0.036 * (eye.y - y)
    part_line = np.exp(-((x - part_x) / 0.0018) ** 2) * falloff(eye.y - 0.055, eye.y + 0.005, y)
    s1 = ang * 360.0 + 3.6 * np.sin(dist_b * 92.0 + z * 48.0)
    s2 = ang * 720.0 - 2.4 * np.cos(z * 135.0 - x * 78.0)
    s3 = ang * 1180.0 + 1.5 * np.sin(dist_b * 185.0 - z * 98.0)
    clump = np.sin(ang * 48.0 + 0.9 * np.sin(dist_b * 44.0))
    fibres = 0.42 * np.sin(s1) + 0.28 * np.sin(s2) + 0.14 * np.sin(s3) + 0.16 * clump
    # Richer chestnut-espresso tonal range so swept strands stay readable on shaded side & night!
    shade = np.clip(0.74 + 0.24 * fibres - 0.07 * part_line, 0.44, 0.99)
    warm_var = 0.055 * np.sin(ang * 19.0 + dist_b * 35.0)
    albedo = np.full((size, size, 3), 0.72, np.float32)
    albedo[used] = np.stack((
        np.clip(shade * (1.04 + warm_var), 0.0, 1.0),
        np.clip(shade * (0.96 + warm_var * 0.4), 0.0, 1.0),
        np.clip(shade * (0.89 - warm_var * 0.3), 0.0, 1.0),
    ), axis=-1)

    colour_node = bsdf.inputs['Base Color'].links[0].from_node
    colour_node.image = packed_image(output / 'hair_bun_albedo.png', _dilate(albedo, used, 8))

    height = np.zeros(used.shape, np.float32)
    height[used] = 0.00030 * fibres + 0.00018 * clump
    h = _dilate(height[..., None], used, 5)[..., 0]
    p_d = _dilate(pos, used, 4)
    du = np.maximum(np.linalg.norm(np.roll(p_d, 1, 1) - np.roll(p_d, -1, 1), axis=-1), 0.00035)
    dv = np.maximum(np.linalg.norm(np.roll(p_d, 1, 0) - np.roll(p_d, -1, 0), axis=-1), 0.00035)
    gx = (np.roll(h, 1, 1) - np.roll(h, -1, 1)) / du
    gy = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) / dv
    nrm = np.stack((np.clip(gx, -0.86, 0.86), np.clip(gy, -0.86, 0.86), np.ones_like(h)), axis=-1)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-6)
    if bsdf.inputs['Normal'].links:
        nmap_node = bsdf.inputs['Normal'].links[0].from_node
        nmap_node.inputs['Strength'].default_value = 0.90
        if nmap_node.inputs['Color'].links:
            nmap_node.inputs['Color'].links[0].from_node.image = packed_image(
                output / 'hair_bun_normal.png', _dilate(nrm * 0.5 + 0.5, used, 8), normal=True)

    return Vector((0.002, eye.y - 0.138, eye.z + 0.088)), skull


def rebuild_jules_hair(face, shell, groom, eyes, output):
    """Build a premium, layered, natural hair-card updo + soft face-framing tendrils for Jules."""
    eye = (eyes[0] + eyes[1]) * 0.5
    skin_slot = next(i for i, m in enumerate(face.data.materials) if m.name.startswith('hero_skin_face_'))
    skin = mesh_tree(face.data, skin_slot)

    atlas_img = generate_hair_card_atlas(output, 'hair_locks_atlas.png', size=1024)
    bun_center, skull = _shape_jules_hairline_and_bun(face, shell, eyes, output)

    lengths_slot = next((i for i, m in enumerate(shell.data.materials)
                         if m.name.startswith('hero_hair_lengths')), None)
    cap_tree = mesh_tree(shell.data, 0)
    bun_tree = mesh_tree(shell.data, lengths_slot) if lengths_slot is not None else cap_tree

    # Clear old groom geometry cleanly and build all 4 real hair-card layers from scratch.
    batch = ([], [], [])
    motion_vals = []
    rng = random.Random(202607)

    def add_ribbon_with_motion(centres, normals, width, strip, freedom_base=0.0, opacity=0.96):
        before = len(batch[0])
        ribbon(batch, centres, normals, width, strip)
        added = len(batch[0]) - before
        n_rows = added // 2
        for r in range(n_rows):
            t = r / max(1, n_rows - 1)
            f_val = freedom_base * (t ** 1.4)
            motion_vals.extend([(f_val, opacity), (f_val, opacity)])

    # --- LAYER 1: Swept layered scalp locks (155 overlapping tapered ribbons) ---
    # Flowing gracefully from forehead, temples, crown, sides and nape into the bun.
    cap_verts = [v.co.copy() for p in shell.data.polygons if p.material_index == 0
                 for v in (shell.data.vertices[i] for i in p.vertices)]
    edge_count = {}
    for p in shell.data.polygons:
        if p.material_index == 0:
            for e in p.edge_keys:
                edge_count[e] = edge_count.get(e, 0) + 1
    rim_pts = [shell.data.vertices[i].co.copy() for e, c in edge_count.items() if c == 1 for i in e]
    rim_kd = KDTree(len(rim_pts)) if rim_pts else None
    if rim_kd is not None:
        for k_r, pt_r in enumerate(rim_pts):
            rim_kd.insert(pt_r, k_r)
        rim_kd.balance()

    def rim_dist(pt):
        if rim_kd is None:
            return 1.0
        return rim_kd.find(pt)[2]

    # Sample evenly around the scalp (golden angle spiral strictly INSIDE the dense scalp cap,
    # NEVER starting alpha-scissored cards out in the feathered hairline rim -> ZERO black comb-teeth!).
    for idx in range(165):
        u = idx / 165.0
        az = idx * 2.39996323
        elev = -0.15 + 1.15 * (u ** 0.72)
        d_ray = Vector((math.cos(elev) * math.sin(az), math.cos(elev) * math.cos(az), math.sin(elev))).normalized()
        hit, nrm, _, _ = cap_tree.ray_cast(skull + d_ray * 0.25, -d_ray, 0.25)
        if hit is None or nrm.dot(d_ray) < 0.15:
            continue
        if hit.z < eye.z - 0.048 and hit.y > eye.y - 0.085:
            continue
        # Strictly keep Layer 1 roots >= 18mm inside the feathered hairline (forehead, temples & nape)!
        if rim_dist(hit) < 0.018:
            continue

        # Sweep smoothly and flush toward the bun across the scalp (zero sticking-up shiny strips!).
        length = rng.uniform(0.044, 0.078)
        width = rng.uniform(0.0068, 0.0112)
        lift_amp = rng.uniform(0.0005, 0.0014)
        steps = 8
        centres, normals = [], []
        cur = hit.copy()
        for step in range(steps):
            t = step / (steps - 1)
            to_bun = bun_center - cur
            tang = to_bun - nrm * to_bun.dot(nrm)
            if tang.length < 1e-4:
                break
            tang.normalize()
            ray_d = (cur - skull).normalized()
            surf_hit, surf_n, _, _ = cap_tree.ray_cast(skull + ray_d * 0.28, -ray_d, 0.28)
            if surf_hit is None:
                surf_hit, surf_n, _, _ = bun_tree.ray_cast(cur + nrm * 0.04, -nrm, 0.08)
            if surf_hit is None:
                break
            lift = 0.00025 + lift_amp * math.sin(math.pi * t) + 0.0004 * t
            centres.append(surf_hit + surf_n * lift)
            normals.append(surf_n)
            cur = surf_hit + tang * (length / (steps - 1))
            nrm = surf_n
        if len(centres) >= 5:
            add_ribbon_with_motion(centres, normals, width, idx % 6, freedom_base=0.0, opacity=0.92)

    # --- LAYER 2: Recessed swept crown cards (strictly >= 18mm INSIDE dense scalp -> ZERO forehead/nape teeth!) ---
    sorted_rim = sorted(rim_pts, key=lambda q: math.atan2(q.x, q.y - (eye.y - 0.07)))
    picked_rim = []
    for co in sorted_rim:
        if co.z < eye.z - 0.055:
            continue
        if all((co - prev).length > 0.0046 for prev in picked_rim[-10:]):
            picked_rim.append(co)

    for idx, co in enumerate(picked_rim):
        hit, nrm, _, _ = skin.find_nearest(co)
        if hit is None:
            continue
        to_bun = bun_center - hit
        tang = (to_bun - nrm * to_bun.dot(nrm))
        if tang.length < 1e-4:
            continue
        tang.normalize()
        # Start strictly 17-24mm INSIDE the feathered hairline so cards sit over 100% opaque scalp
        # and NEVER overhang the forehead, temples, or nape as blocky comb-teeth!
        is_front = smooth(eye.y - 0.045, eye.y + 0.005, hit.y)
        inset = rng.uniform(0.0185, 0.0255) if is_front > 0.25 else rng.uniform(0.0155, 0.0220)
        start = hit + tang * inset
        if rim_dist(start) < 0.0145:
            continue
        length = rng.uniform(0.036, 0.056)
        width = rng.uniform(0.0078, 0.0125)
        steps = 7
        centres, normals = [], []
        cur = start
        for step in range(steps):
            t = step / (steps - 1)
            on_cap = cap_tree.find_nearest(cur)
            on_skin = skin.find_nearest(cur)
            if on_cap[0] is not None and (on_cap[0] - cur).length < 0.010:
                base, n = on_cap[0], on_cap[1]
            elif on_skin[0] is not None:
                base, n = on_skin[0], on_skin[1]
            else:
                break
            lift = 0.00025 + 0.0011 * math.sin(math.pi * t) + 0.0004 * t
            centres.append(base + n * lift)
            normals.append(n)
            to_b = bun_center - base
            tang = (to_b - n * to_b.dot(n)).normalized()
            cur = base + tang * (length / (steps - 1))
        if len(centres) >= 4:
            strip_id = 3 + (idx % 4)
            add_ribbon_with_motion(centres, normals, width, strip_id, freedom_base=0.0, opacity=0.90)

    # --- LAYER 3: Lush layered bun wrap ribbons & wispy silhouette loops (135 cards) ---
    for idx in range(135):
        phi0 = idx * 2.39996323
        elev0 = rng.uniform(-0.45, 0.72)
        sweep_dir = 1.0 if idx % 5 != 0 else -1.0
        arc_len = rng.uniform(1.1, 2.3) * sweep_dir
        width = rng.uniform(0.0080, 0.0160)
        loft = rng.uniform(0.0014, 0.0048)
        if idx >= 102:
            # Outer wispy silhouette-breaking loops around the tousled bun with subtle walk/run sway.
            loft = rng.uniform(0.0040, 0.0084)
            width = rng.uniform(0.0065, 0.0125)
        steps = 9
        centres, normals = [], []
        for step in range(steps):
            t = step / (steps - 1)
            ang = phi0 + arc_len * t
            el = elev0 + 0.35 * math.sin(t * math.pi + phi0) - 0.18 * t
            d_ray = Vector((math.cos(el) * math.cos(ang),
                            math.cos(el) * math.sin(ang),
                            math.sin(el))).normalized()
            hit, nrm, _, _ = bun_tree.ray_cast(bun_center + d_ray * 0.14, -d_ray, 0.18)
            if hit is None or nrm.dot(d_ray) < 0.05:
                break
            lift = 0.0006 + loft * math.sin(math.pi * t) + 0.0009 * t
            centres.append(hit + nrm * lift)
            normals.append(nrm)
        if len(centres) >= 5:
            strip = (idx % 6) if idx < 102 else (5 + (idx % 3))
            add_ribbon_with_motion(centres, normals, width, strip, freedom_base=0.034 if idx >= 102 else 0.020, opacity=0.96)

    # --- LAYER 4: Soft tucked temple-sweep locks (strictly behind the hairline, ZERO blotches on face!) ---
    for sign in (-1, 1):
        for k in range(5):
            z0 = eye.z + 0.042 + 0.009 * k
            y0 = eye.y - 0.044 - 0.005 * k
            x0 = sign * (0.054 + 0.003 * math.sin(k * 0.7))
            start_hit, start_n, _, _ = cap_tree.find_nearest(Vector((x0, y0, z0)))
            if start_hit is None or rim_dist(start_hit) < 0.016 or start_hit.z < eye.z + 0.018:
                continue
            length = rng.uniform(0.042, 0.068)
            width = rng.uniform(0.0095, 0.0145)
            steps = 8
            centres, normals = [], []
            cur = start_hit.copy()
            n_cur = start_n
            for step in range(steps):
                t = step / (steps - 1)
                on_cap = cap_tree.find_nearest(cur)
                on_skin = skin.find_nearest(cur)
                if on_cap[0] is not None and (on_cap[0] - cur).length < 0.012 and t > 0.15:
                    base, n_cur = on_cap[0], on_cap[1]
                elif on_skin[0] is not None:
                    base, n_cur = on_skin[0], on_skin[1]
                else:
                    break
                lift = 0.0005 + 0.0018 * math.sin(math.pi * t) + 0.0006 * t
                centres.append(base + n_cur * lift)
                normals.append(n_cur)
                to_b = bun_center - base
                tang = (to_b - n_cur * to_b.dot(n_cur))
                if tang.length < 1e-4:
                    break
                tang.normalize()
                cur = base + tang * (length / (steps - 1))
            if len(centres) >= 5:
                add_ribbon_with_motion(centres, normals, width, 1 + (k % 4), freedom_base=0.0, opacity=0.96)

    # Write final Groom_bun_jules mesh cleanly.
    points, polygons, texels = batch
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    uv_layer = bm.loops.layers.uv.new('SurfaceUV')
    freedom_layer = bm.loops.layers.uv.new('ClothFreedom')
    head_idx = groom.vertex_groups['b_head'].index
    verts = [bm.verts.new(p) for p in points]
    for v in verts:
        v[deform][head_idx] = 1.0
    for poly_ids in polygons:
        try:
            f = bm.faces.new([verts[i] for i in poly_ids])
        except ValueError:
            continue
        f.smooth = True
        for loop, vi in zip(f.loops, poly_ids):
            loop[uv_layer].uv = texels[vi]
            loop[freedom_layer].uv = motion_vals[vi]
    bm.to_mesh(groom.data)
    bm.free()
    groom.data.uv_layers.active_index = 0
    groom.data.update()
    _assign_atlas(groom.data.materials[0], atlas_img)
    print(f'AAA JULES HAIR: cap_verts={len(shell.data.vertices)} groom_verts={len(groom.data.vertices)} groom_faces={len(groom.data.polygons)}', flush=True)


def _ade_curl_card_atlas(output, size=1024, strips=8):
    """Crisp overlapping 3C/4A micro-coil lock clusters for Ade's textured curly crop."""
    rng = np.random.default_rng(7719)
    img = np.zeros((size, size, 4), np.float32)
    w_px = size // strips
    yy, xx = np.mgrid[0:size, 0:w_px]
    u = (xx + 0.5) / w_px
    v = (yy + 0.5) / size

    for s in range(strips):
        patch = img[:, s * w_px:(s + 1) * w_px]
        # Soft interlocking curly base at roots dissolving into fine individual S/C micro-coils.
        root_mass = np.exp(-((u - 0.5) / 0.34) ** 2) * np.clip(v / 0.14, 0, 1) * np.clip((0.76 - v) / 0.48, 0, 1)
        coil_tex = 0.5 + 0.5 * np.sin((u * 18.0 + np.sin(v * 28.0 + s)) * math.pi) * np.cos((v * 24.0 - u * 11.0) * math.pi)
        base_a = root_mass * (0.36 + 0.42 * coil_tex)
        patch[..., 3] = np.maximum(patch[..., 3], base_a)
        lit_base = 0.115 + 0.080 * coil_tex
        patch[..., 0] = np.where(base_a > 0.05, lit_base * 1.12, patch[..., 0])
        patch[..., 1] = np.where(base_a > 0.05, lit_base * 0.91, patch[..., 1])
        patch[..., 2] = np.where(base_a > 0.05, lit_base * 0.74, patch[..., 2])

        for _ in range(74):
            cv = rng.uniform(0.06, 0.92)
            spread = 0.32 * (1.0 - 0.30 * cv)
            cu = 0.5 + rng.uniform(-spread, spread)
            rad_u = rng.uniform(0.09, 0.17) * (1.08 - 0.28 * cv)
            rad_v = rad_u * (w_px / size) * rng.uniform(0.85, 1.30)
            du = (u - cu) / rad_u
            dv = (v - cv) / rad_v
            r = np.hypot(du, dv)
            ang = np.arctan2(dv, du)
            start = rng.uniform(0, math.tau)
            sweep = rng.uniform(3.2, 4.9)
            thick = rng.uniform(0.22, 0.36)
            ring = np.exp(-((r - 1.0) / thick) ** 2)
            arc = (np.mod(ang - start, math.tau) < sweep).astype(np.float32)
            m = ring * arc * np.clip((0.98 - cv) / 0.18, 0.35, 1.0)
            tone = rng.uniform(0.105, 0.205) * (0.86 + 0.24 * cv)
            mask = m > patch[..., 3] * 0.72
            patch[..., 0] = np.where(mask, tone * 1.12, patch[..., 0])
            patch[..., 1] = np.where(mask, tone * 0.90, patch[..., 1])
            patch[..., 2] = np.where(mask, tone * 0.74, patch[..., 2])
            patch[..., 3] = np.maximum(patch[..., 3], m)

        edge = np.clip(np.minimum(u, 1.0 - u) / 0.06, 0.0, 1.0)
        patch[..., 3] *= edge

    out_path = output / 'hair_ade_coils.png'
    im = bpy.data.images.get('hair_ade_coils')
    if im is None or im.size[0] != size:
        im = bpy.data.images.new('hair_ade_coils', size, size, alpha=True)
    im.alpha_mode = 'STRAIGHT'
    im.pixels.foreach_set(img[::-1].ravel())
    im.filepath_raw = str(out_path)
    im.file_format = 'PNG'
    img_arr = None
    im.save()
    im.pack()
    return im


def rebuild_ade_hair_realism(face, shell, groom, eyes, output):
    """Round Ade's curly crop with a razor-clean organic barber lineup (no wavy step
    or shadow bar), true velvety 3-zone stubble skin-fade around sides & back, and
    tightly nestled interlocking micro-coil cards (ZERO flat dark confetti flecks!)."""
    eye = (eyes[0] + eyes[1]) * 0.5
    skin_slot = next(i for i, m in enumerate(face.data.materials) if m.name.startswith('hero_skin_face_'))
    skin = mesh_tree(face.data, skin_slot)
    skull = eye + Vector((0.0, -0.072, 0.026))
    data = shell.data

    # 0. Subdivide frontal hairline & fade zone cleanly so lineup and taper transitions are silky smooth.
    if len(data.vertices) < 4200:
        bm_s = bmesh.new()
        bm_s.from_mesh(data)
        front_edges = [
            e for e in bm_s.edges
            if any(v.co.z > eye.z - 0.015 for v in e.verts)
        ]
        if front_edges:
            bmesh.ops.subdivide_edges(bm_s, edges=front_edges, cuts=1, use_grid_fill=True)
            bm_s.to_mesh(data)
            data.update()
        bm_s.free()

    # 1. Reshape crown silhouette: natural rounded athletic curly crop + smooth 3-zone barber taper fade.
    rng = random.Random(9941)
    crown_pts = [v.co.copy() for v in data.vertices if v.co.z > eye.z + 0.045]
    anchors = rng.sample(crown_pts, min(580, len(crown_pts))) if crown_pts else []
    kd = KDTree(len(anchors))
    for k, pt in enumerate(anchors):
        kd.insert(pt, k)
    kd.balance()

    coverage = {}
    crown_weight = {}
    for v in data.vertices:
        p = v.co
        ray = (p - skull).normalized()
        hit, _, _, _ = skin.ray_cast(p + ray * 0.022, -ray, 0.050)
        if hit is None:
            coverage[v.index] = 0.0
            crown_weight[v.index] = 0.0
            continue

        # Seamless 95mm velvety barber taper fade around temples, above ears & occipital nape.
        front = smooth(eye.y - 0.082, eye.y - 0.010, p.y)
        side = smooth(0.032, 0.068, abs(p.x))
        back = smooth(eye.y - 0.064, eye.y - 0.148, p.y)
        fade_lo = eye.z - 0.048 + 0.050 * front - 0.030 * back
        fade_hi = eye.z + 0.072 + 0.008 * front - 0.016 * back

        fade = smooth(fade_lo, fade_hi, p.z) ** 1.12
        # Natural barber lineup across the forehead with subtle micro-follicle edge breakup (never a hard ruler stamp!).
        lineup_wisp = 0.0007 * math.sin(p.x * 420.0) + 0.0004 * math.cos(p.x * 890.0)
        lineup_z = eye.z + 0.0495 + 0.0014 * ((abs(p.x) / 0.048) ** 2) + lineup_wisp
        forehead_cut = smooth(lineup_z - 0.0042, lineup_z + 0.0046, p.z)
        in_front = smooth(0.058, 0.038, abs(p.x)) * smooth(eye.y - 0.032, eye.y + 0.004, p.y)
        cov = fade * (1.0 - in_front) + forehead_cut * in_front
        cov *= smooth(eye.z - 0.075, eye.z - 0.024, p.z)
        coverage[v.index] = cov

        # Softly rounded tapered athletic curly dome with multi-scale individual curl clump variation!
        top_dome = smooth(eye.z + 0.050, eye.z + 0.098, p.z)
        corner_round = 1.0 - 0.44 * side * smooth(eye.z + 0.050, eye.z + 0.096, p.z) * (1.0 - smooth(eye.z + 0.098, eye.z + 0.128, p.z))
        clump = 0.0
        if anchors and cov > 0.50:
            _, ci, cd = kd.find(p)
            micro = 0.5 + 0.5 * math.sin(p.x * 520.0 + p.y * 470.0 + p.z * 390.0)
            clump = max(0.0, 1.0 - cd / 0.0092) ** 1.30 * (0.30 + 0.70 * math.sin(ci * 2.17) ** 2) + 0.25 * micro
        # Hairline lip stays flush (0.3mm) rising smoothly over 14mm into natural 8.6mm curly crown!
        front_flush = 1.0 - 0.65 * in_front * (1.0 - smooth(lineup_z, lineup_z + 0.016, p.z))
        crown_h = (0.0010 + 0.0080 * top_dome * corner_round + 0.0028 * clump) * (cov ** 1.35) * front_flush
        lift = 0.00025 + crown_h
        v.co = hit + ray * lift
        crown_weight[v.index] = top_dome * cov

    data.update()

    # Write smooth fade coverage into ClothFreedom.y.
    density = data.uv_layers.get('ClothFreedom')
    if density is not None:
        for loop in data.loops:
            density.data[loop.index].uv.y = min(1.0, max(0.0, coverage.get(loop.vertex_index, 0.0)))

    # 2. Bake 1024px high-definition curly-top + velvety micro-stubble fade albedo & normal maps!
    mat = data.materials[0]
    bsdf = mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = 0.62
    size = 1024
    pos, nrm_r, used = raster_uv(shell, size, material_index=0)
    x, y, z = pos[used].T
    c1 = np.sin(x * 460.0 + np.sin(y * 420.0 + z * 310.0) * 1.9) * np.cos(y * 440.0 - z * 360.0)
    c2 = np.sin(x * 890.0 - z * 780.0 + y * 590.0) * np.cos(y * 820.0 + x * 690.0)
    # Realistic fine stippled barber stubble follicles in the fade zone (tiny individual hair dots!).
    st_hash = np.sin(np.floor(x * 1650.0) * 127.1 + np.floor(y * 1650.0) * 311.7 + np.floor(z * 1650.0) * 74.7)
    follicle = np.mod(np.abs(st_hash) * 43758.5453, 1.0)
    stubble_dots = (follicle > 0.46).astype(np.float32) * (0.55 + 0.45 * np.sin(x * 2400.0 + z * 2100.0))

    front_r = falloff(eye.y - 0.082, eye.y - 0.012, y)
    back_r = falloff(eye.y - 0.064, eye.y - 0.148, y)
    f_lo = eye.z - 0.044 + 0.052 * front_r - 0.028 * back_r
    f_hi = eye.z + 0.062 + 0.008 * front_r - 0.016 * back_r
    t_fade = np.clip((z - f_lo) / np.maximum(f_hi - f_lo, 0.01), 0.0, 1.0) ** 1.15
    # Keep dense crisp curls up to the clean barber forehead lineup.
    lineup_zr = eye.z + 0.0495 + 0.0014 * ((np.abs(x) / 0.048) ** 2)
    in_fr_r = falloff(0.058, 0.040, np.abs(x)) * falloff(eye.y - 0.032, eye.y + 0.004, y)
    t_curl = t_fade * (1.0 - in_fr_r) + falloff(lineup_zr - 0.0025, lineup_zr + 0.0040, z) * in_fr_r

    # Rich warm espresso-black curls on top with stronger curl-ridge contrast (readable in shade & night!)
    curl_val = 0.115 + 0.092 * (0.5 + 0.5 * c1) + 0.058 * (0.5 + 0.5 * c2)
    fade_val = 0.28 - 0.14 * t_curl - 0.115 * stubble_dots * (1.0 - 0.55 * t_curl)
    val = fade_val * (1.0 - t_curl) + curl_val * t_curl
    col = np.full((size, size, 3), 0.13, np.float32)
    col[used] = np.stack((val * 1.15, val * 0.90, val * 0.74), axis=-1)
    colour_node = bsdf.inputs['Base Color'].links[0].from_node
    colour_node.image = packed_image(output / 'hair_ade_crop_albedo.png', _dilate(col, used, 8))

    height = np.zeros(used.shape, np.float32)
    height[used] = (0.00058 * c1 + 0.00032 * c2) * t_curl + 0.00020 * stubble_dots * (1.0 - t_curl)
    h = _dilate(height[..., None], used, 5)[..., 0]
    p_d = _dilate(pos, used, 4)
    du = np.maximum(np.linalg.norm(np.roll(p_d, 1, 1) - np.roll(p_d, -1, 1), axis=-1), 0.00035)
    dv = np.maximum(np.linalg.norm(np.roll(p_d, 1, 0) - np.roll(p_d, -1, 0), axis=-1), 0.00035)
    gx = (np.roll(h, 1, 1) - np.roll(h, -1, 1)) / du
    gy = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) / dv
    nmap = np.stack((np.clip(gx, -0.80, 0.80), np.clip(gy, -0.80, 0.80), np.ones_like(h)), axis=-1)
    nmap /= np.maximum(np.linalg.norm(nmap, axis=-1, keepdims=True), 1e-6)
    if bsdf.inputs['Normal'].links:
        nmap_node = bsdf.inputs['Normal'].links[0].from_node
        nmap_node.inputs['Strength'].default_value = 0.84
        if nmap_node.inputs['Color'].links:
            nmap_node.inputs['Color'].links[0].from_node.image = packed_image(
                output / 'hair_ade_crop_normal.png', _dilate(nmap * 0.5 + 0.5, used, 8), normal=True)

    # 3. Tightly nestled interlocking micro-coil cards hugging the crown contour (ZERO floating confetti chips!).
    cap_tree = BVHTree.FromPolygons([v.co for v in data.vertices], [tuple(p.vertices) for p in data.polygons])
    coil_img = _ade_curl_card_atlas(output)
    _assign_atlas(groom.data.materials[0], coil_img)

    candidates = [
        v.co.copy() for v in data.vertices
        if coverage.get(v.index, 0.0) > 0.88
        and v.co.z > (eye.z + 0.068 if v.co.y > eye.y - 0.034 else eye.z + 0.060)
    ]
    rng.shuffle(candidates)

    gbm = bmesh.new()
    uv_l = gbm.loops.layers.uv.new('SurfaceUV')
    fr_l = gbm.loops.layers.uv.new('ClothFreedom')
    deform = gbm.verts.layers.deform.verify()
    head_idx = groom.vertex_groups['b_head'].index

    placed = []
    for root in candidates:
        if len(placed) >= 520:
            break
        if any((root - q).length < 0.0052 for q in placed[-36:]):
            continue
        loc, n, _, _ = cap_tree.find_nearest(root)
        if loc is None:
            continue
        placed.append(loc)
        rand_v = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 0.6)))
        tang = n.cross(rand_v)
        if tang.length < 1e-4:
            continue
        tang.normalize()
        if loc.y > eye.y - 0.032 and tang.y > 0.0:
            tang = -tang
        side = n.cross(tang).normalized()
        is_top = smooth(eye.z + 0.064, eye.z + 0.100, loc.z)
        length = rng.uniform(0.0072, 0.0118) * (0.72 + 0.28 * is_top)
        width = rng.uniform(0.0058, 0.0092) * (0.76 + 0.24 * is_top)
        # Sculpted interlocking curl loops that break the crown silhouette naturally without confetti spikes.
        arch = rng.uniform(0.0009, 0.0020) * (0.60 + 0.40 * is_top)

        p0 = loc - n * 0.0008
        p1 = loc + tang * (length * 0.50) + n * arch
        p2 = loc + tang * length - n * 0.0002

        rows = []
        for k, (pc, w_sc) in enumerate(((p0, 0.90), (p1, 1.0), (p2, 0.68))):
            v_l = gbm.verts.new(pc - side * (width * 0.5 * w_sc))
            v_r = gbm.verts.new(pc + side * (width * 0.5 * w_sc))
            v_l[deform][head_idx] = 1.0
            v_r[deform][head_idx] = 1.0
            rows.append((v_l, v_r))
        strip = rng.randrange(8)
        for k, (a, b) in enumerate(zip(rows, rows[1:])):
            f = gbm.faces.new((a[0], a[1], b[1], b[0]))
            f.smooth = True
            for loop, sx, sy in zip(f.loops, (0, 1, 1, 0), (k * 0.5, k * 0.5, (k + 1) * 0.5, (k + 1) * 0.5)):
                loop[uv_l].uv = ((strip + 0.06 + 0.88 * sx) / 8.0, sy)
                loop[fr_l].uv = (0.0, 0.94)

    gbm.to_mesh(groom.data)
    gbm.free()
    groom.data.uv_layers.active_index = 0
    groom.data.update()
    print(f'AAA ADE HAIR: cap_verts={len(data.vertices)} groom_verts={len(groom.data.vertices)} groom_faces={len(groom.data.polygons)}', flush=True)
