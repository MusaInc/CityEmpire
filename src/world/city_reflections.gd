class_name CityReflections
extends Node3D
## Real city reflections for the Mobile renderer (it has no SSR): reflection
## probes that follow you, so glass facades, car paint, chrome, wet streets
## and puddles mirror the actual buildings, skyline, sky and lights round you
## (reflection overhaul 2026-11-26; first version 2026-11-21).
##
##  * Street layer: a box-projected probe (parallax-corrected: the canyon of
##    facades either side of you lines up in the reflection) ~180 m across,
##    recentred every STREET_STEP m.
##  * City layer (High only): a 900 m probe for everything beyond, recentred
##    every CITY_STEP m.
##
## No pop-in: each layer has two probes. The spare captures at intensity 0 –
## the Mobile renderer skips a probe with no intensity, so a capture in
## progress is never seen – and swaps in only when it's done; captures are
## close together in space and time (moves of tens of metres, every
## LIGHT_EVERY s as the sun and weather change, or at once on a big change
## of light), so one capture differs little from the next. (Mobile takes
## the first probe that covers a pixel in full: an intensity cross-fade would
## dim the reflection half-way, so the swap is instant by design.)
##
## Cost: a probe renders its six faces over six frames at the atlas size
## (project.godot: 256 px, 8 slots), and only when recaptured – never every
## frame. Off on Low (the shaders' fake reflections carry it, refl_probe = 0).

const STREET_STEP := 36.0
const CITY_STEP := 240.0
const LIGHT_EVERY := 40.0
const STREET_SIZE := Vector3(180.0, 90.0, 180.0)
const CITY_SIZE := Vector3(900.0, 320.0, 900.0)
const CAPTURE_FRAMES := 9     # six faces + filtering, with a margin

var view_fn := Callable()   # () -> Vector3: where you are (camera or vehicle)
## () -> float: 0..1 how far inside a room the camera is (outdoor probes rest).
var indoor_fn := Callable()
## Lighting signature: () -> Vector3 (night, rain, sun height) – a big change
## recaptures at once.
var light_fn := Callable()
var quality := 2
var on := true

var _layers: Array = []
var _ball: MeshInstance3D
var _age := 0.0
var _room_t := 0.0
# per layer: {size, step, box, probes[2], live, last, pending, frames, t}


func _ready() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings:
		quality = clampi(int(settings.quality), 0, 2)
	on = quality >= 1
	_layers.append(_make_layer("Street", STREET_SIZE, STREET_STEP, true, 24.0, 1.0))
	if quality >= 2:
		_layers.append(_make_layer("City", CITY_SIZE, CITY_STEP, false, 0.0, 0.92))
	RenderingServer.global_shader_parameter_set("refl_probe", 1.0 if on else 0.0)
	if "--probe-sphere" in OS.get_cmdline_user_args():
		# (Debug: a chrome ball in front of the camera that shows exactly
		# what the probes hold.)
		_ball = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.2
		sm.height = 2.4
		_ball.mesh = sm
		var m := StandardMaterial3D.new()
		m.metallic = 1.0
		m.roughness = 0.0
		_ball.material_override = m
		add_child(_ball)
	if not on:
		for l in _layers:
			for p: ReflectionProbe in l["probes"]:
				p.visible = false


func _make_layer(nm: String, sz: Vector3, step: float, box: bool, blend: float, intensity: float) -> Dictionary:
	var probes: Array = []
	for i in 2:
		var p := ReflectionProbe.new()
		p.name = "%s%d" % [nm, i]
		p.update_mode = ReflectionProbe.UPDATE_ONCE
		p.size = sz
		p.max_distance = sz.x * 0.75
		p.box_projection = box
		p.blend_distance = blend
		p.interior = false
		p.enable_shadows = false
		p.intensity = 0.0
		p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		# (Distant buildings are big; the probe needn't see street clutter.)
		p.mesh_lod_threshold = 6.0 if box else 12.0
		# (Not the full-screen look quad – it painted over every cube face –
		# nor the rain streaks round the camera or the water surface.)
		p.cull_mask = 0xFFFFF & ~WaterMirror.LAYER
		add_child(p)
		probes.append(p)
	return {"size": sz, "step": step, "box": box, "probes": probes, "live": -1, "pending": -1,
		"frames": 0, "last": Vector3(INF, 0, INF), "t": 0.0, "light": Vector3.ZERO, "intensity": intensity}


func _process(dt: float) -> void:
	_room_t -= dt
	if _room_t <= 0.0:
		_room_t = 0.5
		_budget_rooms()
	if not on or not view_fn.is_valid():
		return
	_age += dt
	var p: Vector3 = view_fn.call()
	if _ball:
		var c := get_viewport().get_camera_3d()
		if c:
			_ball.global_position = c.global_position - c.global_basis.z * 7.0 - c.global_basis.y * 1.0
	var indoor: float = float(indoor_fn.call()) if indoor_fn.is_valid() else 0.0
	var lsig: Vector3 = light_fn.call() if light_fn.is_valid() else Vector3.ZERO
	for l: Dictionary in _layers:
		var probes: Array = l["probes"]
		# A capture in flight: swap it in once its faces are done.
		if int(l["pending"]) >= 0:
			l["frames"] = int(l["frames"]) + 1
			if int(l["frames"]) >= CAPTURE_FRAMES:
				var np: ReflectionProbe = probes[int(l["pending"])]
				np.intensity = float(l["intensity"])
				if int(l["live"]) >= 0:
					(probes[int(l["live"])] as ReflectionProbe).intensity = 0.0
				l["live"] = l["pending"]
				l["pending"] = -1
			continue
		if indoor > 0.6:
			continue   # (outdoor probes rest while you're inside a room)
		l["t"] = float(l["t"]) + dt
		var moved := Vector2(p.x - l["last"].x, p.z - l["last"].z).length() > float(l["step"]) or absf(p.y - l["last"].y) > float(l["step"]) * 0.5
		# (Soon after loading the city is still streaming in: a few quick
		# recaptures so the first, emptier one doesn't stay up.)
		var every := LIGHT_EVERY if _age > 20.0 else 4.0
		var relit := float(l["t"]) > every or (lsig - (l["light"] as Vector3)).length() > 0.18
		if moved or relit or int(l["live"]) < 0:
			_capture(l, p, lsig)


func _capture(l: Dictionary, p: Vector3, lsig: Vector3) -> void:
	var probes: Array = l["probes"]
	var i := 0 if int(l["live"]) != 0 else 1
	var pr: ReflectionProbe = probes[i]
	pr.intensity = 0.0
	var sz: Vector3 = l["size"]
	if l["box"]:
		# Box centred a little above you; captured from eye height (origin
		# offset), so facades and the street line up with box projection.
		pr.global_position = Vector3(p.x, p.y + sz.y * 0.5 - 12.0, p.z)
		pr.origin_offset = Vector3(0.0, -sz.y * 0.5 + 14.0 + randf() * 0.01, 0.0)
	else:
		pr.global_position = Vector3(p.x, p.y + 40.0, p.z)
		pr.origin_offset = Vector3(0.0, -30.0 + randf() * 0.01, 0.0)
	# (Moving or changing an UPDATE_ONCE probe is what makes it render again.)
	l["pending"] = i
	l["frames"] = 0
	l["last"] = p
	l["t"] = 0.0
	l["light"] = lsig


## Room probe budget. Every shop, home, venue and lobby has its own small
## probe (InteriorKit.room_probe), and Godot captures probes one at a time,
## a few frames each, from one 12-slot atlas (project.godot). Left alone,
## twenty-odd of them queued ahead of the street probe after every move –
## the street reflection only arrived seconds later – and evicted each
## other's atlas slots. Only rooms near the camera matter (their lights
## fade out by ~64 m anyway), so at most ROOM_MAX of them, nearest first,
## within ROOM_RANGE (with a margin so they don't flicker at the edge).
const ROOM_MAX := 8
const ROOM_RANGE := 70.0
const ROOM_MARGIN := 10.0


func _budget_rooms() -> void:
	var c := get_viewport().get_camera_3d()
	if c == null:
		return
	var at := c.global_position
	var near: Array = []
	for zone: Node in get_tree().get_nodes_in_group("interior_lighting_zones"):
		var rp := zone.get_node_or_null("InteriorBounce") as ReflectionProbe
		if rp == null or not (zone as Node3D).is_visible_in_tree():
			continue
		var d := rp.global_position.distance_to(at)
		var reach := ROOM_RANGE + (ROOM_MARGIN if rp.visible else 0.0)
		if d < reach:
			near.append([d, rp])
		else:
			rp.visible = false
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in near.size():
		(near[i][1] as ReflectionProbe).visible = i < ROOM_MAX
