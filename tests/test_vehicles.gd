extends RefCounted
## WorldState vehicles (tools/blender/ws_cars.py, ws_fleet.py, kestrel.py):
## every body in BodyDims loads, every material it uses is one CarVisual
## knows (an unknown name falls back to flat grey - a placeholder look), it
## has head and tail lamps on both sides (lamp glows, brake lights), and its
## wheel model exists.

const LIT := ["paint", "paint2", "lamp_head", "lamp_tail", "beacon_red", "beacon_blue"]


func test_every_body_is_complete(t) -> void:
	for body: String in BodyDims.DIMS:
		var mesh := CarVisual.load_mesh(body)
		if not t.check(mesh != null, "%s loads" % body):
			continue
		var unknown := []
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var n := src.resource_name if src else ""
			if n in LIT:
				continue
			var m := CarVisual.shared_mat(n)
			if m is StandardMaterial3D and (m as StandardMaterial3D).albedo_color == Color(0.5, 0.5, 0.5):
				unknown.append(n)
		t.check(unknown.is_empty(), "%s: no unknown materials %s" % [body, unknown])
		var spots := CarVisual.lamp_spots(body, mesh)
		if body != "civ_box" and body != "mammoth":   # (truck lamps: on the load body's rear sill)
			t.check((spots["head"] as Array).size() == 2, "%s: head lamps both sides" % body)
		t.check((spots["tail"] as Array).size() == 2, "%s: tail lamps both sides" % body)
		var w := String(BodyDims.DIMS[body].get("wheel", "steel"))
		t.check(CarVisual.load_mesh("wheel_" + w) != null, "%s: wheel_%s exists" % [body, w])


func test_traffic_lod_keeps_window_finish(t) -> void:
	var city := CityWorld.new()
	var shader := preload("res://src/world/shaders/traffic.gdshader")
	for kind in CityWorld.CAR_KINDS:
		var body := String(kind[2])
		var near_body := body + "_traffic" if ResourceLoader.exists(CityWorld.MODEL_VEH + body + "_traffic.glb") else body
		for model in [near_body, body + "_lod1"]:
			var mesh := city._traffic_car_mesh(model, shader, body)
			if not t.check(mesh != null, "%s loads" % model):
				continue
			var far := CityWorld._car_far_mesh(mesh)
			var pane := far.surface_get_material(1) as ShaderMaterial
			t.check(pane != null and pane.get_shader_parameter("finish") == 2,
				"%s has a traffic window material through the distance transition" % model)
	for model in ["civ_van", "civ_van_lod1", "kestrel"]:
		var mesh := CarVisual.load_mesh(model)
		var windows: Array[String] = []
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m.resource_name.begins_with("glass"):
				windows.append(m.resource_name)
		# (2026-11-26: the traffic fleet has real cabins – clear glass cut
		# through; the van's cargo doors stay sealed behind the cab bulkhead.)
		var want: Array[String] = []
		want.assign(["glass_clear"] if model == "kestrel" else ["glass_clear", "glass"])
		windows.sort()
		want.sort()
		t.check(windows == want, "%s has its authored glazing (%s)" % [model, windows])
	# A fallback body can lack glazing. Every emitted box must still use
	# the lane shader when Traffic builds its moving instances.
	var paint_only := ArrayMesh.new()
	paint_only.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	var paint := ShaderMaterial.new()
	paint.shader = shader
	paint.set_shader_parameter("use_instance_color", true)
	paint_only.surface_set_material(0, paint)
	var fallback := CityWorld._car_far_mesh(paint_only)
	t.check(fallback.get_surface_count() == 1 and fallback.surface_get_material(0) == paint,
		"a fallback without glazing emits only its vehicle body")
	city.free()
