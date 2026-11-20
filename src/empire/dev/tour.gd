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
	if args.has("tour-tree"):
		for c1 in get_tree().root.get_node("EmpireGame").get_children():
			var names := []
			for c2 in c1.get_children():
				names.append(String(c2.name))
			var uniq := {}
			for nm2 in names:
				uniq[String(nm2).rstrip("0123456789_-")] = true
			print("TOUR_TREE ", c1.name, ": ", ", ".join(PackedStringArray(uniq.keys())))
	if args.has("tour-noshadow"):
		for nd in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			(nd as DirectionalLight3D).shadow_enabled = false
	# --tour-hide=A,B: hide every node whose name starts with one of these
	# (finding what draws an artefact).
	for pat in String(args.get("tour-hide", "")).split(",", false):
		for nd in get_tree().root.find_children(pat + "*", "", true, false):
			if nd is Node3D:
				(nd as Node3D).visible = false
				print("TOUR_HIDE ", nd.get_path())
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
		if parts.size() > 3 and parts[3] == "rel":
			# (Heights relative to the ground at the hero's spot.)
			from.y += gy
			to.y += gy
		var cam: Node = game.get("camera")
		cam.set("cine", func(_dt: float) -> Array:
			return [Transform3D(Basis.looking_at(to - from, Vector3.UP), from), float(args.get("tour-fov", "62"))])
		if args.has("tour-nohero"):
			(game.get("player") as Node3D).visible = false
		await get_tree().create_timer(wait).timeout
		if args.has("tour-clear"):
			# (tools/photos: a view whose camera sits inside or behind a
			# building swings round the target / climbs until the line
			# of sight is clear; --tour-clear=redo shoots only those.)
			var fixed := await _clear_view(from, to)
			if fixed.is_empty():
				if String(args["tour-clear"]) == "redo":
					print("TOUR_CLEAR ", nm)
					continue
			else:
				var f2: Vector3 = fixed[0]
				print("TOUR_MOVED ", nm, " ", f2)
				# (lambdas capture by value: a new one for the new spot)
				var fov := float(args.get("tour-fov", "62"))
				cam.set("cine", func(_dt: float) -> Array:
					return [Transform3D(Basis.looking_at(to - f2, Vector3.UP), f2), fov])
				await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		# --tour-probe=name@x,y;name@x,y (pixels at 1280x720)
		for pr in String(args.get("tour-probe", "")).split(";", false):
			if pr.split("@")[0] == nm:
				_probe(pr.split("@")[1].split_floats(","))
		var img := get_viewport().get_texture().get_image()
		if args.has("tour-jpg"):
			# (tools/photos: property photos, w px wide, JPEG.)
			var jw := int(args["tour-jpg"])
			img.resize(jw, int(img.get_height() * float(jw) / img.get_width()), Image.INTERPOLATE_BILINEAR)
			img.save_jpg(dir.path_join(nm + ".jpg"), 0.82)
		else:
			img.save_png(dir.path_join(nm + ".png"))
		var ri := func(k): return RenderingServer.get_rendering_info(k)
		print("TOUR_SHOT ", nm, " ", JSON.stringify({"draws": ri.call(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"prims": ri.call(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)}))
	get_tree().quit()


## --tour-probe=px,py: what is under that pixel (finding what draws an
## artefact): the collider the ray hits, and every visible mesh whose
## bounds hold the hit point.
func _probe(px: PackedFloat64Array) -> void:
	var cam := get_viewport().get_camera_3d()
	var vs := get_viewport().get_visible_rect().size
	var sp := Vector2(px[0], px[1]) * vs / Vector2(1280, 720)
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	var space := get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + d * 2000.0))
	var p: Vector3 = hit.get("position", o + d * 15.0)
	print("TOUR_PROBE hit ", p, " ", (hit["collider"] as Node).get_path() if hit else "nothing")
	for nd in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := nd as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var bb := g.global_transform * g.get_aabb()
		if bb.grow(0.5).has_point(p) and bb.size.length() < 400.0:
			print("TOUR_PROBE mesh ", g.get_path(), " ", bb)


## [] when the camera at `from` sees `to` (nothing solid between them, the
## last 4 m at the target ignored: the shopfront itself); else [new_from]:
## the nearest clear spot found by turning round the target in 30° steps
## and climbing, keeping the distance. [] also when nothing is clear.
func _clear_view(from: Vector3, to: Vector3) -> Array:
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var blocked := func(p: Vector3) -> bool:
		var d := (p - to)
		var q := PhysicsRayQueryParameters3D.create(to + d.normalized() * 4.0, p + d.normalized() * 1.5)
		return not space.intersect_ray(q).is_empty()
	if not blocked.call(from):
		return []
	var off := from - to
	var flat := Vector2(off.x, off.z)
	var r := flat.length()
	for lift in [0.0, 15.0, 35.0, 60.0]:
		for k in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6]:
			if lift == 0.0 and k == 0:
				continue
			var a := flat.angle() + deg_to_rad(30.0 * k)
			var p := to + Vector3(cos(a) * r, off.y + lift, sin(a) * r)
			if not blocked.call(p):
				return [p]
	print("TOUR_BLOCKED ", from)
	return []
