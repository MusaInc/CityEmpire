class_name EmpireStyle
extends RefCounted
## City Empire's interface look: Outfit type (OFL, shared with the studio's
## other games), deep ink panels, a money green, a signal amber for calls to
## action. Sizes are for the 1280×720 canvas (stretch "expand"), large enough
## to tap on a phone.

const INK := Color("#0f1a22")
const INK2 := Color("#182733")
const LINE := Color(1, 1, 1, 0.09)
const PAPER := Color("#f3efe6")
const MUTED := Color("#9fb0ba")
const GREEN := Color("#39c27f")
const AMBER := Color("#f5b13d")
const RED := Color("#ec5a4a")
const BLUE := Color("#4ea3ef")
const PANEL := Color(0.055, 0.094, 0.125, 0.95)
const GOLD := Color("#e9c27a")

static var _theme: Theme
## A list was being dragged: the finger lifting isn't a tap (TouchScroll).
static var tap_block_until := 0


static func font(weight := "bold") -> Font:
	return UiStyle.font(weight)


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("semibold")
	t.default_font_size = 19
	t.set_color("font_color", "Label", PAPER)
	var btn := StyleBoxFlat.new()
	btn.bg_color = INK2
	btn.set_corner_radius_all(12)
	btn.content_margin_left = 18
	btn.content_margin_right = 18
	btn.content_margin_top = 10
	btn.content_margin_bottom = 10
	btn.border_color = LINE
	btn.set_border_width_all(1)
	btn.border_width_top = 2
	btn.border_color = Color(1, 1, 1, 0.1)
	var hov := btn.duplicate()
	hov.bg_color = INK2.lightened(0.12)
	var prs := btn.duplicate()
	prs.bg_color = AMBER.darkened(0.25)
	var dis := btn.duplicate()
	dis.bg_color = Color(INK2, 0.5)
	for s in ["normal", "focus"]:
		t.set_stylebox(s, "Button", btn)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", prs)
	t.set_stylebox("disabled", "Button", dis)
	t.set_color("font_color", "Button", PAPER)
	t.set_color("font_disabled_color", "Button", Color(PAPER, 0.35))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_font_size("font_size", "Button", 19)
	var pnl := StyleBoxFlat.new()
	pnl.bg_color = PANEL
	pnl.set_corner_radius_all(20)
	pnl.content_margin_left = 26
	pnl.content_margin_right = 26
	pnl.content_margin_top = 22
	pnl.content_margin_bottom = 22
	pnl.shadow_color = Color(0, 0, 0, 0.45)
	pnl.shadow_size = 24
	pnl.shadow_offset = Vector2(0, 6)
	pnl.border_color = Color(1, 1, 1, 0.07)
	pnl.set_border_width_all(1)
	pnl.border_width_top = 2
	pnl.anti_aliasing = true
	t.set_stylebox("panel", "PanelContainer", pnl)
	var sl := StyleBoxFlat.new()
	sl.bg_color = Color(1, 1, 1, 0.12)
	sl.set_corner_radius_all(4)
	sl.content_margin_top = 4
	sl.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", sl)
	var grab := StyleBoxFlat.new()
	grab.bg_color = AMBER
	grab.set_corner_radius_all(4)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.18)
	sb.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb)
	var sbg := StyleBoxEmpty.new()
	t.set_stylebox("scroll", "VScrollBar", sbg)
	_theme = t
	return t


static func label(text: String, size := 19, col := PAPER, weight := "semibold") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func button(text: String, cb: Callable, primary := false, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 52)
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		# Tactile: a lighter top lip and a darker base under the amber face.
		var sb := StyleBoxFlat.new()
		sb.bg_color = AMBER
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.border_color = AMBER.lightened(0.35)
		sb.border_width_top = 2
		sb.shadow_color = AMBER.darkened(0.55)
		sb.shadow_size = 0
		sb.shadow_offset = Vector2(0, 3)
		sb.expand_margin_bottom = 0
		b.add_theme_stylebox_override("normal", sb)
		var h := sb.duplicate()
		h.bg_color = AMBER.lightened(0.12)
		b.add_theme_stylebox_override("hover", h)
		var pr := sb.duplicate()
		pr.bg_color = AMBER.darkened(0.12)
		pr.border_width_top = 0
		b.add_theme_stylebox_override("pressed", pr)
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_font_override("font", font("bold"))
	b.pressed.connect(func():
		if Time.get_ticks_msec() < tap_block_until:
			return
		Sfx.play("click", -10.0)
		cb.call())
	return b


static func chip(text: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.18)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(text, 15, col, "bold"))
	return p


static func hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func row_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb
