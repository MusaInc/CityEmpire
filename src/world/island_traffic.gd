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
var cars: Array = []       # {lane, s, v, kind, col, wait}
var _mm: Array = []        # MultiMesh per car kind
var _rng := RandomNumberGenerator.new()
var world: Node


func setup(layout: CityLayout, p_world: Node) -> void:
	world = p_world
	_rng.seed = 2207
	for l: Dictionary in SkyportIsland.lanes(layout, 3.0):
		var pts: PackedVector3Array = l["pts"]
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		lanes.append({"pts": pts, "len": cum[-1], "cum": cum, "speed": float(l["speed"]) * 0.8, "next": l["next"],
			"city_start": l["city_start"], "city_end": l["city_end"]})
	var meshes: Array = world.get("car_meshes") if world else []
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
		mmi.custom_aabb = AABB(Vector3(900, -20, -800), Vector3(1700, 260, 1500))
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
			"col": (CityWorld.CAR_COLORS[_rng.randi() % CityWorld.CAR_COLORS.size()] as Color) if String(CityWorld.CAR_KINDS[k][0]) != "car_taxi" else CityWorld.TAXI_YELLOW,
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
			var rem := float(L["len"]) - float(c["s"])
			if rem < 25.0 and not L["city_end"]:
				want = minf(want, maxf(rem * 0.5, 4.0))   # (slow into the junction)
			c["v"] = move_toward(float(c["v"]), want, dt * (3.0 if want > float(c["v"]) else 7.0))
			c["s"] = float(c["s"]) + float(c["v"]) * dt
			if float(c["s"]) >= float(L["len"]):
				_next_lane(c, L)
	for c in cars:
		if float(c["wait"]) > 0.0:
			c["wait"] = float(c["wait"]) - dt
			if float(c["wait"]) <= 0.0:
				c["wait"] = 0.0
	_draw()


## At a lane end: on into a lane leaving the junction (one with room at its
## start), or into the city (and back later on the island-bound lane).
func _next_lane(c: Dictionary, L: Dictionary) -> void:
	if L["city_end"]:
		for li in lanes.size():
			if lanes[li]["city_start"]:
				c["lane"] = li
				c["s"] = 0.0
				c["wait"] = _rng.randf_range(4.0, 14.0)   # (in the city a while)
				return
	var nxt: Array = L["next"]
	if nxt.is_empty():
		c["s"] = float(L["len"])
		c["v"] = 0.0
		return
	var li2: int = nxt[_rng.randi() % nxt.size()]
	for c2 in cars:
		if c2 != c and int(c2["lane"]) == li2 and float(c2["s"]) < GAP and float(c2["wait"]) <= 0.0:
			c["s"] = float(L["len"])
			c["v"] = 0.0   # (wait for room)
			return
	c["lane"] = li2
	c["s"] = 0.0


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
		var hd := Vector3(d.x, 0.0, d.z).normalized()
		var basis := Basis.looking_at((hd + Vector3.UP * d.y).normalized(), Vector3.UP)
		p.y -= 0.38   # (lanes ride 0.4 m above the road)
		# The traffic shader's parked pose: 5 m along the car's back axis.
		(groups[int(c["kind"])] as Array).append([Transform3D(basis, p + basis.z * 5.0), Color(0.0, 5.0, 10.0, 0.0), c["col"]])
	for k in _mm.size():
		var mm: MultiMesh = _mm[k]
		var g: Array = groups[k]
		if mm.instance_count != g.size():
			mm.instance_count = g.size()
		if not g.is_empty():
			mm.buffer = CityWorld._instance_buffer(g)
