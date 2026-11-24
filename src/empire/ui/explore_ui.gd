class_name ExploreUI
extends RefCounted
## Explore: every real place in the city worth going to, nearest first,
## by category – shops and boutiques, food and drink, cars and craft,
## suppliers, business opportunities, Skyport, landmarks and homes. Places
## you've walked or driven past are "discovered" (flags.seen); the rest are
## marked NEW. One tap sets the GPS route (both maps draw it); places with
## a card (independents, units to let) also open it.

const S = preload("res://src/empire/ui/empire_style.gd")
const SEE := 45.0          # m: passing this close discovers a place

## [key, label, colour]
const CATS := [["all", "Nearby", Color("#f3efe6")], ["shops", "Shops", Color("#f5b13d")], ["fashion", "Fashion", Color("#f06292")],
	["food", "Food & drink", Color("#ff8a65")], ["vehicles", "Cars & craft", Color("#4ea3ef")],
	["business", "Suppliers", Color("#9575cd")], ["opportunity", "For sale / to let", Color("#39c27f")],
	["landmark", "Landmarks", Color("#e9c27a")], ["yours", "Yours", Color("#f5b13d")]]

static var cat := "all"
static var _places: Array = []
static var _places_t := -1000000
static var _places_n := -1
static var _places_empire_id := 0


static func reset_cache() -> void:
	_places.clear()
	_places_t = -1000000
	_places_n = -1
	_places_empire_id = 0


static func clear_caches() -> void:
	reset_cache()
	cat = "all"


static func places(g: EmpireGame) -> Array:
	var e := g.empire
	var eid := e.get_instance_id()
	if eid == _places_empire_id and Time.get_ticks_msec() - _places_t < 20000 and _places_n == e.firms.size() + e.businesses.size() * 1000:
		return _places
	_places_empire_id = eid
	_places_t = Time.get_ticks_msec()
	_places_n = e.firms.size() + e.businesses.size() * 1000
	var out: Array = []
	# Skyport's named places.
	if g.skyport_play:
		var what := {"dealer_budget": ["vehicles", "Used and everyday cars"], "dealer_commercial": ["vehicles", "Vans and trucks"],
			"dealer_luxury": ["vehicles", "Sports and supercars"], "clothes_everyday": ["fashion", "Everyday clothing store"],
			"clothes_premium": ["fashion", "Designer fashion house"], "aviation": ["vehicles", "Helicopters and planes"],
			"marina": ["vehicles", "Boats and yachts"], "cargo": ["business", "Airport imports for your shops"],
			"terminal": ["landmark", "Skyport Airport terminal"]}
		for sid in what:
			var st := g.skyport_play.site(sid)
			if st.is_empty():
				continue
			out.append({"key": "site:" + sid, "name": String(st["name"]), "cat": what[sid][0], "what": what[sid][1], "pos": st["door"],
				"ref": {"kind": "place", "id": sid}})
	# Cash & carry.
	for isl in ["west", "east"]:
		var w := g.wholesaler(isl)
		if not w.is_empty():
			out.append({"key": "unit:" + String(w["id"]), "name": String(w.get("name", "Cash & Carry")), "cat": "business",
				"what": "Wholesale stock for your shops", "pos": Premises.door_point(w), "ref": {"kind": "unit", "id": w["id"]}})
	# Independents (their kind of shop), the QuikSave chain, your own shops.
	var firm_cat := {"clothing": ["fashion", "Independent boutique · shop clothes here"], "cafe": ["food", "Café"],
		"takeaway": ["food", "Takeaway"], "bakery": ["food", "Bakery"], "convenience": ["shops", "Convenience store"],
		"phones": ["shops", "Phone shop"]}
	for f in e.firms:
		var u: Dictionary = g.unit_by_id.get(f["unit"], {})
		if u.is_empty():
			continue
		var fc: Array = firm_cat.get(String(f.get("type", "convenience")), ["shops", "Shop"])
		var sale: bool = f.get("for_sale", false)
		out.append({"key": "unit:" + String(u["id"]), "name": String(f["name"]), "cat": "opportunity" if sale else fc[0],
			"what": (fc[1] + (" · FOR SALE %s" % EmpireData.money(CityLife.firm_price(f)) if sale else "")), "pos": Premises.door_point(u),
			"ref": {"kind": "unit", "id": u["id"]}, "firm": true, "unit": u})
	for r in e.rivals:
		var u2: Dictionary = g.unit_by_id.get(r["unit"], {})
		if not u2.is_empty():
			out.append({"key": "unit:" + String(u2["id"]), "name": String(r["name"]), "cat": "shops", "what": "QuikSave chain store · rival",
				"pos": Premises.door_point(u2), "ref": {"kind": "unit", "id": u2["id"]}, "rival": true, "unit": u2})
	for b: Business in e.businesses:
		var u3: Dictionary = g.unit_by_id.get(String(b.premises.get("id", "")), {})
		if not u3.is_empty():
			out.append({"key": "unit:" + String(u3["id"]), "name": b.name, "cat": "yours", "what": "Your %s" % String(EmpireData.business_type(b.type_id).get("name", "shop")).to_lower(),
				"pos": Premises.door_point(u3), "ref": {"kind": "biz", "id": b.id}, "biz": b})
	# Empty units to let (the nearest are listed; all are on the map).
	for u4 in g.units:
		if u4["kind"] == "shop" and g.occupier(u4["id"]).is_empty() and e.business_at(u4["id"]) == null:
			if u4.get("flagship", false):
				var use := String(u4["street_use"])
				var category := "fashion" if use in ["clothing", "department"] else "shops"
				out.append({"key": "unit:" + String(u4["id"]), "name": String(u4["name"]),
					"cat": category, "what": "%s · %d m²" % [Premises.STREET_TITLES[use], int(u4["size"])],
					"pos": Premises.door_point(u4), "ref": {"kind": "unit", "id": u4["id"]}, "unit": u4})
				continue
			out.append({"key": "unit:" + String(u4["id"]), "name": "%s unit" % EmpireData.district(u4["district"]).get("name", "Shop"),
				"cat": "opportunity", "what": "To let · %s/day · %d m²" % [EmpireData.money(float(u4["rent"])), int(u4.get("size", 0))],
				"pos": Premises.door_point(u4), "ref": {"kind": "unit", "id": u4["id"]}, "unit": u4, "vacant": true})
	# Landmarks and homes.
	out.append({"key": "stadium", "name": "The Heights Ground", "cat": "landmark", "what": "Football stadium · the club office",
		"pos": g.club_office_pos(), "ref": {"kind": "place", "id": "stadium"}})
	if not e.hq.is_empty():
		var hu := g.hq_unit()
		if not hu.is_empty():
			out.append({"key": "hq", "name": "Your head office", "cat": "yours", "what": "Head office", "pos": Premises.door_point(hu),
				"ref": {"kind": "unit", "id": hu["id"]}})
	for hm in g.homes():
		var h: Dictionary = hm["h"]
		var own := e.owns_property(String(hm["id"]))
		out.append({"key": String(hm["id"]), "name": String(hm["name"]), "cat": "yours" if own else "landmark",
			"what": "Your home" if own else "Home for sale · %s" % EmpireData.money(float(hm["price"])),
			"pos": Apartments.spawn_point(h), "ref": {"kind": "place", "id": String(hm["id"])}})
	_places = out
	return out


## Called by the game every second or so: mark what you've passed.
static func discover(g: EmpireGame) -> void:
	var here := g.vehicle_node().global_position if g.vehicle_node() else g.player.global_position
	var seen: Dictionary = g.empire.flags.get("seen", {})
	for p in places(g):
		if seen.has(p["key"]):
			continue
		var pp: Vector3 = p["pos"]
		if absf(pp.y - here.y) > 25.0 or Vector2(pp.x - here.x, pp.z - here.z).length_squared() >= SEE * SEE:
			continue
		var reward := g.empire.record_discovery(String(p["key"]), String(p["name"]), not p.get("vacant", false))
		if not reward["milestone"] and not p.get("vacant", false) and p["cat"] in ["fashion", "vehicles", "landmark", "food"]:
			g.ui.toast("Discovered: %s" % p["name"], "info")


static func tab(ui: EmpireUI, v: VBoxContainer) -> void:
	var g := ui.game
	var e := g.empire
	var here := g.vehicle_node().global_position if g.vehicle_node() else g.player.global_position
	var seen: Dictionary = e.flags.get("seen", {})
	var all := places(g)
	var top := S.hbox(8)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in CATS:
		var key := String(c[0])
		var n := all.filter(func(p): return key == "all" or p["cat"] == key).size()
		if n == 0 and key != "all":
			continue
		var b := S.chip_button("%s · %d" % [c[1], n] if key != "all" else String(c[1]), cat == key, func():
			cat = key
			ui.open_phone("explore"), c[2])
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 15)
		chips.add_child(b)
	top.add_child(chips)
	var found := all.filter(func(p): return seen.has(p["key"]) and not p.get("vacant", false)).size()
	var total := all.filter(func(p): return not p.get("vacant", false)).size()
	var dl := S.label("%d / %d discovered" % [found, total], 14, S.MUTED, "bold")
	top.add_child(dl)
	v.add_child(top)
	var list: Array = all.filter(func(p): return cat == "all" and not p.get("vacant", false) or p["cat"] == cat)
	list.sort_custom(func(a, b): return here.distance_squared_to(a["pos"]) < here.distance_squared_to(b["pos"]))
	if cat == "opportunity" or cat == "all":
		list = list.slice(0, 60)
	var col := S.vbox(6)
	if list.is_empty():
		col.add_child(S.label("Nothing here yet.", 16, S.MUTED))
	var gps_ref: Dictionary = e.flags.get("gps_ref", {})
	for p in list:
		col.add_child(_row(ui, p, here, seen.has(p["key"]), gps_ref == p["ref"]))
	v.add_child(ui._scroll(col, 370))


static func _row(ui: EmpireUI, p: Dictionary, here: Vector3, known: bool, routed: bool) -> Control:
	var g := ui.game
	var colr := Glass.BLUE
	for c in CATS:
		if c[0] == p["cat"]:
			colr = c[2]
	var pan := PanelContainer.new()
	var sb := Glass.box(Color(colr, 0.14) if routed else Glass.CARD, 18, 0, Color(colr, 0.45) if routed else Glass.SEP)
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	pan.add_theme_stylebox_override("panel", sb)
	var h := Glass.hbox(12)
	pan.add_child(h)
	var pp: Vector3 = p["pos"]
	var pid := String((p.get("ref", {}) as Dictionary).get("id", ""))
	if pid != "":
		var thumb := PhotoBook.frame(pid, "front", Vector2(96, 66), pp, 12)
		thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(thumb)
	var tv := Glass.vbox(2)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nh := Glass.hbox(8)
	var nm := Glass.line(String(p["name"]), "headline")
	nm.custom_minimum_size.x = 140
	nh.add_child(nm)
	if not known and not p.get("vacant", false) and p["cat"] != "yours":
		nh.add_child(Glass.badge("NEW", Glass.ACCENT_TEXT))
	if routed:
		nh.add_child(Glass.badge("ROUTE SET", colr))
	tv.add_child(nh)
	var d := Vector2(pp.x - here.x, pp.z - here.z).length()
	tv.add_child(Glass.line("%s  ·  %s  ·  %s" % [p["what"], ui._dist_text(d), _place_area(g, pp)], "footnote", Glass.LABEL2))
	h.add_child(tv)
	if p.has("unit") and not p.get("rival", false):
		var db := Glass.button("Details", func():
			if p.get("firm", false):
				ui.open_firm(p["unit"], true)
			else:
				ui.open_property(p["unit"], true), "gray", "small")
		db.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(db)
	elif p.has("biz"):
		var mb := Glass.button("Manage", func(): ui.open_manage(p["biz"]), "gray", "small")
		mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(mb)
	var mapb := Glass.button("Map", func(): ui.open_phone("map", p["ref"] if String(p["ref"].get("kind", "")) == "unit" else {}), "gray", "small")
	mapb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mapb)
	var gob := Glass.button("GPS", func():
		g.set_gps(pp, String(p["name"]), p["ref"])
		ui.close_panel(true)
		ui.toast("Route set: %s" % p["name"], "info"), "filled", "small", Glass.BLUE, "gps")
	gob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(gob)
	return pan


static func _place_area(g: EmpireGame, p: Vector3) -> String:
	if SkyportIsland.distance_to(p) < 1.0:
		return "Skyport"
	var isl := "Westbank" if g.layout.mainland and p.x < 0.0 else "Commercial Island"
	return isl
