class_name CityLife
extends RefCounted
## The city around your shops (pure data, config/empire/events.json):
##
##  * Weather: rolled each morning from yesterday's forecast. It scales
##    footfall and what people come in for (rain sells coffee, a heatwave
##    sells cold drinks) and the 3-D sky follows it.
##  * Events: at most one new one a day – a street festival, a wholesale
##    deal or shortage, a hygiene inspection, a viral review, a sick
##    employee, a break-in (CCTV stops it), payday.
##  * Rivals: the QuikSave chain opens stores in free units (often near
##    yours) and takes shoppers within the competition radius. Buy them out;
##    after a few buy-outs the chain stops expanding, and when the last
##    store is yours QuikSave leaves the city.
##  * Firms: independent shops trading in most of the smaller units. They
##    compete a little, go up for sale when an owner retires (and close if
##    nobody buys) and new ones open; buy one to take over a running shop.
##
## Everything lives in Empire's saved state (weather, forecast, events,
## rivals, firms, news); Empire.market (the city's shop units) is set by the game
## and isn't saved.


static func cfg() -> Dictionary:
	return EmpireData.file("events")


static func weather_def(id: String) -> Dictionary:
	return (cfg().get("weather", {}) as Dictionary).get(id, {"name": id, "footfall": 1.0, "mix": {}, "sky": "clear"})


static func rival_cfg() -> Dictionary:
	return cfg().get("rivals", {})


# ----------------------------------------------------------- the day
## New game: fair weather, no events, the chain's first stores.
static func start(e: Empire) -> void:
	e.weather = "sunny"
	e.forecast = _roll_weather(e)
	e.events.clear()
	e.rivals.clear()
	e.news.clear()
	e.firms.clear()
	e.flags.erase("firms_seeded")
	for i in int(rival_cfg().get("start", 2)):
		_open_rival(e, true)
	ensure_firms(e)
	_headline(e, "Welcome to the city. %s runs %d stores here – for now." % [rival_cfg().get("name", "QuikSave"), e.rivals.size()], "info")


## Called once each morning (after the day closes, day already advanced).
static func new_day(e: Empire) -> void:
	# Yesterday's one-day effects end.
	for b: Business in e.businesses:
		for st in b.staff:
			st.erase("off")
	e.events = e.events.filter(func(ev): return int(ev.get("until", 0)) >= e.day)
	e.weather = e.forecast if e.forecast != "" else "cloudy"
	e.forecast = _roll_weather(e)
	var wd := weather_def(e.weather)
	if e.weather in ["rain", "storm", "heatwave", "foggy"]:
		_headline(e, "%s today. %s" % [wd.get("name", e.weather), _weather_tip(e.weather)], "info")
	# A new event?
	if e.rng.randf() < float(cfg().get("event_chance", 0.6)):
		_roll_event(e)
	_rivals_day(e)
	_firms_day(e)


static func _weather_tip(w: String) -> String:
	match w:
		"rain", "storm":
			return "Fewer shoppers, but hot drinks fly out."
		"heatwave":
			return "Stock the fridges: cold drinks sell double."
		"foggy":
			return "A slow, misty day: hot drinks sell, cold ones don't."
	return ""


static func _roll_weather(e: Empire) -> String:
	var ws: Dictionary = cfg().get("weather", {})
	var total := 0.0
	for k in ws:
		total += float(ws[k].get("weight", 1.0))
	var r := e.rng.randf() * total
	for k in ws:
		r -= float(ws[k].get("weight", 1.0))
		if r <= 0.0:
			return k
	return "cloudy"


static func _roll_event(e: Empire) -> void:
	var evs: Dictionary = cfg().get("events", {})
	var opts: Array = []
	var total := 0.0
	for k in evs:
		# Events about your shops need shops (and staff for a sick day).
		if k in ["inspection", "viral", "burglary"] and e.businesses.is_empty():
			continue
		if k == "sick" and e.businesses.all(func(b): return b.staff.is_empty()):
			continue
		opts.append(k)
		total += float(evs[k].get("weight", 1.0))
	var r := e.rng.randf() * total
	var kind := ""
	for k in opts:
		r -= float(evs[k].get("weight", 1.0))
		if r <= 0.0:
			kind = k
			break
	if kind != "":
		trigger(e, kind)


## Starts an event (tests call it directly). Returns the event dict.
static func trigger(e: Empire, kind: String, target := "") -> Dictionary:
	var d: Dictionary = cfg().get("events", {}).get(kind, {})
	var ev := {"kind": kind, "until": e.day + int(d.get("days", 1)) - 1}
	var text := String(d.get("text", kind))
	match kind:
		"festival":
			var ks: Array = EmpireData.economy().get("districts", {}).keys()
			# Usually somewhere you trade.
			var mine: Array = []
			for b: Business in e.businesses:
				mine.append(b.district_key())
			var dk: String = target if target != "" else (mine[e.rng.randi() % mine.size()] if not mine.is_empty() and e.rng.randf() < 0.6 else ks[e.rng.randi() % ks.size()])
			ev["district"] = dk
			ev["k"] = float(d.get("footfall", 1.5))
			text = text % EmpireData.district(dk).get("name", dk)
		"deal", "price_rise":
			var ids: Array = EmpireData.product_ids()
			var pid: String = target if target != "" else ids[e.rng.randi() % ids.size()]
			ev["product"] = pid
			ev["k"] = float(d.get("price", 1.0))
			text = text % EmpireData.product(pid).get("name", pid)
		"payday":
			ev["k"] = float(d.get("footfall", 1.2))
		"inspection", "viral", "burglary":
			var b := _pick_business(e, target)
			if b == null:
				return {}
			ev["biz"] = b.id
			text = text % b.name
			if kind == "viral":
				b.add_rep(float(d.get("rep", 10)))
			elif kind == "burglary":
				text = _burglary(e, b, float(d.get("share", 0.2)), text)
			elif kind == "inspection":
				ev["hour"] = int(d.get("hour", 14))
		"sick":
			var pool: Array = []
			for b: Business in e.businesses:
				for st in b.staff:
					if target == "" or st["id"] == target:
						pool.append([b, st])
			if pool.is_empty():
				return {}
			var pick: Array = pool[e.rng.randi() % pool.size()]
			ev["biz"] = (pick[0] as Business).id
			text = text % ("%s (%s, %s)" % [pick[1]["name"], EmpireData.role(pick[1]["role"]).get("name", ""), (pick[0] as Business).name])
			if Offices.recruitment(e)[2]:
				text += " Your recruitment agency's temp covers the shift."   # (no lost shift)
			else:
				pick[1]["off"] = true
	ev["text"] = text
	e.events.append(ev)
	var kind_col := "good" if kind in ["festival", "deal", "viral", "payday"] else ("bad" if kind in ["burglary", "price_rise"] else "warn")
	_headline(e, text, kind_col)
	return ev


static func _pick_business(e: Empire, id: String) -> Business:
	if e.businesses.is_empty():
		return null
	if id != "":
		return e.business(id)
	return e.businesses[e.rng.randi() % e.businesses.size()]


static func _burglary(e: Empire, b: Business, share: float, text: String) -> String:
	if b.has_upgrade("security"):
		return text + " – the CCTV scared them off. Nothing taken."
	var lost := 0
	var lost_cost := 0.0
	for pid in b.backroom.units.keys():
		var n := int(floor(float(b.backroom.qty(pid)) * share))
		if n > 0:
			b.backroom.destroy(pid, n)
			lost += n
			lost_cost += e.unit_cost(pid) * n
	b.today["stolen"] = int(b.today.get("stolen", 0)) + lost
	b.today["other"] = float(b.today.get("other", 0.0)) + lost_cost
	e.stats["units_stolen"] = int(e.stats.get("units_stolen", 0)) + lost
	if lost == 0:
		return text + ": the stock room was empty, nothing taken."
	return text + ": %d units taken from the stock room (%s). CCTV would have stopped it." % [lost, EmpireData.money(lost_cost)]


## Each minute: inspections happen at their hour.
static func minute(e: Empire) -> void:
	if int(e.minute) % 60 != 0:
		return
	var h := int(e.minute) / 60
	for ev in e.events:
		if ev.get("kind") == "inspection" and int(ev.get("hour", -1)) == h and not ev.get("done", false):
			ev["done"] = true
			_inspect(e, ev)


static func _inspect(e: Empire, ev: Dictionary) -> void:
	var b := e.business(String(ev.get("biz", "")))
	if b == null:
		return
	var d: Dictionary = cfg()["events"]["inspection"]
	if b.cleanliness >= float(d.get("good", 0.72)):
		b.add_rep(float(d.get("rep", 8)))
		e.stats["inspections_passed"] = int(e.stats.get("inspections_passed", 0)) + 1
		ev["result"] = "pass"
		_headline(e, "%s scored 5 stars for hygiene. Shoppers noticed (+%d ★)." % [b.name, int(d.get("rep", 8))], "good")
	elif b.cleanliness < float(d.get("bad", 0.45)):
		var fine := float(d.get("fine", 150))
		e.company_cash -= fine
		e._book("company", -fine, "fine", "Hygiene fine: %s" % b.name, b.id)
		b.today["other"] = float(b.today.get("other", 0.0)) + fine
		b.add_rep(-float(d.get("rep", 8)))
		ev["result"] = "fail"
		_headline(e, "%s failed its hygiene inspection: %s fine. Hire a cleaner!" % [b.name, EmpireData.money(fine)], "bad")
	else:
		ev["result"] = "ok"
		_headline(e, "%s passed its inspection (could be cleaner)." % b.name, "info")


# ------------------------------------------------------------- effects
## Footfall multiplier for a business today: weather × festival × payday.
static func footfall_k(e: Empire, b: Business) -> float:
	var k := float(weather_def(e.weather).get("footfall", 1.0))
	for ev in e.events:
		match String(ev.get("kind")):
			"festival":
				if ev.get("district") == b.district_key():
					k *= float(ev.get("k", 1.0))
			"payday", "campaign":
				k *= float(ev.get("k", 1.0))
	# The football (home-game crowds, a title), your marketing agency.
	k *= Club.footfall_k(e, b) * Club.trophy_k(e) * (1.0 + Offices.footfall_bonus(e))
	return k * e.hq_footfall_k()


## Category weights for what shoppers want today (weather).
static func mix_k(e: Empire) -> Dictionary:
	return weather_def(e.weather).get("mix", {})


## Wholesale price multiplier for a product (deals and shortages).
static func price_k(e: Empire, pid: String) -> float:
	var k := 1.0
	for ev in e.events:
		if ev.get("product", "") == pid:
			k *= float(ev.get("k", 1.0))
	return k


# --------------------------------------------------------------- rivals
static func is_rival(e: Empire, unit_id: String) -> bool:
	return e.rivals.any(func(r): return r["unit"] == unit_id)


static func rival_at(e: Empire, unit_id: String) -> Dictionary:
	for r in e.rivals:
		if r["unit"] == unit_id:
			return r
	return {}


static func rival_price(r: Dictionary) -> float:
	return roundf(float(r.get("price", 8000.0)) * float(rival_cfg().get("price_k", 1.6)) / 50.0) * 50.0


static func _free_units(e: Empire) -> Array:
	return e.market.filter(func(u): return u.get("kind", "shop") == "shop" and e.business_at(u["id"]) == null \
		and not is_taken(e, u["id"]) and u["id"] != e.flags.get("start_unit", ""))


static func _open_rival(e: Empire, quiet := false) -> Dictionary:
	var rc := rival_cfg()
	var free := _free_units(e)
	var per := {}
	for r in e.rivals:
		per[r["district"]] = int(per.get(r["district"], 0)) + 1
	free = free.filter(func(u): return int(per.get(u["district"], 0)) < int(rc.get("per_district", 2)))
	if free.is_empty():
		return {}
	var pick: Dictionary = {}
	if not e.businesses.is_empty() and e.rng.randf() < float(rc.get("near_you", 0.6)):
		# Aggressive: the free unit nearest one of your shops.
		var best := INF
		for u in free:
			for b: Business in e.businesses:
				var d := _dist(u.get("pos", []), b.premises.get("pos", []))
				if d < best:
					best = d
					pick = u
	if pick.is_empty():
		pick = free[e.rng.randi() % free.size()]
	var r := {"unit": pick["id"], "district": pick["district"], "pos": pick.get("pos", []), "price": float(pick.get("price", 8000.0)),
		"name": "%s %s" % [rc.get("name", "QuikSave"), EmpireData.district(pick["district"]).get("name", "")], "opened": e.day}
	e.rivals.append(r)
	if not quiet:
		var near := e.businesses.filter(func(b): return _dist(r["pos"], b.premises.get("pos", [])) < float(EmpireData.economy().get("competition_radius", 140.0)))
		if near.is_empty():
			_headline(e, "%s opened a new store in %s." % [rc.get("name", "QuikSave"), EmpireData.district(r["district"]).get("name", "")], "info")
		else:
			_headline(e, "%s opened right by %s – it'll take some of your shoppers. Buy it out from the Rivals tab." % [rc.get("name", "QuikSave"), (near[0] as Business).name], "warn")
	return r


static func _dist(a, b) -> float:
	if not a is Array or not b is Array or (a as Array).size() < 3 or (b as Array).size() < 3:
		return INF
	return Vector2(a[0], a[2]).distance_to(Vector2(b[0], b[2]))


static func _rivals_day(e: Empire) -> void:
	var rc := rival_cfg()
	if e.flags.get("rival_gone", false) or int(e.stats.get("rivals_bought", 0)) >= int(rc.get("retreat_after", 3)):
		return
	if e.day >= int(rc.get("first_day", 4)) and (e.day - int(rc.get("first_day", 4))) % int(rc.get("every_days", 4)) == 0 \
			and e.rivals.size() < int(rc.get("max", 7)):
		_open_rival(e)


## Rival stores within the competition radius of a business.
static func rivals_near(e: Empire, b: Business) -> int:
	var r := float(EmpireData.economy().get("competition_radius", 140.0))
	var n := 0
	for rv in e.rivals:
		if _dist(rv["pos"], b.premises.get("pos", [])) < r:
			n += 1
	return n


## Buys a rival store: it becomes your business (freehold, its regulars
## stay: reputation 60). Returns the business or null (and why in `err`).
static func buy_out(e: Empire, unit: Dictionary, err := []) -> Business:
	var r := rival_at(e, unit.get("id", ""))
	if r.is_empty():
		err.append("Not a rival store")
		return null
	var price := rival_price(r)
	if not e.pay(price, "property", "Bought out %s" % r["name"]):
		err.append("Not enough money (%s)" % EmpireData.money(price))
		return null
	e.rivals.erase(r)
	var b := e._open_business(unit, "convenience")
	b.owned = true
	b.reputation = 60.0
	e.stats["rivals_bought"] = int(e.stats.get("rivals_bought", 0)) + 1
	var rc := rival_cfg()
	if e.rivals.is_empty() and int(e.stats["rivals_bought"]) >= int(rc.get("retreat_after", 3)):
		e.flags["rival_gone"] = true
		_headline(e, "%s has pulled out of the city. Every corner shop that matters is yours." % rc.get("name", "QuikSave"), "good")
	elif int(e.stats["rivals_bought"]) == int(rc.get("retreat_after", 3)):
		_headline(e, "%s has stopped opening stores. Buy the last %d and they're gone." % [rc.get("name", "QuikSave"), e.rivals.size()], "good")
	else:
		_headline(e, "You bought out %s. Its regulars are now your customers." % r["name"], "good")
	e._check_goals()
	e.changed.emit()
	return b


static func _headline(e: Empire, text: String, kind: String) -> void:
	e.news.append({"day": e.day, "text": text, "kind": kind})
	if e.news.size() > 40:
		e.news = e.news.slice(e.news.size() - 40)
	e._note(text, kind)


# --------------------------------------------------------------- firms
## Independent shops trading in the established units (Premises "est"):
## {unit, name, owner, district, pos, rent, price, rep, since, colour,
## for_sale, listed}. They compete for shoppers, sometimes go up for sale
## and close if nobody buys; buying one takes over a running shop.
static func firm_cfg() -> Dictionary:
	return cfg().get("firms", {})


static func is_firm(e: Empire, unit_id: String) -> bool:
	return e.firms.any(func(f): return f["unit"] == unit_id)


static func firm_at(e: Empire, unit_id: String) -> Dictionary:
	for f in e.firms:
		if f["unit"] == unit_id:
			return f
	return {}


## Someone else trades here (QuikSave or an independent).
static func is_taken(e: Empire, unit_id: String) -> bool:
	return is_rival(e, unit_id) or is_firm(e, unit_id)


## Seeds the independents once (new game, or the first load of an older save).
static func ensure_firms(e: Empire) -> void:
	if e.flags.get("firms_seeded", false) or e.market.is_empty():
		return
	e.flags["firms_seeded"] = true
	var fc := firm_cfg()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([e.seed, "firms"])
	for u in e.market:
		if not u.get("est", false) or e.business_at(u["id"]) != null or is_rival(e, u["id"]):
			continue
		if rng.randf() < float(fc.get("trading_share", 0.8)):
			_new_firm(e, u, rng, e.day - rng.randi_range(200, 4000))
	var n := mini(int(fc.get("for_sale_start", 3)), e.firms.size())
	for i in n:
		var f: Dictionary = e.firms[rng.randi() % e.firms.size()]
		f["for_sale"] = true
		f["listed"] = e.day


static func _new_firm(e: Empire, u: Dictionary, rng: RandomNumberGenerator, since: int) -> Dictionary:
	var fc := firm_cfg()
	var sd := EmpireData.file("staff")
	var first: Array = sd.get("first_names", ["Sam"])
	var last: Array = sd.get("last_names", ["Smith"])
	var owner := "%s %s" % [first[rng.randi() % first.size()], last[rng.randi() % last.size()]]
	# What kind of shop: weighted by the district (cafés in the Financial
	# District, boutiques in Old Town, takeaways by the docks…).
	var tw: Dictionary = (fc.get("types", {}) as Dictionary).get(u["district"], (fc.get("types", {}) as Dictionary).get("default", {"convenience": 1}))
	var type := "convenience"
	var tot := 0.0
	for k in tw:
		tot += float(tw[k])
	var pick := rng.randf() * tot
	for k in tw:
		pick -= float(tw[k])
		if pick <= 0.0:
			type = k
			break
	var kinds: Array = (fc.get("kinds_by_type", {}) as Dictionary).get(type, fc.get("kinds", ["Stores"]))
	var names: Array = (fc.get("names_by_type", {}) as Dictionary).get(type, fc.get("names", []))
	var nm := ""
	var r := rng.randf()
	if r < 0.45:
		nm = "%s %s" % [_possessive(owner.get_slice(" ", 1)), kinds[rng.randi() % kinds.size()]]
	elif r < 0.7:
		nm = "%s %s" % [_possessive(owner.get_slice(" ", 0)), kinds[rng.randi() % kinds.size()]]
	elif not names.is_empty():
		nm = names[rng.randi() % names.size()]
	else:
		nm = "%s %s" % [owner.get_slice(" ", 1), kinds[0]]
	var cols: Array = fc.get("colours", ["#2f7d4a"])
	var f := {"unit": u["id"], "name": nm, "owner": owner, "district": u["district"], "pos": u.get("pos", []),
		"rent": float(u.get("rent", 30.0)), "price": float(u.get("price", 7000.0)),
		"rep": roundf(clampf(rng.randfn(52.0, 14.0), 15.0, 90.0)), "since": since,
		"colour": cols[rng.randi() % cols.size()], "for_sale": false, "listed": 0, "type": type}
	e.firms.append(f)
	return f


static func _possessive(n: String) -> String:
	return n + ("'" if n.ends_with("s") else "'s")


## Rough daily profit of an independent (what its books show a buyer).
static func firm_profit(f: Dictionary) -> float:
	var d := EmpireData.district(f["district"])
	var td := EmpireData.business_type(String(f.get("type", "convenience")))
	var hours := 0.0
	for h in range(int(td.get("open", 7)), int(td.get("close", 22))):
		hours += EmpireData.hour_curve(float(h) + 0.5)
	var shoppers := float(d.get("footfall", 8.0)) * float(EmpireData.economy().get("footfall_scale", 1.0)) * hours \
		* (0.5 + float(f.get("rep", 50.0)) / 100.0) * 0.8 * float(td.get("footfall_k", 1.0))
	# What a shopper spends here, net of what it cost: the type's goods.
	var margin := 0.0
	var wsum := 0.0
	for pid in EmpireData.product_ids():
		var p := EmpireData.product(pid)
		if EmpireData.type_sells(String(f.get("type", "convenience")), pid):
			var w := float(p.get("demand", 1.0))
			margin += w * (float(p["rrp"]) - float(p["case_cost"]) / float(p["case_qty"]))
			wsum += w
	var basket: Array = td.get("basket", [1, 4])
	var per := (margin / maxf(wsum, 0.01)) * (float(basket[0]) + float(basket[1])) * 0.5 * 0.75
	var gross := shoppers * per * float(d.get("affluence", 1.0))
	return roundf(gross - float(f.get("rent", 30.0)) - 100.0 - float(td.get("utilities", 4.0)) * 3.0)


static func firm_price(f: Dictionary) -> float:
	var fc := firm_cfg()
	var v := float(f.get("rent", 30.0)) * float(fc.get("rent_days", 40)) + maxf(firm_profit(f), 15.0) * float(fc.get("goodwill_days", 20)) \
		+ float(fc.get("stock_value", 450))
	v *= float(fc.get("sale_discount", 0.8)) if f.get("for_sale", false) else float(fc.get("offer_premium", 1.25))
	return roundf(v / 50.0) * 50.0


static func firms_for_sale(e: Empire) -> Array:
	return e.firms.filter(func(f): return f.get("for_sale", false))


static func _firms_day(e: Empire) -> void:
	ensure_firms(e)
	if e.market.is_empty():
		return
	var fc := firm_cfg()
	for f in e.firms.duplicate():
		f["rep"] = clampf(float(f["rep"]) + e.rng.randf_range(-1.5, 1.5) + (50.0 - float(f["rep"])) * 0.02, 10.0, 95.0)
		if f.get("for_sale", false) and e.day - int(f.get("listed", 0)) > int(fc.get("close_after", 10)):
			e.firms.erase(f)
			_headline(e, "%s in %s has closed for good. The unit is to let." % [f["name"], _dname(f)], "info")
	if firms_for_sale(e).size() < int(fc.get("max_for_sale", 7)) and e.rng.randf() < float(fc.get("sale_chance", 0.05)) * 4.0:
		var cands := e.firms.filter(func(f): return not f.get("for_sale", false))
		if not cands.is_empty():
			var f: Dictionary = cands[e.rng.randi() % cands.size()]
			f["for_sale"] = true
			f["listed"] = e.day
			_headline(e, "For sale: %s in %s – %s is retiring. Asking %s." % [f["name"], _dname(f), f["owner"],
				EmpireData.money(firm_price(f))], "good")
	if e.rng.randf() < float(fc.get("open_chance", 0.25)):
		var free := _free_units(e).filter(func(u): return u.get("est", false))
		if not free.is_empty():
			var u: Dictionary = free[e.rng.randi() % free.size()]
			var f := _new_firm(e, u, e.rng, e.day)
			f["rep"] = 35.0
			var mine := e.businesses.filter(func(b): return _dist(f["pos"], b.premises.get("pos", [])) < float(EmpireData.economy().get("competition_radius", 140.0)))
			_headline(e, ("New independent %s opened near %s." % [f["name"], (mine[0] as Business).name]) if not mine.is_empty()
				else "New independent %s opened in %s." % [f["name"], _dname(f)], "warn" if not mine.is_empty() else "info")


static func _dname(f: Dictionary) -> String:
	return String(EmpireData.district(f.get("district", "")).get("name", ""))


## How much the independents within the competition radius weigh against a
## business (each counts as part of a competitor, capped).
static func firms_near(e: Empire, b: Business) -> float:
	var fc := firm_cfg()
	var r := float(EmpireData.economy().get("competition_radius", 140.0))
	var n := 0.0
	for f in e.firms:
		if _dist(f["pos"], b.premises.get("pos", [])) < r:
			n += float(fc.get("comp_weight", 0.3)) * (0.5 + float(f.get("rep", 50.0)) / 100.0)
	return minf(n, float(fc.get("comp_cap", 0.9)))


## Buys an independent: you take over the lease (rent from tomorrow), its
## regulars (reputation), the stock on its shelves and its cashier.
static func buy_firm(e: Empire, unit: Dictionary, err := []) -> Business:
	var f := firm_at(e, unit.get("id", ""))
	if f.is_empty():
		err.append("Not for sale")
		return null
	var price := firm_price(f)
	if not e.pay(price, "property", "Bought %s" % f["name"]):
		err.append("Not enough money (%s)" % EmpireData.money(price))
		return null
	e.firms.erase(f)
	var b := e._open_business(unit, String(f.get("type", "convenience")))
	b.name = f["name"]
	b.reputation = maxf(float(f["rep"]), 30.0)
	# The stock that came with it, on the shelves: its own kind of goods.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([e.seed, unit["id"], e.day])
	for pid in EmpireData.product_ids():
		var p := EmpireData.product(pid)
		if b.sells(pid) and rng.randf() < 0.85:
			e._receive(b.backroom, pid, EmpireData.case_qty(pid), float(p.get("case_cost", 0.0)) / float(EmpireData.case_qty(pid)))
	e.restock_from_backroom(b, 999)
	# The cashier stays on.
	var c := Staff.make(rng, "cashier", e.day, 90 + e.businesses.size())
	c["hired_day"] = e.day
	c["business"] = b.id
	b.staff.append(c)
	b.open = true
	e.stats["hires"] = int(e.stats.get("hires", 0)) + 1
	e.stats["firms_bought"] = int(e.stats.get("firms_bought", 0)) + 1
	_headline(e, "You bought %s from %s. Its regulars, stock and cashier come with it." % [f["name"], f["owner"]], "good")
	e._check_goals()
	e.changed.emit()
	return b
