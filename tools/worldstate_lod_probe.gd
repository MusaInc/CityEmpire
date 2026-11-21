extends SceneTree
## Small rendered check: each LOD transition must draw exactly one mesh.
## godot --path . -s res://tools/worldstate_lod_probe.gd [-- --shot=/tmp/lod.png]
func _initialize() -> void:
	go.call_deferred()
func go() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var near := MeshInstance3D.new()
	near.name = "Near"
	near.mesh = BoxMesh.new()
	var far := MeshInstance3D.new()
	far.name = "Far"
	far.mesh = BoxMesh.new()
	far.position.x = 1.0 # deliberately different AABB centres
	for mi in [near, far]:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color.GREEN if mi == near else Color.RED
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(mi)
	far.visibility_range_begin = 10.0
	far.visibility_range_begin_margin = 1.0
	var world_script = load("res://src/world/city_world.gd")
	world_script.link_lods(near, far)
	var camera := Camera3D.new()
	scene.add_child(camera)
	var ok := true
	for d in [8.0, 10.0, 12.0, 10.0, 8.0]:
		camera.position = Vector3(0, 0, d)
		for frame in 3:
			await process_frame
			await RenderingServer.frame_post_draw
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		print("LOD distance=", d, " draws=", draws)
		ok = ok and draws == 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			root.get_texture().get_image().save_png(arg.trim_prefix("--shot="))
	quit(0 if ok else 1)
