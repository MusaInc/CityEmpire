extends Node
## Character review rig: the WorldState hero dressed through the real
## in-game path (HeroLook.build → CharacterRig.apply_look), under the game's
## own atmosphere, on a neutral stage, from FIXED cameras keyed to the
## skeleton (so every milestone is shot identically and comparable).
##
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --rendering-method mobile \
##     --resolution 800x1000 --fixed-fps 30 res://tools/character_lab.tscn -- <outdir> [outfits] [poses]
##
## outfits: comma list of OUTFITS keys (default: all), or catalog for both builds' tops
## poses:   comma list of idle,walk,run,drive,reach,bent,collar (default: all but collar)
## light:   "game" (the game's atmosphere, default) or "neutral" (flat grey
##          studio: soft key from the camera side, strong ambient, so no
##          shadow can hide a defect; files get a __neutral suffix)
##          "city" opens the actual WorldState wardrobe and captures its views.
##          Add --play and --save=<temporary path> to capture a fresh city.
## views: optional comma list, e.g. three_quarter,face,collar,shoes.
## Files: <outdir>/<outfit>__<pose>__<view>.png and stats.json (triangles,
## draw surfaces, visible meshes, frame-time from the renderer).

const OUTFITS := {
	# The baseline in-game outfit (screenshot 2026-11-17): orange shirt, shades.
	"orange_shirt": {"face": "hero_ade", "hair": "hair_crop", "top": "top_shirt", "top_col": "#d9822b",
		"pants_col": "#3d4530", "shoes": "shoes_classic", "head": "head_bare", "eyewear": "face_shades"},
	"tee_cap": {"face": "hero_theo", "hair": "hair_crop", "top": "top_tee", "top_col": "#3f6db3",
		"pants_col": "#c9bc9c", "shoes": "shoes_gum", "head": "head_cap", "eyewear": "face_none"},
	"polo_phones": {"face": "hero_kai", "hair": "hair_fade", "top": "top_polo", "top_col": "#f2f1ec",
		"pants_col": "#1f2d4a", "shoes": "shoes_blackout", "head": "head_phones", "eyewear": "face_none"},
	"blazer": {"face": "hero_malik", "hair": "hair_crop", "top": "top_blazer", "top_col": "#1a1c20",
		"pants_col": "#1a1c20", "shoes": "shoes_blackout", "head": "head_bare", "eyewear": "face_shades"},
	"hoodie": {"face": "hero_ren", "hair": "hair_curls", "top": "top_hoodie", "top_col": "#5d1f2a",
		"pants_col": "#3b3f46", "shoes": "shoes_volt", "head": "head_bare", "eyewear": "face_none"},
	"ade_bare": {"face": "hero_ade", "hair": "hair_natural", "top": "top_jumper", "top_col": "#e8e2d8",
		"pants_col": "#2a2c30", "shoes": "shoes_classic", "head": "head_bare", "eyewear": "face_none"},
	"ade_tee": {"face": "hero_ade", "hair": "hair_natural", "top": "top_tee", "top_col": "#c96f92",
		"pants_col": "#1f2d4a", "shoes": "shoes_classic", "head": "head_bare", "eyewear": "face_none"},
	"rio_skin": {"body": "b", "face": "hero_rio", "hair": "hair_natural", "top": "top_long", "top_col": "#c96f92",
		"pants_col": "#1f2d4a", "shoes": "shoes_classic", "head": "head_bare", "eyewear": "face_none"},
	"rio_bare": {"body": "b", "face": "hero_rio", "hair": "hair_natural", "top": "top_tee", "top_col": "#c96f92",
		"pants_col": "#1f2d4a", "shoes": "shoes_classic", "head": "head_bare", "eyewear": "face_none"},
	"sam_blazer": {"body": "b", "face": "hero_sam", "hair": "hair_bob", "top": "top_blazer", "top_col": "#3b3f46",
		"pants_col": "#25304a", "shoes": "shoes_blackout", "head": "head_bare", "eyewear": "face_none"},
	"noa_hood": {"body": "b", "face": "hero_noa", "hair": "hair_ponytail", "top": "top_hoodie", "top_col": "#c9c4b8",
		"pants_col": "#3b3f46", "shoes": "shoes_gum", "head": "head_bare", "eyewear": "face_none"},
	"sam_bare": {"body": "b", "face": "hero_sam", "hair": "hair_natural", "top": "top_jumper", "top_col": "#2f4a33",
		"pants_col": "#c9bc9c", "shoes": "shoes_gum", "head": "head_bare", "eyewear": "face_none"},
	"a_workshirt": {"face": "hero_theo", "hair": "hair_crop", "top": "top_shirt", "top_col": "#e7e3d9",
		"trousers": "chinos", "pants_col": "#3a414c", "shoes": "shoes_gum"},
	"b_workshirt": {"body": "b", "face": "hero_rio", "hair": "hair_fade", "top": "top_shirt", "top_col": "#e7e3d9",
		"trousers": "cargo", "pants_col": "#3e463c", "shoes": "shoes_blackout"},
	"a_denim": {"face": "hero_malik", "hair": "hair_fade", "top": "top_bomber", "top_col": "#3e584b",
		"trousers": "jeans", "pants_col": "#355a82", "shoes": "shoes_classic"},
	"a_shorts": {"face": "hero_kai", "hair": "hair_buzz", "top": "top_tee", "top_col": "#8a4645",
		"trousers": "shorts", "pants_col": "#596050", "shoes": "shoes_gum"},
	"a_joggers": {"face": "hero_ren", "hair": "hair_pixie", "top": "top_hoodie", "top_col": "#2e4563",
		"trousers": "joggers", "pants_col": "#515561", "shoes": "shoes_classic"},
	"b_denim": {"body": "b", "face": "hero_jules", "hair": "hair_bun", "top": "top_bomber", "top_col": "#b27e52",
		"trousers": "jeans", "pants_col": "#345275", "shoes": "shoes_blackout"},
	"b_shorts": {"body": "b", "face": "hero_remy", "hair": "hair_pixie", "top": "top_polo", "top_col": "#d6c59a",
		"trousers": "shorts", "pants_col": "#2b343e", "shoes": "shoes_classic"},
	"b_joggers": {"body": "b", "face": "hero_noa", "hair": "hair_ponytail", "top": "top_hoodie", "top_col": "#6c697f",
		"trousers": "joggers", "pants_col": "#58555c", "shoes": "shoes_gum"},
	"jumper": {"face": "hero_ade", "hair": "hair_natural", "top": "top_jumper", "top_col": "#2f4a33",
		"pants_col": "#8a7a5a", "shoes": "shoes_classic", "head": "head_beanie", "eyewear": "face_none"},
}

## Views: [right, up, forward] camera offset in the hero's own frame, the
## joint (or point) aimed at, fov. Full-body views aim at the pelvis.
const CATALOG_COLORS := ["#c96f92", "#3f6db3", "#d9822b", "#2f4a33", "#5d1f2a", "#3b3f46", "#c9c4b8", "#426355"]

const FULL := {
	"front": [Vector3(0, 0.05, 3.9), "pelvis", 30.0],
	"three_quarter": [Vector3(2.6, 0.25, 2.9), "pelvis", 30.0],
	"side": [Vector3(3.9, 0.05, 0), "pelvis", 30.0],
	"rear": [Vector3(0, 0.15, -3.9), "pelvis", 30.0],
}
const CLOSE := {
	"face": [Vector3(0.18, 0.04, 0.95), "face", 24.0],
	"face_side": [Vector3(0.95, 0.04, 0.12), "face", 24.0],
	"face_34": [Vector3(0.62, 0.06, 0.72), "face", 24.0],
	"collar": [Vector3(0.12, 0.1, 0.9), "collar", 30.0],
	"chest": [Vector3(0.0, 0.0, 1.25), "chest_mid", 32.0],
	"shoulder": [Vector3(0.75, 0.15, 0.55), "sh_r", 32.0],
	"cuff": [Vector3(0.55, 0.05, 0.45), "wr_r", 28.0],
	"back_collar": [Vector3(0.1, 0.12, -0.9), "collar", 30.0],
	"brows": [Vector3(0.06, 0.06, 0.55), "brow", 24.0],
	"brows_34": [Vector3(0.38, 0.05, 0.42), "brow", 24.0],
	"collar_34": [Vector3(0.45, 0.12, 0.65), "collar", 30.0],
	"collar_side": [Vector3(0.8, 0.08, 0.05), "collar", 30.0],
	"hem_back": [Vector3(0.2, 0.1, -1.0), "hem", 32.0],
	"hem_front": [Vector3(0.25, 0.1, 1.0), "hem", 32.0],
	"lower": [Vector3(0.12, 0.04, 1.58), "lower", 33.0],
	"shoes": [Vector3(0.44, 0.25, 0.77), "feet", 31.0],
	"hair_back": [Vector3(0.39, 0.13, -0.75), "face", 27.0],
}
const POSE_VIEWS := {
	"idle": ["front", "three_quarter", "side", "rear", "face", "face_side", "collar", "chest", "shoulder", "cuff", "back_collar", "hem_back", "hem_front", "lower", "shoes", "hair_back"],
	"collar": ["collar", "collar_34", "collar_side", "back_collar", "chest", "shoulder"],
	"head": ["brows", "brows_34", "face", "face_side"],
	"portrait": ["face", "face_side", "face_34"],
	"walk": ["three_quarter", "side"],
	"run": ["three_quarter", "side"],
	"walk_pass": ["front", "side"],
	"run_pass": ["front", "side"],
	"drive": ["three_quarter", "side", "shoulder"],
	"reach": ["front", "three_quarter", "shoulder"],
	"bent": ["front", "three_quarter", "shoulder", "cuff"],
}

@onready var root := get_tree().root
var player: Player
var rig: CharacterRig
var cam: Camera3D
var out := ""
var stats := {}
var neutral := false
var key: DirectionalLight3D
var view_filter := PackedStringArray()


class Bot:
	extends RefCounted
	var move := Vector3.ZERO
	var human_steer := true
	func drive(_p, _dt) -> Dictionary:
		return {"move": move, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "art/character_review/scratch"
	var outfits: Array = Array(args[1].split(",")) if args.size() > 1 and args[1] != "all" else OUTFITS.keys()
	if outfits == ["catalog"]:
		outfits.clear()
		for body in ["a", "b"]:
			for top in HeroLook.TOPS:
				outfits.append(body + "_" + top[0])
	var poses: Array = Array(args[2].split(",")) if args.size() > 2 and args[2] != "all" else POSE_VIEWS.keys().filter(func(k): return k != "collar" and k != "head" and k != "portrait")
	neutral = args.size() > 3 and args[3] == "neutral"
	if args.size() > 4:
		view_filter = args[4].split(",")
	DirAccess.make_dir_recursive_absolute(out)
	if args.size() > 3 and args[3] == "city":
		await _city_review(outfits)
		return
	if neutral:
		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.55, 0.56, 0.58)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.82, 0.82, 0.84)
		env.ambient_light_energy = 0.9
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		we.environment = env
		root.add_child(we)
		key = DirectionalLight3D.new()
		key.light_energy = 0.75
		key.shadow_enabled = true
		root.add_child(key)
	else:
		var atmo := Atmosphere.new()
		root.add_child(atmo)
	var stage := Node3D.new()
	root.add_child(stage)
	PrototypeWorld.add_box(stage, Vector3(0, -0.5, 0), Vector3(400, 1, 400), Color(0.42, 0.43, 0.45), false, true)
	# A soft, distant backdrop so silhouettes read (same for every milestone).
	PrototypeWorld.add_box(stage, Vector3(0, 20, -60), Vector3(120, 40, 2), Color(0.62, 0.64, 0.67))
	PrototypeWorld.add_box(stage, Vector3(0, 20, 60), Vector3(120, 40, 2), Color(0.62, 0.64, 0.67))
	player = Player.new()
	player.params = load("res://config/empire_params.tres")
	player.swing_enabled = false
	player.everyday = true
	root.add_child(player)
	rig = CharacterRig.new()
	player.add_child(rig)
	rig.set_player(player)
	cam = Camera3D.new()
	cam.near = 0.02
	root.add_child(cam)
	cam.make_current()
	await get_tree().physics_frame
	for o: String in outfits:
		rig.apply_look(HeroLook.build(_look(o)))
		for p: String in poses:
			await _pose(o, p)
	if not stats.is_empty():  # (pose sets without idle, e.g. the neutral collar pass, keep the idle stats)
		var f := FileAccess.open(out + "/stats.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(stats, "  "))
		f.close()
	print("CHARACTER_LAB done ", out)
	get_tree().quit()


func _look(o: String) -> Dictionary:
	var l: Dictionary = HeroLook.DEFAULT.duplicate()
	if o.get_slice("_", 1) == "top":
		l["body"] = o.left(1)
		l["face"] = "hero_rio" if l["body"] == "b" else "hero_ade"
		l["top"] = o.substr(2)
		for i in HeroLook.TOPS.size():
			if HeroLook.TOPS[i][0] == l["top"]:
				l["top_col"] = CATALOG_COLORS[i]
				break
		return l
	for k in OUTFITS[o]:
		l[k] = OUTFITS[o][k]
	return l


func _city_review(outfits: Array) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as EmpireGame
	root.add_child(game)
	if game.state == "title":
		game._play()
	game.ui.close_panel(true)
	for i in 15:
		await get_tree().physics_frame
	game.ui.open_style()
	for o: String in outfits:
		game.ui._style_tab = "clothes" if o.begins_with("a_") or o.begins_with("b_") else "you"
		game.ui._style_set(_look(o))
		for view in [["portrait", true, 0.24], ["outfit", false, -0.22], ["rear", false, PI - 0.3]]:
			if not view_filter.is_empty() and not view[0] in view_filter:
				continue
			game.ui._style_portrait = view[1]
			game.ui._style_orbit = view[2]
			game.ui._style_frame()
			game.ui._update_style_zoom()
			for i in 2:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s__wardrobe_%s.png" % [out, o, view[0]])
	game.ui._close_style()
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/street.png")
	print("CHARACTER_LAB city done ", out)
	get_tree().quit()


func _freeze(on: bool) -> void:
	var m := Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	player.process_mode = m
	rig.process_mode = m


func _pose(o: String, p: String) -> void:
	RenderingServer.render_loop_enabled = false
	_freeze(false)
	var bot := Bot.new()
	player.bot = bot
	player.respawn(Vector3(0, 1.0, 0))
	player.s.velocity = Vector3.ZERO
	rig.set_facing(Vector3.FORWARD)
	match p:
		"walk", "run", "walk_pass", "run_pass":
			bot.move = Vector3.FORWARD * (0.24 if p.begins_with("walk") else 0.76)
			# Settle into the stride, then stop on a passing-contact frame
			# (one foot well ahead): the most legible stride pose.
			for i in 75:
				await get_tree().process_frame
			var best := -1.0
			for i in 40:
				await get_tree().process_frame
				var j := rig.joint_positions()
				var spread: float = absf((j["an_l"] - j["an_r"]).dot(rig._facing))
				if p.ends_with("_pass"):
					if spread < 0.10:
						break
				elif spread > best * 0.97 and i > 20:
					break
				best = maxf(best, spread)
		_:
			for i in 50:
				await get_tree().process_frame
	_freeze(true)
	if p in ["drive", "reach", "bent"]:
		_set_pose(p)
	RenderingServer.render_loop_enabled = true
	await get_tree().process_frame
	var views: Array = POSE_VIEWS[p]
	for v: String in views:
		if not view_filter.is_empty() and v not in view_filter:
			continue
		_aim(v)
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s__%s__%s%s.png" % [out, o, p, v, "__neutral" if neutral else ""])
	if p == "idle":
		stats[o] = _measure()
	player.bot = null


## Static test poses (pivot rotations, as the gameplay animation sets them).
func _set_pose(p: String) -> void:
	var q := {}
	for b in CharacterRig.BONES:
		q[b] = Quaternion.IDENTITY
	match p:
		"drive":  # seated at a wheel: thighs level, shins down, hands at 10-and-2
			for sd in ["l", "r"]:
				var sx := -1.0 if sd == "l" else 1.0
				q["thigh_" + sd] = CharacterRig._rx(deg_to_rad(88.0)) * CharacterRig._rz(sx * deg_to_rad(6.0))
				q["shin_" + sd] = CharacterRig._rx(deg_to_rad(-80.0))
				q["upper_arm_" + sd] = CharacterRig._rx(deg_to_rad(42.0)) * CharacterRig._rz(sx * deg_to_rad(12.0))
				q["forearm_" + sd] = CharacterRig._rx(deg_to_rad(48.0))
			q["spine"] = CharacterRig._rx(deg_to_rad(-6.0))
			rig.bones["hips"].position = CharacterRig.BONES["hips"][1] - Vector3(0, 0.9 + 0.42, 0)
		"reach":  # left arm straight out to the side, right arm reaching forward
			q["upper_arm_l"] = CharacterRig._rz(deg_to_rad(-88.0))
			q["upper_arm_r"] = CharacterRig._rx(deg_to_rad(92.0)) * CharacterRig._rz(deg_to_rad(8.0))
			q["chest"] = CharacterRig._ry(deg_to_rad(-6.0))
		"bent":  # elbows hard bent: left hand to the shoulder, right hand raised (phone / wave)
			q["upper_arm_l"] = CharacterRig._rx(deg_to_rad(25.0)) * CharacterRig._rz(deg_to_rad(-14.0))
			q["forearm_l"] = CharacterRig._rx(deg_to_rad(130.0))
			q["upper_arm_r"] = CharacterRig._rz(deg_to_rad(75.0))
			q["forearm_r"] = CharacterRig._rz(deg_to_rad(105.0))
	for b in q:
		(rig.bones[b] as Node3D).quaternion = q[b]
	rig._sync_skeleton()


func _aim(v: String) -> void:
	var spec: Array = FULL[v] if FULL.has(v) else CLOSE[v]
	var j := rig.joint_positions()
	var fwd: Vector3 = rig._facing
	fwd.y = 0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var target: Vector3
	match spec[1]:
		"face":
			target = (j["neck"] as Vector3).lerp(j["head"], 0.5) + fwd * 0.05
		"collar":
			target = (j["neck"] as Vector3) + Vector3(0, -0.03, 0)
		"chest_mid":
			target = (j["chest"] as Vector3).lerp(j["neck"], 0.45)
		"brow":
			target = (j["neck"] as Vector3).lerp(j["head"], 0.62) + fwd * 0.07
		"hem":
			target = (j["pelvis"] as Vector3) + Vector3(0, -0.06, 0)
		"lower":
			target = (j["pelvis"] as Vector3).lerp((j["an_l"] as Vector3).lerp(j["an_r"], 0.5), 0.50)
		"feet":
			target = (j["an_l"] as Vector3).lerp(j["an_r"], 0.5) + fwd * 0.08
		"pelvis":
			# Full-body views frame the whole figure: aim at mid-height.
			target = Vector3((j["pelvis"] as Vector3).x, player.global_position.y, (j["pelvis"] as Vector3).z)
		_:
			target = j[spec[1]]
	var off: Vector3 = spec[0]
	cam.fov = spec[2]
	cam.global_position = target + right * off.x + Vector3.UP * off.y + fwd * off.z
	cam.look_at(target, Vector3.UP)
	if key:
		# key light from just above and beside the camera: everything the camera sees is lit
		var from := (cam.global_position - target).normalized() + Vector3.UP * 0.6 + right * 0.25
		key.look_at_from_position(target + from, target, Vector3.UP)


func _measure() -> Dictionary:
	var tris := 0
	var surfaces := 0
	var meshes := []
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		meshes.append(String(m.name))
		for s in m.mesh.get_surface_count():
			surfaces += 1
			var a := m.mesh.surface_get_arrays(s)
			var idx = a[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return {"triangles": tris, "draw_surfaces": surfaces, "meshes": meshes,
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1)}
