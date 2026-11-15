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

const NEAR := 62.0
const KEEP := 74.0
const SPACING := 16.0         # one person per this many metres of pavement
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
	# Skyport Island: a pavement each side of every road (walked along one
	# side and back along the other, so nobody reaches an end and vanishes).
	if SkyportIsland.enabled and game.skyport:
		for rd in game.skyport.plan_data.get("roads", []):
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
			_add_loop(ring, 1)
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


func _add_loop(pts: PackedVector2Array, dir: int) -> void:
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
	_loops.append({"pts": pts, "cum": cum, "len": length, "dir": dir, "rect": r})
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
	return [a.lerp(b, (s - cum[lo]) / seg), (b - a) / seg]


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
	_people.append({"loop": li, "s": s, "dir": int(l["dir"]) * (1 if _rng.randf() < 0.85 else -1),
		"speed": _rng.randf_range(1.05, 1.5), "body": _rng.randi() % maxi(_mmis.size(), 1), "seed": _rng.randf(),
		"top": TOPS[_rng.randi() % TOPS.size()], "scale": _rng.randf_range(0.93, 1.06), "lane": _rng.randf_range(-0.35, 0.35),
		"stride": _rng.randf() * 3.0, "look": 0.0, "state": "walk", "t": 0.0, "goal": Vector3.ZERO, "pos": Vector3.ZERO,
		"yaw": 0.0, "walk": 1.0, "browsed": false, "dodge": 0.0, "pace": 1.0})


func _populate(focus: Vector3) -> void:
	var want: Array = []   # [loop, s] slots in range
	for li in _loops_near(focus, NEAR):
		var l: Dictionary = _loops[li]
		var step := SPACING / maxf(density, 0.05)
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
		var s2: float = float(w[1]) + _rng.randf_range(-4.0, 4.0)
		var sp2: Array = _sample(_loops[w[0]], s2)
		var p := Vector3(sp2[0].x, focus.y, sp2[0].y)
		if not _first and not _unseen(p, 48.0):
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
	_queue_up()
	var keep: Array = []
	for pr in _people:
		_step(pr, dt, me, eye)
		var p: Vector3 = pr["pos"]
		if pr["state"] == "gone":
			continue
		if Vector2(p.x, p.z).distance_to(Vector2(focus.x, focus.z)) > KEEP:
			continue
		keep.append(pr)
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


func _step(pr: Dictionary, dt: float, me: Vector3, eye: Vector3) -> void:
	var l: Dictionary = _loops[pr["loop"]]
	var state: String = pr["state"]
	var target_walk := 1.0
	var p: Vector3
	var fwd := Vector2.ZERO
	match state:
		"walk":
			var v := float(pr["speed"]) * float(pr["pace"])
			pr["s"] = float(pr["s"]) + float(pr["dir"]) * v * dt
			var sp: Array = _sample(l, pr["s"])
			var d: Vector2 = (sp[1] as Vector2) * float(pr["dir"])
			var side := Vector2(-d.y, d.x)
			var base: Vector2 = sp[0] + side * float(pr["lane"])
			pr["dodge"] = move_toward(float(pr["dodge"]), _dodge_for(base, d, side, me, eye, float(pr["dodge"])), dt * 1.1)
			var q: Vector2 = base + side * float(pr["dodge"])
			p = Vector3(q.x, 0.0, q.y)
			fwd = d
			# A shop door at hand: look in the window, or go in.
			if not pr["browsed"]:
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
			p = pr["pos"]
			p.y = 0.0
			var g: Vector3 = pr["goal"]
			fwd = Vector2(g.x - p.x, g.z - p.z).normalized()
			target_walk = 0.0
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
			var mv := fwd * minf(float(pr["speed"]) * dt, to.length())
			p += Vector3(mv.x, 0.0, mv.y)
			pr["stride"] = float(pr["stride"]) + mv.length()
	if state == "walk":
		# (Stride follows the distance actually walked: no skating feet.)
		pr["stride"] = float(pr["stride"]) + float(pr["speed"]) * float(pr["pace"]) * dt
		target_walk = clampf(float(pr["pace"]) * 1.15, 0.0, 1.0)
	# Step round you; glance at you as you pass.
	var rel := Vector2(me.x - p.x, me.z - p.z)
	var dist := rel.length()
	# (Last resort only: the sidestep above normally keeps them clear.)
	if dist < 0.75 and state != "enter":
		var push := (0.75 - dist) * 0.9
		p -= Vector3(rel.x, 0.0, rel.y).normalized() * push
	var look := 0.0
	if dist < 6.0 and fwd != Vector2.ZERO:
		var ang := fwd.angle_to(rel)
		if absf(ang) < 1.6:
			look = clampf(ang, -0.9, 0.9) * (1.0 - dist / 6.0)
	pr["look"] = lerpf(float(pr["look"]), -look, 1.0 - exp(-4.0 * dt))
	p.y = float(_ground.call(p.x, p.z))
	pr["pos"] = p
	if fwd != Vector2.ZERO:
		pr["yaw"] = lerp_angle(float(pr["yaw"]), atan2(-fwd.x, -fwd.y), 1.0 - exp(-8.0 * dt))
	pr["walk"] = move_toward(float(pr["walk"]), target_walk, dt * 3.0)


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
			var b := Basis(Vector3.UP, float(pr["yaw"])).scaled(Vector3.ONE * float(pr["scale"]))
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
		var sc := float(pr["scale"])
		var b := Basis(Vector3.UP, float(pr["yaw"])).scaled(Vector3(sc, 1.0, sc))
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
