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
