class_name AirTraffic
extends Node3D
## Scripted airliners at Skyport (shared world dressing; no physics, no AI):
## each runs a fixed cycle – approach over the sea, touch down, roll out,
## taxi to its stand, wait, push back, taxi to the runway, take off, climb
## out and away – as a timeline of keyframed segments evaluated from the
## clock. Two planes, offset in time, share the runway. Only animated
## within ACTIVE m of the camera; beyond that they're hidden (cost: two
## MultiMesh-free meshes and a few vector lerps a frame).

const ACTIVE := 3200.0
const AUDIO_RANGE := 450.0
const CYCLE := 300.0      # s for one full arrival + departure

static var _jet_stream: AudioStreamWAV

var world: CityWorld

var _planes: Array = []   # [Node3D, time offset, stand, lights dict, AudioStreamPlayer3D]
var _paths: Array = []    # per plane: [[t0, t1, p0, p1, yaw0, yaw1, kind], ...] in cycle seconds
var _t := float(OS.get_environment("AIR_T")) if OS.has_environment("AIR_T") else 0.0   # (captures: start mid-cycle)


static func _make_jet_stream() -> AudioStreamWAV:
	if _jet_stream != null:
		return _jet_stream
	var rate := 22050
	var samples := int(rate * 1.6)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4077
	var raw := PackedFloat32Array()
	raw.resize(samples)
	var lp := 0.0
	var lp2 := 0.0
	for i in samples:
		var n := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, n, 0.22)
		lp2 = lerpf(lp2, lp, 0.08)
		var ph := float(i) / float(rate)
		var turbine := sin(ph * TAU * 1850.0) * 0.05 + sin(ph * TAU * 925.0) * 0.03
		raw[i] = clampf((lp * 0.42 + lp2 * 0.55 + turbine) * 0.65, -0.95, 0.95)
	# Crossfade tail into head for a seamless loop.
	var xf := 1600
	for i in xf:
		var w := float(i) / float(xf)
		raw[i] = lerpf(raw[samples - xf + i], raw[i], w)
	for i in samples:
		var v := clampi(int(raw[i] * 32767.0), -32768, 32767)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples - xf
	_jet_stream = wav
	return wav


static func _nav_bulb(radius: float, col: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.0
	sm.material = mat
	mi.mesh = sm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _add_nav_lights(node: Node3D) -> Dictionary:
	var nav_l := _nav_bulb(0.32, Color(1.0, 0.08, 0.06), Vector3(-17.25, 5.70, 8.3))
	var nav_r := _nav_bulb(0.32, Color(0.08, 1.0, 0.22), Vector3(17.25, 5.70, 8.3))
	var strobe_l := _nav_bulb(0.36, Color(1.0, 0.98, 0.94), Vector3(-17.35, 5.70, 8.6))
	var strobe_r := _nav_bulb(0.36, Color(1.0, 0.98, 0.94), Vector3(17.35, 5.70, 8.6))
	var strobe_t := _nav_bulb(0.34, Color(1.0, 0.98, 0.94), Vector3(0.0, 5.25, 17.9))
	var beacon := _nav_bulb(0.36, Color(1.0, 0.06, 0.04), Vector3(0.0, 5.95, 2.0))
	var landing := _nav_bulb(0.45, Color(1.0, 0.96, 0.85), Vector3(0.0, 1.5, -13.8))
	for m in [nav_l, nav_r, strobe_l, strobe_r, strobe_t, beacon, landing]:
		node.add_child(m)
	return {"nav": [nav_l, nav_r], "strobes": [strobe_l, strobe_r, strobe_t], "beacon": beacon, "landing": landing}


func setup(P: Dictionary) -> void:
	var rw: Dictionary = P["runway"]
	var a: Vector3 = rw["from"]
	var b: Vector3 = rw["to"]
	var stands: Array = P["stands"]
	var jet_wav := _make_jet_stream()
	for k in 2:
		var stand: Vector3 = (stands[1 + k * 2] as Array)[0]
		var node := CraftModels.build("plane", "liner", {"size": Vector3(34, 9, 36), "jet": true,
			"paint": Color(0.94, 0.94, 0.95), "trim": [Color(0.12, 0.32, 0.6), Color(0.62, 0.14, 0.18)][k]})
		node.scale = Vector3.ONE
		add_child(node)
		var lights := _add_nav_lights(node)
		var au := AudioStreamPlayer3D.new()
		au.stream = jet_wav
		au.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		au.unit_size = 38.0
		au.max_distance = AUDIO_RANGE
		au.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		au.volume_db = -80.0
		node.add_child(au)
		_planes.append([node, k * CYCLE * 0.5, stand, lights, au])
		_paths.append(_timeline(a, b, stand))


## Arrival from the east over the sea (land westbound), departure eastbound
## out over the sea again.
func _timeline(a: Vector3, b: Vector3, stand: Vector3) -> Array:
	var y := a.y
	var east := -PI * 0.5          # (yaw facing +x)
	var north := 0.0
	var tw := Vector3(stand.x, y, 395.0)   # taxiway abeam the stand
	var segs: Array = []
	var t := [0.0]   # (lambdas capture locals by value: keep the clock in an array)
	var add := func(dur: float, p0: Vector3, p1: Vector3, y0: float, y1: float, kind := "taxi") -> void:
		segs.append([t[0], t[0] + dur, p0, p1, y0, y1, kind])
		t[0] += dur
	var west := PI * 0.5
	# Arrive over the open sea from the east, land westbound (never over the
	# city's towers), roll out, turn off onto the taxiway to the stand.
	add.call(40.0, b + Vector3(2600, 180, 0), b + Vector3(60, 14, 0), west, west, "approach")
	add.call(4.0, b + Vector3(60, 14, 0), b + Vector3(-120, 0.02, 0), west, west, "approach")
	add.call(16.0, b + Vector3(-120, 0.02, 0), Vector3(stand.x - 140.0, y + 0.02, a.z), west, west, "rollout")
	add.call(10.0, Vector3(stand.x - 140.0, y + 0.02, a.z), Vector3(stand.x - 140.0, y + 0.02, 395.0), west, north, "taxi")
	add.call(14.0, Vector3(stand.x - 140.0, y + 0.02, 395.0), tw + Vector3(0, 0.02, 0), north, east, "taxi")
	add.call(8.0, tw + Vector3(0, 0.02, 0), stand + Vector3(0, 0.02, 10.0), east, north, "taxi")
	add.call(90.0, stand + Vector3(0, 0.02, 10.0), stand + Vector3(0, 0.02, 10.0), north, north, "parked")   # turnaround
	add.call(10.0, stand + Vector3(0, 0.02, 10.0), tw + Vector3(0, 0.02, 0), north, west, "pushback")        # push back
	add.call(18.0, tw + Vector3(0, 0.02, 0), Vector3(a.x + 40.0, y + 0.02, 395.0), west, west, "taxi")
	add.call(10.0, Vector3(a.x + 40.0, y + 0.02, 395.0), a + Vector3(40, 0.02, 0), west, east, "taxi")
	add.call(26.0, a + Vector3(40, 0.02, 0), a + Vector3(620, 0.02, 0), east, east, "takeoff")              # takeoff roll
	add.call(40.0, a + Vector3(620, 0.02, 0), b + Vector3(2400, 320, -400), east, east, "climb")           # climb out
	return segs


func _process(dt: float) -> void:
	_t += dt
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var paused := get_tree().paused
	var night := world.night_amount if is_instance_valid(world) else 0.0
	for i in _planes.size():
		var pl: Array = _planes[i]
		var node: Node3D = pl[0]
		var lights: Dictionary = pl[3]
		var au: AudioStreamPlayer3D = pl[4]
		var segs: Array = _paths[i]
		var total: float = (segs[segs.size() - 1] as Array)[1]
		var ct := fposmod(_t + float(pl[1]), CYCLE)
		node.visible = ct < total
		if not node.visible:
			if au.playing:
				au.stop()
			continue
		var seg_kind := "taxi"
		for si in segs.size():
			var s: Array = segs[si]
			if ct >= float(s[0]) and ct < float(s[1]):
				seg_kind = String(s[6])
				var u := (ct - float(s[0])) / maxf(float(s[1]) - float(s[0]), 0.001)
				var p0: Vector3 = s[2]
				var p1: Vector3 = s[3]
				var e := u * u * (3.0 - 2.0 * u) if p0.y < 20.0 and p1.y < 20.0 else u
				var p := p0.lerp(p1, e)
				var d := p1 - p0
				var hlen := Vector2(d.x, d.z).length()
				var yaw := float(s[4])
				if seg_kind == "parked":
					yaw = float(s[4])
				elif seg_kind == "pushback":
					# Back out tail-first from stand, then pivot cleanly onto taxiway heading.
					yaw = lerp_angle(float(s[4]), float(s[5]), smoothstep(0.62, 1.0, u))
				elif hlen > 1.0:
					# Align along the segment travel direction so the jet never crabs sideways;
					# smoothly pivot only near segment entry/exit waypoints.
					var seg_yaw := atan2(-d.x, -d.z)
					if u < 0.20:
						yaw = lerp_angle(float(s[4]), seg_yaw, smoothstep(0.0, 0.20, u))
					elif u > 0.80:
						yaw = lerp_angle(seg_yaw, float(s[5]), smoothstep(0.80, 1.0, u))
					else:
						yaw = seg_yaw
				else:
					yaw = lerp_angle(float(s[4]), float(s[5]), smoothstep(0.0, 1.0, u))
				var pitch := clampf(atan2(d.y, hlen + 0.01) * 0.8, -0.12, 0.25)
				node.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), p)
				var gear := node.get_node_or_null("Gear")
				if gear:
					gear.visible = p.y < SkyportIsland.LAND_Y + 25.0
				break
		var dist := node.global_position.distance_to(cam.global_position)
		if dist > ACTIVE:
			node.visible = false
			if au.playing:
				au.stop()
			continue
		# Aviation nav, anti-collision beacon, double-flash wingtip strobes & landing light.
		var phase := fposmod(_t + float(i) * 0.65, 1.4)
		var strobe_on := (phase < 0.07) or (phase > 0.17 and phase < 0.24)
		var beacon_on := fposmod(_t + float(i) * 0.4, 1.1) < 0.16
		var nav_vis := night > 0.15 or seg_kind != "parked"
		for n_mi: MeshInstance3D in lights["nav"]:
			n_mi.visible = nav_vis
		for s_mi: MeshInstance3D in lights["strobes"]:
			s_mi.visible = strobe_on and seg_kind != "parked"
		(lights["beacon"] as MeshInstance3D).visible = beacon_on
		(lights["landing"] as MeshInstance3D).visible = seg_kind in ["approach", "rollout", "takeoff", "climb"]
		# Distance-gated jet engine audio (culled cleanly at 450 m).
		var thrust := 0.0
		match seg_kind:
			"takeoff", "climb":
				thrust = 1.0
			"approach":
				thrust = 0.72
			"rollout":
				thrust = 0.55
			"taxi", "pushback":
				thrust = 0.28
			_:
				thrust = 0.0
		if not paused and dist < AUDIO_RANGE and thrust > 0.01:
			if not au.playing:
				au.play()
			var target_db := lerpf(-22.0, -2.0, thrust)
			au.volume_db = lerpf(au.volume_db, target_db, 1.0 - exp(-dt * 4.0))
			au.pitch_scale = lerpf(0.75, 1.25, thrust)
		elif au.playing:
			au.volume_db = lerpf(au.volume_db, -80.0, 1.0 - exp(-dt * 6.0))
			if au.volume_db < -65.0:
				au.stop()
