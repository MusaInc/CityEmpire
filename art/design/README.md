# Design pass (2026-11-16): craft + walk-in venues

Design work for the "finish the game" plan, built from code so it can be
regenerated and tweaked (art/ is .gdignored; the game loads copies from
assets/craft and assets/venues):

    blender -b --factory-startup --python tools/blender/build_craft.py  -- art/design/craft  [render_dir] [ids]
    blender -b --factory-startup --python tools/blender/build_venues.py -- art/design/venues [render_dir] [ids]

The GLBs are build output (git-ignored); craft.json / venues.json record sizes,
triangle counts, node pivots and interaction marks.

## Craft (tools/blender/build_craft.py)

Replaces the box models in src/vehicle/craft_models.gd with section-lofted
bodies in the Never Stop cars' style. Ids match config/empire/vehicles.json:
wren, kite, regent (helicopters), skylark, merlin, aurora (planes), dart,
swift, majesty (boats) + liner (AirTraffic).

- Conventions: Godot -Z forward, Y up; aircraft origin on the ground, boats on
  the waterline. Sizes follow vehicles.json `size`.
- Nodes the game animates (origin = pivot): Rotor, RotorBlur, TailRotor,
  Prop / Prop_L / Prop_R, PropBlur*, Gear (retract; Skylark's is fixed),
  Outboard. Body is everything else.
- Materials: paint (owner colour), paint2 (trim colour), glass, lamp_* emissive
  (nav red/green, strobe, landing), rotor_blur (alpha), antifoul, teak, ...
- Budget: 4k (Dart) – 20k (Majesty) triangles; the cars are ~6k.

In game: CraftModels.build() loads `res://assets/craft/<id>.glb` (box models
remain the fallback), recolours paint/paint2 from the spec and keeps the
Rotor/Props/Gear node names Craft drives; CraftModels.animate() spins tail
rotors and props and swaps in the blur discs at speed.

## Venues (tools/blender/build_venues.py)

Each venue is one GLB: a static "Venue" mesh, named moving nodes, and empties
for gameplay marks (Godot coordinates in venues.json).

| id | what | nodes | marks |
|---|---|---|---|
| meridian | Meridian Prestige showroom (60×28 m of its 120×36 footprint): hypercar turntable gallery, 4 plinths with spec totems, configurator wall, sales pods, lounge + bar, handover bay, mezzanine | Door_L/R, Turntable, RollerDoor | car_*, spot_car_*, spot_turntable, spot_configurator, spot_sales_*, spot_handover, npc_* |
| kestrel | Kestrel Motors used-car showroom: tiles, bunting, price stands, desk, waiting area | Door_L/R, RollerDoor | car_*, spot_car_*, spot_sales_0 |
| arden | Maison Arden boutique: arched niches with brass rails, mannequin plinth, knitwear tables, watch counter, shoe wall, velvet fitting rooms | Door_L/R | spot_look_*, spot_watches, spot_shoes, spot_fitting, spot_till |
| threadline | Threadline everyday store: wall bays, round rails, front stage of mannequins, till, fitting rooms | Door_L/R | spot_till, spot_fitting |
| lobby | Residential lobby: street portal + canopy, concierge, mailboxes, lift landing, shaft and a real lift car | Door_L/R, LiftDoor_L/R, LiftCar, CarDoor_L/R | door_in, spot_lift_call, lift_car_floor, spot_concierge, spot_mail |
| study | Apartment study / Empire Desk: three screens, recruitment board, trophy wall, TV + sofa | – | spot_empire_desk, spot_recruitment, spot_trophies, spot_tv |
| hq | HQ floor: reception, 12 bench desks (48 seats), corner office, boardroom, empire map wall | – | spot_empire_desk, spot_boardroom, spot_map_wall, spot_reception, npc_desk_* |

Lift design: the shaft is 2.2 m square behind the landing; LiftCar (1.6×1.5 m,
mirror back, brass handrail, button panel, floor indicator) rides the guides.
In game the car is an AnimatableBody3D carrying the hero: doors close, car
rises to the apartment's floor height, doors open into the flat's hallway.

In game (meridian, kestrel, arden, threadline): Venues
(src/empire/world/venues.gd) – SkyportIsland carves each room out of the
building behind its site (0.45 m padding: flush faces z-fight), the room sits
4 cm above the island paving, gets collision, an interior ReflectionProbe
(ambient; without it floors take the zenith sky's blue), room lights, sliding
doors, turntable, display cars and walk-up points. Check: `--scenarios=XW
[--sc-film=<dir>]`. Garments are unbevelled boxes (Arden 75k, Threadline 50k
triangles). lobby / study / hq are designed but not wired in yet.
