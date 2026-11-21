"""Headless Blender review renders of the exported hero (assets/models/character.glb).

blender -b --factory-startup --python tools/blender/render_character_review.py -- <glb> <outdir> [outfits] [views]

Imports the shipping GLB (so what is reviewed is what the game loads), shows
one outfit's variant meshes (the same selection rules as CharacterRig.
_show_variants), and renders fixed cameras under fixed lights with Cycles on
the CPU: a material pass and a clay pass (uniform grey: geometry only, which
is what this reconstruction is judged on). Same cameras every milestone.
"""
import bpy, sys, math, json
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
GLB, OUT = argv[0], argv[1]
WANT = argv[2].split(',') if len(argv) > 2 else ['orange_shirt', 'tee_cap']
VIEWS_WANTED = argv[3].split(',') if len(argv) > 3 else None

# outfit -> (face, hair style, top cut, extra accessory meshes, colours)
OUTFITS = {
    'orange_shirt': dict(face='ade', hair='crop', top='shirt', acc=['shades'], top_col=(0.85, 0.51, 0.17), pants=(0.24, 0.27, 0.19)),
    'tee_cap': dict(face='theo', hair='crop', top='tee', acc=['cap'], top_col=(0.25, 0.43, 0.70), pants=(0.79, 0.74, 0.61)),
    'polo_phones': dict(face='kai', hair='fade', top='polo', acc=['headphones'], top_col=(0.95, 0.95, 0.93), pants=(0.12, 0.18, 0.29)),
    'blazer': dict(face='malik', hair='crop', top='blazer', acc=['shades'], top_col=(0.1, 0.11, 0.13), pants=(0.1, 0.11, 0.13)),
    'rio_tee': dict(face='rio', hair='curls', top='tee', acc=[], top_col=(0.79, 0.43, 0.57), pants=(0.12, 0.18, 0.29)),
    'sam_blazer': dict(face='sam', hair='bob', top='blazer', acc=[], top_col=(.23, .25, .27), pants=(.15, .19, .29)),
}
SKIN = {'ade': (0.32, 0.2, 0.14), 'theo': (0.78, 0.6, 0.5), 'kai': (0.6, 0.43, 0.32), 'malik': (0.42, 0.27, 0.18), 'ren': (0.72, 0.55, 0.42),
        'rio': (0.36, 0.22, 0.15), 'sam': (0.9, 0.74, 0.64)}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']

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
    'face': (Vector((0.22, 0.95, 0.03)), Vector((0, 0.05, 1.68)), 85),
    'face_side': (Vector((0.95, 0.15, 0.03)), Vector((0, 0.03, 1.68)), 85),
    'collar': (Vector((0.15, 0.85, 0.12)), Vector((0, 0.03, 1.5)), 60),
    'shoulder': (Vector((0.75, 0.55, 0.18)), Vector((0.2, 0, 1.45)), 60),
    'cuff': (Vector((0.6, 0.5, 0.05)), Vector((0.55, 0.0, 0.95)), 60),
}
CLAY_VIEWS = ['front', 'three_quarter', 'side', 'rear', 'face', 'shoulder', 'cuff']


def show(spec):
    f, hs, top = spec['face'], spec['hair'], spec['top']
    for o in meshes:
        n = o.name
        vis = True
        if n == 'Top_Collar':
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
            vis = top in ('shirt', 'blazer')
        elif n == 'Courier_Cargo' or n.startswith('Cargo_gusset'):
            vis = top not in ('shirt', 'blazer')
        elif n == 'Courier_Waistband':
            vis = top == 'shirt'
        elif n.startswith('Mask_'):
            vis = False
        elif n.startswith('Acc_'):
            vis = any(n == 'Acc_%s_%s' % (a, f) or n.startswith('Acc_%s_%s_' % (a, f)) for a in spec['acc'])
        o.hide_render = not vis
        o.hide_viewport = not vis


def lin(c):
    # Shop colours are sRGB; Blender colour inputs are linear.
    return tuple(((x + .055) / 1.055) ** 2.4 if x > .04045 else x / 12.92 for x in c)


def tint(spec):
    # Approximate the game's tints on the imported materials (white-ish
    # authored colours are multiplied by the outfit colour, as in hero_pbr).
    for o in meshes:
        for slot in o.material_slots:
            m = slot.material
            if m is None or not m.use_nodes:
                continue
            p = m.node_tree.nodes.get('Principled BSDF')
            if p is None:
                continue
            nm = m.name
            col = None
            if nm in ('hero_shirt', 'hero_tee', 'hero_knit', 'hero_blazer', 'hero_fleece', 'hero_rib', 'hero_lapel', 'hero_top', 'hero_shirt_trim', 'hero_buttonhole'):
                col = spec['top_col']
            elif nm.startswith('hero_skin'):
                col = SKIN[spec['face']]
            elif nm == 'hero_glove':
                sk = SKIN[spec['face']]
                col = (sk[0] * .8, sk[1] * .7, sk[2] * .66)
            elif nm in ('hero_chino', 'hero_cargo', 'hero_cargo_pocket', 'hero_waistband'):
                col = spec['pants']
            if col is not None:
                tex = [l for l in m.node_tree.links if l.to_socket == p.inputs['Base Color']]
                if tex:
                    mix = m.node_tree.nodes.new('ShaderNodeMix')
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


def aim(view):
    off, tgt, lens = VIEWS[view]
    cam.location = tgt + off
    d = tgt - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    cam_data.lens = lens


report = {}
for name in WANT:
    spec = OUTFITS[name]
    show(spec)
    tint(spec)
    for v in VIEWS_WANTED or VIEWS:
        aim(v)
        sc.render.filepath = '%s/%s__%s.png' % (OUT, name, v)
        bpy.ops.render.render(write_still=True)
    if name == WANT[0] and VIEWS_WANTED is None:
        saved = {o.name: list(o.data.materials) for o in meshes}
        for o in meshes:
            for i in range(len(o.data.materials)):
                o.data.materials[i] = clay
        for v in CLAY_VIEWS:
            aim(v)
            sc.render.filepath = '%s/%s__clay_%s.png' % (OUT, name, v)
            bpy.ops.render.render(write_still=True)
        for o in meshes:
            for i, m in enumerate(saved[o.name]):
                o.data.materials[i] = m
    vis = [o for o in meshes if not o.hide_render]
    report[name] = {'visible_meshes': len(vis), 'triangles': sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in vis)}
open(OUT + '/blender_stats.json', 'w').write(json.dumps(report, indent=2))
print('REVIEW RENDERS DONE', OUT, report, flush=True)
