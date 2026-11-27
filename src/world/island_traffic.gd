class_name IslandTraffic
extends Node3D
## Cars on Skyport Island's roads and bridge, using the city's own traffic
## models and shader (CityWorld.car_meshes, the "parked" pose encoding so
## the shader holds each car where the CPU puts it). A few dozen cars at
## most, each on a lane of SkyportIsland.lanes(): drive at the lane's speed,
## keep a gap behind the car ahead on the same lane, pick a way on at each
## junction (never straight back), queue at lane ends, and when one reaches
## the city end of the bridge it carries on into the city out of sight (it
## re-enters on the island-bound lane a little later). Exists only with the
## island's near content (built and freed with it).

const CARS := 26
const GAP := 9.0          # m to the car ahead on the same lane
const LEN := 4.6

var lanes: Array = []      # [{pts, len, cum, speed, next, city_start, city_end}]
var _city_starts: Array[int] = []
var _city_start_rr := 0
var cars: Array = []       # {lane, s, v, kind, col, wait}
var _mm: Array = []        # MultiMesh per car kind
var _rng := RandomNumberGenerator.new()
var world: Node
## Your vehicle (TrafficBodies sets it): cars brake for it in their lane.
var blocker := Vector3(INF, 0, INF)
var crossing_people := PackedVector3Array()


func setup(layout: CityLayout, p_world: Node) -> void:
	world = p_world
	add_to_group("island_traffic")
	# (The lanes are world space – the island's roads and both bridges – so
	# this node ignores the island's own transform.)
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.seed = 2207
	for l: Dictionary in SkyportIsland.lanes(layout, 3.0):
		var pts: PackedVector3Array = l["pts"]
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		var li_new := lanes.size()
		lanes.append({"pts": pts, "len": cum[-1], "cum": cum, "speed": float(l["speed"]) * 0.8, "next": l["next"],
			"city_start": l["city_start"], "city_end": l["city_end"]})
		if l["city_start"]:
			_city_starts.append(li_new)
	# (one MultiMesh per kind over the whole island, so no per-car LOD: the
	# ~1.2k-triangle mid models; the full ones are for the city's near band)
	var meshes: Array = world.get("car_mid_meshes") if world else []
	if meshes.is_empty():
		return
	var kinds: Array = []
	for k in meshes.size():
		if meshes[k] != null:
			kinds.append(k)
	for k in meshes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = meshes[k]
		mm.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-1100, -20, 380), Vector3(1800, 260, 1900))
		add_child(mmi)
		_mm.append(mm)
	# Spread the cars over the lanes, a gap apart.
	for i in CARS:
		var li := _rng.randi() % lanes.size()
		var L: Dictionary = lanes[li]
		if float(L["len"]) < 20.0:
			continue
		var k: int = kinds[_rng.randi() % kinds.size()]
		cars.append({"lane": li, "s": _rng.randf_range(0.0, float(L["len"]) - 8.0), "v": float(L["speed"]) * 0.6, "kind": k,
			"col": CityWorld.kind_colour(k, CityWorld.CAR_COLORS[_rng.randi() % CityWorld.CAR_COLORS.size()]),
			"wait": 0.0})


func _sample(L: Dictionary, s: float) -> Array:
	var cum: PackedFloat32Array = L["cum"]
	var pts: PackedVector3Array = L["pts"]
	s = clampf(s, 0.0, float(L["len"]))
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := maxf(cum[hi] - cum[lo], 0.001)
	var p := pts[lo].lerp(pts[hi], (s - cum[lo]) / seg)
	var d := pts[hi] - pts[lo]
	return [p, d.normalized() if d.length() > 0.001 else Vector3.FORWARD]


## Permit a crossing once there is room. An approaching vehicle with enough
## distance to brake yields once a pedestrian has stepped into the crossing.
func crossing_blocked(a: Vector2, b: Vector2) -> bool:
	if blocker.x < INF:
		var player_car := Vector2(blocker.x, blocker.z)
		if Geometry2D.get_closest_point_to_segment(player_car, a, b).distance_to(player_car) < 3.5:
			return true
	for c in cars:
		if float(c["wait"]) > 0.0:
			continue
		var sample := _sample(lanes[c["lane"]], float(c["s"]))
		var p: Vector3 = sample[0]
		var dir: Vector3 = sample[1]
		var here := Vector2(p.x, p.z)
		if Geometry2D.get_closest_point_to_segment(here, a, b).distance_to(here) < 3.5:
			return true
		var ahead := here + Vector2(dir.x, dir.z) * (4.0 + float(c["v"]) * 1.6)
		if Geometry2D.segment_intersects_segment(here, ahead, a, b) != null:
			return true
	return false


func _process(dt: float) -> void:
	if _mm.is_empty():
		return
	dt = minf(dt, 0.1)
	# Ahead-of-me on the same lane: sort each lane's cars by s.
	var by_lane := {}
	for c in cars:
		if float(c["wait"]) > 0.0:
			continue
		if not by_lane.has(c["lane"]):
			by_lane[c["lane"]] = []
		(by_lane[c["lane"]] as Array).append(c)
	for li in by_lane:
		var lst: Array = by_lane[li]
		lst.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))
		for i in lst.size():
			var c: Dictionary = lst[i]
			var L: Dictionary = lanes[li]
			var want := float(L["speed"])
			if i + 1 < lst.size():
				var gap := float(lst[i + 1]["s"]) - float(c["s"]) - LEN
				want = minf(want, maxf((gap - GAP * 0.5) * 0.8, 0.0))
			if blocker.x < INF:
				# Your vehicle or walking player in the lane ahead: stop short of it.
				var sp0 := _sample(L, float(c["s"]))
				var to: Vector3 = blocker - (sp0[0] as Vector3)
				var ahead := to.dot(sp0[1] as Vector3)
				if absf(to.y) < 3.5 and ahead > 0.0 and ahead < 30.0 and (to - (sp0[1] as Vector3) * ahead).length() < 2.6:
					want = minf(want, maxf((ahead - LEN - 2.5) * 0.8, 0.0))
			if not crossing_people.is_empty():
				var sp := _sample(L, float(c["s"]))
				var dir: Vector3 = sp[1]
				for person in crossing_people:
					var delta: Vector3 = person - sp[0]
					var ahead := delta.dot(dir)
					if ahead > 0.0 and ahead < 30.0 and (delta - dir * ahead).length() < 3.0:
						want = minf(want, maxf((ahead - LEN - 2.5) * 0.8, 0.0))
			var rem := float(L["len"]) - float(c["s"])
			if rem < 25.0 and not L["city_end"]:
				want = minf(want, maxf(rem * 0.5, 4.0))   # (slow into the junction)
			var prev_v := float(c["v"])
			c["v"] = move_toward(prev_v, want, dt * (3.0 if want > prev_v else 7.0))
			c["braking"] = want < prev_v - 0.6 or float(c["v"]) < 0.8
			c["s"] = float(c["s"]) + float(c["v"]) * dt
			if float(c["s"]) >= float(L["len"]):
				_next_lane(c, L)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for c in cars:
		if float(c["wait"]) > 0.0:
			c["wait"] = float(c["wait"]) - dt
			if float(c["wait"]) <= 0.0:
				# Only re-enter out of view (or far off) so cars never pop in on the bridge mouth.
				var sp_w := _sample(lanes[int(c["lane"])], 0.0)
				if cam != null:
					var to_w: Vector3 = (sp_w[0] as Vector3) - cam.global_position
					if to_w.length_squared() < 160.0 * 160.0 and to_w.normalized().dot(-cam.global_basis.z) > 0.2:
						c["wait"] = 1.5
						continue
				c["wait"] = 0.0
	_draw()


## At a lane end: on into a lane leaving the junction (try every exit so one
## busy branch never deadlocks the whole approach), or into the city.
func _next_lane(c: Dictionary, L: Dictionary) -> void:
	if L["city_end"] and not _city_starts.is_empty():
		var li: int = _city_starts[_city_start_rr % _city_starts.size()]
		_city_start_rr = (_city_start_rr + 1) % _city_starts.size()
		c["lane"] = li
		c["s"] = 0.0
		c["wait"] = _rng.randf_range(4.0, 14.0)   # (in the city a while)
		return
	var nxt: Array = (L["next"] as Array).duplicate()
	if nxt.is_empty():
		c["s"] = float(L["len"])
		c["v"] = 0.0
		c["braking"] = true
		return
	# Shuffle candidate exits and take the first one with clear entry room.
	for i in range(nxt.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = nxt[i]
		nxt[i] = nxt[j]
		nxt[j] = tmp
	for cand_li in nxt:
		var li2 := int(cand_li)
		var blocked := false
		for c2 in cars:
			if c2 != c and int(c2["lane"]) == li2 and float(c2["s"]) < GAP and float(c2["wait"]) <= 0.0:
				blocked = true
				break
		if not blocked:
			c["lane"] = li2
			c["s"] = 0.0
			return
	c["s"] = float(L["len"])
	c["v"] = 0.0   # (all exits busy: wait for room)
	c["braking"] = true


## Where a car is (its body's transform: on the road, facing its way).
func car_xf(c: Dictionary) -> Transform3D:
	var sp := _sample(lanes[c["lane"]], float(c["s"]))
	var d: Vector3 = sp[1]
	var hd := Vector3(d.x, 0.0, d.z)
	if hd.length_squared() < 0.0001:
		hd = Vector3.FORWARD
	return Transform3D(Basis.looking_at(hd.normalized(), Vector3.UP), (sp[0] as Vector3) - Vector3.UP * 0.38)


func _draw() -> void:
	var groups: Array = []
	for m in _mm:
		groups.append([])
	for c in cars:
		if float(c["wait"]) > 0.0:
			continue
		var sp := _sample(lanes[c["lane"]], float(c["s"]))
		var p: Vector3 = sp[0]
		var d: Vector3 = sp[1]
		var hd := Vector3(d.x, 0.0, d.z)
		if hd.length_squared() < 0.0001:
			hd = Vector3.FORWARD
		else:
			hd = hd.normalized()
		var basis := Basis.looking_at((hd + Vector3.UP * d.y).normalized(), Vector3.UP)
		p.y -= 0.38   # (lanes ride 0.4 m above the road)
		# The traffic shader's parked pose: 5 m along the car's back axis; alpha = braking.
		var brk := 1.0 if bool(c.get("braking", false)) else 0.0
		(groups[int(c["kind"])] as Array).append([Transform3D(basis, p + basis.z * 5.0), Color(0.0, 5.0, 10.0, brk), c["col"]])
	for k in _mm.size():
		var mm: MultiMesh = _mm[k]
		var g: Array = groups[k]
		if mm.instance_count != g.size():
			mm.instance_count = g.size()
		if not g.is_empty():
			mm.buffer = CityWorld._instance_buffer(g)
