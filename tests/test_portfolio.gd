extends RefCounted
## Running several shops at once: each keeps its own stock, staff, takings
## and books; the company sums them without double counting; one unit can
## only ever hold one business (and a save that has two is merged, never
## loses stock or staff); every shop reports what it's doing.

func _unit(n: int, district := "west:suburb") -> Dictionary:
	return {"id": "shop_%d_0" % (n * 300), "name": "Unit %d" % n, "shop_name": "Shop %d" % n, "district": district,
		"island": district.get_slice(":", 0), "size": 100.0, "rent": 30.0 + n, "price": 9000.0,
		"pos": [n * 300.0, 0.0, 0.0]}


func _stock(e: Empire, b: Business, order: Dictionary) -> void:
	var key := "w_" + b.id
	e.buy_wholesale(key, order)
	var pal: Stock = e.pallets[key]
	for pid in order:
		Stock.transfer(pal, b.backroom, pid, pal.qty(pid))
	e.restock_from_backroom(b, 1000)


func _cashier(e: Empire, b: Business) -> void:
	var cs := e.candidates.filter(func(x): return x["role"] == "cashier")
	if cs.is_empty():
		e.candidates = Staff.candidates(e.day + 50, e.seed + 3)
		cs = e.candidates.filter(func(x): return x["role"] == "cashier")
	e.hire(b, cs[0])


func test_shops_run_independently_and_books_add_up(t) -> void:
	var e := Empire.new()
	e.new_game(21)
	e.personal_cash = 30000.0
	var a := e.rent_premises(_unit(1))
	var b := e.rent_premises(_unit(2, "west:midtown"))
	var c := e.rent_premises(_unit(3))
	t.check(a != null and b != null and c != null and e.businesses.size() == 3, "three shops rented")
	t.check(a.id != b.id and b.id != c.id, "each has its own id")
	e.transfer_to_company(8000.0)
	_stock(e, a, {"crisps": 2, "cola": 2, "milk": 2, "bread": 2})
	_stock(e, b, {"choc_bar": 2, "water": 2, "tea": 1})
	_stock(e, c, {"crisps": 1})
	_cashier(e, a)
	_cashier(e, b)
	t.check(a.staff.size() == 1 and b.staff.size() == 1 and c.staff.is_empty(), "staff belong to the shop that hired them")
	t.check(a.backroom.qty("choc_bar") == 0 and b.shelf_qty("crisps") == 0, "stock stays where it was put")
	var company0 := e.company_cash
	e.minute = 6.0 * 60.0
	e.advance(1440.0 - e.minute)
	var ra: Dictionary = a.history[-1]
	var rb: Dictionary = b.history[-1]
	var rc: Dictionary = c.history[-1]
	t.check(int(ra["served"]) > 5 and int(rb["served"]) > 5, "both staffed shops traded off-screen (%d, %d)" % [int(ra["served"]), int(rb["served"])])
	t.check(int(rc["customers"]) == 0 and float(rc["revenue"]) == 0.0, "the shop with nobody on the till didn't trade")
	t.check(float(rc["rent"]) > 0.0 and float(rc["profit"]) < 0.0, "…but still paid its rent (lost %.2f)" % -float(rc["profit"]))
	var sum := 0.0
	var cash_expect := company0
	for r in [ra, rb, rc]:
		sum += float(r["profit"])
		cash_expect += float(r["revenue"]) - float(r["fees"]) - float(r["wages"]) - float(r["rent"]) - float(r["utilities"])
	var co: Dictionary = e.day_reports[-1]
	t.check(absf(float(co["profit"]) - sum) < 0.01, "company profit %.2f = sum of the shops %.2f" % [float(co["profit"]), sum])
	t.check(absf(e.company_cash - cash_expect) < 0.05, "company cash %.2f = start + each shop's takings − costs %.2f" % [e.company_cash, cash_expect])
	# Wages, rent and utilities were booked once per shop.
	var rent_lines := e.ledger.filter(func(x): return String(x["cat"]) == "rent" and String(x["memo"]).begins_with("Rent:") and int(x["day"]) == int(co["day"]))
	t.check(rent_lines.size() == 3, "one rent line per shop (%d)" % rent_lines.size())


func test_one_business_per_unit(t) -> void:
	var e := Empire.new()
	e.new_game(5)
	e.personal_cash = 30000.0
	var u := _unit(1)
	var a := e.rent_premises(u)
	t.check(a != null, "rented")
	t.check(e.rent_premises(u) == null, "renting it again does nothing")
	var cash := e.personal_cash
	var f := e.buy_premises(u)
	t.check(f == a and a.owned and e.businesses.size() == 1, "buying the freehold upgrades the same business")
	t.check(e.buy_premises(u) == null and e.personal_cash == cash - 9000.0, "it can't be bought twice (paid once)")


func test_duplicate_records_in_a_save_are_merged(t) -> void:
	var e := Empire.new()
	e.new_game(9)
	e.personal_cash = 30000.0
	var a := e.rent_premises(_unit(1))
	e.transfer_to_company(5000.0)
	_stock(e, a, {"crisps": 2, "cola": 1})
	_cashier(e, a)
	var units0 := e.total_units()
	var d := e.to_dict()
	# A corrupt save: the same unit twice, the copy with its own stock and staff.
	var dup: Dictionary = (d["businesses"][0] as Dictionary).duplicate(true)
	dup["id"] = "b999"
	dup["staff"] = [{"id": "s_dup", "name": "Pat Copy", "role": "stocker", "wage": 9.0, "skill": 3, "traits": [], "business": "b999"}]
	(d["businesses"] as Array).append(dup)
	var e2 := Empire.from_dict(d)
	t.check(e2.businesses.size() == 1, "loaded as one business (%d)" % e2.businesses.size())
	var b2: Business = e2.businesses[0]
	t.check(b2.staff.size() == 2, "staff from both records kept (%d)" % b2.staff.size())
	t.check(e2.total_units() >= units0, "no stock lost in the merge (%d ≥ %d)" % [e2.total_units(), units0])
	t.check(int(e2.flags.get("repaired_duplicates", 0)) == 1, "the repair is recorded")
	# Loading again changes nothing (idempotent).
	var e3 := Empire.from_dict(e2.to_dict())
	t.check(e3.businesses.size() == 1 and e3.total_units() == e2.total_units(), "reloading is idempotent")


func test_status_says_what_the_shop_is_doing(t) -> void:
	var e := Empire.new()
	e.new_game(3)
	e.personal_cash = 20000.0
	var b := e.rent_premises(_unit(1))
	t.check(b.status(10.0)[0] == "no_stock", "new shop: out of stock")
	e.transfer_to_company(3000.0)
	_stock(e, b, {"crisps": 1})
	t.check(b.status(10.0)[0] == "no_cashier", "stocked, nobody on the till: says so")
	b.live = true
	t.check(b.status(10.0)[0] == "trading", "with you at the till: trading")
	b.live = false
	_cashier(e, b)
	t.check(b.status(10.0)[0] == "trading", "with a cashier: trading")
	t.check(b.status(3.0)[0] == "after_hours", "at 3am: closed for the night")
	b.open = false
	t.check(b.status(10.0)[0] == "closed", "switched off: closed")


func test_dismissal_notice_pay_is_in_the_shops_profit(t) -> void:
	var e := Empire.new()
	e.new_game(4)
	e.personal_cash = 20000.0
	var b := e.rent_premises(_unit(1))
	e.transfer_to_company(3000.0)
	_cashier(e, b)
	var x: Dictionary = b.staff[0]
	var before := float(b.today.get("other", 0.0))
	e.fire(b, x)
	t.check(b.staff.is_empty(), "dismissed")
	t.check(float(b.today["other"]) > before + 1.0, "notice pay counted in the shop's day (%.2f)" % float(b.today["other"]))
