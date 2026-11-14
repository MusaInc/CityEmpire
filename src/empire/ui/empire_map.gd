class_name EmpireMap
extends Control
## The phone map: the real city (the same baked map as the HUD minimap),
## north up, that you drag to pan and pinch / scroll / +− to zoom. Markers:
## your shops, wholesalers, QuikSave, businesses for sale, shops to let,
## independents, your vehicles and you; names appear as you zoom in. Tap a
## marker to set the GPS (and see what it is).

const MIN_ZOOM := 0.35   # px per metre
const MAX_ZOOM := 3.2

var game: EmpireGame
var _center := Vector2.ZERO   # world x/z at the middle of the view
var _zoom := 0.8
var _markers: Array = []      # [screen pos, world pos, label]
var _selected := ""
var _touches := {}            # index -> position (pinch)
var _pinch0 := 0.0
var _zoom0 := 0.0
var _dragged := 0.0


## What occupies a unit, for colours and labels.
static func unit_kind(g: EmpireGame, u: Dictionary) -> String:
	if u["kind"] == "wholesale":
		return "wholesale"
	if g.empire.business_at(u["id"]) != null:
		return "yours"
	if CityLife.is_rival(g.empire, u["id"]):
		return "rival"
	var f := CityLife.firm_at(g.empire, u["id"])
	if not f.is_empty():
		return "sale" if f.get("for_sale", false) else "firm"
	return "to_let"


static func kind_colour(kind: String) -> Color:
	match kind:
		"yours":
			return EmpireStyle.GREEN
		"wholesale":
			return EmpireStyle.BLUE
		"rival":
			return Color(CityLife.rival_cfg().get("colour", "#d8262f"))
		"sale":
			return Color(0.3, 0.92, 0.78)
		"to_let":
			return EmpireStyle.AMBER
	return Color(0.78, 0.8, 0.84)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	clip_contents = true
	var me := game.player.global_position
	_center = Vector2(me.x, me.z)
	if game.gps_target() != Vector3.INF:
		var t: Vector3 = game.gps_target()
		_center = (_center + Vector2(t.x, t.z)) * 0.5
	# Buttons: zoom and re-centre.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.anchor_left = 1.0
	col.anchor_right = 1.0
	col.offset_left = -64
	col.offset_top = 12
	add_child(col)
	for b in [["+", func(): _zoom_by(1.4, size * 0.5)], ["−", func(): _zoom_by(1.0 / 1.4, size * 0.5)], ["◎", func():
			var p := game.player.global_position
			_center = Vector2(p.x, p.z)
			queue_redraw()]]:
		var btn := EmpireStyle.button(b[0], b[1], false, 52)
		btn.add_theme_font_size_override("font_size", 24)
		col.add_child(btn)


var _had_tex := false


func _process(_dt: float) -> void:
	# (Opened before the city image finished baking: draw it when it lands.)
	if not _had_tex and EmpireMinimap.map_tex != null:
		_had_tex = true
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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.22, 0.3))
	var b := Minimap.BOUNDS
	if EmpireMinimap.map_tex:
		draw_texture_rect(EmpireMinimap.map_tex, Rect2(_to_screen(b.position), b.size * _zoom), false)
	_markers.clear()
	var f := EmpireStyle.font("bold")
	var labels: Array = []
	for u in game.units:
		var kind := unit_kind(game, u)
		var dp := Premises.door_point(u)
		var s := _to_screen(Vector2(dp.x, dp.z))
		if s.x < -20 or s.y < -20 or s.x > size.x + 20 or s.y > size.y + 20:
			continue
		var col := kind_colour(kind)
		var label := ""
		match kind:
			"yours":
				label = game.empire.business_at(u["id"]).name
			"wholesale":
				label = String(u["name"])
			"rival":
				label = String(CityLife.rival_at(game.empire, u["id"])["name"])
			"sale", "firm":
				var fm := CityLife.firm_at(game.empire, u["id"])
				label = String(fm["name"]) + (" · for sale %s" % EmpireData.money(CityLife.firm_price(fm)) if kind == "sale" else "")
			_:
				label = "To let · %s/day" % EmpireData.money(float(u["rent"]))
		var big := kind in ["yours", "wholesale", "rival", "sale"]
		var r := (7.0 if big else (4.5 if kind == "to_let" else 3.2)) * clampf(_zoom / 0.8, 0.8, 1.4)
		draw_circle(s, r + 1.5, Color(0, 0, 0, 0.55))
		if kind in ["rival", "sale"]:
			draw_rect(Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0), col)
		else:
			draw_circle(s, r, col)
		if big or _zoom > 1.6 or u["id"] == _selected:
			labels.append([s, label, big or u["id"] == _selected])
		_markers.append([s, dp, label, u["id"]])
	for l in labels:
		var fs := 15 if l[2] else 13
		var w := f.get_string_size(l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos: Vector2 = l[0] + Vector2(10, 5)
		draw_rect(Rect2(pos + Vector2(-4, -fs), Vector2(w + 8, fs + 6)), Color(EmpireStyle.INK, 0.72))
		draw_string(f, pos, l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
	for vid in game.cars:
		var c: Node3D = game.cars[vid]
		var s2 := _to_screen(Vector2(c.global_position.x, c.global_position.z))
		draw_rect(Rect2(s2 - Vector2(5, 5), Vector2(10, 10)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(s2 - Vector2(4, 4), Vector2(8, 8)), Color.WHITE)
	var t: Vector3 = game.gps_target()
	if t != Vector3.INF:
		var g := _to_screen(Vector2(t.x, t.z))
		draw_arc(g, 13.0, 0, TAU, 28, EmpireStyle.AMBER, 3.0, true)
		draw_line(_to_screen(Vector2(game.player.global_position.x, game.player.global_position.z)), g, Color(EmpireStyle.AMBER, 0.5), 2.0, true)
	var me := game.player.global_position
	var sp := _to_screen(Vector2(me.x, me.z))
	var yaw := game.camera.view_yaw()
	var tri := PackedVector2Array([sp + Vector2(0, -12).rotated(-yaw), sp + Vector2(8, 8).rotated(-yaw), sp + Vector2(0, 4).rotated(-yaw), sp + Vector2(-8, 8).rotated(-yaw)])
	draw_circle(sp, 15.0, Color(1, 1, 1, 0.18))
	draw_colored_polygon(tri, Color.WHITE)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.7), 1.5, true)
	# Legend.
	var lx := 14.0
	var ly := size.y - 16.0
	draw_rect(Rect2(Vector2(6, size.y - 36), Vector2(size.x - 12, 30)), Color(EmpireStyle.INK, 0.8))
	for it in [["yours", "Yours"], ["wholesale", "Wholesale"], ["rival", "QuikSave"], ["sale", "For sale"], ["to_let", "To let"], ["firm", "Independent"]]:
		draw_circle(Vector2(lx + 5, ly - 5), 5.0, kind_colour(it[0]))
		draw_string(f, Vector2(lx + 14, ly), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, EmpireStyle.PAPER)
		lx += 22.0 + f.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14.0
	draw_string(f, Vector2(size.x - 250, ly), "drag to move · pinch to zoom · tap to GPS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, EmpireStyle.MUTED)


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
				_tap(t.position)
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
				_tap(m.position)
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


func _tap(pos: Vector2) -> void:
	var best: Array = []
	var bd := 28.0
	for m in _markers:
		var d := (m[0] as Vector2).distance_to(pos)
		if d < bd:
			bd = d
			best = m
	if best.is_empty():
		return
	_selected = best[3]
	game.set_gps(best[1], best[2])
	game.ui.toast("GPS set: %s" % best[2], "info")
	queue_redraw()
