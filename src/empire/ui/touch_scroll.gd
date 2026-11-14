class_name TouchScroll
extends ScrollContainer
## A list you drag like a phone list: a drag that starts anywhere – on a
## button too – scrolls it, with momentum, and the finger lifting at the
## end of a drag never counts as a tap on the button under it
## (EmpireStyle.tap_block_until). Mouse wheel works as usual.

const DEADZONE := 10.0
const FRICTION := 4.5

var _down := false
var _dragging := false
var _travel := 0.0
var _vel := 0.0
var _last_t := 0


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_deadzone = 1000  # (the built-in touch drag is replaced by ours)


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			if get_global_rect().has_point(t.position):
				_down = true
				_dragging = false
				_travel = 0.0
				_vel = 0.0
		else:
			if _dragging:
				EmpireStyle.tap_block_until = Time.get_ticks_msec() + 180
				get_viewport().set_input_as_handled()
			_down = false
			_dragging = false
	elif e is InputEventScreenDrag and _down:
		var d := e as InputEventScreenDrag
		_travel += absf(d.relative.y)
		if not _dragging and _travel > DEADZONE:
			_dragging = true
		if _dragging:
			scroll_vertical = int(scroll_vertical - d.relative.y)
			var now := Time.get_ticks_msec()
			var dt := maxf(float(now - _last_t) / 1000.0, 0.008)
			_vel = lerpf(_vel, -d.relative.y / dt, 0.5)
			_last_t = now
			get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if _down or absf(_vel) < 8.0:
		if not _down:
			_vel = 0.0
		return
	scroll_vertical = int(scroll_vertical + _vel * dt)
	_vel *= exp(-FRICTION * dt)
