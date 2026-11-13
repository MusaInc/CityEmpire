class_name EmpireUI
extends CanvasLayer
## Everything on screen: the HUD (kept minimal – money, clock, the next
## objective with a GPS arrow, the context prompt, what you're carrying, the
## shop you're in), toasts and floating numbers, and the panels: title,
## wholesaler, shop management (overview / prices / stock / staff /
## upgrades / reports), property, stockroom, phone (businesses, map, bank,
## vehicles, goals, game) and the end-of-day report.
## Panels pause the world while open.

const S = preload("res://src/empire/ui/empire_style.gd")

var game: EmpireGame
var hud: Control
var touch: EmpireTouch
var _money: Label
var _company: Label
var _clock: Label
var _speed: Label
var _obj_title: Label
var _obj: Label
var _gps: Label
var _arrow: Control
var _prompt: PanelContainer
var _prompt_l: Label
var _prompt_key: Label
var _carry: Label
var _strip: Label
var _strip_panel: PanelContainer
var _weather_l: Label
var _drive: Label
var _toasts: VBoxContainer
var _floats: Control
var _panel_root: Control
var _panel: PanelContainer
var _title_root: Control
var _tab := ""
var _manage_biz: Business
var _cart := {}
var _cart_unit := {}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = S.theme()
	add_child(root)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	root.add_child(hud)
	_build_hud()
	touch = EmpireTouch.new()
	touch.ui = self
	touch.visible = false
	root.add_child(touch)
	_floats = Control.new()
	_floats.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_floats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_floats)
	_panel_root = Control.new()
	_panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel_root)
	_title_root = Control.new()
	_title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_title_root)


# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	# Money (top left).
	var m := _hud_panel(Vector2(18, 16), Vector2(250, 78))
	var mv := S.vbox(0)
	m.add_child(mv)
	_money = S.label("£0", 30, S.PAPER, "black")
	_company = S.label("Company £0", 16, S.MUTED)
	mv.add_child(_money)
	mv.add_child(_company)
	# Clock (top centre).
	var c := _hud_panel(Vector2(0, 16), Vector2(270, 56))
	_anchor(c, 0.5, 0.0, Vector2(-135, 16), Vector2(270, 56))
	var ch := S.hbox(10)
	c.add_child(ch)
	_clock = S.label("Mon 07:30", 24, S.PAPER, "bold")
	_speed = S.label("", 18, S.AMBER, "black")
	ch.add_child(_clock)
	ch.add_child(_speed)
	_weather_l = S.label("", 16, S.MUTED, "bold")
	ch.add_child(_weather_l)
	# The shop you're in (under the money).
	_strip_panel = _hud_panel(Vector2(18, 104), Vector2(250, 50))
	_strip = S.label("", 15, S.PAPER)
	_strip_panel.add_child(_strip)
	# Objective (top right).
	var o := _hud_panel(Vector2(0, 16), Vector2(360, 82))
	_anchor(o, 1.0, 0.0, Vector2(-442, 16), Vector2(360, 82))
	var ov := S.vbox(2)
	o.add_child(ov)
	_obj_title = S.label("OBJECTIVE", 13, S.AMBER, "black")
	_obj = S.label("", 17, S.PAPER)
	_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj.custom_minimum_size.x = 330
	_gps = S.label("", 15, S.MUTED)
	ov.add_child(_obj_title)
	ov.add_child(_obj)
	ov.add_child(_gps)
	_arrow = _Arrow.new()
	_anchor(_arrow, 0.5, 0.0, Vector2(-22, 112), Vector2(44, 44))
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_arrow)
	# Phone button (top right corner).
	var phone := S.button("☰", func(): open_phone(), false, 52)
	_anchor(phone, 1.0, 0.0, Vector2(-70, 16), Vector2(52, 52))
	phone.add_theme_font_size_override("font_size", 26)
	hud.add_child(phone)
	# Toasts (right, under the objective).
	_toasts = S.vbox(8)
	_anchor(_toasts, 1.0, 0.0, Vector2(-442, 112), Vector2(390, 300))
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_toasts)
	# Prompt (bottom centre).
	_prompt = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(S.INK, 0.86)
	psb.set_corner_radius_all(26)
	psb.content_margin_left = 10
	psb.content_margin_right = 22
	psb.content_margin_top = 8
	psb.content_margin_bottom = 8
	_prompt.add_theme_stylebox_override("panel", psb)
	_anchor(_prompt, 0.5, 1.0, Vector2(-200, -150), Vector2(400, 50))
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ph := S.hbox(12)
	_prompt.add_child(ph)
	_prompt_key = S.label(" E ", 18, S.INK, "black")
	var kb := StyleBoxFlat.new()
	kb.bg_color = S.AMBER
	kb.set_corner_radius_all(14)
	kb.content_margin_left = 8
	kb.content_margin_right = 8
	_prompt_key.add_theme_stylebox_override("normal", kb)
	_prompt_l = S.label("", 20, S.PAPER, "bold")
	ph.add_child(_prompt_key)
	ph.add_child(_prompt_l)
	hud.add_child(_prompt)
	# Carrying (bottom left) and driving readout.
	_carry = S.label("", 17, S.PAPER, "bold")
	_anchor(_carry, 0.0, 1.0, Vector2(24, -64), Vector2(900, 30))
	_carry.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_carry.add_theme_constant_override("outline_size", 6)
	hud.add_child(_carry)
	_drive = S.label("", 30, S.PAPER, "black")
	_anchor(_drive, 0.5, 1.0, Vector2(-300, -80), Vector2(600, 40))
	_drive.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drive.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_drive.add_theme_constant_override("outline_size", 8)
	hud.add_child(_drive)


## Anchors a control at (ax, ay) of the screen with its top-left `off` from
## that point and the given size (stays put on any aspect ratio).
static func _anchor(c: Control, ax: float, ay: float, off: Vector2, size: Vector2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = off.x
	c.offset_top = off.y
	c.offset_right = off.x + size.x
	c.offset_bottom = off.y + size.y


func _hud_panel(pos: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(S.INK, 0.78)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.custom_minimum_size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(p)
	return p


func show_hud() -> void:
	_title_root.visible = false
	for c in _title_root.get_children():
		c.queue_free()
	hud.visible = true
	touch.visible = DisplayServer.is_touchscreen_available() or game.args.has("touch")
	update_hud()


func update_hud() -> void:
	if game == null or game.empire == null or not hud.visible:
		return
	var e := game.empire
	_money.text = EmpireData.money(e.personal_cash)
	_company.text = "Company %s" % EmpireData.money(e.company_cash)
	_company.add_theme_color_override("font_color", S.RED if e.company_cash < 0.0 else S.MUTED)
	_clock.text = "%s %s" % [e.weekday(), e.clock_text()]
	_weather_l.text = String(CityLife.weather_def(e.weather).get("name", ""))
	_speed.text = "×%d" % int(game.time_scale) if game.time_scale > 1.0 and game.floor == null and game.driving == "" else ""
	var ob := game.objective()
	_obj.text = String(ob[0])
	var tgt: Vector3 = ob[1]
	if tgt == Vector3.INF:
		tgt = game.gps_target()
		if tgt != Vector3.INF:
			_obj.text += "\nGPS: " + String(e.flags.get("gps_label", ""))
	var me := game.player.global_position
	if tgt != Vector3.INF and Vector2(me.x, me.z).distance_to(Vector2(tgt.x, tgt.z)) > 8.0:
		var d := Vector2(me.x, me.z).distance_to(Vector2(tgt.x, tgt.z))
		_gps.text = "%d m" % int(d) if d < 1000.0 else "%.1f km" % (d / 1000.0)
		var view := game.camera.view_yaw() if game.driving == "" else game.chase.view_yaw()
		var to := atan2(-(tgt.x - me.x), -(tgt.z - me.z))
		(_arrow as _Arrow).angle = wrapf(view - to, -PI, PI)
		_arrow.visible = true
	else:
		_gps.text = ""
		_arrow.visible = false
	_arrow.queue_redraw()
	# Prompt.
	var pr := game.spot_prompt()
	_prompt.visible = String(pr[0]) != "" and _panel == null
	_prompt_l.text = String(pr[0])
	_prompt_l.add_theme_color_override("font_color", S.PAPER if pr[1] else Color(S.PAPER, 0.5))
	_prompt_key.visible = pr[1] and not touch.visible
	_prompt.offset_left = -_prompt.size.x * 0.5
	_prompt.offset_right = _prompt.size.x * 0.5
	touch.action_text = String(pr[0]) if pr[1] else ""
	# Carrying.
	var c := e.carried
	if c.is_empty():
		_carry.text = ""
	else:
		var names: Array = []
		for pid in c.units:
			names.append("%s ×%d" % [EmpireData.product(pid)["name"], c.qty(pid)])
		_carry.text = "CARRYING %d/%d  ·  %s" % [c.cases_used(), c.case_capacity, ", ".join(names)]
	# Shop strip.
	var b := game.current_business()
	if b:
		var cap := 0
		for s in b.slots:
			cap += int(s["cap"])
		var fill := float(b.shelf_units()) / maxf(cap, 1)
		var trading := b.open and b.within_hours(e.hour())
		_strip.text = "%s · %s\n★ %d  ·  shelves %d%%  ·  queue %d  ·  today %s" % [b.name.to_upper(),
			"OPEN" if trading else "CLOSED", int(b.reputation), int(fill * 100.0),
			game.floor.queue_length() if game.floor else 0, EmpireData.money(float(b.today["revenue"]))]
		_strip_panel.visible = true
	else:
		_strip.text = ""
		_strip_panel.visible = false
	if game.driving != "":
		var car: Car = game.cars[game.driving]
		var v := e.vehicle(game.driving)
		_drive.text = "%d mph   ·   %d/%d cases" % [int(car.speed * 2.237), (v["cargo"] as Stock).cases_used(),
			(v["cargo"] as Stock).case_capacity]
	else:
		_drive.text = ""
	_update_floats()


func toast(text: String, kind := "info") -> void:
	var col: Color = {"good": S.GREEN, "warn": S.AMBER, "bad": S.RED}.get(kind, S.BLUE)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(S.INK, 0.9)
	sb.set_corner_radius_all(12)
	sb.border_color = col
	sb.border_width_left = 5
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var l := S.label(text, 16, S.PAPER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 340
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(p)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	var tw := create_tween()
	tw.tween_interval(4.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


var _float_items: Array = []


func float_text(text: String, world_p: Vector3, col: Color) -> void:
	var l := S.label(text, 22, col, "black")
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	_floats.add_child(l)
	_float_items.append({"l": l, "p": world_p, "t": 0.0})


func _update_floats() -> void:
	var cam := get_viewport().get_camera_3d()
	for f in _float_items.duplicate():
		f["t"] = float(f["t"]) + get_process_delta_time()
		var l: Label = f["l"]
		if float(f["t"]) > 1.6 or cam == null:
			l.queue_free()
			_float_items.erase(f)
			continue
		var wp: Vector3 = f["p"] + Vector3.UP * float(f["t"]) * 0.8
		if cam.is_position_behind(wp):
			l.visible = false
			continue
		l.visible = true
		l.position = cam.unproject_position(wp) - l.size * 0.5
		l.modulate.a = clampf(2.0 - float(f["t"]) * 1.25, 0.0, 1.0)


class _Arrow extends Control:
	var angle := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array([Vector2(0, -18), Vector2(13, 12), Vector2(0, 5), Vector2(-13, 12)])
		var out := PackedVector2Array()
		for p in pts:
			out.append(c + p.rotated(angle))
		draw_colored_polygon(out, EmpireStyle.AMBER)
		out.append(out[0])
		draw_polyline(out, Color(0, 0, 0, 0.6), 2.0, true)


# --------------------------------------------------------------- panels
func _open(title: String, width := 860.0, height := 560.0) -> VBoxContainer:
	close_panel(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_root.add_child(dim)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(width, height)
	_anchor(_panel, 0.5, 0.5, -Vector2(width, height) * 0.5, Vector2(width, height))
	_panel_root.add_child(_panel)
	var v := S.vbox(14)
	_panel.add_child(v)
	var head := S.hbox(10)
	var t := S.label(title, 28, S.PAPER, "black")
	head.add_child(t)
	head.add_child(S.spacer())
	head.add_child(S.button("✕", close_panel.bind(true), false, 52))
	v.add_child(head)
	return v


func close_panel(resume := true) -> void:
	for c in _panel_root.get_children():
		c.queue_free()
	_panel = null
	if resume:
		get_tree().paused = false
		if game and game.state == "play" and not touch.visible and not game.args.has("shot"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func panel_open() -> bool:
	return _panel != null


func _scroll(content: Control, h := 400.0) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, h)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


func _row(children: Array) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", S.row_bg())
	var h := S.hbox(12)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	for c in children:
		h.add_child(c)
	p.add_child(h)
	return p


func _fixed(text: String, w: float, size := 17, col := S.PAPER, weight := "semibold") -> Label:
	var l := S.label(text, size, col, weight)
	l.custom_minimum_size.x = w
	l.clip_text = true
	return l


# ---------------------------------------------------------------- title
func show_title(has_save: bool) -> void:
	hud.visible = false
	touch.visible = false
	for c in _title_root.get_children():
		c.queue_free()
	_title_root.visible = true
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.05, 0.07, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(shade)
	var v := S.vbox(14)
	v.position = Vector2(80, 150)
	_title_root.add_child(v)
	var mark := S.label("MUSA STUDIOS", 16, S.AMBER, "black")
	v.add_child(mark)
	var t := S.label("CITY EMPIRE", 84, S.PAPER, "black")
	t.add_theme_constant_override("outline_size", 0)
	v.add_child(t)
	v.add_child(S.label("Start as the worker. Become the owner. Build the empire.", 21, S.MUTED))
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	v.add_child(gap)
	if has_save:
		var b := S.button("CONTINUE", func(): game.continue_game(), true, 320)
		v.add_child(b)
	v.add_child(S.button("NEW GAME", func():
		if has_save:
			_confirm_new()
		else:
			game.start_new(), not has_save, 320))
	v.add_child(S.button("SETTINGS", func(): _settings_panel(), false, 320))


func _confirm_new() -> void:
	var v := _open("Start again?", 560, 240)
	v.add_child(S.label("Your saved empire will be replaced.", 19, S.MUTED))
	var h := S.hbox(12)
	h.add_child(S.button("Cancel", close_panel.bind(false), false, 160))
	h.add_child(S.button("New game", func():
		close_panel(true)
		game.start_new(), true, 200))
	v.add_child(h)


func intro() -> void:
	var v := _open("Welcome to the city", 760, 460)
	var txt := S.label("You've got %s in savings and an old hatchback.\n\nThe little shop on the quay is going cheap. Rent it, " % EmpireData.money(game.empire.personal_cash) \
		+ "drive to the cash & carry for stock, carry it in, fill the shelves and serve your first customers.\n\n" \
		+ "The QuikSave chain wants every corner of this city. Grow, hire, buy them out – and drive them out.", 19, S.PAPER)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(700, 0)
	v.add_child(txt)
	var ctr := S.label("Move WASD / left stick · Look mouse / right side · Act E · Phone TAB · Drive W/S/A/D, Space handbrake · T fast-forward", 15, S.MUTED)
	ctr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctr.custom_minimum_size = Vector2(700, 0)
	v.add_child(ctr)
	v.add_child(S.button("LET'S GO", func():
		game.empire.flags["intro_done"] = true
		close_panel(true), true, 220))


# ------------------------------------------------------------ wholesale
func open_wholesale(unit: Dictionary) -> void:
	_cart_unit = unit
	_wholesale_page()


func _wholesale_page() -> void:
	var unit := _cart_unit
	var v := _open(String(unit.get("name", "Wholesale")), 980, 640)
	var e := game.empire
	var cap := 0
	for veh in e.vehicles:
		cap = maxi(cap, (veh["cargo"] as Stock).case_capacity)
	var info := S.label("Trade prices by the case. Goods go to the collection bay outside — your biggest vehicle holds %d cases." % cap, 16, S.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 900
	v.add_child(info)
	var list := S.vbox(6)
	var cats := EmpireData.categories()
	for cat in cats:
		list.add_child(S.label(String(cats[cat]["name"]).to_upper(), 14, Color.from_string(cats[cat]["colour"], S.AMBER), "black"))
		for pid in EmpireData.product_ids():
			var p := EmpireData.product(pid)
			if p["cat"] != cat:
				continue
			var n := int(_cart.get(pid, 0))
			var unit_cost := EmpireData.unit_cost(pid)
			var swatch := ColorRect.new()
			swatch.color = EmpireData.colour(pid)
			swatch.custom_minimum_size = Vector2(18, 28)
			var note := ""
			if p["fixture"] == "fridge":
				note = "  · fridge"
			elif p["fixture"] in ["coffee", "pickmix"]:
				note = "  · needs %s" % ("Coffee Machine" if p["fixture"] == "coffee" else "Pick & Mix Wall")
			list.add_child(_row([swatch, _fixed(String(p["name"]) + note, 330),
				_fixed("%d per case" % int(p["case_qty"]), 110, 15, S.MUTED),
				_fixed(EmpireData.money(float(p["case_cost"]), true), 90, 17, S.PAPER, "bold"),
				_fixed("%s each · RRP %s" % [EmpireData.money(unit_cost, true), EmpireData.money(float(p["rrp"]), true)], 210, 14, S.MUTED),
				S.button("−", func(): _cart_add(pid, -1), false, 46),
				_fixed(str(n), 34, 20, S.AMBER if n > 0 else S.PAPER, "black"),
				S.button("+", func(): _cart_add(pid, 1), false, 46)]))
	v.add_child(_scroll(list, 400))
	var total := 0.0
	var cases := 0
	for pid in _cart:
		total += float(EmpireData.product(pid)["case_cost"]) * int(_cart[pid])
		cases += int(_cart[pid])
	var foot := S.hbox(14)
	foot.add_child(S.label("%d case%s · %s" % [cases, "" if cases == 1 else "s", EmpireData.money(total, true)], 24, S.PAPER, "black"))
	foot.add_child(S.label("You have %s + company %s" % [EmpireData.money(e.personal_cash), EmpireData.money(e.company_cash)], 15, S.MUTED))
	foot.add_child(S.spacer())
	var sack := e.carried.case_capacity < 6
	if sack:
		foot.add_child(S.button("Sack truck £120 (carry 6)", func():
			if e.pay(120.0, "equipment", "Sack truck"):
				e.carried.case_capacity = 6
				toast("Sack truck: you can carry 6 cases now", "good")
				_wholesale_page()
			else:
				toast("Not enough money", "bad")))
	foot.add_child(S.button("Clear", func(): _cart.clear(); _wholesale_page()))
	foot.add_child(S.button("PAY · %s" % EmpireData.money(total, true), func():
		var err := game.buy_wholesale(_cart_unit, _cart)
		if err != "":
			toast(err, "bad")
			return
		toast("Paid. %d case%s waiting at the collection bay." % [cases, "" if cases == 1 else "s"], "good")
		_cart.clear()
		close_panel(true), true, 220))
	v.add_child(foot)


func _cart_add(pid: String, d: int) -> void:
	_cart[pid] = clampi(int(_cart.get(pid, 0)) + d, 0, 99)
	if int(_cart[pid]) == 0:
		_cart.erase(pid)
	_wholesale_page()


# ------------------------------------------------------------- property
func open_property(u: Dictionary) -> void:
	var d := EmpireData.district(u["district"])
	var v := _open(String(u.get("shop_name", "Shop unit")), 760, 470)
	v.add_child(S.label("%s  ·  %s  ·  %d m²" % [u["name"], d.get("name", ""), int(u["size"])], 18, S.MUTED))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 40)
	g.add_theme_constant_override("v_separation", 8)
	for pair in [["Rent", "%s a day (deposit %s)" % [EmpireData.money(float(u["rent"])), EmpireData.money(float(u["rent"]) * 3.0)]],
			["Freehold", EmpireData.money(float(u["price"]))],
			["Shoppers", "%s · about %d an hour at peak" % [_level(float(d.get("footfall", 8)), [7, 11, 16]), int(float(d.get("footfall", 8)) * 1.4)]],
			["Spending", _level(float(d.get("affluence", 1.0)), [0.95, 1.08, 1.2])],
			["They buy", _top_mix(d)],
			["Island", "Commercial Island" if u["island"] == "east" else "Westbank (industrial & residential)"]]:
		g.add_child(S.label(pair[0], 17, S.MUTED))
		g.add_child(S.label(pair[1], 18, S.PAPER, "bold"))
	v.add_child(g)
	v.add_child(S.label("You have %s + company %s" % [EmpireData.money(game.empire.personal_cash), EmpireData.money(game.empire.company_cash)], 15, S.MUTED))
	var h := S.hbox(12)
	h.add_child(S.button("RENT · %s deposit" % EmpireData.money(float(u["rent"]) * 3.0), func():
		var err := game.rent_unit(u)
		if err != "":
			toast(err, "bad")
		else:
			close_panel(true), true, 300))
	h.add_child(S.button("BUY · %s" % EmpireData.money(float(u["price"])), func():
		var err := game.rent_unit(u, true)
		if err != "":
			toast(err, "bad")
		else:
			close_panel(true), false, 240))
	v.add_child(h)


static func _level(x: float, cuts: Array) -> String:
	if x < float(cuts[0]):
		return "Quiet"
	if x < float(cuts[1]):
		return "Steady"
	if x < float(cuts[2]):
		return "Busy"
	return "Very busy"


static func _top_mix(d: Dictionary) -> String:
	var mix: Dictionary = d.get("mix", {})
	var ks := mix.keys()
	ks.sort_custom(func(a, b): return float(mix[a]) > float(mix[b]))
	var names: Array = []
	for k in ks.slice(0, 3):
		names.append(String(EmpireData.categories().get(k, {}).get("name", k)))
	return ", ".join(names)


func open_home(hm: Dictionary) -> void:
	var v := _open(String(hm["name"]), 720, 380)
	v.add_child(S.label("%s · %d m above the street · %s" % [EmpireData.district(hm["district"]).get("name", ""), int(hm["floor"]),
		["a studio", "a one-bed flat", "a loft", "a luxury apartment", "the penthouse"][int(hm["tier"])]], 18, S.MUTED))
	var txt := S.label("Live here (a bed to sleep in and a view), or let it out: tenants pay about %s a day." % EmpireData.money(float(hm["price"]) * 0.0045), 18, S.PAPER)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size.x = 650
	v.add_child(txt)
	v.add_child(S.label("You have %s + company %s" % [EmpireData.money(game.empire.personal_cash), EmpireData.money(game.empire.company_cash)], 15, S.MUTED))
	v.add_child(S.button("BUY · %s" % EmpireData.money(float(hm["price"])), func():
		var rec := hm.duplicate()
		rec.erase("h")
		if game.empire.buy_property(rec):
			toast("The keys are yours", "good")
			close_panel(true)
		else:
			toast("Not enough money", "bad"), true, 260))


# ----------------------------------------------------------------- rack
func open_rack(b: Business) -> void:
	var v := _open("Stockroom · %d/%d cases" % [b.backroom.cases_used(), b.backroom.case_capacity], 720, 520)
	var list := S.vbox(6)
	for pid in b.backroom.units:
		var p := EmpireData.product(pid)
		var on_shelf := b.shelf_qty(pid)
		list.add_child(_row([_fixed(String(p["name"]), 260, 18, S.PAPER, "bold"),
			_fixed("%d in stock" % b.backroom.qty(pid), 120, 16, S.MUTED),
			_fixed("%d on shelves" % on_shelf, 130, 16, S.MUTED),
			S.button("TAKE A CASE", func():
				game.take_case(b, pid)
				close_panel(true), true, 160)]))
	v.add_child(_scroll(list, 360))
	v.add_child(S.label("Carry a case to a shelf (or the fridge) and press ACTION to fill it.", 15, S.MUTED))


# ---------------------------------------------------------------- price
func open_price(b: Business, pid: String) -> void:
	if pid == "":
		return
	var p := EmpireData.product(pid)
	var v := _open(String(p["name"]), 640, 400)
	var cost := game.empire.unit_cost(pid)
	var info := S.label("", 18, S.PAPER)
	var share := S.label("", 16, S.MUTED)
	var refresh := func():
		var pr := b.price(pid)
		info.text = "%s each  ·  cost %s  ·  margin %d%%  ·  RRP %s" % [EmpireData.money(pr, true), EmpireData.money(cost, true),
			int((pr - cost) / maxf(pr, 0.01) * 100.0), EmpireData.money(EmpireData.rrp(pid), true)]
		share.text = "About %d%% of shoppers here would pay this." % int(DemandModel.buy_share(b, pid, pr) * 100.0)
	refresh.call()
	v.add_child(info)
	v.add_child(share)
	var h := S.hbox(10)
	for step: float in [-0.25, -0.05, 0.05, 0.25]:
		h.add_child(S.button(("%+.2f" % step).replace("+", "+£").replace("-", "−£"), func():
			b.set_price(pid, b.price(pid) + step)
			refresh.call()
			_refresh_interior(b), false, 110))
	v.add_child(h)
	v.add_child(S.button("Set to RRP", func():
		b.set_price(pid, EmpireData.rrp(pid))
		refresh.call()
		_refresh_interior(b)))


func _refresh_interior(b: Business) -> void:
	var si: ShopInterior = game.interiors.get(b.premises.get("id", ""))
	if si:
		si.refresh_goods()


# --------------------------------------------------------------- manage
func open_manage(b: Business, tab := "overview") -> void:
	_manage_biz = b
	_tab = tab
	var v := _open(b.name, 1060, 650)
	var tabs := S.hbox(8)
	for t in [["overview", "Overview"], ["prices", "Prices"], ["stock", "Stock & orders"], ["staff", "Staff"],
			["upgrades", "Upgrades"], ["reports", "Reports"]]:
		var bt := S.button(t[1], func(): open_manage(b, t[0]), t[0] == tab)
		tabs.add_child(bt)
	v.add_child(tabs)
	match tab:
		"overview": _m_overview(v, b)
		"prices": _m_prices(v, b)
		"stock": _m_stock(v, b)
		"staff": _m_staff(v, b)
		"upgrades": _m_upgrades(v, b)
		"reports": _m_reports(v, b)


func _stat(title: String, value: String, col := S.PAPER) -> VBoxContainer:
	var s := S.vbox(0)
	s.add_child(S.label(title.to_upper(), 13, S.MUTED, "black"))
	s.add_child(S.label(value, 26, col, "black"))
	s.custom_minimum_size.x = 180
	return s


func _m_overview(v: VBoxContainer, b: Business) -> void:
	var e := game.empire
	var t := b.today
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 14)
	var trading := b.trading(e.hour()) or (b.open and b.within_hours(e.hour()))
	g.add_child(_stat("Status", "OPEN" if trading else "CLOSED", S.GREEN if trading else S.RED))
	g.add_child(_stat("Takings today", EmpireData.money(float(t["revenue"]), true)))
	g.add_child(_stat("Customers", "%d / %d served" % [int(t["customers"]), int(t["served"])]))
	g.add_child(_stat("Reputation", "★ %d" % int(b.reputation), S.AMBER))
	g.add_child(_stat("Clean", "%d%%" % int(b.cleanliness * 100.0)))
	g.add_child(_stat("Rent / day", EmpireData.money(b.rent_per_day()) if not b.owned else "Owned"))
	g.add_child(_stat("Staff / hour", EmpireData.money(b.wages_per_hour(), true)))
	g.add_child(_stat("Stockroom", "%d/%d cases" % [b.backroom.cases_used(), b.backroom.case_capacity]))
	g.add_child(_stat("Out of stock", str(int(t["stockouts"])), S.RED if int(t["stockouts"]) > 0 else S.PAPER))
	g.add_child(_stat("Too dear", str(int(t["too_expensive"]))))
	v.add_child(g)
	var tips: Array = []
	if not b.has_role("cashier"):
		tips.append("Nobody's on the till: the shop only trades while you're here. Hire a cashier to keep it open while you're away.")
	if int(t["not_stocked"]) > 8:
		tips.append("%d shoppers wanted things you don't sell. Check Reports for what's asked for." % int(t["not_stocked"]))
	if b.cleanliness < 0.6:
		tips.append("The floor's grubby: it's costing you sales. Clean it or hire a cleaner.")
	if e.company_cash < 0.0:
		tips.append("The company account is overdrawn. Move savings in from the phone (Bank).")
	for tp in tips:
		var l := S.label("• " + tp, 16, S.AMBER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 980
		v.add_child(l)
	var h := S.hbox(12)
	h.add_child(S.button("CLOSE SHOP" if b.open else "OPEN SHOP", func():
		b.open = not b.open
		game._refresh_signs(b.premises["id"])
		open_manage(b, "overview")))
	if not b.owned:
		h.add_child(S.button("Buy the freehold · %s" % EmpireData.money(float(b.premises.get("price", 0))), func():
			if e.buy_premises(b.premises) == null:
				toast("Not enough money", "bad")
			open_manage(b, "overview")))
	v.add_child(h)


func _m_prices(v: VBoxContainer, b: Business) -> void:
	var list := S.vbox(6)
	var stocked := b.stocked_products()
	if stocked.is_empty():
		list.add_child(S.label("Nothing on the shelves yet.", 18, S.MUTED))
	for pid in stocked:
		var p := EmpireData.product(pid)
		var cost := game.empire.unit_cost(pid)
		var pr := b.price(pid)
		var share := DemandModel.buy_share(b, pid, pr)
		list.add_child(_row([_fixed(String(p["name"]), 240, 18, S.PAPER, "bold"),
			_fixed(EmpireData.money(pr, true), 80, 20, S.AMBER, "black"),
			_fixed("cost %s · %d%% margin" % [EmpireData.money(cost, true), int((pr - cost) / maxf(pr, 0.01) * 100.0)], 200, 15, S.MUTED),
			_fixed("%d%% would buy" % int(share * 100.0), 130, 15, S.GREEN if share > 0.6 else (S.AMBER if share > 0.3 else S.RED)),
			S.button("−5p", func(): b.set_price(pid, pr - 0.05); _refresh_interior(b); open_manage(b, "prices"), false, 70),
			S.button("+5p", func(): b.set_price(pid, pr + 0.05); _refresh_interior(b); open_manage(b, "prices"), false, 70),
			S.button("RRP", func(): b.set_price(pid, EmpireData.rrp(pid)); _refresh_interior(b); open_manage(b, "prices"), false, 70)]))
	v.add_child(_scroll(list, 460))


func _m_stock(v: VBoxContainer, b: Business) -> void:
	var e := game.empire
	var list := S.vbox(6)
	var fee := e.delivery_fee(b)
	var head := S.label("Phone order: delivered to the stockroom by 06:00 tomorrow (%s)." % ("free with your driver" if fee == 0.0 else "%s delivery" % EmpireData.money(fee)), 16, S.MUTED)
	v.add_child(head)
	for pid in EmpireData.product_ids():
		var p := EmpireData.product(pid)
		if not p["cat"] in b.type_def().get("categories", []):
			continue
		if p["fixture"] == "coffee" and not b.has_upgrade("coffee"):
			continue
		if p["fixture"] == "pickmix" and not b.has_upgrade("pick_mix"):
			continue
		var pending := 0
		for o in b.orders:
			pending += int(o["units"].get(pid, 0))
		var n := int(_cart.get("o_" + pid, 0))
		list.add_child(_row([_fixed(String(p["name"]), 230, 17, S.PAPER, "bold"),
			_fixed("shelf %d" % b.shelf_qty(pid), 80, 15, S.MUTED),
			_fixed("room %d" % b.backroom.qty(pid), 80, 15, S.MUTED),
			_fixed("coming %d" % pending if pending > 0 else "", 100, 15, S.BLUE),
			_fixed("%s/case" % EmpireData.money(float(p["case_cost"]), true), 110, 15, S.MUTED),
			S.button("−", func(): _cart["o_" + pid] = maxi(n - 1, 0); open_manage(b, "stock"), false, 46),
			_fixed(str(n), 30, 19, S.AMBER if n > 0 else S.PAPER, "black"),
			S.button("+", func(): _cart["o_" + pid] = n + 1; open_manage(b, "stock"), false, 46)]))
	v.add_child(_scroll(list, 380))
	var order := {}
	var total := fee
	for k in _cart:
		if String(k).begins_with("o_") and int(_cart[k]) > 0:
			order[String(k).trim_prefix("o_")] = int(_cart[k])
			total += float(EmpireData.product(String(k).trim_prefix("o_"))["case_cost"]) * int(_cart[k])
	var h := S.hbox(12)
	h.add_child(S.label("Order total %s" % EmpireData.money(total if not order.is_empty() else 0.0, true), 20, S.PAPER, "black"))
	h.add_child(S.spacer())
	h.add_child(S.button("PLACE ORDER", func():
		var err := e.order_delivery(b, order)
		if err != "":
			toast(err, "bad")
		else:
			toast("Ordered: arriving by 06:00", "good")
			for k in _cart.keys():
				if String(k).begins_with("o_"):
					_cart.erase(k)
		open_manage(b, "stock"), true, 200))
	v.add_child(h)


func _m_staff(v: VBoxContainer, b: Business) -> void:
	var e := game.empire
	var list := S.vbox(6)
	list.add_child(S.label("ON YOUR TEAM", 14, S.AMBER, "black"))
	if b.staff.is_empty():
		list.add_child(S.label("Just you. Hire people to take over the routine work.", 16, S.MUTED))
	for st in b.staff:
		list.add_child(_row([_fixed(String(st["name"]), 200, 18, S.PAPER, "bold"),
			_fixed(String(EmpireData.role(st["role"]).get("name", "")), 150, 16, S.MUTED),
			_fixed("skill " + "●".repeat(int(st["skill"])) + "○".repeat(5 - int(st["skill"])), 140, 15, S.AMBER),
			_fixed(Staff.trait_names(st), 150, 14, S.MUTED),
			_fixed("%s/h" % EmpireData.money(float(st["wage"]), true), 90, 16),
			S.button("Let go", func(): game.fire(b, st); open_manage(b, "staff"), false, 100)]))
	list.add_child(S.label("LOOKING FOR WORK TODAY", 14, S.AMBER, "black"))
	for c in e.candidates:
		var r := EmpireData.role(c["role"])
		var why := S.label(String(r.get("desc", "")), 14, S.MUTED)
		why.custom_minimum_size.x = 260
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(_row([_fixed(String(c["name"]), 180, 18, S.PAPER, "bold"),
			_fixed(String(r.get("name", "")), 140, 16, S.BLUE, "bold"),
			_fixed("●".repeat(int(c["skill"])) + "○".repeat(5 - int(c["skill"])), 80, 15, S.AMBER),
			_fixed(Staff.trait_names(c), 110, 14, S.MUTED), why,
			_fixed("%s/h" % EmpireData.money(float(c["wage"]), true), 80, 16),
			S.button("Hire", func(): game.hire(b, c); open_manage(b, "staff"), true, 90)]))
	v.add_child(_scroll(list, 430))
	var hrs := b.hours()
	v.add_child(S.label("Shifts cover opening hours (%02d:00–%02d:00): a %s/h team costs about %s a day." % [int(hrs.x), int(hrs.y),
		EmpireData.money(b.wages_per_hour(), true), EmpireData.money(b.wages_per_hour() * (hrs.y - hrs.x))], 15, S.MUTED))


func _m_upgrades(v: VBoxContainer, b: Business) -> void:
	var list := S.vbox(6)
	for u in b.type_def().get("upgrades", []):
		var d := EmpireData.upgrade(u)
		var have := b.has_upgrade(u)
		var desc := S.label(String(d.get("desc", "")), 15, S.MUTED)
		desc.custom_minimum_size.x = 430
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var btn: Control
		if have:
			btn = S.chip("FITTED", S.GREEN)
		else:
			btn = S.button("Buy · %s" % EmpireData.money(float(d.get("cost", 0))), func():
				var err := game.buy_upgrade(b, u)
				if err != "":
					toast(err, "bad")
				open_manage(b, "upgrades"), true, 170)
		list.add_child(_row([_fixed(String(d.get("name", u)), 220, 18, S.PAPER, "bold"), desc, S.spacer(), btn]))
	v.add_child(_scroll(list, 470))


func _m_reports(v: VBoxContainer, b: Business) -> void:
	var list := S.vbox(6)
	if b.history.is_empty():
		list.add_child(S.label("Your first report comes at midnight.", 18, S.MUTED))
	var hist := b.history.duplicate()
	hist.reverse()
	list.add_child(_row([_fixed("Day", 70, 14, S.MUTED, "black"), _fixed("Takings", 110, 14, S.MUTED, "black"),
		_fixed("Goods", 100, 14, S.MUTED, "black"), _fixed("Wages", 90, 14, S.MUTED, "black"),
		_fixed("Rent+bills", 110, 14, S.MUTED, "black"), _fixed("Profit", 110, 14, S.MUTED, "black"),
		_fixed("Served", 90, 14, S.MUTED, "black"), _fixed("Lost sales", 230, 14, S.MUTED, "black")]))
	for r in hist:
		var pr := float(r["profit"])
		list.add_child(_row([_fixed(str(int(r["day"])), 70), _fixed(EmpireData.money(float(r["revenue"])), 110),
			_fixed(EmpireData.money(-float(r["cogs"])), 100, 17, S.MUTED), _fixed(EmpireData.money(-float(r["wages"])), 90, 17, S.MUTED),
			_fixed(EmpireData.money(-(float(r["rent"]) + float(r["utilities"]))), 110, 17, S.MUTED),
			_fixed(EmpireData.money(pr), 110, 18, S.GREEN if pr >= 0.0 else S.RED, "black"),
			_fixed("%d/%d" % [int(r["served"]), int(r["customers"])], 90),
			_fixed("%d empty · %d not sold · %d dear" % [int(r["stockouts"]), int(r["not_stocked"]), int(r["too_expensive"])], 260, 14, S.MUTED)]))
	v.add_child(_scroll(list, 470))


# ---------------------------------------------------------------- phone
func open_phone(tab := "businesses") -> void:
	var e := game.empire
	var v := _open("Phone", 1000, 640)
	var tabs := S.hbox(8)
	for t in [["businesses", "Businesses"], ["city", "City"], ["map", "Map"], ["bank", "Bank"], ["vehicles", "Vehicles"],
			["property", "Property"], ["goals", "Goals"], ["game", "Game"]]:
		tabs.add_child(S.button(t[1], func(): open_phone(t[0]), t[0] == tab))
	v.add_child(tabs)
	match tab:
		"businesses":
			var list := S.vbox(6)
			if e.businesses.is_empty():
				list.add_child(S.label("No businesses yet. Look for TO LET signs.", 18, S.MUTED))
			for b: Business in e.businesses:
				var trading := b.trading(e.hour())
				list.add_child(_row([_fixed(b.name, 220, 19, S.PAPER, "bold"),
					_fixed(String(b.district().get("name", "")), 170, 15, S.MUTED),
					S.chip("TRADING" if trading else ("OPEN" if b.open else "CLOSED"), S.GREEN if trading else S.MUTED),
					_fixed("today %s" % EmpireData.money(float(b.today["revenue"])), 130, 16),
					_fixed("★ %d · staff %d" % [int(b.reputation), b.staff.size()], 130, 15, S.AMBER),
					S.button("Manage", func(): open_manage(b), true, 110),
					S.button("GPS", func():
						game.set_gps(Premises.door_point(game.unit_by_id[b.premises["id"]]), b.name)
						close_panel(true), false, 70)]))
			list.add_child(S.label("PLACES", 14, S.AMBER, "black"))
			for u in game.units:
				if u["kind"] == "wholesale":
					list.add_child(_row([_fixed(String(u["name"]), 300, 18, S.PAPER, "bold"),
						_fixed("Wholesaler · " + String(EmpireData.district(u["district"]).get("name", "")), 300, 15, S.MUTED),
						S.button("GPS", func():
							game.set_gps(Premises.door_point(u), u["name"])
							close_panel(true), false, 70)]))
			var free := game.units.filter(func(u): return u["kind"] == "shop" and e.business_at(u["id"]) == null)
			free.sort_custom(func(a, b): return float(a["rent"]) < float(b["rent"]))
			for u in free:
				list.add_child(_row([_fixed("TO LET · " + String(u["shop_name"]), 300, 17, S.PAPER),
					_fixed(String(EmpireData.district(u["district"]).get("name", "")), 220, 15, S.MUTED),
					_fixed("%s/day" % EmpireData.money(float(u["rent"])), 110, 16, S.AMBER),
					S.button("GPS", func():
						game.set_gps(Premises.door_point(u), String(u["shop_name"]))
						close_panel(true), false, 70)]))
			v.add_child(_scroll(list, 470))
		"city":
			_city_tab(v)
		"map":
			var m := EmpireMap.new()
			m.game = game
			m.custom_minimum_size = Vector2(940, 480)
			v.add_child(m)
		"bank":
			var g := GridContainer.new()
			g.columns = 4
			g.add_theme_constant_override("h_separation", 26)
			g.add_child(_stat("Savings", EmpireData.money(e.personal_cash, true)))
			g.add_child(_stat("Company", EmpireData.money(e.company_cash, true), S.RED if e.company_cash < 0 else S.PAPER))
			g.add_child(_stat("Stock value", EmpireData.money(e.stock_value())))
			g.add_child(_stat("Net worth", EmpireData.money(e.net_worth()), S.GREEN))
			v.add_child(g)
			if e.day_reports.size() >= 2:
				var chart := _NetChart.new()
				chart.reports = e.day_reports
				chart.custom_minimum_size = Vector2(940, 110)
				v.add_child(chart)
			var h := S.hbox(10)
			for amt: float in [100.0, 500.0, 2000.0]:
				h.add_child(S.button("Put %s in" % EmpireData.money(amt), func():
					if not e.transfer_to_company(amt):
						toast("Not enough savings", "bad")
					open_phone("bank")))
			for amt2: float in [100.0, 500.0]:
				h.add_child(S.button("Take %s out" % EmpireData.money(amt2), func():
					if not e.draw_from_company(amt2):
						toast("Not enough in the company", "bad")
					open_phone("bank")))
			v.add_child(h)
			var lim := e.loan_limit()
			var h2 := S.hbox(10)
			h2.add_child(S.label("Business loan: up to %s at %.1f%% a day" % [EmpireData.money(lim),
				float(EmpireData.economy()["loan"]["daily_rate"]) * 100.0], 17, S.MUTED))
			for frac: float in [0.25, 1.0]:
				var amt3 := floorf(lim * frac / 100.0) * 100.0
				if amt3 >= 100.0:
					h2.add_child(S.button("Borrow %s" % EmpireData.money(amt3), func():
						e.take_loan(amt3)
						open_phone("bank")))
			v.add_child(h2)
			for l in e.loans:
				v.add_child(_row([_fixed("Loan %s · due day %d" % [EmpireData.money(float(l["principal"])), int(l["due"])], 360),
					S.button("Repay", func():
						if not e.repay_loan(l, float(l["principal"])):
							toast("Not enough money", "bad")
						open_phone("bank"))]))
			var led := S.vbox(4)
			var recent := e.ledger.slice(maxi(e.ledger.size() - 40, 0))
			recent.reverse()
			for x in recent:
				if absf(float(x["amount"])) < 0.005:
					continue
				led.add_child(_row([_fixed("Day %d %02d:%02d" % [int(x["day"]), int(x["min"]) / 60, int(x["min"]) % 60], 130, 14, S.MUTED),
					_fixed("Company" if x["acct"] == "company" else "Savings", 90, 14, S.MUTED), _fixed(String(x["memo"]), 420, 15),
					_fixed(EmpireData.money(float(x["amount"]), true), 110, 16, S.GREEN if float(x["amount"]) > 0 else S.PAPER, "bold")]))
			v.add_child(_scroll(led, 150 if e.day_reports.size() >= 2 else 260))
		"vehicles":
			var list2 := S.vbox(6)
			for veh in e.vehicles:
				var md := EmpireData.vehicle_model(veh["model"])
				list2.add_child(_row([_fixed(String(md["name"]), 220, 18, S.PAPER, "bold"),
					_fixed("%d cases · %d%% condition · %d km" % [(veh["cargo"] as Stock).case_capacity, int(float(veh["condition"]) * 100.0),
						int(float(veh["km"]))], 330, 15, S.MUTED),
					S.button("Service", func():
						var err := e.service_vehicle(veh)
						toast(err if err != "" else "Serviced", "bad" if err != "" else "good")
						open_phone("vehicles"), false, 120),
					S.button("GPS", func():
						var c: Car = game.cars.get(veh["id"])
						if c:
							game.set_gps(c.global_position, String(md["name"]))
						close_panel(true), false, 70)]))
			list2.add_child(S.label("DEALER (delivered to the kerb beside you)", 14, S.AMBER, "black"))
			for mid in EmpireData.vehicle_models():
				var md2 := EmpireData.vehicle_model(mid)
				if float(md2.get("price", 0)) <= 0.0:
					continue
				list2.add_child(_row([_fixed(String(md2["name"]), 220, 18, S.PAPER, "bold"),
					_fixed("%d cases · top %d mph" % [int(md2["cargo"]), int(float(md2["top_speed"]) * 2.237)], 260, 15, S.MUTED),
					S.spacer(),
					S.button("Buy · %s" % EmpireData.money(float(md2["price"])), func():
						var err := game.buy_vehicle(mid)
						toast(err if err != "" else "Delivered outside", "bad" if err != "" else "good")
						open_phone("vehicles"), true, 180)]))
			v.add_child(_scroll(list2, 470))
		"property":
			var lp := S.vbox(6)
			lp.add_child(S.label("HOMES (buy at the tower's street door)", 14, S.AMBER, "black"))
			for hm in game.homes():
				var owned := e.owns_property(hm["id"])
				var rec: Dictionary = {}
				for q in e.properties:
					if q["id"] == hm["id"]:
						rec = q
				var row: Array = [_fixed(String(hm["name"]), 230, 18, S.PAPER, "bold"),
					_fixed("%s · %d m up" % [EmpireData.district(hm["district"]).get("name", ""), int(hm["floor"])], 220, 15, S.MUTED),
					_fixed(EmpireData.money(float(hm["price"])), 110, 17)]
				if owned:
					var let: bool = rec.get("let", false)
					row.append(S.chip("LET · %s/day" % EmpireData.money(float(hm["price"]) * 0.0045) if let else "YOURS", S.GREEN))
					row.append(S.button("Move in" if let else "Let it out", func():
						e.set_let(hm["id"], not let)
						open_phone("property"), false, 140))
				else:
					row.append(_fixed("lets for %s/day" % EmpireData.money(float(hm["price"]) * 0.0045), 160, 15, S.MUTED))
				row.append(S.button("GPS", func():
					game.set_gps(game.home_lift(hm), String(hm["name"]))
					close_panel(true), false, 70))
				lp.add_child(_row(row))
			lp.add_child(S.label("YOUR PREMISES", 14, S.AMBER, "black"))
			for b: Business in e.businesses:
				lp.add_child(_row([_fixed(b.name, 230, 18, S.PAPER, "bold"),
					_fixed(String(b.district().get("name", "")), 220, 15, S.MUTED),
					S.chip("FREEHOLD" if b.owned else "RENTED · %s/day" % EmpireData.money(b.rent_per_day()), S.GREEN if b.owned else S.MUTED)]))
			v.add_child(_scroll(lp, 470))
		"goals":
			var list3 := S.vbox(6)
			if e.flags.get("won", false):
				list3.add_child(S.label("EMPIRE COMPLETE · day %d" % int(e.flags.get("won_day", e.day)), 18, S.GREEN, "black"))
			for ch in EmpireData.chapters():
				list3.add_child(S.label(String(ch["name"]).to_upper(), 15, S.AMBER, "black"))
				for gl in ch["goals"]:
					var done := e.goals_done.has(gl["id"])
					var prog := e.stat(gl["stat"])
					list3.add_child(_row([_fixed("✓" if done else "○", 30, 20, S.GREEN if done else S.MUTED, "black"),
						_fixed(String(gl["text"]), 420, 17, S.PAPER if not done else S.MUTED),
						_fixed("" if done else "%s / %s" % [_short(prog), _short(float(gl["value"]))], 200, 15, S.MUTED)]))
			v.add_child(_scroll(list3, 470))
		"game":
			v.add_child(S.label("Day %d · %s %s · net worth %s" % [e.day, e.weekday(), e.clock_text(), EmpireData.money(e.net_worth())], 18, S.MUTED))
			var h3 := S.hbox(10)
			h3.add_child(S.button("Save", func(): game.save_game(); toast("Saved", "good"), true, 140))
			h3.add_child(S.button("Fast-forward ×4" if game.time_scale <= 1.0 else "Normal speed", func(): game.toggle_fast(); open_phone("game"), false, 220))
			h3.add_child(S.button("Sleep till 07:00", func():
				close_panel(true)
				game.sleep_until(7.0), false, 200))
			v.add_child(h3)
			v.add_child(S.button("Settings", func(): _settings_panel(), false, 200))
			v.add_child(S.button("Save & quit to title", func():
				game.save_game()
				close_panel(true)
				get_tree().reload_current_scene(), false, 280))


static func _short(x: float) -> String:
	if x >= 1000.0:
		return EmpireData.money(x)
	return str(int(x))


func _settings_panel() -> void:
	var v := _open("Settings", 680, 520)
	var q := S.hbox(10)
	q.add_child(S.label("Graphics", 18, S.MUTED))
	for i in 3:
		q.add_child(S.button(["Battery", "Balanced", "Best"][i], func():
			Settings.quality = i
			Settings.apply()
			Settings.save()
			_settings_panel(), Settings.quality == i))
	v.add_child(q)
	var s := S.hbox(10)
	s.add_child(S.label("Look sensitivity", 18, S.MUTED))
	for k: float in [0.6, 1.0, 1.5]:
		s.add_child(S.button("%.1f×" % k, func():
			Settings.look_sensitivity = k
			Settings.save()
			_settings_panel(), is_equal_approx(Settings.look_sensitivity, k)))
	v.add_child(s)
	var hp := S.hbox(10)
	hp.add_child(S.label("Vibration", 18, S.MUTED))
	hp.add_child(S.button("On" if Settings.haptics else "Off", func():
		Settings.haptics = not Settings.haptics
		Settings.save()
		_settings_panel()))
	v.add_child(hp)
	for pair in [["Music", "music_volume"], ["Sound", "sfx_volume"]]:
		var vh := S.hbox(10)
		vh.add_child(_fixed(pair[0], 150, 18, S.MUTED))
		for lv: float in [0.0, 0.3, 0.6, 1.0]:
			var key: String = pair[1]
			vh.add_child(S.button(["Off", "Low", "Mid", "High"][[0.0, 0.3, 0.6, 1.0].find(lv)], func():
				Settings.set(key, lv)
				Settings.save()
				if game and game.audio:
					game.audio.apply_volumes()
				_settings_panel(), is_equal_approx(float(Settings.get(key)), lv), 90))
		v.add_child(vh)
	v.add_child(S.label("City Empire saves on this device only. No accounts, no ads, no tracking.", 15, S.MUTED))


# ---------------------------------------------------------- day report
func day_report(r: Dictionary) -> void:
	if _panel != null or game.state != "play":
		toast("Day %d closed: %s profit" % [int(r["day"]), EmpireData.money(float(r["profit"]))], "good" if float(r["profit"]) >= 0 else "bad")
		return
	var v := _open("Day %d — the books" % int(r["day"]), 900, 520)
	var list := S.vbox(6)
	for br in r["businesses"]:
		var pr := float(br["profit"])
		var tops: Array = []
		for pid in br["top"]:
			tops.append(String(EmpireData.product(pid).get("name", pid)))
		list.add_child(_row([_fixed(String(br["name"]), 200, 19, S.PAPER, "bold"),
			_fixed("takings %s" % EmpireData.money(float(br["revenue"])), 150),
			_fixed("costs %s" % EmpireData.money(float(br["cogs"]) + float(br["wages"]) + float(br["rent"]) + float(br["utilities"]) + float(br["fees"]) + float(br["theft"]) + float(br.get("other", 0.0))), 150, 16, S.MUTED),
			_fixed(("profit " if pr >= 0 else "loss ") + EmpireData.money(absf(pr)), 160, 19, S.GREEN if pr >= 0 else S.RED, "black"),
			_fixed("best: " + ", ".join(tops), 240, 14, S.MUTED)]))
	v.add_child(_scroll(list, 280))
	var tot := float(r["profit"])
	v.add_child(S.label(("Total profit " if tot >= 0 else "Total loss ") + EmpireData.money(absf(tot), true), 28,
		S.GREEN if tot >= 0 else S.RED, "black"))
	if float(r.get("personal", 0.0)) > 0.0:
		v.add_child(S.label("Rent from tenants: %s" % EmpireData.money(float(r["personal"]), true), 17, S.MUTED))
	var e := game.empire
	var today := CityLife.weather_def(e.weather)
	var fc := CityLife.weather_def(e.forecast)
	var ev_txt := ""
	for ev in e.events:
		if int(ev.get("until", 0)) >= e.day and not ev.get("kind") in ["burglary", "viral"]:
			ev_txt = "  ·  " + String(ev.get("text", ""))
	var fl := S.label("Today: %s (then %s)%s" % [today.get("name", ""), fc.get("name", ""), ev_txt], 16, S.AMBER)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.custom_minimum_size.x = 840
	v.add_child(fl)
	v.add_child(S.button("NEXT DAY", close_panel.bind(true), true, 200))


# ----------------------------------------------------------------- city
func _city_tab(v: VBoxContainer) -> void:
	var e := game.empire
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 40)
	var wd := CityLife.weather_def(e.weather)
	var fd := CityLife.weather_def(e.forecast)
	g.add_child(_stat("Today", String(wd.get("name", "")), S.AMBER))
	g.add_child(_stat("Tomorrow", String(fd.get("name", "")), S.MUTED))
	var rc := CityLife.rival_cfg()
	g.add_child(_stat(String(rc.get("name", "QuikSave")) + " stores", "gone" if e.flags.get("rival_gone", false) else str(e.rivals.size()),
		S.GREEN if e.flags.get("rival_gone", false) else S.RED))
	v.add_child(g)
	var tip := String(CityLife._weather_tip(e.weather))
	if tip != "":
		v.add_child(S.label(tip, 16, S.MUTED))
	var list := S.vbox(6)
	if not e.rivals.is_empty():
		list.add_child(S.label("RIVALS · buy a store out and its regulars become yours", 14, S.RED, "black"))
		for r in e.rivals:
			var u: Dictionary = game.unit_by_id.get(r["unit"], {})
			if u.is_empty():
				continue
			var near := 0
			for b: Business in e.businesses:
				if CityLife._dist(r["pos"], b.premises.get("pos", [])) < float(EmpireData.economy().get("competition_radius", 140.0)):
					near += 1
			list.add_child(_row([_fixed(String(r["name"]), 290, 17, S.PAPER, "bold"),
				_fixed("near %d of yours" % near if near > 0 else "no shop of yours nearby", 200, 15, S.AMBER if near > 0 else S.MUTED),
				_fixed(EmpireData.money(CityLife.rival_price(r)), 110, 17, S.PAPER, "bold"),
				S.button("Buy out", func(): open_rival(u), true, 120),
				S.button("GPS", func():
					game.set_gps(Premises.door_point(u), String(r["name"]))
					close_panel(true), false, 70)]))
	list.add_child(S.label("NEWS", 14, S.AMBER, "black"))
	var ns: Array = e.news.duplicate()
	ns.reverse()
	for n in ns:
		var col: Color = {"good": S.GREEN, "warn": S.AMBER, "bad": S.RED}.get(String(n.get("kind", "")), S.MUTED)
		var l := S.label(String(n.get("text", "")), 16, S.PAPER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 760
		list.add_child(_row([_fixed("Day %d" % int(n.get("day", 0)), 70, 14, col, "bold"), l]))
	v.add_child(_scroll(list, 400))


func open_rival(u: Dictionary) -> void:
	var e := game.empire
	var r := CityLife.rival_at(e, u["id"])
	if r.is_empty():
		return
	var rc := CityLife.rival_cfg()
	var v := _open(String(r["name"]), 760, 440)
	var d := EmpireData.district(r["district"])
	v.add_child(S.label("A %s store since day %d  ·  %s  ·  %d m²" % [rc.get("name", "QuikSave"), int(r.get("opened", 1)), d.get("name", ""), int(u.get("size", 0))], 17, S.MUTED))
	var txt := S.label("Every %s store takes shoppers from shops within %d m. Buy it out and you get the freehold, the fitted shop (empty shelves) and its regulars: it opens as yours at ★ 60.\n\nAfter %d buy-outs the chain stops expanding. Buy every last store and they leave the city." % [
		rc.get("name", "QuikSave"), int(EmpireData.economy().get("competition_radius", 140.0)), int(rc.get("retreat_after", 3))], 17, S.PAPER)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size.x = 700
	v.add_child(txt)
	var price := CityLife.rival_price(r)
	v.add_child(S.label("Price %s  ·  you have %s + company %s" % [EmpireData.money(price), EmpireData.money(e.personal_cash), EmpireData.money(e.company_cash)], 18, S.AMBER, "bold"))
	var h := S.hbox(12)
	var buy := S.button("BUY OUT · %s" % EmpireData.money(price), func():
		var err := game.buy_out_rival(u)
		if err != "":
			toast(err, "bad")
		else:
			close_panel(true), true, 320)
	buy.disabled = not e.can_afford(price)
	h.add_child(buy)
	h.add_child(S.button("Not now", close_panel.bind(true), false, 160))
	v.add_child(h)


## Shown once, when every goal is done.
func victory() -> void:
	var e := game.empire
	var v := _open("City Tycoon", 820, 520)
	var t := S.label("You built the empire.", 34, S.GREEN, "black")
	v.add_child(t)
	var txt := S.label("From one rented corner shop and an old hatchback to the biggest name in the city. %s is gone, and every street knows your shops." % CityLife.rival_cfg().get("name", "QuikSave"), 18, S.PAPER)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size.x = 760
	v.add_child(txt)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 40)
	g.add_theme_constant_override("v_separation", 10)
	g.add_child(_stat("Days", str(e.day)))
	g.add_child(_stat("Net worth", EmpireData.money(e.net_worth()), S.GREEN))
	g.add_child(_stat("Businesses", str(e.businesses.size())))
	g.add_child(_stat("Total takings", EmpireData.money(float(e.stats.get("revenue", 0.0)))))
	g.add_child(_stat("Customers served", str(int(e.stats.get("sales", 0)))))
	g.add_child(_stat("Staff", str(int(e.stat("staff")))))
	v.add_child(g)
	v.add_child(S.label("The city keeps running: play on as long as you like.", 16, S.MUTED))
	v.add_child(S.button("KEEP PLAYING", close_panel.bind(true), true, 260))


## Net worth over the last days (Bank tab).
class _NetChart extends Control:
	var reports: Array = []

	func _draw() -> void:
		var n := reports.size()
		if n < 2:
			return
		var lo := INF
		var hi := -INF
		for r in reports:
			lo = minf(lo, float(r.get("net_worth", 0.0)))
			hi = maxf(hi, float(r.get("net_worth", 0.0)))
		if hi - lo < 1.0:
			hi = lo + 1.0
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.04))
		var pts := PackedVector2Array()
		for i in n:
			var x := 10.0 + (w - 20.0) * float(i) / float(n - 1)
			var y := h - 18.0 - (h - 36.0) * (float(reports[i].get("net_worth", 0.0)) - lo) / (hi - lo)
			pts.append(Vector2(x, y))
		var fill := pts.duplicate()
		fill.append(Vector2(pts[-1].x, h - 18.0))
		fill.append(Vector2(pts[0].x, h - 18.0))
		draw_colored_polygon(fill, Color("#39c27f", 0.14))
		draw_polyline(pts, Color("#39c27f"), 2.5, true)
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(10, 14), "Net worth, last %d days: %s → %s" % [n, EmpireData.money(float(reports[0].get("net_worth", 0.0))),
			EmpireData.money(float(reports[-1].get("net_worth", 0.0)))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#9fb0ba"))
		# Profit bars along the bottom.
		var pm := 1.0
		for r in reports:
			pm = maxf(pm, absf(float(r.get("profit", 0.0))))
		for i in n:
			var p := float(reports[i].get("profit", 0.0))
			var x2 := 10.0 + (w - 20.0) * float(i) / float(n - 1)
			var bh := 12.0 * absf(p) / pm
			draw_rect(Rect2(x2 - 2.0, h - 6.0 - (bh if p > 0 else 0.0), 4.0, maxf(bh, 1.0)), Color("#39c27f") if p >= 0 else Color("#ec5a4a"))
