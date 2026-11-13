extends RefCounted
## CityLife: weather, events and the QuikSave rival chain, headless.

const STARTER := {"id": "test_unit", "name": "Test Unit", "shop_name": "Test Shop", "district": "west:suburb",
	"island": "west", "size": 100.0, "rent": 35.0, "price": 9000.0, "pos": [0.0, 0.0, 0.0]}


## A small fake city: units spaced along a street in two districts.
func _market() -> Array:
	var m: Array = []
	for i in 10:
		var dk := "west:suburb" if i < 5 else "east:midtown"
		m.append({"id": "u%d" % i, "kind": "shop", "name": "Unit %d" % i, "shop_name": "Shop %d" % i, "district": dk,
			"island": dk.get_slice(":", 0), "size": 100.0, "rent": 30.0, "price": 7000.0, "pos": [i * 90.0, 0.0, 0.0]})
	return m


func _game(seed := 5) -> Empire:
	var e := Empire.new()
	e.market = _market()
	e.flags["start_unit"] = "u0"
	e.new_game(seed)
	return e


func _free(e: Empire, from := 1) -> Dictionary:
	for i in range(from, e.market.size()):
		var u: Dictionary = e.market[i]
		if not CityLife.is_rival(e, u["id"]) and e.business_at(u["id"]) == null:
			return u
	return {}


func _stocked(e: Empire, unit: Dictionary) -> Business:
	e.personal_cash = 50000.0
	var b := e.rent_premises(unit)
	e.transfer_to_company(5000.0)
	var order := {"crisps": 2, "cola": 2, "water": 2, "milk": 1, "bread": 1, "choc_bar": 1}
	e.buy_wholesale("w1", order)
	for pid in order:
		Stock.transfer(e.pallets["w1"], b.backroom, pid, 999)
	e.restock_from_backroom(b, 60)
	return b


func test_new_game_has_rivals_weather_and_news(t) -> void:
	var e := _game()
	t.check(e.rivals.size() == int(CityLife.rival_cfg()["start"]), "the chain starts with %d stores" % e.rivals.size())
	t.check(not CityLife.is_rival(e, "u0"), "never on the starter unit")
	t.check(e.weather != "" and e.forecast != "", "weather and a forecast (%s, %s)" % [e.weather, e.forecast])
	t.check(not e.news.is_empty(), "a headline")
	var r: Dictionary = e.rivals[0]
	t.check(e.rent_premises(e.market.filter(func(u): return u["id"] == r["unit"])[0]) == null, "a rival's unit can't be rented")


func test_weather_changes_footfall_and_what_sells(t) -> void:
	var e := _game()
	var b := _stocked(e, _free(e, 0))
	e.weather = "sunny"
	var sunny := CityLife.footfall_k(e, b)
	e.weather = "storm"
	var storm := CityLife.footfall_k(e, b)
	t.check(storm < sunny, "storms keep shoppers home (%.2f < %.2f)" % [storm, sunny])
	# Category draws: a heatwave makes shoppers want drinks far more often.
	var rng := RandomNumberGenerator.new()
	var drinks := {}
	for w in ["cloudy", "heatwave"]:
		e.weather = w
		rng.seed = 9
		var n := 0
		for i in 600:
			for pid in DemandModel.make_shopper(b, rng, CityLife.mix_k(e))["wants"]:
				if EmpireData.product(pid)["cat"] == "drinks":
					n += 1
		drinks[w] = n
	t.check(drinks["heatwave"] > drinks["cloudy"] * 1.3, "heatwave drinks demand %d vs %d" % [drinks["heatwave"], drinks["cloudy"]])


func test_days_roll_weather_and_events(t) -> void:
	var e := _game(8)
	var seen := {}
	var kinds := {}
	for d in 30:
		e.advance(1440.0)
		seen[e.weather] = true
		for ev in e.events:
			kinds[ev["kind"]] = true
	t.check(seen.size() >= 3, "weather varies over a month (%s)" % ", ".join(seen.keys()))
	t.check(kinds.size() >= 3, "several kinds of events happen (%s)" % ", ".join(kinds.keys()))
	t.check(e.news.size() > 5, "the news feed fills (%d)" % e.news.size())


func test_wholesale_deal_and_shortage_change_prices(t) -> void:
	var e := _game()
	e.personal_cash = 1000.0
	var base := e.case_price("cola")
	CityLife.trigger(e, "deal", "cola")
	t.check(is_equal_approx(e.case_price("cola"), base * 0.7), "deal: 30%% off (%.2f)" % e.case_price("cola"))
	var cash := e.personal_cash
	e.buy_wholesale("w1", {"cola": 1})
	t.check(is_equal_approx(cash - e.personal_cash, base * 0.7), "and you pay the deal price")
	t.check(is_equal_approx(e.unit_cost("cola"), base * 0.7 / 24.0), "stock valued at what it cost")
	CityLife.trigger(e, "price_rise", "milk")
	t.check(e.case_price("milk") > float(EmpireData.product("milk")["case_cost"]), "shortage raises a price")
	e.advance(1440.0 * 4)
	t.check(is_equal_approx(e.case_price("cola"), base), "deals end")


func test_inspection_rewards_clean_and_fines_dirty(t) -> void:
	var e := _game()
	var b := _stocked(e, _free(e))
	b.cleanliness = 0.95
	var rep0 := b.reputation
	CityLife.trigger(e, "inspection", b.id)
	e.minute = 13.0 * 60.0 + 59.0
	e.advance(2.0)
	t.check(b.reputation > rep0 + 5.0, "clean shop: reputation up (%.0f → %.0f)" % [rep0, b.reputation])
	e.advance(1440.0)
	b.cleanliness = 0.2
	var cash := e.company_cash
	CityLife.trigger(e, "inspection", b.id)
	e.minute = 13.0 * 60.0 + 59.0
	e.advance(2.0)
	t.check(e.company_cash < cash - 100.0, "dirty shop: fined")


func test_burglary_and_cctv(t) -> void:
	var e := _game()
	var b := _stocked(e, _free(e))
	var before := b.backroom.total_units()
	var sold := int(e.stats["units_sold"])
	CityLife.trigger(e, "burglary", b.id)
	t.check(b.backroom.total_units() < before, "a break-in empties some of the stock room (%d → %d)" % [before, b.backroom.total_units()])
	t.check(e.total_units() + int(e.stats["units_sold"]) - sold + int(e.stats["units_stolen"]) == int(e.stats["units_bought"]),
		"units still balance (stolen counted)")
	b.apply_upgrade("security")
	var n := b.backroom.total_units()
	CityLife.trigger(e, "burglary", b.id)
	t.check(b.backroom.total_units() == n, "CCTV stops it")


func test_sick_staff_skip_work_and_wages(t) -> void:
	var e := _game()
	var b := _stocked(e, _free(e))
	var c: Dictionary = e.candidates.filter(func(x): return x["role"] == "cashier")[0]
	e.hire(b, c)
	t.check(b.trading(10.0), "a cashier: trading")
	CityLife.trigger(e, "sick", c["id"])
	t.check(not b.trading(10.0) and is_zero_approx(b.wages_per_hour()), "off sick: no cashier, no wage")
	e.advance(1440.0)
	t.check(b.trading(10.0), "back the next day")


func test_rivals_open_near_you_compete_and_can_be_bought(t) -> void:
	var e := _game(3)
	var b := _stocked(e, _free(e, 2))
	var c: Dictionary = e.candidates.filter(func(x): return x["role"] == "cashier")[0]
	e.hire(b, c)
	e.rivals.clear()
	var base := DemandModel.arrivals_per_hour(b, 12.0, e.competitors_near(b))
	# Run until the chain expands.
	for d in 12:
		e.advance(1440.0)
	t.check(e.rivals.size() >= 2, "the chain opened stores (%d)" % e.rivals.size())
	var near := CityLife.rivals_near(e, b)
	t.check(near >= 1, "one opened near your shop (%d within range)" % near)
	t.check(DemandModel.arrivals_per_hour(b, 12.0, e.competitors_near(b)) < base, "and takes footfall")
	var r: Dictionary = e.rivals[0]
	var unit: Dictionary = e.market.filter(func(u): return u["id"] == r["unit"])[0]
	e.personal_cash = 0.0
	e.company_cash = 100.0
	t.check(CityLife.buy_out(e, unit) == null, "can't buy out without the money")
	e.personal_cash = 100000.0
	var nb := CityLife.buy_out(e, unit)
	t.check(nb != null and nb.owned and not CityLife.is_rival(e, r["unit"]), "bought out: yours, freehold")
	t.check(e.stat("rivals_bought") == 1.0, "counted")


func test_chain_retreats_after_buyouts(t) -> void:
	var e := _game(4)
	e.personal_cash = 1e7
	var guard := 0
	while not e.flags.get("rival_gone", false) and guard < 20:
		guard += 1
		if e.rivals.is_empty():
			e.advance(1440.0)
			continue
		var r: Dictionary = e.rivals[0]
		CityLife.buy_out(e, e.market.filter(func(u): return u["id"] == r["unit"])[0])
	t.check(e.flags.get("rival_gone", false), "QuikSave leaves once every store is bought (%d bought)" % int(e.stats["rivals_bought"]))
	var n := e.rivals.size()
	e.advance(1440.0 * 10)
	t.check(e.rivals.size() == n, "and never comes back")
	t.check(e.stat("rival_gone") == 1.0, "goal stat")


func test_city_life_saves(t) -> void:
	var e := _game()
	CityLife.trigger(e, "festival", "west:suburb")
	var d := e.to_dict()
	var e2 := Empire.from_dict(JSON.parse_string(JSON.stringify(d)))
	t.check(e2.weather == e.weather and e2.forecast == e.forecast, "weather saved")
	t.check(e2.rivals.size() == e.rivals.size() and e2.events.size() == e.events.size(), "rivals and events saved")
	t.check(e2.news.size() == e.news.size(), "news saved")
	var old := d.duplicate(true)
	old["version"] = 2
	for k in ["events", "rivals", "news", "weather", "forecast"]:
		old.erase(k)
	var e3 := Empire.from_dict(old)
	t.check(e3.rivals.is_empty() and e3.events.is_empty(), "a v2 save loads with no city life yet")
