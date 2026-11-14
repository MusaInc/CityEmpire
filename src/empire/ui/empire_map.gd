class_name EmpireMap
extends Control
## The phone's full map: the real city, north up, that you drag to pan and
## pinch / scroll / +− to zoom. It is the HUD minimap seen from further out:
## the same baked image, markers and purple GPS route (MapKit, Gps).
##
## Tap a marker to select it: a card says what it is, how far, and offers
## Set GPS / Cancel route and the place's own action (manage, inspect, buy
## a vehicle…). Tap an empty street for a waypoint. Filter chips hide the
## kinds of place you don't care about. No typing anywhere.

const MIN_ZOOM := 0.35   # px per metre
const MAX_ZOOM := 3.2
const S = preload("res://src/empire/ui/empire_style.gd")
const FILTERS := [["all", "All"], ["yours", "Mine"], ["to_let", "To let"], ["sale", "For sale"],
	["wholesale", "Suppliers"], ["car", "Vehicles"]]

static var filter := "all"     # (kept while the phone is closed)
static var _view := {}         # last centre/zoom (kept between openings)

var game: EmpireGame
var _center := Vector2.ZERO   # world x/z at the middle of the view
var _zoom := 0.8
var _drawn: Array = []        # [screen pos, marker]
var _selected := {}           # marker dict, or {"kind": "point", "world": …}
var _touches := {}            # index -> position (pinch)
var _pinch0 := 0.0
var _zoom0 := 0.0
var _dragged := 0.0
var _card: PanelContainer
var _chips: HBoxContainer
## The route this view last drew (world points; scenario checks compare views).
var drawn_route := PackedVector3Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	clip_contents = true
	var me := game.player.global_position
	_center = Vector2(me.x, me.z)
	if not _view.is_empty():
		_center = _view["c"]
		_zoom = _view["z"]
	elif game.gps and game.gps.active():
		var t: Vector3 = game.gps.dest
		_center = (_center + Vector2(t.x, t.z)) * 0.5
	# Zoom, centre on you, whole route.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.anchor_left = 1.0
	col.anchor_right = 1.0
	col.offset_left = -66
	col.offset_top = 12
	add_child(col)
	for b in [["+", func(): _zoom_by(1.4, size * 0.5)], ["−", func(): _zoom_by(1.0 / 1.4, size * 0.5)],
			["◎", center_on_player], ["⤢", _fit_route]]:
		var btn := S.button(b[0], b[1], false, 54)
		btn.custom_minimum_size = Vector2(54, 54)
		btn.add_theme_font_size_override("font_size", 24)
		col.add_child(btn)
	# Filter chips (top left).
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	_chips.position = Vector2(10, 10)
	add_child(_chips)
	_build_chips()
	_card = PanelContainer.new()
	_card.visible = false
	add_child(_card)
	# Re-select the destination so its card shows Cancel route.
	if game.gps and game.gps.active():
		for m in MapKit.markers(game):
			if m["ref"] == game.gps.ref:
				_selected = m
		_show_card()


func _exit_tree() -> void:
	_view = {"c": _center, "z": _zoom}


func _build_chips() -> void:
	for c in _chips.get_children():
		c.queue_free()
	for f in FILTERS:
		var on: bool = filter == f[0]
		var b := S.chip_button(f[1], on, func():
			filter = f[0]
			_build_chips()
			queue_redraw())
		_chips.add_child(b)


var _had_tex := false


func _process(_dt: float) -> void:
	# (Opened before the city image finished baking: draw it when it lands.)
	if not _had_tex and EmpireMinimap.map_tex != null:
		_had_tex = true
		queue_redraw()
	# Live: you, your car and the route move.
	if is_visible_in_tree() and Engine.get_process_frames() % 6 == 0:
		queue_redraw()


func _to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + (p - _center) * _zoom


func _to_world(s: Vector2) -> Vector2:
	return _center + (s - size * 0.5) / _zoom


func _zoom_by(k: float, at: Vector2) -> void:
	var w := _to_world(at)
	_zoom = clampf(_zoom * k, MIN_ZOOM, MAX_ZOOM)
	_center = w - (at - size * 0.5) / _zoom
	_clamp()
	queue_redraw()


func _clamp() -> void:
	var b := Minimap.BOUNDS
	_center = _center.clamp(b.position, b.end)


func center_on_player() -> void:
	var p := game.gps._here() if game.gps else game.player.global_position
	_center = Vector2(p.x, p.z)
	queue_redraw()


## Zooms to show the whole route (or you and the destination).
func _fit_route() -> void:
	if game.gps == null or not game.gps.active():
		center_on_player()
		return
	var pts: PackedVector3Array = game.gps.points
	var r := Rect2(Vector2(game.gps.dest.x, game.gps.dest.z), Vector2.ZERO)
	var here: Vector3 = game.gps._here()
	r = r.expand(Vector2(here.x, here.z))
	for p in pts:
		r = r.expand(Vector2(p.x, p.z))
	_center = r.get_center()
	var sz := r.size + Vector2(80, 80)
	_zoom = clampf(minf((size.x - 140.0) / sz.x, (size.y - 160.0) / sz.y), MIN_ZOOM, MAX_ZOOM)
	queue_redraw()


func _shown(kind: String) -> bool:
	if filter == "all":
		return true
	if filter == "sale":
		return kind in ["sale", "rival"]
	return kind == filter


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.22, 0.3))
	var b := Minimap.BOUNDS
	if EmpireMinimap.map_tex:
		draw_texture_rect(EmpireMinimap.map_tex, Rect2(_to_screen(b.position), b.size * _zoom), false)
	var k := clampf(_zoom / 0.8, 0.85, 1.35)
	# Route (the same points the minimap draws).
	var gps: Gps = game.gps
	if gps and gps.active():
		var sp := PackedVector2Array()
		drawn_route = gps.ahead()
		for p in drawn_route:
			sp.append(_to_screen(Vector2(p.x, p.z)))
		MapKit.draw_route(self, sp, clampf(3.0 * _zoom + 2.0, 4.0, 9.0))
	_drawn.clear()
	var f := S.font("bold")
	var labels: Array = []
	var sel_id := String(_selected.get("id", ""))
	for m in MapKit.markers(game):
		var kind: String = m["kind"]
		if m["world"] == Vector3.ZERO or not _shown(kind):
			continue
		var w: Vector3 = m["world"]
		var s := _to_screen(Vector2(w.x, w.z))
		if s.x < -20 or s.y < -20 or s.x > size.x + 20 or s.y > size.y + 20:
			continue
		var pri := MapKit.priority(kind)
		# Independents only when zoomed in or filtered for.
		if pri == 2 and _zoom < 1.1 and filter == "all" and m["id"] != sel_id:
			continue
		MapKit.draw_marker(self, s, kind, k, m["id"] == sel_id)
		_drawn.append([s, m])
		if pri == 0 or _zoom > 1.6 or m["id"] == sel_id:
			labels.append([s, String(m["label"]), pri == 0 or m["id"] == sel_id])
	for l in labels:
		var fs := 15 if l[2] else 13
		var tw := f.get_string_size(l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos: Vector2 = l[0] + Vector2(11, 5)
		draw_rect(Rect2(pos + Vector2(-4, -fs), Vector2(tw + 8, fs + 6)), Color(S.INK, 0.75))
		draw_string(f, pos, l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
	if gps and gps.active():
		MapKit.draw_destination(self, _to_screen(Vector2(gps.dest.x, gps.dest.z)), k)
	if String(_selected.get("kind", "")) == "point":
		var wp: Vector3 = _selected["world"]
		draw_arc(_to_screen(Vector2(wp.x, wp.z)), 10.0, 0, TAU, 24, Color.WHITE, 2.5, true)
	# You (on foot: where you face; driving: the car's heading).
	var me: Vector3 = gps._here() if gps else game.player.global_position
	var yaw := game.chase.view_yaw() if game.driving != "" else game.camera.view_yaw()
	MapKit.draw_player(self, _to_screen(Vector2(me.x, me.z)), Vector2(-sin(yaw), -cos(yaw)), 1.1)
	# Route status (no route / planning) along the bottom.
	if gps and gps.active() and gps.message != "":
		var msg := gps.message
		var mw := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_rect(Rect2(Vector2(size.x * 0.5 - mw * 0.5 - 12, 60), Vector2(mw + 24, 30)), Color(S.INK, 0.88))
		draw_string(f, Vector2(size.x * 0.5 - mw * 0.5, 81), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, S.AMBER)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
			if _touches.size() == 2:
				var ps: Array = _touches.values()
				_pinch0 = (ps[0] as Vector2).distance_to(ps[1])
				_zoom0 = _zoom
			if _touches.size() == 1:
				_dragged = 0.0
		else:
			_touches.erase(t.index)
			if _touches.is_empty() and _dragged < 12.0:
				tap(t.position)
		accept_event()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() >= 2:
			var ps: Array = _touches.values()
			var dist := (ps[0] as Vector2).distance_to(ps[1])
			if _pinch0 > 1.0:
				var mid: Vector2 = ((ps[0] as Vector2) + (ps[1] as Vector2)) * 0.5
				_zoom_by(clampf(_zoom0 * dist / _pinch0, MIN_ZOOM, MAX_ZOOM) / _zoom, mid)
			_dragged = 99.0
		else:
			_center -= d.relative / _zoom
			_dragged += d.relative.length()
			_clamp()
			queue_redraw()
		accept_event()
	elif e is InputEventMouseButton:
		var m := e as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_WHEEL_UP and m.pressed:
			_zoom_by(1.15, m.position)
		elif m.button_index == MOUSE_BUTTON_WHEEL_DOWN and m.pressed:
			_zoom_by(1.0 / 1.15, m.position)
		elif m.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
			if m.pressed:
				_dragged = 0.0
			elif _dragged < 6.0:
				tap(m.position)
		accept_event()
	elif e is InputEventMouseMotion and (e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT \
			and not DisplayServer.is_touchscreen_available():
		var mm := e as InputEventMouseMotion
		_center -= mm.relative / _zoom
		_dragged += mm.relative.length()
		_clamp()
		queue_redraw()
	elif e is InputEventMagnifyGesture:
		_zoom_by((e as InputEventMagnifyGesture).factor, (e as InputEventMagnifyGesture).position)


## A tap: the nearest marker within reach, else a waypoint on that street.
func tap(pos: Vector2) -> void:
	var best := {}
	var bd := 30.0
	for d in _drawn:
		var dd := (d[0] as Vector2).distance_to(pos)
		if dd < bd:
			bd = dd
			best = d[1]
	if best.is_empty():
		var w := _to_world(pos)
		var wy := game.layout.ground_y(w.x, w.y)
		_selected = {"id": "", "kind": "point", "world": Vector3(w.x, wy, w.y), "label": "Waypoint",
			"sub": String(EmpireData.district(("west:" if w.x < CityLayout.FAR_SHORE else "east:") + game.layout.district(w.x, w.y)).get("name", "")),
			"ref": {"kind": "point"}}
	else:
		_selected = best
	_show_card()
	queue_redraw()


## Selects a marker by its ref (another screen's "Show on map").
func select_ref(ref: Dictionary) -> void:
	for m in MapKit.markers(game):
		if m["ref"] == ref:
			_selected = m
			var w: Vector3 = m["world"]
			_center = Vector2(w.x, w.z)
			_zoom = maxf(_zoom, 1.2)
			_show_card()
			queue_redraw()
			return


func _show_card() -> void:
	for c in _card.get_children():
		c.queue_free()
	if _selected.is_empty():
		_card.visible = false
		return
	_card.visible = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(S.INK, 0.94)
	sb.set_corner_radius_all(18)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(1)
	sb.content_margin_left = 18
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_card.add_theme_stylebox_override("panel", sb)
	var h := S.hbox(14)
	_card.add_child(h)
	var v := S.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var kind := String(_selected.get("kind", "point"))
	var name_l := S.label(String(_selected.get("label", "")), 20, S.PAPER, "black")
	name_l.clip_text = true
	v.add_child(name_l)
	var w: Vector3 = _selected["world"]
	var here: Vector3 = game.gps._here() if game.gps else game.player.global_position
	var dist := Vector2(here.x - w.x, here.z - w.z).length()
	var dtxt := "%.1f km" % (dist / 1000.0) if dist >= 1000.0 else "%d m" % int(dist)
	v.add_child(S.label("%s · %s away" % [String(_selected.get("sub", "")), dtxt], 15, S.MUTED))
	var is_dest: bool = game.gps != null and game.gps.active() and (game.gps.ref == _selected.get("ref", {}) and kind != "point" \
		or (kind == "point" and game.gps.dest.distance_to(w) < 1.0))
	if is_dest:
		var st := game.gps.message if game.gps.message != "" else "Route: %s" % game.gps.distance_text()
		v.add_child(S.label(st, 15, Gps.COLOUR.lightened(0.3), "bold"))
		h.add_child(S.button("Cancel route", func():
			game.clear_gps()
			_show_card()
			queue_redraw(), false, 52))
	else:
		h.add_child(S.button("Set GPS", func():
			game.set_gps(w, String(_selected.get("label", "")), _selected.get("ref", {}))
			_show_card()
			queue_redraw(), true, 52))
	var act := _action()
	if not act.is_empty():
		h.add_child(S.button(act[0], act[1], false, 52))
	var x := S.button("✕", func():
		_selected = {}
		_show_card()
		queue_redraw(), false, 52)
	x.custom_minimum_size = Vector2(52, 52)
	h.add_child(x)
	_card.anchor_left = 0.0
	_card.anchor_right = 1.0
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.offset_left = 10
	_card.offset_right = -84
	_card.offset_top = -92
	_card.offset_bottom = -10


## The selected place's own action: [label, callable] or [].
func _action() -> Array:
	var ref: Dictionary = _selected.get("ref", {})
	var ui: EmpireUI = game.ui
	match String(ref.get("kind", "")):
		"unit":
			var u: Dictionary = game.unit_by_id.get(String(ref["id"]), {})
			match String(_selected["kind"]):
				"yours":
					var b: Business = game.empire.business_at(String(ref["id"]))
					return ["Manage", func(): ui.open_manage(b)]
				"to_let":
					return ["Inspect", func(): ui.open_property(u, true)]
				"sale":
					return ["Inspect", func(): ui.open_firm(u, true)]
				"rival":
					return ["Inspect", func(): ui.open_rival(u, true)]
				"hq":
					return ["Head office", func(): ui.open_hq()]
		"vehicle":
			return ["Vehicles", func(): ui.open_phone("vehicles")]
	return []
