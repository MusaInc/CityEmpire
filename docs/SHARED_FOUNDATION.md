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
