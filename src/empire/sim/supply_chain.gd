class_name SupplyChain
extends RefCounted
## The supply chain (2026-11-27), on top of the cash & carry:
##
##   wholesale supplier → company warehouse → delivery fleet → branches → profit
##
## Early on you drive to the cash & carry and carry the cases in yourself (the
## existing loop). Later you buy a warehouse (config commerce.json
## "warehouses": a depot by an island's cash & carry, a dock-side
## distribution centre, or your Skyport Logistics estate), stock it in bulk at
## contract prices (bulk discount + warehouse_discount, delivered by the
## supplier), put vans from your garage on the rounds with a hired driver,
## and the fleet keeps every branch topped up twice a day (fleet.runs hours):
## each van loads what its branches are short of, drives the round (time from
## the distance at fleet.speed_kmh plus a stop per shop; km, wear and fuel
## through Empire.drive) and unloads into each stockroom. Branches the fleet
## serves need no supplier deliveries, so no delivery fees, and a manager (or a
## level-3 business) re-orders from the warehouse first.
##
## Wholesale contracts: city firms ask for so many cases a day of a category
## for some days at a margin over cost; the warehouse ships them at the end of
## each day (a van on the fleet needed), short days pay a penalty.
##
## Stock in the warehouse is an Empire pallet ("depot"), so every existing
## stock count, value and save already includes it. State: Empire.flags.chain
## {site, racks, fleet {vid: {driver, wage, runs, km, cases}}, trips [...],
##  contracts [...], offers [...], done, week [...]}.

const PALLET := "depot"


static func cfg() -> Dictionary:
	return EmpireData.file("commerce")


static func state(e: Empire) -> Dictionary:
	return e.flags.get("chain", {})


static func has_warehouse(e: Empire) -> bool:
	return String(state(e).get("site", "")) != ""


static func sites() -> Array:
	return cfg().get("warehouses", [])


static func site_def(id: String) -> Dictionary:
	for s: Dictionary in sites():
		if s["id"] == id:
			return s
	return {}


static func site(e: Empire) -> Dictionary:
	return site_def(String(state(e).get("site", "")))


static func capacity(e: Empire) -> int:
	if not has_warehouse(e):
		return 0
	return int(site(e).get("cases", 0)) + int(state(e).get("racks", 0)) * int(cfg().get("racking", {}).get("cases", 400))


static func stock(e: Empire) -> Stock:
	var p: Stock = e.pallets.get(PALLET, null)
	if p == null:
		p = Stock.new(0, "warehouse")
		e.pallets[PALLET] = p
	return p


static func cases_held(e: Empire) -> int:
	return stock(e).cases_used() if e.pallets.has(PALLET) else 0


## World position of the warehouse ([] if unknown): by its island's cash &
## carry, or the Skyport estate.
static func position(e: Empire) -> Array:
	var s := site(e)
	if s.is_empty():
		return []
	if s.has("estate"):
		var v := Ventures.estate_at(Ventures.estate_def(String(s["estate"])))
		return [v.x, v.y, v.z]
	for u in e.market:
		if u.get("kind", "") == "wholesale" and String(u.get("island", "")) == String(s["island"]):
			return u.get("pos", [])
	return []


static func site_block(e: Empire, id: String) -> String:
	var s := site_def(id)
	if s.is_empty():
		return "No such site"
	if has_warehouse(e):
		return "You already run %s" % site(e).get("name", "a warehouse")
	if s.has("estate") and not Ventures.owns_estate(e, String(s["estate"])):
		return "Buy the %s estate first" % Ventures.estate_def(String(s["estate"])).get("name", "")
	if e.company_cash < float(s.get("price", 0.0)):
		return "Needs %s in the company account" % EmpireData.money(float(s["price"]))
	return ""


static func buy_site(e: Empire, id: String) -> String:
	var why := site_block(e, id)
	if why != "":
		return why
	var s := site_def(id)
	if float(s.get("price", 0.0)) > 0.0 and not e.pay(float(s["price"]), "property", "Bought %s" % s["name"]):
		return "Not enough money"
	e.flags["chain"] = {"site": id, "racks": 0, "fleet": {}, "trips": [], "contracts": [], "offers": [], "done": 0, "week": [],
		"paid": float(s.get("price", 0.0))}
	stock(e)
	e._note("%s is yours. Stock it in bulk, then put a van on the rounds." % s["name"], "good", {"kind": "tab", "id": "company"})
	e.changed.emit()
	return ""


static func add_racking(e: Empire) -> String:
	var st := state(e)
	var rk: Dictionary = cfg().get("racking", {})
	if st.is_empty():
		return "No warehouse"
	if int(st.get("racks", 0)) >= int(rk.get("max", 3)):
		return "The building's full"
	if not e.pay(float(rk.get("cost", 22000)), "upgrade", "Warehouse racking"):
		return "Needs %s" % EmpireData.money(float(rk.get("cost", 22000)))
	st["racks"] = int(st.get("racks", 0)) + 1
	e.changed.emit()
	return ""


## Contract price of a case into the warehouse (bulk at the top band and
## the warehouse discount, on top of head office / flagship buying power).
static func case_cost(e: Empire, pid: String) -> float:
	return e.case_price(pid) * (1.0 - float(cfg().get("warehouse_discount", 0.07))) * Careers.bulk_k(e, 150)


## Buys cases into the warehouse ({pid: cases}). "" = done.
static func stock_up(e: Empire, order: Dictionary) -> String:
	if not has_warehouse(e):
		return "No warehouse"
	var cases := 0
	var cost := 0.0
	for pid in order:
		cases += maxi(int(order[pid]), 0)
		cost += case_cost(e, pid) * maxi(int(order[pid]), 0)
	if cases <= 0:
		return "Nothing to order"
	if cases_held(e) + cases > capacity(e):
		return "Room for %d more cases" % maxi(capacity(e) - cases_held(e), 0)
	if not e.pay(cost, "stock", "Warehouse stock: %d cases" % cases):
		return "Needs %s" % EmpireData.money(cost)
	for pid in order:
		var n := maxi(int(order[pid]), 0)
		if n > 0:
			e._receive(stock(e), pid, n * EmpireData.case_qty(pid), case_cost(e, pid) / EmpireData.case_qty(pid))
	e.stats["cases_bought"] = int(e.stats.get("cases_bought", 0)) + cases
	e.stats["spent_stock"] = float(e.stats.get("spent_stock", 0.0)) + cost
	e.changed.emit()
	return ""


## What the branches are short of, as warehouse cases (a quick "fill the
## warehouse for my shops" order, up to `room`).
static func suggested_order(e: Empire, room := -1) -> Dictionary:
	var want := {}
	for b: Business in e.businesses:
		var plan := e.restock_plan(b, true)
		for pid in plan["cases"]:
			want[pid] = int(want.get(pid, 0)) + int(plan["cases"][pid]) * 2
	var left := room if room >= 0 else maxi(capacity(e) - cases_held(e), 0)
	var out := {}
	var keys := want.keys()
	var more := true
	while more and left > 0:
		more = false
		for pid in keys:
			var have := int(out.get(pid, 0)) + stock(e).qty(pid) / maxi(EmpireData.case_qty(pid), 1)
			if have < int(want[pid]) and left > 0:
				out[pid] = int(out.get(pid, 0)) + 1
				left -= 1
				more = true
	return out


# -------------------------------------------------------------------- fleet
static func fleet(e: Empire) -> Dictionary:
	return state(e).get("fleet", {})


static func fleet_model(v: Dictionary) -> bool:
	return (cfg().get("fleet", {}).get("models", []) as Array).has(String(v.get("model", "")))


static func on_fleet(e: Empire, vid: String) -> bool:
	return fleet(e).has(vid)


## Puts a van on the rounds with a driver hired from today's candidates
## (or takes it off). "" = done.
static func toggle_fleet(e: Empire, vid: String) -> String:
	var st := state(e)
	if st.is_empty():
		return "Buy a warehouse first"
	var v := e.vehicle(vid)
	if v.is_empty():
		return "No such vehicle"
	var fl: Dictionary = st["fleet"]
	if fl.has(vid):
		fl.erase(vid)
		v.erase("fleet")
		e._note("%s is back in your garage" % EmpireData.vehicle_model(String(v["model"])).get("name", "Van"), "info")
		e.changed.emit()
		return ""
	if not fleet_model(v):
		return "Vans and trucks only"
	if Trades.on_hire(e, vid):
		return "It's on hire"
	var cand: Dictionary = {}
	for c in e.candidates:
		if c["role"] == "driver":
			cand = c
			break
	var driver := String(cand.get("name", "Sam Okafor")) if not cand.is_empty() else "Sam Okafor"
	if not cand.is_empty():
		e.candidates.erase(cand)
	var wage := float(cfg().get("fleet", {}).get("driver_wage", 13.5))
	if not cand.is_empty():
		wage = maxf(Staff.wage_for(cand), wage)
	fl[vid] = {"driver": driver, "wage": wage, "runs": 0, "km": 0.0, "cases": 0}
	v["fleet"] = true
	e._note("%s now drives the %s on the rounds" % [driver, EmpireData.vehicle_model(String(v["model"])).get("name", "van")], "good", {"kind": "tab", "id": "company"})
	e.changed.emit()
	return ""


static func capacity_of(v: Dictionary) -> int:
	return int(EmpireData.vehicle_model(String(v.get("model", ""))).get("cargo", 30))


## Branches served by the fleet (all of them on the warehouse's island and
## any island joined to it by a bridge – every island is, so: all).
static func served(e: Empire, b: Business) -> bool:
	return has_warehouse(e) and not fleet(e).is_empty() and b != null


static func _dist(a: Array, b: Array) -> float:
	if a.size() < 3 or b.size() < 3:
		return 600.0
	return Vector2(float(a[0]), float(a[2])).distance_to(Vector2(float(b[0]), float(b[2])))


## Plans and starts the rounds (called at each fleet.runs hour).
static func dispatch(e: Empire) -> int:
	var st := state(e)
	if st.is_empty() or fleet(e).is_empty():
		return 0
	var fc: Dictionary = cfg().get("fleet", {})
	var depot := position(e)
	# Every branch's shortfall, biggest first.
	var need: Array = []
	for b: Business in e.businesses:
		var plan := e.restock_plan(b, true)
		var lines := {}
		for pid in plan["cases"]:
			var have := stock(e).qty(pid) / maxi(EmpireData.case_qty(pid), 1)
			var n := mini(int(plan["cases"][pid]), have)
			if n > 0:
				lines[pid] = n
		if not lines.is_empty():
			need.append({"biz": b.id, "lines": lines, "n": lines.values().reduce(func(a, x): return a + int(x), 0), "pos": b.premises.get("pos", [])})
	need.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	var started := 0
	var trips: Array = st.get("trips", [])
	for vid in fleet(e):
		if need.is_empty():
			break
		if trips.any(func(t): return String(t["vid"]) == String(vid)):
			continue   # (still out on the last round)
		var v := e.vehicle(String(vid))
		if v.is_empty():
			continue
		var room := capacity_of(v)
		var stops: Array = []
		var load := {}
		while not need.is_empty() and room > 0:
			var n: Dictionary = need.pop_front()
			var take := {}
			for pid in n["lines"]:
				var avail := stock(e).qty(pid) / maxi(EmpireData.case_qty(pid), 1) - int(load.get(pid, 0))
				var c := mini(mini(int(n["lines"][pid]), avail), room)
				if c > 0:
					take[pid] = c
					load[pid] = int(load.get(pid, 0)) + c
					room -= c
			if not take.is_empty():
				stops.append({"biz": n["biz"], "lines": take, "pos": n["pos"]})
		if stops.is_empty():
			continue
		# Load the van (the cases leave the warehouse now: they're in transit).
		for pid in load:
			Stock.transfer(stock(e), v["cargo"], pid, int(load[pid]) * EmpireData.case_qty(pid))
		var t := e.minute
		var at := depot
		var km := 0.0
		for s: Dictionary in stops:
			var d := _dist(at, s["pos"]) * 1.35   # (roads aren't straight)
			km += d / 1000.0
			t += d / 1000.0 / float(fc.get("speed_kmh", 34.0)) * 60.0 + float(fc.get("stop_minutes", 12.0))
			s["eta"] = t
			at = s["pos"]
		km += _dist(at, depot) * 1.35 / 1000.0
		trips.append({"vid": vid, "stops": stops, "km": km, "back": t + _dist(at, depot) * 1.35 / 1000.0 / float(fc.get("speed_kmh", 34.0)) * 60.0, "day": e.day})
		started += 1
	st["trips"] = trips
	return started


## Every game minute: unload at stops whose time has come, bring vans home.
static func minute(e: Empire) -> void:
	var st := state(e)
	if st.is_empty():
		return
	var fc: Dictionary = cfg().get("fleet", {})
	var runs: Array = fc.get("runs", [6.0, 13.0])
	var h := e.minute / 60.0
	for r in runs:
		var key := "run_%d_%d" % [e.day, int(float(r) * 10)]
		if h >= float(r) and h < float(r) + 3.0 and not st.has(key):
			st[key] = true
			for k in st.keys():
				if String(k).begins_with("run_") and not String(k).begins_with("run_%d_" % e.day):
					st.erase(k)
			dispatch(e)
	var trips: Array = st.get("trips", [])
	var keep: Array = []
	for t: Dictionary in trips:
		var v := e.vehicle(String(t["vid"]))
		var late := int(t.get("day", e.day)) < e.day
		for s: Dictionary in t["stops"]:
			if s.get("done", false) or (float(s["eta"]) > e.minute and not late):
				continue
			s["done"] = true
			var b := e.business(String(s["biz"]))
			var n := 0
			for pid in s["lines"]:
				var units := int(s["lines"][pid]) * EmpireData.case_qty(pid)
				if v.is_empty():
					continue
				if b == null:
					Stock.transfer(v["cargo"], stock(e), pid, units)
					continue
				var room := b.backroom.room_for(pid)
				if room < units:
					b.backroom.case_capacity += Stock.cases_for(pid, units - room)
				n += Stock.transfer(v["cargo"], b.backroom, pid, units) / maxi(EmpireData.case_qty(pid), 1)
			if b != null and n > 0:
				var fl: Dictionary = fleet(e).get(String(t["vid"]), {})
				fl["cases"] = int(fl.get("cases", 0)) + n
				e.stats["fleet_cases"] = int(e.stats.get("fleet_cases", 0)) + n
				e._note("%s: %d cases from the warehouse" % [b.name, n], "info", {"kind": "biz", "id": b.id, "tab": "stock"})
				e.stock_delivered.emit(b)
				e.fleet_arrived.emit(b, String(t["vid"]))
		if float(t["back"]) <= e.minute or late:
			if not v.is_empty():
				# Anything not unloaded goes back on the racks.
				for pid in (v["cargo"] as Stock).units.keys():
					Stock.transfer(v["cargo"], stock(e), pid, (v["cargo"] as Stock).qty(pid))
				e.drive(v, float(t["km"]))
				var fl: Dictionary = fleet(e).get(String(t["vid"]), {})
				fl["runs"] = int(fl.get("runs", 0)) + 1
				fl["km"] = float(fl.get("km", 0.0)) + float(t["km"])
				var fuel := float(t["km"]) * float(fc.get("fuel_per_km", 0.32))
				e.company_cash -= fuel
				e._book("company", -fuel, "fuel", "Fleet diesel")
		else:
			keep.append(t)
	st["trips"] = keep


## Vans out on a round right now: [{vid, next stop biz, eta}].
static func on_the_road(e: Empire) -> Array:
	var out: Array = []
	for t: Dictionary in state(e).get("trips", []):
		for s: Dictionary in t["stops"]:
			if not s.get("done", false):
				out.append({"vid": t["vid"], "biz": s["biz"], "eta": s["eta"]})
				break
	return out


# ---------------------------------------------------------------- contracts
static func contracts(e: Empire) -> Array:
	return state(e).get("contracts", [])


static func offers(e: Empire) -> Array:
	return state(e).get("offers", [])


static func _make_offer(e: Empire) -> Dictionary:
	var cc: Dictionary = cfg().get("contracts", {})
	var cats := ["drinks", "snacks", "groceries", "hot", "bakery", "household", "sweets"]
	var cat: String = cats[e.rng.randi() % cats.size()]
	var pids: Array = EmpireData.product_ids().filter(func(p): return String(EmpireData.product(p).get("cat", "")) == cat)
	if pids.is_empty():
		return {}
	var pid: String = pids[e.rng.randi() % pids.size()]
	var cases := e.rng.randi_range(int(cc["cases"][0]), int(cc["cases"][1]))
	var days := e.rng.randi_range(int(cc["days"][0]), int(cc["days"][1]))
	var margin := e.rng.randf_range(float(cc["margin"][0]), float(cc["margin"][1]))
	var clients: Array = cc.get("clients", ["A client"])
	return {"id": e.new_id("ct"), "client": clients[e.rng.randi() % clients.size()], "pid": pid, "cases": cases, "days": days,
		"price": snappedf(e.case_price(pid) * (1.0 + margin), 0.05), "expires": e.day + 2}


static func accept(e: Empire, offer_id: String) -> String:
	var st := state(e)
	if fleet(e).is_empty():
		return "Put a van on the rounds first"
	for o: Dictionary in offers(e):
		if o["id"] == offer_id:
			(st["offers"] as Array).erase(o)
			o["start"] = e.day + 1
			o["left"] = int(o["days"])
			o["shipped"] = 0
			o["short"] = 0
			(st["contracts"] as Array).append(o)
			e._note("Contract signed with %s" % o["client"], "good", {"kind": "tab", "id": "company"})
			e.changed.emit()
			return ""
	return "That offer's gone"


static func end_day(e: Empire) -> Dictionary:
	var st := state(e)
	var out := {"revenue": 0.0, "profit": 0.0, "upkeep": 0.0}
	if st.is_empty():
		return out
	var cc: Dictionary = cfg().get("contracts", {})
	# Contracts ship from the warehouse.
	var keep: Array = []
	for c: Dictionary in contracts(e):
		if int(c.get("start", e.day)) > e.day:
			keep.append(c)
			continue
		var pid := String(c["pid"])
		var cq := maxi(EmpireData.case_qty(pid), 1)
		var have := stock(e).qty(pid) / cq
		var send := mini(int(c["cases"]), have) if not fleet(e).is_empty() else 0
		if send > 0:
			var cost_basis := e.unit_cost(pid) * cq * send
			stock(e).destroy(pid, send * cq)
			var rev := float(c["price"]) * send
			e.company_cash += rev
			e._book("company", rev, "sales", "Contract: %s" % c["client"])
			out["revenue"] = float(out["revenue"]) + rev
			out["profit"] = float(out["profit"]) + rev - cost_basis
			c["shipped"] = int(c["shipped"]) + send
		var short := int(c["cases"]) - send
		if short > 0:
			var pen := float(c["price"]) * short * float(cc.get("penalty_k", 0.5))
			e.company_cash -= pen
			e._book("company", -pen, "fees", "Contract shortfall: %s" % c["client"])
			out["profit"] = float(out["profit"]) - pen
			c["short"] = int(c["short"]) + short
		c["left"] = int(c["left"]) - 1
		if int(c["left"]) <= 0:
			if int(c["short"]) == 0:
				st["done"] = int(st.get("done", 0)) + 1
				e.stats["contracts_done"] = int(e.stats.get("contracts_done", 0)) + 1
				e._note("Contract with %s completed in full" % c["client"], "good")
			else:
				e._note("Contract with %s ended %d cases short" % [c["client"], int(c["short"])], "warn")
		else:
			keep.append(c)
	st["contracts"] = keep
	# New offers.
	var offs: Array = offers(e).filter(func(o): return int(o["expires"]) >= e.day + 1)
	if e.day % int(cc.get("offer_every_days", 2)) == 0 and offs.size() + keep.size() < int(cc.get("max_open", 3)) + 2:
		var o := _make_offer(e)
		if not o.is_empty():
			offs.append(o)
	st["offers"] = offs
	# Running costs: upkeep and the drivers.
	var up := float(site(e).get("upkeep", 0.0))
	for vid in fleet(e):
		up += float(fleet(e)[vid].get("wage", 13.5)) * 8.0
	e.company_cash -= up
	e._book("company", -up, "upkeep", "Warehouse & drivers")
	out["upkeep"] = up
	out["profit"] = float(out["profit"]) - up
	var wk: Array = st.get("week", [])
	wk.append({"day": e.day, "revenue": out["revenue"], "profit": out["profit"]})
	st["week"] = wk.slice(maxi(wk.size() - 7, 0))
	return out


static func week_value(e: Empire, key: String) -> float:
	var v := 0.0
	for d: Dictionary in state(e).get("week", []):
		v += float(d.get(key, 0.0))
	return v


static func assets_value(e: Empire) -> float:
	var st := state(e)
	if st.is_empty():
		return 0.0
	return float(st.get("paid", 0.0)) * 0.85 + int(st.get("racks", 0)) * float(cfg().get("racking", {}).get("cost", 22000)) * 0.6
