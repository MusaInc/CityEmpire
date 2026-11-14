class_name EmpireMinimap
extends Control
## The HUD minimap: a disc of the real city (City Swing's baked map, see
## Minimap.MapPainter) round you, turning with the camera, zooming out when
## you drive. Markers: your shops (green), wholesalers (blue), QuikSave
## (red squares), businesses for sale (teal), shops to let (amber), your
## vehicles (white) and the GPS target (gold, pinned to the rim when it's
## off the map). Tap it to open the full map. EmpireMap shares the texture.

const SHADER := preload("res://src/ui/shaders/minimap.gdshader")
const R_WALK := 110.0
const R_DRIVE := 240.0

static var map_tex: Texture2D
static var _baking := false

var game: EmpireGame
var _mat: ShaderMaterial
var _overlay: Control
var _radius := R_WALK
var _yaw := 0.0


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
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image() if vp.get_texture() else null
	vp.queue_free()
	_baking = false
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	map_tex = ImageTexture.create_from_image(img)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("opacity", 0.92)
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
	if game.driving != "" and game.cars.has(game.driving):
		return (game.cars[game.driving] as Node3D).global_position
	return game.player.global_position


func _process(dt: float) -> void:
	if game == null or not is_visible_in_tree():
		return
	if map_tex and _mat.get_shader_parameter("map") != map_tex:
		_mat.set_shader_parameter("map", map_tex)
		_mat.set_shader_parameter("origin", Minimap.BOUNDS.position)
		_mat.set_shader_parameter("extent", Minimap.BOUNDS.size)
	_yaw = lerp_angle(_yaw, game.camera.view_yaw(), 1.0 - exp(-10.0 * dt))
	var want := R_DRIVE if game.driving != "" else R_WALK
	_radius = lerpf(_radius, want, 1.0 - exp(-1.5 * dt))
	var c := _focus()
	_mat.set_shader_parameter("center", Vector2(c.x, c.z))
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
	var rad := size.x * 0.5 - 6.0
	var e := game.empire
	for u in game.units:
		var dp := Premises.door_point(u)
		var sp := _to_map(dp)
		if sp.distance_to(ctr) > rad:
			continue
		var kind := EmpireMap.unit_kind(game, u)
		var col := EmpireMap.kind_colour(kind)
		match kind:
			"yours", "wholesale":
				ov.draw_circle(sp, 5.5, Color(0, 0, 0, 0.5))
				ov.draw_circle(sp, 4.5, col)
			"rival", "sale":
				ov.draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), col)
			"to_let":
				ov.draw_circle(sp, 3.0, col)
			_:
				ov.draw_circle(sp, 2.0, Color(col, 0.7))
	for vid in game.cars:
		if vid == game.driving:
			continue
		var cp := _to_map((game.cars[vid] as Node3D).global_position)
		if cp.distance_to(ctr) < rad:
			ov.draw_rect(Rect2(cp - Vector2(3, 3), Vector2(6, 6)), Color.WHITE)
	# GPS target: on the map, or pinned to the rim pointing at it.
	var t: Vector3 = game.gps_target()
	if t != Vector3.INF:
		var gp := _to_map(t)
		var off := gp - ctr
		if off.length() > rad - 6.0:
			gp = ctr + off.normalized() * (rad - 6.0)
		ov.draw_circle(gp, 7.0, Color(0, 0, 0, 0.5))
		ov.draw_circle(gp, 5.5, EmpireStyle.AMBER)
		ov.draw_arc(gp, 9.0, 0, TAU, 20, Color(EmpireStyle.AMBER, 0.6), 1.5, true)
	# You: an arrow pointing where the camera faces (always up).
	var tri := PackedVector2Array([ctr + Vector2(0, -9), ctr + Vector2(6.5, 7), ctr + Vector2(0, 3.5), ctr + Vector2(-6.5, 7)])
	ov.draw_colored_polygon(tri, Color.WHITE)
	ov.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.6), 1.2, true)
	# North tick on the rim.
	var north := (_to_map(_focus() + Vector3(0, 0, -50)) - ctr).normalized()
	var n := ctr + north * (size.x * 0.5 - 10.0)
	ov.draw_circle(n, 8.0, Color(EmpireStyle.INK, 0.9))
	ov.draw_string(EmpireStyle.font("black"), n + Vector2(-4.5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
