extends Node
## Deterministic Mobile review on the staging commit and checkpoint.
## Pass --review-out=<absolute path> after Godot's -- separator.

@onready var game := get_parent() as EmpireGame
var output: String


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	output = String(game.args.get("review-out", ""))
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		get_tree().quit(1)
		return
	game.ui.close_panel(true)
	if game.args.has("review-poses"):
		await _poses()
		return
	var estate := game.starter_unit()
	var door := Premises.door_point(estate)
	var outward := Premises.outward(estate)
	var along := Vector3(-outward.z, 0, outward.x)
	var at := game._kerb_point(door + outward * 6.5 + along * 5.0)
	at.y = game.layout.ground_y(at.x, at.z) + 0.035
	var yaw := atan2(-along.x, -along.z)
	game._teleport(at + Vector3.UP * 0.90, yaw)
	var vf := game.empire.add_vehicle("stiletto", at, yaw)
	var id := String(vf["id"])
	var car := game._spawn_car(vf)
	car.place(Transform3D(Basis(Vector3.UP, yaw), at))
	await get_tree().physics_frame
	# Hold the same car, view and sky while changing only the loaded material.
	game.enter_vehicle(id)
	car.freeze = true
	var center: Vector3 = car.visual.body.to_global(Vector3(0, 0.68, 0))
	var eye := center + car.global_basis * Vector3(3.2, 0.95, -3.1)
	game.camera.cam.make_current()
	game.camera.cine = func(_dt: float) -> Array:
		return [Transform3D(Basis.looking_at(center - eye), eye), 58.0]
	game.ui.hide()
	_weather(14.0, "clear")
	await _frames(27)
	await _sample_frames("stiletto_day", 12)
	await _shot("01_stiletto_runtime")
	_clearance(car, "stiletto")
	var body: MeshInstance3D = car.visual.body
	var restored := {}
	for i in body.mesh.get_surface_count():
		var imported := body.mesh.surface_get_material(i)
		if imported and imported.resource_name == "paint":
			restored[i] = body.get_surface_override_material(i)
			var pbr := StandardMaterial3D.new()
			pbr.albedo_color = car.spec["paint"]
			pbr.metallic = 0.45
			pbr.roughness = 0.3
			body.set_surface_override_material(i, pbr)
	await _frames(3)
	await _shot("02_stiletto_pbr_isolation")
	for i in restored:
		body.set_surface_override_material(i, restored[i])
	_weather(21.8, "clear")
	await _frames(4)
	await _shot("03_stiletto_night")
	_weather(17.0, "rain")
	await _frames(4)
	await _shot("04_stiletto_rain")
	_weather(14.0, "clear")
	game.chase.cam.make_current()
	game.ui.show()
	var original := Settings.driving_lens
	Settings.driving_lens = 0.0
	await _frames(5)
	var lens := game.get_node("DrivingLens") as LensFx
	game.process_mode = Node.PROCESS_MODE_DISABLED
	lens.set_process(false)
	await _shot("05_lens_off")
	Settings.driving_lens = 1.0
	lens.visible = true
	lens.set_speed(0.65, 4.0)
	await _frames(2)
	await _shot("06_lens_on")
	lens.set_process(true)
	Settings.driving_lens = original
	game.process_mode = Node.PROCESS_MODE_INHERIT
	game.ui.hide()
	game.camera.cam.make_current()
	var highway := Vector3((CityLayout.FAR_SHORE + 56.0) * 0.5, CityLayout.BRIDGE_DECK, CityLayout.BRIDGE_Z)
	var view := highway + Vector3(-12, -8, -24)
	var target := highway + Vector3(48, -2.9, 5)
	game.camera.cine = func(_dt: float) -> Array:
		return [Transform3D(Basis.looking_at(target - view), view), 64.0]
	game.world.build_all_near(highway, 280.0)
	await _frames(13)
	await _shot("07_bridge_soffit")
	await _drive_review(car)
	get_tree().quit()


func _drive_review(car: Car) -> void:
	var site := Vector3(-765, CityLayout.approach_y(-765) + 0.07, CityLayout.BRIDGE_Z + 4.2)
	car.place(Transform3D(Basis.looking_at(Vector3.RIGHT), site))
	car.freeze = false
	car.park_lock = false
	game.chase.set_target(car, true)
	game.chase.cam.make_current()
	game.world.set_viewer(game.chase)
	game.world.build_all_near(site, 300.0)
	_weather(21.8, "rain")
	await _frames(6)
	car.linear_velocity = Vector3.RIGHT * 30.0
	await _sample_frames("bridge_drive", 24)
	await _shot("08_driving_bridge_wet")
	print("DRIVE_REVIEW speed=", car.speed, " pos=", car.global_position)


func _sample_frames(label: String, count: int) -> void:
	var durations := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in count:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		durations.append(float(now - last) / 1000.0)
		last = now
	durations.sort()
	print("FRAME_REVIEW ", label, " p50=", durations[count >> 1], " p95=", durations[ceili(count * 0.95) - 1])


func _poses() -> void:
	var at := game.player.global_position
	var failures := 0
	var original := game.rig.look_state.duplicate()
	var profiles := EmpireData.file("vehicle_entries")
	for body_type in ["a", "b"]:
		var appearance := original.duplicate()
		appearance["body"] = body_type
		game.rig.apply_look(appearance)
		for model in ["kestrel", "scout", "marlin", "brute", "vanta", "halcyon", "stiletto", "goliath", "warden", "van", "box"]:
			var vehicle := game.empire.add_vehicle(model, at + Vector3(0, 0.3, -4), 0.0)
			var id := String(vehicle["id"])
			var car := game._spawn_car(vehicle)
			game.enter_vehicle(id)
			car.freeze = true
			for i in 32:
				await get_tree().process_frame
			if game.rig.vehicle_seated:
				var profile: Dictionary = profiles[car.spec["body"]]
				var head := game.rig.bones["head"] as Node3D
				var crown: Vector3 = car.visual.body.to_local(head.global_position + head.global_basis.y * 0.18)
				var offset := clampf((crown.z - float(profile["seat"][0])) / 0.12, 0.0, 4.0)
				var roof: Array = profile["roof_samples"]
				var clearance := lerpf(float(roof[floori(offset)]), float(roof[ceili(offset)]), fposmod(offset, 1.0)) - crown.y
				print("CABIN ", body_type, " ", model, " crown=", crown, " clearance=", clearance)
				failures += int(clearance <= 0.0)
			else:
				print("CABIN ", body_type, " ", model, " opaque glass")
			game._finish_vehicle_exit(at, Transform3D.IDENTITY, 70.0, id)
			game.cars.erase(id)
			car.queue_free()
	var repeat_ok := await _boarding_cycles()
	failures += int(not repeat_ok)
	var feared := await _panic_drive(false)
	failures += int(feared < 0.42)
	# Check prediction and wrong-elevation rejection without using a traffic-mesh shortcut.
	var focus := Vector3(0, 0, 0)
	game.crowd._vehicles = [[Vector2(0.4, -14), Vector2(0, 20), 1.0, 0.0, 2.3, 0.0, false]]
	var hazard: Array = game.crowd.call("_vehicle_hazard", focus, Vector2(0, -1))
	var wrong_deck: Array = game.crowd.call("_vehicle_hazard", focus + Vector3.UP * 5.0, Vector2(0, -1))
	failures += int(float(hazard[0]) < 0.5 or float(wrong_deck[0]) > 0.0)
	print("CROWD predicted=", hazard, " other deck=", wrong_deck)
	print("POSE_REVIEW failures=", failures)
	get_tree().quit(failures)


func _boarding_cycles() -> bool:
	var position := Vector3(-765, CityLayout.approach_y(-765) + 0.06, CityLayout.BRIDGE_Z + 2.2)
	var yaw := -PI * 0.5
	var rotation := Basis(Vector3.UP, yaw)
	var record := game.empire.add_vehicle("stiletto", position, yaw)
	var id := String(record["id"])
	var car := game._spawn_car(record)
	car.place(Transform3D(rotation, position))
	car.freeze = true
	game.world.build_all_near(position, 290.0)
	var loops_ok := true
	for side in [1.0, -1.0]:
		var stand := position + rotation.x * float(side) * 1.85 + Vector3.UP * 0.9
		game._teleport(stand, yaw)
		await get_tree().physics_frame
		game.enter_vehicle(id, true)
		var anchor := car.global_position
		var access := game.vehicle_access
		var pin_ok := access.active() and is_equal_approx(access.side, float(side))
		for i in 155:
			await get_tree().physics_frame
			if access.active():
				pin_ok = pin_ok and car.freeze and not game.drive_input.enabled and car.global_position.distance_to(anchor) < 0.05
		var entered := game.driving == id and game.drive_input.enabled and not access.active()
		car.freeze = true
		game.exit_vehicle(true)
		for i in 130:
			await get_tree().physics_frame
		var exited := game.driving.is_empty() and game.player.input_enabled and not access.active()
		print("ACCESS_REVIEW side=", side, " pinned=", pin_ok, " entered=", entered, " exited=", exited)
		loops_ok = loops_ok and pin_ok and entered and exited
		if not exited:
			break
	return loops_ok


func _panic_drive(capture: bool) -> float:
	var unit := game.starter_unit()
	var door := Premises.door_point(unit)
	var desired := Premises.outward(unit)
	game._teleport(door + desired * 7.0 + Vector3.UP, 0.0)
	if game.in_vehicle():
		return 0.0
	for i in 50:
		await get_tree().physics_frame
	var subject: Dictionary = {}
	var lane := Vector2.ZERO
	for pr in game.crowd._people:
		var loop: Dictionary = game.crowd._loops[pr["loop"]]
		if pr["state"] != "walk" or not (loop["crossings"] as Array).is_empty():
			continue
		var ahead: Array = game.crowd._sample(loop, float(pr["s"]) + 4.0)
		var behind: Array = game.crowd._sample(loop, float(pr["s"]) - 18.0)
		if int(ahead[2]) == int(behind[2]):
			subject = pr
			lane = ahead[1]
			break
	if subject.is_empty() or lane == Vector2.ZERO:
		print("PANIC_REVIEW could not select a clear sidewalk")
		return 0.0
	var origin: Vector3 = subject["pos"]
	var dir := Vector3(lane.x, 0, lane.y)
	var pos := origin - dir * 15.0
	pos.y = game.layout.ground_y(pos.x, pos.z) + 0.055
	var yaw := atan2(-dir.x, -dir.z)
	var car_record := game.empire.add_vehicle("stiletto", pos, yaw)
	var car := game._spawn_car(car_record)
	car.place(Transform3D(Basis(Vector3.UP, yaw), pos))
	game.enter_vehicle(String(car_record["id"]))
	car.park_lock = false
	car.linear_velocity = dir * 19.0
	var fear := 0.0
	var speed := 0.0
	for i in 44:
		await get_tree().physics_frame
		fear = maxf(fear, float(subject.get("fear", 0.0)))
		speed = maxf(speed, car.speed)
		if capture and not is_zero_approx(fear) and i % 10 == 0:
			await _shot("panic_%02d" % i)
	print("PANIC_REVIEW peak_fear=", fear, " vehicle_peak_mps=", speed, " vehicle_displacement=", car.global_position.distance_to(pos))
	return fear


func _clearance(car: Car, label: String) -> void:
	var head := game.rig.bones["head"] as Node3D
	var crown: Vector3 = car.visual.body.to_local(head.global_position + head.global_basis.y * 0.18)
	print("DRIVER_CROWN ", label, " ", crown)


func _weather(hour: float, weather: String) -> void:
	game.empire.minute = hour * 60.0
	game.atmosphere.hour = hour
	game.atmosphere.set_weather(weather, true)
	game.atmosphere._apply(0.0, true)


func _frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
	if result != OK:
		push_error("Could not save " + label)
	print("REVIEW ", label, " draws=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		" primitives=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		" video=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))
