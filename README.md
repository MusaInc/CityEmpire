# City Empire (Musa Studios)

Third-person open-world business simulator on the studio's shared city.
Start as the worker, become the owner, build the empire.

Godot 4.5.1 · GDScript · Mobile renderer · Jolt physics. Independent project:
city + hero forked from CitySwing (2b8f11d), vehicles from Never Stop (e6f4bca).

- Play: `godot res://scenes/boot.tscn` (title → New game / Continue)
- Tests: `godot --headless --fixed-fps 60 -s res://tests/run_tests.gd` (City Empire suites)
- Inherited CitySwing suites: `... -s res://tests/run_tests.gd -- @inherited`
- Scripted playthrough: `godot --headless --fixed-fps 60 res://scenes/main.tscn -- --play --new --autoplay`
- Captures: `xvfb-run -a godot --rendering-method mobile res://scenes/main.tscn -- --play --new --demo=staff --goto=start --inside --hour=11 --shot=out.png --shot-at=8`
- Perf counters: same with `--perf=20` (prints PERF line; fps/ms are meaningless under llvmpipe)
- Player journeys (onboarding, GPS, car recovery, expansion, shop generation, save/load, failures):
  `xvfb-run -a godot --rendering-method mobile res://scenes/main.tscn -- --play --new --scenarios[=A,E,D,C,F,G,H]`
  (under xvfb: the maps record the route they drew; ~3 fps there, so checks wait on conditions)
- Capture helpers: `--gps=<unit id|wholesale:west|car>` (a route), `--at=x,z[,yaw]` (stand anywhere)

See docs/STATUS.md, docs/ARCHITECTURE.md, docs/SHARED_FOUNDATION.md.
