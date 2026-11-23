"""Final corrective sculpt and grooming for WorldState's fixed playable pair."""
import math
import random
from collections import defaultdict

from mathutils import Vector
from mathutils.bvhtree import BVHTree

from wardrobe_quality import adjust_basis, smooth


def bell(value, width):
    return math.exp(-(value / width) ** 2)


def material_vertices(obj, names):
    return {index for poly in obj.data.polygons
            if obj.data.materials[poly.material_index].name.startswith(names)
            for index in poly.vertices}


def finish_face(face, identity):
    eye = material_vertices(face, ('hero_eye',))
    eyes = [sum((face.data.vertices[i].co for i in eye if side * face.data.vertices[i].co.x > 0),
                Vector()) / sum(side * face.data.vertices[i].co.x > 0 for i in eye)
            for side in (-1, 1)]
    eye_z = (eyes[0].z + eyes[1].z) * .5
    eye_y = (eyes[0].y + eyes[1].y) * .5
    skin = material_vertices(face, ('hero_skin_face_', 'hero_lid_rim', 'hero_lips'))
    eyebrows = material_vertices(face, ('hero_brow',))
    lip_z = eye_z - (.065 if identity == 'jules' else .068)
    keys = face.data.shape_keys.key_blocks

    for i in skin:
        p = face.data.vertices[i].co
        x, y, z = p
        s = abs(x)
        front = smooth(eye_y - .016, eye_y + .023, y)
        inside = smooth(eye_y - .069, eye_y - .010, y)
        jaw = bell(z - eye_z + .075, .024) * bell(s-.052, .022) * inside
        cheek = bell(s-.047, .021) * bell(z-eye_z+.034, .019) * front
        bridge = bell(x,.009) * bell(z-eye_z+.018,.024) * front
        wing = bell(s-.014,.006) * bell(z-eye_z+.041,.009) * front
        tendons = bell(s-.027,.012) * bell(z-eye_z+.124,.024) * inside
        cupid = lip_z + .0017 * bell(s-.006,.005)
        lip = bell(s,.021) * front
        lips = .0011*bell(z-cupid-.004,.004) + .0018*bell(z-lip_z+.0045,.005)
        delta = Vector((x * (-.043 if identity == 'jules' else -.023)*jaw,
                        .0020*cheek -.0014*bridge + .0015*wing + .0013*tendons + lips*lip,
                        .0015*jaw))
        for centre in eyes:
            dx, dz = x-centre.x, z-centre.z
            rim = bell(dx,.016) * smooth(centre.y+.004,centre.y+.012,y)
            delta.y += rim * (.0009 * bell(dz-.007,.0027) - .0007*bell(dz-.014,.004))
            delta.z += .042 * dx * rim * bell(dz,.011)
        ear = smooth(.061,.083,s) * bell(z-eye_z+.013,.027) * (1-front)
        delta.x += math.copysign(.0019*ear, x)
        delta.y -= .0007*ear
        for key in keys:
            key.data[i].co += delta
        p += delta
    face.data.update()

    smile = face.shape_key_add(name='Smile')
    focus = face.shape_key_add(name='Focus')
    for i in skin | eyebrows:
        p = face.data.vertices[i].co
        x, y, z = p
        s = abs(x)
        front = smooth(eye_y - .035, eye_y + .020, y)
        corner = bell(s-.021,.012) * bell(z-lip_z,.009) * front
        cheek = bell(s-.039,.024) * bell(z-eye_z+.042,.023) * front
        furrow = bell(s-.015,.020) * bell(z-eye_z-.020,.017) * front
        junction = bell(s,.023) * bell(z-lip_z,.007) * front
        smile.data[i].co += Vector((math.copysign(.0038*corner,x), .0010*cheek, .0045*corner + .0018*cheek))
        focus.data[i].co += Vector((-math.copysign(.0018*furrow,x), -.0011*junction, -.0026*furrow))


def soften_hairline(shell):
    surface = shell.data
    rim = defaultdict(list)
    incidence = defaultdict(int)
    for poly in surface.polygons:
        if poly.material_index == 0:
            for edge in poly.edge_keys:
                incidence[edge] += 1
    for (a, b), count in incidence.items():
        if count == 1:
            rim[a].append(b)
            rim[b].append(a)
    positions = [v.co.copy() for v in surface.vertices]
    for index, neighbours in rim.items():
        if len(neighbours) == 2:
            midpoint = (positions[neighbours[0]] + positions[neighbours[1]]) * .5
            offset = midpoint - positions[index]
            surface.vertices[index].co += offset * min(.61, .0045 / max(offset.length, .0001))
    surface.update()


def shape_hairstyle(shell, strands, identity):
    if identity == 'ade':
        crest = max(v.co.z for v in shell.data.vertices)
        for vertex in shell.data.vertices:
            p = vertex.co
            crown = smooth(crest-.077, crest-.011, p.z)
            p.z -= (.0037 + .0022*bell(p.x+.044,.026)) * crown
            p.x += .0042 * crown
        shell.data.update()
        return

    tied = material_vertices(shell, ('hero_hair_lengths',))
    centre = sum((shell.data.vertices[i].co for i in tied), Vector()) / max(1, len(tied))
    for i in tied:
        p = shell.data.vertices[i].co
        offset = p-centre
        height = smooth(-.025,.017,offset.z)
        angle = math.atan2(offset.x,offset.y)
        # Scrunch the wound silhouette, burying the hard upper outline.
        p.z -= .0031 * height
        p.x += (.0044 + .0024*math.cos(angle+offset.z*70)) * height
    shell.data.update()
    for vertex in strands.data.vertices:
        p = vertex.co
        if not .037 < abs(p.x) < .093 or p.y < .085:
            continue
        eye_level = centre.z - .139
        lock = (1 - smooth(eye_level+.030, eye_level+.074, p.z)) * smooth(eye_level-.125, eye_level-.068, p.z)
        sign = -1 if p.x < 0 else 1
        p.x += sign * .0061 * lock * math.sin((p.z-eye_level)*49.0 + sign*.25)
        p.y += .0035 * lock * math.cos((p.z-eye_level)*42.0)
    strands.data.update()


def grow_hairline(bpy, shell, strands, identity):
    """Layer tapered rooted locks along the existing cap without extra draw calls."""
    import bmesh

    surface = shell.data
    points = [v.co.copy() for v in surface.vertices]
    faces = [tuple(p.vertices) for p in surface.polygons if p.material_index == 0]
    ray = BVHTree.FromPolygons(points, faces)
    if not faces or not strands.data.materials:
        return
    bm = bmesh.new()
    bm.from_mesh(strands.data)
    uv = bm.loops.layers.uv.active
    density = bm.loops.layers.uv.get('ClothFreedom')
    weights = bm.verts.layers.deform.verify()
    head = strands.vertex_groups['b_head'].index
    rng = random.Random(42 if identity == 'ade' else 53)
    crown = max(p.z for p in points if p.y > .025)
    for n in range(105):
        x = rng.uniform(-.065, .065)
        z = crown - rng.uniform(.028, .078)
        hit, _, _, _ = ray.ray_cast(Vector((x,.24,z)), Vector((0,-1,0)), .23)
        if hit is None:
            continue
        length = rng.uniform(.012,.031)
        width = rng.uniform(.0013,.0027)
        rows = []
        strip = n % 8
        for step in range(7):
            t = step / 6
            u = hit.x + (.20*x + rng.uniform(-.00055,.00055))*t
            v = hit.z + length*t
            p, normal, _, _ = ray.ray_cast(Vector((u,.24,v)), Vector((0,-1,0)), .26)
            if p is None or normal.y < .06:
                break
            tangent = normal.cross(Vector((.13,0,1))).normalized()
            crest = (.00015 + .0027 * math.sin(math.pi*t)**1.2)
            row = [bm.verts.new(p + normal*crest + tangent*(side*width*(1-.84*t)))
                   for side in (-1, 1)]
            for vertex in row:
                vertex[weights][head] = 1
            rows.append(row)
        if len(rows) < 3:
            bmesh.ops.delete(bm, geom=[v for row in rows for v in row], context='VERTS')
            continue
        for idx, (a,b) in enumerate(zip(rows, rows[1:])):
            face = bm.faces.new((a[0], a[1], b[1], b[0]))
            face.smooth = True
            for loop, side, t in zip(face.loops, (0,1,1,0), (idx,idx,idx+1,idx+1)):
                loop[uv].uv = ((strip + .08 + .84*side)/8, t/(len(rows)-1))
                if density is not None:
                    loop[density].uv = (0,.12)
    bm.to_mesh(strands.data)
    bm.free()
    strands.data.update()


def finish_body(meshes, rig, identity):
    joints = {bone.name[2:]: bone.head_local.copy() for bone in rig.data.bones}
    for obj in meshes:
        name = obj.name
        if name == 'Skin_Hands':
            def hand(p):
                side = 'l' if p.x < 0 else 'r'
                wrist = joints['hand_'+side]
                axis = (wrist - joints['forearm_'+side]).normalized()
                along = (p-wrist).dot(axis)
                palm = bell(along-.039,.023)
                fingers = smooth(.075,.114,along)
                return Vector((0, .0011*palm*math.tanh((p.y-wrist.y)*45), .0009*fingers))
            adjust_basis(obj, hand)
        if name.startswith(('Top_Bomber','Top_Fashion_Moto','Top_Fashion_Racer','Top_Fashion_Jacket','Top_Fashion_Pullover')):
            def cap(p):
                side = 'l' if p.x < 0 else 'r'
                pivot = joints['upper_arm_'+side]
                vector = p-pivot
                weight = bell(vector.x,.051) * bell(vector.z,.071) * smooth(.011,.052,vector.z)
                return Vector((-.020*vector.x, .029*vector.y, -.0040))*weight
            adjust_basis(obj, cap)
        if identity == 'jules' and name == 'Lower_midiskirt':
            values = obj.data.shape_keys.key_blocks['Hem_Seated']
            for vertex in obj.data.vertices:
                p = vertex.co
                key = values.data[vertex.index].co
                fall = max(0, 1.04-p.z)
                front = smooth(-.02,.105,p.y)
                free = smooth(.26,.55,fall)
                folds = bell(abs(p.x)-.075,.041)
                key.x -= p.x * .13 * free * front
                key.y += .012 * free * folds * front
                key.z -= .014 * free * (1-folds) * front
            neighbours = defaultdict(list)
            for a, b in (edge.vertices[:] for edge in obj.data.edges):
                neighbours[a].append(b)
                neighbours[b].append(a)
            original = [point.co.copy() for point in values.data]
            for i, linked in neighbours.items():
                if len(linked) < 4:
                    continue
                p = obj.data.vertices[i].co
                weight = .26 * smooth(.06,.23,1.04-p.z) * smooth(.008,.11,p.y)
                average = sum((original[j] for j in linked), Vector()) / len(linked)
                values.data[i].co = original[i].lerp(average, weight)


def finish_midi_lining(meshes, rig):
    """Clear the skin behind the folded skirt at the seated upper thigh."""
    joints = {bone.name[2:]: bone.head_local for bone in rig.data.bones}
    for obj in meshes:
        if obj.name not in ('Fashion_Legs', 'Fashion_Barefoot_Legs'):
            continue
        if obj.data.shape_keys is None:
            obj.shape_key_add(name='Basis')
        key = obj.shape_key_add(name='MidiSeatClearance')
        for vertex in obj.data.vertices:
            p = vertex.co
            weight = smooth(.695, .810, p.z)
            if weight == 0:
                continue
            side = 'l' if p.x < 0 else 'r'
            knee, hip = joints['shin_'+side], joints['thigh_'+side]
            axis = knee.lerp(hip, (p.z-knee.z)/(hip.z-knee.z))
            key.data[vertex.index].co += Vector((axis.x-p.x, axis.y-p.y, -.007)) * (.45 * weight)


def finish_fixed_hero(bpy, rig, meshes, identity):
    models = {obj.name: obj for obj in meshes}
    face = models['Face_'+identity]
    if face.data.shape_keys.key_blocks.get('Smile') is not None:
        return
    finish_face(face, identity)
    finish_body(meshes, rig, identity)
    if identity == 'jules':
        finish_midi_lining(meshes, rig)
    style = 'crop' if identity == 'ade' else 'bun'
    shell = models[f'Hair_{style}_{identity}']
    strands = models[f'Groom_{style}_{identity}']
    shape_hairstyle(shell, strands, identity)
    soften_hairline(shell)
    grow_hairline(bpy, shell, strands, identity)
