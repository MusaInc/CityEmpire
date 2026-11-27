class_name PhonePages
extends RefCounted
## The phone's sections, drawn in the Glass language (2026-11-20):
##   home      Wallet/Stocks: the empire card, net-worth chart, what needs
##             you, quick actions, your businesses, recent activity
##   map       full-bleed map, floating search and place cards
##   market    one shop for everything you can buy: businesses, homes,
##             vehicles, fashion, investments
##   city500   Stocks-style rankings; a company's chart and profile
##   vehicles  Garage: a showroom of what you own
##   property  photo listings; a listing's gallery and the deal
##   you       Character: your look, wardrobe and where to shop
##   more      every other section (compact)
## Older sections (Businesses, Finances, Corporate, City, Goals, Game,
## Explore) keep their content, restyled, via EmpireUI.legacy_tab.
## Wide screens split lists from details (an inspector); narrow ones push
## the detail as a page (back returns to the list, scrolled where it was).

const G = preload("res://src/empire/ui/glass.gd")


static func build(ph: Phone, sec: String, page: String, args: Dictionary, body: VBoxContainer) -> void:
	match sec:
		"overview", "home":
			overview_hub(ph, body)
		"businesses":
			if page == "company":
				company(ph, body, int(args.get("idx", 0)))
			else:
				businesses_hub(ph, body)
		"assets":
			if page == "vehicle":
				vehicle_offer(ph, body, String(args.get("model", "")), String(args.get("site", "")))
			elif page == "listing":
				listing(ph, body, args)
			else:
				assets_hub(ph, body)
		"map":
			map_hub(ph, body)
		"profile":
			profile_hub(ph, body)
		"market":
			if page == "vehicle":
				vehicle_offer(ph, body, String(args.get("model", "")), String(args.get("site", "")))
			elif page == "listing":
				listing(ph, body, args)
			else:
				market(ph, body)
		"city500":
			if page == "company":
				company(ph, body, int(args.get("idx", 0)))
			else:
				city500(ph, body)
		"vehicles":
			garage(ph, body)
		"property":
			if page == "listing":
				listing(ph, body, args)
			else:
				property(ph, body)
		"you":
			character(ph, body)
		"more":
			more(ph, body)
		_:
			var v := G.vbox(14)
			v.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.add_child(v)
			ph.ui.legacy_tab(sec, v, Phone.st(sec).get("focus", {}))
			Phone.st(sec).erase("focus")


static func _sub_bar(ph: Phone, sec: String, items: Array, default_key: String, body: VBoxContainer) -> String:
	var st := Phone.st(sec)
	var cur := String(st.get("sub", default_key))
	var valid := false
	for it in items:
		if String(it[0]) == cur:
			valid = true
			break
	if not valid:
		cur = default_key
		st["sub"] = cur
	body.add_child(G.segmented(items, cur, func(k: String):
		Phone.st(sec)["sub"] = k
		ph.refresh()))
	return cur


static func overview_hub(ph: Phone, body: VBoxContainer) -> void:
	var sub := _sub_bar(ph, "overview", [["summary", "Summary"], ["jobs", "Jobs"], ["finances", "Finances"], ["city", "City"], ["goals", "Goals"]], "summary", body)
	match sub:
		"jobs":
			CareerPages.jobs(ph, body)
		"finances":
			var v := G.vbox(12)
			v.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.add_child(v)
			ph.ui.legacy_tab("bank", v)
		"city":
			var v := G.vbox(12)
			v.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.add_child(v)
			ph.ui.legacy_tab("city", v)
		"goals":
			var v := G.vbox(12)
			v.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.add_child(v)
			ph.ui.legacy_tab("goals", v)
		_:
			home(ph, body)


static func businesses_hub(ph: Phone, body: VBoxContainer) -> void:
	var sub := _sub_bar(ph, "businesses", [["shops", "My Businesses"], ["ops", "Operations"], ["reports", "Reports"], ["corporate", "Corporate"], ["city500", "City500"]], "shops", body)
	match sub:
		"ops":
			CareerPages.operations(ph, body)
		"reports":
			CareerPages.reports(ph, body)
		"corporate":
			var v := G.vbox(12)
			v.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.add_child(v)
			ph.ui.legacy_tab("company", v)
		"city500":
			city500(ph, body)
		_:
			var v := G.vbox(12)
			v.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.add_child(v)
			ph.ui.legacy_tab("businesses", v)


static func assets_hub(ph: Phone, body: VBoxContainer) -> void:
	var sub := _sub_bar(ph, "assets", [["property", "Properties"], ["garage", "Garage"], ["market", "Marketplace"]], "property", body)
	match sub:
		"garage":
			garage(ph, body)
		"market":
			market(ph, body)
		_:
			property(ph, body)


static func map_hub(ph: Phone, body: VBoxContainer) -> void:
	var sub := _sub_bar(ph, "map", [["city_map", "City Map"], ["explore", "Nearby"]], "city_map", body)
	if sub == "explore":
		var v := G.vbox(12)
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(v)
		ph.ui.legacy_tab("explore", v)
	else:
		map(ph, body)


static func profile_hub(ph: Phone, body: VBoxContainer) -> void:
	var sub := _sub_bar(ph, "profile", [["character", "Character"], ["game", "Settings"]], "character", body)
	if sub == "game":
		var v := G.vbox(12)
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(v)
		ph.ui.legacy_tab("game", v)
	else:
		character(ph, body)


# ------------------------------------------------------------- helpers
## The page's one vertical scroller (drag anywhere, momentum).
static func scroller(body: VBoxContainer, sep := 22) -> VBoxContainer:
	var sc := TouchScroll.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var v := G.vbox(sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


## A sideways strip of cards.
static func carousel(sep := 16, h := 0.0) -> Array:
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if h > 0.0:
		sc.custom_minimum_size.y = h
	var row := G.hbox(sep)
	sc.add_child(row)
	return [sc, row]


static func width(ph: Phone) -> float:
	return ph._page_host.size.x


static func cols(ph: Phone, min_w: float, of := -1.0) -> int:
	var w := of if of > 0.0 else width(ph)
	return maxi(1, int((w + 16.0) / (min_w + 16.0)))


static func grid(n: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = n
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 16)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


## A tappable photo card: picture on top, title, subtitle, a price line and
## an optional badge on the photo.
static func photo_card(pic: Control, w: float, ph_h: float, title: String, sub: String, price: String, price_col: Color,
		badge := "", badge_col := Color.WHITE, cb = null, selected := false) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, ph_h + 118)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := G.box(G.CARD, 24, 0)
	if selected:
		n.border_color = G.ACCENT
		n.set_border_width_all(3)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = G.CARD.lerp(G.LABEL, 0.06)
	for s in ["normal", "focus", "hover", "disabled"]:
		b.add_theme_stylebox_override(s, n)
	b.add_theme_stylebox_override("pressed", p)
	var v := G.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(v)
	# (A photo frame clips its own corners: clipping it again inside a
	# second clipper drew it black – nested clip_children.)
	var frame: Control
	if pic is Panel and (pic as Panel).clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
		frame = pic
		frame.custom_minimum_size = Vector2(0, ph_h)
		var fs := (frame.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		fs.set_corner_radius_all(24)
		fs.corner_radius_bottom_left = 0
		fs.corner_radius_bottom_right = 0
		fs.bg_color = G.CARD2
		frame.add_theme_stylebox_override("panel", fs)
	else:
		frame = G.rounded(pic, Vector2(0, ph_h), 24)
		(frame.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_bottom_left = 0
		(frame.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_bottom_right = 0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(frame)
	if badge != "":
		var bd := G.badge(badge, badge_col, true)
		bd.position = Vector2(14, 14)
		frame.add_child(bd)
	var t := G.vbox(1)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(G.margin(t, 18, 8, 16, 14))
	t.add_child(G.line(title, "headline"))
	t.add_child(G.line(sub, "footnote", G.LABEL2))
	if price != "":
		t.add_child(G.line(price, "callout", price_col, "semibold"))
	if cb != null:
		G.feedback(b, cb)
	return b


## Buy buttons ask once more by changing in place (no extra screen): the
## first tap turns it into "Confirm · £x" for three seconds.
static func confirm_button(label: String, confirm: String, cb: Callable, sz := "large", col = null, kind := "filled") -> Button:
	return G.confirm_button(label, confirm, cb, sz, col, kind)


## A line chart (Stocks): green if it ends higher than it started, red if
## lower, a soft fill under it; `labels` = draw first/last values.
class Chart extends Control:
	var data: Array = []
	var col := Color.GREEN
	var fill := true
	var thick := 3.0

	func _init(p_data: Array = [], p_size := Vector2(200, 80), p_thick := 3.0) -> void:
		data = p_data
		custom_minimum_size = p_size
		thick = p_thick
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if data.size() >= 2:
			col = Glass.GREEN if float(data[-1]) >= float(data[0]) else Glass.RED

	func _draw() -> void:
		var n := data.size()
		if n < 2:
			draw_line(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), Color(Glass.LABEL3, 0.6), 2.0, true)
			return
		var lo := INF
		var hi := -INF
		for x in data:
			lo = minf(lo, float(x))
			hi = maxf(hi, float(x))
		if hi - lo < 1e-6:
			hi = lo + 1.0
		var pad := thick + 2.0
		var pts := PackedVector2Array()
		for i in n:
			pts.append(Vector2(size.x * float(i) / float(n - 1),
				pad + (size.y - pad * 2.0) * (1.0 - (float(data[i]) - lo) / (hi - lo))))
		if fill:
			var poly := pts.duplicate()
			poly.append(Vector2(size.x, size.y))
			poly.append(Vector2(0, size.y))
			var cols := PackedColorArray()
			for p in poly:
				cols.append(Color(col, 0.22 * (1.0 - p.y / size.y)))
			draw_polygon(poly, cols)
		draw_polyline(pts, col, thick, true)


static func change_pill(pct: float) -> PanelContainer:
	var up := pct >= 0.0
	var p := PanelContainer.new()
	var sb := G.box(G.GREEN if up else G.RED, 10, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.x = 104
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := G.text(("+" if up else "−") + "%.2f%%" % absf(pct), "subhead", Color.WHITE, "semibold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(l)
	return p


# ---------------------------------------------------------------- home
static func home(ph: Phone, body: VBoxContainer) -> void:
	var ui := ph.ui
	var g := ph.game
	var e := g.empire
	var v := scroller(body, 14)
	# Compact, neutral-glass Wealth & Chart card (essential info by default;
	# no oversized gradient financial card).
	var rc := G.card(18, 10)
	v.add_child(rc[0])
	var rv: VBoxContainer = rc[1]
	var hist: Array = e.day_reports.map(func(r): return float(r.get("net_worth", 0.0)))
	var rng := String(Phone.st("overview").get("range", "1W"))
	var nsl: int = {"1W": 7, "1M": 30, "All": 100000}.get(rng, 7)
	var shown: Array = hist.slice(maxi(hist.size() - nsl, 0))
	shown.append(e.net_worth())
	var first := float(shown[0]) if not shown.is_empty() else e.net_worth()
	var delta := e.net_worth() - first
	var yd := float(e.day_reports[-1].get("profit", 0.0)) if not e.day_reports.is_empty() else 0.0
	var top_row := G.hbox(14)
	var nw_col := G.vbox(-2)
	nw_col.add_child(G.text("NET WORTH", "caption2", G.LABEL2, "semibold"))
	nw_col.add_child(G.text(EmpireData.money(e.net_worth()), "title2", G.LABEL, "bold"))
	nw_col.add_child(G.text(("▲ " if delta >= 0.0 else "▼ ") + EmpireData.money(absf(delta)) + (" · " + rng),
		"caption", G.GREEN if delta >= 0.0 else G.RED, "semibold"))
	top_row.add_child(nw_col)
	top_row.add_child(G.spacer())
	var cash_col := G.vbox(-2)
	cash_col.add_child(G.text("AVAILABLE CASH", "caption2", G.LABEL2, "semibold"))
	cash_col.add_child(G.text(EmpireData.money(e.personal_cash + maxf(e.company_cash, 0.0)), "headline", G.ACCENT_TEXT, "semibold"))
	cash_col.add_child(G.text(("Yesterday " + EmpireData.money(yd, true)) if not e.day_reports.is_empty() else "Day %d" % e.day,
		"caption", G.GREEN if yd >= 0.0 else G.RED if not e.day_reports.is_empty() else G.LABEL2))
	top_row.add_child(cash_col)
	rv.add_child(top_row)
	if shown.size() >= 3:
		var ch := Chart.new(shown, Vector2(0, 74), 2.5)
		ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rv.add_child(ch)
	# Actionable alerts & current objective (essential only).
	var rows: Array = []
	var ob := g.objective()
	if String(ob[0]) != "":
		rows.append(G.row(String(ob[0]), "Next step · tap to set route", "", "goals", G.ACCENT_TEXT, ui.objective_action))
	for a in Dashboard.grouped(ui).slice(0, 3):
		var ad: Dictionary = a
		var tone: Color = EmpireUI.tones()[ad["tone"]]
		rows.append(G.row(String(ad["title"]), "Tap to resolve", "", String(ad.get("icon", "alert")), tone, func(): Dashboard.open_group(ui, ad)))
	if rows.is_empty():
		rows.append(G.row("All operations running smoothly", "Every shop is stocked and trading", "", "goals", G.GREEN))
	v.add_child(G.group(rows, "Notifications"))
	# Visual business strip (photo cards).
	v.add_child(G.header("Businesses", "Manage all", func(): ph.go("businesses")))
	var car := carousel(12)
	v.add_child(car[0])
	if e.businesses.is_empty():
		(car[1] as HBoxContainer).add_child(photo_card(Thumbs.place(Dashboard._door(g, null), 120.0), 260, 128, "Lease your first shop",
			"Available units across the city", "Browse properties ›", G.ACCENT_TEXT, "", Color.WHITE, func(): ph.go("property")))
	for b: Business in e.businesses:
		var bb := b
		var uid := String(b.premises.get("id", ""))
		var stt := b.status(e.minute / 60.0)
		var prof := float(b.last_day().get("profit", 0.0))
		(car[1] as HBoxContainer).add_child(photo_card(PhotoBook.frame(uid, "front", Vector2(260, 128), Dashboard._door(g, b), 0), 260, 128,
			b.name, String(EmpireData.business_type(b.type_id).get("name", "Shop")), ("Yesterday " + EmpireData.money(prof, true)) if not b.history.is_empty() else "New",
			G.GREEN if prof >= 0.0 else G.RED, String(stt[1]), EmpireUI.tones()[stt[2]], func(): ui.open_manage(bb)))
	# Progressive disclosure: Recent Activity hidden behind a clean toggle by default.
	var show_more := bool(Phone.st("overview").get("show_activity", false))
	var toggle_row := G.hbox(8)
	toggle_row.add_child(G.button("Hide recent activity" if show_more else "Show recent activity & breakdown", func():
		Phone.st("overview")["show_activity"] = not show_more
		ph.refresh(), "gray", "small"))
	toggle_row.add_child(G.spacer())
	toggle_row.add_child(G.button("Full Finances ›", func():
		Phone.st("overview")["sub"] = "finances"
		ph.refresh(), "plain", "small"))
	v.add_child(toggle_row)
	if show_more:
		var act: Array = []
		var recent := e.ledger.slice(maxi(e.ledger.size() - 20, 0))
		recent.reverse()
		for x in recent:
			if absf(float(x["amount"])) < 0.005:
				continue
			var amt := float(x["amount"])
			act.append(G.row(String(x["memo"]), "Day %d · %02d:%02d" % [int(x["day"]), int(x["min"]) / 60, int(x["min"]) % 60],
				EmpireData.money(amt, true), "bank" if amt < 0.0 else "finances",
				G.GREEN if amt > 0.0 else G.LABEL3, null, G.GREEN if amt > 0.0 else G.LABEL))
			if act.size() >= 6:
				break
		if not act.is_empty():
			v.add_child(G.group(act, "Recent Activity"))
	v.add_child(G.gap(6))


static func _empire_card(ph: Phone, wide: bool) -> Control:
	var e := ph.game.empire
	var ident := ShopStyle.house_ident(e.brand) if not e.brand.is_empty() else {}
	var c1: Color = ident.get("primary", Color("#1f2a44"))
	var c2: Color = ident.get("accent", Color("#c9962e"))
	var card := Panel.new()
	card.custom_minimum_size = Vector2(500 if wide else 0, 250)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not wide else Control.SIZE_FILL
	card.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	card.add_theme_stylebox_override("panel", G.box(Color.WHITE, 30, 0))
	var gr := Gradient.new()
	gr.set_color(0, c1.lightened(0.08))
	gr.set_color(1, c1.lerp(c2, 0.55).darkened(0.15))
	var gt := GradientTexture2D.new()
	gt.gradient = gr
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 1)
	gt.width = 128
	gt.height = 64
	var bg := TextureRect.new()
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)
	var v := G.vbox(4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 28
	v.offset_top = 24
	v.offset_right = -28
	v.offset_bottom = -22
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var top := G.hbox(12)
	top.add_child(ph.ui._brand_badge(44))
	var nm := String(e.brand.get("name", ""))
	top.add_child(G.line(nm if nm != "" else "Your empire", "headline", Color.WHITE))
	var yr := City500.your_rank(e)
	if int(yr["rank"]) > 0:
		top.add_child(G.badge("CITY500 #%d" % int(yr["rank"]), Color.WHITE, true))
	v.add_child(top)
	v.add_child(G.spacer())
	var sp := G.gap(1)
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	v.add_child(G.text("Available to spend", "footnote", Color(1, 1, 1, 0.75), "medium"))
	v.add_child(G.text(EmpireData.money(e.personal_cash + maxf(e.company_cash, 0.0)), "bignum", Color.WHITE))
	var bot := G.hbox(18)
	bot.add_child(G.text("Savings %s" % EmpireData.money(e.personal_cash), "subhead", Color(1, 1, 1, 0.82)))
	bot.add_child(G.text("Company %s" % EmpireData.money(e.company_cash), "subhead", Color(1, 1, 1, 0.82) if e.company_cash >= 0.0 else Color("#ffb3ad")))
	v.add_child(bot)
	return card


# ----------------------------------------------------------------- map
static func map(ph: Phone, body: VBoxContainer) -> void:
	var g := ph.game
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	body.add_child(holder)
	var frame := G.rounded(null, Vector2.ZERO, 30)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.add_child(frame)
	var m := EmpireMap.new()
	m.game = g
	m.chips_top = 84.0
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(m)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	var focus: Dictionary = Phone.st("map").get("focus", {})
	if not focus.is_empty():
		m.select_ref.call_deferred(focus)
		Phone.st("map").erase("focus")
	# Floating search (top left): places by name, tap one to show it.
	var bar := G.surface(-1.0, 4.0, Color(0, 0, 0, 0), true, true)
	bar.position = Vector2(16, 16)
	bar.custom_minimum_size = Vector2(minf(width(ph) - 120.0, 520.0), 58)
	holder.add_child(bar)
	var results := G.surface(26.0, 8.0, Color(0, 0, 0, 0), true, true)
	results.position = Vector2(16, 82)
	results.custom_minimum_size = Vector2(bar.custom_minimum_size.x, 0)
	results.visible = false
	holder.add_child(results)
	var rl := G.vbox(0)
	results.add_child(rl)
	var q := String(Phone.st("map").get("q", ""))
	var fill := func(text: String) -> void:
		Phone.st("map")["q"] = text
		for c in rl.get_children():
			c.queue_free()
		var t := text.strip_edges().to_lower()
		results.visible = t.length() >= 2
		m._chips.visible = not results.visible
		if not results.visible:
			return
		var here := g.player.global_position
		var hits: Array = ExploreUI.places(g).filter(func(p): return String(p["name"]).to_lower().contains(t) or String(p["what"]).to_lower().contains(t))
		hits.sort_custom(func(a, b): return here.distance_squared_to(a["pos"]) < here.distance_squared_to(b["pos"]))
		for p in hits.slice(0, 6):
			var pd: Dictionary = p
			rl.add_child(G.row(String(pd["name"]), "%s · %s" % [String(pd["what"]), ph.ui._dist_text(here.distance_to(pd["pos"]))], "",
				"map", G.BLUE, func():
					results.visible = false
					m._chips.visible = true
					m.select_ref(pd["ref"])))
		if hits.is_empty():
			rl.add_child(G.row("No places match “%s”" % text, "", ""))
	var le := G.search("Search places, shops, showrooms", q, fill)
	var lsb := le.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	lsb.bg_color = Color(0, 0, 0, 0)
	le.add_theme_stylebox_override("normal", lsb)
	bar.add_child(le)
	if q.length() >= 2:
		fill.call_deferred(q)


# --------------------------------------------------------------- market
const MARKET := [["business", "Businesses"], ["homes", "Homes"], ["vehicles", "Vehicles"], ["fashion", "Fashion"], ["invest", "Invest"]]


static func market(ph: Phone, body: VBoxContainer) -> void:
	var g := ph.game
	var e := g.empire
	var s := Phone.st("market")
	var cat := String(s.get("cat", "business"))
	var head := G.hbox(12)
	var seg := G.segmented(MARKET, cat, func(k):
		Phone.st("market")["cat"] = k
		ph.refresh())
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(seg)
	body.add_child(head)
	var q0 := String(s.get("q", ""))
	var v_ref: Array = [null]
	var gen := [0]
	var fill_market := func(query: String) -> void:
		var v: VBoxContainer = v_ref[0]
		if v == null or not is_instance_valid(v):
			return
		for c in v.get_children():
			v.remove_child(c)
			c.queue_free()
		var q_low := query.strip_edges().to_lower()
		var here := g.player.global_position
		var match_q := func(t: String) -> bool: return q_low == "" or t.to_lower().contains(q_low)
		var cw := 300.0
		var n := cols(ph, cw)
		var gd := grid(n)
		var card_w := (width(ph) - 16.0 * (n - 1)) / n
		var ph_h := card_w * 0.56
		match cat:
			"business":
				var items: Array = []
				for f in CityLife.firms_for_sale(e):
					var u: Dictionary = g.unit_by_id.get(f["unit"], {})
					if not u.is_empty():
						items.append([here.distance_to(Premises.door_point(u)), u])
				var lets: Array = []
				for u in g.units:
					if u["kind"] == "shop" and MapKit.unit_kind(g, u) == "to_let":
						lets.append([here.distance_to(Premises.door_point(u)), u])
				lets.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
				items.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
				if not items.is_empty():
					v.add_child(G.header("Trading businesses for sale"))
					v.add_child(_listing_grid(ph, items.filter(func(x): return match_q.call(String(ph.ui._listing(x[1], float(x[0]))["title"]))), n, card_w, ph_h, "market"))
				v.add_child(G.header("Shops to let near you", "On the map", func(): EmpireMap.filter = "property"; ph.go("map")))
				v.add_child(_listing_grid(ph, lets.slice(0, 12).filter(func(x): return match_q.call(String(ph.ui._listing(x[1], float(x[0]))["title"]))), n, card_w, ph_h, "market"))
			"homes":
				var hs: Array = []
				for hm in g.homes():
					if match_q.call(String(hm["name"])):
						hs.append([here.distance_to(g.home_lift(hm)), hm])
				hs.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
				v.add_child(_listing_grid(ph, hs, n, card_w, ph_h, "market"))
			"vehicles":
				var sites := {"dealer_budget": "Kestrel Motors · everyday cars", "dealer_commercial": "Vans and trucks", "dealer_luxury": "Prestige · sports and supercars",
					"aviation": "Skyport Aviation · helicopters and planes", "marina": "The Marina · boats"}
				var any_v := false
				for sid in sites:
					var models: Array = (SkyportPlay.STOCK.get(sid, []) as Array).filter(func(mm): return match_q.call(String(EmpireData.vehicle_model(mm).get("name", mm))))
					if models.is_empty():
						continue
					any_v = true
					v.add_child(G.header(String(sites[sid])))
					var car := carousel(16)
					v.add_child(car[0])
					for model in models:
						var md := EmpireData.vehicle_model(model)
						var mdl := String(model)
						var sd := String(sid)
						var own := SkyportUI._owned(ph.ui, mdl)
						var vcw := clampf(width(ph) * 0.78, 300.0, 420.0)
						var vc := CatalogArt.showcase(CatalogArt.picture(ph.ui, mdl, "hero", Vector2(vcw, vcw * 0.6)), Vector2(vcw, vcw * 0.6),
							String(md.get("name", mdl)), SkyportUI._specs(md), EmpireData.money(float(md.get("price", 0))),
							"YOU OWN %d" % own if own > 0 else "", G.GREEN,
							func(): ph.push("vehicle", {"model": mdl, "site": sd}, String(md.get("name", mdl)), "Marketplace", "car"))
						vc.size_flags_horizontal = Control.SIZE_FILL
						(car[1] as HBoxContainer).add_child(vc)
				if not any_v:
					v.add_child(G.para("No vehicles match right now.", "subhead"))
			"fashion":
				var shops: Array = ExploreUI.places(g).filter(func(p): return p["cat"] == "fashion" and match_q.call(String(p["name"])))
				shops.sort_custom(func(a, b): return here.distance_squared_to(a["pos"]) < here.distance_squared_to(b["pos"]))
				v.add_child(G.para("Clothes are tried on and bought in the shop. Pick one and the route is set.", "subhead"))
				for p in shops.slice(0, 18):
					var pd: Dictionary = p
					gd.add_child(photo_card(Thumbs.place(pd["pos"], 110.0), card_w, ph_h, String(pd["name"]), String(pd["what"]),
						ph.ui._dist_text(here.distance_to(pd["pos"])) + " away", G.LABEL2, "", Color.WHITE, func():
							g.set_gps(pd["pos"], String(pd["name"]), pd["ref"])
							ph.ui.toast("Route set: %s" % pd["name"], "info")
							ph.go("map", pd["ref"])))
				v.add_child(gd)
				v.add_child(G.button("Your wardrobe", func(): ph.go("you"), "gray", "regular", null, "shirt"))
			"invest":
				v.add_child(G.para("Buildings on Skyport Island that pay you rent every day. Run them well and they keep their value.", "subhead"))
				var inner := G.vbox(10)
				SkyportUI.estates(ph.ui, inner)
				var c := G.card(18, 10)
				(c[1] as VBoxContainer).add_child(inner)
				v.add_child(c[0])
		v.add_child(G.gap(8))
	var le := G.search("Search", q0, func(t):
		Phone.st("market")["q"] = t
		gen[0] += 1
		var ticket := int(gen[0])
		ph.get_tree().create_timer(0.10, true, false, true).timeout.connect(func():
			if ticket == gen[0]:
				fill_market.call(t)))
	le.text_submitted.connect(func(t):
		Phone.st("market")["q"] = t
		gen[0] += 1
		fill_market.call(t))
	body.add_child(le)
	v_ref[0] = scroller(body, 20)
	fill_market.call(q0)


## Photo cards for units/homes ([dist, record] pairs); a tap opens the
## listing (inspector page), the badge says what it is.
static func _listing_grid(ph: Phone, items: Array, n: int, card_w: float, ph_h: float, sec: String) -> Control:
	var gd := grid(n)
	if items.is_empty():
		gd.add_child(G.para("Nothing matches right now.", "subhead"))
	# (the first rows of cards now, the rest a few per frame: see STAGGER)
	var later: Array = []
	for i in items.size():
		var it: Array = items[i]
		if i >= 9:
			later.append(func() -> Control: return _listing_card(ph, it, card_w, ph_h, sec))
			continue
		gd.add_child(_listing_card(ph, it, card_w, ph_h, sec))
	if not later.is_empty():
		_stagger_into(ph, gd, later)
	return gd


static func _listing_card(ph: Phone, it: Array, card_w: float, ph_h: float, sec: String) -> Control:
	var info := ph.ui._listing(it[1], float(it[0]))
	var rec: Dictionary = it[1]
	var args := {"id": String(info["id"]), "home": rec.get("kind", "") == "home"}
	var ttl := String(info["title"])
	var sel := String(Phone.st(sec).get("sel", "")) == String(info["id"])
	return CatalogArt.showcase(place_pic(String(info["id"]), "front", info["world"]), Vector2(card_w, ph_h + 40.0),
		ttl, String(info["sub"]), String(info["price"]), String(info["status"]), info["col"], func():
			Phone.st(sec)["sel"] = args["id"]
			ph.push("listing", args, ttl, String(info["sub"]), "property"), sel)


## A place's photograph filling its parent (or its map crop).
static func place_pic(id: String, view: String, world: Vector3) -> Control:
	if PhotoBook.has(id, view):
		var p := PhotoBook.Photo.new()
		p.src = PhotoBook.path(id, view)
		return p
	if world.is_finite():
		return Thumbs.place(world, 140.0)
	return Control.new()


# -------------------------------------------------------------- listing
static func _record(ph: Phone, args: Dictionary) -> Dictionary:
	var id := String(args.get("id", ""))
	if args.get("home", false):
		return ph.game.home_by_id(id)
	return ph.game.unit_by_id.get(id, {})


## One listing as a page: the photographs large (Street · Location ·
## Inside), the facts, and the deal.
static func listing(ph: Phone, body: VBoxContainer, args: Dictionary) -> void:
	var rec := _record(ph, args)
	if rec.is_empty():
		body.add_child(G.para("This listing has gone.", "body"))
		return
	var g := ph.game
	var info := ph.ui._listing(rec, g.player.global_position.distance_to(info_world(ph, rec)))
	var v := scroller(body, 18)
	var id := String(info["id"])
	var views: Array = PhotoBook.views(id)
	if views.is_empty():
		views = ["front"]
	var s := Phone.st("listing")
	var view := String(s.get(id, views[0]))
	if not view in views:
		view = String(views[0])
	var wide := width(ph) > 980.0
	var lay: BoxContainer = G.hbox(22) if wide else G.vbox(18)
	v.add_child(lay)
	var left := G.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(left)
	var pw := (width(ph) * 0.6) if wide else width(ph)
	var makers: Array = []
	var caps: Array = []
	var wpos: Vector3 = info["world"]
	for vw in views:
		var vk := String(vw)
		makers.append(func(): return place_pic(id, vk, wpos))
		caps.append(String(PhotoBook.VIEW_NAMES.get(vk, vk)))
	var big := CatalogArt.Gallery.new(makers, caps if views.size() > 1 else [], views.find(view), 26)
	big.aspect = 0.6
	big.custom_minimum_size = Vector2(pw, pw * 0.6)
	big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(big)
	var bd := G.badge(String(info["status"]), info["col"], true)
	bd.position = Vector2(18, 18)
	big.add_child(bd)
	var right := G.vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wide:
		right.custom_minimum_size.x = 380
	lay.add_child(right)
	right.add_child(G.text(String(info["title"]), "title1"))
	right.add_child(G.para(String(info["sub"]), "subhead"))
	right.add_child(_hairline())
	right.add_child(G.text(String(info["price"]), "title2", CatalogArt.GOLD if info["col"] == G.LABEL else info["col"]))
	right.add_child(G.para(String(info["income"]), "callout", G.LABEL))
	# The deal: the same windows as at the door (agent fee shown there).
	var kind := MapKit.unit_kind(g, rec) if not args.get("home", false) else "home"
	var acts := G.vbox(10)
	right.add_child(acts)
	var main_label := {"to_let": "Rent or buy…", "sale": "Make an offer…", "rival": "Buy it out…", "yours": "Manage", "home": "View the home…"}.get(kind, "Open") as String
	var deal := func() -> void:
		match kind:
			"to_let":
				ph.ui.open_property(rec, true)
			"sale":
				ph.ui.open_firm(rec, true)
			"rival":
				ph.ui.open_rival(rec, true)
			"yours":
				ph.ui.open_manage(g.empire.business_at(String(rec["id"])))
			"home":
				ph.ui.open_home(rec)
	var main := G.button(main_label, deal, "filled", "large")
	acts.add_child(main)
	var gp := G.button("Directions", info["gps"], "tinted", "large", G.BLUE, "gps")
	acts.add_child(gp)
	acts.add_child(G.button("Show on map", func():
		ph.go("map", {"kind": "home" if args.get("home", false) else "unit", "id": id}), "gray", "large", null, "map"))
	right.add_child(G.para("Sign at the door for free, or through an agent from here for a small fee.", "footnote"))
	v.add_child(G.gap(6))


static func info_world(ph: Phone, rec: Dictionary) -> Vector3:
	if rec.get("kind", "") == "home":
		return ph.game.home_lift(rec)
	return Premises.door_point(rec)


# ------------------------------------------------------------- property
const PROP_KINDS := [["to_let", "To let"], ["sale", "For sale"], ["yours", "Yours"], ["home", "Homes"]]


static func property(ph: Phone, body: VBoxContainer) -> void:
	var g := ph.game
	var s := Phone.st("property")
	var kind := String(s.get("kind", "to_let"))
	var dist := String(s.get("district", "all"))
	body.add_child(G.segmented(PROP_KINDS + [["invest", "Invest"]], kind, func(k):
		Phone.st("property")["kind"] = k
		ph.refresh()))
	if kind == "invest":
		var v0 := scroller(body)
		var inner := G.vbox(10)
		SkyportUI.estates(ph.ui, inner)
		var c := G.card(18, 10)
		(c[1] as VBoxContainer).add_child(inner)
		v0.add_child(c[0])
		return
	if kind != "home":
		var dists := {}
		for u in g.units:
			if u["kind"] == "shop":
				dists[String(u["district"])] = String(EmpireData.district(u["district"]).get("name", u["district"]))
		var keys := dists.keys()
		keys.sort()
		var items: Array = [["all", "Everywhere"]]
		for k in keys:
			items.append([k, dists[k]])
		body.add_child(G.pills(items, dist, func(k):
			Phone.st("property")["district"] = k
			ph.refresh()))
	var here := g.player.global_position
	var rows: Array = []
	if kind == "home":
		for hm in g.homes():
			rows.append([here.distance_to(g.home_lift(hm)), hm])
	else:
		for u in g.units:
			if u["kind"] != "shop" or (dist != "all" and u["district"] != dist):
				continue
			var uk := MapKit.unit_kind(g, u)
			if (kind == "sale" and uk not in ["sale", "rival"]) or (kind != "sale" and uk != kind):
				continue
			rows.append([here.distance_to(Premises.door_point(u)), u])
	rows.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var v := scroller(body, 18)
	var n := cols(ph, 290.0)
	var cw := (width(ph) - 16.0 * (n - 1)) / n
	v.add_child(G.text("%d listing%s · nearest first" % [rows.size(), "" if rows.size() == 1 else "s"], "subhead", G.LABEL2))
	v.add_child(_listing_grid(ph, rows.slice(0, 36), n, cw, cw * 0.58, "property"))
	if rows.size() > 36:
		v.add_child(G.para("Showing the nearest 36 – pick a district for the rest.", "footnote"))


# ---------------------------------------------------------- vehicles
static func garage(ph: Phone, body: VBoxContainer) -> void:
	var ui := ph.ui
	var g := ph.game
	var e := g.empire
	var mine: Array = e.vehicles.filter(func(x): return not x.get("test", false))
	var v := scroller(body, 20)
	_lockup_card(ph, v)
	if mine.is_empty():
		v.add_child(G.para("You don't own anything with wheels, wings or a hull yet.", "body"))
		v.add_child(G.button("Browse the showrooms", func(): Phone.st("market")["cat"] = "vehicles"; ph.go("market"), "filled", "large"))
		return
	var s := Phone.st("vehicles")
	var sel := String(s.get("sel", ""))
	var veh: Dictionary = mine[0]
	for x in mine:
		if String(x["id"]) == sel:
			veh = x
	var vid := String(veh["id"])
	var in_lockup := String(veh.get("stored", "")) != ""
	var md := EmpireData.vehicle_model(String(veh["model"]))
	var cls := String(md.get("class", "car"))
	var wide := width(ph) > 980.0
	var lay: BoxContainer = G.hbox(24) if wide else G.vbox(16)
	v.add_child(lay)
	# The showroom: the car's studio photography, swipeable.
	var sw := width(ph) * (0.58 if wide else 1.0)
	var stage := CatalogArt.model_gallery(ui, String(veh["model"]), Vector2(sw, sw * 0.5625), 30)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(stage)
	var info := G.vbox(12)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(info)
	info.add_child(G.text(({"car": "MOTOR", "heli": "ROTORCRAFT", "plane": "AVIATION", "boat": "MARINE"}.get(cls, "") as String) + "  ·  YOURS", "caption2", CatalogArt.GOLD, "semibold"))
	info.add_child(G.text(String(md.get("name", "")), "title1"))
	var inside := g.driving == vid or (g.skyport_play and g.skyport_play.piloting == vid)
	var here := g.player.global_position
	var p := g.vehicle_position(vid)
	info.add_child(G.para("You're in it" if inside else "%s away · %s" % [ui._dist_text(here.distance_to(p)),
		String(EmpireData.district(("west:" if p.x < CityLayout.FAR_SHORE else "east:") + g.layout.district(p.x, p.z)).get("name", ""))], "subhead"))
	var specs := G.hbox(10)
	var cond := float(veh["condition"])
	for f in [["Condition", "%d%%" % int(cond * 100.0), G.GREEN if cond > 0.7 else (G.ORANGE if cond > 0.35 else G.RED)],
			["Driven", "%d km" % int(float(veh["km"])), G.LABEL], ["Worth", EmpireData.money(e.vehicle_value(veh)), G.LABEL]]:
		var fc := G.card(16, 0, G.CARD)
		(fc[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(fc[1] as VBoxContainer).add_child(G.figure(String(f[0]), String(f[1]), f[2], "title3"))
		specs.add_child(fc[0])
	info.add_child(specs)
	info.add_child(G.para(SkyportUI._specs(md) + " · " + SkyportUI._running(md), "footnote"))
	var acts := G.hbox(10)
	info.add_child(acts)
	var fb := G.button("Find", func(): ui.find_vehicle(vid), "filled", "regular", null, "gps")
	fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fb.disabled = inside
	acts.add_child(fb)
	if cls == "car" and in_lockup:
		var tb := G.button("Take out of the lock-up", func():
			var err := g.street_cars.take_out(vid)
			ui.toast(err if err != "" else "It's out at the kerb", "bad" if err != "" else "good")
			ph.refresh(), "filled", "regular", null, "truck")
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acts.add_child(tb)
	elif cls == "car":
		var q := g.delivery_quote(vid)
		var db := G.button("Deliver · %s" % EmpireData.money(float(q["fee"])) if q["ok"] else String(q["why"]), func():
			var err := g.deliver_vehicle(vid)
			ui.toast(err if err != "" else "A driver is bringing it round", "bad" if err != "" else "good")
			ph.refresh(), "gray", "regular", null, "truck")
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		db.disabled = not q["ok"]
		acts.add_child(db)
	var acts2 := G.hbox(10)
	info.add_child(acts2)
	var cost := float(EmpireData.file("vehicles").get("service_cost", 80.0)) * (1.5 - cond * 0.5)
	var svc := G.button("Service · %s" % EmpireData.money(cost), func():
		var err := e.service_vehicle(veh)
		ui.toast(err if err != "" else "Serviced: back to 100%", "bad" if err != "" else "good")
		ph.refresh(), "gray", "regular", null, "wrench")
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.disabled = cond > 0.95
	acts2.add_child(svc)
	var worth := e.vehicle_value(veh)
	var why := e.sell_vehicle_block(veh)
	if why == "" and inside:
		why = "Get out first"
	var hot: bool = veh.get("stolen", false) or String(veh.get("provenance", "")) == "stolen"
	var sell_word := "Chop shop (no papers)" if hot else "Sell"
	var sell := confirm_button("%s · %s" % [sell_word, EmpireData.money(worth)], "Confirm · %s" % EmpireData.money(worth), func():
		var err := g.sell_vehicle(vid)
		ui.toast(err if err != "" else "Sold for %s" % EmpireData.money(worth), "bad" if err != "" else "good")
		if err == "":
			Phone.st("vehicles").erase("sel")
		ph.refresh(), "regular", G.RED, "tinted")
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.disabled = why != ""
	sell.tooltip_text = why
	acts2.add_child(sell)
	# Damage and the garage (vehicle damage overhaul): what's broken, and a
	# Motor Works quote for a mechanical repair or a full restoration.
	if cls == "car" and g.cars.has(vid):
		var car_n: Car = g.cars[vid]
		var report := g.damage_report(car_n)
		var rc := G.card(16, 8)
		var rv: VBoxContainer = rc[1]
		var rtop := G.hbox(10)
		rtop.add_child(G.line("Damage", "headline"))
		var sev := maxf(car_n.body_damage(), car_n.mech_damage())
		rtop.add_child(G.badge("NONE" if report.is_empty() else ("MINOR" if sev < 0.25 else ("SERIOUS" if sev < 0.6 else "SEVERE")),
			G.GREEN if report.is_empty() else (G.ORANGE if sev < 0.6 else G.RED)))
		rv.add_child(rtop)
		rv.add_child(G.para("No damage – it's as it left the showroom." if report.is_empty() else " · ".join(report), "footnote"))
		if not report.is_empty():
			var rq := g.repair_quote(vid)
			var tow := float(rq["tow"])
			rv.add_child(G.para(("At %s." % String((rq["garage"] as Dictionary).get("name", "Motor Works"))) if rq["at_garage"]
				else "Nearest Motor Works is away – collection and return adds %s." % EmpireData.money(tow), "caption"))
			var rb := G.hbox(10)
			rv.add_child(rb)
			var mb := G.button("Mechanical · %s" % EmpireData.money(float(rq["mech"]) + tow), func():
				var err := g.repair_vehicle(vid, "mech")
				ui.toast(err if err != "" else "Engine, tyres and suspension fixed", "bad" if err != "" else "good")
				ph.refresh(), "gray", "regular", null, "wrench")
			mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mb.disabled = not rq["ok"] or float(rq["mech"]) <= 0.0
			rb.add_child(mb)
			var fb2 := G.button("Full restoration · %s" % EmpireData.money(float(rq["full"]) + tow), func():
				var err := g.repair_vehicle(vid, "full")
				ui.toast(err if err != "" else "Restored: bodywork, glass and paint as new", "bad" if err != "" else "good")
				ph.refresh(), "filled", "regular", null, "wrench")
			fb2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fb2.disabled = not rq["ok"]
			rb.add_child(fb2)
		info.add_child(rc[0])
	# Charter Operations for aircraft and boats (passive daily revenue).
	if Ventures.is_charterable(veh):
		var chartered := Ventures.is_chartered(e, vid)
		var daily_inc := Ventures.vehicle_charter_daily(veh)
		var chc := G.card(16, 8)
		var chv: VBoxContainer = chc[1]
		var ch_top := G.hbox(10)
		ch_top.add_child(G.line("Charter Operations", "headline"))
		ch_top.add_child(G.badge("ACTIVE" if chartered else "PRIVATE", G.GREEN if chartered else G.LABEL2))
		chv.add_child(ch_top)
		chv.add_child(G.para(("Earning ~%s/day in executive charter revenue (slight daily wear)." % EmpireData.money(daily_inc)) if chartered else
			"Put this craft on executive charter to earn ~%s/day passively." % EmpireData.money(daily_inc), "footnote"))
		var ch_btn := G.button("Pause charter" if chartered else "Start charter · +%s/day" % EmpireData.money(daily_inc), func():
			var now_on := Ventures.toggle_charter(e, vid)
			g.save_game()
			ui.toast("Charter active: ~%s/day" % EmpireData.money(daily_inc) if now_on else "Removed from charter", "good" if now_on else "info")
			ph.refresh(), "gray" if chartered else "filled", "small", null if not chartered else G.LABEL)
		chv.add_child(ch_btn)
		info.add_child(chc[0])
	# Everything you own, one tap to bring it on stage.
	v.add_child(G.header("Your vehicles", "Showrooms", func(): Phone.st("market")["cat"] = "vehicles"; ph.go("market")))
	var car := carousel(14)
	v.add_child(car[0])
	for x in mine:
		var xd: Dictionary = x
		var xm := EmpireData.vehicle_model(String(xd["model"]))
		var xid := String(xd["id"])
		var xc := CatalogArt.showcase(CatalogArt.picture(ui, String(xd["model"]), "hero", Vector2(280, 168)), Vector2(280, 168),
			String(xm.get("name", "")), "%d%% condition" % int(float(xd["condition"]) * 100.0), "", "", Color.WHITE, func():
				Phone.st("vehicles")["sel"] = xid
				ph.refresh(), xid == vid)
		xc.size_flags_horizontal = Control.SIZE_FILL
		(car[1] as HBoxContainer).add_child(xc)


# ---------------------------------------------------- vehicle (market)
static func vehicle_offer(ph: Phone, body: VBoxContainer, model: String, site: String) -> void:
	var ui := ph.ui
	var g := ph.game
	var md := EmpireData.vehicle_model(model)
	var cls := String(md.get("class", "car"))
	var price := float(md.get("price", 0))
	var v := scroller(body, 18)
	var wide := width(ph) > 980.0
	var lay: BoxContainer = G.hbox(28) if wide else G.vbox(18)
	v.add_child(lay)
	var sw := width(ph) * (0.6 if wide else 1.0)
	var gal := CatalogArt.model_gallery(ui, model, Vector2(sw, sw * 0.5625), 28)
	gal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(gal)
	var own := SkyportUI._owned(ui, model)
	if own > 0:
		var ob := G.badge("YOU OWN %d" % own, G.GREEN, true)
		ob.position = Vector2(18, 18)
		gal.add_child(ob)
	var info := G.vbox(12)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(info)
	info.add_child(G.text(({"car": "MOTOR", "heli": "ROTORCRAFT", "plane": "AVIATION", "boat": "MARINE"}.get(cls, "") as String)
		+ ("  ·  %s" % String(g.skyport_play.site(site).get("name", "")).to_upper() if not g.skyport_play.site(site).is_empty() else ""), "caption2", CatalogArt.GOLD, "semibold"))
	info.add_child(G.text(String(md.get("name", model)), "title1"))
	var d := String(md.get("desc", ""))
	if d != "":
		info.add_child(G.para(d, "body", G.LABEL2))
	info.add_child(_spec_chips(md))
	info.add_child(_hairline())
	var pr := G.hbox(10)
	var pv := G.vbox(0)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_child(G.text("PRICE", "caption2", G.LABEL2, "semibold"))
	pv.add_child(G.text(EmpireData.money(price), "title2", CatalogArt.GOLD))
	pr.add_child(pv)
	info.add_child(pr)
	info.add_child(G.para(SkyportUI._running(md), "footnote"))
	info.add_child(confirm_button("Buy · %s" % EmpireData.money(price), "Tap again to pay %s" % EmpireData.money(price), func():
		var err := g.skyport_play.buy_car(model, site) if cls == "car" else g.skyport_play.buy(model)
		if err != "":
			ui.toast(err, "bad")
			return
		Sfx.play("cash", -3.0)
		ui.toast("It's yours: %s" % ({"car": "parked on the forecourt", "heli": "on the helipad – the GPS shows where",
			"plane": "on a stand by the hangars", "boat": "in a berth at the marina"}.get(cls, "")), "good")
		ph.refresh()))
	var row2 := G.hbox(10)
	info.add_child(row2)
	var tb := G.button({"car": "Test drive", "boat": "Test sail"}.get(cls, "Test flight"), func():
		g.skyport_play.start_test(model, site), "gray", "large")
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(tb)
	var st := g.skyport_play.site(site)
	if not st.is_empty():
		var door: Vector3 = st["door"]
		var db := G.button("Showroom", func():
			g.set_gps(door, String(st["name"]), {"kind": "place", "id": site})
			ui.toast("Route set: %s" % st["name"], "info"), "tinted", "large", G.BLUE, "gps")
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(db)
	v.add_child(G.gap(8))


## A fine gold-tinted rule between sections.
static func _hairline() -> Control:
	var r := ColorRect.new()
	r.color = Color(CatalogArt.GOLD, 0.28)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## The headline numbers as small chips (wraps on narrow phones).
static func _spec_chips(md: Dictionary) -> Control:
	var cls := String(md.get("class", "car"))
	var chips: Array = []
	match cls:
		"heli", "plane":
			chips = [["Cruise", "%d kt" % int(float(md.get("cruise", 0)) * 1.944)], ["Seats", str(int(md.get("seats", 2 if cls == "heli" else 4)))]]
			if cls == "heli":
				chips.append(["Climb", "%d m/s" % int(md.get("climb", 0))])
			else:
				chips.append(["Top", "%d kt" % int(float(md.get("vmax", 0)) * 1.944)])
		"boat":
			chips = [["Top", "%d kt" % int(float(md.get("vmax", 0)) * 1.944)], ["Length", "%d m" % int((md.get("size", [0, 0, 6]) as Array)[2])]]
		_:
			chips = [["Top speed", "%d mph" % int(float(md.get("top_speed", 30.0)) * 2.237)], ["Cargo", "%d cases" % int(md.get("cargo", 8))],
				["Grip", "%d / 10" % clampi(int(roundf(float(md.get("grip", 1.4)) * 5.5)), 1, 10)]]
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 10)
	fl.add_theme_constant_override("v_separation", 10)
	for c in chips:
		var p := PanelContainer.new()
		var sb := G.box(G.FILL, 16, 0)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		p.add_theme_stylebox_override("panel", sb)
		var cv := G.vbox(0)
		cv.add_child(G.text(String(c[0]).to_upper(), "caption2", G.LABEL2, "semibold"))
		cv.add_child(G.text(String(c[1]), "headline"))
		p.add_child(cv)
		fl.add_child(p)
	return fl


# -------------------------------------------------------------- city500
static func _c500_idx(c: Dictionary) -> int:
	if c.has("i"):
		return int(c["i"])
	return City500.companies().find(c)


const STAGGER_FIRST := 14
const STAGGER_PER_FRAME := 6


## Appends rows to a G.group a few per frame (makers: Callables returning
## a row Control), with the group's separators; stops if the group goes.
static func _stagger_rows(ph: Phone, grp: VBoxContainer, makers: Array) -> void:
	var inner: VBoxContainer
	for ch in grp.get_children():
		if ch is PanelContainer:
			inner = (ch as PanelContainer).get_child(0) as VBoxContainer
	if inner == null:
		return
	_stagger_into(ph, inner, makers, true)


## Adds makers' Controls to `box` a few per frame (with G.group separators
## when `rule`).
static func _stagger_into(ph: Phone, box: Container, makers: Array, rule := false) -> void:
	var inner := box
	var queue := makers.duplicate()
	var step := func(self_ref: Array) -> void:
		if not is_instance_valid(inner) or not inner.is_inside_tree():
			return
		for k in STAGGER_PER_FRAME:
			if queue.is_empty():
				return
			var row: Control = (queue.pop_front() as Callable).call()
			if rule:
				var hr := ColorRect.new()
				hr.color = G.SEP
				hr.custom_minimum_size.y = 1
				hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var last := inner.get_child(inner.get_child_count() - 1) as Control if inner.get_child_count() > 0 else null
				inner.add_child(G.margin(hr, 76 if last and last.has_meta("icon") else 22, 0, 0, 0))
			inner.add_child(row)
		if not queue.is_empty():
			ph.get_tree().process_frame.connect(func(): (self_ref[0] as Callable).call(self_ref), CONNECT_ONE_SHOT)
	var holder := [step]
	ph.get_tree().process_frame.connect(func(): step.call(holder), CONNECT_ONE_SHOT)


static func city500(ph: Phone, body: VBoxContainer) -> void:
	var e := ph.game.empire
	var s := Phone.st("city500")
	var sector := String(s.get("sector", ""))
	var q0 := String(s.get("q", ""))
	var wide := width(ph) > 1080.0
	var items: Array = [["", "All"]]
	for k in City500.SECTORS:
		items.append([k, City500.sector_name(k)])
	body.add_child(G.pills(items, sector, func(k):
		Phone.st("city500")["sector"] = k
		ph.refresh()))
	var search_row := G.hbox(10)
	body.add_child(search_row)
	var rank := City500.ranking(e)
	var yr := City500.your_rank(e)
	var day := e.day
	var holdings := City500.all_stakes(e)
	var list_ref: Array = [null, null]   # [VBoxContainer, TouchScroll]
	var gen := [0]
	var fill_c500 := func(query: String, jump_to_you := false) -> void:
		var v: VBoxContainer = list_ref[0]
		var sc: ScrollContainer = list_ref[1]
		if v == null or not is_instance_valid(v):
			return
		for ch in v.get_children():
			v.remove_child(ch)
			ch.queue_free()
		var q_low := query.strip_edges().to_lower()
		var cur_sec := String(Phone.st("city500").get("sector", ""))
		var limit := int(Phone.st("city500").get("limit", 60))
		# (2026-11-27) Rows are built as they're needed: the first screenful
		# now, the rest a few per frame (STAGGER) – opening City500 built all
		# sixty at once, a visible pause on a phone.
		var rows: Array = []
		var later: Array = []
		var shown := 0
		var you_row: Control = null
		for r in rank:
			if r.get("you", false):
				if cur_sec == "" and q_low == "":
					you_row = _c500_you(ph, r)
					rows.append(you_row)
				continue
			var c: Dictionary = r["c"]
			if cur_sec != "" and String(c["sector"]) != cur_sec:
				continue
			if q_low != "" and not String(c["name"]).to_lower().contains(q_low):
				continue
			shown += 1
			if shown > limit:
				continue
			if rows.size() < STAGGER_FIRST or jump_to_you:
				rows.append(_c500_row(ph, r, day, wide))
			else:
				later.append(r)
		var hdr := G.card(20, 6)
		(hdr[1] as VBoxContainer).add_child(G.figure("Your empire's value", City500.money(float(yr["value"])), null, "title2"))
		var ahead: Dictionary = yr["ahead"]
		(hdr[1] as VBoxContainer).add_child(G.para(("#%d of 500" % int(yr["rank"])) + (" · %s to pass %s" % [City500.money(float(ahead["value"]) - float(yr["value"])), ahead["c"]["name"]] if not ahead.is_empty() else "")
			if int(yr["rank"]) > 0 else "%s more to enter the City500" % City500.money(float(yr["gap_500"])), "subhead"))
		v.add_child(hdr[0])
		if cur_sec == "" and q_low == "":
			if not holdings.is_empty():
				var holding_rows: Array = []
				for h: Dictionary in holdings:
					var idx := int(h["idx"])
					var title := String(h["name"])
					holding_rows.append(G.row(title, "%.1f%% owned · %s/day" % [float(h["pct"]), City500.money(float(h["daily_div"]))],
						City500.money(float(h["value"])), "chart", G.GREEN,
						func(): ph.push("company", {"idx": idx}, title, "Portfolio", "star")))
				v.add_child(G.group(holding_rows, "Your holdings"))
			v.add_child(_c500_next(ph))
		if rows.is_empty():
			v.add_child(G.para("No companies match “%s”." % query, "subhead"))
		else:
			var grp := G.group(rows)
			v.add_child(grp)
			if not later.is_empty():
				_stagger_rows(ph, grp, later.map(func(r): return func() -> Control: return _c500_row(ph, r, day, wide)))
		if shown > limit:
			v.add_child(G.button("Show more (%d)" % (shown - limit), func():
				Phone.st("city500")["limit"] = limit + 100
				ph.refresh(), "gray", "regular"))
		if jump_to_you and sc != null and is_instance_valid(sc):
			ph.get_tree().process_frame.connect(func():
				if not is_instance_valid(sc):
					return
				if you_row != null and is_instance_valid(you_row):
					var ty := int(you_row.get_global_rect().position.y - sc.get_global_rect().position.y + sc.scroll_vertical - 140)
					sc.scroll_vertical = maxi(ty, 0)
				else:
					sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value), CONNECT_ONE_SHOT)
	var le := G.search("Search companies", q0, func(t):
		Phone.st("city500")["q"] = t
		gen[0] += 1
		var ticket := int(gen[0])
		ph.get_tree().create_timer(0.12, true, false, true).timeout.connect(func():
			if ticket == gen[0]:
				fill_c500.call(t, false)))
	le.text_submitted.connect(func(t):
		Phone.st("city500")["q"] = t
		gen[0] += 1
		fill_c500.call(t, false))
	search_row.add_child(le)
	var find_me := G.button("Find Me", func():
		Phone.st("city500")["q"] = ""
		Phone.st("city500")["sector"] = ""
		var rk := int(yr["rank"])
		if rk > 0:
			Phone.st("city500")["limit"] = maxi(int(Phone.st("city500").get("limit", 60)), rk + 25)
			if sector != "":
				Phone.st("city500")["jump_me"] = true
				ph.refresh()
			else:
				le.text = ""
				fill_c500.call("", true)
		else:
			ph.ui.toast("%s more to enter the City500 (#500)" % City500.money(float(yr["gap_500"])), "info")
			if sector != "":
				ph.refresh()
			else:
				le.text = ""
				fill_c500.call("", false), "tinted", "regular", G.ACCENT_TEXT, "location")
	search_row.add_child(find_me)
	var split := G.hbox(20)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)
	var lb := G.vbox(10)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.size_flags_stretch_ratio = 1.25
	split.add_child(lb)
	var v := scroller(lb, 14)
	list_ref[0] = v
	list_ref[1] = v.get_parent()
	var jump_now := bool(s.get("jump_me", false))
	s.erase("jump_me")
	fill_c500.call(q0, jump_now)
	if wide:
		var insp := G.vbox(12)
		insp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		split.add_child(insp)
		var sel := int(s.get("sel", -1))
		if sel < 0 and rank.size() > 0:
			for r in rank:
				if not r.get("you", false):
					sel = _c500_idx(r["c"])
					break
		if sel >= 0:
			var iv := scroller(insp, 14)
			_company_body(ph, iv, sel)


## "Your next step": a reachable milestone instead of the billion-pound top.
static func _c500_next(ph: Phone) -> Control:
	var n := City500.next_step(ph.game.empire)
	var card := G.card(20, 10)
	var cv: VBoxContainer = card[1]
	cv.add_child(G.line("YOUR NEXT STEP", "caption", G.ACCENT_TEXT, "semibold"))
	cv.add_child(G.line(String(n["label"]), "title3", null, "semibold"))
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 10)
	pb.max_value = 1.0
	var span := maxf(float(n["target"]) - float(n["from"]), 1.0)
	pb.value = clampf((float(n["value"]) - float(n["from"])) / span, 0.0, 1.0)
	pb.add_theme_stylebox_override("background", G.box(G.FILL, 5, 0))
	pb.add_theme_stylebox_override("fill", G.box(G.ACCENT, 5, 0))
	cv.add_child(pb)
	var when := ""
	if int(n["days"]) > 0:
		when = " · about %d day%s at today's profit" % [int(n["days"]), "" if int(n["days"]) == 1 else "s"]
	elif float(n["profit_day"]) <= 0.0:
		when = " · needs a profit first"
	cv.add_child(G.para("%s to go%s" % [City500.money(float(n["gap"])), when], "subhead"))
	cv.add_child(G.para("Every extra £10 a day of profit adds about %s to your value." % City500.money(float(n["per10"])), "footnote", G.LABEL2))
	cv.add_child(G.para(String(n["tip"]), "footnote"))
	if not (n["near"] as Array).is_empty():
		cv.add_child(G.line("JUST AHEAD OF YOU" if n["ranked"] else "THE CITY500'S BOTTOM RUNG", "caption", G.LABEL2, "semibold"))
		for r in n["near"]:
			var c: Dictionary = r["c"]
			var h := G.hbox(10)
			var nm := G.line("#%d  %s" % [int(r["rank"]), String(c["name"])], "subhead")
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(nm)
			h.add_child(G.line(City500.money(float(r["value"])), "subhead", G.LABEL2))
			cv.add_child(h)
	return card[0]


static func _c500_row(ph: Phone, r: Dictionary, day: int, wide: bool) -> Control:
	var c: Dictionary = r["c"]
	var idx := _c500_idx(c)
	var hist := City500.history(c, day, 14)
	var pct := (float(hist[-1]) / maxf(float(hist[0]), 1.0) - 1.0) * 100.0
	var sel := int(Phone.st("city500").get("sel", -1)) == idx and wide
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 78
	var n := G.box(G.FILL if sel else Color(0, 0, 0, 0), 18, 0)
	for st in ["normal", "focus", "hover"]:
		b.add_theme_stylebox_override(st, n)
	b.add_theme_stylebox_override("pressed", G.box(G.FILL2, 18, 0))
	var h := G.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	h.offset_right = -16
	b.add_child(h)
	var rk := G.text(str(int(r["rank"])), "headline", G.LABEL2)
	rk.custom_minimum_size.x = 52
	rk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(rk)
	var tv := G.vbox(0)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(G.line(String(c["name"]), "headline"))
	var mv := int(r["move"])
	tv.add_child(G.line(City500.sector_name(String(c["sector"])) + ("  ▲%d" % mv if mv > 0 else ("  ▼%d" % -mv if mv < 0 else "")), "footnote", G.LABEL2))
	h.add_child(tv)
	var sp := Chart.new(hist, Vector2(110, 40), 2.0)
	sp.fill = false
	sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sp)
	var vv := G.vbox(2)
	vv.alignment = BoxContainer.ALIGNMENT_CENTER
	vv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var val := G.text(City500.money(float(r["value"])), "headline")
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vv.add_child(val)
	vv.add_child(change_pill(pct))
	h.add_child(vv)
	G.feedback(b, func():
		Phone.st("city500")["sel"] = idx
		if wide:
			ph.refresh()
		else:
			ph.push("company", {"idx": idx}, String(c["name"]), City500.sector_name(String(c["sector"])), "star"))
	return b


static func _c500_you(ph: Phone, r: Dictionary) -> Control:
	var b := G.row("You · %s" % (String(ph.game.empire.brand.get("name", "")) if not ph.game.empire.brand.is_empty() else "Your empire"),
		"#%d · your businesses, property and vehicles" % int(r["rank"]), City500.money(float(r["value"])), "star", G.ACCENT, func(): ph.go("bank"), G.ACCENT_TEXT)
	return b


static func company(ph: Phone, body: VBoxContainer, idx: int) -> void:
	var v := scroller(body, 16)
	_company_body(ph, v, idx)


static func _company_body(ph: Phone, v: VBoxContainer, idx: int) -> void:
	var cs := City500.companies()
	if idx < 0 or idx >= cs.size():
		return
	var c: Dictionary = cs[idx]
	var day := ph.game.empire.day
	var pr := City500.profile(c, day)
	var hist := City500.history(c, day, 60)
	var card := G.card(22, 10)
	var cv: VBoxContainer = card[1]
	var t := G.hbox(10)
	var tv := G.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(G.line(String(c["name"]), "title2"))
	tv.add_child(G.line("%s · %s" % [City500.sector_name(String(c["sector"])), String(c.get("owner", ""))], "subhead", G.LABEL2))
	t.add_child(tv)
	var sw := Panel.new()
	sw.custom_minimum_size = Vector2(14, 14)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.add_theme_stylebox_override("panel", G.box(City500.sector_colour(String(c["sector"])), 7, 0))
	t.add_child(sw)
	cv.add_child(t)
	cv.add_child(G.text(City500.money(float(pr["value"])), "title1"))
	var pct := (float(hist[-1]) / maxf(float(hist[0]), 1.0) - 1.0) * 100.0
	cv.add_child(G.text(("▲ " if pct >= 0.0 else "▼ ") + "%.1f%% over 60 days" % absf(pct), "subhead", G.GREEN if pct >= 0.0 else G.RED, "semibold"))
	var ch := Chart.new(hist, Vector2(0, 190))
	ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_child(ch)
	v.add_child(card[0])
	var rows: Array = [
		G.row("Revenue", "a year", City500.money(float(pr["revenue"]))),
		G.row("Profit", "%.0f%% margin" % (float(pr["margin"]) * 100.0), City500.money(float(pr["profit"]))),
		G.row("Assets", "", City500.money(float(pr["assets"]))),
		G.row("Debt", "", City500.money(float(pr["debt"]))),
		G.row("Staff", "", str(int(pr["staff"]))),
		G.row("Sites", String(pr["ops"]), str(int(pr["sites"]))),
	]
	v.add_child(G.group(rows, "Profile"))
	var why := City500.why_ahead(ph.game.empire, c)
	if why != "":
		v.add_child(G.group([G.row(why, "", "", "chart", G.ORANGE)], "Against you"))
	# Equity investment: buy/sell 5% stakes in City500 companies for daily dividends.
	var e := ph.game.empire
	var st: Dictionary = City500.stake_of(e, idx)
	var pct_held := float(st.get("pct", 0.0))
	var mkt_val := float(st.get("value", 0.0))
	var gain := float(st.get("gain", 0.0))
	var div_day := City500.stake_dividend(c, day, pct_held)
	var eq := G.card(20, 10)
	var ev: VBoxContainer = eq[1]
	var eh := G.hbox(10)
	eh.add_child(G.line("Equity Investment", "headline"))
	if bool(st.get("buyout", false)):
		eh.add_child(G.badge("100% OWNED", G.GREEN))
	elif bool(st.get("control", false)):
		eh.add_child(G.badge("CONTROLLING STAKE", G.ACCENT_TEXT))
	ev.add_child(eh)
	var figs := G.hbox(16)
	figs.add_child(G.figure("Your stake", "%.0f%%" % pct_held, G.ACCENT_TEXT if pct_held > 0.0 else G.LABEL2, "title3"))
	figs.add_child(G.figure("Market value", City500.money(mkt_val) if pct_held > 0.0 else "£0", G.LABEL, "title3"))
	figs.add_child(G.figure("Daily dividend", City500.money(div_day) if pct_held > 0.0 else "£0", G.GREEN if div_day > 0.0 else G.LABEL2, "title3"))
	ev.add_child(figs)
	if pct_held > 0.001:
		ev.add_child(G.para("Unrealised %s%s" % ["+" if gain >= 0.0 else "−", City500.money(absf(gain))], "footnote", G.GREEN if gain >= 0.0 else G.RED))
	var step_pct := minf(5.0, 100.0 - pct_held)
	var step_cost := float(pr["value"]) * (step_pct / 100.0)
	var eacts := G.hbox(10)
	if step_pct > 0.001:
		eacts.add_child(_buy_equity(ph, c, idx, step_pct, step_cost, "Buy %.0f%%" % step_pct))

	if pct_held > 0.001:
		var sell_pct := minf(5.0, pct_held)
		var sell_est := float(pr["value"]) * (sell_pct / 100.0) * 0.985
		var sell_btn := confirm_button("Sell %.0f%% · %s" % [sell_pct, City500.money(sell_est)],
			"Confirm sell · %s" % City500.money(sell_est), func():
			var res: Dictionary = City500.sell_stake(e, idx, sell_pct)
			if not bool(res.get("ok", false)):
				ph.ui.toast(String(res.get("error", "Sale failed")), "bad")
			else:
				ph.game.save_game()
				Sfx.play("cash", -4.0)
				ph.ui.toast("Sold %.0f%% of %s for %s" % [float(res.get("sold_pct", sell_pct)), String(c["name"]), City500.money(float(res.get("proceeds", sell_est)))], "good")
				ph.refresh(), "regular", G.RED, "tinted")
		sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eacts.add_child(sell_btn)
	var target_pct := 100.0 if st["control"] else City500.CONTROL_PCT
	var acquire_pct := target_pct - pct_held
	if acquire_pct > step_pct + 0.001:
		var action := "Acquire remaining shares" if st["control"] else "Take control · %.0f%%" % target_pct
		var acquire_cost := float(pr["value"]) * acquire_pct / 100.0
		var acquisition := _buy_equity(ph, c, idx, acquire_pct, acquire_cost, action)
		ev.add_child(acquisition)

	ev.add_child(eacts)
	v.add_child(eq[0])


static func _buy_equity(ph: Phone, company_data: Dictionary, index: int, pct: float, cost: float, title: String) -> Button:
	var buy := confirm_button("%s · %s" % [title, City500.money(cost)], "Confirm · %s" % City500.money(cost), func():
		var res := City500.buy_stake(ph.game.empire, index, pct)
		if not res["ok"]:
			ph.ui.toast(String(res["error"]), "bad")
			return
		ph.game.save_game()
		Sfx.play("cash", -4.0)
		ph.ui.toast("Acquired %.1f%% of %s" % [float(res["bought_pct"]), String(company_data["name"])], "good")
		ph.refresh(), "regular")
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return buy


# -------------------------------------------------------------- character
static func character(ph: Phone, body: VBoxContainer) -> void:
	var ui := ph.ui
	var g := ph.game
	var e := g.empire
	var v := scroller(body, 20)
	var look := HeroLook.current(e.flags)
	var owned := Wardrobe.owned(e.flags)
	var hero := G.card(24, 12)
	var hv: VBoxContainer = hero[1]
	var parts: Array = []
	for k in ["top", "shoes", "head", "eyewear"]:
		var it := String(look.get(k, ""))
		if it != "" and not it in Wardrobe.FREE:
			parts.append(it.get_slice("_", 1).capitalize())
	hv.add_child(G.text("Jules" if look["body"] == "b" else "Ade", "footnote", G.LABEL2, "medium"))
	hv.add_child(G.para(" · ".join(parts) if not parts.is_empty() else "Everyday clothes", "title2", G.LABEL))
	var paid := 0
	for it in owned:
		paid += Wardrobe.price(String(it))
	var nout := (e.flags.get("outfits", []) as Array).size()
	hv.add_child(G.para("%d items in your wardrobe · %s of clothes · %d saved outfit%s" % [owned.size(), EmpireData.money(float(paid)), nout, "" if nout == 1 else "s"], "subhead"))
	var hb := G.hbox(10)
	var eb := G.button("Character & wardrobe", func(): ui.open_style(), "filled", "large", null, "person")
	eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(eb)
	hv.add_child(hb)
	v.add_child(hero[0])
	# What's in the wardrobe, by kind.
	var kinds := {"top": [], "shoes": [], "head": [], "eyewear": []}
	for it in owned:
		var k := String(it).get_slice("_", 0)
		var key: String = {"top": "top", "shoe": "shoes", "shoes": "shoes", "head": "head", "hat": "head", "eye": "eyewear", "face": "eyewear"}.get(k, "top")
		(kinds[key] as Array).append(String(it))
	var rows: Array = []
	for k in kinds:
		var arr: Array = kinds[k]
		rows.append(G.row({"top": "Tops", "shoes": "Shoes", "head": "Hats", "eyewear": "Eyewear"}[k],
			", ".join(arr.map(func(x): return String(x).get_slice("_", 1).capitalize()).slice(0, 4)) if not arr.is_empty() else "Nothing yet",
			str(arr.size()), "shirt", G.PURPLE))
	v.add_child(G.group(rows, "Wardrobe"))
	# Where to shop.
	var here := g.vehicle_node().global_position if g.vehicle_node() else g.player.global_position
	var shops: Array = ExploreUI.places(g).filter(func(p): return p["cat"] == "fashion")
	shops.sort_custom(func(a, b): return here.distance_squared_to(a["pos"]) < here.distance_squared_to(b["pos"]))
	var srows: Array = []
	for p in shops.slice(0, 8):
		var pd: Dictionary = p
		srows.append(G.row(String(pd["name"]), String(pd["what"]), ui._dist_text(here.distance_to(pd["pos"])), "bag", G.PINK, func():
			g.set_gps(pd["pos"], String(pd["name"]), pd["ref"])
			ui.toast("Route set: %s" % pd["name"], "info")
			ph.go("map", pd["ref"])))
	v.add_child(G.group(srows, "Clothes shops", "Walk in, try anything on and pay for what you keep."))


# ----------------------------------------------------------------- more
static func more(ph: Phone, body: VBoxContainer) -> void:
	var v := scroller(body, 20)
	if not Phone.recents.is_empty():
		var rr: Array = []
		for r in Phone.recents.slice(0, 5):
			var rd: Dictionary = r
			rr.append(G.row(String(rd["title"]), "%s%s" % [Phone.title_of(String(rd["section"])), (" · " + String(rd["sub"])) if String(rd["sub"]) != "" else ""],
				"", String(rd.get("icon", "")) if String(rd.get("icon", "")) != "" else "clock", G.LABEL2, func(): ph.open_recent(rd)))
		v.add_child(G.group(rr, "Recently viewed"))
	var n := cols(ph, 200.0)
	var gd := grid(n)
	for s in Phone.SECTIONS:
		var key := String(s[0])
		if key in Phone.TABS:
			continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 132)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nb := G.box(G.CARD, 24, 0)
		for st in ["normal", "focus", "hover"]:
			b.add_theme_stylebox_override(st, nb)
		b.add_theme_stylebox_override("pressed", G.box(G.CARD.lerp(G.LABEL, 0.08), 24, 0))
		var cv := G.vbox(10)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cv.offset_left = 18
		cv.offset_top = 18
		cv.offset_right = -14
		cv.offset_bottom = -14
		cv.add_child(G.icon_tile(Phone.icon_of(key), Phone.color_of(key), 48))
		cv.add_child(G.line(Phone.title_of(key), "headline"))
		b.add_child(cv)
		G.feedback(b, func(): ph.go(key))
		gd.add_child(b)
	v.add_child(gd)
	v.add_child(G.button("Back to the city", func(): ph.ui.close_panel(true), "gray", "large", null, "back"))


## Your lock-up (StreetCars): buy one, extend it, and what's in it.
static func _lockup_card(ph: Phone, v: VBoxContainer) -> void:
	var g := ph.game
	var sc: StreetCars = g.street_cars
	if sc == null:
		return
	var card := G.card(18, 0, G.CARD)
	v.add_child(card[0])
	var col: VBoxContainer = card[1]
	var slots := sc.lockup_slots()
	col.add_child(G.text("Lock-up garage", "title3"))
	if slots == 0:
		col.add_child(G.para("Keep cars off the street – including ones you've taken. Holds %d cars; use it at any Motor Works: stop at the door and Store in garage." % StreetCars.LOCKUP_SLOTS, "footnote"))
		var b := G.button("Buy a lock-up · %s" % EmpireData.money(StreetCars.LOCKUP_PRICE), func():
			var err := sc.buy_lockup()
			ph.ui.toast(err if err != "" else "Lock-up bought – store cars at any Motor Works", "bad" if err != "" else "good")
			ph.refresh(), "filled", "regular", null, "vehicles")
		b.disabled = not g.empire.can_afford(StreetCars.LOCKUP_PRICE)
		col.add_child(b)
		return
	var inside := sc.stored()
	col.add_child(G.para("%d of %d spaces used · stop at any Motor Works door to store the car you're in" % [inside.size(), slots], "footnote"))
	for x in inside:
		var md := EmpireData.vehicle_model(String(x["model"]))
		var row := G.hbox(10)
		row.add_child(G.para(String(md.get("name", x["model"])), "body"))
		var tb := G.button("Take out", func():
			var err := sc.take_out(String(x["id"]))
			ph.ui.toast(err if err != "" else "It's out at the kerb", "bad" if err != "" else "good")
			ph.refresh(), "gray", "small", null, "truck")
		row.add_child(tb)
		col.add_child(row)
	var ext := G.button("Add %d spaces · %s" % [StreetCars.LOCKUP_SLOTS, EmpireData.money(StreetCars.LOCKUP_EXTEND)], func():
		var err := sc.buy_lockup()
		ph.ui.toast(err if err != "" else "Lock-up extended", "bad" if err != "" else "good")
		ph.refresh(), "gray", "regular", null, "vehicles")
	ext.disabled = not g.empire.can_afford(StreetCars.LOCKUP_EXTEND)
	col.add_child(ext)
