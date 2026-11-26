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

## State machine: "idle_g" | "idle_top" | "closing" | "moving" | "opening"
var state := "idle_g"
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
	lobby_len = float(core["o_face0"]) - float(core["o_door"])
	lobby_hw = float(core["lobby_hw"])
	street_drop = maxf(0.0, base - ground_y) if not is_nan(ground_y) else 0.0
	top_floor_num = maxi(int(round(top_y / Apartments.FLOOR)), 1)
	top_floor_label = "PH" if tier >= 4 else ("F%02d" % top_floor_num)
	transform = Transform3D(Basis(along, Vector3.UP, out), origin)
	_build_geometry()
	_sync_doors()
	_update_indicators("G")


## The street door, on the pavement (compatible with home_lift()).
func street_door_world() -> Vector3:
	return to_global(Vector3(0.0, -street_drop, lobby_len + 0.8))


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
	if absf(lp.x) < lobby_hw + 0.1 and lp.z > -0.1 and lp.z < lobby_len + 0.2 and lp.y > -0.3 and lp.y < LOBBY_H:
		return true
	if absf(lp.x) < Apartments.HALL_HW + 0.1 and lp.z > -0.1 and lp.z < HALL_D + 0.1 and absf(lp.y - (top_y + 0.95)) < 1.8:
		return true
	return is_inside_cabin(world_pos)


func is_riding() -> bool:
	return _player_riding and state in ["closing", "moving", "opening"]


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
	if _cabin_light:
		_cabin_light.visible = near
	if not near and state in ["idle_g", "idle_top"]:
		return
	var lp := to_local(p_world)
	# 1. Ground entrance sliding glass doors open smoothly on approach.
	var ent_near := absf(lp.x) < 2.2 and lp.z > lobby_len - 2.4 and lp.z < lobby_len + 3.4 and lp.y > -street_drop - 1.0 and lp.y < 3.0
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
	var fd_near := owns and absf(lp.x) < 1.4 and lp.z > HALL_D - 1.6 and lp.z < HALL_D + 1.8 and absf(lp.y - top_y) < 2.4
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


func _update_indicators(text: String) -> void:
	var arrow := ""
	if state == "moving":
		arrow = " ▲" if target_top else " ▼"
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
	var slide := _ent_open * 0.92
	if _ent_l:
		_ent_l.position.x = -0.52 - slide
	if _ent_r:
		_ent_r.position.x = 0.52 + slide
	if _ent_col:
		_ent_col.collision_layer = 0 if _ent_open > 0.65 else CityWorld.HUMAN_LAYER


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
func _build_geometry() -> void:
	var pal: Array = TIER_PAL[tier]
	var c_wall: Color = pal[0]
	var c_floor: Color = pal[1]
	var c_trim: Color = pal[2]
	var c_wood: Color = pal[3]
	var c_metal: Color = pal[4]
	var arch := BuildingMesher.new()
	arch._begin({"style": 0})
	var glass_m := BuildingMesher.new()
	glass_m._begin({"style": 0})
	var glow_m := BuildingMesher.new()
	glow_m._begin({"style": 0})
	var col_boxes: Array[AABB] = []
	var add_box := func(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, c: Color, solid := false) -> void:
		arch.solid(minf(x0, x1), minf(z0, z1), maxf(x0, x1), maxf(z0, z1), minf(y0, y1), maxf(y0, y1), c)
		if solid:
			col_boxes.append(AABB(Vector3(minf(x0, x1), minf(y0, y1), minf(z0, z1)), Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))))
	var hw := lobby_hw
	var L := lobby_len
	var dhw := DOOR_W * 0.5
	var sw := SHAFT_W * 0.5
	var ehw := Apartments.STREET_DOOR_HW
	var T := 0.15

	# ==================== 1. GROUND LOBBY (inside the building) ====================
	add_box.call(-hw - T, hw + T, -0.05, L + 0.05, -0.2, 0.02, c_floor, true)                 # floor
	add_box.call(-hw - T, hw + T, -0.05, L + 0.05, LOBBY_H, LOBBY_H + 0.2, c_trim.lightened(0.35), true)  # ceiling
	for sx: float in [-1.0, 1.0]:
		add_box.call(sx * hw, sx * (hw + T), 0.0, L, 0.0, LOBBY_H, c_wall, true)                # side walls
		add_box.call(sx * (hw - 0.02), sx * hw, 0.0, L, 0.0, 0.12, c_trim)                     # skirting
		add_box.call(sx * (hw - 0.03), sx * hw, 0.0, L, 1.05, 1.1, c_wood)                     # dado rail
	# Front wall (inside the facade) round the street door.
	add_box.call(-hw - T, -ehw, L - T, L, 0.0, LOBBY_H, c_wall, true)
	add_box.call(ehw, hw + T, L - T, L, 0.0, LOBBY_H, c_wall, true)
	add_box.call(-ehw, ehw, L - T, L, Apartments.STREET_DOOR_H, LOBBY_H, c_wall, true)
	for ex: float in [-ehw - 0.08, ehw]:
		add_box.call(ex, ex + 0.08, L - 0.22, L + 0.06, 0.0, Apartments.STREET_DOOR_H + 0.08, c_metal)
	add_box.call(-ehw - 0.08, ehw + 0.08, L - 0.22, L + 0.06, Apartments.STREET_DOOR_H, Apartments.STREET_DOOR_H + 0.1, c_metal)
	# Back wall: the lift's landing door.
	add_box.call(-hw - T, -dhw, -T, 0.0, 0.0, LOBBY_H, c_wall, true)
	add_box.call(dhw, hw + T, -T, 0.0, 0.0, LOBBY_H, c_wall, true)
	add_box.call(-dhw, dhw, -T, 0.0, DOOR_H, LOBBY_H, c_wall, true)
	add_box.call(-dhw - 0.12, -dhw, -0.04, 0.1, 0.0, DOOR_H + 0.12, c_metal)
	add_box.call(dhw, dhw + 0.12, -0.04, 0.1, 0.0, DOOR_H + 0.12, c_metal)
	add_box.call(-dhw - 0.12, dhw + 0.12, -0.04, 0.1, DOOR_H, DOOR_H + 0.14, c_metal)
	add_box.call(-0.34, 0.34, 0.0, 0.09, DOOR_H + 0.22, DOOR_H + 0.5, Color(0.08, 0.09, 0.1))
	# Floor finish: a runner from the door to the lift, a mat at the door.
	add_box.call(-0.9, 0.9, 0.4, L - 0.5, 0.02, 0.028, c_trim.lerp(c_floor, 0.4))
	add_box.call(-1.0, 1.0, L - 1.1, L - 0.2, 0.02, 0.034, Color(0.16, 0.15, 0.14))
	# Ceiling light panels along the lobby.
	var n_lamps := maxi(1, int(L / 3.2))
	for i in n_lamps:
		var lz := lerpf(1.2, L - 1.2, (float(i) + 0.5) / n_lamps) if n_lamps > 1 else L * 0.5
		glow_m.solid(-0.9, lz - 0.3, 0.9, lz + 0.3, LOBBY_H - 0.03, LOBBY_H, Color(1.0, 0.93, 0.8))
	# Mailboxes on the back wall left of the lift, a directory right of it.
	add_box.call(-hw + 0.25, -dhw - 0.35, 0.0, 0.2, 0.9, 2.0, c_metal.darkened(0.2), true)
	for r in 3:
		for ci in 3:
			var mx := lerpf(-hw + 0.32, -dhw - 0.42, (float(ci) + 0.5) / 3.0)
			add_box.call(mx - 0.17, mx + 0.17, 0.2, 0.23, 1.0 + r * 0.32, 1.25 + r * 0.32, c_metal)
	# Reception desk (left) with a lamp; seating (right) with a low table.
	var rz := clampf(L * 0.45, 2.6, L - 2.2)
	add_box.call(-hw + 0.1, -hw + 0.75, rz - 0.9, rz + 0.9, 0.0, 1.0, c_wood, true)
	add_box.call(-hw + 0.06, -hw + 0.82, rz - 0.95, rz + 0.95, 1.0, 1.06, c_floor.lightened(0.15))
	add_box.call(-hw + 0.25, -hw + 0.45, rz + 0.3, rz + 0.5, 1.06, 1.36, c_metal)
	glow_m.solid(-hw + 0.2, rz + 0.25, -hw + 0.5, rz + 0.55, 1.36, 1.52, Color(1.0, 0.84, 0.58))
	if hw > 2.0:
		add_box.call(hw - 0.7, hw - 0.1, rz - 1.0, rz + 1.0, 0.0, 0.42, c_trim.lightened(0.1), true)
		add_box.call(hw - 0.7, hw - 0.1, rz - 1.0, rz + 1.0, 0.42, 0.5, c_wood.lightened(0.15))
		add_box.call(hw - 0.2, hw - 0.1, rz - 1.0, rz + 1.0, 0.5, 0.95, c_trim.lightened(0.1))
		add_box.call(hw - 1.45, hw - 0.95, rz - 0.35, rz + 0.35, 0.0, 0.42, c_wood, true)
	# Planters either side of the street door.
	for px: float in [-hw + 0.45, hw - 0.45]:
		var pz := L - 0.6
		add_box.call(px - 0.25, px + 0.25, pz - 0.25, pz + 0.25, 0.0, 0.55, c_trim, true)
		add_box.call(px - 0.3, px + 0.3, pz - 0.3, pz + 0.3, 0.55, 1.2, Color(0.2, 0.4, 0.22))
		add_box.call(px - 0.22, px + 0.22, pz - 0.22, pz + 0.22, 1.2, 1.55, Color(0.24, 0.48, 0.25))
	# Outside: a canopy over the street door, steps down to the pavement.
	add_box.call(-ehw - 0.5, ehw + 0.5, L + 0.02, L + 1.5, Apartments.STREET_DOOR_H + 0.15, Apartments.STREET_DOOR_H + 0.35, c_trim)
	glow_m.solid(-ehw, L + 0.5, ehw, L + 1.0, Apartments.STREET_DOOR_H + 0.12, Apartments.STREET_DOOR_H + 0.15, Color(1.0, 0.9, 0.72))
	if street_drop > 0.04:
		var steps := clampi(ceili(street_drop / 0.17), 1, 8)
		for i in steps:
			var top := -street_drop * float(i) / steps
			add_box.call(-ehw - 0.3, ehw + 0.3, L + 0.05 + i * 0.32, L + 0.05 + (i + 1) * 0.32, -street_drop - 0.1, top, c_trim.lightened(0.25), true)

	# ==================== 2. SHAFT (inside the building) ====================
	var shaft_top := top_y + HALL_H + 0.6
	for sx: float in [-1.0, 1.0]:
		add_box.call(sx * sw, sx * (sw + T), -SHAFT_D - T, 0.0, -0.4, shaft_top, Color(0.52, 0.52, 0.5), true)
	add_box.call(-sw - T, sw + T, -SHAFT_D - T, -SHAFT_D, -0.4, shaft_top, Color(0.52, 0.52, 0.5), true)
	add_box.call(-sw - T, sw + T, -SHAFT_D - T, 0.0, shaft_top, shaft_top + 0.25, Color(0.45, 0.45, 0.44))
	add_box.call(-sw - T, sw + T, -SHAFT_D - T, 0.0, -0.6, -0.4, Color(0.3, 0.3, 0.3), true)   # pit floor
	# Between the lobby and the hall: the shaft's front is closed above the
	# lobby door and below the hall (landing doors only where you get out).
	add_box.call(-sw - T, sw + T, -T, 0.0, LOBBY_H, top_y - 0.2, Color(0.52, 0.52, 0.5), true)
	# Guide rails.
	for sx: float in [-1.0, 1.0]:
		add_box.call(sx * (sw - 0.08), sx * (sw - 0.02), -SHAFT_D * 0.55, -SHAFT_D * 0.45, -0.4, shaft_top, c_metal)

	# ==================== 3. LIFT HALL on the home's floor ====================
	var hh := Apartments.HALL_HW
	var y := top_y
	var fdw := FRONT_DOOR_W * 0.5
	add_box.call(-hh - T, hh + T, -0.05, HALL_D + T, y - 0.2, y + 0.02, c_floor, true)
	add_box.call(-hh - T, hh + T, -0.05, HALL_D + T, y + HALL_H, y + HALL_H + 0.15, c_trim.lightened(0.35), true)
	for sx: float in [-1.0, 1.0]:
		add_box.call(sx * hh, sx * (hh + T), -T, HALL_D + T, y, y + HALL_H, c_wall, true)
		add_box.call(sx * (hh - 0.02), sx * hh, 0.0, HALL_D, y, y + 0.12, c_trim)
	add_box.call(-hh - T, -dhw, -T, 0.0, y, y + HALL_H, c_wall, true)
	add_box.call(dhw, hh + T, -T, 0.0, y, y + HALL_H, c_wall, true)
	add_box.call(-dhw, dhw, -T, 0.0, y + DOOR_H, y + HALL_H, c_wall, true)
	add_box.call(-dhw - 0.12, -dhw, -0.04, 0.1, y, y + DOOR_H + 0.12, c_metal)
	add_box.call(dhw, dhw + 0.12, -0.04, 0.1, y, y + DOOR_H + 0.12, c_metal)
	add_box.call(-dhw - 0.12, dhw + 0.12, -0.04, 0.1, y + DOOR_H, y + DOOR_H + 0.14, c_metal)
	add_box.call(-0.34, 0.34, 0.0, 0.09, y + DOOR_H + 0.18, y + DOOR_H + 0.44, Color(0.08, 0.09, 0.1))
	# Front wall with the home's front door.
	add_box.call(-hh - T, -fdw, HALL_D, HALL_D + T, y, y + HALL_H, c_wall, true)
	add_box.call(fdw, hh + T, HALL_D, HALL_D + T, y, y + HALL_H, c_wall, true)
	add_box.call(-fdw, fdw, HALL_D, HALL_D + T, y + 2.2, y + HALL_H, c_wall, true)
	for fx: float in [-fdw - 0.07, fdw]:
		add_box.call(fx, fx + 0.07, HALL_D - 0.03, HALL_D + T + 0.03, y, y + 2.27, c_wood.darkened(0.2))
	add_box.call(-fdw - 0.07, fdw + 0.07, HALL_D - 0.03, HALL_D + T + 0.03, y + 2.2, y + 2.27, c_wood.darkened(0.2))
	# A console, a mirror, a doormat and a wall light; the door's number.
	add_box.call(hh - 0.4, hh - 0.02, 0.6, 1.6, y, y + 0.82, c_wood, true)
	add_box.call(hh - 0.04, hh - 0.02, 0.7, 1.5, y + 1.15, y + 1.95, Color(0.76, 0.82, 0.88))
	add_box.call(-0.6, 0.6, HALL_D - 0.7, HALL_D - 0.1, y + 0.02, y + 0.035, Color(0.2, 0.17, 0.15))
	glow_m.solid(-0.7, 0.6, 0.7, 1.4, y + HALL_H - 0.03, y + HALL_H, Color(1.0, 0.93, 0.82))
	var plaque := Label3D.new()
	plaque.text = top_floor_label if tier < 4 else "PENTHOUSE"
	plaque.font_size = 26
	plaque.pixel_size = 0.0032
	plaque.modulate = Color(0.95, 0.86, 0.6)
	plaque.position = Vector3(fdw + 0.35, y + 1.55, HALL_D - 0.01)
	plaque.rotation.y = PI
	add_child(plaque)

	arch._end()
	glass_m._end()
	glow_m._end()
	_add_mesh("Architecture", arch.arrays(), _mat_vcol(0.5, 0.08), 260.0)
	_add_mesh("Glass", glass_m.arrays(), _mat_glass(), 220.0, false)
	_add_mesh("Glow", glow_m.arrays(), _mat_glow(), 220.0, false)
	var body := StaticBody3D.new()
	body.name = "CoreCollision"
	body.collision_layer = CityWorld.HUMAN_LAYER | 1
	body.collision_mask = 0
	for bx in col_boxes:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = bx.size
		cs.shape = sh
		cs.position = bx.position + bx.size * 0.5
		body.add_child(cs)
	add_child(body)

	# ==================== 4. DOORS ====================
	_ent_l = _make_door_leaf("EntDoorL", ehw, Apartments.STREET_DOOR_H - 0.05, 0.05, c_metal, true)
	_ent_l.position = Vector3(-ehw * 0.5, 0.02, L - 0.08)
	add_child(_ent_l)
	_ent_r = _make_door_leaf("EntDoorR", ehw, Apartments.STREET_DOOR_H - 0.05, 0.05, c_metal, true)
	_ent_r.position = Vector3(ehw * 0.5, 0.02, L - 0.08)
	add_child(_ent_r)
	_ent_col = _make_door_blocker("EntDoorCol", Vector3(ehw * 2.0, Apartments.STREET_DOOR_H, 0.14), Vector3(0.0, Apartments.STREET_DOOR_H * 0.5, L - 0.08))
	add_child(_ent_col)
	var leaf_w := DOOR_W * 0.5
	_g_door_l = _make_door_leaf("GroundElevDoorL", leaf_w, DOOR_H, 0.05, c_metal, false)
	_g_door_l.position = Vector3(-leaf_w * 0.5, 0.02, 0.02)
	add_child(_g_door_l)
	_g_door_r = _make_door_leaf("GroundElevDoorR", leaf_w, DOOR_H, 0.05, c_metal, false)
	_g_door_r.position = Vector3(leaf_w * 0.5, 0.02, 0.02)
	add_child(_g_door_r)
	_g_door_col = _make_door_blocker("GroundElevDoorCol", Vector3(DOOR_W, DOOR_H, 0.12), Vector3(0.0, DOOR_H * 0.5, 0.02))
	add_child(_g_door_col)
	_top_door_l = _make_door_leaf("TopElevDoorL", leaf_w, DOOR_H, 0.05, c_metal, false)
	_top_door_l.position = Vector3(-leaf_w * 0.5, y + 0.01, 0.02)
	add_child(_top_door_l)
	_top_door_r = _make_door_leaf("TopElevDoorR", leaf_w, DOOR_H, 0.05, c_metal, false)
	_top_door_r.position = Vector3(leaf_w * 0.5, y + 0.01, 0.02)
	add_child(_top_door_r)
	_top_door_col = _make_door_blocker("TopElevDoorCol", Vector3(DOOR_W, DOOR_H, 0.12), Vector3(0.0, y + DOOR_H * 0.5, 0.02))
	add_child(_top_door_col)
	# The home's front door: a hinged leaf (hinge on the left jamb).
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

	# ==================== 5. BUTTONS, SIGNS, INDICATORS, LIGHT ====================
	_call_g_mat = _make_call_panel(Vector3(dhw + 0.28, 1.15, 0.03), 0.0, "▲")
	_call_top_mat = _make_call_panel(Vector3(dhw + 0.28, y + 1.15, 0.03), 0.0, "▼")
	var sign_lbl := Label3D.new()
	sign_lbl.text = home_name.to_upper()
	sign_lbl.font_size = 40
	sign_lbl.pixel_size = 0.0045
	sign_lbl.modulate = Color(1.0, 0.95, 0.84)
	sign_lbl.outline_size = 8
	sign_lbl.outline_modulate = Color(0.06, 0.06, 0.08)
	sign_lbl.position = Vector3(0.0, Apartments.STREET_DOOR_H + 0.25, L + 1.52)
	add_child(sign_lbl)
	var dir_lbl := Label3D.new()
	dir_lbl.text = "RESIDENTS\nG  · LOBBY\n%s · %s" % [top_floor_label, home_name.to_upper()]
	dir_lbl.font_size = 22
	dir_lbl.pixel_size = 0.0036
	dir_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dir_lbl.modulate = Color(0.95, 0.9, 0.78)
	dir_lbl.outline_size = 4
	dir_lbl.position = Vector3(dhw + 0.95, 1.7, 0.02)
	add_child(dir_lbl)
	_ind_ground = _make_indicator(Vector3(0.0, DOOR_H + 0.36, 0.1), 0.0)
	add_child(_ind_ground)
	_ind_top = _make_indicator(Vector3(0.0, y + DOOR_H + 0.31, 0.1), 0.0)
	add_child(_ind_top)
	var lz := InteriorKit.add_lighting_zone(self, AABB(Vector3(-hw, 0.0, 0.0), Vector3(hw * 2.0, LOBBY_H, L)))
	InteriorKit.room_probe(lz, Color(1.0, 0.92, 0.8), 0.55, 0.2)
	_lobby_light = OmniLight3D.new()
	_lobby_light.position = Vector3(0.0, LOBBY_H - 0.45, L * 0.5)
	_lobby_light.light_color = Color(1.0, 0.9, 0.74)
	InteriorKit.tune_light(_lobby_light, 2.6, maxf(7.0, L * 0.75))
	add_child(_lobby_light)
	var hz := InteriorKit.add_lighting_zone(self, AABB(Vector3(-hh, y, 0.0), Vector3(hh * 2.0, HALL_H, HALL_D)))
	var hall_light := OmniLight3D.new()
	hall_light.position = Vector3(0.0, y + HALL_H - 0.3, HALL_D * 0.5)
	hall_light.light_color = Color(1.0, 0.94, 0.84)
	InteriorKit.tune_light(hall_light, 1.7, 3.8)
	hz.add_child(hall_light)
	_build_cabin(c_wood, c_floor, c_metal, c_trim)


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
	cm.solid(-chw, z0, chw, z1, -0.12, 0.02, c_floor.darkened(0.06))
	cm.solid(-chw, z0, chw, z1, CAB_H, CAB_H + 0.14, c_trim)
	cg.solid(-chw + 0.25, z0 + 0.25, chw - 0.25, z1 - 0.25, CAB_H - 0.03, CAB_H + 0.01, Color(1.0, 0.94, 0.82))
	cm.solid(-chw, z0, -chw + 0.08, z1, 0.02, CAB_H, c_wood)
	cm.solid(chw - 0.08, z0, chw, z1, 0.02, CAB_H, c_wood)
	cm.solid(-chw, z0, chw, z0 + 0.08, 0.02, CAB_H, c_wood.lightened(0.05))           # back wall
	cm.solid(-chw + 0.3, z0 + 0.08, chw - 0.3, z0 + 0.1, 1.0, 2.2, Color(0.76, 0.82, 0.88))  # mirror
	cm.solid(-chw + 0.08, z0 + 0.18, -chw + 0.14, z1 - 0.18, 0.92, 0.97, c_metal)
	cm.solid(chw - 0.14, z0 + 0.18, chw - 0.08, z1 - 0.18, 0.92, 0.97, c_metal)
	cm.solid(-chw + 0.3, z0 + 0.08, chw - 0.3, z0 + 0.14, 0.92, 0.97, c_metal)
	cm.solid(-chw, z1 - 0.08, -dhw, z1, 0.02, CAB_H, c_metal)
	cm.solid(dhw, z1 - 0.08, chw, z1, 0.02, CAB_H, c_metal)
	cm.solid(-dhw, z1 - 0.08, dhw, z1, DOOR_H, CAB_H, c_metal)
	cm.solid(chw - 0.12, z1 - 1.2, chw - 0.07, z1 - 0.6, 0.95, 1.55, Color(0.1, 0.11, 0.13))
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
	_btn_g_mat = _make_cabin_button(Vector3(chw - 0.13, 1.15, z1 - 0.9), "G")
	_btn_top_mat = _make_cabin_button(Vector3(chw - 0.13, 1.38, z1 - 0.9), top_floor_label)
	_ind_cabin = _make_indicator(Vector3(0.0, DOOR_H + 0.13, z1 - 0.1), PI)
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
