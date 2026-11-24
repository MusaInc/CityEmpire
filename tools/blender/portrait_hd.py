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
    """High-realism ocular atlas: luminous radial iris stroma (tinted cleanly by the game shader),
    warm collarette depth, crisp dark limbal border, deep black pupil, and natural warm sclera."""
    y, x = (np.mgrid[0:size, 0:size] + .5) / size * 2 - 1
    r, a = np.hypot(x, y), np.arctan2(y, x)
    iris = r / .49
    # Multi-frequency organic radial iris fibres & crypts with bright inner collarette depth.
    fibres = .135 * np.sin(53 * a + 9 * r + 1.8 * np.sin(11 * a) * iris)
    fibres += .078 * np.sin(113 * a - 17 * r + .65 * np.sin(23 * a))
    fibres += .045 * np.sin(179 * a + 13 * r)
    crypt = np.maximum(0, np.sin(29 * a + 7 * r)) * np.exp(-((iris - .56) / .135)**2)
    collarette = np.exp(-((iris - .43) / .13)**2)
    limbal = np.clip((iris - .76) / .24, 0, 1)**1.35
    dye = np.clip(.84 + fibres - .19 * crypt - .56 * limbal + .18 * collarette, .20, 1.0)
    # Natural warm off-white sclera with soft corner shading & subtle capillaries.
    corner = np.clip((r - .44) * 1.65, 0, 1)
    veins = np.maximum(0, np.sin(15 * a + 7 * r + 1.1 * np.sin(a * 8 + r * 22)))**50
    white = np.stack((.84 - .18 * corner, .81 - .21 * corner - .026 * veins * corner,
                      .77 - .22 * corner - .034 * veins * corner), axis=-1)
    # Neutral-warm luminous iris pigment so shader tint produces rich brown/hazel/blue instead of black.
    pigment = dye[..., None] * np.array([1.0, .96, .89]) + collarette[..., None] * np.array([.11, .075, .025])
    coverage = np.clip((.498 - r) / .022, 0, 1)[..., None]
    colour = white * (1 - coverage) + np.clip(pigment, 0, 1) * coverage
    pupil = np.clip((.174 - r) / .015, 0, 1)[..., None]
    return (colour * (1 - pupil) + np.array([.008, .007, .008]) * pupil).astype(np.float32)


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
    # Subtle, ultra-clean natural skin micro-variation (keep fine pore relief in normal map without dirtying albedo!).
    regional = .005 * np.sin(x*184 + z*148) * np.sin(y*111 - z*127)
    variation = regional - (.004 + .005*cheeks)*pore - .003*second
    albedo = resample(colour.image, size)
    albedo[used] *= 1 + variation[:, None]
    albedo[used] *= 1 + (.016 * cheeks + .018 * lip)[:, None] * np.array([.35, -.75, -1.0])
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
