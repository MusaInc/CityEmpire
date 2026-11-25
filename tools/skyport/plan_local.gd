extends SceneTree
## Skyport plan in the island's LOCAL frame (x right, z down), 1 m/px, grid
## every 50 m (bright every 100): land, areas, roads, strips, buildings,
## rail, sites. Extra overlay rects: SKY_RECTS="x0,z0,x1,z1;..." (red).
##   godot --headless -s res://tools/skyport/plan_local.gd -- <out.png>

func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var out := OS.get_cmdline_user_args()[0]
	SkyportIsland.enabled = true
	var layout := CityLayout.new().generate()
	var P := SkyportIsland.plan(layout)
	var X0 := 1250.0
	var Z0 := -420.0
	var W := 2100
	var H := 1100
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(Color(0.12, 0.2, 0.32))
	var o := SkyportIsland.outline()
	for i in W:
		for j in H:
			if Geometry2D.is_point_in_polygon(Vector2(X0 + i, Z0 + j), o):
				img.set_pixel(i, j, Color(0.27, 0.4, 0.24))
	var fill := func(poly: PackedVector2Array, c: Color) -> void:
		var r := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			r = r.expand(p)
		for x in range(int(r.position.x), int(r.end.x) + 1):
			for z in range(int(r.position.y), int(r.end.y) + 1):
				var i := int(x - X0)
				var j := int(z - Z0)
				if i >= 0 and j >= 0 and i < W and j < H and Geometry2D.is_point_in_polygon(Vector2(x, z), poly):
					img.set_pixel(i, j, c)
	var dot := func(q: Vector2, c: Color, r: int) -> void:
		for a in range(-r, r + 1):
			for b in range(-r, r + 1):
				var i := int(q.x - X0) + a
				var j := int(q.y - Z0) + b
				if i >= 0 and j >= 0 and i < W and j < H:
					img.set_pixel(i, j, c)
	var line := func(a: Vector2, c2: Vector2, col: Color, r: int) -> void:
		var L := a.distance_to(c2)
		var k := 0.0
		while k <= L:
			dot.call(a.lerp(c2, k / maxf(L, 0.01)), col, r)
			k += 1.0
	for ar in P["areas"]:
		var c: Color = [Color(0.55, 0.53, 0.5), Color(0.3, 0.5, 0.25), Color(0.4, 0.4, 0.4), Color(0.4, 0.4, 0.4), Color(0.4, 0.4, 0.4), Color(0.62, 0.62, 0.6)][int(ar[0]) % 6]
		fill.call(ar[1], c)
	for st in P["strips"]:
		var a: Vector3 = st[1]
		var b: Vector3 = st[2]
		line.call(Vector2(a.x, a.z), Vector2(b.x, b.z), Color(0.18, 0.18, 0.2), int(float(st[3])))
	for r in P["roads"]:
		var rp: PackedVector3Array = r[1]
		for i in rp.size() - 1:
			line.call(Vector2(rp[i].x, rp[i].z), Vector2(rp[i + 1].x, rp[i + 1].z), Color(0.12, 0.12, 0.13), int(float(r[2]) * 0.5))
	for ln in P.get("rail_local", []):
		var pts: PackedVector2Array = ln
		for i in pts.size() - 1:
			line.call(pts[i], pts[i + 1], Color(0.6, 0.3, 0.8), 3)
	for b: Dictionary in P["buildings"]:
		for t: Array in b["tiers"]:
			fill.call(PackedVector2Array([Vector2(t[0], t[1]), Vector2(t[2], t[1]), Vector2(t[2], t[3]), Vector2(t[0], t[3])]),
				Color(0.85, 0.8, 0.7) if float(t[4]) < 4.0 else Color(0.95, 0.9, 0.8))
	for k in P["sites"]:
		var d: Vector3 = P["sites"][k]["door"]
		dot.call(Vector2(d.x, d.z), Color(1, 0.2, 0.8), 3)
	for s in P["stands"]:
		var p: Vector3 = s[0]
		dot.call(Vector2(p.x, p.z), Color(1, 0.6, 0.1), 3)
	for rs in OS.get_environment("SKY_RECTS").split(";", false):
		var v := rs.split_floats(",")
		var poly := PackedVector2Array([Vector2(v[0], v[1]), Vector2(v[2], v[1]), Vector2(v[2], v[3]), Vector2(v[0], v[3])])
		for i in 4:
			line.call(poly[i], poly[(i + 1) % 4], Color(1, 0.1, 0.1), 1)
	for gx in range(int(X0), int(X0) + W, 50):
		for j in H:
			var c := img.get_pixel(gx - int(X0), j)
			img.set_pixel(gx - int(X0), j, c.lerp(Color.WHITE, 0.55 if gx % 100 == 0 else 0.22))
	for gz in range(int(Z0), int(Z0) + H, 50):
		for i in W:
			var c := img.get_pixel(i, gz - int(Z0))
			img.set_pixel(i, gz - int(Z0), c.lerp(Color.WHITE, 0.55 if gz % 100 == 0 else 0.22))
	img.save_png(out)
	print("PLAN saved ", out)
	quit()
