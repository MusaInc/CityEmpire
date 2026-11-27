# Loading: launch and menu → gameplay (2026-11-27)

All numbers are main-thread CPU on the VPS (8 cores, llvmpipe software
renderer). A phone is faster in absolute terms; the ratios are what carry
over. Frame times measured here are dominated by the software renderer and
say little about a device.

## Measure

- `--load-timing`: every build step (`LOAD_T …`), the splash's frame gaps
  (`LOAD_FRAMES`), the menu→play steps (`ENTER_T …`).
- `--enter=continue|new|character` (+ `--load-timing`, `--save=user://x.json`):
  presses the menu button once the menu settles, prints each step, the
  main-thread block, when streaming caught up and any frame over 100 ms of
  CPU (`SLOW …`). `--enter=confirm --shot-out=<png>` shoots the new-game
  warning.
- Helper used for these numbers: `enter.sh <tag> <kind>` (a fresh copy of the
  same save every run).

## Menu → gameplay (main thread blocked on the press)

| transition | before | after | what changed |
|---|---|---|---|
| New game  | 3,111 ms | 512 ms | Skyport's near detail no longer forced (1.9 s); chunks built in parallel |
| Continue  | 1,047 ms | 15–690 ms | the save isn't loaded a second time; chunks in parallel (15 ms when the menu's view already streamed the hero's street) |
| Character | 908 ms | 461 ms | as Continue |

Streaming round the hero settled: New game 5.1 s → 2.6 s; Character
7.8 s → 6.4 s; Continue ~4.7 s → 3.1–4.8 s (depends on the menu view).

### What was blocking

1. **Skyport's near detail, all at once** (`_teleport` → `load_near_now`,
   ~1.9 s): forced whenever you land within 850 m of the island – both start
   spots are. Now only within 120 m (`TELEPORT_SKYPORT_NOW`); further off it
   streams one step a frame as it always did when you travel there (no step
   over 30 ms was seen after entering).
2. **Chunks round the hero, one at a time** (`CityWorld.build_all_near`,
   0.8–1.5 s): the mesh arrays are pure data (streaming already makes them on
   workers), so they're now generated in parallel and only put in the scene
   on the main thread; chunks already streaming reuse their task.
3. **The save, twice**: the menu loads it at launch; Continue/Character loaded
   it again (empire, cars, interiors, the hero's streets). Reused now – the
   title never changes it. Returning to the title later still reloads.
4. Not a cost: shader compilation (no stall seen at entry), save restore
   itself (~5 ms), interiors (≤35 ms), HUD (~1 ms), new empire (~5 ms).

## Launch

The world was built in one go inside `EmpireGame._ready` (~15.7 s here) and
no frame was drawn meanwhile: the splash froze on navy. Now (`LoadPacer`):

- the build is a coroutine that hands a frame back every ~14 ms of work; the
  tree is paused meanwhile so nothing half-built ticks;
- the city layout (~2.3 s) is generated on a worker thread (identical city:
  `tests/test_load_async.gd`);
- tests, tools and captures still build synchronously, exactly as before.

Splash frames while loading (wall clock, VPS, `LOAD_GAP` lines): before,
one ~15 s freeze. After, the splash moves through most of the build (the
layout on a worker, the car meshes paced at ~0.1 s), but it still stops
for each step that is one big call:

| gap | step |
|---|---|
| 3.8 s, 3.8 s, 1.6 s | minimap bake (offscreen render + GPU readback), then the menu scene's first render (shader compile) – GPU work the VPS emulates on its CPU |
| 2.6 s | Hinterland build |
| 1.7 s | Landforms |
| 0.7–0.95 s | traffic setup, collision, water/structures, Skyport base |

219 frames over the load, 49 of them over 100 ms. The whole launch took
longer on the VPS (each splash frame costs ~20 ms of software rendering;
~1 ms on a phone) – check on device before judging.

Tried and dropped: building the 15 traffic car kinds on worker threads. Their
glTF merge reads and writes mesh arrays through the RenderingServer, which a
worker waits on frame by frame: 3.2 s became 11.4 s. They build on the main
thread, paced between meshes.

## Next candidates

- Car meshes (3.2 s of launch): cache the merged traffic meshes as resources
  (`user://` or baked at export) instead of merging glTFs every launch.
- Minimap bake (~4.3 s here, mostly a GPU readback of a large viewport):
  check its cost on device; render it smaller or tile it if it shows.
- Hinterland (2.6 s) and Landforms (1.7 s): the next single-call stalls;
  split them (data on a worker, nodes paced) so the splash never stops.
- First render of the menu (shader compile): warm the menu's materials
  under the splash, or ship Godot's shader cache.
