class_name Gait
extends RefCounted
## World-space foot placement for ground locomotion (visual only).
##
## A gait clock advances at a cadence picked from the player's real
## horizontal speed. Each foot runs stance → swing on that clock (left at
## phase 0, right at 0.5):
##  * stance: the ankle is LOCKED in the world where it touched down (the hip
##    travels over it, the leg is solved with IK), the heel rolls up over the
##    ball of the foot at the end (toe-off);
##  * swing: the ankle flies from where it lifted to a landing spot predicted
##    from the velocity – ahead of where the hip will be at touchdown by half
##    the ground the stance will cover – arriving with zero world velocity, so
##    it lands where it is and stays there.
## Stance length (duty factor) is capped by how far the legs can reach, so a
## locked foot never has to skate. Turns, diagonals, back-pedalling and slopes
## all fall out of the prediction (it follows the velocity and raycasts the
## landing spot). Standing, both feet stay planted and a foot left out of
## place takes a small settle step. The rig reads the feet (ankle position,
## heading, toe/heel roll, ground normal) and the phase signals used to drive
## pelvis, spine and arms.

const ANKLE_H := 0.05
## Ankle pivot above the ground for this wearer: ANKLE_H, plus the heel
## rise in heeled shoes (CharacterRig.set_heel).
var ankle_h := ANKLE_H
const LEG_LEN := 0.89
const BALL := 0.13
const HEEL := 0.066
const SETTLE_DIST := 0.15
const SETTLE_TIME := 0.3
const START_SPEED := 0.35   # m/s: below this (both feet down) the body stands
const STAND_W := 0.082      # standing feet: half the stance width (m)


class Foot:
	extends RefCounted
	var side := "l"
	var sgn := -1.0           # -1 left, +1 right
	var planted := true
	var pos := Vector3.ZERO   # ankle (planted: lock point, before toe roll)
	var normal := Vector3.UP
	var heading := Vector3.FORWARD
	var from := Vector3.ZERO  # swing: where the ankle lifted
	var from_heading := Vector3.FORWARD
	var target := Vector3.ZERO
	var target_n := Vector3.UP
	var w := 0.0              # swing progress 0..1
	var stance_u := 0.0       # stance progress 0..1
	var toe := 0.0            # heel-up roll about the ball (rad)
	var heel := 0.0           # heel-strike toes-up (rad)
	var td_heel := 0.0        # touchdown heel pitch (continuous handoff from swing)
	var pitch := 0.0          # swing foot pitch relative to level (+ = toes up)
	var settle := false       # standing settle step
	var quick := false        # settle = just putting a foot in the air down where it is
	var cur := Vector3.ZERO   # ankle position this frame (what the rig solves to)
	var lift_toe := 0.0       # heel roll when the foot left the ground
	var world_k := 1.0        # swing: 1 = foot pitch is world-referenced (lift/landing), 0 = relaxed on the shin
	var ease := Vector3.ZERO  # start-up offset eased away (gait begun from a pose off the ground)
	var out := Vector3.ZERO   # cur + ease: the ankle target the rig solves to
	var last_u := 0.0         # clock phase last frame (detects the wrap = touchdown due)
	var due := false          # swing: touchdown time has come
	var rush := INF           # swing: forced touchdown countdown (s) after a dead stop

	func _init(s: String) -> void:
		side = s
		sgn = -1.0 if s == "l" else 1.0


var feet := {"l": Foot.new("l"), "r": Foot.new("r")}
## Touchdowns so far (footstep sounds poll this) and where the last one was.
var touchdowns := 0
var last_touchdown := Vector3.ZERO
var phase := 0.0          # 0..1 gait clock (left touchdown at 0)
var freq := 0.0           # cycles per second
var duty := 0.6           # stance fraction of the cycle
var run := 0.0            # 0 walk … 1 run (gait style)
var everyday := false
var body_type := "a"
var heel_pitch := 0.0
const FOLD_MIN := 0.36    # m: closest an ankle comes to its hip (calf against hamstring)
var sprint := 0.0         # 0..1 above a jog
var moving := false       # stepping (false = standing)
var active := false
var speed := 0.0
var dir := Vector3.FORWARD  # travel direction (horizontal)
var _settle_side := ""
var _stand_t := 0.0
var _prev_speed := 0.0
var _prev_vh := Vector3.ZERO
var _accel_h := Vector3.ZERO
var _peak_speed := 0.0
var _stop_grace := 0.0
var _jolt := 0.0          # s: just stopped dead (wall, collision): feet come straight down


## Steps per second for a horizontal speed (walk ~2/s at 1.4 m/s, jog ~2.8,
## sprint up to ~4.6 – the hero sprints at ~14.5 m/s).
static func cadence(s: float) -> float:
	return clampf(1.55 + 0.36 * s - 0.006 * s * s, 1.5, 5.2)


## Forget everything: the next update starts from the current ankle positions.
## The ground under the feet moved by d (riding a train): planted feet and
## swing paths move with it, so nothing skates or re-steps.
func shift(d: Vector3) -> void:
	if d == Vector3.ZERO:
		return
	for f: Foot in feet.values():
		f.pos += d
		f.from += d
		f.target += d
		f.cur += d
		f.out += d


func reset() -> void:
	active = false
	moving = false
	_settle_side = ""
	_prev_vh = Vector3.ZERO
	_accel_h = Vector3.ZERO
	_peak_speed = 0.0
	_stop_grace = 0.0


## Starts the gait from where the feet are now (landing, end of a get-up,
## respawn). `ankles` side -> world ankle, `ground` callable(at) -> hit dict.
func begin(ankles: Dictionary, facing: Vector3, ground: Callable, vel: Vector3) -> void:
	active = true
	var vh := Vector3(vel.x, 0.0, vel.z)
	dir = vh.normalized() if vh.length() > 0.3 else facing
	# The lower (or further-forward) foot takes the weight first.
	var la: Vector3 = ankles["l"]
	var ra: Vector3 = ankles["r"]
	var lead := "l" if (la.y - ra.y) < -0.03 or ((la - ra).dot(dir) > 0.0 and absf(la.y - ra.y) < 0.03) else "r"
	phase = 0.0 if lead == "l" else 0.5
	speed = vh.length()
	_style(speed)
	_prev_speed = speed
	_prev_vh = vh
	_accel_h = Vector3.ZERO
	_peak_speed = speed
	_stop_grace = 0.0
	_jolt = 0.0
	_stand_t = 0.0
	moving = speed > START_SPEED
	for sd in ["l", "r"]:
		var f: Foot = feet[sd]
		var a: Vector3 = ankles[sd]
		f.heading = facing
		f.toe = 0.0
		f.heel = 0.0
		f.pitch = 0.0
		f.settle = false
		var u := _u(f)
		f.ease = Vector3.ZERO
		var gh: Dictionary = ground.call(a)
		var high := not gh.is_empty() and a.y - (gh.position as Vector3).y - ankle_h > 0.05
		if moving and high:
			# Landing on the run with this foot still in the air: it comes
			# down in a quick step instead of being dragged onto the ground.
			f.planted = false
			f.from = a
			f.from_heading = facing
			f.cur = a
			f.w = 0.0
			f.last_u = u
			f.due = false
			f.rush = 0.07 if sd == lead else 0.16
			f.target = Vector3.ZERO
		elif sd == lead or not moving or u < duty:
			_plant_at(f, a, ground)
			f.ease = (a - f.cur).limit_length(0.5)
			f.stance_u = 0.0 if sd == lead else clampf(u / duty, 0.0, 1.0)
		else:
			f.planted = false
			f.from = a
			f.from_heading = facing
			f.cur = a
			f.w = 0.0
			f.last_u = u
			f.due = false
			f.target = Vector3.ZERO
	_settle_side = ""


func _u(f: Foot) -> float:
	return fposmod(phase + (0.0 if f.side == "l" else 0.5), 1.0)


func _style(s: float) -> void:
	run = smoothstep(2.05, 3.7, s) if everyday else smoothstep(1.9, 3.6, s)
	sprint = smoothstep(4.9, 6.4, s) * 0.35 if everyday else smoothstep(5.0, 12.0, s)


func _plant_at(f: Foot, a: Vector3, ground: Callable) -> void:
	var hit := _sole_hit(ground, a, f.heading, everyday)
	f.planted = true
	f.pos = Vector3(a.x, (hit.position as Vector3).y + ankle_h, a.z) if not hit.is_empty() else a
	var hn: Vector3 = hit.normal if not hit.is_empty() else Vector3.UP
	f.normal = hn.normalized() if hn.length_squared() > 1e-6 else Vector3.UP
	f.cur = f.pos
	f.w = 0.0
	f.due = false
	f.rush = INF


## Advance one frame. `hips`: side -> world hip joint; `centre`: the body's
## ground-level centre (capsule xz); returns nothing – read `feet`.
func update(dt: float, vel: Vector3, facing: Vector3, centre: Vector3, hips: Dictionary, ground: Callable,
		crouch: float) -> void:
	_update(dt, vel, facing, centre, hips, ground, crouch)
	for f: Foot in feet.values():
		f.ease *= exp(-16.0 * dt)
		f.out = f.cur + f.ease


func _update(dt: float, vel: Vector3, facing: Vector3, centre: Vector3, hips: Dictionary, ground: Callable,
		crouch: float) -> void:
	var vh := Vector3(vel.x, 0.0, vel.z)
	speed = vh.length()
	var raw_acc := (vh - _prev_vh) / maxf(dt, 0.001)
	_prev_vh = vh
	_accel_h = _accel_h.lerp(raw_acc.limit_length(25.0), 1.0 - exp(-10.0 * dt))
	# A collision kills the speed far faster than any braking (>40 m/s²).
	if _prev_speed - speed > 40.0 * dt:
		_jolt = 0.3
	_jolt = maxf(_jolt - dt, 0.0)
	_prev_speed = speed
	if speed > START_SPEED * 0.6:
		_peak_speed = maxf(_peak_speed * exp(-1.8 * dt), speed)
	if speed > 0.3:
		var nd := dir.lerp(vh / speed, 1.0 - exp(-14.0 * dt))
		dir = nd.normalized() if nd.length() > 0.2 else vh / speed
	_style(speed)
	var right := Vector3.UP.cross(facing).normalized() * -1.0
	# Reach: how far ahead / behind the hip a stance ankle can be, at the
	# stance hip height (knees flexed a little more at speed).
	# (Hip height at the contacts: walking, the pelvis is lowest there.)
	var hh := LEG_LEN - 0.03 - crouch - lerpf(0.04, 0.015, run)
	var reach_f := sqrt(maxf(LEG_LEN * LEG_LEN - hh * hh, 0.0)) * 0.9
	var toe_max := lerpf(0.55, 0.85, run)
	var hb := hh - BALL * sin(toe_max)
	var reach_b := (sqrt(maxf(LEG_LEN * LEG_LEN - hb * hb, 0.0)) + BALL * (1.0 - cos(toe_max))) * 0.9
	var swinging: bool = not (feet["l"] as Foot).planted or not (feet["r"] as Foot).planted

	# --- start / stop ----------------------------------------------------
	var braking_plant := false
	if not moving:
		if speed > START_SPEED:
			_start(centre, ground)
		else:
			_stand(dt, facing, right, centre, ground, hips)
			return
	elif speed < START_SPEED * 0.6:
		# When decelerating smoothly from a walk/run (not a wall collision), let any
		# in-flight swing foot finish a grounded braking plant step before standing settle.
		if swinging and _jolt <= 0.0 and _peak_speed > 0.9 and _stop_grace < 0.26:
			braking_plant = true
			_stop_grace += dt
			for sd in ["l", "r"]:
				var bf: Foot = feet[sd]
				if not bf.planted:
					bf.rush = minf(bf.rush, 0.14)
		else:
			moving = false
			_stop_grace = 0.0
			_stand_t = 0.0
			_stand(dt, facing, right, centre, ground, hips)
			return
	else:
		_stop_grace = 0.0

	# --- clock -----------------------------------------------------------
	var steps := cadence(maxf(speed, 0.8))
	var heel_k := clampf(1.0 - heel_pitch * 1.4, 0.25, 1.0)
	if everyday:
		steps = lerpf(1.64, 2.22, smoothstep(0.25, 2.0, speed)) + 1.88 * smoothstep(1.9, 6.4, speed)
		if heel_pitch > 0.05:
			steps *= 1.0 + heel_pitch * 0.20
	freq = maxf(steps * 0.5, 0.25)
	var want_duty := lerpf(0.62, 0.43 if everyday else 0.38, run) - 0.1 * sprint
	# Ground covered while a foot is down must fit BOTH front and back leg reach
	# given the front/back split `ahead_frac`, so a planted foot never skates or snaps.
	var cover_max := reach_f + reach_b
	var ahead_frac := lerpf(0.45, 0.37, run) if everyday else lerpf(reach_f / maxf(cover_max, 0.01), 0.35, run)
	var max_cover_f := reach_f / maxf(ahead_frac, 0.1)
	var max_cover_b := reach_b / maxf(1.0 - ahead_frac, 0.1)
	var cover_cap := minf(cover_max, minf(max_cover_f, max_cover_b)) * (0.87 if everyday else 0.96)
	duty = minf(want_duty, cover_cap * freq / maxf(speed, 0.01))
	duty = maxf(duty, 0.12)
	phase = fposmod(phase + freq * dt, 1.0)
	var cover := speed * duty / freq  # m travelled during one stance
	var ahead := cover * ahead_frac
	# Natural human foot track: Jules (narrower frame) walks/runs on a slightly narrower track than Ade.
	var width := (lerpf(0.046, 0.034, run) if body_type == "b" else lerpf(0.058, 0.042, run)) if everyday else lerpf(0.082, 0.032, run)
	var td_heel_nom := lerpf(0.24 if everyday else 0.28, 0.05 if everyday else 0.06, run) * heel_k

	for sd in ["l", "r"]:
		var f: Foot = feet[sd]
		var other: Foot = feet["r" if sd == "l" else "l"]
		var u := _u(f)
		var hip: Vector3 = hips[sd]
		if f.planted:
			f.stance_u = clampf(u / duty, 0.0, 1.0) if u < duty else 1.0
			# Heel strike: start seamlessly from touchdown pitch and roll flat smoothly.
			var heel_base := f.td_heel if f.td_heel > 0.0 else td_heel_nom
			f.heel = (1.0 - smoothstep(0.0, 0.28, f.stance_u)) * heel_base
			# Smooth continuous toe-roll (no discrete while-loop jumps).
			var toe_target := smoothstep(0.52, 1.0, f.stance_u) * toe_max * smoothstep(0.4, 1.6, speed)
			var flat_support := everyday and run < 0.47 and f.stance_u < 0.62
			var a_base := _roll(f.pos, f.heading, f.normal, toe_target)
			if not flat_support:
				var over := a_base.distance_to(hip) - (LEG_LEN - 0.015)
				if over > 0.0:
					toe_target = minf(toe_target + over / (BALL * 0.85), toe_max + 0.2)
			f.toe = move_toward(f.toe, clampf(toe_target, 0.0, toe_max + 0.2), dt * (8.5 if everyday else 11.0))
			var a := _roll(f.pos, f.heading, f.normal, f.toe)
			# Track the ankle around the planted shoe heel during loading (continuous with swing approach).
			if everyday and f.heel > 0.0:
				a += _heel_off(f.heading, f.normal, f.heel)
			f.cur = a
			_pivot(f, facing, dt)
			# Lift: the clock says so, or the body has run away from the foot
			# (a sharp cut, a stop dead): then it's a step, never a skate or a
			# leg hyper-extended behind the hip.
			var rel := a - hip
			var back := -Vector2(rel.x, rel.z).dot(Vector2(facing.x, facing.z))
			var reach_limit := LEG_LEN + (0.043 if flat_support else 0.024)
			var back_lim := 0.72 if everyday else 0.60
			var lost := a.distance_to(hip) > reach_limit or atan2(back, maxf(-rel.y, 0.05)) > back_lim \
				or Vector2(rel.x, rel.z).length() > LEG_LEN * 0.91
			if (u >= duty and not braking_plant) or lost:
				f.planted = false
				f.from = a
				f.from_heading = f.heading
				f.lift_toe = f.toe
				f.pitch = -f.toe
				f.w = 0.0
				f.heel = 0.0
				f.td_heel = 0.0
				f.target = Vector3.ZERO
				f.due = false
				f.rush = INF
				f.last_u = u
		if not f.planted:
			# Time left until this foot's touchdown (its phase wraps to 0). A
			# foot that's late (forced lift, slowing clock) finishes quickly
			# but still smoothly without asymptotic hovering.
			if u < f.last_u - 0.5:
				f.due = true
				f.rush = minf(f.rush, 0.06)
			f.last_u = u
			var left := 0.06 if f.due else (1.0 - u) / freq
			if _jolt > 0.0 or (not braking_plant and speed < (0.65 if everyday else 1.5)):
				f.rush = minf(f.rush, 0.07 + 0.06 * minf(speed, 1.5))  # stopped dead mid-stride: come down now
			if f.rush < INF:
				f.rush -= dt
				left = minf(left, f.rush)
			left = maxf(left, dt)
			f.w = clampf(f.w + (1.0 - f.w) * minf(dt / left, 1.0), 0.0, 1.0)
			# Landing spot: acceleration-aware hip prediction at touchdown, plus
			# half the stance ahead of it, out to this foot's side of the line.
			var side := right * f.sgn * width
			var pred_t := minf(left, 0.45)
			var acc_eff := _accel_h
			if speed > 0.05:
				var v_dir := vh / speed
				var a_along := acc_eff.dot(v_dir)
				if a_along < 0.0 and speed + a_along * pred_t < 0.0:
					# Braking predicts a stop rather than reversing backwards.
					acc_eff -= v_dir * (a_along + speed / maxf(pred_t, 0.001))
			var disp := vh * pred_t + 0.5 * acc_eff * pred_t * pred_t
			var v_end := vh + acc_eff * pred_t
			var end_speed := v_end.length()
			var end_dir := v_end / end_speed if end_speed > 0.25 else dir
			var brake_ahead := clampf(_peak_speed * 0.04, 0.04, 0.15) if braking_plant else 0.0
			var step_ahead := maxf(ahead * clampf(end_speed / maxf(speed, 0.6), 0.15, 1.15) * clampf(speed / 1.0, 0.0, 1.0), brake_ahead)
			var land := centre + disp + end_dir * step_ahead + side
			land.y = f.from.y
			# Straddling a kerb / step edge: move on until the whole sole is on
			# one level (on the step going up, clear of the edge going down).
			var hit := {}
			for i in 4:
				hit = _sole_hit(ground, land + Vector3.UP * 0.3, end_dir, everyday)
				var mid: Dictionary = ground.call(land + Vector3.UP * 0.3)
				if hit.is_empty() or mid.is_empty() or (hit.position as Vector3).y - (mid.position as Vector3).y < 0.03:
					break
				land += end_dir * 0.07
			if not hit.is_empty():
				land.y = (hit.position as Vector3).y + ankle_h
				var tn: Vector3 = hit.normal
				f.target_n = tn.normalized() if tn.length_squared() > 1e-6 else Vector3.UP
			var sharp := _accel_h.length() > 2.5 or braking_plant
			if f.w < 0.85 or f.target == Vector3.ZERO:
				f.target = land  # (frozen for the last part: the foot comes down where it's going)
			elif sharp and f.w < 0.92:
				# Lightly adjust late in swing during sharp turns/braking to prevent skate.
				var adj := (1.0 - smoothstep(0.85, 0.92, f.w)) * (1.0 - exp(-12.0 * dt))
				f.target = f.target.lerp(land, adj)
			# Horizontal: an ease from lift to landing with zero world speed at
			# both ends. Relative to the moving hip that is the runner's path:
			# the foot falls back behind as it lifts, passes under the hip
			# mid-swing and reaches ahead late; running it reaches a little
			# past the landing spot and paws back onto it.
			var e := f.w * f.w * (3.0 - 2.0 * f.w)
			e = lerpf(e, f.w, 0.85 * sprint + (0.14 * run if everyday else 0.0))
			var paw := (0.015 if everyday else 0.08) * run * smoothstep(0.55, 0.82, f.w) * (1.0 - smoothstep(0.82, 1.0, f.w))
			var p := f.from.lerp(f.target, e) + dir * paw
			# Foot pitch: toes stay pointed after push-off, then rise smoothly to match touchdown heel angle.
			var land_pitch := td_heel_nom if everyday else lerpf(0.3, 0.08, run)
			f.pitch = lerpf(-f.lift_toe, land_pitch, smoothstep(0.35, 1.0, f.w))
			f.world_k = clampf(1.0 - smoothstep(0.0, 0.16, f.w) + smoothstep(0.62, 0.95, f.w), 0.0, 1.0)
			if f.rush < INF:
				f.world_k = 1.0
			# Toes along the travel (a touch out), unless backing or side-stepping.
			var travel := facing
			if speed > 0.5 and dir.dot(facing) > 0.5:
				travel = (dir + right * f.sgn * (0.055 if body_type == "b" else 0.075)).normalized()
			f.heading = _yaw_to(f.from_heading, travel, e)
			# Height: natural low clearance walking, athletic (non-marching) knee drive jogging/sprinting.
			var up := f.target.y - f.from.y
			var ey := smoothstep(0.0, 0.52, f.w) if up > 0.0 else smoothstep(0.46, 1.0, f.w)
			p.y = f.from.y + up * ey
			var step_clear := clampf(up * 0.38, 0.0, 0.085)
			var heel_lift_k := clampf(1.0 - heel_pitch * 0.45, 0.72, 1.0)
			var lift_h := (lerpf(0.064 if everyday else 0.095, (0.175 if everyday else 0.25) + 0.045 * sprint, run) * heel_lift_k + step_clear) * clampf(speed / 1.2, 0.35, 1.0)
			var wk := f.w + 0.15 * f.w * (1.0 - f.w)
			var h_walk := pow(sin(PI * wk), 2.0)
			var h_run := smoothstep(0.0, 0.34, f.w) * (1.0 - smoothstep(0.50, 1.0, f.w))
			p.y += lift_h * lerpf(h_walk, h_run, run)
			# Blend in the heel-rocker ankle height on approach so touchdown is 100% continuous (zero 1-frame snap).
			if everyday and f.pitch > 0.0:
				var appr := smoothstep(0.58, 1.0, f.w)
				var tn := f.target_n if f.target_n.length_squared() > 1e-6 else Vector3.UP
				p += _heel_off(f.heading, tn, f.pitch) * appr
			# Never further than the leg reaches from where the hip is now.
			var rel := p - hip
			var swing_reach := LEG_LEN - (lerpf(0.028, 0.055, run) if everyday else 0.012)
			if rel.length() > swing_reach:
				p = hip + rel.normalized() * swing_reach
			# ...and never closer than a fully folded leg allows.
			var rh := Vector2(rel.x, rel.z).length()
			if rh < FOLD_MIN:
				p.y = minf(p.y, hip.y - sqrt(FOLD_MIN * FOLD_MIN - rh * rh))
			var g := _sole_hit(ground, p, f.heading, everyday)
			if not g.is_empty():
				p.y = maxf(p.y, (g.position as Vector3).y + ankle_h + 0.01 * sin(PI * f.w))
			f.cur = p
			f.toe = 0.0
			if f.w >= 0.985 or ((f.due or f.rush < INF) and f.w > 0.98):
				# Touchdown: avoid hard-jumping phase while the opposite foot is mid-stance.
				if not f.due and not other.planted:
					phase = 0.0 if f.side == "l" else 0.5
				f.planted = true
				f.normal = f.target_n.normalized() if f.target_n.length_squared() > 1e-6 else Vector3.UP
				f.heading = (f.heading - f.normal * f.heading.dot(f.normal)).normalized()
				f.td_heel = clampf(f.pitch, 0.0, td_heel_nom) if everyday else td_heel_nom
				f.heel = f.td_heel
				var flat_pos := f.cur - (_heel_off(f.heading, f.normal, f.heel) if everyday and f.heel > 0.0 else Vector3.ZERO)
				f.pos = flat_pos
				touchdowns += 1
				last_touchdown = f.cur
				if f.target != Vector3.ZERO and Vector2(flat_pos.x - f.target.x, flat_pos.z - f.target.z).length() < 0.07:
					f.pos.y = f.target.y
				else:
					var h := _sole_hit(ground, flat_pos + Vector3.UP * 0.3, f.heading, everyday)
					if not h.is_empty():
						f.pos.y = (h.position as Vector3).y + ankle_h
						var hn: Vector3 = h.normal
						f.normal = hn.normalized() if hn.length_squared() > 1e-6 else Vector3.UP
						f.heading = (f.heading - f.normal * f.heading.dot(f.normal)).normalized()
				f.cur = f.pos + (_heel_off(f.heading, f.normal, f.heel) if everyday and f.heel > 0.0 else Vector3.ZERO)
				f.w = 0.0
				f.due = false
				f.rush = INF
				f.world_k = 1.0
				f.stance_u = 0.0


## Leaving a standstill: the foot that's further back along the travel lifts
## first; the clock is set so it's just at toe-off.
func _start(centre: Vector3, _ground: Callable) -> void:
	moving = true
	var l: Foot = feet["l"]
	var r: Foot = feet["r"]
	var first := "l" if (l.pos - r.pos).dot(dir) < 0.0 else "r"
	_style(speed)
	var d := maxf(lerpf(0.62, 0.38, run), 0.55)
	duty = d
	phase = fposmod(d - 0.001 - (0.0 if first == "l" else 0.5), 1.0)
	for f: Foot in [l, r]:
		f.settle = false
		if not f.planted:
			_land_now(f)
	_settle_side = ""


func _land_now(f: Foot) -> void:
	f.planted = true
	f.pos = f.cur
	f.w = 0.0


## Standing: feet stay put; one at a time, a foot well out of its rest spot
## (after a stop, a landing, a turn on the spot) steps back under the hips.
func _stand(dt: float, facing: Vector3, right: Vector3, centre: Vector3, ground: Callable, hips: Dictionary) -> void:
	_stand_t += dt
	for sd in ["l", "r"]:
		var f: Foot = feet[sd]
		if not f.planted and not f.settle:
			# Still in the air from the last stride: just put it down.
			f.settle = true
			f.quick = true
			f.from = f.cur
			f.from_heading = f.heading
			f.w = 0.0
			_settle_side = sd
	# A planted foot the leg can't reach any more (knocked back off a wall)
	# steps in at once.
	for sd in ["l", "r"]:
		var f: Foot = feet[sd]
		if f.planted and f.cur.distance_to(hips[sd]) > LEG_LEN + 0.01:
			f.settle = true
			f.quick = true
			f.planted = false
			f.from = f.cur
			f.from_heading = f.heading
			f.w = 0.0
			_settle_side = sd
	var settle_delay := 0.07 if _peak_speed > 0.9 else 0.12
	if _settle_side == "" and _stand_t > settle_delay:
		var worst := ""
		var far := SETTLE_DIST
		for sd in ["l", "r"]:
			var f: Foot = feet[sd]
			var rest := _standing_spot(centre, facing, right, f)
			var off := Vector2(f.pos.x - rest.x, f.pos.z - rest.z).length()
			var twist := absf(f.heading.signed_angle_to(facing, Vector3.UP))
			if everyday:
				off += maxf(twist - 0.23, 0.0) * 0.23
			if off > far or (not everyday and twist > 0.9):
				far = maxf(off, far)
				worst = sd
		if worst != "":
			var f: Foot = feet[worst]
			f.settle = true
			f.quick = false
			f.planted = false
			f.from = f.cur
			f.from_heading = f.heading
			f.w = 0.0
			_settle_side = worst
		else:
			_peak_speed = move_toward(_peak_speed, 0.0, dt * 4.0)
	for sd in ["l", "r"]:
		var f: Foot = feet[sd]
		if f.planted:
			f.toe = move_toward(f.toe, 0.0, dt * 4.0)
			f.heel = move_toward(f.heel, 0.0, dt * 4.0)
			f.cur = _roll(f.pos, f.heading, f.normal, f.toe)
			f.stance_u = 0.5
			continue
		var step_dur := (0.10 if _jolt > 0.0 else 0.16) if f.quick else SETTLE_TIME
		f.w = minf(f.w + dt / step_dur, 1.0)
		var rest := _standing_spot(centre, facing, right, f)
		rest.y = f.from.y
		var hit: Dictionary = _sole_hit(ground, rest + Vector3.UP * 0.3, facing, true) if everyday \
				else ground.call(rest + Vector3.UP * 0.3)
		if not hit.is_empty():
			rest.y = (hit.position as Vector3).y + ankle_h
		var e := smoothstep(0.0, 1.0, f.w)
		var p := f.from.lerp(rest, e)
		p.y = lerpf(f.from.y, rest.y, e) + sin(PI * f.w) * (0.035 if f.quick else 0.06)
		f.cur = p
		var toe_out := facing.rotated(Vector3.UP, -.105 * f.sgn) if everyday else facing
		f.heading = _yaw_to(f.from_heading, toe_out, e)
		f.pitch = 0.14 * sin(PI * f.w)
		f.world_k = 1.0
		f.toe = 0.0
		if f.w >= 1.0:
			_plant_at(f, p, ground)
			f.settle = false
			_settle_side = ""
			_stand_t = 0.0
			_peak_speed = move_toward(_peak_speed, 0.0, 1.2)


func _standing_spot(centre: Vector3, facing: Vector3, right: Vector3, foot: Foot) -> Vector3:
	var sw := STAND_W * (0.85 if body_type == "b" else 1.0) if everyday else STAND_W
	var spot := centre + right * foot.sgn * sw
	return spot + facing * foot.sgn * (0.022 if body_type == "b" else 0.026) if everyday else spot


## A locked foot keeps its heading while the body turns over it, smoothly
## easing yaw realignment past ~35° of twist instead of snapping.
func _pivot(f: Foot, facing: Vector3, dt: float) -> void:
	var n := f.normal.normalized() if f.normal.length_squared() > 1e-6 else Vector3.UP
	f.normal = n
	var proj := facing - n * facing.dot(n)
	if proj.length_squared() < 1e-6:
		return
	var face := proj.normalized()
	var ang := f.heading.signed_angle_to(face, n)
	var limit := 0.62 if everyday else 0.60
	if absf(ang) > limit:
		var excess := ang - signf(ang) * limit
		var step := excess * (1.0 - exp(-12.0 * dt))
		# Hard anatomical ceiling so extreme whip turns never hyper-twist the ankle.
		var hard := 0.85
		if absf(ang - step) > hard:
			step = ang - signf(ang) * hard
		f.heading = f.heading.rotated(n, step)


func _heel_off(heading: Vector3, normal: Vector3, heel_ang: float) -> Vector3:
	return normal * (HEEL * sin(heel_ang) + ankle_h * (cos(heel_ang) - 1.0)) \
		- heading * (ankle_h * sin(heel_ang) + HEEL * (1.0 - cos(heel_ang)))


## How far forward (+1) / back (-1) the left leg is in the cycle; the right
## leg is the opposite. Peaks at the left foot's touchdown.
func left_forward() -> float:
	if not moving:
		return 0.0
	# Touchdown at phase 0, toe-off at `duty`, back at its furthest there.
	var u := fposmod(phase, 1.0)
	if u < duty:
		return cos(PI * u / duty)          # 1 at touchdown → -1 at toe-off
	return -cos(PI * (u - duty) / (1.0 - duty))  # swinging through


## Step phase 0..1 (0 = a touchdown, either foot).
func step_phase() -> float:
	return fposmod(phase * 2.0, 1.0)


static func _roll(ankle: Vector3, f: Vector3, n: Vector3, toe: float) -> Vector3:
	if toe <= 0.0:
		return ankle
	return ankle + n * sin(toe) * BALL + f * (1.0 - cos(toe)) * BALL


## Turns horizontal direction `a` toward `b` by fraction `t` (safe for
## opposite directions, unlike slerp).
static func _yaw_to(a: Vector3, b: Vector3, t: float) -> Vector3:
	var ah := Vector3(a.x, 0.0, a.z).normalized()
	var bh := Vector3(b.x, 0.0, b.z).normalized()
	if ah.length_squared() < 0.5:
		return bh
	if bh.length_squared() < 0.5:
		return ah
	return ah.rotated(Vector3.UP, ah.signed_angle_to(bh, Vector3.UP) * t)


## Highest ground under the whole sole (heel, ankle, ball): a foot over a
## kerb or step edge rests on the higher side instead of sinking into it.
static func _sole_hit(ground: Callable, at: Vector3, heading: Vector3, width := false) -> Dictionary:
	var hd := Vector3(heading.x, 0.0, heading.z).normalized()
	var best: Dictionary = ground.call(at)
	for off: float in [0.13, -0.07]:
		var h: Dictionary = ground.call(at + hd * off)
		if not h.is_empty() and (best.is_empty() or (h.position as Vector3).y > (best.position as Vector3).y + 0.005):
			best = h
	if width:
		var side := hd.cross(Vector3.UP)
		for off: float in [-0.045, 0.045]:
			var h: Dictionary = ground.call(at + side * off)
			if not h.is_empty() and (best.is_empty() or (h.position as Vector3).y > (best.position as Vector3).y + 0.018):
				best = h
	return best
