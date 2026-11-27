extends CanvasLayer
## Launch → menu as one movement (2026-11-27).
##
##   1. The OS launch screen (assets/splash/launch.png on Brand.NAVY_DEEP)
##      hands over to this screen with the gold W at the SAME size and place
##      (Brand.SPLASH_FRAC of the short side, centred) – no cut, no flash.
##   2. While the game loads, a metallic light sweeps the W now and then and
##      a gold hairline under it tracks the real progress: the scene's
##      threaded load, then the world building round the menu's view.
##   3. When the view has rendered, the navy lifts off the city, the W glides
##      into the menu's wordmark and the city's sound rises with it.
## No dependency on Main/MenuParts: those pull in the city and hero resources.

@export var scene_path := "res://scenes/main.tscn"
@export var auto_start := true
var surface: Control
var bg: ColorRect
var mark: Brand.Mark
var track: ColorRect
var fill: ColorRect
var status: Label
var retry: Button
var _requested := false
var _finishing := false
var _starting := false
var _shown := 0.0          # progress drawn (eases toward _target, never back)
var _target := 0.0
var _shine_in := 0.9
var _master_db := 0.0
var _master := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	_master = AudioServer.get_bus_index("Master")
	_master_db = AudioServer.get_bus_volume_db(_master)
	AudioServer.set_bus_volume_db(_master, -60.0)
	_build_view()
	get_viewport().size_changed.connect(_place)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--boot-shots="):
			_boot_shots(a.trim_prefix("--boot-shots="))
	if auto_start:
		_begin.call_deferred()


## Review: --boot-shots=<dir> saves a frame every 0.5 s from the first splash
## frame through the reveal into the menu (the boot layer frees itself, so
## the loop runs on the tree, not on this node).
func _boot_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var tree := get_tree()
	var loop := func() -> void:
		for i in 40:
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
	var err := ResourceLoader.load_threaded_request(scene_path, "PackedScene")
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
	if not _flying:
		_shine_in -= dt
		if _shine_in <= 0.0:
			_shine_in = 2.8
			mark.shine(1.5, 0.5)
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


func _open_city() -> void:
	_target = 0.6
	await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if packed == null:
		_failed()
		return
	var game := packed.instantiate()
	if game == null:
		_failed()
		return
	_target = 0.7
	await get_tree().process_frame
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	_target = 0.82
	# Late shaders compile and the menu's view builds under this screen.
	# Bounded: never hold more than ~6 s on it.
	var waited := 0
	while waited < 360:
		var warm = game.get("warmed")
		var ready = game.get("title_ready")
		if (warm == null or warm == true) and (ready == null or ready == true):
			break
		_target = minf(0.82 + waited / 360.0 * 0.17, 0.99)
		await get_tree().process_frame
		waited += 1
	_target = 1.0
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
	_requested = false
	_finishing = false
	_starting = false
	status.text = "Couldn't load the city. Please try again."
	track.modulate.a = 0.0
	retry.show()
	retry.grab_focus()
	AudioServer.set_bus_volume_db(_master, _master_db)
