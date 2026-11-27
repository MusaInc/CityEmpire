class_name VehicleGarage
extends Node3D
## The Vehicle Collection: one luxury underground garage shared by every
## apartment lift. Built once, deep under the city; collision always on (a
## car parked here never falls), visuals and lights only while you're in.
##
## 2026-11-27 overhaul (WorldState engine pass):
##   * You arrive by lift, not by teleport: the apartment cabin's doors
##     close, the indicator counts down G → B1 → B2 while the car shudders,
##     and you are carried – unseen, doors shut – into this garage's own lift
##     cabin, which is built to the same plan and finish as the one you left
##     (ApartmentElevator.build_garage_stop). Its doors open on the garage.
##     Going back up is the same in reverse, into the apartment cabin, which
##     then rides on to your floor if you chose it.
##   * Bays 3.9 m wide (a car door opens fully between neighbours), an 8 m
##     aisle and a turning apron before the ramp; numbered bays painted on
##     the floor and on the wall, wheel stops, columns between bay pairs,
##     a bollarded lift lobby, ceiling beams, services, light fittings.
##   * An illuminated exit ramp: LED kerb lines, chevrons, WAY OUT and
##     arrow signs, the shutter lifting as you approach, daylight beyond.
##     Crossing it the screen washes to the light outside, the car is put
##     on the road beside your building (same car, same speed, same
##     damage) while the street there is already streamed, and the light
##     fades back to the street.
## While you're down here the city keeps streaming round your building
## (CityWorld.stream_anchor), so coming out never waits on loading.
##
## Local frame: origin at the lift doors, +Z down the aisle, +X right.

const ORIGIN := Vector3(470.0, -320.0, -195.0)   # under the old town, never under the sea
const BAY_W := 3.9
const BAY_D := 6.2
const AISLE := 8.0
const LOBBY := 7.0
const APRON := 6.0
const H := 4.4
const RAMP_LEN := 28.0
const RAMP_RISE := 4.4
const RAMP_W := 7.0
const MIN_BAYS := 8
const BAY_LEVEL := "B2"

var game: EmpireGame
var bays := 0
var from_home := ""
var inside := false
var lift: ApartmentElevator
var _vis: Node3D
var _col: StaticBody3D
var _shutter: Node3D
var _shutter_open := 0.0
var _lights: Array[Light3D] = []
var _plaques: Array[Label3D] = []
var _lift_tier := -1
var _anchor: Node3D
var _exit: Dictionary = {}        # the road spot outside, found as you climb
var _wash: ColorRect
var _wash_layer: CanvasLayer
var _wash_t := 0.0                # >0 fading in, <0 fading out
var _exiting: Car


func setup(g: EmpireGame) -> void:
	game = g
	position = ORIGIN
	_anchor = Node3D.new()
	_anchor.name = "StreamAnchor"
	_anchor.top_level = true
	add_child(_anchor)
	_wash_layer = CanvasLayer.new()
	_wash_layer.layer = 90
	add_child(_wash_layer)
	_wash = ColorRect.new()
	_wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wash.color = Color(1, 1, 1, 0)
	_wash.visible = false
	_wash_layer.add_child(_wash)
	_build(MIN_BAYS)
	_build_lift(0)


func row_len() -> float:
	return float(bays / 2) * BAY_W


func ramp_start() -> float:
	return LOBBY + row_len() + APRON


func ramp_end() -> float:
	return ramp_start() + RAMP_LEN


func width() -> float:
	return AISLE + BAY_D * 2.0 + 1.0


## Local transform of bay i (cars reversed in, front on show to the aisle).
func bay_xf(i: int) -> Transform3D:
	var side := -1.0 if i % 2 == 0 else 1.0
	var z := LOBBY + BAY_W * (float(i / 2) + 0.5)
	var x := side * (AISLE * 0.5 + BAY_D * 0.5)
	# A Car's front is its local -Z, turned to face the aisle (+X on the
	# left row, -X on the right).
	var b := Basis(Vector3.UP, -PI * 0.5 if side < 0.0 else PI * 0.5)
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


func _home_tier(hid: String) -> int:
	var home := game.home_by_id(hid)
	return clampi(int(home.get("tier", 0)), 0, 4) if not home.is_empty() else 0


# ------------------------------------------------------------ going down / coming up
## Into the garage: every car into its bay, the lights on, the city kept
## streaming round the building you came from. `teleport` false: the lift
## hand-off has already placed you (in this garage's cabin).
func enter(home_id: String, teleport := true) -> void:
	from_home = home_id
	var cars := _cars()
	var need := maxi(MIN_BAYS, ((cars.size() + 2 + 1) / 2) * 2)
	if need != bays:
		_build(need)
	var tier := _home_tier(home_id)
	if tier != _lift_tier:
		_build_lift(tier)
	_set_visible(true)
	inside = true
	_exit = {}
	for p in _plaques:
		p.text = ""
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
		if i < _plaques.size():
			_plaques[i].text = String(EmpireData.vehicle_model(String(v["model"])).get("name", "")).to_upper()
		c.park_lock = true
		v["pos"] = [xf.origin.x, xf.origin.y, xf.origin.z]
		v["yaw"] = xf.basis.get_euler().y
	game.player.kill_plane_floor = ORIGIN.y - 30.0   # (below the world on purpose)
	# The street above stays streamed (and its traffic and people) while
	# you're down here: the way out is ready before you reach it.
	var el: ApartmentElevator = game.elevators.get(home_id)
	_anchor.global_position = el.street_door_world() if el else game.player.global_position
	game.world.stream_anchor = _anchor
	if game.layout.mainland and game.world.mainland:
		game.world.mainland.stream_anchor = _anchor
	if teleport:
		lift.arrive_sealed(false, BAY_LEVEL)
		game._teleport_local(lift.cabin_xf(), Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.95, -ApartmentElevator.SHAFT_D * 0.5)))
	game.ui.toast("Vehicle Collection · %d car%s · drive up the ramp to leave" % [cars.size(), "" if cars.size() == 1 else "s"], "info")


func _release_stream() -> void:
	if game.world.stream_anchor == _anchor:
		game.world.stream_anchor = null
	if game.world.mainland and game.world.mainland.stream_anchor == _anchor:
		game.world.mainland.stream_anchor = null


## Leaving by the lift (EmpireGame.arrive_from_garage has carried you on).
func leave_quietly() -> void:
	inside = false
	game.player.kill_plane_floor = INF
	_release_stream()
	_set_visible(false)
	if lift:
		lift.settle_closed()


## Back up on foot without the ride (Settings "Stuck?", tests).
func leave_on_foot() -> void:
	leave_quietly()
	var home := game.home_by_id(from_home)
	var el: ApartmentElevator = game.elevators.get(from_home)
	if el:
		game._teleport(el.ground_call_world() + el.global_basis.z * 1.6 + Vector3.UP * 1.0, el.global_basis.get_euler().y)
	elif not home.is_empty():
		game._teleport(game.home_lift(home) + Vector3.UP, 0.0)


## The road outside: the nearest safe spot by the building's street door,
## facing along the road (picked as you start up the ramp).
func _find_exit(c: Car) -> Dictionary:
	var el: ApartmentElevator = game.elevators.get(from_home)
	var near := el.street_door_world() if el else _anchor.global_position
	var r: Dictionary = game.safe.road_spot(near + Vector3.DOWN * 0.9, c.spec["size"], {"exclude": [c.get_rid()], "min_d": 4.0})
	if not r["ok"]:
		r = game.safe.road_spot(near + Vector3.DOWN * 0.9, c.spec["size"], {"exclude": [c.get_rid()], "min_d": 4.0, "max_r": 120.0})
	return r


func _daylight() -> Color:
	var hr: float = game.atmosphere.hour if game.atmosphere else 12.0
	var day := clampf(minf(hr - 5.0, 21.5 - hr) / 1.5, 0.0, 1.0)
	return Color(0.05, 0.06, 0.08).lerp(Color(1.0, 0.98, 0.93), day)


func _exit_by_road(c: Car) -> void:
	if _exit.is_empty() or not bool(_exit.get("ok", false)):
		_exit = _find_exit(c)
	if not bool(_exit.get("ok", false)):
		game.ui.toast("No clear road outside – try again in a moment", "warn")
		c.place(global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.05, ramp_start() - 2.0)))
		_wash_t = -0.01
		return
	var spd := clampf(c.forward_speed, 5.0, 12.0)
	var xf: Transform3D = _exit["xf"]
	c.place(Transform3D(xf.basis, xf.origin + xf.basis.y * 0.35), -xf.basis.z * spd)
	game.player.kill_plane_floor = INF
	inside = false
	_release_stream()
	_set_visible(false)
	game.chase.set_target(c, true)
	if lift:
		lift.settle_closed()
	_exit = {}


func _process(dt: float) -> void:
	_tick_wash(dt)
	if not inside or game == null:
		return
	if lift:
		lift.tick(dt, game.player, true)
	# The shutter lifts for a car coming up the ramp; past it, the light.
	var dc: Car = game.cars.get(game.driving) if game.driving != "" else null
	var want := 0.0
	if dc and dc.global_position.distance_to(global_position) < 260.0:
		var lp := to_local(dc.global_position)
		if lp.z > ramp_start() - 2.0:
			if _exit.is_empty():
				_exit = _find_exit(dc)   # (once, a physics query, early)
		if lp.z > ramp_end() - 16.0:
			want = 1.0
		if lp.z > ramp_end() - 3.2 and _wash_t == 0.0 and lp.y > RAMP_RISE - 1.5:
			_exiting = dc
			_wash.color = _daylight()
			_wash.color.a = 0.0
			_wash.visible = true
			_wash_t = 0.001
	_shutter_open = move_toward(_shutter_open, want, dt * 0.9)
	if _shutter:
		_shutter.position.y = _shutter_open * 3.6
	if dc == null and game.player.global_position.distance_to(global_position) > 400.0:
		inside = false
		_release_stream()
		_set_visible(false)


## The wash of light at the top of the ramp: up in 0.22 s, the car moved
## at its peak, then down over 0.6 s on the street.
func _tick_wash(dt: float) -> void:
	if _wash_t == 0.0:
		return
	if _wash_t > 0.0:
		_wash_t += dt
		_wash.color.a = clampf(_wash_t / 0.22, 0.0, 1.0)
		if _wash_t >= 0.22:
			if _exiting and is_instance_valid(_exiting) and inside:
				_exit_by_road(_exiting)
			_exiting = null
			_wash_t = -0.001
	else:
		_wash_t -= dt
		_wash.color.a = clampf(1.0 + _wash_t / 0.6, 0.0, 1.0)
		if _wash_t <= -0.6:
			_wash_t = 0.0
			_wash.visible = false


## In the garage lift's cabin on foot: the floor buttons (back up).
func spot_near(p: Vector3) -> Dictionary:
	if not inside or game.driving != "" or lift == null:
		return {}
	if lift.is_inside_cabin(p) and lift.state == "idle_g":
		return {"kind": "garage_up", "world": lift.cabin_panel_world(), "d": 0.1}
	var d := p.distance_to(lift_door_world() + Vector3.UP * 0.9)
	if d < 2.0 and lift.state == "idle_g" and lift._g_door_open < 0.5:
		return {"kind": "garage_call", "world": lift.ground_call_world(), "d": d}
	return {}


func _set_visible(on: bool) -> void:
	if _vis:
		_vis.visible = on
	if lift:
		lift.visible = on
	for l in _lights:
		l.visible = on


# ------------------------------------------------------------ geometry
func _build_lift(tier: int) -> void:
	_lift_tier = tier
	if lift:
		lift.queue_free()
	lift = ApartmentElevator.build_garage_stop(tier, BAY_LEVEL)
	add_child(lift)
	lift.visible = inside


func _mat(c: Color, rough: float, metal := 0.0, emit := Color.BLACK, energy := 2.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit != Color.BLACK:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	return m


## Boxes are batched per material into one mesh each (a few draw calls for
## the whole garage instead of one per box).
var _batches := {}   # material -> BuildingMesher-free SurfaceTool arrays


func _box(_parent: Node3D, size: Vector3, at: Vector3, mat: Material, solid := false, rot_x := 0.0) -> void:
	_box_rot(size, at, Basis(Vector3.RIGHT, rot_x), mat)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = at
		cs.rotation.x = rot_x
		_col.add_child(cs)


static func _half_on(v: Vector3, hs: Vector3) -> float:
	return absf(v.x) * hs.x + absf(v.y) * hs.y + absf(v.z) * hs.z


func _flush_batches() -> void:
	for mat: Material in _batches:
		var b: Array = _batches[mat]
		if (b[0] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b[0]
		arr[Mesh.ARRAY_NORMAL] = b[1]
		arr[Mesh.ARRAY_INDEX] = b[2]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		var sm := mat as StandardMaterial3D
		if sm and (sm.emission_enabled or sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(mi)
	_batches.clear()


func _label(text: String, size: int, px: float, col: Color, at: Vector3, rot: Vector3, outline := 0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = outline
	l.outline_modulate = Color(0.02, 0.02, 0.03)
	l.position = at
	l.rotation = rot
	l.double_sided = false
	l.shaded = false
	_vis.add_child(l)
	return l


func _build(n: int) -> void:
	bays = n
	if _vis:
		_vis.queue_free()
	if _col:
		_col.queue_free()
	_lights.clear()
	_batches.clear()
	_vis = Node3D.new()
	_vis.name = "Visual"
	add_child(_vis)
	_col = StaticBody3D.new()
	_col.name = "Collision"
	_col.collision_layer = 1 | (1 << 1)
	add_child(_col)
	var floor_m := _mat(Color(0.34, 0.35, 0.36), 0.22, 0.05)     # sealed concrete (epoxy)
	var aisle_m := _mat(Color(0.22, 0.23, 0.245), 0.3, 0.05)     # darker drive aisle
	var wall_m := _mat(Color(0.80, 0.79, 0.76), 0.75)            # fair-faced concrete, painted
	var dado_m := _mat(Color(0.16, 0.17, 0.19), 0.55)            # dark lower band
	var ceil_m := _mat(Color(0.52, 0.52, 0.51), 0.9)
	var beam_m := _mat(Color(0.6, 0.6, 0.59), 0.85)
	var duct_m := _mat(Color(0.66, 0.67, 0.68), 0.4, 0.7)
	var red_m := _mat(Color(0.62, 0.08, 0.06), 0.5)
	var line_m := _mat(Color(0.92, 0.9, 0.84), 0.55)
	var yellow_m := _mat(Color(0.95, 0.74, 0.12), 0.55)
	var walk_m := _mat(Color(0.28, 0.45, 0.38), 0.6)             # green pedestrian walkway
	var led_m := _mat(Color(0.95, 0.97, 1.0), 0.4, 0.0, Color(0.88, 0.94, 1.0), 3.0)
	var warm_m := _mat(Color(1.0, 0.92, 0.78), 0.4, 0.0, Color(1.0, 0.86, 0.66), 2.6)
	var panel_m := _mat(Color(0.95, 0.93, 0.88), 0.5, 0.0, Color(0.62, 0.56, 0.46), 1.8)
	var exit_m := _mat(Color(0.02, 0.32, 0.14), 0.4, 0.0, Color(0.02, 0.42, 0.16), 1.2)
	var sign_m := _mat(Color(0.06, 0.07, 0.08), 0.4, 0.3)
	var steel_m := _mat(Color(0.62, 0.64, 0.66), 0.28, 0.9)
	var stop_m := _mat(Color(0.2, 0.2, 0.21), 0.8)
	var day_m := StandardMaterial3D.new()
	day_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	day_m.albedo_color = Color(1.0, 0.98, 0.94)
	var pool_m := StandardMaterial3D.new()
	pool_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pool_m.albedo_color = Color(1.0, 0.92, 0.78, 0.18)
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(0.5, 0.0)
	var gg := Gradient.new()
	gg.set_color(0, Color(1, 1, 1, 1))
	gg.set_color(1, Color(1, 1, 1, 0))
	grad.gradient = gg
	pool_m.albedo_texture = grad
	_plaques.clear()
	var L := ramp_start()
	var W := width()
	var ax := AISLE * 0.5
	var bx1 := ax + BAY_D           # back of the bays
	# ---- shell: floor, ceiling, walls
	_box(_vis, Vector3(W, 0.2, L), Vector3(0, -0.1, L * 0.5), floor_m, true)
	_box(_vis, Vector3(AISLE, 0.01, L - LOBBY + 0.02), Vector3(0, 0.006, (L + LOBBY) * 0.5), aisle_m)
	_box(_vis, Vector3(W, 0.25, L), Vector3(0, H + 0.125, L * 0.5), ceil_m, true)
	for sx: float in [-1.0, 1.0]:
		_box(_vis, Vector3(0.3, H, L), Vector3(sx * (W * 0.5 + 0.15), H * 0.5, L * 0.5), wall_m, true)
		_box(_vis, Vector3(0.02, 1.1, L - 0.2), Vector3(sx * (W * 0.5 - 0.01), 0.55, L * 0.5), dado_m)
	# back wall (the lift is built into it: ApartmentElevator.build_garage_stop
	# cuts the opening and dresses the portal; this wall fills either side)
	var lw := ApartmentElevator.PORTAL_HW + 0.35
	for sx: float in [-1.0, 1.0]:
		var w0 := lw
		var w1 := W * 0.5 + 0.3
		_box(_vis, Vector3(w1 - w0, H, 0.3), Vector3(sx * (w0 + w1) * 0.5, H * 0.5, -0.15), wall_m, true)
	_box(_vis, Vector3(lw * 2.0, H - ApartmentElevator.PORTAL_H, 0.3), Vector3(0, (H + ApartmentElevator.PORTAL_H) * 0.5, -0.15), wall_m, true)
	# the far end: a wall either side of the ramp's mouth
	var rw := RAMP_W * 0.5 + 0.8
	for sx: float in [-1.0, 1.0]:
		_box(_vis, Vector3(W * 0.5 - rw + 0.3, H, 0.3), Vector3(sx * (rw + W * 0.5 + 0.3) * 0.5, H * 0.5, L + 0.15), wall_m, true)
		_box(_vis, Vector3(W * 0.5 - rw + 0.3, 1.1, 0.02), Vector3(sx * (rw + W * 0.5 + 0.3) * 0.5, 0.55, L - 0.01), dado_m)
	# ---- ceiling structure: transverse beams every two bays, a duct and a
	# sprinkler main along the aisle, cable trays over the bays
	var z := LOBBY
	while z <= L + 0.01:
		_box(_vis, Vector3(W, 0.55, 0.4), Vector3(0, H - 0.275, z), beam_m)
		z += BAY_W * 2.0
	_box(_vis, Vector3(0.9, 0.45, L - 1.0), Vector3(-ax + 0.9, H - 0.9, L * 0.5 + 0.5), duct_m)
	_box(_vis, Vector3(0.08, 0.08, L - 1.0), Vector3(ax - 0.7, H - 0.7, L * 0.5 + 0.5), red_m)
	for sx: float in [-1.0, 1.0]:
		_box(_vis, Vector3(0.4, 0.06, L - LOBBY), Vector3(sx * (bx1 - 0.6), H - 0.65, (L + LOBBY) * 0.5), duct_m)
	# ---- the lift lobby: a walkway, bollards, signs, seating, planters
	_box(_vis, Vector3(2.0, 0.012, LOBBY - 0.6), Vector3(0, 0.008, (LOBBY - 0.6) * 0.5 + 0.3), walk_m)
	_box(_vis, Vector3(AISLE - 0.4, 0.013, 0.3), Vector3(0, 0.009, LOBBY - 0.15), yellow_m)
	for bxp: float in [-3.9, -2.6, -0.9, 0.9, 2.6, 3.9]:
		var bol := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.11
		cyl.bottom_radius = 0.11
		cyl.height = 1.0
		bol.mesh = cyl
		bol.material_override = steel_m
		bol.position = Vector3(bxp, 0.5, LOBBY - 0.6)
		_vis.add_child(bol)
		_box(_vis, Vector3(0.24, 0.06, 0.24), Vector3(bxp, 0.85, LOBBY - 0.6), yellow_m)
		var bcs := CollisionShape3D.new()
		var bsh := CylinderShape3D.new()
		bsh.radius = 0.12
		bsh.height = 1.0
		bcs.shape = bsh
		bcs.position = bol.position
		_col.add_child(bcs)
	var leather := _mat(Color(0.12, 0.07, 0.05), 0.45)
	var oak := _mat(Color(0.42, 0.29, 0.18), 0.5)
	for sx: float in [-1.0, 1.0]:
		var lx := sx * (ax + 2.6)
		_box(_vis, Vector3(0.85, 0.42, 2.2), Vector3(lx, 0.21, 2.6), leather, true)
		_box(_vis, Vector3(0.2, 0.5, 2.2), Vector3(lx + sx * 0.4, 0.62, 2.6), leather)
		_box(_vis, Vector3(0.6, 0.36, 1.0), Vector3(lx - sx * 1.1, 0.18, 2.6), oak, true)
		for pz: float in [0.8, 4.6]:
			_box(_vis, Vector3(0.6, 0.6, 0.6), Vector3(sx * (ax + 1.2), 0.3, pz), _mat(Color(0.15, 0.15, 0.16), 0.5), true)
			_box(_vis, Vector3(0.5, 0.9, 0.5), Vector3(sx * (ax + 1.2), 1.05, pz), _mat(Color(0.14, 0.3, 0.12), 0.9))
		# feature wall either side of the lift: backlit slatted panels
		for k in 7:
			var px := sx * (lw + 0.25 + k * 0.32)
			_box(_vis, Vector3(0.16, 3.2, 0.06), Vector3(px, 1.75, 0.03), oak)
		_box(_vis, Vector3(2.3, 3.2, 0.02), Vector3(sx * (lw + 1.2), 1.75, 0.005), warm_m)
	_label("VEHICLE COLLECTION", 72, 0.0055, Color(0.95, 0.9, 0.8), Vector3(0, 3.95, 0.4), Vector3.ZERO)
	_label("RESIDENTS' LIFT  ·  LEVEL %s" % BAY_LEVEL, 40, 0.004, Color(0.85, 0.82, 0.74), Vector3(0, 3.55, 0.4), Vector3.ZERO)
	# ---- bays: lines, wheel stops, numbers (floor + wall), LED backlights,
	# columns between bay pairs, a pool of light in front of each car
	for i in n:
		var xf := bay_xf(i)
		var side := -1.0 if i % 2 == 0 else 1.0
		var zc := xf.origin.z
		for dz: float in [-BAY_W * 0.5, BAY_W * 0.5]:
			_box(_vis, Vector3(BAY_D - 0.2, 0.012, 0.12), Vector3(xf.origin.x + side * 0.1, 0.008, zc + dz), line_m)
		_box(_vis, Vector3(0.14, 0.012, BAY_W), Vector3(side * (ax + 0.07), 0.008, zc), line_m)
		# wheel stops at the back (low, visual: cars reverse in to them)
		for dz2: float in [-0.75, 0.75]:
			_box(_vis, Vector3(0.18, 0.1, 0.7), Vector3(side * (bx1 - 1.3), 0.05, zc + dz2), stop_m)
			_box(_vis, Vector3(0.19, 0.02, 0.12), Vector3(side * (bx1 - 1.3), 0.1, zc + dz2 + 0.2), yellow_m)
		_label("%02d" % (i + 1), 120, 0.006, Color(0.93, 0.92, 0.88), Vector3(side * (ax + 0.75), 0.02, zc),
			Vector3(-PI * 0.5, PI * 0.5 if side > 0.0 else -PI * 0.5, 0.0))
		_label("%02d" % (i + 1), 96, 0.005, Color(0.95, 0.95, 0.95), Vector3(side * (W * 0.5 - 0.02), 3.3, zc),
			Vector3(0.0, -PI * 0.5 if side > 0.0 else PI * 0.5, 0.0))
		_box(_vis, Vector3(0.05, 0.08, BAY_W - 0.5), Vector3(side * (W * 0.5 - 0.03), 2.75, zc), led_m)
		_box(_vis, Vector3(0.06, 1.5, BAY_W - 0.9), Vector3(side * (W * 0.5 - 0.04), 1.75, zc), panel_m)
		var pl := _label("", 64, 0.004, Color(0.85, 0.72, 0.45), Vector3(side * (W * 0.5 - 0.08), 2.35, zc),
			Vector3(0.0, -PI * 0.5 if side > 0.0 else PI * 0.5, 0.0))
		_plaques.append(pl)
		# ceiling fitting over each bay
		_box(_vis, Vector3(1.4, 0.06, 0.22), Vector3(xf.origin.x, H - 0.7, zc), steel_m)
		_box(_vis, Vector3(1.3, 0.02, 0.16), Vector3(xf.origin.x, H - 0.735, zc), warm_m)
		var pool := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(BAY_D * 0.9, BAY_W * 0.8)
		pool.mesh = pm
		pool.material_override = pool_m
		pool.position = Vector3(xf.origin.x, 0.016, zc)
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(pool)
		if i % 2 == 0:
			for sx: float in [-1.0, 1.0]:
				var cz := zc - BAY_W * 0.5
				_box(_vis, Vector3(0.55, H, 0.55), Vector3(sx * (bx1 + 0.05), H * 0.5, cz), wall_m, true)
				_box(_vis, Vector3(0.57, 1.0, 0.57), Vector3(sx * (bx1 + 0.05), 0.5, cz), yellow_m)
				_box(_vis, Vector3(0.58, 0.12, 0.58), Vector3(sx * (bx1 + 0.05), 1.06, cz), sign_m)
	# ---- the aisle: two LED lines, painted arrows and EXIT signs to the ramp
	for lx: float in [-1.8, 1.8]:
		_box(_vis, Vector3(0.12, 0.05, L - LOBBY - 0.6), Vector3(lx, H - 0.6, (L + LOBBY) * 0.5), led_m)
	var az := LOBBY + 3.0
	while az < L - 2.0:
		_arrow(Vector3(0, 0.01, az), line_m)
		az += 9.0
	for sz: float in [LOBBY + row_len() * 0.5, L - 1.0]:
		_box(_vis, Vector3(2.6, 0.5, 0.08), Vector3(0, H - 1.05, sz), sign_m)
		_box(_vis, Vector3(2.5, 0.42, 0.01), Vector3(0, H - 1.05, sz - 0.045), exit_m)
		_label("WAY OUT  ↑", 56, 0.0055, Color(1, 1, 1), Vector3(0, H - 1.05, sz - 0.07), Vector3(0, PI, 0), 6)
		_box(_vis, Vector3(0.03, 0.4, 0.03), Vector3(-1.1, H - 0.6, sz), steel_m)
		_box(_vis, Vector3(0.03, 0.4, 0.03), Vector3(1.1, H - 0.6, sz), steel_m)
	_label("5", 160, 0.006, Color(0.95, 0.95, 0.95), Vector3(2.2, 0.012, LOBBY + 1.6), Vector3(-PI * 0.5, PI, 0.0))
	# ---- the exit ramp: a gentle 9° climb, kerbs with LED lines, chevrons,
	# warm lights getting brighter, the shutter, daylight beyond
	var ang := atan2(RAMP_RISE, RAMP_LEN)
	var slope := RAMP_LEN / cos(ang)
	var rc := Vector3(0, RAMP_RISE * 0.5 - 0.1, L + RAMP_LEN * 0.5)
	_box(_vis, Vector3(RAMP_W + 1.0, 0.2, slope), rc, aisle_m, true, -ang)
	# a short level landing at the top (the shutter sits on it)
	_box(_vis, Vector3(RAMP_W + 1.0, 0.2, 6.0), Vector3(0, RAMP_RISE - 0.1, ramp_end() + 3.0), aisle_m, true)
	for k in int(slope / 2.2):
		var t := (k + 0.5) * 2.2
		var p := Vector3(0, 0.0, L) + Vector3(0, sin(ang), cos(ang)) * t + Vector3(0, 0.012, 0)
		_chevron(p, -ang, yellow_m)
	for sx: float in [-1.0, 1.0]:
		var kx := sx * (RAMP_W * 0.5 + 0.25)
		_box(_vis, Vector3(0.5, 0.15, slope), rc + Vector3(kx, 0.17, 0), _mat(Color(0.62, 0.62, 0.6), 0.8), false, -ang)
		_box(_vis, Vector3(0.06, 0.04, slope), rc + Vector3(sx * (RAMP_W * 0.5 + 0.02), 0.27, 0), led_m, false, -ang)
		_box(_vis, Vector3(0.3, H + RAMP_RISE + 0.6, RAMP_LEN + 6.0), Vector3(sx * (RAMP_W * 0.5 + 0.65), (H + RAMP_RISE) * 0.5, L + (RAMP_LEN + 6.0) * 0.5), wall_m, true)
	# ceiling over the ramp follows it up (stepped slabs)
	for k in 7:
		var z0 := L + k * (RAMP_LEN + 6.0) / 7.0
		var y0 := minf(RAMP_RISE, (z0 - L) * tan(ang)) + H + 0.2
		_box(_vis, Vector3(RAMP_W + 1.6, 0.3, (RAMP_LEN + 6.0) / 7.0 + 0.05), Vector3(0, y0 + 0.15, z0 + (RAMP_LEN + 6.0) / 14.0), ceil_m, true)
		_box(_vis, Vector3(0.6, 0.04, 1.2), Vector3(0, y0 - 0.02, z0 + (RAMP_LEN + 6.0) / 14.0), warm_m)
	_box(_vis, Vector3(RAMP_W + 1.6, 0.5, 0.1), Vector3(0, H + 0.1, L + 0.4), sign_m)
	_label("WAY OUT  ·  STREET", 60, 0.0055, Color(1.0, 0.95, 0.85), Vector3(0, H + 0.1, L + 0.34), Vector3(0, PI, 0), 0)
	_label("WAY OUT  ·  STREET", 60, 0.0055, Color(1.0, 0.95, 0.85), Vector3(0, H + 0.1, L + 0.46), Vector3.ZERO, 0)
	# the shutter and the daylight past it
	_shutter = Node3D.new()
	_shutter.position = Vector3.ZERO
	_vis.add_child(_shutter)
	var sh_mi := MeshInstance3D.new()
	var sbm := BoxMesh.new()
	sbm.size = Vector3(RAMP_W + 0.8, 3.8, 0.12)
	sh_mi.mesh = sbm
	sh_mi.material_override = _mat(Color(0.5, 0.52, 0.55), 0.45, 0.8)
	sh_mi.position = Vector3(0, RAMP_RISE + 1.9, ramp_end() + 1.0)
	_shutter.add_child(sh_mi)
	_box(_vis, Vector3(RAMP_W + 1.2, 6.0, 0.1), Vector3(0, RAMP_RISE + 3.0, ramp_end() + 6.0), day_m, true)
	_flush_batches()
	_set_lights(L)
	# An interior: no street mist down here, the room's own light (InteriorKit).
	var zone := InteriorKit.add_lighting_zone(_vis, AABB(Vector3(-W * 0.5, -0.5, -2.5), Vector3(W, H + RAMP_RISE + 2.0, L + RAMP_LEN + 9.0)))
	InteriorKit.room_probe(zone, Color(0.96, 0.97, 1.0), 0.75, 0.5)
	_set_visible(inside)


func _set_lights(L: float) -> void:
	# A few soft omnis for the showroom look (mobile: <= 8 per object).
	var k := 0
	var z := LOBBY - 2.0
	while z < L + RAMP_LEN and k < 7:
		var o := OmniLight3D.new()
		var on_ramp := z > L
		o.position = Vector3(0, (H - 0.5) + (RAMP_RISE * clampf((z - L) / RAMP_LEN, 0.0, 1.0) if on_ramp else 0.0), z)
		o.omni_range = 13.0
		o.light_energy = 1.35 if not on_ramp else 1.6
		o.light_color = Color(1.0, 0.95, 0.88)
		o.shadow_enabled = false
		_vis.add_child(o)
		_lights.append(o)
		k += 1
		z += 10.0


func _arrow(at: Vector3, m: Material) -> void:
	# A painted arrow pointing down the aisle (+Z): a shaft and two barbs
	# meeting at the tip.
	var tip := at + Vector3(0, 0, 1.1)
	_box(_vis, Vector3(0.32, 0.012, 2.0), at + Vector3(0, 0, -0.3), m)
	for sd: float in [-1.0, 1.0]:
		var back := Vector3(sd * 0.75, 0.0, -0.75).normalized()
		var centre := tip + back * 0.55
		_box_rot(Vector3(0.28, 0.012, 1.1), centre, Basis.looking_at(back, Vector3.UP), m)


func _chevron(at: Vector3, pitch: float, m: Material) -> void:
	for s: float in [-1.0, 1.0]:
		var b := Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, s * 0.85)
		_box_rot(Vector3(0.25, 0.012, 2.2), at + Basis(Vector3.RIGHT, pitch) * Vector3(s * 0.8, 0, 0), b, m)


## A visual box with any rotation (batched like _box).
func _box_rot(size: Vector3, at: Vector3, basis: Basis, mat: Material) -> void:
	var b: Array = _batches.get(mat, [])
	if b.is_empty():
		b = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
		_batches[mat] = b
	var hs := size * 0.5
	var verts: PackedVector3Array = b[0]
	var norms: PackedVector3Array = b[1]
	var idx: PackedInt32Array = b[2]
	for f in 6:
		var axis := f / 2
		var sg := 1.0 if f % 2 == 0 else -1.0
		var n := Vector3.ZERO
		n[axis] = sg
		var u := Vector3.ZERO
		u[(axis + 1) % 3] = 1.0
		var v := n.cross(u)
		var base := verts.size()
		for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var lp := n * hs[axis] + u * (q.x * hs[(axis + 1) % 3]) + v * (q.y * _half_on(v, hs))
			verts.append(at + basis * lp)
			norms.append(basis * n)
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	b[0] = verts
	b[1] = norms
	b[2] = idx
