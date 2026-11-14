class_name MapKit
extends RefCounted
## What the HUD minimap and the phone's full map have in common, so they
## read as two views of one map: the same baked city image
## (EmpireMinimap.map_tex), the same markers (one list, built here), the
## same marker shapes and colours, the same purple GPS route (Gps.points)
## and the same "you" arrow. Each view only decides its own transform,
## zoom and which priorities it has room for.

const S = preload("res://src/empire/ui/empire_style.gd")

## Marker kinds, most important first. pri: 0 always shown (even on the
## minimap), 1 shown on the minimap when near, 2 full map / zoomed in.
const KINDS := {
	"yours": {"name": "Your shops", "col": Color(0.3, 0.86, 0.5), "shape": "circle", "pri": 0},
	"car": {"name": "Your vehicles", "col": Color(1, 1, 1), "shape": "car", "pri": 0},
	"wholesale": {"name": "Suppliers", "col": Color(0.36, 0.62, 1.0), "shape": "diamond", "pri": 0},
	"hq": {"name": "Head office", "col": Color(0.98, 0.84, 0.38), "shape": "diamond", "pri": 1},
	"sale": {"name": "For sale", "col": Color(0.3, 0.92, 0.78), "shape": "square", "pri": 1},
	"rival": {"name": "QuikSave", "col": Color(0.85, 0.15, 0.18), "shape": "square", "pri": 1},
	"to_let": {"name": "To let", "col": Color(0.98, 0.71, 0.2), "shape": "circle", "pri": 1},
	"home": {"name": "Homes", "col": Color(0.85, 0.7, 1.0), "shape": "circle", "pri": 2},
	"firm": {"name": "Independent", "col": Color(0.78, 0.8, 0.84), "shape": "dot", "pri": 2},
}

static var _cache: Array = []
static var _cache_t := -1.0


## Every marker on the map: {id, kind, world, label, sub, ref}. Rebuilt at
## most twice a second (both maps share the list).
static func markers(g: EmpireGame) -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _cache_t < 0.5 and not _cache.is_empty():
		_refresh_cars(g)
		return _cache
	_cache_t = now
	var out: Array = []
	for u in g.units:
		var kind := unit_kind(g, u)
		var dp := Premises.door_point(u)
		var label := ""
		var sub := String(EmpireData.district(u.get("district", "")).get("name", ""))
		match kind:
			"yours":
				var b: Business = g.empire.business_at(u["id"])
				label = b.name
				sub = "%s · %s" % [String(b.type_def().get("name", "Shop")), sub]
			"wholesale":
				label = String(u["name"])
				sub = "Cash & carry · " + sub
			"hq":
				label = String(u.get("name", "Head office"))
				sub = "Head office · " + sub
			"rival":
				label = String(CityLife.rival_at(g.empire, u["id"]).get("name", "QuikSave"))
				sub = "Rival chain · " + sub
			"sale", "firm":
				var fm := CityLife.firm_at(g.empire, u["id"])
				label = String(fm.get("name", "Shop"))
				if kind == "sale":
					sub = "For sale %s · %s" % [EmpireData.money(CityLife.firm_price(fm)), sub]
				else:
					sub = "Independent · " + sub
			_:
				label = "To let · %s/day" % EmpireData.money(float(u["rent"]))
				sub = "%d m² · %s" % [int(u.get("size", 0)), sub]
		out.append({"id": String(u["id"]), "kind": kind, "world": dp, "label": label, "sub": sub,
			"ref": {"kind": "unit", "id": String(u["id"])}})
	for h in g.homes():
		out.append({"id": String(h["id"]), "kind": "home", "world": g.home_lift(h),
			"label": String(h["name"]), "sub": ("Your home" if g.empire.owns_property(h["id"]) else "Home for sale %s" % EmpireData.money(float(h["price"]))),
			"ref": {"kind": "home", "id": String(h["id"])}})
	for v in g.empire.vehicles:
		out.append({"id": String(v["id"]), "kind": "car", "world": Vector3.ZERO, "label": EmpireData.vehicle_model(v["model"]).get("name", "Car"),
			"sub": "Your vehicle", "ref": {"kind": "vehicle", "id": String(v["id"])}})
	_cache = out
	_refresh_cars(g)
	return out


static func invalidate() -> void:
	_cache_t = -1.0


static func _refresh_cars(g: EmpireGame) -> void:
	for m in _cache:
		if m["kind"] == "car":
			m["world"] = g.vehicle_position(String(m["id"]))


## What occupies a unit (the marker kind).
static func unit_kind(g: EmpireGame, u: Dictionary) -> String:
	match String(u["kind"]):
		"wholesale":
			return "wholesale"
		"hq":
			return "hq"
	if g.empire.business_at(u["id"]) != null:
		return "yours"
	if CityLife.is_rival(g.empire, u["id"]):
		return "rival"
	var f := CityLife.firm_at(g.empire, u["id"])
	if not f.is_empty():
		return "sale" if f.get("for_sale", false) else "firm"
	return "to_let"


static func colour(kind: String) -> Color:
	return KINDS.get(kind, KINDS["firm"])["col"]


static func priority(kind: String) -> int:
	return int(KINDS.get(kind, KINDS["firm"])["pri"])


## One marker, at screen point s (k scales it: the minimap draws smaller).
static func draw_marker(ci: CanvasItem, s: Vector2, kind: String, k := 1.0, selected := false) -> void:
	var d: Dictionary = KINDS.get(kind, KINDS["firm"])
	var col: Color = d["col"]
	var r := (7.0 if int(d["pri"]) == 0 else (5.5 if int(d["pri"]) == 1 else 3.6)) * k
	if selected:
		ci.draw_circle(s, r + 7.0 * k, Color(1, 1, 1, 0.28))
	match String(d["shape"]):
		"square":
			ci.draw_rect(Rect2(s - Vector2(r + 1.5, r + 1.5), Vector2(r + 1.5, r + 1.5) * 2.0), Color(0, 0, 0, 0.6))
			ci.draw_rect(Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0), col)
		"diamond":
			var q := PackedVector2Array([s + Vector2(0, -r - 2.5), s + Vector2(r + 2.5, 0), s + Vector2(0, r + 2.5), s + Vector2(-r - 2.5, 0)])
			ci.draw_colored_polygon(q, Color(0, 0, 0, 0.6))
			var q2 := PackedVector2Array([s + Vector2(0, -r - 0.5), s + Vector2(r + 0.5, 0), s + Vector2(0, r + 0.5), s + Vector2(-r - 0.5, 0)])
			ci.draw_colored_polygon(q2, col)
		"car":
			ci.draw_rect(Rect2(s - Vector2(r + 2.0, r * 0.75 + 2.0), Vector2(r + 2.0, r * 0.75 + 2.0) * 2.0), Color(0, 0, 0, 0.7))
			ci.draw_rect(Rect2(s - Vector2(r, r * 0.75), Vector2(r, r * 0.75) * 2.0), col)
			ci.draw_rect(Rect2(s - Vector2(r * 0.55, r * 0.2), Vector2(r * 1.1, r * 0.4)), Color(0.12, 0.14, 0.18))
		"dot":
			ci.draw_circle(s, r + 1.2, Color(0, 0, 0, 0.45))
			ci.draw_circle(s, r, Color(col, 0.85))
		_:
			ci.draw_circle(s, r + 1.8, Color(0, 0, 0, 0.6))
			ci.draw_circle(s, r, col)


## The GPS route through screen points: a dark casing under a bright purple line.
static func draw_route(ci: CanvasItem, pts: PackedVector2Array, width: float) -> void:
	if pts.size() < 2:
		return
	ci.draw_polyline(pts, Color(Gps.COLOUR_EDGE, 0.85), width + 4.0, true)
	ci.draw_polyline(pts, Gps.COLOUR, width, true)


## Destination pin (purple, so it reads as part of the route).
static func draw_destination(ci: CanvasItem, s: Vector2, k := 1.0) -> void:
	var tip := s
	var head := s + Vector2(0, -16.0 * k)
	ci.draw_line(tip + Vector2(1, 1), head + Vector2(1, 1), Color(0, 0, 0, 0.6), 3.0 * k, true)
	ci.draw_line(tip, head, Color.WHITE, 2.4 * k, true)
	ci.draw_circle(head, 8.5 * k, Color(0, 0, 0, 0.6))
	ci.draw_circle(head, 7.0 * k, Gps.COLOUR)
	ci.draw_circle(head, 2.8 * k, Color.WHITE)


## You: a white arrow along `dir` (screen space, unit) in a soft halo.
static func draw_player(ci: CanvasItem, s: Vector2, dir: Vector2, k := 1.0) -> void:
	var f := dir.normalized() if dir.length() > 0.01 else Vector2.UP
	var r := Vector2(-f.y, f.x)
	ci.draw_circle(s, 14.0 * k, Color(1, 1, 1, 0.16))
	var tri := PackedVector2Array([s + f * 11.0 * k, s - f * 7.0 * k + r * 7.5 * k, s - f * 3.0 * k, s - f * 7.0 * k - r * 7.5 * k])
	ci.draw_colored_polygon(tri, Color.WHITE)
	ci.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.7), 1.5, true)


## Keeps the parts of a polyline inside a circle (the round minimap).
static func clip_to_circle(pts: PackedVector2Array, c: Vector2, rad: float) -> Array:
	var runs: Array = []
	var cur := PackedVector2Array()
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ain := a.distance_to(c) <= rad
		var bin := b.distance_to(c) <= rad
		if ain and bin:
			if cur.is_empty():
				cur.append(a)
			cur.append(b)
			continue
		var hits := _seg_circle(a, b, c, rad)
		if ain and not bin:
			if cur.is_empty():
				cur.append(a)
			cur.append(hits[0] if not hits.is_empty() else b)
			runs.append(cur)
			cur = PackedVector2Array()
		elif bin and not ain:
			cur = PackedVector2Array([hits[0] if not hits.is_empty() else a, b])
		elif hits.size() == 2:
			runs.append(PackedVector2Array([hits[0], hits[1]]))
	if cur.size() >= 2:
		runs.append(cur)
	return runs


static func _seg_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> Array:
	var d := b - a
	var f := a - c
	var A := d.dot(d)
	var B := 2.0 * f.dot(d)
	var C := f.dot(f) - r * r
	var disc := B * B - 4.0 * A * C
	if A < 1e-6 or disc < 0.0:
		return []
	var sq := sqrt(disc)
	var out: Array = []
	for t in [(-B - sq) / (2.0 * A), (-B + sq) / (2.0 * A)]:
		if t >= 0.0 and t <= 1.0:
			out.append(a + d * t)
	return out
