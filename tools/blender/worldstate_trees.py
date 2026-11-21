"""Bake the Natural Trees Revision 2 Blender study into WorldState LODs.

Run: blender -b Natural_Trees_Revision_2.blend -t 4 -P tools/blender/worldstate_trees.py
"""
import math
from pathlib import Path

import bpy
import numpy as np

OUTPUT = Path(__file__).resolve().parents[2] / "assets" / "models"
STUDIES = {
    "oak": (30, 20.18, (0.12, 0.24, 0.039), (0.15, 0.094, 0.051)),
    "birch": (21, 22.95, (0.17, 0.31, 0.048), (0.68, 0.63, 0.51)),
    "pine": (4, 23.02, (0.086, 0.19, 0.054), (0.16, 0.093, 0.058)),
}


def physically_based(name, color, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat, bsdf


def canopy(name, points, cell_size, tile, leaf_color, minimum, directions):
    # Sort real leaf/needle centres into cells, then bake each cell onto
    # crossed planes. Both LODs preserve gaps in the crown and branch outline.
    rng = np.random.default_rng(170)
    keys = np.floor(points / cell_size).astype(np.int32)
    _, group = np.unique(keys, axis=0, return_inverse=True)
    order = np.argsort(group)
    batches = np.split(points[order], np.flatnonzero(np.diff(group[order])) + 1)
    batches = [batch for batch in batches if len(batch) >= minimum]
    columns = math.ceil(math.sqrt(len(batches) * len(directions)))
    atlas_size = columns * tile
    pixels = np.zeros((atlas_size, atlas_size, 4), dtype=np.float32)
    pixels[:, :, :3] = leaf_color
    vertices, faces, uvs = [], [], []
    for cell, sample in enumerate(batches):
        filtered = sample[rng.choice(len(sample), min(len(sample), 850), replace=False)]
        for az, tilt in directions:
            right = np.array((math.cos(az), math.sin(az), 0))
            up = np.array((-math.sin(az)*math.sin(tilt), math.cos(az)*math.sin(tilt), math.cos(tilt)))
            normal = np.cross(right, up)
            u, v = filtered @ right, filtered @ up
            left, bottom = np.min(u) - .30, np.min(v) - .30
            right_edge, top = np.max(u) + .30, np.max(v) + .30
            depth = float(np.median(filtered @ normal))
            index = len(faces)
            col, row = index % columns, index // columns
            patch = pixels[row*tile:(row+1)*tile, col*tile:(col+1)*tile]
            us = (u - left) / (right_edge - left) * (tile-4) + 2
            vs = (v - bottom) / (top - bottom) * (tile-4) + 2
            lengths = rng.uniform(tile*.040, tile*.092, size=len(filtered))
            if name == "pine":
                lengths *= .95
            for du, dv, r, angle, shade in zip(us, vs, lengths, rng.uniform(0, math.tau, len(us)), rng.uniform(.60, 1.28, len(us))):
                x0, x1 = max(2, int(du-r-1)), min(tile-2, int(du+r+2))
                y0, y1 = max(2, int(dv-r-1)), min(tile-2, int(dv+r+2))
                y, x = np.ogrid[y0:y1, x0:x1]
                a = (x-du)*math.cos(angle) + (y-dv)*math.sin(angle)
                b = (x-du)*math.sin(angle) - (y-dv)*math.cos(angle)
                leaf = (a*a + b*b*(4.2 if name == "pine" else 2.0)) < r*r
                fragment = patch[y0:y1, x0:x1]
                fragment[leaf, :3] = np.asarray(leaf_color)*shade
                fragment[leaf, 3] = 1.0
            n = len(vertices)
            vertices.extend((right*x + up*y + normal*depth).tolist() for x, y in ((left,bottom), (right_edge,bottom), (right_edge,top), (left,top)))
            faces.append((n, n+1, n+2, n+3))
            uvs.extend(((col*tile+x)/atlas_size, (row*tile+y)/atlas_size) for x,y in ((2,2), (tile-2,2), (tile-2,tile-2), (2,tile-2)))

    image = bpy.data.images.new(f"{name}_{tile}", atlas_size, atlas_size, alpha=True)
    # Byte images expect display-encoded RGB. Alpha is already linear.
    rgb = pixels[:, :, :3]
    pixels[:, :, :3] = np.where(rgb <= .0031308, rgb*12.92, 1.055*np.power(rgb, 1/2.4)-.055)
    image.pixels.foreach_set(pixels.ravel())
    image.pack()
    mat, bsdf = physically_based("Foliage", leaf_color, .83)
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mat.node_tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    mesh = bpy.data.meshes.new(f"{name}_canopy")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.materials.append(mat)
    uv = mesh.uv_layers.new()
    for loop in mesh.loops:
        uv.data[loop.index].uv = uvs[loop.vertex_index]
    return bpy.data.objects.new("Canopy", mesh)


def scaffold(source, name, bark_color, target):
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = "Scaffold"
    obj.data.materials.clear()
    mat, bsdf = physically_based("Bark", bark_color, .88)
    if name != "birch":
        photo = next(image for image in bpy.data.images if image.name.startswith("bark_diff"))
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = photo
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    obj.data.materials.append(mat)
    triangles = sum(len(poly.vertices)-2 for poly in obj.data.polygons)
    decimate = obj.modifiers.new("Mobile branch budget", "DECIMATE")
    decimate.ratio = target / triangles
    return obj


for name, (stride, height, leaf_color, bark_color) in STUDIES.items():
    branch = bpy.data.objects[f"{name} | natural scaffold and buttresses"]
    leaves = bpy.data.objects[f"{name} | attached leaves and needles"]
    coords = np.empty(len(leaves.data.vertices)*3, dtype=np.float32)
    leaves.data.vertices.foreach_get("co", coords)
    points = coords.reshape(-1, stride, 3).mean(axis=1)
    for suffix, cell_size, tile, density, budget, directions in (
        ("near", 2.7, 48, 35, 2500, ((.3,.1), (1.6,.2), (2.6,1.1))),
        ("far", 5.6, 32, 100, 380, ((.35,.1), (2.0,.65))),
    ):
        wood = scaffold(branch, name, bark_color, budget)
        crown = canopy(name, points, cell_size, tile, leaf_color, density, directions)
        bpy.ops.object.select_all(action="DESELECT")
        for obj in (wood, crown):
            bpy.context.scene.collection.objects.link(obj)
            obj.location = (0, 0, 0)
            scale = 9.2 / height
            obj.scale = (scale * .83, scale * .83, scale)
            obj.select_set(True)
        bpy.context.view_layer.objects.active = wood
        bpy.ops.export_scene.gltf(
            filepath=str(OUTPUT / f"world_tree_{name}_{suffix}.glb"),
            use_selection=True, export_apply=True,
        )
        for obj in (wood, crown):
            bpy.data.objects.remove(obj, do_unlink=True)
