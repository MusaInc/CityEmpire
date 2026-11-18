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
		elif u["kind"] in ["hq", "office"]:
			goals.append(["reception", si.spots.filter(func(s): return s["kind"] in ["hq_desk", "office_desk"])[0]["pos"]])
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


## No building stands sunk into the ground: every face's floor is at most a
## kerb or two below the street in front of it. (Buildings added on the bare
## squares and round the set pieces were laid out at height 0 and never
## lifted: on Westbank's hillside their shopfronts showed just above the
## pavement – "shops 80% underground" – and five on a Georgian terrace were
## buried whole.)
func test_no_building_is_sunk_into_the_ground(t) -> void:
	if _layout == null:
		_layout = CityLayout.new().generate()
	var sunk: Array = []
	var n := 0
	for lay: CityLayout in [_layout.mainland, _layout]:
		for b in lay.buildings:
			if b["kind"] != "normal" or b.has("shape"):
				continue
			var tiers: Array = b["tiers"]
			var t0: Array = tiers[0]
			var base := float(t0[4])
			for k in 4:
				var f := BuildingMesher._face(t0, k)
				var mid: Vector3 = CityLayout.bxf(b) * BuildingMesher._fpt(f, float(f[3]) * 0.5, 0.0, base)
				var out: Vector3 = (CityLayout.bxf(b).basis * (f[2] as Vector3)).normalized()
				var p := mid + out * 2.5
				n += 1
				var g := lay.ground_y(p.x, p.z)
				if g - base > 2.0:
					sunk.append("(%.0f, %.0f) %.1f m" % [p.x, p.z, g - base])
	t.check(sunk.is_empty(), "%d building faces checked, none sunk more than 2 m (%d: %s)" % [n, sunk.size(), str(sunk.slice(0, 4))])


## The far city (FarCity): every land chunk of both cities has a coarse
## ground and its buildings' massing, small enough to keep resident, and the
## dock basins stay water.
func test_far_city_covers_the_islands(t) -> void:
	if _layout == null:
		_layout = CityLayout.new().generate()
	var C := CityWorld.CHUNK
	var worst := 0
	var empty := 0
	var land_chunks := 0
	for L: CityLayout in [_layout, _layout.mainland]:
		if L == null:
			continue
		var bb := L.island
		var x := floorf(bb.position.x / C) * C
		while x < bb.end.x:
			var z := floorf(bb.position.y / C) * C
			while z < bb.end.y:
				var r := Rect2(x, z, C, C)
				var c := r.get_center()
				if Geometry2D.is_point_in_polygon(c, L.coast) and not L.is_water(Vector3(c.x, 0.0, c.y)):
					land_chunks += 1
					var m := BuildingMesher.new()
					m.add_far_ground(L, r)
					if m.is_empty():
						empty += 1
					else:
						var a := m.arrays()
						var idx = a[Mesh.ARRAY_INDEX]
						worst = maxi(worst, (idx.size() if idx != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3)
				z += C
			x += C
	t.check(land_chunks > 20 and empty == 0, "%d land chunks all have far ground (%d empty)" % [land_chunks, empty])
	t.check(worst < 6000, "far ground stays light: worst chunk %d triangles" % worst)


## Coastlines must be simple polygons: a self-crossing outline triangulates
## to nothing, and the island silently loses its ground and collision.
func test_coastlines_triangulate(t) -> void:
	if _layout == null:
		_layout = CityLayout.new().generate()
	var was_s := SkyportIsland.enabled
	var was_l := Landforms.enabled
	SkyportIsland.enabled = true
	Landforms.enabled = true
	var o := SkyportIsland.outline()
	t.check(Geometry2D.triangulate_polygon(o).size() > 0, "Skyport's outline triangulates (%d points)" % o.size())
	for f: Dictionary in Landforms.forms(_layout):
		t.check(Geometry2D.triangulate_polygon(f["poly"]).size() > 0, "landform %s triangulates" % f["name"])
	# Every bridge lands on the island and starts on its city's coast road.
	for B: Dictionary in SkyportIsland.plan(_layout)["bridges"]:
		var F: Vector3 = B["F"]
		t.check(SkyportIsland.contains(F.x + (B["u"] as Vector3).x * 3.0, F.z + (B["u"] as Vector3).z * 3.0), "%s lands on the island" % B["name"])
		t.check(float(B["L"]) > 150.0 and float(B["L"]) < 700.0, "%s spans %.0f m" % [B["name"], float(B["L"])])
	SkyportIsland.enabled = was_s
	Landforms.enabled = was_l


## The baked seabed (tools/bake_seabed.gd) matches today's coastlines –
## land where there's land, water where there's water – so a coast edit
## without a re-bake shows up here; and it has shallows by the beaches and
## deep water between the islands.
func test_seabed_matches_the_coasts(t) -> void:
	if _layout == null:
		_layout = CityLayout.new().generate()
	var was_s := SkyportIsland.enabled
	var was_l := Landforms.enabled
	SkyportIsland.enabled = true
	Landforms.enabled = true
	SkyportIsland.plan(_layout)
	Landforms.forms(_layout)
	var tex: Texture2D = load(CityWorld.SEABED)
	t.check(tex != null, "the seabed is baked (%s)" % CityWorld.SEABED)
	if tex == null:
		return
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var R := Rect2(-2400.0, -1800.0, 4800.0, 4800.0)
	var depth := func(x: float, z: float) -> float:
		var px := clampi(int((x - R.position.x) / R.size.x * img.get_width()), 0, img.get_width() - 1)
		var pz := clampi(int((z - R.position.y) / R.size.y * img.get_height()), 0, img.get_height() - 1)
		return img.get_pixel(px, pz).r * 32.0
	var bad := 0
	var n := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 3000:
		var x := rng.randf_range(-1300.0, 1100.0)
		var z := rng.randf_range(-800.0, 2300.0)
		if Hinterland.height_at(x, z) > Hinterland.SEA_Y + 0.2:
			continue
		var wet := _layout.is_water(Vector3(x, 0.0, z))
		var d: float = depth.call(x, z)
		# (Within a texel of a shore either answer is fine.)
		if wet == (d < 0.05):
			var near_shore := false
			for o: Vector2 in [Vector2(8, 0), Vector2(-8, 0), Vector2(0, 8), Vector2(0, -8)]:
				if _layout.is_water(Vector3(x + o.x, 0.0, z + o.y)) != wet:
					near_shore = true
			if not near_shore:
				bad += 1
		n += 1
	t.check(bad <= n / 200, "the seabed matches the coasts (%d of %d samples disagree: re-run tools/bake_seabed.gd)" % [bad, n])
	# A beach's shallows, and the channel between the islands.
	var beach := Vector3(-498.0, 0.0, 948.0)   # (16 m off the north cove's beach)
	var mid_ch := Vector3(-200.0, 0.0, 780.0)
	t.check(float(depth.call(beach.x, beach.z)) < 3.0, "shallow off Skyport's north cove beach (%.1f m)" % float(depth.call(beach.x, beach.z)))
	t.check(float(depth.call(mid_ch.x, mid_ch.z)) > 6.0, "deep in the channel off the strait (%.1f m)" % float(depth.call(mid_ch.x, mid_ch.z)))
	SkyportIsland.enabled = was_s
	Landforms.enabled = was_l


## Every coast is finished (2026-11-18 coast overhaul): both city islands
## have a sea wall and shore all round (Westbank had none – its whole coast
## was skipped as if it were the strait quay, the esplanade ending in mid-air
## over the sea floor), every shore row runs down through the sea surface
## (-1.6: beaches built for a waterline at 0 stood 40 m of dry sand out into
## coves), rows never fold back or reach past half the open water in front
## (facing beaches crossed into sand ridges), headlands take over the city's
## shore where they join it and meet it on one row, and the coast kit
## (lookouts, jetties, viewpoints) is built.
func test_every_coast_has_a_finished_shore(t) -> void:
	var was_s := SkyportIsland.enabled
	var was_l := Landforms.enabled
	SkyportIsland.enabled = true
	Landforms.enabled = true
	var L0 := CityLayout.new().generate()
	SkyportIsland.plan(L0)
	Landforms._built = false
	Landforms._forms = []
	Landforms.forms(L0)
	for L: CityLayout in [L0, L0.mainland]:
		var nm := "Westbank" if L.is_mainland else "the Commercial Island"
		L.shore_cache = []
		var sr := BuildingMesher.shore_rows(L)
		var smp: Array = sr[0]
		var rows: Array = sr[1]
		var covered: Array = sr[3]
		t.check(smp.size() > 300, "%s has a shore all round (%d samples)" % [nm, smp.size()])
		var dry := 0
		var folds := 0
		var inland := 0
		var under := 0
		var aprons := 0
		for i in smp.size():
			var row: Array = rows[i]
			var p: Vector2 = smp[i][0]
			var ext := Vector2((row[-1] as Vector3).x - p.x, (row[-1] as Vector3).z - p.y).length()
			if ext < 0.5:
				continue   # (the docks' plain quay)
			aprons += 1
			if covered[i]:
				under += 1
			if (row[-1] as Vector3).y > BuildingMesher.SEA_SURFACE - 0.5:
				dry += 1
			var last_d := -0.01
			for v: Vector3 in row:
				var d := Vector2(v.x - p.x, v.z - p.y).length()
				if d < last_d - 0.05:
					folds += 1
					break
				last_d = d
			var end := Vector2((row[-1] as Vector3).x, (row[-1] as Vector3).z)
			if ext > 3.0 and (Geometry2D.is_point_in_polygon(end, L.coast) or SkyportIsland.contains(end.x, end.y)):
				inland += 1
		t.check(aprons > 250, "%s: %d shore rows with an apron" % [nm, aprons])
		t.check(dry == 0, "%s: every shore row reaches under the sea (%d end dry)" % [nm, dry])
		t.check(folds == 0, "%s: no shore row folds back on itself (%d)" % [nm, folds])
		t.check(inland == 0, "%s: no shore row ends on other land (%d)" % [nm, inland])
		t.check(under > 10, "%s: headlands take over the shore where they join (%d samples)" % [nm, under])
	# Headlands joined along a coast start their bands on the city's own row.
	for f: Dictionary in Landforms.forms():
		if not f.has("join"):
			continue
		var o: PackedVector2Array = f["poly"]
		var lf := Landforms.new()
		var r0 := lf._row(f, o, 0, 2)
		var cr: Array = BuildingMesher.shore_row_at(f["L"], o[0])[0]
		t.check(r0.size() == BuildingMesher.SHORE_ROWS + 1 and (r0[-1] as Vector3).is_equal_approx(cr[-1]),
			"%s meets the city's shore on one row" % f["name"])
		lf.free()
	# Skyport: beaches and rock run under the sea, none crosses a cove.
	var o2 := SkyportIsland.outline()
	var sdry := 0
	var sin_land := 0
	for i in o2.size():
		var row := SkyportIsland._blend_row(o2, i)
		if row[-1].y > BuildingMesher.SEA_SURFACE - 0.3:
			sdry += 1
		var end := Vector2(row[-1].x, row[-1].z)
		if end.distance_to(o2[i]) > 3.0 and Geometry2D.is_point_in_polygon(end, o2):
			sin_land += 1
	t.check(sdry == 0, "Skyport: every shore row reaches under the sea (%d dry)" % sdry)
	t.check(sin_land == 0, "Skyport: no shore row ends back on the island (%d)" % sin_land)
	# The places to go.
	var counts := CoastKit.new(L0).build()
	t.check(int(counts["lookout"]) >= 3 and int(counts["jetty"]) >= 3 and int(counts["viewpoint"]) >= 3,
		"the Commercial Island's coast has lookouts, jetties and viewpoints (%s)" % [counts])
	SkyportIsland.enabled = was_s
	Landforms.enabled = was_l
