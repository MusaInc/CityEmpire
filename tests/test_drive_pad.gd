extends RefCounted
## The one-thumb drive pad (EmpireTouch.read_pad) on a real Car on flat
## ground: hold drives, slide up = full throttle + kickdown (quicker, not a
## boost past top speed), slide down = brake in proportion to the pull, let
## go = believable coasting, sideways = a drift only at speed, and nothing
## at parking speeds slides the car about.

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


## Drives the car with a pad offset for `secs` (the drift handbrake rule as
## EmpireTouch applies it). Returns [distance travelled, max |drift angle|].
func _hold(runner: SceneTree, c: Car, o: Vector2, secs: float) -> Array:
	var p0 := c.global_position
	var drifting := false
	var max_drift := 0.0
	for i in int(secs * 60.0):
		var pd := EmpireTouch.read_pad(o, K, absf(c.forward_speed), drifting)
		drifting = pd["drift"]
		c.throttle = pd["gas"]
		c.brake = pd["brake"]
		c.kickdown = pd["kick"]
		c.steer = pd["steer"]
		c.handbrake = bool(pd["drift"]) and absf(c.drift_angle) < deg_to_rad(20.0)
		await runner.physics_frame
		max_drift = maxf(max_drift, absf(c.drift_angle) if c.speed > 3.0 else 0.0)
	return [Vector2(c.global_position.x - p0.x, c.global_position.z - p0.z).length(), max_drift]


func _launch(runner: SceneTree, c: Car, v: float) -> void:
	c.place(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), Vector3(0, 0, -v))
	for i in 20:
		c.throttle = 0.4
		await runner.physics_frame


func test_pad_zones(t) -> void:
	var hold := EmpireTouch.read_pad(Vector2.ZERO, K, 10.0, false)
	t.near(float(hold["gas"]), EmpireTouch.HOLD_THROTTLE, 0.01, "hold = part throttle")
	t.check(not hold["kick"] and float(hold["brake"]) == 0.0, "hold: no kickdown, no brake")
	var up := EmpireTouch.read_pad(Vector2(0, -80), K, 10.0, false)
	t.check(float(up["gas"]) == 1.0 and up["kick"], "slide up = full throttle + kickdown")
	var coast := EmpireTouch.read_pad(Vector2(0, 28), K, 10.0, false)
	t.check(float(coast["gas"]) == 0.0 and float(coast["brake"]) == 0.0, "a little down = lift off (coast)")
	var light := EmpireTouch.read_pad(Vector2(0, 50), K, 10.0, false)
	var hard := EmpireTouch.read_pad(Vector2(0, 112), K, 10.0, false)
	t.check(float(light["brake"]) > 0.0 and float(light["brake"]) < 0.45, "a short pull brakes lightly (%.2f)" % light["brake"])
	t.near(float(hard["brake"]), 1.0, 0.01, "a full pull brakes fully")
	t.check(not EmpireTouch.read_pad(Vector2(100, 0), K, 5.0, false)["drift"], "no drift at parking speed")
	t.check(not EmpireTouch.read_pad(Vector2(40, 0), K, 20.0, false)["drift"], "steering on the pad never drifts by accident")
	t.check(EmpireTouch.read_pad(Vector2(100, 0), K, 20.0, false)["drift"], "a deliberate sideways slide drifts at speed")
	t.check(EmpireTouch.read_pad(Vector2(60, 0), K, 20.0, true)["drift"], "a drift holds while the thumb stays out (hysteresis)")
	t.check(not EmpireTouch.read_pad(Vector2(100, 112), K, 20.0, false)["drift"], "no drift while braking hard")
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


func test_drift_only_at_speed_and_controlled(t) -> void:
	var runner: SceneTree = t
	var g := _ground(runner)
	var c := _car(runner)
	await runner.physics_frame
	# Parking speed: full sideways on the pad just turns.
	c.place(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), Vector3(0, 0, -3.0))
	var slow: Array = await _hold(runner, c, Vector2(110, 30), 2.0)
	t.check(float(slow[1]) < deg_to_rad(8.0), "no slide at parking speed (%.1f°)" % rad_to_deg(slow[1]))
	# At speed: a sideways slide with throttle steps the rear out and holds
	# a controllable angle (no spin).
	await _launch(runner, c, 19.0)
	var yaw0 := c.global_basis.get_euler().y
	var fast: Array = await _hold(runner, c, Vector2(100, -10), 1.6)
	t.note("drift at 19 m/s: peak slip %.0f°" % rad_to_deg(fast[1]))
	t.check(float(fast[1]) > deg_to_rad(12.0), "sideways at speed drifts")
	t.check(float(fast[1]) < deg_to_rad(70.0), "the drift doesn't spin the car")
	# Thumb back to the middle: it straightens up.
	await _hold(runner, c, Vector2(0, 0), 2.0)
	t.check(absf(c.drift_angle) < deg_to_rad(10.0), "centring the thumb catches the slide (%.0f°)" % rad_to_deg(absf(c.drift_angle)))
	t.check(absf(wrapf(c.global_basis.get_euler().y - yaw0, -PI, PI)) > 0.3, "the drift turned the car")
	c.queue_free()
	g.queue_free()
