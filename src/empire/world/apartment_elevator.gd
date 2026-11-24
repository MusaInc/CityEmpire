class_name ApartmentElevator
extends Node3D
## Complete, seamless 3D apartment access system for a single apartment building:
##   * Ground-floor furnished entrance lobby with animated sliding entrance doors,
##     illuminated nameplate canopy, marble/oak flooring, reception console,
##     seating bench, planters, mailboxes, directory plaque and warm lighting.
##   * Architectural glass-and-metal elevator shaft running smoothly from the
##     ground lobby up to a private upper landing corridor connecting directly
##     into the apartment interior.
##   * Working 3D elevator cabin with twin animated sliding doors (cabin +
##     landings), functional 3D floor-selector panel, live digital floor
##     indicator (Label3D), interior lighting, handrail, mirror, collision
##     detection and realistic sounds (door glide, motor hum, floor ticks, chime).
##
## Local coordinate frame (origin at ground lobby floor on the building facade):
##   +X : along building facade (Apartments.along_dir)
##   +Y : vertically up (world UP)
##   +Z : outward from building facade toward street (Apartments.outward)
##
## Layout along +Z:
##   z = 0.0 .. 2.2  : Elevator shaft & cabin (door opens at z = +2.2 on ground,
##                     and at z = 0.0 on the upper floor into the apartment!)
##   z = 2.2 .. 6.2  : Furnished Ground Lobby (entrance door at z = +6.2)
##   Upper floor (y = top_y):
##     z = 0.0 .. 2.2: Elevator cabin arrives here; back door (z = 0.0) opens
##                     directly onto the private landing corridor into the
##                     apartment (z = 0.0 .. -bridge_len)!

const LOBBY_W := 5.8
const LOBBY_D := 4.0
const LOBBY_H := 3.4
const SHAFT_W := 2.5
const SHAFT_D := 2.2
const CAB_W := 2.24
const CAB_D := 1.96
const CAB_H := 2.55
const DOOR_W := 1.48
const DOOR_H := 2.28
const DOOR_SPEED := 2.1       # full open/close in ~0.48 s
const ENTRANCE_SPEED := 1.8

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
var top_y := 16.0          # local height of apartment floor above ground lobby
var top_floor_num := 5
var top_floor_label := "F05"
var bridge_len := 0.8      # upper corridor length from z=0 inward into apartment

## World-frame origin & basis (stored on self.global_transform)
var _out := Vector3.FORWARD
var _along := Vector3.RIGHT

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
	home_id = String(home["id"])
	home_name = String(home["name"])
	tier = clampi(int(home["tier"]), 0, 4)
	name = "Elevator_" + home_id
	_out = Apartments.outward(h).normalized()
	_along = Apartments.along_dir(h).normalized()
	var wc := Apartments.window_center(h)
	var apt_y := float(h["y0"])
	var base_xz := Vector3(wc.x, ground_y, wc.z)
	bridge_len = 0.9
	if h.has("lift"):
		# Skyport Penthouse has a setback podium: align shaft with ground lift
		# and extend the private glazed sky-corridor at top_y back to the window!
		var lv: Vector3 = h["lift"]
		var along_off := (lv - wc).dot(_along)
		var out_off := maxf((lv - wc).dot(_out), 0.0)
		base_xz = Vector3(wc.x, ground_y, wc.z) + _along * along_off + _out * maxf(out_off - 2.6, 0.0)
		bridge_len = maxf(out_off - 2.6, 0.0) + 1.1
	top_y = maxf(apt_y - ground_y, 3.6)
	top_floor_num = maxi(int(round(top_y / Apartments.FLOOR)), 1)
	top_floor_label = "PH" if tier >= 4 else ("F%02d" % top_floor_num)
	# Local frame: +X = _along, +Y = UP, +Z = _out (right-handed check)
	var right := _along
	if right.cross(Vector3.UP).dot(_out) < 0.0:
		right = -right
	_along = right
	transform = Transform3D(Basis(_along, Vector3.UP, _out), base_xz)
	_build_geometry()
	_sync_doors()
	_update_indicators("G")


## World position of the street-side entrance lobby doorway (compatible with home_lift()).
func street_door_world() -> Vector3:
	return to_global(Vector3(0.0, 0.0, SHAFT_D + LOBBY_D + 0.6))


## World position of the ground lobby elevator call button.
func ground_call_world() -> Vector3:
	return to_global(Vector3(0.0, 0.0, SHAFT_D + 0.75))


## World position of the upper apartment landing elevator call button.
func upper_call_world() -> Vector3:
	return to_global(Vector3(0.0, top_y, -0.75))


## World position of the cabin interior floor button panel.
func cabin_panel_world() -> Vector3:
	return to_global(Vector3(CAB_W * 0.42, cabin_y, SHAFT_D * 0.5))


## World position of the cabin centre at its current height.
func cabin_center_world() -> Vector3:
	return to_global(Vector3(0.0, cabin_y + 0.95, SHAFT_D * 0.5))


## True when a world position (player capsule centre) is physically inside the elevator cabin.
func is_inside_cabin(world_pos: Vector3) -> bool:
	var lp := to_local(world_pos)
	return absf(lp.x) < CAB_W * 0.49 and lp.z > 0.05 and lp.z < SHAFT_D - 0.05 and absf(lp.y - (cabin_y + 0.95)) < 1.35


## True when a world position is inside the ground lobby or upper landing.
func is_inside_lobby(world_pos: Vector3) -> bool:
	var lp := to_local(world_pos)
	if absf(lp.x) < LOBBY_W * 0.52 and lp.z > SHAFT_D - 0.1 and lp.z < SHAFT_D + LOBBY_D + 0.2 and lp.y > -0.3 and lp.y < LOBBY_H:
		return true
	if absf(lp.x) < SHAFT_W * 0.6 and lp.z > -bridge_len - 0.3 and lp.z < 0.2 and absf(lp.y - (top_y + 0.95)) < 1.8:
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
	var dist_sq := p_world.distance_squared_to(to_global(Vector3(0.0, cabin_y + 1.0, SHAFT_D * 0.5)))
	var near := dist_sq < 65.0 * 65.0 or p_world.distance_squared_to(global_position) < 65.0 * 65.0
	if _lobby_light:
		_lobby_light.visible = near
	if _cabin_light:
		_cabin_light.visible = near
	if not near and state in ["idle_g", "idle_top"]:
		return
	var lp := to_local(p_world)
	# 1. Ground entrance sliding glass doors open smoothly on approach.
	var ent_near := absf(lp.x) < 2.2 and lp.z > SHAFT_D + LOBBY_D - 2.2 and lp.z < SHAFT_D + LOBBY_D + 3.4 and absf(lp.y) < 3.0
	var ent_target := 1.0 if ent_near else 0.0
	if absf(_ent_open - ent_target) > 0.005:
		var was_closed := _ent_open < 0.05 and ent_target > 0.5
		_ent_open = move_toward(_ent_open, ent_target, dt * ENTRANCE_SPEED)
		if was_closed:
			Sfx.play("elev_door", -14.0, 1.15)
		_sync_entrance_doors()
	# 2. Auto-open elevator doors when the owner walks up to the waiting cabin!
	if owns and state == "idle_g" and not at_top:
		var at_g_bay := absf(lp.x) < 1.6 and lp.z > SHAFT_D - 0.1 and lp.z < SHAFT_D + 2.4 and absf(lp.y) < 2.6
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
		var at_t_bay := absf(lp.x) < 1.6 and lp.z > -bridge_len - 1.2 and lp.z < 0.3 and absf(lp.y - top_y) < 2.6
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
				pl.z = clampf(pl.z, 0.32, SHAFT_D - 0.32)
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
	var cf := _g_door_open if not at_top and state != "moving" else 0.0
	var cb := _top_door_open if at_top and state != "moving" else 0.0
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
		arch.solid(x0, z0, x1, z1, y0, y1, c)
		if solid:
			col_boxes.append(AABB(Vector3(x0, y0, z0), Vector3(x1 - x0, y1 - y0, z1 - z0)))

	var hw := LOBBY_W * 0.5
	var z_lob0 := SHAFT_D
	var z_lob1 := SHAFT_D + LOBBY_D
	var sw := SHAFT_W * 0.5

	# ==================== 1. GROUND LOBBY ====================
	# Polished floor slab + subtle entrance doormat recess
	add_box.call(-hw - 0.12, hw + 0.12, 0.0, z_lob1 + 0.35, -0.18, 0.02, c_floor, true)
	add_box.call(-1.0, 1.0, z_lob1 - 0.85, z_lob1 - 0.08, 0.02, 0.035, c_trim.darkened(0.25))  # entrance mat
	# Ceiling slab + exterior illuminated architectural canopy
	add_box.call(-hw - 0.16, hw + 0.16, 0.0, z_lob1 + 0.16, LOBBY_H, LOBBY_H + 0.24, c_trim, true)
	add_box.call(-hw - 0.25, hw + 0.25, z_lob1 + 0.12, z_lob1 + 1.35, LOBBY_H - 0.12, LOBBY_H + 0.14, c_trim.darkened(0.1))
	add_box.call(-hw - 0.28, hw + 0.28, z_lob1 + 1.32, z_lob1 + 1.40, LOBBY_H - 0.14, LOBBY_H + 0.16, c_metal)
	# Warm ceiling light panels inside lobby + canopy soffit downlights
	glow_m.solid(-1.6, z_lob0 + 0.9, 1.6, z_lob0 + 1.4, LOBBY_H - 0.04, LOBBY_H, Color(1.0, 0.92, 0.78))
	glow_m.solid(-1.6, z_lob1 - 1.3, 1.6, z_lob1 - 0.8, LOBBY_H - 0.04, LOBBY_H, Color(1.0, 0.92, 0.78))
	glow_m.solid(-1.4, z_lob1 + 0.55, 1.4, z_lob1 + 0.85, LOBBY_H - 0.15, LOBBY_H - 0.11, Color(1.0, 0.90, 0.72))
	# Side walls (solid lower wainscot + glazed upper windows so lobby feels bright & real from street)
	for sx: float in [-1.0, 1.0]:
		var x0 := -hw - 0.14 if sx < 0.0 else hw
		var x1 := -hw if sx < 0.0 else hw + 0.14
		add_box.call(x0, x1, z_lob0, z_lob1, 0.0, 1.15, c_wall, true)
		add_box.call(x0, x1, z_lob0, z_lob0 + 0.9, 1.15, LOBBY_H, c_wall, true)
		add_box.call(x0, x1, z_lob1 - 0.65, z_lob1, 1.15, LOBBY_H, c_wall, true)
		add_box.call(x0, x1, z_lob0, z_lob1, LOBBY_H - 0.35, LOBBY_H, c_wall, true)
		glass_m.solid(x0 + 0.04, z_lob0 + 0.9, x1 - 0.04, z_lob1 - 0.65, 1.15, LOBBY_H - 0.35, Color(0.7, 0.82, 0.9))
		col_boxes.append(AABB(Vector3(x0, 1.15, z_lob0 + 0.9), Vector3(0.14, LOBBY_H - 1.5, z_lob1 - z_lob0 - 1.55)))
	# Front street facade wall around entrance doorway (door opening x = -1.05..+1.05, y = 0..2.45)
	add_box.call(-hw, -1.05, z_lob1 - 0.14, z_lob1, 0.0, 0.85, c_trim, true)
	add_box.call(1.05, hw, z_lob1 - 0.14, z_lob1, 0.0, 0.85, c_trim, true)
	add_box.call(-hw, -1.05, z_lob1 - 0.12, z_lob1, 2.45, LOBBY_H, c_trim, true)
	add_box.call(1.05, hw, z_lob1 - 0.12, z_lob1, 2.45, LOBBY_H, c_trim, true)
	add_box.call(-1.05, 1.05, z_lob1 - 0.14, z_lob1, 2.45, LOBBY_H, c_trim, true)
	glass_m.solid(-hw + 0.08, z_lob1 - 0.09, -1.08, z_lob1 - 0.04, 0.85, 2.45, Color(0.68, 0.80, 0.88))
	glass_m.solid(1.08, z_lob1 - 0.09, hw - 0.08, z_lob1 - 0.04, 0.85, 2.45, Color(0.68, 0.80, 0.88))
	col_boxes.append(AABB(Vector3(-hw, 0.85, z_lob1 - 0.14), Vector3(hw - 1.05, 1.6, 0.14)))
	col_boxes.append(AABB(Vector3(1.05, 0.85, z_lob1 - 0.14), Vector3(hw - 1.05, 1.6, 0.14)))
	# Metal doorway surround
	add_box.call(-1.12, -1.02, z_lob1 - 0.18, z_lob1 + 0.04, 0.0, 2.52, c_metal)
	add_box.call(1.02, 1.12, z_lob1 - 0.18, z_lob1 + 0.04, 0.0, 2.52, c_metal)
	add_box.call(-1.12, 1.12, z_lob1 - 0.18, z_lob1 + 0.04, 2.44, 2.54, c_metal)
	# Inner lobby wall framing the elevator doors (door opening x = -DOOR_W/2 .. +DOOR_W/2)
	var dhw := DOOR_W * 0.5
	add_box.call(-hw, -dhw, z_lob0 - 0.14, z_lob0 + 0.04, 0.0, LOBBY_H, c_wall, true)
	add_box.call(dhw, hw, z_lob0 - 0.14, z_lob0 + 0.04, 0.0, LOBBY_H, c_wall, true)
	add_box.call(-dhw, dhw, z_lob0 - 0.14, z_lob0 + 0.04, DOOR_H, LOBBY_H, c_wall, true)
	# Elevator door surround portal (brushed steel / brass)
	add_box.call(-dhw - 0.12, -dhw, z_lob0 - 0.04, z_lob0 + 0.12, 0.0, DOOR_H + 0.12, c_metal)
	add_box.call(dhw, dhw + 0.12, z_lob0 - 0.04, z_lob0 + 0.12, 0.0, DOOR_H + 0.12, c_metal)
	add_box.call(-dhw - 0.12, dhw + 0.12, z_lob0 - 0.04, z_lob0 + 0.12, DOOR_H, DOOR_H + 0.14, c_metal)
	# Digital floor indicator bezel above ground elevator doors
	add_box.call(-0.34, 0.34, z_lob0 + 0.04, z_lob0 + 0.13, DOOR_H + 0.22, DOOR_H + 0.50, Color(0.08, 0.09, 0.10))

	# ==================== 2. LOBBY FURNITURE & DETAILS ====================
	# Left side: Reception / Concierge console desk + warm desk lamp + directory plaque
	add_box.call(-hw + 0.12, -hw + 0.72, z_lob0 + 1.05, z_lob0 + 2.65, 0.02, 0.96, c_wood, true)
	add_box.call(-hw + 0.08, -hw + 0.78, z_lob0 + 1.0, z_lob0 + 2.7, 0.96, 1.02, c_floor.lightened(0.1))
	add_box.call(-hw + 0.25, -hw + 0.50, z_lob0 + 1.25, z_lob0 + 1.50, 1.02, 1.32, c_metal)
	glow_m.solid(-hw + 0.22, z_lob0 + 1.22, -hw + 0.53, z_lob0 + 1.53, 1.32, 1.50, Color(1.0, 0.84, 0.58))
	# Mailbox bank on inner-left wall beside the elevator
	add_box.call(-hw + 0.32, -dhw - 0.32, z_lob0 + 0.04, z_lob0 + 0.24, 0.95, 2.05, c_metal.darkened(0.18))
	for r in 3:
		for c_i in 3:
			var mx := -hw + 0.42 + float(c_i) * 0.44
			var my := 1.04 + float(r) * 0.32
			add_box.call(mx, mx + 0.36, z_lob0 + 0.23, z_lob0 + 0.26, my, my + 0.24, c_metal)
	# Right side: Upholstered waiting bench + indoor planters
	add_box.call(hw - 0.68, hw - 0.12, z_lob0 + 1.15, z_lob0 + 2.75, 0.02, 0.40, c_wood, true)
	add_box.call(hw - 0.65, hw - 0.14, z_lob0 + 1.18, z_lob0 + 2.72, 0.40, 0.50, c_trim.lightened(0.14))
	# Two indoor planters flanking the elevator lobby
	for px: float in [-hw + 0.42, hw - 0.42]:
		var pz := z_lob1 - 0.52
		add_box.call(px - 0.24, px + 0.24, pz - 0.24, pz + 0.24, 0.02, 0.58, c_trim, true)
		add_box.call(px - 0.20, px + 0.20, pz - 0.20, pz + 0.20, 0.58, 0.64, Color(0.24, 0.18, 0.14))
		add_box.call(px - 0.28, px + 0.28, pz - 0.28, pz + 0.28, 0.64, 1.25, Color(0.20, 0.40, 0.22))
		add_box.call(px - 0.20, px + 0.20, pz - 0.20, pz + 0.20, 1.25, 1.52, Color(0.24, 0.48, 0.25))

	# ==================== 3. ARCHITECTURAL ELEVATOR SHAFT ====================
	# Four vertical steel/brass corner columns from ground to top_y + 3.2 m
	var shaft_top := top_y + 3.1
	for sx: float in [-sw, sw - 0.14]:
		for sz: float in [0.0, SHAFT_D - 0.14]:
			add_box.call(sx, sx + 0.14, sz, sz + 0.14, 0.0, shaft_top, c_trim)
	# Horizontal structural rings every floor (3.6 m) + glazed panoramic shaft panels
	var ry := 3.6
	while ry < shaft_top:
		add_box.call(-sw, sw, SHAFT_D - 0.12, SHAFT_D, ry - 0.08, ry + 0.08, c_metal)
		add_box.call(-sw, -sw + 0.10, 0.0, SHAFT_D, ry - 0.08, ry + 0.08, c_metal)
		add_box.call(sw - 0.10, sw, 0.0, SHAFT_D, ry - 0.08, ry + 0.08, c_metal)
		ry += 3.6
	# Panoramic shaft glass (front & sides above lobby roof)
	glass_m.solid(-sw + 0.12, SHAFT_D - 0.06, sw - 0.12, SHAFT_D - 0.02, LOBBY_H, shaft_top, Color(0.62, 0.76, 0.86))
	glass_m.solid(-sw + 0.02, 0.12, -sw + 0.06, SHAFT_D - 0.12, LOBBY_H, shaft_top, Color(0.62, 0.76, 0.86))
	glass_m.solid(sw - 0.06, 0.12, sw - 0.02, SHAFT_D - 0.12, LOBBY_H, shaft_top, Color(0.62, 0.76, 0.86))
	# Shaft penthouse cap
	add_box.call(-sw - 0.1, sw + 0.1, -0.05, SHAFT_D + 0.1, shaft_top, shaft_top + 0.35, c_trim)

	# ==================== 4. PRIVATE UPPER LANDING CORRIDOR ====================
	# Connects elevator back door (z = 0.0) straight into the apartment (z = -bridge_len)
	var ul_w := SHAFT_W * 0.56
	add_box.call(-ul_w, ul_w, -bridge_len - 0.15, 0.08, top_y - 0.18, top_y + 0.01, c_floor, true)
	add_box.call(-ul_w, ul_w, -bridge_len - 0.15, 0.08, top_y + 2.85, top_y + 3.1, c_trim, true)
	glow_m.solid(-0.65, -bridge_len * 0.65, 0.65, -0.25, top_y + 2.81, top_y + 2.85, Color(1.0, 0.92, 0.78))
	# Upper landing door portal & surround (at z = 0.0, facing -Z into apartment)
	add_box.call(-ul_w, -dhw, -0.08, 0.10, top_y, top_y + 2.88, c_wall, true)
	add_box.call(dhw, ul_w, -0.08, 0.10, top_y, top_y + 2.88, c_wall, true)
	add_box.call(-dhw, dhw, -0.08, 0.10, top_y + DOOR_H, top_y + 2.88, c_wall, true)
	add_box.call(-dhw - 0.10, -dhw, -0.14, 0.04, top_y, top_y + DOOR_H + 0.10, c_metal)
	add_box.call(dhw, dhw + 0.10, -0.14, 0.04, top_y, top_y + DOOR_H + 0.10, c_metal)
	add_box.call(-dhw - 0.10, dhw + 0.10, -0.14, 0.04, top_y + DOOR_H, top_y + DOOR_H + 0.12, c_metal)
	add_box.call(-0.34, 0.34, -0.15, -0.06, top_y + DOOR_H + 0.18, top_y + DOOR_H + 0.44, Color(0.08, 0.09, 0.10))
	# Glass safety balustrades on both sides of the upper private corridor
	for sx: float in [-1.0, 1.0]:
		var bx0 := -ul_w if sx < 0.0 else ul_w - 0.10
		var bx1 := -ul_w + 0.10 if sx < 0.0 else ul_w
		add_box.call(bx0, bx1, -bridge_len, 0.0, top_y, top_y + 0.14, c_trim, true)
		add_box.call(bx0, bx1, -bridge_len, 0.0, top_y + 1.06, top_y + 1.14, c_metal, true)
		glass_m.solid(bx0 + 0.02, -bridge_len, bx1 - 0.02, 0.0, top_y + 0.14, top_y + 1.06, Color(0.70, 0.84, 0.92))
		col_boxes.append(AABB(Vector3(bx0, top_y, -bridge_len), Vector3(0.10, 2.6, bridge_len)))

	arch._end()
	glass_m._end()
	glow_m._end()

	_add_mesh("Architecture", arch.arrays(), _mat_vcol(0.42, 0.18), 260.0)
	_add_mesh("Glass", glass_m.arrays(), _mat_glass(), 220.0, false)
	_add_mesh("Glow", glow_m.arrays(), _mat_glow(), 220.0, false)

	var body := StaticBody3D.new()
	body.name = "LobbyCollision"
	body.collision_layer = CityWorld.HUMAN_LAYER
	body.collision_mask = 0
	for bx in col_boxes:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = bx.size
		cs.shape = sh
		cs.position = bx.position + bx.size * 0.5
		body.add_child(cs)
	add_child(body)

	# ==================== 5. ANIMATED SLIDING DOORS ====================
	# Ground street entrance glass doors (at z = z_lob1 - 0.06)
	_ent_l = _make_door_leaf("EntDoorL", 1.02, 2.42, 0.05, c_metal, true)
	_ent_l.position = Vector3(-0.52, 0.02, z_lob1 - 0.06)
	add_child(_ent_l)
	_ent_r = _make_door_leaf("EntDoorR", 1.02, 2.42, 0.05, c_metal, true)
	_ent_r.position = Vector3(0.52, 0.02, z_lob1 - 0.06)
	add_child(_ent_r)
	_ent_col = _make_door_blocker("EntDoorCol", Vector3(2.1, 2.45, 0.14), Vector3(0.0, 1.24, z_lob1 - 0.06))
	add_child(_ent_col)

	# Ground landing elevator doors (at z = z_lob0)
	var leaf_w := DOOR_W * 0.5
	_g_door_l = _make_door_leaf("GroundElevDoorL", leaf_w, DOOR_H, 0.05, c_metal, false)
	_g_door_l.position = Vector3(-leaf_w * 0.5, 0.02, z_lob0)
	add_child(_g_door_l)
	_g_door_r = _make_door_leaf("GroundElevDoorR", leaf_w, DOOR_H, 0.05, c_metal, false)
	_g_door_r.position = Vector3(leaf_w * 0.5, 0.02, z_lob0)
	add_child(_g_door_r)
	_g_door_col = _make_door_blocker("GroundElevDoorCol", Vector3(DOOR_W, DOOR_H, 0.12), Vector3(0.0, DOOR_H * 0.5, z_lob0))
	add_child(_g_door_col)

	# Upper landing elevator doors (at z = -0.02, y = top_y)
	_top_door_l = _make_door_leaf("TopElevDoorL", leaf_w, DOOR_H, 0.05, c_metal, false)
	_top_door_l.position = Vector3(-leaf_w * 0.5, top_y + 0.01, -0.02)
	add_child(_top_door_l)
	_top_door_r = _make_door_leaf("TopElevDoorR", leaf_w, DOOR_H, 0.05, c_metal, false)
	_top_door_r.position = Vector3(leaf_w * 0.5, top_y + 0.01, -0.02)
	add_child(_top_door_r)
	_top_door_col = _make_door_blocker("TopElevDoorCol", Vector3(DOOR_W, DOOR_H, 0.12), Vector3(0.0, top_y + DOOR_H * 0.5, -0.02))
	add_child(_top_door_col)

	# ==================== 6. CALL BUTTONS & SIGNAGE ====================
	_call_g_mat = _make_call_panel(Vector3(dhw + 0.24, 1.15, z_lob0 + 0.06), 0.0, "▲")
	_call_top_mat = _make_call_panel(Vector3(-dhw - 0.24, top_y + 1.15, -0.09), PI, "▼")

	# Exterior residence nameplate on the canopy
	var sign_lbl := Label3D.new()
	sign_lbl.text = home_name.to_upper()
	sign_lbl.font_size = 42
	sign_lbl.pixel_size = 0.0055
	sign_lbl.modulate = Color(1.0, 0.95, 0.84)
	sign_lbl.outline_size = 8
	sign_lbl.outline_modulate = Color(0.06, 0.06, 0.08)
	sign_lbl.position = Vector3(0.0, LOBBY_H + 0.02, z_lob1 + 1.43)
	add_child(sign_lbl)

	# Lobby floor directory plaque (left wall beside reception)
	var dir_lbl := Label3D.new()
	dir_lbl.text = "DIRECTORY\nG  · LOBBY\n%s · %s" % [top_floor_label, home_name.to_upper()]
	dir_lbl.font_size = 22
	dir_lbl.pixel_size = 0.0038
	dir_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dir_lbl.modulate = Color(0.95, 0.90, 0.78)
	dir_lbl.outline_size = 4
	dir_lbl.position = Vector3(-hw + 0.16, 1.72, z_lob0 + 1.85)
	dir_lbl.rotation.y = PI * 0.5
	add_child(dir_lbl)

	# Digital floor indicators (ground landing & upper landing)
	_ind_ground = _make_indicator(Vector3(0.0, DOOR_H + 0.36, z_lob0 + 0.145), 0.0)
	add_child(_ind_ground)
	_ind_top = _make_indicator(Vector3(0.0, top_y + DOOR_H + 0.31, -0.165), PI)
	add_child(_ind_top)

	# Warm lobby lighting (no shadow casting for mobile GPU budget)
	_lobby_light = OmniLight3D.new()
	_lobby_light.position = Vector3(0.0, LOBBY_H - 0.45, z_lob0 + LOBBY_D * 0.5)
	_lobby_light.light_color = Color(1.0, 0.90, 0.74)
	_lobby_light.light_energy = 1.45
	_lobby_light.omni_range = 8.5
	_lobby_light.shadow_enabled = false
	add_child(_lobby_light)

	# ==================== 7. 3D WORKING ELEVATOR CABIN ====================
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
	var z0 := (SHAFT_D - CAB_D) * 0.5
	var z1 := z0 + CAB_D
	var dhw := DOOR_W * 0.5

	# Cabin floor & ceiling slabs
	cm.solid(-chw, z0, chw, z1, -0.12, 0.02, c_floor.darkened(0.06))
	cm.solid(-chw, z0, chw, z1, CAB_H, CAB_H + 0.14, c_trim)
	# Recessed warm LED ceiling panel
	cg.solid(-chw + 0.25, z0 + 0.25, chw - 0.25, z1 - 0.25, CAB_H - 0.03, CAB_H + 0.01, Color(1.0, 0.94, 0.82))
	# Side walls (wood/marble panelling + stainless handrail)
	cm.solid(-chw, z0, -chw + 0.08, z1, 0.02, CAB_H, c_wood)
	cm.solid(chw - 0.08, z0, chw, z1, 0.02, CAB_H, c_wood)
	# Brushed metal safety handrails along both side walls
	cm.solid(-chw + 0.08, z0 + 0.18, -chw + 0.14, z1 - 0.18, 0.92, 0.97, c_metal)
	cm.solid(chw - 0.14, z0 + 0.18, chw - 0.08, z1 - 0.18, 0.92, 0.97, c_metal)
	# Mirror/accent trim strip on left wall
	cm.solid(-chw + 0.08, z0 + 0.28, -chw + 0.10, z1 - 0.28, 1.12, 2.18, Color(0.76, 0.82, 0.88))
	# Front & back door jamb frames
	for fz: float in [z0, z1 - 0.08]:
		cm.solid(-chw, fz, -dhw, fz + 0.08, 0.02, CAB_H, c_metal)
		cm.solid(dhw, fz, chw, fz + 0.08, 0.02, CAB_H, c_metal)
		cm.solid(-dhw, fz, dhw, fz + 0.08, DOOR_H, CAB_H, c_metal)
	# 3D Floor-selector control panel bezel on right wall
	cm.solid(chw - 0.12, z0 + 0.65, chw - 0.07, z0 + 1.25, 0.95, 1.55, Color(0.10, 0.11, 0.13))
	# Indicator bezel above front door inside cabin
	cm.solid(-0.30, z1 - 0.12, 0.30, z1 - 0.06, DOOR_H + 0.02, DOOR_H + 0.24, Color(0.06, 0.07, 0.09))

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

	# Cabin interior floor buttons (3D glowing discs + labels for G and apartment floor)
	_btn_g_mat = _make_cabin_button(Vector3(chw - 0.13, 1.15, z0 + 0.95), "G")
	_btn_top_mat = _make_cabin_button(Vector3(chw - 0.13, 1.38, z0 + 0.95), top_floor_label)

	# Live digital floor indicator inside the cabin
	_ind_cabin = _make_indicator(Vector3(0.0, DOOR_H + 0.13, z1 - 0.13), PI)
	_cabin.add_child(_ind_cabin)

	# Cabin interior light
	_cabin_light = OmniLight3D.new()
	_cabin_light.position = Vector3(0.0, CAB_H - 0.25, SHAFT_D * 0.5)
	_cabin_light.light_color = Color(1.0, 0.94, 0.84)
	_cabin_light.light_energy = 1.15
	_cabin_light.omni_range = 4.5
	_cabin_light.shadow_enabled = false
	_cabin.add_child(_cabin_light)

	# Cabin sliding doors (front = toward ground lobby, back = toward upper apartment)
	var lw := DOOR_W * 0.5
	_cab_front_l = _make_door_leaf("CabFrontL", lw, DOOR_H, 0.04, c_metal.darkened(0.08), false)
	_cab_front_l.position = Vector3(-lw * 0.5, 0.02, z1 - 0.04)
	_cabin.add_child(_cab_front_l)
	_cab_front_r = _make_door_leaf("CabFrontR", lw, DOOR_H, 0.04, c_metal.darkened(0.08), false)
	_cab_front_r.position = Vector3(lw * 0.5, 0.02, z1 - 0.04)
	_cabin.add_child(_cab_front_r)

	_cab_back_l = _make_door_leaf("CabBackL", lw, DOOR_H, 0.04, c_metal.darkened(0.08), false)
	_cab_back_l.position = Vector3(-lw * 0.5, 0.02, z0 + 0.04)
	_cabin.add_child(_cab_back_l)
	_cab_back_r = _make_door_leaf("CabBackR", lw, DOOR_H, 0.04, c_metal.darkened(0.08), false)
	_cab_back_r.position = Vector3(lw * 0.5, 0.02, z0 + 0.04)
	_cabin.add_child(_cab_back_r)

	# Kinematic collision body for cabin floor, ceiling, side walls & animated door blockers
	var cbody := AnimatableBody3D.new()
	cbody.name = "CabinBody"
	cbody.sync_to_physics = false
	cbody.collision_layer = CityWorld.HUMAN_LAYER
	cbody.collision_mask = 0
	_add_col_box(cbody, Vector3(CAB_W, 0.14, CAB_D), Vector3(0.0, -0.05, SHAFT_D * 0.5))
	_add_col_box(cbody, Vector3(CAB_W, 0.14, CAB_D), Vector3(0.0, CAB_H + 0.07, SHAFT_D * 0.5))
	_add_col_box(cbody, Vector3(0.10, CAB_H, CAB_D), Vector3(-chw + 0.05, CAB_H * 0.5, SHAFT_D * 0.5))
	_add_col_box(cbody, Vector3(0.10, CAB_H, CAB_D), Vector3(chw - 0.05, CAB_H * 0.5, SHAFT_D * 0.5))
	_cab_door_col_f = _add_col_box(cbody, Vector3(CAB_W, CAB_H, 0.10), Vector3(0.0, CAB_H * 0.5, z1 - 0.04))
	_cab_door_col_b = _add_col_box(cbody, Vector3(CAB_W, CAB_H, 0.10), Vector3(0.0, CAB_H * 0.5, z0 + 0.04))
	_cabin.add_child(cbody)


# ---------------------------------------------------------------- helpers
func _add_mesh(nm: String, arr: Array, mat: Material, vis_end: float, cast_sh := true) -> void:
	if arr.is_empty():
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
