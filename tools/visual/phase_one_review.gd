extends Node
## Fixed-camera review of the real game. Run phase_one_review.tscn with
## --fixed-fps 12 --resolution 960x540 --rendering-method mobile before the
## scene path and -- --play --new --quality=1 --weather=clear --touch
## --review-out=<directory> --save=<review-only-save-path> after it.

@onready var game := get_parent() as EmpireGame
var output: String


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	output = String(game.args.get("review-out", ""))
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Supply a writable --review-out directory")
		get_tree().quit(1)
		return
	game.ui.close_panel(true)
	game.ui.hide()
	game.player.hide()
	var start := game.starter_unit()
	var door := Premises.door_point(start)
	var outward := Premises.outward(start)
	_hour(14.0)
	var car: Car = game.cars[game.empire.vehicles[0]["id"]]
	var centre := car.global_position + Vector3.UP * 0.55
	await _view("03_vehicle", centre + car.global_basis * Vector3(3.6, 1.25, -4.2), centre)
	var lease_error := game.rent_unit(start)
	if not lease_error.is_empty():
		push_error(lease_error)
		get_tree().quit(1)
		return
	await _view("08_shop", door + outward * 14.0 + Vector3.UP * 2.2, door + Vector3.UP * 2.7)

	var cbd := Vector3(455, game.layout.ground_y(470, -195), -170)
	game._teleport(cbd + Vector3.UP, 0.0)
	_hour(22.0)
	await _view("01_cbd_night", cbd + Vector3.UP * 3.2, cbd + Vector3(55, 4, -50))
	_hour(14.0)
	await _view("02_cbd_day", cbd + Vector3.UP * 3.2, cbd + Vector3(55, 4, -50))
	var west := Vector3(-1057, game.layout.ground_y(-1057, 234), 234)
	game._teleport(west + Vector3.UP, 0.0)
	await _view("05_residential", west + Vector3.UP * 2.0, west + Vector3(4, 3, 78))
	var lane := Vector3(-776, CityLayout.approach_y(-776), CityLayout.BRIDGE_Z + 4)
	game._teleport(lane + Vector3.UP, 0.0)
	await _view("09_bridge_landing", lane + Vector3.UP * 1.8, lane + Vector3(100, 3, 0))
	var airport := Vector3(-376, game.layout.ground_y(-376, 1558), 1558)
	game._teleport(airport + Vector3.UP, 0.0)
	await _view("06_skyport", Vector3(-200, 45, 1450), Vector3(-450, 4, 1620))
	var marina_door: Vector3 = game.skyport_play.site("marina")["door"]
	game._teleport(marina_door + Vector3.UP, 0.0)
	var berth := game.skyport_play.free_slot("boat")
	var boat := game.skyport_play._spawn(game.empire.add_vehicle("dart", berth[0], berth[1]))
	var boat_centre := boat.global_position + Vector3.UP
	await _view("07_marina", boat_centre + Vector3(14, 6, -19), boat_centre)

	game.camera.cine = Callable()
	game._teleport(door + outward * 3.2 + Vector3.UP, atan2(-outward.x, -outward.z) + PI)
	game.rig.set_facing(outward)
	game.player.show()
	game.ui.show()
	var previous_camera := game.camera.cam.transform
	var previous_fov := game.camera.cam.fov
	game.ui.open_style()
	await _shot("04_editor")
	var head := game.rig.bones["head"] as Node3D
	print("WARDROBE_HEAD ", game.camera.cam.unproject_position(head.global_position) / get_viewport().get_visible_rect().size)
	game.ui._close_style()
	var restored := game.camera.cam.transform.is_equal_approx(previous_camera) and is_equal_approx(game.camera.cam.fov, previous_fov)
	print("WARDROBE_CAMERA_RESTORED ", restored)
	get_tree().quit()


func _hour(hour: float) -> void:
	game.empire.minute = hour * 60.0
	game.atmosphere.hour = hour
	game.atmosphere.set_weather("clear", true)
	game.atmosphere._apply(0.0, true)


func _view(label: String, eye: Vector3, target: Vector3) -> void:
	var pose := Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	game.camera.cine = func(_dt: float) -> Array: return [pose, 62.0]
	await _shot(label)


func _shot(label: String) -> void:
	for frame in 10:
		await RenderingServer.frame_post_draw
	var path := output.path_join(label + ".png")
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK:
		push_error("Could not write " + path)
		get_tree().quit(1)
	print("REVIEW ", label, " ", get_viewport().get_camera_3d().global_position)
