"""Final Build B sculpt, posed hand fit, and sewn garment edges."""

from collections import Counter
import math

import bpy
from mathutils import Vector

from build_b_fit import UPPER_BODY, blend_weights, radial_fit, ridge
from build_b_surface import denim_surface, face_surface, knit_surface, shared_face_style, surface_detail
from garment_kit import SkinSurface
from hero_groom import eye_centre, mesh_tree
from wardrobe_quality import adjust_basis, smooth, surface_tree


def bell(value, width):
    return math.exp(-(value / width) ** 2)


def sculpt_face(obj):
    me = obj.data
    eye_index = me.materials.find('hero_eye')
    eye_vertices = {i for p in me.polygons if p.material_index == eye_index for i in p.vertices}
    right_eye = [me.vertices[i].co for i in eye_vertices if me.vertices[i].co.x > 0]
    eye = Vector(tuple((min(p[i] for p in right_eye) + max(p[i] for p in right_eye)) * .5 for i in range(3)))

    def facial_planes(point):
        x, y, z = point
        side = abs(x)
        height = z - eye.z
        face = smooth(.046, eye.y + .013, y)
        if face == 0:
            return Vector()
        orbit = bell(side - eye.x, .016)
        bridge = bell(x, .012) * bell(height + .018, .023)
        bridge_sides = bell(side - .016, .008) * bell(height + .019, .017)
        tip = bell(x, .012) * bell(height + .029, .009)
        cheek = bell(side - .048, .018) * bell(height + .035, .018)
        hollow = bell(side - .053, .014) * bell(height + .060, .017)
        brow = orbit * bell(height - .019, .010)
        tear = orbit * bell(height + .016, .006)
        chin = bell(x, .028) * bell(height + .088, .011)
        lip = bell(x, .024) * bell(height + .064, .006)
        corners = bell(side - .025, .006) * bell(height + .066, .007)
        # Support the nasal bridge, zygoma and chin. Recess the adjacent
        # valleys so these landmarks read under a moving key light.
        dy = (.0042 * bridge - .0020 * bridge_sides + .0025 * tip
              + .0050 * cheek - .0031 * hollow + .0023 * brow - .0018 * tear
              + .0038 * chin + .0018 * lip - .0015 * corners)
        return Vector((math.copysign(.0017 * cheek, x) * face, dy * face, 0))

    keys = obj.data.shape_keys.key_blocks
    for v in me.vertices:
        if v.index in eye_vertices:
            continue
        for key in keys:
            point = key.data[v.index].co
            point += facial_planes(point)
        v.co += facial_planes(v.co)
    me.update()
    return eye


def face_style_delta(point, eye, ocular=False):
    """Match the plane changes and eye proportions used on Build A."""
    x, y, z = point
    width = abs(x)
    level = z - eye.z
    medial = width - eye.x
    side = -1 if x < 0 else 1
    front = smooth(eye.y - .038, eye.y + .010, y)
    front *= 1 - smooth(.062, .081, width)
    orbit = bell(medial, .026) * bell(level, .022)
    side_eye = side * .158 * medial * orbit * front
    lid = -.150 * level * orbit * front
    if ocular:
        return Vector((side_eye, .00055 * front, lid))

    root = bell(x, .015) * bell(level + .016, .023)
    tip = bell(x, .016) * bell(level + .032, .014)
    cheek = bell(width - .044, .021) * bell(level + .032, .027)
    muzzle = bell(x, .044) * bell(level + .057, .022)
    jaw = bell(width - .049, .018) * bell(level + .086, .018)
    chin = bell(x, .032) * bell(level + .091, .015)
    brow = bell(width - .042, .024) * bell(level - .023, .011)
    arch = bell(medial, .021) * bell(level - .025, .013)
    depth = (-.0071 * root - .0042 * tip - .0082 * cheek
             - .0045 * muzzle - .0042 * chin + .0019 * brow)
    contour = side * (.0029 * jaw + .0013 * chin * min(1, width / .027))
    height = -.0046 * tip - .0035 * chin - .0012 * arch
    return Vector((side_eye + contour * front, depth * front, lid + height * front))


def match_build_b_face_style(meshes, texture_dir):
    faces = {obj.name[5:]: obj for obj in meshes if obj.name.startswith('Face_')}
    eyes = {name: eye_centre(face) for name, face in faces.items()}
    for name, face in faces.items():
        mesh = face.data
        eye = eyes[name]
        eye_slot = mesh.materials.find('hero_eye')
        brow_slot = mesh.materials.find('hero_brow')
        ocular = {i for p in mesh.polygons if p.material_index == eye_slot for i in p.vertices}
        brows = {i for p in mesh.polygons if p.material_index == brow_slot for i in p.vertices}
        keys = mesh.shape_keys.key_blocks
        for vertex in mesh.vertices:
            for key in keys:
                point = key.data[vertex.index].co
                point += face_style_delta(point, eye, vertex.index in ocular)
            vertex.co += face_style_delta(vertex.co, eye, vertex.index in ocular)
        mesh.update()

        # Seat the thin brow strands on the new ridge. The skin bake follows
        # the same warp as the geometry, so its brow shadow stays underneath.
        skin = mesh_tree(mesh)
        for idx in brows:
            point = mesh.vertices[idx].co
            origin = Vector((point.x, eye.y + .14, point.z))
            hit = skin.ray_cast(origin, Vector((0, -1, 0)), .16)[0]
            if hit is None or abs(hit.y - point.y) > .009:
                continue
            offset = hit.y + .00052 - point.y
            point.y += offset
            for key in keys:
                key.data[idx].co.y += offset

        # Keep the existing iris colours and make the sclera read clearly
        # inside the longer aperture, including with very dark iris tints.
        uv = mesh.uv_layers[0]
        for poly in mesh.polygons:
            if poly.material_index == eye_slot:
                for li in poly.loop_indices:
                    coord = uv.data[li].uv
                    for i in (0, 1):
                        coord[i] = min(1, max(0, .5 + (coord[i] - .5) * 1.13))
        mesh.update()
        surface_detail(face, texture_dir, lambda p, n, rgb: shared_face_style(p, n, eye, rgb), .66, replace=True)

    for obj in meshes:
        if obj.name.startswith('Acc_shades_'):
            eye = eyes[obj.name.removeprefix('Acc_shades_')]
            adjust_basis(obj, lambda p: face_style_delta(p, eye) * .62)
        elif obj.name.startswith('Mask_'):
            adjust_basis(obj, lambda p: face_style_delta(p, eyes['rio']) * .42)


def limb_frame(joints, side, joint, next_joint):
    origin = joints[joint + '_' + side]
    axis = (joints[next_joint + '_' + side] - origin).normalized()
    return origin, axis, axis.cross(Vector((0, 1, 0))).normalized()


def arm_shape(point, joints, sleeve):
    side = 'r' if point.x > 0 else 'l'
    elbow, axis, across = limb_frame(joints, side, 'forearm', 'hand')
    offset = point - elbow
    distance = offset.dot(axis)
    section = offset - axis * distance
    if abs(point.x) < .18 or abs(distance) > .25 or section.length > .103:
        return Vector()
    mask = 1 - smooth(.060, .103, section.length)
    x = section.dot(across)
    y = section.y
    bicep = bell(distance + .116, .091)
    brachioradialis = bell(distance - .086, .065)
    hinge = bell(distance, .029)
    wrist = bell(distance - .209, .036)
    ulnar = smooth(.006, .024, x) * bell(distance - .205, .014)
    front = smooth(-.012, .028, y)
    back = smooth(.008, .035, -y)
    along = y * (.19 * bicep + .23 * brachioradialis - .09 * hinge - .12 * wrist)
    along += .0058 * hinge * (front * -.35 - back) * (1 - smooth(.022, .050, abs(x)))
    across_gain = x * (.12 * bicep + .17 * brachioradialis - .075 * wrist) + .0022 * ulnar
    delta = (Vector((0, along, 0)) + across * across_gain) * mask
    if sleeve:
        pleat = ridge(distance + .017 + .53 * y, .011) + .66 * ridge(distance - .012 - .45 * y, .013)
        delta += section.normalized() * .0034 * pleat * mask
    return delta


def relax_hand(obj, joints):
    keys = obj.data.shape_keys.key_blocks
    for v in obj.data.vertices:
        side = 'r' if v.co.x > 0 else 'l'
        origin, axis, cross = limb_frame(joints, side, 'forearm', 'hand')
        wrist = joints['hand_' + side]

        def relaxed(point, amount):
            d = (point - wrist).dot(axis)
            across = point.y - wrist.y
            fingers = smooth(.048, .143, d)
            thumb = smooth(.023, .052, across) * smooth(.028, .071, d)
            curl = smooth(.082, .149, d)
            palm = (point - origin).dot(cross)
            return point + Vector((0, (-.19 * fingers * (across + .008) - .17 * thumb * across
                                       + .0035 * curl) * amount, 0)) - cross * palm * .035 * curl * amount

        if keys:
            for key in keys:
                amount = .30 if key.name == 'Grip_' + side else 1.0
                key.data[v.index].co = relaxed(key.data[v.index].co, amount)
        v.co = relaxed(v.co, 1.0)
    obj.data.update()


def tailored_leg(p, joints, fitted):
    side = 'r' if p.x > 0 else 'l'
    x, y, z = p
    ankle, knee, hip = (joints[name + '_' + side] for name in ('foot', 'shin', 'thigh'))
    low = smooth(ankle.z, knee.z, z)
    high = smooth(knee.z, hip.z, z)
    centre_x = ankle.x + (knee.x - ankle.x) * low + (hip.x - knee.x) * high
    offset = x - centre_x
    depth = -.021 + .047 * smooth(.34, .73, z)
    ankle_mask = smooth(.097, .185, z)
    taper = ankle_mask * (1 - smooth(.827, .925, z))
    compression = (.105 if fitted else .135) * taper
    calf = bell(z - .337, .085)
    knee_form = bell(z - .505, .064)
    front, back = smooth(.003, .087, y), smooth(.017, .090, -y)
    crease = ridge(z - .517 + .41 * offset, .016) + .55 * ridge(z - .482 - .47 * offset, .017)
    lap = ridge(z - .824 - .49 * abs(offset), .016) + .64 * ridge(z - .789 - .42 * abs(offset), .013)
    ankle_break = ridge(z - .178 + .43 * abs(offset), .015) + .63 * ridge(z - .140 - .25 * offset, .013)
    taper_depth = -(y - depth) * compression * .85
    folds = (front * (.0061 * crease + .0053 * lap + .0059 * ankle_break)
             - back * (.0051 * ridge(z - .471 - .38 * offset, .015) + .0038 * ankle_break))
    shape = taper * (.0045 * front * knee_form - .0042 * back * calf)
    return Vector((-offset * compression + offset * .045 * calf, taper_depth + folds + shape, 0))


def edge_vertices(obj):
    count = Counter(tuple(sorted(edge)) for face in obj.data.polygons for edge in face.edge_keys)
    neighbours = {}
    for (u, v), hits in count.items():
        if hits == 1:
            neighbours.setdefault(u, []).append(v)
            neighbours.setdefault(v, []).append(u)
    return neighbours


def dress_armholes(tank, skin):
    borders = edge_vertices(tank)
    points = [v.co.copy() for v in tank.data.vertices]
    tree = surface_tree(skin.data)
    keys = tank.data.shape_keys.key_blocks
    for index, adjacent in borders.items():
        p = points[index]
        if not 1.32 < p.z < 1.52 or abs(p.x) < .089 or len(adjacent) != 2:
            continue
        middle = (points[adjacent[0]] + points[adjacent[1]]) * .5
        delta = (middle - p) * .40
        delta *= min(1, .0036 / max(delta.length, .0001))
        nearest, outward, _, distance = tree.find_nearest(p + delta, .014)
        if nearest is not None and outward.length > .5:
            gap = (p + delta - nearest).dot(outward)
            delta += outward * max(0, min(.0045, .004 - gap))
        tank.data.vertices[index].co += delta
        for key in keys:
            key.data[index].co += delta
    tank.data.update()


def finish_build_b_joins(meshes, joints):
    """Close the small skin and cloth intersections revealed by close views."""
    by_name = {o.name: o for o in meshes}
    faces = [obj for obj in meshes if obj.name.startswith('Face_')]
    trees = [surface_tree(obj.data) for obj in [by_name['Fashion_Torso_Skin'], *faces]]
    tank = by_name['Top_Fashion_Tank']
    points = [v.co.copy() for v in tank.data.vertices]
    for index, neighbours in edge_vertices(tank).items():
        p = points[index]
        if not 1.324 < p.z < 1.535 or abs(p.x) < .076 or len(neighbours) != 2:
            continue
        hits = [tree.find_nearest(p, .033) for tree in trees]
        nearest, outward, _, distance = min((hit for hit in hits if hit[0] is not None),
                                             key=lambda hit: hit[3], default=(None, None, None, None))
        if nearest is None:
            continue
        gap = (p - nearest).dot(outward)
        delta = outward * max(-.010, min(.012, .0036 - gap))
        for key in tank.data.shape_keys.key_blocks:
            key.data[index].co += delta
        tank.data.vertices[index].co += delta

    denim = [surface_tree(by_name[name].data) for name in ('Lower_jeans', 'Lower_fitjeans')]
    def tank_hem(p):
        blend = (1 - smooth(1.002, 1.079, p.z)) * (1 - smooth(.16, .205, abs(p.x)))
        if not blend:
            return Vector()
        offset = radial_fit(p, .018, denim, .31, True, .012) * blend
        floor = 1.000 + .0042 * math.cos(math.atan2(p.x, p.y - .018))
        offset.z = (floor - p.z) * .73 * (1 - smooth(1.004, 1.026, p.z))
        return offset

    adjust_basis(tank, tank_hem)

    def liner_delta(p):
        side = 'r' if p.x > 0 else 'l'
        ankle, knee = (joints[name + '_' + side] for name in ('foot', 'shin'))
        axis = ankle.lerp(knee, (p.z - ankle.z) / (knee.z - ankle.z))
        direction = Vector((p.x - axis.x, p.y - axis.y, 0))
        return -direction * .30 * smooth(.093, .169, p.z)

    adjust_basis(by_name['Ankle_Liner'], liner_delta)
    for obj in faces:
        mesh = obj.data
        eye_index = mesh.materials.find('hero_eye')
        eyes = {i for p in mesh.polygons if p.material_index == eye_index for i in p.vertices}
        for i in eyes:
            mesh.vertices[i].co.y -= .0014
            for key in mesh.shape_keys.key_blocks:
                key.data[i].co.y -= .0014
        mesh.update()


def raiseline(angle):
    return .977 + .005 * math.cos(angle) - .0023 * math.cos(angle * 2)


def ribbed_hem(jumper, rib, legs):
    """Finish the waist opening with a four-row knit binding and skin transfer."""
    def even_edge(p):
        if p.z > 1.017 or abs(p.x) > .215:
            return Vector()
        angle = math.atan2(p.x, p.y - .017)
        low = 1 - smooth(.976, 1.013, p.z)
        # Both faces of the folded shell settle into the sewn rib.
        return Vector((0, 0, (raiseline(angle) + .003 - p.z) * low))

    adjust_basis(jumper, even_edge)
    shell = surface_tree(jumper.data)
    under = [surface_tree(o.data) for o in legs]
    width = 72
    points = []
    for row, (rise, ease) in enumerate(((.001, .0005), (.003, .0038), (.016, .0033), (.019, -.001))):
        for column in range(width):
            angle = math.tau * column / width
            ray = Vector((math.sin(angle), math.cos(angle), 0))
            mid = Vector((0, .017, raiseline(angle) + max(.007, rise)))
            hit = shell.ray_cast(mid + ray * .28, -ray, .28)[0]
            if hit is None:
                mid.z += .012
                hit = shell.ray_cast(mid + ray * .28, -ray, .28)[0]
            point = (hit if hit is not None else mid + ray * .145) + ray * ease
            point.z = raiseline(angle) + rise
            if row != 3:
                point += radial_fit(point, .017, under, .30, True, .009)
            points.append(point)
    faces = [(row * width + i, (row + 1) * width + i, (row + 1) * width + (i + 1) % width,
              row * width + (i + 1) % width) for row in range(3) for i in range(width)]
    mesh = bpy.data.meshes.new('Topx_Jumper_Hem')
    mesh.from_pydata(points, [], faces)
    obj = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(rib.data.materials[0])
    uv = mesh.uv_layers.new(name='SurfaceUV')
    for i, poly in enumerate(mesh.polygons):
        poly.use_smooth = True
        row, col = divmod(i, width)
        for loop, (u, v) in zip(poly.loop_indices, ((col, row), (col, row + 1), (col + 1, row + 1), (col + 1, row))):
            uv.data[loop].uv = (u / width, .555 + .052 * v)
    mesh.update()
    source = SkinSurface(jumper)
    for v in mesh.vertices:
        sampled = source.at(v.co)
        blend_weights(obj, v, {name[2:]: weight for name, weight in sampled.items()}, 1.0)
    return obj



def refine_build_b(meshes, joints, texture_dir):
    by_name = {o.name: o for o in meshes}
    for obj in meshes:
        name = obj.name
        if name.startswith('Face_'):
            eye = sculpt_face(obj)
            surface_detail(obj, texture_dir, lambda p, n: face_surface(p, n, eye), .91)
        elif name.startswith(UPPER_BODY) and not name.endswith('_Skirt'):
            adjust_basis(obj, lambda p: arm_shape(p, joints, name == 'Top_Jumper'))
            if name in ('Skin_Hands', 'Courier_Gloves'):
                relax_hand(obj, joints)
        elif name in ('Lower_jeans', 'Lower_fitjeans'):
            adjust_basis(obj, lambda p: tailored_leg(p, joints, name == 'Lower_fitjeans'))
            surface_detail(obj, texture_dir, denim_surface, .83)
    dress_armholes(by_name['Top_Fashion_Tank'], by_name['Fashion_Torso_Skin'])
    top = by_name['Top_Jumper']
    trim = ribbed_hem(top, by_name['Topx_Jumper_Rib'],
                     [by_name[name] for name in ('Lower_jeans', 'Lower_fitjeans', 'Courier_Cargo', 'Courier_Chinos')])
    surface_detail(top, texture_dir, lambda p, n: knit_surface(p, n, joints), .89)
    surface_detail(by_name['Top_Fashion_Tank'], texture_dir, lambda p, n: knit_surface(p, n, joints), .79)
    finish_build_b_joins(meshes, joints)
    return trim
