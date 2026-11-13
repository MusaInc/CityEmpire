class_name EmpireMap
extends Control
## The phone map: both islands' coasts and roads, your businesses (green),
## shops to let (amber), wholesalers (blue), your vehicles and you. Tap a
## marker to set the GPS.

var game: EmpireGame
var _markers: Array = []   # [screen pos, world pos, label]
static var _cache := {}    # "coast"/"roads" -> Array of PackedVector2Array (world)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _cache.is_empty():
		var coasts: Array = []
		var roads: Array = []
		for L in [game.layout, game.layout.mainland]:
			if L == null:
				continue
			if L.roads and L.roads.coast.size() > 2:
				coasts.append(L.roads.coast)
			for r in L.roads.roads:
				roads.append([r["pts"], float(r.get("w", 10.0))])
		_cache["coast"] = coasts
		_cache["roads"] = roads


func _bounds() -> Rect2:
	return Rect2(-1350.0, -720.0, 2420.0, 1380.0)


func _to_screen(p: Vector2) -> Vector2:
	var b := _bounds()
	var k := minf(size.x / b.size.x, size.y / b.size.y)
	var off := (size - b.size * k) * 0.5
	return off + (p - b.position) * k


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#14324a"))
	for c: PackedVector2Array in _cache["coast"]:
		var pts := PackedVector2Array()
		for p in c:
			pts.append(_to_screen(p))
		if pts.size() > 2:
			draw_colored_polygon(pts, Color("#22303a"))
	for r in _cache["roads"]:
		var pts2 := PackedVector2Array()
		for p in r[0]:
			pts2.append(_to_screen(p))
		if pts2.size() > 1:
			draw_polyline(pts2, Color("#4a5e6c"), maxf(1.0, float(r[1]) * 0.12), true)
	# Bridge.
	draw_line(_to_screen(Vector2(CityLayout.APPROACH_END, CityLayout.BRIDGE_Z)), _to_screen(Vector2(70.0, CityLayout.BRIDGE_Z)),
		Color("#6d8496"), 3.0, true)
	_markers.clear()
	var f := EmpireStyle.font("bold")
	for u in game.units:
		var b := game.empire.business_at(u["id"])
		var col := EmpireStyle.AMBER
		var label := String(u.get("shop_name", u["name"])) + " · to let"
		if u["kind"] == "wholesale":
			col = EmpireStyle.BLUE
			label = String(u["name"])
		elif b:
			col = EmpireStyle.GREEN
			label = b.name
		var w := Vector2(float(u["pos"][0]), float(u["pos"][2]))
		var s := _to_screen(w)
		draw_circle(s, 7.0 if b or u["kind"] == "wholesale" else 4.5, col)
		if b or u["kind"] == "wholesale":
			draw_string(f, s + Vector2(10, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))
		_markers.append([s, Premises.door_point(u), label])
	for vid in game.cars:
		var c: Car = game.cars[vid]
		var s2 := _to_screen(Vector2(c.global_position.x, c.global_position.z))
		draw_rect(Rect2(s2 - Vector2(4, 4), Vector2(8, 8)), Color.WHITE)
	var me := game.player.global_position
	var sp := _to_screen(Vector2(me.x, me.z))
	var yaw := game.camera.view_yaw()
	var tri := PackedVector2Array([sp + Vector2(0, -11).rotated(-yaw), sp + Vector2(7, 7).rotated(-yaw), sp + Vector2(-7, 7).rotated(-yaw)])
	draw_colored_polygon(tri, EmpireStyle.RED)
	draw_string(f, Vector2(14, size.y - 14), "Westbank — industrial & residential", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, EmpireStyle.MUTED)
	draw_string(f, Vector2(size.x - 300, size.y - 14), "Commercial Island", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, EmpireStyle.MUTED)
	var t := game.gps_target()
	if t != Vector3.INF:
		var g := _to_screen(Vector2(t.x, t.z))
		draw_arc(g, 12.0, 0, TAU, 24, Color.WHITE, 2.5, true)


func _gui_input(e: InputEvent) -> void:
	var pos := Vector2.INF
	if e is InputEventMouseButton and e.pressed:
		pos = e.position
	elif e is InputEventScreenTouch and e.pressed:
		pos = e.position
	if pos == Vector2.INF:
		return
	var best: Array = []
	var bd := 26.0
	for m in _markers:
		var d := (m[0] as Vector2).distance_to(pos)
		if d < bd:
			bd = d
			best = m
	if not best.is_empty():
		game.set_gps(best[1], best[2])
		game.ui.toast("GPS set: %s" % best[2], "info")
		queue_redraw()
