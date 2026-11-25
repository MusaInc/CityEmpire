"""WorldState vehicle texture pipeline (Blender 4.5).

Two jobs, one process each (tools/vehicle_tex/run.sh drives the fleet):

  library   blender -b --factory-startup --python tools/blender/ws_texture.py -- library <out_dir>
      Shared, tileable PBR detail maps generated from Blender node textures
      (baked to images on a plane through Cycles) and, for the moulded
      parts, real geometry baked selected-to-active: sidewall lettering,
      tread blocks, drilled rotor, machined alloy, lamp optics, leather,
      fabric, plastics, orange-peel clear coat. One normal map
      (<family>_n.png) and one packed mask (<family>_m.png: R cavity,
      G roughness, B metal mask, A albedo variation) per family.

  vehicle   blender -b --factory-startup --python tools/blender/ws_texture.py -- vehicle <in.glb> <out.glb> <bake.png|-> <res> <kind> [ref.glb]
      kind: body (road bodies, ground plane under the AO), wheel, craft,
      model (rail, ships, legacy cars) or entry (door/cabin splits of a
      body: UVs transferred from the textured body <ref.glb>, no own bake).
      * UV0 "Tile": a real unwrap (Smart UV Project, 55 deg islands), scaled
        so 1 UV unit = 1 metre on every island. Tileable library maps use
        it at a fixed density, so paint, leather and plastic grain read the
        same size on every vehicle. Wheels get a cylindrical tread and a
        planar sidewall/face unwrap that the tyre/alloy/rotor maps expect.
      * UV1 "Bake": the same islands packed into 0..0.97 (the top-right
        strip stays white: glass, lenses and anything without its own
        bake sample it).
      * Bake (Cycles, emit): R ambient occlusion (0.55 m, multiplied with a
        4 cm cavity pass so shut lines, vents and panel gaps darken),
        G convex edge (bevel normal vs face normal: chips and edge wear),
        B cavity alone (dirt gathers there). Glass and lenses are left out
        of the occluders (a copy of the meshes is baked, the originals and
        their materials are exported untouched).
      Geometry, normals, node names/transforms and material names are
      kept exactly; only the UV layers change.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]

GLASSY = {"glass", "glass_clear", "lens", "lens_red", "rotor_blur", "bridge_glass", "car_glass", "train_window"}
WHITE_UV = (0.992, 0.992)
PACK_FIT = 0.97


def base_name(mat):
    return mat.name.split(".")[0] if mat else ""


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 16
    sc.render.threads_mode = "FIXED"
    sc.render.threads = int(os.environ.get("BAKE_THREADS", "6"))
    sc.render.bake.margin = 6
    sc.render.bake.margin_type = "EXTEND"
    return sc


def new_image(name, res, float_buf=False):
    img = bpy.data.images.new(name, res, res, alpha=False, float_buffer=float_buf)
    img.colorspace_settings.name = "Non-Color"
    return img


def pixels(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)


def save_png(arr, path, channels=4):
    """arr: HxWxC float 0..1 (row 0 = bottom, Blender order)."""
    h, w = arr.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=channels == 4)
    img.colorspace_settings.name = "Non-Color"
    out = np.ones((h, w, 4), dtype=np.float32)
    out[:, :, :arr.shape[2]] = np.clip(arr, 0.0, 1.0)
    img.pixels.foreach_set(out.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


# --------------------------------------------------------------------------- nodes

class Nodes:
    """Tiny helper for building emission bake materials."""

    def __init__(self, name):
        self.mat = bpy.data.materials.new(name)
        self.mat.use_nodes = True
        self.nt = self.mat.node_tree
        self.nt.nodes.clear()
        self.out = self.nt.nodes.new("ShaderNodeOutputMaterial")
        self.em = self.nt.nodes.new("ShaderNodeEmission")
        self.link(self.em.outputs[0], self.out.inputs[0])

    def node(self, kind, **props):
        n = self.nt.nodes.new(kind)
        for k, v in props.items():
            if k.startswith("in_"):
                key = k[3:]
                n.inputs[int(key) if key.isdigit() else key.replace("_", " ")].default_value = v
            else:
                setattr(n, k, v)
        return n

    def link(self, a, b):
        self.nt.links.new(a, b)

    def math(self, op, a, b=None, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                self.link(v, n.inputs[i])
        return n.outputs[0]

    def emit(self, r, g=None, b=None):
        if g is None:
            self.link(r, self.em.inputs[0])
            return
        c = self.node("ShaderNodeCombineColor")
        for i, v in enumerate((r, g, b)):
            if isinstance(v, (int, float)):
                c.inputs[i].default_value = v
            else:
                self.link(v, c.inputs[i])
        self.link(c.outputs[0], self.em.inputs[0])

    def image_target(self, img):
        n = self.node("ShaderNodeTexImage")
        n.image = img
        self.nt.nodes.active = n
        n.select = True
        return n


# --------------------------------------------------------------------------- library

def seamless_coords(nd, scale):
    """UV on a torus in 4D: x,y,z + w from cos/sin of u and v, so 4D noise
    and Voronoi tile exactly across the 0..1 square."""
    tc = nd.node("ShaderNodeTexCoord")
    sep = nd.node("ShaderNodeSeparateXYZ")
    nd.link(tc.outputs["UV"], sep.inputs[0])
    r = scale / (2.0 * math.pi)
    parts = []
    for comp in (0, 1):
        ang = nd.math("MULTIPLY", sep.outputs[comp], 2.0 * math.pi)
        parts.append(nd.math("MULTIPLY", nd.math("COSINE", ang), r))
        parts.append(nd.math("MULTIPLY", nd.math("SINE", ang), r))
    comb = nd.node("ShaderNodeCombineXYZ")
    nd.link(parts[0], comb.inputs[0])
    nd.link(parts[1], comb.inputs[1])
    nd.link(parts[2], comb.inputs[2])
    return comb.outputs[0], parts[3]


def noise4(nd, scale, detail=4.0, rough=0.55, seed=0.0):
    vec, w = seamless_coords(nd, scale)
    n = nd.node("ShaderNodeTexNoise", noise_dimensions="4D", in_Detail=detail, in_Roughness=rough, in_Scale=1.0)
    nd.link(vec, n.inputs["Vector"])
    nd.link(nd.math("ADD", w, seed * 17.3), n.inputs["W"])
    return n.outputs["Fac"]


def voronoi4(nd, scale, feature="F1", out="Distance", seed=0.0, rand=1.0):
    vec, w = seamless_coords(nd, scale)
    v = nd.node("ShaderNodeTexVoronoi", voronoi_dimensions="4D", feature=feature, in_Scale=1.0)
    v.inputs["Randomness"].default_value = rand
    nd.link(vec, v.inputs["Vector"])
    nd.link(nd.math("ADD", w, seed * 11.1), v.inputs["W"])
    return v.outputs[out]


def bake_plane_emit(nd, res, plane):
    img = new_image(nd.mat.name + "_img", res, float_buf=True)
    nd.image_target(img)
    plane.data.materials.clear()
    plane.data.materials.append(nd.mat)
    bpy.ops.object.select_all(action="DESELECT")
    plane.select_set(True)
    bpy.context.view_layer.objects.active = plane
    bpy.ops.object.bake(type="EMIT", margin=0, use_clear=True)
    return pixels(img)[:, :, :3]


def lib_plane():
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.5, 0.5, 0))
    return bpy.context.object


def height_to_normal(h, strength, wrap=True):
    """Tangent-space normal (Godot/OpenGL, +Y up in texture space) from a
    height field (rows bottom-up, as Blender stores pixels)."""
    if wrap:
        dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
        dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    else:
        dx = np.gradient(h, axis=1)
        dy = np.gradient(h, axis=0)
    n = np.dstack([-dx * strength, -dy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def blur(a, r=1, wrap=True):
    out = a.copy()
    for _ in range(r):
        if wrap:
            out = (out + np.roll(out, 1, 0) + np.roll(out, -1, 0) + np.roll(out, 1, 1) + np.roll(out, -1, 1)) / 5.0
        else:
            p = np.pad(out, 1, mode="edge")
            out = (p[1:-1, 1:-1] + p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 5.0
    return out


def write_family(out, fam, height, strength, cavity, rough, metal, albedo, wrap=True):
    n = height_to_normal(height, strength, wrap)
    save_png(n, os.path.join(out, fam + "_n.png"), 3)
    m = np.dstack([cavity, rough, metal, albedo])
    save_png(m, os.path.join(out, fam + "_m.png"), 4)
    print("LIB", fam, height.shape)


def lib_emit(fn, res, plane):
    nd = Nodes("lib_" + fn.__name__)
    fn(nd)
    return bake_plane_emit(nd, res, plane)


def build_library(out):
    os.makedirs(out, exist_ok=True)
    reset()
    bpy.context.scene.cycles.samples = 1
    plane = lib_plane()
    bpy.ops.object.mode_set(mode="OBJECT")

    # Orange peel: overlapping 1-3 mm dimples (the tile spans 12 cm).
    def peel(nd):
        a = noise4(nd, 38.0, 2.0, 0.45)
        b = noise4(nd, 90.0, 1.0, 0.5, seed=3)
        nd.emit(a, b, nd.math("ADD", a, 0.0))
    px = lib_emit(peel, 512, plane)
    h = px[:, :, 0] * 0.8 + px[:, :, 1] * 0.2
    h = blur(h - h.mean(), 1)
    write_family(out, "paint", h, 9.0, np.ones_like(h), 0.5 + (h - h.mean()) * 0.6, np.zeros_like(h), 0.5 + h * 0.2)

    # Leather: pebble grain cells with soft creases (tile 10 cm).
    def leather(nd):
        cell = voronoi4(nd, 26.0, "DISTANCE_TO_EDGE", seed=1)
        fine = noise4(nd, 160.0, 3.0, 0.6, seed=2)
        broad = noise4(nd, 6.0, 2.0, 0.5, seed=4)
        nd.emit(cell, fine, broad)
    px = lib_emit(leather, 1024, plane)
    edge = np.clip(px[:, :, 0] * 5.0, 0, 1)
    h = np.sqrt(edge) * 0.8 + px[:, :, 1] * 0.2
    h = blur(h, 1)
    cav = 0.55 + 0.45 * np.sqrt(edge)
    write_family(out, "leather", h, 6.0, cav, 0.52 + (1 - edge) * 0.18 + (px[:, :, 2] - 0.5) * 0.12,
                 np.zeros_like(h), 0.45 + (px[:, :, 2] - 0.5) * 0.5 + (cav - 0.8) * 0.4)

    # Woven seat fabric: a twill (2/2) weave with fibre noise (tile 4 cm).
    res = 512
    v, u = np.mgrid[0:res, 0:res] / res
    threads = 24
    tu, tv = u * threads, v * threads
    over = ((np.floor(tu) + np.floor(tv)) % 4) < 2
    wu = np.sin(np.pi * (tu % 1.0)) ** 0.6
    wv = np.sin(np.pi * (tv % 1.0)) ** 0.6

    def fibres(nd):
        nd.emit(noise4(nd, 220.0, 2.0, 0.7, seed=5), noise4(nd, 12.0, 2.0, 0.5, seed=6), 0.0)
    px = lib_emit(fibres, res, plane)
    h = np.where(over, wv * 0.9 + 0.1, wu * 0.9 + 0.1) * 0.85 + px[:, :, 0] * 0.15
    write_family(out, "fabric", h, 5.0, 0.62 + h * 0.38, 0.86 + (px[:, :, 0] - 0.5) * 0.12, np.zeros_like(h),
                 0.5 + (h - 0.5) * 0.35 + (px[:, :, 1] - 0.5) * 0.25)

    # Moulded interior/exterior plastic: fine stipple "sand" grain (tile 6 cm).
    def stipple(nd):
        nd.emit(voronoi4(nd, 70.0, "F1", seed=7), noise4(nd, 30.0, 3.0, 0.6, seed=8), 0.0)
    px = lib_emit(stipple, 512, plane)
    h = 1.0 - np.clip(px[:, :, 0] * 1.6, 0, 1)
    h = blur(h, 1) * 0.8 + px[:, :, 1] * 0.2
    write_family(out, "plastic", h, 4.0, 0.8 + h * 0.2, 0.58 + (h - 0.5) * 0.2, np.zeros_like(h), 0.5 + (px[:, :, 1] - 0.5) * 0.15)

    # Carpet / headliner felt: dense fibre noise (tile 5 cm).
    def felt(nd):
        nd.emit(noise4(nd, 260.0, 4.0, 0.7, seed=9), noise4(nd, 40.0, 2.0, 0.5, seed=10), 0.0)
    px = lib_emit(felt, 512, plane)
    h = px[:, :, 0] * 0.7 + px[:, :, 1] * 0.3
    write_family(out, "carpet", h, 6.0, 0.7 + h * 0.3, 0.92 + (h - 0.5) * 0.08, np.zeros_like(h), 0.5 + (h - 0.5) * 0.5)

    # Rubber seals / mouldings: satin with fine scuffs (tile 8 cm).
    def scuff(nd):
        nd.emit(noise4(nd, 120.0, 3.0, 0.6, seed=11), noise4(nd, 10.0, 3.0, 0.6, seed=12), 0.0)
    px = lib_emit(scuff, 512, plane)
    h = px[:, :, 0]
    write_family(out, "rubber", h, 1.6, np.ones_like(h), 0.72 + (px[:, :, 1] - 0.5) * 0.3, np.zeros_like(h), 0.5 + (px[:, :, 1] - 0.5) * 0.3)

    # Brushed metal (trim strips, chrome scuffs): long streaks along U (tile 20 cm).
    res = 512
    rng = np.random.default_rng(13)
    streak = rng.random((res, 1)).repeat(res, 1)
    for _ in range(3):
        streak = (streak + np.roll(streak, 1, 0)) * 0.5
    def brush(nd):
        nd.emit(noise4(nd, 8.0, 3.0, 0.6, seed=14), 0.0, 0.0)
    px = lib_emit(brush, res, plane)
    h = streak * 0.8 + px[:, :, 0] * 0.2
    write_family(out, "brushed", h, 2.0, np.ones_like(h), 0.22 + (h - 0.5) * 0.16 + (px[:, :, 0] - 0.5) * 0.1, np.ones_like(h),
                 0.5 + (h - 0.5) * 0.2)

    # Lamp reflector facets + clear-lens prism lines (tile 6 cm).
    def facets(nd):
        nd.emit(voronoi4(nd, 14.0, "F1", "Color", seed=15, rand=0.35), voronoi4(nd, 14.0, "DISTANCE_TO_EDGE", seed=15, rand=0.35), 0.0)
    px = lib_emit(facets, 512, plane)
    # Faceted reflector: each cell tilted its own way (normal from cell colour).
    tilt = (px[:, :, :2] - 0.5) * 0.9
    edge = np.clip(px[:, :, 1] * 10.0, 0, 1)
    n = np.dstack([tilt[:, :, 0], tilt[:, :, 1], np.ones(tilt.shape[:2])])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    save_png(n * 0.5 + 0.5, os.path.join(out, "reflector_n.png"), 3)
    save_png(np.dstack([0.75 + edge * 0.25, 0.12 + (1 - edge) * 0.25, np.ones_like(edge), np.full_like(edge, 0.5)]),
             os.path.join(out, "reflector_m.png"))
    print("LIB reflector")
    v, u = np.mgrid[0:512, 0:512] / 512.0
    prism = (np.abs(((u * 12.0) % 1.0) - 0.5) * 2.0) * 0.7 + (np.abs(((v * 4.0) % 1.0) - 0.5) * 2.0) * 0.3
    write_family(out, "lens", prism, 7.0, np.ones_like(prism), np.full_like(prism, 0.05), np.zeros_like(prism), np.full_like(prism, 0.5))

    # Grille / intake mesh: hexagonal honeycomb (tile 10 cm).
    res = 512
    v, u = np.mgrid[0:res, 0:res] / res
    s = 8.0
    x, y = u * s, v * s * 2.0 / math.sqrt(3.0)
    hx = np.abs(((x + 0.5 * (np.floor(y) % 2)) % 1.0) - 0.5)
    hy = np.abs((y % 1.0) - 0.5)
    d = np.maximum(hx, hx * 0.5 + hy * 0.75)
    web = np.clip((d - 0.40) * 12.0, 0, 1)
    write_family(out, "grille", web, 6.0, 0.35 + web * 0.65, 0.5 - web * 0.12, np.zeros_like(web), 0.35 + web * 0.4)

    # Teak deck: planks along U with black caulking seams, grain (tile 1 m wide
    # = 8 planks; boats' decks).
    def grain(nd):
        nd.emit(noise4(nd, 3.0, 6.0, 0.7, seed=18), noise4(nd, 40.0, 3.0, 0.6, seed=19), 0.0)
    px = lib_emit(grain, 1024, plane)
    v, u = np.mgrid[0:1024, 0:1024] / 1024.0
    plank = np.floor(v * 8.0)
    seam = np.clip(np.abs(((v * 8.0) % 1.0) - 0.5) * 2.0 - 0.93, 0, 1) / 0.07
    rng = np.random.default_rng(23)
    tone = rng.random(8)[plank.astype(int) % 8]
    streak = np.sin((v * 8.0 % 1.0) * 40.0 + px[:, :, 0] * 12.0) * 0.5 + 0.5
    h = 1.0 - seam * 0.8 - streak * 0.05
    write_family(out, "teak", h, 5.0, 1.0 - seam * 0.85, 0.62 + streak * 0.1, np.zeros_like(h),
                 np.clip(0.35 + tone * 0.3 + streak * 0.15 + (px[:, :, 1] - 0.5) * 0.2 - seam * 0.4, 0, 1))

    # ---- Moulded wheel parts: geometry baked selected-to-active.
    build_tread(out)
    build_sidewall(out)
    build_rotor(out)
    build_alloy(out)


def tread_height(res):
    """One tread pitch tile (U around the tyre, V across it): four
    circumferential grooves, angled lateral grooves, sipes. Tiles in U."""
    v, u = np.mgrid[0:res, 0:res] / res
    across = v
    h = np.ones((res, res))
    # Circumferential grooves.
    for c in (0.22, 0.42, 0.58, 0.78):
        h = np.minimum(h, np.clip(np.abs(across - c) / 0.022 - 0.4, 0, 1))
    # Shoulder lateral grooves (angled, one per 1/4 tile), centre rib sipes.
    for k in range(4):
        t = (u * 4.0 - k)
        shoulder = (across < 0.22) | (across > 0.78)
        ang = t + (across - 0.5) * 1.3
        g = np.abs(((ang + 0.5) % 1.0) - 0.5)
        h = np.where(shoulder, np.minimum(h, np.clip(g / 0.05 - 0.5, 0, 1)), h)
    mid = (across > 0.22) & (across < 0.78)
    ang = u * 16.0 + (across - 0.5) * 3.0
    sipe = np.abs(((ang + 0.5) % 1.0) - 0.5)
    h = np.where(mid, np.minimum(h, 0.55 + 0.45 * np.clip(sipe / 0.03, 0, 1)), h)
    # Shoulder roll-off at the edges.
    h *= np.clip(np.minimum(across, 1 - across) / 0.06, 0, 1) * 0.3 + 0.7
    return h


def build_tread(out):
    """Tread pitch as real relief: a displaced grid (the high mesh) baked to a
    flat plane's normal (selected to active) plus the height as cavity."""
    res = 512
    h = tread_height(res)
    img = bpy.data.images.new("tread_h", res, res, float_buffer=True)
    img.pixels.foreach_set(np.dstack([h, h, h, np.ones_like(h)]).astype(np.float32).ravel())
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=400, y_subdivisions=400, size=1.0, location=(0.5, 0.5, 0))
    hi = bpy.context.object
    tex = bpy.data.textures.new("tread_tex", "IMAGE")
    tex.image = img
    tex.extension = "REPEAT"
    mod = hi.modifiers.new("disp", "DISPLACE")
    mod.texture = tex
    mod.texture_coords = "UV"
    mod.strength = 0.03
    mod.mid_level = 1.0
    bpy.ops.object.modifier_apply(modifier="disp")
    bpy.ops.object.shade_smooth()
    lo = lib_plane()
    n = bake_normal_to(lo, [hi], res, cage=0.05)
    cav = 0.35 + 0.65 * h
    save_png(n, os.path.join(out, "tread_n.png"), 3)
    save_png(np.dstack([cav, 0.88 - (1 - h) * 0.06, np.zeros_like(h), 0.48 + h * 0.06]), os.path.join(out, "tread_m.png"))
    bpy.data.objects.remove(hi)
    bpy.data.objects.remove(lo)
    print("LIB tread (baked)")


def bake_normal_to(lo, highs, res, cage=0.05):
    sc = bpy.context.scene
    sc.cycles.samples = 4
    img = new_image("n_" + lo.name, res, float_buf=True)
    mat = bpy.data.materials.new("bake_n_" + lo.name)
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    mat.node_tree.nodes.active = node
    lo.data.materials.clear()
    lo.data.materials.append(mat)
    for hobj in highs:
        if not hobj.data.materials:
            hobj.data.materials.append(bpy.data.materials.new("hi"))
    bpy.ops.object.select_all(action="DESELECT")
    for hobj in highs:
        hobj.select_set(True)
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.bake(type="NORMAL", use_selected_to_active=True, cage_extrusion=cage, max_ray_distance=cage * 2.0,
                        normal_space="TANGENT", margin=4, use_clear=True)
    px = pixels(img)[:, :, :3]
    return px


def text_ring(body, radius, size, angle_mid, inward=False, extrude=0.006, name="txt"):
    """A line of raised lettering on a circle of `radius` centred on angle_mid
    (radians, 0 = +X, counter-clockwise), letters upright to the rim."""
    bpy.ops.object.text_add(location=(0, 0, 0))
    t = bpy.context.object
    t.name = name
    t.data.body = body
    t.data.size = size
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    t.data.extrude = extrude
    t.data.space_character = 1.15
    bpy.ops.object.convert(target="MESH")
    me = t.data
    # Bend the flat line around the circle: x -> arc length, y -> radius.
    for vtx in me.vertices:
        x, y, z = vtx.co
        if inward:
            # Lower arc: read left to right, letter tops toward the hub.
            a = angle_mid + x / radius
            r = radius - y
        else:
            a = angle_mid - x / radius
            r = radius + y
        vtx.co = Vector((0.5 + r * math.cos(a) * 0.5, 0.5 + r * math.sin(a) * 0.5, z + extrude))
    return t


def build_sidewall(out):
    """Sidewall disc (planar UV, radius 1 = UV circle): rim protector bands,
    radial ribbing and two lines of moulded lettering, built as geometry and
    baked selected-to-active onto a flat plane. Brand names are the game's
    own (WorldState) - no real tyre makers."""
    res = 1024
    objs = []
    # Backing disc (the sidewall surface), a ring band and the bead ribbing.
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.5, 0.5, 0))
    back = bpy.context.object
    objs.append(back)
    for r_in, r_out, z in ((0.893 - 0.006, 0.893 + 0.006, 0.004), (0.914 - 0.005, 0.914 + 0.005, 0.004)):
        bpy.ops.mesh.primitive_circle_add(vertices=256, radius=r_out * 0.5, fill_type="NOTHING", location=(0.5, 0.5, 0))
        ring = bpy.context.object
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.extrude_region_shrink_fatten(TRANSFORM_OT_shrink_fatten={"value": (r_out - r_in) * 0.5})
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.extrude_region_move(TRANSFORM_OT_translate={"value": (0, 0, z)})
        bpy.ops.object.mode_set(mode="OBJECT")
        objs.append(ring)
    # Fine radial ribs near the bead (r 0.70 .. 0.76).
    bm = bmesh.new()
    for k in range(180):
        a = k / 180.0 * math.tau
        w = 0.0035
        for r0, r1 in ((0.70, 0.76),):
            c, s = math.cos(a), math.sin(a)
            px, py = -s * w, c * w
            vs = [bm.verts.new((0.5 + (r * c + dx) * 0.5, 0.5 + (r * s + dy) * 0.5, zz))
                  for r, dx, dy, zz in ((r0, px, py, 0), (r1, px, py, 0), (r1, -px, -py, 0), (r0, -px, -py, 0),
                                        (r0, px, py, .003), (r1, px, py, .003), (r1, -px, -py, .003), (r0, -px, -py, .003))]
            for f in ((0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
                bm.faces.new([vs[i] for i in f])
    me = bpy.data.meshes.new("ribs")
    bm.to_mesh(me)
    ribs = bpy.data.objects.new("ribs", me)
    bpy.context.collection.objects.link(ribs)
    objs.append(ribs)
    # Lettering: big name on top, size/spec line below, small DOT code.
    objs.append(text_ring("WORLDSTATE", 0.818, 0.066, math.pi * 0.5, name="brand"))
    objs.append(text_ring("CITYGRIP SPORT 4", 0.818, 0.040, math.pi * 1.5, inward=True, name="model"))
    objs.append(text_ring("225/45 R18 94W", 0.818, 0.034, math.pi * 0.04, name="size"))
    objs.append(text_ring("TUBELESS RADIAL", 0.818, 0.026, math.pi * 0.96, name="spec"))
    objs.append(text_ring("DOT 4826  M+S", 0.818, 0.022, math.pi * 1.16, inward=True, name="dot"))
    # Height mask (emit bake of z) and normal bake.
    lo = lib_plane()
    hm = bpy.data.materials.new("hi_z")
    hm.use_nodes = True
    nt = hm.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 100.0
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    nt.links.new(sep.outputs[2], mul.inputs[0])
    nt.links.new(mul.outputs[0], em.inputs[0])
    nt.links.new(em.outputs[0], o.inputs[0])
    for ob in objs:
        ob.data.materials.clear()
        ob.data.materials.append(hm)
    n = bake_normal_to(lo, objs, res, cage=0.03)
    # Emission (height) bake selected-to-active.
    img = new_image("sw_h", res, float_buf=True)
    m2 = lo.data.materials[0]
    m2.node_tree.nodes.active.image = img
    bpy.ops.object.bake(type="EMIT", use_selected_to_active=True, cage_extrusion=0.03, max_ray_distance=0.06, margin=2, use_clear=True)
    h = np.clip(pixels(img)[:, :, 0] / 1.2, 0, 1)
    v, u = np.mgrid[0:res, 0:res] / res
    rad = np.hypot(u - 0.5, v - 0.5) * 2.0
    letters = np.clip(h * 2.0, 0, 1)
    # The flat letter tops bake to a plain normal: the relief reads through
    # the baked height's slopes instead (letters' bevelled sides).
    n = height_to_normal(blur(h, 1, wrap=False), 14.0, wrap=False)
    save_png(n, os.path.join(out, "sidewall_n.png"), 3)
    # Lettering and bands: satin (lower roughness), a touch lighter.
    save_png(np.dstack([0.85 + letters * 0.15, 0.86 - letters * 0.22, np.zeros_like(h), 0.46 + letters * 0.2 + (rad > 0.95) * 0.04]),
             os.path.join(out, "sidewall_m.png"))
    for ob in objs + [lo]:
        bpy.data.objects.remove(ob)
    print("LIB sidewall (baked)")


def build_rotor(out):
    """Brake disc face (planar UV, radius 1 = UV circle, rotor in 0.3..0.58
    as the wheel meshes model it): drilled holes, curved slots and lathe
    rings as baked relief; the hat stays dark cast iron."""
    res = 512
    v, u = np.mgrid[0:res, 0:res] / res
    x, y = (u - 0.5) * 2.0, (v - 0.5) * 2.0
    r = np.hypot(x, y)
    a = np.arctan2(y, x)
    h = np.ones((res, res)) * 0.6
    sweep = (r > 0.32) & (r < 0.57)
    h = np.where(sweep, 0.6 + 0.02 * np.sin(r * 900.0) + 0.03 * np.sin(r * 150.0), h)
    # Drilled holes on three radii, staggered.
    holes = np.zeros_like(h)
    for ring, n_h, off in ((0.38, 18, 0.0), (0.45, 18, 0.5), (0.52, 18, 0.0)):
        for k in range(n_h):
            aa = (k + off) / n_h * math.tau + ring * 3.0
            cx, cy = ring * math.cos(aa), ring * math.sin(aa)
            d = np.hypot(x - cx, y - cy)
            holes = np.maximum(holes, np.clip(1.0 - (d - 0.013) / 0.006, 0, 1))
    # Curved slots between the holes.
    slot_ang = (a * 6.0 / math.pi + r * 9.0) % 2.0
    slots = np.clip(1.0 - np.abs(slot_ang - 1.0) / 0.035, 0, 1) * ((r > 0.35) & (r < 0.55))
    h = h - holes * 0.5 - slots * 0.15
    n = height_to_normal(h, 22.0, wrap=False)
    bright = sweep & (holes < 0.5)
    save_png(n, os.path.join(out, "rotor_n.png"), 3)
    save_png(np.dstack([1.0 - holes * 0.8 - slots * 0.4, np.where(bright, 0.30 + 0.06 * np.sin(r * 400.0), 0.62),
                        np.where(bright, 1.0, 0.75), np.where(bright, 0.75, 0.30)]), os.path.join(out, "rotor_m.png"))
    print("LIB rotor")


def build_alloy(out):
    """Alloy face (planar UV around the hub): diamond-cut lathe rings for the
    machined face, cast texture elsewhere (roughness), drilled lug nuts."""
    res = 512
    v, u = np.mgrid[0:res, 0:res] / res
    x, y = (u - 0.5) * 2.0, (v - 0.5) * 2.0
    r = np.hypot(x, y)
    a = np.arctan2(y, x)
    # (A few lathe rings per texel band at 512 px: finer aliases into moire.)
    lathe = 0.5 + 0.5 * np.sin(r * 260.0)
    rng = np.random.default_rng(21)
    cast = blur(rng.random((res, res)), 6, wrap=False)
    cast = (cast - cast.min()) / max(cast.max() - cast.min(), 1e-6)
    h = lathe * 0.25 + cast * 0.2
    # Five lug nuts on a 0.2 radius PCD + a centre cap ring.
    for k in range(5):
        aa = k / 5.0 * math.tau + math.pi * 0.5
        d = np.hypot(x - 0.2 * math.cos(aa), y - 0.2 * math.sin(aa))
        h += np.clip(1.0 - (d - 0.03) / 0.008, 0, 1) * 0.5
    h += np.clip(1.0 - np.abs(r - 0.13) / 0.006, 0, 1) * 0.3
    n = height_to_normal(h, 10.0, wrap=False)
    save_png(n, os.path.join(out, "alloy_n.png"), 3)
    save_png(np.dstack([0.85 + cast * 0.15, 0.16 + lathe * 0.08 + (cast - 0.5) * 0.08, np.ones_like(h), 0.5 + (lathe - 0.5) * 0.12]),
             os.path.join(out, "alloy_m.png"))
    print("LIB alloy")


# --------------------------------------------------------------------------- vehicles

def mesh_objects():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def import_glb(path):
    bpy.ops.import_scene.gltf(filepath=path, merge_vertices=False, import_shading="NORMALS")
    return mesh_objects()


def ensure_layers(o):
    uvs = o.data.uv_layers
    while len(uvs) < 2:
        uvs.new()
    uvs[0].name = "Tile"
    uvs[1].name = "Bake"
    return uvs


def glassy_face_mask(o):
    names = [base_name(m) for m in o.data.materials]
    flags = np.array([n in GLASSY for n in names] or [False], dtype=bool)
    mi = np.empty(len(o.data.polygons), dtype=np.int32)
    o.data.polygons.foreach_get("material_index", mi)
    return flags[np.clip(mi, 0, len(flags) - 1)] if len(names) else np.zeros(len(mi), bool)


def unwrap_smart(objs):
    """Smart UV Project on every non-glass face of all objects into the Bake
    layer (packed atlas), then Tile = the same islands at 1 UV = 1 m."""
    for o in objs:
        ensure_layers(o)
        o.data.uv_layers.active_index = 1
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    for o in objs:
        bm = bmesh.from_edit_mesh(o.data)
        mask = glassy_face_mask(o)
        for f in bm.faces:
            f.select = not bool(mask[f.index]) if f.index < len(mask) else True
        bmesh.update_edit_mesh(o.data)
    # (A scaled margin per island starves a fleet body of thousands of small
    # islands: 12% coverage. A fixed fraction keeps ~55%.)
    bpy.ops.uv.smart_project(angle_limit=math.radians(55.0), margin_method="FRACTION", island_margin=0.002,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=0.002, shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")
    # Metric scale for Tile; fit Bake into 0..PACK_FIT; glass -> white corner.
    area3, areauv = 0.0, 0.0
    for o in objs:
        me = o.data
        mask = glassy_face_mask(o)
        uv = np.empty(len(me.loops) * 2, dtype=np.float32)
        me.uv_layers[1].data.foreach_get("uv", uv)
        uv = uv.reshape(-1, 2)
        for p in me.polygons:
            if mask[p.index]:
                continue
            area3 += p.area
            ls = list(p.loop_indices)
            a = uv[ls[0]]
            for i in range(1, len(ls) - 1):
                b, c = uv[ls[i]], uv[ls[i + 1]]
                areauv += abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])) * 0.5
    metres = math.sqrt(area3 / max(areauv, 1e-9))
    for o in objs:
        me = o.data
        mask = glassy_face_mask(o)
        uv = np.empty(len(me.loops) * 2, dtype=np.float32)
        me.uv_layers[1].data.foreach_get("uv", uv)
        uv = uv.reshape(-1, 2)
        loop_glass = np.zeros(len(me.loops), dtype=bool)
        for p in me.polygons:
            if mask[p.index]:
                loop_glass[list(p.loop_indices)] = True
        tile = uv * metres
        bake = uv * PACK_FIT
        bake[loop_glass] = WHITE_UV
        tile[loop_glass] = 0.0
        me.uv_layers[0].data.foreach_set("uv", tile.ravel())
        me.uv_layers[1].data.foreach_set("uv", bake.ravel())
    print(f"UNWRAP {len(objs)} objects, {area3:.2f} m2, atlas span {metres:.2f} m")
    return metres


def unwrap_wheel(objs):
    """Wheel meshes: radius 1, axle along X (glTF and Blender alike). Tread
    faces (normals radial) get a cylindrical unwrap: U = turns * 8 (eight
    tread pitches round the tyre), V = across the 0.44 width. Faces looking
    along the axle get a planar unwrap of Y/Z: the UV circle is the wheel's
    radius, matching the sidewall/alloy/rotor maps. Bake = smart atlas."""
    unwrap_smart(objs)  # the Bake atlas
    for o in objs:
        me = o.data
        tile = np.zeros((len(me.loops), 2), dtype=np.float32)
        co = np.empty(len(me.vertices) * 3, dtype=np.float32)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        for p in me.polygons:
            ls = list(p.loop_indices)
            vs = [me.loops[i].vertex_index for i in ls]
            n = p.normal
            if abs(n.x) > 0.55:
                for li, vi in zip(ls, vs):
                    y, z = co[vi][1], co[vi][2]
                    # Mirror on the inner face so lettering reads from outside.
                    s = 1.0 if n.x > 0 else -1.0
                    tile[li] = (0.5 - s * y * 0.5, 0.5 + z * 0.5)
            else:
                us = [math.atan2(co[vi][2], co[vi][1]) / math.tau for vi in vs]
                ref = us[0]
                us = [u + round(ref - u) for u in us]
                for li, vi, u in zip(ls, vs, us):
                    tile[li] = (u * 8.0, co[vi][0] / 0.44 + 0.5)
        me.uv_layers[0].data.foreach_set("uv", tile.ravel())


def bake_vehicle(objs, res, out_png, ground):
    """Bake AO/edge/cavity on a copy of the meshes with glass removed."""
    sc = bpy.context.scene
    sc.cycles.samples = int(os.environ.get("BAKE_SAMPLES", "24"))
    copies = []
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        c = o.copy()
        c.data = o.data.copy()
        bpy.context.collection.objects.link(c)
        copies.append(c)
    for o in objs:
        o.hide_render = True
    for c in copies:
        bm = bmesh.new()
        bm.from_mesh(c.data)
        names = [base_name(m) for m in c.data.materials]
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index < len(names) and names[f.material_index] in GLASSY],
                         context="FACES")
        bm.to_mesh(c.data)
        bm.free()
        c.data.uv_layers.active_index = 1
    # (A node that is all glass / rotor blur has nothing left to bake.)
    for c in [c for c in copies if len(c.data.polygons) == 0]:
        copies.remove(c)
        bpy.data.objects.remove(c)
    plane = None
    if ground:
        lo = min((c.matrix_world @ Vector(b)).z for c in copies for b in c.bound_box)
        bpy.ops.mesh.primitive_plane_add(size=40.0, location=(0, 0, lo - 0.005))
        plane = bpy.context.object
    img = new_image("bake", res, float_buf=True)
    nd = Nodes("ws_bake")
    ao_far = nd.node("ShaderNodeAmbientOcclusion", samples=16, in_Distance=0.55)
    ao_near = nd.node("ShaderNodeAmbientOcclusion", samples=8, in_Distance=0.04)
    bev = nd.node("ShaderNodeBevel", samples=8, in_Radius=0.006)
    geo = nd.node("ShaderNodeNewGeometry")
    dot = nd.node("ShaderNodeVectorMath", operation="DOT_PRODUCT")
    nd.link(bev.outputs[0], dot.inputs[0])
    nd.link(geo.outputs["Normal"], dot.inputs[1])
    edge = nd.math("MULTIPLY", nd.math("SUBTRACT", 1.0, dot.outputs["Value"]), 14.0, clamp=True)
    convex = nd.math("GREATER_THAN", geo.outputs["Pointiness"], 0.505)
    nd.emit(ao_far.outputs["AO"], nd.math("MULTIPLY", edge, convex), ao_near.outputs["AO"])
    nd.image_target(img)
    bpy.ops.object.select_all(action="DESELECT")
    for c in copies:
        c.data.materials.clear()
        c.data.materials.append(nd.mat)
        c.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.bake(type="EMIT", margin=6, use_clear=True)
    px = pixels(img)
    ao, edge_m, cav = px[:, :, 0], px[:, :, 1], px[:, :, 2]
    ao = np.clip(ao, 0, 1) * (0.35 + 0.65 * np.clip(cav, 0, 1))
    # Unbaked texels (outside every island after the margin) stay white;
    # the reserved top-right strip too.
    h, w = ao.shape
    cut = int(PACK_FIT * w) + 1
    rgb = np.dstack([ao, edge_m, cav])
    rgb[:, cut:] = (1.0, 0.0, 1.0)
    rgb[cut:, :] = (1.0, 0.0, 1.0)
    # Soften the noise left by 24 samples (islands keep their margins).
    rgb[:, :, 0] = blur(rgb[:, :, 0], 1, wrap=False)
    rgb[:, :, 2] = blur(rgb[:, :, 2], 1, wrap=False)
    save_png(rgb, out_png, 3)
    for c in copies:
        bpy.data.objects.remove(c)
    if plane:
        bpy.data.objects.remove(plane)
    for o in objs:
        o.hide_render = False
    print(f"BAKE {out_png} {res}px")


def transfer_uvs(objs, ref_path):
    """Entry pieces (cabin opening + doors cut from a body) take the body's
    two UV layers from the nearest body face, so they sample the body's
    own bake and tile at the same density: no change of look as the doors
    open."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=ref_path, merge_vertices=False, import_shading="NORMALS")
    refs = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    src = refs[0]
    if len(refs) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for r in refs:
            r.select_set(True)
        bpy.context.view_layer.objects.active = src
        bpy.ops.object.join()
    ensure_layers(src)   # (glTF keeps no layer names: UVMap, UVMap.001)
    # Source as triangles with both UV layers, in a BVH. (The Data Transfer
    # modifier stalled for 10+ minutes on these 50k-triangle cuts.)
    from mathutils.bvhtree import BVHTree
    from mathutils.geometry import barycentric_transform
    bm = bmesh.new()
    bm.from_mesh(src.data)
    bm.transform(src.matrix_world)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.faces.ensure_lookup_table()
    lay = [bm.loops.layers.uv[i] for i in range(2)]
    tree = BVHTree.FromBMesh(bm)
    for o in objs:
        ensure_layers(o)
        me = o.data
        mw = o.matrix_world
        co = [mw @ v.co for v in me.vertices]
        out = [np.zeros((len(me.loops), 2), dtype=np.float32) for _ in range(2)]
        for p in me.polygons:
            hit = tree.find_nearest(mw @ p.center)
            if hit[2] is None:
                continue
            f = bm.faces[hit[2]]
            tri = [l.vert.co for l in f.loops]
            for li in p.loop_indices:
                q = co[me.loops[li].vertex_index]
                for k in range(2):
                    uvs = [l[lay[k]].uv.to_3d() for l in f.loops]
                    w = barycentric_transform(q, tri[0], tri[1], tri[2], uvs[0], uvs[1], uvs[2])
                    out[k][li] = (w.x, w.y)
        me.uv_layers[0].data.foreach_set("uv", out[0].ravel())
        me.uv_layers[1].data.foreach_set("uv", np.clip(out[1], 0.0, 1.0).ravel())
    bm.free()
    for o in objs:
        # Glass stays on the white texel.
        me = o.data
        mask = glassy_face_mask(o)
        uv = np.empty(len(me.loops) * 2, dtype=np.float32)
        me.uv_layers[1].data.foreach_get("uv", uv)
        uv = uv.reshape(-1, 2)
        for p in me.polygons:
            if mask[p.index]:
                uv[list(p.loop_indices)] = WHITE_UV
        me.uv_layers[1].data.foreach_set("uv", uv.ravel())
    for r in [o for o in bpy.data.objects if o not in before]:
        bpy.data.objects.remove(r)


def export_glb(path):
    for o in bpy.data.objects:
        o.select_set(o.type == "MESH" or o.type == "EMPTY")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False, export_apply=False,
                              export_yup=True, export_materials="EXPORT", export_texcoords=True, export_normals=True,
                              export_tangents=False, export_vertex_color="NONE", export_image_format="NONE",
                              export_extras=True)


def do_vehicle(inp, out, png, res, kind, ref=None):
    reset()
    objs = import_glb(inp)
    if not objs:
        print("NO MESHES", inp)
        return
    if kind == "entry":
        transfer_uvs(objs, ref)
    elif kind == "wheel":
        unwrap_wheel(objs)
    else:
        unwrap_smart(objs)
    if png != "-" and kind != "entry":
        bake_vehicle(objs, res, png, ground=kind == "body")
    export_glb(out)
    print("DONE", out)


if ARGS[0] == "library":
    build_library(ARGS[1])
elif ARGS[0] == "vehicle":
    do_vehicle(ARGS[1], ARGS[2], ARGS[3], int(ARGS[4]), ARGS[5], ARGS[6] if len(ARGS) > 6 else None)
