extends SceneTree
## Street-lamp pool audit: are the draped night pools (CityWorld._pool_arrays)
## on top of the ground that is actually drawn? For a sample of chunks, every
## pool vertex is dropped onto the chunk's ground mesh (a vertical ray against
## its triangles); a vertex under the drawn ground hides that part of the pool,
## one far above it floats. Prints the share of each and the worst lamps.
##   godot --headless -s res://tools/pool_audit.gd [-- --chunks=N]


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var n_chunks := 40
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--chunks="):
			n_chunks = int(a.get_slice("=", 1))
	var city = load("res://src/world/city_world.gd").new()
	root.add_child(city)
	await process_frame
	for w in [city, city.mainland]:
		if w != null:
			_audit(w, n_chunks)
	quit()


func _audit(w: Node, n_chunks: int) -> void:
	var keys: Array = w._all_keys.duplicate()
	keys.sort_custom(func(a, b): return w._by_chunk.get(a, []).size() > w._by_chunk.get(b, []).size())
	keys = keys.slice(0, n_chunks)
	var total := 0
	var under := 0
	var over := 0
	var worst: Array = []
	var steep: Array = []   # [height range over the pool, centre]
	for k in keys:
		var g = w._ground_cache.get(k)
		var pools = w._pool_arrays(k)
		if g == null or pools == null:
			continue
		var gv: PackedVector3Array = g[Mesh.ARRAY_VERTEX]
		var gi: PackedInt32Array = g[Mesh.ARRAY_INDEX] if g[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if gi.is_empty():
			gi.resize(gv.size())
			for i in gv.size():
				gi[i] = i
		# Bucket the ground triangles on a 4 m grid for the ray tests.
		var cells := {}
		for t in range(0, gi.size(), 3):
			var a: Vector3 = gv[gi[t]]
			var b: Vector3 = gv[gi[t + 1]]
			var c: Vector3 = gv[gi[t + 2]]
			for cx in range(int(floor(minf(a.x, minf(b.x, c.x)) / 4.0)), int(floor(maxf(a.x, maxf(b.x, c.x)) / 4.0)) + 1):
				for cz in range(int(floor(minf(a.z, minf(b.z, c.z)) / 4.0)), int(floor(maxf(a.z, maxf(b.z, c.z)) / 4.0)) + 1):
					var ck := Vector2i(cx, cz)
					if not cells.has(ck):
						cells[ck] = []
					cells[ck].append([a, b, c])
		var pv: PackedVector3Array = pools[Mesh.ARRAY_VERTEX]
		var per := (CityWorld.POOL_NX + 1) * (CityWorld.POOL_NZ + 1)
		for lamp in range(0, pv.size(), per):
			var y0 := INF
			var y1 := -INF
			for i in range(lamp, lamp + per):
				y0 = minf(y0, pv[i].y)
				y1 = maxf(y1, pv[i].y)
			var ax: Vector3 = pv[lamp + CityWorld.POOL_NX] - pv[lamp]
			steep.append([y1 - y0, pv[lamp + per / 2], Vector2(ax.x, ax.z).normalized()])
			var lu := 0
			var lo := 0
			var ln := 0
			for i in range(lamp, lamp + per):
				var p: Vector3 = pv[i]
				var top := -INF
				for tri in cells.get(Vector2i(int(floor(p.x / 4.0)), int(floor(p.z / 4.0))), []):
					var hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, 500.0, p.z), Vector3.DOWN, tri[0], tri[1], tri[2])
					if hit != null:
						top = maxf(top, (hit as Vector3).y)
				if top == -INF:
					continue   # (off the chunk's ground: a neighbour's)
				ln += 1
				if p.y < top - 0.02:
					lu += 1
				elif p.y > top + 0.6:
					lo += 1
			total += ln
			under += lu
			over += lo
			if lu + lo > 0:
				worst.append([lu + lo, lu, lo, pv[lamp + per / 2]])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("POOL_AUDIT %s %d vertices: %.1f%% under the drawn ground, %.1f%% floating > 0.6 m" % [
		w.name, total, 100.0 * under / maxf(total, 1), 100.0 * over / maxf(total, 1)])
	steep.sort_custom(func(a, b): return a[0] > b[0])
	print("  steepest pools (for night views):")
	for r in steep.slice(0, 6) + steep.slice(steep.size() / 8, steep.size() / 8 + 4):
		print("    %.1f m over the pool at (%.0f, %.1f, %.0f), along the road (%.2f, %.2f)" % [r[0], r[1].x, r[1].y, r[1].z, r[2].x, r[2].y])
	for r in worst.slice(0, 12):
		print("  lamp at (%.0f, %.1f, %.0f): %d under, %d floating" % [r[3].x, r[3].y, r[3].z, r[1], r[2]])
