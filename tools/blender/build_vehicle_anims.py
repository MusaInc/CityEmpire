"""Author and bake reusable AAA vehicle entry, exit, seat-slide and driving animations
using Blender's native Bezier F-curve Action solver.

Run with Blender in background mode:
  blender -b --factory-startup --python-exit-code 1 --python tools/blender/build_vehicle_anims.py

Outputs:
  * art/hero/vehicle_anims.blend   (Blender scene with named Actions for inspection/refinement)
  * config/empire/vehicle_anims.json (compact 30-sample baked tracks for Godot CharacterRig)

Conventions (canonical entry from RIGHT side, side = +1.0; Godot mirrors cleanly for side = -1.0):
  * Bone local Euler angles [rx, ry, rz] in radians match CharacterRig._rx/_ry/_rz:
      - thighs/shins: +rx raises thigh forward, -rx bends knee back
      - upper_arms/forearms: +rx swings arm forward, +rx bends elbow forward
      - spine/chest/neck/head: -rx leans/ducks forward, +rx leans back
      - ry: +ry turns left (CCW from above), -ry turns right
      - rz: +rz tilts right / abducts left arm, -rz tilts left / abducts right arm
  * Every entry clip is staged cleanly across normalized time u in [0..1]:
      0.00..0.24  REACH & PULL DOOR OPEN (near hand locked to exterior handle, feet planted, subtle step-back)
      0.24..0.54  DUCK & LEAD LEG STEP IN (trailing foot stays grounded! head ducks under roof, lead leg clears sill)
      0.54..0.76  HIP PIVOT & TRAILING LEG IN (hips lower onto cushion, body rotates forward, trailing leg sweeps in)
      0.76..0.93  PULL DOOR SHUT (near hand grabs interior door pull and closes door cleanly)
      0.93..1.00  SETTLE ONTO CONTROLS (both hands smoothly acquire steering wheel / yoke / cyclic & feet settle)
  * Every exit clip is authored specifically for physical realism (NOT a naive time-reversal!):
      0.00..0.22  RELEASE CONTROLS & PUSH DOOR OPEN (near hand pushes interior handle)
      0.22..0.48  SWIVEL HIPS & SWING BOTH FEET OUT TO GROUND (feet plant firmly via ground IK!)
      0.48..0.74  DUCK HEAD & RISE UPRIGHT USING DOOR/PILLAR SUPPORT (weight transfer onto planted feet!)
      0.74..0.94  STEP CLEAR & SWING DOOR CLOSED BEHIND
      0.94..1.00  SETTLE INTO NATURAL STANDING IDLE STANCE
"""
import json
import math
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT_JSON = ROOT / "config/empire/vehicle_anims.json"
OUT_BLEND = ROOT / "art/hero/vehicle_anims.blend"
SAMPLES = 31

BONES = [
    "hips", "spine", "chest", "neck", "head",
    "upper_arm_l", "forearm_l", "hand_l",
    "upper_arm_r", "forearm_r", "hand_r",
    "thigh_l", "shin_l", "foot_l",
    "thigh_r", "shin_r", "foot_r",
]

# Scalar/channel names baked alongside bone Euler curves.
CHANNELS = [
    "seat_t",       # 0 = stand outside, 1 = seated inside
    "yaw_t",        # 0 = facing door inward, 1 = facing vehicle forward
    "door",         # 0 = closed, 1 = full open (scaled by max clear angle)
    "hips_x",       # local lateral offset (m, + = toward vehicle right / outward on +1 side)
    "hips_y",       # local vertical offset (m, negative = crouch/lower, positive = step up)
    "hips_z",       # local fore-aft offset (m, + = step back from door swing)
    "duck",         # 0..1 roof-clearance head duck driver (scaled by actual roof height in Godot)
    "ext_hand_w",   # 0..1 near-hand IK onto exterior door handle
    "int_hand_w",   # 0..1 near-hand IK onto interior door pull
    "brace_hand_w", # 0..1 far-hand IK onto A-pillar / roof / gunwale brace
    "wheel_hand_w", # 0..1 both-hands IK onto steering wheel / helm / controls
    "foot_l_gnd",   # 0..1 left-foot live ground-plane IK weight (on side=+1, left leg is LEAD leg!)
    "foot_r_gnd",   # 0..1 right-foot live ground-plane IK weight (on side=+1, right leg is TRAILING leg!)
    "foot_pedal_w", # 0..1 seated footwell/pedal placement weight
    "grip_l",       # 0..1 left hand finger curl
    "grip_r",       # 0..1 right hand finger curl
]


def _setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    arm_data = bpy.data.armatures.new("VehicleHeroRig")
    arm_obj = bpy.data.objects.new("VehicleHeroRig", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    for idx, name in enumerate(BONES):
        eb = arm_data.edit_bones.new(name)
        eb.head = (idx * 0.1, 0.0, 0.0)
        eb.tail = (idx * 0.1, 0.0, 0.2)
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "XYZ"
    for ch in CHANNELS:
        arm_obj[ch] = 0.0
    return arm_obj


def _bake_clip(arm_obj, clip_name, duration, keyframes):
    """Build a Blender Action with smooth Bezier F-curves for all bones & channels,
    evaluate cleanly across SAMPLES normalized frames, and return the compact dict."""
    action = bpy.data.actions.new(name=clip_name)
    arm_obj.animation_data_create()
    arm_obj.animation_data.action = action
    n_frames = SAMPLES - 1

    # Insert keyframes for all bones and scalar channels.
    for u, data in keyframes:
        frame = round(u * n_frames, 3)
        bone_map = data.get("bones", {})
        for bname in BONES:
            euler = bone_map.get(bname, (0.0, 0.0, 0.0))
            pb = arm_obj.pose.bones[bname]
            pb.rotation_euler = euler
            pb.keyframe_insert(data_path="rotation_euler", frame=frame)
        for ch in CHANNELS:
            if ch in data:
                arm_obj[ch] = float(data[ch])
                arm_obj.keyframe_insert(data_path=f'["{ch}"]', frame=frame)

    # Set smooth clamped auto-Bezier handles on every F-curve (zero overshoot, zero linear corners).
    for fc in action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"
        fc.update()

    # Evaluate via Blender's native F-curve evaluator at evenly spaced samples.
    scene = bpy.context.scene
    out_channels = {ch: [] for ch in CHANNELS}
    out_bones = {b: [] for b in BONES}
    for s in range(SAMPLES):
        scene.frame_set(s)
        for ch in CHANNELS:
            out_channels[ch].append(round(float(arm_obj[ch]), 4))
        for bname in BONES:
            e = arm_obj.pose.bones[bname].rotation_euler
            out_bones[bname].append([round(float(e.x), 4), round(float(e.y), 4), round(float(e.z), 4)])

    # Prune bones that stay strictly zero throughout the clip to keep JSON lean.
    compact_bones = {}
    for bname, vals in out_bones.items():
        if any(abs(v[0]) > 1e-4 or abs(v[1]) > 1e-4 or abs(v[2]) > 1e-4 for v in vals):
            compact_bones[bname] = vals

    return {
        "duration": round(duration, 3),
        "samples": SAMPLES,
        "channels": out_channels,
        "bones": compact_bones,
    }


def _seated_bones(recline=0.08, knee_flex=1.36, hip_flex=1.42, spread=0.09, arm_fwd=0.58, elbow=0.72):
    return {
        "hips": (0.0, 0.0, 0.0),
        "spine": (recline * 0.45, 0.0, 0.0),
        "chest": (recline * 0.55, 0.0, 0.0),
        "neck": (-recline * 0.5, 0.0, 0.0),
        "head": (-recline * 0.35, 0.0, 0.0),
        "thigh_l": (hip_flex, 0.0, -spread),
        "shin_l": (-knee_flex, 0.0, 0.0),
        "foot_l": (0.14, 0.0, 0.0),
        "thigh_r": (hip_flex, 0.0, spread),
        "shin_r": (-knee_flex, 0.0, 0.0),
        "foot_r": (0.14, 0.0, 0.0),
        "upper_arm_l": (arm_fwd, 0.0, -0.14),
        "forearm_l": (elbow, 0.0, 0.0),
        "upper_arm_r": (arm_fwd, 0.0, 0.14),
        "forearm_r": (elbow, 0.0, 0.0),
    }


def _car_enter_keys(crouch=0.14, duck_amt=0.55, step_lift=0.06, lead_thigh=1.18,
                    recline=0.08, hip_flex=1.44, knee_flex=1.38, brace_w=0.45,
                    climb_up=0.0):
    """Canonical right-side (+1) car/SUV/sports/truck entry keyframes.
    On side=+1, character faces -X (into door): LEFT leg is closer to the front (lead leg!),
    LEFT hand is forward (near hinge/pillar), RIGHT hand is aft (near handle!).
    Wait: facing -X means +Z (rear of car) is to the character's LEFT, -Z (front of car) is to
    the character's RIGHT!
    Verify right-hand frame when facing -X (world):
      forward = (-1, 0, 0), up = (0, 1, 0) -> right = forward x up = (0, 0, -1) = car FRONT!
      left = (0, 0, +1) = car REAR (where the exterior door handle sits!).
    So on side=+1:
      - LEFT hand reaches the exterior door handle (rear of door)!
      - RIGHT hand braces on A-pillar / front roof / wheel!
      - RIGHT leg steps in FIRST (toward the footwell / front of cabin)!
      - LEFT leg stays planted on the street while hips enter, then swings in last!
    """
    seated = _seated_bones(recline=recline, hip_flex=hip_flex, knee_flex=knee_flex)
    return [
        # 0.00: Standing square at the door, natural relaxed stance, starting reach.
        (0.00, {
            "seat_t": 0.0, "yaw_t": 0.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.22, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.15, "grip_r": 0.10,
            "bones": {
                "spine": (-0.04, 0.06, 0.0),
                "chest": (-0.05, 0.10, 0.0),
                "neck": (0.04, -0.08, 0.0),
                "head": (0.04, -0.06, 0.0),
                "upper_arm_l": (0.28, 0.0, -0.10), "forearm_l": (0.38, 0.0, 0.0),
                "upper_arm_r": (0.06, 0.0, 0.08), "forearm_r": (0.24, 0.0, 0.0),
            },
        }),
        # 0.14: Left hand grabs exterior handle firmly, slight torso lean in.
        (0.14, {
            "seat_t": 0.0, "yaw_t": 0.0, "door": 0.04,
            "hips_x": 0.03, "hips_y": -0.03, "hips_z": 0.02, "duck": 0.05,
            "ext_hand_w": 0.98, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.92, "grip_r": 0.15,
            "bones": {
                "spine": (-0.12, 0.14, -0.03),
                "chest": (-0.10, 0.18, -0.04),
                "neck": (0.08, -0.14, 0.0),
                "head": (0.06, -0.10, 0.0),
                "thigh_l": (0.14, 0.0, -0.04), "shin_l": (-0.22, 0.0, 0.0),
                "thigh_r": (0.10, 0.0, 0.04), "shin_r": (-0.18, 0.0, 0.0),
                "upper_arm_l": (0.68, 0.0, -0.14), "forearm_l": (0.52, 0.0, 0.0),
                "upper_arm_r": (0.14, 0.0, 0.12), "forearm_r": (0.30, 0.0, 0.0),
            },
        }),
        # 0.28: Pulling door wide open while stepping slightly outward/back to clear swing arc!
        (0.28, {
            "seat_t": 0.02, "yaw_t": 0.05, "door": 0.92,
            "hips_x": 0.14, "hips_y": -0.06, "hips_z": 0.07, "duck": 0.15,
            "ext_hand_w": 0.95, "int_hand_w": 0.0, "brace_hand_w": brace_w * 0.45, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 0.92, "foot_pedal_w": 0.0,
            "grip_l": 0.88, "grip_r": 0.35,
            "bones": {
                "spine": (-0.14, -0.12, 0.04),
                "chest": (-0.12, -0.22, 0.05),
                "neck": (0.10, 0.16, 0.0),
                "head": (0.08, 0.12, 0.0),
                "thigh_l": (0.20, 0.0, -0.08), "shin_l": (-0.30, 0.0, 0.0),
                "thigh_r": (0.34, 0.0, 0.12), "shin_r": (-0.52, 0.0, 0.0),
                "upper_arm_l": (0.58, 0.0, -0.24), "forearm_l": (0.72, 0.0, 0.0),
                "upper_arm_r": (0.48, 0.0, 0.18), "forearm_r": (0.48, 0.0, 0.0),
            },
        }),
        # 0.46: Lead (right) leg lifts & steps over sill into footwell; head ducks under roof; left foot stays grounded!
        (0.46, {
            "seat_t": 0.34, "yaw_t": 0.26, "door": 1.0,
            "hips_x": 0.04, "hips_y": -crouch + climb_up * 0.55 + step_lift * 0.3, "hips_z": 0.02, "duck": duck_amt,
            "ext_hand_w": 0.22, "int_hand_w": 0.0, "brace_hand_w": brace_w, "wheel_hand_w": 0.0,
            "foot_l_gnd": 0.92, "foot_r_gnd": 0.0, "foot_pedal_w": 0.15,
            "grip_l": 0.25, "grip_r": 0.85,
            "bones": {
                "spine": (-0.34 - 0.18 * duck_amt, -0.18, 0.08),
                "chest": (-0.28 - 0.16 * duck_amt, -0.22, 0.10),
                "neck": (-0.14 - 0.12 * duck_amt, 0.18, -0.06),
                "head": (-0.08 - 0.10 * duck_amt, 0.15, -0.05),
                "thigh_r": (lead_thigh, -0.12, 0.22), "shin_r": (-1.34, 0.0, 0.0), "foot_r": (0.28, 0.0, 0.0),
                "thigh_l": (0.42 + climb_up * 0.8, 0.06, -0.10), "shin_l": (-0.64 - climb_up * 0.6, 0.0, 0.0), "foot_l": (-0.12, 0.0, 0.0),
                "upper_arm_l": (0.36, 0.0, -0.22), "forearm_l": (0.55, 0.0, 0.0),
                "upper_arm_r": (0.82, 0.0, 0.20), "forearm_r": (0.64, 0.0, 0.0),
            },
        }),
        # 0.64: Hips pivot and drop onto the seat cushion; head passes beneath roof rail; trailing (left) leg begins lifting in!
        (0.64, {
            "seat_t": 0.82, "yaw_t": 0.72, "door": 0.96,
            "hips_x": 0.0, "hips_y": -crouch * 0.45 + climb_up * 0.25, "hips_z": 0.0, "duck": duck_amt * 0.82,
            "ext_hand_w": 0.0, "int_hand_w": 0.25, "brace_hand_w": brace_w * 0.4, "wheel_hand_w": 0.20,
            "foot_l_gnd": 0.18, "foot_r_gnd": 0.0, "foot_pedal_w": 0.62,
            "grip_l": 0.30, "grip_r": 0.60,
            "bones": {
                "spine": (-0.24 - 0.12 * duck_amt, -0.14, 0.05),
                "chest": (-0.18 - 0.10 * duck_amt, -0.16, 0.06),
                "neck": (-0.08 - 0.08 * duck_amt, 0.14, 0.0),
                "head": (-0.04, 0.12, 0.0),
                "thigh_r": (hip_flex + 0.06, -0.04, 0.12), "shin_r": (-knee_flex, 0.0, 0.0), "foot_r": (0.16, 0.0, 0.0),
                "thigh_l": (1.28, 0.18, -0.24), "shin_l": (-1.58, 0.0, 0.0), "foot_l": (0.34, 0.0, 0.0),
                "upper_arm_l": (0.48, 0.0, -0.32), "forearm_l": (0.62, 0.0, 0.0),
                "upper_arm_r": (0.66, 0.0, 0.16), "forearm_r": (0.76, 0.0, 0.0),
            },
        }),
        # 0.78: Seated facing forward, trailing leg inside cabin; near (right? Wait: once facing -Z forward,
        # RIGHT side of character is NOW next to the right door!! So RIGHT hand reaches out to pull right door shut!)
        (0.78, {
            "seat_t": 0.98, "yaw_t": 0.96, "door": 0.82,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": duck_amt * 0.18,
            "ext_hand_w": 0.0, "int_hand_w": 0.96, "brace_hand_w": 0.0, "wheel_hand_w": 0.45,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 0.92,
            "grip_l": 0.72, "grip_r": 0.92,
            "bones": {
                "spine": (recline * 0.3, -0.12, 0.06),
                "chest": (recline * 0.3, -0.18, 0.08),
                "neck": (0.0, 0.16, -0.04),
                "head": (0.0, 0.12, 0.0),
                "thigh_l": (hip_flex, 0.0, -0.10), "shin_l": (-knee_flex, 0.0, 0.0), "foot_l": (0.15, 0.0, 0.0),
                "thigh_r": (hip_flex, 0.0, 0.10), "shin_r": (-knee_flex, 0.0, 0.0), "foot_r": (0.15, 0.0, 0.0),
                "upper_arm_l": (0.58, 0.0, -0.14), "forearm_l": (0.74, 0.0, 0.0),
                "upper_arm_r": (0.42, 0.0, 0.34), "forearm_r": (0.68, 0.0, 0.0),
            },
        }),
        # 0.91: Door latches firmly shut; near hand releases interior pull and sweeps to wheel!
        (0.91, {
            "seat_t": 1.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.25, "brace_hand_w": 0.0, "wheel_hand_w": 0.85,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 1.0,
            "grip_l": 0.85, "grip_r": 0.82,
            "bones": seated,
        }),
        # 1.00: Settled comfortably in driving posture with both hands gripping steering wheel!
        (1.00, {
            "seat_t": 1.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 1.0,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 1.0,
            "grip_l": 0.86, "grip_r": 0.86,
            "bones": seated,
        }),
    ]


def _car_exit_keys(crouch=0.14, duck_amt=0.55, recline=0.08, hip_flex=1.44, knee_flex=1.38,
                   brace_w=0.42, step_down=0.0):
    """Canonical right-side (+1) exit keyframes (physically authored: push door -> swivel ->
    plant right foot then left foot on street -> duck & stand upright -> close door -> idle)."""
    seated = _seated_bones(recline=recline, hip_flex=hip_flex, knee_flex=knee_flex)
    return [
        # 0.00: Seated in driving posture.
        (0.00, {
            "seat_t": 1.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.15, "brace_hand_w": 0.0, "wheel_hand_w": 0.90,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 1.0,
            "grip_l": 0.82, "grip_r": 0.80,
            "bones": seated,
        }),
        # 0.18: Near (right) hand grabs interior latch & pushes door open.
        (0.18, {
            "seat_t": 0.98, "yaw_t": 0.92, "door": 0.72,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.10,
            "ext_hand_w": 0.0, "int_hand_w": 0.96, "brace_hand_w": 0.0, "wheel_hand_w": 0.25,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 0.65,
            "grip_l": 0.35, "grip_r": 0.88,
            "bones": {
                "spine": (0.02, -0.16, 0.06), "chest": (-0.04, -0.22, 0.08),
                "neck": (0.04, 0.18, 0.0), "head": (0.04, 0.14, 0.0),
                "thigh_l": (hip_flex, 0.06, -0.08), "shin_l": (-knee_flex, 0.0, 0.0),
                "thigh_r": (hip_flex - 0.10, -0.18, 0.22), "shin_r": (-1.45, 0.0, 0.0),
                "upper_arm_l": (0.44, 0.0, -0.14), "forearm_l": (0.62, 0.0, 0.0),
                "upper_arm_r": (0.52, 0.0, 0.34), "forearm_r": (0.66, 0.0, 0.0),
            },
        }),
        # 0.38: Hips swivel outward toward doorway; right foot swings over sill & plants onto ground!
        (0.38, {
            "seat_t": 0.74, "yaw_t": 0.42, "door": 1.0,
            "hips_x": 0.0, "hips_y": -crouch * 0.45 + step_down * 0.25, "hips_z": 0.0, "duck": duck_amt * 0.88,
            "ext_hand_w": 0.0, "int_hand_w": 0.45, "brace_hand_w": brace_w * 0.6, "wheel_hand_w": 0.0,
            "foot_l_gnd": 0.15, "foot_r_gnd": 0.88, "foot_pedal_w": 0.10,
            "grip_l": 0.35, "grip_r": 0.65,
            "bones": {
                "spine": (-0.30 - 0.16 * duck_amt, -0.14, 0.06),
                "chest": (-0.24 - 0.14 * duck_amt, -0.16, 0.06),
                "neck": (-0.10 - 0.10 * duck_amt, 0.12, 0.0),
                "head": (-0.06, 0.10, 0.0),
                "thigh_r": (1.06, 0.0, 0.16), "shin_r": (-1.18, 0.0, 0.0), "foot_r": (0.12, 0.0, 0.0),
                "thigh_l": (1.24, 0.14, -0.18), "shin_l": (-1.48, 0.0, 0.0), "foot_l": (0.26, 0.0, 0.0),
                "upper_arm_l": (0.58, 0.0, -0.18), "forearm_l": (0.64, 0.0, 0.0),
                "upper_arm_r": (0.46, 0.0, 0.28), "forearm_r": (0.58, 0.0, 0.0),
            },
        }),
        # 0.58: Both feet firmly grounded; torso leans forward to clear roof & pushes upright!
        (0.58, {
            "seat_t": 0.24, "yaw_t": 0.14, "door": 0.96,
            "hips_x": 0.06, "hips_y": -crouch * 0.82, "hips_z": 0.04, "duck": duck_amt * 0.72,
            "ext_hand_w": 0.35, "int_hand_w": 0.0, "brace_hand_w": brace_w * 0.7, "wheel_hand_w": 0.0,
            "foot_l_gnd": 0.96, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.45, "grip_r": 0.30,
            "bones": {
                "spine": (-0.32 - 0.14 * duck_amt, 0.06, 0.0),
                "chest": (-0.24 - 0.12 * duck_amt, 0.08, 0.0),
                "neck": (0.12, -0.06, 0.0), "head": (0.10, -0.04, 0.0),
                "thigh_l": (0.64, 0.0, -0.08), "shin_l": (-0.84, 0.0, 0.0),
                "thigh_r": (0.56, 0.0, 0.08), "shin_r": (-0.74, 0.0, 0.0),
                "upper_arm_l": (0.48, 0.0, -0.18), "forearm_l": (0.54, 0.0, 0.0),
                "upper_arm_r": (0.36, 0.0, 0.16), "forearm_r": (0.44, 0.0, 0.0),
            },
        }),
        # 0.76: Standing upright outside, stepping slightly clear & swinging door shut with hand!
        (0.76, {
            "seat_t": 0.0, "yaw_t": 0.08, "door": 0.74,
            "hips_x": 0.10, "hips_y": -0.02, "hips_z": 0.06, "duck": 0.04,
            "ext_hand_w": 0.94, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.72, "grip_r": 0.12,
            "bones": {
                "spine": (-0.08, 0.12, 0.0), "chest": (-0.06, 0.16, 0.0),
                "neck": (0.04, -0.12, 0.0), "head": (0.03, -0.08, 0.0),
                "thigh_l": (0.12, 0.0, -0.05), "shin_l": (-0.18, 0.0, 0.0),
                "thigh_r": (0.08, 0.0, 0.05), "shin_r": (-0.14, 0.0, 0.0),
                "upper_arm_l": (0.58, 0.0, -0.16), "forearm_l": (0.52, 0.0, 0.0),
                "upper_arm_r": (0.10, 0.0, 0.10), "forearm_r": (0.26, 0.0, 0.0),
            },
        }),
        # 0.91: Door clicks shut; arm drops smoothly to side.
        (0.91, {
            "seat_t": 0.0, "yaw_t": 0.55, "door": 0.0,
            "hips_x": 0.03, "hips_y": 0.0, "hips_z": 0.02, "duck": 0.0,
            "ext_hand_w": 0.18, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.12, "grip_r": 0.08,
            "bones": {
                "spine": (-0.02, 0.04, 0.0), "chest": (-0.02, 0.04, 0.0),
                "upper_arm_l": (0.16, 0.0, -0.08), "forearm_l": (0.30, 0.0, 0.0),
                "upper_arm_r": (0.06, 0.0, 0.08), "forearm_r": (0.22, 0.0, 0.0),
            },
        }),
        # 1.00: Clean relaxed standing idle facing vehicle heading (seamless blend into locomotion!).
        (1.00, {
            "seat_t": 0.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.0, "grip_r": 0.0,
            "bones": {
                "upper_arm_l": (0.04, 0.0, -0.07), "forearm_l": (0.22, 0.0, 0.0),
                "upper_arm_r": (0.04, 0.0, 0.07), "forearm_r": (0.22, 0.0, 0.0),
            },
        }),
    ]


def _boat_enter_keys():
    """Step over boat gunwale from dock/quay and settle onto helm seat."""
    seated = _seated_bones(recline=0.05, hip_flex=1.32, knee_flex=1.26, arm_fwd=0.56, elbow=0.66)
    return [
        (0.00, {
            "seat_t": 0.0, "yaw_t": 0.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.20, "int_hand_w": 0.0, "brace_hand_w": 0.25, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.2, "grip_r": 0.2,
            "bones": {"spine": (-0.06, 0.0, 0.0), "upper_arm_r": (0.35, 0.0, 0.14), "forearm_r": (0.42, 0.0, 0.0)},
        }),
        # 0.22: Brace hand on gunwale rail, lift lead knee high over hull gunwale!
        (0.22, {
            "seat_t": 0.16, "yaw_t": 0.10, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.14, "hips_z": 0.0, "duck": 0.05,
            "ext_hand_w": 0.72, "int_hand_w": 0.0, "brace_hand_w": 0.82, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 0.0, "foot_pedal_w": 0.0,
            "grip_l": 0.75, "grip_r": 0.80,
            "bones": {
                "spine": (-0.20, -0.08, 0.06), "chest": (-0.14, -0.10, 0.06),
                "thigh_r": (1.36, -0.08, 0.20), "shin_r": (-1.52, 0.0, 0.0), "foot_r": (0.28, 0.0, 0.0),
                "thigh_l": (0.24, 0.0, -0.06), "shin_l": (-0.34, 0.0, 0.0),
                "upper_arm_l": (0.55, 0.0, -0.22), "forearm_l": (0.60, 0.0, 0.0),
                "upper_arm_r": (0.64, 0.0, 0.22), "forearm_r": (0.56, 0.0, 0.0),
            },
        }),
        # 0.50: Lead foot lands on boat deck; trailing leg lifts smoothly over gunwale!
        (0.50, {
            "seat_t": 0.62, "yaw_t": 0.48, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.18, "hips_z": 0.0, "duck": 0.05,
            "ext_hand_w": 0.35, "int_hand_w": 0.0, "brace_hand_w": 0.55, "wheel_hand_w": 0.25,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 0.45,
            "grip_l": 0.45, "grip_r": 0.60,
            "bones": {
                "spine": (-0.16, -0.12, -0.06), "chest": (-0.10, -0.10, -0.04),
                "thigh_r": (0.72, 0.0, 0.12), "shin_r": (-0.86, 0.0, 0.0),
                "thigh_l": (1.28, 0.12, -0.22), "shin_l": (-1.54, 0.0, 0.0),
                "upper_arm_l": (0.40, 0.0, -0.28), "forearm_l": (0.54, 0.0, 0.0),
                "upper_arm_r": (0.58, 0.0, 0.18), "forearm_r": (0.66, 0.0, 0.0),
            },
        }),
        # 0.78: Lower smoothly onto helm seat, turning forward to helm wheel!
        (0.78, {
            "seat_t": 0.96, "yaw_t": 0.94, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.02, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.88,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 0.92,
            "grip_l": 0.80, "grip_r": 0.82,
            "bones": seated,
        }),
        (1.00, {
            "seat_t": 1.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 1.0,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 1.0,
            "grip_l": 0.86, "grip_r": 0.86,
            "bones": seated,
        }),
    ]


def _boat_exit_keys():
    seated = _seated_bones(recline=0.05, hip_flex=1.32, knee_flex=1.26, arm_fwd=0.56, elbow=0.66)
    return [
        (0.00, {
            "seat_t": 1.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.90,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 1.0,
            "grip_l": 0.80, "grip_r": 0.80,
            "bones": seated,
        }),
        (0.28, {
            "seat_t": 0.72, "yaw_t": 0.50, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.16, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.35, "int_hand_w": 0.0, "brace_hand_w": 0.70, "wheel_hand_w": 0.0,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 0.30,
            "grip_l": 0.55, "grip_r": 0.65,
            "bones": {
                "spine": (-0.18, -0.10, 0.05), "chest": (-0.12, -0.10, 0.05),
                "thigh_r": (1.22, -0.06, 0.20), "shin_r": (-1.42, 0.0, 0.0),
                "thigh_l": (0.82, 0.0, -0.10), "shin_l": (-0.92, 0.0, 0.0),
                "upper_arm_l": (0.48, 0.0, -0.22), "forearm_l": (0.52, 0.0, 0.0),
                "upper_arm_r": (0.58, 0.0, 0.22), "forearm_r": (0.56, 0.0, 0.0),
            },
        }),
        (0.58, {
            "seat_t": 0.24, "yaw_t": 0.16, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.12, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.55, "int_hand_w": 0.0, "brace_hand_w": 0.45, "wheel_hand_w": 0.0,
            "foot_l_gnd": 0.30, "foot_r_gnd": 0.96, "foot_pedal_w": 0.0,
            "grip_l": 0.40, "grip_r": 0.35,
            "bones": {
                "spine": (-0.14, 0.04, 0.0), "chest": (-0.10, 0.04, 0.0),
                "thigh_r": (0.44, 0.0, 0.10), "shin_r": (-0.56, 0.0, 0.0),
                "thigh_l": (1.02, 0.0, -0.16), "shin_l": (-1.28, 0.0, 0.0),
                "upper_arm_l": (0.40, 0.0, -0.18), "forearm_l": (0.46, 0.0, 0.0),
                "upper_arm_r": (0.34, 0.0, 0.16), "forearm_r": (0.40, 0.0, 0.0),
            },
        }),
        (0.84, {
            "seat_t": 0.0, "yaw_t": 0.65, "door": 0.0,
            "hips_x": 0.0, "hips_y": -0.02, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.10, "grip_r": 0.10,
            "bones": {
                "spine": (-0.04, 0.0, 0.0),
                "upper_arm_l": (0.10, 0.0, -0.10), "forearm_l": (0.26, 0.0, 0.0),
                "upper_arm_r": (0.10, 0.0, 0.10), "forearm_r": (0.26, 0.0, 0.0),
            },
        }),
        (1.00, {
            "seat_t": 0.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.0, "grip_r": 0.0,
            "bones": {
                "upper_arm_l": (0.04, 0.0, -0.07), "forearm_l": (0.22, 0.0, 0.0),
                "upper_arm_r": (0.04, 0.0, 0.07), "forearm_r": (0.22, 0.0, 0.0),
            },
        }),
    ]


def _heli_enter_keys():
    """Crouched rotor-clearance approach, grab cabin frame, step up onto skid & into cockpit."""
    seated = _seated_bones(recline=0.04, hip_flex=1.38, knee_flex=1.34, arm_fwd=0.52, elbow=0.82)
    return [
        # Start slightly crouched under overhead rotor disc!
        (0.00, {
            "seat_t": 0.0, "yaw_t": 0.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": -0.09, "hips_z": 0.0, "duck": 0.42,
            "ext_hand_w": 0.25, "int_hand_w": 0.0, "brace_hand_w": 0.20, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.25, "grip_r": 0.25,
            "bones": {
                "spine": (-0.24, 0.04, 0.0), "chest": (-0.18, 0.06, 0.0),
                "neck": (0.14, 0.0, 0.0), "head": (0.10, 0.0, 0.0),
                "thigh_l": (0.26, 0.0, -0.05), "shin_l": (-0.42, 0.0, 0.0),
                "thigh_r": (0.26, 0.0, 0.05), "shin_r": (-0.42, 0.0, 0.0),
                "upper_arm_l": (0.45, 0.0, -0.14), "forearm_l": (0.50, 0.0, 0.0),
                "upper_arm_r": (0.32, 0.0, 0.14), "forearm_r": (0.44, 0.0, 0.0),
            },
        }),
        # 0.24: Grab cabin frame handhold, step right foot up onto landing skid!
        (0.24, {
            "seat_t": 0.18, "yaw_t": 0.12, "door": 0.85,
            "hips_x": 0.04, "hips_y": 0.06, "hips_z": 0.02, "duck": 0.58,
            "ext_hand_w": 0.88, "int_hand_w": 0.0, "brace_hand_w": 0.90, "wheel_hand_w": 0.0,
            "foot_l_gnd": 0.95, "foot_r_gnd": 0.0, "foot_pedal_w": 0.0,
            "grip_l": 0.90, "grip_r": 0.90,
            "bones": {
                "spine": (-0.30, -0.10, 0.05), "chest": (-0.22, -0.12, 0.05),
                "neck": (0.06, 0.10, 0.0), "head": (0.04, 0.08, 0.0),
                "thigh_r": (1.24, -0.06, 0.18), "shin_r": (-1.42, 0.0, 0.0),
                "thigh_l": (0.34, 0.0, -0.08), "shin_l": (-0.48, 0.0, 0.0),
                "upper_arm_l": (0.86, 0.0, -0.20), "forearm_l": (0.64, 0.0, 0.0),
                "upper_arm_r": (0.94, 0.0, 0.22), "forearm_r": (0.62, 0.0, 0.0),
            },
        }),
        # 0.52: Hoist body up & duck into cockpit; lead leg into rudder pedals!
        (0.52, {
            "seat_t": 0.66, "yaw_t": 0.54, "door": 0.96,
            "hips_x": 0.0, "hips_y": 0.14, "hips_z": 0.0, "duck": 0.62,
            "ext_hand_w": 0.15, "int_hand_w": 0.15, "brace_hand_w": 0.72, "wheel_hand_w": 0.22,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 0.52,
            "grip_l": 0.45, "grip_r": 0.75,
            "bones": {
                "spine": (-0.26, -0.14, 0.05), "chest": (-0.18, -0.14, 0.05),
                "neck": (-0.06, 0.12, 0.0), "head": (-0.04, 0.08, 0.0),
                "thigh_r": (1.36, 0.0, 0.12), "shin_r": (-1.36, 0.0, 0.0),
                "thigh_l": (1.30, 0.14, -0.20), "shin_l": (-1.52, 0.0, 0.0),
                "upper_arm_l": (0.58, 0.0, -0.26), "forearm_l": (0.66, 0.0, 0.0),
                "upper_arm_r": (0.72, 0.0, 0.20), "forearm_r": (0.76, 0.0, 0.0),
            },
        }),
        # 0.80: Seated at pilot controls; pull cockpit door closed; grip cyclic & collective!
        (0.80, {
            "seat_t": 0.98, "yaw_t": 0.96, "door": 0.30,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.08,
            "ext_hand_w": 0.0, "int_hand_w": 0.65, "brace_hand_w": 0.0, "wheel_hand_w": 0.72,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 0.96,
            "grip_l": 0.82, "grip_r": 0.86,
            "bones": seated,
        }),
        (1.00, {
            "seat_t": 1.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 1.0,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 1.0,
            "grip_l": 0.88, "grip_r": 0.88,
            "bones": seated,
        }),
    ]


def _heli_exit_keys():
    seated = _seated_bones(recline=0.04, hip_flex=1.38, knee_flex=1.34, arm_fwd=0.52, elbow=0.82)
    return [
        (0.00, {
            "seat_t": 1.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.25, "brace_hand_w": 0.0, "wheel_hand_w": 0.85,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 1.0,
            "grip_l": 0.80, "grip_r": 0.82,
            "bones": seated,
        }),
        (0.24, {
            "seat_t": 0.82, "yaw_t": 0.62, "door": 0.90,
            "hips_x": 0.0, "hips_y": 0.04, "hips_z": 0.0, "duck": 0.45,
            "ext_hand_w": 0.0, "int_hand_w": 0.80, "brace_hand_w": 0.65, "wheel_hand_w": 0.0,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 0.25,
            "grip_l": 0.55, "grip_r": 0.80,
            "bones": {
                "spine": (-0.24, -0.14, 0.06), "chest": (-0.18, -0.16, 0.06),
                "thigh_r": (1.16, -0.10, 0.20), "shin_r": (-1.34, 0.0, 0.0),
                "thigh_l": (1.28, 0.12, -0.18), "shin_l": (-1.48, 0.0, 0.0),
                "upper_arm_l": (0.60, 0.0, -0.20), "forearm_l": (0.64, 0.0, 0.0),
                "upper_arm_r": (0.58, 0.0, 0.30), "forearm_r": (0.62, 0.0, 0.0),
            },
        }),
        # 0.54: Step down from skid onto tarmac while keeping head ducked clear of rotor!
        (0.54, {
            "seat_t": 0.22, "yaw_t": 0.18, "door": 0.88,
            "hips_x": 0.06, "hips_y": -0.12, "hips_z": 0.04, "duck": 0.56,
            "ext_hand_w": 0.50, "int_hand_w": 0.0, "brace_hand_w": 0.60, "wheel_hand_w": 0.0,
            "foot_l_gnd": 0.72, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.50, "grip_r": 0.45,
            "bones": {
                "spine": (-0.30, 0.06, 0.0), "chest": (-0.22, 0.08, 0.0),
                "neck": (0.14, -0.06, 0.0), "head": (0.10, 0.0, 0.0),
                "thigh_l": (0.56, 0.0, -0.08), "shin_l": (-0.76, 0.0, 0.0),
                "thigh_r": (0.48, 0.0, 0.08), "shin_r": (-0.64, 0.0, 0.0),
                "upper_arm_l": (0.66, 0.0, -0.18), "forearm_l": (0.56, 0.0, 0.0),
                "upper_arm_r": (0.52, 0.0, 0.18), "forearm_r": (0.50, 0.0, 0.0),
            },
        }),
        (0.84, {
            "seat_t": 0.0, "yaw_t": 0.65, "door": 0.0,
            "hips_x": 0.02, "hips_y": -0.05, "hips_z": 0.02, "duck": 0.24,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.10, "grip_r": 0.10,
            "bones": {
                "spine": (-0.12, 0.0, 0.0), "chest": (-0.08, 0.0, 0.0),
                "upper_arm_l": (0.12, 0.0, -0.09), "forearm_l": (0.28, 0.0, 0.0),
                "upper_arm_r": (0.12, 0.0, 0.09), "forearm_r": (0.28, 0.0, 0.0),
            },
        }),
        (1.00, {
            "seat_t": 0.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.0,
            "foot_l_gnd": 1.0, "foot_r_gnd": 1.0, "foot_pedal_w": 0.0,
            "grip_l": 0.0, "grip_r": 0.0,
            "bones": {
                "upper_arm_l": (0.04, 0.0, -0.07), "forearm_l": (0.22, 0.0, 0.0),
                "upper_arm_r": (0.04, 0.0, 0.07), "forearm_r": (0.22, 0.0, 0.0),
            },
        }),
    ]


def _slide_across_keys():
    """Smooth across-the-console seat slide when entering from the passenger side
    because the driver's door was blocked by a wall or adjacent vehicle."""
    seated = _seated_bones(recline=0.08, hip_flex=1.42, knee_flex=1.36)
    return [
        (0.00, {
            "seat_t": 0.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.05,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.15,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 0.60,
            "grip_l": 0.35, "grip_r": 0.35,
            "bones": seated,
        }),
        # Mid-slide: slight hip lift over center console, torso leans toward driver side, legs tuck!
        (0.50, {
            "seat_t": 0.50, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.06, "hips_z": 0.02, "duck": 0.35,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 0.55,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 0.45,
            "grip_l": 0.55, "grip_r": 0.65,
            "bones": {
                "spine": (-0.18, -0.14, 0.12), "chest": (-0.14, -0.12, 0.10),
                "neck": (0.06, 0.12, -0.06), "head": (0.04, 0.10, -0.04),
                "thigh_l": (1.56, 0.14, -0.18), "shin_l": (-1.62, 0.0, 0.0),
                "thigh_r": (1.52, -0.14, 0.18), "shin_r": (-1.58, 0.0, 0.0),
                "upper_arm_l": (0.58, 0.0, -0.22), "forearm_l": (0.78, 0.0, 0.0),
                "upper_arm_r": (0.64, 0.0, 0.16), "forearm_r": (0.72, 0.0, 0.0),
            },
        }),
        (1.00, {
            "seat_t": 1.0, "yaw_t": 1.0, "door": 0.0,
            "hips_x": 0.0, "hips_y": 0.0, "hips_z": 0.0, "duck": 0.0,
            "ext_hand_w": 0.0, "int_hand_w": 0.0, "brace_hand_w": 0.0, "wheel_hand_w": 1.0,
            "foot_l_gnd": 0.0, "foot_r_gnd": 0.0, "foot_pedal_w": 1.0,
            "grip_l": 0.86, "grip_r": 0.86,
            "bones": seated,
        }),
    ]


def main():
    arm = _setup_scene()
    clips = {}

    # 1. Standard Saloon / Hatchback (Kestrel, Marlin, Scout)
    clips["saloon_enter"] = _bake_clip(arm, "saloon_enter", 1.72, _car_enter_keys(
        crouch=0.14, duck_amt=0.58, step_lift=0.05, lead_thigh=1.18,
        recline=0.09, hip_flex=1.42, knee_flex=1.36, brace_w=0.35, climb_up=0.0))
    clips["saloon_exit"] = _bake_clip(arm, "saloon_exit", 1.56, _car_exit_keys(
        crouch=0.14, duck_amt=0.58, recline=0.09, hip_flex=1.42, knee_flex=1.36, brace_w=0.35))

    # 2. Low-Roof Sports / Supercar / Hypercar (Brute, Vanta, Halcyon, Stiletto)
    clips["sports_enter"] = _bake_clip(arm, "sports_enter", 1.82, _car_enter_keys(
        crouch=0.23, duck_amt=0.88, step_lift=0.03, lead_thigh=1.28,
        recline=0.17, hip_flex=1.50, knee_flex=1.22, brace_w=0.68, climb_up=0.0))
    clips["sports_exit"] = _bake_clip(arm, "sports_exit", 1.66, _car_exit_keys(
        crouch=0.23, duck_amt=0.88, recline=0.17, hip_flex=1.50, knee_flex=1.22, brace_w=0.68))

    # 3. High-Cab SUV / Pickup / Van / Box Truck (Goliath, Warden, Van, Box, Mammoth)
    clips["high_cab_enter"] = _bake_clip(arm, "high_cab_enter", 1.86, _car_enter_keys(
        crouch=0.06, duck_amt=0.36, step_lift=0.14, lead_thigh=1.34,
        recline=0.04, hip_flex=1.34, knee_flex=1.44, brace_w=0.92, climb_up=0.18))
    clips["high_cab_exit"] = _bake_clip(arm, "high_cab_exit", 1.68, _car_exit_keys(
        crouch=0.08, duck_amt=0.34, recline=0.04, hip_flex=1.34, knee_flex=1.44, brace_w=0.88, step_down=0.16))

    # 4. Boat (Dart, Swift, Majesty)
    clips["boat_enter"] = _bake_clip(arm, "boat_enter", 1.58, _boat_enter_keys())
    clips["boat_exit"] = _bake_clip(arm, "boat_exit", 1.48, _boat_exit_keys())

    # 5. Helicopter (Wren, Kite, Regent)
    clips["heli_enter"] = _bake_clip(arm, "heli_enter", 1.80, _heli_enter_keys())
    clips["heli_exit"] = _bake_clip(arm, "heli_exit", 1.62, _heli_exit_keys())

    # 6. Aircraft / Plane (Skylark, Merlin, Aurora) — step up onto wing/stair + duck into cockpit
    clips["plane_enter"] = _bake_clip(arm, "plane_enter", 1.84, _car_enter_keys(
        crouch=0.10, duck_amt=0.72, step_lift=0.14, lead_thigh=1.30,
        recline=0.08, hip_flex=1.40, knee_flex=1.34, brace_w=0.86, climb_up=0.16))
    clips["plane_exit"] = _bake_clip(arm, "plane_exit", 1.66, _car_exit_keys(
        crouch=0.12, duck_amt=0.72, recline=0.08, hip_flex=1.40, knee_flex=1.34, brace_w=0.82, step_down=0.14))

    # 7. Passenger-to-Driver Across-Seat Slide (when primary side is blocked!)
    clips["slide_across"] = _bake_clip(arm, "slide_across", 0.72, _slide_across_keys())

    # 8. Seated Driving / Piloting Base Postures (layered with live steering wheel / pedal / g-force IK)
    driving_bases = {
        "saloon": _seated_bones(recline=0.09, hip_flex=1.42, knee_flex=1.36, spread=0.09, arm_fwd=0.58, elbow=0.70),
        "sports": _seated_bones(recline=0.17, hip_flex=1.50, knee_flex=1.22, spread=0.10, arm_fwd=0.64, elbow=0.62),
        "high_cab": _seated_bones(recline=0.04, hip_flex=1.34, knee_flex=1.44, spread=0.11, arm_fwd=0.52, elbow=0.76),
        "boat": _seated_bones(recline=0.05, hip_flex=1.32, knee_flex=1.26, spread=0.12, arm_fwd=0.56, elbow=0.66),
        "heli": _seated_bones(recline=0.04, hip_flex=1.38, knee_flex=1.34, spread=0.12, arm_fwd=0.52, elbow=0.82),
        "plane": _seated_bones(recline=0.08, hip_flex=1.40, knee_flex=1.34, spread=0.10, arm_fwd=0.56, elbow=0.72),
    }
    driving_json = {
        k: {b: [round(x, 4) for x in v] for b, v in pose.items()}
        for k, pose in driving_bases.items()
    }

    payload = {
        "_doc": "Baked Blender Bezier F-curve vehicle interaction clips (tools/blender/build_vehicle_anims.py).",
        "clips": clips,
        "driving": driving_json,
    }
    OUT_JSON.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
    OUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND))
    print(f"VEHICLE ANIMS BAKED: {len(clips)} clips, {len(driving_json)} driving postures -> {OUT_JSON} ({OUT_JSON.stat().st_size} bytes)", flush=True)


if __name__ == "__main__":
    main()
