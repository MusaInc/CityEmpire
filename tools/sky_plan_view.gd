extends SceneTree
## Skyport layout sheet: the coastline (shore kinds coloured) over the
## island's content (buildings, roads, strips, stands, sites), 2 m/px.
##   godot --headless -s res://tools/sky_plan_view.gd -- <out.png>

func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "sky.png"
	SkyportIsland.enabled = true
	var layout := CityLayout.new().generate()
	var P := SkyportIsland.plan(layout)
	var x0 := -1100.0
	var z0 := 650.0
	var mpp := 2.0
	var W := int(1800 / mpp)
	var H := int(1750 / mpp)
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(Color(0.12, 0.2, 0.32))
	var o := SkyportIsland.outline()
	for i in W:
		for j in H:
			var q := SkyportIsland.l2(Vector2(x0 + i * mpp, z0 + j * mpp))
			if Geometry2D.is_point_in_polygon(q, o):
				img.set_pixel(i, j, Color(0.25, 0.35, 0.22))
	var px := func(ql: Vector2, c: Color, r: int = 0) -> void:
		var q := SkyportIsland.w2(ql)
		var i := int((q.x - x0) / mpp)
		var j := int((q.y - z0) / mpp)
		for a in range(-r, r + 1):
			for b in range(-r, r + 1):
				if i + a >= 0 and i + a < W and j + b >= 0 and j + b < H:
					img.set_pixel(i + a, j + b, c)
	for b: Dictionary in P["buildings"]:
		var t: Array = b["tiers"][0]
		var x := float(t[0])
		while x <= float(t[2]):
			var z := float(t[1])
			while z <= float(t[3]):
				px.call(Vector2(x, z), Color(0.75, 0.72, 0.65))
				z += mpp
			x += mpp
	for r in P["roads"]:
		var rp: PackedVector3Array = r[1]
		for i in rp.size() - 1:
			var a := Vector2(rp[i].x, rp[i].z)
			var c := Vector2(rp[i + 1].x, rp[i + 1].z)
			var L := a.distance_to(c)
			var k := 0.0
			while k <= L:
				px.call(a.lerp(c, k / maxf(L, 0.01)), Color(0.9, 0.9, 0.2) if not r[3] else Color(0.6, 0.6, 0.6), 1)
				k += mpp
	for st in P["strips"]:
		var a := Vector2((st[1] as Vector3).x, (st[1] as Vector3).z)
		var c := Vector2((st[2] as Vector3).x, (st[2] as Vector3).z)
		var L := a.distance_to(c)
		var k := 0.0
		while k <= L:
			px.call(a.lerp(c, k / maxf(L, 0.01)), Color(0.15, 0.15, 0.15), int(float(st[3]) / mpp))
			k += mpp
	for k in P["sites"]:
		var d: Vector3 = P["sites"][k]["door"]
		px.call(Vector2(d.x, d.z), Color(1, 0.2, 0.8), 3)
	var kinds := SkyportIsland._shore_kind
	for i in o.size():
		var col: Color = [Color(1, 1, 1), Color(1, 0.85, 0.5), Color(0.6, 0.45, 0.35)][kinds[i] if i < kinds.size() else 0]
		var a := o[i]
		var c := o[(i + 1) % o.size()]
		var L := a.distance_to(c)
		var k := 0.0
		while k <= L:
			px.call(a.lerp(c, k / maxf(L, 0.01)), col, 1)
			k += 1.0
	# Both bridges (world).
	for B: Dictionary in P["bridges"]:
		for v: Vector3 in (B["pts"] as PackedVector3Array):
			px.call(SkyportIsland.l2(Vector2(v.x, v.z)), Color(0.9, 0.5, 0.2), 2)
	# The XO rule: content on land, 8 m+ from the shore.
	var near := func(q: Vector2) -> float:
		var best := INF
		for i in o.size():
			best = minf(best, Geometry2D.get_closest_point_to_segment(q, o[i], o[(i + 1) % o.size()]).distance_to(q))
		return best
	var chk: Array = []
	for b: Dictionary in P["buildings"]:
		var t: Array = b["tiers"][0]
		for c in [Vector2(t[0], t[1]), Vector2(t[2], t[1]), Vector2(t[2], t[3]), Vector2(t[0], t[3])]:
			chk.append(["bldg", c])
	for r in P["roads"]:
		if r[3]:
			continue
		var rp: PackedVector3Array = r[1]
		for i in rp.size() - 1:
			var a := Vector2(rp[i].x, rp[i].z)
			var c := Vector2(rp[i + 1].x, rp[i + 1].z)
			var L := a.distance_to(c)
			var k := 0.0
			while k <= L:
				var q := a.lerp(c, k / maxf(L, 0.01))
				chk.append([String(r[0]), q])
				k += 10.0
	for st in P["strips"]:
		chk.append(["strip", Vector2((st[1] as Vector3).x, (st[1] as Vector3).z)])
		chk.append(["strip", Vector2((st[2] as Vector3).x, (st[2] as Vector3).z)])
	for k in P["sites"]:
		var d: Vector3 = P["sites"][k]["door"]
		chk.append([k, Vector2(d.x, d.z)])
	var nbad := 0
	for it in chk:
		var q: Vector2 = it[1]
		if not Geometry2D.is_point_in_polygon(q, o) or float(near.call(q)) < 8.0:
			nbad += 1
			print("OFF-LAND ", it[0], " ", q, " d=", near.call(q))
			px.call(q, Color(1, 0, 0), 4)
	var nk := 0
	for it in chk:
		var q: Vector2 = it[1]
		for kn: Array in SkyportIsland.knolls():
			var c: Vector2 = kn[0]
			var dx := (q.x - c.x) / (float(kn[1]) + 6.0)
			var dz := (q.y - c.y) / (float(kn[2]) + 6.0)
			if dx * dx + dz * dz < 1.0:
				nk += 1
				print("ON-KNOLL ", it[0], " ", q)
	for kn: Array in SkyportIsland.knolls():
		var c: Vector2 = kn[0]
		for a in 64:
			var t := TAU * a / 64.0
			px.call(c + Vector2(cos(t) * float(kn[1]), sin(t) * float(kn[2])), Color(0.4, 1, 0.4), 1)
	print("checked ", chk.size(), " bad ", nbad, " on knolls ", nk)
	img.save_png(out)
	print("saved ", out, " roads=", P["roads"].size(), " bldg=", P["buildings"].size())
	quit()
