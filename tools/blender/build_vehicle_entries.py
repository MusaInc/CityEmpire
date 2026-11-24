"""Extract front door panels and rich entry/driving metadata for all drivable road vehicles.

Run with Blender in background mode:
  blender -b --factory-startup --python-exit-code 1 --python tools/blender/build_vehicle_entries.py

Closed vehicles keep their original mesh for driving. The three entry meshes
(CabinOpening, DoorLeft, DoorRight) are loaded during boarding/exit.
Bodies without a modeled cabin receive a clean dark interior tub (floor, seats,
dashboard, steering wheel) inside CabinOpening so opening a door never reveals
an empty hollow shell.
"""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/vehicles"
OUTPUT = ROOT / "assets/vehicle_entries"
MODELS = ROOT / "config/empire/vehicles.json"
OUTPUT.mkdir(exist_ok=True)

ARCHETYPES = {
    "kestrel": "hatch",
    "scout": "hatch",
    "marlin": "saloon",
    "brute": "sports",
    "vanta": "sports",
    "halcyon": "hypercar",
    "stiletto": "hypercar",
    "goliath": "suv",
    "warden": "suv",
    "civ_van": "van",
    "courier_van": "van",
    "civ_box": "truck",
    "mammoth": "truck",
}

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = next((set(arg.split("=", 1)[1].split(",")) for arg in ARGS if arg.startswith("--only=")), set())
CLEAR_GLASS_BODIES = {"kestrel", "stiletto", "halcyon", "courier_van"}


def _door_outline(body, dims):
    length, roof, ride = (dims[k] for k in ("L", "roof", "ride"))
    wb = dims["wb"]
    if body == "kestrel":
        return [(-0.177, 0.35), (0.71, 0.35), (0.86, 0.80),
                (0.59, 1.15), (0.16, roof - 0.043), (-0.177, roof - 0.043)]
    if body in {"civ_van", "courier_van", "civ_box", "mammoth"}:
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


def _add_box(bm, center, size, mat_idx):
    sx, sy, sz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    cx, cy, cz = center
    pts = [
        (cx - sx, cy - sy, cz - sz), (cx + sx, cy - sy, cz - sz),
        (cx + sx, cy + sy, cz - sz), (cx - sx, cy + sy, cz - sz),
        (cx - sx, cy - sy, cz + sz), (cx + sx, cy - sy, cz + sz),
        (cx + sx, cy + sy, cz + sz), (cx - sx, cy + sy, cz + sz),
    ]
    vs = [bm.verts.new(p) for p in pts]
    faces = [
        (0, 3, 2, 1), (4, 5, 6, 7),
        (0, 1, 5, 4), (2, 3, 7, 6),
        (1, 2, 6, 5), (3, 0, 4, 7),
    ]
    for f in faces:
        poly = bm.faces.new([vs[i] for i in f])
        poly.material_index = mat_idx
        poly.smooth = False


def _add_steering_wheel(bm, center_blender, radius, tilt_rad, mat_idx):
    """Low-poly 3D steering wheel rim + hub + column in Blender coords (+Y forward, +Z up)."""
    cx, cy, cz = center_blender
    segs = 18
    tube_r = 0.017
    rings = []
    for i in range(segs):
        a = math.tau * i / segs
        ca, sa = math.cos(a), math.sin(a)
        pt = Vector((cx + radius * ca, cy - radius * sa * math.sin(tilt_rad), cz + radius * sa * math.cos(tilt_rad)))
        rad_dir = Vector((ca, -sa * math.sin(tilt_rad), sa * math.cos(tilt_rad))).normalized()
        ax_dir = Vector((0.0, math.cos(tilt_rad), math.sin(tilt_rad))).normalized()
        ring = []
        for k in range(6):
            b = math.tau * k / 6
            ring.append(bm.verts.new(pt + rad_dir * (tube_r * math.cos(b)) + ax_dir * (tube_r * math.sin(b))))
        rings.append(ring)
    for i in range(segs):
        r0, r1 = rings[i], rings[(i + 1) % segs]
        for k in range(6):
            f = bm.faces.new((r0[k], r0[(k + 1) % 6], r1[(k + 1) % 6], r1[k]))
            f.material_index = mat_idx
            f.smooth = True
    # Central hub + column
    _add_box(bm, (cx, cy + 0.06, cz - 0.02), (0.09, 0.16, 0.08), mat_idx)


def _add_cabin_interior(cabin_obj, body, dims, outline):
    """Add a clean dark interior tub (floor, seats, dash, console, steering wheel) to
    CabinOpening on bodies that don't have a modeled cabin, so open doors look solid."""
    if body in CLEAR_GLASS_BODIES:
        return
    W = dims["W"]
    roof = dims["roof"]
    ride = dims["ride"]
    front = max(y for y, _ in outline)
    rear = min(y for y, _ in outline)
    sill_z = outline[0][1]
    seat_y = 0.5 * (front + rear) - 0.12
    seat_z = sill_z + 0.14
    dash_y = front + 0.05
    cab_w = min(W * 0.76, W - 0.34)
    seat_x = min(W * 0.22, cab_w * 0.30)

    # Ensure an 'interior' material slot exists.
    mat_idx = None
    for i, m in enumerate(cabin_obj.data.materials):
        if m and m.name.split(".")[0] in ("interior", "trim", "plastic"):
            mat_idx = i
            break
    if mat_idx is None:
        m = bpy.data.materials.new("interior")
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (0.05, 0.05, 0.055, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.9
        cabin_obj.data.materials.append(m)
        mat_idx = len(cabin_obj.data.materials) - 1

    bm = bmesh.new()
    bm.from_mesh(cabin_obj.data)
    # Floor pan & rear bulkhead
    _add_box(bm, (0.0, 0.5 * (front + rear) - 0.08, sill_z - 0.03), (cab_w, (front - rear) + 0.38, 0.05), mat_idx)
    _add_box(bm, (0.0, rear - 0.24, seat_z + 0.28), (cab_w, 0.08, max(0.35, roof - sill_z - 0.12)), mat_idx)
    # Dashboard & center console
    dash_z = min(roof - 0.34, seat_z + 0.36)
    _add_box(bm, (0.0, dash_y, dash_z), (cab_w, 0.36, 0.24), mat_idx)
    _add_box(bm, (0.0, seat_y + 0.16, seat_z + 0.04), (0.20, 0.78, 0.22), mat_idx)
    # Left & right front seats (cushion, backrest, headrest)
    back_h = min(0.56, max(0.36, roof - seat_z - 0.24))
    for sx in (-1.0, 1.0):
        _add_box(bm, (sx * seat_x, seat_y, seat_z), (0.46, 0.48, 0.11), mat_idx)
        _add_box(bm, (sx * seat_x, seat_y - 0.24, seat_z + back_h * 0.5 + 0.04), (0.46, 0.11, back_h), mat_idx)
        _add_box(bm, (sx * seat_x, seat_y - 0.27, min(roof - 0.14, seat_z + back_h + 0.12)), (0.24, 0.09, 0.15), mat_idx)
    # Steering wheel (driver on +X right-hand side, matching WorldState UK convention)
    wheel_y = seat_y + 0.42
    wheel_z = min(roof - 0.28, seat_z + 0.40)
    _add_steering_wheel(bm, (seat_x, wheel_y, wheel_z), 0.175, math.radians(24.0), mat_idx)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(cabin_obj.data)
    bm.free()
    cabin_obj.data.update()


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
    _add_cabin_interior(parts[0], body, dims, outline)

    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / f"{body}.glb"), use_selection=True, export_format="GLB")

    # Convert to Godot axes: Blender (x, y_fwd, z_up) -> Godot (x, z_up, -y_fwd).
    arch = ARCHETYPES.get(body, "saloon")
    front = max(y for y, _ in outline)
    rear = min(y for y, _ in outline)
    sill_y = outline[0][1]
    roof_clear_y = max(z for _, z in outline)
    W = dims["W"]

    hinge_z = -front + 0.11
    hinge_y = sill_y + 0.47
    handle_z = -rear - 0.17
    handle_y = sill_y + 0.55

    # Exact driver seat cushion & steering wheel geometry (in Godot local space).
    if body == "kestrel":
        seat_x = 0.39
        seat_y = 0.56
        seat_z = 0.06
        wheel_center = [0.38, 0.92, -0.38]
        wheel_radius = 0.185
        wheel_tilt = 22.0
    else:
        seat_x = min(W * 0.22, W * 0.5 - 0.44)
        seat_y = sill_y + (0.20 if arch in ("hypercar", "sports") else 0.25)
        seat_z = -0.5 * (front + rear) + 0.12
        wheel_y = min(roof_clear_y - 0.24, seat_y + (0.34 if arch in ("hypercar", "sports") else 0.38))
        wheel_z = seat_z - (0.44 if arch in ("hypercar", "sports") else 0.40)
        wheel_center = [round(seat_x, 4), round(wheel_y, 4), round(wheel_z, 4)]
        wheel_radius = 0.175 if arch in ("hypercar", "sports") else 0.185
        wheel_tilt = 20.0 if arch in ("hypercar", "sports") else (28.0 if arch in ("van", "truck") else 23.0)

    # Interior door pull sits ~32cm forward of the exterior handle and slightly lower.
    int_pull_z = round(hinge_z + (handle_z - hinge_z) * 0.58, 4)
    int_pull_y = round(sill_y + 0.46, 4)

    # A-pillar / roof grab handle (for bracing during low sports duck or tall cab climb).
    pillar_z = round(hinge_z + 0.22, 4)
    pillar_y = round(min(roof_clear_y - 0.08, sill_y + 0.88), 4)
    pillar_x = round(W * 0.5 - 0.15, 4)

    # Footwell pedals (throttle, brake, dead pedal).
    pedal_y = round(sill_y + 0.08, 4)
    pedal_z = round(seat_z - 0.66, 4)

    door_max_deg = 54.0 if arch in ("hypercar", "sports") else (64.0 if arch in ("suv", "van", "truck") else 58.0)

    return {
        "archetype": arch,
        "hinge": [round(hinge_z, 4), round(hinge_y, 4)],
        "handle": [round(handle_z, 4), round(handle_y, 4)],
        "interior_pull": [int_pull_z, int_pull_y],
        "seat": [round(seat_z, 4), round(seat_y, 4)],
        "seat_x": round(seat_x, 4),
        "sill_y": round(sill_y, 4),
        "roof_clear_y": round(roof_clear_y, 4),
        "pillar_grip": [pillar_x, pillar_y, pillar_z],
        "wheel_center": wheel_center,
        "wheel_radius": wheel_radius,
        "wheel_tilt": wheel_tilt,
        "pedal_y": pedal_y,
        "pedal_z": pedal_z,
        "door_max_deg": door_max_deg,
        "driver_side": 1.0,
        "clear_glass": body in CLEAR_GLASS_BODIES,
    }


dims = json.loads((SOURCE / "bodies.json").read_text())
models = json.loads(MODELS.read_text())["models"]
bodies = sorted({m.get("art", m.get("body")) for m in models.values() if m.get("class", "car") == "car"} | {"mammoth"})
profiles = {body: build(body, dims[body]) for body in bodies if body in dims and (not ONLY or body in ONLY)}
if "--write-profiles" in ARGS:
    profile_path = ROOT / "config/empire/vehicle_entries.json"
    current = json.loads(profile_path.read_text())
    for body, profile in profiles.items():
        # Preserve the tuned origins used by existing production vehicles.
        current[body] = profile | current.get(body, {})
    profile_path.write_text(json.dumps(current, indent=2) + "\n")
print(f"VEHICLE ENTRIES BUILT: {len(profiles)} bodies", flush=True)
