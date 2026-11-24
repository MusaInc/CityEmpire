class_name Glass
extends RefCounted
## WORLDSTATE's interface language (2026-11-20 redesign): floating glass
## chrome over the live game, solid grouped content cards, SF Pro on Apple
## devices (the system font) and Inter elsewhere, a restrained gold accent,
## light and dark appearances.
##
## Glass (real background blur) is only used for floating chrome – the
## sidebar, tab bar, sheets, the map's floating controls and the HUD – the
## way iOS does; content sits on solid cards so lists stay cheap to draw.
##
## Sizes are logical px on the game's canvas: 1280×720 in landscape, 720×
## (tall) in portrait (Phone sets the scale). 1 pt ≈ 1.45 px.

const SHADER := preload("res://src/empire/ui/glass.gdshader")

# ------------------------------------------------------------- palette
static var dark := true
static var BG := Color(0.06, 0.06, 0.08, 0.80)        # the app's backdrop tint (over the blurred game)
static var CARD := Color("#1c1c1e")                    # grouped content cards
static var CARD2 := Color("#2c2c2e")                   # inside a card (wells, thumbnails)
static var LABEL := Color.WHITE
static var LABEL2 := Color(0.92, 0.92, 0.96, 0.62)
static var LABEL3 := Color(0.92, 0.92, 0.96, 0.32)
static var SEP := Color(0.33, 0.33, 0.35, 0.6)
static var FILL := Color(0.47, 0.47, 0.5, 0.24)       # gray buttons, search fields, tracks
static var FILL2 := Color(0.47, 0.47, 0.5, 0.36)
static var TINT := Color(0.12, 0.12, 0.14, 0.58)      # glass chrome tint
static var RIM := Color(1, 1, 1, 0.16)
static var ACCENT := Color("#f2bf4a")                  # gold: fills (sparingly)
static var ACCENT_TEXT := Color("#f2bf4a")             # gold as text/tint
static var ON_ACCENT := Color("#1d1606")
static var GREEN := Color("#30d158")
static var RED := Color("#ff453a")
static var BLUE := Color("#0a84ff")
static var ORANGE := Color("#ff9f0a")
static var PURPLE := Color("#bf5af2")
static var TEAL := Color("#40c8e0")
static var PINK := Color("#ff375f")

static var _materials := {}
static var mode := "auto"   # Settings: "auto" (follows the clock), "light", "dark"


static func set_dark(d: bool) -> void:
	dark = d
	if d:
		BG = Color(0.04, 0.04, 0.06, 0.24)
		CARD = Color(0.10, 0.10, 0.12, 0.86)
		CARD2 = Color(0.15, 0.16, 0.18, 0.88)
		LABEL = Color(0.96, 0.96, 0.97, 1.0)
		LABEL2 = Color(0.84, 0.85, 0.88, 0.68)
		LABEL3 = Color(0.80, 0.82, 0.86, 0.36)
		SEP = Color(1.0, 1.0, 1.0, 0.10)
		FILL = Color(1.0, 1.0, 1.0, 0.09)
		FILL2 = Color(1.0, 1.0, 1.0, 0.16)
		TINT = Color(0.08, 0.09, 0.11, 0.78)
		RIM = Color(1.0, 0.96, 0.88, 0.15)
		ACCENT = Color("#dfb963")
		ACCENT_TEXT = Color("#e6c576")
		GREEN = Color("#4cc38a")
		RED = Color("#e05a52")
		BLUE = Color("#8fa8c4")
		ORANGE = Color("#d8a454")
		PURPLE = Color("#a8a2b8")
		TEAL = Color("#7eb0b8")
		PINK = Color("#c88a96")
	else:
		BG = Color(0.08, 0.09, 0.11, 0.20)
		CARD = Color(0.96, 0.96, 0.97, 0.88)
		CARD2 = Color(0.91, 0.91, 0.93, 0.90)
		LABEL = Color(0.10, 0.10, 0.12, 1.0)
		LABEL2 = Color(0.24, 0.25, 0.28, 0.70)
		LABEL3 = Color(0.24, 0.25, 0.28, 0.36)
		SEP = Color(0.12, 0.12, 0.14, 0.12)
		FILL = Color(0.12, 0.12, 0.14, 0.08)
		FILL2 = Color(0.12, 0.12, 0.14, 0.14)
		TINT = Color(0.96, 0.96, 0.97, 0.82)
		RIM = Color(0.85, 0.78, 0.62, 0.35)
		ACCENT = Color("#cfa13e")
		ACCENT_TEXT = Color("#8f6814")
		GREEN = Color("#28895a")
		RED = Color("#c73832")
		BLUE = Color("#476a8c")
		ORANGE = Color("#a67120")
		PURPLE = Color("#6c667d")
		TEAL = Color("#3b737c")
		PINK = Color("#9b5968")
	EmpireStyle.sync()


## The appearance for now: Settings' choice, or (auto) light from 07:00 to
## 19:00 on the game clock and dark at night – the phone matches the sky.
static func want_dark(minute := -1.0) -> bool:
	match mode:
		"light":
			return false
		"dark":
			return true
	if minute < 0.0:
		return true
	var h := fmod(minute, 1440.0) / 60.0
	return h < 7.0 or h >= 19.0


## A palette colour by name (sections keep a colour name, not a value,
## so it follows the appearance).
static func named(n: String) -> Color:
	match n:
		"ACCENT":
			return ACCENT_TEXT
		"BLUE":
			return BLUE
		"GREEN":
			return GREEN
		"RED":
			return RED
		"ORANGE":
			return ORANGE
		"PURPLE":
			return PURPLE
		"TEAL":
			return TEAL
		"PINK":
			return PINK
	return LABEL2


# ---------------------------------------------------------------- type
static var _fonts := {}


## weight: "regular", "medium", "semibold", "bold"; display = big sizes.
static func font(weight := "regular", display := false) -> Font:
	var key := weight + ("_d" if display else "")
	if _fonts.has(key):
		return _fonts[key]
	var f: Font
	var file := {"regular": "Inter-Regular", "medium": "Inter-Medium", "semibold": "Inter-SemiBold", "bold": "Inter-Bold"}.get(weight, "Inter-Regular") as String
	if display and weight in ["bold", "semibold"]:
		file = "InterDisplay-Bold" if weight == "bold" else "InterDisplay-SemiBold"
	var path := "res://assets/fonts/inter/%s.ttf" % file
	var inter: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	if OS.get_name() in ["iOS", "macOS"]:
		# SF Pro is the system font there (not bundled: Apple's licence):
		# asked for by its system name, Inter as the fallback.
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([".AppleSystemUIFont", "SF Pro Text", "SF Pro Display", "Helvetica Neue"])
		sf.font_weight = {"regular": 400, "medium": 500, "semibold": 600, "bold": 700}.get(weight, 400)
		sf.fallbacks = [inter]
		f = sf
	else:
		f = inter
	_fonts[key] = f
	return f


## Text styles (logical px): iOS's ramp at ~1.45 px/pt.
const TYPE := {
	"large": [50, "bold", true], "title1": [40, "bold", true], "title2": [32, "bold", true], "title3": [27, "semibold", true],
	"headline": [24, "semibold", false], "body": [24, "regular", false], "callout": [22, "regular", false],
	"subhead": [21, "regular", false], "footnote": [19, "regular", false], "caption": [17, "regular", false],
	"caption2": [15, "medium", false], "num": [24, "semibold", false], "bignum": [56, "bold", true],
}


static func text(s: String, style := "body", col = null, weight := "") -> Label:
	var t: Array = TYPE.get(style, TYPE["body"])
	var l := Label.new()
	l.text = s
	l.add_theme_font_override("font", font(weight if weight != "" else String(t[1]), bool(t[2])))
	l.add_theme_font_size_override("font_size", int(t[0]))
	l.add_theme_color_override("font_color", col if col != null else LABEL)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A label that wraps inside its container width.
static func para(s: String, style := "subhead", col = null) -> Label:
	var l := text(s, style, col if col != null else LABEL2)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 120
	return l


## A single line that trims with an ellipsis.
static func line(s: String, style := "body", col = null, weight := "") -> Label:
	var l := text(s, style, col, weight)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 40
	return l


# ---------------------------------------------------------------- glass
static func clear_caches() -> void:
	_materials.clear()


static func material(tint: Color, blur := 3.2) -> ShaderMaterial:
	var key := "%s:%s_%.1f" % ["D" if dark else "L", tint.to_html(), blur]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("blur", blur)
	m.set_shader_parameter("sat", 1.5 if dark else 1.25)
	m.set_shader_parameter("lift", 0.0 if dark else 0.04)
	_materials[key] = m
	return m


## A floating glass surface (a PanelContainer: put content in it). Shadow,
## the blurred-backdrop body and a hairline rim are its own internal
## children; `radius` < 0 = a capsule. `frosted_fast = true` uses a crisp
## translucent StyleBoxFlat without a full-screen `hint_screen_texture` pass.
class Surface extends PanelContainer:
	var radius := 28.0
	var tint := Color(0, 0, 0, 0)
	var shadow := true
	var frosted_fast := false
	var _body: Panel
	var _rim: Panel
	var _shadow: Panel
	var _shadow_sb: StyleBoxFlat
	var _body_sb: StyleBoxFlat
	var _rim_sb: StyleBoxFlat
	var _styled_r := -1
	var _styled_dark := false
	var _styled_fast := false
	var _styled_tint := Color(-1, -1, -1, -1)

	func _init(p_radius := 28.0, pad := 0.0, p_tint := Color(0, 0, 0, 0), p_shadow := true, p_fast := false) -> void:
		radius = p_radius
		tint = p_tint
		shadow = p_shadow
		frosted_fast = p_fast
		var e := StyleBoxEmpty.new()
		for s in ["left", "right", "top", "bottom"]:
			e.set("content_margin_" + s, pad)
		add_theme_stylebox_override("panel", e)
		mouse_filter = Control.MOUSE_FILTER_STOP
		if shadow:
			_shadow = _layer()
			_shadow_sb = StyleBoxFlat.new()
			_shadow_sb.bg_color = Color(0, 0, 0, 0)
			_shadow_sb.shadow_size = 22
			_shadow_sb.shadow_offset = Vector2(0, 8)
			_shadow_sb.anti_aliasing = true
			_shadow.add_theme_stylebox_override("panel", _shadow_sb)
		_body = _layer()
		_body_sb = StyleBoxFlat.new()
		_body_sb.anti_aliasing = true
		_body_sb.corner_detail = 10
		_body.add_theme_stylebox_override("panel", _body_sb)
		_rim = _layer()
		_rim_sb = StyleBoxFlat.new()
		_rim_sb.bg_color = Color(0, 0, 0, 0)
		_rim_sb.set_border_width_all(1)
		_rim_sb.anti_aliasing = true
		_rim_sb.corner_detail = 10
		_rim.add_theme_stylebox_override("panel", _rim_sb)
		_restyle()
		resized.connect(_restyle)

	func _layer() -> Panel:
		var p := Panel.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(p, false, Node.INTERNAL_MODE_FRONT)
		return p

	func _r() -> int:
		return int(size.y * 0.5) if radius < 0.0 else int(radius)

	func _restyle() -> void:
		var r := _r()
		var t: Color = tint if tint.a > 0.0 else Glass.TINT
		if r == _styled_r and _styled_dark == Glass.dark and _styled_fast == frosted_fast and _styled_tint == t:
			return
		_styled_r = r
		_styled_dark = Glass.dark
		_styled_fast = frosted_fast
		_styled_tint = t
		if _shadow and _shadow_sb:
			_shadow_sb.set_corner_radius_all(r)
			_shadow_sb.shadow_color = Color(0, 0, 0, 0.28 if Glass.dark else 0.14)
		_body_sb.set_corner_radius_all(r)
		if frosted_fast:
			_body.material = null
			if tint.a > 0.0:
				_body_sb.bg_color = Color(t.r, t.g, t.b, clampf(t.a + 0.24, 0.80, 0.94))
			else:
				_body_sb.bg_color = Color(0.11, 0.11, 0.13, 0.86) if Glass.dark else Color(0.97, 0.97, 0.99, 0.92)
		else:
			_body_sb.bg_color = Color.WHITE
			_body.material = Glass.material(t)
		_rim_sb.set_corner_radius_all(r)
		_rim_sb.border_color = Glass.RIM


static func surface(radius := 28.0, pad := 0.0, tint := Color(0, 0, 0, 0), shadow := true, frosted_fast := false) -> Surface:
	return Surface.new(radius, pad, tint, shadow, frosted_fast)


# ---------------------------------------------------------------- cards
static func box(col: Color, radius := 22, pad := 18.0, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	sb.corner_detail = 8
	for s in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + s, pad)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	return sb


## A solid content card; returns [card, its VBox].
static func card(pad := 20.0, sep := 12, col = null) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(col if col != null else CARD, 24, pad))
	var v := vbox(sep)
	p.add_child(v)
	return [p, v]


## Something drawn clipped to a rounded rectangle (photos, maps, renders).
static func rounded(child: Control, sz: Vector2, radius := 18) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = sz
	p.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	p.add_theme_stylebox_override("panel", box(CARD2, radius, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if child:
		child.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(child)
	return p


static func hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer(w := 0.0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if w > 0.0:
		c.custom_minimum_size = Vector2(w, w)
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func margin(child: Control, l := 0, t := 0, r := 0, b := 0) -> MarginContainer:
	var m := MarginContainer.new()
	for k in [["left", l], ["top", t], ["right", r], ["bottom", b]]:
		m.add_theme_constant_override("margin_" + String(k[0]), int(k[1]))
	m.add_child(child)
	return m


# ------------------------------------------------------------- feedback
## Every tap answers: the control dips (spring back), a light haptic on
## devices, the click sound – and a drag that scrolled a list isn't a tap.
static func feedback(b: BaseButton, cb: Callable, sound := true) -> void:
	b.button_down.connect(func():
		b.pivot_offset = b.size * 0.5
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(0.965, 0.965), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	b.button_up.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT))
	b.pressed.connect(func():
		if Time.get_ticks_msec() < EmpireStyle.tap_block_until:
			return
		if sound:
			Sfx.play("click", -14.0)
		haptic()
		cb.call())


static func haptic(ms := 8) -> void:
	if OS.get_name() in ["iOS", "Android"]:
		Input.vibrate_handheld(ms, 0.35)


static func _btn_box(bg: Color, radius: int, padx: float) -> StyleBoxFlat:
	var sb := box(bg, radius, 0)
	sb.content_margin_left = padx
	sb.content_margin_right = padx
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## Buttons. kind: "filled" (gold, the one main action), "tinted" (a colour
## at low opacity), "gray" (secondary), "plain" (text only), "glass".
## size: "large" (60), "regular" (52), "small" (42). Capsules.
static func button(label: String, cb: Callable, kind := "gray", sz := "regular", col = null, icon := "") -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	var h: float = {"large": 62.0, "regular": 52.0, "small": 42.0}.get(sz, 52.0)
	b.custom_minimum_size = Vector2(h, h)
	var c: Color = col if col != null else ACCENT
	var bg: Color
	var fg: Color
	match kind:
		"filled":
			bg = c
			fg = ON_ACCENT if col == null else Color.WHITE
		"tinted":
			bg = Color(c, 0.18 if dark else 0.14)
			fg = c if col != null else ACCENT_TEXT
		"plain":
			bg = Color(0, 0, 0, 0)
			fg = c if col != null else ACCENT_TEXT
		"glass":
			bg = Color(TINT, 0.0)
			fg = LABEL
		_:
			bg = FILL
			fg = col if col != null else LABEL
	var r := int(h * 0.5)
	var padx: float = {"large": 28.0, "regular": 22.0, "small": 16.0}.get(sz, 22.0)
	var n := _btn_box(bg, r, padx)
	var p := _btn_box(Color(bg.lerp(LABEL, 0.12), maxf(bg.a, 0.18)) if kind != "plain" else Color(FILL, 0.0), r, padx)
	var d := _btn_box(Color(bg, bg.a * 0.45), r, padx)
	for s in ["normal", "focus", "hover"]:
		b.add_theme_stylebox_override(s, n)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(s, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.38))
	b.add_theme_font_override("font", font("semibold"))
	b.add_theme_font_size_override("font_size", {"large": 24, "regular": 22, "small": 19}.get(sz, 22))
	if icon != "":
		var ic := Symbol.new(icon, fg, h * 0.42)
		b.add_child(ic)
		b.text = ("      " if label != "" else "") + label
		b.resized.connect(func():
			ic.position = Vector2(padx * 0.8 if label != "" else (b.size.x - ic.size.x) * 0.5, (b.size.y - ic.size.y) * 0.5))
	feedback(b, cb)
	return b


## A round icon button (close, back, locate…): glass or gray.
static func icon_button(icon: String, cb: Callable, glass := false, px := 52.0, col = null) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px, px)
	var bg := Color(0, 0, 0, 0) if glass else FILL
	for s in ["normal", "focus", "hover", "disabled"]:
		b.add_theme_stylebox_override(s, box(bg, int(px * 0.5), 0))
	b.add_theme_stylebox_override("pressed", box(FILL2, int(px * 0.5), 0))
	var ic := Symbol.new(icon, col if col != null else LABEL, px * 0.44)
	ic.position = Vector2(px, px) * 0.28
	b.add_child(ic)
	feedback(b, cb)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if glass:
		var s := surface(-1.0, 0.0, Color(0, 0, 0, 0), true, true)
		s.custom_minimum_size = Vector2(px, px)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		s.add_child(b)
		return s
	return b


## Tap-to-confirm button: first tap arms in place for 3 seconds (green for
## purchases, red for destructive/sell actions); second tap fires `cb`.
static func confirm_button(label: String, confirm: String, cb: Callable, sz := "large", col = null, kind := "filled") -> Button:
	var armed := [false]
	var destructive: bool = col != null and col == RED
	var padx: float = {"large": 28.0, "regular": 22.0, "small": 16.0}.get(sz, 22.0)
	var b := button(label, func(): pass, kind, sz, col)
	var orig_box := b.get_theme_stylebox("normal")
	var orig_fg := b.get_theme_color("font_color")
	b.pressed.connect(func():
		if Time.get_ticks_msec() < EmpireStyle.tap_block_until:
			return
		if armed[0]:
			armed[0] = false
			cb.call()
			return
		armed[0] = true
		b.text = confirm
		var arm_col: Color = RED if destructive else GREEN
		var gs := _btn_box(arm_col, int(maxf(b.size.y, b.custom_minimum_size.y) * 0.5), padx)
		for s in ["normal", "focus", "hover"]:
			b.add_theme_stylebox_override(s, gs)
		for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(s, Color.WHITE)
		b.get_tree().create_timer(3.0, true, false, true).timeout.connect(func():
			if is_instance_valid(b) and armed[0]:
				armed[0] = false
				b.text = label
				for s in ["normal", "focus", "hover"]:
					b.add_theme_stylebox_override(s, orig_box)
				for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
					b.add_theme_color_override(s, orig_fg)))
	return b


## A selectable capsule (filters): filled when on.
static func pill(label: String, on: bool, cb: Callable, col = null) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	var c: Color = col if col != null else LABEL
	var bg := Color(c, 0.92) if on else FILL
	var fg := (CARD if col == null else Color.WHITE) if on else LABEL
	if on and col == null:
		fg = Color.BLACK if dark else Color.WHITE
	var n := _btn_box(bg, 22, 18)
	for s in ["normal", "focus", "hover", "pressed"]:
		b.add_theme_stylebox_override(s, n)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, fg)
	b.add_theme_font_override("font", font("semibold" if on else "medium"))
	b.add_theme_font_size_override("font_size", 19)
	feedback(b, cb)
	return b


## A row of filter pills that scrolls sideways when it doesn't fit.
static func pills(items: Array, current: String, cb: Callable) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.custom_minimum_size.y = 48
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := hbox(8)
	for it in items:
		var key := String(it[0])
		h.add_child(pill(String(it[1]), key == current, func(): cb.call(key), it[2] if it.size() > 2 else null))
	sc.add_child(h)
	return sc


## Segmented control: a gray track with the chosen segment raised.
static func segmented(items: Array, current: String, cb: Callable) -> PanelContainer:
	var track := PanelContainer.new()
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tb := box(FILL, 18, 3)
	track.add_theme_stylebox_override("panel", tb)
	var h := hbox(2)
	track.add_child(h)
	for it in items:
		var key := String(it[0])
		var on := key == current
		var b := Button.new()
		b.text = String(it[1])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := box(Color(0.39, 0.39, 0.4, 1.0) if (on and dark) else (Color.WHITE if on else Color(0, 0, 0, 0)), 15, 0)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		if on:
			sb.shadow_color = Color(0, 0, 0, 0.12)
			sb.shadow_size = 4
			sb.shadow_offset = Vector2(0, 2)
		for s in ["normal", "focus", "hover", "pressed"]:
			b.add_theme_stylebox_override(s, sb)
		for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(s, LABEL)
		b.add_theme_font_override("font", font("semibold" if on else "medium"))
		b.add_theme_font_size_override("font_size", 19)
		feedback(b, func(): cb.call(key))
		h.add_child(b)
	return track


## Search field: a gray capsule with a magnifier; `cb(text)` as you type.
static func search(placeholder: String, value: String, cb: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.text = value
	le.custom_minimum_size = Vector2(160, 50)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := box(FILL, 25, 0)
	sb.content_margin_left = 52
	sb.content_margin_right = 18
	le.add_theme_stylebox_override("normal", sb)
	var fs := sb.duplicate() as StyleBoxFlat
	fs.border_color = Color(ACCENT_TEXT, 0.6)
	fs.set_border_width_all(1)
	le.add_theme_stylebox_override("focus", fs)
	le.add_theme_font_override("font", font("regular"))
	le.add_theme_font_size_override("font_size", 22)
	le.add_theme_color_override("font_color", LABEL)
	le.add_theme_color_override("font_placeholder_color", LABEL2)
	le.add_theme_color_override("caret_color", ACCENT_TEXT)
	le.clear_button_enabled = true
	var ic := Symbol.new("search", LABEL2, 22)
	ic.position = Vector2(18, 14)
	le.add_child(ic)
	le.text_changed.connect(func(t): cb.call(t))
	return le


# ---------------------------------------------------------------- lists
## An inset grouped list (Settings-style): rows on one card with hairlines
## between them (inset past the icon).
static func group(rows: Array, header := "", footer := "") -> VBoxContainer:
	var outer := vbox(8)
	if header != "":
		outer.add_child(margin(text(header, "headline", LABEL), 6, 6, 0, 0))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(CARD, 22, 0))
	var v := vbox(0)
	p.add_child(v)
	for i in rows.size():
		v.add_child(rows[i])
		if i < rows.size() - 1:
			var hr := ColorRect.new()
			hr.color = SEP
			hr.custom_minimum_size.y = 1
			hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(margin(hr, 76 if (rows[i] as Control).has_meta("icon") else 22, 0, 0, 0))
	outer.add_child(p)
	if footer != "":
		outer.add_child(margin(para(footer, "footnote"), 6, 0, 6, 0))
	return outer


## One row: [icon tile] title / subtitle … value [›]. cb = null: static.
static func row(title: String, sub := "", value := "", icon := "", icon_col = null, cb = null, value_col = null) -> Control:
	var b: Control
	if cb != null:
		var bt := Button.new()
		bt.focus_mode = Control.FOCUS_NONE
		var n := box(Color(0, 0, 0, 0), 22, 0)
		var pr := box(FILL, 0, 0)
		for s in ["normal", "focus", "hover", "disabled"]:
			bt.add_theme_stylebox_override(s, n)
		bt.add_theme_stylebox_override("pressed", pr)
		feedback(bt, cb)
		b = bt
	else:
		b = Control.new()
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.custom_minimum_size.y = 72 if sub != "" else 60
	var h := hbox(16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	h.offset_right = -16
	b.add_child(h)
	if icon != "":
		b.set_meta("icon", true)
		h.add_child(icon_tile(icon, icon_col if icon_col != null else BLUE, 42))
	var tv := vbox(0)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(line(title, "body"))
	if sub != "":
		tv.add_child(line(sub, "footnote", LABEL2))
	h.add_child(tv)
	if value != "":
		var vl := text(value, "body", value_col if value_col != null else LABEL2)
		vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(vl)
	if cb != null:
		var ch := Symbol.new("chevron", LABEL3, 18)
		ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ch)
	return b


## A rounded colour tile with a white symbol (Settings' row icons).
static func icon_tile(icon: String, col: Color, px := 42.0) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(px, px)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", box(col, int(px * 0.26), 0))
	var s := Symbol.new(icon, Color.WHITE, px * 0.6)
	s.position = Vector2(px, px) * 0.2
	p.add_child(s)
	return p


## Section heading with an optional trailing link ("See all ›").
static func header(title: String, link := "", cb = null) -> HBoxContainer:
	var h := hbox(8)
	h.add_child(text(title, "title3"))
	h.add_child(spacer())
	if link != "" and cb != null:
		h.add_child(button(link, cb, "plain", "small"))
	return h


## A big number with a caption above (Wallet/Stocks figures).
static func figure(caption: String, value: String, col = null, size := "title1") -> VBoxContainer:
	var v := vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(text(caption, "footnote", LABEL2, "medium"))
	v.add_child(text(value, size, col if col != null else LABEL))
	return v


## A small status capsule (TO LET, FOR SALE…).
static func badge(s: String, col: Color, on_photo := false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(0, 0, 0, 0.55) if on_photo else Color(col, 0.16), 12, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(text(s, "caption2", Color.WHITE if on_photo else col, "semibold"))
	return p


# ------------------------------------------------------------- symbols
## Line symbols in the SF Symbols spirit (rounded 2 px strokes). Keys the
## old icon set has fall through to EmpireWidgets.Icon.
class Symbol extends Control:
	var key := ""
	var color := Color.WHITE
	var _old: Control

	func _init(p_key := "", p_color := Color.WHITE, px := 26.0) -> void:
		key = p_key
		color = p_color
		custom_minimum_size = Vector2(px, px)
		size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not key in Glass.OWN:
			_old = EmpireWidgets.Icon.new(key, color, px)
			add_child(_old)

	func _draw() -> void:
		if _old:
			return
		var s := size.x / 24.0
		var w := maxf(1.6, 2.0 * s)
		var c := color
		var p := func(x: float, y: float) -> Vector2: return Vector2(x, y) * s
		match key:
			"chevron":
				draw_polyline(PackedVector2Array([p.call(9, 5), p.call(16, 12), p.call(9, 19)]), c, w * 1.1, true)
			"back":
				draw_polyline(PackedVector2Array([p.call(15, 4), p.call(7, 12), p.call(15, 20)]), c, w * 1.2, true)
			"close":
				draw_line(p.call(6, 6), p.call(18, 18), c, w * 1.1, true)
				draw_line(p.call(18, 6), p.call(6, 18), c, w * 1.1, true)
			"search":
				draw_arc(p.call(10.5, 10.5), 6.5 * s, 0, TAU, 28, c, w, true)
				draw_line(p.call(15.3, 15.3), p.call(20.5, 20.5), c, w * 1.2, true)
			"bag":
				draw_rect(Rect2(p.call(4, 8), p.call(16, 13)), c, false, w)
				draw_arc(p.call(12, 8), 4.0 * s, PI, TAU, 14, c, w, true)
			"chart":
				draw_polyline(PackedVector2Array([p.call(3, 18), p.call(9, 11), p.call(13, 14), p.call(21, 5)]), c, w, true)
				draw_line(p.call(16, 5), p.call(21, 5), c, w, true)
				draw_line(p.call(21, 5), p.call(21, 10), c, w, true)
			"person":
				draw_arc(p.call(12, 8), 4.0 * s, 0, TAU, 20, c, w, true)
				draw_arc(p.call(12, 22), 8.0 * s, PI + 0.35, TAU - 0.35, 20, c, w, true)
			"compass":
				draw_arc(p.call(12, 12), 9.0 * s, 0, TAU, 32, c, w, true)
				draw_colored_polygon(PackedVector2Array([p.call(15.5, 8.5), p.call(13, 13), p.call(8.5, 15.5), p.call(11, 11)]), c)
			"clock":
				draw_arc(p.call(12, 12), 9.0 * s, 0, TAU, 32, c, w, true)
				draw_polyline(PackedVector2Array([p.call(12, 7), p.call(12, 12), p.call(15.5, 14)]), c, w, true)
			"grid":
				for gx in 2:
					for gy in 2:
						draw_rect(Rect2(p.call(4 + gx * 9, 4 + gy * 9), p.call(7, 7)), c, false, w)
			"location":
				draw_colored_polygon(PackedVector2Array([p.call(20, 4), p.call(12, 21), p.call(11, 13), p.call(3, 12)]), c)
			"plus":
				draw_line(p.call(12, 5), p.call(12, 19), c, w * 1.1, true)
				draw_line(p.call(5, 12), p.call(19, 12), c, w * 1.1, true)
			"minus":
				draw_line(p.call(5, 12), p.call(19, 12), c, w * 1.1, true)
			"layers":
				draw_polyline(PackedVector2Array([p.call(12, 4), p.call(21, 9), p.call(12, 14), p.call(3, 9), p.call(12, 4)]), c, w, true)
				draw_polyline(PackedVector2Array([p.call(3, 14), p.call(12, 19), p.call(21, 14)]), c, w, true)
			"star":
				var pts := PackedVector2Array()
				for i in 10:
					var a := -PI * 0.5 + i * PI / 5.0
					var rr := (9.0 if i % 2 == 0 else 4.0) * s
					pts.append(p.call(12, 12.5) + Vector2(cos(a), sin(a)) * rr)
				pts.append(pts[0])
				draw_polyline(pts, c, w * 0.9, true)
			"sidebar":
				draw_rect(Rect2(p.call(3, 5), p.call(18, 14)), c, false, w)
				draw_line(p.call(9, 5), p.call(9, 19), c, w, true)
			"car":
				draw_polyline(PackedVector2Array([p.call(3, 16), p.call(3, 12), p.call(6, 7), p.call(18, 7), p.call(21, 12), p.call(21, 16), p.call(3, 16)]), c, w, true)
				draw_circle(p.call(7.5, 17), 2.2 * s, c)
				draw_circle(p.call(16.5, 17), 2.2 * s, c)
			"tag":
				draw_polyline(PackedVector2Array([p.call(4, 4), p.call(12, 4), p.call(21, 13), p.call(13, 21), p.call(4, 12), p.call(4, 4)]), c, w, true)
				draw_circle(p.call(8.5, 8.5), 1.6 * s, c)
			"shirt":
				draw_polyline(PackedVector2Array([p.call(8, 4), p.call(3, 7), p.call(5, 11), p.call(7, 10), p.call(7, 20), p.call(17, 20),
					p.call(17, 10), p.call(19, 11), p.call(21, 7), p.call(16, 4), p.call(14, 6), p.call(10, 6), p.call(8, 4)]), c, w, true)
			"heart":
				draw_arc(p.call(8.5, 9), 4.0 * s, PI, TAU, 12, c, w, true)
				draw_arc(p.call(15.5, 9), 4.0 * s, PI, TAU, 12, c, w, true)
				draw_polyline(PackedVector2Array([p.call(4.5, 9.5), p.call(12, 20), p.call(19.5, 9.5)]), c, w, true)
			"globe":
				draw_arc(p.call(12, 12), 9.0 * s, 0, TAU, 32, c, w, true)
				draw_line(p.call(3, 12), p.call(21, 12), c, w * 0.8, true)
				draw_arc(p.call(12, 12), 9.0 * s, -PI * 0.5, PI * 0.5, 20, c, w * 0.8, true)
				draw_set_transform(Vector2.ZERO)
			"dot":
				draw_circle(p.call(12, 12), 5.0 * s, c)
			_:
				draw_arc(p.call(12, 12), 8.0 * s, 0, TAU, 24, c, w, true)


## Symbols drawn here (the rest are EmpireWidgets.Icon's).
const OWN := ["chevron", "back", "close", "search", "bag", "chart", "person", "compass", "clock", "grid", "location", "plus",
	"minus", "layers", "star", "sidebar", "car", "tag", "shirt", "heart", "globe", "dot"]
