class_name EmpireTouch
extends Control
## Phone controls. Left half: a floating stick (walk; steer when driving).
## Right half: drag to look. Buttons on the right: ACTION (shows the current
## prompt), JUMP; in a vehicle GAS / BRAKE and OUT. Everything writes the
## same input actions the keyboard and pads use, so the game reads one path.

var ui: EmpireUI
var action_text := ""
var _stick_id := -1
var _stick_o := Vector2.ZERO
var _stick_v := Vector2.ZERO
var _look_id := -1
var _look_last := Vector2.ZERO
var _held := {}   # touch index -> button name
const R := 70.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The screen minus the notch / Dynamic Island / home indicator (the HUD's
## rect: EmpireUI insets it by the display's safe area).
func _safe() -> Rect2:
	if ui != null and ui.hud != null:
		return ui.hud.get_global_rect()
	return get_viewport_rect()


func _buttons() -> Dictionary:
	var sr := _safe()
	var s := sr.end  # (positions below are from the safe area's far corner)
	var out := {}
	var driving := ui.game != null and ui.game.driving != ""
	if driving:
		out["gas"] = Rect2(s.x - 170, s.y - 210, 140, 140)
		out["brake"] = Rect2(s.x - 330, s.y - 170, 120, 120)
		out["action"] = Rect2(s.x - 150, s.y - 350, 110, 110)
	else:
		out["action"] = Rect2(s.x - 200, s.y - 220, 160, 160)
		out["jump"] = Rect2(s.x - 330, s.y - 140, 100, 100)
	return out


func _input(event: InputEvent) -> void:
	if not visible or ui.panel_open() or ui.game == null or ui.game.state != "play":
		return
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
			if t.position.x < get_viewport_rect().size.x * 0.45 and _stick_id < 0:
				_stick_id = t.index
				_stick_o = t.position
				_stick_v = Vector2.ZERO
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
			if t.index == _look_id:
				_look_id = -1
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_id:
			_stick_v = ((d.position - _stick_o) / R).limit_length(1.0)
			_apply_stick()
			queue_redraw()
		elif d.index == _look_id:
			ui.game.camera.add_touch_look(d.position - _look_last, get_viewport_rect().size.x)
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
		"gas":
			if on:
				Input.action_press("accelerate")
			else:
				Input.action_release("accelerate")
		"brake":
			if on:
				Input.action_press("brake")
			else:
				Input.action_release("brake")


func _apply_stick() -> void:
	var v := _stick_v
	for a in ["move_left", "move_right", "move_forward", "move_back", "steer_left", "steer_right"]:
		Input.action_release(a)
	if v.length() < 0.08:
		return
	if v.x < 0.0:
		Input.action_press("move_left", -v.x)
		Input.action_press("steer_left", -v.x)
	else:
		Input.action_press("move_right", v.x)
		Input.action_press("steer_right", v.x)
	if v.y < 0.0:
		Input.action_press("move_forward", -v.y)
	else:
		Input.action_press("move_back", v.y)


func _process(_dt: float) -> void:
	# A panel opening (phone, day report) or the game leaving play swallows
	# the touch's release in _input: let go of everything held, or the stick
	# keeps walking you (and GAS keeps driving) behind the panel.
	var blocked := not visible or ui.panel_open() or ui.game == null or ui.game.state != "play"
	if blocked and (_stick_id >= 0 or _look_id >= 0 or not _held.is_empty()):
		for k in _held.values():
			_press(k, false)
		_held.clear()
		_stick_id = -1
		_look_id = -1
		_stick_v = Vector2.ZERO
		_apply_stick()
	if visible:
		queue_redraw()


func _draw() -> void:
	if ui.game == null or ui.game.state != "play" or ui.panel_open():
		return
	var f := EmpireStyle.font("black")
	if _stick_id >= 0:
		draw_circle(_stick_o, R, Color(1, 1, 1, 0.08))
		draw_arc(_stick_o, R, 0, TAU, 48, Color(1, 1, 1, 0.3), 2.0, true)
		draw_circle(_stick_o + _stick_v * R, 30, Color(1, 1, 1, 0.45))
	else:
		var sr := _safe()
		draw_arc(Vector2(sr.position.x + 150, sr.end.y - 150), R, 0, TAU, 48, Color(1, 1, 1, 0.12), 2.0, true)
	var bs := _buttons()
	for k in bs:
		var r: Rect2 = bs[k]
		var c := r.get_center()
		var rad := r.size.x * 0.5
		var on := _held.values().has(k)
		var col := Color(EmpireStyle.INK, 0.55)
		var txt := String(k).to_upper()
		if k == "action":
			if ui.game.driving != "":
				txt = "OUT"
			elif action_text == "":
				col = Color(EmpireStyle.INK, 0.3)
				txt = ""
			else:
				col = Color(EmpireStyle.AMBER, 0.92)
				txt = action_text.get_slice(" ", 0)
		if on:
			col = col.lightened(0.25)
		draw_circle(c, rad, col)
		draw_arc(c, rad, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)
		var fs := 22 if txt.length() < 7 else 16
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(f, c + Vector2(-tw * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			EmpireStyle.INK if k == "action" and action_text != "" and ui.game.driving == "" else EmpireStyle.PAPER)
