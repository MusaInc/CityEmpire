class_name TitleMenu
extends Control
## The title menu (2026-11-27): the city is the picture. A small wordmark top
## left, a quiet column of text actions bottom left, the view's name bottom
## right – and only soft corner shading so the backdrop stays the star.
##
## On launch the boot screen's gold W flies into this wordmark's mark
## (logo_rect / reveal / handoff), so splash → menu is one movement.

var ui: EmpireUI
var game: EmpireGame
var has_save := false
var view := {}

var wordmark: Brand.Wordmark
var _actions: VBoxContainer
var _caption: VBoxContainer
var _shades: Array[Control] = []
var _items: Array[Control] = []
var _veil: ColorRect
var _inset := [0.0, 0.0, 0.0, 0.0]
var _busy := false

const PAD := 56.0


func _init(p_ui: EmpireUI, p_game: EmpireGame, p_has_save: bool, p_view: Dictionary) -> void:
	ui = p_ui
	game = p_game
	has_save = p_has_save
	view = p_view
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build()


func _shade(from: Vector2, to: Vector2, alpha: float, radial := false) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(Brand.NAVY_DEEP, alpha))
	g.set_color(1, Color(Brand.NAVY_DEEP, 0.0))
	g.add_point(0.45, Color(Brand.NAVY_DEEP, alpha * 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 256
	gt.fill = GradientTexture2D.FILL_RADIAL if radial else GradientTexture2D.FILL_LINEAR
	gt.fill_from = from
	gt.fill_to = to
	var r := TextureRect.new()
	r.texture = gt
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _build() -> void:
	# Only the corners the text sits in are shaded: top (wordmark) and a soft
	# pool bottom left (actions). The rest of the frame is the city.
	var top := _shade(Vector2(0.5, 0.0), Vector2(0.5, 0.34), 0.50)
	add_child(top)
	var pool := _shade(Vector2(0.0, 1.0), Vector2(0.62, 0.18), 0.74, true)
	add_child(pool)
	var foot := _shade(Vector2(0.5, 1.0), Vector2(0.5, 0.72), 0.32)
	add_child(foot)
	_shades = [top, pool, foot]

	wordmark = Brand.Wordmark.new(30.0)
	add_child(wordmark)

	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 2)
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_actions)
	if has_save:
		_actions.add_child(_item("Continue", _continue_sub(), true, func(): _enter(game.continue_game)))
		_actions.add_child(_item("New game", "", false, _confirm_new))
		_actions.add_child(_item("Character", "", false, func(): _enter(func():
			game.continue_game()
			ui.open_style())))
	else:
		_actions.add_child(_item("Begin", "Your empire starts with one shop", true, func(): _enter(game.start_new)))
	_actions.add_child(_item("Settings", "", false, ui._settings_panel))

	_caption = VBoxContainer.new()
	_caption.add_theme_constant_override("separation", 2)
	_caption.alignment = BoxContainer.ALIGNMENT_END
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var place := _tracked(String(view.get("name", "")).to_upper(), 13, Color(Brand.IVORY, 0.86), 3)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_caption.add_child(place)
	var mood := Glass.text(String(view.get("mood", "")), "caption", Color(Brand.IVORY, 0.52), "regular")
	mood.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_caption.add_child(mood)
	add_child(_caption)

	_veil = ColorRect.new()
	_veil.color = Brand.NAVY_DEEP
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.modulate.a = 0.0
	add_child(_veil)
	resized.connect(_layout)
	_layout()
	# Hidden until revealed (the boot screen calls reveal; otherwise at once).
	for c: Control in [wordmark.word, _caption] + _items + _shades:
		c.modulate.a = 0.0
	wordmark.mark.modulate.a = 0.0
	if get_tree().root.get_node_or_null("Boot") == null:
		wordmark.mark.modulate.a = 1.0
		reveal(0.1)


func _tracked(s: String, px: int, col: Color, track: int) -> Label:
	var l := Label.new()
	l.text = s
	var fv := FontVariation.new()
	fv.base_font = Glass.font("semibold")
	fv.spacing_glyph = track
	l.add_theme_font_override("font", fv)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _continue_sub() -> String:
	var e := game.empire
	if e == null:
		return ""
	return "Day %d  ·  %s" % [e.day, EmpireData.money(e.net_worth())]


## One action: text only, a gold rule beside the primary one.
func _item(label: String, sub: String, primary: bool, cb: Callable) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.custom_minimum_size = Vector2(320, 62 if sub != "" else 50)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := ColorRect.new()
	rule.color = Brand.GOLD if primary else Color(0, 0, 0, 0)
	rule.custom_minimum_size = Vector2(2, 30 if sub != "" else 22)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Label.new()
	t.text = label
	t.add_theme_font_override("font", Glass.font("semibold", true))
	t.add_theme_font_size_override("font_size", 30 if primary else 23)
	t.add_theme_color_override("font_color", Brand.GOLD_TEXT if primary else Color(Brand.IVORY, 0.9))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(t)
	if sub != "":
		col.add_child(Glass.text(sub, "footnote", Color(Brand.IVORY, 0.58), "regular"))
	row.add_child(col)
	b.add_child(row)
	b.button_down.connect(func(): row.modulate = Color(1, 1, 1, 0.6))
	b.button_up.connect(func(): row.modulate = Color.WHITE)
	b.mouse_entered.connect(func(): create_tween().tween_property(row, "position:x", 6.0, 0.14))
	b.mouse_exited.connect(func(): create_tween().tween_property(row, "position:x", 0.0, 0.18))
	Glass.feedback(b, func():
		if not _busy:
			cb.call())
	_items.append(b)
	return b


func set_insets(inset: Array) -> void:
	_inset = inset
	_layout()


func _layout() -> void:
	var vs := size if size.x > 0.0 else get_viewport_rect().size
	var l := PAD + float(_inset[0])
	var t := PAD * 0.72 + float(_inset[1])
	var r := PAD + float(_inset[2])
	var b := PAD * 0.8 + minf(float(_inset[3]), 20.0)
	wordmark.position = Vector2(l, t)
	wordmark.size = wordmark.get_combined_minimum_size()
	_actions.size = _actions.get_combined_minimum_size()
	_actions.position = Vector2(l - 18.0, vs.y - b - _actions.size.y)
	_caption.size = Vector2(420, _caption.get_combined_minimum_size().y)
	_caption.position = Vector2(vs.x - r - 420.0, vs.y - b - _caption.size.y)


## Where the wordmark's W sits on screen (the boot W lands here).
func logo_rect() -> Rect2:
	_layout()
	# Screen space (the boot layer has no transform): the menu sits inside
	# the safe-area root, so a local position landed a few px off.
	return wordmark.mark.get_global_rect()


## Fade everything but the W in, staggered (the W arrives with the boot).
func reveal(delay := 0.0) -> void:
	var tw := create_tween().set_parallel()
	for s in _shades:
		tw.tween_property(s, "modulate:a", 1.0, 0.9).set_delay(delay).set_trans(Tween.TRANS_SINE)
	# (the lettering waits for the boot W to land, or the W flew across it)
	tw.tween_property(wordmark.word, "modulate:a", 1.0, 0.7).set_delay(delay + 0.85).set_trans(Tween.TRANS_SINE)
	var i := 0
	for it in _items:
		tw.tween_property(it, "modulate:a", 1.0, 0.55).set_delay(delay + 0.55 + i * 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		i += 1
	tw.tween_property(_caption, "modulate:a", 1.0, 0.9).set_delay(delay + 0.9).set_trans(Tween.TRANS_SINE)
	# (not the W: it stays hidden until handoff(), or two Ws showed mid-glide)


## The boot W has landed on ours: show ours and let it shine once.
func handoff() -> void:
	wordmark.mark.modulate.a = 1.0
	wordmark.mark.shine(1.1, 0.4)


## Into the world: a short dip to navy hides the camera cut, then lifts.
func _enter(cb: Callable) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_veil, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_SINE)
	await tw.finished
	# (The veil outlives the menu: it lives on the UI root while the world
	# streams in under it, then fades.)
	var veil := _veil
	remove_child(veil)
	ui.add_overlay(veil)
	cb.call()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(veil):
		var t2 := veil.create_tween()
		t2.tween_property(veil, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
		t2.tween_callback(veil.queue_free)


func _confirm_new() -> void:
	var v := ui._open("Start again?", 560, 240)
	v.add_child(Glass.para("Your saved empire will be replaced.", "subhead"))
	var h := Glass.hbox(12)
	h.add_child(Glass.button("Cancel", func(): ui.close_panel(false), "gray", "large"))
	h.add_child(Glass.button("New game", func():
		ui.close_panel(true)
		_enter(game.start_new), "filled", "large"))
	v.add_child(h)
