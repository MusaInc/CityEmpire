# WorldState vehicle texture report

**Project** · `/home/abdul/workspace/projects/CityEmpire` · WorldState 0.11.9 checkout · Git HEAD `2b3af61` · 2026-11-24

**Finding.** The 91 vehicle GLBs under `assets/` contain **zero embedded images, zero external image references and zero material texture bindings**. Their visual detail comes from modeled parts, material factors, vertex colors on procedural meshes and shader math. There are no dedicated vehicle body, cabin, tyre, wheel, glass, lamp or trim image resolutions to report. A small set of procedural scenery vehicles inherits shared world images, and several textures carry runtime positioning or effects data. Those are listed below with their dimensions.

**Scope and method.** Compared the owned catalogue, road traffic, police, damage swaps and showrooms with the aircraft, marine, rail, warehouse and airport dressing code. Parsed the binary glTF manifests and mesh accessors for all 91 vehicle GLBs under `assets/`, the 10 craft design copies and 13 venue GLBs checked for attached exhibits. Inspected the vehicle import sidecars, material assignment code and shader samplers. A Godot 4.5.1 headless check loaded all 91 model scenes, inspected 1,676 imported surfaces and confirmed zero bound material textures. The same check measured the generated traffic data textures on the default layout (seed 1207). Appearance, UV overlap, texel density and GPU performance were not measured in a rendered playthrough. The only project file produced by the assessment is this report.

## 1. Paths and source ownership

All paths in backticks are exact project-relative paths unless they begin with `res://`, which identifies the same file through Godot. A GLB row identifies its imported Godot materials by **GLB path plus material name**. The paired import file is the exact GLB path with `.import` appended. All 91 sidecars use `materials/extract=0` and empty subresource overrides, so there are no extracted vehicle `.tres` paths. Godot imports the embedded glTF material factors as `StandardMaterial3D`. The runtime owners below identify where those materials are kept, duplicated or overridden.

No vehicle model `.blend` was found in this checkout or in the repository's locally available Git history. The Blender Python sources in the tables are the editable project-side sources where present. `art/hero/courier.blend` and `art/hero/courier_b.blend` are character scenes. `tools/blender/build_vehicle_anims.py` names `art/hero/vehicle_anims.blend` as an animation authoring output, absent from this checkout. That output concerns character interactions. The Courier Van comment in `src/empire/empire_game.gd` names `tools/blender/build_player_cars.py`, which is absent. The present `tools/blender/ws_cars.py` defines and exports `courier_van` and `civ_box`.

### Road roster and default wheels

Owned IDs and display names come from `config/empire/vehicles.json`. Default physical wheel fits come from `src/vehicle/car_catalog.gd` and `src/empire/empire_game.gd`. The full-size body path is listed for each car, including those that share a body. The detailed material and UV inventory follows in section 5.

| Vehicle or role | Full body path | Default physical wheel or traffic fit |
|---|---|---|
| Kestrel Hatch (`hatch`) and Kestrel Hatch (used) (`used_kestrel`) | `assets/vehicles/kestrel.glb` | `assets/vehicles/wheel_kestrel.glb` |
| Courier Van (`van`) | `assets/vehicles/courier_van.glb` | `assets/vehicles/wheel_steel.glb` |
| Box Truck (`box`) | `assets/vehicles/civ_box.glb` | `assets/vehicles/wheel_steel.glb` |
| Marlin Saloon (`saloon`) | `assets/vehicles/marlin.glb` | `assets/vehicles/wheel_multi.glb` |
| Scout RS (`scout`) | `assets/vehicles/scout.glb` | `assets/vehicles/wheel_rally.glb` |
| Brute V8 (`brute`) | `assets/vehicles/brute.glb` | `assets/vehicles/wheel_dish.glb` |
| Vanta GT (`vanta`) | `assets/vehicles/vanta.glb` | `assets/vehicles/wheel_y5.glb` |
| Goliath Pickup (`goliath`) | `assets/vehicles/goliath.glb` | `assets/vehicles/wheel_offroad.glb` |
| Warden 4x4 (`warden`) | `assets/vehicles/warden.glb` | `assets/vehicles/wheel_offroad.glb` |
| Halcyon Supercar (`halcyon`) and Stiletto Hypercar (`stiletto`) | `assets/vehicles/halcyon.glb`, `assets/vehicles/stiletto.glb` | `assets/vehicles/wheel_center.glb` |
| Pursuit Patrol | `assets/vehicles/police_patrol.glb` | `assets/vehicles/wheel_steel.glb` |
| Pursuit Interceptor | `assets/vehicles/police_interceptor.glb` | `assets/vehicles/wheel_y5.glb` |
| Police Heavy Unit, available through the body/capture path | `assets/vehicles/police_heavy.glb` | `assets/vehicles/wheel_offroad.glb` |
| Mammoth heavy truck, available through the body/capture path | `assets/vehicles/mammoth.glb` | `assets/vehicles/wheel_steel.glb` |
| Civilian sedan, compact, SUV, taxi and van | `assets/vehicles/civ_sedan.glb`, `assets/vehicles/civ_compact.glb`, `assets/vehicles/civ_suv.glb`, `assets/vehicles/civ_taxi.glb`, `assets/vehicles/civ_van.glb` | Near `assets/vehicles/wheel_traffic.glb`, mid procedural, physical civilian specification uses steel |
| Civilian police and ambulance traffic | `assets/vehicles/civ_police.glb`, `assets/vehicles/civ_ambulance.glb` | Near `assets/vehicles/wheel_traffic.glb`, mid procedural |
| Civilian bus, catalog/body/capture asset | `assets/vehicles/civ_bus.glb` | `assets/vehicles/wheel_steel.glb` |

`src/world/city_world.gd` (`CAR_KINDS`) selects the seven civilian/emergency traffic bodies listed above, plus Kestrel, Marlin, Scout, Warden, Goliath, Vanta, Brute and Halcyon. The eight latter bodies have separate near and mid files. The seven civilian near models use their base file and have separate mid files. The far band is generated by `CityWorld._car_far_mesh`. Skyport road traffic uses the mid band. The airport surface lot uses the first three city kinds in mid and far bands. `src/shared/street_pursuit.gd` spawns Patrol and Interceptor. Mammoth, Heavy Unit and the bus are included because the project can instantiate their full bodies. The current WorldState owned catalogue and city traffic list give them no default fleet slot. Delivery cutscenes use `assets/models/car_van.glb` with its imported material slots. Traffic collisions can swap to a physical `CarVisual` body through `src/empire/world/wrecks.gd`.

### Aircraft and boat roster

Godot loads `assets/craft/` for the nine owned craft and the Skyport airliner. The editable generator for each is `tools/blender/build_craft.py`. The matching design GLBs in the table are byte-identical copies of the runtime GLBs. Craft use `src/vehicle/craft_models.gd`; the owned catalogue and visual spawns also pass through `src/empire/skyport_play.gd`.

| Vehicle | Runtime model | Blender design export |
|---|---|---|
| Wren H1 helicopter | `assets/craft/wren.glb` | `art/design/craft/wren.glb` |
| Kite T4 helicopter | `assets/craft/kite.glb` | `art/design/craft/kite.glb` |
| Regent Executive helicopter | `assets/craft/regent.glb` | `art/design/craft/regent.glb` |
| Skylark 4 propeller plane | `assets/craft/skylark.glb` | `art/design/craft/skylark.glb` |
| Merlin Twin propeller plane | `assets/craft/merlin.glb` | `art/design/craft/merlin.glb` |
| Aurora 7 Jet | `assets/craft/aurora.glb` | `art/design/craft/aurora.glb` |
| Dart 18 runabout | `assets/craft/dart.glb` | `art/design/craft/dart.glb` |
| Swift 26 Sport speedboat | `assets/craft/swift.glb` | `art/design/craft/swift.glb` |
| Majesty 92 Yacht | `assets/craft/majesty.glb` | `art/design/craft/majesty.glb` |
| Skyport narrow-body airliner, scheduled and parked liveries | `assets/craft/liner.glb` | `art/design/craft/liner.glb` |

`src/empire/world/venues.gd` instantiates vehicles independently at exhibit markers in `assets/venues/kestrel.glb`, `assets/venues/meridian.glb`, `assets/venues/aviation.glb` and `assets/venues/marina.glb`. Those venue meshes carry their own finishes. Catalog thumbnails in `src/empire/ui/thumbs.gd` render the vehicle model to a viewport. They have no dedicated image files for vehicle surfaces.

### Rail, marine and procedural scenery

Rows with a GDScript constructor have no separate model or Blender file. Shared world materials in this table are detailed in section 3.

| Vehicle or group | Model or geometry source | Godot material owner and coordinates |
|---|---|---|
| City Loop and Airport Rail trains, leading/trailing cabs and intermediate coaches | `assets/models/train_cab.glb` and `assets/models/train_car.glb`, generated by `tools/blender/build_kit.py` | `src/world/trains.gd` retains imported materials and shares a duplicate of `train_window` and `lamp` across the fleet for night emission. No exported UVs. |
| Skyport Link people mover | `src/world/skyport_airport.gd`, `LinkShuttle.setup()` | `src/world/skyport_island.gd` (`_bmat()`) supplies the world building shader. A single procedural mesh is shared by both cars. Generated architectural UV/material attributes and vertex colors. |
| Port-route and open-ocean container ships | `assets/models/cargo_ship.glb`, generated by `tools/blender/build_cargo_ship.py` | `src/world/sea_and_sky.gd` keeps imported hull, bridge glazing, deck, fittings and container materials. Additional navigation lights and wakes use its generated StandardMaterial3D instances. Geometric fallback hull uses vertex color. No exported UVs. |
| Moored dock-basin container ship | `src/world/set_pieces.gd`, `ship()` | `src/world/building_mesher.gd` and `src/world/city_world.gd` batch it into the world building material. Generated architectural UV/material attributes and vertex colors. |
| Bay motorboat and sailing yacht | `src/world/sea_and_sky.gd`, `_motorboat()`, `_yacht()` | Shared vertex-color `_mat` at roughness 0.75 and alpha `_wake_mat`. Hull/deck/sail colors are authored in code. No image UV unwrap. |
| Waterfront moored motorboat and sailing yacht | `src/world/coast_life.gd`, `_motorboat()`, `_yacht()` | World building material via `src/world/building_mesher.gd` and `src/world/city_world.gd`. Generated architectural attributes. Skyport marina's separate moored craft in `src/world/island_life.gd` reuse owned craft GLBs. |
| News helicopter and high-altitude airliner | `src/world/sea_and_sky.gd`, `_helicopter()`, `_airliner()` | Shared vertex-color `_mat` and unshaded emissive `_lamp_mat`. Rotor/wing/glazing detail is colored geometry. No image UV unwrap. |
| Parked regional prop and parked business jet | `src/world/skyport_airport.gd`, `build_parked()`, IDs `regional` and `bizjet`; geometry in `src/vehicle/craft_models.gd` | Runtime box meshes through `CraftModels._build_boxes()`, with shared vertex-color `StandardMaterial3D` (roughness 0.45). No dedicated image UV unwrap. Skyport's scheduled GLB airliner has additional unshaded emissive bulbs from `src/world/air_traffic.gd`. |
| Gate and apron equipment including belt loaders, catering truck, fuel bowser, baggage tugs and carts, ground power units and pushback tractors | `src/world/skyport_airport.gd`, `build_parked()` and `build_apron_kit()` | World building material through `SkyportIsland._bmat()`. Vehicle silhouettes and colors are part of the merged `GateEquipment` and `ApronKit` meshes. |
| Skyport garage parked-car props and surface-lot fallback props | `src/world/skyport_airport.gd`, `build_car_park()` and `build_apron_kit()` | Two colored boxes per car, batched into the shared world building material. |
| Wholesale warehouse forklift | `src/empire/world/shop_interior.gd`, `_build_warehouse()` | Vertex-colored body, cage, tyres and forks in the warehouse batch, `ShopInterior._mat("vc")` with roughness 0.7. |

## 2. Godot material and shader assignments

### Physical road vehicles and display cars

The executable material definitions live in `src/vehicle/car_visual.gd`. All finishes below have **no surface texture file** and therefore no pixel resolution. Geometry, imported normals, material values or analytical shading supply the current detail.

| Surface / imported names | Effective Godot material and exact shader path |
|---|---|
| Main bodywork, `paint` | Per-car `ShaderMaterial` from `res://src/vehicle/car_paint.gdshader`. Tint, flake, wetness, dirt, gloss and clear coat are procedural. Its shared analytic reflection include is `res://src/world/shaders/fake_reflect.gdshaderinc`. |
| Secondary bodywork, `paint2` | Per-car `StandardMaterial3D`; color from the spec, metallic 0.10, roughness 0.35. |
| Clear cabin windows, `glass_clear`; dark glazing, `glass` | Shared `res://src/vehicle/car_glass_clear.gdshader` and `res://src/vehicle/car_glass.gdshader`, respectively. Both use the analytic reflection include. Clear glass has view-dependent transparency. Traffic has its own glass variants. |
| Cabin and underbody, `interior`, `headliner`, `plastic`, `rubber`, `liner`, `bed` | Shared `StandardMaterial3D` per name. Roughness 0.72, 0.90, 0.48, 0.80, 0.85 and 0.95 respectively. Interior colors currently combine seats, rails, dash or other components under a small number of material IDs. |
| Tread and sidewall, `tyre`, `tyre_wall` | Shared `res://src/vehicle/wheel_rubber.gdshader` for separate player wheel meshes, with sidewall and off-road switches. The shader uses axle-local position for mould marks and sipes. On imported body surfaces and entry pieces these names resolve to plain shared rubber finishes in `shared_mat()`. |
| Alloy, dark rim and caliper, `rim`, `rim_dark`, `caliper` | Shared `StandardMaterial3D`. Metallic 0.84/0.85/0.35 and roughness 0.21/0.28/0.24. Rim and painted caliper finishes have scalar clear coat. Physical wheel calipers are generated in code and may use plain `trim`. |
| Brake disc, `disc` | Wheel meshes use shared `res://src/vehicle/brake_rotor.gdshader`. Axle-local radius and angle drive ring and slot detail, roughness and steel coloration. Non-wheel surfaces resolve through shared `StandardMaterial3D`. |
| Headlight and taillight emitters, `lamp_head`, `lamp_tail`; reverse, `lamp_rev` | Per-car emissive `StandardMaterial3D` for head and tail. `res://src/vehicle/reverse_lamp.gdshader` handles reverse. Procedural flare billboards use `res://src/vehicle/lamp_flare.gdshader` with generated UV and UV2 values, vertex colors and lamp directions. Beam lighting is generated from SpotLight3D nodes. |
| Lamp hardware, `lamp_housing`, `reflector`, `lens`, `lens_red`, `reflex`, `lamp_amber`, `sign` | Shared `StandardMaterial3D` per name. Reflectors are metal, clear/red lenses use alpha, reflex is glossy deep red, amber/sign are emissive. Lens shape and lamp internals are modeled. |
| Police beacon, `beacon_blue` and the supported `beacon_red` slot | Per-car `res://src/vehicle/beacon.gdshader`. Emission changes through code and procedural shader phase. |
| Trim and exterior details, `trim`, `chrome`, `grille`, `seam`, `carbon`, `cladding`, `plate`, `plate_rear`, `livery_blue`, `livery_green`, `livery_yellow` | Shared `StandardMaterial3D` per name through `shared_mat()`. Chrome is metallic 1.0 and roughness 0.12. Carbon uses scalar clear coat. Liveries, plate faces and badges use material colors and/or geometry. |
| Contact shadow, damage internals and workshop additions | Inline `CONTACT_SHADER` in `src/vehicle/car_visual.gd`; uses generated quad UV. Opaque frame, armour, ram, cage, hopper and spikes use code-created scalar materials in the same file. Torn-off parts carry copied overrides. |

`src/vehicle/car_visual.gd` applies the entry meshes' body finishes by matching material names, stripping Blender's numeric suffix. Where there is no matching body slot it calls `shared_mat()`. Entry exports contain `CabinOpening`, `DoorLeft` and `DoorRight`. Keep their materials and UV placement coordinated with the main body when painting or baking visible panel detail.

### Traffic, craft and other imported vehicles

| Rendering path | Associated Godot material definition |
|---|---|
| Parked city traffic and Skyport traffic | `src/world/city_world.gd` (`TRAFFIC_MATS`, `_traffic_car_mesh()`, `_commit_traffic()`) merges lower-detail surfaces by finish. Uses `res://src/world/shaders/traffic.gdshader`, `res://src/world/shaders/traffic_glass.gdshader` and `res://src/world/shaders/traffic_ao.gdshader`. Both imported glass names share the same glass group. Many trim, cabin, lens and dark wheel slots merge into one dark group. Paint is instance-tinted. |
| Moving Commercial and Westbank traffic | `src/world/traffic.gd` duplicates the prepared materials, using `res://src/world/shaders/traffic_path.gdshader`, `res://src/world/shaders/traffic_path_glass.gdshader` and `res://src/world/shaders/traffic_path_ao.gdshader`. The far band simplifies glass. `res://src/world/shaders/traffic_beam.gdshader` and `res://src/world/shaders/traffic_path_beam.gdshader` remain in code. Current stock traffic construction supplies zero beam width. |
| Owned craft, showroom craft and imported Skyport airliners | `src/vehicle/craft_models.gd` retains each GLB's `StandardMaterial3D` slots, duplicating and caching `paint`/`paint2` by material name and tint. Other body, deck, upholstery, glazing, gear, blade and light finishes use embedded scalar factors. Glass and blur are separate material slots where present. |
| Cargo ship, legacy Delivery Van and rail | Imported `StandardMaterial3D` as identified by GLB and slot in section 5. `src/world/trains.gd` duplicates the window and headlamp materials for night control. `src/empire/world/shop_interior.gd` puts the Delivery Van's imported mesh directly on the delivery actor. |

## 3. Actual images and generated texture resolutions

| Texture or binding | Exact path or runtime owner | Resolution and use |
|---|---|---|
| Dedicated vehicle maps | No file path. No texture bindings in any vehicle GLB or in the runtime vehicle surface materials. | N/A for base color, normal, roughness, metallic, AO, emission, opacity, clear-coat, tread, livery and decals. Procedural shading has no source image dimensions. |
| Shared painted world trim | `res://assets/textures/pbr/metal_plate_02.png` → `metal_tex` in `res://src/world/shaders/building.gdshader`. Bound by `src/world/city_world.gd`. | **1024 × 1024**. Dominant-axis world projection on eligible saturated trim. Packed value, normal detail and roughness with a shader-controlled metallic boost. Can affect the procedural dock ship, waterfront boats, Link shuttle and airport props. |
| Shared neutral world trim | `res://assets/textures/pbr/codex_concrete.png` → `struct_tex` in the same building shader. | **1024 × 1024**. Dominant-axis world projection on eligible neutral surfaces. Shares the UV-independent world-material path with painted trim. Near-field fade, material category and roughness gates apply to both images. |
| Traffic path data `lane_tex` | `src/world/traffic.gd` (`_bake_texture()`) | **1024 × 32** Commercial and **1024 × 17** Westbank on the default layout. The height formula is max(1, ceil(packed lane records ÷ 1024)). RGBA float, without mipmaps. Lane headers and sample coordinates steer the GPU instances. |
| World traffic height `ground_height` | `src/world/city_world.gd` (`_bake_ground_height()`) and `src/world/city_terrain.gd` (`bake()`) | **601 × 721** on the default world layout. Each axis is ceil(grid span in metres ÷ 2) + 1. RG float, without mipmaps. Terrain data, sampled by the static-path traffic and glass shaders' moving branch. |
| Tyre skid trail gradient | `src/fx/vehicle_fx.gd`, `GradientTexture2D` on the skid ribbon material | **32 × 1** generated at runtime. The alpha profile feathers the mark across the ribbon. This is the one intentionally tiny vehicle-related visual texture. |
| Vehicle particles and water rings | `res://src/fx/particle.gdshader` and `res://src/fx/water_ripple.gdshader` | Analytical masks, no image dimensions. |

The asphalt, storefront, showroom and seabed images render the surrounding scene. Environment lighting can affect vehicle reflections. These images are outside the vehicle's surface texture inventory.

## 4. Gaps and realism priorities

**UV and source gap.** The road body GLBs and animated entry GLBs export `TEXCOORD_0`, but only **60 of 888** road body/LOD primitives and **21 of 452** entry primitives contain even one non-zero-area UV triangle. Almost all such triangles are on fragments of trim, chrome or small lamp/livery regions. Main paint UVs are collapsed on the owned fleet. All 15 wheel GLBs, all 10 craft GLBs, the five legacy cars, both rail GLBs and the cargo ship have no UV set. No audited vehicle GLB exports `TEXCOORD_1` or `TANGENT`. Godot import's `ensure_tangents=true` is an import setting. It cannot remedy missing or collapsed UVs. No evidence supports treating any existing exported vehicle UV layer as a complete bake layout. Material and UV evidence by file is below.

**Resolution gap.** There are no low-resolution vehicle surface maps to upscale. Low detail appears in geometry LODs and props. Civilian traffic mids are 1,111–1,142 triangles before the runtime wheels, near copies of the eight catalogue traffic bodies are 5,811–5,964 triangles, and the shared near traffic wheel has 396 triangles. Far traffic uses generated box silhouettes. The legacy delivery van is 1,600 triangles, with integrated wheels. Skyport equipment and some parked aircraft/cars are procedural blocks. Replace or refine geometry where silhouettes, cabin openings, wheel arches and glass volume matter. Texture work cannot change those shapes.

| Priority | Surfaces and vehicles | Suggested authoring targets |
|---|---|---|
| 1 | Kestrel Hatch/used, Courier Van and Box Truck. Follow with premium showroom cars and the matching `assets/vehicle_entries/` meshes. | Establish seam placement and consistent pixel density in a usable UV0. For close-view cars, start with a **2048²** exterior mask/normal/packed material set and **1024²–2048²** for cockpit trim. Keep base paint tint, clear coat, rain and dirt in the current shader. Add UV masks for seams, badges, chips, panel dirt and substrate exposure. Keep painted dielectric surfaces low-metallic and use metallic masks for exposed metal, badges and chrome. Bake through equivalent static and opening body parts. |
| 2 | All shared road wheels, especially off-road, steel, center-lock and Kestrel. | A shared **1024²** cylindrical tread and radial sidewall set can carry molded text, fine relief, roughness and wear. Retain large grooves in geometry. Keep rubber dielectric. Use a separate shared **512²–1024²** machined alloy/rotor atlas or tiled normal and roughness, with metal masks for coated versus bare wheel surfaces and a distinct caliper finish. |
| 3 | Physical road headlamps, taillamps and glass across the cabin fleet, then aircraft and marine glazing. | A **512²–1024²** shared optical atlas can add reflector/lens micro-normal and roughness, lamp emissive masks, rear defroster lines and edge frit. Keep headlamp and brake state controls. Use subtle glass roughness and normal variation, a separate lens layer and restrained marks in the central windshield. |
| 4 | Cabins in purchasable road vehicles, helicopters and boats, starting with models viewed through clear panes or boardside. | Reuse **512²–1024²** tileable fabric, leather grain, molded plastic, carpet, anodized metal and non-slip deck normals/roughness. Split overly broad `interior` surfaces by material type. Reserve unique space for stitches, markings and instrumentation. Prioritize geometry where windows reveal empty shells. |
| 5 | Train front/coach, port cargo ship, yacht and aircraft exteriors. | Use **1024²–2048²** UV atlases or decals for fleet markings, door lines, airframe fasteners, scuffs, draft marks and exterior labels. Use tileable deck grain/non-slip, painted metal, selective exposed-metal masks, salt or grime masks and deliberate roughness variation. Keep large ship surfaces tiled and allocate unique UV space to lettering. |
| 6 | Near civic traffic, variants and far scenery. | Add a shared **512²–1024²** decal/livery atlas for taxi signs, emergency markings, plates and lenses only where they resolve on screen. Keep mid/far variants on the existing cheap finish groups where possible. Evaluate replacement silhouettes for the Delivery Van and airport equipment independently of image sizes. |

Recommended map sizes are starting points. Verify UV coverage, padding at mip levels, mirrored/split tangent orientation, damage swaps, door alignment, wet/dry response, glass sorting and headlight contrast. Use sRGB for color data, linear for material masks, and Godot-compatible tangent-space normals, with mipmaps and platform-appropriate compression. Pack AO, roughness and metallic where the receiving shader supports those channels. Test the Mobile renderer first, then the Web compatibility renderer. Measure texture memory and traffic draw counts before adding unique maps to shared batches.


## 5. Per-file mesh, UV and material inventory

Every row below has **no image maps and no image resolution**. `UV0` is the exported glTF `TEXCOORD_0` attribute. “0 area” means no triangle on the primitive had UV area above 5 × 10⁻¹¹ square UV units. In the details column, `trim 344/3844` means 344 UV triangles with nonzero area out of 3,844 on that primitive. All other primitives with UV0 have zero area. This check measures whether coordinates span two dimensions. It does not verify usable islands, spacing or absence of overlap. Material names below preserve the GLB names and Blender suffixes. Triangle counts are exported mesh counts before Godot's generated LODs or runtime geometry additions.

Road generators `tools/blender/kestrel.py`, `tools/blender/ws_cars.py` and `tools/blender/ws_fleet.py` share helpers in `tools/blender/build_kit.py` and `tools/blender/ws_rear.py`. To locate runtime materials by name, use the assignment tables in section 2. For craft, cargo ship, rail and the delivered legacy van, the GLB itself is also the Godot material source.

### Full-size road bodies

| Exact model path | Blender generator | Triangles | UV0 details | Imported material slots |
|---|---|---:|---|---|
| `assets/vehicles/brute.glb` | `tools/blender/ws_cars.py` | 38,885 | `trim` 544/8162, `chrome` 240/2786 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `disc`, `reflex`, `glass_clear`, `carbon`, `paint2` |
| `assets/vehicles/civ_ambulance.glb` | `tools/blender/ws_fleet.py` | 19,558 | `trim` 420/5576 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `lamp_rev`, `lamp_tail`, `reflex`, `plate_rear`, `disc`, `glass`, `beacon_blue`, `livery_green`, `livery_yellow` |
| `assets/vehicles/civ_box.glb` | `tools/blender/ws_cars.py` | 35,509 | `trim` 428/5782 | `paint`, `liner`, `lamp_housing`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `plastic`, `plate`, `glass_clear`, `lamp_tail`, `lamp_rev`, `plate_rear`, `reflex` |
| `assets/vehicles/civ_bus.glb` | `tools/blender/ws_cars.py` | 55,418 | `trim` 460/14386, `chrome` 140/1602, `lamp_amber` 314/1364 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `plate`, `lamp_rev`, `lamp_tail`, `lens_red`, `plate_rear`, `reflex`, `glass_clear`, `headliner`, `glass` |
| `assets/vehicles/civ_compact.glb` | `tools/blender/ws_fleet.py` | 16,744 | `trim` 372/4604 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `reflex`, `lamp_tail`, `lamp_rev`, `plate_rear`, `disc`, `glass` |
| `assets/vehicles/civ_police.glb` | `tools/blender/ws_fleet.py` | 19,425 | `trim` 300/4880 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `reflex`, `lamp_tail`, `lamp_rev`, `plate_rear`, `disc`, `glass`, `beacon_blue`, `livery_blue`, `livery_yellow` |
| `assets/vehicles/civ_sedan.glb` | `tools/blender/ws_fleet.py` | 17,296 | `trim` 536/4624 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `reflex`, `lamp_tail`, `lamp_rev`, `plate_rear`, `disc`, `glass` |
| `assets/vehicles/civ_suv.glb` | `tools/blender/ws_fleet.py` | 19,150 | `trim` 388/4752 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `reflex`, `lamp_tail`, `lamp_rev`, `plate_rear`, `disc`, `glass` |
| `assets/vehicles/civ_taxi.glb` | `tools/blender/ws_fleet.py` | 17,208 | `trim` 392/4428 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `reflex`, `lamp_tail`, `lamp_rev`, `plate_rear`, `disc`, `glass`, `sign` |
| `assets/vehicles/civ_van.glb` | `tools/blender/ws_fleet.py` | 17,794 | `trim` 336/5300 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `lamp_rev`, `lamp_tail`, `reflex`, `plate_rear`, `disc`, `glass` |
| `assets/vehicles/courier_van.glb` | `tools/blender/ws_cars.py` | 33,194 | `trim` 336/6000, `chrome` 232/1856 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `reflex`, `glass_clear`, `glass` |
| `assets/vehicles/goliath.glb` | `tools/blender/ws_cars.py` | 40,032 | `trim` 408/7174, `chrome` 158/2818 | `paint`, `bed`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `cladding`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `disc`, `reflex`, `glass_clear` |
| `assets/vehicles/halcyon.glb` | `tools/blender/ws_cars.py` | 41,785 | `trim` 166/6316, `chrome` 212/2342 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `lamp_head`, `trim`, `lamp_amber`, `reflector`, `lamp_rev`, `lamp_tail`, `chrome`, `lens_red`, `plate_rear`, `carbon`, `disc`, `reflex`, `glass_clear`, `glass` |
| `assets/vehicles/kestrel.glb` | `tools/blender/kestrel.py` | 44,671 | `trim` 344/3844 | `paint`, `liner`, `interior`, `lamp_housing`, `plastic`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `plate`, `lamp_rev`, `lamp_tail`, `lens_red`, `plate_rear`, `glass_clear` |
| `assets/vehicles/mammoth.glb` | `tools/blender/ws_cars.py` | 35,276 | `trim` 320/5954 | `paint`, `liner`, `lamp_housing`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `plastic`, `plate`, `glass_clear`, `lamp_tail`, `lamp_rev`, `plate_rear`, `reflex` |
| `assets/vehicles/marlin.glb` | `tools/blender/ws_cars.py` | 44,422 | `trim` 356/7340, `chrome` 200/4930 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `disc`, `reflex`, `glass_clear`, `carbon` |
| `assets/vehicles/police_heavy.glb` | `tools/blender/ws_cars.py` | 44,393 | `paint` 288/11518, `trim` 336/9340, `chrome` 144/2452 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `disc`, `reflex`, `glass_clear`, `glass`, `cladding`, `beacon_blue`, `paint2` |
| `assets/vehicles/police_interceptor.glb` | `tools/blender/ws_cars.py` | 43,361 | `trim` 312/8224, `chrome` 144/3064, `paint2` 288/736 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `carbon`, `disc`, `reflex`, `glass_clear`, `beacon_blue`, `paint2` |
| `assets/vehicles/police_patrol.glb` | `tools/blender/ws_cars.py` | 42,957 | `paint` 288/7568, `trim` 416/6076, `chrome` 144/4198 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `reflex`, `glass_clear`, `beacon_blue`, `paint2` |
| `assets/vehicles/scout.glb` | `tools/blender/ws_cars.py` | 39,703 | `trim` 448/7536, `chrome` 256/2588 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `plate`, `lamp_rev`, `lamp_tail`, `lens_red`, `plate_rear`, `disc`, `reflex`, `glass_clear`, `glass`, `carbon`, `paint2`, `cladding` |
| `assets/vehicles/stiletto.glb` | `tools/blender/ws_cars.py` | 43,406 | `trim` 136/7064, `chrome` 168/2054 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `lamp_head`, `trim`, `lamp_amber`, `reflector`, `lamp_rev`, `lamp_tail`, `chrome`, `lens_red`, `plate_rear`, `carbon`, `disc`, `reflex`, `glass_clear`, `glass` |
| `assets/vehicles/vanta.glb` | `tools/blender/ws_cars.py` | 41,714 | `trim` 280/8306, `chrome` 138/2836 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `carbon`, `disc`, `reflex`, `glass_clear` |
| `assets/vehicles/warden.glb` | `tools/blender/ws_cars.py` | 44,929 | `trim` 424/9774, `chrome` 168/2650 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `disc`, `reflex`, `glass_clear`, `glass`, `cladding` |

### Traffic near and mid body variants

| Exact model path | Blender generator | Triangles | UV0 details | Imported material slots |
|---|---|---:|---|---|
| `assets/vehicles/brute_lod1.glb` | `tools/blender/lod1.py` | 1,157 | `trim` 4/189 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `glass_clear`, `carbon`, `paint2` |
| `assets/vehicles/brute_traffic.glb` | `tools/blender/lod1.py` | 5,877 | `trim` 24/761 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `disc`, `reflex`, `glass_clear`, `carbon`, `paint2` |
| `assets/vehicles/civ_ambulance_lod1.glb` | `tools/blender/ws_fleet.py` | 1,111 | `trim` 3/301 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `lamp_rev`, `lamp_tail`, `reflex`, `plate_rear`, `disc`, `glass`, `beacon_blue`, `livery_green`, `livery_yellow` |
| `assets/vehicles/civ_compact_lod1.glb` | `tools/blender/ws_fleet.py` | 1,142 | `trim` 4/319 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `reflex`, `lamp_tail`, `lamp_rev`, `plate_rear`, `disc`, `glass` |
| `assets/vehicles/civ_police_lod1.glb` | `tools/blender/ws_fleet.py` | 1,115 | `trim` 2/251 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `reflex`, `lamp_tail`, `lamp_rev`, `plate_rear`, `disc`, `glass`, `beacon_blue`, `livery_blue`, `livery_yellow` |
| `assets/vehicles/civ_sedan_lod1.glb` | `tools/blender/ws_fleet.py` | 1,141 | `trim` 4/319 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `reflex`, `lamp_tail`, `lamp_rev`, `plate_rear`, `disc`, `glass` |
| `assets/vehicles/civ_suv_lod1.glb` | `tools/blender/ws_fleet.py` | 1,132 | `trim` 2/265 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `reflex`, `lamp_tail`, `lamp_rev`, `plate_rear`, `disc`, `glass` |
| `assets/vehicles/civ_taxi_lod1.glb` | `tools/blender/ws_fleet.py` | 1,140 | `trim` 3/302 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `reflex`, `lamp_tail`, `lamp_rev`, `plate_rear`, `disc`, `glass`, `sign` |
| `assets/vehicles/civ_van_lod1.glb` | `tools/blender/ws_fleet.py` | 1,127 | `trim` 1/328 | `paint`, `liner`, `lamp_housing`, `plastic`, `reflector`, `lamp_head`, `chrome`, `lamp_amber`, `trim`, `plate`, `lamp_rev`, `lamp_tail`, `reflex`, `plate_rear`, `disc`, `glass` |
| `assets/vehicles/goliath_lod1.glb` | `tools/blender/lod1.py` | 1,111 | 0 area on every primitive | `paint`, `bed`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `cladding`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_tail`, `lens_red`, `glass_clear` |
| `assets/vehicles/goliath_traffic.glb` | `tools/blender/lod1.py` | 5,829 | `trim` 16/729 | `paint`, `bed`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `cladding`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `reflex`, `glass_clear` |
| `assets/vehicles/halcyon_lod1.glb` | `tools/blender/lod1.py` | 1,191 | `trim` 1/179 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `lamp_head`, `trim`, `lamp_amber`, `reflector`, `lamp_rev`, `lamp_tail`, `chrome`, `lens_red`, `plate_rear`, `carbon`, `glass_clear`, `glass` |
| `assets/vehicles/halcyon_traffic.glb` | `tools/blender/lod1.py` | 5,964 | `trim` 6/458, `chrome` 4/235 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `lamp_head`, `trim`, `lamp_amber`, `reflector`, `lamp_rev`, `lamp_tail`, `chrome`, `lens_red`, `plate_rear`, `carbon`, `disc`, `reflex`, `glass_clear`, `glass` |
| `assets/vehicles/kestrel_lod1.glb` | `tools/blender/lod1.py` | 1,124 | `trim` 3/85 | `paint`, `liner`, `interior`, `lamp_housing`, `plastic`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `lamp_tail`, `lens_red`, `glass_clear` |
| `assets/vehicles/kestrel_traffic.glb` | `tools/blender/lod1.py` | 5,874 | `trim` 13/261 | `paint`, `liner`, `interior`, `lamp_housing`, `plastic`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `plate`, `lamp_rev`, `lamp_tail`, `lens_red`, `plate_rear`, `glass_clear` |
| `assets/vehicles/marlin_lod1.glb` | `tools/blender/lod1.py` | 1,074 | 0 area on every primitive | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `lamp_tail`, `lens_red`, `glass_clear`, `carbon` |
| `assets/vehicles/marlin_traffic.glb` | `tools/blender/lod1.py` | 5,821 | `trim` 10/551 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `reflex`, `glass_clear`, `carbon` |
| `assets/vehicles/scout_lod1.glb` | `tools/blender/lod1.py` | 1,090 | `trim` 2/216 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `plate`, `lamp_rev`, `lamp_tail`, `lens_red`, `plate_rear`, `glass_clear`, `glass`, `carbon`, `paint2`, `cladding` |
| `assets/vehicles/scout_traffic.glb` | `tools/blender/lod1.py` | 5,815 | `trim` 12/809 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `plate`, `lamp_rev`, `lamp_tail`, `lens_red`, `plate_rear`, `reflex`, `glass_clear`, `glass`, `carbon`, `paint2`, `cladding` |
| `assets/vehicles/vanta_lod1.glb` | `tools/blender/lod1.py` | 1,093 | 0 area on every primitive | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `carbon`, `glass_clear` |
| `assets/vehicles/vanta_traffic.glb` | `tools/blender/lod1.py` | 5,811 | `trim` 4/641 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `carbon`, `reflex`, `glass_clear` |
| `assets/vehicles/warden_lod1.glb` | `tools/blender/lod1.py` | 1,149 | 0 area on every primitive | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_tail`, `lens_red`, `glass_clear`, `glass`, `cladding` |
| `assets/vehicles/warden_traffic.glb` | `tools/blender/lod1.py` | 5,868 | `trim` 10/724 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `reflex`, `glass_clear`, `glass`, `cladding` |

### Road wheel assets

The physical garage options are steel, five, split, deep, blade, turbine, mesh and offroad. Other paths are vehicle-specific defaults or the common traffic wheel.

| Exact model path | Blender generator | Triangles | UV0 details | Imported material slots |
|---|---|---:|---|---|
| `assets/vehicles/wheel_blade.glb` | `tools/blender/ws_cars.py` | 1,872 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `rim_dark`, `chrome` |
| `assets/vehicles/wheel_center.glb` | `tools/blender/ws_cars.py` | 3,700 | Absent | `tyre`, `tyre_wall`, `liner`, `rim_dark`, `disc`, `chrome`, `rim`, `caliper` |
| `assets/vehicles/wheel_deep.glb` | `tools/blender/ws_cars.py` | 1,888 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `rim_dark`, `chrome` |
| `assets/vehicles/wheel_dish.glb` | `tools/blender/ws_cars.py` | 4,060 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `chrome`, `rim_dark` |
| `assets/vehicles/wheel_five.glb` | `tools/blender/ws_cars.py` | 1,656 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `rim_dark`, `chrome` |
| `assets/vehicles/wheel_kestrel.glb` | `tools/blender/kestrel.py` | 2,816 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `rim_dark`, `chrome` |
| `assets/vehicles/wheel_mesh.glb` | `tools/blender/ws_cars.py` | 2,844 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `rim_dark`, `chrome` |
| `assets/vehicles/wheel_multi.glb` | `tools/blender/ws_cars.py` | 3,872 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `chrome`, `rim_dark` |
| `assets/vehicles/wheel_offroad.glb` | `tools/blender/ws_cars.py` | 3,428 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `chrome`, `rim_dark` |
| `assets/vehicles/wheel_rally.glb` | `tools/blender/ws_cars.py` | 2,832 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `chrome`, `rim_dark`, `paint2` |
| `assets/vehicles/wheel_split.glb` | `tools/blender/ws_cars.py` | 2,196 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `rim_dark`, `chrome` |
| `assets/vehicles/wheel_steel.glb` | `tools/blender/ws_cars.py` | 3,384 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `chrome`, `rim_dark` |
| `assets/vehicles/wheel_traffic.glb` | `tools/blender/ws_fleet.py` | 396 | Absent | `tyre`, `liner`, `rim` |
| `assets/vehicles/wheel_turbine.glb` | `tools/blender/ws_cars.py` | 2,412 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `rim_dark`, `chrome` |
| `assets/vehicles/wheel_y5.glb` | `tools/blender/ws_cars.py` | 3,972 | Absent | `tyre`, `tyre_wall`, `liner`, `rim`, `disc`, `chrome`, `rim_dark` |

### Animated road entry variants

The generator imports the corresponding body GLB first. The existing `civ_van` entry export belongs to the civilian van. The owned van uses `courier_van`. The generator includes Mammoth as a target, with no `assets/vehicle_entries/mammoth.glb` in this checkout. Its access code uses the fallback without animated door meshes.

| Exact model path | Blender generator | Triangles | UV0 details | Imported material slots |
|---|---|---:|---|---|
| `assets/vehicle_entries/brute.glb` | `tools/blender/build_vehicle_entries.py` | 46,360 | `trim` 544/7754, `chrome` 240/2338 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `disc`, `reflex`, `glass_clear`, `carbon`, `paint2` |
| `assets/vehicle_entries/civ_box.glb` | `tools/blender/build_vehicle_entries.py` | 45,235 | `trim.001` 428/6186 | `paint.001`, `liner.001`, `lamp_housing.001`, `interior.001`, `rubber.001`, `lens.001`, `reflector.001`, `trim.001`, `chrome.001`, `lamp_head.001`, `lamp_amber.001`, `plastic.001`, `plate.001`, `glass_clear.001`, `lamp_tail.001`, `lamp_rev.001`, `plate_rear.001`, `reflex.001` |
| `assets/vehicle_entries/civ_van.glb` | `tools/blender/build_vehicle_entries.py` | 22,704 | `trim.002` 336/5310 | `paint.002`, `liner.002`, `lamp_housing.002`, `plastic.002`, `reflector.002`, `lamp_head.002`, `chrome.002`, `lamp_amber.002`, `trim.002`, `plate.002`, `lamp_rev.002`, `lamp_tail.002`, `reflex.002`, `plate_rear.002`, `disc.001`, `glass` |
| `assets/vehicle_entries/courier_van.glb` | `tools/blender/build_vehicle_entries.py` | 39,362 | `trim` 336/5188, `chrome` 232/1402 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `reflector`, `trim`, `chrome`, `lamp_head`, `lamp_amber`, `lamp_rev`, `plate`, `lamp_tail`, `lens_red`, `plate_rear`, `reflex`, `glass_clear`, `glass` |
| `assets/vehicle_entries/goliath.glb` | `tools/blender/build_vehicle_entries.py` | 47,932 | `trim.003` 408/6294, `chrome.003` 158/2586 | `paint.003`, `bed`, `liner.003`, `lamp_housing.003`, `plastic.003`, `interior.002`, `rubber.002`, `cladding`, `lens.002`, `reflector.003`, `trim.003`, `chrome.003`, `lamp_head.003`, `lamp_amber.003`, `lamp_rev.003`, `plate.003`, `lamp_tail.003`, `lens_red.001`, `plate_rear.003`, `disc.002`, `reflex.003`, `glass_clear.002` |
| `assets/vehicle_entries/halcyon.glb` | `tools/blender/build_vehicle_entries.py` | 50,779 | `trim` 166/6537, `chrome` 212/1774 | `paint`, `liner`, `lamp_housing`, `plastic`, `interior`, `rubber`, `lens`, `lamp_head`, `trim`, `lamp_amber`, `reflector`, `lamp_rev`, `lamp_tail`, `chrome`, `lens_red`, `plate_rear`, `carbon`, `disc`, `reflex`, `glass_clear`, `glass` |
| `assets/vehicle_entries/kestrel.glb` | `tools/blender/build_vehicle_entries.py` | 58,813 | `trim.005` 344/4351 | `paint.005`, `liner.005`, `interior.004`, `lamp_housing.005`, `plastic.005`, `rubber.004`, `lens.004`, `reflector.005`, `trim.005`, `chrome.005`, `lamp_head.005`, `lamp_amber.005`, `plate.004`, `lamp_rev.005`, `lamp_tail.005`, `lens_red.003`, `plate_rear.005`, `glass_clear.004` |
| `assets/vehicle_entries/marlin.glb` | `tools/blender/build_vehicle_entries.py` | 53,866 | `trim.006` 356/7342, `chrome.006` 200/4076 | `paint.006`, `liner.006`, `lamp_housing.006`, `plastic.006`, `interior.005`, `rubber.005`, `lens.005`, `reflector.006`, `trim.006`, `chrome.006`, `lamp_head.006`, `lamp_amber.006`, `lamp_rev.006`, `plate.005`, `lamp_tail.006`, `lens_red.004`, `plate_rear.006`, `disc.004`, `reflex.005`, `glass_clear.005`, `carbon.002` |
| `assets/vehicle_entries/scout.glb` | `tools/blender/build_vehicle_entries.py` | 48,507 | `trim.007` 448/7308, `chrome.007` 256/2142 | `paint.007`, `liner.007`, `lamp_housing.007`, `plastic.007`, `interior.006`, `rubber.006`, `lens.006`, `reflector.007`, `trim.007`, `chrome.007`, `lamp_head.007`, `lamp_amber.007`, `plate.006`, `lamp_rev.007`, `lamp_tail.007`, `lens_red.005`, `plate_rear.007`, `disc.005`, `reflex.006`, `glass_clear.006`, `glass.002`, `carbon.003`, `paint2.001`, `cladding.001` |
| `assets/vehicle_entries/stiletto.glb` | `tools/blender/build_vehicle_entries.py` | 53,669 | `trim.001` 136/6894, `chrome.001` 168/1486 | `paint.001`, `liner.001`, `lamp_housing.001`, `plastic.001`, `interior.001`, `rubber.001`, `lens.001`, `lamp_head.001`, `trim.001`, `lamp_amber.001`, `reflector.001`, `lamp_rev.001`, `lamp_tail.001`, `chrome.001`, `lens_red.001`, `plate_rear.001`, `carbon.001`, `disc.001`, `reflex.001`, `glass_clear.001`, `glass.001` |
| `assets/vehicle_entries/vanta.glb` | `tools/blender/build_vehicle_entries.py` | 50,166 | `trim.009` 280/7958, `chrome.009` 138/2308 | `paint.009`, `liner.009`, `lamp_housing.009`, `plastic.009`, `interior.008`, `rubber.008`, `lens.008`, `reflector.009`, `trim.009`, `chrome.009`, `lamp_head.009`, `lamp_amber.009`, `lamp_rev.009`, `plate.007`, `lamp_tail.009`, `lens_red.007`, `plate_rear.009`, `carbon.005`, `disc.007`, `reflex.008`, `glass_clear.008` |
| `assets/vehicle_entries/warden.glb` | `tools/blender/build_vehicle_entries.py` | 54,158 | `trim.010` 424/9689, `chrome.010` 168/2218 | `paint.010`, `liner.010`, `lamp_housing.010`, `plastic.010`, `interior.009`, `rubber.009`, `lens.009`, `reflector.010`, `trim.010`, `chrome.010`, `lamp_head.010`, `lamp_amber.010`, `lamp_rev.010`, `plate.008`, `lamp_tail.010`, `lens_red.008`, `plate_rear.010`, `disc.008`, `reflex.009`, `glass_clear.009`, `glass.004`, `cladding.002` |

### Aircraft and boat GLBs

| Exact model path | Blender generator | Triangles | UV0 details | Imported material slots |
|---|---|---:|---|---|
| `assets/craft/aurora.glb` | `tools/blender/build_craft.py` | 17,168 | Absent | `gelcoat`, `glass`, `paint2`, `paint`, `seam`, `intake`, `metal`, `exhaust`, `lamp_nav_red`, `lamp_nav_green`, `lamp_strobe`, `lamp_head`, `tyre`, `rim` |
| `assets/craft/dart.glb` | `tools/blender/build_craft.py` | 5,956 | Absent | `paint`, `antifoul`, `gelcoat`, `teak`, `cushion`, `trim`, `chrome`, `glass`, `metal` |
| `assets/craft/kite.glb` | `tools/blender/build_craft.py` | 12,328 | Absent | `paint`, `glass`, `seam`, `paint2`, `intake`, `exhaust`, `metal`, `trim`, `lamp_nav_red`, `lamp_nav_green`, `lamp_strobe`, `lamp_head`, `blade`, `blade_tip`, `rotor_blur` |
| `assets/craft/liner.glb` | `tools/blender/build_craft.py` | 19,940 | Absent | `gelcoat`, `glass`, `paint2`, `seam`, `fairing`, `paint`, `intake`, `metal`, `exhaust`, `lamp_nav_red`, `lamp_nav_green`, `lamp_strobe`, `tyre`, `rim` |
| `assets/craft/majesty.glb` | `tools/blender/build_craft.py` | 33,804 | Absent | `paint`, `antifoul`, `gelcoat`, `glass`, `teak`, `cushion`, `chrome`, `metal`, `lamp_strobe`, `trim`, `lamp_nav_red`, `lamp_nav_green` |
| `assets/craft/merlin.glb` | `tools/blender/build_craft.py` | 13,628 | Absent | `gelcoat`, `glass`, `paint2`, `paint`, `intake`, `exhaust`, `lamp_nav_red`, `lamp_nav_green`, `lamp_strobe`, `lamp_head`, `blade`, `blade_tip`, `rotor_blur`, `metal`, `tyre`, `rim` |
| `assets/craft/regent.glb` | `tools/blender/build_craft.py` | 13,108 | Absent | `paint`, `glass`, `paint2`, `seam`, `exhaust`, `intake`, `metal`, `lamp_nav_red`, `lamp_nav_green`, `lamp_strobe`, `lamp_head`, `blade`, `blade_tip`, `trim`, `rotor_blur`, `tyre`, `rim` |
| `assets/craft/skylark.glb` | `tools/blender/build_craft.py` | 10,604 | Absent | `gelcoat`, `glass`, `paint2`, `paint`, `lamp_nav_red`, `lamp_nav_green`, `lamp_strobe`, `lamp_head`, `blade`, `blade_tip`, `rotor_blur`, `metal`, `tyre`, `rim` |
| `assets/craft/swift.glb` | `tools/blender/build_craft.py` | 8,124 | Absent | `paint`, `antifoul`, `gelcoat`, `chrome`, `paint2`, `teak`, `cushion`, `trim`, `glass`, `lamp_nav_red`, `lamp_nav_green`, `metal` |
| `assets/craft/wren.glb` | `tools/blender/build_craft.py` | 9,608 | Absent | `paint`, `glass`, `metal`, `paint2`, `lamp_nav_red`, `lamp_nav_green`, `lamp_strobe`, `lamp_head`, `blade`, `blade_tip`, `trim`, `rotor_blur` |

### Legacy road, rail and cargo ship GLBs

The inherited legacy road exports match the `tools/blender/build_cars.py` filenames and material scheme. That script is the available generator. Exact historical Blender build provenance for these inherited binaries was unavailable.

| Exact model path | Blender generator | Triangles | UV0 details | Imported material slots |
|---|---|---:|---|---|
| `assets/models/car_hatch.glb` | `tools/blender/build_cars.py` | 1,624 | Absent | `paint`, `car_glass`, `trim`, `tyre`, `hub`, `lamp`, `lamp_red`, `plate` |
| `assets/models/car_sedan.glb` | `tools/blender/build_cars.py` | 1,624 | Absent | `paint`, `car_glass`, `trim`, `tyre`, `hub`, `lamp`, `lamp_red`, `plate` |
| `assets/models/car_suv.glb` | `tools/blender/build_cars.py` | 1,744 | Absent | `paint`, `car_glass`, `trim`, `tyre`, `hub`, `lamp`, `lamp_red`, `plate` |
| `assets/models/car_taxi.glb` | `tools/blender/build_cars.py` | 1,732 | Absent | `paint`, `car_glass`, `trim`, `tyre`, `hub`, `lamp`, `lamp_red`, `plate`, `lamp_sign` |
| `assets/models/car_van.glb` | `tools/blender/build_cars.py` | 1,600 | Absent | `paint`, `car_glass`, `trim`, `tyre`, `hub`, `lamp`, `lamp_red`, `plate` |
| `assets/models/cargo_ship.glb` | `tools/blender/build_cargo_ship.py` | 2,212 | Absent | `boot_red`, `hull_navy`, `deck_grey`, `rust_steel`, `super_white`, `bridge_glass`, `crane_ochre`, `funnel_stripe`, `lifeboat_org`, `railing`, `box_rust`, `box_blue`, `box_green`, `box_ochre`, `box_slate`, `box_cream` |
| `assets/models/train_cab.glb` | `tools/blender/build_kit.py` | 1,438 | Absent | `train_body`, `train_window`, `train_door`, `train_stripe`, `train_dark`, `train_roof`, `lamp` |
| `assets/models/train_car.glb` | `tools/blender/build_kit.py` | 1,312 | Absent | `train_body`, `train_window`, `train_door`, `train_stripe`, `train_dark`, `train_roof` |

### Coverage notes

- The 61 road GLBs comprise 23 full-size bodies, eight near traffic variants, 15 mid variants and 15 wheels. Section 5 also lists 12 entry exports, 10 craft exports and eight world-model GLBs. Catalogue and livery aliases reuse those model and material paths.
- The seven standard traffic bodies have dedicated mid GLBs. Box Truck, Mammoth, Stiletto, civilian bus and the physical pursuit variants have no separate traffic LOD exports in the checkout. These have no stock city traffic slots. Godot's scene import can still generate per-mesh LODs for the corresponding base assets.
- Fallback checks for `assets/models/car_police.glb` and `assets/models/car_ambulance.glb` would find no files. The current traffic renderer resolves `assets/vehicles/civ_police.glb` and `assets/vehicles/civ_ambulance.glb` and their mid models first.
- The most prominent shared road surfaces are `paint`, `glass`/`glass_clear`, `trim`, `chrome` and the lamp names. A shared finish change in `src/vehicle/car_visual.gd` can affect a large part of the fleet. An edit to GLB material factors alone is bypassed by many road overrides. Changes to shared craft paint would also need to consider `CraftModels._paints` cache keys, which use only slot name and color.

