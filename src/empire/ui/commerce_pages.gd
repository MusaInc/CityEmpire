class_name CommercePages
extends RefCounted
## Phone pages for the commercial empire (2026-11-27): Empire (your company,
## career stage, divisions, consolidated books), Supply chain (warehouse,
## fleet, contracts) and Ventures (nightclub, car hire, hotel facilities),
## plus the Growth tab in a business's manage panel (levels + the trade's
## own loop). Minimal text, big figures, one action per card.

const G = preload("res://src/empire/ui/glass.gd")


static func _card(v: VBoxContainer, pad := 20.0) -> VBoxContainer:
	var c := G.card(pad, 12, G.CARD)
	v.add_child(c[0])
	return c[1]


static func _act(ph: Phone, err: String, ok := "") -> void:
	if err != "":
		ph.ui.toast(err, "warn")
	elif ok != "":
		ph.ui.toast(ok, "good")
	ph.refresh()


## A thin progress bar.
class Bar extends Control:
	var f := 0.0
	var col := Color(0.2, 0.5, 1.0)
	func _init(p_f: float, p_col: Color, h := 8.0) -> void:
		f = clampf(p_f, 0.0, 1.0)
		col = p_col
		custom_minimum_size = Vector2(0, h)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := size.y * 0.5
		draw_rect(Rect2(Vector2.ZERO, size), G.FILL, true)
		if f > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(maxf(size.x * f, r * 2.0), size.y)), col, true)


## Your logo: the mark (LOGOS) in the brand colours with the initials.
class LogoMark extends Control:
	var kind := "monogram"
	var a := Color.BLACK
	var b := Color.WHITE
	var txt := ""
	func _init(p_kind: String, cols: Array, p_txt: String, px := 84.0) -> void:
		kind = p_kind
		a = cols[0]
		b = cols[1]
		txt = p_txt
		custom_minimum_size = Vector2(px, px)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := Vector2(s, s) * 0.5
		match kind:
			"circle":
				draw_circle(c, s * 0.5, a)
				draw_arc(c, s * 0.42, 0, TAU, 48, b, s * 0.04, true)
			"diamond":
				draw_colored_polygon(PackedVector2Array([Vector2(c.x, 0), Vector2(s, c.y), Vector2(c.x, s), Vector2(0, c.y)]), a)
			"bars":
				draw_rect(Rect2(0, 0, s, s), a)
				for i in 3:
					draw_rect(Rect2(s * 0.12, s * (0.14 + i * 0.08), s * 0.76, s * 0.035), b)
			"arch":
				draw_rect(Rect2(0, s * 0.35, s, s * 0.65), a)
				draw_circle(Vector2(c.x, s * 0.42), s * 0.5, a)
			"star":
				var pts := PackedVector2Array()
				for i in 10:
					var r := s * (0.5 if i % 2 == 0 else 0.26)
					var an := -PI * 0.5 + i * PI / 5.0
					pts.append(c + Vector2(cos(an), sin(an)) * r)
				draw_colored_polygon(pts, a)
			_:
				draw_style_box(G.box(a, int(s * 0.24), 0), Rect2(0, 0, s, s))
		var f := G.font("bold", true)
		var fs := int(s * (0.36 if txt.length() > 1 else 0.48))
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(c.x - w * 0.5, c.y + fs * 0.36 + (s * 0.08 if kind == "bars" else 0.0)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, b)


## Daily profit as bars (positive up, negative down).
class Chart extends Control:
	var vals: Array = []
	func _init(p_vals: Array, h := 120.0) -> void:
		vals = p_vals
		custom_minimum_size = Vector2(0, h)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if vals.is_empty():
			return
		var hi := 1.0
		for x in vals:
			hi = maxf(hi, absf(float(x)))
		var mid := size.y * 0.7
		var w := size.x / vals.size()
		draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(G.SEP, 1.0), 1.0)
		for i in vals.size():
			var x := float(vals[i])
			var hgt := (mid - 6.0) * x / hi if x >= 0.0 else (size.y - mid - 4.0) * x / hi
			var r := Rect2(i * w + w * 0.18, mid - maxf(hgt, 0.0), w * 0.64, absf(hgt))
			draw_rect(r, G.GREEN if x >= 0.0 else G.RED, true)


# ------------------------------------------------------------------ Empire
static func empire(ph: Phone, body: VBoxContainer) -> void:
	var e := ph.game.empire
	var v := PhonePages.scroller(body, 18)
	# Company
	var cc := _card(v, 22)
	var top := G.hbox(18)
	top.add_child(LogoMark.new(Company.logo(e), Company.colours(e), Company.initials(e), 84))
	var tv := G.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(G.text(Company.name_of(e), "title1"))
	tv.add_child(G.text("%d businesses · %d industries · %d islands" % [e.businesses.size(), Company.industries(e), Company.islands(e)], "subhead", G.LABEL2))
	top.add_child(tv)
	cc.add_child(top)
	if Company.has_brand(e):
		var lh := G.hbox(8)
		for id in Company.LOGOS:
			lh.add_child(G.pill(String(id).capitalize(), Company.logo(e) == id, func():
				Company.set_logo(e, id)
				ph.refresh()))
		var sc := ScrollContainer.new()
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size.y = 48
		sc.add_child(lh)
		cc.add_child(sc)
	else:
		cc.add_child(G.para("Name your company in Corporate: your sign goes on every shopfront, van and tower you own.", "footnote"))
	var figs := _figs()
	var rev := 0.0
	var prof := 0.0
	var series: Array = []
	for r: Dictionary in e.day_reports.slice(maxi(e.day_reports.size() - 7, 0)):
		rev += float(r.get("revenue", 0.0))
		prof += float(r.get("profit", 0.0))
	for r: Dictionary in e.day_reports.slice(maxi(e.day_reports.size() - 21, 0)):
		series.append(float(r.get("profit", 0.0)))
	figs.add_child(G.figure("Net worth", EmpireData.money(e.net_worth()), null, "title2"))
	figs.add_child(G.figure("Sales · 7 days", EmpireData.money(rev), null, "title2"))
	figs.add_child(G.figure("Profit · 7 days", EmpireData.money(prof), G.GREEN if prof >= 0.0 else G.RED, "title2"))
	cc.add_child(figs)
	if series.size() >= 2:
		cc.add_child(Chart.new(series, 110))
	# Career stage
	var stc := _card(v, 22)
	var st := Progression.current(e)
	var head := G.hbox(10)
	head.add_child(G.text(String(st.get("name", "")), "title2"))
	head.add_child(G.spacer())
	head.add_child(G.text("Stage %d of %d" % [Progression.index(e) + 1, Progression.stages().size()], "footnote", G.LABEL2))
	stc.add_child(head)
	stc.add_child(G.para(String(st.get("goal", "")), "subhead"))
	stc.add_child(Bar.new(Progression.progress(e), G.BLUE, 8))
	var rows: Array = []
	for s: Dictionary in Progression.steps(e):
		var n := float(s["n"])
		var have := float(s["have"])
		var val := "Done" if s["done"] else (EmpireData.money(have) + " / " + EmpireData.money(n) if n >= 1000.0 else "%d / %d" % [int(have), int(n)])
		rows.append(G.row(String(s["t"]), "", val, "goals" if s["done"] else "clock", G.GREEN if s["done"] else G.LABEL3, null, G.GREEN if s["done"] else null))
	stc.add_child(G.group(rows))
	# Divisions
	var divs := Company.divisions(e)
	if not divs.is_empty():
		var drows: Array = []
		for d: Dictionary in divs:
			var sub := "%s · %d %s" % [String(d["trade"]), int(d["branches"]), "branch" if int(d["branches"]) == 1 else "branches"]
			if int(d.get("top_level", 0)) > 0:
				sub += " · up to %s" % Growth.level_name(int(d["top_level"]))
			drows.append(G.row(String(d["name"]), sub, EmpireData.money(float(d["profit"])), "businesses", G.ORANGE, null,
				G.GREEN if float(d["profit"]) >= 0.0 else G.RED))
		v.add_child(G.group(drows, "Divisions", "Profit over the last 7 days."))
	# Businesses and their levels
	if not e.businesses.is_empty():
		var brows: Array = []
		for b: Business in e.businesses:
			var bb := b
			brows.append(G.row(b.name, "%s · %s" % [Growth.level_name(b.level), b.district().get("name", "")],
				"Ready to grow" if Growth.block(e, b) == "" and b.level < Growth.MAX_LEVEL else "", "chart", G.BLUE, func():
					ph.ui.open_manage(bb, "growth"), G.GREEN))
		v.add_child(G.group(brows, "Growth", "Each business grows from an independent to the chain's flagship."))


# ------------------------------------------------------------ Supply chain
## Corporate (2026-11-27, native): your brand, the head office in Meridian
## Tower and marketing campaigns – stacked cards that fit a phone.
static func corporate(ph: Phone, body: VBoxContainer) -> void:
	var ui := ph.ui
	var g := ph.game
	var e := g.empire
	var v := PhonePages.scroller(body, 18)
	# Brand
	var bc := _card(v, 20)
	bc.add_child(G.text("Your brand", "title3"))
	var pv := EmpireWidgets.BrandPreview.new()
	pv.ident = ShopStyle.house_ident(e.brand if not e.brand.is_empty() else ShopStyle.default_house(""))
	pv.custom_minimum_size = Vector2(0, 150)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bc.add_child(pv)
	if e.brand.is_empty():
		bc.add_child(G.para("Your shops each wear their own sign. Create a brand and every one trades under your name.", "footnote"))
		bc.add_child(G.button("Create your brand", func(): ui.open_brand(), "filled", "large"))
	else:
		var hb := G.hbox(10)
		hb.add_child(G.text("%d shop%s wear it" % [e.businesses.size(), "" if e.businesses.size() == 1 else "s"], "subhead", G.LABEL2))
		hb.add_child(G.spacer())
		hb.add_child(G.button("Edit brand", func(): ui.open_brand(), "gray", "small"))
		bc.add_child(hb)
	# Head office
	var hc := _card(v, 20)
	hc.add_child(G.text("Head office · Meridian Tower", "footnote", G.ACCENT_TEXT, "semibold"))
	var tier := e.hq_tier()
	if tier > 0:
		var d := e.hq_def(tier)
		hc.add_child(G.text(String(d["name"]), "title2"))
		var pl := ui._perks(d)
		hc.add_child(G.para(pl.text, "footnote"))
		pl.free()
		hc.add_child(G.text("Upkeep %s a day" % EmpireData.money(float(d["upkeep"])), "footnote", G.LABEL2))
	else:
		hc.add_child(G.text("No head office yet", "title2"))
		hc.add_child(G.para("Lease a floor of the city's tallest tower: bulk buying for every shop, and a marketing desk.", "footnote"))
	var nd := e.hq_def(tier + 1)
	if not nd.is_empty():
		hc.add_child(G.text("Next: %s · %s" % [nd["name"], EmpireData.money(float(nd["price"]))], "subhead", G.ACCENT_TEXT, "semibold"))
		hc.add_child(Bar.new(float(e.businesses.size()) / maxf(float(nd["shops"]), 1.0), G.ACCENT))
		var why := e.hq_block(tier + 1)
		hc.add_child(G.text("%d of %d shops%s" % [mini(e.businesses.size(), int(nd["shops"])), int(nd["shops"]), " · " + why if why != "" else ""], "footnote", G.LABEL2))
	hc.add_child(G.button("GPS to the tower", func():
		var u := g.hq_unit()
		if not u.is_empty():
			g.set_gps(Premises.door_point(u), "Meridian Tower")
		ui.close_panel(true), "filled" if tier == 0 else "gray", "regular", null, "goals"))
	# Marketing
	var run := e.campaign_running()
	var rows: Array = []
	for c in EmpireData.hq().get("campaigns", []):
		var cd: Dictionary = c
		var why2 := e.campaign_block(cd["id"])
		var live: bool = run.get("id", "") == cd["id"]
		var sub := "+%d%% shoppers · %d days" % [roundi(float(cd["footfall"]) * 100.0), int(cd["days"])] + (" · ★+%d" % int(cd["rep"]) if int(cd["rep"]) > 0 else "")
		if live:
			var left := int(run["until"]) - e.day + 1
			rows.append(G.row(String(cd["name"]), "Running · %d day%s left" % [left, "" if left == 1 else "s"], "", "megaphone", G.GREEN))
		else:
			var can := why2 == "" or why2.begins_with("Costs")
			rows.append(G.row(String(cd["name"]), sub, EmpireData.money(float(cd["cost"])), "megaphone", G.ORANGE if can else G.LABEL3,
				func():
					if not can:
						ui.toast(why2, "warn")
						return
					var err := e.run_campaign(cd["id"])
					if err == "":
						Sfx.play("chime", -6.0)
					_act(ph, err, "%s is running" % cd["name"])))
	if not rows.is_empty():
		v.add_child(G.group(rows, "Marketing", "Campaigns are run from your head office." if tier == 0 else ""))
	v.add_child(G.gap(4))


static func supply(ph: Phone, body: VBoxContainer) -> void:
	var e := ph.game.empire
	var v := PhonePages.scroller(body, 18)
	if not SupplyChain.has_warehouse(e):
		var hc := _card(v, 22)
		hc.add_child(G.text("Your own warehouse", "title1"))
		hc.add_child(G.para("Buy in bulk at contract prices, store it in your own warehouse and let your vans keep every branch stocked twice a day – no more cash & carry runs or delivery fees.", "subhead"))
		for s: Dictionary in SupplyChain.sites():
			var c := _card(v, 20)
			c.add_child(G.text(String(s["name"]), "title3"))
			c.add_child(G.para("%s · %d cases%s" % [String(s.get("blurb", "")), int(s["cases"]),
				" · %s a day" % EmpireData.money(float(s["upkeep"])) if float(s.get("upkeep", 0)) > 0 else ""], "footnote"))
			var why := SupplyChain.site_block(e, String(s["id"]))
			var id := String(s["id"])
			var btn := G.button("Buy · %s" % EmpireData.money(float(s["price"])) if float(s["price"]) > 0 else "Open the depot", func():
				_act(ph, SupplyChain.buy_site(e, id), "Warehouse open"), "filled", "regular")
			btn.disabled = why != ""
			c.add_child(btn)
			if why != "":
				c.add_child(G.para(why, "footnote", G.LABEL2))
		return
	# Warehouse
	var s := SupplyChain.site(e)
	var wc := _card(v, 22)
	wc.add_child(G.text(String(s["name"]), "title1"))
	var held := SupplyChain.cases_held(e)
	var cap := SupplyChain.capacity(e)
	var figs := _figs()
	figs.add_child(G.figure("Cases held", "%d / %d" % [held, cap], null, "title2"))
	figs.add_child(G.figure("Stock value", EmpireData.money(_stock_value(e, SupplyChain.stock(e))), null, "title2"))
	figs.add_child(G.figure("Contracts done", str(int(e.stats.get("contracts_done", 0))), null, "title2"))
	wc.add_child(figs)
	wc.add_child(Bar.new(float(held) / maxf(float(cap), 1.0), G.BLUE, 8))
	var plan := SupplyChain.suggested_order(e)
	var n := 0
	var cost := 0.0
	for pid in plan:
		n += int(plan[pid])
		cost += SupplyChain.case_cost(e, pid) * int(plan[pid])
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 10)
	acts.add_theme_constant_override("v_separation", 10)
	var fill := G.button("Stock my branches · %d cases · %s" % [n, EmpireData.money(cost)] if n > 0 else "Your branches are covered", func():
		_act(ph, SupplyChain.stock_up(e, plan), "Delivered to the warehouse"), "filled", "regular", null, "truck")
	fill.disabled = n == 0
	acts.add_child(fill)
	var rk: Dictionary = SupplyChain.cfg().get("racking", {})
	if int(SupplyChain.state(e).get("racks", 0)) < int(rk.get("max", 3)):
		acts.add_child(G.button("More racking · %s" % EmpireData.money(float(rk.get("cost", 0))), func():
			_act(ph, SupplyChain.add_racking(e), "+%d cases of racking" % int(rk.get("cases", 0))), "gray", "regular"))
	wc.add_child(acts)
	wc.add_child(G.para("Contract prices: %d%% under the cash & carry." % roundi((1.0 - SupplyChain.case_cost(e, "cola") / maxf(e.case_price("cola"), 0.01)) * 100.0), "footnote"))
	# Fleet
	var frows: Array = []
	var road := SupplyChain.on_the_road(e)
	for veh: Dictionary in e.vehicles:
		if not SupplyChain.fleet_model(veh):
			continue
		var vid := String(veh["id"])
		var nm := String(EmpireData.vehicle_model(String(veh["model"])).get("name", "Van"))
		var on := SupplyChain.on_fleet(e, vid)
		var sub := "In your garage · %d cases" % SupplyChain.capacity_of(veh)
		if on:
			var fl: Dictionary = SupplyChain.fleet(e)[vid]
			sub = "%s · %d rounds · %d cases delivered · %d%% condition" % [fl["driver"], int(fl["runs"]), int(fl["cases"]), roundi(float(veh["condition"]) * 100)]
			for r: Dictionary in road:
				if String(r["vid"]) == vid:
					var bz := e.business(String(r["biz"]))
					sub = "On the road → %s, %s · %s" % [bz.name if bz else "a branch", _clock(float(r["eta"])), fl["driver"]]
		frows.append(G.row(nm, sub, "On the rounds" if on else "Add", "truck", G.GREEN if on else G.LABEL3, func():
			if ph.game.driving == vid:
				ph.ui.toast("Park it and get out first", "warn")
				return
			var err := SupplyChain.toggle_fleet(e, vid)
			ph.game.sync_away_cars()
			_act(ph, err), G.GREEN if on else G.BLUE))
	if frows.is_empty():
		frows.append(G.row("No vans yet", "Buy a Courier Van or Box Truck from the Marketplace", "", "truck", G.LABEL3))
	var runs: Array = SupplyChain.cfg().get("fleet", {}).get("runs", [6, 13])
	v.add_child(G.group(frows, "Delivery fleet", "Rounds leave at %s. A driver is hired from today's job seekers." % ", ".join(runs.map(func(h): return _clock(float(h) * 60.0)))))
	# Contracts
	var crows: Array = []
	for c: Dictionary in SupplyChain.contracts(e):
		var pn := String(EmpireData.product(String(c["pid"])).get("name", c["pid"]))
		crows.append(G.row(String(c["client"]), "%d cases of %s a day · %d days left%s" % [int(c["cases"]), pn, int(c["left"]),
			" · %d short" % int(c["short"]) if int(c["short"]) > 0 else ""], EmpireData.money(float(c["price"]) * int(c["cases"])) + "/day", "desk", G.BLUE))
	for o: Dictionary in SupplyChain.offers(e):
		var pn := String(EmpireData.product(String(o["pid"])).get("name", o["pid"]))
		var oid := String(o["id"])
		var margin := float(o["price"]) / maxf(e.case_price(String(o["pid"])), 0.01) - 1.0
		crows.append(G.row("Offer: %s" % o["client"], "%d cases of %s a day for %d days · +%d%% over cost" % [int(o["cases"]), pn, int(o["days"]), roundi(margin * 100)],
			"Sign", "desk", G.ORANGE, func(): _act(ph, SupplyChain.accept(e, oid), "Contract signed"), G.BLUE))
	if crows.is_empty():
		crows.append(G.row("No offers today", "City firms ask for supply every couple of days", "", "desk", G.LABEL3))
	v.add_child(G.group(crows, "Wholesale contracts", "Shipped from the warehouse each night; a short day costs half its value."))


## A row of figures that wraps on a narrow phone instead of widening the card.
static func _figs() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 28)
	f.add_theme_constant_override("v_separation", 10)
	return f


static func _stock_value(e: Empire, s: Stock) -> float:
	var t := 0.0
	for pid in s.units:
		t += e.unit_cost(String(pid)) * int(s.units[pid])
	return t


static func _clock(m: float) -> String:
	var mm := int(m) % 1440
	return "%02d:%02d" % [mm / 60, mm % 60]


# ---------------------------------------------------------------- Ventures
static func ventures(ph: Phone, body: VBoxContainer) -> void:
	var e := ph.game.empire
	var v := PhonePages.scroller(body, 18)
	_club_card(ph, e, v)
	_rental_card(ph, e, v)
	_hotel_card(ph, e, v)


static func _club_card(ph: Phone, e: Empire, v: VBoxContainer) -> void:
	var c := _card(v, 22)
	if not Trades.owns_club(e):
		c.add_child(G.text("Nightlife", "title1"))
		c.add_child(G.para("Run a club Thursday to Sunday: book the nights, set the door price, fill the VIP tables.", "subhead"))
		for s: Dictionary in Trades.club_cfg().get("sites", []):
			var id := String(s["id"])
			var row := G.hbox(10)
			row.add_child(G.para("%s · %s · %d capacity" % [s["name"], EmpireData.district(String(s["district"])).get("name", ""), int(s["capacity"])], "body"))
			row.add_child(G.button("Buy · %s" % EmpireData.money(float(s["price"])), func(): _act(ph, Trades.buy_club(e, id), "The club is yours"), "filled", "small"))
			c.add_child(row)
		return
	var cl := Trades.club(e)
	var s := Trades.club_site(String(cl["site"]))
	c.add_child(G.text(String(s["name"]), "title1"))
	var f := Trades.club_forecast(e)
	var wd := e.weekday()
	if not f["open"]:
		for d in ["Thu", "Fri", "Sat", "Sun"]:
			f = Trades.club_forecast(e, d)
			wd = d
			if f["open"]:
				break
	var figs := _figs()
	figs.add_child(G.figure("Popularity", "%d" % roundi(float(cl.get("pop", 50))), null, "title2"))
	figs.add_child(G.figure("%s crowd" % wd, "%d / %d" % [int(f["crowd"]), int(f["capacity"])], null, "title2"))
	figs.add_child(G.figure("VIP tables", str(int(f["vips"])), null, "title2"))
	figs.add_child(G.figure("Night's profit", EmpireData.money(float(f["takings"]) - float(f["cost"])), G.GREEN if float(f["takings"]) >= float(f["cost"]) else G.RED, "title2"))
	c.add_child(figs)
	var evs: Array = []
	for ev: Dictionary in Trades.club_cfg().get("events", []):
		evs.append([ev["id"], "%s · %s" % [ev["name"], EmpireData.money(float(ev["cost"]))]])
	c.add_child(G.text("Tonight's event", "headline"))
	c.add_child(G.pills(evs, String(cl.get("event", "house")), func(k):
		Trades.set_club(e, "event", k)
		ph.refresh()))
	var entry: Array = Trades.club_cfg().get("entry", [6, 12, 20])
	c.add_child(G.text("Door price", "headline"))
	c.add_child(G.segmented([["0", "£%d" % int(entry[0])], ["1", "£%d" % int(entry[1])], ["2", "£%d" % int(entry[2])]], str(int(cl.get("entry", 1))),
		func(k):
			Trades.set_club(e, "entry", int(k))
			ph.refresh()))


static func _rental_card(ph: Phone, e: Empire, v: VBoxContainer) -> void:
	var c := _card(v, 22)
	var dk: Dictionary = Trades.rental_cfg().get("desk", {})
	if not Trades.owns_rental(e):
		c.add_child(G.text("Car hire", "title1"))
		c.add_child(G.para("A desk in the Skyport terminal: put cars from your garage on hire. Book by class, price and condition – and keep them serviced.", "subhead"))
		c.add_child(G.button("Open the desk · %s" % EmpireData.money(float(dk.get("price", 0))), func(): _act(ph, Trades.buy_rental(e), "Car hire open"), "filled", "regular"))
		return
	var r := Trades.rental(e)
	c.add_child(G.text(String(dk.get("name", "Car hire")), "title1"))
	var last: Dictionary = (r.get("days", []) as Array).back() if not (r.get("days", []) as Array).is_empty() else {}
	var figs := _figs()
	figs.add_child(G.figure("On hire", str(r.get("cars", {}).size()), null, "title2"))
	figs.add_child(G.figure("Booked yesterday", str(int(last.get("booked", 0))), null, "title2"))
	figs.add_child(G.figure("Takings", EmpireData.money(float(r.get("takings", 0.0))), null, "title2"))
	c.add_child(figs)
	c.add_child(G.text("Rates", "headline"))
	c.add_child(G.segmented([["0.85", "Value"], ["1.0", "Standard"], ["1.25", "Premium"]], _rate_key(float(r.get("price_k", 1.0))),
		func(k):
			r["price_k"] = float(k)
			ph.refresh()))
	var rows: Array = []
	for veh: Dictionary in e.vehicles:
		var vid := String(veh["id"])
		var on := Trades.on_hire(e, vid)
		if not on and not Trades.rentable(veh):
			continue
		var nm := String(EmpireData.vehicle_model(String(veh["model"])).get("name", "Car"))
		rows.append(G.row(nm, "%s · %s a day · %d%% condition · %d%% booked" % [Trades.rental_class(veh).capitalize(), EmpireData.money(Trades.day_rate(veh, float(r.get("price_k", 1.0)))),
			roundi(float(veh["condition"]) * 100), roundi(Trades.hire_chance(e, veh) * 100)], "On hire" if on else "Add", "vehicles", G.GREEN if on else G.LABEL3,
			func():
				if ph.game.driving == vid:
					ph.ui.toast("Park it and get out first", "warn")
					return
				Trades.toggle_hire(e, vid)
				ph.game.sync_away_cars()
				ph.refresh(), G.GREEN if on else G.BLUE))
	if rows.is_empty():
		rows.append(G.row("No cars to hire out", "Buy cars in the Marketplace", "", "vehicles", G.LABEL3))
	v.add_child(G.group(rows, "Hire fleet", "Cars on hire stay at the terminal. Service them in the Garage when they're tired."))


static func _rate_key(k: float) -> String:
	if k < 0.95:
		return "0.85"
	if k > 1.1:
		return "1.25"
	return "1.0"


static func _hotel_card(ph: Phone, e: Empire, v: VBoxContainer) -> void:
	if not Ventures.owns_estate(e, "skyport_hotel"):
		return
	var st: Dictionary = e.flags.get("estates", {}).get("skyport_hotel", {})
	var rows: Array = []
	for f: Dictionary in Trades.hotel_facilities():
		var fid := String(f["id"])
		var have := Trades.has_facility(st, fid)
		rows.append(G.row(String(f["name"]), "+%d%% guests · +%d%% room rate · %s a day" % [roundi(float(f["occ"]) * 100), roundi(float(f["rate"]) * 100), EmpireData.money(float(f["upkeep"]))],
			"Open" if have else EmpireData.money(float(f["cost"])), "property", G.GREEN if have else G.PURPLE,
			null if have else func(): _act(ph, Trades.build_facility(e, "skyport_hotel", fid), "Opened"), G.GREEN if have else G.BLUE))
	v.add_child(G.group(rows, "Skyport Hotel · %d%% occupied" % roundi(float(st.get("occ", 0.0)) * 100), "Facilities fill rooms and lift the nightly rate."))


# ------------------------------------------------------- Growth (manage tab)
static func growth_tab(ui: EmpireUI, v: VBoxContainer, b: Business) -> void:
	var e := ui.game.empire
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = 470
	var w := G.vbox(16)
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(w)
	v.add_child(sc)
	# The ladder
	var lad := G.hbox(10)
	for n in range(1, Growth.MAX_LEVEL + 1):
		var on := n == b.level
		var c := G.card(16, 4, Color(G.BLUE, 0.16) if on else (G.CARD if n > b.level else Color(G.GREEN, 0.10)))
		c[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(c[1] as VBoxContainer).add_child(G.text("Level %d" % n, "footnote", G.LABEL2, "semibold"))
		(c[1] as VBoxContainer).add_child(G.text(Growth.level_name(n), "headline"))
		lad.add_child(c[0])
	w.add_child(lad)
	var cur := Growth.level_def(b.level)
	w.add_child(G.para(String(cur.get("blurb", "")), "subhead"))
	if b.level < Growth.MAX_LEVEL:
		var nx := Growth.level_def(b.level + 1)
		var nc := G.card(20, 10, G.CARD)
		w.add_child(nc[0])
		var box: VBoxContainer = nc[1]
		box.add_child(G.text("Next: %s" % nx["name"], "title3"))
		box.add_child(G.para(String(nx.get("blurb", "")), "footnote"))
		var rows: Array = []
		for r: Dictionary in Growth.needs(e, b):
			rows.append(G.row(String(r["text"]), "", "Done" if r["done"] else String(r["have"]), "goals" if r["done"] else "clock", G.GREEN if r["done"] else G.LABEL3, null, G.GREEN if r["done"] else null))
		box.add_child(G.group(rows))
		var why := Growth.block(e, b)
		var gb := G.button("Grow to %s · %s" % [nx["name"], EmpireData.money(Growth.cost(b, b.level + 1))], func():
			var err := Growth.grow(e, b)
			ui.toast(err if err != "" else "%s is now a %s" % [b.name, Growth.level_name(b.level)], "warn" if err != "" else "good")
			if err == "":
				ui.game.refresh_business_world(b)
			ui.open_manage(b, "growth"), "filled", "large")
		gb.disabled = why != ""
		box.add_child(gb)
	# The trade's own loop
	match Trades.kind(b):
		"food":
			var fc := G.card(20, 10, G.CARD)
			w.add_child(fc[0])
			var fb: VBoxContainer = fc[1]
			fb.add_child(G.text("Kitchen", "title3"))
			fb.add_child(G.para("The supplier sets what the food costs and how good it is – your reputation follows the food.", "footnote"))
			var sups: Array = []
			for s: Dictionary in Trades.suppliers():
				sups.append([s["id"], "%s · %+d%%" % [s["name"], roundi((float(s["cost_k"]) - 1.0) * 100)]])
			fb.add_child(G.pills(sups, String(Trades.supplier(b).get("id", "standard")), func(k):
				Trades.set_supplier(e, b, k)
				ui.open_manage(b, "growth")))
			fb.add_child(G.text("Menu", "headline"))
			fb.add_child(G.segmented([["tight", "Tight · better"], ["classic", "Classic"], ["wide", "Wide · busier"]], String(b.trade.get("menu", "classic")), func(k):
				Trades.set_menu(e, b, k)
				ui.open_manage(b, "growth")))
		"clothing":
			var cc := G.card(20, 10, G.CARD)
			w.add_child(cc[0])
			var cb: VBoxContainer = cc[1]
			cb.add_child(G.text("Collections", "title3"))
			var curc := Trades.collection_def(String(b.trade.get("collection", "basics")))
			cb.add_child(G.para("In store: %s · %d%% fresh. Collections fade over two weeks and only sell where they suit the street." % [curc.get("name", ""), roundi(Trades.freshness(e, b) * 100) if b.trade.has("launched") else 60], "footnote"))
			var rows: Array = []
			for c: Dictionary in Trades.collections():
				var cid := String(c["id"])
				var fitp := roundi(Trades.fit(b, c) * 100)
				var why := Trades.launch_block(e, b, cid)
				rows.append(G.row(String(c["name"]), "Suits this district %d%%%s" % [fitp, " · sells best when sunny" if c.has("weather") else ""],
					"In store" if why == "Already in store" else ("Launch · %s" % EmpireData.money(float(c["launch"])) if float(c["launch"]) > 0 else "Launch"),
					"tag", G.GREEN if fitp >= 90 else (G.ORANGE if fitp >= 50 else G.RED),
					null if why != "" else func():
						var err := Trades.launch(e, b, cid)
						ui.toast(err if err != "" else "%s launched" % c["name"], "warn" if err != "" else "good")
						ui.open_manage(b, "growth"), G.BLUE))
			cb.add_child(G.group(rows))
