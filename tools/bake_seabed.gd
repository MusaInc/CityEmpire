extends SceneTree
## Bakes the bay's seabed: a depth map built from the real coastlines (both
## city islands, Westbank, the landforms, Skyport Island, the hills round the
## bay), so the water shader can colour, calm and foam the sea by depth.
##   godot --headless -s res://tools/bake_seabed.gd
## Writes res://assets/world/seabed.png (LA8): L = depth / MAX_DEPTH, A =
## how rocky the nearest shore is (0 sand … 1 rock / sea wall). Re-run it
## whenever a coastline changes (test_world checks it matches the coasts).
##
## Depth model (metres below the sea surface), by distance d to the nearest
## land and that shore's kind:
##   sand: a shelf – 0.4 m at the waterline, ~2 m at 25 m, ~6 m at 75 m,
##         ~12 m at 160 m, on down to the channel floor (turquoise shallows
##         by the beaches, deep blue between the islands);
##   rock / sea wall: steep – ~3 m at the foot, ~9 m at 25 m, ~16 m at 90 m;
##   plus gentle sand ridges and hollows (noise) on the shelf, and the
##   channels deepest mid-water.

const RECT := Rect2(-2400.0, -1800.0, 4800.0, 4800.0)
const SIZE := 896
const MAX_DEPTH := 32.0
const OUT := "res://assets/world/seabed.png"


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var t0 := Time.get_ticks_msec()
	var layout := CityLayout.new().generate()
	SkyportIsland.enabled = true
	Landforms.enabled = true
	SkyportIsland.plan(layout)
	Landforms.forms(layout)
	var n := SIZE
	var cell := RECT.size.x / n
	# 1. Land mask and each land pixel's shore kind (0 sand, 1 rock).
	var land := PackedByteArray()
	land.resize(n * n)
	var kind := PackedFloat32Array()
	kind.resize(n * n)
	# Vertical quay walls (the strait quays, Skyport's quays): deep water at
	# the foot – a "boulder toe" there drew surf lines a few metres off a
	# sheer wall (2026-11-18: pale stripes in the strait).
	var quay := PackedFloat32Array()
	quay.resize(n * n)
	SkyportIsland.outline()
	var sky_k := SkyportIsland._shore_kind
	for j in n:
		for i in n:
			var x := RECT.position.x + (i + 0.5) * cell
			var z := RECT.position.y + (j + 0.5) * cell
			var idx := j * n + i
			var is_land := false
			var k := 1.0
			if Hinterland.height_at(x, z) > Hinterland.SEA_Y + 0.2:
				is_land = true
				k = 0.0   # (the bay's own shore: beaches)
			elif not layout.is_water(Vector3(x, 0.0, z)):
				is_land = true
				k = 1.0   # (city sea walls and quays: a steep apron; refined below)
			land[idx] = 1 if is_land else 0
			kind[idx] = k
	# Only shoreline pixels matter (the distance pass carries their kind
	# out to sea): the island's and the landforms' own shore kinds there.
	var sky_l := SkyportIsland.outline()
	for j in range(1, n - 1):
		for i in range(1, n - 1):
			var idx := j * n + i
			if land[idx] == 0 or (land[idx - 1] == 1 and land[idx + 1] == 1 and land[idx - n] == 1 and land[idx + n] == 1):
				continue
			var x := RECT.position.x + (i + 0.5) * cell
			var z := RECT.position.y + (j + 0.5) * cell
			if SkyportIsland.contains(x, z):
				kind[idx] = _sky_kind(sky_l, sky_k, SkyportIsland.l2(Vector2(x, z)))
				if _sky_quay(sky_l, sky_k, SkyportIsland.l2(Vector2(x, z))):
					quay[idx] = 1.0
			elif absf(x - CityLayout.FAR_SHORE) < 12.0 or absf(x - CityLayout.RIVER_EDGE) < 12.0:
				quay[idx] = 1.0
			else:
				var f := Landforms.at(x, z)
				if not f.is_empty():
					kind[idx] = _form_kind(f, Vector2(x, z))
	print("mask %d ms" % (Time.get_ticks_msec() - t0))
	# 2. Distance to land (two-pass chamfer, in metres), carrying the
	# nearest land pixel's kind with it.
	var dist := PackedFloat32Array()
	dist.resize(n * n)
	var nk := PackedFloat32Array()
	nk.resize(n * n)
	var nq := PackedFloat32Array()
	nq.resize(n * n)
	for idx in n * n:
		dist[idx] = 0.0 if land[idx] == 1 else 1e9
		nk[idx] = kind[idx]
		nq[idx] = quay[idx]
	var a := cell
	var b := cell * 1.41421
	for j in n:
		for i in n:
			var idx := j * n + i
			if land[idx] == 1:
				continue
			var best := dist[idx]
			var bk := nk[idx]
			var bq := nq[idx]
			for o: Array in [[-1, 0, a], [0, -1, a], [-1, -1, b], [1, -1, b]]:
				var ii: int = i + int(o[0])
				var jj: int = j + int(o[1])
				if ii < 0 or jj < 0 or ii >= n:
					continue
				var c := dist[jj * n + ii] + float(o[2])
				if c < best:
					best = c
					bk = nk[jj * n + ii]
					bq = nq[jj * n + ii]
			dist[idx] = best
			nk[idx] = bk
			nq[idx] = bq
	for j in range(n - 1, -1, -1):
		for i in range(n - 1, -1, -1):
			var idx := j * n + i
			if land[idx] == 1:
				continue
			var best := dist[idx]
			var bk := nk[idx]
			var bq := nq[idx]
			for o: Array in [[1, 0, a], [0, 1, a], [1, 1, b], [-1, 1, b]]:
				var ii: int = i + int(o[0])
				var jj: int = j + int(o[1])
				if ii < 0 or jj >= n or ii >= n:
					continue
				var c := dist[jj * n + ii] + float(o[2])
				if c < best:
					best = c
					bk = nk[jj * n + ii]
					bq = nq[jj * n + ii]
			dist[idx] = best
			nk[idx] = bk
			nq[idx] = bq
	print("distance %d ms" % (Time.get_ticks_msec() - t0))
	# The nearest shore's kind changes abruptly where two shores' reaches
	# meet; blur it (≈ 40 m, separable box, twice) so the depth profile
	# blends instead of stepping into a visible line.
	var R := 4
	for pass_i in 2:
		var tmp := PackedFloat32Array()
		tmp.resize(n * n)
		for j in n:
			for i in n:
				var acc := 0.0
				var cnt := 0
				for o in range(-R, R + 1):
					var ii := clampi(i + o, 0, n - 1)
					acc += nk[j * n + ii]
					cnt += 1
				tmp[j * n + i] = acc / cnt
		for j in n:
			for i in n:
				var acc2 := 0.0
				var cnt2 := 0
				for o in range(-R, R + 1):
					var jj := clampi(j + o, 0, n - 1)
					acc2 += tmp[jj * n + i]
					cnt2 += 1
				nk[j * n + i] = acc2 / cnt2
	print("blur %d ms" % (Time.get_ticks_msec() - t0))
	# 3. Depth.
	var img := Image.create(n, n, false, Image.FORMAT_LA8)
	for j in n:
		for i in n:
			var idx := j * n + i
			var x := RECT.position.x + (i + 0.5) * cell
			var z := RECT.position.y + (j + 0.5) * cell
			var d := dist[idx]
			var r := nk[idx]
			var depth := 0.0
			if land[idx] == 0:
				depth = depth_at(d, r, x, z)
				if nq[idx] > 0.5:
					depth = maxf(depth, lerpf(4.5, depth, smoothstep(20.0, 80.0, d)))
			img.set_pixel(i, j, Color(depth / MAX_DEPTH, 0.0, 0.0, r))
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("seabed %dx%d (%.1f m/px) → %s in %d ms" % [n, n, cell, OUT, Time.get_ticks_msec() - t0])
	quit()


## Depth below the surface d metres out from a shore of rockiness r.
static func depth_at(d: float, r: float, x: float, z: float) -> float:
	# Every shore has a shallow shelf (turquoise water follows the coasts),
	# its width varying slowly along the coast – ×0.55 to ×1.6 – so the
	# shallows swell into bays and pinch off points rather than drawing an
	# even band. Rock and sea walls get a narrower, steeper one.
	var wv := 0.55 + 1.05 * clampf(0.5 + 0.5 * (sin(x * 0.0061 + z * 0.0037) * 0.6 + sin(z * 0.0097 - x * 0.0043 + 1.3) * 0.4), 0.0, 1.0)
	var ds := d / wv
	# Sand: a long shallow shelf, then down to the floor.
	var sand := 0.4 + 1.8 * smoothstep(0.0, 25.0, ds) + 3.8 * smoothstep(15.0, 75.0, ds) + 6.0 * smoothstep(50.0, 160.0, ds) + 10.0 * smoothstep(140.0, 420.0, ds)
	# Rock / sea wall: a boulder toe ~1.5 m down, a shelf to ~4 m over the
	# first 30–40 m, then a steeper drop.
	var rock := 1.4 + 2.4 * smoothstep(0.0, 34.0, ds) + 7.0 * smoothstep(28.0, 110.0, ds) + 11.0 * smoothstep(90.0, 420.0, ds)
	var depth := lerpf(sand, rock, r)
	# Sand ridges and hollows on the shelf (fade out in deep water), and a
	# broad unevenness on the channel floor.
	var shelf := 1.0 - smoothstep(60.0, 260.0, d)
	depth += (sin(x * 0.045 + z * 0.021) * 0.5 + sin(x * 0.013 - z * 0.038 + 1.7) * 0.5) * 0.9 * shelf * (1.0 - r)
	depth += (sin(x * 0.0041 + z * 0.0027) + sin(z * 0.0053 - x * 0.0019 + 2.0)) * 1.6 * smoothstep(150.0, 600.0, d)
	return clampf(depth, 0.3, MAX_DEPTH - 0.1)


## (Local coordinates: the outline and q.)
static func _sky_kind(o: PackedVector2Array, k: PackedByteArray, lq: Vector2) -> float:
	var best := INF
	var bk := 2
	for i in o.size():
		var dd := Geometry2D.get_closest_point_to_segment(lq, o[i], o[(i + 1) % o.size()]).distance_to(lq)
		if dd < best:
			best = dd
			bk = k[i] if i < k.size() else 2
	return 0.0 if bk == 1 else 1.0   # (beach: sand; rock or quay: steep)


static func _sky_quay(o: PackedVector2Array, k: PackedByteArray, lq: Vector2) -> bool:
	var best := INF
	var bk := 2
	for i in o.size():
		var dd := Geometry2D.get_closest_point_to_segment(lq, o[i], o[(i + 1) % o.size()]).distance_to(lq)
		if dd < best:
			best = dd
			bk = k[i] if i < k.size() else 2
	return bk == 0


static func _form_kind(f: Dictionary, q: Vector2) -> float:
	var o: PackedVector2Array = f["poly"]
	var k: PackedByteArray = f["kinds"]
	var best := INF
	var bk := 2
	for i in o.size():
		if k[i] == 3:
			continue
		var dd := Geometry2D.get_closest_point_to_segment(q, o[i], o[(i + 1) % o.size()]).distance_to(q)
		if dd < best:
			best = dd
			bk = k[i]
	return 0.0 if bk == 1 else 1.0
