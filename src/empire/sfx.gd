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
