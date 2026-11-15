class_name EmpireTouch
extends Control
## Phone controls (landscape). Three contexts, only what each one needs:
##
##  * On foot. Left half: a floating stick (walk). Right half: drag to look.
##    ACTION (shows the current prompt's verb) and JUMP, bottom right.
##  * Driving. Left half: the same floating stick steers (its x only).
##    Right: ONE drive pad (Never Stop's smart stick, made for ordinary
##    driving). Put a thumb down anywhere on the right that isn't a button:
##      hold            = drive on (part throttle: easy to place the car)
##      slide up        = more throttle, past KICK_PX full throttle + kickdown
##      slide down a bit= lift off (coast, engine braking)
##      slide down more = brake, harder the further you pull (held at a
##                        standstill = reverse, as with the brake pedal)
##      slide sideways  = drift: only above DRIFT_SPEED, the rear wheels are
##                        unlocked again once the car is sliding (a
##                        controlled slide, not a spin); with the left thumb
##                        free it steers too
##      let go          = coast (the car's engine braking slows it)
##    A small tick (haptic) marks each zone change. A small round button
##    above the pad is the contextual action (OUT when slow enough, or what
##    the prompt says): there is no separate exit button.
##  * Panels (phone, shop management) take the screen: nothing is drawn.
## Everything writes the same inputs the keyboard and pads use (Input
## actions on foot, DriveInput's touch_* fields in a car).

var ui: EmpireUI
var action_text := ""
var _stick_id := -1
var _stick_o := Vector2.ZERO
var _stick_v := Vector2.ZERO
var _look_id := -1
var _look_last := Vector2.ZERO
var _held := {}   # touch index -> button name
const R := 70.0

## Drive pad (canvas px at k = 1).
const PAD_R := 112.0
const LIFT_PX := 18.0        # below the landing point: lift off
const BRAKE_PX := 38.0       # further down: brake, progressive to PAD_R
const KICK_PX := 56.0        # up this far: full throttle + kickdown
const DRIFT_PX := 74.0       # sideways this far (deliberate)
const HOLD_THROTTLE := 0.68
const DRIFT_SPEED := 9.0     # m/s (~20 mph): no handbrake turns while parking
var _pad_id := -1
var _pad_o := Vector2.ZERO
var _pad_p := Vector2.ZERO
var _pad_zone := ""
var _drifting := false
## What the pad is doing now (drawn, and read by tests).
var pad := {"gas": 0.0, "brake": 0.0, "kick": false, "drift": false, "steer": 0.0, "zone": ""}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_physics_priority = -20  # (the drift handbrake, before DriveInput reads it)


## The screen minus the notch / Dynamic Island / home indicator (the HUD's
## rect: EmpireUI insets it by the display's safe area).
func _safe() -> Rect2:
	if ui != null and ui.hud != null:
		return ui.hud.get_global_rect()
	return get_viewport_rect()


## Control scale: tablets draw canvas units physically bigger, so bring the
## controls (and thumb travel) back toward phone size there.
func ui_k() -> float:
	var vp := get_viewport_rect().size
	return clampf(lerpf(1.0, 0.82, clampf((vp.x / maxf(vp.y, 1.0) - 2.0) / -0.6, 0.0, 1.0)), 0.8, 1.0)


func _driving() -> bool:
	return ui.game != null and ui.game.driving != ""


func _car() -> Car:
	return ui.game.cars.get(ui.game.driving) if _driving() else null


func pad_home() -> Vector2:
	var s := _safe().end
	var k := ui_k()
	return s - Vector2(PAD_R + 58.0, PAD_R + 46.0) * k


func _buttons() -> Dictionary:
	var sr := _safe()
	var s := sr.end  # (positions below are from the safe area's far corner)
	var k := ui_k()
	var out := {}
	if _driving():
		# Only when there is something to do (OUT needs the car slow).
		if action_text != "":
			var h := pad_home()
			out["action"] = Rect2(h + Vector2(-PAD_R - 40.0, -PAD_R - 70.0) * k, Vector2(92, 92) * k)
	else:
		out["action"] = Rect2(s.x - 200 * k, s.y - 220 * k, 160 * k, 160 * k)
		out["jump"] = Rect2(s.x - 330 * k, s.y - 140 * k, 100 * k, 100 * k)
	return out


func _input(event: InputEvent) -> void:
	if not visible or ui.panel_open() or ui.game == null or ui.game.state != "play":
		return
	var w := get_viewport_rect().size.x
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var bs := _buttons()
			for k in bs:
				if (bs[k] as Rect2).grow(14).has_point(t.position):
					_held[t.index] = k
					_press(k, true)
					get_viewport().set_input_as_handled()
					queue_redraw()
					return
			if t.position.x < w * 0.45 and _stick_id < 0:
				_stick_id = t.index
				_stick_o = t.position
				_stick_v = Vector2.ZERO
			elif _driving() and t.position.x >= w * 0.5 and _pad_id < 0:
				_pad_id = t.index
				_pad_o = t.position
				_pad_p = t.position
				_pad_zone = ""
				_drifting = false
				_apply_pad()
			elif _look_id < 0:
				_look_id = t.index
				_look_last = t.position
		else:
			if _held.has(t.index):
				_press(_held[t.index], false)
				_held.erase(t.index)
			if t.index == _stick_id:
				_stick_id = -1
				_stick_v = Vector2.ZERO
				_apply_stick()
			if t.index == _pad_id:
				_pad_id = -1
				_apply_pad()
			if t.index == _look_id:
				_look_id = -1
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_id:
			_stick_v = ((d.position - _stick_o) / R).limit_length(1.0)
			_apply_stick()
			queue_redraw()
		elif d.index == _pad_id:
			_pad_p = d.position
			# The landing point follows a thumb that wanders well past full
			# travel, so pulling back always responds at once.
			var so := _pad_p - _pad_o
			var lim := PAD_R * ui_k() * 1.35
			if so.length() > lim:
				_pad_o = _pad_p - so.normalized() * lim
			_apply_pad()
		elif d.index == _look_id:
			ui.game.camera.add_touch_look(d.position - _look_last, w)
			_look_last = d.position


func _press(k: String, on: bool) -> void:
	match k:
		"action":
			if on:
				ui.game.act()
		"jump":
			if on:
				Input.action_press("jump")
			else:
				Input.action_release("jump")


func _apply_stick() -> void:
	var v := _stick_v
	for a in ["move_left", "move_right", "move_forward", "move_back", "steer_left", "steer_right"]:
		Input.action_release(a)
	if v.length() < 0.08:
		_steer_from_pad()
		return
	if v.x < 0.0:
		Input.action_press("move_left", -v.x)
		Input.action_press("steer_left", -v.x)
	else:
		Input.action_press("move_right", v.x)
		Input.action_press("steer_right", v.x)
	if _driving():
		return  # (driving: the stick only steers; the pad drives)
	if v.y < 0.0:
		Input.action_press("move_forward", -v.y)
	else:
		Input.action_press("move_back", v.y)


## Pad offset -> drive controls. Axes are independent, so diagonals combine
## (up + sideways = a powered slide; down + sideways = trail-braking turn).
static func read_pad(o: Vector2, k: float, speed: float, was_drifting: bool) -> Dictionary:
	var out := {"gas": 0.0, "brake": 0.0, "kick": false, "drift": false, "steer": 0.0, "zone": "G"}
	if o.y > BRAKE_PX * k:
		# Brake builds with the pull (eased: the first part of the travel
		# scrubs speed gently for traffic and parking, a full pull stops hard).
		var bt := clampf((o.y - BRAKE_PX * k) / ((PAD_R - BRAKE_PX) * k), 0.0, 1.0)
		out["brake"] = 0.08 + 0.92 * pow(bt, 1.5)
		out["zone"] = "B"
	elif o.y > LIFT_PX * k:
		out["zone"] = "C"   # coast
	else:
		var up := clampf(-o.y / (KICK_PX * k), 0.0, 1.0)
		out["gas"] = lerpf(HOLD_THROTTLE, 1.0, up)
		out["kick"] = -o.y >= KICK_PX * k
		out["zone"] = "K" if out["kick"] else "G"
	var side := absf(o.x)
	# Hysteresis: a slide that has started holds until the thumb comes
	# well back in (or the car slows to a crawl); none below DRIFT_SPEED.
	var want := side > DRIFT_PX * k and speed > DRIFT_SPEED
	if was_drifting:
		want = side > DRIFT_PX * k * 0.7 and speed > DRIFT_SPEED * 0.65
	out["drift"] = want and float(out["brake"]) < 0.6
	if out["drift"]:
		out["zone"] += "D"
	out["steer"] = clampf(o.x / (PAD_R * k), -1.0, 1.0) if side > 8.0 * k else 0.0
	return out


func _apply_pad() -> void:
	var di: DriveInput = ui.game.drive_input if ui.game else null
	if di == null:
		return
	var car := _car()
	if _pad_id < 0 or car == null:
		pad = {"gas": 0.0, "brake": 0.0, "kick": false, "drift": false, "steer": 0.0, "zone": ""}
		_drifting = false
		_pad_zone = ""
	else:
		pad = read_pad(_pad_p - _pad_o, ui_k(), absf(car.forward_speed), _drifting)
		_drifting = pad["drift"]
		if String(pad["zone"]) != _pad_zone:
			if _pad_zone != "":
				Settings.haptic(12, 0.35)
			_pad_zone = pad["zone"]
	di.touch_active = true
	di.touch_gas = pad["gas"]
	di.touch_brake = pad["brake"]
	di.touch_kickdown = pad["kick"]
	_steer_from_pad()


## Sideways on the pad steers when the left thumb is free.
func _steer_from_pad() -> void:
	var di: DriveInput = ui.game.drive_input if ui.game else null
	if di == null:
		return
	di.touch_steer = float(pad["steer"]) if _stick_id < 0 else 0.0


func _physics_process(_dt: float) -> void:
	# The handbrake for a pad drift is applied only while the slide builds:
	# once the rear has stepped out (~20°) it is let go so the car holds a
	# controllable angle on steering and throttle instead of spinning.
	var di: DriveInput = ui.game.drive_input if ui != null and ui.game else null
	if di == null:
		return
	var car := _car()
	if car != null and pad["drift"]:
		di.touch_handbrake = absf(car.drift_angle) < deg_to_rad(20.0)
	else:
		di.touch_handbrake = false


func release_all() -> void:
	for k in _held.values():
		_press(k, false)
	_held.clear()
	_stick_id = -1
	_look_id = -1
	_pad_id = -1
	_stick_v = Vector2.ZERO
	_apply_stick()
	_apply_pad()


func _process(_dt: float) -> void:
	# A panel opening (phone, day report) or the game leaving play swallows
	# the touch's release in _input: let go of everything held, or the stick
	# keeps walking you (and the pad keeps driving) behind the panel.
	var blocked := not visible or ui.panel_open() or ui.game == null or ui.game.state != "play"
	if blocked and (_stick_id >= 0 or _look_id >= 0 or _pad_id >= 0 or not _held.is_empty()):
		release_all()
	# Getting out with a thumb still on the pad: drop it.
	if _pad_id >= 0 and not _driving():
		_pad_id = -1
		_apply_pad()
	if visible:
		queue_redraw()


func _draw() -> void:
	if ui.game == null or ui.game.state != "play" or ui.panel_open():
		return
	var f := EmpireStyle.font("black")
	var k := ui_k()
	var sr := _safe()
	if _stick_id >= 0:
		draw_circle(_stick_o, R, Color(1, 1, 1, 0.08))
		draw_arc(_stick_o, R, 0, TAU, 48, Color(1, 1, 1, 0.3), 2.0, true)
		draw_circle(_stick_o + _stick_v * R, 30, Color(1, 1, 1, 0.45))
	else:
		var home := Vector2(sr.position.x + 150, sr.end.y - 150)
		draw_arc(home, R, 0, TAU, 48, Color(1, 1, 1, 0.12), 2.0, true)
		if _driving():
			_label(f, home + Vector2(0, R + 22), "STEER", 13, Color(1, 1, 1, 0.4))
	if _driving():
		_draw_pad(f, k)
	var bs := _buttons()
	for key in bs:
		var r: Rect2 = bs[key]
		var c := r.get_center()
		var rad := r.size.x * 0.5
		var on := _held.values().has(key)
		var col := Color(EmpireStyle.INK, 0.55)
		var txt := String(key).to_upper()
		var ink := EmpireStyle.PAPER
		if key == "action":
			if action_text == "":
				col = Color(EmpireStyle.INK, 0.3)
				txt = ""
			else:
				col = Color(EmpireStyle.AMBER, 0.92)
				txt = verb(action_text)
				ink = EmpireStyle.INK
		if on:
			col = col.lightened(0.25)
		draw_circle(c, rad, col)
		draw_arc(c, rad, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)
		var fs := int((22 if txt.length() < 7 else 16) * (k if rad < 60 else 1.0))
		_label(f, c + Vector2(0, fs * 0.35), txt, fs, ink)


func _label(f: Font, at: Vector2, txt: String, fs: int, col: Color) -> void:
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, at - Vector2(tw * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## The one word that fits on the action button for a prompt
## ("TO LET · £26/day" → VIEW, "PARK & GET OUT" → OUT).
static func verb(prompt: String) -> String:
	var p := prompt.to_upper()
	# What the prompt offers (often after the place's name: "ROSSI'S · MAKE
	# AN OFFER £17,650"), most specific first.
	for pair in [["GET OUT", "OUT"], ["MAKE AN OFFER", "OFFER"], ["FOR SALE", "BUY"], ["BUY OUT", "BUY"],
			["TO LET", "VIEW"], ["SERVE", "SERVE"], ["UNLOAD", "UNLOAD"], ["FILL THE SHELVES", "FILL"]]:
		if p.contains(pair[0]):
			return pair[1]
	var w := p.get_slice(" ", 0).get_slice("·", 0).strip_edges()
	return w if w.length() <= 8 else w.substr(0, 7) + "…"


func _draw_pad(f: Font, k: float) -> void:
	var r := PAD_R * k
	var live := _pad_id >= 0
	var c := _pad_o if live else pad_home()
	var a := 1.0 if live else 0.6
	draw_circle(c, r, Color(EmpireStyle.INK, 0.28 * a))
	draw_arc(c, r, 0, TAU, 56, Color(1, 1, 1, 0.3 * a), 1.5, true)
	# Zones: throttle up, brake down, drift either side; the coast band is
	# the thin gap just below the middle.
	var zones := [[-PI * 0.5, EmpireStyle.GREEN, bool(pad["kick"])], [PI * 0.5, EmpireStyle.RED, float(pad["brake"]) > 0.0],
		[0.0, EmpireStyle.AMBER, bool(pad["drift"]) and float(pad["steer"]) > 0.0],
		[PI, EmpireStyle.AMBER, bool(pad["drift"]) and float(pad["steer"]) <= 0.0]]
	for z in zones:
		var on: bool = z[2]
		draw_arc(c, r + 4.0, float(z[0]) - 0.5, float(z[0]) + 0.5, 16, Color(z[1] as Color, 0.95 if on else 0.38 * a), 6.0 if on else 3.0, true)
	var fs := maxi(11, int(13 * k))
	var car := _car()
	var rev := car != null and float(pad["brake"]) > 0.5 and car.forward_speed < 1.5
	_label(f, c + Vector2(0, -r - 12 * k), "KICKDOWN", fs, Color(1, 1, 1, 0.65 * a))
	_label(f, c + Vector2(0, r + 22 * k), "REVERSE" if rev else "BRAKE", fs, Color(1, 1, 1, 0.65 * a))
	_label(f, c + Vector2(-r - 30 * k, 4), "DRIFT", fs, Color(1, 1, 1, 0.5 * a))
	_label(f, c + Vector2(r + 30 * k, 4), "DRIFT", fs, Color(1, 1, 1, 0.5 * a))
	# Brake depth as a fill down the lower arc.
	if float(pad["brake"]) > 0.0:
		var bd := float(pad["brake"])
		draw_arc(c, r - 7.0, PI * 0.5 - bd * 0.9, PI * 0.5 + bd * 0.9, 24, Color(EmpireStyle.RED, 0.7), 5.0, true)
	var knob := c
	if live:
		knob = c + (_pad_p - _pad_o).limit_length(r)
	var kr := 44.0 * k
	var z := String(pad["zone"])
	var kc := Color(1, 1, 1, 0.14)
	var txt := "DRIVE"
	if live:
		if z.begins_with("B"):
			kc = EmpireStyle.RED
			txt = "REV" if rev else "BRAKE"
		elif z.begins_with("C"):
			kc = EmpireStyle.MUTED
			txt = "COAST"
		elif z.begins_with("K"):
			kc = EmpireStyle.GREEN
			txt = "KICK"
		else:
			kc = EmpireStyle.AMBER
			txt = "DRIVE"
		if pad["drift"]:
			txt = "DRIFT"
		kc = Color(kc, 0.88)
	draw_circle(knob, kr, kc)
	draw_arc(knob, kr, 0, TAU, 40, Color(1, 1, 1, 0.0 if live else 0.4), 1.5, true)
	_label(f, knob + Vector2(0, (fs + 2) * 0.36), txt, fs + 2, EmpireStyle.INK if live else Color(1, 1, 1, 0.8))
