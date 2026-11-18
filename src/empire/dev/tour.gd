extends Node
## Captures: many fixed views from one start-up (the world loads once).
##   --tour=<file> [--tour-wait=s] [--stats]
## Each line of <file>: name:at_x,at_z:cam_x,cam_y,cam_z,look_x,look_y,look_z
## in world metres (absolute y, unlike --cam). The hero is put down at at_x,
## at_z (centres the streaming), the camera fixed, and after tour-wait
## seconds the frame is saved next to the file as <name>.png.

var game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: Dictionary = game.get("args")
	var path := String(args["tour"])
	var wait := float(args.get("tour-wait", "6"))
	var dir := path.get_base_dir()
	var lines := FileAccess.get_file_as_string(path).split("\n", false)
	var only := String(args.get("tour-only", ""))
	await get_tree().create_timer(4.0).timeout
	for ln in lines:
		ln = ln.strip_edges()
		if ln == "" or ln.begins_with("#"):
			continue
		var parts := ln.split(":")
		var nm := parts[0]
		if only != "" and not (nm in only.split(",")):
			continue
		var at := parts[1].split_floats(",")
		var cv := parts[2].split_floats(",")
		var layout: CityLayout = game.get("layout")
		var gy := layout.ground_y(at[0], at[1])
		if is_nan(gy):
			gy = 1.0
		game.call("_teleport", Vector3(at[0], gy + 1.0, at[1]), 0.0)
		# (The clock keeps running: every view at the hour asked for.)
		if args.has("hour"):
			(game.get("empire") as Object).set("minute", float(args["hour"]) * 60.0)
		var from := Vector3(cv[0], cv[1], cv[2])
		var to := Vector3(cv[3], cv[4], cv[5])
		var cam: Node = game.get("camera")
		cam.set("cine", func(_dt: float) -> Array:
			return [Transform3D(Basis.looking_at(to - from, Vector3.UP), from), 62.0])
		await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join(nm + ".png"))
		var ri := func(k): return RenderingServer.get_rendering_info(k)
		print("TOUR_SHOT ", nm, " ", JSON.stringify({"draws": ri.call(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"prims": ri.call(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)}))
	get_tree().quit()
