class_name CatalogArt
extends RefCounted
## Catalogue photography for the phone (Premium UI pass, 2026-11-26):
## Blender studio renders of every purchasable vehicle, aircraft and boat
## (tools/catalog/run.sh → assets/ui/catalog/<model>_<view>.jpg, 1280×720),
## loaded lazily on a thread like the property photos (PhotoBook.Photo).
## No live 3D: a model without a render falls back to Thumbs' one-off shot.
##
## Also the two building blocks the Garage, Marketplace and Properties use:
## Gallery (one big swipeable image, page dots, arrows) and showcase()
## (an image-led card: the picture fills it, words on a soft scrim).

const G = preload("res://src/empire/ui/glass.gd")
const DIR := "res://assets/ui/catalog/"
const VIEWS := ["hero", "side", "rear", "detail"]
const VIEW_NAMES := {"hero": "Front", "side": "Profile", "rear": "Rear", "detail": "Detail"}
## Models that share another's photography.
const ALIAS := {"used_kestrel": "hatch"}
const GOLD := Color("#d9b26a")


static func key(model: String) -> String:
	return String(ALIAS.get(model, model))


static func path(model: String, view := "hero") -> String:
	return DIR + key(model) + "_" + view + ".jpg"


static func has(model: String, view := "hero") -> bool:
	return ResourceLoader.exists(path(model, view))


static func views(model: String) -> Array:
	return VIEWS.filter(func(v): return has(model, v))


## The picture of a model filling its parent: the studio render if there is
## one, else the live one-off shot.
static func picture(ui: EmpireUI, model: String, view := "hero", fallback_size := Vector2(640, 360)) -> Control:
	if has(model, view):
		var p := PhotoBook.Photo.new()
		p.src = path(model, view)
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return p
	var t := ui.thumbs.vehicle(model, fallback_size)
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return t


## A soft dark fade from the bottom (and a lighter one from the top) so
## white words sit on any photo.
static func scrim(strength := 0.78, top := 0.0) -> TextureRect:
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gr.colors = PackedColorArray([Color(0, 0, 0, top), Color(0, 0, 0, 0.0), Color(0, 0, 0, strength)])
	var gt := GradientTexture2D.new()
	gt.gradient = gr
	gt.width = 4
	gt.height = 128
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr


## An image-led card: `pic` fills it (rounded, clipped), the title, a line
## under it and the price sit on a scrim at the bottom; an optional badge
## top-left and a gold hairline when selected.
static func showcase(pic: Control, sz: Vector2, title: String, sub: String, price: String, badge := "", badge_col := Color.WHITE,
		cb = null, selected := false, price_col := Color.WHITE) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = sz
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["normal", "focus", "hover", "disabled", "pressed"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	var frame := Panel.new()
	frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel", G.box(Color(0.07, 0.075, 0.085), 24, 0))
	b.add_child(frame)
	if pic:
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.add_child(pic)
	frame.add_child(scrim(0.82, 0.18))
	var words := G.vbox(0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_END
	var wm := G.margin(words, 20, 12, 20, 16)
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(wm)
	var t := G.line(title, "headline", Color.WHITE)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(t)
	var bottom := G.hbox(10)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(bottom)
	var s2 := G.line(sub, "footnote", Color(1, 1, 1, 0.72))
	s2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s2.clip_text = true
	bottom.add_child(s2)
	if price != "":
		bottom.add_child(G.text(price, "callout", GOLD if price_col == Color.WHITE else price_col, "semibold"))
	if badge != "":
		var bd := G.badge(badge, badge_col, true)
		bd.position = Vector2(14, 14)
		frame.add_child(bd)
	# a fine rim (gold when it's the one on show)
	var rim := Panel.new()
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rs := StyleBoxFlat.new()
	rs.draw_center = false
	rs.set_corner_radius_all(24)
	rs.set_border_width_all(3 if selected else 1)
	rs.border_color = GOLD if selected else Color(1, 1, 1, 0.10)
	rim.add_theme_stylebox_override("panel", rs)
	b.add_child(rim)
	b.button_down.connect(func(): b.scale = Vector2(0.985, 0.985))
	b.button_up.connect(func(): b.scale = Vector2.ONE)
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	if cb != null:
		G.feedback(b, cb)
	return b


## One large image you swipe through (or tap the arrows / dots): `makers`
## are Callables returning the Control for each page (filled to the frame).
## `captions` (optional) label each page in the corner.
class Gallery extends Panel:
	var makers: Array = []
	var captions: Array = []
	var index := 0
	var radius := 28
	## height / width; > 0 keeps the frame that shape at whatever width the
	## layout gives it (the page may still be 0 wide when it's built).
	var aspect := 0.5625
	var _strip: Control
	var _pages: Array = []
	var _dots: HBoxContainer
	var _cap: Label
	var _offset := 0.0
	var _drag := false
	var _press := Vector2.INF
	var _finger := -1
	var _tw: Tween

	func _init(p_makers: Array = [], p_captions: Array = [], p_index := 0, p_radius := 28) -> void:
		makers = p_makers
		captions = p_captions
		index = clampi(p_index, 0, maxi(0, p_makers.size() - 1))
		radius = p_radius
		clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		mouse_filter = Control.MOUSE_FILTER_PASS
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _ready() -> void:
		add_theme_stylebox_override("panel", Glass.box(Color(0.07, 0.075, 0.085), radius, 0))
		_strip = Control.new()
		_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_strip)
		for i in makers.size():
			var holder := Control.new()
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.clip_contents = true
			_strip.add_child(holder)
			_pages.append(holder)
			var c: Control = (makers[i] as Callable).call()
			if c:
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE
				c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				holder.add_child(c)
		add_child(CatalogArt.scrim(0.38, 0.0))
		if makers.size() > 1:
			_dots = HBoxContainer.new()
			_dots.add_theme_constant_override("separation", 8)
			_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_dots)
			for i in makers.size():
				var d := Panel.new()
				d.mouse_filter = Control.MOUSE_FILTER_IGNORE
				d.custom_minimum_size = Vector2(8, 8)
				_dots.add_child(d)
			for side in [-1, 1]:
				var sd := int(side)
				var ab := Glass.icon_button("chevron" if sd > 0 else "back", func(): go(index + sd), true, 44.0, Color.WHITE)
				ab.name = "Arrow%d" % sd
				add_child(ab)
		if not captions.is_empty():
			var cp := PanelContainer.new()
			var sb := Glass.box(Color(0, 0, 0, 0.45), 12, 0)
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			cp.add_theme_stylebox_override("panel", sb)
			cp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cp.name = "Caption"
			_cap = Glass.text("", "caption2", Color.WHITE, "semibold")
			cp.add_child(_cap)
			add_child(cp)
			# (anchored top-right, growing left: sizes itself to its words)
			cp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			cp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			cp.offset_right = -16
			cp.offset_top = 16
		resized.connect(_layout)
		_layout()

	func _layout() -> void:
		if _strip == null:
			return
		var w := size.x
		if aspect > 0.0 and w > 1.0 and absf(custom_minimum_size.y - w * aspect) > 1.0:
			custom_minimum_size.y = w * aspect   # (a container resizes us again)
		for i in _pages.size():
			var h: Control = _pages[i]
			h.position = Vector2(w * i, 0)
			h.size = size
		_strip.size = Vector2(w * maxf(1, _pages.size()), size.y)
		_offset = -w * index
		_strip.position.x = _offset
		if _dots:
			_dots.reset_size()
			_dots.position = Vector2((w - _dots.size.x) * 0.5, size.y - 26)
			for side in [-1, 1]:
				var ab := get_node_or_null("Arrow%d" % side) as Control
				if ab:
					ab.position = Vector2(14 if side < 0 else w - ab.size.x - 14, (size.y - ab.size.y) * 0.5)
		_paint()

	func _paint() -> void:
		if _dots:
			for i in _dots.get_child_count():
				var d := _dots.get_child(i) as Panel
				var on := i == index
				d.custom_minimum_size = Vector2(22 if on else 8, 8)
				d.add_theme_stylebox_override("panel", Glass.box(Color(1, 1, 1, 0.95 if on else 0.45), 4, 0))
			for side in [-1, 1]:
				var ab := get_node_or_null("Arrow%d" % side) as Control
				if ab:
					ab.visible = (index > 0) if side < 0 else (index < _pages.size() - 1)
		if _cap and index < captions.size():
			_cap.text = String(captions[index]).to_upper()
			var cp := _cap.get_parent() as Control
			cp.offset_left = cp.offset_right - cp.get_combined_minimum_size().x

	func go(i: int) -> void:
		index = clampi(i, 0, maxi(0, _pages.size() - 1))
		_slide()

	func _slide() -> void:
		if _tw and _tw.is_valid():
			_tw.kill()
		_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw.tween_property(_strip, "position:x", -size.x * index, 0.32)
		_offset = -size.x * index
		_paint()

	# Horizontal swipes (touch or mouse); a mostly vertical drag is left to
	# the page's scroller.
	func _input(e: InputEvent) -> void:
		if not is_visible_in_tree() or _pages.size() < 2:
			return
		var pos := Vector2.INF
		var pressed := false
		var released := false
		var moved := Vector2.ZERO
		if e is InputEventScreenTouch:
			var t := e as InputEventScreenTouch
			if t.pressed and _finger < 0:
				pos = t.position
				pressed = true
				_finger = t.index
			elif not t.pressed and t.index == _finger:
				released = true
				_finger = -1
		elif e is InputEventScreenDrag and (e as InputEventScreenDrag).index == _finger:
			moved = (e as InputEventScreenDrag).relative
		elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := e as InputEventMouseButton
			pressed = mb.pressed
			released = not mb.pressed
			pos = mb.position
		elif e is InputEventMouseMotion and (e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			moved = (e as InputEventMouseMotion).relative
		if pressed:
			if get_global_rect().has_point(pos):
				_press = Vector2.ZERO
				_drag = false
			else:
				_press = Vector2.INF
				_finger = -1
		elif moved != Vector2.ZERO and _press != Vector2.INF:
			_press += moved
			if not _drag and absf(_press.x) > 14.0 and absf(_press.x) > absf(_press.y) * 1.4:
				_drag = true
				if _tw and _tw.is_valid():
					_tw.kill()
			if _drag:
				var lo := -size.x * (_pages.size() - 1)
				var x := _offset + _press.x
				if x > 0.0 or x < lo:   # rubber band past the ends
					x = clampf(x, lo, 0.0) + (x - clampf(x, lo, 0.0)) * 0.3
				_strip.position.x = x
				get_viewport().set_input_as_handled()
		elif released and _press != Vector2.INF:
			if _drag:
				var step := 0
				if _press.x < -size.x * 0.18:
					step = 1
				elif _press.x > size.x * 0.18:
					step = -1
				EmpireStyle.tap_block_until = Time.get_ticks_msec() + 180
				go(index + step)
				get_viewport().set_input_as_handled()
			_press = Vector2.INF
			_drag = false


## A Gallery of a model's studio photography (one page if it has none).
static func model_gallery(ui: EmpireUI, model: String, sz: Vector2, radius := 28) -> Control:
	var vs := views(model)
	var makers: Array = []
	var caps: Array = []
	if vs.is_empty():
		makers.append(func(): return picture(ui, model, "hero", sz))
	for v in vs:
		var vv := String(v)
		makers.append(func(): return picture(ui, model, vv, sz))
		caps.append(VIEW_NAMES.get(vv, vv))
	var g := Gallery.new(makers, caps, 0, radius)
	g.custom_minimum_size = sz
	return g
