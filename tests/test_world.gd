extends RefCounted
## The business layer on the shared city: premises placement on both
## islands, interiors that can be walked (every shelf, till and the stock
## room reachable from the street, even fully upgraded), doorways clear of
## the building's collision, stable ids.

static var _layout: CityLayout


func _units() -> Array:
	if _layout == null:
		_layout = CityLayout.new().generate()
	var out: Array = []
	for P in [_layout.mainland.premises, _layout.premises]:
		out.append_array(P.units)
	return out


func test_premises_on_both_islands(t) -> void:
	var units := _units()
	var west := units.filter(func(u): return u["island"] == "west" and u["kind"] == "shop")
	var east := units.filter(func(u): return u["island"] == "east" and u["kind"] == "shop")
	var whole := units.filter(func(u): return u["kind"] == "wholesale")
	t.check(west.size() >= 6, "Westbank has shops to let (%d)" % west.size())
	t.check(east.size() >= 10, "the Commercial Island has shops to let (%d)" % east.size())
	t.check(whole.size() == 2 and whole[0]["island"] != whole[1]["island"], "a wholesaler on each island")
	var ids := {}
	for u in units:
		ids[u["id"]] = true
	t.check(ids.size() == units.size(), "unit ids are unique")
	var west_rent := 0.0
	var east_rent := 0.0
	for u in west:
		west_rent += float(u["rent"]) / west.size()
	for u in east:
		east_rent += float(u["rent"]) / east.size()
	t.check(east_rent > west_rent * 1.5, "the Commercial Island costs more (avg rent £%.0f vs £%.0f)" % [east_rent, west_rent])
	var again := CityLayout.new().generate()
	var ids2: Array = []
	for P in [again.mainland.premises, again.premises]:
		for u in P.units:
			ids2.append(u["id"])
	t.check(ids2.size() == units.size() and ids.has(ids2[0]) and ids.has(ids2[-1]), "placement is deterministic (saves refer to ids)")


func test_doorways_are_clear(t) -> void:
	var blocked := []
	for u in _units():
		var boxes := BuildingMesher.collision_boxes(u["b"])
		var xf := CityLayout.bxf(u["b"])
		var door := Premises.door_point(u)
		var out := Premises.outward(u)
		for dd: float in [-1.5, -0.5, 0.0, 0.6]:
			var p := door + out * dd + Vector3.UP * 1.0
			var q := xf.affine_inverse() * p
			for bx: AABB in boxes:
				if bx.has_point(q):
					blocked.append("%s at %.1f" % [u["id"], dd])
					break
	t.check(blocked.is_empty(), "no building collision across any doorway %s" % [blocked.slice(0, 5)])


func test_interiors_walkable_even_fully_upgraded(t) -> void:
	var bad: Array = []
	var shops := 0
	for u in _units():
		var b: Business = null
		if u["kind"] == "shop":
			# Every kind of shop, spread over the units.
			var kinds := ["convenience", "clothing", "cafe", "takeaway", "bakery", "phones"]
			b = Business.new("t", kinds[shops % kinds.size()])
			b.setup_new(Premises.record(u), 1)
			for up in b.type_def().get("upgrades", []):
				b.apply_upgrade(up)
			shops += 1
		var si := ShopInterior.new()
		si.setup(u, b)
		var from := si.door_out
		var goals: Array = []
		if b:
			var want := 0
			for k in Business.FIXTURE_KINDS:
				want += int(b.fixtures.get(k, 0))
			if si.placed.size() < want:
				bad.append("%s fits %d of %d fixtures" % [u["id"], si.placed.size(), want])
			for i in si.slot_pick:
				goals.append(["slot %d" % i, si.slot_pick[i]])
			for i in si.till_customer.size():
				goals.append(["till %d" % i, si.till_customer[i]])
				goals.append(["behind till %d" % i, si.till_staff[i]])
			goals.append(["stockroom", si.rack_pos])
			goals.append(["office", si.office_pos])
		elif u["kind"] == "hq":
			goals.append(["reception", si.spots.filter(func(s): return s["kind"] == "hq_desk")[0]["pos"]])
		else:
			goals.append(["trade counter", si.spots.filter(func(s): return s["kind"] == "trade")[0]["pos"]])
		for g in goals:
			var path := si.path(from, g[1])
			if path.is_empty() or (path[path.size() - 1] as Vector3).distance_to(g[1]) > 0.3:
				bad.append("%s: no way to %s" % [u["id"], g[0]])
		si.free()
	t.check(shops > 10, "checked %d shops" % shops)
	t.check(bad.is_empty(), "every fixture, till, stockroom and counter is reachable: %s" % [bad.slice(0, 6)])


func test_goods_shown_match_stock(t) -> void:
	var u: Dictionary = _units().filter(func(x): return x["kind"] == "shop")[0]
	var b := Business.new("t", "convenience")
	b.setup_new(Premises.record(u), 1)
	var src := Stock.new()
	src.create("cola", 24)
	src.create("crisps", 30)
	b.shelve(src, b.slot_for("cola"), "cola", 24)
	b.shelve(src, b.slot_for("crisps"), "crisps", 15)
	var si := ShopInterior.new()
	si.setup(u, b)
	var root := Node3D.new()
	root.add_child(si)
	si.refresh_goods()
	var items := 0
	for c in si._goods.get_children():
		if c is MultiMeshInstance3D:
			items += (c as MultiMeshInstance3D).multimesh.instance_count
	t.check(items > 10, "goods drawn on the shelves (%d packs)" % items)
	var tags := 0
	for lab in si._labels.get_children():
		if (lab as Label3D).text.contains("£"):
			tags += 1
	t.check(tags == 2, "two price tags show prices (%d)" % tags)
	root.free()


## Shops are glazed wall to wall (the interior shows from the street); the
## opening stays centred, so the door point – and every unit's id – holds.
func test_shopfronts_glazed_wall_to_wall(t) -> void:
	var narrow := []
	var moved := []
	for u in _units():
		if u["kind"] != "shop":
			continue
		var w := float(u["a1"]) - float(u["a0"])
		if float(u["oa1"]) - float(u["oa0"]) < w - 0.81:
			narrow.append(u["id"])
		var d := Premises.door_point(u)
		if Vector2(d.x, d.z).distance_to(Vector2(float(u["pos"][0]), float(u["pos"][2]))) > 0.01:
			moved.append(u["id"])
	t.check(narrow.is_empty(), "every shop glazed nearly wall to wall %s" % [narrow.slice(0, 5)])
	t.check(moved.is_empty(), "door points (and ids) unchanged %s" % [moved.slice(0, 5)])


## A building on a slope stands on a dressed-stone base course. It used to
## be drawn as wall, so the facade shader painted windows and shop glass on
## it: a strip of half-buried fake shops along the foot of the street.
func test_base_course_is_stone_not_windows(t) -> void:
	if _layout == null:
		_layout = CityLayout.new().generate()
	var checked := 0
	var painted := 0
	var stone := 0
	for b in _layout.buildings:
		if checked >= 40 or not BuildingMesher.base_course(b).has_volume() or BuildingMesher.shaped(b):
			continue
		checked += 1
		var m := BuildingMesher.new()
		m.add_building(b, true)
		var a := m.arrays()
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var base := BuildingMesher.base_of(b)
		for i in verts.size():
			var kind := roundf(cols[i].a * 8.0)
			if kind == BuildingMesher.KIND_STONE:
				stone += 1
			elif kind == BuildingMesher.KIND_WALL and verts[i].y < base - 0.05:
				painted += 1
	t.check(checked > 5, "buildings on slopes found (%d)" % checked)
	t.check(stone > 0, "their base courses are stone (%d verts)" % stone)
	t.check(painted == 0, "no facade (window-painted) wall below a lot's level (%d verts)" % painted)
