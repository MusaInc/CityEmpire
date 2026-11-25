extends Node3D
## Vehicle texture review stage: one body at a time on an asphalt apron
## under a procedural sky and sun, Mobile renderer, the game's CarVisual
## and shaders, fixed cameras (identical before/after).
##   xvfb-run -a godot --rendering-method mobile --resolution 1280x720 res://tools/vehicle_tex/review.tscn -- \
##     --out=<abs dir> --bodies=kestrel,courier_van [--views=front34,wheel,...] [--before] [--paint=#rrggbb] [--dirt=0.6]
## --before renders with VehicleTex disabled (the pre-texture look).

const VIEWS := {
	"front34": [Vector3(3.3, 1.25, -4.3), Vector3(0, 0.6, 0), 50.0],
	"rear34": [Vector3(-3.4, 1.45, 4.4), Vector3(0, 0.65, 0), 50.0],
	"side": [Vector3(6.4, 1.0, 0.0), Vector3(0, 0.7, 0), 48.0],
	"wheel": [Vector3(-1.9, 0.55, -2.3), Vector3(-0.85, 0.35, -1.35), 38.0],   # front-left wheel (axle z fixed below)
	"nose": [Vector3(0.9, 0.85, -3.6), Vector3(0.0, 0.62, -2.0), 40.0],
	"tail": [Vector3(-0.9, 1.0, 3.8), Vector3(0.0, 0.8, 2.0), 40.0],
	"interior": [Vector3(-1.45, 1.35, 0.25), Vector3(0.25, 0.85, -0.55), 55.0],
	"panel": [Vector3(-2.3, 1.1, 0.6), Vector3(-0.9, 0.75, -0.2), 34.0],
}

var out := ""
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out = String(args.get("out", "/tmp"))
	DirAccess.make_dir_recursive_absolute(out)
	VehicleTex.enabled = not args.has("before")
	_stage()
	_run.call_deferred()


func _stage() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.32, 0.5, 0.78)
	ps.sky_horizon_color = Color(0.72, 0.78, 0.86)
	ps.ground_bottom_color = Color(0.18, 0.17, 0.16)
	ps.ground_horizon_color = Color(0.5, 0.5, 0.5)
	sky.sky_material = ps
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-140), 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.11, 0.11, 0.115)
	gm.roughness = 0.88
	ground.material_override = gm
	add_child(ground)


func _spec(body: String) -> Dictionary:
	var cs := CarCatalog.spec("kestrel")
	cs["body"] = body
	CarCatalog._fit_body(cs)
	var pk := body.trim_prefix("police_")
	if CarCatalog.POLICE.has(pk):
		cs["paint"] = (CarCatalog.POLICE[pk]["livery"] as Array)[0]
		cs["paint2"] = (CarCatalog.POLICE[pk]["livery"] as Array)[1]
		cs["wheel"] = CarCatalog.POLICE[pk]["wheel"]
	elif BodyDims.DIMS[body].has("wheel"):
		cs["wheel"] = BodyDims.DIMS[body]["wheel"]
	if args.has("paint"):
		cs["paint"] = Color.from_string(String(args["paint"]), Color.WHITE)
	return cs


func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var views: PackedStringArray = String(args.get("views", ",".join(VIEWS.keys()))).split(",")
	for body in String(args.get("bodies", "kestrel")).split(","):
		var c := Car.new()
		c.setup(_spec(body), "display")
		c.freeze = true
		add_child(c)
		var vis := CarVisual.new()
		c.add_child(vis)
		vis.setup(c)
		var wr := float(c.spec["wheel_r"])
		c.global_position = Vector3(0, -c.wheel_local(0).y + wr, 0)
		if args.has("dirt"):
			vis.paint_mat.set_shader_parameter("dirt", float(args["dirt"]))
		var w0 := c.wheel_local(0)
		for v in views:
			var vw: Array = VIEWS[v]
			var eye: Vector3 = vw[0]
			var at: Vector3 = vw[1]
			if v == "wheel":
				at = Vector3(w0.x, wr, w0.z)
				eye = at + Vector3(-1.3, 0.25, -0.9)
			var sz := c.spec["size"] as Vector3
			if v in ["front34", "rear34", "side"]:
				eye *= maxf(1.0, sz.z / 4.4)
			cam.fov = float(vw[2])
			cam.look_at_from_position(eye, at, Vector3.UP)
			for i in 8:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path := out.path_join("%s_%s%s.png" % [body, v, "_before" if args.has("before") else ""])
			img.save_png(path)
			print("REVIEW ", path)
		c.queue_free()
		await get_tree().process_frame
	get_tree().quit()
