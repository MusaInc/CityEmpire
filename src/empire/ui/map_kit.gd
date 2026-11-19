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
## style: "own" solid badge + white ring (yours), "buy" dark badge with a
## coloured ring and glyph (to rent / for sale), "place" solid badge.
const KINDS := {
	"yours": {"name": "Your businesses", "col": Color(0.24, 0.78, 0.47), "icon": "shop", "style": "own", "pri": 0},
	"car": {"name": "Your vehicles", "col": Color(0.3, 0.55, 0.95), "icon": "car", "style": "own", "pri": 0},
	"home_own": {"name": "Your homes", "col": Color(0.62, 0.48, 0.95), "icon": "house", "style": "own", "pri": 0},
	"hq": {"name": "Head office", "col": Color(0.92, 0.74, 0.3), "icon": "tower", "style": "own", "pri": 0},
	"wholesale": {"name": "Suppliers", "col": Color(0.33, 0.56, 0.95), "icon": "box", "style": "place", "pri": 0},
	"airport": {"name": "Airport", "col": Color(0.28, 0.6, 0.9), "icon": "plane", "style": "place", "pri": 0},
	"sale": {"name": "Business for sale", "col": Color(0.25, 0.85, 0.72), "icon": "tag", "style": "buy", "pri": 1},
	"to_let": {"name": "Shop to let", "col": Color(0.98, 0.7, 0.22), "icon": "key", "style": "buy", "pri": 1},
	"home": {"name": "Home for sale", "col": Color(0.72, 0.6, 1.0), "icon": "house", "style": "buy", "pri": 1},
	"dealer": {"name": "Car dealers", "col": Color(0.3, 0.62, 0.98), "icon": "car", "style": "buy", "pri": 1},
	"aviation": {"name": "Aircraft sales", "col": Color(0.3, 0.62, 0.98), "icon": "plane", "style": "buy", "pri": 1},
	"marina": {"name": "Marina", "col": Color(0.25, 0.7, 0.85), "icon": "anchor", "style": "place", "pri": 1},
	"fashion": {"name": "Clothing", "col": Color(0.92, 0.36, 0.56), "icon": "bag", "style": "place", "pri": 1},
	"landmark": {"name": "Landmarks", "col": Color(0.88, 0.72, 0.38), "icon": "star", "style": "place", "pri": 1},
	"rival": {"name": "QuikSave", "col": Color(0.84, 0.2, 0.22), "icon": "shop", "style": "place", "pri": 1},
	"food": {"name": "Food & drink", "col": Color(0.96, 0.52, 0.32), "icon": "cup", "style": "place", "pri": 2},
	"firm": {"name": "Other shops", "col": Color(0.55, 0.6, 0.66), "icon": "shop", "style": "place", "pri": 2},
	"place": {"name": "Places", "col": Color(0.31, 0.64, 0.94), "icon": "star", "style": "place", "pri": 1},
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
					var ft := String(fm.get("type", ""))
					sub = "%s · %s" % [String(EmpireData.business_type(ft).get("name", "Independent")), sub]
					# (Boutiques and food get their own markers: things to go to.)
					if ft == "clothing":
						kind = "fashion"
					elif ft in ["cafe", "takeaway", "bakery"]:
						kind = "food"
			_:
				label = "To let · %s/day" % EmpireData.money(float(u["rent"]))
				sub = "%d m² · %s" % [int(u.get("size", 0)), sub]
		out.append({"id": String(u["id"]), "kind": kind, "world": dp, "label": label, "sub": sub,
			"ref": {"kind": "unit", "id": String(u["id"])}})
	for h in g.homes():
		out.append({"id": String(h["id"]), "kind": "home_own" if g.empire.owns_property(h["id"]) else "home", "world": g.home_lift(h),
			"label": String(h["name"]), "sub": ("Your home" if g.empire.owns_property(h["id"]) else "Home for sale %s" % EmpireData.money(float(h["price"]))),
			"ref": {"kind": "home", "id": String(h["id"])}})
	# Places that aren't shop units: Skyport's showrooms, fashion houses,
	# marina, cargo and terminal; the stadium.
	if g.skyport_play:
		for sid in ["dealer_budget", "dealer_commercial", "dealer_luxury", "clothes_everyday", "clothes_premium", "aviation", "marina", "cargo", "terminal"]:
			var st := g.skyport_play.site(sid)
			if st.is_empty():
				continue
			var pk := "fashion" if sid.begins_with("clothes") else ({"terminal": "airport", "aviation": "aviation", "marina": "marina",
				"cargo": "wholesale"}.get(sid, "dealer") as String)
			out.append({"id": "site:" + sid, "kind": pk, "world": st["door"], "label": String(st["name"]),
				"sub": {"dealer_budget": "Car dealer", "dealer_commercial": "Vans and trucks", "dealer_luxury": "Supercars",
					"clothes_everyday": "Clothing store", "clothes_premium": "Fashion house", "aviation": "Aircraft sales",
					"marina": "Boats and berths", "cargo": "Imports", "terminal": "Airport"}.get(sid, "") + " · Skyport",
				"ref": {"kind": "place", "id": sid}})
	out.append({"id": "stadium", "kind": "landmark", "world": g.club_office_pos(), "label": "The Heights Ground",
		"sub": "Football stadium", "ref": {"kind": "place", "id": "stadium"}})
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


## One marker, at screen point s (k scales it: the minimap draws smaller):
## a round badge in the kind's colour with its glyph. Yours: solid with a
## white ring; to rent / for sale: dark with a coloured ring and glyph;
## other places: solid. Too small for a glyph (far minimap) → a dot.
static func radius(kind: String, k := 1.0) -> float:
	var pri := int(KINDS.get(kind, KINDS["firm"])["pri"])
	return (9.5 if pri == 0 else (8.5 if pri == 1 else 7.0)) * k


static func draw_marker(ci: CanvasItem, s: Vector2, kind: String, k := 1.0, selected := false) -> void:
	var d: Dictionary = KINDS.get(kind, KINDS["firm"])
	var col: Color = d["col"]
	var r := radius(kind, k)
	var st := String(d["style"])
	if selected:
		ci.draw_circle(s, r + 7.0, Color(1, 1, 1, 0.3))
	ci.draw_circle(s + Vector2(0, 1.2), r + 1.6, Color(0, 0, 0, 0.45))   # (shadow)
	var gc := Color.WHITE
	match st:
		"own":
			ci.draw_circle(s, r + 1.4, Color.WHITE)
			ci.draw_circle(s, r - 0.6, col)
		"buy":
			ci.draw_circle(s, r, col)
			ci.draw_circle(s, r - 2.0, Color(0.07, 0.1, 0.13))
			gc = col.lightened(0.15)
		_:
			ci.draw_circle(s, r, col)
	if r < 5.5:
		return
	glyph(ci, s, r * 0.58, String(d["icon"]), gc)


## A small white line icon centred at c, half-size h.
static func glyph(ci: CanvasItem, c: Vector2, h: float, icon: String, gc: Color) -> void:
	var w := maxf(1.2, h * 0.24)
	match icon:
		"shop":
			# Awning over a shopfront.
			ci.draw_rect(Rect2(c + Vector2(-h, -h * 0.75), Vector2(h * 2.0, h * 0.55)), gc)
			for i in 3:
				ci.draw_circle(c + Vector2(-h + h * (0.33 + i * 0.67), -h * 0.2), h * 0.33, gc)
			ci.draw_rect(Rect2(c + Vector2(-h * 0.8, h * 0.05), Vector2(h * 1.6, h * 0.8)), gc, false, w)
		"bag":
			ci.draw_rect(Rect2(c + Vector2(-h * 0.8, -h * 0.35), Vector2(h * 1.6, h * 1.25)), gc)
			ci.draw_arc(c + Vector2(0, -h * 0.35), h * 0.45, PI, TAU, 10, gc, w)
		"cup":
			ci.draw_rect(Rect2(c + Vector2(-h * 0.75, -h * 0.45), Vector2(h * 1.2, h * 1.15)), gc)
			ci.draw_arc(c + Vector2(h * 0.48, h * 0.1), h * 0.32, -PI * 0.5, PI * 0.5, 8, gc, w)
			ci.draw_line(c + Vector2(-h * 0.9, h * 0.85), c + Vector2(h * 0.6, h * 0.85), gc, w)
		"box":
			ci.draw_rect(Rect2(c + Vector2(-h * 0.85, -h * 0.75), Vector2(h * 1.7, h * 1.5)), gc)
			ci.draw_line(c + Vector2(0, -h * 0.75), c + Vector2(0, -h * 0.1), Color(0, 0, 0, 0.45), w)
			ci.draw_line(c + Vector2(-h * 0.85, -h * 0.1), c + Vector2(h * 0.85, -h * 0.1), Color(0, 0, 0, 0.45), w * 0.8)
		"car":
			ci.draw_rect(Rect2(c + Vector2(-h, -h * 0.05), Vector2(h * 2.0, h * 0.6)), gc)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.6, -h * 0.05), c + Vector2(-h * 0.35, -h * 0.6),
				c + Vector2(h * 0.4, -h * 0.6), c + Vector2(h * 0.7, -h * 0.05)]), gc)
			ci.draw_circle(c + Vector2(-h * 0.55, h * 0.6), h * 0.26, gc)
			ci.draw_circle(c + Vector2(h * 0.55, h * 0.6), h * 0.26, gc)
		"house":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h, -h * 0.05), c + Vector2(0, -h * 0.95), c + Vector2(h, -h * 0.05)]), gc)
			ci.draw_rect(Rect2(c + Vector2(-h * 0.7, -h * 0.1), Vector2(h * 1.4, h * 0.95)), gc)
		"tower":
			ci.draw_rect(Rect2(c + Vector2(-h * 0.45, -h), Vector2(h * 0.9, h * 1.95)), gc)
			ci.draw_rect(Rect2(c + Vector2(h * 0.45, -h * 0.2), Vector2(h * 0.45, h * 1.15)), gc)
		"key":
			ci.draw_arc(c + Vector2(-h * 0.45, 0), h * 0.42, 0, TAU, 12, gc, w)
			ci.draw_line(c + Vector2(-h * 0.05, 0), c + Vector2(h * 0.95, 0), gc, w)
			ci.draw_line(c + Vector2(h * 0.75, 0), c + Vector2(h * 0.75, h * 0.4), gc, w)
			ci.draw_line(c + Vector2(h * 0.45, 0), c + Vector2(h * 0.45, h * 0.3), gc, w)
		"tag":
			var f := S.font("black")
			var fs := int(h * 2.0)
			var tw := f.get_string_size("£", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			ci.draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), "£", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, gc)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + i * PI / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * (h * 1.05 if i % 2 == 0 else h * 0.45))
			ci.draw_colored_polygon(pts, gc)
		"plane":
			ci.draw_line(c + Vector2(0, -h), c + Vector2(0, h * 0.9), gc, w * 1.4)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h, h * 0.1), c + Vector2(0, -h * 0.35), c + Vector2(h, h * 0.1),
				c + Vector2(0, h * 0.05)]), gc)
			ci.draw_line(c + Vector2(-h * 0.4, h * 0.8), c + Vector2(h * 0.4, h * 0.8), gc, w)
		"anchor":
			ci.draw_line(c + Vector2(0, -h * 0.75), c + Vector2(0, h * 0.85), gc, w)
			ci.draw_line(c + Vector2(-h * 0.45, -h * 0.4), c + Vector2(h * 0.45, -h * 0.4), gc, w)
			ci.draw_arc(c + Vector2(0, h * 0.2), h * 0.7, 0.2, PI - 0.2, 10, gc, w)
			ci.draw_circle(c + Vector2(0, -h * 0.85), h * 0.2, gc)
		_:
			ci.draw_circle(c, h * 0.45, gc)


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
