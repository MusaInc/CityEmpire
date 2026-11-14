extends RefCounted
## GPS routes follow the road graph (never straight through buildings or
## water), work on foot and by car across both landmasses, and say so when
## a place can't be reached.

static var _layout: CityLayout
static var _gps: Gps
static var _grid := {}


func _setup() -> Gps:
	if _gps == null:
		_layout = CityLayout.new().generate()
		_gps = Gps.new()
		_gps.net = RoadNet.new().build(_layout)
		for b in _layout.buildings:
			if b["kind"] == "invisible":
				continue
			for t in b["tiers"]:
				var box := CityLayout.tier_aabb(b, t)
				for cx in range(floori(box.position.x / 25.0), floori(box.end.x / 25.0) + 1):
					for cz in range(floori(box.position.z / 25.0), floori(box.end.z / 25.0) + 1):
						var k := Vector2i(cx, cz)
						if not _grid.has(k):
							_grid[k] = []
						_grid[k].append(box)
	return _gps


func _inside_building(p: Vector3) -> bool:
	# (At the route's own height: roads on decks pass over low roofs.)
	for box: AABB in _grid.get(Vector2i(floori(p.x / 25.0), floori(p.z / 25.0)), []):
		if box.size.x < 1.5 or box.size.z < 1.5 or box.size.y < 1.5:
			continue
		if box.grow(-0.6).has_point(p + Vector3.UP * 1.0):
			return true
	return false


func _units() -> Array:
	var out: Array = []
	for P in [_layout.mainland.premises, _layout.premises]:
		out.append_array(P.units)
	return out


func _unit(kind: String, island: String) -> Dictionary:
	for u in _units():
		if u["kind"] == kind and u["island"] == island:
			return u
	return {}


func _check_route(t, r: Dictionary, from: Vector3, to: Vector3, what: String) -> void:
	var pts: PackedVector3Array = r["points"]
	t.check(String(r["error"]) == "" and pts.size() >= 3, "%s: a route (%s)" % [what, r["error"]])
	if pts.size() < 3:
		return
	var straight := Vector2(from.x - to.x, from.z - to.z).length()
	t.check(float(r["length"]) >= straight * 0.98, "%s: route %.0f m ≥ straight line %.0f m" % [what, r["length"], straight])
	t.check(float(r["length"]) < straight * 3.5 + 400.0, "%s: no wild detour (%.0f m)" % [what, r["length"]])
	# Every stretch of the line is on a road: samples every ~4 m are near a
	# lane and never inside a building or over the sea (ends excepted: the
	# door and where you stand).
	var off_road := 0
	var in_building := 0
	var wet := 0
	var n := 0
	for i in range(1, pts.size() - 2):
		var a := pts[i]
		var b := pts[i + 1]
		var steps := maxi(int(Vector2(b.x - a.x, b.z - a.z).length() / 4.0), 1)
		for k in steps:
			var p := a.lerp(b, float(k) / steps)
			n += 1
			if _gps.net.nearest(p, Vector3.ZERO, 9.0).is_empty():
				off_road += 1
			if _inside_building(p):
				in_building += 1
			if _layout.is_water(p) and p.y < 2.0:
				wet += 1
	t.check(off_road == 0, "%s: every sample on a road (%d of %d off)" % [what, off_road, n])
	t.check(in_building == 0, "%s: never through a building (%d)" % [what, in_building])
	t.check(wet == 0, "%s: never across open water (%d)" % [what, wet])


func test_walk_route_follows_streets(t) -> void:
	var g := _setup()
	var a := _unit("shop", "west")
	var b := _unit("wholesale", "west")
	var from := Premises.door_point(a) + Premises.outward(a) * 3.0
	var to := Premises.door_point(b) + Premises.outward(b) * 3.0
	_check_route(t, g.plan(from, to, "walk"), from, to, "walk to the cash & carry")


func test_drive_route_crosses_the_bridge(t) -> void:
	var g := _setup()
	var a := _unit("shop", "west")
	var b := _unit("wholesale", "east")
	var from := Premises.door_point(a) + Premises.outward(a) * 6.0
	var to := Premises.door_point(b) + Premises.outward(b) * 4.0
	var r := g.plan(from, to, "drive")
	_check_route(t, r, from, to, "drive Westbank → Harbour Wholesale")
	# (Over the river: some of the route is on the bridge between the lands.)
	var crossed := false
	for p in (r["points"] as PackedVector3Array):
		if p.x > CityLayout.FAR_SHORE and p.x < -100.0:
			crossed = true
	t.check(crossed, "the drive crosses the river on the bridge")


func test_walk_and_drive_to_every_shop(t) -> void:
	var g := _setup()
	var a := _unit("shop", "west")
	var from := Premises.door_point(a) + Premises.outward(a) * 3.0
	var fails: Array = []
	var t0 := Time.get_ticks_usec()
	var n := 0
	for u in _units():
		var to := Premises.door_point(u) + Premises.outward(u) * 3.0
		for m in ["walk", "drive"]:
			var r := g.plan(from, to, m)
			n += 1
			if String(r["error"]) != "" or (r["points"] as PackedVector3Array).size() < 2:
				fails.append("%s %s: %s" % [m, u["id"], r["error"]])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	t.check(fails.is_empty(), "every unit reachable on foot and by car (%d fail: %s)" % [fails.size(), str(fails.slice(0, 4))])
	t.check(ms < 120.0, "a route costs %.1f ms on average (computed only on set / reroute)" % ms)


func test_unreachable_is_explained(t) -> void:
	var g := _setup()
	var a := _unit("shop", "west")
	var from := Premises.door_point(a) + Premises.outward(a) * 3.0
	var sea := Vector3(-150.0, 0.0, -1400.0)   # open water south of the river mouth
	var r := g.plan(from, sea, "walk")
	t.check(String(r["error"]) != "", "a destination out at sea gets a reason (%s)" % r["error"])
	t.check((r["points"] as PackedVector3Array).is_empty(), "…and no line is drawn")
