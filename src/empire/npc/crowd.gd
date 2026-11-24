class_name Crowd
extends Node3D
## The people on the pavements round you, simulated on the CPU and drawn
## with the hero-derived bodies (assets/models/crowd.glb, crowd.gdshader):
##
##  * Everyone walks a loop – the pavement ring round a block (two lanes,
##    opposite ways), so nobody reaches the end of a path and vanishes.
##  * People only exist within NEAR m of you. New ones appear out of sight
##    (behind the camera or far off) and leave by walking out of range, so
##    you never see anyone pop in or out. The GPU walkers (CityWorld) are
##    hidden inside this radius and carry the streets beyond it.
##  * They step round you and out of the camera's line of sight to you
##    (an eased sidestep within the pavement, never a shove), keep their
##    distance behind slower walkers instead of walking through them, glance
##    at you, stop to look in shop windows, and now and then turn in at a
##    shop door (anyone else's shop) and go in.
## One MultiMesh per body type, rebuilt each frame from the people's state.

const NEAR := 92.0           # (was 62: the hand-over to the GPU walkers happened in plain view)
const KEEP := 104.0
const DROP := 150.0           # past this anyone goes, seen or not (a few pixels tall)
const SPACING := 36.0         # one person per this many metres of pavement (halved 2026-11-21: fewer, better people)
const LANES := [1.7, 3.0]     # m in from the block edge (as CityWorld)
const MODEL := "res://assets/models/crowd.glb"
const TOPS := [Color(0.85, 0.85, 0.82), Color(0.12, 0.13, 0.16), Color(0.55, 0.12, 0.12), Color(0.16, 0.28, 0.5),
	Color(0.36, 0.42, 0.3), Color(0.45, 0.45, 0.48), Color(0.62, 0.36, 0.5), Color(0.2, 0.45, 0.48), Color(0.5, 0.2, 0.55),
	Color(0.85, 0.7, 0.2), Color(0.25, 0.55, 0.75), Color(0.9, 0.45, 0.35), Color(0.75, 0.72, 0.62), Color(0.3, 0.3, 0.32)]

var game: EmpireGame
var density := 1.0
var _loops: Array = []        # {pts, cum, len, dir, rect}
var _grid := {}               # Vector2i(100 m cell) -> [loop index]
var _people: Array = []       # see _spawn
var _mmis: Array = []         # MultiMeshInstance3D per body
var _blobs: MultiMeshInstance3D   # contact shadows (one draw for everyone)
var _doors: Array = []        # [Vector3 door, Vector3 outward, unit id]
var _rng := RandomNumberGenerator.new()
var _acc := 0.0
var _first := true
var _ground: Callable
var _island_traffic: IslandTraffic
var _vehicles: Array = []          # [[Vector2 pos, Vector2 vel, float radius]]
var _crossing_entries := {}        # sidewalk loop idx -> [{cross_loop, entry_s, pos}]


func setup(p_game: EmpireGame) -> void:
	game = p_game
	_rng.seed = 1777
	_ground = func(x: float, z: float) -> float: return game.layout.ground_y(x, z)
	var layouts: Array = [game.layout]
	if game.layout.mainland:
		layouts.append(game.layout.mainland)
	for L: CityLayout in layouts:
		for blk in L.blocks:
			if blk["kind"] not in ["block", "plaza", "park"]:
				continue
			for li in LANES.size():
				var ring := Geometry2D.offset_polygon(blk["poly"], -float(LANES[li]))
				if ring.is_empty() or (ring[0] as PackedVector2Array).size() < 3:
					continue
				_add_loop(ring[0], 1 if li == 0 else -1)
	for city: CityWorld in [game.world, game.world.mainland]:
		if city != null and city.traffic != null:
			_add_city_crossings(city.traffic)
	# Skyport Island: a pavement each side of every road (walked along one
	# side and back along the other, so nobody reaches an end and vanishes).
	if SkyportIsland.enabled and game.skyport:
		var all_roads: Array = game.skyport.wplan.get("roads", [])
		for rd in all_roads:
			if rd[3]:
				continue  # (not on the bridge deck)
			var rp: PackedVector3Array = (rd[1] as PackedVector3Array).duplicate()
			var off := float(rd[2]) * 0.5 + 2.2
			# Turn round 12 m short of each end: people cross at the junction's
			# mouth, not through the middle of it.
			for end in [0, 1]:
				var i0 := 0 if end == 0 else rp.size() - 1
				var i1 := 1 if end == 0 else rp.size() - 2
				var dd := rp[i1] - rp[i0]
				if dd.length() > 30.0:
					rp[i0] = rp[i0] + dd.normalized() * 12.0
			var ring := PackedVector2Array()
			for side: float in [1.0, -1.0]:
				var idxs := range(rp.size()) if side > 0.0 else range(rp.size() - 1, -1, -1)
				for i in idxs:
					var a := rp[maxi(i - 1, 0)]
					var b := rp[mini(i + 1, rp.size() - 1)]
					var d := Vector2(b.x - a.x, b.z - a.z).normalized()
					var n := Vector2(-d.y, d.x) * off * side
					ring.append(Vector2(rp[i].x, rp[i].z) + n)
			# Where roads merge (the two bridge approaches meet in a Y) one
			# road's pavement runs inside the other's lanes: people walked
			# along the carriageway. A loop that does that is left out.
			if _loop_on_carriageway(ring, all_roads, rd):
				continue
			_add_loop(ring, 1, [rp.size() - 1, ring.size() - 1])
	for u in game.units:
		if u["kind"] == "shop":
			_doors.append([Premises.door_point(u), Premises.outward(u), u["id"]])
	var scene: PackedScene = load(MODEL)
	if scene == null:
		return
	var inst := scene.instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	mis.sort_custom(func(a, b): return String(a.name) < String(b.name))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/empire/npc/crowd.gdshader")
	for mi in mis:
		var m: Mesh = (mi as MeshInstance3D).mesh.duplicate()
		m.surface_set_material(0, mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = m
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mmis.append(mmi)
	inst.free()
	# Contact shadows: a soft disc under each person.
	var q := QuadMesh.new()
	q.size = Vector2(0.95, 0.95)
	q.orientation = PlaneMesh.FACE_Y
	var bm := ShaderMaterial.new()
	bm.shader = load("res://src/empire/npc/blob_shadow.gdshader")
	q.material = bm
	var bmm := MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.use_custom_data = true
	bmm.mesh = q
	_blobs = MultiMeshInstance3D.new()
	_blobs.multimesh = bmm
	_blobs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blobs)


func _add_city_crossings(traffic: Traffic) -> void:
	for crossing: Dictionary in traffic.pedestrian_crossings:
		var a: Vector3 = crossing["a"]
		var b: Vector3 = crossing["b"]
		var away: Vector3 = crossing["away"]
		var ends := [Vector2(a.x, a.z), Vector2(b.x, b.z)]
		var tails := PackedVector2Array()
		var connects: Array = []
		for p: Vector3 in [a, b]:
			var target := p + away * 8.0
			var tail := Vector2(target.x, target.z)
			var nearest := INF
			var snap := Vector2.INF
			var best_loop := -1
			var best_s := 0.0
			var best_dir := 1
			for index in _loops_near(target, 5.0):
				var loop: Dictionary = _loops[index]
				if not loop.get("city_crossing", {}).is_empty():
					continue
				var poly: PackedVector2Array = loop["pts"]
				var cum: PackedFloat32Array = loop["cum"]
				for i in poly.size():
					var pa := poly[i]
					var pb := poly[(i + 1) % poly.size()]
					var q := Geometry2D.get_closest_point_to_segment(tail, pa, pb)
					var distance := q.distance_to(tail)
					if distance < nearest:
						nearest = distance
						snap = q
						best_loop = int(index)
						best_s = cum[i] + pa.distance_to(q)
						best_dir = int(loop["dir"])
			if nearest < 3.0 and best_loop >= 0:
				tails.append(snap)
				connects.append({"loop": best_loop, "s": best_s, "dir": best_dir})
		if tails.size() != 2:
			continue
		var ring := PackedVector2Array([ends[0], ends[1], tails[1], ends[1], ends[0], tails[0]])
		var cross_idx := _loops.size()
		_add_loop(ring, 1, [0, 3], {"traffic": traffic, "site": crossing, "connects": connects})
		if _loops.size() > cross_idx:
			var cloop: Dictionary = _loops[cross_idx]
			var ccum: PackedFloat32Array = cloop["cum"]
			# Register crossing entry points on each connected sidewalk loop so walkers
			# can naturally turn onto a crossing and continue along the opposite sidewalk.
			for k in 2:
				var conn: Dictionary = connects[k]
				var sw_loop := int(conn["loop"])
				if not _crossing_entries.has(sw_loop):
					_crossing_entries[sw_loop] = []
				var entry_s := float(ccum[5]) if k == 0 else float(ccum[2])
				(_crossing_entries[sw_loop] as Array).append({"cross_loop": cross_idx, "entry_s": entry_s, "pos": tails[k]})


## True when a pavement loop (sampled every 4 m along each side, its
## crossings at the ends left out) runs over another road's carriageway for
## more than 30 m - longer than any side road's mouth it crosses.
static func _loop_on_carriageway(ring: PackedVector2Array, roads: Array, own: Array) -> bool:
	var half := ring.size() / 2
	var on := 0
	for side in 2:
		var i0 := side * half
		for i in range(i0, i0 + half - 1):
			var a := ring[i]
			var b := ring[i + 1]
			var n := maxi(1, int(a.distance_to(b) / 4.0))
			for k in n + 1:
				var q := a.lerp(b, float(k) / n)
				for rd in roads:
					if rd == own:
						continue
					var rp: PackedVector3Array = rd[1]
					var hw := float(rd[2]) * 0.5 + 0.3
					for j in rp.size() - 1:
						var cp := Geometry2D.get_closest_point_to_segment(q, Vector2(rp[j].x, rp[j].z), Vector2(rp[j + 1].x, rp[j + 1].z))
						if cp.distance_to(q) < hw:
							on += 1
							if on * 4 > 30:
								return true
							break
	return false


func _add_loop(pts: PackedVector2Array, dir: int, crossings := [], city_crossing := {}) -> void:
	var cum := PackedFloat32Array([0.0])
	for i in pts.size():
		cum.append(cum[i] + pts[i].distance_to(pts[(i + 1) % pts.size()]))
	var length := cum[pts.size()]
	if length < 20.0:
		return
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	var idx := _loops.size()
	_loops.append({"pts": pts, "cum": cum, "len": length, "dir": dir, "rect": r, "crossings": crossings, "city_crossing": city_crossing})
	for cx in range(floori(r.position.x / 100.0), floori(r.end.x / 100.0) + 1):
		for cz in range(floori(r.position.y / 100.0), floori(r.end.y / 100.0) + 1):
			var k := Vector2i(cx, cz)
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(idx)


## Point and direction at arc length s round loop l.
func _sample(l: Dictionary, s: float) -> Array:
	var pts: PackedVector2Array = l["pts"]
	var cum: PackedFloat32Array = l["cum"]
	s = fposmod(s, float(l["len"]))
	var lo := 0
	var hi := pts.size()
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var a := pts[lo]
	var b := pts[(lo + 1) % pts.size()]
	var seg := maxf(cum[lo + 1] - cum[lo], 0.001)
	return [a.lerp(b, (s - cum[lo]) / seg), (b - a) / seg, lo]


func _focus() -> Vector3:
	var vn := game.vehicle_node()
	if vn != null and is_instance_valid(vn):
		return vn.global_position
	return game.player.global_position


func _loops_near(p: Vector3, r: float) -> Array:
	var out := {}
	for cx in range(floori((p.x - r) / 100.0), floori((p.x + r) / 100.0) + 1):
		for cz in range(floori((p.z - r) / 100.0), floori((p.z + r) / 100.0) + 1):
			for i in _grid.get(Vector2i(cx, cz), []):
				out[i] = true
	return out.keys()


## Hidden from the camera: behind it, or far enough off not to notice.
func _unseen(p: Vector3, far: float) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return true
	var to := p - cam.global_position
	if to.length() > far:
		return true
	return to.normalized().dot(-cam.global_basis.z) < 0.25


func _spawn(li: int, s: float) -> void:
	var l: Dictionary = _loops[li]
	var is_city_cross := not (l["city_crossing"] as Dictionary).is_empty()
	var spd := _rng.randf_range(1.05, 1.5)
	_people.append({"loop": li, "s": s, "dir": 1 if is_city_cross else int(l["dir"]) * (1 if _rng.randf() < 0.85 else -1),
		"speed": spd, "vel_cur": spd, "body": _rng.randi() % maxi(_mmis.size(), 1), "seed": _rng.randf(),
		"top": TOPS[_rng.randi() % TOPS.size()], "scale": _rng.randf_range(0.93, 1.06), "lane": _rng.randf_range(-0.35, 0.35),
		"stride": _rng.randf() * 3.0, "look": 0.0, "glance": 0.0, "glance_t": _rng.randf_range(0.7, 2.4),
		"state": "walk", "t": 0.0, "goal": Vector3.ZERO, "pos": Vector3.ZERO, "yaw": 0.0, "walk": 1.0,
		"browsed": false, "dodge": 0.0, "avoid": Vector2.ZERO, "pace": 1.0, "crossed": false, "cross_cd": 0.0, "waiting": false})


func _populate(focus: Vector3) -> void:
	var want: Array = []   # [loop, s] slots in range
	for li in _loops_near(focus, NEAR):
		var l: Dictionary = _loops[li]
		var step := SPACING / maxf(density, 0.05)
		var city: Dictionary = l["city_crossing"]
		if not city.is_empty():
			var site: Dictionary = city["site"]
			var kerb: Vector3 = site["a"]
			if focus.distance_squared_to(kerb) < 58.0 * 58.0 and not _people.any(func(pr): return pr["loop"] == li):
				want.append([li, float(l["cum"][2])])
			continue
		var s := fposmod(float(li) * 7.3, step)
		while s < float(l["len"]):
			var sp: Array = _sample(l, s)
			if (sp[0] as Vector2).distance_to(Vector2(focus.x, focus.z)) < NEAR:
				want.append([li, s])
			s += step
	var missing := want.size() - _people.size()
	if missing <= 0 or want.is_empty():
		return
	for i in mini(missing, 30 if _first else 4):
		var w: Array = want[_rng.randi() % want.size()]
		var city_route: bool = not _loops[w[0]]["city_crossing"].is_empty()
		if city_route and _people.any(func(pr): return pr["loop"] == w[0]):
			continue
		var jitter := 1.0 if city_route else 4.0
		var s2: float = float(w[1]) + _rng.randf_range(-jitter, jitter)
		var sp2: Array = _sample(_loops[w[0]], s2)
		if sp2[2] in _loops[w[0]]["crossings"]:
			continue
		var p := Vector3(sp2[0].x, focus.y, sp2[0].y)
		if not _first and not _unseen(p, 70.0):
			continue
		var clear := true
		for q in _people:
			if (q["pos"] as Vector3).distance_to(p) < 2.5:
				clear = false
				break
		if clear:
			_spawn(int(w[0]), s2)


func _process(dt: float) -> void:
	if game == null or _mmis.is_empty() or game.state != "play" or get_tree().paused:
		return
	var focus := _focus()
	_acc += dt
	if _acc > 0.4 or _first:
		_acc = 0.0
		_populate(focus)
		_first = false
	var me := game.player.global_position
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else me
	_island_traffic = get_tree().get_first_node_in_group("island_traffic") as IslandTraffic
	_collect_vehicles(focus)
	_queue_up()
	var keep: Array = []
	var crossing_people := PackedVector3Array()
	var occupied := {}
	for city: CityWorld in [game.world, game.world.mainland]:
		if city != null and city.traffic != null:
			city.traffic.pedestrian_obstacles.clear()
	for pr in _people:
		_step(pr, dt, me, eye)
		var p: Vector3 = pr["pos"]
		if pr["state"] == "gone":
			continue
		# Out of range: they leave only off camera (or once they're specks).
		var dd := Vector2(p.x, p.z).distance_to(Vector2(focus.x, focus.z))
		if dd > DROP or dd > KEEP and _unseen(p, 70.0):
			continue
		keep.append(pr)
		if pr.get("crossing", false):
			var city: Dictionary = _loops[pr["loop"]]["city_crossing"]
			if city.is_empty():
				crossing_people.append(p)
			else:
				var traffic: Traffic = city["traffic"]
				var site: Dictionary = city["site"]
				var a: Vector3 = site["a"]
				var b: Vector3 = site["b"]
				if not occupied.has(a):
					occupied[a] = true
					# Hold every lane until the last pedestrian reaches the curb.
					var points := ceili(a.distance_to(b) / 3.2)
					for i in range(1, points):
						traffic.pedestrian_obstacles.append(a.lerp(b, float(i) / points))
	if _island_traffic != null:
		_island_traffic.crossing_people = crossing_people
	_people = keep
	_draw_people()


## Walkers on the same loop and side of the pavement who are closing on
## someone ahead slow to that person's pace (no walking through people).
## pr["pace"] is the share of their own speed they walk at this frame.
func _queue_up() -> void:
	var by_loop := {}
	for pr in _people:
		pr["pace"] = 1.0
		if pr["state"] != "walk":
			continue
		var k := Vector2i(int(pr["loop"]), int(pr["dir"]))
		if not by_loop.has(k):
			by_loop[k] = []
		(by_loop[k] as Array).append(pr)
	for k in by_loop:
		var list: Array = by_loop[k]
		if list.size() < 2:
			continue
		var ln := float((_loops[(k as Vector2i).x] as Dictionary)["len"])
		for a: Dictionary in list:
			for b: Dictionary in list:
				if is_same(a, b) or absf(float(a["lane"]) - float(b["lane"])) > 0.55:
					continue
				# Metres from a forward to b along the walking direction.
				var gap := fposmod((float(b["s"]) - float(a["s"])) * float(a["dir"]), ln)
				if gap < 1.6 and float(a["speed"]) > float(b["speed"]) * float(b["pace"]):
					var p := float(b["speed"]) * float(b["pace"]) / float(a["speed"])
					a["pace"] = minf(float(a["pace"]), lerpf(p, 1.0, clampf((gap - 0.9) / 0.7, 0.0, 1.0)))


func _crossing_clear(loop: Dictionary, index: int) -> bool:
	var city: Dictionary = loop["city_crossing"]
	if not city.is_empty():
		var site: Dictionary = city["site"]
		var midpoint := (site["a"] as Vector3).lerp(site["b"], 0.5)
		if _focus().distance_squared_to(midpoint) > 60.0 * 60.0:
			return false
		var vehicle := game.vehicle_node()
		return (city["traffic"] as Traffic).pedestrian_crossing_clear(site,
			vehicle.global_position if vehicle else Vector3.INF)
	if _island_traffic == null:
		return true
	var points: PackedVector2Array = loop["pts"]
	return not _island_traffic.crossing_blocked(points[index], points[(index + 1) % points.size()])


func _collect_vehicles(focus: Vector3) -> void:
	_vehicles.clear()
	var max_d2 := (NEAR + 16.0) * (NEAR + 16.0)
	var f2 := Vector2(focus.x, focus.z)
	for car_v in game.cars.values():
		var car := car_v as Car
		if car == null or not is_instance_valid(car):
			continue
		var cp := Vector2(car.global_position.x, car.global_position.z)
		if cp.distance_squared_to(f2) > max_d2:
			continue
		var sz: Vector3 = car.spec["size"]
		var rad := maxf(sz.x * 0.5, 0.95)
		_vehicles.append([cp, Vector2(car.linear_velocity.x, car.linear_velocity.z), rad])
	if game.traffic_bodies != null:
		for entry: Array in game.traffic_bodies.city_cars():
			var id := int(entry[0])
			var xf: Transform3D = entry[1]
			var tr: Traffic = entry[2]
			var cp := Vector2(xf.origin.x, xf.origin.z)
			if cp.distance_squared_to(f2) > max_d2:
				continue
			var spd := tr.car_speed(id)
			var fwd := -xf.basis.z
			_vehicles.append([cp, Vector2(fwd.x, fwd.z).normalized() * spd, 1.05])
	if _island_traffic != null:
		for c: Dictionary in _island_traffic.cars:
			if float(c["wait"]) > 0.0:
				continue
			var sp: Array = _island_traffic._sample(_island_traffic.lanes[c["lane"]], float(c["s"]))
			var p3: Vector3 = sp[0]
			var cp := Vector2(p3.x, p3.z)
			if cp.distance_squared_to(f2) > max_d2:
				continue
			var d3: Vector3 = sp[1]
			_vehicles.append([cp, Vector2(d3.x, d3.z).normalized() * float(c["v"]), 1.05])


## Checks if a nearby moving or encroaching vehicle threatens a pedestrian at `pos`.
## Returns [pause: bool, step_back: Vector2, look_at: Vector2] (look_at == Vector2.INF when none).
func _vehicle_hazard(pos: Vector2) -> Array:
	var pause := false
	var escape := Vector2.ZERO
	var look_at := Vector2.INF
	var closest_threat := INF
	for v: Array in _vehicles:
		var vp: Vector2 = v[0]
		var vv: Vector2 = v[1]
		var vr: float = float(v[2])
		var to_ped := pos - vp
		var dist2 := to_ped.length_squared()
		if dist2 > 144.0:
			continue
		var vspeed := vv.length()
		var dist := sqrt(dist2)
		if vspeed > 1.1:
			var vdir := vv / vspeed
			var ahead := to_ped.dot(vdir)
			var lat_signed := to_ped.cross(vdir)
			var lat := absf(lat_signed)
			var look_d := clampf(3.2 + vspeed * 0.95, 3.2, 12.0)
			if ahead > -1.8 and ahead < look_d and lat < vr + 2.2:
				pause = true
				var away := (to_ped - vdir * ahead)
				if away.length_squared() < 0.01:
					away = Vector2(-vdir.y, vdir.x)
				else:
					away = away.normalized()
				var urgency := clampf(1.0 - maxf(ahead, 0.0) / look_d, 0.25, 1.0) * clampf(1.0 - lat / (vr + 2.2), 0.2, 1.0)
				escape += away * urgency * 1.45
				if dist < closest_threat:
					closest_threat = dist
					look_at = vp
		elif dist < vr + 1.15 and dist > 0.01:
			# Stationary or creeping car encroaching on the pavement: step cleanly around it.
			var away := to_ped / dist
			escape += away * clampf((vr + 1.15 - dist) / 1.15, 0.0, 1.0) * 1.1
			if dist < closest_threat:
				closest_threat = dist
				look_at = vp
	return [pause, escape.limit_length(1.35), look_at]


func _transfer_to_sidewalk(pr: Dictionary, conn: Dictionary, cur_pos: Vector2) -> void:
	var new_loop := int(conn["loop"])
	var new_s := float(conn["s"])
	var new_dir := int(conn["dir"]) * (1 if _rng.randf() < 0.8 else -1)
	var nl: Dictionary = _loops[new_loop]
	var sp := _sample(nl, new_s)
	var d: Vector2 = (sp[1] as Vector2) * float(new_dir)
	var side := Vector2(-d.y, d.x)
	var new_base: Vector2 = (sp[0] as Vector2) + side * float(pr["lane"])
	pr["loop"] = new_loop
	pr["s"] = new_s
	pr["dir"] = new_dir
	pr["crossing"] = false
	pr["crossed"] = false
	pr["waiting"] = false
	pr["dodge"] = 0.0
	pr["cross_cd"] = _rng.randf_range(14.0, 26.0)
	# Absorb any tiny lane offset smoothly into avoid so there is zero position jump.
	var residual := cur_pos - new_base
	pr["avoid"] = residual.limit_length(1.1) if residual.length() < 1.5 else Vector2.ZERO


func _step(pr: Dictionary, dt: float, me: Vector3, eye: Vector3) -> void:
	var l: Dictionary = _loops[pr["loop"]]
	var state: String = pr["state"]
	var had_pos := (pr["pos"] as Vector3) != Vector3.ZERO
	var prev_xz := Vector2((pr["pos"] as Vector3).x, (pr["pos"] as Vector3).z)
	var p: Vector3
	var fwd := Vector2.ZERO
	var base_speed := maxf(float(pr["speed"]), 0.4)
	var vel_cur := float(pr["vel_cur"])
	var avoid: Vector2 = pr["avoid"]
	pr["cross_cd"] = maxf(float(pr["cross_cd"]) - dt, 0.0)
	pr["waiting"] = false
	var hazard_look := Vector2.INF

	match state:
		"walk":
			var target_v := base_speed * float(pr["pace"])
			var crossings: Array = l["crossings"]
			var cur_s := float(pr["s"])
			var dir_sgn := float(pr["dir"])
			var cur_sp := _sample(l, cur_s)
			var in_crossing := bool(pr.get("crossing", false))
			# Look ahead ~1.15 m for a blocked crossing so walkers decelerate smoothly to the kerb.
			if not in_crossing and not crossings.is_empty():
				var probe_sp := _sample(l, cur_s + dir_sgn * 1.15)
				if probe_sp[2] in crossings and not _crossing_clear(l, int(probe_sp[2])):
					target_v = 0.0
					pr["waiting"] = true
			# Check nearby vehicles on or encroaching on the pavement.
			var check_pos := prev_xz if had_pos else (cur_sp[0] as Vector2)
			var haz := _vehicle_hazard(check_pos)
			var veh_pause: bool = haz[0]
			var veh_escape: Vector2 = haz[1]
			hazard_look = haz[2]
			if veh_pause and not in_crossing:
				target_v = 0.0
				pr["waiting"] = true
			var accel_rate := 3.4 if target_v < vel_cur else 2.2
			vel_cur = move_toward(vel_cur, target_v, dt * accel_rate)
			var distance := vel_cur * dt
			var next := cur_s + dir_sgn * distance
			var sp := _sample(l, next)
			if sp[2] in crossings and not in_crossing:
				if not _crossing_clear(l, int(sp[2])):
					next = cur_s
					sp = cur_sp
					distance = 0.0
					vel_cur = 0.0
					pr["waiting"] = true
			pr["s"] = next
			var now_crossing: bool = sp[2] in crossings
			pr["crossing"] = now_crossing
			if now_crossing:
				pr["crossed"] = true
			var d: Vector2 = (sp[1] as Vector2) * dir_sgn
			var side := Vector2(-d.y, d.x)
			var base: Vector2 = (sp[0] as Vector2) + side * float(pr["lane"])
			# End of a city crossing: continue seamlessly onto the destination sidewalk
			# instead of looping back and forth across the same zebra forever.
			var city_c: Dictionary = l["city_crossing"]
			if not city_c.is_empty() and bool(pr["crossed"]) and not now_crossing:
				var seg_idx := int(sp[2])
				var connects: Array = city_c.get("connects", [])
				if connects.size() == 2 and (seg_idx == 2 or seg_idx == 5):
					var dest_conn: Dictionary = connects[1] if seg_idx == 2 else connects[0]
					_transfer_to_sidewalk(pr, dest_conn, base + side * float(pr["dodge"]) + avoid)
					l = _loops[pr["loop"]]
					sp = _sample(l, float(pr["s"]))
					d = (sp[1] as Vector2) * float(pr["dir"])
					side = Vector2(-d.y, d.x)
					base = (sp[0] as Vector2) + side * float(pr["lane"])
					avoid = pr["avoid"]
			# Sidewalk walkers may occasionally turn onto a crossing when passing its entry tail.
			elif city_c.is_empty() and float(pr["cross_cd"]) <= 0.0 and not now_crossing:
				var entries: Array = _crossing_entries.get(int(pr["loop"]), [])
				for ent: Dictionary in entries:
					var epos: Vector2 = ent["pos"]
					if (sp[0] as Vector2).distance_to(epos) < 1.35:
						pr["cross_cd"] = _rng.randf_range(12.0, 22.0)
						var cli := int(ent["cross_loop"])
						var on_cross := 0
						for other in _people:
							if int(other["loop"]) == cli:
								on_cross += 1
						if on_cross < 2 and _rng.randf() < 0.30:
							var old_p := base + side * float(pr["dodge"]) + avoid
							pr["loop"] = cli
							pr["s"] = float(ent["entry_s"])
							pr["dir"] = 1
							pr["crossed"] = false
							pr["crossing"] = false
							pr["dodge"] = 0.0
							l = _loops[cli]
							sp = _sample(l, float(pr["s"]))
							d = (sp[1] as Vector2) * float(pr["dir"])
							side = Vector2(-d.y, d.x)
							base = (sp[0] as Vector2) + side * float(pr["lane"])
							avoid = (old_p - base).limit_length(1.1)
						break
			var dodge := 0.0 if now_crossing else _dodge_for(base, d, side, me, eye, float(pr["dodge"]))
			pr["dodge"] = move_toward(float(pr["dodge"]), dodge, dt * 1.1)
			# Smooth steered avoidance around very close hero or approaching vehicles (no sideways shove-sliding).
			var want_avoid := veh_escape
			var candidate := base + side * float(pr["dodge"]) + avoid
			var rel_hero := Vector2(me.x - candidate.x, me.z - candidate.y)
			var hdist := rel_hero.length()
			if not now_crossing and hdist < 1.05 and hdist > 0.001:
				var away_h := -rel_hero / hdist
				var tang := Vector2(-away_h.y, away_h.x)
				if tang.dot(d) < 0.0:
					tang = -tang
				var steer_away := (away_h * 0.72 + tang * 0.68).normalized()
				want_avoid += steer_away * clampf((1.05 - hdist) / 1.05, 0.25, 1.0) * 0.85
			want_avoid = want_avoid.limit_length(1.35)
			var avoid_rate := 1.45 if want_avoid.length_squared() > avoid.length_squared() else 0.95
			avoid = avoid.move_toward(want_avoid, dt * avoid_rate)
			pr["avoid"] = avoid
			var q: Vector2 = base + side * float(pr["dodge"]) + avoid
			p = Vector3(q.x, 0.0, q.y)
			fwd = d
			# A shop door at hand: look in the window, or go in.
			if not pr["browsed"] and not now_crossing and not bool(pr["waiting"]):
				for dr in _doors:
					var dp: Vector3 = dr[0]
					if Vector2(dp.x, dp.z).distance_to(q) < 2.2 and game.empire.business_at(String(dr[2])) == null:
						pr["browsed"] = true
						var roll := _rng.randf()
						var occupied := CityLife.is_taken(game.empire, String(dr[2]))
						if roll < 0.22 and occupied:
							pr["state"] = "enter"
							pr["goal"] = dp - (dr[1] as Vector3) * 3.5
						elif roll < 0.4:
							pr["state"] = "browse"
							pr["t"] = _rng.randf_range(2.0, 5.0)
							pr["goal"] = dp
						break
		"browse":
			vel_cur = move_toward(vel_cur, 0.0, dt * 3.6)
			var bp := prev_xz
			var haz := _vehicle_hazard(bp)
			var want_avoid: Vector2 = haz[1]
			hazard_look = haz[2]
			var rel_b := Vector2(me.x - bp.x, me.z - bp.y)
			var bdist := rel_b.length()
			if bdist < 0.95 and bdist > 0.001:
				want_avoid += (-rel_b / bdist) * clampf((0.95 - bdist) / 0.95, 0.25, 1.0) * 0.65
			var step_b := want_avoid.limit_length(1.2) * dt * 1.1
			bp += step_b
			p = Vector3(bp.x, 0.0, bp.y)
			var g: Vector3 = pr["goal"]
			fwd = Vector2(g.x - p.x, g.z - p.z).normalized()
			pr["t"] = float(pr["t"]) - dt
			if float(pr["t"]) <= 0.0:
				pr["state"] = "walk"
		"enter":
			p = pr["pos"]
			p.y = 0.0
			var g2: Vector3 = pr["goal"]
			var to := Vector2(g2.x - p.x, g2.z - p.z)
			if to.length() < 0.3:
				pr["state"] = "gone"
				return
			fwd = to.normalized()
			vel_cur = move_toward(vel_cur, base_speed, dt * 2.5)
			var mv := fwd * minf(vel_cur * dt, to.length())
			p += Vector3(mv.x, 0.0, mv.y)
	pr["vel_cur"] = vel_cur

	# Measure actual ground movement so diagonal avoidance steps steer heading & stride cleanly.
	var actual_dist := 0.0
	var actual_speed := 0.0
	if had_pos:
		var move_delta := Vector2(p.x, p.z) - prev_xz
		var dlen := move_delta.length()
		if dlen < 2.0:
			actual_dist = dlen
			actual_speed = dlen / maxf(dt, 0.001)
			if actual_speed > 0.22 and state != "browse":
				var move_dir := move_delta / dlen
				var blend := clampf((actual_speed - 0.22) / 0.65, 0.0, 0.85)
				fwd = fwd.lerp(move_dir, blend).normalized() if fwd != Vector2.ZERO else move_dir
	var target_walk := clampf(actual_speed / base_speed, 0.0, 1.0) if had_pos else (1.0 if state == "walk" else 0.0)
	var walk_rate := 7.0 if target_walk < float(pr["walk"]) else 5.0
	pr["walk"] = lerpf(float(pr["walk"]), target_walk, 1.0 - exp(-walk_rate * dt))
	if pr["walk"] < 0.01 and target_walk <= 0.0:
		pr["walk"] = 0.0
	if actual_dist > 0.0004:
		# Keep foot speed locked to ground speed even while decelerating (shader scales swing by walk).
		var eff_walk := maxf(float(pr["walk"]), 0.42)
		pr["stride"] = float(pr["stride"]) + actual_dist / eff_walk

	# Natural head glances: check traffic at crossings, scan shop windows, watch approaching cars or hero.
	pr["glance_t"] = float(pr["glance_t"]) - dt
	if float(pr["glance_t"]) <= 0.0:
		if bool(pr["waiting"]):
			# Alternate looking left/right along the road for traffic.
			var cur_g := float(pr["glance"])
			var sgn := -1.0 if cur_g >= 0.0 else 1.0
			pr["glance"] = sgn * _rng.randf_range(0.50, 0.78)
			pr["glance_t"] = _rng.randf_range(1.1, 2.0)
		elif state == "browse":
			pr["glance"] = _rng.randf_range(-0.42, 0.42)
			pr["glance_t"] = _rng.randf_range(1.4, 2.8)
		else:
			pr["glance"] = _rng.randf_range(-0.26, 0.26) if _rng.randf() < 0.45 else 0.0
			pr["glance_t"] = _rng.randf_range(2.2, 4.5)
	var look := float(pr["glance"])
	var rel := Vector2(me.x - p.x, me.z - p.z)
	var dist := rel.length()
	if hazard_look != Vector2.INF and fwd != Vector2.ZERO:
		var hrel := hazard_look - Vector2(p.x, p.z)
		if hrel.length_squared() > 0.04:
			look = -clampf(fwd.angle_to(hrel), -0.95, 0.95)
	elif dist < 6.0 and fwd != Vector2.ZERO:
		var ang := fwd.angle_to(rel)
		if absf(ang) < 1.6:
			var hero_look := -clampf(ang, -0.9, 0.9) * (1.0 - dist / 6.0)
			look = lerpf(look, hero_look, clampf(1.0 - dist / 6.0, 0.0, 1.0))
	pr["look"] = lerpf(float(pr["look"]), look, 1.0 - exp(-4.5 * dt))
	p.y = float(_ground.call(p.x, p.z))
	pr["pos"] = p
	if fwd != Vector2.ZERO:
		var target_yaw := atan2(-fwd.x, -fwd.y)
		pr["yaw"] = target_yaw if not had_pos else lerp_angle(float(pr["yaw"]), target_yaw, 1.0 - exp(-7.5 * dt))


## The sidestep (m along `side`) that keeps a walker at `base` heading `d`
## clear of you and of the line from the camera to you, for things within
## a few metres ahead. Picks the side they're already on; within ±1.1 m.
func _dodge_for(base: Vector2, d: Vector2, side: Vector2, me: Vector3, eye: Vector3, cur: float) -> float:
	var want := 0.0
	var hero := Vector2(me.x, me.z)
	var cam := Vector2(eye.x, eye.z)
	var obstacles: Array = [hero]
	if game.driving == "" and hero.distance_to(cam) < 9.0:
		# Points along the camera→you line (people crossing it fill the view).
		obstacles.append(hero.lerp(cam, 0.4))
		obstacles.append(hero.lerp(cam, 0.8))
		obstacles.append(cam)
	for o: Vector2 in obstacles:
		var v := o - base
		var along := v.dot(d)
		if along < -0.8 or along > 4.5:
			continue
		var lat := v.dot(side)
		var clear := 1.15
		if absf(lat - cur) < clear:
			var away := lat - clear if lat >= cur else lat + clear
			if absf(away) <= 1.1 and absf(away) > absf(want):
				want = away
			elif absf(away) > 1.1:
				want = clampf(away, -1.1, 1.1)
	return want


func _draw_people() -> void:
	var by_body: Array = []
	for i in _mmis.size():
		by_body.append([])
	for pr in _people:
		(by_body[int(pr["body"]) % _mmis.size()] as Array).append(pr)
	for i in _mmis.size():
		var mm: MultiMesh = (_mmis[i] as MultiMeshInstance3D).multimesh
		var list: Array = by_body[i]
		if mm.instance_count != list.size():
			mm.instance_count = list.size()
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 20)
		var j := 0
		for pr in list:
			var b := Basis(Vector3.UP, float(pr["yaw"])).scaled(_person_scale(pr))
			var o: Vector3 = pr["pos"]
			for r in 3:
				buf[j] = b.x[r]
				buf[j + 1] = b.y[r]
				buf[j + 2] = b.z[r]
				buf[j + 3] = o[r]
				j += 4
			var c: Color = pr["top"]
			buf[j] = c.r; buf[j + 1] = c.g; buf[j + 2] = c.b; buf[j + 3] = 1.0
			buf[j + 4] = float(pr["stride"]); buf[j + 5] = float(pr["seed"]); buf[j + 6] = float(pr["walk"]); buf[j + 7] = float(pr["look"])
			j += 8
		if not list.is_empty():
			mm.buffer = buf
		var mmi := _mmis[i] as MultiMeshInstance3D
		mmi.custom_aabb = AABB(_focus() - Vector3(KEEP, 20, KEEP), Vector3(KEEP * 2, 60, KEEP * 2))
	_draw_blobs()


static func _person_scale(person: Dictionary) -> Vector3:
	var width := lerpf(0.92, 1.09, fposmod(float(person["seed"]) * 7.31, 1.0))
	return Vector3(width, 1.0, lerpf(1.0, width, 0.58)) * float(person["scale"])


## Contact shadows: flat on the pavement under each person, a touch
## lighter as they walk away out of the near range (they fade with them).
func _draw_blobs() -> void:
	if _blobs == null:
		return
	var mm := _blobs.multimesh
	if mm.instance_count != _people.size():
		mm.instance_count = _people.size()
	if _people.is_empty():
		return
	var focus := _focus()
	var buf := PackedFloat32Array()
	buf.resize(_people.size() * 16)
	var j := 0
	for pr in _people:
		var o: Vector3 = pr["pos"]
		var scale := _person_scale(pr)
		scale.y = 1.0
		var b := Basis(Vector3.UP, float(pr["yaw"])).scaled(scale)
		for r in 3:
			buf[j] = b.x[r]
			buf[j + 1] = b.y[r]
			buf[j + 2] = b.z[r]
			buf[j + 3] = o[r] + (0.035 if r == 1 else 0.0)
			j += 4
		var d := Vector2(o.x - focus.x, o.z - focus.z).length()
		buf[j] = clampf((NEAR + 6.0 - d) / 12.0, 0.0, 1.0)
		buf[j + 1] = 0.0; buf[j + 2] = 0.0; buf[j + 3] = 0.0
		j += 4
	mm.buffer = buf
	_blobs.custom_aabb = AABB(focus - Vector3(KEEP, 20, KEEP), Vector3(KEEP * 2, 60, KEEP * 2))


## How many people are out (for the debug readout / tests).
func count() -> int:
	return _people.size()
