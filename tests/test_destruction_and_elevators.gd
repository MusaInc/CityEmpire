extends Node
## Automated verification for the vehicle destruction refinement pass
## and the elevator overhaul (apartments, hotels, offices, HQ, garage).


func test_detached_panels_recentered_and_internals_anchored(t) -> void:
	var host := Node3D.new()
	add_child(host)
	var spec := CarCatalog.spec("kestrel")
	var car := Car.new()
	car.setup(spec)
	host.add_child(car)
	var vis := CarVisual.new()
	car.add_child(vis)
	vis.setup(car)
	car.visual = vis
	var body_aabb := vis.body.mesh.get_aabb()

	# Detach front bumper, hood, and left door.
	CarVisual._debris.clear()
	vis.detach("bumper_f", car.global_position + Vector3(0, 0.4, -2.0), Vector3.FORWARD)
	vis.detach("hood", car.global_position + Vector3(0, 0.9, -1.5), Vector3.UP)
	vis.detach("door_l", car.global_position + Vector3(-0.9, 0.7, 0.0), Vector3.LEFT)

	# 1. No legacy floating Frame_* ghost shells; solid Internals_* anchored inside body AABB.
	var has_old_frame := false
	var internals_count := 0
	for ch in vis.get_children():
		if String(ch.name).begins_with("Frame_"):
			has_old_frame = true
		if String(ch.name).begins_with("Internals_"):
			internals_count += 1
			for sub in ch.get_children():
				if sub is MeshInstance3D:
					var iaabb := (sub as MeshInstance3D).mesh.get_aabb()
					var expanded := body_aabb.grow(0.15)
					t.check(expanded.encloses(iaabb), "%s fits inside vehicle chassis bounds" % ch.name)
	t.check(not has_old_frame, "no floating normal-offset Frame_* ghost shells")
	t.check(internals_count == 3, "exposed internal components spawned for all 3 detached parts (%d)" % internals_count)

	# 2. Detaching left door shattered left side glass so no floating window remains.
	t.check(float(car.glass.get("left", 0.0)) >= 1.0, "left door detachment shatters left window glass")

	# 3. Every detached debris RigidBody3D has a recentered mesh (pivot at true centroid) and tight collider.
	t.check(CarVisual._debris.size() == 3, "3 detached debris panels spawned (%d)" % CarVisual._debris.size())
	for d: Dictionary in CarVisual._debris:
		var rb := d["body"] as RigidBody3D
		t.check(rb != null and is_instance_valid(rb), "debris body is valid")
		var mi: MeshInstance3D = null
		var cs: CollisionShape3D = null
		for ch in rb.get_children():
			if ch is MeshInstance3D:
				mi = ch
			elif ch is CollisionShape3D:
				cs = ch
		t.check(mi != null and cs != null, "debris has mesh and collider")
		if mi and mi.mesh:
			var c := mi.mesh.get_aabb().get_center()
			t.check(c.length() < 0.06, "%s mesh is recentered at centroid (offset %.3f)" % [rb.name, c.length()])
		if cs and cs.shape is BoxShape3D:
			var bsz := (cs.shape as BoxShape3D).size
			t.check(bsz.x > 0.05 and bsz.y > 0.05 and bsz.z > 0.05, "%s collider has valid extents" % rb.name)

	# 4. Settled debris freezes to 0 physics CPU.
	for d: Dictionary in CarVisual._debris:
		var rb := d["body"] as RigidBody3D
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	CarVisual._debris_frame = -1
	CarVisual._tick_debris(0.7, null)
	var all_frozen := true
	for d: Dictionary in CarVisual._debris:
		var rb := d["body"] as RigidBody3D
		if not rb.freeze or rb.collision_layer != 0:
			all_frozen = false
	t.check(all_frozen, "settled debris panels freeze and disable collision to save iOS physics CPU")

	# Clean up debris and host.
	for d: Dictionary in CarVisual._debris:
		if is_instance_valid(d["body"]):
			(d["body"] as Node).queue_free()
	CarVisual._debris.clear()
	host.queue_free()
	await get_tree().process_frame


func test_crumpling_stiffness_and_normal_recompute(t) -> void:
	var host := Node3D.new()
	add_child(host)
	var spec := CarCatalog.spec("kestrel")
	var car := Car.new()
	car.setup(spec)
	host.add_child(car)
	var vis := CarVisual.new()
	car.add_child(vis)
	vis.setup(car)
	car.visual = vis

	# Heavy frontal dent near nose/windscreen.
	vis._dent_local(Vector3(0.0, 0.75, -1.8), Vector3(0.0, 0.0, 1.0), 0.25, 1.3)
	var max_glass_disp := 0.0
	var max_paint_disp := 0.0
	for s in vis._arrays.size():
		var kind: String = vis._surf_kinds[s]
		var v: PackedVector3Array = vis._arrays[s][Mesh.ARRAY_VERTEX]
		var r: PackedVector3Array = vis._rest[s]
		for i in v.size():
			var d := v[i].distance_to(r[i])
			if kind in ["glass", "glass_clear"]:
				max_glass_disp = maxf(max_glass_disp, d)
			elif kind == "paint":
				max_paint_disp = maxf(max_paint_disp, d)
	t.check(max_paint_disp > 0.04 and max_paint_disp <= 0.281, "paint panel crumpled realistically (%.3f m)" % max_paint_disp)
	t.check(max_glass_disp <= 0.056, "brittle glass resisted taffy stretching (%.3f m)" % max_glass_disp)
	host.queue_free()
	await get_tree().process_frame


func test_elevators_across_building_styles_and_garage(t) -> void:
	var host := Node3D.new()
	add_child(host)
	for style in ["hotel", "office", "hq"]:
		var el := ApartmentElevator.build_commercial_stop(style, "u_" + style, style.to_upper() + " TOWER", "F12")
		host.add_child(el)
		t.check(el.commercial_stop and el.building_style == style, "%s commercial elevator initialized" % style)
		t.check(el._cabin != null and el._cabin.get_node_or_null("CabinMirror") != null, "%s cabin has reflective mirror" % style)
		t.check(el._cabin.get_node_or_null("CabinMetal") != null and el._cabin.get_node_or_null("CabinWood") != null, "%s cabin has distinct metallic & wood PBR layers" % style)
		t.check(el._btn_top_mat != null and el._btn_g_mat != null and el._btn_gar_mat != null, "%s cabin has full COP floor buttons" % style)
		t.check(el.is_inside_cabin(el.safe_cabin_world()), "%s safe_cabin_world is inside cabin bounds" % style)

	# Garage stop matching hotel style + sealed arrival sequence.
	var gl := ApartmentElevator.build_garage_stop(3, VehicleGarage.BAY_LEVEL, "hotel")
	host.add_child(gl)
	t.check(gl.garage_stop and gl.building_style == "hotel", "garage lift matches source building style")
	gl.arrive_sealed(false, VehicleGarage.BAY_LEVEL)
	t.check(gl.state == "arriving" and gl._g_door_open == 0.0, "garage lift arrives sealed before opening")
	t.check(gl.is_inside_cabin(gl.safe_cabin_world()), "garage safe_cabin_world is inside cabin bounds")

	host.queue_free()
	await get_tree().process_frame
