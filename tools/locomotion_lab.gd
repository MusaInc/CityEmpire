extends SceneTree
## WorldState Locomotion Lab: captures gameplay-faithful everyday locomotion
## videos, contact sheets, and biomechanical metrics for both Ade and Jules
## across flat ground, slopes, stairs, kerbs, turns, starts/stops, circles,
## and indoor spaces.
##
## Usage:
##   xvfb-run -a -s "-screen 0 1280x720x24 -nolisten tcp" godot --rendering-method mobile \
##     --resolution 640x480 --fixed-fps 30 -s res://tools/locomotion_lab.gd -- \
##     <out_dir> [--body=a|b|both] [--scenarios=walk,sprint,...] [--metrics-only]

const MotionAudit := preload("res://tools/motion_audit_core.gd")

const ALL_SCENARIOS := [
	"idle", "slow_walk", "walk", "jog", "sprint",
	"start_stop", "turns", "circles", "slope", "stairs", "indoor"
]

var player: Player
var rig: CharacterRig
var cam: Camera3D
var out_dir := ""
var metrics_only := false
var _cam_off := Vector3(0.0, 0.25, 3.6)
var _cam_pos := Vector3.ZERO
var _cam_lerp := 0.28
var _look_y := 0.05


class ScriptDriver:
	extends RefCounted
	var move := Vector3.ZERO
	var jump := false
	var human_steer := true

	func drive(_p, _dt) -> Dictionary:
		var j := jump
		jump = false
		return {"move": move, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": j}


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "/tmp/ws_locomotion_lab"
	var body_arg := "both"
	var scenarios: Array = ALL_SCENARIOS.duplicate()
	for a in args.slice(1):
		if a.begins_with("--body="):
			body_arg = a.substr(7)
		elif a.begins_with("--scenarios="):
			scenarios = Array(a.substr(12).split(","))
		elif a == "--metrics-only":
			metrics_only = true

	DirAccess.make_dir_recursive_absolute(out_dir)
	_build_stage()
	await physics_frame

	var bodies: Array = ["a", "b"] if body_arg == "both" else [body_arg]
	var report := {}
	for body in bodies:
		var label := "ade" if body == "a" else "jules"
		_apply_hero(body)
		await process_frame
		await process_frame
		report[label] = {}
		for sc in scenarios:
			var r: Dictionary = await _run_scenario(label, sc)
			report[label][sc] = r
			print("LOCO %-5s %-11s | slide avg %.3f max %.2f | snap %4.0f pops %3d | sink %.3f float %.3f | joints %2d | bob %.1fmm" % [
				label, sc, r["slide_avg"], r["slide"], r["snap"], r["pops"],
				r["sink"], r["float"], r["joint_bad"], r["bob_mm"]])

	var f := FileAccess.open(out_dir + "/metrics.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("LOCOMOTION_LAB_DONE %s" % out_dir)
	quit()


func _build_stage() -> void:
	var atmo := Atmosphere.new()
	root.add_child(atmo)
	var stage := Node3D.new()
	root.add_child(stage)

	# Flat ground with subtle checker strips so foot-locking / skating is visually unmistakable.
	PrototypeWorld.add_box(stage, Vector3(0, -0.5, 0), Vector3(400, 1, 400), Color(0.42, 0.44, 0.47), false, true)
	for i in range(-30, 31):
		var col := Color(0.32, 0.34, 0.37) if (i % 2 == 0) else Color(0.50, 0.52, 0.55)
		PrototypeWorld.add_box(stage, Vector3(i * 1.0, -0.04, 0.0), Vector3(0.08, 0.085, 80.0), col, false, true)
		PrototypeWorld.add_box(stage, Vector3(0.0, -0.04, i * 1.0), Vector3(80.0, 0.085, 0.08), col, false, true)

	# Sloped street ramp at z = 25 (12 deg up, flat plateau, 12 deg down).
	var slope_len := 10.0
	var slope_ang := deg_to_rad(12.0)
	var rise := slope_len * sin(slope_ang)
	var run := slope_len * cos(slope_ang)
	_add_ramp(stage, Vector3(-6.0 + run * 0.5, rise * 0.5 - 0.1, 25.0), Vector3(slope_len, 0.2, 5.0), slope_ang, Color(0.48, 0.46, 0.43))
	PrototypeWorld.add_box(stage, Vector3(-6.0 + run + 2.5, rise - 0.1, 25.0), Vector3(5.0, 0.2, 5.0), Color(0.48, 0.46, 0.43), false, true)
	_add_ramp(stage, Vector3(-6.0 + run + 5.0 + run * 0.5, rise * 0.5 - 0.1, 25.0), Vector3(slope_len, 0.2, 5.0), -slope_ang, Color(0.48, 0.46, 0.43))

	# Realistic stairs at z = 45: 8 risers of 0.17m height, 0.34m tread, plateau, then 8 steps down.
	var sx := -8.0
	for i in 8:
		var h := 0.17 * (i + 1)
		PrototypeWorld.add_box(stage, Vector3(sx + i * 0.34, h * 0.5, 45.0), Vector3(0.34, h, 3.6), Color(0.54, 0.52, 0.49), false, true)
	var top_h := 0.17 * 8
	var plat_x := sx + 8 * 0.34 + 1.2
	PrototypeWorld.add_box(stage, Vector3(plat_x, top_h * 0.5, 45.0), Vector3(2.4, top_h, 3.6), Color(0.52, 0.50, 0.47), false, true)
	var down_x := plat_x + 1.2 + 0.17
	for i in 8:
		var h := 0.17 * (8 - i)
		PrototypeWorld.add_box(stage, Vector3(down_x + i * 0.34, h * 0.5, 45.0), Vector3(0.34, h, 3.6), Color(0.54, 0.52, 0.49), false, true)

	# Indoor room & doorway at z = -25.
	PrototypeWorld.add_box(stage, Vector3(0.0, 1.5, -28.0), Vector3(8.0, 3.0, 0.3), Color(0.68, 0.66, 0.62), false, true)
	PrototypeWorld.add_box(stage, Vector3(-4.0, 1.5, -25.0), Vector3(0.3, 3.0, 6.0), Color(0.68, 0.66, 0.62), false, true)
	PrototypeWorld.add_box(stage, Vector3(4.0, 1.5, -25.0), Vector3(0.3, 3.0, 6.0), Color(0.68, 0.66, 0.62), false, true)

	player = Player.new()
	player.params = load("res://config/empire_params.tres").duplicate()
	player.swing_enabled = false
	player.everyday = true
	root.add_child(player)

	rig = CharacterRig.new()
	player.add_child(rig)
	rig.set_player(player)

	cam = Camera3D.new()
	cam.fov = 44.0
	cam.far = 500.0
	root.add_child(cam)
	cam.make_current()


func _add_ramp(parent: Node3D, pos: Vector3, sz: Vector3, rot_z: float, col: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.z = rot_z
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = sz
	cs.shape = bx
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	parent.add_child(body)


func _apply_hero(body: String) -> void:
	var sel := HeroLook.DEFAULT.duplicate()
	sel["body"] = body
	if body == "b":
		sel["top"] = "top_fashion_ribcrop"
		sel["trousers"] = "relaxeddenim"
		sel["footwear"] = "streettrainers"
		sel["top_col"] = "#d9cbb9"
		sel["pants_col"] = "#365172"
		sel["shoes"] = "shoes_classic"
	rig.apply_look(HeroLook.build(sel))


func _reset(at: Vector3, face_dir := Vector3.RIGHT, indoors := false) -> ScriptDriver:
	var drv := ScriptDriver.new()
	player.bot = drv
	player.indoors = indoors
	player.respawn(at)
	player.s.velocity = Vector3.ZERO
	rig._prev_vel = Vector3.ZERO
	rig.set_facing(face_dir.normalized())
	return drv


func _run_scenario(label: String, sc: String) -> Dictionary:
	var drv: ScriptDriver
	var secs := 3.0
	var events := {}
	var per_frame_cb: Callable = Callable()
	_cam_lerp = 0.25
	_look_y = 0.02

	match sc:
		"idle":
			drv = _reset(Vector3(0.0, 0.92, 0.0), Vector3.BACK)
			_cam_off = Vector3(0.85, 0.12, 2.35)
			secs = 3.2
		"slow_walk":
			drv = _reset(Vector3(-4.0, 0.92, 0.0), Vector3.RIGHT)
			_cam_off = Vector3(0.0, 0.15, 3.1)
			secs = 3.2
			events = {0.15: func(): drv.move = Vector3.RIGHT * 0.26}
		"walk":
			drv = _reset(Vector3(-6.0, 0.92, 0.0), Vector3.RIGHT)
			_cam_off = Vector3(0.55, 0.18, 3.1)
			secs = 3.2
			events = {0.15: func(): drv.move = Vector3.RIGHT * 0.50}
		"jog":
			drv = _reset(Vector3(-10.0, 0.92, 0.0), Vector3.RIGHT)
			_cam_off = Vector3(0.65, 0.22, 3.4)
			secs = 3.0
			events = {0.15: func(): drv.move = Vector3.RIGHT * 0.78}
		"sprint":
			drv = _reset(Vector3(-15.0, 0.92, 0.0), Vector3.RIGHT)
			_cam_off = Vector3(0.75, 0.24, 3.6)
			secs = 3.0
			events = {0.15: func(): drv.move = Vector3.RIGHT * 1.0}
		"start_stop":
			drv = _reset(Vector3(-8.0, 0.92, 0.0), Vector3.RIGHT)
			_cam_off = Vector3(0.3, 0.18, 3.4)
			secs = 4.6
			events = {
				0.2: func(): drv.move = Vector3.RIGHT * 0.52,
				1.3: func(): drv.move = Vector3.ZERO,
				2.1: func(): drv.move = Vector3.RIGHT * 0.95,
				3.4: func(): drv.move = Vector3.ZERO,
			}
		"turns":
			drv = _reset(Vector3(-6.0, 0.92, 0.0), Vector3.RIGHT)
			_cam_off = Vector3(-1.8, 1.35, 3.2)
			secs = 4.8
			events = {
				0.1: func(): drv.move = Vector3.RIGHT * 0.62,
				1.2: func(): drv.move = Vector3.FORWARD * 0.62,
				2.2: func(): drv.move = Vector3.BACK * 0.85,
				3.5: func(): drv.move = Vector3.LEFT * 0.85,
			}
		"circles":
			drv = _reset(Vector3(0.0, 0.92, 0.0), Vector3.RIGHT)
			_cam_off = Vector3(0.0, 1.85, 3.6)
			secs = 4.0
			per_frame_cb = func(t: float):
				var ang := t * 1.65
				drv.move = Vector3(cos(ang), 0.0, sin(ang)) * 0.55
		"slope":
			drv = _reset(Vector3(-9.0, 0.92, 25.0), Vector3.RIGHT)
			_cam_off = Vector3(0.4, 0.35, 3.8)
			secs = 5.5
			events = {0.1: func(): drv.move = Vector3.RIGHT * 0.55}
		"stairs":
			drv = _reset(Vector3(-10.0, 0.92, 45.0), Vector3.RIGHT)
			_cam_off = Vector3(0.3, 0.45, 3.8)
			secs = 5.2
			events = {0.1: func(): drv.move = Vector3.RIGHT * 0.48}
		"indoor":
			drv = _reset(Vector3(-2.5, 0.92, -25.0), Vector3.RIGHT, true)
			_cam_off = Vector3(-0.4, 0.95, 2.8)
			secs = 3.8
			events = {
				0.2: func(): drv.move = Vector3.RIGHT * 0.35,
				1.3: func(): drv.move = Vector3.FORWARD * 0.30,
				2.3: func(): drv.move = Vector3.LEFT * 0.32,
				3.1: func(): drv.move = Vector3.ZERO,
			}
		_:
			push_error("Unknown scenario: " + sc)
			return {}

	await physics_frame
	await process_frame

	var meter := MotionAudit.Meter.new(rig, player, get_root().get_world_3d().direct_space_state)
	var frame_dir := "%s/%s_%s" % [out_dir, label, sc]
	if not metrics_only:
		DirAccess.make_dir_recursive_absolute(frame_dir)

	var t := 0.0
	var frame_i := 0
	var hip_y_min := INF
	var hip_y_max := -INF
	var dt_step := 1.0 / 30.0
	_cam_pos = player.global_position + _cam_off

	while t < secs:
		for at in events.keys():
			if t >= float(at):
				(events[at] as Callable).call()
				events.erase(at)
		if per_frame_cb.is_valid():
			per_frame_cb.call(t)
		await rig.posed
		var dt: float = player.get_process_delta_time()
		t += dt
		meter.sample(t, dt)
		if t > 0.5:
			var hy: float = (rig.bones["hips"] as Node3D).position.y
			hip_y_min = minf(hip_y_min, hy)
			hip_y_max = maxf(hip_y_max, hy)

		var target := player.global_position + Vector3(0.0, _look_y, 0.0)
		_cam_pos = _cam_pos.lerp(target + _cam_off, _cam_lerp)
		cam.global_position = _cam_pos
		cam.look_at(target, Vector3.UP)

		if not metrics_only:
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("%s/f_%04d.png" % [frame_dir, frame_i])
		frame_i += 1

	var res := meter.result()
	res["bob_mm"] = snappedf((hip_y_max - hip_y_min) * 1000.0 if hip_y_max > hip_y_min else 0.0, 0.1)
	res["frames"] = frame_i
	return res
