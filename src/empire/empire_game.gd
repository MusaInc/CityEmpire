class_name EmpireGame
extends Node3D
## City Empire's main scene: the shared city (CityWorld, both islands), the
## CitySwing hero on foot (webs off, everyday movement), Never Stop's car
## physics for driving, and the business layer on top:
##
##  * Empire (src/empire/sim) is the whole economy; this node advances its
##    clock, drives the Atmosphere's time of day from it and saves it.
##  * Premises (shop units + wholesalers cut into real ground floors) get a
##    ShopInterior when you're near; the shop you're in runs as a ShopFloor
##    (walking customers and staff), every other one in the model.
##  * Interaction: the nearest "spot" (shelf slot, till, stock room, office,
##    door, trade counter, collection bay, a car's door/boot, a TO LET board)
##    gives a context prompt; ACTION (E / pad X / touch) does it.
##  * Goods move only through Stock transfers: bay → hands → boot → hands →
##    stock room / shelf, so nothing duplicates.

signal spot_changed(spot: Dictionary)

const SAVE_PATH := "user://cityempire_save.json"
const STREAM_IN := 150.0
const STREAM_OUT := 210.0
const REACH := 1.6

var args := {}
var state := "boot"      # boot / title / play
var atmosphere: Atmosphere
var world: CityWorld
var layout: CityLayout
var player: Player
var rig: CharacterRig
var camera: SwingCamera
var chase: ChaseCamera
var drive_input: DriveInput
var vfx: VehicleFx
var audio: AudioDirector
var sfx: Sfx
var empire: Empire
var ui: EmpireUI
var units: Array = []
var unit_by_id := {}
var interiors := {}      # unit id -> ShopInterior
var floor: ShopFloor
var floor_unit := ""
var cars := {}           # vehicle id -> Car
var driving := ""        # vehicle id being driven
var spot := {}           # the current interaction
var carry_node: Node3D
var time_scale := 1.0    # 1 normal, 3 fast (only with nobody needing you)
var minutes_per_second := 1.0
var _stream_t := 0.0
var _save_t := 0.0
var _last_car_pos := Vector3.ZERO
var _km_acc := 0.0
var _clean_t := 0.0
var _tutorial := 0
var _warm := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("quality"):
		Settings.quality = int(args["quality"])
	Settings.time_of_day = "empire"   # the Empire's clock drives the sun
	Settings.weather = "empire"       # and its daily weather the sky (CityLife)
	Settings.apply()
	minutes_per_second = float(EmpireData.economy().get("minutes_per_real_second", 1.0))
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)

	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	var t0 := Time.get_ticks_msec()
	world = CityWorld.new()
	world.name = "World"
	add_child(world)
	layout = world.layout
	atmosphere.configure(args, world)
	Car.water_check = layout.is_water
	for P in [layout.mainland.premises if layout.mainland else null, layout.premises]:
		if P:
			for u in P.units:
				units.append(u)
				unit_by_id[u["id"]] = u
	print("City Empire world: %d ms, %d units" % [Time.get_ticks_msec() - t0, units.size()])

	player = Player.new()
	player.name = "Player"
	player.params = load("res://config/empire_params.tres")
	player.swing_enabled = false
	player.everyday = true
	add_child(player)
	player.ground_fn = layout.ground_y
	rig = CharacterRig.new()
	rig.name = "Rig"
	player.add_child(rig)
	rig.set_player(player)
	var look := Shop.look({"face": "face_none", "head": "head_bare", "suit": "sky", "top": "top_long",
		"pants": "pants_navy", "hero": "hero_ade", "hair": "hair_natural"})
	look["glove"] = look["skin"]  # bare hands (the hero model always wears gloves)
	rig.apply_look(look)
	camera = SwingCamera.new()
	camera.name = "CameraRig"
	add_child(camera)
	camera.set_target(player)
	camera.distance_scale = 0.62   # closer than the swing camera: street level
	world.set_viewer(camera)
	chase = ChaseCamera.new()
	chase.name = "ChaseCamera"
	add_child(chase)
	camera.cam.make_current()
	drive_input = DriveInput.new()
	drive_input.name = "DriveInput"
	add_child(drive_input)
	drive_input.enabled = false
	vfx = VehicleFx.new()
	vfx.name = "VehicleFx"
	add_child(vfx)
	audio = AudioDirector.new()
	audio.name = "Audio"
	add_child(audio)
	audio.attach_player(player)
	audio.attach_weather(atmosphere)
	sfx.director = audio
	carry_node = Node3D.new()
	carry_node.name = "Carry"
	add_child(carry_node)

	ui = EmpireUI.new()
	ui.game = self
	add_child(ui)

	var has_save := FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_PATH + ".bak")
	if args.has("save"):
		pass
	if args.has("new") or (args.has("play") and not has_save):
		new_game()
		_play()
	elif args.has("play") and has_save:
		load_game()
		_play()
	else:
		if has_save:
			load_game()
		else:
			new_game()
		_title(has_save)
	_after_start.call_deferred()


func _after_start() -> void:
	# Captures / tests: jump straight to a situation.
	if args.has("goto"):
		var g := String(args["goto"])
		var u: Dictionary = starter_unit() if g == "start" else (wholesaler(g.get_slice(":", 1)) if g.begins_with("wholesale") else unit_by_id.get(g, {}))
		if g == "rival" and not empire.rivals.is_empty():
			u = unit_by_id.get(empire.rivals[0]["unit"], {})
		if g == "firm":
			var fs := CityLife.firms_for_sale(empire)
			if fs.is_empty():
				fs = empire.firms
			# The independent nearest the starter shop (a familiar street).
			var s0 := starter_unit()
			var best := INF
			for f in fs:
				var d0 := CityLife._dist(f["pos"], s0["pos"])
				if d0 < best:
					best = d0
					u = unit_by_id.get(f["unit"], {})
		if not u.is_empty():
			var inside := args.has("inside")
			var p := Premises.door_point(u) + Premises.outward(u) * (-2.5 if inside else 3.0) + Vector3.UP * 1.0
			_teleport(p, atan2(Premises.outward(u).x, Premises.outward(u).z) + (PI if not inside else 0.0))
	if args.has("hour"):
		empire.minute = float(args["hour"]) * 60.0
	if args.has("demo"):
		_demo_setup(String(args["demo"]))
	if args.has("noworld"):
		world.visible = false
	if args.has("probe"):
		# Debug: which visual instances sit around the hero's feet?
		await get_tree().create_timer(3.0).timeout
		var p := player.global_position
		var hits := RenderingServer.instances_cull_ray(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0, get_world_3d().scenario)
		for id in hits:
			var o := instance_from_id(id)
			if o is Node:
				print("PROBE ", (o as Node).get_path(), "  ", o.get_class())
		var si: ShopInterior = interiors.get(floor_unit)
		for id in hits:
			var o := instance_from_id(id)
			if si and o is MeshInstance3D and (o as Node).name == "Detail":
				var mi := o as MeshInstance3D
				var arr := mi.mesh.surface_get_arrays(0)
				var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var inv := (si.global_transform.affine_inverse() * mi.global_transform)
				var n := 0
				for i in range(0, vv.size(), 3):
					var q := inv * ((vv[i] + vv[i + 1] + vv[i + 2]) / 3.0)
					if q.x > 0.2 and q.x < si.W - 0.2 and q.z < -0.4 and q.z > -si.D + 0.2 and q.y > -0.6 and q.y < si.H:
						n += 1
						if n < 12:
							print("DETAIL tri room=", q, " a=", inv * vv[i], " b=", inv * vv[i + 1], " c=", inv * vv[i + 2])
				print("DETAIL inside: ", n)
		if String(args.get("probe")).begins_with("hide:"):
			var names := String(args["probe"]).trim_prefix("hide:").split("+")
			for id in hits:
				var o := instance_from_id(id)
				if o is Node3D and (o as Node).name in names:
					(o as Node3D).visible = false
	if args.has("view"):
		# Captures: a fixed camera relative to the hero: "x,y,z,lx,ly,lz" offsets (m).
		var v := String(args["view"]).split(",")
		camera.cine = func(_dt: float) -> Array:
			var o := player.global_position
			var from := o + Vector3(float(v[0]), float(v[1]), float(v[2]))
			var to := o + Vector3(float(v[3]), float(v[4]), float(v[5]))
			return [Transform3D(Basis.looking_at(to - from, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD), from), 62.0]
	if args.has("days"):
		# Captures: run the economy forward (news, rivals, a net-worth history).
		for i in int(args["days"]):
			empire.advance(1440.0)
		ui.close_panel(true)
	if args.has("panel"):
		var pn := String(args["panel"])
		if pn == "victory":
			ui.victory()
		elif pn == "rival" and not empire.rivals.is_empty():
			ui.open_rival(unit_by_id[empire.rivals[0]["unit"]])
		elif pn == "firm" and not empire.firms.is_empty():
			var fs2 := CityLife.firms_for_sale(empire)
			ui.open_firm(unit_by_id[(fs2[0] if not fs2.is_empty() else empire.firms[0])["unit"]])
		elif pn == "report":
			empire.advance(1440.0 - empire.minute + 1.0)
		else:
			ui.open_phone(pn)
	if args.has("shot"):
		_capture(String(args["shot"]), float(args.get("shot-at", "4")))
	if args.has("selftest"):
		_selftest.call_deferred()
	if args.has("autoplay"):
		var ap: Node = load("res://src/empire/dev/autoplay.gd").new()
		ap.set("game", self)
		add_child(ap)


# ---------------------------------------------------------------- game
func new_game() -> void:
	empire = Empire.new()
	empire.market = _market()
	var start := starter_unit()
	empire.flags["start_unit"] = start["id"]
	empire.new_game(int(args.get("seed", "1")))
	_connect_empire()
	_sync_rivals()
	var out := Premises.outward(start)
	var along := Premises.along_dir(start)
	var door := Premises.door_point(start)
	# Your old hatchback, parked at the kerb a few metres along.
	var car_p := _kerb_point(door + out * 6.5 + along * 5.0)
	var v: Dictionary = empire.vehicles[0]
	v["pos"] = [car_p.x, car_p.y, car_p.z]
	v["yaw"] = atan2(-along.x, -along.z)
	_spawn_cars()
	_teleport(door + out * 3.2 + Vector3.UP * 1.0, atan2(-out.x, -out.z) + PI)
	_tutorial = 0


## The city's shop units as the economy sees them (CityLife's market).
func _market() -> Array:
	var m: Array = []
	for u in units:
		if u["kind"] == "shop":
			m.append(Premises.record(u))
	return m


var _rival_sig := ""


## Rebuilds the interiors of units whose occupier (QuikSave, an independent,
## for sale or not) changed.
func _sync_rivals() -> void:
	var tags := {}
	for r in empire.rivals:
		tags[String(r["unit"])] = "r"
	for f in empire.firms:
		tags[String(f["unit"])] = "f" + ("s" if f.get("for_sale", false) else "") + String(f["name"])
	var ids: Array = tags.keys()
	ids.sort()
	var parts: Array = []
	for id in ids:
		parts.append("%s=%s" % [id, tags[id]])
	var sig := ",".join(parts)
	if sig == _rival_sig:
		return
	var old := {}
	for p in _rival_sig.split(",", false):
		old[p.get_slice("=", 0)] = p.get_slice("=", 1)
	_rival_sig = sig
	for id in interiors.keys():
		if String(tags.get(id, "")) != String(old.get(id, "")):
			rebuild_interior(id)


## Who trades in a unit that isn't yours: the QuikSave record, or an
## independent's (marked "firm"), or {}.
func occupier(unit_id: String) -> Dictionary:
	var r := CityLife.rival_at(empire, unit_id)
	if not r.is_empty():
		return r
	var f := CityLife.firm_at(empire, unit_id)
	if not f.is_empty():
		var d := f.duplicate()
		d["firm"] = true
		return d
	return {}


## Today's sky follows the Empire's weather.
func _sync_weather() -> void:
	if args.has("weather"):
		return
	var sky := String(CityLife.weather_def(empire.weather).get("sky", "clear"))
	if atmosphere.weather != sky:
		atmosphere.set_weather(sky, state != "play")


## The cheapest shop on Westbank: the one you can just afford.
func starter_unit() -> Dictionary:
	var best := {}
	for u in units:
		if u["kind"] == "shop" and u["island"] == "west" and (best.is_empty() or float(u["rent"]) < float(best["rent"])):
			best = u
	return best


func wholesaler(island: String) -> Dictionary:
	for u in units:
		if u["kind"] == "wholesale" and u["island"] == island:
			return u
	for u in units:
		if u["kind"] == "wholesale":
			return u
	return {}


func _connect_empire() -> void:
	empire.notified.connect(func(t, k): ui.toast(t, k))
	empire.day_ended.connect(func(r):
		ui.day_report(r)
		save_game())
	empire.sold.connect(func(_b, amt): pass)
	empire.goal_done.connect(func(_g): Sfx.play("chime", -4.0))
	empire.won.connect(func():
		Sfx.play("chime", -2.0)
		save_game()
		ui.victory())


func _title(_has_save: bool) -> void:
	state = "title"
	player.input_enabled = false
	ui.show_title(FileAccess.file_exists(SAVE_PATH))
	# A slow orbit over the starter street.
	var u := starter_unit()
	var c := Premises.door_point(u)
	var t := [0.0]
	camera.cine = func(dt: float) -> Array:
		t[0] += dt * 0.05
		var p := c + Vector3(cos(t[0]) * 38.0, 22.0, sin(t[0]) * 38.0)
		return [Transform3D(Basis.looking_at(c + Vector3.UP * 4.0 - p, Vector3.UP), p), 55.0]


func start_new() -> void:
	new_game()
	save_game()
	_play()


func continue_game() -> void:
	load_game()
	_play()


func _play() -> void:
	state = "play"
	camera.cine = Callable()
	camera.snap()
	player.input_enabled = driving == ""
	ui.show_hud()
	if empire.flags.get("intro_done", false) == false and not args.has("shot") and not args.has("autoplay") and not args.has("perf"):
		ui.intro()
	if not DisplayServer.is_touchscreen_available() and not args.has("touch") and not args.has("shot"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _teleport(p: Vector3, yaw: float) -> void:
	player.respawn(p)
	player.last_safe_position = p
	camera.face(yaw)
	world.build_all_near(p, 300.0)


## A point on the street surface near p (car spawns).
func _kerb_point(p: Vector3) -> Vector3:
	var g := layout.ground_y(p.x, p.z)
	if layout.mainland and p.x < CityLayout.FAR_SHORE:
		g = layout.mainland.ground_y(p.x, p.z)
	return Vector3(p.x, g + 0.35, p.z)


# --------------------------------------------------------------- frame
func _process(dt: float) -> void:
	if empire == null:
		return
	if state == "play" and not get_tree().paused:
		var k := time_scale if driving == "" and floor == null else 1.0
		var t0 := Time.get_ticks_usec()
		empire.advance(dt * minutes_per_second * k)
		_perf_sim += Time.get_ticks_usec() - t0
	atmosphere.hour = empire.hour()
	_stream_t -= dt
	if _stream_t <= 0.0:
		_stream_t = 0.4
		_sync_weather()
		_sync_rivals()
		_stream_interiors()
		_update_live_floor()
	if state != "play":
		return
	_update_spot()
	_update_carry_visual()
	if driving != "":
		_track_driving()
	_save_t += dt
	if _save_t > 90.0:
		_save_t = 0.0
		save_game()
	_tutorial_step()
	ui.update_hud()
	if args.has("perf"):
		_perf_sample(dt)


var _perf_sim := 0
var _perf := {}


## `--perf=<seconds>`: averages over the run, printed at the end (and quit).
func _perf_sample(dt: float) -> void:
	if _perf.is_empty():
		_perf = {"n": 0, "dt": 0.0, "proc": 0.0, "phys": 0.0, "draw": 0.0, "prim": 0.0, "obj": 0.0, "sim": 0, "floor": 0,
			"cust": 0, "t": 0.0}
	_perf["t"] = float(_perf["t"]) + dt
	if float(_perf["t"]) < 3.0:
		_perf_sim = 0
		return  # (warm-up)
	_perf["n"] = int(_perf["n"]) + 1
	_perf["dt"] = float(_perf["dt"]) + dt
	_perf["proc"] = float(_perf["proc"]) + Performance.get_monitor(Performance.TIME_PROCESS)
	_perf["phys"] = float(_perf["phys"]) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_perf["draw"] = float(_perf["draw"]) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_perf["prim"] = float(_perf["prim"]) + Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_perf["obj"] = float(_perf["obj"]) + Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_perf["sim"] = int(_perf["sim"]) + _perf_sim
	_perf_sim = 0
	if floor:
		_perf["cust"] = int(_perf["cust"]) + floor.customers.size()
	if float(_perf["t"]) >= float(args["perf"]) + 3.0:
		var n := maxf(float(_perf["n"]), 1.0)
		print("PERF frames=%d fps=%.1f process=%.2fms physics=%.2fms draws=%.0f prims=%.0fk objects=%.0f sim=%.3fms customers=%.1f mem=%.0fMB" % [
			int(n), n / float(_perf["dt"]), float(_perf["proc"]) / n * 1000.0, float(_perf["phys"]) / n * 1000.0,
			float(_perf["draw"]) / n, float(_perf["prim"]) / n / 1000.0, float(_perf["obj"]) / n,
			float(_perf["sim"]) / n / 1000.0, float(_perf["cust"]) / n, Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6])
		get_tree().quit()


func _unhandled_input(e: InputEvent) -> void:
	if state != "play":
		return
	if e.is_action_pressed("interact") or e.is_action_pressed("interact_alt"):
		act()
	elif e.is_action_pressed("pause") or e.is_action_pressed("phone"):
		ui.open_phone()
	elif e.is_action_pressed("map"):
		ui.open_phone("map")
	elif e.is_action_pressed("speed_up"):
		toggle_fast()


func toggle_fast() -> void:
	time_scale = 1.0 if time_scale > 1.0 else 4.0
	ui.toast("Time ×%d" % int(time_scale) if time_scale > 1.0 else "Normal time", "info")


# ----------------------------------------------------------- interiors
func _stream_interiors() -> void:
	var focus := player.global_position if driving == "" else (cars[driving] as Node3D).global_position
	for u in units:
		var d := Vector2(focus.x, focus.z).distance_to(Vector2(float(u["pos"][0]), float(u["pos"][2])))
		var id: String = u["id"]
		if d < STREAM_IN and not interiors.has(id):
			_build_interior(u)
		elif d > STREAM_OUT and interiors.has(id) and floor_unit != id:
			interiors[id].queue_free()
			interiors.erase(id)


func _build_interior(u: Dictionary) -> ShopInterior:
	var si := ShopInterior.new()
	var b := empire.business_at(u["id"])
	si.setup(u, b, layout.ground_y, occupier(u["id"]) if b == null else {})
	add_child(si)
	interiors[u["id"]] = si
	if u["kind"] == "wholesale":
		si.refresh_goods(_pallet(u["id"]))
	_refresh_signs(u["id"])
	return si


func rebuild_interior(unit_id: String) -> void:
	if interiors.has(unit_id):
		var keep := floor_unit == unit_id
		if keep:
			_end_floor()
		interiors[unit_id].queue_free()
		interiors.erase(unit_id)
		_build_interior(unit_by_id[unit_id])


func _refresh_signs(unit_id: String) -> void:
	var si: ShopInterior = interiors.get(unit_id)
	if si == null:
		return
	var b := empire.business_at(unit_id)
	if not si.rival.is_empty():
		var h := empire.hour()
		si.update_signs(h >= 7.0 and h < (22.0 if si.rival.get("firm", false) else 23.0))
		return
	si.update_signs(b != null and b.open and b.within_hours(empire.hour()))


func _pallet(unit_id: String) -> Stock:
	if not empire.pallets.has(unit_id):
		empire.pallets[unit_id] = Stock.new(0, "pallet")
	return empire.pallets[unit_id]


## Which shop you're in (or just outside): it runs as a live ShopFloor.
func _update_live_floor() -> void:
	var want := ""
	if driving == "":
		for id in interiors:
			var si: ShopInterior = interiors[id]
			if si.kind != "shop" or empire.business_at(id) == null:
				continue
			var local := si.global_transform.affine_inverse() * player.global_position
			if local.x > -3.0 and local.x < si.W + 3.0 and local.z < 6.0 and local.z > -si.D - 0.5 \
					and absf(local.y) < 4.0:
				want = id
				break
	player.indoors = false
	for id in interiors:
		if (interiors[id] as ShopInterior).contains(player.global_position):
			player.indoors = true
	if want == floor_unit:
		return
	_end_floor()
	if want != "":
		floor_unit = want
		floor = ShopFloor.new()
		floor.name = "ShopFloor"
		floor.minutes_per_second = minutes_per_second
		add_child(floor)
		floor.setup(empire, empire.business_at(want), interiors[want])
		floor.served.connect(func(amt, _n, at):
			Sfx.play("cash", -3.0)
			ui.float_text("+" + EmpireData.money(amt, true), at, Color(0.5, 1.0, 0.6)))
		floor.walked_out.connect(func(at): ui.float_text("Gave up waiting", at, Color(1.0, 0.45, 0.35)))
	for id in interiors:
		_refresh_signs(id)


func _end_floor() -> void:
	if floor:
		floor.queue_free()
		floor = null
	floor_unit = ""


func current_business() -> Business:
	return empire.business_at(floor_unit) if floor_unit != "" else null


# ---------------------------------------------------------------- spots
func _update_spot() -> void:
	var best := {}
	var best_d := INF
	if driving == "" and not player.stunned:
		var p := player.global_position
		for id in interiors:
			var si: ShopInterior = interiors[id]
			if si.global_transform.origin.distance_to(p) > 60.0:
				continue
			for s in si.world_spots():
				var d := Vector2(p.x, p.z).distance_to(Vector2(s["world"].x, s["world"].z))
				var reach := REACH * (1.4 if s["kind"] in ["trade", "pallet", "office"] else 1.0)
				if d < reach and absf(p.y - 0.9 - s["world"].y) < 1.6 and d < best_d:
					best = s
					best_d = d
			# TO LET board outside an unrented shop.
			if si.kind == "shop" and empire.business_at(id) == null:
				var u: Dictionary = si.unit
				var w := Premises.door_point(u) + Premises.outward(u) * 1.2
				var d2 := Vector2(p.x, p.z).distance_to(Vector2(w.x, w.z))
				if d2 < 2.4 and d2 < best_d:
					best = {"kind": "letboard", "unit": id, "world": w}
					best_d = d2
		var hs := _home_spots(p, best, best_d)
		best = hs[0]
		best_d = hs[1]
		for vid in cars:
			var car: Car = cars[vid]
			var xf := car.global_transform
			var half: float = car.spec["size"].z * 0.5
			var door := xf * Vector3(-car.spec["size"].x * 0.5 - 0.6, 0.0, -0.3)
			var boot := xf * Vector3(0.0, 0.0, half + 0.8)
			for s2 in [{"kind": "car_door", "vehicle": vid, "world": door}, {"kind": "car_boot", "vehicle": vid, "world": boot}]:
				var d3 := Vector2(p.x, p.z).distance_to(Vector2(s2["world"].x, s2["world"].z))
				if d3 < 1.5 and d3 < best_d:
					best = s2
					best_d = d3
	var changed: bool = best.get("kind", "") != spot.get("kind", "") or best.get("slot", -9) != spot.get("slot", -9) \
		or best.get("vehicle", "") != spot.get("vehicle", "") or best.get("interior") != spot.get("interior")
	spot = best
	if changed:
		spot_changed.emit(spot)


## The prompt for the current spot: [text, enabled].
func spot_prompt() -> Array:
	if driving != "":
		return ["PARK & GET OUT", true]
	if spot.is_empty():
		return ["", false]
	var si: ShopInterior = spot.get("interior")
	var b: Business = si.biz if si else null
	match String(spot["kind"]):
		"slot":
			var s: Dictionary = b.slots[spot["slot"]]
			var pid := _carried_for(b, spot["slot"])
			if pid != "":
				return ["STOCK %s" % String(EmpireData.product(pid)["name"]).to_upper(), true]
			if not empire.carried.is_empty():
				var cp: String = empire.carried.units.keys()[0]
				var where := {"fridge": "A FRIDGE", "shelf": "A SHELF", "coffee": "THE COFFEE MACHINE",
					"pickmix": "THE PICK & MIX"}.get(String(EmpireData.product(cp).get("fixture", "")), "ANOTHER SPOT") as String
				if int(s["qty"]) >= int(s["cap"]) and b.can_hold(spot["slot"], cp):
					return ["THIS SLOT IS FULL", false]
				return ["%s GOES ON %s" % [String(EmpireData.product(cp)["name"]).to_upper(), where], false]
			if s["product"] == "":
				return ["EMPTY SLOT · bring stock", false]
			return ["PRICE · %s %s" % [EmpireData.product(s["product"])["name"], EmpireData.money(b.price(s["product"]), true)], true]
		"till":
			if floor and floor.room == si:
				if floor.scanning_at(spot["till"]):
					return ["SCANNING…", false]
				if floor.waiting_at(spot["till"]):
					return ["SERVE CUSTOMER", true]
			return ["TILL · no one waiting", false]
		"rack":
			if not empire.carried.is_empty():
				return ["STORE %d CASE%s" % [empire.carried.cases_used(), "" if empire.carried.cases_used() == 1 else "S"], true]
			if b.backroom.is_empty():
				return ["STOCKROOM · empty", false]
			return ["TAKE STOCK", true]
		"office":
			return ["MANAGE %s" % b.name.to_upper(), true]
		"door":
			return ["CLOSE SHOP" if b.open else "OPEN SHOP", true]
		"clean":
			if b.cleanliness > 0.9:
				return ["", false]
			return ["CLEAN FLOOR (%d%%)" % int(b.cleanliness * 100.0), true]
		"trade":
			return ["BUY STOCK", true]
		"pallet":
			var pal := _pallet(si.unit["id"])
			if pal.is_empty():
				return ["COLLECTION BAY · nothing waiting", false]
			if empire.carried.room_for(pal.units.keys()[0]) <= 0:
				return ["HANDS FULL", false]
			return ["PICK UP (%d case%s waiting)" % [pal.cases_used(), "" if pal.cases_used() == 1 else "s"], true]
		"letboard":
			var u: Dictionary = unit_by_id[spot["unit"]]
			var rv := CityLife.rival_at(empire, u["id"])
			if not rv.is_empty():
				return ["%s · BUY OUT %s" % [String(CityLife.rival_cfg().get("name", "QuikSave")).to_upper(), EmpireData.money(CityLife.rival_price(rv))], true]
			var fm := CityLife.firm_at(empire, u["id"])
			if not fm.is_empty():
				return ["%s · %s %s" % [String(fm["name"]).to_upper(), "FOR SALE" if fm.get("for_sale", false) else "MAKE AN OFFER",
					EmpireData.money(CityLife.firm_price(fm))], true]
			return ["TO LET · %s/day" % EmpireData.money(float(u["rent"])), true]
		"home_lift":
			var home := home_by_id(spot["home"])
			if empire.owns_property(spot["home"]):
				var q = empire.properties.filter(func(x): return x["id"] == spot["home"])[0]
				if q.get("let", false):
					return ["%s · LET TO TENANTS" % String(home["name"]).to_upper(), false]
				return ["LIFT UP TO %s" % String(home["name"]).to_upper(), true]
			return ["FOR SALE · %s · %s" % [home["name"], EmpireData.money(float(home["price"]))], true]
		"home_down":
			return ["LIFT DOWN TO THE STREET", true]
		"home_bed":
			return ["SLEEP TILL 07:00", true]
		"car_door":
			var v := empire.vehicle(spot["vehicle"])
			return ["DRIVE %s" % String(EmpireData.vehicle_model(v["model"])["name"]).to_upper(), true]
		"car_boot":
			var v2 := empire.vehicle(spot["vehicle"])
			var cargo: Stock = v2["cargo"]
			var near_bay := _bay_near(cars[spot["vehicle"]].global_position)
			if not empire.carried.is_empty():
				return ["LOAD %d CASE%s" % [empire.carried.cases_used(), "" if empire.carried.cases_used() == 1 else "S"], true]
			if near_bay != "" and not _pallet(near_bay).is_empty():
				return ["YARD CREW: LOAD FROM BAY", true]
			if not cargo.is_empty():
				return ["UNLOAD (%d/%d cases)" % [cargo.cases_used(), cargo.case_capacity], true]
			return ["BOOT · empty (%d cases)" % cargo.case_capacity, false]
	return ["", false]


## The product in your hands that can go on slot i (or "").
func _carried_for(b: Business, slot_i: int) -> String:
	for pid in empire.carried.units:
		if b.can_hold(slot_i, pid) and int(b.slots[slot_i]["qty"]) < int(b.slots[slot_i]["cap"]):
			return pid
	return ""


## Do the current spot's action.
func act() -> void:
	if state != "play":
		return
	if driving != "":
		exit_vehicle()
		return
	if spot.is_empty():
		return
	var pr := spot_prompt()
	if not pr[1]:
		Sfx.play("error", -10.0)
		return
	var si: ShopInterior = spot.get("interior")
	var b: Business = si.biz if si else null
	match String(spot["kind"]):
		"slot":
			var i: int = spot["slot"]
			var pid := _carried_for(b, i)
			if pid != "":
				var n := b.shelve(empire.carried, i, pid, empire.carried.qty(pid))
				empire.stats["units_shelved"] = int(empire.stats["units_shelved"]) + n
				empire._check_goals()
				Sfx.play("drop", -6.0, 1.3)
				ui.float_text("+%d on shelf" % n, player.global_position + Vector3.UP * 2.0, Color(0.7, 0.9, 1.0))
				si.refresh_goods()
			else:
				ui.open_price(b, b.slots[i]["product"])
		"till":
			if floor and floor.player_serve(spot["till"]):
				Sfx.play("click", -4.0)
		"rack":
			if not empire.carried.is_empty():
				var moved := 0
				for pid2 in empire.carried.units.keys():
					moved += Stock.transfer(empire.carried, b.backroom, pid2, empire.carried.qty(pid2))
				if not empire.carried.is_empty():
					ui.toast("The stockroom is full", "warn")
				if moved > 0:
					Sfx.play("drop", -6.0)
				si.refresh_goods()
			else:
				ui.open_rack(b)
		"office":
			ui.open_manage(b)
		"door":
			b.open = not b.open
			Sfx.play("bell", -8.0)
			_refresh_signs(si.unit["id"])
			ui.toast("%s is %s" % [b.name, "OPEN" if b.open else "CLOSED"], "info")
		"clean":
			b.cleanliness = minf(b.cleanliness + 0.34, 1.0)
			Sfx.play("pickup", -10.0, 1.6)
			si.refresh_goods()
		"trade":
			ui.open_wholesale(si.unit)
		"pallet":
			var pal := _pallet(si.unit["id"])
			var pid3: String = pal.units.keys()[0]
			var take := mini(pal.qty(pid3), EmpireData.case_qty(pid3))
			var got := Stock.transfer(pal, empire.carried, pid3, take)
			if got > 0:
				Sfx.play("pickup", -6.0)
			si.refresh_goods(pal)
		"letboard":
			if CityLife.is_rival(empire, spot["unit"]):
				ui.open_rival(unit_by_id[spot["unit"]])
			elif CityLife.is_firm(empire, spot["unit"]):
				ui.open_firm(unit_by_id[spot["unit"]])
			else:
				ui.open_property(unit_by_id[spot["unit"]])
		"home_lift":
			if empire.owns_property(spot["home"]):
				var h: Dictionary = home_by_id(spot["home"])["h"]
				_teleport(Apartments.spawn_point(h), atan2(Apartments.outward(h).x, Apartments.outward(h).z) + PI)
				Sfx.play("bell", -8.0)
			else:
				ui.open_home(home_by_id(spot["home"]))
		"home_down":
			var home2 := home_by_id(spot["home"])
			var l := home_lift(home2)
			_teleport(l + Apartments.outward(home2["h"]) * 1.5 + Vector3.UP * 1.0, atan2(-Apartments.outward(home2["h"]).x, -Apartments.outward(home2["h"]).z) + PI)
			Sfx.play("bell", -8.0)
		"home_bed":
			sleep_until(7.0)
			save_game()
		"car_door":
			enter_vehicle(spot["vehicle"])
		"car_boot":
			_boot_action(spot["vehicle"])


func _boot_action(vid: String) -> void:
	var v := empire.vehicle(vid)
	var cargo: Stock = v["cargo"]
	if not empire.carried.is_empty():
		var moved := 0
		for pid in empire.carried.units.keys():
			moved += Stock.transfer(empire.carried, cargo, pid, empire.carried.qty(pid))
		if not empire.carried.is_empty():
			ui.toast("The boot is full (%d cases)" % cargo.case_capacity, "warn")
		if moved > 0:
			Sfx.play("drop", -5.0, 0.8)
		return
	var bay := _bay_near(cars[vid].global_position)
	if bay != "" and not _pallet(bay).is_empty():
		var pal := _pallet(bay)
		var moved2 := Stock.transfer_all(pal, cargo)
		var n := 0
		for k in moved2:
			n += Stock.cases_for(k, moved2[k])
		ui.toast("Loaded %d case%s into the %s%s" % [n, "" if n == 1 else "s", EmpireData.vehicle_model(v["model"])["name"],
			"" if pal.is_empty() else " — it's full, %d left on the bay" % pal.cases_used()], "good" if pal.is_empty() else "warn")
		Sfx.play("drop", -4.0, 0.8)
		if interiors.has(bay):
			interiors[bay].refresh_goods(pal)
		return
	if cargo.is_empty():
		return
	# Take one case of whatever there's most of.
	var best := ""
	for pid2 in cargo.units:
		if best == "" or cargo.qty(pid2) > cargo.qty(best):
			best = pid2
	var got := Stock.transfer(cargo, empire.carried, best, mini(cargo.qty(best), EmpireData.case_qty(best)))
	if got > 0:
		Sfx.play("pickup", -6.0)


## The wholesaler whose collection bay is within 14 m of p ("" none).
func _bay_near(p: Vector3) -> String:
	for id in interiors:
		var si: ShopInterior = interiors[id]
		if si.kind == "wholesale" and si.to_world(si.rack_pos).distance_to(p) < 14.0:
			return id
	return ""


# ---------------------------------------------------------------- carry
var _carry_count := -1


func _update_carry_visual() -> void:
	var n := empire.carried.cases_used()
	var list: Array = []
	for pid in empire.carried.units:
		for c in Stock.cases_for(pid, empire.carried.qty(pid)):
			list.append(pid)
	if n != _carry_count:
		_carry_count = n
		for c in carry_node.get_children():
			c.queue_free()
		for i in list.size():
			var mi := MeshInstance3D.new()
			mi.mesh = ShopInterior.shape_mesh("case")
			var m := StandardMaterial3D.new()
			m.albedo_color = EmpireData.colour(list[i]).lerp(Color(0.72, 0.56, 0.36), 0.55)
			m.roughness = 0.85
			mi.material_override = m
			mi.position = Vector3(0, i * 0.33, 0)
			mi.rotation.y = 0.08 * float(i % 2) - 0.04
			carry_node.add_child(mi)
		rig.carrying = n > 0
	carry_node.visible = n > 0 and driving == ""
	if n > 0:
		var yaw := rig.global_rotation.y if rig else player.global_rotation.y
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		carry_node.global_position = player.global_position + fwd * 0.42 + Vector3.UP * 0.05
		carry_node.global_rotation = Vector3(0.0, yaw, 0.0)


# -------------------------------------------------------------- vehicles
func _car_spec(model: String) -> Dictionary:
	var m := EmpireData.vehicle_model(model)
	var s: Dictionary
	if String(m.get("base", "civ")) == "civ":
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		s = CarCatalog.civ_spec(String(m["body"]), rng)
		s["engine"] = 5.2
	else:
		s = CarCatalog.spec(String(m["base"]))
	s["top_speed"] = float(m.get("top_speed", s["top_speed"]))
	s["paint"] = Color.from_string(String(m.get("paint", "#cccccc")), Color.WHITE)
	s["nitro"] = 0.0
	return s


func _spawn_cars() -> void:
	for id in cars:
		cars[id].queue_free()
	cars.clear()
	for v in empire.vehicles:
		_spawn_car(v)


func _spawn_car(v: Dictionary) -> Car:
	var c := Car.new()
	c.name = "Car_" + String(v["id"])
	c.setup(_car_spec(v["model"]), "player")
	add_child(c)
	var vis := CarVisual.new()
	c.add_child(vis)
	vis.setup(c)
	c.visual = vis
	var p := Vector3(float(v["pos"][0]), float(v["pos"][1]), float(v["pos"][2]))
	c.place(Transform3D(Basis(Vector3.UP, float(v.get("yaw", 0.0))), p + Vector3.UP * 0.3))
	cars[v["id"]] = c
	vfx.cars = cars.values()
	return c


func enter_vehicle(vid: String) -> void:
	var c: Car = cars.get(vid)
	if c == null:
		return
	driving = vid
	player.input_enabled = false
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.collision_layer = 0
	drive_input.car = c
	drive_input.enabled = true
	chase.set_target(c, true)
	chase.cam.make_current()
	world.set_viewer(chase)
	_last_car_pos = c.global_position
	if c.visual:
		c.visual.enable_headlights(false)
	Sfx.play("click", -6.0)


func exit_vehicle() -> void:
	var c: Car = cars.get(driving)
	if c == null:
		driving = ""
		return
	if Vector2(c.linear_velocity.x, c.linear_velocity.z).length() > 4.0:
		ui.toast("Slow down to get out", "warn")
		return
	var v := empire.vehicle(driving)
	var xf := c.global_transform
	v["pos"] = [xf.origin.x, xf.origin.y, xf.origin.z]
	v["yaw"] = xf.basis.get_euler().y
	var side := xf * Vector3(-c.spec["size"].x * 0.5 - 0.9, 0.0, -0.2)
	drive_input.enabled = false
	drive_input.car = null
	c.throttle = 0.0
	c.brake = 1.0
	c.handbrake = true
	driving = ""
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.visible = true
	player.collision_layer = 1 << 2
	player.respawn(Vector3(side.x, maxf(side.y, xf.origin.y) + 0.9, side.z))
	player.input_enabled = true
	camera.face(xf.basis.get_euler().y)
	camera.cam.make_current()
	world.set_viewer(camera)


func _track_driving() -> void:
	var c: Car = cars.get(driving)
	if c == null:
		return
	var p := c.global_position
	_km_acc += p.distance_to(_last_car_pos) / 1000.0
	_last_car_pos = p
	if _km_acc > 0.05:
		empire.drive(empire.vehicle(driving), _km_acc)
		_km_acc = 0.0
	# Keep the hero with the car (streaming, interaction distances).
	player.global_position = p + Vector3.UP * 1.5
	if c.in_water and c.water_t > 2.0:
		_recover_car(c)


func _recover_car(c: Car) -> void:
	var p := c.global_position
	var g := _kerb_point(Vector3(p.x, 0.0, p.z))
	c.place(Transform3D(c.global_basis, g + Vector3.UP * 1.0))
	ui.toast("Towed out of the water (£60)", "warn")
	empire.pay(60.0, "vehicle", "Recovery")


func buy_vehicle(model: String) -> String:
	# Delivered to the kerb outside where you are.
	var p := player.global_position
	var yaw := camera.view_yaw()
	var spot_p := _kerb_point(p + Vector3(sin(yaw), 0, cos(yaw)) * 6.0)
	var v := empire.buy_vehicle(model, spot_p, yaw + PI * 0.5)
	if v.is_empty():
		return "Not enough money"
	_spawn_car(v)
	return ""


# -------------------------------------------------------------- business
func buy_firm(u: Dictionary) -> String:
	var err: Array = []
	var b := CityLife.buy_firm(empire, Premises.record(u), err)
	if b == null:
		return err[0] if not err.is_empty() else "Can't buy it"
	_sync_rivals()
	rebuild_interior(u["id"])
	Sfx.play("cash", -2.0)
	save_game()
	return ""


func buy_out_rival(u: Dictionary) -> String:
	var err: Array = []
	var b := CityLife.buy_out(empire, Premises.record(u), err)
	if b == null:
		return err[0] if not err.is_empty() else "Can't buy it"
	_sync_rivals()
	rebuild_interior(u["id"])
	Sfx.play("cash", -2.0)
	save_game()
	return ""


func rent_unit(u: Dictionary, buy := false) -> String:
	var b := empire.buy_premises(Premises.record(u)) if buy else empire.rent_premises(Premises.record(u))
	if b == null:
		return "Not enough money"
	rebuild_interior(u["id"])
	save_game()
	return ""


func buy_wholesale(u: Dictionary, order: Dictionary, sack_truck := false) -> String:
	var err := empire.buy_wholesale(u["id"], order)
	if err == "" and interiors.has(u["id"]):
		interiors[u["id"]].refresh_goods(_pallet(u["id"]))
	if err == "":
		Sfx.play("cash", -4.0)
	return err


func buy_upgrade(b: Business, up: String) -> String:
	var err := empire.buy_upgrade(b, up)
	if err == "":
		rebuild_interior(b.premises["id"])
		Sfx.play("chime", -4.0)
	return err


func hire(b: Business, cand: Dictionary) -> void:
	if empire.hire(b, cand) and floor and floor.biz == b:
		floor.sync_staff()


func fire(b: Business, e: Dictionary) -> void:
	empire.fire(b, e)
	if floor and floor.biz == b:
		floor.sync_staff()


func take_case(b: Business, pid: String) -> void:
	var n := mini(b.backroom.qty(pid), EmpireData.case_qty(pid))
	var got := Stock.transfer(b.backroom, empire.carried, pid, n)
	if got == 0:
		ui.toast("Hands full", "warn")
	else:
		Sfx.play("pickup", -6.0)
	if interiors.has(b.premises["id"]):
		interiors[b.premises["id"]].refresh_goods()


func gps_target() -> Vector3:
	var t = empire.flags.get("gps", null)
	if t is Array and (t as Array).size() == 3:
		return Vector3(t[0], t[1], t[2])
	return Vector3.INF


func set_gps(p: Vector3, label: String) -> void:
	empire.flags["gps"] = [p.x, p.y, p.z]
	empire.flags["gps_label"] = label


func clear_gps() -> void:
	empire.flags.erase("gps")
	empire.flags.erase("gps_label")


func sleep_until(hour: float) -> void:
	# Fast-forward (the model runs every shop meanwhile).
	_end_floor()
	var target := hour * 60.0
	var mins := fposmod(target - empire.minute, 1440.0)
	empire.advance(mins)
	ui.toast("It's %s %s" % [empire.weekday(), empire.clock_text()], "info")


# ---------------------------------------------------------------- homes
## CitySwing's five apartments (real rooms high in real towers) are the
## homes you can buy: a lift from the street, a bed to sleep in, or let
## them out for daily rent.
const HOME_PRICES := [18000.0, 42000.0, 85000.0, 160000.0, 350000.0]


func homes() -> Array:
	var out: Array = []
	if layout.apartments == null:
		return out
	for h in layout.apartments.homes:
		out.append({"id": "home_" + String(h["id"]), "kind": "home", "name": String(h["name"]),
			"price": HOME_PRICES[clampi(int(h["tier"]), 0, 4)], "tier": int(h["tier"]), "h": h,
			"floor": Apartments.floor_height(h), "district": "east:" + layout.district(Apartments.window_center(h).x,
			Apartments.window_center(h).z)})
	return out


## Street door of a home's tower (below its window, on the pavement).
func home_lift(home: Dictionary) -> Vector3:
	var h: Dictionary = home["h"]
	var c := Apartments.window_center(h) + Apartments.outward(h) * 1.6
	return Vector3(c.x, layout.ground_y(c.x, c.z), c.z)


func _home_spots(p: Vector3, best: Dictionary, best_d: float) -> Array:
	for home in homes():
		var lift := home_lift(home)
		var d := Vector2(p.x, p.z).distance_to(Vector2(lift.x, lift.z))
		if d < 2.2 and absf(p.y - 0.9 - lift.y) < 2.0 and d < best_d:
			best = {"kind": "home_lift", "home": home["id"], "world": lift}
			best_d = d
		if empire.owns_property(home["id"]):
			var h: Dictionary = home["h"]
			var up := Apartments.spawn_point(h) - Vector3.UP * 0.95
			var d2 := p.distance_to(up + Vector3.UP * 0.95)
			if d2 < 1.6 and d2 < best_d:
				best = {"kind": "home_down", "home": home["id"], "world": up}
				best_d = d2
			for sp in HomeInteriors.spots.get(String(h["id"]), []):
				if sp["kind"] == "bed":
					var d3 := p.distance_to(sp["pos"] + Vector3.UP * 0.95)
					if d3 < 1.8 and d3 < best_d:
						best = {"kind": "home_bed", "home": home["id"], "world": sp["pos"]}
						best_d = d3
	return [best, best_d]


func home_by_id(id: String) -> Dictionary:
	for h in homes():
		if h["id"] == id:
			return h
	return {}


# -------------------------------------------------------------- tutorial
## The opening objectives, in order, shown on the HUD with a GPS target.
func objective() -> Array:
	var start: Dictionary = unit_by_id.get(empire.flags.get("start_unit", ""), starter_unit())
	if empire.businesses.is_empty():
		return ["Rent %s – walk up to the TO LET sign" % String(start.get("shop_name", "the shop")), Premises.door_point(start)]
	var b: Business = empire.businesses[0]
	var w := wholesaler(b.island())
	if int(empire.stats["cases_bought"]) == 0:
		return ["Drive to %s and buy stock" % String(w.get("name", "the wholesaler")), Premises.door_point(w)]
	var pal := _pallet(w.get("id", ""))
	var in_cars := 0
	for v in empire.vehicles:
		in_cars += (v["cargo"] as Stock).total_units()
	if not pal.is_empty() and in_cars == 0 and empire.carried.is_empty() and b.stock_units() == 0:
		return ["Collect your goods from the collection bay (park by it, use the boot)", Premises.door_point(w)]
	if b.stock_units() == 0:
		return ["Take the stock to %s and carry it in" % b.name, Premises.door_point(unit_by_id.get(b.premises["id"], start))]
	if int(empire.stats["sales"]) == 0:
		if b.shelf_units() == 0:
			return ["Put stock on the shelves (carry a case to a shelf)", Vector3.INF]
		return ["Serve customers at the till", Vector3.INF]
	var g: Array = empire.current_goals(1)
	if (g[1] as Array).is_empty():
		return ["Build your empire", Vector3.INF]
	return [String(g[0]) + ": " + String(g[1][0]["text"]), Vector3.INF]


func _tutorial_step() -> void:
	pass


# ------------------------------------------------------------------ save
func save_game() -> void:
	if empire == null or state == "boot":
		return
	# Vehicles' positions and the hero's, then the economy.
	for v in empire.vehicles:
		var c: Car = cars.get(v["id"])
		if c and is_instance_valid(c):
			v["pos"] = [c.global_position.x, c.global_position.y, c.global_position.z]
			v["yaw"] = c.global_basis.get_euler().y
	var d := {"empire": empire.to_dict(), "player": [player.global_position.x, player.global_position.y,
		player.global_position.z, camera.view_yaw()], "driving": driving, "saved_at": Time.get_datetime_string_from_system()}
	if driving != "":
		var c2: Car = cars[driving]
		var side := c2.global_transform * Vector3(-c2.spec["size"].x * 0.5 - 0.9, 0.9, 0.0)
		d["player"] = [side.x, side.y, side.z, camera.view_yaw()]
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("City Empire: cannot write the save")
		return
	f.store_string(JSON.stringify(d))
	f.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_PATH + ".bak"))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(SAVE_PATH))


func load_game() -> bool:
	var d = null
	for p in [SAVE_PATH, SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			d = JSON.parse_string(f.get_as_text()) if f else null
			if d is Dictionary and (d as Dictionary).has("empire"):
				break
			d = null
	if d == null:
		new_game()
		return false
	empire = Empire.from_dict(d["empire"])
	empire.market = _market()
	if not empire.flags.has("start_unit"):
		empire.flags["start_unit"] = starter_unit()["id"]
	CityLife.ensure_firms(empire)
	_connect_empire()
	_rival_sig = "?"
	_spawn_cars()
	var pp: Array = d.get("player", [])
	if pp.size() >= 4:
		_teleport(Vector3(pp[0], pp[1], pp[2]) + Vector3.UP * 0.2, float(pp[3]))
	else:
		var s := starter_unit()
		_teleport(Premises.door_point(s) + Premises.outward(s) * 3.0 + Vector3.UP, 0.0)
	for id in interiors.keys():
		rebuild_interior(id)
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if state == "play":
			save_game()


# ------------------------------------------------------- captures/tests
func _demo_setup(kind: String) -> void:
	# A running shop for captures: rented, stocked, prices set, a till queue.
	var u := starter_unit()
	if empire.business_at(u["id"]) == null:
		empire.personal_cash = 6000.0
		rent_unit(u)
	var b := empire.business_at(u["id"])
	var order := {}
	for pid in ["crisps", "choc_bar", "gummies", "cola", "water", "energy", "milk", "bread", "beans", "pasta", "loo_roll", "tea"]:
		order[pid] = 2
	empire.buy_wholesale("demo", order)
	var pal: Stock = empire.pallets["demo"]
	for pid in order:
		Stock.transfer(pal, b.backroom, pid, pal.qty(pid))
	empire.restock_from_backroom(b, 2000)
	if kind == "carry":
		Stock.transfer(b.backroom, empire.carried, "cola", 48)
	if kind == "staff":
		for c in empire.candidates.duplicate():
			if c["role"] in ["cashier", "stocker", "cleaner"]:
				empire.hire(b, c)
	b.cleanliness = 0.75
	rebuild_interior(u["id"])
	empire.minute = maxf(empire.minute, 9.0 * 60.0)


func _capture(path: String, at: float) -> void:
	await get_tree().create_timer(at).timeout
	await RenderingServer.frame_post_draw
	print("CAPTURE player=%s floor_unit=%s interiors=%d cam=%s" % [player.global_position, floor_unit, interiors.size(),
		get_viewport().get_camera_3d().global_position])
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)
	get_tree().quit()


func _selftest() -> void:
	var ok := units.size() > 10 and wholesaler("west").size() > 0 and empire != null
	ok = ok and player != null and cars.size() >= 1
	print("SELFTEST units=%d cars=%d %s" % [units.size(), cars.size(), "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
