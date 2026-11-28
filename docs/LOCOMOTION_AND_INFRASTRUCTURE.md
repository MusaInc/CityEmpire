# WorldState — Locomotion & Architectural Infrastructure Guide

## 1. Procedural Locomotion Architecture (`Gait` + `CharacterRig` + `SwingPhysics`)

WorldState uses a lightweight, mobile-first procedural locomotion stack tailored to iOS frame-rate and memory budgets (zero motion-matching database bloat, zero per-frame allocations on the hot path):

| Layer | File | Responsibility |
|---|---|---|
| **Movement Physics** | `src/physics/swing_physics.gd` | Deterministic `_everyday_move` analogue walk→jog→sprint speed curve, momentum-preserving cornering, braking reversals, indoor precision caps. |
| **Input & Camera** | `src/empire/ui/empire_touch.gd`, `src/player/player.gd`, `src/camera/swing_camera.gd` | Rescaled radial stick deadzone (`0.08..1.0` → `0..1`, `pow(mag, 1.22)`), doorway steering assist, smooth step-height & elevator/indoor camera framing. |
| **World-Space Foot Placement** | `src/player/gait.gd` | Speed-matched cadence, dual front/back reach-clamped duty factor (prevents foot skating & mid-stance over-extension), continuous heel-to-toe rocker, smooth rate-limited toe-off, braking plant & turn-in-place settle steps, `body_type` & `heel_pitch` stride adaptation. |
| **Full-Body Kinematics & Idle** | `src/player/character_rig.gd` | Analytical 2-bone leg/arm IK (`_two_bone`), double-knee loading-response cushion, pelvis vaulting/list/shift, counter-rotating spine/chest/clavicles, pendular forearm lag, forward running lean, turn banking, slope lean, relaxed hands/fingers, breathing/weight-shift/gaze/blink idle life, smoothed `_hip_drop` across stairs & kerbs. |
| **Pedestrians** | `src/empire/npc/crowd.gd`, `src/world/shaders/person_pose.gdshaderinc` | GPU vertex-shader locomotion for MultiMesh crowds with heel-to-toe rollover, loading-response knee bend, forearm lag, per-person `seed` desynchronization (cadence, posture, arm vigour), smoothed slope ground tracking, and distance-based simulation LOD (1/2/3-frame ticks). |

### Reusable Tooling & Cross-Game Compounding
- **Locomotion Lab (`tools/locomotion_lab.gd`)** & **Video/Sheet Packer (`tools/locomotion_review.py`)**: Scripted gameplay-faithful capture of real-time (30fps) + slow-motion (0.35x) MP4s, contact sheets, and quantitative metrics (`slide_avg`, `slide_max`, `snap`, `pops`, `sink`, `float`, `joint_bad`, `bob_mm`) across flat ground, slopes, stairs, turns, circles, starts/stops, and interiors.
- **Reusability across Musa Studios titles**:
  - **CitySwing**: Shares `Gait`, `CharacterRig`, and `SwingPhysics` directly; the dual-reach duty clamp, continuous heel-strike touchdown, and normalized pivot axes eliminate jog/sprint skating and knee snaps without affecting web-swinging feel.
  - **NEVER STOP**: Shares `EmpireTouch` analogue stick/pad curves and pedestrian `Crowd` shader upgrades for street-level atmosphere.
  - **Motion Sports & future titles**: `Gait` foot-locking + `CharacterRig._two_bone` + `tools/locomotion_lab.gd` form a drop-in bipedal locomotion & regression-testing harness.

---

## 2. Modular Architectural Infrastructure (`SkyportKit` + `InfraKit`)

All elevated transit structures, access towers, skywalks, station platforms, and viaduct/bridge undersides share GPU-instanced modular Blender meshes (`tools/blender/build_skyport.py` → `assets/models/skyport_kit.glb`, zero extra textures, vertex-coloured concrete/steel/luminaires + `kit_glass` glazing):

- **`transit_pavilion_base` / `transit_pavilion_bay` / `transit_pavilion_crown`** (`InfraKit.pavilion`): Grounded granite plinth with street-level entrance canopy, stacked glazed curtain-wall storeys with structural dark steel corner piers & architectural concrete lift core, and cantilevered roof crown with recessed warm soffit luminaires. Replaces skeletal staircase scaffolding and plain monolith boxes across City Loop stations, Westbank Quay, Airport Rail stations, and Skyport Link stations.
- **`skywalk_bay`** (`InfraKit.skywalk`): Enclosed glazed pedestrian footbridge with deep underside structural box girder, vertical steel mullions, handrails, and integrated roof canopy + ceiling luminaires, supported by intermediate `InfraKit.pier` columns on long spans (>14 m).
- **`platform_bracket`** (`InfraKit.platform_brackets`): Sculpted tapered cantilevered support ribs tying elevated station platforms into central viaduct box girders across City Loop, Airport Rail, and Skyport Link.
- **`deck_girders` + `underpass_lamp` + `pier_*`** (`InfraKit.girders`, `InfraKit.pier`, `InfraKit.portal`): Flanged box/I-girders, warm underpass luminaires, and chamfered octagonal piers with grounded footings applied consistently across City Loop viaducts, the Island Bridge landing, Airport Rail, and Skyport Link.
