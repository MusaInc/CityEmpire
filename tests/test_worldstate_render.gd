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

func test_planter_trees_survive_low_quality_and_refresh(t) -> void:
	var world := CityWorld.new()
	var root := Node3D.new()
	var key := Vector2i.ZERO
	var first := Vector3(20, 0, 20)
	var second := Vector3(22, 0, 20)
	var verge := Vector3(23, 0, 20)
	world.prop_density = 0.5
	world._loaded[key] = root
	world._props_by_chunk[key] = []
	for p in [first, second, verge]:
		world._props_by_chunk[key].append(["tree", Transform3D(Basis.IDENTITY, p)])
	for p in [first, second]:
		world._planter_spots[CityWorld._tree_position_key(p)] = true
		world.prop_meshes["tree_" + TreeKit.pick(p)] = BoxMesh.new()
	t.check(world.chunk_props(key).size() == 2, "both planted trees survive and occupy the verge cell")
	world.refresh_props(key)
	world.broken[CityWorld.item_key(first)] = true
	world.refresh_props(key)
	var standing := world.chunk_props(key)
	t.check(standing.size() == 1 and standing[0][1].origin == second, "only the unbroken tree remains in the layout")
	var groups := root.get_children()
	t.check(groups.size() == 1 and groups[0].get_child_count() == 2, "refresh replaces earlier foliage batches")
	if groups.size() == 1 and groups[0].get_child_count() == 2:
		for lod: MultiMeshInstance3D in groups[0].get_children():
			t.check(lod.multimesh.instance_count == 1, "both LODs retain only the standing tree")
	root.free()
	world.free()

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


func test_traffic_stops_at_signal_and_moves_on_green(t) -> void:
	var traffic := Traffic.new()
	traffic.layout = CityLayout.new()
	var straight := PackedVector2Array([Vector2.ZERO, Vector2(90, 0)])
	var approach := traffic._add_lane(straight, false, 9.0, 0)
	var connector := traffic._add_lane(PackedVector2Array([Vector2(90, 0), Vector2(96, 0)]), false, 7.0, 1)
	var departure := traffic._add_lane(PackedVector2Array([Vector2(96, 0), Vector2(180, 0)]), false, 9.0, 2)
	traffic.l_ends[approach].append(connector)
	traffic.l_next[connector] = departure
	traffic.l_signals[approach] = 0.0
	traffic.c_lane.append(approach)
	traffic.l_cars[approach].append(0)
	traffic.c_s0.append(70.0)
	traffic.c_t0.append(0.0)
	traffic.c_v.append(9.0)
	traffic.c_stop.append(Traffic.NO_STOP)
	traffic.c_ease.append(Traffic.EASE)
	traffic.c_book.append(-1)
	traffic.c_wait.append(-1.0)
	traffic.c_ek.append(Traffic.EV_DECIDE)
	traffic.c_ev.append(0.0)
	traffic.c_xi.append(0)
	traffic.c_grp.append(-1)
	traffic.c_slot.append(-1)
	var saved_clock := Traffic.signal_time
	Traffic.signal_time = 14.0
	for i in 36:
		traffic.now += 0.1
		Traffic.signal_time += 0.1
		if traffic.c_ev[0] <= traffic.now:
			traffic._event(0)
	t.check(traffic.c_lane[0] == approach and traffic._at_rest(0), "red light queues the car before its connector")
	t.check(is_equal_approx(traffic.car_s(0, traffic.now), traffic.l_len[approach] - Traffic.STOP_MARGIN), "the vehicle stops before the junction")
	Traffic.signal_time = 0.0
	for i in 100:
		traffic.now += 0.1
		Traffic.signal_time += 0.1
		if traffic.c_ev[0] <= traffic.now:
			traffic._event(0)
	t.check(traffic.c_lane[0] == departure, "green releases the car onto the connecting street")
	Traffic.signal_time = saved_clock
	traffic.free()


func test_skyport_crossing_waits_for_approaching_traffic(t) -> void:
	var traffic := IslandTraffic.new()
	traffic.lanes = [{"pts": PackedVector3Array([Vector3.ZERO, Vector3(60, 0, 0)]),
		"cum": PackedFloat32Array([0.0, 60.0]), "len": 60.0}]
	var car := {"wait": 0.0, "lane": 0, "s": 12.0, "v": 10.0}
	traffic.cars = [car]
	var a := Vector2(30, -4)
	var b := Vector2(30, 4)
	t.check(traffic.crossing_blocked(a, b), "a moving car approaching the crossing makes the walker wait")
	car["s"] = 40.0
	t.check(not traffic.crossing_blocked(a, b), "the crossing is clear once the car has passed")
	traffic.blocker = Vector3(30, 0, 0)
	t.check(traffic.crossing_blocked(a, b), "the player's vehicle can occupy the crossing")
	traffic.free()


func test_through_signal_holds_a_queue_and_releases_in_order(t) -> void:
	var traffic := Traffic.new()
	traffic.layout = CityLayout.new()
	var lane := traffic._add_lane(PackedVector2Array([Vector2.ZERO, Vector2(180, 0)]), false, 9.0, 0)
	traffic.through_signals[lane] = [[96.0, 0.0]]
	traffic.c_lane = PackedInt32Array([lane, lane])
	traffic.l_cars[lane] = [1, 0]
	traffic.c_s0 = PackedFloat32Array([72.0, 56.0])
	traffic.c_t0 = PackedFloat32Array([0.0, 0.0])
	traffic.c_v = PackedFloat32Array([9.0, 9.0])
	traffic.c_stop = PackedFloat32Array([Traffic.NO_STOP, Traffic.NO_STOP])
	traffic.c_ease = PackedFloat32Array([Traffic.EASE, Traffic.EASE])
	traffic.c_ek = PackedInt32Array([0, 0])
	traffic.c_ev = PackedFloat32Array([0.0, 0.0])
	traffic.c_xi = PackedInt32Array([0, 0])
	traffic.c_book = PackedInt32Array([-1, -1])
	traffic.c_grp = PackedInt32Array([-1, -1])
	traffic.c_slot = PackedInt32Array([-1, -1])
	var saved := Traffic.signal_time
	Traffic.signal_time = 14.0
	for id in 2:
		traffic._reset_signal(id, traffic.c_s0[id])
		traffic._schedule(id)
	for step in 50:
		traffic.now += 0.1
		Traffic.signal_time += 0.1
		for id in 2:
			if traffic.c_ev[id] <= traffic.now:
				traffic._event(id)
	var front := traffic.car_s(0, traffic.now)
	var rear := traffic.car_s(1, traffic.now)
	t.check(traffic._at_rest(0) and traffic._at_rest(1), "both cars stop for red")
	t.check(is_equal_approx(front, 96.0 - Traffic.STOP_MARGIN) and front - rear >= Traffic.GAP - 0.01,
		"the front car stops before the junction and the follower preserves the gap")
	Traffic.signal_time = 0.0
	for step in 68:
		traffic.now += 0.1
		Traffic.signal_time += 0.1
		for id in 2:
			if traffic.c_ev[id] <= traffic.now:
				traffic._event(id)
	front = traffic.car_s(0, traffic.now)
	rear = traffic.car_s(1, traffic.now)
	t.check(front > rear and rear > 96.0 and traffic.c_lane[0] == lane and traffic.c_lane[1] == lane,
		"both resumed straight through on the same lane and preserved order")
	Traffic.signal_time = saved
	traffic.free()


func test_city_pedestrian_phase_and_vehicle_clearance(t) -> void:
	var traffic := Traffic.new()
	traffic.layout = CityLayout.new()
	var lane := traffic._add_lane(PackedVector2Array([Vector2.ZERO, Vector2(90, 0)]), false, 9.0, 0)
	var crossing := {"a": Vector3(36, 0, -6), "b": Vector3(36, 0, 6), "phase": 0.0, "lanes": {lane: 36.0}}
	var saved := Traffic.signal_time
	Traffic.signal_time = 2.0
	t.check(not traffic.pedestrian_crossing_clear(crossing, Vector3.INF), "a green light for the side street keeps pedestrians at the kerb")
	Traffic.signal_time = 16.0
	t.check(traffic.pedestrian_crossing_clear(crossing, Vector3.INF), "a clear crossing opens after vehicles have time to clear")
	t.check(not traffic.pedestrian_crossing_clear(crossing, Vector3(36, 0, 0)), "a player's car on the zebra keeps the crossing closed")
	traffic.l_cars[lane] = [0]
	traffic.c_lane = PackedInt32Array([lane])
	traffic.c_s0 = PackedFloat32Array([27.0])
	traffic.c_t0 = PackedFloat32Array([0.0])
	traffic.c_v = PackedFloat32Array([8.0])
	traffic.c_stop = PackedFloat32Array([Traffic.NO_STOP])
	traffic.c_ease = PackedFloat32Array([Traffic.EASE])
	t.check(not traffic.pedestrian_crossing_clear(crossing, Vector3.INF), "a vehicle still approaching the zebra keeps the crossing closed")
	traffic.c_s0[0] = 43.0
	t.check(traffic.pedestrian_crossing_clear(crossing, Vector3.INF), "the pedestrian can start once the vehicle has passed")
	Traffic.signal_time = 24.0
	t.check(not traffic.pedestrian_crossing_clear(crossing, Vector3.INF), "pedestrians cannot start a crossing near the end of red")
	Traffic.signal_time = saved
	traffic.free()


func test_tyre_spray_needs_moving_wheel_on_wet_pavement(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var scene := Node3D.new()
	tree.root.add_child(scene)
	var fx := VehicleFx.new()
	scene.add_child(fx)
	fx.set_process(false)
	var car := Car.new()
	car.process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(car)
	var paved := func(_point: Vector3) -> bool: return true
	var off_road := func(_point: Vector3) -> bool: return false
	fx.wet_tyre_spray(car, 0.9, 0.2, paved)
	t.check(fx.smoke.next == 0, "a stationary airborne car emits no spray")

	car.linear_velocity = Vector3(0, 0, -22)
	car.wheels_on_ground = 1
	car._hit[2] = true
	car._contact[2] = Vector3(-0.8, 0, 1.5)
	fx.wet_tyre_spray(car, 0.02, 0.2, paved)
	t.check(fx.smoke.next == 0, "a dry road emits no spray")
	fx.wet_tyre_spray(car, 0.9, 0.2, off_road)
	t.check(fx.smoke.next == 0, "wet grass emits no road spray")

	fx.wet_tyre_spray(car, 0.02, 1.0 / 60.0, paved)
	fx.wet_tyre_spray(car, 0.9, 1.0 / 60.0, paved)
	t.check(fx.smoke.next == 2, "one grounded rear wheel produces its own mist and drops")
	t.check(fx.smoke.pos[0].x < -0.8 and fx.smoke.pos[0].z >= car._contact[2].z,
		"spray starts outside the grounded tyre")
	car.in_water = true
	fx.wet_tyre_spray(car, 0.9, 0.2, paved)
	t.check(fx.smoke.next == 2, "submerged wheels emit no road spray")
	scene.free()


func test_storefront_panes_fit_between_mullions(t) -> void:
	var room := ShopInterior.new()
	var frame := ShopInterior._Batch.new()
	room._glazed_bays(frame, Vector2(0.0, 5.4), Vector2(0.55, 3.0), 0.12,
		0.043, 1.9, Color.DIM_GRAY, Color(0.7, 0.8, 0.9, 0.16))
	var glass := room._glass.commit()
	var vertices: PackedVector3Array = glass.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	t.check(vertices.size() == 18, "three panes use one plane each")
	for v: Vector3 in vertices:
		var left_edge := floorf(v.x / 1.8) * 1.8
		t.check(v.x >= left_edge + 0.044 and v.x <= left_edge + 1.8 - 0.044,
			"glass finishes inside its mullions")
		t.check(v.y > 0.55 and v.y < 3.0 and is_equal_approx(v.z, -0.12),
			"pane stays behind the frame and between the sill and head")
	room.free()


func test_facade_fittings_use_whole_window_bays(t) -> void:
	for style in range(8):
		var width := 19.96
		var seed := 0.4173
		var bay := BuildingMesher.facade_bays(style, width, seed)
		t.near(bay.x * 2.0 + bay.y * bay.z, width, 0.001, "whole bays fit the façade and its corner piers")
		var storey := BuildingMesher.facade_storey(style, seed)
		var band := BuildingMesher._window_band(storey * 0.46, storey * 4.48, 0.0, style, seed)
		t.near(band.x, storey, 0.001, "solid belt covers the partial row at a setback")
		t.near(band.y, storey * 4.0, 0.001, "solid belt covers the partial row below a cornice")
