class_name PhotoBook
extends RefCounted
## Property photos: real in-game renders of every purchasable place
## (tools/photos/shoot.sh → assets/photos/<id>_<view>.jpg, 640 px; views
## "front", "area", "inside"). Loaded lazily on a thread when a card first
## shows and kept in a small cache (most recent CACHE textures), so a long
## listing never loads more than it shows. A place without a photo falls
## back to its crop of the baked city map.

const S = preload("res://src/empire/ui/empire_style.gd")
const DIR := "res://assets/photos/"
const CACHE := 48
const VIEW_NAMES := {"front": "Street", "area": "Location", "inside": "Inside"}

static var _cache := {}          # path -> Texture2D
static var _order: Array = []    # paths, oldest first


static func path(id: String, view: String) -> String:
	return DIR + (id + "_" + view).replace(":", "_").replace("/", "_").replace(" ", "_") + ".jpg"


static func has(id: String, view := "front") -> bool:
	return ResourceLoader.exists(path(id, view))


## The views this place has photos of, best first.
static func views(id: String) -> Array:
	return ["front", "inside", "area"].filter(func(v): return has(id, v))


static func _remember(p: String, t: Texture2D) -> void:
	_cache[p] = t
	_order.erase(p)
	_order.append(p)
	while _order.size() > CACHE:
		_cache.erase(_order.pop_front())


## A rounded photo frame of size sz: the photo when there is one (fading in
## once loaded), else the map crop round `world` (if given).
static func frame(id: String, view: String, sz: Vector2, world := Vector3.INF, radius := 14) -> Control:
	var pan := Panel.new()
	pan.custom_minimum_size = sz
	pan.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.1, 0.13)
	sb.set_corner_radius_all(radius)
	pan.add_theme_stylebox_override("panel", sb)
	if has(id, view):
		var ph := Photo.new()
		ph.src = path(id, view)
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pan.add_child(ph)
	elif world.is_finite():
		var t := Thumbs.place(world, 140.0)
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pan.add_child(t)
	return pan


## A photo that loads itself on a thread the first time it's shown.
class Photo extends TextureRect:
	var src := ""
	var _req := false

	func _ready() -> void:
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS   # (the phone pauses the tree)
		if PhotoBook._cache.has(src):
			texture = PhotoBook._cache[src]
			set_process(false)
			return
		modulate.a = 0.0
		ResourceLoader.load_threaded_request(src, "Texture2D")
		_req = true

	func _process(dt: float) -> void:
		if _req:
			var st := ResourceLoader.load_threaded_get_status(src)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				var t := ResourceLoader.load_threaded_get(src) as Texture2D
				PhotoBook._remember(src, t)
				texture = t
				_req = false
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_req = false
				set_process(false)
			return
		modulate.a = minf(1.0, modulate.a + dt * 4.0)
		if modulate.a >= 1.0:
			set_process(false)


## The gallery: one big photo, the other views below to switch, the facts
## and the place's own actions ([[label, callable, primary], …]).
static func gallery(ui: EmpireUI, id: String, title: String, sub: String, facts: Array, actions: Array, world := Vector3.INF,
		view := "") -> void:
	var vs := views(id)
	if view == "" or not view in vs:
		view = vs[0] if not vs.is_empty() else "front"
	var v := ui._open(title, 940, 620)
	v.add_child(S.label(sub, 16, S.MUTED))
	var h := S.hbox(18)
	v.add_child(h)
	var left := S.vbox(8)
	left.add_child(frame(id, view, Vector2(600, 338), world, 16))
	if vs.size() > 1:
		var strip := S.hbox(8)
		for vw in vs:
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(150, 84)
			var fr := frame(id, vw, Vector2(150, 84), world, 10)
			fr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			b.add_child(fr)
			var sbn := StyleBoxFlat.new()
			sbn.bg_color = Color(0, 0, 0, 0)
			sbn.set_corner_radius_all(10)
			sbn.set_border_width_all(3 if vw == view else 0)
			sbn.border_color = S.AMBER
			for stn in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(stn, sbn)
			var cap := S.label(String(VIEW_NAMES.get(vw, vw)), 12, S.PAPER, "black")
			cap.position = Vector2(8, 60)
			cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(cap)
			var vk := String(vw)
			b.pressed.connect(func(): gallery(ui, id, title, sub, facts, actions, world, vk))
			strip.add_child(b)
		left.add_child(strip)
	h.add_child(left)
	var right := S.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for f in facts:
		var fv := S.vbox(-2)
		fv.add_child(S.label(String(f[0]).to_upper(), 12, S.MUTED, "black"))
		fv.add_child(S.label(String(f[1]), 20, f[2] if f.size() > 2 else S.PAPER, "black"))
		right.add_child(fv)
	right.add_child(S.spacer())
	for a in actions:
		right.add_child(S.button(String(a[0]), a[1], a.size() > 2 and a[2], 260))
	h.add_child(right)
