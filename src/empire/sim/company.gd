class_name Company
extends RefCounted
## Your company (2026-11-27): the brand (Empire.brand: name, colours, sign
## face – ShopStyle.house_ident) plus a logo mark, grouped into divisions with
## consolidated books. The same identity is painted on every shopfront you
## own (ShopStyle.house), your head office, warehouse and the delivery fleet's
## vans (SupplyChain fleet → CarPaint livery). A recognised brand pulls
## shoppers: every branch past the second adds a little footfall to all of
## them (brand_footfall), up to +10%.

const LOGOS := ["monogram", "circle", "diamond", "bars", "arch", "star"]


static func name_of(e: Empire) -> String:
	var n := String(e.brand.get("name", ""))
	return n if n != "" else "Your company"


static func has_brand(e: Empire) -> bool:
	return String(e.brand.get("name", "")) != ""


static func logo(e: Empire) -> String:
	var l := String(e.brand.get("logo", "monogram"))
	return l if LOGOS.has(l) else "monogram"


static func set_logo(e: Empire, id: String) -> void:
	if LOGOS.has(id):
		e.brand["logo"] = id
		e.changed.emit()


static func initials(e: Empire) -> String:
	var parts := name_of(e).split(" ", false)
	var s := ""
	for p in parts:
		if s.length() < 2 and p.length() > 0 and p[0] == p[0].to_upper():
			s += p[0]
	return s if s != "" else name_of(e).left(1).to_upper()


static func colours(e: Empire) -> Array:
	var id := ShopStyle.house_ident(e.brand) if has_brand(e) else {}
	var p: Color = id.get("primary", Color(0.12, 0.2, 0.32)) if id.get("primary") is Color else Color(0.12, 0.2, 0.32)
	var a: Color = id.get("accent", Color(0.95, 0.75, 0.3)) if id.get("accent") is Color else Color(0.95, 0.75, 0.3)
	return [p, a]


static func brand_footfall(e: Empire) -> float:
	if not has_brand(e):
		return 0.0
	return clampf(float(e.businesses.size() - 2) * 0.02, 0.0, 0.1)


## Divisions: the trades you run, each with its last-7-day books, plus the
## non-shop arms (offices, estates, club, hire, warehouse).
static func divisions(e: Empire) -> Array:
	var by := {}
	for b: Business in e.businesses:
		var key := b.type_id
		if not by.has(key):
			by[key] = {"id": key, "name": "%s %s" % [name_of(e), _trade_word(key)], "trade": String(b.type_def().get("name", key)),
				"branches": 0, "revenue": 0.0, "profit": 0.0, "top_level": 1}
		var d: Dictionary = by[key]
		d["branches"] = int(d["branches"]) + 1
		d["top_level"] = maxi(int(d["top_level"]), b.level)
		for r: Dictionary in b.history.slice(maxi(b.history.size() - 7, 0)):
			d["revenue"] = float(d["revenue"]) + float(r.get("revenue", 0.0))
			d["profit"] = float(d["profit"]) + float(r.get("profit", 0.0))
	var out: Array = by.values()
	out.sort_custom(func(a, b): return float(a["revenue"]) > float(b["revenue"]))
	if SupplyChain.has_warehouse(e):
		out.append({"id": "logistics", "name": "%s Logistics" % name_of(e), "trade": "Warehousing & distribution",
			"branches": SupplyChain.fleet(e).size(), "revenue": SupplyChain.week_value(e, "revenue"), "profit": SupplyChain.week_value(e, "profit"), "top_level": 0})
	if Trades.owns_club(e):
		var net := 0.0
		for n: Dictionary in Trades.club(e).get("nights", []).slice(-7):
			net += float(n.get("net", 0.0))
		out.append({"id": "club", "name": String(Trades.club_site(String(Trades.club(e)["site"])).get("name", "Club")), "trade": "Nightlife",
			"branches": 1, "revenue": maxf(net, 0.0), "profit": net, "top_level": 0})
	if Trades.owns_rental(e):
		var net := 0.0
		for n: Dictionary in Trades.rental(e).get("days", []).slice(-7):
			net += float(n.get("net", 0.0))
		out.append({"id": "rental", "name": "%s Car Hire" % name_of(e), "trade": "Car rental",
			"branches": Trades.rental(e).get("cars", {}).size(), "revenue": maxf(net, 0.0), "profit": net, "top_level": 0})
	return out


## Industries the company trades in (for the career stages).
static func industries(e: Empire) -> int:
	var set := {}
	for b: Business in e.businesses:
		set[Trades.kind(b) + ":" + b.type_id] = true
	if SupplyChain.has_warehouse(e):
		set["logistics"] = true
	if Trades.owns_club(e):
		set["club"] = true
	if Trades.owns_rental(e):
		set["rental"] = true
	if not e.offices.is_empty():
		set["offices"] = true
	if not (e.flags.get("estates", {}) as Dictionary).is_empty():
		set["property"] = true
	if Ventures.owns_dealer(e):
		set["dealer"] = true
	return set.size()


static func islands(e: Empire) -> int:
	var set := {}
	for b: Business in e.businesses:
		set[b.island()] = true
	if not (e.flags.get("estates", {}) as Dictionary).is_empty() or Trades.owns_rental(e):
		set["skyport"] = true
	return set.size()


static func _trade_word(type_id: String) -> String:
	return {"convenience": "Stores", "takeaway": "Kitchens", "cafe": "Coffee", "bakery": "Bakeries",
		"clothing": "Fashion", "phones": "Tech"}.get(type_id, "Retail")
