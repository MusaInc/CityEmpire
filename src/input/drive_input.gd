class_name DriveInput
extends Node
## Merges keyboard, gamepad and touch into car controls each physics frame.
## Press to accelerate: GAS pedal (touch), W / Up, or the right trigger.
## Settings → Accelerate → Auto brings back the old always-on throttle.

var car: Car
var enabled := true
var auto_accelerate := false
## Touch writes these (TouchDrive); -1..1 steer, 0..1 the rest.
var touch_steer := 0.0
var touch_pad_steer := 0.0
var touch_gas := 0.0
var touch_brake := 0.0
var touch_handbrake := false
var touch_nitro := false
var touch_kickdown := false
var touch_active := false
var touch_jump := false
var touch_drop := false
var _steer_smooth := 0.0
var _pad_smooth := 0.0
var _slide_smooth := 0.0


static func pad_authority(primary: float) -> float:
	return 1.0 - smoothstep(0.025, 0.08, absf(primary))


static func pad_slide_request(side: float, speed: float, gas: float, brake: float) -> float:
	var demand := smoothstep(0.58, 0.93, absf(side))
	var motion := smoothstep(8.0, 13.0, speed) * (1.0 - smoothstep(27.0, 39.0, speed))
	return demand * motion * smoothstep(0.30, 0.66, gas) * (1.0 - smoothstep(0.02, 0.18, brake))


func _ready() -> void:
	process_physics_priority = -10  # before the cars read their controls


func _physics_process(dt: float) -> void:
	Prof.begin("input")
	if not is_instance_valid(car) or not enabled:
		_pad_smooth = 0.0
		_slide_smooth = 0.0
		if is_instance_valid(car):
			car.power_slide = 0.0
		Prof.end("input")
		return  # someone else (autopilot, cinematic) is driving
	var key_steer := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var steer := key_steer if absf(key_steer) > absf(touch_steer) else touch_steer
	var authority := pad_authority(steer)
	# Digital keys ramp in (a tap is a small correction, a hold a full turn).
	var digital := absf(key_steer) == 1.0 and not touch_active
	if digital:
		_steer_smooth = move_toward(_steer_smooth, steer, dt * 6.5 if signf(steer) == signf(_steer_smooth) else dt * 10.0)
		steer = _steer_smooth
	else:
		_steer_smooth = steer
	var sens: float = Settings.steer_sensitivity
	steer = clampf(signf(steer) * pow(absf(steer), 1.0 / maxf(sens, 0.3)), -1.0, 1.0)
	var brake := maxf(Input.get_action_strength("brake"), touch_brake)
	var thr := maxf(Input.get_action_strength("accelerate"), touch_gas)
	auto_accelerate = Settings.accelerate == "auto"
	if auto_accelerate:
		thr = maxf(thr, 1.0 if brake < 0.1 else 0.0)
	var side_limit := lerpf(0.88, 0.63, smoothstep(8.0, 34.0, absf(car.forward_speed)))
	var pad_limit := side_limit * authority
	var pad_target := touch_pad_steer * pad_limit
	var unwinding := absf(pad_target) < absf(_pad_smooth) or pad_target * _pad_smooth < 0.0
	_pad_smooth = move_toward(_pad_smooth, pad_target, dt * (7.0 if unwinding else 3.8))
	_pad_smooth = clampf(_pad_smooth, -pad_limit, pad_limit)
	car.steer = clampf(steer + _pad_smooth, -1.0, 1.0)
	var slide := pad_slide_request(touch_pad_steer, car.forward_speed, touch_gas, brake) * authority
	_slide_smooth = move_toward(_slide_smooth, slide, dt * (4.2 if slide > _slide_smooth else 8.0))
	_slide_smooth = minf(_slide_smooth, authority)
	car.power_slide = _slide_smooth
	car.throttle = thr
	car.brake = brake
	car.handbrake = Input.is_action_pressed("handbrake") or touch_handbrake
	car.nitro = Input.is_action_pressed("nitro") or touch_nitro
	# (Shift on a keyboard: the same key as Never Stop's NOS.)
	car.kickdown = touch_kickdown or (Input.is_action_pressed("nitro") and thr > 0.9)
	touch_jump = false
	touch_drop = false
	Prof.end("input")


