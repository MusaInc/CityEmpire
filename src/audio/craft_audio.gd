class_name CraftAudio
extends AudioStreamPlayer3D
## Pre-baked seamless engine loops for a Craft (synthesized once per craft kind
## into AudioStreamWAV in memory and modulated by pitch_scale + volume_db per
## frame — zero per-sample GDScript loops during gameplay):
##   heli        rotor beat (filtered noise chopped at blade-pass rate) + turbine whine;
##   plane_prop  warm multi-harmonic propeller buzz + wash;
##   plane_jet   broad turbine roar + subtle whine;
##   boat        throaty outboard burble + secondary speed-driven water spray hiss.
## Only the craft you're in (or within 120 m) makes sound; unattended boats stay silent.

const RATE := 22050
const LOOP_SECS := 1.5

static var _baked_loops := {}   # profile key -> AudioStreamWAV

var craft: Craft
var _profile := "heli"
var _gain := 0.0
var _last_level := 0.0
var _hiss_player: AudioStreamPlayer3D
var _hiss_gain := 0.0


static func _encode_loop(raw: PackedFloat32Array, xfade_samples: int) -> AudioStreamWAV:
	var n := raw.size()
	var xf := mini(xfade_samples, n / 4)
	if xf > 0:
		for i in xf:
			var w := float(i) / float(xf)
			raw[i] = lerpf(raw[n - xf + i], raw[i], w)
	var loop_len := n - xf
	var data := PackedByteArray()
	data.resize(loop_len * 2)
	for i in loop_len:
		var v := clampi(int(raw[i] * 32767.0), -32768, 32767)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = loop_len
	return wav


static func _baked_loop(profile: String) -> AudioStreamWAV:
	if _baked_loops.has(profile):
		return _baked_loops[profile] as AudioStreamWAV
	var xf := 1100
	var loop_len := int(RATE * LOOP_SECS)
	var total := loop_len + xf
	var raw := PackedFloat32Array()
	raw.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["craft_audio", profile])
	var lp := 0.0
	var lp2 := 0.0
	var ph0 := 0.0
	var ph1 := 0.0
	var ph2 := 0.0
	match profile:
		"heli":
			# Exact integer blade-pass cycles over LOOP_SECS (14 Hz -> 21 cycles in 1.5 s).
			var blade := 14.0
			var whine := 1400.0
			for i in total:
				ph0 = fmod(ph0 + blade / float(RATE), 1.0)
				ph1 = fmod(ph1 + whine / float(RATE), 1.0)
				var chop := pow(1.0 - ph0, 5.5)
				var noise := rng.randf_range(-1.0, 1.0)
				lp = lerpf(lp, noise, 0.085)
				raw[i] = clampf((lp * (0.35 + 1.75 * chop) + sin(ph1 * TAU) * 0.045) * 0.58, -0.95, 0.95)
		"plane_jet":
			var whine := 2600.0
			for i in total:
				var noise := rng.randf_range(-1.0, 1.0)
				lp = lerpf(lp, noise, 0.24)
				lp2 = lerpf(lp2, lp, 0.09)
				ph1 = fmod(ph1 + whine / float(RATE), 1.0)
				raw[i] = clampf(((lp * 0.45 + lp2 * 0.45) + sin(ph1 * TAU) * 0.055) * 0.58, -0.95, 0.95)
		"plane_prop":
			# Exact integer cycles (66 Hz -> 99 cycles in 1.5 s).
			var f0 := 66.0
			for i in total:
				ph0 = fmod(ph0 + f0 / float(RATE), 1.0)
				var saw := ph0 * 2.0 - 1.0
				lp = lerpf(lp, saw, 0.28)
				var noise := rng.randf_range(-1.0, 1.0)
				lp2 = lerpf(lp2, noise, 0.05)
				raw[i] = clampf((lp * 0.56 + sin(ph0 * TAU * 2.0) * 0.24 + lp2 * 0.25) * 0.55, -0.95, 0.95)
		"boat_hiss":
			for i in total:
				var noise := rng.randf_range(-1.0, 1.0)
				lp = lerpf(lp, noise, 0.34)
				raw[i] = clampf(lp * 0.42, -0.95, 0.95)
		_:
			# Boat outboard burble: 48 Hz fundamental + 4 Hz lope (exact cycles in 1.5 s).
			var f0 := 48.0
			var lope := 4.0
			for i in total:
				ph0 = fmod(ph0 + f0 / float(RATE), 1.0)
				ph2 = fmod(ph2 + lope / float(RATE), 1.0)
				var burble := (ph0 * 2.0 - 1.0) * (0.62 + 0.38 * sin(ph2 * TAU))
				lp = lerpf(lp, burble, 0.20)
				raw[i] = clampf(lp * 0.58, -0.95, 0.95)
	var wav := _encode_loop(raw, xf)
	_baked_loops[profile] = wav
	return wav


func setup(c: Craft) -> void:
	craft = c
	process_mode = Node.PROCESS_MODE_ALWAYS
	if craft.kind == "heli":
		_profile = "heli"
	elif craft.kind == "plane":
		_profile = "plane_jet" if bool(craft.spec.get("jet", false)) else "plane_prop"
	else:
		_profile = "boat"
	stream = _baked_loop(_profile)
	bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	unit_size = 18.0
	max_distance = 260.0
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	volume_db = -80.0
	if _profile == "boat":
		_hiss_player = AudioStreamPlayer3D.new()
		_hiss_player.stream = _baked_loop("boat_hiss")
		_hiss_player.bus = bus
		_hiss_player.unit_size = unit_size
		_hiss_player.max_distance = max_distance
		_hiss_player.attenuation_model = attenuation_model
		_hiss_player.volume_db = -80.0
		add_child(_hiss_player)


func _process(dt: float) -> void:
	if craft == null or not is_instance_valid(craft):
		return
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(global_position) < 120.0
	var level := _level()
	var want := not get_tree().paused and near and level >= 0.02
	if want:
		_last_level = level
	_gain = move_toward(_gain, 1.0 if want else 0.0, maxf(dt, 0.001) * 8.0)
	if not want and _gain <= 0.0005:
		if playing:
			stop()
		if _hiss_player and _hiss_player.playing:
			_hiss_player.stop()
		_hiss_gain = 0.0
		return
	var eff_level := level if want else _last_level
	var target_pitch := 1.0
	var target_lin := eff_level * _gain
	match _profile:
		"heli":
			target_pitch = lerpf(0.38, 1.18, clampf(eff_level, 0.0, 1.0))
			target_lin *= 0.85
		"plane_jet":
			target_pitch = lerpf(0.75, 1.32, clampf(eff_level, 0.0, 1.0))
			target_lin *= 0.82
		"plane_prop":
			target_pitch = lerpf(0.55, 1.55, clampf(eff_level, 0.0, 1.0))
			target_lin *= 0.80
		_:
			target_pitch = lerpf(0.62, 1.65, clampf(eff_level, 0.0, 1.0))
			target_lin *= 0.78
	if not playing:
		volume_db = -80.0
		pitch_scale = target_pitch
		play()
	pitch_scale = lerpf(pitch_scale, target_pitch, 1.0 - exp(-10.0 * dt))
	volume_db = linear_to_db(maxf(target_lin, 0.0001))
	if _hiss_player != null:
		var hiss := clampf(absf(craft.forward_speed) / 18.0, 0.0, 1.0) if want else 0.0
		_hiss_gain = move_toward(_hiss_gain, hiss, maxf(dt, 0.001) * 5.0)
		if _hiss_gain <= 0.002:
			if _hiss_player.playing:
				_hiss_player.stop()
		else:
			if not _hiss_player.playing:
				_hiss_player.volume_db = -80.0
				_hiss_player.play()
			_hiss_player.pitch_scale = lerpf(0.85, 1.35, _hiss_gain)
			_hiss_player.volume_db = linear_to_db(maxf(_hiss_gain * 0.45 * _gain, 0.0001))


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
