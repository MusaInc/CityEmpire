# Shared foundation: what changed in code shared with CitySwing / Never Stop

City Empire is an independent copy; nothing is linked across repos. To bring an
improvement back, copy the file/hunk and run that game's own suite.

Edits to shared code (all opt-in / default-off for the original games):
- `src/player/player.gd`: `swing_enabled` (default true), `everyday` (default false) gate webs, wall runs, scramble, long reach; stick curve uses the indoor curve when `everyday`.
- `src/player/character_rig.gd`: `carrying` flag → two-hand carry pose (default off).
- `src/world/building_mesher.gd`: no plinth on tier 0 when b["apt"]["ground"] (only set by Premises).
- `src/world/city_layout.gd`: `premises = Premises.place(self)` on both landmasses. **This changes collision** (shop rooms are cut out), so CitySwing's recorded Time Trial courses would need re-recording if merged; the inherited suite shows 4 course tests failing for this reason (+1 pre-existing test_city failure). 156/161 inherited tests pass.
- `src/input/input_setup.gd`, `src/core/settings.gd`: City Empire bindings / driving settings (game-specific, don't merge back).
- Ported from Never Stop: car.gd, car_visual.gd, car_catalog.gd, chase_camera.gd, drive_input.gd (BattleKit removed), vehicle_fx.gd (preset lookup made tolerant), road_net.gd/ai_driver.gd (unused yet).

Candidates for a real shared package later: Stock/Business/DemandModel/Empire (pure data, no city deps), ShopInterior's batcher + walk grid, Premises.

## Skyport Island (2026-11-15): reusable world content, opt-in

Built so CitySwing / Never Stop can use the same island without City Empire's
economy. Nothing in these files reads Empire, Business or the UI.
- `src/world/skyport_island.gd` (SkyportIsland): outline, districts, roads, lanes,
  runway/taxiways/aprons/helipads, buildings (CityLayout building dicts drawn by
  the shared BuildingMesher + building.gdshader), cable-stayed bridge (A-frame
  pylons and crossbeams at 34 m and 102 m above the deck: swing anchors),
  quay cranes, containers, marina piers, trees, `plan(layout)` data with named
  `sites` (games attach their own meaning). Static `enabled` (default **false**):
  only a game that sets it gets the island in `CityLayout.is_water/ground_y`,
  the RoadNet lanes and the map painter.
- `src/world/shaders/island_ground.gdshader`: one material for all island
  surfaces (kinds in vertex alpha).
- `src/world/air_traffic.gd`: scripted airliners (no physics).
- `src/vehicle/craft.gd`, `craft_models.gd`, `src/camera/craft_camera.gd`:
  helicopter/plane/boat bodies, models and follow camera; input is a plain
  dictionary (`{active, gas, kick, brake, steer}`), so Never Stop's TouchDrive
  stick can feed it the same way City Empire's drive pad does.
- Shared-code edits: `CityLayout.is_water/ground_y` (one early-out each, only
  when enabled), `RoadNet._add_skyport/_stitch_skyport` (no-ops when disabled),
  `Minimap.BOUNDS` widened to x 2520 (the baked map is ~40% wider: more
  texture memory, see STATUS perf), `MapPainter._skyport`.
- To use in CitySwing: set `SkyportIsland.enabled = true` before building the
  world, add a SkyportIsland node and call `build(layout, world)`.

City Empire-only (do not copy): `src/empire/skyport_play.gd`, `wardrobe.gd`,
`sim/ventures.gd`, `ui/skyport_ui.gd`, `ui/dashboard.gd`, `ui/thumbs.gd`.

## 0.6.1 world quality pass (2026-11-16)

Shared, still opt-in through `SkyportIsland.enabled` unless noted:
- `SkyportIsland.road_y(layout, x, z)` and `ramp_points()`: the bridge ramp
  starts under the city avenue's lowest lane and rises over the kerb to the
  deck (DECK_END 1432); `plan()` returns `rail_gap`, `homes`, `penthouse`.
- `BuildingMesher.rail_gaps` (static, default empty = no change): esplanade
  railing segments whose midpoint is in a gap are skipped (the Skyport bridge
  crosses the esplanade). CityWorld fills it only when the island is enabled.
- `BuildingMesher.roof_top(..., style)` / `cap_poly`: warehouse (style 3) roofs
  add `METAL_ROOF` (8.0) to the roof seed; building.gdshader draws them as
  ribbed metal with skylights and rust. **Affects every game's warehouses.**
- `CityInfrastructure.bridge_landing`: ramp heights ease to the street's real
  `road_y` per point (the old bridge's island end sat 0.43 m proud).
- New, game-agnostic: `src/world/shoreline.gd` + `shaders/shore_foam.gdshader`
  (foam strip along any coast polygon; CityWorld adds one for the city coast –
  **visible in every game**), `src/world/island_traffic.gd` (MultiMesh cars on
  the island lanes, crossing the bridge, reusing CityWorld car kinds),
  `src/world/island_life.gd` (moored boats, cranes, airport tug, yard truck),
  `src/audio/craft_audio.gd` (synthesised engine audio for Craft).
- City Empire-only: island pavement loops in `empire/npc/crowd.gd`, home
  records/ownership markers (`skyport_play.gd`, `ventures.gd` HOME_ESTATE).
