"""City Empire crowd: pedestrians made from the hero's own character.

Run:  blender -b --factory-startup --python tools/blender/build_crowd.py -- assets/models [preview.png]

Imports both skinned hero builds, including fitted hair and clothes. For each outfit in
VARIANTS: poses the arms down from the bind A-pose and the legs together,
bakes the pose, joins the pieces, decimates to ~TARGET triangles and exports
an unskinned mesh `person_<n>` into crowd.glb, one material ("person").
Per-vertex data the shaders use (crowd.gdshader / person_pose.gdshaderinc):
  UV.x  = part + 0.5 (0 shoes, 1 skin, 2 trousers, 3 hair, 4 top, 5 dark
          face details, 6 accent: top panels, collar, hair ties, 8 eye white,
          9 lips)
  UV.y  = limb + 0.5 (0 body, 1 left leg, 2 right leg, 3 left arm, 4 right
          arm, 5 head) – the side with the most skin weight
  UV2.x = how much the vertex follows that limb (its bones' skin weight)
  UV2.y = how much it follows the lower segment (shin+foot / forearm+hand)
(glTF flips v on export: the shaders read 0.5 - UV.y and 1 - UV2.y.)
Pivots (Godot y, metres): hip 0.94, knee 0.49, shoulder 1.5, elbow PRINTed.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "assets/models"
PREVIEW = ARGS[1] if len(ARGS) > 1 else ""
TARGET = int(os.environ.get("CROWD_TARGET", "3100"))   # CROWD_TARGET=900 CROWD_OUT=crowd_far.glb: the far walkers

# Alternate builds while keeping the eight existing runtime slots.
VARIANTS = {
    "a": [(0, "ade", "crop", "polo"), (2, "malik", "fade", "blazer"),
          (4, "theo", "curls", "hoodie"), (6, "kai", "buzz", "shirt")],
    "b": [(1, "rio", "ponytail", "tee"), (3, "sam", "bun", "jumper"),
          (5, "noa", "pixie", "polo"), (7, "jules", "bob", "blazer")],
}

PART = {"hero_skin": 1, "hero_skin_body": 1, "hero_glove": 1, "hero_lips": 9, "hero_sclera": 8, "hero_iris": 5,
        "hero_pupil": 5, "hero_lash": 5, "hero_brow": 5, "hero_cargo": 2, "hero_cargo_pocket": 2, "hero_liner": 0,
        "hero_trainer": 0, "hero_trainer_panels": 0, "hero_midsole": 0, "hero_outsole": 0, "hero_lid_rim": 1, "hero_chino": 2, "hero_waistband": 2, "hero_eye": 8,
        "hero_hair": 3, "hero_top": 4, "hero_top_panel": 6, "hero_top_collar": 6,
        "hero_shirt_white": 6, "hero_tie": 6, "hero_rib": 6, "hero_lapel": 6}
CHAINS = {1: ("b_thigh_l", "b_shin_l", "b_foot_l"), 2: ("b_thigh_r", "b_shin_r", "b_foot_r"),
          3: ("b_upper_arm_l", "b_forearm_l", "b_hand_l"), 4: ("b_upper_arm_r", "b_forearm_r", "b_hand_r"),
          5: ("b_head", "b_neck")}
LOWER = {"b_shin_l", "b_foot_l", "b_shin_r", "b_foot_r", "b_forearm_l", "b_hand_l", "b_forearm_r", "b_hand_r"}


def part_of(mat_name):
    if mat_name.startswith("hero_hair_tie"):
        return 6
    if mat_name.startswith("hero_hair"):
        return 3
    if mat_name.startswith("hero_skin_face"):
        return 1
    return PART.get(mat_name.split(".")[0], 4)


def load(model):
    imported = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, model))
    objects = set(bpy.context.scene.objects) - imported
    return next(o for o in objects if o.type == "ARMATURE"), objects


def rotate_bone(arm, name, axis, deg):
    pb = arm.pose.bones[name]
    pivot = arm.matrix_world @ pb.head
    R = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-pivot)
    pb.matrix = arm.matrix_world.inverted() @ R @ arm.matrix_world @ pb.matrix
    bpy.context.view_layer.update()


def pose(arm):
    # Arms down by the sides (bind pose is ~42 degrees out), legs together.
    rotate_bone(arm, "b_upper_arm_l", "Y", -34.0)
    rotate_bone(arm, "b_upper_arm_r", "Y", 34.0)
    rotate_bone(arm, "b_forearm_l", "X", 8.0)
    rotate_bone(arm, "b_forearm_r", "X", 8.0)
    rotate_bone(arm, "b_thigh_l", "Y", 2.5)
    rotate_bone(arm, "b_thigh_r", "Y", -2.5)
    e = arm.matrix_world @ arm.pose.bones["b_forearm_l"].head
    h = arm.matrix_world @ arm.pose.bones["b_hand_l"].tail
    print("POSE elbow", tuple(round(v, 3) for v in e), "hand", tuple(round(v, 3) for v in h))


def pieces(face, hair, cut):
    formal = cut in ("shirt", "blazer")
    trouser = {"Courier_Chinos"} if formal else {"Courier_Cargo", "Cargo_gusset_l", "Cargo_gusset_r"}
    names = trouser | {"Ankle_Liner", "Courier_Trainers", "Courier_Soles", "Skin_Hands",
                       "Face_" + face, "Hair_%s_%s" % (hair, face), "Top_" + cut.capitalize(),
                       "Skin_Arms_" + cut.capitalize()}
    if cut == "shirt":
        names.add("Courier_Waistband")
    return [o for o in bpy.context.scene.objects if o.type == "MESH"
            and (o.name in names or o.name.startswith("Topx_" + cut.capitalize() + "_"))]


def build(arm, v, face, hair, cut):
    objs = pieces(face, hair, cut)
    bpy.ops.object.select_all(action="DESELECT")
    dup = []
    for o in objs:
        c = o.copy()
        c.data = o.data.copy()
        bpy.context.scene.collection.objects.link(c)
        if c.data.shape_keys:
            c.shape_key_clear()
        dup.append(c)
    # Bake the pose (armature modifier), keep the vertex groups.
    for c in dup:
        bpy.context.view_layer.objects.active = c
        for m in list(c.modifiers):
            if m.type == "ARMATURE":
                m.object = arm
                bpy.ops.object.modifier_apply(modifier=m.name)
        c.parent = None
        c.matrix_world = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    for c in dup:
        c.select_set(True)
    bpy.context.view_layer.objects.active = dup[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "person_%d" % v
    ob.data.name = ob.name
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    dec = ob.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, TARGET / max(tris, 1))
    bpy.ops.object.modifier_apply(modifier=dec.name)
    me = ob.data
    # Per-vertex limb and weights from the skin.
    gname = {g.index: g.name for g in ob.vertex_groups}
    vdata = []
    for vert in me.vertices:
        w = {}
        tot = 0.0
        for g in vert.groups:
            n = gname.get(g.group, "")
            w[n] = w.get(n, 0.0) + g.weight
            tot += g.weight
        tot = max(tot, 1e-6)
        best, best_w = 0, 0.0
        for limb, bones in CHAINS.items():
            cw = sum(w.get(b, 0.0) for b in bones) / tot
            if cw > best_w:
                best, best_w = limb, cw
        if best_w < 0.02:
            best, best_w = 0, 0.0
        lw = sum(w.get(b, 0.0) for b in LOWER if b in CHAINS.get(best, ())) / tot if best in (1, 2, 3, 4) else 0.0
        vdata.append((best, min(best_w, 1.0), min(lw, 1.0)))
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv1 = me.uv_layers.new(name="UVMap")
    uv2 = me.uv_layers.new(name="UV2")
    for poly in me.polygons:
        part = part_of(me.materials[poly.material_index].name) if me.materials else 4
        poly.use_smooth = True
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            limb, cw, lw = vdata[vi]
            uv1.data[li].uv = (part + 0.5, limb + 0.5)
            uv2.data[li].uv = (cw, lw)
    me.materials.clear()
    me.materials.append(bpy.data.materials.get("person") or bpy.data.materials.new("person"))
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    print("PERSON %d: %s/%s/%s %d -> %d tris" % (v, face, hair, cut, tris, sum(len(p.vertices) - 2 for p in me.polygons)))
    return ob


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    people = []
    for body, variants in VARIANTS.items():
        arm, objects = load("character.glb" if body == "a" else "character_b.glb")
        pose(arm)
        people.extend(build(arm, *spec) for spec in variants)
        for obj in objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    for i, p in enumerate(people):
        p.location = (0, 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    for p in people:
        p.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, os.environ.get("CROWD_OUT", "crowd.glb")), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_materials="EXPORT", export_skins=False,
                              export_animations=False)
    print("CROWD DONE")
    if PREVIEW:
        for i, p in enumerate(people):
            p.location = (i * 0.9 - len(people) * 0.45, 0, 0)
        scn = bpy.context.scene
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        scn.collection.objects.link(cam)
        cam.location = (0, -9.0, 1.1)
        cam.rotation_euler = (math.radians(88), 0, 0)
        cam.data.lens = 40
        scn.camera = cam
        scn.render.engine = "BLENDER_WORKBENCH"
        scn.display.shading.light = "STUDIO"
        scn.display.shading.color_type = "SINGLE"
        scn.render.resolution_x = 1600
        scn.render.resolution_y = 600
        scn.render.filepath = PREVIEW
        bpy.ops.render.render(write_still=True)


main()
