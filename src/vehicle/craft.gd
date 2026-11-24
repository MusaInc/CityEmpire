class_name Craft
extends CharacterBody3D
## Helicopters, planes and boats: one body, a state machine per class, the
## same one-thumb controls as the car (EmpireTouch's drive pad / keys):
##   input {active, gas (0..1 held), kick (slide up), brake (0..1 slide down),
##   steer (-1..1)} – set every frame by the game (`controls`).
##
## Helicopter  states landed → spooling → flying (hovering / cruising) → landing
##   hold = fly forward at cruise, up = climb, down = descend, sideways = turn
##   (assisted yaw, banks into it), release = hover in place at this height.
##   Landing is automatic: descend near the ground slowly and it settles.
## Plane       states parked/taxi → takeoff roll → airborne → landing roll
##   on the ground: hold = taxi, up = full power (takeoff), down = wheel
##   brakes, sideways = steer the nosewheel. Rotates on its own past Vr with
##   full power. In the air: hold = cruise level, up = climb, down = descend,
##   sideways = bank and turn, release = level off at cruise. Stall
##   protection keeps it above stall speed (the nose drops, it never falls).
##   Touch down on any paved surface below the landing speed.
## Boat        states moored / under way
##   hold = cruise, up = full speed, down = slow then reverse, sideways =
##   rudder (needs way on, a little at rest), release = coast to a stop in
##   the water's drag. It floats at sea level and bobs; land stops it.
## Visuals: a few dozen boxes per craft (procedural, vertex colours).

const SEA_Y := -1.6
const GROUND_MASK := 1 | (1 << 3)

var kind := "heli"           # heli / plane / boat
var model := ""
var spec := {}
var state := "landed"
var input := {"active": false, "gas": 0.0, "kick": false, "brake": 0.0, "steer": 0.0}
var water_check := Callable()   # (Vector3) -> bool, open water
## Read by the HUD / camera / touch (car-compatible names).
var speed := 0.0
var forward_speed := 0.0
var drift_angle := 0.0
var altitude := 0.0
var rotor := 0.0             # 0..1 spin-up
var throttle := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _roll := 0.0
var _vy := 0.0
var _td_shock := 0.0        # plane touchdown suspension settle impulse
var _visual: Node3D
var _rotor_node: Node3D
var _t := 0.0
var crashed_t := 0.0
var _gear: Node3D
var gear_down := 1.0      # 1 down .. 0 stowed (planes)
## Berths a boat can moor at: [[Vector3, yaw], ...] (the game sets them).
var berths: Array = []
var moored_at := -1
## Where it last stood at rest (landed, parked, stopped on the water):
## saves made in flight keep this, and a crash recovers the craft here.
var rest_xf := Transform3D()
## Open water right under it (helicopters and planes can't set down there:
## the ground ray used to find the sea-floor collision and "land" them under
## the surface, and a crash then recovered them back into the sea).
var over_water := false


func setup(p_kind: String, p_model: String, p_spec: Dictionary) -> void:
	kind = p_kind
	model = p_model
	spec = p_spec
	state = "moored" if kind == "boat" else ("parked" if kind == "plane" else "landed")
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 2) | (1 << 3)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var sz: Vector3 = spec.get("size", Vector3(3, 2, 8))
	bs.size = Vector3(sz.x * (0.5 if kind == "plane" else 0.9), sz.y * 0.7, sz.z * 0.9)
	cs.shape = bs
	cs.position = Vector3(0, sz.y * 0.4, 0)
	add_child(cs)
	_visual = CraftModels.build(kind, model, spec)
	add_child(_visual)
	_rotor_node = _visual.get_node_or_null("Rotor")
	_gear = _visual.get_node_or_null("Gear")
	var au := CraftAudio.new()
	au.name = "Audio"
	add_child(au)
	au.setup(self)
	floor_snap_length = 0.0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING


func place(xf: Transform3D) -> void:
	global_position = xf.origin
	_yaw = xf.basis.get_euler().y
	_pitch = 0.0
	_roll = 0.0
	velocity = Vector3.ZERO
	speed = 0.0
	forward_speed = 0.0
	altitude = 0.0
	_vy = 0.0
	_td_shock = 0.0
	if kind == "boat":
		global_position.y = SEA_Y
	state = "moored" if kind == "boat" else ("parked" if kind == "plane" else "landed")
	crashed_t = 0.0
	throttle = 0.0
	gear_down = 1.0
	if _gear:
		_gear.scale = Vector3.ONE
		_gear.show()
	moored_at = -1
	over_water = false
	_apply_basis()
	rest_xf = global_transform


func forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _apply_basis() -> void:
	global_basis = Basis(Vector3.UP, _yaw)
	if _visual:
		_visual.basis = Basis.from_euler(Vector3(_pitch, 0.0, _roll))


## Ground (or deck/roof) hit dict under p, within `reach` below; empty if none.
func _ground_hit(p: Vector3, reach := 400.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * reach, GROUND_MASK, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)


## Ground (or deck/roof) height under p, within `reach` below; NAN if none.
func ground_below(p: Vector3, reach := 400.0) -> float:
	var hit := _ground_hit(p, reach)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else NAN


## Can the pilot step out here?
func can_exit() -> bool:
	match kind:
		"heli":
			return state == "landed"
		"plane":
			return state in ["parked", "taxi"] and speed < 2.0
		_:
			return speed < 1.5


func hud_text() -> String:
	match kind:
		"heli":
			return "%d kt · %d ft · %s" % [int(speed * 1.944), int(altitude * 3.28), _state_word()]
		"plane":
			return "%d kt · %d ft · %s" % [int(speed * 1.944), int(altitude * 3.28), _state_word()]
	return "%d kt · %s" % [int(speed * 1.944), _state_word()]


func _state_word() -> String:
	return {"landed": "LANDED", "spooling": "SPOOLING UP", "flying": "HOVER" if speed < 3.0 else "FLYING",
		"landing": "LANDING", "parked": "PARKED", "taxi": "TAXI", "roll": "TAKEOFF ROLL", "air": "AIRBORNE",
		"stall": "STALL – NOSE DOWN", "moored": "MOORED" if moored_at >= 0 else "STOPPED", "underway": "UNDER WAY", "crashed": "DAMAGED"}.get(state, state.to_upper())


func _physics_process(dt: float) -> void:
	_t += dt
	if state == "crashed":
		# (Wreck: still until the game recovers it to rest_xf – SkyportPlay.)
		crashed_t = maxf(crashed_t - dt * 0.5, 0.0)
		velocity = Vector3.ZERO
		return
	match kind:
		"heli":
			_heli(dt)
		"plane":
			_plane(dt)
		_:
			_boat(dt)
	var hv := Vector2(velocity.x, velocity.z)
	# (On the ground and on the water: speed over the ground.)
	speed = velocity.length() if (kind == "heli" or state in ["air", "stall"]) else hv.length()
	forward_speed = hv.dot(Vector2(forward().x, forward().z))
	if _rotor_node:
		_rotor_node.rotate_y(dt * 40.0 * rotor)
	CraftModels.animate(_visual, dt, rotor)
	if _gear:
		# Up once well clear of the runway; down for the approach (low and
		# coming down) and always on the ground. Folds up into the body.
		var want := 1.0
		if state in ["air", "stall"] and (altitude > 25.0 and _vy > -1.5 or altitude > 80.0):
			want = 0.0
		gear_down = move_toward(gear_down, want, dt / 2.5)
		_gear.scale = Vector3(1.0, maxf(gear_down, 0.02), 1.0)
		_gear.visible = gear_down > 0.03
	_apply_basis()
	if can_exit() and (kind == "boat" or not over_water):
		rest_xf = global_transform


# ---------------------------------------------------------- helicopter
## The water under p: true when the first thing below is the sea (or the
## sea floor), not a deck, a quay or land.
func _wet_below(p: Vector3, g: float) -> bool:
	if not water_check.is_valid() or not bool(water_check.call(p)):
		return false
	return is_nan(g) or g < SEA_Y + 0.3


func _heli(dt: float) -> void:
	var g := ground_below(global_position, 600.0)
	over_water = _wet_below(global_position, g)
	if over_water:
		g = SEA_Y + 1.5   # (the surface is the floor; it can hover but not set down)
	altitude = global_position.y - g if not is_nan(g) else global_position.y
	var on := bool(input["active"])
	var cruise: float = spec.get("cruise", 38.0)
	var climb: float = spec.get("climb", 7.0)
	match state:
		"landed":
			rotor = move_toward(rotor, 0.0, dt * 0.25)
			velocity = Vector3.ZERO
			if on and (float(input["gas"]) > 0.0 or input["kick"]):
				state = "spooling"
		"spooling":
			rotor = move_toward(rotor, 1.0, dt / float(spec.get("spool", 1.6)))
			if not on:
				state = "landed"
			elif rotor >= 1.0:
				state = "flying"
				_vy = 2.5
		"flying", "landing":
			rotor = 1.0
			# Vertical: up climbs, down descends, otherwise hold height.
			var want_vy := 0.0
			var brk_in := float(input["brake"])
			if input["kick"]:
				want_vy = climb
			elif brk_in > 0.0:
				want_vy = -climb * brk_in
				if altitude < 8.0:
					want_vy = maxf(want_vy, -1.6)   # (flare: gentle near the ground)
			# Ground-effect hover cushion near solid surfaces (< 6 m): adds subtle buoyant
			# lift when hovering or easing down, while allowing crisp landing on full down.
			if not over_water and altitude > 0.3 and altitude < 6.0 and want_vy <= 0.2:
				var ge := clampf(1.0 - altitude / 6.0, 0.0, 1.0)
				if brk_in < 0.25:
					want_vy += ge * 0.42
				elif brk_in < 0.85:
					want_vy *= lerpf(1.0, 0.72, ge)
			_vy = move_toward(_vy, want_vy, dt * 6.0)
			# Forward: holding the pad flies on at cruise; letting go hovers.
			var want_f := cruise if (on and (float(input["gas"]) > 0.0 or input["kick"])) else 0.0
			if brk_in > 0.0:
				want_f = 0.0
			var hv := Vector3(velocity.x, 0.0, velocity.z)
			var target := forward() * want_f
			hv = hv.move_toward(target, dt * float(spec.get("accel", 9.0)))
			var turn := float(input["steer"]) * float(spec.get("yaw", 1.1))
			_yaw = wrapf(_yaw - turn * dt, -PI, PI)
			# Subtle altitude wind sway so hovering high feels alive without fighting input.
			var sway_k := clampf((altitude - 6.0) / 36.0, 0.0, 1.0)
			var sway_pitch := sin(_t * 0.61) * 0.014 * sway_k
			var sway_roll := cos(_t * 0.79) * 0.018 * sway_k
			_pitch = lerpf(_pitch, -0.18 * clampf(want_f / cruise, 0.0, 1.0) + 0.05 * brk_in + sway_pitch, 1.0 - exp(-3.0 * dt))
			_roll = lerpf(_roll, -turn * 0.35 * clampf(hv.length() / 10.0, 0.25, 1.0) + sway_roll, 1.0 - exp(-3.0 * dt))
			var pre_v := Vector3(hv.x, _vy, hv.z)
			velocity = pre_v
			var col := move_and_slide()
			if col and get_slide_collision_count() > 0:
				for i in get_slide_collision_count():
					var n := get_slide_collision(i).get_normal()
					if n.y < 0.55:
						var into := maxf(-pre_v.dot(n), 0.0)
						if into > 12.0:
							_crash()
							return
						var hn := Vector3(n.x, 0.0, n.z)
						if hn.length_squared() > 0.01:
							hn = hn.normalized()
							velocity = velocity.slide(n) + hn * clampf(into * 0.45, 2.0, 6.0)
							global_position += hn * 0.15
						if n.y < -0.5:
							_vy = minf(_vy, -1.5)
							velocity.y = _vy
			var post_hv := Vector3(velocity.x, 0.0, velocity.z)
			# Settles onto the ground when low, slow and coming down.
			if over_water and altitude < 1.0:
				_vy = maxf(_vy, 0.0)
				global_position.y = maxf(global_position.y, g)
			elif altitude < 1.2 and _vy <= 0.2 and post_hv.length() < 6.0:
				state = "landed"
				velocity = Vector3.ZERO
				_vy = 0.0
				_pitch = 0.0
				_roll = 0.0
				if not is_nan(g):
					global_position.y = g
			elif _vy < -0.5 and altitude < 25.0:
				state = "landing"
			else:
				state = "flying"


# --------------------------------------------------------------- plane
## True only when the surface beneath the plane's gear and wingspan is dry,
## level (<= ~16 deg slope) and wide enough for a runway/road touchdown.
func _can_land_plane(g: float) -> bool:
	if is_nan(g) or absf(_roll) >= 0.45:
		return false
	var sz: Vector3 = spec.get("size", Vector3(11.0, 3.0, 8.0))
	var fwd := forward()
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var half_l := clampf(sz.z * 0.45, 3.0, 8.0)
	var span := clampf(sz.x * 0.35, 3.0, 6.0)
	var probes := [
		global_position,
		global_position + fwd * half_l,
		global_position - fwd * half_l,
		global_position + right * span,
		global_position - right * span,
	]
	for pt: Vector3 in probes:
		var hit := _ground_hit(pt + Vector3.UP * 2.0, 8.0)
		if hit.is_empty():
			return false
		var n: Vector3 = hit["normal"]
		var hy: float = (hit["position"] as Vector3).y
		if n.y < 0.96 or _wet_below(pt, hy) or absf(hy - g) > 0.65:
			return false
	return true


func _plane(dt: float) -> void:
	var g := ground_below(global_position + Vector3.UP * 2.0, 800.0)
	over_water = _wet_below(global_position, g)
	if over_water:
		g = SEA_Y
	if over_water and state in ["taxi", "roll", "landing_roll", "parked"]:
		_crash()   # (rolled off the end into the sea)
		return
	altitude = global_position.y - g if not is_nan(g) else global_position.y
	var on := bool(input["active"])
	var vr: float = spec.get("vr", 40.0)
	var stall: float = spec.get("stall", 34.0)
	var cruise: float = spec.get("cruise", 70.0)
	var vmax: float = spec.get("vmax", 95.0)
	var thrust: float = spec.get("thrust", 6.0)
	rotor = move_toward(rotor, 1.0 if on or state == "air" else 0.0, dt * 0.6)
	var fwd := forward()
	var v := maxf(forward_speed, 0.0)
	match state:
		"parked", "taxi", "roll", "landing_roll":
			# Throttle: hold = taxi, up = full; drag and brakes.
			var want_t := 0.0
			if on and input["kick"]:
				want_t = 1.0
			elif on and float(input["gas"]) > 0.0:
				want_t = 0.28
			throttle = move_toward(throttle, want_t, dt * 0.8)
			var acc := thrust * throttle - 0.012 * v * v * 0.1 - 0.35
			if float(input["brake"]) > 0.0:
				acc -= 6.0 * float(input["brake"])
			if throttle < 0.4:
				v = minf(v, 14.0) if want_t > 0.0 else v
			v = maxf(v + acc * dt, 0.0)
			var steer_k := clampf(1.2 - v / 30.0, 0.15, 1.0)
			_yaw = wrapf(_yaw - float(input["steer"]) * 0.7 * steer_k * dt * clampf(v / 3.0, 0.0, 1.0), -PI, PI)
			_roll = lerpf(_roll, 0.0, dt * 4.0)
			state = "parked" if v < 0.3 and throttle < 0.05 else ("roll" if throttle > 0.6 else "taxi")
			# Rotate at Vr with full power: the assisted takeoff.
			_td_shock = move_toward(_td_shock, 0.0, dt * 0.22)
			var target_gpitch := (0.12 if (v > vr * 0.92 and throttle > 0.8) else 0.0) - _td_shock
			_pitch = lerpf(_pitch, target_gpitch, 1.0 - exp(-5.0 * dt))
			if v > vr and throttle > 0.8:
				state = "air"
				_vy = 3.0
			velocity = fwd * v + Vector3.UP * -2.0
			var gcol := move_and_slide()
			if gcol and get_slide_collision_count() > 0 and v > 22.0:
				for i in get_slide_collision_count():
					if get_slide_collision(i).get_normal().y < 0.5:
						_crash()
						return
			if not is_nan(g) and global_position.y > g + 0.05:
				global_position.y = maxf(g, global_position.y - dt * 6.0)
		"air", "stall":
			# Speed: hold = cruise, up = full power and climb, down = descend.
			# Deployed landing gear adds subtle aerodynamic drag on approach.
			var gear_drag := 1.0 - 0.075 * gear_down
			var want_v := (cruise if on else cruise * 0.85) * gear_drag
			var want_vy := 0.0
			if on and input["kick"]:
				want_v = vmax * gear_drag
				want_vy = float(spec.get("climb", 9.0))
			elif float(input["brake"]) > 0.0:
				want_v = lerpf(cruise * gear_drag, stall * 1.12, float(input["brake"]))
				want_vy = -float(spec.get("climb", 9.0)) * 0.9 * float(input["brake"])
			var speed_rate := thrust * (0.6 + 0.22 * gear_down if want_v < v else 0.6)
			v = move_toward(v, want_v, dt * speed_rate)
			if v < stall:
				# Stall protection: nose down, gain speed, never fall out of the sky.
				state = "stall"
				want_vy = -6.0
				v = move_toward(v, stall * 1.1, dt * 8.0)
			else:
				state = "air"
			_vy = move_toward(_vy, want_vy, dt * 5.0)
			var bank := float(input["steer"]) * 0.6
			_roll = lerpf(_roll, -bank, 1.0 - exp(-2.5 * dt))
			_yaw = wrapf(_yaw + _roll * 9.8 / maxf(v, 20.0) * dt * 1.6, -PI, PI)
			_pitch = lerpf(_pitch, clampf(_vy / maxf(v, 20.0), -0.3, 0.35), 1.0 - exp(-3.0 * dt))
			velocity = fwd * v + Vector3.UP * _vy
			var col := move_and_slide()
			# Touching down: low, slow enough, not dropping fast, on a flat wide surface.
			if altitude < 2.5 and _vy < 1.0 and over_water:
				_crash()   # (ditched: no landing on the water)
			elif altitude < 2.5 and _vy < 1.0:
				var land_max: float = float(spec.get("land_max", 62.0))
				var flat_ok := _can_land_plane(g)
				if flat_ok and v < land_max and _vy > -6.0:
					# Soft oleo-strut touchdown compression & bounce damping.
					_td_shock = clampf(absf(_vy) * 0.024, 0.015, 0.11)
					state = "landing_roll"
					_vy = 0.0
					_pitch = -_td_shock * 0.5
					_roll = 0.0
					if not is_nan(g):
						global_position.y = g
				elif not flat_ok and (altitude < 1.0 or _vy <= -3.5 or v >= land_max * 0.85):
					_crash()   # (steep cliff, narrow roof or uneven ground)
				elif not flat_ok or _vy <= -6.0 or v >= land_max:
					_vy = maxf(2.2, absf(_vy) * 0.42)   # (damped bounce: too fast or unsuitable surface)
			if col and get_slide_collision_count() > 0 and v > 25.0:
				var n := get_slide_collision(0).get_normal()
				if n.y < 0.5:
					_crash()


func _crash() -> void:
	state = "crashed"
	velocity = Vector3.ZERO
	crashed_t = 1.0


# ---------------------------------------------------------------- boat
## Multi-point hull shoreline probe (bow, bow shoulders, midship, stern).
## Returns {hits: int, push: Vector3} where push points back toward open water.
func _hull_land_probe(pos: Vector3, yaw: float) -> Dictionary:
	if not water_check.is_valid():
		return {"hits": 0, "push": Vector3.ZERO}
	var sz: Vector3 = spec.get("size", Vector3(2.4, 1.3, 8.0))
	var hl := sz.z * 0.5
	var hw := sz.x * 0.45
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var r := Vector3(cos(yaw), 0.0, -sin(yaw))
	var offsets := [
		f * hl,
		f * (hl * 0.65) + r * hw,
		f * (hl * 0.65) - r * hw,
		r * hw,
		-r * hw,
		-f * (hl * 0.85) + r * (hw * 0.85),
		-f * (hl * 0.85) - r * (hw * 0.85),
		-f * hl,
	]
	var hits := 0
	var push := Vector3.ZERO
	for off: Vector3 in offsets:
		if not bool(water_check.call(pos + off)):
			hits += 1
			push -= off
	push.y = 0.0
	if push.length_squared() > 0.0001:
		push = push.normalized()
	return {"hits": hits, "push": push}


func _boat(dt: float) -> void:
	altitude = 0.0
	var on := bool(input["active"])
	var vmax: float = spec.get("vmax", 18.0)
	var acc: float = spec.get("accel", 3.0)
	var v := forward_speed
	var want := 0.0
	if on and input["kick"]:
		want = vmax
	elif on and float(input["gas"]) > 0.0:
		want = vmax * 0.6
	if float(input["brake"]) > 0.0:
		want = -vmax * 0.3 * float(input["brake"]) if v < 1.5 else 0.0
	if on or float(input["brake"]) > 0.0:
		v = move_toward(v, want, dt * (acc if absf(want) > absf(v) else acc * 1.6))
	else:
		v = move_toward(v, 0.0, dt * (0.35 + 0.04 * absf(v)))   # water drag
	var cur_probe := _hull_land_probe(global_position, _yaw)
	var cur_hits: int = int(cur_probe["hits"])
	var steer := float(input["steer"])
	var prev_yaw := _yaw
	# Steer flips with the boat's direction like a real rudder.
	_yaw = wrapf(_yaw - steer * float(spec.get("turn", 0.6)) * clampf(absf(v) / 5.0, 0.15, 1.0) * signf(v if absf(v) > 0.2 else 1.0) * dt, -PI, PI)
	if cur_hits == 0 and int(_hull_land_probe(global_position, _yaw)["hits"]) > 0:
		_yaw = prev_yaw
	var fwd := forward()
	var sp_norm := clampf(v / maxf(vmax, 1.0), 0.0, 1.0)
	var sz_boat: Vector3 = spec.get("size", Vector3(2.4, 1.3, 8.0))
	var sport_hull := clampf(1.0 - (sz_boat.z - 6.0) / 22.0, 0.25, 1.0)
	# Crisp inward banking into turns (deeper on V-hull sport boats, measured on yachts)
	# and speed-dependent bow planing pitch (hump rise then levelling onto the plane).
	var bank_max := lerpf(0.06, 0.20, sport_hull)
	var target_bank := -steer * bank_max * clampf(absf(v) / maxf(vmax, 1.0), 0.0, 1.0) * signf(v if absf(v) > 0.2 else 1.0)
	_roll = lerpf(_roll, target_bank, 1.0 - exp(-5.0 * dt))
	var hump := sin(clampf(sp_norm * 1.45, 0.0, 1.0) * PI) * 0.055 * sport_hull
	var plane_trim := (0.04 + 0.045 * sport_hull) * smoothstep(0.15, 0.95, sp_norm)
	_pitch = lerpf(_pitch, hump + plane_trim, 1.0 - exp(-3.5 * dt))
	var step_pos := global_position + fwd * v * maxf(dt * 3.0, 0.15)
	var next_probe := _hull_land_probe(step_pos, _yaw)
	var next_hits: int = int(next_probe["hits"])
	var vel_vec := fwd * v
	if next_hits > 0 and (cur_hits == 0 or next_hits >= cur_hits):
		var push: Vector3 = next_probe["push"] if (next_probe["push"] as Vector3).length_squared() > 0.01 else (cur_probe["push"] as Vector3)
		if push.length_squared() > 0.01 and vel_vec.dot(push) < 0.0:
			var head_on := absf(fwd.dot(push))
			vel_vec = Vector3.ZERO if head_on > 0.72 else vel_vec.slide(push) * 0.6
			v = vel_vec.dot(fwd)
		elif push.length_squared() <= 0.01:
			vel_vec = Vector3.ZERO
			v = 0.0
	if cur_hits > 0 and (cur_probe["push"] as Vector3).length_squared() > 0.01:
		vel_vec += (cur_probe["push"] as Vector3) * 1.4
	velocity = Vector3(vel_vec.x, 0.0, vel_vec.z)
	var col := move_and_slide()
	if col and get_slide_collision_count() > 0:
		velocity.y = 0.0
		v = Vector3(velocity.x, 0.0, velocity.z).dot(fwd)
	var plane_lift := smoothstep(0.32, 0.90, sp_norm) * 0.16 * sport_hull
	var bob_k := lerpf(1.0, 0.45, smoothstep(0.35, 0.85, sp_norm))
	global_position.y = SEA_Y + float(spec.get("float", 0.0)) + plane_lift + (0.08 * sin(_t * 1.3) + 0.04 * sin(_t * 2.9)) * bob_k
	state = "underway" if absf(v) > 0.5 else "moored"
	# Docking assist: slow, close to a free berth and nobody on the throttle
	# – slide smoothly into the berth via collision-checked motion.
	moored_at = -1
	if absf(v) < 1.8 and not on:
		var best := -1
		var bd := 12.0
		for i in berths.size():
			var bp: Vector3 = berths[i][0]
			var d := Vector2(bp.x - global_position.x, bp.z - global_position.z).length()
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			var bp2: Vector3 = berths[best][0]
			var k := 1.0 - exp(-1.2 * dt)
			var step := Vector3(bp2.x - global_position.x, 0.0, bp2.z - global_position.z) * k
			var cand_yaw := wrapf(lerp_angle(_yaw, float(berths[best][1]), k), -PI, PI)
			var after_hits := int(_hull_land_probe(global_position + step, cand_yaw)["hits"])
			if after_hits <= cur_hits:
				var dcol := move_and_collide(step)
				if dcol:
					var rem := dcol.get_remainder().slide(dcol.get_normal())
					rem.y = 0.0
					if rem.length_squared() > 1e-6:
						move_and_collide(rem)
				_yaw = cand_yaw
			if Vector2(bp2.x - global_position.x, bp2.z - global_position.z).length() < 1.2:
				moored_at = best
	velocity = Vector3(velocity.x, 0.0, velocity.z)
