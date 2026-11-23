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
var prior_player := Vector3.ZERO
var elapsed := 0.0
var acting := false
var finish: Callable
var handle: Node3D
var craft_grip: Marker3D
var prior_camera := Transform3D.IDENTITY
var prior_fov := 70.0
var camera_to: Camera3D
var pinned := false
var _capsule := CapsuleShape3D.new()
var _last_clear_check := 0.0
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
		return {"edge": dims.x * 0.5 - 0.06, "hinge": hinge, "handle": pull,
			"seat": Vector3(dims.x * 0.23, float(hip[1]) + 0.20, float(hip[0])),
			"step": clampf(float(hip[1]), 0.37, 0.95), "swing": absf(float(hinge[0]) - float(pull[0])) + 0.15}
	var craft := body as Craft
	var dims: Vector3 = craft.spec["size"]
	var edge := dims.x * (0.47 if craft.kind == "boat" else (0.17 if craft.kind == "plane" else 0.34))
	edge = clampf(edge, 0.58, 2.65)
	var z := -dims.z * (0.22 if craft.kind != "boat" else 0.08)
	var step := clampf(dims.y * (0.32 if craft.kind == "boat" else 0.29), 0.42, 1.35)
	return {"edge": edge, "hinge": [z - 0.38, step + 0.32], "handle": [z, step + 0.40],
		"seat": Vector3(edge * 0.49, step + 0.28, z - 0.27), "step": step, "swing": 0.0}


func active() -> bool:
	return vehicle != null or acting


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
		(body as Car).freeze = true
	seat = profile["seat"]
	seat.x *= side
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
	game.rig.vehicle_pose = 0.0
	game.rig.show()
	game.camera.hide_body = false
	game.camera.cine = _camera
	game.camera.cam.make_current()
	game.world.set_viewer(game.camera)
	elapsed = 0.0
	_last_clear_check = 0.0
	if not board:
		game.player.global_position = vehicle.global_transform * seat
		game.rig.vehicle_pose = 1.0
	acting = true


func tick(dt: float) -> void:
	if not acting:
		return
	if not is_instance_valid(vehicle):
		_cancel()
		return
	var player := game.player
	if entering and not route.is_empty():
		var to := route[0]
		var before := player.global_position
		var next := before.move_toward(to, WALK_RATE * dt)
		if not _walk_clear(before, next, vehicle):
			_cancel()
			return
		player.global_position = next
		player.foot_velocity = (next - before) / maxf(dt, 0.001)
		player.s.velocity = player.foot_velocity
		player.controls.move = player.foot_velocity.normalized()
		if before.distance_to(to) < 0.045:
			route.pop_front()
		return

	elapsed += dt
	_last_clear_check -= dt
	if _last_clear_check <= 0.0:
		_last_clear_check = 0.1
		if not _clear(stand, vehicle):
			_cancel()
			return
	player.foot_velocity = Vector3.ZERO
	player.s.velocity = Vector3.ZERO
	player.controls.move = Vector3.ZERO
	var root := vehicle.global_transform
	var u := clampf(elapsed / 1.42, 0, 1)
	var door := smoothstep(0.10, 0.39, u) * (1.0 - smoothstep(0.76, 1.0, u))
	if vehicle is Car and (vehicle as Car).visual:
		handle = (vehicle as Car).visual.pose_access(side, door, profile)
	var board := smoothstep(0.35, 0.79, u) if entering else 1.0 - smoothstep(0.32, 0.74, u)
	var lift := sin(board * PI) * clampf(float(profile["step"]) * 0.37, 0.12, 0.37)
	var chair := root * seat
	player.global_position = stand.lerp(chair, board) + Vector3.UP * lift
	var inward := root.basis.x * -side
	var facing := inward.rotated(Vector3.UP, -side * PI * 0.5 * smoothstep(0.18, 0.89, board))
	game.rig.vehicle_facing = facing
	game.rig.vehicle_pose = maxf(0.001, smoothstep(0.09, 0.96, board))
	game.rig.vehicle_grip = handle
	var opening := smoothstep(0.02, 0.20, u) * (1.0 - smoothstep(0.38, 0.56, u))
	var closing := smoothstep(0.73, 0.84, u) * (1.0 - smoothstep(0.93, 1.0, u))
	game.rig.vehicle_grip_weight = maxf(opening, closing * 0.83) if vehicle is Car else sin(u * PI)
	if elapsed >= 1.42:
		var from := game.camera.cam.global_transform
		var fov := game.camera.cam.fov
		var done := finish
		_release()
		done.call(stand, from, fov)


func _camera(_dt: float) -> Array:
	if not is_instance_valid(vehicle):
		return [prior_camera, prior_fov]
	var p := game.player.global_position
	var car_basis := vehicle.global_basis
	var forward := -car_basis.z
	var sidewards := car_basis.x * side
	var focus := p + Vector3.UP * 0.26
	var eye := focus + sidewards * 2.9 - forward * 1.25 + Vector3.UP * 1.07
	var angle := Basis.looking_at(focus - eye, Vector3.UP)
	var near := Transform3D(angle, eye)
	var start_blend := smoothstep(0.0, 0.43, elapsed)
	var aimed := prior_camera.interpolate_with(near, start_blend)
	var fov := lerpf(prior_fov, 66.0, start_blend)
	if entering and is_instance_valid(camera_to):
		var end := smoothstep(0.89, 1.42, elapsed)
		aimed = aimed.interpolate_with(camera_to.global_transform, end)
		fov = lerpf(fov, camera_to.fov, end)
	var q := PhysicsRayQueryParameters3D.create(focus, aimed.origin, 1 | CityWorld.HUMAN_LAYER, [game.player.get_rid(), vehicle.get_rid()])
	var hit := game.player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		aimed.origin = (hit["position"] as Vector3).move_toward(focus, 0.29)
	return [aimed, fov]


func _release() -> void:
	if is_instance_valid(craft_grip):
		craft_grip.queue_free()
	craft_grip = null
	handle = null
	if is_instance_valid(vehicle) and vehicle is Car:
		var car := vehicle as Car
		if car.visual:
			car.visual.end_access()
		car.freeze = pinned
	acting = false
	vehicle = null
	game.rig.vehicle_pose = 0.0
	game.rig.vehicle_grip = null
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
