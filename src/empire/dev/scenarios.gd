extends Node
## Runtime player journeys through the real game (scene, physics, streaming
## interiors, phone UI, GPS): `--play --new --scenarios[=A,E,…]`. Run it
## under xvfb (the maps only record what they drew when they draw).
## Moves the hero by teleporting (walking routes are the GPS's job, which
## is checked by following its own route points). Prints SCENARIO PASS /
## FAIL lines and quits with the number of failures.

var game: EmpireGame
var fails := 0
var checks := 0
var _which := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_which = String(game.args.get("scenarios", "1"))
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if game.args.has("sc-debug"):
		print("    gps: active=%s ref=%s label=%s pts=%d msg=%s manual=%s obj=%s" % [game.gps.active(), game.gps.ref, game.gps.label,
			game.gps.points.size(), game.gps.message, game.empire.flags.get("gps_manual", false), game.objective()[0]])
	checks += 1
	if not ok:
		fails += 1
	print("SCENARIO %s  %s" % ["PASS" if ok else "FAIL", what])


func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


## Waits until cond() is true or `secs` of real time pass (software-rendered
## runs crawl at a few fps, so fixed waits aren't reliable). Returns cond().
func until(cond: Callable, secs: float) -> bool:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func want(key: String) -> bool:
	return _which == "1" or key in _which.split(",")


func stand(p: Vector3) -> void:
	if game.ui.panel_open():
		game.ui.close_panel(true)
	if game.driving != "":
		game.exit_vehicle()
	game.player.respawn(p + Vector3.UP * 0.95)
	game.player.last_safe_position = p + Vector3.UP * 0.95
	game.world.build_all_near(p, 200.0)
	await frames(6)
	game._update_spot()


func door_out(u: Dictionary, m := 3.0) -> Vector3:
	return Premises.door_point(u) + Premises.outward(u) * m


## B: drive the suspension bridge's joints at speed. A car in your hands
## runs from the Westbank approach viaduct over the anchorage onto the deck
## (the old 2 m hole), and from the deck's east end onto the island ramp.
## Fails if it drops, gets thrown up, or stalls.
func scenario_b() -> void:
	print("--- B: bridge joints")
	var vid := String(game.empire.vehicles[0]["id"])
	game.enter_vehicle(vid)
	var car: Car = game.cars[vid]
	game.drive_input.enabled = false
	var runs := [[CityLayout.FAR_SHORE - 70.0, CityLayout.FAR_SHORE + 60.0, "west joint (viaduct → anchorage → deck)"],
		[20.0, 76.0, "east joint (deck → island ramp)"]]
	for run in runs:
		var x0: float = run[0]
		var x1: float = run[1]
		var y0 := CityInfrastructure.bridge_height(game.layout, x0) if x0 > 56.0 else CityLayout.approach_y(x0)
		var z := CityLayout.BRIDGE_Z + 3.8
		car.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x0, y0 + 0.6, z)), Vector3(14.0, 0.0, 0.0))
		var min_dy := 0.0
		var max_vy := 0.0
		var end := Time.get_ticks_msec() + 150000
		var reached := false
		while Time.get_ticks_msec() < end:
			car.throttle = 0.8
			car.brake = 0.0
			car.steer = -clampf((car.global_position.z - z) * 0.08, -0.3, 0.3)  # (heading +x: right is +z)
			await get_tree().physics_frame
			var px := car.global_position.x
			var want := CityInfrastructure.bridge_height(game.layout, px) if px > 56.0 else (CityLayout.approach_y(px) if px < CityLayout.FAR_SHORE - 2.0 else CityLayout.BRIDGE_DECK)
			min_dy = minf(min_dy, car.global_position.y - want)
			max_vy = maxf(max_vy, absf(car.linear_velocity.y))
			if px > x1:
				reached = true
				break
		check(reached, "%s: drove across (%.0f m/s)" % [run[2], car.speed])
		check(min_dy > -1.0, "%s: never dropped below the road (lowest %.2f m)" % [run[2], min_dy])
		check(max_vy < 4.0, "%s: no jolt (peak vertical speed %.1f m/s)" % [run[2], max_vy])
	game.drive_input.enabled = true


# ------------------------------------------------- Skyport expansion
## Ground height of the driving surface under (x, z), cast from `from_y`
## down (roads, decks, land; not props). NAN = nothing.
func _surface(x: float, z: float, from_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - 80.0, z), 1 | (1 << 3))
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else NAN


## Walks a line of samples along a road; returns [steps over 0.18 m, holes,
## worst step, where].
func _audit_line(pts: Array, expect: Callable) -> Array:
	var steps := 0
	var holes := 0
	var worst := 0.0
	var where := Vector3.ZERO
	var prev := NAN
	for p: Vector3 in pts:
		# (From just above the road: overpasses and decks overhead don't count.)
		var y := _surface(p.x, p.z, float(expect.call(p)) + 0.3)
		if is_nan(y) or y < float(expect.call(p)) - 1.0:
			holes += 1
			if game.args.has("sc-debug"):
				print("    hole at %s (expect %.2f, got %s)" % [p, float(expect.call(p)) - 0.3, y])
			where = p
			prev = NAN
			continue
		# (Against the road's own height: a hill is a slope, not a step.)
		var dev := y - float(expect.call(p))
		if not is_nan(prev) and absf(dev - prev) > 0.18:
			steps += 1
			if game.args.has("sc-debug"):
				print("    step %.2f at %s" % [dev - prev, p])
			if absf(dev - prev) > worst:
				worst = absf(dev - prev)
				where = p
		prev = dev
	return [steps, holes, worst, where]


## XA: surface audit. Every lane of the Skyport bridge from the city avenue
## to the island (0.5 m samples), every island road, the old bridge's two
## joints, and every city street centreline on both landmasses (2 m). A
## road may slope; it may not step more than a kerb or have holes.
func _probe_at(x: float, z: float, from_y: float) -> void:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - 80.0, z), 1 | (1 << 3))
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	print("    probe (%.1f, %.1f): %s y=%s road_y=%.2f ground_y=%.2f" % [x, z, (hit["collider"] as Node).get_path() if not hit.is_empty() else "nothing",
		(hit["position"] as Vector3).y if not hit.is_empty() else "-", game.layout.terrain.road_y(x, z), game.layout.ground_y(x, z)])


## A bridge's frame: along (m from its sea-wall end S, + towards the
## island) and across (m, + to the left of travel towards the island).
func _bf(B: Dictionary, p: Vector3) -> Vector2:
	var u: Vector3 = B["u"]
	var S: Vector3 = B["S"]
	var r := Vector2(p.x - S.x, p.z - S.z)
	return Vector2(r.dot(Vector2(u.x, u.z)), r.dot(Vector2(-u.z, u.x)))


func _bp(B: Dictionary, along: float, across: float) -> Vector3:
	var u: Vector3 = B["u"]
	var S: Vector3 = B["S"]
	return Vector3(S.x + u.x * along - u.z * across, 0.0, S.z + u.z * along + u.x * across)


## The driving surface's height: a bridge's ramp / deck, else the island,
## else the city's road.
func _road_y(p: Vector3) -> float:
	var by := SkyportIsland.bridge_road_y(game.layout, p.x, p.z)
	if not is_nan(by):
		return by
	var iy := SkyportIsland.ground_y(p.x, p.z)
	return iy if not is_nan(iy) else game.layout.terrain.road_y(p.x, p.z)


## Where a bridge's ramp starts on the coast road (along, from S).
func _ramp_start(B: Dictionary) -> float:
	return _bf(B, B["s0"]).x


func scenario_xa() -> void:
	print("--- XA: road surface audit")
	var P: Dictionary = game.skyport.plan_data
	game._teleport(SkyportIsland.w(Vector3(1700, SkyportIsland.LAND_Y + 1.0, -20)), 0.0)   # (loads the island's detail)
	await frames(5)
	var exp_b := func(p: Vector3) -> float: return _road_y(p) + 0.3
	for B: Dictionary in P["bridges"]:
		var lane_pts: Array = []
		var tot := [0, 0, 0.0, Vector3.ZERO]
		for dz: float in [-7.0, -3.4, 0.0, 3.4, 7.0]:
			var lp: Array = []
			# (From just onto the ramp to past the landing on the quay.)
			var al := _ramp_start(B) + 2.0
			while al < float(B["L"]) + 16.0:
				lp.append(_bp(B, al, dz))
				al += 0.5
			lane_pts.append_array(lp)
			var rl := _audit_line(lp, exp_b)
			tot[0] += int(rl[0])
			tot[1] += int(rl[1])
			if float(rl[2]) > float(tot[2]):
				tot[2] = rl[2]
				tot[3] = rl[3]
		check(int(tot[0]) == 0 and int(tot[1]) == 0, "%s, coast road to island, 5 lanes: %d steps, %d holes (worst %.2f m at %s)" % [B["name"], tot[0], tot[1], tot[2], tot[3]])
		# Something solid standing up out of the road (railings, walls) in the lanes.
		var blocked := 0
		var bwhere := Vector3.ZERO
		var u: Vector3 = B["u"]
		for p: Vector3 in lane_pts:
			var y := _surface(p.x, p.z, float(exp_b.call(p)) + 2.5)
			if is_nan(y):
				continue
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 0.45, p.z) - u * 0.5, Vector3(p.x, y + 0.45, p.z) + u * 0.5, 1 | (1 << 3))
			if not game.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				blocked += 1
				bwhere = p
		check(blocked == 0, "nothing stands up in %s's lanes (%d samples blocked, last at %s)" % [B["name"], blocked, bwhere])
		# Traffic on the coast road through the bridge's junction: five lane
		# lines along the ring road, 45 m either side of the junction.
		var cross_bad := 0
		var city: CityLayout = game.layout if B["city"] == "island" else game.layout.mainland
		var s0v: Vector3 = B["s0"]
		var ring: Dictionary = city.roads.by_name.get("ring", {})
		var rp2: PackedVector2Array = ring.get("pts", PackedVector2Array())
		for lane_off: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			var previous := NAN
			for i in rp2.size() - 1:
				var a2 := rp2[i]
				var b2 := rp2[i + 1]
				var L2 := a2.distance_to(b2)
				var nrm := (b2 - a2).normalized().orthogonal()
				var t := 0.0
				while t < L2:
					var q := a2.lerp(b2, t / L2)
					t += 0.5
					if q.distance_to(Vector2(s0v.x, s0v.z)) > 45.0:
						previous = NAN
						continue
					q += nrm * lane_off
					var y := _surface(q.x, q.y, city.terrain.road_y(q.x, q.y) + 1.5)
					if is_nan(y) or (not is_nan(previous) and absf(y - previous) > 0.18):
						cross_bad += 1
					previous = y
		check(cross_bad == 0, "%s coast-road cross traffic: %d steps or holes" % [B["name"], cross_bad])
	var island_pts: Array = []
	var road_obstacles: Array = []
	var clearance := BoxShape3D.new()
	clearance.size = Vector3(2.0, 1.4, 3.0)
	for rd in game.skyport.wplan["roads"]:
		if rd[3]:
			continue
		var rp: PackedVector3Array = rd[1]
		for i in rp.size() - 1:
			var L := rp[i].distance_to(rp[i + 1])
			var k := 0.0
			while k < L:
				var centre := rp[i].lerp(rp[i + 1], k / L)
				island_pts.append(centre)
				var direction := (rp[i + 1] - rp[i]).normalized()
				for offset: float in [-3.4, 3.4]:
					var query := PhysicsShapeQueryParameters3D.new()
					query.shape = clearance
					query.collision_mask = 1
					query.transform = Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.z)), centre + Vector3(-direction.z, 0, direction.x) * offset + Vector3.UP * 1.1)
					if not game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
						road_obstacles.append("%s at %s" % [rd[0], centre])
				k += 2.0
	var r2 := _audit_line(island_pts, func(p): return SkyportIsland.LAND_Y + 0.3)   # (all flat)
	check(int(r2[0]) == 0 and int(r2[1]) == 0, "island roads: %d steps, %d holes over %d samples" % [r2[0], r2[1], island_pts.size()])
	check(road_obstacles.is_empty(), "island vehicle clearance: %d obstructions %s" % [road_obstacles.size(), str(road_obstacles.slice(0, 6))])
	var ramp_errors := 0
	var park := SkyportAirport.CAR_PARK
	for level in 4:
		for k in 65:
			var z := park.end.y - k
			var y := SkyportIsland.LAND_Y + level * 3.2 + clampf((float(k) - 8.0) / 48.0, 0.0, 1.0) * 3.2
			var wp := SkyportIsland.w(Vector3(park.position.x - 4, y, z))
			var actual := _surface(wp.x, wp.z, y + 0.4)
			if is_nan(actual) or absf(actual - y) > 0.04:
				ramp_errors += 1
				print("Ramp level %d sample %d expected %.3f got %.3f" % [level, k, y, actual])
	check(ramp_errors == 0, "all four parking ramps have continuous collision (%d bad samples)" % ramp_errors)
	# City streets (both landmasses), centrelines; a jump between samples on
	# separate roads is not a step, so audit each road on its own. Where a
	# bridge ramp carries the road (the old bridge's island ramp, the Skyport
	# bridges' ramps) the street under it is skipped: the ramp is the road
	# there, and it's audited above / by --scenarios=B.
	var carried := func(q: Vector2) -> bool:
		for rp3: Vector3 in game.layout.bridge_ramp:
			if Vector2(rp3.x, rp3.z).distance_to(q) < 12.0:
				return true
		for B2: Dictionary in P["bridges"]:
			var f := _bf(B2, Vector3(q.x, 0.0, q.y))
			# The tapered shoulders are audited by the cross-traffic scan above.
			var half_width := 21.0 if f.x <= _bf(B2, B2["a0"]).x else 12.0
			if f.x > _ramp_start(B2) - 2.0 and f.x < 2.0 and absf(f.y) < half_width:
				return true
		return false
	var bad_roads := 0
	var worst := 0.0
	var wpos := Vector3.ZERO
	var n := 0
	for L: CityLayout in [game.layout, game.layout.mainland]:
		for rd in L.roads.roads:
			var rp2: PackedVector2Array = rd["pts"]
			var pts: Array = []
			for i in rp2.size() - 1:
				var a := rp2[i]
				var b := rp2[i + 1]
				var Ln := a.distance_to(b)
				var k := 0.0
				while k < Ln:
					var q2 := a.lerp(b, k / Ln)
					# (Only where the street is drawn: the road graph runs a few
					# metres past the coast, where a headland may now stand.)
					if not game.layout.is_water(Vector3(q2.x, 0, q2.y)) and not L.is_water(Vector3(q2.x, 0, q2.y)) and not carried.call(q2) \
							and Geometry2D.is_point_in_polygon(q2, L.coast):
						pts.append(Vector3(q2.x, 0.0, q2.y))
					k += 2.0
			n += pts.size()
			var rr := _audit_line(pts, func(p): return L.terrain.road_y(p.x, p.z) + 0.3)
			if int(rr[0]) > 0 or int(rr[1]) > 0:
				bad_roads += 1
				if float(rr[2]) > worst or int(rr[1]) > 0:
					worst = maxf(worst, float(rr[2]))
					wpos = rr[3]
	check(bad_roads == 0, "city streets: %d of the roads have a step or hole (worst %.2f m at %s; %d samples)" % [bad_roads, worst, wpos, n])


## XO: the Skyport coastline vs its content: every building corner, road
## point, airport strip end, stand, helipad and site door is on land and at
## least 8 m from the shore (no building in the sea, no road off the edge).
func scenario_xo() -> void:
	print("--- XO: Skyport coast vs content")
	var P: Dictionary = game.skyport.plan_data
	var o := SkyportIsland.outline()
	var near := func(q: Vector2) -> float:
		var best := INF
		for i in o.size():
			var cp := Geometry2D.get_closest_point_to_segment(q, o[i], o[(i + 1) % o.size()])
			best = minf(best, cp.distance_to(q))
		return best
	var bad: Array = []
	var pts: Array = []
	for b: Dictionary in P["buildings"]:
		var t: Array = b["tiers"][0]
		for c in [Vector2(t[0], t[1]), Vector2(t[2], t[1]), Vector2(t[2], t[3]), Vector2(t[0], t[3])]:
			pts.append(["building", c])
	for r in P["roads"]:
		if r[3]:
			continue
		var rp: PackedVector3Array = r[1]
		for i in rp.size() - 1:
			var L := Vector2(rp[i].x, rp[i].z).distance_to(Vector2(rp[i + 1].x, rp[i + 1].z))
			var k := 0.0
			while k <= L:
				var q := Vector2(rp[i].x, rp[i].z).lerp(Vector2(rp[i + 1].x, rp[i + 1].z), k / maxf(L, 0.01))
				pts.append([String(r[0]), q])
				k += 10.0
	for st in P["strips"]:
		pts.append(["strip", Vector2((st[1] as Vector3).x, (st[1] as Vector3).z)])
		pts.append(["strip", Vector2((st[2] as Vector3).x, (st[2] as Vector3).z)])
	for sd in P["stands"]:
		pts.append(["stand", Vector2((sd[0] as Vector3).x, (sd[0] as Vector3).z)])
	for hp: Vector3 in P["helipads"]:
		if hp.y < SkyportIsland.LAND_Y + 1.0:
			pts.append(["helipad", Vector2(hp.x, hp.z)])
	for k in P["sites"]:
		var d: Vector3 = P["sites"][k]["door"]
		pts.append([k, Vector2(d.x, d.z)])
	for it in pts:
		var q: Vector2 = it[1]
		if not Geometry2D.is_point_in_polygon(q, o) or float(near.call(q)) < 8.0:
			bad.append("%s at %s (%.0f m)" % [it[0], q, near.call(q)])
	check(bad.is_empty(), "all %d content points on land, 8 m+ from the shore (%s)" % [pts.size(), str(bad.slice(0, 6))])
	# The shore isn't a rectangle: the outline's area vs its bounding box.
	var bb := Rect2(o[0], Vector2.ZERO)
	for v in o:
		bb = bb.expand(v)
	var area := 0.0
	for i in o.size():
		area += o[i].x * o[(i + 1) % o.size()].y - o[(i + 1) % o.size()].x * o[i].y
	var fill := absf(area) * 0.5 / bb.get_area()
	check(fill < 0.86, "the island fills %.0f%% of its bounding box (bays, a waist, headlands)" % (fill * 100.0))


## XV: the Skyport bridge at 8, 20 and 34 m/s, city → island and back,
## starting on the avenue (over the ramp and the esplanade): no stall, no
## drop below the road, no jolt, never off the deck.
func scenario_xv() -> void:
	print("--- XV: bridge crossings at speed, both ways")
	var P: Dictionary = game.skyport.plan_data
	var vid := String(game.empire.vehicles[0]["id"])
	game.enter_vehicle(vid)
	var car: Car = game.cars[vid]
	game.drive_input.enabled = false
	game.skyport.load_near_now()
	var speeds: Array = [8.0, 20.0, 34.0] if not OS.has_environment("XV_SPEED") else [float(OS.get_environment("XV_SPEED"))]
	for B: Dictionary in P["bridges"]:
		var u: Vector3 = B["u"]
		var L: float = B["L"]
		for v0: float in speeds:
			for dir: int in [1, -1]:
				# Keep right: the lane left of the centreline going towards
				# the island is +across (see _bf), so dir picks the side.
				var lane := -3.8 * dir
				var a0 := _ramp_start(B) + 2.0 if dir > 0 else L + 14.0
				var a1 := L + 12.0 if dir > 0 else _ramp_start(B) + 4.0
				var p0 := _bp(B, a0, lane)
				var d := u * dir
				car.place(Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), p0 + Vector3.UP * (_road_y(p0) + 0.6)), d * v0)
				var m := {"low": 0.0, "vy": 0.0, "off": 0.0, "at": a0, "vyat": 0.0, "offat": 0.0}
				var ok := await until(func():
					var f := _bf(B, car.global_position)
					var vel := Vector2(car.linear_velocity.x, car.linear_velocity.z)
					var vc := vel.dot(Vector2(-u.z, u.x))
					var kg := clampf(10.0 / maxf(car.speed, 1.0), 0.2, 1.0)
					car.steer = -clampf(((f.y - lane) * 0.1 + vc * 0.12) * kg, -0.3, 0.3) * dir
					car.throttle = 1.0 if car.forward_speed < v0 else 0.0
					car.brake = 0.0
					m["low"] = minf(m["low"], car.global_position.y - _road_y(car.global_position))
					if absf(car.linear_velocity.y) > float(m["vy"]):
						m["vy"] = absf(car.linear_velocity.y)
						m["vyat"] = f.x
					if absf(f.y - lane) > float(m["off"]):
						m["off"] = absf(f.y - lane)
						m["offat"] = f.x
					m["at"] = f.x
					return (f.x > a1) if dir > 0 else (f.x < a1), 400.0)
				if not ok:
					var cs: Array = car.get_colliding_bodies() if car.has_method("get_colliding_bodies") else []
					print("    stalled at %s (frame %s) v %s hits %s" % [car.global_position, _bf(B, car.global_position), car.linear_velocity,
						cs.map(func(b): return String((b as Node).get_path()))])
					var sp3 := game.get_world_3d().direct_space_state
					for hy: float in [0.05, 0.4, 0.7, 0.9, 1.1, 1.3, 1.6]:
						for ac2: float in [0.0]:
							var c0 := car.global_position + Vector3(-u.z, 0, u.x) * ac2
							var from3 := Vector3(c0.x, _road_y(c0) + hy, c0.z) + u * float(dir) * 0.0
							var to3 := from3 + u * float(dir) * 4.0
							var q3 := PhysicsRayQueryParameters3D.create(from3, to3, 1 | (1 << 3))
							q3.exclude = [car.get_rid()]
							var h3 := sp3.intersect_ray(q3)
							if not h3.is_empty():
								print("      ray h %.2f ac %.0f hits %s at %s n %s" % [hy, ac2, (h3["collider"] as Node).get_path(), h3["position"], h3["normal"]])
					for d3: float in [0.0, 1.0, 2.0, 3.0, 4.0]:
						var c1 := car.global_position + u * float(dir) * d3
						print("      down at +%.0f: surface %.3f road_y %.3f" % [d3, _surface(c1.x, c1.z, 3.0), _road_y(c1)])
				check(ok and float(m["low"]) > -0.6 and float(m["vy"]) < 6.0 and float(m["off"]) < 6.0,
					"%s %s at %d m/s: across=%s (%.0f m along), lowest %.2f m, peak vertical %.1f m/s (%.0f m), drift %.1f m (%.0f m)" % [
					B["name"], "to the island" if dir > 0 else "to the city", int(v0), ok, m["at"], m["low"], m["vy"], m["vyat"], m["off"], m["offat"]])
	car.throttle = 0.0
	await until(func():
		car.brake = 1.0
		return car.speed < 1.0, 30.0)
	car.brake = 0.0   # (released: the next scenario drives this car)
	game.drive_input.enabled = true
	game.exit_vehicle()


## XR: drive every airport route: from each bridge's island end, a GPS
## road route to every Skyport place (terminal, cargo, aviation, dealers,
## marina, Airport Central's entrance), driven by a physics car following
## it: reaches the end, never stalls, never drops below the road, never
## touches a structure (buildings, rail piers, railings).
func scenario_xr() -> void:
	print("--- XR: driving routes from both bridges to every airport destination")
	var P: Dictionary = game.skyport.plan_data
	var vid := String(game.empire.vehicles[0]["id"])
	game.enter_vehicle(vid)
	var car: Car = game.cars[vid]
	game.drive_input.enabled = false
	game.skyport.load_near_now()
	var dests: Array = []
	for id in ["terminal", "cargo", "aviation", "dealer_commercial", "dealer_luxury", "marina"]:
		dests.append([id, game.skyport_play.site(id)["door"]])
	dests.append(["Airport Central", SkyportIsland.w(Vector3(1910.0, SkyportIsland.LAND_Y, 76.0))])
	var only := OS.get_environment("XR_ONLY")
	for B: Dictionary in P["bridges"]:
		var u: Vector3 = B["u"]
		var L: float = B["L"]
		for dd: Array in dests:
			if only != "" and not String(dd[0]).contains(only):
				continue
			var start := _bp(B, L - 30.0, -3.8)
			start.y = _road_y(start)
			var r: Dictionary = game.gps.plan(start, dd[1], "drive", u)
			var route: PackedVector3Array = r["points"]
			if route.size() < 2:
				check(false, "%s → %s: no route (%s)" % [B["name"], dd[0], r["error"]])
				continue
			car.place(Transform3D(Basis(Vector3.UP, atan2(-u.x, -u.z)), start + Vector3.UP * 0.6), u * 8.0)
			var st := {"i": 0, "low": 0.0, "slow": 0.0, "hits": {}}
			var goal := route[route.size() - 1]
			var ok := await until(func():
				var p := car.global_position
				var i: int = st["i"]
				while i < route.size() - 1 and Vector2(route[i].x - p.x, route[i].z - p.z).length() < 12.0:
					i += 1
				st["i"] = i
				# Pure pursuit: a point ~12 m ahead on the route.
				var tgt := route[i]
				var fwd := -car.global_basis.z
				fwd.y = 0.0
				var des := Vector3(tgt.x - p.x, 0.0, tgt.z - p.z).normalized()
				var cy := fwd.normalized().cross(des).y
				var ang := fwd.normalized().angle_to(des)
				car.steer = clampf(-signf(cy) * ang * 1.6, -1.0, 1.0)
				var want := 13.0 if ang < 0.25 else 7.0
				car.throttle = 0.7 if car.forward_speed < want else 0.0
				car.brake = 0.4 if car.forward_speed > want + 3.0 else 0.0
				st["low"] = minf(float(st["low"]), p.y - _road_y(p))
				if car.speed < 0.5:
					st["slow"] = float(st["slow"]) + get_process_delta_time()
				else:
					st["slow"] = 0.0
				for bdy in car.get_colliding_bodies():
					var co := bdy as CollisionObject3D
					if co and (co.collision_layer & 1) != 0 and (co.collision_layer & (1 << 3)) == 0:
						(st["hits"] as Dictionary)[String(co.get_path())] = true
				return Vector2(goal.x - p.x, goal.z - p.z).length() < 14.0 or float(st["slow"]) > 10.0, 240.0)
			var reached := Vector2(goal.x - car.global_position.x, goal.z - car.global_position.z).length() < 14.0
			check(ok and reached and float(st["low"]) > -0.6 and (st["hits"] as Dictionary).is_empty(),
				"%s → %s: %s (%.0f m route, lowest %.2f m, hits %s)" % [B["name"], dd[0], "arrived" if reached else "stopped %.0f m short" % Vector2(goal.x - car.global_position.x, goal.z - car.global_position.z).length(),
				float(r["length"]), float(st["low"]), (st["hits"] as Dictionary).keys().slice(0, 2)])
			car.throttle = 0.0
			await until(func():
				car.brake = 1.0
				return car.speed < 1.0, 20.0)
			car.brake = 0.0
	game.drive_input.enabled = true
	game.exit_vehicle()


## XN: the Skyport Penthouse – buy it, lift up, up to the helipad and down,
## reload inside, lift down. The suite comes with the hotel.
func scenario_xn() -> void:
	print("--- XN: penthouse and homes")
	game.ui.close_panel(true)
	var e := game.empire
	e.personal_cash = 3000000.0
	var hm := game.home_by_id("home_skyport_penthouse")
	check(not hm.is_empty(), "the penthouse is one of the homes")
	var lift := game.home_lift(hm)
	game._teleport(lift + Vector3(0, 1.0, 0), 0.0)
	await until(func(): return String(game.spot.get("kind", "")) == "home_lift", 20.0)
	check(String(game.game_prompt() if false else game.spot_prompt()[0]).contains("FOR SALE"), "its street lift offers it for sale (%s)" % game.spot_prompt()[0])
	var rec := hm.duplicate()
	rec.erase("h")
	var cash := e.personal_cash + e.company_cash
	check(e.buy_property(rec) and absf(cash - (e.personal_cash + e.company_cash) - float(hm["price"])) < 0.01, "bought for %s, paid once" % EmpireData.money(float(hm["price"])))
	game.act()
	await frames(5)
	var h: Dictionary = hm["h"]
	check(absf(game.player.global_position.y - float(h["y0"])) < 2.5, "the lift took you up to the penthouse (%.0f m)" % game.player.global_position.y)
	var rs: Array = game.skyport_play.roof_spots()
	game._teleport((rs[0] as Vector3) + Vector3.UP * 1.0, 0.0)
	await until(func(): return String(game.spot.get("kind", "")) == "sky_roof", 15.0)
	game.act()
	await frames(10)
	var pad: Vector3 = game.skyport.wplan["penthouse"]["pad"]
	check(Vector2(game.player.global_position.x - pad.x, game.player.global_position.z - pad.z).length() < 12.0 and game.player.global_position.y > pad.y - 0.5,
		"up the stairs onto the rooftop helipad (%.0f m)" % game.player.global_position.y)
	await wait(1.0)
	check(game.player.global_position.y > pad.y - 0.5, "standing on the roof, not falling through it")
	game._teleport(Apartments.spawn_point(h), 0.0)
	game.save_game()
	game.load_game()
	await frames(10)
	check(game.empire.owns_property("home_skyport_penthouse"), "still yours after a reload")
	check(absf(game.player.global_position.y - float(h["y0"]) - 0.95) < 2.0, "reloaded inside the penthouse (%.0f m)" % game.player.global_position.y)
	await until(func(): return String(game.spot.get("kind", "")) == "home_down", 15.0)
	game.act()
	await frames(5)
	check(game.player.global_position.y < SkyportIsland.LAND_Y + 3.0, "lift down to the street")
	check(not game.empire.owns_property("home_skyport_suite"), "the hotel suite isn't yours without the hotel")
	game.empire.personal_cash += 2000000.0
	check(Ventures.buy_estate(game.empire, "skyport_hotel") == "" and game.empire.owns_property("home_skyport_suite"), "buying the hotel gives you the suite's keys")
	Ventures.sell_estate(game.empire, "skyport_hotel")
	check(not game.empire.owns_property("home_skyport_suite"), "selling the hotel hands the keys back")


## XD: drive a car over the landmark bridge onto Skyport Island, and the GPS
## plans a road route from the city to the airport across it.
func scenario_xd() -> void:
	print("--- XD: Skyport bridges and GPS")
	var P: Dictionary = game.skyport.plan_data
	var B: Dictionary = P["bridges"][0]
	var L: float = B["L"]
	var u: Vector3 = B["u"]
	# Start on the coast road by the Harbour Bridge's ramp (earlier
	# scenarios may leave us up a tower).
	var st := _bp(B, _ramp_start(B) - 6.0, 0.0)
	game._teleport(st + Vector3.UP * (_road_y(st) + 1.0), 0.0)
	await frames(5)
	game.set_gps(game.skyport_play.site("terminal")["door"], "Skyport Airport", {"kind": "place", "id": "terminal"})
	game.gps.wait_net()
	await until(func(): return game.gps.points.size() >= 2 or game.gps.message != "", 40.0)
	var crosses := false
	for q in game.gps.points:
		for B2: Dictionary in P["bridges"]:
			var f := _bf(B2, q)
			if f.x > 30.0 and f.x < float(B2["L"]) - 30.0 and absf(f.y) < 14.0:
				crosses = true
	check(game.gps.points.size() >= 2 and crosses, "GPS from the city to the airport crosses a bridge (%d points, %s)" % [game.gps.points.size(), game.gps.message])
	# Set back from any road (the penthouse's lift across its plaza): still
	# a route, ending on foot – it used to say "No road goes there".
	var lift: Vector3 = game.skyport.wplan["homes"][0]["lift"]
	var r2: Dictionary = game.gps.plan(game.player.global_position, lift, "walk")
	check(String(r2["error"]) == "" and (r2["points"] as PackedVector3Array).size() >= 2,
		"a route to the penthouse lift (%d points, '%s')" % [(r2["points"] as PackedVector3Array).size(), r2["error"]])
	var vid := String(game.empire.vehicles[0]["id"])
	game.enter_vehicle(vid)
	var car: Car = game.cars[vid]
	game.drive_input.enabled = false
	var p0 := _bp(B, 6.0, -3.8)
	car.place(Transform3D(Basis(Vector3.UP, atan2(-u.x, -u.z)), p0 + Vector3.UP * (_road_y(p0) + 0.6)), u * 16.0)
	var mm := {"low": 0.0}
	var reached := await until(func():
		var f := _bf(B, car.global_position)
		car.throttle = 0.75
		car.brake = 0.0   # (an earlier scenario may have left it held: XV stops with brake 1)
		car.steer = -clampf((f.y + 3.8) * 0.08, -0.3, 0.3)
		mm["low"] = minf(mm["low"], car.global_position.y - _road_y(car.global_position))
		return f.x > L + 14.0, 180.0)
	check(reached, "drove over the %s onto the island (%.0f of %.0f m)" % [B["name"], _bf(B, car.global_position).x, L])
	check(float(mm["low"]) > -1.0, "never dropped below the deck (lowest %.2f m)" % float(mm["low"]))
	check(not game.layout.is_water(car.global_position), "the island is land, not sea")
	car.throttle = 0.0
	await until(func():
		car.brake = 1.0
		return car.speed < 1.0, 30.0)
	car.brake = 0.0
	game.drive_input.enabled = true
	game.exit_vehicle()
	check(game.driving == "", "stopped and got out on the island")


## XB: a showroom – walk up to a display car, buy it (money once), it's
## parked on the forecourt, and it survives a save and reload.
func scenario_xb() -> void:
	print("--- XB: dealership")
	var sp: SkyportPlay = game.skyport_play
	var door: Vector3 = sp.site("dealer_budget")["door"]
	game._teleport(door + Vector3(0, 1, 2), PI)
	await until(func(): return sp.displays.size() >= 3, 20.0)
	check(sp.displays.size() >= 3, "display cars on the forecourts (%d)" % sp.displays.size())
	var dk: String = sp.displays.keys()[0]
	var dc: Car = sp.displays[dk]
	game._teleport(dc.global_position + Vector3(0, 1.0, 3.6), PI)
	await until(func(): return String(game.spot.get("kind", "")) == "sky_display", 15.0)
	check(String(game.spot.get("kind", "")) == "sky_display", "walking up to a display car offers INSPECT (%s)" % game.spot_prompt()[0])
	game.empire.personal_cash = 30000.0
	var before := game.empire.personal_cash + game.empire.company_cash
	var n0 := game.empire.vehicles.size()
	var err := sp.buy_car("saloon", "dealer_budget")
	var price := float(EmpireData.vehicle_model("saloon")["price"])
	check(err == "" and game.empire.vehicles.size() == n0 + 1, "bought a saloon (%s)" % err)
	check(absf(before - (game.empire.personal_cash + game.empire.company_cash) - price) < 0.01, "paid exactly once (%s)" % EmpireData.money(price))
	var vid := String(game.empire.vehicles[-1]["id"])
	check(game.cars.has(vid), "it's parked on the forecourt")
	# Test drive: no charge, no extra record after.
	var cash := game.empire.personal_cash
	sp.start_test("vanta", "dealer_luxury")
	await frames(5)
	check(game.driving != "" and game.empire.vehicle(game.driving).get("test", false), "test drive started")
	game.exit_vehicle()
	await frames(5)
	check(game.empire.vehicles.size() == n0 + 1 and game.empire.personal_cash == cash, "test drive ended: nothing kept, nothing paid")
	game.save_game()
	game.load_game()
	await frames(10)
	var found := false
	for v in game.empire.vehicles:
		if String(v["id"]) == vid:
			found = true
	check(found and game.cars.has(vid), "the saloon is still yours after a reload")


## XC: clothes – try on in a store, pay, it's owned and worn, a saved
## outfit, all after a reload.
func scenario_xc() -> void:
	print("--- XC: clothing store")
	var e := game.empire
	e.personal_cash = 5000.0
	game.ui.open_store("clothes_premium")
	await frames(3)
	game.ui._style_set({"top": "top_blazer", "shoes": "shoes_royal"})
	await frames(2)
	var un := Wardrobe.unpaid(e.flags, HeroLook.current(e.flags))
	check(un.size() == 2, "trying on two items you don't own (%s)" % str(un))
	# (Empire.pay takes company cash first: count both.)
	var cash := e.personal_cash + e.company_cash
	var err := Wardrobe.buy(e, un, "clothes_premium")
	check(err == "" and absf(cash - e.personal_cash - e.company_cash - 740.0) < 0.01, "paid £740 once (%s)" % err)
	Wardrobe.save_outfit(e.flags, HeroLook.current(e.flags))
	game.ui._close_style()
	game.save_game()
	game.load_game()
	await frames(5)
	var l := HeroLook.current(game.empire.flags)
	check(l["top"] == "top_blazer" and Wardrobe.owns(game.empire.flags, "shoes_royal"), "wearing and owning them after a reload")
	check((game.empire.flags.get("outfits", []) as Array).size() >= 1, "the saved outfit is there")
	# Leaving a store without paying puts your own clothes back.
	game.ui.open_store("clothes_premium")
	await frames(2)
	game.ui._style_set({"shoes": "shoes_gold"})
	game.ui._close_style()
	check(HeroLook.current(game.empire.flags)["shoes"] != "shoes_gold", "walked out unpaid: the gold trainers stay in the shop")


## XW: the walk-in venues (car showrooms, clothes shops). For each room:
## start on the pavement, walk through the sliding doors (they open) to the
## middle of the floor (solid, indoors under its ceiling), visit every
## walk-up point (each offers its prompt), check the display cars stand
## inside, then walk back out. `--sc-film=<dir>`: a screenshot per room.
func scenario_xw() -> void:
	print("--- XW: walk-in venues")
	var v: Venues = game.venues
	var vplan: Dictionary = game.skyport.plan_data.get("venues", {})
	check(vplan.size() == Venues.DEFS.size(), "every venue was carved into its building (%s)" % str(vplan.keys()))
	var p := game.player
	var w := _Walk.new()
	for id: String in vplan:
		var xf := v.venue_xf(id)
		var d: Dictionary = Venues.DEFS[id]
		var street := xf * Vector3(0, 0, 4.0)
		if not game.skyport.near_loaded():
			game.skyport.load_near_now()
		v.load_near_now(street)
		await stand(street)
		await until(func(): return v.rooms.has(id), 10.0)
		check(v.rooms.has(id), "%s: the room streams in" % id)
		if not v.rooms.has(id):
			continue
		var R: Dictionary = v.rooms[id]
		await until(func(): return p.is_on_floor(), 5.0)
		await frames(10)
		p.bot = w
		var opened := [0.0]
		var ax := float(d["aisle"])
		var dx := ((R["doors"][0][1] as Vector3).x + (R["doors"][-1][1] as Vector3).x) * 0.5   # (the entrance)
		var inside := xf * Vector3(ax, 0, -float(d["d"]) * 0.45)
		var watch := func() -> void:
			opened[0] = maxf(opened[0], float(R["door_t"]))
		get_tree().process_frame.connect(watch)
		# Through the doors, along the aisle to mid-floor.
		var a: Dictionary = {}
		for wp: Vector3 in [Vector3(dx, 0, 2.0), Vector3(dx, 0, -0.9), Vector3(ax, 0, -1.1), Vector3(ax, 0, -float(d["d"]) * 0.45)]:
			a = await _walk_to(w, xf * wp, 20.0)
			if not a["ok"]:
				break
		get_tree().process_frame.disconnect(watch)
		check(a["ok"], "%s: walked in through the front (%s)" % [id, a.get("at", "%.1fs" % a["t"])])
		check(opened[0] > 0.8, "%s: the doors slid open (%.2f)" % [id, opened[0]])
		var fy := p.global_position.y - 0.9 - xf.origin.y
		check(absf(fy) < 0.25 and p.is_on_floor(), "%s: standing on the floor (%.2f m)" % [id, fy])
		check(v.ceiling_at(p.global_position) < INF and p.indoors, "%s: indoors under the ceiling" % id)
		if game.args.has("sc-film"):
			# From just inside the doors, eye height, looking in (and back out).
			for view: Array in [["in", Vector3(0, 1.7, -1.5), Vector3(0, 1.2, -float(d["d"]))],
					["back", Vector3(float(d["w"]) * 0.3, 2.2, -float(d["d"]) + 1.5), Vector3(-float(d["w"]) * 0.1, 1.2, 0.0)]]:
				var from: Vector3 = xf * (view[1] as Vector3)
				var to: Vector3 = xf * (view[2] as Vector3)
				game.camera.cine = func(_dt: float) -> Array:
					return [Transform3D(Basis.looking_at(to - from, Vector3.UP), from), 70.0]
				await wait(1.0)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [String(game.args["sc-film"]), id, view[0]])
			game.camera.cine = Callable()
		p.bot = null
		var bad: Array = []
		for sp: Array in R["spots"]:
			var q: Vector3 = sp[1]
			await stand(Vector3(q.x, xf.origin.y, q.z) + (xf.basis * Vector3(0, 0, 0.6)))
			game._update_spot()
			if String(game.spot.get("venue_spot", "")) != String(sp[0]):
				bad.append("%s→%s (hero %s, spot %s)" % [sp[0], game.spot.get("venue_spot", game.spot.get("kind", "none")), p.global_position.snapped(Vector3.ONE * 0.01), q.snapped(Vector3.ONE * 0.01)])
		check(bad.is_empty(), "%s: every walk-up point offers its prompt (%d points; %s)" % [id, (R["spots"] as Array).size(), str(bad)])
		var cars_in := 0
		for key: String in R["cars"]:
			var c: Car = game.skyport_play.displays.get(key)
			if c and v.ceiling_at(c.global_position + Vector3.UP) < INF:
				cars_in += 1
		check(cars_in == (R["cars"] as Array).size(), "%s: %d display cars, all inside" % [id, cars_in])
		await stand(inside)
		await until(func(): return p.is_on_floor(), 5.0)
		p.bot = w
		var b: Dictionary = {}
		for wp: Vector3 in [Vector3(ax, 0, -1.1), Vector3(dx, 0, -0.9), Vector3(dx, 0, 5.0)]:
			b = await _walk_to(w, xf * wp, 20.0)
			if not b["ok"]:
				break
		check(b["ok"], "%s: walked back out (%s)" % [id, b.get("at", "%.1fs" % b["t"])])
		p.bot = null


## `--sc-film=<dir>`: saves what the player sees now as <dir>/<tag>.png.
func _film(tag: String) -> void:
	if not game.args.has("sc-film"):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [String(game.args["sc-film"]), tag])


## Drives a craft with scripted controls until cond (or timeout).
func _fly(c: Craft, inp: Dictionary, cond: Callable, secs: float) -> bool:
	game.skyport_play.script_input = inp
	var ok := await until(cond, secs)
	return ok


## XK: a helicopter – buy, take off, climb, fly, turn, descend, land, get
## out, save and reload: it's where you left it.
func scenario_xk() -> void:
	print("--- XK: helicopter")
	var sp: SkyportPlay = game.skyport_play
	game.empire.personal_cash = 300000.0
	var err := sp.buy("wren")
	check(err == "", "bought a Wren on the helipad (%s)" % err)
	var vid := String(game.empire.vehicles[-1]["id"])
	var c: Craft = sp.crafts[vid]
	sp.enter(vid)
	await frames(3)
	var p0 := c.global_position
	check(await _fly(c, {"active": true, "gas": 0.0, "kick": true, "brake": 0.0, "steer": 0.0}, func(): return c.state == "flying" and c.altitude > 25.0, 90.0),
		"took off and climbed (%.0f m)" % c.altitude)
	check((c.get_node("Audio") as AudioStreamPlayer3D).playing, "the rotors are heard while you fly")
	await _film("craft_wren")
	var y0 := c._yaw
	check(await _fly(c, {"active": true, "gas": 1.0, "kick": false, "brake": 0.0, "steer": 0.6}, func(): return Vector2(c.global_position.x - p0.x, c.global_position.z - p0.z).length() > 120.0, 120.0),
		"flew forward and turned (%.0f m)" % Vector2(c.global_position.x - p0.x, c.global_position.z - p0.z).length())
	check(absf(wrapf(c._yaw - y0, -PI, PI)) > 0.3, "the yaw follows the stick")
	await _fly(c, {"active": false, "gas": 0.0, "kick": false, "brake": 0.0, "steer": 0.0}, func(): return c.speed < 2.0, 40.0)
	check(c.speed < 2.5 and c.state == "flying", "let go: it hovers (%.1f m/s)" % c.speed)
	check(await _fly(c, {"active": true, "gas": 0.0, "kick": false, "brake": 1.0, "steer": 0.0}, func(): return c.state == "landed", 150.0),
		"descended and landed (%s, %.1f m)" % [c.state, c.altitude])
	sp.script_input = {}
	var where := c.global_position
	check(sp.exit() == "", "got out")
	game.save_game()
	game.load_game()
	await frames(10)
	var c2: Craft = sp.crafts.get(vid)
	check(c2 != null and c2.global_position.distance_to(where) < 3.0, "after a reload it's where it landed")
	var n := 0
	for v in game.empire.vehicles:
		if String(v["id"]) == vid:
			n += 1
	check(n == 1, "exactly one record (no duplicates)")


## XP: a plane – from the runway threshold: takeoff roll, rotate, climb,
## descend onto the runway, roll out, brake, get out.
func scenario_xp() -> void:
	print("--- XP: plane")
	var sp: SkyportPlay = game.skyport_play
	game.empire.personal_cash = 300000.0
	check(sp.buy("skylark") == "", "bought a Skylark (on a stand)")
	var vid := String(game.empire.vehicles[-1]["id"])
	var c: Craft = sp.crafts[vid]
	var rw: Dictionary = SkyportIsland.RUNWAY
	c.place(Transform3D(Basis(Vector3.UP, SkyportIsland.wyaw(-PI * 0.5)), SkyportIsland.w((rw["from"] as Vector3) + Vector3(30, 0.05, 0))))
	sp.enter(vid)
	await frames(3)
	check(await _fly(c, {"active": true, "gas": 1.0, "kick": true, "brake": 0.0, "steer": 0.0}, func(): return c.state == "air", 120.0),
		"takeoff roll and lift-off (%.0f m along)" % (SkyportIsland.l(c.global_position).x - (rw["from"] as Vector3).x))
	check(await _fly(c, {"active": true, "gas": 1.0, "kick": true, "brake": 0.0, "steer": 0.0}, func(): return c.altitude > 25.0, 60.0),
		"climbing (%.0f m)" % c.altitude)
	await _film("craft_skylark")
	if c._gear:   # (the Skylark's gear is fixed, in spats)
		check(await _fly(c, {"active": true, "gas": 1.0, "kick": true, "brake": 0.0, "steer": 0.0}, func(): return c.gear_down < 0.05, 40.0),
			"the gear folds away in the climb (%.2f)" % c.gear_down)
	else:
		await _fly(c, {"active": true, "gas": 1.0, "kick": true, "brake": 0.0, "steer": 0.0}, func(): return c.altitude > 40.0, 40.0)
	check(await _fly(c, {"active": true, "gas": 0.0, "kick": false, "brake": 1.0, "steer": 0.0}, func(): return c.state in ["landing_roll", "taxi", "parked"], 120.0),
		"descended and touched down (%s at %.0f m along)" % [c.state, SkyportIsland.l(c.global_position).x - (rw["from"] as Vector3).x])
	check(SkyportIsland.contains(c.global_position.x, c.global_position.z), "on the island, not in the sea")
	check(await _fly(c, {"active": false, "gas": 0.0, "kick": false, "brake": 1.0, "steer": 0.0}, func(): return c.speed < 1.0, 90.0),
		"braked to a stop (%.1f m/s)" % c.speed)
	check(c.gear_down > 0.95, "the gear is down after landing (%.2f)" % c.gear_down)
	sp.script_input = {}
	check(sp.exit() == "", "got out on the ground")


## XF: flight edge cases (quality audit 2026-11-18). A save made in flight
## (the 90 s autosave, or iOS closing the app) used to keep the craft and
## you in mid-air – the helicopter reloaded hovering, frozen, at height;
## a plane that crashed froze where it hit and could never be left.
func scenario_xf() -> void:
	print("--- XF: flight saves and crashes")
	var sp: SkyportPlay = game.skyport_play
	game.empire.personal_cash = 600000.0
	check(sp.buy("wren") == "", "bought a Wren")
	var vid := String(game.empire.vehicles[-1]["id"])
	var c: Craft = sp.crafts[vid]
	var pad := c.global_position
	sp.enter(vid)
	await frames(3)
	check(await _fly(c, {"active": true, "gas": 0.0, "kick": true, "brake": 0.0, "steer": 0.0}, func(): return c.altitude > 40.0, 90.0),
		"climbing (%.0f m)" % c.altitude)
	game.save_game()   # (as the autosave would, in the air)
	sp.script_input = {}
	game.load_game()
	await frames(20)
	var c2: Craft = sp.crafts.get(vid)
	check(c2 != null and c2.global_position.distance_to(pad) < 3.0, "reloaded: the helicopter is back on its pad (%.0f m away)" % (c2.global_position.distance_to(pad) if c2 else -1.0))
	var pg := game.player.global_position
	check(pg.distance_to(pad) < 12.0 and absf(pg.y - pad.y) < 3.0, "and you're standing beside it (%.1f m off, %.1f m up)" % [pg.distance_to(pad), pg.y - pad.y])
	# A plane that crashes is recovered and can be left again.
	check(sp.buy("skylark") == "", "bought a Skylark")
	var pid := String(game.empire.vehicles[-1]["id"])
	var pl: Craft = sp.crafts[pid]
	var stand := pl.global_position
	sp.enter(pid)
	await frames(3)
	pl.global_position += Vector3(0, 60, 0)
	pl.state = "air"
	pl._crash()
	var cash := game.empire.personal_cash + game.empire.company_cash
	check(await until(func(): return pl.state != "crashed", 15.0), "the wreck is recovered (%s)" % pl.state)
	check(pl.global_position.distance_to(stand) < 3.0, "back where it last stood (%.0f m away)" % pl.global_position.distance_to(stand))
	check(game.empire.personal_cash + game.empire.company_cash < cash, "the recovery was paid for")
	check(sp.exit() == "", "and you can get out")
	# A car on its roof is put back on its wheels (it stayed upside down).
	var vid2 := String(game.empire.vehicles[0]["id"])
	var car: Car = game.cars[vid2]
	game.enter_vehicle(vid2)
	await frames(5)
	car.place(Transform3D(Basis(Vector3.FORWARD, PI), car.global_position + Vector3.UP * 1.5))
	check(await until(func(): return car.global_basis.y.dot(Vector3.UP) > 0.9 and car.upside_time == 0.0, 12.0),
		"a flipped car is back on its wheels (up·y %.2f)" % car.global_basis.y.dot(Vector3.UP))
	game.exit_vehicle()


## U: "Stuck? Back to the street" (quality audit 2026-11-18). Puts you, then
## your car, inside a big building near the start (as a glitch through a
## wall would) and checks the escape lands you outside it, by a road, on
## the ground – and the car on a lane, upright, able to drive off.
func scenario_u() -> void:
	print("--- U: stuck recovery")
	await until(func(): return game.gps.ready_net(), 60.0)
	var start := game.starter_unit()
	var sp := Premises.door_point(start)
	var pick := {}
	var best := INF
	for b: Dictionary in game.layout.buildings:
		if String(b.get("kind", "")) in ["invisible", "structure"]:
			continue
		var t: Array = b["tiers"][0]
		if float(t[2]) - float(t[0]) < 24.0 or float(t[3]) - float(t[1]) < 24.0:
			continue
		var c := CityLayout.bxf(b) * Vector3((float(t[0]) + float(t[2])) * 0.5, 0.0, (float(t[1]) + float(t[3])) * 0.5)
		var d := Vector2(c.x - sp.x, c.z - sp.z).length()
		if d < best:
			best = d
			pick = {"b": b, "c": c, "t": t}
	check(not pick.is_empty(), "a big building near the start (%.0f m)" % best)
	var inside := func(p: Vector3) -> bool:
		var l := CityLayout.bxf(pick["b"]).affine_inverse() * p
		var t: Array = pick["t"]
		return l.x > float(t[0]) + 0.3 and l.x < float(t[2]) - 0.3 and l.z > float(t[1]) + 0.3 and l.z < float(t[3]) - 0.3
	var c: Vector3 = pick["c"]
	var gy := game.layout.ground_y(c.x, c.z)
	game._teleport(Vector3(c.x, gy + 1.0, c.z), 0.0)
	await frames(10)
	check(inside.call(game.player.global_position), "you're wedged inside it")
	check(game.unstick() == "", "Back to the street")
	await wait(1.5)
	var pg := game.player.global_position
	var lane := game.gps.net.nearest(pg, Vector3.ZERO, 12.0, -1, true)
	check(not inside.call(pg), "you're out of the building")
	check(not lane.is_empty(), "beside a road (%.1f m from a lane)" % (float(lane["dist"]) if not lane.is_empty() else -1.0))
	check(game.player.is_on_floor() and absf(pg.y - game.layout.ground_y(pg.x, pg.z)) < 2.5, "standing on the ground (%.1f m up)" % (pg.y - game.layout.ground_y(pg.x, pg.z)))
	# The car, jammed into the same building.
	var vid := String(game.empire.vehicles[0]["id"])
	var car: Car = game.cars[vid]
	game.enter_vehicle(vid)
	await frames(5)
	car.place(Transform3D(Basis(), Vector3(c.x, gy + 0.6, c.z)))
	await frames(10)
	check(game.unstick() == "", "car: Back to the street")
	await wait(1.0)
	var cp := car.global_position
	var cl := game.gps.net.nearest(cp, Vector3.ZERO, 4.0, -1, true)
	check(not inside.call(cp) and not cl.is_empty(), "the car is on a lane (%.1f m)" % (float(cl["dist"]) if not cl.is_empty() else -1.0))
	check(car.global_basis.y.dot(Vector3.UP) > 0.95, "upright")
	game.drive_input.enabled = false
	var p0 := car.global_position
	for _i in 240:   # (4 s of physics; wall-clock is ~3 fps under xvfb)
		car.throttle = 0.7
		car.brake = 0.0
		car.steer = 0.0
		await get_tree().physics_frame
	car.throttle = 0.0
	game.drive_input.enabled = true
	check(car.global_position.distance_to(p0) > 4.0, "and drives off (%.1f m)" % car.global_position.distance_to(p0))
	game.exit_vehicle()


## L: a long session's resources (quality audit 2026-11-18). Tours eight
## places across the three islands three times, staying ~8 s at each so
## chunks, interiors, crowds and traffic stream in and out; after every lap
## prints nodes, orphan nodes, objects, static and video memory. A leak
## shows as growth from lap to lap (the first lap warms the caches).
## `--sc-laps=N` for longer soaks.
func scenario_l() -> void:
	print("--- L: soak")
	var spots := [Vector2(-800, 0), Vector2(470, -195), Vector2(250, 600), Vector2(-376, 1493),
		Vector2(124, 1148), Vector2(-560, 458), Vector2(524, 672), Vector2(600, 0)]
	var laps := int(game.args.get("sc-laps", "3"))
	var rows: Array = []
	for lap in laps:
		for sp: Vector2 in spots:
			game._teleport(Vector3(sp.x, game.layout.ground_y(sp.x, sp.y) + 1.0, sp.y), 0.0)
			await wait(8.0)
		var start := game.starter_unit()
		game._teleport(Premises.door_point(start) + Premises.outward(start) * 3.0 + Vector3.UP, 0.0)
		await wait(8.0)
		var r := {"lap": lap, "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
			"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			"static_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
			"video_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
			"interiors": game.interiors.size()}
		rows.append(r)
		print("SOAK ", JSON.stringify(r))
	if rows.size() >= 3:
		var a: Dictionary = rows[1]
		var b: Dictionary = rows[-1]
		var per := float(rows.size() - 2)
		check(float(b["nodes"]) - float(a["nodes"]) < 400.0 * per, "nodes steady after warm-up (%d → %d)" % [int(a["nodes"]), int(b["nodes"])])
		check(float(b["orphans"]) - float(a["orphans"]) < 50.0 * per, "no orphan nodes piling up (%d → %d)" % [int(a["orphans"]), int(b["orphans"])])
		check(float(b["static_mb"]) - float(a["static_mb"]) < 40.0 * per, "memory steady (%.0f → %.0f MB)" % [float(a["static_mb"]), float(b["static_mb"])])
		check(float(b["video_mb"]) - float(a["video_mb"]) < 60.0 * per, "GPU memory steady (%.0f → %.0f MB)" % [float(a["video_mb"]), float(b["video_mb"])])


## XG: a boat – buy at the marina, sail out, turn, stop, step off onto a pier.
func scenario_xg() -> void:
	print("--- XG: boat")
	var sp: SkyportPlay = game.skyport_play
	game.empire.personal_cash = 100000.0
	check(sp.buy("dart") == "", "bought a Dart (in a berth)")
	var vid := String(game.empire.vehicles[-1]["id"])
	var c: Craft = sp.crafts[vid]
	sp.enter(vid)
	await frames(3)
	var p0 := c.global_position
	check(await _fly(c, {"active": true, "gas": 1.0, "kick": false, "brake": 0.0, "steer": 0.3}, func(): return c.global_position.distance_to(p0) > 60.0, 120.0),
		"under way (%.0f m)" % c.global_position.distance_to(p0))
	check(absf(c.global_position.y - Craft.SEA_Y) < 0.6, "floating at sea level (%.2f)" % c.global_position.y)
	await _film("craft_dart")
	check(await _fly(c, {"active": true, "gas": 0.0, "kick": false, "brake": 1.0, "steer": 0.0}, func(): return absf(c.forward_speed) < 0.6, 60.0),
		"slowed to a stop")
	# Docking: drift in slowly near a free berth, hands off: it lines up.
	var bth: Array = c.berths[1]
	c.place(Transform3D(Basis(Vector3.UP, float(bth[1]) + 0.4), (bth[0] as Vector3) + Vector3(6.0, 0.0, 3.0)))
	check(await _fly(c, {"active": false, "gas": 0.0, "kick": false, "brake": 0.0, "steer": 0.0}, func(): return c.moored_at >= 0, 60.0),
		"eased into the berth and moored (%s)" % c.hud_text())
	sp.script_input = {}
	check(sp.exit() == "", "stepped off")
	check(not game.layout.is_water(game.player.global_position) or game.player.global_position.y > 0.3, "onto a pier or dry land (y %.1f)" % game.player.global_position.y)


## XH: airport imports into a shop: paid once, goods arrive in the stockroom.
func scenario_xh() -> void:
	print("--- XH: imports")
	var e := game.empire
	if e.businesses.is_empty():
		e.personal_cash = 6000.0
		game.rent_unit(game.starter_unit())
	var b: Business = e.businesses[0]
	e.personal_cash = 10000.0
	var pid: String = b.sellable()[0]
	var lines := {pid: 8}
	var q := Ventures.import_quote(e, lines, "express")
	var cash := e.personal_cash + e.company_cash
	var in_shop := func() -> int:
		var n := b.backroom.qty(pid) + b.floor_pile.qty(pid)
		for sl: Dictionary in b.slots:
			if String(sl["product"]) == pid:
				n += int(sl["qty"])
		return n
	var units0: int = in_shop.call()
	var bought0 := int(e.stats.get("units_bought", 0))
	check(Ventures.import_order(e, b.id, lines, "express") == "", "ordered 8 cases by express")
	check(absf(cash - (e.personal_cash + e.company_cash) - float(q["total"])) < 0.01, "paid the quote once (%s)" % EmpireData.money(float(q["total"])))
	e.advance(1440.0)
	# (A day passes before it lands: shoppers buy some, some walk out of the
	# door. What counts is that every case was received into the shop.)
	var received := int(e.stats.get("units_bought", 0)) - bought0
	check(received == 8 * EmpireData.case_qty(pid) and (in_shop.call() as int) > units0, "received in the shop's stock (%d units of %d)" % [received, 8 * EmpireData.case_qty(pid)])
	check(Ventures.imports_due(e).is_empty(), "nothing left in transit")


## XI: property – buy flats, set the rent, a week passes: tenants move in,
## rent is booked once a day, upkeep paid, valuation follows.
func scenario_xi() -> void:
	print("--- XI: property portfolio")
	var e := game.empire
	e.personal_cash = 2000000.0
	check(Ventures.buy_estate(e, "marina_quay") == "", "bought Marina Quay Apartments")
	check(Ventures.buy_estate(e, "marina_quay") != "", "can't buy it twice")
	Ventures.set_rent(e, "marina_quay", 0.85)
	var n0 := e.ledger.filter(func(l): return String(l.get("memo", "")).begins_with("Rent: Marina")).size()
	for i in 7:
		e.end_day()
	var st: Dictionary = e.flags["estates"]["marina_quay"]
	var n1 := e.ledger.filter(func(l): return String(l.get("memo", "")).begins_with("Rent: Marina")).size()
	check(float(st["occ"]) > 0.6, "tenants moved in (%d%% let)" % int(float(st["occ"]) * 100.0))
	check(n1 - n0 == 7, "rent booked once a day (%d entries in 7 days)" % (n1 - n0))
	check(Ventures.renovate(e, "marina_quay") == "" and float(st["cond"]) == 1.0, "renovated")
	check(Ventures.valuation(e, "marina_quay") > 300000.0, "valued (%s)" % EmpireData.money(Ventures.valuation(e, "marina_quay")))


## XS: the island is in the world: land collision, buildings, the map.
func scenario_xs() -> void:
	print("--- XS: Skyport Island in the world")
	var P: Dictionary = game.skyport.plan_data
	# Streaming: away from the island its detail isn't loaded; on it, it is.
	game.ui.close_panel(true)   # (earlier days left a day report open: panels pause the world)
	game._teleport(Vector3(500, game.layout.ground_y(500, -400) + 1.0, -400), 0.0)   # (the city's north side: well away)
	await until(func(): return game.skyport.near_root == null, 40.0)
	if game.skyport.near_root != null:
		print("    paused=%s driving=%s piloting=%s viewer=%s d=%.0f" % [get_tree().paused, game.driving, game.skyport_play.piloting,
			game.skyport.viewer.call(), SkyportIsland.distance_to(game.skyport.viewer.call())])
	check(game.skyport.near_root == null, "in the city the island's detail isn't loaded")
	game._teleport(SkyportIsland.w(Vector3(1700, SkyportIsland.LAND_Y + 1.0, -20)), 0.0)
	await until(func(): return game.skyport.near_loaded(), 60.0)
	check(game.skyport.near_loaded(), "arriving on the island loads its detail")
	check((P["buildings"] as Array).size() > 30, "buildings on the island (%d)" % (P["buildings"] as Array).size())
	var space := game.get_world_3d().direct_space_state
	var holes := 0
	for lx in range(1420, 2440, 40):
		for lz in range(-340, 560, 40):
			var wp := SkyportIsland.w(Vector3(lx, 0, lz))
			var x := wp.x
			var z := wp.z
			if not (SkyportIsland.contains(x - 3, z - 3) and SkyportIsland.contains(x + 3, z + 3) and SkyportIsland.contains(x - 3, z + 3) and SkyportIsland.contains(x + 3, z - 3)):
				continue   # (samples on the shoreline itself)
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400, z), Vector3(x, -20, z), 1 | (1 << 3))
			var hit := space.intersect_ray(q)
			if hit.is_empty() or (hit["position"] as Vector3).y < SkyportIsland.LAND_Y - 0.5:
				holes += 1
				print("    hole at ", x, ", ", z, " hit ", hit.get("position", "none"))
	check(holes == 0, "no holes in the island's collision (%d)" % holes)
	var rw: Dictionary = SkyportIsland.RUNWAY
	var bad := 0
	for x in range(int((rw["from"] as Vector3).x), int((rw["to"] as Vector3).x), 25):
		for dz: float in [-20.0, 0.0, 20.0]:
			var rp := SkyportIsland.w(Vector3(x, 0, 470 + dz))
			var q2 := PhysicsRayQueryParameters3D.create(Vector3(rp.x, 50, rp.z), Vector3(rp.x, -5, rp.z), 1 | (1 << 3))
			var h2 := space.intersect_ray(q2)
			if h2.is_empty() or absf((h2["position"] as Vector3).y - SkyportIsland.LAND_Y) > 0.05:
				bad += 1
	check(bad == 0, "the runway is one continuous flat surface (%d bad samples)" % bad)
	check(not game.layout.is_water(SkyportIsland.w(Vector3(2000, 0, 0))) and game.layout.is_water(SkyportIsland.w(Vector3(1250, 0, 300))), "is_water knows the island")


func _run() -> void:
	await wait(1.0)
	game.gps.wait_net()
	var t0 := Time.get_ticks_msec()
	if want("A"):
		await scenario_a()
	if want("E"):
		await scenario_e()
	if want("D"):
		await scenario_d()
	if want("C"):
		await scenario_c()
	if want("F"):
		await scenario_f()
	if want("G"):
		await scenario_g()
	if want("H"):
		await scenario_h()
	if want("P"):
		await scenario_p()
	if _which.split(",").has("B"):
		await scenario_b()
	for k in ["XO", "XA", "XV", "XN", "XD", "XR", "XB", "XC", "XK", "XP", "XF", "XG", "XH", "XI", "XS", "XW"]:
		if _which.split(",").has(k) or _which.split(",").has("X"):
			await call("scenario_" + k.to_lower())
	if _which.split(",").has("U"):
		await scenario_u()
	if _which.split(",").has("L"):
		await scenario_l()
	if _which.split(",").has("W"):
		await scenario_w()
	if _which.split(",").has("V"):
		await scenario_v()
	if _which.split(",").has("S"):
		# The Style screen as a new player meets it (`--sc-film=<png>`): the
		# welcome, LET'S GO, then the editor with the hero idling in it.
		game.empire.flags.erase("styled")
		game.ui.intro()
		await frames(3)
		for b in game.ui.find_children("*", "Button", true, false):
			if (b as Button).text == "LET'S GO":
				(b as Button).pressed.emit()
				break
		await until(func(): return game.ui.panel_open(), 5.0)
		await wait(2.0)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(game.args.get("sc-film", "user://style.png")))
	print("SCENARIO DONE %d/%d passed in %.0f s" % [checks - fails, checks, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(fails)


# ---------------------------------------------- A: a new player's first steps
func scenario_a() -> void:
	print("--- A: onboarding from a fresh save")
	var e := game.empire
	var ob := game.objective()
	check(String(ob[0]).begins_with("Find your car") or e.flags.get("seen_car", false),
		"step 1 is finding the car – already ticked off: it's beside you (%s)" % ob[0])
	var vid: String = e.vehicles[0]["id"]
	await until(func(): return e.flags.get("seen_car", false) or game.gps.points.size() >= 2, 15.0)
	# (You start beside it, so this one ticks off almost at once.)
	print("  (car %.1f m away; gps active=%s msg=%s)" % [game.player.global_position.distance_to(game.vehicle_position(vid)), game.gps.active(), game.gps.message])
	check(e.flags.get("seen_car", false) or (game.gps.active() and game.gps.points.size() >= 2),
		"the car is found (it's right beside you), or routed to (%d points)" % game.gps.points.size())
	await stand(game.vehicle_position(vid) + Vector3(3.0, 0, 0))
	await wait(0.6)
	check(e.flags.get("seen_car", false), "walking up to the car ticks it off")
	check(String(game.objective()[3]) == "map", "next: open the map (%s)" % game.objective()[0])
	game.ui.objective_action()
	await frames(3)
	check(game.ui.panel_open() and e.flags.get("opened_map", false), "tapping the objective opens the map")
	game.ui.close_panel(true)
	check(String(game.objective()[0]).begins_with("Inspect"), "next: inspect a shop (%s)" % game.objective()[0])
	var start := game.starter_unit()
	await until(func(): return game.gps.active() and game.gps.dest.distance_to(Premises.door_point(start)) < 3.0, 15.0)
	check(game.gps.active() and game.gps.dest.distance_to(Premises.door_point(start)) < 3.0, "the GPS now leads to the shop to let")
	game.ui.open_property(start, true)
	await frames(2)
	game.ui.close_panel(true)
	check(String(game.objective()[0]).begins_with("Rent"), "inspected → next: rent it (%s)" % game.objective()[0])
	var cash := e.personal_cash
	await stand(door_out(start, 1.9))
	check(game.spot.get("kind") == "letboard", "TO LET board prompt at the door")
	check(game.rent_unit(start) == "", "rented at the door")
	check(is_equal_approx(cash - e.personal_cash, float(start["rent"]) * 3.0), "paid the deposit only (no agent fee in person)")
	check(String(game.objective()[0]).begins_with("Drive to"), "next: buy stock (%s)" % game.objective()[0])
	var w := game.wholesaler("west")
	await until(func(): return game.gps.active() and game.gps.dest.distance_to(Premises.door_point(w)) < 3.0, 15.0)
	check(game.gps.active() and game.gps.dest.distance_to(Premises.door_point(w)) < 3.0, "the route now goes to the cash & carry (dest %s, %s, %s)" % [
		game.gps.dest, game.gps.label, game.gps.message])


# ------------------------------------------------------------- E: GPS
func scenario_e() -> void:
	print("--- E: GPS route, both maps, rerouting, car and foot")
	var e := game.empire
	var start := game.starter_unit()
	var w := game.wholesaler("east")
	await stand(door_out(start))
	game.set_gps(Premises.door_point(w), String(w["name"]), {"kind": "unit", "id": String(w["id"])})
	var gps := game.gps
	check(gps.active() and gps.points.size() >= 3 and gps.message == "", "route planned to %s (%d points, %s)" % [w["name"], gps.points.size(), gps.distance_text()])
	var len0 := gps.remaining
	check(len0 > game.player.global_position.distance_to(gps.dest), "route is longer than the straight line (%.0f m)" % len0)
	# Both maps draw the same route.
	await wait(0.4)
	var mini_route: PackedVector3Array = game.ui.minimap.drawn_route
	game.ui.open_phone("map")
	await frames(4)
	var maps := game.ui.find_children("*", "EmpireMap", true, false)
	check(maps.size() == 1, "the full map is open")
	if maps.size() == 1:
		var m: EmpireMap = maps[0]
		m.queue_redraw()
		await frames(3)
		check(m.drawn_route.size() >= 2 and m.drawn_route.size() == mini_route.size(),
			"minimap and full map drew the same route (%d / %d points)" % [mini_route.size(), m.drawn_route.size()])
		var same := m.drawn_route.size() == mini_route.size()
		for i in range(1, mini_route.size()):
			if same and mini_route[i].distance_to(m.drawn_route[i]) > 0.01:
				same = false
		check(same, "…point for point")
	game.ui.close_panel(true)
	# Follow the route part way: progress and distance go down. (A point on
	# a street, not out on a bridge: with the three islands joined up the
	# route may cross Skyport.)
	var mid := gps.points[gps.points.size() / 3]
	for frac: float in [0.33, 0.25, 0.45, 0.2, 0.55, 0.65]:
		var c := gps.points[int(gps.points.size() * frac)]
		if not game.layout.is_water(c) and is_nan(SkyportIsland.bridge_road_y(game.layout, c.x, c.z)) and not SkyportIsland.contains(c.x, c.z):
			mid = c
			break
	await stand(mid)
	await wait(0.8)
	check(gps.remaining < len0 * 0.85 and gps.progress_i > 0, "following it: %.0f m left (was %.0f)" % [gps.remaining, len0])
	# A wrong turn: well off the route → it re-plans from where you are.
	var r0 := gps.reroutes
	var i := gps.progress_i
	var a := gps.points[i]
	var b := gps.points[mini(i + 1, gps.points.size() - 1)]
	var side := Vector3(-(b - a).z, 0, (b - a).x).normalized()
	var off := Vector3.INF
	# A street well away from every part of the route (a real wrong turn).
	var probes: Array = []
	for dist: float in [70.0, -70.0, 110.0, -110.0, 160.0, -160.0]:
		probes.append(mid + side * dist)
	for dist2: float in [90.0, 140.0, 200.0]:
		for k in 16:
			probes.append(mid + Vector3(cos(k * TAU / 16.0), 0.0, sin(k * TAU / 16.0)) * dist2)
	for p: Vector3 in probes:
		var near := gps.net.nearest(p, Vector3.ZERO, 12.0)
		if near.is_empty() or game.layout.is_water(p):
			continue
		var md0 := INF
		for q in gps.points:
			md0 = minf(md0, Vector2(q.x - near["pos"].x, q.z - near["pos"].z).length())
		if md0 > 40.0:
			off = near["pos"]
			break
	if off != Vector3.INF:
		var md := INF
		for q in gps.points:
			md = minf(md, Vector2(q.x - off.x, q.z - off.z).length())
		print("  (off-route test point %.0f m from the route)" % md)
		await stand(off)
		# (Planned on a worker thread: wait for the new route to land.)
		await until(func(): return gps.reroutes > r0 and gps.points.size() >= 2 \
			and Vector2(gps.points[0].x - off.x, gps.points[0].z - off.z).length() < 6.0, 25.0)
		check(gps.reroutes > r0, "wrong turn → rerouted (%d)" % gps.reroutes)
		check(gps.points.size() >= 2 and Vector2(gps.points[0].x - off.x, gps.points[0].z - off.z).length() < 6.0,
			"the new route starts where you are")
	else:
		check(false, "found a street off the route to test rerouting")
	# Get in the car: the route is re-planned for driving (one-way lanes).
	var vid: String = e.vehicles[0]["id"]
	var car: Car = game.cars[vid]
	await stand(game.player.global_position)
	var cp := game.player.global_position + Vector3(4, 0, 0)
	car.place(Transform3D(Basis(), game._kerb_point(cp) + Vector3.UP * 0.3))
	await frames(10)
	game.enter_vehicle(vid)
	await until(func(): return gps.mode == "drive", 25.0)
	check(game.driving == vid and gps.mode == "drive", "in the car: route mode %s" % gps.mode)
	game.exit_vehicle()
	await until(func(): return gps.mode == "walk", 25.0)
	check(game.driving == "" and gps.mode == "walk", "out again: route mode %s" % gps.mode)
	# Arrive: the route clears itself.
	await stand(door_out(w, 2.0))
	await until(func(): return not gps.active(), 15.0)
	check(not gps.active(), "arrived: route cleared")
	# Unreachable destinations say why and draw nothing.
	game.set_gps(Vector3(-150, 0, -1400), "Out at sea", {"kind": "point"})
	await frames(2)
	check(gps.message != "" and gps.points.is_empty(), "a place you can't reach: %s" % gps.message)
	game.clear_gps()


# ------------------------------------------------------------- D: the car
func scenario_d() -> void:
	print("--- D: where's my car? find it, have it brought round")
	var e := game.empire
	var vid: String = e.vehicles[0]["id"]
	var start := game.starter_unit()
	var car_p := game.vehicle_position(vid)
	# Walk off somewhere far (a few hundred metres: another shop's door).
	var far := {}
	for u in game.units:
		var d := Premises.door_point(u).distance_to(car_p)
		if u["island"] == "west" and d > 350.0 and d < 900.0:
			far = u
			break
	await stand(door_out(far))
	var q := game.delivery_quote(vid)
	check(not q["ok"] or q["fee"] > 0.0, "a delivery quote (%s)" % (EmpireData.money(float(q["fee"])) if q["ok"] else q["why"]))
	game.ui.open_phone("vehicles")
	await frames(2)
	game.ui.find_vehicle(vid)
	await frames(2)
	game.ui.close_panel(true)
	check(game.gps.active() and String(game.gps.ref.get("kind", "")) == "vehicle" and game.gps.dest.distance_to(car_p) < 2.0,
		"Find sets the GPS to where the car really is")
	check(game.gps.points.size() >= 2, "…with a walking route (%s)" % game.gps.distance_text())
	e.personal_cash = maxf(e.personal_cash, 500.0)
	var cash := e.personal_cash + e.company_cash
	var err := game.deliver_vehicle(vid)
	check(err == "", "delivery booked (%s)" % err)
	var here0 := game.player.global_position
	await until(func(): return game.vehicle_position(vid).distance_to(here0) < 40.0, 30.0)
	var here := game.player.global_position
	var now := game.vehicle_position(vid)
	check(now.distance_to(here) < 40.0, "the car arrived on your street (%.0f m away)" % now.distance_to(here))
	check(absf((cash - (e.personal_cash + e.company_cash)) - float(q["fee"])) < 0.5, "charged the quoted fee once")
	var v := e.vehicle(vid)
	check(Vector3(v["pos"][0], v["pos"][1], v["pos"][2]).distance_to(now) < 2.0, "its parked position is saved")
	q = game.delivery_quote(vid)
	check(not q["ok"] and String(q["why"]).contains("walk"), "next to you, delivery is refused with a reason (%s)" % q["why"])
	await until(func(): return game.gps.dest.distance_to(game.vehicle_position(vid)) < 15.0 or not game.gps.active(), 10.0)
	check(game.gps.dest.distance_to(game.vehicle_position(vid)) < 15.0 or not game.gps.active(), "the GPS followed the car to its new spot")
	game.clear_gps()


# ---------------------------------------------- C + B: expansion, staff
func scenario_c() -> void:
	print("--- C/B: several shops, hired staff, away from them all")
	var e := game.empire
	e.personal_cash += 60000.0
	var picks: Array = []
	var seen := {}
	for u in game.units:
		if u["kind"] == "shop" and MapKit.unit_kind(game, u) == "to_let" and not seen.has(u["district"]):
			seen[u["district"]] = true
			picks.append(u)
		if picks.size() >= 3:
			break
	var n0 := e.businesses.size()
	for u in picks:
		var fee := EmpireGame.agent_fee(float(u["rent"]) * 3.0)
		var before := e.personal_cash + e.company_cash
		check(game.rent_unit(u, false, "convenience", fee) == "", "rented %s remotely (agent fee %s)" % [u["shop_name"], EmpireData.money(fee)])
		check(absf(before - (e.personal_cash + e.company_cash) - (float(u["rent"]) * 3.0 + fee)) < 0.5, "…paid deposit + fee once")
		check(game.rent_unit(u, false, "convenience", fee) != "", "…and can't rent the same unit twice")
	check(e.businesses.size() == n0 + 3, "%d businesses" % e.businesses.size())
	var ids := {}
	for b: Business in e.businesses:
		ids[String(b.premises["id"])] = true
	check(ids.size() == e.businesses.size(), "one business per unit")
	e.transfer_to_company(20000.0)
	var mine: Array = e.businesses.slice(n0)
	var orders := [{"crisps": 2, "cola": 2, "milk": 1}, {"water": 2, "choc_bar": 2}, {"bread": 2, "tea": 1}]
	for k in mine.size():
		var b: Business = mine[k]
		check(e.order_delivery(b, orders[k]) == "", "%s: ordered stock by phone" % b.name)
		var cs := e.candidates.filter(func(x): return x["role"] == "cashier")
		if cs.is_empty():
			e.candidates = Staff.candidates(e.day + 40 + k, e.seed + k)
			cs = e.candidates.filter(func(x): return x["role"] == "cashier")
		game.hire(mine[k], cs[0])
		var st := e.candidates.filter(func(x): return x["role"] == "stocker")
		if not st.is_empty() and k == 0:
			game.hire(mine[k], st[0])
	check(mine.all(func(b): return b.has_role("cashier")), "a cashier at each new shop")
	# Away from all of them (a wholesaler's yard), to the next morning and past noon.
	await stand(door_out(game.wholesaler("east"), 6.0))
	check(game.floor_unit == "", "nowhere near any of them (no live shop floor)")
	var wages0 := 0.0
	e.advance(fposmod(6.5 * 60.0 - e.minute, 1440.0))
	check(mine.all(func(b): return b.stock_units() > 0), "deliveries arrived overnight at every shop")
	for b: Business in mine:
		e.restock_from_backroom(b, 200)  # (opening up: the morning shelf fill)
	e.advance(6.0 * 60.0)
	for b: Business in mine:
		check(int(b.today["served"]) > 0, "%s traded while you were away (%d served, %s)" % [b.name, int(b.today["served"]), EmpireData.money(float(b.today["revenue"]))])
		wages0 += float(b.today["wages"])
	check(wages0 > 0.0, "wages accrue at every staffed shop (%.2f)" % wages0)
	var sold: Dictionary = mine[1].today["by_product"]
	check(not sold.has("cola") and not sold.has("bread"), "each shop sells only its own stock (%s)" % str(sold.keys()))
	# The portfolio shows them all; a card's buttons open the right shop.
	game.ui.open_phone("businesses")
	await frames(3)
	var labels := game.ui.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	check(mine.all(func(b): return labels.has(b.name)), "the portfolio lists every shop")
	game.ui.close_panel(true)
	e.advance(1440.0 - e.minute + 1.0)
	var co: Dictionary = e.day_reports[-1]
	var sum := 0.0
	for b: Business in e.businesses:
		sum += float(b.history[-1]["profit"])
	check(absf(float(co["profit"]) - sum) < 1.0 or e.loans.size() > 0 or e.hq_tier() > 0,
		"company profit %.2f = the shops' %.2f" % [float(co["profit"]), sum])


# --------------------------------------------- F: commercial units in the world
func scenario_f() -> void:
	print("--- F: shops across the city: one each, at street level, stable")
	var by_d := {}
	for u in game.units:
		var k := String(u["district"])
		if not by_d.has(k):
			by_d[k] = []
		(by_d[k] as Array).append(u)
	var sample: Array = []
	for k in by_d:
		var list: Array = by_d[k]
		sample.append(list[0])
		sample.append(list[list.size() / 2])
	var bad: Array = []
	for pass_i in 2:
		for u in sample:
			await stand(door_out(u, 4.0))
			game._stream_interiors()
			await frames(2)
			var si: ShopInterior = game.interiors.get(u["id"])
			if si == null:
				bad.append("%s: no interior" % u["id"])
				continue
			var floor_y := si.global_position.y
			var street := game.layout.ground_y(Premises.door_point(u).x + Premises.outward(u).x * 2.0, Premises.door_point(u).z + Premises.outward(u).z * 2.0)
			if floor_y < street - 0.6 or floor_y > street + 1.6:
				bad.append("%s: floor %.2f vs street %.2f" % [u["id"], floor_y, street])
		# Every interior node in the scene is unique per unit.
		await frames(2)
		var names := {}
		for n in game.get_children():
			if n is ShopInterior and not n.is_queued_for_deletion():
				names[n.name] = int(names.get(n.name, 0)) + 1
		var dups := names.keys().filter(func(k): return int(names[k]) > 1)
		check(dups.is_empty(), "pass %d: no unit has two interiors (%d live, dups %s)" % [pass_i + 1, names.size(), str(dups)])
		check(names.size() == game.interiors.size(), "pass %d: scene interiors (%d) = tracked (%d)" % [pass_i + 1, names.size(), game.interiors.size()])
	check(bad.is_empty(), "%d sampled shops in %d districts at street level, twice over (%s)" % [sample.size(), by_d.size(), str(bad.slice(0, 3))])


# ------------------------------------------------------------- G: save/load
func scenario_g() -> void:
	print("--- G: save, reload, everything still there")
	var e := game.empire
	var w := game.wholesaler("west")
	game.set_gps(Premises.door_point(w), String(w["name"]), {"kind": "unit", "id": String(w["id"])})
	var vid: String = e.vehicles[0]["id"]
	var car_p := game.vehicle_position(vid)
	var snap := {"biz": e.businesses.map(func(b): return [b.id, b.premises["id"], b.staff.map(func(x): return x["id"]), b.stock_units()]),
		"personal": e.personal_cash, "company": e.company_cash, "day": e.day, "gps": game.gps.dest, "units": e.total_units()}
	game.save_game()
	game.load_game()
	await wait(0.6)
	var e2 := game.empire
	var biz2: Array = e2.businesses.map(func(b): return [b.id, b.premises["id"], b.staff.map(func(x): return x["id"]), b.stock_units()])
	check(str(biz2) == str(snap["biz"]), "businesses, their units, staff and stock reload exactly (%d shops)" % biz2.size())
	check(absf(e2.personal_cash - float(snap["personal"])) < 0.01 and absf(e2.company_cash - float(snap["company"])) < 0.01, "money reloads")
	check(e2.total_units() == int(snap["units"]), "every unit of stock reloads")
	check(game.vehicle_position(vid).distance_to(car_p) < 1.5, "the car is where it was parked (%.2f m)" % game.vehicle_position(vid).distance_to(car_p))
	check(game.gps.active() and game.gps.dest.distance_to(snap["gps"]) < 0.5 and game.gps.points.size() >= 2, "the GPS route is back")
	game.clear_gps()


# ------------------------------------------------------- H: things going wrong
func scenario_h() -> void:
	print("--- H: no money, no stock, nobody on the till, nowhere to go")
	var e := game.empire
	var saved := [e.personal_cash, e.company_cash]
	e.personal_cash = 0.0
	e.company_cash = 0.0
	var free := game.units.filter(func(u): return u["kind"] == "shop" and MapKit.unit_kind(game, u) == "to_let")
	check(game.rent_unit(free[0]) != "", "renting with no money says why: %s" % game.rent_unit(free[0]))
	var vid: String = e.vehicles[0]["id"]
	await stand(door_out(free[0]))
	var q := game.delivery_quote(vid)
	check(not q["ok"] and String(q["why"]) != "", "car delivery with no money (or nearby) says why: %s" % q["why"])
	e.personal_cash = saved[0] + 5000.0
	e.company_cash = saved[1]
	if e.businesses.is_empty():
		game.rent_unit(game.starter_unit())
	var b: Business = e.businesses[0]
	if not b.has_role("cashier"):
		var cs := e.candidates.filter(func(x): return x["role"] == "cashier")
		if not cs.is_empty():
			game.hire(b, cs[0])
	var st0 := b.status(10.0)
	for x in b.staff.duplicate():
		if x["role"] == "cashier":
			e.fire(b, x)
	check(b.status(11.0)[0] in ["no_cashier", "no_stock"], "no cashier: the shop shows it can't trade (%s)" % b.status(11.0)[1])
	var issues := game.ui.biz_issues(b)
	check(issues.any(func(i): return String(i[0]).contains("cashier") or String(i[0]).contains("stock")), "…and Home lists it with a fix (%s)" % (issues[0][0] if not issues.is_empty() else "none"))
	var al := game.ui.alerts()
	check(al.all(func(a): return String(a["btn"]) == "" or (a["cb"] as Callable).is_valid()), "every alert button has an action")
	game.set_gps(Vector3(-150, 0, -1400), "Sea", {"kind": "point"})
	check(game.gps.points.is_empty() and game.gps.message != "", "unreachable GPS: %s" % game.gps.message)
	game.clear_gps()
	check(not game.gps.active() and not e.flags.has("gps"), "Cancel route clears it (and the save)")
	print("(status before: %s)" % st0[1])


# ------------------------------------- P: walking into your parked car
## The hero walks (and runs) into the side of the parked car: it doesn't move,
## you stop against it, and it still drives once you're in.
func scenario_p() -> void:
	print("--- P: the hero and the parked car")
	var vid: String = game.empire.vehicles[0]["id"]
	var car: Car = game.cars[vid]
	await stand(car.global_position + car.global_basis.x * 4.0)
	await until(func(): return car.freeze, 10.0)
	check(car.freeze, "the parked car settles and locks (frozen=%s)" % car.freeze)
	var before := car.global_transform
	var w := _Walk.new()
	var p := game.player
	p.bot = w
	for amt: float in [0.65, 1.0]:
		await stand(car.global_position + car.global_basis.x * 4.0)
		p.bot = w
		w.amount = amt
		# (Aim at its middle: you can't get there, only up against the side.)
		await _walk_to(w, car.global_position, 5.0)
		var moved := car.global_position.distance_to(before.origin)
		var turned := rad_to_deg(car.global_basis.z.angle_to(before.basis.z))
		var side := absf((p.global_position - car.global_position).dot(car.global_basis.x))
		check(moved < 0.02 and turned < 0.5, "%s into the car: it moved %.3f m, turned %.2f°" % ["walking" if amt < 0.8 else "running", moved, turned])
		check(side > float(car.spec["size"].x) * 0.5, "%s: you stop against the side (%.2f m from its middle)" % ["walking" if amt < 0.8 else "running", side])
	p.bot = null
	game.enter_vehicle(vid)
	game.drive_input.enabled = false
	var x0 := car.global_position
	await until(func():
		car.throttle = 1.0
		car.brake = 0.0
		car.handbrake = false
		return car.global_position.distance_to(x0) > 3.0, 10.0)
	check(not car.freeze and car.global_position.distance_to(x0) > 3.0, "it drives off once you're in (%.1f m)" % car.global_position.distance_to(x0))
	car.throttle = 0.0
	await until(func():
		car.brake = 1.0
		return car.speed < 0.5, 10.0)
	game.drive_input.enabled = true
	game.exit_vehicle()


# ------------------------------------- W: walking in and out of every shop
## Not in the default set (it walks every unit: `--scenarios=W`, add
## `--sc-units=N` for a sample, `--sc-pace=0.45` for a stroll). The hero
## walks from the pavement through the door to the middle of the shop floor,
## then back out to the street, steered like a player holding the stick.
class _Walk:
	extends RefCounted
	var target := Vector3.ZERO
	var amount := 1.0
	var human_steer := true
	func drive(p: Player, _dt: float) -> Dictionary:
		var d := target - p.global_position
		d.y = 0.0
		var mv := d.normalized() * amount if d.length() > 0.25 else Vector3.ZERO
		return {"move": mv, "aim": mv if mv != Vector3.ZERO else Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


func _walk_to(w: _Walk, to: Vector3, secs: float) -> Dictionary:
	var p := game.player
	w.target = to
	var t := 0.0
	var stuck := 0.0
	var last := p.global_position
	var low := INF
	while t < secs:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var pos := p.global_position
		low = minf(low, pos.y)
		stuck = stuck + 1.0 / 60.0 if pos.distance_to(last) < 0.004 else 0.0
		last = pos
		if Vector2(pos.x - to.x, pos.z - to.z).length() < 0.45:
			return {"ok": true, "t": t, "low": low}
		if stuck > 1.5:
			break
	var hit := ""
	for k in p.get_slide_collision_count():
		var c := p.get_slide_collision(k)
		var o := c.get_collider() as Node
		hit += " [%s n=%s y=%.2f]" % [o.get_path() if o else "?", c.get_normal().snapped(Vector3.ONE * 0.01), c.get_position().y - p.global_position.y + 0.9]
	return {"ok": false, "t": t, "low": low, "at": "%s%s" % [p.global_position, hit]}


func scenario_w() -> void:
	print("--- W: walking in and out of shops")
	var p := game.player
	var w := _Walk.new()
	w.amount = float(game.args.get("sc-pace", "1.0"))
	var stag := [0]
	p.staggered.connect(func(sp, n):
		stag[0] += 1
		if game.args.has("sc-debug"):
			var hit := ""
			for k in p.get_slide_collision_count():
				var c := p.get_slide_collision(k)
				hit += " [%s at %s]" % [(c.get_collider() as Node).get_path() if c.get_collider() else "?", c.get_position()]
			for sid in game.interiors:
				var si2: ShopInterior = game.interiors[sid]
				var lq := si2.global_transform.affine_inverse() * p.global_position
				if lq.x > -2.0 and lq.x < si2.W + 2.0 and lq.z > -si2.D and lq.z < 4.0:
					hit += " room %s x=%.2f d=%.2f door=%s W=%.1f" % [sid, lq.x, -lq.z, si2.door, si2.W]
			print("    stagger %.1f m/s n=%s at %s%s" % [sp, n, p.global_position, hit]))
	var list: Array = []
	var only := String(game.args.get("sc-only", "")).split(",", false)
	for u in game.units:
		if String(u["kind"]) in ["shop", "wholesale"] and (only.is_empty() or String(u["id"]) in only):
			list.append(u)
	var n := int(game.args.get("sc-units", str(list.size())))
	var step := maxf(1.0, float(list.size()) / n)
	var bad := 0
	var done := 0
	var i := 0.0
	while int(i) < list.size():
		var u: Dictionary = list[int(i)]
		i += step
		var dp := Premises.door_point(u)
		var out := Premises.outward(u)
		# (`--sc-side=<m>`: start that far along the shopfront, to come at the door at an angle.)
		var street := dp + out * 3.0 + Premises.along_dir(u) * float(game.args.get("sc-side", "0"))
		street.y = float(game.layout.ground_y(street.x, street.z))
		await stand(street)
		p.bot = w
		await until(func(): return game.interiors.has(u["id"]), 5.0)
		await frames(2)
		var si: ShopInterior = game.interiors.get(u["id"])
		if si == null:
			print("  (no interior for %s)" % u["id"])
			continue
		var drop := si.street_drop
		# Stood on the street (its collision streamed in) before setting off.
		w.target = p.global_position
		await until(func(): return p.is_on_floor(), 5.0)
		await frames(10)
		if absf(p.global_position.y - 0.9 - street.y) > 1.5:
			print("  (no pavement at the start point for %s: landed %.1f m off it; skipped)" % [u["id"], p.global_position.y - 0.9 - street.y])
			p.bot = null
			continue
		if game.args.has("sc-debug"):
			var bb: Dictionary = u["b"]
			var fr := dp + out * 3.0
			print("  unit %s dp=%s base=%.2f tier0=%s ground(front)=%.2f lifted=%s keys=%s" % [u["id"], dp, BuildingMesher.base_of(bb),
				str(bb["tiers"][0]), game.layout.ground_y(fr.x, fr.z), bb.get("lift", "-"), bb.keys()])
		if absf(street.y - dp.y) > 2.0:
			street.y = dp.y - drop  # (a podium or deck the terrain doesn't know about)
		var inside := si.to_world(si.door_in + ShopInterior.R(0.0, 0.6, 0.0))
		var floor_y := si.global_transform.origin.y
		stag[0] = 0
		if game.args.has("sc-debug"):
			var l0 := si.global_transform.affine_inverse() * p.global_position
			print("    start x=%.2f d=%.2f  door=%s" % [l0.x, -l0.z, si.door])
		var a: Dictionary = await _walk_to(w, inside, 12.0)
		var in_y := p.global_position.y - 0.9 - floor_y
		var in_ok: bool = a["ok"] and absf(in_y) < 0.1 and si.contains(p.global_position)
		var b: Dictionary = await _walk_to(w, street + out * 0.5, 12.0)
		var out_ok: bool = b["ok"]
		var fell: bool = minf(a["low"], b["low"]) < minf(floor_y, street.y) + 0.9 - 0.5
		var good: bool = in_ok and out_ok and stag[0] == 0 and not fell
		done += 1
		if not good:
			bad += 1
		if not good or game.args.has("sc-debug"):
			print("  %s %s drop=%.2f dy=%.2f in=%s(%.1fs%s) out=%s(%.1fs%s) stag=%d fell=%s" % ["ok " if good else "BAD", u["id"], drop, in_y,
				in_ok, a["t"], "" if a["ok"] else " at %s" % a.get("at"), out_ok, b["t"], "" if b["ok"] else " at %s" % b.get("at"), stag[0], fell])
		p.bot = null
	check(bad == 0, "walked into and out of %d/%d shops without getting stuck, stumbling or falling" % [done - bad, done])


## Films one walk in and out (`--scenarios=V --sc-film=<dir> [--sc-only=<unit>]
## [--sc-pace=…]`, under xvfb): a frame every 0.2 s of game time, the
## camera as the player sees it.
func scenario_v() -> void:
	var dir := String(game.args.get("sc-film", "user://film"))
	var p := game.player
	var u: Dictionary = game.starter_unit()
	if game.args.has("sc-only"):
		u = game.unit_by_id[String(game.args["sc-only"])]
	var dp := Premises.door_point(u)
	var out := Premises.outward(u)
	var street := dp + out * 4.5 + Premises.along_dir(u) * 1.5
	street.y = float(game.layout.ground_y(street.x, street.z))
	await stand(street)
	await until(func(): return game.interiors.has(u["id"]), 5.0)
	var si: ShopInterior = game.interiors[u["id"]]
	p.rotation.y = atan2(-out.x, -out.z)
	game.camera.snap()
	await wait(1.0)
	var w := _Walk.new()
	w.amount = float(game.args.get("sc-pace", "1.0"))
	p.bot = w
	var legs := [si.to_world(si.door_in + ShopInterior.R(0.0, 1.4, 0.0)), dp + out * 4.0 - Premises.along_dir(u) * 1.5]
	var n := 0
	for leg: Vector3 in legs:
		w.target = leg
		var t := 0.0
		while t < 8.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			if Engine.get_physics_frames() % 12 == 0:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [dir, n])
				n += 1
			var d: Vector3 = leg - p.global_position
			if Vector2(d.x, d.z).length() < 0.45:
				break
		if leg == legs[0]:
			w.target = p.global_position
			for k in 30:
				await get_tree().physics_frame
	p.bot = null
	print("FILM %d frames in %s" % [n, dir])
