extends RefCounted
## Vehicle texture pass (tools/blender/ws_texture.py, tools/vehicle_tex/run.sh):
## every fleet model has its Blender bake and a UV2 (bake atlas) layer, the
## shared library loads, and the finishes CarVisual hands out carry them.

const LIBRARY := ["paint", "leather", "fabric", "plastic", "carpet", "rubber", "brushed", "reflector", "lens",
	"grille", "teak", "tread", "sidewall", "rotor", "alloy"]


static func _has_uv2(path: String) -> bool:
	var inst := (load(path) as PackedScene).instantiate()
	var ok := true
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV2] == null:
				ok = false
	inst.free()
	return ok


func test_library_loads(t) -> void:
	for fam: String in LIBRARY:
		t.check(VehicleTex.tex(fam + "_n") != null and VehicleTex.tex(fam + "_m") != null, "library %s" % fam)


func test_every_body_and_wheel_is_baked(t) -> void:
	var names: Array = []
	for body: String in BodyDims.DIMS:
		if ResourceLoader.exists(CarVisual.DIR + body + ".glb"):
			names.append(body)
	for kind in CityWorld.CAR_KINDS:
		for suffix in ["_traffic", "_lod1"]:
			if ResourceLoader.exists(CarVisual.DIR + String(kind[2]) + suffix + ".glb"):
				names.append(String(kind[2]) + suffix)
	for w in ["blade", "center", "deep", "dish", "five", "kestrel", "mesh", "multi", "offroad", "rally", "split", "steel", "traffic", "turbine", "y5"]:
		names.append("wheel_" + w)
	for n: String in names:
		t.check(VehicleTex.bake(n) != null, "%s has a bake" % n)
		t.check(_has_uv2(CarVisual.DIR + n + ".glb"), "%s has UV2 on every surface" % n)
	for e in DirAccess.get_files_at("res://assets/vehicle_entries"):
		if e.ends_with(".glb"):
			t.check(_has_uv2("res://assets/vehicle_entries/" + e), "entry %s has UV2" % e)


func test_finishes_carry_textures(t) -> void:
	var m := CarVisual.body_finish("interior", "kestrel") as ShaderMaterial
	if t.check(m != null, "interior is a textured finish"):
		t.check(m.get_shader_parameter("bake_tex") == VehicleTex.bake("kestrel"), "interior samples the Kestrel bake")
		t.check(m.get_shader_parameter("detail_n") == VehicleTex.tex("leather_n"), "interior is leather-grained")
	# Glass stays the see-through glass shader.
	t.check(CarVisual.body_finish("glass_clear", "kestrel") == CarVisual.shared_mat("glass_clear"), "clear glass untouched")
	# Paint colour is still the uniform (respray works).
	var c := Car.new()
	c.setup(CarCatalog.spec("kestrel"), "display")
	var vis := CarVisual.new()
	c.add_child(vis)
	vis.setup(c)
	vis.set_paint(Color(0.8, 0.1, 0.1))
	t.check(vis.paint_mat.get_shader_parameter("base_color") == Color(0.8, 0.1, 0.1), "respray sets the paint colour")
	t.check(vis.paint_mat.get_shader_parameter("bake_tex") != null, "paint samples the body bake")
	c.free()
