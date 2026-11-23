"""Bake the Build B skin, knit, denim, and hair surface detail."""

import math
from pathlib import Path

import bpy
import numpy as np

from garment_kit import _dilate, raster_uv, seam_height


def bell(value, width):
    return np.exp(-(value / width) ** 2)


def falloff(start, end, value):
    t = np.clip((value - start) / (end - start), 0, 1)
    return t * t * (3 - 2 * t)


def pixels(image):
    width, height = image.size
    data = np.empty(width * height * 4, np.float32)
    image.pixels.foreach_get(data)
    return data.reshape(height, width, 4)


def packed_image(path, rgb, normal=False):
    height, width = rgb.shape[:2]
    img = bpy.data.images.new(path.stem, width, height, alpha=False)
    if normal:
        img.colorspace_settings.name = 'Non-Color'
    rgba = np.ones((height, width, 4), np.float32)
    rgba[..., :3] = np.clip(rgb, 0, 1)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = str(path)
    img.file_format = 'PNG'
    img.save()
    img.pack()
    return img


def detail_nodes(material):
    shader = material.node_tree.nodes.get('Principled BSDF')
    colour = shader.inputs['Base Color'].links[0].from_node
    normal = shader.inputs['Normal'].links[0].from_node
    return colour, normal, normal.inputs['Color'].links[0].from_node


def surface_detail(obj, output, field, strength, index=0, replace=False, texture_key=None):
    """Lay spatial dye and relief over the garment's existing UV seams."""
    colour, mapping, normal = detail_nodes(obj.data.materials[index])
    original = colour.image
    size = original.size[0]
    pos, normals, used = raster_uv(obj, size, material_index=index)
    albedo = pixels(original)[..., :3].copy()
    if replace:
        albedo[used], relief = field(pos[used], normals[used], albedo[used])
    else:
        dye, relief = field(pos[used], normals[used])
        albedo[used] *= dye
    albedo = _dilate(albedo, used, 6)

    height = np.zeros(used.shape, np.float32)
    height[used] = relief
    height = _dilate(height[..., None], used, 5)[..., 0]
    positions = _dilate(pos, used, 5)
    for dimension in (0, 1):
        span = np.roll(positions, -1, dimension) - np.roll(positions, 1, dimension)
        step = np.clip(np.linalg.norm(span, axis=-1), .00045, .04)
        gradient = (np.roll(height, -1, dimension) - np.roll(height, 1, dimension)) / step
        if dimension == 0:
            dv = np.clip(gradient, -.55, .55)
        else:
            du = np.clip(gradient, -.55, .55)
    original_normal = normal.image
    if replace:
        xyz = np.zeros_like(albedo)
        xyz[..., 2] = 1
    else:
        old = pixels(original_normal)
        ix = np.floor(np.arange(size) * (old.shape[1] / size)).astype(int)
        iy = np.floor(np.arange(size) * (old.shape[0] / size)).astype(int)
        xyz = old[iy[:, None], ix[None, :], :3] * 2 - 1
    xyz[..., 0] -= du
    xyz[..., 1] -= dv
    xyz /= np.maximum(np.linalg.norm(xyz, axis=-1, keepdims=True), .01)
    colour_name = f'{texture_key}_albedo.png' if texture_key else Path(original.filepath).name
    normal_name = f'{texture_key}_normal.png' if texture_key else Path(original_normal.filepath).name
    colour.image = packed_image(output / colour_name, albedo)
    normal.image = packed_image(output / normal_name, xyz * .5 + .5, True)
    mapping.inputs['Strength'].default_value = strength


def face_surface(pos, normal, eye):
    x, y, z = pos.T
    side = np.abs(x)
    level = z - eye.z
    front = falloff(.047, eye.y + .013, y) * falloff(.05, .65, normal[:, 1])
    orbit = bell(side - eye.x, .023) * bell(level + .010, .011)
    socket = bell(side - eye.x, .022) * bell(level - .010, .006)
    cheek = bell(side - .047, .021) * bell(level + .035, .022)
    cheek_shadow = bell(side - .053, .019) * bell(level + .063, .020)
    nose = bell(x, .019) * bell(level + .038, .014)
    nostril = bell(side - .012, .007) * bell(level + .043, .0048)
    chin = bell(x, .029) * bell(level + .090, .009)
    temple = bell(side - .061, .015) * bell(level - .005, .026)
    blush = (cheek * .80 + nose * .56) * front
    shadow = front * (.15 * orbit + .12 * socket + .17 * nostril + .12 * cheek_shadow + .06 * chin + .09 * temple)
    grain = np.sin(x * 865 + z * 532) * np.sin(y * 783 - z * 1440)
    mottling = np.sin(x * 207 + y * 111) * np.sin(z * 332 - y * 91)
    value = 1 - shadow + .012 * grain + .027 * mottling
    colour = value[:, None] * (1 + blush[:, None] * np.array([.035, -.078, -.089]))
    philtrum = bell(side - .005, .0034) * bell(level + .052, .008)
    wrinkle = bell(level + .014 + .32 * (side - eye.x)**2 / .025, .0019) * bell(side - eye.x, .016)
    relief = front * (.00055 * philtrum - .00044 * wrinkle - .00050 * nostril
                      + .00042 * cheek + .000052 * grain)
    return colour, relief


def shared_face_style(pos, normal, eye, original):
    x, y, z = pos.T
    side, level = np.abs(x), z - eye.z
    front = falloff(eye.y - .030, eye.y + .014, y) * falloff(.04, .57, normal[:, 1])
    chin = bell(x, .040) * bell(level + .089, .021)
    cheek = bell(side - .046, .024) * bell(level + .044, .026)
    nose_wall = bell(side - .017, .009) * bell(level + .024, .017)
    socket = bell(side - eye.x, .021) * bell(level + .012, .010)
    centre = bell(x, .011) * bell(level + .026, .018)
    mottling = .008 * np.sin(x * 128 + z * 154) * np.sin(y * 149 - z * 86)
    mottling += .007 * np.sin(x * 431 + z * 55) * np.sin(y * 479 - z * 306)
    tone = .934 + mottling - front * (.031 * nose_wall + .036 * socket) + .015 * centre * front
    colour = tone[:, None] * np.array([1.025, 1, .982])
    colour += (chin * front)[:, None] * np.array([-.045, -.034, -.014])
    colour += (cheek * front)[:, None] * np.array([.017, -.007, -.010])
    # Carry each sculpt's own lip line, nostrils and brow pigment onto the
    # common skin finish without carrying over the broad cheek shading.
    lips = bell(x, .035) * bell(level + .065, .016) * falloff(eye.y + .012, eye.y + .032, y)
    brows = bell(side - eye.x, .025) * bell(level - .022, .008) * front
    nostrils = bell(side - .011, .009) * bell(level + .047, .006) * front
    keep = np.maximum.reduce((.91 * lips, .53 * brows, .64 * nostrils))[:, None]
    colour = colour * (1 - keep) + original * keep
    relief = front * (.00021 * centre - .00019 * nose_wall - .00013 * socket)
    relief += .00008 * np.sin(x * 1290 + z * 62) * lips
    return colour, relief


def knit_surface(pos, normal, joints):
    x, y, z = pos.T
    front = falloff(.011, .080, y)
    back = falloff(.01, .072, -y)
    side = np.abs(x)
    trunk = 1 - falloff(.147, .198, side)
    waist = bell(z - 1.111 - .39 * (side - .095) + .017 * np.sign(x), .017) * bell(side - .108, .054)
    underarm = bell(z - 1.326 - .69 * (side - .119), .022) * bell(side - .138, .035)
    drape = trunk * ((front + back * .64) * waist + .75 * underarm)
    sleeve = np.zeros_like(z)
    for hand, sign in (('l', -1), ('r', 1)):
        elbow = np.array(joints['forearm_' + hand])
        axis = np.array((joints['hand_' + hand] - joints['forearm_' + hand]).normalized())
        local = (pos - elbow) @ axis
        sleeve += (x * sign > .18) * (bell(local + .013 + y * .70, .010) - .57 * bell(local - .004 + y * .69, .012))
    stitches = .00016 * np.sin(x * 1650 + .8 * np.sin(z * 2000)) * np.sin(z * 1190 + 1.1 * np.cos(y * 1310))
    shadow = 1 - .086 * drape - .043 * np.maximum(sleeve, 0) + .035 * np.sin(x * 137 + z * 89) * np.sin(y * 170)
    return shadow[:, None], .0010 * drape + .00115 * sleeve + stitches


def denim_surface(pos, normal):
    x, y, z = pos.T
    side = np.abs(x)
    front = falloff(.019, .085, y)
    back = falloff(.015, .083, -y)
    leg = falloff(.091, .27, z)
    centre = np.interp(z, [.09, .49, .94], [.175, .142, .10])
    offset = side - centre
    seam = seam_height(y + .004, z, width=.0017, stitch_off=.0042, stitch_h=.00035)
    seam *= falloff(.030, .071, np.abs(offset)) * leg
    waist = 1.025 + .009 * back
    band = falloff(waist - .035, waist - .028, z)
    topstitch = .82 * seam_height(z - waist + .024, x * 2, stitch_off=.0035, stitch_h=.00037)
    yoke = seam_height(z - .973 - side * .104, x, stitch_off=.0032, stitch_h=.00027) * back
    pocket = seam_height(z - .992 + side * .275, x, stitch_off=.003, stitch_h=.00028)
    pocket *= front * falloff(.055, .083, side)
    fly = seam_height(x - .013, z, stitch_off=.0038, stitch_h=.00030) * front * falloff(.865, .938, z)
    cuff = seam_height(z - .108, side, stitch_off=.0030, stitch_h=.00031)
    whiskers = (bell(z - .829 - .57 * offset, .010) + .66 * bell(z - .794 - .28 * offset, .012))
    whiskers *= front * bell(offset, .070)
    wear = front * (bell(z - .66, .20) * bell(offset + .009, .056))
    folds = (bell(z - .517 + .35 * offset, .021) + .53 * bell(z - .479 + .48 * offset, .012)) * front
    folds += bell(z - .472 - .38 * offset, .015) * back
    crops = (bell(z - .177 + .52 * offset, .015) + .62 * bell(z - .143 - .30 * offset, .013)) * (front + .57 * back)
    twill = np.sin(z * 1130 + (x + y * .61) * 780) * np.sin(z * 1780 - y * 850)
    value = .77 + .19 * wear + .095 * whiskers + .053 * folds + .045 * crops - .055 * band + .020 * twill
    value += np.clip((seam + topstitch + yoke + pocket + fly + cuff) * 144, -.16, .11)
    relief = seam + topstitch + yoke + pocket + fly + cuff + .00014 * twill
    relief += .0009 * whiskers + .0011 * folds + .0010 * crops
    return value[:, None], relief



def length_material(source, output, name):
    """Make a cylindrical fibre atlas for the tied lengths and wrapped buns."""
    mat = source.copy()
    mat.name = 'hero_' + name
    y, x = np.mgrid[0:512, 0:512].astype(np.float32) / 512
    across = x * math.tau
    wave = across + .0048 * np.sin(y * math.tau * 2 + across * 3)
    clumps = .27 * np.cos(13 * wave + 1.3 * y) + .19 * np.cos(27 * wave - 2 * y)
    strands = .18 * np.cos(67 * wave) + .11 * np.cos(113 * wave + .6 * np.sin(y * 11))
    dye = np.clip(.59 + clumps + strands, .25, .96)
    colour, mapping, normal = detail_nodes(mat)
    colour.image = packed_image(output / (name + '_albedo.png'),
                                dye[..., None] * np.array([1.0, .985, .96]))
    fibre = np.roll(dye, 1, 1) - np.roll(dye, -1, 1)
    xyz = np.stack([fibre * 1.45, np.zeros_like(fibre), np.ones_like(fibre)], axis=-1)
    xyz /= np.linalg.norm(xyz, axis=-1, keepdims=True)
    normal.image = packed_image(output / (name + '_normal.png'), xyz * .5 + .5, True)
    mapping.inputs['Strength'].default_value = .91
    mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .44
    return mat
