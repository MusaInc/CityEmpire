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
	_vy = 0.0
	if kind == "boat":
		global_position.y = SEA_Y
	state = "moored" if kind == "boat" else ("parked" if kind == "plane" else "landed")
	crashed_t = 0.0
	throttle = 0.0
	_apply_basis()
	rest_xf = global_transform


func forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _apply_basis() -> void:
	global_basis = Basis(Vector3.UP, _yaw)
	if _visual:
		_visual.basis = Basis.from_euler(Vector3(_pitch, 0.0, _roll))


## Ground (or deck/roof) height under p, within `reach` below; NAN if none.
func ground_below(p: Vector3, reach := 400.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * reach, GROUND_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
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
	if can_exit():
		rest_xf = global_transform


# ---------------------------------------------------------- helicopter
func _heli(dt: float) -> void:
	var g := ground_below(global_position, 600.0)
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
			if input["kick"]:
				want_vy = climb
			elif float(input["brake"]) > 0.0:
				want_vy = -climb * float(input["brake"])
				if altitude < 8.0:
					want_vy = maxf(want_vy, -1.6)   # (flare: gentle near the ground)
			_vy = move_toward(_vy, want_vy, dt * 6.0)
			# Forward: holding the pad flies on at cruise; letting go hovers.
			var want_f := cruise if (on and (float(input["gas"]) > 0.0 or input["kick"])) else 0.0
			if float(input["brake"]) > 0.0:
				want_f = 0.0
			var hv := Vector3(velocity.x, 0.0, velocity.z)
			var target := forward() * want_f
			hv = hv.move_toward(target, dt * float(spec.get("accel", 9.0)))
			var turn := float(input["steer"]) * float(spec.get("yaw", 1.1))
			_yaw += turn * dt
			_pitch = lerpf(_pitch, -0.18 * clampf(want_f / cruise, 0.0, 1.0) + 0.05 * float(input["brake"]), 1.0 - exp(-3.0 * dt))
			_roll = lerpf(_roll, -turn * 0.35 * clampf(hv.length() / 10.0, 0.25, 1.0), 1.0 - exp(-3.0 * dt))
			velocity = Vector3(hv.x, _vy, hv.z)
			move_and_slide()
			# Settles onto the ground when low, slow and coming down.
			if altitude < 1.2 and _vy <= 0.2 and hv.length() < 6.0:
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
func _plane(dt: float) -> void:
	var g := ground_below(global_position + Vector3.UP * 2.0, 800.0)
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
			_yaw += float(input["steer"]) * 0.7 * steer_k * dt * clampf(v / 3.0, 0.0, 1.0)
			_roll = lerpf(_roll, 0.0, dt * 4.0)
			state = "parked" if v < 0.3 and throttle < 0.05 else ("roll" if throttle > 0.6 else "taxi")
			# Rotate at Vr with full power: the assisted takeoff.
			_pitch = lerpf(_pitch, 0.12 if (v > vr * 0.92 and throttle > 0.8) else 0.0, dt * 2.0)
			if v > vr and throttle > 0.8:
				state = "air"
				_vy = 3.0
			velocity = fwd * v + Vector3.UP * -2.0
			move_and_slide()
			if not is_nan(g) and global_position.y > g + 0.05:
				global_position.y = maxf(g, global_position.y - dt * 6.0)
		"air", "stall":
			# Speed: hold = cruise, up = full power and climb, down = descend.
			var want_v := cruise if on else cruise * 0.85
			var want_vy := 0.0
			if on and input["kick"]:
				want_v = vmax
				want_vy = float(spec.get("climb", 9.0))
			elif float(input["brake"]) > 0.0:
				want_v = lerpf(cruise, stall * 1.15, float(input["brake"]))
				want_vy = -float(spec.get("climb", 9.0)) * 0.9 * float(input["brake"])
			v = move_toward(v, want_v, dt * thrust * 0.6)
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
			_yaw += -_roll * 9.8 / maxf(v, 20.0) * dt * 1.6
			_pitch = lerpf(_pitch, clampf(_vy / maxf(v, 20.0), -0.3, 0.35), 1.0 - exp(-3.0 * dt))
			velocity = fwd * v + Vector3.UP * _vy
			var col := move_and_slide()
			# Touching down: low, slow enough, not dropping fast, on something flat.
			if altitude < 2.5 and _vy < 1.0:
				if v < float(spec.get("land_max", 62.0)) and _vy > -6.0:
					state = "landing_roll"
					_vy = 0.0
					_pitch = 0.0
					_roll = 0.0
					if not is_nan(g):
						global_position.y = g
				elif _vy <= -6.0 or v >= float(spec.get("land_max", 62.0)):
					_vy = 2.0   # (a firm bounce: too fast to land)
			if col and get_slide_collision_count() > 0 and v > 25.0:
				var n := get_slide_collision(0).get_normal()
				if n.y < 0.5:
					_crash()


func _crash() -> void:
	state = "crashed"
	velocity = Vector3.ZERO
	crashed_t = 1.0


# ---------------------------------------------------------------- boat
func _boat(dt: float) -> void:
	altitude = 0.0
	var on := bool(input["active"])
	var vmax: float = spec.get("vmax", 18.0)
	var acc: float = spec.get("accel", 3.0)
	var fwd := forward()
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
	var steer := float(input["steer"])
	_yaw += -steer * float(spec.get("turn", 0.6)) * clampf(absf(v) / 5.0, 0.15, 1.0) * signf(v if absf(v) > 0.2 else 1.0) * dt
	_roll = lerpf(_roll, steer * 0.08 * clampf(absf(v) / vmax, 0.0, 1.0), dt * 3.0)
	_pitch = lerpf(_pitch, 0.07 * clampf(v / vmax, 0.0, 1.0), dt * 2.0)
	var next := global_position + fwd * v * dt * 4.0
	if water_check.is_valid() and not bool(water_check.call(next)):
		v = 0.0   # (ran into the shore)
	velocity = fwd * v
	move_and_slide()
	global_position.y = SEA_Y + float(spec.get("float", 0.0)) + 0.08 * sin(_t * 1.3) + 0.04 * sin(_t * 2.9)
	state = "underway" if absf(v) > 0.5 else "moored"
	# Docking assist: slow, close to a free berth and nobody on the throttle
	# – the boat eases into the berth and lines up with it.
	moored_at = -1
	if absf(v) < 1.8 and not bool(input.get("active", false)):
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
			global_position.x = lerpf(global_position.x, bp2.x, k)
			global_position.z = lerpf(global_position.z, bp2.z, k)
			_yaw = lerp_angle(_yaw, float(berths[best][1]), k)
			if bd < 1.2:
				moored_at = best
	# Steer flips with the boat's direction like a real rudder.
	_yaw = wrapf(_yaw, -PI, PI)
	velocity = fwd * v
