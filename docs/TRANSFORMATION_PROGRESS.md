# WorldState — Next-Generation Transformation Progress

**Started:** 2026-11-24  
**Baseline Checkpoint:** tag `checkpoint-codex-baseline` (preserves all Codex work: 56 vehicle meshes, architecture, storefronts, lighting, wet roads, hero polish)  
**Baseline Tests:** `tests/run_tests.gd` — **112 passed, 0 failed** (60.3s)  
**Target Version:** `0.11.0` (internal TestFlight via `.github/workflows/testflight.yml`)

---

## Transformation Tracks

### Track 1: Checkpoint & Baseline Captures
- [x] Repository audit across 4 specialized domains (Environment/Rendering, Living City/Vehicles/Animation, Interiors/Economy/Reliability, UI/UX/Performance)
- [x] Baseline test suite verified (112/112 pass)
- [x] Recoverable git checkpoint commit + `checkpoint-codex-baseline` tag
- [ ] Baseline BEFORE screenshots & `RENDER_STATS` / `PERF` recorded (running)

### Track 2: Environment, Architecture, Trees & Cinematic Rendering
- [ ] Fix Skyport night streetlamps (`LampLights` wiring + road lamp poles + `island_ground.gdshader` temp-aware wet reflections & rain ripples)
- [ ] Add city skyline & night-light reflections to `water.gdshader`
- [ ] Fix `building.gdshader` ALU & visual bugs (gate `city_reflection`/`room` on `glass`, wet `SPECULAR`, preserve window `bend_n` under PBR normal, fix graffiti `fwidth()` dynamic-branch loop, remove dead roof code)
- [ ] Night street realism: warm shopfront pavement spill (`ground.gdshader`), emissive portal brass lamps (`building_mesher.gd`), ground-hugging traffic headlight beams (`city_world.gd` + `traffic_path_beam.gdshader`)
- [ ] Architectural depth & neighbourhood identity: pitched/hipped roofs + chimneys on Georgian/Old Town & Westbank residential, open-railing balconies, awning gussets, corner downpipes, vertex-baked contact AO, enhanced `ShadowProxy`
- [ ] Wet-reactive `furniture.gdshader` + sidewalk tree grates
- [ ] Vegetation variety (district-biased species using existing tree GLBs + wind-synced bark + wet foliage + `Landforms` near-tree detail) + distant foothill night lights in `hinterland.gdshader`
- [ ] Lightweight MSAA-compatible `cinematic` post-grade without `hint_depth_texture`

### Track 3: Living City Simulation, Traffic AI & Ambient Life
- [ ] Fix frozen `player_pos` while driving/flying (eliminates double overlapping CPU+GPU crowds)
- [ ] Fix dual `Traffic` `&"traffic_time"` conflict + bus/box-truck collision box sizing (`traffic_bodies.gd`)
- [ ] Time-of-day (rush hour / quiet night / nightlife) & weather responsiveness in `Crowd` and `Traffic`
- [ ] Richer `Crowd` routines: spatial-grid `_doors`, street walkers browsing/entering player-owned shops, bench resting, phone-checking pauses, cached `_island_traffic`
- [ ] Dynamic traffic brake lights (`traffic_path.gdshader`), emergency beacons on police/ambulance traffic, smooth `IslandLife` vehicles, `AirTraffic` nav/strobe lights & jet sound

### Track 4: Character Animation, Vehicle Experience & Audio Immersion
- [ ] Fix seated driver orientation (align to car pitch/roll/yaw without door-clipping lag) + per-vehicle cabin seats/wheel targets in `vehicle_entries.json`
- [ ] Contextual hero animations (phone-use pose, till-serving/interaction, resting) + smooth vehicle entry/exit door SFX
- [ ] Upgrade indoor `ShopPerson` (`npc.gdshader` + `shop_person.gd`: `z_scale` stride, `person_pose_idle`, smooth accel/decel, cached carry materials)
- [ ] Vehicle class differentiation (handling, suspension, braking, weight across Hatch/Van/Box/Saloon/Sports/Muscle/4x4/Supercar/Hypercar) + Craft physics polish (heli ground effect, plane landing/drag, boat planing)
- [ ] Fix `CarAudio` engine lookup (`scout`/`goliath`/`engine_sound`), fix double wind audio, wire `scrape.wav` + wet surface hiss + player horn + time-of-day/district ambience modulation, optimize `CraftAudio`

### Track 5: Interiors, Deep Economy, Lifestyle & Gameplay Reliability
- [ ] Critical bug fixes: `"phone"`→`"phones"` in `shop_interior.gd`, rival/venue door collisions, Wardrobe 7-slot unpaid revert, Flagship backroom capacity preservation, `open_property` remote fee preservation, `GET OUT` speed threshold sync, gate beta £1M cheat behind `OS.is_debug_build()`, `dt` clamp & focus/resume handlers, `ExploreUI` cache invalidation, safe save/load driving placement
- [ ] Interior immersion: interactive `"fitness"` rooms, HQ tier lobby upgrades, visual CCTV & reputation polish, functional luxury home `wardrobe` & `trophies` spots
- [ ] Deep business & economic simulation: activate `punctual`/`honest`/`ambitious` staff traits, expose `sell_estate()` UI, City500 equity investments & dividends/acquisitions (making #1 climb strategic & rewarding), competitor price-war promotions
- [ ] Lifestyle gameplay: consumable public retail items (energy/sprint buffs instead of carrying wholesale crates), Explore discovery milestone rewards, charter dispatch income for owned aircraft/yachts

### Track 6: Revolutionary Apple-Inspired Mobile UI & UX
- [ ] Fix `Phone.go()` double rebuild & 2-frame blink, preserve sidebar scroll
- [ ] Fix iPhone vs iPad landscape breakpoint + unify safe-area insets (including title screen)
- [ ] Reduce stacked `Glass.Surface` `hint_screen_texture` blur passes & stop resize `StyleBoxFlat` allocations
- [ ] Migrate key legacy Phone screens (`businesses`, `bank`, `explore`, `city`, `SkyportUI` showroom/vehicle cards, opening hours & finance selectors) to cohesive `Glass` cards with real imagery, live search, City500 "Find me", and purchase confirmation
- [ ] Transparent/theme-matched `Thumbs.vehicle()` renders
- [ ] Wardrobe Studio in-place updates (preserve scroll!) + drag-to-orbit hero preview
- [ ] Dirty-gate HUD & Minimap redraws, fix `TouchScroll` finger-ID & modal interception

### Track 7: Aggressive Intelligent Mobile Optimization
- [ ] Lazy hero material installation & unequipped garment overhead reduction (`character_rig.gd`)
- [ ] Link parked-car LODs via `visibility_parent`, pre-allocate `Traffic` MultiMesh capacity, fast far-traffic shader
- [ ] Bare depth material for `ShadowProxy`, `ShopInterior` glass `visibility_range_end` & budgeted `_stream_interiors()`, outdoor interior-light culling, pre-indexed chunk streetlights for `LampLights`
- [ ] Live `Settings.changed` propagation (shadows/glow/view_distance/crowd), static cache cleanup on reload, `Glass._materials` dark/light key fix, `Thumbs` LRU cap, continuous `_glow_nodes` pruning

### Track 8: Final Verification & TestFlight Release
- [ ] Full test suite + new regression tests pass
- [ ] `--scenarios` critical player journeys + `--autoplay` pass
- [ ] Strict Godot headless `--import` check (0 script/parse/resource errors)
- [ ] Matched AFTER screenshots & `PERF`/`RENDER_STATS` captured and visually inspected
- [ ] Commit, push to GitHub, trigger `.github/workflows/testflight.yml`, verify build & upload
