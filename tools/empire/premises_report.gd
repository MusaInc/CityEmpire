extends SceneTree
## Lists the shop units and wholesalers placed in the city (both landmasses).
##   godot --headless -s res://tools/empire/premises_report.gd

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var L := CityLayout.new().generate()
	print("layout %d ms" % (Time.get_ticks_msec() - t0))
	for P: Premises in [L.mainland.premises, L.premises]:
		for u in P.units:
			print("%-10s %-22s %-28s %-16s %5.0f m²  rent £%4.0f  price £%6.0f  door (%.0f, %.1f, %.0f)" % [u["kind"], u["id"],
				u.get("shop_name", u["name"]), u["district"], u["size"], u["rent"], u["price"], u["pos"][0], u["pos"][1], u["pos"][2]])
	quit()
