class_name Thumbs
extends Node
## Cached preview images for the dashboard, from the game's own content:
##  * vehicles: the real car / aircraft / boat model rendered once in a
##    small offscreen viewport (3/4 view, studio light), cached per model
##    for the session (one ~260×150 image each; the viewport is freed);
##  * places: a crop of the baked city map (the same image as the minimap)
##    round a world point, with a pin – no extra rendering at all.
## No live 3D in the dashboard: images only, made on demand, one at a time.

const VW := Vector2i(640, 368)   # (big enough for the Garage and Marketplace hero shots)
const CACHE_MAX := 24

static var _cache := {}       # model -> ImageTexture
static var _order: Array = [] # LRU keys, oldest first
var _queue: Array = []        # [model, TextureRect]
var _busy := false
var game: EmpireGame


static func clear_caches() -> void:
	_cache.clear()
	_order.clear()


static func _remember(model: String, tex: Texture2D) -> void:
	_cache[model] = tex
	_order.erase(model)
	_order.append(model)
	while _order.size() > CACHE_MAX:
		_cache.erase(_order.pop_front())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # (the phone pauses the tree)


## A TextureRect that shows the model's picture (now if cached, else when
## it's rendered).
func vehicle(model: String, size := Vector2(260, 150)) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _cache.has(model):
		_order.erase(model)
		_order.append(model)
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
		_remember(model, await _render(model))
	var tex: Texture2D = _cache.get(model)
	for j in [job] + _queue.filter(func(q): return q[0] == model):
		if is_instance_valid(j[1]):
			(j[1] as TextureRect).texture = tex
	_queue = _queue.filter(func(q): return q[0] != model)
	_render_next.call_deferred()


func _render(model: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = VW
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS   # (freed after three frames)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.89, 0.95)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.78, 0.58, 0.0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.98, 0.95)
	vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.42, -2.4, 0.0)
	rim.light_energy = 0.62
	rim.light_color = Color(0.82, 0.90, 1.0)
	vp.add_child(rim)
	var cls := SkyportPlay.vclass(model)
	var holder := Node3D.new()
	vp.add_child(holder)
	var length := 4.6
	var width := 2.0
	if cls == "car":
		var c := Car.new()
		c.setup(game._car_spec(model), "display")
		c.freeze = true
		holder.add_child(c)
		var vis := CarVisual.new()
		c.add_child(vis)
		vis.setup(c)
		var csz := c.spec["size"] as Vector3
		length = float(csz.z)
		width = float(csz.x)
	else:
		var spec := SkyportPlay.craft_spec(model)
		holder.add_child(CraftModels.build(cls, model, spec))
		var ssz := spec["size"] as Vector3
		length = maxf(float(ssz.z), float(ssz.x))
		width = maxf(float(ssz.x), float(ssz.z) * 0.55)
	# Subtle studio contact shadow disc so the vehicle grounds cleanly on both Light and Dark cards.
	var shadow := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(width * 1.45, length * 1.28)
	qm.orientation = PlaneMesh.FACE_Y
	shadow.mesh = qm
	var sgrad := Gradient.new()
	sgrad.set_color(0, Color(0.0, 0.0, 0.0, 0.34))
	sgrad.add_point(0.55, Color(0.0, 0.0, 0.0, 0.16))
	sgrad.set_color(sgrad.get_point_count() - 1, Color(0.0, 0.0, 0.0, 0.0))
	var stex := GradientTexture2D.new()
	stex.gradient = sgrad
	stex.fill = GradientTexture2D.FILL_RADIAL
	stex.fill_from = Vector2(0.5, 0.5)
	stex.fill_to = Vector2(1.0, 0.5)
	stex.width = 64
	stex.height = 64
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_texture = stex
	smat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	shadow.material_override = smat
	shadow.position = Vector3(0.0, 0.02, 0.0)
	holder.add_child(shadow)
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
