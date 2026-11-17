class_name AirportRail
extends RefCounted
## The Airport Line (2026-11-17): a double-track elevated railway joining
## both cities through Skyport Island, run by the city's own Trains (a
## RailNetwork line, end to end and back on each track):
##
##   Westbank Airport  – over the water, west of the Westbank Bridge –
##   Airport Central   – beside the terminal (entrance hall, covered walk to
##                       the departures kerb, taxi rank, the car parks) –
##   Skyport Commercial – on the town's waterfront, a path to Harbour Row –
##   Harbour Quay      – over the water off the Commercial Island's south
##                       shore, east of the Harbour Bridge.
##
## Planned with the island's roads (SkyportIsland.plan): its corridor runs
## beside Hangar Lane, along x 2014 across the avenue and Industrial Way, and
## down the east shore; buildings and trees keep clear of it, piers stay out
## of every carriageway (the deck spans junctions), 16 m over the roads –
## grade-separated everywhere, no level crossings – and it never meets the
## runway, a taxiway or either road bridge. Straights joined by true arcs,
## so each station sits on straight track.

const DECK_LAND := 16.0          # deck above Skyport's ground
const DECK_WATER := 22.0         # deck above the sea (boats pass under)
const DECK_HALF := RailNetwork.PAIR + RailNetwork.HALF   # 6.4 m: both tracks
const R_ISLAND := 60.0
const R_WATER := 150.0
const PIER_EVERY := 30.0
## World ends over the water off each city, island control points (local).
const WEST_END := Vector2(-650.0, 548.0)
const EAST_END := Vector2(560.0, 650.0)
const ISLAND := [Vector2(1414.0, 103.5), Vector2(2014.0, 103.5), Vector2(2014.0, -360.0), Vector2(1400.0, -360.0)]
## Stations: [name, centre (world for the ends, local on the island), local?]
const STATIONS := [["Westbank Airport", Vector2(-614.0, 592.0), false], ["Airport Central", Vector2(1905.0, 103.5), true],
	["Skyport Commercial", Vector2(1630.0, -360.0), true], ["Harbour Quay", Vector2(524.0, 672.0), false]]


## The line's plan, into P (SkyportIsland.plan): P["rail"] = [line] (world,
## a RailNetwork line dict), P["rail_local"] = [centreline, local 2-D],
## P["rail_stations"] = [{name, s, c, dir, island}].
static func plan(P: Dictionary, layout: CityLayout) -> void:
	var ctrl: Array = [WEST_END]
	for q: Vector2 in ISLAND:
		ctrl.append(SkyportIsland.w2(q))
	ctrl.append(EAST_END)
	var radii: Array = [0.0, R_WATER, R_ISLAND, R_ISLAND, R_WATER, 0.0]
	var flat := _filleted(ctrl, radii)
	flat = RailNetwork._resample_open(flat, RailNetwork.STEP)
	var n := flat.size()
	var target := PackedFloat32Array()
	target.resize(n)
	for i in n:
		var q := flat[i]
		target[i] = (SkyportIsland.LAND_Y + DECK_LAND) if SkyportIsland.contains(q.x, q.y) else DECK_WATER
	# Ease between the island's deck and the water's: ~1.5 % grades.
	var ys := target
	for pass_i in 4:
		ys = _ease_open(ys, 50)
	var pts := PackedVector3Array()
	for i in n:
		pts.append(Vector3(flat[i].x, ys[i] + RailNetwork.RAIL_H, flat[i].y))
	var stations: Array = []
	var st_info: Array = []
	for sd: Array in STATIONS:
		var c: Vector2 = SkyportIsland.w2(sd[1]) if sd[2] else sd[1]
		var best := 0
		for i in n:
			if flat[i].distance_squared_to(c) < flat[best].distance_squared_to(c):
				best = i
		var s := best * RailNetwork.STEP
		# (Never past the ends: a terminus platform's far end is the buffer.)
		s = clampf(s, RailNetwork.STATION_LEN * 0.5 + 4.0, (n - 1) * RailNetwork.STEP - RailNetwork.STATION_LEN * 0.5 - 4.0)
		stations.append(s)
		var a := RailNetwork._at(pts, s - 20.0, false)
		var b := RailNetwork._at(pts, s + 20.0, false)
		var d := b - a
		d.y = 0.0
		st_info.append({"name": sd[0], "s": s, "c": RailNetwork._at(pts, s, false), "dir": d.normalized(), "island": sd[2]})
	var line := {"name": "airport", "pts": pts, "loop": false, "oneway": false, "trains": 2,
		"tracks": [RailNetwork.PAIR, -RailNetwork.PAIR], "stations": stations, "cars": 4}
	var loc := PackedVector2Array()
	for q in flat:
		loc.append(SkyportIsland.l2(q))
	P["rail"] = [line]
	P["rail_local"] = [loc]
	P["rail_stations"] = st_info


## Polyline through ctrl with each interior corner rounded to a circular arc
## of its radius (radii[i] for ctrl[i]).
static func _filleted(ctrl: Array, radii: Array) -> PackedVector2Array:
	var out := PackedVector2Array([ctrl[0]])
	for i in range(1, ctrl.size() - 1):
		var p: Vector2 = ctrl[i]
		var d0: Vector2 = (p - (ctrl[i - 1] as Vector2)).normalized()
		var d1: Vector2 = ((ctrl[i + 1] as Vector2) - p).normalized()
		var th := acos(clampf(d0.dot(d1), -1.0, 1.0))
		var R: float = radii[i]
		if th < 0.01 or R <= 0.0:
			out.append(p)
			continue
		var t := R * tan(th * 0.5)
		var a := p - d0 * t
		var turn := signf(d0.cross(d1))           # +1 one way, -1 the other
		var nrm := Vector2(-d0.y, d0.x) * turn
		var c := a + nrm * R
		var a0 := (a - c).angle()
		var steps := maxi(4, int(R * th / 3.0))
		for k in steps + 1:
			out.append(c + Vector2.from_angle(a0 + turn * th * k / steps) * R)
	out.append(ctrl[ctrl.size() - 1])
	return out


static func _ease_open(y: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var n := y.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := 0.0
		var c := 0
		for k in range(maxi(0, i - r), mini(n, i + r + 1)):
			s += y[k]
			c += 1
		out[i] = s / c
	# (The ends keep their own level: a terminus isn't pulled down.)
	return out


# ------------------------------------------------------------------- build
const CONCRETE := RailNetwork.CONCRETE
const CONCRETE_DK := RailNetwork.CONCRETE_DK
const STEEL := RailNetwork.RAIL_STEEL
const CANOPY := Color(0.86, 0.87, 0.88)
const PLATFORM := RailNetwork.PLATFORM
const LINE_BLUE := Color(0.1, 0.36, 0.62)


## The viaduct, stations and their access as meshes (one per ~300 m, so it
## culls) plus collision (decks, parapets, platforms, piers, stairs).
static func build(target: Node3D, body: StaticBody3D, isl: SkyportIsland, layout: CityLayout) -> void:
	var P: Dictionary = isl.plan_data
	if not P.has("rail"):
		return
	var line: Dictionary = P["rail"][0]
	var pts: PackedVector3Array = line["pts"]
	var n := pts.size()
	var m := BuildingMesher.new()
	var run := 0.0
	var chunk := 0
	var i := 0
	var next_pier := 12.0
	while i < n - 1:
		var j := mini(i + 10, n - 1)
		while j > i + 1 and RailNetwork._chord_dev(pts, i, j) > 0.12:
			j -= 1
		var a := pts[i]
		var b := pts[j]
		var d := b - a
		var side := Vector3(-d.z, 0.0, d.x).normalized()
		var ext := d.normalized() * 0.3
		var da := a - Vector3.UP * RailNetwork.RAIL_H
		var db := b - Vector3.UP * RailNetwork.RAIL_H
		# Deck slab and its box girder; parapets with a blue line stripe.
		m.beam(da - ext + Vector3.DOWN * 0.7, db + ext + Vector3.DOWN * 0.7, DECK_HALF * 2.0, 1.4, CONCRETE)
		m.beam(da - ext + Vector3.DOWN * 1.9, db + ext + Vector3.DOWN * 1.9, 6.0, 1.0, CONCRETE_DK)
		SkyportIsland._box_beam(body, da - ext + Vector3.DOWN * 0.7, db + ext + Vector3.DOWN * 0.7, DECK_HALF * 2.0, 1.4)
		for sg: float in [-1.0, 1.0]:
			var o := side * sg * (DECK_HALF - 0.2)
			m.beam(da - ext + o + Vector3.UP * 0.5, db + ext + o + Vector3.UP * 0.5, 0.4, 1.0, CONCRETE)
			m.beam(da - ext + o + side * sg * 0.21 + Vector3.UP * 0.6, db + ext + o + side * sg * 0.21 + Vector3.UP * 0.6, 0.02, 0.3, LINE_BLUE)
			SkyportIsland._box_beam(body, da - ext + o + Vector3.UP * 0.5, db + ext + o + Vector3.UP * 0.5, 0.4, 1.0)
			# Both tracks: ballast bed and two rails each.
			var tc := side * sg * RailNetwork.PAIR
			m.beam(a + tc + Vector3.DOWN * (RailNetwork.RAIL_H - 0.04) - ext, b + tc + Vector3.DOWN * (RailNetwork.RAIL_H - 0.04) + ext,
				2.6, 0.12, Color(0.36, 0.33, 0.3))
			for rs: float in [-0.72, 0.72]:
				var ro := tc + side * rs + Vector3.DOWN * 0.08
				m.beam(a + ro - ext, b + ro + ext, 0.1, 0.16, STEEL)
		# Piers every 30 m (none in a carriageway: the deck spans it).
		var s0 := i * RailNetwork.STEP
		var s1 := j * RailNetwork.STEP
		while next_pier < s1:
			if next_pier >= s0:
				_pier(m, body, pts, next_pier, P, layout)
			next_pier += PIER_EVERY
		run += d.length()
		if run > 300.0:
			isl._mesh_into(m, "AirportRail_%d" % chunk, target, 0.0, 3800.0)
			m = BuildingMesher.new()
			chunk += 1
			run = 0.0
		i = j
	# Buffer stops at both ends.
	for e in [0, n - 1]:
		var p := pts[e]
		var dd := (pts[mini(e + 1, n - 1)] - pts[maxi(e - 1, 0)]).normalized() * (-1.0 if e == 0 else 1.0)
		var sd := Vector3(-dd.z, 0.0, dd.x)
		for sg: float in [-1.0, 1.0]:
			var q := p + sd * sg * RailNetwork.PAIR - dd * 1.0
			m.beam(q - sd * 1.2, q + sd * 1.2, 0.8, 1.2, Color(0.75, 0.12, 0.1))
	for st: Dictionary in P["rail_stations"]:
		_station(m, body, line, st, layout, P)
	isl._mesh_into(m, "AirportRail_%d" % chunk, target, 0.0, 3800.0)


static func _pier(m: BuildingMesher, body: StaticBody3D, pts: PackedVector3Array, s: float, P: Dictionary,
		layout: CityLayout) -> void:
	var p := RailNetwork._at(pts, s, false)
	var q2 := Vector2(p.x, p.z)
	var on_island := SkyportIsland.contains(q2.x, q2.y)
	var gy := -8.0
	if on_island:
		var ql := SkyportIsland.l2(q2)
		if SkyportIsland.road_clearance(P, ql) < 1.5:
			return   # (a carriageway under the deck: spanned)
		gy = SkyportIsland.LAND_Y - 0.3
	elif not layout.is_water(Vector3(q2.x, 0.0, q2.y)):
		var g := layout.ground_y(q2.x, q2.y)
		gy = (g if not is_nan(g) else 0.0) - 0.3
	var dir := RailNetwork._at(pts, s + 2.0, false) - RailNetwork._at(pts, s - 2.0, false)
	dir.y = 0.0
	dir = dir.normalized()
	var ps := Vector3(-dir.z, 0.0, dir.x)
	var top := p.y - RailNetwork.RAIL_H - 2.4
	# One column on the centreline, a hammerhead under both tracks.
	m.beam(Vector3(p.x, gy, p.z), Vector3(p.x, top, p.z), 2.0, 2.0, CONCRETE_DK)
	m.beam(Vector3(p.x, top + 0.5, p.z) - ps * 5.4, Vector3(p.x, top + 0.5, p.z) + ps * 5.4, 1.8, 1.2, CONCRETE)
	SkyportIsland._box_beam(body, Vector3(p.x, gy, p.z), Vector3(p.x, top, p.z), 2.0, 2.0)
	if not on_island and gy < -1.0:
		# A cutwater footing at the waterline.
		m.beam(Vector3(p.x, -3.0, p.z) - dir * 2.0, Vector3(p.x, -3.0, p.z) + dir * 2.0, 3.4, 3.2, CONCRETE_DK)


## A station: side platforms outside both tracks under a long canopy, name
## boards, a stair-and-lift tower down to the ground, and the access the
## stop serves (see the class notes).
static func _station(m: BuildingMesher, body: StaticBody3D, line: Dictionary, st: Dictionary, layout: CityLayout,
		P: Dictionary) -> void:
	var pts: PackedVector3Array = line["pts"]
	var s0: float = st["s"]
	var L := RailNetwork.STATION_LEN
	var a := RailNetwork._at(pts, s0 - L * 0.5, false)
	var b := RailNetwork._at(pts, s0 + L * 0.5, false)
	var d: Vector3 = st["dir"]
	var side := Vector3(-d.z, 0.0, d.x)
	var c: Vector3 = st["c"]
	var off_pl := RailNetwork.PAIR + RailNetwork.PLATFORM_GAP + 1.75
	for sg: float in [-1.0, 1.0]:
		var o := side * sg * off_pl
		var pa := a + o
		var pb := b + o
		m.beam(pa + Vector3.DOWN * 0.1, pb + Vector3.DOWN * 0.1, 3.5, 2.2, PLATFORM)
		SkyportIsland._box_beam(body, pa + Vector3.DOWN * 0.1, pb + Vector3.DOWN * 0.1, 3.5, 2.2)
		m.beam(pa - side * sg * 1.72 + Vector3.UP * 0.96, pb - side * sg * 1.72 + Vector3.UP * 0.96, 0.06, 0.04,
			Color(0.95, 0.8, 0.15))
		var t := 4.0
		while t < L - 2.0:
			var q := pa.lerp(pb, t / L) + side * sg * 1.3
			m.beam(q + Vector3.UP * 1.0, q + Vector3.UP * 5.0, 0.3, 0.3, Color(0.3, 0.32, 0.34))
			t += 10.0
		m.beam(pa + side * sg * 1.6 + Vector3.UP * 1.6, pb + side * sg * 1.6 + Vector3.UP * 1.6, 0.12, 1.4,
			Color(0.32, 0.42, 0.48))   # glazed screen
		SkyportIsland._box_beam(body, pa + side * sg * 1.6 + Vector3.UP * 1.6, pb + side * sg * 1.6 + Vector3.UP * 1.6, 0.12, 1.4)
		var mid := (pa + pb) * 0.5 + side * sg * 1.45 + Vector3.UP * 3.4
		m.beam(mid - d * 3.0, mid + d * 3.0, 0.1, 0.8, LINE_BLUE)       # name board
	# One canopy over both platforms and the tracks (a shallow vault: three
	# planes), with a blue fascia.
	var ra := a + Vector3.UP * 5.2
	var rb := b + Vector3.UP * 5.2
	m.beam(ra, rb, 9.0, 0.2, CANOPY)
	for sg: float in [-1.0, 1.0]:
		m.beam(ra + side * sg * 7.6 + Vector3.DOWN * 0.45, rb + side * sg * 7.6 + Vector3.DOWN * 0.45, 6.4, 0.18, CANOPY)
		m.beam(ra + side * sg * 10.8 + Vector3.DOWN * 0.9, rb + side * sg * 10.8 + Vector3.DOWN * 0.9, 0.2, 0.7, LINE_BLUE)
	# Ground access: a stair-and-lift tower beside the platforms, at the end
	# that faces the people it serves.
	var name: String = st["name"]
	var tower := Vector3.ZERO
	var gy := 0.0
	match name:
		"Westbank Airport":
			tower = _toward_land(layout.mainland if layout.mainland else layout, a, b, side, off_pl)
		"Harbour Quay":
			tower = _toward_land(layout, a, b, side, off_pl)
		_:
			tower = c + side * (off_pl + 5.5) * (1.0 if name == "Airport Central" else -1.0)
	if tower != Vector3.ZERO:
		var tq := Vector2(tower.x, tower.z)
		if SkyportIsland.contains(tq.x, tq.y):
			gy = SkyportIsland.LAND_Y
		else:
			var lay := layout.mainland if (name == "Westbank Airport" and layout.mainland) else layout
			var g := lay.ground_y(tq.x, tq.y)
			gy = g if not is_nan(g) else 0.0
		m.beam(Vector3(tower.x, gy, tower.z), Vector3(tower.x, c.y + 5.6, tower.z), 6.0, 6.0, Color(0.36, 0.4, 0.44))
		m.beam(Vector3(tower.x, c.y + 5.6, tower.z), Vector3(tower.x, c.y + 6.0, tower.z), 6.8, 6.8, LINE_BLUE)
		SkyportIsland._box_beam(body, Vector3(tower.x, gy, tower.z), Vector3(tower.x, c.y + 5.6, tower.z), 6.0, 6.0)
		# A bridge from the tower to the nearer platform.
		var near_pl := c + (tower - c).project(side).normalized() * off_pl
		near_pl.y = c.y
		m.beam(Vector3(tower.x, c.y - 0.1, tower.z), near_pl + Vector3.DOWN * 0.1, 3.0, 0.4, PLATFORM)
		SkyportIsland._box_beam(body, Vector3(tower.x, c.y - 0.1, tower.z), near_pl + Vector3.DOWN * 0.1, 3.0, 0.4)
		# The line's roundel on the tower (a blue disc and white bar).
		var face := (tower - c).normalized()
		face.y = 0.0
		var rp := Vector3(tower.x, c.y + 2.5, tower.z) + face * 3.05
		m.prism(SkyportAirport._ring(Vector2(rp.x, rp.z), 1.2, 12), rp.y - 1.2, rp.y + 1.2, LINE_BLUE)
	if name == "Airport Central":
		_airport_central(m, body, st, tower, P)
	elif name == "Skyport Commercial":
		# The path from the tower through the waterfront to Harbour Row.
		var t0 := SkyportIsland.l(tower)
		var path := [Vector2(t0.x, t0.z), Vector2(t0.x, -262.0)]
		var pa3 := SkyportIsland.w(Vector3(path[0].x, SkyportIsland.LAND_Y + 0.02, path[0].y))
		var pb3 := SkyportIsland.w(Vector3(path[1].x, SkyportIsland.LAND_Y + 0.02, path[1].y))
		m.beam(pa3, pb3, 4.0, 0.06, Color(0.66, 0.64, 0.6))


## Where a terminus's tower stands: off the platform end nearer the land.
static func _toward_land(lay: CityLayout, a: Vector3, b: Vector3, side: Vector3, off_pl: float) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for e: Vector3 in [a, b]:
		for sg: float in [-1.0, 1.0]:
			var q := e + side * sg * (off_pl + 5.5)
			var land_d := _land_dist(lay, Vector2(q.x, q.z))
			if land_d < best_d:
				best_d = land_d
				best = q
	return best


static func _land_dist(lay: CityLayout, q: Vector2) -> float:
	var best := INF
	for r in range(0, 120, 4):
		for k in 16:
			var v := q + Vector2.from_angle(TAU * k / 16.0) * float(r)
			if not lay.is_water(Vector3(v.x, 0.0, v.y)):
				return float(r)
	return best


## Airport Central's ground level: an entrance hall between the viaduct and
## Hangar Lane, a covered walk along Departures to the terminal's north
## door, and the taxi rank on the forecourt kerb (painted bays, cabs).
static func _airport_central(m: BuildingMesher, body: StaticBody3D, st: Dictionary, tower: Vector3, P: Dictionary) -> void:
	var Y := SkyportIsland.LAND_Y
	var W := func(x: float, z: float, yy: float) -> Vector3: return SkyportIsland.w(Vector3(x, yy, z))
	# Entrance hall (local 1880..1940 x 60..92): glass box, a white roof.
	var hall := Rect2(1880.0, 60.0, 60.0, 32.0)
	var c := hall.get_center()
	var a: Vector3 = W.call(hall.position.x, c.y, Y + 3.5)
	var b: Vector3 = W.call(hall.end.x, c.y, Y + 3.5)
	m.beam(a, b, hall.size.y, 7.0, Color(0.42, 0.55, 0.62))
	m.beam(a + Vector3.UP * 3.7, b + Vector3.UP * 3.7, hall.size.y + 2.0, 0.5, CANOPY)
	SkyportIsland._box_beam(body, a, b, hall.size.y, 7.0)
	# Covered walk: hall → across Hangar Lane (the junction's zebra) → down
	# the Departures pavement to the terminal's north front.
	var walk := [Vector2(1940.0, 92.0), Vector2(1943.5, 104.0), Vector2(1943.5, 166.0)]
	for k in walk.size() - 1:
		var p0: Vector2 = walk[k]
		var p1: Vector2 = walk[k + 1]
		if k == 1:
			p0 = Vector2(1943.5, 120.0)   # (open over the crossing)
		var w0: Vector3 = W.call(p0.x, p0.y, Y + 4.0)
		var w1: Vector3 = W.call(p1.x, p1.y, Y + 4.0)
		m.beam(w0, w1, 3.6, 0.25, CANOPY)
		var t := 0.0
		var Lw := p0.distance_to(p1)
		while t <= Lw:
			var q := p0.lerp(p1, t / maxf(Lw, 0.01))
			var col: Vector3 = W.call(q.x, q.y, Y)
			m.beam(col, col + Vector3.UP * 3.9, 0.22, 0.22, Color(0.3, 0.32, 0.34))
			t += 8.0
	# Taxi rank: yellow bays along the forecourt's terminal-side kerb, cabs.
	for k in 6:
		var x := 1968.0 + k * 6.5
		var p0: Vector3 = W.call(x, 158.5, Y + 0.035)
		var p1: Vector3 = W.call(x + 5.6, 158.5, Y + 0.035)
		m.beam(p0, p1, 2.4, 0.015, Color(0.92, 0.72, 0.12))
		if k < 4:
			var cc: Vector3 = W.call(x + 2.8, 158.5, Y + 0.45)
			var ca: Vector3 = cc + SkyportIsland.wd(Vector3(-2.2, 0.0, 0.0))
			var cb: Vector3 = cc + SkyportIsland.wd(Vector3(2.2, 0.0, 0.0))
			m.beam(ca, cb, 1.8, 0.85, Color(0.95, 0.76, 0.1))
			m.beam(ca.lerp(cb, 0.25) + Vector3.UP * 0.7, ca.lerp(cb, 0.72) + Vector3.UP * 0.7, 1.6, 0.55, Color(0.12, 0.13, 0.15))
	var sign_at: Vector3 = W.call(1960.0, 98.0, Y)
	m.beam(sign_at, sign_at + Vector3.UP * 4.5, 0.3, 0.3, Color(0.3, 0.32, 0.34))
	m.beam(sign_at + Vector3.UP * 4.5 + SkyportIsland.wd(Vector3(0, 0, -1.2)), sign_at + Vector3.UP * 4.5 + SkyportIsland.wd(Vector3(0, 0, 1.2)),
		0.2, 1.1, LINE_BLUE)
