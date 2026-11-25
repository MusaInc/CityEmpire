# Vehicle texture pipeline

Answers `VEHICLE_TEXTURE_REPORT.md` (2026-11-24: 91 vehicle GLBs, no images,
collapsed UVs). All 91 now carry a real Blender unwrap and, except the door
entries (which reuse their body's), their own Blender bake.

## Run

```
tools/vehicle_tex/run.sh [name-regex]      # library + every GLB, in place, geometry-checked
tools/vehicle_tex/import_settings.sh       # VRAM compression / mipmaps / normal-map flags
godot --headless --import
```

`KIND=entry|body|wheel|craft|model` limits a run to one job type; `SKIP_LIB=1` skips the
library. The originals live in `art/vehicle_tex_orig/` (gitignored) and are always the
input, so the run is repeatable. A GLB is only replaced after
`tools/vehicle_tex/verify_geometry.py` confirms the same triangles (positions to the mm,
normals within 1 degree; sub-1 cm² slivers ignored), node names, transforms and
material slots. Bake time is about 1m45s per 2048 px body on the VPS (6 threads).

## What Blender makes (`tools/blender/ws_texture.py`)

* **Library** (`assets/vehicles/tex/<family>_n.png` + `_m.png`: R cavity, G roughness,
  B metal mask, A albedo variation). Tileable through 4D (torus) noise and Voronoi
  baked from Cycles emission. Families: paint (orange peel), leather, fabric (twill,
  also carbon weave), plastic (stipple grain), carpet, rubber, brushed, reflector
  facets, lens prisms, grille honeycomb, teak decking. The moulded wheel parts are built
  as geometry: tread pitch (displaced grid baked selected-to-active), sidewall (rim
  bands, ribs and curved lettering "WORLDSTATE / CITYGRIP SPORT 4 / 225/45 R18 94W",
  baked to a height map, then a normal map), drilled and slotted rotor, machined alloy.
* **Per model**: UV0 `Tile` = Smart UV Project (55°) scaled so 1 UV unit = 1 m. Every
  family tiles at the same physical size on every vehicle. UV1 `Bake` = the same islands
  packed into 0..0.97; the top-right strip stays white. Wheels get a cylindrical tread
  UV (8 pitches per turn) and a planar face UV (the UV circle is the tyre).
  Bake RGB: R = AO 0.55 m × 4 cm cavity, G = convex edges (bevel vs face normal),
  B = cavity. Glass and lenses are removed from a copy before baking, and road bodies
  get a ground plane. Entries (`assets/vehicle_entries`) take both UV layers from their
  processed body by BVH nearest face, so doors sample the body's bake.

Sizes: player/catalogue bodies 2048, civilian bodies and `_traffic` 1024, `_lod1` 512,
wheels 512, craft 1024 (aurora/majesty/liner 2048), rail and ship 1024, legacy cars 512.

## Godot

* `src/vehicle/vehicle_tex.gd` (VehicleTex): library and bake lookup, the
  material-name → family table (`FINISH`), `surface()` (cached) / `make_surface()`,
  `dress()` / `dress_mesh()` for craft, rail, ship and the delivery van.
  `VehicleTex.enabled = false` renders everything as before the pass.
* `src/vehicle/car_surface.gdshader`: base look + tiled detail (fades out by 30 m) +
  UV2 AO and cavity, plus stitching on convex seams for interiors and cushions.
* `car_paint.gdshader`: orange peel (within 9 m), baked AO. Reflections and sun glints
  are masked by AO, grime collects in cavities, and edges chip once `dirt` rises.
  Colour is still the `base_color` uniform, so resprays and liveries work.
* `wheel_rubber.gdshader` / `brake_rotor.gdshader`: baked tread, sidewall and rotor
  maps on the wheel unwrap (procedural fallback without UVs).
* Traffic (`traffic.gdshader`, `traffic_path.gdshader`): per-kind bake on UV2.
  Merged wheels and far boxes point at the white texel (`CityWorld._fill_uv2`).
* Dents keep all arrays, and detached panels copy UV/UV2, so damaged cars keep the look.

## Review

`tools/vehicle_tex/review.tscn` is a fixed-camera stage with the Mobile renderer:
```
xvfb-run -a godot --rendering-method mobile --resolution 1280x720 res://tools/vehicle_tex/review.tscn -- \
  --out=<abs dir> --bodies=kestrel,courier_van [--views=front34,wheel,interior,panel,tail,nose,rear34,side] [--before] [--dirt=0.6]
```
In game: `tools/vehicle_tex/capture.sh <dir> "kestrel:side_l van:rear34"`. Use the owned model
ids here (`van`, not `courier_van`).

## Known exception

`assets/vehicle_entries/goliath.glb`: two triangles (2 cm² each) inside the
headlamp housing of the cabin-opening piece keep Blender-derived normals (their
vertices are shared with conflicting neighbours, so `restore_normals.py`
leaves them). They are invisible in a dark gloss housing that only draws while
the doors animate. Positions are identical. Every other GLB passes `verify_geometry.py`.
