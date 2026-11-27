class_name Apartments
extends RefCounted
## Five homes, each a real room inside a real building of the generated city,
## opening onto the street/skyline through a window you can run out of and
## climb back into.
##
## Placement (deterministic – layout data only, no random draws, so the city
## and the recorded courses don't reshuffle): for each tier, the candidate
## buildings with a tier spanning the tier's floor height and room for the
## room, every face of that tier scored for its view (rays out of the window
## at eye height against every building's box: the longest clear sightlines
## win; a blank wall a few metres away fails), nearest the business district
## breaking ties for the higher tiers. The penthouse goes near the top of the
## tallest building that fits it.
##
## The result is stored on the building (b["apt"]) so BuildingMesher draws
## the facade with the opening (walls_with_opening), collision_boxes() cuts
## the room out of the tier, and features skip the opening. Coordinates are
## the building's lot frame (CityLayout.bxf turns them into the world).

const FLOOR := 3.6
const WALL := 0.3    # outer wall thickness round a home's floor
const SLACK := 4.5   # how much bigger than its spec a home's floor plate may be  # storey height (matches the facade shader's bands)
const TIERS := [
	{"id": "starter", "name": "Quay Studio", "floor": [14.0, 30.0], "w": 12.0, "d": 11.0, "h": 4.0,
		"open_w": 4.2, "sill": 0.0, "open_h": 3.0, "price": 0, "view": 45.0},
	{"id": "city", "name": "City Apartment", "floor": [28.0, 48.0], "w": 16.0, "d": 14.0, "h": 4.2,
		"open_w": 6.4, "sill": 0.0, "open_h": 3.2, "price": 1500, "view": 80.0},
	{"id": "loft", "name": "High-Rise Loft", "floor": [55.0, 90.0], "w": 20.0, "d": 16.0, "h": 6.2,
		"open_w": 10.0, "sill": 0.0, "open_h": 5.2, "price": 4000, "view": 120.0},
	{"id": "sky", "name": "Luxury Sky Apartment", "floor": [95.0, 155.0], "w": 24.0, "d": 18.0, "h": 5.2,
		"open_w": 14.0, "sill": 0.0, "open_h": 4.2, "price": 9000, "view": 160.0},
	{"id": "penthouse", "name": "Ultimate Penthouse", "floor": [-1.0, -1.0], "w": 26.0, "d": 20.0, "h": 7.2,
		"open_w": 22.0, "sill": 0.0, "open_h": 5.8, "price": 20000, "view": 50.0, "cbd": 900.0},
]

## Placed homes: [{id, tier, name, b (building dict), t (tier index), face,
## a0, a1, y0, y1, oa0, oa1, oy0, oy1, depth, price}]. World helpers below.
var homes: Array = []
var _layout: CityLayout
var _grid := {}     # 25 m cell -> Array of world AABBs (view blocking)


static func place(layout: CityLayout) -> Apartments:
	var A := Apartments.new()
	A._layout = layout
	A._index()
	var used := {}
	for ti in TIERS.size():
		var spec: Dictionary = TIERS[ti]
		var best := {}
		var best_s := -INF
		var cands: Array = A._candidates(spec, used)
		for c in cands:
			var s: float = c["score"]
			if s > best_s:
				best_s = s
				best = c
		if best.is_empty():
			continue
		best["id"] = spec["id"]
		best["tier"] = ti
		best["name"] = spec["name"]
		best["price"] = spec["price"]
		best["wins"] = facade_windows(best)
		best["core"] = make_core(best)
		var b: Dictionary = best["b"]
		# Facade geometry needs a building frame, not a circular building→home→building graph.
		var facade_home := best.duplicate()
		facade_home["b"] = b.duplicate()
		b["apt"] = facade_home
		b.erase("_features")  # (re-derived clear of the window)
		A.homes.append(best)
	A._layout = null
	return A


func _index() -> void:
	for b in _layout.buildings:
		if b["kind"] == "invisible":
			continue
		for t in b["tiers"]:
			var box := CityLayout.tier_aabb(b, t)
			for cx in range(floori(box.position.x / 25.0), floori(box.end.x / 25.0) + 1):
				for cz in range(floori(box.position.z / 25.0), floori(box.end.z / 25.0) + 1):
					var k := Vector2i(cx, cz)
					if not _grid.has(k):
						_grid[k] = []
					_grid[k].append(box)


## Free metres along a ray from `p` (world) in horizontal direction `d`, up to `reach`.
func _clear(p: Vector3, d: Vector3, reach: float, skip: Array) -> float:
	var s := 4.0
	while s < reach:
		var q := p + d * s
		for box: AABB in _grid.get(Vector2i(floori(q.x / 25.0), floori(q.z / 25.0)), []):
			if box in skip:
				continue
			if box.has_point(q):
				return s
		if _layout.ground_y(q.x, q.z) > q.y:
			return s
		s += 5.0
	return reach


func _candidates(spec: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	var pent: bool = spec["floor"][0] < 0.0
	var order: Array = _layout.buildings
	if pent:
		# Tallest first: the penthouse wants the city's highest suitable roof.
		order = _layout.buildings.filter(func(b): return b["kind"] == "normal")
		var tall := func(b: Dictionary) -> float: return float(b["tiers"][-1][5]) - BuildingMesher.base_of(b)
		order.sort_custom(func(a, b): return tall.call(a) > tall.call(b))
		order = order.slice(0, 60)  # (a 26 m penthouse needs a broad top: the slimmest supertalls can't hold it)
	for b in order:
		if b["kind"] != "normal" or b.has("apt") or b.has("shape"):
			continue
		var base := BuildingMesher.base_of(b)
		var tiers: Array = b["tiers"]
		for ti in tiers.size():
			var t: Array = tiers[ti]
			var y0: float
			if pent:
				if ti != tiers.size() - 1:
					continue
				# A storey or so under the roof slab (and any crown above).
				y0 = base + floorf((float(t[5]) - base - spec["h"] - 2.4) / FLOOR) * FLOOR
			else:
				var lo: float = spec["floor"][0]
				var hi: float = spec["floor"][1]
				var mid := (lo + hi) * 0.5
				y0 = base + roundf(mid / FLOOR) * FLOOR
				if y0 - base < lo:
					y0 += FLOOR
			if y0 < float(t[4]) + 1.0 or y0 + spec["h"] > float(t[5]) - 1.5:
				continue
			for k in 4:
				var f := BuildingMesher._face(t, k)
				var flen: float = f[3]
				var depth := float(t[3]) - float(t[1]) if k % 2 == 0 else float(t[2]) - float(t[0])
				# The whole floor (360° glass): the room is the storey's footprint
				# inside 0.3 m outer walls, so the tier must be about its size.
				var rw := flen - 2.0 * WALL
				var rd := depth - WALL
				if rw < spec["w"] or rw > spec["w"] + SLACK or rd < spec["d"] or rd > spec["d"] + SLACK:
					continue
				var a0 := WALL
				var a1 := flen - WALL
				var oa0 := (flen - float(spec["open_w"])) * 0.5
				var c := {"b": b, "t": ti, "face": k, "a0": a0, "a1": a1, "y0": y0, "y1": y0 + spec["h"],
					"oa0": oa0, "oa1": oa0 + float(spec["open_w"]), "oy0": y0 + float(spec["sill"]),
					"oy1": y0 + float(spec["sill"]) + float(spec["open_h"]), "depth": rd}
				var view := _view(c, spec)
				if view < 0.0:
					continue
				var s := view
				if not pent:
					var cp := window_center(c)
					s -= Vector2(cp.x, cp.z).distance_to(CityLayout.CBD_CENTER) * (0.05 if spec["price"] > 0 else 0.0)
				else:
					s += (float(t[5]) - base) * 2.0  # height above its street first
				s -= ((rw - float(spec["w"])) + (rd - float(spec["d"]))) * 70.0  # its intended size, not a hall
				c["score"] = s
				out.append(c)
	return out


## Sum of clear sightlines out of the window (straight out and ±28°), or −1
## if the straight-out view is shorter than the tier needs (a wall outside).
func _view(c: Dictionary, spec: Dictionary) -> float:
	var p := window_center(c) + Vector3.UP * 1.6
	var n := outward(c)
	var skip: Array = []
	for t in (c["b"] as Dictionary)["tiers"]:
		skip.append(CityLayout.tier_aabb(c["b"], t))
	var reach := 320.0
	var straight := _clear(p + n * 1.0, n, reach, skip)
	if straight < float(spec["view"]):
		return -1.0
	# Open air under the window too: no neighbour's roof just below the sill
	# (you'd step out onto it, and swing-ins land there instead of the sill).
	if _clear(p + n * 1.0 + Vector3.DOWN * 4.0, n, 30.0, skip) < 30.0:
		return -1.0
	var l := _clear(p + n * 1.0, n.rotated(Vector3.UP, 0.49), reach, skip)
	var r := _clear(p + n * 1.0, n.rotated(Vector3.UP, -0.49), reach, skip)
	var clear := straight + 0.6 * (l + r)
	if float(spec["view"]) < 120.0 and not spec.has("cbd"):
		return clear * 0.08 + _city_below(p + Vector3.UP * 30.0, n, skip) * 28.0
	# High up, an empty view (open sea) is dull: what makes it is city spread
	# out below – rooftops under eye level across the cone in front.
	var to_cbd := Vector3(CityLayout.CBD_CENTER.x - p.x, 0.0, CityLayout.CBD_CENTER.y - p.z).normalized()
	return clear * 0.05 + _city_below(p, n, skip) * 25.0 + float(spec.get("cbd", 150.0)) * n.dot(to_cbd)


func _city_below(p: Vector3, n: Vector3, skip: Array) -> float:
	var hits := 0.0
	for ang: float in [-0.6, -0.3, 0.0, 0.3, 0.6]:
		var d := n.rotated(Vector3.UP, ang)
		var dist := 60.0
		while dist <= 520.0:
			var q := p + d * dist
			for box: AABB in _grid.get(Vector2i(floori(q.x / 25.0), floori(q.z / 25.0)), []):
				if box in skip:
					continue
				if box.end.y < p.y - 5.0 and q.x >= box.position.x and q.x <= box.end.x \
						and q.z >= box.position.z and q.z <= box.end.z:
					hits += 1.0
					break
			dist += 40.0
	return hits


# ------------------------------------------------------------ geometry
## The home's side and back windows as facade openings: [face k of its tier,
## along0, along1, y0, y1] (local frame), from HomeInteriors.windows_for.
static func facade_windows(c: Dictionary) -> Array:
	var out: Array = []
	var t: Array = (c["b"] as Dictionary)["tiers"][c["t"]]
	var f := face_of(c)
	var W := float(c["a1"]) - float(c["a0"])
	var D := float(c["depth"])
	var y0 := float(c["y0"])
	var room := func(x: float, z: float) -> Vector3: return BuildingMesher._fpt(f, float(c["a0"]) + x, -z, 0.0)
	for wd in HomeInteriors.windows_for(int(c["tier"]), W, D, float(c["y1"]) - y0):
		var p0: Vector3
		var p1: Vector3
		match String(wd[0]):
			"back":
				p0 = room.call(wd[1], D)
				p1 = room.call(wd[2], D)
			"left":
				p0 = room.call(0.0, wd[1])
				p1 = room.call(0.0, wd[2])
			_:
				p0 = room.call(W, wd[1])
				p1 = room.call(W, wd[2])
		for k in 4:
			var fk := BuildingMesher._face(t, k)
			var o: Vector3 = fk[0]
			var n: Vector3 = fk[2]
			if absf((p0 - o).dot(n) + WALL) < 0.2 and absf((p1 - o).dot(n) + WALL) < 0.2:
				var u0 := (p0 - o).dot(fk[1])
				var u1 := (p1 - o).dot(fk[1])
				out.append([k, minf(u0, u1), maxf(u0, u1), y0 + float(wd[3]), y0 + float(wd[4])])
				break
	return out


# ------------------------------------------------------------ the core
## The tower core that reaches each home from the street (apartment
## overhaul 2026-11-25: the lift used to be a glass shaft bolted to the
## outside of the facade with its lobby on the pavement, entering through
## the open window wall). Measured in the home's face frame (along a, out o
## – negative inside – and absolute y), so it holds in a building's local
## or world frame alike (Skyport's records are turned):
##   shaft   a_c ± SHAFT_HW, o from the room's back wall (o_back) forward
##           SHAFT_D to the door line o_door, from the ground floor (base)
##           up to the home's floor;
##   hall    the enclosed lift hall on the home's floor in front of the
##           shaft (o_door .. o_hall, HALL_HW either side), the home's front
##           door in its front wall – carved out of the back of the room;
##   lobby   on the ground floor, from the shaft's door line out to the
##           facade of the bottom tier on the same side (o_face0), LOBBY_HW
##           either side, with the street door in that facade (a_f0 along
##           the bottom tier's face).
## a_c is the middle of the widest solid stretch of the back wall (where the
## home's own layout keeps its front door, between the windows).
const SHAFT_HW := 1.35
const SHAFT_D := 2.4
const HALL_HW := 1.6
const HALL_D := 2.1
const LOBBY_HW := 2.6
const LOBBY_H := 3.6
const STREET_DOOR_HW := 1.15
const STREET_DOOR_H := 2.7
## The street entrance's opening by the home's tier (2026-11-27: grander
## the dearer the home): [half width, height, recess depth].
const PORTAL := [[1.15, 2.75, 0.7], [1.3, 2.9, 0.9], [1.4, 3.0, 1.0], [1.55, 3.2, 1.2], [1.75, 3.4, 1.4]]


static func portal(c: Dictionary) -> Array:
	return PORTAL[clampi(int(c.get("tier", 0)), 0, 4)]


static func make_core(c: Dictionary) -> Dictionary:
	var b: Dictionary = c["b"]
	var tiers: Array = b["tiers"]
	var k := int(c["face"])
	var f := face_of(c)
	var W := float(c["a1"]) - float(c["a0"])
	var D := float(c["depth"])
	var H := float(c["y1"]) - float(c["y0"])
	# Solid stretches of the back wall (low windows only: a penthouse's upper
	# row sits above the hall).
	var cuts: Array = []
	for wd in HomeInteriors.windows_for(int(c["tier"]), W, D, H):
		if String(wd[0]) == "back" and float(wd[3]) < 2.8:
			cuts.append(Vector2(float(wd[1]), float(wd[2])))
	cuts.sort_custom(func(x, y): return x.x < y.x)
	var best := Vector2(W * 0.5, 0.0)   # (centre, width)
	var x := 0.4
	for ct: Vector2 in cuts + [Vector2(W - 0.4, W)]:
		var w := ct.x - x
		if w > best.y:
			best = Vector2((x + ct.x) * 0.5, w)
		x = maxf(x, ct.y)
	var xc := clampf(best.x, HALL_HW + 0.5, W - HALL_HW - 0.5)
	var a_c := float(c["a0"]) + xc
	var o_back := -D
	var o_door := o_back + SHAFT_D
	# The bottom tier's facade on the same side, measured in this face's frame.
	var t0: Array = tiers[0]
	var f0 := BuildingMesher._face(t0, k)
	var o_face0 := ((f0[0] as Vector3) - (f[0] as Vector3)).dot(f[2])
	var mid0: Vector3 = BuildingMesher._fpt(f, a_c, o_face0, 0.0)
	var a_f0 := (mid0 - (f0[0] as Vector3)).dot(f0[1])
	var lobby_hw := minf(LOBBY_HW, minf(a_f0, float(f0[3]) - a_f0) - 0.5)
	return {"a_c": a_c, "x": xc, "o_back": o_back, "o_door": o_door, "o_hall": o_door + HALL_D,
		"o_face0": o_face0, "a_f0": a_f0, "base": float(t0[4]), "lobby_hw": maxf(lobby_hw, HALL_HW + 0.2)}


## The core's volumes in the building's local frame (for cutting its
## collision): [lobby, shaft]. Empty when the home has no core.
static func core_cuts(c: Dictionary) -> Array[AABB]:
	var out: Array[AABB] = []
	var k: Dictionary = c.get("core", {})
	if k.is_empty():
		return out
	var f := face_of(c)
	var a_c: float = k["a_c"]
	var base: float = k["base"]
	var lhw: float = k["lobby_hw"]
	out.append(BuildingMesher._fbox(f, a_c - lhw, a_c + lhw, float(k["o_door"]) - 0.05, float(k["o_face0"]) + 0.4, base - 0.2, base + LOBBY_H))
	out.append(BuildingMesher._fbox(f, a_c - SHAFT_HW, a_c + SHAFT_HW, float(k["o_back"]), float(k["o_door"]) + 0.05, base - 0.2, float(c["y0"]) + 0.05))
	return out


## The street door cut in the bottom tier's facade: [face, a0, a1, y0, y1].
static func core_door(c: Dictionary) -> Array:
	var k: Dictionary = c.get("core", {})
	if k.is_empty():
		return []
	var a: float = k["a_f0"]
	var pt := portal(c)
	var hw := minf(float(pt[0]), float(k["lobby_hw"]) - 0.15)
	return [int(c["face"]), a - hw, a + hw, float(k["base"]), float(k["base"]) + float(pt[1])]


## Kept clear of features, plinths and awnings: the street door's opening
## and a few metres in front of it (local frame).
static func door_zone(c: Dictionary) -> AABB:
	var k: Dictionary = c.get("core", {})
	if k.is_empty():
		return AABB()
	var f := face_of(c)
	var a_c: float = k["a_c"]
	var pt := portal(c)
	var hw := float(pt[0]) + 0.75   # (the portal's pilasters and sconces)
	return BuildingMesher._fbox(f, a_c - hw, a_c + hw, float(k["o_face0"]) - 0.6, float(k["o_face0"]) + 3.2,
		float(k["base"]) - 1.0, float(k["base"]) + float(pt[1]) + 1.2)


## A box minus another (axis-aligned): up to six pieces.
static func subtract(box: AABB, cut: AABB) -> Array[AABB]:
	var out: Array[AABB] = []
	if not box.intersects(cut):
		out.append(box)
		return out
	var lo := box.position
	var hi := box.end
	var cl := cut.position.max(lo)
	var ch := cut.end.min(hi)
	if cl.y > lo.y:
		out.append(AABB(lo, Vector3(hi.x, cl.y, hi.z) - lo))
	if ch.y < hi.y:
		out.append(AABB(Vector3(lo.x, ch.y, lo.z), hi - Vector3(lo.x, ch.y, lo.z)))
	if cl.x > lo.x:
		out.append(AABB(Vector3(lo.x, cl.y, lo.z), Vector3(cl.x, ch.y, hi.z) - Vector3(lo.x, cl.y, lo.z)))
	if ch.x < hi.x:
		out.append(AABB(Vector3(ch.x, cl.y, lo.z), Vector3(hi.x, ch.y, hi.z) - Vector3(ch.x, cl.y, lo.z)))
	if cl.z > lo.z:
		out.append(AABB(Vector3(cl.x, cl.y, lo.z), Vector3(ch.x, ch.y, cl.z) - Vector3(cl.x, cl.y, lo.z)))
	if ch.z < hi.z:
		out.append(AABB(Vector3(cl.x, cl.y, ch.z), Vector3(ch.x, ch.y, hi.z) - Vector3(cl.x, cl.y, ch.z)))
	var keep: Array[AABB] = []
	for a in out:
		if a.size.x > 0.005 and a.size.y > 0.005 and a.size.z > 0.005:
			keep.append(a)
	return keep


## Local-frame face of the home's tier.
static func face_of(c: Dictionary) -> Array:
	return BuildingMesher._face((c["b"] as Dictionary)["tiers"][c["t"]], c["face"])


## The room (local frame).
static func room_box(c: Dictionary) -> AABB:
	return BuildingMesher._fbox(face_of(c), c["a0"], c["a1"], -float(c["depth"]), 0.0, c["y0"], c["y1"])


## World: centre of the window opening at sill height, and the outward normal.
static func window_center(c: Dictionary) -> Vector3:
	var f := face_of(c)
	var a := (float(c["oa0"]) + float(c["oa1"])) * 0.5
	var p: Vector3 = BuildingMesher._fpt(f, a, 0.0, c["oy0"])
	return CityLayout.bxf(c["b"]) * p


static func outward(c: Dictionary) -> Vector3:
	return (CityLayout.bxf(c["b"]).basis * (face_of(c)[2] as Vector3)).normalized()


static func along_dir(c: Dictionary) -> Vector3:
	return (CityLayout.bxf(c["b"]).basis * (face_of(c)[1] as Vector3)).normalized()


## World: where the hero wakes up (capsule centre) – inside, facing the window.
static func spawn_point(c: Dictionary) -> Vector3:
	# Near the glass in the big high rooms (so the follow camera, a few metres
	# behind, still looks out over the city), mid-room in the small flats.
	var back := 2.2 if float(c["depth"]) >= 10.0 else minf(float(c["depth"]) * 0.45, 3.0)
	var p := window_center(c) - outward(c) * back
	return Vector3(p.x, float(c["y0"]) + 0.95, p.z)


## Local → world for a point in the face frame (along, out, y).
static func face_point(c: Dictionary, a: float, o: float, y: float) -> Vector3:
	return CityLayout.bxf(c["b"]) * BuildingMesher._fpt(face_of(c), a, o, y)


## World point → face frame [along, out, y] (out > 0 = outside the facade).
static func to_face(c: Dictionary, p: Vector3) -> Vector3:
	var f := face_of(c)
	var q := CityLayout.bxf(c["b"]).affine_inverse() * p
	var d := q - (f[0] as Vector3)
	return Vector3(d.dot(f[1]), d.dot(f[2]), q.y)


## Height of the room's floor above its street (for the UI).
static func floor_height(c: Dictionary) -> float:
	return float(c["y0"]) - BuildingMesher.base_of(c["b"])


## The tier box minus the room: boxes for collision_boxes (local frame),
## plus jambs, lintel and sill framing the opening.
static func split_tier(c: Dictionary, box: AABB) -> Array[AABB]:
	var out: Array[AABB] = []
	var r := room_box(c)
	if not box.intersects(r):
		out.append(box)
		return out
	# Below and above the room: whole footprint.
	if r.position.y > box.position.y:
		out.append(AABB(box.position, Vector3(box.size.x, r.position.y - box.position.y, box.size.z)))
	if r.end.y < box.end.y:
		out.append(AABB(Vector3(box.position.x, r.end.y, box.position.z),
			Vector3(box.size.x, box.end.y - r.end.y, box.size.z)))
	# The room's storey: the footprint minus the room's rectangle.
	var y0 := maxf(r.position.y, box.position.y)
	var y1 := minf(r.end.y, box.end.y)
	var F := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	var R := Rect2(r.position.x, r.position.z, r.size.x, r.size.z).intersection(F)
	for rr in [Rect2(F.position.x, F.position.y, R.position.x - F.position.x, F.size.y),
			Rect2(R.end.x, F.position.y, F.end.x - R.end.x, F.size.y),
			Rect2(R.position.x, F.position.y, R.size.x, R.position.y - F.position.y),
			Rect2(R.position.x, R.end.y, R.size.x, F.end.y - R.end.y)]:
		if rr.size.x > 0.01 and rr.size.y > 0.01:
			out.append(AABB(Vector3(rr.position.x, y0, rr.position.y), Vector3(rr.size.x, y1 - y0, rr.size.y)))
	# Frame round the opening (inside the room's front 0.3 m).
	var f := face_of(c)
	var T := 0.3
	var frame := [[c["a0"], c["oa0"], c["y0"], c["y1"]], [c["oa1"], c["a1"], c["y0"], c["y1"]],
		[c["oa0"], c["oa1"], c["oy1"], c["y1"]], [c["oa0"], c["oa1"], c["y0"], c["oy0"]]]
	for fr in frame:
		if float(fr[1]) - float(fr[0]) > 0.01 and float(fr[3]) - float(fr[2]) > 0.01:
			out.append(BuildingMesher._fbox(f, fr[0], fr[1], -T, 0.0, fr[2], fr[3]))
	return out
