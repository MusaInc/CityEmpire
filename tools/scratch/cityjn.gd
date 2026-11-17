extends SceneTree
func _initialize() -> void:
	_go.call_deferred()
func _go() -> void:
	SkyportIsland.enabled = true
	Landforms.enabled = true
	var layout := CityLayout.new().generate()
	for L: CityLayout in [layout, layout.mainland]:
		var tag := "isl" if L == layout else "wb"
		var ends: Array = L.roads.road_ends
		var n := 0
		for i in range(0, ends.size(), maxi(1, ends.size() / 7)):
			var e: Array = ends[i]
			var r: Dictionary = L.roads.roads[int(e[0])]
			var p: Vector2 = e[2]
			var d: Vector2 = e[3]
			if float(e[4]) < 1.0:
				continue
			print("CJ %s %s %.1f,%.1f dir %.3f,%.3f w=%.0f kind=%s" % [tag, r.get("name", "?"), p.x, p.y, d.x, d.y, float(r["w"]), r["kind"]])
			n += 1
		for rb in L.roads.roundabouts:
			print("RB %s %.1f,%.1f r=%.0f" % [tag, (rb["c"] as Vector2).x, (rb["c"] as Vector2).y, float(rb["r"])])
			break
	quit()
