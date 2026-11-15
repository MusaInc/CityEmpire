class_name Thumbs
extends Node
## Cached preview images for the dashboard, from the game's own content:
##  * vehicles: the real car / aircraft / boat model rendered once in a
##    small offscreen viewport (3/4 view, studio light), cached per model
##    for the session (one ~260×150 image each; the viewport is freed);
##  * places: a crop of the baked city map (the same image as the minimap)
##    round a world point, with a pin – no extra rendering at all.
## No live 3D in the dashboard: images only, made on demand, one at a time.

const VW := Vector2i(260, 150)

static var _cache := {}       # model -> ImageTexture
var _queue: Array = []        # [model, TextureRect]
var _busy := false
var game: EmpireGame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # (the phone pauses the tree)


## A TextureRect that shows the model's picture (now if cached, else when
## it's rendered).
func vehicle(model: String, size := Vector2(260, 150)) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _cache.has(model):
		tr.texture = _cache[model]
	else:
		_queue.append([model, tr])
		if not _busy:
			_render_next.call_deferred()
	return tr


func _render_next() -> void:
	if _queue.is_empty() or DisplayServer.get_name() == "headless":
		_busy = false
		_queue.clear()
		return
	_busy = true
	var job: Array = _queue.pop_front()
	var model := String(job[0])
	if not _cache.has(model):
		_cache[model] = await _render(model)
	for j in [job] + _queue.filter(func(q): return q[0] == model):
		if is_instance_valid(j[1]):
			(j[1] as TextureRect).texture = _cache[model]
	_queue = _queue.filter(func(q): return q[0] != model)
	_render_next.call_deferred()


func _render(model: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = VW
	vp.own_world_3d = true
	vp.transparent_bg = false   # (the Mobile renderer writes no 3D alpha: use the card colour)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS   # (freed after three frames)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.17, 0.21)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0.0)
	sun.light_energy = 1.4
	vp.add_child(sun)
	var cls := SkyportPlay.vclass(model)
	var holder := Node3D.new()
	vp.add_child(holder)
	var length := 4.6
	if cls == "car":
		var c := Car.new()
		c.setup(game._car_spec(model), "display")
		c.freeze = true
		holder.add_child(c)
		var vis := CarVisual.new()
		c.add_child(vis)
		vis.setup(c)
		length = float((c.spec["size"] as Vector3).z)
	else:
		var spec := SkyportPlay.craft_spec(model)
		holder.add_child(CraftModels.build(cls, model, spec))
		length = maxf((spec["size"] as Vector3).z, (spec["size"] as Vector3).x)
	var cam := Camera3D.new()
	cam.fov = 32.0
	var d := length * 1.45 + 1.2
	var cp := Vector3(d * 0.75, d * 0.38, -d * 0.62)
	# (look_at needs the node in the tree: set the basis directly.)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, length * 0.08 + 0.6, 0) - cp, Vector3.UP), cp)
	vp.add_child(cam)
	add_child(vp)
	cam.make_current()
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return ImageTexture.create_from_image(img)


## A crop of the city map round `world` (radius r m) with a pin.
static func place(world: Vector3, r := 160.0, size := Vector2(260, 150)) -> Control:
	var c := _Place.new()
	c.world = world
	c.r = r
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


class _Place extends Control:
	var world := Vector3.ZERO
	var r := 160.0
	var _had := false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_dt: float) -> void:
		# (The map bakes a moment after the game starts: draw it when it lands.)
		if not _had and EmpireMinimap.map_tex != null:
			_had = true
			queue_redraw()

	func _draw() -> void:
		var tex := EmpireMinimap.map_tex
		var rect := Rect2(Vector2.ZERO, size)
		if tex == null:
			draw_rect(rect, Color(0.14, 0.2, 0.26))
			return
		var asp := size.x / maxf(size.y, 1.0)
		var half := Vector2(r * asp, r)
		var src := Rect2((Vector2(world.x, world.z) - half - Minimap.BOUNDS.position) / Minimap.M_PER_PX, half * 2.0 / Minimap.M_PER_PX)
		draw_texture_rect_region(tex, rect, src)
		draw_rect(rect, Color(0.04, 0.06, 0.08, 0.18))
		var c := size * 0.5
		draw_circle(c + Vector2(0, 2), 9.0, Color(0, 0, 0, 0.35))
		draw_circle(c, 8.0, EmpireStyle.AMBER)
		draw_circle(c, 3.5, EmpireStyle.INK)
