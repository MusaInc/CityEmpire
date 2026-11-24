extends SceneTree
## Matched WorldState layout, camera positions, weather, and simulation steps.

var game: Node
var output := ""
var only := PackedStringArray()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lab-output="):
			output = arg.trim_prefix("--lab-output=")
		if arg.begins_with("--lab-scenes="):
			only = arg.trim_prefix("--lab-scenes=").split(",", false)
	run.call_deferred()


func run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("The comparison requires a display and an output directory.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.minutes_per_second = 0.0
	game.ui.close_panel(true)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var west := Vector3(-1057, game.layout.ground_y(-1057, 234), 234)
	var cbd := Vector3(492, game.layout.ground_y(492, -174), -174)
	if selected("day"):
		await street("day", west + Vector3(2, 0, 3), west + Vector3(0, 1.8, 0), west + Vector3(4, 3, 78), 14.0, "clear")
	if selected("night"):
		await street("night", cbd + Vector3(1, 0, -2), cbd + Vector3(0, 1.7, 0), cbd + Vector3(48, 3.2, -60), 22.0, "clear")
	if selected("rain"):
		await street("rain", cbd + Vector3(1, 0, -2), cbd + Vector3(0, 1.7, 0), cbd + Vector3(48, 3.2, -60), 22.0, "rain")
	if selected("interior"):
		var starter: Dictionary = game.starter_unit()
		var shop: Node3D = game.interiors.get(starter["id"])
		if shop == null:
			shop = game._build_interior(starter)
		var foot: Vector3 = shop.to_world(Vector3(shop.W * 0.32, 0.0, -shop.D * 0.21))
		var eye: Vector3 = shop.to_world(Vector3(shop.W * 0.23, 2.3, -shop.D * 0.13))
		var target: Vector3 = shop.to_world(Vector3(shop.W * 0.63, 1.30, -shop.D * 0.65))
		await street("interior", foot, eye, target, 11.0, "clear", true)
	if selected("driving"):
		game.camera.cine = Callable()
		game._teleport(west + Vector3.UP, PI)
		weather(22.0, "rain")
		var id := String(game.empire.vehicles[0]["id"])
		var car: RigidBody3D = game.cars[id]
		car.place(Transform3D(Basis(Vector3.UP, PI), west + Vector3(0.8, 0.40, 5.5)))
		game.enter_vehicle(id)
		game.drive_input.enabled = false
		car.handbrake = false
		car.brake = 0.0
		car.throttle = 0.26
		await capture("driving")
	quit(0)


func selected(scene: String) -> bool:
	return only.is_empty() or scene in only


func weather(hour: float, sky: String) -> void:
	game.args["weather"] = sky
	game.empire.minute = hour * 60.0
	game.atmosphere.hour = hour
	game.atmosphere.set_weather(sky, true)
	game.atmosphere._apply(0.0, true)


func street(scene: String, spawn: Vector3, eye: Vector3, target: Vector3, hour: float, sky: String, indoors := false) -> void:
	if not indoors:
		spawn.y = game.layout.ground_y(spawn.x, spawn.z)
	game._teleport(spawn + Vector3.UP * 0.92, 0.0)
	weather(hour, sky)
	var pose := Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	game.camera.cine = func(_dt: float) -> Array: return [pose, 63.0]
	await capture(scene)


func capture(scene: String) -> void:
	for i in 16:
		await RenderingServer.frame_post_draw
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in 12:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	var m: Dictionary = load("res://src/world/render_lab.gd").metrics(root)
	m["scene"] = scene
	m["weather"] = game.atmosphere.weather
	m["frame_p50_ms"] = snappedf(times[5], 0.01)
	m["frame_p95_ms"] = snappedf(times[11], 0.01)
	m["wetness"] = game.atmosphere.wetness
	var err := root.get_texture().get_image().save_png(output.path_join(scene + ".png"))
	if err != OK:
		push_error("Screenshot write failed for " + scene)
	print("LAB_STATS ", JSON.stringify(m))
