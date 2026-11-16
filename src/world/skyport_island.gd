class_name SkyportIsland
extends Node3D
## Skyport Island: the third island, east of the Commercial Island, joined to
## its cliff-top avenue ("heights") by a cable-stayed landmark bridge.
##
## Shared world content (no game logic here): the outline, the four
## districts' buildings (built with the city's own BuildingMesher and
## building shader), roads and their lane graph, the airport surfaces
## (runway, taxiways, aprons, stands, helipads), the marina's piers and
## berths, and named interaction sites. A game opts in (`enabled`), builds it
## with `build()` and reads `plan()` for its own use (City Empire: dealers,
## shops, aircraft, boats, property). CitySwing / Never Stop can do the same
## without inheriting any business logic.
##
## Districts:
##   high-rise coastal (north-west): a composed skyline round the Skyport
##     Spire, towers in clusters with setbacks, a penthouse tower with a
##     rooftop helipad, a waterfront promenade;
##   retail row (along Skyport Avenue): budget, luxury and commercial car
##     dealers, two clothing stores;
##   industrial & logistics (north-east): distribution centre, warehouses,
##     container yard, quay cranes, truck yard;
##   airport (south): 1 km runway, parallel taxiway and connectors, terminal
##     with drop-off and parking, control tower, three hangars (the first is
##     the aircraft showroom), helipads, cargo terminal, stands;
##   marina (west shore): piers and berths off Marina Drive.
## Streaming: always resident – the land and roads (one mesh, one trimesh
## collision), the bridge and the plain skyline. Everything else (detailed
## buildings and their collision, airport dressing, cranes and containers,
## marina, trees, airliners) is built when the viewer comes within NEAR_LOAD
## m of the island – one piece a frame, so there's no hitch – and freed
## beyond NEAR_FREE. The city never pays for the island's detail.

const LAND_Y := 3.0
const SEA_Y := -1.6
const DETAIL_RANGE := 650.0
const NEAR_LOAD := 1200.0
const NEAR_FREE := 2000.0
const FAR_RANGE := 5200.0
const BRIDGE_ISLAND_X := 1560.0        # where the bridge road becomes Skyport Avenue (graph)
const DECK_END := 1432.0               # the deck lands on the shore here (road on land beyond)
const PYLONS := [1135.0, 1285.0]       # cable-stayed pylons (in the water)
const PYLON_TOP := 128.0
const RUNWAY := {"from": Vector3(1430.0, LAND_Y, 470.0), "to": Vector3(2430.0, LAND_Y, 470.0), "w": 45.0}
const COL_PAVE := Color(0.56, 0.56, 0.55)
const COL_GRASS := Color(0.33, 0.47, 0.26)
const COL_ROAD := Color(0.3, 0.3, 0.31)
const COL_APRON := Color(0.5, 0.5, 0.49)
const COL_RUNWAY := Color(0.26, 0.26, 0.27)

static var enabled := false
static var _plan := {}
static var _outline := PackedVector2Array()
static var _bbox := Rect2()

var plan_data := {}
var world_ref: Node   # CityWorld (materials)
var body: StaticBody3D          # detail collision (near content)
var street: StaticBody3D        # land, roads, bridge deck (always)
var near_root: Node3D           # near content, when loaded
var _target: Node = self        # where _mesh puts meshes
var _steps: Array = []          # near content still to build (one a frame)
var _check_t := 0.0
## Point the streaming measures from (the game sets it; else the camera).
var viewer: Callable


# ------------------------------------------------------------ geometry
static func outline() -> PackedVector2Array:
	if _outline.is_empty():
		_outline = PackedVector2Array([Vector2(1400, -640), Vector2(1700, -662), Vector2(2100, -655), Vector2(2400, -625),
			Vector2(2468, -540), Vector2(2482, -120), Vector2(2474, 300), Vector2(2448, 540), Vector2(2320, 592),
			Vector2(1900, 600), Vector2(1500, 592), Vector2(1408, 545), Vector2(1378, 320), Vector2(1384, 40),
			Vector2(1376, -180), Vector2(1372, -420), Vector2(1384, -580)])
		_bbox = Rect2(_outline[0], Vector2.ZERO)
		for v in _outline:
			_bbox = _bbox.expand(v)
	return _outline


static func contains(x: float, z: float) -> bool:
	if not enabled:
		return false
	outline()
	if not _bbox.has_point(Vector2(x, z)):
		return false
	return Geometry2D.is_point_in_polygon(Vector2(x, z), _outline)


## Ground height on the island (NAN off it). The bridge is not ground.
static func ground_y(x: float, z: float) -> float:
	return LAND_Y if contains(x, z) else NAN


# ---------------------------------------------------------------- plan
## Everything about the island as data. Needs the city only for where the
## bridge meets the Commercial Island's cliff-top avenue.
static func plan(layout: CityLayout) -> Dictionary:
	if not _plan.is_empty():
		return _plan
	var e := _city_end(layout)
	var a_end := _avenue_end(layout, e)
	e.y = maxf(e.y, _ramp_top(layout, a_end))   # (deck start = the ramp's top)
	var z0 := e.z
	var P := {}
	var A := Vector3(BRIDGE_ISLAND_X, LAND_Y, z0)
	var B := Vector3(1610.0, LAND_Y, z0)
	var H := Vector3(1890.0, LAND_Y, z0)
	var C := Vector3(1960.0, LAND_Y, z0)
	var D := Vector3(2330.0, LAND_Y, z0)
	var T1 := Vector3(1610.0, LAND_Y, -300.0)
	var I := Vector3(1890.0, LAND_Y, 110.0)
	var y := func(x: float, zz: float) -> Vector3: return Vector3(x, LAND_Y, zz)
	# Roads: [name, points, width]. Junctions are shared end points.
	var bridge_pts := PackedVector3Array()
	var n := 40
	for i in n + 1:
		var x := lerpf(e.x, A.x, float(i) / n)
		bridge_pts.append(Vector3(x, bridge_y(e, x), z0))
	var roads: Array = [
		["Skyport Bridge", bridge_pts, 22.0, true],
		["Skyport Avenue", PackedVector3Array([A, B]), 22.0, false],
		["Skyport Avenue", PackedVector3Array([B, H]), 22.0, false],
		["Skyport Avenue", PackedVector3Array([H, C]), 22.0, false],
		["Skyport Avenue", PackedVector3Array([C, D]), 22.0, false],
		["Tower Road", PackedVector3Array([B, T1]), 14.0, false],
		["Tower Road", PackedVector3Array([T1, y.call(1610.0, -560.0), y.call(1890.0, -560.0), H]), 14.0, false],
		["Marina Drive", PackedVector3Array([T1, y.call(1452.0, -300.0)]), 12.0, false],
		["Industrial Way", PackedVector3Array([C, y.call(1960.0, -330.0), y.call(2330.0, -330.0), D]), 16.0, false],
		["Terminal Road", PackedVector3Array([H, I]), 16.0, false],
		["Terminal Road", PackedVector3Array([I, y.call(1960.0, 150.0), y.call(2260.0, 150.0), y.call(2330.0, 80.0), D]), 16.0, false],
		["Hangar Lane", PackedVector3Array([I, y.call(1700.0, 110.0), y.call(1600.0, 140.0)]), 12.0, false],
	]
	P["roads"] = roads
	P["city_end"] = e
	P["avenue_end"] = a_end
	# The railing opening over the esplanade's sea wall, the bridge's width.
	P["rail_gap"] = Rect2(e.x - 30.0, e.z - 13.5, 60.0, 27.0)
	P["bridge_foot"] = A
	# Surfaces (areas): [kind, polygon, colour]. Kinds as island_ground.gdshader.
	var areas: Array = []
	var grass := Geometry2D.intersect_polygons(_rect(1390, 410, 2470, 600), outline())
	for g in grass:
		areas.append([1, g, COL_GRASS])
	areas.append([1, _rect(1640, -545, 1875, -380), COL_GRASS])           # tower park
	areas.append([5, _rect(1560, 170, 1880, 385), COL_APRON])              # hangar apron
	areas.append([5, _rect(1895, 242, 2330, 385), COL_APRON])              # terminal apron
	areas.append([5, _rect(2335, 160, 2462, 385), COL_APRON])              # cargo apron
	areas.append([5, _rect(1965, 58, 2255, 132), COL_APRON])               # terminal car park
	areas.append([5, _rect(1985, -150, 2160, -40), COL_APRON])             # truck yard
	areas.append([5, _rect(2140, -610, 2450, -345), COL_APRON])            # container yard
	for f in [[1630, 8, 1725, 96], [1745, 8, 1875, 96], [1975, 8, 2075, 96]]:
		areas.append([0, _rect(f[0], f[1], f[2], f[3]), Color(0.62, 0.6, 0.57)])  # dealer forecourts (paved)
	P["areas"] = areas
	# Airport strips: [kind, from, to, half width].
	var strips: Array = [
		[3, RUNWAY["from"], RUNWAY["to"], RUNWAY["w"] * 0.5],
		[4, Vector3(1470, LAND_Y, 395), Vector3(2410, LAND_Y, 395), 11.5],
	]
	for cx: float in [1480.0, 1940.0, 2400.0]:
		strips.append([4, Vector3(cx, LAND_Y, 384), Vector3(cx, LAND_Y, 470), 11.5])
	P["strips"] = strips
	P["helipads"] = [Vector3(1585, LAND_Y, 205), Vector3(1585, LAND_Y, 255), Vector3(1585, LAND_Y, 305)]
	P["stands"] = [[Vector3(1990, LAND_Y, 300), PI], [Vector3(2080, LAND_Y, 300), PI], [Vector3(2170, LAND_Y, 300), PI],
		[Vector3(2260, LAND_Y, 300), PI], [Vector3(1700, LAND_Y, 340), PI], [Vector3(1800, LAND_Y, 340), PI]]
	P["runway"] = RUNWAY
	# Marina: piers out into the strait off the west shore, berths between.
	var piers: Array = []
	var berths: Array = []
	for k in 4:
		var pz := -345.0 + k * 34.0
		piers.append([Vector3(1300, 0.6, pz - 1.5), Vector3(1386, 0.6, pz + 1.5)])
		for j in 3:
			berths.append([Vector3(1318.0 + j * 24.0, SEA_Y, pz + 12.0), -PI * 0.5])
	P["piers"] = piers
	P["berths"] = berths
	P["buildings"] = _buildings(P)
	# Named places (games attach their own meaning).
	P["sites"] = {
		"dealer_budget": {"name": "Kestrel Motors", "door": Vector3(1678, LAND_Y, 4), "lot": Rect2(1630, 8, 95, 88), "face": Vector3(0, 0, -1)},
		"dealer_luxury": {"name": "Meridian Prestige", "door": Vector3(1810, LAND_Y, 4), "lot": Rect2(1745, 8, 130, 88), "face": Vector3(0, 0, -1)},
		"dealer_commercial": {"name": "Skyport Commercials", "door": Vector3(2025, LAND_Y, 4), "lot": Rect2(1975, 8, 100, 88), "face": Vector3(0, 0, -1)},
		"clothes_everyday": {"name": "Threadline", "door": Vector3(1685, LAND_Y, -38), "face": Vector3(0, 0, 1)},
		"clothes_premium": {"name": "Maison Arden", "door": Vector3(1815, LAND_Y, -38), "face": Vector3(0, 0, 1)},
		"aviation": {"name": "Skyport Aviation", "door": Vector3(1675, LAND_Y, 300), "face": Vector3(0, 0, 1)},
		"marina": {"name": "Skyport Marina", "door": Vector3(1455, LAND_Y, -275), "face": Vector3(0, 0, -1)},
		"cargo": {"name": "Skyport Cargo", "door": Vector3(2398, LAND_Y, 155), "face": Vector3(0, 0, -1)},
		"terminal": {"name": "Skyport Airport", "door": Vector3(2110, LAND_Y, 160), "face": Vector3(0, 0, -1)},
	}
	_plan = P
	return P


static func _rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## Where the avenue's asphalt ends (the esplanade's inner edge) on the way
## to the bridge: the ramp over the esplanade runs from here to city_end.
static func _avenue_end(layout: CityLayout, e: Vector3) -> Vector3:
	var x := e.x
	while x > e.x - 60.0 and layout.block_at(x, e.z) >= 0:
		x -= 0.5
	return Vector3(x, layout.ground_y(x + 0.6, e.z), e.z)


## The ramp that carries the avenue up its kerb onto the esplanade and on
## to the deck: [start on the asphalt, top of the kerb, deck start].
## The ramp's run up to the esplanade: the avenue is cambered, so the deck
## (at its highest point across the width) sits up to ~0.9 m above the low
## lanes; over 7 m that was a 17% kick that threw cars at speed. 28 m ≈ 3%.
const RAMP_RUN := 28.0


static func ramp_points(P: Dictionary, layout: CityLayout) -> PackedVector3Array:
	var a0: Vector3 = P["avenue_end"]
	var e: Vector3 = P["city_end"]
	# Across its 22 m the avenue isn't level: start just under the lowest
	# point of the asphalt (it emerges from the road, never a lip), meet the
	# esplanade at its highest point (the pavement never pokes through).
	var lo := INF
	for dz: float in [-11.0, -5.5, 0.0, 5.5, 11.0]:
		lo = minf(lo, layout.terrain.road_y(a0.x - RAMP_RUN, a0.z + dz))
	var s0 := Vector3(a0.x - RAMP_RUN, lo - 0.03, a0.z)
	var top := _ramp_top(layout, a0)
	return PackedVector3Array([s0, Vector3(a0.x, top, a0.z), Vector3(e.x, e.y, e.z)])


## The ramp's height over the esplanade: its highest point across the
## road's width (the deck starts at this height too).
static func _ramp_top(layout: CityLayout, a0: Vector3) -> float:
	var hi := a0.y
	for dz: float in [-11.0, -5.5, 0.0, 5.5, 11.0]:
		hi = maxf(hi, layout.ground_y(a0.x + 0.6, a0.z + dz))
	return hi + 0.01


## The driving surface's height along the Skyport road (city avenue → ramp
## over the esplanade → bridge deck → island). For audits and the bridge.
static func road_y(layout: CityLayout, x: float, z: float) -> float:
	var P := plan(layout)
	var e: Vector3 = P["city_end"]
	var rp := ramp_points(P, layout)
	if x <= rp[0].x:
		return layout.terrain.road_y(x, z)
	if x <= rp[1].x:
		# (The ramp emerges from the asphalt: the surface is whichever is higher.)
		return maxf(layout.terrain.road_y(x, z), lerpf(rp[0].y, rp[1].y, (x - rp[0].x) / maxf(rp[1].x - rp[0].x, 0.01)))
	if x <= e.x:
		return lerpf(rp[1].y, rp[2].y, (x - rp[1].x) / maxf(rp[2].x - rp[1].x, 0.01))
	return bridge_y(e, x)


## Where the bridge meets the city: the last point of the "heights" avenue
## that's still on the cliff top.
static func _city_end(layout: CityLayout) -> Vector3:
	var pts: PackedVector2Array = layout.roads.by_name["heights"]["pts"] if layout and layout.roads.by_name.has("heights") else PackedVector2Array()
	var e := Vector2(1000.0, -18.0)
	for p in pts:
		if not layout.is_water(Vector3(p.x, 0.0, p.y)) and p.x > e.x - 40.0:
			e = p
	# Step back a few metres from the cliff edge; the deck starts at the
	# esplanade's own surface there (it used to start at road level, a
	# 0.24 m step up off the pavement).
	var yv := layout.ground_y(e.x - 4.0, e.y) if layout else 30.0
	return Vector3(e.x - 4.0, yv, e.y)


## Deck height along the bridge: high over the strait (ships pass under the
## main span), easing down onto the island.
## The deck falls ~29 m over ~420 m. One steady grade (~7%) with eased
## vertical curves over the first and last 12% (peak ~8%): the old hump +
## smoothstep crested at x≈1160 and then fell at up to 16%, which threw
## cars at motorway speed.
static func bridge_y(e: Vector3, x: float) -> float:
	var t := clampf((x - e.x) / (DECK_END - e.x), 0.0, 1.0)
	const F := 0.12
	var s: float
	if t < F:
		s = t * t / (2.0 * F * (1.0 - F))
	elif t > 1.0 - F:
		s = 1.0 - (1.0 - t) * (1.0 - t) / (2.0 * F * (1.0 - F))
	else:
		s = (t - F * 0.5) / (1.0 - F)
	return lerpf(e.y, LAND_Y, s)


# ----------------------------------------------------------- buildings
static func _b(tiers: Array, style: int, col: Color, seed: float, kind := "normal") -> Dictionary:
	return {"tiers": tiers, "style": style, "color": col, "kind": kind, "seed": seed}


## A tower in one of several silhouettes (all axis-aligned boxes, so the
## city's mesher, shader and collision apply as they are).
static func _tower(x: float, z: float, w: float, d: float, h: float, form: String) -> Array:
	var t: Array = []
	match form:
		"setback":
			t = [[x, z, x + w, z + d, LAND_Y, LAND_Y + h * 0.55], [x + w * 0.1, z + d * 0.1, x + w * 0.9, z + d * 0.9, LAND_Y + h * 0.55, LAND_Y + h * 0.82],
				[x + w * 0.24, z + d * 0.24, x + w * 0.76, z + d * 0.76, LAND_Y + h * 0.82, LAND_Y + h]]
		"podium":
			t = [[x, z, x + w, z + d, LAND_Y, LAND_Y + 14.0], [x + w * 0.35, z + d * 0.15, x + w * 0.95, z + d * 0.85, LAND_Y + 14.0, LAND_Y + h]]
		"stepped":
			t = [[x, z, x + w, z + d, LAND_Y, LAND_Y + h * 0.4], [x, z, x + w * 0.66, z + d, LAND_Y + h * 0.4, LAND_Y + h * 0.7],
				[x, z, x + w * 0.36, z + d * 0.7, LAND_Y + h * 0.7, LAND_Y + h]]
		"slab":
			t = [[x, z, x + w, z + d, LAND_Y, LAND_Y + h]]
		"spire":
			t = [[x, z, x + w, z + d, LAND_Y, LAND_Y + h * 0.5], [x + w * 0.12, z + d * 0.12, x + w * 0.88, z + d * 0.88, LAND_Y + h * 0.5, LAND_Y + h * 0.78],
				[x + w * 0.28, z + d * 0.28, x + w * 0.72, z + d * 0.72, LAND_Y + h * 0.78, LAND_Y + h * 0.93],
				[x + w * 0.42, z + d * 0.42, x + w * 0.58, z + d * 0.58, LAND_Y + h * 0.93, LAND_Y + h]]
	return t


static func _buildings(P: Dictionary) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var S := CityLayout.Style
	var glass_cols := [Color(0.62, 0.7, 0.76), Color(0.55, 0.6, 0.62), Color(0.7, 0.72, 0.7), Color(0.5, 0.56, 0.62)]
	# High-rise coastal district: [x, z, w, d, h, form, style]. A composed
	# skyline – the Spire on the waterfront corner, clusters stepping down
	# inland and towards the airport, gaps between them for views (and
	# swing lines).
	var towers := [
		[1660, -628, 40, 40, 272, "spire", S.GLASS],
		[1505, -560, 30, 34, 168, "setback", S.DARK_GLASS],
		[1440, -540, 34, 30, 128, "podium", S.MODERN],
		[1520, -500, 36, 28, 104, "stepped", S.GLASS],
		[1440, -480, 30, 40, 86, "slab", S.DECO],
		[1730, -628, 30, 34, 142, "podium", S.DARK_GLASS],
		[1790, -630, 40, 30, 176, "stepped", S.GLASS],
		[1850, -628, 26, 30, 96, "slab", S.MODERN],
		[1650, -360, 40, 30, 150, "setback", S.MODERN],
		[1715, -350, 30, 40, 118, "podium", S.GLASS],
		[1770, -360, 46, 34, 196, "spire", S.DARK_GLASS],
		[1830, -350, 34, 30, 74, "stepped", S.DECO],
		[1650, -280, 34, 36, 92, "slab", S.GLASS],
		[1800, -280, 36, 34, 132, "setback", S.GLASS],
		[1650, -205, 70, 30, 44, "slab", S.DECO],                # mid-rise offices
		[1760, -205, 50, 30, 64, "stepped", S.MODERN],
		[1835, -205, 36, 36, 38, "slab", S.STONE],
		[1490, -420, 30, 30, 48, "slab", S.SANDSTONE],
	]
	for t in towers:
		var col: Color = glass_cols[rng.randi() % glass_cols.size()] if int(t[6]) in [S.GLASS, S.DARK_GLASS] else \
			[Color(0.82, 0.79, 0.72), Color(0.74, 0.74, 0.72), Color(0.66, 0.62, 0.56)][rng.randi() % 3]
		var b := _b(_tower(t[0], t[1], t[2], t[3], t[4], t[5]), int(t[6]), col, rng.randf())
		b["district"] = "highrise"
		out.append(b)
	# Three towers with a home inside (HomeInteriors via Apartments-style
	# records: their walls and collision are cut round the room and window):
	#   the Skyport Penthouse on the waterfront corner, its window wall facing
	#   west straight across the strait at the city (nothing in between);
	#   a suite at the top of the Skyport Hotel, looking north over the park;
	#   the Marina Quay show flat, looking west over the marina.
	var homes: Array = []
	var pt := _b([[1430, -630, 1474, -594, LAND_Y, LAND_Y + 130.0], [1436, -627.3, 1456.3, -600.7, LAND_Y + 130.0, LAND_Y + 145.0]],
		S.DARK_GLASS, Color(0.5, 0.56, 0.62), 0.47)
	out.append(pt)
	homes.append(_home(pt, 1, 3, 4, "skyport_penthouse", "Skyport Penthouse", LAND_Y + 133.6))
	homes[-1]["lift"] = Vector3(1426.5, LAND_Y, -614.0)   # (the window is on the narrower top: the lobby is below on the base)
	var ht := _b([[1720, -270, 1770, -240, LAND_Y, LAND_Y + 17.0], [1730, -270, 1754.6, -251.7, LAND_Y + 17.0, LAND_Y + 61.0]],
		S.MODERN, Color(0.82, 0.79, 0.72), 0.36)
	out.append(ht)
	homes.append(_home(ht, 1, 2, 3, "skyport_suite", "Skyport Hotel Suite", LAND_Y + 49.4))
	var mq := _b([[1430, -420, 1464, -390, LAND_Y, LAND_Y + 40.0], [1430, -420, 1444.3, -403.4, LAND_Y + 40.0, LAND_Y + 52.0]],
		S.MODERN, Color(0.74, 0.74, 0.72), 0.58)
	out.append(mq)
	homes.append(_home(mq, 1, 3, 1, "skyport_flat", "Marina Quay Show Flat", LAND_Y + 43.6))
	P["homes"] = homes
	P["penthouse"] = {"pad": Vector3(1446.15, LAND_Y + 145.0, -614.0)}
	(P["helipads"] as Array).append(P["penthouse"]["pad"])
	# Retail row on Skyport Avenue: dealers (glazed showrooms behind their
	# forecourts) and two clothing stores.
	out.append(_b([[1640, 66, 1720, 96, LAND_Y, LAND_Y + 8.0]], S.MODERN, Color(0.86, 0.85, 0.8), 0.31, "normal"))
	out.append(_b([[1750, 60, 1870, 96, LAND_Y, LAND_Y + 11.0]], S.DARK_GLASS, Color(0.2, 0.22, 0.25), 0.62, "normal"))
	out.append(_b([[1980, 60, 2072, 96, LAND_Y, LAND_Y + 10.0]], S.WAREHOUSE, Color(0.62, 0.64, 0.66), 0.17, "normal"))
	out.append(_b([[1662, -66, 1708, -42, LAND_Y, LAND_Y + 9.0]], S.BRICK, Color(0.66, 0.4, 0.32), 0.44, "normal"))
	out.append(_b([[1790, -70, 1840, -42, LAND_Y, LAND_Y + 11.0]], S.STONE, Color(0.84, 0.81, 0.74), 0.77, "normal"))
	# Industrial & logistics.
	var ind := [[1985, -305, 2160, -170, 16.0], [2180, -305, 2312, -200, 12.0], [2180, -180, 2312, -40, 12.0],
		[1975, -600, 2055, -360, 14.0], [2065, -600, 2130, -360, 11.0], [2350, -300, 2448, -40, 13.0]]
	for r in ind:
		out.append(_b([[r[0], r[1], r[2], r[3], LAND_Y, LAND_Y + r[4]]], S.WAREHOUSE,
			[Color(0.6, 0.62, 0.64), Color(0.42, 0.5, 0.58), Color(0.55, 0.52, 0.48)][rng.randi() % 3], rng.randf()))
	# Airport: terminal (long glass hall on a stone base), control tower,
	# hangars, cargo terminal.
	out.append(_b([[1962, 168, 2258, 236, LAND_Y, LAND_Y + 9.0], [1975, 172, 2245, 232, LAND_Y + 9.0, LAND_Y + 18.0]], S.GLASS,
		Color(0.6, 0.68, 0.74), 0.12))
	out.append(_b([[2284, 198, 2298, 212, LAND_Y, LAND_Y + 52.0], [2280, 194, 2302, 216, LAND_Y + 52.0, LAND_Y + 60.0]], S.DARK_GLASS,
		Color(0.25, 0.3, 0.34), 0.58))
	for k in 3:
		var hx := 1640.0 + k * 80.0
		out.append(_b([[hx, 190, hx + 72, 288, LAND_Y, LAND_Y + 20.0]], S.WAREHOUSE, Color(0.78, 0.79, 0.8), 0.2 + k * 0.1))
	out.append(_b([[2340, 170, 2455, 290, LAND_Y, LAND_Y + 15.0]], S.WAREHOUSE, Color(0.45, 0.52, 0.6), 0.9))
	# Marina office and boat sales.
	out.append(_b([[1400, -268, 1462, -238, LAND_Y, LAND_Y + 7.0]], S.MODERN, Color(0.9, 0.9, 0.88), 0.66))
	return out


## An Apartments-format home in building b, tier ti, behind face k (its
## window wall), the HomeInteriors plan `tier` (Apartments.TIERS), floor at
## y0. Marks b with "apt" so its walls and collision are cut round it.
static func _home(b: Dictionary, ti: int, k: int, tier: int, id: String, nm: String, y0: float) -> Dictionary:
	var spec: Dictionary = Apartments.TIERS[tier]
	var t: Array = b["tiers"][ti]
	var f := BuildingMesher._face(t, k)
	var flen: float = f[3]
	var depth := float(t[3]) - float(t[1]) if k % 2 == 0 else float(t[2]) - float(t[0])
	var oa0 := (flen - float(spec["open_w"])) * 0.5
	var c := {"b": b, "t": ti, "face": k, "a0": Apartments.WALL, "a1": flen - Apartments.WALL, "y0": y0, "y1": y0 + float(spec["h"]),
		"oa0": oa0, "oa1": oa0 + float(spec["open_w"]), "oy0": y0 + float(spec["sill"]),
		"oy1": y0 + float(spec["sill"]) + float(spec["open_h"]), "depth": depth - Apartments.WALL,
		"id": id, "tier": tier, "name": nm, "price": 0}
	c["wins"] = Apartments.facade_windows(c)
	var facade := c.duplicate()
	facade["b"] = b.duplicate()
	b["apt"] = facade
	return c


# ---------------------------------------------------------------- build
## Builds meshes and collision under this node. `world` gives the city's
## building material (so the island matches the city exactly).
var _layout: CityLayout


func build(layout: CityLayout, world: Node) -> void:
	world_ref = world
	_layout = layout
	plan_data = plan(layout)
	street = StaticBody3D.new()
	street.name = "Ground"
	street.collision_layer = 1 << 3
	add_child(street)
	_build_ground(street)
	add_child(Shoreline.build(Shoreline.polygon_edges(outline())))
	_build_skyline()
	_build_bridge(street)


## Is the near content loaded (all of it)?
func near_loaded() -> bool:
	return near_root != null and _steps.is_empty()


## Builds the near content now, all at once (tests, teleports).
func load_near_now() -> void:
	if near_root == null:
		_start_near()
	while not _steps.is_empty():
		(_steps.pop_front() as Callable).call()


func _start_near() -> void:
	near_root = Node3D.new()
	near_root.name = "Near"
	add_child(near_root)
	body = StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1 | (1 << 1)
	near_root.add_child(body)
	var near_street := StaticBody3D.new()
	near_street.name = "NearGround"
	near_street.collision_layer = 1 << 3
	near_root.add_child(near_street)
	_steps = [
		func(): _near(_build_detail.bind("wn")), func(): _near(_build_detail.bind("ws")),
		func(): _near(_build_detail.bind("en")), func(): _near(_build_detail.bind("es")),
		func(): _near(_build_airport_dressing), func(): _near(_build_marina.bind(near_street)),
		func(): _near(_build_industry), func(): _near(_build_trees),
		func():
			var at := AirTraffic.new()
			at.name = "AirTraffic"
			near_root.add_child(at)
			at.setup(plan_data),
		func():
			var tr := IslandTraffic.new()
			tr.name = "Traffic"
			near_root.add_child(tr)
			tr.setup(_layout, world_ref),
		func():
			for h: Dictionary in plan_data.get("homes", []):
				near_root.add_child(HomeInteriors.build(h, _bmat())),
		func():
			var lf := IslandLife.new()
			lf.name = "Life"
			near_root.add_child(lf)
			lf.setup(plan_data),
	]


func _near(f: Callable) -> void:
	if near_root == null:
		return
	_target = near_root
	f.call()
	_target = self


func _free_near() -> void:
	_steps.clear()
	if near_root:
		near_root.queue_free()
	near_root = null
	body = null


## Distance from p to the island (0 on it).
static func distance_to(p: Vector3) -> float:
	outline()
	var q := Vector2(p.x, p.z)
	if _bbox.has_point(q):
		return 0.0
	return Vector2(clampf(q.x, _bbox.position.x, _bbox.end.x), clampf(q.y, _bbox.position.y, _bbox.end.y)).distance_to(q)


func _process(_dt: float) -> void:
	if plan_data.is_empty():
		return
	if not _steps.is_empty():
		(_steps.pop_front() as Callable).call()
		return
	_check_t -= _dt
	if _check_t > 0.0:
		return
	_check_t = 0.5
	var p: Vector3
	if viewer.is_valid():
		p = viewer.call()
	else:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		p = cam.global_position
	var d := distance_to(p)
	if near_root == null and d < NEAR_LOAD:
		_start_near()
	elif near_root != null and d > NEAR_FREE:
		_free_near()


func _ground_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://src/world/shaders/island_ground.gdshader")
	return m


## A flat polygon at height y, kind k (UV = world x/z).
static func _poly_tris(st: SurfaceTool, poly: PackedVector2Array, yv: float, kind: int, col: Color) -> void:
	# (One winding for every polygon, so all faces point up.)
	if not Geometry2D.is_polygon_clockwise(poly):
		poly = poly.duplicate()
		poly.reverse()
	var tri := Geometry2D.triangulate_polygon(poly)
	var c := Color(col.r, col.g, col.b, (kind + 0.5) / 8.0)
	for i in range(0, tri.size(), 3):
		for j in [0, 1, 2]:   # (front faces up: the same winding as _strip)
			var v := poly[tri[i + j]]
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v.x, v.y))
			st.set_uv2(Vector2(0, 0))
			st.add_vertex(Vector3(v.x, yv, v.y))


## A strip along a polyline (UV.x metres across from the centre, UV.y
## metres along; UV2 = half width, total length).
static func _strip(st: SurfaceTool, pts: PackedVector3Array, hw: float, lift: float, kind: int, col: Color) -> void:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	var c := Color(col.r, col.g, col.b, (kind + 0.5) / 8.0)
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		d.y = 0.0
		var L := (b - a).length()
		if L < 0.01:
			continue
		var s := Vector3(-d.z, 0.0, d.x).normalized() * hw
		# (Overlap 0.5 m at bends so the joins leave no slivers.)
		var ext := d.normalized() * (0.5 if i < pts.size() - 2 else 0.0)
		var q := [a - s, a + s, b + s + ext, b - s + ext]
		var u := [Vector2(-hw, acc), Vector2(hw, acc), Vector2(hw, acc + L + ext.length()), Vector2(-hw, acc + L + ext.length())]
		for j in [0, 2, 1, 0, 3, 2]:
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.set_uv(u[j])
			st.set_uv2(Vector2(hw, total))
			st.add_vertex((q[j] as Vector3) + Vector3.UP * lift)
		acc += L


func _build_ground(street: StaticBody3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Layers, bottom up: grass everywhere; paving (pavements along every road,
	# forecourts round every building, the high-rise plaza and the marina
	# quay); the planted areas on top of that; concrete aprons and yards;
	# airport strips; roads. (It was one sheet of beige paving.)
	_poly_tris(st, outline(), LAND_Y, 1, COL_GRASS)
	var pave_y := LAND_Y + 0.008
	for r in plan_data["roads"]:
		if not r[3]:
			_strip(st, r[1], float(r[2]) * 0.5 + 5.0, 0.008, 0, COL_PAVE)
	for b: Dictionary in plan_data["buildings"]:
		var t: Array = b["tiers"][0]
		var g := 6.0 if float(t[5]) - float(t[4]) > 40.0 else 4.0
		_poly_tris(st, _rect(float(t[0]) - g, float(t[1]) - g, float(t[2]) + g, float(t[3]) + g), pave_y, 0, COL_PAVE)
	for pr in [[1385, -480, 1475, -200], [1955, 135, 2265, 168]]:
		var poly := Geometry2D.intersect_polygons(_rect(pr[0], pr[1], pr[2], pr[3]), outline())
		for q in poly:
			_poly_tris(st, q, pave_y, 0, COL_PAVE.lightened(0.04))
	for a in plan_data["areas"]:
		_poly_tris(st, a[1], LAND_Y + (0.011 if int(a[0]) == 1 else 0.014), int(a[0]), a[2])
	for s in plan_data["strips"]:
		_strip(st, PackedVector3Array([s[1], s[2]]), s[3], 0.025 if int(s[0]) == 3 else 0.02, int(s[0]), COL_RUNWAY if int(s[0]) == 3 else COL_APRON.darkened(0.15))
	for r in plan_data["roads"]:
		if r[3]:
			continue  # (the bridge deck draws its own road)
		_strip(st, r[1], float(r[2]) * 0.5, 0.03, 2, COL_ROAD)
	for hp: Vector3 in plan_data["helipads"]:
		if hp.y > LAND_Y + 1.0:
			continue
		_pad(st, hp, LAND_Y + 0.035)
	# Cliff / quay skirt round the edge down to the sea bed.
	var o := outline()
	var c := Color(0.55, 0.53, 0.5, 0.5 / 8.0)
	for i in o.size():
		var a := o[i]
		var b := o[(i + 1) % o.size()]
		var n := Vector3(b.y - a.y, 0.0, -(b.x - a.x)).normalized()
		var q := [Vector3(a.x, LAND_Y, a.y), Vector3(b.x, LAND_Y, b.y), Vector3(b.x, -9.0, b.y), Vector3(a.x, -9.0, a.y)]
		for j in [0, 1, 2, 0, 2, 3]:
			st.set_color(c)
			st.set_normal(n)
			st.set_uv(Vector2((q[j] as Vector3).x + (q[j] as Vector3).z, (q[j] as Vector3).y))
			st.set_uv2(Vector2.ZERO)
			st.add_vertex(q[j])
	var mi := MeshInstance3D.new()
	mi.name = "GroundMesh"
	mi.mesh = st.commit()
	mi.material_override = _ground_mat()
	mi.visibility_range_end = FAR_RANGE
	add_child(mi)
	# Collision: the land as solid slabs (one convex prism per triangle of
	# the outline, 12 m deep). A zero-thickness trimesh let a car that hit
	# the deck/land joint sink through it and sit on its belly.
	var o2 := outline()
	var tri := Geometry2D.triangulate_polygon(o2)
	for i in range(0, tri.size(), 3):
		var pts := PackedVector3Array()
		for j in 3:
			var v := o2[tri[i + j]]
			pts.append(Vector3(v.x, LAND_Y, v.y))
			pts.append(Vector3(v.x, LAND_Y - 12.0, v.y))
		var cp := ConvexPolygonShape3D.new()
		cp.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = cp
		street.add_child(cs)


static func _pad(st: SurfaceTool, c: Vector3, yv: float) -> void:
	var col := Color(0.32, 0.34, 0.36, 6.5 / 8.0)
	var r := 10.0
	var q := [Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)]
	for j in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2((q[j] as Vector3).x, (q[j] as Vector3).z))
		st.set_uv2(Vector2.ZERO)
		st.add_vertex(Vector3(c.x, yv, c.z) + q[j])


func _bmat() -> Material:
	return world_ref.get("building_mat") if world_ref else StandardMaterial3D.new()


func _mesh(m: BuildingMesher, nm: String, range_begin: float, range_end: float) -> void:
	if m.is_empty():
		return
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.arrays())
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = am
	mi.material_override = _bmat()
	mi.visibility_range_begin = range_begin
	mi.visibility_range_end = range_end
	_target.add_child(mi)


func _groups() -> Dictionary:
	var groups := {}
	for b: Dictionary in plan_data["buildings"]:
		var t0: Array = b["tiers"][0]
		var key := "w" if float(t0[0]) < 1940.0 else "e"
		key += "n" if float(t0[1]) < 0.0 else "s"
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(b)
	return groups


## The plain skyline (always resident; shows from the city).
func _build_skyline() -> void:
	var groups := _groups()
	for key in groups:
		var far := BuildingMesher.new()
		for b: Dictionary in groups[key]:
			far.add_building(b, false)
		_mesh(far, "Skyline_" + key, DETAIL_RANGE - 20.0, FAR_RANGE)


## One district's detailed buildings and their collision (near content).
func _build_detail(key: String) -> void:
	var near := BuildingMesher.new()
	for b: Dictionary in _groups().get(key, []):
		near.add_building(b, true)
		near.add_features(b)
		for bx in BuildingMesher.collision_boxes(b):
			CityWorld._add_box(body, bx)
	_mesh(near, "Detail_" + key, 0.0, DETAIL_RANGE)
	if key == "wn":
		# Penthouse rooftop helipad (on the tower's top).
		var pad: Vector3 = plan_data["penthouse"]["pad"]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_pad(st, pad, pad.y + 0.05)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _ground_mat()
		mi.visibility_range_end = 1500.0
		_target.add_child(mi)


## The landmark: a cable-stayed bridge on two white A-frame pylons, the
## deck high over the strait, easing down onto the island.
func _build_bridge(street: StaticBody3D) -> void:
	# (The bridge's railings, piers and pylons: always resident, like the deck.)
	var bridge_body := StaticBody3D.new()
	bridge_body.name = "BridgeCollision"
	bridge_body.collision_layer = 1 | (1 << 1)
	add_child(bridge_body)
	var e: Vector3 = plan_data["city_end"]
	var road: Array = plan_data["roads"][0]
	var pts: PackedVector3Array = road[1]
	var m := BuildingMesher.new()
	var white := Color(0.88, 0.88, 0.86)
	var deck_c := Color(0.42, 0.43, 0.45)
	var z0 := e.z
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if a.x >= DECK_END - 0.5:
			continue   # (on the island the road is on the land itself)
		if b.x > DECK_END:
			b = Vector3(DECK_END, bridge_y(e, DECK_END), b.z)
		var d := (b - a).normalized()
		var ext := d * 0.3
		var a0 := a - ext + Vector3.DOWN * 0.8
		var b0 := b + ext + Vector3.DOWN * 0.8
		m.beam(a0, b0, 26.0, 1.6, deck_c)
		_box_beam(street, a0, b0, 26.0, 1.6)
		for sg: float in [-1.0, 1.0]:
			var o := Vector3(0, 0, sg * 12.6)
			m.beam(a + o + Vector3.UP * 0.55, b + o + Vector3.UP * 0.55, 0.5, 1.1, white)
			_box_beam(bridge_body, a + o + Vector3.UP * 0.55, b + o + Vector3.UP * 0.55, 0.5, 1.1)
			m.beam(a + Vector3(0, -1.9, sg * 11.0) - ext, b + Vector3(0, -1.9, sg * 11.0) + ext, 1.2, 1.6, white)  # edge girders
	# Approach piers on land (island side) every 30 m.
	var x := DECK_END - 30.0
	while x > 1300.0:
		var yy := bridge_y(e, x)
		if yy - LAND_Y > 3.5:
			for sg: float in [-1.0, 1.0]:
				m.beam(Vector3(x, LAND_Y - 0.5, z0 + sg * 7.0), Vector3(x, yy - 1.6, z0 + sg * 7.0), 1.6, 1.6, white)
				_box_beam(bridge_body, Vector3(x, LAND_Y - 0.5, z0 + sg * 7.0), Vector3(x, yy - 1.6, z0 + sg * 7.0), 1.6, 1.6)
		x -= 30.0
	# Pylons: A-frames from the water, legs meeting above the deck, three
	# crossbeams (one under the deck carries it), cables fanning to the deck.
	for px: float in PYLONS:
		var dy := bridge_y(e, px)
		for sg: float in [-1.0, 1.0]:
			var foot := Vector3(px, -6.0, z0 + sg * 16.0)
			var head := Vector3(px, PYLON_TOP, z0 + sg * 2.2)
			m.beam(foot, head, 4.2, 4.2, white)
			_box_beam(bridge_body, foot, head, 4.2, 4.2)
		for cy: float in [dy - 2.2, dy + 34.0, PYLON_TOP - 26.0]:
			var t := (cy + 6.0) / (PYLON_TOP + 6.0)
			var half := lerpf(16.0, 2.2, t)
			m.beam(Vector3(px, cy, z0 - half), Vector3(px, cy, z0 + half), 3.0, 3.0, white)
			_box_beam(bridge_body, Vector3(px, cy, z0 - half), Vector3(px, cy, z0 + half), 3.0, 3.0)
		m.solid(px - 9.0, z0 - 22.0, px + 9.0, z0 + 22.0, -8.0, 0.6, Color(0.6, 0.6, 0.58))   # pier cap at the water
		_box_beam(bridge_body, Vector3(px, -8.0, z0), Vector3(px, 0.6, z0), 18.0, 44.0)
		for sg: float in [-1.0, 1.0]:
			for k in 11:
				var off := 18.0 + k * 13.0
				for dir: float in [-1.0, 1.0]:
					var dx := px + dir * off
					if dx < e.x + 6.0 or dx > DECK_END - 4.0:
						continue
					var anchor := Vector3(dx, bridge_y(e, dx) + 0.4, z0 + sg * 11.6)
					var top := Vector3(px, PYLON_TOP - 6.0 - k * 4.2, z0 + sg * 2.6)
					m.beam(anchor, top, 0.28, 0.28, Color(0.95, 0.95, 0.93))
	# Deck lamps every 36 m.
	var lx := e.x + 18.0
	while lx < BRIDGE_ISLAND_X:
		var ly := bridge_y(e, lx)
		for sg: float in [-1.0, 1.0]:
			m.beam(Vector3(lx, ly, z0 + sg * 12.2), Vector3(lx, ly + 7.5, z0 + sg * 12.2), 0.22, 0.22, Color(0.25, 0.26, 0.28))
			m.beam(Vector3(lx, ly + 7.4, z0 + sg * 12.2), Vector3(lx, ly + 7.4, z0 + sg * 10.6), 0.2, 0.2, Color(0.25, 0.26, 0.28))
		lx += 36.0
	_mesh(m, "Bridge", 0.0, FAR_RANGE)
	# Road surface on the deck.
	# The ramp from the avenue over the esplanade to the deck (collision
	# slabs whose tops are the road line, and its road surface).
	var rp := ramp_points(plan_data, _layout)
	for i in rp.size() - 1:
		var u := rp[i]
		var v := rp[i + 1]
		var dn := Vector3.DOWN * 0.4
		_box_beam(street, u + dn, v + dn + (v - u).normalized() * 0.2, 22.0, 0.8)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_strip(st, pts, 11.0, 0.03, 7, COL_ROAD)
	if rp.size() >= 2:
		_strip(st, rp, 11.0, 0.03, 2, COL_ROAD)
	var mi := MeshInstance3D.new()
	mi.name = "BridgeRoad"
	mi.mesh = st.commit()
	mi.material_override = _ground_mat()
	mi.visibility_range_end = 2600.0
	add_child(mi)


static func _box_beam(b: StaticBody3D, a: Vector3, c: Vector3, w: float, h: float) -> void:
	var L := a.distance_to(c)
	if L < 0.01:
		return
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, L)
	cs.shape = bs
	cs.transform = Transform3D(BuildingMesher.beam_basis(a, c), (a + c) * 0.5)
	b.add_child(cs)


## Airport dressing: runway edge lights, a windsock mast, stand markings and
## parked ground equipment (static boxes), approach lights over the water.
func _build_airport_dressing() -> void:
	var m := BuildingMesher.new()
	var rw: Dictionary = RUNWAY
	var a: Vector3 = rw["from"]
	var b: Vector3 = rw["to"]
	var hw: float = float(rw["w"]) * 0.5 + 1.2
	var x := a.x
	while x <= b.x:
		for sg: float in [-1.0, 1.0]:
			m.solid(x - 0.25, a.z + sg * hw - 0.25, x + 0.25, a.z + sg * hw + 0.25, LAND_Y, LAND_Y + 0.45, Color(0.95, 0.92, 0.75))
		x += 60.0
	# Approach light bars out over the water at both ends.
	for end: Array in [[a.x, -1.0], [b.x, 1.0]]:
		for k in 6:
			var ax: float = float(end[0]) + float(end[1]) * (30.0 + k * 30.0)
			m.solid(ax - 0.4, a.z - 8.0, ax + 0.4, a.z + 8.0, LAND_Y - 4.0 + 3.0, LAND_Y + 0.6, Color(0.35, 0.36, 0.38))
			m.solid(ax - 0.3, a.z - 0.3, ax + 0.3, a.z + 0.3, SEA_Y - 2.0, LAND_Y, Color(0.35, 0.36, 0.38))
	# Ground service: tugs and baggage carts by the stands.
	for s: Array in plan_data["stands"]:
		var p: Vector3 = s[0]
		m.solid(p.x - 20.0, p.z - 26.0, p.x - 16.0, p.z - 22.5, LAND_Y, LAND_Y + 1.6, Color(0.92, 0.75, 0.15))
		m.solid(p.x + 16.0, p.z - 26.0, p.x + 22.0, p.z - 23.0, LAND_Y, LAND_Y + 1.2, Color(0.75, 0.76, 0.78))
	# Windsock mast.
	m.beam(Vector3(1500, LAND_Y, 430), Vector3(1500, LAND_Y + 8.0, 430), 0.2, 0.2, Color(0.9, 0.9, 0.9))
	m.beam(Vector3(1500, LAND_Y + 7.6, 430), Vector3(1503.5, LAND_Y + 7.3, 430), 0.7, 0.7, Color(0.95, 0.45, 0.1))
	# Terminal canopy over the drop-off.
	m.solid(1980, 150, 2240, 168, LAND_Y + 5.2, LAND_Y + 5.6, Color(0.85, 0.86, 0.88))
	for k in 9:
		m.beam(Vector3(1990 + k * 30.0, LAND_Y, 152), Vector3(1990 + k * 30.0, LAND_Y + 5.2, 152), 0.35, 0.35, Color(0.5, 0.52, 0.55))
	# Control tower cab glass ring and a radar on top.
	m.solid(2281, 195, 2301, 215, LAND_Y + 60.0, LAND_Y + 61.0, Color(0.85, 0.85, 0.85))
	m.beam(Vector3(2291, LAND_Y + 61.0, 205), Vector3(2291, LAND_Y + 64.0, 205), 0.4, 0.4, Color(0.8, 0.8, 0.8))
	m.beam(Vector3(2288, LAND_Y + 64.0, 205), Vector3(2294, LAND_Y + 64.0, 205), 0.4, 1.2, Color(0.9, 0.9, 0.9))
	# Hangar doors (dark, ribbed by the warehouse style) facing the apron.
	for k in 3:
		var hx := 1640.0 + k * 80.0
		m.solid(hx + 6.0, 287.6, hx + 66.0, 288.4, LAND_Y, LAND_Y + 15.0, Color(0.3, 0.33, 0.36))
	_mesh(m, "AirportDressing", 0.0, 1400.0)


func _build_marina(street: StaticBody3D) -> void:
	var m := BuildingMesher.new()
	var wood := Color(0.55, 0.42, 0.3)
	for pr: Array in plan_data["piers"]:
		var a: Vector3 = pr[0]
		var b: Vector3 = pr[1]
		m.solid(a.x, a.z, b.x, b.z, 0.2, 0.6, wood)
		CityWorld._add_box(street, AABB(Vector3(a.x, 0.2, a.z), Vector3(b.x - a.x, 0.4, b.z - a.z)))
		var x := a.x
		while x < b.x:
			m.solid(x - 0.2, a.z - 0.4, x + 0.2, a.z, SEA_Y - 3.0, 1.4, Color(0.35, 0.3, 0.25))
			x += 8.0
	# A ramp from the quay down to the pier level.
	m.solid(1386, -360, 1400, -230, 0.6, LAND_Y, Color(0.7, 0.7, 0.68))
	CityWorld._add_box(street, AABB(Vector3(1386, 0.0, -360), Vector3(14, LAND_Y, 130)))
	_mesh(m, "Marina", 0.0, 1400.0)


## Street trees along Skyport Avenue and Tower Road, and clumps in the
## parks (the city's own tree mesh, one MultiMesh).
func _build_trees() -> void:
	var xfs: Array = []
	var e: Vector3 = plan_data["city_end"]
	var x := BRIDGE_ISLAND_X + 20.0
	while x < 2320.0:
		if absf(x - 1610.0) > 14.0 and absf(x - 1890.0) > 14.0 and absf(x - 1960.0) > 14.0:
			for sg: float in [-1.0, 1.0]:
				xfs.append(Transform3D(Basis(Vector3.UP, x * 0.37), Vector3(x, LAND_Y, e.z + sg * 15.0)))
		x += 18.0
	var zz := -540.0
	while zz < -40.0:
		for xx: float in [1597.0, 1623.0, 1877.0, 1903.0]:
			xfs.append(Transform3D(Basis(Vector3.UP, zz * 0.51), Vector3(xx, LAND_Y, zz)))
		zz += 20.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 70:
		var p := Vector3(rng.randf_range(1650, 1870), LAND_Y, rng.randf_range(-540, -390))
		if rng.randf() < 0.5:
			p = Vector3(rng.randf_range(1410, 1610), LAND_Y, rng.randf_range(15, 155))
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), p))
	# TreeKit species (avenues mostly one kind, parks mixed), one MultiMesh
	# per species.
	var by_sp := {}
	for xf: Transform3D in xfs:
		var park := absf(xf.origin.z - e.z) > 20.0
		var sp := TreeKit.pick(xf.origin, park)
		if not by_sp.has(sp):
			by_sp[sp] = []
		by_sp[sp].append(Transform3D(TreeKit.shape(xf.origin, xf.basis.get_scale().y), xf.origin))
	for sp: String in by_sp:
		var list: Array = by_sp[sp]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = TreeKit.mesh(sp)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_custom_data(i, TreeKit.tint((list[i] as Transform3D).origin, sp))
		var mi := MultiMeshInstance3D.new()
		mi.name = "Trees_" + sp
		mi.multimesh = mm
		mi.visibility_range_end = 900.0
		_target.add_child(mi)


## Container stacks and quay cranes in the logistics district.
func _build_industry() -> void:
	var m := BuildingMesher.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	var cols := [Color(0.7, 0.2, 0.15), Color(0.15, 0.35, 0.6), Color(0.85, 0.55, 0.1), Color(0.2, 0.5, 0.3),
		Color(0.55, 0.55, 0.57), Color(0.5, 0.15, 0.4)]
	var z := -595.0
	while z < -360.0:
		var x := 2150.0
		while x < 2440.0:
			if rng.randf() < 0.82:
				var h := 1 + rng.randi() % 4
				for k in h:
					m.solid(x, z, x + 12.0, z + 2.4, LAND_Y + k * 2.6, LAND_Y + (k + 1) * 2.6 - 0.05, cols[rng.randi() % cols.size()])
				CityWorld._add_box(body, AABB(Vector3(x, LAND_Y, z), Vector3(12.0, h * 2.6, 2.4)))
			x += 13.0
		z += 3.2 if rng.randf() < 0.8 else 9.0
	# Two quay cranes on the north edge (lattice legs, boom out over the water).
	for cx: float in [2230.0, 2370.0]:
		var yel := Color(0.85, 0.68, 0.12)
		for lx: float in [-8.0, 8.0]:
			for lz: float in [-618.0, -598.0]:
				m.beam(Vector3(cx + lx, LAND_Y, lz), Vector3(cx + lx, LAND_Y + 42.0, lz), 1.4, 1.4, yel)
				_box_beam(body, Vector3(cx + lx, LAND_Y, lz), Vector3(cx + lx, LAND_Y + 42.0, lz), 1.4, 1.4)
		m.beam(Vector3(cx - 9.0, LAND_Y + 42.0, -608.0), Vector3(cx + 9.0, LAND_Y + 42.0, -608.0), 2.0, 2.0, yel)
		m.beam(Vector3(cx, LAND_Y + 44.0, -560.0), Vector3(cx, LAND_Y + 44.0, -690.0), 2.2, 3.0, yel)
		_box_beam(body, Vector3(cx, LAND_Y + 44.0, -560.0), Vector3(cx, LAND_Y + 44.0, -690.0), 2.2, 3.0)
		m.solid(cx - 3.0, -650.0, cx + 3.0, -644.0, LAND_Y + 38.0, LAND_Y + 42.5, Color(0.3, 0.3, 0.32))
	_mesh(m, "Industry", 0.0, 2200.0)


## Lanes for RoadNet (GPS): for every road a lane each way 3.4 m either side
## of its centreline, sampled every `step` m; at each junction every lane
## arriving can carry on into every lane leaving (not straight back), and a
## dead end turns round. Lanes leaving / reaching the bridge's city end are
## flagged for stitching into the city's lanes.
## Returns [{pts, speed, next: [local lane ids], city_start, city_end}].
static func lanes(layout: CityLayout, step: float) -> Array:
	var P := plan(layout)
	var e: Vector3 = P["city_end"]
	var out: Array = []
	var ends := {}   # Vector2i(node) -> {"in": [lane], "out": [lane]}
	var key := func(v: Vector3) -> Vector2i: return Vector2i(roundi(v.x), roundi(v.z))
	for r in P["roads"]:
		var pts: PackedVector3Array = r[1]
		var speed := 22.0 if r[0] == "Skyport Bridge" or r[0] == "Skyport Avenue" else 13.0
		for dir in [1, -1]:
			var src := pts.duplicate()
			if dir < 0:
				src.reverse()
			var off := PackedVector3Array()
			for i in src.size():
				var a := src[maxi(i - 1, 0)]
				var b := src[mini(i + 1, src.size() - 1)]
				var d := b - a
				d.y = 0.0
				var side := Vector3(-d.z, 0.0, d.x).normalized() * 3.4
				off.append(src[i] + side + Vector3.UP * 0.4)
			var lp := _resample(off, step)
			var id := out.size()
			out.append({"pts": lp, "speed": speed, "next": [], "city_start": false, "city_end": false, "u": -1})
			var k0: Vector2i = key.call(src[0])
			var k1: Vector2i = key.call(src[src.size() - 1])
			for kk in [k0, k1]:
				if not ends.has(kk):
					ends[kk] = {"in": [], "out": []}
			(ends[k0]["out"] as Array).append(id)
			(ends[k1]["in"] as Array).append(id)
			if src[0].distance_to(e) < 2.0:
				out[id]["city_start"] = true
			if src[src.size() - 1].distance_to(e) < 2.0:
				out[id]["city_end"] = true
		out[out.size() - 2]["u"] = out.size() - 1
		out[out.size() - 1]["u"] = out.size() - 2
	for kk in ends:
		var ins: Array = ends[kk]["in"]
		var outs: Array = ends[kk]["out"]
		for li in ins:
			if (out[li] as Dictionary)["city_end"]:
				continue
			for lo in outs:
				if lo != int(out[li]["u"]) or outs.size() == 1:
					(out[li]["next"] as Array).append(lo)
	return out


static func _resample(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array([pts[0]])
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		var t := step - carry
		while t <= L:
			out.append(a.lerp(b, t / L))
			t += step
		carry = L - (t - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > 0.3:
		out.append(pts[pts.size() - 1])
	return out
