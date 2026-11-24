# WorldState 0.11.1 Mobile refinement

Production checkpoint `checkpoint-worldstate-mobile-49` points to `a5c1120`.
Production uses Godot 4.5.1 Mobile with an arm64 iPhone and iPad export and
iOS 15 deployment target. Forward+ remains in the separate rendering lab.

## Cabin and materials

Blender sampled the exported roof along the driver's head travel, including
the width and depth of the crown. The Stiletto's measured skin height is
1.015–1.057 m. Its old 0.51 m pelvis anchor combined with a largely upright
rig to put the crown near 1.35 m in gameplay. The new pose and boarding path
use the measured cabin envelope and the active rig proportions. Footwell
and wheel targets drive lower- and upper-limb IK. Access pins the vehicle
and owns controls until the player has entered or exited.

The Stiletto's closed and split GLBs contain no texture maps or vertex
colors for the affected paint. Dark lines persist in the controlled Godot
capture when the runtime paint shader is replaced with constant PBR. The
Python source created a pair of dark bonnet strips and painted-width
35 mm louvres using a separate projection surface. The rebuilt mid-engine
assets keep physical intakes, window seals and narrow panel joints. They
omit cosmetic bonnet strips and use formed extractors. Runtime paint
also drops extra normal-based albedo darkening and the synthetic clearcoat
horizon band. Closed, split and Halcyon traffic tiers were regenerated.
The owned Courier Van has a modeled, clear-glazed cab and working door
meshes. The saved vehicle ID, cargo and driving inputs persist.

## City and performance

Street and island materials blend the original WorldState detail with
existing CC0 scans. They use one compressed mipmapped detail texture per
material. Road ponding mainly alters roughness and specular response.
Roadside lighting uses shorter attenuation ranges and reduced nighttime
ambient exposure. Car lights use one dipped spotlight and smaller glows.
Regenerated Blender furniture and the shared bridge and viaduct soffit
geometry reuse the existing mesh batches. The added structural details
have no collision bodies.

Crowd threat evaluation is staggered and altitude-aware. It looks for
traffic trajectories, strong impacts, active sirens and nearby alarm.
Pedestrians choose available routes on their sidewalk path, vary their
reaction time, run and recover. Streaming prioritizes a predicted corridor
using speed, local road direction and camera direction. Chunk requests and
uploads remain capped. The driving lens samples the centre at native UVs
and runs before the interface.

## Verification

Run `tools/visual/refinement_review.tscn` with `--play --new --seed=1
--quality=1 --touch --fixedscale --review-out=<absolute path>`. Run the
same visual mode at the checkpoint for a matched comparison. Headless
`--review-poses` in the refined checkout exercises both player rigs,
cabin clearance, both sides of Stiletto entry and exit, and crowd reactions.
See the screenshot review for measured frame time, draw calls and
video allocation on the Linux Vulkan software renderer. iPhone and iPad
performance and thermal behavior require hardware.
