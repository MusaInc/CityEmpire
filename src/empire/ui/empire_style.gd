class_name EmpireStyle
extends RefCounted
## The older screens' helpers, now drawn in the Glass language (2026-11-20
## redesign): the same names (PAPER = primary label, MUTED = secondary,
## AMBER = the gold accent as text…) so every screen built with them takes
## the new look and the current light/dark appearance. New screens use
## Glass directly.

static var INK := Color("#1d1606")       # text on the gold accent
static var INK2 := Color("#2c2c2e")      # wells inside cards
static var LINE := Color(0.33, 0.33, 0.35, 0.6)
static var PAPER := Color.WHITE          # primary label
static var MUTED := Color(0.92, 0.92, 0.96, 0.62)
static var GREEN := Color("#30d158")
static var AMBER := Color("#f5c75a")
static var RED := Color("#ff453a")
static var BLUE := Color("#0a84ff")
static var PANEL := Color("#1c1c1e")
static var GOLD := Color("#f5c75a")

static var _theme: Theme
static var _theme_dark := true
## A list was being dragged: the finger lifting isn't a tap (TouchScroll).
static var tap_block_until := 0


## Glass.set_dark calls this: the old names follow the appearance.
static func sync() -> void:
	INK = Glass.ON_ACCENT
	INK2 = Glass.CARD2
	LINE = Glass.SEP
	PAPER = Glass.LABEL
	MUTED = Glass.LABEL2
	GREEN = Glass.GREEN
	AMBER = Glass.ACCENT_TEXT
	RED = Glass.RED
	BLUE = Glass.BLUE
	PANEL = Glass.CARD
	GOLD = Glass.ACCENT_TEXT
	if _theme and _theme_dark != Glass.dark:
		_theme = null


## Old weights onto the new type: semibold = body, bold = emphasis, black = titles.
static func font(weight := "bold") -> Font:
	return Glass.font({"semibold": "medium", "bold": "semibold", "black": "bold"}.get(weight, "medium"))


static func theme() -> Theme:
	if _theme:
		return _theme
	_theme_dark = Glass.dark
	var t := Theme.new()
	t.default_font = Glass.font("regular")
	t.default_font_size = 21
	t.set_color("font_color", "Label", PAPER)
	var btn := Glass.box(Glass.FILL, 26, 0)
	btn.content_margin_left = 20
	btn.content_margin_right = 20
	btn.content_margin_top = 8
	btn.content_margin_bottom = 8
	var prs := btn.duplicate() as StyleBoxFlat
	prs.bg_color = Glass.FILL2
	var dis := btn.duplicate() as StyleBoxFlat
	dis.bg_color = Color(Glass.FILL, Glass.FILL.a * 0.5)
	for s in ["normal", "focus", "hover"]:
		t.set_stylebox(s, "Button", btn)
	t.set_stylebox("pressed", "Button", prs)
	t.set_stylebox("disabled", "Button", dis)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(s, "Button", PAPER)
	t.set_color("font_disabled_color", "Button", Color(PAPER, 0.35))
	t.set_font_size("font_size", "Button", 21)
	t.set_font("font", "Button", Glass.font("semibold"))
	var pnl := Glass.box(Glass.CARD, 28, 26)
	pnl.content_margin_top = 22
	pnl.content_margin_bottom = 22
	t.set_stylebox("panel", "PanelContainer", pnl)
	var sl := StyleBoxFlat.new()
	sl.bg_color = Glass.FILL2
	sl.set_corner_radius_all(4)
	sl.content_margin_top = 3
	sl.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", sl)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Glass.ACCENT
	grab.set_corner_radius_all(4)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	var le := Glass.box(Glass.FILL, 22, 0)
	le.content_margin_left = 18
	le.content_margin_right = 18
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate() as StyleBoxFlat
	lef.border_color = Color(Glass.ACCENT_TEXT, 0.7)
	lef.set_border_width_all(1)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", PAPER)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.8))
	t.set_color("caret_color", "LineEdit", AMBER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PAPER, 0.22)
	sb.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	t.set_stylebox("scroll", "HScrollBar", StyleBoxEmpty.new())
	t.set_stylebox("grabber", "HScrollBar", StyleBoxEmpty.new())
	_theme = t
	return t


static func label(text: String, size := 19, col = null, weight := "semibold") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Glass.font({"semibold": "regular", "bold": "semibold", "black": "bold"}.get(weight, "regular"), size >= 26))
	l.add_theme_font_size_override("font_size", int(round(size * 1.08)))
	l.add_theme_color_override("font_color", col if col != null else PAPER)
	return l


## primary = the gold filled capsule (one per screen, ideally); else gray.
static func button(text: String, cb: Callable, primary := false, min_w := 0.0) -> Button:
	var b := Glass.button(text, cb, "filled" if primary else "gray", "regular")
	b.custom_minimum_size.x = min_w
	return b


## A tappable filter pill: filled when on.
static func chip_button(text: String, on: bool, cb: Callable, col = null) -> Button:
	return Glass.pill(text, on, cb, null if col == null or col == AMBER else col)


static func chip(text: String, col: Color) -> PanelContainer:
	return Glass.badge(text, col)


static func hbox(sep := 12) -> HBoxContainer:
	return Glass.hbox(sep)


static func vbox(sep := 10) -> VBoxContainer:
	return Glass.vbox(sep)


static func spacer() -> Control:
	return Glass.spacer()


static func row_bg() -> StyleBoxFlat:
	var sb := Glass.box(Color(PAPER, 0.045), 16, 0)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb
