class_name CarAudio
extends Node
## The car you drive, heard (ported from Never Stop's AudioDirector): two
## engine loops (low / high firing) per engine type, pitched and crossfaded
## by rpm and louder under throttle; a gear-change clunk; tyre squeal and
## scrub from wheel slip; wind with speed; crashes by impact strength.
## Silent when you're on foot or the game is paused.

const DIR := "res://assets/audio/"
## Engine by body (vehicles.json "body"/"base") – honoured after spec["engine_sound"].
const ENGINE_OF := {
	"kestrel": "i4", "civ_van": "diesel", "civ_box": "diesel", "mammoth": "diesel", "civ_bus": "diesel",
	"marlin": "v6", "scout": "f6", "brute": "v8", "goliath": "v8", "warden": "v8",
	"vanta": "f6", "halcyon": "v10", "stiletto": "v10",
}

var car: Car
var surface_at: Callable
var _road_surface := "asphalt"
var _surface_time := 0.0
var _compression := 0.0
var _joint_wait := 0.0
var _streams := {}
var _lo: AudioStreamPlayer
var _hi: AudioStreamPlayer
var _loops := {}
var _pool: Array = []
var _pool_i := 0
var _kind := ""
var _exotic := false
var _gear := 1
var _impact_haptic_cooldown := 0.0
var _horn_cooldown := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_lo = _player()
	_hi = _player()
	for k in ["tyre_squeal", "tyre_scrub", "wind", "rolling", "scrape", "wet_spray"]:
		var p := _player()
		var src_name: String = "tyre_scrub" if k == "rolling" else ("rain_loop" if k == "wet_spray" else k)
		p.stream = _loop(src_name)
		p.volume_db = -80.0
		_loops[k] = p
	for i in 6:
		_pool.append(_player())


func _player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(p)
	return p


func _stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var path := DIR + name + ".wav"
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
	return _streams[name]


func _loop(name: String) -> AudioStream:
	var s := _stream(name)
	if s is AudioStreamWAV:
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		return w
	return s


func play(name: String, db := 0.0, pitch := 1.0) -> void:
	var s := _stream(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


## Sound the vehicle horn pitched to the car's class.
func play_horn() -> void:
	if _horn_cooldown > 0.0:
		return
	_horn_cooldown = 0.32
	var pitch := 1.0
	match _kind:
		"diesel":
			pitch = 0.76
		"v8":
			pitch = 0.90
		"v10":
			pitch = 1.15
		"f6":
			pitch = 1.08
		"i4":
			pitch = 1.04
	play("horn", -5.0, pitch * randf_range(0.98, 1.02))


## Play a vehicle door latch / cabin thud (opening = unlatch, closing = solid shut).
func play_door(opening: bool) -> void:
	var heavy := _kind in ["diesel", "v8", "v10"]
	if opening:
		play("gear", -11.0, 1.28 if not heavy else 1.12)
		play("bump", -22.0, 1.32)
	else:
		play("bump", -8.0, 0.72 if heavy else 0.84)
		play("gear", -14.0, 0.94 if heavy else 1.04)


func _resolve_engine_kind(c: Car, model: Dictionary) -> String:
	var candidates: Array[String] = []
	if c != null and c.spec is Dictionary:
		var s_snd := String(c.spec.get("engine_sound", ""))
		if s_snd != "":
			candidates.append(s_snd)
	var m_snd := String(model.get("engine_sound", ""))
	if m_snd != "":
		candidates.append(m_snd)
	var body := String(model.get("body", c.spec.get("body", "") if (c != null and c.spec is Dictionary) else ""))
	if ENGINE_OF.has(body):
		candidates.append(String(ENGINE_OF[body]))
	for cand in candidates:
		if _stream("engine_%s_low" % cand) != null and _stream("engine_%s_high" % cand) != null:
			return cand
	var price := float(model.get("price", 0))
	return "i4" if price < 15000 else ("v6" if price < 60000 else ("v8" if price < 150000 else "v10"))


## Start hearing this car (null: on foot – everything goes quiet).
func set_car(c: Car, model := {}) -> void:
	if car and is_instance_valid(car) and car.impact.is_connected(_on_impact):
		car.impact.disconnect(_on_impact)
	car = c
	_surface_time = 0.0
	_joint_wait = 0.3
	_compression = 0.0
	if c == null:
		for p in [_lo, _hi] + _loops.values():
			(p as AudioStreamPlayer).stop()
		return
	var body := String(model.get("body", c.spec.get("body", "") if c.spec is Dictionary else ""))
	var kind := _resolve_engine_kind(c, model)
	_exotic = body in ["vanta", "halcyon", "stiletto"] or kind == "v10"
	if kind != _kind:
		_kind = kind
		_lo.stream = _loop("engine_%s_low" % kind)
		_hi.stream = _loop("engine_%s_high" % kind)
	_lo.volume_db = -30.0
	_hi.volume_db = -40.0
	_lo.play()
	_hi.play()
	for p in _loops.values():
		var ap := p as AudioStreamPlayer
		if ap.stream != null:
			ap.play()
	c.impact.connect(_on_impact)
	play_door(false)   # (the door shuts, the engine catches)


func _on_impact(strength: float, _at: Vector3, _n: Vector3, _other: Object) -> void:
	if strength >= 5.0 and _impact_haptic_cooldown <= 0.0:
		_impact_haptic_cooldown = 0.25
		Settings.haptic(22, lerpf(0.18, 0.45, smoothstep(5.0, 18.0, strength)))
	if strength > 12.0:
		play("crash_heavy_%d" % (randi() % 3), linear_to_db(clampf(strength / 30.0, 0.5, 1.0)), randf_range(0.9, 1.05))
		if strength > 20.0:
			play("glass", -6.0, randf_range(0.9, 1.1))
	elif strength > 3.0:
		play("crash_light_%d" % (randi() % 3), linear_to_db(clampf(strength / 12.0, 0.25, 1.0)), randf_range(0.9, 1.15))


func _set_loop(k: String, db: float, s: float, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _loops.get(k)
	if p == null or p.stream == null:
		return
	p.volume_db = lerpf(p.volume_db, db, s)
	p.pitch_scale = pitch


func _process(dt: float) -> void:
	_impact_haptic_cooldown = maxf(_impact_haptic_cooldown - dt, 0.0)
	_horn_cooldown = maxf(_horn_cooldown - dt, 0.0)
	if car == null or not is_instance_valid(car):
		return
	var paused := get_tree().paused
	var k := 1.0 - exp(-10.0 * dt)
	var rpm := car.rpm
	var thr := car.throttle
	var hi_mix := smoothstep(0.32 if _exotic else 0.35, 0.82 if _exotic else 0.85, rpm)
	var base := lerpf(-12.0, -4.0, thr) if not paused else -60.0
	var exotic_pitch := 1.12 if _exotic else (0.86 if _kind == "diesel" else 1.0)
	_lo.pitch_scale = (lerpf(0.75, 2.2, rpm) if rpm < 0.7 else lerpf(1.9, 2.4, (rpm - 0.7) / 0.3)) * exotic_pitch
	_hi.pitch_scale = lerpf(0.45, 1.08 if _exotic else 1.05, rpm) * exotic_pitch
	_lo.volume_db = lerpf(_lo.volume_db, base + linear_to_db(maxf(1.0 - hi_mix, 0.02)), k)
	_hi.volume_db = lerpf(_hi.volume_db, base + linear_to_db(maxf(hi_mix, 0.02)), k)
	if car.gear != _gear:
		if car.gear > _gear and thr > 0.5:
			play("gear", -10.0, randf_range(0.95, 1.05))
		_gear = car.gear
	var slip := 0.0
	for i in 4:
		slip = maxf(slip, car.wheel_slip[i])
	var sp := car.speed
	_surface_time -= dt
	if _surface_time <= 0.0 and surface_at.is_valid():
		_road_surface = String(surface_at.call(car.global_position))
		_surface_time = 0.12
	var wet := maxf(CarVisual.visible_wetness, 1.0 if _road_surface == "wet_asphalt" else 0.0)
	var tyre_level := -5.0 if _road_surface == "asphalt" else (0.0 if _road_surface == "wet_asphalt" else 3.0)
	tyre_level += wet * 2.5
	var tyre_pitch := 1.05 if _road_surface == "wet_asphalt" else (0.68 if _road_surface == "grass" else 0.84)
	tyre_pitch += wet * 0.14
	var rolling := smoothstep(1.5, 32.0, sp) * float(car.wheels_on_ground) * 0.25
	_set_loop("rolling", -80.0 if paused or rolling < 0.001 else -25.0 + tyre_level + linear_to_db(rolling),
		k, tyre_pitch + minf(sp, 40.0) * 0.008)
	var spray := wet * smoothstep(5.0, 26.0, sp) * clampf(float(car.wheels_on_ground) * 0.25, 0.0, 1.0)
	if _road_surface == "grass":
		spray = 0.0
	_set_loop("wet_spray", -80.0 if paused or spray < 0.02 else lerpf(-28.0, -10.0, spray),
		k, lerpf(1.30, 1.72, clampf((sp - 5.0) / 35.0, 0.0, 1.0)))
	var comp := maxf(maxf(car.wheel_comp_visual[0], car.wheel_comp_visual[1]),
		maxf(car.wheel_comp_visual[2], car.wheel_comp_visual[3]))
	_joint_wait -= dt
	if not paused and _joint_wait <= 0.0 and car.wheels_on_ground >= 2 and sp > 3.5:
		var jolt := comp - _compression
		if jolt > maxf(0.042, dt * 1.15):
			play("bump", lerpf(-23.0, -11.0, smoothstep(0.04, 0.14, jolt)), 0.66)
			_joint_wait = 0.26
	_compression = comp
	var scr := clampf(car.scraping, 0.0, 1.0)
	_set_loop("scrape", -80.0 if paused or scr < 0.05 else lerpf(-24.0, -7.0, scr),
		k, lerpf(0.85, 1.22, clampf(sp / 30.0, 0.0, 1.0)))
	_set_loop("tyre_squeal", -80.0 if paused or slip < 0.25 or sp < 6.0 else lerpf(-20.0, -6.0, slip), k, lerpf(0.9, 1.1, clampf(sp / 50.0, 0.0, 1.0)))
	_set_loop("tyre_scrub", -80.0 if paused or slip < 0.15 else lerpf(-26.0, -12.0, slip), k)
	_set_loop("wind", -80.0 if paused else lerpf(-40.0, -14.0, clampf(sp / 45.0, 0.0, 1.0)), k)
