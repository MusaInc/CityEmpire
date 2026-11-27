extends RefCounted
## The splash keeps animating because the heavy, node-free parts of loading
## run on worker threads (2026-11-27). They must build the SAME city as the
## main thread: saves hold position-based ids.


func _sig(L: CityLayout) -> String:
	var h: Array = []
	for b in L.buildings:
		h.append(str(b.get("pos", b.get("center", Vector2.ZERO))))
	var s := "%d|%d|%s" % [L.buildings.size(), L.props.size(), str(h).md5_text()]
	if L.premises:
		s += "|u%d" % L.premises.units.size()
	if L.mainland:
		s += " / M %d|%d|%s" % [L.mainland.buildings.size(), L.mainland.props.size(), str(L.mainland.buildings.map(func(b): return str(b.get("pos", Vector2.ZERO)))).md5_text()]
	return s


func test_layout_on_a_worker_thread_matches_main_thread(t) -> void:
	SkyportIsland.enabled = true
	Landforms.enabled = true
	var t0 := Time.get_ticks_msec()
	var a := CityLayout.new().generate()
	var t1 := Time.get_ticks_msec()
	var out := [null]
	var tid := WorkerThreadPool.add_task(func(): out[0] = CityLayout.new().generate())
	WorkerThreadPool.wait_for_task_completion(tid)
	var t2 := Time.get_ticks_msec()
	print("    layout: main %d ms, worker %d ms" % [t1 - t0, t2 - t1])
	t.check(out[0] != null, "the worker built a layout")
	if out[0] != null:
		var sa := _sig(a)
		var sb := _sig(out[0])
		t.check(sa == sb, "same city on both threads (%s vs %s)" % [sa, sb])
