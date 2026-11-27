class_name ApartmentElevator
extends Node3D
## The way up to a home, inside its building (apartment overhaul
## 2026-11-25; the old version was a glass shaft and lobby bolted onto the
## outside of the facade, entering through the open window wall):
##   street door (sliding glass, nameplate canopy) in the bottom tier's
##   facade → a residential lobby running back to the lift: reception desk,
##   seating, mailboxes, directory, planters, warm light → the lift (call
##   button, indicator, a car that rides the shaft with you, its doors and the
##   landing doors working together, floor buttons, chime) → the enclosed lift
##   hall on the home's floor → the home's front door (swings open as you
##   reach it) → the apartment. No step of it is a teleport.
## The layout is Apartments.make_core's (the building's collision is
## hollowed out along it); every wall here collides on the human layer.
##
## Local frame: origin on the ground floor at the middle of the lift's door
## line; +Z towards the lobby / hall (the home's window side), +Y up, +X along.
##   z = −SHAFT_D .. 0   the shaft (the car), doors at z = 0 on every floor
##   z = 0 .. lobby_len   the ground lobby, street door at z = lobby_len
##   z = 0 .. HALL_D      the lift hall at y = top_y, front door at z = HALL_D

const LOBBY_H := 3.4
const SHAFT_W := 2.5
const SHAFT_D := Apartments.SHAFT_D
const HALL_D := Apartments.HALL_D
const HALL_H := 2.85
const CAB_W := 2.24
const CAB_D := 1.96
const CAB_H := 2.55
const DOOR_W := 1.48
const DOOR_H := 2.28
const DOOR_SPEED := 2.1       # full open/close in ~0.48 s
const ENTRANCE_SPEED := 1.8
const FRONT_DOOR_W := 1.0

## Tier palettes: [wall, floor, trim/accent, wood/panel, metal]
const TIER_PAL := [
	[Color(0.86, 0.82, 0.76), Color(0.56, 0.44, 0.32), Color(0.28, 0.34, 0.34), Color(0.58, 0.42, 0.26), Color(0.66, 0.68, 0.70)],
	[Color(0.92, 0.91, 0.88), Color(0.76, 0.64, 0.48), Color(0.22, 0.28, 0.34), Color(0.68, 0.54, 0.38), Color(0.74, 0.76, 0.78)],
	[Color(0.46, 0.45, 0.44), Color(0.36, 0.36, 0.37), Color(0.14, 0.15, 0.16), Color(0.38, 0.26, 0.18), Color(0.22, 0.23, 0.25)],
	[Color(0.86, 0.84, 0.80), Color(0.82, 0.80, 0.76), Color(0.26, 0.18, 0.12), Color(0.32, 0.20, 0.12), Color(0.78, 0.64, 0.36)],
	[Color(0.24, 0.23, 0.22), Color(0.18, 0.18, 0.19), Color(0.78, 0.62, 0.32), Color(0.22, 0.15, 0.10), Color(0.82, 0.66, 0.34)],
]

var home_id := ""
var home_name := ""
var tier := 0
var top_y := 16.0          # the home's floor above the lobby floor
var top_floor_num := 5
var top_floor_label := "F05"
var lobby_len := 8.0       # door line to the street door
var lobby_hw := 2.6
var street_drop := 0.0     # lobby floor above the pavement outside the door
var room_h := 3.2          # the home's floor-to-ceiling (the core is clad up to it)

## State machine: "idle_g" | "idle_top" | "closing" | "moving" | "opening"
## | "trip" (a sealed ride past floors that aren't here: the Vehicle
## Collection levels) | "sealed" (doors shut, the rider has been carried on)
## | "arriving" (doors shut, about to open).
var state := "idle_g"
## A garage stop (2026-11-27): this lift's only landing is the Vehicle
## Collection's; its trip() carries you on to the apartment lift's cabin.
var garage_stop := false
## A sealed trip: floor labels to pass, then done() (the rider is carried on).
var _trip_labels: Array = []
var _trip_t := 0.0
var _trip_dur := 0.0
var _trip_done := Callable()
var _trip_pending := false
var _trip_after_ride := false
var _arrive_t := 0.0
## 0..1 while the cabin is travelling with you aboard (the camera's rumble).
var ride_rumble := 0.0
var at_top := false
var target_top := false
var cabin_y := 0.0
var _ride_t := 0.0
var _ride_dur := 3.2
var _ride_y0 := 0.0
var _ride_y1 := 0.0
var _player_riding := false
var _last_disp_floor := 0
var _hum_cd := 0.0
var _auto_close_t := 0.0

## Door open fractions (0 = closed, 1 = open)
var _ent_open := 0.0
var _g_door_open := 0.0
var _top_door_open := 0.0

## Scene nodes for animation & indicators
var _ent_l: Node3D
var _ent_r: Node3D
var _ent_col: StaticBody3D
var _g_door_l: Node3D
var _g_door_r: Node3D
var _g_door_col: StaticBody3D
var _top_door_l: Node3D
var _top_door_r: Node3D
var _top_door_col: StaticBody3D
var _cabin: Node3D
var _cab_front_l: Node3D
var _cab_front_r: Node3D
var _cab_back_l: Node3D
var _cab_back_r: Node3D
var _front_door: Node3D
var _front_door_col: StaticBody3D
var _front_open := 0.0
var _cab_door_col_f: CollisionShape3D
var _cab_door_col_b: CollisionShape3D
var _ind_ground: Label3D
var _ind_top: Label3D
var _ind_cabin: Label3D
var _btn_g_mat: StandardMaterial3D
var _btn_top_mat: StandardMaterial3D
var _call_g_mat: StandardMaterial3D
var _call_top_mat: StandardMaterial3D
var _lobby_light: OmniLight3D
var _porch_light: OmniLight3D
var _lobby_light2: OmniLight3D
var _cabin_light: OmniLight3D


static func build(home: Dictionary, ground_y: float) -> ApartmentElevator:
	var el := ApartmentElevator.new()
	el._init_from_home(home, ground_y)
	return el


func _init_from_home(home: Dictionary, ground_y: float) -> void:
	var h: Dictionary = home["h"]
	var core: Dictionary = h["core"]
	home_id = String(home["id"])
	home_name = String(home["name"])
	tier = clampi(int(home["tier"]), 0, 4)
	name = "Elevator_" + home_id
	var base: float = core["base"]
	var origin := Apartments.face_point(h, core["a_c"], core["o_door"], base)
	var out := Apartments.outward(h)
	var along := Apartments.along_dir(h)
	if along.cross(Vector3.UP).dot(out) < 0.0:
		along = -along
	top_y = float(h["y0"]) - base
	room_h = float(h["y1"]) - float(h["y0"])
	lobby_len = float(core["o_face0"]) - float(core["o_door"])
	lobby_hw = float(core["lobby_hw"])
	street_drop = maxf(0.0, base - ground_y) if not is_nan(ground_y) else 0.0
	top_floor_num = maxi(int(round(top_y / Apartments.FLOOR)), 1)
	top_floor_label = "PH" if tier >= 4 else ("F%02d" % top_floor_num)
	var pt := Apartments.portal(h)
	_ent_hw = minf(float(pt[0]), lobby_hw - 0.15)
	_ent_h = minf(float(pt[1]), LOBBY_H - 0.25)
	_recess = clampf(float(pt[2]), 0.0, maxf(0.0, lobby_len - 5.0))
	_door_z = lobby_len - _recess
	transform = Transform3D(Basis(along, Vector3.UP, out), origin)
	_build_geometry()
	_sync_doors()
	_update_indicators("G")


## The street door, on the pavement (compatible with home_lift()).
func street_door_world() -> Vector3:
	return to_global(Vector3(0.0, -street_drop, lobby_len + 0.8 + (0.32 * clampi(ceili(street_drop / 0.16), 1, 8) if street_drop > 0.04 else 0.0)))


func ground_call_world() -> Vector3:
	return to_global(Vector3(0.0, 0.0, 0.75))


func upper_call_world() -> Vector3:
	return to_global(Vector3(0.0, top_y, 0.75))


func cabin_panel_world() -> Vector3:
	return to_global(Vector3(CAB_W * 0.42, cabin_y, -SHAFT_D * 0.5))


func cabin_center_world() -> Vector3:
	return to_global(Vector3(0.0, cabin_y + 0.95, -SHAFT_D * 0.5))


## Where the home's front door is (the hall side), world.
func front_door_world() -> Vector3:
	return to_global(Vector3(0.0, top_y, HALL_D))


func is_inside_cabin(world_pos: Vector3) -> bool:
	var lp := to_local(world_pos)
	return absf(lp.x) < CAB_W * 0.49 and lp.z < -0.05 and lp.z > -SHAFT_D + 0.05 and absf(lp.y - (cabin_y + 0.95)) < 1.35


func is_inside_lobby(world_pos: Vector3) -> bool:
	var lp := to_local(world_pos)
	if absf(lp.x) < lobby_hw + 0.1 and lp.z > -0.1 and lp.z < _door_z + 0.1 and lp.y > -0.3 and lp.y < LOBBY_H:
		return true
	if absf(lp.x) < Apartments.HALL_HW + 0.1 and lp.z > -0.1 and lp.z < HALL_D + 0.1 and absf(lp.y - (top_y + 0.95)) < 1.8:
		return true
	return is_inside_cabin(world_pos)


func is_riding() -> bool:
	return _player_riding and state in ["closing", "moving", "opening", "trip", "arriving"]


## Request the elevator to arrive at `to_top` (called from lobby or upper landing).
func call_to(to_top: bool) -> void:
	if state == "moving" or state == "closing":
		return
	if at_top == to_top:
		if state != "opening":
			_start_open()
		return
	target_top = to_top
	_player_riding = false
	_start_close()


## Press the floor button from inside the cabin (with player aboard).
func ride_to(to_top: bool) -> void:
	if state == "moving" or state == "closing":
		return
	if at_top == to_top:
		_start_open()
		return
	Sfx.play("click", -4.0)
	target_top = to_top
	_player_riding = true
	_set_button_lit(to_top)
	_start_close()


## Instant arrival helper used only by automated `--autoplay` smoke tests.
func snap_to_top(player: Node3D) -> void:
	at_top = true
	target_top = true
	cabin_y = top_y
	state = "idle_top"
	_player_riding = false
	_g_door_open = 0.0
	_top_door_open = 1.0
	_cabin.position.y = cabin_y
	_sync_doors()
	_update_indicators(top_floor_label)


## A sealed ride past floors this shaft doesn't show (the Vehicle
## Collection's levels below the lobby): the doors close, the cabin rides to
## the lobby first if it's up, then hums past `labels` (the indicator counts
## them, the car shudders), and done() carries the rider on – to the other
## end's cabin, which is identical inside, so the cut can't be seen.
func trip(labels: Array, done: Callable) -> void:
	if state in ["moving", "closing", "trip", "sealed"]:
		return
	_trip_labels = labels
	_trip_done = done
	_player_riding = true
	_set_button_lit(false, true)
	Sfx.play("click", -4.0)
	if at_top:
		target_top = false
		_trip_after_ride = true
		_start_close()
		return
	_trip_after_ride = false
	_trip_pending = true
	_start_close()


func _start_trip() -> void:
	_trip_pending = false
	state = "trip"
	_last_disp_floor = -99
	_trip_t = 0.0
	_trip_dur = 1.3 + 1.05 * float(_trip_labels.size())
	_hum_cd = 0.0
	Sfx.play("elev_hum", -12.0)


## The far end of a trip: the cabin is here, doors shut, the rider inside;
## after a beat the doors open (or it rides on up, `then_top`).
func arrive_sealed(to_top: bool, label: String, then_top := false) -> void:
	at_top = to_top
	target_top = to_top
	cabin_y = top_y if to_top else 0.0
	if _cabin:
		_cabin.position.y = cabin_y
	_g_door_open = 0.0
	_top_door_open = 0.0
	_sync_doors()
	_update_indicators(label)
	_player_riding = true
	if then_top and not to_top:
		state = "idle_g"
		ride_to(true)
		return
	state = "arriving"
	_arrive_t = 0.55


## After a trip carried the rider away: this end goes back to rest, shut.
func settle_closed() -> void:
	_player_riding = false
	ride_rumble = 0.0
	state = "idle_top" if at_top else "idle_g"
	_update_indicators(top_floor_label if at_top else "G")


## The cabin's frame (riders are carried between ends in it).
func cabin_xf() -> Transform3D:
	return _cabin.global_transform if _cabin else global_transform


func _start_close() -> void:
	if _g_door_open > 0.05 or _top_door_open > 0.05:
		Sfx.play("elev_door", -9.0)
	state = "closing"


func _start_move() -> void:
	state = "moving"
	_ride_y0 = cabin_y
	_ride_y1 = top_y if target_top else 0.0
	var dist := absf(_ride_y1 - _ride_y0)
	_ride_dur = clampf(1.8 + dist * 0.055, 2.2, 5.2)
	_ride_t = 0.0
	_hum_cd = 0.0
	_last_disp_floor = int(round(cabin_y / Apartments.FLOOR))
	if _player_riding:
		Sfx.play("elev_hum", -12.0)


func _start_open() -> void:
	state = "opening"
	_auto_close_t = 8.0
	Sfx.play("chime", -7.0)
	Sfx.play("elev_door", -9.0)
	_set_button_lit(false, true)


## Called every frame from EmpireGame._process() with player and ownership status.
func tick(dt: float, player: Node3D, owns: bool) -> void:
	if player == null:
		return
	var p_world := player.global_position
	var dist_sq := p_world.distance_squared_to(to_global(Vector3(0.0, cabin_y + 1.0, -SHAFT_D * 0.5)))
	var near := dist_sq < 65.0 * 65.0 or p_world.distance_squared_to(global_position) < 65.0 * 65.0
	if _lobby_light:
		_lobby_light.visible = near
	if _porch_light:
		_porch_light.visible = near
	if _lobby_light2:
		_lobby_light2.visible = near
	if _cabin_light:
		_cabin_light.visible = near
	if not near and state in ["idle_g", "idle_top", "sealed"]:
		return
	ride_rumble = move_toward(ride_rumble, 1.0 if _player_riding and state in ["moving", "trip"] else 0.0, dt * 2.5)
	var lp := to_local(p_world)
	# 1. Ground entrance sliding glass doors open smoothly on approach.
	var ent_near := not garage_stop and absf(lp.x) < _ent_hw + 1.0 and lp.z > _door_z - 2.4 and lp.z < lobby_len + 3.4 and lp.y > -street_drop - 1.0 and lp.y < 3.0
	var ent_target := 1.0 if ent_near else 0.0
	if absf(_ent_open - ent_target) > 0.005:
		var was_closed := _ent_open < 0.05 and ent_target > 0.5
		_ent_open = move_toward(_ent_open, ent_target, dt * ENTRANCE_SPEED)
		if was_closed:
			Sfx.play("elev_door", -14.0, 1.15)
		_sync_entrance_doors()
	# 2. Auto-open elevator doors when the owner walks up to the waiting cabin!
	if owns and state == "idle_g" and not at_top:
		var at_g_bay := absf(lp.x) < 1.6 and lp.z > -0.1 and lp.z < 2.4 and absf(lp.y) < 2.6
		var in_cab := is_inside_cabin(p_world)
		if (at_g_bay or in_cab) and _g_door_open < 0.99:
			if _g_door_open < 0.05:
				Sfx.play("elev_door", -11.0)
			_g_door_open = move_toward(_g_door_open, 1.0, dt * DOOR_SPEED)
			_auto_close_t = 6.0
			_sync_doors()
		elif not at_g_bay and not in_cab and _g_door_open > 0.0:
			_auto_close_t -= dt
			if _auto_close_t <= 0.0:
				_g_door_open = move_toward(_g_door_open, 0.0, dt * DOOR_SPEED)
				_sync_doors()
	elif owns and state == "idle_top" and at_top:
		var at_t_bay := absf(lp.x) < 1.6 and lp.z > -0.1 and lp.z < HALL_D + 0.4 and absf(lp.y - top_y) < 2.6
		var in_cab := is_inside_cabin(p_world)
		if (at_t_bay or in_cab) and _top_door_open < 0.99:
			if _top_door_open < 0.05:
				Sfx.play("elev_door", -11.0)
			_top_door_open = move_toward(_top_door_open, 1.0, dt * DOOR_SPEED)
			_auto_close_t = 6.0
			_sync_doors()
		elif not at_t_bay and not in_cab and _top_door_open > 0.0:
			_auto_close_t -= dt
			if _auto_close_t <= 0.0:
				_top_door_open = move_toward(_top_door_open, 0.0, dt * DOOR_SPEED)
				_sync_doors()
	# 2b. The home's front door (hall side): swings open as you reach it
	# from either side, if it's yours.
	var fd_near := owns and not garage_stop and absf(lp.x) < 1.4 and lp.z > HALL_D - 1.6 and lp.z < HALL_D + 1.8 and absf(lp.y - top_y) < 2.4
	var fd_target := 1.0 if fd_near else 0.0
	if absf(_front_open - fd_target) > 0.004:
		if _front_open < 0.04 and fd_target > 0.5:
			Sfx.play("click", -12.0, 0.7)
		_front_open = move_toward(_front_open, fd_target, dt * 2.2)
		if _front_door:
			_front_door.rotation.y = -_front_open * deg_to_rad(96.0)
		if _front_door_col:
			_front_door_col.collision_layer = 0 if _front_open > 0.4 else CityWorld.HUMAN_LAYER
	# 3. Elevator state machine (closing -> moving -> opening).
	match state:
		"closing":
			_g_door_open = move_toward(_g_door_open, 0.0, dt * DOOR_SPEED)
			_top_door_open = move_toward(_top_door_open, 0.0, dt * DOOR_SPEED)
			_sync_doors()
			if _g_door_open <= 0.001 and _top_door_open <= 0.001:
				if _trip_pending:
					_start_trip()
				else:
					_start_move()
		"moving":
			var prev_y := cabin_y
			_ride_t = minf(_ride_t + dt, _ride_dur)
			var u := _ride_t / maxf(_ride_dur, 0.01)
			# Smooth S-curve (ease-in, steady cruise, gentle ease-out).
			var ease_u := u * u * (3.0 - 2.0 * u)
			cabin_y = lerpf(_ride_y0, _ride_y1, ease_u)
			_cabin.position.y = cabin_y
			var dy := cabin_y - prev_y
			# Carry player smoothly inside the cabin with zero teleport!
			if _player_riding:
				var p_new := player.global_position + Vector3(0.0, dy, 0.0)
				# Clamp gently inside cabin walls while riding so player never clips out.
				var pl := to_local(p_new)
				pl.x = clampf(pl.x, -CAB_W * 0.36, CAB_W * 0.36)
				pl.z = clampf(pl.z, -SHAFT_D + 0.32, -0.32)
				pl.y = cabin_y + 0.95
				var wp := to_global(pl)
				player.global_position = wp
				if player.get("s") != null:
					player.s.position = wp
					player.s.velocity = Vector3(0.0, dy / maxf(dt, 1e-4), 0.0)
				_hum_cd -= dt
				if _hum_cd <= 0.0 and _ride_t < _ride_dur - 0.5:
					_hum_cd = 0.85
					Sfx.play("elev_hum", -14.0)
			var fl := int(round(cabin_y / Apartments.FLOOR))
			if fl != _last_disp_floor:
				_last_disp_floor = fl
				var lbl := "G" if fl <= 0 else (top_floor_label if fl >= top_floor_num else ("F%02d" % fl))
				_update_indicators(lbl)
				if _player_riding:
					Sfx.play("elev_tick", -15.0)
			if _ride_t >= _ride_dur:
				at_top = target_top
				cabin_y = top_y if at_top else 0.0
				_cabin.position.y = cabin_y
				_update_indicators(top_floor_label if at_top else "G")
				if _trip_after_ride:
					_trip_after_ride = false
					_start_trip()
				else:
					_start_open()
		"opening":
			if at_top:
				_top_door_open = move_toward(_top_door_open, 1.0, dt * DOOR_SPEED)
			else:
				_g_door_open = move_toward(_g_door_open, 1.0, dt * DOOR_SPEED)
			_sync_doors()
			var done := (_top_door_open >= 0.999) if at_top else (_g_door_open >= 0.999)
			if done:
				state = "idle_top" if at_top else "idle_g"
				_player_riding = false
		"arriving":
			_arrive_t -= dt
			if _arrive_t <= 0.0:
				_start_open()
		"trip":
			_trip_t = minf(_trip_t + dt, _trip_dur)
			var n := _trip_labels.size()
			# (a beat to pull away, the floors, a beat to settle)
			var k := clampi(int(floor((_trip_t - 0.65) / maxf(_trip_dur - 1.3, 0.01) * n)), -1, n - 1)
			if k >= 0 and k != _last_disp_floor:
				_last_disp_floor = k
				_update_indicators(String(_trip_labels[k]))
				Sfx.play("elev_tick", -15.0)
			_hum_cd -= dt
			if _hum_cd <= 0.0 and _trip_t < _trip_dur - 0.5:
				_hum_cd = 0.85
				Sfx.play("elev_hum", -14.0)
			if _trip_t >= _trip_dur:
				state = "sealed"
				_last_disp_floor = -99
				if _trip_done.is_valid():
					_trip_done.call()


func _update_indicators(text: String) -> void:
	var arrow := ""
	if state == "moving":
		arrow = " ▲" if target_top else " ▼"
	elif state == "trip":
		arrow = " ▼" if not garage_stop else " ▲"
	var full := text + arrow
	if _ind_ground:
		_ind_ground.text = full
	if _ind_top:
		_ind_top.text = full
	if _ind_cabin:
		_ind_cabin.text = full


func _set_button_lit(top_selected: bool, clear_all := false) -> void:
	var off := Color(0.28, 0.30, 0.34)
	var on := Color(1.0, 0.78, 0.25)
	if _btn_g_mat:
		var lit_g := (not clear_all) and (not top_selected)
		_btn_g_mat.albedo_color = on if lit_g else off
		_btn_g_mat.emission = on if lit_g else Color(0.18, 0.20, 0.24)
		_btn_g_mat.emission_energy_multiplier = 2.4 if lit_g else 0.4
	if _btn_top_mat:
		var lit_t := (not clear_all) and top_selected
		_btn_top_mat.albedo_color = on if lit_t else off
		_btn_top_mat.emission = on if lit_t else Color(0.18, 0.20, 0.24)
		_btn_top_mat.emission_energy_multiplier = 2.4 if lit_t else 0.4
	if _call_g_mat:
		var cg := (not clear_all) and (not top_selected) and not _player_riding
		_call_g_mat.emission_energy_multiplier = 2.2 if cg else 0.7
	if _call_top_mat:
		var ct := (not clear_all) and top_selected and not _player_riding
		_call_top_mat.emission_energy_multiplier = 2.2 if ct else 0.7


func _sync_entrance_doors() -> void:
	# Both leaves swing in on their jamb pivots (eased), 0 → 92°.
	var e := _ent_open * _ent_open * (3.0 - 2.0 * _ent_open)
	if _ent_l:
		_ent_l.rotation.y = e * deg_to_rad(92.0)
	if _ent_r:
		_ent_r.rotation.y = -e * deg_to_rad(92.0)
	if _ent_col:
		_ent_col.collision_layer = 0 if _ent_open > 0.55 else CityWorld.HUMAN_LAYER


func _sync_doors() -> void:
	var gs := _g_door_open * (DOOR_W * 0.48)
	if _g_door_l:
		_g_door_l.position.x = -DOOR_W * 0.25 - gs
	if _g_door_r:
		_g_door_r.position.x = DOOR_W * 0.25 + gs
	if _g_door_col:
		_g_door_col.collision_layer = 0 if _g_door_open > 0.72 else CityWorld.HUMAN_LAYER
	var ts := _top_door_open * (DOOR_W * 0.48)
	if _top_door_l:
		_top_door_l.position.x = -DOOR_W * 0.25 - ts
	if _top_door_r:
		_top_door_r.position.x = DOOR_W * 0.25 + ts
	if _top_door_col:
		_top_door_col.collision_layer = 0 if _top_door_open > 0.72 else CityWorld.HUMAN_LAYER
	# Cabin doors mirror whichever landing door is currently open.
	var cf := (_top_door_open if at_top else _g_door_open) if state != "moving" else 0.0
	var cb := 0.0
	var cfs := cf * (DOOR_W * 0.46)
	var cbs := cb * (DOOR_W * 0.46)
	if _cab_front_l:
		_cab_front_l.position.x = -DOOR_W * 0.25 - cfs
	if _cab_front_r:
		_cab_front_r.position.x = DOOR_W * 0.25 + cfs
	if _cab_back_l:
		_cab_back_l.position.x = -DOOR_W * 0.25 - cbs
	if _cab_back_r:
		_cab_back_r.position.x = DOOR_W * 0.25 + cbs
	if _cab_door_col_f:
		_cab_door_col_f.disabled = cf > 0.72
	if _cab_door_col_b:
		_cab_door_col_b.disabled = cb > 0.72


# ---------------------------------------------------------------- geometry
## Finishes by tier (2026-11-27 entrance pass): what the street portal, the
## lobby's feature wall and the lift surrounds are made of.
##   [portal stone, portal metal (frames, letters), canopy, feature wall,
##    lift surround, door frame metal]
const TIER_FINISH := [
	[Color(0.62, 0.6, 0.57), Color(0.2, 0.21, 0.23), Color(0.24, 0.25, 0.27), Color(0.7, 0.66, 0.6), Color(0.56, 0.55, 0.53), Color(0.22, 0.23, 0.25)],
	[Color(0.84, 0.8, 0.72), Color(0.62, 0.64, 0.66), Color(0.3, 0.32, 0.35), Color(0.62, 0.48, 0.34), Color(0.78, 0.76, 0.72), Color(0.6, 0.62, 0.64)],
	[Color(0.2, 0.2, 0.21), Color(0.09, 0.09, 0.1), Color(0.1, 0.1, 0.11), Color(0.36, 0.25, 0.17), Color(0.16, 0.16, 0.17), Color(0.08, 0.08, 0.09)],
	[Color(0.9, 0.87, 0.8), Color(0.55, 0.42, 0.26), Color(0.88, 0.85, 0.78), Color(0.3, 0.2, 0.13), Color(0.84, 0.8, 0.72), Color(0.5, 0.38, 0.22)],
	[Color(0.1, 0.1, 0.11), Color(0.78, 0.62, 0.34), Color(0.12, 0.12, 0.13), Color(0.18, 0.13, 0.09), Color(0.08, 0.08, 0.09), Color(0.74, 0.58, 0.32)],
]
## The lift portal on every landing (lobby, home floor, garage): the
## opening's half width and height in its wall (the wall is built round it).
const PORTAL_HW := 1.3
const PORTAL_H := 2.95
const LANDING_Z := -0.1     # the landing doors sit back in the wall's reveal

var _ent_hw := 1.15
var _ent_h := 2.7
var _recess := 0.7
var _door_z := 8.0          # the street doors' line (lobby_len − recess)
var _arch: BuildingMesher
var _glass_m: BuildingMesher
var _glow_m: BuildingMesher
var _col_boxes: Array[AABB] = []


func _bx(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, c: Color, solid := false) -> void:
	_arch.solid(minf(x0, x1), minf(z0, z1), maxf(x0, x1), maxf(z0, z1), minf(y0, y1), maxf(y0, y1), c)
	if solid:
		_col_boxes.append(AABB(Vector3(minf(x0, x1), minf(y0, y1), minf(z0, z1)), Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))))


func _gl(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, c: Color) -> void:
	_glow_m.solid(minf(x0, x1), minf(z0, z1), maxf(x0, x1), maxf(z0, z1), minf(y0, y1), maxf(y0, y1), c)


func _begin_meshes() -> void:
	_arch = BuildingMesher.new()
	_arch._begin({"style": 0})
	_glass_m = BuildingMesher.new()
	_glass_m._begin({"style": 0})
	_glow_m = BuildingMesher.new()
	_glow_m._begin({"style": 0})
	_col_boxes.clear()


func _end_meshes(vis_end: float) -> void:
	_arch._end()
	_glass_m._end()
	_glow_m._end()
	_add_mesh("Architecture", _arch.arrays(), _mat_vcol(0.5, 0.08), vis_end)
	_add_mesh("Glass", _glass_m.arrays(), _mat_glass(), vis_end - 40.0, false)
	_add_mesh("Glow", _glow_m.arrays(), _mat_glow(), vis_end - 40.0, false)
	var body := StaticBody3D.new()
	body.name = "CoreCollision"
	body.collision_layer = CityWorld.HUMAN_LAYER | 1
	body.collision_mask = 0
	for bx in _col_boxes:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = bx.size
		cs.shape = sh
		cs.position = bx.position + bx.size * 0.5
		body.add_child(cs)
	add_child(body)
	_arch = null
	_glass_m = null
	_glow_m = null


func _build_geometry() -> void:
	var pal: Array = TIER_PAL[tier]
	var fin: Array = TIER_FINISH[tier]
	_begin_meshes()
	_build_entrance(pal, fin)
	_build_lobby(pal, fin)
	_build_shaft(pal, top_y + HALL_H + 0.6)
	_build_hall(pal, fin)
	_end_meshes(260.0)
	_build_entrance_doors(fin)
	_build_landing_doors(pal, top_y)
	_build_front_door(pal)
	_build_cabin(pal[3], pal[1], pal[4], pal[2])
	_build_lights()


## The street entrance: a portal proud of the facade (stone or metal by
## tier), a canopy with the building's name, sconces, an intercom, and the
## glass double doors set back in a lined, lit recess. Nothing of the
## facade crosses it (BuildingMesher keeps its door_zone clear).
func _build_entrance(pal: Array, fin: Array) -> void:
	var c_stone: Color = fin[0]
	var c_metal: Color = fin[1]
	var c_canopy: Color = fin[2]
	var c_floor: Color = pal[1]
	var L := lobby_len
	var ehw := _ent_hw
	var eh := _ent_h
	var dz := _door_z
	var T := 0.15
	# The recess: lined reveals, a soffit with downlights, a stone floor
	# running out to the pavement.
	for sx: float in [-1.0, 1.0]:
		_bx(sx * ehw, sx * (ehw + T), dz, L + 0.02, 0.0, eh, c_stone, true)
	_bx(-ehw - T, ehw + T, dz, L + 0.02, eh, eh + 0.12, c_stone.darkened(0.08), true)
	for k in 2:
		var lz := lerpf(dz + 0.3, L - 0.25, float(k) / 1.0) if L - dz > 0.8 else (dz + L) * 0.5
		_gl(-0.12, 0.12, lz - 0.12, lz + 0.12, eh - 0.015, eh, Color(1.0, 0.88, 0.66))
	_bx(-ehw, ehw, dz - 0.05, L + 0.35, -0.04, 0.025, c_stone.darkened(0.25), true)
	# Front wall inside the facade round the doors (the lobby's street end).
	var hw := lobby_hw
	var fz := minf(dz, L - 0.03)   # (never in the facade's plane)
	_bx(-hw - T, -ehw, fz - T, fz, 0.0, LOBBY_H, pal[0], true)
	_bx(ehw, hw + T, fz - T, fz, 0.0, LOBBY_H, pal[0], true)
	_bx(-ehw, ehw, fz - T, fz, eh, LOBBY_H, pal[0], true)
	if L - dz > 0.05:
		# (behind the facade either side of the recess: the lobby's front
		# corners, so the recess never looks into the wall's thickness)
		# (kept 3 cm behind the facade plane: flush, they z-fought the
		# building's wall and showed as white panels round the door)
		for sx: float in [-1.0, 1.0]:
			_bx(sx * (ehw + T), sx * (hw + T), dz, L - 0.03, 0.0, LOBBY_H, pal[0], true)
		_bx(-hw - T, hw + T, dz, L - 0.03, LOBBY_H, LOBBY_H + 0.1, pal[0])
	# The door frame: metal jambs, head and a transom bar; the transom glass.
	var fw := 0.07
	for sx: float in [-1.0, 1.0]:
		_bx(sx * (ehw - fw), sx * ehw, dz - 0.04, dz + 0.08, 0.0, eh, c_metal)
	_bx(-ehw, ehw, dz - 0.04, dz + 0.08, eh - fw, eh, c_metal)
	var door_h := minf(eh - 0.45, 2.45)
	_bx(-ehw, ehw, dz - 0.04, dz + 0.08, door_h, door_h + 0.06, c_metal)
	_glass_m.solid(-ehw + fw, dz + 0.01, ehw - fw, dz + 0.03, door_h + 0.06, eh - fw, Color(0.7, 0.8, 0.86))
	# Outside: the portal surround proud of the facade.
	var po := 0.22 + 0.06 * tier                # projection
	var pw := 0.34 + 0.06 * tier                # pilaster width
	var ph := eh + 0.5 + 0.08 * tier            # lintel top
	var c_pil := c_stone if tier != 2 and tier != 4 else c_stone.lightened(0.04)
	for sx: float in [-1.0, 1.0]:
		_bx(sx * ehw, sx * (ehw + pw), L, L + po, -0.05, ph, c_pil, true)
		# a shadow gap and a base block
		_bx(sx * (ehw + pw), sx * (ehw + pw + 0.03), L, L + po - 0.04, -0.05, ph - 0.05, c_pil.darkened(0.35))
		_bx(sx * ehw, sx * (ehw + pw + 0.02), L, L + po + 0.03, -0.05, 0.32, c_pil.darkened(0.18), true)
		if tier >= 3:
			# metal inlay strips up the pilasters
			_bx(sx * (ehw + pw * 0.45), sx * (ehw + pw * 0.55), L + po, L + po + 0.012, 0.4, ph - 0.25, c_metal)
	_bx(-ehw - pw, ehw + pw, L, L + po, eh, ph, c_pil, true)
	# The canopy: a slab over the pavement with a fascia, lit from below.
	var cd := 1.25 + 0.18 * tier                 # depth out from the facade
	var cy := ph + 0.04
	var cth := 0.16 + 0.03 * tier
	var cw := ehw + pw + 0.35 + 0.1 * tier
	_bx(-cw, cw, L, L + cd, cy, cy + cth, c_canopy, true)
	_bx(-cw, cw, L + cd - 0.05, L + cd + 0.02, cy - 0.05, cy + cth + 0.05, c_metal if tier >= 3 else c_canopy.darkened(0.2))
	for k in 3:
		var lx := lerpf(-cw + 0.5, cw - 0.5, float(k) / 2.0)
		_gl(lx - 0.09, lx + 0.09, L + cd * 0.5 - 0.09, L + cd * 0.5 + 0.09, cy - 0.012, cy, Color(1.0, 0.86, 0.62))
	if tier == 0 or tier == 2:
		# (slim steel ties back to the wall above)
		for sx: float in [-1.0, 1.0]:
			_bx(sx * (cw - 0.3) - 0.02, sx * (cw - 0.3) + 0.02, L, L + cd - 0.1, cy + cth, cy + cth + 0.04, c_metal)
	# Sconces either side (tier 1 up), uplights at the pilaster feet (3 up).
	if tier >= 1:
		for sx: float in [-1.0, 1.0]:
			var x := sx * (ehw + pw + 0.28)
			_bx(x - 0.07, x + 0.07, L, L + 0.06, 1.7, 2.25, c_metal)
			_gl(x - 0.05, x + 0.05, L + 0.06, L + 0.1, 1.76, 2.19, Color(1.0, 0.84, 0.58))
	if tier >= 3:
		for sx: float in [-1.0, 1.0]:
			_gl(sx * (ehw + pw * 0.5) - 0.08, sx * (ehw + pw * 0.5) + 0.08, L + po + 0.05, L + po + 0.2, -0.04, 0.0, Color(1.0, 0.9, 0.72))
	# Planters either side (tier 2 up) – on the pavement against the wall.
	if tier >= 2:
		for sx: float in [-1.0, 1.0]:
			var px := sx * (cw + 0.45)
			_bx(px - 0.32, px + 0.32, L + 0.05, L + 0.65, -0.05, 0.62, c_canopy.lightened(0.08), true)
			_bx(px - 0.28, px + 0.28, L + 0.09, L + 0.61, 0.62, 1.05, Color(0.17, 0.33, 0.17))
			_bx(px - 0.2, px + 0.2, L + 0.17, L + 0.53, 1.05, 1.4, Color(0.21, 0.4, 0.2))
	# The intercom on the right reveal: plate, screen, camera, buttons.
	var ix := ehw - 0.005
	var iz := lerpf(dz, L, 0.55)
	_bx(ix - 0.03, ix, iz - 0.09, iz + 0.09, 1.12, 1.48, c_metal.lightened(0.25) if tier != 2 else Color(0.16, 0.16, 0.17))
	_gl(ix - 0.034, ix - 0.03, iz - 0.06, iz + 0.06, 1.34, 1.44, Color(0.45, 0.65, 0.85))
	_gl(ix - 0.036, ix - 0.03, iz - 0.012, iz + 0.012, 1.455, 1.47, Color(0.2, 0.9, 0.4))
	for r in 3:
		for k in 2:
			_bx(ix - 0.04, ix - 0.03, iz - 0.05 + k * 0.06, iz - 0.01 + k * 0.06, 1.16 + r * 0.055, 1.2 + r * 0.055, Color(0.08, 0.08, 0.09))
	# Steps down to the pavement where the lobby sits above it.
	if street_drop > 0.04:
		var steps := clampi(ceili(street_drop / 0.16), 1, 8)
		for i in steps:
			var tp := -street_drop * float(i) / steps
			_bx(-ehw - pw, ehw + pw, L + 0.35 + i * 0.32, L + 0.35 + (i + 1) * 0.32, -street_drop - 0.1, tp, c_stone.darkened(0.12), true)


func _build_lobby(pal: Array, fin: Array) -> void:
	var c_wall: Color = pal[0]
	var c_floor: Color = pal[1]
	var c_trim: Color = pal[2]
	var c_wood: Color = pal[3]
	var c_metal: Color = pal[4]
	var c_feat: Color = fin[3]
	var hw := lobby_hw
	var L := _door_z
	var T := 0.15
	# Floor (with a border inlay), ceiling (a lit cove), side walls.
	_bx(-hw - T, hw + T, -0.05, L + 0.05, -0.2, 0.02, c_floor, true)
	_bx(-hw + 0.3, hw - 0.3, 0.3, L - 0.3, 0.02, 0.026, c_floor.lerp(c_trim, 0.25))
	_bx(-hw + 0.38, hw - 0.38, 0.38, L - 0.38, 0.026, 0.028, c_floor.lightened(0.06))
	_bx(-hw - T, hw + T, -0.05, L + 0.05, LOBBY_H, LOBBY_H + 0.2, c_trim.lightened(0.35), true)
	# A dropped ceiling with a lit cove round it (the glow is the gap).
	_bx(-hw, hw, 0.0, L, LOBBY_H - 0.06, LOBBY_H, c_wall.lightened(0.05))
	_bx(-hw + 0.45, hw - 0.45, 0.45, L - 0.45, LOBBY_H - 0.34, LOBBY_H - 0.06, c_wall)
	var gy := LOBBY_H - 0.07
	var cove := Color(1.0, 0.9, 0.74)
	for sx: float in [-1.0, 1.0]:
		_gl(sx * (hw - 0.42), sx * (hw - 0.3), 0.3, L - 0.3, gy - 0.008, gy, cove)
	for zz: float in [0.3, L - 0.42]:
		_gl(-hw + 0.3, hw - 0.3, zz, zz + 0.12, gy - 0.008, gy, cove)
	for sx: float in [-1.0, 1.0]:
		_bx(sx * hw, sx * (hw + T), 0.0, L, 0.0, LOBBY_H, c_wall, true)
		_bx(sx * (hw - 0.02), sx * hw, 0.0, L, 0.0, 0.12, c_trim)
	# Left wall: timber panelling with the mailboxes; right wall: the
	# feature panel behind the concierge desk with the building's name.
	_bx(-hw + 0.04, -hw, 0.3, L - 0.3, 0.12, 2.6, c_wood)
	for k in int((L - 0.6) / 0.6):
		var z := 0.3 + k * 0.6
		_bx(-hw + 0.05, -hw + 0.04, z, z + 0.012, 0.12, 2.6, c_wood.darkened(0.3))
	_bx(-hw + 0.05, -hw, 0.3, L - 0.3, 2.6, 2.64, c_metal)
	var mz := clampf(L * 0.3, 1.0, L - 2.0)
	_bx(-hw + 0.2, -hw + 0.05, mz - 0.6, mz + 0.6, 0.95, 1.85, c_metal.darkened(0.25), true)
	for r in 3:
		for ci in 4:
			var z := lerpf(mz - 0.55, mz + 0.55, (float(ci) + 0.5) / 4.0)
			_bx(-hw + 0.22, -hw + 0.2, z - 0.12, z + 0.12, 1.02 + r * 0.27, 1.24 + r * 0.27, c_metal)
	var rz := clampf(L * 0.5, 2.4, L - 2.0)
	_bx(hw - 0.04, hw, rz - 1.4, rz + 1.4, 0.12, 3.0, c_feat)
	_gl(hw - 0.05, hw - 0.04, rz - 1.4, rz + 1.4, 3.0, 3.04, Color(1.0, 0.88, 0.68))
	# The concierge desk (curved front: three facets), a lamp, a stool.
	var dx := hw - 1.35
	_bx(dx - 0.35, dx + 0.35, rz - 0.75, rz + 0.75, 0.0, 1.05, c_wood, true)
	_bx(dx - 0.45, dx + 0.4, rz - 0.85, rz + 0.85, 1.05, 1.1, c_floor.lightened(0.18))
	_bx(dx - 0.36, dx - 0.35, rz - 0.75, rz + 0.75, 0.1, 0.16, c_metal)
	_gl(dx - 0.37, dx - 0.36, rz - 0.7, rz + 0.7, 0.04, 0.07, Color(1.0, 0.86, 0.6))
	_bx(dx + 0.1, dx + 0.2, rz + 0.45, rz + 0.55, 1.1, 1.42, c_metal)
	_gl(dx + 0.04, dx + 0.26, rz + 0.39, rz + 0.61, 1.42, 1.56, Color(1.0, 0.84, 0.58))
	# Framed artwork down the plain wall, each with a picture light.
	var arts := [Color(0.62, 0.42, 0.3), Color(0.3, 0.42, 0.52), Color(0.72, 0.66, 0.52), Color(0.36, 0.46, 0.34)]
	var az := rz + 2.6
	var ai := 0
	while az < L - 1.8:
		_bx(hw - 0.05, hw, az - 0.62, az + 0.62, 1.15, 2.05, c_metal.darkened(0.2))
		_bx(hw - 0.06, hw - 0.05, az - 0.55, az + 0.55, 1.22, 1.98, arts[ai % arts.size()])
		_bx(hw - 0.18, hw - 0.05, az - 0.3, az + 0.3, 2.12, 2.16, c_metal)
		_gl(hw - 0.17, hw - 0.07, az - 0.28, az + 0.28, 2.115, 2.12, Color(1.0, 0.88, 0.66))
		az += 4.2
		ai += 1
	# Seating by the street end: a bench and a planter.
	if L > 6.0:
		var sz := L - 2.0
		_bx(-hw + 0.25, -hw + 0.8, sz - 1.0, sz + 0.4, 0.0, 0.45, c_trim.lightened(0.1), true)
		_bx(-hw + 0.25, -hw + 0.8, sz - 1.0, sz + 0.4, 0.45, 0.52, c_wood.lightened(0.12))
	for px: float in [-hw + 0.45, hw - 0.45]:
		var pz := L - 0.6
		_bx(px - 0.25, px + 0.25, pz - 0.25, pz + 0.25, 0.0, 0.55, c_trim, true)
		_bx(px - 0.3, px + 0.3, pz - 0.3, pz + 0.3, 0.55, 1.2, Color(0.2, 0.4, 0.22))
		_bx(px - 0.22, px + 0.22, pz - 0.22, pz + 0.22, 1.2, 1.55, Color(0.24, 0.48, 0.25))
	# Pendant lights down the middle.
	var n_lamps := maxi(1, int(L / 3.4))
	for i in n_lamps:
		var lz := lerpf(1.6, L - 1.4, (float(i) + 0.5) / n_lamps) if n_lamps > 1 else L * 0.5
		_bx(-0.01, 0.01, lz - 0.01, lz + 0.01, LOBBY_H - 0.9, LOBBY_H - 0.3, c_metal)
		_bx(-0.2, 0.2, lz - 0.2, lz + 0.2, LOBBY_H - 1.0, LOBBY_H - 0.9, c_metal)
		_gl(-0.18, 0.18, lz - 0.18, lz + 0.18, LOBBY_H - 1.02, LOBBY_H - 1.0, Color(1.0, 0.9, 0.72))
	# Back wall: the lift's portal in it.
	var res := _portal_wall(0.0, hw + T, LOBBY_H, pal, fin)
	_ind_ground = res[0]
	_call_g_mat = res[1]


## The wall a lift landing is set in (from −half to +half, floor y0 up to
## y1) and the portal dressing round the doors: a surround panel, a metal
## architrave with returns into the reveal, a threshold plate, the floor
## indicator flush in the head (its digits are a Label3D in front), the
## call plate on the right. Shared by every landing (lobby, home floor,
## garage) so they all match. Returns [indicator Label3D, call material].
func _portal_wall(y0: float, half: float, y1: float, pal: Array, fin: Array, garage := false) -> Array:
	var T := 0.15
	var dhw := DOOR_W * 0.5
	var c_wall: Color = pal[0]
	var c_sur: Color = fin[4]
	var c_metal: Color = pal[4] if tier != 2 else Color(0.3, 0.31, 0.33)
	if not garage:
		_bx(-half, -dhw, -T, 0.0, y0, y1, c_wall, true)
		_bx(dhw, half, -T, 0.0, y0, y1, c_wall, true)
		_bx(-dhw, dhw, -T, 0.0, y0 + DOOR_H, y1, c_wall, true)
	else:
		# (the garage's back wall fills beyond the portal itself)
		_bx(-PORTAL_HW - 0.35, -dhw, -T, 0.0, y0, y0 + PORTAL_H, c_wall, true)
		_bx(dhw, PORTAL_HW + 0.35, -T, 0.0, y0, y0 + PORTAL_H, c_wall, true)
		_bx(-dhw, dhw, -T, 0.0, y0 + DOOR_H, y0 + PORTAL_H, c_wall, true)
	# surround panel (flush-proud), split by fine shadow joints
	_bx(-PORTAL_HW, PORTAL_HW, 0.0, 0.03, y0, y0 + PORTAL_H, c_sur)
	for sx: float in [-1.0, 1.0]:
		_bx(sx * (dhw + 0.55), sx * (dhw + 0.56), 0.03, 0.032, y0, y0 + PORTAL_H, c_sur.darkened(0.35))
	_bx(-PORTAL_HW, PORTAL_HW, 0.03, 0.032, y0 + DOOR_H + 0.58, y0 + DOOR_H + 0.59, c_sur.darkened(0.35))
	# architrave: jambs and head proud of the panel, returning into the reveal
	var aw := 0.07
	for sx: float in [-1.0, 1.0]:
		_bx(sx * dhw, sx * (dhw + aw), LANDING_Z - 0.02, 0.06, y0, y0 + DOOR_H + aw, c_metal)
	_bx(-dhw - aw, dhw + aw, LANDING_Z - 0.02, 0.06, y0 + DOOR_H, y0 + DOOR_H + aw, c_metal)
	_bx(-dhw, dhw, LANDING_Z - 0.16, 0.08, y0 - 0.05, y0 + 0.012, c_metal.darkened(0.1), true)   # sill plate (bridges the gap to the car)
	# indicator: a dark glass strip in the head, digits glowing in it
	_bx(-0.42, 0.42, 0.03, 0.045, y0 + DOOR_H + 0.2, y0 + DOOR_H + 0.44, Color(0.04, 0.045, 0.05))
	var ind := _make_indicator(Vector3(0.0, y0 + DOOR_H + 0.32, 0.05), 0.0)
	add_child(ind)
	# call plate in the right of the surround
	var cmat := _make_call_panel(Vector3(dhw + 0.3, y0 + 1.12, 0.045), 0.0, "▲" if garage else ("▼" if y0 > 0.5 else "▲"))
	return [ind, cmat]


func _build_shaft(pal: Array, shaft_top: float) -> void:
	var sw := SHAFT_W * 0.5
	var T := 0.15
	var conc := Color(0.52, 0.52, 0.5)
	for sx: float in [-1.0, 1.0]:
		_bx(sx * sw, sx * (sw + T), -SHAFT_D - T, -T, -0.4, shaft_top, conc, true)
	_bx(-sw - T, sw + T, -SHAFT_D - T, -SHAFT_D, -0.4, shaft_top, conc, true)
	_bx(-sw - T, sw + T, -SHAFT_D - T, 0.0, shaft_top, shaft_top + 0.25, conc.darkened(0.1))
	_bx(-sw - T, sw + T, -SHAFT_D - T, 0.0, -0.6, -0.4, Color(0.3, 0.3, 0.3), true)   # pit floor
	if not garage_stop:
		# Between the lobby and the hall the shaft's front is closed.
		_bx(-sw - T, sw + T, -T, 0.0, LOBBY_H + 0.2, top_y - 0.2, conc, true)
	for sx: float in [-1.0, 1.0]:
		_bx(sx * (sw - 0.08), sx * (sw - 0.02), -SHAFT_D * 0.55, -SHAFT_D * 0.45, -0.4, shaft_top, pal[4])


## The enclosed lift hall on the home's floor: finished like a private
## entrance hall (panelled walls, a lit ceiling cove, a console and mirror,
## artwork), the lift portal behind, the home's front door ahead.
func _build_hall(pal: Array, fin: Array) -> void:
	var c_wall: Color = pal[0]
	var c_floor: Color = pal[1]
	var c_trim: Color = pal[2]
	var c_wood: Color = pal[3]
	var hh := Apartments.HALL_HW
	var y := top_y
	var T := 0.15
	var fdw := FRONT_DOOR_W * 0.5
	_bx(-hh - T, hh + T, -0.05, HALL_D + T, y - 0.2, y + 0.02, c_floor, true)
	_bx(-hh + 0.2, hh - 0.2, 0.2, HALL_D - 0.2, y + 0.02, y + 0.03, c_floor.lerp(c_trim, 0.2))
	_bx(-hh - T, hh + T, -0.05, HALL_D + T, y + HALL_H, y + HALL_H + 0.15, c_trim.lightened(0.35), true)
	_bx(-hh, hh, 0.0, HALL_D, y + HALL_H - 0.16, y + HALL_H, c_wall.lightened(0.05))
	_gl(-hh + 0.35, hh - 0.35, 0.35, HALL_D - 0.35, y + HALL_H - 0.17, y + HALL_H - 0.16, Color(1.0, 0.93, 0.82))
	for sx: float in [-1.0, 1.0]:
		_bx(sx * hh, sx * (hh + T), -T, HALL_D + T, y, y + HALL_H, c_wall, true)
		_bx(sx * (hh - 0.02), sx * hh, 0.0, HALL_D, y, y + 0.12, c_trim)
		_bx(sx * (hh - 0.03), sx * hh, 0.0, HALL_D, y + 0.95, y + 0.99, c_wood)
	# Front wall with the home's front door, its frame and number.
	_bx(-hh - T, -fdw, HALL_D, HALL_D + T, y, y + HALL_H, c_wall, true)
	_bx(fdw, hh + T, HALL_D, HALL_D + T, y, y + HALL_H, c_wall, true)
	_bx(-fdw, fdw, HALL_D, HALL_D + T, y + 2.2, y + HALL_H, c_wall, true)
	for fx: float in [-fdw - 0.08, fdw]:
		_bx(fx, fx + 0.08, HALL_D - 0.04, HALL_D + T + 0.04, y, y + 2.28, c_wood.darkened(0.2))
	_bx(-fdw - 0.08, fdw + 0.08, HALL_D - 0.04, HALL_D + T + 0.04, y + 2.2, y + 2.28, c_wood.darkened(0.2))
	# Console, mirror, doormat, an artwork, a wall light.
	_bx(hh - 0.4, hh - 0.02, 0.5, 1.5, y, y + 0.82, c_wood, true)
	_bx(hh - 0.04, hh - 0.02, 0.6, 1.4, y + 1.15, y + 1.95, Color(0.76, 0.82, 0.88))
	_bx(-0.6, 0.6, HALL_D - 0.7, HALL_D - 0.1, y + 0.03, y + 0.04, Color(0.2, 0.17, 0.15))
	_bx(-hh + 0.02, -hh + 0.05, 0.5, 1.5, y + 1.2, y + 2.0, fin[3])
	_bx(-hh + 0.05, -hh + 0.06, 0.55, 1.45, y + 1.25, y + 1.95, Color(0.55, 0.42, 0.32).lerp(pal[2], 0.4))
	var plaque := Label3D.new()
	plaque.text = top_floor_label if tier < 4 else "PENTHOUSE"
	plaque.font_size = 26
	plaque.pixel_size = 0.0032
	plaque.modulate = Color(0.95, 0.86, 0.6)
	plaque.position = Vector3(fdw + 0.35, y + 1.55, HALL_D - 0.01)
	plaque.rotation.y = PI
	add_child(plaque)
	var res := _portal_wall(y, hh + T, y + HALL_H, pal, fin)
	_ind_top = res[0]
	_call_top_mat = res[1]
	_clad_core(pal, fin)


## Inside the home, the lift's hall and shaft are one built-in core: clad
## floor to ceiling (to the mezzanine's underside in a penthouse), plaster
## sides with a skirting and a shadow gap at the ceiling, the face round
## the front door in the tier's feature finish with a deep reveal, wall
## lights either side (2026-11-27: it read as a white box standing in the
## room, stopping short of the ceiling).
func _clad_core(pal: Array, fin: Array) -> void:
	var hh := Apartments.HALL_HW
	var y := top_y
	var T := 0.15
	var fdw := FRONT_DOOR_W * 0.5
	var top := (HomeInteriors.MEZZ if tier >= 4 else room_h) - 0.012
	if top < HALL_H + 0.05:
		return
	var c_side: Color = (pal[0] as Color).lightened(0.04)
	var c_face: Color = fin[3]
	var c_dark: Color = (pal[2] as Color).darkened(0.25)
	var x0 := hh + T
	var x1 := x0 + 0.04
	var zb := -SHAFT_D
	var z0 := HALL_D + T
	var zf := z0 + 0.06
	for sx: float in [-1.0, 1.0]:
		_bx(sx * x0, sx * x1, zb, zf, y, y + top, c_side, true)
		_bx(sx * x1, sx * (x1 + 0.012), zb, zf, y, y + 0.11, c_dark)                   # skirting
		_bx(sx * x1, sx * (x1 + 0.004), zb, zf, y + top - 0.05, y + top - 0.03, c_dark)  # shadow gap
	# the door face: feature finish, a deep lined reveal, a lintel
	var ow := fdw + 0.1
	_bx(-x1, -ow, z0, zf, y, y + top, c_face, true)
	_bx(ow, x1, z0, zf, y, y + top, c_face, true)
	_bx(-ow, ow, z0, zf, y + 2.36, y + top, c_face, true)
	for sx: float in [-1.0, 1.0]:
		_bx(sx * fdw, sx * ow, z0 + 0.045, zf + 0.02, y, y + 2.36, c_dark)
	_bx(-ow, ow, z0 + 0.045, zf + 0.02, y + 2.28, y + 2.36, c_dark)
	# vertical joints in the feature face, and the skirting
	for k in 3:
		for sx: float in [-1.0, 1.0]:
			var jx := sx * lerpf(ow + 0.3, x1 - 0.2, float(k) / 2.0)
			_bx(jx - 0.004, jx + 0.004, zf, zf + 0.003, y + 0.11, y + top - 0.06, c_face.darkened(0.3))
	_bx(-x1, x1, zf, zf + 0.012, y, y + 0.11, c_dark)
	_bx(-x1, x1, zf, zf + 0.004, y + top - 0.05, y + top - 0.03, c_dark)
	# wall lights either side of the door
	for sx: float in [-1.0, 1.0]:
		var lx := sx * (ow + 0.32)
		_bx(lx - 0.05, lx + 0.05, zf, zf + 0.05, y + 1.75, y + 2.1, pal[4])
		_gl(lx - 0.035, lx + 0.035, zf + 0.05, zf + 0.06, y + 1.8, y + 2.05, Color(1.0, 0.86, 0.62))


func _build_entrance_doors(fin: Array) -> void:
	# Glass double doors on pivots at the jambs, opening inward together.
	var door_h := minf(_ent_h - 0.45, 2.45)
	var leaf_w := _ent_hw - 0.07
	_ent_l = _make_glass_leaf("EntDoorL", leaf_w, door_h, fin[5], 1.0)
	_ent_l.position = Vector3(-_ent_hw + 0.07, 0.02, _door_z + 0.02)
	add_child(_ent_l)
	_ent_r = _make_glass_leaf("EntDoorR", leaf_w, door_h, fin[5], -1.0)
	_ent_r.position = Vector3(_ent_hw - 0.07, 0.02, _door_z + 0.02)
	add_child(_ent_r)
	_ent_col = _make_door_blocker("EntDoorCol", Vector3(_ent_hw * 2.0, door_h, 0.14), Vector3(0.0, door_h * 0.5, _door_z + 0.02))
	add_child(_ent_col)


## A framed glass leaf hinged at its outer edge (`sgn` +1: hinge on the
## left, leaf extends +x): stiles and rails in metal, a tall pull handle.
func _make_glass_leaf(nm: String, w: float, h: float, metal: Color, sgn: float) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	var mm := _mat_solid(metal, 0.32, 0.75)
	var parts := [
		[Vector3(0.06, h, 0.05), Vector3(sgn * 0.03, h * 0.5, 0.0)],
		[Vector3(0.06, h, 0.05), Vector3(sgn * (w - 0.03), h * 0.5, 0.0)],
		[Vector3(w, 0.06, 0.05), Vector3(sgn * w * 0.5, h - 0.03, 0.0)],
		[Vector3(w, 0.16, 0.05), Vector3(sgn * w * 0.5, 0.08, 0.0)],
		[Vector3(0.025, 0.9, 0.05), Vector3(sgn * (w - 0.14), 1.05, 0.065)],
		[Vector3(0.025, 0.9, 0.05), Vector3(sgn * (w - 0.14), 1.05, -0.065)],
	]
	for pt: Array in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pt[0]
		mi.mesh = bm
		mi.position = pt[1]
		mi.material_override = mm
		mi.visibility_range_end = 180.0
		n.add_child(mi)
	var g := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(w - 0.1, h - 0.2, 0.012)
	g.mesh = gb
	g.position = Vector3(sgn * w * 0.5, (h - 0.2) * 0.5 + 0.16, 0.0)
	g.material_override = _mat_glass()
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visibility_range_end = 180.0
	n.add_child(g)
	n.set_meta("sgn", sgn)
	return n


func _build_landing_doors(pal: Array, y: float) -> void:
	var c_metal: Color = pal[4] if tier != 2 else Color(0.42, 0.43, 0.45)
	var leaf_w := DOOR_W * 0.5
	_g_door_l = _make_door_leaf("GroundElevDoorL", leaf_w, DOOR_H, 0.04, c_metal, false)
	_g_door_l.position = Vector3(-leaf_w * 0.5, 0.02, LANDING_Z)
	add_child(_g_door_l)
	_g_door_r = _make_door_leaf("GroundElevDoorR", leaf_w, DOOR_H, 0.04, c_metal, false)
	_g_door_r.position = Vector3(leaf_w * 0.5, 0.02, LANDING_Z)
	add_child(_g_door_r)
	_g_door_col = _make_door_blocker("GroundElevDoorCol", Vector3(DOOR_W, DOOR_H, 0.12), Vector3(0.0, DOOR_H * 0.5, LANDING_Z))
	add_child(_g_door_col)
	if garage_stop:
		return
	_top_door_l = _make_door_leaf("TopElevDoorL", leaf_w, DOOR_H, 0.04, c_metal, false)
	_top_door_l.position = Vector3(-leaf_w * 0.5, y + 0.01, LANDING_Z)
	add_child(_top_door_l)
	_top_door_r = _make_door_leaf("TopElevDoorR", leaf_w, DOOR_H, 0.04, c_metal, false)
	_top_door_r.position = Vector3(leaf_w * 0.5, y + 0.01, LANDING_Z)
	add_child(_top_door_r)
	_top_door_col = _make_door_blocker("TopElevDoorCol", Vector3(DOOR_W, DOOR_H, 0.12), Vector3(0.0, y + DOOR_H * 0.5, LANDING_Z))
	add_child(_top_door_col)


func _build_front_door(pal: Array) -> void:
	var c_wood: Color = pal[3]
	var y := top_y
	var T := 0.15
	var fdw := FRONT_DOOR_W * 0.5
	_front_door = Node3D.new()
	_front_door.name = "FrontDoor"
	_front_door.position = Vector3(-fdw, y, HALL_D + T * 0.5)
	add_child(_front_door)
	var leaf := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(FRONT_DOOR_W, 2.18, 0.06)
	leaf.mesh = lb
	leaf.position = Vector3(fdw, 1.09, 0.0)
	leaf.material_override = _mat_solid(c_wood.darkened(0.1), 0.5, 0.0)
	_front_door.add_child(leaf)
	var knob := MeshInstance3D.new()
	var kb := BoxMesh.new()
	kb.size = Vector3(0.12, 0.04, 0.16)
	knob.mesh = kb
	knob.position = Vector3(FRONT_DOOR_W - 0.1, 1.0, 0.0)
	knob.material_override = _mat_solid(Color(0.74, 0.57, 0.3), 0.3, 0.8)
	_front_door.add_child(knob)
	_front_door_col = _make_door_blocker("FrontDoorCol", Vector3(FRONT_DOOR_W, 2.2, 0.12), Vector3(0.0, y + 1.1, HALL_D + T * 0.5))
	add_child(_front_door_col)


func _build_lights() -> void:
	var L := _door_z
	var hw := lobby_hw
	var fin: Array = TIER_FINISH[tier]
	# Signage: the building's name on the canopy fascia, a number plate.
	var ph := _ent_h + 0.5 + 0.08 * tier
	var cd := 1.25 + 0.18 * tier
	var cth := 0.16 + 0.03 * tier
	var sign_lbl := Label3D.new()
	sign_lbl.text = home_name.to_upper()
	sign_lbl.font_size = 44
	sign_lbl.pixel_size = 0.0036 + 0.0002 * tier
	sign_lbl.modulate = (fin[1] as Color).lightened(0.35) if tier >= 3 else Color(1.0, 0.96, 0.88)
	sign_lbl.outline_size = 0
	sign_lbl.shaded = true
	sign_lbl.position = Vector3(0.0, ph + 0.04 + cth * 0.5, lobby_len + cd + 0.03)
	add_child(sign_lbl)
	var num := Label3D.new()
	num.text = str(10 + (absi(hash(home_id)) % 180))
	num.font_size = 40
	num.pixel_size = 0.0035
	num.modulate = (fin[1] as Color).lightened(0.2)
	num.shaded = true
	var pw := 0.34 + 0.06 * tier
	num.position = Vector3(-(_ent_hw + pw * 0.5), 2.05, lobby_len + 0.22 + 0.06 * tier + 0.01)
	add_child(num)
	var dir_lbl := Label3D.new()
	dir_lbl.text = "%s\nRESIDENTS\nG  ·  LOBBY\n%s  ·  %s" % [home_name.to_upper(), top_floor_label, "HOME"]
	dir_lbl.font_size = 22
	dir_lbl.pixel_size = 0.0034
	dir_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dir_lbl.modulate = Color(0.98, 0.92, 0.8)
	dir_lbl.outline_size = 0
	dir_lbl.position = Vector3(hw - 0.05, 2.3, clampf(L * 0.5, 2.4, L - 2.0))
	dir_lbl.rotation.y = -PI * 0.5
	add_child(dir_lbl)
	var lz := InteriorKit.add_lighting_zone(self, AABB(Vector3(-hw, 0.0, 0.0), Vector3(hw * 2.0, LOBBY_H, L)))
	InteriorKit.room_probe(lz, Color(1.0, 0.92, 0.8), 0.55, 0.2)
	# Warm light: one for a short lobby, two down a long one; the dark
	# palettes (loft, penthouse) get more so the finishes still read.
	var dark := tier == 2 or tier == 4
	var n_l := 1 if L < 9.0 else 2
	for i in n_l:
		var ol := OmniLight3D.new()
		ol.position = Vector3(0.0, LOBBY_H - 0.45, L * (0.5 if n_l == 1 else (0.28 if i == 0 else 0.74)))
		ol.light_color = Color(1.0, 0.9, 0.74)
		InteriorKit.tune_light(ol, (2.6 if n_l == 1 else 2.2) * (1.35 if dark else 1.0), maxf(7.0, L * (0.75 if n_l == 1 else 0.42)))
		add_child(ol)
		if i == 0:
			_lobby_light = ol
		else:
			_lobby_light2 = ol
	# A warm light under the canopy (shadowless, near only).
	_porch_light = OmniLight3D.new()
	_porch_light.position = Vector3(0.0, _ent_h + 0.2, lobby_len + 0.6)
	_porch_light.light_color = Color(1.0, 0.84, 0.6)
	_porch_light.light_energy = 1.1
	_porch_light.omni_range = 4.5
	_porch_light.shadow_enabled = false
	add_child(_porch_light)
	var hh := Apartments.HALL_HW
	var y := top_y
	var hz := InteriorKit.add_lighting_zone(self, AABB(Vector3(-hh, y, 0.0), Vector3(hh * 2.0, HALL_H, HALL_D)))
	var hall_light := OmniLight3D.new()
	hall_light.position = Vector3(0.0, y + HALL_H - 0.3, HALL_D * 0.5)
	hall_light.light_color = Color(1.0, 0.94, 0.84)
	InteriorKit.tune_light(hall_light, 1.7, 3.8)
	hz.add_child(hall_light)


## The Vehicle Collection's end of the line (VehicleGarage): a landing (the
## same portal, doors, indicator and call plate as every other) and a cabin
## built to the same plan and finish as tier `t`'s, so arriving by lift
## looks like the ride you set off on.
static func build_garage_stop(t: int, label: String) -> ApartmentElevator:
	var el := ApartmentElevator.new()
	el.garage_stop = true
	el.tier = clampi(t, 0, 4)
	el.name = "GarageLift"
	el.top_y = 0.0
	el.top_floor_num = 1
	el.top_floor_label = label
	el.lobby_len = 0.0
	el.lobby_hw = PORTAL_HW
	var pal: Array = TIER_PAL[el.tier]
	var fin: Array = TIER_FINISH[el.tier]
	el._begin_meshes()
	var res := el._portal_wall(0.0, PORTAL_HW + 0.35, PORTAL_H, pal, fin, true)
	el._ind_ground = res[0]
	el._call_g_mat = res[1]
	el._build_shaft(pal, CAB_H + 0.8)
	el._end_meshes(200.0)
	el._build_landing_doors(pal, 0.0)
	el._build_cabin(pal[3], pal[1], pal[4], pal[2])
	el._sync_doors()
	el._update_indicators(label)
	return el


func _build_cabin(c_wood: Color, c_floor: Color, c_metal: Color, c_trim: Color) -> void:
	_cabin = Node3D.new()
	_cabin.name = "ElevatorCabin"
	add_child(_cabin)
	var cm := BuildingMesher.new()
	cm._begin({"style": 0})
	var cg := BuildingMesher.new()
	cg._begin({"style": 0})
	var chw := CAB_W * 0.5
	var z0 := -SHAFT_D * 0.5 - CAB_D * 0.5
	var z1 := z0 + CAB_D
	var zc := -SHAFT_D * 0.5
	var dhw := DOOR_W * 0.5
	# floor: stone with a metal border; ceiling: a lit panel in a frame
	cm.solid(-chw, z0, chw, z1, -0.12, 0.02, c_floor.darkened(0.06))
	cm.solid(-chw + 0.1, z0 + 0.1, chw - 0.1, z1 - 0.1, 0.02, 0.026, c_floor.lightened(0.08))
	cm.solid(-chw, z0, chw, z1, CAB_H, CAB_H + 0.14, c_trim)
	cm.solid(-chw, z0, chw, z1, CAB_H - 0.06, CAB_H, c_metal)
	cg.solid(-chw + 0.22, z0 + 0.22, chw - 0.22, z1 - 0.22, CAB_H - 0.07, CAB_H - 0.06, Color(1.0, 0.94, 0.82))
	# walls: timber panels framed in metal, a mirror on the back
	for sx: float in [-1.0, 1.0]:
		cm.solid(sx * chw - (0.08 if sx > 0 else 0.0), z0, sx * chw + (0.0 if sx > 0 else 0.08), z1, 0.02, CAB_H, c_wood)
		for k in 3:
			var zz := lerpf(z0 + 0.12, z1 - 0.12, float(k) / 3.0)
			cm.solid(sx * (chw - 0.085) - 0.004, zz, sx * (chw - 0.085) + 0.004, zz + 0.01, 0.1, CAB_H - 0.1, c_metal)
	cm.solid(-chw, z0, chw, z0 + 0.08, 0.02, CAB_H, c_wood.lightened(0.05))
	cm.solid(-chw + 0.22, z0 + 0.08, chw - 0.22, z0 + 0.1, 0.95, 2.3, Color(0.76, 0.82, 0.88))
	cm.solid(-chw + 0.2, z0 + 0.08, chw - 0.2, z0 + 0.11, 0.93, 0.95, c_metal)
	cm.solid(-chw + 0.2, z0 + 0.08, chw - 0.2, z0 + 0.11, 2.3, 2.32, c_metal)
	# handrails
	cm.solid(-chw + 0.08, z0 + 0.18, -chw + 0.13, z1 - 0.18, 0.92, 0.96, c_metal)
	cm.solid(chw - 0.13, z0 + 0.18, chw - 0.08, z1 - 0.18, 0.92, 0.96, c_metal)
	cm.solid(-chw + 0.3, z0 + 0.1, chw - 0.3, z0 + 0.15, 0.92, 0.96, c_metal)
	# front return walls (metal) round the doors, the operating panel
	cm.solid(-chw, z1 - 0.08, -dhw, z1, 0.02, CAB_H, c_metal)
	cm.solid(dhw, z1 - 0.08, chw, z1, 0.02, CAB_H, c_metal)
	cm.solid(-dhw, z1 - 0.08, dhw, z1, DOOR_H, CAB_H, c_metal)
	cm.solid(chw - 0.11, z1 - 1.25, chw - 0.08, z1 - 0.55, 0.9, 1.62, Color(0.08, 0.085, 0.1))
	cg.solid(chw - 0.115, z1 - 1.1, chw - 0.11, z1 - 0.7, 1.5, 1.58, Color(1.0, 0.7, 0.25))
	cm._end()
	cg._end()
	var mi := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cm.arrays())
	mi.mesh = mesh
	mi.material_override = _mat_vcol(0.32, 0.28)
	mi.visibility_range_end = 180.0
	_cabin.add_child(mi)
	var gi := MeshInstance3D.new()
	var gmesh := ArrayMesh.new()
	gmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cg.arrays())
	gi.mesh = gmesh
	gi.material_override = _mat_glow()
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cabin.add_child(gi)
	_btn_g_mat = _make_cabin_button(Vector3(chw - 0.13, 1.08, z1 - 0.9), "G" if not garage_stop else "▲")
	_btn_top_mat = _make_cabin_button(Vector3(chw - 0.13, 1.3, z1 - 0.9), top_floor_label)
	_ind_cabin = _make_indicator(Vector3(chw - 0.115, 1.54, z1 - 0.9), -PI * 0.5)
	_ind_cabin.font_size = 22
	_cabin.add_child(_ind_cabin)
	_cabin_light = OmniLight3D.new()
	_cabin_light.position = Vector3(0.0, CAB_H - 0.25, zc)
	_cabin_light.light_color = Color(1.0, 0.94, 0.84)
	InteriorKit.tune_light(_cabin_light, 1.85, 3.8)
	_cabin.add_child(_cabin_light)
	InteriorKit.add_lighting_zone(_cabin, AABB(Vector3(-chw, 0.0, z0), Vector3(CAB_W, CAB_H, CAB_D)))
	var lw := DOOR_W * 0.5
	_cab_front_l = _make_door_leaf("CabFrontL", lw, DOOR_H, 0.04, c_metal.darkened(0.08), false)
	_cab_front_l.position = Vector3(-lw * 0.5, 0.02, z1 - 0.04)
	_cabin.add_child(_cab_front_l)
	_cab_front_r = _make_door_leaf("CabFrontR", lw, DOOR_H, 0.04, c_metal.darkened(0.08), false)
	_cab_front_r.position = Vector3(lw * 0.5, 0.02, z1 - 0.04)
	_cabin.add_child(_cab_front_r)
	var cbody := AnimatableBody3D.new()
	cbody.name = "CabinBody"
	cbody.sync_to_physics = false
	cbody.collision_layer = CityWorld.HUMAN_LAYER
	cbody.collision_mask = 0
	_add_col_box(cbody, Vector3(CAB_W, 0.14, CAB_D), Vector3(0.0, -0.05, zc))
	_add_col_box(cbody, Vector3(CAB_W, 0.14, CAB_D), Vector3(0.0, CAB_H + 0.07, zc))
	_add_col_box(cbody, Vector3(0.1, CAB_H, CAB_D), Vector3(-chw + 0.05, CAB_H * 0.5, zc))
	_add_col_box(cbody, Vector3(0.1, CAB_H, CAB_D), Vector3(chw - 0.05, CAB_H * 0.5, zc))
	_add_col_box(cbody, Vector3(CAB_W, CAB_H, 0.1), Vector3(0.0, CAB_H * 0.5, z0 + 0.04))
	_cab_door_col_f = _add_col_box(cbody, Vector3(CAB_W, CAB_H, 0.1), Vector3(0.0, CAB_H * 0.5, z1 - 0.04))
	_cabin.add_child(cbody)


# ---------------------------------------------------------------- helpers
func _add_mesh(nm: String, arr: Array, mat: Material, vis_end: float, cast_sh := true) -> void:
	if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null or (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	mi.visibility_range_end = vis_end
	if not cast_sh:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _make_door_leaf(nm: String, w: float, h: float, thick: float, col: Color, glazed: bool) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, thick)
	mi.mesh = bm
	mi.position.y = h * 0.5
	if glazed:
		mi.material_override = _mat_glass()
		# Add brushed-metal frame bar at bottom and vertical pull handle
		var bar := MeshInstance3D.new()
		var bbm := BoxMesh.new()
		bbm.size = Vector3(w, 0.14, thick + 0.02)
		bar.mesh = bbm
		bar.position.y = 0.07
		bar.material_override = _mat_solid(col, 0.35, 0.55)
		n.add_child(bar)
	else:
		mi.material_override = _mat_solid(col, 0.28, 0.65)
	mi.visibility_range_end = 180.0
	n.add_child(mi)
	return n


func _make_door_blocker(nm: String, sz: Vector3, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = nm
	sb.collision_layer = CityWorld.HUMAN_LAYER
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = sz
	cs.shape = sh
	cs.position = pos
	sb.add_child(cs)
	return sb


func _add_col_box(parent: Node3D, sz: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = sz
	cs.shape = sh
	cs.position = pos
	parent.add_child(cs)
	return cs


func _make_call_panel(pos: Vector3, rot_y: float, sym: String) -> StandardMaterial3D:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = rot_y
	add_child(holder)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.14, 0.26, 0.03)
	plate.mesh = pm
	plate.material_override = _mat_solid(Color(0.12, 0.13, 0.15), 0.3, 0.6)
	holder.add_child(plate)
	var btn := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, 0.02)
	btn.mesh = bm
	btn.position = Vector3(0.0, 0.0, 0.018)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.95, 0.80, 0.35)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.82, 0.32)
	bmat.emission_energy_multiplier = 0.7
	btn.material_override = bmat
	holder.add_child(btn)
	var lbl := Label3D.new()
	lbl.text = sym
	lbl.font_size = 24
	lbl.pixel_size = 0.0024
	lbl.modulate = Color(0.1, 0.1, 0.1)
	lbl.position = Vector3(0.0, 0.0, 0.032)
	holder.add_child(lbl)
	return bmat


func _make_cabin_button(pos: Vector3, text: String) -> StandardMaterial3D:
	var btn := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.09, 0.09)
	btn.mesh = bm
	btn.position = pos
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.28, 0.30, 0.34)
	bmat.emission_enabled = true
	bmat.emission = Color(0.18, 0.20, 0.24)
	bmat.emission_energy_multiplier = 0.4
	btn.material_override = bmat
	_cabin.add_child(btn)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 22
	lbl.pixel_size = 0.0022
	lbl.modulate = Color(0.98, 0.96, 0.90)
	lbl.outline_size = 4
	lbl.position = pos + Vector3(-0.018, 0.0, 0.0)
	lbl.rotation.y = -PI * 0.5
	_cabin.add_child(lbl)
	return bmat


func _make_indicator(pos: Vector3, rot_y: float) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = "G"
	lbl.font_size = 32
	lbl.pixel_size = 0.0042
	lbl.modulate = Color(1.0, 0.72, 0.22)
	lbl.outline_size = 4
	lbl.outline_modulate = Color(0.04, 0.04, 0.05)
	lbl.position = pos
	lbl.rotation.y = rot_y
	return lbl


static func _mat_vcol(rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	return m


static func _mat_solid(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


static func _mat_glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.68, 0.82, 0.90, 0.32)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.15
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _mat_glow() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
