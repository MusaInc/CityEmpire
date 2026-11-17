extends RefCounted
## Skyport Island's planned transport network (SkyportIsland.plan, 2026-11-17):
## the roads as one connected hierarchy on land, clear of buildings and of
## each other, every place reachable by road from both bridges, and the
## Airport Line a continuous double-track railway between all three islands,
## clear of buildings, runway and taxiways, with its stations on straight
## track and the trains registered on it.

static var _layout: CityLayout
static var _P: Dictionary


func _plan() -> Dictionary:
	if _P.is_empty():
		SkyportIsland.enabled = true
		_layout = CityLayout.new().generate()
		_P = SkyportIsland.plan(_layout)
	return _P


static func _segs(r: Array) -> Array:
	var out: Array = []
	var pts: PackedVector3Array = r[1]
	for i in pts.size() - 1:
		out.append([Vector2(pts[i].x, pts[i].z), Vector2(pts[i + 1].x, pts[i + 1].z)])
	return out


static func _key(v: Vector3) -> Vector2i:
	return Vector2i(roundi(v.x), roundi(v.z))


func test_roads_are_on_land_and_off_buildings(t) -> void:
	var P := _plan()
	var o := SkyportIsland.outline()
	var off_land: Array = []
	var through: Array = []
	for r: Array in P["roads"]:
		var hw := float(r[2]) * 0.5
		for sg: Array in _segs(r):
			var a: Vector2 = sg[0]
			var b: Vector2 = sg[1]
			var L := a.distance_to(b)
			var k := 0.0
			while k <= L:
				var q := a.lerp(b, k / maxf(L, 0.01))
				if not Geometry2D.is_point_in_polygon(q, o):
					off_land.append("%s at %s" % [r[0], q.round()])
				for bd: Dictionary in P["buildings"]:
					if bd.get("mesh", true) == false and bd.get("kind", "") == "invisible":
						continue
					var t0: Array = bd["tiers"][0]
					var rect := Rect2(t0[0], t0[1], float(t0[2]) - float(t0[0]), float(t0[3]) - float(t0[1])).grow(hw - 0.5)
					if rect.has_point(q):
						through.append("%s at %s" % [r[0], q.round()])
						break
				k += 4.0
	t.check(off_land.is_empty(), "every road on the island (%s)" % [off_land.slice(0, 4)])
	t.check(through.is_empty(), "no road through a building (%s)" % [through.slice(0, 4)])


func test_carriageways_meet_only_at_junctions(t) -> void:
	# Two roads' surfaces may only touch where they share an end (a
	# junction); anywhere else they overlap = a road drawn over a road.
	var P := _plan()
	var roads: Array = P["roads"]
	var bad: Array = []
	for i in roads.size():
		for j in range(i + 1, roads.size()):
			var ri: Array = roads[i]
			var rj: Array = roads[j]
			var pi: PackedVector3Array = ri[1]
			var pj: PackedVector3Array = rj[1]
			var ends := [pi[0], pi[-1], pj[0], pj[-1]]
			var clear := (float(ri[2]) + float(rj[2])) * 0.5
			for si: Array in _segs(ri):
				for sj: Array in _segs(rj):
					var cps := Geometry2D.get_closest_points_between_segments(si[0], si[1], sj[0], sj[1])
					var d := (cps[0] as Vector2).distance_to(cps[1])
					if d >= clear - 0.5:
						continue
					# (Fine near a node they share or meet at.)
					var near_node := false
					for e: Vector3 in ends:
						if (cps[0] as Vector2).distance_to(Vector2(e.x, e.z)) < clear + 30.0:
							near_node = true
					# (The gateway's slip road tapering into the main line: a
					# merge, only between those two, only within the taper.)
					var mg: Dictionary = P.get("merge", {})
					if not mg.is_empty() and mg["slip"] in [ri[0], rj[0]] and "Harbour Approach" in [ri[0], rj[0]]:
						var mn: Vector3 = mg["node"]
						if (cps[0] as Vector2).distance_to(Vector2(mn.x, mn.z)) < float(mg["taper"]) + 22.0:
							near_node = true
					if not near_node:
						bad.append("%s / %s at %s" % [ri[0], rj[0], (cps[0] as Vector2).round()])
	t.check(bad.is_empty(), "no overlapping carriageways (%s)" % [bad.slice(0, 4)])


func test_network_is_connected_from_both_bridges(t) -> void:
	# A graph of road ends: everything reachable from the merge (where both
	# bridges arrive), and the only dead ends are the deliberate ones
	# (the car park's ramp, the marina's car park, the gated airside road
	# and fuel farm).
	var P := _plan()
	var adj := {}
	for r: Array in P["roads"]:
		var pts: PackedVector3Array = r[1]
		var a := _key(pts[0])
		var b := _key(pts[-1])
		for k in [a, b]:
			if not adj.has(k):
				adj[k] = []
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	var start := _key(P["bridge_foot"])
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var k: Vector2i = todo.pop_back()
		for n2 in adj[k]:
			if not seen.has(n2):
				seen[n2] = true
				todo.append(n2)
	t.check(seen.size() == adj.size(), "all %d road nodes reachable from the bridges (%d)" % [adj.size(), seen.size()])
	var dead: Array = []
	for k in adj:
		if (adj[k] as Array).size() == 1:
			dead.append(k)
	# The bridge landings (the bridges carry on), plus the deliberate ends.
	var allowed := 2 + 5   # (+ Hangar Access to the aviation office)
	t.check(dead.size() <= allowed, "dead ends only where intended: %d (%s)" % [dead.size(), dead])
	for B: Dictionary in P["bridges"]:
		var jl := SkyportIsland.l(B["pts"][-1])
		t.check(adj.has(_key(jl)), "%s lands on an island road" % B["name"])


func test_every_place_has_road_access(t) -> void:
	var P := _plan()
	var far: Array = []
	for id: String in P["sites"]:
		var door: Vector3 = P["sites"][id]["door"]
		var d := SkyportIsland.road_clearance(P, Vector2(door.x, door.z))
		if d > 45.0:
			far.append("%s %.0f m" % [id, d])
	t.check(far.is_empty(), "every site within 45 m of a road kerb (%s)" % [far])


func test_airport_line_joins_the_three_islands(t) -> void:
	var P := _plan()
	t.check(P.has("rail") and (P["rail"] as Array).size() == 1, "the Airport Line is planned")
	var line: Dictionary = P["rail"][0]
	var pts: PackedVector3Array = line["pts"]
	# Continuous (2 m samples), gentle grades, no kinks.
	var gap := 0.0
	var grade := 0.0
	var turn := 0.0
	for i in pts.size() - 1:
		var d := pts[i + 1] - pts[i]
		gap = maxf(gap, Vector2(d.x, d.z).length())
		grade = maxf(grade, absf(d.y) / maxf(Vector2(d.x, d.z).length(), 0.01))
		if i > 0:
			var d0 := pts[i] - pts[i - 1]
			turn = maxf(turn, absf(Vector2(d0.x, d0.z).angle_to(Vector2(d.x, d.z))))
	t.check(gap < 2.5, "continuous track (largest step %.2f m)" % gap)
	t.check(grade < 0.035, "grades under 3.5%% (%.1f%%)" % (grade * 100.0))
	t.check(turn < deg_to_rad(4.0), "no kinks (sharpest %.1f° per 2 m)" % rad_to_deg(turn))
	# Ends off both cities, through Skyport.
	var a := Vector2(pts[0].x, pts[0].z)
	var b := Vector2(pts[-1].x, pts[-1].z)
	t.check(a.y < 700.0 and a.x < -400.0, "west end off Westbank (%s)" % a.round())
	t.check(b.y < 700.0 and b.x > 300.0, "east end off the Commercial Island (%s)" % b.round())
	var on_sky := 0
	for p in pts:
		if SkyportIsland.contains(p.x, p.z):
			on_sky += 1
	t.check(on_sky * RailNetwork.STEP > 1000.0, "over 1 km of it on Skyport (%.0f m)" % (on_sky * RailNetwork.STEP))
	# Four stations, each on straight track.
	var st: Array = line["stations"]
	t.check(st.size() == 4, "four stations (%d)" % st.size())
	for s: float in st:
		var p0 := RailNetwork._at(pts, s - RailNetwork.STATION_LEN * 0.5, false)
		var p1 := RailNetwork._at(pts, s + RailNetwork.STATION_LEN * 0.5, false)
		var pm := RailNetwork._at(pts, s, false)
		var dev := Geometry2D.get_closest_point_to_segment(Vector2(pm.x, pm.z), Vector2(p0.x, p0.z), Vector2(p1.x, p1.z)).distance_to(Vector2(pm.x, pm.z))
		t.check(dev < 0.3, "station at %.0f m on straight track (%.2f m off)" % [s, dev])
	# The trains run on it.
	var found := false
	for ln: Dictionary in _layout.rail.lines:
		if ln["name"] == "airport":
			found = true
	t.check(found, "the Airport Line is one of the city's train lines")


func test_airport_line_is_clear(t) -> void:
	# Deck footprint clear of every building (tall ones: it runs at 19 m),
	# the runway and every taxiway; it never crosses a road bridge.
	var P := _plan()
	var loc: PackedVector2Array = P["rail_local"][0]
	var hits: Array = []
	for i in range(0, loc.size(), 2):
		var q := loc[i]
		for bd: Dictionary in P["buildings"]:
			var t0: Array = bd["tiers"][0]
			var rect := Rect2(t0[0], t0[1], float(t0[2]) - float(t0[0]), float(t0[3]) - float(t0[1])).grow(AirportRail.DECK_HALF + 0.3)
			if rect.has_point(q):
				hits.append("building at %s" % q.round())
		for s: Array in P["strips"]:
			if float(s[3]) < 2.0:
				continue
			var a: Vector3 = s[1]
			var b: Vector3 = s[2]
			var cp := Geometry2D.get_closest_point_to_segment(q, Vector2(a.x, a.z), Vector2(b.x, b.z))
			if cp.distance_to(q) < float(s[3]) + AirportRail.DECK_HALF + 5.0:
				hits.append("airside strip at %s" % q.round())
	t.check(hits.is_empty(), "rail corridor clear (%s)" % [hits.slice(0, 4)])
	var pts: PackedVector3Array = P["rail"][0]["pts"]
	for B: Dictionary in P["bridges"]:
		var bp: PackedVector3Array = B["pts"]
		var cross := false
		for i in range(0, pts.size() - 1, 4):
			for k in bp.size() - 1:
				if Geometry2D.segment_intersects_segment(Vector2(pts[i].x, pts[i].z), Vector2(pts[mini(i + 4, pts.size() - 1)].x, pts[mini(i + 4, pts.size() - 1)].z),
						Vector2(bp[k].x, bp[k].z), Vector2(bp[k + 1].x, bp[k + 1].z)) != null:
					cross = true
		t.check(not cross, "the line never crosses the %s" % B["name"])


func test_trains_run_the_whole_airport_line(t) -> void:
	# The city's own Trains on the Airport Line: over a full return cycle
	# each train calls at all four stations both ways (dwells there), runs
	# end to end on its own track, and its cars stay on the rails.
	var P := _plan()
	var line: Dictionary = P["rail"][0]
	var tr := Trains.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(tr)
	tr.setup([line], BoxMesh.new(), BoxMesh.new())
	var trains: Array = tr._trains
	t.check(trains.size() == 2, "two trains, one on each track (%d)" % trains.size())
	var stations: Array = line["stations"]
	var total: float = (line["pts"] as PackedVector3Array).size() * RailNetwork.STEP
	for k in trains.size():
		var trn: Dictionary = trains[k]
		var cycle: float = trn["cycle"]
		var calls := {}
		var lo := INF
		var hi := -INF
		var off_rail := 0.0
		var step := 0.5
		var tt := 0.0
		var prev := -1.0
		while tt < cycle + 1.0:
			tr._clock = tt
			tr._place_all()
			var s: float = trn["s"]
			lo = minf(lo, s)
			hi = maxf(hi, s)
			for si in stations.size():
				if absf(s - float(stations[si])) < 0.01 and absf(float(trn["v"])) < 0.01:
					calls[si] = int(calls.get(si, 0)) + 1
			for car: AnimatableBody3D in trn["cars"]:
				var p := car.global_position
				var best := INF
				var pts: PackedVector3Array = line["pts"]
				var guess := clampi(int(s / RailNetwork.STEP), 0, pts.size() - 1)
				for i in range(maxi(0, guess - 30), mini(pts.size(), guess + 30)):
					best = minf(best, Vector2(p.x - pts[i].x, p.z - pts[i].z).length())
				off_rail = maxf(off_rail, absf(best - RailNetwork.PAIR))
			tt += step
		t.check(calls.size() == stations.size(), "train %d calls at all %d stations (%s)" % [k, stations.size(), calls.keys()])
		t.check(lo < float(stations[0]) + 1.0 and hi > float(stations[-1]) - 1.0,
			"train %d runs end to end (%.0f–%.0f of %.0f m)" % [k, lo, hi, total])
		t.check(off_rail < 0.6, "train %d's cars on their track (worst %.2f m off)" % [k, off_rail])
		t.note("train %d: round trip %.0f s, %d station calls" % [k, cycle, calls.size()])
	tr.queue_free()
