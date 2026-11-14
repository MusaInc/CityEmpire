extends SceneTree
## Balance probe: one fully staffed shop (cashier + stocker + manager) per
## district, stocked with every shelf/fridge product, run for N days with the
## manager re-ordering. Prints daily profit so tuning changes can be judged.
##   godot --headless -s res://tools/balance_sim.gd -- [days]

func _init() -> void:
	var days := 20
	var nfirms := 4
	var type := "convenience"
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			days = int(a)
		elif a.begins_with("type="):
			type = a.get_slice("=", 1)
		elif a.begins_with("firms="):
			nfirms = int(a.get_slice("=", 1))
	for dk in EmpireData.economy()["districts"]:
		var e := Empire.new()
		e.new_game(3)
		e.personal_cash = 20000.0
		var k := float(EmpireData.district(dk).get("rent_k", 1.0))
		var rent := roundf(120.0 * 0.22 * k)
		var prem := {"id": "u_" + dk, "name": dk, "shop_name": dk, "district": dk, "island": dk.split(":")[0],
			"size": 120.0, "rent": rent, "price": rent * 240.0}
		prem["pos"] = [0.0, 0.0, 0.0]
		var b := e.rent_premises(prem, type)
		# A typical high street: independents trading around it.
		for i in nfirms:
			e.firms.append({"unit": "f%d" % i, "name": "F", "owner": "O", "district": dk, "pos": [60.0 + i * 10.0, 0.0, 0.0],
				"rent": rent, "price": rent * 240.0, "rep": 50.0, "since": 0, "colour": "#2f7d4a", "for_sale": false, "listed": 0})
		e.transfer_to_company(6000.0)
		var order := {}
		var cats: Array = b.type_def().get("categories", [])
		for pid in EmpireData.product_ids():
			var pp := EmpireData.product(pid)
			if String(pp["cat"]) in cats and int(b.fixtures.get(String(pp["fixture"]), 0)) > 0:
				order[pid] = 1
		e.buy_wholesale("w1", order)
		var pal: Stock = e.pallets["w1"]
		for pid in order:
			Stock.transfer(pal, b.backroom, pid, pal.qty(pid))
		e.restock_from_backroom(b, 1000)
		for role in ["cashier", "stocker", "manager"]:
			var c: Array = e.candidates.filter(func(x): return x["role"] == role)
			e.hire(b, c[0])
		var tot := 0.0
		var line := ""
		for d in days:
			e.advance(1440.0)
			var r: Dictionary = b.history[-1]
			tot += float(r["profit"])
			if d == days - 1:
				pass
				line += " d%d:%.0f(rev %.0f cust %d rep %.0f)" % [d + 1, r["profit"], r["revenue"], r["customers"], r["reputation"]]
		print("%-18s rent %4.0f  total %7.0f  avg/day %6.0f |%s" % [dk, rent, tot, tot / days, line])
	quit()
