extends CanvasLayer
## Launch → menu as one movement (2026-11-27).
##
##   1. The OS launch screen (assets/splash/launch.png on Brand.NAVY_DEEP)
##      hands over to this screen with the gold W at the SAME size and place
##      (Brand.SPLASH_FRAC of the short side, centred) – no cut, no flash.
##   2. While the game loads, a golden shimmer travels across the W every few
##      seconds and a soft glow breathes round it (2026-11-27), and a gold
##      hairline tracks the real progress: the scene's threaded load, then
##      the world's build (LoadPacer: paced so frames keep coming, its
##      node-free parts on worker threads) and the menu's view.
##   3. When the view has rendered, the navy lifts off the city, the W glides
##      into the menu's wordmark and the city's sound rises with it.
## No dependency on Main/MenuParts: those pull in the city and hero resources.

@export var scene_path := "res://scenes/main.tscn"
@export var auto_start := true
var surface: Control
var bg: ColorRect
var mark: Brand.Mark
var glow: Brand.Glow
var plain: TextureRect
var track: ColorRect
var fill: ColorRect
var status: Label
var retry: Button
var _requested := false
var _finishing := false
var _starting := false
var _shown := 0.0          # progress drawn (eases toward _target, never back)
var _target := 0.0
var _anim := 0.0           # the shimmer/breath clock (clamped per frame)
var _fx := 1.0             # shimmer + glow strength (fades out at the reveal)
var _t_boot := 0
var _gaps := {"max": 0.0, "n": 0, "over34": 0, "over50": 0, "over100": 0, "sum": 0.0}
var _timing := false
var _last_us := 0
var _master_db := 0.0
var _master := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	_t_boot = Time.get_ticks_msec()
	_timing = LoadPacer.timing()
	_master = AudioServer.get_bus_index("Master")
	_master_db = AudioServer.get_bus_volume_db(_master)
	AudioServer.set_bus_volume_db(_master, -60.0)
	print("BOOT ready (%s, %s)" % [OS.get_name(), RenderingServer.get_current_rendering_driver_name()])
	_build_view()
	get_viewport().size_changed.connect(_place)
	_first_frame.call_deferred()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--boot-shots="):
			_boot_shots(a.trim_prefix("--boot-shots="))
	if auto_start:
		_begin.call_deferred()


func _first_frame() -> void:
	await RenderingServer.frame_post_draw
	print("BOOT first frame drawn at %d ms" % (Time.get_ticks_msec() - _t_boot))


## Review: --boot-shots=<dir> saves a frame every 0.5 s from the first splash
## frame through the reveal into the menu (the boot layer frees itself, so
## the loop runs on the tree, not on this node).
func _boot_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var tree := get_tree()
	var loop := func() -> void:
		for i in 120:
			await RenderingServer.frame_post_draw
			tree.root.get_texture().get_image().save_png("%s/boot_%02d.png" % [dir, i])
			print("BOOT_SHOT ", i)
			await tree.create_timer(0.5, true, false, true).timeout
		tree.quit()
	loop.call()


func _build_view() -> void:
	surface = Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(surface)
	bg = ColorRect.new()
	bg.color = Brand.NAVY_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(bg)
	glow = Brand.Glow.new()
	surface.add_child(glow)
	# Insurance: the same W in flat gold with no custom shader, exactly under
	# the shaded one (same mask, so it never shows round it). If the gold
	# shader ever fails to compile on a device, the W is still there.
	plain = TextureRect.new()
	plain.texture = preload("res://assets/brand/w_alpha.png")   # (white W with alpha: the mask, as alpha)
	plain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plain.stretch_mode = TextureRect.STRETCH_SCALE
	plain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	plain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plain.material = CanvasItemMaterial.new()
	plain.self_modulate = Brand.GOLD
	surface.add_child(plain)
	mark = Brand.Mark.new(100.0)
	surface.add_child(mark)
	track = ColorRect.new()
	track.color = Color(Brand.GOLD, 0.16)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.modulate.a = 0.0
	surface.add_child(track)
	fill = ColorRect.new()
	fill.color = Color(Brand.GOLD, 0.9)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_override("font", Glass.font("medium"))
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_color_override("font_color", Color(Brand.IVORY, 0.7))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(status)
	retry = Button.new()
	retry.text = "Try again"
	retry.visible = false
	retry.add_theme_font_override("font", Glass.font("semibold"))
	retry.add_theme_color_override("font_color", Brand.GOLD_TEXT)
	retry.pressed.connect(_begin)
	surface.add_child(retry)
	_place()


## The W exactly where launch.png draws it (fit to the window, centred).
func _place() -> void:
	if _flying:
		return
	var vs := get_viewport().get_visible_rect().size
	var w := Brand.SPLASH_FRAC * minf(vs.x, vs.y)
	mark.set_width(w)
	mark.position = (vs - mark.size) * 0.5
	plain.position = mark.position
	plain.size = mark.size
	glow.fit(mark)
	var lw := w * 0.62
	track.size = Vector2(lw, 2.0)
	track.position = Vector2((vs.x - lw) * 0.5, mark.position.y + mark.size.y + w * 0.30)
	fill.size = Vector2(lw * _shown, 2.0)
	status.size = Vector2(vs.x, 24)
	status.position = Vector2(0, track.position.y + 18.0)
	retry.size = Vector2(200, 44)
	retry.position = Vector2((vs.x - 200.0) * 0.5, status.position.y + 30.0)


var _flying := false


func _begin() -> void:
	if _requested or _finishing or _starting:
		return
	_starting = true
	retry.hide()
	status.text = ""
	_target = 0.0
	# The hairline eases in only if the load is not instant.
	var tw := create_tween()
	tw.tween_property(track, "modulate:a", 1.0, 0.5).set_delay(0.35)
	# Let the branded frame reach the display before requesting heavier assets.
	await get_tree().process_frame
	await get_tree().process_frame
	# (Sub-threads: the scene's dependencies load in parallel.)
	var err := ResourceLoader.load_threaded_request(scene_path, "PackedScene", true)
	if err != OK:
		_failed()
		return
	_requested = true
	_starting = false


func _process(dt: float) -> void:
	# Progress line: ease toward the target, never backwards.
	if _target > _shown:
		_shown = move_toward(_shown, _target, maxf((_target - _shown) * 5.0 * dt, 0.12 * dt))
	fill.size.x = track.size.x * _shown
	_animate(dt)
	if _timing and _requested and not _flying:
		# (Wall clock between frames, not dt.)
		var now := Time.get_ticks_usec()
		var gap := (now - _last_us) / 1000000.0 if _last_us > 0 else dt
		_last_us = now
		_gaps["n"] += 1
		_gaps["sum"] += gap
		_gaps["max"] = maxf(_gaps["max"], gap)
		if gap > 0.1:
			print("LOAD_GAP %5.0f ms ending at t=%d" % [gap * 1000.0, Time.get_ticks_msec()])
		for lim in [34, 50, 100]:
			if gap * 1000.0 > lim:
				_gaps["over%d" % lim] += 1
	if not _requested or _finishing:
		return
	var amount: Array = []
	var state := ResourceLoader.load_threaded_get_status(scene_path, amount)
	if not amount.is_empty():
		_target = maxf(_target, float(amount[0]) * 0.55)
	match state:
		ResourceLoader.THREAD_LOAD_LOADED:
			_finishing = true
			_open_city()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_failed()


## The W's life while it waits: a shimmer of light travels across the gold
## every SHIMMER_EVERY s and a soft glow breathes round it. Both ease in after
## the OS launch screen's hand-off (that frame is still) and fade at the
## reveal. The clock steps at most 1/30 s a frame, so a slow frame slows the
## light a touch instead of making it jump.
const SHIMMER_EVERY := 3.6
const SHIMMER_TRAVEL := 1.9
const BREATH := 4.8


func _animate(dt: float) -> void:
	_anim += minf(dt, 1.0 / 30.0)
	var intro := smoothstep(0.35, 1.6, _anim) * _fx
	var breath := 0.5 - 0.5 * cos(TAU * _anim / BREATH)
	glow.set_strength(intro * (0.07 + 0.13 * breath))
	mark.mat.set_shader_parameter("lift", 1.0 + 0.045 * breath * intro)
	var t := fmod(maxf(_anim - 0.8, 0.0), SHIMMER_EVERY) / SHIMMER_TRAVEL
	if _anim > 0.8 and t < 1.0:
		mark.mat.set_shader_parameter("sweep", lerpf(-0.45, 1.45, smoothstep(0.0, 1.0, t)))
		mark.mat.set_shader_parameter("sweep_k", 0.46 * intro * sin(PI * t))
	else:
		mark.mat.set_shader_parameter("sweep_k", 0.0)


func _open_city() -> void:
	_target = 0.6
	await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if _timing:
		print("LOAD_T BOOT scene loaded            %6d ms since boot" % (Time.get_ticks_msec() - _t_boot))
	if packed == null:
		_failed()
		return
	var game := packed.instantiate()
	if game == null:
		_failed()
		return
	_target = 0.62
	await get_tree().process_frame
	# The world builds over many frames from here (EmpireGame._ready yields).
	LoadPacer.progress = 0.0
	LoadPacer.active = true
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	# Until the world is whole and the menu's view has rendered (title_ready).
	# Bounded by wall time, not frames: the build is paced, so frames come.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000:
		var warm = game.get("warmed")
		var ready = game.get("title_ready")
		if (warm == null or warm == true) and (ready == null or ready == true):
			break
		_target = maxf(_target, 0.62 + LoadPacer.progress * 0.37)
		await get_tree().process_frame
	LoadPacer.active = false
	_target = 1.0
	if _timing:
		print("LOAD_T BOOT world+menu ready        %6d ms since boot" % (Time.get_ticks_msec() - _t_boot))
		var n := maxi(int(_gaps["n"]), 1)
		print("LOAD_FRAMES %d frames while loading, mean %.1f ms, worst %.0f ms, >34 ms: %d, >50 ms: %d, >100 ms: %d" % [
			n, float(_gaps["sum"]) / n * 1000.0, float(_gaps["max"]) * 1000.0, _gaps["over34"], _gaps["over50"], _gaps["over100"]])
	await get_tree().create_timer(0.18).timeout
	_reveal(game)


func _reveal(game: Node) -> void:
	_flying = true
	var ui = game.get("ui")
	var to := Rect2()
	if game.get("state") == "title" and ui != null:
		to = ui.title_logo_rect()
	if ui != null and game.get("state") == "title":
		ui.title_reveal(0.35)
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "_fx", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(track, "modulate:a", 0.0, 0.3)
	tw.tween_property(bg, "modulate:a", 0.0, 1.3).set_delay(0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if to.size.x > 0.0:
		tw.tween_property(mark, "position", to.position, 1.15).set_delay(0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(mark, "size", to.size, 1.15).set_delay(0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(mark, "custom_minimum_size", to.size, 1.15).set_delay(0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	else:
		tw.tween_property(mark, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	# The city's sound rises as it appears.
	tw.tween_method(func(db: float): AudioServer.set_bus_volume_db(_master, db), -60.0, _master_db, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(1.3).timeout
	if ui != null and to.size.x > 0.0:
		ui.title_handoff()
		mark.visible = false   # the menu's own W carries on from here
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await tw.finished
	queue_free()


func _failed() -> void:
	LoadPacer.active = false
	_requested = false
	_finishing = false
	_starting = false
	status.text = "Couldn't load the city. Please try again."
	track.modulate.a = 0.0
	retry.show()
	retry.grab_focus()
	AudioServer.set_bus_volume_db(_master, _master_db)
