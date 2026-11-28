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
const SPACING := 26.0         # quality over quantity: cleaner spacing, richer individual behaviour & lower CPU
const LANES := [1.7, 3.0]     # m in from the block edge (as CityWorld)
const MODEL := "res://assets/models/crowd.glb"
const TOPS := [
	Color(0.86, 0.85, 0.82), Color(0.11, 0.12, 0.15), Color(0.54, 0.14, 0.15), Color(0.16, 0.28, 0.48),
	Color(0.34, 0.42, 0.30), Color(0.45, 0.45, 0.48), Color(0.60, 0.36, 0.48), Color(0.19, 0.43, 0.46),
	Color(0.44, 0.24, 0.48), Color(0.82, 0.68, 0.24), Color(0.24, 0.50, 0.68), Color(0.82, 0.44, 0.34),
	Color(0.75, 0.71, 0.61), Color(0.26, 0.27, 0.30), Color(0.20, 0.25, 0.34), Color(0.68, 0.58, 0.46),
	Color(0.38, 0.24, 0.18), Color(0.22, 0.36, 0.28), Color(0.74, 0.28, 0.24), Color(0.56, 0.62, 0.68),
	Color(0.88, 0.82, 0.72), Color(0.32, 0.36, 0.44), Color(0.66, 0.46, 0.28), Color(0.16, 0.18, 0.20),
]
const OBS_RADII := {
	"bench": 0.72, "bin": 0.42, "hydrant": 0.38, "bollard": 0.32, "sign_post": 0.36,
	"bus_shelter": 1.05, "planter": 0.82, "streetlight": 0.38, "traffic_light": 0.42,
	"tree": 0.62, "tree_tall": 0.68,
}

var game: EmpireGame
var density := 1.0
var _loops: Array = []        # {pts, cum, len, dir, rect, crossings, city_crossing, kind}
var _grid := {}               # Vector2i(100 m cell) -> [loop index]
var _people: Array = []       # see _spawn
var _pool: Array = []         # recycled pedestrian dicts (zero GC churn on spawn/despawn)
var _mmis: Array = []         # MultiMeshInstance3D per body
var _by_body: Array = []      # reusable per-body scratch arrays (zero per-frame allocs)
var _mm_bufs: Array[PackedFloat32Array] = []  # persistent buffers (zero per-frame allocs)
var _blob_buf := PackedFloat32Array()
var _blobs: MultiMeshInstance3D   # contact shadows (one draw for everyone)
var _doors: Array = []        # [Vector3 door, Vector3 outward, unit id]
var _door_grid := {}          # Vector2i(100 m cell) -> [door entry]
var _seats: Array = []        # [{pos: Vector3, yaw: float, kind: String, busy: bool}]
var _seat_grid := {}          # Vector2i(100 m cell) -> [seat idx]
var _obs_grid := {}           # Vector2i(50 m cell) -> [[Vector2 pos, float radius]]
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
			# Plazas and parks are walked across, not only round: two inner
			# promenades (the middles of the big squares were empty).
			if bkind in ["plaza", "park"]:
				for inset: float in [9.0, 18.0]:
					var inner := Geometry2D.offset_polygon(blk["poly"], -inset)
					if not inner.is_empty() and (inner[0] as PackedVector2Array).size() >= 3:
						_add_loop(inner[0], 1 if inset < 10.0 else -1, [], {}, bkind)
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
		# The terminal's halls, airside mall and gate lounges.
		for lp: PackedVector2Array in game.skyport.wplan.get("walk_loops", []):
			_add_loop(lp, 1, [], {}, "plaza")
			var rev := lp.duplicate()
			rev.reverse()
			_add_loop(rev, -1, [], {}, "plaza")
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
	_seats.clear()
	_seat_grid.clear()
	_obs_grid.clear()
	for city: CityWorld in [game.world, game.world.mainland]:
		if city == null:
			continue
		if city.has_method("activity_furniture"):
			for item in city.activity_furniture():
				var fkind := String(item[0])
				var fxf: Transform3D = item[1]
				var fwd := fxf.basis.z
				var yaw := atan2(-fwd.x, -fwd.z)
				if fkind == "bench":
					# Two seat slots per bench, offset ±0.42 m along the bench's X axis.
					for sx: float in [-0.42, 0.42]:
						var sp := fxf * Vector3(sx, 0.0, 0.16)
						_register_seat(sp, yaw, "bench")
				elif fkind == "bus_shelter":
					# One bench seat + one standing wait spot under the shelter.
					_register_seat(fxf * Vector3(-0.55, 0.0, 0.25), yaw, "bench")
					_register_seat(fxf * Vector3(0.65, 0.0, 0.35), yaw, "shelter_wait")
		# Index pavement furniture, lampposts, and trees so pedestrians steer around them.
		for items in city._furniture_by_chunk.values():
			for it in items:
				var rad := float(OBS_RADII.get(String(it[0]), 0.0))
				if rad > 0.0:
					_register_obstacle((it[1] as Transform3D).origin, rad)
		for items in city._props_by_chunk.values():
			for it in items:
				var rad := float(OBS_RADII.get(String(it[0]), 0.0))
				if rad > 0.0:
					_register_obstacle((it[1] as Transform3D).origin, rad)
	var scene: PackedScene = load(MODEL)
	if scene == null:
		return
	var inst := scene.instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	mis.sort_custom(func(a, b):
		var na := int(String(a.name).trim_prefix("person_"))
		var nb := int(String(b.name).trim_prefix("person_"))
		return na < nb)
	var crowd_sh: Shader = load("res://src/empire/npc/crowd.gdshader")
	var mat_male := ShaderMaterial.new()
	mat_male.shader = crowd_sh
	mat_male.set_shader_parameter("pivot_k", 1.0)
	mat_male.set_shader_parameter("fade_out_start", NEAR - 4.0)
	mat_male.set_shader_parameter("fade_out_end", NEAR + 8.0)
	var mat_female := ShaderMaterial.new()
	mat_female.shader = crowd_sh
	mat_female.set_shader_parameter("pivot_k", 0.925)
	mat_female.set_shader_parameter("fade_out_start", NEAR - 4.0)
	mat_female.set_shader_parameter("fade_out_end", NEAR + 8.0)
	_mm_bufs.clear()
	_by_body.clear()
	for mi in mis:
		var nstr := String(mi.name)
		var body_num := int(nstr.trim_prefix("person_")) if nstr.begins_with("person_") else 0
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = (mi as MeshInstance3D).mesh
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat_female if (body_num % 2 == 1) else mat_male
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mmis.append(mmi)
		_mm_bufs.append(PackedFloat32Array())
		_by_body.append([])
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


func _register_seat(pos: Vector3, yaw: float, kind: String) -> void:
	var idx := _seats.size()
	_seats.append({"pos": pos, "yaw": yaw, "kind": kind, "busy": false})
	var sk := Vector2i(floori(pos.x / 100.0), floori(pos.z / 100.0))
	if not _seat_grid.has(sk):
		_seat_grid[sk] = []
	(_seat_grid[sk] as Array).append(idx)


func _register_obstacle(pos: Vector3, radius: float) -> void:
	var ok := Vector2i(floori(pos.x / 50.0), floori(pos.z / 50.0))
	if not _obs_grid.has(ok):
		_obs_grid[ok] = []
	(_obs_grid[ok] as Array).append([Vector2(pos.x, pos.z), radius])


func _obs_clear(p: Vector2, pad := 0.35) -> bool:
	var cx := floori(p.x / 50.0)
	var cz := floori(p.y / 50.0)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for ob in _obs_grid.get(Vector2i(cx + dx, cz + dz), []):
				var r := float(ob[1]) + pad
				if p.distance_squared_to(ob[0] as Vector2) < r * r:
					return false
	return true


func _obstacle_avoid(q: Vector2, d: Vector2) -> Vector2:
	var cx := floori(q.x / 50.0)
	var cz := floori(q.y / 50.0)
	var push := Vector2.ZERO
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for ob in _obs_grid.get(Vector2i(cx + dx, cz + dz), []):
				var op: Vector2 = ob[0]
				var clear := float(ob[1]) + 0.42
				var rel := q - op
				var d2 := rel.length_squared()
				if d2 >= clear * clear or d2 < 0.0001:
					continue
				var dist := sqrt(d2)
				var away := rel / dist
				var tang := Vector2(-away.y, away.x)
				if tang.dot(d) < 0.0:
					tang = -tang
				var w := clampf((clear - dist) / clear, 0.2, 1.0)
				push += (away * 0.72 + tang * 0.68).normalized() * (w * 0.9)
	return push.limit_length(1.1)


func _acquire_person() -> Dictionary:
	return _pool.pop_back() if not _pool.is_empty() else {}


func _recycle_person(pr: Dictionary) -> void:
	_release_seat(pr)
	if _pool.size() < 96:
		_pool.append(pr)


## Release pooled dictionaries when entering interiors/garage to free idle RAM.
func trim_pool() -> void:
	_pool.clear()


func _claim_seat_near(q: Vector2, max_r: float) -> int:
	var x0 := floori((q.x - max_r) / 100.0)
	var x1 := floori((q.x + max_r) / 100.0)
	var z0 := floori((q.y - max_r) / 100.0)
	var z1 := floori((q.y + max_r) / 100.0)
	var best := -1
	var best_d2 := max_r * max_r
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			for idx in _seat_grid.get(Vector2i(cx, cz), []):
				var st: Dictionary = _seats[int(idx)]
				if bool(st["busy"]):
					continue
				var sp: Vector3 = st["pos"]
				var d2 := (sp.x - q.x) * (sp.x - q.x) + (sp.z - q.y) * (sp.z - q.y)
				if d2 < best_d2:
					best_d2 = d2
					best = int(idx)
	if best >= 0:
		_seats[best]["busy"] = true
	return best


func _release_seat(pr: Dictionary) -> void:
	var si := int(pr.get("seat", -1))
	if si >= 0 and si < _seats.size():
		_seats[si]["busy"] = false
	pr["seat"] = -1


## Spawn a pedestrian stepping out of a parked vehicle onto the nearest pavement loop.
func spawn_from_car(world_pos: Vector3, body_idx: int, seed_val: float, top_col: Color) -> void:
	var best_loop := -1
	var best_s := 0.0
	var best_d2 := 24.0 * 24.0
	var q := Vector2(world_pos.x, world_pos.z)
	for li in _loops_near(world_pos, 24.0):
		var loop: Dictionary = _loops[int(li)]
		if not (loop["city_crossing"] as Dictionary).is_empty():
			continue
		var poly: PackedVector2Array = loop["pts"]
		var cum: PackedFloat32Array = loop["cum"]
		for i in poly.size():
			var pa := poly[i]
			var pb := poly[(i + 1) % poly.size()]
			var cp := Geometry2D.get_closest_point_to_segment(q, pa, pb)
			var d2 := cp.distance_squared_to(q)
			if d2 < best_d2:
				best_d2 = d2
				best_loop = int(li)
				best_s = cum[i] + pa.distance_to(cp)
	if best_loop < 0:
		return
	var l: Dictionary = _loops[best_loop]
	var sp := _sample(l, best_s)
	var d: Vector2 = (sp[1] as Vector2) * float(l["dir"])
	var pos := Vector3(world_pos.x, float(_ground.call(world_pos.x, world_pos.z)), world_pos.z)
	_people.append({"loop": best_loop, "s": best_s, "dir": int(l["dir"]),
		"speed": _rng.randf_range(1.12, 1.45), "vel_cur": 0.4, "profile": "commuter",
		"body": body_idx % maxi(_mmis.size(), 1), "seed": seed_val, "slot": _rng.randi() % 6, "fade": 1.0,
		"top": top_col, "scale": _rng.randf_range(0.95, 1.04), "lane": _rng.randf_range(-0.3, 0.3),
		"stride": 0.0, "look": 0.0, "glance": 0.0, "glance_t": 1.4,
		"state": "walk", "t": 0.0, "goal": Vector3.ZERO, "pos": pos, "yaw": atan2(-d.x, -d.y), "walk": 0.4,
		"browsed": false, "dodge": 0.0, "avoid": (q - (sp[0] as Vector2)).limit_length(1.4), "pace": 1.0,
		"crossed": false, "cross_cd": 6.0, "pause_cd": 18.0, "waiting": false, "pose": 0, "seat": -1,
		"phone_walk": _rng.randf() < 0.25, "gy_x": pos.x, "gy_z": pos.z, "gy": pos.y})


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
	var body_pick := _rng.randi() % maxi(_mmis.size(), 1)
	if profile == "jogger" and _mmis.size() >= 12:
		body_pick = 10 if _rng.randf() < 0.5 else 11
	elif profile == "commuter" and _mmis.size() >= 9 and _rng.randf() < 0.55:
		var comm_bodies := [2, 6, 7, 8, 15] if _mmis.size() >= 16 else [2, 6, 7, 8]
		body_pick = comm_bodies[_rng.randi() % comm_bodies.size()]
	var phone_walk := (profile in ["commuter", "stroller", "default"]) and _cur_weather != "storm" and _rng.randf() < 0.16
	var pr := _acquire_person()
	pr["loop"] = li; pr["s"] = s; pr["dir"] = 1 if is_city_cross else int(l["dir"]) * (1 if _rng.randf() < 0.85 else -1)
	pr["speed"] = spd; pr["vel_cur"] = spd * _speed_scale; pr["profile"] = profile; pr["body"] = body_pick
	pr["seed"] = _rng.randf(); pr["slot"] = _rng.randi() % 6; pr["fade"] = 1.0 if _first else 0.0
	pr["top"] = TOPS[_rng.randi() % TOPS.size()]; pr["scale"] = _rng.randf_range(0.92, 1.07); pr["lane"] = _rng.randf_range(-0.35, 0.35)
	pr["stride"] = _rng.randf() * 3.0; pr["look"] = 0.0; pr["glance"] = 0.0; pr["glance_t"] = _rng.randf_range(0.7, 2.4)
	pr["state"] = "walk"; pr["t"] = 0.0; pr["goal"] = Vector3.ZERO; pr["pos"] = Vector3.ZERO; pr["yaw"] = 0.0; pr["walk"] = 1.0
	pr["browsed"] = false; pr["dodge"] = 0.0; pr["avoid"] = Vector2.ZERO; pr["pace"] = 1.0; pr["crossed"] = false; pr["cross_cd"] = 0.0
	pr["pause_cd"] = _rng.randf_range(9.0, 26.0); pr["waiting"] = false; pr["pose"] = 1 if profile == "jogger" else (3 if phone_walk else 0)
	pr["seat"] = -1; pr["phone_walk"] = phone_walk; pr["gy_x"] = 1e9; pr["gy_z"] = 1e9; pr["gy"] = 0.0
	pr["fear"] = 0.0; pr["alarm"] = 0.0; pr["firsthand"] = 0.0; pr["fleeing"] = false; pr["crossing"] = false; pr["lag"] = 0.0
	_people.append(pr)


func _populate(focus: Vector3) -> void:
	# Predictive velocity-biased spawn centre so driving ahead pre-populates upcoming streets.
	var pop_focus := focus
	if game != null and game.world != null:
		var vel: Vector3 = game.world._vel
		var hvel := Vector3(vel.x, 0.0, vel.z)
		if hvel.length_squared() > 9.0:
			pop_focus = focus + hvel.limit_length(18.0) * 2.2
	if not _first and _target_count > 0 and _people.size() >= _target_count - 1 \
			and pop_focus.distance_squared_to(_last_pop_focus) < 16.0 * 16.0 \
			and absf(_eff_density - _last_pop_density) < 0.08:
		return
	var want: Array = []   # [loop, s] slots in range
	var step := SPACING / maxf(_eff_density, 0.05)
	for li in _loops_near(pop_focus, NEAR):
		var l: Dictionary = _loops[li]
		var city: Dictionary = l["city_crossing"]
		if not city.is_empty():
			var site: Dictionary = city["site"]
			var kerb: Vector3 = site["a"]
			if focus.distance_squared_to(kerb) < 58.0 * 58.0 and int(_crossing_counts.get(li, 0)) < 2:
				want.append([li, float(l["cum"][2])])
			continue
		var s := fposmod(float(li) * 7.3, step)
		while s < float(l["len"]):
			var sp: Array = _sample(l, s)
			if (sp[0] as Vector2).distance_to(Vector2(pop_focus.x, pop_focus.z)) < NEAR:
				want.append([li, s])
			s += step
	_target_count = want.size()
	_last_pop_focus = pop_focus
	_last_pop_density = _eff_density
	var missing := want.size() - _people.size()
	if missing <= 0 or want.is_empty():
		return
	for i in mini(missing, 28 if _first else 4):
		var w: Array = want[_rng.randi() % want.size()]
		var city_route: bool = not _loops[w[0]]["city_crossing"].is_empty()
		if city_route and int(_crossing_counts.get(w[0], 0)) >= 2:
			continue
		var jitter := 1.0 if city_route else 4.0
		var s2: float = float(w[1]) + _rng.randf_range(-jitter, jitter)
		var sp2: Array = _sample(_loops[w[0]], s2)
		if sp2[2] in _loops[w[0]]["crossings"]:
			continue
		var p := Vector3(sp2[0].x, focus.y, sp2[0].y)
		# Never spawn in plain sight inside NEAR (92 m): strict frustum check out to 100 m,
		# and never spawn inside street furniture, lampposts, or trees.
		if not _first and not _unseen(p, 100.0):
			continue
		if not _obs_clear(sp2[0] as Vector2, 0.4):
			continue
		var clear := true
		for q in _people:
			if (q["pos"] as Vector3).distance_to(p) < 2.5:
				clear = false
				break
		if clear:
			_spawn(int(w[0]), s2)
			var spawned: Dictionary = _people[_people.size() - 1]
			# On initial/distant populate, seed some bench sitters and chatting pairs directly
			# so parks, plazas, and bus stops immediately feel lived in.
			if not city_route and _cur_weather not in ["rain", "storm"] and _rng.randf() < 0.22:
				var si := _claim_seat_near(Vector2(p.x, p.z), 12.0)
				if si >= 0:
					var st: Dictionary = _seats[si]
					spawned["seat"] = si
					spawned["pos"] = st["pos"]
					spawned["yaw"] = float(st["yaw"])
					spawned["state"] = "sit" if String(st["kind"]) == "bench" else "pause"
					spawned["pose"] = 2 if String(st["kind"]) == "bench" else 3
					spawned["walk"] = 0.0
					spawned["vel_cur"] = 0.0
					spawned["t"] = _rng.randf_range(18.0, 52.0)
					var fdir := Vector2(-sin(float(st["yaw"])), -cos(float(st["yaw"])))
					spawned["goal"] = (st["pos"] as Vector3) + Vector3(fdir.x, 0.0, fdir.y) * 2.0
			elif not city_route and String(_loops[w[0]].get("kind", "block")) in ["plaza", "park"] and _cur_weather != "storm" and _rng.randf() < 0.16 and missing > 1:
				var d2: Vector2 = sp2[1]
				var p_a := Vector3(sp2[0].x, float(_ground.call(sp2[0].x, sp2[0].y)), sp2[0].y)
				var p_b := p_a + Vector3(d2.x, 0.0, d2.y) * 1.05
				if _obs_clear(Vector2(p_b.x, p_b.z), 0.4):
					p_b.y = float(_ground.call(p_b.x, p_b.z))
					var chat_t := _rng.randf_range(14.0, 34.0)
					spawned["pos"] = p_a
					spawned["state"] = "chat"
					spawned["pose"] = 4
					spawned["walk"] = 0.0
					spawned["vel_cur"] = 0.0
					spawned["t"] = chat_t
					spawned["goal"] = p_b
					spawned["yaw"] = atan2(-(p_b.x - p_a.x), -(p_b.z - p_a.z))
					_spawn(int(w[0]), s2 + 1.05)
					var partner: Dictionary = _people[_people.size() - 1]
					partner["pos"] = p_b
					partner["state"] = "chat"
					partner["pose"] = 4
					partner["walk"] = 0.0
					partner["vel_cur"] = 0.0
					partner["t"] = chat_t + _rng.randf_range(-1.5, 1.5)
					partner["goal"] = p_a
					partner["yaw"] = atan2(-(p_a.x - p_b.x), -(p_a.z - p_b.z))
			if city_route:
				_crossing_counts[w[0]] = int(_crossing_counts.get(w[0], 0)) + 1


func _process(dt: float) -> void:
	if game == null or _mmis.is_empty() or game.state != "play" or get_tree().paused:
		return
	if game.garage and game.garage.inside:
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
	var frame := Engine.get_process_frames()
	if (frame & 3) == 0 or _vehicles.is_empty():
		_collect_vehicles(focus)
	_panic_calls.clear()
	for pr in _people:
		if float(pr.get("fear", 0.0)) > 0.64 and float(pr.get("firsthand", 0.0)) > 0.0:
			var at: Vector3 = pr["pos"]
			_panic_calls.append(Vector2(at.x, at.z))
	if frame % 3 == 0:
		_queue_up(focus)
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
		if float(pr.get("fade", 1.0)) < 1.0:
			pr["fade"] = minf(float(pr["fade"]) + dt / 0.9, 1.0)
		var p0: Vector3 = pr["pos"]
		var d2_focus := (p0.x - fx) * (p0.x - fx) + (p0.z - fz) * (p0.z - fz) if p0 != Vector3.ZERO else 0.0
		# (2026-11-27 engine pass) Simulation LOD: everyone within 48 m
		# steps every frame; further out (where they're only a few pixels
		# tall and don't dodge or browse anyway) every 2nd frame, past 75 m
		# every 3rd, on staggered frames, with the time they skipped. They
		# walk the same paths at the same speeds.
		var every := 1 if d2_focus < 48.0 * 48.0 or p0 == Vector3.ZERO else (2 if d2_focus < 75.0 * 75.0 else 3)
		var lag := float(pr.get("lag", 0.0)) + dt
		if every > 1 and (frame + int(pr.get("slot", 0))) % every != 0:
			pr["lag"] = lag
		else:
			pr["lag"] = 0.0
			_step(pr, minf(lag, 0.1), me, eye, d2_focus)
		var p: Vector3 = pr["pos"]
		if pr["state"] == "gone":
			_recycle_person(pr)
			continue
		# Out of range: they leave only off camera (or once they're specks beyond DROP).
		var dd := Vector2(p.x - fx, p.z - fz).length()
		if dd > DROP or dd > keep_r and _unseen(p, 108.0):
			_recycle_person(pr)
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
## Runs only within 48 m and sorts by s per loop so it stays O(N log N).
func _queue_up(focus: Vector3) -> void:
	var by_loop := {}
	var fx := focus.x
	var fz := focus.z
	for pr in _people:
		pr["pace"] = 1.0
		if pr["state"] != "walk":
			continue
		var p0: Vector3 = pr["pos"]
		if (p0.x - fx) * (p0.x - fx) + (p0.z - fz) * (p0.z - fz) > 48.0 * 48.0:
			continue
		var k := Vector2i(int(pr["loop"]), int(pr["dir"]))
		if not by_loop.has(k):
			by_loop[k] = []
		(by_loop[k] as Array).append(pr)
	for k in by_loop:
		var list: Array = by_loop[k]
		if list.size() < 2:
			continue
		var kv := k as Vector2i
		var ln := float((_loops[kv.x] as Dictionary)["len"])
		var dir_s := float(kv.y)
		list.sort_custom(func(a, b): return float(a["s"]) * dir_s < float(b["s"]) * dir_s)
		var n := list.size()
		for i in n:
			var a: Dictionary = list[i]
			var sa := float(a["s"])
			var sp_a := float(a["speed"])
			var lane_a := float(a["lane"])
			for step_i in range(1, mini(n, 4)):
				var b: Dictionary = list[(i + step_i) % n]
				var gap := fposmod((float(b["s"]) - sa) * dir_s, ln)
				if gap >= 1.6:
					break
				if absf(lane_a - float(b["lane"])) <= 0.55 and sp_a > float(b["speed"]) * float(b["pace"]):
					var p := float(b["speed"]) * float(b["pace"]) / sp_a
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
	if game.wrecks != null:
		live_cars.append_array(game.wrecks.cars())
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
		if fear > 0.42 and state in ["browse", "pause", "sit", "to_seat", "chat"]:
			_release_seat(pr)
			state = "walk"
			pr["state"] = state
			pr["pose"] = 0
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
						if on_cross < 5 and _rng.randf() < 0.34:
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
			# Smooth steered avoidance around very close hero, static pavement obstacles, or approaching vehicles.
			var want_avoid := veh_escape
			if not far:
				var candidate := base + side * float(pr["dodge"]) + avoid
				if not now_crossing:
					want_avoid += _obstacle_avoid(candidate, d)
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
			if not now_crossing and want_avoid.length_squared() > 0.04:
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
				# Natural bench sitting, phone-checking, or resting pauses on sidewalks / plazas / parks.
				if not entered_shop and float(pr["pause_cd"]) <= 0.0 and _cur_weather != "storm" and city_c.is_empty():
					var lkind := String(l.get("kind", "block"))
					var pause_chance := 0.24 if lkind in ["plaza", "park"] else (0.16 if profile == "stroller" else 0.09)
					if _cur_weather == "rain":
						pause_chance *= 0.35
					pr["pause_cd"] = _rng.randf_range(16.0, 34.0)
					if _rng.randf() < pause_chance:
						var seat_idx := _claim_seat_near(q, 5.5) if _cur_weather != "rain" else -1
						if seat_idx >= 0:
							var st_d: Dictionary = _seats[seat_idx]
							pr["seat"] = seat_idx
							pr["state"] = "to_seat"
							pr["goal"] = st_d["pos"]
							pr["t"] = _rng.randf_range(16.0, 42.0)
						else:
							pr["state"] = "pause"
							pr["pose"] = 3 if _rng.randf() < 0.65 else 0
							pr["t"] = _rng.randf_range(4.0, 8.2) if lkind in ["plaza", "park"] else _rng.randf_range(2.2, 5.0)
							var face_v := d.rotated(_rng.randf_range(-0.65, 0.65))
							pr["goal"] = Vector3(q.x + face_v.x * 2.0, 0.0, q.y + face_v.y * 2.0)
		"to_seat":
			p = pr["pos"]
			p.y = 0.0
			var gs: Vector3 = pr["goal"]
			var to_s := Vector2(gs.x - p.x, gs.z - p.z)
			if to_s.length() < 0.25:
				var si := int(pr.get("seat", -1))
				var is_bench := si >= 0 and si < _seats.size() and String(_seats[si]["kind"]) == "bench"
				pr["state"] = "sit" if is_bench else "pause"
				pr["pose"] = 2 if is_bench else 3
				if si >= 0 and si < _seats.size():
					var syaw := float(_seats[si]["yaw"])
					var fdir := Vector2(-sin(syaw), -cos(syaw))
					pr["goal"] = gs + Vector3(fdir.x, 0.0, fdir.y) * 2.0
				vel_cur = 0.0
				fwd = Vector2.ZERO
			else:
				fwd = to_s.normalized()
				vel_cur = move_toward(vel_cur, base_speed * 0.85, dt * 3.0)
				var mv_s := fwd * minf(vel_cur * dt, to_s.length())
				p += Vector3(mv_s.x, 0.0, mv_s.y)
		"sit":
			vel_cur = 0.0
			var si := int(pr.get("seat", -1))
			if si >= 0 and si < _seats.size():
				var st_pos: Vector3 = _seats[si]["pos"]
				p = Vector3(st_pos.x, 0.0, st_pos.z)
				var syaw := float(_seats[si]["yaw"])
				fwd = Vector2(-sin(syaw), -cos(syaw))
			else:
				p = Vector3(prev_xz.x, 0.0, prev_xz.y)
				fwd = Vector2.ZERO
			pr["pose"] = 2
			pr["t"] = float(pr["t"]) - dt
			if float(pr["t"]) <= 0.0:
				_release_seat(pr)
				pr["state"] = "walk"
				pr["pose"] = 3 if bool(pr.get("phone_walk", false)) else 0
		"chat":
			vel_cur = 0.0
			p = Vector3(prev_xz.x, 0.0, prev_xz.y)
			var gc: Vector3 = pr["goal"]
			var to_c := Vector2(gc.x - p.x, gc.z - p.z)
			fwd = to_c.normalized() if to_c.length_squared() > 0.001 else Vector2.ZERO
			pr["pose"] = 4
			pr["t"] = float(pr["t"]) - dt
			if float(pr["t"]) <= 0.0:
				pr["state"] = "walk"
				pr["pose"] = 3 if bool(pr.get("phone_walk", false)) else 0
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
				_release_seat(pr)
				pr["state"] = "walk"
				pr["pose"] = 3 if bool(pr.get("phone_walk", false)) else 0
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
	if state == "walk":
		pr["pose"] = 1 if (profile == "jogger" and not bool(pr["waiting"]) and fear < 0.42) else (3 if bool(pr.get("phone_walk", false)) and fear < 0.25 and not bool(pr.get("crossing", false)) else 0)
	# Query ground_y tightly nearby (0.45 m) so feet never float or sink on sloped pavements.
	var dx_g := p.x - float(pr.get("gy_x", 1e9))
	var dz_g := p.z - float(pr.get("gy_z", 1e9))
	var gy_thresh := 0.20 if not far else 1.44
	if not had_pos or dx_g * dx_g + dz_g * dz_g > gy_thresh or state in ["sit", "to_seat"]:
		var gy := float(_ground.call(p.x, p.z))
		pr["gy_x"] = p.x
		pr["gy_z"] = p.z
		pr["gy"] = gy
		p.y = gy
	else:
		p.y = float(pr["gy"])
	pr["pos"] = p
	if fwd != Vector2.ZERO:
		var target_yaw := atan2(-fwd.x, -fwd.y)
		var turn_rate := 8.5 if vel_cur < 0.35 else 6.8
		pr["yaw"] = target_yaw if not had_pos else lerp_angle(float(pr["yaw"]), target_yaw, 1.0 - exp(-turn_rate * dt))


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
	var n_bodies := _mmis.size()
	for i in n_bodies:
		(_by_body[i] as Array).clear()
	for pr in _people:
		(_by_body[int(pr["body"]) % n_bodies] as Array).append(pr)
	var focus := _focus()
	var aabb := AABB(focus - Vector3(KEEP, 20, KEEP), Vector3(KEEP * 2, 60, KEEP * 2))
	for i in n_bodies:
		var mmi := _mmis[i] as MultiMeshInstance3D
		var mm: MultiMesh = mmi.multimesh
		var list: Array = _by_body[i]
		var cnt := list.size()
		if cnt > mm.instance_count:
			var cap := maxi(8, mm.instance_count)
			while cap < cnt:
				cap *= 2
			mm.instance_count = cap
			_mm_bufs[i].resize(cap * 20)
		mm.visible_instance_count = cnt
		if cnt > 0:
			var buf: PackedFloat32Array = _mm_bufs[i]
			var j := 0
			for pr in list:
				var b := Basis(Vector3.UP, float(pr["yaw"])).scaled(_person_scale(pr))
				var o: Vector3 = pr["pos"]
				buf[j] = b.x.x; buf[j + 1] = b.y.x; buf[j + 2] = b.z.x; buf[j + 3] = o.x
				buf[j + 4] = b.x.y; buf[j + 5] = b.y.y; buf[j + 6] = b.z.y; buf[j + 7] = o.y
				buf[j + 8] = b.x.z; buf[j + 9] = b.y.z; buf[j + 10] = b.z.z; buf[j + 11] = o.z
				var c: Color = pr["top"]
				buf[j + 12] = c.r; buf[j + 13] = c.g; buf[j + 14] = c.b; buf[j + 15] = float(pr.get("fear", 0.0))
				# Pack pose_mode * 32 + fade_steps (0..16) + seed (0..1) into INSTANCE_CUSTOM.y.
				var fk := 16.0 - floorf(clampf(float(pr.get("fade", 1.0)), 0.0, 1.0) * 16.0)
				var pm := float(int(pr.get("pose", 0))) * 32.0
				buf[j + 16] = float(pr["stride"]); buf[j + 17] = fposmod(float(pr["seed"]), 1.0) + fk + pm; buf[j + 18] = float(pr["walk"]); buf[j + 19] = float(pr["look"])
				j += 20
			mm.buffer = buf
		mmi.custom_aabb = aabb
	_draw_blobs(focus, aabb)


static func _person_scale(person: Dictionary) -> Vector3:
	var width := lerpf(0.90, 1.11, fposmod(float(person["seed"]) * 7.31, 1.0))
	return Vector3(width, 1.0, lerpf(1.0, width, 0.58)) * float(person["scale"])


## Contact shadows: flat on the pavement under each person, a touch
## lighter as they walk away out of the near range (they fade with them).
func _draw_blobs(focus: Vector3, aabb: AABB) -> void:
	if _blobs == null:
		return
	var mm := _blobs.multimesh
	var cnt := _people.size()
	if cnt > mm.instance_count:
		var cap := maxi(16, mm.instance_count)
		while cap < cnt:
			cap *= 2
		mm.instance_count = cap
		_blob_buf.resize(cap * 16)
	mm.visible_instance_count = cnt
	if cnt == 0:
		return
	var buf := _blob_buf
	var j := 0
	for pr in _people:
		var o: Vector3 = pr["pos"]
		var scale := _person_scale(pr)
		scale.y = 1.0
		var b := Basis(Vector3.UP, float(pr["yaw"])).scaled(scale)
		buf[j] = b.x.x; buf[j + 1] = b.y.x; buf[j + 2] = b.z.x; buf[j + 3] = o.x
		buf[j + 4] = b.x.y; buf[j + 5] = b.y.y; buf[j + 6] = b.z.y; buf[j + 7] = o.y + 0.035
		buf[j + 8] = b.x.z; buf[j + 9] = b.y.z; buf[j + 10] = b.z.z; buf[j + 11] = o.z
		var d := Vector2(o.x - focus.x, o.z - focus.z).length()
		buf[j + 12] = clampf((NEAR + 6.0 - d) / 12.0, 0.0, 1.0)
		buf[j + 13] = 0.0; buf[j + 14] = 0.0; buf[j + 15] = 0.0
		j += 16
	mm.buffer = buf
	_blobs.custom_aabb = aabb


## How many people are out (for the debug readout / tests).
func count() -> int:
	return _people.size()
