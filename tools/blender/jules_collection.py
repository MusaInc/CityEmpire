"""Five fitted Jules outfits, built against the approved skinned body."""
import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.geometry import barycentric_transform

from garment_kit import SkinSurface, iso_cut, weights_from
from wardrobe_quality import adjust_basis, smooth, surface_tree


def project_trim_uv(mesh, donor=None):
    """Give a sewn detail tangent coordinates and match the fabric on pockets."""
    uv = mesh.uv_layers.active or mesh.uv_layers.new(name='UVMap')
    surface = SkinSurface(donor) if donor is not None else None
    if surface is not None:
        donor_uv = donor.data.uv_layers.active
        donor_faces = donor.data.loop_triangles
    for polygon in mesh.polygons:
        normal_axis = max(range(3), key=lambda axis: abs(polygon.normal[axis]))
        axes = [axis for axis in range(3) if axis != normal_axis]
        for index in polygon.loop_indices:
            point = mesh.vertices[mesh.loops[index].vertex_index].co
            if surface is None:
                uv.data[index].uv = tuple(point[axis] for axis in axes)
                continue
            hit, _, triangle, _ = surface.tree.find_nearest(point)
            corners = [Vector((*donor_uv.data[i].uv, 0)) for i in donor_faces[triangle].loops]
            positions = [surface.positions[i] for i in surface.triangles[triangle]]
            uv.data[index].uv = barycentric_transform(hit, *positions, *corners).xy


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
        project_trim_uv(mesh)
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
        """Build a clean, narrow vertical button placket matching the cardigan fabric."""
        tree = surface_tree(shell.data)
        points, faces = [], []
        for index in range(15):
            z = 1.124 + .126 * index / 14
            row = len(points)
            for idx in range(5):
                t = idx / 4
                x = (t - 0.5) * 0.022
                hit = tree.ray_cast(Vector((x, 0.40, z)), Vector((0, -1, 0)))[0]
                if hit is None or hit.y < 0.04:
                    break
                p = hit.copy()
                p.y += .0016 + .0010 * math.sin(math.pi * t)
                points.append(p)
            if len(points) - row != 5:
                del points[row:]
                continue
            if row and len(points) >= 10:
                faces.extend((row-5+i, row+i, row+i+1, row-4+i) for i in range(4))
        if faces:
            self.attach_panel('Topx_Fashion_Ribcrop_Placket', shell, points, faces, shell.data.materials[0])

    def gown_sash(self, bodice, skirt):
        trees = [surface_tree(ob.data) for ob in (bodice, skirt)]
        points, faces = [], []
        columns = 49
        for ring in range(6):
            t = ring / 5
            for vertex in range(columns):
                angle = math.tau * vertex / (columns - 1)
                z = 1.018 + .034 * t - .006 * math.sin(angle)
                centre = Vector((0, .019, z))
                direction = Vector((math.sin(angle), math.cos(angle), 0))
                hits = [tree.ray_cast(centre + direction * .27, -direction)[0] for tree in trees]
                hit = max((p for p in hits if p is not None), key=lambda p: (p - centre).dot(direction), default=None)
                if hit is None:
                    hit = centre + direction * .115
                points.append(hit + direction * (.0014 + .0008 * math.sin(t * math.pi)))
                if ring and vertex:
                    j = ring * columns + vertex
                    faces.append((j - columns - 1, j - 1, j, j - columns))
        fabric = self.material('hero_fashion_top_satin_sash', (.18, .18, .18), .70)
        self.attach_panel('Topx_Fashion_Cowldress_Sash', skirt, points, faces, fabric)

    def casual(self):
        # Build cropped V-neck ribbed cardigan from closed Blouse base so lower front is cleanly closed (no gaping belly gap!).
        top = self.clone('Top_Fashion_Blouse', 'Top_Fashion_Ribcrop', 'hero_fashion_top_rib_ivory', .80)
        def neckline(p):
            # Smooth modern curved V-neck cardigan ending at z = 1.258, cropped neatly at z = 1.122,
            # with the blouse's standing neck collar cleanly trimmed away (ZERO upturned shoulder flaps!).
            dz = max(p.z - 1.258, 0.0)
            v = max(abs(p.x) - (.008 + .46 * (dz ** .86)), 1.258 - p.z, .010 - p.y)
            no_collar = (1.428 + .014 * smooth(.01, -.05, p.y)) - p.z
            return min(v, no_collar, max(p.z - 1.122 - .012 * smooth(.14, 0, abs(p.x)), abs(p.x) - .218))
        self.cut(top, neckline, rim=.0028)
        self.button_placket(top)
        # 3 clean small tonal buttons evenly spaced down the closed center placket.
        btn_mat = self.material('hero_fashion_top_rib_ivory_btn', (.72, .66, .58), .45)
        plk = self.models.get('Topx_Fashion_Ribcrop_Placket') or top
        ptree = surface_tree(plk.data)
        b_pts, b_faces = [], []
        for bz in (1.148, 1.192, 1.236):
            hit = ptree.ray_cast(Vector((0.0, 0.40, bz)), Vector((0.0, -1.0, 0.0)))[0]
            if hit is None:
                continue
            c = hit + Vector((0.0, 0.0018, 0.0))
            base = len(b_pts)
            segs = 10
            r = 0.0046
            for k in range(segs):
                a = math.tau * k / segs
                b_pts.append(c + Vector((math.cos(a) * r, 0.0, math.sin(a) * r)))
            b_pts.append(c + Vector((0.0, 0.0016, 0.0)))
            for k in range(segs):
                b_faces.append((base + k, base + (k + 1) % segs, base + segs))
        if b_faces:
            self.attach_panel('Topx_Fashion_Ribcrop_Buttons', top, b_pts, b_faces, btn_mat)
        jeans = self.clone('Lower_widejeans', 'Lower_relaxeddenim', 'hero_fashion_bottom_denim_relaxed', .82)
        adjust_basis(jeans, lambda p: Vector((math.copysign(.004 * smooth(.47, .07, p.z), p.x), 0, .014 * smooth(.15, .03, p.z))))
        # Tuck Fashion_Crop_Skin cleanly inside waistbands so skin NEVER clips jaggedly out of jeans/skirts!
        crop_skin = self.models.get('Fashion_Crop_Skin')
        if crop_skin is not None:
            def crop_waist_tuck(p):
                overlap = smooth(1.036, 0.998, p.z) * (1.0 - smooth(.155, .205, abs(p.x)))
                return Vector((-p.x * .30 * overlap, -(p.y - .018) * .42 * overlap, 0))
            adjust_basis(crop_skin, crop_waist_tuck)

    def sport_bra(self):
        bra = self.clone('Top_Fashion_Camisole', 'Top_Fashion_Crossbra', 'hero_fashion_top_jersey_bra', .74)
        self.cut(bra, lambda p: p.z - (1.200 + .023 * smooth(.09, -.05, p.y)))
        straps = self.clone('Topx_Fashion_Camisole_Straps', 'Topx_Fashion_Crossbra_Straps', 'hero_fashion_top_jersey_bra', .74)
        self.cut(straps, lambda p: p.y + .038)
        self.crossed_back('Crossbra', .133, .0055, 'jersey')
        skin = self.clone('Fashion_Crop_Skin', 'JulesSkin_Crossbra')
        def waistband_clearance(p):
            overlap = smooth(1.012, 0.985, p.z) * (1 - smooth(.146, .190, abs(p.x)))
            return Vector((-p.x * .30 * overlap, -(p.y - .018) * .42 * overlap, 0))
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
        teeth = self.material('hero_jules_zip_metal', (.28, .29, .32), .36, .72)
        for side, label in ((-1, 'Left'), (1, 'Right')):
            # Trace the actual front zip edge of Top_Fashion_Zipcrop cleanly so rails never float off the chest!
            self.surface_strip('Topx_Fashion_Zipcrop_Zip' + label, top,
                [(side * (.074 + .038 * f), 1.152 + .242 * f) for f in (i/30 for i in range(31))],
                .0018, teeth, .0016)
        bra = self.clone('Top_Fashion_Crossbra', 'Topx_Fashion_Zipcrop_Bra', 'hero_jules_black_jersey', .78)
        black = self.material('hero_jules_black_jersey_flat', (.020, .021, .026), .79)
        bra.data.materials[0] = black
        skirt = self.clone('Lower_miniskirt', 'Lower_utilitymini', 'hero_fashion_bottom_cotton_utility', .83)
        adjust_basis(skirt, lambda p: Vector((0, 0, .051 * smooth(.98, .65, p.z))))
        for side in (-1, 1):
            self.surface_strip(f'Lower_utilitymini_Pocket{side:+d}', skirt,
                [(side * (.128 + .015 * t), .899 - t * .111) for t in (i/9 for i in range(10))],
                .023, skirt.data.materials[0], .005)

    def smart(self):
        top = self.clone('Top_Fashion_Blouse', 'Top_Fashion_Tailoredknit', 'hero_fashion_top_rib_tailored', .76)
        def opening(p):
            # Tasteful, flattering soft curved V-neck with the blouse's standing collar trimmed cleanly away!
            dz = max(p.z - 1.304, 0.0)
            v = max(abs(p.x) - (.016 + .50 * (dz ** .82)), 1.304 - p.z, .010 - p.y)
            no_collar = (1.428 + .014 * smooth(.01, -.05, p.y)) - p.z
            return min(v, no_collar)
        self.cut(top, opening, rim=.0032)
        skirt = self.clone('Lower_miniskirt', 'Lower_beltedmini', 'hero_fashion_bottom_crepe_belted', .68)
        adjust_basis(skirt, lambda p: Vector((-p.x*.085 * smooth(.95, .66, p.z), -(p.y-.028)*.025*smooth(.94,.66,p.z), .039 * smooth(.99, .65, p.z))))
        belt = self.material('hero_jules_tan_leather', (.21,.115,.058), .63)
        brass = self.material('hero_jules_brass', (.52,.31,.095), .35, .7)
        self.surface_strip('Lower_beltedmini_Belt', skirt, [(x, 1.013) for x in (-.128,-.095,-.055,0,.055,.095,.128)],
                           .013, belt)
        self.surface_strip('Lower_beltedmini_Buckle', skirt, [(0,z) for z in (.985,.999,1.016,1.030)],
                           .013, brass, .006)

    def formal(self):
        top = self.clone('Top_Fashion_Camisole', 'Top_Fashion_Cowldress', 'hero_fashion_top_satin_cowl', .70)
        straps = self.clone('Topx_Fashion_Camisole_Straps', 'Topx_Fashion_Cowldress_Straps', 'hero_fashion_top_satin_cowl', .70)
        self.cut(straps, lambda p: p.y + .038)
        self.crossed_back('Cowldress', .182, .0026, 'satin')
        def sweetheart_neckline(p):
            # Refined, smooth, classy gentle sweetheart neckline (no exaggerated rollercoaster peaks!).
            ax = abs(p.x)
            front_w = smooth(.008, .085, p.y)
            sweetheart = 1.300 + .022 * math.exp(-((ax - .064) / .045) ** 2) - .022 * smooth(.094, .148, ax)
            back_line = 1.278
            top_z = back_line + (sweetheart - back_line) * front_w
            return top_z - p.z
        self.cut(top, sweetheart_neckline, rim=.0030)
        skirt = self.clone('Lower_midiskirt', 'Topx_Fashion_Cowldress_Skirt', 'hero_fashion_top_satin_cowl_skirt', .70)
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
                if p.x >= 0 or p.z < .36:
                    return Vector()
                t = max(0.0, min(1.0, (p.z - knee.z) / max(hip.z - knee.z, 1e-4)))
                centre = knee.lerp(hip, t)
                # Tuck concealed back AND outer-lateral hip/thigh cleanly inside the closed side of the slit skirt!
                back_tuck = .26 * smooth(.40, .56, p.z) * smooth(.045, -.01, p.y)
                outer_tuck = .24 * smooth(.42, .62, p.z) * smooth(.095, .145, abs(p.x))
                tuck = max(back_tuck, outer_tuck)
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
