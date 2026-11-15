class_name Gps
extends Node
## The one GPS route of the game: the HUD minimap and the phone's full map
## both draw `points` (the same array), so they always show the same route.
##
## Routing uses the shared road graph (RoadNet: Never Stop's lane network
## of both landmasses, stitched over the bridge), built once on a thread at
## start. Driving follows lanes the way traffic does (one-way roundabouts,
## the right side of the road); on foot the same graph is walked both ways.
## A route is only computed when a destination is set, when you leave the
## route, or when you get in or out of a car – never per frame.
##
## Destination refs ({kind: "unit"|"vehicle"|"home"|"point", id}) are saved
## in Empire.flags, so an active route survives a reload.

signal changed

const COLOUR := Color(0.74, 0.36, 1.0)        # route purple (both maps)
const COLOUR_EDGE := Color(0.16, 0.05, 0.3)
const OFF_ROUTE_WALK := 18.0
const OFF_ROUTE_DRIVE := 28.0
const ARRIVE_WALK := 7.0
const ARRIVE_DRIVE := 16.0

var game: EmpireGame
var net: RoadNet
var dest := Vector3.INF
var label := ""
var ref := {}
var points := PackedVector3Array()   # start → destination, world space
var mode := "walk"                   # walk / drive (the route was planned for)
var progress_i := 0                  # route segment you're on
var remaining := 0.0                 # road metres left
var turn := Vector2.ZERO             # x: -1 left / +1 right / 0 none, y: metres to it
var message := ""                    # why there's no line ("" = fine)
var reroutes := 0

var _thread: Thread
var _need_route := false
var _check_t := 0.0
var _off_t := 0.0
var _last_route_t := -10.0
var _seg_cum := PackedFloat32Array()  # route metres at each point
# Re-planning while you move (off route, car in/out, a moving target) runs
# on a worker thread: RoadNet is read-only once built.
var _task := -1
var _task_result := {}
var _task_mode := ""
var _task_dest := Vector3.INF


## Starts building the road graph in the background.
func setup(p_game: EmpireGame) -> void:
	game = p_game
	_thread = Thread.new()
	_thread.start(_build_net.bind(game.layout))


func _build_net(layout: CityLayout) -> RoadNet:
	return RoadNet.new().build(layout)


func ready_net() -> bool:
	if net != null:
		return true
	if _thread and _thread.is_started() and not _thread.is_alive():
		net = _thread.wait_to_finish()
		_thread = null
		return net != null
	return false


## Blocks until the road graph exists (tests, scripted runs).
func wait_net() -> void:
	if net == null and _thread and _thread.is_started():
		net = _thread.wait_to_finish()
		_thread = null


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)


# ------------------------------------------------------------ public
func active() -> bool:
	return dest != Vector3.INF


func set_destination(p: Vector3, p_label: String, p_ref := {}) -> void:
	dest = p
	label = p_label
	ref = p_ref.duplicate()
	message = ""
	points = PackedVector3Array()
	_need_route = true
	_last_route_t = -10.0
	_persist()
	if ready_net():
		_route_now()
	else:
		message = "Planning route…"
	changed.emit()


func clear(reason := "") -> void:
	dest = Vector3.INF
	label = ""
	ref = {}
	points = PackedVector3Array()
	_seg_cum = PackedFloat32Array()
	remaining = 0.0
	turn = Vector2.ZERO
	message = reason
	_need_route = false
	_persist()
	changed.emit()


## Restores the saved destination (after a load / new game).
func restore() -> void:
	var f: Dictionary = game.empire.flags
	var t = f.get("gps", null)
	if t is Array and (t as Array).size() == 3:
		set_destination(Vector3(t[0], t[1], t[2]), String(f.get("gps_label", "")), f.get("gps_ref", {}))
	else:
		dest = Vector3.INF
		points = PackedVector3Array()
		changed.emit()


## Route points still ahead of you (for drawing: the part you've driven is dropped).
func ahead() -> PackedVector3Array:
	if points.size() < 2:
		return points
	var out := PackedVector3Array()
	out.append(_here())
	for i in range(clampi(progress_i + 1, 0, points.size()), points.size()):
		out.append(points[i])
	return out


func distance_text() -> String:
	if not active():
		return ""
	var d := remaining if points.size() >= 2 else _d2(_here(), dest)
	return "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(roundf(d / 10.0) * 10.0)


func turn_text() -> String:
	if turn.x == 0.0 or points.size() < 2:
		return ""
	var m := int(roundf(turn.y / 10.0) * 10.0)
	return "%s in %d m" % ["Turn left" if turn.x < 0.0 else "Turn right", maxi(m, 10)]


# ------------------------------------------------------------ frame
func _process(dt: float) -> void:
	if game == null or game.state != "play":
		return
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if active() and _task_dest.distance_to(dest) < 0.01:
			_apply(_task_result, _task_mode)
	if not active():
		return
	if _need_route and ready_net():
		_route_async()
	# A moving target (your car being driven / delivered) re-aims.
	if String(ref.get("kind", "")) == "vehicle":
		var c: Car = game.cars.get(String(ref.get("id", "")))
		if c and c.global_position.distance_to(dest) > 12.0:
			dest = c.global_position
			_need_route = true
			_persist()
	_check_t -= dt
	if _check_t > 0.0:
		return
	_check_t = 0.25
	var want_mode := _mode_now()
	var here := _here()
	var arrive := ARRIVE_DRIVE if want_mode == "drive" else ARRIVE_WALK
	if _d2(here, dest) < arrive:
		var what := label
		clear()
		game.ui.toast("Arrived%s" % (": " + what if what != "" else ""), "good")
		return
	if want_mode != mode and points.size() >= 2:
		_reroute()
		return
	if points.size() < 2:
		return
	_track(here, 0.25)


func _track(here: Vector3, dt: float) -> void:
	# Nearest segment in a window ahead of where we were (cheap, monotone-ish).
	var best_i := progress_i
	var best_d := INF
	var best_t := 0.0
	var lo := maxi(progress_i - 3, 0)
	var hi := mini(progress_i + 60, points.size() - 1)
	for i in range(lo, hi):
		var a := points[i]
		var b := points[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(here.x - a.x, here.z - a.z)
		var l2 := maxf(ab.length_squared(), 0.0001)
		var t := clampf(ap.dot(ab) / l2, 0.0, 1.0)
		var d := (ap - ab * t).length()
		if d < best_d:
			best_d = d
			best_i = i
			best_t = t
	progress_i = best_i
	var seg_len := _seg_cum[best_i + 1] - _seg_cum[best_i]
	remaining = maxf(_seg_cum[-1] - (_seg_cum[best_i] + seg_len * best_t), 0.0) + best_d
	var off := OFF_ROUTE_DRIVE if mode == "drive" else (60.0 if mode == "direct" else OFF_ROUTE_WALK)
	if best_d > off:
		_off_t += dt
		if _off_t > 1.2:
			_reroute()
	else:
		_off_t = 0.0
	turn = _next_turn(best_i, best_t)


func _reroute() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_route_t < 2.5 or _task >= 0:
		return
	_off_t = 0.0
	reroutes += 1
	_route_async()


# ------------------------------------------------------------ routing
func _here() -> Vector3:
	var vn := game.vehicle_node()
	if vn != null and is_instance_valid(vn):
		return vn.global_position
	return game.player.global_position


## walk / drive (roads) or direct (flying or sailing: a straight line,
## not the road graph).
func _mode_now() -> String:
	if game.skyport_play and game.skyport_play.piloting != "":
		return "direct"
	return "drive" if game.driving != "" else "walk"


func _heading() -> Vector3:
	if game.driving != "" and game.cars.has(game.driving):
		var f := -(game.cars[game.driving] as Node3D).global_basis.z
		f.y = 0.0
		return f.normalized()
	return Vector3.ZERO


## Plans now, on this thread (when you set a destination: one tap, one plan).
func _route_now() -> void:
	_need_route = false
	_last_route_t = Time.get_ticks_msec() / 1000.0
	var m := _mode_now()
	_apply(plan(_here(), dest, m, _heading()), m)


## Plans on a worker thread (re-planning on the move: no frame hitch). The
## old route stays up until the new one lands.
func _route_async() -> void:
	if _task >= 0:
		return
	_need_route = false
	_last_route_t = Time.get_ticks_msec() / 1000.0
	var m := _mode_now()
	var from := _here()
	var h := _heading()
	var to := dest
	_task_mode = m
	_task_dest = to
	_task = WorkerThreadPool.add_task(func(): _task_result = plan(from, to, m, h))


func _apply(r: Dictionary, m: String) -> void:
	mode = m
	points = r["points"]
	message = r["error"]
	progress_i = 0
	_off_t = 0.0
	_seg_cum = PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		_seg_cum.append(_seg_cum[i - 1] + _d2(points[i], points[i - 1]))
	remaining = _seg_cum[-1] if points.size() >= 2 else 0.0
	turn = _next_turn(0, 0.0) if points.size() >= 2 else Vector2.ZERO
	changed.emit()


## A road route from `from` to `to`: {points, length, error}. Pure (tests call it).
func plan(from: Vector3, to: Vector3, p_mode: String, heading := Vector3.ZERO) -> Dictionary:
	var out := {"points": PackedVector3Array(), "length": 0.0, "error": ""}
	if p_mode == "direct":
		# Air and sea: straight there (the map shows the line; no roads).
		out["points"] = PackedVector3Array([from, Vector3(to.x, from.y, to.z)])
		out["length"] = _d2(from, to)
		return out
	if net == null:
		out["error"] = "Planning route…"
		return out
	var s0 := net.nearest(from, heading, 60.0) if p_mode == "drive" and heading != Vector3.ZERO else {}
	if s0.is_empty():
		s0 = net.nearest(from, Vector3.ZERO, 120.0)
	var t0 := net.nearest(to, Vector3.ZERO, 120.0)
	if s0.is_empty():
		out["error"] = "You're too far from any road"
		return out
	if t0.is_empty():
		out["error"] = "No road goes there"
		return out
	var pts := PackedVector3Array()
	if p_mode == "drive":
		var f := net.flow_field(to)
		if net.field_distance(f, s0["lane"], s0["s"]) < INF:
			pts = net.route(f, s0["lane"], s0["s"], 60000.0)
		else:
			# The nearest lane to the door only leads away (a one-way stub):
			# fall back to the street graph either way round.
			pts = _walk_route(s0, t0, to)
		if pts.is_empty():
			out["error"] = "No road route there from here"
			return out
	else:
		pts = _walk_route(s0, t0, to)
		if pts.is_empty():
			out["error"] = "No way there on foot from here"
			return out
	var full := PackedVector3Array([from])
	full.append_array(pts)
	if _d2(full[-1], to) > 0.5:
		full.append(to)
	full = _simplify(full)
	var length := 0.0
	for i in range(1, full.size()):
		length += _d2(full[i], full[i - 1])
	out["points"] = full
	out["length"] = length
	return out


## On foot: the lane graph walked in both directions (Dijkstra from the
## target, then downhill from the start).
func _walk_route(s0: Dictionary, t0: Dictionary, to: Vector3) -> PackedVector3Array:
	var n := net.node_count()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var hd := PackedFloat32Array()
	var hn := PackedInt32Array()
	var tl: int = t0["lane"]
	var ts: float = t0["s"]
	for id in net.lane_nodes[tl]:
		var c := absf(net.node_s[id] - ts)
		dist[id] = c
		RoadNet._push(hd, hn, c, id)
	while hn.size() > 0:
		var top := RoadNet._pop(hd, hn)
		var d: float = top[0]
		var u: int = top[1]
		if d > dist[u]:
			continue
		for pass_i in 2:
			var es: PackedInt32Array = net.in_edges[u] if pass_i == 0 else net.out_edges[u]
			var cs: PackedFloat32Array = net.in_cost[u] if pass_i == 0 else net.out_cost[u]
			for k in es.size():
				var v := es[k]
				var nd := d + cs[k]
				if nd < dist[v]:
					dist[v] = nd
					RoadNet._push(hd, hn, nd, v)
	# Best node to start from on our lane (either way along it).
	var sl: int = s0["lane"]
	var ss: float = s0["s"]
	var start := -1
	var sbest := INF
	for id in net.lane_nodes[sl]:
		var c2 := absf(net.node_s[id] - ss) + dist[id]
		if c2 < sbest:
			sbest = c2
			start = id
	if start < 0 or sbest == INF:
		return PackedVector3Array()
	var out := PackedVector3Array()
	_lane_span(out, sl, ss, net.node_s[start])
	var u2 := start
	var guard := 0
	while guard < 20000:
		guard += 1
		if net.node_lane[u2] == tl:
			_lane_span(out, tl, net.node_s[u2], ts)
			break
		# Downhill: the neighbour on the shortest way (dist strictly falls, so
		# this can't loop).
		var best := -1
		var bscore := INF
		var bcost := 0.0
		for pass_i in 2:
			var es: PackedInt32Array = net.out_edges[u2] if pass_i == 0 else net.in_edges[u2]
			var cs: PackedFloat32Array = net.out_cost[u2] if pass_i == 0 else net.in_cost[u2]
			for k in es.size():
				var v := es[k]
				if dist[v] < dist[u2] and dist[v] + cs[k] < bscore:
					bscore = dist[v] + cs[k]
					bcost = cs[k]
					best = v
		if best < 0:
			break
		# Along the lane – unless the edge is a loop's wrap (a 0 m step from
		# its end back to its start): then the next node is where we are.
		if net.node_lane[best] == net.node_lane[u2] and absf(net.node_s[best] - net.node_s[u2]) < bcost + 1.0:
			_lane_span(out, net.node_lane[u2], net.node_s[u2], net.node_s[best])
		else:
			out.append(net.node_pos[best])
		u2 = best
	out.append(to)
	return out


## Lane points between s_a and s_b (either direction), appended.
func _lane_span(out: PackedVector3Array, lane: int, s_a: float, s_b: float) -> void:
	var step := RoadNet.STEP
	var dir := 1.0 if s_b >= s_a else -1.0
	var s := s_a
	var guard := 0
	while (s_b - s) * dir > 0.0 and guard < 4000:
		guard += 1
		out.append(net.lane_point(lane, s))
		s += step * dir
	out.append(net.lane_point(lane, s_b))


## Drops points that add nothing (straight runs): fewer to draw and track.
static func _simplify(p: PackedVector3Array) -> PackedVector3Array:
	if p.size() < 3:
		return p
	var out := PackedVector3Array([p[0]])
	for i in range(1, p.size() - 1):
		var a := out[-1]
		var b := p[i]
		var c := p[i + 1]
		if _d2(b, a) < 0.8:
			continue
		var ab := Vector2(b.x - a.x, b.z - a.z).normalized()
		var bc := Vector2(c.x - b.x, c.z - b.z).normalized()
		if ab.dot(bc) > 0.9995 and _d2(b, a) < 60.0:
			continue
		out.append(b)
	out.append(p[-1])
	return out


static func _d2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The next real turn ahead (over 40° within ~25 m): [-1 left / +1 right, metres].
func _next_turn(i0: int, t0: float) -> Vector2:
	var walked := -(_seg_cum[i0 + 1] - _seg_cum[i0]) * t0 if i0 + 1 < _seg_cum.size() else 0.0
	# (Point 1 is where the route joins the road from where you stood: stepping
	# onto it isn't a turn. Nor is the last bit up to the door.)
	for i in range(maxi(i0 + 1, 2), points.size() - 2):
		walked = _seg_cum[i] - _seg_cum[i0] - (_seg_cum[i0 + 1] - _seg_cum[i0]) * t0
		if walked > 900.0:
			break
		var a := _dir_over(i, -1, 12.0)
		var b := _dir_over(i, 1, 12.0)
		if a == Vector2.ZERO or b == Vector2.ZERO:
			continue
		var ang := a.angle_to(b)
		if absf(ang) > deg_to_rad(40.0):
			# (map view: x right, y = world z down; a positive angle turns right)
			return Vector2(signf(ang), maxf(walked, 0.0))
	return Vector2.ZERO


func _dir_over(i: int, sgn: int, span: float) -> Vector2:
	var acc := 0.0
	var j := i
	while acc < span:
		var k := j + sgn
		if k < 0 or k >= points.size():
			break
		acc += Vector2(points[k].x - points[j].x, points[k].z - points[j].z).length()
		j = k
	if j == i:
		return Vector2.ZERO
	var d := Vector2(points[j].x - points[i].x, points[j].z - points[i].z) * float(sgn)
	return d.normalized() if d.length() > 0.01 else Vector2.ZERO


func _persist() -> void:
	if game == null or game.empire == null:
		return
	var f: Dictionary = game.empire.flags
	if dest == Vector3.INF:
		f.erase("gps")
		f.erase("gps_label")
		f.erase("gps_ref")
	else:
		f["gps"] = [dest.x, dest.y, dest.z]
		f["gps_label"] = label
		f["gps_ref"] = ref
