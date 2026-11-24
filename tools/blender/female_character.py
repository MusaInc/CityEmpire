"""Build B's female anatomy and fit on the shared courier topology.

All dimensions are in metres. Body shaping happens before the wardrobe is
drafted, so garments sample the new body just as they do for Build A.
"""
import math

import numpy as np
from mathutils import Vector

from build_b_detail import dress_armholes, relax_hand, ribbed_hem
from build_b_surface import denim_surface, falloff, knit_surface, packed_image, pixels, surface_detail
from garment_kit import _dilate, raster_uv
from wardrobe_quality import adjust_basis, smooth


HEIGHTS = [0, .940, 1.169, 1.315, 1.457, 1.553, 1.659, 1.812]


def bell(x, radius):
    return math.exp(-(x / radius) ** 2)


def anatomy(x, depth, height):
    """Draft the rib cage, gluteal profile and shoulder slope from the torso."""
    side = abs(x)
    waist = bell(height - 1.109, .114)
    pelvis = bell(height - .996, .123)
    shoulder = bell(height - 1.475, .082) * smooth(.047, .174, side)
    neck = bell(height - 1.564, .060) * (1 - smooth(.043, .093, side))
    seat = bell(height - .966, .105) * bell(side - .089, .078)
    chest = bell(height - 1.354, .076) * bell(side - .070, .057)
    upper_back = bell(height - 1.376, .101) * bell(side, .134)
    return Vector((x * (1 + .055 * pelvis - .053 * waist - .090 * shoulder - .081 * neck),
                   depth - .019 * seat * smooth(.027, .103, -depth)
                   + .006 * chest * smooth(.032, .098, depth)
                   + .005 * upper_back * smooth(.011, .083, -depth) - .009 * neck,
                   height - .024 * shoulder))


def upper_arm(point, shoulder, axis):
    """Blend a lower deltoid cap into the elbow without changing the wrist."""
    along = (point - shoulder).dot(axis)
    radial = point - shoulder - axis * along
    cap = bell(along - .029, .048)
    biceps = bell(along - .130, .061)
    front = smooth(-.016, .032, radial.y)
    return point - radial * (.12 * bell(along - .044, .121)) + Vector((
        .045 * radial.x * cap, .003 * (front * biceps - (1 - front) * cap),
        .046 * radial.z * cap))


def hand_planes(point, wrist, axis, blend):
    """Keep the wrist transition and articulate the palm and knuckle arc."""
    delta = point - wrist
    length = delta.dot(axis)
    across = delta - axis * length
    dorsal = smooth(-.008, -.027, across.y)
    knuckle = bell(length - .083 - .31 * across.z, .011)
    heel = bell(length - .035, .025)
    point.y += blend * (.0018 * heel * (1 - dorsal) - .0019 * dorsal * knuckle)
    return point


def pelvis_blend(point, source_depth):
    falloff = bell(point.z - .921, .092) * bell(abs(point.x) - .090, .077)
    return point - Vector((0, .011 * falloff * smooth(.022, .094, -source_depth), 0))


def face_planes(points, face_ids, socket_ids, mouth_ids, reference=False):
    """Set the orbital, mid-face and mandibular planes before making the lids."""
    sockets = [sum((points[i] for i in ids), Vector()) / len(ids) for ids in socket_ids]
    mouth = sum((points[i] for i in mouth_ids), Vector()) / len(mouth_ids)
    eye = (sockets[0] + sockets[1]) * .5
    for i in face_ids:
        p = points[i]
        x, y, z = p
        side = abs(x)
        jaw = bell(z - (eye.z - .075), .031) * smooth(.028, .070, side)
        jaw *= smooth(eye.y - .119, eye.y - .051, y)
        lower_face = bell(z - (mouth.z - .020), .038) * smooth(mouth.y - .026, mouth.y + .009, y)
        cheek = bell(side - .054, .019) * bell(z - (eye.z - .030), .017)
        cheek *= smooth(eye.y - .047, eye.y + .013, y)
        nasal = bell(x, .015) * bell(z - (eye.z - .028), .019) * smooth(eye.y + .006, eye.y + .030, y)
        brow = bell(side - .037, .030) * bell(z - (eye.z + .018), .013)
        brow *= smooth(eye.y - .018, eye.y + .013, y)
        p.x *= 1 - .094 * jaw - .037 * lower_face + .025 * cheek
        p.y += .0038 * cheek - .0038 * nasal - .0038 * brow + .0042 * jaw
        p.z += .0038 * jaw + .0023 * lower_face
        for socket in sockets:
            dx = (x - socket.x) * (1 if socket.x > 0 else -1)
            dz = z - socket.z
            # Raise the lateral canthus and soften the lower lid without
            # scaling the eyeball or disturbing its centre.
            lid = bell(dx, .020) * bell(dz, .011) * smooth(socket.y + .003, socket.y + .010, y)
            p.z += lid * (.087 * dx - .076 * min(0, dz))
            p.y -= .0009 * lid
        if reference:
            # Distinct upper cheek, softly projecting lips and a tapered chin.
            chin = bell(x, .021) * bell(z - mouth.z + .032, .015)
            chin *= smooth(mouth.y - .028, mouth.y + .006, y)
            lip = bell(x, .023) * smooth(mouth.y + .003, mouth.y + .013, y)
            cupids_bow = bell(side - .007, .005) * bell(z - mouth.z - .006, .0037)
            lower_lip = bell(z - mouth.z + .004, .0049)
            p.y += .0031 * chin + lip * (.0021 * cupids_bow + .0028 * lower_lip)
            p.x += math.copysign(.0017 * cheek, x)


def hoops(face, eye_height, eye_depth):
    """Small gold hoops positioned at the sculpt's earlobes."""
    import bpy
    from wardrobe_quality import surface_tree

    skin = surface_tree(face.data)
    finish = bpy.data.materials.new('hero_earring_gold')
    finish.diffuse_color = (.47, .25, .066, 1)
    finish.use_nodes = True
    shader = finish.node_tree.nodes['Principled BSDF']
    shader.inputs['Base Color'].default_value = finish.diffuse_color
    shader.inputs['Metallic'].default_value = .76
    shader.inputs['Roughness'].default_value = .26
    result = []
    for side in (-1, 1):
        ray = Vector((side * .19, eye_depth - .062, eye_height - .052))
        ear = skin.ray_cast(ray, Vector((-side, 0, 0)), .14)[0]
        if ear is None:
            continue
        bpy.ops.mesh.primitive_torus_add(major_segments=22, minor_segments=6,
            major_radius=.0145, minor_radius=.0012, location=ear + Vector((side*.0015, 0, -.013)),
            rotation=(0, math.pi * .40 * side, 0))
        hoop = bpy.context.object
        hoop.name = 'Jules hoop'
        hoop.data.materials.append(finish)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        for poly in hoop.data.polygons:
            poly.use_smooth = True
        head = hoop.vertex_groups.new(name='b_head')
        head.add(list(range(len(hoop.data.vertices))), 1.0, 'REPLACE')
        result.append(hoop)
    return result


def warm_skin(colour, x, y, z, nx, ny, eye_z, eye_y):
    """Body-independent flesh tones that still respond to all player skin tints."""
    cheek = (bell_array(abs(x) - .051, .026) * bell_array(z - eye_z + .031, .020)
             * ((y - eye_y + .02) / .03).clip(0, 1))
    lid = bell_array(abs(x) - .035, .022) * bell_array(z - eye_z - .007, .006) * ny.clip(0, 1)
    temple = bell_array(abs(x) - .068, .035) * bell_array(z - eye_z - .010, .041) * abs(nx)
    colour *= (1 + .035 * cheek - .020 * lid - .009 * temple)[:, None]
    colour[:, 1] *= 1 - .036 * cheek - .012 * lid
    colour[:, 2] *= 1 - .020 * cheek + .010 * lid


def bell_array(x, radius):
    import numpy as np
    return np.exp(-(x / radius) ** 2)


def sculpt_portrait(mesh, eyes, mouth, lip_volume=1.0):
    """Sculpt the high-resolution cage while retaining its UVs and edge loops."""
    for vertex in mesh.vertices:
        p = vertex.co
        x, y, z = p
        eye = min(eyes, key=lambda centre: abs(x - centre.x))
        dx, dz = x - eye.x, z - eye.z
        front = smooth(eye.y - .023, eye.y + .009, y)
        arc = .010 * math.sqrt(max(0, 1 - (dx / .017) ** 2))
        aperture = bell(dx, .015) * front
        orbit = .0023 * bell(dz - arc - .001, .0037)
        orbit -= .0009 * bell(dz - arc - .006, .0024)
        orbit += .0015 * bell(dz + .53 * arc, .0037)
        p.y += orbit * aperture
        cheek = bell(abs(x) - .049, .016) * bell(z - eye.z + .027, .017)
        p.y += .0030 * cheek * front
        nasal = smooth(eye.y, eye.y + .033, y)
        p.y += .0031 * bell(x, .009) * bell(z - eye.z + .031, .013) * nasal
        p.y -= .0024 * bell(abs(x) - .011, .0041) * bell(z - eye.z + .043, .0046) * nasal
        lip_y = smooth(mouth.y + .003, mouth.y + .013, y)
        seam = mouth.z - .001 + .0015 * min(1, (x / .024) ** 2)
        lip = z - seam
        bow = .0016 * bell(abs(x) - .006, .004)
        p.y += lip_volume * lip_y * bell(x, .020) * (
            .0028 * bell(lip - .0039 - bow, .0034)
            + .0034 * bell(lip + .0048, .0047) - .0017 * bell(lip, .0016))
        p.y -= .0018 * lip_y * bell(x, .021) * bell(lip + .015, .0058)
    mesh.update()


def optimize_portrait(face):
    """Reduce the game mesh and transfer the eyelid pose from the sculpt."""
    import bpy
    from mathutils.bvhtree import BVHTree
    from mathutils.geometry import barycentric_transform

    study = face.copy()
    study.data = face.data.copy()
    study.name = 'Build B portrait sculpt'
    bpy.context.collection.objects.link(study)
    study.hide_render = True
    study.hide_set(True)
    source = study.data
    source.calc_loop_triangles()
    points = [vertex.co.copy() for vertex in source.vertices]
    triangles = [tuple(t.vertices) for t in source.loop_triangles]
    blink = [p.co - points[i] for i, p in enumerate(source.shape_keys.key_blocks['Blink'].data)]
    field = BVHTree.FromPolygons(points, triangles, all_triangles=True)

    face.shape_key_clear()
    model = face.data
    protected = {idx for poly in model.polygons
                 if not model.materials[poly.material_index].name.startswith('hero_skin_face')
                 for idx in poly.vertices}
    group_name = 'Portrait reduction'
    simplifiable = face.vertex_groups.new(name=group_name)
    rest = [v.index for v in model.vertices if v.index not in protected]
    simplifiable.add(rest, 1, 'REPLACE')
    face.hide_set(False)
    bpy.ops.object.select_all(action='DESELECT')
    face.select_set(True)
    bpy.context.view_layer.objects.active = face
    modifier = face.modifiers.new('Portrait detail budget', 'DECIMATE')
    modifier.ratio = .34
    modifier.vertex_group = group_name
    modifier.vertex_group_factor = 3
    face.modifiers.move(len(face.modifiers) - 1, 0)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    face.vertex_groups.remove(face.vertex_groups[group_name])
    face.shape_key_add(name='Basis')
    key = face.shape_key_add(name='Blink')
    for vertex in face.data.vertices:
        nearest, _, index, _ = field.find_nearest(vertex.co)
        a, b, c = triangles[index]
        if blink[a].length_squared or blink[b].length_squared or blink[c].length_squared:
            key.data[vertex.index].co += barycentric_transform(
                nearest, points[a], points[b], points[c], blink[a], blink[b], blink[c])
    return study


def finish_wardrobe(meshes, joints, texture_dir):
    """Fit exposed seams and carry their sampled skin weights into the trims."""
    lookup = {obj.name: obj for obj in meshes}
    for name in ('Skin_Hands', 'Courier_Gloves'):
        relax_hand(lookup[name], joints)
    for name in ('Lower_jeans', 'Lower_fitjeans'):
        surface_detail(lookup[name], texture_dir, denim_surface, .66)
    knit = lookup['Top_Jumper']
    surface_detail(knit, texture_dir, lambda p, n: knit_surface(p, n, joints), .73)
    band = ribbed_hem(knit, lookup['Topx_Jumper_Rib'],
                      [lookup[name] for name in ('Lower_jeans', 'Lower_fitjeans', 'Courier_Cargo', 'Courier_Chinos')])
    tank = lookup['Top_Fashion_Tank']
    dress_armholes(tank, lookup['Fashion_Torso_Skin'])
    surface_detail(tank, texture_dir, lambda p, n: knit_surface(p, n, joints), .61)
    _fit_neck_weights(meshes)
    _fit_ankle_liner(lookup['Ankle_Liner'], joints)
    return band


def _fit_neck_weights(meshes):
    # Split the influence between the throat and torso on the shared 17-bone
    # rig. Every face has the same weights through the collar.
    for obj in meshes:
        if not obj.name.startswith('Face_'):
            continue
        head = obj.vertex_groups['b_head']
        neck = obj.vertex_groups.get('b_neck') or obj.vertex_groups.new(name='b_neck')
        chest = obj.vertex_groups.get('b_chest') or obj.vertex_groups.new(name='b_chest')
        groups = [g for g in obj.vertex_groups if g not in (head, neck, chest)]
        for vertex in obj.data.vertices:
            p = vertex.co
            if p.z >= 1.617:
                continue
            throat = p.z + .28 * max(0, p.y - .046)
            skull = smooth(1.562, 1.611, throat)
            upper = smooth(1.466, 1.555, throat) * (1 - .70 * smooth(.049, .102, abs(p.x)))
            for group in groups:
                group.remove([vertex.index])
            for group, fraction in ((head, skull), (neck, (1 - skull) * upper),
                                    (chest, (1 - skull) * (1 - upper))):
                group.add([vertex.index], fraction, 'REPLACE')


def _fit_ankle_liner(obj, joints):
    def taper(p):
        side = 'l' if p.x < 0 else 'r'
        ankle, knee = (joints[name + '_' + side] for name in ('foot', 'shin'))
        centre = ankle.lerp(knee, (p.z - ankle.z) / (knee.z - ankle.z))
        return -Vector((p.x - centre.x, p.y - centre.y, 0)) * .29 * smooth(.092, .164, p.z)

    adjust_basis(obj, taper)


def _silhouette_delta(point):
    """Bring the head down and lift the shoulder girdle as separate contours."""
    x, y, z = point
    side = abs(x)
    throat = smooth(1.479, 1.622, z) * (1 - smooth(.052, .142, side))
    skull = smooth(1.558, 1.634, z + .29 * max(0, y - .053))
    neck = max(throat, skull)
    arm = smooth(.132, .242, side) * max(smooth(1.09, 1.24, z), smooth(.267, .353, side))
    deltoid = smooth(.089, .161, side) * bell(z - 1.461, .070)
    shoulder = max(arm, deltoid)
    return Vector((-math.copysign(.006 * shoulder, x), -.0035 * neck, .019 * shoulder - .049 * neck))


def _seat_arm_panels(meshes, joints):
    """Skin and cloth should articulate around the same shoulder surface."""
    from build_b_fit import blend_weights
    from garment_kit import SkinSurface

    skin_obj = next(obj for obj in meshes if obj.name == 'Fashion_Crop_Skin')
    skin = SkinSurface(skin_obj)
    skin_keys = skin_obj.data.shape_keys.key_blocks
    sleeveless = {'Top_Fashion_' + name for name in ('Tank', 'Fitteddress', 'Onedress', 'Squareneck', 'Vest')} | {'Top_Vest'}

    for obj in meshes:
        if not obj.name.startswith(('Top_', 'Topx_')) or obj.name.endswith('_Skirt'):
            continue
        for vertex in obj.data.vertices:
            p = vertex.co
            side = 'l' if p.x < 0 else 'r'
            shoulder, elbow = (joints[name + '_' + side] for name in ('upper_arm', 'forearm'))
            axis = (elbow - shoulder).normalized()
            off = p - shoulder
            along = off.dot(axis)
            radial = (off - axis * along).length
            amount = (smooth(.077, .123, abs(p.x))
                      * smooth(-.08, -.029, along) * (1 - smooth(.092, .158, along))
                      * (1 - smooth(.071, .109, radial)))
            if amount < .01:
                continue
            armhole = 0.0
            if obj.name in sleeveless:
                lift = max(0, min(1, (p.z - 1.364) / .145))
                width = .161 + .016 * bell(p.z - 1.30, .10) - (.027 if obj.name.endswith('Vest') else .051) * lift
                armhole = (1 - smooth(.004, .031, abs(abs(p.x) - width))) * smooth(1.30, 1.40, p.z)
            nearest, normal, triangle, distance = skin.tree.find_nearest(p, .056 if armhole > .1 else .037)
            if nearest is None:
                continue
            sampled = {name[2:]: weight for name, weight in skin.at(p).items() if name.startswith('b_')}
            if sampled:
                blend_weights(obj, vertex, sampled, max(amount * .86, armhole * .99))
            # The binding and its pose correction follow the actual skin rim.
            if armhole > .01:
                delta = (nearest + normal * .0038 - p) * armhole * .83
                if obj.data.shape_keys:
                    keys = obj.data.shape_keys.key_blocks
                    for key in keys:
                        key.data[vertex.index].co += delta
                    for direction in ('l', 'r'):
                        shape = 'Bend_Shoulder_' + direction
                        cloth_key = keys.get(shape)
                        if cloth_key is None:
                            continue
                        ids = skin.triangles[triangle]
                        influence = [1 / max(.001, (skin.positions[i] - nearest).length) for i in ids]
                        fold = sum(((skin_keys[shape].data[i].co - skin.positions[i]) * w
                                    for i, w in zip(ids, influence)), Vector()) / sum(influence)
                        old_fold = cloth_key.data[vertex.index].co - keys[0].data[vertex.index].co
                        cloth_key.data[vertex.index].co = keys[0].data[vertex.index].co + old_fold.lerp(fold, armhole)
                p += delta
            elif obj.name.startswith('Top_') and distance < .024:
                signed = (p - nearest).dot(normal)
                if signed > -.017:
                    delta = normal * amount * min(.012, max(0, .006 - signed))
                    if obj.data.shape_keys:
                        for key in obj.data.shape_keys.key_blocks:
                            key.data[vertex.index].co += delta
                    p += delta
        obj.data.update()


def _secure_layer_joins(meshes):
    for obj in meshes:
        if obj.name == 'Fashion_Slip':
            # The safety shorts follow the body inside the skirt's waist.
            adjust_basis(obj, lambda p: Vector((-.074 * p.x, -.12 * (p.y - .018), 0)))
        elif obj.name in ('Topx_Fashion_Cardigan_Under', 'Topx_Fashion_Jacket_Under'):
            adjust_basis(obj, lambda p: Vector((.16 * p.x, .002, 0)))
        elif obj.name.endswith('dress_Skirt'):
            key = obj.data.shape_keys.key_blocks['Hem_Seated']
            for vertex in obj.data.vertices:
                x, y, z = vertex.co
                join = bell(z - .964, .061)
                outward = Vector((x, y - .020, 0)).normalized()
                key.data[vertex.index].co += outward * (.009 * join)



_CROPPED_HEMS = {
    'Courier_Cargo': .195, 'Courier_Chinos': .173, 'Lower_jeans': .188,
    'Lower_joggers': .178, 'Lower_fitjeans': .202, 'Lower_leggings': .195,
}


def _crop_trouser_hems(meshes):
    from build_b_fit import blend_weights

    for obj in meshes:
        height = _CROPPED_HEMS.get(obj.name)
        if height is None:
            continue
        hem = min(v.co.z for v in obj.data.vertices)
        # Preserve the original cut, topstitching and cuffs. Redistribute
        # only the calf below the knee to arrive at the new ankle break.
        adjust_basis(obj, lambda p: Vector((0, 0, (height - hem) * (1 - smooth(hem, .455, p.z)))))
        for vertex in obj.data.vertices:
            pin = (1 - smooth(height + .016, .320, vertex.co.z)) * .95
            if pin > 0:
                side = 'l' if vertex.co.x < 0 else 'r'
                blend_weights(obj, vertex, {'shin_' + side: 1}, pin)


def _tuck_cropped_ankles(meshes, joints):
    """Keep skin concealed inside the trouser cuff through the stride."""
    from build_b_fit import blend_weights

    def tuck(p):
        side = 'l' if p.x < 0 else 'r'
        foot, knee = (joints[name + '_' + side] for name in ('foot', 'shin'))
        axis = foot.lerp(knee, (p.z - foot.z) / (knee.z - foot.z))
        inward = .67 * smooth(.145, .255, p.z)
        return Vector(((axis.x - p.x) * inward, (axis.y - p.y) * inward, 0))

    for obj in meshes:
        if obj.name not in ('Fashion_Cropped_Ankles', 'Fashion_Cropped_Barefeet'):
            continue
        adjust_basis(obj, tuck)
        for vertex in obj.data.vertices:
            pin = smooth(.092, .168, vertex.co.z)
            if pin > 0:
                side = 'l' if vertex.co.x < 0 else 'r'
                blend_weights(obj, vertex, {'shin_' + side: 1}, pin)


def anchor_leather_waist(obj):
    """Use torso joints for the jacket body when the arms reach forward."""
    from build_b_fit import blend_weights

    for vertex in obj.data.vertices:
        p = vertex.co
        if p.z >= 1.26 or abs(p.x) >= .215:
            continue
        # The sleeve crosses the waist's projection in the draft. Restrict
        # the correction to the jacket panel so it cannot pick up arm joints.
        depth = 1 - smooth(1.19, 1.26, p.z)
        side = 1 - smooth(.181, .215, abs(p.x))
        spine = smooth(1.008, 1.175, p.z)
        blend_weights(obj, vertex, {'hips': 1 - spine, 'spine': spine}, depth * side)


def fit_silhouette(meshes, rig, anatomy_study=None):
    """Fit the exposed neckline and shoulder join on the finished rig."""
    import bpy

    joints = {bone.name[2:]: bone.head_local.copy() for bone in rig.data.bones}
    _seat_arm_panels(meshes, joints)
    _secure_layer_joins(meshes)
    _crop_trouser_hems(meshes)
    _tuck_cropped_ankles(meshes, joints)
    reference = next(obj for obj in meshes if obj.name == 'Face_jules')
    crown = max(v.co.z + _silhouette_delta(v.co).z for v in reference.data.vertices)

    def fit(point):
        delta = _silhouette_delta(point)
        # Match the 168 cm turnaround above the waist. Keep the full head
        # volume and the original gameplay leg geometry and ground contact.
        delta.z -= (crown - 1.68) * smooth(1.115, 1.579, point.z)
        return delta

    for obj in meshes:
        if any(v.co.z > 1.04 for v in obj.data.vertices):
            adjust_basis(obj, fit)
    if anatomy_study is not None:
        adjust_basis(anatomy_study, fit)
        anatomy_study.parent = rig
        modifier = anatomy_study.modifiers.new('Shared gameplay rig', 'ARMATURE')
        modifier.object = rig

    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    edit = rig.data.edit_bones
    for name in ('chest', 'neck', 'head', 'upper_arm_l', 'forearm_l', 'hand_l', 'upper_arm_r', 'forearm_r', 'hand_r'):
        bone = edit['b_' + name]
        delta = fit(bone.head)
        bone.head += delta
        if name.startswith('hand') or name == 'head':
            bone.tail += delta
    edit['b_spine'].tail = edit['b_chest'].head
    edit['b_chest'].tail = edit['b_neck'].head
    edit['b_neck'].tail = edit['b_head'].head
    for side in ('l', 'r'):
        edit['b_upper_arm_' + side].tail = edit['b_forearm_' + side].head
        edit['b_forearm_' + side].tail = edit['b_hand_' + side].head
    bpy.ops.object.mode_set(mode='OBJECT')
    anchor_leather_waist(next(obj for obj in meshes if obj.name == 'Top_Fashion_Moto'))


def fit_jules_shoulders(rig, meshes, output):
    """Carry one shoulder contour through the skin, sewn panels and pose keys."""
    models = {obj.name: obj for obj in meshes}
    joints = rig.data.bones
    shoulder = joints['b_upper_arm_r'].head_local
    axis = (joints['b_forearm_r'].head_local - shoulder).normalized()

    def contour(p):
        x, y, z = p
        side = abs(x)
        if z < 1.20 or z > 1.49 or side > .37:
            return Vector()
        clavicle = bell(side - .105, .046) * bell(z - 1.435, .024) * smooth(.009, .048, y)
        upper = smooth(shoulder.z - .072, shoulder.z - .017, z)
        bridge = bell(side - .160, .037) * upper
        cap = bell(side - .225, .043) * upper
        sign = math.copysign(1, x)
        delta = Vector((-sign * .012 * cap, .0026 * clavicle, .010 * bridge - .010 * cap))
        across = Vector((side, y, z)) - shoulder
        along = across.dot(axis)
        radial = across - axis * along
        radial.x *= sign
        taper = (smooth(.137, .183, side) * smooth(1.20, 1.24, z)
                 * smooth(.006, .043, along) * (1 - smooth(.079, .161, along)))
        return delta - radial * .075 * taper

    def chest(p):
        return bell(abs(p.x) - .096, .050) * bell(p.z - 1.278, .046) * smooth(.119, .155, p.y)

    def clothing(p):
        return contour(p) - Vector((0, .003 * chest(p), 0))

    def torso_fit(p):
        # Relieve the skin where a fitted front panel passes over the bust.
        return contour(p) - Vector((0, .009 * chest(p), 0))

    for obj in meshes:
        name = obj.name
        if name.startswith(('Top_', 'Topx_')) and not name.endswith('_Skirt'):
            adjust_basis(obj, clothing)
        elif name in ('Fashion_Torso_Skin', 'Fashion_Crop_Skin'):
            adjust_basis(obj, torso_fit)
        elif name.startswith('Skin_Arms_') or name in ('Face_jules', 'Build B anatomy study'):
            adjust_basis(obj, contour)

    # The neck and chest are separate surfaces. Match the skin tint through
    # their meet while retaining the photographed neck above the collar.
    face, torso = models['Face_jules'], models['Fashion_Torso_Skin']
    skin = face.data.materials['hero_skin_face_jules'].node_tree.nodes['Principled BSDF']
    body = torso.data.materials['hero_skin_body'].node_tree.nodes['Principled BSDF']
    body_image = body.inputs['Base Color'].links[0].from_node.image
    size = body_image.size[0]
    pos, _, used = raster_uv(torso, size, material_index=0)
    shoulder_skin = used & (pos[..., 2] > 1.38) & (pos[..., 1] > .028) & (abs(pos[..., 0]) < .13)
    target = np.median(pixels(body_image)[shoulder_skin, :3], axis=0)
    colour = skin.inputs['Base Color'].links[0].from_node
    size = colour.image.size[0]
    pos, _, used = raster_uv(face, size, material_index=face.data.materials.find('hero_skin_face_jules'))
    rgb = pixels(colour.image)[..., :3].copy()
    lower = used & (pos[..., 2] < 1.515)
    weight = (1 - falloff(1.425, 1.515, pos[..., 2][lower]))[:, None]
    rgb[lower] += (target - rgb[lower]) * weight
    colour.image = packed_image(output / 'face_jules_albedo.png', _dilate(rgb, used, 8))
