class_name CraftAudio
extends AudioStreamPlayer3D
## Synthesised engine sound for a Craft (no samples, no memory to speak of):
##   heli   a rotor beat (filtered noise chopped at the blade-pass rate) over
##          a turbine whine, both rising with the rotor's spin-up;
##   plane  propeller: a buzz of harmonics at the prop rate; jet: a broad
##          roar (noise) under a whine, both with the throttle;
##   boat   an outboard's low burble plus water hiss rising with speed.
## Only the craft you're in (or within 120 m) makes sound; the generator is
## filled a buffer at a time in _process (22.05 kHz mono).

const RATE := 22050.0

var craft: Craft
var _pb: AudioStreamGeneratorPlayback
var _ph := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _lp := 0.0
var _lp2 := 0.0
var _rng := RandomNumberGenerator.new()
var _gain := 0.0
var _last_level := 0.0


func setup(c: Craft) -> void:
	craft = c
	process_mode = Node.PROCESS_MODE_ALWAYS
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.15
	stream = gen
	bus = "SFX"
	unit_size = 18.0
	max_distance = 260.0
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_rng.seed = 7


func _process(dt: float) -> void:
	if craft == null or not is_instance_valid(craft):
		return
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(global_position) < 120.0
	var level := _level()
	var want := not get_tree().paused and near and level >= 0.02
	if want:
		_last_level = level
	var prev_gain := _gain
	_gain = move_toward(_gain, 1.0 if want else 0.0, maxf(dt, 0.001) * 10.0)
	if not want and _gain <= 0.0005:
		if playing:
			stop()
			_pb = null
		return
	if not playing:
		play()
		_pb = get_stream_playback()
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var eff_level := level if want else _last_level
	match craft.kind:
		"heli":
			_heli(buf, eff_level)
		"plane":
			_plane(buf, eff_level)
		_:
			_boat(buf, eff_level)
	if prev_gain < 0.9995 or _gain < 0.9995:
		var inv := 1.0 / float(maxi(n - 1, 1))
		for i in n:
			buf[i] *= lerpf(prev_gain, _gain, float(i) * inv)
	_pb.push_buffer(buf)


func _player_aboard() -> bool:
	var owner_node := craft.get_parent()
	if owner_node != null and owner_node.has_method("vehicle_node"):
		return owner_node.call("vehicle_node") == craft
	return false


## How loud: the rotor / throttle / speed, by kind.
func _level() -> float:
	match craft.kind:
		"heli":
			return craft.rotor
		"plane":
			return maxf(craft.rotor * 0.5, craft.throttle) if craft.state != "air" else 0.8
	if bool(craft.input.get("active", false)) or absf(craft.forward_speed) > 0.3:
		return clampf(0.25 + absf(craft.forward_speed) / maxf(float(craft.spec.get("vmax", 15.0)), 1.0), 0.0, 1.0)
	return 0.12 if _player_aboard() else 0.0


func _heli(buf: PackedVector2Array, level: float) -> void:
	var blade := 4.0 + 13.0 * level              # blade passes a second
	var whine := 900.0 + 900.0 * level
	for i in buf.size():
		_ph[0] = fmod(_ph[0] + blade / RATE, 1.0)
		_ph[1] = fmod(_ph[1] + whine / RATE, 1.0)
		var chop: float = pow(1.0 - _ph[0], 6.0)       # sharp attack, quick decay: the "whop"
		var noise := _rng.randf_range(-1.0, 1.0)
		_lp = lerpf(_lp, noise, 0.08)            # low-passed noise
		var s := _lp * (0.35 + 1.8 * chop) * level + sin(_ph[1] * TAU) * 0.05 * level
		buf[i] = Vector2(s, s) * 0.6


func _plane(buf: PackedVector2Array, level: float) -> void:
	var jet: bool = craft.spec.get("jet", false)
	var f0 := (35.0 + 70.0 * level) if not jet else (2200.0 + 1400.0 * level)
	for i in buf.size():
		var noise := _rng.randf_range(-1.0, 1.0)
		var s := 0.0
		if jet:
			_lp = lerpf(_lp, noise, 0.25)
			_ph[1] = fmod(_ph[1] + f0 / RATE, 1.0)
			s = _lp * 0.7 * level + sin(_ph[1] * TAU) * 0.06 * level
		else:
			_ph[0] = fmod(_ph[0] + f0 / RATE, 1.0)
			var saw: float = _ph[0] * 2.0 - 1.0
			_lp = lerpf(_lp, saw, 0.3)
			_lp2 = lerpf(_lp2, noise, 0.05)
			s = (_lp * 0.6 + sin(_ph[0] * TAU * 2.0) * 0.25) * level + _lp2 * 0.25 * level
		buf[i] = Vector2(s, s) * 0.55


func _boat(buf: PackedVector2Array, level: float) -> void:
	var f0 := 28.0 + 55.0 * level
	var hiss := clampf(absf(craft.forward_speed) / 18.0, 0.0, 1.0)
	for i in buf.size():
		_ph[0] = fmod(_ph[0] + f0 / RATE, 1.0)
		_ph[2] = fmod(_ph[2] + (f0 * 0.5 + 3.0) / RATE, 1.0)
		var burble: float = (_ph[0] * 2.0 - 1.0) * (0.6 + 0.4 * sin(_ph[2] * TAU))
		_lp = lerpf(_lp, burble, 0.2)
		var noise := _rng.randf_range(-1.0, 1.0)
		_lp2 = lerpf(_lp2, noise, 0.35)
		var s := _lp * 0.55 * level + _lp2 * 0.3 * hiss
		buf[i] = Vector2(s, s) * 0.6
