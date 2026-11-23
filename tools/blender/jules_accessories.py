"""Fit Jules's existing hoops, crew socks and fixed updo to the character."""
import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Vector

from build_b_surface import surface_detail
from hero_groom import eye_centre, mesh_tree, ribbon, strand_opacity, tied_freedom
from wardrobe_quality import adjust_basis, smooth


def fit_hoops(face):
    material = face.data.materials.find('hero_earring_gold')
    skin = mesh_tree(face.data, face.data.materials.find('hero_skin_face_jules'))
    indices = {i for p in face.data.polygons if p.material_index == material for i in p.vertices}
    eye = eye_centre(face)
    for sign in (-1, 1):
        vertices = [face.data.vertices[i] for i in indices if sign * face.data.vertices[i].co.x > 0]
        apex = max(vertices, key=lambda v: v.co.z).co.copy()
        height = eye.z - .044
        depth = eye.y - .0615
        anchor, _, _, _ = skin.ray_cast(Vector((sign*.16, depth, height)), Vector((-sign, 0, 0)), .12)
        if anchor is None or abs(anchor.x) < .065:
            raise RuntimeError(f'Could not locate Jules’s earlobe on side {sign}')
        delta = anchor + Vector((sign*.0007, 0, .0003)) - apex
        for vertex in vertices:
            vertex.co += delta
            for key in face.data.shape_keys.key_blocks:
                key.data[vertex.index].co += delta
    face.data.update()


def raise_socks(collection):
    name = 'Fashion_Lounge_Socks'
    old = collection.models.pop(name)
    knit = old.data.materials[0]
    collection.meshes.remove(old)
    bpy.data.objects.remove(old, do_unlink=True)
    socks = collection.clone('Fashion_Legs', name)
    collection.cut(socks, lambda p: min(p.z - .055, .236 - p.z), .0025)
    socks.data.materials.clear()
    socks.data.materials.append(knit)
    joints = collection.rig.data.bones

    def knit_clearance(p):
        side = 'l' if p.x < 0 else 'r'
        ankle = joints['b_foot_' + side].head_local
        knee = joints['b_shin_' + side].head_local
        centre = ankle.lerp(knee, (p.z - ankle.z) / (knee.z - ankle.z))
        radial = Vector((p.x-centre.x, p.y-centre.y, 0)).normalized()
        cuff = smooth(.218, .230, p.z)
        return radial * (.0035 + .0019 * cuff)

    adjust_basis(socks, knit_clearance)


def cap_fibres(points, _normals):
    x, y, z = points.T
    # The brushed strands converge toward the tie. Keep the fine breakup
    # under the existing broader locks and the approved hairline texture.
    phi = np.arctan2(x + .005, y + .070)
    spread = np.hypot(x + .005, y + .070)
    phase = 274 * phi + 2.1 * np.sin(spread*123 + z*56)
    ribbons = np.sin(phase) + .43 * np.sin(phase * 1.71 - z * 217)
    return (1 + .024 * ribbons)[:, None], .000075 * ribbons


def add_updo_strands(groom, shell, eye):
    """Lay tapered strand cards along existing scalp and wound bun surfaces."""
    batch = ([], [], [])
    rng = random.Random(19277)
    lengths = shell.data.materials.find('hero_hair_lengths_b')
    skin = mesh_tree(shell.data, 0)
    coil = mesh_tree(shell.data, lengths)
    coil_indices = {i for p in shell.data.polygons if p.material_index == lengths for i in p.vertices}
    knot = sum((shell.data.vertices[i].co for i in coil_indices), Vector()) / len(coil_indices)

    for strand in range(56):
        phi = strand * 2.399963
        bundle = strand >= 30
        if bundle:
            tree, origin = coil, knot
        else:
            tree, origin = skin, Vector((0, eye.y - .080, eye.z + .021))
        centres, normals = [], []
        for step in range(9):
            t = step / 8
            sweep = phi + (.95 if bundle else .27) * t
            height = .46 + .22 * math.sin(phi*2) - .27 * t if bundle else .38 + .54*t
            direction = Vector((math.sin(sweep), math.cos(sweep), height)).normalized()
            hit, normal, _, _ = tree.ray_cast(origin + direction*.27, -direction, .27)
            if hit is None or normal.dot(direction) < .10:
                break
            if centres and (hit-centres[-1]).length > .024:
                break
            lift = (.0009 if bundle else .0013) * math.sin(math.pi*t) + .00045*t - .00021
            centres.append(hit + normal*lift)
            normals.append(normal)
        if len(centres) >= 7:
            ribbon(batch, centres, normals, rng.uniform(.00115, .0028), strand % 8)

    points, polygons, texels = batch
    bm = bmesh.new()
    bm.from_mesh(groom.data)
    tex = bm.loops.layers.uv.get('SurfaceUV')
    motion = bm.loops.layers.uv.get('ClothFreedom')
    weights = bm.verts.layers.deform.verify()
    head = groom.vertex_groups['b_head'].index
    verts = [bm.verts.new(p) for p in points]
    for vertex in verts:
        vertex[weights][head] = 1.0
    for indices in polygons:
        face = bm.faces.new([verts[i] for i in indices])
        face.smooth = True
        for corner, index in zip(face.loops, indices):
            corner[tex].uv = texels[index]
            p = corner.vert.co
            corner[motion].uv = (tied_freedom(p, eye, 'bun')*.60, strand_opacity(p, eye, 'bun'))
    bm.to_mesh(groom.data)
    bm.free()
    groom.data.update()


def finish_jules_accessories(collection, output):
    if collection.rig.get('jules_accessory_fit'):
        return
    output.mkdir(parents=True, exist_ok=True)
    models = collection.models
    face = models['Face_jules']
    fit_hoops(face)
    raise_socks(collection)
    shell = models['Hair_bun_jules']
    add_updo_strands(models['Groom_bun_jules'], shell, eye_centre(face))
    scalp = shell.data.materials[0].node_tree.nodes['Principled BSDF']
    scalp.inputs['Roughness'].default_value = .62
    surface_detail(shell, output, cap_fibres, .69, texture_key='jules_bun_fibres')
    collection.rig['jules_accessory_fit'] = 1
