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
##   airport town (east, facing the open sea): low and mid-rise offices,
##     an airline headquarters, a business hotel, a penthouse building with a
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
const NEAR_LOAD := 600.0     # (the island sits right by both cities now: detail only as you near it)
const NEAR_FREE := 900.0
const FAR_RANGE := 5200.0
const BRIDGE_ISLAND_X := 1560.0        # Skyport Avenue's first junction east of Bridge Road (local)
const QUAY_X := 1424.0                 # local: the north quay the bridges land on (world z ≈ 992)
const BRIDGE_ROAD_X := 1446.0          # local: Bridge Road, along the quay
## Local z of the two landings on the quay: [to the Commercial Island
## (north-east), to Westbank (north-west)].
const LANDINGS := [-106.0, 34.0]
## Each bridge: [name, landing index, world point near where it should leave
## the city, which city ("island" | "mainland")]. The city end is the nearest
## point of that city's coast road to the hint, so it meets a real street.
const BRIDGES := [
	["Harbour Bridge", 0, Vector2(200.0, 585.0), "island", "fan"],      # white A-frame cable-stay
	["Westbank Bridge", 1, Vector2(-560.0, 458.0), "mainland", "truss"], # steel through-truss
]
const TRUSS_HALF := 112.0  # m: the Westbank Bridge's truss span, each side of mid-span
const BRIDGE_CREST := 16.0             # deck height at mid-span (boats pass under)
const BRIDGE_W := 22.0
## 1.8 km (was 1 km: too short for the jets that use it; the island grew a
## runway peninsula to the south for it – see coast_points).
const RUNWAY := {"from": Vector3(1430.0, LAND_Y, 470.0), "to": Vector3(3230.0, LAND_Y, 470.0), "w": 45.0}
const HANGARS := [
	[1640, 192, 1712, 288, 20.0, Color(0.8, 0.81, 0.82), 0.21, true],
	[1722, 184, 1808, 292, 25.0, Color(0.62, 0.68, 0.74), 0.33, false],
	[1818, 204, 1870, 282, 15.0, Color(0.84, 0.8, 0.7), 0.47, true],
]
const COL_PAVE := Color(0.56, 0.56, 0.55)
const COL_GRASS := Color(0.33, 0.47, 0.26)
const COL_ROAD := Color(0.3, 0.3, 0.31)
const COL_APRON := Color(0.5, 0.5, 0.49)
const COL_RUNWAY := Color(0.26, 0.26, 0.27)

static var enabled := false
static var _plan := {}
## Walk-in venues (a game sets this before build): [{id, site, w, d, h}].
## Each carves a w × d room (h tall) out of the building behind its site's
## door, front on the door's side: the building is split round it plus a
## slab above it, and a "hollow" record keeps the map footprint without mesh
## or collision – the game builds the room (plan_data["venues"][id]:
## rect, origin = front-centre floor, yaw = 0 when the front faces +z).
static var venues: Array = []

# ------------------------------------------------------------ placement
## The island is designed (and built) in its own LOCAL coordinates – every
## number in this file – and placed in the world by one transform: a quarter
## turn and a move south of the strait, so it sits under both city islands
## (Westbank to its north-west, the Commercial Island to its north-east) with
## its old west shore, the bridge landing, facing them. Local (x, z) → world
## (ORIGIN.x − (z − PIVOT.y), ORIGIN.y + (x − PIVOT.x)). The node carries the
## transform, so meshes and collision need nothing; anything that leaves this
## file (plan data, lanes, sites, the map) goes through w() / l().
const PIVOT := Vector2(1432.0, -36.0)     # local: the bridge landing
const ORIGIN := Vector2(-200.0, 950.0)    # world: where the landing sits
const YAW := -PI * 0.5                     # local +x → world +z


## The local → world transform (for the node and for conversions).
static func xform() -> Transform3D:
	var b := Basis(Vector3.UP, YAW)
	return Transform3D(b, Vector3(ORIGIN.x, 0.0, ORIGIN.y) - b * Vector3(PIVOT.x, 0.0, PIVOT.y))


## Local point → world.
static func w(v: Vector3) -> Vector3:
	return Vector3(ORIGIN.x - (v.z - PIVOT.y), v.y, ORIGIN.y + (v.x - PIVOT.x))


## World point → local.
static func l(v: Vector3) -> Vector3:
	return Vector3(PIVOT.x + (v.z - ORIGIN.y), v.y, PIVOT.y - (v.x - ORIGIN.x))


static func w2(v: Vector2) -> Vector2:
	return Vector2(ORIGIN.x - (v.y - PIVOT.y), ORIGIN.y + (v.x - PIVOT.x))


static func l2(v: Vector2) -> Vector2:
	return Vector2(PIVOT.x + (v.y - ORIGIN.y), PIVOT.y - (v.x - ORIGIN.x))


## Local direction → world (no translation).
static func wd(v: Vector3) -> Vector3:
	return Vector3(-v.z, v.y, v.x)


## Local yaw (rotation about +Y) → world yaw.
static func wyaw(a: float) -> float:
	return a + YAW


## Local axis-aligned rect → world (still axis-aligned: a quarter turn).
static func wrect(r: Rect2) -> Rect2:
	var a := w2(r.position)
	var b := w2(r.end)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())


static func wpoly(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(w2(v))
	return out


static func wpts(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in pts:
		out.append(w(v))
	return out


## A building tier [x0, z0, x1, z1, y0, y1] → world (still a box).
static func wtier(t: Array) -> Array:
	var r := wrect(Rect2(float(t[0]), float(t[1]), float(t[2]) - float(t[0]), float(t[3]) - float(t[1])))
	var out := [r.position.x, r.position.y, r.end.x, r.end.y, t[4], t[5]]
	return out


## A building record with its tiers in world coordinates.
static func wbuilding(b: Dictionary) -> Dictionary:
	var c := b.duplicate()
	var ts: Array = []
	for t: Array in b["tiers"]:
		ts.append(wtier(t))
	c["tiers"] = ts
	return c


## A home record (Apartments-style) in world coordinates: the building's
## tiers turned, and its face index with them – BuildingMesher._face runs
## round a box counter-clockwise from the +z side, and the quarter turn takes
## local face k to world face k + 3 with the same start corner, so every
## along-the-face measure stays as it is.
static func whome(h: Dictionary) -> Dictionary:
	var c := h.duplicate()
	c["b"] = wbuilding(h["b"])
	c["face"] = (int(h["face"]) + 3) % 4
	c["wins"] = Apartments.facade_windows(c)
	if h.has("lift"):
		c["lift"] = w(h["lift"])
	return c


## The plan's places in WORLD coordinates, for games (sites, stands,
## berths, helipads, piers, the penthouse pad, homes, buildings, runway,
## roads). Yaws are world yaws; piers are [min corner, max corner].
static func world_plan(P: Dictionary) -> Dictionary:
	var W := {}
	var sites := {}
	for k in P["sites"]:
		var d: Dictionary = (P["sites"][k] as Dictionary).duplicate()
		d["door"] = w(d["door"])
		if d.has("lot"):
			d["lot"] = wrect(d["lot"])
		if d.has("face"):
			d["face"] = wd(d["face"])
		sites[k] = d
	W["sites"] = sites
	var yawed := func(list: Array) -> Array:
		var out: Array = []
		for it: Array in list:
			out.append([w(it[0]), wyaw(float(it[1]))])
		return out
	W["stands"] = yawed.call(P["stands"])
	W["berths"] = yawed.call(P["berths"])
	var pads: Array = []
	for v: Vector3 in P["helipads"]:
		pads.append(w(v))
	W["helipads"] = pads
	var piers: Array = []
	for pr: Array in P["piers"]:
		var a := w(pr[0])
		var b := w(pr[1])
		piers.append([Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)), Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))])
	W["piers"] = piers
	W["penthouse"] = {"pad": w(P["penthouse"]["pad"])}
	var bs: Array = []
	for b: Dictionary in P["buildings"]:
		bs.append(wbuilding(b))
	W["buildings"] = bs
	var hs: Array = []
	for h: Dictionary in P.get("homes", []):
		hs.append(whome(h))
	W["homes"] = hs
	var rw: Dictionary = P["runway"]
	W["runway"] = {"from": w(rw["from"]), "to": w(rw["to"]), "w": rw["w"]}
	var roads: Array = []
	for r in P["roads"]:
		roads.append([r[0], wpts(r[1]), r[2], r[3]])
	for B: Dictionary in P["bridges"]:
		roads.append([B["name"], B["pts"], BRIDGE_W, true])
	W["roads"] = roads
	var strips: Array = []
	for st in P["strips"]:
		strips.append([st[0], w(st[1]), w(st[2]), st[3]])
	W["strips"] = strips
	W["bridges"] = P["bridges"]
	return W


## Saves from before the island moved (save v5 and older): Skyport was
## built in world space east of the Commercial Island, joined by a bridge
## off its east cliffs. A position there – a parked car, a moored boat, an
## aircraft on a stand, the player – maps to the same place on the island
## now (old world = local), and one on the old bridge to the new bridge
## quay. Elsewhere it's returned unchanged.
static func was_old_site(p: Vector3) -> bool:
	return p.x > 1040.0 and p.z > -820.0 and p.z < 820.0


static func migrate_point(p: Vector3) -> Vector3:
	if not was_old_site(p):
		return p
	if p.x < QUAY_X and absf(p.z - PIVOT.y) < 30.0:
		return w(Vector3(BRIDGE_ROAD_X + 30.0, LAND_Y + 0.5, PIVOT.y + clampf(p.z - PIVOT.y, -8.0, 8.0)))
	return w(p)


## The coastline in world coordinates.
static func world_outline() -> PackedVector2Array:
	return wpoly(outline())
static var _outline := PackedVector2Array()
static var _bbox := Rect2()

var plan_data := {}   # the plan, LOCAL coordinates (this file builds from it)
var wplan := {}       # the same for games, WORLD coordinates (world_plan())
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
## The coastline as control points, each with the kind of shore on the
## stretch that starts there: "quay" (engineered: straight wall), "beach"
## (sand sloping into the sea), "rock" (a boulder revetment). Two wide lobes –
## the high-rise district and port in the north, the airport in the south –
## pinched in the middle by a west cove (south of the bridge) and a sheltered
## east inlet, so the island reads as a landform, not a slab.
## The coastline, drawn in WORLD coordinates (north up) as control points,
## each with the kind of shore on the stretch that starts there: "quay"
## (engineered, straight), "beach" (sand sloping into the sea), "rock" (a
## boulder revetment). A long, narrow airport island in the Malé manner:
## the runway along its west side, landside and a compact town and port
## along the east, and the coast drawn close round them – rocky points,
## small coves and peninsulas, no spare land. Only three stretches are
## straight: the bridge quay (both bridges land on it), the marina quay and
## the container quay.
## (Converted to local by l2(); outline() works in local like everything here.)
const Q_Z := 942.0     # world z of the bridge quay (local x QUAY_X)
const M_Z := 904.0     # world z of the marina quay (local x 1386)
const P_X := 98.0      # world x of the container quay (local z -334)
static func coast_points() -> Array:
	return [
	[l2(Vector2(-800, 930)), "rock"],
	[l2(Vector2(-760, 880)), "rock"],
	[l2(Vector2(-690, 866)), "rock"],
	[l2(Vector2(-616, 884)), "beach"],
	[l2(Vector2(-560, 930)), "beach"],
	[l2(Vector2(-498, 964)), "beach"],
	[l2(Vector2(-440, 958)), "rock"],
	[l2(Vector2(-398, 934)), "rock"],
	[l2(Vector2(-366, 926)), "rock"],
	[l2(Vector2(-342.0, Q_Z)), "quay"],
	[l2(Vector2(-84.0, Q_Z)), "rock"],
	[l2(Vector2(-70, 926)), "rock"],
	[l2(Vector2(-52.0, M_Z)), "quay"],
	[l2(Vector2(96.0, M_Z)), "rock"],
	[l2(Vector2(126, 918)), "rock"],
	[l2(Vector2(140, 984)), "rock"],
	[l2(Vector2(112, 1060)), "beach"],
	[l2(Vector2(104, 1140)), "beach"],
	[l2(Vector2(130, 1214)), "rock"],
	[l2(Vector2(176, 1252)), "rock"],
	[l2(Vector2(152, 1304)), "rock"],
	[l2(Vector2(112, 1352)), "beach"],
	[l2(Vector2(106, 1420)), "beach"],
	[l2(Vector2(76, 1440)), "beach"],
	[l2(Vector2(46, 1462)), "beach"],
	[l2(Vector2(66, 1486)), "rock"],
	[l2(Vector2(P_X, 1528)), "quay"],
	[l2(Vector2(P_X, 1976)), "rock"],
	[l2(Vector2(124, 2004)), "rock"],
	[l2(Vector2(132, 2070)), "rock"],
	[l2(Vector2(104, 2138)), "beach"],
	[l2(Vector2(40, 2172)), "beach"],
	[l2(Vector2(-40, 2170)), "rock"],
	[l2(Vector2(-58, 2140)), "rock"],
	[l2(Vector2(0, 2120)), "beach"],
	[l2(Vector2(40, 2084)), "beach"],
	[l2(Vector2(10, 2050)), "beach"],
	[l2(Vector2(-80, 2032)), "beach"],
	[l2(Vector2(-150, 2058)), "rock"],
	[l2(Vector2(-196, 2100)), "rock"],
	[l2(Vector2(-252, 2072)), "rock"],
	[l2(Vector2(-320, 2030)), "beach"],
	[l2(Vector2(-420, 2018)), "beach"],
	[l2(Vector2(-520, 2032)), "rock"],
	# The runway peninsula (2026-11-19): the runway was 1 km – half what the
	# airliners using it need – on a squat island. It now runs 1.8 km down a
	# narrow reclaimed strip to the south, Malé style: rock armour both sides,
	# one sheltered beach in the inner corner, the threshold 60 m from the tip.
	[l2(Vector2(-566, 2090)), "beach"],
	[l2(Vector2(-584, 2180)), "rock"],
	[l2(Vector2(-578, 2300)), "rock"],
	[l2(Vector2(-588, 2420)), "rock"],
	[l2(Vector2(-584, 2540)), "rock"],
	[l2(Vector2(-592, 2660)), "rock"],
	[l2(Vector2(-610, 2770)), "rock"],
	[l2(Vector2(-660, 2830)), "rock"],
	[l2(Vector2(-730, 2844)), "rock"],
	[l2(Vector2(-790, 2810)), "rock"],
	[l2(Vector2(-806, 2700)), "rock"],
	[l2(Vector2(-800, 2560)), "rock"],
	[l2(Vector2(-806, 2420)), "rock"],
	[l2(Vector2(-798, 2280)), "rock"],
	[l2(Vector2(-802, 2140)), "rock"],
	[l2(Vector2(-796, 2040)), "rock"],
	[l2(Vector2(-792, 1940)), "rock"],
	[l2(Vector2(-788, 1830)), "rock"],   # (rock armour along the runway)
	[l2(Vector2(-802, 1724)), "rock"],
	[l2(Vector2(-858, 1706)), "rock"],
	[l2(Vector2(-918, 1712)), "rock"],
	[l2(Vector2(-940, 1676)), "rock"],
	[l2(Vector2(-884, 1632)), "rock"],
	[l2(Vector2(-826, 1584)), "rock"],
	[l2(Vector2(-792, 1500)), "rock"],   # (rock armour along the runway)
	[l2(Vector2(-790, 1380)), "rock"],   # (rock armour along the runway)
	[l2(Vector2(-808, 1260)), "rock"],
	[l2(Vector2(-840, 1180)), "rock"],
	[l2(Vector2(-802, 1100)), "rock"],
	[l2(Vector2(-792, 1000)), "rock"],
	]
static var _shore_kind := PackedByteArray()   # per outline point: 0 quay, 1 beach, 2 rock (the edge starting there)


static func outline() -> PackedVector2Array:
	if _outline.is_empty():
		# Natural stretches: a Catmull-Rom curve through the control points,
		# every ~10 m, with a little irregularity (more on rock than sand);
		# quays stay straight.
		var COAST := coast_points()
		var n := COAST.size()
		var pts := PackedVector2Array()
		var kinds := PackedByteArray()
		for i in n:
			var kind := String(COAST[i][1])
			var p1: Vector2 = COAST[i][0]
			var p2: Vector2 = COAST[(i + 1) % n][0]
			var p0: Vector2 = COAST[(i - 1 + n) % n][0]
			var p3: Vector2 = COAST[(i + 2) % n][0]
			var k := maxi(1, ceili(p1.distance_to(p2) / 10.0))
			var kb := 0 if kind == "quay" else (1 if kind == "beach" else 2)
			for j in k:
				var t := float(j) / k
				var q := p1.lerp(p2, t) if kind == "quay" else _catmull(p0, p1, p2, p3, t)
				if kind != "quay" and j > 0:
					var d := (p2 - p1).normalized()
					var amp := 1.2 if kind == "beach" else 3.0
					var w := sin(q.x * 0.071 + q.y * 0.053) * 0.6 + sin(q.x * 0.19 - q.y * 0.17) * 0.4
					q += Vector2(d.y, -d.x) * w * amp
				pts.append(q)
				kinds.append(kb)
		_outline = pts
		_shore_kind = kinds
		_bbox = Rect2(_outline[0], Vector2.ZERO)
		for v in _outline:
			_bbox = _bbox.expand(v)
	return _outline


## Shore kind of the edge from outline point i: 0 quay, 1 beach, 2 rock.
static func shore_kind(i: int) -> int:
	outline()
	return _shore_kind[i % _shore_kind.size()]


## Where each stretch of shore meets the sea (for the foam): the wall for a
## quay, out down the beach / rocks otherwise.
static func waterline_edges() -> Array:
	var o := outline()
	var out: Array = []
	# (Where each shore row crosses the sea surface: beaches and rock blend
	# and vary in width, so the waterline is read off the row itself.)
	var wl := PackedVector2Array()
	var ok := PackedByteArray()
	for i in o.size():
		var row := _blend_row(o, i)
		var q := o[i]
		var found := 0
		for j in row.size() - 1:
			if row[j].y >= BuildingMesher.SEA_SURFACE and row[j + 1].y < BuildingMesher.SEA_SURFACE:
				var t := (row[j].y - BuildingMesher.SEA_SURFACE) / maxf(row[j].y - row[j + 1].y, 0.001)
				var v := row[j].lerp(row[j + 1], t)
				q = Vector2(v.x, v.z)
				found = 1
				break
		wl.append(q)
		ok.append(found)
	for i in o.size():
		var a := wl[i]
		var b := wl[(i + 1) % o.size()]
		if ok[i] == 0 or ok[(i + 1) % o.size()] == 0 or a.distance_to(b) > 40.0:
			continue
		var dd := (b - a).normalized()
		var on := Vector2(dd.y, -dd.x)
		if on.dot(_out_n(o, i)) < 0.0:
			on = -on
		out.append([a, b, on])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Is world (x, z) on the island?
static func contains(x: float, z: float) -> bool:
	if not enabled:
		return false
	var q := l2(Vector2(x, z))
	return contains_local(q.x, q.y)


static func contains_local(x: float, z: float) -> bool:
	outline()
	if not _bbox.has_point(Vector2(x, z)):
		return false
	return Geometry2D.is_point_in_polygon(Vector2(x, z), _outline)


## Ground height on the island (NAN off it). The bridge is not ground.
## Distance from (q) to the coastline.
static func _shore_dist(q: Vector2) -> float:
	var o := outline()
	var best := INF
	for i in o.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, o[i], o[(i + 1) % o.size()]).distance_to(q))
	return best


## Ground height at world (x, z) (NAN off the island).
static func ground_y(x: float, z: float) -> float:
	if not enabled:
		return NAN
	var q := l2(Vector2(x, z))
	return ground_y_local(q.x, q.y)


static func ground_y_local(x: float, z: float) -> float:
	return LAND_Y + knoll_h(x, z) if contains_local(x, z) else NAN


## Grassy knolls on the open ground (headlands and the park west of the
## terminal): [centre, radius x, radius z, height]. The developed land –
## roads, aprons, the runway, every building's forecourt – stays level; these
## sit only where nothing is built, clear of the shore bands.
## Knolls, WORLD coordinates: [centre, radius east-west, radius north-south, height].
const KNOLLS_W := [
	[Vector2(-772, 902), 24.0, 18.0, 5.0],     # the north-west point (runway approach)
	[Vector2(-880, 1672), 30.0, 20.0, 5.5],    # the west spit
	[Vector2(-190, 2066), 26.0, 18.0, 4.5],    # the south point
	[Vector2(146, 1258), 12.0, 18.0, 4.0],     # the east point
]
static var _knolls: Array = []


## The knolls in local terms: [centre, radius along local x, along local z, height].
static func knolls() -> Array:
	if _knolls.is_empty():
		for k: Array in KNOLLS_W:
			_knolls.append([l2(k[0]), float(k[2]), float(k[1]), float(k[3])])
	return _knolls


## Height of the knolls above LAND_Y at (x, z) (0 off them).
static func knoll_h(x: float, z: float) -> float:
	var h := 0.0
	for k: Array in knolls():
		var c: Vector2 = k[0]
		var dx := (x - c.x) / float(k[1])
		var dz := (z - c.y) / float(k[2])
		var r2 := dx * dx + dz * dz
		if r2 < 1.0:
			# A smooth dome with a little irregularity on its flanks.
			var w := 1.0 + 0.12 * sin(x * 0.09 + z * 0.05) * r2
			h = maxf(h, float(k[3]) * pow(1.0 - r2, 2.0) * w)
	return h


# ---------------------------------------------------------------- plan
## Everything about the island as data. Needs the city only for where the
## bridge meets the Commercial Island's cliff-top avenue.
static func plan(layout: CityLayout) -> Dictionary:
	if not _plan.is_empty():
		return _plan
	var z0 := PIVOT.y
	var P := {}
	var y := func(x: float, zz: float) -> Vector3: return Vector3(x, LAND_Y, zz)
	# The bridges first: the approach roads leave each deck on its heading.
	P["bridges"] = _plan_bridges(layout)
	# ------------------------------------------------------------ the roads
	# A planned airport district (2026-11-17), as one hierarchy:
	#  * the gateway: each bridge sweeps on off its deck as an approach road
	#    and the two merge in a Y into Skyport Avenue at M (a landscaped gore
	#    with the island's sign between them) – no quay T-junction;
	#  * Skyport Avenue, the spine, with Terminal Circus (a roundabout) where
	#    the terminal, the town and the industrial estate branch off;
	#  * the terminal loop: Terminal Approach → Departures (past the hotel and
	#    Airport Central station) → the forecourt kerb → Arrivals → back out
	#    to the avenue (Terminal Exit) or round the car parks; parking access;
	#  * the town: Tower Road's loop, Marina Drive, Quay Street, Harbour Row
	#    (the waterfront towers) and Dock Street;
	#  * Aviation Way to Hangar Lane (catering, academy, hangars, hotel),
	#    the gated airside service road to the fire station and helipads;
	#  * Industrial Way, the Cargo Road loop and the fuel farm gate.
	# Junctions are shared end points; roads: [name, points, width, bridge].
	var M: Vector3 = y.call(1570.0, z0)                 # the merge
	var B: Vector3 = y.call(1625.0, z0)                 # Tower Road
	var AV: Vector3 = y.call(1735.0, z0)                # Aviation Way
	var RC := Vector2(1954.0, z0)               # Terminal Circus
	var RR := 26.0              # ring centreline (two lanes, 12 m: 20–32 m from the centre)
	var RN: Vector3 = y.call(RC.x - RR, z0)
	var RS: Vector3 = y.call(RC.x + RR, z0)
	var RW: Vector3 = y.call(RC.x, z0 + RR)
	var RE: Vector3 = y.call(RC.x, z0 - RR)
	var TX: Vector3 = y.call(2270.0, z0)                # Terminal Exit
	var D: Vector3 = y.call(2330.0, z0)                 # Industrial Way
	var CG: Vector3 = y.call(2420.0, z0)                # Cargo Road
	var A1: Vector3 = y.call(1954.0, 40.0)
	var A2: Vector3 = y.call(1954.0, 152.0)
	var A3: Vector3 = y.call(2270.0, 152.0)
	var A4: Vector3 = y.call(2270.0, 40.0)
	var HL: Vector3 = y.call(1954.0, 112.0)
	var T1: Vector3 = y.call(1625.0, -176.0)
	var T2: Vector3 = y.call(1954.0, -176.0)
	var T3: Vector3 = y.call(1890.0, -176.0)
	var Q1: Vector3 = y.call(1482.0, -176.0)
	var roads: Array = []
	# The gateway: the Harbour Bridge's road is the main line – one sweep
	# off the deck that straightens into Skyport Avenue (no junction) – and
	# the Westbank Bridge's joins it as a slip road from the side at a
	# shallow angle (~15°) at M, like an on-ramp: no Y of two equal roads,
	# no wide triangle between them.
	var ends: Array = []
	for bi in 2:
		var Bd: Dictionary = P["bridges"][bi]
		var J0: Vector3 = l(Bd["Jw"] as Vector3)
		J0.y = LAND_Y
		var u3: Vector3 = Bd["u"]
		var ul := l(w(J0) + u3) - J0
		ul.y = 0.0
		ends.append([J0, ul.normalized()])
	var H0: Vector3 = y.call(1530.0, z0)
	var hp := _bez(ends[0][0], ends[0][1], H0, Vector3(1, 0, 0), 40.0, 34.0, 16)   # (H0 at x 1530)
	hp.append(M)
	roads.append(["Harbour Approach", hp, 22.0, false])
	# (Beside the main line edge to edge – 22 m between centrelines – at
	# x 1500, then a 70 m S-taper into it: the lanes merge.)
	var S0: Vector3 = y.call(1500.0, z0 + 22.0)
	var wp := _bez(ends[1][0], ends[1][1], S0, Vector3(1, 0, 0), 30.0, 26.0, 14)
	# (The taper: a smooth S from beside the main line into it, ~10° at M.)
	var tp := _bez(S0, Vector3(1, 0, 0), M, Vector3(0.985, 0.0, -0.174), 30.0, 30.0, 12)
	for k in range(1, tp.size()):
		wp.append(tp[k])
	roads.append(["Westbank Approach", wp, 22.0, false])
	P["merge"] = {"node": M, "slip": "Westbank Approach", "taper": 52.0}
	roads.append_array([
		["Skyport Avenue", PackedVector3Array([M, B]), 22.0, false],
		["Skyport Avenue", PackedVector3Array([B, AV]), 22.0, false],
		["Skyport Avenue", PackedVector3Array([AV, RN]), 22.0, false],
		["Skyport Avenue", PackedVector3Array([RS, TX]), 22.0, false],
		["Skyport Avenue", PackedVector3Array([TX, D]), 22.0, false],
		["Skyport Avenue", PackedVector3Array([D, CG]), 22.0, false],
		["Fuel Farm Road", PackedVector3Array([CG, y.call(2466.0, z0)]), 12.0, false],
		# The town.
		["Tower Road", PackedVector3Array([B, T1]), 14.0, false],
		["Tower Road", PackedVector3Array([T1, T3]), 14.0, false],
		["Tower Road", PackedVector3Array([T3, T2]), 14.0, false],
		["Tower Road", PackedVector3Array([T2, RE]), 14.0, false],
		["Marina Drive", PackedVector3Array([Q1, T1]), 12.0, false],
		["Marina Drive", PackedVector3Array([Q1, y.call(1436.0, -176.0)]), 12.0, false],   # (the marina's car park)
		["Quay Street", PackedVector3Array([Q1, y.call(1482.0, -259.0)]), 10.0, false],
		["Harbour Row", PackedVector3Array([y.call(1482.0, -259.0), y.call(1890.0, -259.0)]), 10.0, false],
		["Dock Street", PackedVector3Array([y.call(1890.0, -259.0), T3]), 10.0, false],
		# Industry and cargo.
		["Industrial Way", PackedVector3Array([T2, y.call(2330.0, -176.0)]), 16.0, false],
		["Industrial Way", PackedVector3Array([y.call(2330.0, -176.0), D]), 16.0, false],
		["Cargo Road", PackedVector3Array([CG, y.call(2420.0, 152.0)]), 14.0, false],
		["Cargo Road", PackedVector3Array([y.call(2420.0, 152.0), A3]), 14.0, false],
		# The terminal loop.
		["Terminal Approach", PackedVector3Array([RW, A1]), 16.0, false],
		["Departures", PackedVector3Array([A1, HL]), 14.0, false],
		["Departures", PackedVector3Array([HL, A2]), 14.0, false],
		["Terminal Forecourt", PackedVector3Array([A2, y.call(2096.0, 152.0)]), 16.0, false],
		["Terminal Forecourt", PackedVector3Array([y.call(2096.0, 152.0), A3]), 16.0, false],
		["Parking Access", PackedVector3Array([y.call(2096.0, 152.0), y.call(2096.0, 134.0)]), 10.0, false],
		["Arrivals", PackedVector3Array([A3, A4]), 14.0, false],
		["Car Park Road", PackedVector3Array([A4, A1]), 12.0, false],
		["Terminal Exit", PackedVector3Array([A4, TX]), 14.0, false],
		# Aviation.
		["Aviation Way", PackedVector3Array([AV, y.call(1735.0, 112.0)]), 12.0, false],
		["Hangar Lane", PackedVector3Array([y.call(1558.0, 112.0), y.call(1656.0, 112.0)]), 12.0, false],
		["Hangar Lane", PackedVector3Array([y.call(1656.0, 112.0), y.call(1735.0, 112.0)]), 12.0, false],
		["Hangar Lane", PackedVector3Array([y.call(1735.0, 112.0), HL]), 12.0, false],
		["Airside Service Road", PackedVector3Array([y.call(1558.0, 112.0), y.call(1558.0, 316.0)]), 10.0, false],
		["Hangar Access", PackedVector3Array([y.call(1656.0, 112.0), y.call(1656.0, 166.0)]), 10.0, false],
	])
	# Terminal Circus: the ring (one road per quarter, between the arms).
	var ring := [RN, RE, RS, RW]
	for qi in 4:
		var r0: Vector3 = ring[qi]
		var r1: Vector3 = ring[(qi + 1) % 4]
		var a0 := atan2(r0.z - RC.y, r0.x - RC.x)
		var a1 := atan2(r1.z - RC.y, r1.x - RC.x)
		var da := wrapf(a1 - a0, -PI, PI)
		var arc := PackedVector3Array()
		for k in 9:
			var t := a0 + da * k / 8.0
			arc.append(y.call(RC.x + cos(t) * RR, RC.y + sin(t) * RR))
		arc[0] = ring[qi]
		arc[8] = ring[(qi + 1) % 4]
		roads.append(["Terminal Circus", arc, 12.0, false])
	# Round internal bends without moving shared junction endpoints. The same
	# centreline feeds rendering, minimap, pedestrians and vehicle navigation.
	for r: Array in roads:
		r[1] = _round_road(r[1])
	P["roads"] = roads
	P["bridge_foot"] = M
	# The Airport Line, planned with the roads (buildings and trees keep
	# clear of its corridor).
	AirportRail.plan(P, layout)
	P["circus"] = [RC, RR]
	# Surfaces (areas): [kind, polygon, colour]. Kinds as island_ground.gdshader.
	var areas: Array = []
	var grass := Geometry2D.intersect_polygons(_rect(1390, 410, 2470, 600), outline())
	for g in grass:
		areas.append([1, g, COL_GRASS])
	# The gateway gore between the two approach curves (landscaped, the
	# island's sign in it) and Terminal Circus's planted island.
	var ha: PackedVector3Array = roads[0][1]
	var wa: PackedVector3Array = roads[1][1]
	var region := PackedVector2Array()
	for v in ha:
		region.append(Vector2(v.x, v.z))
	for k in range(wa.size() - 2, -1, -1):
		region.append(Vector2(wa[k].x, wa[k].z))
	var gore := PackedVector2Array()
	var shrunk := Geometry2D.offset_polygon(region, -17.0)
	if not shrunk.is_empty():
		gore = shrunk[0]
		areas.append([1, gore, COL_GRASS])
	P["gore"] = gore
	var isle := PackedVector2Array()
	for k in 24:
		isle.append(RC + Vector2(cos(TAU * k / 24.0), sin(TAU * k / 24.0)) * (RR - 6.0))
	areas.append([1, isle, COL_GRASS])
	areas.append([5, _rect(1560, 170, 1880, 385), COL_APRON])              # hangar apron
	areas.append([5, _rect(1895, 242, 2330, 385), COL_APRON])              # terminal apron
	areas.append([5, _rect(2335, 160, 2462, 385), COL_APRON])              # cargo apron
	areas.append([5, _rect(1965, 58, 2255, 132), COL_APRON, "bays"])       # terminal car park (bays, parked cars)
	areas.append([5, _rect(2140, -300, 2450, -196), COL_APRON])            # container yard
	for f in [[1630, 8, 1725, 96], [1745, 8, 1875, 96], [2350, -80, 2448, -50]]:
		areas.append([0, _rect(f[0], f[1], f[2], f[3]), Color(0.62, 0.6, 0.57), "bays"])  # dealer forecourts (display bays)
	areas.append([0, _rect(1568, 119.5, 1644, 126), Color(0.64, 0.61, 0.56)])
	areas.append([0, _rect(1396, -196, 1445, -176), Color(0.64, 0.61, 0.56)])
	P["areas"] = areas
	# Airport strips: [kind, from, to, half width].
	var strips: Array = [
		[3, RUNWAY["from"], RUNWAY["to"], RUNWAY["w"] * 0.5],
		[4, Vector3(1470, LAND_Y, 395), Vector3(3210, LAND_Y, 395), 11.5],
	]
	for cx: float in [1480.0, 1700.0, 1940.0, 2160.0, 2400.0, 2660.0, 2930.0, 3200.0]:
		strips.append([4, Vector3(cx, LAND_Y, 384), Vector3(cx, LAND_Y, 470), 11.5])
	# Rapid exits: arrivals land westbound and turn off at a shallow angle.
	for rx: float in [2780.0, 2290.0, 1860.0]:
		strips.append([4, Vector3(rx, LAND_Y, 466), Vector3(rx - 120.0, LAND_Y, 398), 11.5])
	# Fire station apron out to the taxiway.
	strips.append([4, Vector3(1520, LAND_Y, 334), Vector3(1520, LAND_Y, 384), 9.0])
	# Apron markings (narrow taxiway strips read as painted lines): a lead-in
	# line from the taxiway to every stand, its stop bar, and the equipment
	# restraint line along the gates.
	for sx: float in [1990.0, 2080.0, 2170.0, 2260.0]:
		strips.append([4, Vector3(sx, LAND_Y, 383), Vector3(sx, LAND_Y, 288), 0.3])
		strips.append([4, Vector3(sx - 4.0, LAND_Y, 289), Vector3(sx + 4.0, LAND_Y, 289), 0.3])
	strips.append([4, Vector3(1958, LAND_Y, 262), Vector3(2292, LAND_Y, 262), 0.25])
	for sx: float in [1700.0, 1800.0]:
		strips.append([4, Vector3(sx, LAND_Y, 383), Vector3(sx, LAND_Y, 326), 0.3])
	P["strips"] = strips
	P["helipads"] = [Vector3(1585, LAND_Y, 205), Vector3(1585, LAND_Y, 255), Vector3(1585, LAND_Y, 305)]
	P["stands"] = [[Vector3(1990, LAND_Y, 300), PI], [Vector3(2080, LAND_Y, 300), PI], [Vector3(2170, LAND_Y, 300), PI],
		[Vector3(2260, LAND_Y, 300), PI], [Vector3(1700, LAND_Y, 340), PI], [Vector3(1800, LAND_Y, 340), PI]]
	P["runway"] = RUNWAY
	# Marina: piers out into the strait off the west shore, berths between.
	var piers: Array = []
	var berths: Array = []
	for k in 4:
		var pz := -296.0 + k * 34.0
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
		# (On the avenue by the industrial estate: its old lot sat in the
		# terminal's car-park loop.)
		"dealer_commercial": {"name": "Skyport Commercials", "door": Vector3(2399, LAND_Y, -80), "lot": Rect2(2352, -76, 94, 24), "face": Vector3(0, 0, 1)},
		"clothes_everyday": {"name": "Threadline", "door": Vector3(1685, LAND_Y, -52), "face": Vector3(0, 0, 1)},
		"clothes_premium": {"name": "Maison Arden", "door": Vector3(1815, LAND_Y, -52), "face": Vector3(0, 0, 1)},
		# (Its sales office is the hangar's landside annex, on Hangar Access.)
		"aviation": {"name": "Skyport Aviation", "door": Vector3(1606, LAND_Y, 119.5), "face": Vector3(0, 0, -1)},
		"marina": {"name": "Skyport Marina", "door": Vector3(1410, LAND_Y, -192), "face": Vector3(0, 0, 1)},
		"cargo": {"name": "Skyport Cargo", "door": Vector3(2398, LAND_Y, 155), "face": Vector3(0, 0, -1)},
		"terminal": {"name": "Skyport Airport", "door": Vector3(2110, LAND_Y, 160), "face": Vector3(0, 0, -1)},
	}
	_plan = P
	return P


## Metres from q (local) to the nearest road's kerb (negative: on it).
static func road_clearance(P: Dictionary, q: Vector2) -> float:
	var best := INF
	for r in P.get("roads", []):
		var pts: PackedVector3Array = r[1]
		var hw := float(r[2]) * 0.5
		for i in pts.size() - 1:
			var cp := Geometry2D.get_closest_point_to_segment(q, Vector2(pts[i].x, pts[i].z), Vector2(pts[i + 1].x, pts[i + 1].z))
			best = minf(best, cp.distance_to(q) - hw)
	return best


## Metres from q (local) to the Airport Line's centreline less its deck
## half-width (INF without one).
static func rail_clearance(P: Dictionary, q: Vector2) -> float:
	var best := INF
	for ln in P.get("rail_local", []):
		var pts: PackedVector2Array = ln
		for i in range(0, pts.size() - 1):
			var cp := Geometry2D.get_closest_point_to_segment(q, pts[i], pts[i + 1])
			best = minf(best, cp.distance_to(q) - AirportRail.DECK_HALF)
	return best


## Terminal Circus's arms: [[unit radial dir (local, flat), half width,
## road name]] for every road ending on the ring.
func _circus_arms() -> Array:
	var circ: Array = plan_data.get("circus", [])
	var out: Array = []
	if circ.is_empty():
		return out
	var C: Vector2 = circ[0]
	var RR: float = circ[1]
	for r in plan_data["roads"]:
		if r[0] == "Terminal Circus":
			continue
		var pts: PackedVector3Array = r[1]
		for e: Vector3 in [pts[0], pts[-1]]:
			var q := Vector2(e.x, e.z)
			if absf(q.distance_to(C) - RR) < 1.0:
				out.append([(q - C).normalized(), float(r[2]) * 0.5, r[0]])
	return out


## Terminal Circus as one engineered roundabout (the ring roads stay in the
## plan for lanes and the GPS, but are drawn here): a two-lane annulus, the
## entries flared with curved kerbs into it, white edge lines and a dashed
## lane line round it (broken at the entries), and on every arm a give-way
## line with a yield triangle and a zebra set back past the splitter
## island's nose (the islands and planting: SkyportAirport.build_circus).
func _circus_surface(st: SurfaceTool) -> void:
	var circ: Array = plan_data.get("circus", [])
	if circ.is_empty():
		return
	var C: Vector2 = circ[0]
	var RR: float = circ[1]
	var Ro := RR + 6.0
	var Ri := RR - 6.0
	var Y := LAND_Y
	var road := Color(COL_ROAD.r, COL_ROAD.g, COL_ROAD.b, 2.5 / 8.0)
	var pave := Color(COL_PAVE.r, COL_PAVE.g, COL_PAVE.b, 0.5 / 8.0)
	var v3 := func(q: Vector2, lift: float) -> Vector3: return Vector3(q.x, Y + lift, q.y)
	var fill := func(poly: PackedVector2Array, col: Color, lift: float) -> void:
		var tri := Geometry2D.triangulate_polygon(poly)
		for i in range(0, tri.size(), 3):
			var a := poly[tri[i]]
			var b := poly[tri[i + 1]]
			var c := poly[tri[i + 2]]
			var vs := [a, b, c]
			if (b - a).cross(c - a) > 0.0:
				vs = [a, c, b]
			for v: Vector2 in vs:
				st.set_color(col)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(50.0, 0.0))     # (plain: no lane lines)
				st.set_uv2(Vector2(100.0, 0.0))
				st.add_vertex(v3.call(v, lift))
	var paint := func(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> void:
		var vs := [a, b, c, a, c, d]
		if (b - a).cross(c - a) > 0.0:
			vs = [a, c, b, a, d, c]
		for v: Vector2 in vs:
			st.set_color(road)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(edge_line_x(10.0), 0.0))   # (on the edge-line band: solid white)
			st.set_uv2(Vector2(10.0, 1.0))
			st.add_vertex(v3.call(v, 0.04))
	var arms := _circus_arms()
	# Flares: each entry's kerbs curve out into the ring (asphalt), with the
	# pavement following them round.
	for arm: Array in arms:
		var u: Vector2 = arm[0]
		var hw: float = arm[1]
		var nrm := Vector2(-u.y, u.x)
		for sg: float in [-1.0, 1.0]:
			for layer in 2:
				var h := hw + (5.0 if layer == 1 else 0.0)
				var R := Ro + (5.0 if layer == 1 else 0.0)
				var te := sqrt(maxf(R * R - h * h, 1.0))
				var E := C + u * te + nrm * sg * h
				var P0 := C + u * (te + 16.0) + nrm * sg * h
				var aE := (E - C).angle()
				var turn := signf(u.cross(nrm * sg))
				var aF := aE + turn * (18.0 / R)
				var F := C + Vector2.from_angle(aF) * R
				# Control: where the edge line meets the ring's tangent at F.
				var tF := Vector2.from_angle(aF).orthogonal()
				var dl := u
				var den := dl.cross(tF)
				var Q := E
				if absf(den) > 1e-4:
					var tt := (F - P0).cross(tF) / den
					Q = P0 + dl * tt
				var poly := PackedVector2Array([E, P0])
				for k in range(1, 12):
					var t := float(k) / 12.0
					poly.append(P0.lerp(Q, t).lerp(Q.lerp(F, t), t))
				poly.append(F)
				for k in range(1, 6):
					poly.append(C + Vector2.from_angle(aF + (aE - aF) * k / 6.0) * R)
				fill.call(poly, pave if layer == 1 else road, 0.009 if layer == 1 else 0.033)
	# The ring itself, over the arms' ends.
	var seg := 72
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		fill.call(PackedVector2Array([C + Vector2.from_angle(a0) * Ri, C + Vector2.from_angle(a0) * Ro,
			C + Vector2.from_angle(a1) * Ro, C + Vector2.from_angle(a1) * Ri]), road, 0.034)
	# Lines: inner edge, outer edge and the dashed lane line (broken at the
	# entries).
	var mouth := func(ang: float) -> bool:
		for arm: Array in arms:
			var au := (arm[0] as Vector2).angle()
			if absf(wrapf(ang - au, -PI, PI)) < (float(arm[1]) + 6.0) / Ro:
				return true
		return false
	for k in 144:
		var a0 := TAU * k / 144.0
		var a1 := TAU * (k + 1) / 144.0
		var d0 := Vector2.from_angle(a0)
		var d1 := Vector2.from_angle(a1)
		paint.call(C + d0 * (Ri + 0.35), C + d0 * (Ri + 0.5), C + d1 * (Ri + 0.5), C + d1 * (Ri + 0.35))
		if not mouth.call((a0 + a1) * 0.5):
			paint.call(C + d0 * (Ro - 0.5), C + d0 * (Ro - 0.35), C + d1 * (Ro - 0.35), C + d1 * (Ro - 0.5))
			if k % 3 == 0:
				paint.call(C + d0 * (RR - 0.07), C + d0 * (RR + 0.07), C + d1 * (RR + 0.07), C + d1 * (RR - 0.07))
	# Each entry: a double dashed give-way line across the lanes coming in
	# (keep right: on the right of travel towards the ring), a yield
	# triangle in them, and a zebra set back in the splitter island's gap.
	for arm: Array in arms:
		var u: Vector2 = arm[0]
		var hw: float = arm[1]
		var din := -u
		var rin := Vector2(-din.y, din.x)       # (right of travel: x × up)
		var lat := 0.6
		while lat < hw - 0.6:
			for row: float in [0.4, 1.0]:
				var b0 := C + u * (Ro + row) + rin * lat
				paint.call(b0, b0 + rin * 0.6, b0 + rin * 0.6 + u * 0.3, b0 + u * 0.3)
			lat += 1.2
		# Yield triangle: base towards the ring, apex towards the driver.
		var mid := C + u * (Ro + 6.5) + rin * (hw * 0.5)
		var tip := C + u * (Ro + 11.5) + rin * (hw * 0.5)
		var bl := mid - rin * 1.3
		var br := mid + rin * 1.3
		for e: Array in [[bl, br], [br, tip], [tip, bl]]:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var nn := (b - a).orthogonal().normalized() * 0.11
			paint.call(a - nn, b - nn, b + nn, a + nn)
		# Zebra across the whole arm, 12–15 m out (the splitter's gap).
		var off := -hw + 0.8
		while off + 0.6 < hw - 0.6:
			var z0 := C + u * (Ro + 12.0) + rin * off
			paint.call(z0, z0 + rin * 0.6, z0 + rin * 0.6 + u * 3.0, z0 + u * 3.0)
			off += 1.2


## A cubic Bézier from a (leaving along ta) to b (arriving along tb), n
## segments – the gateway's approach curves.
static func _bez(a: Vector3, ta: Vector3, b: Vector3, tb: Vector3, la: float, lb: float, n: int) -> PackedVector3Array:
	var c1 := a + ta * la
	var c2 := b - tb * lb
	var out := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		var u := 1.0 - t
		out.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
	out[0] = a
	out[n] = b
	return out


static func _rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## The deck runs on this far over the quay at ground level: the bridges
## meet the quay at an angle, and a deck cut square to its own axis left a
## triangle of open water beside one kerb.
const LAND_RUN := 14.0


## The landing: the bridge's road from the coast road to the deck. Columns
## across the bridge (m from its axis; ±12.85 = the parapets' outer faces).
## The city end of each bridge is a street (CityLayout.bridge_spurs: a
## T-junction on the coast road, cut through the esplanade); each column
## starts MOUTH m short of where that street meets the sea wall – flush
## with it – and rises over the wall's coping to the deck's first point
## (S). The coast slopes across the bridge on Westbank and meets it at an
## angle, so the landing is a warped grid; where the run is too short the
## deck starts further out and the landing becomes a walled abutment.
const LAND_COLS := [-12.85, -11.0, -8.8, -6.6, -4.4, -2.2, 0.0, 2.2, 4.4, 6.6, 8.8, 11.0, 12.85]
const MOUTH := 10.0
const MOUTH_ROWS := 8
const LAND_ROWS := 20
const LAND_GRADE := 0.025   # (grade of the climb onto the wall coping, met at an angle: keep it gentle)
const LAND_AVG_GRADE := 0.06


## The bridges, world space. Each: {name, city ("island" | "mainland"),
## s0 (ramp start on the coast road's asphalt), a0 (the asphalt's edge),
## S (deck start at the sea wall), F (landing on the north quay), Jw (Bridge
## Road), u (unit direction S → F, horizontal), L (S → F, horizontal), y0
## (deck height at S), pts (driving centreline s0 … Jw), rail_gap}.
static func _plan_bridges(layout: CityLayout) -> Array:
	var out: Array = []
	if layout == null:
		return out
	for bd: Array in BRIDGES:
		var lz: float = LANDINGS[int(bd[1])]
		var F := w(Vector3(QUAY_X, LAND_Y, lz))
		var Jw := w(Vector3(BRIDGE_ROAD_X, LAND_Y, lz))
		var city: CityLayout = layout if String(bd[3]) == "island" else layout.mainland
		var R := _coast_road_point(city, bd[2])
		var u2 := (Vector2(F.x, F.z) - R).normalized()
		# Jw (where the island's approach road starts) on the bridge's own
		# axis at Bridge Road's x: it used to be square across from F, so the
		# road ran LAND_RUN m on and then doglegged sideways to it – a Z step
		# in the kerbs and markings at every bridge's island end (2026-11-18).
		var ul2 := l(F + Vector3(u2.x, 0.0, u2.y)) - l(F)
		if ul2.x > 0.2:
			Jw = w(l(F) + ul2 * ((BRIDGE_ROAD_X - QUAY_X) / ul2.x))
		# Out from the road to the sea wall; the deck starts 4 m short of it.
		var q := R
		while not layout.is_water(Vector3(q.x, 0.0, q.y)) and q.distance_to(R) < 240.0:
			q += u2 * 0.5
		var S2 := q - u2 * 4.0
		# Back from there over the esplanade to the asphalt's edge.
		var a2 := S2
		while city.block_at(a2.x, a2.y) >= 0 and a2.distance_to(S2) < 70.0:
			a2 -= u2 * 0.5
		var n2 := Vector2(-u2.y, u2.x)
		# The deck starts level at y_es: over the esplanade's highest point
		# by the road...
		var hi := -INF
		for k: float in [-11.0, -5.5, 0.0, 5.5, 11.0]:
			var e2 := a2 + u2 * 0.6 + n2 * k
			hi = maxf(hi, city.ground_y(e2.x, e2.y))
		var y_es := maxf(hi + 0.01, city.ground_y(S2.x, S2.y))
		# Clear the sea wall's top (road height + kerb) across the deck's whole
		# width – the coast crosses under it at an angle.
		for k: float in [-13.0, -9.0, -5.0, 0.0, 5.0, 9.0, 13.0]:
			var c2 := S2 + n2 * k
			var guard := 0
			while not layout.is_water(Vector3(c2.x, 0.0, c2.y)) and guard < 120:
				c2 += u2 * 0.5
				guard += 1
			while layout.is_water(Vector3(c2.x, 0.0, c2.y)) and guard < 240:
				c2 -= u2 * 0.5
				guard += 1
			var H := city.terrain.road_y(c2.x, c2.y)
			# (Under the bridge's end the shore is a plain quay wall:
			# BuildingMesher.shore_profile.)
			y_es = maxf(y_es, H + CityTerrain.KERB + 0.04)
		var land := _plan_landing(layout, city, S2, u2, y_es)
		# Where the esplanade is too short for a column to climb to the deck
		# at LAND_AVG_GRADE (Westbank's coast road slopes 1.8 m across the
		# bridge), the deck starts further out: the landing carries on over
		# the sea wall as a walled abutment.
		for it in 3:
			# (S past every column's sea wall, and enough run for each.)
			var need := 0.0
			for kv: float in (land["kerb"] as PackedFloat32Array):
				need = maxf(need, kv + 6.0)
			for j in LAND_COLS.size():
				var h0: float = ((land["h"] as Array)[j] as PackedFloat32Array)[0]
				var a_start: float = ((land["al"] as Array)[j] as PackedFloat32Array)[0]
				need = maxf(need, (float(land["y_es"]) - h0) / LAND_AVG_GRADE + a_start)
			if need < 0.5:
				break
			S2 += u2 * minf(need, 40.0)
			land = _plan_landing(layout, city, S2, u2, float(land["y_es"]))
		y_es = float(land["y_es"])
		var S := Vector3(S2.x, y_es, S2.y)
		var L := Vector2(F.x - S.x, F.z - S.z).length()
		# s0: where the bridge's axis crosses the coast road's centre line (its
		# lanes join the city's there); a0: the kerb on the axis.
		var ci := LAND_COLS.find(0.0)
		var kerb0: float = (land["kerb"] as PackedFloat32Array)[ci]
		var B := {"name": bd[0], "city": bd[3], "style": bd[4], "s0": Vector3(R.x, city.terrain.road_y(R.x, R.y), R.y),
			"a0": Vector3(S2.x + u2.x * kerb0, _landing_y(land, kerb0, 0.0), S2.y + u2.y * kerb0), "S": S, "F": F, "Jw": Jw,
			"u": Vector3(u2.x, 0.0, u2.y), "L": L, "y0": y_es, "land": land}
		# Lanes: the coast road's centre, the landing's centre column, the deck.
		var pts := PackedVector3Array([B["s0"]])
		var cal: PackedFloat32Array = (land["al"] as Array)[ci]
		var ch: PackedFloat32Array = (land["h"] as Array)[ci]
		for i in cal.size() - 1:
			pts.append(Vector3(S2.x + u2.x * cal[i], ch[i], S2.y + u2.y * cal[i]))
		var n := maxi(24, int(L / 12.0))
		for i in n + 1:
			var sd := L * i / n
			pts.append(S + Vector3(u2.x, 0.0, u2.y) * sd + Vector3.UP * (deck_y(B, sd) - S.y))
		pts.append(F + Vector3(u2.x, 0.0, u2.y) * LAND_RUN)
		pts.append(Jw)
		B["pts"] = pts
		# How far past F the deck's outer corner still overhangs the water
		# (it meets the quay at an angle): its parapets run on that far.
		# (Per side: the side already over the quay at F needs nothing.)
		var nn := Vector3(-u2.y, 0.0, u2.x)
		var qext := PackedFloat32Array()
		for sg: float in [-1.0, 1.0]:
			var ext := 0.0
			while ext < LAND_RUN and l(F + Vector3(u2.x, 0.0, u2.y) * ext + nn * (sg * 13.0)).x < QUAY_X + 0.5:
				ext += 0.5
			qext.append(ext)
		B["quay_ext"] = qext
		# The sea-wall railing opens where the ramp crosses it.
		# (Centred where the approach street meets the wall, on the axis.)
		var gc := S2 + u2 * kerb0
		B["rail_gap"] = Rect2(gc - Vector2(30.0, 30.0), Vector2(60.0, 60.0))
		out.append(B)
	return out


## Plans the landing (see LAND_COLS): {cols, kerb (along, per column),
## al / h (per column: along positions and heights of its rows), y_es}.
## "along" is metres from S along the bridge (negative: on land).
static func _plan_landing(layout: CityLayout, city: CityLayout, S2: Vector2, u2: Vector2, y_es: float) -> Dictionary:
	var n2 := Vector2(-u2.y, u2.x)
	# What the road surface must stay on or above at a point: the road
	# itself, a pavement (+5 cm, or it shows through), or over the shore the
	# sea wall and its apron (as y_es above).
	var env := func(p: Vector2) -> float:
		var H := city.terrain.road_y(p.x, p.y)
		if layout.is_water(Vector3(p.x, 0.0, p.y)):
			return H + CityTerrain.KERB + 0.04   # (the sea wall's coping)
		if city.block_at(p.x, p.y) >= 0:
			return city.ground_y(p.x, p.y) + 0.05
		return H
	var at := func(al: float, c: float) -> Vector2: return S2 + u2 * al + n2 * c
	# Each column's "kerb": where the approach street meets the sea wall –
	# coming back from the sea, the first land, less the wall's coping.
	var kerb := PackedFloat32Array()
	for c: float in LAND_COLS:
		var k := -45.0
		var al := 60.0
		while al > -80.0:
			var p: Vector2 = at.call(al, c)
			if not layout.is_water(Vector3(p.x, 0.0, p.y)):
				k = al - CityLayout.SPUR_WALL_GAP
				break
			al -= 0.25
		kerb.append(k)
	# The deck must start above everything just short of it.
	for c: float in LAND_COLS:
		for al: float in [-1.5, -0.75, 0.0]:
			y_es = maxf(y_es, float(env.call(at.call(al, c))) + 0.06)
	var als: Array = []
	var hs: Array = []
	for ci in LAND_COLS.size():
		var c: float = LAND_COLS[ci]
		var k0: float = kerb[ci]
		var a_start := k0 - MOUTH
		var row := PackedFloat32Array()
		for i in MOUTH_ROWS:
			row.append(lerpf(a_start, k0, float(i) / MOUTH_ROWS))
		for i in LAND_ROWS + 1:
			row.append(lerpf(k0, 0.0, float(i) / LAND_ROWS))
		# The surface needs: env everywhere (sampled every 0.5 m, plus a
		# margin for the straight runs between rows), and no step steeper
		# than LAND_GRADE up to it.
		var fine: Array = []
		var al := a_start
		while al <= 0.0:
			fine.append([al, float(env.call(at.call(al, c))) + 0.06])
			al += 0.5
		var p0: Vector2 = at.call(a_start, c)
		var h0 := city.terrain.road_y(p0.x, p0.y)
		# Leave the street on its own grade (a sloping coast road met an eased,
		# level start: a 6 % sag that bounced cars at 34 m/s); the extra term
		# fades out with zero slope by the deck.
		var pb: Vector2 = at.call(a_start - 3.0, c)
		var g0 := clampf((h0 - city.terrain.road_y(pb.x, pb.y)) / 3.0, -0.08, 0.08)
		var h := PackedFloat32Array()
		for i in row.size():
			var t := (row[i] - a_start) / -a_start
			var tc := clampf(t, 0.0, 1.0)
			var v := lerpf(h0, y_es, _ease_grade(tc)) + g0 * (row[i] - a_start) * (1.0 - tc) * (1.0 - tc)
			for f: Array in fine:
				v = maxf(v, float(f[1]) - LAND_GRADE * absf(float(f[0]) - row[i]))
			h.append(v)
		# Round the corners the cones leave (keeping the floor), then pin
		# both ends: flush with the road, level with the deck.
		for pass_i in 2:
			var sm := h.duplicate()
			for i in range(1, h.size() - 1):
				sm[i] = maxf(h[i - 1] * 0.25 + h[i] * 0.5 + h[i + 1] * 0.25, h[i] - 0.02)
			h = sm
		h[0] = h0
		h[h.size() - 1] = y_es
		als.append(row)
		hs.append(h)
	return {"cols": PackedFloat32Array(LAND_COLS), "kerb": kerb, "al": als, "h": hs, "y_es": y_es}


## Height of a landing at (along, across), or NAN off it.
static func _landing_y(land: Dictionary, al: float, c: float) -> float:
	var cols: PackedFloat32Array = land["cols"]
	if c < cols[0] or c > cols[cols.size() - 1]:
		return NAN
	var j := 0
	while j < cols.size() - 2 and c > cols[j + 1]:
		j += 1
	var t := (c - cols[j]) / (cols[j + 1] - cols[j])
	var ya := _col_y(land, j, al)
	var yb := _col_y(land, j + 1, al)
	if is_nan(ya) or is_nan(yb):
		return NAN
	return lerpf(ya, yb, t)


static func _col_y(land: Dictionary, j: int, al: float) -> float:
	var row: PackedFloat32Array = (land["al"] as Array)[j]
	var h: PackedFloat32Array = (land["h"] as Array)[j]
	if al < row[0] - 0.01 or al > 0.01:
		return NAN
	for i in row.size() - 1:
		if al <= row[i + 1]:
			return lerpf(h[i], h[i + 1], clampf((al - row[i]) / maxf(row[i + 1] - row[i], 0.001), 0.0, 1.0))
	return h[h.size() - 1]


## Is world (x, z) under a bridge's ramp or deck where it leaves its city
## (street furniture there – a bench on the esplanade's edge – stood up
## through the deck: CityWorld drops props here)?
static func under_bridge(x: float, z: float) -> bool:
	if not enabled or _plan.is_empty():
		return false
	for B: Dictionary in _plan["bridges"]:
		var u: Vector3 = B["u"]
		var S: Vector3 = B["S"]
		var s0: Vector3 = B["s0"]
		var r := Vector2(x - S.x, z - S.z)
		var along := r.dot(Vector2(u.x, u.z))
		var across := absf(r.dot(Vector2(-u.z, u.x)))
		var back := Vector2(S.x - s0.x, S.z - s0.z).length()
		if across < BRIDGE_W * 0.5 + 3.0 and along > -back - 3.0 and along < 30.0:
			return true
	return false


## Is world (x, z) on the shore under a bridge's low end (the deck clears a
## sand apron there, not rock armour)?
static func over_bridge_shore(x: float, z: float) -> bool:
	if not enabled or _plan.is_empty():
		return false
	for B: Dictionary in _plan["bridges"]:
		var u: Vector3 = B["u"]
		var S: Vector3 = B["S"]
		var r := Vector2(x - S.x, z - S.z)
		var along := r.dot(Vector2(u.x, u.z))
		var across := absf(r.dot(Vector2(-u.z, u.x)))
		if across < BRIDGE_W * 0.5 + 8.0 and along > -20.0 and along < 90.0:
			return true
	return false


## The coast road's point nearest a hint (the ring, else any road).
static func _coast_road_point(city: CityLayout, hint: Vector2) -> Vector2:
	var best := hint
	var bd := INF
	for r: Dictionary in city.roads.roads:
		var pts: PackedVector2Array = r["pts"]
		var pen := 0.0 if String(r.get("name", "")) == "ring" else 60.0
		for i in pts.size() - 1:
			var c := Geometry2D.get_closest_point_to_segment(hint, pts[i], pts[i + 1])
			var d := c.distance_to(hint) + pen
			if d < bd:
				bd = d
				best = c
	return best


## Deck height s metres along a bridge from its sea-wall end: one steady
## grade up to the crest at mid-span and down to the quay, each with eased
## vertical curves over its first and last 12% (≤ ~7%: the old bridge's
## hump threw cars at motorway speed).
static func deck_y(B: Dictionary, sd: float) -> float:
	var L: float = B["L"]
	var y0: float = B["y0"]
	var crest := maxf(BRIDGE_CREST, y0 + 4.0)
	var mid := L * 0.5
	if sd <= mid:
		return lerpf(y0, crest, _ease_grade(clampf(sd / mid, 0.0, 1.0)))
	return lerpf(crest, LAND_Y, _ease_grade(clampf((sd - mid) / (L - mid), 0.0, 1.0)))


## 0 → 1 with a steady middle and eased (parabolic) ends: flat at both ends.
static func _ease_grade(t: float) -> float:
	const F := 0.12
	if t < F:
		return t * t / (2.0 * F * (1.0 - F))
	if t > 1.0 - F:
		return 1.0 - (1.0 - t) * (1.0 - t) / (2.0 * F * (1.0 - F))
	return (t - F * 0.5) / (1.0 - F)


## The driving surface's height on a bridge's road at world (x, z) – the
## ramp, the deck – or NAN if (x, z) isn't on one. For audits and cars.
static func bridge_road_y(layout: CityLayout, x: float, z: float) -> float:
	if not enabled:
		return NAN
	for B: Dictionary in plan(layout)["bridges"]:
		var u: Vector3 = B["u"]
		var s0: Vector3 = B["s0"]
		var S: Vector3 = B["S"]
		var rel := Vector2(x - S.x, z - S.z)
		var along := rel.dot(Vector2(u.x, u.z))
		var across := absf(rel.dot(Vector2(-u.z, u.x)))
		if across > BRIDGE_W * 0.5 + 1.0:
			continue
		var d_s0 := -Vector2(S.x - s0.x, S.z - s0.z).length()
		if along < d_s0 - 2.0 or along > float(B["L"]) + LAND_RUN:
			continue
		if along < 0.0:
			var ly := _landing_y(B["land"], along, rel.dot(Vector2(-u.z, u.x)))
			if not is_nan(ly):
				return ly
			var city: CityLayout = layout if String(B["city"]) == "island" else layout.mainland
			return city.terrain.road_y(x, z)   # (the coast road, short of the mouth)
		return deck_y(B, along)
	return NAN


# ----------------------------------------------------------- buildings
static func _b(tiers: Array, style: int, col: Color, seed: float, kind := "normal") -> Dictionary:
	# Shared facade details are relative to base, even though tiers are absolute.
	return {"tiers": tiers, "base": LAND_Y, "foot": LAND_Y, "style": style, "color": col, "kind": kind, "seed": seed}


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
	# The airport town: [x, z, w, d, h, form, style]. Low and mid-rise only
	# (no skyscrapers on an airport island: the runway's approach is over
	# it, and the cities across the water carry the skyline) – offices,
	# an airline headquarters, a parking garage, a business hotel.
	var towers := [
		# Waterfront row, facing the open sea.
		[1490, -306, 34, 30, 22, "slab", S.MODERN],
		[1540, -306, 60, 36, 16, "slab", S.STONE],               # parking garage
		[1660, -310, 50, 40, 36, "podium", S.GLASS],             # airline headquarters
		[1730, -306, 44, 34, 28, "stepped", S.DARK_GLASS],
		[1790, -306, 40, 30, 24, "slab", S.GLASS],
		[1850, -304, 26, 30, 18, "slab", S.MODERN],
		# Middle row, north of Tower Road.
		[1505, -250, 30, 34, 26, "setback", S.DARK_GLASS],
		[1550, -246, 36, 28, 20, "slab", S.GLASS],
		[1650, -240, 40, 30, 32, "setback", S.MODERN],
		[1715, -240, 30, 40, 18, "slab", S.GLASS],
		[1770, -240, 46, 34, 38, "podium", S.DARK_GLASS],
		[1830, -240, 34, 30, 16, "slab", S.DECO],
		# Inner row, between Tower Road and the avenue.
		[1640, -160, 70, 30, 30, "slab", S.DECO],                # offices (eight floors)
		[1800, -160, 36, 34, 24, "setback", S.GLASS],
		[1490, -160, 30, 30, 14, "slab", S.SANDSTONE],
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
	var pt := _b([[1430, -310, 1474, -274, LAND_Y, LAND_Y + 34.0], [1436, -307.3, 1456.3, -280.7, LAND_Y + 34.0, LAND_Y + 49.0]],
		S.DARK_GLASS, Color(0.5, 0.56, 0.62), 0.47)
	out.append(pt)
	homes.append(_home(pt, 1, 3, 4, "skyport_penthouse", "Skyport Penthouse", LAND_Y + 37.6))
	homes[-1]["lift"] = Vector3(1426.5, LAND_Y, -294.0)   # (the window is on the narrower top: the lobby is below on the base)
	var ht := _b([[1720, -160, 1770, -130, LAND_Y, LAND_Y + 17.0], [1730, -160, 1754.6, -141.7, LAND_Y + 17.0, LAND_Y + 45.0]],
		S.MODERN, Color(0.82, 0.79, 0.72), 0.36)
	out.append(ht)
	homes.append(_home(ht, 1, 2, 3, "skyport_suite", "Skyport Hotel Suite", LAND_Y + 33.4))
	var mq := _b([[1430, -250, 1464, -220, LAND_Y, LAND_Y + 40.0], [1430, -250, 1444.3, -233.4, LAND_Y + 40.0, LAND_Y + 52.0]],
		S.MODERN, Color(0.74, 0.74, 0.72), 0.58)
	out.append(mq)
	homes.append(_home(mq, 1, 3, 1, "skyport_flat", "Marina Quay Show Flat", LAND_Y + 43.6))
	P["homes"] = homes
	P["penthouse"] = {"pad": Vector3(1446.15, LAND_Y + 49.0, -294.0)}
	(P["helipads"] as Array).append(P["penthouse"]["pad"])
	# Retail row on Skyport Avenue: dealers (glazed showrooms behind their
	# forecourts) and two clothing stores.
	out.append(_b([[1640, 66, 1720, 96, LAND_Y, LAND_Y + 8.0]], S.MODERN, Color(0.86, 0.85, 0.8), 0.31, "normal"))
	out.append(_b([[1750, 60, 1870, 96, LAND_Y, LAND_Y + 11.0]], S.DARK_GLASS, Color(0.2, 0.22, 0.25), 0.62, "normal"))
	# Keep storefronts and their plinths outside the avenue and its pavement.
	out.append(_b([[1662, -80, 1708, -56, LAND_Y, LAND_Y + 9.0]], S.BRICK, Color(0.66, 0.4, 0.32), 0.44, "normal"))
	out.append(_b([[1790, -84, 1840, -56, LAND_Y, LAND_Y + 11.0]], S.STONE, Color(0.84, 0.81, 0.74), 0.77, "normal"))
	# Industrial & logistics.
	# (The first and last leave the Airport Line's corridor at x 2014; the
	# third fronts the avenue as Skyport Commercials' showroom.)
	var ind := [[2032, -160, 2160, -60, 16.0], [2180, -160, 2312, -60, 12.0], [2350, -150, 2448, -82, 13.0],
		[2032, -296, 2130, -200, 14.0]]
	for r in ind:
		out.append(_b([[r[0], r[1], r[2], r[3], LAND_Y, LAND_Y + r[4]]], S.WAREHOUSE,
			[Color(0.6, 0.62, 0.64), Color(0.42, 0.5, 0.58), Color(0.55, 0.52, 0.48)][rng.randi() % 3], rng.randf()))
	# Airport: terminal (long glass hall on a stone base), control tower,
	# hangars, cargo terminal.
	# (The terminal is a glazed hall under a curved roof: _build_terminal.)
	var term := _b([[1962, 168, 2258, 236, LAND_Y, LAND_Y + TERMINAL_HALL]], S.GLASS, Color(0.6, 0.68, 0.74), 0.12)
	term["mesh"] = false   # (a glazed hall: SkyportAirport.build_terminal; the record keeps collision and the map)
	out.append(term)
	# Skyport Grand: the airport hotel beside the terminal, a low setback block
	# between the runway and the town.
	var hotel := _b(_tower(1900, 170, 44, 52, 30, "setback"), S.GLASS, Color(0.55, 0.62, 0.66), 0.83)
	hotel["district"] = "airport"
	out.append(hotel)
	# Control tower (drawn by SkyportAirport.build_tower; these boxes are its
	# collision and map footprint): base block, shaft, cab.
	var twr := _b([[2274, 190, 2308, 220, LAND_Y, LAND_Y + 8.1], [2287, 201, 2295, 209, LAND_Y + 8.1, LAND_Y + 54.4],
		[2282.5, 196.5, 2299.5, 213.5, LAND_Y + 54.4, LAND_Y + 61.6]], S.DARK_GLASS, Color(0.25, 0.3, 0.34), 0.58)
	twr["mesh"] = false
	out.append(twr)
	# Airport fire station (ARFF) between the hangars and the runway's west
	# end: four engine bays facing the taxiway, a training tower.
	out.append(_b([[1492, 300, 1548, 334, LAND_Y, LAND_Y + 9.0], [1530, 300, 1548, 312, LAND_Y + 9.0, LAND_Y + 18.0]], S.BRICK,
		Color(0.62, 0.3, 0.24), 0.71))
	# Hangars: three different buildings (a line of identical sheds read as
	# clones from the air) – the aviation company's maintenance hangar, a
	# wide-body bay and a small GA hangar – each with a ridged roof (stepped
	# tiers along the span) and a lean-to office annex on the landside.
	for hg: Array in HANGARS:
		var x0: float = hg[0]
		var z0: float = hg[1]
		var x1: float = hg[2]
		var z1: float = hg[3]
		var hh: float = hg[4]
		var span := x1 - x0
		var tiers: Array = [[x0, z0, x1, z1, LAND_Y, LAND_Y + hh],
			[x0 + span * 0.18, z0, x1 - span * 0.18, z1, LAND_Y + hh, LAND_Y + hh + 2.2],
			[x0 + span * 0.38, z0, x1 - span * 0.38, z1, LAND_Y + hh + 2.2, LAND_Y + hh + 3.4]]
		out.append(_b(tiers, S.WAREHOUSE, hg[5], hg[6]))
		if hg[7]:
			out.append(_b([[x0, z0 - 14.0, x0 + span * 0.45, z0, LAND_Y, LAND_Y + 8.0]], S.MODERN, Color(0.86, 0.86, 0.84), float(hg[6]) + 0.05))
	out.append(_b([[2340, 170, 2455, 290, LAND_Y, LAND_Y + 15.0]], S.WAREHOUSE, Color(0.45, 0.52, 0.6), 0.9))
	# Landside aviation businesses on the open ground south of Hangar Lane:
	# flight catering (a loading dock towards the apron) and an aviation
	# academy with a simulator hall.
	var fc := _b([[1702, 128, 1772, 176, LAND_Y, LAND_Y + 10.0]], S.WAREHOUSE, Color(0.86, 0.87, 0.86), 0.27)
	fc["district"] = "airport"
	out.append(fc)
	var ac := _b([[1792, 124, 1872, 156, LAND_Y, LAND_Y + 15.0], [1820, 156, 1872, 176, LAND_Y, LAND_Y + 9.0]], S.GLASS,
		Color(0.55, 0.62, 0.66), 0.39)
	ac["district"] = "airport"
	out.append(ac)
	# Landside galleries have their own footprint, accessible from the public
	# road network without crossing the apron or walking along the quay edge.
	var sales := _b([[1568, 126, 1644, 169, LAND_Y, LAND_Y + 10.47]],
		S.MODERN, Color(0.36, 0.40, 0.44), 0.38)
	sales["district"] = "airport"
	out.append(sales)
	out.append(_b([[1396, -245, 1424, -196, LAND_Y, LAND_Y + 9.16]], S.MODERN, Color(0.85, 0.84, 0.78), 0.66))
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
	_carve_venues(plan_data)
	wplan = world_plan(plan_data)
	transform = xform()   # (local → world: see "placement")
	street = StaticBody3D.new()
	street.name = "Ground"
	street.collision_layer = 1 << 3
	add_child(street)
	_build_ground(street)
	add_child(Shoreline.build(waterline_edges()))
	_build_skyline()
	_build_bridge(street)


static func _carve_venues(P: Dictionary) -> void:
	P["venues"] = {}
	var blds: Array = P["buildings"]
	for v: Dictionary in venues:
		var s: Dictionary = (P.get("sites", {}) as Dictionary).get(String(v["site"]), {})
		if s.is_empty():
			continue
		var door: Vector3 = s["door"]
		var fz := signf((s["face"] as Vector3).z)
		if fz == 0.0:
			continue   # (fronts on ±z only)
		# The first building straight back from the site's door (a dealer's
		# door is its forecourt gate: the showroom stands behind the lot).
		var bi := -1
		var probe_m := 2.0
		while bi < 0 and probe_m < 120.0:
			var probe := door - Vector3(0, 0, fz) * probe_m
			probe_m += 2.0
			for i in blds.size():
				var t0: Array = blds[i]["tiers"][0]
				if (blds[i]["tiers"] as Array).size() == 1 and not blds[i].get("hollow", false) \
						and probe.x >= float(t0[0]) and probe.x <= float(t0[2]) and probe.z >= float(t0[1]) and probe.z <= float(t0[3]):
					bi = i
					break
		if bi < 0:
			continue
		var b: Dictionary = blds[bi]
		var t: Array = b["tiers"][0]
		var x0 := float(t[0])
		var z0 := float(t[1])
		var x1 := float(t[2])
		var z1 := float(t[3])
		var y0 := float(t[4])
		var y1 := float(t[5])
		# The cut is PAD wider, deeper and taller than the room: the room has
		# its own walls and ceiling, and building faces left flush with them
		# z-fight (striped walls, the facade showing through).
		const PAD := 0.45
		var w := minf(float(v["w"]) + PAD * 2.0, x1 - x0)
		var d := minf(float(v["d"]) + PAD, z1 - z0)
		var h := minf(float(v["h"]) + PAD, y1 - y0)
		var cx := clampf(door.x, x0 + w * 0.5, x1 - w * 0.5)
		var front := z0 if fz < 0.0 else z1
		var r := Rect2(cx - w * 0.5, front if fz < 0.0 else front - d, w, d)
		var pieces: Array = []
		if r.position.x > x0 + 0.5:
			pieces.append([x0, z0, r.position.x, z1, y0, y1])
		if r.end.x < x1 - 0.5:
			pieces.append([r.end.x, z0, x1, z1, y0, y1])
		if fz < 0.0 and r.end.y < z1 - 0.5:
			pieces.append([r.position.x, r.end.y, r.end.x, z1, y0, y1])
		if fz > 0.0 and r.position.y > z0 + 0.5:
			pieces.append([r.position.x, z0, r.end.x, r.position.y, y0, y1])
		var out: Array = []
		for pc: Array in pieces:
			var nb := b.duplicate(true)
			nb["tiers"] = [pc]
			out.append(nb)
		if y1 - (y0 + h) > 0.6:
			var slab := b.duplicate(true)
			slab["tiers"] = [[r.position.x, r.position.y, r.end.x, r.end.y, y0 + h, y1]]
			out.append(slab)
		var hollow := b.duplicate(true)
		hollow["tiers"] = [[r.position.x, r.position.y, r.end.x, r.end.y, y0, y0 + h]]
		hollow["mesh"] = false
		hollow["hollow"] = true
		hollow["venue"] = String(v["id"])
		out.append(hollow)
		blds.remove_at(bi)
		blds.append_array(out)
		P["venues"][String(v["id"])] = {"site": String(v["site"]), "rect": r, "h": h,
			"origin": Vector3(cx, y0, front), "yaw": 0.0 if fz > 0.0 else PI}


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
		func(): _near(_build_terminal.bind(near_street)),
		func(): SkyportAirport.build_terminal(self, near_root, body),
		func(): SkyportAirport.build_tower(near_root, self),
		func(): SkyportAirport.build_parked(plan_data, near_root, self),
		func(): SkyportAirport.build_masts(near_root, body, self),
		func(): SkyportAirport.build_fuel_farm(near_root, body, self),
		func(): SkyportAirport.build_car_park(near_root, body, self),
		func(): SkyportAirport.build_apron_kit(plan_data, near_root, self),
		func(): SkyportAirport.build_circus(plan_data, near_root, self, _circus_arms()),
		func(): _near(_build_industry), func(): _near(_build_trees), func(): _near(_build_beach_life),
		func(): _near(_build_quayside.bind(body)),
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
			# (Interiors from the world-space records, in a top-level node: their
			# interaction spots are world positions, like the city's homes.)
			var hn := Node3D.new()
			hn.name = "Homes"
			near_root.add_child(hn)
			hn.top_level = true
			hn.global_transform = Transform3D.IDENTITY
			for h: Dictionary in wplan.get("homes", []):
				hn.add_child(HomeInteriors.build(h, _bmat())),
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
		remove_child(near_root)
		near_root.queue_free()
	near_root = null
	for key in _groups():
		var skyline := get_node_or_null("Skyline_" + key) as GeometryInstance3D
		if skyline:
			skyline.visibility_range_begin = 0.0
	body = null


## Distance from p to the island (0 on it).
## Distance from world point p to the island's bounding box.
static func distance_to(p: Vector3) -> float:
	outline()
	var q := l2(Vector2(p.x, p.z))
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
	m.set_shader_parameter("asph_tex", load("res://assets/textures/pbr/asphalt_01.png"))
	m.set_shader_parameter("pave_tex", load("res://assets/textures/pbr/concrete_pavement.png"))
	m.set_shader_parameter("pbr_on", true)
	m.set_shader_parameter("skyport_grass", true)
	var edge := w(Vector3(0.0, 0.0, 180.0))
	var into_airfield := wd(Vector3.BACK)
	m.set_shader_parameter("airfield_edge", Vector3(into_airfield.x, into_airfield.z, -into_airfield.dot(edge)))
	return m


## A flat polygon at height y, kind k (UV = world x/z).
static func _poly_tris(st: SurfaceTool, poly: PackedVector2Array, yv: float, kind: int, col: Color, flag := 0.0) -> void:
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
			st.set_uv2(Vector2(flag, 0))   # (3 = a car park: island_ground paints bays)
			st.add_vertex(Vector3(v.x, yv, v.y))


## Ease interior road corners while retaining junction endpoints.
static func _round_road(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var p := pts[i]
		var run := minf(18.0, minf(p.distance_to(pts[i - 1]), p.distance_to(pts[i + 1])) * 0.25)
		var a := p.move_toward(pts[i - 1], run)
		var b := p.move_toward(pts[i + 1], run)
		for k in 7:
			var t := float(k) / 6.0
			out.append(a.lerp(p, t).lerp(p.lerp(b, t), t))
	out.append(pts[-1])
	return out


## Shared miter vertices keep bends closed without overlapping road faces.
static func _road_side(pts: PackedVector3Array, i: int, hw: float) -> Vector3:
	var a := pts[i] - pts[maxi(0, i - 1)]
	var b := pts[mini(pts.size() - 1, i + 1)] - pts[i]
	a.y = 0.0
	b.y = 0.0
	if a.length_squared() < 0.0001:
		a = b
	if b.length_squared() < 0.0001:
		b = a
	var na := Vector3(-a.z, 0, a.x).normalized()
	var nb := Vector3(-b.z, 0, b.x).normalized()
	var m := (na + nb).normalized()
	return m * hw / maxf(m.dot(nb), 0.5)


## Metres from a junction box's edge to its stop line: a zebra crossing
## (1–4 m out) and the stop line; no lane markings in between.
const CROSS_RUN := 5.5


## Road nodes where two or more ends meet: {key: {p, arms: [[dir, hw]]}}
## (dir: unit, flat, from the node along the road).
static func _road_nodes(roads: Array) -> Dictionary:
	var nodes := {}
	for r in roads:
		if r[3]:
			continue
		var pts: PackedVector3Array = r[1]
		var hw := float(r[2]) * 0.5
		for e in 2:
			var p := pts[0] if e == 0 else pts[-1]
			var q := _point_at(pts, 6.0) if e == 0 else _point_at(pts, _length(pts) - 6.0)
			var d := q - p
			d.y = 0.0
			var k := Vector2i(roundi(p.x), roundi(p.z))
			if not nodes.has(k):
				nodes[k] = {"p": p, "arms": []}
			(nodes[k]["arms"] as Array).append([d.normalized(), hw])
	return nodes


static func _length(pts: PackedVector3Array) -> float:
	var t := 0.0
	for i in range(1, pts.size()):
		t += pts[i].distance_to(pts[i - 1])
	return t


## Junction surfaces under the road strips (plain asphalt): a disc at the
## node (closes the wedge two strips leave meeting at an angle) and a
## kerb-radius fillet in every corner between neighbouring arms, so the
## kerb line turns the corner on a curve instead of a square notch.
static func _junction_surfaces(st: SurfaceTool, nodes: Dictionary, lift: float) -> void:
	var c := Color(COL_ROAD.r, COL_ROAD.g, COL_ROAD.b, 2.5 / 8.0)
	var tri := func(a: Vector3, b: Vector3, d: Vector3) -> void:
		var t3 := [a, b, d]
		if ((t3[1] - t3[0]) as Vector3).cross(t3[2] - t3[0]).y > 0.0:
			t3 = [a, d, b]
		for v: Vector3 in t3:
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(50.0, 0.0))   # (no lane lines)
			st.set_uv2(Vector2(100.0, 0.0))
			st.add_vertex(v + Vector3.UP * lift)
	for k in nodes:
		var N: Vector3 = nodes[k]["p"]
		var arms: Array = nodes[k]["arms"]
		if arms.size() < 2:
			continue
		arms.sort_custom(func(x: Array, y: Array) -> bool:
			return atan2((x[0] as Vector3).z, (x[0] as Vector3).x) < atan2((y[0] as Vector3).z, (y[0] as Vector3).x))
		var straight := arms.size() == 2 and (arms[0][0] as Vector3).dot(arms[1][0]) < -0.985
		if straight:
			continue   # (a road carrying on: nothing to fill, keep its lines)
		var hmax := 0.0
		for a: Array in arms:
			hmax = maxf(hmax, float(a[1]))
		# (A road carrying straight through – a T, a roundabout's ring –
		# covers the junction itself: no fill disc, which bulged out past
		# its far kerb; the kerb returns below do the corners.)
		var through := false
		for a: Array in arms:
			for b: Array in arms:
				if (a[0] as Vector3).dot(b[0]) < -0.9:
					through = true
		if not through:
			for i in 24:
				var a0 := TAU * i / 24.0
				var a1 := TAU * (i + 1) / 24.0
				tri.call(N, N + Vector3(cos(a0), 0, sin(a0)) * hmax, N + Vector3(cos(a1), 0, sin(a1)) * hmax)
		for i in arms.size():
			var A: Array = arms[i]
			var B: Array = arms[(i + 1) % arms.size()]
			var da: Vector3 = A[0]
			var db: Vector3 = B[0]
			var cross_y := da.x * db.z - da.z * db.x
			if cross_y <= 0.02:
				continue   # (the corner is 180° or more: the outside of a bend)
			# Kerb lines: arm A's edge on B's side, B's edge on A's side.
			var na := Vector3(-da.z, 0, da.x)   # (towards B: rotating da towards db)
			var nb := Vector3(db.z, 0, -db.x)
			var pa := N + na * float(A[1])
			var pb := N + nb * float(B[1])
			# Corner C: pa + da t = pb + db s.
			var den := da.x * db.z - da.z * db.x
			var w := pb - pa
			var t := (w.x * db.z - w.z * db.x) / den
			var C := pa + da * t
			var theta := acos(clampf(da.dot(db), -1.0, 1.0))
			var R := 9.0 if minf(float(A[1]), float(B[1])) >= 7.0 else 6.0
			var dd := R / tan(theta * 0.5)
			if dd > 30.0:
				continue
			var Ta := C + da * dd
			var Tb := C + db * dd
			var O := C + (da + db).normalized() * (R / sin(theta * 0.5))
			# Fan from C over the arc Ta → Tb (the arc bulges back towards C).
			var va := Ta - O
			var vb := Tb - O
			var ang0 := atan2(va.z, va.x)
			var ang1 := atan2(vb.z, vb.x)
			var dang := wrapf(ang1 - ang0, -PI, PI)
			var prev := Ta
			for s2 in range(1, 9):
				var an := ang0 + dang * s2 / 8.0
				var q := O + Vector3(cos(an), 0, sin(an)) * R
				tri.call(C, prev, q)
				prev = q


## A continuous strip: UV.x across, UV.y along; UV2 = half width, length.
## box0 / box1: metres at the start / end inside a junction – plain asphalt
## there (no lines), and a stop line across the lanes arriving at it.
static func _strip(st: SurfaceTool, pts: PackedVector3Array, hw: float, lift: float, kind: int, col: Color,
		box0 := 0.0, box1 := 0.0) -> void:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	var mark0 := box0 > 0.0
	var mark1 := box1 > 0.0
	box0 = absf(box0)
	box1 = absf(box1)
	if box0 > 0.0 or box1 > 0.0:
		pts = _split_at(pts, [box0 + CROSS_RUN, total - box1 - CROSS_RUN])
	var c := Color(col.r, col.g, col.b, (kind + 0.5) / 8.0)
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := (b - a).length()
		if L < 0.01:
			continue
		var sa := _road_side(pts, i, hw)
		var sb := _road_side(pts, i + 1, hw)
		var q := [a - sa, a + sa, b + sb, b - sb]
		var u := [Vector2(-hw, acc), Vector2(hw, acc), Vector2(hw, acc + L), Vector2(-hw, acc + L)]
		var mid := acc + L * 0.5
		var plain := (box0 > 0.0 and mid < box0 + CROSS_RUN) or (box1 > 0.0 and mid > total - box1 - CROSS_RUN)
		for j in [0, 2, 1, 0, 3, 2]:
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(50.0, (u[j] as Vector2).y) if plain else u[j])
			st.set_uv2(Vector2(100.0, total) if plain else Vector2(hw, total))
			st.add_vertex((q[j] as Vector3) + Vector3.UP * lift)
		acc += L
	# At each junction mouth: a zebra crossing just outside the box, then a
	# stop line across the arriving lanes (traffic keeps right: arriving at
	# the end, its lanes are on the +side; arriving at the start, the −side).
	var white := func(a3: Vector3, b3: Vector3, c3: Vector3, d3: Vector3, at: float) -> void:
		var vs := [a3, b3, c3, a3, c3, d3]
		if (b3 - a3).cross(c3 - a3).y > 0.0:   # (wind so the face points up, whichever way the road runs)
			vs = [a3, c3, b3, a3, d3, c3]
		for v: Vector3 in vs:
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(edge_line_x(hw), at))   # (on the edge-line band: solid white)
			st.set_uv2(Vector2(hw, total))
			st.add_vertex(v + Vector3.UP * (lift + 0.004))
	for e in 2:
		var bx := box1 if e == 1 else box0
		if bx <= 0.0 or not (mark1 if e == 1 else mark0):
			continue
		var sg := -1.0 if e == 1 else 1.0   # (away from the junction, along)
		var jat := total if e == 1 else 0.0
		var z0 := _point_at(pts, jat + sg * (bx + 1.0))
		var z1 := _point_at(pts, jat + sg * (bx + 4.0))
		var zd := z1 - z0
		zd.y = 0.0
		var zn := Vector3(-zd.z, 0.0, zd.x).normalized()
		var off := -hw + 0.7
		while off + 0.6 < hw - 0.6:
			white.call(z0 + zn * off, z0 + zn * (off + 0.6), z1 + zn * (off + 0.6), z1 + zn * off, jat + sg * bx)
			off += 1.2
		var at := jat + sg * (bx + CROSS_RUN - 0.6)
		var p0 := _point_at(pts, at)
		var p1 := _point_at(pts, at + sg * 0.5)
		var d := p1 - p0
		d.y = 0.0
		var side := Vector3(-d.z, 0.0, d.x).normalized() * (1.0 if e == 1 else -1.0)
		var o0 := 0.2
		var o1 := hw - 0.5
		white.call(p0 + side * o0, p0 + side * o1, p1 + side * o1, p1 + side * o0, at)


## Where island_ground.gdshader draws a road's solid edge line (metres from
## its centre line, half width hw) – painted quads that must come out solid
## white (zebras, stop lines, the roundabout's lines) put their UV.x on it.
static func edge_line_x(hw: float) -> float:
	return hw - 2.5 if hw >= 10.0 else maxf(hw - 1.8, minf(4.6, hw - 0.5))


## The polyline with points inserted at these distances along it.
static func _split_at(pts: PackedVector3Array, cuts: Array) -> PackedVector3Array:
	var out := PackedVector3Array([pts[0]])
	var acc := 0.0
	for i in pts.size() - 1:
		var L := pts[i].distance_to(pts[i + 1])
		var ds: Array = []
		for cu: float in cuts:
			if cu > acc + 0.05 and cu < acc + L - 0.05:
				ds.append(cu)
		ds.sort()
		for cu: float in ds:
			out.append(pts[i].lerp(pts[i + 1], (cu - acc) / L))
		out.append(pts[i + 1])
		acc += L
	return out


## The point s metres along a polyline (clamped).
static func _point_at(pts: PackedVector3Array, sd: float) -> Vector3:
	var acc := 0.0
	for i in pts.size() - 1:
		var L := pts[i].distance_to(pts[i + 1])
		if sd <= acc + L or i == pts.size() - 2:
			return pts[i].lerp(pts[i + 1], clampf((sd - acc) / maxf(L, 0.001), 0.0, 1.0))
		acc += L
	return pts[-1]


func _build_ground(street: StaticBody3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Layers, bottom up: grass everywhere; paving (pavements along every road,
	# forecourts round every building, the high-rise plaza and the marina
	# quay); the planted areas on top of that; concrete aprons and yards;
	# airport strips; roads. (It was one sheet of beige paving.)
	_poly_tris(st, outline(), LAND_Y, 1, COL_GRASS)
	var coast := outline()
	var forecourt_y := LAND_Y + 0.012
	for r in plan_data["roads"]:
		if not r[3]:
			_strip(st, r[1], float(r[2]) * 0.5 + 5.0, 0.008, 0, COL_PAVE)
	for b: Dictionary in plan_data["buildings"]:
		var t: Array = b["tiers"][0]
		var g := 6.0 if float(t[5]) - float(t[4]) > 40.0 else 4.0
		var forecourt := _rect(float(t[0]) - g, float(t[1]) - g, float(t[2]) + g, float(t[3]) + g)
		for part: PackedVector2Array in Geometry2D.intersect_polygons(forecourt, coast):
			_poly_tris(st, part, forecourt_y, 0, COL_PAVE)
	for pr in [[1385, -312, 1475, -184], [1955, 135, 2265, 168]]:
		var poly := Geometry2D.intersect_polygons(_rect(pr[0], pr[1], pr[2], pr[3]), coast)
		for q in poly:
			_poly_tris(st, q, LAND_Y + 0.016, 0, COL_PAVE.lightened(0.04))
	for a in plan_data["areas"]:
		_poly_tris(st, a[1], LAND_Y + (0.018 if int(a[0]) == 1 else 0.019), int(a[0]), a[2], 3.0 if a.size() > 3 and a[3] == "bays" else 0.0)
	for s in plan_data["strips"]:
		_strip(st, PackedVector3Array([s[1], s[2]]), s[3], 0.027 if int(s[0]) == 3 else 0.023, int(s[0]), COL_RUNWAY if int(s[0]) == 3 else COL_APRON.darkened(0.15))
	# Junctions (3+ road ends meet): each road's markings stop at the
	# crossing road's kerb – the box between is plain asphalt – and its
	# approach lanes get a stop line. (They used to run straight through
	# each other.)
	var ends := {}
	var key := func(v: Vector3) -> Vector2i: return Vector2i(roundi(v.x), roundi(v.z))
	for r in plan_data["roads"]:
		if r[3]:
			continue
		var rp: PackedVector3Array = r[1]
		for e: Vector3 in [rp[0], rp[-1]]:
			var k: Vector2i = key.call(e)
			if not ends.has(k):
				ends[k] = []
			(ends[k] as Array).append(float(r[2]) * 0.5)
	# Junction boxes (metres at a road's end with no lines; > 0: a zebra and
	# a stop line outside it, < 0: plain only). Priority: at a junction
	# where two arms carry straight on (a T, a roundabout's ring), that road
	# keeps its lines right through and only the side road stops; the
	# gateway's slip road tapers into the main line with no markings.
	var dirs := {}   # node key -> [[road index, unit dir from the node, hw]]
	var ri := 0
	for r in plan_data["roads"]:
		if not r[3]:
			var rp: PackedVector3Array = r[1]
			for e in 2:
				var p0 := rp[0] if e == 0 else rp[-1]
				var q := _point_at(rp, 6.0) if e == 0 else _point_at(rp, _length(rp) - 6.0)
				var dv := q - p0
				dv.y = 0.0
				var k: Vector2i = key.call(p0)
				if not dirs.has(k):
					dirs[k] = []
				(dirs[k] as Array).append([ri, dv.normalized(), float(r[2]) * 0.5])
		ri += 1
	var merge: Dictionary = plan_data.get("merge", {})
	var box := func(e: Vector3, hw: float, idx: int) -> float:
		var arms: Array = dirs.get(key.call(e), [])
		if arms.size() < 3:
			return 0.0
		var me: Array = []
		for a: Array in arms:
			if int(a[0]) == idx:
				me = a
		if me.is_empty():
			return 0.0
		var name: String = plan_data["roads"][idx][0]
		if not merge.is_empty() and key.call(e) == key.call(merge["node"]):
			return -float(merge["taper"]) if name == merge["slip"] else 0.0
		# A through pair (arms ~opposite): this road is on it → no box.
		var through_hw := 0.0
		for a: Array in arms:
			for b: Array in arms:
				if int(a[0]) < int(b[0]) and (a[1] as Vector3).dot(b[1]) < -0.9:
					if int(a[0]) == idx or int(b[0]) == idx:
						return 0.0
					through_hw = maxf(through_hw, maxf(float(a[2]), float(b[2])))
		if through_hw > 0.0:
			return through_hw + 1.0
		var widest := 0.0
		for a: Array in arms:
			if int(a[0]) != idx:
				widest = maxf(widest, float(a[2]))
		return widest + 1.0
	var jn := _road_nodes(plan_data["roads"])
	var circ0: Array = plan_data.get("circus", [])
	if not circ0.is_empty():
		for k in jn.keys():
			var np: Vector3 = jn[k]["p"]
			if Vector2(np.x, np.z).distance_to(circ0[0]) < float(circ0[1]) + 1.0:
				jn.erase(k)
	_junction_surfaces(st, jn, 0.027)
	var ridx := 0
	for r in plan_data["roads"]:
		ridx += 1
		if r[3]:
			continue  # (the bridge deck draws its own road)
		var rp2: PackedVector3Array = r[1]
		var hw := float(r[2]) * 0.5
		# (The merging slip road a hair under the main line: where it tapers
		# in, the main line's lane markings carry on over it.)
		if r[0] == "Terminal Circus":
			continue   # (drawn as one ring: _circus_surface)
		var lift := 0.029 if not merge.is_empty() and r[0] == merge["slip"] else 0.03
		var circ: Array = plan_data.get("circus", [])
		var b0: float = box.call(rp2[0], hw, ridx - 1)
		var b1: float = box.call(rp2[-1], hw, ridx - 1)
		# (Roundabout arms: no stop box – the ring's give-way, splitter and
		# set-back crossing are drawn with it.)
		if not circ.is_empty():
			if Vector2(rp2[0].x, rp2[0].z).distance_to(circ[0]) < float(circ[1]) + 1.0:
				b0 = 0.0
			if Vector2(rp2[-1].x, rp2[-1].z).distance_to(circ[0]) < float(circ[1]) + 1.0:
				b1 = 0.0
		_strip(st, rp2, hw, lift, 2, COL_ROAD, b0, b1)
	_circus_surface(st)
	for hp: Vector3 in plan_data["helipads"]:
		if hp.y > LAND_Y + 1.0:
			continue
		_pad(st, hp, LAND_Y + 0.035)
	# Knolls: radial grass domes over the flat land (1.5 cm proud at their rim).
	var knoll_faces := PackedVector3Array()
	for k: Array in knolls():
		knoll_faces.append_array(_knoll(st, k))
	# The shore all round: quay walls where it's engineered, sand beaches
	# sloping into the sea, boulder revetments elsewhere (shore_band()).
	var shore_faces := _shore_bands(st)
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
	var ksh := ConcavePolygonShape3D.new()
	ksh.set_faces(knoll_faces)
	var kcs := CollisionShape3D.new()
	kcs.shape = ksh
	street.add_child(kcs)
	# The beaches and revetments are solid too (walk down to the water).
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(shore_faces)
	var scs := CollisionShape3D.new()
	scs.shape = sh
	street.add_child(scs)


## One knoll: rings × segments of grass following knoll_h(); returns its
## collision faces.
func _knoll(st: SurfaceTool, k: Array) -> PackedVector3Array:
	var c: Vector2 = k[0]
	var RINGS := 10
	var SEG := 28
	var grid: Array = []
	for i in RINGS + 1:
		var row: Array = []
		var r := 1.0 - float(i) / RINGS
		for j in SEG:
			var a := TAU * j / SEG
			var x := c.x + cos(a) * float(k[1]) * r
			var z := c.y + sin(a) * float(k[2]) * r
			row.append(Vector3(x, LAND_Y + knoll_h(x, z) + 0.015, z))
			if i == RINGS:
				break   # (the summit: one point)
		grid.append(row)
	var faces := PackedVector3Array()
	var col := Color(COL_GRASS.r, COL_GRASS.g, COL_GRASS.b, 1.5 / 8.0)
	var put := func(a: Vector3, b: Vector3, d: Vector3) -> void:
		var n := (d - a).cross(b - a).normalized()
		if n.y < 0.0:
			var t := b
			b = d
			d = t
			n = -n
		for v: Vector3 in [a, d, b]:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(Vector2(v.x, v.z))
			st.set_uv2(Vector2(0, 0))
			st.add_vertex(v)
		faces.append_array(PackedVector3Array([a, d, b]))
	for i in RINGS:
		var A: Array = grid[i]
		var B: Array = grid[i + 1]
		for j in SEG:
			var j2 := (j + 1) % SEG
			if B.size() == 1:
				put.call(A[j], A[j2], B[0])
			else:
				put.call(A[j], A[j2], B[j2])
				put.call(A[j], B[j2], B[j])
	return faces


## Shore profiles: [metres out from the land's edge, height] per kind.
const SHORE_PROFILES := [
	[[0.0, LAND_Y], [0.0, -9.0]],                                                     # quay: a wall
	[[0.0, LAND_Y], [7.0, LAND_Y - 0.55], [18.0, 1.1], [29.0, 0.05], [40.0, -1.0], [54.0, -4.0]],   # beach
	[[0.0, LAND_Y], [3.5, LAND_Y - 0.5], [9.0, 0.6], [14.0, -0.9], [19.0, -3.0], [25.0, -6.5]],    # rock
]


## Outward normal at outline point i (averaged over its two edges).
static func _out_n(o: PackedVector2Array, i: int) -> Vector2:
	var n := o.size()
	var a := o[(i - 1 + n) % n]
	var b := o[i]
	var c := o[(i + 1) % n]
	var d := ((b - a).normalized() + (c - b).normalized()).normalized()
	var nn := Vector2(d.y, -d.x)
	if Geometry2D.is_point_in_polygon(b + nn * 0.5, o):
		nn = -nn
	return nn


## A row of the profile for kind k at outline point i (rock jitters), its
## width scaled by w.
static func _shore_row(o: PackedVector2Array, i: int, k: int, w := 1.0) -> PackedVector3Array:
	var p := o[i]
	var nn := _out_n(o, i)
	var row := PackedVector3Array()
	var prof: Array = SHORE_PROFILES[k]
	for j in prof.size():
		var d: float = prof[j][0] * (w if k != 0 else 1.0)
		var y: float = prof[j][1]
		if k == 2 and j > 0:
			var h := sin(p.x * 1.37 + p.y * 0.91 + j * 2.1) * 0.5 + sin(p.x * 0.43 - p.y * 1.7 + j) * 0.5
			d += h * 1.6
			y += h * 0.45
		row.append(Vector3(p.x + nn.x * d, y, p.y + nn.y * d))
	return row


## Shore width factor along the coast (0.7–1.45): beaches swell and pinch.
static func _shore_w(p: Vector2) -> float:
	return 0.7 + 0.75 * clampf(0.5 + 0.5 * (sin(p.x * 0.021 + p.y * 0.013) * 0.6 + sin(p.y * 0.034 - p.x * 0.017 + 2.0) * 0.4), 0.0, 1.0)


## How sandy the shore is at outline point i (0 rock … 1 beach), averaged
## over its natural neighbours so beaches fade into rock over ~60 m
## instead of stepping (quays: −1, never blended).
static func _sandiness(o: PackedVector2Array, i: int) -> float:
	if shore_kind(i) == 0:
		return -1.0
	var n := o.size()
	var acc := 0.0
	var cnt := 0.0
	for j in range(-3, 4):
		var k := shore_kind((i + j + n) % n)
		if k == 0:
			continue
		var wgt := 1.0 - absf(j) / 4.0
		acc += (1.0 if k == 1 else 0.0) * wgt
		cnt += wgt
	return acc / maxf(cnt, 0.001)


## The blended row at outline point i: beach and rock profiles mixed by
## sandiness, with the width factor; quays as they are.
static func _blend_row(o: PackedVector2Array, i: int) -> PackedVector3Array:
	return _row_as(o, i, _sandiness(o, i))


## Point i's row with sandiness sd (−1: a quay wall). Clamped to under half
## the open water in front (a narrow cove's two beaches used to cross and
## stand up as a sand ridge over the water and the grass), its last point
## tucked under the baked sea floor.
static func _row_as(o: PackedVector2Array, i: int, sd: float) -> PackedVector3Array:
	if sd < 0.0:
		return _shore_row(o, i, 0)
	var w := _shore_w(o[i])
	var bch := _shore_row(o, i, 1, w)
	var rck := _shore_row(o, i, 2, w)
	var row := PackedVector3Array()
	var t := smoothstep(0.0, 1.0, sd)
	for j in bch.size():
		row.append(rck[j].lerp(bch[j], t))
	var p := o[i]
	var nn := _out_n(o, i)
	var prof: Array = []
	for v in row:
		prof.append([nn.dot(Vector2(v.x, v.z) - p), v.y])
	prof = BuildingMesher.fit_row(prof, _reach_at(o, i))
	var side: Array = []
	for v in row:
		side.append(Vector2(v.x, v.z) - p - nn * nn.dot(Vector2(v.x, v.z) - p))
	for j in row.size():
		var q: Vector2 = p + nn * float(prof[j][0]) + (side[j] as Vector2)
		row[j] = Vector3(q.x, float(prof[j][1]), q.y)
	SeabedMesh.tuck(row, xform())
	return row


static var _reach := PackedFloat32Array()


## How far point i's shore may reach: under half the distance to the next
## land along its normal (this island across a cove, a city, a landform).
static func _reach_at(o: PackedVector2Array, i: int) -> float:
	if _reach.size() != o.size():
		_reach.resize(o.size())
		for k in o.size():
			var p := o[k]
			var nn := _out_n(o, k)
			var r := 200.0
			var t := 4.0
			while t < 400.0:
				var q := p + nn * t
				var wq := w2(q)
				if Geometry2D.is_point_in_polygon(q, o) or (Landforms.enabled and Landforms.contains(wq.x, wq.y)):
					r = t * 0.45
					break
				t += 3.0 if t < 80.0 else 8.0
			_reach[k] = r
	return _reach[i]


## Shore geometry into st (sand / rock / concrete, UV2.y = -1 marks shore for
## island_ground.gdshader); returns the collision faces.
func _shore_bands(st: SurfaceTool) -> PackedVector3Array:
	var o := outline()
	var faces := PackedVector3Array()
	var quay_c := Color(0.55, 0.53, 0.5)
	var sand_c := Color(0.8, 0.72, 0.55)
	var rock_c := Color(0.42, 0.4, 0.37)
	var colour := func(sd: float) -> Color:
		if sd < 0.0:
			return quay_c
		return rock_c.lerp(sand_c, smoothstep(0.35, 0.65, sd))
	var out_dir := [Vector2.ZERO]   # (the stretch's outward normal: lambdas capture by value)
	var put := func(q: Array, cs: Array) -> void:
		var nrm := ((q[2] as Vector3) - (q[0] as Vector3)).cross((q[1] as Vector3) - (q[0] as Vector3)).normalized()
		var od: Vector2 = out_dir[0]
		if absf(nrm.y) < 0.5 and od != Vector2.ZERO:
			# Walls face the sea (a vertical face's sign was arbitrary: half
			# the quays were lit from behind - flat black from the water).
			if Vector2(nrm.x, nrm.z).dot(od) < 0.0:
				nrm = -nrm
		elif nrm.y < -0.01:
			nrm = -nrm
		for vi in 3:
			var v: Vector3 = q[vi]
			var c: Color = cs[vi]
			if v.y < -1.2 and c.r > 0.7:
				c = c.darkened(0.28)   # wet sand (the sea is at -1.6)
			c.a = 0.5 / 8.0
			st.set_color(c)
			st.set_normal(nrm)
			st.set_uv(Vector2(v.x, v.z))
			st.set_uv2(Vector2(0.0, -1.0))
			st.add_vertex(v)
			faces.append(v)
	var n := o.size()
	var sds: Array = []
	for i in n:
		sds.append(_sandiness(o, i))
	for i in n:
		var i2 := (i + 1) % n
		var s1: float = sds[i]
		var s2: float = sds[i2]
		var ca: Color = colour.call(s1)
		var cb: Color = colour.call(s2)
		var A := _row_as(o, i, s1)
		var B := _row_as(o, i2, s2)
		out_dir[0] = (_out_n(o, i) + _out_n(o, i2)).normalized()
		if (s1 < 0.0) != (s2 < 0.0):
			# Quay meets natural shore: run this stretch with point i's own
			# profile, then close the step to point i2's with rock.
			B = _row_as(o, i2, s1)
			var own := _row_as(o, i2, s2)
			for j in mini(B.size(), own.size()) - 1:
				put.call([B[j], own[j + 1], B[j + 1]], [rock_c, rock_c, rock_c])
				put.call([B[j], B[j + 1], own[j + 1]], [rock_c, rock_c, rock_c])
			cb = ca
		var is_quay := s1 < 0.0
		for j in mini(A.size(), B.size()) - 1:
			var a := A[j]
			var b := B[j]
			var c := B[j + 1]
			var d := A[j + 1]
			var up := (c - a).cross(b - d)
			if up.y < 0.0 or (is_quay and up.dot(Vector3(d.x - a.x, 0, d.z - a.z)) < 0.0):
				put.call([a, d, c], [ca, ca, cb])
				put.call([a, c, b], [ca, cb, cb])
			else:
				put.call([a, b, c], [ca, cb, cb])
				put.call([a, c, d], [ca, cb, ca])
	return faces


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


## Like _mesh, into any node (SkyportAirport's pieces).
func _mesh_into(m: BuildingMesher, nm: String, target: Node, range_begin: float, range_end: float) -> void:
	var prev := _target
	_target = target
	_mesh(m, nm, range_begin, range_end)
	_target = prev


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
			if b.get("mesh", true):
				far.add_building(b, false)
		_mesh(far, "Skyline_" + key, 0.0, FAR_RANGE)


## One district's detailed buildings and their collision (near content).
func _build_detail(key: String) -> void:
	var near := BuildingMesher.new()
	for b: Dictionary in _groups().get(key, []):
		if b.get("mesh", true):   # (the terminal and the tower are drawn by SkyportAirport)
			near.add_building(b, true)
			near.add_features(b)
		if b.get("hollow", false):
			continue   # (a walk-in venue: the game builds its room and collision)
		for bx in BuildingMesher.collision_boxes(b):
			CityWorld._add_box(body, bx)
	_mesh(near, "Detail_" + key, 0.0, 0.0)
	var detail := near_root.get_node_or_null("Detail_" + key) as GeometryInstance3D
	var skyline := get_node_or_null("Skyline_" + key) as GeometryInstance3D
	if detail and skyline:
		skyline.visibility_range_begin = DETAIL_RANGE
		skyline.visibility_range_begin_margin = 20.0
		CityWorld.link_lods(detail, skyline)
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
## The bridges to the two city islands, built in world space (a top-level
## node: the island's own transform doesn't apply). Each is built in its own
## frame – the deck along +x from the sea wall (x 0) to the quay (x L) – and
## that frame is placed between its city end and its landing.
func _build_bridge(_street: StaticBody3D) -> void:
	var root := Node3D.new()
	root.name = "Bridges"
	root.top_level = true
	add_child(root)
	root.global_transform = Transform3D.IDENTITY
	for B: Dictionary in plan_data["bridges"]:
		_build_one_bridge(B, root)
	# The Airport Line (world space, always loaded: it's seen from both
	# cities): viaduct, stations, access; decks and platforms walkable.
	if plan_data.has("rail"):
		var rr := Node3D.new()
		rr.name = "AirportLine"
		root.add_child(rr)
		var rb := StaticBody3D.new()
		rb.name = "Structure"
		rb.collision_layer = 1 | (1 << 1)
		rr.add_child(rb)
		AirportRail.build(rr, rb, self, _layout)


func _build_one_bridge(B: Dictionary, root: Node3D) -> void:
	var u: Vector3 = B["u"]
	var S: Vector3 = B["S"]
	var L: float = B["L"]
	var fr := Node3D.new()
	fr.name = String(B["name"]).replace(" ", "")
	fr.transform = Transform3D(Basis(u, Vector3.UP, u.cross(Vector3.UP)), Vector3(S.x, 0.0, S.z))
	root.add_child(fr)
	var inv := fr.transform.affine_inverse()
	var road_body := StaticBody3D.new()   # (the driving surface: ground layer)
	road_body.name = "Road"
	road_body.collision_layer = 1 << 3
	fr.add_child(road_body)
	var body := StaticBody3D.new()        # railings, piers, pylon
	body.name = "Structure"
	body.collision_layer = 1 | (1 << 1)
	fr.add_child(body)
	var at := func(sd: float) -> Vector3: return Vector3(sd, deck_y(B, sd), 0.0)
	var m := BuildingMesher.new()
	var white := Color(0.88, 0.88, 0.86)
	var deck_c := Color(0.42, 0.43, 0.45)
	# Deck, railings and edge girders, segment by segment.
	var n := maxi(24, int(L / 12.0))
	for i in n:
		var a: Vector3 = at.call(L * i / n)
		var c: Vector3 = at.call(L * (i + 1) / n)
		var d := (c - a).normalized()
		var ext := d * 0.3
		var a0 := a - ext + Vector3.DOWN * 0.8
		var c0 := c + ext + Vector3.DOWN * 0.8
		m.beam(a0, c0, 26.0, 1.6, deck_c)
		_box_beam(road_body, a0, c0, 26.0, 1.6)
		for sg: float in [-1.0, 1.0]:
			var o := Vector3(0, 0, sg * 12.6)
			m.beam(a + o + Vector3.UP * 0.55, c + o + Vector3.UP * 0.55, 0.5, 1.1, white)
			_box_beam(body, a + o + Vector3.UP * 0.55, c + o + Vector3.UP * 0.55, 0.5, 1.1)
			m.beam(a + Vector3(0, -1.9, sg * 11.0) - ext, c + Vector3(0, -1.9, sg * 11.0) + ext, 1.2, 1.6, white)
	# On over the quay at ground level (see LAND_RUN).
	var e0 := Vector3(L - 0.3, LAND_Y - 0.8, 0.0)
	var e1 := Vector3(L + LAND_RUN, LAND_Y - 0.8, 0.0)
	m.beam(e0, e1, 26.0, 1.6, deck_c)
	_box_beam(road_body, e0, e1, 26.0, 1.6)
	# Its parapets and edge girders carry on until both corners are over the
	# quay (the slab alone read as a bare box standing in the sea).
	var qe: PackedFloat32Array = B.get("quay_ext", PackedFloat32Array([0.0, 0.0]))
	for k in 2:
		var sg := -1.0 if k == 0 else 1.0
		var qx := qe[k]
		if qx > 0.5:
			var a := Vector3(L - 0.3, LAND_Y, sg * 12.6)
			var c := Vector3(L + qx, LAND_Y, sg * 12.6)
			m.beam(a + Vector3.UP * 0.55, c + Vector3.UP * 0.55, 0.5, 1.1, white)
			_box_beam(body, a + Vector3.UP * 0.55, c + Vector3.UP * 0.55, 0.5, 1.1)
			m.beam(Vector3(L - 0.3, LAND_Y - 1.9, sg * 11.0), Vector3(L + qx, LAND_Y - 1.9, sg * 11.0), 1.2, 1.6, white)
	# Piers every 32 m from the sea bed (not at the pylon).
	var mid := L * 0.5
	var sd := 30.0
	while sd < L - 12.0:
		var clear := 24.0 if String(B.get("style", "fan")) == "fan" else TRUSS_HALF - 6.0
		if absf(sd - mid) > clear:
			var dy := deck_y(B, sd)
			if dy > 3.0:
				for sg: float in [-1.0, 1.0]:
					m.beam(Vector3(sd, -6.0, sg * 7.0), Vector3(sd, dy - 1.6, sg * 7.0), 1.8, 1.8, white)
					_box_beam(body, Vector3(sd, -6.0, sg * 7.0), Vector3(sd, dy - 1.6, sg * 7.0), 1.8, 1.8)
				m.beam(Vector3(sd, dy - 2.4, -8.5), Vector3(sd, dy - 2.4, 8.5), 1.6, 1.6, white)
		sd += 32.0
	if String(B.get("style", "fan")) == "truss":
		_build_truss(B, m, body, mid)
	else:
		_build_fan(B, m, body, mid, L)
	# Deck lamps every 36 m.
	var lx := 18.0
	while lx < L:
		var ly := deck_y(B, lx)
		for sg: float in [-1.0, 1.0]:
			m.beam(Vector3(lx, ly, sg * 12.2), Vector3(lx, ly + 7.5, sg * 12.2), 0.22, 0.22, Color(0.25, 0.26, 0.28))
			m.beam(Vector3(lx, ly + 7.4, sg * 12.2), Vector3(lx, ly + 7.4, sg * 10.6), 0.2, 0.2, Color(0.25, 0.26, 0.28))
		lx += 36.0
	_landing_walls(B, fr.transform, body, m)
	var prev := _target
	_target = fr
	_mesh(m, "Bridge", 0.0, FAR_RANGE)
	_target = prev
	# The road surface: landing, deck, and on across the quay to Bridge Road.
	var deck := PackedVector3Array()
	for i in n + 1:
		deck.append(at.call(L * i / n))
	var tail := PackedVector3Array([Vector3(L, LAND_Y, 0.0), Vector3(L + LAND_RUN, LAND_Y, 0.0), inv * (B["Jw"] as Vector3)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_landing_road(B, road_body, st)
	_strip(st, deck, 11.0, 0.03, 7, COL_ROAD)
	_strip(st, tail, 11.0, 0.03, 2, COL_ROAD)
	var mi := MeshInstance3D.new()
	mi.name = "BridgeRoad"
	mi.mesh = st.commit()
	mi.material_override = _ground_mat()
	mi.visibility_range_end = 2600.0
	fr.add_child(mi)



## The Harbour Bridge's landmark: an A-frame pylon at mid-span with cables
## fanning to the deck both ways.
func _build_fan(B: Dictionary, m: BuildingMesher, body: StaticBody3D, mid: float, L: float) -> void:
	var white := Color(0.88, 0.88, 0.86)
	var cy0 := deck_y(B, mid)
	var top := cy0 + 74.0
	for sg: float in [-1.0, 1.0]:
		var foot := Vector3(mid, -6.0, sg * 16.0)
		var head := Vector3(mid, top, sg * 2.2)
		m.beam(foot, head, 4.0, 4.0, white)
		_box_beam(body, foot, head, 4.0, 4.0)
	for cy: float in [cy0 - 2.2, cy0 + 30.0, top - 20.0]:
		var t := (cy + 6.0) / (top + 6.0)
		var half := lerpf(16.0, 2.2, t)
		m.beam(Vector3(mid, cy, -half), Vector3(mid, cy, half), 3.0, 3.0, white)
		_box_beam(body, Vector3(mid, cy, -half), Vector3(mid, cy, half), 3.0, 3.0)
	m.solid(mid - 9.0, -22.0, mid + 9.0, 22.0, -8.0, 0.6, Color(0.6, 0.6, 0.58))   # pier cap at the water
	_box_beam(body, Vector3(mid, -8.0, 0.0), Vector3(mid, 0.6, 0.0), 18.0, 44.0)
	for sg: float in [-1.0, 1.0]:
		for k in 10:
			var off := 18.0 + k * minf(13.0, (mid - 30.0) / 10.0)
			for dir: float in [-1.0, 1.0]:
				var dx := mid + dir * off
				if dx < 6.0 or dx > L - 6.0:
					continue
				var anchor := Vector3(dx, deck_y(B, dx) + 0.4, sg * 11.6)
				var tp := Vector3(mid, top - 4.0 - k * 3.6, sg * 2.6)
				m.beam(anchor, tp, 0.28, 0.28, Color(0.95, 0.95, 0.93))


## The Westbank Bridge: a steel through-truss over the main span – a
## camelback top chord (deepest mid-span), verticals and Warren diagonals
## each side, portal and top bracing well clear of the traffic, on heavy
## river piers. Weathered green-grey steel: Westbank's older, industrial
## character, unlike the Harbour Bridge's white A-frame, the strait's red
## suspension bridge and the white rail arch.
func _build_truss(B: Dictionary, m: BuildingMesher, body: StaticBody3D, mid: float) -> void:
	var steel := Color(0.3, 0.38, 0.34)
	var pier := Color(0.68, 0.67, 0.64)
	var n := 16
	var low := func(sg: float, k: int) -> Vector3:
		var sd := mid - TRUSS_HALF + 2.0 * TRUSS_HALF * k / n
		return Vector3(sd, deck_y(B, sd) + 0.2, sg * 14.2)
	var high := func(sg: float, k: int) -> Vector3:
		var u := -1.0 + 2.0 * k / n
		var p: Vector3 = low.call(sg, k)
		return p + Vector3(0.0, 14.0 + 9.0 * (1.0 - u * u), 0.0)
	for sg: float in [-1.0, 1.0]:
		for k in n:
			var a: Vector3 = low.call(sg, k)
			var c: Vector3 = low.call(sg, k + 1)
			m.beam(a, c, 1.2, 2.2, steel)                              # bottom chord
			if k > 0 and k < n - 1:
				var ta: Vector3 = high.call(sg, k)
				var tc: Vector3 = high.call(sg, k + 1)
				m.beam(ta, tc, 1.4, 1.6, steel)                        # top chord
				_box_beam(body, ta, tc, 1.4, 1.6)
		for k in range(1, n):
			var b0: Vector3 = low.call(sg, k)
			var t0: Vector3 = high.call(sg, k)
			m.beam(b0, t0, 0.9, 0.9, steel)                            # vertical
			_box_beam(body, b0, t0, 0.9, 0.9)
			# Warren diagonals, alternating; the end posts slope down to the bearings.
			var nb: Vector3 = low.call(sg, k + 1 if k % 2 == 1 else k - 1)
			if k == 1:
				m.beam(t0, low.call(sg, 0), 1.2, 1.2, steel)
			elif k == n - 1:
				m.beam(t0, low.call(sg, n), 1.2, 1.2, steel)
			else:
				m.beam(t0, nb, 0.7, 0.7, steel)
	# Top bracing: struts across at every node, X-bracing every other bay.
	for k in range(1, n):
		var a: Vector3 = high.call(-1.0, k)
		var c: Vector3 = high.call(1.0, k)
		m.beam(a, c, 0.8, 0.9, steel)
		if k < n - 1 and k % 2 == 1:
			m.beam(a, high.call(1.0, k + 1), 0.45, 0.45, steel)
			m.beam(c, high.call(-1.0, k + 1), 0.45, 0.45, steel)
	# River piers under the bearings.
	for sd: float in [mid - TRUSS_HALF, mid + TRUSS_HALF]:
		var dy := deck_y(B, sd)
		m.solid(sd - 6.0, -18.0, sd + 6.0, 18.0, -8.0, dy - 1.6, pier)
		m.solid(sd - 7.5, -19.5, sd + 7.5, 19.5, -8.0, 0.4, pier.darkened(0.25))
		_box_beam(body, Vector3(sd, -8.0, 0.0), Vector3(sd, dy - 1.6, 0.0), 36.0, 12.0)


## Blend the raised approach sideways into the coast road. The bridge-axis
## crossing was smooth, but the rectangular ramp had a lip for coast traffic.
## The landing's road (see LAND_COLS), in the bridge's frame (x along from
## S, z across, y up): marked carriageway from the kerb on (the deck's
## markings carry on), plain asphalt in the mouth (it lies on the coast
## road's own lanes), paved verges under the parapets. Collision: one
## convex slab per cell, its top the surface.
func _landing_road(B: Dictionary, road_body: StaticBody3D, st: SurfaceTool) -> void:
	var land: Dictionary = B["land"]
	var cols: PackedFloat32Array = land["cols"]
	var als: Array = land["al"]
	var hs: Array = land["h"]
	var nr: int = (als[0] as PackedFloat32Array).size()
	var P := func(j: int, i: int) -> Vector3:
		return Vector3((als[j] as PackedFloat32Array)[i], (hs[j] as PackedFloat32Array)[i], cols[j])
	for j in cols.size() - 1:
		var verge := j == 0 or j == cols.size() - 2
		for i in nr - 1:
			var q: Array[Vector3] = [P.call(j, i), P.call(j, i + 1), P.call(j + 1, i + 1), P.call(j + 1, i)]
			var mouth := i < MOUTH_ROWS and verge   # (verges in the mouth: on the street's asphalt)
			# (In the mouth the verges lie on the coast road: plain asphalt.)
			var paved := verge and not mouth
			var col := Color(COL_PAVE.r, COL_PAVE.g, COL_PAVE.b, 0.5 / 8.0) if paved else Color(COL_ROAD.r, COL_ROAD.g, COL_ROAD.b, 7.5 / 8.0)
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				var t: Array[Vector3] = [q[tri[0]], q[tri[1]], q[tri[2]]]
				if (t[1] - t[0]).cross(t[2] - t[0]).y > 0.0:
					t.reverse()
				for v: Vector3 in t:
					st.set_color(col)
					st.set_normal(Vector3.UP)
					if mouth or (verge and not paved):
						st.set_uv(Vector2(50.0, v.x))   # (no lane lines)
						st.set_uv2(Vector2(100.0, 0.0))
					else:
						st.set_uv(Vector2(v.z, v.x))
						st.set_uv2(Vector2(11.0, 0.0))
					st.add_vertex(v + Vector3.UP * 0.03)
			var hull := PackedVector3Array()
			for v: Vector3 in q:
				hull.append(v)
				hull.append(v + Vector3.DOWN * 0.6)
			var shape := ConvexPolygonShape3D.new()
			shape.points = hull
			var cs := CollisionShape3D.new()
			cs.shape = shape
			road_body.add_child(cs)


## The landing's sides: a concrete wall from the road edge down into the
## ground (or the sea), and from the kerb on a parapet like the deck's.
func _landing_walls(B: Dictionary, frame: Transform3D, body: StaticBody3D, m: BuildingMesher) -> void:
	var land: Dictionary = B["land"]
	var cols: PackedFloat32Array = land["cols"]
	var als: Array = land["al"]
	var hs: Array = land["h"]
	var city: CityLayout = _layout if B["city"] == "island" else _layout.mainland
	var white := Color(0.88, 0.88, 0.86)
	for j: int in [0, cols.size() - 1]:
		var sg := signf(cols[j])
		var row: PackedFloat32Array = als[j]
		var h: PackedFloat32Array = hs[j]
		var foot := func(i: int) -> float:
			var w := frame * Vector3(row[i], 0.0, cols[j] + sg * 0.3)
			if _layout.is_water(Vector3(w.x, 0.0, w.z)):
				return -3.0
			return city.ground_y(w.x, w.z) - 0.4
		for i in row.size() - 1:
			var a := Vector3(row[i], h[i], cols[j])
			var b := Vector3(row[i + 1], h[i + 1], cols[j])
			var fa: float = foot.call(i)
			var fb: float = foot.call(i + 1)
			if a.y - fa < 0.45 and b.y - fb < 0.45 and i < MOUTH_ROWS:
				continue   # (flush with the road: nothing to show)
			var nrm := Vector3(0, 0, sg)
			var qa := Vector3(a.x, fa, a.z)
			var qb := Vector3(b.x, fb, b.z)
			# (Winding: outward, like BuildingMesher's walls.)
			if sg > 0.0:
				m.quad(qa, a, b, qb, nrm, Vector2(0, fa), Vector2(0, a.y), Vector2(1, b.y), Vector2(1, fb), white, BuildingMesher.KIND_TRIM, 0.0, 0.0)
			else:
				m.quad(qb, b, a, qa, nrm, Vector2(0, fb), Vector2(0, b.y), Vector2(1, a.y), Vector2(1, fa), white, BuildingMesher.KIND_TRIM, 0.0, 0.0)
			if i >= MOUTH_ROWS:
				var o := Vector3(0, 0, -sg * 0.25)   # (parapet centre: ±12.6, as on the deck)
				var ext := (b - a).normalized() * 0.05
				m.beam(a + o + Vector3.UP * 0.55 - ext, b + o + Vector3.UP * 0.55 + ext, 0.5, 1.1, white)
				_box_beam(body, a + o + Vector3.UP * 0.55 - ext, b + o + Vector3.UP * 0.55 + ext, 0.5, 1.1)


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
			# (A steel gantry on three piles, lamps along the top – the bar
			# used to float over the sea on one thin post.)
			var grey := Color(0.42, 0.43, 0.45)
			m.solid(ax - 0.25, a.z - 8.0, ax + 0.25, a.z + 8.0, LAND_Y + 0.1, LAND_Y + 0.45, grey)
			for lz: float in [-6.5, 0.0, 6.5]:
				m.solid(ax - 0.45, a.z + lz - 0.45, ax + 0.45, a.z + lz + 0.45, SEA_Y - 3.0, SEA_Y + 0.6, Color(0.3, 0.3, 0.29))
				m.solid(ax - 0.18, a.z + lz - 0.18, ax + 0.18, a.z + lz + 0.18, SEA_Y + 0.6, LAND_Y + 0.1, grey)
			for li in 7:
				var lz2 := -7.2 + li * 2.4
				m.solid(ax - 0.3, a.z + lz2 - 0.3, ax + 0.3, a.z + lz2 + 0.3, LAND_Y + 0.45, LAND_Y + 0.75, Color(0.98, 0.95, 0.85))
	# Ground service: tugs and baggage carts by the stands.
	for s: Array in plan_data["stands"]:
		var p: Vector3 = s[0]
		m.solid(p.x - 20.0, p.z - 26.0, p.x - 16.0, p.z - 22.5, LAND_Y, LAND_Y + 1.6, Color(0.92, 0.75, 0.15))
		m.solid(p.x + 16.0, p.z - 26.0, p.x + 22.0, p.z - 23.0, LAND_Y, LAND_Y + 1.2, Color(0.75, 0.76, 0.78))
	# Windsock mast.
	m.beam(Vector3(1500, LAND_Y, 430), Vector3(1500, LAND_Y + 8.0, 430), 0.2, 0.2, Color(0.9, 0.9, 0.9))
	m.beam(Vector3(1500, LAND_Y + 7.6, 430), Vector3(1503.5, LAND_Y + 7.3, 430), 0.7, 0.7, Color(0.95, 0.45, 0.1))
	# The terminal roof's raking columns, landside and airside.
	var tx := TERMINAL_ROOF.position.x + 12.0
	while tx < TERMINAL_ROOF.end.x - 6.0:
		# [roof z, foot z]: landside on the drop-off pavement (Terminal Road
		# runs under the overhang), airside by the gates.
		for zs: Array in [[160.0, 163.5], [246.0, 243.0]]:
			var zz: float = zs[0]
			var top := Vector3(tx, terminal_roof_y(tx, zz) - 0.4, zz)
			m.beam(Vector3(tx + 1.5, LAND_Y, zs[1]), top, 0.45, 0.45, Color(0.86, 0.87, 0.88))
			m.beam(Vector3(tx - 1.5, LAND_Y, zs[1]), top, 0.45, 0.45, Color(0.86, 0.87, 0.88))
		tx += 32.0
	# The door frames attach to each hangar's actual apron-facing wall.
	# Their depth clears the facade's cladding and its ledges.
	for hangar: Array in HANGARS:
		var left := float(hangar[0]) + 4.0
		var right := float(hangar[2]) - 4.0
		var front := float(hangar[3])
		var height := float(hangar[4]) - 4.2
		var frame := Color("777f85")
		m.solid(left, front - 0.03, right, front + 0.35, LAND_Y, LAND_Y + height, Color("48525c"))
		m.solid(left - 0.28, front - 0.06, right + 0.28, front + 0.62, LAND_Y + height, LAND_Y + height + 0.62, frame)
		for k in 9:
			var gate := lerpf(left, right, float(k) / 8.0)
			m.solid(gate - 0.105, front + 0.29, gate + 0.105, front + 0.48, LAND_Y, LAND_Y + height, frame)
		for k in [2.4, 4.8, 7.2]:
			m.solid(left, front + 0.30, right, front + 0.455, LAND_Y + k, LAND_Y + k + 0.11, frame)
	_mesh(m, "AirportDressing", 0.0, 1400.0)


## The terminal roof: one long curved shell (a shallow wave along it) that
## oversails the hall on both sides – over the drop-off canopy landside and
## the gates airside – on raking columns, glazed down to the hall between.
const TERMINAL_HALL := 14.0
const TERMINAL_ROOF := Rect2(1946, 146, 328, 104)


static func terminal_roof_y(x: float, z: float) -> float:
	var u := clampf((z - TERMINAL_ROOF.position.y) / TERMINAL_ROOF.size.y, 0.0, 1.0)
	var arch := sin(PI * u)
	return LAND_Y + TERMINAL_HALL + 1.0 + 8.5 * arch + 1.6 * sin((x - TERMINAL_ROOF.position.x) * 0.038) * arch


func _build_terminal(street: StaticBody3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var R := TERMINAL_ROOF
	var nx := 41
	var nz := 14
	var grid: Array = []
	for i in nx + 1:
		var row: Array = []
		for j in nz + 1:
			var xx := R.position.x + R.size.x * i / nx
			var zz := R.position.y + R.size.y * j / nz
			row.append(Vector3(xx, terminal_roof_y(xx, zz), zz))
		grid.append(row)
	var put := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		for v: Vector3 in [a, b, c]:
			st.add_vertex(v)
			faces.append(v)
	for i in nx:
		for j in nz:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c: Vector3 = grid[i + 1][j + 1]
			var d: Vector3 = grid[i][j + 1]
			# Top (clockwise seen from above) and the soffit underneath.
			put.call(a, b, c)
			put.call(a, c, d)
			var dn := Vector3(0, -0.6, 0)   # (the soffit: a shell's thickness below)
			put.call(a + dn, c + dn, b + dn)
			put.call(a + dn, d + dn, c + dn)
	st.generate_normals()
	var roof := MeshInstance3D.new()
	roof.name = "TerminalRoof"
	roof.mesh = st.commit()
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.9, 0.91, 0.92)
	rm.metallic = 0.12
	rm.roughness = 0.42
	roof.material_override = rm
	roof.visibility_range_end = 2600.0
	_target.add_child(roof)
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = sh
	street.add_child(cs)
	# (The hall's glazing, full height: SkyportAirport.build_terminal.)


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
	m.solid(1386, -300, 1400, -190, 0.6, LAND_Y, Color(0.7, 0.7, 0.68))
	CityWorld._add_box(street, AABB(Vector3(1386, 0.0, -300), Vector3(14, LAND_Y, 110)))
	_mesh(m, "Marina", 0.0, 1400.0)


## Skyport's quay edges (they were bare wall tops): in the town and by the
## marina a promenade edge – stone coping, iron railing, lamps every 24 m,
## benches facing the water; on the working quays east of x 2050 mooring
## bollards and fender piles instead. Railings collide; gaps at the marina
## piers and ramp, the bridges' ends and the rail viaduct's piers.
func _build_quayside(body: StaticBody3D) -> void:
	var o := outline()
	var n := o.size()
	var m := BuildingMesher.new()
	var iron := Color(0.16, 0.2, 0.2)
	var stone := Color(0.7, 0.67, 0.62)
	var lampc := Color(1.0, 0.95, 0.8)
	var wood := Color(0.55, 0.42, 0.3)
	var run := 0.0
	var next_lamp := 12.0
	var next_bench := 30.0
	var next_bollard := 6.0
	var blocked := func(q: Vector2) -> bool:
		if Rect2(1380, -305, 26, 120).has_point(q):
			return true   # (the marina ramp and pier roots)
		for pr: Array in plan_data["piers"]:
			if Rect2(Vector2((pr[0] as Vector3).x, (pr[0] as Vector3).z), Vector2((pr[1] as Vector3).x - (pr[0] as Vector3).x,
					(pr[1] as Vector3).z - (pr[0] as Vector3).z)).grow(4.0).has_point(q):
				return true
		var wq := w2(q)
		if under_bridge(wq.x, wq.y) or over_bridge_shore(wq.x, wq.y):
			return true
		# Never across a road: the bridges' landings run over the quay to
		# Bridge Road (the railing and a lamp stood across the carriageway).
		if road_clearance(plan_data, q) < 1.0:
			return true
		for B: Dictionary in plan_data["bridges"]:
			var bp: PackedVector3Array = B["pts"]
			for j in bp.size() - 1:
				var cp := Geometry2D.get_closest_point_to_segment(wq, Vector2(bp[j].x, bp[j].z), Vector2(bp[j + 1].x, bp[j + 1].z))
				if cp.distance_to(wq) < BRIDGE_W * 0.5 + 2.0:
					return true
		return rail_clearance(plan_data, q) < 3.0
	for i in n:
		var i2 := (i + 1) % n
		var a := o[i]
		var b := o[i2]
		var seg := a.distance_to(b)
		if shore_kind(i) != 0 or shore_kind(i2) != 0 or seg < 0.5:
			run += seg
			continue
		var nn := ((_out_n(o, i) + _out_n(o, i2)) * 0.5).normalized()
		var t := (b - a) / seg
		var town := (a.x + b.x) * 0.5 < 2050.0
		var s0 := run
		run += seg
		next_lamp = maxf(next_lamp, s0 + 6.0)
		next_bench = maxf(next_bench, s0 + 14.0)
		next_bollard = maxf(next_bollard, s0 + 3.0)
		if town:
			# Coping and railing in 4 m panels (each checked for gaps).
			var k := 0.0
			while k < seg:
				var k1 := minf(k + 4.0, seg)
				var p0 := a + t * k - nn * 0.35
				var p1 := a + t * k1 - nn * 0.35
				if not blocked.call((p0 + p1) * 0.5):
					var A := Vector3(p0.x, LAND_Y, p0.y)
					var B := Vector3(p1.x, LAND_Y, p1.y)
					_bx(m, A + Vector3.UP * 0.12, B + Vector3.UP * 0.12, 0.7, 0.24, stone)
					m.beam(A + Vector3.UP * 1.05, B + Vector3.UP * 1.05, 0.07, 0.07, iron)
					m.beam(A + Vector3.UP * 0.6, B + Vector3.UP * 0.6, 0.04, 0.04, iron)
					_bx(m, A + Vector3.UP * 0.24, A + Vector3.UP * 1.1, 0.08, 0.08, iron)
					_box_beam(body, A + Vector3.UP * 0.6, B + Vector3.UP * 0.6, 0.3, 1.2)
				k = k1
			while next_lamp < run:
				var q := a + t * (next_lamp - s0) - nn * 1.2
				next_lamp += 24.0
				if blocked.call(q):
					continue
				_bx(m, Vector3(q.x, LAND_Y, q.y), Vector3(q.x, LAND_Y + 4.2, q.y), 0.14, 0.14, iron)
				_bx(m, Vector3(q.x, LAND_Y + 4.2, q.y), Vector3(q.x, LAND_Y + 4.6, q.y), 0.34, 0.34, lampc)
				_bx(m, Vector3(q.x, LAND_Y + 4.6, q.y), Vector3(q.x, LAND_Y + 4.7, q.y), 0.46, 0.46, iron)
			while next_bench < run:
				var q2 := a + t * (next_bench - s0) - nn * 2.2
				next_bench += 36.0
				if blocked.call(q2):
					continue
				var c := Vector3(q2.x, LAND_Y, q2.y)
				var tv := Vector3(t.x, 0.0, t.y)
				var nv := Vector3(nn.x, 0.0, nn.y)
				_bx(m, c - tv * 0.9 + Vector3.UP * 0.45, c + tv * 0.9 + Vector3.UP * 0.45, 0.45, 0.08, wood)
				_bx(m, c - nv * 0.24 - tv * 0.9 + Vector3.UP * 0.8, c - nv * 0.24 + tv * 0.9 + Vector3.UP * 0.8, 0.06, 0.3, wood)
				for sg: float in [-0.75, 0.75]:
					_bx(m, c + tv * sg, c + tv * sg + Vector3.UP * 0.45, 0.5, 0.06, iron)
		else:
			while next_bollard < run:
				var q3 := a + t * (next_bollard - s0) - nn * 0.7
				next_bollard += 14.0
				if blocked.call(q3):
					continue
				var c3 := Vector3(q3.x, LAND_Y, q3.y)
				_bx(m, c3, c3 + Vector3.UP * 0.55, 0.36, 0.36, Color(0.12, 0.13, 0.14))
				_bx(m, c3 + Vector3.UP * 0.55, c3 + Vector3.UP * 0.65, 0.5, 0.5, Color(0.12, 0.13, 0.14))
				# A fender pile on the wall face below it.
				var f := q3 + nn * 0.95
				_bx(m, Vector3(f.x, SEA_Y - 1.0, f.y), Vector3(f.x, LAND_Y - 0.1, f.y), 0.45, 0.45, wood.darkened(0.25))
	_mesh(m, "Quayside", 0.0, 900.0)


## Life on Skyport's beaches (2026-11-18: they were empty sand blobs):
## umbrellas over towels and sun loungers in loose groups along the dry
## sand, lifeguard towers on stilts every ~160 m, windbreaks. One mesh.
func _build_beach_life() -> void:
	var o := outline()
	var n := o.size()
	var m := BuildingMesher.new()
	var cols := [Color(0.92, 0.25, 0.22), Color(0.98, 0.82, 0.25), Color(0.22, 0.52, 0.86), Color(0.2, 0.68, 0.55),
		Color(0.95, 0.55, 0.2), Color(0.85, 0.35, 0.6)]
	var white := Color(0.95, 0.95, 0.93)
	var run := 0.0
	var next_slot := 6.0
	var next_tower := 60.0
	for i in n:
		var i2 := (i + 1) % n
		var seg := o[i].distance_to(o[i2])
		var sd := _sandiness(o, i)
		var sd2 := _sandiness(o, i2)
		if sd < 0.85 or sd2 < 0.85:
			run += seg
			next_slot = run + 6.0
			continue
		var A := _row_as(o, i, sd)
		var B := _row_as(o, i2, sd2)
		if A.size() < 3 or B.size() < 3:
			run += seg
			continue
		var s0 := run
		run += seg
		while next_slot < run:
			var f := (next_slot - s0) / seg
			var h := hash(Vector2i(int(next_slot), 7)) % 1000 / 1000.0
			var h2 := hash(Vector2i(int(next_slot), 13)) % 1000 / 1000.0
			var want_tower := next_slot >= next_tower
			next_slot += 9.0 + h2 * 6.0
			# Across the dry sand: between the top row (1) and the swash (2).
			var t := 0.25 + 0.5 * h2 if not want_tower else 0.15
			var r1 := A[1].lerp(B[1], f)
			var r2 := A[2].lerp(B[2], f)
			var q := r1.lerp(r2, t)
			var wq := w(q)
			if over_bridge_shore(wq.x, wq.z) or under_bridge(wq.x, wq.z):
				continue
			var down := (r2 - r1)
			down.y = 0.0
			down = down.normalized()                         # towards the sea
			var side := Vector3(-down.z, 0.0, down.x)
			var col: Color = cols[int(h * 97.0) % cols.size()]
			if want_tower:
				next_tower = next_slot + 150.0
				_lifeguard(m, q, down, side)
				continue
			if h < 0.42:
				_umbrella(m, q, col, white)
				for k in 2:
					var tq := q + side * (-1.1 + 2.2 * k) + down * 0.6
					_bx(m, tq - down * 0.9 + Vector3.UP * 0.03, tq + down * 0.9 + Vector3.UP * 0.03, 0.85, 0.03,
						cols[(int(h * 97.0) + 1 + k * 2) % cols.size()])
			elif h < 0.66:
				_umbrella(m, q, col, white)
				for k in 2:
					var lq := q + side * (-0.9 + 1.8 * k) + down * 0.3
					_lounger(m, lq, down, side, white if k == 0 else Color(0.25, 0.45, 0.7))
			elif h < 0.78:
				# A striped windbreak and a towel in its lee.
				for k in 4:
					var wa := q + side * (-1.8 + k * 1.2)
					var wb := wa + side * 1.2
					_bx(m, wa + Vector3.UP * 0.55, wb + Vector3.UP * 0.55, 0.03, 1.1, col if k % 2 == 0 else white)
					_bx(m, wa + Vector3.DOWN * 0.2, wa + Vector3.UP * 1.15, 0.05, 0.05, Color(0.55, 0.42, 0.3))
				_bx(m, q + down * 0.4 - side * 0.9 + Vector3.UP * 0.03, q + down * 0.4 + side * 0.9 + Vector3.UP * 0.03, 0.85, 0.03,
					cols[(int(h * 97.0) + 3) % cols.size()])
	_mesh(m, "BeachLife", 0.0, 700.0)


func _umbrella(m: BuildingMesher, q: Vector3, col: Color, white: Color) -> void:
	_bx(m, q + Vector3.DOWN * 0.3, q + Vector3.UP * 2.3, 0.06, 0.06, white)
	# A shallow cone in three tiers, panels alternating with white.
	for tier in 3:
		var r := 1.35 - tier * 0.45
		var y0 := 2.08 + tier * 0.11
		var ring := PackedVector2Array()
		for a in 8:
			ring.append(Vector2(q.x, q.z) + Vector2.from_angle(TAU * (a + 0.5) / 8.0) * r)
		m.prism(ring, q.y + y0, q.y + y0 + 0.11, col if tier != 1 else col.lerp(white, 0.75))


func _lounger(m: BuildingMesher, q: Vector3, down: Vector3, side: Vector3, col: Color) -> void:
	var frame := Color(0.85, 0.85, 0.82)
	var foot := q + down * 0.8
	var hip := q - down * 0.2
	var head := q - down * 0.85 + Vector3.UP * 0.45
	_bx(m, foot + Vector3.UP * 0.32, hip + Vector3.UP * 0.32, 0.62, 0.07, col)
	_bx(m, hip + Vector3.UP * 0.32, head + Vector3.UP * 0.32, 0.62, 0.07, col)
	for p: Vector3 in [foot, hip - down * 0.1]:
		for sg: float in [-1.0, 1.0]:
			var l := p + side * sg * 0.27
			_bx(m, l, l + Vector3.UP * 0.3, 0.05, 0.05, frame)


## A lifeguard tower: a hut on four stilts with a ramp, red roof and flag.
func _lifeguard(m: BuildingMesher, q: Vector3, down: Vector3, side: Vector3) -> void:
	var white := Color(0.94, 0.94, 0.9)
	var red := Color(0.85, 0.18, 0.15)
	var deck := q.y + 2.2
	for a: float in [-1.0, 1.0]:
		for b: float in [-1.0, 1.0]:
			var l := q + down * a * 1.1 + side * b * 1.1
			_bx(m, Vector3(l.x, q.y - 0.5, l.z), Vector3(l.x, deck, l.z), 0.18, 0.18, white)
	var c := Vector3(q.x, deck, q.z)
	_bx(m, c - down * 1.5, c + down * 1.7, 3.0, 0.15, Color(0.55, 0.42, 0.3))
	_bx(m, c - down * 1.1 + Vector3.UP * 1.1, c + down * 0.9 + Vector3.UP * 1.1, 2.4, 2.0, white)
	_bx(m, c + down * 0.88 + Vector3.UP * 1.3, c + down * 0.93 + Vector3.UP * 1.3, 1.9, 0.8, Color(0.2, 0.28, 0.33))   # window
	_bx(m, c - down * 1.5 + Vector3.UP * 2.2, c + down * 1.4 + Vector3.UP * 2.2, 3.0, 0.25, red)
	# Ramp down the land side, a rail on the sea side, a flag.
	_bx(m, c - down * 1.5 + Vector3.UP * 0.05, q - down * 4.8 + Vector3.UP * 0.05, 1.0, 0.1, Color(0.55, 0.42, 0.3))
	_bx(m, c + down * 1.65 + Vector3.UP * 0.5 - side * 1.4, c + down * 1.65 + Vector3.UP * 0.5 + side * 1.4, 0.06, 0.06, white)
	var fp := c + side * 1.3 + down * 1.2
	_bx(m, fp, fp + Vector3.UP * 4.2, 0.06, 0.06, white)
	_bx(m, fp + Vector3.UP * 3.7 + down * 0.05, fp + Vector3.UP * 3.7 + side * 1.0, 0.03, 0.55, red)


## A capped box (short pieces show their ends).
static func _bx(m: BuildingMesher, a: Vector3, b: Vector3, wd: float, ht: float, col: Color) -> void:
	m.beam(a, b, wd, ht, col, BuildingMesher.KIND_TRIM, true)


## Street trees along Skyport Avenue and Tower Road, and clumps in the
## parks (the city's own tree mesh, one MultiMesh).
func _build_trees() -> void:
	var xfs: Array = []
	var e := Vector3(0.0, LAND_Y, PIVOT.y)   # (Skyport Avenue's line)
	var x := BRIDGE_ISLAND_X + 70.0
	while x < 2320.0:
		if absf(x - 1625.0) > 14.0 and absf(x - 1735.0) > 12.0 and absf(x - 1954.0) > 34.0 and absf(x - 2270.0) > 12.0 \
				and absf(x - 2014.0) > 8.0:
			for sg: float in [-1.0, 1.0]:
				xfs.append(Transform3D(Basis(Vector3.UP, x * 0.37), Vector3(x, LAND_Y, e.z + sg * 15.0)))
		x += 18.0
	var zz := -160.0
	while zz < -40.0:
		for xx: float in [1612.0, 1638.0, 1941.0, 1967.0]:
			if xx < 1900.0 or zz < -68.0:
				xfs.append(Transform3D(Basis(Vector3.UP, zz * 0.51), Vector3(xx, LAND_Y, zz)))
		zz += 20.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# Landscaped verges: a tree every ~22 m both sides of every public road,
	# just beyond its pavement, clear of junctions (25 m), of the other
	# carriageways, of buildings and of the rail corridor (filtered below).
	var nodes := {}
	for r in plan_data["roads"]:
		for re: Vector3 in [(r[1] as PackedVector3Array)[0], (r[1] as PackedVector3Array)[-1]]:
			nodes[Vector2i(roundi(re.x), roundi(re.z))] = Vector2(re.x, re.z)
	for r in plan_data["roads"]:
		if String(r[0]) in ["Airside Service Road", "Terminal Forecourt", "Parking Access", "Terminal Circus"]:
			continue
		var pts: PackedVector3Array = r[1]
		var off := float(r[2]) * 0.5 + 5.0 + 2.5
		var tot := _length(pts)
		var sd := 11.0
		while sd < tot - 6.0:
			var pa := _point_at(pts, sd)
			var pb := _point_at(pts, minf(sd + 1.0, tot))
			var dv := pb - pa
			dv.y = 0.0
			var nv := Vector3(-dv.z, 0.0, dv.x).normalized()
			for sg: float in [-1.0, 1.0]:
				var q := pa + nv * off * sg
				var near := false
				for k in nodes:
					if (nodes[k] as Vector2).distance_to(Vector2(q.x, q.z)) < 25.0:
						near = true
						break
				if near:
					continue
				var inb := false
				for bd: Dictionary in plan_data["buildings"]:
					var t0: Array = bd["tiers"][0]
					if Rect2(t0[0], t0[1], float(t0[2]) - float(t0[0]), float(t0[3]) - float(t0[1])).grow(3.0).has_point(Vector2(q.x, q.z)):
						inb = true
						break
				if not inb:
					xfs.append(Transform3D(Basis(Vector3.UP, sd * 0.37).scaled(Vector3.ONE * (0.85 + 0.3 * fposmod(sd * 0.137, 1.0))), q))
			sd += 22.0
	# Terminal Circus: three ornamental trees in the middle of its island.
	var circ: Array = plan_data.get("circus", [])
	if not circ.is_empty():
		for o: Vector2 in [Vector2(0.0, 0.0), Vector2(4.5, 3.0), Vector2(-4.0, -3.5)]:
			var cq: Vector2 = (circ[0] as Vector2) + o
			xfs.append(Transform3D(Basis(Vector3.UP, o.x).scaled(Vector3.ONE * 1.15), Vector3(cq.x, LAND_Y, cq.y)))
	var gore: PackedVector2Array = plan_data.get("gore", PackedVector2Array())
	var gb := Rect2(gore[0], Vector2.ZERO) if not gore.is_empty() else Rect2()
	for v in gore:
		gb = gb.expand(v)
	for k in 140:
		var p := Vector3(rng.randf_range(gb.position.x, gb.end.x), LAND_Y, rng.randf_range(gb.position.y, gb.end.y))
		if gore.is_empty() or not Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), gore):
			p = Vector3.INF
		if rng.randf() < 0.5:
			p = Vector3(rng.randf_range(1410, 1610), LAND_Y, rng.randf_range(15, 155))
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), p))
	# Copses on the knolls (their crowns and flanks, not the bare summits).
	for kn: Array in knolls():
		var c: Vector2 = kn[0]
		for k in int(float(kn[1]) * float(kn[2]) / 180.0):
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf_range(0.08, 0.8))
			xfs.append(Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * rng.randf_range(0.85, 1.3)),
				Vector3(c.x + cos(a) * float(kn[1]) * r, LAND_Y, c.y + sin(a) * float(kn[2]) * r)))
	# Landscape copses and lone trees over the open landside lawns (from the
	# air the island was a golf course of bare grass between the blocks);
	# none airside (local z > 175: the taxiways, stands and the runway).
	var o := outline()
	var lb := Rect2(o[0], Vector2.ZERO)
	for v in o:
		lb = lb.expand(v)
	var crng := RandomNumberGenerator.new()
	crng.seed = 9187
	var extra: Array = []
	# An even jittered grid over the landside (random centres left whole
	# lawns bare): a copse, a lone tree or open grass in every 34 m cell.
	var gx := lb.position.x
	while gx < lb.end.x:
		var gz := lb.position.y
		while gz < minf(lb.end.y, 175.0):
			var c := Vector2(gx + crng.randf_range(4.0, 30.0), gz + crng.randf_range(4.0, 30.0))
			var roll := crng.randf()
			if roll < 0.55:
				var n := crng.randi_range(3, 9)
				var rad := crng.randf_range(6.0, 15.0)
				for j in n:
					var a := crng.randf() * TAU
					var r := sqrt(crng.randf()) * rad
					extra.append(Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * crng.randf_range(0.8, 1.35)),
						Vector3(c.x + cos(a) * r, LAND_Y, c.y + sin(a) * r)))
			elif roll < 0.88:
				extra.append(Transform3D(Basis(Vector3.UP, crng.randf() * TAU).scaled(Vector3.ONE * crng.randf_range(0.9, 1.4)),
					Vector3(c.x, LAND_Y, c.y)))
			gz += 34.0
		gx += 34.0
	for xf: Transform3D in extra:
		var q := Vector2(xf.origin.x, xf.origin.z)
		if q.y > 175.0 or road_clearance(plan_data, q) < 7.0:
			continue
		var inb := false
		for bd: Dictionary in plan_data["buildings"]:
			for t0: Array in bd["tiers"]:
				if Rect2(t0[0], t0[1], float(t0[2]) - float(t0[0]), float(t0[3]) - float(t0[1])).grow(6.0).has_point(q):
					inb = true
					break
			if inb:
				break
		for sk in plan_data.get("sites", {}):
			var site: Dictionary = plan_data["sites"][sk]
			if site.has("lot") and (site["lot"] as Rect2).grow(5.0).has_point(q):
				inb = true
			var dr: Vector3 = site["door"]
			if Vector2(dr.x, dr.z).distance_to(q) < 22.0:
				inb = true
		if not inb:
			xfs.append(xf)
	# On land only (12 m+ from the shore), standing on the ground (knolls).
	var kept: Array = []
	for xf: Transform3D in xfs:
		if not xf.origin.is_finite():
			continue
		var q := Vector2(xf.origin.x, xf.origin.z)
		if not Geometry2D.is_point_in_polygon(q, o) or _shore_dist(q) < 12.0:
			continue
		# (Off every carriageway and out of the rail corridor's piers.)
		if road_clearance(plan_data, q) < 4.4 or rail_clearance(plan_data, q) < 7.0:
			continue
		var paved := false
		for ar in plan_data["areas"]:
			if int(ar[0]) != 1 and Geometry2D.is_point_in_polygon(q, ar[1]):
				paved = true   # (aprons, car parks, forecourts)
				break
		if paved:
			continue
		xf.origin.y = LAND_Y + knoll_h(q.x, q.y)
		kept.append(xf)
	# The terminal car park's planters (on paving: added after the filter).
	for tq: Vector2 in SkyportAirport.park_trees():
		kept.append(Transform3D(Basis(Vector3.UP, tq.x * 0.31).scaled(Vector3.ONE * 0.95), Vector3(tq.x, LAND_Y, tq.y)))
	# Keep the planted rhythm across the island with room for mature crowns.
	var plots := {}
	var batches := {}
	for xf: Transform3D in kept:
		var p := xf.origin
		if hash(Vector3i(roundi(p.x * 4.0), roundi(p.z * 4.0), 43)) % 3 != 0:
			continue
		var plot := Vector2i(floori(p.x / 10.0), floori(p.z / 10.0))
		if plots.has(plot):
			continue
		plots[plot] = true
		var species := TreeKit.pick(p, absf(p.z - e.z) > 20.0)
		var sector := Vector2i(floori(p.x / 120.0), floori(p.z / 120.0))
		if not batches.has(sector):
			batches[sector] = {}
		if not batches[sector].has(species):
			batches[sector][species] = []
		batches[sector][species].append(Transform3D(TreeKit.shape(p, xf.basis.get_scale().y), p))
	for sector in batches:
		for species in batches[sector]:
			TreeKit.instance_batch(_target, species, batches[sector][species], 620.0)


## Container stacks and quay cranes in the logistics district.
func _build_industry() -> void:
	var m := BuildingMesher.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	var cols := [Color(0.7, 0.2, 0.15), Color(0.15, 0.35, 0.6), Color(0.85, 0.55, 0.1), Color(0.2, 0.5, 0.3),
		Color(0.55, 0.55, 0.57), Color(0.5, 0.15, 0.4)]
	var z := -290.0
	while z < -205.0:
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
			for lz: float in [-318.0, -298.0]:
				m.beam(Vector3(cx + lx, LAND_Y, lz), Vector3(cx + lx, LAND_Y + 42.0, lz), 1.4, 1.4, yel)
				_box_beam(body, Vector3(cx + lx, LAND_Y, lz), Vector3(cx + lx, LAND_Y + 42.0, lz), 1.4, 1.4)
		m.beam(Vector3(cx - 9.0, LAND_Y + 42.0, -308.0), Vector3(cx + 9.0, LAND_Y + 42.0, -308.0), 2.0, 2.0, yel)
		m.beam(Vector3(cx, LAND_Y + 44.0, -260.0), Vector3(cx, LAND_Y + 44.0, -390.0), 2.2, 3.0, yel)
		_box_beam(body, Vector3(cx, LAND_Y + 44.0, -260.0), Vector3(cx, LAND_Y + 44.0, -390.0), 2.2, 3.0)
		m.solid(cx - 3.0, -350.0, cx + 3.0, -344.0, LAND_Y + 38.0, LAND_Y + 42.5, Color(0.3, 0.3, 0.32))
	_mesh(m, "Industry", 0.0, 2200.0)


## Lanes for RoadNet (GPS): for every road a lane each way 3.4 m either side
## of its centreline, sampled every `step` m; at each junction every lane
## arriving can carry on into every lane leaving (not straight back), and a
## dead end turns round. Lanes leaving / reaching the bridge's city end are
## flagged for stitching into the city's lanes.
## Returns [{pts, speed, next: [local lane ids], city_start, city_end}].
static func lanes(layout: CityLayout, step: float) -> Array:
	var P := plan(layout)
	var out: Array = []
	var ends := {}   # Vector2i(node) -> {"in": [lane], "out": [lane]}
	var key := func(v: Vector3) -> Vector2i: return Vector2i(roundi(v.x), roundi(v.z))
	# World space: the island's roads through w(), the bridges as planned.
	var all: Array = []
	var city_pts: Array = []
	for r in P["roads"]:
		all.append([r[0], wpts(r[1])])
	for B: Dictionary in P["bridges"]:
		all.append([B["name"], B["pts"]])
		city_pts.append(B["s0"])
	var at_city := func(v: Vector3) -> bool:
		for c: Vector3 in city_pts:
			if v.distance_to(c) < 2.0:
				return true
		return false
	for r in all:
		var pts: PackedVector3Array = r[1]
		var speed := 22.0 if String(r[0]).ends_with("Bridge") or r[0] in ["Skyport Avenue", "Harbour Approach", "Westbank Approach"] else 13.0
		# (Terminal Circus: one way round – traffic keeps right, so the ring
		# runs anticlockwise from above: against its points' direction.)
		var dirs_l: Array = [-1] if r[0] == "Terminal Circus" else [1, -1]
		var n_before := out.size()
		for dir in dirs_l:
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
			if at_city.call(src[0]):
				out[id]["city_start"] = true
			if at_city.call(src[src.size() - 1]):
				out[id]["city_end"] = true
		if out.size() - n_before == 2:
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
