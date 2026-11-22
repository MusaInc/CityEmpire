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


def stamp_leaf(patch, polygon, color, padding):
    # Even/odd polygon fill in pixel space, with subpixel edge coverage.
    lo = np.maximum(padding, np.floor(polygon.min(axis=0)).astype(int))
    hi = np.minimum(patch.shape[0] - padding, np.ceil(polygon.max(axis=0)).astype(int))
    if np.any(hi <= lo):
        return
    x, y = np.meshgrid(np.arange(lo[0], hi[0]), np.arange(lo[1], hi[1]))
    edge_a = polygon
    edge_b = np.roll(polygon, -1, axis=0)
    d = edge_b - edge_a
    alpha = np.zeros(x.shape, dtype=np.float32)
    for dx, dy in ((.24, .24), (.76, .24), (.24, .76), (.76, .76)):
        px, py = (x + dx)[..., None], (y + dy)[..., None]
        crosses = (edge_a[:, 1] > py) != (edge_b[:, 1] > py)
        boundary = edge_a[:, 0] + (py - edge_a[:, 1]) * d[:, 0] / np.where(abs(d[:, 1]) > 1e-8, d[:, 1], 1.0)
        alpha += (np.count_nonzero(crosses & (px < boundary), axis=-1) % 2) * .25
    dest = patch[lo[1]:hi[1], lo[0]:hi[0]]
    covered = alpha > 0
    dest[covered, :3] = color
    dest[:, :, 3] = np.maximum(dest[:, :, 3], alpha)


def canopy(name, leaf_shapes, leaf_tints, cell_size, tile, leaf_color, minimum, directions, lod):
    # Project the Blender study's serrated leaves and needles into the
    # existing layered cards, preserving their orientation and spacing.
    points = leaf_shapes.mean(axis=1)
    crown_center = points.mean(axis=0)
    rng = np.random.default_rng(170)
    keys = np.floor(points / cell_size).astype(np.int32)
    _, group = np.unique(keys, axis=0, return_inverse=True)
    order = np.argsort(group, kind="stable")
    batches = np.split(order, np.flatnonzero(np.diff(group[order])) + 1)
    batches = [ids for ids in batches if len(ids) >= minimum]
    columns = math.ceil(math.sqrt(len(batches) * len(directions)))
    atlas_size = columns * tile
    pixels = np.empty((atlas_size, atlas_size, 4), dtype=np.float32)
    pixels[:, :, :3] = leaf_color
    pixels[:, :, 3] = 0.0
    vertices, faces, uvs, normals = [], [], [], []
    pad = 4
    for ids in batches:
        if len(ids) > 1900:
            ids = rng.choice(ids, 1900, replace=False)
        sample = points[ids]
        centre = sample.mean(axis=0)
        direction = (centre - crown_center) / np.array((1.0, 1.0, .62))
        for az, tilt in directions:
            right = np.array((math.cos(az), math.sin(az), 0))
            up = np.array((-math.sin(az)*math.sin(tilt), math.cos(az)*math.sin(tilt), math.cos(tilt)))
            normal = np.cross(right, up)
            projected = leaf_shapes[ids] @ np.stack((right, up), axis=1)
            lo = np.min(projected, axis=(0, 1)) - .06
            hi = np.max(projected, axis=(0, 1)) + .06
            depth = float(np.median(sample @ normal))
            index = len(faces)
            col, row = index % columns, index // columns
            patch = pixels[row*tile:(row+1)*tile, col*tile:(col+1)*tile]
            uv_px = (projected - lo) / (hi - lo) * (tile - 2*pad) + pad
            z = sample @ normal
            z_low, z_range = z.min(), max(np.ptp(z), .01)
            for i in np.argsort(z):
                outline = uv_px[i]
                # Small rear needles need coverage at mips; preserve each
                # real direction and centre while widening only its footprint.
                scale = 1.25 if name == "pine" else 1.12
                outline = outline.mean(axis=0) + (outline - outline.mean(axis=0)) * scale
                shade = .73 + .26 * rng.random() + .14 * (z[i] - z_low) / z_range
                stamp_leaf(patch, outline, leaf_tints[ids[i]] * shade, pad)
            n = len(vertices)
            left, bottom = lo
            right_edge, top = hi
            for x, y in ((left, bottom), (right_edge, bottom), (right_edge, top), (left, top)):
                p = right*x + up*y + normal*depth
                vertices.append(p.tolist())
                outward = direction + (p - centre) * .38 + np.array((0, 0, 2.6))
                normals.append((outward / max(np.linalg.norm(outward), .001)).tolist())
            faces.append((n, n+1, n+2, n+3))
            uvs.extend(((col*tile+x)/atlas_size, (row*tile+y)/atlas_size)
                       for x,y in ((pad,pad), (tile-pad,pad), (tile-pad,tile-pad), (pad,tile-pad)))

    image = bpy.data.images.new(f"{name}_{48 if lod == 'near' else 32}", atlas_size, atlas_size, alpha=True)
    rgb = pixels[:, :, :3]
    pixels[:, :, :3] = np.where(rgb <= .0031308, rgb*12.92, 1.055*np.power(rgb, 1/2.4)-.055)
    image.pixels.foreach_set(pixels.ravel())
    image.pack()
    mat, bsdf = physically_based("Foliage", leaf_color, .88)
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mat.node_tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    mesh = bpy.data.meshes.new(f"{name}_canopy")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.normals_split_custom_set_from_vertices(normals)
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
    shape = coords.reshape(-1, stride, 3)
    if name != "pine":
        shape = np.concatenate([shape[:, ::3], shape[:, 2::3][:, ::-1]], axis=1)
    materials = np.empty(len(leaves.data.polygons), dtype=np.int32)
    leaves.data.polygons.foreach_get("material_index", materials)
    stride_faces = 1 if name == "pine" else (stride // 3 - 1) * 2
    palette = np.asarray([mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value[:3]
                          for mat in leaves.data.materials])
    tints = palette[materials[::stride_faces]]
    for suffix, cell_size, tile, density, budget, directions in (
        ("near", 2.7, 60, 26, 2500, ((.3,.2), (1.6,.5), (2.6,1.1))),
        ("far", 5.6, 40, 70, 380, ((.35,.2), (2.0,.75))),
    ):
        wood = scaffold(branch, name, bark_color, budget)
        crown = canopy(name, shape, tints, cell_size, tile, leaf_color, density, directions, suffix)
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
