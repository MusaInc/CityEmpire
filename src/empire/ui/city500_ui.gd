class_name City500UI
extends RefCounted
## The City500 tab: your standing (rank, value and what it's made of, who
## you chase next), today's market moves, and the table – search, sector
## filter, pages of 25 – with a profile card per company that compares it
## with your empire.

const S = preload("res://src/empire/ui/empire_style.gd")
const PAGE := 25

static var query := ""
static var sector := ""
static var page := 0


static func tab(ui: EmpireUI, v: VBoxContainer) -> void:
	var e := ui.game.empire
	var me := City500.empire_value(e)
	var yr := City500.your_rank(e)
	var body := S.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# ---- left: you
	var left := S.vbox(10)
	left.custom_minimum_size.x = 300
	body.add_child(left)
	var card := _panel(Color(S.AMBER, 0.10), Color(S.AMBER, 0.55))
	var cv := S.vbox(4)
	card.add_child(cv)
	cv.add_child(S.label("YOUR EMPIRE", 13, S.AMBER, "black"))
	var rk := int(yr["rank"])
	var big := S.label("#%d" % rk if rk > 0 else "Unranked", 54 if rk > 0 else 40, S.PAPER, "black")
	cv.add_child(big)
	var mv := City500.you_move(e)
	var sub := "of the City500" if rk > 0 else "%s to enter at #500" % City500.money(float(yr["gap_500"]))
	if rk > 0 and mv != 0:
		sub += "  ·  %s %d this week" % ["▲" if mv > 0 else "▼", absi(mv)]
	cv.add_child(S.label(sub, 15, S.MUTED))
	cv.add_child(_bar(float(yr["value"]), float(yr["ahead"].get("value", yr["floor"])) if rk != 1 else float(yr["value"])))
	var ah: Dictionary = yr["ahead"]
	if rk == 1:
		cv.add_child(S.label("The most valuable company in the city.", 15, S.GREEN, "bold"))
	elif not ah.is_empty():
		var nxt := S.label("Next: #%d %s · %s ahead" % [int(ah["rank"]), ah["c"]["name"], City500.money(float(ah["value"]) - float(yr["value"]))], 15, S.PAPER, "bold")
		nxt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(nxt)
	left.add_child(card)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 6)
	g.add_child(ui._stat("Empire value", City500.money(float(me["value"])), S.GREEN))
	g.add_child(ui._stat("Profit / year", City500.money(float(me["profit_year"])), S.GREEN if float(me["profit_year"]) >= 0.0 else S.RED))
	g.add_child(ui._stat("Revenue / year", City500.money(float(me["revenue_year"]))))
	g.add_child(ui._stat("Assets", City500.money(float(me["assets"]))))
	g.add_child(ui._stat("Debt", City500.money(float(me["debt"])), S.RED if float(me["debt"]) > 0.0 else S.PAPER))
	g.add_child(ui._stat("Reputation", "★ %d" % int(me["reputation"]), S.AMBER))
	left.add_child(g)
	var how := S.label("Valued like every company here: what you own at book value, less debt, plus %.1f years of your trading profit (last 7 days). Moving cash around adds nothing – profit does." % City500.EARN_MULTIPLE, 13, S.MUTED)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(how)
	var news := S.vbox(4)
	news.add_child(S.label("MARKET TODAY", 13, S.AMBER, "black"))
	for h in City500.headlines(e.day).slice(0, 3):
		var l := S.label(("▲ " if h[1] == "good" else ("▼ " if h[1] in ["bad", "warn"] else "• ")) + String(h[0]), 14,
			S.GREEN if h[1] == "good" else (S.RED if h[1] in ["bad", "warn"] else S.PAPER))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		news.add_child(l)
	left.add_child(news)
	# ---- right: the table
	var right := S.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 8)
	tools.add_theme_constant_override("v_separation", 6)
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var q := LineEdit.new()
	q.placeholder_text = "Search companies"
	q.text = query
	q.custom_minimum_size = Vector2(230, 44)
	q.add_theme_font_override("font", S.font("semibold"))
	q.add_theme_font_size_override("font_size", 17)
	q.text_submitted.connect(func(t):
		query = t
		page = 0
		ui.open_phone("city500"))
	tools.add_child(q)
	tools.add_child(S.button("Go", func():
		query = q.text
		page = 0
		ui.open_phone("city500"), false, 60))
	if query != "" or sector != "":
		tools.add_child(S.button("Clear", func():
			query = ""
			sector = ""
			page = 0
			ui.open_phone("city500"), false, 80))
	tools.add_child(S.spacer())
	tools.add_child(S.button("Find me", func():
		query = ""
		sector = ""
		page = maxi(0, (int(yr["position"]) - 1) / PAGE) if rk > 0 else (City500.N - 1) / PAGE
		ui.open_phone("city500"), false, 110))
	right.add_child(tools)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	chips.add_child(_chip("All", sector == "", func(): sector = ""; page = 0; ui.open_phone("city500")))
	for s in City500.SECTORS:
		var sk := String(s)
		chips.add_child(_chip(City500.sector_name(sk).get_slice(" ", 0), sector == sk, func(): sector = sk; page = 0; ui.open_phone("city500")))
	right.add_child(chips)
	var rows: Array = City500.ranking(e).filter(func(r):
		if r.get("you", false):
			return query == "" and sector == ""
		var c: Dictionary = r["c"]
		return (sector == "" or c["sector"] == sector) and (query == "" or String(c["name"]).to_lower().contains(query.to_lower())))
	var pages := maxi(1, ceili(float(rows.size()) / PAGE))
	page = clampi(page, 0, pages - 1)
	var list := S.vbox(4)
	if rows.is_empty():
		list.add_child(S.label("No company matches \"%s\"." % query, 16, S.MUTED))
	for r in rows.slice(page * PAGE, (page + 1) * PAGE):
		list.add_child(_row(ui, r))
	if rk == 0 and query == "" and sector == "" and page == pages - 1:
		list.add_child(_row(ui, {"you": true, "rank": int(yr["position"]), "value": float(yr["value"]), "move": 0}))
	right.add_child(ui._scroll(list, 300))
	var pg := S.hbox(8)
	var prev := S.button("‹ Prev", func(): page -= 1; ui.open_phone("city500"), false, 100)
	prev.disabled = page == 0
	pg.add_child(prev)
	pg.add_child(S.label("Page %d of %d · %d companies" % [page + 1, pages, rows.size()], 14, S.MUTED))
	var nx := S.button("Next ›", func(): page += 1; ui.open_phone("city500"), false, 100)
	nx.disabled = page >= pages - 1
	pg.add_child(nx)
	right.add_child(pg)


static func _row(ui: EmpireUI, r: Dictionary) -> Control:
	var you: bool = r.get("you", false)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(S.AMBER, 0.16) if you else Color(1, 1, 1, 0.035)
	sb.set_corner_radius_all(10)
	if you:
		sb.border_color = S.AMBER
		sb.set_border_width_all(1)
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = Color(1, 1, 1, 0.08) if not you else Color(S.AMBER, 0.22)
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	var h := S.hbox(10)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var rank := int(r["rank"])
	h.add_child(_cell("#%d" % rank, 64, 18, S.AMBER if rank <= 10 or you else S.PAPER, "black"))
	var mv := int(r.get("move", 0))
	h.add_child(_cell(("▲%d" % mv) if mv > 0 else (("▼%d" % -mv) if mv < 0 else "–"), 52, 13, S.GREEN if mv > 0 else (S.RED if mv < 0 else S.MUTED), "bold"))
	if you:
		var nm := String(ui.game.empire.brand.get("name", ""))
		h.add_child(_cell((nm if nm != "" else "Your empire") + "  (you)", 0, 17, S.AMBER, "black", true))
		h.add_child(_cell("Your empire", 150, 13, S.MUTED))
	else:
		var c: Dictionary = r["c"]
		h.add_child(_cell(String(c["name"]), 0, 17, S.PAPER, "bold", true))
		var sc := _cell(City500.sector_name(c["sector"]), 150, 13, City500.sector_colour(c["sector"]), "bold")
		h.add_child(sc)
	h.add_child(_cell(City500.money(float(r["value"])), 140, 16, S.PAPER, "bold"))
	b.pressed.connect(func():
		if Time.get_ticks_msec() < S.tap_block_until:
			return
		Sfx.play("click", -12.0)
		if you:
			ui.open_phone("bank")
		else:
			profile(ui, r["c"]))
	return b


static func _cell(t: String, w: float, size: int, col: Color, weight := "semibold", expand := false) -> Label:
	var l := S.label(t, size, col, weight)
	l.custom_minimum_size.x = w
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func _chip(t: String, on: bool, cb: Callable) -> Button:
	var b := S.chip_button(t, on, cb)
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 14)
	return b


static func _panel(bg: Color, border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(16)
	for m in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + m, 16)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Progress toward the next company (or #500).
static func _bar(mine: float, target: float) -> Control:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(320, 10)
	pb.max_value = 1.0
	pb.value = clampf(mine / maxf(target, 1.0), 0.0, 1.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = S.AMBER
	fg.set_corner_radius_all(5)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


## A company's card: what it is, its numbers over 30 days, and side by side
## with you.
static func profile(ui: EmpireUI, c: Dictionary) -> void:
	var e := ui.game.empire
	var p := City500.profile(c, e.day)
	var rank := 0
	for r in City500.ranking(e):
		if not r.get("you", false) and int(r["c"]["i"]) == int(c["i"]):
			rank = int(r["rank"])
			break
	var v := ui._open(String(c["name"]), 900, 600)
	var head := S.hbox(10)
	head.add_child(S.chip(City500.sector_name(c["sector"]), City500.sector_colour(c["sector"])))
	head.add_child(S.label(("#%d in the City500" % rank) if rank > 0 else "Outside the City500 today", 17, S.AMBER, "black"))
	head.add_child(S.label("·  Founded %d  ·  %s  ·  CEO %s" % [int(c["founded"]), c["owner"], c["ceo"]], 15, S.MUTED))
	v.add_child(head)
	var ops := S.label("Operates %d %s with %s staff." % [int(p["sites"]), String(p["ops"]), _n(int(p["staff"]))], 16, S.PAPER)
	v.add_child(ops)
	var h := S.hbox(18)
	var hist := City500.history(c, e.day, 30)
	var chg := (float(hist[-1]) / float(hist[0]) - 1.0) * 100.0
	var cv := S.vbox(4)
	cv.add_child(S.label("VALUE · 30 DAYS  %s%.1f%%" % ["+" if chg >= 0.0 else "", chg], 13, S.GREEN if chg >= 0.0 else S.RED, "black"))
	cv.add_child(EmpireWidgets.Spark.new(hist, Vector2(330, 120)))
	h.add_child(cv)
	# Side by side.
	var me := City500.empire_value(e)
	var t := GridContainer.new()
	t.columns = 3
	t.add_theme_constant_override("h_separation", 26)
	t.add_theme_constant_override("v_separation", 5)
	t.add_child(S.label("", 13))
	t.add_child(S.label(String(c["name"]).to_upper(), 12, S.MUTED, "black"))
	t.add_child(S.label("YOU", 12, S.AMBER, "black"))
	for kv in [["Value", "value", "value"], ["Revenue / yr", "revenue", "revenue_year"], ["Profit / yr", "profit", "profit_year"],
			["Assets", "assets", "assets"], ["Debt", "debt", "debt"]]:
		t.add_child(S.label(String(kv[0]), 15, S.MUTED))
		t.add_child(S.label(City500.money(float(p[kv[1]])), 16, S.PAPER, "bold"))
		t.add_child(S.label(City500.money(float(me[kv[2]])), 16, S.AMBER, "bold"))
	t.add_child(S.label("Staff", 15, S.MUTED))
	t.add_child(S.label(_n(int(p["staff"])), 16, S.PAPER, "bold"))
	t.add_child(S.label(_n(int(me["staff"])), 16, S.AMBER, "bold"))
	t.add_child(S.label("Reputation", 15, S.MUTED))
	t.add_child(S.label("★ %d" % int(c["rep"]), 16, S.PAPER, "bold"))
	t.add_child(S.label("★ %d" % int(me["reputation"]), 16, S.AMBER, "bold"))
	h.add_child(t)
	v.add_child(h)
	var ahead := float(p["value"]) > float(me["value"])
	var why := S.label(("Why it's ahead: " + City500.why_ahead(e, c)) if ahead else
		"You're worth %s more than %s." % [City500.money(float(me["value"]) - float(p["value"])), c["name"]], 16, S.PAPER if ahead else S.GREEN, "bold")
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.custom_minimum_size.x = 840
	v.add_child(why)
	if ahead:
		var gap := float(p["value"]) - float(me["value"])
		var days := gap / maxf(float(me["profit_day"]) * 365.0 * City500.EARN_MULTIPLE / 30.0 + float(me["profit_day"]), 1.0)
		var tip := S.label("To pass it: every extra £1 of daily profit adds about %s to your value. %s" % [
			City500.money(365.0 * City500.EARN_MULTIPLE), ("At today's pace that's roughly %d days of growth." % int(days)) if float(me["profit_day"]) > 0.0 and days < 3650 else "Get a shop trading at a profit first."], 14, S.MUTED)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size.x = 840
		v.add_child(tip)
	var acts := S.hbox(10)
	acts.add_child(S.button("‹ City500", func(): ui.open_phone("city500"), true, 160))
	v.add_child(acts)


static func _n(x: int) -> String:
	var s := str(x)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
