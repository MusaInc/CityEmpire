class_name NearTrafficPool
extends Node3D
## Renders animated wheels (rolling + front-wheel steering) and visible seated
## drivers/passengers for all near moving vehicles (< CAR_NEAR) across both
## city landmasses and Skyport Island, using just 3 shared MultiMeshInstance3D
## draw calls total (1 wheel batch + 2 seated-occupant batches).

const WHEEL_MODEL := "res://assets/vehicles/wheel_traffic.glb"
const DRIVER_MODEL := "res://assets/models/crowd_seated.glb"
const ENTRIES_PATH := "res://config/empire/vehicle_entries.json"
const DRIVER_RANGE := 86.0   # m: visible occupants inside transparent cabins (matches CAR_NEAR)

var game: EmpireGame
var _wheel_mmi: MultiMeshInstance3D
var _wheel_buf := PackedFloat32Array()
var _driver_mmis: Array[MultiMeshInstance3D] = []
var _driver_bufs: Array[PackedFloat32Array] = []
var _seats := {}             # body_name -> [seat_x, seat_y, seat_z]
var _island_cache: IslandTraffic
var _island_check_t := 0.0
var _parked_exit_t := 14.0
var _rng := RandomNumberGenerator.new()


func setup(p_game: EmpireGame) -> void:
	game = p_game
	_load_seat_profiles()
	_build_wheel_batch()
	_build_driver_batches()


func _load_seat_profiles() -> void:
	_seats.clear()
	if FileAccess.file_exists(ENTRIES_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ENTRIES_PATH))
		if parsed is Dictionary:
			for body_name in parsed:
				var prof: Dictionary = parsed[body_name]
				var st: Array = prof.get("seat", [-0.25, 0.56])
				var sx := float(prof.get("seat_x", 0.42))
				var side := float(prof.get("driver_side", 1.0))
				# Driver sits on right (UK RHD) when driver_side > 0; pelvis_y adjusted for seated mesh height.
				_seats[String(body_name)] = [sx * side, float(st[1]) - 0.10, float(st[0])]


func _seat_for(body_name: String, d: Dictionary) -> Array:
	var roof := float(d.get("roof", 1.48))
	var max_sy := roof - 0.98  # driver_0 head top is +0.82 m at 0.88 scale -> 16 cm headroom under roof
	if _seats.has(body_name):
		var s0: Array = _seats[body_name]
		return [float(s0[0]), minf(float(s0[1]), max_sy), float(s0[2])]
	# Fallback for civ_* models without explicit vehicle_entries.json record.
	var w := float(d.get("W", 1.82))
	var ride := float(d.get("ride", 0.14))
	var sx := clampf(w * 0.23, 0.36, 0.48)
	var sy := minf(clampf(ride + (roof - ride) * 0.32, 0.36, 0.85), max_sy)
	var sz := -0.14 if roof < 1.75 else -0.52
	var out := [sx, sy, sz]
	_seats[body_name] = out
	return out


func _build_wheel_batch() -> void:
	if not ResourceLoader.exists(WHEEL_MODEL):
		return
	var inst := (load(WHEEL_MODEL) as PackedScene).instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	var src: Mesh = (mis[0] as MeshInstance3D).mesh if mis.size() > 0 else null
	inst.free()
	if src == null:
		return
	var mesh: Mesh = src.duplicate()
	for si in mesh.get_surface_count():
		var old := mesh.surface_get_material(si)
		var sn := String(old.resource_name) if old else ""
		var mat := StandardMaterial3D.new()
		if sn == "rim":
			mat.albedo_color = Color(0.55, 0.56, 0.59)
			mat.metallic = 0.78
			mat.roughness = 0.26
		elif sn == "tyre":
			mat.albedo_color = Color(0.055, 0.055, 0.058)
			mat.roughness = 0.88
		else:
			mat.albedo_color = Color(0.03, 0.03, 0.035)
			mat.roughness = 0.75
		mesh.surface_set_material(si, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0
	_wheel_mmi = MultiMeshInstance3D.new()
	_wheel_mmi.name = "NearTrafficWheels"
	_wheel_mmi.multimesh = mm
	_wheel_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wheel_mmi)


func _build_driver_batches() -> void:
	var path := DRIVER_MODEL if ResourceLoader.exists(DRIVER_MODEL) else ""
	if path == "":
		return
	var inst := (load(path) as PackedScene).instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	mis.sort_custom(func(a, b): return String(a.name) < String(b.name))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/empire/npc/crowd.gdshader")
	mat.set_shader_parameter("pivot_k", 1.0)
	for mi in mis:
		var m: Mesh = (mi as MeshInstance3D).mesh.duplicate()
		m.surface_set_material(0, mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = m
		mm.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "NearTrafficDrivers_%s" % String(mi.name)
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_driver_mmis.append(mmi)
		_driver_bufs.append(PackedFloat32Array())
	inst.free()


func _island(dt: float) -> IslandTraffic:
	if _island_cache != null and is_instance_valid(_island_cache):
		return _island_cache
	_island_cache = null
	_island_check_t -= dt
	if _island_check_t <= 0.0 and is_inside_tree():
		_island_cache = get_tree().get_first_node_in_group("island_traffic") as IslandTraffic
		_island_check_t = 1.0 if _island_cache == null else 0.0
	return _island_cache


func _process(dt: float) -> void:
	if game == null or game.world == null or _wheel_mmi == null or game.state != "play" or get_tree().paused:
		return
	if game.garage and game.garage.inside:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var drv_r2 := DRIVER_RANGE * DRIVER_RANGE
	var wheel_xfs: Array[Transform3D] = []
	var drv_groups: Array = []
	for i in _driver_mmis.size():
		drv_groups.append([])

	# City traffic (both Commercial Island and Westbank): every car currently drawn in band 0.
	for world_n in [game.world, game.world.mainland]:
		if world_n == null or world_n.traffic == null:
			continue
		var tr: Traffic = world_n.traffic
		for id in tr.near_drawn_ids():
			var li := tr.c_lane[id]
			var s := tr.car_s(id, tr.now)
			var k := tr.c_kind[id]
			if k < 0 or k >= CityWorld.CAR_KINDS.size():
				continue
			var body_name := String(CityWorld.CAR_KINDS[k][2])
			var d: Dictionary = BodyDims.DIMS.get(body_name, {})
			if d.is_empty():
				continue
			var pos := tr.lane_point(li, s)
			var pf := tr.lane_point(li, s + 1.35)
			var pr := tr.lane_point(li, s - 1.35)
			var fw := tr.lane_dir(li, s)
			var run := maxf(Vector2(pf.x - pr.x, pf.z - pr.z).length(), 0.5)
			var grade := clampf((pf.y - pr.y) / run, -0.6, 0.6)
			pos.y = 0.5 * (pf.y + pr.y)
			var fw3 := Vector3(fw.x, grade, fw.z).normalized()
			var zb := -fw3
			var xb := Vector3.UP.cross(zb).normalized()
			var yb := zb.cross(xb)
			var car_b := Basis(xb, yb, zb)
			# Front-wheel steering angle from lane curvature 4.5 m ahead.
			var fw_ahead := tr.lane_dir(li, s + 4.5)
			var steer := clampf(Vector2(fw.x, fw.z).angle_to(Vector2(fw_ahead.x, fw_ahead.z)) * 1.35, -0.52, 0.52)
			var wr := float(d["wheel_r"])
			var tw := float(d["tyre_w"])
			var track := float(d["W"]) - tw - 0.05
			var spin := -s / maxf(wr, 0.15)
			_append_wheels(wheel_xfs, pos, car_b, d["axles"], wr, tw, track, spin, steer)
			if not drv_groups.is_empty() and pos.distance_squared_to(cp) < drv_r2:
				_append_occupants(drv_groups, id, pos, car_b, body_name, d, steer)

	# Skyport Island traffic: visible occupants inside near island cars (wheels are on mid mesh).
	var it := _island(dt)
	if it != null and not drv_groups.is_empty():
		var idx_i := 9000
		for c: Dictionary in it.cars:
			idx_i += 1
			if float(c["wait"]) > 0.0:
				continue
			var xf := it.car_xf(c)
			if xf.origin.distance_squared_to(cp) >= drv_r2:
				continue
			var k := int(c.get("kind", 0))
			if k < 0 or k >= CityWorld.CAR_KINDS.size():
				continue
			var body_name := String(CityWorld.CAR_KINDS[k][2])
			var d: Dictionary = BodyDims.DIMS.get(body_name, {})
			if not d.is_empty():
				_append_occupants(drv_groups, idx_i, xf.origin, xf.basis, body_name, d, 0.0)

	var aabb := AABB(cp - Vector3(110, 110, 110), Vector3(220, 220, 220))
	_upload_wheels(wheel_xfs, aabb)
	_upload_drivers(drv_groups, aabb)
	_step_parked_exits(dt, cp)


## Periodically let a pedestrian step out of a nearby kerbside parked car onto the pavement.
func _step_parked_exits(dt: float, cp: Vector3) -> void:
	_parked_exit_t -= dt
	if _parked_exit_t > 0.0 or game == null or game.crowd == null or game.state != "play":
		return
	_parked_exit_t = _rng.randf_range(18.0, 32.0)
	for w_n in [game.world, game.world.mainland]:
		var cw := w_n as CityWorld
		if cw == null:
			continue
		var c0 := Vector2i(floori(cp.x / CityWorld.CHUNK), floori(cp.z / CityWorld.CHUNK))
		if not cw._loaded.has(c0):
			continue
		var parked := cw.parked_cars(c0)
		for pc in parked:
			var xf: Transform3D = pc[0]
			var d := xf.origin.distance_to(cp)
			if d < 18.0 or d > 48.0:
				continue
			var exit_pos := xf.origin + xf.basis.x * 1.45
			game.crowd.spawn_from_car(exit_pos, _rng.randi() % 12, _rng.randf(),
				Crowd.TOPS[_rng.randi() % Crowd.TOPS.size()])
			return


func _append_wheels(out: Array[Transform3D], pos: Vector3, car_b: Basis, axles: Array, wr: float, tw: float, track: float, spin: float, steer: float) -> void:
	var scale_v := Vector3(tw / 0.44, wr, wr)
	var spin_b := Basis(Vector3.RIGHT, spin)
	for ai in axles.size():
		var az := float(axles[ai])
		var is_front := ai == 0
		var st_b := Basis(Vector3.UP, -steer) if is_front else Basis.IDENTITY
		for side: float in [-1.0, 1.0]:
			var flip := Basis(Vector3.UP, PI) if side < 0.0 else Basis.IDENTITY
			var local_b := st_b * spin_b * flip * Basis.from_scale(scale_v)
			var local_p := Vector3(side * track * 0.5, wr, -az)
			out.append(Transform3D(car_b * local_b, pos + car_b * local_p))


func _append_occupants(groups: Array, id: int, pos: Vector3, car_b: Basis, body_name: String, d: Dictionary, steer: float) -> void:
	var seat := _seat_for(body_name, d)
	var sx := float(seat[0])
	var sy := float(seat[1])
	var sz := float(seat[2])
	var h := absi((id + 17) * 2654435761)
	var seed_f := float(h % 1000) / 1000.0
	var gi := h % groups.size()
	var top_c: Color = Crowd.TOPS[(h >> 8) % Crowd.TOPS.size()]
	var head_look := clampf(-steer * 0.7, -0.45, 0.45)
	var driver_p := pos + car_b * Vector3(sx, sy, sz)
	(groups[gi] as Array).append([Transform3D(car_b.scaled(Vector3.ONE * 0.88), driver_p), top_c, seed_f, head_look])
	# ~28% of cars carry a front-seat passenger too.
	if (h >> 4) % 100 < 28:
		var h2 := absi((id + 91) * 1597334677)
		var gi2 := h2 % groups.size()
		var pass_p := pos + car_b * Vector3(-sx, sy, sz + 0.04)
		(groups[gi2] as Array).append([Transform3D(car_b.scaled(Vector3.ONE * 0.86), pass_p),
			Crowd.TOPS[(h2 >> 8) % Crowd.TOPS.size()], float(h2 % 1000) / 1000.0, 0.12])


func _upload_wheels(xfs: Array[Transform3D], aabb: AABB) -> void:
	var mm := _wheel_mmi.multimesh
	var cnt := xfs.size()
	if cnt > mm.instance_count:
		var cap := maxi(32, mm.instance_count)
		while cap < cnt:
			cap *= 2
		mm.instance_count = cap
		_wheel_buf.resize(cap * 12)
	mm.visible_instance_count = cnt
	if cnt > 0:
		var buf := _wheel_buf
		var j := 0
		for xf in xfs:
			var b := xf.basis
			var o := xf.origin
			buf[j] = b.x.x; buf[j + 1] = b.y.x; buf[j + 2] = b.z.x; buf[j + 3] = o.x
			buf[j + 4] = b.x.y; buf[j + 5] = b.y.y; buf[j + 6] = b.z.y; buf[j + 7] = o.y
			buf[j + 8] = b.x.z; buf[j + 9] = b.y.z; buf[j + 10] = b.z.z; buf[j + 11] = o.z
			j += 12
		mm.buffer = buf
	_wheel_mmi.custom_aabb = aabb


func _upload_drivers(groups: Array, aabb: AABB) -> void:
	for gi in _driver_mmis.size():
		var mmi := _driver_mmis[gi]
		var mm := mmi.multimesh
		var list: Array = groups[gi]
		var cnt := list.size()
		if cnt > mm.instance_count:
			var cap := maxi(8, mm.instance_count)
			while cap < cnt:
				cap *= 2
			mm.instance_count = cap
			_driver_bufs[gi].resize(cap * 20)
		mm.visible_instance_count = cnt
		if cnt > 0:
			var buf: PackedFloat32Array = _driver_bufs[gi]
			var j := 0
			for item in list:
				var xf: Transform3D = item[0]
				var b := xf.basis
				var o := xf.origin
				var c: Color = (item[1] as Color).srgb_to_linear()
				buf[j] = b.x.x; buf[j + 1] = b.y.x; buf[j + 2] = b.z.x; buf[j + 3] = o.x
				buf[j + 4] = b.x.y; buf[j + 5] = b.y.y; buf[j + 6] = b.z.y; buf[j + 7] = o.y
				buf[j + 8] = b.x.z; buf[j + 9] = b.y.z; buf[j + 10] = b.z.z; buf[j + 11] = o.z
				buf[j + 12] = c.r; buf[j + 13] = c.g; buf[j + 14] = c.b; buf[j + 15] = 0.0
				buf[j + 16] = 0.0; buf[j + 17] = float(item[2]); buf[j + 18] = 0.0; buf[j + 19] = float(item[3])
				j += 20
			mm.buffer = buf
		mmi.custom_aabb = aabb
