class_name SkyportPlay
extends Node
## City Empire's side of Skyport Island and everything that moves off the
## road: owned helicopters, planes and boats (Craft), the physical showrooms
## (car dealers with display cars you walk up to, aviation sales in the
## first hangar, boat sales at the marina), test drives / flights, and the
## island's named sites (clothing stores, cargo terminal).
##
## Ownership is Empire.vehicles as for cars ({id, model, pos, yaw, ...});
## the vehicle's class (vehicles.json "class": car / heli / plane / boat)
## decides what spawns. A test drive is a vehicle record flagged "test": it
## is never saved and is removed when you get out (no duplicates, no cost).

const REACH := 3.5
const DISPLAY_RANGE := 220.0
## Dealer stock by site (vehicles.json models).
const STOCK := {
	"dealer_budget": ["used_kestrel", "saloon", "scout"],
	"dealer_commercial": ["van", "box", "goliath"],
	"dealer_luxury": ["brute", "warden", "vanta", "halcyon", "stiletto"],
	"aviation": ["wren", "kite", "regent", "skylark", "merlin", "aurora"],
	"marina": ["dart", "swift", "majesty"],
}

var game: EmpireGame
var crafts := {}            # vehicle id -> Craft
var piloting := ""
var cam: CraftCamera
var displays := {}          # "site/model" -> Car (frozen, on the forecourt)
var _disp_t := 0.0
var _test_return := Vector3.INF
var _km_acc := 0.0
var _last := Vector3.ZERO


func setup(g: EmpireGame) -> void:
	game = g
	process_physics_priority = -15   # (controls in before the craft move)
	cam = CraftCamera.new()
	cam.name = "CraftCamera"
	add_child(cam)


static func vclass(model: String) -> String:
	return String(EmpireData.vehicle_model(model).get("class", "car"))


static func craft_spec(model: String) -> Dictionary:
	var m := EmpireData.vehicle_model(model).duplicate(true)
	var sz: Array = m.get("size", [3, 2, 8])
	m["size"] = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
	m["paint"] = Color.from_string(String(m.get("paint", "#dddddd")), Color.WHITE)
	m["trim"] = Color.from_string(String(m.get("trim", "#222222")), Color.BLACK)
	return m


func site(id: String) -> Dictionary:
	return (game.skyport.wplan.get("sites", {}) as Dictionary).get(id, {}) if game.skyport else {}


# ---------------------------------------------------------------- crafts
func spawn_all() -> void:
	for k in crafts:
		if is_instance_valid(crafts[k]):
			crafts[k].queue_free()
	crafts.clear()
	for v in game.empire.vehicles:
		if vclass(String(v["model"])) != "car":
			_spawn(v)


func _spawn(v: Dictionary) -> Craft:
	var model := String(v["model"])
	var c := Craft.new()
	c.name = "Craft_" + String(v["id"])
	c.setup(vclass(model), model, craft_spec(model))
	c.water_check = game.layout.is_water
	c.berths = game.skyport.wplan.get("berths", []) if game.skyport else []
	game.add_child(c)
	var p := Vector3(float(v["pos"][0]), float(v["pos"][1]), float(v["pos"][2]))
	c.place(Transform3D(Basis(Vector3.UP, float(v.get("yaw", 0.0))), p))
	crafts[v["id"]] = c
	return c


## A free place for a new craft of this class: a helipad, a stand, a berth.
func free_slot(kind: String) -> Array:
	var P: Dictionary = game.skyport.wplan
	var opts: Array = []
	match kind:
		"heli":
			for hp: Vector3 in P["helipads"]:
				if hp.y < SkyportIsland.LAND_Y + 1.0:
					opts.append([hp, SkyportIsland.wyaw(PI)])
		"plane":
			opts = P["stands"]
		_:
			opts = P["berths"]
	for o in opts:
		var taken := false
		for k in crafts:
			if is_instance_valid(crafts[k]) and (crafts[k] as Craft).global_position.distance_to(o[0]) < 9.0:
				taken = true
		if not taken:
			return o
	var last: Array = opts[opts.size() - 1]
	return [(last[0] as Vector3) + SkyportIsland.wd(Vector3(0, 0, 30.0 * crafts.size())), last[1]]


func buy(model: String) -> String:
	var kind := vclass(model)
	var slot := free_slot(kind) if kind != "car" else []
	if kind == "car":
		return buy_car(model)
	var v := game.empire.buy_vehicle(model, slot[0], slot[1])
	if v.is_empty():
		return "Not enough money"
	_spawn(v)
	game.set_gps(slot[0], String(EmpireData.vehicle_model(model).get("name", model)), {"kind": "vehicle", "id": v["id"]})
	return ""


## A car bought at a showroom: waiting on the dealer's forecourt edge.
func buy_car(model: String, at_site := "") -> String:
	var s := site(at_site if at_site != "" else _nearest_dealer())
	var p: Vector3 = s.get("door", game.player.global_position) as Vector3 + SkyportIsland.wd(Vector3(-6.0, 0.0, -6.0))
	var v := game.empire.buy_vehicle(model, p + Vector3.UP * 0.3, 0.0)
	if v.is_empty():
		return "Not enough money"
	game._spawn_car(v)
	return ""


func _nearest_dealer() -> String:
	var best := "dealer_budget"
	var bd := INF
	for k in ["dealer_budget", "dealer_commercial", "dealer_luxury"]:
		var d := (site(k).get("door", Vector3.ZERO) as Vector3).distance_to(game.player.global_position)
		if d < bd:
			bd = d
			best = k
	return best


func enter(vid: String) -> void:
	var c: Craft = crafts.get(vid)
	if c == null:
		return
	piloting = vid
	game.player.input_enabled = false
	game.player.visible = false
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.collision_layer = 0
	# (Ease from the walking camera to the craft's: no cut.)
	var from := get_viewport().get_camera_3d().global_transform if get_viewport().get_camera_3d() else Transform3D()
	cam.set_target(c, from)
	cam.cam.make_current()
	game.world.set_viewer(cam)
	_last = c.global_position
	Sfx.play("click", -6.0)


## Out of the craft (only when it's down / stopped). Returns why not.
func exit() -> String:
	var c: Craft = crafts.get(piloting)
	if c == null:
		piloting = ""
		return ""
	if not c.can_exit():
		return {"heli": "Land first", "plane": "Stop on the ground first"}.get(c.kind, "Slow down first") as String
	var v := game.empire.vehicle(piloting)
	v["pos"] = [c.global_position.x, c.global_position.y, c.global_position.z]
	v["yaw"] = c.global_basis.get_euler().y
	var out := _step_off(c)
	var was := piloting
	piloting = ""
	game.player.process_mode = Node.PROCESS_MODE_INHERIT
	game.player.visible = true
	game.player.collision_layer = 1 << 2
	game.player.respawn(out + Vector3.UP * 0.9)
	game.player.input_enabled = true
	game.camera.face(c.global_basis.get_euler().y)
	game.camera.cam.make_current()
	game.world.set_viewer(game.camera)
	if v.get("test", false):
		end_test(was)
	return ""


## Where the pilot steps out: beside the cabin, or (boats) the nearest pier
## or quay.
func _step_off(c: Craft) -> Vector3:
	var side := c.global_transform * Vector3(-(c.spec["size"] as Vector3).x * 0.5 - 1.6, 0.0, 0.0)
	if c.kind != "boat":
		var g := c.ground_below(side + Vector3.UP * 3.0, 20.0)
		return Vector3(side.x, (g if not is_nan(g) else c.global_position.y), side.z)
	var best := Vector3.INF
	var bd := INF
	for pr: Array in game.skyport.wplan["piers"]:
		var a: Vector3 = pr[0]
		var b: Vector3 = pr[1]
		var q := Vector3(clampf(c.global_position.x, a.x, b.x), 0.7, clampf(c.global_position.z, a.z, b.z))
		var d := q.distance_to(c.global_position)
		if d < bd:
			bd = d
			best = q
	if bd < 25.0:
		return best
	# Anywhere else: the nearest dry ground within 60 m.
	for r: float in [6.0, 12.0, 20.0, 30.0, 45.0, 60.0]:
		for k in 16:
			var q2 := c.global_position + Vector3(cos(k * TAU / 16.0), 0.0, sin(k * TAU / 16.0)) * r
			if not game.layout.is_water(q2):
				return Vector3(q2.x, game.layout.ground_y(q2.x, q2.z), q2.z)
	return best if best != Vector3.INF else c.global_position + Vector3.UP * 2.0


func track(dt: float) -> void:
	var c: Craft = crafts.get(piloting)
	if c == null:
		return
	game.player.global_position = c.global_position + Vector3.UP * 1.5
	var p := c.global_position
	_km_acc += p.distance_to(_last) / 1000.0
	_last = p
	if _km_acc > 0.2:
		var v := game.empire.vehicle(piloting)
		if not v.get("test", false):
			game.empire.drive(v, _km_acc * (3.0 if c.kind != "boat" else 1.5))   # (fuel by the km, more for aircraft)
		_km_acc = 0.0


func sync_positions() -> void:
	for vid in crafts:
		var c: Craft = crafts[vid]
		var v := game.empire.vehicle(vid)
		if c and is_instance_valid(c) and not v.is_empty():
			v["pos"] = [c.global_position.x, c.global_position.y, c.global_position.z]
			v["yaw"] = c.global_basis.get_euler().y


## Controls each physics frame: the touch drive pad and the keys, as for cars.
## Scenario / test hook: when set, used instead of the touch pad and keys.
var script_input := {}


func _physics_process(_dt: float) -> void:
	var c: Craft = crafts.get(piloting)
	if c == null:
		return
	if not script_input.is_empty():
		c.input = script_input.duplicate()
		return
	var pad: Dictionary = game.ui.touch.pad if game.ui and game.ui.touch else {}
	var key_gas := Input.get_action_strength("accelerate")
	var key_brake := Input.get_action_strength("brake")
	var key_steer := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var touch_steer := game.drive_input.touch_steer if game.drive_input.touch_active else 0.0
	var steer := key_steer if absf(key_steer) > absf(touch_steer) else touch_steer
	var pad_on := String(pad.get("zone", "")) != ""
	c.input = {
		"active": pad_on or key_gas > 0.0 or key_brake > 0.0 or Input.is_action_pressed("nitro"),
		"gas": maxf(float(pad.get("gas", 0.0)), key_gas),
		"kick": bool(pad.get("kick", false)) or (Input.is_action_pressed("nitro") and key_gas > 0.0),
		"brake": maxf(float(pad.get("brake", 0.0)), key_brake),
		"steer": clampf(steer, -1.0, 1.0),
	}


# -------------------------------------------------------------- test drives
## A test drive / flight: a temporary vehicle record (never saved, no cost),
## removed when you get out, and you're put back at the showroom.
func start_test(model: String, at_site: String) -> void:
	var s := site(at_site)
	_test_return = s.get("door", game.player.global_position)
	var kind := vclass(model)
	var pos: Vector3
	var yaw := 0.0
	if kind == "car":
		pos = (s["door"] as Vector3) + SkyportIsland.wd(Vector3(-8.0, 0.0, -9.0)) + Vector3.UP * 0.3
		yaw = SkyportIsland.wyaw(-PI * 0.5)
	else:
		var slot := free_slot(kind)
		pos = slot[0]
		yaw = slot[1]
	var v := game.empire.add_vehicle(model, pos, yaw)
	v["test"] = true
	if kind == "car":
		game._spawn_car(v)
		game.ui.close_panel(true)
		game.enter_vehicle(String(v["id"]))
	else:
		_spawn(v)
		game.ui.close_panel(true)
		enter(String(v["id"]))
	game.ui.toast("Test %s: get out to bring it back" % ("drive" if kind == "car" else ("sail" if kind == "boat" else "flight")), "info")


func end_test(vid: String) -> void:
	var v := game.empire.vehicle(vid)
	if v.is_empty() or not v.get("test", false):
		return
	game.empire.vehicles.erase(v)
	if crafts.has(vid):
		crafts[vid].queue_free()
		crafts.erase(vid)
	if game.cars.has(vid):
		game.cars[vid].queue_free()
		game.cars.erase(vid)
	if _test_return != Vector3.INF:
		game._teleport(_test_return + Vector3.UP + SkyportIsland.wd(Vector3(0, 0, 3.0)), game.camera.view_yaw())
	game.ui.toast("Test over – it's back with the dealer", "info")


# ------------------------------------------------------------ showrooms
func _process(dt: float) -> void:
	if game == null or game.skyport == null or game.state != "play":
		return
	_disp_t -= dt
	if _disp_t > 0.0:
		return
	_disp_t = 0.5
	update_markers()
	var p := game.player.global_position
	for sid in ["dealer_budget", "dealer_commercial", "dealer_luxury"]:
		var s := site(sid)
		var near := (s["door"] as Vector3).distance_to(p) < DISPLAY_RANGE
		var models: Array = STOCK[sid]
		for i in models.size():
			var key := "%s/%s" % [sid, models[i]]
			if near and not displays.has(key):
				displays[key] = _display_car(sid, String(models[i]), i)
			elif not near and displays.has(key):
				displays[key].queue_free()
				displays.erase(key)


## A display car on a forecourt (frozen: it's for looking at).
func _display_car(sid: String, model: String, i: int) -> Car:
	# (Laid out on the island's own plan – rows along the avenue – then placed.)
	var lot: Rect2 = game.skyport.plan_data["sites"][sid]["lot"]
	var c := Car.new()
	c.name = "Display_" + model
	c.setup(game._car_spec(model), "display")
	game.add_child(c)
	var vis := CarVisual.new()
	c.add_child(vis)
	vis.setup(c)
	c.visual = vis
	var x := lot.position.x + 10.0 + i * minf(17.0, (lot.size.x - 20.0) / maxf(float((STOCK[sid] as Array).size() - 1), 1.0))
	var pos := SkyportIsland.w(Vector3(x, SkyportIsland.LAND_Y + 0.35, lot.position.y + 30.0))
	c.place(Transform3D(Basis(Vector3.UP, SkyportIsland.wyaw(PI * 0.15)), pos))
	c.freeze = true
	c.set_meta("site", sid)
	c.set_meta("model", model)
	return c


# --------------------------------------------------------- ownership
var _own_sig := ""
var _own_root: Node3D


## Your buildings on Skyport Island wear a slim flag in your company's
## colours on the roof (subtle from the street, clear from the air);
## rebuilt when what you own changes.
func update_markers() -> void:
	var e := game.empire
	var owned: Array = (e.flags.get("estates", {}) as Dictionary).keys()
	if e.owns_property("home_skyport_penthouse"):
		owned.append("penthouse")
	owned.sort()
	var cols := [Color(e.brand.get("primary", "#f5b13d")), Color(e.brand.get("accent", "#f3efe6"))] if not e.brand.is_empty() \
		else [EmpireStyle.AMBER, EmpireStyle.PAPER]
	var sig := str(owned) + str(cols)
	if sig == _own_sig:
		return
	_own_sig = sig
	if _own_root:
		_own_root.queue_free()
	_own_root = Node3D.new()
	_own_root.name = "OwnedMarkers"
	game.add_child(_own_root)
	for id in owned:
		var at: Vector3
		if id == "penthouse":
			at = (game.skyport.wplan["penthouse"]["pad"] as Vector3) + SkyportIsland.wd(Vector3(-8.0, 0.0, -11.0))
		else:
			var d := Ventures.estate_def(String(id))
			if d.is_empty():
				continue
			at = Ventures.estate_at(d)
			var top := -INF
			var corner := Vector3(at.x, 0.0, at.z)
			for b: Dictionary in game.skyport.wplan["buildings"]:
				var t0: Array = b["tiers"][0]
				if at.x >= float(t0[0]) and at.x <= float(t0[2]) and at.z >= float(t0[1]) and at.z <= float(t0[3]):
					var tt: Array = b["tiers"][-1]
					top = float(tt[5])
					corner = Vector3(float(tt[0]) + 1.5, 0.0, float(tt[1]) + 1.5)
			if top == -INF:
				top = at.y + 1.0   # (the berths: on the pier)
			at = Vector3(corner.x, top, corner.z)
		_own_root.add_child(_flag(at, cols[0], cols[1]))


static func _flag(at: Vector3, a: Color, b: Color) -> Node3D:
	var n := Node3D.new()
	n.position = at
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := func(lo: Vector3, hi: Vector3, c: Color) -> void:
		var v := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
			Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
		for f in [[1, 0, 3, 2], [4, 5, 6, 7], [0, 4, 7, 3], [5, 1, 2, 6], [7, 6, 2, 3]]:
			for j in [0, 2, 1, 0, 3, 2]:
				st.set_color(c)
				st.add_vertex(v[f[j]])
	box.call(Vector3(-0.06, 0.0, -0.06), Vector3(0.06, 6.0, 0.06), Color(0.8, 0.8, 0.82))
	box.call(Vector3(0.06, 4.6, -0.02), Vector3(2.6, 5.9, 0.02), a)
	box.call(Vector3(0.06, 5.05, -0.025), Vector3(2.6, 5.45, 0.025), b)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.visibility_range_end = 1600.0
	n.add_child(mi)
	return n


## The penthouse's roof: a stair up to the helipad from the back of the
## room, and back down from the pad. [up spot, down spot] in the world.
func roof_spots() -> Array:
	var hm := game.home_by_id("home_skyport_penthouse")
	if hm.is_empty():
		return []
	var h: Dictionary = hm["h"]
	var up := Apartments.face_point(h, float(h["a0"]) + 1.6, -float(h["depth"]) + 1.6, float(h["y0"]))
	var pad: Vector3 = game.skyport.wplan["penthouse"]["pad"]
	return [up, pad + SkyportIsland.wd(Vector3(6.0, 0.0, 0.0))]


## The nearest showroom thing / craft / site within reach of p:
## {kind: sky_craft | sky_display | sky_site, ...} plus its distance "d".
func spot_near(p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for vid in crafts:
		var c: Craft = crafts[vid]
		if not is_instance_valid(c):
			continue
		var r := (c.spec["size"] as Vector3).z * 0.5 + REACH
		var d := Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length()
		if d < r and absf(c.global_position.y - p.y) < 4.0 and d - r < bd:
			bd = d - r
			best = {"kind": "sky_craft", "vehicle": vid, "world": c.global_position, "d": maxf(d - r, 0.0)}
	for key in displays:
		var dc: Car = displays[key]
		var d2 := Vector2(dc.global_position.x - p.x, dc.global_position.z - p.z).length() - 2.8
		if d2 < REACH and d2 < bd:
			bd = d2
			best = {"kind": "sky_display", "model": dc.get_meta("model"), "site": dc.get_meta("site"), "world": dc.global_position, "d": maxf(d2, 0.0)}
	if game.skyport and game.empire.owns_property("home_skyport_penthouse"):
		var rs := roof_spots()
		for k in rs.size():
			var q: Vector3 = rs[k]
			var dq := p.distance_to(q + Vector3.UP * 0.95)
			if dq < 2.0 and dq < bd:
				bd = dq
				best = {"kind": "sky_roof", "up": k == 0, "world": q, "d": dq}
	if game.skyport:
		var sites: Dictionary = game.skyport.wplan.get("sites", {})
		for sid in sites:
			if String(sid).begins_with("clothes") and game.venues and game.venues.has_venue(sid):
				continue   # (a walk-in shop: its points are inside)
			var door: Vector3 = sites[sid]["door"]
			var d3 := Vector2(door.x - p.x, door.z - p.z).length() - 3.0
			if d3 < REACH and absf(door.y - p.y) < 3.0 and d3 < bd:
				bd = d3
				best = {"kind": "sky_site", "site": sid, "world": door, "d": maxf(d3, 0.0)}
	if game.venues:
		var vs := game.venues.spot_near(p)
		if not vs.is_empty() and float(vs["d"]) < bd:
			best = vs
	return best


func prompt(s: Dictionary) -> Array:
	match String(s["kind"]):
		"sky_craft":
			var v := game.empire.vehicle(s["vehicle"])
			var md := EmpireData.vehicle_model(String(v.get("model", "")))
			var verb := {"heli": "FLY", "plane": "FLY", "boat": "BOARD"}.get(String(md.get("class", "")), "USE") as String
			return ["%s %s" % [verb, String(md.get("name", "")).to_upper()], true]
		"sky_display":
			var md2 := EmpireData.vehicle_model(String(s["model"]))
			return ["INSPECT %s · %s" % [String(md2.get("name", "")).to_upper(), EmpireData.money(float(md2.get("price", 0)))], true]
		"sky_roof":
			return ["UP TO THE HELIPAD" if s["up"] else "DOWN TO THE PENTHOUSE", true]
		"sky_site":
			var st := site(String(s["site"]))
			if s.has("venue_spot"):
				return ["%s · %s" % [Venues.spot_label(String(s["venue_spot"])), String(st.get("name", "")).to_upper()], true]
			var what := {"aviation": "AIRCRAFT SALES", "marina": "BOAT SALES", "cargo": "IMPORTS & CARGO",
				"clothes_everyday": "SHOP CLOTHES", "clothes_premium": "SHOP FASHION", "terminal": "AIRPORT"}.get(String(s["site"]), "SHOWROOM") as String
			return ["%s · %s" % [String(st.get("name", "")).to_upper(), what], true]
	return ["", false]


func act(s: Dictionary) -> void:
	match String(s["kind"]):
		"sky_craft":
			enter(String(s["vehicle"]))
		"sky_display":
			SkyportUI.vehicle_card(game.ui, String(s["model"]), String(s["site"]))
		"sky_roof":
			var rs := roof_spots()
			var to: Vector3 = rs[1] if s["up"] else rs[0]
			game._teleport(to + Vector3(0.0, 1.0, 0.0) + SkyportIsland.wd(Vector3(-1.5, 0, 0) if s["up"] else Vector3(1.5, 0, 0)), game.camera.view_yaw())
			Sfx.play("bell", -8.0)
		"sky_site":
			var sid := String(s["site"])
			match sid:
				"aviation", "marina", "dealer_budget", "dealer_commercial", "dealer_luxury":
					SkyportUI.showroom(game.ui, sid)
				"clothes_everyday", "clothes_premium":
					SkyportUI.clothes(game.ui, sid)
				"cargo":
					SkyportUI.imports(game.ui)
				"terminal":
					SkyportUI.terminal(game.ui)
