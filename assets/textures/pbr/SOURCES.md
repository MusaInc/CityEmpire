# PBR detail textures

CC0 (public domain) from Poly Haven (https://polyhaven.com), downloaded 2026-11-21,
1K JPG sets packed by `tools/textures/pack_detail.gd` into one RGBA texture each:
R = albedo luminance (mean 0.5), G/B = OpenGL normal x/y, A = roughness.

| File | Poly Haven asset | Used for |
|---|---|---|
| asphalt_01.png | asphalt_01 | streets, island roads, bridge decks |
| concrete_pavement.png | concrete_pavement | pavements, plazas |
| large_red_bricks.png | large_red_bricks | brick facades (detail only: colour stays the building's) |
| concrete_wall_008.png | concrete_wall_008 | rendered / concrete / stone facades |

CC0: no attribution required; listed here for provenance.
| metal_plate_02.png | metal_plate_02 | painted steel: bridges, gantries, kits |
| codex_concrete.png | (Codex study 04_concrete_wall, owner's) | concrete structures: pylons, viaducts, parapets |

## WorldState street and retail materials

The `worldstate_*.png` maps use original ImageGen colour studies from
`../source/codex`. They store luminance, derived relief normals and
material-specific roughness in one mipmapped texture. The outdoor maps are
1024 px square and the indoor maps are 512 px square.

| Material | Runtime use |
|---|---|
| `worldstate_street_asphalt.png` | Roadways, bridge decks and airport asphalt |
| `worldstate_pavement_concrete.png` | Pavements, forecourts, concrete floors |
| `worldstate_retail_ceramic.png` | Shop tile floors |
| `worldstate_retail_oak.png` | Wood floors in cafés and fashion shops |
| `worldstate_retail_terrazzo.png` | Electronics retail floors |
