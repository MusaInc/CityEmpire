extends SceneTree
## Ground height under a shop unit vs its floor (base): terrain poking through?
func _initialize() -> void:
	var L := CityLayout.new().generate()
	for P: Premises in [L.mainland.premises, L.premises]:
		var lay: CityLayout = L.mainland if P == L.mainland.premises else L
		for u in P.units:
			var xf := Premises.room_xf(u)
			var sz := Premises.room_size(u)
			var hi := -INF
			var lo := INF
			for fx in 5:
				for fz in 5:
					var p := xf * Vector3(sz.x * (fx + 0.5) / 5.0, 0, -sz.z * (fz + 0.5) / 5.0)
					var g := lay.ground_y(p.x, p.z)
					hi = maxf(hi, g - p.y)
					lo = minf(lo, g - p.y)
			print("%-22s ground-floor  min %+.2f  max %+.2f" % [u["id"], lo, hi])
	quit()
