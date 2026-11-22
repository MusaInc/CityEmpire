extends RefCounted
## The shop floor with people on it: a busy convenience shop with a cashier
## and a stacker, shoppers arriving in a rush. They come in through the door
## one at a time, never walk through each other (or you), queue, pay at the
## till, and every sale shows up in the stock and the takings.


func _shop_unit() -> Dictionary:
	var L := CityLayout.new().generate()
	for P in [L.mainland.premises, L.premises]:
		for u in P.units:
			if u["kind"] == "shop":
				return u
	return {}


func test_busy_shop_floor(t) -> void:
	var runner: SceneTree = t
	var u := _shop_unit()
	var e := Empire.new()
	e.new_game(5)
	e.personal_cash = 8000.0
	var b := e.rent_premises(Premises.record(u))
	e.transfer_to_company(3000.0)
	var order := {"crisps": 2, "choc_bar": 2, "cola": 2, "water": 2, "milk": 2, "bread": 2, "gummies": 1, "energy": 1}
	e.buy_wholesale("w1", order)
	var pal: Stock = e.pallets["w1"]
	for pid in order:
		Stock.transfer(pal, b.backroom, pid, pal.qty(pid))
	e.restock_from_backroom(b, 140)
	for role in ["cashier", "stocker"]:
		e.hire(b, e.candidates.filter(func(x): return x["role"] == role)[0])
	b.open = true
	e.minute = 11.0 * 60.0
	var si := ShopInterior.new()
	si.setup(u, b)
	var centre := (si.door.x + si.door.y) * 0.5
	var entrance := AABB(Vector3(centre - 0.61, 0.45, -3.45), Vector3(1.22, 0.94, 4.5))
	var obstructions := 0
	for fixture: CollisionShape3D in si._col.get_children():
		var bounds := (fixture.shape as BoxShape3D).size
		if AABB(fixture.position - bounds * 0.5, bounds).intersects(entrance):
			obstructions += 1
	t.check(obstructions == 0, "the doorway and approach stay clear of interior and street fixtures")
	t.check(-si.pile_pos.z > si.D - ShopInterior.BACKROOM, "delivery overflow stages behind the shop floor")
	var root := Node3D.new()
	runner.root.add_child(root)
	root.add_child(si)
	var fl := ShopFloor.new()
	fl.minutes_per_second = 0.5
	root.add_child(fl)
	fl.setup(e, b, si)
	# You, standing in the middle of the shop floor.
	var cells := si.walk.keys()
	var mid := si.cell_pos(cells[cells.size() / 2])
	fl.hero_at = mid
	var shelf0 := b.shelf_units()
	var rev0 := float(b.today["revenue"])
	b.pending_arrivals = 9
	var overlaps := 0
	var through_you := 0
	var cust_frames := 0
	var samples := 0
	var max_in := 0
	var spawned_at_once := 0
	var last_n := 0
	for f in 60 * 75:
		await runner.process_frame
		var ps: Array = []
		for c in fl.customers:
			ps.append((c["p"] as ShopPerson).position)
		for k in fl.staff_people:
			ps.append((fl.staff_people[k]["p"] as ShopPerson).position)
		if fl.customers.size() - last_n > 1:
			spawned_at_once += 1
		last_n = fl.customers.size()
		max_in = maxi(max_in, fl.customers.size())
		for i in ps.size():
			for j in range(i + 1, ps.size()):
				samples += 1
				if Vector2(ps[i].x - ps[j].x, ps[i].z - ps[j].z).length() < 0.3:
					overlaps += 1
		for c in fl.customers:
			cust_frames += 1
			var q: Vector3 = (c["p"] as ShopPerson).position
			if Vector2(q.x - mid.x, q.z - mid.z).length() < 0.3:
				through_you += 1
		if b.pending_arrivals == 0 and fl.customers.is_empty() and f > 600:
			break
	for c in fl.customers:
		t.note("still inside: %s at %s (path %d left)" % [c["state"], (c["p"] as ShopPerson).position, (c["p"] as ShopPerson).path.size()])
	t.note("people inside at most %d; overlapping pairs %d of %d samples; sales %d; shelves %d → %d units" % [
		max_in, overlaps, samples, int(b.today["served"]), shelf0, b.shelf_units()])
	t.check(spawned_at_once == 0, "shoppers come through the door one at a time")
	t.check(samples > 0 and float(overlaps) / float(samples) < 0.002, "people don't walk through each other")
	# (In a one-person aisle they wait, then squeeze past with an "excuse me".)
	t.check(float(through_you) / maxf(cust_frames, 1.0) < 0.01, "people give way to you (%d of %d frames at your spot)" % [through_you, cust_frames])
	t.check(int(b.today["served"]) >= 4, "the cashier serves the queue (%d sales)" % int(b.today["served"]))
	t.check(float(b.today["revenue"]) > rev0, "sales are in the takings")
	t.check(b.shelf_units() < shelf0 + 200, "the shelves give up what was sold")
	t.check(fl.customers.size() <= 1, "everyone gets served or leaves (%d still inside)" % fl.customers.size())
	root.queue_free()
