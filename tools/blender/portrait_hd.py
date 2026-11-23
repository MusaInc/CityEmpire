"""Bake high-resolution, mesh-aligned skin and ocular detail for the two heroes."""

import numpy as np

from build_b_surface import packed_image, pixels
from garment_kit import _dilate, raster_uv


def resample(image, size):
    """Sample the existing colour or linear PBR channels with bilinear filtering."""
    src = pixels(image)[..., :3]
    index = (np.arange(size) + .5) * src.shape[0] / size - .5
    index = np.clip(index, 0, src.shape[0] - 1.001)
    lo = index.astype(int)
    mix = (index - lo).astype(np.float32)
    columns = src[:, lo] * (1 - mix[None, :, None]) + src[:, lo + 1] * mix[None, :, None]
    return columns[lo] * (1 - mix[:, None, None]) + columns[lo + 1] * mix[:, None, None]


def pores(points, frequency):
    cell = points * frequency
    box = np.floor(cell)
    jitter = np.stack([np.sin(box @ direction) for direction in (
        (21.19, 17.67, 91.13), (79.03, 31.47, 14.17), (47.21, 71.53, 51.37))], axis=1)
    jitter = .25 + .5 * np.mod(jitter * 1453.29, 1)
    distance = np.sum((cell - box - jitter) ** 2, axis=1)
    return np.exp(-distance / .031)


def ocular_atlas(size=512):
    y, x = (np.mgrid[0:size, 0:size] + .5) / size * 2 - 1
    r, a = np.hypot(x, y), np.arctan2(y, x)
    iris = r / .49
    fibres = .095 * np.sin(47*a + 11*r + 1.6*np.sin(9*a) * iris)
    fibres += .057 * np.sin(103*a - 21*r + .55*np.sin(21*a))
    fibres += .038 * np.sin(159*a + 11*r)
    crypt = np.maximum(0, np.sin(31*a + 8*r))*np.exp(-((iris-.57)/.121)**2)
    ring = np.clip((iris-.78)/.22, 0, 1)**1.45
    dye = np.clip(.66 + fibres - .185*crypt - .37*ring + .065*np.exp(-((iris-.53)/.17)**2), .17, .87)
    corner = np.clip((r-.45)*1.65, 0, 1)
    veins = np.maximum(0, np.sin(15*a + 7*r + 1.1*np.sin(a*8+r*22)))**56
    white = np.stack((.69-.19*corner, .66-.23*corner-.027*veins*corner,
                      .60-.23*corner-.036*veins*corner), axis=-1)
    pigment = dye[..., None]*np.array([1.0, .93, .80])
    coverage = np.clip((.497-r)/.023, 0, 1)[..., None]
    colour = white * (1-coverage) + pigment * coverage
    pupil = np.clip((.181-r)/.016, 0, 1)[..., None]
    return (colour*(1-pupil) + np.array([.012,.010,.009])*pupil).astype(np.float32)


def bake_portrait_hd(face, identity, output):
    slot = next(index for index, material in enumerate(face.data.materials)
                if material.name == 'hero_skin_face_' + identity)
    shader = face.data.materials[slot].node_tree.nodes['Principled BSDF']
    colour = shader.inputs['Base Color'].links[0].from_node
    normal = shader.inputs['Normal'].links[0].from_node
    normal_image = normal.inputs['Color'].links[0].from_node
    if colour.image.size[0] >= 2048:
        return
    size = 2048
    pos, direction, used = raster_uv(face, size, material_index=slot)
    points = pos[used]
    x, y, z = points.T
    ocular = face.data.materials['hero_eye']
    eye = ocular.node_tree.nodes['Principled BSDF'].inputs['Base Color'].links[0].from_node
    eye.image = packed_image(output / 'ocular_albedo.png', ocular_atlas())
    eye_vertices = {i for poly in face.data.polygons if face.data.materials[poly.material_index] == ocular
                    for i in poly.vertices}
    eye_height = sum(face.data.vertices[i].co.z for i in eye_vertices) / len(eye_vertices)
    front = np.clip((direction[used, 1] + .10)*1.15, .08, 1)
    cheeks = np.exp(-((np.abs(x)-.041)/.035)**2 - ((z-eye_height+.033)/.034)**2) * front
    pore = pores(points, 1660)
    second = pores(points + .0178, 2640)
    lip = np.exp(-(x/.024)**4 - ((z-eye_height+.064)/.010)**2) * front
    regional = .018 * np.sin(x*184 + z*148) * np.sin(y*111 - z*127)
    variation = regional - (.011 + .014*cheeks)*pore - .009*second
    albedo = resample(colour.image, size)
    albedo[used] *= 1 + variation[:, None]
    albedo[used] *= 1 + (.025 * cheeks + .021 * lip)[:, None] * np.array([.35, -.75, -1.0])
    colour.image = packed_image(output / f'face_{identity}_albedo.png', _dilate(albedo, used, 9))
    del albedo

    height = np.zeros(used.shape, np.float32)
    height[used] = -(0.000037+0.000035*cheeks)*pore - .000018*second
    height[used] += .000022*lip*np.sin(3050*x + .8*np.sin(z*460+x*110))
    normal_map = resample(normal_image.image, size) * 2 - 1
    for axis, channel in ((0, 1), (1, 0)):
        valid = used & np.roll(used, 1, axis) & np.roll(used, -1, axis)
        lengths = np.linalg.norm(np.roll(pos, -1, axis) - np.roll(pos, 1, axis), axis=-1)
        relief = np.roll(height, -1, axis) - np.roll(height, 1, axis)
        normal_map[..., channel][valid] = (.76*normal_map[..., channel][valid]
                                          - np.clip(relief[valid] / np.maximum(lengths[valid], .00024), -.22, .22))
    normal_map /= np.maximum(np.linalg.norm(normal_map, axis=-1, keepdims=True), 1e-6)
    normal_image.image = packed_image(output / f'face_{identity}_normal.png',
                                      _dilate(normal_map*.5 + .5, used, 7), normal=True)
    normal.inputs['Strength'].default_value = .74
