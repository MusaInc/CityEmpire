# Musa shared foundation (WorldState · CitySwing · NEVER STOP)

All three games grew from one city (CitySwing → NEVER STOP on 6 Nov, CitySwing
+ NEVER STOP → WorldState on 13 Nov) and then diverged. Since 20 Nov 2026 the
best implementation of each system is the **reference standard**, and the
other games take it wherever it fits their design.

## Reference standard per system (audit, 20 Nov 2026)

| System | Reference | Why / what the others take |
|---|---|---|
| Vehicle bodies, glazing, interiors, lamps | WorldState (Kestrel Blender pipeline, `tools/blender/ws_*.py`) | NEVER STOP + CitySwing use the same `assets/vehicles` / fleet meshes |
| Vehicle physics, handling, damage, breakable panels | NEVER STOP (`Car`, `CarVisual`) | WorldState already runs the same `Car` (+kickdown, park lock); CitySwing now uses it for pursuits |
| Driving AI, police, pursuit | NEVER STOP (`AIDriver`, `RoadNet`, `PursuitDirector`) | `StreetPursuit` brings emergent chases to WorldState + CitySwing |
| Chase camera | NEVER STOP (size-fit per vehicle) / WorldState far clip 6.5 km | far clip ported to NEVER STOP |
| Character, faces, hair, clothing | WorldState (character_b, hero_pbr/skin) | CitySwing hero is still the 1.0 rig (App Store build) |
| Locomotion, swinging, traversal, rooftops | CitySwing | WorldState carries CitySwing's rig + gait |
| Roads, markings, junctions, roundabouts | WorldState (`city_roads.gd` + `ground.gdshader`) | merged into both; NEVER STOP keeps its expressway ring |
| Buildings, facades, shopfronts | WorldState (`building.gdshader`: age by quarter, shop kinds, graffiti) | copied to both |
| Trees, street furniture | WorldState (`TreeKit` 6 species + Blender trees; `ws_street.py` furniture) | copied to both |
| Water, coast | WorldState (`water.gdshader` wave trains, seabed depth) | shader copied (no seabed bake outside WorldState: shallow colour only) |
| Lighting, sky, atmosphere, image filter | WorldState (Crisp `look.gdshader`, lamp glow, hinterland haze) | copied to both; Crisp is the default everywhere |
| Traffic + pedestrians | WorldState (Blender fleet, lane-following, collisions) | CitySwing uses the fleet meshes; NEVER STOP keeps its physical civilians |
| Touch controls | NEVER STOP (smart stick) / CitySwing (swing) | per game |
| UI | WorldState (`Glass` design system, Inter / SF Pro) | per-game accents |
| Render budget, MetalFX, FrameGovernor | CitySwing (App Review 2.1 fix) | shared by all three |
| Saves | all atomic (.tmp → .bak → rename) | — |

## How sharing works

`tools/shared/manifest.json` lists every shared file:

* **copy** — WorldState's file is the source of truth. `tools/shared/sync.py
  --apply` copies it into the other repos (plus `.import`/`.uid` sidecars).
* **merged** — the file was 3-way merged once and keeps game-specific changes
  (e.g. NEVER STOP's expressway markings). `sync.py` reports drift; merge by
  hand with `git merge-file` against the old common version.

```
python3 tools/shared/sync.py              # what differs
python3 tools/shared/sync.py --apply      # copy the 'copy' entries
```

Commit in each repo afterwards; every game must stay independently buildable.
When a shared file improves in CitySwing or NEVER STOP first, bring it to
WorldState and sync from here so there is one copy of the truth.

## StreetPursuit

`src/shared/street_pursuit.gd`: an emergent police chase on the road graph.
A getaway car (civilian body, `AIDriver` on a wandering route) and police
units (`CarCatalog.POLICE`, beacons + siren) that follow the road it really
took, then go for it directly once close. Endings: `takedown` (the player),
`busted`, `crashed`, `escaped`.

* WorldState: rams from a vehicle count (+£2,500 "Citizen's arrest"); off
  indoors and while flying. `--pursuit` starts one at once, `--no-pursuit`
  turns them off.
* CitySwing: Open City only; land on the getaway car to stop it (+150 coins).
