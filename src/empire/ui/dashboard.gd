class_name Dashboard
extends RefCounted
## The phone's command centre, visual first:
##   nav      Home · Map · Businesses · Garage · More (one row of tabs; the
##            rest – Property, Finances, Corporate, City, Goals, Style,
##            Game – live under More)
##   Home     money and net worth, a small profit-yesterday mark, ONE row of
##            grouped alerts ("3 shops need attention" opens the list), and
##            picture cards: Garage (real model renders), Businesses (map
##            crops of your shops), Property, Airport, Explore, Your Empire
##            (net-worth sparkline)
##   Garage   every vehicle you own as a picture card: where it is, Find,
##            Deliver (cars), and the showrooms to buy more
## Alerts are grouped by kind across shops and only escalate when it's
## real: a single loss-making day is "watch", three in a row is a problem.

const S = preload("res://src/empire/ui/empire_style.gd")
const NAV := EmpireUI.PHONE_TABS


# ---------------------------------------------------------------- nav
static func nav(ui: EmpireUI, tab: String, in_more: bool) -> HBoxContainer:
	var h := S.hbox(6)
	for t in NAV:
		var key := String(t[0])
		var on: bool = key == tab or (key == "more" and in_more)
		var b := S.chip_button(String(t[1]), on, func():
			if Time.get_ticks_msec() < S.tap_block_until:
				return
			Sfx.play("click", -12.0)
			ui.open_phone(key))
		b.custom_minimum_size = Vector2(112, 46)
		b.add_theme_font_size_override("font_size", 17)
		h.add_child(b)
	return h


# ------------------------------------------------------------- alerts
## Grouped alerts: [{title, tone, count, items [{biz, text, tab}], icon}].
static func grouped(ui: EmpireUI) -> Array:
	var e := ui.game.empire
	var groups := {
		"stock": {"title": "%d shop%s low on stock", "tone": "warn", "items": [], "icon": "stock"},
		"staff": {"title": "%d shop%s short of staff", "tone": "warn", "items": [], "icon": "staff"},
		"loss": {"title": "%d shop%s losing money", "tone": "bad", "items": [], "icon": "bank"},
		"watch": {"title": "%d shop%s had a slow day", "tone": "muted", "items": [], "icon": "bank"},
		"clean": {"title": "%d shop%s need a clean", "tone": "warn", "items": [], "icon": "staff"},
	}
	for b: Business in e.businesses:
		for iss in ui.biz_issues(b):
			var text := String(iss[0])
			var tab := String(iss[2])
			var kind := ""
			if tab == "stock":
				kind = "stock"
			elif text.contains("cashier") or text.contains("off today"):
				kind = "staff"
			elif text.contains("Dirty"):
				kind = "clean"
			elif text.begins_with("Lost"):
				# Three losing days in a row is a problem; one is a fluctuation.
				var bad := 0
				for r in b.history.slice(maxi(b.history.size() - 3, 0)):
					if float(r.get("profit", 0.0)) < 0.0:
						bad += 1
				kind = "loss" if bad >= 3 or b.history.size() < 3 and bad >= 1 and float(b.last_day().get("profit", 0.0)) < -150.0 else "watch"
			if kind == "":
				continue
			var items: Array = groups[kind]["items"]
			if not items.any(func(x): return x["biz"] == b):
				items.append({"biz": b, "text": text, "tab": tab})
	var out: Array = []
	for k in ["loss", "stock", "staff", "clean", "watch"]:
		var g: Dictionary = groups[k]
		var n := (g["items"] as Array).size()
		if n == 0:
			continue
		g["count"] = n
		g["title"] = String(g["title"]) % [n, "" if n == 1 else "s"]
		g["kind"] = k
		out.append(g)
	if e.company_cash < 0.0:
		out.push_front({"title": "Company account overdrawn (%s)" % EmpireData.money(e.company_cash), "tone": "bad", "count": 1,
			"items": [], "icon": "bank", "kind": "overdrawn"})
	# Property and imports.
	for id in e.flags.get("estates", {}):
		var st: Dictionary = e.flags["estates"][id]
		if float(st["cond"]) < 0.55:
			out.append({"title": "%s needs maintenance" % Ventures.estate_def(id)["name"], "tone": "warn", "count": 1, "items": [],
				"icon": "property", "kind": "estate"})
	return out


static func open_group(ui: EmpireUI, g: Dictionary) -> void:
	match String(g.get("kind", "")):
		"overdrawn":
			ui.open_phone("bank")
			return
		"estate":
			ui.open_phone("property")
			return
	var v := ui._open(String(g["title"]), 760, 520)
	var hint: String = {"stock": "Buy a pack at the cash & carry or import through Skyport Cargo; a stacker fills the shelves.",
		"staff": "A cashier keeps a shop trading when you're not there.", "loss": "Losing three days running: check prices, stock and staff.",
		"watch": "One slow day is normal. Keep an eye on it.", "clean": "A cleaner keeps the floor tidy."}.get(String(g["kind"]), "")
	v.add_child(S.label(hint, 16, S.MUTED))
	var list := S.vbox(8)
	for it in g["items"]:
		var b: Business = it["biz"]
		var tab := String(it["tab"])
		list.add_child(ui._row([ui._fixed(b.name, 220, 18, S.PAPER, "bold"), ui._fixed(String(it["text"]), 330, 15, S.MUTED), S.spacer(),
			S.button({"stock": "Stock", "staff": "Staff", "reports": "Finances"}.get(tab, "Manage"), func(): ui.open_manage(b, tab), true, 120),
			S.button("GPS", func():
				ui.game.set_gps(_door(ui.game, b), b.name, {"kind": "unit", "id": String(b.premises.get("id", ""))})
				ui.close_panel(true), false, 80)]))
	v.add_child(ui._scroll(list, 380))
	v.add_child(S.button("Back", func(): ui.open_phone("home"), false, 120))


## A business's door in the world (its saved record has no geometry: the
## unit does). No business: the starter shop.
static func _door(g: EmpireGame, b: Business) -> Vector3:
	var u: Dictionary = g.unit_by_id.get(String(b.premises.get("id", "")), {}) if b else {}
	if u.is_empty():
		u = g.starter_unit()
	return Premises.door_point(u)


# --------------------------------------------------------------- home
## Card width so three fill the phone's content area.
static var card_w := 290.0


static func card(title: String, sub: String, pic: Control, cb: Callable, accent := S.AMBER) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(card_w, 206)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(18)
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.set_border_width_all(1)
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = Color(1, 1, 1, 0.09)
	hv.border_color = Color(accent, 0.6)
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	var v := S.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 10
	v.offset_bottom = -10
	b.add_child(v)
	var frame := PanelContainer.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.06, 0.09, 0.12)
	fsb.set_corner_radius_all(12)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(card_w - 20.0, 124)
	if pic:
		pic.custom_minimum_size = Vector2(card_w - 20.0, 124)
		frame.add_child(pic)
	v.add_child(frame)
	var t := S.label(title, 19, S.PAPER, "black")
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var s := S.label(sub, 14, S.MUTED)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.clip_text = true
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(s)
	b.pressed.connect(func():
		if Time.get_ticks_msec() < S.tap_block_until:
			return
		Sfx.play("click", -12.0)
		cb.call())
	return b


static func fit(ui: EmpireUI) -> void:
	var w := minf(1220.0, ui.get_viewport().get_visible_rect().size.x - 40.0) - 48.0 - 36.0
	card_w = floorf((w - 28.0) / 3.0)


static func home(ui: EmpireUI, v: VBoxContainer) -> void:
	fit(ui)
	var g := ui.game
	var e := g.empire
	# Alerts: one compact row of grouped chips.
	var al := grouped(ui)
	var ar := S.hbox(8)
	var ob := g.objective()
	if String(ob[0]) != "":
		ar.add_child(S.button("▸ " + String(ob[0]), ui.objective_action, true, 0))
	for a in al.slice(0, 4):
		var ad: Dictionary = a
		var chip := S.chip_button(String(ad["title"]), false, func(): open_group(ui, ad), EmpireUI.TONES[ad["tone"]])
		ar.add_child(chip)
	if al.is_empty() and String(ob[0]) == "":
		ar.add_child(S.label("All quiet: every shop is stocked, staffed and trading.", 16, S.MUTED))
	v.add_child(ar)
	# Picture cards.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	# Garage: your best vehicle.
	var best := {}
	for veh in e.vehicles:
		if veh.get("test", false):
			continue
		if best.is_empty() or float(EmpireData.vehicle_model(veh["model"]).get("price", 0)) > float(EmpireData.vehicle_model(best["model"]).get("price", 0)):
			best = veh
	var garage_pic: Control = ui.thumbs.vehicle(String(best["model"])) if not best.is_empty() else null
	grid.add_child(card("Garage", "%d vehicle%s · %s" % [e.vehicles.size(), "" if e.vehicles.size() == 1 else "s",
		String(EmpireData.vehicle_model(best.get("model", "")).get("name", "")) if not best.is_empty() else "none yet"], garage_pic, func(): ui.open_phone("vehicles")))
	# Businesses: your biggest earner on the map.
	var top: Business = null
	for b: Business in e.businesses:
		if top == null or float(b.last_day().get("profit", 0.0)) > float(top.last_day().get("profit", 0.0)):
			top = b
	grid.add_child(card("Businesses", "%d shop%s%s" % [e.businesses.size(), "" if e.businesses.size() == 1 else "s",
		(" · best " + top.name) if top else " · rent your first"], Thumbs.place(_door(g, top)), func(): ui.open_phone("businesses")))
	var es: Dictionary = e.flags.get("estates", {})
	grid.add_child(card("Property", ("%d building%s you own" % [es.size(), "" if es.size() == 1 else "s"]) if not es.is_empty() else "Flats, offices, a hotel – invest",
		Thumbs.place(SkyportIsland.w(Vector3(1700, 3, -220)), 260.0), func(): ui.open_phone("property")))
	# City500: where you stand.
	var yr := City500.your_rank(e)
	var rk := int(yr["rank"])
	var pic := VBoxContainer.new()
	pic.alignment = BoxContainer.ALIGNMENT_CENTER
	pic.custom_minimum_size = Vector2(card_w - 20, 120)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var big := S.label("#%d" % rk if rk > 0 else "—", 58, S.AMBER, "black")
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.add_child(big)
	var cap := S.label("CITY500 RANK" if rk > 0 else "%s TO ENTER" % City500.money(float(yr["gap_500"])).to_upper(), 13, S.MUTED, "black")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.add_child(cap)
	grid.add_child(card("City500", "Empire value %s" % City500.money(float(yr["value"])), pic, func(): ui.open_phone("city500"), S.AMBER))
	grid.add_child(card("Explore", "Shops, fashion, showrooms, Skyport – %d places" % ExploreUI.places(g).filter(func(p): return not p.get("vacant", false)).size(), Thumbs.place(SkyportIsland.w(Vector3(1720, 3, -40)), 300.0),
		func(): ui.open_phone("explore")))
	var spark := EmpireWidgets.Spark.new(e.day_reports.map(func(r): return float(r.get("profit", 0.0))).slice(maxi(e.day_reports.size() - 14, 0)), Vector2(270, 150))
	grid.add_child(card("Your empire", "Net worth %s" % EmpireData.money(e.net_worth()), spark, func(): ui.open_phone("bank"), S.GREEN))
	v.add_child(ui._scroll(grid, 430))


## Places you might want to go: one tap sets the route.
static func _explore(ui: EmpireUI) -> void:
	card_w = 280.0
	var g := ui.game
	var v := ui._open("Explore", 920, 560)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	for sid in ["dealer_budget", "dealer_commercial", "dealer_luxury", "clothes_everyday", "clothes_premium", "aviation", "marina", "cargo", "terminal"]:
		var st := g.skyport_play.site(sid)
		if st.is_empty():
			continue
		var door: Vector3 = st["door"]
		var nm := String(st["name"])
		var what := {"dealer_budget": "Used and everyday cars", "dealer_commercial": "Vans and trucks", "dealer_luxury": "Sports and supercars",
			"clothes_everyday": "Casual clothes", "clothes_premium": "Luxury fashion", "aviation": "Helicopters and planes",
			"marina": "Boats and yachts", "cargo": "Imports for your shops", "terminal": "The airport"}.get(sid, "") as String
		grid.add_child(card(nm, what, Thumbs.place(door, 120.0), func():
			g.set_gps(door, nm, {"kind": "place", "id": sid})
			ui.close_panel(true)
			ui.toast("Route set: %s" % nm, "info")))
	v.add_child(ui._scroll(grid, 450))


# -------------------------------------------------------------- garage
static func garage(ui: EmpireUI, v: VBoxContainer) -> void:
	fit(ui)
	var g := ui.game
	var e := g.empire
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var here := g.player.global_position
	for veh in e.vehicles:
		if veh.get("test", false):
			continue
		var vid := String(veh["id"])
		var md := EmpireData.vehicle_model(String(veh["model"]))
		var p := g.vehicle_position(vid)
		var cls := String(md.get("class", "car"))
		var inside := g.driving == vid or (g.skyport_play and g.skyport_play.piloting == vid)
		var sub := "You're in it" if inside else ("%s away · %d%% condition" % [ui._dist_text(here.distance_to(p)), int(float(veh["condition"]) * 100.0)])
		grid.add_child(card(String(md.get("name", "")), sub, ui.thumbs.vehicle(String(veh["model"])), func(): _vehicle_sheet(ui, vid),
			{"heli": S.BLUE, "plane": S.BLUE, "boat": S.BLUE}.get(cls, S.AMBER)))
	v.add_child(ui._scroll(grid, 430))
	var shops := S.hbox(10)
	shops.add_child(S.label("BUY MORE", 13, S.AMBER, "black"))
	for sid in ["dealer_budget", "dealer_commercial", "dealer_luxury", "aviation", "marina"]:
		var st := g.skyport_play.site(sid)
		if st.is_empty():
			continue
		var door: Vector3 = st["door"]
		var nm := String(st["name"])
		shops.add_child(S.button(nm, func():
			g.set_gps(door, nm, {"kind": "place", "id": sid})
			ui.close_panel(true)
			ui.toast("Route set: %s" % nm, "info"), false, 0))
	v.add_child(shops)


static func _vehicle_sheet(ui: EmpireUI, vid: String) -> void:
	var g := ui.game
	var veh := g.empire.vehicle(vid)
	var md := EmpireData.vehicle_model(String(veh["model"]))
	var cls := String(md.get("class", "car"))
	var v := ui._open(String(md.get("name", "")), 740, 440)
	var h := S.hbox(16)
	h.add_child(ui.thumbs.vehicle(String(veh["model"]), Vector2(300, 170)))
	var info := S.vbox(6)
	info.add_child(S.label(SkyportUI._specs(md), 16, S.PAPER, "bold"))
	info.add_child(S.label(SkyportUI._running(md), 14, S.MUTED))
	info.add_child(S.label("Condition %d%% · %d km" % [int(float(veh["condition"]) * 100.0), int(float(veh["km"]))], 15, S.MUTED))
	h.add_child(info)
	v.add_child(h)
	var acts := S.hbox(10)
	acts.add_child(S.button("Find · GPS", func(): ui.find_vehicle(vid), true, 160))
	if cls == "car":
		var q := g.delivery_quote(vid)
		var del := S.button("Deliver to me · %s" % EmpireData.money(float(q["fee"])) if q["ok"] else "Deliver to me", func():
			var err := g.deliver_vehicle(vid)
			ui.toast(err if err != "" else "A driver is bringing it round", "bad" if err != "" else "good")
			ui.close_panel(true), false, 230)
		del.disabled = not q["ok"]
		acts.add_child(del)
	acts.add_child(S.spacer())
	var worth := g.empire.vehicle_value(veh)
	var sell := S.button("Sell · %s" % EmpireData.money(worth), func():
		var err := g.sell_vehicle(vid)
		ui.toast(err if err != "" else "Sold the %s for %s" % [String(md.get("name", "")), EmpireData.money(worth)], "bad" if err != "" else "good")
		if err == "":
			ui.open_phone("vehicles"), false, 170)
	var why := g.empire.sell_vehicle_block(veh)
	if why == "" and (g.driving == vid or (g.skyport_play and g.skyport_play.piloting == vid)):
		why = "Get out first"
	sell.disabled = why != ""
	if why != "":
		sell.tooltip_text = why
	acts.add_child(sell)
	acts.add_child(S.button("Back", func(): ui.open_phone("vehicles"), false, 110))
	v.add_child(acts)
