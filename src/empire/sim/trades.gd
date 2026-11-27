class_name Trades
extends RefCounted
## Each trade plays differently (2026-11-27; config/empire/commerce.json).
## The corner shop's loop is the existing one (buy stock, price it, mind the
## margins). On top of it:
##
##  * Food (takeaway, café, bakery): a supplier range – value / market fresh /
##    artisan – sets what the food costs (booked against the day as a
##    supplier adjustment on the cost of goods) and how good it is (appeal,
##    and reputation drifts towards the range's level when you serve); the
##    menu size trades footfall against quality. Business.trade {supplier, menu}.
##  * Clothing: collections. Launching one costs money; it pulls shoppers and
##    lifts what they'll pay while it's fresh (it fades over fresh_days) and
##    only if it suits the district (designer labels die in the estates; resort
##    wear sells on sunny days). Business.trade {collection, launched}.
##  * Nightclub: a venue you buy (statistical: Thu–Sun nights). Entry price,
##    an event each night, popularity and VIP tables. Empire.flags.nightclub.
##  * Car rental: a Skyport desk, cars from your garage put on hire. Bookings
##    by class, price, condition and day; hired cars rack up km and wear (and
##    are away from your garage while on hire). Empire.flags.rental.
##  * Hotel facilities: the Skyport Hotel estate gains a restaurant, spa,
##    conference suite and rooftop bar: more guests, dearer rooms (Ventures
##    reads them in target_occupancy / unit_rent).
##
## What each loop gives a business shows up as Business.trade.quality /
## .footfall (read by Business.quality_bonus / footfall_bonus → DemandModel),
## refreshed by refresh() every hour, so the walking shoppers and the
## statistical ones both feel it.

const FOOD := ["takeaway", "cafe", "bakery"]


static func cfg() -> Dictionary:
	return EmpireData.file("commerce")


static func kind(b: Business) -> String:
	if b.type_id in FOOD:
		return "food"
	if b.type_id == "clothing":
		return "clothing"
	return "retail"


# --------------------------------------------------------------------- food
static func suppliers() -> Array:
	return cfg().get("food", {}).get("suppliers", [])


static func supplier_def(id: String) -> Dictionary:
	for s: Dictionary in suppliers():
		if s["id"] == id:
			return s
	return suppliers()[1] if suppliers().size() > 1 else {}


static func supplier(b: Business) -> Dictionary:
	return supplier_def(String(b.trade.get("supplier", "standard")))


static func set_supplier(e: Empire, b: Business, id: String) -> void:
	b.trade["supplier"] = id
	refresh_one(e, b)
	e._note("%s now buys %s" % [b.name, String(supplier_def(id).get("name", id)).to_lower()], "info", {"kind": "biz", "id": b.id})
	e.changed.emit()


static func set_menu(e: Empire, b: Business, size: String) -> void:
	if not cfg().get("food", {}).get("menu_sizes", {}).has(size):
		return
	b.trade["menu"] = size
	refresh_one(e, b)
	e.changed.emit()


# ----------------------------------------------------------------- clothing
static func collections() -> Array:
	return cfg().get("clothing", {}).get("collections", [])


static func collection_def(id: String) -> Dictionary:
	for c: Dictionary in collections():
		if c["id"] == id:
			return c
	return collections()[0] if not collections().is_empty() else {}


## 1 when just launched, fading to 0.25 after fresh_days.
static func freshness(e: Empire, b: Business) -> float:
	var days := float(e.day - int(b.trade.get("launched", e.day)))
	return clampf(1.0 - days / float(cfg().get("clothing", {}).get("fresh_days", 14)), 0.25, 1.0)


## How well a collection suits b's district (1 inside its affluence band).
static func fit(b: Business, c: Dictionary) -> float:
	var aff := float(b.district().get("affluence", 1.0))
	var band: Array = c.get("affluence", [0.0, 9.0])
	if aff >= float(band[0]) and aff <= float(band[1]):
		return 1.0
	var off := minf(absf(aff - float(band[0])), absf(aff - float(band[1])))
	return clampf(1.0 - off * 2.5, 0.2, 1.0)


static func launch_block(e: Empire, b: Business, id: String) -> String:
	var c := collection_def(id)
	if c.is_empty() or kind(b) != "clothing":
		return "Not a clothing store"
	if String(b.trade.get("collection", "basics")) == id and freshness(e, b) > 0.8:
		return "Already in store"
	if e.company_cash < float(c.get("launch", 0.0)):
		return "Needs %s" % EmpireData.money(float(c.get("launch", 0.0)))
	return ""


static func launch(e: Empire, b: Business, id: String) -> String:
	var why := launch_block(e, b, id)
	if why != "":
		return why
	var c := collection_def(id)
	if float(c.get("launch", 0.0)) > 0.0 and not e.pay(float(c["launch"]), "upgrade", "%s: %s launch" % [b.name, c["name"]], b.id):
		return "Not enough money"
	b.trade["collection"] = id
	b.trade["launched"] = e.day
	b.trade.erase("stale_noted")
	refresh_one(e, b)
	e._note("%s launched %s" % [b.name, c["name"]], "good", {"kind": "biz", "id": b.id})
	e.changed.emit()
	return ""


# -------------------------------------------------------- per-business lift
## Sets b.trade.quality / .footfall from its loop (+ the company's brand).
static func refresh_one(e: Empire, b: Business) -> void:
	var q := 0.0
	var f := 0.0
	match kind(b):
		"food":
			var s := supplier(b)
			q += float(s.get("quality", 0.0))
			var m: Array = cfg().get("food", {}).get("menu_sizes", {}).get(String(b.trade.get("menu", "classic")), [1.0, 0.0])
			f += float(m[0]) - 1.0
			q += float(m[1])
		"clothing":
			var c := collection_def(String(b.trade.get("collection", "basics")))
			var k := fit(b, c)
			var fr := freshness(e, b) if b.trade.has("launched") else 0.6
			q += float(c.get("quality", 0.0)) * (k * 2.0 - 1.0)
			var wf := 1.5 if c.has("weather") and e.weather == String(c["weather"]) else 1.0
			f += float(c.get("footfall", 0.0)) * fr * k * wf
	f += Company.brand_footfall(e)
	b.trade["quality"] = snappedf(q, 0.001)
	b.trade["footfall"] = snappedf(f, 0.001)


static func refresh(e: Empire) -> void:
	for b: Business in e.businesses:
		refresh_one(e, b)


## Before the day's books close: the food supplier's adjustment on the cost
## of goods (budget ranges save, artisan costs more) and reputation drift
## towards the range's level.
static func before_day_end(e: Empire) -> void:
	for b: Business in e.businesses:
		if kind(b) != "food":
			continue
		var s := supplier(b)
		var adj := float(b.today.get("cogs", 0.0)) * (float(s.get("cost_k", 1.0)) - 1.0)
		if absf(adj) > 0.005:
			b.today["other"] = float(b.today.get("other", 0.0)) + adj
			e.company_cash -= adj
			e._book("company", -adj, "stock", "%s: %s" % [b.name, s.get("name", "supplier")], b.id)
		if int(b.today.get("served", 0)) > 0:
			b.reputation = lerpf(b.reputation, float(s.get("rep_target", 55.0)), 0.06)


# ---------------------------------------------------------------- nightclub
static func club_cfg() -> Dictionary:
	return cfg().get("nightclub", {})


static func club_site(id: String) -> Dictionary:
	for s: Dictionary in club_cfg().get("sites", []):
		if s["id"] == id:
			return s
	return {}


static func club(e: Empire) -> Dictionary:
	return e.flags.get("nightclub", {})


static func owns_club(e: Empire) -> bool:
	return not club(e).is_empty()


static func buy_club(e: Empire, site_id: String) -> String:
	if owns_club(e):
		return "You already run a club"
	var s := club_site(site_id)
	if s.is_empty():
		return "No such venue"
	if not e.pay(float(s["price"]), "property", "Bought %s" % s["name"]):
		return "Needs %s" % EmpireData.money(float(s["price"]))
	e.flags["nightclub"] = {"site": site_id, "event": "house", "entry": 1, "pop": 50.0, "nights": [], "paid": float(s["price"]), "takings": 0.0}
	e._note("%s is yours – Thursday to Sunday nights" % s["name"], "good")
	e.changed.emit()
	return ""


static func event_def(id: String) -> Dictionary:
	for ev: Dictionary in club_cfg().get("events", []):
		if ev["id"] == id:
			return ev
	return club_cfg().get("events", [{}])[0]


static func set_club(e: Empire, key: String, value) -> void:
	var c := club(e)
	if c.is_empty():
		return
	c[key] = value
	e.changed.emit()


## Tonight's expected crowd (0 on a dark night).
static func club_forecast(e: Empire, weekday := "") -> Dictionary:
	var c := club(e)
	if c.is_empty():
		return {}
	var cc := club_cfg()
	var wd := weekday if weekday != "" else e.weekday()
	var night := float(cc.get("nights", {}).get(wd, 0.0))
	var s := club_site(String(c["site"]))
	var ev := event_def(String(c.get("event", "house")))
	var entry_i := clampi(int(c.get("entry", 1)), 0, 2)
	var entry := float(cc.get("entry", [6, 12, 20])[entry_i])
	var price_k := [1.18, 1.0, 0.76][entry_i] as float
	var wet := 0.88 if e.weather in ["rain", "storm", "showers"] else 1.0
	var pop := clampf(float(c.get("pop", 50.0)) / 70.0, 0.25, 1.5)
	var cap := int(s.get("capacity", 300))
	var crowd := mini(roundi(cap * night * float(ev.get("draw", 1.0)) * price_k * wet * pop), cap) if night > 0.0 else 0
	var vips := roundi(crowd * float(cc.get("vip_share", 0.04)) * float(ev.get("vip", 1.0)) * (1.3 if entry_i == 2 else 1.0))
	var takings := crowd * entry + crowd * float(cc.get("bar_spend", 24.0)) * 0.7 + vips * float(cc.get("vip_spend", 380.0)) * float(s.get("vip", 1.0))
	var staff := ceili(crowd / 100.0 * float(cc.get("staff_per_100", 6))) * float(cc.get("staff_wage_night", 95.0)) if crowd > 0 else 0.0
	var cost := (float(ev.get("cost", 0.0)) if crowd > 0 else 0.0) + staff
	return {"open": night > 0.0, "crowd": crowd, "capacity": cap, "vips": vips, "takings": takings, "cost": cost, "entry": entry}


static func club_day(e: Empire) -> float:
	var c := club(e)
	if c.is_empty():
		return 0.0
	var s := club_site(String(c["site"]))
	var f := club_forecast(e)
	var net := float(f["takings"]) - float(f["cost"]) - float(s.get("upkeep", 0.0))
	e.company_cash += net
	e._book("company", net, "club_night" if f["open"] else "upkeep", "%s %s" % [s["name"], "night" if f["open"] else "upkeep"])
	var pop := float(c.get("pop", 50.0))
	if f["open"]:
		var fill := float(f["crowd"]) / maxf(float(f["capacity"]), 1.0)
		pop += float(event_def(String(c.get("event", "house"))).get("pop", 0)) + (fill - 0.75) * 6.0
	c["pop"] = clampf(lerpf(pop, 50.0, 0.04), 5.0, 100.0)
	c["takings"] = float(c.get("takings", 0.0)) + net
	var nights: Array = c.get("nights", [])
	nights.append({"day": e.day, "wd": e.weekday(), "crowd": f["crowd"], "vips": f["vips"], "net": net})
	c["nights"] = nights.slice(maxi(nights.size() - 14, 0))
	return net


static func club_value(e: Empire) -> float:
	return float(club(e).get("paid", 0.0))


# ------------------------------------------------------------------- rental
static func rental_cfg() -> Dictionary:
	return cfg().get("rental", {})


static func rental(e: Empire) -> Dictionary:
	return e.flags.get("rental", {})


static func owns_rental(e: Empire) -> bool:
	return not rental(e).is_empty()


static func buy_rental(e: Empire) -> String:
	if owns_rental(e):
		return "Already open"
	var d: Dictionary = rental_cfg().get("desk", {})
	if not e.pay(float(d.get("price", 45000)), "property", "Opened %s" % d.get("name", "car hire")):
		return "Needs %s" % EmpireData.money(float(d.get("price", 45000)))
	e.flags["rental"] = {"cars": {}, "price_k": 1.0, "paid": float(d.get("price", 45000)), "takings": 0.0, "days": []}
	e._note("%s is open: put cars from your garage on hire" % d.get("name", "Car hire"), "good")
	e.changed.emit()
	return ""


static func rental_class(v: Dictionary) -> String:
	return String(rental_cfg().get("model_class", {}).get(String(v.get("model", "")), ""))


static func rentable(v: Dictionary) -> bool:
	return not v.is_empty() and not v.get("test", false) and rental_class(v) != "" and String(v.get("driver", "")) == "" \
		and not v.get("fleet", false)


static func on_hire(e: Empire, vid: String) -> bool:
	return bool(rental(e).get("cars", {}).get(vid, false))


static func toggle_hire(e: Empire, vid: String) -> bool:
	var r := rental(e)
	var v := e.vehicle(vid)
	if r.is_empty() or v.is_empty():
		return false
	var cars: Dictionary = r.get("cars", {})
	if cars.has(vid):
		cars.erase(vid)
		v.erase("hire")
	elif rentable(v):
		cars[vid] = true
		v["hire"] = true
	r["cars"] = cars
	e.changed.emit()
	return cars.has(vid)


static func day_rate(v: Dictionary, price_k := 1.0) -> float:
	return float(rental_cfg().get("classes", {}).get(rental_class(v), 40.0)) * price_k


static func hire_chance(e: Empire, v: Dictionary) -> float:
	var r := rental(e)
	var pk := float(r.get("price_k", 1.0))
	var price := clampf(1.0 - (pk - 1.0) * 1.6, 0.35, 1.3)
	var cond := smoothstep(0.25, 0.85, float(v.get("condition", 1.0)))
	var wk := 1.15 if e.weekday() in ["Fri", "Sat", "Sun"] else 1.0
	return clampf(float(rental_cfg().get("base_occ", 0.62)) * price * cond * wk, 0.0, 0.97)


static func rental_day(e: Empire) -> float:
	var r := rental(e)
	if r.is_empty():
		return 0.0
	var cars: Dictionary = r.get("cars", {})
	var net := 0.0
	var booked := 0
	for vid in cars.keys():
		var v := e.vehicle(String(vid))
		if v.is_empty():
			cars.erase(vid)
			continue
		if e.rng.randf() < hire_chance(e, v):
			booked += 1
			net += day_rate(v, float(r.get("price_k", 1.0)))
			# (Hirers pay their own fuel; a day's hire wears a car like a
			# few minutes of your own driving – not 140 km of it.)
			var km := float(rental_cfg().get("km_per_day", 140)) * e.rng.randf_range(0.5, 1.4)
			v["km"] = float(v.get("km", 0.0)) + km
			v["condition"] = maxf(float(v.get("condition", 1.0)) - float(rental_cfg().get("wear_per_hire", 0.012)), 0.0)
	var up := float(rental_cfg().get("desk", {}).get("upkeep", 35))
	e.company_cash += net - up
	if net > 0.0:
		e._book("company", net, "rental", "Car hire: %d bookings" % booked)
	e._book("company", -up, "upkeep", "Car hire desk")
	r["takings"] = float(r.get("takings", 0.0)) + net - up
	var days: Array = r.get("days", [])
	days.append({"day": e.day, "booked": booked, "fleet": cars.size(), "net": net - up})
	r["days"] = days.slice(maxi(days.size() - 14, 0))
	return net - up


# -------------------------------------------------------------------- hotel
static func hotel_facilities() -> Array:
	return cfg().get("hotel", {}).get("facilities", [])


static func has_facility(st: Dictionary, id: String) -> bool:
	return (st.get("fac", []) as Array).has(id)


static func hotel_occ_k(st: Dictionary) -> float:
	var k := 0.0
	for f: Dictionary in hotel_facilities():
		if has_facility(st, f["id"]):
			k += float(f.get("occ", 0.0))
	return k


static func hotel_rate_k(st: Dictionary) -> float:
	var k := 0.0
	for f: Dictionary in hotel_facilities():
		if has_facility(st, f["id"]):
			k += float(f.get("rate", 0.0))
	return k


static func hotel_upkeep(st: Dictionary) -> float:
	var k := 0.0
	for f: Dictionary in hotel_facilities():
		if has_facility(st, f["id"]):
			k += float(f.get("upkeep", 0.0))
	return k


static func build_facility(e: Empire, estate_id: String, fac_id: String) -> String:
	var st: Dictionary = e.flags.get("estates", {}).get(estate_id, {})
	if st.is_empty() or String(Ventures.estate_def(estate_id).get("kind", "")) != "hotel":
		return "You don't own the hotel"
	if has_facility(st, fac_id):
		return "Already built"
	for f: Dictionary in hotel_facilities():
		if f["id"] == fac_id:
			if not e.pay(float(f["cost"]), "upgrade", "Hotel: %s" % f["name"]):
				return "Needs %s" % EmpireData.money(float(f["cost"]))
			var fac: Array = st.get("fac", [])
			fac.append(fac_id)
			st["fac"] = fac
			e._note("Skyport Hotel: %s open" % f["name"], "good")
			e.changed.emit()
			return ""
	return "No such facility"


# --------------------------------------------------------------- the day
static func end_day(e: Empire) -> Dictionary:
	var out := {"club": club_day(e), "rental": rental_day(e)}
	for b: Business in e.businesses:
		if kind(b) == "clothing" and b.trade.has("launched") and freshness(e, b) <= 0.3 and not b.trade.get("stale_noted", false):
			b.trade["stale_noted"] = true
			e._note("%s: the %s collection is looking tired – launch a new one" % [b.name, collection_def(String(b.trade.get("collection", ""))).get("name", "")], "warn", {"kind": "biz", "id": b.id})
	return out


static func assets_value(e: Empire) -> float:
	return club_value(e) + float(rental(e).get("paid", 0.0)) * 0.8
