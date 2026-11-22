"""Build B anatomy and garment finishing in the gameplay bind pose (metres)."""

import math

from mathutils import Matrix, Vector

from garment_kit import SkinSurface
from wardrobe_quality import TUCKED_TOPS, adjust_basis, smooth, surface_tree


# Shared by the skin, its clothing, and the arm pivots. The outer arm receives
# the same offset from deltoid to wrist so sleeve openings stay on the cuffs.
ARM_OFFSET = (.016, -.005, .037)
HEAD_PIVOT = Vector((0, .044, 1.584))
HEAD_OFFSET = Vector((0, -.023, -.009))
HEAD_ROTATION = Matrix.Rotation(math.radians(3.5), 3, 'X')
NECK_PIVOT = Vector((0, -.005, 1.514))


def head_delta(point):
    offset = point - HEAD_PIVOT
    offset.x *= 1.055
    offset.y *= 1.035
    offset.z *= 1.025
    return HEAD_PIVOT + HEAD_OFFSET + HEAD_ROTATION @ offset - point


def upper_body_delta(point):
    x, y, z = point
    side = abs(x)
    arm = smooth(.143, .268, side) * max(smooth(1.042, 1.189, z), smooth(.27, .40, side))
    shoulder = smooth(.065, .181, side) * smooth(1.234, 1.426, z)
    amount = max(arm, shoulder)
    dx, dy, dz = ARM_OFFSET
    # Narrow the rib cage below the shoulder line and carry the front and
    # back contours into the armholes.
    torso = (1 - smooth(.167, .231, side)) * smooth(1.019, 1.107, z) * (1 - smooth(1.37, 1.472, z))
    trunk = (1 - smooth(.10, .194, side)) * (1 - smooth(1.449, 1.54, z))
    chest = math.exp(-((z - 1.331) / .114) ** 2)
    taper = .056 + .052 * smooth(1.176, 1.31, z)
    deltoid = math.exp(-((side - .211) / .047) ** 2 - ((z - 1.432) / .059) ** 2)
    back = smooth(.015, .078, -y)
    front = smooth(.033, .117, y)
    return Vector((math.copysign(dx * amount, x) - taper * x * torso,
                   dy * amount + trunk * (.006 * front * chest - .008 * back * chest) - .072 * (y - .018) * torso,
                   dz * amount - .011 * deltoid))


def sleeve_delta(point, joints):
    side = 'l' if point.x < 0 else 'r'
    shoulder, wrist = (joints[name + '_' + side] for name in ('upper_arm', 'hand'))
    length = (wrist - shoulder).length
    axis = (wrist - shoulder) / length
    along = (point - shoulder).dot(axis)
    radial = point - shoulder - axis * along
    cap = smooth(.024, .121, along)
    cuff = 1 - smooth(length - .081, length + .009, along)
    sleeve = 1 - smooth(.078, .118, radial.length)
    taper = .148 - .043 * smooth(.205, .418, along)
    return -radial * (cap * cuff * sleeve * taper)


def head_and_neck_delta(point):
    x, y, z = point
    # The jaw turns with the skull. Beneath it, keep the throat and nape as
    # an oval section with a quiet transition into the clavicles.
    skull = smooth(1.538, 1.578, z + .33 * max(0, y - .065))
    neck = smooth(1.482, 1.537, z) * (1 - skull)
    throat = Vector((-x * .135, -.007 - (y - .026) * .12, -.010))
    return upper_body_delta(point) * (1 - skull) + throat * neck + head_delta(point) * skull


def neckline_delta(point):
    x, y, z = point
    dx, dy = x, y - .023
    radius = math.hypot(dx, dy)
    front = smooth(0, .052, dy)
    rear = smooth(0, .047, -dy)
    around = smooth(1.457, 1.534, z) * (1 - smooth(.080, .163, radius))
    return Vector((.31 * dx * around,
                   (.11 * dy - .008 * rear) * around,
                   -(.028 + .007 * front - .006 * rear) * around))


def ridge(distance, width):
    """The crest and trough of one cloth fold, along a sewn tension line."""
    return math.exp(-(distance / width) ** 2) - .43 * math.exp(-((distance - width) / width) ** 2)


def knit_delta(point):
    x, y, z = point
    side = abs(x)
    if z < 1.118 and side < .21:
        hem = (1 - smooth(1.002, 1.118, z)) * (1 - smooth(.166, .21, side))
        roll = ridge(z - 1.061 + .21 * x, .022)
        return Vector((-.027 * x * hem, -.085 * (y - .018) * hem + .0025 * roll, 0))
    if side < .17 and 1.002 < z < 1.451:
        front = smooth(.048, .105, y)
        back = smooth(.019, .064, -y)
        edge = smooth(.034, .106, side) * (1 - smooth(.139, .17, side))
        # Diagonal drag from the side seams and two soft gathers above the hem.
        shift = .015 if x < 0 else -.011
        waist = ridge(z - 1.111 - .43 * (side - .095) - shift, .019)
        armpit = ridge(z - 1.341 - .83 * (side - .128) + shift, .022)
        fall = math.exp(-((side - .122) / .055) ** 2)
        return Vector((0, front * (.006 * edge * waist + .004 * fall * armpit)
                       - back * (.005 * edge * waist + .004 * fall * armpit), 0))
    return Vector()


def jean_delta(point, joints):
    x, y, z = point
    side = 'l' if x < 0 else 'r'
    hip, knee = (joints[name + '_' + side] for name in ('thigh', 'shin'))
    fraction = max(0, min(1, (z - knee.z) / (hip.z - knee.z)))
    axis = knee.lerp(hip, fraction)
    upper_thigh = smooth(.53, .772, z) * (1 - smooth(.859, .965, z))
    hip_shell = math.exp(-((z - .925) / .093) ** 2)
    outseam = smooth(.101, .187, abs(x))
    seat = math.exp(-((z - .944) / .120) ** 2) * smooth(.026, .113, -y)
    waist = smooth(.966, 1.023, z)
    # Let the waistband rise gently at the back; taper the seat and upper
    # thigh into the leg without altering the centre seam or shoe opening.
    dx = -.145 * (x - axis.x) * upper_thigh * smooth(.018, .050, abs(x))
    dx -= x * (.074 * hip_shell * outseam + .029 * waist)
    dy = -.12 * (y - .02) * upper_thigh + .017 * seat - .063 * (y - .018) * waist
    dz = waist * (-.003 + .010 * smooth(.035, .102, -y))
    front = smooth(.036, .107, y)
    drape = math.exp(-((abs(x) - abs(axis.x)) / .066) ** 2)
    if z < .90:
        # Set in the denim whiskers under the pockets and ease over the knee.
        fly = ridge(z - .831 - .37 * (abs(x) - .1), .015)
        lap = ridge(z - .792 - .46 * (abs(x) - .1), .017)
        knee_fold = ridge(z - .525 + .40 * (abs(x) - abs(knee.x)), .019)
        cuff = ridge(z - .182 + .43 * (abs(x) - .166), .017)
        dy += front * drape * (.005 * fly + .0035 * lap + .004 * knee_fold + .0045 * cuff)
    return Vector((dx, dy, dz))


def blend_weights(obj, vertex, target, blend):
    groups = obj.vertex_groups
    weights = {g.group: g.weight * (1 - blend) for g in vertex.groups}
    for name, weight in target.items():
        group = groups.get('b_' + name)
        if group is None:
            group = groups.new(name='b_' + name)
        weights[group.index] = weights.get(group.index, 0) + weight * blend
    strongest = dict(sorted(weights.items(), key=lambda g: g[1], reverse=True)[:4])
    total = sum(strongest.values())
    for index, original in weights.items():
        if strongest.get(index, 0) > .00001:
            groups[index].add([vertex.index], strongest[index] / total, 'REPLACE')
        elif original or any(g.group == index for g in vertex.groups):
            groups[index].remove([vertex.index])


def radial_fit(point, centre_y, surfaces, spread, outer, margin):
    """Return a cloth adjustment along a horizontal fitting ray."""
    centre = Vector((0, centre_y, point.z))
    direction = point - centre
    radius = direction.length
    if radius < .022:
        return Vector()
    direction /= radius
    radii = []
    for tree in surfaces:
        hit = tree.ray_cast(centre + direction * spread, -direction, spread)[0]
        if hit is not None:
            radii.append((hit - centre).dot(direction))
    if not radii:
        return Vector()
    delta = max(0, max(radii) + margin - radius) if outer else min(0, min(radii) - margin - radius)
    return direction * max(-.051, min(.025, delta))


def finish_openings(meshes):
    by_name = {obj.name: obj for obj in meshes}
    faces = [surface_tree(obj.data) for name, obj in by_name.items() if name.startswith('Face_')]
    denim = [surface_tree(by_name[name].data) for name in ('Lower_jeans', 'Lower_fitjeans')]
    waist_shells = denim + [surface_tree(by_name[name].data)
                          for name in ('Courier_Cargo', 'Courier_Chinos', 'Lower_joggers')]

    def neckline_clearance(point):
        # Lift close crew necks across all five facial sculpts. The falloff
        # at the jaw keeps the rib on the neck even on faces with a low chin.
        neck = (1 - smooth(.099, .134, abs(point.x))) * smooth(1.462, 1.498, point.z)
        neck *= 1 - smooth(1.528, 1.548, point.z)
        if not neck:
            return Vector()
        delta = radial_fit(point, .012, faces, .23, True, .006) * neck
        shoulder = smooth(.057, .079, abs(point.x)) * (1 - smooth(.104, .131, abs(point.x)))
        if shoulder:
            origin = point + delta + Vector((0, 0, .034))
            hits = [tree.ray_cast(origin, Vector((0, 0, -1)), .050)[0] for tree in faces]
            lift = max((hit.z + .006 - point.z for hit in hits if hit is not None), default=0)
            delta.z = min(.020, max(0, lift)) * shoulder
        return delta

    def tucked_hem(point):
        waist = smooth(.928, .970, point.z) * (1 - smooth(1.022, 1.057, point.z))
        if waist and abs(point.x) < .22:
            return radial_fit(point, .018, denim, .31, False, .011) * waist
        return Vector()

    def jumper_hem(point):
        depth = 1 - smooth(1.014, 1.062, point.z)
        if depth and abs(point.x) < .21:
            delta = radial_fit(point, .018, waist_shells, .32, True, .013) * depth
            delta.z = .011 * (1 - smooth(.979, 1.012, point.z))
            return delta
        return Vector()

    for obj in meshes:
        if obj.name.startswith(CREW_NECKS):
            adjust_basis(obj, neckline_clearance)
        if obj.name in TUCKED_TOPS:
            adjust_basis(obj, tucked_hem)
            for vertex in obj.data.vertices:
                p = vertex.co
                waist = (1 - smooth(1.018, 1.060, p.z)) * smooth(.919, .970, p.z)
                if waist and abs(p.x) < .22:
                    blend_weights(obj, vertex, {'hips': 1}, waist * .94)
        if obj.name == 'Top_Jumper':
            adjust_basis(obj, jumper_hem)
            skin = SkinSurface(by_name['Lower_jeans'])
            for vertex in obj.data.vertices:
                p = vertex.co
                blend = 1 - smooth(1.017, 1.068, p.z)
                if blend and abs(p.x) < .21:
                    sampled = skin.at(p)
                    if sampled:
                        blend_weights(obj, vertex, {name[2:]: weight for name, weight in sampled.items()}, blend)


# These panels previously followed the extended neck. Scoop their cut and
# lower the binding together. The shaped necks on the fashion tops already
# sit on the chest and use the shared upper body adjustment only.
CREW_NECKS = ('Top_Tee', 'Topx_Tee_', 'Top_Jumper', 'Topx_Jumper_Rib')
HIGH_NECKS = ('Top_Collar', 'Top_Polo', 'Topx_Polo_', 'Top_Shirt', 'Topx_Shirt_',
              'Top_Hoodie', 'Topx_Hoodie_', 'Top_Bomber', 'Topx_Bomber_',
              'Top_Blazer', 'Topx_Blazer_', 'Top_Vest', 'Topx_Vest_')
UPPER_BODY = ('Top_', 'Topx_', 'Skin_Arms_', 'Fashion_Torso_Skin',
              'Fashion_Crop_Skin', 'Skin_Hands', 'Courier_Gloves')
HEAD_ATTACHMENTS = ('Hair_', 'Groom_', 'Eyes_', 'Eye_', 'EyeRim_', 'Lid_', 'Brow_', 'Acc_')


def fit_build_b(meshes, joints):
    """Fit the final wardrobe shells, then move the matching bind pivots."""
    for obj in meshes:
        name = obj.name
        if name.startswith(('Lower_jeans', 'Lower_fitjeans')):
            adjust_basis(obj, lambda p: jean_delta(p, joints))
            for vertex in obj.data.vertices:
                blend = smooth(.958, 1.008, vertex.co.z)
                if blend:
                    blend_weights(obj, vertex, {'hips': 1}, blend)
        elif name.startswith(('Face_', 'Mask_')):
            adjust_basis(obj, head_and_neck_delta)
            for vertex in obj.data.vertices:
                p = vertex.co
                level = p.z + .27 * max(0, p.y - .052)
                skull = smooth(1.533, 1.572, level)
                neck = smooth(1.481, 1.536, level) * (1 - skull) * (1 - smooth(.041, .086, abs(p.x)))
                blend_weights(obj, vertex, {'chest': 1 - neck - skull, 'neck': neck, 'head': skull}, .94)
        elif name.startswith(HEAD_ATTACHMENTS):
            adjust_basis(obj, head_delta)
        elif name.startswith(UPPER_BODY) and not name.endswith('_Skirt'):
            scoop = 1 if name.startswith(CREW_NECKS) else .57 if name.startswith(HIGH_NECKS) else 0
            def fit_cloth(point):
                delta = upper_body_delta(point) + sleeve_delta(point, joints)
                if scoop:
                    delta += neckline_delta(point) * scoop
                if name == 'Top_Jumper':
                    delta += knit_delta(point)
                return delta
            adjust_basis(obj, fit_cloth)
            if scoop:
                for vertex in obj.data.vertices:
                    p = vertex.co
                    blend = smooth(1.450, 1.528, p.z) * (1 - smooth(.076, .136, abs(p.x)))
                    if blend:
                        blend_weights(obj, vertex, {'chest': .95, 'neck': .05}, .88 * blend)

    finish_openings(meshes)
    for side, sign in (('l', -1), ('r', 1)):
        for bone in ('upper_arm_', 'forearm_', 'hand_'):
            joints[bone + side] += Vector((sign * ARM_OFFSET[0], *ARM_OFFSET[1:]))
        joints['clavicle_' + side] += Vector((sign * .004, -.002, -.012))
    joints['neck'] = NECK_PIVOT.copy()
    joints['head'] += head_delta(joints['head'])


def neck_anatomy_delta(point):
    x, y, z = point
    side = abs(x)
    mid = math.exp(-((z - 1.541) / .023) ** 2)
    base = (1 - smooth(.065, .108, side)) * (1 - smooth(1.577, 1.604, z))
    rear = 1 - smooth(-.018, .038, y)
    widen = 1 - smooth(.067, .101, y)
    # Fill the nape and the sides where the first fit pinched in. The chin
    # and the visible part of the throat keep separate, rounded profiles.
    width = .185 * x * mid * widen * base
    depth = -.0132 * mid * rear * base
    entry = .021 + .023 * smooth(1.490, 1.558, z)
    tendon = math.exp(-((side - entry) / .013) ** 2 - ((z - 1.522) / .037) ** 2)
    tendon *= smooth(.022, .053, y) * (1 - smooth(.066, .088, y))
    notch = math.exp(-(x / .020) ** 2 - ((z - 1.489) / .014) ** 2)
    depth += .0028 * tendon - .0018 * notch * smooth(.034, .059, y)
    under_jaw = math.exp(-((z - 1.554) / .014) ** 2 - ((y - .074) / .032) ** 2)
    under_jaw *= 1 - smooth(.036, .070, side)
    ridge = math.exp(-((z - 1.493) / .022) ** 2 - ((side - .070) / .040) ** 2)
    return Vector((width, depth, .003 * ridge * rear - .0036 * under_jaw))


def fit_build_b_neck(meshes, joints):
    """Finish the cervical shape, its skin weights and the adjoining garment rims."""
    faces = [obj for obj in meshes if obj.name.startswith('Face_')]
    for obj in meshes:
        name = obj.name
        if not (name.startswith(('Face_', 'Mask_')) or name in ('Fashion_Torso_Skin', 'Fashion_Crop_Skin')):
            continue
        adjust_basis(obj, neck_anatomy_delta)
        for vertex in obj.data.vertices:
            x, y, z = vertex.co
            side = abs(x)
            if not 1.465 < z < 1.607 or side > .128:
                continue
            amount = smooth(1.465, 1.486, z) * (1 - smooth(.095, .128, side))
            jaw = smooth(.069, .093, y) * smooth(1.525, 1.553, z)
            head = max(jaw, smooth(1.545, 1.591, z + .20 * max(0, y - .055)))
            neck = (1 - head) * smooth(1.478, 1.523, z) * (1 - smooth(.051, .106, side))
            shoulder = (1 - head - neck) * .22 * smooth(.053, .116, side)
            clavicle = 'clavicle_r' if x > 0 else 'clavicle_l'
            blend_weights(obj, vertex, {'chest': 1 - head - neck - shoulder,
                                        'neck': neck, 'head': head, clavicle: shoulder}, amount)

    contours = [surface_tree(face.data) for face in faces]

    def collar_delta(p, fitted_crew):
        rise = smooth(1.463, 1.493, p.z) * (1 - smooth(1.534, 1.552, p.z))
        side = abs(p.x)
        near = 1 - smooth(.079, .124, side)
        if not rise or not near:
            return Vector()
        delta = radial_fit(p, .008, contours, .187, True, .0038) * rise * near
        shoulder = smooth(.053, .077, side) * (1 - smooth(.112, .136, side)) * rise
        if fitted_crew and shoulder:
            start = p + delta + Vector((0, 0, .027))
            hits = [tree.ray_cast(start, Vector((0, 0, -1)), .042)[0] for tree in contours]
            gap = max((hit.z + .0065 - p.z for hit in hits if hit is not None), default=0)
            delta.z += min(.017, max(0, gap)) * shoulder
        return delta

    for obj in meshes:
        if obj.name.startswith((*CREW_NECKS, *HIGH_NECKS, 'Top_Fashion_', 'Topx_Fashion_')):
            fitted_crew = obj.name.startswith(CREW_NECKS)
            adjust_basis(obj, lambda p: collar_delta(p, fitted_crew))

    # Set the rotation axes inside the new section and beneath the skull.
    joints['neck'] += Vector((0, .0055, -.0035))
    joints['head'] += Vector((0, .013, .001))


def finish_build_b_nape(meshes):
    """Set a smooth rear neckline between the trapezius and the skull base."""
    low, high = 1.502, 1.614
    faces = {obj.name: obj for obj in meshes if obj.name.startswith('Face_')}
    for face in faces.values():
        skin = surface_tree(face.data)
        steps = 48
        levels = [low + (high - low) * i / steps for i in range(steps + 1)]
        back = [skin.ray_cast(Vector((0, -.22, z)), Vector((0, 1, 0)), .25)[0] for z in levels]
        if any(hit is None for hit in back):
            continue
        depth = [hit.y for hit in back]
        start, stop = depth[0], depth[-1]
        reach = stop - start

        def smooth_nape(p):
            if not low < p.z < high or p.y > .029:
                return Vector()
            t = (p.z - low) / (high - low)
            sample = t * steps
            index = min(steps - 1, int(sample))
            original = depth[index] + (depth[index + 1] - depth[index]) * (sample - index)
            # Monotone Hermite contour. The small lower tangent meets the
            # shoulder, and the larger upper tangent continues into the skull.
            profile = start + reach * (-2 * t**3 + 3 * t**2 + .22 * (t**3 - 2*t*t + t) + 2.06 * (t**3 - t*t))
            lateral = 1 - smooth(.032, .092, abs(p.x))
            rear = 1 - smooth(-.011, .032, p.y)
            return Vector((0, (profile - original) * lateral * rear, 0))

        adjust_basis(face, smooth_nape)
        for vertex in face.data.vertices:
            p = vertex.co
            if not 1.535 < p.z < 1.604 or p.y > .018 or abs(p.x) > .079:
                continue
            amount = smooth(1.535, 1.551, p.z) * (1 - smooth(.052, .079, abs(p.x)))
            amount *= 1 - smooth(-.006, .018, p.y)
            head = smooth(1.549, 1.608, p.z)
            blend_weights(face, vertex, {'head': head, 'neck': 1 - head}, amount * .57)

    contours = [surface_tree(face.data) for face in faces.values()]
    def clear_rear_binding(p):
        if not 1.495 < p.z < 1.547 or p.y >= .010:
            return Vector()
        near = (1 - smooth(-.024, .010, p.y)) * (1 - smooth(.061, .102, abs(p.x)))
        return radial_fit(p, .014, contours, .182, True, .0033) * near

    for obj in meshes:
        if obj.name.startswith((*CREW_NECKS, *HIGH_NECKS, 'Top_Fashion_')):
            adjust_basis(obj, clear_rear_binding)
