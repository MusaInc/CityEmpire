"""Reproject the supplied Jules portrait onto the authored face UVs.

The portrait contains baked light and painted eye and hair pixels. Use its
skin and lip detail while keeping the individual skinned facial surfaces.
"""
import numpy as np


def smooth(lo, hi, value):
    t = np.clip((value - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def bilinear(image, u, v):
    height, width = image.shape[:2]
    x = np.clip(u * (width - 1), 0, width - 1.001)
    y = np.clip((1 - v) * (height - 1), 0, height - 1.001)
    ix, iy = x.astype(int), y.astype(int)
    fx, fy = (x - ix)[:, None], (y - iy)[:, None]
    top = image[iy, ix] * (1 - fx) + image[iy, ix + 1] * fx
    bottom = image[iy + 1, ix] * (1 - fx) + image[iy + 1, ix + 1] * fx
    return top * (1 - fy) + bottom * fy


def project(colour, points, normals, eye, mouth, source):
    """Fit the portrait landmarks, filter painted features and blend onto skin."""
    x, depth, z = points.T
    ix, iy, iz = eye
    u = .5 + x * (.124 / ix)
    lip_z = mouth.z - .001
    v = np.interp(z, [lip_z - .048, lip_z - .028, lip_z, iz - .034, iz, iz + .025, iz + .059],
                  [.870, .756, .611, .493, .337, .244, .125])
    ref = bilinear(source, u, v)
    skin = smooth(.095, .25, ref[:, 0]) * smooth(.055, .14, ref[:, 1])
    centre = smooth(.20, .76, normals[:, 1]) * smooth(iy - .078, iy - .006, depth)
    edge = 1 - smooth(.055, .083, abs(x))
    mask = skin * centre * edge * smooth(.125, .19, v) * (1 - smooth(.78, .93, v))
    for side in (-1, 1):
        ur = u - (.5 + side * .124)
        orbit = (ur / .079) ** 2 + ((v - .334) / .044) ** 2
        brow = (ur / .109) ** 2 + ((v - .262) / .043) ** 2
        mask *= smooth(.72, 1.32, orbit) * smooth(.66, 1.25, brow)
    # Estimate the local light field with a broad reference sample, retaining
    # fine freckles, dermal colour and lip texture without a second nose shadow.
    ambient = sum(bilinear(source, u + du, v + dv) for du, dv in (
        (-.025, 0), (.025, 0), (0, -.028), (0, .028),
        (-.021, -.020), (.021, .020), (-.021, .020), (.021, -.020))) / 8
    signal = np.clip(ref - ambient, -.069, .057)
    chroma = ref / np.maximum(ref[:, :1], .10)
    blend = np.clip(signal * 1.22 + (chroma - np.array([1, .63, .46])) * .14, -.19, .12)
    lip = np.exp(-((u - .5) / .087) ** 4 - ((v - .611) / .034) ** 4)
    blend[:, 1] -= lip * .096
    blend[:, 2] -= lip * .068
    colour *= 1 + mask[:, None] * blend
    return np.clip(colour, .35, 1)


def finish_skin_material(face, identity, output):
    """Bake different reflectance on the cheek, T-zone and lips into the ORM."""
    from build_b_surface import packed_image, pixels
    from garment_kit import _dilate, raster_uv

    slot = next(i for i, material in enumerate(face.data.materials)
                if material.name.startswith('hero_skin_face_'))
    shader = face.data.materials[slot].node_tree.nodes['Principled BSDF']
    separate = shader.inputs['Roughness'].links[0].from_node
    texture = separate.inputs[0].links[0].from_node
    old = pixels(texture.image)
    size = 512
    positions, normals, valid = raster_uv(face, size, material_index=slot)
    xs = np.floor((np.arange(size) + .5) * old.shape[1] / size).astype(int)
    ys = np.floor((np.arange(size) + .5) * old.shape[0] / size).astype(int)
    orm = old[ys[:, None], xs[None, :], :3].copy()

    ocular_vertices = {i for poly in face.data.polygons
                       if face.data.materials[poly.material_index].name == 'hero_eye'
                       for i in poly.vertices}
    eye_height = sum(face.data.vertices[i].co.z for i in ocular_vertices) / len(ocular_vertices)
    x, depth, z = positions[valid].T
    forward = smooth(.08, .76, normals[valid, 1])
    forehead = np.exp(-(x/.034)**2 - ((z-eye_height-.033)/.036)**2)
    nose = np.exp(-(x/.016)**2 - ((z-eye_height+.027)/.021)**2)
    lip = np.exp(-(x/.022)**4 - ((z-eye_height+.064)/.007)**2)
    detail = np.sin(z*3100+x*1900) * np.sin(x*2020-depth*2400)
    orm[..., 1][valid] = .59 + forward * (.018 * detail - .085 * forehead
                                         - .145 * nose - .079 * lip)
    texture.image = packed_image(output / ('hero_skin_face_' + identity + '_orm.png'),
                                 _dilate(orm, valid, 9), normal=True)
