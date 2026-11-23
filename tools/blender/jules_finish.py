"""Surface and fit finish for the assembled Jules collection.

Works on skinned mesh coordinates. UV islands, weights and pose shapes remain
the contract between these meshes and the game.
"""
import math

import numpy as np
from mathutils import Vector

from build_b_surface import falloff, surface_detail
from garment_kit import seam_height
from jules_accessories import finish_jules_accessories
from jules_collection import project_trim_uv
from wardrobe_quality import adjust_basis, smooth
from jules_upper_fit import fit_upper_collection


def bell(value, radius):
    return math.exp(-(value / radius) ** 2)


def shell_delta(p, side, depth):
    return Vector((p.x * side, (p.y - .020) * depth, 0))


def finish_sewn_details(collection):
    if collection.rig.get('jules_sewn_detail_uv'):
        return
    models = collection.models
    front = {'Topx_Fashion_Ribcrop_Placket', 'Lower_beltedmini_Buckle'}
    for name, ob in models.items():
        if name.startswith('Lower_utilitymini_Pocket'):
            project_trim_uv(ob.data, models['Lower_utilitymini'])
        if name in front or name == 'Topx_Fashion_Cowldress_Sash':
            for polygon in ob.data.polygons:
                outward = (Vector((polygon.center.x, polygon.center.y - .019, 0))
                           if name.endswith('_Sash') else Vector((0, 1, 0)))
                if polygon.normal.dot(outward) < 0:
                    polygon.flip()
            ob.data.update()
        if not ob.data.uv_layers and (name.startswith(('JulesAccessory_', 'Topx_Fashion_'))
                                      or name.startswith('Lower_beltedmini_')):
            project_trim_uv(ob.data)
    collection.rig['jules_sewn_detail_uv'] = 1


def finish_jules_collection(collection, output):
    """Refit the existing sewn panels and bake new textile relief."""
    if collection.rig.get('jules_surface_finish'):
        finish_sewn_details(collection)
        finish_jules_accessories(collection, output)
        return
    models = collection.models
    output.mkdir(parents=True, exist_ok=True)
    b = collection.rig.data.bones
    knee_z = b['b_shin_r'].head_local.z
    ankle_z = b['b_foot_r'].head_local.z

    def jeans(p):
        leg_center = .102 + max(0.0, .79 - p.z) * .055
        side = abs(p.x) - leg_center
        crease = bell(p.z - knee_z, .082) * smooth(.035, .092, p.y)
        stack = bell(p.z - (ankle_z + .103), .052)
        front = smooth(.027, .101, p.y)
        folds = .004 * math.cos(p.z * 122 + side * 34) * crease
        folds += .0048 * math.cos(p.z * 162 + side * 27) * stack * front
        rise = bell(p.z - 1.011, .047)
        return Vector((-p.x * .018 * rise, folds - (p.y-.02)*.031*rise, 0))

    adjust_basis(models['Lower_relaxeddenim'], jeans)

    def skirt_fit(p, shaped):
        hem = smooth(1.005, .725, p.z)
        hip = bell(p.z - .91, .065)
        panel = math.atan2(p.x, p.y-.021)
        folds = math.cos(panel*9 + (p.z - .75)*12) * hem * (.0023 if shaped else .0035)
        depth = -.075 if shaped else -.017
        side = -.115 if shaped else -.056
        # Keep the thighs' front allowance when the side seam is brought in.
        folds += (.011 if shaped else .007) * hip * smooth(.028,.09,p.y)
        delta = shell_delta(p, side*hem, depth*hem)
        delta.y += folds * math.cos(panel)
        delta.x += folds * math.sin(panel)
        return delta

    for name, ob in tuple(models.items()):
        if name.startswith('Lower_beltedmini'):
            adjust_basis(ob, lambda p: skirt_fit(p, True))
        elif name.startswith('Lower_utilitymini'):
            adjust_basis(ob, lambda p: skirt_fit(p, False))

    def shorts(p):
        thigh = bell(p.z - .77, .074)
        side = abs(p.x) - .105
        compression = smooth(.041, .095, abs(side)) * thigh
        rise = smooth(.928, 1.018, p.z)
        return Vector((-math.copysign(.0037 * compression, side) * math.copysign(1,p.x),
                       -(p.y-.019) * (.028*rise + .035*thigh), 0))

    adjust_basis(models['Lower_sprintshorts'], shorts)

    def satin(p):
        angle = math.atan2(p.x, p.y-.019)
        lower = smooth(.895,.55,p.z)
        sweep = angle*7 + p.z*11.0
        cloth = .0074*math.sin(sweep)*lower + .0035*math.sin(sweep*1.63 + .8)*lower
        gathering = bell(p.z - 1.067 + p.x*.23, .082) * smooth(.040,.122,p.y)
        body_fold = .0021 * math.sin((p.z + p.x*.46) * 123) * gathering
        return Vector((cloth*math.sin(angle), cloth*math.cos(angle) + body_fold, -.0038*lower*math.sin(angle*3)))

    for name, ob in tuple(models.items()):
        if name.startswith('Topx_Fashion_Cowldress_') or name == 'Top_Fashion_Cowldress':
            adjust_basis(ob, satin)

    fit_upper_collection(collection)

    # One descriptor per principal textile. The maps use real-world stitch
    # spacing and are baked into the existing packed UVs.
    textiles = {
        'Lower_relaxeddenim': ('denim', .82, .82),
        'Top_Fashion_Ribcrop': ('rib', .83, .68),
        'Top_Fashion_Zipcrop': ('shell', .67, .71),
        'Lower_utilitymini': ('shell', .80, .72),
        'Top_Fashion_Tailoredknit': ('rib', .77, .65),
        'Lower_beltedmini': ('crepe', .73, .54),
        'Top_Fashion_Crossbra': ('stretch', .71, .67),
        'Lower_sprintshorts': ('stretch', .75, .68),
        'Top_Fashion_Cowldress': ('satin', .41, .30),
        'Topx_Fashion_Cowldress_Skirt': ('satin', .43, .32),
    }
    for name, (fabric, roughness, strength) in textiles.items():
        garment = models[name]
        shader = garment.data.materials[0].node_tree.nodes.get('Principled BSDF')
        collection.roughness(shader, roughness)
        shader.inputs['Specular IOR Level'].default_value = .39 if fabric == 'satin' else .27
        shader.inputs['Sheen Weight'].default_value = .18 if fabric in ('rib', 'shell', 'crepe') else .09
        anisotropy = shader.inputs.get('Anisotropic')
        if fabric == 'satin' and anisotropy is not None:
            anisotropy.default_value = .27
        if shader.inputs['Normal'].is_linked and shader.inputs['Base Color'].is_linked:
            surface_detail(garment, output, textile_field(fabric, name), strength,
                           texture_key="jules_" + name.lower())

    # Low-profile raised stitches and front lacing use geometry so they
    # retain depth at oblique angles and under studio highlights.
    denim = models['Lower_relaxeddenim']
    thread = collection.material('hero_jules_denim_thread', (.30,.205,.102), .83)
    for side, tag in [(-1, 'L'), (1, 'R')]:
        points = [(side * (0.072 + .066*t + .026*t*t), 1.010 - .110*t)
                  for t in (i/21 for i in range(22))]
        collection.surface_strip(f'Lower_relaxeddenim_PocketThread{tag}', denim, points,
                                 .00085, thread, .0021)
    shoe = models['Footwear_highstreet']
    # Round the collar seam and give the toe box more space above the laces.
    adjust_basis(shoe, lambda p: Vector((0, .0047 * smooth(.095,.158,p.y),
                                         .0038 * bell(p.y-.114,.041) * smooth(.047,.075,p.z))))
    for name in ('Footwear_highstreet', 'Footwear_pumps', 'Footwear_eveningstraps'):
        for mat in models[name].data.materials:
            if mat.name.startswith(('hero_fashion_shoe_', 'hero_streettrainer_upper')):
                shader = mat.node_tree.nodes.get('Principled BSDF')
                collection.roughness(shader, .47 if name == 'Footwear_pumps' else .56)
                shader.inputs['Specular IOR Level'].default_value = .34
    for name, ob in models.items():
        if name.startswith('JulesAccessory_'):
            for mat in ob.data.materials:
                shader = mat.node_tree.nodes.get('Principled BSDF')
                shader.inputs['Metallic'].default_value = .54
                collection.roughness(shader, .26)

    collection.rig['jules_surface_finish'] = 1
    finish_sewn_details(collection)
    finish_jules_accessories(collection, output)


def textile_field(style, name):
    """Return the textile's dye and tangent relief in metres."""
    grains = {'denim': .000098, 'rib': .000165, 'shell': .000067,
              'crepe': .000082, 'stretch': .000063, 'satin': .000018}

    def evaluate(p, n):
        x, y, z = p.T
        a = np.arctan2(x, y - .019)
        axis = np.where(n[:, 1] > 0, x, y)
        front = falloff(.012, .086, y)
        grain = (np.sin(axis * 2350 + z * 1168) * np.sin(z * 1910 - axis*520)
                 + .43 * np.sin((axis + z) * 4231))
        if style == 'rib':
            grain = np.cos(axis*1960 + z*58) + .35*grain
        if style == 'denim':
            grain = np.cos((axis+z*.61)*2130) * np.cos(z*1700) + .45 * grain
        relief = grains[style] * grain
        dye = 1 + grain * (.014 if style == 'satin' else .024)
        if style == 'denim':
            thigh = np.exp(-((z-.79)/.16)**2) * front
            wash = .13*thigh * np.exp(-((np.abs(x)-.112)/.060)**2)
            whisker = np.sin((z + abs(x)*.18)*199 + x*14)
            dye *= (.925 + wash + .024 * whisker * thigh)
            relief += .000082 * whisker * thigh
            relief += seam_height(np.abs(x) - (.166 + (.99-z)*.056), z, groove=.00026,
                                  width=.0016, stitch_off=.0028, stitch_len=.0027, stitch_h=.00021)
        elif style in ('stretch','shell','crepe'):
            zhem = .718 if name.startswith('Lower_') else 1.204 if style == 'stretch' else 1.164
            relief += seam_height(z-zhem, a, groove=.00013, width=.002,
                                  stitch_off=.0029, stitch_len=.0032, stitch_h=.00012)
        return dye[:, None], relief

    return evaluate
