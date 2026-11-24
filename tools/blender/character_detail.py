"""Close-up anatomy and groom detail for the WorldState Blender export.

Loaded by build_character.py after the garment kit supplies the UV baker.
"""

import zlib


def stable_seed(*parts):
    return zlib.crc32(':'.join(parts).encode())


def eye_material():
    """A shared high-detail ocular atlas, with iris tint applied in the game shader."""
    n = 512
    y, x = (np.mgrid[0:n, 0:n] + .5) / n * 2 - 1
    r = np.hypot(x, y)
    angle = np.arctan2(y, x)
    iris_radius = .485
    iris = r / iris_radius
    # Organic fibrous iris stroma: multi-frequency radial trabeculae, subtle collarette, deep crypts, soft dark limbal ring.
    swirl = 0.08 * np.sin(angle * 7 + r * 6) + 0.04 * np.cos(angle * 13 - r * 9)
    a_w = angle + swirl * np.clip(iris, 0, 1)
    fibres = (.095 * np.sin(54 * a_w + 5 * r + 1.2 * np.sin(a_w * 11) * iris)
              + .062 * np.sin(113 * a_w - 11 * r + .5 * np.sin(a_w * 19))
              + .038 * np.sin(187 * a_w + 9 * r))
    # Warm golden-amber collarette ring (subtle, NOT a bright white starburst!).
    collar = .14 * np.exp(-((iris - .44) / .14) ** 2)
    crypt = np.maximum(0, np.sin(23 * a_w + 5 * r)) * np.exp(-((iris - .60) / .16) ** 2)
    furrow = .045 * np.sin(iris * 26.0) * np.clip((iris - .50) / .45, 0, 1)
    rim = np.clip((iris - .70) / .30, 0, 1) ** 1.45
    pigment = np.clip(.68 + fibres - .16 * crypt + collar - furrow - .54 * rim, .14, .95)
    # Natural moist ivory sclera: gently shaded and subtly pinker toward peripheral corners.
    whites = np.clip((r - .46) * 1.55, 0, .85)
    corner_pink = np.clip((r - .56) * 1.8, 0, 1.0)
    vessels = np.maximum(0, np.sin(angle * 15 + np.sin(r * 21) + angle * r * 9)) ** 42 * whites
    albedo = np.stack([.86 - .10 * whites + .035 * corner_pink,
                       .83 - .14 * whites - .025 * corner_pink - .028 * vessels,
                       .79 - .16 * whites - .038 * corner_pink - .036 * vessels], -1)
    iris_col = pigment[..., None] * np.array([1.0, .93, .85]) + collar[..., None] * np.array([.11, .065, .02])
    iris_mask = np.clip((iris_radius - r) / .028, 0, 1)
    albedo = albedo * (1 - iris_mask[..., None]) + np.clip(iris_col, 0, 1) * iris_mask[..., None]
    pupil = np.clip((.182 - r) / .016, 0, 1)
    albedo = albedo * (1 - pupil[..., None]) + np.array([.008, .007, .008]) * pupil[..., None]
    return material('hero_eye', (1, 1, 1), .10, _save('ocular_albedo', albedo))


def map_eye(ob):
    """Project continuous iris/sclera UVs onto an anatomical eyeball with parallel natural gaze."""
    centre = sum((v.co for v in ob.data.vertices), Vector()) / len(ob.data.vertices)
    # True straight-ahead optical axis (eliminates cross-eyed / upward stare).
    forward = Vector((0.0, 1.0, -0.008)).normalized()
    right = forward.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(forward).normalized()
    layer = ob.data.uv_layers[0]
    for loop in ob.data.loops:
        d = (ob.data.vertices[loop.vertex_index].co - centre).normalized()
        layer.data[loop.index].uv = (.5 + .49 * d.dot(right), .5 + .49 * d.dot(up))


def blink_shape(face, lashes, eyes, skin):
    """Close the lids across the eye aperture. Lash and lid use one field."""
    limits = []
    for centre, radius, tips in zip(eyes[0], eyes[1], lashes):
        inner = min(tips, key=lambda p: p.x)
        outer = max(tips, key=lambda p: p.x)
        limits.append((centre, radius, inner, outer, max(p.z for p in tips)))
    # Join first so the lash and skin can share the same blend shape name.
    face.shape_key_add(name='Basis')
    key = face.shape_key_add(name='Blink')
    moving = {idx for poly in face.data.polygons
              if face.data.materials[poly.material_index] in (skin, LID_MATERIAL) for idx in poly.vertices}
    for idx in moving:
        p = face.data.vertices[idx].co
        closed = key.data[idx]
        for centre, radius, inner, outer, peak in limits:
            span = outer.x - inner.x
            if span < .01 or not inner.x - .001 < p.x < outer.x + .001:
                continue
            if p.y < centre.y + radius * .33:
                continue
            s = max(0.0, min(1.0, (p.x - inner.x) / span))
            arc = math.sin(math.pi * s) ** .75
            seam = inner.z * (1 - s) + outer.z * s - .0028 * arc
            window = max(.005, peak - seam)
            height = p.z - seam
            if not -.007 < height < window + .012:
                continue
            upper = max(0.0, min(1.0, (window + .011 - height) / .011))
            lower = max(0.0, min(1.0, (height + .007) / .007))
            amount = min(1.0, arc * 2.4) * min(upper, lower)
            closed.co.z -= height * amount * .98
            # Lids slide along the eye instead of cutting a chord through it.
            ey = centre.y + math.sqrt(max(0.0, radius ** 2 - (p.x - centre.x) ** 2
                                            - (closed.co.z - centre.z) ** 2))
            closed.co.y += max(0.0, ey + .0008 - p.y) * amount


LOCKS = [(0.000, .146), (.151, .225), (.232, .376), (.379, .514),
         (.527, .641), (.656, .752), (.754, .892), (.893, .999)]
HAIR_CARDS = {
    'buzz': (20, .005, .0016), 'crop': (235, .037, .0048), 'fade': (235, .037, .005),
    'curls': (235, .028, .008), 'pixie': (230, .045, .006),
    'ponytail': (144, .043, .006), 'bun': (130, .036, .006),
}


def make_lock_material():
    image = bpy.data.images.load(str(SRC / 'hair_locks.png'))
    image.alpha_mode = 'STRAIGHT'
    image.scale(1024, 1024)
    w, h = image.size
    pixels = np.empty(w * h * 4, np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(h, w, 4)
    a = pixels[..., 3].copy()
    lum = pixels[..., :3] @ np.array([.2126, .7152, .0722])
    # Neutralize the brown dye so the same groom supports silver and blonde.
    # Discard thin background fringes and give mips neutral RGB in empty texels.
    pixels[..., :3] = np.where(a > .36, np.clip(.32 + lum * 1.6, .41, .82), .45)[..., None]
    pixels[..., 3] = np.clip((a - .26) / .70, 0, 1)
    atlas = bpy.data.images.new('hair_locks_atlas', w, h, alpha=True)
    atlas.pixels.foreach_set(pixels.ravel())
    atlas.filepath_raw = str(TEX / 'hair_locks_atlas.png')
    atlas.file_format = 'PNG'
    atlas.save()
    mat = material('hero_hair_cards', (.052, .044, .039), .69, atlas.filepath_raw)
    nodes = mat.node_tree.nodes
    tex = next(n for n in nodes if n.type == 'TEX_IMAGE')
    mat.node_tree.links.new(tex.outputs['Alpha'], nodes['Principled BSDF'].inputs['Alpha'])
    mat.use_backface_culling = False
    bpy.data.images.remove(image)
    return mat


def groom_locks(hair, fid, style, margin, ecz, ecy, lock_material):
    """Lay layered, tapered strand cards over the scalp and along long cuts."""
    me = hair.data
    tree = BVHTree.FromPolygons([v.co for v in me.vertices], [list(p.vertices) for p in me.polygons])
    centre = Vector((0, ecy - .062, ecz + .025))
    top = max(v.co.z for v in me.vertices)
    rng = np.random.default_rng(stable_seed(fid, style))
    count, length, width = HAIR_CARDS[style]
    verts, uv, polys = [], [], []
    for _ in range(count * 7):
        if len(polys) >= count * 8:
            break
        z = rng.uniform(-.80 if style in ('ponytail', 'bun') else -.38, 1.0)
        a = rng.uniform(0, math.tau)
        radial = math.sqrt(1 - z * z)
        ray = Vector((math.cos(a) * radial, math.sin(a) * radial, z))
        root, normal, _, _ = tree.ray_cast(centre + ray * .36, -ray)
        if root is None or normal.dot(ray) < .25:
            continue
        edge = margin(root)
        if edge < (.010 if style in ('buzz','crop','fade') else .004):
            continue
        if style in ('buzz','crop','fade') and root.z < top - .044:
            continue
        if style in ('fade', 'crop') and root.z < top - .051 and rng.random() > .15:
            continue
        if style == 'buzz' and edge > .014 and rng.random() > .38:
            continue
        direction = Vector((.55-.23*math.sin(a), 1, -.18))
        if style == 'fade':
            direction = Vector((.73, .58 + .23*math.cos(a), -.14))
        if style in ('ponytail', 'bun'):
            direction = Vector((-.35 * root.x / .08, -1, -.14))
        elif style == 'curls':
            direction = Vector((math.cos(a * 2), math.sin(a * 2), .38))
        elif style == 'pixie':
            direction = Vector((.87, .71, -.28 if root.y < ecy else -.62))
        tangent = direction - normal * direction.dot(normal)
        if tangent.length < .1:
            continue
        tangent.normalize()
        side = tangent.cross(normal).normalized()
        draw_len = length * rng.uniform(.64, 1.34)
        draw_width = width * rng.uniform(.69, 1.22)
        if style in ('buzz', 'crop', 'fade'):
            draw_len *= .52 + .48 * min(1.0, max(0.0, (root.z - (top - .07)) / .05))
        curl = style == 'curls'
        lock = int(rng.choice([3, 6] if curl else [0, 1, 4, 5, 7]))
        u0, u1 = LOCKS[lock]
        lift = {'buzz': .0006, 'crop': .0015, 'fade': .0019, 'curls': .0038, 'pixie': .0024,
                'ponytail': .0016, 'bun': .0015}[style] * rng.uniform(.8, 1.18)
        start = len(verts)
        card_points = []
        card_uvs = []
        for i in range(5):
            t = i * .25
            guide = root + tangent * ((t - .16) * draw_len)
            ray = (guide - centre).normalized()
            p, n, _, _ = tree.ray_cast(centre + ray * .36, -ray)
            if p is None or (p - guide).length > .018:
                # A card which leaves its fitted shell can form a visible
                # detached fleck at the temples as it turns.
                break
            arch = lift * math.sin(math.pi*t)**.9 + .0010*t - .0014*(1-t)**2
            bend = draw_width * (.28 if curl else .18) * math.sin(math.pi*t + .2)
            if style in ('crop','fade','pixie'):
                bend += .0017*t*t
            for j in range(3):
                lateral = j - 1
                card_points.append(p + n * (arch - abs(lateral) * lift * .28)
                             + side * (lateral * draw_width * (.57-.14*t) + bend))
                card_uvs.append((u0 + (u1 - u0) * j * .5, .97 - .94 * t))
        if len(card_points) != 15:
            continue
        verts.extend(card_points)
        uv.extend(card_uvs)
        for i in range(4):
            for j in range(2):
                k = start + i*3 + j
                polys.append((k,k+1,k+4,k+3))
    cards = mesh('Groom_' + style + '_' + fid, verts, uv, polys, polys)
    cards.data.materials.append(lock_material)
    for poly in cards.data.polygons:
        poly.use_smooth = True
    vg = cards.vertex_groups.new(name='b_head')
    vg.add(list(range(len(verts))), 1.0, 'REPLACE')
    return cards



def sculpt_head(points, fid):
    """Sculpt the facial planes while retaining each identity's eye spacing."""
    sockets = []
    moving = {j for i in head_faces for j in bf[i]}
    for side in ('l', 'r'):
        ids = {j for i in GROUP_FACES['helper-%s-eye'%side] for j in bf[i]}
        sockets.append(sum((points[j] for j in ids), Vector()) / len(ids))
        for band in (1,2):
            moving.update(j for i in GROUP_FACES['helper-%s-eyelashes-%s'%(side,band)] for j in bf[i])
    mouth_ids = {j for i in GROUP_FACES['helper-tongue'] for j in bf[i]}
    mouth = sum((points[j] for j in mouth_ids),Vector()) / len(mouth_ids)
    eye = (sockets[0]+sockets[1])*.5
    character = {'ade': (1.0,1.15), 'malik': (.91,1.16), 'ren': (.85,.90),
                 'kai': (1.09,1.0), 'theo': (1.17,.94), 'rio': (1.0,1.07),
                 'sam': (1.15,.95), 'noa': (.88,.88), 'remy': (1.04,1.10),
                 'jules': (.91,1.02)}
    nose_scale, cheek_scale = character[fid]
    for j in moving:
        p = points[j]
        x, y, z = p
        ax = abs(x)
        if y > eye.y + .008:
            bridge = math.exp(-(x/.012)**2-((z-eye.z+.012)/.020)**2)
            tip = math.exp(-(x/.013)**2-((z-eye.z+.032)/.010)**2)
            ala = math.exp(-((ax-.014)/.008)**2-((z-eye.z+.039)/.0065)**2)
            nostril = math.exp(-((ax-.0134)/.0047)**2-((z-eye.z+.043)/.0043)**2)
            cheek = math.exp(-((ax-.047)/.018)**2-((z-eye.z+.026)/.015)**2)
            below = math.exp(-((ax-.047)/.016)**2-((z-eye.z+.057)/.019)**2)
            p.y += nose_scale*(.0056*bridge+.0083*tip+.0025*ala-.0028*nostril)
            p.y += cheek_scale*(.0052*cheek-.0022*below)
            p.x += math.copysign(.0029*cheek, x)
            lip_t = max(0, 1-(x/.027)**2)
            dz = z-mouth.z-.0012*lip_t
            upper = math.exp(-((dz-.0035)/.0035)**2)
            lower = math.exp(-((dz+.0045)/.0042)**2)
            gap = math.exp(-(dz/.0014)**2)
            if y > mouth.y + .006:
                p.y += (.0045*upper+.0048*lower-.0014*gap)*lip_t
                p.z -= .0009*lip_t*lower
        for centre in sockets:
            dx,dz = x-centre.x,z-centre.z
            if abs(dx) < .022 and y > centre.y+.005 and abs(dz)<.023:
                orbit = math.exp(-(dx/.0145)**4-(dz/.016)**4)
                opening = (.06 if dz > 0 else .04) if BODY == 'b' else (.07 if dz > 0 else .04)
                p.z += orbit * dz * opening
                p.y += .0014*orbit*math.exp(-((dz+.006)/.005)**2)
        if ax > .067 and eye.y-.112 < y < eye.y-.03:
            ear = math.exp(-((z-eye.z+.012)/.025)**2-((y-eye.y+.065)/.026)**2)
            p.x += math.copysign(.003*ear, x)
            p.y -= .0018*ear
        jaw = math.exp(-((z-eye.z+.076)/.021)**2-((y-eye.y+.021)/.037)**2)
        p.x *= 1+(.052 if BODY=='a' else -.029)*jaw
        if BODY == 'b':
            zygoma = math.exp(-((ax-.052)/.019)**2-((z-eye.z+.022)/.022)**2)
            p.y += .0029*zygoma if y>eye.y-.027 else 0
            gonion = math.exp(-((ax-.061)/.022)**2-((z-eye.z+.093)/.018)**2)
            p.z += .0024*gonion
            p.y += .0015*gonion
        chin = math.exp(-(x/.029)**2-((z-mouth.z+.026)/.013)**2)
        if y > mouth.y-.020:
            p.y += .0041*chin


def eye_lid_rims(face_tree, centre, radius, tips, name):
    """Fit a narrow roll of skin to each eyelid opening on the sculpt."""
    x0 = min(p.x for p in tips)+.002
    x1 = max(p.x for p in tips)-.002
    objects = []
    for upper in (True, False):
        rows, uv = [], []
        for k in range(21):
            t = k/20
            x = x0+(x1-x0)*t
            cap = math.sin(math.pi*t)**.7
            direction = 1 if upper else -1
            for i in range(9):
                z = centre.z + direction*(.0015+i*.0014)*(.43+.57*cap)
                hit, _, _, _ = face_tree.ray_cast(Vector((x,centre.y+.12,z)), Vector((0,-1,0)))
                eye_front = centre.y + math.sqrt(max(0, radius**2-(x-centre.x)**2-(z-centre.z)**2))
                if hit is None or hit.y < max(centre.y+.003, eye_front-.0008):
                    continue
                # The rim rests on and rolls toward the raw edge of the lid.
                a = (.0005 + .0010*cap) * direction
                rows.append([hit+Vector((0,.00030,-a*.37)),
                             hit+Vector((0,.00056,a*.35)),
                             hit+Vector((0,.00010,a))])
                uv.append([(t,0),(t,.5),(t,1)])
                break
        if len(rows) < 8:
            continue
        lid = grid_mesh(name + ('_Upper' if upper else '_Lower'),rows,uv)
        face_out(lid, lambda _: Vector((0,1,0)))
        lid.data.materials.append(LID_MATERIAL)
        vg = lid.vertex_groups.new(name='b_head')
        vg.add(list(range(len(lid.data.vertices))),1.0,'REPLACE')
        objects.append(lid)
    return objects
