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
const Widgets = preload("res://src/empire/ui/empire_widgets.gd")

var game: EmpireGame
var hud: Control
var minimap: EmpireMinimap
var touch: EmpireTouch
var _money: Label
var _clock: Label
var _speed: Label
var _obj_title: Label
var _obj: Label
var _gps: Label
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
	# A soft vignette over the 3-D view, under everything else.
	var vig := ColorRect.new()
	vig.name = "Vignette"
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://src/empire/ui/shaders/vignette.gdshader")
	vig.material = vm
	root.add_child(vig)
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
	# Keep everything clear of the notch / Dynamic Island / home indicator
	# (in landscape the island sat on top of the minimap).
	_safe_root = root
	root.resized.connect(_apply_safe_area)
	_apply_safe_area.call_deferred()


var _safe_root: Control


## Insets the HUD by the display's safe area (none on desktop or in a window).
func _apply_safe_area() -> void:
	if _safe_root == null:
		return
	var inset := [0.0, 0.0, 0.0, 0.0]  # left, top, right, bottom
	var sa := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if sa.size.x > 0 and win.x > 0 and DisplayServer.screen_get_size() == win:
		var k := _safe_root.size / Vector2(win)
		inset = [sa.position.x * k.x, sa.position.y * k.y, (win.x - sa.end.x) * k.x, (win.y - sa.end.y) * k.y]
		# The home indicator inset is tall; the HUD only needs a little of it.
		inset[3] = minf(inset[3], 14.0)
	# (Only the HUD: panels and the title are centred, with full-screen dims
	# that must still reach the edges; floating labels track 3-D points.)
	hud.offset_left = inset[0]
	hud.offset_top = inset[1]
	hud.offset_right = -inset[2]
	hud.offset_bottom = -inset[3]


# ------------------------------------------------------------------ HUD
## HUD layout (inside the safe area), by corner:
##   top left    one translucent strip: your money · day and time · weather;
##               under it the objective (tap: its screen or route) and, only
##               inside one of your shops, that shop's line
##   top right   the minimap (big: roads, route, destination) with the next
##               turn under it; the phone button beside it
##   top centre  notifications
##   bottom      left: the stick; right: ACTION/JUMP on foot, the drive pad
##               in a car (EmpireTouch); the prompt and speed in the middle
## Company money and profit live in the phone (Finances), not on screen.
const HUD_ALPHA := 0.62
var _turn: PanelContainer
var _turn_icon: Control
var _turn_dist: Label
var _turn_sub: Label
var _obj_panel: PanelContainer
var _phone_btn: Button
var _drive_panel: PanelContainer


func _build_hud() -> void:
	# Money · time · weather (top left), one row.
	var m := _hud_panel(Vector2(16, 12), Vector2(0, 46), S.GREEN)
	_anchor(m, 0.0, 0.0, Vector2(16, 12), Vector2(0, 46))
	var mh := S.hbox(14)
	m.add_child(mh)
	_money = S.label("£0", 24, S.PAPER, "black")
	_clock = S.label("Mon 07:30", 19, S.PAPER, "bold")
	_speed = S.label("", 17, S.AMBER, "black")
	_weather_l = S.label("", 16, S.MUTED, "bold")
	mh.add_child(_money)
	mh.add_child(_dot())
	mh.add_child(_clock)
	mh.add_child(_speed)
	mh.add_child(_dot())
	mh.add_child(_weather_l)
	# Objective (under the strip): tap for its screen or its route.
	var o := _hud_panel(Vector2(16, 66), Vector2(0, 0), S.AMBER)
	_anchor(o, 0.0, 0.0, Vector2(16, 66), Vector2(0, 0))
	_obj_panel = o
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.gui_input.connect(func(ev: InputEvent):
		var tap: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed)
		if tap and game.state == "play" and _panel == null:
			o.accept_event()
			objective_action())
	var ov := S.vbox(0)
	o.add_child(ov)
	_obj_title = S.label("OBJECTIVE", 11, S.AMBER, "black")
	_obj = S.label("", 15, S.PAPER)
	_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj.custom_minimum_size.x = 300
	_gps = S.label("", 13, S.MUTED)
	ov.add_child(_obj_title)
	ov.add_child(_obj)
	ov.add_child(_gps)
	# The shop you're in (under the objective; only in your own shops).
	_strip_panel = _hud_panel(Vector2(16, 150), Vector2(0, 0))
	_anchor(_strip_panel, 0.0, 0.0, Vector2(16, 150), Vector2(0, 0))
	_strip = S.label("", 14, S.PAPER)
	_strip_panel.add_child(_strip)
	# (The two stack: the objective's height changes with its text.)
	var col := S.vbox(8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(col, 0.0, 0.0, Vector2(16, 66), Vector2(0, 0))
	hud.add_child(col)
	for pc in [o, _strip_panel]:
		hud.remove_child(pc)
		(pc as Control).position = Vector2.ZERO
		(pc as Control).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(pc)
	# Minimap (top right) and the next turn under it.
	minimap = EmpireMinimap.new()
	hud.add_child(minimap)
	_turn = _hud_panel(Vector2.ZERO, Vector2(0, 52))
	var tsb := _turn.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	tsb.bg_color = Color(Gps.COLOUR.darkened(0.55), 0.8)
	tsb.content_margin_left = 10
	tsb.content_margin_right = 12
	tsb.content_margin_top = 5
	tsb.content_margin_bottom = 5
	_turn.add_theme_stylebox_override("panel", tsb)
	var th := S.hbox(10)
	_turn.add_child(th)
	_turn_icon = _TurnIcon.new()
	_turn_icon.custom_minimum_size = Vector2(38, 38)
	th.add_child(_turn_icon)
	var tv := S.vbox(-2)
	th.add_child(tv)
	_turn_dist = S.label("", 20, S.PAPER, "black")
	_turn_sub = S.label("", 13, Color(S.PAPER, 0.8), "semibold")
	_turn_sub.clip_text = true
	_turn_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(_turn_dist)
	tv.add_child(_turn_sub)
	# Phone button (left of the minimap).
	_phone_btn = S.button("☰", func(): open_phone(), false, 52)
	_phone_btn.add_theme_font_size_override("font_size", 26)
	hud.add_child(_phone_btn)
	# Toasts (top centre).
	_toasts = S.vbox(8)
	_anchor(_toasts, 0.5, 0.0, Vector2(-200, 12), Vector2(400, 300))
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (tappable toasts stop clicks themselves)
	hud.add_child(_toasts)
	# Prompt (bottom centre).
	_prompt = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(S.INK, 0.72)
	psb.set_corner_radius_all(22)
	psb.border_color = Color(1, 1, 1, 0.1)
	psb.set_border_width_all(1)
	psb.content_margin_left = 8
	psb.content_margin_right = 18
	psb.content_margin_top = 6
	psb.content_margin_bottom = 6
	_prompt.add_theme_stylebox_override("panel", psb)
	_anchor(_prompt, 0.5, 1.0, Vector2(-200, -128), Vector2(400, 42))
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ph := S.hbox(10)
	_prompt.add_child(ph)
	_prompt_key = S.label(" E ", 16, S.INK, "black")
	var kb := StyleBoxFlat.new()
	kb.bg_color = S.AMBER
	kb.set_corner_radius_all(12)
	kb.content_margin_left = 7
	kb.content_margin_right = 7
	_prompt_key.add_theme_stylebox_override("normal", kb)
	_prompt_l = S.label("", 17, S.PAPER, "bold")
	ph.add_child(_prompt_key)
	ph.add_child(_prompt_l)
	hud.add_child(_prompt)
	# Carrying (bottom centre, over the prompt) and the speed pill (driving).
	_carry = S.label("", 15, S.PAPER, "bold")
	_anchor(_carry, 0.5, 1.0, Vector2(-450, -78), Vector2(900, 26))
	_carry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_carry.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_carry.add_theme_constant_override("outline_size", 6)
	hud.add_child(_carry)
	_drive_panel = _hud_panel(Vector2.ZERO, Vector2(0, 40))
	_anchor(_drive_panel, 0.5, 1.0, Vector2(-80, -58), Vector2(160, 40))
	_drive_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_drive = S.label("", 22, S.PAPER, "black")
	_drive.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drive_panel.add_child(_drive)
	_layout_hud()
	hud.resized.connect(_layout_hud)


func _dot() -> Label:
	return S.label("·", 18, Color(S.PAPER, 0.35), "black")


## Minimap size follows the screen: big enough to read roads and turns on a
## phone (≈ a third of the height), not a quarter of an iPad.
func minimap_size() -> float:
	var h := hud.size.y if hud.size.y > 0.0 else 720.0
	return clampf(h * 0.31, 190.0, 290.0)


func _layout_hud() -> void:
	var mm := minimap_size()
	_anchor(minimap, 1.0, 0.0, Vector2(-mm - 16.0, 12.0), Vector2(mm, mm))
	_anchor(_turn, 1.0, 0.0, Vector2(-mm - 16.0 + 6.0, mm + 18.0), Vector2(mm - 12.0, 52))
	_turn.size = Vector2(mm - 12.0, 52)
	_turn_sub.custom_minimum_size.x = mm - 80.0
	_anchor(_phone_btn, 1.0, 0.0, Vector2(-mm - 16.0 - 62.0, 12.0), Vector2(52, 52))
	# Objective text wraps before it reaches the toasts' column.
	_obj.custom_minimum_size.x = clampf(hud.size.x * 0.24, 260.0, 380.0)


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


func _hud_panel(pos: Vector2, size: Vector2, accent := Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# Translucent (no blur: it costs a full-screen pass on a phone).
	sb.bg_color = Color(S.INK, HUD_ALPHA)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.border_width_top = 1
	if accent.a > 0.0:
		# A coloured edge on the left (money green, objective amber).
		sb.border_color = accent
		sb.border_width_left = 4
		sb.border_width_top = 0
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.custom_minimum_size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(p)
	return p


func show_hud() -> void:
	minimap.game = game
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
	_clock.text = "%s %s" % [e.weekday(), e.clock_text()]
	var wname := String(CityLife.weather_def(e.weather).get("name", ""))
	var hr := e.hour()
	if (hr < 6.0 or hr >= 20.0) and wname in ["Sunny", "Heatwave"]:
		wname = "Clear night" if wname == "Sunny" else "Warm night"
	_weather_l.text = wname
	_speed.text = "×%d" % int(game.time_scale) if game.time_scale > 1.0 and game.floor == null and not game.in_vehicle() else ""
	_speed.visible = _speed.text != ""
	var ob := game.objective()
	_obj.text = String(ob[0])
	_obj_panel.visible = _obj.text != ""
	# The route: the next turn (big) and what's left (small) under the
	# minimap, purple as on both maps. One place for distances.
	var gps: Gps = game.gps
	if gps.active():
		var to := gps.label if gps.label != "" else "destination"
		if gps.message != "":
			_turn_dist.text = "No route"
			_turn_sub.text = gps.message
			(_turn_icon as _TurnIcon).dir = 2
		elif gps.turn.x != 0.0 and gps.turn.y < 600.0:
			var tm := maxi(int(roundf(gps.turn.y / 10.0) * 10.0), 10)
			_turn_dist.text = "%d m" % tm
			_turn_sub.text = "%s · %s to go" % ["Turn left" if gps.turn.x < 0.0 else "Turn right", gps.distance_text()]
			(_turn_icon as _TurnIcon).dir = -1 if gps.turn.x < 0.0 else 1
		else:
			_turn_dist.text = gps.distance_text()
			_turn_sub.text = "Ahead to " + to
			(_turn_icon as _TurnIcon).dir = 0
		_turn_icon.queue_redraw()
		_turn.visible = true
		_gps.text = ""
	else:
		_turn.visible = false
		_gps.text = "Tap for what to do" if (ob.size() > 3 and String(ob[3]) != "") else ""
	_gps.visible = _gps.text != ""
	_gps.add_theme_color_override("font_color", S.MUTED)
	# Prompt.
	var pr := game.spot_prompt()
	# In a car the exit is the action button (touch) or E (shown small):
	# no banner over the road.
	_prompt.visible = String(pr[0]) != "" and _panel == null and not (game.in_vehicle() and (touch.visible or not pr[1]))
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
	var cr = game.vehicle_node()
	if cr is Craft:
		_drive.text = (cr as Craft).hud_text()
		_drive_panel.visible = true
	elif game.driving != "":
		var car: Car = game.cars[game.driving]
		var v := e.vehicle(game.driving)
		var cargo := v["cargo"] as Stock
		_drive.text = "%d mph" % int(absf(car.forward_speed) * 2.237)
		if cargo.cases_used() > 0:
			_drive.text += "  ·  %d/%d cases" % [cargo.cases_used(), cargo.case_capacity]
		_drive_panel.visible = true
	else:
		_drive.text = ""
		_drive_panel.visible = false
	# Inside a shop the minimap shows nothing useful: it shrinks away while
	# you're on your shop floor (the route still shows under it when set).
	minimap.visible = game.floor == null or gps.active()
	_update_floats()


## A notification. With a ref it's tappable ("›"): it opens what it's about.
func toast(text: String, kind := "info", ref := {}) -> void:
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
	var l := S.label(text + ("  ›" if not ref.is_empty() else ""), 16, S.PAPER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 340
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not ref.is_empty():
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(ev: InputEvent):
			var tap: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed)
			if tap and game.state == "play":
				p.accept_event()
				open_ref(ref))
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


## The next-turn glyph: -1 left, 0 ahead, 1 right, 2 none (no route).
class _TurnIcon extends Control:
	var dir := 0

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, size.x * 0.5, Color(1, 1, 1, 0.14))
		var col := EmpireStyle.PAPER
		if dir == 2:
			draw_line(c + Vector2(-8, -8), c + Vector2(8, 8), EmpireStyle.AMBER, 4.0, true)
			draw_line(c + Vector2(8, -8), c + Vector2(-8, 8), EmpireStyle.AMBER, 4.0, true)
			return
		var s := float(dir)
		# Stem up from the bottom, then a bend toward the turn and the head.
		var a := c + Vector2(-5.0 * s, 13)
		var b := c + Vector2(-5.0 * s, -2) if dir != 0 else c + Vector2(0, -8)
		if dir == 0:
			a = c + Vector2(0, 13)
		draw_line(a, b, col, 5.0, true)
		if dir == 0:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -15), c + Vector2(8, -5), c + Vector2(-8, -5)]), col)
		else:
			var tip := c + Vector2(13.0 * s, -2)
			draw_line(b, tip - Vector2(6.0 * s, 0), col, 5.0, true)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-9.0 * s, -8), tip + Vector2(-9.0 * s, 8)]), col)


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
	var sc := TouchScroll.new()
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
	# A scrim from the left (the city stays bright on the right), and a
	# darker floor for the footer.
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.04, 0.06, 0.88))
	g.set_color(1, Color(0.02, 0.04, 0.06, 0.0))
	g.add_point(0.45, Color(0.02, 0.04, 0.06, 0.62))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(shade)
	var v := S.vbox(12)
	v.position = Vector2(84, 128)
	_title_root.add_child(v)
	var mark := S.label("M U S A   S T U D I O S   P R E S E N T S", 14, S.GOLD, "bold")
	v.add_child(mark)
	var t := S.label("CITY EMPIRE", 92, S.PAPER, "black")
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	t.add_theme_constant_override("shadow_offset_y", 4)
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_outline_size", 10)
	v.add_child(t)
	var rule := ColorRect.new()
	rule.color = S.GOLD
	rule.custom_minimum_size = Vector2(120, 3)
	v.add_child(rule)
	v.add_child(S.label("Start as the worker. Become the owner. Build the empire.", 22, Color(S.PAPER, 0.82)))
	var foot := S.label("v%s  ·  a Musa Studios game" % String(ProjectSettings.get_setting("application/config/version", "")), 14, Color(S.MUTED, 0.8))
	_anchor(foot, 0.0, 1.0, Vector2(84, -48), Vector2(500, 24))
	_title_root.add_child(foot)
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	v.add_child(gap)
	if has_save:
		var b := S.button("CONTINUE", func(): game.continue_game(), true, 360)
		v.add_child(b)
	v.add_child(S.button("NEW GAME", func():
		if has_save:
			_confirm_new()
		else:
			game.start_new(), not has_save, 360))
	v.add_child(S.button("SETTINGS", func(): _settings_panel(), false, 360))


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
		close_panel(true)
		if not game.empire.flags.has("styled"):
			# A moment's play first: the welcome paused the game before the
			# hero had landed from spawning (the editor would show the mid-air
			# balance pose).
			await get_tree().create_timer(0.7).timeout
			if not panel_open() and game.state == "play":
				open_style(true), true, 220))


# ------------------------------------------------------------ wholesale
func open_wholesale(unit: Dictionary) -> void:
	_cart_unit = unit
	_wholesale_page()


## The shop the wholesale page is stocking for: the one you picked, else
## your shop nearest to you.
var _ws_for := ""
## Showing the item-by-item list instead of the packs.
var _ws_custom := false


func _ws_target() -> Business:
	var e := game.empire
	var b := e.business(_ws_for) if _ws_for != "" else null
	if b != null:
		return b
	var best := INF
	for x: Business in e.businesses:
		var pp: Array = x.premises.get("pos", [0, 0, 0])
		var d := game.player.global_position.distance_to(Vector3(float(pp[0]), float(pp[1]), float(pp[2])))
		if d < best:
			best = d
			b = x
	return b


## Units already bought but not yet in a shop: in vehicles, in your arms,
## waiting on collection bays.
func _in_transit() -> Dictionary:
	var e := game.empire
	var out := {}
	var stocks: Array = [e.carried]
	for veh in e.vehicles:
		stocks.append(veh["cargo"])
	for w in e.pallets:
		stocks.append(e.pallets[w])
	for st: Stock in stocks:
		for pid in st.units:
			out[pid] = int(out.get(pid, 0)) + st.qty(pid)
	return out


## A one-tap stock pack: what it gets you, the cases, the price, one button.
func _pack_card(title: String, sub: String, plan: Dictionary, fee: float, verb: String, cb: Callable) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", S.row_bg())
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c := S.vbox(6)
	c.add_child(S.label(title, 21, S.PAPER, "black"))
	var l := S.label(sub, 15, S.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	c.add_child(l)
	var n := int(plan["count"])
	if n == 0:
		c.add_child(S.chip("Nothing needed: it's all there or on its way" if plan["short"] == "" else
			("No room left in your vehicle" if plan["short"] == "space" else "Not enough money for a case"), S.GREEN if plan["short"] == "" else S.AMBER))
	else:
		var lines := (plan["cases"] as Dictionary).size()
		c.add_child(S.label("%d case%s · %d product%s · %s%s" % [n, "" if n == 1 else "s", lines, "" if lines == 1 else "s",
			EmpireData.money(float(plan["cost"]) + fee, true), " incl. delivery" if fee > 0.0 else ""], 18, S.AMBER, "bold"))
		c.add_child(S.button("%s · %s" % [verb, EmpireData.money(float(plan["cost"]) + fee, true)], cb, true, 0))
	p.add_child(c)
	return p


func _wholesale_page() -> void:
	var unit := _cart_unit
	var v := _open(String(unit.get("name", "Wholesale")), 1000, 660)
	var e := game.empire
	var cap := 0
	var veh_name := "car"
	for veh in e.vehicles:
		if (veh["cargo"] as Stock).case_capacity > cap:
			cap = (veh["cargo"] as Stock).case_capacity
			veh_name = String(EmpireData.vehicle_model(veh["model"]).get("name", "car"))
	var waiting := 0
	if e.pallets.has(unit.get("id", "")):
		waiting = (e.pallets[unit["id"]] as Stock).cases_used()
	var b := _ws_target()
	var custom := _ws_custom or b == null
	if b != null and e.businesses.size() > 1:
		var who := HFlowContainer.new()
		who.add_theme_constant_override("h_separation", 8)
		who.add_theme_constant_override("v_separation", 6)
		who.add_child(S.label("STOCKING", 13, S.AMBER, "black"))
		for x: Business in e.businesses:
			who.add_child(S.chip_button(x.name, x == b, func(): _ws_for = x.id; _cart.clear(); _wholesale_page()))
		v.add_child(who)
	if not custom:
		var free := maxi(cap - waiting, 0)
		var budget := maxf(e.company_cash, 0.0) + maxf(e.personal_cash, 0.0)
		var tr := _in_transit()
		var top := e.restock_plan(b, false, free, budget, tr)
		var full := e.restock_plan(b, true, free, budget, tr)
		var info := S.label("Pick a pack for %s: it works out every line the shop sells, counting what's on the shelves, in the stockroom and already bought. Goods wait at the collection bay outside: back your %s up to it and press LOAD, then UNLOAD outside your shop." % [b.name, veh_name], 16, S.MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = 920
		v.add_child(info)
		var packs := S.hbox(14)
		var buy := func(plan: Dictionary) -> void:
			var err := game.buy_wholesale(_cart_unit, plan["cases"])
			if err != "":
				toast(err, "bad")
				return
			toast("Paid. %d cases waiting at the collection bay: back your vehicle up to it and press LOAD." % int(plan["count"]), "good")
			close_panel(true)
		if full["cases"] == top["cases"]:
			# (Cut to the same load by the vehicle or the money: one card.)
			packs.add_child(_pack_card("Restock pack", "A spread of every line the shop is short of, as much as you can take in one trip.", top, 0.0, "BUY",
				func(): buy.call(top)))
		else:
			packs.add_child(_pack_card("Top up the shelves", "Enough to fill every shelf, fridge and counter in the shop.", top, 0.0, "BUY",
				func(): buy.call(top)))
			packs.add_child(_pack_card("Full restock", "Full shelves and a refill of each line in the stockroom, so you don't need to come back tomorrow.", full, 0.0, "BUY",
				func(): buy.call(full)))
		v.add_child(packs)
		var why := ""
		if full["short"] == "space":
			why = "Packs are cut to %d cases: what your %s holds%s. Order the rest from the phone (Businesses › Stock), or come back." % [free, veh_name, " with %d already on the bay" % waiting if waiting > 0 else ""]
		elif full["short"] == "money":
			why = "Packs are cut to what you can afford right now."
		if why != "":
			var wl := S.label(why, 15, S.AMBER)
			wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			wl.custom_minimum_size.x = 920
			v.add_child(wl)
		v.add_child(S.spacer())
		var foot0 := S.hbox(12)
		foot0.add_child(S.button("Choose items yourself", func(): _ws_custom = true; _wholesale_page(), false, 0))
		foot0.add_child(S.spacer())
		_sack_truck_button(foot0)
		v.add_child(foot0)
		return
	var info2 := S.label("Trade prices by the case. Goods go to the collection bay outside — your biggest vehicle holds %d cases." % cap, 16, S.MUTED)
	info2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info2.custom_minimum_size.x = 900
	v.add_child(info2)
	var list := S.vbox(6)
	var cats := EmpireData.categories()
	for cat in cats:
		var pids: Array = EmpireData.product_ids().filter(func(q): return EmpireData.product(q)["cat"] == cat and (b == null or b.sells(q)))
		if pids.is_empty():
			continue
		list.add_child(S.label(String(cats[cat]["name"]).to_upper(), 14, Color.from_string(cats[cat]["colour"], S.AMBER), "black"))
		for pid in pids:
			var p := EmpireData.product(pid)
			var n := int(_cart.get(pid, 0))
			var unit_cost := EmpireData.unit_cost(pid)
			var swatch := ColorRect.new()
			swatch.color = EmpireData.colour(pid)
			swatch.custom_minimum_size = Vector2(18, 28)
			var note := ""
			if b != null:
				note = "  · %d in the shop" % (b.shelf_qty(pid) + b.backroom.qty(pid))
			elif p["fixture"] == "fridge":
				note = "  · fridge"
			list.add_child(_row([swatch, _fixed(String(p["name"]) + note, 330),
				_fixed("%d per case" % int(p["case_qty"]), 110, 15, S.MUTED),
				_fixed(EmpireData.money(e.case_price(pid), true), 90, 17, S.PAPER, "bold"),
				_fixed("%s each · RRP %s" % [EmpireData.money(unit_cost, true), EmpireData.money(float(p["rrp"]), true)], 210, 14, S.MUTED),
				S.button("−", func(): _cart_add(pid, -1), false, 46),
				_fixed(str(n), 34, 20, S.AMBER if n > 0 else S.PAPER, "black"),
				S.button("+", func(): _cart_add(pid, 1), false, 46)]))
	v.add_child(_scroll(list, 400))
	var total := 0.0
	var cases := 0
	for pid in _cart:
		total += e.case_price(pid) * int(_cart[pid])
		cases += int(_cart[pid])
	var foot := S.hbox(14)
	foot.add_child(S.label("%d case%s · %s" % [cases, "" if cases == 1 else "s", EmpireData.money(total, true)], 24, S.PAPER, "black"))
	foot.add_child(S.label("You have %s + company %s" % [EmpireData.money(e.personal_cash), EmpireData.money(e.company_cash)], 15, S.MUTED))
	foot.add_child(S.spacer())
	if b != null:
		foot.add_child(S.button("Packs", func(): _ws_custom = false; _wholesale_page()))
	_sack_truck_button(foot)
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


func _sack_truck_button(row: HBoxContainer) -> void:
	var e := game.empire
	if e.carried.case_capacity >= 6:
		return
	row.add_child(S.button("Sack truck £120 (carry 6)", func():
		if e.pay(120.0, "equipment", "Sack truck"):
			e.carried.case_capacity = 6
			toast("Sack truck: you can carry 6 cases now", "good")
			_wholesale_page()
		else:
			toast("Not enough money", "bad")))


func _cart_add(pid: String, d: int) -> void:
	_cart[pid] = clampi(int(_cart.get(pid, 0)) + d, 0, 99)
	if int(_cart[pid]) == 0:
		_cart.erase(pid)
	_wholesale_page()


# ------------------------------------------------------------- property
var _rent_type := "convenience"


## A shop unit to let. `remote`: inspected from the phone – renting or
## buying then goes through the letting agent (a stated fee); at the
## door it's free.
func open_property(u: Dictionary, remote := false) -> void:
	game.empire.flags["inspected_property"] = true
	if not game.empire.businesses.is_empty():
		game.empire.flags["viewed_expansion"] = true
	var d := EmpireData.district(u["district"])
	var v := _open(String(u.get("shop_name", "Shop unit")), 900, 600)
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
	# What to open here.
	var types := S.hbox(8)
	for tid in EmpireData.business_types():
		var td := EmpireData.business_type(tid)
		if not td.get("playable", false):
			continue
		types.add_child(S.button("%s %s" % [td.get("icon", ""), td.get("name", tid)], func():
			_rent_type = tid
			open_property(u), tid == _rent_type, 0))
	v.add_child(S.label("OPEN AS", 13, S.AMBER, "black"))
	v.add_child(types)
	var td2 := EmpireData.business_type(_rent_type)
	var sells := []
	for c in td2.get("categories", []):
		sells.append(String((EmpireData.file("products").get("categories", {}) as Dictionary).get(c, {}).get("name", c)))
	v.add_child(S.label("%s: sells %s · open %02d:00–%02d:00" % [td2.get("name", ""), ", ".join(sells), int(td2.get("open", 7)), int(td2.get("close", 22))], 15, S.MUTED))
	var fee_r := EmpireGame.agent_fee(float(u["rent"]) * 3.0) if remote else 0.0
	var fee_b := EmpireGame.agent_fee(float(u["price"])) if remote else 0.0
	var dist := game.player.global_position.distance_to(Premises.door_point(u))
	v.add_child(S.label("You have %s + company %s%s" % [EmpireData.money(game.empire.personal_cash), EmpireData.money(game.empire.company_cash),
		("  ·  %s away · through the agent: +%s rent / +%s buy" % [_dist_text(dist), EmpireData.money(fee_r), EmpireData.money(fee_b)]) if remote else ""], 15, S.MUTED))
	var h := S.hbox(12)
	var rent := S.button("RENT · %s deposit%s" % [EmpireData.money(float(u["rent"]) * 3.0), " + fee" if remote else ""], func():
		var err := game.rent_unit(u, false, _rent_type, fee_r)
		if err != "":
			toast(err, "bad")
		else:
			close_panel(true), true, 300)
	rent.disabled = not game.empire.can_afford(float(u["rent"]) * 3.0 + fee_r)
	h.add_child(rent)
	var buy := S.button("BUY · %s%s" % [EmpireData.money(float(u["price"])), " + fee" if remote else ""], func():
		var err := game.rent_unit(u, true, _rent_type, fee_b)
		if err != "":
			toast(err, "bad")
		else:
			close_panel(true), false, 240)
	buy.disabled = not game.empire.can_afford(float(u["price"]) + fee_b)
	h.add_child(buy)
	if remote:
		h.add_child(S.button("GPS there", func():
			game.set_gps(Premises.door_point(u), String(u.get("shop_name", "Shop")), {"kind": "unit", "id": String(u["id"])})
			close_panel(true), false, 150))
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
	var v := _open("Stockroom · %d/%d cases" % [b.backroom.cases_used(), b.backroom.case_capacity], 720, 560)
	# The whole job in one go: every shelf topped up from here.
	var gaps := 0
	for s0: Dictionary in b.slots:
		if String(s0["product"]) != "" and b.backroom.qty(s0["product"]) > 0:
			gaps += int(s0["cap"]) - int(s0["qty"])
	for pid0 in b.backroom.units:
		if b.shelf_qty(pid0) == 0 and b.slot_for(pid0) >= 0:
			gaps += 1
	var top := S.hbox(12)
	if gaps > 0:
		top.add_child(S.button("FILL THE SHELVES", func():
			var moved := game.empire.restock_from_backroom(b, 99999)
			_refresh_interior(b)
			toast("Filled the shelves: %d item%s put out" % [moved, "" if moved == 1 else "s"] if moved > 0 else "Nothing here fits on the shelves", "good" if moved > 0 else "info")
			open_rack(b), true, 260))
		top.add_child(S.label("Puts out everything that fits,\nemptiest shelves first.", 15, S.MUTED))
	else:
		top.add_child(S.label("The shelves are as full as this stockroom can make them." if not b.backroom.is_empty() else "Nothing in the stockroom: order a pack from the phone (Stock & orders).", 16, S.MUTED))
	v.add_child(top)
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
		# What the decision means: profit from ten shoppers who want it, and
		# the price that would make the most (from the same demand model).
		var per10 := 10.0 * DemandModel.buy_share(b, pid, pr) * (pr - cost)
		var best_p := pr
		var best_v := -INF
		var tp := maxf(cost, 0.05)
		while tp <= EmpireData.rrp(pid) * 2.2:
			var tv := DemandModel.buy_share(b, pid, tp) * (tp - cost)
			if tv > best_v:
				best_v = tv
				best_p = tp
			tp += 0.05
		share.text = "About %d%% of shoppers here would pay this: ~%s profit per 10 who want it.\n%s" % [
			int(DemandModel.buy_share(b, pid, pr) * 100.0), EmpireData.money(per10, true),
			"That's about the best price here." if absf(best_p - pr) < 0.11 else "Most profit here at about %s (%s per 10)." % [
				EmpireData.money(best_p, true), EmpireData.money(10.0 * best_v, true)]]
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
	var fee := e.delivery_fee(b)
	var when := "by 06:00 tomorrow" if e.minute >= 360.0 else "by 06:00"
	var head := S.label("Delivered to the stockroom %s (%s)%s" % [when, "free with your driver" if fee == 0.0 else "%s delivery" % EmpireData.money(fee),
		" · your manager orders a full restock every night at 21:05" if b.has_role("manager") else ""], 16, S.MUTED)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size.x = 980
	v.add_child(head)
	if not _ws_custom:
		var budget := maxf(e.company_cash, 0.0) + maxf(e.personal_cash, 0.0) - fee
		var top := e.restock_plan(b, false, 9999, budget)
		var full := e.restock_plan(b, true, 9999, budget)
		var order := func(plan: Dictionary) -> void:
			var err := e.order_delivery(b, plan["cases"])
			if err != "":
				toast(err, "bad")
			else:
				toast("Ordered %d cases: in the stockroom %s" % [int(plan["count"]), when], "good")
			open_manage(b, "stock")
		var packs := S.hbox(14)
		packs.add_child(_pack_card("Top up the shelves", "Every shelf, fridge and counter filled, counting what's already in the stockroom and on order.", top, fee, "ORDER",
			func(): order.call(top)))
		packs.add_child(_pack_card("Full restock", "Full shelves and a refill of each line in the stockroom. A stacker puts it out; without one, use the stockroom's FILL THE SHELVES.", full, fee, "ORDER",
			func(): order.call(full)))
		v.add_child(packs)
		var lines := S.vbox(4)
		lines.add_child(S.label("WHAT THE SHOP HAS", 13, S.AMBER, "black"))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 6)
		var targets := b.shelf_targets()
		for pid in b.sellable():
			if not targets.has(pid):
				continue
			var have := b.shelf_qty(pid) + b.backroom.qty(pid)
			var fill := float(have) / float(maxi(int(targets[pid]), 1))
			flow.add_child(S.chip("%s %d" % [String(EmpireData.product(pid)["name"]), have], S.GREEN if fill >= 0.75 else (S.AMBER if fill > 0.0 else S.RED)))
		lines.add_child(flow)
		v.add_child(_scroll(lines, 170))
		var foot := S.hbox(12)
		foot.add_child(S.button("Choose items yourself", func(): _ws_custom = true; open_manage(b, "stock")))
		v.add_child(foot)
		return
	var list := S.vbox(6)
	for pid in b.sellable():
		var p := EmpireData.product(pid)
		var pending := 0
		for o in b.orders:
			pending += int(o["units"].get(pid, 0))
		var n := int(_cart.get("o_" + pid, 0))
		list.add_child(_row([_fixed(String(p["name"]), 230, 17, S.PAPER, "bold"),
			_fixed("shelf %d" % b.shelf_qty(pid), 80, 15, S.MUTED),
			_fixed("room %d" % b.backroom.qty(pid), 80, 15, S.MUTED),
			_fixed("coming %d" % pending if pending > 0 else "", 100, 15, S.BLUE),
			_fixed("%s/case" % EmpireData.money(e.case_price(pid), true), 110, 15, S.MUTED),
			S.button("−", func(): _cart["o_" + pid] = maxi(n - 1, 0); open_manage(b, "stock"), false, 46),
			_fixed(str(n), 30, 19, S.AMBER if n > 0 else S.PAPER, "black"),
			S.button("+", func(): _cart["o_" + pid] = n + 1; open_manage(b, "stock"), false, 46)]))
	v.add_child(_scroll(list, 380))
	var order2 := {}
	var total := fee
	for k in _cart:
		if String(k).begins_with("o_") and int(_cart[k]) > 0:
			order2[String(k).trim_prefix("o_")] = int(_cart[k])
			total += e.case_price(String(k).trim_prefix("o_")) * int(_cart[k])
	var h := S.hbox(12)
	h.add_child(S.button("Packs", func(): _ws_custom = false; open_manage(b, "stock")))
	h.add_child(S.label("Order total %s" % EmpireData.money(total if not order2.is_empty() else 0.0, true), 20, S.PAPER, "black"))
	h.add_child(S.spacer())
	h.add_child(S.button("PLACE ORDER", func():
		var err := e.order_delivery(b, order2)
		if err != "":
			toast(err, "bad")
		else:
			toast("Ordered: arriving %s" % when, "good")
			for k in _cart.keys():
				if String(k).begins_with("o_"):
					_cart.erase(k)
		open_manage(b, "stock"), true, 200))
	v.add_child(h)


## Staff tab filter: a role id, or "" for everyone.
var _staff_role := ""
const ROLE_JOBS := {"cashier": ["Till", "only while you serve"], "stocker": ["Shelves", "you refill them"],
	"cleaner": ["Cleaning", "gets dirty"], "manager": ["Re-orders", "you order stock"], "driver": ["Collections", "delivery fee"]}


func _skill_dots(n: int) -> String:
	return "●".repeat(n) + "○".repeat(5 - n)


func _m_staff(v: VBoxContainer, b: Business) -> void:
	var e := game.empire
	var roles: Array = b.type_def().get("roles", ROLE_JOBS.keys())
	var list := S.vbox(6)
	# Every job: who covers it, or a one-tap hire of today's best for it.
	list.add_child(S.label("JOBS", 14, S.AMBER, "black"))
	var jobs := GridContainer.new()
	jobs.columns = 2
	jobs.add_theme_constant_override("h_separation", 10)
	jobs.add_theme_constant_override("v_separation", 6)
	for r: String in roles:
		var job: Array = ROLE_JOBS.get(r, [r, ""])
		var cell := S.hbox(8)
		cell.custom_minimum_size.x = 490
		var tag: PanelContainer
		if b.has_role(r):
			var who: Array = b.staff_with(r).map(func(x): return String(x["name"]).get_slice(" ", 0))
			tag = S.chip("✓ %s: %s" % [job[0], ", ".join(who)], S.GREEN)
			cell.add_child(tag)
		else:
			tag = S.chip("✗ %s – %s" % [job[0], job[1]], S.MUTED)
			cell.add_child(tag)
			cell.add_child(S.spacer())
			var best := e.best_candidate(r)
			if not best.is_empty():
				cell.add_child(S.button("Hire %s %s · %s/h" % [String(best["name"]).get_slice(" ", 0), _skill_dots(int(best["skill"])),
					EmpireData.money(float(best["wage"]), true)], func(): game.hire(b, best); open_manage(b, "staff"), true, 0))
		tag.custom_minimum_size.x = 210
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		jobs.add_child(cell)
	list.add_child(jobs)
	list.add_child(S.label("ON YOUR TEAM", 14, S.AMBER, "black"))
	if b.staff.is_empty():
		list.add_child(S.label("Just you. Hire people to take over the routine work.", 16, S.MUTED))
	for st in b.staff:
		list.add_child(_row([_fixed(String(st["name"]) + (" · off today" if st.get("off", false) else ""), 200, 18, S.AMBER if st.get("off", false) else S.PAPER, "bold"),
			_fixed(String(EmpireData.role(st["role"]).get("name", "")), 150, 16, S.MUTED),
			_fixed("skill " + _skill_dots(int(st["skill"])), 140, 15, S.AMBER),
			_fixed(Staff.trait_names(st), 150, 14, S.MUTED),
			_fixed("%s/h" % EmpireData.money(float(st["wage"]), true), 90, 16),
			S.button("Let go", func(): game.fire(b, st); open_manage(b, "staff"), false, 100)]))
	# Today's job seekers, by role, best first.
	var seekers: Array = e.candidates.filter(func(c): return c["role"] in roles)
	var head := S.hbox(8)
	head.add_child(S.label("LOOKING FOR WORK TODAY · %d" % seekers.size(), 14, S.AMBER, "black"))
	list.add_child(head)
	var filt := HFlowContainer.new()
	filt.add_theme_constant_override("h_separation", 8)
	filt.add_theme_constant_override("v_separation", 6)
	if not _staff_role in roles:
		_staff_role = ""
	filt.add_child(S.chip_button("Everyone %d" % seekers.size(), _staff_role == "", func(): _staff_role = ""; open_manage(b, "staff")))
	for r: String in roles:
		var n := seekers.filter(func(c): return c["role"] == r).size()
		filt.add_child(S.chip_button("%s %d" % [String(EmpireData.role(r).get("name", r)), n], _staff_role == r, func(): _staff_role = r; open_manage(b, "staff")))
	list.add_child(filt)
	var shown: Array = seekers.filter(func(c): return _staff_role == "" or c["role"] == _staff_role)
	shown.sort_custom(func(x, y):
		if x["role"] != y["role"]:
			return roles.find(x["role"]) < roles.find(y["role"])
		if int(x["skill"]) != int(y["skill"]):
			return int(x["skill"]) > int(y["skill"])
		return float(x["wage"]) < float(y["wage"]))
	if shown.is_empty():
		list.add_child(S.label("Nobody left for that job today: a new lot come looking tomorrow.", 16, S.MUTED))
	for c in shown:
		var r := EmpireData.role(c["role"])
		var traits := Staff.trait_names(c)
		var why := S.label(traits if traits != "" else String(r.get("desc", "")), 14, S.MUTED)
		why.custom_minimum_size.x = 250
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(_row([_fixed(String(c["name"]), 180, 18, S.PAPER, "bold"),
			_fixed(String(r.get("name", "")), 140, 16, S.BLUE, "bold"),
			_fixed(_skill_dots(int(c["skill"])), 80, 15, S.AMBER), why, S.spacer(),
			_fixed("%s/h" % EmpireData.money(float(c["wage"]), true), 80, 16),
			S.button("Hire", func(): game.hire(b, c); open_manage(b, "staff"), true, 90)]))
	v.add_child(_scroll(list, 430))
	var hrs := b.hours()
	v.add_child(S.label(("Shifts cover opening hours (%02d:00–%02d:00): a %s/h team costs about %s a day. " % [int(hrs.x), int(hrs.y),
		EmpireData.money(b.wages_per_hour(), true), EmpireData.money(b.wages_per_hour() * (hrs.y - hrs.x))] if not b.staff.is_empty() else "")
		+ "New people look for work every morning.", 15, S.MUTED))


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
const PHONE_TABS := [["home", "Home"], ["businesses", "Businesses"], ["map", "Map"], ["vehicles", "Vehicles"],
	["property", "Property"], ["bank", "Finances"], ["company", "Corporate"], ["more", "More"]]
## Under More (the rail highlights More; a back button returns to it).
const MORE_TABS := [["style", "Style", "Your character: face, hair and clothes"], ["city", "City", "Weather, rivals, news and the market"], ["goals", "Goals", "Your career, chapter by chapter"],
	["game", "Game", "Save, speed, sleep and settings"]]
const PHONE_SUB := {"home": "Your empire at a glance: what needs you, and where to go next",
	"businesses": "Every shop, office and the club: status, stock, staff and money",
	"company": "Brand, head office, office companies, the football club and marketing",
	"city": "Weather, rivals and the news", "map": "Tap a place for its card · tap a street for a waypoint",
	"bank": "Accounts, profit, loans and the ledger", "vehicles": "Where your vehicles are, and getting to them",
	"property": "Shops to let, businesses for sale, office floors and homes", "goals": "Your career, chapter by chapter",
	"game": "Save, speed and settings", "more": "Everything else"}


## The phone: a nav rail with line icons on the left, the tab's title and
## your money across the top, the tab's content below (returned).
func _phone_shell(tab: String) -> VBoxContainer:
	close_panel(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var e := game.empire
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.42)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_root.add_child(dim)
	var W := 1220.0
	var H := 690.0
	_panel = PanelContainer.new()
	var psb := (S.theme().get_stylebox("panel", "PanelContainer") as StyleBoxFlat).duplicate() as StyleBoxFlat
	psb.content_margin_left = 0
	psb.content_margin_top = 0
	psb.content_margin_bottom = 0
	psb.content_margin_right = 0
	_panel.add_theme_stylebox_override("panel", psb)
	_panel.custom_minimum_size = Vector2(W, H)
	_anchor(_panel, 0.5, 0.5, -Vector2(W, H) * 0.5, Vector2(W, H))
	_panel_root.add_child(_panel)
	var row := S.hbox(0)
	_panel.add_child(row)
	# The rail.
	var rail := PanelContainer.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0, 0, 0, 0.22)
	rsb.corner_radius_top_left = 20
	rsb.corner_radius_bottom_left = 20
	rsb.content_margin_left = 14
	rsb.content_margin_right = 14
	rsb.content_margin_top = 20
	rsb.content_margin_bottom = 16
	rail.add_theme_stylebox_override("panel", rsb)
	rail.custom_minimum_size.x = 214
	row.add_child(rail)
	var rv := S.vbox(4)
	rail.add_child(rv)
	var who := S.hbox(10)
	var badge := _brand_badge(40)
	who.add_child(badge)
	var wv := S.vbox(-2)
	var cname := String(e.brand.get("name", ""))
	wv.add_child(S.label(cname if cname != "" else "Your company", 17, S.PAPER, "black"))
	wv.add_child(S.label("Day %d · %s %s" % [e.day, e.weekday(), e.clock_text()], 13, S.MUTED))
	who.add_child(wv)
	rv.add_child(who)
	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	rv.add_child(gap)
	var in_more := MORE_TABS.any(func(t): return t[0] == tab)
	for t in PHONE_TABS:
		rv.add_child(_rail_button(t[0], t[1], t[0] == tab or (t[0] == "more" and in_more)))
	# Content.
	var body := MarginContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		body.add_theme_constant_override("margin_" + side, 24)
	body.add_theme_constant_override("margin_top", 18)
	body.add_theme_constant_override("margin_bottom", 18)
	row.add_child(body)
	var v := S.vbox(14)
	body.add_child(v)
	var head := S.hbox(14)
	var hv := S.vbox(-2)
	var title := ""
	for t in PHONE_TABS + MORE_TABS:
		if t[0] == tab:
			title = t[1]
	if in_more:
		head.add_child(S.button("‹", func(): open_phone("more"), false, 52))
	hv.add_child(S.label(title, 30, S.PAPER, "black"))
	hv.add_child(S.label(String(PHONE_SUB.get(tab, "")), 15, S.MUTED))
	head.add_child(hv)
	head.add_child(S.spacer())
	head.add_child(_money_pill("Savings", e.personal_cash, S.PAPER))
	head.add_child(_money_pill("Company", e.company_cash, S.RED if e.company_cash < 0.0 else S.PAPER))
	head.add_child(_money_pill("Net worth", e.net_worth(), S.GREEN))
	head.add_child(S.button("✕", close_panel.bind(true), false, 52))
	v.add_child(head)
	var rule := ColorRect.new()
	rule.color = S.LINE
	rule.custom_minimum_size.y = 1
	v.add_child(rule)
	return v


func _rail_button(key: String, text: String, on: bool) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 50)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(S.AMBER, 0.14) if on else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 52
	if on:
		sb.border_color = S.AMBER
		sb.border_width_left = 3
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = Color(S.AMBER, 0.2) if on else Color(1, 1, 1, 0.05)
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.text = text
	b.add_theme_font_override("font", S.font("bold" if on else "semibold"))
	b.add_theme_font_size_override("font_size", 18)
	var col := S.AMBER if on else Color(S.PAPER, 0.78)
	for cn in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(cn, col if cn == "font_color" else (S.AMBER if on else S.PAPER))
	var ic := Widgets.Icon.new(key, col, 24)
	ic.position = Vector2(16, 13)
	ic.size = Vector2(24, 24)
	b.add_child(ic)
	b.pressed.connect(func():
		if Time.get_ticks_msec() < S.tap_block_until:
			return
		Sfx.play("click", -12.0)
		open_phone(key))
	return b


func _money_pill(title: String, amount: float, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.045)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", sb)
	var v := S.vbox(-3)
	v.add_child(S.label(title.to_upper(), 11, S.MUTED, "black"))
	v.add_child(S.label(EmpireData.money(amount), 20, col, "black"))
	p.add_child(v)
	return p


## Your logo: the roundel in your brand's colours (a plain CE mark before
## you've made one).
func _brand_badge(px: float) -> Control:
	var e := game.empire
	var c := _Roundel.new()
	c.custom_minimum_size = Vector2(px, px)
	if not e.brand.is_empty():
		c.ident = ShopStyle.house_ident(e.brand)
	return c


class _Roundel extends Control:
	var ident := {}

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		var prim: Color = ident.get("primary", EmpireStyle.INK2.lightened(0.15))
		var acc: Color = ident.get("accent", EmpireStyle.AMBER)
		draw_circle(c, r, acc)
		draw_circle(c, r * 0.84, prim)
		var t := String(ident.get("initial", "CE")) if not ident.is_empty() else "CE"
		var f: Font = ShopStyle.font(String(ident.get("face", ""))) if not ident.is_empty() else EmpireStyle.font("black")
		var fs := int(r * (0.95 if t.length() == 1 else 0.7))
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, acc)


func open_phone(tab := "home", focus := {}) -> void:
	var e := game.empire
	# (Onboarding: these count as having looked.)
	if tab == "map":
		e.flags["opened_map"] = true
	elif tab == "bank":
		e.flags["viewed_finances"] = true
	elif tab == "property" and not e.businesses.is_empty():
		e.flags["viewed_expansion"] = true
	if tab == "style":
		open_style()
		return
	var v := _phone_shell(tab)
	match tab:
		"home":
			_home_tab(v)
		"businesses":
			_portfolio_tab(v)
		"more":
			_more_tab(v)
		"city":
			_city_tab(v)
		"company":
			_company_tab(v)
		"map":
			var m := EmpireMap.new()
			m.game = game
			m.custom_minimum_size = Vector2(948, 520)
			v.add_child(m)
			if not focus.is_empty():
				m.select_ref.call_deferred(focus)
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
			_vehicles_tab(v)
		"property":
			_property_tab(v)
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
			# TestFlight builds: money to try things out with (remove for release).
			v.add_child(S.button("TESTER · add £1,000,000", func():
				e.personal_cash += 1000000.0
				e._book("personal", 1000000.0, "other", "Tester money")
				e.changed.emit()
				toast("£1,000,000 added to your personal account", "good")
				open_phone("game"), false, 340))
			v.add_child(S.button("Save & quit to title", func():
				game.save_game()
				close_panel(true)
				get_tree().reload_current_scene(), false, 280))
			# Attribution the character's source assets ask for (art/hero/CREDITS.md).
			v.add_child(S.label("CREDITS", 14, S.AMBER, "black"))
			var cr := S.label("Character built on MakeHuman (CC0) · Hooded sweat jacket · Elvaerwyn · CC BY · " +
				"Running shoes 01 · punkduck · CC BY 3.0 · Cargo pants · Cortu Johnstone · CC0 · Gloves · MRT · CC0 · " +
				"Shop typefaces · SIL Open Font License", 13, S.MUTED)
			cr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cr.custom_minimum_size.x = 640
			v.add_child(cr)


# ------------------------------------------------------------ company
func _card(minw := 0.0) -> Array:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(16)
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.set_border_width_all(1)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.x = minw
	var v := S.vbox(10)
	p.add_child(v)
	return [p, v]


func _section(icon: String, text: String, col := S.AMBER) -> HBoxContainer:
	var h := S.hbox(8)
	h.add_child(Widgets.Icon.new(icon, col, 20))
	h.add_child(S.label(text.to_upper(), 14, col, "black"))
	return h


func _company_tab(v: VBoxContainer) -> void:
	var e := game.empire
	var top := S.hbox(16)
	v.add_child(top)
	# Brand card.
	var bc := _card(450)
	top.add_child(bc[0])
	var bv: VBoxContainer = bc[1]
	bv.add_child(_section("brand", "Your brand"))
	var pv := Widgets.BrandPreview.new()
	pv.ident = ShopStyle.house_ident(e.brand if not e.brand.is_empty() else ShopStyle.default_house(""))
	pv.custom_minimum_size = Vector2(412, 170)
	bv.add_child(pv)
	if e.brand.is_empty():
		bv.add_child(S.label("Your shops each wear their own sign. Create a brand and every one trades under your name.", 15, S.MUTED))
		bv.get_child(-1).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bv.add_child(S.button("Create your brand", func(): open_brand(), true))
	else:
		var hb := S.hbox(10)
		hb.add_child(S.label("%d shop%s wear it" % [e.businesses.size(), "" if e.businesses.size() == 1 else "s"], 15, S.MUTED))
		hb.add_child(S.spacer())
		hb.add_child(S.button("Edit brand", func(): open_brand(), false, 150))
		bv.add_child(hb)
	# Head office card.
	var hc := _card(0)
	(hc[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(hc[0])
	var hv: VBoxContainer = hc[1]
	hv.add_child(_section("tower", "Head office · Meridian Tower"))
	var tier := e.hq_tier()
	if tier > 0:
		var d := e.hq_def(tier)
		hv.add_child(S.label(String(d["name"]), 26, S.PAPER, "black"))
		hv.add_child(_perks(d))
		hv.add_child(S.label("Upkeep %s/day" % EmpireData.money(float(d["upkeep"])), 15, S.MUTED))
	else:
		hv.add_child(S.label("No head office yet", 24, S.PAPER, "black"))
		var t := S.label("Lease a floor of the city's tallest tower: bulk buying for every shop, and a marketing desk.", 15, S.MUTED)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hv.add_child(t)
	var nd := e.hq_def(tier + 1)
	if not nd.is_empty():
		var why := e.hq_block(tier + 1)
		var nh := S.hbox(10)
		nh.add_child(S.label("Next: %s · %s" % [nd["name"], EmpireData.money(float(nd["price"]))], 16, S.AMBER, "bold"))
		hv.add_child(nh)
		hv.add_child(_progress(float(e.businesses.size()), float(nd["shops"]), "%d / %d shops" % [e.businesses.size(), int(nd["shops"])]))
		if why != "":
			hv.add_child(S.label(why, 14, S.MUTED))
	var gh := S.hbox(10)
	gh.add_child(S.button("GPS to the tower", func():
		var u := game.hq_unit()
		if not u.is_empty():
			game.set_gps(Premises.door_point(u), "Meridian Tower")
		close_panel(true), tier == 0, 220))
	hv.add_child(gh)
	# Marketing.
	v.add_child(_section("megaphone", "Marketing"))
	var run := e.campaign_running()
	var list := S.vbox(6)
	for c in EmpireData.hq().get("campaigns", []):
		var why2 := e.campaign_block(c["id"])
		var live: bool = run.get("id", "") == c["id"]
		var row: Array = [_fixed(String(c["name"]), 200, 18, S.PAPER, "bold"),
			_fixed(String(c["blurb"]), 330, 14, S.MUTED),
			_fixed("+%d%% shoppers · %d days" % [roundi(float(c["footfall"]) * 100.0), int(c["days"])] + (" · ★+%d" % int(c["rep"]) if int(c["rep"]) > 0 else ""), 230, 14, S.GREEN)]
		row.append(S.spacer())
		if live:
			row.append(S.chip("RUNNING · %d DAY%s LEFT" % [int(run["until"]) - e.day + 1, "" if int(run["until"]) == e.day else "S"], S.GREEN))
		else:
			var btn := S.button(EmpireData.money(float(c["cost"])), func():
				var err := e.run_campaign(c["id"])
				toast(err if err != "" else "%s is running" % c["name"], "bad" if err != "" else "good")
				if err == "":
					Sfx.play("chime", -6.0)
				open_phone("company"), why2 == "", 130)
			btn.disabled = why2 != "" and not why2.begins_with("Costs")
			if btn.disabled:
				btn.tooltip_text = why2
			row.append(btn)
		list.add_child(_row(row))
	if e.hq_tier() == 0:
		list.add_child(S.label("Campaigns are run from your head office.", 15, S.MUTED))
	v.add_child(_scroll(list, 150))


func _perks(d: Dictionary) -> Label:
	var bits: Array = []
	if float(d.get("wholesale", 0)) > 0.0:
		bits.append("−%d%% on every case of stock" % roundi(float(d["wholesale"]) * 100.0))
	if float(d.get("footfall", 0)) > 0.0:
		bits.append("+%d%% shoppers in every shop" % roundi(float(d["footfall"]) * 100.0))
	var l := S.label(" · ".join(bits), 15, S.GREEN, "bold")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _progress(x: float, of: float, text: String) -> Control:
	var h := S.hbox(10)
	var bar := _Bar.new()
	bar.k = clampf(x / maxf(of, 1.0), 0.0, 1.0)
	bar.custom_minimum_size = Vector2(220, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	h.add_child(S.label(text, 14, S.MUTED))
	return h


class _Bar extends Control:
	var k := 0.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.1))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * k, size.y)), EmpireStyle.GREEN if k >= 1.0 else EmpireStyle.AMBER)


# -------------------------------------------------------- brand studio
var _draft := {}
var _draft_roll := 0


func open_brand() -> void:
	var e := game.empire
	if _draft.is_empty():
		_draft = e.brand.duplicate() if not e.brand.is_empty() else ShopStyle.default_house("")
	var v := _open("Brand studio", 1180, 660)
	var row := S.hbox(22)
	v.add_child(row)
	# Left: the shopfront and the name.
	var lv := S.vbox(12)
	row.add_child(lv)
	var pv := Widgets.BrandPreview.new()
	pv.ident = ShopStyle.house_ident(_draft)
	pv.custom_minimum_size = Vector2(540, 300)
	lv.add_child(pv)
	var nh := S.hbox(10)
	var le := LineEdit.new()
	le.text = String(_draft.get("name", ""))
	le.placeholder_text = "Company name"
	le.max_length = 22
	le.custom_minimum_size = Vector2(380, 54)
	le.add_theme_font_override("font", S.font("bold"))
	le.add_theme_font_size_override("font_size", 22)
	le.text_changed.connect(func(t: String):
		_draft["name"] = t
		pv.ident = ShopStyle.house_ident(_draft)
		pv.queue_redraw())
	nh.add_child(le)
	nh.add_child(S.button("Suggest", func():
		_draft_roll += 1
		_draft["name"] = ShopStyle.suggest_name(_draft_roll + e.seed * 31)
		open_brand(), false, 140))
	lv.add_child(nh)
	var cost := e.rebrand_cost() if String(e.brand.get("name", "")) != "" else 0.0
	lv.add_child(S.label("Free: your first brand." if cost <= 0.0 else "New signs for %d shops: %s" % [e.businesses.size(), EmpireData.money(cost)], 16, S.MUTED))
	var ah := S.hbox(10)
	ah.add_child(S.button("Apply brand" if cost <= 0.0 else "Apply · %s" % EmpireData.money(cost), func():
		var err := e.set_brand(_draft)
		if err != "":
			toast(err, "bad")
			return
		_draft = {}
		Sfx.play("chime", -4.0)
		toast("Your shops now trade as %s" % e.brand["name"], "good")
		open_phone("company"), true, 260))
	ah.add_child(S.button("Cancel", func():
		_draft = {}
		open_phone("company"), false, 140))
	lv.add_child(ah)
	# Right: colours, lettering, sign.
	var rv := S.vbox(10)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rv)
	rv.add_child(S.label("COLOURS", 14, S.AMBER, "black"))
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	for pal in ShopStyle.HOUSE_PALETTES:
		var on: bool = String(_draft.get("primary", "")) == pal[0] and String(_draft.get("accent", "")) == pal[1]
		g.add_child(_swatch(Color(pal[0]), Color(pal[1]), on, func():
			_draft["primary"] = pal[0]
			_draft["accent"] = pal[1]
			open_brand()))
	rv.add_child(g)
	var sw := S.hbox(10)
	sw.add_child(S.button("Swap colours", func():
		var p0 = _draft["primary"]
		_draft["primary"] = _draft["accent"]
		_draft["accent"] = p0
		open_brand(), false, 170))
	rv.add_child(sw)
	rv.add_child(S.label("LETTERING", 14, S.AMBER, "black"))
	var fg := GridContainer.new()
	fg.columns = 4
	fg.add_theme_constant_override("h_separation", 8)
	fg.add_theme_constant_override("v_separation", 8)
	for f in ShopStyle.HOUSE_FACES:
		var b := S.button(String(ShopStyle.FACE_NAMES.get(f, f)), func():
			_draft["face"] = f
			open_brand(), String(_draft.get("face", "")) == f, 128)
		b.add_theme_font_override("font", ShopStyle.font(f))
		b.add_theme_font_size_override("font_size", 20 if f != "neon" else 15)
		fg.add_child(b)
	rv.add_child(fg)
	rv.add_child(S.label("SIGN", 14, S.AMBER, "black"))
	var sg := S.hbox(8)
	for sn in ShopStyle.HOUSE_SIGNS:
		sg.add_child(S.button(String(ShopStyle.SIGN_NAMES.get(sn, sn)), func():
			_draft["sign"] = sn
			open_brand(), String(_draft.get("sign", "")) == sn, 120))
	rv.add_child(sg)


func _swatch(a: Color, b: Color, on: bool, cb: Callable) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(68, 52)
	var sb := StyleBoxFlat.new()
	sb.bg_color = a
	sb.set_corner_radius_all(12)
	sb.border_color = S.PAPER if on else Color(1, 1, 1, 0.15)
	sb.set_border_width_all(3 if on else 1)
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, sb)
	var dot := ColorRect.new()
	dot.color = b
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.position = Vector2(40, 24)
	dot.size = Vector2(18, 18)
	btn.add_child(dot)
	btn.pressed.connect(func():
		if Time.get_ticks_msec() < S.tap_block_until:
			return
		Sfx.play("click", -12.0)
		cb.call())
	return btn


# ---------------------------------------------------------------- style
## Your character: the camera turns to face the hero (left of the screen),
## the choices sit on the right and every tap shows straight away. `first`:
## straight after the welcome, with a "Start" button.
var _style_tab := "you"
var _style_orbit := 0.0
var _style_first := false


func open_style(first := false) -> void:
	_style_first = first
	close_panel(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var e := game.empire
	var l := HeroLook.current(e.flags)
	_style_pose(true)
	_style_frame()
	var catcher := Control.new()  # (the left side stays clear: the hero is there)
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_root.add_child(catcher)
	var W := 600.0
	var H := 680.0
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(W, H)
	_anchor(_panel, 1.0, 0.5, Vector2(-W - 24.0, -H * 0.5), Vector2(W, H))
	_panel_root.add_child(_panel)
	var v := S.vbox(12)
	_panel.add_child(v)
	var head := S.hbox(10)
	var shop := style_shop
	head.add_child(S.label("Make your character" if first else (String(Wardrobe.STORES[shop]["name"]) if shop != "" else "Your wardrobe"), 28, S.PAPER, "black"))
	head.add_child(S.spacer())
	if not first:
		head.add_child(S.button("✕", _close_style, false, 52))
	v.add_child(head)
	var tabs := S.hbox(8)
	var tab_list := [["you", "Face & hair"], ["clothes", "Clothes"], ["extras", "Shoes & hats"]]
	if shop != "":
		tab_list = [["clothes", "Clothes"], ["extras", "Shoes & more"]]
		if _style_tab == "you":
			_style_tab = "clothes"
	elif not first:
		tab_list.append(["outfits", "Outfits"])
	for tb in tab_list:
		tabs.add_child(S.button(tb[1], func():
			_style_tab = tb[0]
			open_style(_style_first), _style_tab == tb[0], 170))
	v.add_child(tabs)
	var body := S.vbox(10)
	match _style_tab:
		"you":
			_style_choices(body, "FACE", HeroLook.FACES, l, "face", 3)
			var fc := HeroLook.face_colors(l["face"])
			_style_colours(body, "SKIN", HeroLook.SKIN, l, "skin", fc["skin"])
			_style_choices(body, "HAIRCUT", HeroLook.HAIRS, l, "hair", 3)
			_style_colours(body, "HAIR COLOUR", HeroLook.HAIR, l, "hair_col", fc["hair"])
		"clothes":
			_style_choices(body, "TOP", _style_list(HeroLook.TOPS, first), l, "top", 3)
			_style_colours(body, "TOP COLOUR", HeroLook.CLOTH, l, "top_col")
			_style_colours(body, "TROUSERS", HeroLook.TROUSERS, l, "pants_col")
		"extras":
			_style_choices(body, "SHOES", _style_list(HeroLook.SHOES, first), l, "shoes", 3)
			_style_choices(body, "HAT", _style_list(HeroLook.HATS, first), l, "head", 4)
			_style_choices(body, "EYEWEAR", _style_list(HeroLook.EYEWEAR, first), l, "eyewear", 4)
		"outfits":
			body.add_child(S.label("SAVED OUTFITS", 14, S.AMBER, "black"))
			var outs: Array = e.flags.get("outfits", [])
			if outs.is_empty():
				body.add_child(S.label("Dress up, then save the look here to wear it again in one tap.", 16, S.MUTED))
			for o in outs:
				var od: Dictionary = o
				body.add_child(_row([_fixed("%s · %s" % [HeroLook.label(HeroLook.TOPS, String(od.get("top", ""))),
					HeroLook.label(HeroLook.SHOES, String(od.get("shoes", "")))], 300, 17, S.PAPER, "bold"), S.spacer(),
					S.button("Wear", func(): _style_set(od), true, 110)]))
			body.add_child(S.button("Save what I'm wearing", func():
				Wardrobe.save_outfit(e.flags, HeroLook.current(e.flags))
				open_style(false), false, 300))
	v.add_child(_scroll(body, H - 250.0))
	var foot := S.hbox(10)
	foot.add_child(S.button("⟲", func():
		_style_orbit -= 0.6
		_style_frame(), false, 64))
	foot.add_child(S.button("⟳", func():
		_style_orbit += 0.6
		_style_frame(), false, 64))
	foot.add_child(S.button("Random", func():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var r := {}
		for pair in [["face", HeroLook.FACES], ["hair", HeroLook.HAIRS], ["top", HeroLook.TOPS], ["shoes", HeroLook.SHOES]]:
			var lst: Array = pair[1]
			r[pair[0]] = lst[rng.randi() % lst.size()][0]
		r["top_col"] = HeroLook.CLOTH[rng.randi() % HeroLook.CLOTH.size()]
		r["pants_col"] = HeroLook.TROUSERS[rng.randi() % HeroLook.TROUSERS.size()]
		r["hair_col"] = ""
		r["skin"] = ""
		r["head"] = "head_bare"
		r["eyewear"] = "face_none"
		_style_set(r), false, 130))
	foot.add_child(S.spacer())
	var unpaid := Wardrobe.unpaid(e.flags, l) if (shop != "" and not first) else []
	if not unpaid.is_empty():
		var tot := 0
		for it in unpaid:
			tot += Wardrobe.price(String(it))
		foot.add_child(S.button("Buy look · %s" % EmpireData.money(float(tot)), func():
			var err := Wardrobe.buy(e, unpaid, shop)
			if err != "":
				toast(err, "bad")
			else:
				Sfx.play("cash", -4.0)
				toast("Bought – it's in your wardrobe", "good")
			open_style(false), true, 220))
	foot.add_child(S.button("Start" if first else ("Leave" if shop != "" else "Done"), _close_style, unpaid.is_empty(), 140))
	v.add_child(foot)


## The Style screen as a store (`style_shop` = a Wardrobe.STORES key) or
## your wardrobe. Look on entering a store (put back if you leave unpaid).
var style_shop := ""
var _style_entry := {}


## The choices for a list: the store's stock (priced) in a store, what you
## own in your wardrobe, everything when making your character.
func _style_list(list: Array, first: bool) -> Array:
	var flags := game.empire.flags
	var out: Array = []
	for it in list:
		var id := String(it[0])
		if first or style_shop == "" and Wardrobe.owns(flags, id):
			out.append(it)
		elif style_shop != "" and (id in Wardrobe.STORES[style_shop]["items"] or id in Wardrobe.FREE):
			var lbl := String(it[1])
			if not Wardrobe.owns(flags, id):
				lbl += " · " + EmpireData.money(float(Wardrobe.price(id)))
			else:
				lbl += " ✓"
			out.append([id, lbl])
	return out


func open_store(store: String) -> void:
	style_shop = store
	_style_entry = HeroLook.current(game.empire.flags).duplicate()
	_style_tab = "clothes"
	open_style(false)


func _style_set(changes: Dictionary) -> void:
	var e := game.empire
	var l := HeroLook.current(e.flags)
	l.merge(changes, true)
	e.flags["look"] = l
	game.apply_hero_look()
	Sfx.play("click", -12.0)
	open_style(_style_first)


func _style_choices(v: VBoxContainer, title: String, list: Array, l: Dictionary, key: String, cols: int) -> void:
	v.add_child(S.label(title, 14, S.AMBER, "black"))
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	var w := (540.0 - 8.0 * (cols - 1)) / cols
	for it in list:
		g.add_child(S.button(String(it[1]), func(): _style_set({key: it[0]}), String(l.get(key, "")) == it[0], w))
	v.add_child(g)


## A row of colour swatches; `own` (when given) is a first swatch meaning
## "the face's own colour" (stored as "").
func _style_colours(v: VBoxContainer, title: String, list: Array, l: Dictionary, key: String, own = null) -> void:
	v.add_child(S.label(title, 14, S.AMBER, "black"))
	var g := GridContainer.new()
	g.columns = 8
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	var cur := String(l.get(key, ""))
	if own is Color:
		g.add_child(_swatch(own, own.lightened(0.5), cur == "", func(): _style_set({key: ""})))
	for hx in list:
		var c := Color(String(hx))
		g.add_child(_swatch(c, c, cur != "" and Color(cur).is_equal_approx(c), func(): _style_set({key: hx})))
	v.add_child(g)


## Stand the hero still (idling, animated) while the editor is open.
func _style_pose(on: bool) -> void:
	var p: Player = game.player
	if on:
		p.velocity = Vector3.ZERO
		p.s.velocity = Vector3.ZERO
	game.rig.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_INHERIT


## The camera in front of the hero (orbiting with ⟲ ⟳), the hero on the left
## half of the screen, clear of the panel.
func _style_frame() -> void:
	var p: Player = game.player
	var fwd: Vector3 = game.rig._facing
	fwd = fwd.rotated(Vector3.UP, _style_orbit)
	var side := fwd.cross(Vector3.UP).normalized()
	var chest := p.global_position + Vector3.UP * 0.35
	var eye := chest + fwd * 3.1 + Vector3.UP * 0.25
	var look_at := chest - side * 0.95  # look right of the hero: they sit left of centre
	var cam: Camera3D = game.camera.cam
	cam.global_transform = Transform3D(Basis.looking_at(look_at - eye, Vector3.UP), eye)
	cam.fov = 50.0


func _close_style() -> void:
	var first := _style_first
	_style_pose(false)
	_style_first = false
	var e := game.empire
	if first:
		e.flags["styled"] = true
		# (Your starting outfit is yours.)
		var lk := HeroLook.current(e.flags)
		var o := Wardrobe.owned(e.flags)
		for k in ["top", "shoes", "head", "eyewear"]:
			if not String(lk[k]) in o:
				o.append(String(lk[k]))
	elif style_shop != "" and not Wardrobe.unpaid(e.flags, HeroLook.current(e.flags)).is_empty():
		# Left the store without paying: back into what you came in wearing.
		var back := HeroLook.current(e.flags)
		for k in ["top", "shoes", "head", "eyewear"]:
			if not Wardrobe.owns(e.flags, String(back[k])):
				back[k] = _style_entry.get(k, HeroLook.DEFAULT[k])
		e.flags["look"] = back
		game.apply_hero_look()
	style_shop = ""
	game.save_game()
	close_panel(true)
	game.camera.snap()


# ---------------------------------------------------------- head office
## The reception desk in Meridian Tower: the three tiers side by side.
func open_hq() -> void:
	var e := game.empire
	var v := _open("Meridian Tower", 1120, 560)
	var tier := e.hq_tier()
	v.add_child(S.label("Reception · %s" % ("welcome back" if tier > 0 else "office suites to let, from %s" % EmpireData.money(float(e.hq_def(1)["price"]))), 17, S.MUTED))
	var h := S.hbox(14)
	v.add_child(h)
	for i in range(1, 4):
		var d := e.hq_def(i)
		var c := _card(0)
		(c[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(c[0])
		var cv: VBoxContainer = c[1]
		var mine := tier >= i
		var th := S.hbox(8)
		th.add_child(S.label("FLOOR %d" % [1, 3, 60][i - 1] if i < 3 else "ALL 60 FLOORS", 13, S.MUTED, "black"))
		th.add_child(S.spacer())
		if mine:
			th.add_child(S.chip("YOURS", S.GREEN))
		cv.add_child(th)
		cv.add_child(S.label(String(d["name"]), 24, S.PAPER, "black"))
		var bl := S.label(String(d["blurb"]), 15, S.MUTED)
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size = Vector2(300, 64)
		cv.add_child(bl)
		cv.add_child(_perks(d))
		cv.add_child(S.label("Unlocks: " + ", ".join(EmpireData.hq().get("campaigns", []).filter(func(x): return int(x["tier"]) == i).map(func(x): return String(x["name"]))), 14, S.PAPER))
		cv.add_child(S.label("Upkeep %s/day · needs %d shops" % [EmpireData.money(float(d["upkeep"])), int(d["shops"])], 14, S.MUTED))
		if not mine:
			var why := e.hq_block(i)
			var b := S.button("Take it · %s" % EmpireData.money(float(d["price"])), func():
				var err := e.buy_hq(i)
				if err != "":
					toast(err, "bad")
					return
				Sfx.play("chime", -2.0)
				toast("%s is yours" % d["name"], "good")
				open_hq(), i == tier + 1)
			b.disabled = why != ""
			cv.add_child(b)
			if why != "":
				cv.add_child(S.label(why, 14, S.AMBER))
	var fh := S.hbox(10)
	fh.add_child(S.button("Brand studio", func(): open_brand(), false, 180))
	fh.add_child(S.button("Marketing", func(): open_phone("company"), false, 160))
	v.add_child(fh)


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
	g.columns = 4
	g.add_theme_constant_override("h_separation", 40)
	var wd := CityLife.weather_def(e.weather)
	var fd := CityLife.weather_def(e.forecast)
	g.add_child(_stat("Today", String(wd.get("name", "")), S.AMBER))
	g.add_child(_stat("Tomorrow", String(fd.get("name", "")), S.MUTED))
	var rc := CityLife.rival_cfg()
	g.add_child(_stat(String(rc.get("name", "QuikSave")) + " stores", "gone" if e.flags.get("rival_gone", false) else str(e.rivals.size()),
		S.GREEN if e.flags.get("rival_gone", false) else S.RED))
	g.add_child(_stat("Independents", "%d · %d for sale" % [e.firms.size(), CityLife.firms_for_sale(e).size()], S.PAPER))
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
	var sale := CityLife.firms_for_sale(e)
	sale.sort_custom(func(a, b): return CityLife.firm_price(a) < CityLife.firm_price(b))
	if not sale.is_empty():
		list.add_child(S.label("BUSINESSES FOR SALE · running shops with stock, staff and regulars", 14, S.GREEN, "black"))
		for f in sale:
			var u2: Dictionary = game.unit_by_id.get(f["unit"], {})
			if u2.is_empty():
				continue
			list.add_child(_row([_fixed(String(f["name"]), 240, 17, S.PAPER, "bold"),
				_fixed("%s · ★ %d · %s/day" % [CityLife._dname(f), int(f["rep"]), EmpireData.money(CityLife.firm_profit(f))], 262, 15, S.MUTED),
				_fixed(EmpireData.money(CityLife.firm_price(f)), 100, 17, S.PAPER, "bold"),
				S.button("View", func(): open_firm(u2), true, 100),
				S.button("GPS", func():
					game.set_gps(Premises.door_point(u2), String(f["name"]))
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


func open_rival(u: Dictionary, remote := false) -> void:
	var e := game.empire
	var r := CityLife.rival_at(e, u["id"])
	if r.is_empty():
		return
	e.flags["inspected_property"] = true
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
	var fee := EmpireGame.agent_fee(price) if remote else 0.0
	v.add_child(S.label("Price %s%s  ·  you have %s + company %s" % [EmpireData.money(price), (" + %s broker" % EmpireData.money(fee)) if remote else "",
		EmpireData.money(e.personal_cash), EmpireData.money(e.company_cash)], 18, S.AMBER, "bold"))
	var h := S.hbox(12)
	var buy := S.button("BUY OUT · %s" % EmpireData.money(price + fee), func():
		var err := game.buy_out_rival(u, fee)
		if err != "":
			toast(err, "bad")
		else:
			close_panel(true), true, 320)
	buy.disabled = not e.can_afford(price + fee)
	h.add_child(buy)
	h.add_child(S.button("Not now", close_panel.bind(true), false, 160))
	v.add_child(h)


## An independent shop: its books and the asking price.
func open_firm(u: Dictionary, remote := false) -> void:
	var e := game.empire
	var f := CityLife.firm_at(e, u["id"])
	if f.is_empty():
		return
	e.flags["inspected_property"] = true
	if not e.businesses.is_empty():
		e.flags["viewed_expansion"] = true
	var v := _open(String(f["name"]), 780, 470)
	var d := EmpireData.district(f["district"])
	var yrs := maxi(1, (e.day - int(f.get("since", e.day))) / 365)
	v.add_child(S.label("Independent · run by %s for %d year%s  ·  %s  ·  %d m²" % [f["owner"], yrs, "" if yrs == 1 else "s",
		d.get("name", ""), int(u.get("size", 0))], 17, S.MUTED))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 36)
	var prof := CityLife.firm_profit(f)
	g.add_child(_stat("Reputation", "★ %d" % int(f["rep"]), S.AMBER))
	g.add_child(_stat("Profit / day", EmpireData.money(prof), S.GREEN if prof > 0.0 else S.RED))
	g.add_child(_stat("Rent / day", EmpireData.money(float(f.get("rent", 0.0)))))
	g.add_child(_stat("Status", "FOR SALE" if f.get("for_sale", false) else "Trading", S.AMBER if f.get("for_sale", false) else S.PAPER))
	v.add_child(g)
	var txt := S.label(("%s is retiring and wants a quick sale: the price is %d%% under value." % [f["owner"], roundi((1.0 - float(CityLife.firm_cfg().get("sale_discount", 0.8))) * 100.0)])
		if f.get("for_sale", false) else "Not on the market, but %s will sell for the right offer." % f["owner"].get_slice(" ", 0), 17, S.PAPER)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size.x = 720
	v.add_child(txt)
	var inc := S.label("You take over the lease (rent from tomorrow), the stock on the shelves, the cashier and its regulars. It keeps trading from the moment you buy it.", 16, S.MUTED)
	inc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inc.custom_minimum_size.x = 720
	v.add_child(inc)
	var price := CityLife.firm_price(f)
	var fee := EmpireGame.agent_fee(price) if remote else 0.0
	v.add_child(S.label("Price %s%s  ·  you have %s + company %s" % [EmpireData.money(price), (" + %s broker" % EmpireData.money(fee)) if remote else "",
		EmpireData.money(e.personal_cash), EmpireData.money(e.company_cash)], 18, S.AMBER, "bold"))
	var h := S.hbox(12)
	var buy := S.button("BUY THE BUSINESS · %s" % EmpireData.money(price + fee), func():
		var err := game.buy_firm(u, fee)
		if err != "":
			toast(err, "bad")
		else:
			close_panel(true), true, 360)
	buy.disabled = not e.can_afford(price + fee)
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


# ================================================================ phone 2
# Home dashboard, portfolio, property listings, vehicles and More. Every
# button here goes somewhere real (a manage tab, the map with a place
# selected, a route) – nothing needs typing.

const TONES := {"good": S.GREEN, "warn": S.AMBER, "bad": S.RED, "muted": S.MUTED, "info": S.BLUE}

static var _pf_district := "all"
static var _pf_sort := "attention"
static var _pr_kind := "to_let"
static var _pr_district := "all"


## What's wrong at a shop: [[text, tone, manage tab], …] (worst first).
func biz_issues(b: Business) -> Array:
	var e := game.empire
	var out: Array = []
	var st := b.status(e.hour())
	if st[0] == "no_stock":
		out.append(["Out of stock – nothing on the shelves", "bad", "stock"])
	elif b.shelf_fill() < 0.25 and b.backroom.total_units() < 12 and b.orders.is_empty():
		out.append(["Running low – shelves %d%%, back room nearly empty" % int(b.shelf_fill() * 100.0), "warn", "stock"])
	if not b.has_role("cashier"):
		out.append(["No cashier – it only trades while you're at the till", "warn", "staff"])
	for x in b.staff:
		if x.get("off", false):
			out.append(["%s is off today" % String(x["name"]), "warn", "staff"])
	var ld := b.last_day()
	if not ld.is_empty() and float(ld.get("profit", 0.0)) < 0.0:
		out.append(["Lost %s yesterday" % EmpireData.money(-float(ld["profit"])), "bad", "reports"])
	if b.cleanliness < 0.4:
		out.append(["Dirty floor is putting shoppers off – a cleaner fixes it", "warn", "staff"])
	if not b.open:
		out.append(["Closed by you", "muted", "overview"])
	return out


## Things that need you, company-wide: {text, tone, icon, btn, cb}.
func alerts() -> Array:
	var e := game.empire
	var out: Array = []
	var ob := game.objective()
	if String(ob[0]) != "":
		var act := String(ob[3]) if ob.size() > 3 else ""
		out.append({"text": "Next: " + String(ob[0]), "tone": "info", "icon": "goals",
			"btn": "Go" if (ob[1] as Vector3) != Vector3.INF or act != "" else "", "cb": objective_action})
	if e.company_cash < 0.0:
		out.append({"text": "The company account is overdrawn (%s): 1%% a day interest" % EmpireData.money(e.company_cash),
			"tone": "bad", "icon": "bank", "btn": "Finances", "cb": func(): open_phone("bank")})
	for b: Business in e.businesses:
		for iss in biz_issues(b):
			if iss[1] == "muted":
				continue
			var tab: String = iss[2]
			out.append({"text": "%s: %s" % [b.name, iss[0]], "tone": iss[1], "icon": "businesses",
				"btn": {"stock": "Stock", "staff": "Staff", "reports": "Finances", "overview": "Manage"}.get(tab, "Manage"),
				"cb": func(): open_manage(b, tab)})
	# Your car, when it's a walk away.
	if game.driving == "" and not e.vehicles.is_empty():
		var vid: String = e.vehicles[0]["id"]
		var d := game.player.global_position.distance_to(game.vehicle_position(vid))
		if d > 350.0:
			out.append({"text": "Your %s is %s away" % [EmpireData.vehicle_model(e.vehicles[0]["model"]).get("name", "car"), _dist_text(d)],
				"tone": "muted", "icon": "vehicles", "btn": "Find", "cb": func(): find_vehicle(vid)})
	# A business for sale (the nearest).
	var fs := CityLife.firms_for_sale(e)
	if not fs.is_empty() and not e.businesses.is_empty():
		var f: Dictionary = fs[0]
		var u: Dictionary = game.unit_by_id.get(f["unit"], {})
		if not u.is_empty():
			out.append({"text": "%s is for sale: %s" % [f["name"], EmpireData.money(CityLife.firm_price(f))],
				"tone": "muted", "icon": "property", "btn": "Inspect", "cb": func(): open_firm(u, true)})
	var rank := {"bad": 0, "warn": 1, "info": 2, "good": 3, "muted": 4}
	out.sort_custom(func(a, b): return int(rank[a["tone"]]) < int(rank[b["tone"]]))
	return out


## Tapping the objective: its screen, or its route on the map.
func objective_action() -> void:
	var ob := game.objective()
	var act := String(ob[3]) if ob.size() > 3 else ""
	var b: Business = game.empire.businesses[0] if not game.empire.businesses.is_empty() else null
	match act:
		"map":
			open_phone("map")
		"property":
			if game.empire.businesses.is_empty():
				var u: Dictionary = game.unit_by_id.get(game.empire.flags.get("start_unit", ""), game.starter_unit())
				open_phone("map", {"kind": "unit", "id": String(u.get("id", ""))})
			else:
				open_phone("property")
		"staff":
			if b:
				open_manage(b, "staff")
		"finances":
			if b:
				open_manage(b, "reports")
		_:
			if (ob[1] as Vector3) != Vector3.INF:
				game.set_gps(ob[1], String(ob[2]) if ob.size() > 2 else "", {"kind": "objective"})
				game.empire.flags.erase("gps_manual")
				open_phone("map")


static func _dist_text(d: float) -> String:
	return "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(roundf(d / 10.0) * 10.0)


func _tile(icon: String, title: String, sub: String, cb: Callable, col := S.AMBER) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(218, 92)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(16)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = Color(1, 1, 1, 0.09)
	var pr := sb.duplicate() as StyleBoxFlat
	pr.bg_color = Color(col, 0.22)
	for st in ["normal", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	var ic := Widgets.Icon.new(icon, col, 30)
	ic.position = Vector2(16, 16)
	ic.size = Vector2(30, 30)
	b.add_child(ic)
	var t := S.label(title, 19, S.PAPER, "black")
	t.position = Vector2(58, 12)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(t)
	var st2 := S.label(sub, 14, S.MUTED)
	st2.position = Vector2(58, 40)
	st2.size = Vector2(150, 44)
	st2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(st2)
	b.pressed.connect(func():
		if Time.get_ticks_msec() < S.tap_block_until:
			return
		Sfx.play("click", -10.0)
		cb.call())
	return b


func _home_tab(v: VBoxContainer) -> void:
	var e := game.empire
	# Today, yesterday, shops, staff.
	var today_rev := 0.0
	var yday := 0.0
	var trading := 0
	var staff_n := 0
	for b: Business in e.businesses:
		today_rev += float(b.today["revenue"])
		yday += float(b.last_day().get("profit", 0.0))
		if b.status(e.hour())[0] == "trading":
			trading += 1
		staff_n += b.staff.size()
	var g := S.hbox(26)
	g.add_child(_stat("Takings today", EmpireData.money(today_rev), S.PAPER))
	g.add_child(_stat("Profit yesterday", EmpireData.money(yday, true) if not e.day_reports.is_empty() else "–",
		S.GREEN if yday >= 0.0 else S.RED))
	g.add_child(_stat("Shops trading", "%d / %d" % [trading, e.businesses.size()], S.PAPER))
	g.add_child(_stat("Staff", str(staff_n), S.PAPER))
	if game.gps.active():
		g.add_child(S.spacer())
		var gv := S.vbox(4)
		gv.add_child(S.label("ROUTE · " + game.gps.label.to_upper(), 13, Gps.COLOUR.lightened(0.3), "black"))
		var gh := S.hbox(8)
		gh.add_child(S.label(game.gps.message if game.gps.message != "" else game.gps.distance_text(), 18, S.PAPER, "bold"))
		gh.add_child(S.button("Map", func(): open_phone("map"), false, 80))
		gh.add_child(S.button("Cancel", func():
			game.clear_gps()
			open_phone("home"), false, 96))
		gv.add_child(gh)
		g.add_child(gv)
	v.add_child(g)
	var cols := S.hbox(18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	# Needs you.
	var left := S.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(_section("alert", "Needs you"))
	var list := S.vbox(6)
	var al := alerts()
	if al.is_empty():
		list.add_child(S.label("All quiet: every shop is stocked, staffed and making money.", 17, S.MUTED))
	for a in al.slice(0, 12):
		var row := PanelContainer.new()
		var sb := S.row_bg()
		sb.border_color = TONES[a["tone"]]
		sb.border_width_left = 4
		row.add_theme_stylebox_override("panel", sb)
		var h := S.hbox(12)
		row.add_child(h)
		var tl := S.label(String(a["text"]), 16, S.PAPER)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.custom_minimum_size.x = 300
		h.add_child(tl)
		if String(a["btn"]) != "":
			h.add_child(S.button(String(a["btn"]), a["cb"], a["tone"] == "info", 104))
		list.add_child(row)
	left.add_child(_scroll(list, 400))
	# Quick actions.
	var right := S.vbox(10)
	cols.add_child(right)
	right.add_child(_section("gps", "Quick actions"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	right.add_child(grid)
	var vid: String = e.vehicles[0]["id"] if not e.vehicles.is_empty() else ""
	grid.add_child(_tile("map", "Map", "Places, routes, GPS", func(): open_phone("map")))
	grid.add_child(_tile("vehicles", "Find my car", "Route to where it's parked" if game.driving == "" else "You're in it",
		func(): find_vehicle(vid) if vid != "" else null))
	grid.add_child(_tile("businesses", "My shops", "%d running" % e.businesses.size(), func(): open_phone("businesses")))
	grid.add_child(_tile("property", "Expand", "Shops to let and for sale", func(): open_phone("property")))
	grid.add_child(_tile("finances", "Finances", "Profit, cash, loans", func(): open_phone("bank")))
	grid.add_child(_tile("stock", "Suppliers", "Route to the cash & carry", func():
		var here := game.player.global_position
		var w := game.wholesaler("west" if here.x < CityLayout.FAR_SHORE else "east")
		if not w.is_empty():
			game.set_gps(Premises.door_point(w), String(w["name"]), {"kind": "unit", "id": String(w["id"])})
			open_phone("map", {"kind": "unit", "id": String(w["id"])})))


func _portfolio_tab(v: VBoxContainer) -> void:
	var e := game.empire
	if e.businesses.is_empty():
		var cv := _card()
		(cv[1] as VBoxContainer).add_child(S.label("No shops yet", 24, S.PAPER, "black"))
		(cv[1] as VBoxContainer).add_child(S.label("Rent an empty unit (amber on the map) or buy an independent that's for sale.", 17, S.MUTED))
		(cv[1] as VBoxContainer).add_child(S.button("Find a shop", func(): open_phone("property"), true, 220))
		v.add_child(cv[0])
		return
	# Company line + filters.
	var dists := {}
	for b: Business in e.businesses:
		dists[b.district_key()] = String(b.district().get("name", b.district_key()))
	var fh := S.hbox(6)
	fh.add_child(S.chip_button("All districts", _pf_district == "all", func():
		_pf_district = "all"
		open_phone("businesses")))
	for k in dists:
		fh.add_child(S.chip_button(String(dists[k]), _pf_district == k, func():
			_pf_district = k
			open_phone("businesses")))
	fh.add_child(S.spacer())
	for sk in [["attention", "Needs me"], ["profit", "Profit"], ["name", "A–Z"]]:
		fh.add_child(S.chip_button(sk[1], _pf_sort == sk[0], func():
			_pf_sort = sk[0]
			open_phone("businesses"), S.BLUE))
	v.add_child(fh)
	var bs: Array = e.businesses.filter(func(b): return _pf_district == "all" or b.district_key() == _pf_district)
	match _pf_sort:
		"profit":
			bs.sort_custom(func(a, b): return float(a.last_day().get("profit", 0.0)) > float(b.last_day().get("profit", 0.0)))
		"name":
			bs.sort_custom(func(a, b): return a.name < b.name)
		_:
			bs.sort_custom(func(a, b): return biz_issues(a).size() > biz_issues(b).size())
	var list := S.vbox(10)
	for b: Business in bs:
		list.add_child(_biz_card(b))
	v.add_child(_scroll(list, 470))


func _biz_card(b: Business) -> PanelContainer:
	var e := game.empire
	var cv := _card()
	var c: VBoxContainer = cv[1]
	var st := b.status(e.hour())
	var top := S.hbox(12)
	var nm := S.label(b.name, 21, S.PAPER, "black")
	top.add_child(nm)
	top.add_child(S.label("%s · %s" % [String(b.type_def().get("name", "Shop")), String(b.district().get("name", ""))], 15, S.MUTED))
	top.add_child(S.spacer())
	var issues := biz_issues(b)
	if issues.any(func(i): return i[1] in ["bad", "warn"]):
		top.add_child(Widgets.Icon.new("alert", S.AMBER, 22))
	top.add_child(S.chip(String(st[1]), TONES[st[2]]))
	c.add_child(top)
	var ld := b.last_day()
	var prof := float(ld.get("profit", 0.0))
	var roles: Array = []
	for r in ["cashier", "stocker", "cleaner", "manager", "driver"]:
		var n := b.staff_with(r).size()
		if n > 0:
			roles.append("%s%s" % [String(EmpireData.role(r).get("name", r)).to_lower(), " ×%d" % n if n > 1 else ""])
	var stats := HFlowContainer.new()
	stats.add_theme_constant_override("h_separation", 30)
	stats.add_theme_constant_override("v_separation", 6)
	var staff_txt := ", ".join(roles) if not roles.is_empty() else "none"
	if staff_txt.length() > 30:
		staff_txt = "%d people" % b.staff.size()
	stats.add_child(_stat("Yesterday", EmpireData.money(prof, true) if not ld.is_empty() else "–", S.GREEN if prof >= 0.0 else S.RED))
	stats.add_child(_stat("Takings today", EmpireData.money(float(b.today["revenue"]))))
	stats.add_child(_stat("Shelves", "%d%%" % int(b.shelf_fill() * 100.0), S.RED if b.shelf_fill() < 0.2 else S.PAPER))
	stats.add_child(_stat("Back room", "%d/%d cases" % [b.backroom.cases_used(), b.backroom.case_capacity]))
	stats.add_child(_stat("Staff", staff_txt, S.PAPER if not roles.is_empty() else S.AMBER))
	stats.add_child(_stat("Premises", "Freehold" if b.owned else "%s/day" % EmpireData.money(b.rent_per_day())))
	c.add_child(stats)
	if not issues.is_empty() and issues[0][1] != "muted":
		c.add_child(S.label("⚠ " + String(issues[0][0]), 15, TONES[issues[0][1]], "bold"))
	var acts := S.hbox(8)
	acts.add_child(S.button("Manage", func(): open_manage(b), true, 120))
	for t in [["Stock", "stock"], ["Staff", "staff"], ["Finances", "reports"], ["Upgrades", "upgrades"]]:
		acts.add_child(S.button(t[0], func(): open_manage(b, t[1]), false, 110))
	acts.add_child(S.spacer())
	acts.add_child(S.button("GPS", func():
		var u: Dictionary = game.unit_by_id.get(b.premises["id"], {})
		if not u.is_empty():
			game.set_gps(Premises.door_point(u), b.name, {"kind": "unit", "id": String(u["id"])})
			open_phone("map", {"kind": "unit", "id": String(u["id"])}), false, 90))
	c.add_child(acts)
	return cv[0]


func _more_tab(v: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	for t in MORE_TABS:
		var tile := _tile(t[0], t[1], t[2], func(): open_phone(t[0]))
		tile.custom_minimum_size = Vector2(440, 100)
		(tile.get_child(2) as Label).size = Vector2(360, 44)
		grid.add_child(tile)
	v.add_child(grid)


# ------------------------------------------------------------ property
func _property_tab(v: VBoxContainer) -> void:
	var e := game.empire
	var kh := S.hbox(6)
	for k in [["to_let", "To let"], ["sale", "For sale"], ["yours", "Yours"], ["home", "Homes"]]:
		kh.add_child(S.chip_button(k[1], _pr_kind == k[0], func():
			_pr_kind = k[0]
			open_phone("property")))
	kh.add_child(S.spacer())
	var dists := {}
	for u in game.units:
		if u["kind"] == "shop":
			dists[String(u["district"])] = String(EmpireData.district(u["district"]).get("name", u["district"]))
	var dh := S.hbox(6)
	dh.add_child(S.chip_button("Everywhere", _pr_district == "all", func():
		_pr_district = "all"
		open_phone("property"), S.BLUE))
	var keys := dists.keys()
	keys.sort()
	for k in keys:
		dh.add_child(S.chip_button(String(dists[k]), _pr_district == k, func():
			_pr_district = k
			open_phone("property"), S.BLUE))
	v.add_child(kh)
	var ds := ScrollContainer.new()
	ds.custom_minimum_size = Vector2(900, 52)
	ds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ds.add_child(dh)
	v.add_child(ds)
	var note := S.label("Inspect anything from here. Sign at the door for free, or through an agent from your phone for a fee.", 15, S.MUTED)
	v.add_child(note)
	var list := S.vbox(6)
	var here := game.player.global_position
	var rows: Array = []
	if _pr_kind == "home":
		for hm in game.homes():
			rows.append([here.distance_to(game.home_lift(hm)), hm])
	else:
		for u in game.units:
			if u["kind"] != "shop":
				continue
			if _pr_district != "all" and u["district"] != _pr_district:
				continue
			var kind := MapKit.unit_kind(game, u)
			if _pr_kind == "sale" and kind not in ["sale", "rival"]:
				continue
			if _pr_kind != "sale" and kind != _pr_kind:
				continue
			rows.append([here.distance_to(Premises.door_point(u)), u])
	rows.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	if rows.is_empty():
		list.add_child(S.label("Nothing here right now – try another district.", 17, S.MUTED))
	for r in rows.slice(0, 40):
		list.add_child(_property_row(r[1], float(r[0])))
	v.add_child(_scroll(list, 360))


func _property_row(x: Dictionary, dist: float) -> PanelContainer:
	var e := game.empire
	var cells: Array = []
	if x.get("kind", "") == "home":
		var owned := e.owns_property(x["id"])
		cells = [_fixed(String(x["name"]), 230, 18, S.PAPER, "bold"),
			_fixed("%s · %d m up" % [EmpireData.district(x["district"]).get("name", ""), int(x["floor"])], 210, 15, S.MUTED),
			_fixed(_dist_text(dist), 80, 15, S.MUTED),
			_fixed("Yours" if owned else EmpireData.money(float(x["price"])), 110, 17, S.GREEN if owned else S.PAPER, "bold")]
		if owned:
			var let := false
			for q in e.properties:
				if q["id"] == x["id"]:
					let = q.get("let", false)
			cells.append(S.button("Move in" if let else "Let it out", func():
				e.set_let(x["id"], not let)
				open_phone("property"), false, 130))
		else:
			cells.append(_fixed("buy at its street door", 180, 14, S.MUTED))
		cells.append(S.spacer())
		cells.append(S.button("GPS", func():
			game.set_gps(game.home_lift(x), String(x["name"]), {"kind": "home", "id": String(x["id"])})
			open_phone("map", {"kind": "home", "id": String(x["id"])}), false, 80))
		return _row(cells)
	var u := x
	var kind := MapKit.unit_kind(game, u)
	var dname := String(EmpireData.district(u["district"]).get("name", ""))
	var title := ""
	var money := ""
	var inspect: Callable
	match kind:
		"to_let":
			title = String(u.get("shop_name", "Shop unit"))
			money = "%s/day · buy %s" % [EmpireData.money(float(u["rent"])), EmpireData.money(float(u["price"]))]
			inspect = func(): open_property(u, true)
		"sale":
			var f := CityLife.firm_at(e, u["id"])
			title = String(f.get("name", "Shop"))
			money = "%s · makes ~%s/day" % [EmpireData.money(CityLife.firm_price(f)), EmpireData.money(CityLife.firm_profit(f))]
			inspect = func(): open_firm(u, true)
		"rival":
			var r := CityLife.rival_at(e, u["id"])
			title = String(r.get("name", "QuikSave"))
			money = "buy out %s" % EmpireData.money(CityLife.rival_price(r))
			inspect = func(): open_rival(u, true)
		"yours":
			var b: Business = e.business_at(u["id"])
			title = b.name
			money = "Freehold" if b.owned else "Rented · %s/day" % EmpireData.money(b.rent_per_day())
			inspect = func(): open_manage(b)
	cells = [_fixed(title, 200, 18, S.PAPER, "bold"), _fixed("%s · %d m²" % [dname, int(u.get("size", 0))], 190, 15, S.MUTED),
		_fixed(_dist_text(dist), 70, 15, S.MUTED), _fixed(money, 230, 16, S.AMBER if kind != "yours" else S.GREEN, "bold"),
		S.spacer(), S.button("Inspect" if kind != "yours" else "Manage", inspect, false, 112),
		S.button("GPS", func():
			game.set_gps(Premises.door_point(u), title, {"kind": "unit", "id": String(u["id"])})
			open_phone("map", {"kind": "unit", "id": String(u["id"])}), false, 80)]
	return _row(cells)


# ------------------------------------------------------------ vehicles
func find_vehicle(vid: String) -> void:
	if vid == "" or game.driving == vid:
		toast("You're driving it", "info")
		return
	var p := game.vehicle_position(vid)
	var nm := String(EmpireData.vehicle_model(game.empire.vehicle(vid).get("model", "hatch")).get("name", "Car"))
	game.set_gps(p, "Your " + nm, {"kind": "vehicle", "id": vid})
	open_phone("map", {"kind": "vehicle", "id": vid})


func _vehicles_tab(v: VBoxContainer) -> void:
	var e := game.empire
	var list := S.vbox(10)
	var here := game.player.global_position
	for veh in e.vehicles:
		var vid := String(veh["id"])
		var md := EmpireData.vehicle_model(veh["model"])
		var p := game.vehicle_position(vid)
		var dist := here.distance_to(p)
		var where := String(EmpireData.district(("west:" if p.x < CityLayout.FAR_SHORE else "east:") + game.layout.district(p.x, p.z)).get("name", ""))
		var cargo := veh["cargo"] as Stock
		var cv := _card()
		var c: VBoxContainer = cv[1]
		var top := S.hbox(12)
		top.add_child(S.label(String(md["name"]), 21, S.PAPER, "black"))
		top.add_child(S.label(("You're driving it" if game.driving == vid else "Parked · %s · %s away" % [where, _dist_text(dist)]), 16, S.MUTED))
		top.add_child(S.spacer())
		var cond := float(veh["condition"])
		top.add_child(S.chip("%d%% condition" % int(cond * 100.0), S.GREEN if cond > 0.7 else (S.AMBER if cond > 0.35 else S.RED)))
		c.add_child(top)
		c.add_child(S.label("Cargo %d/%d cases%s · %d km driven" % [cargo.cases_used(), cargo.case_capacity,
			(" (" + _cargo_text(cargo) + ")") if not cargo.is_empty() else "", int(float(veh["km"]))], 15, S.MUTED))
		var acts := S.hbox(8)
		if game.driving != vid:
			acts.add_child(S.button("Find · set GPS", func(): find_vehicle(vid), true, 180))
			var q := game.delivery_quote(vid)
			var del := S.button("Deliver to me · %s" % EmpireData.money(float(q["fee"])) if q["ok"] else "Deliver to me", func():
				var err := game.deliver_vehicle(vid)
				toast(err if err != "" else "A driver is bringing it round – look for it on your street", "bad" if err != "" else "good")
				open_phone("vehicles"), false, 230)
			del.disabled = not q["ok"]
			acts.add_child(del)
			if not q["ok"]:
				acts.add_child(S.label(String(q["why"]), 14, S.MUTED))
		acts.add_child(S.spacer())
		var cost := float(EmpireData.file("vehicles").get("service_cost", 80.0)) * (1.5 - cond * 0.5)
		var svc := S.button("Mobile mechanic · %s" % EmpireData.money(cost), func():
			var err := e.service_vehicle(veh)
			toast(err if err != "" else "Serviced: back to 100%", "bad" if err != "" else "good")
			open_phone("vehicles"), false, 240)
		svc.disabled = cond > 0.95
		acts.add_child(svc)
		c.add_child(acts)
		list.add_child(cv[0])
	list.add_child(S.label("DEALER (delivered to the kerb beside you)", 14, S.AMBER, "black"))
	for mid in EmpireData.vehicle_models():
		var md2 := EmpireData.vehicle_model(mid)
		if float(md2.get("price", 0)) <= 0.0:
			continue
		list.add_child(_row([_fixed(String(md2["name"]), 220, 18, S.PAPER, "bold"),
			_fixed("%d cases · top %d mph" % [int(md2["cargo"]), int(float(md2["top_speed"]) * 2.237)], 260, 15, S.MUTED),
			S.spacer(),
			S.button("Buy · %s" % EmpireData.money(float(md2["price"])), func():
				var err := game.buy_vehicle(mid)
				toast(err if err != "" else "Delivered outside", "bad" if err != "" else "good")
				open_phone("vehicles"), true, 180)]))
	v.add_child(_scroll(list, 470))


static func _cargo_text(c: Stock) -> String:
	var names: Array = []
	for pid in c.units:
		names.append("%s ×%d" % [EmpireData.product(pid).get("name", pid), c.qty(pid)])
	return ", ".join(names.slice(0, 3)) + ("…" if names.size() > 3 else "")


## A notification's "show me": opens what it refers to.
func open_ref(ref: Dictionary) -> void:
	match String(ref.get("kind", "")):
		"biz":
			var b: Business = game.empire.business(String(ref.get("id", "")))
			if b:
				open_manage(b, String(ref.get("tab", "overview")))
		"unit":
			open_phone("map", {"kind": "unit", "id": String(ref.get("id", ""))})
		"vehicle":
			find_vehicle(String(ref.get("id", "")))
		"tab":
			open_phone(String(ref.get("id", "home")))
