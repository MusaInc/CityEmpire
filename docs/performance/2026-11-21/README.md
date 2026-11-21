# WorldState streaming and rendering pass — 21 November 2026

Implementation commit: `4a3f1b9`. Source baseline: `48ebb6d`, plus the 17 shader edits already present when this pass began. Those shader edits were preserved, not authored or committed by this pass. All visual captures use that working-tree shader state. Gameplay features, quality presets, texture resolutions and traffic/crowd counts are retained.

## Implemented

- Moved deterministic pedestrian placement, terrain sampling and packed MultiMesh buffer generation into the existing chunk worker tasks. The main thread now only creates and uploads the instances. A worker/main-thread equivalence check protects placement and counts.
- Cached deterministic parked-car layouts already generated for collision at startup. Streamed visuals and wreck queries reuse them; broken cars are filtered at read time and callers receive independent working lists. Restoring a wreck does not regenerate the layout.
- Preloaded the existing near-tree mesh cache under the loading screen, preventing first-use loads during exploration. This moves work, rather than eliminating it or reducing tree quality.
- FarCity now uploads at most two chunks per frame with a 2 ms soft CPU budget, releasing generation arrays as uploads complete. `finish()` still drains synchronously for captures/teleports. A single upload can exceed the soft budget; this is not a hard real-time guarantee.
- Linked building and structure LODs through Godot visibility dependencies. The low mesh owns the transition and hysteresis, preventing independent bounds from producing overlapping facades or gaps. Skyport's explicit 20 m overlap is removed; its skyline remains available until each district's detail exists, and returns when detail unloads.
- Prevented rectangular occluders from covering rounded/notched building cutouts. Raised-building occluders start inside their actual bottom tier instead of extending to world height zero. This conservatively trades some occlusion efficiency for correct visibility.
- Included Westbank traffic in the existing 14-body collision pool and crash conversion. Traffic IDs are scoped to their originating Traffic instance, so converting or releasing car 0 on one island cannot affect car 0 on the other. Both cities brake for wrecks. Stale Skyport bodies are parked when its traffic unloads.
- Removed camera sweep minimum-distance clamps that could place the lens beyond a nearby wall. Chase/orbit and walking sweeps now respect the safe fraction. A real physics close-wall regression reproduces the chase-camera case.
- Reset adaptive-resolution samples on settings changes, pauses and large resume intervals. Disabled governors no longer request GPU timing. Existing MetalFX/bilinear selection and resolution caps remain intact.
- Added opt-in section timing (`--profile-world`) and wall-clock frame p50/p95/p99/max to `--perf`. The old FPS field is now explicitly `sim_fps`: fixed simulation timing is not a device benchmark. Section reports now show total, mean-per-call and peak; nested sections must not be summed.

## Measured CPU result

Godot 4.5.1, Linux headless/dummy renderer, default new-game Westbank spawn, quality 1, `--fixed-fps 30 -- --new --quality=1 --perf=1 --profile-world`. One second sampled after three simulation seconds of warm-up. Section timing includes startup/warm-up; compare per-call peaks rather than the old misleading `ms/frame` denominator. Baseline and optimized runs instantiated 36 and 37 chunks respectively because worker completion is asynchronous. These are short diagnostic samples, not sustained performance acceptance.

| Main-thread section | Before peak | After peak |
| --- | ---: | ---: |
| Complete chunk creation/upload | 17.822 ms | 6.804 ms |
| Pedestrian placement/upload | 5.367 ms | 0.088 ms |
| Parked traffic placement/upload | 2.459 ms | 0.358 ms |
| Props | 9.561 ms | 2.481 ms |
| Far-city upload batch | 6.574 ms | 0.514 ms |

Logs: [before](cpu-before.log), [after](cpu-after.log). Chunk peak decreased approximately **62%**. Far-city batches decreased approximately **92%**, by spreading work over frames rather than reducing world content. Approximate mean chunk cost from totals/counts: 5.99 → 1.85 ms. Headless process-monitor averages were 22.77 → 13.20 ms; scheduling and the short sample limit this comparison. The optimized wall-clock sample was p50 8.83 / p95 13.08 / p99 15.31 ms. No baseline wall-clock percentiles were recorded, so no percentile improvement is claimed.

No iPhone/iPad FPS, GPU time, battery, thermal or device memory improvement is claimed. Headless memory was approximately 782 → 786 MB; caching was not a memory-saving result.

## Visual and targeted checks

- [Westbank before](street-before.png) / [after](street-after.png), 960×540, native new-game camera. Shopfront, character, nearby trees and geometry preserved. Draw calls 377 → 378; triangles 1,094,077 → 1,100,546. This is not a demonstrated draw-call reduction in this view. Texture memory stayed 96 MB; reported video memory 322.3 → 320 MB. Streaming completion differs slightly; don't interpret these as sustained memory gains.
- [Skyport after](skyport-after.png), 960×720 (tablet aspect), noon, penthouse loaded, fixed camera `--cam=-650,100,1250,-200,20,1450`. Airport, buildings, roads and distant terrain inspected. A fixed staging view, not a touch-play session.
- [Commercial Island after](east-street-after.png), 1200×540 (wide phone aspect), noon, normal gameplay camera at `--goto=wholesale:east`. Street, character, collection bay, pedestrians and traffic inspected; this is a staged teleport, not a complete island traversal.
- Rendered LOD sweep: 8 → 10 → 12 → 10 → 8 m, deliberately different AABB centres; **one draw at every step**, no double-draw/gap. [Log](lod.log), reproducible with `tools/worldstate_lod_probe.gd` on a rendered Godot instance.
- [Targeted regressions](tests.log): bounded far uploads/finish, worker placement equivalence, two-island pooled collision ownership, conservative occluder extents, parked-cache removal/restore, close-wall camera, and resolution-governor resume sampling.

Commands (use an isolated `XDG_DATA_HOME` to protect real saves):

```sh
godot --headless --path . -s tests/run_tests.gd -- test_worldstate_render
godot --headless --path . --fixed-fps 30 -- --new --quality=1 --perf=1 --profile-world
godot --path . -s tools/worldstate_lod_probe.gd
godot --path . --resolution 960x540 --fixed-fps 30 -- --new --quality=1 --nohud --stats --shot=/tmp/street.png --shot-at=0.5
```

## Remaining before release acceptance

- Massive grey-wall reports have not been reproduced in normal gameplay during this pass. An exploratory fixed-camera Commercial Island capture put the camera inside existing geometry and was rejected; it is not evidence of a normal gameplay bug or a fix. The close-wall camera and occluder corrections address proven defects but do not establish that every wall/flicker report is resolved.
- Validate physical iPhone/iPad Metal builds: actual touch driving/walking, both bridges, rapid camera turns at LOD boundaries, vehicle collisions on each island, background/resume, and sustained thermal/frame-pacing/memory behavior. No Apple build or TestFlight upload was performed here.
- Startup and Skyport's coarse near-content construction steps remain potential hitch sources. This pass measures and improves city chunk commits; it does not claim every loading stage is asynchronous or within 2 ms.
- Existing ObjectDB/resource/PagedAllocator warnings at game shutdown remain. They occurred before and after these changes; no sustained leak or crash was established.
- Existing ASTC/ETC2 import configuration, compressed PBR textures/mipmaps, traffic LODs, GPU instancing and collision pooling were retained. Additional pooling, global texture cuts, broader physics rewrites or render-quality reductions were not justified by these measurements.

## Technique references

Godot's [3D optimization guidance](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html), [visibility dependencies/HLOD](https://docs.godotengine.org/en/4.5/tutorials/3d/visibility_ranges.html), [MultiMesh batching and culling limits](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html), and [occlusion culling](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html). Applied selectively to measured work and confirmed geometry/collision defects; no feature checklist was used as a reason to add another rendering system.
