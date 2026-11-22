extends RefCounted
## Right-pad throttle, braking and the left/right steering handoff.

const K := 1.0   # phone scale


func _ground(runner: SceneTree) -> StaticBody3D:
	var g := StaticBody3D.new()
	g.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	g.add_child(cs)
	runner.root.add_child(g)
	return g


func _car(runner: SceneTree, model := "hatch") -> Car:
	var m := EmpireData.vehicle_model(model)
	var s := CarCatalog.spec(String(m["base"]))
	s["top_speed"] = float(m["top_speed"])
	s["nitro"] = 0.0
	var c := Car.new()
	c.setup(s, "player")
	runner.root.add_child(c)
	c.place(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)))
	return c


## Returns [distance travelled, max absolute tyre slip angle].
func _hold(runner: SceneTree, c: Car, o: Vector2, secs: float, steer := 0.0, drift := false) -> Array:
	var p0 := c.global_position
	var max_drift := 0.0
	for i in int(secs * 60.0):
		var pd := EmpireTouch.read_pad(o, K)
		c.throttle = pd["gas"]
		c.brake = pd["brake"]
		c.kickdown = pd["kick"]
		c.steer = steer
		c.handbrake = drift
		await runner.physics_frame
		max_drift = maxf(max_drift, absf(c.drift_angle) if c.speed > 3.0 else 0.0)
	return [Vector2(c.global_position.x - p0.x, c.global_position.z - p0.z).length(), max_drift]


func _launch(runner: SceneTree, c: Car, v: float) -> void:
	c.place(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), Vector3(0, 0, -v))
	for i in 20:
		c.throttle = 0.4
		await runner.physics_frame


func test_pad_zones(t) -> void:
	var hold := EmpireTouch.read_pad(Vector2.ZERO, K)
	t.near(float(hold["gas"]), EmpireTouch.HOLD_THROTTLE, 0.01, "hold = part throttle")
	t.check(not hold["kick"] and float(hold["brake"]) == 0.0, "hold: no kickdown, no brake")
	var up := EmpireTouch.read_pad(Vector2(0, -80), K)
	t.check(float(up["gas"]) == 1.0 and up["kick"], "slide up = full throttle + kickdown")
	var coast := EmpireTouch.read_pad(Vector2(0, 28), K)
	t.check(float(coast["gas"]) == 0.0 and float(coast["brake"]) == 0.0, "a little down = lift off (coast)")
	var light := EmpireTouch.read_pad(Vector2(0, 50), K)
	var hard := EmpireTouch.read_pad(Vector2(0, 112), K)
	t.check(float(light["brake"]) > 0.0 and float(light["brake"]) < 0.45, "a short pull brakes lightly (%.2f)" % light["brake"])
	t.near(float(hard["brake"]), 1.0, 0.01, "a full pull brakes fully")
	for x in [-112.0, -50.0, 50.0, 112.0]:
		t.check(EmpireTouch.read_pad(Vector2(x, 0), K) == hold, "sideways motion on the throttle pad keeps the same input")
		t.check(EmpireTouch.read_pad(Vector2(x, 112), K) == hard, "diagonal braking keeps the same input")
	t.check(EmpireTouch.verb("PARK & GET OUT") == "OUT" and EmpireTouch.verb("TO LET · £26/day") == "VIEW", "action button verbs")


func test_hold_vs_kickdown(t) -> void:
	var runner: SceneTree = t
	var g := _ground(runner)
	var c := _car(runner)
	await runner.physics_frame
	var a: Array = await _hold(runner, c, Vector2.ZERO, 4.0)
	var v_hold := c.speed
	c.place(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)))
	await runner.physics_frame
	var b: Array = await _hold(runner, c, Vector2(0, -90), 4.0)
	var v_kick := c.speed
	t.note("4 s: hold %.1f m/s (%.0f m), kickdown %.1f m/s (%.0f m)" % [v_hold, a[0], v_kick, b[0]])
	t.check(v_hold > 8.0, "holding the pad drives off (%.1f m/s)" % v_hold)
	t.check(v_kick > v_hold * 1.25, "kickdown pulls harder than holding")
	t.check(v_kick < float(c.spec["top_speed"]) + 0.5, "kickdown never passes top speed")
	c.queue_free()
	g.queue_free()


func test_brake_is_progressive_and_coast_is_gentle(t) -> void:
	var runner: SceneTree = t
	var g := _ground(runner)
	var c := _car(runner)
	await runner.physics_frame
	var dists := []
	for pull in [52.0, 112.0]:
		await _launch(runner, c, 20.0)
		var v0 := c.speed
		# (Until it stops: a full pull held at a standstill then reverses.)
		var p0 := c.global_position
		var secs := 0.0
		while c.speed > 0.4 and secs < 12.0:
			await _hold(runner, c, Vector2(0, pull), 0.1)
			secs += 0.1
		dists.append(Vector2(c.global_position.x - p0.x, c.global_position.z - p0.z).length())
		t.check(c.speed <= 0.4, "pull %d stops the car from %.0f m/s" % [int(pull), v0])
	t.note("stopping from 20 m/s: light %.1f m, full %.1f m" % dists)
	t.check(float(dists[0]) > float(dists[1]) * 1.6, "a light pull stops much further than a full one")
	t.check(float(dists[1]) < 30.0, "a full pull stops in a believable distance")
	await _launch(runner, c, 20.0)
	await _hold(runner, c, Vector2(9999, 9999), 0.0)
	c.throttle = 0.0
	c.brake = 0.0
	c.kickdown = false
	for i in 180:
		await runner.physics_frame
	t.note("coasting 3 s from 20 m/s: %.1f m/s" % c.speed)
	t.check(c.speed < 18.0 and c.speed > 8.0, "letting go coasts down (engine braking), not a stop")
	c.queue_free()
	g.queue_free()


func test_two_thumb_priority_and_power_slide(t) -> void:
	var runner: SceneTree = t
	var g := _ground(runner)
	var c := _car(runner)
	var input := DriveInput.new()
	runner.root.add_child(input)
	input.car = c
	input.enabled = false
	await runner.physics_frame
	await _launch(runner, c, 19.0)
	var yaw0 := c.global_basis.get_euler().y
	input.enabled = true
	input.touch_gas = EmpireTouch.HOLD_THROTTLE
	input.touch_pad_steer = EmpireTouch.read_pad_steer(18.0, K)
	for i in 30:
		await runner.physics_frame
	t.near(c.global_basis.get_euler().y, yaw0, 0.025, "vertical throttle tolerates sideways thumb jitter")
	input.touch_pad_steer = EmpireTouch.read_pad_steer(40.0, K)
	for i in 30:
		await runner.physics_frame
	t.check(c.steer > 0.02 and c.steer < 0.18 and c.power_slide == 0.0, "a small side pull steers without starting a slide")

	input.enabled = false
	await _launch(runner, c, 19.0)
	input.enabled = true
	input.touch_pad_steer = EmpireTouch.read_pad_steer(104.0, K)
	var max_slip := 0.0
	for i in 52:
		await runner.physics_frame
		max_slip = maxf(max_slip, absf(c.drift_angle))
	t.note("right-pad peak slip %.1f°" % rad_to_deg(max_slip))
	t.check(c.power_slide > 0.6 and max_slip > deg_to_rad(11.0) and max_slip < deg_to_rad(37.0),
		"deliberate right-thumb travel produces a controlled drift")
	t.check(not c.handbrake and c.throttle > 0.5, "right-thumb drifting preserves throttle and independent handbrake")

	input.touch_steer = -0.52
	for i in 4:
		await runner.physics_frame
	t.near(c.steer, -0.52, 0.01, "left countersteer has priority over a held right turn")
	t.near(c.power_slide, 0.0, 0.01, "left input takes the right pad out of drift mode")
	input.touch_steer = -0.09
	await runner.physics_frame
	await runner.physics_frame
	t.near(c.steer, -0.09, 0.01, "a small intentional left turn still has priority")
	input.touch_steer = 0.0
	input.touch_pad_steer = 0.0
	for i in 20:
		await runner.physics_frame
	t.near(c.steer, 0.0, 0.01, "releasing the right control returns steering to centre")
	t.near(c.power_slide, 0.0, 0.01, "releasing the right control restores rear grip")
	input.touch_handbrake = true
	await runner.physics_frame
	await runner.physics_frame
	t.check(c.handbrake, "the dedicated handbrake still works with its own input")
	input.queue_free()
	c.queue_free()
	g.queue_free()
