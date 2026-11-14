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
	# Follow the route part way: progress and distance go down.
	var mid := gps.points[gps.points.size() / 3]
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
	for dist: float in [70.0, -70.0, 110.0, -110.0, 160.0, -160.0]:
		var p := mid + side * dist
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
