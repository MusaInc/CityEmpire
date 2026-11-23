"""Extract front door panels from WorldState's authored road vehicle meshes.

Run with Blender in background mode. Closed vehicles keep their original
mesh. The three entry meshes are only loaded for the boarding sequence.
"""
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/vehicles"
OUTPUT = ROOT / "assets/vehicle_entries"
MODELS = ROOT / "config/empire/vehicles.json"
OUTPUT.mkdir(exist_ok=True)


def _door_outline(body, dims):
    length, roof, ride = (dims[k] for k in ("L", "roof", "ride"))
    wb = dims["wb"]
    if body == "kestrel":
        return [(-0.177, 0.35), (0.71, 0.35), (0.86, 0.80),
                (0.59, 1.15), (0.16, roof - 0.043), (-0.177, roof - 0.043)]
    if body in {"civ_van", "civ_box", "mammoth"}:
        rear = wb * 0.5 - dims["wheel_r"] - 0.79
        front = min(length * 0.34, wb * 0.5 + 0.02)
        top = min(roof - 0.085, 1.94)
        return [(rear, ride + 0.18), (front - 0.28, ride + 0.18),
                (front, top * 0.67), (front - 0.32, top), (rear, top)]
    rear = -length * (0.12 if body in {"halcyon", "stiletto", "brute", "vanta"} else 0.035)
    front = wb * 0.5 - 0.28
    top = roof - 0.065
    return [(rear, ride + 0.18), (front - 0.26, ride + 0.18), (front, top * 0.67),
            (front - 0.35, top * 0.96), (rear, top)]


def _mesh(name, source, classification):
    mesh = source.copy()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if classification(f) is False], context="FACES")
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate(clean_customdata=False)
    target = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(target)
    return target


def build(body, dims):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE / f"{body}.glb"))
    source = next(obj for obj in bpy.context.selected_objects if obj.type == "MESH")
    bpy.context.view_layer.objects.active = source
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    outline = _door_outline(body, dims)
    side_x = dims["W"] * 0.365
    planes = []
    for (y, z), (ny, nz) in zip(outline, outline[1:] + outline[:1]):
        planes.append((Vector((0, y, z)), Vector((0, z - nz, ny - y)).normalized()))
    bm = bmesh.new()
    bm.from_mesh(source.data)
    for location, inward in planes + [
            (Vector((side_x, 0, 0)), Vector((1, 0, 0))),
            (Vector((-side_x, 0, 0)), Vector((-1, 0, 0)))]:
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                              dist=0.00008, plane_co=location, plane_no=inward)
    clipped = source.data.copy()
    bm.to_mesh(clipped)
    bm.free()

    def panel(face):
        at = face.calc_center_median()
        if abs(at.x) < side_x or any((at - co).dot(n) < -0.00015 for co, n in planes):
            return 0
        return 1 if at.x > 0 else -1

    parts = [_mesh(name, clipped, lambda face: panel(face) == side) for name, side in [
        ("CabinOpening", 0), ("DoorLeft", -1), ("DoorRight", 1)]]
    if min(len(door.data.polygons) for door in parts[1:]) < 40:
        raise ValueError(f"Missing door faces for {body}")
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / f"{body}.glb"), use_selection=True, export_format="GLB")
    # Godot axes. The hinge sits near the leading edge and below the window.
    front = max(y for y, _ in outline)
    rear = min(y for y, _ in outline)
    return {"hinge": [-front + 0.11, outline[0][1] + 0.47],
            "handle": [-rear - 0.17, outline[0][1] + 0.55],
            "seat": [-0.5 * (front + rear) + 0.12, outline[0][1] + 0.24]}


dims = json.loads((SOURCE / "bodies.json").read_text())
models = json.loads(MODELS.read_text())["models"]
bodies = sorted({m.get("art", m.get("body")) for m in models.values() if m.get("class", "car") == "car"})
profiles = {body: build(body, dims[body]) for body in bodies if body in dims}
(ROOT / "config/empire/vehicle_entries.json").write_text(json.dumps(profiles, indent=2) + "\n")
