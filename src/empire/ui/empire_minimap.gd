class_name EmpireMinimap
extends Control
## The HUD minimap: a disc of the real city (City Swing's baked map, see
## Minimap.MapPainter) round you, turning with your heading, zooming out
## with speed when you drive. It is the full map (EmpireMap) seen closer:
## the same image, markers, colours and purple GPS route (MapKit, Gps),
## with only the more important markers shown. The destination is pinned
## to the rim when it's off the disc. Tap it to open the full map.

const SHADER := preload("res://src/ui/shaders/minimap.gdshader")
const R_WALK := 125.0
const R_DRIVE := 190.0      # at a crawl; out to R_DRIVE_FAST at speed
const R_DRIVE_FAST := 330.0

static var map_tex: Texture2D
static var _baking := false

var game: EmpireGame
var _mat: ShaderMaterial
var _overlay: Control
var _radius := R_WALK
var _yaw := 0.0
## The route this view last drew (world points; scenario checks compare views).
var drawn_route := PackedVector3Array()
var _last_pos := Vector2(INF, INF)
var _last_yaw := INF
var _last_radius := -1.0
var _last_route_sig := ""
var _last_redraw_ms := -1000000
var _last_tex: Texture2D = null


## Bakes the city map once (both islands); awaitable, no-op headless.
static func bake(host: Node, layout: CityLayout) -> void:
	if map_tex != null or _baking or DisplayServer.get_name() == "headless":
		return
	_baking = true
	var size_px := Vector2i(int(Minimap.BOUNDS.size.x / Minimap.M_PER_PX), int(Minimap.BOUNDS.size.y / Minimap.M_PER_PX))
	var vp := SubViewport.new()
	vp.size = size_px
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Minimap.MapPainter.new()
	painter.layouts = [layout] if layout.mainland == null else [layout.mainland, layout]
	painter.layout = layout
	vp.add_child(painter)
	host.add_child(vp)
	# Keep the one-shot texture on the GPU. Reading it back to generate
	# mipmaps synchronizes rendering and briefly duplicates its storage.
	vp.tree_exiting.connect(func():
		map_tex = null
		_baking = false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	map_tex = vp.get_texture()
	_baking = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("opacity", 0.9)
	# Roads read clearly against blocks at a glance (the baked map is soft).
	_mat.set_shader_parameter("contrast", 1.35)
	material = _mat
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _gui_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if tap and game and game.state == "play":
		accept_event()
		game.ui.open_phone("map")


func _focus() -> Vector3:
	var vn := game.vehicle_node()
	if vn != null and is_instance_valid(vn):
		return vn.global_position
	return game.player.global_position


func _process(dt: float) -> void:
	if game == null or not is_visible_in_tree():
		return
	var tex_changed := map_tex != _last_tex
	if map_tex and _mat.get_shader_parameter("map") != map_tex:
		_mat.set_shader_parameter("map", map_tex)
		_mat.set_shader_parameter("origin", Minimap.BOUNDS.position)
		_mat.set_shader_parameter("extent", Minimap.BOUNDS.size)
		tex_changed = true
	var view := game.view_yaw()
	_yaw = lerp_angle(_yaw, view, 1.0 - exp(-10.0 * dt))
	var want := R_WALK
	var vn2 := game.vehicle_node()
	if vn2 != null and is_instance_valid(vn2):
		var spd := absf(float(vn2.get("speed")))
		want = lerpf(R_DRIVE, R_DRIVE_FAST, clampf(spd / 30.0, 0.0, 1.0))
		if vn2 is Craft and (vn2 as Craft).kind != "boat":
			want = lerpf(R_DRIVE_FAST, 900.0, clampf((vn2 as Craft).altitude / 150.0, 0.0, 1.0))  # (flying: see further)
	_radius = lerpf(_radius, want, 1.0 - exp(-1.5 * dt))
	var c := _focus()
	var c2 := Vector2(c.x, c.z)
	var gps: Gps = game.gps
	var route_sig := ""
	if gps and gps.active():
		route_sig = "%d|%.1f,%.1f|%s" % [gps.points.size(), gps.dest.x, gps.dest.z, gps.message]
	var now_ms := Time.get_ticks_msec()
	var moved := c2.distance_to(_last_pos) > 0.5
	var turned := absf(angle_difference(_yaw, _last_yaw)) > 0.02
	var zoomed := absf(_radius - _last_radius) > 0.5
	var routed := route_sig != _last_route_sig
	var stale := (now_ms - _last_redraw_ms) >= 500
	if not (tex_changed or moved or turned or zoomed or routed or stale):
		return
	_last_tex = map_tex
	_last_pos = c2
	_last_yaw = _yaw
	_last_radius = _radius
	_last_route_sig = route_sig
	_last_redraw_ms = now_ms
	_mat.set_shader_parameter("center", c2)
	_mat.set_shader_parameter("forward", Vector2(-sin(_yaw), -cos(_yaw)))
	_mat.set_shader_parameter("radius_m", _radius)
	queue_redraw()
	_overlay.queue_redraw()


func _draw() -> void:
	if map_tex:
		draw_texture_rect(map_tex, Rect2(Vector2.ZERO, size), false)
	else:
		draw_circle(size * 0.5, size.x * 0.5, Color(0.08, 0.1, 0.13, 0.7))


func _to_map(p: Vector3) -> Vector2:
	var c := _focus()
	var f := Vector2(-sin(_yaw), -cos(_yaw))
	var r := Vector2(-f.y, f.x)
	var d := Vector2(p.x - c.x, p.z - c.z)
	return size * 0.5 + Vector2(d.dot(r), -d.dot(f)) / _radius * size.x * 0.5


func _draw_overlay() -> void:
	if game == null:
		return
	var ov := _overlay
	var ctr := size * 0.5
	var rad := size.x * 0.5 - 4.0
	var k := 0.8
	# The GPS route first (markers sit on top of it).
	var gps: Gps = game.gps
	if gps and gps.active():
		var pts := gps.ahead()
		drawn_route = pts
		if pts.size() >= 2:
			var sp := PackedVector2Array()
			for p in pts:
				sp.append(_to_map(p))
			for run in MapKit.clip_to_circle(sp, ctr, rad):
				MapKit.draw_route(ov, run, 5.0)
	var near_r := rad - 4.0
	for m in MapKit.markers(game):
		var kind: String = m["kind"]
		var pri := MapKit.priority(kind)
		if pri > 1 or m["world"] == Vector3.ZERO:
			continue
		if kind == "car" and (String(m["id"]) == game.driving or (game.skyport_play and String(m["id"]) == game.skyport_play.piloting)):
			continue
		var sp2 := _to_map(m["world"])
		var dc := sp2.distance_to(ctr)
		if dc > near_r:
			continue
		# Lower-priority markers only near the middle (less clutter at the rim).
		if pri == 1 and dc > near_r * 0.8:
			continue
		MapKit.draw_marker(ov, sp2, kind, k)
	# Destination: on the disc, or pinned to the rim pointing at it.
	if gps and gps.active():
		var gp := _to_map(gps.dest)
		var off := gp - ctr
		if off.length() > rad - 10.0:
			gp = ctr + off.normalized() * (rad - 10.0)
			ov.draw_circle(gp, 8.0, Color(0, 0, 0, 0.55))
			ov.draw_circle(gp, 6.5, Gps.COLOUR)
		else:
			MapKit.draw_destination(ov, gp, 0.85)
	# You: always in the middle, pointing up (the map turns under you).
	MapKit.draw_player(ov, ctr, Vector2.UP, 0.9)
	# North tick on the rim.
	var north := (_to_map(_focus() + Vector3(0, 0, -50)) - ctr).normalized()
	var n := ctr + north * (size.x * 0.5 - 10.0)
	ov.draw_circle(n, 8.0, Color(EmpireStyle.INK, 0.9))
	ov.draw_string(EmpireStyle.font("black"), n + Vector2(-4.5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	# (The next turn is the HUD's turn panel under the disc.)
