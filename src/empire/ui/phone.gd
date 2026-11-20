class_name Phone
extends Control
## The phone (2026-11-20 redesign): one persistent shell over the paused,
## blurred city, in the Glass language.
##
##   regular (wide: iPad, iPhone landscape)  a floating glass sidebar with
##       every section and your recents; the section fills the rest; some
##       sections split into a list and an inspector when there's room.
##   compact (portrait iPhone, narrow)       full-width pages, a floating
##       glass tab bar (Empire · Map · Market · City500 · More).
##
## Navigation keeps its context: every section has its own page stack,
## each page its scroll positions, and sections keep their filters and
## selection (static: they last until you quit). Refreshing a page after an
## action rebuilds it in place and puts every list back where it was – the
## old phone rebuilt from scratch and jumped to the top on every tap.
## Detail windows open as sheets OVER the page (the page underneath is
## untouched); closing one returns to exactly where you were.

const SECTIONS := [
	["home", "Empire", "chart", "ACCENT"], ["map", "Map", "map", "BLUE"], ["market", "Marketplace", "bag", "PINK"],
	["city500", "City500", "star", "ORANGE"], ["vehicles", "Garage", "car", "TEAL"], ["property", "Property", "property", "GREEN"],
	["you", "Character", "person", "PURPLE"], ["businesses", "Businesses", "businesses", "ORANGE"], ["bank", "Finances", "bank", "GREEN"],
	["explore", "Explore", "compass", "BLUE"], ["company", "Corporate", "company", "PURPLE"], ["city", "City", "city", "TEAL"],
	["goals", "Goals", "goals", "ORANGE"], ["game", "Game", "game", "LABEL2"],
]
const TABS := ["home", "map", "market", "city500", "more"]

## Session state (survives closing the phone).
static var section := "home"
static var stacks := {}        # section -> [{page, args, title}]
static var scroll_mem := {}    # "section|page|args" -> [[v, h], …] per scroll container (tree order)
static var state := {}         # section -> Dictionary (filters, selection, search)
static var recents: Array = [] # [{title, sub, section, page, args, icon}]

var ui: EmpireUI
var game: EmpireGame
var compact := false
var _page_host: Control        # where the page goes
var _page: Control
var _sheet_layer: Control
var _sheet: Control = null
var _title_l: Label
var _back_btn: Control
var _built_size := Vector2.ZERO
var _was_hud := false
var _was_touch := false


static func st(sec: String) -> Dictionary:
	if not state.has(sec):
		state[sec] = {}
	return state[sec]


static func title_of(sec: String) -> String:
	for s in SECTIONS:
		if s[0] == sec:
			return s[1]
	return "More" if sec == "more" else sec.capitalize()


static func color_of(sec: String) -> Color:
	for s in SECTIONS:
		if s[0] == sec:
			return Glass.named(String(s[3]))
	return Glass.LABEL2


static func icon_of(sec: String) -> String:
	for s in SECTIONS:
		if s[0] == sec:
			return s[2]
	return "grid"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_hud = ui.hud.visible
	_was_touch = ui.touch.visible
	ui.hud.visible = false
	ui.touch.visible = false
	get_viewport().size_changed.connect(_on_resize)
	_build()


func _exit_tree() -> void:
	save_scroll()
	if is_instance_valid(ui):
		ui.hud.visible = _was_hud
		ui.touch.visible = _was_touch
	# (The HUD and the windows opened in the street are always dark glass:
	# back to the dark palette for anything built from here on.)
	Glass.set_dark(true)


## (WORLDSTATE is landscape-only: the phone never turns upright. The
## compact layout below is only for narrow windows.)
func _on_resize() -> void:
	if get_viewport_rect().size.distance_to(_built_size) > 2.0:
		save_scroll()
		_build.call_deferred()


# ---------------------------------------------------------------- shell
func _build() -> void:
	for c in get_children():
		c.queue_free()
	_sheet = null
	var vs := get_viewport_rect().size
	_built_size = vs
	compact = vs.x < 1100.0
	Glass.set_dark(Glass.want_dark(game.empire.minute if game and game.empire else -1.0))
	theme = EmpireStyle.theme()
	var safe := _safe_insets(vs)
	# The city behind, blurred and tinted: the app's backdrop.
	var back := Glass.surface(0.0, 0.0, Glass.BG, false)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	var top := 18.0 + safe.y
	if compact:
		_page_host = Control.new()
		_page_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_page_host.offset_left = 22 + safe.x
		_page_host.offset_right = -22 - safe.z
		_page_host.offset_top = top
		_page_host.offset_bottom = 0
		add_child(_page_host)
		_tab_bar(vs, safe)
	else:
		var sw := 296.0
		var side := Glass.surface(30.0, 0.0)
		side.position = Vector2(16 + safe.x, 16 + safe.y)
		side.size = Vector2(sw, vs.y - 32 - safe.y - safe.w)
		side.custom_minimum_size = side.size
		add_child(side)
		side.add_child(_sidebar())
		_page_host = Control.new()
		_page_host.position = Vector2(16 + safe.x + sw + 26, top)
		_page_host.size = Vector2(vs.x - _page_host.position.x - 24 - safe.z, vs.y - top - 12 - safe.w)
		add_child(_page_host)
	_sheet_layer = Control.new()
	_sheet_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sheet_layer)
	_show_page(false)


## Safe-area insets in canvas px (left, top, right, bottom): notch,
## Dynamic Island, home indicator.
func _safe_insets(vs: Vector2) -> Vector4:
	var sr := DisplayServer.get_display_safe_area()
	var ss := Vector2(DisplayServer.screen_get_size())
	if ss.x <= 0 or sr.size.x <= 0 or not OS.get_name() in ["iOS", "Android"]:
		return Vector4.ZERO
	var k := vs.x / ss.x
	return Vector4(sr.position.x * k, sr.position.y * k, (ss.x - sr.end.x) * k, (ss.y - sr.end.y) * k)


func _sidebar() -> Control:
	var e := game.empire
	var v := Glass.vbox(2)
	var m := Glass.margin(v, 14, 18, 14, 14)
	# Who and how much: your brand mark, name and spendable money.
	var who := Glass.hbox(12)
	who.add_child(ui._brand_badge(46))
	var wv := Glass.vbox(-2)
	wv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := String(e.brand.get("name", ""))
	wv.add_child(Glass.line(nm if nm != "" else "Your empire", "headline"))
	wv.add_child(Glass.line(EmpireData.money(e.personal_cash + maxf(e.company_cash, 0.0)), "subhead", Glass.LABEL2))
	who.add_child(wv)
	v.add_child(Glass.margin(who, 6, 0, 0, 12))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := Glass.vbox(2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	for s in SECTIONS:
		list.add_child(_side_item(String(s[0])))
	if not recents.is_empty():
		list.add_child(Glass.gap(14))
		list.add_child(Glass.margin(Glass.text("Recents", "footnote", Glass.LABEL2, "semibold"), 12, 0, 0, 4))
		for r in recents.slice(0, 4):
			var rd: Dictionary = r
			list.add_child(_recent_item(rd))
	v.add_child(Glass.gap(8))
	var back := Glass.button("Back to the city", func(): ui.close_panel(true), "gray", "regular", null, "back")
	v.add_child(back)
	return m


func _side_item(key: String) -> Button:
	var on := key == section
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 50)
	var n := Glass.box(Glass.FILL2 if on else Color(0, 0, 0, 0), 14, 0)
	n.content_margin_left = 58
	var p := Glass.box(Glass.FILL, 14, 0)
	p.content_margin_left = 58
	for s in ["normal", "focus", "hover"]:
		b.add_theme_stylebox_override(s, n)
	b.add_theme_stylebox_override("pressed", p)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = title_of(key)
	b.add_theme_font_override("font", Glass.font("semibold" if on else "medium"))
	b.add_theme_font_size_override("font_size", 21)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, Glass.LABEL)
	var ic := Glass.Symbol.new(icon_of(key), color_of(key) if not (key == "home") else Glass.ACCENT_TEXT, 26)
	ic.position = Vector2(18, 12)
	b.add_child(ic)
	Glass.feedback(b, func(): go(key))
	return b


func _recent_item(r: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	var n := Glass.box(Color(0, 0, 0, 0), 12, 0)
	n.content_margin_left = 58
	var p := Glass.box(Glass.FILL, 12, 0)
	p.content_margin_left = 58
	for s in ["normal", "focus", "hover"]:
		b.add_theme_stylebox_override(s, n)
	b.add_theme_stylebox_override("pressed", p)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = String(r["title"])
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_override("font", Glass.font("regular"))
	b.add_theme_font_size_override("font_size", 19)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, Glass.LABEL2)
	var ic := Glass.Symbol.new("clock", Glass.LABEL3, 20)
	ic.position = Vector2(22, 12)
	b.add_child(ic)
	Glass.feedback(b, func(): open_recent(r))
	return b


func _tab_bar(vs: Vector2, safe: Vector4) -> void:
	var bar := Glass.surface(-1.0, 6.0)
	var w := minf(vs.x - 40.0, 640.0)
	var h := 84.0
	bar.position = Vector2((vs.x - w) * 0.5, vs.y - h - 16 - maxf(safe.w - 8.0, 0.0))
	bar.size = Vector2(w, h)
	bar.custom_minimum_size = bar.size
	add_child(bar)
	var row := Glass.hbox(0)
	bar.add_child(row)
	var cur := section if section in TABS else "more"
	for key: String in TABS:
		var on := key == cur
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := Glass.box(Glass.FILL2 if on else Color(0, 0, 0, 0), 36, 0)
		for s in ["normal", "focus", "hover", "pressed"]:
			b.add_theme_stylebox_override(s, n)
		var col := Glass.ACCENT_TEXT if on else Glass.LABEL
		var cv := Glass.vbox(2)
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var ic := Glass.Symbol.new("grid" if key == "more" else icon_of(key), col, 30)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(ic)
		var lb := Glass.text("More" if key == "more" else ("Market" if key == "market" else title_of(key)), "caption2", col, "semibold" if on else "medium")
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(lb)
		b.add_child(cv)
		Glass.feedback(b, func(): go(key))
		row.add_child(b)


# ---------------------------------------------------------------- pages
func _stack(sec: String) -> Array:
	if not stacks.has(sec) or (stacks[sec] as Array).is_empty():
		stacks[sec] = [{"page": "root", "args": {}, "title": title_of(sec)}]
	return stacks[sec]


func _page_key(sec := "") -> String:
	var s := sec if sec != "" else section
	var top: Dictionary = _stack(s)[-1]
	return "%s|%s|%s" % [s, top["page"], JSON.stringify(top["args"])]


## Switch section (its own stack and scroll come back with it); the same
## section again = refresh in place (scroll kept).
func go(sec: String, focus := {}) -> void:
	dismiss_sheet(false)
	if sec == section and focus.is_empty():
		# Tapping the current tab again pops to its root (iOS), else refresh.
		if (_stack(sec) as Array).size() > 1:
			save_scroll()
			stacks[sec] = [_stack(sec)[0]]
			_show_page(true)
		else:
			refresh()
		return
	save_scroll()
	section = sec
	if not focus.is_empty():
		st(sec)["focus"] = focus
	if compact or true:
		_build()   # (sidebar/tab highlight follow; pages restore their scroll)
	_show_page(true)


## Push a detail page within the section (back returns, scroll intact).
func push(page: String, args: Dictionary, title: String, sub := "", icon := "") -> void:
	dismiss_sheet(false)
	save_scroll()
	_stack(section).append({"page": page, "args": args, "title": title})
	_remember(title, sub, section, page, args, icon)
	_show_page(true)


func back() -> void:
	var s := _stack(section)
	if s.size() > 1:
		save_scroll()
		s.pop_back()
		_show_page(true)


func open_recent(r: Dictionary) -> void:
	save_scroll()
	section = String(r["section"])
	var s := _stack(section)
	stacks[section] = [s[0], {"page": r["page"], "args": r["args"], "title": r["title"]}] if String(r["page"]) != "root" else [s[0]]
	_build()


func _remember(title: String, sub: String, sec: String, page: String, args: Dictionary, icon: String) -> void:
	for i in range(recents.size() - 1, -1, -1):
		if recents[i]["title"] == title and recents[i]["section"] == sec:
			recents.remove_at(i)
	recents.push_front({"title": title, "sub": sub, "section": sec, "page": page, "args": args, "icon": icon})
	if recents.size() > 8:
		recents.resize(8)


## Rebuild the current page in place, every list where it was.
func refresh() -> void:
	save_scroll()
	_show_page(false)


func _show_page(animate: bool) -> void:
	if _page and is_instance_valid(_page):
		_page.queue_free()
	var top: Dictionary = _stack(section)[-1]
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page = page
	_page_host.add_child(page)
	# Header: back · large title · close.
	var head := Glass.hbox(12)
	var depth := (_stack(section) as Array).size()
	if depth > 1:
		head.add_child(Glass.icon_button("back", back, true, 52))
	var tv := Glass.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_l = Glass.line(String(top["title"]) if depth > 1 else title_of(section), "title1" if depth > 1 else "large")
	tv.add_child(_title_l)
	var sub := _subtitle()
	if sub != "" and depth == 1:
		tv.add_child(Glass.line(sub, "subhead", Glass.LABEL2))
	head.add_child(tv)
	if compact:
		head.add_child(Glass.icon_button("close", func(): ui.close_panel(true), true, 52))
	page.add_child(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	if compact:
		page.add_child(Glass.gap(96 + _safe_insets(get_viewport_rect().size).w))   # (clear of the tab bar)
	PhonePages.build(self, section, String(top["page"]), top["args"], body)
	# Lists come back where they were (laid out first: hidden until then).
	var key := _page_key()
	var saved: Array = scroll_mem.get(key, [])
	if saved.any(func(x): return int(x[0]) != 0 or int(x[1]) != 0):
		page.modulate.a = 0.0   # (hidden for the two frames layout takes: no jump)
	elif animate:
		page.modulate.a = 0.55
	_restore.call_deferred(page, key, animate)


func _restore(page: Control, key: String, animate: bool) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(page):
		return
	var saved: Array = scroll_mem.get(key, [])
	var scs := _scrolls(page)
	for i in mini(saved.size(), scs.size()):
		scs[i].scroll_vertical = int(saved[i][0])
		scs[i].scroll_horizontal = int(saved[i][1])
	if animate:
		page.position.x += 24.0
		var tw := page.create_tween().set_parallel()
		tw.tween_property(page, "modulate:a", 1.0, 0.18)
		tw.tween_property(page, "position:x", page.position.x - 24.0, 0.32).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	else:
		page.modulate.a = 1.0


func _scrolls(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is ScrollContainer:
			out.append(c)
		out.append_array(_scrolls(c))
	return out


func save_scroll() -> void:
	if _page == null or not is_instance_valid(_page) or _page.is_queued_for_deletion():
		return
	var arr: Array = []
	for sc: ScrollContainer in _scrolls(_page):
		arr.append([sc.scroll_vertical, sc.scroll_horizontal])
	scroll_mem[_page_key()] = arr


func _subtitle() -> String:
	var e := game.empire
	match section:
		"home":
			return "Day %d · %s %s" % [e.day, e.weekday(), e.clock_text()]
		"market":
			return "Businesses, homes, cars and clothes – buy in a tap"
		"city500":
			var yr := City500.your_rank(e)
			return ("You're #%d of 500" % int(yr["rank"])) if int(yr["rank"]) > 0 else "%s to enter the list" % City500.money(float(yr["gap_500"]))
		"vehicles":
			return "%d vehicle%s" % [e.vehicles.size(), "" if e.vehicles.size() == 1 else "s"]
		"property":
			return "Shops to let, businesses for sale, homes and investments"
		"map":
			return ""
	return String(EmpireUI.PHONE_SUB.get(section, ""))


# ---------------------------------------------------------------- sheets
## A detail window over the page (the page stays as it is). Returns the
## content box, like EmpireUI._open did. compact: a bottom sheet with a
## grabber (drag down to close); regular: a centred form sheet.
func present_sheet(title: String, w: float, h: float) -> VBoxContainer:
	dismiss_sheet(false)
	var vs := get_viewport_rect().size
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet_layer.add_child(layer)
	_sheet = layer
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed or ev is InputEventScreenTouch and ev.pressed:
			dismiss_sheet())
	layer.add_child(dim)
	var sw := minf(maxf(w * 1.12, 640.0), vs.x - 80.0) if not compact else vs.x
	var sh := minf(h * 1.15 + 90.0, vs.y - (40.0 if not compact else 70.0))
	var sheet := PanelContainer.new()
	var sb := Glass.box(Glass.CARD if Glass.dark else Color(0.97, 0.97, 0.98, 1.0), 34, 0)
	if compact:
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 30
	sheet.add_theme_stylebox_override("panel", sb)
	sheet.size = Vector2(sw, sh)
	sheet.custom_minimum_size = Vector2(sw, sh)
	var rest := Vector2((vs.x - sw) * 0.5, (vs.y - sh) * 0.5) if not compact else Vector2(0, vs.y - sh)
	sheet.position = rest + Vector2(0, vs.y * 0.4 if compact else 40.0)
	sheet.modulate.a = 0.0 if not compact else 1.0
	layer.add_child(sheet)
	var v := Glass.vbox(14)
	sheet.add_child(Glass.margin(v, 26, 12 if compact else 22, 26, 22))
	if compact:
		var grab := Panel.new()
		grab.custom_minimum_size = Vector2(56, 6)
		grab.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grab.add_theme_stylebox_override("panel", Glass.box(Glass.LABEL3, 3, 0))
		v.add_child(grab)
		_drag_to_close(sheet, rest)
	var head := Glass.hbox(10)
	head.add_child(Glass.line(title, "title2"))
	head.add_child(Glass.icon_button("close", func(): dismiss_sheet(), false, 48))
	v.add_child(head)
	# Older detail screens were laid out for a wide panel: they scroll
	# rather than clip when the sheet is narrower.
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	v.add_child(sc)
	var content := Glass.vbox(14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	var tw := sheet.create_tween().set_parallel()
	tw.tween_property(dim, "color:a", 0.28, 0.25)
	tw.tween_property(sheet, "position", rest, 0.45).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tw.tween_property(sheet, "modulate:a", 1.0, 0.15)
	return content


func _drag_to_close(sheet: Control, rest: Vector2) -> void:
	var drag := {"on": false, "y0": 0.0}
	sheet.gui_input.connect(func(ev):
		if (ev is InputEventScreenTouch or ev is InputEventMouseButton) and ev.pressed and ev.position.y < 90.0:
			drag["on"] = true
			drag["y0"] = ev.position.y
		elif (ev is InputEventScreenTouch or ev is InputEventMouseButton) and not ev.pressed and drag["on"]:
			drag["on"] = false
			if sheet.position.y - rest.y > 140.0:
				dismiss_sheet()
			else:
				sheet.create_tween().tween_property(sheet, "position", rest, 0.35).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
		elif (ev is InputEventScreenDrag or ev is InputEventMouseMotion) and drag["on"]:
			sheet.position.y = maxf(rest.y, sheet.position.y + ev.relative.y))


func has_sheet() -> bool:
	return _sheet != null and is_instance_valid(_sheet)


## Close the sheet; the page under it refreshes in place (what you did in
## the sheet shows) with its scroll positions kept.
func dismiss_sheet(refresh_page := true) -> void:
	if not has_sheet():
		return
	var s := _sheet
	_sheet = null
	ui._panel = self
	var tw := s.create_tween().set_parallel()
	tw.tween_property(s, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(s.queue_free)
	if refresh_page:
		refresh()
