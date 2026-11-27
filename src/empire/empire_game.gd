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
## Where this session saves: SAVE_PATH, or --save=<path> (tests/captures).
var save_path := SAVE_PATH
const STREAM_IN := 150.0
const STREAM_OUT := 210.0
const FRONT_CELL := 72.0
const FRONT_IN := 72.0
const FRONT_OUT := 92.0
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
var vehicle_access := VehicleAccess.new(self)
var skyport: SkyportIsland
var skyport_play: SkyportPlay
var venues: Venues   # walk-in showrooms + clothes shops on Skyport
var vfx: VehicleFx
var audio: AudioDirector
var ambience: AmbientScape   # neighbourhood beds, shop doorways, interior reverb
var sfx: Sfx
var empire: Empire
var ui: EmpireUI
var gps: Gps
var pursuit: StreetPursuit
var speed_fx: SpeedFx
const PURSUIT_REWARD := 2500.0
var traffic_bodies: TrafficBodies
var near_traffic: NearTrafficPool
var wrecks: Wrecks
var street_cars: StreetCars   # stealing cars, lock-up garages
var career: CareerPlay       # courier runs, shift work, the driver
var garage: VehicleGarage    # the Vehicle Collection under the city
var props: Destructibles
var damage_desk: DamageDesk
var smash: StorefrontSmash
var car_audio: CarAudio
var units: Array = []
var unit_by_id := {}
var interiors := {}
var elevators := {}        # home id -> ApartmentElevator
var _elev_riding := false
var _front_cells := {}
var _front_rooms := {}      # unit id -> ShopInterior
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
var _dry_t := 0.0             # safe-position sampling clock
var safe: SafeGround          # every water recovery asks this where to go
var _car_safe := {}           # vehicle id -> last safe Transform3D on dry land
const HERO_BOX := Vector3(0.8, 1.8, 0.8)
var _pending_vehicle_deliveries := {}
var _last_car_pos := Vector3.ZERO
var _km_acc := 0.0
var _clean_t := 0.0
var _tutorial := 0
var _cloud_sync := Callable()


var _lt_ms := 0
var _tr_us := 0   # (--load-timing: the transition profiler's last mark)
var _title_save_loaded := false   # (the save loaded at launch, still as loaded)


## --load-timing: one step of a menu → gameplay transition, in ms since the
## previous mark (main-thread time: nothing else runs meanwhile).
func _tr(tag: String) -> void:
	if not LoadPacer.timing():
		return
	var now := Time.get_ticks_usec()
	if _tr_us > 0:
		print("ENTER_T %-34s %7.1f ms" % [tag, (now - _tr_us) / 1000.0])
	_tr_us = now


func _mem_mark(tag: String, prev: Array) -> void:
	if LoadPacer.timing():
		var now := Time.get_ticks_msec()
		print("LOAD_T EG %-26s %6d ms (t=%d)" % [tag, now - _lt_ms if _lt_ms > 0 else 0, now])
		_lt_ms = now
	StartupTrace.mark(tag)
	if not args.has("mem-audit"):
		return
	var mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objs := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var res := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	print("MEM_AUDIT %-24s %7.1f MB (%+6.1f) | nodes %6d (%+6d) | objs %6d | res %5d" % [
		tag, mb, mb - float(prev[0]), nodes, nodes - int(prev[1]), objs, res])
	prev[0] = mb
	prev[1] = nodes


func _ready() -> void:
	StartupTrace.mark("game scene ready callback")
	CarVisual.auto_dent = true   # (every car's impacts dent its own body)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var _mp := [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]
	_mem_mark("boot", _mp)
	# At launch (LoadPacer active: the boot screen) the build below hands
	# frames back to the splash. Nothing half-built may tick meanwhile: the
	# tree is paused until the world is whole (the boot layer always runs).
	var tree := get_tree()
	var paced := LoadPacer.active
	if paced:
		tree.paused = true
		LoadPacer.stage = "Generating streets and buildings"
	Prof.enabled = args.has("profile-world")
	if args.has("quality"):
		Settings.quality = int(args["quality"])
	if args.has("look"):
		Settings.look = args["look"]   # captures: --look=crisp|clean|... (not saved)
	if args.has("geo"):
		# Geometry inspector (DevServer, tools/citydev): wireframes kept for
		# its wire mode, and nothing drawn until a frame is asked for - no
		# production shader is ever compiled on the VPS's CPU renderer.
		RenderingServer.set_debug_generate_wireframes(true)
		RenderingServer.render_loop_enabled = false
	Settings.time_of_day = "empire"   # the Empire's clock drives the sun
	Settings.weather = "empire"       # and its daily weather the sky (CityLife)
	Settings.apply()
	StartupTrace.mark("graphics settings applied (tier=%s quality=%d)" % [Settings.device_tier, Settings.quality])
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
	world.street_interiors_enabled = true
	add_child(world)
	if not world.is_built:
		await world.built
	_mem_mark("CityWorld+Mainland", _mp)
	await LoadPacer.step(tree, 0.74)
	layout = world.layout
	# Skyport Island (the third island: airport, logistics, high-rise, marina).
	SkyportIsland.enabled = true
	Venues.register()   # (the island carves their rooms out of its buildings)
	LoadPacer.stage = "Building Skyport and coastline"
	var t1 := Time.get_ticks_msec()
	skyport = SkyportIsland.new()
	skyport.name = "Skyport"
	add_child(skyport)
	await skyport.build(layout, world)
	_mem_mark("SkyportIsland", _mp)
	await LoadPacer.step(tree, 0.80)
	var lfn := Landforms.new()
	lfn.name = "Landforms"
	add_child(lfn)
	await lfn.build(layout)
	_mem_mark("Landforms", _mp)
	await LoadPacer.step(tree, 0.86)
	skyport.viewer = func() -> Vector3:
		if state == "title" and is_instance_valid(_title_focus):
			return _title_focus.global_position
		if garage and garage.inside and world.stream_anchor:
			return world.stream_anchor.global_position   # (underground: the street above)
		return vehicle_node().global_position if vehicle_node() else player.global_position
	print("Skyport Island: %d ms" % (Time.get_ticks_msec() - t1))
	_build_elevators()
	_mem_mark("Elevators", _mp)
	await LoadPacer.step(tree, 0.87)
	LoadPacer.stage = "Preparing the player and city systems"
	atmosphere.configure(args, world)
	Car.water_check = layout.is_water
	for P in [layout.mainland.premises if layout.mainland else null, layout.premises]:
		if P:
			for u in P.units:
				units.append(u)
				unit_by_id[u["id"]] = u
	for u: Dictionary in world.street_units + skyport.street_units:
		var key := _front_key(Vector2(u["pos"][0], u["pos"][2]))
		if not _front_cells.has(key):
			_front_cells[key] = []
		_front_cells[key].append(u)
		unit_by_id[u["id"]] = u
		if u.get("flagship", false):
			units.append(u)
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
	_mem_mark("Player+CharacterRig", _mp)
	await LoadPacer.step(tree, 0.89)
	# The people on the pavements round you (the GPU walkers carry the far streets).
	crowd = Crowd.new()
	crowd.name = "Crowd"
	add_child(crowd)
	if not paced:
		crowd.setup(self)
	_mem_mark("Crowd node", _mp)
	await LoadPacer.step(tree, 0.91)
	camera = SwingCamera.new()
	camera.name = "CameraRig"
	add_child(camera)
	camera.set_target(player)
	camera.distance_scale = 0.86   # street level (0.62 felt cramped; 0.76 still too close – user, 2026-11-20)
	world.set_viewer(camera)
	chase = ChaseCamera.new()
	chase.name = "ChaseCamera"
	add_child(chase)
	var lens := LensFx.new()
	lens.name = "DrivingLens"
	lens.chase_camera = chase
	add_child(lens)
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
	ambience = AmbientScape.new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.setup(self)
	audio.surface_at = _surface_sound_at
	sfx.director = audio
	carry_node = Node3D.new()
	carry_node.name = "Carry"
	add_child(carry_node)

	# NEVER STOP's speed streaks at the screen edges when you're flying along.
	var fx_layer := CanvasLayer.new()
	fx_layer.name = "SpeedFxLayer"
	fx_layer.layer = 1
	add_child(fx_layer)
	speed_fx = SpeedFx.new()
	fx_layer.add_child(speed_fx)
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
	safe = SafeGround.new(layout, world, func(): return gps.net if gps.ready_net() else null)
	# Real lamp light near the camera (the draped pools carry the far streets).
	var ll := LampLights.new()
	ll.name = "LampLights"
	add_child(ll)
	ll.setup([world, world.mainland], func() -> Vector3:
		var c := get_viewport().get_camera_3d()
		return c.global_position if c else player.global_position)
	if skyport and ll.has_method("add_island_lamps"):
		ll.call("add_island_lamps", skyport)
	car_audio = CarAudio.new()
	car_audio.name = "CarAudio"
	add_child(car_audio)
	car_audio.surface_at = _surface_sound_at
	# Solid traffic near you (the drawn cars have no bodies of their own).
	traffic_bodies = TrafficBodies.new()
	traffic_bodies.name = "TrafficBodies"
	add_child(traffic_bodies)
	traffic_bodies.setup(self)
	near_traffic = NearTrafficPool.new()
	near_traffic.name = "NearTrafficPool"
	add_child(near_traffic)
	if not paced:
		near_traffic.setup(self)
	_mem_mark("UI+Venues+Gps", _mp)
	await LoadPacer.step(tree, 0.94)
	# Dynamic resolution on phones (CitySwing's FrameGovernor; WorldState never
	# installed it, audit WS-08): eases the 3-D render scale down under load or
	# heat and back up with headroom, so heavy views stay smooth.
	var gov := FrameGovernor.new()
	gov.name = "FrameGovernor"
	gov.enabled = OS.has_feature("mobile") and not args.has("fixedscale")
	add_child(gov)
	# Hitting things like NEVER STOP: street furniture flies, cars are cars.
	wrecks = Wrecks.new()
	wrecks.name = "Wrecks"
	add_child(wrecks)
	wrecks.setup(self)
	street_cars = StreetCars.new()
	street_cars.name = "StreetCars"
	add_child(street_cars)
	street_cars.setup(self)
	career = CareerPlay.new()
	career.name = "CareerPlay"
	add_child(career)
	career.setup(self)
	garage = VehicleGarage.new()
	garage.name = "VehicleGarage"
	add_child(garage)
	garage.setup(self)
	_mem_mark("Wrecks+Garage", _mp)
	await LoadPacer.step(tree, 0.96)
	props = Destructibles.new()
	props.name = "Destructibles"
	add_child(props)
	props.setup(world as CityWorld)
	props.cars_fn = func() -> Array:
		var out: Array = wrecks.cars()
		var me := vehicle_node() as Car
		if me:
			out.append(me)
		if pursuit and pursuit.state == "chase":
			if is_instance_valid(pursuit.suspect):
				out.append(pursuit.suspect)
			out.append_array(pursuit.police.filter(func(c): return is_instance_valid(c)))
		return out
	props.broke.connect(_on_prop_broke)
	props.focus_fn = func() -> Vector3: return player.global_position if player else Vector3.INF
	damage_desk = DamageDesk.new()
	damage_desk.name = "DamageDesk"
	add_child(damage_desk)
	damage_desk.setup(self)
	smash = StorefrontSmash.new()
	smash.name = "StorefrontSmash"
	add_child(smash)
	smash.setup(self)
	# Clouds in the world at the towers' height (weather-driven).
	if Settings.quality > 0 and not args.has("no-clouds"):
		var clouds := CloudLayer.new()
		clouds.name = "Clouds"
		clouds.slices = 3 if Settings.quality >= 2 else 2
		add_child(clouds)
		clouds.view_fn = func() -> Vector3:
			var c := get_viewport().get_camera_3d()
			return c.global_position if c else player.global_position
		var skym: ShaderMaterial = atmosphere.sky_mat if "sky_mat" in atmosphere else null
		clouds.set_process(true)
		var cloud_t := [0.0]
		_cloud_sync = func():
			if get_tree().paused or not is_instance_valid(clouds) or skym == null:
				return
			cloud_t[0] -= get_process_delta_time()
			if cloud_t[0] > 0.0:
				return
			cloud_t[0] = 0.25
			clouds.cover = float(skym.get_shader_parameter("cloud_cover"))
			clouds.dark = float(skym.get_shader_parameter("cloud_dark"))
		get_tree().process_frame.connect(_cloud_sync)
	RenderingServer.global_shader_parameter_set("refl_probe", 0.0)
	RenderingServer.global_shader_parameter_set("mirror_on", 0.0)
	_mem_mark("City systems and HUD", _mp)
	LoadPacer.stage = "Checking saved progress"

	await LoadPacer.step(tree, 0.97)
	if args.has("save"):
		save_path = String(args["save"])
	else:
		# The WORLDSTATE rename moved the desktop app-data folder: bring a
		# City Empire save over (copied; the old folder is left alone). WS-07
		SafeSave.migrate_dir(["City Empire", "CityEmpire"], ["cityempire_save.json", "cityempire_save.json.bak"])
	var has_save := FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")
	StartupTrace.mark("save check complete, existing=%s" % has_save)
	if args.has("new") or (args.has("play") and not has_save):
		new_game()
		_play()
	elif args.has("play") and has_save:
		load_game()
		_play()
	else:
		if has_save:
			if paced:
				await tree.process_frame
			_title_save_loaded = load_game()
		elif not paced:
			new_game()
		LoadPacer.stage = "Preparing the main menu"
		await LoadPacer.step(tree, 0.99)
		_title(has_save)
	if paced:
		tree.paused = false
	startup_ready = true
	StartupTrace.mark("initial state ready (%s)" % state)
	_after_start.call_deferred()


func _start_optional_play_systems() -> void:
	# Keep offscreen rendering and reflection pipelines off the critical path.
	for i in 8:
		await get_tree().process_frame
	if crowd.game == null:
		StartupTrace.mark("loading near pedestrian assets")
		crowd.setup(self)
		await get_tree().process_frame
	if near_traffic.game == null:
		near_traffic.setup(self)
		await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return
	StartupTrace.mark("starting gameplay map")
	await EmpireMinimap.bake(self, layout)
	StartupTrace.mark("gameplay map ready")
	await get_tree().process_frame
	_start_reflections()


func _start_reflections() -> void:
	StartupTrace.mark("initializing optional reflections")
	# Real reflections (overhaul 2026-11-26; off on Low, and with
	# --noreflect for comparisons): probes that follow you for glass, paint,
	# chrome and wet streets, and a planar mirror for the water.
	if not args.has("noreflect"):
		var refl := CityReflections.new()
		refl.name = "CityReflections"
		add_child(refl)
		refl.view_fn = func() -> Vector3:
			var c := get_viewport().get_camera_3d()
			return c.global_position if c else player.global_position
		refl.indoor_fn = func() -> float:
			var c := get_viewport().get_camera_3d()
			return InteriorKit.camera_weight(get_tree(), c.global_position) if c else 0.0
		refl.light_fn = func() -> Vector3:
			return Vector3(atmosphere.night if atmosphere else 0.0, atmosphere.wetness if atmosphere else 0.0,
				clampf(atmosphere.hour / 24.0, 0.0, 1.0) if atmosphere else 0.0)
		if not args.has("no-mirror"):
			var mirror := WaterMirror.new()
			mirror.name = "WaterMirror"
			mirror.water_fn = layout.is_water
			add_child(mirror)
	else:
		RenderingServer.global_shader_parameter_set("refl_probe", 0.0)
		RenderingServer.global_shader_parameter_set("mirror_on", 0.0)



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
				_spawn_car(ov, player.global_position + Vector3.DOWN * 0.9)
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
		var r0 := p + Vector3.UP * 3.0
		var r1 := p + Vector3.DOWN * 3.0
		if String(args["probe"]).begins_with("line:"):
			# --probe=line:x,y,z,x2,y2,z2 (world): what lies along that line.
			var lv := String(args["probe"]).trim_prefix("line:").split_floats(",")
			r0 = Vector3(lv[0], lv[1], lv[2])
			r1 = Vector3(lv[3], lv[4], lv[5])
		var hits := RenderingServer.instances_cull_ray(r0, r1, get_world_3d().scenario)
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
	if args.has("devserver"):
		# Persistent visual-dev session (tools/citydev): free camera and
		# instant screenshots over HTTP on 127.0.0.1.
		var ds := DevServer.new()
		ds.name = "DevServer"
		add_child(ds)
		ds.start(self, int(args["devserver"]), String(args.get("devshots", "")), args.has("geo"))
	if args.has("fleet"):
		# Captures: one of each traffic kind parked in a row ahead of the hero
		# (the real traffic meshes, shader and instancing, parked encoding),
		# for judging the fleet in the game. "fleet=mid" shows the mid LODs.
		var cw: CityWorld = world as CityWorld
		var lod := String(args["fleet"])
		var su := starter_unit()
		var fwd := Premises.outward(su)
		var base := Premises.door_point(su)
		var side := fwd.cross(Vector3.UP).normalized()
		for k in CityWorld.CAR_KINDS.size():
			var mesh: Mesh = cw.car_mid_meshes[k] if lod == "mid" else cw.car_meshes[k]
			if mesh == null:
				continue
			var at := base + fwd * 10.0 + side * (float(k) - 3.0) * 6.0
			at.y = layout.ground_y(at.x, at.z)
			var b := Basis.looking_at(-side, Vector3.UP)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = 1
			# ("fleet=beams": crawling at 1 mm/s so the night headlight beams
			# show - parked cars keep theirs off.)
			var spd := 0.001 if lod == "beams" else 0.0
			mm.buffer = CityWorld._instance_buffer([[Transform3D(b, at + b.z * 5.0), Color(spd, 5.0, 10.0, 0.0),
				CityWorld.kind_colour(k, CityWorld.CAR_COLORS[k % CityWorld.CAR_COLORS.size()])]])
			mm.custom_aabb = AABB(base - Vector3(40, 10, 40), Vector3(80, 25, 80))   # (instances are in world space)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			add_child(mmi)
			mmi.global_position = Vector3.ZERO
		var eye := base + fwd * 2.0 + Vector3.UP * 2.4 - side * 1.0
		var look := base + fwd * 10.0 + Vector3.UP * 0.6
		if args.has("fleet-zoom"):
			# "--fleet-zoom=k": a rear three-quarter close-up of kind k (as
			# --carcam=rear34 frames your own car).
			var zk := int(args["fleet-zoom"])
			var zat := base + fwd * 10.0 + side * (float(zk) - 3.0) * 6.0
			zat.y = layout.ground_y(zat.x, zat.z)
			look = zat + Vector3.UP * 0.7
			eye = zat + side * 4.4 - fwd * 3.6 + Vector3.UP * 1.6
		camera.cine = func(_dt: float) -> Array:
			return [Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye), 70.0]
	if args.has("shopcam"):
		# Captures: the --goto unit (or the starter shop) from the pavement,
		# looking in through its shopfront (night lighting checks).
		var shop_u: Dictionary = unit_by_id.get(String(args.get("goto", "")), {})
		if String(args.get("goto", "")) == "rival" and not empire.rivals.is_empty():
			shop_u = unit_by_id.get(empire.rivals[0]["unit"], {})
		if shop_u.is_empty():
			shop_u = starter_unit()
		var sf := Premises.outward(shop_u)
		var sb := Premises.door_point(shop_u)
		var s_eye := sb + sf * 8.5 + Vector3.UP * 1.9 + sf.cross(Vector3.UP).normalized() * 1.5
		var s_look := sb - sf * 3.0 + Vector3.UP * 1.6
		camera.cine = func(_dt: float) -> Array:
			return [Transform3D(Basis.looking_at(s_look - s_eye, Vector3.UP), s_eye), 62.0]
	if args.has("shopfronts"):
		# Captures: the decorative shopfront bay nearest you (ShopfrontKit),
		# looking along its street ("--shopfronts=n": the n-th nearest).
		var bays: Array = []
		for w2 in [world, world.mainland]:
			if w2 == null:
				continue
			for k in (w2 as CityWorld)._loaded:
				for b in (w2 as CityWorld)._by_chunk.get(k, []):
					for it in ShopfrontKit.bays_for([b], layout):
						if String(it[0]).begins_with("bay"):
							bays.append(it[1])
		var me := player.global_position
		bays.sort_custom(func(a, b): return (a as Transform3D).origin.distance_to(me) < (b as Transform3D).origin.distance_to(me))
		if not bays.is_empty():
			var bx: Transform3D = bays[mini(int(args["shopfronts"]), bays.size() - 1)]
			var s_eye := bx * Vector3(-3.5, 1.75, 6.5)
			var s_look := bx * Vector3(4.0, 2.1, 0.0)
			camera.cine = func(_dt: float) -> Array:
				return [Transform3D(Basis.looking_at(s_look - s_eye, Vector3.UP), s_eye), 60.0]
	if args.has("homedoor"):
		# Captures: an apartment tower's street entrance from across the pavement.
		var hel: ApartmentElevator = elevators.get(String(args["homedoor"]), elevators.values()[0] if not elevators.is_empty() else null)
		if hel:
			var hd := hel.street_door_world()
			var ho := hel.global_basis.z
			var h_eye := hd + ho * 9.0 + hel.global_basis.x * 2.5 + Vector3.UP * 1.8
			var h_look := hd + Vector3.UP * 2.2
			camera.cine = func(_dt: float) -> Array:
				return [Transform3D(Basis.looking_at(h_look - h_eye, Vector3.UP), h_eye), 62.0]
	if args.has("carcam") and not empire.vehicles.is_empty():
		# Captures: a fixed camera on your first car - front34, rear34, side,
		# side_l, front, rear, nose, tail - for checking the car in the game.
		var cc: Car = cars.get(String(empire.vehicles[-1]["id"]))   # (the last: --own=<model> frames that one)
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
	if args.has("signal-cam"):
		# Captures: the nearest traffic light's heads, from 14 m down the street.
		var best: Transform3D
		var bd := INF
		var here := player.global_position
		for w2 in [world, world.mainland]:
			if w2 == null:
				continue
			for key in (w2 as CityWorld)._all_keys:
				for it in (w2 as CityWorld).chunk_props(key):
					if it[0] == "traffic_light":
						var dd := (it[1] as Transform3D).origin.distance_to(here)
						if dd < bd:
							bd = dd
							best = it[1]
		if bd < INF:
			var head := best * Vector3(3.7, 5.2, 0.0)
			var from := best * Vector3(3.7, 4.0, -14.0)
			camera.cine = func(_dt: float) -> Array:
				return [Transform3D(Basis.looking_at(head - from, Vector3.UP), from), 40.0]
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
	if args.has("photo-targets"):
		_write_photo_targets(String(args["photo-targets"]))
	if args.has("maplegend"):
		EmpireMap.legend = true   # (captures: the map with its key showing)
	if args.has("mapzoom"):
		EmpireMap._view = {"c": Vector2(player.global_position.x, player.global_position.z), "z": float(args["mapzoom"])}
	if args.has("panel"):
		var pn := String(args["panel"])
		if pn == "victory":
			ui.victory()
		elif pn == "rival" and not empire.rivals.is_empty():
			ui.open_rival(unit_by_id[empire.rivals[0]["unit"]])
		elif pn == "firm" and not empire.firms.is_empty():
			var fs2 := CityLife.firms_for_sale(empire)
			ui.open_firm(unit_by_id[(fs2[0] if not fs2.is_empty() else empire.firms[0])["unit"]])
		elif pn == "phonestyle":
			# (captures: the real path – light phone → Character & wardrobe)
			Glass.mode = "light"
			ui.open_phone("character")
			await get_tree().process_frame
			ui.open_style()
		elif pn.begins_with("style"):
			ui._style_tab = pn.get_slice(":", 1) if ":" in pn else "character"
			ui.open_style()
		elif pn == "brand":
			ui.open_brand()
		elif pn == "hq":
			ui.open_hq()
		elif pn == "report":
			empire.advance(1440.0 - empire.minute + 1.0)
		elif pn == "wholesale":
			ui.open_wholesale(wholesaler("west"))
		elif pn == "gallery":
			# (captures: the photo gallery of the first firm for sale)
			var fs3 := CityLife.firms_for_sale(empire)
			if not fs3.is_empty():
				ui._listing(unit_by_id[fs3[0]["unit"]], 0.0)["open"].call()
		elif pn in ["stock", "staff"] and not empire.businesses.is_empty():
			ui.open_manage(empire.businesses[0], pn)
		else:
			ui.open_phone(pn)
	if args.has("phone-shots"):
		# (captures: --phone-shots=<dir> [--phone-sections=a,b]: the phone
		# open on each section in turn, one PNG each)
		_phone_shots.call_deferred(String(args["phone-shots"]), String(args.get("phone-sections", "home,map,market,city500,vehicles,property,you,more,bank,businesses")))
	if args.has("shot"):
		_capture(String(args["shot"]), float(args.get("shot-at", "4")))
	if args.has("selftest"):
		_selftest.call_deferred()
	if args.has("scenarios"):
		var sc: Node = load("res://src/empire/dev/scenarios.gd").new()
		sc.set("game", self)
		add_child(sc)
	if args.has("tour"):
		var tr: Node = load("res://src/empire/dev/tour.gd").new()
		tr.set("game", self)
		add_child(tr)
	if args.has("autoplay"):
		var ap: Node = load("res://src/empire/dev/autoplay.gd").new()
		ap.set("game", self)
		add_child(ap)


func _phone_shots(dir: String, secs: String) -> void:
	await get_tree().create_timer(float(args.get("phone-delay", "5")), true, false, true).timeout
	DirAccess.make_dir_recursive_absolute(dir)
	for sec in secs.split(",", false):
		var parts := sec.split(":")
		ui.open_phone(parts[0])
		if parts.size() > 1 and ui.phone:
			# name:page:arg  (e.g. city500:company:3, market:vehicle:stiletto)
			match parts[1]:
				"company":
					ui.phone.push("company", {"idx": int(parts[2])}, "Company")
				"vehicle":
					ui.phone.push("vehicle", {"model": parts[2], "site": "dealer_luxury"}, EmpireData.vehicle_model(parts[2]).get("name", ""))
				"cat":
					Phone.st(parts[0])["cat"] = parts[2]
					ui.phone.refresh()
				"listing":
					var fs := CityLife.firms_for_sale(empire)
					if not fs.is_empty():
						ui.phone.push("listing", {"id": String(fs[0]["unit"]), "home": false}, String(fs[0]["name"]))
				"sheet":
					if not empire.businesses.is_empty():
						ui.open_manage(empire.businesses[0], parts[2] if parts.size() > 2 else "overview")
		await get_tree().create_timer(float(args.get("phone-wait", "4")), true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, sec.replace(":", "_")])
		print("PHONE_SHOT ", sec)
	get_tree().quit()


# ---------------------------------------------------------------- game
func _reset_vehicle_state() -> void:
	if vehicle_access:
		vehicle_access.interrupt()
	if driving != "":
		var c: Car = cars.get(driving)
		if c and is_instance_valid(c):
			c.occupied = false
			c.throttle = 0.0
			c.brake = 1.0
			c.handbrake = true
			c.power_slide = 0.0
		driving = ""
	if skyport_play:
		skyport_play.force_exit_for_reset()
	if chase:
		chase.target = null
	if drive_input:
		drive_input.enabled = false
		drive_input.car = null
	if car_audio:
		car_audio.set_car(null)
	if speed_fx:
		speed_fx.player = null
	if rig:
		rig.vehicle_seated = false
		rig.vehicle_steer = 0.0
		rig.process_mode = Node.PROCESS_MODE_INHERIT
	if player:
		player.scripted = false
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.visible = true
		player.collision_layer = 1 << 2
		player.input_enabled = state == "play"
	if camera and camera.cam:
		camera.cam.make_current()
	if world and camera:
		world.set_viewer(camera)
	_end_floor()
	_car_safe.clear()
	_pending_vehicle_deliveries.clear()
	_km_acc = 0.0


func new_game() -> void:
	_reset_vehicle_state()
	ExploreUI.reset_cache()
	_tr("new_game: reset")
	empire = Empire.new()
	empire.market = _market()
	var start := starter_unit()
	empire.flags["start_unit"] = start["id"]
	empire.new_game(int(args.get("seed", "1")))
	_tr("new_game: new empire")
	_connect_empire()
	_sync_rivals()
	_tr("new_game: connect + rivals")
	var out := Premises.outward(start)
	var along := Premises.along_dir(start)
	var door := Premises.door_point(start)
	# Your old hatchback, parked at the kerb a few metres along.
	var car_p := _kerb_point(door + out * 6.5 + along * 5.0)
	var v: Dictionary = empire.vehicles[0]
	v["pos"] = [car_p.x, car_p.y, car_p.z]
	v["yaw"] = atan2(-along.x, -along.z)
	_spawn_cars()
	_tr("new_game: spawn cars")
	_obj_sig = ""
	gps.restore()
	_teleport(door + out * 3.2 + Vector3.UP * 1.0, atan2(-out.x, -out.z) + PI)
	_tr("new_game: teleport")
	_tutorial = 0
	# (No forced "open the map" step: the opening is Nadia's offer instead.)
	empire.flags["opened_map"] = true
	if not args.has("autoplay") and not args.has("scenarios") and not args.has("shot"):
		get_tree().create_timer(4.0, false).timeout.connect(_opening_offer)


# ------------------------------------------------------------ the opening
## Two shops to choose from on Westbank: the cheap corner unit you're
## standing outside, and a bigger one near the market (more passing trade,
## more rent) – a real first decision, not a tutorial step.
func opening_units() -> Array:
	var cheap := starter_unit()
	var best := {}
	var bd := INF
	var c0 := Premises.door_point(cheap)
	for u in units:
		if u["kind"] != "shop" or u["island"] != "west" or u["id"] == cheap["id"] or u.get("flagship", false):
			continue
		if float(u["rent"]) < float(cheap["rent"]) * 1.25 or float(u["rent"]) > float(cheap["rent"]) * 2.4:
			continue
		var d := Premises.door_point(u).distance_to(c0)
		if d > 80.0 and d < 600.0 and d < bd:
			bd = d
			best = u
	return [cheap] if best.is_empty() else [cheap, best]


func _opening_offer() -> void:
	if empire == null or not empire.businesses.is_empty() or empire.flags.get("opening_done", false) or state != "play":
		return
	ui.open_opening_offer(opening_units())


func choose_opening(u: Dictionary) -> void:
	empire.flags["opening_done"] = true
	if u.is_empty():
		empire._note("Nadia: No rush – the TO LET boards are all over Westbank. Ring me when you've found one.", "info")
		return
	empire.flags["start_unit"] = String(u["id"])
	empire.flags["seen_car"] = true
	gps.set_destination(Premises.door_point(u), String(u.get("shop_name", "Your shop")))
	empire._note("Nadia: Great – the keys are with the board outside %s. Take a look round before you sign." % String(u.get("shop_name", "the shop")), "good")


## Milestone texts from the people round you, and the first sale.
func _on_sold(_biz: String, amount: float) -> void:
	if int(empire.stats.get("sales", 0)) == 1 and not empire.flags.get("first_sale", false):
		empire.flags["first_sale"] = true
		Sfx.play("chime", 0.0)
		Settings.haptic(60, 0.7)
		var b := empire.business(_biz)
		ui.toast("Your first sale! %s in the till at %s" % [EmpireData.money(amount), b.name if b else "your shop"], "good")
		get_tree().create_timer(6.0, false).timeout.connect(func():
			empire._note("Ray from the café next door: Saw your first customer leave smiling. Welcome to the street – keep the shelves full and they'll come back.", "info"))


## The city's shop units as the economy sees them (CityLife's market).
func _market() -> Array:
	var m: Array = []
	for u in units:
		if u["kind"] == "shop" and not u.get("flagship", false):
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


## Today's sky follows the Empire's weather with natural intra-day breaks so
## rain and fog don't lock the city into one mood all day.
func _sync_weather() -> void:
	if args.has("weather") or state == "title":
		return
	var sky := String(CityLife.weather_def(empire.weather).get("sky", "clear"))
	var h := empire.hour()
	match empire.weather:
		"rain":
			if h < 10.0:
				sky = "cloudy"
			elif h >= 15.5 and h < 19.5:
				sky = "clear"
		"storm":
			if h < 10.5:
				sky = "cloudy"
			elif h >= 16.5 and h < 18.5:
				sky = "rain"
		"foggy":
			if h >= 11.0 and h < 20.5:
				sky = "clear"
	# Passing sun showers on dry days: about one half-hour in nine, picked
	# per day and slot so it's the same on a reload.
	if sky in ["clear", "bright", "cloudy"] and h > 6.5 and h < 21.0:
		var slot := int(h * 2.0)
		if float(hash(Vector2i(empire.day, slot)) % 1000) / 1000.0 < 0.11:
			sky = "showers"
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
	empire.fleet_arrived.connect(func(b: Business, _vid: String): _fleet_drop[b.id] = true)
	empire.stock_delivered.connect(_show_stock_delivery, CONNECT_DEFERRED)
	empire.day_ended.connect(func(r):
		# City500: your position, and the market's day in the news.
		for n in City500.day_ended(empire):
			empire._note(String(n[0]), String(n[1]), {"kind": "tab", "id": "city500"})
		var hl := City500.headlines(empire.day)
		if not hl.is_empty():
			var pick: Array = hl[empire.day % hl.size()]
			empire.news.append({"day": empire.day, "text": "City500 · " + String(pick[0]), "kind": String(pick[1])})
		ui.day_report(r)
		save_game())
	empire.sold.connect(_on_sold)
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


var _title_focus: Node3D
const TITLE_HOUR := 19.2   # (fallback when no title view loads)
var _title_hour := TITLE_HOUR
var _title_view := {}
var _title_r := {}
var _title_t := 0.0
## Scene data is ready independently of render submission.
var startup_ready := false
var title_ready := false
var _optional_play_scheduled := false
var _title_hero_vis := true


func _title(has_save: bool) -> void:
	state = "title"
	player.input_enabled = false
	_title_hero_vis = player.visible
	player.visible = false   # (the views are the city, not the hero)
	if audio:
		audio.menu = true
	if _title_focus == null:
		_title_focus = Node3D.new()
		_title_focus.name = "TitleFocus"
		add_child(_title_focus)
	apply_title_view(TitleViews.pick(String(args.get("title-view", ""))), LoadPacer.active)
	ui.show_title(has_save, _title_view)
	title_ready = true
	if args.has("title-tour"):
		_title_tour.call_deferred(String(args["title-tour"]))
	if args.has("enter"):
		_profile_enter.call_deferred(String(args["enter"]))


## --enter=continue|new|character [--load-timing]: presses the menu's button
## (with its navy dip) once the menu has settled, then reports each step,
## the main-thread block, when streaming round the hero has caught up and
## every hitch in the next 8 s. Quits when done.
func _profile_enter(kind: String) -> void:
	while not title_ready:
		await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	var tm: Node = ui.title_menu
	if kind == "confirm":   # (a look at the new-game warning)
		tm._confirm_new()
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(args.get("shot-out", "user://confirm.png")))
		get_tree().quit()
		return
	var cb: Callable
	match kind:
		"new":
			cb = start_new
		"character":
			cb = func():
				continue_game()
				ui.open_style()
				_tr("character: open_style")
		_:
			cb = continue_game
	var t_press := Time.get_ticks_usec()
	var t_cb := [0, 0]
	var wrapped := func():
		_tr_us = Time.get_ticks_usec()
		t_cb[0] = Time.get_ticks_usec()
		cb.call()
		t_cb[1] = Time.get_ticks_usec()
	tm._enter(wrapped)
	while t_cb[1] == 0:
		await get_tree().process_frame
	print("ENTER_SUMMARY %s: press→callback %.0f ms (the dip), callback (main thread blocked) %.0f ms" % [kind, (t_cb[0] - t_press) / 1000.0, (t_cb[1] - t_cb[0]) / 1000.0])
	var t0 := Time.get_ticks_usec()
	var worst := 0.0
	var cpu_worst := 0.0
	var over := {"34": 0, "50": 0, "100": 0, "250": 0}
	var settled_at := -1.0
	var quiet := 0
	var frames := 0
	var last := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 8000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		frames += 1
		worst = maxf(worst, dt)
		# (Script + physics CPU per frame, without the VPS's software renderer.)
		var cpu := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		cpu_worst = maxf(cpu_worst, cpu)
		if cpu > 100.0:
			print("SLOW frame %d after entering: CPU %.0f ms (process %.0f, physics %.0f)" % [frames, cpu,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
		for k in over:
			if dt > float(k):
				over[k] += 1
		var busy: bool = not world._pending.is_empty() or not world._results.is_empty()
		quiet = 0 if busy else quiet + 1
		if settled_at < 0.0 and quiet >= 5:
			settled_at = (now - t_cb[0]) / 1000.0
	print("ENTER_SUMMARY %s: streaming settled %.0f ms after the press's callback began; next 8 s: %d frames, worst %.0f ms, >34 ms %d, >50 ms %d, >100 ms %d, >250 ms %d; worst frame CPU (process+physics) %.0f ms" % [
		kind, settled_at, frames, worst, over["34"], over["50"], over["100"], over["250"], cpu_worst])
	get_tree().quit()


## Puts the menu camera on a view: its hour, its weather, the world built
## round what it sees, and the slow dolly.
func apply_title_view(v: Dictionary, stream_details := false) -> void:
	if v.is_empty():
		v = {"id": "bridges", "name": "Harbour Bridges", "mood": "Blue hour", "hour": TITLE_HOUR, "weather": "clear", "fov": 56,
			"eye": [268, 42, 840], "look": [-38, 29, 817], "focus": [96, 10, 795]}
	_title_view = v
	_title_r = TitleViews.resolve(v, layout)
	_title_t = 0.0
	_title_hour = float(v.get("hour", TITLE_HOUR))
	atmosphere.hour = _title_hour
	atmosphere.set_weather(String(v.get("weather", "clear")), true)
	var focus: Vector3 = _title_r["focus"]
	_title_focus.global_position = focus
	world.set_viewer(_title_focus)
	if not stream_details:
		if skyport and SkyportIsland.distance_to(focus) < SkyportIsland.NEAR_LOAD and not skyport.near_loaded():
			skyport.load_near_now()
		if venues:
			venues.load_near_now(focus)
		world.build_all_near(focus, 340.0)
	var dur := float(v.get("dur", 42.0))
	var fov := float(v.get("fov", 52.0))
	camera.cine = func(dt: float) -> Array:
		_title_t += dt
		return [TitleViews.at(_title_r, dur, _title_t), fov]
	camera.snap()


## Review: every title view in turn, one PNG each (--title-ui keeps the menu).
func _title_tour(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var wait := float(args.get("title-wait", "6"))
	var only := String(args.get("title-only", ""))
	if not args.has("title-ui"):
		ui._title_root.visible = false
	for v in TitleViews.all():
		var id := String(v.get("id", ""))
		if only != "" and not id in only.split(","):
			continue
		apply_title_view(v)
		if args.has("title-ui"):
			ui.show_title(true, v)
			ui.title_reveal(0.0)
		_title_t = float(args.get("title-at", "8"))
		await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join(id + ".png"))
		print("TITLE_SHOT ", id, " ", JSON.stringify({"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}))
	get_tree().quit()


func start_new() -> void:
	StartupTrace.mark("Begin or confirmed New game selected")
	new_game()
	save_game()
	_tr("start_new: save_game")
	_play()


func continue_game() -> void:
	StartupTrace.mark("Continue selected")
	# The menu loaded this save at launch and nothing on the title changes it
	# (the sim only runs in play): loading it again re-made the empire, cars,
	# interiors and the hero's streets for nothing (2026-11-27).
	if not (state == "title" and _title_save_loaded):
		load_game()
	_play()


func _play() -> void:
	var from_title := state == "title"
	_title_save_loaded = false   # (only the first entry from the launch menu reuses it)
	state = "play"
	title_ready = true
	camera.cine = Callable()
	if from_title:
		player.visible = _title_hero_vis
	if audio:
		audio.menu = false
	_tr("_play: begin")
	if from_title:
		# (The title streamed round its view: the hero's street now.)
		world.build_all_near(player.global_position, 260.0)
		_tr("_play: world.build_all_near 260 m")
	world.set_viewer(chase if driving != "" else camera)   # (the title streamed round its own camera)
	camera.snap()
	player.input_enabled = driving == ""
	ui.show_hud()
	_tr("_play: viewer + hud")
	StartupTrace.mark("gameplay ready (spawn and HUD)")
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(
			func(): StartupTrace.mark("first gameplay frame submitted"), CONNECT_ONE_SHOT)
	if not _optional_play_scheduled:
		_optional_play_scheduled = true
		_start_optional_play_systems.call_deferred()
	if empire.flags.get("intro_done", false) == false and not args.has("shot") and not args.has("tour") and not args.has("autoplay") and not args.has("perf") \
			and not args.has("scenarios"):
		ui.intro()
	if not DisplayServer.is_touchscreen_available() and not args.has("touch") and not args.has("shot") and not args.has("tour"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


const TELEPORT_SKYPORT_NOW := 120.0


func _teleport(p: Vector3, yaw: float) -> void:
	vehicle_access.interrupt()
	# Arriving ON Skyport Island (or at its shore) its buildings must be solid
	# now. Further off (within NEAR_LOAD, 850 m: both start spots) it streams
	# its near detail in one step a frame by itself – forcing all of it here
	# was ~1.9 s of every New game / Continue on the VPS (2026-11-27).
	if skyport and SkyportIsland.distance_to(p) < TELEPORT_SKYPORT_NOW and not skyport.near_loaded():
		skyport.load_near_now()
		_tr("  teleport: skyport near")
	if venues:
		venues.load_near_now(p)
		_tr("  teleport: venues near")
	world.build_all_near(p, 300.0)
	_tr("  teleport: world.build_all_near 300 m")
	if empire:
		_stream_street_rooms(p, 24.0, 4)
		_tr("  teleport: street rooms")
	# A save made in (or over) the sea used to reload you there and remember
	# that spot as dry ground: the wading check then sent you back to it for
	# ever. Somewhere safe instead.
	if safe and layout.is_water(p) and not safe.is_safe(p + Vector3.DOWN * 1.0):
		var f := safe.find(p, HERO_BOX, {"kind": "foot", "fallbacks": [_dry_pos]})
		if f["ok"]:
			p = (f["pos"] as Vector3) + Vector3.UP * 1.0
	player.respawn(p)
	player.last_safe_position = p
	_dry_pos = p if not layout.is_water(p) else Vector3.INF
	_wet_t = 0.0
	camera.face(yaw)


## A point on the street surface near p (car spawns).
func _kerb_point(p: Vector3) -> Vector3:
	var g := layout.ground_y(p.x, p.z)
	if layout.mainland and p.x < CityLayout.FAR_SHORE:
		g = layout.mainland.ground_y(p.x, p.z)
	return Vector3(p.x, g + 0.35, p.z)


func _surface_sound_at(p: Vector3) -> String:
	if driving == "" and player.indoors:
		return "interior"
	var at := Vector2(p.x, p.z)
	var map := layout.mainland if layout.mainland and p.x < CityLayout.FAR_SHORE else layout
	if absf(p.y - map.ground_y(p.x, p.z)) < 3.0 and map.is_park(at):
		return "grass"
	if map.roads.on_road(at) or (driving != "" and p.y > map.ground_y(p.x, p.z) + 2.1):
		return "wet_asphalt" if atmosphere.wetness > 0.32 else "asphalt"
	return "paving"


# --------------------------------------------------------------- frame
## The apartment you were last in (flags.last_home): the app starts you
## there (2026-11-26). Checked every couple of seconds.
var _home_t := 0.0


func _track_home(dt: float) -> void:
	_home_t -= dt
	if _home_t > 0.0 or empire == null or driving != "" or player == null:
		return
	_home_t = 2.0
	var p := player.global_position
	for home in homes():
		var h: Dictionary = home["h"]
		var f := Apartments.to_face(h, p)
		# (to_face: x along, y out of the facade, z height)
		if f.x > float(h["a0"]) and f.x < float(h["a1"]) and f.y < 0.0 and f.y > -float(h["depth"]) - 0.2 \
				and f.z > float(h["y0"]) - 0.3 and f.z < float(h["y0"]) + 3.0:
			empire.flags["last_home"] = String(home["id"])
			return


## Inside the last apartment you were in, if it's still yours to live in.
func _home_spawn() -> Dictionary:
	var hid := String(empire.flags.get("last_home", ""))
	if hid == "" or not empire.owns_property(hid):
		return {}
	var q := empire.properties.filter(func(x): return x["id"] == hid)
	if not q.is_empty() and q[0].get("let", false):
		return {}
	var home := home_by_id(hid)
	if home.is_empty():
		return {}
	var h: Dictionary = home["h"]
	var a := (float(h["a0"]) + float(h["a1"])) * 0.5 + (float(h["a1"]) - float(h["a0"])) * 0.2
	var p := Apartments.face_point(h, a, -1.7, float(h["y0"]) + 1.0)
	var o := Apartments.outward(h)
	return {"pos": p, "yaw": atan2(o.x, o.z)}


func _process(dt: float) -> void:
	_track_home(dt)
	if empire == null:
		return
	var sim_dt := minf(dt, 0.1)
	if state == "play" and not get_tree().paused:
		var k := time_scale if driving == "" and floor == null else 1.0
		var t0 := Time.get_ticks_usec()
		empire.advance(sim_dt * minutes_per_second * k)
		_perf_sim += Time.get_ticks_usec() - t0
		player.walk_speed_scale = float(empire.active_buff().get("walk_speed", 1.0))
	if rig:
		var phone_up: bool = ui != null and ui.phone != null and is_instance_valid(ui.phone) and ui.phone.visible
		rig.using_phone = phone_up and driving == "" and (skyport_play == null or skyport_play.piloting == "")
	if not atmosphere.fixed_hour:
		atmosphere.hour = empire.hour() if state != "title" else _title_hour
	_stream_t -= dt
	if _stream_t <= 0.0:
		_stream_t = 0.4
		_sync_weather()
		_sync_rivals()
		_sync_brand()
		_stream_interiors()
		_update_live_floor()
		for id: String in interiors:
			_refresh_signs(id)
		if state == "play" and args.has("objective-gps"):
			# (Off since 2026-11-26: the objective no longer routes itself –
			# no permanent route on screen; Go on the phone sets it.)
			_objective_gps()
			_update_stadium()
			_update_pursuit()
			ExploreUI.discover(self)
	if state != "play":
		return
	if vehicle_access.active():
		vehicle_access.tick(dt)
		return
	_drain_interiors()
	_tick_elevators(dt)
	_update_spot()
	_update_indoors()
	if floor and floor.room:
		# (Shoppers and staff step round you.)
		floor.hero_at = floor.room.to_local(player.global_position) if driving == "" else Vector3.INF
	_update_carry_visual()
	if driving != "":
		_track_driving(dt)
	elif skyport_play and skyport_play.piloting != "":
		skyport_play.track(dt)
	else:
		_check_wading(dt)
	_save_t += dt
	if _save_t > 90.0:
		_save_t = 0.0
		save_game(true)
	_tutorial_step()
	ui.update_hud()
	if args.has("perf"):
		_perf_sample(dt)


var _perf_sim := 0
var _perf := {}
var _perf_last_us := 0
var _perf_frames_ms: Array[float] = []


## `--perf=<seconds>`: averages over the run, printed at the end (and quit).
func _perf_sample(dt: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := (now - _perf_last_us) / 1000.0 if _perf_last_us > 0 else 0.0
	_perf_last_us = now
	if _perf.is_empty():
		_perf = {"n": 0, "dt": 0.0, "proc": 0.0, "phys": 0.0, "draw": 0.0, "prim": 0.0, "obj": 0.0, "sim": 0, "floor": 0,
			"cust": 0, "t": 0.0}
	_perf["t"] = float(_perf["t"]) + dt
	if float(_perf["t"]) < 3.0:
		_perf_sim = 0
		return  # (warm-up)
	if elapsed > 0.0:
		_perf_frames_ms.append(elapsed)
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
		print("PERF frames=%d sim_fps=%.1f process=%.2fms physics=%.2fms draws=%.0f prims=%.0fk objects=%.0f sim=%.3fms customers=%.1f mem=%.0fMB" % [
			int(n), n / float(_perf["dt"]), float(_perf["proc"]) / n * 1000.0, float(_perf["phys"]) / n * 1000.0,
			float(_perf["draw"]) / n, float(_perf["prim"]) / n / 1000.0, float(_perf["obj"]) / n,
			float(_perf["sim"]) / n / 1000.0, float(_perf["cust"]) / n, Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6])
		_perf_frames_ms.sort()
		if not _perf_frames_ms.is_empty():
			var count := _perf_frames_ms.size()
			print("FRAME_MS wall_clock p50=%.2f p95=%.2f p99=%.2f max=%.2f samples=%d" % [
				_perf_frames_ms[int((count - 1) * 0.5)], _perf_frames_ms[int((count - 1) * 0.95)],
				_perf_frames_ms[int((count - 1) * 0.99)], _perf_frames_ms[-1], count])
		if Prof.enabled:
			Prof.report(int(n))
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
	elif driving != "" and e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo and (e as InputEventKey).keycode == KEY_H:
		if car_audio:
			car_audio.play_horn()


func toggle_fast() -> void:
	time_scale = 1.0 if time_scale > 1.0 else 4.0
	ui.toast("Time ×%d" % int(time_scale) if time_scale > 1.0 else "Normal time", "info")


# ----------------------------------------------------------- interiors
var _interior_queue: Array = []


func _drain_interiors() -> void:
	while not _interior_queue.is_empty():
		var u: Dictionary = _interior_queue.pop_front()
		if not interiors.has(String(u["id"])):
			_build_interior(u)
			return


func _stream_interiors() -> void:
	var dc: Node3D = cars.get(driving) if driving != "" else null
	var focus := dc.global_position if dc and is_instance_valid(dc) else player.global_position
	if garage and garage.inside and world.stream_anchor:
		focus = world.stream_anchor.global_position
	var to_build: Array = []
	for u in units:
		if u.has("street_use"):
			continue
		var d := Vector2(focus.x, focus.z).distance_to(Vector2(float(u["pos"][0]), float(u["pos"][2])))
		var id: String = u["id"]
		if d < STREAM_IN and not interiors.has(id):
			to_build.append([d, u])
		elif d > STREAM_OUT and interiors.has(id) and floor_unit != id:
			interiors[id].queue_free()
			interiors.erase(id)
	if not to_build.is_empty():
		to_build.sort_custom(func(a, b): return a[0] < b[0])
		if state != "play":
			for i in mini(4, to_build.size()):
				_build_interior(to_build[i][1])
		else:
			# (2026-11-27) In play they're queued, nearest first, and built
			# one per frame (_drain_interiors) – two in one frame were the
			# 35–60 ms hitches driving into a shopping street.
			_interior_queue.clear()
			for i in mini(3, to_build.size()):
				_interior_queue.append(to_build[i][1])
	# Cull active interior point/spot lights when player is outdoors beyond 36 m.
	for id: String in interiors:
		var si: ShopInterior = interiors[id]
		if not is_instance_valid(si) or not si.has_method("set_exterior_lights_active"):
			continue
		var u: Dictionary = unit_by_id.get(id, {})
		if u.is_empty():
			continue
		var d2 := Vector2(focus.x, focus.z).distance_to(Vector2(float(u["pos"][0]), float(u["pos"][2])))
		si.call("set_exterior_lights_active", id == floor_unit or d2 < 36.0)

	_stream_street_rooms(focus, FRONT_IN, 3)


static func _front_key(at: Vector2) -> Vector2i:
	return Vector2i((at / FRONT_CELL).floor())


func _stream_street_rooms(focus: Vector3, radius: float, budget: int) -> void:
	var xy := Vector2(focus.x, focus.z)
	for id: String in _front_rooms.keys():
		if id == floor_unit:
			continue
		var u: Dictionary = unit_by_id[id]
		if xy.distance_squared_to(Vector2(u["pos"][0], u["pos"][2])) > FRONT_OUT * FRONT_OUT:
			interiors[id].queue_free()
			interiors.erase(id)
			_front_rooms.erase(id)
	var nearby: Array = []
	var lo := _front_key(xy - Vector2.ONE * radius)
	var hi := _front_key(xy + Vector2.ONE * radius)
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			for u: Dictionary in _front_cells.get(Vector2i(x, z), []):
				if interiors.has(u["id"]):
					continue
				var dist := xy.distance_squared_to(Vector2(u["pos"][0], u["pos"][2]))
				if dist < radius * radius and absf(focus.y - float(u["pos"][1])) < 25.0:
					nearby.append([dist, u])
	nearby.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(budget, nearby.size()):
		_build_interior(nearby[i][1])


func _build_interior(u: Dictionary) -> ShopInterior:
	var si := ShopInterior.new()
	if u["kind"] == "office":
		si.office = Offices.at(empire, u["id"])
	var b := empire.business_at(u["id"])
	var ground := layout.ground_y
	if u.get("island", "") == "skyport":
		ground = func(x: float, z: float) -> float:
			var p := SkyportIsland.l(Vector3(x, 0.0, z))
			return SkyportIsland.ground_y_local(p.x, p.z)
	if smash:
		si.front_state = smash.state_for(String(u["id"]))   # (a smashed window stays smashed)
	si.setup(u, b, ground, occupier(u["id"]) if b == null and not u.has("street_use") else {})
	add_child(si)
	interiors[u["id"]] = si
	if u.has("street_use"):
		_front_rooms[u["id"]] = true
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
	var local := si.to_local(player.global_position)
	var occupied := local.x > 0.0 and local.x < si.W and local.z < 0.0 and local.z > -si.D and absf(local.y - 1.0) < 1.6
	if not si.rival.is_empty():
		var h := empire.hour()
		si.update_signs(h >= 7.0 and h < (22.0 if si.rival.get("firm", false) else 23.0), h < 6.5 or h >= 21.5, occupied)
		return
	var trading := (si.unit.has("street_use") and b == null) or (b != null and b.open and b.within_hours(empire.hour()))
	si.update_signs(trading, false, occupied)


## Branches whose delivery is your own fleet's (the van wears your livery).
var _fleet_drop := {}


func _show_stock_delivery(b: Business) -> void:
	var own := _fleet_drop.has(b.id)
	_fleet_drop.erase(b.id)
	if state != "play":
		return
	var si: ShopInterior = interiors.get(b.premises["id"])
	if not is_instance_valid(si) or si.kind != "shop":
		return
	var door_at := si.to_world(si.door_out)
	if door_at.distance_squared_to(player.global_position) > 55.0 * 55.0:
		return
	var bay := _delivery_bay(door_at)
	var truck := world._load_mesh("car_van") if bay.origin != Vector3.INF else null
	if truck and not truck.has_meta("dressed"):
		VehicleTex.dress_mesh(truck, "car_van")   # (cached mesh: once)
		truck.set_meta("dressed", true)
	si.show_stock_delivery(bay, truck, _delivery_van_start(bay) if truck else Vector3.INF)
	if args.has("sc-debug"):
		print("    delivery: own=%s bay=%s truck=%s shown=%s" % [own, bay.origin, truck != null, is_instance_valid(si._delivery_truck)])
	if own and truck and is_instance_valid(si._delivery_truck):
		_livery(si._delivery_truck, truck.get_aabb())


## Your company's livery on a van: brand-coloured side panels with the name
## and the logo initials (Company), both sides.
func _livery(van: Node3D, bounds: AABB) -> void:
	var cols := Company.colours(empire)
	var nm := Company.name_of(empire).to_upper()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cols[0]
	mat.roughness = 0.35
	mat.metallic = 0.2
	var span := bounds.size.z * 0.56
	var hgt := bounds.size.y * 0.34
	var cz := bounds.get_center().z + bounds.size.z * 0.12   # (the load box, behind the cab: front is -Z)
	var cy := bounds.position.y + bounds.size.y * 0.55
	for side: float in [-1.0, 1.0]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(span, hgt)
		q.mesh = qm
		q.material_override = mat
		var x := bounds.get_center().x + side * (bounds.size.x * 0.5 + 0.012)
		q.position = Vector3(x, cy, cz)
		q.rotation.y = side * PI * 0.5
		van.add_child(q)
		var lb := Label3D.new()
		lb.text = "%s\n%s" % [nm, "Deliveries" if SupplyChain.has_warehouse(empire) else ""]
		lb.font = ShopStyle.font(String(empire.brand.get("face", ""))) if Company.has_brand(empire) else EmpireStyle.font("black")
		lb.font_size = 64
		lb.pixel_size = minf(0.006, span * 0.8 / maxf(nm.length() * 38.0, 1.0))
		lb.modulate = cols[1]
		lb.shaded = false
		lb.double_sided = false
		lb.outline_size = 0
		lb.position = Vector3(x + side * 0.004, cy, cz)
		lb.rotation.y = side * PI * 0.5
		van.add_child(lb)


## A business grew a level: rebuild the shop so the fit-out shows now.
func refresh_business_world(b: Business) -> void:
	rebuild_interior(String(b.premises.get("id", "")))
	Sfx.play("chime", -4.0)


## Keep the delivery van on a free parking strip, clear of an intersection.
func _delivery_bay(door_at: Vector3) -> Transform3D:
	var missing := Transform3D(Basis.IDENTITY, Vector3.INF)
	if not gps.ready_net():
		return missing
	var lane := gps.net.nearest(door_at, Vector3.ZERO, 34.0, -1, true)
	if lane.is_empty():
		return missing
	var id: int = lane["lane"]
	var near := gps.net.lane_point(id, lane["s"])
	var direction := gps.net.lane_dir(id, lane["s"])
	direction = Vector3(direction.x, 0, direction.z).normalized()
	if direction.is_zero_approx():
		return missing
	var side := Vector3(-direction.z, 0.0, direction.x)
	if side.dot(door_at - near) < 0.0:
		side = -side
	var roads := layout.mainland.roads if layout.mainland and door_at.x < CityLayout.FAR_SHORE else layout.roads
	var basis := Basis.looking_at(direction, Vector3.UP)
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.35, 1.55, 5.9)
	query.shape = box
	query.collision_mask = CityWorld.PROPS_LAYER | CityWorld.SOLID_LAYER | Car.BODY_LAYER | 1
	var space := get_world_3d().direct_space_state
	for along: float in [0.0, 6.4, -6.4, 12.8, -12.8]:
		for offset: float in [0.6, 1.5, 2.4, 3.3, 4.2]:
			var p := near + direction * along + side * offset
			var field := roads.field_at(Vector2(p.x, p.z))
			var inset := field.y - absf(field.x)
			if field.y < 7.0 or field.w < 9.0 or inset < 1.2 or inset > 2.0:
				continue
			p = _kerb_point(p) - Vector3.UP * 0.31
			query.transform = Transform3D(basis, p + Vector3.UP * 1.02)
			if space.intersect_shape(query, 1).is_empty():
				return Transform3D(basis, p)
	return missing


func _delivery_van_start(bay: Transform3D) -> Vector3:
	var roads := layout.mainland.roads if layout.mainland and bay.origin.x < CityLayout.FAR_SHORE else layout.roads
	var stroke := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.35, 1.48, 5.9)
	stroke.shape = box
	stroke.collision_mask = CityWorld.PROPS_LAYER | CityWorld.SOLID_LAYER | Car.BODY_LAYER | 1
	var space := get_world_3d().direct_space_state
	for distance: float in [4.8, 3.2, 1.8]:
		var start := _kerb_point(bay.origin + bay.basis.z * distance) - Vector3.UP * 0.31
		if absf(start.y - bay.origin.y) > distance * 0.12:
			continue
		var field := roads.field_at(Vector2(start.x, start.z))
		var inset := field.y - absf(field.x)
		if field.y < 7.0 or field.w < 9.0 or inset < 1.2 or inset > 2.2:
			continue
		stroke.transform = Transform3D(bay.basis, start + Vector3.UP * 1.02)
		stroke.motion = bay.origin - start
		var motion := space.cast_motion(stroke)
		if not motion.is_empty() and motion[0] >= 1.0 and space.intersect_shape(stroke, 1).is_empty():
			return start
	return Vector3.INF


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
	var in_elev := false
	if driving == "":
		var p := player.global_position
		for id in interiors:
			var si: ShopInterior = interiors[id]
			if si.global_transform.origin.distance_squared_to(p) < 6400.0 and si.contains(p):
				ceiling = si.global_transform.origin.y + si.H
				break
		if ceiling == INF and venues:
			ceiling = venues.ceiling_at(p)
		if ceiling == INF and garage and garage.inside:
			if garage.lift and garage.lift.is_inside_cabin(p):
				ceiling = garage.lift.global_position.y + garage.lift.cabin_y + ApartmentElevator.CAB_H - 0.05
				in_elev = true
			else:
				ceiling = garage.global_position.y + VehicleGarage.H - 0.1
		if ceiling == INF:
			for el: ApartmentElevator in elevators.values():
				if el.is_inside_cabin(p):
					ceiling = el.global_position.y + el.cabin_y + ApartmentElevator.CAB_H - 0.05
					in_elev = true
					break
				elif el.is_inside_lobby(p):
					var at_upper := absf(p.y - (el.global_position.y + el.top_y + 0.95)) < 2.2
					ceiling = el.global_position.y + (el.top_y + 2.8 if at_upper else ApartmentElevator.LOBBY_H)
					break
	player.indoors = ceiling < INF
	if audio:
		audio.shelter = 1.0 if player.indoors else (0.6 if driving != "" else 0.0)
	camera.indoor_ceiling = ceiling
	camera.in_elevator = in_elev
	if atmosphere.rain_fx:
		atmosphere.rain_fx.sheltered = ceiling < INF
	var close := camera.cam.global_position.distance_squared_to(player.global_position) < 12.25
	# (Outdoors the close-up fill fades at night: at full strength it lit the
	# hero like daylight on a dark street – night rebalance 2026-11-26.)
	var out_fill := 0.27 * lerpf(1.0, 0.6, atmosphere.night) if atmosphere else 0.27   # (0.25 left the hero a silhouette by the shops)
	_hero_fill(1.0 if ceiling < INF else (out_fill if close and driving == "" else 0.0))


## Indoors the building shadows the sun and the hero (dark clothes, deep skin
## tones) went to a silhouette against bright shelving. A soft light on the
## camera's side that lights only the hero (its own render layer), faded in
## while you're inside.
var _fill: OmniLight3D
var _portrait_rim: OmniLight3D
var _fill_e := 0.0


func _hero_fill(amount: float) -> void:
	if _fill == null:
		_fill = OmniLight3D.new()
		_fill.name = "HeroFill"
		_fill.light_cull_mask = CharacterRig.HERO_LIGHT_LAYER
		_fill.shadow_enabled = false
		_fill.omni_range = 5.0
		_fill.omni_attenuation = 0.6
		_fill.light_color = Color(1.0, 0.96, 0.9)
		_fill.light_specular = 0.2
		add_child(_fill)
	_fill_e = move_toward(_fill_e, amount, get_process_delta_time() * 2.0)
	_fill.visible = _fill_e > 0.01
	if _fill.visible:
		var h := player.global_position + Vector3.UP * 0.4
		var c := camera.cam.global_position
		var to_c := Vector3(c.x - h.x, 0.0, c.z - h.z).normalized()
		_fill.global_position = h + to_c * 1.6 + to_c.cross(Vector3.UP) * 0.6 + Vector3.UP * 1.0
		_fill.light_energy = 1.1 * _fill_e


## The wardrobe's preview light (the game is paused, so _hero_fill doesn't
## run): the same hero-only fill, brighter, from the camera's side, so deep
## skin tones and dark clothes read instead of a silhouette.
func studio_light(on: bool) -> void:
	_hero_fill(0.0)
	_fill_e = 0.0
	_fill.visible = on
	if not on:
		_fill.omni_range = 5.0
		_fill.light_color = Color(1.0, 0.96, 0.9)
		if _portrait_rim:
			_portrait_rim.hide()
		return
	var head := (rig.bones["head"] as Node3D).global_position
	var cam_pos := camera.cam.global_position
	var front := Vector3(cam_pos.x - head.x, 0.0, cam_pos.z - head.z).normalized()
	var side := front.cross(Vector3.UP)
	_fill.global_position = head + front * 1.45 - side * 0.8 + Vector3.UP * 0.65
	_fill.omni_range = 5.0
	_fill.light_color = Color(1.0, 0.95, 0.88)
	_fill.light_energy = 1.62
	if _portrait_rim == null:
		_portrait_rim = OmniLight3D.new()
		_portrait_rim.name = "PortraitRim"
		_portrait_rim.light_cull_mask = CharacterRig.HERO_LIGHT_LAYER
		_portrait_rim.light_color = Color(0.72, 0.83, 1.0)
		_portrait_rim.light_energy = 0.40
		_portrait_rim.light_specular = 0.14
		_portrait_rim.omni_range = 4.2
		_portrait_rim.omni_attenuation = 0.85
		add_child(_portrait_rim)
	_portrait_rim.global_position = head - front * 0.45 + side * 1.35 + Vector3.UP * 0.42
	_portrait_rim.show()


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
			if si.global_transform.origin.distance_to(p) > 80.0:
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
		# down (they stack in the stockroom staging area).
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
			if not car.visible:
				continue   # (in the lock-up)
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
	if garage and not in_vehicle() and not player.stunned:
		# The Vehicle Collection: a button beside every lift you own (down),
		# the lift doors in the garage (back up).
		var gs := garage.spot_near(player.global_position)
		if not gs.is_empty() and float(gs["d"]) < best_d:
			best = gs
			best_d = float(gs["d"])
		for hid: String in elevators:
			if not empire.owns_property(hid):
				continue
			var el: ApartmentElevator = elevators[hid]
			var gb := el.ground_call_world() + el.global_basis.x * 1.1
			var dg := player.global_position.distance_to(gb + Vector3.UP * 0.9)
			if dg < 1.6 and dg < best_d:
				best = {"kind": "garage_down", "home": hid, "world": gb}
				best_d = dg
	if street_cars and not in_vehicle() and not player.stunned and best_d > 0.9:
		# Any other car you're standing at: steal it.
		var sc := street_cars.spot_near(player.global_position)
		if not sc.is_empty() and float(sc["d"]) * 0.9 < best_d:
			best = sc
			best_d = float(sc["d"]) * 0.9
	var changed: bool = best.get("kind", "") != spot.get("kind", "") or best.get("slot", -9) != spot.get("slot", -9) \
		or best.get("vehicle", "") != spot.get("vehicle", "") or best.get("interior") != spot.get("interior") \
		or best.get("site") != spot.get("site") or best.get("model") != spot.get("model") \
		or best.get("venue_spot") != spot.get("venue_spot") or best.get("home", "") != spot.get("home", "") \
		or best.get("to_top", false) != spot.get("to_top", false)
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
		# (Only offered once the car is slow enough to leave — matches exit_vehicle threshold.)
		var dc: Car = cars.get(driving)
		var slow := dc == null or Vector2(dc.linear_velocity.x, dc.linear_velocity.z).length() <= 1.15
		if street_cars and not street_cars.store_spot().is_empty():
			return ["STORE IN GARAGE", true]
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
		"street_reception":
			if String(si.unit.get("street_use", "")) == "fitness":
				return ["WORK OUT · %s (£15)" % String(si.unit["name"]).to_upper(), empire.personal_cash >= 15.0]
			return ["RECEPTION · " + String(si.unit["name"]).to_upper(), true]
		"retail_checkout":
			return ["BROWSE · " + String(si.unit.get("name", "CHECKOUT")).to_upper(), true]
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
			if u.get("flagship", false):
				return ["BUSINESS PREMISES · " + String(u["name"]).to_upper(), true]
			var rv := CityLife.rival_at(empire, u["id"])
			if not rv.is_empty():
				return ["%s · BUY OUT %s" % [String(CityLife.rival_cfg().get("name", "QuikSave")).to_upper(), EmpireData.money(CityLife.rival_price(rv))], true]
			var fm := CityLife.firm_at(empire, u["id"])
			if not fm.is_empty() and String(fm.get("type", "")) == "clothing":
				return ["%s · SHOP CLOTHES" % String(fm["name"]).to_upper(), true]
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
				return ["CALL LIFT · %s" % String(home["name"]).to_upper(), true]
			if String(home.get("estate", "")) != "":
				return ["%s · COMES WITH %s" % [String(home["name"]).to_upper(), String(Ventures.estate_def(home["estate"])["name"]).to_upper()], true]
			return ["FOR SALE · %s · %s" % [home["name"], EmpireData.money(float(home["price"]))], true]
		"elev_call_g":
			return ["CALL ELEVATOR TO LOBBY", true]
		"elev_call_top":
			var el_t: ApartmentElevator = elevators.get(spot["home"])
			return ["CALL ELEVATOR TO %s" % (el_t.top_floor_label if el_t else "APARTMENT"), true]
		"elev_select":
			return ["CHOOSE A FLOOR", true]
		"home_down":
			return ["CALL ELEVATOR TO STREET", true]
		"home_bed":
			return ["SLEEP TILL 07:00", true]
		"home_wardrobe":
			return ["WARDROBE · CHANGE OUTFIT", true]
		"home_trophies":
			return ["EMPIRE GALLERY · CITY500", true]
		"home_jobs":
			return ["PROPERTY DESK · MANAGE PORTFOLIO", true]
		"car_door":
			var v := empire.vehicle(spot["vehicle"])
			return ["DRIVE %s" % String(EmpireData.vehicle_model(v["model"])["name"]).to_upper(), true]
		"steal_car":
			return street_cars.prompt(spot)
		"garage_down":
			return ["VEHICLE COLLECTION", true]
		"garage_up":
			return ["LIFT · CHOOSE A FLOOR", true]
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


## Moves the cases you're carrying to the stockroom staging area.
func _put_down(b: Business, si: ShopInterior) -> void:
	var n := empire.carried.cases_used()
	for pid in empire.carried.units.keys():
		Stock.transfer(empire.carried, b.floor_pile, pid, empire.carried.qty(pid))
	Sfx.play("drop", -6.0)
	ui.toast("Staged %d case%s in the stockroom. Staff put them on the racks when there's room." % [n, "" if n == 1 else "s"], "info")
	si.refresh_goods()


## The product in your hands that can go on slot i (or "").
func _carried_for(b: Business, slot_i: int) -> String:
	for pid in empire.carried.units:
		if b.can_hold(slot_i, pid) and int(b.slots[slot_i]["qty"]) < int(b.slots[slot_i]["cap"]):
			return pid
	return ""


## Do the current spot's action.
func act() -> void:
	if state != "play" or vehicle_access.active():
		return
	if driving != "":
		var gu: Dictionary = street_cars.store_spot() if street_cars else {}
		if not gu.is_empty():
			street_cars.store_current(gu)
			return
		exit_vehicle(true)
		return
	if skyport_play and skyport_play.piloting != "":
		var why := skyport_play.exit(true)
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
				if rig:
					rig.trigger_interact()
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
		"street_reception":
			var use := String(si.unit["street_use"])
			if use == "fitness":
				var workout := empire.fitness_session(String(si.unit["name"]), 15.0)
				if workout["ok"]:
					Sfx.play("pickup", -5.0, 1.15)
					save_game()
				else:
					ui.toast(String(workout["error"]), "warn")
			elif use == "furniture":
				ui.open_property(si.unit)
			else:
				if use == "garage":
					# The Motor Works desk: the car you came in (nearest) is the one quoted.
					var near_v := ""
					var nd := 60.0
					for k in cars:
						var dk := (cars[k] as Car).global_position.distance_to(player.global_position)
						if dk < nd:
							nd = dk
							near_v = k
					if near_v != "":
						Phone.st("vehicles")["sel"] = near_v
				ui.open_phone({"bank": "finances", "garage": "garage", "warehouse": "businesses"}.get(use, "property"))
		"retail_checkout":
			if String(si.unit.get("street_use", "")) in ["clothing", "department"]:
				ui.open_store("clothes_premium", String(si.unit["name"]))
			else:
				ui.open_public_checkout(si)
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
				var el_h: ApartmentElevator = elevators.get(spot["home"])
				if el_h and not args.has("autoplay"):
					el_h.call_to(false)
					ui.toast("Step inside the elevator and press [%s]" % el_h.top_floor_label, "info")
				else:
					var h: Dictionary = home_by_id(spot["home"])["h"]
					if el_h:
						el_h.snap_to_top(player)
					_teleport(Apartments.spawn_point(h), atan2(Apartments.outward(h).x, Apartments.outward(h).z) + PI)
					Sfx.play("chime", -8.0)
			elif String(home_by_id(spot["home"]).get("estate", "")) != "":
				ui.open_phone("property")   # (the suite / flat come with their building)
			else:
				ui.open_home(home_by_id(spot["home"]))
		"elev_call_g":
			var el_g: ApartmentElevator = elevators.get(spot["home"])
			if el_g:
				Sfx.play("click", -5.0)
				el_g.call_to(false)
		"elev_call_top":
			var el_u: ApartmentElevator = elevators.get(spot["home"])
			if el_u:
				Sfx.play("click", -5.0)
				el_u.call_to(true)
		"elev_select":
			ui.open_lift_floors(String(spot["home"]), false)
		"home_down":
			var el_d: ApartmentElevator = elevators.get(spot["home"])
			if el_d:
				el_d.call_to(true)
			else:
				var home2 := home_by_id(spot["home"])
				var l := home_lift(home2)
				_teleport(l + Apartments.outward(home2["h"]) * 1.5 + Vector3.UP * 1.0, atan2(-Apartments.outward(home2["h"]).x, -Apartments.outward(home2["h"]).z) + PI)
				Sfx.play("bell", -8.0)
		"home_bed":
			sleep_until(7.0)
			save_game()
		"home_wardrobe":
			ui.open_style(false)
		"home_trophies":
			ui.open_phone("city500")
		"home_jobs":
			ui.open_phone("property")
		"car_door":
			enter_vehicle(spot["vehicle"], true)
		"steal_car":
			street_cars.steal(spot)
		"garage_down":
			# The way down is the lift itself: call it, step in, ▼.
			var el_gd: ApartmentElevator = elevators.get(String(spot["home"]))
			if el_gd:
				Sfx.play("click", -5.0)
				el_gd.call_to(false)
				ui.toast("Step into the lift and choose ▼ Vehicle Collection", "info")
		"garage_up":
			ui.open_lift_floors(garage.from_home, true)
		"garage_call":
			Sfx.play("click", -5.0)
			garage.lift.call_to(false)
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
	# doesn't fit stays in the staging area for staff to tidy away).
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
			"" if spill == 0 else " (%d staged: the racks are full)" % spill], "good" if spill == 0 else "warn")
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


# -------------------------------------------------------------- pursuits
## Emergent police chases (StreetPursuit, shared with CitySwing): start once
## the road graph exists; only while you're out in the city.
func _update_pursuit() -> void:
	if pursuit == null:
		if not gps.ready_net() or args.has("no-pursuit"):
			return
		pursuit = StreetPursuit.new()
		pursuit.name = "StreetPursuit"
		add_child(pursuit)
		pursuit.setup(gps.net, _pursuit_focus, func(): return get_viewport().get_camera_3d())
		pursuit.started.connect(func(_at: Vector3):
			ui.toast("Police pursuit nearby", "info"))
		pursuit.ended.connect(_on_pursuit_ended)
		pursuit.can_takedown = func(): return driving != ""
		if args.has("pursuit"):
			pursuit.debug_log = true
			pursuit.debug_cam = args.has("pursuit-cam")
			pursuit.force_start()
	pursuit.enabled = not player.indoors and floor_unit == "" \
		and not (skyport_play != null and skyport_play.piloting != "")


func _pursuit_focus() -> Vector3:
	var v := vehicle_node()
	return v.global_position if v else player.global_position


func _on_pursuit_ended(why: String, _at: Vector3) -> void:
	match why:
		"takedown":
			empire.reward(PURSUIT_REWARD, "Citizen's arrest")
			ui.toast("Citizen's arrest! The police thank you: +%s" % EmpireData.money(PURSUIT_REWARD), "good")
			Sfx.play("cash", -4.0)
		"busted":
			ui.toast("The police caught the getaway car", "info")


# -------------------------------------------------------------- vehicles
func _car_spec(model: String) -> Dictionary:
	var m := EmpireData.vehicle_model(model)
	if m.is_empty() and BodyDims.DIMS.has(model):
		# Captures (--own=<body>): any WorldState body on the Kestrel's
		# handling - police units in their livery, the bus, the Mammoth.
		m = {"base": "hatch", "art": model}
		var cs := CarCatalog.spec("kestrel")
		cs["body"] = model
		CarCatalog._fit_body(cs)
		var pk := model.trim_prefix("police_")
		if CarCatalog.POLICE.has(pk):
			cs["paint"] = (CarCatalog.POLICE[pk]["livery"] as Array)[0]
			cs["paint2"] = (CarCatalog.POLICE[pk]["livery"] as Array)[1]
			cs["wheel"] = CarCatalog.POLICE[pk]["wheel"]
		elif BodyDims.DIMS[model].has("wheel"):
			cs["wheel"] = BodyDims.DIMS[model]["wheel"]
		return cs
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
	for k in ["grip", "brake_force", "turn_rate", "susp_stiff", "roll_gain", "mass_scale", "engine", "engine_gain", "drift_slip", "downforce_gain"]:
		if m.has(k):
			s[k] = m[k]
	return s


func _spawn_cars() -> void:
	for id in cars:
		cars[id].queue_free()
	cars.clear()
	for v in empire.vehicles:
		if SkyportPlay.vclass(String(v["model"])) == "car" and not away(v):
			var c := _spawn_car(v)
			# (Loading: your cars' crumple data is ready before the first
			# knock – it was a 40–70 ms stall on the first dent of a drive.)
			if c:
				CarVisual.warm_dent_cache(String(c.spec["body"]))
	if street_cars:
		street_cars.apply_stored()
	if skyport_play:
		skyport_play.spawn_all()   # (helicopters, planes, boats)


## A car that's out working: on hire at the Skyport desk or on the
## warehouse rounds (Trades / SupplyChain) – not in your garage or street.
static func away(v: Dictionary) -> bool:
	return bool(v.get("hire", false)) or bool(v.get("fleet", false))


## After cars go on hire / the rounds or come back: their bodies leave or
## return (the one you're driving never does).
func sync_away_cars() -> void:
	for v in empire.vehicles:
		var id := String(v["id"])
		if SkyportPlay.vclass(String(v["model"])) != "car" or id == driving:
			continue
		if away(v) and cars.has(id):
			cars[id].queue_free()
			cars.erase(id)
		elif not away(v) and not cars.has(id):
			_spawn_car(v)


## In any vehicle: a car you're driving or a craft you're piloting.
func in_vehicle() -> bool:
	return driving != "" or (skyport_play != null and skyport_play.piloting != "")


## The vehicle you're in (Car or Craft), or null.
## Knocked something over: a thump you feel, not a crash (no damage).
func _on_prop_broke(kind: String, at: Vector3, by: Car) -> void:
	if by != vehicle_node():
		return
	if damage_desk:
		damage_desk.report(kind.replace("_", " "), at, float(Destructibles.COST.get(kind, 160.0 if kind.begins_with("tree") else 40.0)))
	var tree := kind.begins_with("tree")
	if car_audio:
		car_audio.play("crash_heavy_%d" % (randi() % 3) if tree else "crash_light_%d" % (randi() % 2),
			-8.0 if tree else -12.0, randf_range(0.95, 1.1) if tree else randf_range(1.15, 1.35))
	if chase:
		chase.shake(0.28 if tree else (0.08 if kind in ["bin", "bollard", "sign_post", "crates"] else 0.16))
		if tree:
			chase.punch(-2.5)
	if Engine.has_singleton("Haptics") or OS.has_feature("mobile"):
		Input.vibrate_handheld(35 if tree else 15)


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


## `settle_from`: a new car (bought, test drive, gift) is put down on the
## nearest clear road at that point's level via SafeGround.road_spot, and
## the record takes the settled spot.
func _spawn_car(v: Dictionary, settle_from := Vector3.INF) -> Car:
	if SkyportPlay.vclass(String(v["model"])) != "car":
		return null   # (aircraft and boats: SkyportPlay)
	var c := Car.new()
	c.name = "Car_" + String(v["id"])
	var spec := _car_spec(v["model"])
	if v.has("paint"):
		spec["paint"] = Color.from_string(String(v["paint"]), spec["paint"])   # (a stolen car keeps its colour)
	c.setup(spec, "player")
	c.park_lock = true
	add_child(c)
	var vis := CarVisual.new()
	c.add_child(vis)
	vis.setup(c)
	c.visual = vis
	var p := Vector3(float(v["pos"][0]), float(v["pos"][1]), float(v["pos"][2]))
	var yaw := float(v.get("yaw", 0.0))
	if safe and layout.is_water(p) and p.y < Car.WATER_Y + 1.5:
		# (Saved sunk in the sea: towed out on load, not left to loop.)
		var f := safe.find(p, c.spec["size"], {"kind": "car"})
		if f["ok"]:
			p = f["pos"]
			yaw = f["yaw"] if not is_nan(float(f["yaw"])) else yaw
	c.place(Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 0.3))
	# Damage comes back with the car (parked, stored, saved): mechanical
	# state, glass, lamps, paint, and the dents replayed into the body.
	c.apply_damage_state(v.get("damage", {}))
	vis.apply_visual_state(v.get("dent_state", {}))
	if settle_from != Vector3.INF and safe:
		var rs := safe.road_spot(settle_from, c.spec["size"], {"exclude": [c.get_rid(), player.get_rid()], "min_d": 3.0})
		if rs["ok"]:
			var rx: Transform3D = rs["xf"]
			c.place(Transform3D(rx.basis, rx.origin + rx.basis.y * 0.35))
			v["pos"] = [rx.origin.x, rx.origin.y, rx.origin.z]
			v["yaw"] = rx.basis.get_euler().y
	c.splashed.connect(func(at: Vector3, spd: float):
		var sc := clampf(c.mass / 1400.0, 0.85, 1.65)
		if vfx:
			vfx.splash(at, spd, sc)
		if audio:
			audio.play("splash", clampf(lerpf(-5.0, 3.0, spd / 20.0), -5.0, 3.0), clampf(lerpf(1.06, 0.72, spd / 24.0), 0.72, 1.1)))
	vfx.watch(c)
	# Your car's crashes: the camera feels them (shake + a punch on heavy
	# frontal hits), the phone buzzes, the dashboard warns about what broke.
	c.impact.connect(func(strength: float, _at: Vector3, _n: Vector3, _o: Object):
		if driving == "" or cars.get(driving) != c or strength < 4.0:
			return
		chase.shake(clampf(strength / 32.0, 0.08, 0.75))
		if strength > 12.0:
			chase.punch(-clampf(strength / 6.0, 1.5, 5.0))
		Settings.haptic(int(clampf(strength * 3.0, 15.0, 80.0)), clampf(strength / 30.0, 0.2, 1.0)))
	c.damaged.connect(_on_own_car_damaged.bind(c))
	cars[v["id"]] = c
	vfx.cars = cars.values()
	return c


## What broke on the car you're driving, said once on screen.
func _on_own_car_damaged(kind: String, what: Variant, _at: Vector3, c: Car) -> void:
	if driving == "" or cars.get(driving) != c or ui == null:
		return
	if kind == "tyre":
		ui.toast("Puncture! %s tyre" % ["Front-left", "Front-right", "Rear-left", "Rear-right"][int(what)], "warn")
	elif kind == "overheat":
		ui.toast("Engine overheating – ease off or get it to a Motor Works", "bad")
	elif kind == "glass" and what is Array and float(what[1]) >= 1.0 and String(what[0]) == "front":
		ui.toast("Windscreen smashed", "warn")


func enter_vehicle(vid: String, animate := false) -> void:
	var c: Car = cars.get(vid)
	if c == null or vehicle_access.active():
		return
	if animate:
		if absf(c.speed) > 1.15 or c.in_water or player.stunned:
			ui.toast("The car needs to be stopped", "warn")
			return
		var found := vehicle_access.landing(c, true)
		if found.is_empty():
			ui.toast("Move to a clear door", "warn")
			return
		chase.set_target(c, true)
		vehicle_access.start(c, true, found, _finish_vehicle_entry.bind(vid), chase.cam)
		return
	_finish_vehicle_entry(Vector3.ZERO, Transform3D.IDENTITY, 64.0, vid)


func _finish_vehicle_entry(_stand: Vector3, _from: Transform3D, _fov: float, vid: String) -> void:
	var c: Car = cars.get(vid)
	if c == null:
		return
	driving = vid
	c.occupied = true
	c.freeze = false
	player.input_enabled = false
	rig.vehicle_seated = c.visual != null and c.visual.has_clear_cabin
	if rig.vehicle_seated:
		_update_driver_pose(c)
		rig.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.visible = rig.vehicle_seated
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.collision_layer = 0
	drive_input.car = c
	drive_input.enabled = true
	speed_fx.player = c
	if _from == Transform3D.IDENTITY:
		chase.set_target(c, true)
	chase.cam.make_current()
	world.set_viewer(chase)
	_last_car_pos = c.global_position
	if c.visual:
		c.visual.enable_headlights(false)
	Sfx.play("click", -6.0)
	car_audio.set_car(c, EmpireData.vehicle_model(String(empire.vehicle(vid).get("model", ""))))


func exit_vehicle(animate := false) -> void:
	if vehicle_access.active():
		return
	var c: Car = cars.get(driving)
	if c == null:
		driving = ""
		return
	if Vector2(c.linear_velocity.x, c.linear_velocity.z).length() > (1.15 if animate else 4.0):
		ui.toast("Stop the car to get out", "warn")
		return
	var found := vehicle_access.landing(c, false)
	if found.is_empty():
		ui.toast("Both sides are blocked. Move to a clear spot.", "warn")
		return
	drive_input.enabled = false
	c.throttle = 0.0
	c.brake = 1.0
	c.handbrake = true
	c.power_slide = 0.0
	if animate:
		vehicle_access.start(c, false, found, _finish_vehicle_exit.bind(driving))
		return
	_finish_vehicle_exit(found["pos"], Transform3D.IDENTITY, 70.0, driving)


func _finish_vehicle_exit(stand: Vector3, from: Transform3D, fov: float, vid: String) -> void:
	var c: Car = cars.get(vid)
	if c == null:
		return
	var v := empire.vehicle(vid)
	var xf := c.global_transform
	v["pos"] = [xf.origin.x, xf.origin.y, xf.origin.z]
	v["yaw"] = xf.basis.get_euler().y
	_store_damage(v, c)
	drive_input.car = null
	drive_input.enabled = false
	speed_fx.player = null
	c.occupied = false
	driving = ""
	car_audio.set_car(null)
	_finish_on_foot(stand, xf.basis.get_euler().y, from, fov)
	if v.get("test", false) and skyport_play:
		skyport_play.end_test(vid)


func _finish_on_foot(stand: Vector3, yaw: float, from: Transform3D, fov: float) -> void:
	rig.vehicle_seated = false
	rig.vehicle_steer = 0.0
	rig.process_mode = Node.PROCESS_MODE_INHERIT
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.visible = true
	player.collision_layer = 1 << 2
	player.respawn(stand)
	player.input_enabled = true
	rig.set_facing(-Basis(Vector3.UP, yaw).z)
	camera.face(yaw)
	if from != Transform3D.IDENTITY:
		camera.blend_from(from, fov)
	camera.cam.make_current()
	world.set_viewer(camera)


func restore_vehicle_view() -> void:
	player.scripted = false
	player.visible = false
	player.input_enabled = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.collision_layer = 0
	if driving != "":
		var car: Car = cars.get(driving)
		if car:
			rig.vehicle_seated = car.visual != null and car.visual.has_clear_cabin
			if rig.vehicle_seated:
				_update_driver_pose(car)
				rig.process_mode = Node.PROCESS_MODE_PAUSABLE
				player.visible = true
			drive_input.car = car
			drive_input.enabled = true
			chase.set_target(car, true)
			chase.cam.make_current()
			world.set_viewer(chase)
	elif skyport_play and skyport_play.piloting != "":
		skyport_play.cam.cam.make_current()
		world.set_viewer(skyport_play.cam)


func _update_driver_pose(car: Car) -> void:
	player.global_position = car.visual.body.to_global(car.visual.driver_seat)
	rig.vehicle_facing = -car.global_basis.z
	rig.vehicle_basis = car.visual.body.global_basis
	rig.vehicle_wheel_offset = car.visual.cabin_profile["wheel"]
	rig.vehicle_roof_room = car.visual.cabin_profile["roof_room"]
	rig.vehicle_ankle_offset = car.visual.cabin_profile["ankle"]
	rig.vehicle_steer = car.steer


func _track_driving(dt: float) -> void:
	var c: Car = cars.get(driving)
	if c == null:
		return
	var p := c.global_position
	RenderingServer.global_shader_parameter_set(&"player_pos", p)
	_km_acc += p.distance_to(_last_car_pos) / 1000.0
	_last_car_pos = p
	if _km_acc > 0.05:
		empire.drive(empire.vehicle(driving), _km_acc)
		_km_acc = 0.0
	vfx.wet_tyre_spray(c, atmosphere.wetness, dt, _spray_on_pavement)
	# Keep the hero with the car (streaming, interaction distances).
	if rig.vehicle_seated:
		_update_driver_pose(c)
	else:
		player.global_position = p + Vector3.UP * 1.5
	if c.in_water and c.water_t > 2.0:
		_recover_car(c)
	elif c.upside_time > 2.0:
		_right_car(c)
	else:
		if garage == null or not garage.inside:
			_sample_car_safe(driving, c, get_process_delta_time())


func _spray_on_pavement(at: Vector3) -> bool:
	var p := Vector2(at.x, at.z)
	var land := layout.mainland if layout.mainland and at.x < CityLayout.FAR_SHORE else layout
	var roads := land.roads
	if roads.field_rect.has_point(p) and roads.on_road(p) and absf(at.y - land.ground_y(at.x, at.z)) < 0.24:
		return true
	# The city road fields stop at the shore. Check the suspended deck
	# and viaduct at their actual height, even where there is land below.
	if at.x >= CityLayout.APPROACH_END and at.x <= CityLayout.RIVER_EDGE + 26.0 \
			and absf(at.z - CityLayout.BRIDGE_Z) < 8.7 and absf(at.y - CityLayout.approach_y(at.x)) < 0.45:
		return true
	if SkyportIsland.enabled:
		var bridge := SkyportIsland.bridge_road_y(layout, at.x, at.z)
		if not is_nan(bridge) and absf(at.y - bridge) < 0.4:
			return true
		var site := SkyportIsland.l(at)
		if absf(site.y - SkyportIsland.LAND_Y) < 0.25 and SkyportIsland.contains_local(site.x, site.z):
			return SkyportIsland.road_clearance(SkyportIsland.plan(layout), Vector2(site.x, site.z)) < 0.0
	return false


## The car's last safe place (wheels down on dry land, upright, slow
## enough to be somewhere it meant to be): the tow's fallback.
func _sample_car_safe(vid: String, c: Car, dt: float) -> void:
	_dry_t -= dt
	if _dry_t > 0.0:
		return
	_dry_t = 0.5
	if c.in_water or c.airtime > 0.0 or c.global_basis.y.y < 0.85:
		return
	var p := c.global_position
	if layout.is_water(p) and p.y < Car.WATER_Y + 1.5:
		return
	if safe.is_safe(p, [c.get_rid()]):
		_car_safe[vid] = c.global_transform
		safe.settled(vid)


var _was_wet := false
var _wade_snd_t := 0.0


## On foot the sea has a floor (the cars' water collision) but every quay is
## too tall to step up: someone who walks off the edge would wade forever.
## Remember the last dry ground and put them back on it, with realistic splash
## & wading wake effects on entry and movement.
func _check_wading(dt: float) -> void:
	var p := player.global_position
	var wet := p.y < Car.WATER_Y + 1.2 and layout.is_water(p)
	if not wet:
		_was_wet = false
		_wet_t = 0.0
		_dry_t -= dt
		# (Sampled, and only where the ground really is dry and solid: a
		# remembered "dry" spot in the sea is how the old loop began.)
		if _dry_t <= 0.0 and player.is_on_floor() and not player.stunned and not player.indoors:
			_dry_t = 0.3
			if safe.is_safe(p + Vector3.DOWN * 0.9, [player.get_rid()]):
				_dry_pos = p
				player.last_safe_position = p + Vector3.UP * 0.2
				safe.settled("hero")
		return
	if not _was_wet:
		_was_wet = true
		var spd := maxf(player.velocity.length(), maxf(-player.velocity.y, 0.0) * 1.35)
		var is_jump := spd >= 4.5
		var obj_sc := clampf(0.45 + spd * 0.035, 0.52, 0.95) if is_jump else 0.34
		if vfx:
			vfx.splash(Vector3(p.x, Car.WATER_Y + 0.05, p.z), maxf(spd, 2.8), obj_sc)
		if audio:
			var db := clampf(lerpf(-5.0, 1.0, spd / 14.0), -5.0, 1.0) if is_jump else -9.0
			var pitch := clampf(lerpf(1.12, 0.86, spd / 14.0), 0.86, 1.12) if is_jump else 1.24
			audio.play("splash", db, pitch)
	else:
		if vfx:
			vfx.water_disturb(p, player.velocity, 0.38, dt)
		_wade_snd_t -= dt
		if _wade_snd_t <= 0.0 and Vector2(player.velocity.x, player.velocity.z).length() > 0.8:
			_wade_snd_t = 0.46
			if audio:
				audio.play("splash", -13.0, 1.32)
	_wet_t += dt
	if _wet_t < 1.5:
		return
	_wet_t = 0.0
	var f := safe.find(p, HERO_BOX, {"kind": "foot", "key": "hero", "exclude": [player.get_rid()],
		"fallbacks": [_dry_pos, player.last_safe_position, _start_point()]})
	var back: Vector3 = (f["pos"] as Vector3) + Vector3.UP * 0.6 if f["ok"] else _start_point()
	player.respawn(back)
	player.last_safe_position = back
	_dry_pos = back
	if f["ok"] and not is_nan(float(f["yaw"])):
		camera.face(float(f["yaw"]))
	ui.toast("Back on dry land", "warn")


## Where a brand-new game starts you (outside the first shop): the last resort.
func _start_point() -> Vector3:
	var s := starter_unit()
	return Premises.door_point(s) + Premises.outward(s) * 3.0 + Vector3.UP * 0.6


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
	# Onto the nearest road (bridges included) or dry ground with room for
	# the car, never the same spot it sank at (that was the old loop: the
	# tow put it down in the sea and it was towed again every 2 s).
	var p := c.global_position
	var vid := ""
	for k in cars:
		if cars[k] == c:
			vid = k
	var fb: Array = []
	if _car_safe.has(vid):
		fb.append((_car_safe[vid] as Transform3D).origin)
	# The water surface is the level to search from (a car that sank off a
	# deck comes back to the shore road, not up onto the deck it fell from).
	var from := Vector3(p.x, maxf(p.y, Car.WATER_Y + 0.5), p.z)
	var f := safe.road_spot(from, c.spec["size"], {"key": vid, "exclude": [c.get_rid()], "fallbacks": fb, "min_d": 0.0})
	var xf: Transform3D
	if f["ok"]:
		xf = f["xf"]
		xf.origin += xf.basis.y * 0.6
	elif _car_safe.has(vid):
		xf = _car_safe[vid]
		xf.origin += Vector3.UP * 0.6
	else:
		var sp := _start_point()
		xf = Transform3D(Basis.IDENTITY, _kerb_point(sp) + Vector3.UP * 0.6)
	c.place(xf)
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
	if _pending_vehicle_deliveries.has(vid):
		out["why"] = "Delivery in progress"
		return out
	if driving != "":
		out["why"] = "Get out of the car first"
		return out
	if player.indoors:
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
	# A road on the level you're standing on (a bridge deck, a street under
	# it, a ramp, a tunnel), kerb side first, checked for solid ground and
	# room – never the street under the bridge you're on, never the sea.
	var spot_r := safe.road_spot(me + Vector3.DOWN * 0.9, c.spec["size"], {"exclude": [c.get_rid(), player.get_rid()], "min_d": 3.5})
	if not spot_r["ok"]:
		out["why"] = "No clear road here – walk to a street"
		return out
	out["at"] = spot_r["xf"]
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
	reset_all_elevators()
	if garage and garage.inside and driving == "":
		garage.leave_on_foot()
		return ""
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
	var dc_u: Car = cars.get(driving) if driving != "" else null
	var here := dc_u.global_position if dc_u and is_instance_valid(dc_u) else player.global_position
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
		var rs := safe.road_spot(here, c.spec["size"], {"exclude": [c.get_rid()], "min_d": 0.0, "key": driving})
		if rs["ok"]:
			var rx: Transform3D = rs["xf"]
			c.place(Transform3D(rx.basis, rx.origin + rx.basis.y * 0.4))
		else:
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
	var c: Car = cars[vid]
	var xf: Transform3D = q["at"]
	var fee := float(q["fee"])
	_pending_vehicle_deliveries[vid] = true
	get_tree().create_timer(2.5, false).timeout.connect(func():
		_pending_vehicle_deliveries.erase(vid)
		if not is_instance_valid(c) or cars.get(vid) != c or driving == vid:
			return
		if not empire.pay(fee, "vehicle", "Vehicle delivered to you"):
			ui.toast("Delivery cancelled · not enough money", "warn")
			return
		c.linear_velocity = Vector3.ZERO
		c.angular_velocity = Vector3.ZERO
		c.place(Transform3D(xf.basis, xf.origin + xf.basis.y * 0.35))
		var v := empire.vehicle(vid)
		v["pos"] = [xf.origin.x, xf.origin.y, xf.origin.z]
		v["yaw"] = xf.basis.get_euler().y
		ui.toast("Your vehicle is here", "good")
		Sfx.play("chime", -6.0))
	return ""


func buy_vehicle(model: String) -> String:
	# Delivered to the kerb of the road beside you, on your level (spawn
	# reliability pass 2026-11-25: it used to go 6 m ahead of the camera at
	# the terrain height – under the bridge you stood on, inside a shop,
	# in the dock).
	var p := player.global_position + Vector3.DOWN * 0.9
	var yaw := camera.view_yaw()
	var spot_p := _kerb_point(p + Vector3(sin(yaw), 0, cos(yaw)) * 6.0)
	var v := empire.buy_vehicle(model, spot_p, yaw + PI * 0.5)
	if v.is_empty():
		return "Not enough money"
	_spawn_car(v, p)
	Settings.haptic(28, 0.36)
	return ""


# ------------------------------------------------------- damage + repairs
func _store_damage(v: Dictionary, c: Car) -> void:
	v["damage"] = c.damage_state()
	if c.visual:
		v["dent_state"] = c.visual.visual_state()


## What's wrong with an owned car, in words (garage card, quote screen).
func damage_report(c: Car) -> Array[String]:
	var out: Array[String] = []
	if c == null:
		return out
	var g: Dictionary = c.glass
	if float(g["front"]) >= 1.0:
		out.append("Windscreen smashed")
	elif float(g["front"]) > 0.05:
		out.append("Windscreen cracked")
	var panes := 0
	for k in ["rear", "left", "right"]:
		if float(g[k]) >= 1.0:
			panes += 1
	if panes > 0:
		out.append("%d window%s broken" % [panes, "s" if panes > 1 else ""])
	var lamps := 0
	for k in c.lamps_ok:
		if not c.lamps_ok[k]:
			lamps += 1
	if lamps > 0:
		out.append("%d lamp%s smashed" % [lamps, "s" if lamps > 1 else ""])
	var lost := c.parts_lost()
	if lost > 0:
		out.append("%d panel%s missing" % [lost, "s" if lost > 1 else ""])
	var names := ["front-left", "front-right", "rear-left", "rear-right"]
	for i in 4:
		if c.tyre[i] > 0.5:
			out.append("%s tyre flat" % names[i].capitalize())
		if c.susp[i] > 0.25:
			out.append("%s suspension bent" % names[i].capitalize())
	if c.engine < 0.75:
		out.append("Engine damaged (%d%%)" % int(c.engine * 100.0))
	if c.coolant < 1.0:
		out.append("Radiator leaking" if c.coolant > 0.0 else "Out of coolant")
	if c.roof > 0.1:
		out.append("Roof crushed")
	var sc := 0.0
	for k in c.scuff:
		sc = maxf(sc, float(c.scuff[k]))
	if sc > 0.15 and out.size() < 6:
		out.append("Paint scratched")
	return out


var _garages: Array = []


## The nearest Motor Works (garage) door and its distance: [unit, metres].
func nearest_garage(p: Vector3) -> Array:
	if _garages.is_empty():
		for u: Dictionary in world.street_units + (skyport.street_units if skyport else []):
			if String(u.get("street_use", "")) == "garage":
				_garages.append(u)
	var best := {}
	var bd := INF
	for u: Dictionary in _garages:
		var d := p.distance_to(Premises.door_point(u))
		if d < bd:
			bd = d
			best = u
	return [best, bd]


## A garage's price for a car: {ok, why, mech, full, tow, at_garage, garage}.
## Mechanical = engine, cooling, tyres, suspension, alignment; restoration
## = that plus bodywork, glass, lamps and paint. Prices follow what the car
## is worth and how badly it's hurt; away from a Motor Works a tow is added.
func repair_quote(vid: String) -> Dictionary:
	var out := {"ok": false, "why": "", "mech": 0.0, "full": 0.0, "tow": 0.0, "at_garage": false, "garage": {}}
	var c: Car = cars.get(vid)
	if c == null:
		out["why"] = "Not a road vehicle"
		return out
	# (Priced as a car is worth to fix – the free starter hatch still costs
	# real money to repair.)
	var value := maxf(float(EmpireData.vehicle_model(String(empire.vehicle(vid).get("model", ""))).get("price", 12000.0)), 9000.0)
	var md := c.mech_damage()
	var bd := c.body_damage()
	var mech := 0.0
	if md > 0.01:
		mech = 60.0 + value * 0.05 * md
		for i in 4:
			mech += 95.0 * c.tyre[i] + 160.0 * c.susp[i]
		if c.coolant < 1.0:
			mech += 140.0
	var body := 0.0
	var sc := 0.0
	for k in c.scuff:
		sc = maxf(sc, float(c.scuff[k]))
	if bd > 0.01 or sc > 0.02:
		body = 120.0 + value * 0.16 * bd + value * 0.02 * sc
		for k in c.glass:
			body += 210.0 * minf(1.0, float(c.glass[k])) * (1.6 if k == "front" else 1.0)
		for k in c.lamps_ok:
			if not c.lamps_ok[k]:
				body += 85.0 + value * 0.002
		body += value * 0.03 * float(c.parts_lost())
	out["mech"] = roundf(minf(mech, value * 0.35))
	out["full"] = roundf(minf(mech + body, value * 0.6))
	var g := nearest_garage(c.global_position)
	out["garage"] = g[0]
	out["at_garage"] = float(g[1]) < 45.0 and player.global_position.distance_to(c.global_position) < 30.0
	if not out["at_garage"]:
		out["tow"] = roundf(clampf(45.0 + float(g[1]) * 0.05, 45.0, 220.0)) if not (g[0] as Dictionary).is_empty() else 120.0
	if float(out["full"]) <= 0.0:
		out["why"] = "Nothing to fix"
		return out
	if driving == vid and absf(c.speed) > 1.0:
		out["why"] = "Stop the car first"
		return out
	out["ok"] = true
	return out


## mode "mech" | "full". "" or why not.
func repair_vehicle(vid: String, mode: String) -> String:
	var q := repair_quote(vid)
	if not q["ok"]:
		return String(q["why"])
	var c: Car = cars[vid]
	var cost := float(q["mech"] if mode == "mech" else q["full"]) + float(q["tow"])
	if mode == "mech" and float(q["mech"]) <= 0.0:
		return "Nothing mechanical to fix"
	if not empire.pay(cost, "vehicle", ("Mechanical repair" if mode == "mech" else "Full restoration") + (" + tow" if float(q["tow"]) > 0.0 else "")):
		return "Not enough money (%s)" % EmpireData.money(cost)
	if mode == "mech":
		c.reset_mechanical()
	else:
		c.repair_full()
		var v := empire.vehicle(vid)
		v["condition"] = 1.0
	if c.visual:
		c.visual.refresh_damage()
	_store_damage(empire.vehicle(vid), c)
	Sfx.play("chime", -6.0)
	save_game()
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
	Settings.haptic(28, 0.36)
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
	Settings.haptic(28, 0.36)
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
	Settings.haptic(28, 0.36)
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


var last_wholesale_loaded := 0
var last_wholesale_veh := ""


## Finds the player's closest parked road vehicle near the warehouse (or largest
## road vehicle with free cargo space) for automatic loading on checkout.
func wholesale_vehicle(u: Dictionary) -> Dictionary:
	var door := Premises.door_point(u)
	var best := {}
	var best_d := INF
	for v in empire.vehicles:
		if SkyportPlay.vclass(String(v["model"])) != "car":
			continue
		var st: Stock = v["cargo"]
		if st.case_capacity <= 0:
			continue
		var c: Car = cars.get(v["id"])
		var d := c.global_position.distance_to(door) if (c and is_instance_valid(c)) else 9999.0
		if best.is_empty() or d < best_d:
			best = v
			best_d = d
	return best


func buy_wholesale(u: Dictionary, order: Dictionary, sack_truck := false) -> String:
	last_wholesale_loaded = 0
	last_wholesale_veh = ""
	var err := empire.buy_wholesale(u["id"], order)
	if err == "":
		# Auto-load purchased stock directly into the player's vehicle parked outside,
		# respecting its cargo capacity (eliminates repetitive manual pallet loading).
		var veh := wholesale_vehicle(u)
		if not veh.is_empty():
			var pal := _pallet(u["id"])
			var cargo: Stock = veh["cargo"]
			var before := cargo.cases_used()
			for pid in pal.units.keys():
				var qty := pal.qty(pid)
				if qty > 0:
					Stock.transfer(pal, cargo, pid, qty)
			last_wholesale_loaded = cargo.cases_used() - before
			last_wholesale_veh = String(EmpireData.vehicle_model(veh["model"]).get("name", "vehicle"))
		if interiors.has(u["id"]):
			interiors[u["id"]].refresh_goods(_pallet(u["id"]))
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
	var t0 := Time.get_ticks_msec()
	empire.fast_forward(mins)
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


## Build furnished ground lobbies, shafts and working 3D elevators for every apartment.
func _build_elevators() -> void:
	var old := get_node_or_null("ApartmentElevators")
	if old:
		remove_child(old)
		old.queue_free()
	elevators.clear()
	var root := Node3D.new()
	root.name = "ApartmentElevators"
	add_child(root)
	for home in homes():
		var h: Dictionary = home["h"]
		if not h.has("core"):
			continue
		# The pavement outside the home's street door (the lobby floor may sit
		# a step or two above it).
		var core: Dictionary = h["core"]
		var outside := Apartments.face_point(h, core["a_c"], float(core["o_face0"]) + 1.4, core["base"])
		var gy: float
		if String(home.get("district", "")) == "east:skyport":
			gy = SkyportIsland.LAND_Y
		else:
			gy = _kerb_point(outside).y - 0.35
		var el := ApartmentElevator.build(home, gy)
		root.add_child(el)
		elevators[String(home["id"])] = el


func _tick_elevators(dt: float) -> void:
	if elevators.is_empty():
		return
	var riding := false
	for hid: String in elevators:
		var el: ApartmentElevator = elevators[hid]
		var owns := empire.owns_property(hid)
		if owns:
			# (a plain loop: this ran a filter lambda per lift per frame)
			for x: Dictionary in empire.properties:
				if x["id"] == hid:
					owns = not x.get("let", false)
					break
		el.tick(dt, player, owns)
		if el.is_riding():
			riding = true
			_riding_el = el
	if garage and garage.inside and garage.lift and garage.lift.is_riding():
		riding = true
		_riding_el = garage.lift
	if riding and _riding_el and is_instance_valid(_riding_el) and _riding_el.ride_rumble > 0.01:
		camera.vibrate(0.0045 * _riding_el.ride_rumble)
	if riding and not _elev_riding:
		_elev_riding = true
		player.scripted = true
		_face_lift_doors(_riding_el, false)
	elif not riding and _elev_riding:
		_elev_riding = false
		player.scripted = false
		_face_lift_doors(_riding_el, false)   # (doors open: smooth turn to face out)
		_riding_el = null
	elif not riding and player.scripted and not vehicle_access.active() and driving == "" and not camera.cine.is_valid():
		# Recovery guard: never leave controls permanently disabled after an interrupted transition.
		player.scripted = false


var _riding_el: ApartmentElevator


## Safely reset all elevator state machines so an interrupted transition never
## leaves the player trapped or controls disabled.
func reset_all_elevators() -> void:
	for el: ApartmentElevator in elevators.values():
		if is_instance_valid(el):
			el.reset_safe()
	if garage and garage.lift and is_instance_valid(garage.lift):
		garage.lift.reset_safe()
	_elev_riding = false
	_riding_el = null
	if player and driving == "" and not vehicle_access.active():
		player.scripted = false


## Character and camera face out through the lift's doors (riding, arriving).
func _face_lift_doors(el: ApartmentElevator, instant := false) -> void:
	if el == null or not is_instance_valid(el):
		return
	var out := el.global_basis.z
	out.y = 0.0
	out = out.normalized()
	rig.set_facing(out)
	var target_yaw := atan2(-out.x, -out.z)
	if instant:
		camera.face(target_yaw)
	else:
		camera.ease_face(target_yaw)


## Inside the cabin: the floor buttons (2026-11-26) – up to the apartment,
## the lobby, or down to the Vehicle Collection.
func lift_floors(hid: String) -> Array:
	var el: ApartmentElevator = elevators.get(hid)
	if el == null:
		return []
	var home := home_by_id(hid)
	return [["▲  %s · %s" % [String(home.get("name", "Apartment")), el.top_floor_label], "top", el.at_top],
		["●  Lobby · G", "lobby", not el.at_top],
		["▼  Vehicle Collection · %s" % VehicleGarage.BAY_LEVEL, "garage", false]]


func choose_floor(hid: String, which: String) -> void:
	var el: ApartmentElevator = elevators.get(hid)
	if el == null:
		return
	match which:
		"top":
			el.ride_to(true)
		"lobby":
			el.ride_to(false)
		"garage":
			# (2026-11-27) A real ride, not a cut: the doors close, the cabin
			# rides down to the lobby if it's up, then hums on past B1 to the
			# Vehicle Collection's level while it shudders; doors shut, you
			# are carried into the garage lift's cabin (same plan, same
			# finish), whose doors then open on the garage.
			_face_lift_doors(el)
			el.trip(["B1", VehicleGarage.BAY_LEVEL], func():
				var from := el.cabin_xf()
				garage.enter(hid, false)
				garage.lift.arrive_sealed(false, VehicleGarage.BAY_LEVEL)
				_carry_rider(from, garage.lift)
				el.settle_closed())


## From the garage's lift back up (the floor panel in its cabin): the same
## ride in reverse – B1, G – into the apartment lift's cabin at the lobby,
## which opens there or rides on up to the home.
func arrive_from_garage(hid: String, to_top: bool) -> void:
	var el: ApartmentElevator = elevators.get(hid)
	if el == null or garage.lift == null:
		return
	var gl := garage.lift
	_face_lift_doors(gl)
	gl.trip(["B1", "G"], func():
		var from := gl.cabin_xf()
		garage.leave_quietly()
		el.arrive_sealed(false, "G", to_top)
		_carry_rider(from, el))


## Moves you from one lift cabin to another at the same place inside it
## (doors shut both ends: nothing to see). The camera keeps its framing.
func _carry_rider(from: Transform3D, to_el: ApartmentElevator) -> void:
	var to := to_el.cabin_xf()
	var rel := from.affine_inverse() * player.global_position
	var p := to * rel
	vehicle_access.interrupt()
	player.respawn(p)
	player.last_safe_position = p
	_face_lift_doors(to_el, true)
	player.scripted = true
	_riding_el = to_el


## Places you in a lift cabin (`rel` in its frame): the garage's way in
## without the ride (tests, "Stuck?").
func _teleport_local(xf: Transform3D, rel: Transform3D) -> void:
	var p := xf * rel.origin
	var f := (xf.basis * rel.basis).z
	_teleport(p, atan2(-f.x, -f.z))


## Street door of a home's tower (below its window, on the pavement).
func home_lift(home: Dictionary) -> Vector3:
	var el: ApartmentElevator = elevators.get(String(home.get("id", "")))
	if el:
		return el.street_door_world()
	var h: Dictionary = home["h"]
	if h.has("lift"):
		return h["lift"]
	var c := Apartments.window_center(h) + Apartments.outward(h) * 1.6
	return Vector3(c.x, layout.ground_y(c.x, c.z), c.z)


func _home_spots(p: Vector3, best: Dictionary, best_d: float) -> Array:
	for home in homes():
		var hid := String(home["id"])
		var owns := empire.owns_property(hid)
		var is_let := false
		if owns:
			var q := empire.properties.filter(func(x): return x["id"] == hid)
			if not q.is_empty() and q[0].get("let", false):
				is_let = true
		var el: ApartmentElevator = elevators.get(hid)
		if el:
			# Inside the 3D elevator cabin: functional floor selector button!
			if owns and not is_let and el.is_inside_cabin(p):
				if el.state in ["idle_g", "idle_top"]:
					return [{"kind": "elev_select", "home": hid, "to_top": not el.at_top, "world": el.cabin_panel_world()}, 0.1]
				return [{}, 0.1]
			# Ground lobby entrance & call button
			var ent := el.street_door_world()
			var d_ent := Vector2(p.x, p.z).distance_to(Vector2(ent.x, ent.z))
			if d_ent < 2.4 and absf(p.y - 0.9 - ent.y) < 2.2 and d_ent < best_d:
				if not owns or is_let or args.has("autoplay"):
					best = {"kind": "home_lift", "home": hid, "world": ent}
					best_d = d_ent
			var gcall := el.ground_call_world()
			var d_gc := p.distance_to(gcall + Vector3.UP * 1.0)
			if d_gc < 2.0 and d_gc < best_d:
				if not owns or is_let:
					best = {"kind": "home_lift", "home": hid, "world": gcall}
					best_d = d_gc
				elif el.at_top and el.state == "idle_top":
					best = {"kind": "elev_call_g", "home": hid, "world": gcall}
					best_d = d_gc
			# Upper private landing call button (when cabin is at ground floor)
			if owns and not is_let:
				var ucall := el.upper_call_world()
				var d_uc := p.distance_to(ucall + Vector3.UP * 1.0)
				if d_uc < 2.0 and not el.at_top and el.state == "idle_g" and d_uc < best_d:
					best = {"kind": "elev_call_top", "home": hid, "world": ucall}
					best_d = d_uc
		else:
			var lift := home_lift(home)
			var d := Vector2(p.x, p.z).distance_to(Vector2(lift.x, lift.z))
			if d < 2.2 and absf(p.y - 0.9 - lift.y) < 2.0 and d < best_d:
				best = {"kind": "home_lift", "home": hid, "world": lift}
				best_d = d
		if owns:
			var h: Dictionary = home["h"]
			for sp in HomeInteriors.spots.get(String(h["id"]), []):
				var sk := String(sp["kind"])
				if sk in ["bed", "wardrobe", "trophies", "jobs"]:
					var d3 := p.distance_to(sp["pos"] + Vector3.UP * 0.95)
					if d3 < 1.8 and d3 < best_d:
						best = {"kind": "home_" + sk, "home": hid, "world": sp["pos"]}
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
func save_game(background := false) -> void:
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
			_store_damage(v, c)
	var yaw := view_yaw()
	var d := {"empire": empire.to_dict(), "player": [player.global_position.x, player.global_position.y,
		player.global_position.z, yaw], "driving": driving, "saved_at": Time.get_datetime_string_from_system()}
	if driving != "":
		var c2: Car = cars.get(driving)
		if c2 and is_instance_valid(c2):
			var is_test_car := bool(empire.vehicle(driving).get("test", false))
			if is_test_car:
				d["driving"] = ""
				if skyport_play and skyport_play._test_return != Vector3.INF:
					var ret: Vector3 = skyport_play._test_return + Vector3.UP + SkyportIsland.wd(Vector3(0, 0, 3.0))
					d["player"] = [ret.x, ret.y, ret.z, yaw]
				else:
					var side := c2.global_transform * Vector3(-c2.spec["size"].x * 0.5 - 0.9, 0.9, 0.0)
					d["player"] = [side.x, side.y, side.z, yaw]
			else:
				var side := c2.global_transform * Vector3(-c2.spec["size"].x * 0.5 - 0.9, 0.9, 0.0)
				if safe:
					var sf := safe.find(side, HERO_BOX, {"kind": "foot", "max_r": 12.0, "exclude": [c2.get_rid()]})
					if sf["ok"]:
						side = (sf["pos"] as Vector3) + Vector3.UP * 0.9
				d["player"] = [side.x, side.y, side.z, yaw]
		else:
			d["driving"] = ""
	elif skyport_play and skyport_play.piloting != "":
		var cr2: Craft = skyport_play.crafts.get(skyport_play.piloting)
		var is_test_craft := bool(empire.vehicle(skyport_play.piloting).get("test", false))
		if is_test_craft:
			if skyport_play._test_return != Vector3.INF:
				var ret2: Vector3 = skyport_play._test_return + Vector3.UP + SkyportIsland.wd(Vector3(0, 0, 3.0))
				d["player"] = [ret2.x, ret2.y, ret2.z, yaw]
			else:
				var sp := _start_point()
				d["player"] = [sp.x, sp.y, sp.z, yaw]
		elif cr2 and is_instance_valid(cr2):
			var side2 := skyport_play.saved_pilot_point(cr2)
			d["player"] = [side2.x, side2.y + 1.0, side2.z, yaw]
	if background:
		# Autosave: the file work runs off the main thread (SafeSave).
		SafeSave.write_async(save_path, d, _on_saved)
		return
	_on_saved(SafeSave.write(save_path, d))


func _on_saved(err: String) -> void:
	if err != "":
		push_warning("WORLDSTATE: save failed – " + err)
		if ui and not _save_warned:
			_save_warned = true   # (once a session: autosave would repeat it)
			ui.toast("Couldn't save your game (%s). Free some space; your last save is kept." % err, "bad")
	else:
		_save_warned = false


var _save_warned := false


## Schema check before a save is trusted (SafeSave.read): the economy's core
## fields with the right types; anything else falls back to defaults/migrate.
static func save_problem(d: Dictionary) -> String:
	if not (d.get("empire") is Dictionary):
		return "no economy"
	var e: Dictionary = d["empire"]
	var why := SafeSave.has_types(e, {"day": TYPE_FLOAT, "minute": TYPE_FLOAT, "personal_cash": TYPE_FLOAT,
		"company_cash": TYPE_FLOAT, "businesses": TYPE_ARRAY, "vehicles": TYPE_ARRAY, "flags": TYPE_DICTIONARY,
		"properties": TYPE_ARRAY, "loans": TYPE_ARRAY}, ["day"])
	if why != "":
		return why
	for b in e.get("businesses", []):
		if not (b is Dictionary):
			return "a business record is broken"
	for v in e.get("vehicles", []):
		if not (v is Dictionary) or not (v as Dictionary).has("id"):
			return "a vehicle record is broken"
	if d.has("player") and not (d["player"] is Array):
		return "player position is broken"
	if float(e["day"]) < 1.0:
		return "day out of range"
	return ""


func load_game() -> bool:
	StartupTrace.mark("save read started")
	var d = SafeSave.read(save_path, save_problem)
	StartupTrace.mark("save read complete (source=%s)" % SafeSave.last_source)
	if d == null:
		if SafeSave.last_error != "":
			# Unreadable save and backup: keep the files for recovery (the next
			# autosave writes a fresh one; the broken one is set aside first).
			for p in [save_path, save_path + ".bak"]:
				if FileAccess.file_exists(p):
					DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(p + ".broken"))
		new_game()
		if SafeSave.last_error != "" and ui:
			ui.toast.call_deferred("Your save couldn't be read, so a new game started. The old file is kept.", "bad")
		return false
	if SafeSave.last_source == "backup" and ui:
		ui.toast.call_deferred("Your last save was damaged – loaded the one before it.", "bad")
	_tr("load_game: read save")
	_reset_vehicle_state()
	ExploreUI.reset_cache()
	empire = Empire.from_dict(d["empire"])
	empire.market = _market()
	if not empire.flags.has("start_unit"):
		empire.flags["start_unit"] = starter_unit()["id"]
	CityLife.ensure_firms(empire)
	Ventures._grant_homes(empire)   # (homes that come with Skyport buildings)
	_migrate_penthouse_estate()
	_tr("load_game: restore empire")
	_connect_empire()
	_tr("load_game: connect empire")
	_rival_sig = "?"
	_spawn_cars()
	_tr("load_game: spawn cars")
	_obj_sig = ""
	gps.restore()
	var pp: Array = d.get("player", [])
	if pp.size() >= 4 and int((d.get("empire", {}) as Dictionary).get("version", 1)) < 6:
		# (Saved on Skyport Island before it moved: Empire.migrate v6.)
		var q := SkyportIsland.migrate_point(Vector3(float(pp[0]), float(pp[1]), float(pp[2])))
		pp = [q.x, q.y, q.z, float(pp[3])]
	if pp.size() >= 4 and float(pp[1]) < -100.0:
		pp = []   # (saved in the Vehicle Collection: start up top)
	var hs := _home_spawn() if not args.has("goto") else {}
	if not hs.is_empty():
		# The app starts you in the apartment you were last in.
		_teleport(hs["pos"], float(hs["yaw"]))
	elif pp.size() >= 4:
		_teleport(Vector3(pp[0], pp[1], pp[2]) + Vector3.UP * 0.2, float(pp[3]))
	else:
		var s := starter_unit()
		_teleport(Premises.door_point(s) + Premises.outward(s) * 3.0 + Vector3.UP, 0.0)
	_tr("load_game: teleport")
	for id in interiors.keys():
		rebuild_interior(id)
	_tr("load_game: rebuild %d interiors" % interiors.size())
	StartupTrace.mark("save restored, player positioned and interiors loaded")
	return true


func _exit_tree() -> void:
	SafeSave.settle()   # (an autosave still writing finishes before teardown)
	if _cloud_sync.is_valid() and get_tree() and get_tree().process_frame.is_connected(_cloud_sync):
		get_tree().process_frame.disconnect(_cloud_sync)
	_cloud_sync = Callable()
	CarVisual.trim_caches()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if state == "play":
			save_game()
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED,
			NOTIFICATION_APPLICATION_FOCUS_OUT] and ui and ui.touch:
		ui.touch.reset_contacts()


# ------------------------------------------------------- captures/tests
## Captures of the commercial empire: a branded company a few weeks in –
## three shops (one a major retailer), a warehouse and van, a contract,
## the club, car hire and the hotel with a spa.
func _demo_commerce(b: Business) -> void:
	var e := empire
	e.personal_cash = 6000000.0
	e.transfer_to_company(4000000.0)
	e.set_brand(ShopStyle.default_house("Crown Goods"))
	for role in ["cashier", "stocker", "manager"]:
		var cs := e.candidates.filter(func(x): return x["role"] == role)
		if not cs.is_empty():
			e.hire(b, cs[0])
	var n := 0
	for u2 in units:
		if n >= 2:
			break
		if u2["kind"] == "shop" and u2["island"] == "east" and e.business_at(u2["id"]) == null and not CityLife.is_taken(e, u2["id"]):
			e.rent_premises(u2, "cafe" if n == 0 else "clothing")
			n += 1
	Growth.apply_level(b, 3)
	for x: Business in e.businesses:
		for i in 6:
			x.history.append({"day": i, "revenue": 900.0 + 180.0 * i, "profit": 140.0 + 40.0 * i})
	for i in 14:
		e.day_reports.append({"day": i + 1, "revenue": 2200.0 + 160.0 * i, "profit": -300.0 + 120.0 * i + (240.0 if i % 3 == 0 else 0.0),
			"company": e.company_cash, "personal": e.personal_cash, "net_worth": e.net_worth(), "assets": e.asset_value(), "debt": 0.0})
	SupplyChain.buy_site(e, "west_depot")
	SupplyChain.stock_up(e, SupplyChain.suggested_order(e))
	var v := e.buy_vehicle("van", player.global_position + Vector3(8, 0, 0), 0.0)
	SupplyChain.toggle_fleet(e, String(v["id"]))
	SupplyChain.end_day(e)
	SupplyChain.end_day(e)
	Trades.buy_club(e, "vault")
	Trades.buy_rental(e)
	for m in ["saloon", "scout"]:
		Trades.toggle_hire(e, String(e.buy_vehicle(m, player.global_position + Vector3(-8, 0, 0), 0.0)["id"]))
	Ventures.buy_estate(e, "skyport_hotel")
	Trades.build_facility(e, "skyport_hotel", "spa")
	e.stats["profitable_days"] = 4
	Progression.check(e)
	Growth.refresh(e)
	Trades.refresh(e)


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
	if kind == "commerce":
		_demo_commerce(b)
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
		# Captures: cars drawn per traffic LOD (moving "Cars_*", parked/chunk
		# "Traffic_*"): instances in each band's MultiMeshes.
		var tc := {}
		for n in find_children("*", "MultiMeshInstance3D", true, false):
			var nm := String(n.name)
			if nm.begins_with("Cars_") or nm.begins_with("Traffic_"):
				var key := nm.split("_")[0] + ("_mid" if nm.ends_with("_mid") else ("_far" if nm.ends_with("_far") else "_near"))
				tc[key] = int(tc.get(key, 0)) + (n as MultiMeshInstance3D).multimesh.instance_count
		print("TRAFFIC_COUNTS ", JSON.stringify(tc))
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


## Dev (tools/photos/shoot.sh): every purchasable place and its estate-agent
## camera views, as JSON lines {id, view, from, to} (world m; y absolute).
## Shops: square-ish across the street at a little above eye height, and a
## high three-quarter "location" view. Homes: the tower from outside, and
## the room from inside towards its windows. Skyport estates: two aerial
## three-quarter views.
func _write_photo_targets(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	var put := func(id: String, view: String, from: Vector3, to: Vector3) -> void:
		f.store_line(JSON.stringify({"id": id, "view": view, "from": [from.x, from.y, from.z], "to": [to.x, to.y, to.z]}))
	for u in units:
		if not String(u["kind"]) in ["shop", "hq", "office"]:
			continue
		var d := Premises.door_point(u)
		var o := Premises.outward(u)
		var al := Premises.along_dir(u)
		put.call(String(u["id"]), "front", d + o * 15.0 + al * 4.5 + Vector3.UP * 3.0, d + Vector3.UP * 4.2 - al * 0.8)
		put.call(String(u["id"]), "area", d + o * 42.0 - al * 22.0 + Vector3.UP * 30.0, d + Vector3.UP * 6.0)
	for hm in homes():
		var h: Dictionary = hm["h"]
		var wc := Apartments.window_center(h)
		var o2 := Apartments.outward(h)
		var side := o2.cross(Vector3.UP).normalized()
		put.call(String(hm["id"]), "front", wc + o2 * 70.0 + side * 25.0 - Vector3.UP * 12.0, wc + Vector3.UP * 6.0)
		var sp := Apartments.spawn_point(h)
		put.call(String(hm["id"]), "inside", sp + Vector3.UP * 1.5 - o2 * 1.0, wc + o2 * 4.0 - Vector3.UP * 1.0)
	for ed in Ventures.ESTATES:
		var at := Ventures.estate_at(ed)
		put.call(String(ed["id"]), "front", at + Vector3(-70, 40, 60), at + Vector3.UP * 12.0)
		put.call(String(ed["id"]), "area", at + Vector3(80, 70, -60), at + Vector3.UP * 8.0)
	f.close()
	print("PHOTO_TARGETS ", path)
	get_tree().quit()
