extends RefCounted
## Focused regressions for streaming handoffs and collision source ownership.

class FlatWorld extends CityWorld:
	func _walk_lift(_p: Vector3) -> float:
		return 0.15

class TestGame extends EmpireGame:
	var test_car: Car
	func vehicle_node() -> Node3D:
		return test_car

class TestTraffic extends Traffic:
	var at := Vector3.ZERO
	func car_count() -> int:
		return 1
	func car_position(_id: int) -> Vector3:
		return at
	func car_s(_id: int, _time: float) -> float:
		return 0.0
	func lane_point(_lane: int, _s: float) -> Vector3:
		return at
	func lane_dir(_lane: int, _s: float) -> Vector3:
		return Vector3.FORWARD
	func yield_to(_p: Vector3, _ids: Array) -> void:
		pass

func test_far_upload_is_bounded_and_finish_drains(t) -> void:
	var w := CityWorld.new()
	var far := FarCity.new()
	far.world = w
	var mesh := BoxMesh.new()
	for i in 7:
		far._keys.append(Vector2i(i, 0))
		far._arrays.append({"low": mesh.get_mesh_arrays(), "ground": null})
	far._instantiate()
	t.check(far._nodes.size() > 0 and far._nodes.size() <= FarCity.UPLOADS_PER_FRAME, "far uploads bounded per frame")
	t.check(not far.ready_now(), "partially uploaded city is not ready")
	far.finish()
	t.check(far.ready_now() and far._nodes.size() == 7 and far._arrays.is_empty(), "finish drains and releases arrays")
	far.finish()
	t.check(far._nodes.size() == 7, "finish is idempotent")
	far.free()
	w.free()

func test_walker_worker_matches_main_thread(t) -> void:
	var w := FlatWorld.new()
	w.walker_meshes = [BoxMesh.new()]
	w._walk_paths = [[Vector3(10, 0, 10), Vector3(160, 0, 10)], [Vector3(500, 0, 10), Vector3(600, 0, 10)]]
	var expected := w._walker_buffers(Vector2i.ZERO)
	var result := [[]]
	var task := WorkerThreadPool.add_task(func(): result[0] = w._walker_buffers(Vector2i.ZERO))
	WorkerThreadPool.wait_for_task_completion(task)
	t.check(expected == result[0] and not expected[0].is_empty(), "seeded placement is identical on worker")
	var root := Node3D.new()
	w._add_walkers(root, Vector2i.ZERO, expected)
	t.check(root.get_child(0).multimesh.instance_count == expected[0].size() / 20, "all generated walkers reach instancing")
	root.free()
	w.free()

func test_westbank_collision_and_drop_are_source_specific(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var g := TestGame.new()
	g.world = CityWorld.new()
	g.world.mainland = CityWorld.new()
	var east := TestTraffic.new()
	var west := TestTraffic.new()
	east.at = Vector3(10, 0, 0)
	west.at = Vector3(-10, 0, 0)
	east.c_lane = PackedInt32Array([0])
	west.c_lane = PackedInt32Array([0])
	g.world.traffic = east
	g.world.mainland.traffic = west
	g.test_car = Car.new()
	g.test_car.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(g.test_car)
	var bodies := TrafficBodies.new()
	tree.root.add_child(bodies)
	bodies.setup(g)
	bodies.set_physics_process(false)
	bodies._physics_process(0.25)
	t.check(bodies.city_cars().size() == 2, "both cities receive pooled collision bodies")
	bodies.drop(0, west)
	var remaining := bodies.city_cars()
	t.check(remaining.size() == 1 and remaining[0][2] == east, "same numeric id on the other island is untouched")
	bodies.free()
	g.test_car.free()
	east.free()
	west.free()
	g.world.mainland.free()
	g.world.free()
	g.free()

func test_occluder_does_not_fill_elevated_or_shaped_space(t) -> void:
	var w := CityWorld.new()
	var b := {"kind": "normal", "tiers": [[0.0, 0.0, 20.0, 20.0, 30.0, 70.0]], "rot": 0.0}
	w._by_chunk[Vector2i.ZERO] = [b]
	var root := Node3D.new()
	w._add_occluder(root, Vector2i.ZERO)
	var occ: ArrayOccluder3D = root.get_child(0).occluder
	for v in occ.vertices:
		t.check(v.y >= 30.5, "occluder stays inside raised building")
	root.free()
	root = Node3D.new()
	b["shape"] = {"segs": 12}
	w._add_occluder(root, Vector2i.ZERO)
	t.check(root.get_child_count() == 0, "box occluder cannot fill a round facade's cutouts")
	root.free()
	w.free()

class ParkedWorld extends CityWorld:
	var generations := 0
	func _generate_parked_cars(_key: Vector2i) -> Array:
		generations += 1
		return [[Transform3D(Basis.IDENTITY, Vector3(10, 0, 10)), 0]]

func test_parked_cache_survives_wreck_removal_and_restore(t) -> void:
	var w := ParkedWorld.new()
	var first := w.parked_cars(Vector2i.ZERO)
	first.clear()
	t.check(w.parked_cars(Vector2i.ZERO).size() == 1 and w.generations == 1, "caller cannot mutate cached layout")
	var key := CityWorld.item_key(Vector3(10, 0, 10))
	w.broken[key] = true
	t.check(w.parked_cars(Vector2i.ZERO).is_empty(), "wrecked parked car stays hidden")
	w.broken.erase(key)
	t.check(w.parked_cars(Vector2i.ZERO).size() == 1 and w.generations == 1, "restoring a car needs no regeneration")
	w.free()

func test_chase_camera_respects_close_wall(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var scene := Node3D.new()
	tree.root.add_child(scene)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 10, 0.2)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	wall.position = Vector3(0, 2, 0.7)
	var car := Car.new()
	car.process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(car)
	var camera := ChaseCamera.new()
	scene.add_child(camera)
	camera.set_physics_process(false)
	camera.target = car
	await tree.physics_frame
	await tree.physics_frame
	camera._chase(1.0 / 60.0)
	t.check(camera.global_position.z < 0.35, "camera stays before close wall instead of forcing a 15% minimum")
	scene.free()

func test_resolution_governor_discards_resume_interval(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var gov := FrameGovernor.new()
	tree.root.add_child(gov)
	gov.set_process(false)
	gov._acc = 0.49
	gov._frames = 15
	gov._since_change = 10.0
	gov._headroom_time = 3.5
	var scale := gov.scale
	gov._last_us = Time.get_ticks_usec() - 2000000
	gov._process(1.0 / 30.0)
	t.check(gov.scale == scale and gov._acc == 0.0 and gov._frames == 0, "resume gap cannot trigger downscale")
	t.check(gov._headroom_time == 0.0, "resume cannot reuse pre-pause headroom")
	gov.free()
