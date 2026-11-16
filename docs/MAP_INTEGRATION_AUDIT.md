# Map integration audit — 2026-11-16

Scope: polish the existing three-island world. Coast outlines, runway, landmarks,
bridge spans/elevations, save format, gameplay systems and streaming distances
remain unchanged.

Implemented:

- Bridge lane graphs now follow the rendered quay landing dogleg instead of
  cutting directly from the quay to Bridge Road. All three road bridges retain
  their existing validated span profiles. Tapered asphalt shoulders now blend
  both Skyport approaches sideways into the coast roads, removing the exposed
  slab edges for cross traffic. These share the existing road mesh/material.
- Skyport building records supply the actual 3 m foundation level to the shared
  building mesher. Plinths, shopfront details and awnings no longer use sea-level
  defaults. Two clothing stores were set back 14 m to clear the avenue; their
  interaction points moved with them.
- Relocated the overlapping car park out of the commercial showroom. Added four
  ramps with level turning landings, matching collision, outer guards, collidable
  parapets and a clear west aisle. Slab ends overlap 10 cm to close collision seams.
- Added a second terminal approach, parking access and a service road to the fire
  station; adjusted Hangar Lane to feed it clear of buildings and helipads. New
  intersections are explicit shared endpoints in the lane graph.
- Rounded internal road bends and replaced overlapping strip ends with shared
  mitered edges. Pavements and roads use the same curves as navigation.

Verification:

- Main regression suite: 68 passed, zero failures. One concurrent software-rendering
  run exceeded the existing economy timing limit (2,095 ms versus 1,500 ms); the
  suite was rerun after capture to separate CPU contention from map regressions.
- Inherited cleanup suite: 3 passed, zero failures (includes suspension-bridge
  approach geometry, collision, grade and public-space checks).
- B/XV driving scenarios: 18/18 checks passed, including both Skyport bridges
  in both directions at 8, 20 and 34 m/s and suspension-bridge joints at 24 m/s.
  Worst measured Skyport crossing body offset: -0.22 m; peak vertical speed:
  4.0 m/s; lateral drift: 0.1 m. These are vehicle-body measurements, not holes.
- Expanded XA/XO audit: 12/12 checks passed, including lateral coast-road
  scans across both bridge approaches. No steps/holes in 1,930 airport-road
  samples or 19,801 city-road samples; no vehicle-sized airport-road obstructions;
  all four car-park ramps have continuous collision; 632 content points remain
  on land with shore clearance.
- New regression audit checks full road widths against buildings and shore,
  building foundation heights, building/car-park overlaps, duplicate segments,
  escape routes from every island lane, and airport GPS routes through both
  bridge connections in both directions.
- Visual captures: `/tmp/world-cleanup-views/` (airport) and
  `/tmp/world-cleanup-final-views/westbank_finished.png` (finished curved shoulder). Test logs:
  `/tmp/world-regression-final.log`, `/tmp/world-inherited.log`,
  `/tmp/world-crossings-verified.log`, `/tmp/world-clearance-verified.log`,
  `/tmp/world-audit-final.log`.

Performance and limitations:

All added road geometry stays in the existing ground mesh, and parking geometry
stays in the existing car-park mesh. No new materials, textures, mesh instances,
traffic population, or streaming ranges. Navigation gains only local roads;
parking adds box collision shapes and bridge shoulders add 128 small convex
collision prisms across the two bridges. Actual device RAM/draw-call
and frame-time deltas have not been profiled. Godot shutdown resource / ObjectDB warnings persist in regression and scenario
runs and remain unresolved.
Automated sampling cannot prove the absence of every possible collision issue.
