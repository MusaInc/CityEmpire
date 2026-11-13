extends Node
## Scripted playthrough of the first-business loop through the real game
## (scene, physics, interiors, shop floor, UI calls): `--autoplay`.
## Moves the hero by teleporting next to each interaction spot (it doesn't
## test walking routes) and drives the car for a few seconds to check the
## physics, then teleports it across town. Prints AUTOPLAY PASS/FAIL lines
## and quits with the number of failures.

var game: EmpireGame
var fails := 0
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print("AUTOPLAY %s  %s" % ["PASS" if ok else "FAIL", what])


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Puts the hero on a spot (world) and refreshes the current spot.
func stand_at(p: Vector3) -> void:
	if game.ui.panel_open():
		game.ui.close_panel(true)  # (a player closes what they opened)
	game.player.respawn(p + Vector3.UP * 0.95)
	await frames(8)
	game._update_spot()


func spot_of(kind: String, si: ShopInterior, extra := {}) -> Dictionary:
	for s in si.world_spots():
		if s["kind"] != kind:
			continue
		var ok := true
		for k in extra:
			if s.get(k) != extra[k]:
				ok = false
		if ok:
			return s
	return {}


func _run() -> void:
	await wait(1.0)
	var e := game.empire
	var start := game.starter_unit()
	var w := game.wholesaler("west")
	check(not start.is_empty() and not w.is_empty(), "starter shop %s and wholesaler %s exist" % [start.get("id"), w.get("id")])
	# 1 — rent the shop at its TO LET board.
	await stand_at(Premises.door_point(start) + Premises.outward(start) * 1.3)
	check(game.spot.get("kind") == "letboard", "TO LET board prompt at the shop door (%s)" % game.spot.get("kind"))
	var cash0 := e.personal_cash
	check(game.rent_unit(start) == "", "rented the shop")
	var b := e.business_at(start["id"])
	check(b != null and e.personal_cash < cash0, "business created, deposit paid (%.0f → %.0f)" % [cash0, e.personal_cash])
	check(game.interiors.has(start["id"]) and (game.interiors[start["id"]] as ShopInterior).biz == b, "interior rebuilt with fixtures")
	# 2 — the car: get in, drive a few seconds.
	var vid: String = e.vehicles[0]["id"]
	var car: Car = game.cars[vid]
	var cxf := car.global_transform
	await stand_at(cxf * Vector3(-car.spec["size"].x * 0.5 - 0.6, 0.0, -0.3))
	check(game.spot.get("kind") == "car_door", "DRIVE prompt at the driver's door (%s)" % game.spot.get("kind"))
	game.act()
	check(game.driving == vid, "in the car")
	var p0 := car.global_position
	Input.action_press("accelerate")
	await wait(2.5)
	Input.action_release("accelerate")
	var moved := car.global_position.distance_to(p0)
	check(moved > 4.0, "the car drives (%.1f m in 2.5 s)" % moved)
	Input.action_press("brake")
	await wait(2.0)
	Input.action_release("brake")
	# Teleport to the wholesaler's collection bay (route driving isn't scripted).
	var wsi: ShopInterior = game.interiors.get(w["id"])
	if wsi == null:
		wsi = game._build_interior(w)
	var bay := wsi.to_world(wsi.rack_pos)
	var out := Premises.outward(w)
	var park := game._kerb_point(bay + out * 5.0)
	car.place(Transform3D(Basis(Vector3.UP, atan2(out.x, out.z) + PI * 0.5), park + Vector3.UP * 0.2))
	await frames(90)
	game.exit_vehicle()
	check(game.driving == "", "got out at the wholesaler")
	# 3 — buy at the trade counter.
	var trade := spot_of("trade", wsi)
	await stand_at(trade["world"])
	check(game.spot.get("kind") == "trade", "TRADE COUNTER prompt (%s)" % game.spot.get("kind"))
	var order := {"crisps": 1, "choc_bar": 1, "cola": 1, "water": 1, "bread": 1, "milk": 1}
	var money0 := e.personal_cash + e.company_cash
	check(game.buy_wholesale(w, order) == "", "paid for 6 cases")
	var pal := game._pallet(w["id"])
	check(pal.cases_used() == 6, "6 cases on the collection bay (%d)" % pal.cases_used())
	check(money0 - (e.personal_cash + e.company_cash) > 50.0, "money left the account")
	# 4 — pick one case up by hand, then let the yard crew load the rest.
	var pspot := spot_of("pallet", wsi)
	await stand_at(pspot["world"])
	check(game.spot.get("kind") == "pallet", "COLLECTION BAY prompt (%s)" % game.spot.get("kind"))
	game.act()
	check(e.carried.cases_used() == 1, "carrying one case")
	var cargo: Stock = e.vehicles[0]["cargo"]
	await stand_at(car.global_transform * Vector3(0.0, 0.0, car.spec["size"].z * 0.5 + 0.8))
	check(game.spot.get("kind") == "car_boot", "BOOT prompt (%s)" % game.spot.get("kind"))
	game.act()  # load the carried case
	check(e.carried.is_empty() and cargo.cases_used() == 1, "case loaded into the boot")
	game.act()  # yard crew loads the bay
	check(pal.is_empty() and cargo.cases_used() == 6, "yard crew loaded the rest (boot %d, bay %d)" % [cargo.cases_used(), pal.cases_used()])
	var units_total := e.total_units()
	# 5 — drive back (teleport), unload, carry in, shelve.
	await stand_at(car.global_transform * Vector3(-car.spec["size"].x * 0.5 - 0.6, 0.0, -0.3))
	game.act()
	var sd := Premises.door_point(start)
	var so := Premises.outward(start)
	var sa := Premises.along_dir(start)
	car.place(Transform3D(Basis(Vector3.UP, atan2(-sa.x, -sa.z)), game._kerb_point(sd + so * 6.5) + Vector3.UP * 0.2))
	await frames(90)
	game.exit_vehicle()
	var ssi: ShopInterior = game.interiors[start["id"]]
	var shelved := 0
	for trip in 6:
		await stand_at(car.global_transform * Vector3(0.0, 0.0, car.spec["size"].z * 0.5 + 0.8))
		game.act()
		if e.carried.is_empty():
			break
		var pid: String = e.carried.units.keys()[0]
		var si := b.slot_for(pid)
		if si < 0:
			# No shelf for it: into the stockroom.
			await stand_at(ssi.to_world(ssi.rack_pos))
			game.act()
			continue
		await stand_at(ssi.to_world(ssi.slot_pick[si]))
		var before := b.shelf_units()
		game.act()
		shelved += b.shelf_units() - before
		if not e.carried.is_empty():
			await stand_at(ssi.to_world(ssi.rack_pos))
			game.act()
	check(shelved > 60, "carried goods in and filled shelves (%d units)" % shelved)
	check(e.total_units() == units_total, "no units created or lost moving them (%d)" % e.total_units())
	check(cargo.is_empty(), "boot emptied")
	# 6 — open at 10:00 and serve customers.
	e.minute = 10.0 * 60.0
	var tspot := spot_of("till", ssi, {"till": 0})
	await stand_at(tspot["world"])
	check(game.floor != null and game.floor.biz == b, "the shop runs live with the owner inside")
	var sales0 := int(e.stats["sales"])
	var t := 0.0
	var served_by_me := 0
	while t < 120.0 and served_by_me < 3:
		await wait(0.5)
		t += 0.5
		game._update_spot()
		if game.floor and int(t * 2) % 10 == 0:
			var st: Array = []
			for c in game.floor.customers:
				var pp: ShopPerson = c["p"]
				st.append("%s(%d) at %s arrived=%s pi=%d/%d" % [c["state"], (c["basket"] as Stock).total_units(), pp.position, pp.arrived(), pp._pi, pp.path.size()])
			print("AUTOPLAY dbg t=%.0f %s scanning=%s sales=%d spot=%s" % [t, st, game.floor.scanning.keys(), int(e.stats["sales"]), game.spot.get("kind")])
		if game.floor and game.floor.waiting_at(0):
			if game.player.global_position.distance_to(tspot["world"]) > 1.2:
				await stand_at(tspot["world"])
			game.act()
			served_by_me += 1
			await wait(4.0)
			t += 4.0
	check(int(e.stats["sales"]) > sales0, "served %d customer(s) at the till; %d sales" % [served_by_me, int(e.stats["sales"]) - sales0])
	check(float(b.today["revenue"]) > 0.0, "takings %.2f" % float(b.today["revenue"]))
	# 7 — hire a cashier: they serve without you.
	var cash_c := {}
	for c in e.candidates:
		if c["role"] == "cashier":
			cash_c = c
	check(not cash_c.is_empty(), "a cashier is looking for work")
	game.hire(b, cash_c)
	check(b.has_role("cashier") and game.floor.staff_people.size() == 1, "cashier hired and on the floor")
	await stand_at(ssi.to_world(ssi.office_pos))
	var s1 := int(e.stats["sales"])
	await wait(60.0)
	check(int(e.stats["sales"]) > s1, "the cashier served customers on their own (%d)" % (int(e.stats["sales"]) - s1))
	# 8 — an upgrade rebuilds the shop.
	e.company_cash += 1000.0
	check(game.buy_upgrade(b, "lighting") == "" and b.has_upgrade("lighting"), "bought LED lighting")
	# 9 — save, reload, compare.
	var units_before := e.total_units()
	var rev := float(b.lifetime["revenue"])
	game.save_game()
	game.load_game()
	var e2 := game.empire
	var b2 := e2.business_at(start["id"])
	check(b2 != null and b2.has_upgrade("lighting") and b2.has_role("cashier"), "reloaded: business, upgrade, staff")
	check(e2.total_units() == units_before and is_equal_approx(float(b2.lifetime["revenue"]), rev), "reloaded: stock %d, takings %.2f" % [e2.total_units(), rev])
	# 10 — buy a home, take the lift up, sleep.
	var homes := game.homes()
	check(homes.size() == 5, "five homes for sale (%d)" % homes.size())
	var studio: Dictionary = homes[0]
	await stand_at(game.home_lift(studio))
	check(game.spot.get("kind") == "home_lift", "FOR SALE prompt at the tower door (%s)" % game.spot.get("kind"))
	e2.personal_cash += float(studio["price"])
	var rec := studio.duplicate()
	rec.erase("h")
	check(e2.buy_property(rec), "bought %s" % studio["name"])
	game._update_spot()
	game.act()
	await frames(10)
	var up := Apartments.spawn_point(studio["h"])
	check(game.player.global_position.distance_to(up) < 1.5, "the lift took us up %d m" % int(studio["floor"]))
	game._update_spot()
	var bed := {}
	for sp in HomeInteriors.spots.get(String(studio["h"]["id"]), []):
		if sp["kind"] == "bed":
			bed = sp
	if not bed.is_empty():
		await stand_at(bed["pos"])
		check(game.spot.get("kind") == "home_bed", "SLEEP prompt at the bed (%s)" % game.spot.get("kind"))
		var d0 := e2.day
		game.act()
		check(e2.day == d0 + 1 and absf(e2.minute - 420.0) < 2.0, "slept till 07:00 next day (day %d %s)" % [e2.day, e2.clock_text()])
	# 11 — the day closes.
	game._end_floor()
	e2.advance(1440.0 - e2.minute + 1.0)
	check(b2.history.size() >= 1, "day report written (profit %.2f)" % (float(b2.history[-1]["profit"]) if not b2.history.is_empty() else 0.0))
	# 12 — city life: weather drives the sky, a rival store can be bought out.
	game._sync_weather()
	check(game.atmosphere.weather == String(CityLife.weather_def(e2.weather)["sky"]), "the sky follows today's weather (%s → %s)" % [e2.weather, game.atmosphere.weather])
	check(not e2.rivals.is_empty(), "QuikSave has stores in the city (%d)" % e2.rivals.size())
	var rv: Dictionary = e2.rivals[0]
	var ru: Dictionary = game.unit_by_id[rv["unit"]]
	await stand_at(Premises.door_point(ru) + Premises.outward(ru) * 1.5)
	await frames(40)
	var rsi: ShopInterior = game.interiors.get(rv["unit"])
	check(rsi != null and not rsi.rival.is_empty() and rsi.world_spots().is_empty(), "the rival store is drawn as QuikSave (no spots)")
	game._update_spot()
	check(game.spot.get("kind") == "letboard" and String(game.spot_prompt()[0]).begins_with("QUIKSAVE"), "BUY OUT prompt at its door (%s)" % game.spot_prompt()[0])
	e2.personal_cash += CityLife.rival_price(rv)
	check(game.buy_out_rival(ru) == "", "bought it out")
	var nb := e2.business_at(rv["unit"])
	await frames(40)
	var nsi: ShopInterior = game.interiors.get(rv["unit"])
	check(nb != null and nb.owned and nsi != null and nsi.rival.is_empty() and nsi.biz == nb, "it's ours now, interior rebuilt as our shop")
	print("AUTOPLAY DONE %d/%d passed" % [checks - fails, checks])
	get_tree().quit(fails)
