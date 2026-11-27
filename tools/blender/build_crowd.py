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
SEATED_MODE = os.environ.get("CROWD_SEATED", "0") == "1"

# Alternate builds (even = body A male, odd = body B female) across 12 everyday outfits.
# Tuple: (slot, face, hair, cut, lower, footwear, acc)
VARIANTS = {
    "a": [
        (0, "ade", "crop", "polo", "chinos", "trainers", ""),
        (2, "ade", "crop", "blazer", "chinos", "derbies", ""),
        (4, "ade", "buzz", "hoodie", "jeans", "trainers", "beanie"),
        (6, "ade", "crop", "shirt", "chinos", "derbies", "shades"),
        (8, "ade", "buzz", "coat", "chinos", "derbies", ""),
        (10, "ade", "crop", "track", "track", "trainers", "cap"),
    ],
    "b": [
        (1, "jules", "bun", "tee", "jeans", "trainers", ""),
        (3, "jules", "crop", "jumper", "fitjeans", "trainers", ""),
        (5, "jules", "bun", "polo", "chinos", "trainers", "shades"),
        (7, "jules", "crop", "coat", "chinos", "trainers", ""),
        (9, "jules", "bun", "bomber", "widejeans", "trainers", "beanie"),
        (11, "jules", "buzz", "track", "leggings", "trainers", "headphones"),
    ],
}

SEATED_VARIANTS = {
    "a": [(0, "ade", "crop", "coat", "chinos", "trainers", "")],
    "b": [(1, "jules", "bun", "bomber", "jeans", "trainers", "")],
}

PART = {"hero_skin": 1, "hero_skin_body": 1, "hero_glove": 1, "hero_lips": 9, "hero_sclera": 8, "hero_iris": 5,
        "hero_pupil": 5, "hero_lash": 5, "hero_brow": 5, "hero_cargo": 2, "hero_cargo_pocket": 2, "hero_liner": 0,
        "hero_trainer": 0, "hero_trainer_panels": 0, "hero_midsole": 0, "hero_outsole": 0, "hero_lid_rim": 1,
        "hero_chino": 2, "hero_waistband": 2, "hero_eye": 8, "hero_jeans": 2, "hero_denim": 2, "hero_jogger": 2,
        "hero_track": 2, "hero_leggings": 2, "hero_derby": 0, "hero_shoe": 0, "hero_boot": 0,
        "hero_hair": 3, "hero_groom": 3, "hero_top": 4, "hero_top_panel": 6, "hero_top_collar": 6,
        "hero_shirt_white": 6, "hero_tie": 6, "hero_rib": 6, "hero_lapel": 6, "hero_shades": 5, "hero_acc": 6}
CHAINS = {1: ("b_thigh_l", "b_shin_l", "b_foot_l"), 2: ("b_thigh_r", "b_shin_r", "b_foot_r"),
          3: ("b_upper_arm_l", "b_forearm_l", "b_hand_l"), 4: ("b_upper_arm_r", "b_forearm_r", "b_hand_r"),
          5: ("b_head", "b_neck")}
LOWER = {"b_shin_l", "b_foot_l", "b_shin_r", "b_foot_r", "b_forearm_l", "b_hand_l", "b_forearm_r", "b_hand_r"}


def part_of(mat_name, obj_name=""):
    if obj_name.startswith(("Hair_", "Groom_")):
        return 3
    if obj_name.startswith("Acc_shades"):
        return 5
    if obj_name.startswith("Acc_"):
        return 6
    if obj_name.startswith(("Lower_", "Courier_Cargo", "Courier_Chinos", "Cargo_gusset")):
        return 2
    if obj_name.startswith(("Footwear_", "Courier_Trainer", "Courier_Soles", "Ankle_Liner")):
        return 0
    if mat_name.startswith("hero_hair_tie"):
        return 6
    if mat_name.startswith(("hero_hair", "hero_groom")):
        return 3
    if mat_name.startswith("hero_skin_face"):
        return 1
    if "lip" in mat_name.lower():
        return 9
    if "sclera" in mat_name.lower() or "eye_white" in mat_name.lower():
        return 8
    if any(k in mat_name.lower() for k in ("iris", "pupil", "lash", "brow")):
        return 5
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


def pose_seated(arm):
    # Driving pose: arms forward toward steering wheel, hands gripping rim, thighs forward.
    rotate_bone(arm, "b_upper_arm_l", "Y", -26.0)
    rotate_bone(arm, "b_upper_arm_r", "Y", 26.0)
    rotate_bone(arm, "b_upper_arm_l", "X", 52.0)
    rotate_bone(arm, "b_upper_arm_r", "X", 52.0)
    rotate_bone(arm, "b_forearm_l", "X", 28.0)
    rotate_bone(arm, "b_forearm_r", "X", 28.0)
    rotate_bone(arm, "b_thigh_l", "X", 82.0)
    rotate_bone(arm, "b_thigh_r", "X", 82.0)
    rotate_bone(arm, "b_shin_l", "X", -78.0)
    rotate_bone(arm, "b_shin_r", "X", -78.0)


def pieces(face, hair, cut, lower="chinos", footwear="trainers", acc=""):
    meshes = {o.name for o in bpy.context.scene.objects if o.type == "MESH"}
    if lower == "jeans" and "Lower_jeans" in meshes:
        trouser = {"Lower_jeans", "Lower_jeans_Pockets"}
    elif lower == "fitjeans" and "Lower_fitjeans" in meshes:
        trouser = {"Lower_fitjeans"}
    elif lower == "widejeans" and "Lower_widejeans" in meshes:
        trouser = {"Lower_widejeans"}
    elif lower == "track" and "Lower_track" in meshes:
        trouser = {"Lower_track", "Lower_track_Stripes"}
    elif lower == "leggings" and "Lower_leggings" in meshes:
        trouser = {"Lower_leggings"}
    elif lower == "cargo" and "Courier_Cargo" in meshes:
        trouser = {"Courier_Cargo", "Cargo_gusset_l", "Cargo_gusset_r"}
    else:
        trouser = {"Courier_Chinos"}
    if footwear == "derbies" and "Footwear_derbies" in meshes:
        shoes = {"Footwear_derbies", "Ankle_Liner"}
    else:
        shoes = {"Courier_Trainers", "Courier_Soles", "Ankle_Liner"}
    names = trouser | shoes | {"Skin_Hands", "Face_" + face, "Top_" + cut.capitalize(),
                               "Skin_Arms_" + cut.capitalize()}
    if cut == "shirt":
        names.add("Courier_Waistband")
    if "Face_" + face not in meshes:
        alt = sorted(n for n in meshes if n.startswith("Face_"))
        names.discard("Face_" + face)
        names.add(alt[0])
        face = alt[0][5:]
        print("CROWD fallback face", face)
    hn = "Hair_%s_%s" % (hair, face)
    gn = "Groom_%s_%s" % (hair, face)
    if hn in meshes:
        names.add(hn)
    else:
        alts = sorted(n for n in meshes if n.startswith("Hair_") and n.endswith("_" + face))
        if alts:
            pick = alts[sum(map(ord, hair)) % len(alts)]
            names.add(pick)
            print("CROWD fallback hair", hn, "->", pick)
    if gn in meshes:
        names.add(gn)
    if acc:
        an = "Acc_%s_%s" % (acc, face)
        if an in meshes:
            names.add(an)
    out = [o for o in bpy.context.scene.objects if o.type == "MESH"
           and (o.name in names or o.name.startswith("Topx_" + cut.capitalize() + "_"))]
    assert any(o.name.startswith("Face_") for o in out), "no face for %s/%s" % (face, cut)
    assert any(o.name.startswith(("Hair_", "Groom_")) for o in out), "no hair for %s/%s" % (face, cut)
    return out


def build(arm, v, face, hair, cut, lower="chinos", footwear="trainers", acc=""):
    objs = pieces(face, hair, cut, lower, footwear, acc)
    bpy.ops.object.select_all(action="DESELECT")
    dup = []
    # Tag each source object's faces with its resolved part ID via a temporary material
    # BEFORE joining, so part_of() can inspect obj.name (Hair_/Groom_/Acc_/Lower_) accurately.
    for o in objs:
        c = o.copy()
        c.data = o.data.copy()
        bpy.context.scene.collection.objects.link(c)
        if c.data.shape_keys:
            c.shape_key_clear()
        orig_name = o.name
        is_head_detail = orig_name.startswith(("Face_", "Hair_", "Groom_"))
        # Remap materials to canonical "__part_<id>" so join() preserves exact part IDs.
        for mi, mat in enumerate(list(c.data.materials)):
            pid = part_of(mat.name if mat else "", orig_name)
            mname = "__part_%d" % pid
            c.data.materials[mi] = bpy.data.materials.get(mname) or bpy.data.materials.new(mname)
        if not c.data.materials:
            pid = part_of("", orig_name)
            mname = "__part_%d" % pid
            c.data.materials.append(bpy.data.materials.get(mname) or bpy.data.materials.new(mname))
        # Protect head/face/hair and shoe soles during decimation so eyes/hair/soles never collapse.
        vg = c.vertex_groups.new(name="_decimate_body")
        is_sole = orig_name.startswith(("Courier_Soles", "Courier_Trainers", "Footwear_"))
        if is_head_detail:
            all_vi = [vert.index for vert in c.data.vertices]
            if all_vi:
                vg.add(all_vi, 0.0, "REPLACE")
        elif is_sole:
            low_vi = [vert.index for vert in c.data.vertices if vert.co.z < 0.14]
            hi_vi = [vert.index for vert in c.data.vertices if vert.co.z >= 0.14]
            if low_vi:
                vg.add(low_vi, 0.0, "REPLACE")
            if hi_vi:
                vg.add(hi_vi, 1.0, "REPLACE")
        else:
            all_vi = [vert.index for vert in c.data.vertices]
            if all_vi:
                vg.add(all_vi, 1.0, "REPLACE")
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
    ob.name = ("driver_%d" if SEATED_MODE else "person_%d") % v
    ob.data.name = ob.name
    me = ob.data
    if SEATED_MODE:
        # Trim legs below mid-thigh and shift pelvis to origin (0, 0, 0) so driver sits cleanly on seat.
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(me)
        # Pelvis in Blender Z-up is at ~0.92 m; trim anything below z < 0.72 m (shins/feet).
        drop = [vert for vert in bm.verts if vert.co.z < 0.72]
        if drop:
            bmesh.ops.delete(bm, geom=drop, context="VERTS")
        for vert in bm.verts:
            vert.co.z -= 0.90
        bm.to_mesh(me)
        bm.free()
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > TARGET:
        # Protected-head decimation: decimate body/garments first, then gentle overall pass if still over.
        dec = ob.modifiers.new("dec_body", "DECIMATE")
        dec.vertex_group = "_decimate_body"
        dec.ratio = max(0.08, min(1.0, (TARGET * 0.72) / max(tris, 1)))
        bpy.ops.object.modifier_apply(modifier=dec.name)
        tris2 = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        if tris2 > TARGET:
            dec2 = ob.modifiers.new("dec_all", "DECIMATE")
            dec2.ratio = min(1.0, TARGET / max(tris2, 1))
            bpy.ops.object.modifier_apply(modifier=dec2.name)
    me = ob.data
    me.validate(clean_customdata=False)
    # Per-vertex limb and weights from the skin.
    gname = {g.index: g.name for g in ob.vertex_groups}
    vdata = []
    for vert in me.vertices:
        w = {}
        tot = 0.0
        for g in vert.groups:
            n = gname.get(g.group, "")
            if n == "_decimate_body":
                continue
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
    hair_polys = 0
    for poly in me.polygons:
        mname = me.materials[poly.material_index].name if me.materials and poly.material_index < len(me.materials) else "__part_4"
        part = int(mname.split("_")[-1]) if mname.startswith("__part_") else 4
        if part == 3:
            hair_polys += 1
        poly.use_smooth = True
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            limb, cw, lw = vdata[vi]
            uv1.data[li].uv = (part + 0.5, limb + 0.5)
            uv2.data[li].uv = (cw, lw)
    assert hair_polys > 0, "hair vanished after decimation on %s" % ob.name
    me.materials.clear()
    me.materials.append(bpy.data.materials.get("person") or bpy.data.materials.new("person"))
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    print("%s: %s/%s/%s/%s %d -> %d tris (hair_polys=%d)" % (
        ob.name, face, hair, cut, lower, tris, sum(len(p.vertices) - 2 for p in me.polygons), hair_polys))
    return ob


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    people = []
    specs = SEATED_VARIANTS if SEATED_MODE else VARIANTS
    for body, variants in specs.items():
        arm, objects = load("character.glb" if body == "a" else "character_b.glb")
        if SEATED_MODE:
            pose_seated(arm)
        else:
            pose(arm)
        people.extend(build(arm, *spec) for spec in variants)
        for obj in objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    for i, p in enumerate(people):
        p.location = (0, 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    for p in people:
        p.select_set(True)
    default_out = "crowd_seated.glb" if SEATED_MODE else "crowd.glb"
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, os.environ.get("CROWD_OUT", default_out)), export_format="GLB", use_selection=True,
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
