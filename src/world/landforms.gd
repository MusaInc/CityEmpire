class_name Landforms
extends Node3D
## Natural land added round the two city islands, outside their generated
## coasts (which stay exactly as they are, so blocks, units and saves don't
## move): headland parks, beaches, a breakwater harbour. They break up the
## straight quays along the strait between the Commercial Island and
## Westbank. Shared and opt-in like SkyportIsland: static `enabled` (default
## false); a game that sets it gets the land in CityLayout.is_water/ground_y,
## the map, and build().
##
## Each landform: a smooth outline through control points (each with the
## shore kind of the stretch from it: "quay" | "beach" | "rock" | "attach" =
## joined to the island, no shore), a top that follows the quay's height
## where it joins and rises into gentle mounds inland, shore bands down into
## the sea, collision, and park trees.

static var enabled := false
static var _forms: Array = []   # [{name, poly, kinds, bbox, attach_x, layout_side, h0}]
static var _built := false

const SEA_Y := -1.6
const MOUND := 2.6


## The landforms (computed once from the layout: their tops meet its quays).
static func forms(layout: CityLayout = null) -> Array:
	if _built or layout == null:
		return _forms
	_built = true
	var W := CityLayout.RIVER_EDGE           # the Commercial Island's strait quay (x)
	var E := CityLayout.FAR_SHORE            # Westbank's strait quay (x)
	# [name, side (+1: east of the strait on the Commercial Island, -1: Westbank), control points]
	var spec := [
		# (Strait Point and Lighthouse Point wrap the island's square corners
		# on the strait, so neither end of the quay reads as a slab.)
		["Strait Point Park", 1, [
			[Vector2(W + 0.3, -640), "rock"], [Vector2(W - 14, -690), "rock"], [Vector2(W - 58, -722), "rock"],
			[Vector2(W - 112, -704), "beach"], [Vector2(W - 146, -640), "beach"], [Vector2(W - 140, -560), "rock"],
			[Vector2(W - 118, -486), "rock"], [Vector2(W - 126, -410), "beach"], [Vector2(W - 104, -330), "beach"],
			[Vector2(W - 84, -270), "beach"], [Vector2(W - 46, -222), "rock"], [Vector2(W - 12, -204), "rock"],
			[Vector2(W + 0.3, -200), "attach"]]],
		["Lighthouse Point", 1, [
			[Vector2(W + 0.3, 440), "rock"], [Vector2(W - 18, 442), "rock"], [Vector2(W - 54, 470), "beach"],
			[Vector2(W - 78, 524), "beach"], [Vector2(W - 84, 590), "beach"], [Vector2(W - 64, 650), "rock"],
			[Vector2(W - 22, 690), "rock"], [Vector2(W + 0.3, 610), "attach"]]],
		["North Mole", -1, _mole([Vector2(E - 0.3, -421), Vector2(E + 40, -418), Vector2(E + 84, -394), Vector2(E + 106, -352)], 16.0)],
		["South Mole", -1, _mole([Vector2(E - 0.3, -159), Vector2(E + 38, -162), Vector2(E + 80, -186), Vector2(E + 98, -232)], 16.0)],
		["Kestrel Head", -1, [
			[Vector2(E - 0.3, -500), "rock"], [Vector2(E + 14, -546), "rock"], [Vector2(E + 56, -568), "rock"],
			[Vector2(E + 98, -540), "beach"], [Vector2(E + 104, -492), "beach"], [Vector2(E + 74, -456), "rock"],
			[Vector2(E + 26, -444), "rock"], [Vector2(E - 0.3, -442), "attach"]]],
		["Southstrand", -1, [
			[Vector2(E - 0.3, 400), "rock"], [Vector2(E + 24, 402), "rock"], [Vector2(E + 70, 428), "beach"],
			[Vector2(E + 92, 480), "beach"], [Vector2(E + 74, 540), "rock"], [Vector2(E + 30, 566), "rock"],
			[Vector2(E - 0.3, 480), "attach"]]],
		# (Joined along the Commercial Island's own south coast – not a
		# straight quay – so it follows the sea wall exactly: "coast".)
		["Harbour Strand", 1, [
			[Vector2(262, 624), "rock"], [Vector2(270, 646), "rock"], [Vector2(300, 690), "beach"],
			[Vector2(352, 724), "beach"], [Vector2(412, 726), "beach"], [Vector2(462, 694), "rock"],
			[Vector2(482, 652), "rock"], [Vector2(478, 618), "attach"]], "coast"],
		# The Commercial Island's open-sea coasts (joined along the coast
		# itself): a high promontory off the north cliffs, a headland on the
		# east cliffs, a sand spit on the low south-east shore and a rocky
		# point on the straight south edge – the bays between them read as
		# bays.
		["North Cliff Head", 1, [
			[Vector2(612, -612), "rock"], [Vector2(626, -660), "rock"], [Vector2(652, -706), "rock"],
			[Vector2(690, -728), "rock"], [Vector2(728, -712), "rock"], [Vector2(744, -676), "rock"],
			[Vector2(742, -640), "attach"]], "coast"],
		["Cliff Point", 1, [
			[Vector2(1068, -372), "rock"], [Vector2(1110, -380), "rock"], [Vector2(1158, -352), "rock"],
			[Vector2(1186, -304), "rock"], [Vector2(1170, -258), "rock"], [Vector2(1122, -238), "rock"],
			[Vector2(1088, -246), "rock"], [Vector2(1064, -244), "attach"]], "coast"],
		["Eastmouth Spit", 1, [
			[Vector2(986, 262), "rock"], [Vector2(1020, 278), "beach"], [Vector2(1072, 316), "beach"],
			[Vector2(1110, 372), "beach"], [Vector2(1118, 430), "beach"], [Vector2(1092, 468), "rock"],
			[Vector2(1050, 470), "rock"], [Vector2(1024, 452), "attach"]], "coast"],
		["Southgate Point", 1, [
			[Vector2(640, 622), "rock"], [Vector2(652, 660), "rock"], [Vector2(684, 700), "rock"],
			[Vector2(726, 712), "beach"], [Vector2(770, 690), "beach"], [Vector2(790, 652), "rock"],
			[Vector2(786, 622), "attach"]], "coast"],
		# Westbank's open coasts (joined along its own coast; it's hilly, so
		# the high ones fall away to rocky points): a north-west cape, a sand
		# spit on the north shore, a headland off the west hills and a point
		# on the south-west lobe. (The south-east is the Westbank Bridge's.)
		["Hollow Cape", -1, [
			[Vector2(-1066, -386), "rock"], [Vector2(-1104, -404), "rock"], [Vector2(-1140, -446), "rock"],
			[Vector2(-1132, -500), "rock"], [Vector2(-1086, -520), "rock"], [Vector2(-1040, -500), "rock"],
			[Vector2(-1010, -466), "attach"]], "coast"],
		["Northsand Spit", -1, [
			[Vector2(-900, -520), "rock"], [Vector2(-904, -560), "beach"], [Vector2(-880, -604), "beach"],
			[Vector2(-838, -620), "beach"], [Vector2(-800, -596), "beach"], [Vector2(-790, -556), "rock"],
			[Vector2(-798, -504), "attach"]], "coast"],
		["Westhill Head", -1, [
			[Vector2(-1118, 52), "rock"], [Vector2(-1160, 44), "rock"], [Vector2(-1206, 12), "rock"],
			[Vector2(-1214, -34), "rock"], [Vector2(-1176, -64), "beach"], [Vector2(-1124, -66), "beach"],
			[Vector2(-1070, -26), "attach"]], "coast"],
		["Lantern Point", -1, [
			[Vector2(-936, 460), "rock"], [Vector2(-934, 504), "rock"], [Vector2(-904, 544), "rock"],
			[Vector2(-860, 552), "beach"], [Vector2(-826, 524), "beach"], [Vector2(-830, 472), "rock"],
			[Vector2(-862, 414), "attach"]], "coast"],
		["Strand Park", -1, [
			[Vector2(E - 0.3, 100), "rock"], [Vector2(E + 22, 96), "rock"], [Vector2(E + 70, 124), "beach"],
			[Vector2(E + 100, 180), "beach"], [Vector2(E + 96, 248), "beach"], [Vector2(E + 62, 296), "rock"],
			[Vector2(E + 20, 312), "rock"], [Vector2(E - 0.3, 310), "attach"]]],
	]
	for sp in spec:
		var pts := PackedVector2Array()
		var kinds := PackedByteArray()
		var cps: Array = sp[2]
		var n := cps.size()
		for i in n - 1:
			var kind := String(cps[i][1])
			var p1: Vector2 = cps[i][0]
			var p2: Vector2 = cps[i + 1][0]
			var p0: Vector2 = cps[maxi(i - 1, 0)][0]
			var p3: Vector2 = cps[mini(i + 2, n - 1)][0]
			var k := maxi(1, ceili(p1.distance_to(p2) / 8.0))
			var kb := {"quay": 0, "beach": 1, "rock": 2, "attach": 3}[kind] as int
			for j in k:
				var t := float(j) / k
				var straight := kind in ["quay", "attach"] or String(cps[i + 1][1]) == "attach" and kind != "beach" and kind != "rock"
				var q := p1.lerp(p2, t) if straight else SkyportIsland._catmull(p0, p1, p2, p3, t)
				if not straight and j > 0:
					var d := (p2 - p1).normalized()
					var w := sin(q.x * 0.083 + q.y * 0.061) * 0.6 + sin(q.x * 0.21 - q.y * 0.19) * 0.4
					q += Vector2(d.y, -d.x) * w * (1.0 if kind == "beach" else 2.4)
				pts.append(q)
				kinds.append(kb)
		var side: int = sp[1]
		var L: CityLayout = layout if side > 0 else layout.mainland
		var join := PackedVector2Array()
		var join_start := -1
		if sp.size() > 3 and String(sp[3]) == "coast" and L != null:
			# Snap both ends onto the coast and close along it (the shorter way).
			var coast_join := _coast_between(L.coast, cps[n - 1][0], cps[0][0])
			for j in coast_join.size() - 1:
				var a := coast_join[j]
				var b := coast_join[j + 1]
				var count := maxi(1, ceili(a.distance_to(b) / 4.0))
				for k in count:
					join.append(a.lerp(b, float(k) / count))
			join.append(coast_join[-1])
			pts[0] = join[join.size() - 1]
			join_start = pts.size()
			for v in join:
				pts.append(v)
				kinds.append(3)
			pts.remove_at(pts.size() - 1)
			kinds.remove_at(kinds.size() - 1)
		else:
			var end: Vector2 = cps[n - 1][0]
			var start := pts[0]
			var count := maxi(1, ceili(end.distance_to(start) / 4.0))
			for j in count:
				pts.append(end.lerp(start, float(j) / count))
				kinds.append(3)
		var ax := W + 4.0 if side > 0 else E - 4.0
		var bb := Rect2(pts[0], Vector2.ZERO)
		for v in pts:
			bb = bb.expand(v)
		var f := {"name": sp[0], "poly": pts, "kinds": kinds, "bbox": bb, "attach_x": ax, "side": side, "L": L,
			"paved": String(sp[0]).ends_with("Mole")}
		if not join.is_empty():
			var heights := PackedFloat32Array()
			for v in join:
				heights.append(L.terrain.road_y(v.x, v.y) + CityTerrain.KERB)
			f["join"] = join
			f["jh"] = heights
			f["join_i"] = join_start

		_forms.append(f)
	return _forms


## A breakwater: quay sides along a centreline, a rounded rock head, the
## root attached to the quay. Returns control points like the other specs.
static func _mole(c: Array, w: float) -> Array:
	var hw := w * 0.5
	var left: Array = []
	var right: Array = []
	for i in c.size():
		var a: Vector2 = c[maxi(i - 1, 0)]
		var b: Vector2 = c[mini(i + 1, c.size() - 1)]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		left.append(c[i] + n * hw)
		right.append(c[i] - n * hw)
	var out: Array = [[c[0] + (left[0] - c[0]), "attach"]]
	out[0] = [Vector2((c[0] as Vector2).x, (left[0] as Vector2).y), "quay"]
	for i in range(1, c.size()):
		out.append([left[i], "quay" if i < c.size() - 1 else "rock"])
	# Round head: a half circle round the tip.
	var tip: Vector2 = c[-1]
	var d2 := (tip - (c[-2] as Vector2)).normalized()
	var n2 := Vector2(-d2.y, d2.x)
	for k in range(1, 4):
		var ang := PI * k / 4.0
		out.append([tip + n2 * cos(ang) * hw + d2 * sin(ang) * hw * 1.2, "rock"])
	for i in range(c.size() - 1, 0, -1):
		out.append([right[i], "quay"])
	out.append([Vector2((c[0] as Vector2).x, (right[0] as Vector2).y), "attach"])
	return out


## The coast from a to b (each snapped to its nearest coast vertex), the
## shorter way round.
static func _coast_between(coast: PackedVector2Array, a: Vector2, b: Vector2) -> PackedVector2Array:
	var ia := 0
	var ib := 0
	for i in coast.size():
		if coast[i].distance_squared_to(a) < coast[ia].distance_squared_to(a):
			ia = i
		if coast[i].distance_squared_to(b) < coast[ib].distance_squared_to(b):
			ib = i
	var n := coast.size()
	var fwd := PackedVector2Array()
	var i := ia
	while true:
		fwd.append(coast[i])
		if i == ib:
			break
		i = (i + 1) % n
	var back := PackedVector2Array()
	i = ia
	while true:
		back.append(coast[i])
		if i == ib:
			break
		i = (i - 1 + n) % n
	return fwd if fwd.size() <= back.size() else back


## Distance from q to where the landform joins its island.
static func _join_dist(f: Dictionary, q: Vector2) -> float:
	if not f.has("join"):
		return absf(q.x - float(f["attach_x"]))
	var j: PackedVector2Array = f["join"]
	var best := INF
	for i in j.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, j[i], j[i + 1]).distance_to(q))
	return best


## The island's height where the landform joins it, nearest q.
static func _base_h(f: Dictionary, q: Vector2) -> float:
	if not f.has("join"):
		return _quay_h(f, q.y)
	var j: PackedVector2Array = f["join"]
	var jh: PackedFloat32Array = f["jh"]
	var best := INF
	var h := jh[0]
	for i in j.size() - 1:
		var cp := Geometry2D.get_closest_point_to_segment(q, j[i], j[i + 1])
		var d := cp.distance_to(q)
		if d < best:
			best = d
			var L := j[i].distance_to(j[i + 1])
			h = lerpf(jh[i], jh[i + 1], cp.distance_to(j[i]) / maxf(L, 0.01))
	return h


static func _quay_h(f: Dictionary, z: float) -> float:
	var layout: CityLayout = f["L"]
	if layout == null:
		return CityTerrain.KERB
	var edge_x := CityLayout.RIVER_EDGE if int(f["side"]) > 0 else CityLayout.FAR_SHORE
	return layout.terrain.road_y(edge_x, z) + CityTerrain.KERB


## The landform containing (x, z), or {}.
static func at(x: float, z: float) -> Dictionary:
	if not enabled:
		return {}
	var q := Vector2(x, z)
	for f: Dictionary in _forms:
		if (f["bbox"] as Rect2).grow(0.5).has_point(q) and Geometry2D.is_point_in_polygon(q, f["poly"]):
			return f
	return {}


static func contains(x: float, z: float) -> bool:
	return not at(x, z).is_empty()


## Ground height on a landform (NAN off them): the quay's height where it
## joins, easing up into low mounds away from the join and the shore.
static func ground_y(x: float, z: float) -> float:
	var f := at(x, z)
	if f.is_empty():
		return NAN
	return _height(f, x, z)


static func _height(f: Dictionary, x: float, z: float) -> float:
	var base := _base_h(f, Vector2(x, z))
	var from_join := _join_dist(f, Vector2(x, z))
	if f.has("join") and base > 6.0:
		# Joined to a cliff top: the headland falls away towards its point
		# (a flat-topped drum at cliff height looked built, not grown).
		base = lerpf(base, maxf(4.0, base * 0.3), smoothstep(8.0, 95.0, from_join))
	var edge := _edge_dist(f, Vector2(x, z))
	var k := smoothstep(14.0, 50.0, from_join) * smoothstep(4.0, 30.0, edge) * (0.0 if f.get("paved", false) else 1.0)
	var hill := (sin(x * 0.031 + z * 0.017) * 0.5 + 0.5) * (sin(x * 0.012 - z * 0.027 + 1.3) * 0.5 + 0.5)
	return base + MOUND * hill * k


static func _edge_dist(f: Dictionary, q: Vector2) -> float:
	var o: PackedVector2Array = f["poly"]
	var kinds: PackedByteArray = f["kinds"]
	var best := INF
	for i in o.size():
		if kinds[i] == 3:
			continue
		var cp := Geometry2D.get_closest_point_to_segment(q, o[i], o[(i + 1) % o.size()])
		best = minf(best, cp.distance_to(q))
	return best


## Esplanade railing openings where a landform joins (BuildingMesher.rail_gaps).
static func rail_gaps() -> Array:
	var out: Array = []
	for f: Dictionary in _forms:
		var bb: Rect2 = f["bbox"]
		if f.has("join"):
			var jr := Rect2((f["join"] as PackedVector2Array)[0], Vector2.ZERO)
			for v in (f["join"] as PackedVector2Array):
				jr = jr.expand(v)
			out.append(jr.grow(-6.0).grow_individual(0.0, 12.0, 0.0, 12.0) if jr.size.x > jr.size.y else jr.grow(-6.0).grow_individual(12.0, 0.0, 12.0, 0.0))
		else:
			out.append(Rect2(float(f["attach_x"]) - 12.0, bb.position.y + 6.0, 24.0, bb.size.y - 12.0))
	return out


# ------------------------------------------------------------------ build
var _mat: ShaderMaterial


func build(layout: CityLayout) -> void:
	forms(layout)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/world/shaders/island_ground.gdshader")
	_mat.set_shader_parameter("asph_tex", load("res://assets/textures/pbr/worldstate_street_asphalt.png"))
	_mat.set_shader_parameter("pave_tex", load("res://assets/textures/pbr/worldstate_pavement_concrete.png"))
	_mat.set_shader_parameter("pbr_on", true)
	var body := StaticBody3D.new()
	body.name = "LandformCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for f: Dictionary in _forms:
		_build_form(f, body)
		await LoadPacer.pace(get_tree())


func _build_form(f: Dictionary, body: StaticBody3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var o: PackedVector2Array = f["poly"]
	var kinds: PackedByteArray = f["kinds"]
	var bb: Rect2 = f["bbox"]
	# Top: outline + interior grid, Delaunay, triangles inside kept.
	var pts := PackedVector2Array(o)
	var gx := bb.position.x + 5.0
	while gx < bb.end.x:
		var gz := bb.position.y + 5.0
		while gz < bb.end.y:
			var q := Vector2(gx + sin(gz * 0.7) * 1.5, gz + sin(gx * 0.9) * 1.5)
			if Geometry2D.is_point_in_polygon(q, o) and _edge_dist(f, q) > 3.0:
				pts.append(q)
			gz += 9.0
		gx += 9.0
	var tri := Geometry2D.triangulate_delaunay(pts)
	var grass := Color(0.33, 0.47, 0.26, 1.5 / 8.0)
	for i in range(0, tri.size(), 3):
		var a := pts[tri[i]]
		var b := pts[tri[i + 1]]
		var c := pts[tri[i + 2]]
		if not Geometry2D.is_point_in_polygon((a + b + c) / 3.0, o):
			continue
		var vs := [a, b, c]
		var v3: Array = []
		for v: Vector2 in vs:
			v3.append(Vector3(v.x, _height(f, v.x, v.y), v.y))
		var nrm := ((v3[1] as Vector3) - (v3[0] as Vector3)).cross((v3[2] as Vector3) - (v3[0] as Vector3))
		if nrm.y > 0.0:
			v3 = [v3[0], v3[2], v3[1]]
			nrm = -nrm
		nrm = -nrm.normalized()
		for v: Vector3 in v3:
			# A sandy fringe along beach stretches, a gravel path ring inland.
			var e := _beach_dist(f, Vector2(v.x, v.z))
			# (The beach edge is drawn by the shader from the distance in
			# UV2.x (negative = "metres to the beach + 1"): vertex colours
			# zig-zagged along the 9 m triangles as beige patches.)
			var col := grass
			var marker := 0.0
			# (Capped, never 0 on a landform: a 0 beside a capped vertex
			# interpolated through "near a beach" and drew a sand line.)
			var beach := -(minf(e, 40.0) + 1.0)
			if f.get("paved", false):
				col = Color(0.6, 0.59, 0.56, 0.5 / 8.0)
				beach = 0.0
			st.set_color(col)
			st.set_normal(nrm)
			st.set_uv(Vector2(v.x, v.z))
			st.set_uv2(Vector2(beach, marker))
			st.add_vertex(v)
			faces.append(v)
	# Shore bands round the free edges.
	for i in o.size():
		var k := kinds[i]
		if k == 3:
			continue
		var j := (i + 1) % o.size()
		var A := _row(f, o, i, k)
		var B := _row(f, o, j, k)
		for r in A.size() - 1:
			var q := [A[r], B[r], B[r + 1], A[r + 1]]
			# (Wind so the visible side faces up / out to sea: Godot fronts
			# are clockwise, i.e. their normal is (c - a) x (b - a).)
			var nn2 := SkyportIsland._out_n(o, i)
			var want := Vector3(nn2.x, 1.0, nn2.y)
			var vis := ((q[2] as Vector3) - (q[0] as Vector3)).cross((q[1] as Vector3) - (q[0] as Vector3))
			var order := [0, 1, 2, 0, 2, 3] if vis.dot(want) >= 0.0 else [0, 2, 1, 0, 3, 2]
			var col2 := Color(0.55, 0.53, 0.5) if k == 0 else (Color(0.8, 0.72, 0.55) if k == 1 else Color(0.42, 0.4, 0.37))
			for idx in order:
				var v: Vector3 = q[idx]
				var cc := col2
				if k == 1 and v.y < -1.2 and v.y > -2.2:
					cc = col2.darkened(0.12)   # (the swash band only: below it the water tints it)
				elif k == 2 and r == 0 and idx < 2:
					# (Scrub over the rock's top edge: turf doesn't stop on a
					# ruled line where the rock begins.)
					cc = Color(0.3, 0.36, 0.22)
				cc.a = 0.5 / 8.0
				st.set_color(cc)
				st.set_uv(Vector2(v.x, v.z))
				st.set_uv2(Vector2(0.0, -1.0))
				st.add_vertex(v)
				faces.append(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = String(f["name"]).replace(" ", "")
	mi.mesh = st.commit()
	mi.material_override = _mat
	mi.visibility_range_end = 4000.0
	add_child(mi)
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = sh
	body.add_child(cs)
	_trees(f)
	_foam(f)


func _beach_dist(f: Dictionary, q: Vector2) -> float:
	var o: PackedVector2Array = f["poly"]
	var kinds: PackedByteArray = f["kinds"]
	var best := INF
	for i in o.size():
		if kinds[i] != 1:
			continue
		var cp := Geometry2D.get_closest_point_to_segment(q, o[i], o[(i + 1) % o.size()])
		best = minf(best, cp.distance_to(q))
	return best


## A profile row at outline point i (kind k): from the top's edge down to the
## sea bed, 1 + BuildingMesher.SHORE_ROWS points (the first is the top's
## edge). Where the landform leaves its island's coast (the two ends of its
## join) the row IS the city's shore row there, under the top's edge, so
## the city's apron and the landform's bands meet on one line (they used to
## cross: rock and sand slabs through each other at every headland). Rows
## are clamped to under half the open water in front (BuildingMesher.
## shore_reach), so they never cross a neighbour's.
func _row(f: Dictionary, o: PackedVector2Array, i: int, k: int) -> PackedVector3Array:
	var p := o[i]
	var nn := SkyportIsland._out_n(o, i)
	var top := _height(f, p.x, p.y)
	var row := PackedVector3Array()
	row.append(Vector3(p.x, top, p.y))
	var L: CityLayout = f.get("L")
	if f.has("join") and L != null and (i == 0 or i == int(f.get("join_i", -1))):
		var cr: Array = BuildingMesher.shore_row_at(L, p)[0]
		if cr.size() == BuildingMesher.SHORE_ROWS:
			for v: Vector3 in cr:
				row.append(Vector3(v.x, minf(v.y, top - 0.05), v.z))
			return row
	var prof: Array
	match k:
		0:
			prof = [[0.0, top], [0.0, top - 2.0], [0.0, 0.0], [0.0, -1.0], [0.0, -2.0], [0.0, -4.0], [0.0, -6.0], [0.0, -9.0]]
		1:
			prof = [[0.0, top], [4.0, lerpf(top, 0.15, 0.4)], [8.0, lerpf(top, 0.15, 0.75)], [12.0, 0.15], [17.0, -0.6],
				[23.0, -1.6], [32.0, -4.0], [46.0, -9.0]]
		_:
			# (A high top gets wider, sloping rocky flanks, not a wall.)
			var sc := clampf(top / 5.0, 1.0, 4.0)
			prof = [[0.0, top], [1.6 * sc, top - 0.3 - top * 0.12], [3.0 * sc, top - 0.5 - top * 0.3],
				[5.0 * sc, lerpf(top, 0.1, 0.75)], [7.0 * sc, 0.1], [9.5 * sc, -1.0], [13.0 * sc, -3.2], [18.0 * sc, -9.0]]
	var reach := BuildingMesher.shore_reach(L, p, nn) if L != null else 999.0
	var ext: float = prof[-1][0]
	var sc2 := minf(1.0, reach / maxf(ext, 0.01))
	prof = BuildingMesher.fit_row(prof, reach)
	for r in prof.size():
		var d: float = prof[r][0]
		var y: float = prof[r][1]
		if k == 2 and r > 0 and r < prof.size() - 1:
			var hh := sin(p.x * 1.37 + p.y * 0.91 + r * 2.1) * 0.5 + sin(p.x * 0.43 - p.y * 1.7 + r) * 0.5
			d += hh * 1.6 * sc2
			y += hh * 0.45
		row.append(Vector3(p.x + nn.x * d, y, p.y + nn.y * d))
	SeabedMesh.tuck(row)
	return row


func _trees(f: Dictionary) -> void:
	if f.get("paved", false):
		return
	# (2026-11-25) A designed park instead of a tree every 2,700 m² at random
	# (the headlands read as bare golf greens): a gravel loop path inset from
	# the shore, copses and lone specimen trees in the lawns either side of
	# it, shrub and flower beds where the path bends, benches and lamps along
	# it, tufts of long grass towards the shore.
	var o: PackedVector2Array = f["poly"]
	var bb: Rect2 = f["bbox"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(f["name"]))
	var by_sp := {}
	var plant := {}   # FoliageKit name -> [Transform3D]
	var add_tree := func(q: Vector2, s: float) -> void:
		var p := Vector3(q.x, _height(f, q.x, q.y), q.y)
		var sp := TreeKit.pick(p, true)
		if not by_sp.has(sp):
			by_sp[sp] = []
		by_sp[sp].append(Transform3D(TreeKit.shape(p, s), p))
	var add_plant := func(nm: String, q: Vector2, s: float) -> void:
		if not plant.has(nm):
			plant[nm] = []
		var p := Vector3(q.x, _height(f, q.x, q.y) - 0.04, q.y)
		(plant[nm] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
	var land := func(q: Vector2, edge_min: float) -> bool:
		return Geometry2D.is_point_in_polygon(q, o) and _edge_dist(f, q) > edge_min and _beach_dist(f, q) > edge_min + 2.0
	# The path: the outline inset 18 m (smoothed), only on the landform.
	var path: PackedVector2Array = PackedVector2Array()
	var ins := Geometry2D.offset_polygon(o, -18.0)
	if not ins.is_empty():
		var ring: PackedVector2Array = ins[0]
		var L := 0.0
		for i in ring.size():
			L += ring[i].distance_to(ring[(i + 1) % ring.size()])
		var n := maxi(12, int(L / 4.0))
		var acc := 0.0
		var i := 0
		for k in n:
			var target := L * k / n
			while i < ring.size() - 1 and acc + ring[i].distance_to(ring[i + 1]) < target:
				acc += ring[i].distance_to(ring[i + 1])
				i += 1
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			var seg := maxf(a.distance_to(b), 0.01)
			path.append(a.lerp(b, clampf((target - acc) / seg, 0.0, 1.0)))
	if path.size() > 8:
		_path_mesh(f, path)
		var benches: Array = []
		var lamps: Array = []
		for k in range(0, path.size(), 7):
			var a := path[k]
			var b := path[(k + 1) % path.size()]
			var d := (b - a).normalized()
			var nrm := Vector2(-d.y, d.x)
			if not Geometry2D.is_point_in_polygon(a + nrm * 3.0, o):
				nrm = -nrm
			# Alternate: a bench facing the path (its back to the lawn), a
			# lamp, or a shrub bed.
			var kind := k / 7 % 3
			var q := a + nrm * 2.6
			if kind == 0 and land.call(q, 4.0):
				var p := Vector3(q.x, _height(f, q.x, q.y), q.y)
				benches.append(Transform3D(Basis(Vector3.UP, atan2(-nrm.x, -nrm.y) + PI), p))
				add_plant.call("bush_low", q + nrm * 1.8, rng.randf_range(0.8, 1.1))
			elif kind == 1:
				var lq := a - nrm * 2.2
				if land.call(lq, 3.0):
					lamps.append(Transform3D(Basis(Vector3.UP, atan2(nrm.x, nrm.y)), Vector3(lq.x, _height(f, lq.x, lq.y), lq.y)))
			else:
				for j in 3:
					var bq := q + nrm * (1.0 + j * 0.9) + d * rng.randf_range(-1.6, 1.6)
					if land.call(bq, 3.0):
						add_plant.call(["flower_bed", "bush_round", "box_ball"][j], bq, rng.randf_range(0.8, 1.15))
		_furniture(benches, lamps)
	# Copses (a group of 4–8 trees, shrubs round their feet) and lone trees.
	var copses := maxi(2, int(bb.get_area() / 9000.0))
	for c in copses * 3:
		if copses <= 0:
			break
		var cq := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
		if not land.call(cq, 12.0) or _near_path(path, cq, 7.0):
			continue
		copses -= 1
		for t in rng.randi_range(4, 8):
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 9.0
			var q := cq + Vector2(cos(a), sin(a)) * r
			if land.call(q, 10.0) and not _near_path(path, q, 4.0):
				add_tree.call(q, rng.randf_range(0.85, 1.25))
		for t in 6:
			var a := rng.randf() * TAU
			var q := cq + Vector2(cos(a), sin(a)) * rng.randf_range(8.0, 12.0)
			if land.call(q, 6.0) and not _near_path(path, q, 2.5):
				add_plant.call(["bush_round", "shrub_tall", "bush_low"][t % 3], q, rng.randf_range(0.8, 1.2))
	var singles := int(bb.get_area() / 3000.0)
	for i in singles * 3:
		if singles <= 0:
			break
		var q := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
		if land.call(q, 14.0) and not _near_path(path, q, 5.0):
			add_tree.call(q, rng.randf_range(0.9, 1.3))
			singles -= 1
	# Long grass towards the shore (between the lawn and the beach / rocks).
	for i in int(bb.get_area() / 90.0):
		var q := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
		if Geometry2D.is_point_in_polygon(q, o):
			var e: float = _edge_dist(f, q)
			if e > 5.0 and e < 14.0 and _beach_dist(f, q) > 6.0:
				add_plant.call("grass_tuft", q, rng.randf_range(0.9, 1.5))
	for sp: String in by_sp:
		TreeKit.instance_batch(self, sp, by_sp[sp], 900.0, true, 46.0)
		if TreeImpostors.ready():
			TreeImpostors.place(self, {sp: by_sp[sp]}, 880.0, 2600.0)
	FoliageKit.place(self, plant, 240.0)


static func _near_path(path: PackedVector2Array, q: Vector2, r: float) -> bool:
	for i in path.size():
		if Geometry2D.get_closest_point_to_segment(q, path[i], path[(i + 1) % path.size()]).distance_to(q) < r:
			return true
	return false


## The gravel loop: a 2.6 m strip draped on the ground, edged with timber.
func _path_mesh(f: Dictionary, path: PackedVector2Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := path.size()
	var hw := 1.3
	for i in n:
		var a := path[i]
		var b := path[(i + 1) % n]
		var d := (b - a).normalized()
		var nr := Vector2(-d.y, d.x) * hw
		var pa := path[(i - 1 + n) % n]
		var da := (a - pa).normalized()
		var na := Vector2(-da.y, da.x) * hw
		var nm := ((na + nr) * 0.5).normalized() * hw
		var nb := ((nr + Vector2(-((path[(i + 2) % n] - b).normalized()).y, ((path[(i + 2) % n] - b).normalized()).x) * hw) * 0.5).normalized() * hw
		var A0 := a + nm
		var A1 := a - nm
		var B0 := b + nb
		var B1 := b - nb
		var y := func(q: Vector2) -> float: return _height(f, q.x, q.y) + 0.035
		var v := [Vector3(A0.x, y.call(A0), A0.y), Vector3(B0.x, y.call(B0), B0.y), Vector3(B1.x, y.call(B1), B1.y),
			Vector3(A1.x, y.call(A1), A1.y)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v[idx].x, v[idx].z) * 0.5)
			st.add_vertex(v[idx])
	var mi := MeshInstance3D.new()
	mi.name = "ParkPath"
	mi.mesh = st.commit()
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.74, 0.69, 0.6)
	gm.roughness = 0.95
	gm.albedo_texture = load("res://assets/textures/pbr/worldstate_pavement_concrete.png")
	gm.uv1_scale = Vector3(0.25, 0.25, 1.0)
	mi.material_override = gm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 900.0
	add_child(mi)


## Benches and lamp posts (the city's own models) as MultiMeshes.
func _furniture(benches: Array, lamps: Array) -> void:
	for pair: Array in [["bench", benches], ["streetlight", lamps]]:
		var xfs: Array = pair[1]
		var path := "res://assets/models/%s.glb" % pair[0]
		if xfs.is_empty() or not ResourceLoader.exists(path):
			continue
		var inst := (load(path) as PackedScene).instantiate()
		var mis := inst.find_children("*", "MeshInstance3D", true, false)
		var m: Mesh = (mis[0] as MeshInstance3D).mesh if not mis.is_empty() else null
		inst.free()
		if m == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Park_" + String(pair[0])
		mmi.multimesh = mm
		mmi.visibility_range_end = 400.0
		add_child(mmi)


func _foam(f: Dictionary) -> void:
	# (At the water's edge on each row: the sea is at -1.6.)
	var o: PackedVector2Array = f["poly"]
	var kinds: PackedByteArray = f["kinds"]
	var wl := PackedVector2Array()
	var ok := PackedByteArray()
	for i in o.size():
		var k := kinds[i] if kinds[i] != 3 else kinds[(i - 1 + o.size()) % o.size()]
		var row := _row(f, o, i, k)
		var q := o[i]
		var found := 0
		for j in row.size() - 1:
			if row[j].y >= BuildingMesher.SEA_SURFACE and row[j + 1].y < BuildingMesher.SEA_SURFACE:
				var v := row[j].lerp(row[j + 1], (row[j].y - BuildingMesher.SEA_SURFACE) / maxf(row[j].y - row[j + 1].y, 0.001))
				q = Vector2(v.x, v.z)
				found = 1
				break
		wl.append(q)
		ok.append(found)
	var edges: Array = []
	for i in o.size():
		if kinds[i] == 3:
			continue
		var j := (i + 1) % o.size()
		if ok[i] == 0 or ok[j] == 0 or wl[i].distance_to(wl[j]) > 30.0:
			continue
		var a := wl[i]
		var b := wl[j]
		var dd := (b - a).normalized()
		var on := Vector2(dd.y, -dd.x)
		if on.dot(SkyportIsland._out_n(o, i)) < 0.0:
			on = -on
		edges.append([a, b, on])
	if not edges.is_empty():
		add_child(Shoreline.build(edges))
