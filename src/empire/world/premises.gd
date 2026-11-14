class_name Premises
extends RefCounted
## Commercial units cut into the ground floors of real buildings of the
## shared city (both landmasses), plus the wholesale warehouses.
##
## Same machinery as CitySwing's apartments: a unit is stored on its
## building as b["apt"] (with "ground": true), so BuildingMesher draws the
## facade with the shopfront opening, collision_boxes() cuts the room out of
## the tier and the occluder stops below it. Placement is deterministic
## (layout data only, no random draws) so the city never reshuffles.
##
## A unit: {id, kind ("shop"|"wholesale"), name, shop_name, district
## (island:district), island, size (m²), rent (£/day), price (£), b, t, face,
## a0, a1, y0, y1, oa0, oa1, oy0, oy1, depth, pos [x,y,z] (door, world)}.

const SHOP := {"w": [9.0, 14.0], "d": [9.0, 13.0], "h": 4.2, "open_w": 6.0, "open_h": 3.1, "full_front": true}
const WAREHOUSE := {"w": [18.0, 30.0], "d": [14.0, 22.0], "h": 6.5, "open_w": 7.0, "open_h": 4.6}
const WAREHOUSE_SMALL := {"w": [13.0, 22.0], "d": [11.0, 18.0], "h": 5.2, "open_w": 6.5, "open_h": 4.2}
## Shops wanted per district (the best-scoring units, spread out).
const QUOTA := {"west:suburb": 4, "west:midtown": 3, "west:waterfront": 2, "east:docks": 2, "east:midtown": 3,
	"east:cbd": 3, "east:waterfront": 3, "east:georgian": 3}
const SPACING := 110.0
## Second pass: smaller units along every shopping street, already trading
## (independent shops) or empty. Placed after the 24 originals so their ids
## (and old saves) don't change.
const SHOP_SMALL := {"w": [9.0, 12.5], "d": [9.6, 12.5], "h": 4.2, "open_w": 5.0, "open_h": 3.1, "full_front": true}
const EST_SPACING := 42.0
const EST_QUOTA := 14
## Third pass: the corporate head office – a marble lobby cut into the
## tallest CBD tower that has room on its street (placed last: every
## earlier id holds).
const HQ := {"w": [11.0, 16.0], "d": [9.0, 13.0], "h": 5.0, "open_w": 5.2, "open_h": 3.6}
const HQ_DISTRICT := "east:cbd"
## Fourth pass: office lobbies in the other tall towers, where you can open
## office companies (Offices). Placed after the head office: every earlier
## id holds.
const OFFICE := {"w": [10.0, 14.0], "d": [9.0, 12.0], "h": 4.6, "open_w": 4.6, "open_h": 3.4}
const OFFICE_QUOTA := {"east:cbd": 3, "east:midtown": 2, "east:waterfront": 1, "east:docks": 1}
const OFFICE_MIN_H := 28.0
const WHOLESALERS := {"west:waterfront": "Quayside Cash & Carry", "east:docks": "Harbour Wholesale Market"}
const NAMES := ["Corner Shop", "Daily Stop", "Night & Day", "Local Store", "Mini Market", "Express", "Grab & Go",
	"Neighbourhood Store", "Village Shop", "City Stop", "Quick Mart", "Late Shop", "Food & Wine", "The Kiosk",
	"Market Corner", "Parade Stores", "Fresh Stop", "High Street Express", "Harbour Stores", "Square Mini Market",
	"Station Store", "Hilltop Shop", "Promenade Stores", "Avenue Express"]

var units: Array = []
var _layout: CityLayout
var _grid := {}


static func place(layout: CityLayout) -> Premises:
	var P := Premises.new()
	P._layout = layout
	P._index()
	var island := "west" if layout.is_mainland else "east"
	# Wholesalers first (they want the biggest frontages).
	for key in WHOLESALERS:
		if not String(key).begins_with(island):
			continue
		var best := P._best(key, WAREHOUSE, [])
		if best.is_empty():
			# Smaller trade counter (and the neighbouring districts) before none at all.
			for k2 in [key, island + ":midtown", island + ":suburb"]:
				best = P._best(k2, WAREHOUSE_SMALL, [])
				if not best.is_empty():
					break
		if not best.is_empty():
			best["kind"] = "wholesale"
			best["name"] = WHOLESALERS[key]
			P._claim(best)
	var cands: Array = []
	for key in QUOTA:
		if String(key).begins_with(island):
			cands.append_array(P._candidates(key, SHOP))
	cands.sort_custom(func(a, b): return a["score"] > b["score"])
	var per := {}
	for c in cands:
		var key: String = c["district"]
		if int(per.get(key, 0)) >= int(QUOTA[key]):
			continue
		if c["b"].has("apt") or not P._far_from_others(c):
			continue
		c["kind"] = "shop"
		P._claim(c)
		per[key] = int(per.get(key, 0)) + 1
	# Established units: the rest of the high street.
	var est: Array = []
	for key in QUOTA:
		if String(key).begins_with(island):
			est.append_array(P._candidates(key, SHOP_SMALL))
	est.sort_custom(func(a, b): return a["score"] > b["score"])
	var per2 := {}
	for c in est:
		var key: String = c["district"]
		if int(per2.get(key, 0)) >= EST_QUOTA or c["b"].has("apt") or not P._far_from_others(c, EST_SPACING):
			continue
		c["kind"] = "shop"
		c["est"] = true
		P._claim(c)
		per2[key] = int(per2.get(key, 0)) + 1
	# The head-office tower (the island with the CBD only).
	if HQ_DISTRICT.begins_with(island):
		var best_hq := {}
		for c in P._candidates(HQ_DISTRICT, HQ):
			var b: Dictionary = c["b"]
			if b.has("apt") or not P._far_from_others(c, 20.0):
				continue
			var top := 0.0
			for t in b["tiers"]:
				top = maxf(top, float(t[5]))
			c["score"] = float(c["score"]) * 0.25 + (top - float(c["y0"]))
			c["tower_h"] = top - float(c["y0"])
			if best_hq.is_empty() or float(c["score"]) > float(best_hq["score"]):
				best_hq = c
		if not best_hq.is_empty():
			best_hq["kind"] = "hq"
			best_hq["name"] = "Meridian Tower"
			P._claim(best_hq)
	# Office towers (the Commercial Island).
	if not layout.is_mainland:
		var offs: Array = []
		for key in OFFICE_QUOTA:
			for c in P._candidates(key, OFFICE):
				var b: Dictionary = c["b"]
				if b.has("apt") or not P._far_from_others(c, 60.0):
					continue
				var top := 0.0
				for t in b["tiers"]:
					top = maxf(top, float(t[5]))
				if top - float(c["y0"]) < OFFICE_MIN_H:
					continue
				c["score"] = float(c["score"]) * 0.3 + (top - float(c["y0"])) * 0.5
				offs.append(c)
		offs.sort_custom(func(a, b): return a["score"] > b["score"])
		var per3 := {}
		var towers: Array = EmpireData.file("offices").get("towers", [])
		var ti := 0
		for c in offs:
			var key: String = c["district"]
			if int(per3.get(key, 0)) >= int(OFFICE_QUOTA[key]) or c["b"].has("apt") or not P._far_from_others(c, 60.0):
				continue
			c["kind"] = "office"
			c["name"] = towers[ti % towers.size()] if not towers.is_empty() else "Office tower"
			ti += 1
			P._claim(c)
			per3[key] = int(per3.get(key, 0)) + 1
	# Names, rents and prices.
	var n := 0
	for u in P.units:
		# Stable across placement changes (saves refer to it): kind + door position.
		u["id"] = "%s_%d_%d" % [u["kind"], roundi(float(u["pos"][0])), roundi(float(u["pos"][2]))]
		if u["kind"] == "shop":
			u["name"] = "Unit %d, %s" % [n + 1, EmpireData.district(u["district"]).get("name", u["district"])]
			u["shop_name"] = NAMES[(n * 7 + (5 if island == "east" else 0)) % NAMES.size()]
		var k := float(EmpireData.district(u["district"]).get("rent_k", 1.0))
		u["rent"] = roundf(float(u["size"]) * 0.22 * k)
		u["price"] = roundf(float(u["rent"]) * 240.0 / 50.0) * 50.0
		n += 1
	return P


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


func _blocked(p: Vector3) -> bool:
	for box: AABB in _grid.get(Vector2i(floori(p.x / 25.0), floori(p.z / 25.0)), []):
		if box.has_point(p):
			return true
	return false


func district_key(x: float, z: float) -> String:
	return ("west:" if _layout.is_mainland else "east:") + _layout.district(x, z)


## Distance (m) from a world point to the nearest road centreline, and that road's half width.
func _road_gap(p: Vector2) -> Vector2:
	var best := INF
	var hw := 5.0
	for r in _layout.roads.roads:
		var pts: PackedVector2Array = r["pts"]
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			var d := q.distance_to(p)
			if d < best:
				best = d
				hw = float(r.get("w", 10.0)) * 0.5
	return Vector2(best, hw)


func _best(key: String, spec: Dictionary, used: Array) -> Dictionary:
	var c := _candidates(key, spec)
	var best := {}
	for x in c:
		if best.is_empty() or x["score"] > best["score"]:
			best = x
	return best


func _candidates(key: String, spec: Dictionary) -> Array:
	var out: Array = []
	for b in _layout.buildings:
		if b["kind"] != "normal" or b.has("apt") or b.has("shape"):
			continue
		var t: Array = b["tiers"][0]
		var base := BuildingMesher.base_of(b)
		if absf(float(t[4]) - base) > 0.05:
			continue  # (a tower on a podium: its first tier isn't on the street)
		if float(t[5]) - base < float(spec["h"]) + 1.6:
			continue
		var c0 := CityLayout.base_center(b)
		if district_key(c0.x, c0.y) != key:
			continue
		for k in 4:
			var f := BuildingMesher._face(t, k)
			var flen: float = f[3]
			var depth := float(t[3]) - float(t[1]) if k % 2 == 0 else float(t[2]) - float(t[0])
			var W := minf(flen - 0.6, float(spec["w"][1]))
			var D := minf(depth - 0.4, float(spec["d"][1]))
			if W < float(spec["w"][0]) or D < float(spec["d"][0]):
				continue
			var a0 := (flen - W) * 0.5
			var c := {"b": b, "t": 0, "face": k, "a0": a0, "a1": a0 + W, "y0": base, "y1": base + float(spec["h"]),
				"depth": D, "ground": true, "wins": []}
			# Shops are glazed nearly wall to wall between their pilasters (the
			# interior shows through); warehouses keep a trade-counter opening.
			# (Centred either way, so the door point – and the unit's id – holds.)
			var ow := W - 0.8 if spec.get("full_front", false) else minf(float(spec["open_w"]), W - 2.0)
			c["oa0"] = a0 + (W - ow) * 0.5
			c["oa1"] = float(c["oa0"]) + ow
			c["oy0"] = base
			c["oy1"] = base + float(spec["open_h"])
			# The street in front: open, walkable, at the shop floor's level.
			var door := door_point(c)
			var nrm := outward(c)
			var front := door + nrm * 3.0
			if _blocked(front + Vector3.UP * 1.0) or _blocked(door + nrm * 7.0 + Vector3.UP * 1.0):
				continue
			if _layout.is_water(front):
				continue
			var gy := _layout.ground_y(front.x, front.z)
			if gy > base + 0.15 or gy < base - 0.4:
				continue
			var rg := _road_gap(Vector2(front.x, front.z))
			if rg.x > rg.y + 9.0:
				continue  # (round the back: no street)
			var s := 100.0 - absf(W - float(spec["w"][1])) * 2.0 - (rg.x - rg.y) * 3.0
			s -= absf(gy - base) * 30.0
			# Shops like busy corners near the district's heart.
			s -= Vector2(door.x, door.z).distance_to(_district_heart(key)) * 0.05
			c["district"] = key
			c["island"] = key.get_slice(":", 0)
			c["size"] = roundf(W * D)
			c["pos"] = [door.x, door.y, door.z]
			c["score"] = s
			out.append(c)
	return out


func _district_heart(key: String) -> Vector2:
	match key:
		"east:cbd":
			return CityLayout.CBD_CENTER
		"east:midtown":
			return Vector2(700.0, 250.0)
		"east:docks":
			return Vector2(300.0, 380.0)
		"east:waterfront":
			return Vector2(160.0, -40.0)
		"east:georgian":
			return Vector2(880.0, -300.0)
		"west:midtown":
			return Vector2(-930.0, -60.0)
		"west:waterfront":
			return Vector2(-560.0, 40.0)
	return Vector2(-900.0, 150.0)


func _far_from_others(c: Dictionary, spacing := SPACING) -> bool:
	var p := Vector2(float(c["pos"][0]), float(c["pos"][2]))
	for u in units:
		if Vector2(float(u["pos"][0]), float(u["pos"][2])).distance_to(p) < spacing:
			return false
	return true


func _claim(c: Dictionary) -> void:
	var b: Dictionary = c["b"]
	var facade := c.duplicate()
	facade["b"] = b.duplicate()
	facade.erase("score")
	b["apt"] = facade
	b.erase("_features")
	c.erase("score")
	units.append(c)


# ----------------------------------------------------------- geometry
static func face_of(c: Dictionary) -> Array:
	return BuildingMesher._face((c["b"] as Dictionary)["tiers"][c["t"]], c["face"])


## World: the middle of the shopfront at floor level.
static func door_point(c: Dictionary) -> Vector3:
	var f := face_of(c)
	var a := (float(c["oa0"]) + float(c["oa1"])) * 0.5
	return CityLayout.bxf(c["b"]) * BuildingMesher._fpt(f, a, 0.0, c["y0"])


static func outward(c: Dictionary) -> Vector3:
	return (CityLayout.bxf(c["b"]).basis * (face_of(c)[2] as Vector3)).normalized()


static func along_dir(c: Dictionary) -> Vector3:
	return (CityLayout.bxf(c["b"]).basis * (face_of(c)[1] as Vector3)).normalized()


## Room frame → world (right-handed): x along the shopfront from the room's
## left wall (0..W), y up from the floor, z OUT of the facade – the room is
## z in [-depth, 0]. (ShopInterior authors with depth d = -z.)
static func room_xf(c: Dictionary) -> Transform3D:
	var f := face_of(c)
	var org: Vector3 = BuildingMesher._fpt(f, float(c["a0"]), 0.0, float(c["y0"]))
	var along: Vector3 = f[1]
	var outward_l: Vector3 = f[2]
	var local := Transform3D(Basis(along, Vector3.UP, outward_l), org)
	return CityLayout.bxf(c["b"]) * local


static func room_size(c: Dictionary) -> Vector3:
	return Vector3(float(c["a1"]) - float(c["a0"]), float(c["y1"]) - float(c["y0"]), float(c["depth"]))


## Opening in room x (left, right).
static func opening_x(c: Dictionary) -> Vector2:
	return Vector2(float(c["oa0"]) - float(c["a0"]), float(c["oa1"]) - float(c["a0"]))


## Record without the building reference (for Business.premises / saves).
static func record(c: Dictionary) -> Dictionary:
	var r := {}
	for k in ["id", "kind", "name", "shop_name", "district", "island", "size", "rent", "price", "pos", "est"]:
		if c.has(k):
			r[k] = c[k]
	return r
