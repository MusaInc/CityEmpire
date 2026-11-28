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
##      slide sideways  = steer, with a power slide at wider throw under gas
##      let go          = coast (the car's engine braking slows it)
##    DRIFT is a separate handbrake button for cars.
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
const DRIFT_PX := 66.0       # sideways this far: handbrake drift (Never Stop smart stick)
const SIDE_DEAD_PX := 28.0   # generous deadzone prevents unintended steering from minor right-stick wobble
const SIDE_FULL_PX := 104.0
const HOLD_THROTTLE := 0.68
const DRIFT_SPEED := 8.0     # m/s (~18 mph): matches Never Stop's drift threshold
var _pad_id := -1
var _pad_o := Vector2.ZERO
var _pad_p := Vector2.ZERO
var _pad_zone := ""
## What the pad is doing now (drawn, and read by tests).
var pad := {"gas": 0.0, "brake": 0.0, "kick": false, "drift": false, "zone": ""}
## Cached visual state so _process only queues redraws on actual changes.
var _d_blocked := true
var _d_driving := false
var _d_safe := Rect2()
var _d_size := -1.0
var _d_inset := -1.0
var _d_opacity := -1.0
var _d_action := ""
var _d_mode := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_physics_priority = -20  # (the drift handbrake, before DriveInput reads it)


## The screen minus the notch / Dynamic Island / home indicator (the HUD's
## rect plus the full bottom safe-area inset for the iPhone home indicator).
func _safe() -> Rect2:
	var vp := get_viewport_rect()
	var r := ui.hud.get_global_rect() if (ui != null and ui.hud != null) else vp
	var bottom_inset := 0.0
	if ui != null:
		bottom_inset = float(ui._safe_insets(vp.size)[3])
	else:
		var sa := DisplayServer.get_display_safe_area()
		var win := DisplayServer.window_get_size()
		if sa.size.x > 0 and win.x > 0 and DisplayServer.screen_get_size() == win:
			bottom_inset = float(win.y - sa.end.y) * (vp.size.y / float(win.y))
	if bottom_inset > 0.0:
		var max_end_y := vp.end.y - bottom_inset
		if r.end.y > max_end_y:
			r.size.y = maxf(0.0, max_end_y - r.position.y)
	return r


## Control scale: tablets draw canvas units physically bigger, so bring the
## controls (and thumb travel) back toward phone size there.
func ui_k() -> float:
	var vp := get_viewport_rect().size
	return clampf(lerpf(1.0, 0.82, clampf((vp.x / maxf(vp.y, 1.0) - 2.0) / -0.6, 0.0, 1.0)), 0.8, 1.0) * Settings.touch_size


func _driving() -> bool:
	return ui.game != null and ui.game.in_vehicle()


## The vehicle you're in (Car or Craft: both have forward_speed / drift_angle).
func _car() -> Node3D:
	return ui.game.vehicle_node() if _driving() else null


## What the pad's directions mean for the vehicle you're in.
func profile() -> Dictionary:
	var v := _car()
	var k := String(v.get("kind")) if v is Craft else "car"
	match k:
		"heli":
			return {"up": "CLIMB", "down": "DESCEND", "hold": "FLY", "idle": "HOVER"}
		"plane":
			var air := String(v.get("state")) in ["air", "stall"]
			return {"up": "CLIMB" if air else "TAKE OFF", "down": "DESCEND" if air else "BRAKE", "side": "BANK" if air else "STEER",
				"hold": "CRUISE" if air else "TAXI", "idle": "LEVEL" if air else "IDLE"}
		"boat":
			return {"up": "FULL AHEAD", "down": "ASTERN", "hold": "AHEAD", "idle": "DRIFT"}
	return {"up": "KICKDOWN", "down": "BRAKE", "hold": "DRIVE", "idle": "DRIVE"}


func pad_home() -> Vector2:
	var s := _safe().end
	var k := ui_k()
	return s - Vector2((PAD_R + 58.0) * k + Settings.touch_inset, (PAD_R + 46.0) * k)


func _buttons() -> Dictionary:
	var sr := _safe()
	var s := sr.end  # (positions below are from the safe area's far corner)
	var k := ui_k()
	var out := {}
	if _driving():
		var h := pad_home()
		# OUT needs the car to be slow. Drift is controlled directly by sliding the right pad left/right (Never Stop style).
		if action_text != "":
			out["action"] = Rect2(h + Vector2(-PAD_R - 40.0, -PAD_R - 70.0) * k, Vector2(92, 92) * k)
	else:
		var inset := Settings.touch_inset
		out["action"] = Rect2(s.x - 200 * k - inset, s.y - 220 * k, 160 * k, 160 * k)
		out["jump"] = Rect2(s.x - 330 * k - inset, s.y - 140 * k, 100 * k, 100 * k)
	return out


func _over_hud(pos: Vector2) -> bool:
	if ui == null:
		return false
	for ctrl in [ui._phone_btn, ui.minimap, ui._obj.get_parent() if ui._obj else null]:
		if ctrl is Control and (ctrl as Control).visible and (ctrl as Control).get_global_rect().grow(6.0).has_point(pos):
			return true
	return false


func _input(event: InputEvent) -> void:
	if not visible or ui.panel_open() or ui.game == null or ui.game.state != "play":
		return
	var w := get_viewport_rect().size.x
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var driving := _driving()
		if t.pressed:
			if _over_hud(t.position):
				return
			var bs := _buttons()
			for k in bs:
				if (bs[k] as Rect2).grow(14).has_point(t.position):
					_held[t.index] = k
					_press(k, true)
					get_viewport().set_input_as_handled()
					queue_redraw()
					return
			if driving:
				# Clean 50/50 split while driving/piloting: no dead zone and
				# never rotate the inactive on-foot SwingCamera.
				if t.position.x < w * 0.5:
					if _stick_id < 0:
						_stick_id = t.index
						_stick_o = t.position
						_stick_v = Vector2.ZERO
						queue_redraw()
				elif _pad_id < 0:
					_pad_id = t.index
					_pad_o = t.position
					_pad_p = t.position
					_pad_zone = ""
					_apply_pad()
					queue_redraw()
			else:
				if t.position.x < w * 0.45 and _stick_id < 0:
					_stick_id = t.index
					_stick_o = t.position
					_stick_v = Vector2.ZERO
					queue_redraw()
				elif _look_id < 0:
					_look_id = t.index
					_look_last = t.position
		else:
			var changed := false
			if _held.has(t.index):
				_press(_held[t.index], false)
				_held.erase(t.index)
				changed = true
			if t.index == _stick_id:
				_stick_id = -1
				_stick_v = Vector2.ZERO
				_apply_stick()
				changed = true
			if t.index == _pad_id:
				_pad_id = -1
				_apply_pad()
				changed = true
			if t.index == _look_id:
				_look_id = -1
			if changed:
				queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_id:
			_stick_v = ((d.position - _stick_o) / (R * Settings.touch_size)).limit_length(1.0)
			_apply_stick()
			queue_redraw()
		elif d.index == _pad_id:
			_pad_p = d.position
			# The landing point follows a thumb that wanders well past full
			# travel, so pulling back always responds at once, while keeping
			# horizontal steering and vertical throttle axes independent for
			# both Car and Craft.
			var so := _pad_p - _pad_o
			var lim := PAD_R * ui_k() * 1.35
			_pad_o = _pad_p - so.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
			_apply_pad()
			queue_redraw()
		elif d.index == _look_id:
			ui.game.camera.add_touch_look(d.position - _look_last, w)
			_look_last = d.position


func reset_contacts() -> void:
	if _held.values().has("jump"):
		Input.action_release("jump")
	_held.clear()
	_stick_id = -1
	_stick_v = Vector2.ZERO
	_pad_id = -1
	_look_id = -1
	_apply_stick()
	_apply_pad()
	if ui.game and ui.game.drive_input:
		ui.game.drive_input.touch_handbrake = false
	queue_redraw()


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
	var raw_len := _stick_v.length()
	var v := Vector2.ZERO
	if raw_len >= 0.08:
		var mag := clampf((raw_len - 0.08) / 0.92, 0.0, 1.0)
		v = (_stick_v / raw_len) * (mag if _driving() else pow(mag, 1.22))
	for action in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(action)
	var driving := _driving()
	if ui.game and ui.game.drive_input:
		ui.game.drive_input.touch_steer = clampf(v.x * Settings.touch_steering, -1.0, 1.0) if driving else 0.0
		ui.game.drive_input.touch_active = _stick_id >= 0 or _pad_id >= 0
	if driving or v.is_zero_approx():
		return
	Input.action_press("move_left" if v.x < 0.0 else "move_right", absf(v.x))
	Input.action_press("move_forward" if v.y < 0.0 else "move_back", absf(v.y))


## Vertical travel on the right pad controls power and braking; sideways travel past DRIFT_PX engages drift (Never Stop smart stick).
static func read_pad(o: Vector2, k: float) -> Dictionary:
	var out := {"gas": 0.0, "brake": 0.0, "kick": false, "drift": false, "zone": "G"}
	if o.y > BRAKE_PX * k:
		var bt := clampf((o.y - BRAKE_PX * k) / ((PAD_R - BRAKE_PX) * k), 0.0, 1.0)
		out["brake"] = 0.08 + 0.92 * pow(bt, 1.5)
		out["zone"] = "B"
	elif o.y > LIFT_PX * k:
		out["zone"] = "C"
	else:
		var up := clampf(-o.y / (KICK_PX * k), 0.0, 1.0)
		out["gas"] = lerpf(HOLD_THROTTLE, 1.0, up)
		out["kick"] = -o.y >= KICK_PX * k
		out["zone"] = "K" if out["kick"] else "G"
	if absf(o.x) >= DRIFT_PX * k:
		out["drift"] = true
		out["zone"] = String(out["zone"]) + "D"
	return out


static func read_pad_steer(offset: float, scale: float) -> float:
	var travel := clampf((absf(offset) / scale - SIDE_DEAD_PX) / (SIDE_FULL_PX - SIDE_DEAD_PX), 0.0, 1.0)
	return signf(offset) * pow(travel, 1.55)


func _apply_pad() -> void:
	var di: DriveInput = ui.game.drive_input if ui.game else null
	if di == null:
		return
	var car = _car()
	if _pad_id < 0 or car == null:
		pad = {"gas": 0.0, "brake": 0.0, "kick": false, "drift": false, "zone": ""}
		_pad_zone = ""
	else:
		pad = read_pad(_pad_p - _pad_o, ui_k())
		if String(pad["zone"]) != _pad_zone:
			if _pad_zone != "":
				Settings.haptic(12, 0.35)
			_pad_zone = pad["zone"]
	di.touch_active = _pad_id >= 0 or _stick_id >= 0
	di.touch_gas = pad["gas"]
	di.touch_brake = pad["brake"]
	di.touch_kickdown = pad["kick"]
	# Never let minor right-stick wobble steer while left stick is active or while braking.
	var allow_pad_steer := _pad_id >= 0 and car != null and _stick_id < 0 and float(pad["brake"]) < 0.05
	di.touch_pad_steer = read_pad_steer(_pad_p.x - _pad_o.x, ui_k()) if allow_pad_steer else 0.0


func _physics_process(_dt: float) -> void:
	var di: DriveInput = ui.game.drive_input if ui != null and ui.game else null
	if di == null:
		return
	var car := _car() as Car
	di.touch_handbrake = car != null and absf(car.forward_speed) > DRIFT_SPEED and bool(pad.get("drift", false))


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
	queue_redraw()


func _draw_mode(driving: bool) -> int:
	if not driving:
		return 0
	var v := _car()
	if v is Craft:
		var k := String(v.get("kind"))
		if k == "heli":
			return 3
		if k == "plane":
			return 5 if String(v.get("state")) in ["air", "stall"] else 4
		return 6
	var rev := v is Car and float(pad["brake"]) > 0.5 and float(v.get("forward_speed")) < 1.5
	return 2 if rev else 1


func _process(_dt: float) -> void:
	# A panel opening (phone, day report) or the game leaving play swallows
	# the touch's release in _input: let go of everything held, or the stick
	# keeps walking you (and the pad keeps driving) behind the panel.
	var blocked := not visible or ui.panel_open() or ui.game == null or ui.game.state != "play"
	if blocked and (_stick_id >= 0 or _look_id >= 0 or _pad_id >= 0 or not _held.is_empty()):
		release_all()
	var driving := _driving()
	# Getting out with a thumb still on the pad: drop it.
	if not driving and (_pad_id >= 0 or _held.values().has("drift")):
		release_all()
	if not visible:
		_d_blocked = true
		return
	var op := Settings.touch_opacity
	if not is_equal_approx(self_modulate.a, op):
		self_modulate.a = op
	var sr := _safe()
	var sz := Settings.touch_size
	var ins := Settings.touch_inset
	var mode := _draw_mode(driving)
	var dirty := blocked != _d_blocked or driving != _d_driving or sr != _d_safe \
		or not is_equal_approx(sz, _d_size) or not is_equal_approx(ins, _d_inset) \
		or not is_equal_approx(op, _d_opacity) or action_text != _d_action or mode != _d_mode
	if dirty:
		_d_blocked = blocked
		_d_driving = driving
		_d_safe = sr
		_d_size = sz
		_d_inset = ins
		_d_opacity = op
		_d_action = action_text
		_d_mode = mode
		queue_redraw()


func _draw() -> void:
	if ui.game == null or ui.game.state != "play" or ui.panel_open():
		return
	var f := EmpireStyle.font("black")
	var k := ui_k()
	var sr := _safe()
	var radius := R * k
	if _stick_id >= 0:
		draw_circle(_stick_o, radius, Color(1, 1, 1, 0.08))
		draw_arc(_stick_o, radius, 0, TAU, 48, Color(1, 1, 1, 0.3), 2.0, true)
		draw_circle(_stick_o + _stick_v * radius, 30 * k, Color(1, 1, 1, 0.45))
	else:
		var home := Vector2(sr.position.x + 150 * k + Settings.touch_inset, sr.end.y - 150 * k)
		draw_arc(home, radius, 0, TAU, 48, Color(1, 1, 1, 0.12), 2.0, true)
		if _driving():
			_label(f, home + Vector2(0, radius + 22), "STEER", 13, Color(1, 1, 1, 0.4))
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
		while fs > 11 and f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > rad * 1.72:
			fs -= 1
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
	var car = _car()
	var is_car := car is Car
	var drifting := bool(pad.get("drift", false)) and is_car
	var zones := [[-PI * 0.5, EmpireStyle.GREEN, bool(pad["kick"])],
		[PI * 0.5, EmpireStyle.RED, float(pad["brake"]) > 0.0]]
	if is_car:
		zones.append([0.0, EmpireStyle.AMBER, drifting and (_pad_p.x - _pad_o.x) > 0.0])
		zones.append([PI, EmpireStyle.AMBER, drifting and (_pad_p.x - _pad_o.x) < 0.0])
	for z in zones:
		var on: bool = z[2]
		draw_arc(c, r + 4.0, float(z[0]) - 0.5, float(z[0]) + 0.5, 16, Color(z[1] as Color, 0.95 if on else 0.38 * a), 6.0 if on else 3.0, true)
	var fs := maxi(11, int(13 * k))
	var prof := profile()
	var rev := is_car and float(pad["brake"]) > 0.5 and float(car.get("forward_speed")) < 1.5
	_label(f, c + Vector2(0, -r - 12 * k), String(prof["up"]), fs, Color(1, 1, 1, 0.65 * a))
	_label(f, c + Vector2(0, r + 22 * k), "REVERSE" if rev else String(prof["down"]), fs, Color(1, 1, 1, 0.65 * a))
	if is_car:
		_label(f, c + Vector2(-r - 30 * k, fs * 0.35), "DRIFT", fs, Color(1, 1, 1, 0.55 * a))
		_label(f, c + Vector2(r + 30 * k, fs * 0.35), "DRIFT", fs, Color(1, 1, 1, 0.55 * a))
	# Brake depth as a fill down the lower arc.
	if float(pad["brake"]) > 0.0:
		var bd := float(pad["brake"])
		draw_arc(c, r - 7.0, PI * 0.5 - bd * 0.9, PI * 0.5 + bd * 0.9, 24, Color(EmpireStyle.RED, 0.7), 5.0, true)
	var knob := c
	if live:
		var offset := _pad_p - _pad_o
		knob += offset.limit_length(r)
	var kr := 44.0 * k
	var z := String(pad["zone"])
	var kc := Color(1, 1, 1, 0.14)
	var txt := String(prof["idle"])
	if live:
		if drifting:
			kc = EmpireStyle.AMBER
			txt = "DRIFT"
		elif z.begins_with("B"):
			kc = EmpireStyle.RED
			txt = "REV" if rev else String(prof["down"]).get_slice(" ", 0)
		elif z.begins_with("C"):
			kc = EmpireStyle.MUTED
			txt = "COAST" if is_car else String(prof["idle"])
		elif z.begins_with("K"):
			kc = EmpireStyle.GREEN
			txt = "KICK" if is_car else String(prof["up"]).get_slice(" ", 0)
		else:
			kc = EmpireStyle.AMBER
			txt = String(prof["hold"])
		kc = Color(kc, 0.88)
	draw_circle(knob, kr, kc)
	draw_arc(knob, kr, 0, TAU, 40, Color(1, 1, 1, 0.0 if live else 0.4), 1.5, true)
	_label(f, knob + Vector2(0, (fs + 2) * 0.36), txt, fs + 2, EmpireStyle.INK if live else Color(1, 1, 1, 0.8))
