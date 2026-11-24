class_name LensFx
extends CanvasLayer
## Fisheye at the screen edges (lens.gdshader) between the 3D world and the
## HUD: layer -1 draws after the 3D image and before every UI layer (≥ 0).
## SwingCamera feeds it speed; the bend widens a touch as you go faster.

const BASE := 0.045
const FAST := 0.05   # extra at full swing speed

## WorldState assigns its chase rig before adding the layer to the tree.
var chase_camera: ChaseCamera

var _rect: ColorRect
var _mat: ShaderMaterial
var _speed := 0.0
var _strength := -1.0


func _ready() -> void:
	layer = -1
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/ui/shaders/lens.gdshader")
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	get_viewport().size_changed.connect(_on_size)
	_on_size()
	if chase_camera != null:
		_mat.set_shader_parameter("driving", true)
		process_mode = Node.PROCESS_MODE_ALWAYS
		visible = false
	set_process(chase_camera != null)
	_apply()


func _process(dt: float) -> void:
	var car := chase_camera.target
	visible = Settings.driving_lens > 0.0 and not get_tree().paused and chase_camera.cam.is_current() \
		and chase_camera.mode == "chase" and is_instance_valid(car)
	if visible:
		var velocity := car.linear_velocity
		var speed := Vector2(velocity.x, velocity.z).length()
		set_speed(smoothstep(3.0, 32.0, speed), dt)
	else:
		_speed = 0.0


func _on_size() -> void:
	var s := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", s.x / maxf(s.y, 1.0))


## 0..1 swing speed (smoothed here).
func set_speed(amount: float, dt: float) -> void:
	_speed = lerpf(_speed, clampf(amount, 0.0, 1.0), 1.0 - exp(-3.0 * dt))
	_apply()


func _apply() -> void:
	var strength := BASE + FAST * _speed
	if chase_camera != null:
		strength = Settings.driving_lens * (0.026 + 0.035 * _speed)
	if absf(strength - _strength) > 0.0002:
		_strength = strength
		_mat.set_shader_parameter("strength", strength)
