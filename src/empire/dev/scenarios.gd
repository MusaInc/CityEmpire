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
		# (An earlier scenario can leave the car moving: you can only get
		# out once it has stopped.)
		var dc: Car = game.cars[game.driving]
		dc.linear_velocity = Vector3.ZERO
		dc.angular_velocity = Vector3.ZERO
		await frames(3)
		game.exit_vehicle()
	check(game.driving == "", "on foot")
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


## RS: road-vehicle spawn reliability. Finds places where one road runs over
## another (bridge approaches, flyovers, viaducts), stands the hero on each
## level and asks SafeGround.road_spot where a delivered / bought car goes:
## it must land on the hero's own level, on solid dry ground, upright, with
## all four wheels down after settling. Also the middle of each bridge deck
## (over open water: never the sea). Then one real purchase through the game.
func scenario_rs() -> void:
	print("--- RS: vehicle spawn on the right level")
	var net: RoadNet = game.gps.net
	var buckets := {}
	var stacked: Array = []   # [upper Vector3, lower Vector3]
	for li in net.lanes.size():
		if net.lane_conn[li] == 1:
			continue
		var lp: PackedVector3Array = net.lanes[li]
		for i in range(0, lp.size(), 3):
			var q := lp[i]
			var k := Vector2i(floori(q.x / 6.0), floori(q.z / 6.0))
			if buckets.has(k):
				var o: Vector3 = buckets[k]
				if absf(o.y - q.y) > 5.5:
					stacked.append([q if q.y > o.y else o, o if q.y > o.y else q])
					buckets.erase(k)
					continue
			buckets[k] = q
	stacked.shuffle()
	print("    stacked road sites: %d" % stacked.size())
	var size: Vector3 = game._car_spec("hatch")["size"]
	var tried := 0
	for pair: Array in stacked:
		if tried >= 6:
			break
		tried += 1
		for lvl in 2:
			var at: Vector3 = pair[lvl]
			await stand(at)
			await frames(4)
			var r := game.safe.road_spot(at, size, {"exclude": [game.player.get_rid()], "min_d": 3.5})
			var ok: bool = r["ok"]
			var y := (r["xf"] as Transform3D).origin.y if ok else NAN
			check(ok and absf(y - at.y) < 2.0, "%s level at (%.0f, %.1f, %.0f): car put at y %.1f (%s)" % [
				"upper" if lvl == 0 else "lower", at.x, at.y, at.z, y, r.get("how", "")])
	# Bridge decks over open water: never the sea.
	var mids: Array = []
	for li in range(0, net.lanes.size(), 7):
		var lp2: PackedVector3Array = net.lanes[li]
		if lp2.size() < 20 or net.lane_conn[li] == 1:
			continue
		var q2 := lp2[lp2.size() / 2]
		if game.layout.is_water(q2) and q2.y > 3.0:
			mids.append(q2)
		if mids.size() >= 4:
			break
	for m: Vector3 in mids:
		await stand(m)
		await frames(4)
		var r2 := game.safe.road_spot(m, size, {"exclude": [game.player.get_rid()], "min_d": 3.5})
		var o2 := (r2["xf"] as Transform3D).origin
		check(r2["ok"] and not game.layout.is_water(o2) or (r2["ok"] and o2.y > m.y - 2.0), "bridge deck at (%.0f, %.1f, %.0f): car on the deck (y %.1f, %s)" % [m.x, m.y, m.z, o2.y, r2.get("how", "")])
	# A real purchase on the last stacked site's upper level, settled.
	if not stacked.is_empty():
		var top: Vector3 = stacked[0][0]
		await stand(top)
		await frames(4)
		game.empire.personal_cash += 100000.0
		var n0 := game.cars.size()
		check(game.buy_vehicle("hatch") == "", "bought a car on the upper level")
		var c: Car = game.cars.values()[game.cars.size() - 1] if game.cars.size() > n0 else null
		if c:
			await wait(2.5)
			var cp := c.global_position
			var under := _surface(cp.x, cp.z, cp.y + 0.5)
			check(absf(cp.y - top.y) < 2.5 and absf(under - top.y) < 1.0 and c.global_basis.y.y > 0.9,
				"it stands on that level (y %.1f vs %.1f, surface under it %.1f)" % [cp.y, top.y, under])


## IC: infrastructure clearance in physics (complements tools/infra_clearance.gd,
## which audits the city's structure data): a 2.2 m × 2.4 m box swept along
## every lane (every 3 m, 0.45–2.85 m above it) must touch no world solid –
## no pier, column, footing or crosshead in any carriageway, junction or
## turning lane on any island. Whatever collision is live is checked (Skyport
## is resident; the city near the hero is streamed in first).
func scenario_ic() -> void:
	print("--- IC: nothing solid stands in a traffic lane")
	var net: RoadNet = game.gps.net
	var space := game.get_world_3d().direct_space_state
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.2, 2.4, 2.6)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = 1 | CityWorld.SOLID_LAYER
	var bad := {}
	var tested := 0
	for li in net.lanes.size():
		var lp: PackedVector3Array = net.lanes[li]
		for i in lp.size():
			var p := lp[i]
			var d := net.lane_dir(li, i * RoadNet.STEP)
			q.transform = Transform3D(Basis.looking_at(d, Vector3.UP), p + Vector3.UP * 1.65)
			tested += 1
			for h: Dictionary in space.intersect_shape(q, 4):
				var col: Object = h.get("collider")
				var nm: String = String((col as Node).name) if col is Node else str(col)
				if nm.begins_with("Car_") or col is Car or col is CharacterBody3D:
					continue
				var key := Vector2i(floori(p.x / 6.0), floori(p.z / 6.0))
				if not bad.has(key):
					var what := ""
					if col is CollisionObject3D:
						var co := col as CollisionObject3D
						var owner_id := co.shape_find_owner(int(h.get("shape", 0)))
						var sh_node := co.shape_owner_get_owner(owner_id) as Node3D
						if sh_node:
							var shp := (sh_node as CollisionShape3D).shape if sh_node is CollisionShape3D else null
							what = " shape at %s size %s" % [sh_node.global_position, (shp as BoxShape3D).size if shp is BoxShape3D else "?"]
					bad[key] = "%s at (%.0f, %.1f, %.0f) lane %d%s%s" % [nm, p.x, p.y, p.z, li, " (junction)" if net.lane_conn[li] == 1 else "", what]
	for k in bad:
		print("    ", bad[k])
	check(bad.is_empty(), "%d lane samples swept: %d obstructed spots" % [tested, bad.size()])


## VD: vehicle damage. Your car is driven into a concrete block on a quiet
## lane at parking, town and motorway speeds, scraped along it, hit from the
## side and dropped on its roof; every stage is checked (and filmed with
## `--sc-film=<dir>`: a close-up per stage). Then the damage must survive a
## save (state + dents replayed into a fresh car), and a garage must quote
## and fix it.
func scenario_vd() -> void:
	print("--- VD: localised vehicle damage")
	var film := String(game.args.get("sc-film", ""))
	var vid := String(game.empire.vehicles[0]["id"])
	var car: Car = game.cars[vid]
	var net: RoadNet = game.gps.net
	var start := game._start_point()
	var near := net.nearest(start, Vector3.ZERO, 200.0, -1, true)
	var lane: int = near["lane"]
	var s0: float = near["s"]
	var p0 := net.lane_point(lane, s0)
	var dir := net.lane_dir(lane, s0)
	await stand(p0 + Vector3(-dir.z, 0, dir.x) * 6.0)
	game.enter_vehicle(vid)
	game.drive_input.enabled = false
	await frames(5)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(6.0, 3.0, 1.0)
	cs.shape = bs
	wall.add_child(cs)
	var wm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	wm.mesh = bm
	wall.add_child(wm)
	game.add_child(wall)
	var basis := Basis.looking_at(dir, Vector3.UP)
	var wall_at := p0 + dir * 14.0 + Vector3.UP * 1.5
	wall.global_transform = Transform3D(basis, wall_at)
	await get_tree().physics_frame
	var stages := [["parking", 2.8, 0.0], ["town", 11.0, 0.0], ["fast", 24.0, 0.0]]
	for st: Array in stages:
		car.place(Transform3D(basis, p0 + Vector3.UP * 0.5), dir * float(st[1]))
		for i in 90:
			car.throttle = 0.2 if i < 40 else 0.0
			car.brake = 0.0
			await get_tree().physics_frame
		car.linear_velocity = Vector3.ZERO
		print("    %s (%.0f m/s): kind %s · front dmg %.2f · glass %s · lamps %s · engine %.2f · dents %d" % [st[0], st[1], car.impact_kind,
			car.dmg["front"], car.glass, car.lamps_ok, car.engine, car.visual.dent_log.size()])
		if film != "":
			wall.visible = false
			wall.process_mode = Node.PROCESS_MODE_DISABLED
			await _shot(car, film + "/vd_%s.png" % st[0], Vector3(-2.4, 1.3, -4.4))
			wall.visible = true
			wall.process_mode = Node.PROCESS_MODE_INHERIT
	check(car.dmg["front"] > 0.2 and float(car.glass["front"]) > 0.05, "front end and windscreen damaged after the fast hit (front %.2f, screen %.2f)" % [car.dmg["front"], car.glass["front"]])
	check(not car.lamps_ok["head_l"] or not car.lamps_ok["head_r"], "a headlamp smashed")
	check(car.engine < 1.0 and car.visual.dent_log.size() > 0, "engine hurt (%.2f) and the body dented (%d dents)" % [car.engine, car.visual.dent_log.size()])
	# Side impact: the block swung alongside, the car shoved into it sideways.
	var side := Vector3(-dir.z, 0, dir.x)
	wall.global_transform = Transform3D(Basis.looking_at(side, Vector3.UP), p0 + side * 3.2 + Vector3.UP * 1.5)
	await get_tree().physics_frame
	car.place(Transform3D(basis, p0 + Vector3.UP * 0.5), side * 13.0)
	for i in 70:
		await get_tree().physics_frame
	check(float(car.dmg["right"]) + float(car.dmg["left"]) > 0.05, "side hit damaged a flank (L %.2f R %.2f, glass %s)" % [car.dmg["left"], car.dmg["right"], car.glass])
	if film != "":
		wall.visible = false
		await _shot(car, film + "/vd_side.png", Vector3(4.2, 1.5, 0.5))
		wall.visible = true
	# Rollover: on its roof from 1.6 m.
	wall.queue_free()
	car.place(Transform3D(basis * Basis(Vector3.FORWARD, PI), p0 + Vector3.UP * 2.6), Vector3.DOWN * 6.0)
	for i in 50:
		await get_tree().physics_frame
	check(car.roof > 0.0, "rollover crushed the roof (%.2f, kind %s)" % [car.roof, car.impact_kind])
	game._right_car(car)
	await frames(30)
	if film != "":
		await _shot(car, film + "/vd_roof.png", Vector3(-3.0, 2.6, 3.4))
	# Persistence: the record carries the damage; a fresh car gets it back.
	var v := game.empire.vehicle(vid)
	game._store_damage(v, car)
	var copy := v.duplicate(true)
	copy["id"] = "vd_copy"
	var c2: Car = game._spawn_car(copy)
	await frames(3)
	check(c2 != null and absf(c2.engine - car.engine) < 0.001 and c2.glass == car.glass and c2.lamps_ok == car.lamps_ok
		and c2.visual.dent_log.size() == car.visual.dent_log.size(), "damage survives a save (engine, glass, lamps, %d dents)" % (c2.visual.dent_log.size() if c2 else -1))
	if c2:
		game.cars.erase("vd_copy")
		c2.queue_free()
	# Garage: a quote, then a full restoration.
	game.drive_input.enabled = true
	car.linear_velocity = Vector3.ZERO
	await frames(10)
	game.empire.personal_cash += 50000.0
	var q := game.repair_quote(vid)
	print("    quote: ", q)
	check(q["ok"] and float(q["full"]) > float(q["mech"]) and float(q["mech"]) > 0.0, "garage quotes mechanical %s / restoration %s (+ tow %s)" % [q["mech"], q["full"], q["tow"]])
	check(game.repair_vehicle(vid, "full") == "" and car.body_damage() < 0.01 and car.mech_damage() < 0.01 and car.visual.dent_log.is_empty(), "restored as new")


## VE: getting in and out of your car through the universal quick
## transition: each way must finish inside 0.9 s of game time, leave the hero
## standing on the ground clear of the bodywork (no floating, no clipping)
## and hand over the controls. `--sc-film=<dir>` saves frames through both.
func scenario_ve() -> void:
	print("--- VE: quick vehicle entry and exit")
	var film := String(game.args.get("sc-film", ""))
	var vid := String(game.empire.vehicles[0]["id"])
	var car: Car = game.cars[vid]
	if game.driving != "":
		game.exit_vehicle()
		await frames(5)
	var side := car.global_transform * Vector3(-(car.spec["size"] as Vector3).x * 0.5 - 1.6, 0.0, -0.4)
	await stand(Vector3(side.x, car.global_position.y, side.z))
	await wait(1.0)
	var t0 := Time.get_ticks_msec()
	var g0 := 0.0
	game.enter_vehicle(vid, true)
	var fr := 0
	while game.driving != vid and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		g0 += get_process_delta_time()
		if film != "" and fr % 2 == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(film + "/ve_in_%02d.png" % fr)
		fr += 1
	check(game.driving == vid and g0 < 0.9, "in and driving after %.2f s of game time" % g0)
	await wait(1.0)
	car.linear_velocity = Vector3.ZERO
	await frames(5)
	var g1 := 0.0
	var t1 := Time.get_ticks_msec()
	game.exit_vehicle(true)
	fr = 0
	while game.driving != "" and Time.get_ticks_msec() - t1 < 20000:
		await get_tree().process_frame
		g1 += get_process_delta_time()
		if film != "" and fr % 2 == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(film + "/ve_out_%02d.png" % fr)
		fr += 1
	check(game.driving == "" and g1 < 0.9, "out on foot after %.2f s of game time" % g1)
	await wait(0.6)
	var pp := game.player.global_position
	var under := _surface(pp.x, pp.z, pp.y + 0.2)
	var local := car.global_transform.affine_inverse() * pp
	var half: Vector3 = (car.spec["size"] as Vector3) * 0.5
	check(absf(pp.y - 0.9 - under) < 0.35, "standing on the ground (feet %.2f, ground %.2f)" % [pp.y - 0.9, under])
	check(absf(local.x) > half.x + 0.15 or absf(local.z) > half.z + 0.15, "clear of the bodywork (%.2f m from the side)" % (absf(local.x) - half.x))
	check(game.player.input_enabled, "controls handed back")


## SM: environmental destruction. Your car at a shop window: a parking
## nudge (2 m/s) must be stopped by it; at 9 m/s it smashes through into the
## shop (window broken, the car inside, the bodywork hurt, a charge or a
## repair bill raised), and the frame and pilasters stand. Then a bench and a
## bus shelter: the bench always goes, the shelter only to enough momentum.
func scenario_sm() -> void:
	print("--- SM: storefronts and street furniture")
	var film := String(game.args.get("sc-film", ""))
	var vid := String(game.empire.vehicles[0]["id"])
	var car: Car = game.cars[vid]
	if game.driving == "":
		game.enter_vehicle(vid)
	game.drive_input.enabled = false
	game.empire.personal_cash += 50000.0
	# A street room with a window near the start.
	var start := game._start_point()
	car.place(Transform3D(Basis.IDENTITY, start + Vector3.UP * 0.5))
	game.world.build_all_near(start, 200.0)
	await frames(30)
	var best: ShopInterior = null
	var bd := INF
	for _try in 40:
		game._stream_interiors()
		for r in get_tree().get_nodes_in_group("shop_spans"):
			var si := r as ShopInterior
			if si.span_count() == 0 or si.unit.get("island", "") == "skyport":
				continue
			var d := si.global_position.distance_to(start)
			if d < bd:
				bd = d
				best = si
		if best:
			break
		await frames(10)
	check(best != null, "a shop with breakable windows streamed in (%s)" % (best.unit.get("id", "") if best else "none"))
	if best == null:
		return
	var b := best.span_box(0)
	var xf: Transform3D = b[0]
	var lo: Vector3 = b[1]
	var hi: Vector3 = b[2]
	var centre := xf * ((lo + hi) * 0.5)
	var out := xf.basis.z.normalized()
	var face := Basis.looking_at(-out, Vector3.UP)
	var spawn := centre + out * 7.0
	spawn.y = _surface(spawn.x, spawn.z, spawn.y + 3.0)
	var cash0 := game.empire.personal_cash + game.empire.company_cash
	# 1. A nudge.
	car.place(Transform3D(face, spawn + Vector3.UP * 0.4), -out * 2.0)
	for i in 120:
		car.throttle = 0.0
		await get_tree().physics_frame
	check(not best.span_broken(0), "a 2 m/s nudge doesn't break the window")
	# 2. Through it.
	car.place(Transform3D(face, spawn + Vector3.UP * 0.4), -out * 9.0)
	var got_in := false
	for i in 100:
		car.throttle = 0.15
		await get_tree().physics_frame
		var l := xf.affine_inverse() * car.global_position
		if l.z < -1.2:
			got_in = true
	car.throttle = 0.0
	car.brake = 1.0
	check(best.span_broken(0), "9 m/s smashes the window")
	check(got_in, "and the car goes on into the shop")
	check(car.dmg["front"] > 0.0 or car.scuff["front"] > 0.0, "the car took the hit (front %.2f, scuff %.2f, screen %.2f)" % [car.dmg["front"], car.scuff["front"], car.glass["front"]])
	await wait(1.0)
	if film != "":
		await _shot(car, film + "/sm_inside.png", Vector3(0.0, 2.2, 7.5))
		var cam := Camera3D.new()
		game.add_child(cam)
		cam.global_position = centre + out * 9.0 + Vector3.UP * 1.6 + xf.basis.x * 3.0
		cam.look_at(centre, Vector3.UP)
		cam.make_current()
		await frames(6)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(film + "/sm_front.png")
		cam.queue_free()
		game.chase.cam.make_current()
	# The charge: right away for your own shop, after the patrol for others.
	await until(func(): return game.empire.personal_cash + game.empire.company_cash < cash0 - 100.0, 90.0)
	check(game.empire.personal_cash + game.empire.company_cash < cash0 - 100.0, "billed for the damage (%s)" % EmpireData.money(cash0 - game.empire.personal_cash - game.empire.company_cash))
	# The room rebuilt from scratch keeps its broken window.
	check(game.smash.state_for(String(best.unit["id"])).get(0, "") == "broken", "remembered as broken")


## AP: every home's journey on foot, no teleports: from the pavement in
## through the street door, down the lobby to the lift, call it, step in,
## ride up, out into the lift hall, through the front door and into the
## apartment – the hero steered like a player holding the stick. Fails on
## any leg that can't be walked. `--sc-only=home_x,…` limits it,
## `--sc-film=<dir>` saves the hero-camera view in the lobby, the hall and
## the apartment.
func scenario_ap() -> void:
	print("--- AP: street to apartment, every home")
	var film := String(game.args.get("sc-film", ""))
	var only := String(game.args.get("sc-only", "")).split(",", false)
	var e := game.empire
	e.personal_cash = 9000000.0
	var p := game.player
	var w := _Walk.new()
	w.amount = 0.8
	for hm: Dictionary in game.homes():
		var hid := String(hm["id"])
		if not only.is_empty() and not (hid in only):
			continue
		var el: ApartmentElevator = game.elevators.get(hid)
		if el == null:
			check(false, "%s has a lift" % hid)
			continue
		if not e.owns_property(hid) and String(hm.get("estate", "")) == "":
			var rec := hm.duplicate()
			rec.erase("h")
			e.buy_property(rec)
		var owned := e.owns_property(hid)
		if not owned:
			print("    %s: comes with an estate – skipped" % hid)
			continue
		var out := el.global_basis.z.normalized()
		var street := el.street_door_world() + out * 1.8
		await stand(street)
		await wait(0.5)
		p.bot = w
		var legs := [["street door", el.to_global(Vector3(0, 0, el.lobby_len - 0.6))],
			["down the lobby", el.to_global(Vector3(0, 0, 1.4))]]
		var ok := true
		for leg: Array in legs:
			var r := await _walk_to(w, leg[1], 14.0)
			if not r["ok"]:
				check(false, "%s: %s (stuck at %s)" % [hid, leg[0], r.get("at", "")])
				ok = false
				break
		if ok and film != "":
			await _hero_shot(film + "/ap_%s_lobby.png" % hid)
		if ok:
			el.call_to(false)
			await until(func(): return el.state == "idle_g" and el._g_door_open > 0.95, 15.0)
			var r2 := await _walk_to(w, el.cabin_center_world() - Vector3.UP * 0.95, 8.0)
			ok = r2["ok"] and el.is_inside_cabin(p.global_position)
			check(ok, "%s: into the lift car" % hid)
		if ok:
			el.ride_to(true)
			await until(func(): return el.state == "idle_top", 150.0)
			ok = el.at_top and el.is_inside_cabin(p.global_position)
			if not ok:
				print("    ride: state=%s at_top=%s cabin_y=%.2f riding=%s player local=%s" % [el.state, el.at_top, el.cabin_y, el._player_riding, el.to_local(p.global_position)])
			check(ok, "%s: rode up with the car (%.1f m)" % [hid, el.top_y])
		if ok:
			var r3 := await _walk_to(w, el.to_global(Vector3(0, el.top_y, Apartments.HALL_D * 0.5)), 8.0)
			ok = r3["ok"]
			check(ok, "%s: out into the lift hall%s" % [hid, "" if ok else " (stuck at %s)" % r3.get("at", "")])
			if ok and film != "":
				await _hero_shot(film + "/ap_%s_hall.png" % hid)
		if ok:
			var inside := el.to_global(Vector3(0, el.top_y, Apartments.HALL_D + 1.6))
			var r4 := await _walk_to(w, inside, 10.0)
			var f := Apartments.to_face(hm["h"], p.global_position)
			var h: Dictionary = hm["h"]
			ok = r4["ok"] and f.y > float(h["y0"]) and f.y < float(h["y0"]) + 2.5 and f.x > float(h["a0"]) and f.x < float(h["a1"]) and f.z < -0.3
			check(ok, "%s: through the front door into the apartment%s" % [hid, "" if ok else " (at %s)" % r4.get("at", p.global_position)])
			if ok and film != "":
				w.target = p.global_position
				await wait(0.8)
				await _hero_shot(film + "/ap_%s_home.png" % hid)
		p.bot = null
		el._player_riding = false


func _hero_shot(path: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _shot(car: Car, path: String, off: Vector3) -> void:
	var cam := Camera3D.new()
	game.add_child(cam)
	var at := car.global_transform * off
	cam.global_position = at
	cam.look_at(car.global_position + Vector3.UP * 0.6, Vector3.UP)
	cam.fov = 50.0
	cam.make_current()
	await frames(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	cam.queue_free()
	game.chase.cam.make_current()


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
				for dx in [-2.0, -1.0, 0.0, 1.0, 2.0]:
					for dz in [-2.0, -1.0, 0.0, 1.0, 2.0]:
						_probe_at(p.x + dx, p.z + dz, float(expect.call(p)) + 0.6)
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
	# (Your own cars aren't road obstructions: an earlier scenario - XA's
	# drive - leaves one stopped on an island road.)
	var own: Array[RID] = []
	for c in game.cars.values():
		own.append((c as CollisionObject3D).get_rid())
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
					query.exclude = own
					query.transform = Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.z)), centre + Vector3(-direction.z, 0, direction.x) * offset + Vector3.UP * 1.1)
					var hits := game.get_world_3d().direct_space_state.intersect_shape(query, 1)
					if not hits.is_empty():
						var co: Object = hits[0]["collider"]
						road_obstacles.append("%s at %s (%s)" % [rd[0], centre, (co as Node).get_path() if co is Node else str(co)])
						if OS.has_environment("SC_DEBUG"):
							var rid: RID = hits[0]["rid"]
							var si: int = hits[0]["shape"]
							var srid := PhysicsServer3D.body_get_shape(rid, si)
							print("OBST ", PhysicsServer3D.body_get_shape_transform(rid, si), " ", PhysicsServer3D.shape_get_data(srid))
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
					# (The island's Grand Diagonal west of x 150 is the old bridge's
					# lane - Traffic skips it too; under the deck it's the plaza
					# round the bridge piers, not a street.)
					if not L.is_mainland and rd.get("name", "") == "diagonal" and q2.x < 150.0:
						k += 2.0
						continue
					if not game.layout.is_water(Vector3(q2.x, 0, q2.y)) and not L.is_water(Vector3(q2.x, 0, q2.y)) and not carried.call(q2) \
							and Geometry2D.is_point_in_polygon(q2, L.coast):
						pts.append(Vector3(q2.x, 0.0, q2.y))
					k += 2.0
			n += pts.size()
			var rr := _audit_line(pts, func(p): return L.terrain.road_y(p.x, p.z) + 0.3)
			if int(rr[0]) > 0 or int(rr[1]) > 0:
				bad_roads += 1
				if game.args.has("sc-debug"):
					print("    BAD ROAD ", rd.get("name", "?"), " ", rd.get("kind", "?"), " ", rp2, " keys ", rd.keys())
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
		if game.args.has("sc-debug"):
			var al := _ramp_start(B) - 10.0
			var line := ""
			while al < 30.0:
				var pp := _bp(B, al, 3.8)
				line += "%.0f:%.2f/%.2f " % [al, _surface(pp.x, pp.z, _road_y(pp) + 2.0), _road_y(pp)]
				al += 2.0
			print("    PROFILE ", B["name"], " ", line)
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
	if game.ui.panel_open():
		game.ui.close_panel(true)
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
	game.ui._style_set({"top": "top_shirt", "shoes": "shoes_royal"})
	await frames(2)
	var un := Wardrobe.unpaid(e.flags, HeroLook.current(e.flags))
	check(un.size() == 2, "trying on two items you don't own (%s)" % str(un))
	# (Empire.pay takes company cash first: count both.)
	var cash := e.personal_cash + e.company_cash
	var err := Wardrobe.buy(e, un, "clothes_premium")
	var expected := Wardrobe.price("top_shirt") + Wardrobe.price("shoes_royal")
	check(err == "" and absf(cash - e.personal_cash - e.company_cash - expected) < 0.01, "paid for both items once (%s)" % err)
	Wardrobe.save_outfit(e.flags, HeroLook.current(e.flags))
	game.ui._close_style()
	game.save_game()
	game.load_game()
	await frames(5)
	var l := HeroLook.current(game.empire.flags)
	check(l["top"] == "top_shirt" and Wardrobe.owns(game.empire.flags, "shoes_royal"), "wearing and owning them after a reload")
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
			var marker := String(sp[0])
			var offered := String(game.spot.get("venue_spot", ""))
			if game.spot.get("kind") == "sky_display":
				offered = "inspect_" + String(game.spot.get("model", ""))
			if offered != marker or game.spot.get("site") != d["site"]:
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
	var apron := SkyportIsland.w(Vector3(1660, SkyportIsland.LAND_Y + 1.5, 470))
	car.place(Transform3D(Basis.IDENTITY, apron))
	game.enter_vehicle(vid2)
	await frames(5)
	car.place(Transform3D(Basis(Vector3.FORWARD, PI), apron))
	check(await until(func(): return car.global_basis.y.dot(Vector3.UP) > 0.9 and car.upside_time == 0.0, 12.0),
		"a flipped car is back on its wheels (up·y %.2f)" % car.global_basis.y.dot(Vector3.UP))
	await until(func(): return car.wheels_on_ground > 0 and car.linear_velocity.length() < 1.0, 10.0)
	game.exit_vehicle()
	check(game.driving == "", "got out of the recovered car")


## U: "Stuck? Back to the street" (quality audit 2026-11-18). Puts you, then
## your car, inside a big building near the start (as a glitch through a
## wall would) and checks the escape lands you outside it, by a road, on
## the ground – and the car on a lane, upright, able to drive off.
func scenario_u() -> void:
	print("--- U: stuck recovery")
	await until(func(): return game.gps.ready_net(), 60.0)
	if game.driving != "":
		# (An earlier scenario can leave the car moving: you can only get
		# out once it has stopped.)
		var dc: Car = game.cars[game.driving]
		dc.linear_velocity = Vector3.ZERO
		dc.angular_velocity = Vector3.ZERO
		await frames(3)
		game.exit_vehicle()
	check(game.driving == "", "on foot")
	var start := game.starter_unit()
	var sp := Premises.door_point(start)
	# (From wherever an earlier scenario left you: back at the start, with
	# its streets and buildings streamed in, before picking the building.)
	game._teleport(sp + Premises.outward(start) * 3.0 + Vector3.UP, 0.0)
	await wait(3.0)
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
	game.ui.close_panel(true)
	if game.driving != "":
		var car: Car = game.cars[game.driving]
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		game.exit_vehicle()
	check(game.driving == "" and game.skyport_play.piloting == "", "on foot before checking distance-based streaming")
	var north := Vector3(940.0, 0.0, -420.0)
	north.y = game.layout.ground_y(north.x, north.z) + 1.0
	check(SkyportIsland.distance_to(north) > SkyportIsland.NEAR_FREE, "the test point is beyond the unload radius")
	game._teleport(north, 0.0)
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
	if _which.split(",").has("RS"):
		await scenario_rs()
	if _which.split(",").has("IC"):
		await scenario_ic()
	if _which.split(",").has("VD"):
		await scenario_vd()
	if _which.split(",").has("VE"):
		await scenario_ve()
	if _which.split(",").has("SM"):
		await scenario_sm()
	if _which.split(",").has("AP"):
		await scenario_ap()
	for k in ["XO", "XA", "XV", "XN", "XD", "XR", "XB", "XC", "XK", "XP", "XF", "XG", "XH", "XI", "XS", "XW"]:
		if _which.split(",").has(k) or _which.split(",").has("X"):
			await call("scenario_" + k.to_lower())
	if _which.split(",").has("K"):
		await scenario_k()
	if _which.split(",").has("KS"):
		await scenario_ks()
	if _which.split(",").has("UI"):
		await scenario_ui()
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
	# Start on the public road, not inside a neighbouring shop.
	var near := game.gps.net.nearest(Premises.door_point(far), Vector3.ZERO, 40.0, -1, true)
	check(not near.is_empty(), "found a public lane near the destination")
	if near.is_empty():
		return
	await stand(game.gps.net.lane_point(near["lane"], near["s"]))
	var q := game.delivery_quote(vid)
	check(q["ok"] and q["fee"] > 0.0, "a delivery quote (%s)" % (EmpireData.money(float(q["fee"])) if q["ok"] else q["why"]))
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
	check(game.deliver_vehicle(vid) == "Delivery in progress", "a duplicate delivery is refused")
	check(is_equal_approx(e.personal_cash + e.company_cash, cash), "charged on arrival")
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
	if game.args.has("sc-flat"):
		await _film_flat(dir, u)
		return
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


## `--scenarios=V --sc-flat[=pace] --sc-film=<dir>`: the hero walks 14 m
## along the pavement in front of the starter shop, filmed square-on from
## the side at 20 frames a second (judging the legs).
func _film_flat(dir: String, u: Dictionary) -> void:
	var p := game.player
	var along := Premises.along_dir(u)
	var out := Premises.outward(u)
	var a := Premises.door_point(u) + out * 4.6 - along * 7.0
	a.y = float(game.layout.ground_y(a.x, a.z))
	await stand(a)
	p.rotation.y = atan2(-along.x, -along.z)
	game.camera.snap()
	await wait(1.0)
	var w := _Walk.new()
	w.amount = float(game.args.get("sc-flat", "1.0")) if String(game.args.get("sc-flat", "")) not in ["", "true"] else 1.0
	w.target = a + along * 14.0
	p.bot = w
	var n := 0
	var t := 0.0
	while t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var c := p.global_position + Vector3.UP * 0.05
		var eye := c - out * 4.5 + Vector3.UP * 0.1
		game.camera.cine = func(_dt: float) -> Array:
			return [Transform3D(Basis.looking_at(c - eye, Vector3.UP), eye), 42.0]
		if Engine.get_physics_frames() % 3 == 0 and t > 0.8:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/s%03d.png" % [dir, n])
			n += 1
	p.bot = null
	game.camera.cine = Callable()
	print("FILM %d frames in %s (walked %.1f m)" % [n, dir, p.global_position.distance_to(a)])


# ------------------------------------------- UI: the phone keeps its place
## `--scenarios=UI`: lists stay where you scrolled them through actions,
## sheets, detail pages and section switches; filters and selections
## survive closing the phone; buying a car from the Marketplace works.
func _page_scroll() -> ScrollContainer:
	var ph := game.ui.phone
	if ph == null:
		return null
	for sc in ph._scrolls(ph._page):
		if sc is TouchScroll:
			return sc
	return null


func _settle() -> void:
	for k in 6:
		await get_tree().process_frame


func scenario_ui() -> void:
	print("--- UI: phone navigation keeps its place")
	var ui := game.ui
	var e := game.empire
	e.personal_cash = 400000.0
	ui.open_phone("property")
	await _settle()
	var sc := _page_scroll()
	check(sc != null, "Property has a scrolling list")
	if sc == null:
		return
	sc.scroll_vertical = 640
	await _settle()
	var at := sc.scroll_vertical
	check(at > 300, "the list scrolled (%d px)" % at)
	# 1. Any action refreshes the page: the list must not jump to the top.
	ui.phone.refresh()
	await _settle()
	check(absi(_page_scroll().scroll_vertical - at) <= 2, "after an action the list is still at %d px (was %d)" % [_page_scroll().scroll_vertical, at])
	# 2. A sheet over the list, then closed.
	var u: Dictionary = {}
	for x in game.units:
		if x["kind"] == "shop" and MapKit.unit_kind(game, x) == "to_let":
			u = x
			break
	ui.open_property(u, true)
	await _settle()
	check(ui.phone != null and ui.phone.has_sheet(), "a detail opens as a sheet over the phone (the phone stays)")
	ui.phone.dismiss_sheet()
	await _settle()
	check(absi(_page_scroll().scroll_vertical - at) <= 2, "closing the sheet: still at %d px" % _page_scroll().scroll_vertical)
	# 3. Into a listing and back.
	ui.phone.push("listing", {"id": String(u["id"]), "home": false}, "Listing")
	await _settle()
	check(Phone.stacks["property"].size() == 2, "the listing is a page on Property's stack")
	ui.phone.back()
	await _settle()
	check(absi(_page_scroll().scroll_vertical - at) <= 2, "back from the listing: still at %d px" % _page_scroll().scroll_vertical)
	# 4. Another section and back.
	ui.open_phone("city500")
	await _settle()
	Phone.st("city500")["sector"] = "retail"
	ui.phone.refresh()
	await _settle()
	ui.open_phone("property")
	await _settle()
	check(absi(_page_scroll().scroll_vertical - at) <= 2, "back on Property from City500: still at %d px" % _page_scroll().scroll_vertical)
	# 5. Close the phone and open it again: City500 keeps its filter.
	ui.close_panel(true)
	await _settle()
	ui.open_phone("city500")
	await _settle()
	check(String(Phone.st("city500").get("sector", "")) == "retail", "City500 remembers its sector filter after closing the phone")
	# 6. Buy a car from the Marketplace (two taps, no extra screen).
	var n0 := e.vehicles.size()
	var cash0 := e.personal_cash + e.company_cash
	ui.open_phone("market")
	await _settle()
	ui.phone.push("vehicle", {"model": "saloon", "site": "dealer_budget"}, "Saloon")
	await _settle()
	var buy: Button = null
	for b in ui.phone._page.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("Buy ·"):
			buy = b
	check(buy != null, "the car's page has a Buy button")
	if buy:
		buy.pressed.emit()
		check(e.vehicles.size() == n0 and buy.text.begins_with("Tap again"), "the first tap asks to confirm in place")
		buy.pressed.emit()
		await _settle()
	var price := float(EmpireData.vehicle_model("saloon").get("price", 0))
	check(e.vehicles.size() == n0 + 1, "the second tap buys it (%d → %d vehicles)" % [n0, e.vehicles.size()])
	check(absf((cash0 - (e.personal_cash + e.company_cash)) - price) < 1.0, "paid %s" % EmpireData.money(price))
	check(ui.phone != null, "the phone stays open after buying")
	# 7. Rent a shop from a listing's sheet: the sheet closes, the phone stays.
	var nb := e.businesses.size()
	ui.open_phone("property")
	await _settle()
	ui.open_property(u, true)
	await _settle()
	var rent: Button = null
	for b2 in ui.phone._sheet.find_children("*", "Button", true, false):
		if (b2 as Button).text.begins_with("RENT"):
			rent = b2
	check(rent != null and not rent.disabled, "the shop's sheet offers RENT")
	if rent:
		rent.pressed.emit()
		await _settle()
	check(e.businesses.size() == nb + 1, "rented it from the phone (%d → %d businesses)" % [nb, e.businesses.size()])
	check(ui.phone != null and not ui.phone.has_sheet(), "the sheet closed, the phone stayed")
	ui.close_panel(true)



# ------------------------------------- K: hitting things (NEVER STOP's rules)
## Clear straight approach to `to` from `from` (nothing solid to a car between).
func _clear_line(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.8, to + Vector3.UP * 0.8, 1 | (1 << 7))
	return game.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Drives `car` from `start` along `dir` at `v` for `secs`; returns the lowest speed seen.
func _ram(car: Car, start: Vector3, dir: Vector3, v: float, secs: float, coast_after_hit := false) -> float:
	var y := maxf(start.y, game.layout.ground_y(start.x, start.z)) if game.layout else start.y  # (lanes on viaducts)
	car.place(Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(start.x, y + 0.5, start.z)), dir * v)
	var low := INF
	_wreck_n0 = game.wrecks.wrecks.size()
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	var t := 0.0
	while t < secs and Time.get_ticks_msec() < end + 20000:
		var hit_any: bool = coast_after_hit and game.wrecks.wrecks.size() > _wreck_n0
		car.throttle = 0.0 if hit_any else 0.35
		car.brake = 0.0
		car.steer = 0.0
		car.handbrake = false   # (left on when you got out)
		await get_tree().physics_frame
		var t_was := t
		t += get_physics_process_delta_time()
		if t > 0.3:
			low = minf(low, car.speed)
		if game.args.has("sc-film"):
			for at in [0.9, 1.4, 2.0]:
				if t_was < at and t >= at:
					await RenderingServer.frame_post_draw
					_film_n += 1
					get_viewport().get_texture().get_image().save_png("%s/k_%02d.png" % [String(game.args["sc-film"]), _film_n])
	return low


var _film_n := 0
var _wreck_n0 := 0


func scenario_k() -> void:
	print("--- K: hitting things – furniture flies, other cars are cars")
	var vid := String(game.empire.vehicles[0]["id"])
	game.enter_vehicle(vid)
	var car: Car = game.cars[vid]
	game.drive_input.enabled = false
	var here := car.global_position
	# 1 – a street light.
	var lamp: Array = []
	var dir := Vector3.ZERO
	var cells: Array = game.props._grid.keys()
	cells.sort_custom(func(a, b): return Vector2(a).distance_to(Vector2(here.x, here.z) / Destructibles.CELL) < Vector2(b).distance_to(Vector2(here.x, here.z) / Destructibles.CELL))
	for c in cells.slice(0, 60):
		for it in game.props._grid[c]:
			if String(it[0]) != "streetlight":
				continue
			var o: Vector3 = (it[1] as Transform3D).origin
			for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
				if _clear_line(o - d * 14.0, o - d * 1.0):
					lamp = it
					dir = d
					break
			if not lamp.is_empty():
				break
		if not lamp.is_empty():
			break
	check(not lamp.is_empty(), "found a street light with a clear run-up")
	if not lamp.is_empty():
		var o: Vector3 = (lamp[1] as Transform3D).origin
		var pieces0: int = game.props._pieces.size()
		var low := await _ram(car, o - dir * 14.0, dir, 12.0, 2.2)
		var cw: CityWorld = lamp[3]
		check(cw.broken.has(CityWorld.item_key(o)), "the street light is knocked down (gone from the street)")
		check(game.props._pieces.size() > pieces0, "…and flies off as a physical piece")
		check(low > 7.0, "the car carries on (lowest %.1f m/s from 12: it isn't a wall)" % low)
	# 2 – a parked car, from behind.
	var cw2: CityWorld = game.world
	var target: Array = []
	for wc in [game.world, game.world.mainland]:
		if wc and (wc as CityWorld)._loaded.has(Vector2i(floori(here.x / CityWorld.CHUNK), floori(here.z / CityWorld.CHUNK))):
			cw2 = wc
	var c0 := Vector2i(floori(here.x / CityWorld.CHUNK), floori(here.z / CityWorld.CHUNK))
	for r in 3:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var key := c0 + Vector2i(dx, dz)
				if not target.is_empty() or not cw2._loaded.has(key):
					continue
				for pc in cw2.parked_cars(key):
					var xf: Transform3D = pc[0]
					for sd: float in [1.0, -1.0]:
						if target.is_empty() and _clear_line(xf.origin + xf.basis.x * sd * 9.0, xf.origin + xf.basis.x * sd * 2.5):
							target = [pc[0], pc[1], sd]
					if not target.is_empty():
						break
	check(not target.is_empty(), "found a parked car with a clear run-up from the road")
	if not target.is_empty():
		var xf: Transform3D = target[0]
		var n0: int = game.wrecks.wrecks.size()
		var p0 := xf.origin
		var sd: float = target[2]
		await _ram(car, xf.origin + xf.basis.x * sd * 9.0, -xf.basis.x * sd, 10.0, 2.0)
		var w: Array = game.wrecks.wrecks.slice(n0)
		check(not w.is_empty(), "hitting the parked car turns it into a real car")
		if not w.is_empty():
			var wc: Car = w[0]["car"]
			check(wc.global_position.distance_to(p0) > 0.8, "…which is shunted (%.1f m)" % wc.global_position.distance_to(p0))
			check(cw2.broken.has(CityWorld.item_key(p0)), "…and has left the kerb (not drawn twice)")
	# 3 – a moving traffic car, from behind in its lane.
	var tr: Traffic = game.world.traffic
	var hit_id := -1
	var start := Vector3.ZERO
	var fwd := Vector3.ZERO
	for attempt in 6:
		await stand(here + Vector3(attempt * 37.0, 0, attempt * -23.0))
		await wait(0.6)
		for it in game.traffic_bodies.city_cars():
			var xf: Transform3D = it[1]
			if tr.car_speed(int(it[0])) < 3.0:
				continue
			if _clear_line(xf.origin + xf.basis.z * 14.0, xf.origin + xf.basis.z * 3.0):
				hit_id = int(it[0])
				start = xf.origin + xf.basis.z * 14.0
				fwd = -xf.basis.z
				break
		if hit_id >= 0:
			break
	check(hit_id >= 0, "found a moving traffic car with clear lane behind it")
	if hit_id >= 0:
		game.enter_vehicle(vid)
		game.drive_input.enabled = false   # (enter_vehicle hands the car back to the player's input)
		var n1: int = game.wrecks.wrecks.size()
		var tf := func():
			var wl: Array = game.wrecks.wrecks
			var wd := ""
			if wl.size() > n1:
				var wc: Car = wl[-1]["car"]
				wd = "wreck at %s v=%s (me %s)" % [wc.global_position.snapped(Vector3.ONE * 0.1), wc.linear_velocity.snapped(Vector3.ONE * 0.1), car.global_position.snapped(Vector3.ONE * 0.1)]
			print("  trace: speed %.1f  wrecks %d %s" % [car.speed, wl.size(), wd])
		await _ram(car, start, fwd, tr.car_speed(hit_id) + 9.0, 2.6, true)
		tf.call()
		check(tr.knocked.has(hit_id), "the traffic car is knocked out of the traffic")
		var w2: Array = game.wrecks.wrecks.slice(n1)
		check(not w2.is_empty() and (w2[0]["car"] as Car).speed > 1.0 or not w2.is_empty() and (w2[0]["car"] as Car).global_position.distance_to(start) > 16.0,
			"…and becomes a real car that the hit pushes along")
	game.drive_input.enabled = true


## KS: a minute of real driving through traffic (AIDriver on your car, no
## avoidance: it hits things): every swap is either touched or put back, no
## wreck is flung, no traffic slot leaks, no CPU car is left inside another.
func scenario_ks() -> void:
	print("--- KS: a minute in traffic")
	await until(func(): return game.gps.ready_net(), 30.0)
	var vid := String(game.empire.vehicles[0]["id"])
	game.enter_vehicle(vid)
	game.drive_input.enabled = false
	var car: Car = game.cars[vid]
	var net: RoadNet = game.gps.net
	# A busy avenue on the Commercial Island.
	var start := Vector3(560.0, 0.0, -120.0)
	var n := net.nearest(start, Vector3.ZERO, 200.0, -1, true)
	check(not n.is_empty(), "found a lane to start on")
	if n.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var path := net.wander(int(n["lane"]), float(n["s"]), 900.0, rng, 0.3)
	car.place(Transform3D(Basis.looking_at((path[1] - path[0]).normalized(), Vector3.UP), path[0] + Vector3.UP * 0.4), Vector3.ZERO)
	var d := AIDriver.new(car)
	d.avoid = false
	d.skill = 1.0
	d.set_path(path)
	var space := game.get_world_3d().direct_space_state
	var swaps := 0
	var hit := 0
	var flung := 0
	var max_w := 0
	var t := 0.0
	var seen := {}
	while t < 60.0:
		car.handbrake = false
		d.update(get_physics_process_delta_time(), space)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if d.remaining() < 20:
			var nn := net.nearest(car.global_position, -car.global_basis.z, 30.0)
			if not nn.is_empty():
				d.set_path(net.wander(int(nn["lane"]), float(nn["s"]), 900.0, rng, 0.3))
		for w in game.wrecks.wrecks:
			var c: Car = w["car"]
			if not is_instance_valid(c):
				continue
			if not seen.has(c):
				seen[c] = true
				swaps += 1
			if w["hit"] and not seen.has(str(c.get_instance_id()) + "h"):
				seen[str(c.get_instance_id()) + "h"] = true
				hit += 1
			if c.linear_velocity.length() > 45.0:
				flung += 1
		max_w = maxi(max_w, game.wrecks.wrecks.size())
	var tr: Traffic = game.world.traffic
	var live := {}
	for w in game.wrecks.wrecks:
		if int(w["traffic"]) >= 0:
			live[int(w["traffic"])] = true
	var leaked := 0
	for id in tr.knocked:
		if not live.has(id):
			leaked += 1
	print("  drove %.0f m: swaps %d, touched %d, wrecks now %d (max %d), knocked %d" % [car.global_position.distance_to(path[0]), swaps, hit, game.wrecks.wrecks.size(), max_w, tr.knocked.size()])
	check(swaps == 0 or hit > 0, "swapped cars are ones you actually hit (%d/%d)" % [hit, swaps])
	check(game.wrecks.wrecks.all(func(w): return w["hit"] or float(w["t"]) <= 1.3), "no untouched swap left standing in a lane")
	check(flung == 0, "no wreck flung by a bad spawn (%d frames)" % flung)
	check(leaked == 0, "no traffic slot left knocked without its wreck (%d)" % leaked)
	game.drive_input.enabled = true
