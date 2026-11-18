class_name SafeGround
extends RefCounted
## Where something can safely be put back after it ends up in the sea:
## dry land or a road (bridges included) standing clear of the water, solid
## underfoot, with room round it. Every recovery goes through here – a car
## towed out, the hero wading back, a ditched aircraft, a save loaded in the
## water – so none of them can land the body back in the sea.
##
## (2026-11-18: the tow put the car down at the same x/z it sank at, so it
## fell straight back in and was towed again every 2 s; a save made in the
## water reloaded the hero there AND remembered that spot as "dry".)
##
## Search order: the nearest road lane (dry by construction, any island,
## bridge decks too), then solid dry ground round the point, then the
## remembered last safe places. A recovery that repeats near the same spot
## within a few seconds blacklists that spot and widens the search.

const WATER_Y := -1.6
## Ground has to stand this far above the sea surface to count as dry.
const DRY_MARGIN := 0.3
const GROUND_MASK := 1 | (1 << 3)               # world solids + street/ground (+ water floor)
const BLOCK_MASK := 1 | (1 << 1) | (1 << 2) | (1 << 4)   # buildings, kit, bodies, props
const LANE_RADII := [30.0, 80.0, 200.0, 600.0, 2000.0]
const RING_RADII := [3.0, 6.0, 10.0, 15.0, 22.0, 30.0, 40.0, 55.0, 75.0, 100.0]
const LOOP_WINDOW_MS := 10000
const LOOP_RADIUS := 25.0
const BAD_RADIUS := 18.0
const BAD_MS := 90000

var layout: CityLayout
var host: Node3D          # any node in the 3-D world (for the physics space)
var net_fn := Callable()  # () -> RoadNet or null
## [Vector3 target, msec] of recent recoveries, per key ("hero", vehicle id).
var _recent := {}
## [[Vector3, until_msec], ...] spots that sent something back into the sea.
var _bad: Array = []


func _init(p_layout: CityLayout, p_host: Node3D, p_net_fn := Callable()) -> void:
	layout = p_layout
	host = p_host
	net_fn = p_net_fn


# ---------------------------------------------------------------- tests
## Open water at this x/z (the coast polygons; a bridge deck is "water" here).
func water_xz(p: Vector3) -> bool:
	return layout.is_water(p)


## The ground under p by the layout (no physics): NAN over open water.
func ground_xz(p: Vector3) -> float:
	if layout.is_water(p):
		return NAN
	var g := layout.ground_y(p.x, p.z)
	return g if g > WATER_Y + DRY_MARGIN else NAN


## Physics probe straight down from `top` over `reach` metres:
## {y, wet, steep, hit}. wet = the first thing under it is the sea floor or
## lies below the surface. Bodies in `exclude` are ignored.
func probe(top: Vector3, reach := 30.0, exclude: Array[RID] = []) -> Dictionary:
	var out := {"y": NAN, "wet": false, "steep": false, "hit": false}
	if host == null or not host.is_inside_tree():
		return out
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * reach, GROUND_MASK, exclude)
	var hit := host.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return out
	out["hit"] = true
	var y := float((hit["position"] as Vector3).y)
	out["y"] = y
	var col: Object = hit.get("collider")
	out["wet"] = y < WATER_Y + DRY_MARGIN or (col is Node and (col as Node).is_in_group("water"))
	out["steep"] = (hit["normal"] as Vector3).y < 0.72
	return out


## Room for a box `size` (x width, y height, z length) standing on y at p.
func clear_at(p: Vector3, size: Vector3, yaw := 0.0, exclude: Array[RID] = []) -> bool:
	if host == null or not host.is_inside_tree():
		return true
	var sh := BoxShape3D.new()
	sh.size = Vector3(maxf(size.x - 0.2, 0.3), maxf(size.y - 0.4, 0.4), maxf(size.z - 0.2, 0.3))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * (size.y * 0.5 + 0.25))
	q.collision_mask = BLOCK_MASK
	q.exclude = exclude
	return host.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Is p (a body's feet / a car's underside) a safe place to stand right
## now? Dry, solid, not too steep. Physics wins when there is any; with no
## collision streamed in there, the layout decides.
func is_safe(p: Vector3, exclude: Array[RID] = []) -> bool:
	var pr := probe(p + Vector3.UP * 1.5, 6.0, exclude)
	if pr["hit"]:
		return not pr["wet"] and not pr["steep"] and float(pr["y"]) > p.y - 2.5
	return not is_nan(ground_xz(p)) and p.y > WATER_Y + DRY_MARGIN


func _is_bad(p: Vector3) -> bool:
	var now := Time.get_ticks_msec()
	var keep: Array = []
	var bad := false
	for b: Array in _bad:
		if int(b[1]) > now:
			keep.append(b)
			if Vector2(p.x, p.z).distance_to(Vector2((b[0] as Vector3).x, (b[0] as Vector3).z)) < BAD_RADIUS:
				bad = true
	_bad = keep
	return bad


## A dry standing point at x/z near `p` (y from physics, else the layout),
## or Vector3.INF. Physics only above a believable ground height: a ray that
## lands on a roof is not the street.
func _stand_at(p: Vector3, size: Vector3, yaw: float, exclude: Array[RID], need_physics: bool) -> Vector3:
	if _is_bad(p):
		return Vector3.INF
	var g := ground_xz(p)
	var top := (g if not is_nan(g) else maxf(p.y, WATER_Y)) + 4.0
	var pr := probe(Vector3(p.x, top, p.z), 40.0, exclude)
	var y := NAN
	if pr["hit"]:
		if pr["wet"] or pr["steep"]:
			return Vector3.INF
		y = float(pr["y"])
		if not is_nan(g) and y > g + 2.5:
			return Vector3.INF   # (a roof, a canopy, a parked bus)
	elif need_physics or is_nan(g):
		return Vector3.INF
	else:
		y = g
	var at := Vector3(p.x, y, p.z)
	if pr["hit"] and not clear_at(at, size, yaw, exclude):
		return Vector3.INF
	return at


# ---------------------------------------------------------------- search
## Somewhere safe near `from` for a body of `size` (x, y, z metres).
## opts: kind "foot" | "car" | "craft", exclude (Array[RID]), fallbacks
## (Array of Vector3, newest first), key (loop tracking), max_r.
## Returns {ok, pos (feet / underside), yaw, how}.
func find(from: Vector3, size: Vector3, opts := {}) -> Dictionary:
	var kind := String(opts.get("kind", "foot"))
	var ex: Array[RID] = []
	for r in opts.get("exclude", []):
		ex.append(r)
	var max_r := float(opts.get("max_r", 2000.0))
	var escalate := _looping(String(opts.get("key", "")), from)
	var res := {}
	if kind == "foot" and not escalate:
		res = _ring(from, size, ex, minf(max_r, 60.0))
	if res.is_empty():
		res = _lane(from, size, ex, kind, max_r, escalate)
	if res.is_empty() and kind != "foot":
		res = _ring(from, size, ex, minf(max_r, 100.0))
	if res.is_empty():
		for f in opts.get("fallbacks", []):
			if f is Vector3 and f != Vector3.INF and not _is_bad(f):
				var at := _stand_at(f, size, 0.0, ex, false)
				if at != Vector3.INF:
					res = {"pos": at, "yaw": NAN, "how": "last safe"}
					break
	if res.is_empty():
		return {"ok": false, "pos": from, "yaw": NAN, "how": "none"}
	res["ok"] = true
	_note(String(opts.get("key", "")), res["pos"])
	return res


## True when this key was recovered near here a moment ago (the last place
## didn't hold): that place is blacklisted and the search skips nearby land.
func _looping(key: String, from: Vector3) -> bool:
	if key == "" or not _recent.has(key):
		return false
	var r: Array = _recent[key]
	var last: Vector3 = r[0]
	if Time.get_ticks_msec() - int(r[1]) < LOOP_WINDOW_MS and Vector2(from.x, from.z).distance_to(Vector2(last.x, last.z)) < LOOP_RADIUS:
		_bad.append([last, Time.get_ticks_msec() + BAD_MS])
		return true
	return false


func _note(key: String, at: Vector3) -> void:
	if key != "":
		_recent[key] = [at, Time.get_ticks_msec()]


## Recent recovery count bookkeeping is per key; clear it once the body has
## been fine for a while (the game calls this from its safe-position tick).
func settled(key: String) -> void:
	_recent.erase(key)


func _ring(from: Vector3, size: Vector3, ex: Array[RID], max_r: float) -> Dictionary:
	for r: float in RING_RADII:
		if r > max_r:
			break
		var n := 12 if r < 20.0 else 20
		var best := Vector3.INF
		var bd := INF
		for k in n:
			var a := k * TAU / n
			var q := from + Vector3(cos(a), 0.0, sin(a)) * r
			var at := _stand_at(q, size, 0.0, ex, true)
			if at == Vector3.INF or not _dry_round(at, 1.6):
				continue
			var d := absf(at.y - from.y)
			if d < bd:
				bd = d
				best = at
		if best != Vector3.INF:
			return {"pos": best, "yaw": NAN, "how": "ground"}
	return {}


## A little dry land all round (not the very lip of a quay).
func _dry_round(p: Vector3, r: float) -> bool:
	for k in 4:
		var a := k * TAU / 4.0
		if layout.is_water(p + Vector3(cos(a), 0.0, sin(a)) * r) and p.y < WATER_Y + 3.0:
			return false
	return true


func _lane(from: Vector3, size: Vector3, ex: Array[RID], kind: String, max_r: float, escalate: bool) -> Dictionary:
	var net = net_fn.call() if net_fn.is_valid() else null
	if net == null:
		return {}
	for r: float in LANE_RADII:
		if r > max_r:
			break
		var near: Dictionary = net.nearest(from, Vector3.ZERO, r, -1, true)
		if near.is_empty():
			continue
		var lane: int = near["lane"]
		var s0: float = near["s"]
		for ds: float in [0.0, 8.0, -8.0, 16.0, -16.0, 30.0, -30.0, 50.0, -50.0]:
			var p: Vector3 = net.lane_point(lane, s0 + ds)
			if p.y < WATER_Y + DRY_MARGIN + 0.2 or (escalate and _is_bad(p)):
				continue
			var dir: Vector3 = net.lane_dir(lane, s0 + ds)
			var yaw := atan2(-dir.x, -dir.z)
			if kind == "foot":
				# On the pavement beside the lane (kerb side), else its edge.
				var side := Vector3(-dir.z, 0.0, dir.x)
				if side.dot(from - p) < 0.0:
					side = -side
				for off: float in [5.5, 3.5, 2.0]:
					var w := p + side * off
					if not net.nearest(w, Vector3.ZERO, 1.6, -1, true).is_empty() and off > 2.0:
						continue
					var at := _stand_lane(w, p.y, size, yaw, ex)
					if at != Vector3.INF:
						return {"pos": at, "yaw": yaw, "how": "pavement"}
			else:
				var at2 := _stand_lane(p, p.y, size, yaw, ex)
				if at2 != Vector3.INF:
					return {"pos": at2, "yaw": yaw, "how": "road"}
	return {}


## A point on (or by) a lane: the lane height is trusted when no physics is
## streamed in there (roads and bridge decks are dry by construction).
func _stand_lane(p: Vector3, lane_y: float, size: Vector3, yaw: float, ex: Array[RID]) -> Vector3:
	if _is_bad(p):
		return Vector3.INF
	var pr := probe(Vector3(p.x, lane_y + 3.0, p.z), 8.0, ex)
	if pr["hit"]:
		if pr["wet"] or pr["steep"]:
			return Vector3.INF
		var at := Vector3(p.x, float(pr["y"]), p.z)
		return at if clear_at(at, size, yaw, ex) else Vector3.INF
	return Vector3(p.x, lane_y, p.z) if lane_y > WATER_Y + DRY_MARGIN else Vector3.INF
