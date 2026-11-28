class_name Sfx
extends Node
## Small UI/shop sounds synthesised at start-up (no asset files): till
## beeps, the cash drawer, a pickup thump, a notification chime, door bell.
## Anything else is passed to the game's AudioDirector (CitySwing's wavs).

static var _inst: Sfx
var director: AudioDirector
var _streams := {}
var _pool: Array = []
var _next := 0


func _ready() -> void:
	_inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		add_child(p)
		_pool.append(p)
	_streams["beep"] = _tone([[1850.0, 0.07]], 0.35)
	_streams["cash"] = _tone([[1320.0, 0.05], [0.0, 0.03], [1760.0, 0.05], [0.0, 0.02], [2640.0, 0.18]], 0.3, true)
	_streams["pickup"] = _tone([[140.0, 0.09]], 0.6, false, true)
	_streams["drop"] = _tone([[95.0, 0.12]], 0.6, false, true)
	_streams["chime"] = _tone([[880.0, 0.12], [1318.5, 0.25]], 0.3, true)
	_streams["bell"] = _tone([[2093.0, 0.35]], 0.25, true)
	_streams["error"] = _tone([[220.0, 0.12], [0.0, 0.04], [196.0, 0.16]], 0.3)
	_streams["click"] = _tone([[2400.0, 0.012]], 0.25)
	_streams["elev_tick"] = _tone([[1320.0, 0.025]], 0.16, true)
	_streams["elev_btn"] = _tone([[1760.0, 0.018]], 0.20, true)
	_streams["elev_chime"] = _tone([[1046.5, 0.16], [783.99, 0.34]], 0.24, true)
	_streams["elev_door"] = _elev_door()
	_streams["elev_hum"] = _elev_hum()


static func play(name: String, db := 0.0, pitch := 1.0) -> void:
	if _inst == null:
		return
	if not _inst._streams.has(name):
		if _inst.director:
			_inst.director.play(name, db, pitch)
		return
	var p: AudioStreamPlayer = _inst._pool[_inst._next]
	_inst._next = (_inst._next + 1) % _inst._pool.size()
	p.stream = _inst._streams[name]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


## Notes: [[hz, seconds], …] (0 Hz = rest). `ring` lets each note decay
## like a bell; `thud` is a low noisy knock.
static func _tone(notes: Array, amp: float, ring := false, thud := false) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for nt in notes:
		var hz: float = nt[0]
		var n := int(float(nt[1]) * rate)
		for i in n:
			var t := float(i) / rate
			var env := minf(t / 0.004, 1.0) * (exp(-t * 9.0) if ring else minf((float(n - i) / rate) / 0.01, 1.0))
			var v := 0.0
			if thud:
				env = exp(-t * 28.0)
				v = (sin(TAU * hz * t * (1.0 - t * 2.0)) * 0.8 + rng.randf_range(-0.3, 0.3)) * env
			elif hz > 0.0:
				v = (sin(TAU * hz * t) * 0.75 + sin(TAU * hz * 2.0 * t) * 0.18) * env
			var s := int(clampf(v * amp, -1.0, 1.0) * 32767.0)
			data.append(s & 0xff)
			data.append((s >> 8) & 0xff)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


static func _elev_door() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.52
	var n := int(dur * rate)
	var data := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / rate
		var u := clampf(t / dur, 0.0, 1.0)
		var env := sin(PI * u)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.09)
		lp2 = lerpf(lp2, lp, 0.18)
		var glide := sin(TAU * (128.0 + 24.0 * u) * t) * 0.18
		var latch := exp(-t * 48.0) * sin(TAU * 420.0 * t) * 0.16
		var v := (lp2 * 0.45 + glide) * env * 0.26 + latch
		var s := int(clampf(v, -1.0, 1.0) * 32767.0)
		data.append(s & 0xff)
		data.append((s >> 8) & 0xff)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


static func _elev_hum() -> AudioStreamWAV:
	var rate := 22050
	var dur := 1.05
	var n := int(dur * rate)
	var data := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var air := 0.0
	for i in n:
		var t := float(i) / rate
		var env := minf(t / 0.20, 1.0) * minf((dur - t) / 0.24, 1.0)
		air = lerpf(air, rng.randf_range(-1.0, 1.0), 0.04)
		var motor := sin(TAU * 72.0 * t) * 0.52 + sin(TAU * 144.0 * t) * 0.20 + sin(TAU * 216.0 * t) * 0.06
		var v := (motor + air * 0.18) * env * 0.15
		var s := int(clampf(v, -1.0, 1.0) * 32767.0)
		data.append(s & 0xff)
		data.append((s >> 8) & 0xff)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
