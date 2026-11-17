extends SceneTree
## Road network inspector for all three islands (Commercial Island, Westbank,
## Skyport). Lists every junction by type and flags geometric defects:
##   dangling     a road end that meets no other road (and isn't at the coast)
##   near_miss    an end that stops short of a road it was heading for
##   overshoot    an end that pokes out past the far kerb of the road it meets
##   sharp_angle  roads meeting at < 35° (a slit of asphalt, unreadable paint)
##   close_jn     two junctions on one road closer than their mouths need
##   stub         a road shorter than 18 m between its ends
##   tight_bend   a centre-line radius below what its kind allows
##   crossing     two centre lines crossing away from any roundabout (X junction)
##   off_land     a road point outside its island's coast (not a bridge approach)
##   overlap      two roads running side by side, their carriageways overlapping
##   grade        a road steeper than 12 % (sampled on the city terrain)
##   lanes        traffic lanes that end without a connection (dead lanes)
##
##   godot --headless -s res://tools/road_audit.gd -- [out.json]
## Prints a summary and one line per defect; the JSON has every junction
## (type, position, arms) for picking audit cameras.

var out := {"junctions": [], "defects": []}


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	SkyportIsland.enabled = true
	var layout := CityLayout.new().generate()
	_city("island", layout)
	if layout.mainland != null:
		_city("westbank", layout.mainland)
	_skyport(layout)
	_lanes("island", layout)
	if layout.mainland != null:
		_lanes("westbank", layout.mainland)
	var counts := {}
	for d: Dictionary in out["defects"]:
		counts[d["kind"]] = int(counts.get(d["kind"], 0)) + 1
	var jt := {}
	for j: Dictionary in out["junctions"]:
		var k := "%s/%s" % [j["island"], j["type"]]
		jt[k] = int(jt.get(k, 0)) + 1
	print("ROAD_AUDIT junctions ", JSON.stringify(jt))
	print("ROAD_AUDIT defects ", JSON.stringify(counts), " total ", out["defects"].size())
	for d: Dictionary in out["defects"]:
		print("  ", d["island"], " ", d["kind"], " @", d["at"], " ", d.get("note", ""))
	if args.size() > 0:
		var f := FileAccess.open(args[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(out, " "))
	quit()


func _defect(island: String, kind: String, at: Vector2, note := "") -> void:
	out["defects"].append({"island": island, "kind": kind, "at": [snappedf(at.x, 0.1), snappedf(at.y, 0.1)], "note": note})


func _junction(island: String, type: String, at: Vector2, arms: Array, note := "", dir := Vector2.ZERO) -> void:
	out["junctions"].append({"island": island, "type": type, "at": [snappedf(at.x, 0.1), snappedf(at.y, 0.1)],
		"arms": arms, "note": note, "dir": [snappedf(dir.x, 0.001), snappedf(dir.y, 0.001)]})


static func _closest_on(pts: PackedVector2Array, p: Vector2) -> Array:
	# [distance, point, segment index, t along the line (m)]
	var best := [INF, Vector2.ZERO, -1, 0.0]
	var along := 0.0
	for i in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		var d := q.distance_to(p)
		if d < best[0]:
			best = [d, q, i, along + pts[i].distance_to(q)]
		along += pts[i].distance_to(pts[i + 1])
	return best


static func _dir_at(pts: PackedVector2Array, i: int) -> Vector2:
	return (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i, 0)]).normalized()


func _city(island: String, L: CityLayout) -> void:
	var R := L.roads
	var roads: Array = R.roads
	var coast := R.coast
	var name_of := func(r: Dictionary) -> String:
		return String(r.get("name", "%s#%d" % [r["kind"], int(r.get("id", -1))]))
	# Ends: where does each end land?
	var ends_on := {}   # road index -> Array of [t, other index]
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		if r.get("loop", false):
			continue
		var pts: PackedVector2Array = r["pts"]
		if pts.size() < 2:
			continue
		var hw := float(r["w"]) * 0.5
		var length := CityRoads.length_of(pts)
		if length < 18.0:
			_defect(island, "stub", pts[0], "%s %.1f m" % [name_of.call(r), length])
		for e in 2:
			var p := pts[0] if e == 0 else pts[-1]
			var dir := (p - (pts[1] if e == 0 else pts[-2])).normalized()
			var best := [INF, -1, Vector2.ZERO, 0.0]
			for oi in roads.size():
				if oi == ri:
					continue
				var o: Dictionary = roads[oi]
				var c := _closest_on(o["pts"], p)
				var gap: float = float(c[0]) - float(o["w"]) * 0.5
				if gap < best[0]:
					best = [gap, oi, c[1], c[3], c[2]]
			var at_coast := not Geometry2D.is_point_in_polygon(p - dir * 1.0, coast) or _dist_to_poly(p, coast) < hw + 25.0
			if best[1] < 0 or float(best[0]) > 1.5:
				if at_coast:
					pass
				elif float(best[0]) < 25.0 and best[1] >= 0:
					_defect(island, "near_miss", p, "%s end %d stops %.1f m short of %s" % [name_of.call(r), e, best[0], name_of.call(roads[best[1]])])
				else:
					_defect(island, "dangling", p, "%s end %d" % [name_of.call(r), e])
				continue
			var o: Dictionary = roads[best[1]]
			var ohw := float(o["w"]) * 0.5
			var c2 := _closest_on(o["pts"], p)
			var od := _dir_at(o["pts"], int(c2[2]))
			var ang := rad_to_deg(acos(clampf(absf(od.dot(dir)), 0.0, 1.0)))
			# Signed: is the end past the other road's centre line by more than its half width?
			var side := (p - (c2[1] as Vector2))
			var past := side.dot(dir)
			if past > ohw + 0.6 and not o.get("ring", false):
				_defect(island, "overshoot", p, "%s pokes %.1f m past %s's far kerb" % [name_of.call(r), past - ohw, name_of.call(o)])
			var ring: bool = o.get("ring", false)
			var type := "roundabout_arm" if ring else ("T_major" if r["kind"] != "minor" and o["kind"] != "minor" else
				("T_minor_on_major" if o["kind"] != "minor" else "T_minor"))
			if ang < 90.0 - 55.0 + 0.0 and ang < 35.0:
				_defect(island, "sharp_angle", p, "%s meets %s at %.0f°" % [name_of.call(r), name_of.call(o), ang])
			_junction(island, type, p, [name_of.call(r), name_of.call(o)], "%.0f°" % ang, -dir)
			if not ends_on.has(best[1]):
				ends_on[best[1]] = []
			ends_on[best[1]].append([float(c2[3]), ri, hw])
	# Close junctions along one road (staggered mouths overlap).
	for oi in ends_on:
		var js: Array = ends_on[oi]
		js.sort_custom(func(a, b): return a[0] < b[0])
		for k in range(1, js.size()):
			var gap: float = float(js[k][0]) - float(js[k - 1][0]) - float(js[k][2]) - float(js[k - 1][2])
			if gap < 8.0 and gap > -1e9:
				var o: Dictionary = roads[oi]
				var c := CityLayout._offset_line(o["pts"], 0.0)
				var q := _point_at(c, float(js[k][0]))
				# (Opposite sides of a road at the same place is a crossroads, not a stagger.)
				var pa: PackedVector2Array = roads[js[k][1]]["pts"]
				var pb: PackedVector2Array = roads[js[k - 1][1]]["pts"]
				var ea := pa[0] if _closest_on(o["pts"], pa[0])[0] < _closest_on(o["pts"], pa[-1])[0] else pa[-1]
				var eb := pb[0] if _closest_on(o["pts"], pb[0])[0] < _closest_on(o["pts"], pb[-1])[0] else pb[-1]
				var cq: Vector2 = _closest_on(o["pts"], ea)[1]
				var same_side := (ea - cq).dot(eb - cq) > 0.0
				var stagger := absf(float(js[k][0]) - float(js[k - 1][0]))
				if same_side or stagger > 2.5:
					_defect(island, "close_jn", q, "on %s: mouths %.1f m apart (%s, stagger %.1f m)" % [name_of.call(o), gap,
						"same side" if same_side else "opposite sides", stagger])
	# Crossings of centre lines away from ends/roundabouts.
	for i in roads.size():
		for j in range(i + 1, roads.size()):
			var a: Dictionary = roads[i]
			var b: Dictionary = roads[j]
			if a.get("ring", false) or b.get("ring", false):
				continue
			for x in CityRoads._crossings(a["pts"], b["pts"]):
				var pa: PackedVector2Array = a["pts"]
				var pb: PackedVector2Array = b["pts"]
				var near_end := false
				for e: Vector2 in [pa[0], pa[-1], pb[0], pb[-1]]:
					if e.distance_to(x) < 20.0:
						near_end = true
				if near_end:
					continue
				var in_rb := false
				for rb in R.roundabouts:
					if (rb["c"] as Vector2).distance_to(x) < float(rb["r"]) + 2.0:
						in_rb = true
				if in_rb:
					continue
				var ta := _closest_on(pa, x)
				var tb := _closest_on(pb, x)
				var ang := rad_to_deg(acos(clampf(absf(_dir_at(pa, ta[2]).dot(_dir_at(pb, tb[2]))), 0.0, 1.0)))
				_junction(island, "crossroads", x, [name_of.call(a), name_of.call(b)], "%.0f°" % ang, _dir_at(pa, ta[2]))
				if ang < 35.0:
					_defect(island, "sharp_angle", x, "%s crosses %s at %.0f°" % [name_of.call(a), name_of.call(b), ang])
	for rb in R.roundabouts:
		var arms: Array = []
		for r in roads:
			if r.get("ring", false):
				continue
			for x in CityRoads._crossings(r["pts"], CityRoads._circle(rb["c"], float(rb["r"]), 48)):
				arms.append(name_of.call(r))
		_junction(island, "roundabout", rb["c"], arms)
	# Bends.
	for r in roads:
		if r.get("ring", false):
			continue
		var pts := CityRoads._simplify(r["pts"], 0.25)
		var min_r := INF
		var at := Vector2.ZERO
		for i in range(1, pts.size() - 1):
			var a := pts[i - 1]
			var b := pts[i]
			var c := pts[i + 1]
			if a.distance_to(b) < 2.0 or b.distance_to(c) < 2.0:
				continue
			var rr := _circum(a, b, c)
			if rr < min_r:
				min_r = rr
				at = b
		var need := 12.0 if r["kind"] == "minor" else 40.0
		if r.get("loop", false):
			need = 30.0
		if min_r < need:
			_defect(island, "tight_bend", at, "%s radius %.1f m (≥ %.0f)" % [name_of.call(r), min_r, need])
	# Off land.
	for r in roads:
		if String(r.get("name", "")).ends_with("Approach"):
			continue
		for p: Vector2 in r["pts"]:
			if not Geometry2D.is_point_in_polygon(p, coast) and _dist_to_poly(p, coast) > 4.0:
				_defect(island, "off_land", p, "%s" % name_of.call(r))
				break
	# Grades (city terrain).
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		var prev := NAN
		var s := 0.0
		var step := 6.0
		var worst := 0.0
		var wat := Vector2.ZERO
		var line := _resample(pts, step)
		for i in line.size():
			var y := L.ground_y(line[i].x, line[i].y) if L.has_method("ground_y") else 0.0
			if i > 0 and not is_nan(prev):
				var g := absf(y - prev) / step
				if g > worst:
					worst = g
					wat = line[i]
			prev = y
		if worst > 0.12:
			_defect(island, "grade", wat, "%s %.0f %%" % [name_of.call(r), worst * 100.0])


func _skyport(layout: CityLayout) -> void:
	var P := SkyportIsland.plan(layout)
	var roads: Array = P["roads"]
	var nodes := SkyportIsland._road_nodes(roads)
	var w2 := func(v: Vector3) -> Vector2:
		var q := SkyportIsland.w(v)
		return Vector2(q.x, q.z)
	var circ: Array = P.get("circus", [])
	for k in nodes:
		var nd: Dictionary = nodes[k]
		var p: Vector3 = nd["p"]
		var arms: Array = nd["arms"]
		var wp: Vector2 = w2.call(p)
		var in_circus := not circ.is_empty() and Vector2(p.x, p.z).distance_to(circ[0]) < float(circ[1]) + 1.0
		if arms.size() == 1:
			# An end on another road's side (T) or a true dead end?
			var on_side := false
			var nm := ""
			for r in roads:
				var pts: PackedVector3Array = r[1]
				var flat := PackedVector2Array()
				for q in pts:
					flat.append(Vector2(q.x, q.z))
				var c := _closest_on(flat, Vector2(p.x, p.z))
				if float(c[0]) < float(r[2]) * 0.5 + 1.0 and float(c[0]) > 0.05:
					on_side = true
					nm = r[0]
			_junction("skyport", "T_side" if on_side else "end", wp, [nm])
			if not on_side:
				var near_city := false
				for e in [SkyportIsland.w(p)]:
					near_city = not Geometry2D.is_point_in_polygon(Vector2(e.x, e.z), _sky_coast()) or _dist_to_poly(Vector2(e.x, e.z), _sky_coast()) < 30.0
				if not near_city:
					_defect("skyport", "dangling", wp, "road end at local (%.0f, %.0f)" % [p.x, p.z])
			continue
		var type := "roundabout_arm" if in_circus else ("node_%d" % arms.size())
		var d0: Vector3 = (arms[0] as Array)[0]
		var wd := SkyportIsland.w(p + d0 * 10.0) - SkyportIsland.w(p)
		_junction("skyport", type, wp, [arms.size()], "", Vector2(wd.x, wd.z).normalized())
		var dirs: Array = []
		for a: Array in arms:
			dirs.append(a[0] as Vector3)
		for i in dirs.size():
			for j in range(i + 1, dirs.size()):
				var cosv := (dirs[i] as Vector3).dot(dirs[j])
				var ang := rad_to_deg(acos(clampf(cosv, -1.0, 1.0)))
				if ang < 35.0 and not in_circus:
					_defect("skyport", "sharp_angle", wp, "arms %.0f° apart at local (%.0f, %.0f)" % [ang, p.x, p.z])
	# Nodes too close (separate junction boxes overlapping).
	var ks := nodes.keys()
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			var a: Vector3 = nodes[ks[i]]["p"]
			var b: Vector3 = nodes[ks[j]]["p"]
			var d := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
			if d > 0.5 and d < 24.0:
				var in_c := not circ.is_empty() and Vector2(a.x, a.z).distance_to(circ[0]) < float(circ[1]) + 2.0
				if not in_c:
					_defect("skyport", "close_jn", w2.call(a), "nodes %.1f m apart" % d)
	# Bends and grades.
	for r in roads:
		if r[0] == "Terminal Circus":
			continue
		var pts: PackedVector3Array = r[1]
		var min_r := INF
		var at := Vector3.ZERO
		var worst := 0.0
		var wat := Vector3.ZERO
		for i in range(1, pts.size() - 1):
			var a := Vector2(pts[i - 1].x, pts[i - 1].z)
			var b := Vector2(pts[i].x, pts[i].z)
			var c := Vector2(pts[i + 1].x, pts[i + 1].z)
			if a.distance_to(b) > 1.5 and b.distance_to(c) > 1.5:
				var rr := _circum(a, b, c)
				if rr < min_r:
					min_r = rr
					at = pts[i]
		for i in range(1, pts.size()):
			var hd := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
			if hd > 0.5:
				var g := absf(pts[i].y - pts[i - 1].y) / hd
				if g > worst:
					worst = g
					wat = pts[i]
		var need := 12.0 if float(r[2]) < 14.0 else 30.0
		if min_r < need:
			_defect("skyport", "tight_bend", w2.call(at), "%s radius %.1f m" % [r[0], min_r])
		if worst > 0.12 and not String(r[0]).ends_with("Bridge"):
			_defect("skyport", "grade", w2.call(wat), "%s %.0f %%" % [r[0], worst * 100.0])
	# Overlaps: roads (not sharing an end) whose carriageways overlap.
	for i in roads.size():
		for j in range(i + 1, roads.size()):
			var a: Array = roads[i]
			var b: Array = roads[j]
			var fa := PackedVector2Array()
			for q in (a[1] as PackedVector3Array):
				fa.append(Vector2(q.x, q.z))
			var fb := PackedVector2Array()
			for q in (b[1] as PackedVector3Array):
				fb.append(Vector2(q.x, q.z))
			var lim := (float(a[2]) + float(b[2])) * 0.5 - 0.5
			var run := 0
			for q in _resample(fa, 4.0):
				var c := _closest_on(fb, q)
				if float(c[0]) < lim and q.distance_to(fa[0]) > lim + 6.0 and q.distance_to(fa[-1]) > lim + 6.0 \
						and q.distance_to(fb[0]) > lim + 6.0 and q.distance_to(fb[-1]) > lim + 6.0:
					run += 1
					if run == 3:
						_defect("skyport", "overlap", SkyportIsland.w2(q), "%s / %s" % [a[0], b[0]])
				else:
					run = 0


## Traffic lanes (Traffic.build_network): a lane that ends with nowhere to
## go (dead), or that nothing feeds and no car can turn into (orphan).
func _lanes(island: String, L: CityLayout) -> void:
	var t := Traffic.new()
	t.layout = L
	t.build_network()
	var dead := 0
	var orphan := 0
	var base := 0
	for li in t.l_base.size():
		if t.l_piece[li] < 0:
			continue
		base += 1
		var lp: PackedVector3Array = t._lane_pts[li]
		if t.l_loop[li] == 0 and (t.l_ends[li] as Array).is_empty() and t.l_next[li] < 0:
			dead += 1
			_defect(island, "lanes", Vector2(lp[-1].x, lp[-1].z), "dead lane end (%d m lane)" % int(t.l_len[li]))
		if (t.l_feeds[li] as Array).is_empty() and t.l_loop[li] == 0:
			orphan += 1
			_defect(island, "lanes", Vector2(lp[0].x, lp[0].z), "orphan lane start (nothing turns into it)")
	print("ROAD_AUDIT lanes %s: %d lanes, %d dead ends, %d orphans" % [island, base, dead, orphan])
	t.free()


var _sky_coast_cache := PackedVector2Array()
func _sky_coast() -> PackedVector2Array:
	if _sky_coast_cache.is_empty():
		for q in SkyportIsland.outline():
			var v: Vector2 = q
			_sky_coast_cache.append(SkyportIsland.w2(v))
	return _sky_coast_cache


static func _circum(a: Vector2, b: Vector2, c: Vector2) -> float:
	var A := a.distance_to(b)
	var B := b.distance_to(c)
	var C := c.distance_to(a)
	var area2 := absf((b - a).cross(c - a))
	if area2 < 1e-6:
		return INF
	return A * B * C / (2.0 * area2)


static func _dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p))
	return best


static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out_p := PackedVector2Array()
	var total := CityRoads.length_of(pts)
	var s := 0.0
	while s <= total:
		out_p.append(_point_at(pts, s))
		s += step
	return out_p


static func _point_at(pts: PackedVector2Array, s: float) -> Vector2:
	var acc := 0.0
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		if acc + l >= s:
			return pts[i].lerp(pts[i + 1], (s - acc) / maxf(l, 1e-6))
		acc += l
	return pts[-1]
