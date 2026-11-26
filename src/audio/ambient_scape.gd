class_name AmbientScape
extends Node
## The sound of where you are (2026-11-26 audio pass), on top of
## AudioDirector's city/traffic beds:
##   * neighbourhood beds crossfading with your surroundings – passers-by
##     chatter where the streets are busy, gulls and water by the harbour and
##     the strait, birdsong in the parks; day/night scaled;
##   * open shops near you sound from their doorways (AudioStreamPlayer3D:
##     voices, footsteps, the till, the door chime), up to SHOP_VOICES at once;
##   * a soft room reverb on the SFX bus indoors.
## Loops are synthesised by tools/audio/gen_ambience.py. Re-evaluated a few
## times a second; the emitters are pooled (no per-frame allocation).

const SHOP_VOICES := 3
const SHOP_RANGE := 28.0
const EVERY := 0.35

var game: EmpireGame
var _beds := {}                      # name -> AudioStreamPlayer
var _shop_pool: Array[AudioStreamPlayer3D] = []
var _t := 0.0
var _reverb_idx := -1


func setup(g: EmpireGame) -> void:
	game = g
	for n in ["amb_chatter", "amb_harbour", "amb_park"]:
		var p := AudioStreamPlayer.new()
		p.stream = _loop(n)
		p.bus = "SFX"
		p.volume_db = -60.0
		add_child(p)
		if p.stream:
			p.play(randf() * 4.0)
		_beds[n] = p
	for i in SHOP_VOICES:
		var e := AudioStreamPlayer3D.new()
		e.stream = _loop("amb_shop")
		e.bus = "SFX"
		e.unit_size = 5.0
		e.max_distance = SHOP_RANGE
		e.attenuation_filter_cutoff_hz = 3200.0   # (muffled from out on the street)
		e.volume_db = -8.0
		add_child(e)
		_shop_pool.append(e)
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx >= 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.35
		rv.damping = 0.6
		rv.wet = 0.0
		rv.dry = 1.0
		AudioServer.add_bus_effect(sfx, rv)
		_reverb_idx = AudioServer.get_bus_effect_count(sfx) - 1


static func _loop(n: String) -> AudioStream:
	var path := "res://assets/audio/%s.wav" % n
	if not ResourceLoader.exists(path):
		return null
	return load(path)   # (looped in the import settings: edit/loop_mode=2)


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0 or game == null or game.player == null or game.empire == null:
		return
	_t = EVERY
	var listener := game.vehicle_node().global_position if game.vehicle_node() else game.player.global_position
	var h := game.empire.hour()
	var day := clampf(1.0 - absf(h - 14.0) / 9.0, 0.15, 1.0)
	var indoors: bool = game.player.indoors and game.driving == ""
	var in_car := game.driving != ""
	var muffle := 0.35 if indoors else (0.55 if in_car else 1.0)
	# Surroundings, sampled in a ring round you.
	var water := 0.0
	var green := 0.0
	for k in 8:
		var a := float(k) * TAU / 8.0
		var q := listener + Vector3(cos(a), 0.0, sin(a)) * 45.0
		if game.layout.is_water(q):
			water += 1.0 / 8.0
		if game.layout.is_park(Vector2(q.x, q.z)):
			green += 1.0 / 8.0
	var busy := clampf(1.0 - water - green, 0.0, 1.0) * day
	_bed("amb_chatter", busy * muffle, -14.0)
	_bed("amb_harbour", water * muffle, -12.0)
	_bed("amb_park", green * day * muffle, -13.0)
	# Open shops near you, nearest first.
	var shops: Array = []
	for id in game.interiors:
		var si: ShopInterior = game.interiors[id]
		if si == null or not is_instance_valid(si):
			continue
		var open_now := si.biz.trading(h) if si.biz else (h >= 8.0 and h < 20.0 and si.kind == "shop")
		if not open_now:
			continue
		var door := Premises.door_point(si.unit)
		var d := door.distance_to(listener)
		if d < SHOP_RANGE:
			shops.append([d, door + Vector3.UP * 1.4])
	shops.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in _shop_pool.size():
		var e := _shop_pool[i]
		if i < shops.size() and e.stream:
			e.global_position = shops[i][1]
			if not e.playing:
				e.play(randf() * 6.0)
		elif e.playing:
			e.stop()
	# Room reverb indoors.
	if _reverb_idx >= 0:
		var rv := AudioServer.get_bus_effect(AudioServer.get_bus_index("SFX"), _reverb_idx) as AudioEffectReverb
		if rv:
			rv.wet = move_toward(rv.wet, 0.16 if indoors else 0.0, 0.08)


func _bed(n: String, gain: float, top_db: float) -> void:
	var p: AudioStreamPlayer = _beds.get(n)
	if p == null:
		return
	var want := -60.0 if gain < 0.02 else top_db + linear_to_db(gain)
	p.volume_db = move_toward(p.volume_db, want, 4.0)
