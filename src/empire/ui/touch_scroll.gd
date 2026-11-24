class_name TouchScroll
extends ScrollContainer
## A list you drag like a phone list: a drag that starts anywhere – on a
## button too – scrolls it, with momentum, and the finger lifting at the
## end of a drag never counts as a tap on the button under it
## (EmpireStyle.tap_block_until). Mouse wheel works as usual.

const DEADZONE := 10.0
const FRICTION := 4.5

var _finger_id := -1
var _dragging := false
var _travel := 0.0
var _vel := 0.0
var _last_t := 0


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_deadzone = 1000  # (the built-in touch drag is replaced by ours)


## True if a modal sheet or higher opaque/interactive sibling sits above this
## scroll container at `pos` (e.g. a Phone sheet over a background page).
func _is_occluded(pos: Vector2) -> bool:
	var n: Node = self
	var child_branch: Node = self
	while n != null:
		var p := n.get_parent()
		if p == null or p is Viewport:
			break
		if p is Phone:
			var ph := p as Phone
			if ph.has_sheet() and ph._sheet != child_branch and not ph._sheet.is_ancestor_of(self):
				return true
		if p is Control:
			var idx := n.get_index()
			for i in range(idx + 1, p.get_child_count()):
				var sib := p.get_child(i)
				if sib is Control:
					var sc := sib as Control
					if sc.is_visible_in_tree() and sc.mouse_filter == Control.MOUSE_FILTER_STOP and sc.get_global_rect().has_point(pos):
						return true
		child_branch = n
		n = p
	return false


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			if _finger_id < 0 and get_global_rect().has_point(t.position) and not _is_occluded(t.position):
				_finger_id = t.index
				_dragging = false
				_travel = 0.0
				_vel = 0.0
				_last_t = Time.get_ticks_msec()
		elif t.index == _finger_id:
			if _dragging:
				EmpireStyle.tap_block_until = Time.get_ticks_msec() + 180
				get_viewport().set_input_as_handled()
			_finger_id = -1
			_dragging = false
	elif e is InputEventScreenDrag and _finger_id >= 0:
		var d := e as InputEventScreenDrag
		if d.index != _finger_id:
			return
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
	if _finger_id >= 0 or absf(_vel) < 8.0:
		if _finger_id < 0:
			_vel = 0.0
		return
	scroll_vertical = int(scroll_vertical + _vel * dt)
	_vel *= exp(-FRICTION * dt)
