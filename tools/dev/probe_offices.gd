extends SceneTree
func _init():
	var L: CityLayout = CityLayout.new().generate()
	var n := 0
	for u in L.premises.units:
		if u["kind"] in ["office", "hq"]:
			n += 1
			print("OFF ", u["id"], " ", u["name"], " ", u["district"], " rent ", u["rent"])
	print("TOTAL units ", L.premises.units.size() + L.mainland.premises.units.size(), " offices ", n)
	quit()
