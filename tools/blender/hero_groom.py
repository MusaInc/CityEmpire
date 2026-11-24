"""Fit the player grooms to each sculpt and export strand surfaces."""

import math
from dataclasses import dataclass

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import convex_hull_2d

from build_b_surface import detail_nodes, length_material, packed_image, pixels
from garment_kit import _dilate, iso_cut, raster_uv
from wardrobe_quality import fit_headphone_band, smooth


def wound_gather(centre, radius, material):
    """Build a gathered style out of overlapping, UV-directed lock meshes."""
    points, faces, texels = [], [], []
    sectors, sides = 56, 9
    for ring, (height, reach, bulk) in enumerate((
            (-.53, .55, .29), (-.29, .69, .30), (-.02, .70, .31),
            (.25, .64, .28), (.48, .49, .26), (.61, .29, .23), (.65, .11, .19))):
        start = len(points)
        for i in range(sectors + 1):
            t = i / sectors
            angle = math.tau * t
            outward = Vector((math.cos(angle), math.sin(angle), 0))
            curl = .09 * math.sin(angle + ring * .88) + .07 * math.sin(2 * angle + ring)
            root = centre + radius * (outward * (reach + .042 * math.cos(angle * 3 + ring))
                                      + Vector((.058 * height, 0, height + curl)))
            for j in range(sides):
                section = math.tau * j / sides
                grooves = 1 + .045 * math.cos(section * 3 + angle * 4 + ring)
                offset = outward * math.cos(section) + Vector((0, 0, .70 * math.sin(section)))
                points.append(root + radius * bulk * grooves * offset)
                texels.append((j / sides + ring * .115, t))
        for row in range(sectors):
            for j in range(sides):
                a = start + row * sides + j
                b = start + row * sides + (j + 1) % sides
                faces.append((a, a + sides, b + sides, b))
    mesh = bpy.data.meshes.new('Wrapped lock surfaces')
    mesh.from_pydata(points, [], faces)
    mesh.materials.append(material)
    layout = mesh.uv_layers.new(name='SurfaceUV')
    for p in mesh.polygons:
        p.use_smooth = True
        across = [texels[i][0] for i in p.vertices]
        for loop, vertex in zip(p.loop_indices, p.vertices):
            u, v = texels[vertex]
            layout.data[loop].uv = (u + float(max(across) - u > .5), v)
    locks = bpy.data.objects.new('Wound bun', mesh)
    bpy.context.collection.objects.link(locks)
    return locks


@dataclass(frozen=True)
class Cut:
    clearance: float
    crown: float
    locks: int
    length: float
    width: float
    roughness: float


CUTS = {
    'buzz': Cut(.0031, .0008, 72, .007, .0014, .73),
    'crop': Cut(.0042, .0027, 126, .032, .0028, .54),
    'fade': Cut(.0051, .0032, 114, .033, .0025, .59),
    'curls': Cut(.0056, .0076, 145, .026, .0033, .58),
    'pixie': Cut(.0038, .0058, 136, .048, .0031, .50),
    'ponytail': Cut(.0035, .0038, 142, .049, .0025, .55),
    'bun': Cut(.0035, .0037, 142, .043, .0024, .57),
}


def mesh_tree(mesh, material=0):
    return BVHTree.FromPolygons([v.co for v in mesh.vertices],
                               [p.vertices[:] for p in mesh.polygons if p.material_index == material])


def eye_centre(face):
    eye = face.data.materials.find('hero_eye')
    ids = {i for p in face.data.polygons if p.material_index == eye for i in p.vertices}
    points = [face.data.vertices[i].co for i in ids if face.data.vertices[i].co.x > 0]
    return Vector(tuple((min(p[i] for p in points) + max(p[i] for p in points)) * .5 for i in range(3)))


@dataclass
class Ear:
    rim: list
    centre: Vector

    def distance(self, point):
        """Signed distance to the measured lateral outline in the YZ plane."""
        p = Vector((point.y, point.z))
        outside = False
        best = 1.0
        for index, a in enumerate(self.rim):
            b = self.rim[(index + 1) % len(self.rim)]
            step = b - a
            fraction = max(0, min(1, (p - a).dot(step) / max(step.length_squared, 1e-9)))
            best = min(best, (p - a - step * fraction).length)
            outside |= step.cross(p - a) < 0
        return best if outside else -best


def measure_ear(skin, eye, sign):
    """Sample the pinna where it stands off the adjacent temple and mastoid."""
    def lateral(y, z):
        p = skin.ray_cast(Vector((sign * .145, y, z)), Vector((-sign, 0, 0)), .14)[0]
        return abs(p.x) if p is not None else 0

    points = []
    for z in np.arange(eye.z - .069, eye.z + .004, .0017):
        fore, rear = eye.y - .041, eye.y - .119
        span = fore - rear
        first, last = lateral(rear, z), lateral(fore, z)
        for y in np.arange(eye.y - .109, eye.y - .049, .0017):
            f = (y - rear) / span
            skin_x = lateral(y, z)
            reference = (first * (1 - f) + last * f) + .004 * math.sin(f * math.pi)
            if skin_x > max(.065, reference + .0059):
                points.append(Vector((y, z)))
    if len(points) < 6:
        raise ValueError(f'Could not measure an ear at {eye}, side {sign}')
    hull = [points[i] for i in convex_hull_2d(points)]
    signed_area = sum(a.cross(b) for a, b in zip(hull, hull[1:] + hull[:1]))
    if signed_area < 0:
        hull.reverse()
    centre = sum(hull, Vector((0, 0))) / len(hull)
    return Ear(hull, centre)


def ear_distance(point, ears, cut):
    if abs(point.x) < .048:
        return .04
    ear = ears[point.x > 0]
    gap = ear.distance(point) - cut.clearance
    return max(gap, .051 - abs(point.x))


def flow_guide(point, eye, style):
    x, y, z = point
    if style in ('ponytail', 'bun'):
        return Vector((-.72 * x, eye.y - .164 - y, eye.z + .043 - z))
    if style == 'pixie':
        return Vector((.84, .62, -.42))
    if style == 'fade':
        return Vector((.65, .81, -.14))
    if style == 'curls':
        return Vector((math.sin(x * 81 + z * 37), math.cos(y * 74 - x * 91), .31))
    return Vector((.26, 1, -.16))


def tied_freedom(point, eye, style):
    if style == 'bun':
        return .014 * smooth(eye.y - .142, eye.y - .203, point.y)
    if point.y < eye.y - .127:
        return .08 * smooth(eye.z + .022, eye.z - .161, point.z)
    return 0


def fade_progress(point, eye, style):
    # Smooth, believable barber fade along temples and occipital nape for all short cuts.
    temple = smooth(eye.y - .115, eye.y - .022, point.y)
    level = point.z - eye.z
    if style == 'fade':
        return smooth(-.048 + .018 * temple, .060 + .008 * temple, level) ** 1.15
    if style == 'buzz':
        return smooth(-.056 + .014 * temple, .016 + .010 * temple, level)
    return smooth(-.046 + .014 * temple, .042 + .010 * temple, level) ** 1.10


def strand_opacity(point, eye, style):
    if style in ('crop', 'fade'):
        return smooth(.57, .87, fade_progress(point, eye, style))
    return 1


def fit_shell(obj, skin, eye, ears, style):
    cut = CUTS[style]
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    cap = {v for face in bm.faces if face.material_index == 0 for v in face.verts}
    crest = max(v.co.z for v in cap)
    skull = Vector((0, eye.y - .062, eye.z + .026))
    # A pre-existing tied length can share slot 0, but sits entirely behind the
    # scalp. Preserve that component until it receives its own unwrap.
    def on_cap(p):
        return not (style in ('ponytail', 'bun') and p.y < eye.y - .139 and abs(p.x) < .049)

    bm.normal_update()
    for v in cap:
        p = v.co
        if not on_cap(p):
            continue
        distance = ear_distance(p, ears, cut)
        raised = smooth(eye.z + .025, crest - .023, p.z)
        edge = smooth(.003, .024, distance)
        forward = smooth(eye.y - .048, eye.y + .006, p.y)
        sweep = p.x + .43 * (p.y - eye.y)
        strands = .5 + .5 * math.cos(sweep * 227 + 1.55 * math.sin(p.z * 54))
        if style == 'curls':
            strands = (.5 + .5 * math.sin(p.x * 139 + p.z * 94)) * (.5 + .5 * math.cos(p.y * 132 - p.z * 77))
        bump = cut.crown * (.26 + .74 * strands) * max(.20, raised) * edge
        if style in ('crop', 'buzz'):
            bump *= .6  # these are the two meshes worn under headwear
        p += v.normal * bump
        # Offset the smooth ruler-like fringe into short, irregular roots.
        fringe = (1 - smooth(eye.z + .038, eye.z + .078, p.z)) * forward
        if style != 'buzz':
            recession = .005 * smooth(.021, .067, abs(p.x)) if style in ('ponytail', 'bun') else 0
            p.z += fringe * edge * (recession + .0028 * math.sin(p.x * 129 + .7) + .0012 * math.sin(p.x * 304))
        direction = (p - skull).normalized()
        hit, _, _, _ = skin.ray_cast(p + direction * .023, -direction, .048)
        if hit is not None:
            gap = (p - hit).dot(direction)
            # Narrow the rim into the root zone and keep the helmet mesh
            # floating in the temple from reading like a disconnected cap.
            near_ear = 1 - smooth(.007, .019, abs(distance))
            target_gap = .0020 + .008 * (1 - near_ear)
            settle = max(0, .00045 - gap) - max(0, gap - target_gap) * .70 * near_ear
            if style in ('crop', 'fade'):
                density = fade_progress(p, eye, style)
                target = .0009 + .0067 * density
                settle -= max(0, gap - target) * (1 - density)
            p += direction * max(-.0056, min(.0045, settle))

    iso_cut(bm, lambda p: ear_distance(p, ears, cut) if on_cap(p) else .04)
    bm.to_mesh(obj.data)
    bm.free()
    me = obj.data
    density = me.uv_layers.get('GroomDensity') or me.uv_layers.get('ClothFreedom')
    if density is not None:
        for poly in me.polygons:
            length = obj.data.materials[poly.material_index].name.startswith('hero_hair_lengths')
            for li in poly.loop_indices:
                p = me.vertices[me.loops[li].vertex_index].co
                if poly.material_index == 0 and on_cap(p):
                    transition = smooth(0, .009, ear_distance(p, ears, cut))
                    old = density.data[li].uv.y
                    if style in ('crop', 'fade'):
                        old = fade_progress(p, eye, style)
                    elif style == 'buzz':
                        old = min(1, old * 1.83)
                    density.data[li].uv.y = old * (.29 + .71 * transition)
                if style in ('ponytail', 'bun'):
                    density.data[li].uv.x = tied_freedom(p, eye, style) if length else 0
    obj.data.update()
    return skull


def length_components(obj, material, style, eye):
    me = obj.data
    if any(m.name.startswith('hero_hair_lengths') for m in me.materials):
        return
    links = {}
    for poly in me.polygons:
        if poly.material_index == 0:
            for a, b in poly.edge_keys:
                links.setdefault(a, set()).add(b)
                links.setdefault(b, set()).add(a)
    visited = set()
    for root in links:
        if root in visited:
            continue
        part = [root]
        visited.add(root)
        for i in part:
            for j in links[i] - visited:
                visited.add(j)
                part.append(j)
        if len(part) < 40 or len(part) > 300:
            continue
        if sum(me.vertices[i].co.y for i in part) / len(part) > eye.y - .137:
            continue
        uv = me.uv_layers[0]
        centre = sum((me.vertices[i].co for i in part), Vector()) / len(part)
        ordered = sorted(part)
        coords = {}
        if style == 'ponytail' and len(ordered) == 84:
            for index, i in enumerate(ordered):
                row, col = divmod(index, 14)
                coords[i] = (col / 14, row / 5)
        else:
            for i in ordered:
                axis = (me.vertices[i].co - centre).normalized()
                coords[i] = ((math.atan2(axis.x, axis.y) / math.tau) % 1, math.acos(axis.z) / math.pi)
        me.materials.append(material)
        for poly in me.polygons:
            if poly.material_index != 0 or any(i not in coords for i in poly.vertices):
                continue
            poly.material_index = len(me.materials) - 1
            u = [coords[i][0] for i in poly.vertices]
            seam = max(u) - min(u) > .52
            for loop, i in zip(poly.loop_indices, poly.vertices):
                s, t = coords[i]
                uv.data[loop].uv = (s + float(seam and s < .45), t)
        return


def shape_tied_length(obj, style):
    mesh = obj.data
    slot = next((i for i, mat in enumerate(mesh.materials)
                 if mat.name.startswith('hero_hair_lengths')), None)
    if slot is None:
        return
    bm = bmesh.new()
    bm.from_mesh(mesh)
    edges = {e for f in bm.faces if f.material_index == slot for e in f.edges}
    if style == 'ponytail' and edges:
        bmesh.ops.subdivide_edges(bm, edges=list(edges), cuts=1, smooth=.43, use_grid_fill=True)
    bm.normal_update()
    length = {v for f in bm.faces if f.material_index == slot for v in f.verts}
    if length:
        centre = sum((v.co for v in length), Vector()) / len(length)
        top = max(v.co.z for v in length)
        for v in length:
            offset = v.co - centre
            if style == 'ponytail':
                taper = smooth(.022, .215, top - v.co.z)
                v.co.x += .010 * taper * math.sin(taper * 2.3)
                v.co.y += .007 * taper * taper
            else:
                angle = math.atan2(offset.x, offset.y)
                ridge = math.cos(angle * 11 + offset.z * 86)
                v.co += v.normal * (.0016 * ridge * smooth(.004, .021, math.hypot(offset.x, offset.y)))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def atlas_image(old, output):
    """Translucent strands grouped into tapered, crooked clumps."""
    n, strips = 1024, 8
    v = np.arange(n, dtype=np.float32)[:, None] / n
    alpha = np.zeros((n, n), np.float32)
    light = np.full((n, n), .45, np.float32)
    rng = np.random.default_rng(10174)
    for strip in range(strips):
        section = slice(strip * n // strips, (strip + 1) * n // strips)
        u = np.arange(section.start, section.stop, dtype=np.float32)[None, :] / n
        shadow, highlight = alpha[:, section], light[:, section]
        for _ in range(25):
            root = (strip + rng.uniform(.08, .92)) / strips
            phase = rng.random() * math.tau
            lift = rng.uniform(.008, .031)
            end = rng.uniform(.68, .99)
            width = rng.uniform(.00055, .0014)
            lean = rng.uniform(-.023, .023)
            path = root + lean * v + lift * np.sin(v * 2.5 + phase) * v
            envelope = np.clip(v / .09, 0, 1) * np.clip((end - v) / .16, 0, 1)
            d = (u - path) / width
            fibre = np.exp(-d*d) * envelope
            highlight[:] = np.where(fibre > shadow, rng.uniform(.48, .88), highlight)
            np.maximum(shadow, fibre, out=shadow)
    img = bpy.data.images.new('hair_locks_atlas', n, n, alpha=True)
    img.alpha_mode = 'STRAIGHT'
    rgba = np.stack((light, light * .984, light * .963, alpha), -1).astype(np.float32)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = str(output / 'hair_locks_atlas.png')
    img.file_format = 'PNG'
    img.save()
    img.pack()
    for node in old.node_tree.nodes:
        if node.type == 'TEX_IMAGE':
            node.image = img


def ribbon(batch, centres, normals, width, strip):
    points, faces, uv = batch
    base = len(points)
    count = len(centres)
    for i, (centre, normal) in enumerate(zip(centres, normals)):
        direction = centres[min(i + 1, count - 1)] - centres[max(0, i - 1)]
        across = direction.cross(normal).normalized()
        t = i / (count - 1)
        span = width * (.96 - .67 * t) * (.70 + .30 * math.sin(math.pi * t))
        for j in (0, 1):
            points.append(centre + across * ((j - .5) * span))
            uv.append(((strip + .06 + j * .88) / 8, t))
    faces.extend((base+i, base+i+1, base+i+3, base+i+2) for i in range(0, 2 * count - 2, 2))


def curl_cluster(root, normal, axis, across, rng):
    radius = rng.uniform(.0055, .010)
    turns = rng.uniform(.76, 1.21)
    twist = rng.uniform(-.35, .35)
    centres, normals = [], []
    for i in range(9):
        t = i / 8
        phase = t * math.tau * turns
        spread = radius * (.78 + .22 * math.sin(t * math.pi))
        span = (math.cos(phase) - 1) * spread
        lift = math.sin(t * math.pi) * (spread * (.76 + .24 * math.sin(phase + twist)))
        centre = root + axis * (span + radius * t * 1.60) + across * (math.sin(phase) * spread)
        centres.append(centre + normal * (lift + .0010 * t - .00045))
        normals.append((normal + across * math.sin(phase) * .28).normalized())
    return centres, normals


def bound_lengths(batch, base, style, rng):
    """Lay visible loose strands over the tied bundle in the same draw surface."""
    mesh = base.data
    slot = next((i for i, mat in enumerate(mesh.materials)
                 if mat.name.startswith('hero_hair_lengths')), None)
    if slot is None:
        return
    length_faces = [p.vertices[:] for p in mesh.polygons if p.material_index == slot]
    if not length_faces:
        return
    points = [v.co for v in mesh.vertices]
    lengths = [points[i] for i in {i for face in length_faces for i in face}]
    skin = BVHTree.FromPolygons(points, length_faces)
    centre = sum(lengths, Vector()) / len(lengths)
    lo, hi = min(p.z for p in lengths), max(p.z for p in lengths)
    for lock in range(24 if style == 'ponytail' else 19):
        angle = (lock * 2.39996) % math.tau
        roots, normals = [], []
        for row in range(7):
            t = row / 6
            if style == 'ponytail':
                z = hi - (hi - lo) * (.105 + .020 * (lock % 5) + t * (.59 + .05 * (lock % 4)))
                section = sorted(lengths, key=lambda p: abs(p.z - z))[:15]
                origin = sum(section, Vector()) / len(section)
                origin.z = z
                direction = Vector((math.cos(angle + t * .26), math.sin(angle + t * .26), 0))
            else:
                origin = centre
                roll = angle + t * math.tau * .47
                z = (.18 + .12 * (lock % 4)) * math.cos(t * math.pi)
                direction = Vector((math.cos(roll), math.sin(roll), z)).normalized()
            hit, normal, _, _ = skin.ray_cast(origin + direction * .13, -direction, .16)
            if hit is None or direction.dot(normal) < .05:
                break
            lift = .00124 * math.sin(t * math.pi) + .00065 * t - .00021
            roots.append(hit + normal * lift)
            normals.append(normal)
        if len(roots) == 7:
            ribbon(batch, roots, normals, rng.uniform(.0022, .0041), lock % 8)


def portrait_locks(batch, eye):
    """Two temple guides break away from the crown and curl past the jaw."""
    for side in (-1, 1):
        for layer in range(4):
            centres = []
            for row in range(12):
                t = row / 11
                wave = math.sin(t * math.tau + .38 * side)
                x = .033 + .034 * math.sin(t * math.pi / 2) + .008 * wave * t
                y = eye.y - .012 + .031 * math.sin(t * math.pi * .96) - .020 * t * t
                centres.append(Vector((side * (x + .0018 * layer), y + .0023 * layer,
                                       eye.z + .088 - (.190 + .004 * layer) * t)))
            normal = Vector((side * .56, .83, 0)).normalized()
            ribbon(batch, centres, [normal] * len(centres), .012 - layer * .0018, (layer + 2) % 8)


def build_cards(obj, base, eye, ears, skull, style, seed):
    """Make narrow swept ribbons with roots on the fitted scalp."""
    cut = CUTS[style]
    shell = mesh_tree(base.data)
    rng = np.random.default_rng(seed)
    batch = ([], [], [])
    points, faces, uv = batch
    cluster_count = 0
    for _ in range(cut.locks * 12):
        if len(points) >= cut.locks * 10:
            break
        a = rng.uniform(0, math.tau)
        z = rng.uniform(-.75 if style in ('ponytail', 'bun', 'fade') else -.33, 1)
        ring = math.sqrt(1 - z*z)
        direction = Vector((ring * math.sin(a), ring * math.cos(a), z))
        root, normal, _, _ = shell.ray_cast(skull + direction * .28, -direction, .28)
        if root is None or normal.dot(direction) < .32:
            continue
        growth = fade_progress(root, eye, style) if style in ('fade', 'crop') else 1
        if growth < .12 or (growth < .84 and rng.random() > growth * .82 + .08):
            continue
        if ear_distance(root, ears, cut) < .003:
            continue
        guide = flow_guide(root, eye, style)
        draw = guide - normal * guide.dot(normal)
        if draw.length < .07:
            continue
        draw.normalize()
        across = draw.cross(normal).normalized()
        if style == 'curls' and cluster_count < 61 and root.z > eye.z + .014 and rng.random() < .62:
            centres, norms = curl_cluster(root, normal, draw, across, rng)
            supported = True
            for p in centres:
                if ear_distance(p, ears, cut) <= .004:
                    supported = False
                    break
                if p.y > eye.y - .026 and p.z < eye.z + .085:
                    d = (p - skull).normalized()
                    hit = shell.ray_cast(skull + d * .25, -d, .25)[0]
                    if hit is None or (p - hit).length > .013:
                        supported = False
                        break
            if supported:
                ribbon(batch, centres, norms, rng.uniform(.0037, .0061), int(rng.integers(8)))
                cluster_count += 1
                continue
        length = cut.length * rng.uniform(.62, 1.23)
        width = cut.width * rng.uniform(.61, 1.14)
        swing = rng.uniform(-.008, .008) * (1.65 if style in ('pixie', 'curls') else 1)
        tuft = rng.uniform(.0005, .0026) * (1.5 if style in ('curls', 'pixie') else 1)
        if style == 'buzz':
            swing *= .1
            tuft *= .29
        layered = style == 'pixie' and rng.random() < .34
        if layered:
            width *= 1.63
            tuft *= 1.66
            swing *= 1.3
        if style in ('crop', 'fade'):
            length *= .17 + .83 * growth
            width *= .28 + .72 * growth
            tuft *= .26 + .74 * growth
        strip = int(rng.integers(8))
        rows, texels = [], []
        last_surface = None
        feather = 0
        for i in range(5):
            t = i / 4
            curve = math.sin(t * math.pi)
            d = (root + draw * (t - .18) * length + across * swing * curve - skull).normalized()
            hit, n, _, _ = shell.ray_cast(skull + d * .29, -d, .29)
            if (hit is None or (last_surface and (hit - last_surface).length > .023)) and layered and i >= 3:
                # Feather only the ends. Every root stays on the underlying
                # shell, with a bounded extension away from the head.
                hit = last_surface + draw * min(.0065, length * .19)
                n = normal
                feather += 1
            if hit is None or ear_distance(hit, ears, cut) < .0016 or feather > 2:
                break
            if style in ('crop', 'fade') and fade_progress(hit, eye, style) < .09:
                break
            last_surface = hit
            for j in (0, 1):
                offset = across * ((j - .5) * width * (1.13 - .73 * t))
                p = hit + offset + n * (tuft * curve + t * .0007 - .00028)
                if ear_distance(p, ears, cut) < .0012:
                    break
                rows.append(p)
                texels.append(((strip + .06 + j * .88) / 8, t))
        if len(rows) != 10:
            continue
        start = len(points)
        points.extend(rows)
        uv.extend(texels)
        faces.extend((start+i, start+i+1, start+i+3, start+i+2) for i in range(0, 8, 2))
    if style in ('ponytail', 'bun'):
        bound_lengths(batch, base, style, rng)
    if obj.name == 'Groom_bun_jules':
        portrait_locks(batch, eye)
    previous = obj.data
    me = bpy.data.meshes.new(obj.name + '_Strands')
    me.from_pydata(points, [], faces)
    me.materials.append(previous.materials[0])
    obj.data = me
    main = me.uv_layers.new(name='SurfaceUV')
    for face in me.polygons:
        face.use_smooth = True
        for loop in face.loop_indices:
            main.data[loop].uv = uv[me.loops[loop].vertex_index]
    motion = me.uv_layers.new(name='GroomMotion', do_init=False)
    for loop in me.loops:
        vert = me.vertices[loop.vertex_index].co
        if style in ('ponytail', 'bun'):
            motion.data[loop.index].uv.x = tied_freedom(vert, eye, style)
        motion.data[loop.index].uv.y = strand_opacity(vert, eye, style)
    if previous.uv_layers.get('ClothFreedom'):
        motion.name = 'ClothFreedom'
    me.uv_layers.active_index = 0
    me.update()
    if not previous.users:
        bpy.data.meshes.remove(previous)


def head_weights(obj):
    obj.vertex_groups.clear()
    group = obj.vertex_groups.new(name='b_head')
    group.add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')


def scalp_bake(obj, eye, style, output):
    """Bake clean hair flow against the scalp's actual UVs."""
    colour_node, normal_map, normal_node = detail_nodes(obj.data.materials[0])
    material = obj.data.materials[0]
    size = 512
    positions, _, mask = raster_uv(obj, size, material_index=0)
    x, y, z = positions[mask].T
    relative_y, relative_z = y - eye.y, z - eye.z
    crown = np.arctan2(x, relative_y + .109)
    if style in ('ponytail', 'bun'):
        flow = np.arctan2(x, relative_z - .037)
        streak = flow * 86 + 1.12 * np.sin(relative_y * 65 + flow * 4)
    elif style == 'curls':
        flow = crown
        streak = crown * 34 + 2.5 * np.sin(relative_z * 136 + x * 79) + .70 * np.sin(y * 160)
    elif style in ('pixie', 'fade', 'crop'):
        flow = crown
        streak = (x - relative_y * (.62 if style == 'pixie' else .38)) * 1320
        streak += 1.74 * np.sin(relative_z * 60 + x * 35) + .52 * np.sin(y * 83)
    else:
        flow = crown
        streak = (x + relative_y * .32) * 2360 + .84 * np.sin(z * 815)
    fibres = .56 * np.cos(streak) + .28 * np.cos(streak * 1.94 + .71) + .16 * np.sin(streak * 3.12)
    clumps = np.sin(flow * (19 if style == 'curls' else 31) + .57 * np.cos(relative_z * 39))
    if style == 'buzz':
        fibres = np.sin(x * 1920 + z * 1140) * np.sin(y * 1480 - z * 2010)
        clumps = .64 * np.sin((x + y) * 243 + z * 97) * np.cos(z * 112 - y * 166)
    if style in ('crop', 'fade'):
        stubble = np.sin(x * 1980 + z * 791) * np.sin(y * 1560 - z * 1770)
        long = np.clip((relative_z + .006) / .077, 0, 1)
        fibres = stubble * (1 - long) + fibres * long
        clumps *= .26 + .74 * long
    texture = .72 + (.10 if style == 'buzz' else .18) * fibres + .095 * clumps
    rgb = np.full((size, size, 3), .57, np.float32)
    rgb[mask] = texture[:, None] * np.array([1, .981, .954])
    colour_node.image = packed_image(output / ('hair_' + style + '_albedo.png'), _dilate(rgb, mask, 10))
    height = np.zeros(mask.shape, np.float32)
    lift = .00012 if style == 'buzz' else .00027
    height[mask] = lift * fibres + .00020 * clumps
    h = _dilate(height[..., None], mask, 5)[..., 0]
    p = _dilate(positions, mask, 4)
    du = np.maximum(np.linalg.norm(np.roll(p, 1, 1) - np.roll(p, -1, 1), axis=-1), .00057)
    dv = np.maximum(np.linalg.norm(np.roll(p, 1, 0) - np.roll(p, -1, 0), axis=-1), .00057)
    gx = (np.roll(h, 1, 1) - np.roll(h, -1, 1)) / du
    gy = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) / dv
    normal = np.stack((np.clip(gx, -.85, .85), np.clip(gy, -.85, .85), np.ones_like(h)), -1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    normal_node.image = packed_image(output / ('hair_' + style + '_normal.png'),
                                     _dilate(normal * .5 + .5, mask, 9), True)
    normal_map.inputs['Strength'].default_value = .89
    material.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = CUTS[style].roughness


def remove_legacy_scalp_paint(face, eye, body, output):
    """Lift the old uniform hairline baked into the editable baseline skin."""
    colour, _, _ = detail_nodes(face.data.materials[0])
    image = colour.image
    pos, _, mask = raster_uv(face, image.size[0], material_index=0)
    x, y, z = pos[mask].T.copy()
    y -= eye.y
    z -= eye.z
    if body == 'b':
        # The corrected B head sits back at a slight angle from the original
        # texture bake. Measure the old dye in the original skull axes.
        tilt = math.radians(3.5)
        y, z = (math.cos(tilt) * y + math.sin(tilt) * z) / 1.035, (-math.sin(tilt) * y + math.cos(tilt) * z) / 1.025
        x /= 1.055
    outline = np.maximum.reduce([z - .045, np.minimum(-.085 - y, z + .070),
                                 np.minimum.reduce([np.abs(x) - .055, -.030 - y, z - .012])])
    darkness = np.clip((outline + .005) / .009, 0, 1)
    side = np.clip((.035 - z) / .020, 0, 1) + np.clip((-.060 - y) / .020, 0, 1)
    stubble = np.clip(1 + outline / .026, 0, 1) * (outline < 0) * np.clip(side, 0, 1)
    stubble *= np.clip((z + .075) / .020, 0, 1)
    absorption = (1 - .24 * darkness) * (1 - .22 * (.85 * stubble) ** 1.4)
    rgb = pixels(image)[..., :3].copy()
    rgb[mask] /= absorption[:, None]
    colour.image = packed_image(output / (face.name.lower() + '_albedo.png'), _dilate(rgb, mask, 10))


def groom_hero(meshes, output, body, legacy_skin_paint=False):
    objects = {obj.name: obj for obj in meshes}
    faces = sorted(name[5:] for name in objects if name.startswith('Face_'))
    first = faces[0]
    pony = objects[f'Hair_ponytail_{first}']
    lengths = next((m for m in pony.data.materials if m.name.startswith('hero_hair_lengths')), None)
    if lengths is None and body == 'b':
        lengths = bpy.data.materials.get('hero_hair_lengths_b')
    if lengths is None:
        lengths = length_material(pony.data.materials[0], output, 'hair_lengths_b' if body == 'b' else 'hair_lengths')
    atlas_image(objects[f'Groom_crop_{first}'].data.materials[0], output)
    reference = {}
    for index, face in enumerate(faces):
        head = objects['Face_' + face]
        skin = mesh_tree(head.data)
        eye = eye_centre(head)
        if legacy_skin_paint:
            remove_legacy_scalp_paint(head, eye, body, output)
        ears = {sign > 0: measure_ear(skin, eye, sign) for sign in (-1, 1)}
        print('EAR FIT', face, [(len(e.rim), tuple(round(v, 3) for v in e.centre)) for e in ears.values()], flush=True)
        styles = {}
        for style_index, style in enumerate(CUTS):
            hair = objects[f'Hair_{style}_{face}']
            cards = objects[f'Groom_{style}_{face}']
            if style in ('ponytail', 'bun'):
                length_components(hair, lengths, style, eye)
                shape_tied_length(hair, style)
            skull = fit_shell(hair, skin, eye, ears, style)
            build_cards(cards, hair, eye, ears, skull, style, 24057 + index * 83 + style_index * 41)
            head_weights(hair)
            head_weights(cards)
            styles[style] = hair
            print('GROOM', style, face, len(hair.data.vertices), len(cards.data.vertices), flush=True)
        fit_headphone_band(objects['Acc_headphones_' + face], head, styles, eye.z + .005)
        if face in ('ade', 'noa'):
            reference = {style: (obj, eye) for style, obj in styles.items()}
    for style, (hair, eye) in reference.items():
        scalp_bake(hair, eye, style, output)
