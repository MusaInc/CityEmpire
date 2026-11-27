# WorldState engine pass — 27 November 2026

Branch `engine-overhaul` from 0.20.0 (`c5e8795`). "Before" = a worktree of `c5e8795` with the same harness copied in.

## How it was measured

Godot 4.5.1, Linux **headless** (dummy renderer), quality 1, `--fixed-fps 30 -- --play --new --quality=1 --scenarios=BENCH`.
The bench drives a fixed route: city-centre crawl, to the centre, to Skyport, to Westbank, location transitions (home / lift / garage / interiors), then opens every phone page.
Frame times are wall-clock **CPU** frame times. There is no GPU here, so GPU time, draw calls, thermals and battery are **not measured**. The TestFlight build is for those.

## Frame times (whole bench)

| | before | after |
| --- | ---: | ---: |
| frames | 18,595 | 18,918 |
| p50 | 10.18 ms | 8.57 ms |
| p95 | 16.29 ms | 14.48 ms |
| p99 | 22.80 ms | 19.89 ms |
| frames > 33 ms | 67 | 29 |
| frames > 50 ms | 21 | 11 |
| frames > 100 ms | 6 | 2 |
| worst frame | 770 ms | 504 ms |

By phase (p99 / frames over 50 ms):

| phase | before | after |
| --- | --- | --- |
| centre crawl | 20.9 ms / 3 | 18.8 ms / 1 |
| to Skyport | 24.9 ms / 7 | 19.8 ms / 5 |
| to Westbank | 21.9 ms / 6 | 19.6 ms / 1 |
| transitions | 47.4 ms / 4 | 23.3 ms / 3 |

Phone page open (ms, first open): City500 96.9 → 71.1, property 45.5 → 42.8. Other pages are within ±10 ms (noise on this box).

## Memory (SOAK: 3 driving laps + garage round trips)

| lap | before | after |
| --- | ---: | ---: |
| 0 | 1454 MB | 1388 MB |
| 1 | 1482 MB | 1393 MB |
| 2 | 1488 MB | 1401 MB |

Static memory grows +34 MB over the laps before and +13 MB after. Node and object counts stay flat in both, so there is no leak in the node tree. Both runs passed 7/7.

## Loop check

`--scenarios=GL --sc-all` (apartment → lift → garage → car → street, all 8 homes): **136/136**.

## Still open

- One remaining long frame (≈500–730 ms) when the bench teleports between islands. It comes from Skyport unloading about 2,500 nodes at once. Normal driving never does this, but a fast-travel would.
- Dent rebuilds still re-upload the body mesh (≈10–17 ms per dent, `PROF dent`).
- `car_impact_signal` peaks at ≈33 ms on a heavy hit.
- Raw data: `bench-before.json`, `bench-after.json` (per-phase, per-system, memory every 2 s, hitch attribution).
