extends RefCounted
## 2026-11-27 engine pass: device profiles, async autosave, dent cells,
## garage dimensions, residential tower ground floors.

const P := "user://test_engine_async.json"


func test_device_profiles(t) -> void:
	var hi := DeviceProfile.classify("iPhone16,2", 8 * 1024 * 1024 * 1024)
	t.check(hi["tier"] == "high" and int(hi["quality"]) == 2 and hi["fps_60"], "iPhone 15 Pro: High, 60 fps")
	var mid := DeviceProfile.classify("iPhone13,2", 4 * 1024 * 1024 * 1024)
	t.check(mid["tier"] == "mid" and int(mid["quality"]) == 1 and mid["fps_60"], "iPhone 12: Medium, 60 fps (governor adapts)")
	var lo := DeviceProfile.classify("iPhone11,8", 3 * 1024 * 1024 * 1024)
	t.check(lo["tier"] == "low" and int(lo["quality"]) == 0 and not lo["fps_60"], "iPhone XR: Low, steady 30")
	var ipad := DeviceProfile.classify("iPad14,5", 8 * 1024 * 1024 * 1024)
	t.check(ipad["tier"] == "high", "M2 iPad Pro: High")
	var small_ram := DeviceProfile.classify("iPhone14,7", 3 * 1024 * 1024 * 1024)
	t.check(small_ram["tier"] == "low", "under 3.5 GB of memory caps the tier")
	var four_gb := DeviceProfile.classify("iPhone14,2", 4 * 1024 * 1024 * 1024)
	t.check(four_gb["tier"] == "mid", "a 4 GB A15 phone starts at Medium")


func test_async_autosave(t) -> void:
	for s in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(P + s))
	var data := {"empire": {"day": 7, "minute": 1.0, "personal_cash": 1.0, "company_cash": 0.0, "businesses": [], "vehicles": [], "flags": {}}, "player": [0, 1, 0, 0]}
	var res := {"err": "?"}
	t.check(SafeSave.write_async(P, data, func(e: String): res["err"] = e), "the write starts")
	data["empire"]["day"] = 99   # (the snapshot was taken: changing the data now changes nothing)
	# A blocking save waits for the one in flight, then writes.
	SafeSave.write(P + ".x", data)
	var loop := Engine.get_main_loop() as SceneTree
	for i in 30:
		if res["err"] != "?":
			break
		await loop.process_frame
	t.check(res["err"] == "", "the background save completed without error")
	var back = JSON.parse_string(FileAccess.get_file_as_string(P))
	t.check(back is Dictionary and int(back["empire"]["day"]) == 7, "it saved the snapshot taken when it started")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(P + ".x"))


func test_dent_cells_cover_every_vertex(t) -> void:
	var rv := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 3000:
		rv.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 1.5), rng.randf_range(-2.4, 2.4)))
	var cells := CarVisual._cells_for(rv)
	var seen := 0
	var ok := true
	for k in cells:
		for i: int in (cells[k] as PackedInt32Array):
			seen += 1
			ok = ok and Vector3i((rv[i] / CarVisual.DENT_CELL).floor()) == k
	t.check(seen == rv.size() and ok, "each vertex is in exactly its own cell (%d of %d)" % [seen, rv.size()])


func test_garage_has_room_to_open_doors(t) -> void:
	t.check(VehicleGarage.BAY_W >= 3.8, "bays are wide enough to open a door between cars (%.1f m)" % VehicleGarage.BAY_W)
	t.check(VehicleGarage.AISLE >= 7.5, "the aisle leaves room to turn out of a bay (%.1f m)" % VehicleGarage.AISLE)
	var grade := VehicleGarage.RAMP_RISE / VehicleGarage.RAMP_LEN
	t.check(grade < 0.18, "the exit ramp is a gentle climb (%.0f%%)" % (grade * 100.0))


func test_residential_towers_have_no_shopfronts(t) -> void:
	var b := {"seed": 0.0, "apt": {"core": {"a_c": 1.0}}}
	# Find a seed the shader would give shops, then make it a home tower.
	for k in 256:
		b["seed"] = float(k) / 256.0 + 0.001
		if BuildingMesher.ground_shops({"seed": b["seed"]}):
			break
	t.check(BuildingMesher.ground_shops({"seed": b["seed"]}), "(a seed with shops)")
	t.check(BuildingMesher.residential_tower(b) and not BuildingMesher.ground_shops(b), "a home tower's ground floor is residential")
	b["apt"]["ground"] = true
	t.check(not BuildingMesher.residential_tower(b), "a shop unit's building is not")
