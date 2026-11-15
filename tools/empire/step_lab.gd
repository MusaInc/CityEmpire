extends SceneTree
## Kerbs and stairs on foot: walks/jogs the everyday hero at steps of
## several heights and angles and reports which ones it gets up.
##   godot --headless --fixed-fps 60 -s res://tools/empire/step_lab.gd

class Walker:
	extends RefCounted
	var dir := Vector3.FORWARD
	var amount := 1.0
	var human_steer := true
	func drive(_p: Player, _dt: float) -> Dictionary:
		return {"move": dir * amount, "aim": dir, "grapple": false, "reel": 0.0, "jump": false}


func _initialize() -> void:
	_run.call_deferred()


func _box(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	b.add_child(c)
	b.position = at
	parent.add_child(b)


func _course(kind: String) -> Node3D:
	var n := Node3D.new()
	_box(n, Vector3(200, 1, 200), Vector3(0, -0.5, 0))
	match kind:
		"kerb12": _box(n, Vector3(200, 0.12, 100), Vector3(0, 0.06, -52))
		"kerb20": _box(n, Vector3(200, 0.20, 100), Vector3(0, 0.10, -52))
		"kerb30": _box(n, Vector3(200, 0.30, 100), Vector3(0, 0.15, -52))
		"kerb40": _box(n, Vector3(200, 0.40, 100), Vector3(0, 0.20, -52))
		"stairs":
			for i in 8:
				_box(n, Vector3(200, 0.17 * (i + 1), 0.3), Vector3(0, 0.085 * (i + 1), -2.15 - 0.3 * i))
			_box(n, Vector3(200, 1.36, 100), Vector3(0, 0.68, -54.4))
		"steep":  # deep risers, 20 cm, 26 cm treads (entrance plinths)
			for i in 4:
				_box(n, Vector3(200, 0.2 * (i + 1), 0.26), Vector3(0, 0.1 * (i + 1), -2.13 - 0.26 * i))
			_box(n, Vector3(200, 0.8, 100), Vector3(0, 0.4, -53.0))
	return n


func _trial(kind: String, amount: float, angle: float) -> Dictionary:
	var world := _course(kind)
	root.add_child(world)
	var p := Player.new()
	p.params = load("res://config/empire_params.tres")
	p.swing_enabled = false
	p.everyday = true
	var w := Walker.new()
	w.dir = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle))
	w.amount = amount
	p.bot = w
	root.add_child(p)
	p.respawn(Vector3(0, 0.95, 0))
	var staggers := [0]
	p.staggered.connect(func(_a, _b): staggers[0] += 1)
	var t := 0.0
	var top_y := 0.0
	while t < 4.0:
		await physics_frame
		t += 1.0 / 60.0
	var dz := -p.global_position.z
	var y := p.global_position.y - 0.9
	p.queue_free()
	world.queue_free()
	await physics_frame
	return {"y": y, "dz": dz, "stag": staggers[0]}


func _run() -> void:
	var fails := 0
	for kind in ["kerb12", "kerb20", "kerb30", "kerb40", "stairs", "steep"]:
		var line := "%-7s" % kind
		for amount in [0.45, 0.7, 1.0]:
			for angle in [0.0, 40.0, 70.0]:
				var r: Dictionary = await _trial(kind, amount, angle)
				var want := 1.3 if kind == "stairs" else (0.75 if kind == "steep" else 0.0)
				var up: bool = float(r["dz"]) > 3.0 and float(r["y"]) > want + float(kind.trim_prefix("kerb").to_int()) / 100.0 - 0.06 and int(r["stag"]) == 0
				if not up and kind != "kerb40":
					fails += 1
				line += "  %s%.2f/%d°:%s" % ["", amount, int(angle), ("ok" if up else "NO(y%.2f z%.1f s%d)" % [r["y"], r["dz"], r["stag"]])]
		print(line)
	print("STEP_LAB fails=%d" % fails)
	quit(fails)
