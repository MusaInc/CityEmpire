class_name Prof
extends RefCounted
## Tiny section profiler for benchmarks: Prof.begin("x") ... Prof.end("x");
## Prof.report() prints total ms per section. Off unless enabled.
static var enabled := false
static var _t := {}
static var _acc := {}
static var _n := {}
static var _max := {}


static func begin(k: String) -> void:
	if enabled:
		_t[k] = Time.get_ticks_usec()


static func end(k: String) -> void:
	if enabled and _t.has(k):
		var elapsed: int = Time.get_ticks_usec() - _t[k]
		_acc[k] = _acc.get(k, 0) + elapsed
		_max[k] = maxi(_max.get(k, 0), elapsed)
		_n[k] = _n.get(k, 0) + 1


static var _frame_acc := 0
static var _last_total := 0


## Profiled script time since the last call (ms).
static func frame_ms() -> float:
	var total := 0
	for k in _acc:
		if k != "flow_field" and k != "nearest" and k != "driver" and k != "integrate":
			total += _acc[k]
	var d := total - _last_total
	_last_total = total
	return d / 1000.0


static func report(_frames: int) -> void:
	var keys := _acc.keys()
	keys.sort_custom(func(a, b): return _acc[a] > _acc[b])
	for k in keys:
		print("PROF %-22s total=%.3f ms calls=%d mean=%.3f ms peak=%.3f ms" % [
			k, _acc[k] / 1000.0, _n[k], _acc[k] / 1000.0 / maxf(_n[k], 1), _max[k] / 1000.0])
