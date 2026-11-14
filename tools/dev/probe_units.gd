extends SceneTree
## Every commercial unit: floor vs the street, duplicates, overlaps.
func _init():
	var L: CityLayout = CityLayout.new().generate()
	var all: Array = []
	for P in [L.mainland.premises if L.mainland else null, L.premises]:
		if P:
			all.append_array(P.units)
	var ids := {}
	var bad := 0
	for u in all:
		var id: String = u["id"]
		if ids.has(id):
			print("DUP id ", id)
		ids[id] = true
		var door := Premises.door_point(u)
		var out := Premises.outward(u)
		var f := door + out * 2.0
		var gy := L.ground_y(f.x, f.z)
		var xf := Premises.room_xf(u)
		var sz := Premises.room_size(u)
		var lo := INF
		var hi := -INF
		for fx in 5:
			for fz in 5:
				var p := xf * Vector3(sz.x * (fx + 0.5) / 5.0, 0, -sz.z * (fz + 0.5) / 5.0)
				var g := L.ground_y(p.x, p.z)
				lo = minf(lo, g - p.y)
				hi = maxf(hi, g - p.y)
		var bc := BuildingMesher.base_course(u["b"])
		var t0: Array = u["b"]["tiers"][0]
		var flag := absf(gy - door.y) > 0.6 or hi > 0.5 or lo < -1.5
		if flag:
			bad += 1
		if flag or OS.get_cmdline_user_args().has("all"):
			print("%s %s door.y=%.2f street=%.2f ground-floor[min %.2f max %.2f] base_course=%s tier y=[%.2f %.2f] h=%.1f" % [
				"BAD " if flag else "ok  ", id, door.y, gy, lo, hi, str(bc.end.y) if bc.has_volume() else "-", float(t0[4]), float(t0[5]), sz.y])
	# Footprint overlaps between units.
	for i in all.size():
		for j in range(i + 1, all.size()):
			var a: Dictionary = all[i]
			var b: Dictionary = all[j]
			if a["b"] == b["b"] or Vector2(a["pos"][0], a["pos"][2]).distance_to(Vector2(b["pos"][0], b["pos"][2])) < 8.0:
				print("OVERLAP ", a["id"], " ", b["id"])
	print("UNITS ", all.size(), " flagged ", bad)
	quit()
