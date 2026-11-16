class_name Ventures
extends RefCounted
## The Skyport expansion's industries, on top of Empire's money and stock
## (state in Empire.flags, so saves keep their format):
##
## Imports (airport cargo): order goods in bulk from an overseas supplier –
##   sea freight (cheapest, 3 days), standard air (next day) or express (same
##   evening) – for one of your shops. Goods cost less than wholesale, plus
##   freight per case and 5% duty; paid when ordered, delivered into the
##   shop's stockroom on arrival (overflow by the door). Owning the Skyport
##   Logistics warehouse makes the local delivery free (it's £1.20 a case).
##   flags.imports = [{id, biz, lines {pid: cases}, day, min, sup}]
## Property investment: buy buildings on Skyport Island; tenants (or hotel
##   guests) pay rent daily depending on occupancy, which drifts towards a
##   level set by your rent (cheap fills up, dear empties) and condition;
##   upkeep every day, wear every day, renovation restores condition and
##   lifts the rent the market pays. Valuation follows condition and income.
##   Some buildings bring perks: the hangar (no hangar fees), the marina
##   berths (no marina fees), the warehouse (free import delivery).
##   flags.estates = {id: {rent_k, occ, cond, renovated, bought_day}}
## Dealership business: buy Kestrel Motors and run it – buy cars at trade,
##   price them, buyers come by the day (fewer when you're dear), each sale
##   is booked, staff and rent are paid daily. flags.dealership =
##   {stock: {model: n}, markup, sold, revenue}
## Running costs: hangar fees for aircraft, marina fees for boats, daily.

const SUPPLIERS := [
	{"id": "sea", "name": "Harbour Consolidated", "how": "Sea freight", "days": 3.0, "price_k": 0.68, "per_case": 0.55},
	{"id": "air", "name": "Skyport Air Cargo", "how": "Standard air", "days": 1.0, "price_k": 0.78, "per_case": 1.6},
	{"id": "express", "name": "Nightjet Express", "how": "Express (tonight)", "days": 0.4, "price_k": 0.84, "per_case": 3.2},
]
const MIN_CASES := 6
const DUTY := 0.05
const LOCAL_DELIVERY := 1.2

## Buildings you can invest in. kind: flats / offices / hotel / warehouse /
## hangar / berths / home. units × rent a unit a day at full occupancy.
## "at": on Skyport Island's LOCAL plan – use estate_at() for the world.
const ESTATES := [
	{"id": "marina_quay", "name": "Marina Quay Apartments", "kind": "flats", "price": 420000.0, "units": 16, "rent": 30.0, "upkeep": 70.0,
		"at": Vector3(1447, 3, -235), "desc": "Sixteen flats over the marina, with a show flat you can use"},
	{"id": "tower_offices", "name": "Tower Road Offices", "kind": "offices", "price": 780000.0, "units": 8, "rent": 110.0, "upkeep": 150.0,
		"at": Vector3(1675, 3, -145), "desc": "Eight floors of offices on Tower Road"},
	{"id": "skyport_hotel", "name": "Skyport Hotel", "kind": "hotel", "price": 1600000.0, "units": 60, "rent": 26.0, "upkeep": 420.0,
		"at": Vector3(1745, 3, -145), "desc": "Sixty rooms by the park, guests by the night; the top-floor suite is yours to use"},
	{"id": "logistics", "name": "Skyport Logistics Warehouse", "kind": "warehouse", "price": 260000.0, "units": 1, "rent": 0.0, "upkeep": 45.0,
		"at": Vector3(2400, 3, -110), "desc": "Free local delivery for every import"},
	{"id": "hangar2", "name": "Hangar 2", "kind": "hangar", "price": 350000.0, "units": 1, "rent": 0.0, "upkeep": 60.0,
		"at": Vector3(1756, 3, 240), "desc": "Your own hangar: no hangar fees for your aircraft"},
	{"id": "berths", "name": "Marina Berths", "kind": "berths", "price": 180000.0, "units": 12, "rent": 16.0, "upkeep": 30.0,
		"at": Vector3(1340, 0, -250), "desc": "Twelve berths: rent them out, moor free yourself"}
]
## Homes that come with a building (the hotel's top-floor suite, the
## flats' show flat): owning the building gives you the home's keys.
const HOME_ESTATE := {"skyport_suite": "skyport_hotel", "skyport_flat": "marina_quay"}

const RENT_LEVELS := [[0.85, "Cheap"], [1.0, "Market"], [1.2, "Premium"]]

const DEALER_PRICE := 150000.0
const DEALER_MODELS := ["used_kestrel", "saloon", "scout", "van", "brute"]
const TRADE_K := 0.82


# ------------------------------------------------------------- imports
static func supplier(id: String) -> Dictionary:
	for s in SUPPLIERS:
		if s["id"] == id:
			return s
	return SUPPLIERS[0]


## {goods, freight, duty, delivery, total, cases, arrives: "day N hh:mm"}
static func import_quote(e: Empire, lines: Dictionary, sup_id: String) -> Dictionary:
	var s := supplier(sup_id)
	var goods := 0.0
	var cases := 0
	for pid in lines:
		var n := int(lines[pid])
		goods += float(EmpireData.product(pid).get("case_cost", 0.0)) * float(s["price_k"]) * n
		cases += n
	var freight := float(s["per_case"]) * cases
	var duty := goods * DUTY
	var delivery := 0.0 if owns_estate(e, "logistics") else LOCAL_DELIVERY * cases
	var t := e.day * 1440.0 + e.minute + float(s["days"]) * 1440.0
	return {"goods": goods, "freight": freight, "duty": duty, "delivery": delivery, "total": goods + freight + duty + delivery,
		"cases": cases, "arrive_t": t}


static func import_order(e: Empire, biz_id: String, lines: Dictionary, sup_id: String) -> String:
	var q := import_quote(e, lines, sup_id)
	if int(q["cases"]) < MIN_CASES:
		return "Minimum order %d cases" % MIN_CASES
	if e.business(biz_id) == null:
		return "Pick one of your shops"
	if not e.pay(float(q["total"]), "imports", "Import: %d cases via %s" % [q["cases"], supplier(sup_id)["name"]], biz_id):
		return "Not enough money (%s)" % EmpireData.money(float(q["total"]))
	var orders: Array = e.flags.get("imports", [])
	orders.append({"id": e.new_id("imp"), "biz": biz_id, "lines": lines.duplicate(), "t": q["arrive_t"], "sup": sup_id,
		"unit_k": float(q["total"]) / maxf(float(q["goods"]) / float(supplier(sup_id)["price_k"]), 0.01)})
	e.flags["imports"] = orders
	e.stats["imports"] = int(e.stats.get("imports", 0)) + 1
	return ""


## Arrivals: goods into the shop's stockroom, at their landed cost.
static func deliver_imports(e: Empire) -> void:
	var orders: Array = e.flags.get("imports", [])
	if orders.is_empty():
		return
	var now := e.day * 1440.0 + e.minute
	var keep: Array = []
	for o: Dictionary in orders:
		if float(o["t"]) > now:
			keep.append(o)
			continue
		var b: Business = e.business(String(o["biz"]))
		if b == null:
			continue
		var cases := 0
		for pid in o["lines"]:
			var units := int(o["lines"][pid]) * EmpireData.case_qty(pid)
			var landed := float(EmpireData.product(pid).get("case_cost", 0.0)) * float(o["unit_k"]) / EmpireData.case_qty(pid)
			var tmp := Stock.new(0, "import")
			e._receive(tmp, pid, units, landed)
			var moved := Stock.transfer(tmp, b.backroom, pid, units)
			if moved < units:
				Stock.transfer(tmp, b.floor_pile, pid, units - moved)
			cases += int(o["lines"][pid])
		e._note("Import arrived at %s: %d cases" % [b.name, cases], "good")
	e.flags["imports"] = keep


static func imports_due(e: Empire) -> Array:
	return e.flags.get("imports", [])


# ------------------------------------------------------------- property
## An estate's position in the world ("at" is on Skyport Island's own plan).
static func estate_at(d: Dictionary) -> Vector3:
	return SkyportIsland.w(d["at"])


static func estate_def(id: String) -> Dictionary:
	for d in ESTATES:
		if d["id"] == id:
			return d
	return {}


static func owns_estate(e: Empire, id: String) -> bool:
	return (e.flags.get("estates", {}) as Dictionary).has(id)


static func buy_estate(e: Empire, id: String) -> String:
	var d := estate_def(id)
	if d.is_empty() or owns_estate(e, id):
		return "Not for sale"
	if not e.pay(float(d["price"]), "property", "Bought %s" % d["name"]):
		return "Not enough money (%s)" % EmpireData.money(float(d["price"]))
	var es: Dictionary = e.flags.get("estates", {})
	es[id] = {"rent_k": 1.0, "occ": 0.35 if int(d["units"]) > 0 else 0.0, "cond": 0.85, "renovated": 0, "bought_day": e.day,
		"income": 0.0, "last": 0.0}
	e.flags["estates"] = es
	_grant_homes(e)
	e._note("You own %s" % d["name"], "good")
	return ""


## The keys to the homes that come with buildings you own (and only those):
## a property record per home, so the lift, bed and saving work as for any
## home. Also run on load (saves made before the homes existed).
static func _grant_homes(e: Empire) -> void:
	for hid in HOME_ESTATE:
		var pid := "home_" + String(hid)
		var want := owns_estate(e, String(HOME_ESTATE[hid]))
		var has := e.owns_property(pid)
		if want and not has:
			e.properties.append({"id": pid, "kind": "home", "name": hid, "price": 0.0, "let": false, "income": 0.0, "with_estate": true})
		elif has and not want:
			e.properties = e.properties.filter(func(q): return q["id"] != pid)


static func sell_estate(e: Empire, id: String) -> String:
	if not owns_estate(e, id):
		return ""
	var v := valuation(e, id)
	e.company_cash += v
	e._book("company", v, "property", "Sold %s" % estate_def(id)["name"])
	(e.flags["estates"] as Dictionary).erase(id)
	_grant_homes(e)
	return ""


static func set_rent(e: Empire, id: String, k: float) -> void:
	if owns_estate(e, id):
		e.flags["estates"][id]["rent_k"] = k


static func renovate_cost(id: String) -> float:
	return float(estate_def(id)["price"]) * 0.08


static func renovate(e: Empire, id: String) -> String:
	if not owns_estate(e, id):
		return ""
	var c := renovate_cost(id)
	if not e.pay(c, "property", "Renovated %s" % estate_def(id)["name"]):
		return "Not enough money (%s)" % EmpireData.money(c)
	var st: Dictionary = e.flags["estates"][id]
	st["cond"] = 1.0
	st["renovated"] = int(st["renovated"]) + 1
	return ""


## Where occupancy settles for this rent and condition (0..1).
static func target_occupancy(st: Dictionary, kind: String) -> float:
	var k := float(st["rent_k"])
	var base := {0.85: 0.97, 1.0: 0.9, 1.2: 0.72}.get(snappedf(k, 0.05), 0.85) as float
	if kind == "hotel":
		base *= 0.85
	return clampf(base * lerpf(0.55, 1.05, float(st["cond"])), 0.0, 1.0)


## A unit's rent a day (market rent rises 12% a renovation).
static func unit_rent(d: Dictionary, st: Dictionary) -> float:
	return float(d["rent"]) * float(st["rent_k"]) * (1.0 + 0.12 * int(st["renovated"]))


static func valuation(e: Empire, id: String) -> float:
	var d := estate_def(id)
	var st: Dictionary = e.flags.get("estates", {}).get(id, {})
	if st.is_empty():
		return float(d["price"])
	var income_y := unit_rent(d, st) * float(d["units"]) * float(st["occ"]) * 365.0
	return float(d["price"]) * lerpf(0.82, 1.04, float(st["cond"])) + income_y * 0.6 * (1.0 + 0.1 * int(st["renovated"])) - float(d["rent"]) * float(d["units"]) * 365.0 * 0.5


## Once a day: occupancy drifts, rent comes in, upkeep goes out, buildings wear.
static func estates_day(e: Empire) -> Dictionary:
	var es: Dictionary = e.flags.get("estates", {})
	var tot := {"income": 0.0, "upkeep": 0.0}
	for id in es:
		var d := estate_def(id)
		if d.is_empty():
			continue
		var st: Dictionary = es[id]
		var kind := String(d["kind"])
		if int(d["units"]) > 0:
			var tgt := target_occupancy(st, kind)
			if kind == "hotel":
				tgt *= clampf(float(CityLife.weather_def(e.weather).get("footfall", 1.0)), 0.7, 1.15)
			st["occ"] = clampf(float(st["occ"]) + (tgt - float(st["occ"])) * 0.18 + e.rng.randf_range(-0.02, 0.02), 0.0, 1.0)
		var income := unit_rent(d, st) * float(d["units"]) * float(st["occ"])
		var upkeep := float(d["upkeep"]) * lerpf(1.3, 1.0, float(st["cond"]))
		st["cond"] = maxf(float(st["cond"]) - 0.004, 0.2)
		st["last"] = income - upkeep
		st["income"] = float(st.get("income", 0.0)) + income
		if income > 0.0:
			e.company_cash += income
			e._book("company", income, "rent_in", "Rent: %s" % d["name"])
		e.company_cash -= upkeep
		e._book("company", -upkeep, "upkeep", "Upkeep: %s" % d["name"])
		tot["income"] = float(tot["income"]) + income
		tot["upkeep"] = float(tot["upkeep"]) + upkeep
	return tot


# ----------------------------------------------------------- dealership
static func owns_dealer(e: Empire) -> bool:
	return e.flags.has("dealership")


static func buy_dealer(e: Empire) -> String:
	if owns_dealer(e):
		return ""
	if not e.pay(DEALER_PRICE, "business", "Bought Kestrel Motors"):
		return "Not enough money (%s)" % EmpireData.money(DEALER_PRICE)
	e.flags["dealership"] = {"stock": {}, "markup": 1.0, "sold": 0, "revenue": 0.0, "profit": 0.0, "last": 0.0}
	e._note("Kestrel Motors is yours: stock the forecourt", "good")
	return ""


static func trade_price(model: String) -> float:
	return float(EmpireData.vehicle_model(model).get("price", 0.0)) * TRADE_K


static func dealer_buy_stock(e: Empire, model: String) -> String:
	var dl: Dictionary = e.flags.get("dealership", {})
	if dl.is_empty():
		return "You don't own the dealership"
	var units := 0
	for m in dl["stock"]:
		units += int(dl["stock"][m])
	if units >= 8:
		return "The forecourt is full (8 cars)"
	var c := trade_price(model)
	if not e.pay(c, "stock", "Trade-in stock: %s" % EmpireData.vehicle_model(model)["name"]):
		return "Not enough money (%s)" % EmpireData.money(c)
	dl["stock"][model] = int(dl["stock"].get(model, 0)) + 1
	return ""


## Buyers today: ~1.2 a day at list price, fewer the dearer; each buys one
## car in stock (cheaper cars sell more often).
static func dealer_day(e: Empire) -> float:
	var dl: Dictionary = e.flags.get("dealership", {})
	if dl.is_empty():
		return 0.0
	var mk := float(dl["markup"])
	var lam := 1.2 * pow(1.0 / mk, 4.0)
	var buyers := 0
	var l := exp(-lam)
	var p := 1.0
	while true:
		p *= e.rng.randf()
		if p < l:
			break
		buyers += 1
	var revenue := 0.0
	var cogs := 0.0
	for i in buyers:
		var models: Array = []
		for m in dl["stock"]:
			if int(dl["stock"][m]) > 0:
				models.append(m)
		if models.is_empty():
			break
		models.sort_custom(func(a, b): return trade_price(a) < trade_price(b))
		var pick: String = models[0] if e.rng.randf() < 0.6 else models[e.rng.randi() % models.size()]
		dl["stock"][pick] = int(dl["stock"][pick]) - 1
		var price := float(EmpireData.vehicle_model(pick)["price"]) * mk
		revenue += price
		cogs += trade_price(pick)
		dl["sold"] = int(dl["sold"]) + 1
	var costs := 120.0 + 80.0   # (a salesperson and the lot)
	if revenue > 0.0:
		e.company_cash += revenue
		e._book("company", revenue, "sales", "Kestrel Motors: %d car%s sold" % [buyers, "" if buyers == 1 else "s"])
	e.company_cash -= costs
	e._book("company", -costs, "wages", "Kestrel Motors: staff and lot")
	dl["revenue"] = float(dl["revenue"]) + revenue
	dl["last"] = revenue - cogs - costs
	dl["profit"] = float(dl["profit"]) + revenue - cogs - costs
	return revenue - cogs - costs


# ----------------------------------------------------------- running costs
static func craft_fees(e: Empire) -> float:
	var total := 0.0
	for v in e.vehicles:
		if v.get("test", false):
			continue
		var md := EmpireData.vehicle_model(String(v["model"]))
		var cls := String(md.get("class", "car"))
		if cls == "car":
			continue
		if cls in ["heli", "plane"] and owns_estate(e, "hangar2"):
			continue
		if cls == "boat" and owns_estate(e, "berths"):
			continue
		total += float(md.get("fee", 0.0))
	if total > 0.0:
		e.company_cash -= total
		e._book("company", -total, "fees", "Hangar and marina fees")
	return total


## Everything Ventures does at the end of a day.
static func end_day(e: Empire) -> Dictionary:
	var es := estates_day(e)
	var dl := dealer_day(e)
	var fees := craft_fees(e)
	return {"rent": es["income"], "upkeep": es["upkeep"], "dealer": dl, "fees": fees}
