class_name VehicleGarage
extends Node3D
## The Vehicle Collection (2026-11-26): one luxury underground garage shared
## by every apartment lift ("VEHICLE COLLECTION" beside each lift in its
## ground lobby). Built once, deep under the city; collision always on (a
## car parked here never falls), visuals and lights only while you're in.
##
## Going down recalls every road vehicle you own into its own bay – the same
## Car nodes moved (condition, paint, damage, cargo all kept; nothing is
## spawned twice). Walk round them, get into any one and drive up the exit
## ramp: the shutter lifts, and you come out on a safe road beside the
## building you came down from, still driving. On foot, the lift door takes
## you back up to that lobby.
##
## Local frame: origin at the lift doors, +Z down the aisle, +X right.

const ORIGIN := Vector3(470.0, -320.0, -195.0)   # under the old town, never under the sea
const BAY_W := 3.2
const BAY_D := 6.0
const AISLE := 7.0
const LOBBY := 5.0
const H := 4.2
const RAMP_LEN := 14.0
const MIN_BAYS := 8

var game: EmpireGame
var bays := 0
var from_home := ""
var inside := false
var _vis: Node3D
var _col: StaticBody3D
var _shutter: Node3D
var _shutter_open := 0.0
var _lights: Array[Light3D] = []
var _built_for := -1


func setup(g: EmpireGame) -> void:
	game = g
	position = ORIGIN
	_build(MIN_BAYS)


func row_len() -> float:
	return float(bays / 2) * BAY_W


func ramp_start() -> float:
	return LOBBY + row_len() + 2.0


## Local transform of bay i (cars nose-in to the side walls, facing out to the aisle).
func bay_xf(i: int) -> Transform3D:
	var side := -1.0 if i % 2 == 0 else 1.0
	var z := LOBBY + BAY_W * (float(i / 2) + 0.5)
	var x := side * (AISLE * 0.5 + BAY_D * 0.5)
	# reversed in: the car's front (-Z local of a Car) faces the aisle
	var b := Basis(Vector3.UP, PI * 0.5 if side < 0.0 else -PI * 0.5)
	return Transform3D(b, Vector3(x, 0.05, z))


func lift_door_world() -> Vector3:
	return to_global(Vector3(0.0, 0.0, 0.6))


func _cars() -> Array:
	var out: Array = []
	for v in game.empire.vehicles:
		if SkyportPlay.vclass(String(v["model"])) != "car" or v.get("test", false) or v.get("stolen", false):
			continue
		var c: Car = game.cars.get(String(v["id"]))
		if c and is_instance_valid(c) and String(v["id"]) != game.driving:
			out.append([v, c])
	return out


# ------------------------------------------------------------ going down / coming up
func enter(home_id: String) -> void:
	from_home = home_id
	var cars := _cars()
	var need := maxi(MIN_BAYS, ((cars.size() + 2 + 1) / 2) * 2)
	if need != bays:
		_build(need)
	_set_visible(true)
	inside = true
	for i in cars.size():
		var v: Dictionary = cars[i][0]
		var c: Car = cars[i][1]
		if game.street_cars:
			# out of the lock-up too: every car's in the collection
			if String(v.get("stored", "")) != "":
				v.erase("stored")
				c.process_mode = Node.PROCESS_MODE_INHERIT
				c.visible = true
				var lm: Array = c.get_meta("lockup_layers", [c.collision_layer, c.collision_mask])
				c.collision_layer = int(lm[0])
				c.collision_mask = int(lm[1])
				c.remove_meta("lockup_layers")
		v.erase("wanted_at")
		c.freeze = false
		c.linear_velocity = Vector3.ZERO
		c.angular_velocity = Vector3.ZERO
		var xf := global_transform * bay_xf(i)
		c.place(xf)
		c.park_lock = true
		v["pos"] = [xf.origin.x, xf.origin.y, xf.origin.z]
		v["yaw"] = xf.basis.get_euler().y
	game._teleport(to_global(Vector3(0.0, 1.0, 2.2)), PI)
	game.ui.toast("Vehicle Collection · %d car%s · drive up the ramp to leave" % [cars.size(), "" if cars.size() == 1 else "s"], "info")
	Sfx.play("bell", -8.0)


## Back up the lift on foot, to the lobby you came down from.
func leave_on_foot() -> void:
	inside = false
	_set_visible(false)
	var home := game.home_by_id(from_home)
	var el: ApartmentElevator = game.elevators.get(from_home)
	if el:
		game._teleport(el.ground_call_world() + el.global_basis.z * 1.6 + Vector3.UP * 1.0, el.global_basis.get_euler().y)
	elif not home.is_empty():
		game._teleport(game.home_lift(home) + Vector3.UP, 0.0)
	Sfx.play("bell", -8.0)


func _exit_by_road(c: Car) -> void:
	var el: ApartmentElevator = game.elevators.get(from_home)
	var near := el.street_door_world() if el else game.player.global_position
	var r: Dictionary = game.safe.road_spot(near + Vector3.DOWN * 0.9, c.spec["size"], {"exclude": [c.get_rid()], "min_d": 4.0})
	if not r["ok"]:
		r = game.safe.road_spot(near + Vector3.DOWN * 0.9, c.spec["size"], {"exclude": [c.get_rid()], "min_d": 4.0, "max_r": 120.0})
	if not r["ok"]:
		game.ui.toast("No clear road outside – try again in a moment", "warn")
		c.place(global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.05, ramp_start() - 2.0)))
		return
	var xf: Transform3D = r["xf"]
	c.place(Transform3D(xf.basis, xf.origin + xf.basis.y * 0.35), -xf.basis.z * 6.0)
	inside = false
	_set_visible(false)
	game.chase.set_target(c, true)
	Sfx.play("chime", -8.0)


func _process(dt: float) -> void:
	if not inside or game == null:
		return
	# The shutter lifts for a car coming up the ramp; the top of the ramp is
	# the way out.
	var dc: Car = game.cars.get(game.driving) if game.driving != "" else null
	var want := 0.0
	if dc and dc.global_position.distance_to(global_position) < 200.0:
		var lp := to_local(dc.global_position)
		if lp.z > ramp_start() - 6.0:
			want = 1.0
		if lp.z > ramp_start() + RAMP_LEN - 1.5:
			_exit_by_road(dc)
			return
	_shutter_open = move_toward(_shutter_open, want, dt * 1.4)
	if _shutter:
		_shutter.position.y = 2.0 + _shutter_open * 3.2
	if dc == null and game.player.global_position.distance_to(global_position) > 400.0:
		inside = false
		_set_visible(false)


## Near the lift doors on foot: the way back up.
func spot_near(p: Vector3) -> Dictionary:
	if not inside or game.driving != "":
		return {}
	var d := p.distance_to(lift_door_world() + Vector3.UP * 0.9)
	return {"kind": "garage_up", "world": lift_door_world(), "d": d} if d < 2.4 else {}


func _set_visible(on: bool) -> void:
	if _vis:
		_vis.visible = on
	for l in _lights:
		l.visible = on


# ------------------------------------------------------------ geometry
func _mat(c: Color, rough: float, metal := 0.0, emit := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit != Color.BLACK:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = 2.2
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, solid := false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = at
		_col.add_child(cs)


func _build(n: int) -> void:
	bays = n
	if _vis:
		_vis.queue_free()
	if _col:
		_col.queue_free()
	_lights.clear()
	_vis = Node3D.new()
	_vis.name = "Visual"
	add_child(_vis)
	_col = StaticBody3D.new()
	_col.name = "Collision"
	_col.collision_layer = 1 | (1 << 1)
	add_child(_col)
	var floor_m := _mat(Color(0.16, 0.165, 0.17), 0.22, 0.15)      # polished concrete
	var wall_m := _mat(Color(0.82, 0.81, 0.78), 0.6)
	var dark_m := _mat(Color(0.07, 0.075, 0.08), 0.5)
	var line_m := _mat(Color(0.92, 0.9, 0.85), 0.5)
	var led_m := _mat(Color(0.9, 0.95, 1.0), 0.4, 0.0, Color(0.85, 0.92, 1.0))
	var warm_m := _mat(Color(1.0, 0.9, 0.75), 0.4, 0.0, Color(1.0, 0.86, 0.66))
	var L := ramp_start()
	var W := AISLE + BAY_D * 2.0 + 1.0
	# floor, ceiling, walls (lobby + bays)
	_box(_vis, Vector3(W, 0.2, L), Vector3(0, -0.1, L * 0.5), floor_m, true)
	_box(_vis, Vector3(W, 0.2, L), Vector3(0, H + 0.1, L * 0.5), dark_m, true)
	for sx: float in [-1.0, 1.0]:
		_box(_vis, Vector3(0.3, H, L), Vector3(sx * (W * 0.5 + 0.15), H * 0.5, L * 0.5), wall_m, true)
	_box(_vis, Vector3(W, H, 0.3), Vector3(0, H * 0.5, -0.15), wall_m, true)
	# lift doors (brushed steel) in the back wall, and a lobby carpet
	_box(_vis, Vector3(2.2, 2.5, 0.06), Vector3(0, 1.25, 0.02), _mat(Color(0.6, 0.62, 0.64), 0.3, 0.9))
	_box(_vis, Vector3(6.0, 0.02, 3.6), Vector3(0, 0.01, 2.2), _mat(Color(0.18, 0.08, 0.06), 0.9))
	var sign := Label3D.new()
	sign.text = "VEHICLE COLLECTION"
	sign.font_size = 72
	sign.pixel_size = 0.006
	sign.modulate = Color(0.95, 0.9, 0.8)
	sign.position = Vector3(0, 3.1, 0.08)
	_vis.add_child(sign)
	# bays: lines, number boards, LED back strips, pillars, ceiling light strips
	for i in n:
		var xf := bay_xf(i)
		var side := -1.0 if i % 2 == 0 else 1.0
		var zc := xf.origin.z
		for dz: float in [-BAY_W * 0.5, BAY_W * 0.5]:
			_box(_vis, Vector3(BAY_D, 0.012, 0.1), Vector3(xf.origin.x, 0.006, zc + dz), line_m)
		_box(_vis, Vector3(0.12, 0.012, BAY_W), Vector3(side * (AISLE * 0.5 + 0.06), 0.006, zc), line_m)
		_box(_vis, Vector3(0.05, 0.08, BAY_W - 0.4), Vector3(side * (W * 0.5 - 0.03), 2.4, zc), led_m)
		var num := Label3D.new()
		num.text = "%02d" % (i + 1)
		num.font_size = 96
		num.pixel_size = 0.005
		num.modulate = Color(0.95, 0.95, 0.95)
		num.position = Vector3(side * (W * 0.5 - 0.02), 3.1, zc)
		num.rotation.y = -PI * 0.5 if side > 0.0 else PI * 0.5   # (facing into the aisle, readable)
		_vis.add_child(num)
		_box(_vis, Vector3(0.5, 0.04, BAY_W - 0.6), Vector3(xf.origin.x, H - 0.03, zc), warm_m)
		if i % 2 == 0:
			for sx: float in [-1.0, 1.0]:
				_box(_vis, Vector3(0.5, H, 0.5), Vector3(sx * (AISLE * 0.5 + BAY_D + 0.2), H * 0.5, zc - BAY_W * 0.5), wall_m, true)
	# aisle light strip
	_box(_vis, Vector3(0.3, 0.04, L - LOBBY), Vector3(0, H - 0.03, (L + LOBBY) * 0.5), led_m)
	# lights: a few soft omnis for the showroom look (mobile: <= 8 per object)
	var k := 0
	for z in range(int(LOBBY), int(L), 10):
		var o := OmniLight3D.new()
		o.position = Vector3(0, H - 0.4, float(z) + 4.0)
		o.omni_range = 12.0
		o.light_energy = 1.4
		o.light_color = Color(1.0, 0.95, 0.88)
		o.shadow_enabled = false
		_vis.add_child(o)
		_lights.append(o)
		k += 1
		if k >= 6:
			break
	# the exit ramp up to the shutter
	var ramp := Node3D.new()
	_vis.add_child(ramp)
	var rise := 3.0
	var ang := atan2(rise, RAMP_LEN)
	var rmi := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(AISLE, 0.2, RAMP_LEN / cos(ang))
	rmi.mesh = rb
	rmi.material_override = floor_m
	rmi.position = Vector3(0, rise * 0.5 - 0.1, L + RAMP_LEN * 0.5)
	rmi.rotation.x = -ang
	_vis.add_child(rmi)
	var rcs := CollisionShape3D.new()
	var rsh := BoxShape3D.new()
	rsh.size = rb.size
	rcs.shape = rsh
	rcs.position = rmi.position
	rcs.rotation = rmi.rotation
	_col.add_child(rcs)
	for sx: float in [-1.0, 1.0]:
		_box(_vis, Vector3(0.3, H + rise, RAMP_LEN), Vector3(sx * (AISLE * 0.5 + 0.15), (H + rise) * 0.5, L + RAMP_LEN * 0.5), wall_m, true)
	_box(_vis, Vector3(AISLE, 0.2, RAMP_LEN), Vector3(0, H + rise + 0.1, L + RAMP_LEN * 0.5), dark_m, true)
	_shutter = Node3D.new()
	_shutter.position = Vector3(0, 2.0, L + RAMP_LEN - 0.5)
	_vis.add_child(_shutter)
	_box(_shutter, Vector3(AISLE, 4.0, 0.12), Vector3(0, rise, 0), _mat(Color(0.5, 0.52, 0.55), 0.45, 0.8))
	# (the shutter's leaf is visual; the exit fires before a car reaches it)
	# An interior: no street mist down here, the room's own light (InteriorKit).
	var zone := InteriorKit.add_lighting_zone(_vis, AABB(Vector3(-W * 0.5, -0.5, -0.5), Vector3(W, H + rise + 1.0, L + RAMP_LEN + 1.0)))
	InteriorKit.room_probe(zone, Color(0.96, 0.97, 1.0), 0.75, 0.5)
	_set_visible(inside)
