extends RefCounted
## The commercial empire layer (2026-11-27), headless: business levels,
## warehouse + fleet + contracts, the trade loops (food, clothing, club, car
## hire, hotel), company divisions and career stages, and their saves.


func _market() -> Array:
	var m: Array = []
	for i in 36:
		var dk := "west:suburb" if i < 12 else ("east:midtown" if i < 24 else "east:cbd")
		m.append({"id": "u%d" % i, "kind": "shop", "name": "Unit %d" % i, "shop_name": "Shop %d" % i, "district": dk,
			"island": dk.get_slice(":", 0), "size": 100.0, "rent": 30.0, "price": 7000.0, "pos": [i * 80.0, 0.0, 0.0]})
	m.append({"id": "w_west", "kind": "wholesale", "name": "Cash & Carry", "district": "west:suburb", "island": "west",
		"size": 400.0, "rent": 0.0, "price": 0.0, "pos": [-200.0, 0.0, 0.0]})
	return m


func _game(seed := 11) -> Empire:
	var e := Empire.new()
	e.market = _market()
	e.flags["start_unit"] = "u0"
	e.new_game(seed)
	e.personal_cash = 2000000.0
	e.transfer_to_company(1500000.0)
	return e


## Rents the first free unit in unit i's district (the city's independents
## and rivals already occupy some).
func _shop(e: Empire, i: int, type_id := "convenience") -> Business:
	var dk := String(e.market[i * 3]["district"])
	for u: Dictionary in e.market:
		if u["district"] == dk and u.get("kind", "") == "shop" and u["id"] != "u0" and e.business_at(u["id"]) == null and not CityLife.is_taken(e, u["id"]):
			return e.rent_premises(u, type_id)
	return null


func _stock_shop(e: Empire, b: Business) -> void:
	var plan := e.restock_plan(b, false)
	e.buy_wholesale("w1", plan["cases"])
	var pal: Stock = e.pallets["w1"]
	for pid in plan["cases"]:
		Stock.transfer(pal, b.backroom, pid, pal.qty(pid))
	e.restock_from_backroom(b, 100000)


func _hire(e: Empire, b: Business, role: String) -> void:
	var c: Array = e.candidates.filter(func(x): return x["role"] == role)
	if c.is_empty():
		e.candidates = Staff.candidates(e.day + 50, e.seed)
		c = e.candidates.filter(func(x): return x["role"] == role)
	e.hire(b, c[0])


func _days(e: Empire, n: int) -> void:
	for i in n:
		e.advance(1440.0)


# ------------------------------------------------------------------ levels
func test_levels_need_requirements_and_change_the_shop(t) -> void:
	var e := _game()
	var b := _shop(e, 1)
	t.check(b.level == 1, "a new shop is an independent")
	t.check(Growth.block(e, b) != "", "can't grow without upgrades/staff/history")
	var cap0: int = b.slots[0]["cap"]
	var shelves0 := int(b.fixtures.get("shelf", 0))
	var back0 := b.backroom.case_capacity
	var ff0 := b.footfall_bonus()
	var q0 := b.quality_bonus()
	for u in ["lighting", "signage", "floor"]:
		e.buy_upgrade(b, u)
	_hire(e, b, "cashier")
	_hire(e, b, "stocker")
	_stock_shop(e, b)
	_days(e, 4)
	b.reputation = 60.0
	if Growth._sum7(b, "profit") <= 0.0:
		b.history.append({"profit": 500.0, "revenue": 900.0})
	var why := Growth.block(e, b)
	t.check(why == "", "requirements met (%s)" % why)
	var cash := e.company_cash
	var err := Growth.grow(e, b)
	t.check(err == "" and b.level == 2, "grew to Established (%s)" % err)
	t.near(cash - e.company_cash, Growth.cost(b, 2), 0.5, "the fit-out is paid from the company")
	t.check(int(b.fixtures.get("shelf", 0)) == shelves0 + 1, "the fit-out adds a shelf unit")
	t.check(int(b.slots[0]["cap"]) > cap0, "deeper shelves (%d → %d)" % [cap0, int(b.slots[0]["cap"])])
	t.check(b.backroom.case_capacity > back0, "a bigger stockroom")
	t.check(b.footfall_bonus() > ff0 and b.quality_bonus() > q0, "more shoppers, nicer shop")


func test_level_three_automates_and_four_needs_a_chain(t) -> void:
	var e := _game()
	var b := _shop(e, 1)
	Growth.apply_level(b, 3)
	t.check(Growth.automated(b), "a major retailer re-orders itself")
	t.check(b.tills() >= 2, "self-checkout till")
	b.reputation = 90.0
	for i in 7:
		b.history.append({"profit": 2000.0, "revenue": 3000.0})
	t.check(Growth.block(e, b).begins_with("Needs"), "a flagship needs a head office and branches")
	_shop(e, 2)
	_shop(e, 3)
	t.check(e.buy_hq(1) == "", "head office")
	t.check(Growth.block(e, b) == "", "requirements met with HQ + 3 branches (%s)" % Growth.block(e, b))
	var other: Business = e.businesses[1]
	var before := other.footfall_bonus()
	var w0 := e.case_price("cola")
	Growth.grow(e, b)
	t.check(b.level == 4, "corporate flagship")
	t.check(other.footfall_bonus() > before, "the flagship lifts the other branches")
	t.check(e.case_price("cola") < w0, "and the chain buys cheaper")


func test_level_survives_save(t) -> void:
	var e := _game()
	var b := _shop(e, 1, "clothing")
	Growth.apply_level(b, 2)
	Trades.launch(e, b, "street")
	var e2 := Empire.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	var b2: Business = e2.businesses[0]
	t.check(b2.level == 2, "level")
	t.check(b.fixtures.keys().all(func(k): return int(b2.fixtures.get(k, -1)) == int(b.fixtures[k])), "fit-out %s vs %s" % [b2.fixtures, b.fixtures])
	t.check(String(b2.trade.get("collection", "")) == "street", "trade state")
	t.check(b2.slots.size() == b.slots.size() and int(b2.slots[0]["cap"]) == int(b.slots[0]["cap"]), "slots")


# ------------------------------------------------------------ supply chain
func test_warehouse_fleet_delivers_to_branches(t) -> void:
	var e := _game()
	var a := _shop(e, 1)
	var b := _shop(e, 2)
	t.check(SupplyChain.buy_site(e, "west_depot") == "", "bought the depot")
	t.check(SupplyChain.position(e).size() == 3, "the depot sits by the cash & carry")
	var order := SupplyChain.suggested_order(e)
	t.check(not order.is_empty(), "a suggested order for the branches")
	var units0 := e.total_units()
	t.check(SupplyChain.stock_up(e, order) == "", "stocked the warehouse")
	t.check(e.total_units() > units0, "stock counted in the empire")
	t.check(SupplyChain.case_cost(e, "cola") < e.case_price("cola"), "contract prices beat the cash & carry")
	var v := e.buy_vehicle("van", Vector3.ZERO, 0.0)
	t.check(SupplyChain.toggle_fleet(e, String(v["id"])) == "", "van on the rounds")
	t.check(e.delivery_fee(a) == 0.0, "served branches pay no delivery fee")
	var held0 := e.total_units()
	var back_a := a.backroom.total_units() + b.backroom.total_units()
	var arrived := []
	e.fleet_arrived.connect(func(biz, vid): arrived.append(biz.id))
	# Run the morning round.
	e.minute = 5.0 * 60.0 + 55.0
	e.advance(240.0)
	t.check(a.backroom.total_units() + b.backroom.total_units() > back_a, "branches received stock (%d → %d)" % [back_a, a.backroom.total_units() + b.backroom.total_units()])
	t.check(e.total_units() == held0, "no units made or lost on the road")
	t.check(not arrived.is_empty(), "the world hears the van arrive")
	t.check(float(v["km"]) > 0.0, "the van drove the round")
	t.check(int(SupplyChain.fleet(e)[String(v["id"])]["runs"]) >= 1, "round counted")


func test_contracts_ship_from_the_warehouse(t) -> void:
	var e := _game()
	_shop(e, 1)
	SupplyChain.buy_site(e, "west_depot")
	var v := e.buy_vehicle("van", Vector3.ZERO, 0.0)
	SupplyChain.toggle_fleet(e, String(v["id"]))
	var o := SupplyChain._make_offer(e)
	o["days"] = 2
	o["cases"] = 3
	SupplyChain.state(e)["offers"] = [o]
	t.check(SupplyChain.accept(e, String(o["id"])) == "", "signed")
	SupplyChain.stock_up(e, {o["pid"]: 10})
	var rev0 := float(e.stats.get("contracts_done", 0))
	_days(e, 3)
	t.check(float(e.stats.get("contracts_done", 0)) == rev0 + 1.0, "contract completed in full")
	t.check(SupplyChain.stock(e).qty(o["pid"]) == 4 * EmpireData.case_qty(o["pid"]), "six cases left the warehouse")


# ------------------------------------------------------------------ trades
func test_food_supplier_changes_cost_and_quality(t) -> void:
	var e := _game()
	var b := _shop(e, 5, "cafe")
	var q0 := b.quality_bonus()
	Trades.set_supplier(e, b, "premium")
	t.check(b.quality_bonus() > q0, "artisan range is nicer")
	b.today["cogs"] = 100.0
	var cash := e.company_cash
	Trades.before_day_end(e)
	t.near(cash - e.company_cash, 22.0, 0.01, "and costs 22% more")
	Trades.set_supplier(e, b, "budget")
	t.check(b.quality_bonus() < q0, "value range is worse")


func test_clothing_collections_suit_districts_and_fade(t) -> void:
	var e := _game()
	var rich := _shop(e, 9, "clothing")   # Financial District
	var poor := _shop(e, 1, "clothing")   # Westbank Estates
	Trades.launch(e, rich, "designer")
	Trades.launch(e, poor, "designer")
	t.check(rich.quality_bonus() > poor.quality_bonus(), "designer labels need money in the district")
	var f0 := rich.footfall_bonus()
	e.day += 20
	Trades.refresh(e)
	t.check(rich.footfall_bonus() < f0 or is_equal_approx(f0, rich.footfall_bonus()), "collections fade")
	t.check(Trades.freshness(e, rich) <= 0.3, "stale after the fresh days")


func test_nightclub_nights_and_popularity(t) -> void:
	var e := _game()
	t.check(Trades.buy_club(e, "vault") == "", "bought The Vault")
	t.check(not Trades.club_forecast(e, "Tue")["open"], "dark on Tuesdays")
	var sat: Dictionary = Trades.club_forecast(e, "Sat")
	t.check(int(sat["crowd"]) > 0 and float(sat["takings"]) > float(sat["cost"]), "a Saturday makes money")
	Trades.set_club(e, "event", "guest_dj")
	t.check(int(Trades.club_forecast(e, "Sat")["crowd"]) > int(sat["crowd"]) or int(sat["crowd"]) == int(sat["capacity"]), "a guest DJ pulls a crowd")
	Trades.set_club(e, "entry", 2)
	t.check(int(Trades.club_forecast(e, "Sat")["vips"]) > 0, "VIP tables")


func test_car_hire_books_cars_and_wears_them(t) -> void:
	var e := _game()
	t.check(Trades.buy_rental(e) == "", "desk open")
	var cars: Array = []
	for i in 6:
		var v := e.buy_vehicle("saloon", Vector3.ZERO, 0.0)
		Trades.toggle_hire(e, String(v["id"]))
		cars.append(v)
	t.check(Trades.on_hire(e, String(cars[0]["id"])), "on hire")
	var cash := e.company_cash
	var net := 0.0
	for i in 5:
		net += Trades.rental_day(e)
	t.check(net > 0.0, "bookings make money (%.0f)" % net)
	t.check(cars.any(func(v): return float(v["km"]) > 0.0), "hired cars rack up km")
	var hi := Trades.hire_chance(e, cars[0])
	Trades.rental(e)["price_k"] = 1.25
	t.check(Trades.hire_chance(e, cars[0]) < hi, "dear rates book less")


func test_hotel_facilities_fill_rooms(t) -> void:
	var e := _game()
	t.check(Ventures.buy_estate(e, "skyport_hotel") == "", "bought the hotel")
	var st: Dictionary = e.flags["estates"]["skyport_hotel"]
	var occ0 := Ventures.target_occupancy(st, "hotel")
	var rate0 := Ventures.unit_rent(Ventures.estate_def("skyport_hotel"), st)
	t.check(Trades.build_facility(e, "skyport_hotel", "spa") == "", "spa built")
	t.check(Ventures.target_occupancy(st, "hotel") > occ0, "more guests")
	t.check(Ventures.unit_rent(Ventures.estate_def("skyport_hotel"), st) > rate0, "dearer rooms")


# ------------------------------------------------------- company & stages
func test_company_divisions_and_stages(t) -> void:
	var e := _game()
	e.set_brand({"name": "Crown Goods", "primary": "#0f3d5c", "accent": "#f5b13d", "face": "display", "sign": "lightbox"})
	_shop(e, 1)
	_shop(e, 5, "cafe")
	t.check(Company.initials(e) == "CG", "logo initials")
	t.check(Company.divisions(e).size() == 2, "a division per trade")
	t.check(Progression.current(e)["id"] == "entrepreneur", "starts as an entrepreneur")
	e.stats["profitable_days"] = 1
	e.businesses[0].lifetime["revenue"] = 3000.0
	Progression.check(e)
	t.check(Progression.current(e)["id"] == "owner", "moves up when the steps are done")
	t.check(Progression.steps(e).size() == 3, "three steps a stage")
	var e2 := Empire.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	t.check(Progression.index(e2) == Progression.index(e), "stage saved")


func test_bought_out_rival_arrives_fitted_out(t) -> void:
	var e := _game()
	var u: Dictionary = e.market[20]
	e.rivals = e.rivals.filter(func(r): return r["unit"] != u["id"])
	e.firms = e.firms.filter(func(f): return f.get("unit", "") != u["id"])
	e.rivals.append({"unit": u["id"], "district": u["district"], "pos": u["pos"], "price": 8000.0, "name": "QuikSave Midtown", "opened": 1})
	var b := CityLife.buy_out(e, u)
	t.check(b != null and b.level == 2, "an acquired chain store starts Established")
