class_name Bench
extends Node
## Engine benchmark (2026-11-27 engine pass): `--play --new --scenarios=BENCH`
## (headless for main-thread CPU, xvfb for draw stats). Drives a physics car
## along GPS road routes at speed across the three islands, then repeats
## location transitions (lift → garage → street), sampling every frame:
##   wall-clock frame time, Godot process/physics time, draw calls,
##   primitives, objects, static memory, node count;
##   per-script _process/_physics_process cost (this node takes over the
##   processing of every scripted node and times each call, grouped by
##   script file) – so a hitch frame says WHICH system spiked.
## Prints BENCH lines; `--bench-out=<json>` writes the full result.
## Dev only: nothing in the game calls this outside --scenarios=BENCH.

var game: EmpireGame
var on := false
var _taken: Array = []          # [node, script name, physics?]
var _scan_t := 0.0
var _frame := {}                # script -> usec this frame
var _acc := {}                  # script -> total usec
var _peak := {}                 # script -> peak usec in one frame
var _frames_ms: Array[float] = []
var _last_us := 0
var _hitches: Array = []        # [t, ms, top systems]
var _phase := ""
var _phase_stats := {}          # phase -> {frames, ms list}
var _mem_track: Array = []
var _t := 0.0
var _draws := 0.0
var _prims := 0.0
var _objs := 0.0
var _n := 0
var _last_nodes := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	process_physics_priority = -1000


func start() -> void:
	on = true
	_rescan()
	get_tree().node_added.connect(_on_added)
	_last_us = Time.get_ticks_usec()


var _added: Array = []
var _added_prev: Array = []


func _on_added(n: Node) -> void:
	_added.append(n)


## New nodes are checked a frame after they arrive (after their _ready has
## decided whether they process): no tree walks while measuring.
func _take_new() -> void:
	var todo := _added_prev
	_added_prev = _added
	_added = []
	for n in todo:
		if not is_instance_valid(n):
			continue
		var nd: Node = n
		if nd.get_script() == null or not nd.is_inside_tree():
			continue
		if nd.is_processing() and nd.has_method("_process"):
			nd.set_process(false)
			_taken.append([nd, _script_name(nd), false])
		if nd.is_physics_processing() and nd.has_method("_physics_process"):
			nd.set_physics_process(false)
			_taken.append([nd, _script_name(nd), true])


func stop() -> void:
	on = false
	if get_tree().node_added.is_connected(_on_added):
		get_tree().node_added.disconnect(_on_added)
	for e: Array in _taken:
		if is_instance_valid(e[0]):
			var n: Node = e[0]
			if e[2]:
				n.set_physics_process(true)
			else:
				n.set_process(true)
	_taken.clear()


func phase(nm: String) -> void:
	_phase = nm
	if not _phase_stats.has(nm):
		_phase_stats[nm] = {"ms": [] as Array[float], "draws": 0.0, "n": 0}


func _script_name(n: Node) -> String:
	var s: Script = n.get_script()
	return s.resource_path.get_file().get_basename() if s else n.get_class()


func _rescan() -> void:
	var seen := {}
	for e: Array in _taken:
		if is_instance_valid(e[0]):
			seen[str(e[0].get_instance_id()) + str(e[2])] = true
	var keep: Array = []
	for e: Array in _taken:
		if is_instance_valid(e[0]) and not (e[0] as Node).is_queued_for_deletion():
			keep.append(e)
	_taken = keep
	_scan(get_tree().root, seen)


func _scan(n: Node, seen: Dictionary) -> void:
	if n != self and n.get_script() != null and n.can_process():
		var id := str(n.get_instance_id())
		if n.is_processing() and n.has_method("_process"):
			n.set_process(false)
			if not seen.has(id + "false"):
				_taken.append([n, _script_name(n), false])
		if n.is_physics_processing() and n.has_method("_physics_process"):
			n.set_physics_process(false)
			if not seen.has(id + "true"):
				_taken.append([n, _script_name(n), true])
	for c in n.get_children():
		_scan(c, seen)


func _run_taken(dt: float, physics: bool) -> void:
	var paused := get_tree().paused
	for e: Array in _taken:
		if e[2] != physics:
			continue
		if not is_instance_valid(e[0]):
			continue
		var n: Node = e[0]
		if not n.is_inside_tree():
			continue
		if paused and not n.can_process():
			continue
		var t0 := Time.get_ticks_usec()
		if physics:
			n._physics_process(dt)
		else:
			n._process(dt)
		var us := Time.get_ticks_usec() - t0
		var k: String = e[1] + (" (phys)" if physics else "")
		_frame[k] = int(_frame.get(k, 0)) + us


func _physics_process(dt: float) -> void:
	if on:
		_run_taken(dt, true)


func _process(dt: float) -> void:
	if not on:
		return
	_run_taken(dt, false)
	_take_new()
	_scan_t -= dt
	if _scan_t <= 0.0:
		# (drop freed entries now and then: a cheap pass over the list)
		_scan_t = 5.0
		_taken = _taken.filter(func(e): return is_instance_valid(e[0]))
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	_t += dt
	_n += 1
	_frames_ms.append(ms)
	_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	if _phase != "":
		var ps: Dictionary = _phase_stats[_phase]
		(ps["ms"] as Array[float]).append(ms)
		ps["draws"] = float(ps["draws"]) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		ps["n"] = int(ps["n"]) + 1
	for k: String in _frame:
		var us: int = _frame[k]
		_acc[k] = int(_acc.get(k, 0)) + us
		_peak[k] = maxi(int(_peak.get(k, 0)), us)
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var dnodes := nodes - _last_nodes
	_last_nodes = nodes
	if ms > 50.0 and _n > 5:
		var keys := _frame.keys()
		keys.sort_custom(func(a, b): return _frame[a] > _frame[b])
		var top := []
		for k in keys.slice(0, 3):
			top.append("%s %.1f" % [k, _frame[k] / 1000.0])
		top.append("[process %.1f physics %.1f nodes %+d]" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, dnodes])
		_hitches.append([snappedf(_t, 0.1), snappedf(ms, 0.1), _phase, top])
	_frame.clear()
	if _n % 60 == 0:
		_mem_track.append([snappedf(_t, 0.1), int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT))])


static func pct(a: Array[float], q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[int((s.size() - 1) * q)]


func report() -> Dictionary:
	var n := maxf(_n, 1)
	var out := {"frames": _n, "secs": _t,
		"p50": pct(_frames_ms, 0.5), "p95": pct(_frames_ms, 0.95), "p99": pct(_frames_ms, 0.99), "max": pct(_frames_ms, 1.0),
		"over33": _frames_ms.filter(func(x): return x > 33.4).size(), "over50": _frames_ms.filter(func(x): return x > 50.0).size(),
		"over100": _frames_ms.filter(func(x): return x > 100.0).size(),
		"draws": _draws / n, "prims_k": _prims / n / 1000.0, "objects": _objs / n,
		"systems": {}, "phases": {}, "hitches": _hitches, "mem": _mem_track}
	var keys := _acc.keys()
	keys.sort_custom(func(a, b): return _acc[a] > _acc[b])
	print("BENCH frames=%d p50=%.2f p95=%.2f p99=%.2f max=%.1f >33ms=%d >50ms=%d >100ms=%d draws=%.0f prims=%.0fk objects=%.0f" % [
		_n, out["p50"], out["p95"], out["p99"], out["max"], out["over33"], out["over50"], out["over100"], out["draws"], out["prims_k"], out["objects"]])
	for k in keys.slice(0, 24):
		out["systems"][k] = {"mean_ms": _acc[k] / 1000.0 / n, "peak_ms": _peak[k] / 1000.0}
		print("BENCH sys %-26s mean=%.3f ms/frame peak=%.2f ms" % [k, _acc[k] / 1000.0 / n, _peak[k] / 1000.0])
	for ph: String in _phase_stats:
		var ps: Dictionary = _phase_stats[ph]
		var a: Array[float] = ps["ms"]
		out["phases"][ph] = {"frames": a.size(), "p50": pct(a, 0.5), "p95": pct(a, 0.95), "p99": pct(a, 0.99), "max": pct(a, 1.0),
			"over50": a.filter(func(x): return x > 50.0).size(), "draws": float(ps["draws"]) / maxf(int(ps["n"]), 1)}
		print("BENCH phase %-14s frames=%d p50=%.2f p95=%.2f p99=%.2f max=%.1f >50ms=%d draws=%.0f" % [ph, a.size(),
			pct(a, 0.5), pct(a, 0.95), pct(a, 0.99), pct(a, 1.0), out["phases"][ph]["over50"], out["phases"][ph]["draws"]])
	for h in _hitches.slice(0, 60):
		print("BENCH hitch t=%.1f %.0f ms [%s] %s" % [h[0], h[1], h[2], ", ".join(h[3])])
	if not _mem_track.is_empty():
		print("BENCH mem start %d MB nodes %d → end %d MB nodes %d" % [_mem_track[0][1], _mem_track[0][2], _mem_track[-1][1], _mem_track[-1][2]])
	return out
