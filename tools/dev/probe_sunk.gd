extends SceneTree
## Faces whose painted ground-floor shopfront (building.gdshader: uv.y < 4.6
## from the tier's foot) is mostly below the street in front of it.
func _init():
	var L: CityLayout = CityLayout.new().generate()
	var n := 0
	var shown := 0
	for lay: CityLayout in [L.mainland, L]:
		for b in lay.buildings:
			if b["kind"] != "normal" or b.has("shape"):
				continue
			if not BuildingMesher.ground_shops(b):
				continue
			var t: Array = b["tiers"][0]
			var base := BuildingMesher.base_of(b)
			for k in 4:
				var f := BuildingMesher._face(t, k)
				var mid: Vector3 = CityLayout.bxf(b) * BuildingMesher._fpt(f, float(f[3]) * 0.5, 0.0, base)
				var out: Vector3 = (CityLayout.bxf(b).basis * (f[2] as Vector3)).normalized()
				var p := mid + out * 2.5
				var g := lay.ground_y(p.x, p.z)
				var sunk := g - base
				if sunk > 2.0:
					n += 1
					if shown < 30:
						shown += 1
						var has_unit: bool = b.has("apt") and (b["apt"] as Dictionary).get("ground", false)
						print("SUNK %.1f m  at (%.0f, %.0f) face %d  base %.1f street %.1f  unit=%s" % [sunk, p.x, p.z, k, base, g, has_unit])
	print("SUNK faces: ", n)
	quit()
