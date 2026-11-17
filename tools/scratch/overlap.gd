extends SceneTree
func _initialize() -> void:
	_go.call_deferred()
func _go() -> void:
	SkyportIsland.enabled = true
	Landforms.enabled = true
	var layout := CityLayout.new().generate()
	for L: CityLayout in [layout, layout.mainland]:
		var bad := 0
		var near_j := 0
		var shown := 0
		for b: Dictionary in L.buildings:
			if String(b.get("kind", "normal")) in ["structure", "bridge", "frame"]:
				continue
			var xf := CityLayout.bxf(b)
			var t: Array = b["tiers"][0]
			var hits := 0
			var n := 0
			var x := float(t[0]) + 0.5
			while x < float(t[2]):
				var z := float(t[1]) + 0.5
				while z < float(t[3]):
					var w := xf * Vector3(x, 0, z)
					n += 1
					if L.roads.on_road(Vector2(w.x, w.z)):
						hits += 1
					z += 2.0
				x += 2.0
			if hits > 0:
				bad += 1
				if shown < 6:
					var c := xf * Vector3((float(t[0]) + float(t[2])) * 0.5, 0, (float(t[1]) + float(t[3])) * 0.5)
					print("  overlap %s: %d/%d samples on road, kind=%s at %s" % ["main" if L == layout else "westbank", hits, n, b.get("kind", "?"), c])
					shown += 1
		print("OV %s: %d of %d buildings touch a carriageway" % ["island" if L == layout else "mainland", bad, L.buildings.size()])
	quit()
