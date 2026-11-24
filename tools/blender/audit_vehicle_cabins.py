"""Measure exported cabin clearance along the driver's head travel in Blender.

Run with blender -b -t 2 --python tools/blender/audit_vehicle_cabins.py.
Use -- --write to update only the derived seating measurements.
"""
import json
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
PROFILES = ROOT / "config/empire/vehicle_entries.json"
VEHICLES = ROOT / "assets/vehicles"


def audit(body, profile):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(VEHICLES / f"{body}.glb"))
    mesh = bmesh.new()
    materials = set()
    for item in bpy.context.scene.objects:
        if item.type != "MESH":
            continue
        materials.update(slot.name.split(".")[0] for slot in item.material_slots)
        vertices = [mesh.verts.new(item.matrix_world @ v.co) for v in item.data.vertices]
        for poly in item.data.polygons:
            mat = item.material_slots[poly.material_index].name.split(".")[0]
            if mat in {"paint", "paint2", "glass_clear", "glass", "carbon"}:
                mesh.faces.new([vertices[i] for i in poly.vertices])
    tree = BVHTree.FromBMesh(mesh)
    seat_z, pelvis_y = profile["seat"]
    seat_x = profile["seat_x"]
    heights = []
    for head_offset in (0.0, 0.12, 0.24, 0.36, 0.48):
        at = Vector((seat_x, -seat_z - head_offset, 4.0))
        # Sweep the head width and depth. Exterior skin leaves room for
        # the headliner, hair and motion in the runtime pose.
        samples = []
        for lateral in (-0.08, 0.0, 0.08):
            for fore in (-0.07, 0.0, 0.07):
                hit, _, _, _ = tree.ray_cast(at + Vector((lateral, fore, 0)), Vector((0, 0, -1)))
                if hit is not None:
                    samples.append(hit.z)
        heights.append(round(min(samples), 4) if samples else 0.0)
    mesh.free()
    print(body, "hip", pelvis_y, "roof", heights, "glass", "glass_clear" in materials, flush=True)
    return heights


def main():
    data = json.loads(PROFILES.read_text())
    for body, profile in data.items():
        if (VEHICLES / f"{body}.glb").exists():
            profile["roof_samples"] = audit(body, profile)
    if "--write" in sys.argv:
        PROFILES.write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    main()
