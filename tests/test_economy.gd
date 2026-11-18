extends RefCounted
## City Empire's economy, headless: inventory conservation, purchase/sale
## arithmetic, profit and expense accounting, shopper behaviour, staff,
## off-screen simulation, ownership/progression and save/load.

const STARTER := {"id": "test_unit", "name": "Test Unit", "shop_name": "Test Shop", "district": "west:suburb",
	"island": "west", "size": 100.0, "rent": 35.0, "price": 9000.0}


func _game(seed := 7) -> Empire:
	var e := Empire.new()
	e.new_game(seed)
	return e


## A shop with stock on every shelf, money in the bank and a cashier.
func _running_shop(e: Empire, with_cashier := true) -> Business:
	e.personal_cash = 5000.0
	var b := e.rent_premises(STARTER)
	e.transfer_to_company(2000.0)
	var order := {"crisps": 2, "choc_bar": 2, "cola": 2, "water": 2, "milk": 2, "bread": 2, "beans": 1, "gummies": 1,
		"energy": 1, "eggs": 1, "pasta": 1, "loo_roll": 1, "tea": 1, "washup": 1, "mints": 1, "pretzels": 1}
	e.buy_wholesale("w1", order)
	var pal: Stock = e.pallets["w1"]
	for pid in order:
		Stock.transfer(pal, b.backroom, pid, pal.qty(pid))
	e.restock_from_backroom(b, 1000)
	if with_cashier:
		var c: Dictionary = e.candidates.filter(func(x): return x["role"] == "cashier")[0]
		e.hire(b, c)
	return b


func _units_everywhere(e: Empire) -> int:
	return e.total_units()


# ------------------------------------------------------------ inventory
func test_stock_transfer_conserves_units_and_respects_capacity(t) -> void:
	var a := Stock.new(0)
	var b := Stock.new(2)  # two cases of room
	a.create("crisps", 100)  # 24 a case
	var moved := Stock.transfer(a, b, "crisps", 100)
	t.check(moved == 48, "two cases of crisps fit (moved %d)" % moved)
	t.check(a.qty("crisps") + b.qty("crisps") == 100, "no units created or lost")
	t.check(b.room_for("crisps") == 0 and b.cases_used() == 2, "full at two cases")
	t.check(Stock.transfer(a, b, "cola", 5) == 0, "nothing else fits")
	t.check(Stock.transfer(b, b, "crisps", 5) == 0, "transfer to itself does nothing")
	t.check(Stock.transfer(a, b, "crisps", -3) == 0, "negative transfers do nothing")
	var c := Stock.new(1)
	c.create("cola", 10)
	t.check(c.room_for("cola") == 14, "the open case's free room counts (%d)" % c.room_for("cola"))


func test_shelving_and_unshelving_conserve_units(t) -> void:
	var e := _game()
	e.personal_cash = 3000.0
	var b := e.rent_premises(STARTER)
	t.check(b != null, "rented the shop")
	e.buy_wholesale("w1", {"crisps": 2, "cola": 1})
	var before := _units_everywhere(e)
	t.check(before == 72, "bought 2×24 crisps + 24 cola (%d)" % before)
	var pal: Stock = e.pallets["w1"]
	Stock.transfer(pal, e.carried, "crisps", 48)
	var si := b.slot_for("crisps")
	t.check(si >= 0 and b.slots[si]["fixture"] == "shelf", "crisps go on a shelf slot")
	var n := b.shelve(e.carried, si, "crisps", 48)
	t.check(n == 30, "a shelf slot holds 30 (shelved %d)" % n)
	t.check(not b.can_hold(si, "cola"), "a shelf slot can't take fridge goods")
	var fi := b.slot_for("cola")
	t.check(fi >= 0 and b.slots[fi]["fixture"] == "fridge", "cola goes in the fridge")
	t.check(b.shelve(pal, fi, "cola", 24) == 24, "fridge slot filled")
	var basket := Stock.new()
	t.check(b.unshelve(basket, si, 5) == 5, "took 5 off the shelf")
	t.check(_units_everywhere(e) + basket.total_units() == before, "every unit accounted for")


func test_buying_wholesale_costs_the_right_amount(t) -> void:
	var e := _game()
	var cash := e.personal_cash
	var err := e.buy_wholesale("w1", {"crisps": 1, "cola": 2})
	var expect := 9.20 + 2.0 * 10.80
	t.check(err == "", "purchase ok (%s)" % err)
	t.check(is_equal_approx(cash - e.personal_cash, expect), "paid %.2f (expected %.2f)" % [cash - e.personal_cash, expect])
	t.check(e.stats["cases_bought"] == 3 and e.stats["units_bought"] == 72, "counted 3 cases / 72 units")
	e.personal_cash = 1.0
	t.check(e.buy_wholesale("w1", {"tea": 500}) != "", "can't buy without the money")
	t.check(e.stats["cases_bought"] == 3, "a refused purchase adds no stock")
	t.check(is_equal_approx(e.unit_cost("crisps"), 9.20 / 24.0), "unit cost from the case price")


# -------------------------------------------------------------- selling
func test_checkout_arithmetic_and_cogs(t) -> void:
	var e := _game()
	var b := _running_shop(e, false)
	b.set_price("crisps", 1.0)
	b.set_price("cola", 1.5)
	var basket := Stock.new()
	b.unshelve(basket, b.slot_with("crisps"), 2)
	b.unshelve(basket, b.slot_with("cola"), 1)
	var cash := e.company_cash
	var total := e.checkout(b, basket)
	t.check(is_equal_approx(total, 3.5), "2×£1 + £1.50 = £3.50 (got %.2f)" % total)
	var fee := 3.5 * 0.015 * 0.6
	t.check(is_equal_approx(e.company_cash - cash, 3.5 - fee), "takings minus card fees banked")
	var cogs := 2.0 * e.unit_cost("crisps") + e.unit_cost("cola")
	t.check(is_equal_approx(float(b.today["cogs"]), cogs), "cost of goods sold recorded (%.3f)" % float(b.today["cogs"]))
	t.check(basket.is_empty(), "the basket left with the customer")
	t.check(e.stats["units_sold"] == 3 and e.stats["sales"] == 1, "sale counted")
	t.check(e.goals_done.has("first_sale"), "first-sale milestone done")


func test_prices_are_clamped(t) -> void:
	var e := _game()
	var b := _running_shop(e, false)
	b.set_price("cola", 999.0)
	t.check(b.price("cola") <= EmpireData.rrp("cola") * 3.0 + 0.001, "max 3× RRP")
	b.set_price("cola", -5.0)
	t.check(b.price("cola") >= EmpireData.rrp("cola") * 0.4 - 0.05, "min 40% RRP")


# ------------------------------------------------------------ shoppers
func test_demand_falls_with_price(t) -> void:
	var e := _game()
	var b := _running_shop(e, false)
	var r := EmpireData.rrp("cola")
	var s1 := DemandModel.buy_share(b, "cola", r * 0.8)
	var s2 := DemandModel.buy_share(b, "cola", r)
	var s3 := DemandModel.buy_share(b, "cola", r * 1.3)
	var s4 := DemandModel.buy_share(b, "cola", r * 2.0)
	t.check(s1 >= s2 and s2 > s3 and s3 > s4, "share falls with price (%.2f %.2f %.2f %.2f)" % [s1, s2, s3, s4])
	t.check(s1 > 0.95 and s4 == 0.0, "cheap sells to nearly all, double RRP to nobody here")
	# Empirical: the decision function agrees with the analytic share.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	b.set_price("cola", r * 1.15)
	var bought := 0
	var asked := 0
	for i in 2000:
		var sh := DemandModel.make_shopper(b, rng)
		sh["wants"] = ["cola"]
		sh["wtp"] = {"cola": EmpireData.rrp("cola") * float(b.district()["affluence"]) * rng.randf_range(0.9, 1.7)}
		asked += 1
		if DemandModel.decide(b, sh, "cola")["result"] == "buy":
			bought += 1
	var share := float(bought) / asked
	var expect := DemandModel.buy_share(b, "cola", b.price("cola"))
	t.check(absf(share - expect) < 0.05, "simulated share %.2f ≈ model %.2f" % [share, expect])


func test_shopper_outcomes_stockout_and_not_stocked(t) -> void:
	var e := _game()
	var b := _running_shop(e, false)
	var sh := {"wants": ["batteries"], "wtp": {"batteries": 10.0}, "seed": 1}
	t.check(DemandModel.decide(b, sh, "batteries")["result"] == "not_stocked", "the shop doesn't sell batteries")
	var si := b.slot_with("bread")
	var sink := Stock.new()
	while b.slot_with("bread") >= 0:
		b.unshelve(sink, b.slot_with("bread"), 99)
	sh = {"wants": ["bread"], "wtp": {"bread": 10.0}, "seed": 1}
	t.check(si >= 0 and DemandModel.decide(b, sh, "bread")["result"] == "stockout", "empty bread shelf = stockout")
	b.set_price("milk", EmpireData.rrp("milk") * 3.0)
	sh = {"wants": ["milk"], "wtp": {"milk": EmpireData.rrp("milk")}, "seed": 1}
	t.check(DemandModel.decide(b, sh, "milk")["result"] == "too_expensive", "3× price is too expensive")


func test_reputation_reacts_to_service(t) -> void:
	var e := _game()
	var b := _running_shop(e)
	var r0 := b.reputation
	for i in 40:
		e.visit_offscreen(b)
	t.check(b.reputation > r0, "well-stocked, fairly priced visits raise reputation (%.1f → %.1f)" % [r0, b.reputation])
	for s: Dictionary in b.slots:
		s["qty"] = 0  # (test: wipe shelves – not a conservation check)
	var r1 := b.reputation
	for i in 40:
		e.visit_offscreen(b)
	t.check(b.reputation < r1, "empty shelves cost reputation (%.1f → %.1f)" % [r1, b.reputation])


# ----------------------------------------------------------- the day
func test_full_day_offscreen_conserves_stock_and_books_balance(t) -> void:
	var e := _game(11)
	var b := _running_shop(e)
	var bought := int(e.stats["units_bought"])
	var company0 := e.company_cash
	var personal0 := e.personal_cash
	var day0 := e.day
	e.advance(1440.0 - e.minute)  # to midnight: the day's books close
	t.check(e.day == day0 + 1, "a day passed")
	var rep: Dictionary = b.history[-1]
	t.check(int(rep["served"]) > 20, "a cashier served shoppers all day (%d)" % int(rep["served"]))
	var here := e.total_units() + int(e.stats["units_sold"]) + int(e.stats["units_stolen"])
	t.check(here == bought, "units: held %d + sold %d + stolen %d == bought %d" % [e.total_units(),
		e.stats["units_sold"], e.stats["units_stolen"], bought])
	# Company account moved by exactly takings − fees − wages − rent − utilities − interest.
	var expect: float = company0 + float(rep["revenue"]) - float(rep["fees"]) - float(rep["wages"]) - float(rep["rent"]) \
		- float(rep["utilities"])
	t.check(absf(e.company_cash - expect) < 0.05, "company cash %.2f == expected %.2f" % [e.company_cash, expect])
	t.check(is_equal_approx(e.personal_cash, personal0), "personal savings untouched")
	var profit: float = float(rep["revenue"]) - float(rep["cogs"]) - float(rep["wages"]) - float(rep["rent"]) \
		- float(rep["utilities"]) - float(rep["fees"]) - float(rep["theft"])
	t.check(absf(profit - float(rep["profit"])) < 0.01, "report profit = revenue − COGS − costs")
	t.check(float(rep["wages"]) > 60.0, "a full shift of wages was paid (%.2f)" % float(rep["wages"]))


func test_unattended_shop_without_staff_does_not_trade(t) -> void:
	var e := _game()
	var b := _running_shop(e, false)
	e.advance(12.0 * 60.0)
	t.check(int(b.today["customers"]) == 0 and e.stats["sales"] == 0, "nobody can be served: no trade")
	b.live = true  # the owner is in the shop
	e.minute = 10.0 * 60.0
	e.advance(60.0)
	t.check(b.pending_arrivals > 0, "with the owner there, shoppers arrive as walking agents (%d)" % b.pending_arrivals)


func test_overpriced_expensive_shop_loses_money_good_shop_profits(t) -> void:
	# Same premises and stock, four days each: an established shop
	# (reputation 70) with fair prices and one cashier vs gouging with idle staff.
	var good := _game(21)
	var gb := _running_shop(good)
	gb.reputation = 70.0
	var bad := _game(21)
	var bb := _running_shop(bad)
	bb.reputation = 70.0
	for pid in EmpireData.product_ids():
		bb.set_price(pid, EmpireData.rrp(pid) * 2.4)
	# The bad one also hires a full team it can't use.
	for c in bad.candidates.duplicate():
		if c["role"] != "cashier":
			bad.hire(bb, c)
	var gp := 0.0
	var bp := 0.0
	for d in 4:
		_restock(good, gb)
		_restock(bad, bb)
		good.advance(1440.0)
		bad.advance(1440.0)
		gp += float(gb.history[-1]["profit"])
		bp += float(bb.history[-1]["profit"])
		print("        good day: ", _brief(gb.history[-1]), "\n        bad day:  ", _brief(bb.history[-1]))
	t.check(gp > 0.0, "fair prices + one cashier make money (%.0f over 4 days)" % gp)
	t.check(bp < 0.0, "gouging with idle staff loses money (%.0f over 4 days)" % bp)
	t.check(gb.reputation > bb.reputation, "and reputation follows (%.0f vs %.0f)" % [gb.reputation, bb.reputation])


func _brief(r: Dictionary) -> String:
	return "rev %.0f cogs %.0f wages %.0f rent %.0f util %.0f theft %.0f → %.0f | cust %d served %d stockout %d notst %d dear %d out %d rep %.0f" % [
		r["revenue"], r["cogs"], r["wages"], r["rent"], r["utilities"], r["theft"], r["profit"], r["customers"],
		r["served"], r["stockouts"], r["not_stocked"], r["too_expensive"], r["walked_out"], r["reputation"]]


func _restock(e: Empire, b: Business) -> void:
	var order := {}
	for pid in b.stocked_products():
		if b.shelf_qty(pid) + b.backroom.qty(pid) < 30:
			order[pid] = 1
	if order.is_empty():
		return
	if e.buy_wholesale("w1", order) == "":
		var pal: Stock = e.pallets["w1"]
		for pid in order:
			Stock.transfer(pal, b.backroom, pid, pal.qty(pid))
	e.restock_from_backroom(b, 1000)


# --------------------------------------------------------------- staff
func test_staff_wages_skill_and_effects(t) -> void:
	var e := _game()
	var b := _running_shop(e, false)
	var st: Dictionary = e.candidates.filter(func(x): return x["role"] == "stocker")[0]
	t.check(st["wage"] >= 4.0 and st["wage"] <= 10.0, "stocker wage in range (%.2f)" % st["wage"])
	t.check(e.hire(b, st), "hired the stocker")
	t.check(not e.hire(b, st), "can't hire the same person twice")
	# Empty the shelves into the back room; the stocker puts it back.
	for i in b.slots.size():
		b.unshelve(b.backroom, i, 99)
	t.check(b.shelf_units() == 0, "shelves emptied")
	e.minute = 9.0 * 60.0
	e.advance(60.0)
	t.check(b.shelf_units() > 50, "an hour's stocking (%d units)" % b.shelf_units())
	var cl: Dictionary = e.candidates.filter(func(x): return x["role"] == "cleaner")[0]
	e.hire(b, cl)
	b.cleanliness = 0.2
	e.advance(60.0)
	t.check(b.cleanliness > 0.4, "the cleaner cleans (%.2f)" % b.cleanliness)
	var w := b.wages_per_hour()
	t.check(is_equal_approx(w, float(st["wage"]) + float(cl["wage"])), "wage bill per hour")
	var cash := e.company_cash
	e.fire(b, cl)
	t.check(e.company_cash < cash and b.staff.size() == 1, "firing pays notice and removes them")


func test_manager_reorders_and_delivery_arrives(t) -> void:
	var e := _game()
	var b := _running_shop(e)
	var m: Dictionary = e.candidates.filter(func(x): return x["role"] == "manager")[0]
	e.hire(b, m)
	var sink := Stock.new()
	for i in b.slots.size():
		b.unshelve(sink, i, 99)
	for pid in b.backroom.units.keys():
		Stock.transfer(b.backroom, sink, pid, 999)
	e.company_cash = 3000.0
	e.minute = 21.0 * 60.0
	e.advance(10.0)
	t.check(not b.orders.is_empty(), "the manager ordered stock at closing")
	var bought0 := int(e.stats["units_bought"])
	e.minute = 23.0 * 60.0 + 59.0
	e.advance(7.0 * 60.0)
	t.check(b.orders.is_empty() and b.backroom.total_units() > 0, "the delivery arrived by 06:00")
	t.check(int(e.stats["units_bought"]) > bought0, "delivered units counted as bought")


# ------------------------------------------------------- ownership etc
func test_rent_buy_upgrade_and_progression(t) -> void:
	var e := _game()
	t.check(e.rent_premises(STARTER) != null, "rent with starting savings")
	t.check(e.rent_premises(STARTER) == null, "can't rent the same unit twice")
	t.check(e.goals_done.has("rent_shop"), "milestone: first shop")
	var b: Business = e.businesses[0]
	t.check(b.rent_per_day() == 35.0, "rent is charged")
	e.personal_cash = 20000.0
	t.check(e.buy_premises(STARTER) == b and b.owned and b.rent_per_day() == 0.0, "buying the freehold stops the rent")
	var shelves := b.slot_indices("shelf").size()
	t.check(e.buy_upgrade(b, "shelf_2") == "" and b.slot_indices("shelf").size() == shelves + 6, "extra shelving adds 6 slots")
	t.check(e.buy_upgrade(b, "shelf_2") != "", "an upgrade can't be bought twice")
	t.check(e.buy_upgrade(b, "coffee") == "" and b.slot_indices("coffee").size() == 1, "coffee machine adds the coffee slot")
	t.check(b.slots[b.slot_indices("coffee")[0]]["product"] == "coffee", "its slot sells coffee")
	t.check(e.goals_done.has("first_upgr"), "milestone: upgrade")
	var nw := e.net_worth()
	t.check(nw > 9000.0, "net worth counts the freehold (%.0f)" % nw)


func test_loans_and_overdraft(t) -> void:
	var e := _game()
	var lim := e.loan_limit()
	t.check(lim >= 1500.0, "a starter loan is always on offer (%.0f) – no softlock" % lim)
	t.check(e.take_loan(1500.0) and e.company_cash == 1500.0, "loan paid into the company")
	t.check(not e.take_loan(1e7), "can't borrow beyond the limit")
	var c := e.company_cash
	e.end_day()
	t.check(e.company_cash < c, "interest charged daily")
	t.check(e.repay_loan(e.loans[0], 1500.0) and e.loans.is_empty(), "repaid")


func test_vehicle_cargo_capacity_and_wear(t) -> void:
	var e := _game()
	var v: Dictionary = e.vehicles[0]
	var cargo: Stock = v["cargo"]
	t.check(cargo.case_capacity == 8, "the hatch carries 8 cases")
	e.personal_cash = 5000.0
	e.buy_wholesale("w1", {"crisps": 10})
	var pal: Stock = e.pallets["w1"]
	var moved := Stock.transfer(pal, cargo, "crisps", 240)
	t.check(moved == 8 * 24 and pal.qty("crisps") == 48, "8 cases loaded, 2 left on the bay")
	t.check(Stock.transfer(pal, e.carried, "crisps", 999) == 48, "carry the rest (3 cases max = 72 units room)")
	e.drive(v, 50.0)
	t.check(float(v["condition"]) < 1.0 and float(v["km"]) == 50.0, "driving wears the car")
	t.check(e.service_vehicle(v) == "" and float(v["condition"]) == 1.0, "service restores it")
	e.personal_cash = 20000.0
	var van := e.buy_vehicle("van", Vector3.ZERO, 0.0)
	t.check(not van.is_empty() and (van["cargo"] as Stock).case_capacity == 30, "the courier van carries 30 cases")


# ---------------------------------------------------------------- save
func test_save_round_trip_preserves_everything(t) -> void:
	var e := _game(5)
	var b := _running_shop(e)
	e.buy_upgrade(b, "lighting")
	b.set_price("cola", 1.55)
	e.advance(300.0)
	e.carried.create("crisps", 0)
	var d := e.to_dict()
	var json := JSON.stringify(d)
	var back = JSON.parse_string(json)
	var e2 := Empire.from_dict(back)
	t.check(e2.day == e.day and absf(e2.minute - e.minute) < 0.01, "clock")
	t.check(absf(e2.company_cash - e.company_cash) < 0.01 and absf(e2.personal_cash - e.personal_cash) < 0.01, "money")
	t.check(e2.total_units() == e.total_units(), "every unit (%d vs %d)" % [e2.total_units(), e.total_units()])
	var b2: Business = e2.businesses[0]
	t.check(b2.has_upgrade("lighting") and is_equal_approx(b2.price("cola"), 1.55), "upgrades and prices")
	t.check(b2.staff.size() == b.staff.size() and b2.staff[0]["name"] == b.staff[0]["name"], "staff")
	t.check(b2.shelf_units() == b.shelf_units() and b2.slots.size() == b.slots.size(), "shelves")
	t.check(e2.stats["units_sold"] == e.stats["units_sold"], "stats")
	# Both carry on identically (rng state saved too).
	e.advance(600.0)
	e2.advance(600.0)
	t.check(absf(e.company_cash - e2.company_cash) < 0.01, "the loaded game continues identically")


func test_old_save_migrates(t) -> void:
	var old := {"version": 1, "seed": 3, "day": 4, "minute": 600.0, "cash": 1234.0, "businesses": [], "vehicles": []}
	var e := Empire.from_dict(old)
	t.check(e.personal_cash == 1234.0 and e.company_cash == 0.0, "v1 cash → personal savings")
	t.check(e.day == 4 and e.stats.has("units_sold"), "missing stats filled in")
	t.check(int(e.to_dict()["version"]) == Empire.VERSION, "saved at the current version")


func test_v5_save_moves_skyport_things(t) -> void:
	# (v6: Skyport Island moved south of the strait; old world = its local.)
	var old := {"version": 5, "vehicles": [
		{"id": "a", "model": "heli", "pos": [1585.0, 3.0, 205.0], "yaw": PI},
		{"id": "b", "model": "hatch", "pos": [500.0, 2.0, 100.0], "yaw": 0.3},
		{"id": "c", "model": "hatch", "pos": [1200.0, 20.0, -30.0], "yaw": 0.0}],
		"flags": {"gps": [1678.0, 3.0, 4.0]}}
	var d := Empire.migrate(old)
	var a: Array = d["vehicles"][0]["pos"]
	var want := SkyportIsland.w(Vector3(1585, 3, 205))
	t.check(Vector3(a[0], a[1], a[2]).distance_to(want) < 0.01, "a helicopter on its pad moves with the island")
	t.check(is_equal_approx(float(d["vehicles"][0]["yaw"]), SkyportIsland.wyaw(PI)), "and turns with it")
	t.check(d["vehicles"][1]["pos"] == [500.0, 2.0, 100.0], "a car in the city stays put")
	var c: Array = d["vehicles"][2]["pos"]
	var cq := Vector3(c[0], c[1], c[2])
	t.check(SkyportIsland.l(cq).x > SkyportIsland.QUAY_X, "a car on the old bridge lands on the island (%s)" % cq)
	var g: Array = d["flags"]["gps"]
	t.check(Vector3(g[0], g[1], g[2]).distance_to(SkyportIsland.w(Vector3(1678, 3, 4))) < 0.01, "the GPS target moves too")
	t.check(int(d["version"]) == 6, "now v6")


func test_offscreen_fast_forward_is_cheap(t) -> void:
	var e := _game()
	var b := _running_shop(e)
	var s2 := STARTER.duplicate()
	s2["id"] = "u2"
	e.personal_cash += 1000.0
	var b2 := e.rent_premises(s2)
	var rng := RandomNumberGenerator.new()
	var c2 := Staff.make(rng, "cashier", e.day, 99)
	e.candidates.append(c2)
	e.hire(b2, c2)
	var t0 := Time.get_ticks_usec()
	e.advance(7.0 * 1440.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	t.check(ms < 1500.0, "a week of two shops simulates in %.0f ms" % ms)
	t.check(e.day == 8 and b.history.size() == 7, "seven reports")


func test_money_format(t) -> void:
	t.check(EmpireData.money(1234.4) == "£1,234", "thousands")
	t.check(EmpireData.money(1.999, true) == "£2.00", "pence rounding")
	t.check(EmpireData.money(-35.0) == "-£35", "negative")


# ------------------------------------------------- one-tap stock, hiring
func test_shops_only_sell_what_they_have_a_place_for(t) -> void:
	var e := _game()
	e.personal_cash = 9000.0
	var bakery := e.rent_premises(STARTER, "bakery")
	t.check(bakery.sells("croissant") and bakery.sells("bread"), "a bakery sells bakes and bread")
	t.check(not bakery.sells("beans") and not bakery.sells("pasta"), "a bakery doesn't sell tins or pasta")
	t.check(not bakery.sells("milk"), "no fridge, no milk")
	t.check(not bakery.sells("coffee"), "no coffee until it has a machine")
	bakery.apply_upgrade("coffee")
	t.check(bakery.sells("coffee"), "the coffee machine adds coffee")


func test_restock_pack_fills_every_slot_and_counts_what_is_there(t) -> void:
	for type_id in ["convenience", "clothing", "cafe", "takeaway", "bakery", "phones"]:
		var e := _game()
		e.personal_cash = 900000.0
		var b := e.rent_premises(STARTER, type_id)
		var plan := e.restock_plan(b, false)
		t.check(int(plan["count"]) > 0 and plan["short"] == "", "%s: a top-up for an empty shop (%d cases)" % [type_id, int(plan["count"])])
		t.check((plan["cases"] as Dictionary).keys().all(func(p): return b.sells(p)), "%s: only its own goods" % type_id)
		# Deliver it and put it out: every slot is then showing something.
		e.order_delivery(b, plan["cases"])
		e.minute = 23.0 * 60.0 + 59.0
		e.advance(7.0 * 60.0)
		e.restock_from_backroom(b, 99999)
		var empty := b.slots.filter(func(s): return int(s["qty"]) == 0).size()
		var low := b.slots.filter(func(s): return int(s["qty"]) < int(s["cap"])).size()
		t.check(empty == 0, "%s: no empty slot after the top-up (%d empty, %d not full)" % [type_id, empty, low])
		var again := e.restock_plan(b, false)
		t.check(int(again["count"]) <= 1, "%s: a second top-up has nothing to add (%d)" % [type_id, int(again["count"])])
		var full := e.restock_plan(b, true)
		t.check(int(full["count"]) > 0, "%s: a full restock still adds stockroom cases (%d)" % [type_id, int(full["count"])])
		t.check(b.backroom.cases_used() + int(full["count"]) <= b.backroom.case_capacity + 1, "%s: …that fit the stockroom" % type_id)


func test_restock_pack_respects_space_and_money_with_a_spread(t) -> void:
	var e := _game()
	e.personal_cash = 900000.0
	var b := e.rent_premises(STARTER)
	var plan := e.restock_plan(b, true, 6)
	t.check(int(plan["count"]) == 6 and plan["short"] == "space", "cut to 6 cases")
	t.check((plan["cases"] as Dictionary).size() == 6, "six different lines, not six of one (%s)" % [plan["cases"]])
	var cheap := e.restock_plan(b, true, 9999, 40.0)
	t.check(float(cheap["cost"]) <= 40.0 and int(cheap["count"]) > 0 and cheap["short"] == "money", "cut to £40 (%s)" % EmpireData.money(float(cheap["cost"]), true))
	# Stock already in the van counts.
	var all := e.restock_plan(b, false)
	var less := e.restock_plan(b, false, 9999, INF, {"crisps": 500})
	t.check(not (less["cases"] as Dictionary).has("crisps") and int(less["count"]) < int(all["count"]), "crisps in the van aren't bought again")


func test_plenty_of_people_looking_for_work(t) -> void:
	var e := _game()
	t.check(e.candidates.size() >= 15, "a long list every day (%d)" % e.candidates.size())
	for r in EmpireData.roles():
		var n := e.candidates.filter(func(c): return c["role"] == r).size()
		t.check(n >= 3, "%d people want to be a %s" % [n, r])
		t.check(not e.best_candidate(r).is_empty(), "a best %s to hire" % r)
	var e2 := _game()
	e2.personal_cash = 9000.0
	var b := e2.rent_premises(STARTER)
	for i in 3:
		t.check(e2.hire(b, e2.best_candidate("cashier")), "hired cashier %d" % (i + 1))
	e2.end_day()
	t.check(e2.candidates.filter(func(c): return c["role"] == "cashier").size() >= 3, "fresh cashiers the next morning")


# ------------------------------------------------- Skyport estates (audit)
## Buying a building and selling it straight back must lose money (it
## made 0.7% a flip on the warehouse and hangar: an endless money loop),
## and the buildings must count in net worth (they were left out, so a
## £1.6M hotel looked like £1.6M lost).
func test_estates_no_flip_profit_and_count_in_net_worth(t) -> void:
	var e := _game()
	e.personal_cash = 5000000.0
	for d in Ventures.ESTATES:
		var id := String(d["id"])
		var worth0 := e.net_worth()
		t.check(Ventures.buy_estate(e, id) == "", "bought %s" % id)
		var after := e.net_worth()
		t.check(after <= worth0 + 0.01, "%s: buying doesn't create money (%.0f → %.0f)" % [id, worth0, after])
		t.check(after > worth0 - float(d["price"]) * 0.5, "%s counts in net worth (%.0f → %.0f)" % [id, worth0, after])
		var cash0 := e.personal_cash + e.company_cash
		Ventures.sell_estate(e, id)
		var cash1 := e.personal_cash + e.company_cash
		t.check(cash1 < cash0 + float(d["price"]), "%s: selling straight back is a loss" % id)


## Renovations: only when it needs one, and the rent rises only for the first few.
func test_renovation_needs_wear_and_rent_rise_is_capped(t) -> void:
	var e := _game()
	e.personal_cash = 5000000.0
	Ventures.buy_estate(e, "marina_quay")
	t.check(Ventures.renovate(e, "marina_quay") == "", "renovated a worn building")
	t.check(Ventures.renovate(e, "marina_quay") != "", "can't renovate one already in top condition")
	var st: Dictionary = e.flags["estates"]["marina_quay"]
	var d := Ventures.estate_def("marina_quay")
	st["renovated"] = 20
	var capped := Ventures.unit_rent(d, st)
	st["renovated"] = Ventures.MAX_RENOVATIONS
	t.check(is_equal_approx(capped, Ventures.unit_rent(d, st)), "rent stops rising after %d renovations" % Ventures.MAX_RENOVATIONS)


## The day's profit includes the Skyport ventures (estate rent and upkeep,
## dealership, hangar and marina fees): it left them out.
func test_day_profit_includes_ventures(t) -> void:
	var e := _game()
	e.personal_cash = 5000000.0
	Ventures.buy_estate(e, "logistics")   # (upkeep only, no rent)
	var got := []
	e.day_ended.connect(func(r): got.append(r))
	e.end_day()
	var r: Dictionary = got[0]
	t.check(float(r["profit"]) < 0.0, "the warehouse's upkeep is in the day's profit (%.0f)" % float(r["profit"]))
