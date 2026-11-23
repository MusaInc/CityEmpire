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
		"home":
			home(ph, body)
		"map":
			map(ph, body)
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
static func confirm_button(label: String, confirm: String, cb: Callable, sz := "large") -> Button:
	var armed := [false]
	var b := G.button(label, func(): pass, "filled", sz)
	b.pressed.connect(func():
		if Time.get_ticks_msec() < EmpireStyle.tap_block_until:
			return
		if armed[0]:
			armed[0] = false
			cb.call()
			return
		armed[0] = true
		b.text = confirm
		var gs := G._btn_box(G.GREEN, int(b.size.y * 0.5), 22)
		for s in ["normal", "focus", "hover"]:
			b.add_theme_stylebox_override(s, gs)
		for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(s, Color.WHITE)
		b.get_tree().create_timer(3.0, true, false, true).timeout.connect(func():
			if is_instance_valid(b) and armed[0]:
				armed[0] = false
				b.text = label
				var ns := G._btn_box(G.ACCENT, int(b.size.y * 0.5), 22)
				for s in ["normal", "focus", "hover"]:
					b.add_theme_stylebox_override(s, ns)
				for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
					b.add_theme_color_override(s, G.ON_ACCENT)))
	return b


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
	var v := scroller(body)
	var wide := width(ph) > 980.0
	var top: BoxContainer = G.hbox(18) if wide else G.vbox(18)
	v.add_child(top)
	# The empire card (Wallet): your brand's colours, net worth up front.
	top.add_child(_empire_card(ph, wide))
	# Today (Stocks): yesterday, rank, the chart.
	var rc := G.card(22, 8)
	(rc[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rc[0])
	var rv: VBoxContainer = rc[1]
	var hist: Array = e.day_reports.map(func(r): return float(r.get("net_worth", 0.0)))
	var rng := String(Phone.st("home").get("range", "1W"))
	var nsl: int = {"1W": 7, "1M": 30, "All": 100000}.get(rng, 7)
	var shown: Array = hist.slice(maxi(hist.size() - nsl, 0))
	shown.append(e.net_worth())
	var hr := G.hbox(10)
	var first := float(shown[0]) if not shown.is_empty() else e.net_worth()
	var delta := e.net_worth() - first
	var dv := G.vbox(0)
	dv.add_child(G.text("Net worth", "footnote", G.LABEL2, "medium"))
	dv.add_child(G.text(EmpireData.money(e.net_worth()), "title2"))
	dv.add_child(G.text(("▲ " if delta >= 0.0 else "▼ ") + EmpireData.money(absf(delta)) + ("  this week" if rng == "1W" else ("  this month" if rng == "1M" else "  since you started")),
		"subhead", G.GREEN if delta >= 0.0 else G.RED, "semibold"))
	hr.add_child(dv)
	hr.add_child(G.spacer())
	hr.add_child(G.segmented([["1W", "1W"], ["1M", "1M"], ["All", "All"]], rng, func(k):
		Phone.st("home")["range"] = k
		ph.refresh()))
	rv.add_child(hr)
	if shown.size() >= 3:
		var ch := Chart.new(shown, Vector2(0, 150 if wide else 130))
		ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rv.add_child(ch)
	else:
		rv.add_child(G.para("Your chart fills in day by day: every night's close adds a point.", "footnote"))
	# What needs you (one row each; objective first).
	var rows: Array = []
	var ob := g.objective()
	if String(ob[0]) != "":
		rows.append(G.row(String(ob[0]), "Your next step", "", "goals", G.ACCENT_TEXT if G.dark else G.ORANGE, ui.objective_action))
	for a in Dashboard.grouped(ui).slice(0, 4):
		var ad: Dictionary = a
		var tone: Color = EmpireUI.tones()[ad["tone"]]
		rows.append(G.row(String(ad["title"]), "Tap to sort it", "", String(ad.get("icon", "alert")), tone, func(): Dashboard.open_group(ui, ad)))
	if rows.is_empty():
		rows.append(G.row("All quiet", "Every shop is stocked, staffed and trading", "", "goals", G.GREEN))
	v.add_child(G.group(rows, "Needs you"))
	# Quick actions: round buttons with captions.
	var qa := G.hbox(0)
	for q in [["map", "Map", "map"], ["bag", "Market", "market"], ["car", "Garage", "vehicles"], ["bank", "Finances", "bank"],
			["star", "City500", "city500"], ["person", "Style", "you"]]:
		var key := String(q[2])
		var cv := G.vbox(6)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ib := G.icon_button(String(q[0]), func(): ph.go(key), false, 66, Phone.color_of(key))
		ib.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(ib)
		var lb := G.text(String(q[1]), "caption", G.LABEL2, "medium")
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(lb)
		qa.add_child(cv)
	v.add_child(qa)
	# Your businesses (photo carousel).
	v.add_child(G.header("Your businesses", "See all", func(): ph.go("businesses")))
	var car := carousel(16)
	v.add_child(car[0])
	if e.businesses.is_empty():
		(car[1] as HBoxContainer).add_child(photo_card(Thumbs.place(Dashboard._door(g, null), 120.0), 320, 170, "Rent your first shop",
			"The unit on the quay is going cheap", "Find shops to let ›", G.ACCENT_TEXT, "", Color.WHITE, func(): ph.go("market")))
	for b: Business in e.businesses:
		var bb := b
		var uid := String(b.premises.get("id", ""))
		var stt := b.status(e.minute / 60.0)
		var prof := float(b.last_day().get("profit", 0.0))
		(car[1] as HBoxContainer).add_child(photo_card(PhotoBook.frame(uid, "front", Vector2(320, 170), Dashboard._door(g, b), 0), 320, 170,
			b.name, String(EmpireData.business_type(b.type_id).get("name", "Shop")), ("Yesterday " + EmpireData.money(prof, true)) if not b.history.is_empty() else "New",
			G.GREEN if prof >= 0.0 else G.RED, String(stt[1]), EmpireUI.tones()[stt[2]], func(): ui.open_manage(bb)))
	# Activity (Wallet's transactions).
	var act: Array = []
	var recent := e.ledger.slice(maxi(e.ledger.size() - 30, 0))
	recent.reverse()
	for x in recent:
		if absf(float(x["amount"])) < 0.005:
			continue
		var amt := float(x["amount"])
		act.append(G.row(String(x["memo"]), "Day %d · %02d:%02d · %s" % [int(x["day"]), int(x["min"]) / 60, int(x["min"]) % 60,
			"Company" if x["acct"] == "company" else "Savings"], EmpireData.money(amt, true), "bank" if amt < 0.0 else "finances",
			G.GREEN if amt > 0.0 else G.LABEL3, null, G.GREEN if amt > 0.0 else G.LABEL))
		if act.size() >= 6:
			break
	if not act.is_empty():
		v.add_child(G.header("Activity", "Finances", func(): ph.go("bank")))
		v.add_child(G.group(act))
	v.add_child(G.gap(10))


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
	var bar := G.surface(-1.0, 4.0)
	bar.position = Vector2(16, 16)
	bar.custom_minimum_size = Vector2(minf(width(ph) - 120.0, 520.0), 58)
	holder.add_child(bar)
	var results := G.surface(26.0, 8.0)
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
	var q := String(s.get("q", ""))
	var le := G.search("Search", q, func(t):
		Phone.st("market")["q"] = t)
	le.text_submitted.connect(func(_t): ph.refresh())
	le.focus_exited.connect(func(): if String(Phone.st("market").get("q", "")) != q: ph.refresh())
	body.add_child(le)
	var v := scroller(body, 20)
	var here := g.player.global_position
	var match_q := func(t: String) -> bool: return q == "" or t.to_lower().contains(q.to_lower())
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
			for sid in sites:
				var models: Array = (SkyportPlay.STOCK.get(sid, []) as Array).filter(func(mm): return match_q.call(String(EmpireData.vehicle_model(mm).get("name", mm))))
				if models.is_empty():
					continue
				v.add_child(G.header(String(sites[sid])))
				var car := carousel(16)
				v.add_child(car[0])
				for model in models:
					var md := EmpireData.vehicle_model(model)
					var mdl := String(model)
					var sd := String(sid)
					var own := SkyportUI._owned(ph.ui, mdl)
					(car[1] as HBoxContainer).add_child(photo_card(ph.ui.thumbs.vehicle(mdl, Vector2(340, 190)), 340, 190, String(md.get("name", mdl)),
						SkyportUI._specs(md), EmpireData.money(float(md.get("price", 0))), G.LABEL, "YOU OWN %d" % own if own > 0 else "", G.GREEN,
						func(): ph.push("vehicle", {"model": mdl, "site": sd}, String(md.get("name", mdl)), "Marketplace", "car")))
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


## Photo cards for units/homes ([dist, record] pairs); a tap opens the
## listing (inspector page), the badge says what it is.
static func _listing_grid(ph: Phone, items: Array, n: int, card_w: float, ph_h: float, sec: String) -> Control:
	var gd := grid(n)
	if items.is_empty():
		gd.add_child(G.para("Nothing matches right now.", "subhead"))
	for it in items:
		var info := ph.ui._listing(it[1], float(it[0]))
		var rec: Dictionary = it[1]
		var args := {"id": String(info["id"]), "home": rec.get("kind", "") == "home"}
		var ttl := String(info["title"])
		var sel := String(Phone.st(sec).get("sel", "")) == String(info["id"])
		gd.add_child(photo_card(PhotoBook.frame(String(info["id"]), "front", Vector2(card_w, ph_h), info["world"], 0), card_w, ph_h,
			ttl, String(info["sub"]), String(info["price"]), info["col"], String(info["status"]), info["col"], func():
				Phone.st(sec)["sel"] = args["id"]
				ph.push("listing", args, ttl, String(info["sub"]), "property"), sel))
	return gd


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
	var big := PhotoBook.frame(id, view, Vector2(pw, pw * 0.58), info["world"], 26)
	big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(big)
	var bd := G.badge(String(info["status"]), info["col"], true)
	bd.position = Vector2(18, 18)
	big.add_child(bd)
	if views.size() > 1:
		left.add_child(G.segmented(views.map(func(x): return [x, String(PhotoBook.VIEW_NAMES.get(x, x))]), view, func(k):
			Phone.st("listing")[id] = k
			ph.refresh()))
	var right := G.vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wide:
		right.custom_minimum_size.x = 380
	lay.add_child(right)
	right.add_child(G.text(String(info["title"]), "title1"))
	right.add_child(G.para(String(info["sub"]), "subhead"))
	right.add_child(G.text(String(info["price"]), "title3", info["col"]))
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
	var md := EmpireData.vehicle_model(String(veh["model"]))
	var cls := String(md.get("class", "car"))
	var wide := width(ph) > 980.0
	var lay: BoxContainer = G.hbox(24) if wide else G.vbox(16)
	v.add_child(lay)
	# The showroom shot.
	var stage := Panel.new()
	stage.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	stage.add_theme_stylebox_override("panel", G.box(Color.WHITE, 30, 0))
	var sw := width(ph) * (0.58 if wide else 1.0)
	stage.custom_minimum_size = Vector2(sw, sw * 0.56)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gr := Gradient.new()
	gr.set_color(0, Color(0.86, 0.87, 0.9) if not G.dark else Color(0.2, 0.21, 0.24))
	gr.set_color(1, Color(0.97, 0.97, 0.98) if not G.dark else Color(0.08, 0.08, 0.1))
	var gt := GradientTexture2D.new()
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.7)
	gt.fill_to = Vector2(1.1, 0.0)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(bg)
	var shot := ui.thumbs.vehicle(String(veh["model"]), stage.custom_minimum_size)
	shot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(shot)
	lay.add_child(stage)
	var info := G.vbox(12)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(info)
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
	if cls == "car":
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
	var sell := G.button("Sell · %s" % EmpireData.money(worth), func():
		var err := g.sell_vehicle(vid)
		ui.toast(err if err != "" else "Sold for %s" % EmpireData.money(worth), "bad" if err != "" else "good")
		if err == "":
			Phone.st("vehicles").erase("sel")
		ph.refresh(), "tinted", "regular", G.RED)
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.disabled = why != ""
	sell.tooltip_text = why
	acts2.add_child(sell)
	# Everything you own, one tap to bring it on stage.
	v.add_child(G.header("Your vehicles", "Showrooms", func(): Phone.st("market")["cat"] = "vehicles"; ph.go("market")))
	var car := carousel(14)
	v.add_child(car[0])
	for x in mine:
		var xd: Dictionary = x
		var xm := EmpireData.vehicle_model(String(xd["model"]))
		var xid := String(xd["id"])
		(car[1] as HBoxContainer).add_child(photo_card(ui.thumbs.vehicle(String(xd["model"]), Vector2(250, 140)), 250, 140,
			String(xm.get("name", "")), "%d%% condition" % int(float(xd["condition"]) * 100.0), "", G.LABEL, "", Color.WHITE, func():
				Phone.st("vehicles")["sel"] = xid
				ph.refresh(), xid == vid))


# ---------------------------------------------------- vehicle (market)
static func vehicle_offer(ph: Phone, body: VBoxContainer, model: String, site: String) -> void:
	var ui := ph.ui
	var g := ph.game
	var md := EmpireData.vehicle_model(model)
	var cls := String(md.get("class", "car"))
	var v := scroller(body, 18)
	var wide := width(ph) > 980.0
	var lay: BoxContainer = G.hbox(24) if wide else G.vbox(16)
	v.add_child(lay)
	var sw := width(ph) * (0.6 if wide else 1.0)
	var shot := ui.thumbs.vehicle(model, Vector2(sw, sw * 0.56))
	var stage := G.rounded(shot, Vector2(sw, sw * 0.56), 30)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(stage)
	var info := G.vbox(12)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(info)
	info.add_child(G.text(EmpireData.money(float(md.get("price", 0))), "title1"))
	var d := String(md.get("desc", ""))
	if d != "":
		info.add_child(G.para(d, "body", G.LABEL))
	info.add_child(G.para(SkyportUI._specs(md), "headline", G.LABEL))
	info.add_child(G.para(SkyportUI._running(md), "subhead"))
	var own := SkyportUI._owned(ui, model)
	if own > 0:
		info.add_child(G.badge("YOU OWN %d" % own, G.GREEN))
	info.add_child(confirm_button("Buy · %s" % EmpireData.money(float(md.get("price", 0))), "Tap again to pay %s" % EmpireData.money(float(md.get("price", 0))), func():
		var err := g.skyport_play.buy_car(model, site) if cls == "car" else g.skyport_play.buy(model)
		if err != "":
			ui.toast(err, "bad")
			return
		Sfx.play("cash", -3.0)
		ui.toast("It's yours: %s" % ({"car": "parked on the forecourt", "heli": "on the helipad – the GPS shows where",
			"plane": "on a stand by the hangars", "boat": "in a berth at the marina"}.get(cls, "")), "good")
		ph.refresh()))
	info.add_child(G.button({"car": "Test drive", "boat": "Test sail"}.get(cls, "Test flight"), func():
		g.skyport_play.start_test(model, site), "gray", "large"))
	var st := g.skyport_play.site(site)
	if not st.is_empty():
		var door: Vector3 = st["door"]
		info.add_child(G.button("Directions to the showroom", func():
			g.set_gps(door, String(st["name"]), {"kind": "place", "id": site})
			ui.toast("Route set: %s" % st["name"], "info"), "tinted", "large", G.BLUE, "gps"))


# -------------------------------------------------------------- city500
static func city500(ph: Phone, body: VBoxContainer) -> void:
	var e := ph.game.empire
	var s := Phone.st("city500")
	var sector := String(s.get("sector", ""))
	var q := String(s.get("q", ""))
	var wide := width(ph) > 1080.0
	var items: Array = [["", "All"]]
	for k in City500.SECTORS:
		items.append([k, City500.sector_name(k)])
	body.add_child(G.pills(items, sector, func(k):
		Phone.st("city500")["sector"] = k
		ph.refresh()))
	var le := G.search("Search companies", q, func(t): Phone.st("city500")["q"] = t)
	le.text_submitted.connect(func(_t): ph.refresh())
	body.add_child(le)
	var split := G.hbox(20)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)
	var lb := G.vbox(10)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.size_flags_stretch_ratio = 1.25
	split.add_child(lb)
	var v := scroller(lb, 14)
	var rank := City500.ranking(e)
	var limit := int(s.get("limit", 60))
	var rows: Array = []
	var shown := 0
	var day := e.day
	for r in rank:
		if r.get("you", false):
			if sector == "" and q == "":
				rows.append(_c500_you(ph, r))
			continue
		var c: Dictionary = r["c"]
		if sector != "" and String(c["sector"]) != sector:
			continue
		if q != "" and not String(c["name"]).to_lower().contains(q.to_lower()):
			continue
		shown += 1
		if shown > limit:
			continue
		rows.append(_c500_row(ph, r, day, wide))
	var yr := City500.your_rank(e)
	var hdr := G.card(20, 6)
	(hdr[1] as VBoxContainer).add_child(G.figure("Your empire's value", City500.money(float(yr["value"])), null, "title2"))
	var ahead: Dictionary = yr["ahead"]
	(hdr[1] as VBoxContainer).add_child(G.para(("#%d of 500" % int(yr["rank"])) + (" · %s to pass %s" % [City500.money(float(ahead["value"]) - float(yr["value"])), ahead["c"]["name"]] if not ahead.is_empty() else "")
		if int(yr["rank"]) > 0 else "%s more to enter the City500" % City500.money(float(yr["gap_500"])), "subhead"))
	v.add_child(hdr[0])
	if sector == "" and q == "":
		v.add_child(_c500_next(ph))
	v.add_child(G.group(rows))
	if shown > limit:
		v.add_child(G.button("Show more (%d)" % (shown - limit), func():
			Phone.st("city500")["limit"] = limit + 100
			ph.refresh(), "gray", "regular"))
	if wide:
		var insp := G.vbox(12)
		insp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		split.add_child(insp)
		var sel := int(s.get("sel", -1))
		if sel < 0 and rank.size() > 0:
			for r in rank:
				if not r.get("you", false):
					sel = int(City500.companies().find(r["c"]))
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
	var idx := City500.companies().find(c)
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
	hv.add_child(G.text("Jules · Build B" if look["body"] == "b" else "Ade · Build A", "footnote", G.LABEL2, "medium"))
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
