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
var _loops: Array = []        # {pts, cum, len, dir, rect, crossings, city_crossing, kind}
var _grid := {}               # Vector2i(100 m cell) -> [loop index]
var _people: Array = []       # see _spawn
var _mmis: Array = []         # MultiMeshInstance3D per body
var _blobs: MultiMeshInstance3D   # contact shadows (one draw for everyone)
var _doors: Array = []        # [Vector3 door, Vector3 outward, unit id]
var _door_grid := {}          # Vector2i(100 m cell) -> [door entry]
var _rng := RandomNumberGenerator.new()
var _acc := 0.0
var _first := true
var _ground: Callable
var _island_traffic: IslandTraffic
var _island_check_t := 0.0
var _vehicles: Array = []          # [[Vector2 pos, Vector2 vel, float radius]]
var _panic_calls: Array[Vector2] = []
var _crossing_entries := {}        # sidewalk loop idx -> [{cross_loop, entry_s, pos}]
var _crossing_counts := {}         # cross loop idx -> active count (rebuilt once per frame)
var _eff_density := 1.0
var _speed_scale := 1.0
var _browse_scale := 1.0
var _cur_hour := 12.0
var _cur_weather := "sunny"
var _target_count := 0
var _last_pop_focus := Vector3.INF
var _last_pop_density := -1.0


func setup(p_game: EmpireGame) -> void:
	game = p_game
	_rng.seed = 1777
	_ground = func(x: float, z: float) -> float: return game.layout.ground_y(x, z)
	var layouts: Array = [game.layout]
	if game.layout.mainland:
		layouts.append(game.layout.mainland)
	for L: CityLayout in layouts:
		for blk in L.blocks:
			var bkind := String(blk["kind"])
			if bkind not in ["block", "plaza", "park"]:
				continue
			for li in LANES.size():
				var ring := Geometry2D.offset_polygon(blk["poly"], -float(LANES[li]))
				if ring.is_empty() or (ring[0] as PackedVector2Array).size() < 3:
					continue
				_add_loop(ring[0], 1 if li == 0 else -1, [], {}, bkind)
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
	_doors.clear()
	_door_grid.clear()
	for u in game.units:
		if u["kind"] == "shop":
			var dp: Vector3 = Premises.door_point(u)
			var entry := [dp, Premises.outward(u), u["id"]]
			_doors.append(entry)
			var dk := Vector2i(floori(dp.x / 100.0), floori(dp.z / 100.0))
			if not _door_grid.has(dk):
				_door_grid[dk] = []
			(_door_grid[dk] as Array).append(entry)
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


func _add_loop(pts: PackedVector2Array, dir: int, crossings := [], city_crossing := {}, kind := "block") -> void:
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
	_loops.append({"pts": pts, "cum": cum, "len": length, "dir": dir, "rect": r, "crossings": crossings,
		"city_crossing": city_crossing, "kind": kind})
	for cx in range(floori(r.position.x / 100.0), floori(r.end.x / 100.0) + 1):
		for cz in range(floori(r.position.y / 100.0), floori(r.end.y / 100.0) + 1):
			var k := Vector2i(cx, cz)
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(idx)


func _doors_near(q: Vector2) -> Array:
	var x0 := floori((q.x - 2.5) / 100.0)
	var x1 := floori((q.x + 2.5) / 100.0)
	var z0 := floori((q.y - 2.5) / 100.0)
	var z1 := floori((q.y + 2.5) / 100.0)
	if x0 == x1 and z0 == z1:
		return _door_grid.get(Vector2i(x0, z0), [])
	var out: Array = []
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var cell: Array = _door_grid.get(Vector2i(cx, cz), [])
			if not cell.is_empty():
				out.append_array(cell)
	return out


func _district_at(p: Vector3) -> String:
	if game == null or game.layout == null:
		return ""
	if p.x < CityLayout.RIVER_EDGE and game.layout.mainland != null:
		return game.layout.mainland.district(p.x, p.z)
	return game.layout.district(p.x, p.z)


func _update_activity(focus: Vector3) -> void:
	var h := 12.0
	var weather := "sunny"
	if game != null and game.empire != null:
		h = game.empire.hour()
		weather = String(game.empire.weather)
	elif game != null and game.atmosphere != null:
		h = game.atmosphere.hour
		weather = String(game.atmosphere.weather)
	_cur_hour = h
	_cur_weather = weather

	var settings := get_node_or_null("/root/Settings")
	var traffic_preset := float(settings.preset().get("traffic", 1.0)) if settings else 1.0

	var tod_density := 1.0
	var tod_speed := 1.0
	if h >= 7.5 and h <= 9.5:
		tod_density = 1.28
		tod_speed = 1.10
	elif h >= 12.0 and h <= 14.0:
		tod_density = 1.22
		tod_speed = 1.05
	elif h >= 17.0 and h <= 19.5:
		tod_density = 1.32
		tod_speed = 1.09
	elif h >= 23.0 or h < 5.5:
		var dist_name := _district_at(focus)
		var nightlife := dist_name in ["cbd", "waterfront", "midtown"]
		tod_density = 0.44 if nightlife else 0.28
		tod_speed = 0.94
	elif h >= 5.5 and h < 7.5:
		var t := (h - 5.5) / 2.0
		tod_density = lerpf(0.32, 1.28, t)
		tod_speed = lerpf(0.96, 1.10, t)
	elif h > 9.5 and h < 10.5:
		var t := (h - 9.5)
		tod_density = lerpf(1.28, 1.0, t)
		tod_speed = lerpf(1.10, 1.0, t)
	elif h > 19.5 and h < 23.0:
		var t := (h - 19.5) / 3.5
		var dist_name := _district_at(focus)
		var night_base := 0.44 if dist_name in ["cbd", "waterfront", "midtown"] else 0.28
		tod_density = lerpf(1.32, night_base, t)
		tod_speed = lerpf(1.09, 0.94, t)

	var w_density := 1.0
	var w_speed := 1.0
	var w_browse := 1.0
	match weather:
		"rain":
			w_density = 0.65
			w_speed = 1.20
			w_browse = 1.45
		"storm":
			w_density = 0.40
			w_speed = 1.28
			w_browse = 1.75
		"foggy", "fog":
			w_density = 0.85
			w_speed = 0.97
		"heatwave", "haze":
			w_density = 1.08
			w_speed = 0.94

	_eff_density = clampf(density * traffic_preset * tod_density * w_density, 0.08, 2.0)
	_speed_scale = tod_speed * w_speed
	_browse_scale = w_browse


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
	var lkind := String(l.get("kind", "block"))
	var profile := "default"
	var spd := _rng.randf_range(1.08, 1.44)
	if not is_city_cross:
		var wet_bad := _cur_weather in ["rain", "storm"]
		var r := _rng.randf()
		var jog_p := (0.16 if lkind == "park" else (0.09 if _cur_hour >= 5.5 and _cur_hour <= 9.5 else 0.02))
		if wet_bad:
			jog_p *= 0.15
		var rush := (_cur_hour >= 7.5 and _cur_hour <= 9.5) or (_cur_hour >= 17.0 and _cur_hour <= 19.5)
		var comm_p := 0.45 if rush else 0.22
		if r < jog_p:
			profile = "jogger"
			spd = _rng.randf_range(2.25, 2.75)
		elif r < jog_p + comm_p:
			profile = "commuter"
			spd = _rng.randf_range(1.38, 1.66)
		elif r < jog_p + comm_p + (0.34 if lkind in ["park", "plaza"] else 0.20):
			profile = "stroller"
			spd = _rng.randf_range(0.88, 1.15)
	_people.append({"loop": li, "s": s, "dir": 1 if is_city_cross else int(l["dir"]) * (1 if _rng.randf() < 0.85 else -1),
		"speed": spd, "vel_cur": spd * _speed_scale, "profile": profile, "body": _rng.randi() % maxi(_mmis.size(), 1), "seed": _rng.randf(),
		"top": TOPS[_rng.randi() % TOPS.size()], "scale": _rng.randf_range(0.93, 1.06), "lane": _rng.randf_range(-0.35, 0.35),
		"stride": _rng.randf() * 3.0, "look": 0.0, "glance": 0.0, "glance_t": _rng.randf_range(0.7, 2.4),
		"state": "walk", "t": 0.0, "goal": Vector3.ZERO, "pos": Vector3.ZERO, "yaw": 0.0, "walk": 1.0,
		"browsed": false, "dodge": 0.0, "avoid": Vector2.ZERO, "pace": 1.0, "crossed": false, "cross_cd": 0.0,
		"pause_cd": _rng.randf_range(9.0, 26.0), "waiting": false})


func _populate(focus: Vector3) -> void:
	if not _first and _target_count > 0 and _people.size() >= _target_count - 1 \
			and focus.distance_squared_to(_last_pop_focus) < 16.0 * 16.0 \
			and absf(_eff_density - _last_pop_density) < 0.08:
		return
	var want: Array = []   # [loop, s] slots in range
	var step := SPACING / maxf(_eff_density, 0.05)
	for li in _loops_near(focus, NEAR):
		var l: Dictionary = _loops[li]
		var city: Dictionary = l["city_crossing"]
		if not city.is_empty():
			var site: Dictionary = city["site"]
			var kerb: Vector3 = site["a"]
			if focus.distance_squared_to(kerb) < 58.0 * 58.0 and int(_crossing_counts.get(li, 0)) == 0:
				want.append([li, float(l["cum"][2])])
			continue
		var s := fposmod(float(li) * 7.3, step)
		while s < float(l["len"]):
			var sp: Array = _sample(l, s)
			if (sp[0] as Vector2).distance_to(Vector2(focus.x, focus.z)) < NEAR:
				want.append([li, s])
			s += step
	_target_count = want.size()
	_last_pop_focus = focus
	_last_pop_density = _eff_density
	var missing := want.size() - _people.size()
	if missing <= 0 or want.is_empty():
		return
	for i in mini(missing, 30 if _first else 4):
		var w: Array = want[_rng.randi() % want.size()]
		var city_route: bool = not _loops[w[0]]["city_crossing"].is_empty()
		if city_route and int(_crossing_counts.get(w[0], 0)) > 0:
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
			if city_route:
				_crossing_counts[w[0]] = int(_crossing_counts.get(w[0], 0)) + 1


func _process(dt: float) -> void:
	if game == null or _mmis.is_empty() or game.state != "play" or get_tree().paused:
		return
	var focus := _focus()
	_crossing_counts.clear()
	for pr in _people:
		var li := int(pr["loop"])
		if not (_loops[li]["city_crossing"] as Dictionary).is_empty():
			_crossing_counts[li] = int(_crossing_counts.get(li, 0)) + 1
	_acc += dt
	if _acc > 0.4 or _first:
		_acc = 0.0
		_update_activity(focus)
		_populate(focus)
		_first = false
	var me := game.player.global_position
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else me
	if _island_traffic == null or not is_instance_valid(_island_traffic):
		_island_check_t -= dt
		if _island_check_t <= 0.0:
			_island_traffic = get_tree().get_first_node_in_group("island_traffic") as IslandTraffic
			_island_check_t = 1.0 if _island_traffic == null else 0.0
	_collect_vehicles(focus)
	_panic_calls.clear()
	for pr in _people:
		if float(pr.get("fear", 0.0)) > 0.64 and float(pr.get("firsthand", 0.0)) > 0.0:
			var at: Vector3 = pr["pos"]
			_panic_calls.append(Vector2(at.x, at.z))
	_queue_up()
	var keep: Array = []
	var crossing_people := PackedVector3Array()
	var occupied := {}
	for city: CityWorld in [game.world, game.world.mainland]:
		if city != null and city.traffic != null:
			city.traffic.pedestrian_obstacles.clear()
	var fx := focus.x
	var fz := focus.z
	var over_budget := _target_count > 0 and _people.size() > _target_count + 4
	var keep_r := KEEP * 0.72 if over_budget else KEEP
	for pr in _people:
		var p0: Vector3 = pr["pos"]
		var d2_focus := (p0.x - fx) * (p0.x - fx) + (p0.z - fz) * (p0.z - fz) if p0 != Vector3.ZERO else 0.0
		_step(pr, dt, me, eye, d2_focus)
		var p: Vector3 = pr["pos"]
		if pr["state"] == "gone":
			continue
		# Out of range: they leave only off camera (or once they're specks).
		var dd := Vector2(p.x - fx, p.z - fz).length()
		if dd > DROP or dd > keep_r and _unseen(p, 70.0):
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
	if _island_traffic != null and is_instance_valid(_island_traffic):
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
	var live_cars := game.cars.values()
	if game.pursuit != null and game.pursuit.state == "chase":
		live_cars.append(game.pursuit.suspect)
		live_cars.append_array(game.pursuit.police)
	for car_v in live_cars:
		var car := car_v as Car
		if car == null or not is_instance_valid(car):
			continue
		var cp := Vector2(car.global_position.x, car.global_position.z)
		if cp.distance_squared_to(f2) > max_d2:
			continue
		var sz: Vector3 = car.spec["size"]
		var rad := maxf(sz.x * 0.5, 0.95)
		var impact := smoothstep(4.0, 12.0, car.last_impact_strength) * (1.0 - smoothstep(0.0, 1.3, car._time - car.last_impact_time))
		var emergency: bool = car.visual != null and car.visual.siren_on
		_vehicles.append([cp, Vector2(car.linear_velocity.x, car.linear_velocity.z), rad, car.global_position.y, sz.z * 0.5, impact, emergency])
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
			_vehicles.append([cp, Vector2(fwd.x, fwd.z).normalized() * spd, 1.05, xf.origin.y, 2.35, 0.0, false])
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
			_vehicles.append([cp, Vector2(d3.x, d3.z).normalized() * float(c["v"]), 1.05, p3.y, 2.35, 0.0, false])


## Predict the swept body footprint and reject traffic on another deck.
## Result: perceived urgency, lateral dodge and danger position.
func _vehicle_hazard(at: Vector3, heading: Vector2) -> Array:
	var pos := Vector2(at.x, at.z)
	var urgency := 0.0
	var escape := Vector2.ZERO
	var look_at := Vector2.INF
	for v: Array in _vehicles:
		var from: Vector2 = v[0]
		var motion: Vector2 = v[1]
		var radial := pos - from
		if radial.length_squared() > 42.0 * 42.0 or absf(at.y - float(v[3])) > 2.2:
			continue
		var speed := motion.length()
		var dist := radial.length()
		var risk := float(v[5]) * 0.82 * (1.0 - smoothstep(3.0, 15.0, dist))
		var dodge := radial.normalized()
		if speed > 1.2:
			var forward := motion / speed
			var lead := radial.dot(forward)
			var intercept := (lead - float(v[4])) / speed
			var side := radial - forward * lead
			var width := float(v[2]) + lerpf(0.32, 1.45, smoothstep(4.0, 22.0, speed))
			if lead > -float(v[4]) and intercept < 1.65 and side.length() < width:
				var seen := 1.0 if heading.dot(-dodge) > -0.33 or intercept < 0.38 else 0.72
				var approach := 1.0 - smoothstep(0.12, 1.65, intercept)
				risk = maxf(risk, smoothstep(2.2, 11.0, speed) * (0.38 + 0.62 * approach) * seen)
				if side.length_squared() > 0.04:
					dodge = side.normalized()
				else:
					dodge = Vector2(-forward.y, forward.x)
			if bool(v[6]) and lead > 0.0 and intercept < 1.8 and side.length() < 4.3:
				risk = maxf(risk, 0.47 * (1.0 - smoothstep(0.5, 1.8, intercept)))
		if dist < float(v[2]) + 0.9:
			escape += dodge * 0.7
		if risk > urgency:
			urgency = risk
			look_at = from
			escape += dodge * (0.45 + risk)
	return [urgency, escape.limit_length(1.25), look_at]


func _update_fear(pr: Dictionary, at: Vector3, dt: float) -> Array:
	var cadence := float(pr.get("threat_tick", float(pr["seed"]) * 0.11)) - dt
	var hazard: Array = pr.get("threat", [0.0, Vector2.ZERO, Vector2.INF])
	var direct := move_toward(float(pr.get("firsthand", 0.0)), 0.0, dt)
	if cadence <= 0.0:
		cadence = 0.10 + float(pr["seed"]) * 0.045
		var yaw := float(pr["yaw"])
		hazard = _vehicle_hazard(at, Vector2(-sin(yaw), -cos(yaw)))
		pr["threat"] = hazard
		if float(hazard[0]) > 0.55:
			direct = 1.5
	pr["threat_tick"] = cadence
	pr["firsthand"] = direct
	var stimulus := float(hazard[0])
	if stimulus < 0.32:
		for caller in _panic_calls:
			if caller.distance_squared_to(Vector2(at.x, at.z)) < 30.25:
				stimulus = 0.37 + float(pr["seed"]) * 0.14
				break
	var delay := float(pr.get("alarm", 0.0))
	var threshold := lerpf(0.10, 0.38, float(pr["seed"]))
	delay = minf(delay + dt, 0.6) if stimulus > 0.33 else maxf(delay - dt * 1.7, 0.0)
	pr["alarm"] = delay
	var fear := float(pr.get("fear", 0.0))
	var target := minf(1.0, stimulus * 1.45) if delay >= threshold else 0.0
	pr["fear"] = move_toward(fear, target, dt * (4.4 if target > fear else 0.45))
	return hazard


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


func _step(pr: Dictionary, dt: float, me: Vector3, eye: Vector3, d2_focus := 0.0) -> void:
	var l: Dictionary = _loops[pr["loop"]]
	var state: String = pr["state"]
	var had_pos := (pr["pos"] as Vector3) != Vector3.ZERO
	var prev_xz := Vector2((pr["pos"] as Vector3).x, (pr["pos"] as Vector3).z)
	var p: Vector3
	var fwd := Vector2.ZERO
	var profile := String(pr.get("profile", "default"))
	var spd_mult := 1.0 if profile == "jogger" else _speed_scale
	var base_speed := maxf(float(pr["speed"]) * spd_mult, 0.4)
	var vel_cur := float(pr["vel_cur"])
	var avoid: Vector2 = pr["avoid"]
	var far := had_pos and d2_focus > 48.0 * 48.0
	var fear := float(pr.get("fear", 0.0))
	var hazard: Array = [0.0, Vector2.ZERO, Vector2.INF]
	if had_pos and not far:
		hazard = _update_fear(pr, pr["pos"], dt)
		fear = float(pr["fear"])
		if fear > 0.42 and state in ["browse", "pause"]:
			state = "walk"
			pr["state"] = state
			pr["pause_cd"] = 12.0
	elif far and fear > 0.0:
		fear = move_toward(fear, 0.0, dt)
		pr["fear"] = fear
	pr["cross_cd"] = maxf(float(pr["cross_cd"]) - dt, 0.0)
	pr["pause_cd"] = maxf(float(pr.get("pause_cd", 0.0)) - dt, 0.0)
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
			var veh_escape: Vector2 = hazard[1]
			hazard_look = hazard[2]
			var running := fear > 0.42
			if running:
				var previous_direction := float(pr["dir"])
				var other := _sample(l, cur_s - previous_direction * 2.6)
				var same := _sample(l, cur_s + previous_direction * 2.6)
				# Choose a safe direction on the authored path once per scare.
				if not bool(pr.get("fleeing", false)) and not in_crossing and hazard_look != Vector2.INF:
					var reverse_dist := (other[0] as Vector2).distance_squared_to(hazard_look)
					var forward_dist := (same[0] as Vector2).distance_squared_to(hazard_look)
					if other[2] not in crossings and (same[2] in crossings or reverse_dist > forward_dist + 1.0):
						dir_sgn = -previous_direction
						pr["dir"] = int(dir_sgn)
						pr["lane"] = -float(pr["lane"])
				target_v = lerpf(2.4, 4.7, fear) * lerpf(0.85, 1.08, float(pr["seed"]))
				if not in_crossing and _sample(l, cur_s + dir_sgn * 1.4)[2] in crossings:
					target_v = 0.0
			elif float(hazard[0]) > 0.39 and not in_crossing:
				target_v *= 0.25
				pr["waiting"] = true
			pr["fleeing"] = running
			var accel_rate := 5.0 if running else (3.4 if target_v < vel_cur else 2.2)
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
					var old_cli := int(pr["loop"])
					var dest_conn: Dictionary = connects[1] if seg_idx == 2 else connects[0]
					_transfer_to_sidewalk(pr, dest_conn, base + side * float(pr["dodge"]) + avoid)
					_crossing_counts[old_cli] = maxi(int(_crossing_counts.get(old_cli, 1)) - 1, 0)
					l = _loops[pr["loop"]]
					sp = _sample(l, float(pr["s"]))
					d = (sp[1] as Vector2) * float(pr["dir"])
					side = Vector2(-d.y, d.x)
					base = (sp[0] as Vector2) + side * float(pr["lane"])
					avoid = pr["avoid"]
			# Sidewalk walkers may occasionally turn onto a crossing when passing its entry tail.
			elif city_c.is_empty() and float(pr["cross_cd"]) <= 0.0 and not now_crossing and not far:
				var entries: Array = _crossing_entries.get(int(pr["loop"]), [])
				for ent: Dictionary in entries:
					var epos: Vector2 = ent["pos"]
					if (sp[0] as Vector2).distance_to(epos) < 1.35:
						pr["cross_cd"] = _rng.randf_range(12.0, 22.0)
						var cli := int(ent["cross_loop"])
						var on_cross := int(_crossing_counts.get(cli, 0))
						if on_cross < 2 and _rng.randf() < 0.30:
							var old_p := base + side * float(pr["dodge"]) + avoid
							pr["loop"] = cli
							pr["s"] = float(ent["entry_s"])
							pr["dir"] = 1
							pr["crossed"] = false
							pr["crossing"] = false
							pr["dodge"] = 0.0
							_crossing_counts[cli] = on_cross + 1
							l = _loops[cli]
							sp = _sample(l, float(pr["s"]))
							d = (sp[1] as Vector2) * float(pr["dir"])
							side = Vector2(-d.y, d.x)
							base = (sp[0] as Vector2) + side * float(pr["lane"])
							avoid = (old_p - base).limit_length(1.1)
						break
			var dodge := 0.0 if (now_crossing or far) else _dodge_for(base, d, side, me, eye, float(pr["dodge"]))
			pr["dodge"] = move_toward(float(pr["dodge"]), dodge, dt * 1.1)
			# Smooth steered avoidance around very close hero or approaching vehicles (no sideways shove-sliding).
			var want_avoid := veh_escape
			if not far:
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
			if running and not now_crossing and want_avoid.length_squared() > 0.04:
				var streets := game.layout.roads
				if base.x < CityLayout.FAR_SHORE and game.layout.mainland != null:
					streets = game.layout.mainland.roads
				if streets.on_road(base + want_avoid) and not streets.on_road(base):
					want_avoid = Vector2.ZERO
			var avoid_rate := 1.45 if want_avoid.length_squared() > avoid.length_squared() else 0.95
			avoid = avoid.move_toward(want_avoid, dt * avoid_rate)
			pr["avoid"] = avoid
			var q: Vector2 = base + side * float(pr["dodge"]) + avoid
			p = Vector3(q.x, 0.0, q.y)
			fwd = d
			# Secondary sidewalk interactions (shop doors + phone/rest pauses) only within 48 m.
			if not far and fear < 0.28 and not now_crossing and not bool(pr["waiting"]) and profile != "jogger":
				var entered_shop := false
				if not pr["browsed"]:
					for dr in _doors_near(q):
						var dp: Vector3 = dr[0]
						if Vector2(dp.x, dp.z).distance_to(q) < 2.2:
							pr["browsed"] = true
							var roll := _rng.randf()
							var uid := String(dr[2])
							var biz: Business = game.empire.business_at(uid) if game.empire != null else null
							if biz != null:
								var is_open := biz.open and biz.within_hours(_cur_hour)
								if is_open and roll < 0.28:
									pr["state"] = "enter"
									pr["goal"] = dp - (dr[1] as Vector3) * 3.5
									entered_shop = true
								elif roll < (0.50 if is_open else 0.22):
									pr["state"] = "browse"
									pr["t"] = _rng.randf_range(2.2, 5.2) * _browse_scale
									pr["goal"] = dp
									entered_shop = true
							else:
								var occupied := CityLife.is_taken(game.empire, uid) if game.empire != null else false
								if roll < 0.22 and occupied:
									pr["state"] = "enter"
									pr["goal"] = dp - (dr[1] as Vector3) * 3.5
									entered_shop = true
								elif roll < 0.42:
									pr["state"] = "browse"
									pr["t"] = _rng.randf_range(2.0, 5.0) * _browse_scale
									pr["goal"] = dp
									entered_shop = true
							break
				# Natural phone-checking or resting pauses on sidewalks / plazas / parks.
				if not entered_shop and float(pr["pause_cd"]) <= 0.0 and _cur_weather != "storm" and city_c.is_empty():
					var lkind := String(l.get("kind", "block"))
					var pause_chance := 0.22 if lkind in ["plaza", "park"] else (0.14 if profile == "stroller" else 0.07)
					if _cur_weather == "rain":
						pause_chance *= 0.35
					pr["pause_cd"] = _rng.randf_range(18.0, 38.0)
					if _rng.randf() < pause_chance:
						pr["state"] = "pause"
						pr["t"] = _rng.randf_range(4.0, 8.2) if lkind in ["plaza", "park"] else _rng.randf_range(2.2, 5.0)
						var face_v := d.rotated(_rng.randf_range(-0.65, 0.65))
						pr["goal"] = Vector3(q.x + face_v.x * 2.0, 0.0, q.y + face_v.y * 2.0)
		"browse", "pause":
			vel_cur = move_toward(vel_cur, 0.0, dt * 3.6)
			var bp := prev_xz
			var want_avoid := Vector2.ZERO
			if not far:
				want_avoid = hazard[1]
				hazard_look = hazard[2]
				var rel_b := Vector2(me.x - bp.x, me.z - bp.y)
				var bdist := rel_b.length()
				if bdist < 0.95 and bdist > 0.001:
					want_avoid += (-rel_b / bdist) * clampf((0.95 - bdist) / 0.95, 0.25, 1.0) * 0.65
			var step_b := want_avoid.limit_length(1.2) * dt * 1.1
			bp += step_b
			p = Vector3(bp.x, 0.0, bp.y)
			var g: Vector3 = pr["goal"]
			var to_g := Vector2(g.x - p.x, g.z - p.z)
			fwd = to_g.normalized() if to_g.length_squared() > 0.001 else Vector2.ZERO
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
			if actual_speed > 0.22 and state != "browse" and state != "pause":
				var move_dir := move_delta / dlen
				var blend := clampf((actual_speed - 0.22) / 0.65, 0.0, 0.85)
				fwd = fwd.lerp(move_dir, blend).normalized() if fwd != Vector2.ZERO else move_dir
	var target_walk := clampf(actual_speed / maxf(base_speed, 0.4), 0.0, 1.0) if had_pos else (1.0 if state == "walk" else 0.0)
	var walk_rate := 7.0 if target_walk < float(pr["walk"]) else 5.0
	pr["walk"] = lerpf(float(pr["walk"]), target_walk, 1.0 - exp(-walk_rate * dt))
	if pr["walk"] < 0.01 and target_walk <= 0.0:
		pr["walk"] = 0.0
	if actual_dist > 0.0004:
		# Keep foot speed locked to ground speed even while decelerating (shader scales swing by walk).
		var eff_walk := maxf(float(pr["walk"]), 0.42)
		pr["stride"] = float(pr["stride"]) + actual_dist / (eff_walk * (1.0 + 0.58 * fear))

	# Natural head glances: check traffic at crossings, scan shop windows, watch approaching cars or hero.
	if not far:
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
			elif state == "pause":
				pr["glance"] = _rng.randf_range(-0.34, 0.34)
				pr["glance_t"] = _rng.randf_range(1.2, 2.5)
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
			buf[j] = c.r; buf[j + 1] = c.g; buf[j + 2] = c.b; buf[j + 3] = float(pr.get("fear", 0.0))
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
