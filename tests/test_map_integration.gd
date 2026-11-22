extends RefCounted

func test_airport_roads_and_buildings(t) -> void:
	var was := SkyportIsland.enabled
	SkyportIsland.enabled = true
	var layout := CityLayout.new().generate()
	var p := SkyportIsland.plan(layout)
	var bad := []
	for b: Dictionary in p["buildings"]:
		t.near(BuildingMesher.base_of(b), SkyportIsland.LAND_Y, 0.001, "facade anchored to island ground")
		var tier: Array = b["tiers"][0]
		var rect := Rect2(Vector2(tier[0], tier[1]), Vector2(tier[2] - tier[0], tier[3] - tier[1]))
		if rect.intersects(SkyportAirport.CAR_PARK):
			bad.append("car park overlaps %s" % rect)
		for q: Vector2 in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
			var height := SkyportIsland.ground_y_local(q.x, q.y)
			if is_nan(height) or absf(height - float(tier[4])) > 0.05:
				bad.append("foundation at %s" % q)
	for r: Array in p["roads"]:
		var pts: PackedVector3Array = r[1]
		for i in pts.size() - 1:
			var n := maxi(1, ceili(pts[i].distance_to(pts[i + 1]) / 3.0))
			var d := (pts[i + 1] - pts[i]).normalized()
			var side := Vector3(-d.z, 0, d.x)
			for k in n + 1:
				for offset: float in [-float(r[2]) * 0.5, 0.0, float(r[2]) * 0.5]:
					var q := pts[i].lerp(pts[i + 1], float(k) / n) + side * offset
					if not SkyportIsland.contains_local(q.x, q.z):
						bad.append("%s off land %s" % [r[0], q])
					for b: Dictionary in p["buildings"]:
						var a: Array = b["tiers"][0]
						if Rect2(Vector2(a[0], a[1]), Vector2(a[2] - a[0], a[3] - a[1])).has_point(Vector2(q.x, q.z)):
							bad.append("%s blocked at %s" % [r[0], q])
	t.check(bad.is_empty(), "road width and foundation audit: %s" % str(bad.slice(0, 12)))
	var lanes := SkyportIsland.lanes(layout, 6.0)
	for start in lanes.size():
		var seen := {start: true}
		var queue := [start]
		while not queue.is_empty():
			var id: int = queue.pop_back()
			for next: int in lanes[id]["next"]:
				if not seen.has(next):
					seen[next] = true
					queue.append(next)
		# Every directed lane must reach a city exit without teleporting.
		var exits := 0
		for j in seen:
			if lanes[j]["city_end"]:
				exits += 1
		t.check(exits > 0, "lane %d can leave the island" % start)
	var gps := Gps.new()
	gps.net = RoadNet.new().build(layout)
	var terminal := SkyportIsland.w(Vector3(2220, SkyportIsland.LAND_Y, 140))
	for bridge: Dictionary in p["bridges"]:
		var city_point: Vector3 = bridge["s0"] - bridge["u"] * 20.0
		for pair: Array in [[city_point, terminal], [terminal, city_point]]:
			var route := gps.plan(pair[0], pair[1], "drive")
			t.check(route["error"] == "" and route["points"].size() > 2, "%s airport route in both directions: %s" % [bridge["name"], route["error"]])
			var crossed := false
			var mid: Vector3 = bridge["S"] + bridge["u"] * float(bridge["L"]) * 0.5
			for point: Vector3 in route["points"]:
				if Vector2(point.x - mid.x, point.z - mid.z).length() < 30.0:
					crossed = true
			t.check(crossed, "%s route uses its actual span" % bridge["name"])
	gps.free()
	var signatures := {}
	for road: Array in p["roads"]:
		var pts: PackedVector3Array = road[1]
		for i in pts.size() - 1:
			var key := "%s:%s" % [pts[i], pts[i + 1]]
			var reverse := "%s:%s" % [pts[i + 1], pts[i]]
			t.check(not signatures.has(key) and not signatures.has(reverse), "no duplicate road segment")
			signatures[key] = true
	for i in p["buildings"].size():
		var a: Array = p["buildings"][i]["tiers"][0]
		var rect := Rect2(Vector2(a[0], a[1]), Vector2(a[2] - a[0], a[3] - a[1]))
		for j in range(i + 1, p["buildings"].size()):
			var b: Array = p["buildings"][j]["tiers"][0]
			t.check(not rect.intersects(Rect2(Vector2(b[0], b[1]), Vector2(b[2] - b[0], b[3] - b[1]))), "buildings %d and %d do not overlap" % [i, j])
	SkyportIsland.enabled = was


func test_generated_layout_releases_both_islands(t) -> void:
	var layout := CityLayout.new().generate(1)
	var island: WeakRef = weakref(layout)
	var westbank: WeakRef = weakref(layout.mainland)
	layout = null
	t.check(island.get_ref() == null and westbank.get_ref() == null,
		"generated layouts release their road, architecture and property helpers")
