extends SceneTree
## Streetlight facing audit: for every streetlight in the generated city,
## is its lantern (CityWorld.LAMP_HEAD, 1.45 m out on the bracket) over the
## road side - nearer a traffic lane than the column is? Lists the ones that
## face away from the road (lantern over the pavement or a building) and a
## count per placement height band so the source routine can be found.
##   godot --headless -s res://tools/lamp_audit.gd


func _initialize() -> void:
	var L := CityLayout.new().generate()
	var net := RoadNet.new().build(L)
	var total := 0
	var counts := {"toward": 0, "sideways": 0, "backwards": 0, "no_road": 0}
	var by_y := {}
	var samples: Array = []
	for p in L.props:
		if String(p[0]) != "streetlight":
			continue
		total += 1
		var xf: Transform3D = p[1]
		var np := net.nearest(xf.origin, Vector3.ZERO, 30.0)
		if np.is_empty():
			counts["no_road"] += 1
			continue
		var lane: Vector3 = np["pos"]
		var to_lane := Vector2(lane.x - xf.origin.x, lane.z - xf.origin.z)
		if to_lane.length() < 0.5:
			continue
		var arm3 := xf.basis * Vector3(0, 0, -1)
		var arm := Vector2(arm3.x, arm3.z).normalized()
		var d := arm.dot(to_lane.normalized())
		var cls := "toward" if d > 0.6 else ("backwards" if d < -0.4 else "sideways")
		counts[cls] += 1
		if cls != "toward":
			var band := "y%d" % int(round(xf.origin.y))
			by_y[cls + " " + band] = int(by_y.get(cls + " " + band, 0)) + 1
			if samples.size() < 20:
				samples.append("  %s pole (%.1f, %.1f, %.1f) yaw %.0f, lane %.1f m away, arm.lane %.2f" % [cls, xf.origin.x,
					xf.origin.y, xf.origin.z, rad_to_deg(xf.basis.get_euler().y), to_lane.length(), d])
	print("LAMPS %d streetlights: %s" % [total, JSON.stringify(counts)])
	for s in samples:
		print(s)
	quit()
