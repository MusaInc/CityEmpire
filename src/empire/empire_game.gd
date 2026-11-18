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
var crowd: Crowd
var layout: CityLayout
var player: Player
var rig: CharacterRig
var camera: SwingCamera
var chase: ChaseCamera
var drive_input: DriveInput
var skyport: SkyportIsland
var skyport_play: SkyportPlay
var venues: Venues   # walk-in showrooms + clothes shops on Skyport
var vfx: VehicleFx
var audio: AudioDirector
var sfx: Sfx
var empire: Empire
var ui: EmpireUI
var gps: Gps
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
var _dry_pos := Vector3.INF   # the last dry ground the hero stood on (out of the sea)
var _wet_t := 0.0
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
	CityWorld.walker_crowd_radius = Crowd.NEAR
	SkyportIsland.enabled = true   # (before the world: the city opens its sea wall for the bridge)
	Landforms.enabled = true       # (headlands, beaches and a harbour along the strait)
	world = CityWorld.new()
	world.name = "World"
	add_child(world)
	layout = world.layout
	# Skyport Island (the third island: airport, logistics, high-rise, marina).
	SkyportIsland.enabled = true
	Venues.register()   # (the island carves their rooms out of its buildings)
	var t1 := Time.get_ticks_msec()
	skyport = SkyportIsland.new()
	skyport.name = "Skyport"
	add_child(skyport)
	skyport.build(layout, world)
	var lfn := Landforms.new()
	lfn.name = "Landforms"
	add_child(lfn)
	lfn.build(layout)
	skyport.viewer = func() -> Vector3: return vehicle_node().global_position if vehicle_node() else player.global_position
	print("Skyport Island: %d ms" % (Time.get_ticks_msec() - t1))
	EmpireMinimap.bake.call_deferred(self, layout)  # (the minimap's and phone map's city image)
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
	# Cars are solid to walk into (you stop against the door, you don't walk
	# into the hull); parked ones are park_lock'ed so it doesn't shove them.
	player.collision_mask |= Car.BODY_LAYER
	player.ground_fn = layout.ground_y
	player.add_to_group("door_openers")  # the stockroom door opens for you
	player.steer_fn = _door_assist
	rig = CharacterRig.new()
	rig.name = "Rig"
	player.add_child(rig)
	rig.set_player(player)
	rig.apply_look(HeroLook.build(HeroLook.DEFAULT))
	# The people on the pavements round you (the GPU walkers carry the far streets).
	crowd = Crowd.new()
	crowd.name = "Crowd"
	add_child(crowd)
	crowd.setup(self)
	camera = SwingCamera.new()
	camera.name = "CameraRig"
	add_child(camera)
	camera.set_target(player)
	camera.distance_scale = 0.76   # closer than the swing camera: street level (0.62 felt cramped)
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
	# Skyport Island's showrooms, aircraft and boats (needs the UI's touch pad).
	skyport_play = SkyportPlay.new()
	skyport_play.name = "SkyportPlay"
	add_child(skyport_play)
	skyport_play.setup(self)
	venues = Venues.new()
	venues.name = "Venues"
	add_child(venues)
	venues.setup(self)
	# The one GPS route (both maps draw it); its road graph builds on a thread.
	gps = Gps.new()
	gps.name = "Gps"
	add_child(gps)
	gps.setup(self)

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
		if g == "hq":
			u = hq_unit()
		if g == "rival" and not empire.rivals.is_empty():
			u = unit_by_id.get(empire.rivals[0]["unit"], {})
		if g.begins_with("type:"):
			# Captures: the independent of that kind nearest the starter shop.
			var want := g.get_slice(":", 1)
			var s1 := starter_unit()
			var bd := INF
			for f in empire.firms:
				if String(f.get("type", "")) == want and CityLife._dist(f["pos"], s1["pos"]) < bd:
					bd = CityLife._dist(f["pos"], s1["pos"])
					u = unit_by_id.get(f["unit"], {})
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
		if not u.is_empty() and args.has("front"):
			# Captures: a camera square-on to the shopfront, `front` m out.
			var fd := float(args["front"])
			var fu := u
			camera.cine = func(_dt: float) -> Array:
				var dp := Premises.door_point(fu) + Vector3.UP * (2.3 + float(args.get("front-up", "0")))
				var from := dp + Premises.outward(fu) * fd + Premises.along_dir(fu) * fd * 0.25 \
					- Vector3.UP * float(args.get("front-up", "0")) * 0.6
				return [Transform3D(Basis.looking_at(dp - from, Vector3.UP), from), 62.0]
		if not u.is_empty() and args.has("stockroom"):
			# Captures: inside the shop, looking at the stockroom wall/door
			# ("in": from inside the stockroom, looking at the racking).
			var su := u
			var sv := String(args["stockroom"])
			camera.cine = func(_dt: float) -> Array:
				var si: ShopInterior = interiors.get(su["id"])
				if si == null:
					return [camera.cam.global_transform, 62.0]
				var pd := si.D - ShopInterior.BACKROOM
				var from := si.to_world(ShopInterior.R(si.W * 0.5, pd - 4.2, 1.7))
				var to := si.to_world(ShopInterior.R(si.W - 1.6, pd, 1.55))
				if sv == "in":
					from = si.to_world(ShopInterior.R(si.W * 0.55, pd + 0.3, 2.3))
					to = si.to_world(ShopInterior.R(si.W * 0.3, si.D, 0.7))
				return [Transform3D(Basis.looking_at(to - from, Vector3.UP), from), 66.0]
		if not u.is_empty() and args.has("roomcam"):
			# Captures: the whole shop floor from high in a back corner, looking
			# at the door and tills ("roomcam=front": from by the door, inward).
			var ru := u
			var rv := String(args["roomcam"])
			camera.cine = func(_dt: float) -> Array:
				var si: ShopInterior = interiors.get(ru["id"])
				if si == null:
					return [camera.cam.global_transform, 62.0]
				var pd := si.D - ShopInterior.BACKROOM
				var from := si.to_world(ShopInterior.R(0.35, pd - 0.3, 2.75))
				var to := si.to_world(ShopInterior.R(si.W * 0.62, 0.6, 0.5))
				if rv == "till" and not si.queue.is_empty():
					# The queue and tills, from just behind the line.
					var q0: Vector3 = si.queue[0]
					var q3: Vector3 = si.queue[mini(3, si.queue.size() - 1)]
					# (From above the counter side: the aisle beside the queue is
					# a gondola.)
					from = si.to_world((q0 + q3) * 0.5 + Vector3(1.0, 2.6, 0) + (q3 - q0).normalized() * 1.5)
					to = si.to_world(q0 - (q3 - q0).normalized() * 0.4)
				if rv == "shelf":
					# Close on the left-wall shelving, at eye height.
					from = si.to_world(ShopInterior.R(2.3, 2.3, 1.6))
					to = si.to_world(ShopInterior.R(0.2, 3.6, 0.85))
				elif rv == "back":
					# Square on to the back wall (fridges / counters).
					from = si.to_world(ShopInterior.R(si.W * 0.4, pd - 3.4, 1.65))
					to = si.to_world(ShopInterior.R(si.W * 0.4, pd, 1.0))
				if rv == "front":
					from = si.to_world(ShopInterior.R(si.W - 0.4, 0.4, 2.7))
					to = si.to_world(ShopInterior.R(si.W * 0.35, pd - 0.5, 0.6))
				return [Transform3D(Basis.looking_at(to - from, Vector3.UP), from), 74.0]
		if not u.is_empty():
			var inside := args.has("inside")
			var p := Premises.door_point(u) + Premises.outward(u) * (-2.5 if inside else 3.0) + Vector3.UP * 1.0
			_teleport(p, atan2(Premises.outward(u).x, Premises.outward(u).z) + (PI if not inside else 0.0))
	if args.has("at"):
		# Captures: stand at world x,z (on the ground), facing yaw (deg).
		var av := String(args["at"]).split(",")
		var ax := float(av[0])
		var az := float(av[1])
		_teleport(Vector3(ax, layout.ground_y(ax, az) + 1.0, az), deg_to_rad(float(av[2]) if av.size() > 2 else 0.0))
	if args.has("drive") and not empire.vehicles.is_empty():
		# Captures/tests: sit in your first vehicle ("drive=<m>" first rolls
		# it that far up its lane so the shot isn't at the kerb).
		enter_vehicle(String(empire.vehicles[0]["id"]))
		if String(args["drive"]) != "" and String(args["drive"]) != "true":
			var dc: Car = cars.get(driving)
			if dc:
				dc.linear_velocity = -dc.global_basis.z * float(args["drive"])
	if args.has("home"):
		# Captures/tests: own a home and stand in it ("home=skyport_penthouse").
		var hm := home_by_id("home_" + String(args["home"]))
		if not hm.is_empty():
			if not empire.owns_property(hm["id"]):
				empire.properties.append({"id": hm["id"], "kind": "home", "name": hm["name"], "price": hm["price"], "let": false, "income": 0.0})
			var hh: Dictionary = hm["h"]
			_teleport(Apartments.spawn_point(hh), atan2(Apartments.outward(hh).x, Apartments.outward(hh).z) + PI)
	if args.has("own"):
		# Captures/tests: own these vehicles (free), in their usual places.
		for om in String(args["own"]).split(","):
			if SkyportPlay.vclass(om) == "car":
				var ov := empire.add_vehicle(om, player.global_position + Vector3(8, 0, 8), 0.0)
				_spawn_car(ov)
			else:
				var os := skyport_play.free_slot(SkyportPlay.vclass(om))
				skyport_play._spawn(empire.add_vehicle(om, os[0], os[1]))
		empire.personal_cash = maxf(empire.personal_cash, 250000.0)
	if args.has("fly"):
		# Captures/tests: own a craft (free) at its slot and get in.
		var fm := String(args["fly"])
		var slot := skyport_play.free_slot(SkyportPlay.vclass(fm))
		var fv := empire.add_vehicle(fm, slot[0], slot[1])
		skyport_play._spawn(fv)
		skyport_play.enter(String(fv["id"]))
		if args.has("fly-up"):
			# (Captures: climb and fly on for this long first.)
			skyport_play.script_input = {"active": true, "gas": 1.0, "kick": true, "brake": 0.0, "steer": 0.15}
			get_tree().create_timer(float(args["fly-up"])).timeout.connect(func():
				skyport_play.script_input = {"active": true, "gas": 1.0, "kick": false, "brake": 0.0, "steer": 0.0})
	if args.has("hour"):
		empire.minute = float(args["hour"]) * 60.0
	if args.has("brand"):
		# Captures: a sample house brand ("1") or "name,primary,accent,face,sign".
		var bp := String(args["brand"]).split(",")
		empire.brand = {"name": "Harbour & Co", "primary": "#0f3d5c", "accent": "#f5b13d", "face": "serif", "sign": "painted"} \
			if bp.size() < 5 else {"name": bp[0], "primary": "#" + bp[1], "accent": "#" + bp[2], "face": bp[3], "sign": bp[4]}
	if args.has("hq"):
		empire.hq = {"tier": int(args["hq"]), "paid": 0.0, "day": empire.day}
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
	if args.has("outfit"):
		# Captures: dress the hero through the normal look path, e.g.
		# --outfit="top=top_shirt;top_col=#d9822b;eyewear=face_shades;face=hero_ade"
		var pv := {}
		for kv in String(args["outfit"]).split(";"):
			if "=" in kv:
				pv[kv.get_slice("=", 0)] = kv.get_slice("=", 1)
		apply_hero_look(pv)
	if args.has("view"):
		# Captures: a fixed camera relative to the hero: "x,y,z,lx,ly,lz" offsets (m).
		var v := String(args["view"]).split(",")
		camera.cine = func(_dt: float) -> Array:
			var o := player.global_position
			var from := o + Vector3(float(v[0]), float(v[1]), float(v[2]))
			var to := o + Vector3(float(v[3]), float(v[4]), float(v[5]))
			return [Transform3D(Basis.looking_at(to - from, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD), from), 62.0]
	if args.has("nohud"):
		ui.visible = false   # (captures: the world only)
	if args.has("carcam") and not empire.vehicles.is_empty():
		# Captures: a fixed camera on your first car - front34, rear34, side,
		# side_l, front, rear, nose, tail - for checking the car in the game.
		var cc: Car = cars.get(String(empire.vehicles[0]["id"]))
		var views := {"front34": [Vector3(3.4, 1.3, -4.2), 0.55], "rear34": [Vector3(-3.4, 1.5, 4.4), 0.6],
			"side": [Vector3(6.2, 1.0, 0.0), 0.6], "side_l": [Vector3(-6.2, 1.0, 0.0), 0.6], "front": [Vector3(0.0, 1.0, -6.5), 0.55],
			"rear": [Vector3(0.0, 1.1, 6.5), 0.6], "nose": [Vector3(1.6, 1.0, -3.6), 0.5], "tail": [Vector3(-1.6, 1.15, 3.7), 0.6]}
		var vw: Array = views.get(String(args["carcam"]), views["front34"])
		camera.cine = func(_dt: float) -> Array:
			if cc == null or not is_instance_valid(cc):
				return [camera.global_transform, 62.0]
			var from := cc.global_transform * (vw[0] as Vector3)
			var to := cc.global_transform * Vector3(0, float(vw[1]), 0)
			return [Transform3D(Basis.looking_at(to - from, Vector3.UP), from), 50.0]
	if args.has("cam"):
		# Captures: a fixed camera in world metres, "x,y,z,lx,ly,lz" (unlike
		# --view, independent of where the hero lands; y is above the ground).
		var cv := String(args["cam"]).split(",")
		var gy := func(x: float, z: float) -> float: return layout.ground_y(x, z)
		var cfrom := Vector3(float(cv[0]), float(cv[1]) + float(gy.call(float(cv[0]), float(cv[2]))), float(cv[2]))
		var cto := Vector3(float(cv[3]), float(cv[4]) + float(gy.call(float(cv[3]), float(cv[5]))), float(cv[5]))
		camera.cine = func(_dt: float) -> Array:
			return [Transform3D(Basis.looking_at(cto - cfrom, Vector3.UP), cfrom), 62.0]
	if args.has("days"):
		# Captures: run the economy forward (news, rivals, a net-worth history).
		for i in int(args["days"]):
			empire.advance(1440.0)
		ui.close_panel(true)
	if args.has("gps"):
		# Captures/tests: a route to a unit id, "wholesale:<island>" or "car".
		gps.wait_net()
		var gid := String(args["gps"])
		if gid == "car":
			ui.find_vehicle(String(empire.vehicles[0]["id"]))
			ui.close_panel(true)
		else:
			var gu: Dictionary = wholesaler(gid.get_slice(":", 1)) if gid.begins_with("wholesale") else unit_by_id.get(gid, {})
			if not gu.is_empty():
				set_gps(Premises.door_point(gu), String(gu.get("name", gid)), {"kind": "unit", "id": String(gu["id"])})
	if args.has("mapview"):
		# Captures: the full map's centre and zoom, "x,z,zoom".
		var mv := String(args["mapview"]).split(",")
		EmpireMap._view = {"c": Vector2(float(mv[0]), float(mv[1])), "z": float(mv[2])}
	if args.has("panel"):
		var pn := String(args["panel"])
		if pn == "victory":
			ui.victory()
		elif pn == "rival" and not empire.rivals.is_empty():
			ui.open_rival(unit_by_id[empire.rivals[0]["unit"]])
		elif pn == "firm" and not empire.firms.is_empty():
			var fs2 := CityLife.firms_for_sale(empire)
			ui.open_firm(unit_by_id[(fs2[0] if not fs2.is_empty() else empire.firms[0])["unit"]])
		elif pn.begins_with("style"):
			ui._style_tab = pn.get_slice(":", 1) if ":" in pn else "you"
			ui.open_style()
		elif pn == "brand":
			ui.open_brand()
		elif pn == "hq":
			ui.open_hq()
		elif pn == "report":
			empire.advance(1440.0 - empire.minute + 1.0)
		elif pn == "wholesale":
			ui.open_wholesale(wholesaler("west"))
		elif pn in ["stock", "staff"] and not empire.businesses.is_empty():
			ui.open_manage(empire.businesses[0], pn)
		else:
			ui.open_phone(pn)
	if args.has("shot"):
		_capture(String(args["shot"]), float(args.get("shot-at", "4")))
	if args.has("selftest"):
		_selftest.call_deferred()
	if args.has("scenarios"):
		var sc: Node = load("res://src/empire/dev/scenarios.gd").new()
		sc.set("game", self)
		add_child(sc)
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
	_obj_sig = ""
	gps.restore()
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


var _brand_sig := "?"
var _crown: Node3D


## Your brand and head office in the world: ShopStyle's house brand, your
## shops' and the lobby's signs, and the tower crown (rebuilt when changed).
func _sync_brand() -> void:
	var sig := "%s|%d" % [JSON.stringify(empire.brand), empire.hq_tier()]
	if sig == _brand_sig:
		return
	var first := _brand_sig == "?"
	_brand_sig = sig
	ShopStyle.house = empire.brand.duplicate()
	ShopStyle.hq_tier = empire.hq_tier()
	_update_crown()
	if first:
		return
	for id in interiors.keys():
		var u: Dictionary = unit_by_id.get(id, {})
		if u.get("kind") == "hq" or empire.business_at(id) != null:
			rebuild_interior(id)


func hq_unit() -> Dictionary:
	for u in units:
		if u["kind"] == "hq":
			return u
	return {}


## Your name in lights round the top of Meridian Tower (the whole tower).
func _update_crown() -> void:
	if _crown:
		_crown.queue_free()
		_crown = null
	var u := hq_unit()
	if u.is_empty() or empire.hq_tier() < 3:
		return
	var hi := ShopStyle.house_ident(empire.brand) if not empire.brand.is_empty() else {}
	var text := String(hi.get("name", "")) if not hi.is_empty() else "HEAD OFFICE"
	if text == "":
		text = "HEAD OFFICE"
	if String(hi.get("face", "")) not in ["script", "retro"]:
		text = text.to_upper()
	var b: Dictionary = u["b"]
	var top: Array = b["tiers"][0]
	for t in b["tiers"]:
		if float(t[5]) > float(top[5]):
			top = t
	var xf := CityLayout.bxf(b)
	_crown = Node3D.new()
	_crown.name = "TowerCrown"
	add_child(_crown)
	for k in 4:
		var f := BuildingMesher._face(top, k)
		var flen: float = f[3]
		var p := xf * BuildingMesher._fpt(f, flen * 0.5, 0.35, float(top[5]) - 7.0)
		var out := (xf.basis * (f[2] as Vector3)).normalized()
		var l := Label3D.new()
		l.text = text
		l.font = ShopStyle.font(String(hi.get("face", "display")))
		l.font_size = 220
		l.outline_size = 0
		l.pixel_size = (flen * 0.78) / maxf(text.length() * 0.62 * 220.0, 1.0)
		l.shaded = false
		l.double_sided = false
		l.modulate = (hi.get("accent", Color(1.0, 0.85, 0.5)) as Color) * 1.15
		l.visibility_range_end = 0.0
		_crown.add_child(l)
		l.global_transform = Transform3D(Basis.looking_at(-out, Vector3.UP), p)
		print("CROWN ", k, " ", p, " flen=", flen, " ps=", l.pixel_size, " door=", Premises.door_point(u))


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
	apply_hero_look()
	_brand_sig = "?"
	_sync_brand()
	empire.notified.connect(func(t, k): ui.toast(t, k, empire.last_ref))
	empire.day_ended.connect(func(r):
		ui.day_report(r)
		save_game())
	empire.sold.connect(func(_b, amt): pass)
	empire.goal_done.connect(func(_g): Sfx.play("chime", -4.0))
	empire.won.connect(func():
		Sfx.play("chime", -2.0)
		save_game()
		ui.victory())


## Dress the hero as the empire's saved look (HeroLook).
func apply_hero_look(preview := {}) -> void:
	var l := HeroLook.current(empire.flags if empire else {})
	l.merge(preview, true)
	rig.apply_look(HeroLook.build(l))


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
	if empire.flags.get("intro_done", false) == false and not args.has("shot") and not args.has("autoplay") and not args.has("perf") \
			and not args.has("scenarios"):
		ui.intro()
	if not DisplayServer.is_touchscreen_available() and not args.has("touch") and not args.has("shot"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _teleport(p: Vector3, yaw: float) -> void:
	if skyport and SkyportIsland.distance_to(p) < SkyportIsland.NEAR_LOAD and not skyport.near_loaded():
		skyport.load_near_now()   # (arriving at once: its buildings must be solid now)
	if venues:
		venues.load_near_now(p)
	player.respawn(p)
	player.last_safe_position = p
	_dry_pos = p
	_wet_t = 0.0
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
		_sync_brand()
		_stream_interiors()
		_update_live_floor()
		if state == "play":
			_objective_gps()
			_update_stadium()
	if state != "play":
		return
	_update_spot()
	_update_indoors()
	if floor and floor.room:
		# (Shoppers and staff step round you.)
		floor.hero_at = floor.room.to_local(player.global_position) if driving == "" else Vector3.INF
	_update_carry_visual()
	if driving != "":
		_track_driving()
	elif skyport_play and skyport_play.piloting != "":
		skyport_play.track(dt)
	else:
		_check_wading(dt)
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
	if u["kind"] == "office":
		si.office = Offices.at(empire, u["id"])
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
		si.update_signs(h >= 7.0 and h < (22.0 if si.rival.get("firm", false) else 23.0), h < 6.5 or h >= 21.5)
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


## Walking at a shop door, in or out: the direction bends towards the middle
## of the doorway, so cutting the corner doesn't catch the door frame (and
## stumble you at a run). Only within ~60° of the doorway and close to it;
## walking along the pavement past a door is left alone.
func _door_assist(move: Vector3) -> Vector3:
	var p := player.global_position
	var mlen := move.length()
	for id in interiors:
		var si: ShopInterior = interiors[id]
		if si.kind == "hq" or si.kind == "office":
			continue
		var o := si.global_transform.origin
		if absf(o.y - (p.y - 0.9)) > 1.6 or Vector2(o.x - p.x, o.z - p.z).length() > si.W + 6.0:
			continue
		var inv := si.global_transform.affine_inverse()
		var l := inv * p
		var d := -l.z  # depth into the room (negative outside)
		var cx := (si.door.x + si.door.y) * 0.5
		var hw := (si.door.y - si.door.x) * 0.5
		if d < -2.8 or d > 1.8 or absf(l.x - cx) > hw + 2.0:
			continue
		var lm := inv.basis * move
		lm.y = 0.0
		var inward := lm.z < 0.0
		# Aim: line up on the doorway's middle just before the frame, then
		# straight through (a stride past it).
		var aim := Vector3(cx, 0.0, -1.2 if inward else 1.5)
		if inward and d < -0.55:
			aim.z = 0.25
		elif not inward and d > 1.0:
			aim.z = -0.6
		var to_aim := Vector3(aim.x - l.x, 0.0, aim.z - l.z)
		if to_aim.length() < 0.3:
			continue
		to_aim = to_aim.normalized()
		var md := lm.normalized()
		var cosang := md.dot(to_aim)
		if cosang < 0.5:
			continue
		# Strongest right at the frame, fading out over ~2 m either side;
		# nothing needed when you're already well inside the opening.
		var near := 1.0 - clampf((absf(d) - 0.4) / 2.2, 0.0, 1.0)
		var off := clampf((absf(l.x - cx) - (hw - 0.65)) / 0.5, 0.0, 1.0)
		var k := near * maxf(off, 0.35) * smoothstep(0.5, 0.8, cosang)
		if k <= 0.01:
			continue
		var nd := md.slerp(to_aim, k).normalized()
		return (si.global_transform.basis * nd).normalized() * mlen
	return move


## Inside a shop, office lobby or warehouse: indoor walking (a brisk walk,
## quick turns) and the camera brought in under the ceiling. Every frame, so
## the change happens as you cross the threshold, not up to 0.4 s later.
func _update_indoors() -> void:
	var ceiling := INF
	if driving == "":
		var p := player.global_position
		for id in interiors:
			var si: ShopInterior = interiors[id]
			if si.global_transform.origin.distance_squared_to(p) < 2500.0 and si.contains(p):
				ceiling = si.global_transform.origin.y + si.H
				break
		if ceiling == INF and venues:
			ceiling = venues.ceiling_at(p)
	player.indoors = ceiling < INF
	camera.indoor_ceiling = ceiling
	if atmosphere.rain_fx:
		atmosphere.rain_fx.sheltered = ceiling < INF
	_hero_fill(ceiling < INF)


## Indoors the building shadows the sun and the hero (dark clothes, deep skin
## tones) went to a silhouette against bright shelving. A soft light on the
## camera's side that lights only the hero (its own render layer), faded in
## while you're inside.
const HERO_LAYER := 1 << 19
var _fill: OmniLight3D
var _fill_e := 0.0


func _hero_fill(on: bool) -> void:
	if _fill == null:
		_fill = OmniLight3D.new()
		_fill.name = "HeroFill"
		_fill.light_cull_mask = HERO_LAYER
		_fill.shadow_enabled = false
		_fill.omni_range = 5.0
		_fill.omni_attenuation = 0.6
		_fill.light_color = Color(1.0, 0.96, 0.9)
		_fill.light_specular = 0.2
		add_child(_fill)
	if rig.skeleton:
		for mi in rig.skeleton.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).layers |= HERO_LAYER
	_fill_e = move_toward(_fill_e, 1.0 if on else 0.0, get_process_delta_time() * 2.0)
	_fill.visible = _fill_e > 0.01
	if _fill.visible:
		var h := player.global_position + Vector3.UP * 0.4
		var c := camera.cam.global_position
		var to_c := Vector3(c.x - h.x, 0.0, c.z - h.z).normalized()
		_fill.global_position = h + to_c * 1.6 + to_c.cross(Vector3.UP) * 0.6 + Vector3.UP * 1.0
		_fill.light_energy = 1.1 * _fill_e


func _end_floor() -> void:
	if floor:
		floor.queue_free()
		floor = null
	floor_unit = ""


func current_business() -> Business:
	return empire.business_at(floor_unit) if floor_unit != "" else null


# ---------------------------------------------------------------- spots
const CAR_REACH := 1.7  # metres from the bodywork that still reach a door or the boot


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
				var reach := REACH * (1.4 if s["kind"] in ["trade", "pallet", "office", "hq_desk", "office_desk", "club_office"] else 1.0)
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
		# Carrying cases in your own shop with nothing else at hand: put them
		# down (they stack by the door).
		if best.is_empty() and not empire.carried.is_empty():
			for id in interiors:
				var si2: ShopInterior = interiors[id]
				if si2.kind == "shop" and si2.biz != null and si2.rival.is_empty() and empire.business_at(id) != null \
						and si2.contains(p):
					best = {"kind": "pile", "interior": si2, "world": p, "pos": si2.pile_pos}
					best_d = 1.5
					break
		var hs := _home_spots(p, best, best_d)
		best = hs[0]
		best_d = hs[1]
		# The club office: the ticket kiosk at the stadium's south gate.
		var co := club_office_pos()
		var dco := Vector2(p.x, p.z).distance_to(Vector2(co.x, co.z))
		if dco < 2.6 and absf(p.y - 0.9 - co.y) < 2.0 and dco < best_d:
			best = {"kind": "club_office", "world": co}
			best_d = dco
		# Cars: walk up to any side of it. The back third is the boot, the
		# rest is a door (either side, or the bonnet): no hunting for the
		# one handle on the driver's side.
		for vid in cars:
			var car: Car = cars[vid]
			var xf := car.global_transform
			var lp := xf.affine_inverse() * p
			var hw: float = car.spec["size"].x * 0.5
			var hl: float = car.spec["size"].z * 0.5
			var gap := Vector2(maxf(absf(lp.x) - hw, 0.0), maxf(absf(lp.z) - hl, 0.0)).length()
			if gap > CAR_REACH or absf(lp.y) > 2.2:
				continue
			var at_boot := lp.z > hl * 0.45 and (lp.z > hl or absf(lp.x) < hw + 0.5)
			var s2 := {"kind": "car_boot" if at_boot else "car_door", "vehicle": vid,
				"world": xf * Vector3(clampf(lp.x, -hw - 0.6, hw + 0.6), 0.0, clampf(lp.z, -hl - 0.6, hl + 0.8))}
			var d3 := gap * 0.8  # a car you're touching beats a shelf behind you
			if d3 < best_d:
				best = s2
				best_d = d3
	if skyport_play and not in_vehicle():
		var sk := skyport_play.spot_near(player.global_position)
		if not sk.is_empty() and float(sk["d"]) < best_d:
			best = sk
			best_d = float(sk["d"])
	var changed: bool = best.get("kind", "") != spot.get("kind", "") or best.get("slot", -9) != spot.get("slot", -9) \
		or best.get("vehicle", "") != spot.get("vehicle", "") or best.get("interior") != spot.get("interior")
	spot = best
	if changed:
		spot_changed.emit(spot)


func _spot_unit() -> String:
	var si = spot.get("interior")
	return String((si as ShopInterior).unit.get("id", "")) if si is ShopInterior else ""


## In front of the south-gate ticket kiosk at The Heights Ground.
func club_office_pos() -> Vector3:
	var c := SetPieces.STADIUM_AT
	var kp := SetPieces._bowl(c, PI * 0.5, SetPieces.BOWL_DEPTH + 6.0)
	var kd := (kp - c).normalized()
	var ks := Vector2(-kd.y, kd.x)
	var q := kp - ks * 7.0 + kd * 2.4
	return Vector3(q.x, layout.ground_y(q.x, q.y), q.y)


var _screen: Label3D
var _screen_sig := ""


## Matchday: the big screen on the forecourt shows the fixture / the score,
## and the streets round the ground fill up for home games.
func _update_stadium() -> void:
	Club.ensure(empire)
	var cl := empire.club
	var txt := ""
	var md := Club.next_match_day(empire)
	var opp: Dictionary = Club.opponent(empire, md)
	var last: Dictionary = cl.get("last", {})
	if not last.is_empty() and int(last.get("day", -1)) == empire.day and empire.hour() >= 17.0:
		txt = "FULL TIME\nHARBOUR CITY %d–%d %s" % [int(last["gf"]), int(last["ga"]), String(last["opp"]).to_upper()]
	elif Club.is_matchday(empire) and empire.hour() >= 15.0 and empire.hour() < 17.0:
		txt = "LIVE · %s\nHARBOUR CITY v %s" % ["HOME" if Club.is_home(empire) else "AWAY", String(opp["name"]).to_upper()]
	else:
		txt = "HARBOUR CITY FC\n%s %s · %s 15:00\nv %s" % ["HOME" if Club.is_home(empire, md) else "AWAY", "TODAY" if md == empire.day else "",
			["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"][(md - 1) % 7], String(opp["name"]).to_upper()]
	if txt != _screen_sig:
		_screen_sig = txt
		if _screen == null:
			var r := Rect2(SetPieces.STADIUM_AT - Vector2(75, 65), Vector2(150, 130))
			var sc := Vector2(r.position.x + 9.0, r.end.y - 9.0)
			var face := (SetPieces.STADIUM_AT - sc).normalized()
			_screen = Label3D.new()
			_screen.name = "StadiumScreen"
			_screen.font = EmpireStyle.font("black")
			_screen.font_size = 96
			_screen.pixel_size = 0.012
			_screen.shaded = false
			_screen.outline_size = 0
			_screen.modulate = Color(1.0, 0.97, 0.9)
			_screen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_screen.visibility_range_end = 400.0
			var gy := layout.ground_y(sc.x, sc.y)
			var at := Vector3(sc.x + face.x * 0.45, gy + 17.0, sc.y + face.y * 0.45)
			add_child(_screen)
			_screen.global_transform = Transform3D(Basis.looking_at(-Vector3(face.x, 0, face.y), Vector3.UP), at)
		_screen.text = txt
	# Home-game crowds on the streets round the ground.
	var near := Vector2(player.global_position.x, player.global_position.z).distance_to(SetPieces.STADIUM_AT) < 450.0
	crowd.density = 2.4 if Club.crowd_on(empire) and near else 1.0


## The prompt for the current spot: [text, enabled].
func spot_prompt() -> Array:
	if skyport_play and skyport_play.piloting != "":
		var cr: Craft = skyport_play.crafts.get(skyport_play.piloting)
		return ["GET OUT", cr != null and cr.can_exit()]
	if driving != "":
		# (Only offered once the car is slow enough to leave.)
		var dc: Car = cars.get(driving)
		var slow := dc == null or Vector2(dc.linear_velocity.x, dc.linear_velocity.z).length() <= 4.0
		return ["GET OUT", slow]
	if spot.is_empty():
		return ["", false]
	if String(spot.get("kind", "")).begins_with("sky_"):
		return skyport_play.prompt(spot)
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
				var fx := String(EmpireData.product(cp).get("fixture", ""))
				if int(b.fixtures.get(fx, 0)) <= 0:
					return ["NO %s YET · put it down or store it" % where.trim_prefix("THE ").trim_prefix("A "), false]
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
		"pile":
			if not empire.carried.is_empty():
				return ["PUT DOWN %d CASE%s" % [empire.carried.cases_used(), "" if empire.carried.cases_used() == 1 else "S"], true]
			if b.floor_pile.is_empty():
				return ["", false]
			return ["PICK UP CASE (%d on the floor)" % b.floor_pile.cases_used(), true]
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
		"hq_desk":
			return ["RECEPTION · %s" % ("YOUR HEAD OFFICE" if empire.hq_tier() > 0 else "OFFICE SUITES TO LET"), true]
		"office_desk":
			var of := Offices.at(empire, _spot_unit())
			return ["RECEPTION · %s" % (String(of["name"]).to_upper() if not of.is_empty() else "OFFICE FLOORS TO LET"), true]
		"club_office":
			return ["CLUB OFFICE · %s" % String(Club.cfg().get("name", "")).to_upper(), true]
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
			if String(home.get("estate", "")) != "":
				return ["%s · COMES WITH %s" % [String(home["name"]).to_upper(), String(Ventures.estate_def(home["estate"])["name"]).to_upper()], true]
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
			var near_shop := _own_shop_near(cars[spot["vehicle"]].global_position)
			if near_shop != null and not cargo.is_empty():
				return ["UNLOAD %d CASE%s INTO %s" % [cargo.cases_used(), "" if cargo.cases_used() == 1 else "S", near_shop.name.to_upper()], true]
			if not cargo.is_empty():
				return ["UNLOAD (%d/%d cases)" % [cargo.cases_used(), cargo.case_capacity], true]
			return ["BOOT · empty (%d cases)" % cargo.case_capacity, false]
	return ["", false]


## Puts everything you're carrying down on the shop floor (by the door).
func _put_down(b: Business, si: ShopInterior) -> void:
	var n := empire.carried.cases_used()
	for pid in empire.carried.units.keys():
		Stock.transfer(empire.carried, b.floor_pile, pid, empire.carried.qty(pid))
	Sfx.play("drop", -6.0)
	ui.toast("Put %d case%s down by the door. Staff move them to the stockroom when there's room (or overnight)." % [n, "" if n == 1 else "s"], "info")
	si.refresh_goods()


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
	if skyport_play and skyport_play.piloting != "":
		var why := skyport_play.exit()
		if why != "":
			ui.toast(why, "warn")
		return
	if spot.is_empty():
		return
	if String(spot.get("kind", "")).begins_with("sky_"):
		skyport_play.act(spot)
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
		"pile":
			if not empire.carried.is_empty():
				_put_down(b, si)
			else:
				var pid4: String = b.floor_pile.units.keys()[0]
				var got := Stock.transfer(b.floor_pile, empire.carried, pid4, mini(b.floor_pile.qty(pid4), EmpireData.case_qty(pid4)))
				if got > 0:
					Sfx.play("pickup", -6.0)
				else:
					ui.toast("Your hands are full", "warn")
				si.refresh_goods()
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
		"hq_desk":
			ui.open_hq()
		"office_desk":
			ui.open_office(unit_by_id.get(_spot_unit(), {}))
		"club_office":
			ui.open_club()
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
			elif String(home_by_id(spot["home"]).get("estate", "")) != "":
				ui.open_phone("property")   # (the suite / flat come with their building)
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
	# Parked at one of your shops: everything goes into its stockroom (what
	# doesn't fit is left by the door for staff to tidy away).
	var shop := _own_shop_near(cars[vid].global_position)
	if shop != null:
		var cases := cargo.cases_used()
		var to_room := 0
		for pid3 in cargo.units.keys():
			to_room += Stock.transfer(cargo, shop.backroom, pid3, cargo.qty(pid3))
		var spill := 0
		for pid4 in cargo.units.keys():
			spill += Stock.cases_for(pid4, cargo.qty(pid4))
			Stock.transfer(cargo, shop.floor_pile, pid4, cargo.qty(pid4))
		ui.toast("Unloaded %d case%s into %s's stockroom%s" % [cases, "" if cases == 1 else "s", shop.name,
			"" if spill == 0 else " (%d by the door: the stockroom's full)" % spill], "good" if spill == 0 else "warn")
		Sfx.play("drop", -4.0, 0.8)
		if interiors.has(shop.premises["id"]):
			interiors[shop.premises["id"]].refresh_goods()
		empire.changed.emit()
		return
	# Take one case of whatever there's most of.
	var best := ""
	for pid2 in cargo.units:
		if best == "" or cargo.qty(pid2) > cargo.qty(best):
			best = pid2
	var got := Stock.transfer(cargo, empire.carried, best, mini(cargo.qty(best), EmpireData.case_qty(best)))
	if got > 0:
		Sfx.play("pickup", -6.0)


## Your shop whose door is within 25 m of p (a car parked out front), or null.
func _own_shop_near(p: Vector3) -> Business:
	var best: Business = null
	var bd := 25.0
	for b: Business in empire.businesses:
		var u: Dictionary = unit_by_id.get(b.premises.get("id", ""), {})
		if u.is_empty():
			continue
		var d := Premises.door_point(u).distance_to(p)
		if d < bd:
			bd = d
			best = b
	return best


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
	if m.has("art"):
		# Its own body (tools/blender/build_player_cars.py), same handling:
		# the van and box truck you own aren't the traffic's light civ_* meshes.
		s["body"] = String(m["art"])
		CarCatalog._fit_body(s)
	s["top_speed"] = float(m.get("top_speed", s["top_speed"]))
	s["paint"] = Color.from_string(String(m.get("paint", "#cccccc")), Color.WHITE)
	s["nitro"] = 0.0
	return s


func _spawn_cars() -> void:
	for id in cars:
		cars[id].queue_free()
	cars.clear()
	for v in empire.vehicles:
		if SkyportPlay.vclass(String(v["model"])) == "car":
			_spawn_car(v)
	if skyport_play:
		skyport_play.spawn_all()   # (helicopters, planes, boats)


## In any vehicle: a car you're driving or a craft you're piloting.
func in_vehicle() -> bool:
	return driving != "" or (skyport_play != null and skyport_play.piloting != "")


## The vehicle you're in (Car or Craft), or null.
func vehicle_node() -> Node3D:
	if driving != "":
		return cars.get(driving)
	if skyport_play and skyport_play.piloting != "":
		return skyport_play.crafts.get(skyport_play.piloting)
	return null


## The camera's heading, whichever camera is live.
func view_yaw() -> float:
	if driving != "":
		return chase.view_yaw()
	if skyport_play and skyport_play.piloting != "":
		return skyport_play.cam.view_yaw()
	return camera.view_yaw()


func _spawn_car(v: Dictionary) -> Car:
	if SkyportPlay.vclass(String(v["model"])) != "car":
		return null   # (aircraft and boats: SkyportPlay)
	var c := Car.new()
	c.name = "Car_" + String(v["id"])
	c.setup(_car_spec(v["model"]), "player")
	c.park_lock = true
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
	c.occupied = true
	c.freeze = false
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
	c.occupied = false
	driving = ""
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.visible = true
	player.collision_layer = 1 << 2
	player.respawn(Vector3(side.x, maxf(side.y, xf.origin.y) + 0.9, side.z))
	player.input_enabled = true
	camera.face(xf.basis.get_euler().y)
	camera.cam.make_current()
	world.set_viewer(camera)
	if v.get("test", false) and skyport_play:
		skyport_play.end_test(String(v["id"]))


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
	elif c.upside_time > 2.0:
		_right_car(c)


## On foot the sea has a floor (the cars' water collision) but every quay is
## too tall to step up: someone who walks off the edge would wade forever.
## Remember the last dry ground and put them back on it.
func _check_wading(dt: float) -> void:
	var p := player.global_position
	var wet := p.y < Car.WATER_Y + 1.2 and layout.is_water(p)
	if not wet:
		_wet_t = 0.0
		if player.is_on_floor() and not player.stunned:
			_dry_pos = p
		return
	_wet_t += dt
	if _wet_t < 1.5:
		return
	_wet_t = 0.0
	var back := _dry_pos
	if back == Vector3.INF:
		var s := starter_unit()
		back = Premises.door_point(s) + Premises.outward(s) * 3.0
	player.respawn(back + Vector3.UP * 0.6)
	player.last_safe_position = back + Vector3.UP * 0.6
	ui.toast("Back on dry land", "warn")


## On its roof or side for two seconds: back on its wheels where it lies,
## facing the way it was going (it used to stay upside down for good –
## Never Stop does the same after 2 s).
func _right_car(c: Car) -> void:
	var f := -c.global_basis.z
	f.y = 0.0
	if f.length() < 0.1:
		f = c.global_basis.y.slide(Vector3.UP)
	var yaw := atan2(-f.x, -f.z) if f.length() > 0.01 else 0.0
	var p := c.global_position
	c.place(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, maxf(p.y, layout.ground_y(p.x, p.z)) + 1.2, p.z)))
	ui.toast("Back on its wheels", "warn")


func _recover_car(c: Car) -> void:
	var p := c.global_position
	var g := _kerb_point(Vector3(p.x, 0.0, p.z))
	c.place(Transform3D(c.global_basis, g + Vector3.UP * 1.0))
	ui.toast("Towed out of the water (£60)", "warn")
	empire.pay(60.0, "vehicle", "Recovery")


## Having a vehicle brought to you: {ok, fee, why, at (Transform3D)}.
## A paid driver brings it to the kerb of the street you're on – you need
## to be outdoors near a road, and it has to be further than a short walk.
func delivery_quote(vid: String) -> Dictionary:
	var out := {"ok": false, "fee": 0.0, "why": "", "at": Transform3D()}
	var c: Car = cars.get(vid)
	if c == null:
		out["why"] = "Not found"
		return out
	if driving != "":
		out["why"] = "Get out of the car first"
		return out
	if player.indoors or floor_unit != "":
		out["why"] = "Step outside onto a street first"
		return out
	var me := player.global_position
	var d := me.distance_to(c.global_position)
	if d < 80.0:
		out["why"] = "It's %d m away – just walk to it" % int(d)
		return out
	if not gps.ready_net():
		out["why"] = "Finding the roads…"
		return out
	var near := gps.net.nearest(me, Vector3.ZERO, 40.0, -1, true)
	if near.is_empty():
		out["why"] = "No road within 40 m – walk to a street"
		return out
	# The kerb side of the lane nearest you, facing along the lane.
	var lane: int = near["lane"]
	var s: float = near["s"]
	var p: Vector3 = gps.net.lane_point(lane, s)
	var dir := gps.net.lane_dir(lane, s)
	var side := Vector3(-dir.z, 0.0, dir.x)
	if side.dot(me - p) < 0.0:
		side = -side
	var at := _kerb_point(p + side * 1.6)
	out["at"] = Transform3D(Basis.looking_at(dir, Vector3.UP), at)
	out["fee"] = clampf(roundf(30.0 + d * 0.03), 30.0, 150.0)
	if not empire.can_afford(float(out["fee"])):
		out["why"] = "Costs %s – not enough money" % EmpireData.money(float(out["fee"]))
		return out
	out["ok"] = true
	return out


## "Stuck? Back to the street" (quality audit 2026-11-18: wedged between a
## building and a lamp post, beached on a kerb island, or walked into a gap
## in the scenery, nothing short of reloading got you out). Puts you – and
## the car you're in – on the nearest road lane, facing along it. Craft go
## back to where they last stood (only once landed / stopped). "" or why not.
func unstick() -> String:
	if skyport_play and skyport_play.piloting != "":
		var cr: Craft = skyport_play.crafts.get(skyport_play.piloting)
		if cr == null:
			return "Not found"
		if not cr.can_exit():
			return "Land first"
		cr.place(cr.rest_xf)
		return ""
	if not gps.ready_net():
		return "Finding the roads…"
	var here := player.global_position if driving == "" else (cars[driving] as Node3D).global_position
	var near := {}
	for r: float in [40.0, 120.0, 400.0]:
		near = gps.net.nearest(here, Vector3.ZERO, r, -1, true)
		if not near.is_empty():
			break
	if near.is_empty():
		return "No road nearby"
	var lane: int = near["lane"]
	var s: float = near["s"]
	var p: Vector3 = gps.net.lane_point(lane, s)
	var dir := gps.net.lane_dir(lane, s)
	if floor_unit != "":
		_end_floor()
	if driving != "":
		var c: Car = cars[driving]
		c.linear_velocity = Vector3.ZERO
		c.angular_velocity = Vector3.ZERO
		c.place(Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(p.x, p.y, p.z) + Vector3.UP * 0.6))
		return ""
	# On foot: on the pavement beside that lane (the kerb side), not in it.
	var side := Vector3(-dir.z, 0.0, dir.x)
	var to_lane := p - here
	to_lane.y = 0.0
	if side.dot(to_lane) > 0.0:
		side = -side
	var walk := p + side * 5.5
	if not gps.net.nearest(walk, Vector3.ZERO, 2.0, -1, true).is_empty():
		walk = p + side * 2.0   # (a wide road: stand at its edge)
	_teleport(Vector3(walk.x, maxf(p.y, layout.ground_y(walk.x, walk.z)) + 1.0, walk.z), atan2(-dir.x, -dir.z))
	return ""


## Pays a driver to bring the vehicle round (it arrives a few seconds later).
func deliver_vehicle(vid: String) -> String:
	var q := delivery_quote(vid)
	if not q["ok"]:
		return String(q["why"])
	if not empire.pay(float(q["fee"]), "vehicle", "Vehicle delivered to you"):
		return "Not enough money"
	var c: Car = cars[vid]
	var xf: Transform3D = q["at"]
	get_tree().create_timer(2.5, false).timeout.connect(func():
		if not is_instance_valid(c) or driving == vid:
			return
		c.linear_velocity = Vector3.ZERO
		c.angular_velocity = Vector3.ZERO
		c.place(Transform3D(xf.basis, xf.origin + Vector3.UP * 0.3))
		var v := empire.vehicle(vid)
		v["pos"] = [xf.origin.x, xf.origin.y, xf.origin.z]
		v["yaw"] = xf.basis.get_euler().y
		ui.toast("Your vehicle is here", "good")
		Sfx.play("chime", -6.0))
	return ""


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
## Buying or renting from the phone goes through an agent: 4% of the money
## changing hands, £40 to £2,500. At the door it's free.
static func agent_fee(amount: float) -> float:
	return clampf(roundf(amount * 0.04), 40.0, 2500.0)


func _agent(fee: float, total: float) -> String:
	if fee > 0.0 and not empire.can_afford(total + fee):
		return "Not enough money (%s with the agent's fee)" % EmpireData.money(total + fee)
	return ""


func _pay_agent(fee: float, what: String, biz := "") -> void:
	if fee > 0.0:
		empire.pay(fee, "other", "Agent's fee: %s" % what, biz)


func buy_firm(u: Dictionary, fee := 0.0) -> String:
	var f := CityLife.firm_at(empire, u["id"])
	var pre := _agent(fee, CityLife.firm_price(f) if not f.is_empty() else 0.0)
	if pre != "":
		return pre
	var err: Array = []
	var b := CityLife.buy_firm(empire, Premises.record(u), err)
	if b == null:
		return err[0] if not err.is_empty() else "Can't buy it"
	_pay_agent(fee, b.name, b.id)
	_sync_rivals()
	rebuild_interior(u["id"])
	Sfx.play("cash", -2.0)
	MapKit.invalidate()
	save_game()
	return ""


func buy_out_rival(u: Dictionary, fee := 0.0) -> String:
	var r := CityLife.rival_at(empire, u["id"])
	var pre := _agent(fee, CityLife.rival_price(r) if not r.is_empty() else 0.0)
	if pre != "":
		return pre
	var err: Array = []
	var b := CityLife.buy_out(empire, Premises.record(u), err)
	if b == null:
		return err[0] if not err.is_empty() else "Can't buy it"
	_pay_agent(fee, b.name, b.id)
	_sync_rivals()
	rebuild_interior(u["id"])
	Sfx.play("cash", -2.0)
	MapKit.invalidate()
	save_game()
	return ""


func rent_unit(u: Dictionary, buy := false, type_id := "convenience", fee := 0.0) -> String:
	if empire.business_at(u["id"]) != null and not buy:
		return "You already run this shop"
	var pre := _agent(fee, float(u["price"]) if buy else float(u["rent"]) * 3.0)
	if pre != "":
		return pre
	var b := empire.buy_premises(Premises.record(u), type_id) if buy else empire.rent_premises(Premises.record(u), type_id)
	if b == null:
		return "Not enough money" if not CityLife.is_taken(empire, u["id"]) else "Someone else trades here"
	_pay_agent(fee, b.name, b.id)
	MapKit.invalidate()
	if type_id != "convenience" and b.opened_day == empire.day:
		# A name to suit the trade: "Village Shop" → "Village Café".
		var kinds: Array = (CityLife.firm_cfg().get("kinds_by_type", {}) as Dictionary).get(type_id, [])
		if not kinds.is_empty():
			b.name = "%s %s" % [String(u.get("shop_name", "Corner")).get_slice(" ", 0), kinds[0]]
	rebuild_interior(u["id"])
	save_game()
	return ""


## Closes a business for good (Empire.close_business) and puts the world
## back: the unit is vacant again (to let), you're no longer on its floor,
## a GPS route to it ends.
func close_business(b: Business) -> Dictionary:
	var uid := String(b.premises.get("id", ""))
	if floor and floor.biz == b:
		_end_floor()
	var r := empire.close_business(b)
	if r.is_empty():
		return r
	if String(gps.ref.get("id", "")) in [b.id, uid]:
		clear_gps()
	MapKit.invalidate()
	if unit_by_id.has(uid):
		rebuild_interior(uid)
	save_game()
	return r


## Sells a vehicle (Empire.sell_vehicle) and takes it out of the world.
func sell_vehicle(vid: String) -> String:
	var v := empire.vehicle(vid)
	if driving == vid or (skyport_play and skyport_play.piloting == vid):
		return "Get out first"
	var why := empire.sell_vehicle_block(v)
	if why != "":
		return why
	empire.sell_vehicle(v)
	if cars.has(vid):
		cars[vid].queue_free()
		cars.erase(vid)
		vfx.cars = cars.values()
	if skyport_play and skyport_play.crafts.has(vid):
		skyport_play.crafts[vid].queue_free()
		skyport_play.crafts.erase(vid)
	if String(gps.ref.get("id", "")) == vid:
		clear_gps()
	MapKit.invalidate()
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
	return gps.dest if gps else Vector3.INF


## Sets the GPS (a road route on both maps). `ref` names what it points at
## ({kind: unit|vehicle|home|objective|point, id}) so the route follows a
## moving car and survives a save.
func set_gps(p: Vector3, label: String, ref := {}) -> void:
	gps.set_destination(p, label, ref)
	if String(ref.get("kind", "")) != "objective":
		empire.flags["gps_manual"] = true


func clear_gps() -> void:
	gps.clear()
	empire.flags.erase("gps_manual")


## Where a vehicle is now (the live car, else where it was parked).
func vehicle_position(vid: String) -> Vector3:
	var c: Car = cars.get(vid)
	if c and is_instance_valid(c):
		return c.global_position
	if skyport_play and skyport_play.crafts.has(vid) and is_instance_valid(skyport_play.crafts[vid]):
		return (skyport_play.crafts[vid] as Node3D).global_position
	var v := empire.vehicle(vid) if empire else {}
	if v.is_empty():
		return Vector3.ZERO
	return Vector3(float(v["pos"][0]), float(v["pos"][1]), float(v["pos"][2]))


var _obj_sig := ""


## The current objective drives the GPS unless you set your own route.
func _objective_gps() -> void:
	var ob := objective()
	var t: Vector3 = ob[1]
	var sig := "%s|%s" % [ob[0], str(t.snapped(Vector3.ONE * 2.0)) if t != Vector3.INF else ""]
	if sig == _obj_sig:
		return
	_obj_sig = sig
	if empire.flags.get("gps_manual", false) and gps.active():
		return
	empire.flags.erase("gps_manual")
	if t == Vector3.INF:
		if String(gps.ref.get("kind", "")) == "objective":
			gps.clear()
		return
	if Vector2(t.x - gps.dest.x, t.z - gps.dest.z).length() > 3.0 or not gps.active():
		gps.set_destination(t, String(ob[2]) if ob.size() > 2 else String(ob[0]), {"kind": "objective"})


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
	# Skyport Island's: the penthouse (a home you buy), the hotel suite and
	# the show flat (yours with the building: Ventures.ESTATE_HOMES).
	if skyport:
		for h: Dictionary in skyport.wplan.get("homes", []):
			var est := String(Ventures.HOME_ESTATE.get(String(h["id"]), ""))
			out.append({"id": "home_" + String(h["id"]), "kind": "home", "name": String(h["name"]),
				"price": SKYPORT_PENTHOUSE if est == "" else float(Ventures.estate_def(est).get("price", 0.0)),
				"tier": int(h["tier"]), "h": h, "estate": est, "floor": Apartments.floor_height(h), "district": "east:skyport"})
	return out


const SKYPORT_PENTHOUSE := 2500000.0


## Saves from the first Skyport build owned the penthouse as an investment
## ("spire_penthouse" estate): it's a home now – same price, same keys.
func _migrate_penthouse_estate() -> void:
	var es: Dictionary = empire.flags.get("estates", {})
	if es.has("spire_penthouse"):
		es.erase("spire_penthouse")
		if not empire.owns_property("home_skyport_penthouse"):
			empire.properties.append({"id": "home_skyport_penthouse", "kind": "home", "name": "Skyport Penthouse",
				"price": SKYPORT_PENTHOUSE, "let": false, "income": 0.0})


## Street door of a home's tower (below its window, on the pavement).
func home_lift(home: Dictionary) -> Vector3:
	var h: Dictionary = home["h"]
	if h.has("lift"):
		return h["lift"]
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
## The opening objectives, in order: [text, GPS target (or INF), short
## label for the route, action] – the action is what tapping the objective
## opens ("map", "property", "staff", "finances", "stock", "" = nothing).
## Each step is done by doing the real thing (flags set where it happens).
func objective() -> Array:
	var start: Dictionary = unit_by_id.get(empire.flags.get("start_unit", ""), starter_unit())
	var f := empire.flags
	var no_shop := empire.businesses.is_empty()
	if no_shop and not f.get("seen_car", false) and not empire.vehicles.is_empty():
		var vid: String = empire.vehicles[0]["id"]
		var cp := vehicle_position(vid)
		var far := player.global_position.distance_to(cp) > 60.0
		# (Walked off before finding it: "on this street" was wrong; the
		# distance is the GPS's, by road.)
		return ["Find your car – follow the route to it" if far else "Find your car – it's parked on this street", cp, "Your car", ""]
	if no_shop and not f.get("opened_map", false):
		return ["Open the map: tap the minimap", Vector3.INF, "", "map"]
	if no_shop and not f.get("inspected_property", false):
		return ["Inspect a shop to let – %s is close by" % String(start.get("shop_name", "one")),
			Premises.door_point(start), String(start.get("shop_name", "Shop to let")), "property"]
	if no_shop:
		return ["Rent a shop – walk up to its TO LET sign (%s is the cheapest)" % String(start.get("shop_name", "")),
			Premises.door_point(start), String(start.get("shop_name", "Shop to let")), "property"]
	var b: Business = empire.businesses[0]
	var w := wholesaler(b.island())
	if int(empire.stats["cases_bought"]) == 0:
		return ["Drive to %s and buy stock" % String(w.get("name", "the wholesaler")), Premises.door_point(w),
			String(w.get("name", "Wholesaler")), ""]
	var pal := _pallet(w.get("id", ""))
	var in_cars := 0
	for v in empire.vehicles:
		in_cars += (v["cargo"] as Stock).total_units()
	if not pal.is_empty() and in_cars == 0 and empire.carried.is_empty() and b.stock_units() == 0:
		return ["Collect your goods from the collection bay (park by it, use the boot)", Premises.door_point(w),
			String(w.get("name", "Wholesaler")), ""]
	if b.stock_units() == 0 and b.orders.is_empty():
		return ["Take the stock to %s and carry it in" % b.name, Premises.door_point(unit_by_id.get(b.premises["id"], start)),
			b.name, ""]
	if int(empire.stats["sales"]) == 0 and b.shelf_units() == 0:
		return ["Put stock on the shelves (carry a case to a shelf)", Vector3.INF, "", ""]
	if int(empire.stats["sales"]) < 3:
		return ["Serve customers at the till (%d/3 sales)" % int(empire.stats["sales"]), _door_if_away(b), b.name, ""]
	if int(empire.stats["hires"]) == 0:
		return ["Hire your first employee – a cashier serves while you're away", Vector3.INF, "", "staff"]
	if not f.get("viewed_finances", false):
		return ["Check how %s is doing: its Finances" % b.name, Vector3.INF, "", "finances"]
	if not f.get("viewed_expansion", false):
		return ["Find your next shop: Property lists every unit to let and for sale", Vector3.INF, "", "property"]
	var g: Array = empire.current_goals(1)
	if (g[1] as Array).is_empty():
		return ["Build your empire", Vector3.INF, "", ""]
	return [String(g[0]) + ": " + String(g[1][0]["text"]), Vector3.INF, "", ""]


## A shop's door when you're not at it (the objective's route), else none.
func _door_if_away(b: Business) -> Vector3:
	var u: Dictionary = unit_by_id.get(b.premises.get("id", ""), {})
	if u.is_empty() or floor_unit == b.premises.get("id", ""):
		return Vector3.INF
	return Premises.door_point(u)


func _tutorial_step() -> void:
	# Found the car: within a few metres of it (or in it).
	if not empire.flags.get("seen_car", false) and not empire.vehicles.is_empty():
		var vid: String = empire.vehicles[0]["id"]
		if driving != "" or player.global_position.distance_to(vehicle_position(vid)) < Gps.ARRIVE_WALK + 2.0:
			empire.flags["seen_car"] = true
			ui.toast("That's your car: it shows on the map as a white square", "good")


# ------------------------------------------------------------------ save
func save_game() -> void:
	if empire == null or state == "boot":
		return
	# Vehicles' positions and the hero's, then the economy.
	if skyport_play:
		skyport_play.sync_positions()
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
		if empire.vehicle(driving).get("test", false):
			d["driving"] = ""
	elif skyport_play and skyport_play.piloting != "":
		var cr2: Craft = skyport_play.crafts.get(skyport_play.piloting)
		if cr2:
			var side2 := skyport_play.saved_pilot_point(cr2)
			d["player"] = [side2.x, side2.y + 1.0, side2.z, camera.view_yaw()]
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
	Ventures._grant_homes(empire)   # (homes that come with Skyport buildings)
	_migrate_penthouse_estate()
	_connect_empire()
	_rival_sig = "?"
	_spawn_cars()
	_obj_sig = ""
	gps.restore()
	var pp: Array = d.get("player", [])
	if pp.size() >= 4 and int((d.get("empire", {}) as Dictionary).get("version", 1)) < 6:
		# (Saved on Skyport Island before it moved: Empire.migrate v6.)
		var q := SkyportIsland.migrate_point(Vector3(float(pp[0]), float(pp[1]), float(pp[2])))
		pp = [q.x, q.y, q.z, float(pp[3])]
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
		for role in ["cashier", "stocker", "cleaner"]:
			var cs := empire.candidates.filter(func(x): return x["role"] == role)
			if not cs.is_empty():
				empire.hire(b, cs[0])
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
	if args.has("stats"):
		# Captures: render cost of this frame (tools/aerial_audit.sh).
		var ri := func(k): return RenderingServer.get_rendering_info(k)
		print("RENDER_STATS ", JSON.stringify({"shot": path.get_file(),
			"draw_calls": ri.call(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"prims": ri.call(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			"objects": ri.call(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			"video_mb": snappedf(ri.call(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
			"tex_mb": snappedf(ri.call(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
			"static_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1)}))
	get_tree().quit()


func _selftest() -> void:
	var ok := units.size() > 10 and wholesaler("west").size() > 0 and empire != null
	ok = ok and player != null and cars.size() >= 1
	print("SELFTEST units=%d cars=%d %s" % [units.size(), cars.size(), "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
