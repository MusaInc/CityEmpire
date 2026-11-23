"""Headless Blender review renders of the exported hero (assets/models/character.glb).

blender -b --factory-startup --python tools/blender/render_character_review.py -- <glb> <outdir> [outfits] [views]

Imports the shipping GLB (so what is reviewed is what the game loads), shows
one outfit's variant meshes (the same selection rules as CharacterRig.
_show_variants), and renders fixed cameras under fixed lights with Cycles on
the CPU: a material pass and a clay pass (uniform grey: geometry only, which
is what this reconstruction is judged on). Same cameras every milestone.
"""
import bpy, sys, math, json
from pathlib import Path
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))

argv = sys.argv[sys.argv.index('--') + 1:]
GLB, OUT = argv[0], argv[1]
WANT = argv[2].split(',') if len(argv) > 2 else ['orange_shirt', 'tee_cap']
VIEWS_WANTED = argv[3].split(',') if len(argv) > 3 else None

# outfit -> (face, hair style, top cut, extra accessory meshes, colours)
OUTFITS = {
    'orange_shirt': dict(face='ade', hair='crop', top='shirt', acc=['shades'], top_col=(0.85, 0.51, 0.17), pants=(0.24, 0.27, 0.19)),
    'ade_plain': dict(face='ade', hair='crop', top='tee', acc=[], top_col=(.57, .58, .60), pants=(.19, .23, .28)),
    'tee_cap': dict(face='theo', hair='crop', top='tee', acc=['cap'], top_col=(0.25, 0.43, 0.70), pants=(0.79, 0.74, 0.61)),
    'polo_phones': dict(face='kai', hair='fade', top='polo', acc=['headphones'], top_col=(0.95, 0.95, 0.93), pants=(0.12, 0.18, 0.29)),
    'blazer': dict(face='malik', hair='crop', top='blazer', acc=['shades'], top_col=(0.1, 0.11, 0.13), pants=(0.1, 0.11, 0.13)),
    'rio_tee': dict(face='rio', hair='curls', top='tee', acc=[], top_col=(0.79, 0.43, 0.57), pants=(0.12, 0.18, 0.29)),
    'sam_shirt': dict(face='sam', hair='pixie', top='shirt', acc=[], lower='chinos',
                      shoes='boots', top_col=(.72, .62, .67), pants=(.15, .19, .29)),
    'noa_dress': dict(face='noa', hair='ponytail', top='fashion_fitteddress', acc=[], lower='dress',
                      shoes='heels', top_col=(.49, .29, .43), pants=(.15, .19, .29)),
    'one_shoulder': dict(face='noa', hair='bun', top='fashion_onedress', acc=[], lower='dress',
                         shoes='heels', top_col=(.47, .17, .29), pants=(.15, .19, .29)),
    'square_neck': dict(face='sam', hair='pixie', top='fashion_squareneck', acc=[], lower='fitjeans',
                        shoes='sandals', top_col=(.47, .36, .26), pants=(.19, .25, .34)),
    'jules_moto': dict(face='jules', hair='bun', top='fashion_moto', acc=[], lower='midiskirt',
                       shoes='streettrainers', top_col=(.45, .24, .17), pants=(.14, .14, .17),
                       shoe_col=(.15, .28, .8)),
}
OUTFITS['red_leather'] = dict(OUTFITS['jules_moto'], top='fashion_racer', lower='widejeans',
    top_col=(.50, .21, .22), pants=(.16, .18, .22), shoe_col=(.88,.87,.84))
OUTFITS['grey_lounge'] = dict(OUTFITS['jules_moto'], top='fashion_pullover', lower='bikershorts',
    top_col=(.45, .45, .45), pants=(.13, .13, .15), shoe_col=(.90,.89,.87))
OUTFITS['jules_seated'] = dict(OUTFITS['jules_moto'], seat=True)
OUTFITS['anatomy'] = dict(OUTFITS['jules_moto'], anatomy=True)
OUTFITS['ade_bomber'] = dict(OUTFITS['ade_plain'], top='bomber', top_col=(.26,.32,.35))
OUTFITS['ade_expression'] = dict(OUTFITS['ade_bomber'], expression='Focus')
OUTFITS['jules_expression'] = dict(OUTFITS['jules_moto'], expression='Smile')
OUTFITS['ade_blink'] = dict(OUTFITS['ade_bomber'], expression='Blink')
OUTFITS['jules_blink'] = dict(OUTFITS['jules_moto'], expression='Blink')
SKIN = {'ade': (0.52, 0.36, 0.265), 'theo': (0.78, 0.6, 0.5), 'kai': (0.6, 0.43, 0.32), 'malik': (0.42, 0.27, 0.18), 'ren': (0.72, 0.55, 0.42),
        'rio': (0.36, 0.22, 0.15), 'sam': (0.9, 0.74, 0.64), 'noa': (0.79, 0.64, 0.51),
        'jules': (.72, .53, .40)}
HAIR = {'sam': (.31, .18, .10), 'theo': (.25, .15, .10), 'jules': (.112, .073, .055)}

if GLB.endswith('.blend'):
    bpy.ops.wm.open_mainfile(filepath=GLB)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
armature = next((obj for obj in bpy.context.scene.objects if obj.type == 'ARMATURE'), None)

sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = 24
sc.cycles.use_denoising = True
sc.render.resolution_x, sc.render.resolution_y = 720, 900
sc.render.film_transparent = False
sc.view_settings.view_transform = 'AgX'
sc.view_settings.look = 'AgX - Medium High Contrast'
world = bpy.data.worlds.new('w')
sc.world = world
world.use_nodes = True
world.node_tree.nodes['Background'].inputs[0].default_value = (0.55, 0.6, 0.68, 1)
world.node_tree.nodes['Background'].inputs[1].default_value = 0.55


def light(name, kind, loc, rot, energy, size=1.0, color=(1, 1, 1)):
    d = bpy.data.lights.new(name, kind)
    d.energy = energy
    d.color = color
    if kind == 'AREA':
        d.size = size
    if kind == 'SUN':
        d.angle = math.radians(3)
    o = bpy.data.objects.new(name, d)
    o.location = loc
    o.rotation_euler = [math.radians(a) for a in rot]
    sc.collection.objects.link(o)


light('key', 'SUN', (0, 0, 5), (50, 0, 145), 3.2, color=(1, 0.96, 0.9))
light('fill', 'AREA', (-2.5, 2.5, 1.6), (70, 0, -135), 120, 3, (0.85, 0.9, 1))
light('rim', 'AREA', (1.5, -2.5, 2.2), (-60, 0, 30), 160, 2)
bpy.ops.mesh.primitive_plane_add(size=30)
floor = bpy.context.object
fm = bpy.data.materials.new('floor')
fm.use_nodes = True
fm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.36, 0.37, 0.39, 1)
fm.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.9
floor.data.materials.append(fm)

clay = bpy.data.materials.new('clay')
clay.use_nodes = True
clay.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.62, 0.62, 0.62, 1)
clay.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.55

cam_data = bpy.data.cameras.new('cam')
cam = bpy.data.objects.new('cam', cam_data)
sc.collection.objects.link(cam)
sc.camera = cam
# The character faces +Y in Blender (glTF -Z, Godot forward).
# name: (camera offset from target, target, lens mm)
VIEWS = {
    'front': (Vector((0, 4.2, 0.1)), Vector((0, 0, 0.92)), 50),
    'three_quarter': (Vector((2.9, 3.0, 0.3)), Vector((0, 0, 0.92)), 50),
    'side': (Vector((4.2, 0, 0.1)), Vector((0, 0, 0.92)), 50),
    'rear': (Vector((0, -4.2, 0.2)), Vector((0, 0, 0.92)), 50),
    'face': (Vector((0.22, 0.95, 0.03)), Vector((0, 0.05, 1.61)), 85),
    'face_side': (Vector((0.95, 0.15, 0.03)), Vector((0, 0.03, 1.61)), 85),
    'collar': (Vector((0.15, 0.85, 0.12)), Vector((0, 0.03, 1.5)), 60),
    'shoulder': (Vector((0.75, 0.55, 0.18)), Vector((0.2, 0, 1.45)), 60),
    'cuff': (Vector((0.6, 0.5, 0.05)), Vector((0.55, 0.0, 0.95)), 60),
    'hair': (Vector((0.52, -0.75, 0.17)), Vector((0, -.04, 1.64)), 83),
    'jacket_detail': (Vector((.29, .80, .05)), Vector((0, .02, 1.30)), 55),
    'shoe_detail': (Vector((.26, .88, .23)), Vector((0, .07, .09)), 55),
    'seated': (Vector((2.0, 3.4, .37)), Vector((0, .13, .85)), 56),
}
CLAY_VIEWS = ['front', 'three_quarter', 'side', 'rear', 'face', 'shoulder', 'cuff']


def show(spec):
    f, hs, top = spec['face'], spec['hair'], spec['top']
    lower = spec.get('lower', 'chinos' if top in ('shirt', 'blazer') else 'cargo')
    shoes = spec.get('shoes', 'trainers')
    bare = lower in ('dress', 'miniskirt', 'midiskirt', 'maxiskirt', 'tailoredshorts')
    barefoot = shoes == 'sandals' and (bare or lower == 'shorts')
    cropped = any(o.name == 'Fashion_Cropped_Ankles' for o in meshes) and lower in (
        'cargo', 'chinos', 'jeans', 'joggers', 'fitjeans', 'leggings')
    for o in meshes:
        n = o.name
        vis = True
        if spec.get('anatomy'):
            vis = n == 'Build B anatomy study'
        elif n in ('Build B anatomy study', 'Build B portrait sculpt'):
            vis = False
        elif n == 'Top_Collar':
            vis = top in ('long', 'tq', 'short', 'vest')
        elif n.startswith('Top_'):
            vis = n.lower() == 'top_' + top
        elif n.startswith('Topx_'):
            vis = n.lower().startswith('topx_' + top + '_')
        elif n.startswith('Skin_Arms_'):
            vis = n.lower() == 'skin_arms_' + top
        elif n.startswith('Skin_Hands'):
            vis = True
        elif n == 'Courier_Gloves':
            vis = not any(m.name.startswith('Skin_Hands') for m in meshes)
        elif n.startswith('Face_'):
            vis = n == 'Face_' + f
        elif n.startswith(('Hair_', 'Groom_')):
            vis = n.endswith('_%s_%s' % (hs, f))
            if n.startswith('Groom_') and any(a in ('cap', 'beanie') for a in spec['acc']):
                vis = False
        elif n == 'Courier_Chinos':
            vis = lower == 'chinos'
        elif n == 'Courier_Cargo' or n.startswith('Cargo_gusset'):
            vis = lower == 'cargo'
        elif n.startswith('Lower_'):
            vis = n.split('_')[1] == lower and not (barefoot and n == 'Lower_shorts_Legs')
        elif n in ('Courier_Trainers', 'Courier_Soles', 'Courier_TrainerTongues', 'Courier_TrainerLaces'):
            vis = shoes == 'trainers'
        elif n.startswith('Footwear_'):
            vis = n == 'Footwear_' + shoes
        elif n == 'Ankle_Liner':
            vis = not cropped and not bare and lower not in ('shorts', 'bikershorts') and shoes not in ('sandals', 'boots')
        elif n == 'Fashion_Cropped_Ankles':
            vis = cropped and shoes != 'sandals'
        elif n == 'Fashion_Cropped_Barefeet':
            vis = cropped and shoes == 'sandals'
        elif n == 'Fashion_Torso_Skin':
            vis = top == 'vest' or (top.startswith('fashion_') and top not in ('fashion_crop', 'fashion_moto', 'fashion_pullover', 'fashion_racer'))
        elif n == 'Fashion_Racer_Midriff':
            vis = top == 'fashion_racer'
        elif n == 'Fashion_Crop_Skin':
            vis = top == 'fashion_crop'
        elif n == 'Fashion_Legs':
            vis = bare and not barefoot
        elif n == 'Fashion_Slip':
            vis = bare and lower != 'tailoredshorts'
        elif n == 'Fashion_Biker_Legs':
            vis = lower == 'bikershorts' and shoes != 'sandals'
        elif n == 'Fashion_Biker_Barefeet':
            vis = lower == 'bikershorts' and shoes == 'sandals'
        elif n == 'Fashion_Lounge_Socks':
            vis = lower == 'bikershorts' and shoes in ('trainers', 'streettrainers')
        elif n == 'Fashion_Feet':
            vis = shoes == 'sandals' and not barefoot and not cropped and lower != 'bikershorts'
        elif n == 'Fashion_Barefoot_Legs':
            vis = barefoot
        elif n == 'Courier_Waistband':
            vis = top == 'shirt'
        elif n.startswith('Mask_'):
            vis = False
        elif n.startswith('Acc_'):
            vis = any(n == 'Acc_%s_%s' % (a, f) or n.startswith('Acc_%s_%s_' % (a, f)) for a in spec['acc'])
        o.hide_render = not vis
        o.hide_viewport = not vis
        o.hide_set(not vis)


def pose(spec):
    if armature is None or not GLB.endswith('.blend'):
        return
    for bone in armature.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    if spec.get('anatomy'):
        return
    face = bpy.data.objects.get('Face_' + spec['face'])
    if face is not None and face.data.shape_keys is not None:
        for expression in ('Smile', 'Focus', 'Blink'):
            key = face.data.shape_keys.key_blocks.get(expression)
            if key is not None:
                key.value = float(spec.get('expression') == expression) * (1 if expression == 'Blink' else .85)
    for side, sign in [('l', -1), ('r', 1)]:
        arm = armature.pose.bones['b_upper_arm_' + side]
        axes = arm.bone.matrix_local.to_3x3().normalized()
        lowered = Matrix.Rotation(math.radians(27) * sign, 3, 'Y')
        arm.rotation_mode = 'QUATERNION'
        arm.rotation_quaternion = (axes.inverted() @ lowered @ axes).to_quaternion()
    if spec.get('seat'):
        from wardrobe_quality import seated_leg_transforms
        joints = {bone.name[2:]: bone.head_local.copy() for bone in armature.data.bones}
        transforms = seated_leg_transforms(joints)
        for part in ('thigh', 'shin', 'foot'):
            for side in ('l', 'r'):
                name = 'b_' + part + '_' + side
                rotation, translation = transforms[name]
                target = rotation.to_4x4()
                target.translation = translation
                armature.pose.bones[name].matrix = target @ armature.data.bones[name].matrix_local
                bpy.context.view_layer.update()
    skirt = bpy.data.objects.get('Lower_midiskirt')
    if skirt is not None and skirt.data.shape_keys is not None:
        skirt.data.shape_keys.key_blocks['Hem_Seated'].value = float(spec.get('seat', False))
    legs = bpy.data.objects.get('Fashion_Legs')
    if legs is not None and legs.data.shape_keys is not None:
        clearance = legs.data.shape_keys.key_blocks.get('MidiSeatClearance')
        if clearance is not None:
            clearance.value = float(spec.get('seat', False) and spec.get('lower') == 'midiskirt')


def lin(c):
    # Shop colours are sRGB; Blender colour inputs are linear.
    return tuple(((x + .055) / 1.055) ** 2.4 if x > .04045 else x / 12.92 for x in c)


def tint_review_iris(material, shader, pigment):
    tree = material.node_tree
    mix = tree.nodes.get('Review iris')
    if mix is not None:
        mix.inputs[2].default_value = (*lin(pigment), 1)
        return
    base = shader.inputs['Base Color']
    if not base.links:
        return
    source = base.links[0].from_socket
    uv = tree.nodes.new('ShaderNodeTexCoord')
    distance = tree.nodes.new('ShaderNodeVectorMath')
    distance.operation = 'DISTANCE'
    distance.inputs[1].default_value = (.5, .5, 0)
    tree.links.new(uv.outputs['UV'], distance.inputs[0])
    rim = tree.nodes.new('ShaderNodeMapRange')
    rim.inputs['From Min'].default_value = .225
    rim.inputs['From Max'].default_value = .252
    rim.inputs['To Min'].default_value = 1
    rim.inputs['To Max'].default_value = 0
    tree.links.new(distance.outputs['Value'], rim.inputs['Value'])
    mix = tree.nodes.new('ShaderNodeMixRGB')
    mix.name = 'Review iris'
    mix.blend_type = 'MULTIPLY'
    mix.inputs[2].default_value = (*lin(pigment), 1)
    tree.links.new(source, mix.inputs[1])
    tree.links.new(rim.outputs[0], mix.inputs[0])
    tree.links.new(mix.outputs[0], base)


def review_scalp(material, shader, uv_layer, skin, short=False):
    """Read the same packed coverage that controls the in-game hairline."""
    nodes, links = material.node_tree.nodes, material.node_tree.links
    if nodes.get('Review scalp density'):
        return
    uv = nodes.new('ShaderNodeUVMap')
    uv.name = 'Review scalp density'
    uv.uv_map = uv_layer
    split = nodes.new('ShaderNodeSeparateXYZ')
    links.new(uv.outputs[0], split.inputs[0])
    curve = nodes.new('ShaderNodeMapRange')
    curve.inputs['From Min'].default_value = .018 if short else .025
    curve.inputs['From Max'].default_value = .943 if short else .57
    links.new(split.outputs['Y'], curve.inputs['Value'])
    if short:
        links.new(curve.outputs['Result'], shader.inputs['Alpha'])
        return
    base = shader.inputs['Base Color']
    blend = nodes.new('ShaderNodeMixRGB')
    blend.inputs[1].default_value = (*lin(skin), 1)
    links.new(base.links[0].from_socket, blend.inputs[2])
    links.new(curve.outputs['Result'], blend.inputs[0])
    links.new(blend.outputs[0], base)


def tint(spec):
    # Approximate the game's tints on the imported materials (white-ish
    # authored colours are multiplied by the outfit colour, as in hero_pbr).
    seen = set()
    for o in meshes:
        if o.hide_render:
            continue
        for slot in o.material_slots:
            m = slot.material
            if m is None or not m.use_nodes or m in seen:
                continue
            seen.add(m)
            p = m.node_tree.nodes.get('Principled BSDF')
            if p is None:
                continue
            nm = m.name
            col = None
            if nm == 'hero_eye':
                tint_review_iris(m, p, (.57, .39, .22) if spec['face'] == 'jules' else (.42, .30, .19))
            if nm in ('hero_shirt', 'hero_tee', 'hero_knit', 'hero_blazer', 'hero_fleece', 'hero_bomber', 'hero_rib', 'hero_lapel', 'hero_top', 'hero_shirt_trim', 'hero_buttonhole'):
                col = spec['top_col']
            elif nm == 'hero_racer_cotton':
                col = (.95, .94, .90)
            elif nm.startswith('hero_fashion_top_'):
                col = spec['top_col']
            elif nm.startswith('hero_fashion_bottom_'):
                col = spec['pants']
            elif nm.startswith('hero_fashion_shoe_'):
                col = spec.get('shoe_col', (.62, .6, .57))
            elif nm == 'hero_streettrainer_upper':
                col = spec.get('shoe_col', (.62, .6, .57))
            elif nm.startswith('hero_skin'):
                col = SKIN[spec['face']]
            elif nm == 'hero_lid_rim':
                col = tuple(value * .88 for value in SKIN[spec['face']])
            elif nm.startswith('hero_hair') or nm in ('hero_brow', 'hero_lash'):
                col = HAIR.get(spec['face'], (.13, .086, .060))
            elif nm == 'hero_glove':
                sk = SKIN[spec['face']]
                col = (sk[0] * .8, sk[1] * .7, sk[2] * .66)
            elif nm in ('hero_chino', 'hero_cargo', 'hero_cargo_pocket', 'hero_waistband'):
                col = spec['pants']
            if col is not None:
                existing = m.node_tree.nodes.get('Review tint')
                if existing is not None:
                    existing.inputs[7].default_value = (*lin(col), 1)
                    continue
                tex = [l for l in m.node_tree.links if l.to_socket == p.inputs['Base Color']]
                if tex:
                    mix = m.node_tree.nodes.new('ShaderNodeMix')
                    mix.name = 'Review tint'
                    mix.data_type = 'RGBA'
                    mix.blend_type = 'MULTIPLY'
                    mix.inputs['Factor'].default_value = 1.0
                    src = tex[0].from_socket
                    m.node_tree.links.remove(tex[0])
                    # Colour sockets (A/B/Result names are shared with the float/vector variants).
                    m.node_tree.links.new(src, mix.inputs[6])
                    mix.inputs[7].default_value = (*lin(col), 1)
                    m.node_tree.links.new(mix.outputs[2], p.inputs['Base Color'])
                else:
                    p.inputs['Base Color'].default_value = (*lin(col), 1)
            if nm in ('hero_hair_buzz', 'hero_hair_crop', 'hero_hair_fade', 'hero_hair_bun') and len(o.data.uv_layers) > 1:
                review_scalp(m, p, o.data.uv_layers[1].name, SKIN[spec['face']], nm != 'hero_hair_bun')


def aim(view, spec):
    off, tgt, lens = VIEWS[view]
    if view in ('face', 'face_side', 'hair'):
        cap = bpy.data.objects.get('Hair_%s_%s' % (spec['hair'], spec['face']))
        face = bpy.data.objects.get('Face_' + spec['face'])
        if cap is not None and face is not None:
            top = max((cap.matrix_world @ v.co).z for v in cap.data.vertices)
            ocular = {i for p in face.data.polygons
                      if face.data.materials[p.material_index].name == 'hero_eye' for i in p.vertices}
            if ocular:
                eye = sum((face.matrix_world @ face.data.vertices[i].co).z for i in ocular) / len(ocular)
                tgt = Vector((tgt.x, tgt.y, (top + eye - .106) * .5))
                if view == 'hair':
                    tgt.z += .030
    if view == 'cuff' and GLB.endswith('.blend'):
        hands = bpy.data.objects.get('Skin_Hands')
        if hands is not None:
            evaluated = hands.evaluated_get(bpy.context.evaluated_depsgraph_get())
            points = [evaluated.matrix_world @ v.co for v in evaluated.data.vertices]
            near = [p for p in points if p.x > 0]
            if near:
                tgt = sum(near, Vector()) / len(near) + Vector((0, 0, .032))
                off = Vector((.42, .49, .09))
                lens = 82
    cam.location = tgt + off
    d = tgt - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    cam_data.lens = lens


report = {}
for name in WANT:
    spec = OUTFITS[name]
    show(spec)
    pose(spec)
    if not spec.get('anatomy'):
        tint(spec)
    for v in VIEWS_WANTED or VIEWS:
        aim(v, spec)
        sc.render.filepath = '%s/%s__%s.png' % (OUT, name, v)
        bpy.ops.render.render(write_still=True)
    if name == WANT[0] and VIEWS_WANTED is None:
        saved = {o.name: list(o.data.materials) for o in meshes}
        for o in meshes:
            for i in range(len(o.data.materials)):
                o.data.materials[i] = clay
        for v in CLAY_VIEWS:
            aim(v, spec)
            sc.render.filepath = '%s/%s__clay_%s.png' % (OUT, name, v)
            bpy.ops.render.render(write_still=True)
        for o in meshes:
            for i, m in enumerate(saved[o.name]):
                o.data.materials[i] = m
    vis = [o for o in meshes if not o.hide_render]
    report[name] = {'visible_meshes': len(vis), 'triangles': sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in vis)}
open(OUT + '/blender_stats.json', 'w').write(json.dumps(report, indent=2))
print('REVIEW RENDERS DONE', OUT, report, flush=True)
