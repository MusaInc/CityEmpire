# WorldState rendering lab

The Mobile overhaul is `a5c1120`. This worktree branches from that exact game. It keeps the bundle identifier `com.musastudios.cityempire`, file locations, save format, controls and assets. The experimental title says **Forward+ Preview** and its TestFlight archive is marked **Internal Testing Only**. TestFlight's **Previous Builds** switches between the two builds through the same app record.

## What the renderer changes

The production workflow pins the official Godot **4.5.1 stable** editor and export templates and selects Xcode 26. The Linux review machine reports `f62fdbde1`, Vulkan 1.4.305 and llvmpipe. Production requests Mobile on iPhone and iPad, uses ARM64, and has a preset minimum OS of 15.0. Godot 4.5.1 defaults to native Metal on iOS when available. An App Store deployment target and a renderer's Apple hardware and OS requirements are separate. The preview explicitly requests native Metal, Forward+, iOS 16.0, and the A12 capability. Recent iPads with M-series chips and recent iPhones are the intended devices for the Quality preset. [Godot renderer requirements](https://docs.godotengine.org/en/4.5/about/system_requirements.html) · [Godot driver configuration](https://docs.godotengine.org/en/4.5/classes/class_projectsettings.html#class-projectsettings-property-rendering-rendering-device-driver-ios)

| Effect | Mobile production | Forward+ preview |
| --- | --- | --- |
| Indirect light | Sky ambient, hand-tuned room lighting, contact shading. LightmapGI and local probes are supported. | Half-resolution SSIL in Quality. SDFGI is isolated in GI study so its update cost, leaking and streaming response can be evaluated. |
| Contact shadows | Procedural and asset AO, plus dynamic sun and lamp shadows. | SSAO in Balanced, Quality and GI study. |
| Reflections | Authored and procedural skyline, wet-road and car reflections. Hybrid tests one box-projected room probe. | SSR on wet streets or indoors in Quality and GI study. Transparent water and glass still need their existing reflection fallback. |
| Atmosphere | Height and depth fog, rain streaks and local lamps. | Short-range volumetrics in rainy or foggy conditions with smaller froxel buffers. |
| Skin | Wrapped diffuse lighting and shader backlight. | A low-strength SSS contribution on existing hero skin in native Metal Quality and GI study. The software review uses the wrapped diffuse skin path. |
| Shadows | Two directional cascades and selected local lights. | Four cascades in Quality and GI study, retaining the near cascade. |
| Antialiasing | MSAA or FXAA. MetalFX spatial when available. | MetalFX temporal where the device supports it, with spatial fallback. FSR2 for non-Metal Forward+ tests. The advanced spatial path uses FXAA to avoid MSAA resolve artifacts. The temporal path uses its own antialiasing. |

[Godot renderer comparison](https://docs.godotengine.org/en/4.5/tutorials/rendering/renderers.html) · [Godot viewport scaling modes](https://docs.godotengine.org/en/4.5/classes/class_viewport.html#enum-viewport-scaling3dmode)

## MetalFX and dynamic resolution

**Settings → Rendering Lab** shows the renderer and driver in use. **Auto**, **Spatial** and **Temporal** choose a preference. The resolved mode appears separately, since temporal support depends on the Metal device. Rendering runs below native resolution where appropriate, with the UI at native resolution. The existing governor uses measured GPU time where available, lowers resolution slowly under sustained load and restores it with hysteresis. The temporal path respects Godot's device-reported minimum input scale.

Godot 4.5.1 exposes spatial and temporal upscaling. Apple's newer MetalFX features, including dynamic input textures and frame interpolation, are separate capabilities and are outside this preview. Temporal quality also depends on good motion vectors. GPU-driven trees, pedestrians, rain, traffic and transparent surfaces deserve a dedicated ghosting check when the camera moves. [Apple MetalFX](https://developer.apple.com/documentation/metalfx) · [WWDC MetalFX dynamic input sizes](https://developer.apple.com/videos/play/wwdc2025/211/)

## Mobile hybrid lighting

The Hybrid profile captures one static interior shell into a box-projected ReflectionProbe when the player is in that room. The capture mask excludes the city, traffic, hero and glass. Direct lighting and the existing ambient settings continue to run. This exercises a Mobile-compatible reflection technique without a city-wide live cubemap.

LightmapGI is viable for fixed room shells and permanent architectural lighting. The city meshes generate and stream at runtime, and some materials already use UV2 as encoded facade data, so a city-wide bake would require a dedicated geometry and UV pipeline. An indoor static bake would need stable UV2 charts, a separate fixture layout, and direct lights for doors, players, changing shop fittings and the sun. Test its memory and lighting seams per fixed room before applying it to the city.

## What Glacier demonstrates

IO Interactive's iOS port describes a new native Metal backend, pass merging for Apple tile memory, carefully tracked compute dependencies, pooled resources, pipeline-state warmup, and native-resolution UI over MetalFX. The engineers reported spatial oversharpening and temporal softness at low input resolution. They also found that downclocking can hide savings in frame-time-only tests. This points to measuring pass bandwidth, thermal stability and cold-start hitches as well as image quality.

Godot Mobile blocks several effects WorldState can experiment with in Forward+. The Hitman comparison also includes differences in asset authoring, material detail, lighting design and production tooling. IO Interactive's desktop ray-tracing papers describe Glacier features on those configurations. IO Interactive's iOS rendering presentation documents a separate set of mobile techniques. [IO Interactive's iOS rendering slides](https://static.graphicsprogrammingconference.com/public/2025/talks/bringing-hitman-to-your-pocket/Catana-Bastian-bringing-hitman-to-your-pocket.pdf) · [Glacier engine](https://ioi.dk/glacier) · [Hitman 3 desktop ray tracing](https://media.gdcvault.com/GDC%2B2022/Speaker%2BSlides/RealTimeRayTracing_DalCorso_Alessandro.pdf)

## A/B procedure

The capture tool `tools/rendering/compare.gd` sets a fixed seed, render scale, camera paths, clock, weather, shop inventory and car input. Use `--rendering-method mobile --lab-profile=reference` and `--rendering-method forward_plus --lab-profile=quality` with the same resolution and the same other arguments. Use `--lab-profile=hybrid --lab-scenes=interior` on Mobile for the third interior capture. The log records GPU timer availability, draw calls, primitives, memory counters, renderer, driver and software frame percentiles. Vulkan llvmpipe results are useful for reproducible pictures, feature checks and submitted geometry. iPad performance requires Metal hardware.

For a device comparison, use the same saved location and graphics quality on each build. Enable **Show performance overlay** in the preview, return to gameplay and collect samples after camera settling. Use **Copy last sample** to retain the latest metrics and use Apple's Metal Performance HUD on both builds for matched Metal GPU timing, resolution and memory. Compare cold launch, repeated runs at the same temperature, and a sustained drive. Apple's Instruments and Xcode GPU capture show pass timing and bandwidth. 60 Hz gives a 16.7 ms frame budget and 30 Hz gives 33.3 ms. [Apple Metal Performance HUD metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics) · [Apple GPU workload capture](https://developer.apple.com/documentation/xcode/capturing-a-metal-workload-in-xcode) · [TestFlight Previous Builds](https://testflight.apple.com/)
