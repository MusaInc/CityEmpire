"""Build the shared WorldState interior shelving and display stock.

Run with Blender in background mode. The modules use metres and export
with the cabinet's open face pointing along +Z in Godot.
"""
from pathlib import Path

import bpy


def material(name, rgb, roughness, metallic=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = mat.diffuse_color
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return mat


def block(size, at, mat, bevel):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    mod = obj.modifiers.new("Machined edges", "BEVEL")
    mod.width = bevel
    mod.segments = 1
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def vessel(at, bottom, top, height, mat):
    bpy.ops.mesh.primitive_cone_add(vertices=14, radius1=bottom, radius2=top, depth=height, location=at)
    obj = bpy.context.object
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = len(poly.vertices) == 4
    return obj


def oval(at, dimensions, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, location=at)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def limb(start, end, bottom, top, mat):
    from mathutils import Vector

    a, b = Vector(start), Vector(end)
    obj = vessel((a + b) * 0.5, bottom, top, (b - a).length, mat)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (b - a).to_track_quat("Z", "Y")
    return obj


def module(name, parts):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
wood = material("Display oak", (0.31, 0.20, 0.12), 0.49)
back = material("Recessed backing", (0.10, 0.095, 0.087), 0.83)
edge = material("Satin metal", (0.24, 0.23, 0.21), 0.4, 0.6)
paper = material("Paper pack", (0.70, 0.70, 0.70), 0.78)
label = material("Printed label", (0.93, 0.91, 0.87), 0.71)
cloth = material("Folded fabric", (0.64, 0.64, 0.64), 0.92)

parts = [block((1.30, 0.046, 2.7), (0, 0.19, 1.35), back, 0.006),
         block((1.30, 0.40, 0.13), (0, 0, 0.065), wood, 0.008)]
for x in (-0.632, 0.632):
    parts.append(block((0.036, 0.42, 2.7), (x, 0, 1.35), wood, 0.006))
for y in (0.44, 0.92, 1.40, 1.88, 2.36, 2.68):
    parts.append(block((1.26, 0.40, 0.029), (0, 0, y), wood, 0.006))
    parts.append(block((1.25, 0.012, 0.016), (0, -0.203, y - 0.004), edge, 0.002))
module("WallBay", parts)
module("Carton", [
    block((0.144, 0.10, 0.235), (0, 0, 0.118), paper, 0.004),
    block((0.115, 0.004, 0.048), (0, -0.050, 0.156), label, 0.002),
    block((0.082, 0.004, 0.018), (0, -0.050, 0.082), edge, 0.001)])
module("Book", [
    block((0.064, 0.15, 0.242), (0, 0, 0.122), label, 0.002),
    block((0.070, 0.014, 0.247), (0, -0.075, 0.124), paper, 0.004),
    block((0.045, 0.003, 0.025), (0, -0.082, 0.178), edge, 0.001)])
module("Fold", [
    block((0.245, 0.167, 0.048), (0, 0, 0.026), cloth, 0.012),
    block((0.228, 0.153, 0.017), (0, -0.006, 0.052), cloth, 0.006)])

ceramic = material("Glazed ceramic", (0.76, 0.74, 0.71), 0.34)
module("Vase", [
    vessel((0, 0, 0.058), 0.070, 0.103, 0.116, ceramic),
    vessel((0, 0, 0.152), 0.103, 0.043, 0.072, ceramic),
    vessel((0, 0, 0.216), 0.043, 0.050, 0.056, ceramic)])

porcelain = material("Mannequin ceramic", (0.74, 0.71, 0.66), 0.47)
charcoal = material("Slim trousers", (0.064, 0.077, 0.092), 0.89)
knit = material("Knit top", (0.36, 0.21, 0.15), 0.93)
sole = material("Matte leather", (0.042, 0.037, 0.032), 0.57)
figure = [
    vessel((0, 0, 0.019), 0.239, 0.232, 0.038, edge),
    oval((0, 0, 1.735), (0.165, 0.193, 0.245), porcelain),
    vessel((0, 0, 1.585), 0.061, 0.049, 0.15, porcelain),
    oval((0, 0, 0.982), (0.339, 0.217, 0.223), charcoal),
    oval((0, 0, 1.255), (0.348, 0.216, 0.578), knit),
    oval((0, 0, 1.442), (0.411, 0.211, 0.208), knit),
]
for side in (-1, 1):
    x = side * 0.095
    stride = side * 0.036
    figure += [
        limb((x, stride, 0.162), (x, stride * 0.35, 0.53), 0.046, 0.062, charcoal),
        limb((x, stride * 0.35, 0.50), (x, 0, 0.995), 0.061, 0.081, charcoal),
        oval((x, stride - 0.037, 0.083), (0.112, 0.242, 0.092), sole),
        limb((side * 0.225, -0.021, 1.148), (side * 0.168, 0, 1.491), 0.045, 0.076, knit),
        limb((side * 0.228, -0.075, 1.013), (side * 0.225, -0.021, 1.181), 0.029, 0.048, knit),
        oval((side * 0.229, -0.08, 0.963), (0.065, 0.047, 0.138), porcelain),
    ]
module("Mannequin", figure)

target = Path(__file__).resolve().parents[2] / "assets/models/interior_wall_kit.glb"
bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", export_cameras=False, export_lights=False)
