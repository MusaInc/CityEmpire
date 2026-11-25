class_name VehicleAccess
extends RefCounted
## Shared boarding and dismount for road vehicles, aircraft and boats.
## The player stays outside collision during the cabin portion only. The
## approach, door sweep and landing space are picked from live physics.

const WALK_RATE := 2.15
const STAND_HEIGHT := 0.90
const BLOCK_MASK := 1 | (1 << 1) | (1 << 2) | (1 << 3) | CityWorld.HUMAN_LAYER | (1 << 6) | CityWorld.PROPS_LAYER

var game: EmpireGame
var vehicle: PhysicsBody3D
var entering := true
var side := 1.0
var profile := {}
var route: Array[Vector3] = []
var stand := Vector3.ZERO
var seat := Vector3.ZERO
var entry_seat := Vector3.ZERO
var driver_seat := Vector3.ZERO
var prior_player := Vector3.ZERO
var elapsed := 0.0
var acting := false
var finish: Callable
var handle: Node3D
var craft_grip: Marker3D
var interior_grip: Marker3D
var prior_camera := Transform3D.IDENTITY
var prior_fov := 70.0
var camera_to: Camera3D
var pinned := false
var _capsule := CapsuleShape3D.new()
var _last_clear_check := 0.0
var _walk_speed := 0.0
var _duration := 1.42
var _cross_cabin := false
var _door_opened_sfx := false
var _door_closed_sfx := false
static var _profiles := {}


func _init(host: EmpireGame) -> void:
	game = host
	_capsule.radius = 0.35
	_capsule.height = 1.72


static func geometry(body: PhysicsBody3D) -> Dictionary:
	if _profiles.is_empty():
		_profiles = EmpireData.file("vehicle_entries")
	if body is Car:
		var car := body as Car
		var dims: Vector3 = car.spec["size"]
		var authored: Dictionary = _profiles.get(car.spec["body"], {})
		var hinge: Array = authored.get("hinge", [-dims.z * 0.20, dims.y * 0.51])
		var pull: Array = authored.get("handle", [-dims.z * 0.02, dims.y * 0.54])
		var hip: Array = authored.get("seat", [-dims.z * 0.11, dims.y * 0.36])
		var driver_side: float = float(authored.get("driver_side", 1.0))
		var seat_x: float = float(authored.get("seat_x", minf(dims.x * 0.23, dims.x * 0.5 - 0.42)))
		var sill_y: float = float(authored.get("sill_y", maxf(float(hip[1]) - 0.16, 0.28)))
		var int_pull: Array = authored.get("interior_pull", [lerpf(float(hinge[0]), float(pull[0]), 0.58), float(pull[1]) - 0.06])
		var wh: Array = authored.get("wheel", [0.0, 0.02, -0.44])
		# The profile names the seated pelvis. The rig's pelvis is 8 cm
		# above the player's root, so use that same offset in both transitions.
		var roof: Array = authored.get("roof_samples", [dims.y])
		var roof_y := minf(float(roof[0]), float(roof[mini(2, roof.size() - 1)]))
		var low := 1.0 - smoothstep(0.53, 0.83, roof_y - float(hip[1]))
		var seat_y := float(hip[1]) - CharacterRig.PELVIS_ABOVE_PLAYER_ROOT - 0.09 * low
		var wheel := Vector3(float(wh[0]), float(wh[1]) + 0.09 * low, float(wh[2]))
		var ankle_y := maxf(sill_y - 0.10, 0.20) + CharacterRig.ANKLE_H - seat_y
		return {"edge": dims.x * 0.5 - 0.06, "hinge": hinge, "handle": pull, "interior_pull": int_pull,
			"seat": Vector3(seat_x * driver_side, seat_y, float(hip[0])),
			"wheel": wheel, "roof_room": roof_y - seat_y - 0.065,
			"ankle": Vector3(0.0, ankle_y, wheel.z - 0.17 - 0.12 * low),
			"seat_x": seat_x, "driver_side": driver_side, "sill_y": sill_y,
			"step": clampf(float(hip[1]), 0.37, 0.95), "swing": absf(float(hinge[0]) - float(pull[0])) + 0.15}
	var craft := body as Craft
	var dims: Vector3 = craft.spec["size"]
	var edge := dims.x * (0.47 if craft.kind == "boat" else (0.17 if craft.kind == "plane" else 0.34))
	edge = clampf(edge, 0.58, 2.65)
	var z := -dims.z * (0.22 if craft.kind != "boat" else 0.08)
	var step := clampf(dims.y * (0.32 if craft.kind == "boat" else 0.29), 0.42, 1.35)
	return {"edge": edge, "hinge": [z - 0.38, step + 0.32], "handle": [z, step + 0.40],
		"interior_pull": [z - 0.12, step + 0.36],
		"seat": Vector3(edge * 0.49, step + 0.28, z - 0.27), "seat_x": edge * 0.49, "driver_side": 0.0, "sill_y": step,
		"step": step, "swing": 0.0}


func active() -> bool:
	return vehicle != null or acting


func _ground_y(at: Vector3, body: PhysicsBody3D) -> float:
	var exclude: Array[RID] = [game.player.get_rid(), body.get_rid()]
	var space := game.player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.85, at + Vector3.DOWN * 1.45,
		1 | (1 << 3), exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.72:
		return INF
	return (hit["position"] as Vector3).y


func _support(at: Vector3, body: PhysicsBody3D) -> Vector3:
	var exclude: Array[RID] = [game.player.get_rid(), body.get_rid()]
	var space := game.player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.22, at + Vector3.DOWN * 2.0,
		1 | (1 << 3), exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.72:
		return Vector3.INF
	var floor: Vector3 = hit["position"]
	if floor.y < Craft.SEA_Y + 0.15 or (floor.y < Craft.SEA_Y + 1.0 and game.layout.is_water(floor)):
		return Vector3.INF
	var centre := floor + Vector3.UP * STAND_HEIGHT
	return centre if _clear(centre, body) else Vector3.INF


func _clear(at: Vector3, body: PhysicsBody3D) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _capsule
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = BLOCK_MASK
	q.exclude = [game.player.get_rid(), body.get_rid()]
	return game.player.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _walk_clear(a: Vector3, b: Vector3, boarding: PhysicsBody3D) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _capsule
	q.transform = Transform3D(Basis.IDENTITY, a + Vector3.UP * 0.18)
	q.motion = b - a
	q.collision_mask = BLOCK_MASK
	q.exclude = [game.player.get_rid()]
	# The plane's collision box includes the wings near the boarding point.
	if boarding is Craft and (boarding as Craft).kind == "plane":
		q.exclude.append(boarding.get_rid())
	var fraction := game.player.get_world_3d().direct_space_state.cast_motion(q)
	return fraction.size() == 2 and fraction[0] >= 0.995


func landing(body: PhysicsBody3D, board: bool, dock := Vector3.INF) -> Dictionary:
	var p := geometry(body)
	var root := body.global_transform
	var here := root.affine_inverse() * game.player.global_position
	var preferred := -1.0 if board and here.x < -0.2 else 1.0
	var door_z := float(p["handle"][0])
	var width := float(p["edge"])
	var points: Array[Vector3] = []
	for candidate_side: float in [preferred, -preferred]:
		for offset: float in [0.0, 0.40, -0.35]:
			var foot := _support(root * Vector3(candidate_side * (width + 0.66), 0, door_z + offset), body)
			if foot == Vector3.INF and dock != Vector3.INF and Vector2(root.origin.x, root.origin.z).distance_to(Vector2(dock.x, dock.z)) < 4.8 \
					and (root.affine_inverse() * dock).x * candidate_side > 0.0:
				foot = _support(dock, body)
			if foot == Vector3.INF:
				continue
			# Allow the door to swing only if the leaf and the player have room.
			var sweep := root * Vector3(candidate_side * (width + float(p["swing"]) * 0.67), 0.23, door_z - 0.25)
			sweep.y = foot.y
			if body is Car and not _clear(sweep, body):
				continue
			points.clear()
			if board:
				var start := game.player.global_position
				if absf(start.y - foot.y) > 0.55 or start.distance_to(foot) > 5.3:
					continue
				if not _walk_clear(start, foot, body):
					var car_length: float = float((body as Car).spec["size"].z) if body is Car else 0.0
					if car_length <= 0.0:
						continue
					var end_z := (float(car_length) * 0.5 + 0.69) * (-1.0 if here.z < 0.0 else 1.0)
					var a := _support(root * Vector3(signf(here.x) * (width + 0.67), 0, end_z), body)
					var b := _support(root * Vector3(candidate_side * (width + 0.67), 0, end_z), body)
					if a == Vector3.INF or b == Vector3.INF or not _walk_clear(start, a, body) \
							or not _walk_clear(a, b, body) or not _walk_clear(b, foot, body):
						continue
					points.assign([a, b])
				points.append(foot)
			return {"pos": foot, "side": candidate_side, "route": points.duplicate()}
	return {}


func start(body: PhysicsBody3D, board: bool, found: Dictionary, done: Callable, native: Camera3D = null) -> void:
	vehicle = body
	entering = board
	profile = geometry(body)
	stand = found["pos"]
	side = found["side"]
	route.assign(found["route"])
	finish = done
	camera_to = native
	prior_player = game.player.global_position
	var current := game.get_viewport().get_camera_3d()
	prior_camera = current.global_transform
	prior_fov = current.fov
	pinned = body is Car and (body as Car).freeze
	if body is Car:
		var car := body as Car
		car.freeze = true
		car.throttle = 0.0
		car.brake = 1.0
		game.drive_input.enabled = false
	var base_seat: Vector3 = profile["seat"]
	var seat_x: float = absf(float(profile.get("seat_x", base_seat.x)))
	if body is Car:
		var ds: float = float(profile.get("driver_side", 1.0))
		driver_seat = Vector3(seat_x * ds, base_seat.y, base_seat.z)
		entry_seat = Vector3(seat_x * side, base_seat.y, base_seat.z)
		_cross_cabin = signf(side) != signf(ds)
	else:
		entry_seat = Vector3(seat_x * side, base_seat.y, base_seat.z)
		driver_seat = entry_seat
		_cross_cabin = false
	seat = driver_seat
	_duration = 0.62 if body is Car else 0.72
	_walk_speed = clampf(Vector2(game.player.s.velocity.x, game.player.s.velocity.z).length(), 0.45, WALK_RATE)
	if body is Craft:
		craft_grip = Marker3D.new()
		var grip: Array = profile["handle"]
		craft_grip.position = Vector3(side * float(profile["edge"]), float(grip[1]), float(grip[0]))
		body.add_child(craft_grip)
		handle = craft_grip
	game.player.process_mode = Node.PROCESS_MODE_INHERIT
	game.player.scripted = true
	game.player.visible = true
	game.player.input_enabled = false
	game.player.collision_layer = 0
	game.player.s.velocity = Vector3.ZERO
	game.player.foot_velocity = Vector3.ZERO
	game.rig.vehicle_seated = false
	game.rig.process_mode = Node.PROCESS_MODE_INHERIT
	game.rig.vehicle_pose = 0.0
	game.rig.vehicle_entry_side = side
	game.rig.vehicle_roof_room = float(profile.get("roof_room", INF))
	game.rig.vehicle_ankle_offset = profile.get("ankle", Vector3.ZERO)
	game.rig.vehicle_grip = null
	game.rig.vehicle_grip_weight = 0.0
	game.rig.show()
	game.camera.hide_body = false
	game.camera.cine = _camera
	game.camera.cam.make_current()
	game.world.set_viewer(game.camera)
	elapsed = 0.0
	_last_clear_check = 0.0
	_door_opened_sfx = false
	_door_closed_sfx = false
	game.rig.vehicle_pose = 0.0
	if not board:
		var root := vehicle.global_transform
		game.player.global_position = root * driver_seat
		game.player.visible = false
	acting = true


## One quick, universal transition for every vehicle (cars, boats, planes,
## helicopters; vehicle interaction pass 2026-11-25 – the 1.5–1.7 s
## full-body boarding animation is gone). Entering, ~0.6 s: the door opens
## with its sound, the hero glides to it on their normal walk cycle (round
## the car's end if that's the clear side), slips in as the camera eases
## straight into the driving view, the door shuts. Leaving: the door opens,
## the hero is placed standing beside it on solid ground facing the way the
## car points, takes a step clear, the door shuts and the walking camera
## takes over from where the transition camera is – no snap, no clipping,
## no floating (every point is a ground probe from landing()).
func tick(dt: float) -> void:
	if not acting:
		return
	if not is_instance_valid(vehicle):
		_cancel()
		return
	var player := game.player
	elapsed += dt
	var u := clampf(elapsed / _duration, 0.0, 1.0)
	var root := vehicle.global_transform
	var door := 0.0
	var prev := player.global_position
	if entering:
		door = smoothstep(0.0, 0.3, u) * (1.0 - smoothstep(0.64, 0.96, u))
		var glide := smoothstep(0.0, 0.46, u)
		var pos := _path_at(glide)
		var inside := smoothstep(0.42, 0.6, u)
		pos = pos.lerp(root * entry_seat, inside)
		player.global_position = pos
		var vel := (pos - prev) / maxf(dt, 0.001)
		vel.y = 0.0
		player.foot_velocity = vel if inside < 0.5 else Vector3.ZERO
		player.s.velocity = player.foot_velocity
		player.controls.move = vel.normalized() if vel.length() > 0.3 and inside < 0.5 else Vector3.ZERO
		if vel.length() > 0.3 and inside < 0.5:
			game.rig.set_facing(vel.normalized())
		# In through the door, then out of sight (a car with a see-through
		# cabin shows its driver once the entry finishes).
		player.visible = u < 0.52
	else:
		door = smoothstep(0.0, 0.26, u) * (1.0 - smoothstep(0.52, 0.92, u))
		var out := root.basis.x * side
		out.y = 0.0
		out = out.normalized()
		if u >= 0.24:
			var step := smoothstep(0.24, 0.62, u)
			var pos2 := stand - out * 0.32 * (1.0 - step)
			var gy := _ground_y(pos2, vehicle)
			if gy < INF:
				pos2.y = gy + STAND_HEIGHT
			player.global_position = pos2
			var fwd := -root.basis.z
			fwd.y = 0.0
			var face := out.lerp(fwd.normalized(), step).normalized()
			game.rig.set_facing(face)
			var vel2 := (pos2 - prev) / maxf(dt, 0.001) if player.visible else Vector3.ZERO
			vel2.y = 0.0
			player.foot_velocity = vel2
			player.s.velocity = vel2
			player.controls.move = vel2.normalized() if vel2.length() > 0.2 else Vector3.ZERO
			player.visible = true
		else:
			player.visible = false
			player.global_position = root * driver_seat
	if vehicle is Car and (vehicle as Car).visual:
		handle = (vehicle as Car).visual.pose_access(side, door, profile)
		if not _door_opened_sfx and door > 0.12:
			_door_opened_sfx = true
			if game.car_audio and game.car_audio.has_method("play_door"):
				game.car_audio.call("play_door", true)
		elif _door_opened_sfx and not _door_closed_sfx and door < 0.1 and u > 0.6:
			_door_closed_sfx = true
			if game.car_audio and game.car_audio.has_method("play_door"):
				game.car_audio.call("play_door", false)
	elif vehicle is Craft and not _door_opened_sfx and u > 0.1:
		_door_opened_sfx = true
		Sfx.play("click", -9.0, 0.8)
	if elapsed >= _duration:
		var from := game.camera.cam.global_transform
		var fov := game.camera.cam.fov
		var done := finish
		_release()
		done.call(stand, from, fov)


## The glide from where the hero stood, round the car if needed, to the door.
func _path_at(t: float) -> Vector3:
	var pts: Array[Vector3] = [prior_player]
	pts.append_array(route)
	if pts[pts.size() - 1].distance_to(stand) > 0.05:
		pts.append(stand)
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	if total < 0.01:
		return stand
	var want := t * total
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if want <= seg:
			return pts[i].lerp(pts[i + 1], want / maxf(seg, 0.001))
		want -= seg
	return pts[pts.size() - 1]


func _camera(_dt: float) -> Array:
	if not is_instance_valid(vehicle):
		return [prior_camera, prior_fov]
	var u := clampf(elapsed / _duration, 0.0, 1.0)
	var k := u * u * u * (u * (u * 6.0 - 15.0) + 10.0)   # smootherstep
	var target := prior_camera
	var tfov := prior_fov
	if entering and is_instance_valid(camera_to):
		target = camera_to.global_transform
		tfov = camera_to.fov
	elif not entering:
		# Where the walking camera will sit: behind the hero, looking the way
		# the car points (EmpireGame._finish_on_foot faces it along the car).
		var fwd := -vehicle.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var focus := stand + Vector3.UP * 0.55 + fwd * 1.5
		var eye := stand - fwd * 3.4 + Vector3.UP * 1.25
		target = Transform3D(Basis.looking_at(focus - eye, Vector3.UP), eye)
		tfov = 70.0
	var aimed := prior_camera.interpolate_with(target, k)
	var fov := lerpf(prior_fov, tfov, k)
	var focus2 := game.player.global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(focus2, aimed.origin, 1 | CityWorld.HUMAN_LAYER, [game.player.get_rid(), vehicle.get_rid()])
	var hit := game.player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		aimed.origin = (hit["position"] as Vector3).move_toward(focus2, 0.29)
	return [aimed, fov]


func _release() -> void:
	if is_instance_valid(craft_grip):
		craft_grip.queue_free()
	craft_grip = null
	if is_instance_valid(interior_grip):
		interior_grip.queue_free()
	interior_grip = null
	handle = null
	if is_instance_valid(vehicle) and vehicle is Car:
		var car := vehicle as Car
		if car.visual:
			car.visual.end_access()
		car.freeze = pinned
	acting = false
	vehicle = null
	camera_to = null
	finish = Callable()
	_walk_speed = 0.0
	_cross_cabin = false
	game.rig.vehicle_pose = 0.0
	game.rig.vehicle_entry_side = 0.0
	game.rig.vehicle_grip = null
	game.rig.vehicle_grip_weight = 0.0
	game.camera.cine = Callable()
	game.player.scripted = false


func _cancel(show_message := true) -> void:
	var was_entering := entering
	_release()
	if was_entering:
		game.player.respawn(prior_player)
		game.player.collision_layer = 1 << 2
		game.player.input_enabled = true
		game.camera.snap()
	else:
		game.restore_vehicle_view()
	if show_message:
		game.ui.toast("Vehicle access is blocked", "warn")


func interrupt() -> void:
	if active():
		_cancel(false)
