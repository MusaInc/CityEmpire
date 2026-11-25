class_name CoastKit
extends RefCounted
## Places to go along the shore, so the coast is somewhere to explore and not
## one long sea wall (2026-11-18 coast overhaul). Built per city layout after
## the landforms are known (CityWorld, before collision and structures):
##
##   * Lookouts on the cliffs: a stone bastion out from the esplanade over the
##     cliff edge, parapet, benches, a coin telescope, a lamp and a board.
##   * Steps down to the sand coves under the low sea walls (with a lifebuoy).
##   * Fishing jetties off the rock armour: timber decks on piles past the
##     boulders, handrails, a bench and a lamp at the end.
##   * Working quays on the strait: ladders and fender piles on the wall face.
##   * The landforms (each built by the layout on its side): a viewpoint with
##     a beacon on the tip of the rocky headlands, a jetty and a kiosk with
##     umbrellas on the beaches.
##
## Kits go into the layout's structures (drawn and collided like every set
## piece), grouped into one kit per ~320 m cell so each costs one draw. The
## railing opens where a lookout, steps or a jetty meet it.

const CELL := 320.0
const STONE := Color(0.66, 0.63, 0.58)
const STONE_DK := Color(0.46, 0.44, 0.41)
const IRON := Color(0.16, 0.2, 0.2)
const WOOD := Color(0.55, 0.42, 0.3)
const WOOD_DK := Color(0.33, 0.25, 0.19)
const WHITE := Color(0.95, 0.95, 0.93)
const LAMP := Color(1.0, 0.95, 0.8)

var L: CityLayout
var rng := RandomNumberGenerator.new()
var _kits := {}
var counts := {"lookout": 0, "steps": 0, "jetty": 0, "ladder": 0, "viewpoint": 0, "beach": 0}


func _init(layout: CityLayout) -> void:
	L = layout
	rng.seed = layout.seed * 53 + (11 if layout.is_mainland else 3)


func _k(p: Vector2) -> Dictionary:
	var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	if not _kits.has(key):
		_kits[key] = L._kit("coast")
	return _kits[key]


func build() -> Dictionary:
	_shore_features()
	_strait_quay()
	if Landforms.enabled:
		for f: Dictionary in Landforms.forms():
			if f.get("L") == L:
				_landform(f)
	return counts


## Railing openings for every kit built so far (both layouts): CityWorld
## re-adds them whenever it rebuilds BuildingMesher.rail_gaps.
static var gaps: Array = []
## Every place built ([kind, Vector3 position, Vector2 facing out to sea]),
## for audits and capture views.
static var places: Array = []


static func _gap(c: Vector2, half: float) -> void:
	var g := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
	gaps.append(g)
	BuildingMesher.rail_gaps.append(g)


static func _gapped(p: Vector2, clear := 6.0) -> bool:
	for g: Rect2 in BuildingMesher.rail_gaps:
		if g.grow(clear).has_point(p):
			return true
	return false


# ------------------------------------------------------------ the city shore
func _shore_features() -> void:
	var sr := BuildingMesher.shore_rows(L)
	var smp: Array = sr[0]
	var rows: Array = sr[1]
	var rocky: Array = sr[2]
	var covered: Array = sr[3]
	var last := {"lookout": -INF, "steps": -INF, "jetty": -INF}
	for i in range(2, smp.size() - 2):
		if covered[i] or covered[i - 1] or covered[i + 1] or covered[i - 2] or covered[i + 2]:
			continue
		var p: Vector2 = smp[i][0]
		var n: Vector2 = smp[i][1]
		var s: float = smp[i][2]
		# (Only on a straight-ish stretch: neighbours' normals agree.)
		if (smp[i - 2][1] as Vector2).dot(n) < 0.94 or (smp[i + 2][1] as Vector2).dot(n) < 0.94:
			continue
		if SkyportIsland.over_bridge_shore(p.x, p.y) or SkyportIsland.under_bridge(p.x, p.y) or _gapped(p, 30.0):
			continue
		var H := L.terrain.road_y(p.x, p.y)
		var top := H + CityTerrain.KERB
		var row: Array = rows[i]
		var r: float = rocky[i]
		var out_d := Vector2((row[-1] as Vector3).x - p.x, (row[-1] as Vector3).z - p.y).length()
		if out_d < 6.0:
			continue  # (docks: no apron)
		var bk := 0.0 if L.is_mainland else CoastLife.beach_k(p)
		if H > 11.0 and s - float(last["lookout"]) > 300.0:
			_lookout(p, n, top)
			last["lookout"] = s
		elif H < 6.0 and r < 0.6 and bk < 0.02 and s - float(last["steps"]) > 110.0:
			_steps(p, n, top, row)
			last["steps"] = s
		elif H < 6.0 and r > 0.75 and bk < 0.02 and s - float(last["jetty"]) > 380.0 \
				and BuildingMesher.shore_reach(L, p, n) > 60.0:
			_jetty(p, n, top, 30.0, L.is_mainland)
			last["jetty"] = s


## A stone bastion half-round out from the sea wall over the cliff.
func _lookout(p: Vector2, n: Vector2, top: float) -> void:
	var k := _k(p)
	var t := Vector2(-n.y, n.x)
	var R := 6.5
	var c := p + n * 0.5
	var arc := PackedVector2Array()
	for a in 13:
		var ang := PI * a / 12.0
		arc.append(c + t * cos(ang) * R + n * sin(ang) * R)
	# The platform (level with the esplanade) and its corbelled base, which
	# steps in down the cliff face.
	L._kprism(k, _ring(c, t, n, R, 0.0, 12), top - 0.35, top, STONE)
	L._kprism(k, _ring(c, t, n, R - 0.3, 0.0, 12), top - 1.6, top - 0.35, STONE_DK)
	L._kprism(k, _ring(c, t, n, R - 1.2, 0.0, 12), top - 4.5, top - 1.6, STONE_DK)
	L._kprism(k, _ring(c, t, n, R - 2.4, 0.0, 12), top - 9.0, top - 4.5, STONE_DK.darkened(0.1))
	# Parapet round the curve: stone dado, iron rail on top.
	for a in 12:
		var q0 := arc[a]
		var q1 := arc[a + 1]
		var m0 := q0 - (q0 - c).normalized() * 0.35
		var m1 := q1 - (q1 - c).normalized() * 0.35
		L._kprism(k, PackedVector2Array([q0, q1, m1, m0]), top, top + 0.55, STONE.lightened(0.08))
		var r0 := (q0 + m0) * 0.5
		var r1 := (q1 + m1) * 0.5
		L._kbeam(k, Vector3(r0.x, top + 1.05, r0.y), Vector3(r1.x, top + 1.05, r1.y), 0.07, 0.07, IRON, false)
		L._kbeam(k, Vector3(r0.x, top + 0.55, r0.y), Vector3(r0.x, top + 1.05, r0.y), 0.05, 0.05, IRON, false)
	_gap(p, R - 0.8)
	# Two benches facing the sea, a telescope on its post, a lamp, a board.
	for sg: float in [-1.0, 1.0]:
		_bench(k, c + t * sg * 2.6 + n * 2.0, n, top)
	var tp := c + n * 4.6
	L._kbeam(k, Vector3(tp.x, top, tp.y), Vector3(tp.x, top + 1.1, tp.y), 0.12, 0.12, IRON)
	var te := tp + n * 0.35
	L._kbeam(k, Vector3(tp.x - n.x * 0.25, top + 1.18, tp.y - n.y * 0.25), Vector3(te.x, top + 1.32, te.y), 0.16, 0.16,
		Color(0.2, 0.42, 0.36), false)
	var lp := c - t * (R - 1.0) + n * 0.6
	_lamp(k, lp, top)
	var bp := c + t * (R - 1.4) + n * 0.4
	L._kbeam(k, Vector3(bp.x, top, bp.y), Vector3(bp.x, top + 1.0, bp.y), 0.08, 0.08, IRON, false)
	L._kbeam(k, Vector3(bp.x - t.x * 0.55, top + 1.25, bp.y - t.y * 0.55), Vector3(bp.x + t.x * 0.55, top + 1.25, bp.y + t.y * 0.55),
		0.06, 0.7, Color(0.18, 0.3, 0.38), false)
	counts["lookout"] += 1
	places.append(["lookout", Vector3(c.x, top, c.y), n])


## A flight down the sea wall to the sand, a lifebuoy beside it.
func _steps(p: Vector2, n: Vector2, top: float, row: Array) -> void:
	var sand := _row_y(p, row, 5.0)
	var rise := top - sand
	if rise < 0.6 or rise > 6.0:
		return
	var k := _k(p)
	var t := Vector2(-n.y, n.x)
	var steps := ceili(rise / 0.28)
	var h := rise / steps
	for i in steps:
		var y1 := top - h * i
		var a := p + n * (-0.65 if i == 0 else i * 0.4)
		var b := p + n * ((i + 1) * 0.4)
		L._kprism(k, PackedVector2Array([a - t * 1.4, a + t * 1.4, b + t * 1.4, b - t * 1.4]), sand - 0.5, y1, STONE)
	# Cheek walls with a handrail.
	var e := p + n * (0.2 + steps * 0.4)
	for sg: float in [-1.0, 1.0]:
		var a2 := p + t * sg * 1.55
		var b2 := e + t * sg * 1.55
		L._kbeam(k, Vector3(a2.x, top + 0.9, a2.y), Vector3(b2.x, sand + 0.9, b2.y), 0.06, 0.06, IRON, false)
	var lb := p - t * 2.6 - n * 0.6
	L._kbeam(k, Vector3(lb.x, top, lb.y), Vector3(lb.x, top + 1.5, lb.y), 0.1, 0.1, Color(0.85, 0.2, 0.16), false)
	L._kbeam(k, Vector3(lb.x, top + 1.05, lb.y) - Vector3(t.x, 0, t.y) * 0.3, Vector3(lb.x, top + 1.05, lb.y) + Vector3(t.x, 0, t.y) * 0.3,
		0.12, 0.55, Color(0.95, 0.5, 0.15), false)
	_gap(p, 1.8)
	counts["steps"] += 1
	places.append(["steps", Vector3(p.x, top, p.y), n])


## Height of a shore row d metres out from its sea wall point p.
static func _row_y(p: Vector2, row: Array, d: float) -> float:
	var prev: Vector3 = row[0]
	for v: Vector3 in row:
		var dv := Vector2(v.x - p.x, v.z - p.y).length()
		var dp := Vector2(prev.x - p.x, prev.z - p.y).length()
		if dv >= d:
			return lerpf(prev.y, v.y, clampf((d - dp) / maxf(dv - dp, 0.01), 0.0, 1.0))
		prev = v
	return (row[-1] as Vector3).y


## A timber jetty out from p along n, deck at `deck`.
func _jetty(p: Vector2, n: Vector2, deck: float, length: float, _west: bool, hw := 1.6) -> void:
	var k := _k(p)
	var t := Vector2(-n.y, n.x)
	var b := p + n * length
	var land := p - n * 0.65
	var A := Vector3(land.x, deck, land.y)
	var B := Vector3(b.x, deck, b.y)
	var T := Vector3(t.x, 0.0, t.y)
	L._kbeam(k, A + Vector3.DOWN * 0.15, B + Vector3.DOWN * 0.15, hw * 2.0, 0.3, WOOD)
	L._kbeam(k, A + Vector3.DOWN * 0.55, B + Vector3.DOWN * 0.55, hw * 2.0 - 0.4, 0.5, WOOD_DK, false)
	var d := 4.0
	while d <= length:
		var q := p + n * d
		for sg: float in [-1.0, 1.0]:
			var c := q + t * sg * (hw - 0.25)
			L._kbeam(k, Vector3(c.x, -5.0, c.y), Vector3(c.x, deck - 0.3, c.y), 0.32, 0.32, WOOD_DK, false)
			var r := q + t * sg * (hw - 0.06)
			L._kbeam(k, Vector3(r.x, deck, r.y), Vector3(r.x, deck + 1.0, r.y), 0.08, 0.08, WOOD_DK, false)
		d += 4.0
	for sg: float in [-1.0, 1.0]:
		var o := T * sg * (hw - 0.06)
		# (The top rail collides: you can't walk off the side.)
		L._kbeam(k, A + o + Vector3.UP * 1.0 + Vector3(n.x, 0, n.y) * 1.5, B + o + Vector3.UP * 1.0, 0.08, 0.08, WOOD)
	# A bench and a lamp at the end, mooring rings.
	_bench(k, b - n * 1.2 - t * 0.6, n, deck)
	_lamp(k, b - n * 0.4 + t * (hw - 0.3), deck)
	_gap(p, hw + 0.2)
	counts["jetty"] += 1
	places.append(["jetty", Vector3(p.x, deck, p.y), n])


# ------------------------------------------------------------ strait quays
## Ladders and fender piles down the strait quay's face (outside the marina,
## the bridges and the landforms).
func _strait_quay() -> void:
	var x := CityLayout.FAR_SHORE if L.is_mainland else CityLayout.RIVER_EDGE
	var sgn := 1.0 if L.is_mainland else -1.0   # (towards the water)
	var I := L.island
	var z := I.position.y + 30.0
	var i := 0
	while z < I.end.y - 30.0:
		var p := Vector2(x, z)
		var wet := p + Vector2(sgn * 3.0, 0.0)
		var skip := (not L.is_mainland and z > CoastLife.MARINA_Z.x - 10.0 and z < CoastLife.MARINA_Z.y + 10.0) \
			or Landforms.contains(wet.x, wet.y) or SkyportIsland.under_bridge(x, z) or _gapped(p) \
			or not L.is_water(Vector3(wet.x, 0.0, wet.y))
		if not skip:
			var k := _k(p)
			var fx := x + sgn * 0.2
			var top := L.ground_y(x - sgn * 3.0, z)
			# Fender pile.
			L._kbeam(k, Vector3(fx, -3.0, z), Vector3(fx, top - 0.1, z), 0.38, 0.38, WOOD_DK, false)
			if i % 3 == 1:
				# A ladder: two stiles and rungs from the coping into the water.
				for sg: float in [-1.0, 1.0]:
					L._kbeam(k, Vector3(fx + sgn * 0.05, -2.4, z + 4.0 + sg * 0.25), Vector3(fx + sgn * 0.05, top + 0.9, z + 4.0 + sg * 0.25),
						0.05, 0.05, IRON, false)
				var ry := -2.2
				while ry < top:
					L._kbeam(k, Vector3(fx + sgn * 0.05, ry, z + 3.75), Vector3(fx + sgn * 0.05, ry, z + 4.25), 0.04, 0.04, IRON, false)
					ry += 0.3
				counts["ladder"] += 1
		z += 16.0
		i += 1


# --------------------------------------------------------------- landforms
func _landform(f: Dictionary) -> void:
	var o: PackedVector2Array = f["poly"]
	var kinds: PackedByteArray = f["kinds"]
	if f.get("paved", false):
		return
	# The tip: the free outline point farthest from the join.
	var tip := -1
	var far := 0.0
	var beach_mid := -1
	var beach_run := 0
	var run := 0
	for i in o.size():
		if kinds[i] == 3:
			run = 0
			continue
		var dj := Landforms._join_dist(f, o[i])
		if dj > far:
			far = dj
			tip = i
		if kinds[i] == 1:
			run += 1
			if run > beach_run:
				beach_run = run
				beach_mid = i - run / 2
		else:
			run = 0
	if tip >= 0 and far > 50.0:
		_viewpoint(f, o, tip)
	if beach_mid >= 0 and beach_run >= 4:
		_beach(f, o, beach_mid)


## A round stone viewpoint just inside the tip, with a beacon.
func _viewpoint(f: Dictionary, o: PackedVector2Array, i: int) -> void:
	var nn := SkyportIsland._out_n(o, i)
	var c := o[i] - nn * 9.0
	if not Geometry2D.is_point_in_polygon(c, o):
		return
	var t := Vector2(-nn.y, nn.x)
	var y := Landforms._height(f, c.x, c.y)
	var k := _k(c)
	L._kprism(k, _ring(c, t, nn, 5.0, -PI, 16), y - 1.2, y + 0.25, STONE)
	for a in 16:
		var a0 := TAU * a / 16.0
		var a1 := TAU * (a + 1) / 16.0
		if a >= 11 and a <= 13:
			continue  # (the way in, from inland)
		var q0 := c + Vector2(cos(a0), sin(a0)) * 5.0
		var q1 := c + Vector2(cos(a1), sin(a1)) * 5.0
		var m0 := c + Vector2(cos(a0), sin(a0)) * 4.6
		var m1 := c + Vector2(cos(a1), sin(a1)) * 4.6
		L._kprism(k, PackedVector2Array([q0, q1, m1, m0]), y + 0.25, y + 0.95, STONE.lightened(0.06))
	_bench(k, c - nn * 1.8 + t * 1.6, nn, y + 0.25)
	_bench(k, c - nn * 1.8 - t * 1.6, nn, y + 0.25)
	# The beacon: a white mast with a green lantern.
	var b := c + nn * 2.6
	L._kbeam(k, Vector3(b.x, y + 0.25, b.y), Vector3(b.x, y + 6.5, b.y), 0.28, 0.28, WHITE)
	L._kbeam(k, Vector3(b.x, y + 6.5, b.y), Vector3(b.x, y + 7.3, b.y), 0.5, 0.5, Color(0.1, 0.62, 0.35), false)
	L._kbeam(k, Vector3(b.x, y + 7.3, b.y), Vector3(b.x, y + 7.45, b.y), 0.65, 0.65, IRON, false)
	counts["viewpoint"] += 1
	places.append(["viewpoint", Vector3(c.x, y, c.y), nn])


## A jetty from the middle of a beach, a kiosk and umbrellas on the sand.
func _beach(f: Dictionary, o: PackedVector2Array, i: int) -> void:
	var nn := SkyportIsland._out_n(o, i)
	var p := o[i]
	var t := Vector2(-nn.y, nn.x)
	var top := Landforms._height(f, p.x, p.y)
	var L2 := L
	if BuildingMesher.shore_reach(L2, p, nn) > 70.0:
		# (Out past the sand, level with the beach's top.)
		_jetty(p - nn * 2.0, nn, maxf(top, 1.2), 48.0, false, 1.4)
	var k := _k(p)
	var kc := p - nn * 7.0 + t * 9.0
	if Geometry2D.is_point_in_polygon(kc, o):
		var ky := Landforms._height(f, kc.x, kc.y)
		var fp := PackedVector2Array([kc - t * 2.0 - nn * 1.6, kc + t * 2.0 - nn * 1.6, kc + t * 2.0 + nn * 1.6, kc - t * 2.0 + nn * 1.6])
		L._kprism(k, fp, ky - 0.3, ky + 2.4, Color(0.3, 0.55, 0.65))
		var eave := PackedVector2Array([kc - t * 2.5 - nn * 2.0, kc + t * 2.5 - nn * 2.0, kc + t * 2.5 + nn * 2.6, kc - t * 2.5 + nn * 2.6])
		L._kprism(k, eave, ky + 2.4, ky + 2.6, WHITE)
		# Serving hatch on the sea side, a counter and a striped awning.
		var hf := kc + nn * 1.62
		L._kbeam(k, Vector3(hf.x, ky + 1.0, hf.y) - Vector3(t.x, 0, t.y) * 1.2, Vector3(hf.x, ky + 1.0, hf.y) + Vector3(t.x, 0, t.y) * 1.2,
			0.05, 0.9, Color(0.12, 0.13, 0.14), false)
		var cf := kc + nn * 1.85
		L._kbeam(k, Vector3(cf.x, ky + 0.98, cf.y) - Vector3(t.x, 0, t.y) * 1.3, Vector3(cf.x, ky + 0.98, cf.y) + Vector3(t.x, 0, t.y) * 1.3,
			0.4, 0.06, WHITE, false)
		for st in 5:
			var a0 := -1.25 + st * 0.5
			var aw := kc + nn * 2.3 + t * (a0 + 0.25)
			L._kbeam(k, Vector3(aw.x, ky + 2.15, aw.y) - Vector3(nn.x, 0, nn.y) * 0.6, Vector3(aw.x, ky + 1.85, aw.y) + Vector3(nn.x, 0, nn.y) * 0.3,
				0.5, 0.04, Color(0.92, 0.3, 0.25) if st % 2 == 0 else WHITE, false)
	var cols := [Color(0.92, 0.25, 0.22), Color(0.98, 0.82, 0.25), Color(0.22, 0.52, 0.86), Color(0.2, 0.68, 0.55)]
	for j in 4:
		var q := p + nn * rng.randf_range(4.0, 9.0) + t * (-14.0 + j * 7.0 + rng.randf_range(-1.5, 1.5))
		var qy := _land_or_shore_y(f, q)
		if is_nan(qy) or qy < 0.4:
			continue
		L._kbeam(k, Vector3(q.x, qy - 0.3, q.y), Vector3(q.x, qy + 2.2, q.y), 0.07, 0.07, WHITE, false)
		var ring := PackedVector2Array()
		for a in 8:
			ring.append(q + Vector2(cos(TAU * (a + 0.5) / 8.0), sin(TAU * (a + 0.5) / 8.0)) * 1.3)
		L._kprism(k, ring, qy + 2.1, qy + 2.25, cols[j % cols.size()])
	counts["beach"] += 1
	places.append(["beach", Vector3(p.x, top, p.y), nn])


## Ground height on a landform, or its beach band near the edge (approx.).
static func _land_or_shore_y(f: Dictionary, q: Vector2) -> float:
	if Geometry2D.is_point_in_polygon(q, f["poly"]):
		return Landforms._height(f, q.x, q.y)
	return lerpf(1.0, 0.15, clampf(Landforms._edge_dist(f, q) / 12.0, 0.0, 1.0))


# ------------------------------------------------------------------ pieces
## Half (from = 0) or full (from = -PI) ring polygon round c, facing n.
static func _ring(c: Vector2, t: Vector2, n: Vector2, r: float, from: float, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for a in seg + 1:
		var ang := lerpf(from, PI, float(a) / seg)
		out.append(c + t * cos(ang) * r + n * sin(ang) * r)
	if from > -PI + 0.01:
		return out
	out.remove_at(out.size() - 1)
	return out


func _bench(k: Dictionary, c: Vector2, n: Vector2, y: float) -> void:
	var t := Vector2(-n.y, n.x)
	L._kbeam(k, Vector3(c.x, y + 0.45, c.y) - Vector3(t.x, 0, t.y) * 0.9, Vector3(c.x, y + 0.45, c.y) + Vector3(t.x, 0, t.y) * 0.9,
		0.45, 0.08, WOOD)
	var bk := c - n * 0.24
	L._kbeam(k, Vector3(bk.x, y + 0.8, bk.y) - Vector3(t.x, 0, t.y) * 0.9, Vector3(bk.x, y + 0.8, bk.y) + Vector3(t.x, 0, t.y) * 0.9,
		0.06, 0.3, WOOD, false)
	for sg: float in [-1.0, 1.0]:
		var l := c + t * sg * 0.75
		L._kbeam(k, Vector3(l.x, y, l.y), Vector3(l.x, y + 0.45, l.y), 0.5, 0.06, IRON, false)


func _lamp(k: Dictionary, c: Vector2, y: float) -> void:
	L._kbeam(k, Vector3(c.x, y, c.y), Vector3(c.x, y + 3.6, c.y), 0.12, 0.12, IRON, false)
	L._kbeam(k, Vector3(c.x, y + 3.6, c.y), Vector3(c.x, y + 3.95, c.y), 0.3, 0.3, LAMP, false)
	L._kbeam(k, Vector3(c.x, y + 3.95, c.y), Vector3(c.x, y + 4.05, c.y), 0.4, 0.4, IRON, false)
