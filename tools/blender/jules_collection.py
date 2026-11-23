"""Five fitted Jules outfits, built against the approved skinned body."""
import math

import bmesh
import bpy
from mathutils import Vector

from garment_kit import iso_cut, weights_from
from wardrobe_quality import adjust_basis, smooth, surface_tree


class Collection:
    def __init__(self, rig, meshes):
        self.rig = rig
        self.meshes = meshes
        self.models = {ob.name: ob for ob in meshes}
        self.materials = {}

    def clone(self, donor, name, textile=None, roughness=None):
        source = self.models[donor]
        obj = source.copy()
        obj.data = source.data.copy()
        obj.name = name
        obj.data.name = name
        source.users_collection[0].objects.link(obj)
        obj.hide_set(True)
        self.add(obj)
        if textile:
            for i, original in enumerate(source.data.materials):
                key = (textile, original.name)
                if key not in self.materials:
                    material = original.copy()
                    material.name = textile if i == 0 else f'{textile}_{i}'
                    shader = material.node_tree.nodes.get('Principled BSDF')
                    if roughness is not None:
                        self.roughness(shader, roughness)
                    self.materials[key] = material
                obj.data.materials[i] = self.materials[key]
        return obj

    @staticmethod
    def roughness(shader, value):
        socket = shader.inputs['Roughness']
        for link in list(socket.links):
            shader.id_data.links.remove(link)
        socket.default_value = value

    def add(self, obj):
        self.models[obj.name] = obj
        self.meshes.append(obj)

    def cut(self, obj, keep, rim=.0022):
        """Cut the posed panels together, then turn the new edge inward."""
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        iso_cut(bm, keep)
        bm.normal_update()
        layer_shapes = list(bm.verts.layers.shape.values())
        trimmed = [e for e in bm.edges if e.is_boundary
                   and all(abs(keep(v.co)) < .001 for v in e.verts)]
        if trimmed and rim:
            normals = {v: v.normal.copy() for e in trimmed for v in e.verts}
            extruded = bmesh.ops.extrude_edge_only(bm, edges=trimmed)
            for v in (e for e in extruded['geom'] if isinstance(e, bmesh.types.BMVert)):
                normal = next((normals[e.other_vert(v)] for e in v.link_edges
                               if e.other_vert(v) in normals), None)
                if normal is None:
                    continue
                delta = -normal * rim
                v.co += delta
                for layer in layer_shapes:
                    v[layer] += delta
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()

    def material(self, name, colour, roughness, metallic=0.0):
        material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        material.use_nodes = True
        shader = material.node_tree.nodes['Principled BSDF']
        shader.inputs['Base Color'].default_value = (*colour, 1)
        shader.inputs['Roughness'].default_value = roughness
        shader.inputs['Metallic'].default_value = metallic
        return material

    def surface_strip(self, name, shell, centreline, width, material, offset=.003, back=False):
        """Build a real folded trim ribbon and transfer the underlying weights."""
        tree = surface_tree(shell.data)
        points, faces = [], []
        for x, z in centreline:
            direction = -1 if back else 1
            hits = [tree.ray_cast(Vector((x + side * width, .40 * direction, z)), Vector((0, -direction, 0)))
                    for side in (-1, 1)]
            if any(hit[0] is None or hit[1].y * direction < .15 for hit in hits):
                continue
            index = len(points)
            for level in (0, 1):
                for hit, normal, _, _ in hits:
                    points.append(hit + normal * (offset if level == 0 else -.0005))
            if index:
                a = index - 4
                faces.extend(((a, index, index+1, a+1), (a, a+2, index+2, index),
                              (a+1, index+1, index+3, a+3)))
        if not faces:
            return
        self.attach_panel(name, shell, points, [face[::-1] for face in faces] if back else faces, material)

    def attach_panel(self, name, shell, points, faces, material):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(points, [], faces)
        mesh.update()
        mesh.materials.append(material)
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        obj = bpy.data.objects.new(name, mesh)
        shell.users_collection[0].objects.link(obj)
        obj.parent = self.rig
        obj.matrix_world = shell.matrix_world.copy()
        weights_from(obj, shell)
        modifier = obj.modifiers.new('Armature', 'ARMATURE')
        modifier.object = self.rig
        obj.hide_set(True)
        self.add(obj)

    def button_placket(self, shell):
        tree = surface_tree(shell.data)
        points, faces = [], []
        for index in range(15):
            z = 1.132 + .093 * index / 14
            edges = []
            for side in (-1, 1):
                hits = (tree.ray_cast(Vector((side * i * .002, .4, z)), Vector((0, -1, 0)))[0]
                        for i in range(1, 42))
                edge = next((hit for hit in hits if hit is not None and hit.y > .063), None)
                if edge is not None:
                    edges.append(edge)
            if len(edges) != 2:
                continue
            row = len(points)
            for index in range(5):
                p = edges[0].lerp(edges[1], index / 4)
                p.x *= 1.13
                p.y += .002 + .005 * math.sin(math.pi * index / 4)
                points.append(p)
            if row:
                faces.extend((row-5+i, row+i, row+i+1, row-4+i) for i in range(4))
        if faces:
            fabric = self.material('hero_fashion_top_rib_placket', (.19,.19,.19), .79)
            self.attach_panel('Topx_Fashion_Ribcrop_Placket', shell, points, faces, fabric)

    def gown_sash(self, bodice, skirt):
        trees = [surface_tree(ob.data) for ob in (bodice, skirt)]
        points, faces = [], []
        columns = 49
        for ring in range(6):
            t = ring / 5
            for vertex in range(columns):
                angle = math.tau * vertex / (columns - 1)
                z = 1.012 + .053*t - .012 * math.sin(angle)
                centre = Vector((0,.019,z))
                direction = Vector((math.sin(angle),math.cos(angle),0))
                hits = [tree.ray_cast(centre+direction*.27,-direction)[0] for tree in trees]
                hit = max((p for p in hits if p is not None), key=lambda p: (p-centre).dot(direction), default=None)
                if hit is None:
                    hit = centre + direction * .115
                points.append(hit + direction * (.0028 + .0022 * math.sin(t*math.pi*3)**2))
                if ring and vertex:
                    j = ring * columns + vertex
                    faces.append((j-columns-1,j-1,j,j-columns))
        fabric = self.material('hero_fashion_top_satin_sash', (.18,.18,.18), .45)
        self.attach_panel('Topx_Fashion_Cowldress_Sash', skirt, points, faces, fabric)

    def casual(self):
        top = self.clone('Top_Fashion_Cardigan', 'Top_Fashion_Ribcrop', 'hero_fashion_top_rib_ivory', .78)
        def neckline(p):
            # Deep V with a closed point and a cropped seam. The sleeves pass
            # through untouched and retain their posed shoulder correctives.
            v = max(abs(p.x) - (.015 + .38 * max(p.z - 1.224, 0)), 1.223 - p.z, .006 - p.y)
            return min(v, max(p.z - 1.115 - .019 * smooth(.14, 0, abs(p.x)), abs(p.x) - .218))
        self.cut(top, neckline)
        self.button_placket(top)
        self.clone('Topx_Fashion_Cardigan_Buttons', 'Topx_Fashion_Ribcrop_Buttons')
        self.cut(self.models['Topx_Fashion_Ribcrop_Buttons'], neckline, 0)
        jeans = self.clone('Lower_widejeans', 'Lower_relaxeddenim', 'hero_fashion_bottom_denim_relaxed', .82)
        adjust_basis(jeans, lambda p: Vector((math.copysign(.010 * smooth(.47, .07, p.z), p.x), 0, 0)))

    def sport_bra(self):
        bra = self.clone('Top_Fashion_Camisole', 'Top_Fashion_Crossbra', 'hero_fashion_top_jersey_bra', .74)
        self.cut(bra, lambda p: p.z - (1.200 + .023 * smooth(.09, -.05, p.y)))
        straps = self.clone('Topx_Fashion_Camisole_Straps', 'Topx_Fashion_Crossbra_Straps', 'hero_fashion_top_jersey_bra', .74)
        self.cut(straps, lambda p: p.y + .038)
        self.crossed_back('Crossbra', .133, .0055, 'jersey')
        skin = self.clone('Fashion_Crop_Skin', 'JulesSkin_Crossbra')
        def waistband_clearance(p):
            overlap = smooth(1.042, 1.005, p.z) * (1 - smooth(.146, .190, abs(p.x)))
            return Vector((-p.x * .34 * overlap, -(p.y - .018) * .49 * overlap, 0))
        adjust_basis(skin, waistband_clearance)
        short = self.clone('Lower_bikershorts', 'Lower_sprintshorts', 'hero_fashion_bottom_jersey_sprint', .76)
        self.cut(short, lambda p: p.z - (.680 + .023 * smooth(.10, .20, abs(p.x))))
        adjust_basis(short, lambda p: Vector((0, -.006 * smooth(1.005, 1.025, p.z) * smooth(.023, -.050, p.y), 0)))

    def crossed_back(self, cut, drop, half_width, textile):
        body = self.models['Fashion_Torso_Skin']
        cloth = self.material('hero_fashion_top_' + textile + '_' + cut.lower() + '_ribbon',
                              (.15,.15,.16), .7 if textile == 'jersey' else .46)
        for side, label in ((-1, 'Left'), (1, 'Right')):
            line = [(side * (.082 - .154*t), 1.413 - drop*t) for t in (i/24 for i in range(25))]
            self.surface_strip('Topx_Fashion_' + cut + '_Cross' + label, body, line,
                               half_width, cloth, .006, back=True)

    def street(self):
        top = self.clone('Top_Fashion_Racer', 'Top_Fashion_Zipcrop', 'hero_fashion_top_cotton_zipcrop', .73)
        self.cut(top, lambda p: max(p.z - 1.145, abs(p.x) - .211))
        self.clone('Topx_Fashion_Pullover_Hood', 'Topx_Fashion_Zipcrop_Hood', 'hero_fashion_top_cotton_zipcrop', .73)
        teeth = self.material('hero_jules_zip_metal', (.19,.18,.18), .52, .62)
        for side, label in ((-1, 'Left'), (1, 'Right')):
            self.surface_strip('Topx_Fashion_Zipcrop_Zip' + label, top,
                [(side * (.072 + .045 * f), 1.150 + .252 * f) for f in (i/30 for i in range(31))],
                .0017, teeth, .0025)
        bra = self.clone('Top_Fashion_Crossbra', 'Topx_Fashion_Zipcrop_Bra', 'hero_jules_black_jersey', .78)
        straps = self.clone('Topx_Fashion_Crossbra_Straps', 'Topx_Fashion_Zipcrop_Straps', 'hero_jules_black_jersey', .78)
        black = self.material('hero_jules_black_jersey_flat', (.020, .021, .026), .79)
        bra.data.materials[0] = black
        straps.data.materials[0] = black
        skirt = self.clone('Lower_miniskirt', 'Lower_utilitymini', 'hero_fashion_bottom_cotton_utility', .83)
        adjust_basis(skirt, lambda p: Vector((0, 0, .051 * smooth(.98, .65, p.z))))
        for side in (-1, 1):
            self.surface_strip(f'Lower_utilitymini_Pocket{side:+d}', skirt,
                [(side * (.128 + .015 * t), .899 - t * .111) for t in (i/9 for i in range(10))],
                .023, skirt.data.materials[0], .005)

    def smart(self):
        top = self.clone('Top_Fashion_Blouse', 'Top_Fashion_Tailoredknit', 'hero_fashion_top_rib_tailored', .69)
        def opening(p):
            return max(abs(p.x) - (.011 + .43 * max(p.z - 1.236, 0)), 1.236 - p.z, .006 - p.y)
        self.cut(top, opening)
        skirt = self.clone('Lower_miniskirt', 'Lower_beltedmini', 'hero_fashion_bottom_crepe_belted', .68)
        adjust_basis(skirt, lambda p: Vector((-p.x*.085 * smooth(.95, .66, p.z), -(p.y-.028)*.025*smooth(.94,.66,p.z), .039 * smooth(.99, .65, p.z))))
        belt = self.material('hero_jules_tan_leather', (.21,.115,.058), .63)
        brass = self.material('hero_jules_brass', (.52,.31,.095), .35, .7)
        self.surface_strip('Lower_beltedmini_Belt', skirt, [(x, 1.013) for x in (-.128,-.095,-.055,0,.055,.095,.128)],
                           .013, belt)
        self.surface_strip('Lower_beltedmini_Buckle', skirt, [(0,z) for z in (.985,.999,1.016,1.030)],
                           .013, brass, .006)

    def formal(self):
        top = self.clone('Top_Fashion_Camisole', 'Top_Fashion_Cowldress', 'hero_fashion_top_satin_cowl', .40)
        def cowl(p):
            front = smooth(.067, .137, p.y)
            centre = 1 - smooth(.018, .113, abs(p.x))
            neck = smooth(1.245, 1.365, p.z)
            gathering = math.sin((p.z - 1.16) * 132 + p.x * 19)
            return Vector((0, front * (.005 * centre * neck + .0019 * gathering),
                           -.022 * front * centre * neck))
        adjust_basis(top, cowl)
        straps = self.clone('Topx_Fashion_Camisole_Straps', 'Topx_Fashion_Cowldress_Straps', 'hero_fashion_top_satin_cowl', .40)
        self.cut(straps, lambda p: p.y + .038)
        self.crossed_back('Cowldress', .182, .0026, 'satin')
        self.cut(top, lambda p: max(1.258 + abs(p.x) * .38 - p.z, p.y + .027))
        skirt = self.clone('Lower_midiskirt', 'Topx_Fashion_Cowldress_Skirt', 'hero_fashion_top_satin_cowl_skirt', .42)
        hem, waist = min(v.co.z for v in skirt.data.vertices), max(v.co.z for v in skirt.data.vertices)
        def fall(p):
            length = smooth(waist - .20, hem, p.z)
            ripple = .014 * length * math.cos(math.atan2(p.x, p.y - .018)*17)
            return Vector((p.x * .14 * length, ripple + p.y * .10 * length,
                           -.29 * length + .005 * length * math.sin(p.x*23)))
        adjust_basis(skirt, fall)
        def split(p):
            openness = .046 * smooth(.830, .505, p.z)
            return max(abs(p.x + .057) - openness, p.z - .830, .046 - p.y)
        self.cut(skirt, split)
        # The gown panel can move in front of the knee before its directional
        # pose key takes over. Keep extra room on the closed side of the slit.
        def knee_ease(p):
            below_hip = smooth(.834, .608, p.z) * smooth(.314, .53, p.z)
            front = smooth(.027, .13, p.y)
            return Vector((0, .028 * front * below_hip, 0))
        adjust_basis(skirt, knee_ease)
        self.gown_sash(top, skirt)
        keys = skirt.data.shape_keys.key_blocks
        seated = keys.get('Hem_Seated')
        if seated is not None:
            for rest, posed in zip(keys[0].data, seated.data):
                p = rest.co
                posed.co.y += .032 * smooth(.024, .119, p.y) * smooth(.82, .53, p.z)
        for donor, label in (('Fashion_Legs', ''), ('Fashion_Barefoot_Legs', '_Bare')):
            legs = self.clone(donor, 'JulesSkin_Cowldress' + label)
            self.cut(legs, lambda p: max(-p.x, .358 - p.z), 0)
            hip = self.rig.data.bones['b_thigh_l'].head_local.copy()
            knee = self.rig.data.bones['b_shin_l'].head_local.copy()
            def slit_clearance(p):
                if p.x >= 0 or p.z < .41:
                    return Vector()
                t = (p.z - knee.z) / (hip.z - knee.z)
                centre = knee.lerp(hip, t)
                tuck = .25 * smooth(.43, .58, p.z) * smooth(.038, -.01, p.y)
                return Vector(((centre.x-p.x)*tuck, (centre.y-p.y)*tuck, 0))
            adjust_basis(legs, slit_clearance)

    def shoes(self):
        trainers = self.clone('Footwear_streettrainers', 'Footwear_highstreet')
        adjust_basis(trainers, lambda p: Vector((0, 0, .026 * smooth(.085, .053, p.y) * smooth(.025, .090, p.z))))
        self.clone('Footwear_heels', 'Footwear_pumps')
        sandals = self.clone('Footwear_sandals', 'Footwear_eveningstraps', 'hero_fashion_shoe_eveningstrap', .46)
        self.roughness(sandals.data.materials[0].node_tree.nodes['Principled BSDF'], .74)

    def jewellery(self, style, colour, drop):
        """A skinned necklace with real round wire and a stamped pendant."""
        mat = self.material('hero_jules_metal_' + style, colour, .32, .67)
        mesh = bpy.data.meshes.new('JulesAccessory_' + style)
        torus = []
        faces = []
        for j in range(49):
            angle = math.tau * j / 48
            front = (1 + math.cos(angle)) * .5
            x = .065 * math.sin(angle)
            y = .036 + (.080 + drop*.22) * math.cos(angle)
            z = 1.442 - drop * front**3
            for i in range(6):
                section = math.tau * i / 6
                width = .0018 if style == 'street' else .0011
                torus.append((x + width * math.cos(section) * math.sin(angle),
                              y + width * math.cos(section) * math.cos(angle), z + width * math.sin(section)))
                if j:
                    faces.append(((j-1)*6+i, (j-1)*6+(i+1)%6, j*6+(i+1)%6, j*6+i))
        centre_y = .118 + drop*.22
        centre_z = 1.435 - drop
        centre_index = len(torus)
        torus.extend((.006*math.sin(math.tau*j/12), centre_y, centre_z + .008*math.cos(math.tau*j/12))
                     for j in range(12))
        faces.append(tuple(range(centre_index, centre_index+12)))
        mesh.from_pydata(torus, [], faces)
        mesh.update()
        mesh.materials.append(mat)
        for polygon in mesh.polygons:
            polygon.use_smooth = len(polygon.vertices) == 4
        obj = bpy.data.objects.new(mesh.name, mesh)
        body = self.models['Fashion_Torso_Skin']
        body.users_collection[0].objects.link(obj)
        obj.parent = self.rig
        obj.matrix_world = body.matrix_world.copy()
        weights_from(obj, body)
        deform = obj.modifiers.new('Armature', 'ARMATURE')
        deform.object = self.rig
        obj.hide_set(True)
        self.add(obj)


def build_jules_collection(rig, meshes):
    if rig.get('jules_collection'):
        return
    collection = Collection(rig, meshes)
    collection.casual()
    collection.sport_bra()
    collection.street()
    collection.smart()
    collection.formal()
    collection.shoes()
    collection.jewellery('day', (.52,.32,.09), .047)
    collection.jewellery('street', (.21,.22,.24), .035)
    collection.jewellery('office', (.49,.28,.07), .051)
    collection.jewellery('evening', (.62,.34,.09), .068)
    rig['jules_collection'] = 1
