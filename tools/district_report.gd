extends SceneTree
## Skyline by quarter (CityLayout._district_character): buildings, how many
## were lowered, mean/max top per district, and roof props left floating
## (a prop over a roof footprint but more than 1 m above it).
##   godot --headless -s res://tools/district_report.gd
func _init() -> void:
	SkyportIsland.enabled = true
	Landforms.enabled = true
	var l := CityLayout.new().generate()
	var by := {}
	for b: Dictionary in l.buildings:
		if b["kind"] != "normal":
			continue
		var c := CityLayout.base_center(b)
		var d := l.district(c.x, c.y)
		var top := float(b["tiers"][-1][5]) - BuildingMesher.base_of(b)
		if not by.has(d):
			by[d] = [0, 0.0, 0.0]
		by[d][0] += 1
		by[d][1] += top
		by[d][2] = maxf(by[d][2], top)
	for d in by:
		print("%-11s n=%4d mean=%5.1f max=%5.1f" % [d, by[d][0], by[d][1] / by[d][0], by[d][2]])
	print("lowered=%d" % l.district_lowered)
	var floating := 0
	for pr in l.props:
		if not String(pr[0]) in ["roof_hut", "ac_unit", "water_tower", "antenna", "cooling_tower"]:
			continue
		var o: Vector3 = (pr[1] as Transform3D).origin
		var best := INF
		for b: Dictionary in l.buildings:
			if b["kind"] != "normal" or not l.inside(b, o + Vector3.DOWN * 0.3, 0.6, 2.0):
				continue
			best = minf(best, absf(o.y - BuildingMesher.roof_y(b)))
		if best > 1.0 and best < INF:
			floating += 1
	print("roof props off their roof: %d" % floating)
	quit()
